namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic

func SourceOwnerScope(sources: string[], fileNames: string[], structs: List<ColumnarStructInput>, activeSourceFileId: int): ColumnarBindingScopeFacts {
    scope := ColumnarBindingScopeFacts.Create(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), ExternalEmptyEnums(), structs, ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    scope.PrepareExternalTypeBindings(null)
    return scope.ForSourceFile(activeSourceFileId)
}

func SourceOwnerEmptyStructs(): List<ColumnarStructInput> {
    return new List<ColumnarStructInput>()
}

func SourceOwnerAssertResolved(scope: ColumnarBindingScopeFacts, enclosingTypeName: string, rootName: string, ownerName: string, expectedExactName: string) {
    exactName := ""
    blocked := true
    assert scope.TryResolveSourceStaticOwner(enclosingTypeName, new string[](0), rootName, ownerName, out exactName, out blocked)

    assert !blocked
    assert exactName == expectedExactName
}

func SourceOwnerAssertBlocked(scope: ColumnarBindingScopeFacts, enclosingTypeName: string, rootName: string, ownerName: string, visibleTypeParameters: string[]) {
    exactName := ""
    blocked := false
    assert !scope.TryResolveSourceStaticOwner(enclosingTypeName, visibleTypeParameters, rootName, ownerName, out exactName, out blocked)

    assert blocked
    assert exactName.Length == 0
}

func SourceOwnerAssertNotSource(scope: ColumnarBindingScopeFacts, rootName: string, ownerName: string) {
    exactName := ""
    blocked := true
    assert !scope.TryResolveSourceStaticOwner("", new string[](0), rootName, ownerName, out exactName, out blocked)

    assert !blocked
    assert exactName.Length == 0
}

func SourceOwnerOneFieldStruct(name: string, fieldName: string): ColumnarStructInput {
    fieldNames := new string[](1)
    fieldNames[0] = fieldName
    return ExternalStruct(name, fieldNames, new string[](0), new List<ColumnarFunctionInput>(), null, true)
}

test "source static owner scope resolves active and current-namespace types exactly" {
    sameFileSources := new string[](1)
    sameFileNames := new string[](1)
    sameFileSources[0] = "namespace Demo\nclass Owner {}\nclass Caller { Owner: string }\n"
    sameFileNames[0] = "same-file.nl"
    sameFileStructs := SourceOwnerEmptyStructs()
    sameFileStructs.Add(SourceOwnerOneFieldStruct("Demo.Caller", "Owner"))
    sameFileScope := SourceOwnerScope(sameFileSources, sameFileNames, sameFileStructs, 0)

    // Scope.Types binds the same-file type before the enclosing member tier.
    SourceOwnerAssertResolved(sameFileScope, "Demo.Caller", "Owner", "Owner", "Demo.Owner")

    currentSources := new string[](2)
    currentNames := new string[](2)
    currentSources[0] = "namespace Demo\nprivate class Owner {}\n"
    currentSources[1] = "namespace Demo\nclass Caller {}\n"
    currentNames[0] = "owner.nl"
    currentNames[1] = "caller.nl"
    currentScope := SourceOwnerScope(currentSources, currentNames, SourceOwnerEmptyStructs(), 1)

    // A current-namespace project type remains visible without being exported.
    SourceOwnerAssertResolved(currentScope, "", "Owner", "Owner", "Demo.Owner")
}

test "source static owner scope honors namespace import order and export visibility" {
    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nclass Owner {}\n"
    sources[1] = "namespace Right\nclass Owner {}\n"
    sources[2] = "namespace Caller\nimport Right\nimport Left\n"
    fileNames[0] = "left.nl"
    fileNames[1] = "right.nl"
    fileNames[2] = "caller.nl"

    ordered := SourceOwnerScope(sources, fileNames, SourceOwnerEmptyStructs(), 2)

    SourceOwnerAssertResolved(ordered, "", "Owner", "Owner", "Right.Owner")

    sources[1] = "namespace Right\nprivate class Owner {}\n"
    exported := SourceOwnerScope(sources, fileNames, SourceOwnerEmptyStructs(), 2)

    SourceOwnerAssertResolved(exported, "", "Owner", "Owner", "Left.Owner")
}

test "source static owner scope retains exact unaliased file-import identity" {
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace Caller\nimport \"models.nl\"\n"
    sources[1] = "namespace Models\nclass Owner {}\n"
    fileNames[0] = "source-owner-files/main.nl"
    fileNames[1] = "source-owner-files/models.nl"
    scope := SourceOwnerScope(sources, fileNames, SourceOwnerEmptyStructs(), 0)

    SourceOwnerAssertResolved(scope, "", "Owner", "Owner", "Models.Owner")
}

test "source static owner scope fails closed for file-import collisions and missing imports" {
    collisionSources := new string[](3)
    collisionNames := new string[](3)
    collisionSources[0] = "import \"left.nl\"\nimport \"right.nl\"\n"
    collisionSources[1] = "namespace Left\nclass Owner {}\n"
    collisionSources[2] = "namespace Right\nclass Owner {}\n"
    collisionNames[0] = "source-owner-collision/main.nl"
    collisionNames[1] = "source-owner-collision/left.nl"
    collisionNames[2] = "source-owner-collision/right.nl"
    collisionScope := SourceOwnerScope(collisionSources, collisionNames, SourceOwnerEmptyStructs(), 0)

    SourceOwnerAssertBlocked(collisionScope, "", "Owner", "Owner", new string[](0))

    missingSources := new string[](1)
    missingNames := new string[](1)
    missingSources[0] = "import \"missing.nl\"\n"
    missingNames[0] = "source-owner-missing/main.nl"
    missingScope := SourceOwnerScope(missingSources, missingNames, SourceOwnerEmptyStructs(), 0)

    SourceOwnerAssertBlocked(missingScope, "", "Math", "Math", new string[](0))
}

test "source static owner scope resolves source aliases before import aliases" {
    aliasSources := new string[](1)
    aliasNames := new string[](1)
    aliasSources[0] = "namespace Demo\nclass Owner {}\ntype Alias = Owner\n"
    aliasNames[0] = "alias.nl"
    aliasScope := SourceOwnerScope(aliasSources, aliasNames, SourceOwnerEmptyStructs(), 0)

    SourceOwnerAssertResolved(aliasScope, "", "Alias", "Alias", "Demo.Owner")

    runtimeAliasSources := new string[](1)
    runtimeAliasNames := new string[](1)
    runtimeAliasSources[0] = "type Alias = System.Math\n"
    runtimeAliasNames[0] = "runtime-alias.nl"
    runtimeAliasScope := SourceOwnerScope(runtimeAliasSources, runtimeAliasNames, SourceOwnerEmptyStructs(), 0)

    SourceOwnerAssertNotSource(runtimeAliasScope, "Alias", "Alias")

    importAliasSources := new string[](2)
    importAliasNames := new string[](2)
    importAliasSources[0] = "namespace Demo\nclass Owner {}\n"
    importAliasSources[1] = "import Demo as Lib\n"
    importAliasNames[0] = "demo.nl"
    importAliasNames[1] = "caller.nl"
    importAliasScope := SourceOwnerScope(importAliasSources, importAliasNames, SourceOwnerEmptyStructs(), 1)

    SourceOwnerAssertBlocked(importAliasScope, "", "Lib", "Lib.Owner", new string[](0))
}

test "source static owner scope fences qualified source names and unrelated short ambiguity" {
    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nclass Owner {}\n"
    sources[1] = "namespace Right\nclass Owner {}\n"
    sources[2] = "namespace Caller\nimport System\n"
    fileNames[0] = "left.nl"
    fileNames[1] = "right.nl"
    fileNames[2] = "caller.nl"
    scope := SourceOwnerScope(sources, fileNames, SourceOwnerEmptyStructs(), 2)

    SourceOwnerAssertBlocked(scope, "", "Left", "Left.Owner", new string[](0))

    SourceOwnerAssertNotSource(scope, "Owner", "Owner")
}

test "source static owner scope respects type-parameter and enclosing-member shadows" {
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace Demo\nclass Caller { Owner: string }\n"
    sources[1] = "namespace Demo\nclass Owner {}\n"
    fileNames[0] = "caller.nl"
    fileNames[1] = "owner.nl"
    structs := SourceOwnerEmptyStructs()
    structs.Add(SourceOwnerOneFieldStruct("Demo.Caller", "Owner"))
    scope := SourceOwnerScope(sources, fileNames, structs, 0)

    SourceOwnerAssertBlocked(scope, "Demo.Caller", "Owner", "Owner", new string[](0))

    visible := new string[](1)
    visible[0] = "Owner"
    SourceOwnerAssertBlocked(scope, "", "Owner", "Owner", visible)
}

test "direct-call planner selects the exact semantic source owner" {
    owner := SourceCallDefinition("Demo.Owner", true)
    parameters := AdversarialDirectCallOneType(typeof(int))
    _selected := SourceCallPublicStatic(owner, "Run", parameters, typeof(int))

    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace Demo\nclass Owner {}\n"
    sources[1] = "namespace Demo\nclass Caller {}\n"
    fileNames[0] = "owner.nl"
    fileNames[1] = "caller.nl"
    scope := SourceOwnerScope(sources, fileNames, SourceOwnerEmptyStructs(), 1)

    tree := DirectCallQualifiedTree("Owner", "Run", DirectCallOneText("7"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    tree.Nodes.SetBindingContext(scope, "Demo.Caller", new string[](0), new string[](0))

    plan := DirectCallPlan(tree, DirectCallSingleDefinitionBindings(owner))

    methodIndex := plan.OperandIndices[plan.OperationCount - 1]
    assert plan.Methods[methodIndex].get_Name() == "Run"
    assert plan.MethodDeclaringTypes[methodIndex].FullName == "Demo.Owner"
}

test "direct-call planner resolves source aliases to exact definitions" {
    owner := SourceCallDefinition("Demo.Owner", true)
    parameters := AdversarialDirectCallOneType(typeof(int))
    _selected := SourceCallPublicStatic(owner, "Run", parameters, typeof(int))

    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "namespace Demo\nclass Owner {}\ntype Alias = Owner\n"
    fileNames[0] = "alias-owner.nl"
    scope := SourceOwnerScope(sources, fileNames, SourceOwnerEmptyStructs(), 0)

    tree := DirectCallQualifiedTree("Alias", "Run", DirectCallOneText("8"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    tree.Nodes.SetBindingContext(scope, "", new string[](0), new string[](0))

    plan := DirectCallPlan(tree, DirectCallSingleDefinitionBindings(owner))

    methodIndex := plan.OperandIndices[plan.OperationCount - 1]
    assert plan.Methods[methodIndex].get_Name() == "Run"
    assert plan.MethodDeclaringTypes[methodIndex].FullName == "Demo.Owner"
}

test "direct-call planner defers file-import alias call-style owners as whole subtrees" {
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "import \"ids.nl\" as Ids\n"
    sources[1] = "package ids\ntype UserId = newtype int\n"
    fileNames[0] = "source-owner-alias/main.nl"
    fileNames[1] = "source-owner-alias/ids.nl"
    scope := SourceOwnerScope(sources, fileNames, SourceOwnerEmptyStructs(), 0)

    tree := DirectCallQualifiedTree("Ids", "UserId", DirectCallOneText("42"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))

    tree.Nodes.SetBindingContext(scope, "", new string[](0), new string[](0))

    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacyWholeSubtreePlanning := false
    DirectCallRejected(tree, ColumnarRangePlannerEmptyBindings(), out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacyWholeSubtreePlanning
}

test "direct-call planner ignores unrelated duplicate source shorts for runtime owners" {
    left := SourceCallDefinition("Left.Math", true)
    right := SourceCallDefinition("Right.Math", true)
    definitions := new ColumnarStructDef[](2)
    definitions[0] = left
    definitions[1] = right

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nclass Math {}\n"
    sources[1] = "namespace Right\nclass Math {}\n"
    sources[2] = "namespace Caller\nimport System\n"
    fileNames[0] = "left.nl"
    fileNames[1] = "right.nl"
    fileNames[2] = "caller.nl"
    scope := SourceOwnerScope(sources, fileNames, SourceOwnerEmptyStructs(), 2)

    tree := DirectCallQualifiedTree("Math", "Abs", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    tree.Nodes.SetBindingContext(scope, "", new string[](0), new string[](0))

    bindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(bindings, "value", 0, typeof(int))
    plan := DirectCallPlan(tree, bindings)

    methodIndex := plan.OperandIndices[plan.OperationCount - 1]
    assert plan.MethodDeclaringTypes[methodIndex].FullName == "System.Math"
    assert plan.Methods[methodIndex].get_Name() == "Abs"
}

test "direct-call planner does not reinterpret value and callable roots as source types" {
    owner := SourceCallDefinition("Owner", true)
    SourceCallPublicStatic(owner, "Run", AdversarialDirectCallOneType(typeof(int)), typeof(int))

    tree := DirectCallQualifiedTree("Owner", "Run", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    ExternalStampScope(tree, "class Owner {}\n")

    valueBindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(valueBindings, "Owner", 0, owner.Builder)

    ColumnarRangePlannerAddParameter(valueBindings, "value", 1, typeof(int))

    valueOwnership := ColumnarDirectCallOwnership.OwnedRejected
    valueLegacy := false
    DirectCallRejected(tree, valueBindings, out valueOwnership, out valueLegacy)

    assert valueOwnership == ColumnarDirectCallOwnership.NotOwned
    assert valueLegacy

    callableBindings := ExternalBindings(null, null, null, ExternalNameSet("Owner"), null)

    callableBindings.SourceTypeDefinitions = SourceCallDefinitions(owner)
    ColumnarRangePlannerAddParameter(callableBindings, "value", 0, typeof(int))

    callableOwnership := ColumnarDirectCallOwnership.OwnedRejected
    callableLegacy := false
    DirectCallRejected(tree, callableBindings, out callableOwnership, out callableLegacy)

    assert callableOwnership == ColumnarDirectCallOwnership.NotOwned
    assert callableLegacy
}

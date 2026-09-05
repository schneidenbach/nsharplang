namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

class ColumnarInstanceMemberByRefProbe {
    static func SourceStruct(out _value: ColumnarBoundIdentifierCurrentStructProbe): bool {
        throw new InvalidOperationException("Signature-only byref probe.")
    }

    static func RuntimeReference(out _value: Version): bool {
        throw new InvalidOperationException("Signature-only byref probe.")
    }

    static func RuntimeValue(out _value: DateTime): bool {
        throw new InvalidOperationException("Signature-only byref probe.")
    }
}

class ColumnarInstanceMemberPrivateGetterProbe {
    value: int

    constructor(value: int) {
        this.value = value
    }

    func HiddenDelegate(): object {
        callback: Func<int> = () => value
        return callback
    }
}

func InstanceMemberTree(receiverName: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), receiverName)

    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))

    return builder.Build(root)
}

func InstanceStringLiteralMemberTree(literalText: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.StringLiteralExpression(), literalText)

    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))

    return builder.Build(root)
}

func InstanceTypeOfMemberTree(typeName: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    typeNode := builder.AddLeaf(0, typeName)
    builder.AddToken(")")
    receiver := builder.AddNode(ColumnarExpressionNodeKind.TypeOfExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(typeNode))

    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))

    return builder.Build(root)
}

func InstanceNestedMemberTree(ownerName: string, receiverMember: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), ownerName)

    builder.AddToken(".")
    receiverMemberStart := builder.AddToken(receiverMember)
    receiver := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), receiverMemberStart, receiverMember.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(owner))

    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))

    return builder.Build(root)
}

func InstanceIndexerTree(receiverName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), receiverName)
    builder.AddToken("[")
    index := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    builder.AddToken("]")
    root := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(receiver, index))
    return builder.Build(root)
}

func InstanceIndexerMemberTree(receiverName: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), receiverName)
    builder.AddToken("[")
    index := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    builder.AddToken("]")
    indexAccess := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(receiver, index))
    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(indexAccess))
    return builder.Build(root)
}

// A closed List<T> parameter over the given source-type element, plus its live source definition.
func InstanceSourceListBindings(parameterName: string, element: ColumnarStructDef): ColumnarFragmentBindings {
    definitions := new ColumnarStructDef[](1)
    definitions[0] = element
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceTypeDefinitions = definitions
    elementType: Type = element.Builder
    typeArguments := new Type[](1)
    typeArguments[0] = elementType
    listType := typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(typeArguments)
    ColumnarRangePlannerAddParameter(bindings, parameterName, 0, listType)
    return bindings
}

func InstanceCallReceiverTree(memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    callee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "factory")
    builder.AddToken("(")
    builder.AddToken(")")
    // Parser expression kind 9 is CallExpression; this slice intentionally leaves calls unowned.
    receiver := builder.AddNode(9, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(callee))
    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))
    return builder.Build(root)
}

func InstanceMemberFromEndTree(receiverName: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), receiverName)

    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    member := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))

    caretStart := builder.AddToken("^")
    root := builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression(), caretStart, 1, 0, builder.Source.Length, ColumnarRangePlannerChildren1(member))

    return builder.Build(root)
}

func InstanceMemberPlan(tree: ColumnarRangePlannerTestTree, bindings: ColumnarFragmentBindings): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    if ColumnarInstanceMemberPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
        throw new InvalidOperationException("Expected instance-member planner ownership.")
    }

    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func InstanceClassBindings(name: string, ordinal: int): ColumnarFragmentBindings {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, name, ordinal, typeof(ColumnarBoundIdentifierCurrentClassProbe))

    bindings.CurrentInstance = BoundCurrentFacts(typeof(ColumnarBoundIdentifierCurrentClassProbe), true)

    return bindings
}

func InstanceStructBindings(name: string, ordinal: int): ColumnarFragmentBindings {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, name, ordinal, typeof(ColumnarBoundIdentifierCurrentStructProbe))

    bindings.CurrentInstance = BoundCurrentFacts(typeof(ColumnarBoundIdentifierCurrentStructProbe), false)

    return bindings
}

func InstanceByRefType(methodName: string): Type {
    method := typeof(ColumnarInstanceMemberByRefProbe).GetMethod(methodName)
    if method == null {
        throw new InvalidOperationException("By-reference instance-member probe method was not found.")
    }

    parameters := method.GetParameters()
    if parameters.Length != 1 {
        throw new InvalidOperationException("By-reference instance-member probe signature is invalid.")
    }

    parameterType := parameters[0].get_ParameterType()
    if !parameterType.get_IsByRef() {
        throw new InvalidOperationException("By-reference instance-member probe did not expose a managed reference.")
    }

    return parameterType
}

func InstanceFacadeAssertTerminal(tree: ColumnarRangePlannerTestTree, receiverType: Type, expectedSuccess: bool, expectedResultType: Type) {
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    parameterOrdinals["receiver"] = 0
    parameterTypes["receiver"] = receiverType
    locals := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    enums := new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
    sourceDefinitions := new ColumnarStructDef[](0)
    tupleNames := new Dictionary<string, string[]>(StringComparer.Ordinal)
    emptyNames := new string[](0)

    typePlan := new ColumnarCodePlan()
    typeOwned := false
    _typeLegacyWholeSubtreePlanning := false
    typeResult := typeof(object)
    typeSuccess := ColumnarRangeIndexPlanner.TryGetTypeFromFacts(tree.Nodes, tree.Source, tree.Root, parameterOrdinals, parameterTypes, locals, enums, ColumnarRangePlannerEmptyLiftedFacts(), null, null, null, sourceDefinitions, new ColumnarUnionDef[](0), tupleNames, emptyNames, emptyNames, emptyNames, typePlan, out typeOwned, out _typeLegacyWholeSubtreePlanning, out typeResult)

    assert typeOwned
    assert typeSuccess == expectedSuccess
    if expectedSuccess {
        assert typeResult == expectedResultType
        ColumnarCodePlanExecutor.Validate(typePlan)
    } else {
        ColumnarRangePlannerAssertEmptyRollback(typePlan)
    }

    parameterTypesForMethod := new Type[](1)
    parameterTypesForMethod[0] = receiverType
    dynamicMethod := BoundDynamicMethod("InstanceFacadeTerminal", expectedResultType, parameterTypesForMethod)

    emitPlan := new ColumnarCodePlan()
    emitOwned := false
    _emitLegacyWholeSubtreePlanning := false
    emitResult := typeof(object)
    emitSuccess := ColumnarRangeIndexPlanner.TryEmitFromFacts(tree.Nodes, tree.Source, tree.Root, parameterOrdinals, parameterTypes, locals, enums, ColumnarRangePlannerEmptyLiftedFacts(), null, null, null, sourceDefinitions, new ColumnarUnionDef[](0), tupleNames, emptyNames, emptyNames, emptyNames, emitPlan, dynamicMethod.GetILGenerator(), out emitOwned, out _emitLegacyWholeSubtreePlanning, out emitResult)

    assert emitOwned
    assert emitSuccess == expectedSuccess
    if expectedSuccess {
        assert emitResult == expectedResultType
        assert emitPlan.Lifecycle == ColumnarCodePlanLifecycle.Consumed
    } else {
        ColumnarRangePlannerAssertEmptyRollback(emitPlan)
    }
}

test "instance member planner owns exact reference and value fields and properties" {
    classField := InstanceMemberPlan(InstanceMemberTree("item", "Field"), InstanceClassBindings("item", 3))

    assert classField.ResultType == typeof(int)
    assert classField.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert classField.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
    assert classField.FieldUsesDeclaredSignature[0]
    assert !classField.ArgumentIsAddress[0]

    classProperty := InstanceMemberPlan(InstanceMemberTree("item", "Value"), InstanceClassBindings("item", 4))

    assert classProperty.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert classProperty.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
    assert classProperty.MethodUsesDeclaredSignature[0]

    structField := InstanceMemberPlan(InstanceMemberTree("item", "Field"), InstanceStructBindings("item", 5))

    assert structField.OpCodeValues[0] == ColumnarCodePlanContract.Ldarga()
    assert structField.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
    assert !structField.ArgumentIsAddress[0]

    structProperty := InstanceMemberPlan(InstanceMemberTree("item", "Value"), InstanceStructBindings("item", 6))

    assert structProperty.OpCodeValues[0] == ColumnarCodePlanContract.Ldarga()
    assert structProperty.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert !structProperty.ArgumentIsAddress[0]
}

test "instance member planner maps open and closed multilevel generic base fields and properties" {
    baseBuilder := TypeOfCreateBuilder(
        "InstanceMappedBase",
        "ColumnarInstanceMemberTests.InstanceMappedBase",
        2
    )
    baseType: Type = baseBuilder
    baseDefinition := new ColumnarStructDef(
        baseBuilder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        "InstanceMappedBase"
    )
    baseArguments := baseBuilder.GetGenericArguments()
    assert baseArguments.Length == 2
    fixedField := ConstructionDefinePublicField(
        baseBuilder,
        "Fixed",
        baseArguments[0]
    )
    baseDefinition.Fields["Fixed"] = fixedField
    reorderedProperty := ColumnarPropertyDef.Define(
        baseBuilder,
        "get_Reordered",
        (MethodAttributes)646,
        baseArguments[1],
        "set_Reordered",
        (MethodAttributes)646
    )
    baseDefinition.Properties["Reordered"] = reorderedProperty

    middleBuilder := TypeOfCreateBuilder(
        "InstanceMappedMiddle",
        "ColumnarInstanceMemberTests.InstanceMappedMiddle",
        1
    )
    middleType: Type = middleBuilder
    middleDefinition := new ColumnarStructDef(
        middleBuilder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        "InstanceMappedMiddle"
    )
    middleArguments := middleBuilder.GetGenericArguments()
    assert middleArguments.Length == 1
    openBaseArguments := new Type[](2)
    openBaseArguments[0] = typeof(string)
    openBaseArguments[1] = middleArguments[0]
    openBase := baseType.MakeGenericType(openBaseArguments)
    ConstructionSetParent(middleBuilder, openBase)
    middleDefinition.BaseDef = baseDefinition
    middleDefinition.ExactBaseType = openBase

    derivedBuilder := TypeOfCreateBuilder(
        "InstanceMappedDerived",
        "ColumnarInstanceMemberTests.InstanceMappedDerived",
        2
    )
    derivedType: Type = derivedBuilder
    derivedDefinition := new ColumnarStructDef(
        derivedBuilder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        "InstanceMappedDerived"
    )
    derivedArguments := derivedBuilder.GetGenericArguments()
    assert derivedArguments.Length == 2
    openMiddleArguments := new Type[](1)
    openMiddleArguments[0] = derivedArguments[1]
    openMiddle := middleType.MakeGenericType(openMiddleArguments)
    ConstructionSetParent(derivedBuilder, openMiddle)
    derivedDefinition.BaseDef = middleDefinition
    derivedDefinition.ExactBaseType = openMiddle

    definitions := new ColumnarStructDef[](3)
    definitions[0] = baseDefinition
    definitions[1] = middleDefinition
    definitions[2] = derivedDefinition

    openDerived := derivedType.MakeGenericType(derivedArguments)
    openBindings := ColumnarRangePlannerEmptyBindings()
    openBindings.SourceTypeDefinitions = definitions
    ColumnarRangePlannerAddParameter(
        openBindings,
        "item",
        0,
        openDerived
    )
    expectedOpenBaseArguments := new Type[](2)
    expectedOpenBaseArguments[0] = typeof(string)
    expectedOpenBaseArguments[1] = derivedArguments[1]
    expectedOpenBase := baseType.MakeGenericType(expectedOpenBaseArguments)

    openField := InstanceMemberPlan(
        InstanceMemberTree("item", "Fixed"),
        openBindings
    )
    assert openField.ResultType == typeof(string)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        openField.FieldDeclaringTypes[0],
        expectedOpenBase
    )
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        openField.Fields[0].get_DeclaringType(),
        expectedOpenBase
    )

    openProperty := InstanceMemberPlan(
        InstanceMemberTree("item", "Reordered"),
        openBindings
    )
    assert openProperty.ResultType == derivedArguments[1]
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        openProperty.MethodDeclaringTypes[0],
        expectedOpenBase
    )
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        openProperty.Methods[0].get_DeclaringType(),
        expectedOpenBase
    )

    closedDerivedArguments := new Type[](2)
    closedDerivedArguments[0] = typeof(int)
    closedDerivedArguments[1] = typeof(long)
    closedDerived := derivedType.MakeGenericType(closedDerivedArguments)
    closedBindings := ColumnarRangePlannerEmptyBindings()
    closedBindings.SourceTypeDefinitions = definitions
    ColumnarRangePlannerAddParameter(
        closedBindings,
        "item",
        0,
        closedDerived
    )
    closedBaseArguments := new Type[](2)
    closedBaseArguments[0] = typeof(string)
    closedBaseArguments[1] = typeof(long)
    closedBase := baseType.MakeGenericType(closedBaseArguments)

    closedField := InstanceMemberPlan(
        InstanceMemberTree("item", "Fixed"),
        closedBindings
    )
    assert closedField.ResultType == typeof(string)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        closedField.FieldDeclaringTypes[0],
        closedBase
    )
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        closedField.Fields[0].get_DeclaringType(),
        closedBase
    )

    closedProperty := InstanceMemberPlan(
        InstanceMemberTree("item", "Reordered"),
        closedBindings
    )
    assert closedProperty.ResultType == typeof(long)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        closedProperty.MethodDeclaringTypes[0],
        closedBase
    )
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        closedProperty.Methods[0].get_DeclaringType(),
        closedBase
    )

    leafBuilder := TypeOfCreateBuilder(
        "InstanceMappedLeaf",
        "ColumnarInstanceMemberTests.InstanceMappedLeaf",
        0
    )
    leafType: Type = leafBuilder
    ConstructionSetParent(leafBuilder, closedBase)
    leafDefinition := new ColumnarStructDef(
        leafBuilder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        "InstanceMappedLeaf"
    )
    leafDefinition.BaseDef = baseDefinition
    leafDefinition.ExactBaseType = closedBase
    leafDefinitions := new ColumnarStructDef[](2)
    leafDefinitions[0] = baseDefinition
    leafDefinitions[1] = leafDefinition
    leafBindings := ColumnarRangePlannerEmptyBindings()
    leafBindings.SourceTypeDefinitions = leafDefinitions
    ColumnarRangePlannerAddParameter(
        leafBindings,
        "item",
        0,
        leafType
    )

    leafField := InstanceMemberPlan(
        InstanceMemberTree("item", "Fixed"),
        leafBindings
    )
    assert leafField.ResultType == typeof(string)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        leafField.FieldDeclaringTypes[0],
        closedBase
    )

    leafProperty := InstanceMemberPlan(
        InstanceMemberTree("item", "Reordered"),
        leafBindings
    )
    assert leafProperty.ResultType == typeof(long)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        leafProperty.MethodDeclaringTypes[0],
        closedBase
    )

    assert !ColumnarInstanceMemberPlanner.ExactTypeOwnsDefinition(
        middleType,
        middleDefinition
    )
    assert ColumnarInstanceMemberPlanner.ExactTypeOwnsDefinition(
        openMiddle,
        middleDefinition
    )

    rawBuilder := TypeOfCreateBuilder(
        "InstanceRawBaseLeaf",
        "ColumnarInstanceMemberTests.InstanceRawBaseLeaf",
        0
    )
    rawType: Type = rawBuilder
    ConstructionSetParent(rawBuilder, middleType)
    rawDefinition := new ColumnarStructDef(
        rawBuilder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        "InstanceRawBaseLeaf"
    )
    rawDefinition.BaseDef = middleDefinition
    rawDefinition.ExactBaseType = middleType
    rawDefinitions := new ColumnarStructDef[](3)
    rawDefinitions[0] = baseDefinition
    rawDefinitions[1] = middleDefinition
    rawDefinitions[2] = rawDefinition
    rawBindings := ColumnarRangePlannerEmptyBindings()
    rawBindings.SourceTypeDefinitions = rawDefinitions
    ColumnarRangePlannerAddParameter(
        rawBindings,
        "item",
        0,
        rawType
    )
    rawTree := InstanceMemberTree("item", "Fixed")
    rawPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarInstanceMemberPlanner.Plan(
            rawTree.Nodes,
            rawTree.Source,
            rawTree.Root,
            rawBindings,
            rawPlan
        )
    }
    ColumnarRangePlannerAssertEmptyRollback(rawPlan)

    mismatchedMiddleArguments := new Type[](1)
    mismatchedMiddleArguments[0] = derivedArguments[0]
    derivedDefinition.ExactBaseType = middleType.MakeGenericType(mismatchedMiddleArguments)
    corruptPlan := new ColumnarCodePlan()
    corruptTree := InstanceMemberTree("item", "Fixed")
    assert throws InvalidOperationException {
        ColumnarInstanceMemberPlanner.Plan(
            corruptTree.Nodes,
            corruptTree.Source,
            corruptTree.Root,
            closedBindings,
            corruptPlan
        )
    }
    ColumnarRangePlannerAssertEmptyRollback(corruptPlan)
    derivedDefinition.ExactBaseType = openMiddle

    shadowField := ConstructionDefinePublicField(
        derivedBuilder,
        "Fixed",
        typeof(int)
    )
    derivedDefinition.Fields["Fixed"] = shadowField
    shadowTree := InstanceMemberTree("item", "Fixed")
    shadowPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarInstanceMemberPlanner.Plan(
            shadowTree.Nodes,
            shadowTree.Source,
            shadowTree.Root,
            closedBindings,
            shadowPlan
        )
    }
    ColumnarRangePlannerAssertEmptyRollback(shadowPlan)
}

test "instance member planner owns scalar literal receivers" {
    bindings := ColumnarRangePlannerEmptyBindings()

    tree := InstanceStringLiteralMemberTree("\"abc\"", "Length")
    assert ColumnarInstanceMemberPlanner.ClaimsRoot(tree.Nodes, tree.Source, tree.Root, bindings)
    plan := InstanceMemberPlan(tree, bindings)
    assert plan.ResultType == typeof(int)
    assert plan.FragmentCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
    assert ExecutorRunV3ScalarPlan(plan, typeof(int)) == "3"

    interpolated := InstanceStringLiteralMemberTree("$\"abc\"", "Length")
    assert ColumnarInstanceMemberPlanner.ClaimsRoot(interpolated.Nodes, interpolated.Source, interpolated.Root, bindings)

    interpolatedPlan := InstanceMemberPlan(interpolated, bindings)
    assert interpolatedPlan.FragmentCount == 2
    assert interpolatedPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert interpolatedPlan.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
    assert ExecutorRunV3ScalarPlan(interpolatedPlan, typeof(int)) == "3"

    hole := InstanceStringLiteralMemberTree("$\"{value}\"", "Length")
    assert !ColumnarInstanceMemberPlanner.ClaimsRoot(hole.Nodes, hole.Source, hole.Root, bindings)

    holePlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(hole.Nodes, hole.Source, hole.Root, bindings, holePlan) == ColumnarFragmentPlanStatus.NotOwned

    ColumnarRangePlannerAssertEmptyRollback(holePlan)
}

test "instance member planner owns exact SZ-array Length reads" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "values", 0, typeof(byte[]))
    tree := InstanceMemberTree("values", "Length")

    assert ColumnarInstanceMemberPlanner.ClaimsRoot(tree.Nodes, tree.Source, tree.Root, bindings)

    plan := InstanceMemberPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldlen()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.ConvI4()

    rejected := InstanceMemberTree("values", "LongLength")
    assert ColumnarInstanceMemberPlanner.ClaimsRoot(rejected.Nodes, rejected.Source, rejected.Root, bindings)

    rejectedPlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(rejected.Nodes, rejected.Source, rejected.Root, bindings, rejectedPlan) == ColumnarFragmentPlanStatus.NotOwned

    ColumnarRangePlannerAssertEmptyRollback(rejectedPlan)
}

test "instance member planner owns typeof receivers and exact Type properties" {
    bindings := ColumnarRangePlannerEmptyBindings()
    tree := InstanceTypeOfMemberTree("string", "Name")

    assert ColumnarInstanceMemberPlanner.ClaimsRoot(tree.Nodes, tree.Source, tree.Root, bindings)

    plan := InstanceMemberPlan(tree, bindings)
    assert plan.ResultType == typeof(string)
    assert plan.FragmentCount == 2
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldtoken()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Callvirt()
    assert ExecutorRunV3ScalarPlan(plan, typeof(string)) == "String"

    rejected := InstanceTypeOfMemberTree("string", "AssemblyQualifiedName")
    assert ColumnarInstanceMemberPlanner.ClaimsRoot(rejected.Nodes, rejected.Source, rejected.Root, bindings)

    rejectedPlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(rejected.Nodes, rejected.Source, rejected.Root, bindings, rejectedPlan) == ColumnarFragmentPlanStatus.NotOwned

    ColumnarRangePlannerAssertEmptyRollback(rejectedPlan)
}

test "instance member planner preserves local storage and runtime value spill forms" {
    sourceLocalBindings := ColumnarRangePlannerEmptyBindings()
    sourceLocalBindings.Locals["item"] = ExternalProbeLocal(typeof(ColumnarBoundIdentifierCurrentStructProbe))

    sourceLocalBindings.CurrentInstance = BoundCurrentFacts(typeof(ColumnarBoundIdentifierCurrentStructProbe), false)

    sourceLocal := InstanceMemberPlan(InstanceMemberTree("item", "Value"), sourceLocalBindings)

    assert sourceLocal.OpCodeValues[0] == ColumnarCodePlanContract.Ldloca()
    assert sourceLocal.OpCodeValues[1] == ColumnarCodePlanContract.Call()

    runtimeBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(runtimeBindings, "instant", 0, typeof(DateTime))

    runtimeValue := InstanceMemberPlan(InstanceMemberTree("instant", "Year"), runtimeBindings)

    assert runtimeValue.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert runtimeValue.OpCodeValues[1] == ColumnarCodePlanContract.Stloc()
    assert runtimeValue.OpCodeValues[2] == ColumnarCodePlanContract.Ldloca()
    assert runtimeValue.OpCodeValues[3] == ColumnarCodePlanContract.Call()
}

test "instance member planner owns inherited runtime properties and tuple names" {
    inheritedBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(inheritedBindings, "error", 0, typeof(ArgumentException))

    inherited := InstanceMemberPlan(InstanceMemberTree("error", "Message"), inheritedBindings)

    assert inherited.ResultType == typeof(string)
    assert inherited.MethodDeclaringTypes[0] == typeof(Exception)
    assert inherited.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()

    tupleBindings := ColumnarRangePlannerEmptyBindings()
    tupleType := typeof(ValueTuple<int, string>)
    ColumnarRangePlannerAddParameter(tupleBindings, "pair", 1, tupleType)
    tupleNames := new string[](2)
    tupleNames[0] = "number"
    tupleNames[1] = "text"
    tupleBindings.TupleNames["pair"] = tupleNames
    tuple := InstanceMemberPlan(InstanceMemberTree("pair", "number"), tupleBindings)

    assert tuple.ResultType == typeof(int)
    assert tuple.Fields[0].get_DeclaringType() == tupleType
    assert tuple.OpCodeValues[3] == ColumnarCodePlanContract.Ldfld()
}

test "instance member planner terminally declines missing static and non-allowlisted members" {
    missingTree := InstanceMemberTree("version", "Missing")
    missingBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(missingBindings, "version", 0, typeof(Version))

    assert ColumnarInstanceMemberPlanner.ClaimsRoot(missingTree.Nodes, missingTree.Source, missingTree.Root, missingBindings)

    missingPlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(missingTree.Nodes, missingTree.Source, missingTree.Root, missingBindings, missingPlan) == ColumnarFragmentPlanStatus.NotOwned

    ColumnarRangePlannerAssertEmptyRollback(missingPlan)

    staticTree := InstanceMemberTree("instant", "UtcNow")
    staticBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(staticBindings, "instant", 0, typeof(DateTime))

    assert ColumnarInstanceMemberPlanner.ClaimsRoot(staticTree.Nodes, staticTree.Source, staticTree.Root, staticBindings)

    staticPlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(staticTree.Nodes, staticTree.Source, staticTree.Root, staticBindings, staticPlan) == ColumnarFragmentPlanStatus.NotOwned

    ColumnarRangePlannerAssertEmptyRollback(staticPlan)

    hiddenTree := InstanceMemberTree("type", "AssemblyQualifiedName")
    hiddenBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(hiddenBindings, "type", 0, typeof(Type))
    assert ColumnarInstanceMemberPlanner.ClaimsRoot(hiddenTree.Nodes, hiddenTree.Source, hiddenTree.Root, hiddenBindings)

    hiddenPlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(hiddenTree.Nodes, hiddenTree.Source, hiddenTree.Root, hiddenBindings, hiddenPlan) == ColumnarFragmentPlanStatus.NotOwned

    ColumnarRangePlannerAssertEmptyRollback(hiddenPlan)
}

test "instance member planner rejects corrupt and shadowed facts atomically" {
    corruptBindings := InstanceClassBindings("item", 0)
    corruptFacts := corruptBindings.CurrentInstance
    if corruptFacts == null {
        throw new InvalidOperationException("Current instance facts were not configured.")
    }

    staticField := typeof(string).GetField("Empty")
    if staticField == null {
        throw new InvalidOperationException("String.Empty field was not found.")
    }

    corruptFacts.Fields["Broken"] = staticField
    corruptTree := InstanceMemberTree("item", "Broken")
    corruptPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarInstanceMemberPlanner.Plan(corruptTree.Nodes, corruptTree.Source, corruptTree.Root, corruptBindings, corruptPlan)
    }

    ColumnarRangePlannerAssertEmptyRollback(corruptPlan)

    arityBindings := InstanceClassBindings("item", 0)
    identityParameters := new Type[](1)
    identityParameters[0] = typeof(int)
    wrongGetter := typeof(ColumnarBoundIdentifierCurrentClassProbe).GetMethod("Identity", identityParameters)

    if wrongGetter == null {
        throw new InvalidOperationException("Identity probe method was not found.")
    }

    arityFacts := arityBindings.CurrentInstance
    if arityFacts == null {
        throw new InvalidOperationException("Current instance facts were not configured.")
    }

    arityFacts.Properties["Broken"] = new ColumnarCurrentPropertyFact(wrongGetter, typeof(int), 0)

    arityTree := InstanceMemberTree("item", "Broken")
    arityPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarInstanceMemberPlanner.Plan(arityTree.Nodes, arityTree.Source, arityTree.Root, arityBindings, arityPlan)
    }

    ColumnarRangePlannerAssertEmptyRollback(arityPlan)

    shadowBindings := InstanceClassBindings("item", 0)
    baseFacts := BoundCurrentFacts(typeof(ColumnarBoundIdentifierCurrentClassProbe), true)
    shadowFacts := shadowBindings.CurrentInstance
    if shadowFacts == null {
        throw new InvalidOperationException("Current instance facts were not configured.")
    }

    shadowFacts.BaseFacts = baseFacts
    shadowTree := InstanceMemberTree("item", "Field")
    shadowPlan := new ColumnarCodePlan()
    assert throws InvalidOperationException {
        ColumnarInstanceMemberPlanner.Plan(shadowTree.Nodes, shadowTree.Source, shadowTree.Root, shadowBindings, shadowPlan)
    }

    ColumnarRangePlannerAssertEmptyRollback(shadowPlan)
}

test "instance member plans execute persisted receiver and member handles" {
    classTree := InstanceMemberTree("item", "Field")
    classPlan := InstanceMemberPlan(classTree, InstanceClassBindings("item", 0))

    classParameters := new Type[](1)
    classParameters[0] = typeof(ColumnarBoundIdentifierCurrentClassProbe)
    classMethod := BoundDynamicMethod("InstanceClassField", typeof(int), classParameters)

    classIl := classMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(classPlan, classIl)
    classIl.Emit(OpCodes.Ret)
    classArguments := new object[](1)
    ExecutorSetObject(classArguments, 0, new ColumnarBoundIdentifierCurrentClassProbe(71))

    assert BoundInvokeText(classMethod, classArguments) == "71"

    structTree := InstanceMemberTree("item", "Value")
    structPlan := InstanceMemberPlan(structTree, InstanceStructBindings("item", 0))

    structParameters := new Type[](1)
    structParameters[0] = typeof(ColumnarBoundIdentifierCurrentStructProbe)
    structMethod := BoundDynamicMethod("InstanceStructProperty", typeof(int), structParameters)

    structIl := structMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(structPlan, structIl)
    structIl.Emit(OpCodes.Ret)
    structArguments := new object[](1)
    ExecutorSetObject(structArguments, 0, new ColumnarBoundIdentifierCurrentStructProbe(72))

    assert BoundInvokeText(structMethod, structArguments) == "72"
}

test "instance member planner executes exact byref receiver forms" {
    sourceStructBindings := InstanceStructBindings("item", 0)
    sourceStructBindings.ParameterTypes["item"] = InstanceByRefType("SourceStruct")

    sourceStructPlan := InstanceMemberPlan(InstanceMemberTree("item", "Value"), sourceStructBindings)

    assert sourceStructPlan.FragmentCount == 1
    assert sourceStructPlan.FragmentOperationStarts[0] == 0
    assert sourceStructPlan.FragmentOperationCounts[0] == 2
    assert sourceStructPlan.FragmentParentIndices[0] == -1
    assert sourceStructPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert sourceStructPlan.ArgumentIsAddress[0]
    assert sourceStructPlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()

    sourceStructParameters := new Type[](1)
    sourceStructParameters[0] = InstanceByRefType("SourceStruct")

    sourceStructMethod := BoundDynamicMethod("InstanceSourceStructByRef", typeof(int), sourceStructParameters)

    sourceStructIl := sourceStructMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(sourceStructPlan, sourceStructIl)
    sourceStructIl.Emit(OpCodes.Ret)
    sourceStructArguments := new object[](1)
    ExecutorSetObject(sourceStructArguments, 0, new ColumnarBoundIdentifierCurrentStructProbe(73))

    assert BoundInvokeText(sourceStructMethod, sourceStructArguments) == "73"

    referenceBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(referenceBindings, "version", 0, InstanceByRefType("RuntimeReference"))

    referencePlan := InstanceMemberPlan(InstanceMemberTree("version", "Major"), referenceBindings)

    assert referencePlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert referencePlan.ArgumentIsAddress[0]
    assert referencePlan.OpCodeValues[1] == ColumnarCodePlanContract.LdindRef()
    assert referencePlan.OpCodeValues[2] == ColumnarCodePlanContract.Callvirt()

    referenceParameters := new Type[](1)
    referenceParameters[0] = InstanceByRefType("RuntimeReference")
    referenceMethod := BoundDynamicMethod("InstanceRuntimeReferenceByRef", typeof(int), referenceParameters)

    referenceIl := referenceMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(referencePlan, referenceIl)
    referenceIl.Emit(OpCodes.Ret)
    referenceArguments := new object[](1)
    referenceConstructorTypes := new Type[](2)
    referenceConstructorTypes[0] = typeof(int)
    referenceConstructorTypes[1] = typeof(int)
    referenceConstructor := ExecutorRequiredConstructor(typeof(Version), referenceConstructorTypes)

    referenceConstructorArguments := new object[](2)
    ExecutorSetObject(referenceConstructorArguments, 0, 74)
    ExecutorSetObject(referenceConstructorArguments, 1, 1)
    referenceValue := referenceConstructor.Invoke(referenceConstructorArguments)

    ExecutorSetObject(referenceArguments, 0, referenceValue)

    assert BoundInvokeText(referenceMethod, referenceArguments) == "74"

    runtimeValueBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(runtimeValueBindings, "instant", 0, InstanceByRefType("RuntimeValue"))

    runtimeValuePlan := InstanceMemberPlan(InstanceMemberTree("instant", "Year"), runtimeValueBindings)

    assert runtimeValuePlan.OperationCount == 2
    assert runtimeValuePlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert runtimeValuePlan.ArgumentIsAddress[0]
    assert runtimeValuePlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert runtimeValuePlan.PlanLocalCount == 0

    runtimeValueParameters := new Type[](1)
    runtimeValueParameters[0] = InstanceByRefType("RuntimeValue")
    runtimeValueMethod := BoundDynamicMethod("InstanceRuntimeValueByRef", typeof(int), runtimeValueParameters)

    runtimeValueIl := runtimeValueMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(runtimeValuePlan, runtimeValueIl)
    runtimeValueIl.Emit(OpCodes.Ret)
    runtimeValueArguments := new object[](1)
    runtimeValueConstructorTypes := new Type[](3)
    runtimeValueConstructorTypes[0] = typeof(int)
    runtimeValueConstructorTypes[1] = typeof(int)
    runtimeValueConstructorTypes[2] = typeof(int)
    runtimeValueConstructor := ExecutorRequiredConstructor(typeof(DateTime), runtimeValueConstructorTypes)

    runtimeValueConstructorArguments := new object[](3)
    ExecutorSetObject(runtimeValueConstructorArguments, 0, 2075)
    ExecutorSetObject(runtimeValueConstructorArguments, 1, 1)
    ExecutorSetObject(runtimeValueConstructorArguments, 2, 2)
    runtimeValue := runtimeValueConstructor.Invoke(runtimeValueConstructorArguments)

    ExecutorSetObject(runtimeValueArguments, 0, runtimeValue)

    assert BoundInvokeText(runtimeValueMethod, runtimeValueArguments) == "2075"
}

test "instance member planner terminally declines inaccessible exact members" {
    callback := new ColumnarInstanceMemberPrivateGetterProbe(1).HiddenDelegate()
    multicastDelegateType := typeof(Func<int>).get_BaseType()
    if multicastDelegateType == null {
        throw new InvalidOperationException("The multicast-delegate metadata probe was not found.")
    }

    delegateType := multicastDelegateType.get_BaseType()
    if delegateType == null {
        throw new InvalidOperationException("The delegate metadata probe was not found.")
    }

    methodProperty := delegateType.GetProperty("Method")
    if methodProperty == null {
        throw new InvalidOperationException("Delegate.Method metadata was not found.")
    }

    hiddenGetter := methodProperty.GetValue(callback) as MethodInfo
    if hiddenGetter == null {
        throw new InvalidOperationException("Delegate.Method did not return exact method metadata.")
    }

    declaringType := hiddenGetter.get_DeclaringType()
    if declaringType == null || hiddenGetter.get_IsStatic() || hiddenGetter.get_IsPublic() {
        throw new InvalidOperationException("The exact private instance getter probe was not preserved.")
    }

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "item", 0, declaringType)
    facts := new ColumnarCurrentInstanceFacts(declaringType, true)
    facts.Properties["Hidden"] = new ColumnarCurrentPropertyFact(hiddenGetter, typeof(int), 0)
    bindings.CurrentInstance = facts
    tree := InstanceMemberTree("item", "Hidden")

    assert ColumnarInstanceMemberPlanner.ClaimsRoot(tree.Nodes, tree.Source, tree.Root, bindings)

    plan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan) == ColumnarFragmentPlanStatus.NotOwned

    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "instance member planner rolls back an emitted external static receiver atomically" {
    bindings := ColumnarRangePlannerEmptyBindings()
    validTree := InstanceNestedMemberTree("DateTime", "UtcNow", "Year")
    ExternalStampScope(validTree, "import System\n")

    assert ColumnarInstanceMemberPlanner.ClaimsRoot(validTree.Nodes, validTree.Source, validTree.Root, bindings)
    validPlan := InstanceMemberPlan(validTree, bindings)
    assert validPlan.ResultType == typeof(int)
    assert validPlan.FragmentCount == 2
    assert validPlan.OpCodeValues[0] == ColumnarCodePlanContract.Call()

    missingTree := InstanceNestedMemberTree("DateTime", "UtcNow", "Missing")
    ExternalStampScope(missingTree, "import System\n")
    assert ColumnarInstanceMemberPlanner.ClaimsRoot(missingTree.Nodes, missingTree.Source, missingTree.Root, bindings)
    missingPlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(missingTree.Nodes, missingTree.Source, missingTree.Root, bindings, missingPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(missingPlan)
}

test "instance member planner owns a List element field through the closed get_Item indexer" {
    element := SourceCallDefinition("InstanceListElement", true)
    idField := ConstructionDefinePublicField(element.Builder, "Id", typeof(int))
    element.Fields["Id"] = idField

    bindings := InstanceSourceListBindings("issues", element)
    tree := InstanceIndexerMemberTree("issues", "Id")

    plan := InstanceMemberPlan(tree, bindings)

    assert plan.ResultType == typeof(int)
    // ldarg issues, ldc.i4.0, callvirt get_Item, ldfld Id.
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[plan.OperationCount - 1] == ColumnarCodePlanContract.Ldfld()
    assert DirectCallHasMethod(plan, "get_Item")
    getterIndex := -1
    scan := 0
    while scan < plan.MethodCount {
        if plan.Methods[scan] != null && plan.Methods[scan].get_Name() == "get_Item" {
            getterIndex = scan
        }
        scan += 1
    }
    assert getterIndex >= 0
    assert plan.MethodParameterTypes[getterIndex].Length == 1
    assert plan.MethodParameterTypes[getterIndex][0] == typeof(int)
}

test "instance member planner owns a List element field as a binary equality operand" {
    element := SourceCallDefinition("InstanceListBinaryElement", true)
    idField := ConstructionDefinePublicField(element.Builder, "Id", typeof(int))
    element.Fields["Id"] = idField

    definitions := new ColumnarStructDef[](1)
    definitions[0] = element
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceTypeDefinitions = definitions
    elementType: Type = element.Builder
    typeArguments := new Type[](1)
    typeArguments[0] = elementType
    listType := typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(typeArguments)
    ColumnarRangePlannerAddParameter(bindings, "issues", 0, listType)
    ColumnarRangePlannerAddParameter(bindings, "id", 1, typeof(int))

    tree := DirectCallParsedTree("issues[0].Id == id")

    plan := new ColumnarCodePlan()
    owned := false
    wholeSubtree := false
    resultType := typeof(int)
    assert ColumnarPrimitiveBinaryPlanner.TryGetTypeRoot(tree.Nodes, tree.Source, tree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), plan, out owned, out wholeSubtree, out resultType)

    assert owned
    assert resultType == typeof(bool)
    assert DirectCallHasMethod(plan, "get_Item")
    ColumnarCodePlanExecutor.Validate(plan)
}

test "instance member planner declines a List element member absent from the element" {
    bindings := ColumnarRangePlannerEmptyBindings()
    intListType := typeof(List<int>)
    ColumnarRangePlannerAddParameter(bindings, "values", 0, intListType)
    tree := InstanceIndexerMemberTree("values", "Id")

    declinePlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, declinePlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(declinePlan)
}

test "instance member planner leaves indexers and invocation receivers unowned" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "items", 0, typeof(int[]))

    indexer := InstanceIndexerTree("items")
    assert !ColumnarInstanceMemberPlanner.MayPlanRoot(indexer.Nodes, indexer.Root)
    indexerPlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(indexer.Nodes, indexer.Source, indexer.Root, bindings, indexerPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(indexerPlan)

    invocation := InstanceCallReceiverTree("Major")
    assert ColumnarInstanceMemberPlanner.MayPlanRoot(invocation.Nodes, invocation.Root)
    assert !ColumnarInstanceMemberPlanner.ClaimsRoot(invocation.Nodes, invocation.Source, invocation.Root, bindings)
    invocationPlan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(invocation.Nodes, invocation.Source, invocation.Root, bindings, invocationPlan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(invocationPlan)
}

test "instance member runtime admission rejects pointer and open generic external shapes" {
    pointerType := Type.GetType("System.Int32*")
    if pointerType == null {
        throw new InvalidOperationException("The CLR pointer-type probe was not found.")
    }

    openGenericType := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedExternalReferenceShape(pointerType)
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedExternalReferenceShape(openGenericType)
}

test "instance member planner terminally declines exact ref-return properties" {
    noParameters := new Type[](0)
    getter := typeof(string).GetMethod("GetPinnableReference", noParameters)
    if getter == null || !getter.get_ReturnType().get_IsByRef() {
        throw new InvalidOperationException("String.GetPinnableReference did not expose its exact ref return.")
    }

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "text", 0, typeof(string))
    facts := new ColumnarCurrentInstanceFacts(typeof(string), true)
    facts.Properties["Reference"] = new ColumnarCurrentPropertyFact(getter, getter.get_ReturnType(), 0)
    bindings.CurrentInstance = facts
    tree := InstanceMemberTree("text", "Reference")

    assert ColumnarInstanceMemberPlanner.ClaimsRoot(tree.Nodes, tree.Source, tree.Root, bindings)
    plan := new ColumnarCodePlan()
    assert ColumnarInstanceMemberPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan) == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "instance member facade reports terminal ownership for every admitted receiver outcome" {
    InstanceFacadeAssertTerminal(InstanceMemberTree("receiver", "Major"), typeof(Version), true, typeof(int))

    InstanceFacadeAssertTerminal(InstanceMemberTree("receiver", "Capacity"), typeof(List<int>), true, typeof(int))

    InstanceFacadeAssertTerminal(InstanceMemberTree("receiver", "WriteIndented"), typeof(System.Text.Json.JsonSerializerOptions), true, typeof(bool))

    InstanceFacadeAssertTerminal(InstanceMemberTree("receiver", "Missing"), typeof(Version), false, typeof(int))

    InstanceFacadeAssertTerminal(InstanceMemberTree("receiver", "UtcNow"), typeof(DateTime), false, typeof(int))

    InstanceFacadeAssertTerminal(InstanceMemberTree("receiver", "AssemblyQualifiedName"), typeof(Type), false, typeof(int))
}

test "range planner recursively owns instance member endpoints" {
    bindings := InstanceClassBindings("end", 0)
    plan := ColumnarRangePlannerPlan(InstanceMemberFromEndTree("end", "Field"), bindings)

    assert plan.ResultType == typeof(Index)
    assert plan.FragmentCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
}

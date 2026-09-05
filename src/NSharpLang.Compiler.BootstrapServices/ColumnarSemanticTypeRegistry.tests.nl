namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

func SemanticEnumIndex(
    definitions: Dictionary<string, ColumnarEnumDef>
): ColumnarSemanticDefinitionIndex<ColumnarEnumDef> {
    return ColumnarSemanticDefinitionIndexes.Enums(definitions)
}

func SemanticStructIndex(
    definitions: Dictionary<string, ColumnarStructDef>
): ColumnarSemanticDefinitionIndex<ColumnarStructDef> {
    return ColumnarSemanticDefinitionIndexes.Structs(definitions)
}

func SemanticUnionIndex(
    definitions: Dictionary<string, ColumnarUnionDef>
): ColumnarSemanticDefinitionIndex<ColumnarUnionDef> {
    return ColumnarSemanticDefinitionIndexes.Unions(definitions)
}

func SemanticTypeResolution(
    program: ColumnarProgramInput,
    sourceFileId: int,
    enums: Dictionary<string, ColumnarEnumDef>,
    structs: Dictionary<string, ColumnarStructDef>,
    unions: Dictionary<string, ColumnarUnionDef>,
    typeParameters: Dictionary<string, Type>?,
    enclosingSourceDeclarationName: string?
): ColumnarSemanticTypeResolution {
    catalog := new ColumnarSemanticTypeResolutionCatalog(
        program,
        enums,
        structs,
        unions
    )
    return catalog.For(
        sourceFileId,
        typeParameters,
        enclosingSourceDeclarationName
    )
}

func SemanticEmptyEnums(): Dictionary<string, ColumnarEnumDef> {
    return new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
}

func SemanticEmptyStructs(): Dictionary<string, ColumnarStructDef> {
    return new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
}

func SemanticEmptyUnions(): Dictionary<string, ColumnarUnionDef> {
    return new Dictionary<string, ColumnarUnionDef>(StringComparer.Ordinal)
}

test "semantic type resolution catalog caches each exact view identity" {
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace First\n"
    sources[1] = "namespace Second\n"
    fileNames[0] = "semantic-registry/catalog-first.nl"
    fileNames[1] = "semantic-registry/catalog-second.nl"
    catalog := new ColumnarSemanticTypeResolutionCatalog(
        ExactTypeProgram(sources, fileNames),
        SemanticEmptyEnums(),
        SemanticEmptyStructs(),
        SemanticEmptyUnions()
    )

    first := catalog.For(0, null, null)
    assert ColumnarConstructionPlanner.SameObject(
        first,
        catalog.For(0, null, null)
    )
    assert !ColumnarConstructionPlanner.SameObject(
        first,
        catalog.For(1, null, null)
    )

    firstOwner := catalog.For(0, null, "First.Owner")
    assert ColumnarConstructionPlanner.SameObject(
        firstOwner,
        catalog.For(0, null, "First.Owner")
    )
    assert !ColumnarConstructionPlanner.SameObject(
        firstOwner,
        catalog.For(0, null, "First.Other")
    )
    assert !ColumnarConstructionPlanner.SameObject(
        firstOwner,
        catalog.For(1, null, "First.Owner")
    )

    genericOwner := TypeOfCreateSourceBuilder(
        "SemanticCatalogGenericOwner",
        true
    )
    genericArguments := genericOwner.GetGenericArguments()
    assert genericArguments.Length == 1
    genericParameter := genericArguments[0]
    firstParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    firstParameters[genericParameter.Name] = genericParameter
    equivalentParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    equivalentParameters[genericParameter.Name] = genericParameter
    generic := catalog.For(0, firstParameters, "First.Owner")
    assert ColumnarConstructionPlanner.SameObject(
        generic,
        catalog.For(0, firstParameters, "First.Owner")
    )
    assert !ColumnarConstructionPlanner.SameObject(
        generic,
        catalog.For(0, equivalentParameters, "First.Owner")
    )
    assert !ColumnarConstructionPlanner.SameObject(
        generic,
        catalog.For(1, firstParameters, "First.Owner")
    )
    assert !ColumnarConstructionPlanner.SameObject(
        generic,
        catalog.For(0, firstParameters, "First.Other")
    )

    emptyParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    assert !ColumnarConstructionPlanner.SameObject(
        first,
        catalog.For(0, emptyParameters, null)
    )
}

test "semantic type resolution catalog creates a fresh structural emission for reused parsed input" {
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "namespace Reemit\nclass Shared {}\n"
    fileNames[0] = "semantic-registry/reemit-shared.nl"
    program := ExactTypeProgram(sources, fileNames)

    firstBuilder := TypeOfCreateSourceBuilder("Reemit.Shared", false)
    firstDefinition := ExactTypeDefinition(firstBuilder, "Reemit.Shared")
    firstStructs := SemanticEmptyStructs()
    firstStructs[firstDefinition.DeclaredTypeName] = firstDefinition
    firstCatalog := new ColumnarSemanticTypeResolutionCatalog(
        program,
        SemanticEmptyEnums(),
        firstStructs,
        SemanticEmptyUnions()
    )
    firstResolution := firstCatalog.For(0, null, null)
    firstSelected := ColumnarSelectedTypeReference.Missing(
        firstResolution.StructuralTypeReferences
    )
    firstClaimed := false
    assert firstResolution.Structs.Resolver.TryResolveSelected(
        "Shared",
        out firstSelected,
        out firstClaimed
    )
    assert firstClaimed
    assert firstSelected.SourceProvenanceName == "Reemit.Shared"
    assert firstResolution.StructuralTypeReferences.ValidatePair(
        firstSelected,
        firstBuilder
    )
    retainedPlan := new ColumnarCodePlan()
    retainedPlan.PrepareMethodBody()
    retainedIndex := retainedPlan.AddType(
        firstSelected,
        firstResolution.StructuralTypeReferences
    )

    secondBuilder := TypeOfCreateSourceBuilder("Reemit.Shared", false)
    secondDefinition := ExactTypeDefinition(secondBuilder, "Reemit.Shared")
    secondStructs := SemanticEmptyStructs()
    secondStructs[secondDefinition.DeclaredTypeName] = secondDefinition
    secondCatalog := new ColumnarSemanticTypeResolutionCatalog(
        program,
        SemanticEmptyEnums(),
        secondStructs,
        SemanticEmptyUnions()
    )
    secondResolution := secondCatalog.For(0, null, null)
    secondSelected := ColumnarSelectedTypeReference.Missing(
        secondResolution.StructuralTypeReferences
    )
    secondClaimed := false
    assert secondResolution.Structs.Resolver.TryResolveSelected(
        "Shared",
        out secondSelected,
        out secondClaimed
    )
    assert secondClaimed

    firstIdentity := firstResolution.StructuralTypeReferences.Identity
    secondIdentity := secondResolution.StructuralTypeReferences.Identity
    assert !ColumnarConstructionPlanner.SameObject(firstIdentity, secondIdentity)
    firstKey := firstSelected.Key
    secondKey := secondSelected.Key
    assert !ColumnarConstructionPlanner.SameObject(firstKey, secondKey)
    assert firstSelected.SourceProvenanceName == secondSelected.SourceProvenanceName
    retainedEntry := StructuralPoolRequiredEntry(retainedPlan, retainedIndex)
    retainedTable := retainedEntry.Table
    firstTable := firstResolution.StructuralTypeReferences
    secondTable := secondResolution.StructuralTypeReferences
    assert ColumnarConstructionPlanner.SameObject(retainedTable, firstTable)
    retainedRuntime := retainedPlan.ValidatedTypeAt(retainedIndex)
    assert ColumnarConstructionPlanner.SameObject(retainedRuntime, firstBuilder)
    assert firstTable.ValidatePair(
        firstSelected,
        firstBuilder
    )
    assert !secondTable.ValidatePair(
        firstSelected,
        firstBuilder
    )
    assert secondTable.ValidatePair(
        secondSelected,
        secondBuilder
    )
}

test "semantic type resolution catalog preserves exact maps behind source aliases" {
    boxBuilder := TypeOfCreateSourceBuilder("Catalog.Box", true)
    boxDefinition := ExactTypeDefinition(boxBuilder, "Catalog.Box")
    structs := SemanticEmptyStructs()
    structs[boxDefinition.DeclaredTypeName] = boxDefinition
    structs["Box"] = boxDefinition

    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace Catalog\nclass Box<T> {}\n"
    sources[1] = "namespace Caller\nimport Catalog\ntype IntBox = Box<int>\n"
    fileNames[0] = "semantic-registry/catalog-box.nl"
    fileNames[1] = "semantic-registry/catalog-caller.nl"
    catalog := new ColumnarSemanticTypeResolutionCatalog(
        ExactTypeProgram(sources, fileNames),
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions()
    )
    resolution := catalog.For(1, null, null)

    exactTypes := resolution.Structs.Resolver.ExactSourceTypes
    assert exactTypes.ContainsKey(boxDefinition.DeclaredTypeName)
    assert !exactTypes.ContainsKey("Box")

    selectedType := typeof(object)
    claimed := false
    assert resolution.Structs.Resolver.TryResolve(
        "IntBox",
        out selectedType,
        out claimed
    )
    assert claimed
    assert selectedType.get_IsGenericType()
    assert ColumnarConstructionPlanner.SameObject(
        selectedType.GetGenericTypeDefinition(),
        boxBuilder
    )
    arguments := selectedType.GetGenericArguments()
    assert arguments.Length == 1
    assert arguments[0] == typeof(int)

    selectedDefinition := boxDefinition
    assert resolution.Structs.TryGetValue("IntBox", out selectedDefinition)
    assert ColumnarConstructionPlanner.SameObject(
        selectedDefinition,
        boxDefinition
    )
}

test "semantic resolver selects nested source types from the exact lexical owner" {
    outer := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Lexical.Outer", false),
        "Lexical.Outer"
    )
    outerSibling := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Lexical.Outer.Sibling", false),
        "Lexical.Outer.Sibling"
    )
    middle := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Lexical.Outer.Middle", false),
        "Lexical.Outer.Middle"
    )
    inner := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Lexical.Outer.Middle.Inner", false),
        "Lexical.Outer.Middle.Inner"
    )
    other := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Lexical.Other", false),
        "Lexical.Other"
    )
    otherSibling := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Lexical.Other.Sibling", false),
        "Lexical.Other.Sibling"
    )
    otherInner := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Lexical.Other.Inner", false),
        "Lexical.Other.Inner"
    )
    topLevelSibling := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("Lexical.Sibling", false),
        "Lexical.Sibling"
    )

    structs := SemanticEmptyStructs()
    structs[outer.DeclaredTypeName] = outer
    structs[outerSibling.DeclaredTypeName] = outerSibling
    structs[middle.DeclaredTypeName] = middle
    structs[inner.DeclaredTypeName] = inner
    structs[other.DeclaredTypeName] = other
    structs[otherSibling.DeclaredTypeName] = otherSibling
    structs[otherInner.DeclaredTypeName] = otherInner
    structs[topLevelSibling.DeclaredTypeName] = topLevelSibling

    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "namespace Lexical\n" + "class Sibling {}\n" + "class Outer {\n" + "  class Sibling {}\n" + "  class Middle { class Inner {} }\n" + "}\n" + "class Other { class Sibling {} class Inner {} }\n"
    fileNames[0] = "semantic-registry/nested-owner.nl"
    program := ExactTypeProgram(sources, fileNames)

    outerResolution := SemanticTypeResolution(
        program,
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        null,
        inner.DeclaredTypeName
    )
    selected := topLevelSibling
    if !outerResolution.Structs.TryGetValue("Sibling", out selected) {
        throw new InvalidOperationException(
            "Nested semantic registry did not resolve the ancestor sibling."
        )
    }
    if !ColumnarConstructionPlanner.SameObject(selected, outerSibling) {
        throw new InvalidOperationException(
            "Nested semantic registry selected the wrong ancestor sibling."
        )
    }

    exactSelected := typeof(object)
    exactClaimed := false
    if !outerResolution.Structs.Resolver.TryResolve(
        "Sibling",
        out exactSelected,
        out exactClaimed
    ) {
        throw new InvalidOperationException(
            "Nested exact resolver did not return the ancestor sibling type."
        )
    }
    if !exactClaimed {
        throw new InvalidOperationException(
            "Nested exact resolver did not claim the ancestor sibling spelling."
        )
    }
    if !ColumnarConstructionPlanner.SameObject(
        exactSelected,
        outerSibling.Builder
    ) {
        throw new InvalidOperationException(
            "Nested exact resolver returned the wrong ancestor sibling type."
        )
    }

    dotted := topLevelSibling
    outerOwnerResolution := SemanticTypeResolution(
        program,
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        null,
        outer.DeclaredTypeName
    )
    if !outerOwnerResolution.Structs.TryGetValue(
        "Middle.Inner",
        out dotted
    ) {
        throw new InvalidOperationException(
            "Nested semantic registry did not resolve a dotted descendant."
        )
    }
    if !ColumnarConstructionPlanner.SameObject(dotted, inner) {
        throw new InvalidOperationException(
            "Nested semantic registry selected the wrong dotted descendant."
        )
    }

    otherResolution := SemanticTypeResolution(
        program,
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        null,
        otherInner.DeclaredTypeName
    )
    selected = topLevelSibling
    if !otherResolution.Structs.TryGetValue("Sibling", out selected) {
        throw new InvalidOperationException(
            "Second nested semantic view did not resolve its sibling."
        )
    }
    if !ColumnarConstructionPlanner.SameObject(selected, otherSibling) {
        throw new InvalidOperationException(
            "Second nested semantic view reused the first owner's cached sibling."
        )
    }

    synthesized := outerResolution.Structs.ForSynthesizedMethod(inner.Builder)
    selected = topLevelSibling
    if !synthesized.TryGetValue("Sibling", out selected) {
        throw new InvalidOperationException(
            "Synthesized semantic view lost its enclosing source declaration."
        )
    }
    if !ColumnarConstructionPlanner.SameObject(selected, outerSibling) {
        throw new InvalidOperationException(
            "Synthesized semantic view selected the wrong enclosing sibling."
        )
    }
}

test "semantic resolver caches exact source aliases and preserves closed generic aliases" {
    boxBuilder := TypeOfCreateSourceBuilder("Left.SemanticBox", true)
    boxDefinition := ExactTypeDefinition(boxBuilder, "Left.SemanticBox")
    structs := SemanticEmptyStructs()
    structs[boxDefinition.DeclaredTypeName] = boxDefinition

    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "namespace Left\nclass SemanticBox<T> {}\ntype IntBox = SemanticBox<int>\n"
    fileNames[0] = "semantic-registry/left.nl"
    program := ExactTypeProgram(sources, fileNames)
    resolution := SemanticTypeResolution(
        program,
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        null,
        ""
    )

    firstType := typeof(object)
    firstClaimed := false
    assert resolution.Structs.Resolver.TryResolve(
        "IntBox",
        out firstType,
        out firstClaimed
    )
    assert firstClaimed
    assert firstType.get_IsGenericType()
    assert ColumnarConstructionPlanner.SameObject(
        firstType.GetGenericTypeDefinition(),
        boxBuilder
    )
    assert resolution.Structs.Resolver.RuntimeGenericValidationCanonical(firstType) == null
    arguments := firstType.GetGenericArguments()
    assert arguments.Length == 1
    assert arguments[0] == typeof(int)

    repeatedType := typeof(object)
    repeatedClaimed := false
    assert resolution.Structs.Resolver.TryResolve(
        "IntBox",
        out repeatedType,
        out repeatedClaimed
    )
    assert repeatedClaimed
    assert ColumnarConstructionPlanner.SameObject(firstType, repeatedType)

    selected := boxDefinition
    assert resolution.Structs.TryGetValue("IntBox", out selected)
    assert ColumnarConstructionPlanner.SameObject(selected, boxDefinition)
    repeated := boxDefinition
    assert resolution.Structs.TryGetValue("IntBox", out repeated)
    assert ColumnarConstructionPlanner.SameObject(repeated, boxDefinition)
}

test "semantic registry treats ambiguous source claims as terminal negative cache entries" {
    leftBuilder := TypeOfCreateSourceBuilder("Left.SemanticWidget", false)
    rightBuilder := TypeOfCreateSourceBuilder("Right.SemanticWidget", false)
    leftDefinition := ExactTypeDefinition(leftBuilder, "Left.SemanticWidget")
    rightDefinition := ExactTypeDefinition(rightBuilder, "Right.SemanticWidget")
    structs := SemanticEmptyStructs()
    structs[leftDefinition.DeclaredTypeName] = leftDefinition
    structs[rightDefinition.DeclaredTypeName] = rightDefinition

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nclass SemanticWidget {}\n"
    sources[1] = "namespace Right\nclass SemanticWidget {}\n"
    sources[2] = "namespace Caller\nclass Consumer {}\n"
    fileNames[0] = "semantic-registry/ambiguous-left.nl"
    fileNames[1] = "semantic-registry/ambiguous-right.nl"
    fileNames[2] = "semantic-registry/ambiguous-caller.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        2,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        null,
        ""
    )
    selectedType := typeof(object)
    claimed := false
    assert !resolution.Structs.Resolver.TryResolve(
        "SemanticWidget",
        out selectedType,
        out claimed
    )
    assert claimed
    assert selectedType == typeof(object)

    selected := leftDefinition
    assert !resolution.Structs.TryGetValue("SemanticWidget", out selected)
    repeated := rightDefinition
    assert !resolution.Structs.TryGetValue("SemanticWidget", out repeated)
}

test "semantic enum registry preserves erased source identity before runtime identity" {
    leftStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    leftStrings["Ready"] = "left"
    rightStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    rightStrings["Ready"] = "right"
    left := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        leftStrings,
        "Left.SemanticState"
    )
    right := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        rightStrings,
        "Right.SemanticState"
    )
    enums := SemanticEmptyEnums()
    enums[left.DeclaredTypeName] = left
    enums[right.DeclaredTypeName] = right

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nenum SemanticState: string { Ready = \"left\" }\n"
    sources[1] = "namespace Right\nenum SemanticState: string { Ready = \"right\" }\n"
    sources[2] = "namespace Caller\nimport Right\n"
    fileNames[0] = "semantic-registry/erased-left.nl"
    fileNames[1] = "semantic-registry/erased-right.nl"
    fileNames[2] = "semantic-registry/erased-caller.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        2,
        enums,
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        ""
    )
    selected := left
    assert resolution.Enums.TryGetValue("SemanticState", out selected)
    assert ColumnarConstructionPlanner.SameObject(selected, right)
    assert selected.StringConstants != null
    assert selected.StringConstants["Ready"] == "right"

    rightReference := ColumnarSelectedTypeReference.Missing(
        resolution.StructuralTypeReferences
    )
    rightClaimed := false
    assert resolution.Enums.Resolver.TryResolveSelected(
        "SemanticState",
        out rightReference,
        out rightClaimed
    )
    assert rightClaimed
    assert rightReference.Key.Kind == ColumnarStructuralTypeReferenceKind.Primitive
    assert rightReference.RuntimeType == typeof(string)
    assert rightReference.SourceProvenanceName == "Right.SemanticState"

    leftReference := ColumnarSelectedTypeReference.Missing(
        resolution.StructuralTypeReferences
    )
    leftClaimed := false
    assert resolution.Enums.Resolver.TryResolveSelected(
        "Left.SemanticState",
        out leftReference,
        out leftClaimed
    )
    assert leftClaimed
    assert Object.ReferenceEquals(leftReference.Key, rightReference.Key)
    assert leftReference.SourceProvenanceName == "Left.SemanticState"
    assert resolution.StructuralTypeReferences.ValidatePair(
        rightReference,
        typeof(string)
    )
    assert resolution.StructuralTypeReferences.ValidatePair(
        leftReference,
        typeof(string)
    )
}

test "semantic enum registry distinguishes source declarations from erased runtime aliases" {
    stringConstants := new Dictionary<string, string>(StringComparer.Ordinal)
    stringConstants["Value"] = "enum"
    selection := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        stringConstants,
        "Models.Selection"
    )
    enums := SemanticEmptyEnums()
    enums[selection.DeclaredTypeName] = selection

    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "namespace Models\nenum Selection: string { Value = \"enum\" }\n"
    sources[1] = "namespace Caller\nimport Models\ntype Text = string\n" + "type SelectionAlias = Selection\n"
    fileNames[0] = "semantic-registry/erased-model.nl"
    fileNames[1] = "semantic-registry/erased-caller.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        1,
        enums,
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        ""
    )

    assert !resolution.Enums.ContainsKey("Text")
    assert !resolution.Enums.ContainsSourceDeclaration("Text")
    assert resolution.Enums.ContainsSourceDeclaration("SelectionAlias")
    assert resolution.Enums.ContainsSourceDeclaration("Selection")
    assert resolution.Enums.ContainsSourceDeclaration("Models.Selection")
}

test "semantic definition index rejects duplicate runtime identities" {
    runtimeType: Type = typeof(int)
    noStrings: Dictionary<string, string>? = null
    firstConstants := new Dictionary<string, int>(StringComparer.Ordinal)
    first := new ColumnarEnumDef(
        runtimeType,
        firstConstants,
        noStrings,
        "Fake.FirstDay"
    )
    secondConstants := new Dictionary<string, int>(StringComparer.Ordinal)
    second := new ColumnarEnumDef(
        runtimeType,
        secondConstants,
        noStrings,
        "Fake.SecondDay"
    )
    enums := SemanticEmptyEnums()
    enums[first.DeclaredTypeName] = first
    enums[second.DeclaredTypeName] = second
    index := SemanticEnumIndex(enums)
    duplicate := first
    assert !index.TryGetUniqueRuntime(runtimeType, out duplicate)

    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = ""
    fileNames[0] = "semantic-registry/runtime.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        enums,
        SemanticEmptyStructs(),
        SemanticEmptyUnions(),
        null,
        ""
    )
    selected := first
    assert !resolution.Enums.TryGetValue("int", out selected)
}

test "semantic resolver keeps syntax-owned generic shapes ahead of exact source resolution" {
    listBuilder := TypeOfCreateSourceBuilder("List", true)
    funcBuilder := TypeOfCreateBuilder(
        "Func",
        "ColumnarSemanticRegistry.Func",
        2
    )
    actionBuilder := TypeOfCreateSourceBuilder("Action", true)
    pointBuilder := TypeOfCreateSourceBuilder("SemanticPoint", false)
    listDefinition := ExactTypeDefinition(listBuilder, "List")
    funcDefinition := ExactTypeDefinition(funcBuilder, "Func")
    actionDefinition := ExactTypeDefinition(actionBuilder, "Action")
    pointDefinition := ExactTypeDefinition(pointBuilder, "SemanticPoint")
    structs := SemanticEmptyStructs()
    structs[listDefinition.DeclaredTypeName] = listDefinition
    structs[funcDefinition.DeclaredTypeName] = funcDefinition
    structs[actionDefinition.DeclaredTypeName] = actionDefinition
    structs[pointDefinition.DeclaredTypeName] = pointDefinition

    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "import System.Buffers\nimport System.Collections.Generic\n" + "class List<T> {}\nclass Func<T,R> {}\nclass Action<T> {}\n" + "class SemanticPoint {}\n" + "type QualifiedPointMap = System.Collections.Generic.Dictionary<SemanticPoint,int>\n" + "type ImportedPointMap = Dictionary<SemanticPoint,int>\n" + "type AllowedPointMap = Dictionary<string,SemanticPoint>\n" + "type UnknownRuntimeGeneric = KeyValuePair<string,int>\n" + "type ByteArrayPool = System.Buffers.ArrayPool<byte>\n" + "type IntArrayPool = System.Buffers.ArrayPool<int>\n" + "type NestedBytePool = System.Collections.Generic.List<System.Buffers.ArrayPool<byte>>\n"
    fileNames[0] = "semantic-registry/syntax-owned.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        null,
        ""
    )
    resolver := resolution.Structs.Resolver

    funcTerminal := true
    assert resolver.TryClassifySyntaxOwnedShape(
        "Func<int,string>",
        out funcTerminal
    )
    assert !funcTerminal
    nestedFuncTerminal := true
    assert resolver.TryClassifySyntaxOwnedShape(
        "Dictionary<string,(callback:Func<int,string>,count:int)>[]",
        out nestedFuncTerminal
    )
    assert !nestedFuncTerminal
    funcType := typeof(object)
    funcClaimed := true
    assert !resolver.TryResolve(
        "Func<int,string>",
        out funcType,
        out funcClaimed
    )
    assert !funcClaimed
    assert funcType == typeof(object)

    listTerminal := false
    assert resolver.TryClassifySyntaxOwnedShape(
        "List<int>",
        out listTerminal
    )
    assert listTerminal
    nestedListTerminal := false
    assert resolver.TryClassifySyntaxOwnedShape(
        "Dictionary<string,(items:List<int>?,fallback:int|string)>[]",
        out nestedListTerminal
    )
    assert nestedListTerminal
    listType := typeof(object)
    listClaimed := false
    assert !resolver.TryResolve("List<int>", out listType, out listClaimed)
    assert listClaimed
    assert listType == typeof(object)

    importedTerminal := true
    assert resolver.TryClassifySyntaxOwnedShape(
        "Dictionary<SemanticPoint,int>",
        out importedTerminal
    )
    assert !importedTerminal
    qualifiedTerminal := true
    assert resolver.TryClassifySyntaxOwnedShape(
        "System.Collections.Generic.Dictionary<SemanticPoint,int>",
        out qualifiedTerminal
    )
    assert !qualifiedTerminal
    importedDirectType := typeof(object)
    importedDirectClaimed := true
    assert !resolver.TryResolve(
        "Dictionary<SemanticPoint,int>",
        out importedDirectType,
        out importedDirectClaimed
    )
    assert !importedDirectClaimed
    qualifiedDirectType := typeof(object)
    qualifiedDirectClaimed := true
    assert !resolver.TryResolve(
        "System.Collections.Generic.Dictionary<SemanticPoint,int>",
        out qualifiedDirectType,
        out qualifiedDirectClaimed
    )
    assert !qualifiedDirectClaimed

    qualifiedAliasType := typeof(object)
    qualifiedAliasClaimed := false
    assert resolver.TryResolve(
        "QualifiedPointMap",
        out qualifiedAliasType,
        out qualifiedAliasClaimed
    )
    assert qualifiedAliasClaimed
    assert resolver.RuntimeGenericValidationCanonical(qualifiedAliasType) == "Dictionary<SemanticPoint,int>"
    importedAliasType := typeof(object)
    importedAliasClaimed := false
    assert resolver.TryResolve(
        "ImportedPointMap",
        out importedAliasType,
        out importedAliasClaimed
    )
    assert importedAliasClaimed
    assert resolver.RuntimeGenericValidationCanonical(importedAliasType) == "Dictionary<SemanticPoint,int>"
    allowedAliasType := typeof(object)
    allowedAliasClaimed := false
    assert resolver.TryResolve(
        "AllowedPointMap",
        out allowedAliasType,
        out allowedAliasClaimed
    )
    assert allowedAliasClaimed
    assert resolver.RuntimeGenericValidationCanonical(allowedAliasType) == "Dictionary<string,SemanticPoint>"
    unknownAliasType := typeof(object)
    unknownAliasClaimed := false
    assert resolver.TryResolve(
        "UnknownRuntimeGeneric",
        out unknownAliasType,
        out unknownAliasClaimed
    )
    assert unknownAliasClaimed
    assert resolver.RuntimeGenericValidationCanonical(unknownAliasType) == "*"

    bytePoolType := typeof(object)
    bytePoolClaimed := false
    assert resolver.TryResolve(
        "ByteArrayPool",
        out bytePoolType,
        out bytePoolClaimed
    )
    assert bytePoolClaimed
    assert resolver.RuntimeGenericValidationCanonical(bytePoolType) == "*"
    intPoolType := typeof(object)
    intPoolClaimed := false
    assert resolver.TryResolve(
        "IntArrayPool",
        out intPoolType,
        out intPoolClaimed
    )
    assert intPoolClaimed
    assert resolver.RuntimeGenericValidationCanonical(intPoolType) == "*"
    nestedPoolType := typeof(object)
    nestedPoolClaimed := false
    assert resolver.TryResolve(
        "NestedBytePool",
        out nestedPoolType,
        out nestedPoolClaimed
    )
    assert nestedPoolClaimed
    assert resolver.RuntimeGenericValidationCanonical(nestedPoolType) == "List<System.Buffers.ArrayPool<byte>>"

    actionTerminal := false
    assert !resolver.TryClassifySyntaxOwnedShape(
        "Action<int>",
        out actionTerminal
    )
    actionType := typeof(object)
    actionClaimed := false
    assert resolver.TryResolve(
        "Action<int>",
        out actionType,
        out actionClaimed
    )
    assert actionClaimed
    assert actionType.get_IsGenericType()
    assert ColumnarConstructionPlanner.SameObject(
        actionType.GetGenericTypeDefinition(),
        actionBuilder
    )
}

test "synthesized semantic views fence type parameters owned by another type" {
    genericOwner := TypeOfCreateSourceBuilder(
        "SemanticGenericOwner",
        true
    )
    synthesizedOwner := TypeOfCreateSourceBuilder(
        "SemanticSynthesizedOwner",
        false
    )
    genericArguments := genericOwner.GetGenericArguments()
    assert genericArguments.Length == 1
    typeParameter := genericArguments[0]
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters[typeParameter.Name] = typeParameter

    collidingBuilder := TypeOfCreateSourceBuilder(
        "SemanticCollision",
        false
    )
    collidingDefinition := ExactTypeDefinition(
        collidingBuilder,
        typeParameter.Name
    )
    structs := SemanticEmptyStructs()
    structs[collidingDefinition.DeclaredTypeName] = collidingDefinition
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "class " + typeParameter.Name + " {}\n"
    fileNames[0] = "semantic-registry/type-parameters.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        typeParameters,
        ""
    )
    resolution.StructuralTypeReferences.RegisterGenericParameters(
        typeParameters,
        ColumnarStructuralGenericOwnerIdentity.SourceType(
            0,
            "SemanticGenericOwner"
        )
    )

    visible := typeof(object)
    visibleClaimed := false
    assert resolution.Structs.Resolver.TryResolve(
        typeParameter.Name,
        out visible,
        out visibleClaimed
    )
    assert visibleClaimed
    assert ColumnarConstructionPlanner.SameObject(visible, typeParameter)

    synthesized := resolution.Structs.ForSynthesizedMethod(synthesizedOwner)
    blockedShapes := new string[](7)
    blockedShapes[0] = typeParameter.Name
    blockedShapes[1] = typeParameter.Name + "?"
    blockedShapes[2] = "(" + typeParameter.Name + ",int)"
    blockedShapes[3] = "(value:" + typeParameter.Name + ",count:int)"
    blockedShapes[4] = typeParameter.Name + "|string"
    blockedShapes[5] = "List<(value:" + typeParameter.Name + "?,fallback:" + typeParameter.Name + "|string)>[]"
    blockedShapes[6] = "&Dictionary<string,(value:" + typeParameter.Name + ",count:int)>"
    for blockedShape in blockedShapes {
        blocked := typeof(object)
        blockedClaimed := false
        assert synthesized.Resolver.ClaimsTypeParameterShape(blockedShape)
        assert !synthesized.Resolver.TryResolve(
            blockedShape,
            out blocked,
            out blockedClaimed
        )
        assert blockedClaimed
        assert blocked == typeof(object)
    }
    collision := collidingDefinition
    assert !synthesized.TryGetValue(typeParameter.Name, out collision)
    assert !synthesized.TryGetValue(
        typeParameter.Name + "?",
        out collision
    )

    ownedSynthesized := resolution.Structs.ForSynthesizedMethod(genericOwner)
    ownedTypeParameter := typeof(object)
    ownedClaimed := false
    if !ownedSynthesized.Resolver.TryResolve(
        typeParameter.Name,
        out ownedTypeParameter,
        out ownedClaimed
    ) {
        throw new InvalidOperationException(
            "Synthesized view on the declaring type lost its type parameter."
        )
    }
    if !ownedClaimed {
        throw new InvalidOperationException(
            "Synthesized view on the declaring type did not claim its type parameter."
        )
    }
    if !ColumnarConstructionPlanner.SameObject(
        ownedTypeParameter,
        typeParameter
    ) {
        throw new InvalidOperationException(
            "Synthesized view on the declaring type selected the wrong type parameter."
        )
    }
    ownedArray := typeof(object)
    ownedArrayClaimed := false
    if !ownedSynthesized.Resolver.TryResolve(
        typeParameter.Name + "[]",
        out ownedArray,
        out ownedArrayClaimed
    ) {
        throw new InvalidOperationException(
            "Synthesized view on the declaring type lost a type-parameter array."
        )
    }
    if !ownedArrayClaimed || !ownedArray.get_IsSZArray() || !ColumnarConstructionPlanner.SameObject(
        ownedArray.GetElementType(),
        typeParameter
    ) {
        throw new InvalidOperationException(
            "Synthesized view returned the wrong type-parameter array shape."
        )
    }

    noParameters := new Type[](0)
    if ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(
        typeParameter,
        noParameters,
        synthesizedOwner
    ) {
        throw new InvalidOperationException(
            "Foreign type parameter was admitted in a synthesized signature."
        )
    }
    if !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(
        typeParameter,
        noParameters,
        genericOwner
    ) {
        throw new InvalidOperationException(
            "Declaring type parameter was rejected from a synthesized signature."
        )
    }
    parameterTypes := new Type[](1)
    parameterTypes[0] = ownedArray
    if !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(
        typeof(int),
        parameterTypes,
        genericOwner
    ) {
        throw new InvalidOperationException(
            "Declaring type-parameter array was rejected from a synthesized signature."
        )
    }
}

test "synthesized program views reject parent method type parameters in signatures and bodies" {
    program := SourceCallDefinition("SemanticMethodProgram", true)
    outer := SourceCallPublicStatic(
        program,
        "Outer",
        new Type[](0),
        SourceCallVoidType()
    )
    BindingMakeGenericMethod(outer.Builder, "TMethod")
    arguments := outer.Builder.GetGenericArguments()
    assert arguments.Length == 1
    methodParameter := arguments[0]
    assert methodParameter.get_DeclaringMethod() != null
    assert ColumnarConstructionPlanner.SameObject(
        methodParameter.get_DeclaringMethod(),
        outer.Builder
    )

    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters[methodParameter.Name] = methodParameter
    collision := ExactTypeDefinition(
        TypeOfCreateSourceBuilder("SemanticMethodCollision", false),
        methodParameter.Name
    )
    structs := SemanticEmptyStructs()
    structs[collision.DeclaredTypeName] = collision
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = "class " + methodParameter.Name + " {}\n"
    fileNames[0] = "semantic-registry/method-parameter.nl"
    resolution := SemanticTypeResolution(
        ExactTypeProgram(sources, fileNames),
        0,
        SemanticEmptyEnums(),
        structs,
        SemanticEmptyUnions(),
        typeParameters,
        ""
    )
    resolution.StructuralTypeReferences.RegisterGenericParameters(
        typeParameters,
        ColumnarStructuralGenericOwnerIdentity.SourceMethod(0, 0)
    )

    visibleArray := typeof(object)
    visibleClaimed := false
    assert resolution.Structs.Resolver.TryResolve(
        methodParameter.Name + "[]",
        out visibleArray,
        out visibleClaimed
    )
    assert visibleClaimed
    assert visibleArray.get_IsSZArray()
    assert ColumnarConstructionPlanner.SameObject(
        visibleArray.GetElementType(),
        methodParameter
    )

    synthesized := resolution.Structs.ForSynthesizedMethod(program.Builder)
    blocked := typeof(object)
    blockedClaimed := false
    assert synthesized.Resolver.ClaimsTypeParameterShape(methodParameter.Name)
    assert synthesized.Resolver.ClaimsTypeParameterShape(
        methodParameter.Name + "[]"
    )
    assert !synthesized.Resolver.TryResolve(
        methodParameter.Name + "[]",
        out blocked,
        out blockedClaimed
    )
    assert blockedClaimed
    assert blocked == typeof(object)
    selected := collision
    assert !synthesized.TryGetValue(methodParameter.Name, out selected)

    signatureParameters := new Type[](1)
    signatureParameters[0] = methodParameter
    assert !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignature(
        typeof(int),
        signatureParameters,
        program.Builder
    )
    assert !ColumnarSemanticTypeRegistryBridge.IsValidSynthesizedMethodSignatureType(
        visibleArray,
        program.Builder
    )
}

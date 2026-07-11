namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


func ConstructionNewTree(
    typeName: string,
    argumentTexts: string[],
    argumentKinds: int[]): ColumnarRangePlannerTestTree {
    if argumentTexts.Length != argumentKinds.Length {
        throw new InvalidOperationException(
            "Construction argument text and kind columns must match.")
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    typeNode := builder.AddLeaf(0, typeName)
    children := new int[](argumentTexts.Length + 1)
    children[0] = typeNode
    index := 0
    while index < argumentTexts.Length {
        children[index + 1] = builder.AddLeaf(
            argumentKinds[index], argumentTexts[index])
        index += 1
    }
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1, 0, 0, builder.Source.Length, children)
    return builder.Build(root)
}

func ConstructionSizedArrayTree(
    elementName: string,
    lengthText: string,
    lengthKind: int): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    element := builder.AddLeaf(0, elementName)
    arrayType := builder.AddNode(
        2, -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren1(element))
    length := builder.AddLeaf(lengthKind, lengthText)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren2(arrayType, length))
    return builder.Build(root)
}

func ConstructionNullableSizedArrayTree(
    elementName: string,
    lengthText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    element := builder.AddLeaf(0, elementName)
    nullableElement := builder.AddNode(
        3, -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren1(element))
    arrayType := builder.AddNode(
        2, -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren1(nullableElement))
    length := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(), lengthText)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren2(arrayType, length))
    return builder.Build(root)
}

func ConstructionMalformedRepeatedSizedArrayTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    malformedElement := builder.AddNode(
        2, -1, 0, 0, builder.Source.Length, new int[](0))
    arrayType := builder.AddNode(
        2, -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren1(malformedElement))
    length := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren2(arrayType, length))
    return builder.Build(root)
}

func ConstructionNestedSizedArrayTree(
    elementName: string,
    lengthText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    element := builder.AddLeaf(0, elementName)
    innerArray := builder.AddNode(
        2, -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren1(element))
    outerArray := builder.AddNode(
        2, -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren1(innerArray))
    length := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(), lengthText)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren2(outerArray, length))
    return builder.Build(root)
}

func ConstructionNestedDirectCallTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "ConstructionConsumer")
    member := DirectCallAppendMember(builder, owner, "Consume")
    stringType := builder.AddLeaf(0, "string")
    character := builder.AddLeaf(
        ColumnarExpressionNodeKind.CharLiteralExpression(), "'z'")
    count := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    nested := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren3(stringType, character, count))
    root := DirectCallAppendCall(
        builder, member, DirectCallOneArgument(nested))
    return builder.Build(root)
}

func ConstructionDirectCallWithArrayLiteralTree(
    elementTexts: string[],
    elementKinds: int[]): ColumnarRangePlannerTestTree {
    if elementTexts.Length != elementKinds.Length {
        throw new InvalidOperationException(
            "Nested array-literal text and kind columns must match.")
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "ConstructionArrayConsumer")
    member := DirectCallAppendMember(builder, owner, "Consume")
    elements := new int[](elementTexts.Length)
    index := 0
    while index < elements.Length {
        elements[index] = builder.AddLeaf(
            elementKinds[index], elementTexts[index])
        index += 1
    }
    array := builder.AddNode(
        ColumnarExpressionNodeKind.ArrayLiteralExpression(),
        -1, 0, 0, builder.Source.Length, elements)
    root := DirectCallAppendCall(
        builder, member, DirectCallOneArgument(array))
    return builder.Build(root)
}

func ConstructionNewWithArrayLiteralTree(
    typeName: string,
    elementTexts: string[],
    elementKinds: int[]): ColumnarRangePlannerTestTree {
    if elementTexts.Length != elementKinds.Length {
        throw new InvalidOperationException(
            "Nested constructor array text and kind columns must match.")
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    typeNode := builder.AddLeaf(0, typeName)
    elements := new int[](elementTexts.Length)
    index := 0
    while index < elements.Length {
        elements[index] = builder.AddLeaf(
            elementKinds[index], elementTexts[index])
        index += 1
    }
    array := builder.AddNode(
        ColumnarExpressionNodeKind.ArrayLiteralExpression(),
        -1, 0, 0, builder.Source.Length, elements)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren2(typeNode, array))
    return builder.Build(root)
}

func ConstructionGenericNewTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    argumentType := builder.AddLeaf(0, "int")
    genericType := builder.AddNode(
        1,
        builder.AddToken("List"),
        4,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(argumentType))
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1, 0, 0, builder.Source.Length,
        ColumnarRangePlannerChildren1(genericType))
    return builder.Build(root)
}

func ConstructionArrayLiteralTree(
    elementTexts: string[],
    elementKinds: int[]): ColumnarRangePlannerTestTree {
    if elementTexts.Length != elementKinds.Length {
        throw new InvalidOperationException(
            "Array-literal text and kind columns must match.")
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    children := new int[](elementTexts.Length)
    index := 0
    while index < elementTexts.Length {
        children[index] = builder.AddLeaf(
            elementKinds[index], elementTexts[index])
        index += 1
    }
    root := builder.AddNode(
        ColumnarExpressionNodeKind.ArrayLiteralExpression(),
        -1, 0, 0, builder.Source.Length, children)
    return builder.Build(root)
}

func ConstructionOneText(value: string): string[] {
    result := new string[](1)
    result[0] = value
    return result
}

func ConstructionTwoTexts(first: string, second: string): string[] {
    result := new string[](2)
    result[0] = first
    result[1] = second
    return result
}

func ConstructionThreeTexts(
    first: string,
    second: string,
    third: string): string[] {
    result := new string[](3)
    result[0] = first
    result[1] = second
    result[2] = third
    return result
}

func ConstructionOneKind(value: int): int[] {
    result := new int[](1)
    result[0] = value
    return result
}

func ConstructionTwoKinds(first: int, second: int): int[] {
    result := new int[](2)
    result[0] = first
    result[1] = second
    return result
}

func ConstructionThreeKinds(first: int, second: int, third: int): int[] {
    result := new int[](3)
    result[0] = first
    result[1] = second
    result[2] = third
    return result
}

func ConstructionEmptyTexts(): string[] {
    return new string[](0)
}

func ConstructionEmptyKinds(): int[] {
    return new int[](0)
}

func ConstructionStampScope(
    tree: ColumnarRangePlannerTestTree,
    factSource: string) {
    ExternalStampScopeFull(
        tree,
        factSource,
        "",
        new string[](0),
        ExternalEmptyStructs(),
        null)
}

func ConstructionStampScopeWithTypeParameters(
    tree: ColumnarRangePlannerTestTree,
    factSource: string,
    visibleTypeParameters: string[]) {
    ExternalStampScopeFull(
        tree,
        factSource,
        "",
        visibleTypeParameters,
        ExternalEmptyStructs(),
        null)
}

func ConstructionPlan(
    tree: ColumnarRangePlannerTestTree,
    bindings: ColumnarFragmentBindings): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := false
    resultType := typeof(int)
    status := ColumnarConstructionPlanner.Plan(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        plan,
        out ownership,
        out legacyWholeSubtreePlanning,
        out resultType)
    if status != ColumnarFragmentPlanStatus.Planned
        || ownership != ColumnarDirectCallOwnership.Planned
        || legacyWholeSubtreePlanning {
        throw new InvalidOperationException(
            "Expected construction planner ownership.")
    }
    assert plan.ResultType == resultType
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func ConstructionRejected(
    tree: ColumnarRangePlannerTestTree,
    bindings: ColumnarFragmentBindings,
    out ownership: ColumnarDirectCallOwnership,
    out legacyWholeSubtreePlanning: bool): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    resultType := typeof(int)
    status := ColumnarConstructionPlanner.Plan(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        plan,
        out ownership,
        out legacyWholeSubtreePlanning,
        out resultType)
    assert status == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)
    return plan
}

func ConstructionBindings(
    definitions: ColumnarStructDef[]): ColumnarFragmentBindings {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceTypeDefinitions = definitions
    return bindings
}

func ConstructionSourceDefinition(
    name: string,
    isReference: bool): ColumnarStructDef {
    return SourceCallDefinition(name, isReference)
}

func ConstructionDefaults(count: int): int[] {
    result := new int[](count)
    index := 0
    while index < count {
        result[index] = -1
        index += 1
    }
    return result
}

func ConstructionDefaultTexts(count: int): string[] {
    result := new string[](count)
    index := 0
    while index < count {
        result[index] = ""
        index += 1
    }
    return result
}

func ConstructionHasOpcode(
    plan: ColumnarCodePlan,
    opCode: short): bool {
    index := 0
    while index < plan.OperationCount {
        if plan.OpCodeValues[index] == opCode {
            return true
        }
        index += 1
    }
    return false
}

test "construction planner owns sized arrays and inferred primitive arrays with exact opcodes" {
    sized := ConstructionSizedArrayTree(
        "int", "3", ColumnarExpressionNodeKind.IntLiteralExpression())
    ConstructionStampScope(sized, "")
    sizedPlan := ConstructionPlan(
        sized, ColumnarRangePlannerEmptyBindings())
    assert sizedPlan.ResultType == typeof(int[])
    assert sizedPlan.OperationCount == 2
    assert sizedPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert sizedPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newarr()
    assert sizedPlan.Types[sizedPlan.OperandIndices[1]] == typeof(int)

    ints := ConstructionArrayLiteralTree(
        ConstructionThreeTexts("1", "2", "3"),
        ConstructionThreeKinds(
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression()))
    ConstructionStampScope(ints, "")
    intPlan := ConstructionPlan(
        ints, ColumnarRangePlannerEmptyBindings())
    assert intPlan.ResultType == typeof(int[])
    assert intPlan.OperationCount == 14
    assert intPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert intPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newarr()
    assert ConstructionHasOpcode(intPlan, ColumnarCodePlanContract.Dup())
    assert ConstructionHasOpcode(
        intPlan, ColumnarCodePlanContract.StelemI4())

    result := NullableArgumentRunPlan(intPlan, typeof(int[]))
    assert result != null
    assert result.ToString() == "System.Int32[]"
}

test "construction planner chooses every fixed and typed array store form" {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.ParameterOrdinals["u"] = 0
    bindings.ParameterTypes["u"] = typeof(uint)
    bindings.ParameterOrdinals["ul"] = 1
    bindings.ParameterTypes["ul"] = typeof(ulong)

    texts := new string[](7)
    kinds := new int[](7)
    texts[0] = "true"
    texts[1] = "'a'"
    texts[2] = "u"
    texts[3] = "ul"
    texts[4] = "1.5f"
    texts[5] = "2.5"
    texts[6] = "\"x\""
    kinds[0] = ColumnarExpressionNodeKind.BoolLiteralExpression()
    kinds[1] = ColumnarExpressionNodeKind.CharLiteralExpression()
    kinds[2] = ColumnarExpressionNodeKind.IdentifierExpression()
    kinds[3] = ColumnarExpressionNodeKind.IdentifierExpression()
    kinds[4] = ColumnarExpressionNodeKind.FloatLiteralExpression()
    kinds[5] = ColumnarExpressionNodeKind.FloatLiteralExpression()
    kinds[6] = ColumnarExpressionNodeKind.StringLiteralExpression()

    expectedTypes := new Type[](7)
    expectedTypes[0] = typeof(bool)
    expectedTypes[1] = typeof(char)
    expectedTypes[2] = typeof(uint)
    expectedTypes[3] = typeof(ulong)
    expectedTypes[4] = typeof(float)
    expectedTypes[5] = typeof(double)
    expectedTypes[6] = typeof(string)
    expectedOpcodes := new short[](7)
    expectedOpcodes[0] = ColumnarCodePlanContract.StelemI1()
    expectedOpcodes[1] = ColumnarCodePlanContract.StelemI2()
    expectedOpcodes[2] = ColumnarCodePlanContract.StelemI4()
    expectedOpcodes[3] = ColumnarCodePlanContract.StelemI8()
    expectedOpcodes[4] = ColumnarCodePlanContract.StelemR4()
    expectedOpcodes[5] = ColumnarCodePlanContract.StelemR8()
    expectedOpcodes[6] = ColumnarCodePlanContract.StelemRef()

    index := 0
    while index < texts.Length {
        tree := ConstructionArrayLiteralTree(
            ConstructionTwoTexts(texts[index], texts[index]),
            ConstructionTwoKinds(kinds[index], kinds[index]))
        ConstructionStampScope(tree, "")
        plan := ConstructionPlan(tree, bindings)
        assert plan.ResultType != null
        assert plan.ResultType.get_IsSZArray()
        assert plan.ResultType.GetElementType() == expectedTypes[index]
        assert ConstructionHasOpcode(plan, expectedOpcodes[index])
        index += 1
    }

    valueDefinition := ConstructionSourceDefinition(
        "ConstructionArrayValue", false)
    valueBindings := ConstructionBindings(
        SourceCallDefinitions(valueDefinition))
    valueBindings.ParameterOrdinals["value"] = 0
    valueBindings.ParameterTypes["value"] = valueDefinition.Builder
    valueTree := ConstructionArrayLiteralTree(
        ConstructionTwoTexts("value", "value"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.IdentifierExpression(),
            ColumnarExpressionNodeKind.IdentifierExpression()))
    ConstructionStampScope(
        valueTree, "struct ConstructionArrayValue {}")
    valuePlan := ConstructionPlan(valueTree, valueBindings)
    assert ConstructionHasOpcode(
        valuePlan, ColumnarCodePlanContract.Stelem())
    typedOperation := valuePlan.OperationCount - 1
    assert ColumnarConstructionPlanner.SameObject(
        valuePlan.Types[valuePlan.OperandIndices[typedOperation]],
        valueDefinition.Builder)
}

test "construction planner defers contextual array shapes as whole subtrees" {
    empty := ConstructionArrayLiteralTree(
        ConstructionEmptyTexts(), ConstructionEmptyKinds())
    ConstructionStampScope(empty, "")
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _emptyPlan := ConstructionRejected(
        empty, ColumnarRangePlannerEmptyBindings(), out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    nulls := ConstructionArrayLiteralTree(
        ConstructionOneText("null"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.NullLiteralExpression()))
    ConstructionStampScope(nulls, "")
    _nullPlan := ConstructionRejected(
        nulls, ColumnarRangePlannerEmptyBindings(), out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    stringAndNull := ConstructionArrayLiteralTree(
        ConstructionTwoTexts("\"value\"", "null"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.StringLiteralExpression(),
            ColumnarExpressionNodeKind.NullLiteralExpression()))
    ConstructionStampScope(stringAndNull, "")
    _mixedNullPlan := ConstructionRejected(
        stringAndNull,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    nullableSized := ConstructionNullableSizedArrayTree("int", "2")
    ConstructionStampScope(nullableSized, "")
    _nullablePlan := ConstructionRejected(
        nullableSized,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    consumer := ConstructionSourceDefinition(
        "ConstructionArrayConsumer", true)
    arrayParameter := new Type[](1)
    arrayParameter[0] = typeof(int[])
    _consume := SourceCallPublicStatic(
        consumer, "Consume", arrayParameter, typeof(int))
    nestedCall := ConstructionDirectCallWithArrayLiteralTree(
        ConstructionEmptyTexts(), ConstructionEmptyKinds())
    ConstructionStampScope(
        nestedCall, "class ConstructionArrayConsumer {}")
    _callPlan := DirectCallRejected(
        nestedCall,
        ConstructionBindings(SourceCallDefinitions(consumer)),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    constructorOwner := ConstructionSourceDefinition(
        "ConstructionArrayConstructorOwner", true)
    _constructor := constructorOwner.DefineUserConstructor(
        arrayParameter, ConstructionDefaults(1), ConstructionDefaultTexts(1))
    nestedConstructor := ConstructionNewWithArrayLiteralTree(
        "ConstructionArrayConstructorOwner",
        ConstructionOneText("null"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.NullLiteralExpression()))
    ConstructionStampScope(
        nestedConstructor,
        "class ConstructionArrayConstructorOwner {}")
    _constructorPlan := ConstructionRejected(
        nestedConstructor,
        ConstructionBindings(SourceCallDefinitions(constructorOwner)),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy
}

test "construction planner rejects malformed admitted array shapes atomically" {
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    mixed := ConstructionArrayLiteralTree(
        ConstructionTwoTexts("1", "\"two\""),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            ColumnarExpressionNodeKind.StringLiteralExpression()))
    ConstructionStampScope(mixed, "")
    _mixedPlan := ConstructionRejected(
        mixed, ColumnarRangePlannerEmptyBindings(), out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    badLength := ConstructionSizedArrayTree(
        "int", "\"three\"",
        ColumnarExpressionNodeKind.StringLiteralExpression())
    ConstructionStampScope(badLength, "")
    _lengthPlan := ConstructionRejected(
        badLength,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    malformedRepeated := ConstructionMalformedRepeatedSizedArrayTree()
    ConstructionStampScope(malformedRepeated, "")
    _malformedPlan := ConstructionRejected(
        malformedRepeated,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner selects source constructors with exact arity before defaults" {
    owner := ConstructionSourceDefinition(
        "ConstructionArityOwner", true)
    exactParameters := new Type[](1)
    exactParameters[0] = typeof(int)
    exactCtor := owner.DefineUserConstructor(
        exactParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))

    defaultParameters := new Type[](2)
    defaultParameters[0] = typeof(int)
    defaultParameters[1] = typeof(string)
    defaultKinds := ConstructionDefaults(2)
    defaultTexts := ConstructionDefaultTexts(2)
    defaultKinds[1] = 4
    defaultTexts[1] = "\"fallback\""
    _defaultCtor := owner.DefineUserConstructor(
        defaultParameters, defaultKinds, defaultTexts)

    tree := ConstructionNewTree(
        "ConstructionArityOwner",
        ConstructionOneText("7"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()))
    ConstructionStampScope(
        tree, "class ConstructionArityOwner {}")
    plan := ConstructionPlan(
        tree, ConstructionBindings(SourceCallDefinitions(owner)))
    assert ColumnarConstructionPlanner.SameObject(
        plan.ResultType, owner.Builder)
    assert plan.ConstructorCount == 1
    assert ColumnarConstructionPlanner.SameObject(
        plan.Constructors[0], exactCtor)
    assert plan.ConstructorParameterTypes[0].Length == 1
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()
}

test "construction planner emits supported source constructor defaults in declaration order" {
    owner := ConstructionSourceDefinition(
        "ConstructionDefaultOwner", true)
    parameters := new Type[](4)
    parameters[0] = typeof(int)
    parameters[1] = typeof(bool)
    parameters[2] = typeof(int)
    parameters[3] = typeof(string)
    defaultKinds := ConstructionDefaults(4)
    defaultTexts := ConstructionDefaultTexts(4)
    defaultKinds[1] = 44
    defaultTexts[1] = "true"
    defaultKinds[2] = 1
    defaultTexts[2] = "19"
    defaultKinds[3] = 4
    defaultTexts[3] = "\"line\\nvalue\""
    constructor := owner.DefineUserConstructor(
        parameters, defaultKinds, defaultTexts)

    tree := ConstructionNewTree(
        "ConstructionDefaultOwner",
        ConstructionOneText("5"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()))
    ConstructionStampScope(
        tree, "class ConstructionDefaultOwner {}")
    plan := ConstructionPlan(
        tree, ConstructionBindings(SourceCallDefinitions(owner)))
    assert plan.OperationCount == 5
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4_1()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.LdcI4()
    assert plan.Int32Values[plan.OperandIndices[2]] == 19
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ldstr()
    assert plan.StringValues[plan.OperandIndices[3]] == "line\nvalue"
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.Newobj()
    assert ColumnarConstructionPlanner.SameObject(
        plan.Constructors[0], constructor)
}

test "construction planner uses unique compatibility and rejects ambiguity and sole mismatch" {
    unique := ConstructionSourceDefinition(
        "ConstructionUniqueOwner", true)
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    stringParameters := new Type[](1)
    stringParameters[0] = typeof(string)
    intCtor := unique.DefineUserConstructor(
        intParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    _stringCtor := unique.DefineUserConstructor(
        stringParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    uniqueTree := ConstructionNewTree(
        "ConstructionUniqueOwner",
        ConstructionOneText("3"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()))
    ConstructionStampScope(
        uniqueTree, "class ConstructionUniqueOwner {}")
    uniquePlan := ConstructionPlan(
        uniqueTree,
        ConstructionBindings(SourceCallDefinitions(unique)))
    assert ColumnarConstructionPlanner.SameObject(
        uniquePlan.Constructors[0], intCtor)

    ambiguous := ConstructionSourceDefinition(
        "ConstructionAmbiguousOwner", true)
    longParameters := new Type[](1)
    longParameters[0] = typeof(long)
    doubleParameters := new Type[](1)
    doubleParameters[0] = typeof(double)
    ambiguous.DefineUserConstructor(
        longParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    ambiguous.DefineUserConstructor(
        doubleParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    ambiguousTree := ConstructionNewTree(
        "ConstructionAmbiguousOwner",
        ConstructionOneText("3"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()))
    ConstructionStampScope(
        ambiguousTree, "class ConstructionAmbiguousOwner {}")
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _ambiguousPlan := ConstructionRejected(
        ambiguousTree,
        ConstructionBindings(SourceCallDefinitions(ambiguous)),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    mismatch := ConstructionSourceDefinition(
        "ConstructionMismatchOwner", true)
    mismatch.DefineUserConstructor(
        stringParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    mismatchTree := ConstructionNewTree(
        "ConstructionMismatchOwner",
        ConstructionOneText("3"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()))
    ConstructionStampScope(
        mismatchTree, "class ConstructionMismatchOwner {}")
    _mismatchPlan := ConstructionRejected(
        mismatchTree,
        ConstructionBindings(SourceCallDefinitions(mismatch)),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner rejects corrupt source constructor facts after complete rollback" {
    owner := ConstructionSourceDefinition(
        "ConstructionCorruptOwner", true)
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    constructor := owner.DefineUserConstructor(
        parameterTypes,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1))
    owner.Constructors.Add(new ColumnarConstructorDef(
        constructor,
        parameterTypes,
        new int[](0),
        new string[](0)))
    tree := ConstructionNewTree(
        "ConstructionCorruptOwner",
        ConstructionOneText("1"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()))
    ConstructionStampScope(
        tree, "class ConstructionCorruptOwner {}")
    plan := new ColumnarCodePlan()
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    resultType := typeof(int)
    assert throws InvalidOperationException {
        ColumnarConstructionPlanner.Plan(
            tree.Nodes,
            tree.Source,
            tree.Root,
            ConstructionBindings(SourceCallDefinitions(owner)),
            plan,
            out ownership,
            out legacy,
            out resultType)
    }
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "construction planner owns exact runtime catalog constructors and executes string construction" {
    repeat := ConstructionNewTree(
        "string",
        ConstructionTwoTexts("'x'", "4"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.CharLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression()))
    ConstructionStampScope(repeat, "")
    repeatPlan := ConstructionPlan(
        repeat, ColumnarRangePlannerEmptyBindings())
    assert repeatPlan.ResultType == typeof(string)
    assert repeatPlan.OperationCount == 3
    assert repeatPlan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
    assert repeatPlan.ConstructorParameterTypes[0].Length == 2
    assert repeatPlan.ConstructorParameterTypes[0][0] == typeof(char)
    assert repeatPlan.ConstructorParameterTypes[0][1] == typeof(int)
    repeatResult := NullableArgumentRunPlan(repeatPlan, typeof(string))
    assert repeatResult != null
    assert repeatResult.ToString() == "xxxx"

    types := new Type[](14)
    counts := new int[](14)
    types[0] = typeof(System.Text.StringBuilder)
    counts[0] = 0
    types[1] = typeof(System.Text.StringBuilder)
    counts[1] = 1
    types[2] = typeof(Version)
    counts[2] = 4
    types[3] = typeof(object)
    counts[3] = 0
    types[4] = typeof(System.Diagnostics.ProcessStartInfo)
    counts[4] = 0
    types[5] = typeof(System.Diagnostics.Process)
    counts[5] = 0
    types[6] = typeof(System.Text.Json.JsonSerializerOptions)
    counts[6] = 0
    types[7] = typeof(System.IO.StreamReader)
    counts[7] = 1
    types[8] = typeof(YamlDotNet.Serialization.DeserializerBuilder)
    counts[8] = 0
    types[9] = typeof(YamlDotNet.Core.Events.Scalar)
    counts[9] = 1
    types[10] = typeof(YamlDotNet.Core.Events.MappingStart)
    counts[10] = 0
    types[11] = typeof(YamlDotNet.Core.Events.MappingEnd)
    counts[11] = 0
    types[12] = typeof(InvalidOperationException)
    counts[12] = 1
    types[13] = typeof(ArgumentException)
    counts[13] = 2

    index := 0
    while index < types.Length {
        constructor: ConstructorInfo? = null
        parameters := new Type[](0)
        assert ColumnarConstructionPlanner.TrySelectRuntimeConstructor(
            types[index], counts[index], out constructor, out parameters)
        assert constructor != null
        assert parameters.Length == counts[index]
        index += 1
    }

    unsupported: ConstructorInfo? = null
    unsupportedParameters := new Type[](0)
    assert !ColumnarConstructionPlanner.TrySelectRuntimeConstructor(
        typeof(Random), 0, out unsupported, out unsupportedParameters)
}

test "construction planner leaves exact excluded construction families to the whole subtree owner" {
    generic := ConstructionGenericNewTree()
    ConstructionStampScope(generic, "import System.Collections.Generic\n")
    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacy := false
    _genericPlan := ConstructionRejected(
        generic,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    valueOwner := ConstructionSourceDefinition(
        "ConstructionDefaultValue", false)
    value := ConstructionNewTree(
        "ConstructionDefaultValue",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds())
    ConstructionStampScope(
        value, "struct ConstructionDefaultValue {}")
    _valuePlan := ConstructionRejected(
        value,
        ConstructionBindings(SourceCallDefinitions(valueOwner)),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    json := ConstructionNewTree(
        "JsonElement",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds())
    ConstructionStampScope(json, "import System.Text.Json\n")
    _jsonPlan := ConstructionRejected(
        json,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy
}

test "construction planner blocks a visible type parameter when its live handle is absent" {
    tree := ConstructionSizedArrayTree(
        "T", "2", ColumnarExpressionNodeKind.IntLiteralExpression())
    visible := new string[](1)
    visible[0] = "T"
    ConstructionStampScopeWithTypeParameters(
        tree, "class T {}", visible)
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _missingPlan := ConstructionRejected(
        tree,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    genericOwner := TypeOfCreateSourceBuilder(
        "ConstructionGenericOwner", true)
    arguments := genericOwner.GetGenericArguments()
    assert arguments.Length == 1
    liveParameterName := arguments[0].Name
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters[liveParameterName] = arguments[0]
    bindings := BindingRawTypeParameters(typeParameters)
    liveTree := ConstructionSizedArrayTree(
        liveParameterName,
        "2",
        ColumnarExpressionNodeKind.IntLiteralExpression())
    liveVisible := new string[](1)
    liveVisible[0] = liveParameterName
    ConstructionStampScopeWithTypeParameters(
        liveTree,
        "class " + liveParameterName + " {}",
        liveVisible)
    livePlan := ConstructionPlan(liveTree, bindings)
    assert livePlan.ResultType.get_IsSZArray()
    assert ColumnarConstructionPlanner.SameObject(
        livePlan.ResultType.GetElementType(), arguments[0])
    assert ColumnarConstructionPlanner.SameObject(
        livePlan.Types[livePlan.OperandIndices[1]], arguments[0])
}

test "construction planner resolves exact aliases and nested live type parameter arrays" {
    alias := ConstructionNewTree(
        "BuilderAlias",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds())
    ConstructionStampScope(
        alias,
        "import System.Text\ntype BuilderAlias = StringBuilder\n")
    aliasPlan := ConstructionPlan(
        alias, ColumnarRangePlannerEmptyBindings())
    assert aliasPlan.ResultType == typeof(System.Text.StringBuilder),
        "exact alias result type"
    assert aliasPlan.ConstructorDeclaringTypes[0]
        == typeof(System.Text.StringBuilder),
        "exact alias constructor owner"

    genericOwner := TypeOfCreateSourceBuilder(
        "ConstructionNestedGenericOwner", true)
    arguments := genericOwner.GetGenericArguments()
    assert arguments.Length == 1, "generic fixture arity"
    parameterName := arguments[0].Name
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters[parameterName] = arguments[0]
    bindings := BindingRawTypeParameters(typeParameters)
    visible := new string[](1)
    visible[0] = parameterName
    nested := ConstructionNestedSizedArrayTree(parameterName, "2")
    ConstructionStampScopeWithTypeParameters(
        nested,
        "class " + parameterName + " {}",
        visible)
    nestedPlan := ConstructionPlan(nested, bindings)
    assert nestedPlan.ResultType.get_IsSZArray(), "outer array result"
    firstElement := nestedPlan.ResultType.GetElementType()
    if firstElement == null {
        throw new InvalidOperationException(
            "Nested generic array did not retain its element type.")
    }
    assert firstElement.get_IsSZArray(), "inner array result"
    assert ColumnarConstructionPlanner.SameObject(
        firstElement.GetElementType(), arguments[0]),
        "live generic element identity"
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        nestedPlan.Types[nestedPlan.OperandIndices[1]], firstElement),
        "newarr operand identity"
}

test "construction planner fences source unions and unsupported runtime constructors" {
    unionBuilder := TypeOfCreateSourceBuilder(
        "ConstructionUnion", false)
    unionDefinition := new ColumnarUnionDef(
        unionBuilder, 0, "ConstructionUnion")
    unionBindings := ColumnarRangePlannerEmptyBindings()
    unions := new List<ColumnarUnionDef>()
    unions.Add(unionDefinition)
    unionBindings.SourceUnionDefinitions = unions
    unionTree := ConstructionNewTree(
        "ConstructionUnion",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds())
    ConstructionStampScope(unionTree, "union ConstructionUnion {}")
    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacy := false
    _unionPlan := ConstructionRejected(
        unionTree, unionBindings, out ownership, out legacy)
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    randomTree := ConstructionNewTree(
        "Random",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds())
    ConstructionStampScope(randomTree, "import System\n")
    _randomPlan := ConstructionRejected(
        randomTree,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy)
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction TryGetType seals valid plans and rolls invalid plans back without execution" {
    valid := ConstructionNewTree(
        "string",
        ConstructionTwoTexts("'q'", "2"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.CharLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression()))
    ConstructionStampScope(valid, "")
    validPlan := new ColumnarCodePlan()
    owned := false
    legacy := false
    resultType := typeof(int)
    assert ColumnarConstructionPlanner.TryGetType(
        valid.Nodes,
        valid.Source,
        valid.Root,
        ColumnarRangePlannerEmptyBindings(),
        validPlan,
        out owned,
        out legacy,
        out resultType)
    assert owned
    assert !legacy
    assert resultType == typeof(string)
    assert validPlan.Status == ColumnarFragmentPlanStatus.Planned
    assert validPlan.Lifecycle == ColumnarCodePlanLifecycle.Sealed
    ColumnarCodePlanExecutor.Validate(validPlan)

    invalid := ConstructionArrayLiteralTree(
        ConstructionTwoTexts("1", "\"x\""),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            ColumnarExpressionNodeKind.StringLiteralExpression()))
    ConstructionStampScope(invalid, "")
    invalidPlan := new ColumnarCodePlan()
    owned = false
    legacy = false
    resultType = typeof(int)
    assert !ColumnarConstructionPlanner.TryGetType(
        invalid.Nodes,
        invalid.Source,
        invalid.Root,
        ColumnarRangePlannerEmptyBindings(),
        invalidPlan,
        out owned,
        out legacy,
        out resultType)
    assert owned
    assert !legacy
    ColumnarRangePlannerAssertEmptyRollback(invalidPlan)
}

test "direct-call argument planning admits nested exact construction" {
    consumer := ConstructionSourceDefinition(
        "ConstructionConsumer", true)
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    target := SourceCallPublicStatic(
        consumer, "Consume", parameterTypes, typeof(string))
    tree := ConstructionNestedDirectCallTree()
    ConstructionStampScope(
        tree, "class ConstructionConsumer {}")
    plan := DirectCallPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(consumer)))
    assert plan.ResultType == typeof(string)
    assert plan.ConstructorCount == 1
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Call()
    assert ColumnarConstructionPlanner.SameObject(
        plan.Methods[plan.OperandIndices[3]], target.Builder)
}

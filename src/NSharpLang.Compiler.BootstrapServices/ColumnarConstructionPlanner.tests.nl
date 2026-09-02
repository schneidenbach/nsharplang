namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

enum ConstructionPlannerDefaultState {
    Unknown,
    Ready
}

enum ConstructionPlannerOtherDefaultState {
    Unknown,
    Ready
}

func ConstructionNewTree(
    typeName: string,
    argumentTexts: string[],
    argumentKinds: int[]
): ColumnarRangePlannerTestTree {
    if argumentTexts.Length != argumentKinds.Length {
        throw new InvalidOperationException(
            "Construction argument text and kind columns must match."
        )
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    typeNode := builder.AddLeaf(0, typeName)
    children := new int[](argumentTexts.Length + 1)
    children[0] = typeNode
    index := 0
    while index < argumentTexts.Length {
        children[index + 1] = builder.AddLeaf(
            argumentKinds[index],
            argumentTexts[index]
        )
        index += 1
    }
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        children
    )
    return builder.Build(root)
}

func ConstructionObjectInitializerTree(
    typeName: string,
    memberNames: string[],
    valueTexts: string[],
    valueKinds: int[]
): ColumnarRangePlannerTestTree {
    if memberNames.Length != valueTexts.Length || memberNames.Length != valueKinds.Length {
        throw new InvalidOperationException(
            "Object-initializer member and value columns must match."
        )
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    typeNode := builder.AddLeaf(0, typeName)
    children := new int[](1 + memberNames.Length * 2)
    children[0] = typeNode
    index := 0
    while index < memberNames.Length {
        children[index * 2 + 1] = builder.AddLeaf(
            ColumnarExpressionNodeKind.IdentifierExpression(),
            memberNames[index]
        )
        children[index * 2 + 2] = builder.AddLeaf(
            valueKinds[index],
            valueTexts[index]
        )
        index += 1
    }
    root := builder.AddNode(
        ColumnarExpressionNodeKind.ObjectInitializerExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        children
    )
    return builder.Build(root)
}

func ConstructionObjectInitializerFromNewTree(
    typeName: string,
    memberName: string,
    valueText: string,
    valueKind: int
): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    typeNode := builder.AddLeaf(0, typeName)
    constructed := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(typeNode)
    )
    member := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        memberName
    )
    value := builder.AddLeaf(valueKind, valueText)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.ObjectInitializerExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren3(constructed, member, value)
    )
    return builder.Build(root)
}

func ConstructionNestedObjectInitializerTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    outerType := builder.AddLeaf(0, "ConstructionNestedOuter")
    outerMember := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "Inner"
    )
    innerType := builder.AddLeaf(0, "ConstructionNestedInner")
    innerMember := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "Value"
    )
    innerValue := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "42"
    )
    inner := builder.AddNode(
        ColumnarExpressionNodeKind.ObjectInitializerExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren3(
            innerType,
            innerMember,
            innerValue
        )
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.ObjectInitializerExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren3(
            outerType,
            outerMember,
            inner
        )
    )
    return builder.Build(root)
}

func ConstructionNegativeObjectInitializerTree(
    typeName: string,
    memberName: string,
    magnitudeText: string
): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    typeNode := builder.AddLeaf(0, typeName)
    member := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        memberName
    )
    minusStart := builder.AddToken("-")
    magnitude := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        magnitudeText
    )
    negative := builder.AddNode(
        ColumnarExpressionNodeKind.UnaryExpression(),
        minusStart,
        1,
        minusStart,
        1 + magnitudeText.Length,
        ColumnarRangePlannerChildren1(magnitude)
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.ObjectInitializerExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren3(typeNode, member, negative)
    )
    return builder.Build(root)
}

func ConstructionSizedArrayTree(
    elementName: string,
    lengthText: string,
    lengthKind: int
): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    element := builder.AddLeaf(0, elementName)
    arrayType := builder.AddNode(
        2,
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(element)
    )
    length := builder.AddLeaf(lengthKind, lengthText)
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(arrayType, length)
    )
    return builder.Build(root)
}

func ConstructionNullableSizedArrayTree(
    elementName: string,
    lengthText: string
): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    element := builder.AddLeaf(0, elementName)
    nullableElement := builder.AddNode(
        3,
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(element)
    )
    arrayType := builder.AddNode(
        2,
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(nullableElement)
    )
    length := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        lengthText
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(arrayType, length)
    )
    return builder.Build(root)
}

func ConstructionMalformedRepeatedSizedArrayTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    malformedElement := builder.AddNode(
        2,
        -1,
        0,
        0,
        builder.Source.Length,
        new int[](0)
    )
    arrayType := builder.AddNode(
        2,
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(malformedElement)
    )
    length := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "2"
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(arrayType, length)
    )
    return builder.Build(root)
}

func ConstructionNestedSizedArrayTree(
    elementName: string,
    lengthText: string
): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    element := builder.AddLeaf(0, elementName)
    innerArray := builder.AddNode(
        2,
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(element)
    )
    outerArray := builder.AddNode(
        2,
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(innerArray)
    )
    length := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        lengthText
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(outerArray, length)
    )
    return builder.Build(root)
}

func ConstructionNestedDirectCallTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "ConstructionConsumer"
    )
    member := DirectCallAppendMember(builder, owner, "Consume")
    stringType := builder.AddLeaf(0, "string")
    character := builder.AddLeaf(
        ColumnarExpressionNodeKind.CharLiteralExpression(),
        "'z'"
    )
    count := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "2"
    )
    nested := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren3(stringType, character, count)
    )
    root := DirectCallAppendCall(
        builder,
        member,
        DirectCallOneArgument(nested)
    )
    return builder.Build(root)
}

func ConstructionNestedGenericDirectCallTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "ConstructionGenericConsumer"
    )
    member := DirectCallAppendMember(builder, owner, "Consume")
    typeStart := builder.AddToken("List")
    argumentType := builder.AddLeaf(0, "int")
    genericType := builder.AddNode(
        1,
        typeStart,
        4,
        typeStart,
        builder.Source.Length - typeStart,
        ColumnarRangePlannerChildren1(argumentType)
    )
    nested := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        typeStart,
        builder.Source.Length - typeStart,
        ColumnarRangePlannerChildren1(genericType)
    )
    root := DirectCallAppendCall(
        builder,
        member,
        DirectCallOneArgument(nested)
    )
    return builder.Build(root)
}

func ConstructionNewWithNestedGenericTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    outerType := builder.AddLeaf(0, "ConstructionGenericCtorConsumer")
    typeStart := builder.AddToken("List")
    argumentType := builder.AddLeaf(0, "int")
    genericType := builder.AddNode(
        1,
        typeStart,
        4,
        typeStart,
        builder.Source.Length - typeStart,
        ColumnarRangePlannerChildren1(argumentType)
    )
    nested := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        typeStart,
        builder.Source.Length - typeStart,
        ColumnarRangePlannerChildren1(genericType)
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(outerType, nested)
    )
    return builder.Build(root)
}

func ConstructionDirectCallWithArrayLiteralTree(
    elementTexts: string[],
    elementKinds: int[]
): ColumnarRangePlannerTestTree {
    if elementTexts.Length != elementKinds.Length {
        throw new InvalidOperationException(
            "Nested array-literal text and kind columns must match."
        )
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        "ConstructionArrayConsumer"
    )
    member := DirectCallAppendMember(builder, owner, "Consume")
    elements := new int[](elementTexts.Length)
    index := 0
    while index < elements.Length {
        elements[index] = builder.AddLeaf(
            elementKinds[index],
            elementTexts[index]
        )
        index += 1
    }
    array := builder.AddNode(
        ColumnarExpressionNodeKind.ArrayLiteralExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        elements
    )
    root := DirectCallAppendCall(
        builder,
        member,
        DirectCallOneArgument(array)
    )
    return builder.Build(root)
}

func ConstructionNewWithArrayLiteralTree(
    typeName: string,
    elementTexts: string[],
    elementKinds: int[]
): ColumnarRangePlannerTestTree {
    if elementTexts.Length != elementKinds.Length {
        throw new InvalidOperationException(
            "Nested constructor array text and kind columns must match."
        )
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    typeNode := builder.AddLeaf(0, typeName)
    elements := new int[](elementTexts.Length)
    index := 0
    while index < elements.Length {
        elements[index] = builder.AddLeaf(
            elementKinds[index],
            elementTexts[index]
        )
        index += 1
    }
    array := builder.AddNode(
        ColumnarExpressionNodeKind.ArrayLiteralExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        elements
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(typeNode, array)
    )
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
        ColumnarRangePlannerChildren1(argumentType)
    )
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(genericType)
    )
    return builder.Build(root)
}

func ConstructionExplicitGenericNewTree(
    typeName: string,
    typeArgumentNames: string[],
    argumentTexts: string[],
    argumentKinds: int[]
): ColumnarRangePlannerTestTree {
    if typeArgumentNames.Length == 0 || argumentTexts.Length != argumentKinds.Length {
        throw new InvalidOperationException(
            "Explicit generic construction columns are invalid."
        )
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    typeStart := builder.AddToken(typeName)
    typeArguments := new int[](typeArgumentNames.Length)
    index := 0
    while index < typeArguments.Length {
        typeArguments[index] = builder.AddLeaf(0, typeArgumentNames[index])
        index += 1
    }
    genericType := builder.AddNode(
        1,
        typeStart,
        typeName.Length,
        typeStart,
        builder.Source.Length - typeStart,
        typeArguments
    )
    children := new int[](argumentTexts.Length + 1)
    children[0] = genericType
    index = 0
    while index < argumentTexts.Length {
        children[index + 1] = builder.AddLeaf(
            argumentKinds[index],
            argumentTexts[index]
        )
        index += 1
    }
    root := builder.AddNode(
        ColumnarExpressionNodeKind.NewExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        children
    )
    return builder.Build(root)
}

func ConstructionArrayLiteralTree(
    elementTexts: string[],
    elementKinds: int[]
): ColumnarRangePlannerTestTree {
    if elementTexts.Length != elementKinds.Length {
        throw new InvalidOperationException(
            "Array-literal text and kind columns must match."
        )
    }
    builder := new ColumnarRangePlannerNodeBuilder()
    children := new int[](elementTexts.Length)
    index := 0
    while index < elementTexts.Length {
        children[index] = builder.AddLeaf(
            elementKinds[index],
            elementTexts[index]
        )
        index += 1
    }
    root := builder.AddNode(
        ColumnarExpressionNodeKind.ArrayLiteralExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        children
    )
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
    third: string
): string[] {
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
    factSource: string
) {
    ExternalStampScopeFull(
        tree,
        factSource,
        "",
        new string[](0),
        ExternalEmptyStructs(),
        null
    )
}

func ConstructionStampScopeFromFiles(
    tree: ColumnarRangePlannerTestTree,
    sources: string[],
    fileNames: string[],
    activeSourceFileId: int
) {
    scope := ColumnarBindingScopeFacts.Create(
        ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames),
        ExternalEmptyEnums(),
        ExternalEmptyStructs(),
        ExternalEmptyUnions(),
        ExternalEmptyInterfaces(),
        null
    )
    scope.PrepareExternalTypeBindings(null)
    tree.Nodes.SetBindingContext(
        scope.ForSourceFile(activeSourceFileId),
        "",
        new string[](0),
        new string[](0)
    )
}

func ConstructionStampScopeWithTypeParameters(
    tree: ColumnarRangePlannerTestTree,
    factSource: string,
    visibleTypeParameters: string[]
) {
    ExternalStampScopeFull(
        tree,
        factSource,
        "",
        visibleTypeParameters,
        ExternalEmptyStructs(),
        null
    )
}

func ConstructionPlan(
    tree: ColumnarRangePlannerTestTree,
    bindings: ColumnarFragmentBindings
): ColumnarCodePlan {
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
        out resultType
    )
    if status != ColumnarFragmentPlanStatus.Planned || ownership != ColumnarDirectCallOwnership.Planned || legacyWholeSubtreePlanning {
        throw new InvalidOperationException(
            "Expected construction planner ownership."
        )
    }
    assert plan.ResultType == resultType
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func ConstructionRejected(
    tree: ColumnarRangePlannerTestTree,
    bindings: ColumnarFragmentBindings,
    out ownership: ColumnarDirectCallOwnership,
    out legacyWholeSubtreePlanning: bool
): ColumnarCodePlan {
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
        out resultType
    )
    assert status == ColumnarFragmentPlanStatus.NotOwned
    ColumnarRangePlannerAssertEmptyRollback(plan)
    return plan
}

func ConstructionBindings(
    definitions: ColumnarStructDef[]
): ColumnarFragmentBindings {
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceTypeDefinitions = definitions
    return bindings
}

func ConstructionSourceDefinition(
    name: string,
    isReference: bool
): ColumnarStructDef {
    return SourceCallDefinition(name, isReference)
}

func ConstructionDefinePublicField(
    owner: TypeBuilder,
    name: string,
    fieldType: Type
): FieldBuilder {
    return ConstructionDefineField(owner, name, fieldType, 6)
}

func ConstructionDefineInitOnlyField(
    owner: TypeBuilder,
    name: string,
    fieldType: Type
): FieldBuilder {
    return ConstructionDefineField(owner, name, fieldType, 38)
}

func ConstructionDefineField(
    owner: TypeBuilder,
    name: string,
    fieldType: Type,
    attributes: int
): FieldBuilder {
    parameterTypes := new Type[](3)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(Type)
    fieldAttributesType := TypeOfRequiredRuntimeType(
        typeof(TypeBuilder),
        "System.Reflection.FieldAttributes"
    )
    parameterTypes[2] = fieldAttributesType
    defineField := ExecutorRequiredMethod(
        typeof(TypeBuilder),
        "DefineField",
        parameterTypes
    )
    arguments := new object[](3)
    ExecutorSetObject(arguments, 0, name)
    ExecutorSetObject(arguments, 1, fieldType)
    ExecutorSetObject(
        arguments,
        2,
        (FieldAttributes)attributes
    )
    value := TypeOfRequiredInvocation(defineField, owner, arguments)
    field := value as FieldBuilder
    if field == null {
        throw new InvalidOperationException(
            "The object-initializer fixture field was not defined."
        )
    }
    return field
}

func ConstructionSetParent(owner: TypeBuilder, parent: Type) {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(Type)
    setParent := ExecutorRequiredMethod(
        typeof(TypeBuilder),
        "SetParent",
        parameterTypes
    )
    wrapperParameters := new Type[](2)
    wrapperParameters[0] = typeof(TypeBuilder)
    wrapperParameters[1] = typeof(Type)
    wrapper := BoundDynamicMethod(
        "ConstructionSetObjectInitializerParent",
        typeof(int),
        wrapperParameters
    )
    il := wrapper.GetILGenerator()
    il.Emit(OpCodes.Ldarg, (short)0)
    il.Emit(OpCodes.Ldarg, (short)1)
    il.Emit(OpCodes.Callvirt, setParent)
    il.Emit(OpCodes.Ldc_I4_0)
    il.Emit(OpCodes.Ret)
    arguments := new object[](2)
    ExecutorSetObject(arguments, 0, owner)
    ExecutorSetObject(arguments, 1, parent)
    target: object? = null
    result := wrapper.Invoke(target, arguments)
    if result == null {
        throw new InvalidOperationException(
            "The object-initializer fixture parent was not installed."
        )
    }
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
    opCode: short
): bool {
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
        "int",
        "3",
        ColumnarExpressionNodeKind.IntLiteralExpression()
    )
    ConstructionStampScope(sized, "")
    sizedPlan := ConstructionPlan(
        sized,
        ColumnarRangePlannerEmptyBindings()
    )
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
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(ints, "")
    intPlan := ConstructionPlan(
        ints,
        ColumnarRangePlannerEmptyBindings()
    )
    assert intPlan.ResultType == typeof(int[])
    assert intPlan.OperationCount == 14
    assert intPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert intPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newarr()
    assert ConstructionHasOpcode(intPlan, ColumnarCodePlanContract.Dup())
    assert ConstructionHasOpcode(
        intPlan,
        ColumnarCodePlanContract.StelemI4()
    )

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
            ConstructionTwoKinds(kinds[index], kinds[index])
        )
        ConstructionStampScope(tree, "")
        plan := ConstructionPlan(tree, bindings)
        assert plan.ResultType != null
        assert plan.ResultType.get_IsSZArray()
        assert plan.ResultType.GetElementType() == expectedTypes[index]
        assert ConstructionHasOpcode(plan, expectedOpcodes[index])
        index += 1
    }

    valueDefinition := ConstructionSourceDefinition(
        "ConstructionArrayValue",
        false
    )
    valueBindings := ConstructionBindings(
        SourceCallDefinitions(valueDefinition)
    )
    valueBindings.ParameterOrdinals["value"] = 0
    valueBindings.ParameterTypes["value"] = valueDefinition.Builder
    valueTree := ConstructionArrayLiteralTree(
        ConstructionTwoTexts("value", "value"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.IdentifierExpression(),
            ColumnarExpressionNodeKind.IdentifierExpression()
        )
    )
    ConstructionStampScope(
        valueTree,
        "struct ConstructionArrayValue {}"
    )
    valuePlan := ConstructionPlan(valueTree, valueBindings)
    assert ConstructionHasOpcode(
        valuePlan,
        ColumnarCodePlanContract.Stelem()
    )
    typedOperation := valuePlan.OperationCount - 1
    assert ColumnarConstructionPlanner.SameObject(
        valuePlan.Types[valuePlan.OperandIndices[typedOperation]],
        valueDefinition.Builder
    )
}

test "construction planner defers contextual array shapes as whole subtrees" {
    empty := ConstructionArrayLiteralTree(
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(empty, "")
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _emptyPlan := ConstructionRejected(
        empty,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    nulls := ConstructionArrayLiteralTree(
        ConstructionOneText("null"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.NullLiteralExpression()
        )
    )
    ConstructionStampScope(nulls, "")
    _nullPlan := ConstructionRejected(
        nulls,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    stringAndNull := ConstructionArrayLiteralTree(
        ConstructionTwoTexts("\"value\"", "null"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.StringLiteralExpression(),
            ColumnarExpressionNodeKind.NullLiteralExpression()
        )
    )
    ConstructionStampScope(stringAndNull, "")
    _mixedNullPlan := ConstructionRejected(
        stringAndNull,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    nullableSized := ConstructionNullableSizedArrayTree("int", "2")
    ConstructionStampScope(nullableSized, "")
    _nullablePlan := ConstructionRejected(
        nullableSized,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    consumer := ConstructionSourceDefinition(
        "ConstructionArrayConsumer",
        true
    )
    arrayParameter := new Type[](1)
    arrayParameter[0] = typeof(int[])
    _consume := SourceCallPublicStatic(
        consumer,
        "Consume",
        arrayParameter,
        typeof(int)
    )
    nestedCall := ConstructionDirectCallWithArrayLiteralTree(
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        nestedCall,
        "class ConstructionArrayConsumer {}"
    )
    _callPlan := DirectCallRejected(
        nestedCall,
        ConstructionBindings(SourceCallDefinitions(consumer)),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.NotOwned
    assert legacy

    constructorOwner := ConstructionSourceDefinition(
        "ConstructionArrayConstructorOwner",
        true
    )
    _constructor := constructorOwner.DefineUserConstructor(
        arrayParameter,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    nestedConstructor := ConstructionNewWithArrayLiteralTree(
        "ConstructionArrayConstructorOwner",
        ConstructionOneText("null"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.NullLiteralExpression()
        )
    )
    ConstructionStampScope(
        nestedConstructor,
        "class ConstructionArrayConstructorOwner {}"
    )
    _constructorPlan := ConstructionRejected(
        nestedConstructor,
        ConstructionBindings(SourceCallDefinitions(constructorOwner)),
        out ownership,
        out legacy
    )
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
            ColumnarExpressionNodeKind.StringLiteralExpression()
        )
    )
    ConstructionStampScope(mixed, "")
    _mixedPlan := ConstructionRejected(
        mixed,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    badLength := ConstructionSizedArrayTree(
        "int",
        "\"three\"",
        ColumnarExpressionNodeKind.StringLiteralExpression()
    )
    ConstructionStampScope(badLength, "")
    _lengthPlan := ConstructionRejected(
        badLength,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    malformedRepeated := ConstructionMalformedRepeatedSizedArrayTree()
    ConstructionStampScope(malformedRepeated, "")
    _malformedPlan := ConstructionRejected(
        malformedRepeated,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner selects source constructors with exact arity before defaults" {
    owner := ConstructionSourceDefinition(
        "ConstructionArityOwner",
        true
    )
    exactParameters := new Type[](1)
    exactParameters[0] = typeof(int)
    exactCtor := owner.DefineUserConstructor(
        exactParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )

    defaultParameters := new Type[](2)
    defaultParameters[0] = typeof(int)
    defaultParameters[1] = typeof(string)
    defaultKinds := ConstructionDefaults(2)
    defaultTexts := ConstructionDefaultTexts(2)
    defaultKinds[1] = 4
    defaultTexts[1] = "\"fallback\""
    _defaultCtor := owner.DefineUserConstructor(
        defaultParameters,
        defaultKinds,
        defaultTexts
    )

    tree := ConstructionNewTree(
        "ConstructionArityOwner",
        ConstructionOneText("7"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionArityOwner {}"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner))
    )
    assert ColumnarConstructionPlanner.SameObject(
        plan.ResultType,
        owner.Builder
    )
    assert plan.ConstructorCount == 1
    assert ColumnarConstructionPlanner.SameObject(
        plan.Constructors[0],
        exactCtor
    )
    assert plan.ConstructorParameterTypes[0].Length == 1
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()
}

test "construction planner prefers identity source constructors in either declaration order" {
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    longParameters := new Type[](1)
    longParameters[0] = typeof(long)

    wideningFirst := ConstructionSourceDefinition(
        "ConstructionWideningFirstOwner",
        true
    )
    wideningFirst.DefineUserConstructor(
        longParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    wideningFirstIdentity := wideningFirst.DefineUserConstructor(
        intParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    wideningFirstTree := ConstructionNewTree(
        "ConstructionWideningFirstOwner",
        ConstructionOneText("7"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        wideningFirstTree,
        "class ConstructionWideningFirstOwner {}"
    )
    wideningFirstPlan := ConstructionPlan(
        wideningFirstTree,
        ConstructionBindings(SourceCallDefinitions(wideningFirst))
    )
    assert ColumnarConstructionPlanner.SameObject(
        wideningFirstPlan.Constructors[0],
        wideningFirstIdentity
    )
    assert wideningFirstPlan.ConstructorParameterTypes[0][0] == typeof(int)

    identityFirst := ConstructionSourceDefinition(
        "ConstructionIdentityFirstOwner",
        true
    )
    identityFirstIdentity := identityFirst.DefineUserConstructor(
        intParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    identityFirst.DefineUserConstructor(
        longParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    identityFirstTree := ConstructionNewTree(
        "ConstructionIdentityFirstOwner",
        ConstructionOneText("7"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        identityFirstTree,
        "class ConstructionIdentityFirstOwner {}"
    )
    identityFirstPlan := ConstructionPlan(
        identityFirstTree,
        ConstructionBindings(SourceCallDefinitions(identityFirst))
    )
    assert ColumnarConstructionPlanner.SameObject(
        identityFirstPlan.Constructors[0],
        identityFirstIdentity
    )
    assert identityFirstPlan.ConstructorParameterTypes[0][0] == typeof(int)
}

test "construction planner rejects equal best constructor ties in either order after rollback" {
    longParameters := new Type[](1)
    longParameters[0] = typeof(long)
    doubleParameters := new Type[](1)
    doubleParameters[0] = typeof(double)

    longFirst := ConstructionSourceDefinition(
        "ConstructionLongFirstTieOwner",
        true
    )
    longFirst.DefineUserConstructor(
        longParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    longFirst.DefineUserConstructor(
        doubleParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    longFirstTree := ConstructionNewTree(
        "ConstructionLongFirstTieOwner",
        ConstructionOneText("7"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        longFirstTree,
        "class ConstructionLongFirstTieOwner {}"
    )
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _longFirstPlan := ConstructionRejected(
        longFirstTree,
        ConstructionBindings(SourceCallDefinitions(longFirst)),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    doubleFirst := ConstructionSourceDefinition(
        "ConstructionDoubleFirstTieOwner",
        true
    )
    doubleFirst.DefineUserConstructor(
        doubleParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    doubleFirst.DefineUserConstructor(
        longParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    doubleFirstTree := ConstructionNewTree(
        "ConstructionDoubleFirstTieOwner",
        ConstructionOneText("7"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        doubleFirstTree,
        "class ConstructionDoubleFirstTieOwner {}"
    )
    _doubleFirstPlan := ConstructionRejected(
        doubleFirstTree,
        ConstructionBindings(SourceCallDefinitions(doubleFirst)),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner emits supported source constructor defaults in declaration order" {
    owner := ConstructionSourceDefinition(
        "ConstructionDefaultOwner",
        true
    )
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
        parameters,
        defaultKinds,
        defaultTexts
    )

    tree := ConstructionNewTree(
        "ConstructionDefaultOwner",
        ConstructionOneText("5"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionDefaultOwner {}"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner))
    )
    assert plan.OperationCount == 5
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4_1()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.LdcI4()
    assert plan.Int32Values[plan.OperandIndices[2]] == 19
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ldstr()
    assert plan.StringValues[plan.OperandIndices[3]] == "line\nvalue"
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.Newobj()
    assert ColumnarConstructionPlanner.SameObject(
        plan.Constructors[0],
        constructor
    )
}

test "construction planner emits dotted enum member constructor defaults" {
    owner := ConstructionSourceDefinition(
        "ConstructionEnumDefaultOwner",
        true
    )
    parameters := new Type[](2)
    parameters[0] = typeof(int)
    parameters[1] = typeof(ConstructionPlannerDefaultState)
    defaultKinds := ConstructionDefaults(2)
    defaultTexts := ConstructionDefaultTexts(2)
    defaultKinds[1] = 1000
    defaultTexts[1] = "ConstructionPlannerDefaultState.Ready"
    constructor := owner.DefineUserConstructor(
        parameters,
        defaultKinds,
        defaultTexts
    )

    constants := new Dictionary<string, int>(StringComparer.Ordinal)
    constants["Unknown"] = 0
    constants["Ready"] = 1
    bindings := ConstructionBindings(SourceCallDefinitions(owner))
    bindings.Enums["ConstructionPlannerDefaultState"] = new ColumnarEnumDef(
        typeof(ConstructionPlannerDefaultState),
        constants
    )

    tree := ConstructionNewTree(
        "ConstructionEnumDefaultOwner",
        ConstructionOneText("5"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionEnumDefaultOwner {}"
    )
    plan := ConstructionPlan(tree, bindings)

    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4()
    assert plan.Int32Values[plan.OperandIndices[1]] == 1
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
    assert ColumnarConstructionPlanner.SameObject(
        plan.Constructors[0],
        constructor
    )
}

test "construction planner resolves aliased enum defaults before registry short names" {
    owner := ConstructionSourceDefinition(
        "ConstructionAliasEnumDefaultOwner",
        true
    )
    parameters := new Type[](2)
    parameters[0] = typeof(int)
    parameters[1] = typeof(ConstructionPlannerDefaultState)
    defaultKinds := ConstructionDefaults(2)
    defaultTexts := ConstructionDefaultTexts(2)
    defaultKinds[1] = 1000
    defaultTexts[1] = "R.State.Ready"
    owner.DefineUserConstructor(
        parameters,
        defaultKinds,
        defaultTexts
    )

    leftConstants := new Dictionary<string, int>(StringComparer.Ordinal)
    leftConstants["Ready"] = 1
    leftDefinition := new ColumnarEnumDef(
        typeof(ConstructionPlannerOtherDefaultState),
        leftConstants,
        null,
        "Left.State"
    )
    rightConstants := new Dictionary<string, int>(StringComparer.Ordinal)
    rightConstants["Ready"] = 1
    rightDefinition := new ColumnarEnumDef(
        typeof(ConstructionPlannerDefaultState),
        rightConstants,
        null,
        "Right.State"
    )

    bindings := ConstructionBindings(SourceCallDefinitions(owner))
    bindings.Enums["State"] = leftDefinition
    bindings.Enums["Left.State"] = leftDefinition
    bindings.Enums["Right.State"] = rightDefinition

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nenum State { Ready }\n"
    sources[1] = "namespace Right\nenum State { Ready }\n"
    sources[2] = "import Left\nimport Right as R\nclass ConstructionAliasEnumDefaultOwner {}\n"
    fileNames[0] = "left-state.nl"
    fileNames[1] = "right-state.nl"
    fileNames[2] = "enum-default-caller.nl"

    tree := ConstructionNewTree(
        "ConstructionAliasEnumDefaultOwner",
        ConstructionOneText("5"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScopeFromFiles(tree, sources, fileNames, 2)
    plan := ConstructionPlan(tree, bindings)

    assert plan.OperationCount == 3
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdcI4()
    assert plan.Int32Values[plan.OperandIndices[1]] == 1
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
}

test "construction planner preserves aliased string enum default identity after CLR erasure" {
    owner := ConstructionSourceDefinition(
        "ConstructionStringEnumDefaultOwner",
        true
    )
    parameters := new Type[](2)
    parameters[0] = typeof(int)
    parameters[1] = typeof(string)
    defaultKinds := ConstructionDefaults(2)
    defaultTexts := ConstructionDefaultTexts(2)
    defaultKinds[1] = 1000
    defaultTexts[1] = "R.State.Ready"
    owner.DefineUserConstructor(
        parameters,
        defaultKinds,
        defaultTexts
    )

    leftStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    leftStrings["Ready"] = "left"
    leftDefinition := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        leftStrings,
        "Left.State"
    )
    rightStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    rightStrings["Ready"] = "right"
    rightDefinition := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        rightStrings,
        "Right.State"
    )

    bindings := ConstructionBindings(SourceCallDefinitions(owner))
    bindings.Enums["State"] = leftDefinition
    bindings.Enums["Left.State"] = leftDefinition
    bindings.Enums["Right.State"] = rightDefinition

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nenum State: string { Ready = \"left\" }\n"
    sources[1] = "namespace Right\nenum State: string { Ready = \"right\" }\n"
    sources[2] = "import Left\nimport Right as R\nclass ConstructionStringEnumDefaultOwner {}\n"
    fileNames[0] = "left-string-state.nl"
    fileNames[1] = "right-string-state.nl"
    fileNames[2] = "string-enum-default-caller.nl"

    tree := ConstructionNewTree(
        "ConstructionStringEnumDefaultOwner",
        ConstructionOneText("5"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScopeFromFiles(tree, sources, fileNames, 2)
    plan := ConstructionPlan(tree, bindings)

    assert plan.OperationCount == 3
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldstr()
    assert plan.StringValues[plan.OperandIndices[1]] == "right"
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
}

test "construction planner does not rebind canonical enum defaults in caller scope" {
    owner := ConstructionSourceDefinition(
        "ConstructionCanonicalStringEnumDefaultOwner",
        true
    )
    parameters := new Type[](2)
    parameters[0] = typeof(int)
    parameters[1] = typeof(string)
    defaultKinds := ConstructionDefaults(2)
    defaultTexts := ConstructionDefaultTexts(2)
    defaultKinds[1] = 1000
    defaultTexts[1] = "Right.State.Ready"
    owner.DefineUserConstructor(
        parameters,
        defaultKinds,
        defaultTexts
    )

    leftStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    leftStrings["Ready"] = "left"
    leftDefinition := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        leftStrings,
        "Left.State"
    )
    rightStrings := new Dictionary<string, string>(StringComparer.Ordinal)
    rightStrings["Ready"] = "right"
    rightDefinition := new ColumnarEnumDef(
        typeof(string),
        new Dictionary<string, int>(StringComparer.Ordinal),
        rightStrings,
        "Right.State"
    )

    bindings := ConstructionBindings(SourceCallDefinitions(owner))
    bindings.Enums["State"] = leftDefinition
    bindings.Enums["Left.State"] = leftDefinition
    bindings.Enums["Right.State"] = rightDefinition

    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "namespace Left\nenum State: string { Ready = \"left\" }\n"
    sources[1] = "namespace Right\nenum State: string { Ready = \"right\" }\n"
    sources[2] = "import Left\nclass ConstructionCanonicalStringEnumDefaultOwner {}\n"
    fileNames[0] = "left-canonical-state.nl"
    fileNames[1] = "right-canonical-state.nl"
    fileNames[2] = "canonical-default-caller.nl"

    tree := ConstructionNewTree(
        "ConstructionCanonicalStringEnumDefaultOwner",
        ConstructionOneText("5"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScopeFromFiles(tree, sources, fileNames, 2)
    plan := ConstructionPlan(tree, bindings)

    assert plan.OperationCount == 3
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldstr()
    assert plan.StringValues[plan.OperandIndices[1]] == "right"
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
}

test "construction planner uses unique compatibility and rejects ambiguity and sole mismatch" {
    unique := ConstructionSourceDefinition(
        "ConstructionUniqueOwner",
        true
    )
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    stringParameters := new Type[](1)
    stringParameters[0] = typeof(string)
    intCtor := unique.DefineUserConstructor(
        intParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    _stringCtor := unique.DefineUserConstructor(
        stringParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    uniqueTree := ConstructionNewTree(
        "ConstructionUniqueOwner",
        ConstructionOneText("3"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        uniqueTree,
        "class ConstructionUniqueOwner {}"
    )
    uniquePlan := ConstructionPlan(
        uniqueTree,
        ConstructionBindings(SourceCallDefinitions(unique))
    )
    assert ColumnarConstructionPlanner.SameObject(
        uniquePlan.Constructors[0],
        intCtor
    )

    ambiguous := ConstructionSourceDefinition(
        "ConstructionAmbiguousOwner",
        true
    )
    longParameters := new Type[](1)
    longParameters[0] = typeof(long)
    doubleParameters := new Type[](1)
    doubleParameters[0] = typeof(double)
    ambiguous.DefineUserConstructor(
        longParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    ambiguous.DefineUserConstructor(
        doubleParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    ambiguousTree := ConstructionNewTree(
        "ConstructionAmbiguousOwner",
        ConstructionOneText("3"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        ambiguousTree,
        "class ConstructionAmbiguousOwner {}"
    )
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _ambiguousPlan := ConstructionRejected(
        ambiguousTree,
        ConstructionBindings(SourceCallDefinitions(ambiguous)),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    mismatch := ConstructionSourceDefinition(
        "ConstructionMismatchOwner",
        true
    )
    mismatch.DefineUserConstructor(
        stringParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    mismatchTree := ConstructionNewTree(
        "ConstructionMismatchOwner",
        ConstructionOneText("3"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        mismatchTree,
        "class ConstructionMismatchOwner {}"
    )
    _mismatchPlan := ConstructionRejected(
        mismatchTree,
        ConstructionBindings(SourceCallDefinitions(mismatch)),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner rejects corrupt source constructor facts after complete rollback" {
    owner := ConstructionSourceDefinition(
        "ConstructionCorruptOwner",
        true
    )
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    constructor := owner.DefineUserConstructor(
        parameterTypes,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    owner.Constructors.Add(new ColumnarConstructorDef(
        constructor,
        parameterTypes,
        new int[](0),
        new string[](0)
    ))
    tree := ConstructionNewTree(
        "ConstructionCorruptOwner",
        ConstructionOneText("1"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionCorruptOwner {}"
    )
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
            out resultType
        )
    }
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "construction planner owns exact runtime catalog constructors and executes string construction" {
    repeat := ConstructionNewTree(
        "string",
        ConstructionTwoTexts("'x'", "4"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.CharLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(repeat, "")
    repeatPlan := ConstructionPlan(
        repeat,
        ColumnarRangePlannerEmptyBindings()
    )
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
            types[index],
            counts[index],
            out constructor,
            out parameters
        )
        assert constructor != null
        assert parameters.Length == counts[index]
        index += 1
    }

    unsupported: ConstructorInfo? = null
    unsupportedParameters := new Type[](0)
    assert !ColumnarConstructionPlanner.TrySelectRuntimeConstructor(
        typeof(Random),
        0,
        out unsupported,
        out unsupportedParameters
    )
    assert !ColumnarConstructionPlanner.TrySelectRuntimeConstructor(
        typeof(InvalidOperationException),
        2,
        out unsupported,
        out unsupportedParameters
    )
}

test "construction planner owns explicit and aliased runtime generic construction" {
    generic := ConstructionGenericNewTree()
    ConstructionStampScope(generic, "import System.Collections.Generic\n")
    genericPlan := ConstructionPlan(
        generic,
        ColumnarRangePlannerEmptyBindings()
    )
    assert genericPlan.ResultType.get_IsGenericType()
    assert genericPlan.ResultType.GetGenericTypeDefinition().FullName == "System.Collections.Generic.List`1"
    assert genericPlan.ResultType.GetGenericArguments()[0] == typeof(int)
    assert genericPlan.ConstructorCount == 1
    assert genericPlan.ConstructorParameterTypes[0].Length == 0

    closedGenericAlias := ConstructionNewTree(
        "IntListAlias",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        closedGenericAlias,
        "import System.Collections.Generic\ntype IntListAlias = List<int>\n"
    )
    closedGenericAliasPlan := ConstructionPlan(
        closedGenericAlias,
        ColumnarRangePlannerEmptyBindings()
    )
    assert closedGenericAliasPlan.ResultType == genericPlan.ResultType
    assert closedGenericAliasPlan.ConstructorCount == 1
}

test "construction planner rebinds aliased source generic constructors to the closed owner" {
    owner := SourceCallGenericDefinition("ConstructionGenericBox")
    ownerType: Type = owner.Builder
    genericArguments := ownerType.GetGenericArguments()
    assert genericArguments.Length == 1
    parameterTypes := new Type[](1)
    parameterTypes[0] = genericArguments[0]
    owner.DefineUserConstructor(
        parameterTypes,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )

    tree := ConstructionNewTree(
        "ConstructionIntBox",
        ConstructionOneText("42"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionGenericBox<T> {}\n" + "type ConstructionIntBox = ConstructionGenericBox<int>\n"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner))
    )

    assert plan.ResultType.get_IsGenericType()
    assert !plan.ResultType.get_IsGenericTypeDefinition()
    assert plan.ResultType.GetGenericTypeDefinition() == ownerType
    assert plan.ResultType.GetGenericArguments()[0] == typeof(int)
    assert plan.ConstructorCount == 1
    assert plan.ConstructorDeclaringTypes[0] == plan.ResultType
    assert plan.ConstructorParameterTypes[0].Length == 1
    assert plan.ConstructorParameterTypes[0][0] == typeof(int)
}

test "construction planner ranks substituted source generic constructor conversions" {
    owner := SourceCallGenericDefinition(
        "ConstructionRankedGenericBox"
    )
    ownerType: Type = owner.Builder
    genericArguments := ownerType.GetGenericArguments()
    assert genericArguments.Length == 1
    longParameters := new Type[](1)
    longParameters[0] = typeof(long)
    owner.DefineUserConstructor(
        longParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    genericParameters := new Type[](1)
    genericParameters[0] = genericArguments[0]
    owner.DefineUserConstructor(
        genericParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )

    tree := ConstructionNewTree(
        "ConstructionRankedIntBox",
        ConstructionOneText("42"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionRankedGenericBox<T> {}\n" + "type ConstructionRankedIntBox = ConstructionRankedGenericBox<int>\n"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner))
    )

    assert plan.ResultType.get_IsGenericType()
    assert !plan.ResultType.get_IsGenericTypeDefinition()
    assert plan.ConstructorCount == 1
    assert plan.ConstructorDeclaringTypes[0] == plan.ResultType
    assert plan.ConstructorParameterTypes[0].Length == 1
    assert plan.ConstructorParameterTypes[0][0] == typeof(int)
}

test "construction planner rebinds a synthesized default constructor on a closed source generic" {
    owner := SourceCallGenericDefinition("ConstructionGenericDefault")
    owner.DefaultCtor = owner.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )

    tree := ConstructionNewTree(
        "ConstructionIntDefault",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        tree,
        "class ConstructionGenericDefault<T> {}\n" + "type ConstructionIntDefault = ConstructionGenericDefault<int>\n"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner))
    )

    assert plan.ResultType.get_IsGenericType()
    assert !plan.ResultType.get_IsGenericTypeDefinition()
    assert ColumnarConstructionPlanner.SameObject(
        plan.ResultType.GetGenericTypeDefinition(),
        owner.Builder
    )
    assert plan.ResultType.GetGenericArguments()[0] == typeof(int)
    assert plan.ConstructorCount == 1
    assert plan.ConstructorDeclaringTypes[0] == plan.ResultType
    assert plan.ConstructorParameterTypes[0].Length == 0
}

test "construction planner substitutes closed generic parameter defaults before selection" {
    owner := SourceCallGenericDefinition("ConstructionGenericOptional")
    openArguments := owner.Builder.GetGenericArguments()
    assert openArguments.Length == 1
    parameters := new Type[](2)
    parameters[0] = openArguments[0]
    parameters[1] = openArguments[0]
    defaultKinds := ConstructionDefaults(2)
    defaultTexts := ConstructionDefaultTexts(2)
    defaultKinds[1] = 1
    defaultTexts[1] = "17"
    owner.DefineUserConstructor(parameters, defaultKinds, defaultTexts)

    tree := ConstructionNewTree(
        "ConstructionIntOptional",
        ConstructionOneText("5"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionGenericOptional<T> {}\n" + "type ConstructionIntOptional = ConstructionGenericOptional<int>\n"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner))
    )

    assert plan.ConstructorCount == 1
    assert plan.ConstructorDeclaringTypes[0] == plan.ResultType
    assert plan.ConstructorParameterTypes[0].Length == 2
    assert plan.ConstructorParameterTypes[0][0] == typeof(int)
    assert plan.ConstructorParameterTypes[0][1] == typeof(int)
    assert plan.Int32Count == 2
    assert plan.Int32Values[0] == 5
    assert plan.Int32Values[1] == 17
    assert plan.OpCodeValues[plan.OperationCount - 1] == ColumnarCodePlanContract.Newobj()
}

test "construction planner owns source class field and property object initializers" {
    owner := ConstructionSourceDefinition(
        "ConstructionObjectClass",
        true
    )
    countField := ConstructionDefinePublicField(
        owner.Builder,
        "Count",
        typeof(int)
    )
    owner.Fields["Count"] = countField
    owner.SetFieldOrder(ConstructionOneText("Count"))
    labelProperty := ColumnarPropertyDef.Define(
        owner.Builder,
        "get_Label",
        (MethodAttributes)646,
        typeof(string),
        "set_Label",
        (MethodAttributes)646
    )
    owner.Properties["Label"] = labelProperty
    owner.DefaultCtor = owner.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )

    tree := ConstructionObjectInitializerTree(
        "ConstructionObjectClass",
        ConstructionTwoTexts("Count", "Label"),
        ConstructionTwoTexts("7", "\"owned\""),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            ColumnarExpressionNodeKind.StringLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionObjectClass {}"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner))
    )

    assert ColumnarConstructionPlanner.SameObject(
        plan.ResultType,
        owner.Builder
    )
    assert plan.ConstructorCount == 1
    assert plan.FieldCount == 1
    assert plan.FieldUsesDeclaredSignature[0]
    assert ColumnarConstructionPlanner.SameObject(
        plan.FieldDeclaringTypes[0],
        owner.Builder
    )
    assert plan.FieldValueTypes[0] == typeof(int)
    assert ConstructionHasOpcode(plan, ColumnarCodePlanContract.Stfld())
    assert plan.MethodCount == 1
    setter := plan.Methods[0]
    assert setter.get_Name() == "set_Label"
    assert setter.get_IsSpecialName()
    assert ColumnarConstructionPlanner.SameObject(
        plan.MethodDeclaringTypes[0],
        owner.Builder
    )
    assert plan.MethodParameterTypes[0].Length == 1
    assert plan.MethodParameterTypes[0][0] == typeof(string)
}

test "construction planner recursively owns nested object initializer values" {
    inner := ConstructionSourceDefinition(
        "ConstructionNestedInner",
        true
    )
    innerField := ConstructionDefinePublicField(
        inner.Builder,
        "Value",
        typeof(int)
    )
    inner.Fields["Value"] = innerField
    inner.SetFieldOrder(ConstructionOneText("Value"))
    inner.DefaultCtor = inner.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )

    outer := ConstructionSourceDefinition(
        "ConstructionNestedOuter",
        true
    )
    outerField := ConstructionDefinePublicField(
        outer.Builder,
        "Inner",
        inner.Builder
    )
    outer.Fields["Inner"] = outerField
    outer.SetFieldOrder(ConstructionOneText("Inner"))
    outer.DefaultCtor = outer.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )

    definitions := new ColumnarStructDef[](2)
    definitions[0] = inner
    definitions[1] = outer
    tree := ConstructionNestedObjectInitializerTree()
    ConstructionStampScope(
        tree,
        "class ConstructionNestedInner { Value: int }\n" + "class ConstructionNestedOuter { Inner: ConstructionNestedInner }\n"
    )
    plan := ConstructionPlan(tree, ConstructionBindings(definitions))

    assert ColumnarConstructionPlanner.SameObject(
        plan.ResultType,
        outer.Builder
    )
    assert plan.ConstructorCount == 2
    assert plan.FieldCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Newobj()
    assert ConstructionHasOpcode(plan, ColumnarCodePlanContract.Stfld())
}

test "construction planner rejects init-only object initializer fields" {
    owner := ConstructionSourceDefinition(
        "ConstructionReadonlyObject",
        true
    )
    readonlyField := ConstructionDefineInitOnlyField(
        owner.Builder,
        "Value",
        typeof(int)
    )
    owner.Fields["Value"] = readonlyField
    owner.SetFieldOrder(ConstructionOneText("Value"))
    owner.DefaultCtor = owner.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )

    tree := ConstructionObjectInitializerTree(
        "ConstructionReadonlyObject",
        ConstructionOneText("Value"),
        ConstructionOneText("1"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionReadonlyObject {}"
    )
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _plan := ConstructionRejected(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner)),
        out ownership,
        out legacy
    )

    assert readonlyField.get_IsInitOnly()
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner rebinds inherited object members on a closed generic derived type" {
    baseDefinition := SourceCallGenericDefinition(
        "ConstructionObjectBase"
    )
    baseArguments := baseDefinition.Builder.GetGenericArguments()
    assert baseArguments.Length == 1
    inheritedField := ConstructionDefinePublicField(
        baseDefinition.Builder,
        "Value",
        baseArguments[0]
    )
    baseDefinition.Fields["Value"] = inheritedField
    baseDefinition.SetFieldOrder(ConstructionOneText("Value"))
    inheritedProperty := ColumnarPropertyDef.Define(
        baseDefinition.Builder,
        "get_Label",
        (MethodAttributes)646,
        baseArguments[0],
        "set_Label",
        (MethodAttributes)646
    )
    baseDefinition.Properties["Label"] = inheritedProperty

    derivedDefinition := SourceCallGenericDefinition(
        "ConstructionObjectDerived"
    )
    derivedArguments := derivedDefinition.Builder.GetGenericArguments()
    assert derivedArguments.Length == 1
    openBaseArguments := new Type[](1)
    openBaseArguments[0] = derivedArguments[0]
    baseBuilderType: Type = baseDefinition.Builder
    openDerivedBase := baseBuilderType.MakeGenericType(
        openBaseArguments
    )
    ConstructionSetParent(derivedDefinition.Builder, openDerivedBase)
    derivedDefinition.BaseDef = baseDefinition
    derivedDefinition.DefaultCtor = derivedDefinition.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )

    definitions := new ColumnarStructDef[](2)
    definitions[0] = baseDefinition
    definitions[1] = derivedDefinition
    tree := ConstructionObjectInitializerTree(
        "ConstructionIntDerived",
        ConstructionTwoTexts("Value", "Label"),
        ConstructionTwoTexts("42", "43"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionObjectBase<T> { Value: T }\n" + "class ConstructionObjectDerived<T>: ConstructionObjectBase<T> {}\n" + "type ConstructionIntDerived = ConstructionObjectDerived<int>\n"
    )
    plan := ConstructionPlan(tree, ConstructionBindings(definitions))

    closedDerivedArguments := new Type[](1)
    closedDerivedArguments[0] = typeof(int)
    derivedBuilderType: Type = derivedDefinition.Builder
    closedDerived := derivedBuilderType.MakeGenericType(
        closedDerivedArguments
    )
    closedBase := baseBuilderType.MakeGenericType(
        closedDerivedArguments
    )
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.ResultType,
        closedDerived
    )
    assert plan.FieldCount == 1
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.FieldDeclaringTypes[0],
        closedBase
    )
    assert plan.FieldValueTypes[0] == typeof(int)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.Fields[0].get_DeclaringType(),
        closedBase
    )
    assert ConstructionHasOpcode(plan, ColumnarCodePlanContract.Stfld())
    assert plan.MethodCount == 1
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.MethodDeclaringTypes[0],
        closedBase
    )
    assert plan.MethodParameterTypes[0].Length == 1
    assert plan.MethodParameterTypes[0][0] == typeof(int)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.Methods[0].get_DeclaringType(),
        closedBase
    )
    assert plan.Methods[0].get_Name() == "set_Label"
}

test "construction planner follows multilevel reordered and fixed generic bases" {
    baseBuilder := TypeOfCreateBuilder(
        "ConstructionMappedBase",
        "ColumnarConstructionTests.ConstructionMappedBase",
        2
    )
    baseBuilderType: Type = baseBuilder
    baseDefinition := new ColumnarStructDef(
        baseBuilder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        "ConstructionMappedBase"
    )
    baseArguments := baseBuilder.GetGenericArguments()
    assert baseArguments.Length == 2
    inheritedField := ConstructionDefinePublicField(
        baseBuilder,
        "Fixed",
        baseArguments[0]
    )
    baseDefinition.Fields["Fixed"] = inheritedField
    baseDefinition.SetFieldOrder(ConstructionOneText("Fixed"))
    inheritedProperty := ColumnarPropertyDef.Define(
        baseBuilder,
        "get_Reordered",
        (MethodAttributes)646,
        baseArguments[1],
        "set_Reordered",
        (MethodAttributes)646
    )
    baseDefinition.Properties["Reordered"] = inheritedProperty

    middleBuilder := TypeOfCreateBuilder(
        "ConstructionMappedMiddle",
        "ColumnarConstructionTests.ConstructionMappedMiddle",
        1
    )
    middleBuilderType: Type = middleBuilder
    middleDefinition := new ColumnarStructDef(
        middleBuilder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        "ConstructionMappedMiddle"
    )
    middleArguments := middleBuilder.GetGenericArguments()
    assert middleArguments.Length == 1
    openBaseArguments := new Type[](2)
    openBaseArguments[0] = typeof(string)
    openBaseArguments[1] = middleArguments[0]
    ConstructionSetParent(
        middleBuilder,
        baseBuilderType.MakeGenericType(openBaseArguments)
    )
    middleDefinition.BaseDef = baseDefinition

    derivedBuilder := TypeOfCreateBuilder(
        "ConstructionMappedDerived",
        "ColumnarConstructionTests.ConstructionMappedDerived",
        2
    )
    derivedBuilderType: Type = derivedBuilder
    derivedDefinition := new ColumnarStructDef(
        derivedBuilder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        "ConstructionMappedDerived"
    )
    derivedArguments := derivedBuilder.GetGenericArguments()
    assert derivedArguments.Length == 2
    openMiddleArguments := new Type[](1)
    openMiddleArguments[0] = derivedArguments[1]
    ConstructionSetParent(
        derivedBuilder,
        middleBuilderType.MakeGenericType(openMiddleArguments)
    )
    derivedDefinition.BaseDef = middleDefinition
    derivedDefinition.DefaultCtor = derivedBuilder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )

    definitions := new ColumnarStructDef[](3)
    definitions[0] = baseDefinition
    definitions[1] = middleDefinition
    definitions[2] = derivedDefinition
    tree := ConstructionObjectInitializerTree(
        "ConstructionMappedAlias",
        ConstructionTwoTexts("Fixed", "Reordered"),
        ConstructionTwoTexts("\"fixed\"", "44"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.StringLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionMappedBase<A,B> { Fixed: A }\n" + "class ConstructionMappedMiddle<T>: ConstructionMappedBase<string,T> {}\n" + "class ConstructionMappedDerived<X,Y>: ConstructionMappedMiddle<Y> {}\n" + "type ConstructionMappedAlias = ConstructionMappedDerived<int,long>\n"
    )
    plan := ConstructionPlan(tree, ConstructionBindings(definitions))

    closedDerivedArguments := new Type[](2)
    closedDerivedArguments[0] = typeof(int)
    closedDerivedArguments[1] = typeof(long)
    closedDerived := derivedBuilderType.MakeGenericType(closedDerivedArguments)
    closedBaseArguments := new Type[](2)
    closedBaseArguments[0] = typeof(string)
    closedBaseArguments[1] = typeof(long)
    closedBase := baseBuilderType.MakeGenericType(closedBaseArguments)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.ResultType,
        closedDerived
    )
    assert plan.FieldCount == 1
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.FieldDeclaringTypes[0],
        closedBase
    )
    assert plan.FieldValueTypes[0] == typeof(string)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.Fields[0].get_DeclaringType(),
        closedBase
    )
    assert plan.MethodCount == 1
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.MethodDeclaringTypes[0],
        closedBase
    )
    assert plan.MethodParameterTypes[0].Length == 1
    assert plan.MethodParameterTypes[0][0] == typeof(long)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.Methods[0].get_DeclaringType(),
        closedBase
    )
}

test "construction planner owns source struct fields and target-typed negative integers" {
    owner := ConstructionSourceDefinition(
        "ConstructionObjectStruct",
        false
    )
    offsetField := ConstructionDefinePublicField(
        owner.Builder,
        "Offset",
        typeof(sbyte)
    )
    owner.Fields["Offset"] = offsetField
    owner.SetFieldOrder(ConstructionOneText("Offset"))

    tree := ConstructionNegativeObjectInitializerTree(
        "ConstructionObjectStruct",
        "Offset",
        "8"
    )
    ConstructionStampScope(
        tree,
        "struct ConstructionObjectStruct {}"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner))
    )

    assert ColumnarConstructionPlanner.SameObject(
        plan.ResultType,
        owner.Builder
    )
    assert plan.PlanLocalCount == 1
    assert plan.FieldCount == 1
    assert plan.FieldValueTypes[0] == typeof(sbyte)
    assert plan.Int32Count == 1
    assert plan.Int32Values[0] == -8
    assert ConstructionHasOpcode(plan, ColumnarCodePlanContract.Initobj())
    assert ConstructionHasOpcode(plan, ColumnarCodePlanContract.Stfld())
}

test "construction planner target-types nullable integer initializer boundaries" {
    owner := ConstructionSourceDefinition(
        "ConstructionNullableLiteralObject",
        true
    )
    nullableByte := NullableArgumentType(typeof(byte))
    nullableShort := NullableArgumentType(typeof(short))
    nullableUInt := NullableArgumentType(typeof(uint))
    byteField := ConstructionDefinePublicField(
        owner.Builder,
        "ByteValue",
        nullableByte
    )
    shortField := ConstructionDefinePublicField(
        owner.Builder,
        "ShortValue",
        nullableShort
    )
    uintField := ConstructionDefinePublicField(
        owner.Builder,
        "UIntValue",
        nullableUInt
    )
    owner.Fields["ByteValue"] = byteField
    owner.Fields["ShortValue"] = shortField
    owner.Fields["UIntValue"] = uintField
    owner.SetFieldOrder(
        ConstructionThreeTexts("ByteValue", "ShortValue", "UIntValue")
    )
    owner.DefaultCtor = owner.Builder.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )

    tree := ConstructionObjectInitializerTree(
        "ConstructionNullableLiteralObject",
        ConstructionThreeTexts("ByteValue", "ShortValue", "UIntValue"),
        ConstructionThreeTexts("255", "32767", "2147483647"),
        ConstructionThreeKinds(
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "class ConstructionNullableLiteralObject {}"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(owner))
    )

    assert plan.ConstructorCount == 4
    assert plan.ConstructorDeclaringTypes[1] == nullableByte
    assert plan.ConstructorDeclaringTypes[2] == nullableShort
    assert plan.ConstructorDeclaringTypes[3] == nullableUInt
    assert plan.ConstructorParameterTypes[1][0] == typeof(byte)
    assert plan.ConstructorParameterTypes[2][0] == typeof(short)
    assert plan.ConstructorParameterTypes[3][0] == typeof(uint)
    assert plan.FieldValueTypes[0] == nullableByte
    assert plan.FieldValueTypes[1] == nullableShort
    assert plan.FieldValueTypes[2] == nullableUInt
    assert plan.Int32Count == 3
    assert plan.Int32Values[0] == 255
    assert plan.Int32Values[1] == 32767
    assert plan.Int32Values[2] == 2147483647

    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    byteOverflow := ConstructionObjectInitializerTree(
        "ConstructionNullableLiteralObject",
        ConstructionOneText("ByteValue"),
        ConstructionOneText("256"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        byteOverflow,
        "class ConstructionNullableLiteralObject {}"
    )
    _byteOverflowPlan := ConstructionRejected(
        byteOverflow,
        ConstructionBindings(SourceCallDefinitions(owner)),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    shortOverflow := ConstructionObjectInitializerTree(
        "ConstructionNullableLiteralObject",
        ConstructionOneText("ShortValue"),
        ConstructionOneText("32768"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        shortOverflow,
        "class ConstructionNullableLiteralObject {}"
    )
    _shortOverflowPlan := ConstructionRejected(
        shortOverflow,
        ConstructionBindings(SourceCallDefinitions(owner)),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    negativeUInt := ConstructionNegativeObjectInitializerTree(
        "ConstructionNullableLiteralObject",
        "UIntValue",
        "1"
    )
    ConstructionStampScope(
        negativeUInt,
        "class ConstructionNullableLiteralObject {}"
    )
    _negativeUIntPlan := ConstructionRejected(
        negativeUInt,
        ConstructionBindings(SourceCallDefinitions(owner)),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner owns and executes an approved runtime object initializer" {
    tree := ConstructionObjectInitializerTree(
        "JsonSerializerOptions",
        ConstructionOneText("PropertyNameCaseInsensitive"),
        ConstructionOneText("true"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.BoolLiteralExpression()
        )
    )
    ConstructionStampScope(tree, "import System.Text.Json\n")
    plan := ConstructionPlan(
        tree,
        ColumnarRangePlannerEmptyBindings()
    )

    assert plan.ResultType == typeof(System.Text.Json.JsonSerializerOptions)
    assert plan.ConstructorCount == 1
    assert plan.MethodCount == 1
    assert plan.Methods[0].get_Name() == "set_PropertyNameCaseInsensitive"
    result := NullableArgumentRunPlan(
        plan,
        typeof(System.Text.Json.JsonSerializerOptions)
    )
    options := result as System.Text.Json.JsonSerializerOptions
    if options == null {
        throw new InvalidOperationException(
            "The runtime object-initializer plan returned the wrong type."
        )
    }
    optionProperty := typeof(System.Text.Json.JsonSerializerOptions).GetProperty("PropertyNameCaseInsensitive")
    if optionProperty == null {
        throw new InvalidOperationException(
            "The runtime object-initializer probe property was not found."
        )
    }
    optionValue := optionProperty.GetValue(options)
    assert optionValue != null && optionValue.ToString() == "True"
}

test "constructed runtime object initializers preserve parity without widening the bare catalog" {
    constructed := ConstructionObjectInitializerFromNewTree(
        "StringBuilder",
        "Capacity",
        "16",
        ColumnarExpressionNodeKind.IntLiteralExpression()
    )
    ConstructionStampScope(constructed, "import System.Text\n")
    plan := ConstructionPlan(
        constructed,
        ColumnarRangePlannerEmptyBindings()
    )
    assert plan.ResultType == typeof(System.Text.StringBuilder)
    assert plan.ConstructorCount == 1
    assert plan.MethodCount == 1
    assert plan.Methods[0].get_Name() == "set_Capacity"
    result := NullableArgumentRunPlan(
        plan,
        typeof(System.Text.StringBuilder)
    )
    builder := result as System.Text.StringBuilder
    if builder == null {
        throw new InvalidOperationException(
            "The constructed runtime object-initializer plan returned the wrong type."
        )
    }
    capacityProperty := typeof(System.Text.StringBuilder).GetProperty("Capacity")
    if capacityProperty == null {
        throw new InvalidOperationException(
            "The StringBuilder capacity property was not found."
        )
    }
    capacity := capacityProperty.GetValue(builder)
    assert capacity != null && capacity.ToString() == "16"

    bareNearMiss := ConstructionObjectInitializerTree(
        "StringBuilder",
        ConstructionOneText("Capacity"),
        ConstructionOneText("16"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(bareNearMiss, "import System.Text\n")
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _bareNearMissPlan := ConstructionRejected(
        bareNearMiss,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner owns source union case object initializers" {
    unionBase := TypeOfCreateBuilder(
        "ConstructionObjectUnionSeed",
        "ColumnarConstructionTests.ConstructionObjectUnion",
        0
    )
    caseType := TypeOfCreateBuilder(
        "ConstructionObjectUnionValueSeed",
        "ColumnarConstructionTests.ConstructionObjectUnionValue",
        0
    )
    ConstructionSetParent(caseType, unionBase)
    constructor := caseType.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )
    numberField := ConstructionDefinePublicField(
        caseType,
        "number",
        typeof(int)
    )
    labelField := ConstructionDefinePublicField(
        caseType,
        "label",
        typeof(string)
    )
    fields := new Dictionary<string, FieldBuilder>(StringComparer.Ordinal)
    fields["number"] = numberField
    fields["label"] = labelField
    caseDefinition := new ColumnarUnionCaseDef(
        caseType,
        constructor,
        ConstructionTwoTexts("number", "label"),
        fields,
        unionBase
    )
    unionDefinition := new ColumnarUnionDef(
        unionBase,
        0,
        "ConstructionObjectUnion"
    )
    unionDefinition.Cases["ConstructionObjectUnion.Value"] = caseDefinition
    unions := new List<ColumnarUnionDef>()
    unions.Add(unionDefinition)
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceUnionDefinitions = unions

    tree := ConstructionObjectInitializerTree(
        "ConstructionObjectUnion.Value",
        ConstructionOneText("number"),
        ConstructionOneText("42"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "union ConstructionObjectUnion { Value { number: int } }"
    )
    plan := ConstructionPlan(tree, bindings)

    assert ColumnarConstructionPlanner.SameObject(
        plan.ResultType,
        unionBase
    )
    assert plan.ConstructorCount == 1
    assert ColumnarConstructionPlanner.SameObject(
        plan.ConstructorDeclaringTypes[0],
        caseType
    )
    assert plan.FieldCount == 1
    assert ColumnarConstructionPlanner.SameObject(
        plan.FieldDeclaringTypes[0],
        caseType
    )
    assert plan.FieldValueTypes[0] == typeof(int)
    assert ConstructionHasOpcode(plan, ColumnarCodePlanContract.Stfld())

    positional := ConstructionNewTree(
        "ConstructionObjectUnion.Value",
        ConstructionTwoTexts("43", "\"ordered\""),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.IntLiteralExpression(),
            ColumnarExpressionNodeKind.StringLiteralExpression()
        )
    )
    ConstructionStampScope(
        positional,
        "union ConstructionObjectUnion { Value { number: int, label: string } }"
    )
    positionalPlan := ConstructionPlan(positional, bindings)
    assert ColumnarConstructionPlanner.SameObject(
        positionalPlan.ResultType,
        unionBase
    )
    assert positionalPlan.ConstructorCount == 1
    assert positionalPlan.FieldCount == 2
    assert ColumnarConstructionPlanner.SameObject(
        positionalPlan.Fields[0],
        numberField
    )
    assert ColumnarConstructionPlanner.SameObject(
        positionalPlan.Fields[1],
        labelField
    )
    assert positionalPlan.FieldValueTypes[0] == typeof(int)
    assert positionalPlan.FieldValueTypes[1] == typeof(string)
    assert positionalPlan.OpCodeValues[0] == ColumnarCodePlanContract.Newobj()
    assert ConstructionHasOpcode(
        positionalPlan,
        ColumnarCodePlanContract.Dup()
    )
}

test "construction planner owns closed generic positional union cases and rejects claimed invalid roots" {
    unionBase := TypeOfCreateBuilder(
        "ConstructionGenericUnionSeed",
        "ColumnarConstructionTests.ConstructionGenericUnion",
        1
    )
    caseType := TypeOfCreateBuilder(
        "ConstructionGenericUnionValueSeed",
        "ColumnarConstructionTests.ConstructionGenericUnionValue",
        1
    )
    unionBaseType: Type = unionBase
    caseBuilderType: Type = caseType
    caseArguments := caseType.GetGenericArguments()
    assert caseArguments.Length == 1
    openBaseArguments := new Type[](1)
    openBaseArguments[0] = caseArguments[0]
    ConstructionSetParent(
        caseType,
        unionBaseType.MakeGenericType(openBaseArguments)
    )
    constructor := caseType.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )
    valueField := ConstructionDefinePublicField(
        caseType,
        "value",
        caseArguments[0]
    )
    fields := new Dictionary<string, FieldBuilder>(StringComparer.Ordinal)
    fields["value"] = valueField
    caseDefinition := new ColumnarUnionCaseDef(
        caseType,
        constructor,
        ConstructionOneText("value"),
        fields,
        unionBase
    )
    unionDefinition := new ColumnarUnionDef(
        unionBase,
        1,
        "ConstructionGenericUnion"
    )
    unionDefinition.Cases["ConstructionGenericUnion.Value"] = caseDefinition
    unions := new List<ColumnarUnionDef>()
    unions.Add(unionDefinition)
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceUnionDefinitions = unions

    tree := ConstructionExplicitGenericNewTree(
        "ConstructionGenericUnion.Value",
        ConstructionOneText("int"),
        ConstructionOneText("44"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        tree,
        "union ConstructionGenericUnion<T> { Value { value: T } }"
    )
    plan := ConstructionPlan(tree, bindings)
    closedArguments := new Type[](1)
    closedArguments[0] = typeof(int)
    closedUnion := unionBaseType.MakeGenericType(closedArguments)
    closedCase := caseBuilderType.MakeGenericType(closedArguments)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.ResultType,
        closedUnion
    )
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.ConstructorDeclaringTypes[0],
        closedCase
    )
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.FieldDeclaringTypes[0],
        closedCase
    )
    assert plan.FieldValueTypes[0] == typeof(int)
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Newobj()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Dup()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Stfld()

    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    missing := ConstructionExplicitGenericNewTree(
        "ConstructionGenericUnion.Missing",
        ConstructionOneText("int"),
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        missing,
        "union ConstructionGenericUnion<T> { Value { value: T } }"
    )
    _missingPlan := ConstructionRejected(
        missing,
        bindings,
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    wrongArity := ConstructionExplicitGenericNewTree(
        "ConstructionGenericUnion.Value",
        ConstructionTwoTexts("int", "string"),
        ConstructionOneText("44"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        wrongArity,
        "union ConstructionGenericUnion<T> { Value { value: T } }"
    )
    _wrongArityPlan := ConstructionRejected(
        wrongArity,
        bindings,
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    missingValue := ConstructionExplicitGenericNewTree(
        "ConstructionGenericUnion.Value",
        ConstructionOneText("int"),
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        missingValue,
        "union ConstructionGenericUnion<T> { Value { value: T } }"
    )
    _missingValuePlan := ConstructionRejected(
        missingValue,
        bindings,
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner owns payload-free value-struct union construction forms" {
    unionBase := TypeOfCreateBuilder(
        "ConstructionValueUnionSeed",
        "ColumnarConstructionTests.ConstructionValueUnion",
        0
    )
    caseType := TypeOfCreateBuilder(
        "ConstructionValueUnionCaseSeed",
        "ColumnarConstructionTests.ConstructionValueUnionCase",
        0
    )
    constructor := caseType.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        new Type[](0)
    )
    caseDefinition := new ColumnarUnionCaseDef(
        caseType,
        constructor,
        ConstructionEmptyTexts(),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        unionBase
    )
    unionBaseReturnType: Type = unionBase
    factory := unionBase.DefineMethod(
        "Create_Only",
        (MethodAttributes)22,
        unionBaseReturnType,
        new Type[](0)
    )
    caseDefinition.IsValueStruct = true
    caseDefinition.ValueStructFactory = factory
    unionDefinition := new ColumnarUnionDef(
        unionBase,
        0,
        "ConstructionValueUnion"
    )
    unionDefinition.IsValueStruct = true
    unionDefinition.Cases["ConstructionValueUnion.Only"] = caseDefinition
    unions := new List<ColumnarUnionDef>()
    unions.Add(unionDefinition)
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.SourceUnionDefinitions = unions

    positional := ConstructionNewTree(
        "ConstructionValueUnion.Only",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        positional,
        "union ConstructionValueUnion { Only }"
    )
    positionalPlan := ConstructionPlan(positional, bindings)
    assert ColumnarConstructionPlanner.SameObject(
        positionalPlan.ResultType,
        unionBase
    )
    assert positionalPlan.MethodCount == 1
    assert positionalPlan.OperationCount == 1
    assert positionalPlan.OpCodeValues[0] == ColumnarCodePlanContract.Call()

    initializer := ConstructionObjectInitializerTree(
        "ConstructionValueUnion.Only",
        ConstructionEmptyTexts(),
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        initializer,
        "union ConstructionValueUnion { Only }"
    )
    initializerPlan := ConstructionPlan(initializer, bindings)
    assert ColumnarConstructionPlanner.SameObject(
        initializerPlan.ResultType,
        unionBase
    )
    assert initializerPlan.MethodCount == 1
    assert initializerPlan.OpCodeValues[0] == ColumnarCodePlanContract.Call()

    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    payload := ConstructionNewTree(
        "ConstructionValueUnion.Only",
        ConstructionOneText("1"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        payload,
        "union ConstructionValueUnion { Only }"
    )
    _payloadPlan := ConstructionRejected(
        payload,
        bindings,
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner owns default source values and JsonElement through initobj" {
    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacy := false

    valueOwner := ConstructionSourceDefinition(
        "ConstructionDefaultValue",
        false
    )
    value := ConstructionNewTree(
        "ConstructionDefaultValue",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        value,
        "struct ConstructionDefaultValue {}"
    )
    valuePlan := ConstructionPlan(
        value,
        ConstructionBindings(SourceCallDefinitions(valueOwner))
    )
    assert ColumnarConstructionPlanner.SameObject(
        valuePlan.ResultType,
        valueOwner.Builder
    )
    assert valuePlan.PlanLocalCount == 1
    assert valuePlan.OperationCount == 3
    assert valuePlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloca()
    assert valuePlan.OpCodeValues[1] == ColumnarCodePlanContract.Initobj()
    assert valuePlan.OpCodeValues[2] == ColumnarCodePlanContract.Ldloc()
    assert ColumnarConstructionPlanner.SameObject(
        valuePlan.Types[valuePlan.PlanLocalTypeIndices[0]],
        valueOwner.Builder
    )

    json := ConstructionNewTree(
        "JsonElement",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(json, "import System.Text.Json\n")
    jsonPlan := ConstructionPlan(
        json,
        ColumnarRangePlannerEmptyBindings()
    )
    assert jsonPlan.ResultType == typeof(System.Text.Json.JsonElement)
    assert jsonPlan.PlanLocalCount == 1
    assert jsonPlan.OperationCount == 3
    assert jsonPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloca()
    assert jsonPlan.OpCodeValues[1] == ColumnarCodePlanContract.Initobj()
    assert jsonPlan.OpCodeValues[2] == ColumnarCodePlanContract.Ldloc()
    jsonResult := NullableArgumentRunPlan(
        jsonPlan,
        typeof(System.Text.Json.JsonElement)
    )
    jsonValueKind := typeof(System.Text.Json.JsonElement).GetProperty("ValueKind")
    if jsonValueKind == null {
        throw new InvalidOperationException(
            "JsonElement.ValueKind was not found."
        )
    }
    kindValue := jsonValueKind.GetValue(jsonResult)
    assert kindValue != null && kindValue.ToString() == "Undefined"

    invalidValue := ConstructionNewTree(
        "ConstructionDefaultValue",
        ConstructionOneText("1"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        invalidValue,
        "struct ConstructionDefaultValue {}"
    )
    _invalidValuePlan := ConstructionRejected(
        invalidValue,
        ConstructionBindings(SourceCallDefinitions(valueOwner)),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    invalidJson := ConstructionNewTree(
        "JsonElement",
        ConstructionOneText("1"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(invalidJson, "import System.Text.Json\n")
    _invalidJsonPlan := ConstructionRejected(
        invalidJson,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction planner owns closed generic default source values" {
    builder := TypeOfCreateBuilder(
        "ConstructionGenericDefaultValue",
        "ColumnarConstructionTests.ConstructionGenericDefaultValue",
        1
    )
    valueType := TypeOfRequiredRuntimeType(
        typeof(TypeBuilder),
        "System.ValueType"
    )
    ConstructionSetParent(builder, valueType)
    builderType: Type = builder
    definition := new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        false,
        false,
        false,
        "ConstructionGenericDefaultValue"
    )
    typeArguments := ConstructionOneText("int")
    tree := ConstructionExplicitGenericNewTree(
        "ConstructionGenericDefaultValue",
        typeArguments,
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        tree,
        "struct ConstructionGenericDefaultValue<T> {}"
    )
    plan := ConstructionPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(definition))
    )
    closedArguments := new Type[](1)
    closedArguments[0] = typeof(int)
    closedType := builderType.MakeGenericType(closedArguments)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.ResultType,
        closedType
    )
    assert plan.PlanLocalCount == 1
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldloca()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Initobj()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ldloc()
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        plan.Types[plan.PlanLocalTypeIndices[0]],
        closedType
    )
}

test "construction planner blocks a visible type parameter when its live handle is absent" {
    tree := ConstructionSizedArrayTree(
        "T",
        "2",
        ColumnarExpressionNodeKind.IntLiteralExpression()
    )
    visible := new string[](1)
    visible[0] = "T"
    ConstructionStampScopeWithTypeParameters(
        tree,
        "class T {}",
        visible
    )
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    _missingPlan := ConstructionRejected(
        tree,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    genericOwner := TypeOfCreateSourceBuilder(
        "ConstructionGenericOwner",
        true
    )
    arguments := genericOwner.GetGenericArguments()
    assert arguments.Length == 1
    liveParameterName := arguments[0].Name
    typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    typeParameters[liveParameterName] = arguments[0]
    bindings := BindingRawTypeParameters(typeParameters)
    liveTree := ConstructionSizedArrayTree(
        liveParameterName,
        "2",
        ColumnarExpressionNodeKind.IntLiteralExpression()
    )
    liveVisible := new string[](1)
    liveVisible[0] = liveParameterName
    ConstructionStampScopeWithTypeParameters(
        liveTree,
        "class " + liveParameterName + " {}",
        liveVisible
    )
    livePlan := ConstructionPlan(liveTree, bindings)
    assert livePlan.ResultType.get_IsSZArray()
    assert ColumnarConstructionPlanner.SameObject(
        livePlan.ResultType.GetElementType(),
        arguments[0]
    )
    assert ColumnarConstructionPlanner.SameObject(
        livePlan.Types[livePlan.OperandIndices[1]],
        arguments[0]
    )
}

test "construction planner resolves exact aliases and nested live type parameter arrays" {
    alias := ConstructionNewTree(
        "BuilderAlias",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(
        alias,
        "import System.Text\ntype BuilderAlias = StringBuilder\n"
    )
    aliasPlan := ConstructionPlan(
        alias,
        ColumnarRangePlannerEmptyBindings()
    )
    assert aliasPlan.ResultType == typeof(System.Text.StringBuilder), "exact alias result type"
    assert aliasPlan.ConstructorDeclaringTypes[0] == typeof(System.Text.StringBuilder), "exact alias constructor owner"

    genericOwner := TypeOfCreateSourceBuilder(
        "ConstructionNestedGenericOwner",
        true
    )
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
        visible
    )
    nestedPlan := ConstructionPlan(nested, bindings)
    assert nestedPlan.ResultType.get_IsSZArray(), "outer array result"
    firstElement := nestedPlan.ResultType.GetElementType()
    if firstElement == null {
        throw new InvalidOperationException(
            "Nested generic array did not retain its element type."
        )
    }
    assert firstElement.get_IsSZArray(), "inner array result"
    assert ColumnarConstructionPlanner.SameObject(
        firstElement.GetElementType(),
        arguments[0]
    ), "live generic element identity"
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
        nestedPlan.Types[nestedPlan.OperandIndices[1]],
        firstElement
    ), "newarr operand identity"
}

test "construction planner terminally rejects raw union bases and unsupported runtime constructors" {
    unionBuilder := TypeOfCreateSourceBuilder(
        "ConstructionUnion",
        false
    )
    unionDefinition := new ColumnarUnionDef(
        unionBuilder,
        0,
        "ConstructionUnion"
    )
    unionBindings := ColumnarRangePlannerEmptyBindings()
    unions := new List<ColumnarUnionDef>()
    unions.Add(unionDefinition)
    unionBindings.SourceUnionDefinitions = unions
    unionTree := ConstructionNewTree(
        "ConstructionUnion",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(unionTree, "union ConstructionUnion {}")
    ownership := ColumnarDirectCallOwnership.OwnedRejected
    legacy := false
    _unionPlan := ConstructionRejected(
        unionTree,
        unionBindings,
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    unionCaseTree := ConstructionNewTree(
        "ConstructionUnion.Value",
        ConstructionOneText("1"),
        ConstructionOneKind(
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
    ConstructionStampScope(
        unionCaseTree,
        "union ConstructionUnion { Value { number: int } }"
    )
    _unionCasePlan := ConstructionRejected(
        unionCaseTree,
        unionBindings,
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy

    randomTree := ConstructionNewTree(
        "Random",
        ConstructionEmptyTexts(),
        ConstructionEmptyKinds()
    )
    ConstructionStampScope(randomTree, "import System\n")
    _randomPlan := ConstructionRejected(
        randomTree,
        ColumnarRangePlannerEmptyBindings(),
        out ownership,
        out legacy
    )
    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacy
}

test "construction TryGetType seals valid plans and rolls invalid plans back without execution" {
    valid := ConstructionNewTree(
        "string",
        ConstructionTwoTexts("'q'", "2"),
        ConstructionTwoKinds(
            ColumnarExpressionNodeKind.CharLiteralExpression(),
            ColumnarExpressionNodeKind.IntLiteralExpression()
        )
    )
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
        out resultType
    )
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
            ColumnarExpressionNodeKind.StringLiteralExpression()
        )
    )
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
        out resultType
    )
    assert owned
    assert !legacy
    ColumnarRangePlannerAssertEmptyRollback(invalidPlan)
}

test "direct-call argument planning admits nested exact construction" {
    consumer := ConstructionSourceDefinition(
        "ConstructionConsumer",
        true
    )
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    target := SourceCallPublicStatic(
        consumer,
        "Consume",
        parameterTypes,
        typeof(string)
    )
    tree := ConstructionNestedDirectCallTree()
    ConstructionStampScope(
        tree,
        "class ConstructionConsumer {}"
    )
    plan := DirectCallPlan(
        tree,
        ConstructionBindings(SourceCallDefinitions(consumer))
    )
    assert plan.ResultType == typeof(string)
    assert plan.ConstructorCount == 1
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Newobj()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Call()
    assert ColumnarConstructionPlanner.SameObject(
        plan.Methods[plan.OperandIndices[3]],
        target.Builder
    )
}

test "nested construction admits explicit generic type roots in call and constructor arguments" {
    listType := typeof(List<int>)
    consumer := ConstructionSourceDefinition(
        "ConstructionGenericConsumer",
        true
    )
    consumeParameters := new Type[](1)
    consumeParameters[0] = listType
    consume := SourceCallPublicStatic(
        consumer,
        "Consume",
        consumeParameters,
        typeof(int)
    )
    callTree := ConstructionNestedGenericDirectCallTree()
    ConstructionStampScope(
        callTree,
        "import System.Collections.Generic\n" + "class ConstructionGenericConsumer {}"
    )
    callPlan := DirectCallPlan(
        callTree,
        ConstructionBindings(SourceCallDefinitions(consumer))
    )

    assert callPlan.ResultType == typeof(int)
    assert callPlan.ConstructorCount == 1
    assert callPlan.ConstructorDeclaringTypes[0] == listType
    assert callPlan.MethodCount == 1
    assert ColumnarConstructionPlanner.SameObject(
        callPlan.Methods[0],
        consume.Builder
    )

    constructorOwner := ConstructionSourceDefinition(
        "ConstructionGenericCtorConsumer",
        true
    )
    constructorParameters := new Type[](1)
    constructorParameters[0] = listType
    constructorOwner.DefineUserConstructor(
        constructorParameters,
        ConstructionDefaults(1),
        ConstructionDefaultTexts(1)
    )
    constructorTree := ConstructionNewWithNestedGenericTree()
    ConstructionStampScope(
        constructorTree,
        "import System.Collections.Generic\n" + "class ConstructionGenericCtorConsumer {}"
    )
    constructorPlan := ConstructionPlan(
        constructorTree,
        ConstructionBindings(SourceCallDefinitions(constructorOwner))
    )

    assert ColumnarConstructionPlanner.SameObject(
        constructorPlan.ResultType,
        constructorOwner.Builder
    )
    assert constructorPlan.ConstructorCount == 2
    assert constructorPlan.ConstructorDeclaringTypes[0] == listType
    assert ColumnarConstructionPlanner.SameObject(
        constructorPlan.ConstructorDeclaringTypes[1],
        constructorOwner.Builder
    )
    assert constructorPlan.OpCodeValues[0] == ColumnarCodePlanContract.Newobj()
    assert constructorPlan.OpCodeValues[1] == ColumnarCodePlanContract.Newobj()
}

// ---- THE ADMISSION SCRATCH TYPES THE FRAME IT WILL BE APPENDED INTO (015-B10) ----
//
// `ValueSyntaxIsAdmitted` builds a scratch at `parentFragment = -1`, and the range/index owner's root
// rule reads exactly that to refuse an ordinary `arr[0]` at a plan ROOT. But an initializer value, an
// array element and a constructor argument are never at a root — all three APPEND sites pass a real
// fragment — so the admission step refused what the append step would have planned. The scratch now
// DECLARES the frame, which is the statement `015-B9` made at the direct-call scratch, made here.
// `new Holder(arr[0])` and `[arr[0], 2]` are the shapes this cost.
test "construction value admission types an ordinary index under the frame it will be appended into" {
    tree := ColumnarRangePlannerOrdinaryLiteralAccess()
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "target", 0, typeof(int[]))

    assert ColumnarConstructionPlanner.ValueSyntaxIsAdmitted(tree.Nodes, tree.Source, tree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), 0)

    // AND THE SURFACE IS INHERITED THROUGH THE SAME SCRATCH: a BINARY selector inside that index is
    // admitted too, because the construction surface is what the scratch types with.
    binary := ColumnarRangePlannerBinarySelectorAccess()
    assert ColumnarConstructionPlanner.ValueSyntaxIsAdmitted(binary.Nodes, binary.Source, binary.Root, bindings, ColumnarRangeIndexHandles.Resolve(), 0)

    // The frame is not a blanket yes: an index over a receiver the owner does not model still declines,
    // so admission still answers a question about the value rather than about the frame.
    unmodelled := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(unmodelled, "target", 0, typeof(int))
    assert !ColumnarConstructionPlanner.ValueSyntaxIsAdmitted(tree.Nodes, tree.Source, tree.Root, unmodelled, ColumnarRangeIndexHandles.Resolve(), 0)
}

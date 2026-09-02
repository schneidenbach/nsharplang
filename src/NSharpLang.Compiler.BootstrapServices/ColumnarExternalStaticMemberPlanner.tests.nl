namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.IO
import System.Reflection.Emit
import System.Text.Json

func ExternalStaticMemberTree(ownerName: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), ownerName)

    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(owner))

    return builder.Build(root)
}

func ExternalQualifiedStaticMemberTree(ownerParts: string[], memberName: string): ColumnarRangePlannerTestTree {
    if ownerParts.Length == 0 {
        throw new InvalidOperationException("Qualified external owner requires at least one name segment.")
    }

    builder := new ColumnarRangePlannerNodeBuilder()
    root := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), ownerParts[0])

    index := 1
    while index < ownerParts.Length {
        builder.AddToken(".")
        partStart := builder.AddToken(ownerParts[index])
        root = builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), partStart, ownerParts[index].Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(root))

        index = index + 1
    }

    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    root = builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(root))

    return builder.Build(root)
}

func ExternalStaticExplicitThisTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    thisStart := builder.AddToken("this.")
    ownerStart := builder.AddToken("Environment")
    owner := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), ownerStart, "Environment".Length, thisStart, ownerStart + "Environment".Length, new int[](0))

    builder.AddToken(".")
    memberStart := builder.AddToken("NewLine")
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, "NewLine".Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(owner))

    return builder.Build(root)
}

func ExternalStaticNewLineFromEndTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "Environment")

    builder.AddToken(".")
    memberStart := builder.AddToken("NewLine")
    member := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, "NewLine".Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(owner))

    builder.AddToken("[")
    caretStart := builder.AddToken("^")
    one := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    fromEnd := builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression(), caretStart, 1, caretStart, 2, ColumnarRangePlannerChildren1(one))

    builder.AddToken("]")
    root := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(member, fromEnd))

    return builder.Build(root)
}

func ExternalStaticCurrentDirectoryRangeTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    owner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "Environment")

    builder.AddToken(".")
    memberStart := builder.AddToken("CurrentDirectory")
    member := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, "CurrentDirectory".Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(owner))

    builder.AddToken("[")
    zero := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    rangeStart := builder.AddToken("..")
    one := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    range := builder.AddNode(ColumnarExpressionNodeKind.RangeExpression(), rangeStart, 2, zero, builder.Source.Length, ColumnarRangePlannerChildren2(zero, one))

    builder.AddToken("]")
    root := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(member, range))

    return builder.Build(root)
}

func ExternalEmptyEnums(): List<ColumnarEnumInput> {
    return new List<ColumnarEnumInput>()
}

func ExternalEmptyStructs(): List<ColumnarStructInput> {
    return new List<ColumnarStructInput>()
}

func ExternalEmptyUnions(): List<ColumnarUnionInput> {
    return new List<ColumnarUnionInput>()
}

func ExternalEmptyInterfaces(): List<ColumnarInterfaceInput> {
    return new List<ColumnarInterfaceInput>()
}

func ExternalStampScopeFull(tree: ColumnarRangePlannerTestTree, factSource: string, enclosingTypeName: string, visibleTypeParameters: string[], structs: List<ColumnarStructInput>, additionalRootBindingNames: string[]?) {
    sources := new string[](1)
    fileNames := new string[](1)
    sources[0] = factSource
    fileNames[0] = "probe.nl"
    scope := ColumnarBindingScopeFacts.Create(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), ExternalEmptyEnums(), structs, ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    scope.PrepareExternalTypeBindings(null)
    tree.Nodes.SetBindingContext(scope.ForSourceFile(0), enclosingTypeName, visibleTypeParameters, additionalRootBindingNames)
}

func ExternalScopeForSources(sources: string[], structs: List<ColumnarStructInput>, interfaces: List<ColumnarInterfaceInput>): ColumnarBindingScopeFacts {
    fileNames := new string[](sources.Length)
    index := 0
    while index < fileNames.Length {
        fileNames[index] = "probe-" + index.ToString() + ".nl"
        index = index + 1
    }

    scope := ColumnarBindingScopeFacts.Create(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), ExternalEmptyEnums(), structs, ExternalEmptyUnions(), interfaces, null)

    scope.PrepareExternalTypeBindings(null)
    return scope
}

func ExternalStampScope(tree: ColumnarRangePlannerTestTree, factSource: string) {
    ExternalStampScopeFull(tree, factSource, "", new string[](0), ExternalEmptyStructs(), null)
}

func ExternalStampScopeWithTypeParameters(tree: ColumnarRangePlannerTestTree, factSource: string, visibleTypeParameters: string[]) {
    ExternalStampScopeFull(tree, factSource, "", visibleTypeParameters, ExternalEmptyStructs(), null)
}

func ExternalPlan(tree: ColumnarRangePlannerTestTree, bindings: ColumnarFragmentBindings): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    status := ColumnarExternalStaticMemberPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan)

    if status != ColumnarFragmentPlanStatus.Planned {
        throw new InvalidOperationException("Expected external static-member planner ownership.")
    }

    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func ExternalAssertLiteralField(
    ownerName: string,
    memberName: string,
    expectedType: Type,
    expectedText: string,
    factSource: string
) {
    tree := ExternalStaticMemberTree(ownerName, memberName)
    ExternalStampScope(tree, factSource)
    plan := ExternalPlan(tree, ColumnarRangePlannerEmptyBindings())
    assert plan.ResultType == expectedType
    assert plan.FieldCount == 0
    assert plan.OperationCount == 1
    assert ExecutorRunV3ScalarPlan(plan, expectedType) == expectedText
}

func ExternalAssertDeclines(tree: ColumnarRangePlannerTestTree, bindings: ColumnarFragmentBindings) {
    plan := new ColumnarCodePlan()
    assert ColumnarExternalStaticMemberPlanner.Plan(tree.Nodes, tree.Source, tree.Root, bindings, plan) == ColumnarFragmentPlanStatus.NotOwned

    ColumnarRangePlannerAssertEmptyRollback(plan)
}

func ExternalBindings(lifted: HashSet<string>? = null, boxed: HashSet<string>? = null, enclosing: HashSet<string>? = null, siblings: HashSet<string>? = null, visibleFunctions: HashSet<string>? = null): ColumnarFragmentBindings {
    return new ColumnarFragmentBindings(new Dictionary<string, int>(StringComparer.Ordinal), new Dictionary<string, Type>(StringComparer.Ordinal), new Dictionary<string, LocalBuilder>(StringComparer.Ordinal), new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal), lifted ?? new HashSet<string>(StringComparer.Ordinal), boxed ?? new HashSet<string>(StringComparer.Ordinal), enclosing ?? new HashSet<string>(StringComparer.Ordinal), siblings ?? new HashSet<string>(StringComparer.Ordinal), visibleFunctions ?? new HashSet<string>(StringComparer.Ordinal))
}

func ExternalNameSet(name: string): HashSet<string> {
    values := new HashSet<string>(StringComparer.Ordinal)
    values.Add(name)
    return values
}

func ExternalProbeLocal(valueType: Type): LocalBuilder {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorInfo := ExecutorRequiredConstructor(typeof(DynamicMethod), constructorTypes)
    constructorArguments := new object[](3)
    ExecutorSetObject(constructorArguments, 0, "ExternalBindingLocal")
    ExecutorSetObject(constructorArguments, 1, valueType)
    ExecutorSetObject(constructorArguments, 2, new Type[](0))
    dynamicMethod := (DynamicMethod)constructorInfo.Invoke(constructorArguments)
    return dynamicMethod.GetILGenerator().DeclareLocal(valueType)
}

func ExternalProbeFunction(tree: ColumnarRangePlannerTestTree, name: string = "Probe", typeParameters: string[]? = null): ColumnarFunctionInput {
    return new ColumnarFunctionInput(name, "string", new string[](0), new string[](0), tree.Nodes, tree.Root, false, typeParameters ?? new string[](0))
}

func ExternalStruct(name: string, fieldNames: string[], baseNames: string[], methods: List<ColumnarFunctionInput>, typeParameters: string[]? = null, isReference: bool = true): ColumnarStructInput {
    fieldTypes := new string[](fieldNames.Length)
    index := 0
    while index < fieldTypes.Length {
        fieldTypes[index] = "string"
        index = index + 1
    }

    return new ColumnarStructInput(name, fieldNames, fieldTypes, methods, new List<ColumnarConstructorInput>(), new List<ColumnarPropertyInput>(), isReference, baseNames, null, null, null, false, typeParameters ?? new string[](0))
}

func ExternalInterfaceWithMethod(name: string, methodName: string): ColumnarInterfaceInput {
    methodNames := new string[](1)
    returnTypes := new string[](1)
    paramNames := new string[][](1)
    paramTypes := new string[][](1)
    bodies := new ColumnarFunctionInput?[](1)
    methodNames[0] = methodName
    returnTypes[0] = "string"
    paramNames[0] = new string[](0)
    paramTypes[0] = new string[](0)
    return new ColumnarInterfaceInput(name, new string[](0), methodNames, returnTypes, paramNames, paramTypes, bodies)
}

test "external static-member planner owns exact field and property handles" {
    fieldTree := ExternalStaticMemberTree("OpCodes", "Ldsfld")
    ExternalStampScope(fieldTree, fieldTree.Source)
    fieldPlan := ExternalPlan(fieldTree, ColumnarRangePlannerEmptyBindings())
    assert fieldPlan.ResultType == typeof(OpCode)
    assert fieldPlan.FieldCount == 1
    assert fieldPlan.MethodCount == 0
    assert fieldPlan.OperationCount == 1
    assert fieldPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldsfld()
    assert fieldPlan.Fields[0].get_DeclaringType() == typeof(OpCodes)
    assert fieldPlan.Fields[0].get_FieldType() == typeof(OpCode)

    propertyTree := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(propertyTree, propertyTree.Source)
    propertyPlan := ExternalPlan(propertyTree, ColumnarRangePlannerEmptyBindings())
    assert propertyPlan.ResultType == typeof(string)
    assert propertyPlan.FieldCount == 0
    assert propertyPlan.MethodCount == 1
    assert propertyPlan.OperationCount == 1
    assert propertyPlan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert propertyPlan.Methods[0].get_ReturnType() == typeof(string)
    assert ExecutorRunV3ScalarPlan(propertyPlan, typeof(string)) == Environment.NewLine
}

test "external static-member planner owns runtime enum and primitive literal fields" {
    enumTree := ExternalStaticMemberTree("StringComparison", "Ordinal")
    ExternalStampScope(enumTree, enumTree.Source)
    enumPlan := ExternalPlan(enumTree, ColumnarRangePlannerEmptyBindings())
    enumType := Type.GetType("System.StringComparison")
    if enumType == null {
        throw new InvalidOperationException("StringComparison runtime type was not found.")
    }
    assert enumPlan.ResultType == enumType
    assert enumPlan.FieldCount == 0
    assert enumPlan.OperationCount == 1
    assert enumPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert ExecutorRunV3ScalarPlan(enumPlan, enumType) == "Ordinal"

    byteEnumTree := ExternalStaticMemberTree("JsonValueKind", "Object")
    ExternalStampScope(byteEnumTree, "import System.Text.Json\n")
    byteEnumPlan := ExternalPlan(
        byteEnumTree,
        ColumnarRangePlannerEmptyBindings()
    )
    assert byteEnumPlan.ResultType == typeof(JsonValueKind)
    assert byteEnumPlan.FieldCount == 0
    assert byteEnumPlan.OperationCount == 1
    assert byteEnumPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert ExecutorRunV3ScalarPlan(
        byteEnumPlan,
        typeof(JsonValueKind)
    ) == "Object"

    ExternalAssertLiteralField("int", "MinValue", typeof(int), "-2147483648", "")
    ExternalAssertLiteralField("int", "MaxValue", typeof(int), "2147483647", "")
    ExternalAssertLiteralField("long", "MinValue", typeof(long), "-9223372036854775808", "")
    ExternalAssertLiteralField("long", "MaxValue", typeof(long), "9223372036854775807", "")
    ExternalAssertLiteralField("uint", "MinValue", typeof(uint), "0", "")
    ExternalAssertLiteralField("uint", "MaxValue", typeof(uint), "4294967295", "")
    ExternalAssertLiteralField("ulong", "MinValue", typeof(ulong), "0", "")
    ExternalAssertLiteralField("ulong", "MaxValue", typeof(ulong), "18446744073709551615", "")
    ExternalAssertLiteralField("short", "MinValue", typeof(short), "-32768", "")
    ExternalAssertLiteralField("short", "MaxValue", typeof(short), "32767", "")
    ExternalAssertLiteralField("ushort", "MinValue", typeof(ushort), "0", "")
    ExternalAssertLiteralField("ushort", "MaxValue", typeof(ushort), "65535", "")
    ExternalAssertLiteralField("byte", "MinValue", typeof(byte), "0", "")
    ExternalAssertLiteralField("byte", "MaxValue", typeof(byte), "255", "")
    ExternalAssertLiteralField("sbyte", "MinValue", typeof(sbyte), "-128", "")
    ExternalAssertLiteralField("sbyte", "MaxValue", typeof(sbyte), "127", "")
    ExternalAssertLiteralField(
        "SearchOption",
        "TopDirectoryOnly",
        typeof(SearchOption),
        "TopDirectoryOnly",
        "import System.IO\n"
    )
    numberStylesType := Type.GetType("System.Globalization.NumberStyles")
    if numberStylesType == null {
        throw new InvalidOperationException(
            "NumberStyles runtime type was not found."
        )
    }
    ExternalAssertLiteralField(
        "NumberStyles",
        "HexNumber",
        numberStylesType,
        "HexNumber",
        "import System.Globalization\n"
    )

    nestedParts := new string[](2)
    nestedParts[0] = "Environment"
    nestedParts[1] = "SpecialFolder"
    nestedTree := ExternalQualifiedStaticMemberTree(nestedParts, "UserProfile")
    ExternalStampScope(nestedTree, "import System\n")
    nestedPlan := ExternalPlan(nestedTree, ColumnarRangePlannerEmptyBindings())
    nestedType := Type.GetType("System.Environment+SpecialFolder")
    if nestedType == null {
        throw new InvalidOperationException("Environment.SpecialFolder runtime type was not found.")
    }
    assert nestedPlan.ResultType == nestedType
    assert ExecutorRunV3ScalarPlan(
        nestedPlan,
        nestedType
    ) == "UserProfile"
}

test "external static-member planner owns closed pool properties and exact type aliases" {
    arrayTree := ExternalStaticMemberTree("ArrayPool", "Shared")
    ExternalStampScope(arrayTree, "import System.Buffers\n")
    arrayPlan := ExternalPlan(arrayTree, ColumnarRangePlannerEmptyBindings())
    arrayType := arrayPlan.ResultType
    if arrayType == null {
        throw new InvalidOperationException("ArrayPool plan had no result type.")
    }
    assert arrayType.get_IsGenericType()
    assert arrayType.GetGenericTypeDefinition().FullName == "System.Buffers.ArrayPool`1"
    assert arrayPlan.MethodCount == 1
    assert arrayPlan.OpCodeValues[0] == ColumnarCodePlanContract.Call()

    aliasTree := ExternalStaticMemberTree("ByteArrayPool", "Shared")
    ExternalStampScope(
        aliasTree,
        "import System.Buffers\ntype ByteArrayPool = ArrayPool<byte>\n"
    )
    aliasPlan := ExternalPlan(aliasTree, ColumnarRangePlannerEmptyBindings())
    assert aliasPlan.ResultType == arrayType

    wrongElementAlias := ExternalStaticMemberTree("ByteArrayPool", "Shared")
    ExternalStampScope(
        wrongElementAlias,
        "import System.Buffers\ntype ByteArrayPool = ArrayPool<int>\n"
    )
    ExternalAssertDeclines(
        wrongElementAlias,
        ColumnarRangePlannerEmptyBindings()
    )

    memoryTree := ExternalStaticMemberTree("ByteMemoryPool", "Shared")
    ExternalStampScope(
        memoryTree,
        "import System.Buffers\ntype ByteMemoryPool = MemoryPool<byte>\n"
    )
    memoryPlan := ExternalPlan(memoryTree, ColumnarRangePlannerEmptyBindings())
    memoryType := memoryPlan.ResultType
    if memoryType == null {
        throw new InvalidOperationException("MemoryPool plan had no result type.")
    }
    assert memoryType.GetGenericTypeDefinition().FullName == "System.Buffers.MemoryPool`1"

    wrongAlias := ExternalStaticMemberTree("ByteArrayPool", "Shared")
    ExternalStampScope(wrongAlias, "type ByteArrayPool = string\n")
    ExternalAssertDeclines(wrongAlias, ColumnarRangePlannerEmptyBindings())

    sourceClass := ExternalStaticMemberTree("ByteArrayPool", "Shared")
    ExternalStampScope(sourceClass, "class ByteArrayPool {}\n")
    ExternalAssertDeclines(sourceClass, ColumnarRangePlannerEmptyBindings())
}

test "external static-member planner owns fully qualified fields and properties" {
    opcodeOwner := new string[](4)
    opcodeOwner[0] = "System"
    opcodeOwner[1] = "Reflection"
    opcodeOwner[2] = "Emit"
    opcodeOwner[3] = "OpCodes"
    fieldTree := ExternalQualifiedStaticMemberTree(opcodeOwner, "Ldsfld")
    ExternalStampScope(fieldTree, fieldTree.Source)
    fieldPlan := ExternalPlan(fieldTree, ColumnarRangePlannerEmptyBindings())
    assert fieldPlan.ResultType == typeof(OpCode)
    assert fieldPlan.Fields[0].get_DeclaringType() == typeof(OpCodes)
    assert ExecutorRunV3ScalarPlan(fieldPlan, typeof(OpCode)) == "ldsfld"

    valueShadow := ExternalQualifiedStaticMemberTree(opcodeOwner, "Ldsfld")
    ExternalStampScope(valueShadow, valueShadow.Source)
    valueBindings := ExternalBindings(null, null, null, null, null)
    ColumnarRangePlannerAddParameter(
        valueBindings,
        "System",
        0,
        typeof(string)
    )
    ExternalAssertDeclines(valueShadow, valueBindings)

    aliasShadow := ExternalQualifiedStaticMemberTree(opcodeOwner, "Ldsfld")
    ExternalStampScope(
        aliasShadow,
        "import System.Reflection.Emit as System\n"
    )
    ExternalAssertDeclines(
        aliasShadow,
        ColumnarRangePlannerEmptyBindings()
    )

    exactSourceShadow := ExternalQualifiedStaticMemberTree(
        opcodeOwner,
        "Ldsfld"
    )
    ExternalStampScope(
        exactSourceShadow,
        "namespace System.Reflection.Emit\nclass OpCodes {}\n"
    )
    ExternalAssertDeclines(
        exactSourceShadow,
        ColumnarRangePlannerEmptyBindings()
    )

    environmentOwner := new string[](2)
    environmentOwner[0] = "System"
    environmentOwner[1] = "Environment"
    propertyTree := ExternalQualifiedStaticMemberTree(environmentOwner, "NewLine")

    ExternalStampScope(propertyTree, propertyTree.Source)
    propertyPlan := ExternalPlan(propertyTree, ColumnarRangePlannerEmptyBindings())

    assert propertyPlan.ResultType == typeof(string)
    assert ExecutorRunV3ScalarPlan(propertyPlan, typeof(string)) == Environment.NewLine

    nestedOwner := new string[](3)
    nestedOwner[0] = "System"
    nestedOwner[1] = "Environment"
    nestedOwner[2] = "SpecialFolder"
    nestedSourceShadow := ExternalQualifiedStaticMemberTree(
        nestedOwner,
        "UserProfile"
    )
    ExternalStampScope(
        nestedSourceShadow,
        "namespace System\nclass Environment { class SpecialFolder {} }\n"
    )
    ExternalAssertDeclines(
        nestedSourceShadow,
        ColumnarRangePlannerEmptyBindings()
    )
}

test "external static-member planner fails closed and rolls unsupported shapes back" {
    unsupported := ExternalStaticMemberTree("Environment", "Missing")
    ExternalStampScope(unsupported, unsupported.Source)
    ExternalAssertDeclines(unsupported, ColumnarRangePlannerEmptyBindings())

    wrongCase := ExternalStaticMemberTree("environment", "NewLine")
    ExternalStampScope(wrongCase, wrongCase.Source)
    ExternalAssertDeclines(wrongCase, ColumnarRangePlannerEmptyBindings())

    unstamped := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalAssertDeclines(unstamped, ColumnarRangePlannerEmptyBindings())

    explicitThis := ExternalStaticExplicitThisTree()
    ExternalStampScope(explicitThis, explicitThis.Source)
    ExternalAssertDeclines(explicitThis, ColumnarRangePlannerEmptyBindings())
}

test "external static-member append rejects schema v2 without mutating plan pools" {
    tree := ExternalStaticMemberTree("OpCodes", "Ldsfld")
    ExternalStampScope(tree, tree.Source)
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    _root := plan.BeginFragment(-1, ColumnarExpressionNodeKind.MemberAccessExpression(), tree.Root)

    resultType := typeof(int)

    assert throws InvalidOperationException {
        ColumnarExternalStaticMemberPlanner.TryAppendStaticMember(tree.Nodes, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(), plan, out resultType)
    }

    assert resultType == typeof(int)
    assert plan.SchemaVersion == ColumnarCodePlanContract.RecursiveSchemaVersion()
    assert plan.Status == ColumnarFragmentPlanStatus.NotOwned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Building
    assert plan.OperationCount == 0
    assert plan.FieldCount == 0
    assert plan.MethodCount == 0
    assert plan.FragmentCount == 1
}

test "external static-member planner rejects every nearer lexical binding tier" {
    tree := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(tree, tree.Source)

    parameter := ExternalBindings(null, null, null, null, null)
    ColumnarRangePlannerAddParameter(parameter, "Environment", 0, typeof(string))
    ExternalAssertDeclines(tree, parameter)

    local := ExternalBindings(null, null, null, null, null)
    local.Locals["Environment"] = ExternalProbeLocal(typeof(string))
    ExternalAssertDeclines(tree, local)

    lifted := ExternalBindings(ExternalNameSet("Environment"), null, null, null, null)
    ExternalAssertDeclines(tree, lifted)
    boxed := ExternalBindings(null, ExternalNameSet("Environment"), null, null, null)
    ExternalAssertDeclines(tree, boxed)
    enclosing := ExternalBindings(null, null, ExternalNameSet("Environment"), null, null)
    ExternalAssertDeclines(tree, enclosing)
    sibling := ExternalBindings(null, null, null, ExternalNameSet("Environment"), null)
    ExternalAssertDeclines(tree, sibling)
    visible := ExternalBindings(null, null, null, null, ExternalNameSet("Environment"))
    ExternalAssertDeclines(tree, visible)

    enumBindings := ExternalBindings(null, null, null, null, null)
    enumBindings.Enums["Environment"] = new ColumnarEnumDef(typeof(ColumnarRangePlannerProbeEnum), new Dictionary<string, int>(StringComparer.Ordinal))

    ExternalAssertDeclines(tree, enumBindings)
}

test "external static-member planner rejects source aliases types and type parameters" {
    aliasTree := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(aliasTree, "type Environment = string")
    ExternalAssertDeclines(aliasTree, ColumnarRangePlannerEmptyBindings())

    namespaceAlias := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(namespaceAlias, "import System as Environment\n")
    ExternalAssertDeclines(namespaceAlias, ColumnarRangePlannerEmptyBindings())

    fileAlias := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(fileAlias, "import \"other.nl\" as Environment\n")
    ExternalAssertDeclines(fileAlias, ColumnarRangePlannerEmptyBindings())

    unaliasedFileImport := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(unaliasedFileImport, "import \"other.nl\"\n")
    ExternalAssertDeclines(unaliasedFileImport, ColumnarRangePlannerEmptyBindings())

    sourceClass := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(sourceClass, "class Environment {}")
    ExternalAssertDeclines(sourceClass, ColumnarRangePlannerEmptyBindings())

    functionTypeParameter := ExternalStaticMemberTree("Environment", "NewLine")
    oneTypeParameter := new string[](1)
    oneTypeParameter[0] = "Environment"
    ExternalStampScopeWithTypeParameters(functionTypeParameter, functionTypeParameter.Source, oneTypeParameter)

    ExternalAssertDeclines(functionTypeParameter, ColumnarRangePlannerEmptyBindings())

    textOnly := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(textOnly, "func Text(): string { return \"type Environment = string\" }\n" + "// import System as Environment\n")

    _textOnlyPlan := ExternalPlan(textOnly, ColumnarRangePlannerEmptyBindings())

    unaliasedImport := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(unaliasedImport, "import System\n")
    _unaliasedImportPlan := ExternalPlan(unaliasedImport, ColumnarRangePlannerEmptyBindings())
}

test "external binding scope uses compact multiline declarations and aliases" {
    multilineType := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(multilineType, "type\nEnvironment = string\n")
    ExternalAssertDeclines(multilineType, ColumnarRangePlannerEmptyBindings())

    multilineNamespaceAlias := ExternalStaticMemberTree("Environment", "NewLine")

    ExternalStampScope(multilineNamespaceAlias, "import System\nas Environment\n")

    ExternalAssertDeclines(multilineNamespaceAlias, ColumnarRangePlannerEmptyBindings())

    multilineFileAlias := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(multilineFileAlias, "import \"other.nl\"\nas Environment\n")

    ExternalAssertDeclines(multilineFileAlias, ColumnarRangePlannerEmptyBindings())

    nestedTypeKeyword := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(nestedTypeKeyword, "func Probe(): string {\n" + "    type Environment = string\n" + "    return \"ok\"\n" + "}\n")

    _nestedTypeKeywordPlan := ExternalPlan(nestedTypeKeyword, ColumnarRangePlannerEmptyBindings())
}

test "external binding scope keeps aliases and ordered imports file local" {
    sources := new string[](2)
    sources[0] = "import System\n" + "import System.Collections.\nGeneric\n"

    sources[1] = "import System\nas Environment\n" + "import System.Text\n"

    scope := ExternalScopeForSources(sources, ExternalEmptyStructs(), ExternalEmptyInterfaces())

    firstScope := scope.ForSourceFile(0)
    assert firstScope.UnaliasedNamespaceImportCount == 2
    assert firstScope.UnaliasedNamespaceImportAt(0) == "System"
    assert firstScope.UnaliasedNamespaceImportAt(1) == "System.Collections.Generic"

    firstTree := ExternalStaticMemberTree("Environment", "NewLine")
    firstTree.Nodes.SetBindingContext(firstScope, "", new string[](0), new string[](0))

    _firstPlan := ExternalPlan(firstTree, ColumnarRangePlannerEmptyBindings())

    secondScope := scope.ForSourceFile(1)
    assert secondScope.UnaliasedNamespaceImportCount == 1
    assert secondScope.UnaliasedNamespaceImportAt(0) == "System.Text"
    secondTree := ExternalStaticMemberTree("Environment", "NewLine")
    secondTree.Nodes.SetBindingContext(secondScope, "", new string[](0), new string[](0))

    ExternalAssertDeclines(secondTree, ColumnarRangePlannerEmptyBindings())

    missingTree := ExternalStaticMemberTree("Environment", "NewLine")
    missingTree.Nodes.SetBindingContext(scope.ForSourceFile(99), "", new string[](0), new string[](0))

    ExternalAssertDeclines(missingTree, ColumnarRangePlannerEmptyBindings())

    incompleteSources := new string[](1)
    incompleteSources[0] = "import System\n"
    incompleteScope := ExternalScopeForSources(incompleteSources, ExternalEmptyStructs(), ExternalEmptyInterfaces())

    missingReferences := new List<string>()
    missingReferences.Add("/nsharp/missing/external-binding-reference.dll")
    incompleteScope.PrepareExternalTypeBindings(missingReferences)
    incompleteTree := ExternalStaticMemberTree("Environment", "NewLine")
    incompleteTree.Nodes.SetBindingContext(incompleteScope.ForSourceFile(0), "", new string[](0), new string[](0))

    _knownBeforeBrokenPlan := ExternalPlan(incompleteTree, ColumnarRangePlannerEmptyBindings())

    unknownSources := new string[](1)
    unknownSources[0] = "import Missing.Namespace\nimport System\n"
    unknownScope := ExternalScopeForSources(unknownSources, ExternalEmptyStructs(), ExternalEmptyInterfaces())

    unknownScope.PrepareExternalTypeBindings(missingReferences)
    unknownTree := ExternalStaticMemberTree("Environment", "NewLine")
    unknownTree.Nodes.SetBindingContext(unknownScope.ForSourceFile(0), "", new string[](0), new string[](0))

    ExternalAssertDeclines(unknownTree, ColumnarRangePlannerEmptyBindings())
}

test "external binding class scope follows analyzer first-base semantics" {
    externalBaseNames := new string[](1)
    externalBaseNames[0] = "Exception"
    externalStructs := new List<ColumnarStructInput>()
    externalStructs.Add(ExternalStruct("ExternalDerived", new string[](0), externalBaseNames, new List<ColumnarFunctionInput>(), null, true))

    externalSources := new string[](1)
    externalSources[0] = "import System\nclass ExternalDerived: Exception {}\n"
    externalScope := ExternalScopeForSources(externalSources, externalStructs, ExternalEmptyInterfaces()).ForSourceFile(0)

    externalTree := ExternalStaticMemberTree("Environment", "NewLine")
    externalTree.Nodes.SetBindingContext(externalScope, "ExternalDerived", new string[](0), new string[](0))

    _externalBasePlan := ExternalPlan(externalTree, ColumnarRangePlannerEmptyBindings())

    collidingBaseNames := new string[](1)
    collidingBaseNames[0] = "TaskCompletionSource"
    collidingStructs := new List<ColumnarStructInput>()
    collidingStructs.Add(ExternalStruct("ExternalMemberDerived", new string[](0), collidingBaseNames, new List<ColumnarFunctionInput>(), null, true))

    collidingSources := new string[](1)
    collidingSources[0] = "import System.Threading.Tasks\nclass ExternalMemberDerived: TaskCompletionSource {}\n"
    collidingScope := ExternalScopeForSources(collidingSources, collidingStructs, ExternalEmptyInterfaces()).ForSourceFile(0)

    collidingTree := ExternalStaticMemberTree("Task", "CompletedTask")
    collidingTree.Nodes.SetBindingContext(collidingScope, "ExternalMemberDerived", new string[](0), new string[](0))

    ExternalAssertDeclines(collidingTree, ColumnarRangePlannerEmptyBindings())

    externalInterfaceNames := new string[](1)
    externalInterfaceNames[0] = "IDisposable"
    externalInterfaceStructs := new List<ColumnarStructInput>()
    externalInterfaceStructs.Add(ExternalStruct("ExternalInterfaceDerived", new string[](0), externalInterfaceNames, new List<ColumnarFunctionInput>(), null, true))

    externalInterfaceSources := new string[](1)
    externalInterfaceSources[0] = "import System\nclass ExternalInterfaceDerived: IDisposable {}\n"
    externalInterfaceScope := ExternalScopeForSources(externalInterfaceSources, externalInterfaceStructs, ExternalEmptyInterfaces()).ForSourceFile(0)

    externalInterfaceTree := ExternalStaticMemberTree("Environment", "NewLine")

    externalInterfaceTree.Nodes.SetBindingContext(externalInterfaceScope, "ExternalInterfaceDerived", new string[](0), new string[](0))

    _externalInterfacePlan := ExternalPlan(externalInterfaceTree, ColumnarRangePlannerEmptyBindings())

    interfaceMethods := new List<ColumnarInterfaceInput>()
    interfaceMethods.Add(ExternalInterfaceWithMethod("IHasEnvironment", "Environment"))

    interfaceBaseNames := new string[](1)
    interfaceBaseNames[0] = "IHasEnvironment"
    reader := ExternalStruct("Reader", new string[](0), interfaceBaseNames, new List<ColumnarFunctionInput>(), null, true)

    interfaceStructs := new List<ColumnarStructInput>()
    interfaceStructs.Add(reader)
    oneSource := new string[](1)
    oneSource[0] = "class Reader {}\ninterface IHasEnvironment {}\n"
    interfaceScope := ExternalScopeForSources(oneSource, interfaceStructs, interfaceMethods).ForSourceFile(0)

    interfaceTree := ExternalStaticMemberTree("Environment", "NewLine")
    interfaceTree.Nodes.SetBindingContext(interfaceScope, "Reader", new string[](0), new string[](0))

    ExternalAssertDeclines(interfaceTree, ColumnarRangePlannerEmptyBindings())

    valueBaseNames := new string[](1)
    valueBaseNames[0] = "IHasEnvironment"
    valueStructs := new List<ColumnarStructInput>()
    valueStructs.Add(ExternalStruct("ValueReader", new string[](0), valueBaseNames, new List<ColumnarFunctionInput>(), null, false))

    valueSource := new string[](1)
    valueSource[0] = "struct ValueReader {}\ninterface IHasEnvironment {}\n"
    valueScope := ExternalScopeForSources(valueSource, valueStructs, interfaceMethods).ForSourceFile(0)

    valueTree := ExternalStaticMemberTree("Environment", "NewLine")
    valueTree.Nodes.SetBindingContext(valueScope, "ValueReader", new string[](0), new string[](0))

    _valuePlan := ExternalPlan(valueTree, ColumnarRangePlannerEmptyBindings())

    inheritedField := new string[](1)
    inheritedField[0] = "Environment"
    qualifiedStructs := new List<ColumnarStructInput>()
    qualifiedStructs.Add(ExternalStruct("Left.Base", inheritedField, new string[](0), new List<ColumnarFunctionInput>(), null, true))

    qualifiedStructs.Add(ExternalStruct("Right.Base", new string[](0), new string[](0), new List<ColumnarFunctionInput>(), null, true))

    exactBaseNames := new string[](1)
    exactBaseNames[0] = "Left.Base"
    qualifiedStructs.Add(ExternalStruct("ExactReader", new string[](0), exactBaseNames, new List<ColumnarFunctionInput>(), null, true))

    ambiguousBaseNames := new string[](1)
    ambiguousBaseNames[0] = "Base"
    qualifiedStructs.Add(ExternalStruct("AmbiguousReader", new string[](0), ambiguousBaseNames, new List<ColumnarFunctionInput>(), null, true))

    qualifiedSource := new string[](1)
    qualifiedSource[0] = "class ExactReader {}\nclass AmbiguousReader {}\n"
    qualifiedScope := ExternalScopeForSources(qualifiedSource, qualifiedStructs, ExternalEmptyInterfaces()).ForSourceFile(0)

    exactTree := ExternalStaticMemberTree("Environment", "NewLine")
    exactTree.Nodes.SetBindingContext(qualifiedScope, "ExactReader", new string[](0), new string[](0))

    ExternalAssertDeclines(exactTree, ColumnarRangePlannerEmptyBindings())

    namespacedStructs := new List<ColumnarStructInput>()
    namespacedStructs.Add(ExternalStruct("Demo.Base", inheritedField, new string[](0), new List<ColumnarFunctionInput>(), null, true))

    namespacedBaseNames := new string[](1)
    namespacedBaseNames[0] = "Base"
    namespacedStructs.Add(ExternalStruct("Demo.Reader", new string[](0), namespacedBaseNames, new List<ColumnarFunctionInput>(), null, true))

    namespacedSources := new string[](1)
    namespacedSources[0] = "namespace Demo\nclass Base {}\nclass Reader {}\n"
    namespacedScope := ExternalScopeForSources(namespacedSources, namespacedStructs, ExternalEmptyInterfaces()).ForSourceFile(0)

    namespacedTree := ExternalStaticMemberTree("Environment", "NewLine")
    namespacedTree.Nodes.SetBindingContext(namespacedScope, "Demo.Reader", new string[](0), new string[](0))

    ExternalAssertDeclines(namespacedTree, ColumnarRangePlannerEmptyBindings())

    orderedStructs := new List<ColumnarStructInput>()
    orderedStructs.Add(ExternalStruct("Left.Base", inheritedField, new string[](0), new List<ColumnarFunctionInput>(), null, true))

    orderedStructs.Add(ExternalStruct("Right.Base", new string[](0), new string[](0), new List<ColumnarFunctionInput>(), null, true))

    orderedBaseNames := new string[](1)
    orderedBaseNames[0] = "Base"
    orderedReader := ExternalStruct("Demo.Reader", new string[](0), orderedBaseNames, new List<ColumnarFunctionInput>(), null, true)

    orderedReader.SourceFileId = 2
    orderedStructs.Add(orderedReader)
    orderedSources := new string[](3)
    orderedSources[0] = "namespace Left\nclass Base {}\n"
    orderedSources[1] = "namespace Right\nclass Base {}\n"
    orderedSources[2] = "namespace Demo\nimport Right\nimport Left\nclass Reader: Base {}\n"
    orderedScope := ExternalScopeForSources(orderedSources, orderedStructs, ExternalEmptyInterfaces()).ForSourceFile(2)

    orderedTree := ExternalStaticMemberTree("Environment", "NewLine")
    orderedTree.Nodes.SetBindingContext(orderedScope, "Demo.Reader", new string[](0), new string[](0))

    _orderedBasePlan := ExternalPlan(orderedTree, ColumnarRangePlannerEmptyBindings())

    ambiguousTree := ExternalStaticMemberTree("Environment", "NewLine")
    ambiguousTree.Nodes.SetBindingContext(qualifiedScope, "AmbiguousReader", new string[](0), new string[](0))

    ExternalAssertDeclines(ambiguousTree, ColumnarRangePlannerEmptyBindings())
}

test "program input stamps current inherited and owner-generic member scope" {
    tree := ExternalStaticMemberTree("Environment", "NewLine")
    probeMethods := new List<ColumnarFunctionInput>()
    probeMethods.Add(ExternalProbeFunction(tree, "Probe", null))
    baseFields := new string[](1)
    baseFields[0] = "Environment"
    baseInput := ExternalStruct("Base", baseFields, new string[](0), new List<ColumnarFunctionInput>(), null, true)

    derivedBases := new string[](1)
    derivedBases[0] = "Base"
    derivedInput := ExternalStruct("Derived", new string[](0), derivedBases, probeMethods, null, true)

    structs := new List<ColumnarStructInput>()
    structs.Add(baseInput)
    structs.Add(derivedInput)
    inheritedProgram := ColumnarProgramInput.CreateSingleSource(tree.Source, new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), structs, ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    inheritedProgram.PrepareExternalTypeBindings(null)
    ExternalAssertDeclines(tree, ColumnarRangePlannerEmptyBindings())

    genericTree := ExternalStaticMemberTree("Environment", "NewLine")
    typeParameters := new string[](1)
    typeParameters[0] = "Environment"
    genericMethods := new List<ColumnarFunctionInput>()
    genericMethods.Add(ExternalProbeFunction(genericTree, "Probe", null))
    genericStructs := new List<ColumnarStructInput>()
    genericStructs.Add(ExternalStruct("GenericOwner", new string[](0), new string[](0), genericMethods, typeParameters, true))

    genericProgram := ColumnarProgramInput.CreateSingleSource(genericTree.Source, new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), genericStructs, ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    genericProgram.PrepareExternalTypeBindings(null)
    ExternalAssertDeclines(genericTree, ColumnarRangePlannerEmptyBindings())

    methodTree := ExternalStaticMemberTree("Environment", "NewLine")
    methodInputs := new List<ColumnarFunctionInput>()
    methodInputs.Add(ExternalProbeFunction(methodTree, "Environment", null))
    methodInputs.Add(ExternalProbeFunction(methodTree, "Probe", null))
    methodStructs := new List<ColumnarStructInput>()
    methodStructs.Add(ExternalStruct("MethodOwner", new string[](0), new string[](0), methodInputs, null, true))

    methodProgram := ColumnarProgramInput.CreateSingleSource(methodTree.Source, new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), methodStructs, ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    methodProgram.PrepareExternalTypeBindings(null)
    ExternalAssertDeclines(methodTree, ColumnarRangePlannerEmptyBindings())
}

test "interface bodies use sequential method scope without inherited interface members" {
    laterTree := ExternalStaticMemberTree("Environment", "NewLine")
    laterMethodNames := new string[](2)
    laterMethodNames[0] = "Read"
    laterMethodNames[1] = "Environment"
    laterReturns := new string[](2)
    laterReturns[0] = "string"
    laterReturns[1] = "string"
    laterParamNames := new string[][](2)
    laterParamTypes := new string[][](2)
    laterParamNames[0] = new string[](0)
    laterParamNames[1] = new string[](0)
    laterParamTypes[0] = new string[](0)
    laterParamTypes[1] = new string[](0)
    laterBodies := new ColumnarFunctionInput?[](2)
    laterBodies[0] = ExternalProbeFunction(laterTree, "Read", null)
    laterInterfaces := new List<ColumnarInterfaceInput>()
    laterInterfaces.Add(new ColumnarInterfaceInput("LaterMember", new string[](0), laterMethodNames, laterReturns, laterParamNames, laterParamTypes, laterBodies))

    laterProgram := ColumnarProgramInput.CreateSingleSource(laterTree.Source, new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), laterInterfaces, null)

    laterProgram.PrepareExternalTypeBindings(null)
    _laterPlan := ExternalPlan(laterTree, ColumnarRangePlannerEmptyBindings())

    priorTree := ExternalStaticMemberTree("Environment", "NewLine")
    priorMethodNames := new string[](2)
    priorMethodNames[0] = "Environment"
    priorMethodNames[1] = "Read"
    priorReturns := new string[](2)
    priorReturns[0] = "string"
    priorReturns[1] = "string"
    priorParamNames := new string[][](2)
    priorParamTypes := new string[][](2)
    priorParamNames[0] = new string[](0)
    priorParamNames[1] = new string[](0)
    priorParamTypes[0] = new string[](0)
    priorParamTypes[1] = new string[](0)
    priorBodies := new ColumnarFunctionInput?[](2)
    priorBodies[1] = ExternalProbeFunction(priorTree, "Read", null)
    priorInterfaces := new List<ColumnarInterfaceInput>()
    priorInterfaces.Add(new ColumnarInterfaceInput("PriorMember", new string[](0), priorMethodNames, priorReturns, priorParamNames, priorParamTypes, priorBodies))

    priorProgram := ColumnarProgramInput.CreateSingleSource(priorTree.Source, new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), priorInterfaces, null)

    priorProgram.PrepareExternalTypeBindings(null)
    ExternalAssertDeclines(priorTree, ColumnarRangePlannerEmptyBindings())

    inheritedTree := ExternalStaticMemberTree("Environment", "NewLine")
    baseMethodNames := new string[](1)
    baseMethodNames[0] = "Environment"
    baseReturns := new string[](1)
    baseReturns[0] = "string"
    baseParamNames := new string[][](1)
    baseParamTypes := new string[][](1)
    baseParamNames[0] = new string[](0)
    baseParamTypes[0] = new string[](0)
    baseBodies := new ColumnarFunctionInput?[](1)
    baseInterface := new ColumnarInterfaceInput("BaseInterface", new string[](0), baseMethodNames, baseReturns, baseParamNames, baseParamTypes, baseBodies)

    derivedBases := new string[](1)
    derivedBases[0] = "BaseInterface"
    derivedMethodNames := new string[](1)
    derivedMethodNames[0] = "Read"
    derivedReturns := new string[](1)
    derivedReturns[0] = "string"
    derivedParamNames := new string[][](1)
    derivedParamTypes := new string[][](1)
    derivedParamNames[0] = new string[](0)
    derivedParamTypes[0] = new string[](0)
    derivedBodies := new ColumnarFunctionInput?[](1)
    derivedBodies[0] = ExternalProbeFunction(inheritedTree, "Read", null)
    derivedInterface := new ColumnarInterfaceInput("DerivedInterface", derivedBases, derivedMethodNames, derivedReturns, derivedParamNames, derivedParamTypes, derivedBodies)

    inheritedInterfaces := new List<ColumnarInterfaceInput>()
    inheritedInterfaces.Add(baseInterface)
    inheritedInterfaces.Add(derivedInterface)
    inheritedProgram := ColumnarProgramInput.CreateSingleSource(inheritedTree.Source, new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), inheritedInterfaces, null)

    inheritedProgram.PrepareExternalTypeBindings(null)
    _inheritedPlan := ExternalPlan(inheritedTree, ColumnarRangePlannerEmptyBindings())
}

test "derived expression tables inherit external binding context in N sharp" {
    parent := ExternalStaticMemberTree("Environment", "NewLine")
    additionalNames := new string[](1)
    additionalNames[0] = "Environment"
    ExternalStampScopeFull(parent, parent.Source, "", new string[](0), ExternalEmptyStructs(), additionalNames)

    derived := ExternalStaticMemberTree("Environment", "NewLine")
    ColumnarNodeTable.InheritBindingContext(derived.Nodes, parent.Nodes)

    ExternalAssertDeclines(derived, ColumnarRangePlannerEmptyBindings())
}

test "program input merge restamps cross-file alias scope" {
    tree := ExternalStaticMemberTree("Environment", "NewLine")
    functions := new List<ColumnarFunctionInput>()
    functions.Add(ExternalProbeFunction(tree, "Probe", null))
    first := ColumnarProgramInput.CreateSingleSource(tree.Source, functions, ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    second := ColumnarProgramInput.CreateSingleSource("type Environment = string", new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    ColumnarProgramInput.AssignSourceFileId(first, 0)
    ColumnarProgramInput.AssignSourceFileId(second, 1)
    programs := new ColumnarProgramInput[](2)
    programs[0] = first
    programs[1] = second
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = tree.Source
    sources[1] = "type Environment = string"
    fileNames[0] = "first.nl"
    fileNames[1] = "second.nl"
    merged := ColumnarProgramInput.MergeSourceFiles(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), programs)

    merged.PrepareExternalTypeBindings(null)
    ExternalAssertDeclines(tree, ColumnarRangePlannerEmptyBindings())
}

test "extensionless file imports preserve unrelated external roots" {
    tree := ExternalStaticMemberTree("Environment", "NewLine")
    functions := new List<ColumnarFunctionInput>()
    functions.Add(ExternalProbeFunction(tree, "Probe", null))
    firstSource := "import \"Models\"\n" + tree.Source
    first := ColumnarProgramInput.CreateSingleSource(firstSource, functions, ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    secondSource := "class Model {}"
    second := ColumnarProgramInput.CreateSingleSource(secondSource, new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    ColumnarProgramInput.AssignSourceFileId(first, 0)
    ColumnarProgramInput.AssignSourceFileId(second, 1)
    programs := new ColumnarProgramInput[](2)
    programs[0] = first
    programs[1] = second
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = firstSource
    sources[1] = secondSource
    fileNames[0] = "Program.nl"
    fileNames[1] = "Models.nl"
    merged := ColumnarProgramInput.MergeSourceFiles(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), programs)

    merged.PrepareExternalTypeBindings(null)
    _plan := ExternalPlan(tree, ColumnarRangePlannerEmptyBindings())
}

test "bare file imports resolve from the project root" {
    tree := ExternalStaticMemberTree("Environment", "NewLine")
    functions := new List<ColumnarFunctionInput>()
    functions.Add(ExternalProbeFunction(tree, "Probe", null))
    firstSource := "import \"Models\"\nimport System\n" + tree.Source
    first := ColumnarProgramInput.CreateSingleSource(firstSource, functions, ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    secondSource := "class Model {}"
    second := ColumnarProgramInput.CreateSingleSource(secondSource, new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    ColumnarProgramInput.AssignSourceFileId(first, 0)
    ColumnarProgramInput.AssignSourceFileId(second, 1)
    programs := new ColumnarProgramInput[](2)
    programs[0] = first
    programs[1] = second
    projectRoot := Path.GetFullPath("nsharp-binding-project-root")
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = firstSource
    sources[1] = secondSource
    fileNames[0] = Path.Combine(Path.Combine(projectRoot, "src"), "Program.nl")

    fileNames[1] = Path.Combine(projectRoot, "Models.nl")
    merged := ColumnarProgramInput.MergeSourceFilesAtProjectRoot(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), programs, projectRoot)

    merged.PrepareExternalTypeBindings(null)
    _plan := ExternalPlan(tree, ColumnarRangePlannerEmptyBindings())
}

test "relative file imports resolve from the current source directory" {
    projectRoot := Path.GetFullPath("nsharp-binding-relative-imports")
    sourceDirectory := Path.Combine(projectRoot, "src/nested")
    sources := new string[](3)
    fileNames := new string[](3)
    sources[0] = "import \"./Sibling\"\nimport \"../Shared\"\nimport System\n"
    sources[1] = "class SiblingModel {}"
    sources[2] = "class SharedModel {}"
    fileNames[0] = Path.Combine(sourceDirectory, "Program.nl")
    fileNames[1] = Path.Combine(sourceDirectory, "Sibling.nl")
    fileNames[2] = Path.Combine(projectRoot, "src/Shared.nl")
    scope := ColumnarBindingScopeFacts.Create(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), projectRoot)

    scope.PrepareExternalTypeBindings(null)
    tree := ExternalStaticMemberTree("Environment", "NewLine")
    tree.Nodes.SetBindingContext(scope.ForSourceFile(0), "", new string[](0), new string[](0))

    _plan := ExternalPlan(tree, ColumnarRangePlannerEmptyBindings())
}

test "external binding scope includes primary parameters and nested types" {
    primaryTree := ExternalStaticMemberTree("Environment", "NewLine")
    primaryMethods := new List<ColumnarFunctionInput>()
    primaryMethods.Add(ExternalProbeFunction(primaryTree, "Read", null))
    primaryNames := new string[](1)
    primaryTypes := new string[](1)
    primaryNames[0] = "Environment"
    primaryTypes[0] = "string"
    initializerBody := new ColumnarFunctionInput(".ctor", "void", primaryNames, primaryTypes, primaryTree.Nodes, primaryTree.Root, false)

    constructors := new List<ColumnarConstructorInput>()
    constructors.Add(new ColumnarConstructorInput(initializerBody, -1, new int[](0), new string[](0), null, null, true))

    primaryStructs := new List<ColumnarStructInput>()
    primaryStructs.Add(new ColumnarStructInput("Owner", new string[](0), new string[](0), primaryMethods, constructors, new List<ColumnarPropertyInput>(), true))

    primaryProgram := ColumnarProgramInput.CreateSingleSource("class Owner(Environment: string) { saved: string = Environment }", new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), primaryStructs, ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    primaryProgram.PrepareExternalTypeBindings(null)
    ExternalAssertDeclines(primaryTree, ColumnarRangePlannerEmptyBindings())

    derivedTree := ExternalStaticMemberTree("Environment", "NewLine")
    baseInitializerTree := ExternalStaticMemberTree("Environment", "NewLine")
    baseInitializerBody := new ColumnarFunctionInput(".ctor", "void", primaryNames, primaryTypes, baseInitializerTree.Nodes, baseInitializerTree.Root, false)

    baseConstructors := new List<ColumnarConstructorInput>()
    baseConstructors.Add(new ColumnarConstructorInput(baseInitializerBody, -1, new int[](0), new string[](0), null, null, true))

    baseInput := new ColumnarStructInput("PrimaryBase", new string[](0), new string[](0), new List<ColumnarFunctionInput>(), baseConstructors, new List<ColumnarPropertyInput>(), true)

    derivedMethods := new List<ColumnarFunctionInput>()
    derivedMethods.Add(ExternalProbeFunction(derivedTree, "Read", null))
    derivedBaseNames := new string[](1)
    derivedBaseNames[0] = "PrimaryBase"
    derivedInput := ExternalStruct("PrimaryDerived", new string[](0), derivedBaseNames, derivedMethods, null, true)

    derivedStructs := new List<ColumnarStructInput>()
    derivedStructs.Add(baseInput)
    derivedStructs.Add(derivedInput)
    derivedProgram := ColumnarProgramInput.CreateSingleSource("class PrimaryBase(Environment: string) {}\n" + "class PrimaryDerived: PrimaryBase {}\n", new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), derivedStructs, ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    derivedProgram.PrepareExternalTypeBindings(null)
    _derivedPrimaryParameterPlan := ExternalPlan(derivedTree, ColumnarRangePlannerEmptyBindings())

    nestedTree := ExternalStaticMemberTree("Environment", "NewLine")
    nestedMethods := new List<ColumnarFunctionInput>()
    nestedMethods.Add(ExternalProbeFunction(nestedTree, "Read", null))
    nestedStructs := new List<ColumnarStructInput>()
    nestedStructs.Add(ExternalStruct("NestedOwner", new string[](0), new string[](0), nestedMethods, null, true))

    nestedProgram := ColumnarProgramInput.CreateSingleSource("class NestedOwner { class Environment {} }", new List<ColumnarFunctionInput>(), ExternalEmptyEnums(), nestedStructs, ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    nestedProgram.PrepareExternalTypeBindings(null)
    ExternalAssertDeclines(nestedTree, ColumnarRangePlannerEmptyBindings())
}

test "external binding source scan resets expression-bodied where clauses" {
    tree := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(tree, "func Earlier<T>(): string where T: class => \"ok\"\n" + "class Environment {}\n")

    ExternalAssertDeclines(tree, ColumnarRangePlannerEmptyBindings())
}

test "external binding resolves unaliased file-import exports exactly" {
    sources := new string[](2)
    fileNames := new string[](2)
    sources[0] = "import \"helpers.nl\"\nimport System\n"
    sources[1] = "func Helper(): string { return \"ok\" }\n"
    fileNames[0] = "main.nl"
    fileNames[1] = "helpers.nl"
    scope := ColumnarBindingScopeFacts.Create(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    scope.PrepareExternalTypeBindings(null)
    tree := ExternalStaticMemberTree("Environment", "NewLine")
    tree.Nodes.SetBindingContext(scope.ForSourceFile(0), "", new string[](0), new string[](0))

    _unrelatedImportPlan := ExternalPlan(tree, ColumnarRangePlannerEmptyBindings())

    sources[1] = "func Environment(): string { return \"shadow\" }\n"
    shadowScope := ColumnarBindingScopeFacts.Create(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    shadowScope.PrepareExternalTypeBindings(null)
    shadowTree := ExternalStaticMemberTree("Environment", "NewLine")
    shadowTree.Nodes.SetBindingContext(shadowScope.ForSourceFile(0), "", new string[](0), new string[](0))

    ExternalAssertDeclines(shadowTree, ColumnarRangePlannerEmptyBindings())

    sources[1] = "private func Environment(): string { return \"private\" }\n"
    privateScope := ColumnarBindingScopeFacts.Create(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    privateScope.PrepareExternalTypeBindings(null)
    privateTree := ExternalStaticMemberTree("Environment", "NewLine")
    privateTree.Nodes.SetBindingContext(privateScope.ForSourceFile(0), "", new string[](0), new string[](0))

    _privateImportPlan := ExternalPlan(privateTree, ColumnarRangePlannerEmptyBindings())

    sources[1] = "internal func Environment(): string { return \"internal\" }\n"
    internalScope := ColumnarBindingScopeFacts.Create(ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames), ExternalEmptyEnums(), ExternalEmptyStructs(), ExternalEmptyUnions(), ExternalEmptyInterfaces(), null)

    internalScope.PrepareExternalTypeBindings(null)
    internalTree := ExternalStaticMemberTree("Environment", "NewLine")
    internalTree.Nodes.SetBindingContext(internalScope.ForSourceFile(0), "", new string[](0), new string[](0))

    _internalImportPlan := ExternalPlan(internalTree, ColumnarRangePlannerEmptyBindings())
}

test "ambiguous project type shorts do not hide imported external types" {
    structs := new List<ColumnarStructInput>()
    structs.Add(ExternalStruct("A.Environment", new string[](0), new string[](0), new List<ColumnarFunctionInput>(), null, true))

    structs.Add(ExternalStruct("B.Environment", new string[](0), new string[](0), new List<ColumnarFunctionInput>(), null, true))

    sources := new string[](3)
    sources[0] = "namespace A\nclass Environment {}\n"
    sources[1] = "namespace B\nclass Environment {}\n"
    sources[2] = "namespace C\nimport System\n"
    scope := ExternalScopeForSources(sources, structs, ExternalEmptyInterfaces()).ForSourceFile(2)

    tree := ExternalStaticMemberTree("Environment", "NewLine")
    tree.Nodes.SetBindingContext(scope, "", new string[](0), new string[](0))

    _ambiguousProjectPlan := ExternalPlan(tree, ColumnarRangePlannerEmptyBindings())
}

test "an unrelated namespaced source type does not hide an external type" {
    structs := new List<ColumnarStructInput>()
    structs.Add(ExternalStruct("A.Environment", new string[](0), new string[](0), new List<ColumnarFunctionInput>(), null, true))

    sources := new string[](2)
    sources[0] = "namespace A\nclass Environment {}\n"
    sources[1] = "namespace C\nimport System\n"
    scope := ExternalScopeForSources(sources, structs, ExternalEmptyInterfaces()).ForSourceFile(1)

    tree := ExternalStaticMemberTree("Environment", "NewLine")
    tree.Nodes.SetBindingContext(scope, "", new string[](0), new string[](0))

    _unrelatedNamespacedPlan := ExternalPlan(tree, ColumnarRangePlannerEmptyBindings())
}

test "package declarations take precedence over namespace declarations" {
    sources := new string[](2)
    sources[0] = "namespace Wrong\nclass Environment {}\n"
    sources[1] = "namespace Wrong\npackage Right\nimport System\n"
    scope := ExternalScopeForSources(sources, ExternalEmptyStructs(), ExternalEmptyInterfaces()).ForSourceFile(1)

    tree := ExternalStaticMemberTree("Environment", "NewLine")
    tree.Nodes.SetBindingContext(scope, "", new string[](0), new string[](0))

    _packagePrecedencePlan := ExternalPlan(tree, ColumnarRangePlannerEmptyBindings())
}

test "range planner composes external static properties recursively" {
    fromEnd := ExternalStaticNewLineFromEndTree()
    ExternalStampScope(fromEnd, fromEnd.Source)
    fromEndPlan := ColumnarRangePlannerPlan(fromEnd, ColumnarRangePlannerEmptyBindings())

    assert fromEndPlan.ResultType == typeof(char)
    assert fromEndPlan.OpCodeValues[0] == ColumnarCodePlanContract.Call()

    slice := ExternalStaticCurrentDirectoryRangeTree()
    ExternalStampScope(slice, slice.Source)
    slicePlan := ColumnarRangePlannerPlan(slice, ColumnarRangePlannerEmptyBindings())

    assert slicePlan.ResultType == typeof(string)
    assert slicePlan.OpCodeValues[0] == ColumnarCodePlanContract.Call()

    shadowed := ExternalStaticNewLineFromEndTree()
    ExternalStampScope(shadowed, shadowed.Source)
    shadowedBindings := ExternalBindings(null, ExternalNameSet("Environment"), null, null, null)

    shadowedPlan := new ColumnarCodePlan()
    assert ColumnarRangeIndexPlanner.Plan(shadowed.Nodes, shadowed.Source, shadowed.Root, shadowedBindings, ColumnarRangeIndexHandles.Resolve(), shadowedPlan) == ColumnarFragmentPlanStatus.NotOwned

    ColumnarRangePlannerAssertEmptyRollback(shadowedPlan)
}

// ---- THE ROOT-APPEND SEQUENCE IS A FACTORING, NOT A SECOND SPELLING (015-B15) ----
//
// `TryAppendRoot` was FACTORED OUT of `Plan` rather than written beside it, and that is the whole of
// byte identity for door kind 8's SEVENTH-arm half: the two callers differ in exactly the wrapper —
// `PrepareV3`/`CompleteV3` versus an already-open schema-v4 method-body plan — and in nothing else.
// The same move `015-B7` made on the direct-call owner, `015-B9` on the primitive-binary owner and
// `015-B14` on the instance-member owner.
test "the external static-member root sequence is the sequence Plan runs" {
    propertyTree := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(propertyTree, propertyTree.Source)
    planned := ExternalPlan(propertyTree, ColumnarRangePlannerEmptyBindings())

    viaAppend := new ColumnarCodePlan()
    viaAppend.PrepareMethodBody()
    appendType := typeof(int)
    assert ColumnarExternalStaticMemberPlanner.TryAppendRoot(propertyTree.Nodes, propertyTree.Source, propertyTree.Root, ColumnarRangePlannerEmptyBindings(), viaAppend, out appendType)

    assert appendType == planned.ResultType
    assert viaAppend.OperationCount == planned.OperationCount
    assert viaAppend.OpCodeValues[0] == planned.OpCodeValues[0]
    assert viaAppend.MethodCount == planned.MethodCount
    assert viaAppend.Methods[0].get_Name() == planned.Methods[0].get_Name()
    declaringType := viaAppend.Methods[0].get_DeclaringType()
    assert declaringType.FullName == "System.Environment"
    assert viaAppend.FragmentCount == planned.FragmentCount
    assert viaAppend.OpenFragmentCount == 0
    assert viaAppend.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()

    // The FIELD shape through the same seam, so the factoring is proved for both of the owner's
    // non-literal appends rather than for the one that happens to be a `call`.
    fieldTree := ExternalStaticMemberTree("OpCodes", "Ldsfld")
    ExternalStampScope(fieldTree, fieldTree.Source)
    fieldPlanned := ExternalPlan(fieldTree, ColumnarRangePlannerEmptyBindings())

    fieldAppend := new ColumnarCodePlan()
    fieldAppend.PrepareMethodBody()
    fieldType := typeof(int)
    assert ColumnarExternalStaticMemberPlanner.TryAppendRoot(fieldTree.Nodes, fieldTree.Source, fieldTree.Root, ColumnarRangePlannerEmptyBindings(), fieldAppend, out fieldType)

    assert fieldType == fieldPlanned.ResultType
    assert fieldAppend.OperationCount == fieldPlanned.OperationCount
    assert fieldAppend.OpCodeValues[0] == ColumnarCodePlanContract.Ldsfld()
    assert fieldAppend.FieldCount == 1
    assert fieldAppend.Fields[0].get_Name() == fieldPlanned.Fields[0].get_Name()
    assert fieldAppend.Fields[0].get_DeclaringType() == typeof(OpCodes)
}

// THE NULL CONTRACT IS THE SOFTER ONE THE SECOND CALLER NEEDS, AND `Plan`'s IS UNCHANGED. A door that
// hands this a null table must decline rather than crash; `Plan` still throws through `ValidateInputs`
// before the sequence is reached, so the owner's existing contract is untouched.
test "the external static-member root sequence declines bad inputs while Plan still throws" {
    tree := ExternalStaticMemberTree("Environment", "NewLine")
    ExternalStampScope(tree, tree.Source)

    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    resultType := typeof(int)

    assert !ColumnarExternalStaticMemberPlanner.TryAppendRoot(null, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(), plan, out resultType)
    assert !ColumnarExternalStaticMemberPlanner.TryAppendRoot(tree.Nodes, null, tree.Root, ColumnarRangePlannerEmptyBindings(), plan, out resultType)
    assert !ColumnarExternalStaticMemberPlanner.TryAppendRoot(tree.Nodes, tree.Source, -1, ColumnarRangePlannerEmptyBindings(), plan, out resultType)
    assert !ColumnarExternalStaticMemberPlanner.TryAppendRoot(tree.Nodes, tree.Source, tree.Nodes.Kinds.Length, ColumnarRangePlannerEmptyBindings(), plan, out resultType)
    assert !ColumnarExternalStaticMemberPlanner.TryAppendRoot(tree.Nodes, tree.Source, tree.Root, null, plan, out resultType)
    assert !ColumnarExternalStaticMemberPlanner.TryAppendRoot(tree.Nodes, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(), null, out resultType)
    assert plan.OperationCount == 0
    assert plan.Status == ColumnarFragmentPlanStatus.NotOwned

    assert throws InvalidOperationException {
        ColumnarExternalStaticMemberPlanner.Plan(null, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(), new ColumnarCodePlan())
    }
}

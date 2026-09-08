namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// These direct controls keep the declaration phase observable before the retained C# constructor
// body emitter consumes its jobs.  The readonly-init native suite retains complete source/runtime
// coverage; this file pins the live declaration state, failure phase, and exact IL prefixes that
// select where later body emission begins.
func ConstructorDeclarationControlsDefinition(name: string, genericParameterCount: int): ColumnarStructDef {
    builder := TypeOfCreateBuilder(
        name,
        "ColumnarConstructorDeclarationControls." + name,
        genericParameterCount
    )
    return new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        name
    )
}

func ConstructorDeclarationControlsAddField(
    definition: ColumnarStructDef,
    name: string,
    fieldType: Type,
    attributes: FieldAttributes
): FieldBuilder {
    field := definition.Builder.DefineField(name, fieldType, attributes)
    definition.Fields[name] = field
    return field
}

func ConstructorDeclarationControlsSetFieldOrder(
    definition: ColumnarStructDef,
    names: string[]
) {
    definition.SetFieldOrder(names)
}

func ConstructorDeclarationControlsEmptyBody(
    name: string,
    parameterNames: string[],
    parameterCanonicals: string[]
): ColumnarFunctionInput {
    return new ColumnarFunctionInput(
        name,
        "void",
        parameterNames,
        parameterCanonicals,
        DeclarationPlanEmptyBody(),
        0,
        false
    )
}

func ConstructorDeclarationControlsAssignmentTree(
    targetName: string,
    operatorText: string
): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    target := builder.AddLeaf(
        ColumnarExpressionNodeKind.IdentifierExpression(),
        targetName
    )
    operatorStart := builder.AddToken(operatorText)
    value := builder.AddLeaf(
        ColumnarExpressionNodeKind.IntLiteralExpression(),
        "1"
    )
    assignment := builder.AddNode(
        14,
        operatorStart,
        operatorText.Length,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren2(target, value)
    )
    statement := builder.AddNode(
        23,
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(assignment)
    )
    root := builder.AddNode(
        25,
        -1,
        0,
        0,
        builder.Source.Length,
        ColumnarRangePlannerChildren1(statement)
    )
    return builder.Build(root)
}

// The central node-text owner recognizes a one-character spanless binary operator as `=`.  The
// declaration validator consumes that shared fact, so retain the source-less shape alongside the
// ordinary parser-shaped assignment above.
func ConstructorDeclarationControlsSpanlessEqualsTree(
    targetName: string
): ColumnarRangePlannerTestTree {
    source := targetName + "1"
    kinds := new int[](5)
    kinds[0] = 25
    kinds[1] = 23
    kinds[2] = 14
    kinds[3] = ColumnarExpressionNodeKind.IdentifierExpression()
    kinds[4] = ColumnarExpressionNodeKind.IntLiteralExpression()
    valueStarts := new int[](5)
    valueStarts[2] = -1
    valueStarts[4] = targetName.Length
    valueLengths := new int[](5)
    valueLengths[2] = 1
    valueLengths[3] = targetName.Length
    valueLengths[4] = 1
    childStarts := new int[](5)
    childStarts[1] = 1
    childStarts[2] = 2
    childStarts[3] = 4
    childStarts[4] = 4
    childCounts := new int[](5)
    childCounts[0] = 1
    childCounts[1] = 1
    childCounts[2] = 2
    children := new int[](4)
    children[0] = 1
    children[1] = 2
    children[2] = 3
    children[3] = 4
    nodes := new ColumnarNodeTable(
        kinds,
        valueStarts,
        valueLengths,
        childStarts,
        childCounts,
        children
    )
    return new ColumnarRangePlannerTestTree(nodes, source, 0)
}

func ConstructorDeclarationControlsBodyFromTree(
    name: string,
    tree: ColumnarRangePlannerTestTree
): ColumnarFunctionInput {
    return new ColumnarFunctionInput(
        name,
        "void",
        new string[](0),
        new string[](0),
        tree.Nodes,
        tree.Root,
        false
    )
}

func ConstructorDeclarationControlsConstructor(
    body: ColumnarFunctionInput,
    chainKind: int,
    chainArgumentKinds: int[],
    chainArgumentTexts: string[],
    isSynthesizedInitializer: bool = false
): ColumnarConstructorInput {
    return new ColumnarConstructorInput(
        body,
        chainKind,
        chainArgumentKinds,
        chainArgumentTexts,
        null,
        null,
        isSynthesizedInitializer,
        0
    )
}

func ConstructorDeclarationControlsInput(
    name: string,
    constructors: IReadOnlyList<ColumnarConstructorInput>
): ColumnarStructInput {
    return new ColumnarStructInput(
        name,
        new string[](0),
        new string[](0),
        new List<ColumnarFunctionInput>(),
        constructors,
        new List<ColumnarPropertyInput>(),
        true
    )
}

func ConstructorDeclarationControlsDefinitions(
    definitions: ColumnarStructDef[]
): Dictionary<string, ColumnarStructDef> {
    result := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
    index := 0
    while index < definitions.Length {
        result[definitions[index].DeclaredTypeName] = definitions[index]
        index = index + 1
    }
    return result
}

func ConstructorDeclarationControlsProgram(
    source: string,
    structs: IReadOnlyList<ColumnarStructInput>
): ColumnarProgramInput {
    return ColumnarProgramInput.CreateSingleSource(
        source,
        new List<ColumnarFunctionInput>(),
        new List<ColumnarEnumInput>(),
        structs,
        new List<ColumnarUnionInput>(),
        new List<ColumnarInterfaceInput>(),
        null
    )
}

func ConstructorDeclarationControlsResolutions(
    program: ColumnarProgramInput,
    definitions: ColumnarStructDef[]
): ColumnarSemanticTypeResolution[] {
    registry := ConstructorDeclarationControlsDefinitions(definitions)
    resolutions := new ColumnarSemanticTypeResolution[](definitions.Length)
    index := 0
    while index < definitions.Length {
        resolutions[index] = SemanticTypeResolution(
            program,
            0,
            SemanticEmptyEnums(),
            registry,
            SemanticEmptyUnions(),
            null,
            definitions[index].DeclaredTypeName
        )
        index = index + 1
    }
    return resolutions
}

func ConstructorDeclarationControlsEmptyInts(): int[] {
    return new int[](0)
}

func ConstructorDeclarationControlsEmptyTexts(): string[] {
    return new string[](0)
}

func ConstructorDeclarationControlsEmptyRegistry(): Dictionary<string, ColumnarStructDef> {
    return new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
}

func ConstructorDeclarationControlsOneType(value: Type): Type[] {
    values := new Type[](1)
    values[0] = value
    return values
}

func ConstructorDeclarationControlsTwoTypes(
    first: Type,
    second: Type
): Type[] {
    values := new Type[](2)
    values[0] = first
    values[1] = second
    return values
}

func ConstructorDeclarationControlsOneText(value: string): string[] {
    values := new string[](1)
    values[0] = value
    return values
}

func ConstructorDeclarationControlsTwoTexts(
    first: string,
    second: string
): string[] {
    values := new string[](2)
    values[0] = first
    values[1] = second
    return values
}

func ConstructorDeclarationControlsOneKind(value: int): int[] {
    values := new int[](1)
    values[0] = value
    return values
}

func ConstructorDeclarationControlsTwoKinds(
    first: int,
    second: int
): int[] {
    values := new int[](2)
    values[0] = first
    values[1] = second
    return values
}

func ConstructorDeclarationControlsDefineUserConstructor(
    definition: ColumnarStructDef,
    parameterTypes: Type[]
): ConstructorBuilder {
    return definition.DefineUserConstructor(
        parameterTypes,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts()
    )
}

func ConstructorDeclarationControlsChainResolution(
    definitions: ColumnarStructDef[]
): ColumnarSemanticTypeResolution {
    inputs := new List<ColumnarStructInput>()
    index := 0
    while index < definitions.Length {
        inputs.Add(
            ConstructorDeclarationControlsInput(
                definitions[index].DeclaredTypeName,
                new List<ColumnarConstructorInput>()
            )
        )
        index = index + 1
    }
    program := ConstructorDeclarationControlsProgram("", inputs)
    return ConstructorDeclarationControlsResolutions(program, definitions)[0]
}

func ConstructorDeclarationControlsExternalBase(
    name: string,
    attributes: MethodAttributes,
    parameterTypes: Type[]
): Type {
    builder := TypeOfCreateBuilder(
        name,
        "ColumnarConstructorDeclarationControls.External." + name,
        0
    )
    constructorInfo := builder.DefineConstructor(
        attributes,
        CallingConventions.Standard,
        parameterTypes
    )
    il := constructorInfo.GetILGenerator()
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(
        OpCodes.Call,
        ExecutorRequiredConstructor(typeof(object), Type.EmptyTypes)
    )
    il.Emit(OpCodes.Ret)
    return IdentityBake(builder)
}

func ConstructorDeclarationControlsExternalDerived(
    name: string,
    baseType: Type
): ColumnarStructDef {
    definition := ConstructorDeclarationControlsDefinition(name, 0)
    definition.RecordBase(null, baseType)
    definition.Builder.SetParent(baseType)
    return definition
}

func ConstructorDeclarationControlsReadInt32(values: int[], index: int): int {
    return values[index] | (values[index + 1] << 8) | (values[index + 2] << 16) | (values[index + 3] << 24)
}

func ConstructorDeclarationControlsResolveMethodToken(
    owner: MethodBase,
    token: int
): MethodBase {
    parameterTypes := ConstructorDeclarationControlsOneType(typeof(int))
    resolveMethod := ExecutorRequiredMethod(
        typeof(Module),
        "ResolveMethod",
        parameterTypes
    )
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, token)
    value := TypeOfRequiredInvocation(
        resolveMethod,
        owner.get_Module(),
        arguments
    )
    resolved := value as MethodBase
    if resolved == null {
        throw new InvalidOperationException(
            "The constructor call token did not resolve to a method."
        )
    }
    return resolved
}

test "constructor declaration owner retains source-order user jobs and depth-order default jobs" {
    user := ConstructorDeclarationControlsDefinition("ConstructorDeclarationJobsUser", 0)
    initialized := ConstructorDeclarationControlsDefinition("ConstructorDeclarationJobsInitialized", 0)
    baseDefinition := ConstructorDeclarationControlsDefinition("ConstructorDeclarationJobsBase", 0)
    derived := ConstructorDeclarationControlsDefinition("ConstructorDeclarationJobsDerived", 0)
    derived.BaseDef = baseDefinition
    derived.ExactBaseType = baseDefinition.Builder

    ConstructorDeclarationControlsAddField(
        initialized,
        "Value",
        typeof(int),
        FieldAttributes.Public
    )
    initializedNames := ConstructorDeclarationControlsOneText("Value")
    ConstructorDeclarationControlsSetFieldOrder(initialized, initializedNames)
    initializerTree := ConstructorDeclarationControlsAssignmentTree("Value", "=")
    initializer := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsBodyFromTree("Initialize", initializerTree),
        0,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        true
    )

    firstParameters := ConstructorDeclarationControlsOneText("count")
    firstCanonicals := ConstructorDeclarationControlsOneText("int")
    firstUser := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody("First", firstParameters, firstCanonicals),
        0,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        false
    )
    secondParameters := ConstructorDeclarationControlsOneText("label")
    secondCanonicals := ConstructorDeclarationControlsOneText("string")
    secondUser := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody("Second", secondParameters, secondCanonicals),
        0,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        false
    )
    userConstructors := new List<ColumnarConstructorInput>()
    userConstructors.Add(firstUser)
    userConstructors.Add(secondUser)
    initializedConstructors := new List<ColumnarConstructorInput>()
    initializedConstructors.Add(initializer)

    inputs := new List<ColumnarStructInput>()
    inputs.Add(ConstructorDeclarationControlsInput(user.DeclaredTypeName, userConstructors))
    inputs.Add(ConstructorDeclarationControlsInput(initialized.DeclaredTypeName, initializedConstructors))
    inputs.Add(ConstructorDeclarationControlsInput(baseDefinition.DeclaredTypeName, new List<ColumnarConstructorInput>()))
    inputs.Add(ConstructorDeclarationControlsInput(derived.DeclaredTypeName, new List<ColumnarConstructorInput>()))
    definitions := new ColumnarStructDef[](4)
    definitions[0] = user
    definitions[1] = initialized
    definitions[2] = baseDefinition
    definitions[3] = derived
    depths := new int[](4)
    depths[0] = 0
    depths[1] = 2
    depths[2] = 0
    depths[3] = 1
    program := ConstructorDeclarationControlsProgram(initializerTree.Source, inputs)
    result := ColumnarConstructorDeclarationPlanner.Declare(
        program,
        inputs,
        definitions,
        ConstructorDeclarationControlsResolutions(program, definitions),
        depths
    )

    assert result.Succeeded
    assert Object.ReferenceEquals(result.ObjectConstructor, ExecutorRequiredConstructor(typeof(object), Type.EmptyTypes))
    assert result.ConstructorJobs.Count == 2
    firstJob := result.ConstructorJobs[0]
    secondJob := result.ConstructorJobs[1]
    assert Object.ReferenceEquals(firstJob.Struct, user)
    assert Object.ReferenceEquals(firstJob.Ctor, firstUser)
    assert Object.ReferenceEquals(firstJob.Builder, user.Constructors[0].Builder)
    assert firstJob.Ordinals["count"] == 1
    assert firstJob.ParamTypes["count"] == typeof(int)
    assert Object.ReferenceEquals(secondJob.Struct, user)
    assert Object.ReferenceEquals(secondJob.Ctor, secondUser)
    assert Object.ReferenceEquals(secondJob.Builder, user.Constructors[1].Builder)
    assert secondJob.Ordinals["label"] == 1
    assert secondJob.ParamTypes["label"] == typeof(string)

    assert initialized.InstanceInitializerPlan != null
    assert initialized.InstanceInitializerPlan.NeedsHelper
    assert initialized.InstanceInitializerPlan.InlineOrdinals.Length == 0
    assert initialized.InstanceInitializerPlan.HelperOrdinals.Length == 1
    assert initialized.InstanceInitializerPlan.HelperOrdinals[0] == 0
    assert initialized.InstanceInitializerFields.Contains("Value")
    assert Object.ReferenceEquals(initialized.InstanceInitializerCtor, initializer)
    assert result.InitializerJobs.Count == 1
    assert Object.ReferenceEquals(result.InitializerJobs[0].Struct, initialized)
    assert Object.ReferenceEquals(result.InitializerJobs[0].Ctor, initializer)
    assert Object.ReferenceEquals(result.InitializerJobs[0].Builder, initialized.InstanceInitializerMethod)

    assert baseDefinition.DefaultCtor != null
    assert derived.DefaultCtor != null
    assert initialized.DefaultCtor != null
    assert result.DefaultConstructorJobs.Count == 2
    assert Object.ReferenceEquals(result.DefaultConstructorJobs[0].Struct, derived)
    assert Object.ReferenceEquals(result.DefaultConstructorJobs[0].Builder, derived.DefaultCtor)
    assert Object.ReferenceEquals(result.DefaultConstructorJobs[1].Struct, initialized)
    assert Object.ReferenceEquals(result.DefaultConstructorJobs[1].Builder, initialized.DefaultCtor)
}

test "constructor declaration owner retains initialized state when a later base-chain declaration declines" {
    initialized := ConstructorDeclarationControlsDefinition("ConstructorDeclarationPartialInitialized", 0)
    ConstructorDeclarationControlsAddField(
        initialized,
        "Ready",
        typeof(int),
        FieldAttributes.Public
    )
    ConstructorDeclarationControlsSetFieldOrder(
        initialized,
        ConstructorDeclarationControlsOneText("Ready")
    )
    initializerTree := ConstructorDeclarationControlsAssignmentTree("Ready", "=")
    initializer := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsBodyFromTree("Initialize", initializerTree),
        0,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        true
    )
    initializedConstructors := new List<ColumnarConstructorInput>()
    initializedConstructors.Add(initializer)

    failing := ConstructorDeclarationControlsDefinition("ConstructorDeclarationPartialFailing", 0)
    unreadNames := ConstructorDeclarationControlsOneText("neverRead")
    // The base-chain decline must occur before parameter canonical indexing.  An attempted parameter
    // pass would index this intentionally absent column and turn the meaningful decline into a crash.
    unreadBody := ConstructorDeclarationControlsEmptyBody(
        "Broken",
        unreadNames,
        ConstructorDeclarationControlsEmptyTexts()
    )
    failingConstructor := ConstructorDeclarationControlsConstructor(
        unreadBody,
        2,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        false
    )
    failingConstructors := new List<ColumnarConstructorInput>()
    failingConstructors.Add(failingConstructor)
    inputs := new List<ColumnarStructInput>()
    inputs.Add(ConstructorDeclarationControlsInput(initialized.DeclaredTypeName, initializedConstructors))
    inputs.Add(ConstructorDeclarationControlsInput(failing.DeclaredTypeName, failingConstructors))
    definitions := new ColumnarStructDef[](2)
    definitions[0] = initialized
    definitions[1] = failing
    depths := new int[](2)
    program := ConstructorDeclarationControlsProgram(initializerTree.Source, inputs)
    result := ColumnarConstructorDeclarationPlanner.Declare(
        program,
        inputs,
        definitions,
        ConstructorDeclarationControlsResolutions(program, definitions),
        depths
    )

    assert !result.Succeeded
    assert result.DeclineSite == "emit.ctor.base-chain-without-base"
    assert result.DeclineMessage == "constructor base initializer requires a modeled base class"
    assert result.DeclineMember == failing.Builder.get_Name() + ".constructor"
    assert result.ConstructorJobs.Count == 0
    assert result.DefaultConstructorJobs.Count == 0
    assert result.InitializerJobs.Count == 1
    assert Object.ReferenceEquals(result.InitializerJobs[0].Struct, initialized)
    assert Object.ReferenceEquals(result.InitializerJobs[0].Ctor, initializer)
    assert initialized.InstanceInitializerPlan != null
    assert initialized.InstanceInitializerPlan.NeedsHelper
    assert initialized.InstanceInitializerFields.Contains("Ready")
    assert Object.ReferenceEquals(initialized.InstanceInitializerCtor, initializer)
    assert initialized.InstanceInitializerMethod != null
    assert failing.Constructors.Count == 0
}

test "constructor declaration owner validates seeded nullable and simple-assignment constructor bodies" {
    definition := ConstructorDeclarationControlsDefinition("ConstructorDeclarationBodyValidation", 0)
    ConstructorDeclarationControlsAddField(definition, "Seeded", typeof(int), FieldAttributes.Public)
    ConstructorDeclarationControlsAddField(definition, "Assigned", typeof(int), FieldAttributes.Public)
    ConstructorDeclarationControlsAddField(definition, "Optional", typeof(int), FieldAttributes.Public)
    ConstructorDeclarationControlsSetFieldOrder(
        definition,
        ConstructorDeclarationControlsTwoTexts("Seeded", "Assigned")
    )
    definition.NullableFields.Add("Optional")
    definition.InstanceInitializerFields.Add("Seeded")

    simple := ConstructorDeclarationControlsAssignmentTree("Assigned", "=")
    assert ColumnarConstructorDeclarationPlanner.IsValidReferenceCtorBody(
        simple.Nodes,
        simple.Source,
        definition,
        simple.Root
    )
    spanless := ConstructorDeclarationControlsSpanlessEqualsTree("Assigned")
    assert ColumnarConstructorDeclarationPlanner.IsValidReferenceCtorBody(
        spanless.Nodes,
        spanless.Source,
        definition,
        spanless.Root
    )

    compound := ConstructorDeclarationControlsAssignmentTree("Assigned", "+")
    assert !ColumnarConstructorDeclarationPlanner.IsValidReferenceCtorBody(
        compound.Nodes,
        compound.Source,
        definition,
        compound.Root
    )
    foreign := ConstructorDeclarationControlsAssignmentTree("Other", "=")
    assert !ColumnarConstructorDeclarationPlanner.IsValidReferenceCtorBody(
        foreign.Nodes,
        foreign.Source,
        definition,
        foreign.Root
    )
    returning := MethodBodyFactsBareReturnBody()
    assert !ColumnarConstructorDeclarationPlanner.IsValidReferenceCtorBody(
        returning,
        "return",
        definition,
        0
    )
    assert !ColumnarConstructorDeclarationPlanner.IsValidReferenceCtorBody(
        simple.Nodes,
        simple.Source,
        null,
        simple.Root
    )
}

test "constructor declaration owner prioritizes parameterless definitions and fails missing bases before IL" {
    priority := ConstructorDeclarationControlsDefinition("ConstructorDeclarationParameterlessPriority", 0)
    firstUser := ConstructorDeclarationControlsDefineUserConstructor(
        priority,
        ConstructorDeclarationControlsOneType(typeof(int))
    )
    zeroUser := ConstructorDeclarationControlsDefineUserConstructor(
        priority,
        Type.EmptyTypes
    )
    laterZeroUser := ConstructorDeclarationControlsDefineUserConstructor(
        priority,
        Type.EmptyTypes
    )
    priority.DefaultCtor = priority.Builder.DefineDefaultConstructor(MethodAttributes.Public)
    assert Object.ReferenceEquals(ColumnarConstructorDeclarationPlanner.ResolveParameterlessCtor(priority), priority.DefaultCtor)
    assert !Object.ReferenceEquals(firstUser, zeroUser)
    assert !Object.ReferenceEquals(zeroUser, laterZeroUser)

    firstZero := ConstructorDeclarationControlsDefinition("ConstructorDeclarationFirstZero", 0)
    ConstructorDeclarationControlsDefineUserConstructor(
        firstZero,
        ConstructorDeclarationControlsOneType(typeof(string))
    )
    selectedZero := ConstructorDeclarationControlsDefineUserConstructor(firstZero, Type.EmptyTypes)
    ConstructorDeclarationControlsDefineUserConstructor(firstZero, Type.EmptyTypes)
    assert Object.ReferenceEquals(ColumnarConstructorDeclarationPlanner.ResolveParameterlessCtor(firstZero), selectedZero)

    syntheticZero := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody(
            "SyntheticZero",
            new string[](0),
            new string[](0)
        ),
        0,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        true
    )
    syntheticWithParameter := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody(
            "SyntheticWithParameter",
            ConstructorDeclarationControlsOneText("value"),
            ConstructorDeclarationControlsOneText("int")
        ),
        0,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        true
    )
    ordinary := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody(
            "Ordinary",
            new string[](0),
            new string[](0)
        ),
        0,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        false
    )
    assert ColumnarConstructorDeclarationPlanner.IsZeroParamSynthesizedInitializer(syntheticZero)
    assert !ColumnarConstructorDeclarationPlanner.IsZeroParamSynthesizedInitializer(syntheticWithParameter)
    synthOnly := new List<ColumnarConstructorInput>()
    synthOnly.Add(syntheticZero)
    assert !ColumnarConstructorDeclarationPlanner.HasCallableConstructor(
        ConstructorDeclarationControlsInput("ConstructorDeclarationSynthOnly", synthOnly)
    )
    synthAndOrdinary := new List<ColumnarConstructorInput>()
    synthAndOrdinary.Add(syntheticZero)
    synthAndOrdinary.Add(ordinary)
    assert ColumnarConstructorDeclarationPlanner.HasCallableConstructor(
        ConstructorDeclarationControlsInput("ConstructorDeclarationOrdinary", synthAndOrdinary)
    )

    missingBase := ConstructorDeclarationControlsDefinition("ConstructorDeclarationMissingBase", 0)
    derived := ConstructorDeclarationControlsDefinition("ConstructorDeclarationMissingBaseDerived", 0)
    derived.BaseDef = missingBase
    il := ReferenceCoercionIl("ConstructorDeclarationMissingBaseChain")
    assert throws InvalidOperationException {
        ColumnarConstructorDeclarationPlanner.EmitCtorBaseChain(
            il,
            derived,
            ExecutorRequiredConstructor(typeof(object), Type.EmptyTypes)
        )
    }
    assert ReferenceCoercionIlOffset(il) == 0

    invalidBase := ConstructorDeclarationControlsDefinition("ConstructorDeclarationInvalidExactBase", 0)
    invalidBase.DefaultCtor = invalidBase.Builder.DefineDefaultConstructor(MethodAttributes.Public)
    invalidDerived := ConstructorDeclarationControlsDefinition("ConstructorDeclarationInvalidExactDerived", 0)
    invalidDerived.BaseDef = invalidBase
    invalidDerived.ExactBaseType = typeof(string)
    invalidBaseCallIl := ReferenceCoercionIl("ConstructorDeclarationInvalidExactBaseCall")
    assert throws ArgumentException {
        ColumnarConstructorDeclarationPlanner.EmitCtorBaseChain(
            invalidBaseCallIl,
            invalidDerived,
            ExecutorRequiredConstructor(typeof(object), Type.EmptyTypes)
        )
    }
    assert ReferenceCoercionIlOffset(invalidBaseCallIl) == 1

    invalidSelf := ConstructorDeclarationControlsDefineUserConstructor(
        invalidDerived,
        Type.EmptyTypes
    )
    invalidChain := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody("InvalidExactBaseChain", new string[](0), new string[](0)),
        2,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        false
    )
    invalidDefinitions := new ColumnarStructDef[](2)
    invalidDefinitions[0] = invalidBase
    invalidDefinitions[1] = invalidDerived
    invalidChainIl := ReferenceCoercionIl("ConstructorDeclarationInvalidExactChain")
    assert throws ArgumentException {
        ColumnarConstructorDeclarationPlanner.EmitChainedConstructorCall(
            invalidChain,
            invalidSelf,
            invalidDerived,
            new Dictionary<string, int>(StringComparer.Ordinal),
            new Dictionary<string, Type>(StringComparer.Ordinal),
            ConstructorDeclarationControlsChainResolution(invalidDefinitions).Structs,
            ConstructorDeclarationControlsDefinitions(invalidDefinitions),
            invalidChainIl
        )
    }
    assert ReferenceCoercionIlOffset(invalidChainIl) == 0
}

test "constructor declaration owner resolves only accessible external parameterless constructors" {
    publicBase := ConstructorDeclarationControlsExternalBase(
        "ConstructorDeclarationPublicExternalBase",
        (MethodAttributes)6,
        Type.EmptyTypes
    )
    familyBase := ConstructorDeclarationControlsExternalBase(
        "ConstructorDeclarationFamilyExternalBase",
        (MethodAttributes)4,
        Type.EmptyTypes
    )
    familyOrAssemblyBase := ConstructorDeclarationControlsExternalBase(
        "ConstructorDeclarationFamilyOrAssemblyExternalBase",
        (MethodAttributes)5,
        Type.EmptyTypes
    )
    privateBase := ConstructorDeclarationControlsExternalBase(
        "ConstructorDeclarationPrivateExternalBase",
        (MethodAttributes)1,
        Type.EmptyTypes
    )
    assemblyBase := ConstructorDeclarationControlsExternalBase(
        "ConstructorDeclarationAssemblyExternalBase",
        (MethodAttributes)3,
        Type.EmptyTypes
    )
    familyAndAssemblyBase := ConstructorDeclarationControlsExternalBase(
        "ConstructorDeclarationFamilyAndAssemblyExternalBase",
        (MethodAttributes)2,
        Type.EmptyTypes
    )
    parameterizedBase := ConstructorDeclarationControlsExternalBase(
        "ConstructorDeclarationParameterizedExternalBase",
        (MethodAttributes)6,
        ConstructorDeclarationControlsOneType(typeof(int))
    )

    publicConstructor := ColumnarConstructorDeclarationPlanner.ResolveAccessibleExternalParameterlessConstructor(publicBase)
    familyConstructor := ColumnarConstructorDeclarationPlanner.ResolveAccessibleExternalParameterlessConstructor(familyBase)
    familyOrAssemblyConstructor := ColumnarConstructorDeclarationPlanner.ResolveAccessibleExternalParameterlessConstructor(familyOrAssemblyBase)
    assert publicConstructor != null
    assert ((int)publicConstructor.get_Attributes() & 7) == 6
    assert familyConstructor != null
    assert ((int)familyConstructor.get_Attributes() & 7) == 4
    assert familyOrAssemblyConstructor != null
    assert ((int)familyOrAssemblyConstructor.get_Attributes() & 7) == 5
    assert ColumnarConstructorDeclarationPlanner.ResolveAccessibleExternalParameterlessConstructor(privateBase) == null
    assert ColumnarConstructorDeclarationPlanner.ResolveAccessibleExternalParameterlessConstructor(assemblyBase) == null
    assert ColumnarConstructorDeclarationPlanner.ResolveAccessibleExternalParameterlessConstructor(familyAndAssemblyBase) == null
    assert ColumnarConstructorDeclarationPlanner.ResolveAccessibleExternalParameterlessConstructor(parameterizedBase) == null
}

test "constructor declaration owner emits the exact external base call and declines inaccessible implicit chains before declaration" {
    derived := ConstructorDeclarationControlsExternalDerived(
        "ConstructorDeclarationAttributeDerived",
        typeof(Attribute)
    )
    builder := derived.Builder.DefineConstructor(
        MethodAttributes.Public,
        CallingConventions.Standard,
        Type.EmptyTypes
    )
    il := builder.GetILGenerator()
    ColumnarConstructorDeclarationPlanner.EmitCtorBaseChain(
        il,
        derived,
        ExecutorRequiredConstructor(typeof(object), Type.EmptyTypes)
    )
    il.Emit(OpCodes.Ret)
    baked := IdentityBake(derived.Builder)
    constructors := baked.GetConstructors()
    assert constructors.Length == 1
    emitted := constructors[0]
    emittedIl := ConstructorDeclarationControlsReadIl(emitted)
    assert emittedIl.Length == 7
    assert emittedIl[0] == 2
    assert emittedIl[1] == 40
    assert emittedIl[6] == 42
    baseCall := ConstructorDeclarationControlsResolveMethodToken(
        emitted,
        ConstructorDeclarationControlsReadInt32(emittedIl, 2)
    )
    assert baseCall.get_DeclaringType() == typeof(Attribute)
    assert baseCall.GetParameters().Length == 0
    assert ((int)baseCall.get_Attributes() & 7) == 4

    privateBase := ConstructorDeclarationControlsExternalBase(
        "ConstructorDeclarationDeclinePrivateExternalBase",
        (MethodAttributes)1,
        Type.EmptyTypes
    )
    explicitDefinition := ConstructorDeclarationControlsExternalDerived(
        "ConstructorDeclarationDeclineExplicitDerived",
        privateBase
    )
    unreadBody := ConstructorDeclarationControlsEmptyBody(
        "UnreadExternalBaseParameter",
        ConstructorDeclarationControlsOneText("neverRead"),
        ConstructorDeclarationControlsEmptyTexts()
    )
    explicitConstructor := ConstructorDeclarationControlsConstructor(
        unreadBody,
        0,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        false
    )
    explicitConstructors := new List<ColumnarConstructorInput>()
    explicitConstructors.Add(explicitConstructor)
    explicitInputs := new List<ColumnarStructInput>()
    explicitInputs.Add(
        ConstructorDeclarationControlsInput(
            explicitDefinition.DeclaredTypeName,
            explicitConstructors
        )
    )
    explicitDefinitions := new ColumnarStructDef[](1)
    explicitDefinitions[0] = explicitDefinition
    explicitProgram := ConstructorDeclarationControlsProgram("", explicitInputs)
    explicitResult := ColumnarConstructorDeclarationPlanner.Declare(
        explicitProgram,
        explicitInputs,
        explicitDefinitions,
        ConstructorDeclarationControlsResolutions(
            explicitProgram,
            explicitDefinitions
        ),
        new int[](1)
    )
    assert !explicitResult.Succeeded
    assert explicitResult.DeclineSite == "emit.ctor.implicit-base-chain"
    assert explicitResult.DeclineMessage == "constructor requires an accessible base parameterless constructor"
    assert explicitResult.DeclineMember == explicitDefinition.Builder.get_Name() + ".constructor"
    assert explicitResult.ConstructorJobs.Count == 0
    assert explicitDefinition.Constructors.Count == 0

    parameterizedBase := ConstructorDeclarationControlsExternalBase(
        "ConstructorDeclarationDeclineParameterizedExternalBase",
        (MethodAttributes)6,
        ConstructorDeclarationControlsOneType(typeof(int))
    )
    defaultDefinition := ConstructorDeclarationControlsExternalDerived(
        "ConstructorDeclarationDeclineDefaultDerived",
        parameterizedBase
    )
    defaultInputs := new List<ColumnarStructInput>()
    defaultInputs.Add(
        ConstructorDeclarationControlsInput(
            defaultDefinition.DeclaredTypeName,
            new List<ColumnarConstructorInput>()
        )
    )
    defaultDefinitions := new ColumnarStructDef[](1)
    defaultDefinitions[0] = defaultDefinition
    defaultProgram := ConstructorDeclarationControlsProgram("", defaultInputs)
    defaultResult := ColumnarConstructorDeclarationPlanner.Declare(
        defaultProgram,
        defaultInputs,
        defaultDefinitions,
        ConstructorDeclarationControlsResolutions(defaultProgram, defaultDefinitions),
        new int[](1)
    )
    assert !defaultResult.Succeeded
    assert defaultResult.DeclineSite == "emit.ctor.default-base-chain"
    assert defaultResult.DeclineMessage == "default constructor requires an accessible external base parameterless constructor"
    assert defaultResult.DeclineMember == defaultDefinition.Builder.get_Name()
    assert defaultResult.DefaultConstructorJobs.Count == 0
    assert defaultDefinition.DefaultCtor == null
}

test "constructor declaration owner excludes this and rebinds a closed generic base before chaining" {
    selfOwner := ConstructorDeclarationControlsDefinition("ConstructorDeclarationThisSelf", 0)
    self := ConstructorDeclarationControlsDefineUserConstructor(
        selfOwner,
        ConstructorDeclarationControlsOneType(typeof(int))
    )
    other := ConstructorDeclarationControlsDefineUserConstructor(
        selfOwner,
        ConstructorDeclarationControlsOneType(typeof(int))
    )
    thisChain := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody("ThisChain", new string[](0), new string[](0)),
        1,
        ConstructorDeclarationControlsOneKind(1),
        ConstructorDeclarationControlsOneText("7"),
        false
    )
    selfDefinitions := new ColumnarStructDef[](1)
    selfDefinitions[0] = selfOwner
    selfResolution := ConstructorDeclarationControlsChainResolution(selfDefinitions)
    selfChainHost := TypeOfCreateBuilder(
        "ConstructorDeclarationThisSelfChainHost",
        "ColumnarConstructorDeclarationControls.ConstructorDeclarationThisSelfChainHost",
        0
    )
    selfIl := ReferenceCoercionBuilderIl(
        selfChainHost,
        "ConstructorDeclarationThisSelfChain"
    )
    assert ColumnarConstructorDeclarationPlanner.EmitChainedConstructorCall(
        thisChain,
        self,
        selfOwner,
        new Dictionary<string, int>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        selfResolution.Structs,
        ConstructorDeclarationControlsDefinitions(selfDefinitions),
        selfIl
    )
    assert ReferenceCoercionIlOffset(selfIl) > 0
    assert !Object.ReferenceEquals(self, other)

    baseDefinition := ConstructorDeclarationControlsDefinition(
        "ConstructorDeclarationClosedBase",
        1
    )
    genericArguments := baseDefinition.Builder.GetGenericArguments()
    assert genericArguments.Length == 1
    openConstructor := ConstructorDeclarationControlsDefineUserConstructor(
        baseDefinition,
        ConstructorDeclarationControlsOneType(genericArguments[0])
    )
    exactArguments := ConstructorDeclarationControlsOneType(typeof(int))
    baseBuilderType: Type = baseDefinition.Builder
    closedBase := baseBuilderType.MakeGenericType(exactArguments)
    derived := ConstructorDeclarationControlsDefinition("ConstructorDeclarationClosedDerived", 0)
    derived.BaseDef = baseDefinition
    derived.ExactBaseType = closedBase
    rebound := ColumnarConstructorDeclarationPlanner.ResolveExactBaseConstructor(
        derived,
        openConstructor
    )
    assert !Object.ReferenceEquals(rebound, openConstructor)
    assert Object.ReferenceEquals(rebound.get_DeclaringType(), closedBase)

    baseChain := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody("BaseChain", new string[](0), new string[](0)),
        2,
        ConstructorDeclarationControlsOneKind(1),
        ConstructorDeclarationControlsOneText("11"),
        false
    )
    chainDefinitions := new ColumnarStructDef[](2)
    chainDefinitions[0] = derived
    chainDefinitions[1] = baseDefinition
    chainResolution := ConstructorDeclarationControlsChainResolution(chainDefinitions)
    chainHost := TypeOfCreateBuilder(
        "ConstructorDeclarationClosedBaseChainHost",
        "ColumnarConstructorDeclarationControls.ConstructorDeclarationClosedBaseChainHost",
        0
    )
    chainIl := ReferenceCoercionBuilderIl(
        chainHost,
        "ConstructorDeclarationClosedBaseChain"
    )
    assert ColumnarConstructorDeclarationPlanner.EmitChainedConstructorCall(
        baseChain,
        self,
        derived,
        new Dictionary<string, int>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        chainResolution.Structs,
        ConstructorDeclarationControlsDefinitions(chainDefinitions),
        chainIl
    )
    assert ReferenceCoercionIlOffset(chainIl) > 0
}

test "constructor declaration owner rejects ambiguous chains before IL and preserves earlier argument IL on later decline" {
    ambiguousBase := ConstructorDeclarationControlsDefinition("ConstructorDeclarationAmbiguousBase", 0)
    ConstructorDeclarationControlsDefineUserConstructor(
        ambiguousBase,
        ConstructorDeclarationControlsOneType(typeof(int))
    )
    ConstructorDeclarationControlsDefineUserConstructor(
        ambiguousBase,
        ConstructorDeclarationControlsOneType(typeof(int))
    )
    ambiguousDerived := ConstructorDeclarationControlsDefinition("ConstructorDeclarationAmbiguousDerived", 0)
    ambiguousDerived.BaseDef = ambiguousBase
    ambiguousDefinitions := new ColumnarStructDef[](2)
    ambiguousDefinitions[0] = ambiguousDerived
    ambiguousDefinitions[1] = ambiguousBase
    ambiguousResolution := ConstructorDeclarationControlsChainResolution(ambiguousDefinitions)
    ambiguousCtor := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody("Ambiguous", new string[](0), new string[](0)),
        2,
        ConstructorDeclarationControlsOneKind(1),
        ConstructorDeclarationControlsOneText("3"),
        false
    )
    ambiguousIl := ReferenceCoercionIl("ConstructorDeclarationAmbiguousChain")
    assert !ColumnarConstructorDeclarationPlanner.EmitChainedConstructorCall(
        ambiguousCtor,
        ConstructorDeclarationControlsDefineUserConstructor(ambiguousDerived, Type.EmptyTypes),
        ambiguousDerived,
        new Dictionary<string, int>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        ambiguousResolution.Structs,
        ConstructorDeclarationControlsDefinitions(ambiguousDefinitions),
        ambiguousIl
    )
    assert ReferenceCoercionIlOffset(ambiguousIl) == 0

    partialBase := ConstructorDeclarationControlsDefinition("ConstructorDeclarationPartialChainBase", 0)
    ConstructorDeclarationControlsDefineUserConstructor(
        partialBase,
        ConstructorDeclarationControlsTwoTypes(typeof(int), typeof(string))
    )
    partialDerived := ConstructorDeclarationControlsDefinition("ConstructorDeclarationPartialChainDerived", 0)
    partialDerived.BaseDef = partialBase
    partialDefinitions := new ColumnarStructDef[](2)
    partialDefinitions[0] = partialDerived
    partialDefinitions[1] = partialBase
    partialResolution := ConstructorDeclarationControlsChainResolution(partialDefinitions)
    partialCtor := ConstructorDeclarationControlsConstructor(
        ConstructorDeclarationControlsEmptyBody("Partial", new string[](0), new string[](0)),
        2,
        ConstructorDeclarationControlsTwoKinds(1, 4),
        ConstructorDeclarationControlsTwoTexts("128", "$\"not-an-ordinary-string\""),
        false
    )
    partialIl := ReferenceCoercionIl("ConstructorDeclarationPartialChain")
    assert !ColumnarConstructorDeclarationPlanner.EmitChainedConstructorCall(
        partialCtor,
        ConstructorDeclarationControlsDefineUserConstructor(partialDerived, Type.EmptyTypes),
        partialDerived,
        new Dictionary<string, int>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        partialResolution.Structs,
        ConstructorDeclarationControlsDefinitions(partialDefinitions),
        partialIl
    )
    // `ldarg.0` (one byte) and the 128 literal (`ldc.i4`, five bytes) remain after
    // the later interpolated-string rejection.  No call is emitted on that failed second argument.
    assert ReferenceCoercionIlOffset(partialIl) == 6
}

func ConstructorDeclarationControlsArgumentTypes(count: int): Type[] {
    types := new Type[](count)
    index := 0
    while index < types.Length {
        types[index] = typeof(int)
        index = index + 1
    }
    return types
}

func ConstructorDeclarationControlsReadIl(method: MethodBase): int[] {
    noParameters := new Type[](0)
    getBody := ExecutorRequiredMethod(typeof(MethodBase), "GetMethodBody", noParameters)
    body := TypeOfRequiredInvocation(getBody, method, new object[](0))
    if body == null {
        throw new InvalidOperationException("The argument-opcode fixture emitted no method body.")
    }
    getBytes := ExecutorRequiredMethod(body.GetType(), "GetILAsByteArray", noParameters)
    bytes := TypeOfRequiredInvocation(getBytes, body, new object[](0))
    if bytes == null {
        throw new InvalidOperationException("The argument-opcode fixture exposed no IL bytes.")
    }
    byteArrayType := bytes.GetType()
    length := Convert.ToInt32(
        TypeOfRequiredInvocation(
            ExecutorRequiredMethod(byteArrayType, "get_Length", noParameters),
            bytes,
            new object[](0)
        )
    )
    getValueTypes := ConstructorDeclarationControlsOneType(typeof(int))
    getValue := ExecutorRequiredMethod(byteArrayType, "GetValue", getValueTypes)
    values := new int[](length)
    arguments := new object[](1)
    index := 0
    while index < values.Length {
        IteratorSetObject(arguments, 0, index)
        values[index] = Convert.ToInt32(TypeOfRequiredInvocation(getValue, bytes, arguments))
        index = index + 1
    }
    return values
}

func ConstructorDeclarationControlsRequiredMethod(
    owner: Type,
    name: string
): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("The argument-opcode fixture did not bake " + name + ".")
    }
    return method
}

test "constructor declaration argument owner selects byte forms through 255 and long forms at 256" {
    owner := TypeOfCreateBuilder(
        "ConstructorDeclarationArgumentBoundary",
        "ColumnarConstructorDeclarationControls.ArgumentBoundary",
        0
    )
    parameters := ConstructorDeclarationControlsArgumentTypes(257)
    load255 := owner.DefineMethod("Load255", (MethodAttributes)22, typeof(int), parameters)
    load255Il := TypeOfMethodBuilderIL(load255)
    ColumnarArgumentInstructionEmitter.EmitLoad(load255Il, 255)
    load255Il.Emit(OpCodes.Ret)
    load256 := owner.DefineMethod("Load256", (MethodAttributes)22, typeof(int), parameters)
    load256Il := TypeOfMethodBuilderIL(load256)
    ColumnarArgumentInstructionEmitter.EmitLoad(load256Il, 256)
    load256Il.Emit(OpCodes.Ret)

    store255 := owner.DefineMethod("Store255", (MethodAttributes)22, ExecutorVoidType(), parameters)
    store255Il := TypeOfMethodBuilderIL(store255)
    store255Il.Emit(OpCodes.Ldc_I4_0)
    ColumnarArgumentInstructionEmitter.EmitStore(store255Il, 255)
    store255Il.Emit(OpCodes.Ret)
    store256 := owner.DefineMethod("Store256", (MethodAttributes)22, ExecutorVoidType(), parameters)
    store256Il := TypeOfMethodBuilderIL(store256)
    store256Il.Emit(OpCodes.Ldc_I4_0)
    ColumnarArgumentInstructionEmitter.EmitStore(store256Il, 256)
    store256Il.Emit(OpCodes.Ret)

    address255 := owner.DefineMethod("Address255", (MethodAttributes)22, ExecutorVoidType(), parameters)
    address255Il := TypeOfMethodBuilderIL(address255)
    ColumnarArgumentInstructionEmitter.EmitLoadAddress(address255Il, 255)
    address255Il.Emit(OpCodes.Pop)
    address255Il.Emit(OpCodes.Ret)
    address256 := owner.DefineMethod("Address256", (MethodAttributes)22, ExecutorVoidType(), parameters)
    address256Il := TypeOfMethodBuilderIL(address256)
    ColumnarArgumentInstructionEmitter.EmitLoadAddress(address256Il, 256)
    address256Il.Emit(OpCodes.Pop)
    address256Il.Emit(OpCodes.Ret)

    baked := IdentityBake(owner)
    load255Bytes := ConstructorDeclarationControlsReadIl(
        ConstructorDeclarationControlsRequiredMethod(baked, "Load255")
    )
    assert load255Bytes.Length == 3
    assert load255Bytes[0] == 14
    assert load255Bytes[1] == 255
    assert load255Bytes[2] == 42
    load256Bytes := ConstructorDeclarationControlsReadIl(
        ConstructorDeclarationControlsRequiredMethod(baked, "Load256")
    )
    assert load256Bytes.Length == 5
    assert load256Bytes[0] == 254
    assert load256Bytes[1] == 9
    assert load256Bytes[2] == 0
    assert load256Bytes[3] == 1
    assert load256Bytes[4] == 42

    store255Bytes := ConstructorDeclarationControlsReadIl(
        ConstructorDeclarationControlsRequiredMethod(baked, "Store255")
    )
    assert store255Bytes.Length == 4
    assert store255Bytes[0] == 22
    assert store255Bytes[1] == 16
    assert store255Bytes[2] == 255
    assert store255Bytes[3] == 42
    store256Bytes := ConstructorDeclarationControlsReadIl(
        ConstructorDeclarationControlsRequiredMethod(baked, "Store256")
    )
    assert store256Bytes.Length == 6
    assert store256Bytes[0] == 22
    assert store256Bytes[1] == 254
    assert store256Bytes[2] == 11
    assert store256Bytes[3] == 0
    assert store256Bytes[4] == 1
    assert store256Bytes[5] == 42

    address255Bytes := ConstructorDeclarationControlsReadIl(
        ConstructorDeclarationControlsRequiredMethod(baked, "Address255")
    )
    assert address255Bytes.Length == 4
    assert address255Bytes[0] == 15
    assert address255Bytes[1] == 255
    assert address255Bytes[2] == 38
    assert address255Bytes[3] == 42
    address256Bytes := ConstructorDeclarationControlsReadIl(
        ConstructorDeclarationControlsRequiredMethod(baked, "Address256")
    )
    assert address256Bytes.Length == 6
    assert address256Bytes[0] == 254
    assert address256Bytes[1] == 10
    assert address256Bytes[2] == 0
    assert address256Bytes[3] == 1
    assert address256Bytes[4] == 38
    assert address256Bytes[5] == 42
}

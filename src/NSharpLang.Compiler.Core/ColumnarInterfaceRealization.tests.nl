namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Threading.Tasks

// These controls own the newly moved orchestration decisions. Existing source, closed-source, and
// external interface resolver suites retain their leaf matching contracts; this file verifies that
// the realization owner selects those paths in the production order and preserves their mutations.
func InterfaceRealizationNoTypes(): Type[] {
    return new Type[](0)
}

func InterfaceRealizationOneType(value: Type): Type[] {
    values := new Type[](1)
    values[0] = value
    return values
}

func InterfaceRealizationOneString(value: string): string[] {
    values := new string[](1)
    values[0] = value
    return values
}

func InterfaceRealizationFunctionInput(
    name: string,
    returnCanonical: string,
    parameterCanonicals: string[],
    isStatic: bool = false,
    isAsync: bool = false,
    typeParameters: string[]? = null
): ColumnarFunctionInput {
    parameterNames := new string[](parameterCanonicals.Length)
    index := 0
    while index < parameterNames.Length {
        parameterNames[index] = "p" + index.ToString()
        index = index + 1
    }

    result := new ColumnarFunctionInput(
        name,
        returnCanonical,
        parameterNames,
        parameterCanonicals,
        DeclarationPlanEmptyBody(),
        0,
        isStatic
    )
    result.IsAsync = isAsync
    if typeParameters != null {
        result.TypeParamNames = typeParameters
    }
    return result
}

func InterfaceRealizationStructInput(
    name: string,
    methods: List<ColumnarFunctionInput>
): ColumnarStructInput {
    return new ColumnarStructInput(
        name,
        new string[](0),
        new string[](0),
        methods,
        new List<ColumnarConstructorInput>(),
        new List<ColumnarPropertyInput>(),
        true
    )
}

func InterfaceRealizationSingleInput(
    input: ColumnarStructInput
): List<ColumnarStructInput> {
    inputs := new List<ColumnarStructInput>()
    inputs.Add(input)
    return inputs
}

func InterfaceRealizationSingleDefinition(
    definition: ColumnarStructDef
): ColumnarStructDef[] {
    definitions := new ColumnarStructDef[](1)
    definitions[0] = definition
    return definitions
}

func InterfaceRealizationSingleResolution(
    input: ColumnarStructInput,
    definition: ColumnarStructDef
): ColumnarSemanticTypeResolution {
    sourceInputs := InterfaceRealizationSingleInput(input)
    sourceDefinitions := SemanticEmptyStructs()
    sourceDefinitions[definition.DeclaredTypeName] = definition
    program := ColumnarProgramInput.CreateSingleSource(
        "",
        new List<ColumnarFunctionInput>(),
        new List<ColumnarEnumInput>(),
        sourceInputs,
        new List<ColumnarUnionInput>(),
        new List<ColumnarInterfaceInput>(),
        null
    )
    return SemanticTypeResolution(
        program,
        0,
        SemanticEmptyEnums(),
        sourceDefinitions,
        SemanticEmptyUnions(),
        null,
        definition.DeclaredTypeName
    )
}

func InterfaceRealizationAbstractMethod(
    owner: ColumnarStructDef,
    name: string,
    returnType: Type,
    parameterTypes: Type[]
): ColumnarInstanceMethodDef {
    return SourceCallDefineInstance(
        owner,
        name,
        parameterTypes,
        new int[](0),
        returnType,
        (MethodAttributes)1478
    )
}

func InterfaceRealizationPublicMethod(
    owner: ColumnarStructDef,
    name: string,
    returnType: Type,
    parameterTypes: Type[]
): ColumnarInstanceMethodDef {
    return SourceCallDefineInstance(
        owner,
        name,
        parameterTypes,
        new int[](0),
        returnType,
        (MethodAttributes)486
    )
}

func InterfaceRealizationDefaultVoidMethod(
    owner: ColumnarStructDef,
    name: string
): ColumnarInstanceMethodDef {
    definition := SourceCallDefineInstance(
        owner,
        name,
        InterfaceRealizationNoTypes(),
        new int[](0),
        ExecutorVoidType(),
        (MethodAttributes)454
    )
    SourceInterfaceMethodEmitVoid(definition.Builder)
    owner.DefaultInterfaceMethodNames.Add(name)
    return definition
}

func InterfaceRealizationEmitOne(method: MethodBuilder) {
    il := TypeOfMethodBuilderIL(method)
    il.Emit(OpCodes.Ldc_I4, 1)
    il.Emit(OpCodes.Ret)
}

func InterfaceRealizationIsCreated(builder: TypeBuilder): bool {
    query := ExecutorRequiredMethod(
        typeof(TypeBuilder),
        "IsCreated",
        InterfaceRealizationNoTypes()
    )
    value := TypeOfRequiredInvocation(query, builder, new object[](0))
    return Convert.ToBoolean(value)
}

func InterfaceRealizationContainsInterface(
    owner: Type,
    expected: Type
): bool {
    for candidate in owner.GetInterfaces() {
        if candidate == expected {
            return true
        }
    }
    return false
}

func InterfaceRealizationInterfaceInputs(
    first: string,
    second: string
): List<ColumnarInterfaceInput> {
    inputs := new List<ColumnarInterfaceInput>()
    inputs.Add(DeclarationPlanInterfaceInput(first))
    inputs.Add(DeclarationPlanInterfaceInput(second))
    return inputs
}

func InterfaceRealizationDefinitions(
    first: ColumnarStructDef,
    second: ColumnarStructDef
): ColumnarStructDef[] {
    definitions := new ColumnarStructDef[](2)
    definitions[0] = first
    definitions[1] = second
    return definitions
}

test "interface realization computes memoized diamond depths and rejects a cycle with its allocated out row" {
    root := SourceCallInterfaceDefinition("InterfaceRealizationDepthRoot")
    left := SourceCallInterfaceDefinition("InterfaceRealizationDepthLeft")
    right := SourceCallInterfaceDefinition("InterfaceRealizationDepthRight")
    leaf := SourceCallInterfaceDefinition("InterfaceRealizationDepthLeaf")
    left.InterfaceBases.Add(root)
    right.InterfaceBases.Add(root)
    leaf.InterfaceBases.Add(left)
    leaf.InterfaceBases.Add(right)

    definitions := new List<ColumnarStructDef>()
    definitions.Add(leaf)
    definitions.Add(right)
    definitions.Add(root)
    definitions.Add(left)

    depths: int[] = null
    assert ColumnarInterfaceRealization.TryComputeInterfaceDepths(definitions, out depths)
    assert depths.Length == 4
    assert depths[0] == 2
    assert depths[1] == 1
    assert depths[2] == 0
    assert depths[3] == 1

    memo := new Dictionary<ColumnarStructDef, int>()
    visiting := new HashSet<ColumnarStructDef>()
    assert ColumnarInterfaceRealization.InterfaceDepthOrMinusOne(leaf, memo, visiting) == 2
    assert memo.Count == 4
    assert memo[root] == 0
    assert memo[left] == 1
    assert memo[right] == 1
    assert memo[leaf] == 2

    first := SourceCallInterfaceDefinition("InterfaceRealizationCycleFirst")
    second := SourceCallInterfaceDefinition("InterfaceRealizationCycleSecond")
    first.InterfaceBases.Add(second)
    second.InterfaceBases.Add(first)
    cycle := new List<ColumnarStructDef>()
    cycle.Add(first)
    cycle.Add(second)
    cycleDepths: int[] = null
    assert !ColumnarInterfaceRealization.TryComputeInterfaceDepths(cycle, out cycleDepths)
    assert cycleDepths.Length == 2
}

test "interface realization finalizes an interface base before its derived metadata" {
    baseDefinition := SourceCallInterfaceDefinition("InterfaceRealizationFinalizeBase")
    derivedDefinition := SourceCallInterfaceDefinition("InterfaceRealizationFinalizeDerived")
    derivedDefinition.InterfaceBases.Add(baseDefinition)
    derivedDefinition.Builder.AddInterfaceImplementation(baseDefinition.Builder)

    // Deliberately reverse declaration order: the supplied depth rows, rather than input order,
    // must create the base before the derived TypeBuilder.
    definitions := new List<ColumnarStructDef>()
    definitions.Add(derivedDefinition)
    definitions.Add(baseDefinition)
    depths := new int[](2)
    depths[0] = 1
    depths[1] = 0

    ColumnarInterfaceRealization.FinalizeInterfaces(
        InterfaceRealizationInterfaceInputs(
            "InterfaceRealizationFinalizeDerived",
            "InterfaceRealizationFinalizeBase"
        ),
        definitions,
        depths
    )

    assert InterfaceRealizationIsCreated(baseDefinition.Builder)
    assert InterfaceRealizationIsCreated(derivedDefinition.Builder)
    derivedRuntime := IdentityBake(derivedDefinition.Builder)
    baseRuntime := IdentityBake(baseDefinition.Builder)
    assert InterfaceRealizationContainsInterface(derivedRuntime, baseRuntime)
}

test "duck registration preserves inherited metadata once and skips default-only requirements" {
    root := SourceCallInterfaceDefinition("InterfaceRealizationDuckRoot")
    derived := SourceCallInterfaceDefinition("InterfaceRealizationDuckDerived")
    InterfaceRealizationAbstractMethod(
        root,
        "Required",
        typeof(int),
        InterfaceRealizationNoTypes()
    )
    InterfaceRealizationDefaultVoidMethod(derived, "OptionalDefault")
    derived.InterfaceBases.Add(root)
    derived.Builder.AddInterfaceImplementation(root.Builder)

    sourceMethods := new List<ColumnarFunctionInput>()
    sourceRequired := InterfaceRealizationFunctionInput(
        "Required",
        "int",
        new string[](0),
        false,
        false,
        new string[](0)
    )
    sourceMethods.Add(sourceRequired)
    sourceInput := InterfaceRealizationStructInput(
        "InterfaceRealizationDuckImplementation",
        sourceMethods
    )
    sourceDefinition := SourceCallDefinition(
        "InterfaceRealizationDuckImplementation",
        true
    )
    concrete := InterfaceRealizationPublicMethod(
        sourceDefinition,
        "Required",
        typeof(int),
        InterfaceRealizationNoTypes()
    )
    InterfaceRealizationEmitOne(concrete.Builder)

    resolution := InterfaceRealizationSingleResolution(
        sourceInput,
        sourceDefinition
    )
    resolutions := new ColumnarSemanticTypeResolution[](1)
    resolutions[0] = resolution
    interfaces := new List<ColumnarStructDef>()
    interfaces.Add(root)
    interfaces.Add(derived)

    ColumnarInterfaceRealization.RegisterDuckInterfaces(
        InterfaceRealizationSingleInput(sourceInput),
        InterfaceRealizationSingleDefinition(sourceDefinition),
        resolutions,
        interfaces
    )
    assert sourceDefinition.ImplementedInterfaces.Count == 2
    assert Object.ReferenceEquals(sourceDefinition.ImplementedInterfaces[0], root)
    assert Object.ReferenceEquals(sourceDefinition.ImplementedInterfaces[1], derived)

    // Running the pass again reaches the existing-builder guard before adding either declaration
    // a second time. This is the live definition mutation, not a copied classification result.
    ColumnarInterfaceRealization.RegisterDuckInterfaces(
        InterfaceRealizationSingleInput(sourceInput),
        InterfaceRealizationSingleDefinition(sourceDefinition),
        resolutions,
        interfaces
    )
    assert sourceDefinition.ImplementedInterfaces.Count == 2

    depths := new int[](2)
    depths[0] = 0
    depths[1] = 1
    ColumnarInterfaceRealization.FinalizeInterfaces(
        InterfaceRealizationInterfaceInputs(
            "InterfaceRealizationDuckRoot",
            "InterfaceRealizationDuckDerived"
        ),
        interfaces,
        depths
    )
    assert InterfaceRealizationIsCreated(root.Builder)
    assert InterfaceRealizationIsCreated(derived.Builder)
    sourceRuntime := IdentityBake(sourceDefinition.Builder)
    rootRuntime := IdentityBake(root.Builder)
    derivedRuntime := IdentityBake(derived.Builder)
    assert InterfaceRealizationContainsInterface(sourceRuntime, rootRuntime)
    assert InterfaceRealizationContainsInterface(sourceRuntime, derivedRuntime)
}

test "duck matching continues past ordinary nonmatches but a reached unresolved candidate is terminal" {
    sourceDefinition := SourceCallDefinition(
        "InterfaceRealizationDuckCandidate",
        true
    )
    parameterTypes := InterfaceRealizationOneType(typeof(int))
    parameterCanonicals := InterfaceRealizationOneString("int")
    sourceMethods := new List<ColumnarFunctionInput>()
    staticCandidate := InterfaceRealizationFunctionInput(
        "Select",
        "int",
        parameterCanonicals,
        true,
        false,
        new string[](0)
    )
    sourceMethods.Add(staticCandidate)
    genericNames := InterfaceRealizationOneString("TMethod")
    genericCandidate := InterfaceRealizationFunctionInput(
        "Select",
        "int",
        parameterCanonicals,
        false,
        false,
        genericNames
    )
    sourceMethods.Add(genericCandidate)
    wrongReturnCandidate := InterfaceRealizationFunctionInput(
        "Select",
        "bool",
        parameterCanonicals,
        false,
        false,
        new string[](0)
    )
    sourceMethods.Add(wrongReturnCandidate)
    wrongParameterCandidate := InterfaceRealizationFunctionInput(
        "Select",
        "int",
        InterfaceRealizationOneString("string"),
        false,
        false,
        new string[](0)
    )
    sourceMethods.Add(wrongParameterCandidate)
    matchingCandidate := InterfaceRealizationFunctionInput(
        "Select",
        "int",
        parameterCanonicals,
        false,
        false,
        new string[](0)
    )
    sourceMethods.Add(matchingCandidate)
    sourceInput := InterfaceRealizationStructInput(
        "InterfaceRealizationDuckCandidate",
        sourceMethods
    )
    resolution := InterfaceRealizationSingleResolution(
        sourceInput,
        sourceDefinition
    )
    assert ColumnarInterfaceRealization.StructInputHasDuckMethod(
        sourceInput,
        sourceDefinition,
        "Select",
        typeof(int),
        parameterTypes,
        resolution.Enums,
        resolution.Structs,
        resolution.Unions
    )

    terminalMethods := new List<ColumnarFunctionInput>()
    unresolvedCandidate := InterfaceRealizationFunctionInput(
        "Select",
        "NotAResolvableReturnType",
        parameterCanonicals,
        false,
        false,
        new string[](0)
    )
    terminalMethods.Add(unresolvedCandidate)
    laterMatchingCandidate := InterfaceRealizationFunctionInput(
        "Select",
        "int",
        parameterCanonicals,
        false,
        false,
        new string[](0)
    )
    terminalMethods.Add(laterMatchingCandidate)
    terminalInput := InterfaceRealizationStructInput(
        "InterfaceRealizationDuckTerminal",
        terminalMethods
    )
    terminalDefinition := SourceCallDefinition(
        "InterfaceRealizationDuckTerminal",
        true
    )
    terminalResolution := InterfaceRealizationSingleResolution(
        terminalInput,
        terminalDefinition
    )
    assert !ColumnarInterfaceRealization.StructInputHasDuckMethod(
        terminalInput,
        terminalDefinition,
        "Select",
        typeof(int),
        parameterTypes,
        terminalResolution.Enums,
        terminalResolution.Structs,
        terminalResolution.Unions
    )
}

test "interface completeness orchestrates source defaults missing and mismatched requirements" {
    requiredInterface := SourceCallInterfaceDefinition("InterfaceRealizationCompletenessRequired")
    InterfaceRealizationAbstractMethod(
        requiredInterface,
        "Read",
        typeof(int),
        InterfaceRealizationOneType(typeof(string))
    )

    implementation := SourceCallDefinition(
        "InterfaceRealizationCompletenessImplementation",
        true
    )
    InterfaceRealizationPublicMethod(
        implementation,
        "Read",
        typeof(int),
        InterfaceRealizationOneType(typeof(string))
    )
    implementation.ImplementedInterfaces.Add(requiredInterface)
    sourceInput := InterfaceRealizationStructInput(
        "InterfaceRealizationCompletenessImplementation",
        new List<ColumnarFunctionInput>()
    )
    registry := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
    registry[requiredInterface.DeclaredTypeName] = requiredInterface
    assert ColumnarInterfaceRealization.InterfacesSatisfied(
        InterfaceRealizationSingleInput(sourceInput),
        InterfaceRealizationSingleDefinition(implementation),
        registry
    )

    implementation.Methods.Remove("Read")
    assert !ColumnarInterfaceRealization.InterfacesSatisfied(
        InterfaceRealizationSingleInput(sourceInput),
        InterfaceRealizationSingleDefinition(implementation),
        registry
    )

    InterfaceRealizationPublicMethod(
        implementation,
        "Read",
        typeof(string),
        InterfaceRealizationOneType(typeof(string))
    )
    assert !ColumnarInterfaceRealization.InterfacesSatisfied(
        InterfaceRealizationSingleInput(sourceInput),
        InterfaceRealizationSingleDefinition(implementation),
        registry
    )

    implementation.Methods.Remove("Read")
    requiredInterface.DefaultInterfaceMethodNames.Add("Read")
    assert ColumnarInterfaceRealization.InterfacesSatisfied(
        InterfaceRealizationSingleInput(sourceInput),
        InterfaceRealizationSingleDefinition(implementation),
        registry
    )
}

test "interface completeness selects closed-source and external checks after its source loop" {
    closed := ClosedSourceGenericInterface("InterfaceRealizationClosed")
    parameter := closed.Builder.GetGenericArguments()[0]
    InterfaceRealizationAbstractMethod(
        closed,
        "Map",
        parameter,
        InterfaceRealizationOneType(parameter)
    )
    closedType := ClosedSourceClose(closed, typeof(int))

    closedImplementation := SourceCallDefinition(
        "InterfaceRealizationClosedImplementation",
        true
    )
    InterfaceRealizationPublicMethod(
        closedImplementation,
        "Map",
        typeof(int),
        InterfaceRealizationOneType(typeof(int))
    )
    closedImplementation.ImplementedInterfaces.Add(closed)
    closedImplementation.ImplementedInterfaceTypes.Add(closedType)

    externalImplementation := SourceCallDefinition(
        "InterfaceRealizationExternalImplementation",
        true
    )
    InterfaceRealizationPublicMethod(
        externalImplementation,
        "Dispose",
        ExecutorVoidType(),
        InterfaceRealizationNoTypes()
    )
    externalImplementation.ExternalInterfaces.Add(typeof(IDisposable))

    closedInput := InterfaceRealizationStructInput(
        "InterfaceRealizationClosedImplementation",
        new List<ColumnarFunctionInput>()
    )
    externalInput := InterfaceRealizationStructInput(
        "InterfaceRealizationExternalImplementation",
        new List<ColumnarFunctionInput>()
    )
    inputs := new List<ColumnarStructInput>()
    inputs.Add(closedInput)
    inputs.Add(externalInput)
    definitions := InterfaceRealizationDefinitions(
        closedImplementation,
        externalImplementation
    )
    registry := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
    registry[closed.DeclaredTypeName] = closed

    assert ColumnarInterfaceRealization.InterfacesSatisfied(
        inputs,
        definitions,
        registry
    )

    externalImplementation.Methods.Remove("Dispose")
    assert !ColumnarInterfaceRealization.InterfacesSatisfied(
        inputs,
        definitions,
        registry
    )
}

test "interface realization keeps async families out states and exact parameter identity rules" {
    sourceInput := InterfaceRealizationStructInput(
        "InterfaceRealizationAsyncOwner",
        new List<ColumnarFunctionInput>()
    )
    sourceDefinition := SourceCallDefinition(
        "InterfaceRealizationAsyncOwner",
        true
    )
    resolution := InterfaceRealizationSingleResolution(
        sourceInput,
        sourceDefinition
    )

    inner: Type = null
    wrapped: Type = null
    assert ColumnarInterfaceRealization.TryComputeAsyncReturnShape(
        "worker",
        "Task",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out inner,
        out wrapped
    )
    assert inner == ExecutorVoidType()
    assert wrapped == typeof(Task)

    assert ColumnarInterfaceRealization.TryComputeAsyncReturnShape(
        "worker",
        "ValueTask",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out inner,
        out wrapped
    )
    assert inner == ExecutorVoidType()
    assert wrapped == typeof(ValueTask)

    assert ColumnarInterfaceRealization.TryComputeAsyncReturnShape(
        "worker",
        "Task<int>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out inner,
        out wrapped
    )
    assert inner == typeof(int)
    assert wrapped == typeof(Task<int>)

    assert ColumnarInterfaceRealization.TryComputeAsyncReturnShape(
        "worker",
        "ValueTask<int>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out inner,
        out wrapped
    )
    assert inner == typeof(int)
    assert wrapped == typeof(ValueTask<int>)

    assert ColumnarInterfaceRealization.TryComputeAsyncReturnShape(
        "MAIN",
        "int",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out inner,
        out wrapped
    )
    assert inner == typeof(int)
    assert wrapped == typeof(Task<int>)

    assert ColumnarInterfaceRealization.TryComputeAsyncReturnShape(
        "worker",
        "int",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out inner,
        out wrapped
    )
    assert inner == typeof(int)
    assert wrapped == typeof(ValueTask<int>)

    assert ColumnarInterfaceRealization.TryComputeAsyncReturnShape(
        "MAIN",
        "void",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out inner,
        out wrapped
    )
    assert inner == ExecutorVoidType()
    assert wrapped == typeof(Task)

    assert ColumnarInterfaceRealization.TryComputeAsyncReturnShape(
        "worker",
        "void",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out inner,
        out wrapped
    )
    assert inner == ExecutorVoidType()
    assert wrapped == typeof(ValueTask)

    assert !ColumnarInterfaceRealization.TryComputeAsyncReturnShape(
        "worker",
        "Task<NotAResolvableInner>",
        resolution.Enums,
        resolution.Structs,
        resolution.Unions,
        out inner,
        out wrapped
    )
    // The delegated resolver clears its Type out slot on a missing inner canonical; the owner
    // preserves that overwrite instead of retaining its initial void sentinel.
    assert inner == null
    assert wrapped == null

    intByRef := typeof(int).MakeByRefType()
    assert ColumnarInterfaceRealization.IsSupportedParameterType(typeof(int))
    assert ColumnarInterfaceRealization.IsSupportedParameterType(intByRef)

    generic := SourceCallGenericDefinition(
        "InterfaceRealizationParamIdentity"
    )
    open: Type = generic.Builder
    first := open.MakeGenericType(InterfaceRealizationOneType(typeof(int)))
    second := open.MakeGenericType(InterfaceRealizationOneType(typeof(int)))
    assert first != second
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(first, second)
    assert !ColumnarInterfaceRealization.ParamTypesMatch(
        InterfaceRealizationOneType(first),
        InterfaceRealizationOneType(second)
    )
    assert ColumnarInterfaceRealization.ParamTypesMatch(
        InterfaceRealizationOneType(first),
        InterfaceRealizationOneType(first)
    )
    assert !ColumnarInterfaceRealization.ParamTypesMatch(
        InterfaceRealizationOneType(typeof(int)),
        InterfaceRealizationNoTypes()
    )
}

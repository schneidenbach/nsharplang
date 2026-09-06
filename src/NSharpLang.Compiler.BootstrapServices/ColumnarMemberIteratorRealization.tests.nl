namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// The member owner must use IEnumerable<T> rather than IReadOnlyList<T>'s Count/indexer route.
// This state is carried by a real emitted IReadOnlyList<T>/IEnumerator<T> fixture so the tests see
// the exact generic Current and disposal operations that the production driver performs.
class MemberIteratorControlsRowsState {
    Rows: object[]
    MoveCount: int
    CurrentCount: int
    DisposeCount: int
    ThrowOnDispose: bool
    RepairRows: List<ColumnarStructInput>
    RepairFieldCanonicals: string[]

    constructor(rows: object[], throwOnDispose: bool) {
        Rows = rows
        MoveCount = 0
        CurrentCount = 0
        DisposeCount = 0
        ThrowOnDispose = throwOnDispose
        RepairRows = new List<ColumnarStructInput>()
        RepairFieldCanonicals = new string[](0)
    }
}

class MemberIteratorControlsRowsRuntime {
    static func MoveNext(state: MemberIteratorControlsRowsState): bool {
        if state.MoveCount >= state.Rows.Length {
            return false
        }
        state.MoveCount = state.MoveCount + 1
        return true
    }

    static func Current(state: MemberIteratorControlsRowsState): object {
        if state.MoveCount == 0 || state.MoveCount > state.Rows.Length {
            throw new InvalidOperationException("member iterator fixture Current was read outside MoveNext")
        }
        state.CurrentCount = state.CurrentCount + 1
        return state.Rows[state.MoveCount - 1]
    }

    static func Dispose(state: MemberIteratorControlsRowsState) {
        state.DisposeCount = state.DisposeCount + 1
        if state.RepairRows.Count > 0 {
            input := state.RepairRows[0]
            input.FieldTypeCanonicals = state.RepairFieldCanonicals
        }
        if state.ThrowOnDispose {
            throw new InvalidOperationException("member iterator fixture disposal failed")
        }
    }
}

class MemberIteratorControlsMutatingMethodsComparer: IEqualityComparer<string> {
    Candidate: ColumnarFunctionInput?
    Armed: bool

    constructor() {
        Candidate = null
        Armed = false
    }

    func Equals(left: string?, right: string?): bool {
        return left == right
    }

    func GetHashCode(value: string): int {
        if Armed && value == "Original" {
            candidateBox: object? = Candidate
            if candidateBox != null {
                candidate := (ColumnarFunctionInput)candidateBox
                candidate.Name = "Changed"
            }
        }
        return 0
    }
}

class MemberIteratorControlsTracingOverloadsComparer: IEqualityComparer<string> {
    Lookups: List<string>
    Armed: bool

    constructor() {
        Lookups = new List<string>()
        Armed = false
    }

    func Equals(left: string?, right: string?): bool {
        return left == right
    }

    func GetHashCode(value: string): int {
        if Armed {
            Lookups.Add(value)
        }
        return 0
    }
}

func MemberIteratorControlsEmitInvalidOperation(il: ILGenerator, message: string) {
    messageParameters := new Type[](1)
    messageParameters[0] = typeof(string)
    constructor := ExecutorRequiredConstructor(typeof(InvalidOperationException), messageParameters)
    il.Emit(OpCodes.Ldstr, message)
    il.Emit(OpCodes.Newobj, constructor)
    il.Emit(OpCodes.Throw)
}

func MemberIteratorControlsWrapReadOnlyList(
    typeName: string,
    elementType: Type,
    state: MemberIteratorControlsRowsState
): object {
    noParameters := new Type[](0)
    elementArguments := new Type[](1)
    elementArguments[0] = elementType
    genericEnumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    genericEnumeratorDefinition := typeof(IEnumerator<int>).GetGenericTypeDefinition()
    genericCollectionDefinition := typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
    genericListDefinition := typeof(IReadOnlyList<int>).GetGenericTypeDefinition()
    genericEnumerable := genericEnumerableDefinition.MakeGenericType(elementArguments)
    genericEnumerator := genericEnumeratorDefinition.MakeGenericType(elementArguments)
    genericCollection := genericCollectionDefinition.MakeGenericType(elementArguments)
    genericList := genericListDefinition.MakeGenericType(elementArguments)
    nongenericEnumerable := typeof(IEnumerable)
    nongenericEnumerator := typeof(IEnumerator)
    disposable := typeof(IDisposable)

    owner := TypeOfCreateBuilder(
        typeName,
        "ColumnarMemberIteratorRealization.Controls." + typeName,
        0
    )
    owner.AddInterfaceImplementation(genericList)
    owner.AddInterfaceImplementation(genericCollection)
    owner.AddInterfaceImplementation(genericEnumerable)
    owner.AddInterfaceImplementation(genericEnumerator)
    owner.AddInterfaceImplementation(nongenericEnumerable)
    owner.AddInterfaceImplementation(nongenericEnumerator)
    owner.AddInterfaceImplementation(disposable)
    stateField := SourceDiscoveryTimingDefineField(
        owner,
        "State",
        typeof(MemberIteratorControlsRowsState)
    )

    constructor := owner.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        noParameters
    )
    constructorIl := constructor.GetILGenerator()
    objectConstructor := ExecutorRequiredConstructor(typeof(object), noParameters)
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Call, objectConstructor)
    constructorIl.Emit(OpCodes.Ret)

    genericGetEnumeratorTarget := ExecutorRequiredMethod(
        genericEnumerable,
        "GetEnumerator",
        noParameters
    )
    genericGetEnumerator := owner.DefineMethod(
        "GenericGetEnumerator",
        (MethodAttributes)481,
        genericEnumerator,
        noParameters
    )
    SourceDiscoveryTimingReturnThis(genericGetEnumerator)
    owner.DefineMethodOverride(genericGetEnumerator, genericGetEnumeratorTarget)

    nongenericGetEnumeratorTarget := ExecutorRequiredMethod(
        nongenericEnumerable,
        "GetEnumerator",
        noParameters
    )
    nongenericGetEnumerator := owner.DefineMethod(
        "NongenericGetEnumerator",
        (MethodAttributes)481,
        nongenericEnumerator,
        noParameters
    )
    SourceDiscoveryTimingReturnThis(nongenericGetEnumerator)
    owner.DefineMethodOverride(nongenericGetEnumerator, nongenericGetEnumeratorTarget)

    runtimeParameterTypes := new Type[](1)
    runtimeParameterTypes[0] = typeof(MemberIteratorControlsRowsState)
    moveNextRuntime := ExecutorRequiredMethod(
        typeof(MemberIteratorControlsRowsRuntime),
        "MoveNext",
        runtimeParameterTypes
    )
    currentRuntime := ExecutorRequiredMethod(
        typeof(MemberIteratorControlsRowsRuntime),
        "Current",
        runtimeParameterTypes
    )
    disposeRuntime := ExecutorRequiredMethod(
        typeof(MemberIteratorControlsRowsRuntime),
        "Dispose",
        runtimeParameterTypes
    )

    genericCurrentTarget := SourceDiscoveryTimingRequiredGetter(genericEnumerator, "Current")
    genericCurrent := owner.DefineMethod(
        "GenericCurrent",
        (MethodAttributes)481,
        elementType,
        noParameters
    )
    genericCurrentIl := TypeOfMethodBuilderIL(genericCurrent)
    genericCurrentIl.Emit(OpCodes.Ldarg_0)
    genericCurrentIl.Emit(OpCodes.Ldfld, stateField)
    genericCurrentIl.Emit(OpCodes.Call, currentRuntime)
    genericCurrentIl.Emit(OpCodes.Castclass, elementType)
    genericCurrentIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(genericCurrent, genericCurrentTarget)

    nongenericCurrentTarget := SourceDiscoveryTimingRequiredGetter(nongenericEnumerator, "Current")
    nongenericCurrent := owner.DefineMethod(
        "NongenericCurrent",
        (MethodAttributes)481,
        typeof(object),
        noParameters
    )
    nongenericCurrentIl := TypeOfMethodBuilderIL(nongenericCurrent)
    MemberIteratorControlsEmitInvalidOperation(
        nongenericCurrentIl,
        "member iterator fixture nongeneric Current was read"
    )
    owner.DefineMethodOverride(nongenericCurrent, nongenericCurrentTarget)

    moveNextTarget := ExecutorRequiredMethod(nongenericEnumerator, "MoveNext", noParameters)
    moveNext := owner.DefineMethod(
        "MoveNext",
        (MethodAttributes)481,
        typeof(bool),
        noParameters
    )
    moveNextIl := TypeOfMethodBuilderIL(moveNext)
    moveNextIl.Emit(OpCodes.Ldarg_0)
    moveNextIl.Emit(OpCodes.Ldfld, stateField)
    moveNextIl.Emit(OpCodes.Call, moveNextRuntime)
    moveNextIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(moveNext, moveNextTarget)

    resetTarget := ExecutorRequiredMethod(nongenericEnumerator, "Reset", noParameters)
    reset := owner.DefineMethod(
        "Reset",
        (MethodAttributes)481,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        noParameters
    )
    resetIl := TypeOfMethodBuilderIL(reset)
    resetIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(reset, resetTarget)

    disposeTarget := ExecutorRequiredMethod(disposable, "Dispose", noParameters)
    dispose := owner.DefineMethod(
        "Dispose",
        (MethodAttributes)481,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        noParameters
    )
    disposeIl := TypeOfMethodBuilderIL(dispose)
    disposeIl.Emit(OpCodes.Ldarg_0)
    disposeIl.Emit(OpCodes.Ldfld, stateField)
    disposeIl.Emit(OpCodes.Call, disposeRuntime)
    disposeIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(dispose, disposeTarget)

    countTarget := SourceDiscoveryTimingRequiredGetter(genericCollection, "Count")
    count := owner.DefineMethod(
        "get_Count",
        (MethodAttributes)481,
        typeof(int),
        noParameters
    )
    countIl := TypeOfMethodBuilderIL(count)
    MemberIteratorControlsEmitInvalidOperation(countIl, "member iterator fixture Count was read")
    owner.DefineMethodOverride(count, countTarget)

    indexParameters := new Type[](1)
    indexParameters[0] = typeof(int)
    itemTarget := SourceDiscoveryTimingRequiredGetter(genericList, "Item")
    item := owner.DefineMethod(
        "get_Item",
        (MethodAttributes)481,
        elementType,
        indexParameters
    )
    itemIl := TypeOfMethodBuilderIL(item)
    MemberIteratorControlsEmitInvalidOperation(itemIl, "member iterator fixture indexer was read")
    owner.DefineMethodOverride(item, itemTarget)

    baked := IdentityBake(owner)
    instanceConstructor := ExecutorRequiredConstructor(baked, noParameters)
    instance := instanceConstructor.Invoke(new object[](0))
    if instance == null {
        throw new InvalidOperationException("The member iterator list fixture was not constructed")
    }
    bakedStateField := baked.GetField("State")
    if bakedStateField == null {
        throw new InvalidOperationException("The member iterator list fixture lost State")
    }
    bakedStateField.SetValue(instance, state)
    return instance
}

class MemberIteratorControlsTypedLists {
    static func SetStructs(
        program: ColumnarProgramInput,
        rows: IReadOnlyList<ColumnarStructInput>
    ) {
        program.Structs = rows
    }

    static func SetMethods(
        input: ColumnarStructInput,
        rows: IReadOnlyList<ColumnarFunctionInput>
    ) {
        input.Methods = rows
    }
}

func MemberIteratorControlsSetStructs(program: ColumnarProgramInput, rows: object) {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(ColumnarProgramInput)
    parameterTypes[1] = typeof(IReadOnlyList<ColumnarStructInput>)
    setter := ExecutorRequiredMethod(typeof(MemberIteratorControlsTypedLists), "SetStructs", parameterTypes)
    arguments := new object[](2)
    IteratorSetObject(arguments, 0, program)
    IteratorSetObject(arguments, 1, rows)
    ignored := setter.Invoke(null, arguments)
    _ = ignored
}

func MemberIteratorControlsSetMethods(input: ColumnarStructInput, rows: object) {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(ColumnarStructInput)
    parameterTypes[1] = typeof(IReadOnlyList<ColumnarFunctionInput>)
    setter := ExecutorRequiredMethod(typeof(MemberIteratorControlsTypedLists), "SetMethods", parameterTypes)
    arguments := new object[](2)
    IteratorSetObject(arguments, 0, input)
    IteratorSetObject(arguments, 1, rows)
    ignored := setter.Invoke(null, arguments)
    _ = ignored
}

func MemberIteratorControlsEmptyProgram(source: string): ColumnarProgramInput {
    return ColumnarProgramInput.CreateSingleSource(
        source,
        new List<ColumnarFunctionInput>(),
        new List<ColumnarEnumInput>(),
        new List<ColumnarStructInput>(),
        new List<ColumnarUnionInput>(),
        new List<ColumnarInterfaceInput>(),
        null
    )
}

// The driver receives an observed program whose Structs may be an emitted protocol wrapper.  Its
// semantic catalog is intentionally built from a separate ordinary source row and the same exact
// definition, so setup stamping cannot consume the observed enumerator while the successful path
// still resolves the enclosing receiver and any source-typed parameter.
func MemberIteratorControlsEnclosingResolution(
    source: string,
    inputName: string,
    fieldNames: string[],
    fieldCanonicals: string[],
    definition: ColumnarStructDef
): ColumnarSemanticTypeResolution {
    catalogInputs := new List<ColumnarStructInput>()
    catalogInputs.Add(MemberIteratorControlsInput(inputName, fieldNames, fieldCanonicals))
    catalogProgram := ColumnarProgramInput.CreateSingleSource(
        source,
        new List<ColumnarFunctionInput>(),
        new List<ColumnarEnumInput>(),
        catalogInputs,
        new List<ColumnarUnionInput>(),
        new List<ColumnarInterfaceInput>(),
        null
    )
    definitions := SemanticEmptyStructs()
    definitions[definition.DeclaredTypeName] = definition
    return SemanticTypeResolution(
        catalogProgram,
        0,
        SemanticEmptyEnums(),
        definitions,
        SemanticEmptyUnions(),
        null,
        definition.DeclaredTypeName
    )
}

func MemberIteratorControlsInput(
    name: string,
    fieldNames: string[],
    fieldCanonicals: string[]
): ColumnarStructInput {
    return new ColumnarStructInput(
        name,
        fieldNames,
        fieldCanonicals,
        new List<ColumnarFunctionInput>(),
        new List<ColumnarConstructorInput>(),
        new List<ColumnarPropertyInput>(),
        true
    )
}

func MemberIteratorControlsDefinition(
    owner: TypeBuilder,
    declaredName: string,
    hasValueField: bool
): ColumnarStructDef {
    fields := new Dictionary<string, FieldBuilder>(StringComparer.Ordinal)
    fieldOrder := new string[](0)
    if hasValueField {
        value := owner.DefineField("Value", typeof(int), FieldAttributes.Public)
        fields["Value"] = value
        fieldOrder = new string[](1)
        fieldOrder[0] = "Value"
    }
    return new ColumnarStructDef(owner, fieldOrder, fields, true, false, false, declaredName)
}

func MemberIteratorControlsInstanceFactory(
    owner: TypeBuilder,
    name: string,
    parameterTypes: Type[]
): MethodBuilder {
    return owner.DefineMethod(
        name,
        (MethodAttributes)6,
        typeof(IEnumerable<int>),
        parameterTypes
    )
}

func MemberIteratorControlsRows(first: object, second: object): object[] {
    rows := new object[](2)
    rows[0] = first
    rows[1] = second
    return rows
}

func MemberIteratorControlsOneRow(value: object): object[] {
    rows := new object[](1)
    rows[0] = value
    return rows
}

func MemberIteratorControlsNoRows(): object[] {
    return new object[](0)
}

func MemberIteratorControlsCall(
    module: ModuleBuilder,
    definition: ColumnarStructDef,
    method: ColumnarFunctionInput,
    builder: MethodBuilder,
    isStatic: bool,
    program: ColumnarProgramInput,
    resolution: ColumnarSemanticTypeResolution,
    source: string,
    types: List<TypeBuilder>,
    ordinal: int[]
): ColumnarIteratorRealizationResult {
    return ColumnarIteratorRealization.EmitMember(
        module,
        definition,
        method,
        builder,
        isStatic,
        program,
        resolution,
        source,
        types,
        ordinal
    )
}

// Async and non-null empty generic maps return before any source-program or helper-local IL read.
// The static path instead advances its ordinal before attempting that helper-local GetILGenerator.
test "member iterator retains early rejection and static ordinal before its own IL acquisition" {
    syncSource := "func* Gen(): IEnumerable<int> { yield 1 }"
    syncProbe := new ColumnarIteratorShapeProbe(
        syncSource,
        "IEnumerable<int>",
        IteratorNoStrings(),
        IteratorNoStrings(),
        IteratorNoStrings(),
        false
    )
    asyncSource := "async func* Gen(): IAsyncEnumerable<int> { yield 1 }"
    asyncProbe := new ColumnarIteratorShapeProbe(
        asyncSource,
        "IAsyncEnumerable<int>",
        IteratorNoStrings(),
        IteratorNoStrings(),
        IteratorNoStrings(),
        false,
        true
    )
    owner := IteratorRealizationControlPersistedHost("MemberIteratorEarlyHost")
    definition := MemberIteratorControlsDefinition(owner, "MemberIteratorEarlyHost", false)
    definition.GenericParameters = new Dictionary<string, Type>(StringComparer.Ordinal)
    asyncMethod := IteratorRealizationControlFunction(
        asyncProbe,
        "Gen",
        "IAsyncEnumerable<int>",
        IteratorNoStrings(),
        true,
        801
    )
    asyncTypes := new List<TypeBuilder>()
    asyncOrdinal := new int[](1)
    asyncOrdinal[0] = 12
    asyncResult: ColumnarIteratorRealizationResult = MemberIteratorControlsCall(
        null,
        definition,
        asyncMethod,
        null,
        true,
        null,
        null,
        asyncSource,
        asyncTypes,
        asyncOrdinal
    )
    assert !asyncResult.Succeeded
    assert asyncResult.DeclineSite == "emit.iterator.async-unsupported"
    assert asyncResult.DeclineMessage == "async member iterator methods are not yet lowered"
    assert asyncResult.DeclineMember == "MemberIteratorEarlyHost.Gen"
    assert asyncTypes.Count == 0
    assert asyncOrdinal[0] == 12

    genericMethod := IteratorRealizationControlFunction(
        syncProbe,
        "Gen",
        "IEnumerable<int>",
        IteratorNoStrings(),
        false,
        802
    )
    genericTypes := new List<TypeBuilder>()
    genericOrdinal := new int[](1)
    genericOrdinal[0] = 13
    genericResult: ColumnarIteratorRealizationResult = MemberIteratorControlsCall(
        null,
        definition,
        genericMethod,
        null,
        false,
        null,
        null,
        syncSource,
        genericTypes,
        genericOrdinal
    )
    assert !genericResult.Succeeded
    assert genericResult.DeclineSite == "emit.iterator.instance-unsupported"
    assert genericResult.DeclineMessage == "generic instance iterator methods are not yet lowered"
    assert genericResult.DeclineMember == "MemberIteratorEarlyHost.Gen"
    assert genericTypes.Count == 0
    assert genericOrdinal[0] == 13

    definition.GenericParameters = null
    staticTypes := new List<TypeBuilder>()
    staticOrdinal := new int[](1)
    staticOrdinal[0] = 14
    staticThrew := false
    try {
        MemberIteratorControlsCall(
            null,
            definition,
            genericMethod,
            null,
            true,
            null,
            null,
            syncSource,
            staticTypes,
            staticOrdinal
        )
    } catch error: NullReferenceException {
        staticThrew = true
    }
    assert staticThrew
    assert staticTypes.Count == 0
    assert staticOrdinal[0] == 15
}

// The first matching source row is selected through IEnumerable<T>, then disposed before later
// field canonical indexing. A second matching row would fail if the loop did not break at first hit.
test "member iterator takes the first source row and disposes before field and ordinal phases" {
    source := "func* Gen(): IEnumerable<int> { yield Value }"
    probe := new ColumnarIteratorShapeProbe(
        source,
        "IEnumerable<int>",
        IteratorNoStrings(),
        IteratorNoStrings(),
        IteratorNoStrings(),
        false
    )
    function := IteratorRealizationControlFunction(
        probe,
        "Gen",
        "IEnumerable<int>",
        IteratorNoStrings(),
        false,
        803
    )

    firstFieldNames := new string[](4)
    firstFieldNames[0] = "Value"
    firstFieldNames[1] = ""
    firstFieldNames[2] = "lower"
    firstFieldNames[3] = "Absent"
    first := MemberIteratorControlsInput(
        "First",
        firstFieldNames,
        IteratorNoStrings()
    )
    later := MemberIteratorControlsInput(
        "First",
        IteratorOne("Value"),
        IteratorNoStrings()
    )
    positiveState := new MemberIteratorControlsRowsState(
        MemberIteratorControlsRows(first, later),
        false
    )
    positiveState.RepairRows.Add(first)
    positiveState.RepairFieldCanonicals = IteratorOne("int")
    positiveRows := MemberIteratorControlsWrapReadOnlyList(
        "MemberIteratorFirstRows",
        typeof(ColumnarStructInput),
        positiveState
    )
    positiveProgram := MemberIteratorControlsEmptyProgram(source)
    MemberIteratorControlsSetStructs(positiveProgram, positiveRows)
    positiveOwner := IteratorRealizationControlPersistedHost("MemberIteratorFirstHost")
    positiveDefinition := MemberIteratorControlsDefinition(
        positiveOwner,
        "First",
        true
    )
    lowerHandle := positiveOwner.DefineField("lower", typeof(int), FieldAttributes.Public)
    positiveDefinition.Fields["lower"] = lowerHandle
    positiveFactory := MemberIteratorControlsInstanceFactory(
        positiveOwner,
        "Gen",
        System.Type.EmptyTypes
    )
    positiveTypes := new List<TypeBuilder>()
    positiveOrdinal := new int[](1)
    positiveOrdinal[0] = 20
    positiveModule := IteratorRealizationControlPersistedModule(positiveOwner)
    catalogFieldCanonicals := new string[](4)
    catalogFieldCanonicals[0] = "int"
    catalogFieldCanonicals[1] = "int"
    catalogFieldCanonicals[2] = "int"
    catalogFieldCanonicals[3] = "int"
    positiveResolution := MemberIteratorControlsEnclosingResolution(
        source,
        "First",
        firstFieldNames,
        catalogFieldCanonicals,
        positiveDefinition
    )
    positiveResult: ColumnarIteratorRealizationResult = MemberIteratorControlsCall(
        positiveModule,
        positiveDefinition,
        function,
        positiveFactory,
        false,
        positiveProgram,
        positiveResolution,
        source,
        positiveTypes,
        positiveOrdinal
    )
    assert positiveResult.Succeeded
    assert positiveTypes.Count == 1
    assert positiveOrdinal[0] == 21
    assert positiveState.MoveCount == 1
    assert positiveState.CurrentCount == 1
    assert positiveState.DisposeCount == 1

    shortFirst := MemberIteratorControlsInput(
        "Throw",
        IteratorOne("Value"),
        IteratorNoStrings()
    )
    shortLater := MemberIteratorControlsInput(
        "Throw",
        IteratorOne("Value"),
        IteratorOne("int")
    )
    throwingState := new MemberIteratorControlsRowsState(
        MemberIteratorControlsRows(shortFirst, shortLater),
        true
    )
    throwingRows := MemberIteratorControlsWrapReadOnlyList(
        "MemberIteratorThrowingStructRows",
        typeof(ColumnarStructInput),
        throwingState
    )
    throwingProgram := MemberIteratorControlsEmptyProgram(source)
    MemberIteratorControlsSetStructs(throwingProgram, throwingRows)
    throwingOwner := IteratorRealizationControlPersistedHost("MemberIteratorThrowingHost")
    throwingDefinition := MemberIteratorControlsDefinition(
        throwingOwner,
        "Scope.Throw",
        true
    )
    throwingTypes := new List<TypeBuilder>()
    throwingOrdinal := new int[](1)
    throwingOrdinal[0] = 22
    throwingCaught := false
    try {
        MemberIteratorControlsCall(
            null,
            throwingDefinition,
            function,
            null,
            false,
            throwingProgram,
            null,
            source,
            throwingTypes,
            throwingOrdinal
        )
    } catch error: InvalidOperationException {
        throwingCaught = error.Message == "member iterator fixture disposal failed"
    }
    assert throwingCaught
    assert throwingTypes.Count == 0
    assert throwingOrdinal[0] == 22
    assert throwingState.MoveCount == 1
    assert throwingState.CurrentCount == 1
    assert throwingState.DisposeCount == 1
}

// An exhausted method source is disposed before AnalyzeShape. The normal twin reaches its shape
// decline and advances the instance-shape ordinal exactly once without obtaining the factory IL.
test "member iterator disposes method enumeration before its shape phase" {
    source := "func* Bad(): IEnumerable<int> { Value = 3\n yield 1 }"
    probe := new ColumnarIteratorShapeProbe(
        source,
        "IEnumerable<int>",
        IteratorNoStrings(),
        IteratorNoStrings(),
        IteratorNoStrings(),
        false
    )
    function := IteratorRealizationControlFunction(
        probe,
        "Bad",
        "IEnumerable<int>",
        IteratorNoStrings(),
        false,
        804
    )
    input := MemberIteratorControlsInput(
        "Methods",
        IteratorOne("Value"),
        IteratorOne("int")
    )
    throwingMethodsState := new MemberIteratorControlsRowsState(
        MemberIteratorControlsNoRows(),
        true
    )
    throwingMethods := MemberIteratorControlsWrapReadOnlyList(
        "MemberIteratorThrowingMethods",
        typeof(ColumnarFunctionInput),
        throwingMethodsState
    )
    program := MemberIteratorControlsEmptyProgram(source)
    MemberIteratorControlsSetMethods(input, throwingMethods)
    structs := new List<ColumnarStructInput>()
    structs.Add(input)
    structsObject: object = structs
    MemberIteratorControlsSetStructs(program, structsObject)
    owner := IteratorRealizationControlPersistedHost("MemberIteratorMethodsHost")
    definition := MemberIteratorControlsDefinition(owner, "Methods", true)
    throwingTypes := new List<TypeBuilder>()
    throwingOrdinal := new int[](1)
    throwingOrdinal[0] = 30
    throwingCaught := false
    try {
        MemberIteratorControlsCall(
            null,
            definition,
            function,
            null,
            false,
            program,
            null,
            source,
            throwingTypes,
            throwingOrdinal
        )
    } catch error: InvalidOperationException {
        throwingCaught = error.Message == "member iterator fixture disposal failed"
    }
    assert throwingCaught
    assert throwingTypes.Count == 0
    assert throwingOrdinal[0] == 30
    assert throwingMethodsState.MoveCount == 0
    assert throwingMethodsState.CurrentCount == 0
    assert throwingMethodsState.DisposeCount == 1

    normalMethodsState := new MemberIteratorControlsRowsState(
        MemberIteratorControlsNoRows(),
        false
    )
    normalMethods := MemberIteratorControlsWrapReadOnlyList(
        "MemberIteratorNormalMethods",
        typeof(ColumnarFunctionInput),
        normalMethodsState
    )
    MemberIteratorControlsSetMethods(input, normalMethods)
    normalTypes := new List<TypeBuilder>()
    normalOrdinal := new int[](1)
    normalOrdinal[0] = 31
    normalResult: ColumnarIteratorRealizationResult = MemberIteratorControlsCall(
        null,
        definition,
        function,
        null,
        false,
        program,
        null,
        source,
        normalTypes,
        normalOrdinal
    )
    assert !normalResult.Succeeded
    assert normalResult.DeclineSite == "emit.iterator.unsupported-shape"
    assert normalResult.DeclineMember == "MemberIteratorMethodsHost.Bad"
    assert normalTypes.Count == 0
    assert normalOrdinal[0] == 32
    assert normalMethodsState.MoveCount == 0
    assert normalMethodsState.CurrentCount == 0
    assert normalMethodsState.DisposeCount == 1
}

// The driver deliberately rereads the live method name for the exact Methods and MethodOverloads
// lookups. A comparer mutates Original to Changed during the first lookup; Changed's two overloads
// then reject the candidate. A normal twin proves Original would otherwise realize successfully.
test "member iterator preserves live repeated method-name reads and overload admission" {
    positiveSource := "func* Gen(other: MethodPositive): IEnumerable<int> { for value in other.Original() { yield value } }"
    positiveProbe := new ColumnarIteratorShapeProbe(
        positiveSource,
        "IEnumerable<int>",
        IteratorOne("other"),
        IteratorOne("MethodPositive"),
        IteratorNoStrings(),
        false
    )

    positiveCandidate := IteratorRealizationControlFunction(
        positiveProbe,
        "Original",
        "IEnumerable<int>",
        IteratorNoStrings(),
        false,
        805
    )
    positiveInput := MemberIteratorControlsInput(
        "MethodPositive",
        IteratorNoStrings(),
        IteratorNoStrings()
    )
    positiveMethods := new List<ColumnarFunctionInput>()
    positiveMethods.Add(positiveCandidate)
    positiveProgram := MemberIteratorControlsEmptyProgram(positiveSource)
    positiveMethodsObject: object = positiveMethods
    MemberIteratorControlsSetMethods(positiveInput, positiveMethodsObject)
    positiveStructs := new List<ColumnarStructInput>()
    positiveStructs.Add(positiveInput)
    positiveStructsObject: object = positiveStructs
    MemberIteratorControlsSetStructs(positiveProgram, positiveStructsObject)
    positiveOwner := IteratorRealizationControlPersistedHost("MemberIteratorMethodPositiveHost")
    positiveDefinition := MemberIteratorControlsDefinition(
        positiveOwner,
        "MethodPositive",
        false
    )
    noTypes := new Type[](0)
    SourceCallPublicInstance(positiveDefinition, "Original", noTypes, typeof(IEnumerable<int>))
    positiveFactoryParameters := new Type[](1)
    positiveOwnerType: Type = positiveOwner
    positiveFactoryParameters[0] = positiveOwnerType
    positiveFactory := MemberIteratorControlsInstanceFactory(
        positiveOwner,
        "Gen",
        positiveFactoryParameters
    )
    positiveTypes := new List<TypeBuilder>()
    positiveOrdinal := new int[](1)
    positiveOrdinal[0] = 40
    positiveResult: ColumnarIteratorRealizationResult = MemberIteratorControlsCall(
        IteratorRealizationControlPersistedModule(positiveOwner),
        positiveDefinition,
        IteratorRealizationControlFunctionWithSignature(
            positiveProbe,
            "Gen",
            "IEnumerable<int>",
            IteratorOne("other"),
            IteratorOne("MethodPositive"),
            IteratorNoStrings(),
            false,
            805
        ),
        positiveFactory,
        false,
        positiveProgram,
        MemberIteratorControlsEnclosingResolution(
            positiveSource,
            "MethodPositive",
            IteratorNoStrings(),
            IteratorNoStrings(),
            positiveDefinition
        ),
        positiveSource,
        positiveTypes,
        positiveOrdinal
    )
    assert positiveResult.Succeeded
    assert positiveTypes.Count == 1
    assert positiveOrdinal[0] == 41

    // A live matching overload key whose value is null reaches the concrete List dereference only
    // after the method walk's finally. This is intentionally an internal malformed fact: it pins
    // the existing null-dereference phase rather than adding a prevalidation policy.
    nullSource := "func* Gen(): IEnumerable<int> { yield 1 }"
    nullProbe := new ColumnarIteratorShapeProbe(
        nullSource,
        "IEnumerable<int>",
        IteratorNoStrings(),
        IteratorNoStrings(),
        IteratorNoStrings(),
        false
    )
    nullIterator := IteratorRealizationControlFunction(
        nullProbe,
        "Gen",
        "IEnumerable<int>",
        IteratorNoStrings(),
        false,
        807
    )
    nullCandidate := IteratorRealizationControlFunction(
        nullProbe,
        "Original",
        "IEnumerable<int>",
        IteratorNoStrings(),
        false,
        807
    )
    nullInput := MemberIteratorControlsInput(
        "NullOverloads",
        IteratorNoStrings(),
        IteratorNoStrings()
    )
    nullMethodsState := new MemberIteratorControlsRowsState(
        MemberIteratorControlsOneRow(nullCandidate),
        false
    )
    nullMethods := MemberIteratorControlsWrapReadOnlyList(
        "MemberIteratorNullOverloadsMethods",
        typeof(ColumnarFunctionInput),
        nullMethodsState
    )
    nullProgram := MemberIteratorControlsEmptyProgram(nullSource)
    MemberIteratorControlsSetMethods(nullInput, nullMethods)
    nullStructs := new List<ColumnarStructInput>()
    nullStructs.Add(nullInput)
    nullStructsObject: object = nullStructs
    MemberIteratorControlsSetStructs(nullProgram, nullStructsObject)
    nullOwner := IteratorRealizationControlPersistedHost("MemberIteratorNullOverloadsHost")
    nullDefinition := MemberIteratorControlsDefinition(
        nullOwner,
        "NullOverloads",
        false
    )
    SourceCallPublicInstance(nullDefinition, "Original", noTypes, typeof(IEnumerable<int>))
    missingOverloads: List<ColumnarInstanceMethodDef> = null
    nullDefinition.MethodOverloads["Original"] = missingOverloads
    nullTypes := new List<TypeBuilder>()
    nullOrdinal := new int[](1)
    nullOrdinal[0] = 41
    expectedNull := new NullReferenceException()
    expectedNullMessage := expectedNull.Message
    nullCaught := false
    try {
        MemberIteratorControlsCall(
            null,
            nullDefinition,
            nullIterator,
            null,
            false,
            nullProgram,
            null,
            nullSource,
            nullTypes,
            nullOrdinal
        )
    } catch error: NullReferenceException {
        nullCaught = error.Message == expectedNullMessage
    }
    assert nullCaught
    assert nullTypes.Count == 0
    assert nullOrdinal[0] == 41
    assert nullMethodsState.MoveCount == 1
    assert nullMethodsState.CurrentCount == 1
    assert nullMethodsState.DisposeCount == 1

    mutatingSource := "func* Gen(other: MethodMutating): IEnumerable<int> { for value in other.Original() { yield value } }"
    mutatingProbe := new ColumnarIteratorShapeProbe(
        mutatingSource,
        "IEnumerable<int>",
        IteratorOne("other"),
        IteratorOne("MethodMutating"),
        IteratorNoStrings(),
        false
    )
    candidate := IteratorRealizationControlFunction(
        mutatingProbe,
        "Original",
        "IEnumerable<int>",
        IteratorNoStrings(),
        false,
        806
    )
    mutatingInput := MemberIteratorControlsInput(
        "MethodMutating",
        IteratorNoStrings(),
        IteratorNoStrings()
    )
    mutatingMethodsState := new MemberIteratorControlsRowsState(
        MemberIteratorControlsOneRow(candidate),
        false
    )
    mutatingMethods := MemberIteratorControlsWrapReadOnlyList(
        "MemberIteratorMutatingMethods",
        typeof(ColumnarFunctionInput),
        mutatingMethodsState
    )
    mutatingProgram := MemberIteratorControlsEmptyProgram(mutatingSource)
    MemberIteratorControlsSetMethods(mutatingInput, mutatingMethods)
    mutatingStructs := new List<ColumnarStructInput>()
    mutatingStructs.Add(mutatingInput)
    mutatingStructsObject: object = mutatingStructs
    MemberIteratorControlsSetStructs(mutatingProgram, mutatingStructsObject)
    mutatingOwner := IteratorRealizationControlPersistedHost("MemberIteratorMethodMutatingHost")
    mutatingDefinition := MemberIteratorControlsDefinition(
        mutatingOwner,
        "MethodMutating",
        false
    )
    memberBuilder := mutatingOwner.DefineMethod(
        "Original",
        (MethodAttributes)6,
        typeof(IEnumerable<int>),
        noTypes
    )
    memberDefinition := new ColumnarInstanceMethodDef(memberBuilder, noTypes, typeof(IEnumerable<int>))
    mutatingComparer := new MemberIteratorControlsMutatingMethodsComparer()
    mutatingMethodsMap := new Dictionary<string, ColumnarInstanceMethodDef>(mutatingComparer)
    mutatingMethodsMap["Original"] = memberDefinition
    mutatingDefinition.Methods = mutatingMethodsMap
    tracingComparer := new MemberIteratorControlsTracingOverloadsComparer()
    changedOverloads := new List<ColumnarInstanceMethodDef>()
    changedOverloads.Add(memberDefinition)
    changedOverloads.Add(memberDefinition)
    overloadMap := new Dictionary<string, List<ColumnarInstanceMethodDef>>(tracingComparer)
    overloadMap["Changed"] = changedOverloads
    mutatingDefinition.MethodOverloads = overloadMap
    mutatingComparer.Candidate = candidate
    mutatingComparer.Armed = true
    tracingComparer.Armed = true

    mutatingTypes := new List<TypeBuilder>()
    mutatingOrdinal := new int[](1)
    mutatingOrdinal[0] = 42
    mutatingResult: ColumnarIteratorRealizationResult = MemberIteratorControlsCall(
        null,
        mutatingDefinition,
        IteratorRealizationControlFunctionWithSignature(
            mutatingProbe,
            "Gen",
            "IEnumerable<int>",
            IteratorOne("other"),
            IteratorOne("MethodMutating"),
            IteratorNoStrings(),
            false,
            806
        ),
        null,
        false,
        mutatingProgram,
        null,
        mutatingSource,
        mutatingTypes,
        mutatingOrdinal
    )
    assert !mutatingResult.Succeeded
    assert mutatingResult.DeclineSite == "emit.iterator.for-in-unsupported"
    assert mutatingResult.DeclineMember == "MemberIteratorMethodMutatingHost.Gen"
    assert candidate.Name == "Changed"
    assert tracingComparer.Lookups.Count == 1
    assert tracingComparer.Lookups[0] == "Changed"
    assert mutatingMethodsState.MoveCount == 1
    assert mutatingMethodsState.CurrentCount == 1
    assert mutatingMethodsState.DisposeCount == 1
    assert mutatingTypes.Count == 0
    assert mutatingOrdinal[0] == 43
}

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
    // Existing controls keep the Count trap armed. The constructor trace control opts in so it can
    // reach the production foreach and prove that its finally runs after the trace record.
    CountAllowed: bool
    RepairRows: List<ColumnarStructInput>
    RepairFieldCanonicals: string[]

    constructor(rows: object[], throwOnDispose: bool) {
        Rows = rows
        MoveCount = 0
        CurrentCount = 0
        DisposeCount = 0
        ThrowOnDispose = throwOnDispose
        CountAllowed = false
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

    static func Count(state: MemberIteratorControlsRowsState): int {
        if !state.CountAllowed {
            throw new InvalidOperationException("member iterator fixture Count was read")
        }
        return state.Rows.Length
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
    constructor := EmitFixtureRequiredConstructor(typeof(InvalidOperationException), messageParameters)
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

    owner := EmitFixtureTypeBuilder(
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
    stateField := EmitFixtureDefineField(
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
    objectConstructor := EmitFixtureRequiredConstructor(typeof(object), noParameters)
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Call, objectConstructor)
    constructorIl.Emit(OpCodes.Ret)

    genericGetEnumeratorTarget := EmitFixtureRequiredMethod(
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
    EmitFixtureReturnThis(genericGetEnumerator)
    owner.DefineMethodOverride(genericGetEnumerator, genericGetEnumeratorTarget)

    nongenericGetEnumeratorTarget := EmitFixtureRequiredMethod(
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
    EmitFixtureReturnThis(nongenericGetEnumerator)
    owner.DefineMethodOverride(nongenericGetEnumerator, nongenericGetEnumeratorTarget)

    runtimeParameterTypes := new Type[](1)
    runtimeParameterTypes[0] = typeof(MemberIteratorControlsRowsState)
    moveNextRuntime := EmitFixtureRequiredMethod(
        typeof(MemberIteratorControlsRowsRuntime),
        "MoveNext",
        runtimeParameterTypes
    )
    currentRuntime := EmitFixtureRequiredMethod(
        typeof(MemberIteratorControlsRowsRuntime),
        "Current",
        runtimeParameterTypes
    )
    disposeRuntime := EmitFixtureRequiredMethod(
        typeof(MemberIteratorControlsRowsRuntime),
        "Dispose",
        runtimeParameterTypes
    )
    countRuntime := EmitFixtureRequiredMethod(
        typeof(MemberIteratorControlsRowsRuntime),
        "Count",
        runtimeParameterTypes
    )

    genericCurrentTarget := EmitFixtureRequiredGetter(genericEnumerator, "Current")
    genericCurrent := owner.DefineMethod(
        "GenericCurrent",
        (MethodAttributes)481,
        elementType,
        noParameters
    )
    genericCurrentIl := EmitFixtureIL(genericCurrent)
    genericCurrentIl.Emit(OpCodes.Ldarg_0)
    genericCurrentIl.Emit(OpCodes.Ldfld, stateField)
    genericCurrentIl.Emit(OpCodes.Call, currentRuntime)
    genericCurrentIl.Emit(OpCodes.Castclass, elementType)
    genericCurrentIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(genericCurrent, genericCurrentTarget)

    nongenericCurrentTarget := EmitFixtureRequiredGetter(nongenericEnumerator, "Current")
    nongenericCurrent := owner.DefineMethod(
        "NongenericCurrent",
        (MethodAttributes)481,
        typeof(object),
        noParameters
    )
    nongenericCurrentIl := EmitFixtureIL(nongenericCurrent)
    MemberIteratorControlsEmitInvalidOperation(
        nongenericCurrentIl,
        "member iterator fixture nongeneric Current was read"
    )
    owner.DefineMethodOverride(nongenericCurrent, nongenericCurrentTarget)

    moveNextTarget := EmitFixtureRequiredMethod(nongenericEnumerator, "MoveNext", noParameters)
    moveNext := owner.DefineMethod(
        "MoveNext",
        (MethodAttributes)481,
        typeof(bool),
        noParameters
    )
    moveNextIl := EmitFixtureIL(moveNext)
    moveNextIl.Emit(OpCodes.Ldarg_0)
    moveNextIl.Emit(OpCodes.Ldfld, stateField)
    moveNextIl.Emit(OpCodes.Call, moveNextRuntime)
    moveNextIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(moveNext, moveNextTarget)

    resetTarget := EmitFixtureRequiredMethod(nongenericEnumerator, "Reset", noParameters)
    reset := owner.DefineMethod(
        "Reset",
        (MethodAttributes)481,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        noParameters
    )
    resetIl := EmitFixtureIL(reset)
    resetIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(reset, resetTarget)

    disposeTarget := EmitFixtureRequiredMethod(disposable, "Dispose", noParameters)
    dispose := owner.DefineMethod(
        "Dispose",
        (MethodAttributes)481,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        noParameters
    )
    disposeIl := EmitFixtureIL(dispose)
    disposeIl.Emit(OpCodes.Ldarg_0)
    disposeIl.Emit(OpCodes.Ldfld, stateField)
    disposeIl.Emit(OpCodes.Call, disposeRuntime)
    disposeIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(dispose, disposeTarget)

    countTarget := EmitFixtureRequiredGetter(genericCollection, "Count")
    count := owner.DefineMethod(
        "get_Count",
        (MethodAttributes)481,
        typeof(int),
        noParameters
    )
    countIl := EmitFixtureIL(count)
    countIl.Emit(OpCodes.Ldarg_0)
    countIl.Emit(OpCodes.Ldfld, stateField)
    countIl.Emit(OpCodes.Call, countRuntime)
    countIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(count, countTarget)

    indexParameters := new Type[](1)
    indexParameters[0] = typeof(int)
    itemTarget := EmitFixtureRequiredGetter(genericList, "Item")
    item := owner.DefineMethod(
        "get_Item",
        (MethodAttributes)481,
        elementType,
        indexParameters
    )
    itemIl := EmitFixtureIL(item)
    MemberIteratorControlsEmitInvalidOperation(itemIl, "member iterator fixture indexer was read")
    owner.DefineMethodOverride(item, itemTarget)

    baked := EmitFixtureBake(owner)
    instanceConstructor := EmitFixtureRequiredConstructor(baked, noParameters)
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
    setter := EmitFixtureRequiredMethod(typeof(MemberIteratorControlsTypedLists), "SetStructs", parameterTypes)
    arguments := new object[](2)
    EmitFixtureSetObject(arguments, 0, program)
    EmitFixtureSetObject(arguments, 1, rows)
    ignored := setter.Invoke(null, arguments)
    _ = ignored
}

func MemberIteratorControlsSetMethods(input: ColumnarStructInput, rows: object) {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(ColumnarStructInput)
    parameterTypes[1] = typeof(IReadOnlyList<ColumnarFunctionInput>)
    setter := EmitFixtureRequiredMethod(typeof(MemberIteratorControlsTypedLists), "SetMethods", parameterTypes)
    arguments := new object[](2)
    EmitFixtureSetObject(arguments, 0, input)
    EmitFixtureSetObject(arguments, 1, rows)
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
    definitions := EmitFixtureEmptyStructs()
    definitions[definition.DeclaredTypeName] = definition
    return EmitFixtureTypeResolution(
        catalogProgram,
        0,
        EmitFixtureEmptyEnums(),
        definitions,
        EmitFixtureEmptyUnions(),
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
    ordinal: int[],
    bodyFacts: ColumnarIteratorBodyFacts?
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
        ordinal,
        bodyFacts
    )
}

// The live facts a member iterator's BODY resolves its own expressions through: the enclosing type's
// definition, which is what an `other.Original()` receiver's member lookup needs.
func MemberIteratorControlsBodyFacts(definition: ColumnarStructDef, resolution: ColumnarSemanticTypeResolution): ColumnarIteratorBodyFacts {
    definitions := new List<ColumnarStructDef>()
    definitions.Add(definition)
    return new ColumnarIteratorBodyFacts(
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        definitions,
        new List<ColumnarUnionDef>(),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal),
        new string[](0),
        definition,
        resolution.StructuralTypeReferences
    )
}

// Async and non-null empty generic maps return before any source-program or helper-local IL read.
// The static path instead advances its ordinal before attempting that helper-local GetILGenerator.
test "member iterator retains early rejection and static ordinal before its own IL acquisition" {
    syncSource := "func* Gen(): IEnumerable<int> { yield 1 }"
    syncProbe := new EmitFixtureIteratorShapeProbe(
        syncSource,
        "IEnumerable<int>",
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        false
    )
    asyncSource := "async func* Gen(): IAsyncEnumerable<int> { yield 1 }"
    asyncProbe := new EmitFixtureIteratorShapeProbe(
        asyncSource,
        "IAsyncEnumerable<int>",
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
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
        EmitFixtureNoStrings(),
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
        asyncOrdinal,
        null
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
        EmitFixtureNoStrings(),
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
        genericOrdinal,
        null
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
            staticOrdinal,
            null
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
    probe := new EmitFixtureIteratorShapeProbe(
        source,
        "IEnumerable<int>",
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        false
    )
    function := IteratorRealizationControlFunction(
        probe,
        "Gen",
        "IEnumerable<int>",
        EmitFixtureNoStrings(),
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
        EmitFixtureNoStrings()
    )
    later := MemberIteratorControlsInput(
        "First",
        EmitFixtureOneString("Value"),
        EmitFixtureNoStrings()
    )
    positiveState := new MemberIteratorControlsRowsState(
        MemberIteratorControlsRows(first, later),
        false
    )
    positiveState.RepairRows.Add(first)
    // The camelCase `lower` is published like any other field the definition holds, so its canonical
    // is read; `Absent` is not in the definition, so the repaired row stops short of it and would
    // throw if it were read.
    repairedCanonicals := new string[](3)
    repairedCanonicals[0] = "int"
    repairedCanonicals[1] = "int"
    repairedCanonicals[2] = "int"
    positiveState.RepairFieldCanonicals = repairedCanonicals
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
        positiveOrdinal,
        null
    )
    assert positiveResult.Succeeded
    assert positiveTypes.Count == 1
    assert positiveOrdinal[0] == 21
    assert positiveState.MoveCount == 1
    assert positiveState.CurrentCount == 1
    assert positiveState.DisposeCount == 1

    shortFirst := MemberIteratorControlsInput(
        "Throw",
        EmitFixtureOneString("Value"),
        EmitFixtureNoStrings()
    )
    shortLater := MemberIteratorControlsInput(
        "Throw",
        EmitFixtureOneString("Value"),
        EmitFixtureOneString("int")
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
            throwingOrdinal,
            null
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

// METHOD SIGNATURES ARE NOT ITERATOR SHAPE INPUT. The method list is hostile: enumerating it
// would throw during disposal. The invalid body still reaches the ordinary shape refusal, so this
// row proves that the removed enclosing-method projection is not part of the realization path.
test "member iterator does not enumerate enclosing methods before its shape phase" {
    source := "func* Bad(): IEnumerable<int> { Absent = 3\n yield 1 }"
    probe := new EmitFixtureIteratorShapeProbe(
        source,
        "IEnumerable<int>",
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        false
    )
    function := IteratorRealizationControlFunction(
        probe,
        "Bad",
        "IEnumerable<int>",
        EmitFixtureNoStrings(),
        false,
        804
    )
    input := MemberIteratorControlsInput(
        "Methods",
        EmitFixtureOneString("Value"),
        EmitFixtureOneString("int")
    )
    methodsState := new MemberIteratorControlsRowsState(
        MemberIteratorControlsNoRows(),
        true
    )
    methods := MemberIteratorControlsWrapReadOnlyList(
        "MemberIteratorThrowingMethods",
        typeof(ColumnarFunctionInput),
        methodsState
    )
    MemberIteratorControlsSetMethods(input, methods)
    program := MemberIteratorControlsEmptyProgram(source)
    inputs := new List<ColumnarStructInput>()
    inputs.Add(input)
    inputsObject: object = inputs
    MemberIteratorControlsSetStructs(program, inputsObject)
    owner := IteratorRealizationControlPersistedHost("MemberIteratorMethodsHost")
    definition := MemberIteratorControlsDefinition(owner, "Methods", true)
    types := new List<TypeBuilder>()
    ordinal := new int[](1)
    ordinal[0] = 31

    result: ColumnarIteratorRealizationResult = MemberIteratorControlsCall(
        null,
        definition,
        function,
        null,
        false,
        program,
        null,
        source,
        types,
        ordinal,
        null
    )
    assert !result.Succeeded
    assert result.DeclineSite == "emit.iterator.unsupported-shape"
    assert result.DeclineMember == "MemberIteratorMethodsHost.Bad"
    assert types.Count == 0
    assert ordinal[0] == 32
    assert methodsState.MoveCount == 0
    assert methodsState.CurrentCount == 0
    assert methodsState.DisposeCount == 0
}

// A successful member generator makes the same promise as the declining one: the input's method
// list is irrelevant to field discovery, shape planning and realization. The nested machine is
// built from the body and its fields; no enclosing method-name table is needed.
test "member iterator realizes a body without enumerating enclosing method rows" {
    source := "func* Gen(): IEnumerable<int> { yield 1 }"
    probe := new EmitFixtureIteratorShapeProbe(
        source,
        "IEnumerable<int>",
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        false
    )
    function := IteratorRealizationControlFunction(
        probe,
        "Gen",
        "IEnumerable<int>",
        EmitFixtureNoStrings(),
        false,
        807
    )
    input := MemberIteratorControlsInput(
        "MethodFactsHost",
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings()
    )
    methodsState := new MemberIteratorControlsRowsState(
        MemberIteratorControlsNoRows(),
        true
    )
    methods := MemberIteratorControlsWrapReadOnlyList(
        "MemberIteratorSuccessfulThrowingMethods",
        typeof(ColumnarFunctionInput),
        methodsState
    )
    MemberIteratorControlsSetMethods(input, methods)
    program := MemberIteratorControlsEmptyProgram(source)
    inputs := new List<ColumnarStructInput>()
    inputs.Add(input)
    inputsObject: object = inputs
    MemberIteratorControlsSetStructs(program, inputsObject)
    owner := IteratorRealizationControlPersistedHost("MemberIteratorMethodFactsHost")
    definition := MemberIteratorControlsDefinition(owner, "MethodFactsHost", false)
    factory := MemberIteratorControlsInstanceFactory(owner, "Gen", System.Type.EmptyTypes)
    resolution := MemberIteratorControlsEnclosingResolution(
        source,
        "MethodFactsHost",
        EmitFixtureNoStrings(),
        EmitFixtureNoStrings(),
        definition
    )
    types := new List<TypeBuilder>()
    ordinal := new int[](1)
    ordinal[0] = 40

    result: ColumnarIteratorRealizationResult = MemberIteratorControlsCall(
        IteratorRealizationControlPersistedModule(owner),
        definition,
        function,
        factory,
        false,
        program,
        resolution,
        source,
        types,
        ordinal,
        null
    )
    assert result.Succeeded
    assert types.Count == 1
    assert ordinal[0] == 41
    assert methodsState.MoveCount == 0
    assert methodsState.CurrentCount == 0
    assert methodsState.DisposeCount == 0
}

// The planner's declaration walk over the hostile constructor list above: a disposal failure after
// the decline is recorded is the one outcome the row below accepts.
func MemberIteratorControlsCatchesHostileDeclarationDispose(
    program: ColumnarProgramInput,
    inputs: List<ColumnarStructInput>,
    definitions: ColumnarStructDef[],
    resolutions: ColumnarSemanticTypeResolution[],
    depths: int[]
): bool {
    try {
        ColumnarConstructorDeclarationPlanner.Declare(
            program,
            inputs,
            definitions,
            resolutions,
            depths,
            new ColumnarSourceAttributeQueue()
        )
    } catch error: InvalidOperationException {
        return error.Message == "member iterator fixture disposal failed"
    }
    return false
}

// THE DECLARATION WALK RECORDS ITS DECLINE BEFORE THE CONSTRUCTOR ITERATOR IT HOLDS IS DISPOSED, even
// when that disposal throws. The hostile list is this file's own emitted `IReadOnlyList<T>`, so the
// row lives beside it rather than beside the planner's trace rows.
test "constructor declaration records its decline before a hostile constructor iterator throws on disposal" {
    definition := EmitFixtureStructDefinition("ConstructorDeclineTraceDispose", 0)
    brokenBody := EmitFixtureEmptyBody(
        "Broken",
        new string[](0),
        new string[](0)
    )
    brokenConstructor := EmitFixtureConstructor(
        brokenBody,
        2,
        new int[](0),
        new string[](0),
        false
    )
    input := EmitFixtureStructInput(
        definition.DeclaredTypeName,
        new List<ColumnarConstructorInput>()
    )
    inputs := new List<ColumnarStructInput>()
    inputs.Add(input)
    definitions := new ColumnarStructDef[](1)
    definitions[0] = definition
    depths := new int[](1)
    program := EmitFixtureSingleSourceProgram("", inputs)
    resolutions := EmitFixtureResolutions(program, definitions)

    rows := new object[](1)
    EmitFixtureSetObject(rows, 0, brokenConstructor)
    state := new MemberIteratorControlsRowsState(rows, true)
    state.CountAllowed = true
    hostileRows := MemberIteratorControlsWrapReadOnlyList(
        "ConstructorDeclineTraceHostileConstructors",
        typeof(ColumnarConstructorInput),
        state
    )
    input.Constructors = (IReadOnlyList<ColumnarConstructorInput>)hostileRows

    ColumnarDeclineTrace.Reset()
    try {
        disposalCaught := MemberIteratorControlsCatchesHostileDeclarationDispose(
            program,
            inputs,
            definitions,
            resolutions,
            depths
        )
        assert disposalCaught
        snapshot := ColumnarDeclineTrace.Snapshot()
        assert snapshot.Count == 1
        assert snapshot[0].SiteId == "emit.ctor.base-chain-without-base"
        assert snapshot[0].Message == "constructor base initializer requires a modeled base class"
        assert snapshot[0].MemberName == definition.Builder.get_Name() + ".constructor"
        assert snapshot[0].SpanStart == -1
        assert snapshot[0].SpanLength == 0
        assert !snapshot[0].HasSourceFileId
        assert state.MoveCount == 1
        assert state.CurrentCount == 1
        assert state.DisposeCount == 1
    } finally {
        ColumnarDeclineTrace.Reset()
    }
}

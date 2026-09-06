namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Threading.Tasks


// These controls cross the complete entry-point realization door.  The production fallback keeps
// the concrete Dictionary.ValueCollection.Enumerator, so the list observation below is intentionally
// limited to the two indexed top-level walks; static fallback remains an ordinary Dictionary witness.
class EntryPointRealizationControlsFunctionRowsState {
    Rows: object[]
    Trace: List<int>
    CountCalls: int
    ThrowOnCountCall: int
    MoveCalls: int

    constructor(rows: object[], throwOnCountCall: int = 0) {
        Rows = rows
        Trace = new List<int>()
        CountCalls = 0
        ThrowOnCountCall = throwOnCountCall
        MoveCalls = 0
    }
}

class EntryPointRealizationControlsFunctionRowsRuntime {
    static func Count(state: EntryPointRealizationControlsFunctionRowsState): int {
        state.CountCalls = state.CountCalls + 1
        state.Trace.Add(10)
        if state.ThrowOnCountCall == state.CountCalls {
            throw new InvalidOperationException("entry-point function-list Count was read")
        }
        return state.Rows.Length
    }

    static func Item(state: EntryPointRealizationControlsFunctionRowsState, index: int): object {
        state.Trace.Add(100 + index)
        return state.Rows[index]
    }

    static func MoveNext(state: EntryPointRealizationControlsFunctionRowsState): bool {
        if state.MoveCalls >= state.Rows.Length {
            return false
        }
        state.MoveCalls = state.MoveCalls + 1
        return true
    }

    static func Current(state: EntryPointRealizationControlsFunctionRowsState): object {
        if state.MoveCalls == 0 || state.MoveCalls > state.Rows.Length {
            throw new InvalidOperationException("entry-point function-list Current was read outside MoveNext")
        }
        return state.Rows[state.MoveCalls - 1]
    }

    static func Dispose(state: EntryPointRealizationControlsFunctionRowsState) {
    }
}

func EntryPointRealizationControlsThrow(il: ILGenerator, message: string) {
    arguments := new Type[](1)
    arguments[0] = typeof(string)
    constructor := ExecutorRequiredConstructor(typeof(InvalidOperationException), arguments)
    il.Emit(OpCodes.Ldstr, message)
    il.Emit(OpCodes.Newobj, constructor)
    il.Emit(OpCodes.Throw)
}

// Reflection.Emit is used only to provide an exact IReadOnlyList<T> receiver whose Count/indexer
// calls are externally observable.  It implements the inherited enumeration members as required by
// the real interface, but the entry-point owner must never enumerate this input.
func EntryPointRealizationControlsObservedFunctions(
    typeName: string,
    state: EntryPointRealizationControlsFunctionRowsState
): object {
    noParameters := new Type[](0)
    elementType := typeof(ColumnarFunctionInput)
    oneElement := new Type[](1)
    oneElement[0] = elementType
    genericEnumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    genericEnumeratorDefinition := typeof(IEnumerator<int>).GetGenericTypeDefinition()
    genericCollectionDefinition := typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
    genericListDefinition := typeof(IReadOnlyList<int>).GetGenericTypeDefinition()
    genericEnumerable := genericEnumerableDefinition.MakeGenericType(oneElement)
    genericEnumerator := genericEnumeratorDefinition.MakeGenericType(oneElement)
    genericCollection := genericCollectionDefinition.MakeGenericType(oneElement)
    genericList := genericListDefinition.MakeGenericType(oneElement)
    nongenericEnumerable := typeof(IEnumerable)
    nongenericEnumerator := typeof(IEnumerator)
    disposable := typeof(IDisposable)

    owner := TypeOfCreateBuilder(
        typeName,
        "ColumnarEntryPointRealizationControls." + typeName,
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
        typeof(EntryPointRealizationControlsFunctionRowsState)
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

    stateParameter := new Type[](1)
    stateParameter[0] = typeof(EntryPointRealizationControlsFunctionRowsState)
    itemParameters := new Type[](2)
    itemParameters[0] = typeof(EntryPointRealizationControlsFunctionRowsState)
    itemParameters[1] = typeof(int)
    countRuntime := ExecutorRequiredMethod(
        typeof(EntryPointRealizationControlsFunctionRowsRuntime),
        "Count",
        stateParameter
    )
    itemRuntime := ExecutorRequiredMethod(
        typeof(EntryPointRealizationControlsFunctionRowsRuntime),
        "Item",
        itemParameters
    )
    moveNextRuntime := ExecutorRequiredMethod(
        typeof(EntryPointRealizationControlsFunctionRowsRuntime),
        "MoveNext",
        stateParameter
    )
    currentRuntime := ExecutorRequiredMethod(
        typeof(EntryPointRealizationControlsFunctionRowsRuntime),
        "Current",
        stateParameter
    )
    disposeRuntime := ExecutorRequiredMethod(
        typeof(EntryPointRealizationControlsFunctionRowsRuntime),
        "Dispose",
        stateParameter
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
    EntryPointRealizationControlsThrow(
        nongenericCurrentIl,
        "entry-point function-list nongeneric Current was read"
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
    countIl.Emit(OpCodes.Ldarg_0)
    countIl.Emit(OpCodes.Ldfld, stateField)
    countIl.Emit(OpCodes.Call, countRuntime)
    countIl.Emit(OpCodes.Ret)
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
    itemIl.Emit(OpCodes.Ldarg_0)
    itemIl.Emit(OpCodes.Ldfld, stateField)
    itemIl.Emit(OpCodes.Ldarg_1)
    itemIl.Emit(OpCodes.Call, itemRuntime)
    itemIl.Emit(OpCodes.Castclass, elementType)
    itemIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(item, itemTarget)

    baked := IdentityBake(owner)
    instanceConstructor := ExecutorRequiredConstructor(baked, noParameters)
    instance := instanceConstructor.Invoke(new object[](0))
    if instance == null {
        throw new InvalidOperationException("The observed entry-point function list was not constructed.")
    }
    bakedState := baked.GetField("State")
    if bakedState == null {
        throw new InvalidOperationException("The observed entry-point function list lost State.")
    }
    bakedState.SetValue(instance, state)
    return instance
}

class EntryPointRealizationControlsOutcome {
    Succeeded: bool
    EntryPoint: MethodBuilder?
    Error: Exception?

    constructor(succeeded: bool, entryPoint: MethodBuilder?, error: Exception?) {
        Succeeded = succeeded
        EntryPoint = entryPoint
        Error = error
    }
}

// This typed source field is populated through FieldInfo.SetValue only for the emitted fixture.
// The actual realization call receives Rows directly as IReadOnlyList<ColumnarFunctionInput>.
class EntryPointRealizationControlsObservedFunctionsFrame {
    Rows: IReadOnlyList<ColumnarFunctionInput>
}

// The direct call is inside this typed runner. A typed source field carries only the dynamically emitted
// IReadOnlyList into its exact interface parameter; it does not replace or hide the realization call.
class EntryPointRealizationControlsTypedInvoker {
    static func Invoke(
        isExecutable: bool,
        funcs: IReadOnlyList<ColumnarFunctionInput>,
        methods: MethodBuilder[],
        asyncWrappedByFunc: Type?[],
        paramTypesByFunc: Dictionary<string, Type>[],
        asyncInnerByFunc: Type[],
        programType: TypeBuilder,
        structRegistry: Dictionary<string, ColumnarStructDef>,
        typeResolutionCatalog: ColumnarSemanticTypeResolutionCatalog
    ): EntryPointRealizationControlsOutcome {
        selected: MethodBuilder? = null
        succeeded := false
        error: Exception? = null
        try {
            succeeded = ColumnarEntryPointRealization.TryEmit(
                isExecutable,
                funcs,
                methods,
                asyncWrappedByFunc,
                paramTypesByFunc,
                asyncInnerByFunc,
                programType,
                structRegistry,
                typeResolutionCatalog,
                out selected
            )
        } catch caught: Exception {
            error = caught
        }
        return new EntryPointRealizationControlsOutcome(succeeded, selected, error)
    }

    // FieldInfo.SetValue supplies only the emitted fixture to a source-typed field. Every actual
    // realization argument is then direct and exact, including the caller-visible out local in Invoke.
    static func InvokeObserved(
        isExecutable: bool,
        frame: EntryPointRealizationControlsObservedFunctionsFrame,
        methods: MethodBuilder[],
        asyncWrappedByFunc: Type[],
        paramTypesByFunc: Dictionary<string, Type>[],
        asyncInnerByFunc: Type[],
        programType: TypeBuilder,
        structRegistry: Dictionary<string, ColumnarStructDef>,
        typeResolutionCatalog: ColumnarSemanticTypeResolutionCatalog
    ): EntryPointRealizationControlsOutcome {
        return EntryPointRealizationControlsTypedInvoker.Invoke(
            isExecutable,
            frame.Rows,
            methods,
            asyncWrappedByFunc,
            paramTypesByFunc,
            asyncInnerByFunc,
            programType,
            structRegistry,
            typeResolutionCatalog
        )
    }
}

func EntryPointRealizationControlsSetObject(values: object[], index: int, value: object) {
    values[index] = value
}

func EntryPointRealizationControlsObservedFrame(
    observed: object
): EntryPointRealizationControlsObservedFunctionsFrame {
    frame := new EntryPointRealizationControlsObservedFunctionsFrame()
    field := typeof(EntryPointRealizationControlsObservedFunctionsFrame).GetField("Rows")
    if field == null {
        throw new InvalidOperationException("The observed-functions frame did not retain Rows.")
    }
    field.SetValue(frame, observed)
    return frame
}

func EntryPointRealizationControlsEmptyBody(): ColumnarNodeTable {
    zero := new int[](1)
    return new ColumnarNodeTable(
        zero,
        zero,
        zero,
        zero,
        zero,
        new int[](0),
        zero,
        zero
    )
}

func EntryPointRealizationControlsFunction(name: string): ColumnarFunctionInput {
    return new ColumnarFunctionInput(
        name,
        "void",
        new string[](0),
        new string[](0),
        EntryPointRealizationControlsEmptyBody(),
        0,
        true
    )
}

func EntryPointRealizationControlsEmptyFunctions(): IReadOnlyList<ColumnarFunctionInput> {
    values := new List<ColumnarFunctionInput>()
    return values
}

func EntryPointRealizationControlsSingleFunctions(name: string): IReadOnlyList<ColumnarFunctionInput> {
    values := new List<ColumnarFunctionInput>()
    values.Add(EntryPointRealizationControlsFunction(name))
    return values
}

func EntryPointRealizationControlsEmptyCatalog(): ColumnarSemanticTypeResolutionCatalog {
    sources := new string[](1)
    sourceNames := new string[](1)
    sources[0] = "namespace EntryPointRealizationControls\n"
    sourceNames[0] = "entry-point-realization-controls/source.nl"
    return new ColumnarSemanticTypeResolutionCatalog(
        ExactTypeProgram(sources, sourceNames),
        SemanticEmptyEnums(),
        SemanticEmptyStructs(),
        SemanticEmptyUnions()
    )
}

func EntryPointRealizationControlsVoidType(): Type {
    result := Type.GetType("System.Void")
    if result == null {
        throw new InvalidOperationException("System.Void was not found.")
    }
    return result
}

func EntryPointRealizationControlsEmptyStructRegistry(): Dictionary<string, ColumnarStructDef> {
    return new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
}

func EntryPointRealizationControlsEmptyParameterMaps(): Dictionary<string, Type>[] {
    return new Dictionary<string, Type>[](0)
}

func EntryPointRealizationControlsSingleEmptyParameterMap(): Dictionary<string, Type>[] {
    maps := new Dictionary<string, Type>[](1)
    maps[0] = new Dictionary<string, Type>(StringComparer.Ordinal)
    return maps
}

func EntryPointRealizationControlsSingleNonemptyParameterMap(): Dictionary<string, Type>[] {
    maps := EntryPointRealizationControlsSingleEmptyParameterMap()
    maps[0]["value"] = typeof(int)
    return maps
}

func EntryPointRealizationControlsSingleMethod(method: MethodBuilder): MethodBuilder[] {
    values := new MethodBuilder[](1)
    values[0] = method
    return values
}

func EntryPointRealizationControlsTwoMethods(first: MethodBuilder, second: MethodBuilder): MethodBuilder[] {
    values := new MethodBuilder[](2)
    values[0] = first
    values[1] = second
    return values
}

func EntryPointRealizationControlsSingleWrapped(value: Type): Type[] {
    values := new Type[](1)
    values[0] = value
    return values
}

func EntryPointRealizationControlsTwoNoWrapped(): Type[] {
    return new Type[](2)
}

func EntryPointRealizationControlsSingleInner(value: Type): Type[] {
    values := new Type[](1)
    values[0] = value
    return values
}

func EntryPointRealizationControlsTwoInner(): Type[] {
    values := new Type[](2)
    voidType := EntryPointRealizationControlsVoidType()
    values[0] = voidType
    values[1] = voidType
    return values
}

func EntryPointRealizationControlsStaticMethod(
    owner: TypeBuilder,
    name: string,
    parameterTypes: Type[]
): ColumnarStaticMethodDef {
    builder := owner.DefineMethod(
        name,
        (MethodAttributes)22,
        EntryPointRealizationControlsVoidType(),
        parameterTypes
    )
    return new ColumnarStaticMethodDef(
        builder,
        parameterTypes,
        new int[](0),
        EntryPointRealizationControlsVoidType()
    )
}

func EntryPointRealizationControlsDefinition(
    owner: TypeBuilder,
    declaredName: string
): ColumnarStructDef {
    return new ColumnarStructDef(
        owner,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        declaredName
    )
}

func EntryPointRealizationControlsRequiredRetainedMethod(
    owner: TypeBuilder,
    name: string
): MethodBuilder {
    ownerRuntimeType := IteratorRealizationControlActualRuntimeType(owner)
    assert ownerRuntimeType.get_FullName() == "System.Reflection.Emit.TypeBuilderImpl"
    flags := BindingFlags.Instance | BindingFlags.NonPublic
    definitionsField := ownerRuntimeType.GetField("_methodDefinitions", flags)
    if definitionsField == null {
        throw new InvalidOperationException("The persisted owner did not retain its method inventory.")
    }
    definitionsObject := definitionsField.GetValue(owner)
    definitions := definitionsObject as IList
    if definitions == null {
        throw new InvalidOperationException("The persisted owner method inventory was not an IList.")
    }
    index := 0
    while index < definitions.Count {
        candidateObject := definitions[index]
        candidate := candidateObject as MethodBuilder
        if candidate != null && candidate.get_Name() == name {
            return candidate
        }
        index += 1
    }
    throw new InvalidOperationException("The persisted owner did not retain method '" + name + "'.")
}

func EntryPointRealizationControlsMethodPrivateField(
    method: MethodBuilder,
    name: string
): object? {
    runtimeType := IteratorRealizationControlActualRuntimeType(method)
    assert runtimeType.get_FullName() == "System.Reflection.Emit.MethodBuilderImpl"
    flags := BindingFlags.Instance | BindingFlags.NonPublic
    field := runtimeType.GetField(name, flags)
    if field == null {
        throw new InvalidOperationException("The persisted method did not expose its expected private field.")
    }
    return field.GetValue(method)
}

func EntryPointRealizationControlsRequiredErrorType(error: Exception?): Type {
    if error == null {
        throw new InvalidOperationException("Expected an entry-point realization error.")
    }
    errorObject: object = error
    return IteratorRealizationControlActualRuntimeType(errorObject)
}

func EntryPointRealizationControlsReflectedArrayLength(value: object): int {
    runtimeType := IteratorRealizationControlActualRuntimeType(value)
    lengthProperty := runtimeType.GetProperty("Length")
    if lengthProperty == null {
        throw new InvalidOperationException("The retained method parameter value was not an array.")
    }
    lengthValue := lengthProperty.GetValue(value)
    if lengthValue == null {
        throw new InvalidOperationException("The retained method parameter array had no length.")
    }
    return Convert.ToInt32(lengthValue)
}

// The two indexed walks retain lowercase priority even when the earlier row is uppercase.  Every
// Count is observable: after a lowercase hit the lower loop still reads Count before the hit guard,
// and the upper loop makes its own first Count read before observing that hit.
test "entry point realization keeps lowercase priority and reads its list live" {
    uppercaseOwner := IteratorRealizationControlPersistedHost("EntryPointRealizationUppercase")
    lowercaseOwner := IteratorRealizationControlPersistedHost("EntryPointRealizationLowercase")
    uppercaseMethod := uppercaseOwner.DefineMethod(
        "Main",
        (MethodAttributes)22,
        EntryPointRealizationControlsVoidType(),
        System.Type.EmptyTypes
    )
    lowercaseMethod := lowercaseOwner.DefineMethod(
        "main",
        (MethodAttributes)22,
        EntryPointRealizationControlsVoidType(),
        System.Type.EmptyTypes
    )
    rows := new object[](2)
    EntryPointRealizationControlsSetObject(rows, 0, EntryPointRealizationControlsFunction("Main"))
    EntryPointRealizationControlsSetObject(rows, 1, EntryPointRealizationControlsFunction("main"))
    state := new EntryPointRealizationControlsFunctionRowsState(rows)
    observed := EntryPointRealizationControlsObservedFunctions(
        "EntryPointRealizationPriorityRows",
        state
    )
    outcome := EntryPointRealizationControlsTypedInvoker.InvokeObserved(
        true,
        EntryPointRealizationControlsObservedFrame(observed),
        EntryPointRealizationControlsTwoMethods(uppercaseMethod, lowercaseMethod),
        EntryPointRealizationControlsTwoNoWrapped(),
        new Dictionary<string, Type>[](2),
        EntryPointRealizationControlsTwoInner(),
        IteratorRealizationControlPersistedHost("EntryPointRealizationPriorityProgram"),
        EntryPointRealizationControlsEmptyStructRegistry(),
        EntryPointRealizationControlsEmptyCatalog()
    )
    assert outcome.Succeeded
    assert outcome.Error == null
    assert Object.ReferenceEquals(outcome.EntryPoint, lowercaseMethod)
    assert state.Trace.Count == 6
    assert state.Trace[0] == 10
    assert state.Trace[1] == 100
    assert state.Trace[2] == 10
    assert state.Trace[3] == 101
    assert state.Trace[4] == 10
    assert state.Trace[5] == 10
    assert state.MoveCalls == 0

    // The fourth Count is the upper-case loop's first condition.  It happens before selection assigns
    // the caller-visible out slot, so its exact exception leaves that slot null.
    throwingState := new EntryPointRealizationControlsFunctionRowsState(rows, 4)
    throwingObserved := EntryPointRealizationControlsObservedFunctions(
        "EntryPointRealizationPriorityThrowRows",
        throwingState
    )
    throwing := EntryPointRealizationControlsTypedInvoker.InvokeObserved(
        true,
        EntryPointRealizationControlsObservedFrame(throwingObserved),
        EntryPointRealizationControlsTwoMethods(uppercaseMethod, lowercaseMethod),
        EntryPointRealizationControlsTwoNoWrapped(),
        new Dictionary<string, Type>[](2),
        EntryPointRealizationControlsTwoInner(),
        IteratorRealizationControlPersistedHost("EntryPointRealizationPriorityThrowProgram"),
        EntryPointRealizationControlsEmptyStructRegistry(),
        EntryPointRealizationControlsEmptyCatalog()
    )
    assert !throwing.Succeeded
    assert throwing.EntryPoint == null
    assert throwing.Error != null
    assert throwing.Error.Message == "entry-point function-list Count was read"
    assert throwingState.Trace.Count == 6
    assert throwingState.Trace[5] == 10
    assert throwingState.MoveCalls == 0

    // A hostile list remains completely unread when the assembly is not executable.
    noReadState := new EntryPointRealizationControlsFunctionRowsState(rows, 1)
    noReadObserved := EntryPointRealizationControlsObservedFunctions(
        "EntryPointRealizationNoReadRows",
        noReadState
    )
    notExecutable := EntryPointRealizationControlsTypedInvoker.InvokeObserved(
        false,
        EntryPointRealizationControlsObservedFrame(noReadObserved),
        new MethodBuilder[](0),
        new Type[](0),
        EntryPointRealizationControlsEmptyParameterMaps(),
        new Type[](0),
        IteratorRealizationControlPersistedHost("EntryPointRealizationNoReadProgram"),
        EntryPointRealizationControlsEmptyStructRegistry(),
        EntryPointRealizationControlsEmptyCatalog()
    )
    assert notExecutable.Succeeded
    assert notExecutable.EntryPoint == null
    assert notExecutable.Error == null
    assert noReadState.Trace.Count == 0
    assert noReadState.MoveCalls == 0
}

// Fallback intentionally receives an ordinary Dictionary.  Its concrete Values enumerator and
// finally cleanup are inspected in the compiled owner; no artificial enumerable replaces that BCL
// path in this control.
test "entry point realization preserves static fallback first-hit and null facts" {
    noFunctions := EntryPointRealizationControlsEmptyFunctions()
    noMethods := new MethodBuilder[](0)
    noWrapped := new Type[](0)
    noMaps := EntryPointRealizationControlsEmptyParameterMaps()
    noInner := new Type[](0)

    // A nonqualifying first row does not stop the original insertion-ordered Values walk; the valid
    // second row is selected by its real static MethodBuilder identity.
    firstOwner := IteratorRealizationControlPersistedHost("EntryPointRealizationStaticFirst")
    secondOwner := IteratorRealizationControlPersistedHost("EntryPointRealizationStaticSecond")
    firstDef := EntryPointRealizationControlsDefinition(firstOwner, "StaticFirst")
    secondDef := EntryPointRealizationControlsDefinition(secondOwner, "StaticSecond")
    oneParameter := new Type[](1)
    oneParameter[0] = typeof(int)
    firstMains := new List<ColumnarStaticMethodDef>()
    firstMains.Add(EntryPointRealizationControlsStaticMethod(firstOwner, "Main", oneParameter))
    firstDef.StaticMethods["Main"] = firstMains
    selectedMains := new List<ColumnarStaticMethodDef>()
    selected := EntryPointRealizationControlsStaticMethod(secondOwner, "Main", System.Type.EmptyTypes)
    selectedMains.Add(selected)
    secondDef.StaticMethods["Main"] = selectedMains
    ordered := EntryPointRealizationControlsEmptyStructRegistry()
    ordered["first"] = firstDef
    ordered["second"] = secondDef
    selectedOutcome := EntryPointRealizationControlsTypedInvoker.Invoke(
        true,
        noFunctions,
        noMethods,
        noWrapped,
        noMaps,
        noInner,
        IteratorRealizationControlPersistedHost("EntryPointRealizationStaticProgram"),
        ordered,
        EntryPointRealizationControlsEmptyCatalog()
    )
    assert selectedOutcome.Succeeded
    assert selectedOutcome.Error == null
    assert Object.ReferenceEquals(selectedOutcome.EntryPoint, selected.Builder)

    // A first structurally eligible row with a null builder still breaks.  The later valid row must
    // not rescue it, and the final no-entry-point result is bare false with the out slot still null.
    nullBuilderOwner := IteratorRealizationControlPersistedHost("EntryPointRealizationNullBuilder")
    laterOwner := IteratorRealizationControlPersistedHost("EntryPointRealizationLaterBuilder")
    nullBuilderDef := EntryPointRealizationControlsDefinition(nullBuilderOwner, "NullBuilder")
    laterDef := EntryPointRealizationControlsDefinition(laterOwner, "LaterBuilder")
    nullBuilderMains := new List<ColumnarStaticMethodDef>()
    nullBuilderFact := EntryPointRealizationControlsStaticMethod(
        nullBuilderOwner,
        "Main",
        System.Type.EmptyTypes
    )
    nullBuilderFact.Builder = null
    nullBuilderMains.Add(nullBuilderFact)
    nullBuilderDef.StaticMethods["Main"] = nullBuilderMains
    laterMains := new List<ColumnarStaticMethodDef>()
    laterMains.Add(EntryPointRealizationControlsStaticMethod(laterOwner, "Main", System.Type.EmptyTypes))
    laterDef.StaticMethods["Main"] = laterMains
    nullBuilderRows := EntryPointRealizationControlsEmptyStructRegistry()
    nullBuilderRows["null-builder"] = nullBuilderDef
    nullBuilderRows["later"] = laterDef
    nullBuilderOutcome := EntryPointRealizationControlsTypedInvoker.Invoke(
        true,
        noFunctions,
        noMethods,
        noWrapped,
        noMaps,
        noInner,
        IteratorRealizationControlPersistedHost("EntryPointRealizationNullBuilderProgram"),
        nullBuilderRows,
        EntryPointRealizationControlsEmptyCatalog()
    )
    assert !nullBuilderOutcome.Succeeded
    assert nullBuilderOutcome.Error == null
    assert nullBuilderOutcome.EntryPoint == null

    // A present Main key whose actual List value is null faults inside the concrete walk.  The owner
    // finally still disposes its concrete dictionary enumerator during unwinding; that is verified by
    // the direct addressed-finally IL review, while this runtime assertion pins the true null path.
    nullListOwner := IteratorRealizationControlPersistedHost("EntryPointRealizationNullList")
    nullListDef := EntryPointRealizationControlsDefinition(nullListOwner, "NullList")
    nullList: List<ColumnarStaticMethodDef> = null
    nullListDef.StaticMethods["Main"] = nullList
    nullListRows := EntryPointRealizationControlsEmptyStructRegistry()
    nullListRows["null-list"] = nullListDef
    nullListOutcome := EntryPointRealizationControlsTypedInvoker.Invoke(
        true,
        noFunctions,
        noMethods,
        noWrapped,
        noMaps,
        noInner,
        IteratorRealizationControlPersistedHost("EntryPointRealizationNullListProgram"),
        nullListRows,
        EntryPointRealizationControlsEmptyCatalog()
    )
    expectedNull := new NullReferenceException()
    assert !nullListOutcome.Succeeded
    assert nullListOutcome.EntryPoint == null
    assert nullListOutcome.Error != null
    assert EntryPointRealizationControlsRequiredErrorType(nullListOutcome.Error) == typeof(NullReferenceException)
    assert nullListOutcome.Error.get_Message() == expectedNull.Message
}

// Selection is published before an async main's unsupported parameter map is refused.  A later
// planner failure likewise leaves the selected source method published, but the newly declared
// wrapper has not acquired an ILGenerator because BuildWrapperPlan failed first.
test "entry point realization preserves selected output across async refusal and plan failure" {
    program := IteratorRealizationControlPersistedHost("EntryPointRealizationAsyncRefusalProgram")
    selected := program.DefineMethod(
        "main",
        (MethodAttributes)22,
        typeof(Task),
        System.Type.EmptyTypes
    )
    asyncRefusal := EntryPointRealizationControlsTypedInvoker.Invoke(
        true,
        EntryPointRealizationControlsSingleFunctions("main"),
        EntryPointRealizationControlsSingleMethod(selected),
        EntryPointRealizationControlsSingleWrapped(typeof(Task)),
        EntryPointRealizationControlsSingleNonemptyParameterMap(),
        EntryPointRealizationControlsSingleInner(EntryPointRealizationControlsVoidType()),
        program,
        EntryPointRealizationControlsEmptyStructRegistry(),
        EntryPointRealizationControlsEmptyCatalog()
    )
    assert !asyncRefusal.Succeeded
    assert asyncRefusal.Error == null
    assert Object.ReferenceEquals(asyncRefusal.EntryPoint, selected)

    failingProgram := IteratorRealizationControlPersistedHost("EntryPointRealizationPlanFailureProgram")
    failingSelected := failingProgram.DefineMethod(
        "main",
        (MethodAttributes)22,
        typeof(int),
        System.Type.EmptyTypes
    )
    planFailure := EntryPointRealizationControlsTypedInvoker.Invoke(
        true,
        EntryPointRealizationControlsSingleFunctions("main"),
        EntryPointRealizationControlsSingleMethod(failingSelected),
        EntryPointRealizationControlsSingleWrapped(typeof(int)),
        EntryPointRealizationControlsSingleEmptyParameterMap(),
        EntryPointRealizationControlsSingleInner(EntryPointRealizationControlsVoidType()),
        failingProgram,
        EntryPointRealizationControlsEmptyStructRegistry(),
        EntryPointRealizationControlsEmptyCatalog()
    )
    assert !planFailure.Succeeded
    assert Object.ReferenceEquals(planFailure.EntryPoint, failingSelected)
    assert planFailure.Error != null
    assert EntryPointRealizationControlsRequiredErrorType(planFailure.Error) == typeof(InvalidOperationException)

    wrapper := EntryPointRealizationControlsRequiredRetainedMethod(
        failingProgram,
        "__NSharpEntryPoint"
    )
    assert EntryPointRealizationControlsMethodPrivateField(wrapper, "_ilGenerator") == null
    parameterTypes := EntryPointRealizationControlsMethodPrivateField(wrapper, "_parameterTypes")
    assert parameterTypes != null
    assert EntryPointRealizationControlsReflectedArrayLength(parameterTypes) == 0
}

// A valid wrapper plan is constructed before GetILGenerator.  A deliberately foreign selected
// MethodBuilder reaches executor pair validation only after the wrapper has acquired its real
// MethodBuilderImpl IL generator; the wrapper is not published as the final entry point on failure.
test "entry point realization acquires wrapper IL before later executor validation" {
    program := IteratorRealizationControlPersistedHost("EntryPointRealizationValidationProgram")
    foreignOwner := IteratorRealizationControlPersistedHost("EntryPointRealizationValidationForeign")
    foreignSelected := foreignOwner.DefineMethod(
        "main",
        (MethodAttributes)22,
        typeof(Task),
        System.Type.EmptyTypes
    )
    validationFailure := EntryPointRealizationControlsTypedInvoker.Invoke(
        true,
        EntryPointRealizationControlsSingleFunctions("main"),
        EntryPointRealizationControlsSingleMethod(foreignSelected),
        EntryPointRealizationControlsSingleWrapped(typeof(Task)),
        EntryPointRealizationControlsSingleEmptyParameterMap(),
        EntryPointRealizationControlsSingleInner(EntryPointRealizationControlsVoidType()),
        program,
        EntryPointRealizationControlsEmptyStructRegistry(),
        EntryPointRealizationControlsEmptyCatalog()
    )
    assert !validationFailure.Succeeded
    assert Object.ReferenceEquals(validationFailure.EntryPoint, foreignSelected)
    assert validationFailure.Error != null
    assert EntryPointRealizationControlsRequiredErrorType(validationFailure.Error) == typeof(InvalidOperationException)

    wrapper := EntryPointRealizationControlsRequiredRetainedMethod(
        program,
        "__NSharpEntryPoint"
    )
    assert EntryPointRealizationControlsMethodPrivateField(wrapper, "_ilGenerator") != null
}

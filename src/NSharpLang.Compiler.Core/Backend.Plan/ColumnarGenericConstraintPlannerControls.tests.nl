namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Independent call-site controls for the moved lookup policy.  The planner owns the query; these
// fixtures deliberately use real CLR generic parameters from different type owners so weak legacy
// name-and-ordinal matching cannot be mistaken for CLR Type identity.
class ConstraintControlsFirst<T> {
}

class ConstraintControlsSecond<T> {
}

class ConstraintControlsThird<T> {
}

class ConstraintControlsDifferentName<U> {
}

// A deliberately non-CLR comparer demonstrates that the initial lookup stays the supplied map's
// TryGetValue, rather than being replaced with Type equality or weak fallback enumeration.
class ConstraintControlsAllTypeComparer: IEqualityComparer<Type> {
    func Equals(left: Type?, right: Type?): bool {
        return true
    }

    func GetHashCode(value: Type): int {
        return 0
    }
}

// This comparer permits setup, then fails only when the planner performs its exact map lookup.  It
// distinguishes an uncaught map operation from a later weak scan or constraint reflection fallback.
class ConstraintControlsDelayedThrowComparer: IEqualityComparer<Type> {
    ThrowOnLookup: bool

    constructor() {
        ThrowOnLookup = false
    }

    func Equals(left: Type?, right: Type?): bool {
        return true
    }

    func GetHashCode(value: Type): int {
        if ThrowOnLookup {
            throw new InvalidOperationException("constraint comparer lookup failed")
        }
        return 0
    }
}

func ConstraintControlsParameter(closedOwner: Type): Type {
    openOwner := closedOwner.GetGenericTypeDefinition()
    parameters := openOwner.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException("Expected one generic type parameter.")
    }
    parameter := parameters[0]
    if !parameter.get_IsGenericParameter() || !parameter.get_IsGenericTypeParameter() || parameter.get_IsGenericMethodParameter() || parameter.get_GenericParameterPosition() != 0 {
        throw new InvalidOperationException("The control type did not expose its expected generic parameter.")
    }
    return parameter
}

func ConstraintControlsOneType(value: Type): Type[] {
    answer := new Type[](1)
    answer[0] = value
    return answer
}

class ConstraintControlsWeakOutcome {
    Result: bool
    Constraints: Type[]?
    ErrorMessage: string?

    constructor(constraints: Type[]?) {
        Result = false
        Constraints = constraints
        ErrorMessage = null
    }
}

// The runner is typed at the actual IEnumerable<KeyValuePair<Type, Type[]>> boundary.  The tests
// invoke it through reflection only to hand it a baked protocol fixture; the planner call and its
// out local are compiled directly in N#.
class ConstraintControlsWeakInvoker {
    static func Find(
        entries: IEnumerable<KeyValuePair<Type, Type[]>>,
        requested: Type,
        outcome: ConstraintControlsWeakOutcome
    ): bool {
        constraints := outcome.Constraints
        try {
            outcome.Result = ColumnarGenericConstraintPlanner.TryFindWeakCallConstraints(
                entries,
                requested,
                out constraints
            )
        } catch error: InvalidOperationException {
            outcome.ErrorMessage = error.Message
        }
        outcome.Constraints = constraints
        return true
    }
}

func ConstraintControlsRequiredGetter(owner: Type, propertyName: string): MethodInfo {
    property := owner.GetProperty(propertyName)
    if property == null {
        throw new InvalidOperationException("Missing property '" + propertyName + "'.")
    }
    getter := property.GetGetMethod()
    if getter == null {
        throw new InvalidOperationException("Missing getter '" + propertyName + "'.")
    }
    return getter
}

func ConstraintControlsDefineField(owner: TypeBuilder, name: string, fieldType: Type): FieldBuilder {
    parameterTypes := new Type[](3)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(Type)
    parameterTypes[2] = typeof(FieldAttributes)
    defineField := ExecutorRequiredMethod(typeof(TypeBuilder), "DefineField", parameterTypes)
    arguments := new object[](3)
    ExecutorSetObject(arguments, 0, name)
    ExecutorSetObject(arguments, 1, fieldType)
    ExecutorSetObject(arguments, 2, (FieldAttributes)6)
    value := TypeOfRequiredInvocation(defineField, owner, arguments)
    field := value as FieldBuilder
    if field == null {
        throw new InvalidOperationException("The constraint protocol fixture field was not defined.")
    }
    return field
}

func ConstraintControlsReturnThis(method: MethodBuilder) {
    il := TypeOfMethodBuilderIL(method)
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Ret)
}

func ConstraintControlsIncrementField(il: ILGenerator, field: FieldBuilder) {
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Dup)
    il.Emit(OpCodes.Ldfld, field)
    il.Emit(OpCodes.Ldc_I4_1)
    il.Emit(OpCodes.Add)
    il.Emit(OpCodes.Stfld, field)
}

func ConstraintControlsEmitTrace(il: ILGenerator, traceField: FieldBuilder, code: int) {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int)
    add := ExecutorRequiredMethod(typeof(List<int>), "Add", parameterTypes)
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Ldfld, traceField)
    il.Emit(OpCodes.Ldc_I4, code)
    il.Emit(OpCodes.Callvirt, add)
}

func ConstraintControlsEmitInvalidOperation(il: ILGenerator, message: string) {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    constructor := ExecutorRequiredConstructor(typeof(InvalidOperationException), parameterTypes)
    il.Emit(OpCodes.Ldstr, message)
    il.Emit(OpCodes.Newobj, constructor)
    il.Emit(OpCodes.Throw)
}

func ConstraintControlsPairType(): Type {
    definition := Type.GetType("System.Collections.Generic.KeyValuePair`2")
    if definition == null {
        throw new InvalidOperationException("KeyValuePair<TK, TV> was not found.")
    }
    arguments := new Type[](2)
    arguments[0] = typeof(Type)
    arguments[1] = typeof(Type[])
    return definition.MakeGenericType(arguments)
}

// Reflection constructs the boxed BCL KeyValuePair placed in the emitted field.  The N# helper under
// test reads that field through IEnumerator<KeyValuePair<Type, Type[]>>.Current; source never builds
// a synthetic pair or substitutes a different generic Current shape.
func ConstraintControlsPairObject(key: Type, value: Type[]): object {
    pairType := ConstraintControlsPairType()
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(Type)
    parameterTypes[1] = typeof(Type[])
    constructor := ExecutorRequiredConstructor(pairType, parameterTypes)
    arguments := new object[](2)
    ExecutorSetObject(arguments, 0, key)
    ExecutorSetObject(arguments, 1, value)
    pair := constructor.Invoke(arguments)
    if pair == null {
        throw new InvalidOperationException("The constraint protocol pair was null.")
    }
    return pair
}

// mode 0: matching MoveNext/normal Dispose; 1: exhausted; 2: MoveNext throws; 3: Dispose throws;
// 4: generic GetEnumerator throws before the planner enters its try/finally; 5: exhausted MoveNext then Dispose throws.
func ConstraintControlsWeakRows(
    typeName: string,
    mode: int,
    key: Type,
    value: Type[],
    trace: List<int>?
): object {
    noParameters := new Type[](0)
    elementArguments := new Type[](1)
    pairType := ConstraintControlsPairType()
    elementArguments[0] = pairType
    genericEnumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    genericEnumeratorDefinition := typeof(IEnumerator<int>).GetGenericTypeDefinition()
    genericEnumerable := genericEnumerableDefinition.MakeGenericType(elementArguments)
    genericEnumerator := genericEnumeratorDefinition.MakeGenericType(elementArguments)
    nongenericEnumerable := typeof(System.Collections.IEnumerable)
    nongenericEnumerator := typeof(System.Collections.IEnumerator)
    disposable := typeof(IDisposable)

    owner := TypeOfCreateBuilder(
        typeName,
        "ColumnarGenericConstraintPlanner.Controls." + typeName,
        0
    )
    owner.AddInterfaceImplementation(genericEnumerable)
    owner.AddInterfaceImplementation(genericEnumerator)
    owner.AddInterfaceImplementation(nongenericEnumerable)
    owner.AddInterfaceImplementation(nongenericEnumerator)
    owner.AddInterfaceImplementation(disposable)
    pairField := ConstraintControlsDefineField(owner, "Pair", pairType)
    acquireCount := ConstraintControlsDefineField(owner, "AcquireCount", typeof(int))
    moveCount := ConstraintControlsDefineField(owner, "MoveCount", typeof(int))
    currentCount := ConstraintControlsDefineField(owner, "CurrentCount", typeof(int))
    disposeCount := ConstraintControlsDefineField(owner, "DisposeCount", typeof(int))
    traceField := ConstraintControlsDefineField(owner, "Trace", typeof(List<int>))

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

    genericGetEnumeratorTarget := ExecutorRequiredMethod(genericEnumerable, "GetEnumerator", noParameters)
    genericGetEnumerator := owner.DefineMethod(
        "GenericGetEnumerator",
        (MethodAttributes)481,
        genericEnumerator,
        noParameters
    )
    genericGetEnumeratorIl := TypeOfMethodBuilderIL(genericGetEnumerator)
    ConstraintControlsIncrementField(genericGetEnumeratorIl, acquireCount)
    if mode == 4 {
        ConstraintControlsEmitInvalidOperation(genericGetEnumeratorIl, "weak entry acquisition failed")
    } else {
        genericGetEnumeratorIl.Emit(OpCodes.Ldarg_0)
        genericGetEnumeratorIl.Emit(OpCodes.Ret)
    }
    owner.DefineMethodOverride(genericGetEnumerator, genericGetEnumeratorTarget)

    nongenericGetEnumeratorTarget := ExecutorRequiredMethod(nongenericEnumerable, "GetEnumerator", noParameters)
    nongenericGetEnumerator := owner.DefineMethod(
        "NongenericGetEnumerator",
        (MethodAttributes)481,
        nongenericEnumerator,
        noParameters
    )
    ConstraintControlsReturnThis(nongenericGetEnumerator)
    owner.DefineMethodOverride(nongenericGetEnumerator, nongenericGetEnumeratorTarget)

    genericCurrentTarget := ConstraintControlsRequiredGetter(genericEnumerator, "Current")
    genericCurrent := owner.DefineMethod(
        "GenericCurrent",
        (MethodAttributes)481,
        pairType,
        noParameters
    )
    genericCurrentIl := TypeOfMethodBuilderIL(genericCurrent)
    ConstraintControlsIncrementField(genericCurrentIl, currentCount)
    genericCurrentIl.Emit(OpCodes.Ldarg_0)
    genericCurrentIl.Emit(OpCodes.Ldfld, pairField)
    genericCurrentIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(genericCurrent, genericCurrentTarget)

    nongenericCurrentTarget := ConstraintControlsRequiredGetter(nongenericEnumerator, "Current")
    nongenericCurrent := owner.DefineMethod(
        "NongenericCurrent",
        (MethodAttributes)481,
        typeof(object),
        noParameters
    )
    nongenericCurrentIl := TypeOfMethodBuilderIL(nongenericCurrent)
    nongenericCurrentIl.Emit(OpCodes.Ldnull)
    nongenericCurrentIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(nongenericCurrent, nongenericCurrentTarget)

    moveNextTarget := ExecutorRequiredMethod(nongenericEnumerator, "MoveNext", noParameters)
    moveNext := owner.DefineMethod(
        "MoveNext",
        (MethodAttributes)481,
        typeof(bool),
        noParameters
    )
    moveNextIl := TypeOfMethodBuilderIL(moveNext)
    ConstraintControlsIncrementField(moveNextIl, moveCount)
    if mode == 2 {
        ConstraintControlsEmitInvalidOperation(moveNextIl, "weak entry movement failed")
    } else if mode == 1 || mode == 5 {
        moveNextIl.Emit(OpCodes.Ldc_I4_0)
        moveNextIl.Emit(OpCodes.Ret)
    } else {
        moveNextIl.Emit(OpCodes.Ldc_I4_1)
        moveNextIl.Emit(OpCodes.Ret)
    }
    owner.DefineMethodOverride(moveNext, moveNextTarget)

    resetTarget := ExecutorRequiredMethod(nongenericEnumerator, "Reset", noParameters)
    reset := owner.DefineMethod(
        "Reset",
        (MethodAttributes)481,
        ExecutorVoidType(),
        noParameters
    )
    resetIl := TypeOfMethodBuilderIL(reset)
    resetIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(reset, resetTarget)

    disposeTarget := ExecutorRequiredMethod(disposable, "Dispose", noParameters)
    dispose := owner.DefineMethod(
        "Dispose",
        (MethodAttributes)481,
        ExecutorVoidType(),
        noParameters
    )
    disposeIl := TypeOfMethodBuilderIL(dispose)
    ConstraintControlsIncrementField(disposeIl, disposeCount)
    if trace != null {
        ConstraintControlsEmitTrace(disposeIl, traceField, 91)
    }
    if mode == 3 || mode == 5 {
        ConstraintControlsEmitInvalidOperation(disposeIl, "weak entry disposal failed")
    } else {
        disposeIl.Emit(OpCodes.Ret)
    }
    owner.DefineMethodOverride(dispose, disposeTarget)

    baked := IdentityBake(owner)
    instanceConstructor := ExecutorRequiredConstructor(baked, noParameters)
    instance := instanceConstructor.Invoke(noParameters)
    if instance == null {
        throw new InvalidOperationException("The constraint protocol fixture was not constructed.")
    }
    bakedPairField := baked.GetField("Pair")
    if bakedPairField == null {
        throw new InvalidOperationException("The constraint protocol fixture lost its Pair field.")
    }
    bakedPairField.SetValue(instance, ConstraintControlsPairObject(key, value))
    if trace != null {
        bakedTraceField := baked.GetField("Trace")
        if bakedTraceField == null {
            throw new InvalidOperationException("The constraint protocol fixture lost its Trace field.")
        }
        bakedTraceField.SetValue(instance, trace)
    }
    return instance
}

func ConstraintControlsCounter(instance: object, fieldName: string): int {
    field := instance.GetType().GetField(fieldName)
    if field == null {
        throw new InvalidOperationException("The constraint protocol counter was not found: " + fieldName)
    }
    return Convert.ToInt32(field.GetValue(instance))
}

func ConstraintControlsInvokeWeak(
    entries: object,
    requested: Type,
    outcome: ConstraintControlsWeakOutcome
): bool {
    method := typeof(ConstraintControlsWeakInvoker).GetMethod("Find")
    if method == null {
        throw new InvalidOperationException("The typed weak lookup runner was not found.")
    }
    arguments := new object[](3)
    ExecutorSetObject(arguments, 0, entries)
    ExecutorSetObject(arguments, 1, requested)
    ExecutorSetObject(arguments, 2, outcome)
    value := TypeOfRequiredInvocation(method, null, arguments)
    return Convert.ToBoolean(value)
}

class ConstraintControlsResolveInvoker {
    static func Resolve(
        map: IReadOnlyDictionary<Type, Type[]>,
        requested: Type,
        outcome: ConstraintControlsWeakOutcome
    ): bool {
        try {
            outcome.Constraints = ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, requested)
            outcome.Result = true
        } catch error: InvalidOperationException {
            outcome.ErrorMessage = error.Message
        }
        return true
    }
}

func ConstraintControlsReadOnlyDictionaryType(): Type {
    definition := Type.GetType("System.Collections.Generic.IReadOnlyDictionary`2")
    if definition == null {
        throw new InvalidOperationException("IReadOnlyDictionary<TKey, TValue> was not found.")
    }
    arguments := new Type[](2)
    arguments[0] = typeof(Type)
    arguments[1] = typeof(Type[])
    return definition.MakeGenericType(arguments)
}

class ConstraintControlsHostileMapState {
    Key: Type
    Value: Type[]?
    Exact: bool
    InitialOut: Type[]?
    LookupCount: int
    AcquireCount: int

    constructor(key: Type, value: Type[]?, exact: bool) {
        Key = key
        Value = value
        Exact = exact
        InitialOut = null
        LookupCount = 0
        AcquireCount = 0
    }
}

// The emitted interface methods call these small typed routines so the test observes the actual
// planner out local without relying on an unmodelled Stind_Ref opcode in the fixture itself.
class ConstraintControlsHostileMapRuntime {
    static func TryGet(
        state: ConstraintControlsHostileMapState,
        requested: Type,
        out value: Type[]
    ): bool {
        state.LookupCount = state.LookupCount + 1
        state.InitialOut = value
        if state.Exact && state.Key == requested {
            value = state.Value
            return true
        }
        value = null
        return false
    }

    static func Acquired(state: ConstraintControlsHostileMapState) {
        state.AcquireCount = state.AcquireCount + 1
    }
}

func ConstraintControlsHostileMap(
    typeName: string,
    exact: bool,
    key: Type,
    value: Type[]?,
    entries: object?
): object {
    noParameters := new Type[](0)
    pairType := ConstraintControlsPairType()
    readOnlyDictionary := ConstraintControlsReadOnlyDictionaryType()
    genericEnumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    genericEnumerableArguments := new Type[](1)
    genericEnumerableArguments[0] = pairType
    genericEnumerable := genericEnumerableDefinition.MakeGenericType(genericEnumerableArguments)
    genericEnumeratorDefinition := typeof(IEnumerator<int>).GetGenericTypeDefinition()
    genericEnumerator := genericEnumeratorDefinition.MakeGenericType(genericEnumerableArguments)
    genericCollectionDefinition := typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
    genericCollection := genericCollectionDefinition.MakeGenericType(genericEnumerableArguments)

    owner := TypeOfCreateBuilder(
        typeName,
        "ColumnarGenericConstraintPlanner.HostileMap." + typeName,
        0
    )
    owner.AddInterfaceImplementation(readOnlyDictionary)
    owner.AddInterfaceImplementation(genericEnumerable)
    owner.AddInterfaceImplementation(typeof(System.Collections.IEnumerable))
    stateField := ConstraintControlsDefineField(owner, "State", typeof(ConstraintControlsHostileMapState))
    enumeratorField := ConstraintControlsDefineField(owner, "Enumerator", genericEnumerator)

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

    tryGetParameters := new Type[](2)
    tryGetParameters[0] = typeof(Type)
    tryGetParameters[1] = typeof(Type[]).MakeByRefType()
    tryGetTarget := ExecutorRequiredMethod(readOnlyDictionary, "TryGetValue", tryGetParameters)
    runtimeTryGetParameters := new Type[](3)
    runtimeTryGetParameters[0] = typeof(ConstraintControlsHostileMapState)
    runtimeTryGetParameters[1] = typeof(Type)
    runtimeTryGetParameters[2] = typeof(Type[]).MakeByRefType()
    runtimeTryGet := ExecutorRequiredMethod(
        typeof(ConstraintControlsHostileMapRuntime),
        "TryGet",
        runtimeTryGetParameters
    )
    tryGet := owner.DefineMethod(
        "TryGetValue",
        (MethodAttributes)481,
        typeof(bool),
        tryGetParameters
    )
    tryGetIl := TypeOfMethodBuilderIL(tryGet)
    tryGetIl.Emit(OpCodes.Ldarg_0)
    tryGetIl.Emit(OpCodes.Ldfld, stateField)
    tryGetIl.Emit(OpCodes.Ldarg_1)
    tryGetIl.Emit(OpCodes.Ldarg_2)
    tryGetIl.Emit(OpCodes.Call, runtimeTryGet)
    tryGetIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(tryGet, tryGetTarget)

    itemTarget := ConstraintControlsRequiredGetter(readOnlyDictionary, "Item")
    itemParameters := new Type[](1)
    itemParameters[0] = typeof(Type)
    item := owner.DefineMethod(
        "get_Item",
        (MethodAttributes)481,
        typeof(Type[]),
        itemParameters
    )
    itemIl := TypeOfMethodBuilderIL(item)
    ConstraintControlsEmitInvalidOperation(itemIl, "hostile map item was read")
    owner.DefineMethodOverride(item, itemTarget)

    keysTarget := ConstraintControlsRequiredGetter(readOnlyDictionary, "Keys")
    keys := owner.DefineMethod(
        "get_Keys",
        (MethodAttributes)481,
        keysTarget.get_ReturnType(),
        noParameters
    )
    keysIl := TypeOfMethodBuilderIL(keys)
    keysIl.Emit(OpCodes.Ldnull)
    keysIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(keys, keysTarget)

    valuesTarget := ConstraintControlsRequiredGetter(readOnlyDictionary, "Values")
    values := owner.DefineMethod(
        "get_Values",
        (MethodAttributes)481,
        valuesTarget.get_ReturnType(),
        noParameters
    )
    valuesIl := TypeOfMethodBuilderIL(values)
    valuesIl.Emit(OpCodes.Ldnull)
    valuesIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(values, valuesTarget)

    containsParameters := new Type[](1)
    containsParameters[0] = typeof(Type)
    containsTarget := ExecutorRequiredMethod(readOnlyDictionary, "ContainsKey", containsParameters)
    contains := owner.DefineMethod(
        "ContainsKey",
        (MethodAttributes)481,
        typeof(bool),
        containsParameters
    )
    containsIl := TypeOfMethodBuilderIL(contains)
    ConstraintControlsEmitInvalidOperation(containsIl, "hostile map ContainsKey was read")
    owner.DefineMethodOverride(contains, containsTarget)

    countTarget := ConstraintControlsRequiredGetter(genericCollection, "Count")
    count := owner.DefineMethod(
        "get_Count",
        (MethodAttributes)481,
        typeof(int),
        noParameters
    )
    countIl := TypeOfMethodBuilderIL(count)
    countIl.Emit(OpCodes.Ldc_I4_0)
    countIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(count, countTarget)

    genericGetEnumeratorTarget := ExecutorRequiredMethod(genericEnumerable, "GetEnumerator", noParameters)
    runtimeAcquireParameters := new Type[](1)
    runtimeAcquireParameters[0] = typeof(ConstraintControlsHostileMapState)
    runtimeAcquire := ExecutorRequiredMethod(
        typeof(ConstraintControlsHostileMapRuntime),
        "Acquired",
        runtimeAcquireParameters
    )
    genericGetEnumerator := owner.DefineMethod(
        "GenericGetEnumerator",
        (MethodAttributes)481,
        genericEnumerator,
        noParameters
    )
    genericGetEnumeratorIl := TypeOfMethodBuilderIL(genericGetEnumerator)
    genericGetEnumeratorIl.Emit(OpCodes.Ldarg_0)
    genericGetEnumeratorIl.Emit(OpCodes.Ldfld, stateField)
    genericGetEnumeratorIl.Emit(OpCodes.Call, runtimeAcquire)
    if entries == null {
        ConstraintControlsEmitInvalidOperation(genericGetEnumeratorIl, "hostile map enumeration reached")
    } else {
        genericGetEnumeratorIl.Emit(OpCodes.Ldarg_0)
        genericGetEnumeratorIl.Emit(OpCodes.Ldfld, enumeratorField)
        genericGetEnumeratorIl.Emit(OpCodes.Ret)
    }
    owner.DefineMethodOverride(genericGetEnumerator, genericGetEnumeratorTarget)

    nongenericEnumerable := typeof(System.Collections.IEnumerable)
    nongenericGetEnumeratorTarget := ExecutorRequiredMethod(nongenericEnumerable, "GetEnumerator", noParameters)
    nongenericGetEnumerator := owner.DefineMethod(
        "NongenericGetEnumerator",
        (MethodAttributes)481,
        typeof(System.Collections.IEnumerator),
        noParameters
    )
    nongenericGetEnumeratorIl := TypeOfMethodBuilderIL(nongenericGetEnumerator)
    ConstraintControlsEmitInvalidOperation(nongenericGetEnumeratorIl, "hostile nongeneric map enumeration reached")
    owner.DefineMethodOverride(nongenericGetEnumerator, nongenericGetEnumeratorTarget)

    baked := IdentityBake(owner)
    instanceConstructor := ExecutorRequiredConstructor(baked, noParameters)
    instance := instanceConstructor.Invoke(noParameters)
    if instance == null {
        throw new InvalidOperationException("The hostile map fixture was not constructed.")
    }
    bakedStateField := baked.GetField("State")
    if bakedStateField == null {
        throw new InvalidOperationException("The hostile map fixture lost its State field.")
    }
    bakedStateField.SetValue(instance, new ConstraintControlsHostileMapState(key, value, exact))
    if entries != null {
        bakedEnumeratorField := baked.GetField("Enumerator")
        if bakedEnumeratorField == null {
            throw new InvalidOperationException("The hostile map fixture lost its Enumerator field.")
        }
        bakedEnumeratorField.SetValue(instance, entries)
    }
    return instance
}

func ConstraintControlsHostileState(instance: object): ConstraintControlsHostileMapState {
    field := instance.GetType().GetField("State")
    if field == null {
        throw new InvalidOperationException("The hostile map State field was not found.")
    }
    state := field.GetValue(instance) as ConstraintControlsHostileMapState
    if state == null {
        throw new InvalidOperationException("The hostile map State was not assigned.")
    }
    return state
}

func ConstraintControlsInvokeResolve(
    map: object,
    requested: Type,
    outcome: ConstraintControlsWeakOutcome
): bool {
    method := typeof(ConstraintControlsResolveInvoker).GetMethod("Resolve")
    if method == null {
        throw new InvalidOperationException("The typed constraint planner runner was not found.")
    }
    arguments := new object[](3)
    ExecutorSetObject(arguments, 0, map)
    ExecutorSetObject(arguments, 1, requested)
    ExecutorSetObject(arguments, 2, outcome)
    value := TypeOfRequiredInvocation(method, null, arguments)
    return Convert.ToBoolean(value)
}

test "the supplied dictionary comparer creates an exact hit before weak fallback or reflection" {
    requested := ConstraintControlsParameter(typeof(ConstraintControlsSecond<int>))
    differentName := ConstraintControlsParameter(typeof(ConstraintControlsDifferentName<int>))
    value := ConstraintControlsOneType(typeof(IComparable))
    map := new Dictionary<Type, Type[]>(new ConstraintControlsAllTypeComparer())
    map.Add(differentName, value)

    // `U` cannot satisfy the later weak name check against `T`; the returned marker therefore proves
    // the map's comparer answered the initial exact lookup and reflection was bypassed.
    result := ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, requested)
    assert Object.ReferenceEquals(result, value)
}

test "a supplied dictionary comparer exception propagates at the exact lookup" {
    requested := ConstraintControlsParameter(typeof(ConstraintControlsSecond<int>))
    differentName := ConstraintControlsParameter(typeof(ConstraintControlsDifferentName<int>))
    comparer := new ConstraintControlsDelayedThrowComparer()
    map := new Dictionary<Type, Type[]>(comparer)
    map.Add(differentName, ConstraintControlsOneType(typeof(IComparable)))
    comparer.ThrowOnLookup = true

    assert throws InvalidOperationException {
        _constraints := ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, requested)
    }
}

test "weak fallback reads the same supplied map live after its order changes" {
    first := ConstraintControlsParameter(typeof(ConstraintControlsFirst<int>))
    requested := ConstraintControlsParameter(typeof(ConstraintControlsSecond<int>))
    later := ConstraintControlsParameter(typeof(ConstraintControlsThird<int>))
    firstValue := ConstraintControlsOneType(typeof(IDisposable))
    laterValue := ConstraintControlsOneType(typeof(IComparable))
    map := new Dictionary<Type, Type[]>()
    map.Add(first, firstValue)
    map.Add(later, laterValue)

    initial := ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, requested)
    assert Object.ReferenceEquals(initial, firstValue)

    map.Clear()
    map.Add(later, laterValue)
    map.Add(first, firstValue)
    reordered := ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, requested)
    assert Object.ReferenceEquals(reordered, laterValue)
}

test "an exact map hit bypasses hostile enumeration and sees the planner's null out local" {
    requested := ConstraintControlsParameter(typeof(ConstraintControlsSecond<int>))
    marker := ConstraintControlsOneType(typeof(IComparable))
    map := ConstraintControlsHostileMap("Exact", true, requested, marker, null)
    outcome := new ConstraintControlsWeakOutcome(null)

    assert ConstraintControlsInvokeResolve(map, requested, outcome)
    assert outcome.Result
    assert outcome.ErrorMessage == null
    assert Object.ReferenceEquals(outcome.Constraints, marker)
    state := ConstraintControlsHostileState(map)
    assert state.LookupCount == 1
    assert state.AcquireCount == 0
    assert state.InitialOut == null
}

test "a map miss reaches its hostile generic enumerator after the exact null out observation" {
    requested := ConstraintControlsParameter(typeof(ConstraintControlsSecond<int>))
    marker := ConstraintControlsOneType(typeof(IComparable))
    map := ConstraintControlsHostileMap("Miss", false, requested, marker, null)
    outcome := new ConstraintControlsWeakOutcome(marker)

    assert ConstraintControlsInvokeResolve(map, requested, outcome)
    assert !outcome.Result
    assert outcome.ErrorMessage == "hostile map enumeration reached"
    assert Object.ReferenceEquals(outcome.Constraints, marker)
    state := ConstraintControlsHostileState(map)
    assert state.LookupCount == 1
    assert state.AcquireCount == 1
    assert state.InitialOut == null
}

test "a public fallback enters the requested getter after it disposes the exhausted weak enumerator" {
    trace := new List<int>()
    expected := ConstraintControlsOneType(typeof(IDisposable))
    requested := GenericConstraintReflectionProbeType(
        "FallbackAfterDispose",
        typeof(object),
        trace,
        1,
        false,
        0,
        "T",
        0,
        0,
        0,
        expected,
        0
    )
    rowValue := ConstraintControlsOneType(typeof(IComparable))
    rows := ConstraintControlsWeakRows("FallbackRows", 1, typeof(int), rowValue, trace)
    map := ConstraintControlsHostileMap("Fallback", false, requested, null, rows)
    outcome := new ConstraintControlsWeakOutcome(null)

    assert ConstraintControlsInvokeResolve(map, requested, outcome)
    assert outcome.Result
    assert outcome.ErrorMessage == null
    assert Object.ReferenceEquals(outcome.Constraints, expected)
    assert GenericConstraintProbeTraceText(trace) == "91,14"
    state := ConstraintControlsHostileState(map)
    assert state.LookupCount == 1
    assert state.AcquireCount == 1
    assert ConstraintControlsCounter(rows, "MoveCount") == 1
    assert ConstraintControlsCounter(rows, "CurrentCount") == 0
    assert ConstraintControlsCounter(rows, "DisposeCount") == 1
}

test "an exhausted throwing disposal prevents the public fallback getter from starting" {
    trace := new List<int>()
    expected := ConstraintControlsOneType(typeof(IDisposable))
    requested := GenericConstraintReflectionProbeType(
        "FallbackBlockedByDispose",
        typeof(object),
        trace,
        1,
        false,
        0,
        "T",
        0,
        0,
        0,
        expected,
        0
    )
    marker := ConstraintControlsOneType(typeof(IComparable))
    rows := ConstraintControlsWeakRows("FallbackDisposeThrows", 5, typeof(int), marker, trace)
    map := ConstraintControlsHostileMap("FallbackDisposeThrows", false, requested, null, rows)
    outcome := new ConstraintControlsWeakOutcome(null)

    assert ConstraintControlsInvokeResolve(map, requested, outcome)
    assert !outcome.Result
    assert outcome.ErrorMessage == "weak entry disposal failed"
    assert outcome.Constraints == null
    assert GenericConstraintProbeTraceText(trace) == "91"
    state := ConstraintControlsHostileState(map)
    assert state.LookupCount == 1
    assert state.AcquireCount == 1
    assert ConstraintControlsCounter(rows, "MoveCount") == 1
    assert ConstraintControlsCounter(rows, "CurrentCount") == 0
    assert ConstraintControlsCounter(rows, "DisposeCount") == 1
}

test "weak lookup reads generic Current then disposes before reporting its first matching value" {
    requested := ConstraintControlsParameter(typeof(ConstraintControlsSecond<int>))
    first := ConstraintControlsParameter(typeof(ConstraintControlsFirst<int>))
    firstValue := ConstraintControlsOneType(typeof(IDisposable))
    rows := ConstraintControlsWeakRows("Hit", 0, first, firstValue, null)
    outcome := new ConstraintControlsWeakOutcome(null)

    assert ConstraintControlsInvokeWeak(rows, requested, outcome)
    assert outcome.Result
    assert outcome.ErrorMessage == null
    assert Object.ReferenceEquals(outcome.Constraints, firstValue)
    assert ConstraintControlsCounter(rows, "AcquireCount") == 1
    assert ConstraintControlsCounter(rows, "MoveCount") == 1
    assert ConstraintControlsCounter(rows, "CurrentCount") == 1
    assert ConstraintControlsCounter(rows, "DisposeCount") == 1
}

test "weak lookup disposes a completed miss before reporting false and a null out value" {
    requested := ConstraintControlsParameter(typeof(ConstraintControlsSecond<int>))
    nonmatching := ConstraintControlsParameter(typeof(ConstraintControlsDifferentName<int>))
    value := ConstraintControlsOneType(typeof(IDisposable))
    rows := ConstraintControlsWeakRows("Miss", 1, nonmatching, value, null)
    outcome := new ConstraintControlsWeakOutcome(value)

    assert ConstraintControlsInvokeWeak(rows, requested, outcome)
    assert !outcome.Result
    assert outcome.ErrorMessage == null
    assert outcome.Constraints == null
    assert ConstraintControlsCounter(rows, "AcquireCount") == 1
    assert ConstraintControlsCounter(rows, "MoveCount") == 1
    assert ConstraintControlsCounter(rows, "CurrentCount") == 0
    assert ConstraintControlsCounter(rows, "DisposeCount") == 1
}

test "weak lookup preserves its direct out local across acquisition movement and disposal failures" {
    requested := ConstraintControlsParameter(typeof(ConstraintControlsSecond<int>))
    matching := ConstraintControlsParameter(typeof(ConstraintControlsFirst<int>))
    nonmatching := ConstraintControlsParameter(typeof(ConstraintControlsDifferentName<int>))
    value := ConstraintControlsOneType(typeof(IDisposable))

    acquireRows := ConstraintControlsWeakRows("AcquireThrows", 4, matching, value, null)
    acquireOutcome := new ConstraintControlsWeakOutcome(value)
    assert ConstraintControlsInvokeWeak(acquireRows, requested, acquireOutcome)
    assert !acquireOutcome.Result
    assert acquireOutcome.ErrorMessage == "weak entry acquisition failed"
    assert Object.ReferenceEquals(acquireOutcome.Constraints, value)
    assert ConstraintControlsCounter(acquireRows, "AcquireCount") == 1
    assert ConstraintControlsCounter(acquireRows, "MoveCount") == 0
    assert ConstraintControlsCounter(acquireRows, "CurrentCount") == 0
    assert ConstraintControlsCounter(acquireRows, "DisposeCount") == 0

    moveRows := ConstraintControlsWeakRows("MoveThrows", 2, nonmatching, value, null)
    moveOutcome := new ConstraintControlsWeakOutcome(value)
    assert ConstraintControlsInvokeWeak(moveRows, requested, moveOutcome)
    assert !moveOutcome.Result
    assert moveOutcome.ErrorMessage == "weak entry movement failed"
    assert Object.ReferenceEquals(moveOutcome.Constraints, value)
    assert ConstraintControlsCounter(moveRows, "AcquireCount") == 1
    assert ConstraintControlsCounter(moveRows, "MoveCount") == 1
    assert ConstraintControlsCounter(moveRows, "CurrentCount") == 0
    assert ConstraintControlsCounter(moveRows, "DisposeCount") == 1

    disposeRows := ConstraintControlsWeakRows("DisposeThrows", 3, matching, value, null)
    disposeOutcome := new ConstraintControlsWeakOutcome(null)
    assert ConstraintControlsInvokeWeak(disposeRows, requested, disposeOutcome)
    assert !disposeOutcome.Result
    assert disposeOutcome.ErrorMessage == "weak entry disposal failed"
    assert Object.ReferenceEquals(disposeOutcome.Constraints, value)
    assert ConstraintControlsCounter(disposeRows, "AcquireCount") == 1
    assert ConstraintControlsCounter(disposeRows, "MoveCount") == 1
    assert ConstraintControlsCounter(disposeRows, "CurrentCount") == 1
    assert ConstraintControlsCounter(disposeRows, "DisposeCount") == 1

    missDisposeRows := ConstraintControlsWeakRows("MissDisposeThrows", 5, nonmatching, value, null)
    missDisposeOutcome := new ConstraintControlsWeakOutcome(value)
    assert ConstraintControlsInvokeWeak(missDisposeRows, requested, missDisposeOutcome)
    assert !missDisposeOutcome.Result
    assert missDisposeOutcome.ErrorMessage == "weak entry disposal failed"
    assert Object.ReferenceEquals(missDisposeOutcome.Constraints, value)
    assert ConstraintControlsCounter(missDisposeRows, "AcquireCount") == 1
    assert ConstraintControlsCounter(missDisposeRows, "MoveCount") == 1
    assert ConstraintControlsCounter(missDisposeRows, "CurrentCount") == 0
    assert ConstraintControlsCounter(missDisposeRows, "DisposeCount") == 1
}

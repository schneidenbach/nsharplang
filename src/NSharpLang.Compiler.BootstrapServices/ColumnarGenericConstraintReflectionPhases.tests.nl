namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// HOSTILE TYPE METADATA, BUILT AS REAL CLR OVERRIDES.
//
// A direct N# subclass of TypeDelegator is outside the current emit surface. These controls instead
// bake the same subclass with Reflection.Emit so the query is exercised through ordinary virtual Type
// getters, without adding a compiler capability solely for its tests.
func GenericConstraintEmitProbeTrace(
    il: ILGenerator,
    traceField: FieldBuilder,
    code: int
) {
    addParameters := new Type[](1)
    addParameters[0] = typeof(int)
    add := ExecutorRequiredMethod(typeof(List<int>), "Add", addParameters)
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Ldfld, traceField)
    il.Emit(OpCodes.Ldc_I4, code)
    il.Emit(OpCodes.Callvirt, add)
}

func GenericConstraintEmitProbeFailure(il: ILGenerator, failureKind: int): bool {
    noParameters := new Type[](0)
    if failureKind == 1 {
        constructor := ExecutorRequiredConstructor(typeof(NotSupportedException), noParameters)
        il.Emit(OpCodes.Newobj, constructor)
        il.Emit(OpCodes.Throw)
        return true
    }
    if failureKind == 2 {
        constructor := ExecutorRequiredConstructor(typeof(NotImplementedException), noParameters)
        il.Emit(OpCodes.Newobj, constructor)
        il.Emit(OpCodes.Throw)
        return true
    }
    if failureKind == 3 {
        messageParameters := new Type[](1)
        messageParameters[0] = typeof(string)
        constructor := ExecutorRequiredConstructor(typeof(InvalidOperationException), messageParameters)
        il.Emit(OpCodes.Ldstr, "generic constraint probe failure")
        il.Emit(OpCodes.Newobj, constructor)
        il.Emit(OpCodes.Throw)
        return true
    }
    return false
}

func GenericConstraintReflectionProbeType(
    typeName: string,
    delegatedType: Type,
    trace: List<int>,
    probeIndex: int,
    isGenericParameter: bool,
    isGenericFailure: int,
    parameterName: string,
    nameFailure: int,
    parameterPosition: int,
    positionFailure: int,
    constraints: Type[],
    constraintsFailure: int
): Type {
    owner := TypeOfCreateBuilder(
        typeName,
        "ColumnarGenericConstraintReflectionPhases." + typeName,
        0
    )
    ConstructionSetParent(owner, typeof(TypeDelegator))

    noParameters := new Type[](0)
    constructorParameters := new Type[](3)
    constructorParameters[0] = typeof(Type)
    constructorParameters[1] = typeof(List<int>)
    constructorParameters[2] = typeof(Type[])
    traceField := ConstructionDefinePublicField(owner, "Trace", typeof(List<int>))
    constraintsField := ConstructionDefinePublicField(owner, "Constraints", typeof(Type[]))
    constructor := owner.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        constructorParameters
    )
    constructorIl := constructor.GetILGenerator()
    parentConstructorParameters := new Type[](1)
    parentConstructorParameters[0] = typeof(Type)
    parentConstructor := ExecutorRequiredConstructor(typeof(TypeDelegator), parentConstructorParameters)
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Ldarg_1)
    constructorIl.Emit(OpCodes.Call, parentConstructor)
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Ldarg_2)
    constructorIl.Emit(OpCodes.Stfld, traceField)
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Ldarg_3)
    constructorIl.Emit(OpCodes.Stfld, constraintsField)
    constructorIl.Emit(OpCodes.Ret)

    isGenericTarget := SourceDiscoveryTimingRequiredGetter(typeof(Type), "IsGenericParameter")
    isGenericImplementation := owner.DefineMethod(
        "get_IsGenericParameter",
        (MethodAttributes)2246,
        typeof(bool),
        noParameters
    )
    isGenericIl := TypeOfMethodBuilderIL(isGenericImplementation)
    GenericConstraintEmitProbeTrace(isGenericIl, traceField, probeIndex * 10 + 1)
    if !GenericConstraintEmitProbeFailure(isGenericIl, isGenericFailure) {
        if isGenericParameter {
            isGenericIl.Emit(OpCodes.Ldc_I4_1)
        } else {
            isGenericIl.Emit(OpCodes.Ldc_I4_0)
        }
        isGenericIl.Emit(OpCodes.Ret)
    }
    owner.DefineMethodOverride(isGenericImplementation, isGenericTarget)

    nameTarget := SourceDiscoveryTimingRequiredGetter(typeof(Type), "Name")
    nameImplementation := owner.DefineMethod(
        "get_Name",
        (MethodAttributes)2246,
        typeof(string),
        noParameters
    )
    nameIl := TypeOfMethodBuilderIL(nameImplementation)
    GenericConstraintEmitProbeTrace(nameIl, traceField, probeIndex * 10 + 2)
    if !GenericConstraintEmitProbeFailure(nameIl, nameFailure) {
        nameIl.Emit(OpCodes.Ldstr, parameterName)
        nameIl.Emit(OpCodes.Ret)
    }
    owner.DefineMethodOverride(nameImplementation, nameTarget)

    positionTarget := SourceDiscoveryTimingRequiredGetter(typeof(Type), "GenericParameterPosition")
    positionImplementation := owner.DefineMethod(
        "get_GenericParameterPosition",
        (MethodAttributes)2246,
        typeof(int),
        noParameters
    )
    positionIl := TypeOfMethodBuilderIL(positionImplementation)
    GenericConstraintEmitProbeTrace(positionIl, traceField, probeIndex * 10 + 3)
    if !GenericConstraintEmitProbeFailure(positionIl, positionFailure) {
        positionIl.Emit(OpCodes.Ldc_I4, parameterPosition)
        positionIl.Emit(OpCodes.Ret)
    }
    owner.DefineMethodOverride(positionImplementation, positionTarget)

    constraintsTarget := ExecutorRequiredMethod(typeof(Type), "GetGenericParameterConstraints", noParameters)
    constraintsImplementation := owner.DefineMethod(
        "GetGenericParameterConstraints",
        (MethodAttributes)198,
        typeof(Type[]),
        noParameters
    )
    constraintsIl := TypeOfMethodBuilderIL(constraintsImplementation)
    GenericConstraintEmitProbeTrace(constraintsIl, traceField, probeIndex * 10 + 4)
    if !GenericConstraintEmitProbeFailure(constraintsIl, constraintsFailure) {
        constraintsIl.Emit(OpCodes.Ldarg_0)
        constraintsIl.Emit(OpCodes.Ldfld, constraintsField)
        constraintsIl.Emit(OpCodes.Ret)
    }
    owner.DefineMethodOverride(constraintsImplementation, constraintsTarget)

    baked := IdentityBake(owner)
    bakedConstructor := ExecutorRequiredConstructor(baked, constructorParameters)
    arguments := new object[](3)
    ExecutorSetObject(arguments, 0, delegatedType)
    ExecutorSetObject(arguments, 1, trace)
    ExecutorSetObject(arguments, 2, constraints)
    instance := bakedConstructor.Invoke(arguments)
    probe := instance as Type
    if probe == null {
        throw new InvalidOperationException("The generic-constraint Type probe was not constructed.")
    }
    return probe
}

func GenericConstraintProbeTraceText(actual: List<int>): string {
    result := ""
    index := 0
    while index < actual.Count {
        if index > 0 {
            result = result + ","
        }
        result = result + actual[index].ToString()
        index += 1
    }
    return result
}

test "call constraints retain the exact raw reflection array" {
    trace := new List<int>()
    expected := new Type[](2)
    expected[0] = typeof(IDisposable)
    expected[1] = typeof(ValueType)
    requested := GenericConstraintReflectionProbeType(
        "ExactReflectionArray",
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
    map := new Dictionary<Type, Type[]>()

    actual := ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, requested)
    assert Object.ReferenceEquals(actual, expected)
    assert GenericConstraintProbeTraceText(trace) == "14"
}

test "call constraint reflection catches only NS and NIE and returns the BCL empty array" {
    map := new Dictionary<Type, Type[]>()
    noConstraints := new Type[](0)

    notSupportedTrace := new List<int>()
    notSupported := GenericConstraintReflectionProbeType(
        "ReflectionNotSupported",
        typeof(string),
        notSupportedTrace,
        1,
        false,
        0,
        "T",
        0,
        0,
        0,
        noConstraints,
        1
    )
    notSupportedResult := ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, notSupported)
    assert Object.ReferenceEquals(notSupportedResult, System.Type.EmptyTypes)
    assert GenericConstraintProbeTraceText(notSupportedTrace) == "14"

    notImplementedTrace := new List<int>()
    notImplemented := GenericConstraintReflectionProbeType(
        "ReflectionNotImplemented",
        typeof(int),
        notImplementedTrace,
        2,
        false,
        0,
        "T",
        0,
        0,
        0,
        noConstraints,
        2
    )
    notImplementedResult := ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, notImplemented)
    assert Object.ReferenceEquals(notImplementedResult, System.Type.EmptyTypes)
    assert GenericConstraintProbeTraceText(notImplementedTrace) == "24"

    otherTrace := new List<int>()
    other := GenericConstraintReflectionProbeType(
        "ReflectionOtherFailure",
        typeof(DateTime),
        otherTrace,
        3,
        false,
        0,
        "T",
        0,
        0,
        0,
        noConstraints,
        3
    )
    assert throws InvalidOperationException {
        ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, other)
    }
    assert GenericConstraintProbeTraceText(otherTrace) == "34"
}

test "weak constraint guards execute outside the position catches" {
    noConstraints := new Type[](0)
    firstValue := new Type[](1)
    firstValue[0] = typeof(string)

    isGenericTrace := new List<int>()
    throwingIsGeneric := GenericConstraintReflectionProbeType(
        "WeakThrowingIsGeneric",
        typeof(object),
        isGenericTrace,
        1,
        true,
        1,
        "T",
        0,
        0,
        0,
        noConstraints,
        0
    )
    isGenericRequested := GenericConstraintReflectionProbeType(
        "WeakIsGenericRequested",
        typeof(string),
        isGenericTrace,
        2,
        true,
        0,
        "T",
        0,
        0,
        0,
        noConstraints,
        0
    )
    isGenericMap := new Dictionary<Type, Type[]>()
    isGenericMap[throwingIsGeneric] = firstValue
    assert throws NotSupportedException {
        ColumnarGenericConstraintPlanner.ResolveCallConstraints(isGenericMap, isGenericRequested)
    }
    assert GenericConstraintProbeTraceText(isGenericTrace) == "11"

    nameTrace := new List<int>()
    throwingName := GenericConstraintReflectionProbeType(
        "WeakThrowingName",
        typeof(int),
        nameTrace,
        3,
        true,
        0,
        "T",
        2,
        0,
        0,
        noConstraints,
        0
    )
    nameRequested := GenericConstraintReflectionProbeType(
        "WeakNameRequested",
        typeof(DateTime),
        nameTrace,
        4,
        true,
        0,
        "T",
        0,
        0,
        0,
        noConstraints,
        0
    )
    nameMap := new Dictionary<Type, Type[]>()
    nameMap[throwingName] = firstValue
    assert throws NotImplementedException {
        ColumnarGenericConstraintPlanner.ResolveCallConstraints(nameMap, nameRequested)
    }
    assert GenericConstraintProbeTraceText(nameTrace) == "31,41,32"
}

test "weak constraint positions read left before right skip NS and NIE and propagate other faults" {
    noConstraints := new Type[](0)
    firstValue := new Type[](1)
    firstValue[0] = typeof(string)
    secondValue := new Type[](1)
    secondValue[0] = typeof(int)
    winningValue := new Type[](1)
    winningValue[0] = typeof(DateTime)
    trace := new List<int>()

    notSupported := GenericConstraintReflectionProbeType(
        "WeakPositionNotSupported",
        typeof(object),
        trace,
        1,
        true,
        0,
        "T",
        0,
        0,
        1,
        noConstraints,
        0
    )
    notImplemented := GenericConstraintReflectionProbeType(
        "WeakPositionNotImplemented",
        typeof(string),
        trace,
        2,
        true,
        0,
        "T",
        0,
        0,
        2,
        noConstraints,
        0
    )
    winner := GenericConstraintReflectionProbeType(
        "WeakPositionWinner",
        typeof(int),
        trace,
        3,
        true,
        0,
        "T",
        0,
        0,
        0,
        noConstraints,
        0
    )
    requested := GenericConstraintReflectionProbeType(
        "WeakPositionRequested",
        typeof(DateTime),
        trace,
        4,
        true,
        0,
        "T",
        0,
        0,
        0,
        noConstraints,
        0
    )
    map := new Dictionary<Type, Type[]>()
    map[notSupported] = firstValue
    map[notImplemented] = secondValue
    map[winner] = winningValue

    result := ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, requested)
    assert Object.ReferenceEquals(result, winningValue)
    assert GenericConstraintProbeTraceText(trace) == "11,41,12,42,13,21,41,22,42,23,31,41,32,42,33,43"

    otherTrace := new List<int>()
    other := GenericConstraintReflectionProbeType(
        "WeakPositionOtherFailure",
        typeof(Guid),
        otherTrace,
        5,
        true,
        0,
        "T",
        0,
        0,
        3,
        noConstraints,
        0
    )
    otherRequested := GenericConstraintReflectionProbeType(
        "WeakPositionOtherRequested",
        typeof(decimal),
        otherTrace,
        6,
        true,
        0,
        "T",
        0,
        0,
        0,
        noConstraints,
        0
    )
    otherMap := new Dictionary<Type, Type[]>()
    otherMap[other] = firstValue
    assert throws InvalidOperationException {
        ColumnarGenericConstraintPlanner.ResolveCallConstraints(otherMap, otherRequested)
    }
    assert GenericConstraintProbeTraceText(otherTrace) == "51,61,52,62,53"
}

test "weak constraint position catches include the right operand before raw reflection" {
    trace := new List<int>()
    noConstraints := new Type[](0)
    mapped := new Type[](1)
    mapped[0] = typeof(string)
    reflected := new Type[](1)
    reflected[0] = typeof(IDisposable)

    key := GenericConstraintReflectionProbeType(
        "WeakRightPositionKey",
        typeof(object),
        trace,
        7,
        true,
        0,
        "T",
        0,
        0,
        0,
        noConstraints,
        0
    )
    requested := GenericConstraintReflectionProbeType(
        "WeakRightPositionRequested",
        typeof(string),
        trace,
        8,
        true,
        0,
        "T",
        0,
        0,
        1,
        reflected,
        0
    )
    map := new Dictionary<Type, Type[]>()
    map[key] = mapped

    result := ColumnarGenericConstraintPlanner.ResolveCallConstraints(map, requested)
    assert Object.ReferenceEquals(result, reflected)
    assert GenericConstraintProbeTraceText(trace) == "71,81,72,82,73,83,84"
}

namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Threading.Tasks

// These iterator names are unique so the independent ECMA-335 control can attribute their
// MethodImpl rows without relying on the older iterator fixtures.  The generic synchronous
// machine carries its own VAR while its factory carries the separately-owned MVAR.
class IteratorBindingSource {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

func* IteratorBindingRepeat<T>(value: T, count: int): IEnumerable<T> {
    i := 0
    while i < count {
        yield value
        i = i + 1
    }
}

// A non-generic top-level async iterator stays inside the admitted baseline surface.  Its mapped
// interfaces cover MoveNextAsync, generic Current, DisposeAsync, and GetAsyncEnumerator(token).
async func* IteratorBindingDelayed(count: int): IAsyncEnumerable<int> {
    i := 0
    while i < count {
        await Task.Delay(1)
        yield i
        i = i + 1
    }
}

class IteratorBindingMapPair {
    InterfaceMethod: MethodInfo
    TargetMethod: MethodInfo

    constructor(interfaceMethod: MethodInfo, targetMethod: MethodInfo) {
        InterfaceMethod = interfaceMethod
        TargetMethod = targetMethod
    }
}

func IteratorBindingPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

// InterfaceMapping is obtained through reflection because stage0 does not admit an
// InterfaceMapping local.  These are still the actual map columns produced by the compiler.
func IteratorBindingMapField(mapping: object, fieldName: string): IList {
    field := mapping.GetType().GetField(fieldName)
    if field == null {
        throw new InvalidOperationException("Missing InterfaceMapping field '" + fieldName + "'")
    }
    values := field.GetValue(mapping) as IList
    if values == null {
        throw new InvalidOperationException("InterfaceMapping field '" + fieldName + "' was not an IList")
    }
    return values
}

func IteratorBindingMappedPair(implementation: Type, interfaceType: Type, memberName: string, parameterCount: int): IteratorBindingMapPair {
    getInterfaceMap := typeof(Type).GetMethod("GetInterfaceMap")
    if getInterfaceMap == null {
        throw new InvalidOperationException("Missing Type.GetInterfaceMap")
    }
    arguments := new object?[](1)
    IteratorBindingPut(arguments, 0, interfaceType)
    mapping := getInterfaceMap.Invoke(implementation, arguments)
    if mapping == null {
        throw new InvalidOperationException("Type.GetInterfaceMap returned null")
    }
    interfaceMethods := IteratorBindingMapField(mapping, "InterfaceMethods")
    targetMethods := IteratorBindingMapField(mapping, "TargetMethods")
    if interfaceMethods.Count != targetMethods.Count {
        throw new InvalidOperationException("InterfaceMapping method columns had different counts")
    }
    index := 0
    while index < interfaceMethods.Count {
        candidate := interfaceMethods[index] as MethodInfo
        target := targetMethods[index] as MethodInfo
        if candidate != null && target != null && candidate.get_Name() == memberName && candidate.GetParameters().Length == parameterCount {
            return new IteratorBindingMapPair(candidate, target)
        }
        index = index + 1
    }
    throw new InvalidOperationException("No mapped member '" + memberName + "'")
}

func IteratorBindingRequiredMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("Missing iterator member '" + name + "'")
    }
    return method
}

func IteratorBindingRequiredDeclaringType(method: MethodInfo): Type {
    owner := method.get_DeclaringType()
    if owner == null {
        throw new InvalidOperationException("Iterator member had no declaring type")
    }
    return owner
}

func IteratorBindingRuntimeType(canonicalName: string): Type {
    resolved := Type.GetType(canonicalName)
    if resolved == null {
        throw new InvalidOperationException("Missing runtime type '" + canonicalName + "'")
    }
    return resolved
}

func IteratorBindingExactZeroSignature(method: MethodInfo, returnType: Type): bool {
    return method.get_ReturnType() == returnType && method.GetParameters().Length == 0
}

func IteratorBindingExactUnarySignature(method: MethodInfo, returnType: Type, parameterType: Type): bool {
    parameters := method.GetParameters()
    return method.get_ReturnType() == returnType && parameters.Length == 1 && parameters[0].get_ParameterType() == parameterType
}

func IteratorBindingHasOpenGenericInterface(owner: Type, definition: Type, argument: Type): bool {
    interfaces := owner.GetInterfaces()
    for candidate in interfaces {
        if candidate.get_IsGenericType() && candidate.GetGenericTypeDefinition() == definition {
            arguments := candidate.GetGenericArguments()
            if arguments.Length == 1 && arguments[0] == argument {
                return true
            }
        }
    }
    return false
}

func IteratorBindingRequirement(condition: bool, label: string): bool {
    if !condition {
        throw new InvalidOperationException("Iterator binding requirement failed: " + label)
    }
    return true
}

func IteratorBindingValueTaskResult(value: object): object? {
    asTask := value.GetType().GetMethod("AsTask")
    if asTask == null {
        throw new InvalidOperationException("Mapped async member did not return a ValueTask")
    }
    empty := new object?[](0)
    task := asTask.Invoke(value, empty)
    if task == null {
        throw new InvalidOperationException("ValueTask.AsTask returned null")
    }
    getAwaiter := task.GetType().GetMethod("GetAwaiter")
    if getAwaiter == null {
        throw new InvalidOperationException("Mapped async task had no awaiter")
    }
    awaiter := getAwaiter.Invoke(task, empty)
    if awaiter == null {
        throw new InvalidOperationException("Mapped async task returned no awaiter")
    }
    getResult := awaiter.GetType().GetMethod("GetResult")
    if getResult == null {
        throw new InvalidOperationException("Mapped async awaiter had no result")
    }
    return getResult.Invoke(awaiter, empty)
}

func IteratorBindingHostMethod(typeName: string, methodName: string): MethodInfo {
    owner := Type.GetType("NSharpLang.Compiler.Columnar." + typeName + ", Compiler")
    if owner == null {
        throw new InvalidOperationException("Missing host " + typeName)
    }
    methods := owner.GetMethods((BindingFlags)40)
    for method in methods {
        if method.get_Name() == methodName {
            return method
        }
    }
    throw new InvalidOperationException("Missing host method " + methodName)
}

func IteratorBindingReadDeclineProperty(target: object, name: string): string {
    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing decline property " + name)
    }
    return Convert.ToString(property.GetValue(target)) ?? ""
}

// Invalid shapes cannot be compiled as part of this test assembly.  This invokes the regular
// parser and emitter entry points, requires parsing first, and makes successful twins prove that
// the path can emit an image.  A one-record result is the exact production emitter decline.
func IteratorBindingEmitOutcome(source: string): string {
    parse := IteratorBindingHostMethod("ColumnarProgramInputBuilder", "TryBuild")
    parseArguments := new object?[](2)
    IteratorBindingPut(parseArguments, 0, source)
    IteratorBindingPut(parseArguments, 1, null)
    if !Convert.ToBoolean(parse.Invoke(null, parseArguments)) {
        throw new InvalidOperationException("Iterator-binding control did not parse")
    }
    program := parseArguments[1]
    if program == null {
        throw new InvalidOperationException("Iterator-binding parser returned no program")
    }
    reset := IteratorBindingHostMethod("ColumnarDeclineTrace", "Reset")
    empty := new object?[](0)
    ignored := reset.Invoke(null, empty)
    _ = ignored
    emit := IteratorBindingHostMethod("ColumnarIlEmitter", "TryEmitColumnarAssembly")
    emitArguments := new object?[](7)
    IteratorBindingPut(emitArguments, 0, "IteratorBindingNegative")
    IteratorBindingPut(emitArguments, 1, "Program")
    IteratorBindingPut(emitArguments, 2, program)
    IteratorBindingPut(emitArguments, 3, false)
    IteratorBindingPut(emitArguments, 4, null)
    IteratorBindingPut(emitArguments, 5, null)
    IteratorBindingPut(emitArguments, 6, null)
    succeeded := Convert.ToBoolean(emit.Invoke(null, emitArguments))
    snapshot := IteratorBindingHostMethod("ColumnarDeclineTrace", "Snapshot")
    records := snapshot.Invoke(null, empty) as IList
    if records == null {
        throw new InvalidOperationException("No iterator-binding decline snapshot")
    }
    if records.Count == 0 {
        if succeeded {
            image := emitArguments[4] as IList
            if image == null || image.Count < 2 || Convert.ToInt32(image[0]) != 77 || Convert.ToInt32(image[1]) != 90 {
                throw new InvalidOperationException("Iterator-binding emitter did not produce an MZ image")
            }
            return "success"
        }
        return "false without decline"
    }
    if succeeded || records.Count != 1 {
        throw new InvalidOperationException("Iterator-binding emitter produced an unexpected decline set")
    }
    first := records[0]
    if first == null {
        throw new InvalidOperationException("Iterator-binding decline snapshot was empty")
    }
    return IteratorBindingReadDeclineProperty(first, "SiteId") + "|" + IteratorBindingReadDeclineProperty(first, "Message") + "|" + IteratorBindingReadDeclineProperty(first, "MemberName")
}

test "a generic synchronous iterator separates factory MVAR from machine VAR and maps every sync route" {
    source := new IteratorBindingSource(41)
    sequence := IteratorBindingRepeat(source, 2)
    boxed: object = sequence
    machine := boxed.GetType()
    machineDefinition := machine.GetGenericTypeDefinition()
    machineParameters := machineDefinition.GetGenericArguments()
    assert IteratorBindingRequirement(machineParameters.Length == 1, "one machine parameter")
    machineVar := machineParameters[0]
    assert IteratorBindingRequirement(machineVar.get_IsGenericParameter(), "machine parameter is generic")
    assert IteratorBindingRequirement(machineVar.get_IsGenericTypeParameter(), "machine parameter is a type parameter")
    assert IteratorBindingRequirement(!machineVar.get_IsGenericMethodParameter(), "machine parameter is not a method parameter")
    assert IteratorBindingRequirement(machineVar.get_GenericParameterPosition() == 0, "machine parameter ordinal")
    assert IteratorBindingRequirement(machineVar.get_DeclaringType() == machineDefinition, "machine parameter declaring type")
    assert IteratorBindingRequirement(machineVar.get_DeclaringMethod() == null, "machine parameter has no declaring method")

    host := machine.get_Assembly().GetType("Program")
    if host == null {
        throw new InvalidOperationException("Missing iterator factory host")
    }
    factory := IteratorBindingRequiredMethod(host, "IteratorBindingRepeat")
    factoryParameters := factory.GetGenericArguments()
    assert IteratorBindingRequirement(factoryParameters.Length == 1, "one factory parameter")
    factoryMVar := factoryParameters[0]
    assert IteratorBindingRequirement(factoryMVar.get_IsGenericParameter(), "factory parameter is generic")
    assert IteratorBindingRequirement(factoryMVar.get_IsGenericMethodParameter(), "factory parameter is a method parameter")
    assert IteratorBindingRequirement(!factoryMVar.get_IsGenericTypeParameter(), "factory parameter is not a type parameter")
    assert IteratorBindingRequirement(factoryMVar.get_GenericParameterPosition() == 0, "factory parameter ordinal")
    factoryTypeOwner := factoryMVar.get_DeclaringType()
    assert IteratorBindingRequirement(factoryTypeOwner == host, "factory parameter declaring type")
    factoryMethodOwner := factoryMVar.get_DeclaringMethod()
    assert IteratorBindingRequirement(factoryMethodOwner != null, "factory parameter declaring method exists")
    sameFactoryOwner := Object.ReferenceEquals(factoryMethodOwner, factory)
    assert IteratorBindingRequirement(sameFactoryOwner, "factory parameter declaring method identity")
    assert IteratorBindingRequirement(factoryMVar != machineVar, "factory and machine parameters differ")
    factoryReturnArguments := factory.get_ReturnType().GetGenericArguments()
    assert IteratorBindingRequirement(factoryReturnArguments.Length == 1, "factory return has one parameter")
    assert IteratorBindingRequirement(factoryReturnArguments[0] == factoryMVar, "factory return uses factory parameter")
    enumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    enumeratorDefinition := typeof(IEnumerator<int>).GetGenericTypeDefinition()
    assert IteratorBindingRequirement(IteratorBindingHasOpenGenericInterface(machineDefinition, enumerableDefinition, machineVar), "machine IEnumerable uses machine parameter")
    assert IteratorBindingRequirement(IteratorBindingHasOpenGenericInterface(machineDefinition, enumeratorDefinition, machineVar), "machine IEnumerator uses machine parameter")

    enumerableType := typeof(IEnumerable<IteratorBindingSource>)
    enumeratorType := typeof(IEnumerator<IteratorBindingSource>)
    moveNext := IteratorBindingMappedPair(machine, typeof(IEnumerator), "MoveNext", 0)
    genericGetEnumerator := IteratorBindingMappedPair(machine, enumerableType, "GetEnumerator", 0)
    genericCurrent := IteratorBindingMappedPair(machine, enumeratorType, "get_Current", 0)
    nongenericGetEnumerator := IteratorBindingMappedPair(machine, typeof(IEnumerable), "GetEnumerator", 0)
    nongenericCurrent := IteratorBindingMappedPair(machine, typeof(IEnumerator), "get_Current", 0)
    reset := IteratorBindingMappedPair(machine, typeof(IEnumerator), "Reset", 0)
    dispose := IteratorBindingMappedPair(machine, typeof(IDisposable), "Dispose", 0)
    assert IteratorBindingRequiredDeclaringType(moveNext.InterfaceMethod) == typeof(IEnumerator)
    assert IteratorBindingRequiredDeclaringType(genericGetEnumerator.InterfaceMethod) == enumerableType
    assert IteratorBindingRequiredDeclaringType(genericCurrent.InterfaceMethod) == enumeratorType
    assert IteratorBindingRequiredDeclaringType(nongenericGetEnumerator.InterfaceMethod) == typeof(IEnumerable)
    assert IteratorBindingRequiredDeclaringType(nongenericCurrent.InterfaceMethod) == typeof(IEnumerator)
    assert IteratorBindingRequiredDeclaringType(reset.InterfaceMethod) == typeof(IEnumerator)
    assert IteratorBindingRequiredDeclaringType(dispose.InterfaceMethod) == typeof(IDisposable)
    assert IteratorBindingRequiredDeclaringType(moveNext.TargetMethod) == machine
    assert IteratorBindingRequiredDeclaringType(genericGetEnumerator.TargetMethod) == machine
    assert IteratorBindingRequiredDeclaringType(genericCurrent.TargetMethod) == machine
    assert IteratorBindingRequiredDeclaringType(nongenericGetEnumerator.TargetMethod) == machine
    assert IteratorBindingRequiredDeclaringType(nongenericCurrent.TargetMethod) == machine
    assert IteratorBindingRequiredDeclaringType(reset.TargetMethod) == machine
    assert IteratorBindingRequiredDeclaringType(dispose.TargetMethod) == machine
    assert IteratorBindingExactZeroSignature(moveNext.InterfaceMethod, typeof(bool))
    assert IteratorBindingExactZeroSignature(moveNext.TargetMethod, typeof(bool))
    assert IteratorBindingExactZeroSignature(genericGetEnumerator.InterfaceMethod, enumeratorType)
    assert IteratorBindingExactZeroSignature(genericGetEnumerator.TargetMethod, enumeratorType)
    assert IteratorBindingExactZeroSignature(genericCurrent.InterfaceMethod, typeof(IteratorBindingSource))
    assert IteratorBindingExactZeroSignature(genericCurrent.TargetMethod, typeof(IteratorBindingSource))
    assert IteratorBindingExactZeroSignature(nongenericGetEnumerator.InterfaceMethod, typeof(IEnumerator))
    assert IteratorBindingExactZeroSignature(nongenericGetEnumerator.TargetMethod, typeof(IEnumerator))
    assert IteratorBindingExactZeroSignature(nongenericCurrent.InterfaceMethod, typeof(object))
    assert IteratorBindingExactZeroSignature(nongenericCurrent.TargetMethod, typeof(object))
    resetReturn := reset.InterfaceMethod.get_ReturnType()
    assert resetReturn.get_FullName() == "System.Void"
    assert IteratorBindingExactZeroSignature(reset.InterfaceMethod, resetReturn)
    assert IteratorBindingExactZeroSignature(reset.TargetMethod, resetReturn)
    disposeReturn := dispose.InterfaceMethod.get_ReturnType()
    assert disposeReturn.get_FullName() == "System.Void"
    assert IteratorBindingExactZeroSignature(dispose.InterfaceMethod, disposeReturn)
    assert IteratorBindingExactZeroSignature(dispose.TargetMethod, disposeReturn)

    empty := new object?[](0)
    first := genericGetEnumerator.InterfaceMethod.Invoke(boxed, empty)
    second := genericGetEnumerator.InterfaceMethod.Invoke(boxed, empty)
    if first == null || second == null {
        throw new InvalidOperationException("Iterator GetEnumerator returned null")
    }
    assert Convert.ToBoolean(moveNext.InterfaceMethod.Invoke(first, empty))
    assert Object.ReferenceEquals(genericCurrent.InterfaceMethod.Invoke(first, empty), source)
    assert Object.ReferenceEquals(nongenericCurrent.InterfaceMethod.Invoke(first, empty), source)
    dispose.InterfaceMethod.Invoke(first, empty)
    assert Convert.ToBoolean(moveNext.InterfaceMethod.Invoke(second, empty))
    assert Object.ReferenceEquals(genericCurrent.InterfaceMethod.Invoke(second, empty), source)
    dispose.InterfaceMethod.Invoke(second, empty)

    third := nongenericGetEnumerator.InterfaceMethod.Invoke(boxed, empty)
    if third == null {
        throw new InvalidOperationException("Non-generic GetEnumerator returned null")
    }
    assert Convert.ToBoolean(moveNext.InterfaceMethod.Invoke(third, empty))
    assert Object.ReferenceEquals(nongenericCurrent.InterfaceMethod.Invoke(third, empty), source)
    dispose.InterfaceMethod.Invoke(third, empty)

    primitiveSequence := IteratorBindingRepeat(29, 1)
    primitiveBoxed: object = primitiveSequence
    primitiveMachine := primitiveBoxed.GetType()
    assert primitiveMachine.GetGenericTypeDefinition() == machineDefinition
    primitiveArguments := primitiveMachine.GetGenericArguments()
    assert primitiveArguments.Length == 1
    assert primitiveArguments[0] == typeof(int)
    primitiveEnumerable := typeof(IEnumerable<int>)
    primitiveEnumerator := typeof(IEnumerator<int>)
    primitiveGetEnumerator := IteratorBindingMappedPair(primitiveMachine, primitiveEnumerable, "GetEnumerator", 0)
    primitiveCurrent := IteratorBindingMappedPair(primitiveMachine, primitiveEnumerator, "get_Current", 0)
    assert IteratorBindingRequiredDeclaringType(primitiveGetEnumerator.TargetMethod) == primitiveMachine
    assert IteratorBindingRequiredDeclaringType(primitiveCurrent.TargetMethod) == primitiveMachine
    assert IteratorBindingExactZeroSignature(primitiveGetEnumerator.TargetMethod, primitiveEnumerator)
    assert IteratorBindingExactZeroSignature(primitiveCurrent.TargetMethod, typeof(int))
    primitiveEnumeratorValue := primitiveGetEnumerator.InterfaceMethod.Invoke(primitiveBoxed, empty)
    if primitiveEnumeratorValue == null {
        throw new InvalidOperationException("Primitive iterator GetEnumerator returned null")
    }
    assert Convert.ToBoolean(moveNext.InterfaceMethod.Invoke(primitiveEnumeratorValue, empty))
    assert Convert.ToInt32(primitiveCurrent.InterfaceMethod.Invoke(primitiveEnumeratorValue, empty)) == 29
}

test "an async iterator maps all async routes including CancellationToken and repeats after disposal" {
    sequence := IteratorBindingDelayed(2)
    boxed: object = sequence
    machine := boxed.GetType()
    asyncEnumerableType := typeof(IAsyncEnumerable<int>)
    asyncEnumeratorType := typeof(IAsyncEnumerator<int>)
    cancellationTokenType := IteratorBindingRuntimeType("System.Threading.CancellationToken, System.Private.CoreLib")
    getAsyncEnumerator := IteratorBindingMappedPair(machine, asyncEnumerableType, "GetAsyncEnumerator", 1)
    moveNextAsync := IteratorBindingMappedPair(machine, asyncEnumeratorType, "MoveNextAsync", 0)
    genericCurrent := IteratorBindingMappedPair(machine, asyncEnumeratorType, "get_Current", 0)
    disposeAsync := IteratorBindingMappedPair(machine, typeof(IAsyncDisposable), "DisposeAsync", 0)
    assert IteratorBindingRequiredDeclaringType(getAsyncEnumerator.InterfaceMethod) == asyncEnumerableType
    assert IteratorBindingRequiredDeclaringType(moveNextAsync.InterfaceMethod) == asyncEnumeratorType
    assert IteratorBindingRequiredDeclaringType(genericCurrent.InterfaceMethod) == asyncEnumeratorType
    assert IteratorBindingRequiredDeclaringType(disposeAsync.InterfaceMethod) == typeof(IAsyncDisposable)
    assert IteratorBindingRequiredDeclaringType(getAsyncEnumerator.TargetMethod) == machine
    assert IteratorBindingRequiredDeclaringType(moveNextAsync.TargetMethod) == machine
    assert IteratorBindingRequiredDeclaringType(genericCurrent.TargetMethod) == machine
    assert IteratorBindingRequiredDeclaringType(disposeAsync.TargetMethod) == machine
    assert IteratorBindingExactUnarySignature(getAsyncEnumerator.InterfaceMethod, asyncEnumeratorType, cancellationTokenType)
    assert IteratorBindingExactUnarySignature(getAsyncEnumerator.TargetMethod, asyncEnumeratorType, cancellationTokenType)
    moveNextReturn := moveNextAsync.InterfaceMethod.get_ReturnType()
    assert moveNextReturn.get_IsGenericType()
    assert moveNextReturn.GetGenericTypeDefinition().get_FullName() == "System.Threading.Tasks.ValueTask`1"
    moveNextArguments := moveNextReturn.GetGenericArguments()
    assert moveNextArguments.Length == 1
    assert moveNextArguments[0] == typeof(bool)
    assert IteratorBindingExactZeroSignature(moveNextAsync.TargetMethod, moveNextReturn)
    assert IteratorBindingExactZeroSignature(genericCurrent.InterfaceMethod, typeof(int))
    assert IteratorBindingExactZeroSignature(genericCurrent.TargetMethod, typeof(int))
    disposeAsyncReturn := disposeAsync.InterfaceMethod.get_ReturnType()
    assert disposeAsyncReturn.get_FullName() == "System.Threading.Tasks.ValueTask"
    assert IteratorBindingExactZeroSignature(disposeAsync.TargetMethod, disposeAsyncReturn)

    token := Activator.CreateInstance(cancellationTokenType)
    if token == null {
        throw new InvalidOperationException("CancellationToken construction returned null")
    }
    invokeArguments := new object?[](1)
    IteratorBindingPut(invokeArguments, 0, token)
    empty := new object?[](0)
    first := getAsyncEnumerator.InterfaceMethod.Invoke(boxed, invokeArguments)
    if first == null {
        throw new InvalidOperationException("GetAsyncEnumerator returned null")
    }
    assert Convert.ToBoolean(IteratorBindingValueTaskResult(moveNextAsync.InterfaceMethod.Invoke(first, empty)))
    assert Convert.ToInt32(genericCurrent.InterfaceMethod.Invoke(first, empty)) == 0
    IteratorBindingValueTaskResult(disposeAsync.InterfaceMethod.Invoke(first, empty))

    second := getAsyncEnumerator.InterfaceMethod.Invoke(boxed, invokeArguments)
    if second == null {
        throw new InvalidOperationException("Second GetAsyncEnumerator returned null")
    }
    assert Convert.ToBoolean(IteratorBindingValueTaskResult(moveNextAsync.InterfaceMethod.Invoke(second, empty)))
    assert Convert.ToInt32(genericCurrent.InterfaceMethod.Invoke(second, empty)) == 0
    IteratorBindingValueTaskResult(disposeAsync.InterfaceMethod.Invoke(second, empty))
}

test "generic and instance async iterators reach their exact emitter declines after accepted twins emit" {
    genericTwin := "import System.Collections.Generic\nimport System.Threading.Tasks\n\nasync func* IteratorBindingGenericTwin(value: int): IAsyncEnumerable<int> {\n    await Task.Delay(1)\n    yield value\n}\n"
    genericAsync := "import System.Collections.Generic\nimport System.Threading.Tasks\n\nasync func* IteratorBindingGenericAsync<T>(value: T): IAsyncEnumerable<T> {\n    await Task.Delay(1)\n    yield value\n}\n"
    instanceTwin := "import System.Collections.Generic\nimport System.Threading.Tasks\n\nasync func* IteratorBindingInstanceTwin(): IAsyncEnumerable<int> {\n    await Task.Delay(1)\n    yield 1\n}\n"
    instanceAsync := "import System.Collections.Generic\nimport System.Threading.Tasks\n\nclass IteratorBindingAsyncHost {\n    async func* InstanceAsync(): IAsyncEnumerable<int> {\n        await Task.Delay(1)\n        yield 1\n    }\n}\n"
    assert IteratorBindingEmitOutcome(genericTwin) == "success"
    assert IteratorBindingEmitOutcome(genericAsync) == "emit.iterator.async-unsupported|generic async iterator methods are not yet lowered|IteratorBindingGenericAsync"
    assert IteratorBindingEmitOutcome(instanceTwin) == "success"
    assert IteratorBindingEmitOutcome(instanceAsync) == "emit.iterator.async-unsupported|async member iterator methods are not yet lowered|IteratorBindingAsyncHost.InstanceAsync"
}

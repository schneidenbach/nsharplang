namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Reflection

func PrivateThreadStaticEmitRuntimeType(identity: string): Type {
    result := Type.GetType(identity)
    if result == null {
        throw new InvalidOperationException("Required ThreadStatic runtime type was not found: " + identity)
    }
    return result
}

func PrivateThreadStaticEmitSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func PrivateThreadStaticEmitRequiredMethod(owner: Type, name: string, parameterTypes: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameterTypes)
    if method == null {
        throw new InvalidOperationException("Required ThreadStatic method was not found: " + name)
    }
    return method
}

func PrivateThreadStaticEmitRequiredPrivateStaticField(name: string): FieldInfo {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(BindingFlags)
    getField := PrivateThreadStaticEmitRequiredMethod(typeof(Type), "GetField", parameterTypes)
    arguments := new object?[](2)
    PrivateThreadStaticEmitSetObject(arguments, 0, name)
    PrivateThreadStaticEmitSetObject(arguments, 1, (BindingFlags)40)
    field := getField.Invoke(typeof(PrivateThreadStaticEmitFacts), arguments) as FieldInfo
    if field == null {
        throw new InvalidOperationException("Private static field was not found: " + name)
    }
    return field
}

func PrivateThreadStaticEmitHasThreadStatic(field: FieldInfo): bool {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(Type)
    parameterTypes[1] = typeof(bool)
    isDefined := PrivateThreadStaticEmitRequiredMethod(typeof(MemberInfo), "IsDefined", parameterTypes)
    threadStaticType := PrivateThreadStaticEmitRuntimeType(
        "System.ThreadStaticAttribute, System.Private.CoreLib"
    )
    arguments := new object?[](2)
    PrivateThreadStaticEmitSetObject(arguments, 0, threadStaticType)
    PrivateThreadStaticEmitSetObject(arguments, 1, false)
    return Convert.ToBoolean(isDefined.Invoke(field, arguments))
}

func PrivateThreadStaticEmitRunThread(probe: PrivateThreadStaticEmitThreadProbe) {
    noParameters := new Type[](0)
    threadType := PrivateThreadStaticEmitRuntimeType("System.Threading.Thread, System.Private.CoreLib")
    threadStartType := PrivateThreadStaticEmitRuntimeType("System.Threading.ThreadStart, System.Private.CoreLib")
    delegateParameters := new Type[](3)
    delegateParameters[0] = typeof(Type)
    delegateParameters[1] = typeof(object)
    delegateParameters[2] = typeof(string)
    createDelegate := PrivateThreadStaticEmitRequiredMethod(
        typeof(Delegate),
        "CreateDelegate",
        delegateParameters
    )
    delegateArguments := new object?[](3)
    PrivateThreadStaticEmitSetObject(delegateArguments, 0, threadStartType)
    PrivateThreadStaticEmitSetObject(delegateArguments, 1, probe)
    PrivateThreadStaticEmitSetObject(delegateArguments, 2, "Run")
    callback := createDelegate.Invoke(null, delegateArguments)
    if callback == null {
        throw new InvalidOperationException("ThreadStatic worker callback was not created")
    }

    constructorParameters := new Type[](1)
    constructorParameters[0] = threadStartType
    constructor := threadType.GetConstructor(constructorParameters)
    if constructor == null {
        throw new InvalidOperationException("ThreadStatic Thread(ThreadStart) constructor was not found")
    }
    threadArguments := new object?[](1)
    PrivateThreadStaticEmitSetObject(threadArguments, 0, callback)
    thread := constructor.Invoke(threadArguments)
    if thread == null {
        throw new InvalidOperationException("ThreadStatic worker was not constructed")
    }

    start := PrivateThreadStaticEmitRequiredMethod(threadType, "Start", noParameters)
    join := PrivateThreadStaticEmitRequiredMethod(threadType, "Join", noParameters)
    invokeArguments := new object?[](0)
    started := start.Invoke(thread, invokeArguments)
    _ = started
    joined := join.Invoke(thread, invokeArguments)
    _ = joined
}

test "private static ThreadStatic fields retain exact visibility and attribute metadata" {
    counter := PrivateThreadStaticEmitRequiredPrivateStaticField("Counter")
    label := PrivateThreadStaticEmitRequiredPrivateStaticField("Label")
    sharedCounter := PrivateThreadStaticEmitRequiredPrivateStaticField("SharedCounter")

    assert counter.get_IsPrivate()
    assert counter.get_IsStatic()
    assert counter.get_FieldType() == typeof(int)
    assert PrivateThreadStaticEmitHasThreadStatic(counter)
    assert label.get_IsPrivate()
    assert label.get_IsStatic()
    assert label.get_FieldType() == typeof(string)
    assert PrivateThreadStaticEmitHasThreadStatic(label)
    assert sharedCounter.get_IsPrivate()
    assert sharedCounter.get_IsStatic()
    assert sharedCounter.get_FieldType() == typeof(int)
    assert !PrivateThreadStaticEmitHasThreadStatic(sharedCounter)
}

test "private static ThreadStatic fields isolate default and assigned values across a real worker thread" {
    PrivateThreadStaticEmitFacts.Reset()
    try {
        assert PrivateThreadStaticEmitFacts.CurrentCounter() == 0
        assert PrivateThreadStaticEmitFacts.CurrentLabel() == null
        assert PrivateThreadStaticEmitFacts.CurrentSharedCounter() == 0
        PrivateThreadStaticEmitFacts.Set(5, "main")
        PrivateThreadStaticEmitFacts.SetSharedCounter(5)

        probe := new PrivateThreadStaticEmitThreadProbe()
        PrivateThreadStaticEmitRunThread(probe)

        assert probe.Error == ""
        assert probe.InitialCounter == 0
        assert probe.InitialLabel == null
        assert probe.InitialSharedCounter == 5
        assert probe.Counter == 17
        assert probe.Label == "worker"
        assert probe.SharedCounter == 23
        assert PrivateThreadStaticEmitFacts.CurrentCounter() == 5
        assert PrivateThreadStaticEmitFacts.CurrentLabel() == "main"
        assert PrivateThreadStaticEmitFacts.CurrentSharedCounter() == 23
    } finally {
        PrivateThreadStaticEmitFacts.Reset()
    }
}

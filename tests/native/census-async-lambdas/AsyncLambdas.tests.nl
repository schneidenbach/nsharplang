namespace NSharpLang.CensusAsyncLambdas.Tests

import System
import System.Collections.Generic
import System.Reflection
import System.Threading.Tasks


// RUNTIME contracts for `async` lambdas. Every assertion here runs the emitted IL: the value the
// task carries, the family it is carried in, the exception that lands on it instead of on the
// caller, and the closure the body reads.
test "an async lambda with an expression body answers the task's result" {
    factory := expressionBodyFactory()
    assert await factory() == 7
}

test "an async lambda's parameters are contextually typed from the delegate" {
    doubling := doublingFactory()
    assert await doubling(21) == 42

    adding := addingFactory()
    assert await adding(3, 4) == 7
}

test "a block-bodied async lambda returns the task's result, not the task" {
    factory := blockBodyFactory()
    assert await factory() == 21
}

test "an async lambda on a unit-task delegate runs its body and completes" {
    log := new List<string>()
    unit := unitTaskFactory(log)
    await unit()
    assert log.Count == 1
    assert log[0] == "ran"
}

test "the task family is the target's decision" {
    valueTask := valueTaskFactory()
    assert await valueTask() == 9

    log := new List<string>()
    unitValueTask := unitValueTaskFactory(log)
    await unitValueTask()
    assert log.Count == 1
    assert log[0] == "unit value task"
}

test "an async lambda captures like an ordinary closure" {
    factory := capturingFactory(5)
    assert await factory() == 6

    counter := new Counter(41)
    next := counter.NextFactory()
    assert await next() == 42
}

test "each turn of a loop captures its own local" {
    factories := perIterationFactories()
    assert factories.Count == 3

    results := new List<int>()
    for factory in factories {
        results.Add(await factory())
    }

    assert results[0] == 0
    assert results[1] == 10
    assert results[2] == 20
}

test "an exception inside an async lambda lands on the returned task" {
    factory := faultingFactory()
    // Building the delegate raises nothing, and neither does invoking it: the body's exception is
    // captured by the task the invocation returns.
    task := factory()
    assert task.IsFaulted

    let caught: Exception? = null
    try {
        value := await task
        print value
    } catch e: Exception {
        caught = e
    }

    assert caught != null
    assert caught is InvalidOperationException
    assert caught.Message == "async lambda boom"
}

test "a bare throw inside an async lambda faults the task with the original trace" {
    factory := rethrowingFactory()
    task := factory()
    assert task.IsFaulted

    let caught: Exception? = null
    try {
        value := await task
        print value
    } catch e: Exception {
        caught = e
    }

    assert caught != null
    trace := caught.StackTrace ?? ""
    assert trace.Contains("failInside")
}

test "an async lambda passed to Task.Run takes the Func<Task> overload, never Action" {
    log := new List<string>()
    runOnThreadPool(log)
    assert log.Count == 1
    assert log[0] == "pool"
}

// CLR METADATA. An `async` lambda is lowered to a synthesized method whose signature is the
// DELEGATE's — the task is the return type, and the body's own result type appears nowhere in it.
test "the synthesized method returns the delegate's task, not the body's value" {
    factory := expressionBodyFactory()
    invoked: Delegate = factory
    method := invoked.Method
    assert method.ReturnType == typeof(Task<int>)
    assert method.GetParameters().Length == 0

    doubling := doublingFactory()
    doublingDelegate: Delegate = doubling
    doublingMethod := doublingDelegate.Method
    assert doublingMethod.ReturnType == typeof(Task<int>)
    assert doublingMethod.GetParameters().Length == 1
    assert doublingMethod.GetParameters()[0].ParameterType == typeof(int)

    valueTask := valueTaskFactory()
    valueTaskDelegate: Delegate = valueTask
    assert valueTaskDelegate.Method.ReturnType == typeof(ValueTask<int>)
}

test "a capturing async lambda is an instance method on a closure display" {
    factory := capturingFactory(5)
    captured: Delegate = factory
    assert captured.Target != null
    declaring := captured.Method.DeclaringType
    assert declaring != null
    assert declaring.Name.StartsWith("<>c__DisplayClass", StringComparison.Ordinal)
}

test "an async local function declares its inner type and returns the wrap" {
    assert localAsyncDoubling(21) == 42
    assert localAsyncCounting() == 3
}

test "an async local function's exception lands on the task it returns" {
    task := localAsyncFaulting()
    let caught: Exception? = null
    try {
        value := await task
        print value
    } catch e: Exception {
        caught = e
    }

    assert caught != null
    assert caught.Message == "local async boom"
}

test "an async local function's CLR method returns the wrapped task" {
    // The declared return is `int`; the emitted method's is `ValueTask<int>`, which is what every
    // call site sees. The method is found by the local-function naming convention.
    program := typeof(Counter).Assembly.GetType("NSharpLang.CensusAsyncLambdas.Tests.Program")
    assert program != null
    let found: MethodInfo? = null
    for method in program.GetMethods(BindingFlags.NonPublic | BindingFlags.Static) {
        if method.Name.StartsWith("<localAsyncDoubling>g__", StringComparison.Ordinal) {
            found = method
        }
    }

    assert found != null
    assert found.ReturnType == typeof(ValueTask<int>)
}

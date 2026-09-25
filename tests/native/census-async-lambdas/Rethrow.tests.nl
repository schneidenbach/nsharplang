namespace NSharpLang.CensusAsyncLambdas.Tests

import System
import System.Collections.Generic


// RUNTIME contracts for the bare `throw` — the rethrow. The observable difference between `throw`
// and `throw e` is the stack trace, so that is what these assert: a rethrow keeps the frame the
// exception was originally raised in, and re-raising the caught object by name does not.
test "a bare throw re-raises the caught exception with its original stack trace" {
    let caught: Exception? = null
    try {
        rethrowFromNamedCatch()
    } catch e: Exception {
        caught = e
    }

    assert caught != null
    trace := caught.StackTrace ?? ""
    assert trace.Contains("failInside")
}

test "throwing the caught exception by name resets the stack to the handler" {
    let caught: Exception? = null
    try {
        throwCaughtByName()
    } catch e: Exception {
        caught = e
    }

    assert caught != null
    trace := caught.StackTrace ?? ""
    assert !trace.Contains("failInside")
}

test "a bare catch has an exception to re-throw too" {
    let caught: Exception? = null
    try {
        rethrowFromBareCatch()
    } catch e: Exception {
        caught = e
    }

    assert caught != null
    assert caught is InvalidOperationException
    trace := caught.StackTrace ?? ""
    assert trace.Contains("failInside")
}

test "a try nested in the handler still re-throws the handler's exception, and its finally runs" {
    log := new List<string>()
    let caught: Exception? = null
    try {
        rethrowFromNestedTry(log)
    } catch e: Exception {
        caught = e
    }

    assert caught != null
    assert caught.Message.Contains("inner failure")
    assert log.Count == 1
    assert log[0] == "finally ran"
}

test "a finally wrapping the handler runs as the rethrown exception travels through it" {
    log := new List<string>()
    let caught: Exception? = null
    try {
        rethrowThroughFinally(log)
    } catch e: Exception {
        caught = e
    }

    assert caught != null
    assert log.Count == 1
    assert log[0] == "outer finally ran"
}

test "a bare throw in the inner of two handlers re-raises the inner exception" {
    assert rethrowInnerOfTwo() == "inner"
}

test "a rethrow re-raises the same exception object, not a copy" {
    assert rethrowPreservesIdentity()
}

test "a rethrow inside an async body faults the returned task and keeps the original trace" {
    task := rethrowFromAsync()
    let caught: Exception? = null
    try {
        task.GetAwaiter().GetResult()
    } catch e: Exception {
        caught = e
    }

    assert caught != null
    assert caught is InvalidOperationException
    trace := caught.StackTrace ?? ""
    assert trace.Contains("failInside")
}

test "a rethrow inside a generator body surfaces from the consuming loop" {
    seen := new List<int>()
    let caught: Exception? = null
    try {
        for n in rethrowFromGenerator() {
            seen.Add(n)
        }
    } catch e: Exception {
        caught = e
    }

    assert seen.Count == 1
    assert seen[0] == 11
    assert caught != null
    trace := caught.StackTrace ?? ""
    assert trace.Contains("failInside")
}

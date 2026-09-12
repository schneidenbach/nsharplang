namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Collections.Generic

test "a return inside a try with a finally is a return, and the value survives the finally" {
    log := new List<string>()
    values := TryFinallyReturnsValue(log)

    assert values.Count == 1
    assert values[0] == 1
    assert log.Count == 1
    assert log[0] == "finally"
}

test "the finally runs on the way out and cannot change the value already leaving" {
    log := new List<string>()

    assert FinallyRunsOnTheWayOut(log) == 42
    assert log.Count == 1
}

test "try/catch/finally returns from the guarded block and from the handler alike" {
    guardedLog := new List<string>()
    assert TryCatchFinallyReturns(false, guardedLog) == "guarded"
    assert guardedLog.Count == 1

    handlerLog := new List<string>()
    assert TryCatchFinallyReturns(true, handlerLog) == "handler:boom"
    assert handlerLog.Count == 1
}

test "returning out of nested protected regions runs every finally, innermost first" {
    log := new List<string>()

    assert NestedTryFinallyReturns(log) == 7
    assert log.Count == 2
    assert log[0] == "inner"
    assert log[1] == "outer"
}

test "a finally that leaves settles the statement even when the guarded block falls through" {
    log := new List<string>()
    threw := false
    try {
        _ = FinallyThatThrowsSettlesIt(log)
    } catch error: InvalidOperationException {
        threw = true
        assert error.Message == "from finally"
    }

    assert threw
    assert log.Count == 1
    assert log[0] == "guarded"
}

test "the hand-written using shape returns from inside the protected region and still disposes" {
    filled := new CountingResource("first")
    assert UsingShapeReturns(filled) == "first"
    assert filled.Disposals == 1

    empty := new CountingResource("")
    assert UsingShapeReturns(empty) == "<empty>"
    assert empty.Disposals == 1
}

test "a guarded block that falls through still needs its own trailing return" {
    log := new List<string>()

    assert GuardedBlockFallsThrough(log) == 5
    assert log.Count == 1
}

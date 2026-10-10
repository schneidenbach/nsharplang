namespace NSharpLang.AsyncGenericIterators.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks
import NSharpLang.AsyncIteratorFixtures

test "a generic async iterator function carries its method parameter into the machine" {
    sequence := LocalPending<string>("generic")
    boxed: object = sequence
    machineArguments := boxed.GetType().GetGenericArguments()
    assert machineArguments.Length == 1
    assert machineArguments[0] == typeof(string)

    joined := ""
    await foreach value in sequence {
        joined = joined + value
    }
    assert joined == "genericgeneric"
}

test "a generic async member carries enclosing and method parameters" {
    shelf := new GenericAsyncShelf<int>(12, "shelf")
    sequence := shelf.Echo<string>("method")
    boxed: object = sequence
    machineArguments := boxed.GetType().GetGenericArguments()
    assert machineArguments.Length == 2
    assert machineArguments[0] == typeof(int)
    assert machineArguments[1] == typeof(string)

    joined := ""
    await foreach value in sequence {
        joined = joined + value
    }
    assert joined == "methodmethod"
}

test "a generic enclosing type parameter flows through an async instance iterator" {
    shelf := new GenericAsyncShelf<int>(5, "shelf")
    sequence := shelf.Values()
    boxed: object = sequence
    machineArguments := boxed.GetType().GetGenericArguments()
    assert machineArguments.Length == 1
    assert machineArguments[0] == typeof(int)

    total := 0
    await foreach value in sequence {
        total = total * 10 + value
    }
    assert total == 55
}

test "generic async iterators are consumable across an assembly boundary" {
    joined := ""
    await foreach value in CrossPending<string>("external") {
        joined = joined + value
    }
    assert joined == "externalexternal"

    shelf := new CrossAsyncShelf<int>(3)
    genericMember := shelf.Stream<bool>(true)
    boxed: object = genericMember
    machineArguments := boxed.GetType().GetGenericArguments()
    assert machineArguments.Length == 2
    assert machineArguments[0] == typeof(int)
    assert machineArguments[1] == typeof(bool)

    observed := false
    count := 0
    await foreach value in genericMember {
        observed = value
        count = count + 1
    }
    assert observed
    assert count == 2
}

test "nested awaits in call arguments preserve written evaluation order" {
    events := new List<int>()
    values := new List<int>()
    await foreach value in NestedAwaitArguments(events) {
        values.Add(value)
    }
    assert events.Count == 2
    assert events[0] == 1
    assert events[1] == 2
    assert values.Count == 1
    assert values[0] == 12
}

test "an instance receiver is evaluated before arguments that await" {
    events := new List<int>()
    observed := 0
    await foreach value in AwaitInstanceReceiver(events) {
        observed = value
    }
    assert events.Count == 4
    assert events[0] == -1
    assert events[1] == 0
    assert events[2] == 1
    assert events[3] == 2
    assert observed == 11
}

test "awaits in conditions and binary operands preserve side-effect order" {
    events := new List<int>()
    values := new List<int>()
    await foreach value in NestedAwaitConditionAndBinary(events) {
        values.Add(value)
    }
    assert events.Count == 2
    assert events[0] == 3
    assert events[1] == 4
    assert values.Count == 1
    assert values[0] == 9
}

test "awaits in interpolation holes preserve written evaluation order" {
    events := new List<int>()
    observed := ""
    await foreach value in NestedAwaitInterpolation(events) {
        observed = value
    }
    assert events.Count == 2
    assert events[0] == 5
    assert events[1] == 6
    assert observed == "5:6"
}

test "a synchronous lock block is supported inside an async iterator" {
    events := new List<int>()
    gate := new object()
    observed := 0
    await foreach value in LockWithoutSuspension(gate, events) {
        observed = value
    }
    assert events.Count == 1
    assert events[0] == 1
    assert observed == 1
}

test "an await in the lock expression completes before the monitor is acquired" {
    events := new List<int>()
    gate := new object()
    observed := 0
    await foreach value in LockOnAwaitedExpression(gate, events) {
        observed = value
    }
    assert events.Count == 2
    assert events[0] == 9
    assert events[1] == 10
    assert observed == 2
}

test "an awaiting finally runs after a matching catch and preserves its side effects" {
    events := new List<int>()
    observed := 0
    await foreach value in AwaitFinallyWithCatch(events) {
        observed = value
    }
    assert events.Count == 3
    assert events[0] == 1
    assert events[1] == 2
    assert events[2] == 3
    assert observed == 11
}

test "an async iterator catch body can await before continuing" {
    events := new List<int>()
    observed := 0
    await foreach value in CatchWithAwait(events) {
        observed = value
    }
    assert events.Count == 3
    assert events[0] == 6
    assert events[1] == 7
    assert events[2] == 8
    assert observed == 7
}

test "an awaiting catch and finally run in order on normal completion" {
    events := new List<int>()
    observed := 0
    await foreach value in AwaitCatchAndFinallyNormal(events) {
        observed = value
    }
    assert events.Count == 6
    assert events[0] == 1
    assert events[1] == 2
    assert events[2] == 4
    assert events[3] == 7
    assert events[4] == 8
    assert events[5] == 9
    assert observed == 3
}

test "an awaiting catch handles the exception before the awaiting finally" {
    events := new List<int>()
    observed := 0
    await foreach value in AwaitCatchAndFinallyCaught(events) {
        observed = value
    }
    assert events.Count == 7
    assert events[0] == 11
    assert events[1] == 12
    assert events[2] == 13
    assert events[3] == 14
    assert events[4] == 15
    assert events[5] == 16
    assert events[6] == 17
    assert observed == 13
}

test "an exception rethrown from an awaiting catch reaches the consumer after finally" {
    events := new List<int>()
    caught := false
    try {
        await foreach value in AwaitCatchAndFinallyRethrown(events) {
        }
    } catch ex: InvalidOperationException {
        caught = true
        events.Add(28)
    }
    assert caught
    assert events.Count == 8
    assert events[0] == 21
    assert events[1] == 22
    assert events[2] == 23
    assert events[3] == 24
    assert events[4] == 25
    assert events[5] == 26
    assert events[6] == 27
    assert events[7] == 28
}

test "yield break from an awaiting catch still runs its awaiting finally" {
    events := new List<int>()
    await foreach value in AwaitCatchAndFinallyYieldBreak(events) {
        assert false
    }
    assert events.Count == 7
    assert events[0] == 31
    assert events[1] == 32
    assert events[2] == 33
    assert events[3] == 34
    assert events[4] == 35
    assert events[5] == 36
    assert events[6] == 37
}

test "nested awaiting catches and finally blocks unwind in lexical order" {
    events := new List<int>()
    observed := 0
    await foreach value in AwaitCatchAndFinallyNested(events) {
        observed = value
    }
    assert events.Count == 11
    assert events[0] == 41
    assert events[1] == 42
    assert events[2] == 43
    assert events[3] == 44
    assert events[4] == 45
    assert events[5] == 46
    assert events[6] == 47
    assert events[7] == 48
    assert events[8] == 52
    assert events[9] == 53
    assert events[10] == 54
    assert observed == 43
}

test "early DisposeAsync after an awaiting catch-finally try runs its outer finally once" {
    events := new List<int>()
    enumerator := AwaitCatchAndFinallyEarlyDispose(events).GetAsyncEnumerator()
    assert await enumerator.MoveNextAsync()
    assert enumerator.Current == 70

    await enumerator.DisposeAsync()

    assert events.Count == 11
    assert events[0] == 61
    assert events[1] == 63
    assert events[2] == 64
    assert events[3] == 65
    assert events[4] == 66
    assert events[5] == 67
    assert events[6] == 68
    assert events[7] == 69
    assert events[8] == 72
    assert events[9] == 73
    assert events[10] == 74
}

test "DisposeAsync rejects a MoveNextAsync still pending inside an awaiting try" {
    events := new List<int>()
    gate := new TaskCompletionSource<bool>()
    enumerator := AwaitCatchAndFinallyWhilePending(events, gate).GetAsyncEnumerator()
    pendingMove := enumerator.MoveNextAsync()
    assert !pendingMove.IsCompleted

    rejected := false
    try {
        await enumerator.DisposeAsync()
    } catch ex: NotSupportedException {
        rejected = true
    }
    assert rejected

    gate.SetResult(false)
    assert await pendingMove
    assert enumerator.Current == 82
    assert events.Count == 5
    assert events[0] == 75
    assert events[1] == 76
    assert events[2] == 79
    assert events[3] == 80
    assert events[4] == 81
}

test "ordinary async methods allow await in catch blocks" {
    assert await OrdinaryCatchAwait() == 12
}

test "ordinary async methods run awaiting catches and finally blocks" {
    normalEvents := new List<int>()
    assert await OrdinaryAwaitCatchAndFinally(normalEvents, false) == 72
    assert normalEvents.Count == 6
    assert normalEvents[0] == 71
    assert normalEvents[1] == 72
    assert normalEvents[2] == 73
    assert normalEvents[3] == 77
    assert normalEvents[4] == 78
    assert normalEvents[5] == 79

    caughtEvents := new List<int>()
    assert await OrdinaryAwaitCatchAndFinally(caughtEvents, true) == 75
    assert caughtEvents.Count == 7
    assert caughtEvents[0] == 71
    assert caughtEvents[1] == 74
    assert caughtEvents[2] == 75
    assert caughtEvents[3] == 76
    assert caughtEvents[4] == 77
    assert caughtEvents[5] == 78
    assert caughtEvents[6] == 79
}

test "ordinary async rethrows pass through the awaited finally" {
    events := new List<int>()
    caught := false
    try {
        await OrdinaryAwaitCatchAndFinallyRethrown(events)
    } catch ex: InvalidOperationException {
        caught = true
        events.Add(88)
    }
    assert caught
    assert events.Count == 8
    assert events[0] == 81
    assert events[1] == 82
    assert events[2] == 83
    assert events[3] == 84
    assert events[4] == 85
    assert events[5] == 86
    assert events[6] == 87
    assert events[7] == 88
}

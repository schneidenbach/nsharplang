namespace NSharpLang.AsyncGenericIterators.Tests

import System.Collections.Generic
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

test "ordinary async methods allow await in catch blocks" {
    assert await OrdinaryCatchAwait() == 12
}

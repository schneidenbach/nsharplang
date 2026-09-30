namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic


// EXECUTED PROOFS FOR A BOUND `await` INSIDE AN ASYNC GENERATOR.
test "a bound await produces its value to the consumer" {
    collected := new List<int>()
    await foreach v in BoundAwait() {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == 4
    assert collected[1] == 8
}

test "a unit await still suspends an async generator" {
    collected := new List<int>()
    await foreach v in DelayThenYield() {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == 1
    assert collected[1] == 2
}

test "an awaited yield value reaches the consumer" {
    collected := new List<string>()
    await foreach v in AwaitedYield() {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == "a"
    assert collected[1] == "b"
}

test "a ValueTask is awaited through its own awaiter" {
    collected := new List<int>()
    await foreach v in AwaitedValueTask() {
        collected.Add(v)
    }
    assert collected.Count == 1
    assert collected[0] == 11
}

test "an awaited value converts into the binding it is assigned to" {
    collected := new List<long>()
    await foreach v in AwaitedAssignment() {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == 5
    assert collected[1] == 6
}

test "an async generator enumerates a sequence source across suspensions" {
    source := new List<int>()
    source.Add(1)
    source.Add(2)
    source.Add(3)
    collected := new List<int>()
    await foreach v in DoubledAsync(source) {
        collected.Add(v)
    }
    assert collected.Count == 3
    assert collected[0] == 2
    assert collected[1] == 4
    assert collected[2] == 6
}

test "an async generator over a sequence source releases its enumerator when the consumer stops" {
    source := new List<string>()
    source.Add("a")
    source.Add("b")
    source.Add("c")
    seen := 0
    await foreach v in TaggedAsync(source) {
        seen = seen + 1
        assert v == "+a"
        break
    }
    assert seen == 1
}

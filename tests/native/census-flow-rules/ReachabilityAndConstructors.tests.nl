namespace NSharpLang.CensusFlowRules.Tests

import System

test "a while true whose only exit is a return needs no trailing return" {
    assert AttemptsUntilThreshold(1) == 1
    assert AttemptsUntilThreshold(4) == 4
}

test "a for whose condition is the constant true is the same statement" {
    assert ForeverLoopUntilThreshold(1) == 1
    assert ForeverLoopUntilThreshold(3) == 3
}

test "a while true whose only exit is a throw needs no trailing return" {
    assert throws InvalidOperationException {
        ThrowsFromForeverLoop()
    }
}

test "a break restores the end point, and the trailing return is the one that runs" {
    assert FirstMultipleOrZero(10, 4) == 4
    assert FirstMultipleOrZero(2, 7) == 0
}

test "a break bound to a nested loop does not restore the outer loop's end point" {
    values := new int[](3)
    values[0] = 1
    values[1] = 3
    values[2] = 2

    assert ClassifyUntilExhausted(values) == 6
}

test "a constructor accepts a bare return and stops running there" {
    forced := new Daemon("/tmp", true)

    assert forced.Root == "/tmp"
    assert forced.Running
    assert forced.Count == 0
}

test "a constructor without the early return runs to the end" {
    plain := new Daemon("/var", false)

    assert plain.Root == "/var"
    assert !plain.Running
    assert plain.Count == 1
}

test "a chained constructor assigns nothing of its own" {
    chained := new Daemon("/etc")

    assert chained.Root == "/etc"
    assert !chained.Running
    assert chained.Count == 1
}

test "value-typed fields are zero-initialized and owe the constructor nothing" {
    daemon := new Daemon("/srv", false)

    assert daemon.Kind == Channel.Primary
    assert daemon.Width == 0
    assert daemon.Debounce == null
}

test "an unconstrained type parameter field owes the constructor nothing" {
    numbers := new Box<int>("numbers")
    text := new Box<string>("text")

    assert numbers.Label == "numbers"
    assert numbers.Item == 0
    assert text.Label == "text"
    assert text.Item == null
}

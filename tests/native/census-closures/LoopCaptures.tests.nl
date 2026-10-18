namespace NSharpLang.CensusClosures.Tests

import System.Collections.Generic

test "a lambda passed to Exists can capture the for-in variable" {
    xs := new List<int>()
    xs.Add(1)
    xs.Add(2)
    xs.Add(9)
    ys := new List<int>()
    ys.Add(2)
    ys.Add(9)
    assert ExistsInLoop(xs, ys) == 2
}

test "a typed delegate local can capture the for-in variable" {
    xs := new List<int>()
    xs.Add(1)
    xs.Add(2)
    xs.Add(2)
    assert TypedLocalInLoop(xs) == 2
}

test "a lambda can capture the classic for variable" {
    ys := new List<int>()
    ys.Add(1)
    ys.Add(7)
    assert ClassicForExists(ys) == 1
}

test "each for-in iteration captures a fresh variable" {
    r := ForeachClosuresAfterLoop()
    assert r.Count == 3
    assert r[0] == 1
    assert r[1] == 2
    assert r[2] == 3
}

test "the classic for variable is one shared variable across iterations" {
    r := ClassicForClosuresAfterLoop()
    assert r.Count == 3
    assert r[0] == 3
    assert r[1] == 3
    assert r[2] == 3
}

test "a while counter that closures capture is one shared variable" {
    r := WhileCounterClosuresAfterLoop()
    assert r.Count == 3
    assert r[0] == 3
    assert r[2] == 3
}

test "an object initializer in a lambda can read a captured parameter or local" {
    assert InitializerCapture(7) == 7
    assert InitializerCaptureLocal() == 5
}

test "the same lambda works as an inline argument" {
    assert InitializerCaptureInline(10) == 12
}

test "a captured value can initialize an external type" {
    assert InitializerCaptureExternal(42) == 42
}

test "decrement and compound steps leave the classic for variable shared" {
    d := DecrementClosures()
    assert d.Count == 3
    assert d[0] == 0
    assert d[2] == 0
    c := CompoundAddClosures()
    assert c.Count == 3
    assert c[0] == 6
    assert c[2] == 6
    s := CompoundSubtractClosures()
    assert s.Count == 4
    assert s[0] == 0
    assert s[3] == 0
    p := PrefixIncrementClosures()
    assert p.Count == 3
    assert p[0] == 3
    assert p[2] == 3
}

test "a closure that writes the loop counter is seen by the loop" {
    assert ClosureMutatesCounter() == 6
}

test "closures before and after a counter write share its final storage" {
    r := SharedCounterAfterMutation()
    assert r.Count == 6
    for value in r {
        assert value == 10
    }
}

test "two loops may reuse a counter name" {
    r := SequentialLoopsSameName()
    assert r.Count == 4
    assert r[0] == 2
    assert r[1] == 2
    assert r[2] == 12
    assert r[3] == 12
}

test "a closure inside a closure reaches the shared counter" {
    r := ClosureInsideClosure()
    assert r.Count == 3
    assert r[0] == 103
    assert r[2] == 103
}

test "a for-in variable inside a classic for keeps its own value" {
    r := ForeachInsideClassicFor()
    assert r.Count == 4
    assert r[0] == 12
    assert r[1] == 22
    assert r[2] == 12
    assert r[3] == 22
}

test "a for-in body may assign its own loop variable before capturing it" {
    r := ForeachAssignsLoopVariable()
    assert r.Count == 3
    assert r[0] == 11
    assert r[1] == 12
    assert r[2] == 13
}

test "nested loops capture their respective counters" {
    r := NestedLoopClosures()
    assert r.Count == 4
    assert r[0] == 33
    assert r[1] == 33
    assert r[2] == 33
    assert r[3] == 33
}

test "out writes to a captured local remain visible to later closure reads" {
    assert CapturedOutResult() == 206
}

test "constructor arguments and anonymous objects inside a lambda capture" {
    assert InitializerConstructorCapture(7) == 7
    assert AnonymousObjectCapture(9) == 9
}

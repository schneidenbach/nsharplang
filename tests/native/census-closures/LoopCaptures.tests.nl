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

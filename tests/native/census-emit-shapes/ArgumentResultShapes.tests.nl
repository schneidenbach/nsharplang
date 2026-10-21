namespace NSharpLang.CensusEmitShapes.Tests

import System

test "mixed numeric and operator-result expressions are call arguments" {
    assert SineOfHalf(0.0) == 0.0
    assert Math.Abs(SineOfHalf(Math.PI) - 1.0) < 1e-12
    assert SineOfHalfText(3.0) == Math.Sin(3.0 / 2).ToString()

    d := new string[](1)
    d[0] = "a"
    assert SerializedByteCountNested(d) == 5

    a := new DateTime(2026, 1, 3)
    b := new DateTime(2026, 1, 1)
    assert AbsDays(a, b) == 2.0
    assert AbsDays(b, a) == 2.0
}

test "nested static calls with a mixed argument" {
    assert ClampedRatio(3.0, 4.0) == 0.75
    assert ClampedRatio(9.0, 4.0) == 1.0
    assert ClampedRatio(-1.0, 4.0) == 0.0
}

test "a lifted equality against a bool literal" {
    assert FlagIsTrue("{\"Flag\":true}")
    assert !FlagIsTrue("{\"Flag\":false}")
    assert !FlagIsTrue("{}")
    assert FlagIsFalse("{\"Flag\":false}")
    assert !FlagIsFalse("{}")
}

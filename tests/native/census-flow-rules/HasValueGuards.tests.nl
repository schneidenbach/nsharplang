namespace NSharpLang.CensusFlowRules.Tests

import System

func HasValueGuardReading(level: int): Reading {
    return new Reading { Level: level }
}

test "a `!x.HasValue` guard that THROWS leaves the unwrap and the bare name readable below it" {
    // Reported NL303 "Member 'Value' not found on type 'int'" before the test was a null fact.
    assert LengthOrThrow("abc") == 6

    thrown := false
    try {
        _ = LengthOrThrow("")
    } catch e: FormatException {
        thrown = true
    }

    assert thrown
}

test "a `!x.HasValue` guard that RETURNS narrows the surviving flow to the inner type" {
    assert LengthOrMinusOne("abcd") == 44
    assert LengthOrMinusOne("") == -1
}

test "a `!x.HasValue` guard that CONTINUES narrows the rest of the loop body" {
    assert SumPresentLengths(["a", "", "bbb", ""]) == 4
    assert SumPresentLengths(new string[0]) == 0
}

test "the positive branch and a conjunction read the value the test just proved" {
    assert LengthInBranch("ab") == 4
    assert LengthInBranch("") == 0
    assert LengthAboveOne("abc") == 103
    assert LengthAboveOne("a") == 0
    assert LengthAboveOne("") == 0
}

test "a disjunction of HasValue tests proves BOTH names past the guard" {
    assert SumOfBoth(2, 3) == 5
    assert SumOfBoth(null, 3) == -1
    assert SumOfBoth(2, null) == -1
}

test "a guard over a STRUCT nullable reads the unwrap and the struct's own member" {
    assert LevelOrZero(HasValueGuardReading(7)) == 14
    assert LevelOrZero(null) == 0
}

test "the guard keeps the DECLARED nullable, so the name can be written null afterwards" {
    // Reported NL202 "expected 'int' but got 'null'" when the guard rebound the name.
    assert !PresentThenCleared("abc").HasValue
    assert PresentThenCleared("") == 42
}

test "a HasValue test on a member PATH narrows the path" {
    assert LastOrMinusOne(new Gauge(5, null)) == 10
    assert LastOrMinusOne(new Gauge(null, null)) == -1
    assert PeakLevelOrMinusOne(new Gauge(null, HasValueGuardReading(9))) == 9
    assert PeakLevelOrMinusOne(new Gauge(null, null)) == -1
}

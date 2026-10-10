namespace NSharpLang.CensusFlowRules.Tests

import System

test "arithmetic on a narrowed nullable runs on the unwrapped value" {
    assert AddOneOrZero(41) == 42
    assert AddOneOrZero(null) == 0
}

test "a narrowed nullable returns from a non-nullable function" {
    assert UnwrapOrFallback(7) == 7
    assert UnwrapOrFallback(null) == -1
}

test "a member of a narrowed lifted named tuple reads its element" {
    let found: (Uri: string, Line: int)? = ("a.nl", 12)

    assert LineOrFallback(found) == 12
    assert UriOrFallback(found) == "a.nl"
    assert LineOrFallback(null) == -1
    assert UriOrFallback(null) == "none"
}

test "the positional spelling of the same read" {
    let pair: (string, int)? = ("b.nl", 5)

    assert SecondOrFallback(pair) == 5
    assert SecondOrFallback(null) == -1
}

test "the positive guard narrows the branch it guards" {
    assert DoubledWhenPresent(21) == 42
    assert DoubledWhenPresent(null) == 0
}

test "the else branch of a null test narrows the same way" {
    assert TripledOrZero(4) == 12
    assert TripledOrZero(null) == 0
}

test "an assert narrows everything after it" {
    assert AssertedPlusTen(5) == 15
}

test "an assert that fails throws instead of unwrapping" {
    assert throws InvalidOperationException {
        AssertedPlusTen(null)
    }
}

test "a HasValue guard proves what a null test proves" {
    assert HasValueThenSum(3, 4) == 7
    assert HasValueThenSum(null, 4) == -1
    assert HasValueThenSum(3, null) == -2
}

test "an or-guard proves both halves in the flow that survives it" {
    assert SumWhenBothPresent(10, 11) == 21
    assert SumWhenBothPresent(null, 11) == -1
    assert SumWhenBothPresent(10, null) == -1
}

test "a break guard narrows the rest of the loop body" {
    assert SumUntilAbsent(PresentThenAbsent()) == 3
}

test "a continue guard narrows the rest of the loop body" {
    assert SumPresentOnly(PresentThenAbsent()) == 7
}

test "a write ends the narrowing it invalidates" {
    assert ReassignedThenCoalesced(1, 8) == 8
    assert ReassignedThenCoalesced(1, null) == 99
}

test "the shapes that lower the nullable themselves stay legal after narrowing" {
    assert CoalescedAfterNarrowing(3) == 3
    assert CoalescedAfterNarrowing(null) == -1
    assert HasValueAfterNarrowing(3)
    assert !HasValueAfterNarrowing(null)
    assert ValueAfterNarrowing(9) == 9
    assert ValueAfterNarrowing(null) == -1
}

test "a narrowed value is an ordinary int as an argument and as an initializer" {
    assert TripledArgument(5) == 15
    assert TripledArgument(null) == 0
    assert StoredThenDoubled(6) == 12
    assert StoredThenDoubled(null) == 0
}

test "a loop body that writes the name loses the narrowing for the whole body" {
    assert AccumulateWithReset(2, 3) == 12
    assert AccumulateWithReset(null, 3) == -1
}

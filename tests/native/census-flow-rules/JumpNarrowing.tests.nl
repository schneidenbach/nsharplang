namespace NSharpLang.CensusFlowRules.Tests

test "continue past a null narrows the rest of the loop body" {
    items := new string?[](4)
    items[0] = "ab"
    items[1] = null
    items[2] = "cde"
    items[3] = null

    assert SumLengthsSkippingNulls(items) == 5
}

test "break past a null narrows the rest of the loop body and stops the loop" {
    items := new string?[](4)
    items[0] = "ab"
    items[1] = "cde"
    items[2] = null
    items[3] = "fghi"

    assert SumLengthsUntilNull(items) == 5
}

test "a jumping else branch narrows the flow that survives it" {
    items := new string?[](3)
    items[0] = "ab"
    items[1] = null
    items[2] = "c"

    assert SumLengthsWithJumpingElse(items) == 5
}

test "return still narrows, so the wider question did not lose the narrower one" {
    assert FirstLengthOrZero(null) == 0
    assert FirstLengthOrZero("abcd") == 4
}

test "a while loop guarded by break reads the narrowed value after the guard" {
    items := new string?[](3)
    items[0] = "first"
    items[1] = "second"
    items[2] = null

    assert LastNonNull(items) == "second"

    empty := new string?[](1)
    empty[0] = null
    assert LastNonNull(empty) == "<none>"
}

test "a break bound to a loop inside the branch does not escape the branch" {
    items := new string?[](3)
    items[0] = null
    items[1] = "x"
    items[2] = null

    assert CountNullsWithInnerBreak(items) == 2
}

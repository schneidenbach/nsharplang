namespace NSharpLang.CensusLiftedOperators.Tests

import System

test "a lifted ordering comparison answers FALSE when either operand is absent" {
    assert LessThan(2, 3)
    assert !LessThan(3, 2)
    assert !LessThan(null, 3)
    assert !LessThan(2, null)
    assert !LessThan(null, null)
}

test "all four orderings answer false on an absent operand, in both directions" {
    assert !LessOrEqual(null, 3)
    assert !GreaterThan(null, 3)
    assert !GreaterOrEqual(null, 3)
    assert !LessOrEqual(3, null)
    assert !GreaterThan(3, null)
    assert !GreaterOrEqual(3, null)
}

test "an absent operand makes an ordering and its negation-pair BOTH false at once" {
    // `a < b` and `a >= b` are both false, which is exactly why a lifted ordering cannot be read
    // as the negation of its opposite.
    assert NeitherOrder(null, 3)
    assert !NeitherOrder(2, 3)
    assert !NeitherOrder(3, 2)
}

test "a mixed lifted and plain ordering lifts the plain side in either position" {
    assert LessThanValue(2, 3)
    assert !LessThanValue(null, 3)
    assert ValueLessThan(2, 3)
    assert !ValueLessThan(2, null)
}

test "a lifted ordering over the wider scalars is the same rule" {
    assert GreaterThanDoubles(2.5, 1.5)
    assert !GreaterThanDoubles(null, 1.5)
    assert LessThanLongs(4000000000L, 4000000001L)
    assert !LessThanLongs(4000000000L, null)
}

test "a lifted ordering over an absent operand is still decided, so a comparison equal to true works" {
    assert (LessThan(null, 3) == false)
    assert (LessThan(2, 3) == true)
}

test "the lifted unary operators are absent in, absent out" {
    assert Negate(5) == -5
    assert Negate(null) == null
    assert NegateLong(4000000000L) == -4000000000L
    assert NegateLong(null) == null
    assert NegateDouble(1.5) == -1.5
    assert NegateDouble(null) == null
    assert Complement(0) == -1
    assert Complement(null) == null
    assert NotBoolean(true) == false
    assert NotBoolean(false) == true
    assert NotBoolean(null) == null
}

test "a CHECKED lifted negation throws on the one int that has no negation, and not on an absent one" {
    threw := false
    try {
        ignored := CheckedNegate(-2147483648)
        assert ignored == null
    } catch ex: OverflowException {
        threw = true
    }
    assert threw

    assert CheckedNegate(null) == null
    assert UncheckedNegate(-2147483648) == -2147483648
}

test "a lifted `++` and `--` step a present value and leave an absent one absent" {
    assert StepUp(4) == 5
    assert StepUp(null) == null
    assert StepDown(4) == 3
    assert StepDown(null) == null
}

test "a lifted postfix `++` still answers the value BEFORE the step" {
    assert StepUpKeepingOldValue(4) == 4
    assert StepUpKeepingOldValue(null) == null
}

test "a lifted compound assignment writes back a lifted answer" {
    assert CompoundAddValue(4, 3) == 7
    assert CompoundAddValue(null, 3) == null
    assert CompoundAddNullable(4, 3) == 7
    assert CompoundAddNullable(4, null) == null
    assert CompoundAddNullable(null, 3) == null
    assert CompoundMultiply(4, 3) == 12
    assert CompoundMultiply(null, 3) == null
    assert CompoundMultiply(4, null) == null
}

test "a narrowed read is NOT lifted a second time" {
    assert NarrowedSum(4) == 5
    assert NarrowedSum(null) == 0
    assert NarrowedComparison(2, 3)
    assert !NarrowedComparison(3, 2)
    assert !NarrowedComparison(null, 3)
}

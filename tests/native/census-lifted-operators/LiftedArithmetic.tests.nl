namespace NSharpLang.CensusLiftedOperators.Tests

import System


// RUNTIME CONTRACTS FOR C# §12.4.8's LIFTED ARITHMETIC, BITWISE AND SHIFT OPERATORS.
//
// Before this rule every one of these expressions was NL202 — "The '+' operator doesn't work with
// 'int?' and 'int'" — so the file COMPILING is half of each contract. The other half is the answer:
// an absent operand on EITHER side makes the whole result absent, and a present pair computes
// exactly what the unlifted operator computes.
test "a lifted sum is absent when either operand is absent and is the sum when neither is" {
    assert AddNullables(2, 3) == 5
    assert AddNullables(null, 3) == null
    assert AddNullables(2, null) == null
    assert AddNullables(null, null) == null
}

test "a mixed lifted and plain pair lifts the plain side, in both orders" {
    assert AddNullableAndValue(2, 3) == 5
    assert AddNullableAndValue(null, 3) == null
    assert AddValueAndNullable(2, 3) == 5
    assert AddValueAndNullable(2, null) == null
}

test "subtraction, multiplication, division and remainder lift the same way" {
    assert SubtractNullables(7, 3) == 4
    assert SubtractNullables(null, 3) == null
    assert MultiplyNullables(7, 3) == 21
    assert MultiplyNullables(7, null) == null
    assert DivideNullables(7, 3) == 2
    assert DivideNullables(null, 3) == null
    assert RemainderNullables(7, 3) == 1
    assert RemainderNullables(7, null) == null
}

test "division by a PRESENT zero still throws — only the presence test is lifted" {
    threw := false
    try {
        ignored := DivideNullables(7, 0)
        assert ignored == null
    } catch ex: DivideByZeroException {
        threw = true
    }
    assert threw
}

test "an absent operand is answered before the division happens, so nothing throws" {
    assert DivideNullables(null, 0) == null
}

test "a mixed-width lifted pair widens the narrower side" {
    assert AddLongAndInt(4000000000L, 7) == 4000000007L
    assert AddLongAndInt(null, 7) == null
    assert MultiplyDoubleAndInt(1.5, 4) == 6.0
    assert MultiplyDoubleAndInt(1.5, null) == null
    assert AddFloats(1.5f, 2.25f) == 3.75f
    assert AddFloats(null, 2.25f) == null
}

test "two lifted bytes promote to an int, exactly as two plain bytes do" {
    assert AddBytes(200, 100) == 300
    assert AddBytes(200, null) == null
}

test "the bitwise family lifts over the integral domain" {
    assert AndNullables(12, 10) == 8
    assert AndNullables(12, null) == null
    assert OrNullables(12, 10) == 14
    assert OrNullables(null, 10) == null
    assert XorNullables(12, 10) == 6
    assert XorNullables(12, null) == null
}

test "a lifted shift is worth the promotion of its VALUE operand alone" {
    assert ShiftLeftNullables(3, 4) == 48
    assert ShiftLeftNullables(null, 4) == null
    assert ShiftLeftNullables(3, null) == null
    assert ShiftRightNullables(-16, 2) == -4
    assert ShiftRightNullables(null, 2) == null
}

test "an unsigned lifted shift right is the UNSIGNED instruction" {
    assert ShiftRightUnsignedNullables(4294967232u, 2) == 1073741808u
    assert ShiftRightUnsignedNullables(null, 2) == null
}

test "a lifted operator in a CHECKED context still throws on a present overflow" {
    threw := false
    try {
        ignored := CheckedAdd(2147483647, 1)
        assert ignored == null
    } catch ex: OverflowException {
        threw = true
    }
    assert threw

    multiplied := false
    try {
        ignored2 := CheckedMultiply(2147483647, 2)
        assert ignored2 == null
    } catch ex: OverflowException {
        multiplied = true
    }
    assert multiplied
}

test "a CHECKED lifted operator with an absent operand throws nothing, because no arithmetic runs" {
    assert CheckedAdd(2147483647, null) == null
    assert CheckedAdd(null, 1) == null
    assert CheckedMultiply(null, 2) == null
}

test "an UNCHECKED lifted overflow wraps, exactly as the unlifted one does" {
    assert UncheckedAdd(2147483647, 1) == -2147483648
    assert UncheckedAdd(null, 1) == null
}

test "a lifted operator evaluates BOTH operands, left before right, even when the left is absent" {
    present := new OperandLog()
    assert LoggedSum(present, 2, 3) == 5
    assert present.Trace() == "left,right"

    absentLeft := new OperandLog()
    assert LoggedSum(absentLeft, null, 3) == null
    assert absentLeft.Trace() == "left,right"

    absentRight := new OperandLog()
    assert LoggedSum(absentRight, 2, null) == null
    assert absentRight.Trace() == "left,right"
}

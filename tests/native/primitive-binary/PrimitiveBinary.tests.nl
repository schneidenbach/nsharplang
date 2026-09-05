namespace NSharpLang.PrimitiveBinary.Tests

import System.Collections.Generic

test "integer arithmetic families execute through the product route" {
    arithmetic := IntArithmetic(10, 3)
    subtracted := IntSubtract(50, 8)
    multiplied := IntMultiply(6, 7)
    divided := IntDivide(84, 2)
    remainder := IntRemainder(142, 100)
    longResult := LongArithmetic(10L, 3L)
    chained := ArithmeticChain(6, 7, 5)
    assert arithmetic == 54
    assert subtracted == 42
    assert multiplied == 42
    assert divided == 42
    assert remainder == 42
    assert longResult == 28L
    assert chained == 41
}

test "unsigned division and remainder and wider numeric arithmetic execute correctly" {
    uintQuotient := UintDivide((uint)84, (uint)2)
    uintRemainder := UintRemainder((uint)142, (uint)100)
    ulongQuotient := UlongDivide((ulong)168, (ulong)4)
    doubleResult := DoubleArithmetic(4.0, 2.0)
    floatResult := FloatArithmetic(1.5f, 2.5f)
    charGap := CharDistance('d', 'a')
    decimalResult := DecimalArithmetic(6m, 4m)
    assert uintQuotient == (uint)42
    assert uintRemainder == (uint)42
    assert ulongQuotient == (ulong)42
    assert doubleResult == 8.0
    assert floatResult == 4.0f
    assert charGap == 3
    assert decimalResult == 24.5m
}

test "bitwise operators execute over the integral surface" {
    intResult := IntBitwise(46, 58)
    longResult := LongAnd(60L, 42L)
    uintResult := UintOr((uint)32, (uint)10)
    ulongResult := UlongXor((ulong)60, (ulong)22)
    assert intResult == 124
    assert longResult == 40L
    assert uintResult == (uint)42
    assert ulongResult == (ulong)42
}

test "shifts select signed and unsigned right shift opcodes" {
    leftShifted := IntLeftShift(21, 1)
    signedShifted := LongRightShift(168L, 2)
    unsignedShifted := UlongRightShift((ulong)168, 2)
    assert leftShifted == 42
    assert signedShifted == 42L
    assert unsignedShifted == (ulong)42
}

test "ordering comparisons produce correct Boolean results" {
    assert IntLess(1, 2)
    assert !IntLess(5, 2)
    assert IntLessEqual(2, 2)
    assert !IntLessEqual(3, 2)
    assert IntGreater(5, 2)
    assert IntGreaterEqual(2, 2)
    assert UintGreater((uint)50, (uint)8)
    assert DoubleLessEqual(2.0, 2.5)
    assert DoubleGreaterEqual(2.0, 2.0)
    assert CharLess('a', 'b')
    assert LongGreater(10L, 5L)
    assert DecimalLess(1m, 2m)

    zero := 0.0
    nan := zero / zero
    assert !DoubleLessEqual(nan, 2.5)
    assert !DoubleGreaterEqual(nan, 2.5)
}

test "equality and inequality execute across numeric Boolean char and string values" {
    assert IntEqual(42, 42)
    assert !IntEqual(42, 7)
    assert IntNotEqual(42, 7)
    assert !IntNotEqual(42, 42)
    assert BoolEqual(true, true)
    assert !BoolEqual(true, false)
    assert BoolNotEqual(true, false)
    assert DoubleEqual(42.0, 42.0)
    assert CharEqual('a', 'a')
    assert DecimalEqual(5m, 5m)
    assert StringEqual("same", "same")
    assert !StringEqual("left", "right")
}

test "string concatenation executes through the product route" {
    joined := StringConcat("left", "right")
    labelled := StringConcat("answer=", "42")
    assert joined == "leftright"
    assert labelled == "answer=42"
}

test "checked and unchecked forms compute non overflowing values" {
    checkedAdd := CheckedIntAdd(20, 22)
    checkedSubtract := CheckedIntSubtract(50, 8)
    checkedMultiply := CheckedIntMultiply(6, 7)
    uncheckedAdd := UncheckedIntAdd(20, 22)
    checkedUint := CheckedUintAdd((uint)20, (uint)22)
    checkedLong := CheckedLongMultiply(6L, 7L)
    assert checkedAdd == 42
    assert checkedSubtract == 42
    assert checkedMultiply == 42
    assert uncheckedAdd == 42
    assert checkedUint == (uint)42
    assert checkedLong == 42L
}

test "cast operands inside binaries execute through the product route" {
    assert UintLiteralEquals((uint)42)
    assert !UintLiteralEquals((uint)7)
    assert IntCharLiteralEquals(97)
    assert !IntCharLiteralEquals(98)
    assert LongCastAdd(41) == 42L
    assert UlongCastFromUint((uint)40) == (ulong)42
    assert UlongCastFromInt(40) == (ulong)42
    assert CharCastEquals(97)
    assert !CharCastEquals(98)
    assert ByteCastAdd(300) == 45
    assert SbyteCastAdd(41) == 42
    assert ShortCastMultiply(10) == 20
    assert DoubleCastLess(4)
    assert !DoubleCastLess(5)
    assert FloatCastAdd(2) == 3.5f
    assert IntCastTruncate(41.9) == 42
    assert UintCastNarrow(5L, (uint)5)
    assert !UintCastNarrow(6L, (uint)5)
}

test "decimal literal operands inside binaries execute through the product route" {
    assert DecimalLiteralEquals(24.5m)
    assert !DecimalLiteralEquals(24.25m)
    assert DecimalLiteralAdd() == 4.0m
    assert DecimalIntegerLiteralAdd() == 7m
    assert DecimalLiteralCompare(0.25m)
    assert !DecimalLiteralCompare(0.75m)
}

test "operators nested inside index and constructor expressions execute" {
    values := [10, 20, 30, 40, 50]
    summedIndex := IndexBySum(values, 1, 2)
    shiftedIndex := IndexByShift(values, 1)
    lastValue := IndexByLastOffset(values)
    boxed := BoxedSum(20, 22)
    sized := SizedArrayLength(6, 7)
    assert summedIndex == 40
    assert shiftedIndex == 30
    assert lastValue == 50
    assert boxed == 42
    assert sized == 42
}

test "bare sibling-function calls execute as binary operands through the product route" {
    assert SiblingEqualsLiteral()
    assert SiblingSumOfCalls(10) == 62
    assert SiblingCallLess(10)
    assert !SiblingCallLess(30)
    assert BoxedSiblingSum(9) == 60
    values := [0, 1, 2, 3, 4, 5, 6]
    assert IndexBySibling(values, 3) == 6
}

test "delegate invocation operands execute as binary comparisons through the product route" {
    fortyTwo: Func<int> = () => 42
    seven: Func<int> = () => 7
    add: Func<int, int> = n => n + 1
    assert DelegateEqualsAnswer(fortyTwo)
    assert !DelegateEqualsAnswer(seven)
    assert DelegateSumEquals(add, 41, 42)
    assert !DelegateSumEquals(add, 10, 42)
}

test "String.Join over a List of string executes as a concatenation operand" {
    tags := new List<string>()
    tags.Add("a")
    tags.Add("b")
    tags.Add("c")
    joined := PrefixedJoin("tags:", tags)
    assert joined == "tags:a,b,c"

    empty := new List<string>()
    emptyJoined := PrefixedJoin("tags:", empty)
    assert emptyJoined == "tags:"
}

test "List element field reads execute as binary equality operands" {
    items := new List<IndexItem>()
    items.Add(new IndexItem { Id: 10, Label: "x" })
    items.Add(new IndexItem { Id: 20, Label: "y" })
    items.Add(new IndexItem { Id: 30, Label: "z" })
    assert IndexItemIdMatches(items, 0, 10)
    assert IndexItemIdMatches(items, 1, 20)
    assert IndexItemIdMatches(items, 2, 30)
    assert !IndexItemIdMatches(items, 1, 99)
}

// Regression guard for the unary-minus boxing miscompile (2026-07-18): a `-84`-style literal
// passed directly in an object-typed argument position produced invalid IL in the CALLING
// method until the task-006 operand arcs landed. Cover every argument position that the
// original executor-shape call exercised, plus the hoisted-local control.
func BoxedProbe(_before: int, _value: object, _after: int): int {
    return 9
}

test "unary-minus literals box directly into object argument positions" {
    negative := -84
    assert BoxedProbe(1, -84, 2) == 9
    assert BoxedProbe(-84, -84, -84) == 9
    assert BoxedProbe(1, negative, 2) == 9
}

namespace NSharpLang.CensusConversions.Tests

// Every assertion below RUNS the emitted IL. A shift whose count was widened to 64 bits, a constant
// that adopted the wrong type, or an unsigned right shift emitted as a signed one would all still
// compile — only the values say which happened.
test "the bit-set idiom sets and reads the bit its index names" {
    words := new ulong[](4)

    SetBit(words, 0)
    SetBit(words, 63)
    SetBit(words, 64)
    SetBit(words, 200)

    assert words[0] == 9223372036854775809UL
    assert words[1] == 1UL
    assert words[3] == 256UL

    assert HasBit(words, 0)
    assert HasBit(words, 63)
    assert HasBit(words, 64)
    assert HasBit(words, 200)
    assert !HasBit(words, 1)
    assert !HasBit(words, 62)
    assert !HasBit(words, 199)
}

test "a shift count is an int under every left operand and every enclosing target" {
    assert ShiftIntoULong(0) == 1UL
    assert ShiftIntoULong(63) == 9223372036854775808UL
    assert ShiftIntoLong(62) == 4611686018427387904L
    assert ShiftIntoUInt(31) == 2147483648U
    assert ShiftIntoInt(30) == 1073741824

    // The count masks itself, so a count past the width wraps exactly as the CLR shift does.
    assert ShiftIntoULong(64) == 1UL
    assert ShiftByConstant() == 9223372036854775808UL
}

test "a ulong right shift is the unsigned one and a long right shift is not" {
    assert ShiftRightULong(9223372036854775808UL, 63) == 1UL
    assert ShiftRightULong(18446744073709551615UL, 60) == 15UL

    // The same bit pattern read as a `long` is negative, and its arithmetic shift keeps the sign.
    assert ShiftRightLong(-1L, 60) == -1L
    assert ShiftRightLong(1024L, 3) == 128L
}

test "an in-range integer constant adopts the other operand's type" {
    assert MaskHex(0x1234UL) == 0x34UL
    assert MaskHexInferred(0xFFUL)
    assert !MaskHexInferred(0xFEUL)
    assert MaskConstantOnLeft(0x1234UL) == 0x34UL
    assert MaskBinary(0x1234UL) == 0x34UL

    assert OrConstant(1UL) == 17UL
    assert XorConstant(0x11UL) == 1UL
    assert AddConstant(18446744073709551614UL) == 18446744073709551615UL
    assert CompoundAddConstant(10UL) == 13UL

    assert CompareConstant(6UL)
    assert !CompareConstant(5UL)
    assert EqualsConstant(1UL)
    assert !EqualsConstant(0UL)

    assert MaskUInt(0xFFFFU) == 0xF0U
    assert MaskLong(0x1234L) == 0x34L
    assert AddNegativeConstant(10L) == 9L
}

// The adopted constant must be the OPERAND's type and not a widened intermediate: a `ulong` mask of
// the high word only survives if the whole operation ran in 64 unsigned bits.
test "an adopted constant does not narrow the operation it joins" {
    high := 18446744073709551615UL

    assert MaskHex(high) == 255UL
    assert OrConstant(high) == high
    assert (high & 0xFFFFFFFFUL) == 4294967295UL
    assert CompareConstant(high)
}

// The emitted signatures are what a caller in another assembly sees, so the shift results must carry
// the LEFT operand's type rather than a promotion of the pair.
test "the emitted return types are the left operand's own and the counts stay int" {
    assert ReturnTypeOf("ShiftIntoULong") == typeof(ulong)
    assert ReturnTypeOf("ShiftIntoLong") == typeof(long)
    assert ReturnTypeOf("ShiftIntoUInt") == typeof(uint)
    assert ReturnTypeOf("ShiftIntoInt") == typeof(int)
    assert FirstParameterTypeOf("ShiftIntoULong") == typeof(int)
    assert FirstParameterTypeOf("ShiftIntoUInt") == typeof(int)

    // An adopted constant does not change the signature it joins either.
    assert ReturnTypeOf("MaskHex") == typeof(ulong)
    assert FirstParameterTypeOf("MaskHex") == typeof(ulong)
    assert ReturnTypeOf("MaskUInt") == typeof(uint)
    assert ReturnTypeOf("MaskConstantOnLeft") == typeof(ulong)
}

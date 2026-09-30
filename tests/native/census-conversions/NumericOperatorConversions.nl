namespace NSharpLang.CensusConversions.Tests

// CENSUS §CONV2/1 AND §CONV2/2 — A SHIFT COUNT IS AN `int`, AND AN INTEGER CONSTANT ADOPTS THE TYPE
// IT IS WRITTEN AGAINST.
//
// `okWords[i >> 6] | (1UL << (i & 63))` reported "The '&' operator doesn't work with 'int' and
// 'ulong'": the enclosing `ulong` target reached down into the SHIFT COUNT, typed `63` as a `ulong`,
// and made `i & 63` a pair with no common type. C# gives every shift operator an `int` right operand
// (§12.11) and takes the result from the LEFT operand alone, so the count is `int` whatever the
// expression is being written into.
//
// `mask & 0xFF` reported the same kind of thing from the other direction. Binary numeric promotion
// has no answer for `ulong` against a signed integral, which is right for two variables and wrong
// for a CONSTANT: §10.2.11 converts an in-range `int` constant to the other side's type, and only a
// non-constant operand is refused.
//
// The functions below are compiled by the tip compiler and EXECUTED by the tests beside them,
// because a shift whose count was typed as the wrong width and a constant that adopted the wrong
// type would both still compile once the type errors stopped.

// ── the bit-set idiom the census probe was drawn from ───────────────────
func SetBit(words: ulong[], index: int) {
    words[index >> 6] = words[index >> 6] | (1UL << (index & 63))
}

func HasBit(words: ulong[], index: int): bool {
    return (words[index >> 6] & (1UL << (index & 63))) != 0
}

// ── a shift count is an `int` under every enclosing target ──────────────

func ShiftIntoULong(count: int): ulong {
    return 1UL << (count & 63)
}

func ShiftIntoLong(count: int): long {
    return 1L << (count & 63)
}

func ShiftIntoUInt(count: int): uint {
    return 1U << (count & 31)
}

func ShiftIntoInt(count: int): int {
    return 1 << (count & 31)
}

// The count is a constant written under a `ulong` target: it is an `int`, so the shift is the
// ordinary `ulong << int` and not a pair with no common type.
func ShiftByConstant(): ulong {
    return 1UL << 63
}

// A right shift over a `ulong` is the UNSIGNED shift: the high bit zero-fills rather than
// sign-extending, which is the difference a `long` left operand would show.
func ShiftRightULong(value: ulong, count: int): ulong {
    return value >> count
}

func ShiftRightLong(value: long, count: int): long {
    return value >> count
}

// ── an integer constant adopts the type it is written against ───────────

func MaskHex(value: ulong): ulong {
    return value & 0xFF
}

// No enclosing target at all: the constant rule is the operator's own, not the assignment's.
func MaskHexInferred(value: ulong): bool {
    masked := value & 0xFF
    return masked == 255
}

func MaskConstantOnLeft(value: ulong): ulong {
    return 0xFF & value
}

func OrConstant(value: ulong): ulong {
    return value | 0x10
}

func XorConstant(value: ulong): ulong {
    return value ^ 0x10
}

func AddConstant(value: ulong): ulong {
    return value + 1
}

func CompareConstant(value: ulong): bool {
    return value > 5
}

func EqualsConstant(value: ulong): bool {
    return value != 0
}

func CompoundAddConstant(value: ulong): ulong {
    total := value
    total += 3
    return total
}

func MaskUInt(value: uint): uint {
    return value & 0xF0
}

func MaskLong(value: long): long {
    return value & 0xFF
}

// A binary literal and an underscore-separated one are the same constant expression as `255`; the
// rule is about the VALUE, not about how it was spelled.
func MaskBinary(value: ulong): ulong {
    return value & 0b1111_1111
}

// A NEGATIVE constant adopts a signed target and the unsigned ones refuse it, which is why this one
// is written against `long`.
func AddNegativeConstant(value: long): long {
    return value + -1
}

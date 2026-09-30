namespace NSharpLang.ScalarCodePlan.Tests

func ReturnIntLiteral(): int {
    return 2_147_483_647
}

func ReturnLongLiteral(): long {
    return 9223372036854775807L
}

func ReturnHexLiteral(): int {
    return 0x7fff_ffff
}

func ReturnBinaryLiteral(): int {
    return 0b1010_0101
}

func ReturnUnsignedLongLiteral(): ulong {
    return 18446744073709551615UL
}

func ReturnMinimumIntLiteral(): int {
    return -2147483648
}

func ReturnSeparatedMinimumIntLiteral(): int {
    return -2_147_483_648
}

func ReturnHexadecimalMinimumIntLiteral(): int {
    return -0x80000000
}

func ReturnBinaryMinimumIntLiteral(): int {
    return -0b10000000000000000000000000000000
}

func ReturnCheckedMinimumIntLiteral(): int {
    return checked(-2147483648)
}

func ReturnNegativeLongLiteral(): long {
    return -1L
}

func ReturnNegativeSingleLiteral(): float {
    return -1.25f
}

func ReturnNegativeZeroSingleLiteral(): float {
    return -0.0f
}

func ReturnNegativeDecimalLiteral(): decimal {
    return -1.25m
}

func ReturnComplementIntLiteral(): int {
    return ~0
}

func ReturnComplementUnsignedLiteral(): ulong {
    return ~0UL
}

func ReturnComplementLongLiteral(): long {
    return ~1L
}

func ReturnLogicalNotLiteral(): bool {
    return !true
}

func ReturnDoubleLiteral(): double {
    return 1.25
}

func ReturnExplicitDoubleLiteral(): double {
    return 1_2.5_0e1D
}

func ReturnSingleLiteral(): float {
    return 6.25e-1F
}

func ReturnNegativeDoubleLiteral(): double {
    return -6.25E-1d
}

func ReturnNegativeZeroDoubleLiteral(): double {
    return -0.0
}

func ReturnRoundedSingleLiteral(): float {
    return 1.0000000596046448f
}

func ReturnMaximumFiniteDoubleLiteral(): double {
    return 1.7976931348623157e308
}

func ReturnOverflowDoubleLiteral(): double {
    return 1e9999
}

func ReturnNegativeOverflowDoubleLiteral(): double {
    return -1e9999
}

func ReturnMaximumFiniteSingleLiteral(): float {
    return 3.4028234e38f
}

func ReturnOverflowSingleLiteral(): float {
    return 3.5e38f
}

func ReturnCharacterLiteral(): char {
    return '\n'
}

func ReturnOrdinaryStringLiteral(): string {
    return "line\nquote\"slash\\"
}

func ReturnTripleStringLiteral(): string {
    value := """
slash\n
"""
    return value
}

// A RAW LITERAL IS AN EXPRESSION IN EVERY POSITION, NOT ONLY AN INITIALIZER, AND THESE TWO
// FUNCTIONS ARE THE CHECK-CLEAN CONTRACT FOR IT. `ParserTokenFacts.CanStartExpression` did not list
// `TripleQuoteStringLiteral`, so `return """…"""` parsed as a bare `return` plus a stray expression
// statement (NL305 + NL312 + NL006) and `"a" + """b"""` was refused at the missing-operand boundary.
// The existing contract above reaches the literal through a LOCAL, which is exactly why it never
// caught either. This project is compiled by the product build, so it fails to BUILD if the row is
// ever dropped again — a stronger statement than any assertion about the value.
func ReturnTripleStringLiteralDirect(): string {
    return """direct"""
}

func ConcatTripleStringLiteral(): string {
    return "a" + """b"""
}

func ReadTenFromEnd(values: int[]): int {
    return values[^1_0]
}

test "scalar code plans supply exact function return values" {
    assert ReturnIntLiteral() == 2147483647
    assert ReturnLongLiteral() == 9223372036854775807L
    assert ReturnHexLiteral() == 2147483647
    assert ReturnBinaryLiteral() == 165
    assert ReturnUnsignedLongLiteral() == 18446744073709551615LU
    assert ReturnMinimumIntLiteral() == -2147483648
    assert ReturnSeparatedMinimumIntLiteral() == -2147483648
    assert ReturnHexadecimalMinimumIntLiteral() == -2147483648
    assert ReturnBinaryMinimumIntLiteral() == -2147483648
    assert ReturnCheckedMinimumIntLiteral() == -2147483648
    assert ReturnNegativeLongLiteral() == -1L
    assert ReturnNegativeSingleLiteral() == -1.25f
    negativeZeroSingle := ReturnNegativeZeroSingleLiteral()
    assert negativeZeroSingle == 0.0f
    assert 1.0f / negativeZeroSingle < 0.0f
    assert ReturnNegativeDecimalLiteral() == -1.25m
    assert ReturnComplementIntLiteral() == -1
    assert ReturnComplementUnsignedLiteral() == 18446744073709551615UL
    assert ReturnComplementLongLiteral() == -2L
    assert !ReturnLogicalNotLiteral()
    assert ReturnDoubleLiteral() == 1.25
    assert ReturnExplicitDoubleLiteral() == 125.0
    assert ReturnSingleLiteral() == 0.625f
    assert ReturnNegativeDoubleLiteral() == -0.625
    assert 1.0 / ReturnNegativeZeroDoubleLiteral() < 0.0
    assert ReturnRoundedSingleLiteral() == 1.0f
    assert ReturnOverflowDoubleLiteral() > ReturnMaximumFiniteDoubleLiteral()
    assert ReturnNegativeOverflowDoubleLiteral() < -ReturnMaximumFiniteDoubleLiteral()
    assert ReturnOverflowSingleLiteral() > ReturnMaximumFiniteSingleLiteral()
    assert ReturnCharacterLiteral() == '\n'
    assert ReturnOrdinaryStringLiteral() == "line\nquote\"slash\\"
    assert ReturnTripleStringLiteral() == "\nslash\\n\n"
    assert ReturnTripleStringLiteralDirect() == "direct"
    assert ConcatTripleStringLiteral() == "ab"
}

test "range code plans recursively consume the shared underscored scalar owner" {
    values := [0, 1, 20, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    assert ReadTenFromEnd(values) == 20
}

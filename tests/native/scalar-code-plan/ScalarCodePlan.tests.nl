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

func ReadTenFromEnd(values: int[]): int {
    return values[^1_0]
}

test "scalar code plans supply exact function return values" {
    assert ReturnIntLiteral() == 2147483647
    assert ReturnLongLiteral() == 9223372036854775807L
    assert ReturnHexLiteral() == 2147483647
    assert ReturnBinaryLiteral() == 165
    assert ReturnUnsignedLongLiteral() == 18446744073709551615LU
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
}

test "range code plans recursively consume the shared underscored scalar owner" {
    values := [0, 1, 20, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    assert ReadTenFromEnd(values) == 20
}

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
    assert ReturnCharacterLiteral() == '\n'
    assert ReturnOrdinaryStringLiteral() == "line\nquote\"slash\\"
    assert ReturnTripleStringLiteral() == "\nslash\\n\n"
}

test "range code plans recursively consume the shared underscored scalar owner" {
    values := [0, 1, 20, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    assert ReadTenFromEnd(values) == 20
}

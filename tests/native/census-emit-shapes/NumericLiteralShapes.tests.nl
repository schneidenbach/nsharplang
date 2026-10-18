namespace NSharpLang.CensusEmitShapes.Tests

test "an unsuffixed integer literal takes the first of int, uint, long, ulong that holds it" {
    assert UnsuffixedIntLiteral() == 2147483647
    assert UnsuffixedLongMask() == 4294967295L
    assert UnsuffixedUlongMask() == 18446744073709551615UL
    assert UnsuffixedUintLiteral() == 2147483647U
    assert UnsuffixedLongLiteral() == 5000000001L
    assert UnsuffixedUlongLiteral() == 9223372036854775808UL
}

test "unary minus recognizes the C sharp int and long minimum literals" {
    assert NegatedIntMinimum() == int.MinValue
    assert NegatedIntMinimumTargetTyped() == int.MinValue
    assert NegatedLongMinimum() == long.MinValue
    assert NegatedLongMinimumWithSuffix() == long.MinValue
    assert NegatedIntNearMinimum() == -2147483647
    assert SelectIntMinimumOverload() == "int"
    assert SelectLongMinimumOverload() == "long"
}

namespace NSharpLang.CensusEmitShapes.Tests

test "an overloaded member binds from a NARROWED nullable receiver" {
    assert CompareNarrowed(3, 2) == 1
    assert CompareNarrowed(2, 2) == 0
    assert CompareNarrowed(1, 2) == -1
    assert CompareNarrowed(null, 2) == -2
    assert DescribeNarrowed(7) == "7"
    assert DescribeNarrowed(null) == "none"
}

test "an overloaded member binds from a parenthesised or indexed receiver" {
    assert CompareParenthesised(1, 2) == 0
    assert CompareParenthesised(5, 2) == 1
    assert CompareIndexed([7], 8) == -1
    assert CompareLong(9, 9) == 0
}

test "the overload is chosen by the ARGUMENT's type, not by arity alone" {
    // `string.IndexOf` has a `char` overload and a `string` one. Picking by arity could only have
    // refused; picking by the argument type answers both.
    assert IndexOfChar("a", "bc") == 1
    assert IndexOfString("a", "bc") == 1
    assert IndexOfChar("zz", "ab") == 3
}

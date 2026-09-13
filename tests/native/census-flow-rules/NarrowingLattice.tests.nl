namespace NSharpLang.CensusFlowRules.Tests

test "an && reaches a parenthesised operand and narrows through it" {
    assert ParenthesisedOperandLength("ab", "cde") == 3
    assert ParenthesisedOperandLength(null, "cde") == -1
    assert ParenthesisedOperandLength("ab", null) == -1
    assert ParenthesisedOperandLength("", "cde") == -1
}

test "a negated guard narrows the flow that survives it" {
    assert NegatedGuardLength("abcd") == 4
    assert NegatedGuardLength(null) == -1
}

test "a doubly negated guard narrows the same way" {
    assert DoubleNegatedGuardLength("abcd") == 4
    assert DoubleNegatedGuardLength(null) == -1
}

test "a ternary narrows the arm its condition proved" {
    assert TernaryLength("abc") == 3
    assert TernaryLength(null) == -1
}

test "a ternary narrows its ELSE arm from the false side of the condition" {
    assert TernaryElseArmLength("abcd") == 4
    assert TernaryElseArmLength(null) == -1
}

test "a ternary condition that is an && narrows both names in the then arm" {
    assert TernaryNestedLength("ab", "cde") == 5
    assert TernaryNestedLength(null, "cde") == -1
    assert TernaryNestedLength("ab", null) == -1
}

test "a null-conditional chain compared against null narrows the whole chain" {
    assert DocumentTextLength(new Document("hello")) == 5
    assert DocumentTextLength(new Document(null)) == -1
    assert DocumentTextLength(null) == -1
}

test "a null-conditional chain compared as not-null narrows inside the branch" {
    assert DocumentTextLengthWhenPresent(new Document("hey")) == 3
    assert DocumentTextLengthWhenPresent(new Document(null)) == -1
    assert DocumentTextLengthWhenPresent(null) == -1
}

test "Nullable's own members bind on an un-narrowed nullable value type" {
    assert LengthOrDefault("abc") == 3
    assert LengthOrDefault(null) == 0
    assert LengthOrFallback("abc", 9) == 3
    assert LengthOrFallback(null, 9) == 9
    assert LengthIsPresent("abc")
    assert !LengthIsPresent(null)
}

test "Nullable's own members still bind after a sound narrowing" {
    assert NarrowedLengthValue("abcde") == 5
    assert NarrowedLengthValue(null) == -1
    assert NarrowedLengthUnwrapped("abcde") == 5
    assert NarrowedLengthUnwrapped(null) == -1
}

test "a narrowed nullable used as its inner type is unwrapped by the emitter" {
    assert NarrowedLengthPlusOne("abc") == 4
    assert NarrowedLengthPlusOne(null) == -1
    assert NarrowedLengthUnwrappedPlusOne("abcd") == 5
    assert NarrowedLengthUnwrappedPlusOne(null) == -1
}

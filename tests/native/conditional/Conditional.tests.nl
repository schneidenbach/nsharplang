namespace NSharpLang.Conditional.Tests

test "boolean short-circuit AND truth table executes through the product route" {
    assert And(true, true)
    assert !And(true, false)
    assert !And(false, true)
    assert !And(false, false)
    assert AndPersisted(true, true)
    assert !AndPersisted(true, false)
}

test "boolean short-circuit OR truth table executes through the product route" {
    assert Or(true, true)
    assert Or(true, false)
    assert Or(false, true)
    assert !Or(false, false)
    assert OrPersisted(false, true)
    assert !OrPersisted(false, false)
}

test "nested short-circuit respects operator precedence" {
    assert AndThenOr(true, true, false)
    assert !AndThenOr(true, false, false)
    assert AndThenOr(false, false, true)
    assert !AndThenOr(false, true, false)
}

test "short-circuit AND evaluates the right operand only when the left is true" {
    assert AndRightEvaluations(false) == 0
    assert AndRightEvaluations(true) == 101
}

test "short-circuit OR evaluates the right operand only when the left is false" {
    assert OrRightEvaluations(true) == 100
    assert OrRightEvaluations(false) == 1
}

test "ternary selects the matching arm for both value and reference types" {
    assert SelectByBoth(true, true, 7, 9) == 7
    assert SelectByBoth(true, false, 7, 9) == 9
    assert MaxOfTwo(3, 8) == 8
    assert MaxOfTwo(11, 4) == 11
    assert Label(true) == "yes"
    assert Label(false) == "no"
}

test "nested ternary inside a short-circuit operand" {
    assert NestedTernaryInAnd(true, true, false, true)
    assert !NestedTernaryInAnd(true, false, true, true)
    assert !NestedTernaryInAnd(false, true, false, true)
    assert !NestedTernaryInAnd(true, true, false, false)
}

test "ternary drives a recursive range-index selector" {
    assert SelectElement(true) == 10
    assert SelectElement(false) == 20
}

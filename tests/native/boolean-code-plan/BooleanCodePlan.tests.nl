namespace NSharpLang.BooleanCodePlan.Tests

func Identity(value: bool): bool {
    return value
}

func LiteralReturn(): bool {
    return true
}

func Select(value: bool): int {
    if value {
        return 1
    }
    return 0
}

test "boolean code plans emit both literal values" {
    assert true
    assert !false
}

test "boolean code plans supply typed call arguments" {
    assert Identity(true)
    assert !Identity(false)
}

test "boolean code plans supply function return values" {
    assert LiteralReturn()
}

test "boolean code plans participate in conditional typing" {
    assert Select(true) == 1
    assert Select(false) == 0
}

test "boolean code plans preserve conditional-expression result types" {
    choose := true
    assert (choose ? true : false)

    choose = false
    assert !(choose ? true : false)
}

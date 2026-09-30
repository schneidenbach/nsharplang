namespace NSharpLang.CensusEmitShapes.Tests

test "a local annotated with an element-nullable array type parses and emits" {
    values: string[] = ["alpha", "beta"]
    assert WidenElements(values) == 2
}

test "the widened view reads the same elements" {
    widened: string?[] = ["alpha", null, "beta"]
    assert CountNonNull(widened) == 2
    assert ElementsOrEmpty(widened) == "alpha-beta"
}

test "a nullable array reference is the other spelling and stays distinct" {
    values: string[] = ["alpha"]
    assert NullableArrayLocal(values) == 1
}

test "a loop variable wears the same annotation" {
    first: string?[] = ["alpha", null]
    second: string?[] = [null, "beta", "gamma"]
    rows: string?[][] = [first, second]
    assert FirstNonNull(rows) == 3
}

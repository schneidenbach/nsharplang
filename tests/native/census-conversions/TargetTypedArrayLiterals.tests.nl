namespace NSharpLang.CensusConversions.Tests

// Each element read back by VALUE, because a literal that converted its elements wrongly would have
// the right length and the wrong contents.
func BoxedInt(value: int): object {
    boxed: object = value
    return boxed
}

test "a target element type converts every element of a literal" {
    local := FromAnnotatedLocal()
    assert local.Length == 4
    assert local[0].Equals("local")
    assert local[1].Equals(BoxedInt(1))
    assert local[3] == null

    // The nested literal is itself an array, reached through the covariant conversion the outer
    // target's element type asks for.
    nested := local[2] as string[]
    assert nested != null
    assert nested.Length == 1
    assert nested[0] == "nested"
}

test "every position that names an element type target-types its literal" {
    fromReturn := FromReturn()
    assert fromReturn.Length == 4
    assert fromReturn[0].Equals("return")

    assert FromArgument() == 4
    assert FromArgumentFirst().Equals("argument")

    fromField := FromField()
    assert fromField.Length == 3
    assert fromField[0].Equals("field")
    assert fromField[1].Equals(BoxedInt(2))
    assert fromField[2] == null
}

test "a lone array literal in a params position is the params array itself" {
    // Three elements, not one element that happens to be a three-element array — the normal form,
    // which is what C# picks for a collection expression in a params position.
    assert FromParamsLiteral() == 3
    assert FromParamsExpanded() == 2

    // The same reading for a `string[]` argument, which reaches `object[]` by covariance: two
    // elements rather than one array wrapped in a one-element array.
    names := new string[](2)
    names[0] = "a"
    names[1] = "b"
    assert FromParamsStringArray(names) == 2
}

test "a literal with no target still infers from its first element" {
    assert InferredElementTypeName() == "System.Int32[]"
}

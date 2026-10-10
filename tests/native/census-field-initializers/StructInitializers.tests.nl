namespace NSharpLang.CensusFieldInitializers.Tests

test "a struct's field initializers run in its declared constructor" {
    measured := new Measured(9)
    assert measured.Scale == 7
    assert measured.Label == "ab"
    assert measured.Value == 9
}

test "a struct value that reaches no constructor keeps the CLR zero" {
    zero: Measured = default
    assert zero.Scale == 0
    assert zero.Label == null
    assert zero.Value == 0
}

test "a struct's primary constructor runs both the parameter captures and the computed initializers" {
    sized := new Sized(3, 4)
    assert sized.Width == 3
    assert sized.Area == 12
    assert sized.Doubled == 10
}

test "a record struct runs its field initializers in its primary constructor" {
    span := new Span2D(6)
    assert span.Length == 6
    assert span.Doubled == 12
}

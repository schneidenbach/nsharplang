namespace NSharpLang.CensusEmitShapes.Tests

test "a conditional over an interpolated string and a string is a string, in both arms" {
    blank := Outcome(3, "   ")
    assert !blank.Item1
    assert blank.Item2 == "exited 3"
    reported := Outcome(3, "boom")
    assert reported.Item2 == "boom"
    assert Describe(true, "name") == "<name>"
    assert Describe(false, "name") == "name"
}

test "a conditional whose arms differ only in nullability is the nullable one" {
    assert Maybe(true, "a", null) == "a"
    assert Maybe(false, "a", null) == null
    assert Maybe(false, "a", "b") == "b"
}

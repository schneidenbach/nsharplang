namespace NSharpLang.ErasedEnumIdentity.Tests

enum Selection: string {
    Value = "enum"
}

type Text = string

// A bare sibling-function call supplying a construction argument for an erased string alias.
func FillCharacter(): char {
    return 'y'
}

test "runtime aliases never acquire a source enum identity through CLR erasure" {
    value := new Text('x', 1 + 2)

    assert value == "xxx"
}

test "sibling-function calls flow into erased-alias construction arguments" {
    value := new Text(FillCharacter(), 1 + 2)

    assert value == "yyy"
}

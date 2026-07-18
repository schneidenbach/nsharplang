namespace NSharpLang.ErasedEnumIdentity.Tests

enum Selection: string {
    Value = "enum"
}

type Text = string

test "runtime aliases never acquire a source enum identity through CLR erasure" {
    value := new Text('x', 1 + 2)

    assert value == "xxx"
}

namespace NSharpLang.ExternalHiddenMembers.Tests

test "a property redeclared with new answers the most derived declaration" {
    assert typedOptionsContext() == "Db"
}

test "the derived property is the one passed where its own type is required" {
    assert contextFromHiddenOptions()
}

test "the base builder and a base-typed view still answer the base declaration" {
    assert baseOptionsContext() == "DbContext"
    assert baseSpelledOptionsContext() == "Db"
}

test "ToString is available through EF Core's interface-typed model" {
    description := modelDescription()
    assert description.Length > 0
    assert description.Contains("Model")
}

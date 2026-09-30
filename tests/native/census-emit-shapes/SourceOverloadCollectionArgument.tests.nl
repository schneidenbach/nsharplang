namespace NSharpLang.CensusEmitShapes.Tests

test "a collection expression with no common element type selects the source overload that accepts it" {
    assert MixedStatic() == "object:3"
    assert MixedInstance(new Sink()) == "object:3"
}

test "a literal whose elements DO have a common type still selects that overload" {
    assert TypedStatic() == "int:3"
}

namespace NSharpLang.CensusEmitShapes.Tests

test "an object initializer of an external struct is a call argument" {
    assert ExternalStructInitializerArgument() == 6
    assert ExternalStructInitializerTrailingCommaArgument() == 2
}

test "a source struct initializer is an argument, return value, and nested value" {
    assert SourceStructInitializerArgument() == 7
    point := SourceStructInitializerReturn()
    assert point.X == 5
    assert point.Y == 6
    segment := NestedStructInitializer()
    assert segment.From.X == 1
    assert segment.From.Y == 2
    assert segment.To.X == 3
    assert segment.To.Y == 4
    assert StructInitializerAfterOtherArguments() == 5
}

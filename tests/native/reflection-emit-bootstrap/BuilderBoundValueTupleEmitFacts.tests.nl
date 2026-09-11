namespace NSharpLang.ReflectionEmitBootstrap.Tests

test "builder-bound ValueTuple job shapes construct and retain every field" {
    assert BuilderBoundValueTupleEmitFacts.RetainsConstructionAndFields()
}

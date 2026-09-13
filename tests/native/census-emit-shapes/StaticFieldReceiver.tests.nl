namespace NSharpLang.CensusEmitShapes.Tests

test "a bare static field is a call receiver in statement position, and the call really mutates it" {
    Registry.Reset()
    Registry.Record("alpha")
    Registry.Record("beta")
    assert Registry.Total() == 2
    assert Registry.Joined() == "alpha,beta"
    Registry.Reset()
    assert Registry.Total() == 0
}

test "a bare static field is an indexer receiver too" {
    Registry.Reset()
    Registry.RecordCount("alpha", 3)
    assert Registry.Counts["alpha"] == 3
    Registry.Reset()
    assert Registry.Counts.Count == 0
}

test "a static member is in scope from an instance body of the declaring type" {
    Registry.Reset()
    Registry.Record("alpha")
    registry := new Registry()
    assert registry.Describe() == "registry:1"
    Registry.Reset()
}

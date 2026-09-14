namespace NSharpLang.CensusEmitShapes.Tests

test "a bare static field is a call receiver from a static body" {
    Registry.Clear()
    Registry.Add("alpha")
    Registry.Add("beta")
    assert Registry.Total() == 2
    assert Registry.Has("alpha")
    assert !Registry.Has("gamma")
}

test "the type-qualified spelling reaches the same storage" {
    Registry.Clear()
    Registry.Qualified("alpha")
    assert Registry.Total() == 1
    assert Registry.Has("alpha")
}

test "an instance body names the same static receiver" {
    Registry.Clear()
    registry := new Registry()
    registry.AddFromInstance("alpha")
    assert Registry.Total() == 1
    assert Registry.Has("alpha")
}

test "a static property is a call receiver too" {
    Registry.Clear()
    Registry.Tag("one")
    Registry.Tag("two")
    assert Registry.TagCount() == 2
}

test "a static member inherited from the base is a receiver in the derived body" {
    DerivedCounter.Reset()
    DerivedCounter.Record(1)
    DerivedCounter.Record(2)
    DerivedCounter.Record(3)
    assert DerivedCounter.SeenCount() == 3
}

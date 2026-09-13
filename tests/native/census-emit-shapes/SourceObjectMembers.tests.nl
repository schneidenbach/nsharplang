namespace NSharpLang.CensusEmitShapes.Tests

test "GetType on a typed source receiver names the runtime type" {
    thing := new Thing { Name: "alpha" }
    assert TypeNameOf(thing) == "Thing"
    assert TypeNameOf(thing) == BoxedTypeNameOf(thing)
}

test "a derived instance through a base-typed binding names the derived type" {
    named := new Named { Name: "beta" }
    assert TypeNameOf(named) == "Named"
    assert BoxedTypeNameOf(named) == "Named"
}

test "the same call from inside the type reads the argument's runtime type" {
    thing := new Thing { Name: "alpha" }
    named := new Named { Name: "beta" }
    assert thing.Describe(thing) == "Thing:alpha"
    assert thing.Describe(named) == "Named:beta"
}

test "this reaches the object members the type inherits" {
    thing := new Thing { Name: "alpha" }
    named := new Named { Name: "beta" }
    assert thing.OwnTypeName() == "Thing"
    assert named.OwnTypeName() == "Named"
    assert thing.OwnHash() == thing.GetHashCode()
    assert thing.IsSelf(thing)
    assert !thing.IsSelf(named)
}

test "the inherited object members agree with the boxed spelling" {
    thing := new Thing { Name: "alpha" }
    assert HashesAgree(thing)
}

test "a source struct receiver is boxed for an inherited object member" {
    extent := new Extent { Width: 2, Height: 3 }
    assert TypeNameOfStruct(extent) == "Extent"
    assert StructuralToString(extent).Contains("Extent")
}

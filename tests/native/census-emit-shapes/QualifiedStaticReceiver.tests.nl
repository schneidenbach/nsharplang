namespace NSharpLang.CensusEmitShapes.Tests

import System
import System.Collections.Generic
import System.IO

func QualifiedStaticsScratchDirectory(): string {
    return Path.Combine(Path.GetTempPath(), "nsharp-qualified-static-" + Guid.NewGuid().ToString("N"))
}

test "a fully-qualified static receiver with a must-unwrapped argument runs the call" {
    path := QualifiedStaticsScratchDirectory()
    try {
        assert QualifiedStatics.MakeDirectory(path) == path
        assert QualifiedStatics.DirectoryExists(path)
    } finally {
        QualifiedStatics.DeleteDirectory(path)
    }
    assert !QualifiedStatics.DirectoryExists(path)
}

test "a must unwrap that fails inside a qualified static call throws the pipeline message" {
    caught: InvalidOperationException? = null
    try {
        _ = QualifiedStatics.DirectoryExists(null)
    } catch failure: InvalidOperationException {
        caught = failure
    }
    assert caught != null
    assert caught.Message == "must unwrap failed: value was null"
}

test "a qualified static receiver takes an argument that is not a bare name" {
    assert QualifiedStatics.Joined("alpha", "beta") == "alpha-beta"
    assert QualifiedStatics.Describe("gamma") == "<gamma>"
}

test "a must argument is typed, so it chooses the overload its unwrapped type names" {
    assert QualifiedStatics.LargerInt(7) == 7
    assert QualifiedStatics.LargerInt(1) == 3
    assert QualifiedStatics.LargerDouble(4.25) == 4.25

    // The chosen overloads are the int and double ones, not one widened pair.
    assert (QualifiedStatics.LargerInt(7) as object).GetType() == typeof(int)
    assert (QualifiedStatics.LargerDouble(4.25) as object).GetType() == typeof(double)
}

test "a qualified generic static closes on the type argument written in front of it" {
    empty := QualifiedStatics.EmptyInts()
    assert empty.Length == 0
    assert (empty as object).GetType() == typeof(int[])

    values := new List<int>()
    values.Add(1)
    values.Add(2)
    values.Add(3)
    assert QualifiedStatics.CountQualified(values) == 3
}

test "a namespace-qualified source type is a static receiver too" {
    assert QualifiedHelperCaller.Through(21) == 42
}

test "a generic extension reaches through an external property hop in its receiver chain" {
    source := new Dictionary<string, object>()
    source["a"] = "one"
    source["b"] = 2
    source["c"] = "three"

    assert ChainedGenericExtensionCallers.ValuesThroughParameter(source) == 2
    assert ChainedGenericExtensionCallers.KeysThroughParameter(source) == 3
}

test "the inline hop and the same hop stored in a local answer alike" {
    source := new Dictionary<string, object>()
    source["a"] = "one"
    source["b"] = 2

    assert ChainedGenericExtensionCallers.ValuesThroughParameter(source) == ChainedGenericExtensionCallers.ValuesThroughLocal(source)
    assert ChainedGenericExtensionCallers.ValuesThroughLocal(source) == 1
}

test "a chain that starts at a source type's own property reaches the external hop behind it" {
    owner := new ChainedGenericExtensions()
    _ = owner.Add("a", "one").Add("b", 2).Add("c", "three")

    assert owner.StringValueCount() == 2
    assert owner.KeyCount() == 3
    assert ChainedGenericExtensionCallers.ThroughSourceOwner(owner) == 2
}

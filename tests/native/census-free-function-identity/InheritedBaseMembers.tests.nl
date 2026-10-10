namespace Census.FreeFunctionIdentity.Tests

import System.Collections.Generic
import Census.FreeFunctionIdentity.Inherited

test "a bare call to a closed external base's member answers what the this-qualified call answers" {
    names := new Names()
    names.Add("abc")
    names.Add("de")

    bare: string = names.FirstBare()
    qualified: string = names.FirstViaThis()
    assert bare == "abc"
    assert qualified == "abc"
    assert names.PositionBare("de") == 1
}

test "a lambda passed bare takes its parameter type from the external base's argument" {
    names := new Names()
    names.Add("abc")
    names.Add("de")

    lengths := names.LengthsBare()
    assert lengths.Count == 2
    assert lengths[0] == 3
    assert lengths[1] == 2
    assert names.LengthsViaThis()[1] == 2
    assert names.LengthCountBare() == 2
    assert names.HasPairBare()
    assert names.HasPairViaThis()

    // The same generic method through a receiver OUTSIDE the type: `TOutput` is still the lambda's.
    outside := names.ConvertAll(s => s.Length + 1)
    assert outside[0] == 4
}

test "a generic source base between the type and the external base is substituted" {
    deep := new Deep()
    deep.Add("mixed")
    deep.Add("other")

    assert deep.FirstBare() == "mixed"
    assert deep.FirstViaThis() == "mixed"
    assert deep.ShoutBare() == "MIXED"
    assert deep.Count == 2
}

test "a nullable argument on the external base makes the bare read nullable" {
    maybe := new MaybeNames()
    maybe.Add(null)
    assert maybe.FirstOrEmptyBare() == "<none>"

    named := new MaybeNames()
    named.Add("first")
    assert named.FirstOrEmptyBare() == "first"
}

test "a static member of the external generic base, named bare, binds the base's argument" {
    comparer := new ByLength().LongestFirstBare()
    words := new List<string>()
    words.Add("a")
    words.Add("ccc")
    words.Add("bb")
    words.Sort(comparer)

    assert words[0] == "ccc"
    assert words[1] == "bb"
    assert words[2] == "a"
}

test "a base closed over a source type binds bare calls, lambda arguments included" {
    tags := new Tags()
    tags.AddBare("red")
    tags.Add(new Tag("blue"))

    assert tags.FirstBare().Label == "red"
    assert tags.HasBare("blue")
    assert !tags.HasBare("green")
    assert tags.HasViaThis("red")
    assert tags.Exists(tag => tag.Label == "blue")
}

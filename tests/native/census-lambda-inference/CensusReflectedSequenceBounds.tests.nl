namespace NSharpLang.CensusLambdaInference.Tests

import System.Collections.Generic


// ── a lambda result read off a reflected member fixes the output type parameter ───────────────
test "SelectMany over a member declared on a source type flattens its sequence" {
    first := new List<string>()
    first.Add("a")
    first.Add("b")
    second := new List<string>()
    second.Add("c")

    bundles := new List<Bundle>()
    bundles.Add(SourceBundle(first))
    bundles.Add(SourceBundle(second))

    flattened := EditsOf(bundles)
    assert flattened.Count == 3
    assert flattened[0] == "a"
    assert flattened[1] == "b"
    assert flattened[2] == "c"
}

test "SelectMany over a REFLECTED sequence fixes the same type parameter" {
    first := new List<string>()
    first.Add("x")
    second := new List<string>()
    second.Add("y")
    second.Add("z")

    flattened := WordsOf(ReflectedBundles(first, second))
    assert flattened.Count == 3
    assert flattened[0] == "x"
    assert flattened[1] == "y"
    assert flattened[2] == "z"
}

test "a reflected member reached only through its interface list still fixes the element" {
    left := new Dictionary<string, int>()
    left["one"] = 1
    right := new Dictionary<string, int>()
    right["two"] = 2

    tables := new List<Dictionary<string, int>>()
    tables.Add(left)
    tables.Add(right)

    keys := KeysOf(tables)
    assert keys.Count == 2
    assert keys.Contains("one")
    assert keys.Contains("two")
}

test "the element type the flatten produced is the real one, not a widened stand-in" {
    rows := new List<string>()
    rows.Add("alpha")

    flattened := WordsOf(ReflectedBundles(rows, new List<string>()))

    // A `string` member on the flattened element: it compiles only because `TResult` really is
    // `string`, and it runs because the emitted call closed over the same answer.
    assert flattened[0].Length == 5
    assert flattened[0].ToUpperInvariant() == "ALPHA"

    counts := LengthsOf(BundlesOf(rows))
    assert counts.Count == 1
    assert counts[0] == 1
}

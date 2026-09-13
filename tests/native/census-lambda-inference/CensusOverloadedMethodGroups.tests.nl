namespace NSharpLang.CensusLambdaInference.Tests

import System.Collections.Generic


// ── an overloaded method group whose output type parameter is still open ──────────────────────
test "the overload the delegate's inputs select is the one whose return fixes the output" {
    widened := Widen.Longs([1, 2, 3])
    assert widened.Length == 3
    assert widened[0] == 10
    assert widened[2] == 30

    // A `long` member on the element: the call's own type is `long[]`, which is what the selected
    // overload's RETURN type decided.
    assert widened[1].ToString() == "20"
}

test "the same group under a different receiver selects a different overload" {
    words := new List<string>()
    words.Add("alpha")
    words.Add("be")

    lengths := Widen.Lengths(words)
    assert lengths.Count == 2
    assert lengths[0] == 5
    assert lengths[1] == 2
}

test "an overloaded predicate group resolves the same way" {
    kept := Filters.Longer([0, 1, 2, 3])
    assert kept.Length == 2
    assert kept[0] == 2
    assert kept[1] == 3

    words := new List<string>()
    words.Add("a")
    words.Add("bb")
    words.Add("ccc")
    keptWords := Filters.LongerWords(words)
    assert keptWords.Count == 2
    assert keptWords[0] == "bb"
    assert keptWords[1] == "ccc"
}

test "selecting an overload for a delegate leaves the group itself untouched" {
    assert Filters.KeptDirectly("ab")
    assert !Filters.KeptDirectly("a")
}

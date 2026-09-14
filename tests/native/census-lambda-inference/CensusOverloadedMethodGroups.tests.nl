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

test "an overloaded group on an instance receiver binds that receiver's overload" {
    words := new List<string>()
    words.Add("a")
    words.Add("bb")

    described := DescribeAll(new Greeter("n:"), words)
    assert described.Count == 2
    assert described[0] == "n:a"
    assert described[1] == "n:bb"

    // A second receiver answers from its own state, which is what makes the delegate bound rather
    // than static.
    other := DescribeAll(new Greeter("m:"), words)
    assert other[0] == "m:a"

    // The overload the position did not select is still callable by its own name.
    assert DescribeCountDirectly(new Greeter("n:"), 7) == "n:7"
}

// ── an overloaded group read off a RECEIVER, at an INSTANCE method's inferring position ───────
test "an overloaded receiver group binds the output type parameter of an instance method too" {
    words := new List<string>()
    words.Add("ann")
    words.Add("bo")
    greeter := new Greeter("hi ")

    described := DescribeAllByConvert(greeter, words)
    assert described.GetType() == typeof(List<string>)
    assert described.Count == 2
    assert described[0] == "hi ann"
    assert described[1] == "hi bo"

    lengths := DescribedLengths(greeter, words)
    assert lengths[0] == 6
    assert lengths[1] == 5
}

test "the storage's declared delegate selects among a receiver group's overloads" {
    // `Func<int, string>` picks `Describe(count: int)`, which no `List<string>` position could.
    shape := DescribeCountAsDelegate(new Greeter("n"))
    assert shape(7) == "n7"
}

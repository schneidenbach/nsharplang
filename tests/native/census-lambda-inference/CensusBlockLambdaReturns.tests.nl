namespace NSharpLang.CensusLambdaInference.Tests

import System.Collections.Generic


// ── a block-bodied lambda at a position that is still open ────────────────────────────────────
test "a block lambda's `return` decides the call's type argument, and the call really runs" {
    spans := SpansOf(SampleNames())
    assert spans.GetType() == typeof(List<Span2>)
    assert spans.Count == 2
    assert spans[0].Start == 5
    assert spans[0].End == 6
    assert spans[1].Start == 2
    assert spans[1].End == 3
}

test "every `return` the block executes takes part, wherever it is written" {
    scores := ScoresOf(SampleNames())
    assert scores.GetType() == typeof(List<int>)
    assert scores[0] == 1
    assert scores[1] == 0

    rows := new List<List<string>>()
    first := new List<string>()
    first.Add("ab")
    first.Add("abcd")
    rows.Add(first)
    rows.Add(new List<string>())

    found := FirstLongIndexIn(rows)
    assert found[0] == 1
    assert found[1] == -1
}

test "a `null` arm takes the type the other arms agree on" {
    names := new List<string>()
    names.Add("be")
    names.Add("")

    upper := UpperOrNull(names)
    assert upper.GetType() == typeof(List<string>)
    assert upper[0] == "BE"
    assert upper[1] == null
}

test "two arms that are not the same type join at what they share" {
    starts := SpansOrMarkers(SampleNames())
    assert starts.GetType() == typeof(List<int>)
    assert starts[0] == 5
    assert starts[1] == 0
}

test "two REFLECTED arms join at their shared base, which emission could not see before" {
    lengths := StreamLengths(BothFlags())
    assert lengths.GetType() == typeof(List<long>)
    assert lengths[0] == 3
    assert lengths[1] == 0
}

test "a nested lambda's returns are its own" {
    lengths := NestedInnerLengths(SampleNames())
    assert lengths.GetType() == typeof(List<int>)
    assert lengths[0] == 6
    assert lengths[1] == 3
}

test "a block body at a position that was never open keeps working" {
    long := LongNames(SampleNames())
    assert long.Count == 1
    assert long[0] == "alpha"
}

// ── the same question for a generic THIS compilation declares ─────────────────────────────────
test "a block lambda closes a SOURCE generic's open return position too" {
    spans := MappedSpans(SampleNames())
    assert spans.GetType() == typeof(List<Span2>)
    assert spans.Count == 2
    assert spans[0].Start == 5
    assert spans[1].End == 3

    lengths := MappedLengths(SampleNames())
    assert lengths.GetType() == typeof(List<int>)
    assert lengths[0] == 5
    assert lengths[1] == 2
}

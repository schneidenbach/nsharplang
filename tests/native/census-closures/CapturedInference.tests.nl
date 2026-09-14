namespace NSharpLang.CensusClosures.Tests

import System.Collections.Generic

test "a lambda that captures a parameter still binds the generic output type" {
    xs := new List<int>()
    xs.Add(1)
    xs.Add(2)

    bumped := BumpAll(xs, 10)
    assert bumped.Count == 2
    assert bumped[0] == 11
    assert bumped[1] == 12

    fromLocal := BumpAllFromLocal(xs)
    assert fromLocal[0] == 4
    assert fromLocal[1] == 5
}

test "the inferred output type is the one the captured value produces" {
    xs := new List<int>()
    xs.Add(1)
    xs.Add(2)

    labelled := LabelAll(xs, "n")
    assert labelled.Count == 2
    assert labelled[0] == "n1"
    assert labelled[1] == "n2"

    scaled := ScaleAll(xs, 10)
    assert scaled[0] == 11
    assert scaled[1] == 21
}

test "a lambda nested at an inferring position reaches the outer lambda's parameter" {
    xs := new List<int>()
    xs.Add(1)
    xs.Add(2)
    ys := new List<int>()
    ys.Add(0)
    ys.Add(2)
    ys.Add(5)

    counts := CountGreater(xs, ys)
    assert counts.Count == 2
    // Greater than 1: 2 and 5. Greater than 2: 5 alone.
    assert counts[0] == 2
    assert counts[1] == 1
}

test "the instance and a captured parameter both reach an inferring position" {
    totals := new Totals(3)
    xs := new List<int>()
    xs.Add(1)
    xs.Add(2)
    weighted := totals.Weighted(xs, 10)
    assert weighted[0] == 13
    assert weighted[1] == 16
}

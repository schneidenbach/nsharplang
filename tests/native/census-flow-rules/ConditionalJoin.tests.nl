namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic

test "the TryGetValue-or-create idiom compiles and indexes both the missing and the present key" {
    locations := new Dictionary<string, List<int>>()

    AddLine(locations, "a", 1)
    AddLine(locations, "a", 2)
    AddLine(locations, "b", 7)

    assert locations.Count == 2
    assert locations["a"].Count == 2
    assert locations["a"][0] == 1
    assert locations["a"][1] == 2
    assert locations["b"].Count == 1
    assert locations["b"][0] == 7
}

test "the mirror — an empty then-branch and the creation in the else — indexes the same way" {
    locations := new Dictionary<string, List<int>>()

    AddLineFromElse(locations, "a", 1)
    AddLineFromElse(locations, "a", 2)
    AddLineFromElse(locations, "b", 7)

    assert locations.Count == 2
    assert locations["a"].Count == 2
    assert locations["b"][0] == 7
}

test "the null-check spelling reads the value the branch created, and the one it was given" {
    existing := new List<int>()
    existing.Add(4)
    existing.Add(5)

    assert CountOrEmpty(null) == 0
    assert CountOrEmpty(existing) == 2
}

test "two assigning branches join to not-null whichever one ran" {
    first := new List<int>()
    first.Add(1)
    second := new List<int>()
    second.Add(2)
    second.Add(3)

    assert ChooseList(true, first, second) == 1
    assert ChooseList(false, first, second) == 2
}

test "an else-if chain joins across all three of its branches" {
    first := new List<int>()
    first.Add(1)
    second := new List<int>()
    second.Add(2)
    second.Add(3)
    third := new List<int>()

    assert ChooseFromChain(0, first, second, third) == 1
    assert ChooseFromChain(1, first, second, third) == 2
    assert ChooseFromChain(2, first, second, third) == 0
}

test "a guard clause still hands the surviving flow the branch it did not take" {
    values := new List<int>()
    values.Add(9)

    assert FirstOrZero(null) == 0
    assert FirstOrZero(values) == 1
}

test "a while loop that fell out of the bottom proves its condition was false" {
    fallback := new List<int>()
    fallback.Add(1)
    fallback.Add(2)
    source := new List<int>()

    assert FillUntilPresent(null, fallback) == 2
    assert FillUntilPresent(source, fallback) == 0
}

test "a for loop exit carries the same fact a while exit does" {
    fallback := new List<int>()
    fallback.Add(1)
    fallback.Add(2)
    fallback.Add(3)
    source := new List<int>()
    source.Add(8)

    assert FillWithCounter(null, fallback) == 3
    assert FillWithCounter(source, fallback) == 1
}

test "a stable property path joins exactly as a local does" {
    index := new LineIndex()

    assert RecordLine(index, 10) == 1
    assert RecordLine(index, 11) == 2

    lines := index.Lines
    assert lines != null
    if lines != null {
        assert lines[0] == 10
        assert lines[1] == 11
    }
}

test "a branch that assigns a maybe-null value leaves the join maybe-null" {
    fallback := new List<int>()
    fallback.Add(1)
    present := new List<int>()
    present.Add(2)
    present.Add(3)

    // `CanUse(null)` is false, so the then-branch runs and assigns the maybe-null input.
    assert CountOrFallback(null, fallback) == -1
    // `CanUse(present)` is true, so the else-branch runs and assigns the fallback.
    assert CountOrFallback(present, fallback) == 1
}

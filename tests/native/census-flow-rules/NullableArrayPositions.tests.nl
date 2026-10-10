namespace NSharpLang.CensusFlowRules.Tests

import System

test "an element-nullable array annotates a LOCAL, not only a parameter" {
    values := new string?[](3)
    values[0] = "a"
    values[2] = "c"
    assert CountPresentLabels(values) == 2

    counts := new int?[](3)
    counts[0] = 4
    counts[2] = 6
    assert SumPresentCounts(counts) == 10
}

test "an ARRAY-nullable annotation is the other spelling and keeps its own meaning" {
    rows: string[]? = ["a", "b"]
    assert LengthOrZero(rows) == 2
    assert LengthOrZero(null) == 0
}

test "both spellings survive a generic argument" {
    values := new string?[](2)
    values[1] = "b"
    collected := CollectOptionalNames(values)
    assert collected.Count == 2
    assert collected[0] == null
    assert collected[1] == "b"

    counts := new int?[](2)
    counts[0] = 7
    map := IndexOptionalCounts(counts)
    assert map.Count == 2
    assert map[0] == 7
    assert map[1] == null
}

test "an array that may be absent whose elements may be absent too" {
    values := new string?[](2)
    values[0] = "a"
    assert PresentInBoth(values) == 1
    assert PresentInBoth(null) == -1
}

test "the four spellings reach the CLR as the arrays they name" {
    labels := new string?[](1)
    counts := new int?[](1)
    shelf := MakeShelf(labels, null, counts, null)

    assert shelf.Labels.Length == 1
    assert shelf.Rows == null
    assert shelf.Counts.Length == 1
    assert shelf.Both == null

    shelfType := typeof(Shelf)
    labelsField := shelfType.GetField("Labels")
    countsField := shelfType.GetField("Counts")
    assert labelsField != null
    assert countsField != null

    // `string?[]` is an array OF `string`: the `?` is an annotation on the element, so the CLR type
    // is unchanged. `int?[]` is an array of `Nullable<int>`, which IS a different CLR element type —
    // the whole reason both spellings have to parse in every position.
    assert labelsField.FieldType == typeof(string[])
    assert countsField.FieldType.GetElementType() == typeof(Nullable<int>)
}

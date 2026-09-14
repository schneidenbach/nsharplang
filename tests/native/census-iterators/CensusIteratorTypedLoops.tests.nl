namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic
import System


// EXECUTED PROOFS FOR THE ANNOTATED LOOP VARIABLE INSIDE A GENERATOR.
test "an annotated loop variable unboxes each element" {
    values: object[] = [1, 2, 3]
    seen := new List<int>()
    for v in UnboxedElements(values) {
        seen.Add(v)
    }
    assert seen.Count == 3
    assert seen[0] == 2
    assert seen[1] == 4
    assert seen[2] == 6
}

test "an annotated loop variable widens each element of a sequence" {
    values := new List<int>()
    values.Add(4)
    values.Add(5)
    seen := new List<long>()
    for v in WidenedElements(values) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0] == 12
    assert seen[1] == 15
}

test "an annotated loop variable narrows each element of a sequence" {
    values := new List<long>()
    values.Add(7)
    values.Add(9)
    seen := new List<int>()
    for v in NarrowedElements(values) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0] == 7
    assert seen[1] == 9
}

test "an annotated loop variable downcasts each element" {
    values := new List<object>()
    values.Add("abc")
    values.Add("de")
    seen := new List<int>()
    for v in DowncastElements(values) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0] == 3
    assert seen[1] == 2
}

test "an element that is not the annotated type raises InvalidCastException at MoveNext" {
    values := new List<object>()
    values.Add(1)
    e := DowncastElements(values).GetEnumerator()
    caught := false
    try {
        e.MoveNext()
    } catch failure: InvalidCastException {
        caught = failure != null
    }
    assert caught
    e.Dispose()
}

test "an annotated loop variable converts each element of a hoisted array" {
    values: int[] = [1, 2]
    seen := new List<long>()
    for v in WidenedArrayElements(values) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0] == 2
    assert seen[1] == 3
}

test "an annotated loop variable widens each element of a string array to object" {
    values: string[] = ["ab", "cde"]
    seen := new List<object>()
    for v in WidenedStringArray(values) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0].ToString() == "ab"
    assert seen[1].ToString() == "cde"
}

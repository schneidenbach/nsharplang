namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic
import System.Text


// EXECUTED PROOFS THAT A STORE INSIDE A GENERATOR REACHES THE OBJECT IT NAMES.
test "a member store inside a generator is observed after enumeration" {
    box := new CensusBox()
    seen := new List<int>()
    for v in StoresIntoBox(box) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0] == 5
    assert seen[1] == 3
    assert box.Value == 5
    assert box.Label == "set"
}

test "a dictionary indexer store inside a generator is observed" {
    table := new Dictionary<string, int>()
    seen := new List<int>()
    for v in StoresIntoDictionary(table) {
        seen.Add(v)
    }
    assert seen.Count == 2
    assert seen[0] == 1
    assert seen[1] == 11
    assert table["a"] == 11
}

test "a List index store inside a generator is observed" {
    values := new List<int>()
    values.Add(0)
    seen := new List<int>()
    for v in StoresIntoList(values) {
        seen.Add(v)
    }
    assert seen.Count == 1
    assert seen[0] == 42
    assert values[0] == 42
}

test "an array element store inside a generator is observed" {
    values: int[] = [0, 0, 0]
    seen := new List<int>()
    for v in StoresIntoArray(values) {
        seen.Add(v)
    }
    assert seen.Count == 1
    assert seen[0] == 9
    assert values[1] == 9
}

test "a settable property store inside a generator is observed" {
    builder := new StringBuilder()
    seen := new List<int>()
    for v in StoresIntoProperty(builder) {
        seen.Add(v)
    }
    assert seen.Count == 1
    assert seen[0] == 2
    assert builder.ToString() == "ab"
}

test "a store inside a generator does not run until the sequence is enumerated" {
    table := new Dictionary<string, int>()
    sequence := StoresIntoDictionary(table)
    assert table.Count == 0
    e := sequence.GetEnumerator()
    assert table.Count == 0
    assert e.MoveNext()
    assert table["a"] == 1
    e.Dispose()
}

test "an instance generator writes its enclosing type's members" {
    counter := new CensusCounter()
    seen := new List<int>()
    for v in counter.Count(4) {
        seen.Add(v)
    }
    assert seen.Count == 4
    assert seen[0] == 0
    assert seen[1] == 1
    assert seen[2] == 3
    assert seen[3] == 6
    assert counter.Total == 6
    assert counter.Tag == "seen"
}

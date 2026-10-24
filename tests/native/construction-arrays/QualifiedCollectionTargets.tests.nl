namespace NSharpLang.ConstructionArrays.Tests

test "a fully qualified collection annotation target-types an empty and a filled local" {
    empty: System.Collections.Generic.List<string> = []
    filled: System.Collections.Generic.List<string> = ["a", "b"]
    assert empty.Count == 0
    assert filled.Count == 2
    assert filled[1] == "b"

    set: System.Collections.Generic.HashSet<int> = [3, 3, 4]
    emptySet: System.Collections.Generic.HashSet<int> = []
    assert set.Count == 2
    assert set.Contains(4)
    assert emptySet.Count == 0

    readOnly: System.Collections.Generic.IReadOnlyList<int> = [5, 6]
    assert readOnly[0] == 5

    sequence: System.Collections.Generic.IEnumerable<string> = []
    assert QualifiedSequenceLength(sequence) == 0
}

test "a qualified collection member takes an assigned literal and a field default" {
    holder := new QualifiedCollectionHolder()
    holder.Items = ["x", "y", "z"]
    holder.Tags = []
    assert holder.Items.Count == 3
    assert holder.Tags.Count == 0
    assert holder.Defaulted[0] == "seed"
    assert holder.Counts.Count == 2
}

test "a qualified collection parameter and return type target-type their literals" {
    assert QualifiedCount(["m", "n"]) == 2
    assert QualifiedCount([]) == 0
    assert QualifiedReadOnlyCount([1, 2, 3]) == 3
    assert QualifiedSequenceLength(["ab", "cde"]) == 5
    assert QualifiedEmptyList().Count == 0
    assert QualifiedPair()[0] == "left"
}

test "a qualified list widens to a qualified sequence" {
    list: System.Collections.Generic.List<string> = ["four"]
    widened: System.Collections.Generic.IEnumerable<string> = list
    assert QualifiedSequenceLength(widened) == 4
}

// A SEQUENCE INTERFACE EVERY `T[]` IMPLEMENTS IS BUILT AS EXACTLY `T[]`, with each element converted
// to the interface's element type. The empty literal and the mixed one used to decline in the backend
// (nothing to infer from, and no single element type) although analysis had already accepted both.
test "an empty or mixed literal at a sequence interface is built as the interface's array" {
    empty: System.Collections.Generic.IEnumerable<string> = []
    readOnly: System.Collections.Generic.IReadOnlyList<int> = []
    list: System.Collections.Generic.IList<int> = []
    collection: System.Collections.Generic.ICollection<int> = []
    readOnlyCollection: System.Collections.Generic.IReadOnlyCollection<int> = []
    assert QualifiedSequenceLength(empty) == 0
    assert readOnly.Count == 0
    assert list.Count == 0
    assert collection.Count == 0
    assert readOnlyCollection.Count == 0

    mixed: System.Collections.Generic.IReadOnlyList<object> = ["a", 1]
    assert mixed.Count == 2
    assert mixed[1].Equals(1)
    widened: System.Collections.Generic.IReadOnlyList<long> = [1, 2]
    assert widened[1] == 2L

    assert QualifiedReadOnlyCount([]) == 0
    assert QualifiedSequenceLength([]) == 0
}

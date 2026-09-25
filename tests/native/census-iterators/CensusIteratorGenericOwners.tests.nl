namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic


// EXECUTED PROOFS FOR STATIC GENERATORS DECLARED INSIDE GENERIC TYPES. Each row enumerates the machine,
// so a machine whose metadata the runtime refuses to load fails here rather than compiling silently.
test "a static generator in a generic type calls back into its declaring type" {
    collected := new List<string>()
    for name in CensusGenericBox<int>.Names(2) {
        collected.Add(name)
    }
    assert collected.Count == 2
    assert collected[0] == "box0"
    assert collected[1] == "box1"
}

test "a generic static generator in a generic type yields its own type parameter" {
    collected := new List<string>()
    for value in CensusGenericBox<int>.Echo<string>("echo") {
        collected.Add(value)
    }
    assert collected.Count == 2
    assert collected[0] == "echo"
    assert collected[1] == "echo"
}

test "both generators run on different instantiations of the same declaring type" {
    names := new List<string>()
    for name in CensusGenericBox<string>.Names(1) {
        names.Add(name)
    }
    echoes := new List<int>()
    for value in CensusGenericBox<string>.Echo<int>(7) {
        echoes.Add(value)
    }
    assert names.Count == 1
    assert names[0] == "box0"
    assert echoes.Count == 2
    assert echoes[0] == 7
}

test "a generic static generator hoists and yields the declaring type's parameter" {
    collected := new List<string>()
    for value in CensusGenericBox<string>.Tagged<int>("item", 3) {
        collected.Add(value)
    }
    assert collected.Count == 2
    assert collected[0] == "item"
    assert collected[1] == "item"
}

test "a generic static generator enumerates twice from the same enumerable" {
    source := CensusGenericBox<int>.Names(2)
    first := 0
    for _ in source {
        first += 1
    }
    second := 0
    for _ in source {
        second += 1
    }
    assert first == 2
    assert second == 2
}

test "an interface-constrained declaring type's generator runs on a satisfying instantiation" {
    items := new List<int>()
    items.Add(3)
    items.Add(1)
    items.Add(7)
    collected := new List<int>()
    for value in CensusRankedBox<int>.Running<string>(items, "tag") {
        collected.Add(value)
    }
    assert collected.Count == 3
    assert collected[0] == 3
    assert collected[1] == 1
    assert collected[2] == 7
}

test "a reference-constrained declaring type's generator runs on a reference instantiation" {
    collected := new List<string>()
    for value in CensusReferenceBox<object>.Describes<string>("a", "b") {
        collected.Add(value)
    }
    assert collected.Count == 2
    assert collected[0] == "ref"
    assert collected[1] == "ref!"
}

test "a per-iteration lambda in a generic type's static generator reads its own iteration" {
    items := new List<string>()
    items.Add("p")
    items.Add("q")
    collected := new List<int>()
    for value in CensusIndexedBox<string>.Positions<int>(items, 9) {
        collected.Add(value)
    }
    assert collected.Count == 2
    assert collected[0] == 0
    assert collected[1] == 10
}

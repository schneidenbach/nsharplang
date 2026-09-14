namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic


// EXECUTED PROOFS FOR STATIC READS AND WRITES INSIDE A GENERATOR. Statics are shared state, so each
// test resets the counters it uses before it enumerates.
test "a static field read inside a generator sees the value the caller set" {
    CensusStaticCounter.Reset()
    CensusStaticCounter.Total = 10

    collected := new List<int>()
    for v in StaticReads(3) {
        collected.Add(v)
    }
    assert collected.Count == 3
    assert collected[0] == 10
    assert collected[1] == 11
    assert collected[2] == 12
}

test "a static field read takes the other arm when the static is zero" {
    CensusStaticCounter.Reset()

    collected := new List<int>()
    for v in StaticReads(2) {
        collected.Add(v)
    }
    assert collected[0] == 0
    assert collected[1] == 1
}

test "a static field write inside a generator is observed after each suspension" {
    CensusStaticCounter.Reset()

    enumerator := StaticWrites(3).GetEnumerator()
    assert CensusStaticCounter.Total == 0

    assert enumerator.MoveNext()
    assert enumerator.Current == 1
    assert CensusStaticCounter.Total == 1
    assert CensusStaticCounter.Label == "step0"

    assert enumerator.MoveNext()
    assert CensusStaticCounter.Total == 2
    assert CensusStaticCounter.Label == "step1"

    assert enumerator.MoveNext()
    assert CensusStaticCounter.Total == 3
    assert !enumerator.MoveNext()
    enumerator.Dispose()
}

test "a static property is read and written through its own accessors inside a generator" {
    CensusRegistry.Current = 0

    collected := new List<int>()
    for v in StaticProperty(3) {
        collected.Add(v)
    }
    assert collected.Count == 3
    assert collected[0] == 2
    assert collected[1] == 4
    assert collected[2] == 6
    assert CensusRegistry.Backing == 6
}

test "a static named through a derived type binds the base declaration" {
    CensusBase.Seen = 5

    collected := new List<int>()
    for v in InheritedStatic() {
        collected.Add(v)
    }
    assert collected.Count == 1
    assert collected[0] == 6
    assert CensusDerived.Seen == 6
}

test "a plain body and a generator write the same static storage" {
    CensusStaticCounter.Reset()
    assert PlainStaticBump() == 1

    for v in StaticWrites(1) {
        assert v == 2
    }
    assert CensusStaticCounter.Total == 2
}

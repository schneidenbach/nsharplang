namespace NSharpLang.CensusIterators.Tests

import System.Collections.Generic


// EXECUTED PROOFS THAT A MEMBER GENERATOR CALLS ITS OWN TYPE'S MEMBERS BY THEIR BARE NAMES.
test "a member generator calls its own member bare and through this" {
    collected := new List<string>()
    for label in new CensusCallHost("a:").Labels() {
        collected.Add(label)
    }
    assert collected.Count == 2
    assert collected[0] == "a:label"
    assert collected[1] == "a:label"
}

test "a member generator selects an overload by the argument it passes" {
    collected := new List<string>()
    for text in new CensusCallHost("").Descriptions(2) {
        collected.Add(text)
    }
    assert collected.Count == 3
    assert collected[0] == "int 0"
    assert collected[1] == "int 1"
    assert collected[2] == "string done"
}

test "a member call in a generator re-runs on every resume against the same instance" {
    host := new CensusCallHost("")
    collected := new List<int>()
    for value in host.Counts(5) {
        collected.Add(value)
    }
    assert collected.Count == 3
    assert collected[0] == 102
    assert collected[1] == 304
    assert collected[2] == 506
    assert host.Calls == 7
}

test "a void member called as a generator statement writes the captured instance" {
    host := new CensusCallHost("")
    collected := new List<int>()
    for value in host.Recorded() {
        collected.Add(value)
    }
    assert collected.Count == 2
    assert collected[0] == 10
    assert collected[1] == 20
    assert host.Calls == 20
}

test "a member generator calls inherited, static and namespace-private members" {
    collected := new List<string>()
    for kind in new CensusCallHost("").Kinds() {
        collected.Add(kind)
    }
    assert collected.Count == 3
    assert collected[0] == "base member"
    assert collected[1] == "static member"
    assert collected[2] == "namespace-private member"
}

test "a member generator calls a private member of its declaring type" {
    collected := new List<string>()
    for text in new CensusCallHost("").Privately() {
        collected.Add(text)
    }
    assert collected.Count == 2
    assert collected[0] == "private member"
    assert collected[1] == "private static member"
}

test "a struct member generator reads and calls through a copy of its receiver" {
    point := new CensusCallPoint { X: 21 }
    values := point.Values()
    point.X = 1
    collected := new List<int>()
    for value in values {
        collected.Add(value)
    }
    assert collected.Count == 3
    assert collected[0] == 21
    assert collected[1] == 42
    assert collected[2] == 42
}

test "a lambda inside a member generator calls the member on the captured instance" {
    collected := new List<string>()
    for text in new CensusCallHost("p:").ThroughLambda() {
        collected.Add(text)
    }
    assert collected.Count == 2
    assert collected[0] == "p:label"
    assert collected[1] == "P:STRING X"
}

test "a per-iteration lambda in a member generator calls the member on the captured instance" {
    words: string[] = ["a", "b"]
    collected := new List<string>()
    for read in new CensusCallHost("w:").PerWord(words) {
        collected.Add(read())
    }
    assert collected.Count == 2
    assert collected[0] == "w:string a"
    assert collected[1] == "w:string b"
}

test "a static generator still calls a static member bare" {
    collected := new List<string>()
    for text in CensusCallHost.Statics() {
        collected.Add(text)
    }
    assert collected.Count == 1
    assert collected[0] == "static member"
}

test "a member generator calls a method its external base declares" {
    names := new CensusCallNames()
    names.Add("first")
    probes: string[] = ["first", "second"]
    collected := new List<bool>()
    for present in names.Presence(probes) {
        collected.Add(present)
    }
    assert collected.Count == 2
    assert collected[0]
    assert !collected[1]
}

namespace NSharpLang.RecordWithExternal.Tests

import System
import NSharpLang.RecordWith.Library

test "a with over a record from another project replaces the named member and keeps the rest" {
    s := new Status { State: "ok", Gate: "A1" }
    t := s with { State: "late" }
    assert t.State == "late"
    assert t.Gate == "A1"
}

test "a with over a record from another project leaves the source untouched" {
    s := new Status { State: "ok", Gate: "A1" }
    t := s with { State: "late" }
    assert s.State == "ok"
    assert !Object.ReferenceEquals(s, t)
}

test "a with over a record from another project accepts null for a nullable member" {
    s := new Status { State: "ok", Gate: "A1" }
    t := s with { Gate: null }
    assert t.Gate == null
    assert t.State == "ok"
}

test "a with over a record from another project applies several replacements in order" {
    r := new Reading { Latitude: 1.5, Name: "a", Count: 1 }
    c := r with { Name: "b", Count: 2 }
    assert c.Latitude == 1.5
    assert c.Name == "b"
    assert c.Count == 2
}

test "a with over a record from another project lifts a plain value into a nullable member" {
    r := new Reading { Latitude: null, Name: "a", Count: 1 }
    c := r with { Latitude: 2.5 }
    assert c.Latitude == 2.5
}

test "a with with no replacements is a distinct equal copy" {
    s := new Status { State: "ok", Gate: "A1" }
    t := s with {}
    assert !Object.ReferenceEquals(s, t)
    assert t.Equals(s)
}

test "a with over a record struct from another project copies by value" {
    p := new Pair { Left: 1, Right: 2 }
    q := p with { Right: 9 }
    assert q.Left == 1
    assert q.Right == 9
    assert p.Right == 2
}

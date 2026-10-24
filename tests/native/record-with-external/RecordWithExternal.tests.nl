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

test "a with over a record from another project writes a public field and an init-only property" {
    slot := new Slot { size: 1, Label: "a" }
    resized := slot with { size: 9 }
    relabelled := slot with { Label: "b" }
    assert resized.size == 9
    assert resized.Label == "a"
    assert relabelled.size == 1
    assert relabelled.Label == "b"
    assert slot.size == 1
    assert slot.Label == "a"
}

test "a with over a derived record from another project preserves its derived members" {
    original := new DetailedStatus { State: "ready", Gate: "A1", Revision: 4 }
    changed := original with { Revision: 5 }
    assert changed.State == "ready"
    assert changed.Gate == "A1"
    assert changed.Revision == 5
    assert changed.GetType().Name == "DetailedStatus"
    assert original.Revision == 4
}

test "a with through a base-typed reference preserves the referenced derived runtime type" {
    derived := new DetailedStatus { State: "ready", Gate: "A1", Revision: 4 }
    original: Status = derived
    changed := original with { State: "late" }
    assert changed.State == "late"
    assert changed.Gate == "A1"
    assert changed.GetType().Name == "DetailedStatus"
    assert original.State == "ready"
}

test "a with over a generic record from another project copies its constructed value" {
    original := new Box<int> { Value: 5, Label: "count" }
    changed := original with { Value: 9 }
    assert changed.Value == 9
    assert changed.Label == "count"
    assert original.Value == 5
    assert !Object.ReferenceEquals(original, changed)
}

namespace NSharpLang.CensusStaticFieldReferences.Tests

import System.Threading

// A BY-REFERENCE ARGUMENT THAT NAMES A STATIC FIELD.
//
// The by-ref argument arm routes every `ref`/`out` argument through
// `ColumnarBoundIdentifierPlanner.TryAppendAddressOf`, which had an arm for a LOCAL (`ldloca`), a
// PARAMETER (`ldarga`) and a CURRENT INSTANCE FIELD (`ldflda`) and none for a static field -- and
// the plan contract carried `ldsfld` and `stsfld` but no `ldsflda` to add one with. So
// `Interlocked.Increment(ref Total)` declined while the identical call over a local, a parameter or
// an instance field emitted. The argument's TYPE could not even be named, because a static read is
// owned by the static-member planner rather than by a `ColumnarBoundIdentifierKind`, so the call
// declined at argument collection before the address-of walk ever ran.
//
// Every row below EXECUTES. Ordering matters inside a row and never across rows, so each row uses
// its own counter type.
class BareCounter {
    static Total: int = 0
}

class QualifiedCounter {
    static Total: int = 0

    static func BumpQualified(): int {
        return Interlocked.Increment(ref QualifiedCounter.Total)
    }
}

class InstanceBumper {
    static Total: int = 0
    Seen: int = 0

    func Bump(): int {
        Seen = Seen + 1
        return Interlocked.Increment(ref Total)
    }
}

class StaticBase {
    static Shared: int = 0
}

class StaticDerived: StaticBase {
    static func Bump(): int {
        return Interlocked.Increment(ref Shared)
    }
}

class FlagHolder {
    static Flag: bool = false
    static Label: string = "start"
    static Depth: long = 0
    static Parsed: int = -1
}

func BumpBare(): int {
    return Interlocked.Increment(ref BareCounter.Total)
}

test "Interlocked.Increment over a static field of the enclosing type counts up" {
    first := QualifiedCounter.BumpQualified()
    second := QualifiedCounter.BumpQualified()
    assert first == 1
    assert second == 2
    assert QualifiedCounter.Total == 2
}

test "a static field named from another type's body is the same storage" {
    assert BumpBare() == 1
    assert BumpBare() == 2
    assert BareCounter.Total == 2
}

test "an instance method may take the address of its type's static field" {
    bumper := new InstanceBumper()
    assert bumper.Bump() == 1
    assert bumper.Bump() == 2
    assert bumper.Seen == 2
    assert InstanceBumper.Total == 2
}

test "a static field a base type declares is addressable from the derived body" {
    assert StaticDerived.Bump() == 1
    assert StaticDerived.Bump() == 2
    assert StaticBase.Shared == 2
}

test "Volatile.Write and Volatile.Read round trip a static bool" {
    Volatile.Write(ref FlagHolder.Flag, true)
    assert Volatile.Read(ref FlagHolder.Flag)
    Volatile.Write(ref FlagHolder.Flag, false)
    assert !Volatile.Read(ref FlagHolder.Flag)
}

test "Interlocked.Exchange over a static REFERENCE field returns the previous value" {
    previous := Interlocked.Exchange(ref FlagHolder.Label, "next")
    assert previous == "start"
    assert FlagHolder.Label == "next"
}

test "Interlocked.Add and CompareExchange reach a static long and a static int" {
    assert Interlocked.Add(ref FlagHolder.Depth, 5) == 5
    assert Interlocked.Add(ref FlagHolder.Depth, 7) == 12
    assert FlagHolder.Depth == 12

    FlagHolder.Parsed = 42
    assert Interlocked.CompareExchange(ref FlagHolder.Parsed, 99, 42) == 42
    assert FlagHolder.Parsed == 99

    // A comparand that does not match leaves the storage alone and still answers the old value.
    assert Interlocked.CompareExchange(ref FlagHolder.Parsed, 7, 42) == 99
    assert FlagHolder.Parsed == 99
}

test "an OUT argument may name a static field" {
    FlagHolder.Parsed = -1
    assert int.TryParse("314", out FlagHolder.Parsed)
    assert FlagHolder.Parsed == 314

    // The failing parse still writes through the same address, which is what `out` guarantees.
    assert !int.TryParse("not a number", out FlagHolder.Parsed)
    assert FlagHolder.Parsed == 0
}

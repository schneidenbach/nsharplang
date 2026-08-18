namespace NSharpLang.Compiler.Performance


// THE CANONICAL CONTRACTS FOR `PerformanceFactStore`, IN N#.
//
// These replace `tests/PerformanceFactStoreTests.cs`, the last canonical C# assertion layer over
// `PerformanceFactStore.nl`. The store is the side table the performance pipeline writes its
// per-position verdicts into — escape, capture, allocation, dispatch, layout and AOT safety for one
// source position — and its whole contract is the KEY: a `(File, Line, Column)` triple in which the
// file may legitimately be `null`.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. Every input is a constructed `PerformanceFacts`
// and every enum member is a dependency-assembly one; both decline at emit from a `tests/native`
// project (`emit.local.initializer` and `emit.typed-local.initializer` respectively).
//
// TWO MEASURED SPELLING WALLS BOUND HOW THE KEY IS INTERROGATED. `for entry in store.All { … }`
// emits, but reading a NAMED TUPLE ELEMENT off the walked entry's key (`entry.Key.Line`) declines
// at `emit.if.condition`; and a tuple LITERAL with a `null` element (`(File: null, Line: 1,
// Column: 1)`) declines at `emit.expression.unhandled-kind`. So the key is interrogated the way
// the deleted C# interrogated it — `All.ContainsKey((File: "a.nl", Line: 3, Column: 10))` — and the
// `null`-file key is reached through `Lookup(null, …)`, which is green and is the entry point
// production uses anyway.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) `null` IS A FILE, NOT AN ABSENCE. The key's first element is `string?`, so a fact recorded
// with no file is retrievable with no file and is a DIFFERENT entry from the same position in
// `a.nl`. A store that coalesced `null` to `""` would pass every other assertion here.
//
// (2) `Record` IS LAST-WRITE-WINS AND IT DOES NOT GROW THE STORE. It removes before it adds, so
// re-recording a position replaces the fact and leaves `Count` alone. `Add` alone would throw on
// the second write; `Add` without the `Remove` would keep the first answer.
//
// (3) `Merge` IS ONE-WAY AND THE OTHER STORE WINS. Every entry of the argument is written over the
// receiver's, and the ARGUMENT is never mutated — the receiver absorbs, the source is untouched.
//
// (4) `PerformanceFacts.Default` IS THE MOST CONSERVATIVE ROW, AND ITS LAYOUT IS
// `ReferenceObject`. Five of its six members are the "nothing interesting happens" member of their
// enum; the sixth is deliberately the WIDEST layout, because a fact that has not been computed must
// not claim to be a struct. The deleted file asserted five of the six and left `ValueLayout` — the
// one that is not the enum's first member — unasserted.

func PerfFactsMake(escape: EscapeKind, allocation: AllocationKind, dispatch: DispatchKind): PerformanceFacts {
    return new PerformanceFacts(escape, CaptureKind.None, allocation, dispatch, ValueLayoutKind.Struct, AotSafetyKind.NoReflection)
}

func PerfFactsWithEscape(escape: EscapeKind): PerformanceFacts {
    return PerfFactsMake(escape, AllocationKind.None, DispatchKind.Direct)
}

func PerfFactsPlain(): PerformanceFacts {
    return PerfFactsMake(EscapeKind.LocalOnly, AllocationKind.None, DispatchKind.Direct)
}

// ---- Record and Lookup ----------------------------------------------------------------------------

// Successor to Record_CanLookUpByPosition.
test "performance fact store records a fact that can be looked up by position" {
    store := new PerformanceFactStore()
    store.Record("a.nl", 3, 10, PerfFactsMake(EscapeKind.Returned, AllocationKind.Closure, DispatchKind.Interface))

    result := store.Lookup("a.nl", 3, 10)

    assert result != null
    if result != null {
        assert result.Escape == EscapeKind.Returned
        assert result.Allocation == AllocationKind.Closure
        assert result.Dispatch == DispatchKind.Interface

        // Not in the deleted file: the three members it never read back are carried too.
        assert result.Capture == CaptureKind.None
        assert result.ValueLayout == ValueLayoutKind.Struct
        assert result.AotSafety == AotSafetyKind.NoReflection
    }
}

// Successor to Lookup_ReturnsNull_WhenNoFactsRecorded.
test "performance fact store looks up nothing in an empty store" {
    store := new PerformanceFactStore()

    assert store.Lookup("a.nl", 1, 1) == null

    // Not in the deleted file: an empty store is empty by both of its own measures.
    assert store.Count == 0
    assert store.All.Count == 0
}

// Successor to Lookup_DistinguishesByFile.
test "performance fact store distinguishes positions by file" {
    store := new PerformanceFactStore()
    store.Record("a.nl", 1, 1, PerfFactsWithEscape(EscapeKind.LocalOnly))
    store.Record("b.nl", 1, 1, PerfFactsWithEscape(EscapeKind.PublicAbi))

    first := store.Lookup("a.nl", 1, 1)
    second := store.Lookup("b.nl", 1, 1)

    assert first != null
    assert second != null
    if first != null {
        assert first.Escape == EscapeKind.LocalOnly
    }
    if second != null {
        assert second.Escape == EscapeKind.PublicAbi
    }
}

// NOT IN THE DELETED FILE. The other two thirds of the key: the LINE and the COLUMN discriminate
// too, which a store keyed on the file alone would fail and the deleted file could not see.
test "performance fact store distinguishes positions by line and column" {
    store := new PerformanceFactStore()
    store.Record("a.nl", 1, 1, PerfFactsWithEscape(EscapeKind.LocalOnly))
    store.Record("a.nl", 2, 1, PerfFactsWithEscape(EscapeKind.Returned))
    store.Record("a.nl", 1, 2, PerfFactsWithEscape(EscapeKind.Stored))

    assert store.Count == 3

    byLine := store.Lookup("a.nl", 2, 1)
    byColumn := store.Lookup("a.nl", 1, 2)
    assert byLine != null
    assert byColumn != null
    if byLine != null {
        assert byLine.Escape == EscapeKind.Returned
    }
    if byColumn != null {
        assert byColumn.Escape == EscapeKind.Stored
    }

    assert store.Lookup("a.nl", 3, 1) == null
    assert store.Lookup("a.nl", 1, 3) == null
}

// Successor to Lookup_TreatsNullFileAsItsOwnKey.
test "performance fact store treats a null file as its own key" {
    store := new PerformanceFactStore()
    store.Record(null, 5, 2, PerfFactsWithEscape(EscapeKind.Stored))

    assert store.Lookup(null, 5, 2) != null
    assert store.Lookup("a.nl", 5, 2) == null
}

// NOT IN THE DELETED FILE. `null` and the EMPTY STRING are two different files, which is the
// distinction a store that coalesced the key would lose.
test "performance fact store separates a null file from an empty file name" {
    store := new PerformanceFactStore()
    store.Record(null, 1, 1, PerfFactsWithEscape(EscapeKind.Stored))
    store.Record("", 1, 1, PerfFactsWithEscape(EscapeKind.PublicAbi))

    assert store.Count == 2

    absent := store.Lookup(null, 1, 1)
    empty := store.Lookup("", 1, 1)
    assert absent != null
    assert empty != null
    if absent != null {
        assert absent.Escape == EscapeKind.Stored
    }
    if empty != null {
        assert empty.Escape == EscapeKind.PublicAbi
    }

    // The `null`-file key is reachable through `Lookup` but not through a tuple LITERAL: a `null`
    // element inside one declines at `emit.expression.unhandled-kind`.
    assert store.All.ContainsKey((File: "", Line: 1, Column: 1))
    assert store.All.Count == 2
}

// Successor to Record_LastWriteWins.
test "performance fact store lets the last write win" {
    store := new PerformanceFactStore()
    store.Record("a.nl", 2, 4, PerfFactsWithEscape(EscapeKind.LocalOnly))
    store.Record("a.nl", 2, 4, PerfFactsWithEscape(EscapeKind.ReflectionBoundary))

    result := store.Lookup("a.nl", 2, 4)
    assert result != null
    if result != null {
        assert result.Escape == EscapeKind.ReflectionBoundary
    }

    assert store.Count == 1

    // Not in the deleted file: a THIRD write still replaces rather than accumulates.
    store.Record("a.nl", 2, 4, PerfFactsWithEscape(EscapeKind.ExpressionTree))
    third := store.Lookup("a.nl", 2, 4)
    assert third != null
    if third != null {
        assert third.Escape == EscapeKind.ExpressionTree
    }

    assert store.Count == 1
    assert store.All.Count == 1
}

// ---- the default row ------------------------------------------------------------------------------

// Successor to Default_IsMostConservative.
test "performance fact store defaults are the most conservative row" {
    fallback := PerformanceFacts.Default

    assert fallback.Escape == EscapeKind.LocalOnly
    assert fallback.Capture == CaptureKind.None
    assert fallback.Allocation == AllocationKind.None
    assert fallback.Dispatch == DispatchKind.Direct
    assert fallback.AotSafety == AotSafetyKind.NoReflection

    // NOT IN THE DELETED FILE, and it is the one member that is NOT its enum's first: an
    // uncomputed fact claims the WIDEST layout rather than the cheapest.
    assert fallback.ValueLayout == ValueLayoutKind.ReferenceObject
    assert fallback.ValueLayout != ValueLayoutKind.Primitive
    assert fallback.ValueLayout != ValueLayoutKind.Struct
}

// NOT IN THE DELETED FILE. The carrier is a plain record and every one of its six members reads
// back what it was constructed with — including the five the default row never varies.
test "performance fact store facts carry every member they were built with" {
    facts := new PerformanceFacts(
        EscapeKind.PassedToUnknown,
        CaptureKind.CapturesRefLike,
        AllocationKind.IteratorStateMachine,
        DispatchKind.ConstrainedValueType,
        ValueLayoutKind.RefStruct,
        AotSafetyKind.DynamicCodeRequired)

    assert facts.Escape == EscapeKind.PassedToUnknown
    assert facts.Capture == CaptureKind.CapturesRefLike
    assert facts.Allocation == AllocationKind.IteratorStateMachine
    assert facts.Dispatch == DispatchKind.ConstrainedValueType
    assert facts.ValueLayout == ValueLayoutKind.RefStruct
    assert facts.AotSafety == AotSafetyKind.DynamicCodeRequired
}

// ---- Merge ----------------------------------------------------------------------------------------

// Successor to Merge_CombinesNonOverlappingPositions.
test "performance fact store merge combines non overlapping positions" {
    receiver := new PerformanceFactStore()
    receiver.Record("a.nl", 1, 1, PerfFactsWithEscape(EscapeKind.LocalOnly))

    source := new PerformanceFactStore()
    source.Record("b.nl", 2, 2, PerfFactsWithEscape(EscapeKind.Returned))

    receiver.Merge(source)

    assert receiver.Count == 2

    kept := receiver.Lookup("a.nl", 1, 1)
    absorbed := receiver.Lookup("b.nl", 2, 2)
    assert kept != null
    assert absorbed != null
    if kept != null {
        assert kept.Escape == EscapeKind.LocalOnly
    }
    if absorbed != null {
        assert absorbed.Escape == EscapeKind.Returned
    }
}

// Successor to Merge_OtherStoreWinsOnCollision.
test "performance fact store merge lets the other store win a collision" {
    receiver := new PerformanceFactStore()
    receiver.Record("a.nl", 1, 1, PerfFactsMake(EscapeKind.LocalOnly, AllocationKind.None, DispatchKind.Direct))

    source := new PerformanceFactStore()
    source.Record("a.nl", 1, 1, PerfFactsMake(EscapeKind.PublicAbi, AllocationKind.Boxing, DispatchKind.Direct))

    receiver.Merge(source)

    assert receiver.Count == 1

    merged := receiver.Lookup("a.nl", 1, 1)
    assert merged != null
    if merged != null {
        assert merged.Escape == EscapeKind.PublicAbi
        assert merged.Allocation == AllocationKind.Boxing
    }
}

// Successor to Merge_DoesNotMutateOtherStore.
test "performance fact store merge does not mutate the other store" {
    receiver := new PerformanceFactStore()
    receiver.Record("a.nl", 1, 1, PerfFactsPlain())

    source := new PerformanceFactStore()
    source.Record("b.nl", 2, 2, PerfFactsPlain())

    receiver.Merge(source)

    assert source.Count == 1
    assert source.Lookup("a.nl", 1, 1) == null

    // Not in the deleted file: the source keeps its OWN entry as well as refusing the receiver's.
    assert source.Lookup("b.nl", 2, 2) != null
}

// NOT IN THE DELETED FILE. The two empty-side merges, which are where an unguarded walk or a
// swapped argument shows up.
test "performance fact store merge handles the empty sides" {
    emptySource := new PerformanceFactStore()
    receiver := new PerformanceFactStore()
    receiver.Record("a.nl", 1, 1, PerfFactsWithEscape(EscapeKind.Returned))
    receiver.Merge(emptySource)

    assert receiver.Count == 1
    assert emptySource.Count == 0
    survivor := receiver.Lookup("a.nl", 1, 1)
    assert survivor != null
    if survivor != null {
        assert survivor.Escape == EscapeKind.Returned
    }

    emptyReceiver := new PerformanceFactStore()
    source := new PerformanceFactStore()
    source.Record("b.nl", 2, 2, PerfFactsWithEscape(EscapeKind.Stored))
    emptyReceiver.Merge(source)

    assert emptyReceiver.Count == 1
    assert source.Count == 1
    absorbed := emptyReceiver.Lookup("b.nl", 2, 2)
    assert absorbed != null
    if absorbed != null {
        assert absorbed.Escape == EscapeKind.Stored
    }
}

// NOT IN THE DELETED FILE. A merge that carries a `null`-file key keeps it a `null`-file key.
test "performance fact store merge carries a null file key" {
    receiver := new PerformanceFactStore()
    source := new PerformanceFactStore()
    source.Record(null, 4, 4, PerfFactsWithEscape(EscapeKind.ExpressionTree))

    receiver.Merge(source)

    assert receiver.Count == 1
    assert receiver.Lookup(null, 4, 4) != null
    assert receiver.Lookup("a.nl", 4, 4) == null
    assert !receiver.All.ContainsKey((File: "", Line: 4, Column: 4))
}

// ---- All ------------------------------------------------------------------------------------------

// Successor to All_ExposesEveryRecordedPosition.
test "performance fact store exposes every recorded position" {
    store := new PerformanceFactStore()
    store.Record("a.nl", 1, 1, PerfFactsPlain())
    store.Record("a.nl", 2, 2, PerfFactsPlain())

    assert store.All.Count == 2
    assert store.All.ContainsKey((File: "a.nl", Line: 1, Column: 1))
    assert store.All.ContainsKey((File: "a.nl", Line: 2, Column: 2))
}

// NOT IN THE DELETED FILE. `All` is the store itself rather than a snapshot — it agrees with
// `Count`, it refuses a key that was never written, and it is walkable.
test "performance fact store all agrees with count and is walkable" {
    store := new PerformanceFactStore()
    assert store.All.Count == store.Count

    store.Record("a.nl", 1, 1, PerfFactsPlain())
    store.Record("b.nl", 2, 2, PerfFactsPlain())
    store.Record("a.nl", 1, 1, PerfFactsWithEscape(EscapeKind.PublicAbi))

    assert store.All.Count == store.Count
    assert store.All.Count == 2
    assert !store.All.ContainsKey((File: "c.nl", Line: 1, Column: 1))
    assert !store.All.ContainsKey((File: "a.nl", Line: 1, Column: 2))

    walked := 0
    for entry in store.All {
        walked = walked + 1
    }

    assert walked == 2
}

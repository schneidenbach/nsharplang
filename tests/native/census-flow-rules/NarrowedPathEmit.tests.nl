namespace NSharpLang.CensusFlowRules.Tests

import System


// RUNTIME contracts for a narrowed VALUE-nullable MEMBER PATH (`NarrowedPathEmit.nl`).
//
// Each narrowing function COMPILING is half of its contract — every one of them declined at emit
// with NL103 before the emitter read path facts. These assertions are the other half: the value
// the narrowed read produces, and — for the invalidation contracts — the `null` a stale unwrap
// would have thrown on instead of returning.
func SlottedWith(slot: int?): Slotted {
    return new Slotted(slot, null)
}

func SlottedAt(row: int, column: int): Slotted {
    return new Slotted(null, new Cell { Row: row, Column: column })
}

// ── the narrowed reads ─────────────────────────────────────────────────────────────────────────

test "a narrowed path is read as its element in arithmetic after `== null`" {
    assert PathPlusOne(SlottedWith(5)) == 6
    assert PathPlusOne(SlottedWith(null)) == 0
}

test "a narrowed path is returned as its element inside `!= null`" {
    assert PathOrMinusOne(SlottedWith(9)) == 9
    assert PathOrMinusOne(SlottedWith(null)) == -1
}

test "a narrowed path is passed as its element to an `int` parameter" {
    assert PathDoubled(SlottedWith(21)) == 42
    assert PathDoubled(SlottedWith(null)) == -1
}

test "`!h.Slot.HasValue` proves the path on the flow that survives it" {
    assert PathPlusTenAfterHasValue(SlottedWith(1)) == 11
    assert PathPlusTenAfterHasValue(SlottedWith(null)) == -1
}

test "a positive `h.Slot.HasValue` narrows its own branch" {
    assert PathTimesThreeWhenHasValue(SlottedWith(4)) == 12
    assert PathTimesThreeWhenHasValue(SlottedWith(null)) == -1
}

test "the else branch of `== null` reads the path narrowed" {
    assert PathMinusOneOrZero(SlottedWith(8)) == 7
    assert PathMinusOneOrZero(SlottedWith(null)) == 0
}

test "a PROPERTY path narrows the way a field path does" {
    assert DoubledPlusOne(SlottedWith(3)) == 7
    assert DoubledPlusOne(SlottedWith(null)) == 0
}

test "the implicit receiver and `this.` narrow their own spelling of the path" {
    assert SlottedWith(2).OwnSlotPlusOne() == 3
    assert SlottedWith(null).OwnSlotPlusOne() == 0
    assert SlottedWith(6).ThisSlotPlusOne() == 7
    assert SlottedWith(null).ThisSlotPlusOne() == 0
}

test "a two-hop path is narrowed by the guard that names it" {
    outer := SlottedWith(null)
    assert NextSlotTimesFive(outer) == -1
    outer.Next = SlottedWith(null)
    assert NextSlotTimesFive(outer) == -2
    outer.Next = SlottedWith(3)
    assert NextSlotTimesFive(outer) == 15
}

test "a `?.` chain proves its tested receiver and the path together" {
    assert ChainedSlotPlusTwo(SlottedWith(40)) == 42
    assert ChainedSlotPlusTwo(SlottedWith(null)) == -1
    assert ChainedSlotPlusTwo(null) == -1
}

test "`assert` and a `[DoesNotReturnIf(false)]` argument prove the path" {
    assert AssertedPathPlusFour(SlottedWith(1)) == 5
    assert RequiredPathPlusFive(SlottedWith(1)) == 6
    assert throws ArgumentException {
        RequiredPathPlusFive(SlottedWith(null))
    }
}

// ── a source struct behind the path ────────────────────────────────────────────────────────────

test "a narrowed struct path is read as the struct: member, return, argument and store" {
    at := SlottedAt(3, 4)
    assert WhereRowPlusColumn(at) == 7
    assert WhereOrOrigin(at).Column == 4
    assert WhereRowThroughArgument(at) == 3
    assert StoredWhereColumn(at) == 4

    empty := SlottedWith(1)
    assert WhereRowPlusColumn(empty) == -1
    assert WhereOrOrigin(empty).Row == 0
    assert WhereRowThroughArgument(empty) == -1
    assert StoredWhereColumn(empty) == -1
}

// ── the shapes that want the shell ─────────────────────────────────────────────────────────────

test "`??` and `.HasValue` keep the shell on a narrowed path" {
    assert PathCoalescedAfterNarrowing(SlottedWith(2)) == 2
    assert PathHasValueAfterNarrowing(SlottedWith(2))
    assert !PathHasValueAfterNarrowing(SlottedWith(null))
}

// ── invalidation, run with NULL so a stale unwrap would throw ──────────────────────────────────

test "writing the path ends the narrowing: the null written is read back, not unwrapped" {
    assert PathAfterOverwrite(SlottedWith(1), null) == null
    assert PathAfterOverwrite(SlottedWith(1), 7) == 7
}

test "writing a prefix ends the narrowing of every path under it" {
    assert PathAfterPrefixRewrite(SlottedWith(1), SlottedWith(null)) == null
    assert PathAfterPrefixRewrite(SlottedWith(1), SlottedWith(8)) == 8
}

test "passing a prefix by `out` ends the narrowing" {
    assert PathAfterOutRefill(SlottedWith(1), SlottedWith(null)) == null
    assert PathAfterOutRefill(SlottedWith(1), SlottedWith(3)) == 3
}

test "a loop body that resets the path reads it as a nullable on every turn" {
    assert PathAccumulatedWithReset(SlottedWith(10), 3) == 20
}

test "an `&&` branch that proves the path does not narrow the flow after it" {
    assert PathUnprovedAfterBranch(SlottedWith(1), true) == 101
    assert PathUnprovedAfterBranch(SlottedWith(1), false) == 1
    assert PathUnprovedAfterBranch(SlottedWith(null), true) == null
}

test "a receiver call keeps the fact, and a narrowed read it broke throws rather than reading a default" {
    assert PathAcrossClearingCall(SlottedWith(null)) == -1
    assert throws InvalidOperationException {
        PathAcrossClearingCall(SlottedWith(4))
    }
}

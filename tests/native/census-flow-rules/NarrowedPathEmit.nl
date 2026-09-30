namespace NSharpLang.CensusFlowRules.Tests


// CENSUS §FLOW4, THE MEMBER-PATH HALF — A NARROWED `T?` PATH IS READ AS ITS `T`, AT EMIT.
//
// `NarrowedValueEmit.nl` pins the rule for a LOCAL: past `if value == null { return 0 }` the read
// `value + 1` is an `int`. The analyzer states the same rule for a stable MEMBER PATH — it files a
// null fact for `h.Slot` and collapses the read's flow type to `int` — and the language tour
// promises `h.Slot + 1` is the narrowed read "exactly as they are for a local". The emitter used to
// know only the local half: every function below compiled clean and then declined at emit with
// NL103 (`emit.return.type-mismatch` for `return h.Slot + 1`), because the read still arrived as the
// declared `Nullable<int>`.
//
// THE UNWRAP NEEDS NO STORAGE OF ITS OWN. The emitter parks the value the ordinary member read
// produced and calls `Value` on the copy, so a field, a property, `this.Slot`, a two-hop path and a
// struct element all narrow the same way a local does.
//
// AND THE PATH IS NEVER UNWRAPPED WHERE THE ANALYZER STOPPED PROVING IT. The second half of this file
// runs every invalidation — a write to the path, a write to a PREFIX, a prefix passed by `out`, a
// loop that resets the path — with a NULL replacement: an emitter that kept a stale fact would call
// `Value` on an empty nullable and throw, instead of returning the `null` the program reads.
struct Cell {
    Row: int
    Column: int
}

class Slotted {
    Slot: int?
    Where: Cell?
    Next: Slotted?

    constructor(slot: int?, cell: Cell?) {
        Slot = slot
        Where = cell
        Next = null
    }

    // A call on the receiver. Reaching it does NOT end a narrowing of `Slot` — the optimistic rule
    // `PropertyPathState.nl` pins for reference paths — so a narrowed read after it that finds the
    // value gone must THROW, never read a default.
    func Clear() {
        Slot = null
    }

    // A PROPERTY path, beside the field one: the read is a getter call, and the unwrap is the same.
    Doubled: int? => Slot == null ? null : Slot * 2

    // THE IMPLICIT RECEIVER. Inside a member, `Slot` is the path `Slot` to the analyzer and to the
    // emitter alike.
    func OwnSlotPlusOne(): int {
        if Slot == null {
            return 0
        }

        return Slot + 1
    }

    // `this.Slot` is its own spelling of the path, and it narrows under its own spelling.
    func ThisSlotPlusOne(): int {
        if this.Slot == null {
            return 0
        }

        return this.Slot + 1
    }
}

func TwiceOf(value: int): int {
    return value * 2
}

func RowOf(cell: Cell): int {
    return cell.Row
}

// THE CENSUS SHAPE, VERBATIM: a bare path read in arithmetic past a `== null` guard clause.
func PathPlusOne(h: Slotted): int {
    if h.Slot == null {
        return 0
    }

    return h.Slot + 1
}

// `return h.Slot` from a non-nullable function, inside a `!= null` branch.
func PathOrMinusOne(h: Slotted): int {
    if h.Slot != null {
        return h.Slot
    }

    return -1
}

// The path as an ARGUMENT, which is the position that selects an overload on the argument's type.
func PathDoubled(h: Slotted): int {
    if h.Slot == null {
        return -1
    }

    return TwiceOf(h.Slot)
}

// `!h.Slot.HasValue` proves the path on the surviving flow, as `!x.HasValue` proves a local.
func PathPlusTenAfterHasValue(h: Slotted): int {
    if !h.Slot.HasValue {
        return -1
    }

    return h.Slot + 10
}

// The positive `HasValue` guard narrows its own branch.
func PathTimesThreeWhenHasValue(h: Slotted): int {
    if h.Slot.HasValue {
        return h.Slot * 3
    }

    return -1
}

// The else branch of a `== null` test is the same fact on the other side.
func PathMinusOneOrZero(h: Slotted): int {
    if h.Slot == null {
        return 0
    } else {
        return h.Slot - 1
    }
}

// A property path narrows the way a field path does.
func DoubledPlusOne(h: Slotted): int {
    if h.Doubled == null {
        return 0
    }

    return h.Doubled + 1
}

// A TWO-HOP path. The first guard proves `h.Next`, the second proves `h.Next.Slot`.
func NextSlotTimesFive(h: Slotted): int {
    if h.Next == null {
        return -1
    }

    if h.Next.Slot == null {
        return -2
    }

    return h.Next.Slot * 5
}

// A `?.` chain that TESTED its receiver proves the receiver and the path together.
func ChainedSlotPlusTwo(h: Slotted?): int {
    if h?.Slot == null {
        return -1
    }

    return h.Slot + 2
}

// `assert` is the guard clause written the other way round.
func AssertedPathPlusFour(h: Slotted): int {
    assert h.Slot != null
    return h.Slot + 4
}

// A `[DoesNotReturnIf(false)]` argument proves the path on the flow that survives the call.
func RequiredPathPlusFive(h: Slotted): int {
    Guard.Require(h.Slot != null, "absent")
    return h.Slot + 5
}

// ── a SOURCE STRUCT behind the path ────────────────────────────────────────────────────────────

// The narrowed struct read, in all three positions: a member of it, a return of it, an argument.
func WhereRowPlusColumn(h: Slotted): int {
    if h.Where == null {
        return -1
    }

    return h.Where.Row + h.Where.Column
}

func WhereOrOrigin(h: Slotted): Cell {
    if h.Where != null {
        return h.Where
    }

    return new Cell { Row: 0, Column: 0 }
}

func WhereRowThroughArgument(h: Slotted): int {
    if !h.Where.HasValue {
        return -1
    }

    return RowOf(h.Where)
}

// An annotated local initialised from the narrowed struct path.
func StoredWhereColumn(h: Slotted): int {
    if h.Where == null {
        return -1
    }

    stored: Cell = h.Where
    return stored.Column
}

// ── the shapes that WANT the shell, still legal on a narrowed path ─────────────────────────────

func PathCoalescedAfterNarrowing(h: Slotted): int {
    if h.Slot == null {
        return -1
    }

    return h.Slot ?? 7
}

func PathHasValueAfterNarrowing(h: Slotted): bool {
    if h.Slot == null {
        return false
    }

    return h.Slot.HasValue
}

// ── what takes the fact away, run with NULL so a stale unwrap would throw ──────────────────────

// Writing the PATH ends it: the read below is a plain `int?` again.
func PathAfterOverwrite(h: Slotted, replacement: int?): int? {
    if h.Slot == null {
        return -1
    }

    h.Slot = replacement
    return h.Slot
}

// Writing a PREFIX ends it: `current` names a different object now.
func PathAfterPrefixRewrite(h: Slotted, other: Slotted): int? {
    current := h
    if current.Slot == null {
        return -1
    }

    current = other
    return current.Slot
}

func Refill(out target: Slotted, value: Slotted) {
    target = value
}

// Passing a PREFIX by `out` is a write to it.
func PathAfterOutRefill(h: Slotted, other: Slotted): int? {
    current := h
    if current.Slot == null {
        return -1
    }

    Refill(out current, other)
    return current.Slot
}

// A loop body that writes the path ends the narrowing for the whole body; the `??` observes it.
func PathAccumulatedWithReset(h: Slotted, rounds: int): int {
    if h.Slot == null {
        return -1
    }

    total := 0
    for round := 0; round < rounds; round++ {
        total = total + (h.Slot ?? 5)
        h.Slot = null
    }

    return total
}

// A branch that is left proves only its own side. Nothing here narrows `h.Slot` for the read at the
// end, so it is still a nullable and still returns the `null` it holds.
func PathUnprovedAfterBranch(h: Slotted, flag: bool): int? {
    if flag && h.Slot != null {
        return h.Slot + 100
    }

    return h.Slot
}

// A CALL ON THE RECEIVER KEEPS THE FACT, and when the call broke it the unwrap is a check, not a
// guess: the narrowed read below throws rather than answering `0 + 1`.
func PathAcrossClearingCall(h: Slotted): int {
    if h.Slot != null {
        h.Clear()
        return h.Slot + 1
    }

    return -1
}

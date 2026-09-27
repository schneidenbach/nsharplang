namespace NSharpLang.CensusFlowRules.Tests

import System


// `x.HasValue` PROVES WHAT `x != null` PROVES — compiled and RUN by the tip compiler.
//
// Not-null when true, null when false, as a null FACT on the receiver's path. It used to rebind the
// name to the inner type instead, which was harmless inside `if x.HasValue { … }` but wrong for a
// GUARD CLAUSE: the surviving flow's facts are installed into the scope that DECLARED the name, and
// there the rebind erased the `int?` itself. `x.Value` after `if !x.HasValue { throw }` reported
// NL303 "Member 'Value' not found on type 'int'", `x = null` below the guard was a type mismatch,
// and `if !h.Slot.HasValue { return }` proved nothing about the path at all — while every one of
// those programs compiled when the guard was spelt `== null`.
//
// Every function below is one of those shapes, in a local, a parameter, a loop, a struct element
// and a member path. Compiling is half the contract; the sibling `.tests.nl` runs them, so a rule
// that narrowed the wrong name would read an absent value and throw rather than merely disagree.
struct Reading {
    Level: int
}

class Gauge {
    Last: int?
    Peak: Reading?

    constructor(last: int?, peak: Reading?) {
        Last = last
        Peak = peak
    }
}

func ReadingLength(text: string): int? {
    if text.Length == 0 {
        return null
    }

    return text.Length
}

// ── the guard clause, three ways out ────────────────────────────────────────────────────────────

func LengthOrThrow(text: string): int {
    parsed := ReadingLength(text)
    if !parsed.HasValue {
        throw new FormatException("empty")
    }

    return parsed.Value + parsed
}

func LengthOrMinusOne(text: string): int {
    parsed := ReadingLength(text)
    if !parsed.HasValue {
        return -1
    }

    widened: int = parsed
    return parsed.Value * 10 + widened
}

func SumPresentLengths(texts: string[]): int {
    total := 0
    for text in texts {
        parsed := ReadingLength(text)
        if !parsed.HasValue {
            continue
        }

        total = total + parsed.Value
    }

    return total
}

// ── the positive branch, and a conjunction that reads the value it just proved ──────────────────

func LengthInBranch(text: string): int {
    parsed := ReadingLength(text)
    if parsed.HasValue {
        return parsed.Value + parsed
    }

    return 0
}

func LengthAboveOne(text: string): int {
    parsed := ReadingLength(text)
    if parsed.HasValue && parsed.Value > 1 {
        return parsed + 100
    }

    return 0
}

// ── a disjunction of two tests proves both names past the guard ─────────────────────────────────

func SumOfBoth(a: int?, b: int?): int {
    if !a.HasValue || !b.HasValue {
        return -1
    }

    return a.Value + b
}

// ── a STRUCT element: the unwrap, and the narrowed struct's own member ──────────────────────────

func LevelOrZero(reading: Reading?): int {
    local := reading
    if !local.HasValue {
        return 0
    }

    return local.Value.Level + local.Level
}

// ── the guard keeps the DECLARED nullable, so the name can still be written null ────────────────

func PresentThenCleared(text: string): int? {
    parsed := ReadingLength(text)
    if !parsed.HasValue {
        return 42
    }

    parsed = null
    return parsed
}

// ── a member PATH is narrowed by the test exactly as by `!= null` ───────────────────────────────

func LastOrMinusOne(gauge: Gauge): int {
    if !gauge.Last.HasValue {
        return -1
    }

    return gauge.Last.Value + gauge.Last.GetValueOrDefault()
}

func PeakLevelOrMinusOne(gauge: Gauge): int {
    if gauge.Peak.HasValue {
        return gauge.Peak.Value.Level
    }

    return -1
}

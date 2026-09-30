namespace NSharpLang.CensusFlowRules.Tests


// CENSUS §FLOW4 — A NARROWED `T?` IS READ AS ITS `T`, AT EMIT.
//
// THE ANALYZER ALREADY REWROTE THE TYPE. Once `if value == null { return 0 }` has run, the analyzer
// answers `int` for `value` — `must value` on the next line is reported as REDUNDANT, and a second
// `value == null` is reported as a null check on a value type. Every rule downstream of that is
// checked against `int`. The emitter had no such fact: it read the DECLARATION, saw `Nullable<int>`,
// and refused `value + 1` (no such operator), `return value` (the return type does not match) and
// `found.Line` (no such member on `Nullable<…>`). The three shapes below are the census's, and the
// only way to write them was a `must` the compiler itself called redundant.
//
// THE FACT IS THE SAME FACT, READ WITH THE SAME RULES. `ColumnarFlowNarrowingFacts` reads the
// condition shapes `AnalyzerFlowNarrowing` reads — `x != null`, `x == null`, `!`, parentheses,
// `&&`/`||`, `x.HasValue` — and the guard clause asks `AlwaysLeaves`, the analyzer's own second
// entry point, so a `break` or a `continue` guard narrows exactly as a `return` guard does.
//
// AND THE SHAPES THAT WANT THE SHELL KEEP IT. `value == null`, `value ?? 0`, `value.HasValue` and
// `value.Value` lower the `Nullable<T>` themselves and stay legal on a name flow has already proved
// present — each is still written below, after the narrowing, and each still runs.
// THE CENSUS SHAPE: arithmetic on a narrowed nullable.
func AddOneOrZero(value: int?): int {
    if value == null {
        return 0
    }

    return value + 1
}

// THE CENSUS SHAPE: returning a narrowed nullable from a non-nullable function.
func UnwrapOrFallback(value: int?): int {
    if value == null {
        return -1
    }

    return value
}

// THE CENSUS SHAPE: a member of a `?`-lifted NAMED tuple.
func LineOrFallback(found: (Uri: string, Line: int)?): int {
    if found == null {
        return -1
    }

    return found.Line
}

func UriOrFallback(found: (Uri: string, Line: int)?): string {
    if found == null {
        return "none"
    }

    return found.Uri
}

// The positional spelling of the same read.
func SecondOrFallback(pair: (string, int)?): int {
    if pair == null {
        return -1
    }

    return pair.Item2
}

// THE POSITIVE GUARD narrows its own branch rather than what follows it.
func DoubledWhenPresent(value: int?): int {
    if value != null {
        return value * 2
    }

    return 0
}

// THE ELSE BRANCH of a `== null` test is the same fact on the other side.
func TripledOrZero(value: int?): int {
    if value == null {
        return 0
    } else {
        return value * 3
    }
}

// AN `assert` IS THE GUARD CLAUSE WRITTEN THE OTHER WAY ROUND.
func AssertedPlusTen(value: int?): int {
    assert value != null
    return value + 10
}

// `x.HasValue` PROVES THE SAME THING `x != null` proves.
func HasValueThenSum(left: int?, right: int?): int {
    if !left.HasValue {
        return -1
    }

    if !right.HasValue {
        return -2
    }

    return left + right
}

// AN `&&` CHAIN proves both halves in the branch it guards.
func SumWhenBothPresent(left: int?, right: int?): int {
    if left == null || right == null {
        return -1
    }

    return left + right
}

// A `break` GUARD IS AS FINAL AS A `return` GUARD, and the narrowing after it is the same narrowing.
func SumUntilAbsent(values: int?[]): int {
    total := 0
    for index := 0; index < values.Length; index++ {
        current := values[index]
        if current == null {
            break
        }

        total = total + current
    }

    return total
}

// A `continue` GUARD LIKEWISE.
func SumPresentOnly(values: int?[]): int {
    total := 0
    for index := 0; index < values.Length; index++ {
        current := values[index]
        if current == null {
            continue
        }

        total = total + current
    }

    return total
}

// A WRITE ENDS THE NARROWING. After `value = replacement` the name holds whatever was written, so the
// `??` below is reached with the value the assignment put there and not with the one the guard proved.
func ReassignedThenCoalesced(value: int?, replacement: int?): int {
    if value == null {
        return -1
    }

    value = replacement
    return value ?? 99
}

// THE SHAPES THAT WANT THE SHELL, all written AFTER the narrowing that proved the name present.
func CoalescedAfterNarrowing(value: int?): int {
    if value == null {
        return -1
    }

    return value ?? 7
}

func HasValueAfterNarrowing(value: int?): bool {
    if value == null {
        return false
    }

    return value.HasValue
}

func ValueAfterNarrowing(value: int?): int {
    if value == null {
        return -1
    }

    return value.Value
}

// A NARROWED VALUE IS AN ORDINARY `int` EVERYWHERE ELSE TOO: as an argument, and as the initializer
// of an annotated local.
func Triple(value: int): int {
    return value * 3
}

func TripledArgument(value: int?): int {
    if value == null {
        return 0
    }

    return Triple(value)
}

func StoredThenDoubled(value: int?): int {
    if value == null {
        return 0
    }

    definitely: int = value
    return definitely + definitely
}

// A LOOP BODY THAT WRITES THE NAME ends the narrowing for the whole body, because the body runs again
// with whatever the last iteration left. The `??` is how that is observed.
func AccumulateWithReset(value: int?, rounds: int): int {
    if value == null {
        return -1
    }

    total := 0
    for round := 0; round < rounds; round++ {
        total = total + (value ?? 5)
        value = null
    }

    return total
}

// The nullable-element array both loop guards read. It is built here because an array LITERAL whose
// elements include `null` is a separate parse limit.
func PresentThenAbsent(): int?[] {
    values := new int?[](4)
    values[0] = 1
    values[1] = 2
    values[2] = null
    values[3] = 4
    return values
}

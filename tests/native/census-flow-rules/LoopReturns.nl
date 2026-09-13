namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic


// CENSUS §FLOW4 — A LOOP BODY THAT NEVER FALLS THROUGH.
//
// `for x in xs { return x }` IS NOT A DEGENERATE LOOP. It is "the first element, or the fallback" —
// the shape a converted `FirstOrDefault` hand-rolls — and the same is true of the counted spelling
// and of the scan loop whose every path either returns or `continue`s. All of them were declined at
// emit because the loop lowering refused any body that could not FALL into the increment.
//
// THE INCREMENT IS NOT REACHED BY FALLING ONLY. A `continue` branches straight at it, so a body that
// always returns leaves the increment and its back edge unreached rather than unreachable-and-wrong;
// the loop's own END POINT is reachable in every case, because the collection may be empty. That is
// why this shape needs no termination reasoning at all: the trailing `return` after the loop is
// still required and is still the one that runs when the collection is empty.
//
// The enumerator spellings (a `List<T>`, a `string`) additionally have their bottom back edge
// OMITTED when the body always returns, exactly as the `while` lowering already omitted it, so the
// emitted method contains no unreachable branch.
func FirstOrFallback(values: List<int>): int {
    for value in values {
        return value
    }

    return -1
}

func FirstArrayOrFallback(values: int[]): int {
    for value in values {
        return value
    }

    return -1
}

func FirstCharOrFallback(text: string): char {
    for character in text {
        return character
    }

    return '?'
}

func FirstCountedOrFallback(values: int[]): int {
    for index := 0; index < values.Length; index++ {
        return values[index]
    }

    return -1
}

// EVERY PATH LEAVES, AND ONE OF THEM IS A `continue`. The increment is reached through the
// `continue` alone, which is the case that proves the loop still iterates.
func FirstEvenOrFallback(values: List<int>): int {
    for value in values {
        if value % 2 == 0 {
            return value
        }

        continue
    }

    return -1
}

// THE DISPOSABLE ENUMERATOR SPELLING. A `List<T>.Enumerator` is disposable, so the loop body sits
// inside a protected region and the `return` leaves through the shared body tail — the path that
// has to keep working when the body never falls through.
func FirstPositiveOrFallback(values: IEnumerable<int>): int {
    for value in values {
        if value > 0 {
            return value
        }

        continue
    }

    return -1
}

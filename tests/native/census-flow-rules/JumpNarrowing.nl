namespace NSharpLang.CensusFlowRules.Tests


// CENSUS §3 — `break` AND `continue` NARROW WHAT FOLLOWS THEM, EXACTLY AS `return` AND `throw` DO.
//
// `if x == null { return }` handed the surviving flow the fact that `x` is not null; `break` and
// `continue` did not, even though the branch is just as gone. One converted project had 66 sites of
// the loop spelling and could not compile any of them. What the guard-clause rule asks is now
// "does the BRANCH leave", not "does the FUNCTION return".
//
// The negatives matter as much as the positives: a jump bound to a construct INSIDE the branch does
// not escape the branch, and the sources below pin both directions by running them.

// The census probe's shape: `continue` past the null, then use the value.
func SumLengthsSkippingNulls(items: string?[]): int {
    total := 0
    for item in items {
        if item == null {
            continue
        }

        total = total + item.Length
    }

    return total
}

// `break` narrows the rest of the body the same way.
func SumLengthsUntilNull(items: string?[]): int {
    total := 0
    for item in items {
        if item == null {
            break
        }

        total = total + item.Length
    }

    return total
}

// The ELSE side of the rule: the then-branch survives when the ELSE jumps.
func SumLengthsWithJumpingElse(items: string?[]): int {
    total := 0
    for item in items {
        if item != null {
            total = total + item.Length
        } else {
            continue
        }

        total = total + 1
    }

    return total
}

// `return` and `throw` still narrow — the wider question must not have lost the narrower one.
func FirstLengthOrZero(value: string?): int {
    if value == null {
        return 0
    }

    return value.Length
}

// A `while` loop with the guard at the top, which is the `Directory.GetParent` shape the census
// reduced: the narrowed value is READ after the guard and the loop terminates on the jump.
func LastNonNull(items: string?[]): string {
    result := "<none>"
    index := 0
    while index < items.Length {
        candidate := items[index]
        if candidate == null {
            break
        }

        result = candidate
        index = index + 1
    }

    return result
}

// A jump bound to a construct INSIDE the branch does not escape it, so the value stays maybe-null
// and has to be read through a null-safe form. This function exists to prove the shape still RUNS
// the way the rule says it is read.
func CountNullsWithInnerBreak(items: string?[]): int {
    nulls := 0
    for item in items {
        if item == null {
            while true {
                break
            }

            nulls = nulls + 1
        }
    }

    return nulls
}

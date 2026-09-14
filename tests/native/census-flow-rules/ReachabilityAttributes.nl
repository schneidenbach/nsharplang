namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Diagnostics.CodeAnalysis


// CENSUS §FLOW4 — `[DoesNotReturn]` AND `[DoesNotReturnIf(bool)]` AS REACHABILITY FACTS.
//
// A CALL THAT NEVER RETURNS IS A `throw` THE SIGNATURE SPELLS. `Fail(message)` is declared `void`
// and never gets there; the only thing that says so is the attribute. Once that is believed, a
// function whose last statement is such a call is COMPLETE — there is nothing after it to return
// from — and a statement written after one is unreachable exactly as it is after a `throw`. N# goes
// further than C# here deliberately: C# reads the attribute for its nullable analysis alone and
// still demands a `return` after the call.
//
// A CALL THAT NEVER RETURNS ON ONE BRANCH IS A GUARD CLAUSE THE SIGNATURE SPELLS.
// `Require([DoesNotReturnIf(false)] condition, message)` returns only when the condition held, so the
// statement after it knows what the condition proved — which is `assert`'s rule with the condition
// named by an argument instead of by a keyword. `[DoesNotReturnIf(true)]` is the mirror.
//
// THE ANNOTATION IS A CONTRACT, AND THE EMITTER TREATS IT AS ONE. At the IL level the call DOES
// return, so a value body that ends in one still needs a terminator: what is written there is the
// contract's own failure — unreachable while the callee keeps its promise, and a precise
// `InvalidOperationException` naming the callee the moment it does not.
class Guard {
    [DoesNotReturn]
    static func Fail(message: string) {
        throw new InvalidOperationException(message)
    }

    static func Require([DoesNotReturnIf(false)] condition: bool, message: string) {
        if !condition {
            throw new ArgumentException(message)
        }
    }

    static func Refuse([DoesNotReturnIf(true)] condition: bool) {
        if condition {
            throw new ArgumentException("refused")
        }
    }

    // The SAME fact reached without a receiver, from inside the declaring type.
    static func PickInside(value: int): string {
        if value > 0 {
            return "positive"
        }

        Fail("not positive")
    }
}

// A FREE FUNCTION carries the attribute the same way, and a call to it ends the path the same way.
[DoesNotReturn]
func FailFree(message: string) {
    throw new InvalidOperationException(message)
}

func PickFree(value: int): string {
    if value > 0 {
        return "positive"
    }

    FailFree("not positive")
}

// THE QUALIFIED SPELLING of the same call.
func PickQualified(value: int): string {
    if value > 0 {
        return "positive"
    }

    Guard.Fail("not positive")
}

// ONE BRANCH ENDS IN A NEVER-RETURNING CALL AND THE OTHER RETURNS, which is the `if`/`else` shape the
// rule has to answer about rather than the trailing-statement one.
func ClassifyOrFail(value: int): string {
    if value == 0 {
        Guard.Fail("zero")
    } else {
        return "non-zero"
    }
}

// A NEVER-RETURNING CALL INSIDE A `try` still leaves through the body tail every protected region
// shares, so the `finally` runs and the function needs no return after the statement.
func FailAfterCleanup(marker: string[]): string {
    try {
        Guard.Fail("always")
    } finally {
        marker[0] = "cleaned"
    }
}

// `[DoesNotReturnIf(false)]` PROVES ITS ARGUMENT ON THE PATH THAT SURVIVES, so the nullable is read
// as its element type on the next line.
func RequiredPlusOne(value: int?): int {
    Guard.Require(value != null, "absent")
    return value + 1
}

// `[DoesNotReturnIf(true)]` is the mirror: the call returned, so the argument was FALSE.
func RefusedPlusTwo(value: int?): int {
    Guard.Refuse(value == null)
    return value + 2
}

// THE REFERENCE SHAPE of the same guard, which needs no unwrap and proves the rule is about the FLOW
// rather than about nullable value types.
func RequiredLength(text: string?): int {
    Guard.Require(text != null, "absent")
    return text.Length
}

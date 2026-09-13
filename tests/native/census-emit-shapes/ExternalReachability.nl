namespace NSharpLang.CensusEmitShapes.Tests

import System
import System.Diagnostics


// `[DoesNotReturn]` AND `[DoesNotReturnIf]` ARE READ FROM BOTH SIDES OF THE SAME FENCE.
//
// The diagnostics pass already read a REFERENCED assembly's reachability attributes — a statement
// after `Environment.FailFast(...)` is NL312 unreachable — while the emitter read only the source
// side. So a value function whose last statement was such a call declined at `emit.body` for not
// always-returning, and `Debug.Assert(x != null)`, whose parameter is `[DoesNotReturnIf(false)]`,
// narrowed nothing.
class Guard {

    // A VALUE METHOD WITH NO `return`. The signature says control never reaches the end of the
    // statement, so there is nothing after it to return from. Never called: it would end the test
    // process, which is exactly the contract the annotation states.
    static func FailFastTail(message: string): int {
        Environment.FailFast(message)
    }

    // THE GUARD CLAUSE A SIGNATURE SPELLS. Reaching the next statement means the argument was true,
    // so the surviving flow is narrowed by what the argument proved — the same reader an `if` uses.
    static func AssertedLength(value: string?): int {
        Debug.Assert(value != null)
        return value.Length
    }

    // The same call as an ordinary statement, with the comparison argument that could not be typed
    // as a `bool` before: the null literal has no type of its own, so typing both operands first
    // refused the whole comparison.
    static func AssertedTrimmed(value: string?): string {
        Debug.Assert(value != null)
        return value.Trim()
    }
}

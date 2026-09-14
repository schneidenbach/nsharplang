namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Diagnostics.CodeAnalysis


// CENSUS §FLOW6 — FLOW STATE FOR A PROPERTY PATH, AND THE THINGS THAT PROVE OR UNPROVE ONE.
//
// A NARROWING USED TO BE ABOUT A NAME. `if x != null { … }` narrowed `x`, and `must x.P` narrowed
// nothing at all — so the converted daemon tests, which write `Assert.NotNull((must unknown).Error)`
// and then read `unknown.Error.Message` on the next line, were told the read might be null twice in
// four lines. The path `x.P` keeps its own state now, and the four things that establish one are
// exactly the four a C# reader expects: a guard, an unwrap, a `?? throw`, and a `[NotNull]`
// postcondition on the ARGUMENT EXPRESSION rather than on a local.
//
// AND THE THINGS THAT TAKE IT AWAY ARE WHAT MAKE IT SOUND. Writing any prefix of the path drops it,
// passing a prefix by `ref`/`out` drops it, leaving the scope drops it, and a loop's back edge drops
// everything the body writes. A METHOD CALL on the receiver does NOT — C# is deliberately optimistic
// there, and N# follows it, because a compiler that assumed every call invalidated every property
// would make guards useless.
//
// WHY THESE ARE RUNTIME CONTRACTS. Every function below both COMPILES (the analyzer half — each one
// reported NL905 before the rule) and RUNS with the narrowed value actually dereferenced, so a rule
// that narrows the wrong path throws a NullReferenceException instead of merely disagreeing. The
// negative half — what the rule deliberately refuses to prove — is a diagnostic, and its contracts
// sit beside `AnalyzerFlowNarrowing` and `AnalyzerNullFlow` in the compiler-service estate.
class ResponseError {
    Code: int
    Message: string

    constructor(code: int, message: string) {
        Code = code
        Message = message
    }
}

class DaemonResponse {
    JsonRpc: string
    Error: ResponseError?
    Reads: int

    constructor(jsonRpc: string, error: ResponseError?) {
        JsonRpc = jsonRpc
        Error = error
        Reads = 0
    }

    // A call on the receiver. It is here so a contract can prove that reaching it does NOT drop the
    // fact about `Error` — the optimistic rule, written as code that runs.
    func Touch() {
        Reads = Reads + 1
    }
}

// A source-declared `[NotNull]` member. `Assert.NotNull` is a static method on a CLASS in every
// xunit file the converter produced, and that shape used to prove nothing at all — the attribute
// reached the call validator only from a FREE function.
class Check {
    static func NotNull([NotNull] value: object?) {
        if value == null {
            throw new InvalidOperationException("expected a value")
        }
    }

    func Present([NotNull] value: object?) {
        if value == null {
            throw new InvalidOperationException("expected a value")
        }
    }
}

// ── `must` proves the path it unwrapped ────────────────────────────────────────────────────────

// The converted site: `(must unknown.Error).Code` on one line and `unknown.Error.Message` on the
// next. The unwrap throws when the path is null, so the second read cannot be reached with a null.
func ErrorCodeThenMessage(response: DaemonResponse): string {
    code := (must response.Error).Code
    return code.ToString() + ":" + response.Error.Message
}

// The same proof through a BOUND unwrap rather than an immediately-dereferenced one.
func BoundErrorThenMessage(response: DaemonResponse): string {
    error := must response.Error
    return error.Code.ToString() + ":" + response.Error.Message
}

// `must` on a plain local, which is the same rule with a one-segment path.
func UnwrappedTextLength(value: string?): int {
    length := (must value).Length
    return length + value.Length
}

// A two-hop path. The unwrap names `response.Error`, and the fact is about that path alone: the
// receiver `response` was already non-null, and nothing here says anything about `response.JsonRpc`.
func DeepPathMessageLength(response: DaemonResponse): int {
    return (must response.Error).Message.Length + response.Error.Message.Length
}

// ── a `[NotNull]` postcondition on an ARGUMENT EXPRESSION ───────────────────────────────────────

// The converted daemon assertion, verbatim in shape: the argument is a PATH written through an
// unwrap, and `must` is transparent — so the fact the call establishes is filed against
// `response.Error`, which is what the next line reads.
func AssertedErrorMessage(response: DaemonResponse?): string {
    Check.NotNull((must response).Error)
    return response.Error.Message
}

// The same thing through an INSTANCE member, because the attribute has to travel on both.
func AssertedErrorMessageViaInstance(response: DaemonResponse, check: Check): string {
    check.Present(response.Error)
    return response.Error.Message
}

// And through the BCL's own `[NotNull]` signature, so the source and reflected readers agree.
func ReflectedAssertedErrorMessage(response: DaemonResponse): string {
    ArgumentNullException.ThrowIfNull(response.Error)
    return response.Error.Message
}

// ── what takes the fact away ───────────────────────────────────────────────────────────────────

// Writing the PATH drops it. The re-check below is what the program relies on, and running it with
// a null replacement is what proves the compiler did not keep the stale answer.
func MessageAfterReset(response: DaemonResponse, replacement: ResponseError?): string {
    first := (must response.Error).Message
    response.Error = replacement
    if response.Error == null {
        return first + "|gone"
    }

    return first + "|" + response.Error.Message
}

// Writing a PREFIX drops it too — `current` is rewritten, so everything known about `current.Error`
// is stale.
func MessageAfterPrefixAssignment(seed: DaemonResponse, replacement: DaemonResponse): string {
    current := seed
    first := (must current.Error).Message
    current = replacement
    if current.Error == null {
        return first + "|gone"
    }

    return first + "|" + current.Error.Message
}

func Replace(out target: DaemonResponse, value: DaemonResponse) {
    target = value
}

// Passing a PREFIX by `out` is an assignment, so it drops the fact as surely as writing it does.
func MessageAfterOutRefill(seed: DaemonResponse, replacement: DaemonResponse): string {
    current := seed
    first := (must current.Error).Message
    Replace(out current, replacement)
    if current.Error == null {
        return first + "|gone"
    }

    return first + "|" + current.Error.Message
}

// A CALL ON THE RECEIVER KEEPS THE FACT. This is the optimistic rule, and it is the one that makes
// path narrowing usable at all: `response.Touch()` could in principle set `Error` to null, and C#
// — and now N# — does not assume it did.
func MessageAcrossReceiverCall(response: DaemonResponse): string {
    if response.Error != null {
        response.Touch()
        return response.Error.Message
    }

    return "none"
}

// ── the back edge ──────────────────────────────────────────────────────────────────────────────

// A path narrowed INSIDE a loop body, after the write that the back edge carries. The join at the
// loop head drops what the previous turn proved; the guard written here re-proves it, and the read
// under that guard is the one that must still be accepted.
func MessagesWhileResetting(response: DaemonResponse, replacement: ResponseError?, turns: int): string {
    total := ""
    turn := 0
    while turn < turns {
        if response.Error != null {
            total = total + response.Error.Message
        }

        response.Error = replacement
        turn = turn + 1
    }

    return total
}

// The `for` form, whose UPDATE CLAUSE is part of the back edge and whose INITIALIZER is not.
func MessagesForResetting(response: DaemonResponse, replacement: ResponseError?, turns: int): string {
    total := ""
    for turn := 0; turn < turns; turn++ {
        if response.Error != null {
            total = total + response.Error.Message
        }

        response.Error = replacement
    }

    return total
}

// The `foreach` form.
func MessagesForEachResetting(response: DaemonResponse, replacement: ResponseError?, turns: int[]): string {
    total := ""
    for turn in turns {
        if response.Error != null {
            total = total + response.Error.Message + turn.ToString()
        }

        response.Error = replacement
    }

    return total
}

// A loop that writes NOTHING the guard depends on keeps the fact it was given, which is the other
// half of the same rule: the kill set is the paths the body writes, not every path there is.
func MessagesWithoutResetting(response: DaemonResponse, turns: int): string {
    total := ""
    if response.Error != null {
        turn := 0
        while turn < turns {
            total = total + response.Error.Message
            turn = turn + 1
        }
    }

    return total
}

// ── A NARROWED PROPERTY PATH IS A NARROWED NULLABLE, INCLUDING FOR `Nullable<T>`'S OWN SURFACE ───
//
// The paths above are all REFERENCE nullables, where the narrowed read and the declared type are
// the same CLR type and nothing has to be unwrapped. A VALUE nullable is where the two halves of
// the narrowing machinery part company: a narrowed LOCAL is narrowed in the symbol table, so
// `count.Value` finds the declaration by walking out of the scopes, while a narrowed PATH is
// narrowed by a null FACT alone — the declared member type belongs to the class, not to the scope —
// so the read COLLAPSES `int?` to `int` and there was nothing left for the member lookup to see.
//
// `slot.Value` on a narrowed `h.Slot` therefore reported NL303 "Member 'Value' not found on type
// 'int'", and `h.Slot.GetValueOrDefault()` reported it for a member `int` never declares at all,
// for the same guard that made `h.Slot + 1` legal one line earlier.
class Sample {
    Slot: int?
    Moment: DateTime?

    constructor(slot: int?, moment: DateTime?) {
        Slot = slot
        Moment = moment
    }
}

func SlotValueOrMinusOne(sample: Sample): int {
    if sample.Slot != null {
        return sample.Slot.Value
    }

    return -1
}

func SlotDoubledOrMinusOne(sample: Sample): int {
    if sample.Slot == null {
        return -1
    }

    return sample.Slot.Value * 2
}

// `Nullable<T>`'s OWN surface on the narrowed path — the member the unwrapped `int` cannot answer.
func SlotOrDefaultThroughPath(sample: Sample): int {
    if sample.Slot != null {
        return sample.Slot.GetValueOrDefault()
    }

    return -1
}

// A `must` on the path proves it exactly as a guard does, and the unwrap is still an unwrap.
func SlotAfterMust(sample: Sample): int {
    ignored := must sample.Slot
    return sample.Slot.Value + ignored
}

// An EXTERNAL element through the same path, so the rule is about the narrowing and not about `int`.
func MomentYearThroughPath(sample: Sample): int {
    if sample.Moment != null {
        return sample.Moment.Value.Year
    }

    return -1
}

// The path's state still dies when a prefix is written, and `.Value` is not exempt from that.
func SlotAfterOverwrite(sample: Sample, replacement: int?): int {
    if sample.Slot == null {
        return -1
    }

    first := sample.Slot.Value
    sample.Slot = replacement
    return first + sample.Slot.GetValueOrDefault()
}

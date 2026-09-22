namespace NSharpLang.CensusExceptionFilters.Tests

import System
import System.Collections.Generic


// CENSUS — `catch <binding> when <expr>`, LOWERED TO A REAL CLR FILTER BLOCK.
//
// A filter is NOT a condition the handler body could have opened with, and it is not the
// catch-and-rethrow N# used to force. The CLR walks a throw in TWO passes: the first pass asks every
// enclosing handler whether it wants the exception — running each filter IN THE FRAME THAT THREW,
// with every frame between the throw and the handler still on the stack — and only then does the
// second pass unwind to the handler that said yes. A rethrow cannot reproduce that, because by the
// time a handler BODY runs the unwinding has already happened.
//
// So the observable claims this file exists to make are ORDERING claims, not just result claims:
//
//   * `FilterRunsBeforeInnerFinally` — the guard runs BEFORE a `finally` nested inside the protected
//     region. That single ordering is the whole difference between a filter and a rethrow, and it is
//     the one row that would go red if the lowering were ever quietly changed back.
//   * `UnmatchedTypeNeverAsks` — a guard is never asked about an exception whose type the clause did
//     not name. The filter block's own `isinst` short-circuits to 0, so a guard written against the
//     clause's type can read the binding without testing it first.
//   * `FalseFilterLeavesTheRegion` — a guard that answers false leaves the region for an outer
//     handler, rather than catching and re-raising.
//
// The binding is filled INSIDE the filter, which is why a guard may read it. Everything else about a
// catch clause is unchanged: declaration order still decides between two clauses that both match,
// `finally` still runs, and a bare `throw` inside the handler still rethrows.
class FilterLog {
    static Entries: List<string> = new List<string>()

    static func Reset() {
        Entries.Clear()
    }

    static func Note(text: string): bool {
        Entries.Add(text)
        return true
    }

    static func NoteAnd(text: string, verdict: bool): bool {
        Entries.Add(text)
        return verdict
    }

    // Joined by hand rather than with `String.Join`: the overload taking a sequence is not modeled by
    // the backend, and a census row must not be the place a workaround is discovered.
    static func Trace(): string {
        joined := ""
        index := 0
        while index < Entries.Count {
            if index > 0 {
                joined = joined + ","
            }
            joined = joined + Entries[index]
            index = index + 1
        }
        return joined
    }
}

// An exception this compilation declares, so a filter can read a member the clause's own type
// supplies rather than one every exception has.
class FilterError: Exception {
    code: int

    constructor(code: int): base("filter-error") {
        this.code = code
    }

    Code: int => code
}

class ExceptionFilters {

    // THE ORDERING ROW. `filter` must appear BEFORE `inner-finally`: the guard runs on the first
    // pass, while the `finally` between the throw and this handler has not run yet. A lowering that
    // caught and rethrew would print `inner-finally` first.
    static func FilterRunsBeforeInnerFinally(): string {
        FilterLog.Reset()
        try {
            try {
                throw new InvalidOperationException("boom")
            } finally {
                FilterLog.Note("inner-finally")
            }
        } catch e: InvalidOperationException when FilterLog.Note("filter") {
            FilterLog.Note("handler")
        }
        return FilterLog.Trace()
    }

    // A guard that answers FALSE does not catch: the exception carries on to the enclosing handler.
    static func FalseFilterLeavesTheRegion(): string {
        FilterLog.Reset()
        try {
            try {
                throw new FilterError(9)
            } catch e: FilterError when e.Code == 7 {
                FilterLog.Note("wrong-handler")
            }
        } catch outer: FilterError {
            FilterLog.Note("outer:" + outer.Code.ToString())
        }
        return FilterLog.Trace()
    }

    // The clause's TYPE is tested before the guard is, so a guard is never asked about an exception
    // of a type this clause did not name. `asked` must NOT appear.
    static func UnmatchedTypeNeverAsks(): string {
        FilterLog.Reset()
        try {
            try {
                throw new ArgumentException("arg")
            } catch e: FilterError when FilterLog.Note("asked") {
                FilterLog.Note("wrong-handler")
            }
        } catch outer: ArgumentException {
            FilterLog.Note("outer")
        }
        return FilterLog.Trace()
    }

    // Two clauses of the SAME type, separated only by their guards: the first whose guard answers
    // true is the one that runs, and the second guard is never asked.
    static func FirstTrueGuardWins(code: int): string {
        FilterLog.Reset()
        try {
            throw new FilterError(code)
        } catch e: FilterError when FilterLog.NoteAnd("ask-low", e.Code < 10) {
            return "low:" + FilterLog.Trace()
        } catch e: FilterError when FilterLog.NoteAnd("ask-high", e.Code >= 10) {
            return "high:" + FilterLog.Trace()
        }
    }

    // A guard on a BARE catch — no type written. `catch when` is the spelling, and the clause still
    // catches everything the guard admits.
    static func BareFilteredCatch(): string {
        FilterLog.Reset()
        try {
            throw new ArgumentException("bare")
        } catch when FilterLog.Note("bare-filter") {
            FilterLog.Note("bare-handler")
        }
        return FilterLog.Trace()
    }

    // The binding is filled before the guard runs, so a guard may read the caught instance's own
    // members — including one only the clause's type declares.
    static func GuardReadsTheBinding(code: int): string {
        try {
            throw new FilterError(code)
        } catch e: FilterError when e.Code == 4 {
            return "four"
        } catch e: FilterError {
            return "other:" + e.Code.ToString()
        }
    }

    // What the guard PROVES is available in the handler. `e.InnerException` is nullable, and the
    // handler reads it without a second test because the guard is the test — the same relation an
    // `if` condition has with its then-branch.
    static func FilterNarrowsForTheHandler(withInner: bool): string {
        try {
            if withInner {
                throw new InvalidOperationException("outer", new ArgumentException("inner"))
            }
            throw new InvalidOperationException("outer")
        } catch e: InvalidOperationException when e.InnerException != null {
            return e.InnerException.Message
        } catch e: InvalidOperationException {
            return "none"
        }
    }

    // A filter beside an UNFILTERED clause of the same type: the filtered one is written first, so
    // it gets first refusal and the unfiltered one is the fallback.
    static func FilteredThenUnfiltered(code: int): string {
        try {
            throw new FilterError(code)
        } catch e: FilterError when e.Code == 1 {
            return "one"
        } catch e: FilterError {
            return "fallback:" + e.Code.ToString()
        }
    }

    // `finally` still runs, and it runs AFTER the filter and before the handler body completes —
    // the full three-part order of a filtered catch with a finally beside it.
    static func FinallyStillRuns(): string {
        FilterLog.Reset()
        try {
            try {
                throw new FilterError(3)
            } catch e: FilterError when FilterLog.Note("filter") {
                FilterLog.Note("handler")
            } finally {
                FilterLog.Note("finally")
            }
        } catch outer: Exception {
            FilterLog.Note("escaped")
        }
        return FilterLog.Trace()
    }

    // A bare `throw` inside a FILTERED handler still rethrows, and the outer handler sees the
    // original instance.
    static func RethrowFromFilteredHandler(): string {
        FilterLog.Reset()
        try {
            try {
                throw new FilterError(5)
            } catch e: FilterError when e.Code == 5 {
                FilterLog.Note("rethrowing")
                throw
            }
        } catch outer: FilterError {
            FilterLog.Note("caught:" + outer.Code.ToString())
        }
        return FilterLog.Trace()
    }

    // A SECOND filtered pair, written with the same binding form the formatter canonicalizes to. The
    // parenthesized spellings also take a guard; that is a PARSER fact and is pinned in the estate
    // (`ColumnarParserStatements.tests.nl`), because the formatter rewrites `catch (e: T)` to
    // `catch e: T` and a formatted source file cannot hold the other spelling.
    static func SecondFilteredPair(code: int): string {
        try {
            throw new FilterError(code)
        } catch e: FilterError when e.Code == 2 {
            return "two"
        } catch e: FilterError {
            return "other"
        }
    }

    // THE CONTROL. Same shape, no `when`: its clause row must carry no filter bit, so the bit the
    // rows beside it assert is a property of the FILTER and not of a try statement.
    static func UnfilteredControl(code: int): string {
        try {
            throw new FilterError(code)
        } catch e: FilterError {
            return "caught:" + e.Code.ToString()
        }
    }

    // A guard with no binding at all — the type is written, the variable is not.
    static func TypeOnlyClauseTakesAFilter(): string {
        FilterLog.Reset()
        try {
            throw new FilterError(6)
        } catch (FilterError) when FilterLog.Note("type-only-filter") {
            FilterLog.Note("type-only-handler")
        }
        return FilterLog.Trace()
    }
}

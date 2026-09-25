namespace NSharpLang.CensusCatchTypes.Tests

import System
import System.Net.Sockets
import System.Text.Json


// CENSUS — THE TYPE A `catch` CLAUSE NAMES, EXECUTED.
//
// A typed catch clause used to be resolved by a CORELIB-ONLY index, so `catch ex: SocketException`
// (System.Net.Primitives), `catch ex: JsonException` (System.Text.Json) and a catch of an exception
// this compilation DECLARES all declined at `emit.statement.block-child` — while `new
// SocketException(...)`, `throw` of one and `ex as SocketException` in the same file all emitted.
// The clause now resolves its type the way every other written type does, so the rows below are
// real IL: each one throws and is caught, and the value each returns says which clause ran.

// An exception THIS COMPILATION declares. It carries a code so a handler can prove it caught the
// instance that was thrown rather than merely reaching the clause.
class CensusCatchError: Exception {
    code: int

    constructor(code: int) {
        this.code = code
    }

    Code: int => code
}

// A derived source exception, so the declaration-order rule can be tested with a base and a derived
// clause that both match the thrown value.
class CensusCatchFatalError: CensusCatchError {
    constructor(code: int): base(code) {
    }
}

class CatchTypes {

    // System.Net.Primitives: the exception named in the clause is not in the core assembly and is
    // not reachable through any hand-written table.
    static func SocketFailure(errorCode: int): string {
        try {
            throw new SocketException(errorCode)
        } catch ex: SocketException {
            return ex.SocketErrorCode.ToString()
        }
    }

    // System.Text.Json, thrown by the framework rather than by this file, so the caught instance is
    // one the runtime constructed.
    static func ParseFailureMessageLength(text: string): int {
        try {
            document := JsonDocument.Parse(text)
            return -document.RootElement.GetArrayLength()
        } catch ex: JsonException {
            return ex.Message.Length
        }
    }

    // A source-declared exception: the clause names a type this compilation is writing, which has no
    // metadata to be indexed from at all.
    static func SourceErrorCode(code: int): int {
        try {
            throw new CensusCatchError(code)
        } catch ex: CensusCatchError {
            return ex.Code
        }
    }

    // FIRST MATCH IN DECLARATION ORDER, across three assemblies in one try. The clauses are ordered
    // socket, json, source, and the answer names which one ran.
    static func ClassifyThrown(kind: int): string {
        try {
            if kind == 0 {
                throw new SocketException(10061)
            }
            if kind == 1 {
                throw new JsonException("bad json")
            }
            if kind == 2 {
                throw new CensusCatchError(7)
            }
            throw new InvalidOperationException("other")
        } catch ex: SocketException {
            return "socket:" + ex.SocketErrorCode.ToString()
        } catch ex: JsonException {
            return "json:" + ex.Message
        } catch ex: CensusCatchError {
            return "source:" + ex.Code.ToString()
        } catch ex: Exception {
            return "base:" + ex.Message
        }
    }

    // A BASE clause written before a DERIVED one still wins, because the CLR takes the first
    // matching handler in declaration order — the same rule for source types as for BCL ones.
    static func BaseBeforeDerived(): string {
        try {
            throw new CensusCatchFatalError(3)
        } catch ex: CensusCatchError {
            return "base:" + ex.Code.ToString()
        } catch ex: CensusCatchFatalError {
            return "derived:" + ex.Code.ToString()
        }
    }

    // The derived clause written FIRST catches the derived value and leaves the base clause for
    // everything else.
    static func DerivedBeforeBase(fatal: bool): string {
        try {
            if fatal {
                throw new CensusCatchFatalError(4)
            }
            throw new CensusCatchError(5)
        } catch ex: CensusCatchFatalError {
            return "derived:" + ex.Code.ToString()
        } catch ex: CensusCatchError {
            return "base:" + ex.Code.ToString()
        }
    }

    // A clause whose exception type does NOT match leaves the region, so an outer handler sees it.
    static func UnmatchedFallsThrough(): string {
        try {
            try {
                throw new InvalidOperationException("inner")
            } catch ex: SocketException {
                return "socket:" + ex.SocketErrorCode.ToString()
            }
        } catch ex: InvalidOperationException {
            return "outer:" + ex.Message
        }
    }

    // A BARE catch is still the catch-all region, and a non-corelib exception lands in it.
    static func BareCatchAll(): string {
        try {
            throw new SocketException(10054)
        } catch {
            return "bare"
        }
    }

    // A `finally` still runs when the typed clause that ran names a non-corelib exception.
    static func FinallyRunsAfterExternalCatch(log: System.Collections.Generic.List<string>): string {
        try {
            throw new JsonException("x")
        } catch ex: JsonException {
            log.Add("catch")
            return "caught:" + ex.Message
        } finally {
            log.Add("finally")
        }
    }

    // The bound variable keeps the CLAUSE'S type, so a member only that type declares is readable.
    static func BoundVariableIsTheClauseType(): string {
        try {
            throw new SocketException(10060)
        } catch ex: SocketException {
            return ex.SocketErrorCode == SocketError.TimedOut ? "timed-out" : "other"
        }
    }
}

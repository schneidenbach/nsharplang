namespace NSharpLang.CensusNarrowedNullableArgument.Tests

import System
import System.Collections.Generic

// A NAME FLOW HAS PROVED PRESENT, PASSED AS AN ARGUMENT.
//
// `return v`, `x: int = v`, `v * 2` and `k == Kind.Method` all emit for a `Nullable<T>` name a null
// check has narrowed — the emitter drops the shell over the value the ordinary read produced. An
// ARGUMENT did not, because the call was typed by a door that resolves bindings from the raw maps,
// where the name still carries the `Nullable<T>` its declaration gave it. The two walks therefore
// disagreed about one value, and NL907 turned the disagreement into a trap: it called the `must`
// that makes the call compile redundant, and removing it as advised declined the build.
//
// These subjects are that argument in each of the call families, with the controls that already
// emitted beside them.
enum SymbolKind {
    Method,
    Field
}

class Facts {
    static func IsCallable(kind: SymbolKind): bool {
        return kind == SymbolKind.Method
    }

    // The reported shape: an enum? narrowed, then passed where the bare enum is declared — with NO
    // `must`, which is the spelling NL907 asks for.
    static func IsCallableSymbol(typedKind: SymbolKind?): bool {
        if typedKind != null {
            return IsCallable(typedKind)
        }
        return false
    }

    // The same, written with the unwrap. Both spellings must compile and must agree.
    static func IsCallableSymbolUnwrapped(typedKind: SymbolKind?): bool {
        if typedKind != null {
            return IsCallable(must typedKind)
        }
        return false
    }

    static func Twice(value: int): int {
        return value * 2
    }

    static func TwiceOrZero(value: int?): int {
        if value != null {
            return Twice(value)
        }
        return 0
    }

    // An EXTERNAL static, and an EXTERNAL generic instance method whose type argument is inferred
    // from this argument alone.
    static func ClampedOrZero(value: int?): int {
        if value != null {
            return Math.Clamp(value, 0, 10)
        }
        return 0
    }

    static func HashOrZero(value: int?): int {
        if value != null {
            hash := new HashCode()
            hash.Add(value)
            return hash.ToHashCode()
        }
        return 0
    }

    // CONTROLS. A parameter that is ITSELF nullable still takes the narrowed name; the positions
    // that never selected on argument types still emit; and the declared value still reaches them.
    static func TakeNullable(value: int?): int {
        if value == null {
            return -1
        }
        return 1
    }

    static func PassThroughNullable(value: int?): int {
        if value != null {
            return TakeNullable(value)
        }
        return 0
    }

    static func ReturnedDirectly(value: int?): int {
        if value != null {
            return value
        }
        return 0
    }

    static func TypedLocal(value: int?): int {
        if value != null {
            copy: int = value
            return copy
        }
        return 0
    }

    static func Doubled(value: int?): int {
        if value != null {
            return value * 2
        }
        return 0
    }
}

// EVALUATION ORDER AND COUNT. The narrowed name is read through a property that records itself, so
// "once, before the second argument" is stated rather than assumed.
class Reader {
    Reads: List<string> = new List<string>()

    Value: int? {
        get {
            Reads.Add("value")
            return 3
        }
    }

    func Ceiling(): int {
        Reads.Add("ceiling")
        return 9
    }

    func Run(): int {
        held := Value
        if held != null {
            return Facts.Twice(held) + Ceiling()
        }
        return 0
    }
}

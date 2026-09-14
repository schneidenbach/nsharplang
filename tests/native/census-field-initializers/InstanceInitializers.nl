namespace NSharpLang.CensusFieldInitializers.Tests

import System.Collections.Generic


// The instance half of the census table. `3 + 4` and `"a" + "b"` are the two rows that used to
// decline: an initializer opening on a literal token was read as that single literal, and the rest
// of the expression was then met where the next member was expected.
class InstanceCensus {
    readonly Scale: int = 3 + 4
    readonly Label: string = "a" + "b"
    readonly Limit: int = int.MaxValue
    readonly Negative: int = -1
    readonly Names: List<string> = new List<string>()
    Mutable: int = 2 * 5
}

// An initializer over PRIMARY-CONSTRUCTOR parameters. A bare parameter name makes the field that
// parameter's storage; an expression over the parameters is an ordinary initializer that reads them.
class Boxed(width: int, height: int) {
    Width: int = width
    Area: int = width * height
}

// Instance initializers run BEFORE the base constructor call in the derived constructor, which is
// what lets a base constructor observe a derived field that a virtual call reaches. The trace
// records the order the three steps actually ran in.
class OrderBase {
    Trace: string

    constructor() {
        Trace = OrderTrace.Note("base-ctor")
    }
}

class OrderDerived: OrderBase {
    readonly Marker: int = OrderTrace.Mark("derived-init")

    constructor() {
        OrderTrace.Note("derived-body")
    }
}

class OrderTrace {
    static Log: string = ""

    static func Note(step: string): string {
        Log = Log + step + ";"
        return Log
    }

    static func Mark(step: string): int {
        Log = Log + step + ";"
        return Log.Length
    }
}

// AN IMPLICITLY-DEFAULTED NULLABLE FIELD BESIDE A WRITTEN INITIALIZER. `Absent: string?` carries no
// `= null`, so the store the initializer body synthesizes for it has no `=` token anywhere in the
// source and its operator span is -1. Reading that span crashed the compiler outright
// (ArgumentOutOfRangeException out of Substring, before any diagnostic): six ordinary lines refused
// to compile at all, for `nlc check`, `build`, `run` and the MSBuild task alike. The shape only
// reaches the initializer planner when the type ALSO has a written initializer, which is why a type
// of nothing but nullable fields never showed it.
class NullableBesideWritten {
    Absent: string?
    AbsentNumber: int?
    Present: int = 2
    PresentText: string = "set"
}

// The same shape with the nullable field written LAST, and with an explicit `= null` beside it —
// both spellings have to land on the same values.
class NullableAfterWritten {
    Present: int = 3
    Absent: string?
    Explicit: string? = null
}

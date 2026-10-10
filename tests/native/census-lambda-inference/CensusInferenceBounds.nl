namespace NSharpLang.CensusLambdaInference.Tests

import System.Collections.Generic
import System.Linq


// TWO INFERENCE BOUNDS FOR ONE TYPE PARAMETER, WHERE ONE IS THE OTHER'S NULLABLE LIFT.
//
// The converter census wrote `Assert.Equal(expected, lspDiagnostic.Severity)` seven times: `expected`
// is a `DiagnosticSeverity` and the property is a `DiagnosticSeverity?`, so the two arguments of a
// REFLECTED `Equal<T>(T, T)` offered `X` and `X?` for the same `T`. Inference bound `T` from the
// first argument and then refused the second, and the call reported NL402 "no overload accepts 2
// arguments with these types".
//
// C# fixes a type parameter to the one bound every other bound converts to. `X` converts to `X?` and
// `X?` does not convert back, so the pair fixes `T` to `X?` — the same lifting rule the conditional
// operator's common type already used. The relation is stated once on each side of the compiler
// (`AnalyzerConversionFacts.IsNullableLiftOf` for the analyzer's two binding maps,
// `ColumnarTypeEquivalenceFacts.IsNullableLiftOf` for the two emit-time unifiers) so the call the
// analyzer admits is the call the backend closes.
enum Level {
    Low,
    High
}

class Reading {
    Severity: Level?

    constructor(Severity: Level?) {
        this.Severity = Severity
    }
}

func ReadingWith(severity: Level?): Reading {
    return new Reading(severity)
}

// A REFLECTED member whose type is `X?`: `FirstOrDefault` over a `List<int?>` returns `int?`, so the
// literal `3` and this call are the `X`/`X?` pair with neither side written by this project.
func FirstBoxedOrNull(values: List<int?>): int? {
    return values.FirstOrDefault()
}

func MaybeName(present: bool): string? {
    if present {
        return "alpha"
    }

    return null
}

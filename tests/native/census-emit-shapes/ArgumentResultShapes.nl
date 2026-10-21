namespace NSharpLang.CensusEmitShapes.Tests

import System
import System.Text
import System.Text.Json

record ArgumentShapesFlagged {
    Flag: bool?
}

// A mixed `double / int` binary is a `double`; the literal is promoted before overload selection.
func SineOfHalf(x: double): double {
    return Math.Sin(x / 2)
}

func SineOfHalfText(x: double): string {
    return Math.Sin(x / 2).ToString()
}

// The nested-argument type path is independent from generic-call inference. The inferred spelling
// `Serialize(d)` is owned by the generic-calls slice; this explicit form pins the nested type path.
func SerializedByteCountNested(d: string[]): int {
    bytes := Encoding.UTF8.GetBytes(JsonSerializer.Serialize<string[]>(d))
    return bytes.Length
}

// A member read of an operator result as the argument of an overloaded static call.
func AbsDays(a: DateTime, b: DateTime): double {
    d := Math.Abs((a - b).TotalDays)
    return d
}

func ClampedRatio(elapsed: double, span: double): double {
    r := Math.Min(1.0, Math.Max(0.0, elapsed / span))
    return r
}

func FlagIsTrue(text: string): bool {
    ok := (must JsonSerializer.Deserialize<ArgumentShapesFlagged>(text)).Flag == true
    return ok
}

func FlagIsFalse(text: string): bool {
    return (must JsonSerializer.Deserialize<ArgumentShapesFlagged>(text)).Flag == false
}

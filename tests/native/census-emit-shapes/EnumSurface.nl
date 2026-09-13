namespace NSharpLang.CensusEmitShapes.Tests


// THE INSTANCE SURFACE A SOURCE ENUM INHERITS IS `System.Enum`, not `object`. Every member below is
// one the CLR gives every enum value; before this slice the analyzer resolved an enum's instance
// members against `object`, so `ToString()` came back `string?` (NL905 on any use of the result) and
// `HasFlag` was "not found on type". The declarations here are ordinary N# — nothing in them is
// specific to the fix — and the tests beside them execute the emitted IL.
enum Access {
    None = 0,
    Read = 1,
    Write = 2,
    All = 3
}

func AccessName(value: Access): string {
    return value.ToString()
}

func AccessNameLowered(value: Access): string {
    return value.ToString().ToLower()
}

func AccessHasFlag(value: Access, flag: Access): bool {
    return value.HasFlag(flag)
}

func AccessTypeCode(value: Access): TypeCode {
    return value.GetTypeCode()
}

// The bitwise spelling of the same question, over two enum VALUES rather than a call.
func AccessHasFlagByMask(value: Access, flag: Access): bool {
    return (value & flag) == flag
}

func AccessCombined(left: Access, right: Access): Access {
    return left | right
}

// `enum as <numeric>`: a source enum's underlying value. The reflected-enum spelling
// (`DayOfWeek as int`) already emitted; this one declined because the emitter's cast arm asked a
// narrower "is an enum" than the target side of the same conversion did.
func AccessOrdinal(value: Access): int {
    return value as int
}

func AccessOrdinalWide(value: Access): long {
    return value as long
}

func ExternalOrdinal(day: DayOfWeek): int {
    return day as int
}

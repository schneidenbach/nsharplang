namespace NSharpLang.CensusEmitShapes.Tests
import System.Collections.Generic


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

// A REFLECTED enum's member read, and its underlying value, in ordinary expression position and
// inside an ITERATOR body — the census reported the member read as declining, and it emits.
func ExternalOrdinal(day: DayOfWeek): int {
    return (int)day
}

func IsMidweek(day: DayOfWeek): bool {
    return day == DayOfWeek.Wednesday
}

func* Weekend(): IEnumerable<DayOfWeek> {
    yield DayOfWeek.Saturday
    yield DayOfWeek.Sunday
}

func* WeekdayOrdinals(): IEnumerable<int> {
    yield (int)DayOfWeek.Monday
    yield (int)DayOfWeek.Friday
}

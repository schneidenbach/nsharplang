namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System.Globalization


// These are the three exact static BCL calls the static-field initializer owner needs.  Keeping the
// probe self-contained makes the seed package check compile the actual signatures and by-ref writes
// without relying on the broader Reflection.Emit bootstrap fixture.
class NumericStaticBindingEmitProbe {
    static func TryParseInt64(text: string, out value: long): bool {
        return Int64.TryParse(text, out value)
    }

    static func TryParseUInt64(text: string, out value: ulong): bool {
        return UInt64.TryParse(text, out value)
    }

    static func TryParseStyledDouble(text: string, out value: double): bool {
        return Double.TryParse(
            text,
            NumberStyles.Float | NumberStyles.AllowThousands,
            CultureInfo.InvariantCulture,
            out value
        )
    }
}

test "N# binds exact Int64 UInt64 and styled Double TryParse calls with BCL out results" {
    signed := 0L
    assert NumericStaticBindingEmitProbe.TryParseInt64("-17", out signed)
    assert signed == -17L
    assert NumericStaticBindingEmitProbe.TryParseInt64("9223372036854775807", out signed)
    assert signed == 9223372036854775807L
    assert NumericStaticBindingEmitProbe.TryParseInt64("-9223372036854775808", out signed)
    assert signed == 0L - 9223372036854775807L - 1L
    signed = 99L
    assert !NumericStaticBindingEmitProbe.TryParseInt64("not-a-long", out signed)
    assert signed == 0L
    signed = 99L
    assert !NumericStaticBindingEmitProbe.TryParseInt64("9223372036854775808", out signed)
    assert signed == 0L

    unsigned := 0UL
    assert NumericStaticBindingEmitProbe.TryParseUInt64("17", out unsigned)
    assert unsigned == 17UL
    assert NumericStaticBindingEmitProbe.TryParseUInt64("18446744073709551615", out unsigned)
    assert unsigned == 18446744073709551615UL
    unsigned = 99UL
    assert !NumericStaticBindingEmitProbe.TryParseUInt64("-17", out unsigned)
    assert unsigned == 0UL
    unsigned = 99UL
    assert !NumericStaticBindingEmitProbe.TryParseUInt64("18446744073709551616", out unsigned)
    assert unsigned == 0UL

    floating := 0.0
    assert NumericStaticBindingEmitProbe.TryParseStyledDouble("1,234.5", out floating)
    assert floating == 1234.5
    floating = 99.0
    assert !NumericStaticBindingEmitProbe.TryParseStyledDouble("not-a-double", out floating)
    assert floating == 0.0
}

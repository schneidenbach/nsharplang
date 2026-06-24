using System;

namespace NSharpLang.Compiler;

internal static class NumericLiteralFacts
{
    public static bool TryParseUnsignedIntegerMagnitude(string text, out ulong value)
    {
            value = ParseUnsignedIntegerMagnitude(text);
            return true;
    }

    public static ulong ParseUnsignedIntegerMagnitude(string text)
    {
        var span = text.AsSpan();
        while (span.Length > 0 && (span[^1] == 'u' || span[^1] == 'U' || span[^1] == 'l' || span[^1] == 'L'))
        {
            span = span[..^1];
        }

        var clean = span.ToString().Replace("_", "");

        if (clean.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            return ulong.Parse(clean[2..], System.Globalization.NumberStyles.HexNumber, System.Globalization.CultureInfo.InvariantCulture);
        if (clean.StartsWith("0b", StringComparison.OrdinalIgnoreCase))
            return Convert.ToUInt64(clean[2..], 2);
        if (clean.StartsWith("0o", StringComparison.OrdinalIgnoreCase))
            return Convert.ToUInt64(clean[2..], 8);

        return ulong.Parse(clean, System.Globalization.CultureInfo.InvariantCulture);
    }

    public static (bool HasUnsigned, bool HasLong) GetIntegerSuffix(string text)
    {
        var hasUnsigned = false;
        var hasLong = false;
        var span = text.AsSpan();

        while (span.Length > 0)
        {
            var last = span[^1];
            if (last == 'u' || last == 'U')
            {
                hasUnsigned = true;
            }
            else if (last == 'l' || last == 'L')
            {
                hasLong = true;
            }
            else
            {
                break;
            }

            span = span[..^1];
        }

        return (hasUnsigned, hasLong);
    }
}

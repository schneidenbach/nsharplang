namespace NSharpLang.Compiler

import System
import System.Globalization

public class NumericLiteralFacts {
    public static func TryParseUnsignedIntegerMagnitude(text: string, out value: ulong): bool {
        value = ParseUnsignedIntegerMagnitude(text)
        return true
    }

    public static func ParseUnsignedIntegerMagnitude(text: string): ulong {
        end := text.Length
        while end > 0 {
            last := text[end - 1]
            if last == 'u' || last == 'U' || last == 'l' || last == 'L' {
                end = end - 1
            } else {
                break
            }
        }

        clean := text.Substring(0, end).Replace("_", "")

        if clean.StartsWith("0x", StringComparison.OrdinalIgnoreCase) {
            return UInt64.Parse(clean.Substring(2), NumberStyles.HexNumber, CultureInfo.InvariantCulture)
        }

        if clean.StartsWith("0b", StringComparison.OrdinalIgnoreCase) {
            return Convert.ToUInt64(clean.Substring(2), 2)
        }

        if clean.StartsWith("0o", StringComparison.OrdinalIgnoreCase) {
            return Convert.ToUInt64(clean.Substring(2), 8)
        }

        return UInt64.Parse(clean, CultureInfo.InvariantCulture)
    }

    public static func GetIntegerSuffix(text: string): NumericLiteralIntegerSuffix {
        hasUnsigned := false
        hasLong := false
        end := text.Length

        while end > 0 {
            last := text[end - 1]
            if last == 'u' || last == 'U' {
                hasUnsigned = true
            } else if last == 'l' || last == 'L' {
                hasLong = true
            } else {
                break
            }

            end = end - 1
        }

        return new NumericLiteralIntegerSuffix(hasUnsigned, hasLong)
    }
}

public class NumericLiteralIntegerSuffix {
    hasUnsignedValue: bool
    hasLongValue: bool
    HasUnsigned: bool => hasUnsignedValue
    HasLong: bool => hasLongValue

    constructor(hasUnsigned: bool, hasLong: bool) {
        hasUnsignedValue = hasUnsigned
        hasLongValue = hasLong
    }
}

namespace NSharpLang.Compiler

import System
import System.Globalization

class NumericLiteralFacts {
    static func GetFloatLiteralTypeInfo(text: string): TypeInfo {
        trimmed := text.Trim()
        if trimmed.EndsWith("m", StringComparison.OrdinalIgnoreCase) {
            return BuiltInTypes.Decimal
        }

        if trimmed.EndsWith("f", StringComparison.OrdinalIgnoreCase) {
            return BuiltInTypes.Float
        }

        return BuiltInTypes.Double
    }

    static func TryGetIntegerLiteralTypeInfo(clrType: Type, out typeInfo: SimpleTypeInfo): bool {
        if clrType == typeof(byte) {
            typeInfo = BuiltInTypes.Byte
            return true
        }

        if clrType == typeof(sbyte) {
            typeInfo = BuiltInTypes.SByte
            return true
        }

        if clrType == typeof(short) {
            typeInfo = BuiltInTypes.Short
            return true
        }

        if clrType == typeof(ushort) {
            typeInfo = BuiltInTypes.UShort
            return true
        }

        if clrType == typeof(int) {
            typeInfo = BuiltInTypes.Int
            return true
        }

        if clrType == typeof(uint) {
            typeInfo = BuiltInTypes.UInt
            return true
        }

        if clrType == typeof(long) {
            typeInfo = BuiltInTypes.Long
            return true
        }

        if clrType == typeof(ulong) {
            typeInfo = BuiltInTypes.ULong
            return true
        }

        if clrType == typeof(char) {
            typeInfo = BuiltInTypes.Char
            return true
        }

        typeInfo = BuiltInTypes.Int
        return false
    }

    static func TryGetNegativeIntegerLiteralMaxMagnitude(typeName: string, out maxMagnitude: ulong): bool {
        if typeName == "sbyte" {
            maxMagnitude = 128UL
            return true
        }

        if typeName == "short" {
            maxMagnitude = 32768UL
            return true
        }

        if typeName == "int" {
            maxMagnitude = 2147483648UL
            return true
        }

        if typeName == "long" {
            maxMagnitude = 9223372036854775808UL
            return true
        }

        maxMagnitude = 0UL
        return false
    }

    static func TryGetUnsignedIntegerLiteralMaxValue(typeName: string, out maxValue: ulong): bool {
        if typeName == "byte" {
            maxValue = 255UL
            return true
        }

        if typeName == "sbyte" {
            maxValue = 127UL
            return true
        }

        if typeName == "short" {
            maxValue = 32767UL
            return true
        }

        if typeName == "ushort" || typeName == "char" {
            maxValue = 65535UL
            return true
        }

        if typeName == "int" {
            maxValue = 2147483647UL
            return true
        }

        if typeName == "uint" {
            maxValue = 4294967295UL
            return true
        }

        if typeName == "long" {
            maxValue = 9223372036854775807UL
            return true
        }

        if typeName == "ulong" {
            maxValue = 18446744073709551615UL
            return true
        }

        maxValue = 0UL
        return false
    }

    static func TryParseUnsignedIntegerMagnitude(text: string, out value: ulong): bool {
        try {
            value = ParseUnsignedIntegerMagnitude(text)
            return true
        } catch _format: FormatException {
            value = 0UL
            return false
        } catch _overflow: OverflowException {
            value = 0UL
            return false
        } catch _argument: ArgumentException {
            value = 0UL
            return false
        }
    }

    static func ParseUnsignedIntegerMagnitude(text: string): ulong {
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

    static func GetIntegerSuffix(text: string): NumericLiteralIntegerSuffix {
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

    // kind 0 = unsuffixed Int32, 1 = signed Int64 (L), 2 = UInt64 (UL/LU), 3 = UInt32 (U).
    //
    // KIND 3 IS DECIDED AFTER THE BODY IS PARSED, BECAUSE C# DECIDES IT BY MAGNITUDE.
    // ECMA-334 §6.4.5.3: a lone `u`/`U` names the FIRST of `uint`, `ulong` whose range holds the
    // value -- so `256U` is `uint` and `5000000000U` is `ulong`, and no suffix spelling
    // distinguishes them. `AnalyzerLiteralExpressions` already states and applies that rule; this
    // parser (then in `ColumnarScalarLiteralPlanner`) published only kinds 0/1/2 and dropped a bare
    // `U` into its `else` as MALFORMED, so the analyzer accepted `256U` and the emitter then
    // declined the whole assembly at `emit.local.initializer` naming the LOCAL. The rejection was contract-pinned as a wall
    // (`invalidIntegers[4] = "1U"`) and, a second time, as the malformed sample of the rollback
    // contract -- while `AnalyzerLiteralExpressions.tests.nl` asserts `1u` is `uint`. The two owners
    // disagreed IN THEIR OWN CONTRACT SUITES, and neither suite could see the other, which is why no
    // probe had ever contradicted the emitter.
    static func TryParseIntegerLiteral(text: string, out literalKind: int, out magnitude: ulong): bool {
        literalKind = 0
        magnitude = 0UL
        if text.Length == 0 {
            return false
        }

        end := text.Length
        hasUnsigned := false
        hasLong := false
        suffixLength := 0
        while end > 0 {
            last := text[end - 1]
            if last == 'u' || last == 'U' {
                if hasUnsigned {
                    return false
                }
                hasUnsigned = true
            } else if last == 'l' || last == 'L' {
                if hasLong {
                    return false
                }
                hasLong = true
            } else {
                break
            }
            suffixLength = suffixLength + 1
            if suffixLength > 2 {
                return false
            }
            end = end - 1
        }

        if suffixLength == 0 {
            literalKind = 0
        } else if suffixLength == 1 && hasLong && !hasUnsigned {
            literalKind = 1
        } else if suffixLength == 2 && hasLong && hasUnsigned {
            literalKind = 2
        } else if suffixLength == 1 && hasUnsigned && !hasLong {
            literalKind = 3
        } else {
            return false
        }

        if !TryParseIntegerBody(text, end, out magnitude) {
            return false
        }

        // The magnitude-dependent half of §6.4.5.3. A `U` too large for `uint` is `ulong`, not an
        // error -- the same literal, one kind further along.
        if literalKind == 3 && magnitude > 4294967295UL {
            literalKind = 2
        }
        return true
    }

    static func TryParseIntegerBody(text: string, end: int, out magnitude: ulong): bool {
        magnitude = 0UL
        if end <= 0 {
            return false
        }
        radix := 10
        index := 0
        if end >= 2 && text[0] == '0' {
            marker := text[1]
            if marker == 'x' || marker == 'X' {
                radix = 16
                index = 2
            } else if marker == 'b' || marker == 'B' {
                radix = 2
                index = 2
            }
        }
        if index >= end {
            return false
        }
        firstDigit := IntegerDigitValue(text[index])
        if firstDigit < 0 || firstDigit >= radix {
            return false
        }

        digitCount := 0
        while index < end {
            ch := text[index]
            if ch == '_' {
                index = index + 1
                continue
            }
            digit := IntegerDigitValue(ch)
            if digit < 0 || digit >= radix {
                return false
            }
            unsignedDigit := (ulong)digit
            unsignedRadix := (ulong)radix
            if magnitude > (18446744073709551615UL - unsignedDigit) / unsignedRadix {
                magnitude = 0UL
                return false
            }
            magnitude = magnitude * unsignedRadix + unsignedDigit
            digitCount = digitCount + 1
            index = index + 1
        }
        return digitCount > 0
    }

    static func IntegerDigitValue(ch: char): int {
        if ch >= '0' && ch <= '9' {
            return ch - '0'
        }
        if ch >= 'a' && ch <= 'f' {
            return 10 + ch - 'a'
        }
        if ch >= 'A' && ch <= 'F' {
            return 10 + ch - 'A'
        }
        return -1
    }
}

class NumericLiteralIntegerSuffix {
    hasUnsignedValue: bool
    hasLongValue: bool
    HasUnsigned: bool => hasUnsignedValue
    HasLong: bool => hasLongValue

    constructor(hasUnsigned: bool, hasLong: bool) {
        hasUnsignedValue = hasUnsigned
        hasLongValue = hasLong
    }
}

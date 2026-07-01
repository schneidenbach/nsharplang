namespace NSharpLang.Compiler

import System
import System.Globalization

public class NumericLiteralFacts {
    public static func GetFloatLiteralTypeInfo(text: string): TypeInfo {
        trimmed := text.Trim()
        if trimmed.EndsWith("m", StringComparison.OrdinalIgnoreCase) {
            return BuiltInTypes.Decimal
        }

        if trimmed.EndsWith("f", StringComparison.OrdinalIgnoreCase) {
            return BuiltInTypes.Float
        }

        return BuiltInTypes.Double
    }

    public static func TryGetIntegerLiteralTypeInfo(clrType: Type, out typeInfo: SimpleTypeInfo): bool {
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

    public static func TryGetNegativeIntegerLiteralMaxMagnitude(typeName: string, out maxMagnitude: ulong): bool {
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

    public static func TryGetUnsignedIntegerLiteralMaxValue(typeName: string, out maxValue: ulong): bool {
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

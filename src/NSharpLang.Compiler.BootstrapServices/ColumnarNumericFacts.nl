namespace NSharpLang.Compiler.Columnar

import System

public class ColumnarNumericFacts {
    public static func IsIntPromotable(t: Type): bool {
        return t == typeof(int) || t == typeof(char)
            || t == typeof(byte) || t == typeof(sbyte) || t == typeof(short) || t == typeof(ushort)
    }

    public static func IsCastableScalar(t: Type): bool {
        return t == typeof(int) || t == typeof(long) || t == typeof(char)
            || t == typeof(double) || t == typeof(float)
            || t == typeof(byte) || t == typeof(sbyte) || t == typeof(short)
            || t == typeof(ushort) || t == typeof(uint) || t == typeof(ulong)
            || t == typeof(decimal)
    }
}

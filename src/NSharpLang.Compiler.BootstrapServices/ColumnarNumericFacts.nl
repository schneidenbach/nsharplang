namespace NSharpLang.Compiler.Columnar

import System

public class ColumnarNumericFacts {
    public static func IsIntPromotable(t: Type): bool {
        return t == typeof(int) || t == typeof(char)
            || t == typeof(byte) || t == typeof(sbyte) || t == typeof(short) || t == typeof(ushort)
    }
}

namespace NSharpLang.Compiler.Columnar

import System

public class ColumnarPatternFacts {
    public static func IsLiteralPatternKind(kind: int): bool {
        return kind >= 0 && kind <= 4
    }

    public static func IsOrderedMatchType(t: Type): bool {
        return t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(char)
            || t == typeof(double) || t == typeof(float)
    }
}

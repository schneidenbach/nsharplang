namespace NSharpLang.Compiler.Columnar

import System

class ColumnarPatternFacts {
    static func IsLiteralPatternKind(kind: int): bool {
        return kind >= 0 && kind <= 4
    }

    static func IsOrderedMatchType(t: Type): bool {
        return t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(char) || t == typeof(double) || t == typeof(float)
    }
}

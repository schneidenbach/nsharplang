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

    // Whether a type is an enum the bitwise family (and/or/xor) may run over.
    //
    // The CLR carries an enum on the evaluation stack as its UNDERLYING integral type, so a bitwise
    // operator over one enum is that underlying type's own opcode with no conversion. What makes an
    // enum different from another row in the promotable table is the RESULT TYPE: the operation
    // keeps the ENUM (`Public | Instance` is a `BindingFlags`, not an `int`), while an
    // int-promotable pair promotes to `int`.
    //
    // The admitted underlying set is EXACTLY the set the family already runs over plain operands, so
    // an enum never reaches an opcode a value of its underlying type could not. A string-backed
    // source enum is not a CLR enum and is refused; so is a builder-backed type that cannot answer
    // either question, which leaves it exactly where it was before this rule existed.
    //
    // This is stated ONCE because both the planner that selects the opcode and the executor that
    // validates the resulting stack shape must agree on it.
    public static func IsBitwiseEnum(t: Type): bool {
        if t == null {
            return false
        }

        isEnum := false
        try {
            isEnum = t.get_IsEnum()
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }

        if !isEnum {
            return false
        }

        underlying: Type? = null
        try {
            underlying = t.GetEnumUnderlyingType()
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }

        if underlying == null {
            return false
        }

        return IsIntPromotable(underlying)
            || underlying == typeof(long) || underlying == typeof(ulong)
            || underlying == typeof(uint)
    }
}

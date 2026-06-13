namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// COLUMNAR PIPELINE — stage 3 support. The numeric/type rules shared by the columnar type inferer
/// (<see cref="ColumnarTypeInferer"/>) and the parity oracle, so binary-numeric-promotion and the
/// classification of inferred types are IDENTICAL by construction (the parity test only has to verify the
/// traversal + lookups, not re-derive promotion). Types are canonical strings (matching
/// <see cref="ColumnarFunctionSymbol.CanonicalType"/>): primitive names verbatim ("int","long","double",
/// "float","decimal","char","bool","string", plus "void","null"), arrays "elem[]", generics "Name&lt;...&gt;".
/// Anything not pure-N#-inferable (BCL member/return types, function-as-value, unresolved) is
/// <see cref="External"/> — resolved by a later stage via the typed host boundary.
///
/// Numeric promotion follows the C# binder (Analyzer.cs GetWiderType / ECMA-334 §12.4.7) for the surface the
/// dogfood corpus uses: char/short/byte/sbyte/ushort promote to int; then double &gt; float &gt; ulong/long
/// &gt; uint &gt; int. decimal-with-float/double and ulong-with-signed are invalid mixes (→ External; the C#
/// binder errors, which the corpus never triggers). Unary and bitwise promotion follows Analyzer.cs as well:
/// unary - promotes small integrals to int and uint to long; unary ~ and shifts promote the operand side only.
/// </summary>
public static class ColumnarTypeLattice
{
    public const string External = "External";

    public static bool IsNumeric(string t) => t switch
    {
        "int" or "long" or "float" or "double" or "decimal"
            or "byte" or "sbyte" or "short" or "ushort" or "uint" or "ulong" or "char" => true,
        _ => false,
    };

    public static bool IsIntegral(string t) => t switch
    {
        "int" or "long" or "byte" or "sbyte" or "short" or "ushort" or "uint" or "ulong" or "char" => true,
        _ => false,
    };

    // Promotes the small integral types to int (C# unary/binary numeric promotion); non-numerics unchanged.
    public static string Promote(string t) => t switch
    {
        "char" or "byte" or "sbyte" or "short" or "ushort" => "int",
        _ => t,
    };

    /// <summary>Binary numeric promotion result, or External if either operand is non-numeric / an invalid mix.</summary>
    public static string Wider(string a, string b)
    {
        if (!IsNumeric(a) || !IsNumeric(b))
            return External;

        var x = Promote(a);
        var y = Promote(b);
        if (x == y)
            return x;

        // Invalid mixes the C# binder rejects.
        if ((x == "decimal" && (y == "float" || y == "double")) ||
            (y == "decimal" && (x == "float" || x == "double")))
            return External;
        if ((x == "ulong" && IsSigned(y)) || (y == "ulong" && IsSigned(x)))
            return External;

        if (x == "double" || y == "double") return "double";
        if (x == "float" || y == "float") return "float";
        if (x == "decimal" || y == "decimal") return "decimal";
        if (x == "ulong" || y == "ulong") return "ulong";
        if (x == "long" || y == "long") return "long";
        if (x == "uint" || y == "uint") return Either(x, y, "uint", "int") ? "long" : "uint";
        return "int";
    }

    /// <summary>Type of an integer literal from its verbatim text (suffix-sensitive); default int.</summary>
    public static string LiteralIntType(string text)
    {
        var hasU = text.IndexOf('u') >= 0 || text.IndexOf('U') >= 0;
        var hasL = text.IndexOf('l') >= 0 || text.IndexOf('L') >= 0;
        if (hasU && hasL) return "ulong";
        if (hasL) return "long";
        if (hasU) return "uint";
        return "int";
    }

    /// <summary>Type of a real literal from its verbatim text; default double, f→float, m→decimal.</summary>
    public static string LiteralFloatType(string text)
    {
        if (text.IndexOf('f') >= 0 || text.IndexOf('F') >= 0) return "float";
        if (text.IndexOf('m') >= 0 || text.IndexOf('M') >= 0) return "decimal";
        return "double";
    }

    public static string UnaryNegation(string operandType) => operandType switch
    {
        "byte" or "sbyte" or "short" or "ushort" or "char" => "int",
        "uint" => "long",
        "int" or "long" or "float" or "double" or "decimal" => operandType,
        _ => External,
    };

    public static string UnaryBitwiseNot(string operandType)
    {
        var promoted = Promote(operandType);
        return IsIntegral(promoted) ? promoted : External;
    }

    public static string Bitwise(string left, string right)
    {
        if (left == "bool" && right == "bool")
            return "bool";
        return IsIntegral(left) && IsIntegral(right) ? Wider(left, right) : External;
    }

    public static string Shift(string left, string right)
        => IsIntegral(left) && IsIntegral(right) ? Promote(left) : External;

    // Matches the C# binder's unary behavior (Analyzer.cs AnalyzeUnaryExpression): unary - applies unary
    // numeric promotion (small integrals → int, uint → long), logical NOT → bool, pre-inc/dec → operand type,
    // bitwise-NOT (~) applies unary integral promotion, and index-from-end (^) remains a host type.
    public static string Unary(string op, string operandType) => op switch
    {
        "!" => "bool",
        "-" => UnaryNegation(operandType),
        "~" => UnaryBitwiseNot(operandType),
        "++" or "--" => operandType,
        _ => External, // ^ (System.Index host type)
    };

    // Matches the C# binder's binary behavior. Arithmetic (+,-,*,/,%) applies numeric promotion via
    // AnalyzeArithmeticOp/GetWiderType; comparison/logical → bool; string '+' → string; '??' → the fallback's
    // type; bitwise ops apply bool/integral rules; shifts promote only the left operand.
    public static string Binary(string op, string left, string right) => op switch
    {
        "==" or "!=" or "<" or ">" or "<=" or ">=" or "&&" or "||" => "bool",
        "+" => left == "string" || right == "string" ? "string" : Wider(left, right),
        "-" or "*" or "/" or "%" => Wider(left, right),
        "&" or "|" or "^" => Bitwise(left, right),
        "<<" or ">>" => Shift(left, right),
        "??" => right,
        _ => External,
    };

    /// <summary>Element type of an indexable: <c>elem[]</c> → elem, string → char, else External.</summary>
    public static string ElementType(string objectType)
    {
        if (objectType.EndsWith("[]", System.StringComparison.Ordinal))
            return objectType.Substring(0, objectType.Length - 2);
        if (objectType == "string")
            return "char";
        return External;
    }

    private static bool IsSigned(string t) => t switch
    {
        "sbyte" or "short" or "int" or "long" => true,
        _ => false,
    };

    private static bool Either(string x, string y, string a, string b)
        => (x == a && y == b) || (x == b && y == a);
}

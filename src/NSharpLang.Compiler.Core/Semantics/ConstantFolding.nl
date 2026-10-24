namespace NSharpLang.Compiler

import System
import System.Globalization


// ONE CONSTANT EXPRESSION, AS THE TREE THE FOLDER READS. A parameter default is the one place N#
// needs the VALUE of an expression at compile time — it is written into metadata and copied into
// every call that omits the argument — and two owners see it in two different shapes: the analyzer
// has the parsed AST, and the back end has the columnar node table it re-parsed from source. Each
// builds this small tree from its own shape, and `ConstantFolder` decides what it is worth, so the
// diagnostic the analyzer reports and the value the back end writes cannot disagree.
//
// A literal carries its SOURCE SPELLING and its token kind (`Token.nl`'s ordinals: 1 integer,
// 2 floating, 3 character, 4 string, 44 `true`, 45 `false`); an operator carries its operator text
// (`+`, `<<`, `~`, …); an enum member carries the enum's identity and the member's value, which the
// builder resolved in its own scope.
class ConstantTerm {
    static LiteralShape: int => 1
    static EnumMemberShape: int => 2
    static UnaryShape: int => 3
    static BinaryShape: int => 4

    Shape: int
    LiteralKind: int
    Text: string
    EnumValue: int
    Left: ConstantTerm?
    Right: ConstantTerm?

    constructor(shape: int, literalKind: int, text: string, enumValue: int, left: ConstantTerm?, right: ConstantTerm?) {
        Shape = shape
        LiteralKind = literalKind
        Text = text
        EnumValue = enumValue
        Left = left
        Right = right
    }

    static func Literal(kind: int, spelling: string): ConstantTerm {
        return new ConstantTerm(ConstantTerm.LiteralShape, kind, spelling, 0, null, null)
    }

    static func EnumMember(enumIdentity: string, value: int): ConstantTerm {
        return new ConstantTerm(ConstantTerm.EnumMemberShape, 0, enumIdentity, value, null, null)
    }

    static func Unary(operatorText: string, operand: ConstantTerm): ConstantTerm {
        return new ConstantTerm(ConstantTerm.UnaryShape, 0, operatorText, 0, operand, null)
    }

    static func Binary(operatorText: string, left: ConstantTerm, right: ConstantTerm): ConstantTerm {
        return new ConstantTerm(ConstantTerm.BinaryShape, 0, operatorText, 0, left, right)
    }
}

// A FOLDED CONSTANT: its CLR type (`System.Int32`, …, `System.String`), its value boxed as exactly
// that runtime primitive, and — for an enum — the enum's identity, with the value held as the
// underlying integer. `IsAdoptableLiteral` marks an unsuffixed integer literal, negated or not: N#
// lets THAT adopt any integral (or `char`) target it fits, where any other `int` constant converts
// only as C#'s implicit constant conversion allows.
class ConstantValue {
    TypeName: string
    Value: object
    EnumIdentity: string?
    IsAdoptableLiteral: bool

    constructor(typeName: string, value: object, enumIdentity: string?, isAdoptableLiteral: bool) {
        TypeName = typeName
        Value = value
        EnumIdentity = enumIdentity
        IsAdoptableLiteral = isAdoptableLiteral
    }

    // The value as an exact decimal, for an integral or `char` constant.
    func IntegralValue(): decimal {
        if Value is char {
            return Convert.ToDecimal((int)Convert.ToChar(Value, CultureInfo.InvariantCulture))
        }
        return Convert.ToDecimal(Value, CultureInfo.InvariantCulture)
    }

    // The value as a double, for a floating comparison or a floating operation.
    func FloatingValue(): double {
        if Value is char {
            return Convert.ToDouble((int)Convert.ToChar(Value, CultureInfo.InvariantCulture))
        }
        return Convert.ToDouble(Value, CultureInfo.InvariantCulture)
    }
}

// What folding answered: the constant, or the sentence that says why there is none. The sentence
// completes "The default value for 'x' cannot be computed: …".
// `Hint` is the fix, when there is an obvious one.
class ConstantFoldResult {
    Value: ConstantValue?
    Problem: string
    Hint: string?

    constructor(value: ConstantValue?, problem: string, hint: string?) {
        Value = value
        Problem = problem
        Hint = hint
    }

    static func Of(value: ConstantValue): ConstantFoldResult {
        return new ConstantFoldResult(value, "", null)
    }

    static func Failed(problem: string): ConstantFoldResult {
        return new ConstantFoldResult(null, problem, null)
    }
}

// C#'S CONSTANT ARITHMETIC, ONCE. Literals take their natural types (an unsuffixed integer is the
// first of `int`, `uint`, `long`, `ulong` that holds it; `-2147483648` is an `int`); operands are
// promoted by the binary numeric promotion rules; integer arithmetic is CHECKED, so an overflow or a
// division by zero is a reported problem rather than a wrapped value, exactly as C# refuses
// `int.MaxValue + 1` in a constant; shifts mask their count; and an enum takes `|`, `&`, `^` and
// `~` against members of its own enum. Every other combination answers a problem naming the
// operator and the types it was given.
class ConstantFolder {
    static func Fold(term: ConstantTerm): ConstantFoldResult {
        if term.Shape == ConstantTerm.LiteralShape {
            return FoldLiteral(term.LiteralKind, term.Text, false)
        }

        if term.Shape == ConstantTerm.EnumMemberShape {
            return ConstantFoldResult.Of(new ConstantValue("System.Int32", term.EnumValue, term.Text, false))
        }

        left := term.Left
        if left == null {
            return ConstantFoldResult.Failed("the expression is incomplete")
        }

        if term.Shape == ConstantTerm.UnaryShape {
            // `-2147483648` and `-9223372036854775808` are the two literals that exist only negated.
            if term.Text == "-" && left.Shape == ConstantTerm.LiteralShape && left.LiteralKind == 1 {
                return FoldLiteral(1, left.Text, true)
            }

            operand := Fold(left)
            if operand.Value == null {
                return operand
            }
            return FoldUnary(term.Text, operand.Value)
        }

        right := term.Right
        if right == null {
            return ConstantFoldResult.Failed("the expression is incomplete")
        }

        leftValue := Fold(left)
        if leftValue.Value == null {
            return leftValue
        }
        rightValue := Fold(right)
        if rightValue.Value == null {
            return rightValue
        }
        return FoldBinary(term.Text, leftValue.Value, rightValue.Value)
    }

    // ------------------------------------------------------------------------------------------
    // LITERALS
    // ------------------------------------------------------------------------------------------

    static func FoldLiteral(kind: int, spelling: string, negated: bool): ConstantFoldResult {
        text := spelling.Trim()
        if kind == 44 || kind == 45 {
            if negated {
                return ConstantFoldResult.Failed("'-' cannot negate a 'bool'")
            }
            return ConstantFoldResult.Of(new ConstantValue("System.Boolean", kind == 44, null, false))
        }

        if kind == 4 || kind == 5 {
            decoded := kind == 5 ? text : StringLiteralDecoder.Decode(text, false)
            return ConstantFoldResult.Of(new ConstantValue("System.String", decoded, null, false))
        }

        if kind == 3 {
            if text.Length < 2 || text[0] != '\'' || text[text.Length - 1] != '\'' {
                return Unreadable(spelling)
            }
            code := StringLiteralDecoder.DecodeCharacterBody(text.Substring(1, text.Length - 2))
            if code < 0 {
                return Unreadable(spelling)
            }
            character := ConstantFoldResult.Of(new ConstantValue("System.Char", (char)code, null, false))
            if negated {
                return FoldUnary("-", must character.Value)
            }
            return character
        }

        if kind != 1 && kind != 2 {
            return Unreadable(spelling)
        }

        if text.Length == 0 {
            return Unreadable(spelling)
        }

        last := text[text.Length - 1]
        isRadixInteger := text.Length > 1 && text[0] == '0' && (text[1] == 'x' || text[1] == 'X' || text[1] == 'b' || text[1] == 'B')
        if last == 'm' || last == 'M' {
            value := 0m
            if !Decimal.TryParse(text.Substring(0, text.Length - 1).Replace("_", ""), NumberStyles.Float, CultureInfo.InvariantCulture, out value) {
                return Unreadable(spelling)
            }
            return ConstantFoldResult.Of(new ConstantValue("System.Decimal", negated ? -value : value, null, false))
        }

        if !isRadixInteger && (last == 'f' || last == 'F') {
            value := 0.0f
            if !Single.TryParse(text.Substring(0, text.Length - 1).Replace("_", ""), NumberStyles.Float, CultureInfo.InvariantCulture, out value) {
                return Unreadable(spelling)
            }
            return ConstantFoldResult.Of(new ConstantValue("System.Single", negated ? -value : value, null, false))
        }

        if kind == 2 || (!isRadixInteger && (last == 'd' || last == 'D')) {
            body := text
            if last == 'd' || last == 'D' {
                body = text.Substring(0, text.Length - 1)
            }
            value := 0.0
            if !Double.TryParse(body.Replace("_", ""), NumberStyles.Float, CultureInfo.InvariantCulture, out value) {
                return Unreadable(spelling)
            }
            return ConstantFoldResult.Of(new ConstantValue("System.Double", negated ? -value : value, null, false))
        }

        literalKind := 0
        magnitude := 0UL
        if !NumericLiteralFacts.TryParseIntegerLiteral(text, out literalKind, out magnitude) {
            return Unreadable(spelling)
        }

        // 0 unsuffixed, 1 `L`, 2 `UL`, 3 `U` — `NumericLiteralFacts.TryParseIntegerLiteral`'s kinds.
        exact := (decimal)magnitude
        if negated {
            exact = -exact
        }

        if literalKind == 0 {
            if negated {
                if exact >= -2147483648m {
                    return ConstantFoldResult.Of(new ConstantValue("System.Int32", Convert.ToInt32(exact), null, true))
                }
                if exact >= -9223372036854775808m {
                    return ConstantFoldResult.Of(new ConstantValue("System.Int64", Convert.ToInt64(exact), null, true))
                }
                return Overflowed("negating it", "long")
            }
            name := "System.UInt64"
            if exact <= 2147483647m {
                name = "System.Int32"
            } else if exact <= 4294967295m {
                name = "System.UInt32"
            } else if exact <= 9223372036854775807m {
                name = "System.Int64"
            }
            return ConstantFoldResult.Of(new ConstantValue(name, must BoxIntegral(name, exact), null, true))
        }

        if literalKind == 1 {
            if negated && exact >= -9223372036854775808m {
                return ConstantFoldResult.Of(new ConstantValue("System.Int64", Convert.ToInt64(exact), null, false))
            }
            if negated {
                return Overflowed("negating it", "long")
            }
            name := exact <= 9223372036854775807m ? "System.Int64" : "System.UInt64"
            return ConstantFoldResult.Of(new ConstantValue(name, must BoxIntegral(name, exact), null, false))
        }

        unsignedName := literalKind == 2 ? "System.UInt64" : "System.UInt32"
        unsigned := new ConstantValue(unsignedName, must BoxIntegral(unsignedName, (decimal)magnitude), null, false)
        if negated {
            return FoldUnary("-", unsigned)
        }
        return ConstantFoldResult.Of(unsigned)
    }

    // ------------------------------------------------------------------------------------------
    // UNARY OPERATORS
    // ------------------------------------------------------------------------------------------

    static func FoldUnary(operatorText: string, operand: ConstantValue): ConstantFoldResult {
        if operand.EnumIdentity != null {
            if operatorText != "~" {
                return Unsupported(operatorText, operand, null)
            }
            return ConstantFoldResult.Of(new ConstantValue(operand.TypeName, ~Convert.ToInt32(operand.Value, CultureInfo.InvariantCulture), operand.EnumIdentity, false))
        }

        if operatorText == "!" {
            if operand.TypeName != "System.Boolean" {
                return Unsupported(operatorText, operand, null)
            }
            return ConstantFoldResult.Of(new ConstantValue("System.Boolean", !Convert.ToBoolean(operand.Value, CultureInfo.InvariantCulture), null, false))
        }

        name := PromotedUnaryName(operand.TypeName)
        if operatorText == "+" {
            if name == "" {
                return Unsupported(operatorText, operand, null)
            }
            return Converted(operand, name)
        }

        if operatorText == "~" {
            if !IsIntegralName(name) {
                return Unsupported(operatorText, operand, null)
            }
            value := operand.IntegralValue()
            if name == "System.Int32" {
                return ConstantFoldResult.Of(new ConstantValue(name, ~Convert.ToInt32(value), null, false))
            }
            if name == "System.UInt32" {
                return ConstantFoldResult.Of(new ConstantValue(name, Convert.ToUInt32(value) ^ 4294967295u, null, false))
            }
            if name == "System.Int64" {
                return ConstantFoldResult.Of(new ConstantValue(name, ~Convert.ToInt64(value), null, false))
            }
            return ConstantFoldResult.Of(new ConstantValue(name, Convert.ToUInt64(value) ^ 18446744073709551615UL, null, false))
        }

        if operatorText != "-" || name == "" {
            return Unsupported(operatorText, operand, null)
        }

        if name == "System.Double" {
            return ConstantFoldResult.Of(new ConstantValue(name, -Convert.ToDouble(operand.Value, CultureInfo.InvariantCulture), null, false))
        }
        if name == "System.Single" {
            return ConstantFoldResult.Of(new ConstantValue(name, -Convert.ToSingle(operand.Value, CultureInfo.InvariantCulture), null, false))
        }
        if name == "System.Decimal" {
            return ConstantFoldResult.Of(new ConstantValue(name, -Convert.ToDecimal(operand.Value, CultureInfo.InvariantCulture), null, false))
        }

        // `-` on a `uint` is a `long` (C#'s unary minus has no `uint` form); on a `ulong` it has
        // no form at all.
        if name == "System.UInt64" {
            return Unsupported(operatorText, operand, null)
        }
        resultName := name == "System.UInt32" ? "System.Int64" : name
        return Checked(-operand.IntegralValue(), resultName, "negating it")
    }

    static func PromotedUnaryName(typeName: string): string {
        if typeName == "System.Char" || typeName == "System.SByte" || typeName == "System.Byte" || typeName == "System.Int16" || typeName == "System.UInt16" || typeName == "System.Int32" {
            return "System.Int32"
        }
        if typeName == "System.UInt32" || typeName == "System.Int64" || typeName == "System.UInt64" || typeName == "System.Single" || typeName == "System.Double" || typeName == "System.Decimal" {
            return typeName
        }
        return ""
    }

    // ------------------------------------------------------------------------------------------
    // BINARY OPERATORS
    // ------------------------------------------------------------------------------------------

    static func FoldBinary(operatorText: string, left: ConstantValue, right: ConstantValue): ConstantFoldResult {
        if left.EnumIdentity != null || right.EnumIdentity != null {
            return FoldEnumBinary(operatorText, left, right)
        }

        if left.TypeName == "System.Boolean" || right.TypeName == "System.Boolean" {
            return FoldBoolBinary(operatorText, left, right)
        }

        if left.TypeName == "System.String" || right.TypeName == "System.String" {
            if operatorText == "+" && left.TypeName == "System.String" && right.TypeName == "System.String" {
                return ConstantFoldResult.Of(new ConstantValue("System.String", (Convert.ToString(left.Value, CultureInfo.InvariantCulture) ?? "") + (Convert.ToString(right.Value, CultureInfo.InvariantCulture) ?? ""), null, false))
            }
            return Unsupported(operatorText, left, right)
        }

        if operatorText == "<<" || operatorText == ">>" {
            return FoldShift(operatorText, left, right)
        }

        name := PromotedBinaryName(left, right)
        if name == "" {
            return Unsupported(operatorText, left, right)
        }

        if operatorText == "==" || operatorText == "!=" || operatorText == "<" || operatorText == "<=" || operatorText == ">" || operatorText == ">=" {
            return FoldComparison(operatorText, left, right, name)
        }

        if name == "System.Double" || name == "System.Single" {
            return FoldFloating(operatorText, left, right, name)
        }
        if name == "System.Decimal" {
            return FoldDecimal(operatorText, left, right)
        }
        return FoldIntegral(operatorText, left, right, name)
    }

    // C#'s binary numeric promotion. A `ulong` beside a signed operand, or a `uint` beside a
    // negative one, is where the rules part: a NON-negative signed constant converts to the
    // unsigned type (C#'s implicit constant conversion makes the unsigned operator applicable), and
    // a negative one leaves `ulong` with no operator and widens `uint` to `long`.
    static func PromotedBinaryName(left: ConstantValue, right: ConstantValue): string {
        leftName := PromotedUnaryName(left.TypeName)
        rightName := PromotedUnaryName(right.TypeName)
        if leftName == "" || rightName == "" {
            return ""
        }
        if leftName == "System.Decimal" || rightName == "System.Decimal" {
            if IsFloatingName(leftName) || IsFloatingName(rightName) {
                return ""
            }
            return "System.Decimal"
        }
        if leftName == "System.Double" || rightName == "System.Double" {
            return "System.Double"
        }
        if leftName == "System.Single" || rightName == "System.Single" {
            return "System.Single"
        }
        if leftName == "System.UInt64" || rightName == "System.UInt64" {
            other := leftName == "System.UInt64" ? right : left
            otherName := leftName == "System.UInt64" ? rightName : leftName
            if IsSignedIntegralName(otherName) && other.IntegralValue() < 0m {
                return ""
            }
            return "System.UInt64"
        }
        if leftName == "System.Int64" || rightName == "System.Int64" {
            return "System.Int64"
        }
        if leftName == "System.UInt32" || rightName == "System.UInt32" {
            other := leftName == "System.UInt32" ? right : left
            otherName := leftName == "System.UInt32" ? rightName : leftName
            if otherName == "System.Int32" && other.IntegralValue() < 0m {
                return "System.Int64"
            }
            return "System.UInt32"
        }
        return "System.Int32"
    }

    static func FoldIntegral(operatorText: string, left: ConstantValue, right: ConstantValue, name: string): ConstantFoldResult {
        a := left.IntegralValue()
        b := right.IntegralValue()
        if operatorText == "+" {
            return Checked(a + b, name, "adding them")
        }
        if operatorText == "-" {
            return Checked(a - b, name, "subtracting them")
        }
        if operatorText == "*" {
            product := 0m
            try {
                product = a * b
            } catch ex: OverflowException {
                return Overflowed("multiplying them", ShortName(name))
            }
            return Checked(product, name, "multiplying them")
        }
        if operatorText == "/" || operatorText == "%" {
            if b == 0m {
                return ConstantFoldResult.Failed("it divides by zero")
            }
            // Integer division truncates toward zero; the operands are exact, and the quotient of
            // two values that fit in 64 bits is computed in 64 bits rather than rounded.
            if IsSignedIntegralName(name) {
                dividend := Convert.ToInt64(a)
                divisor := Convert.ToInt64(b)
                if operatorText == "%" {
                    if divisor == -1L {
                        return Checked(0m, name, "taking the remainder")
                    }
                    return Checked((decimal)(dividend % divisor), name, "taking the remainder")
                }
                if divisor == -1L {
                    return Checked(-a, name, "dividing them")
                }
                return Checked((decimal)(dividend / divisor), name, "dividing them")
            }
            unsignedDividend := Convert.ToUInt64(a)
            unsignedDivisor := Convert.ToUInt64(b)
            if operatorText == "%" {
                return Checked((decimal)(unsignedDividend % unsignedDivisor), name, "taking the remainder")
            }
            return Checked((decimal)(unsignedDividend / unsignedDivisor), name, "dividing them")
        }
        if operatorText == "&" || operatorText == "|" || operatorText == "^" {
            return ConstantFoldResult.Of(new ConstantValue(name, BitwiseOf(operatorText, a, b, name), null, false))
        }
        return Unsupported(operatorText, left, right)
    }

    static func BitwiseOf(operatorText: string, a: decimal, b: decimal, name: string): object {
        if name == "System.Int32" {
            x := Convert.ToInt32(a)
            y := Convert.ToInt32(b)
            return operatorText == "&" ? x & y : (operatorText == "|" ? x | y : x ^ y)
        }
        if name == "System.UInt32" {
            x := Convert.ToUInt32(a)
            y := Convert.ToUInt32(b)
            return operatorText == "&" ? x & y : (operatorText == "|" ? x | y : x ^ y)
        }
        if name == "System.Int64" {
            x := Convert.ToInt64(a)
            y := Convert.ToInt64(b)
            return operatorText == "&" ? x & y : (operatorText == "|" ? x | y : x ^ y)
        }
        ux := Convert.ToUInt64(a)
        uy := Convert.ToUInt64(b)
        return operatorText == "&" ? ux & uy : (operatorText == "|" ? ux | uy : ux ^ uy)
    }

    // THE LEFT OPERAND alone decides the type; the count is an `int` and is masked to the width,
    // as at run time.
    static func FoldShift(operatorText: string, left: ConstantValue, right: ConstantValue): ConstantFoldResult {
        name := PromotedUnaryName(left.TypeName)
        countName := PromotedUnaryName(right.TypeName)
        if !IsIntegralName(name) || countName != "System.Int32" {
            return Unsupported(operatorText, left, right)
        }
        count := Convert.ToInt32(right.IntegralValue())
        value := left.IntegralValue()
        if name == "System.Int32" {
            x := Convert.ToInt32(value)
            return ConstantFoldResult.Of(new ConstantValue(name, operatorText == "<<" ? x << (count & 31) : x >> (count & 31), null, false))
        }
        if name == "System.UInt32" {
            x := Convert.ToUInt32(value)
            return ConstantFoldResult.Of(new ConstantValue(name, operatorText == "<<" ? x << (count & 31) : x >> (count & 31), null, false))
        }
        if name == "System.Int64" {
            x := Convert.ToInt64(value)
            return ConstantFoldResult.Of(new ConstantValue(name, operatorText == "<<" ? x << (count & 63) : x >> (count & 63), null, false))
        }
        ux := Convert.ToUInt64(value)
        return ConstantFoldResult.Of(new ConstantValue(name, operatorText == "<<" ? ux << (count & 63) : ux >> (count & 63), null, false))
    }

    static func FoldFloating(operatorText: string, left: ConstantValue, right: ConstantValue, name: string): ConstantFoldResult {
        a := left.FloatingValue()
        b := right.FloatingValue()
        result := 0.0
        if operatorText == "+" {
            result = a + b
        } else if operatorText == "-" {
            result = a - b
        } else if operatorText == "*" {
            result = a * b
        } else if operatorText == "/" {
            result = a / b
        } else if operatorText == "%" {
            result = a % b
        } else {
            return Unsupported(operatorText, left, right)
        }

        if name == "System.Single" {
            return ConstantFoldResult.Of(new ConstantValue(name, (float)result, null, false))
        }
        return ConstantFoldResult.Of(new ConstantValue(name, result, null, false))
    }

    static func FoldDecimal(operatorText: string, left: ConstantValue, right: ConstantValue): ConstantFoldResult {
        a := left.TypeName == "System.Decimal" ? Convert.ToDecimal(left.Value, CultureInfo.InvariantCulture) : left.IntegralValue()
        b := right.TypeName == "System.Decimal" ? Convert.ToDecimal(right.Value, CultureInfo.InvariantCulture) : right.IntegralValue()
        if (operatorText == "/" || operatorText == "%") && b == 0m {
            return ConstantFoldResult.Failed("it divides by zero")
        }

        result := 0m
        try {
            if operatorText == "+" {
                result = a + b
            } else if operatorText == "-" {
                result = a - b
            } else if operatorText == "*" {
                result = a * b
            } else if operatorText == "/" {
                result = a / b
            } else if operatorText == "%" {
                result = a % b
            } else {
                return Unsupported(operatorText, left, right)
            }
        } catch ex: OverflowException {
            return Overflowed(VerbFor(operatorText), "decimal")
        }
        return ConstantFoldResult.Of(new ConstantValue("System.Decimal", result, null, false))
    }

    static func FoldComparison(operatorText: string, left: ConstantValue, right: ConstantValue, name: string): ConstantFoldResult {
        comparison := 0
        if IsFloatingName(name) {
            a := left.FloatingValue()
            b := right.FloatingValue()
            comparison = a.CompareTo(b)
        } else {
            a := left.TypeName == "System.Decimal" ? Convert.ToDecimal(left.Value, CultureInfo.InvariantCulture) : left.IntegralValue()
            b := right.TypeName == "System.Decimal" ? Convert.ToDecimal(right.Value, CultureInfo.InvariantCulture) : right.IntegralValue()
            comparison = a.CompareTo(b)
        }

        result := false
        if operatorText == "==" {
            result = comparison == 0
        } else if operatorText == "!=" {
            result = comparison != 0
        } else if operatorText == "<" {
            result = comparison < 0
        } else if operatorText == "<=" {
            result = comparison <= 0
        } else if operatorText == ">" {
            result = comparison > 0
        } else {
            result = comparison >= 0
        }
        return ConstantFoldResult.Of(new ConstantValue("System.Boolean", result, null, false))
    }

    static func FoldBoolBinary(operatorText: string, left: ConstantValue, right: ConstantValue): ConstantFoldResult {
        if left.TypeName != "System.Boolean" || right.TypeName != "System.Boolean" {
            return Unsupported(operatorText, left, right)
        }
        a := Convert.ToBoolean(left.Value, CultureInfo.InvariantCulture)
        b := Convert.ToBoolean(right.Value, CultureInfo.InvariantCulture)
        result := false
        if operatorText == "&&" || operatorText == "&" {
            result = a && b
        } else if operatorText == "||" || operatorText == "|" {
            result = a || b
        } else if operatorText == "^" || operatorText == "!=" {
            result = a != b
        } else if operatorText == "==" {
            result = a == b
        } else {
            return Unsupported(operatorText, left, right)
        }
        return ConstantFoldResult.Of(new ConstantValue("System.Boolean", result, null, false))
    }

    // AN ENUM COMBINES ONLY WITH ITS OWN MEMBERS, and only bitwise: `A | B`, `A & B`, `A ^ B`. The
    // flags idiom is the reason these exist; enum arithmetic is not a constant N# writes.
    static func FoldEnumBinary(operatorText: string, left: ConstantValue, right: ConstantValue): ConstantFoldResult {
        if left.EnumIdentity == null || right.EnumIdentity == null || left.EnumIdentity != right.EnumIdentity || (operatorText != "|" && operatorText != "&" && operatorText != "^") {
            return Unsupported(operatorText, left, right)
        }
        a := Convert.ToInt32(left.Value, CultureInfo.InvariantCulture)
        b := Convert.ToInt32(right.Value, CultureInfo.InvariantCulture)
        combined := operatorText == "|" ? a | b : (operatorText == "&" ? a & b : a ^ b)
        return ConstantFoldResult.Of(new ConstantValue(left.TypeName, combined, left.EnumIdentity, false))
    }

    // ------------------------------------------------------------------------------------------
    // SHARED
    // ------------------------------------------------------------------------------------------

    // An integral result, refused when it does not fit the type the operation produces.
    static func Checked(value: decimal, name: string, verb: string): ConstantFoldResult {
        boxed := BoxIntegral(name, value)
        if boxed == null {
            return Overflowed(verb, ShortName(name))
        }
        return ConstantFoldResult.Of(new ConstantValue(name, boxed, null, false))
    }

    static func Converted(operand: ConstantValue, name: string): ConstantFoldResult {
        if name == operand.TypeName {
            return ConstantFoldResult.Of(new ConstantValue(name, operand.Value, null, false))
        }
        return Checked(operand.IntegralValue(), name, "converting it")
    }

    // The value boxed as exactly the named integral type, or null when it does not fit.
    static func BoxIntegral(name: string, value: decimal): object? {
        if value != Decimal.Truncate(value) {
            return null
        }
        if name == "System.Int32" && value >= -2147483648m && value <= 2147483647m {
            return Convert.ToInt32(value)
        }
        if name == "System.UInt32" && value >= 0m && value <= 4294967295m {
            return Convert.ToUInt32(value)
        }
        if name == "System.Int64" && value >= -9223372036854775808m && value <= 9223372036854775807m {
            return Convert.ToInt64(value)
        }
        if name == "System.UInt64" && value >= 0m && value <= 18446744073709551615m {
            return Convert.ToUInt64(value)
        }
        if name == "System.Int16" && value >= -32768m && value <= 32767m {
            return Convert.ToInt16(value)
        }
        if name == "System.UInt16" && value >= 0m && value <= 65535m {
            return Convert.ToUInt16(value)
        }
        if name == "System.SByte" && value >= -128m && value <= 127m {
            return Convert.ToSByte(value)
        }
        if name == "System.Byte" && value >= 0m && value <= 255m {
            return Convert.ToByte(value)
        }
        if name == "System.Char" && value >= 0m && value <= 65535m {
            return (char)Convert.ToInt32(value)
        }
        return null
    }

    static func IsIntegralName(name: string): bool {
        return name == "System.SByte" || name == "System.Byte" || name == "System.Int16" || name == "System.UInt16" || name == "System.Int32" || name == "System.UInt32" || name == "System.Int64" || name == "System.UInt64"
    }

    static func IsSignedIntegralName(name: string): bool {
        return name == "System.SByte" || name == "System.Int16" || name == "System.Int32" || name == "System.Int64"
    }

    static func IsFloatingName(name: string): bool {
        return name == "System.Single" || name == "System.Double"
    }

    // The N# spelling of a constant's type, for the sentences below.
    static func ShortName(name: string): string {
        if name == "System.Boolean" {
            return "bool"
        }
        if name == "System.Char" {
            return "char"
        }
        if name == "System.String" {
            return "string"
        }
        if name == "System.SByte" {
            return "sbyte"
        }
        if name == "System.Byte" {
            return "byte"
        }
        if name == "System.Int16" {
            return "short"
        }
        if name == "System.UInt16" {
            return "ushort"
        }
        if name == "System.Int32" {
            return "int"
        }
        if name == "System.UInt32" {
            return "uint"
        }
        if name == "System.Int64" {
            return "long"
        }
        if name == "System.UInt64" {
            return "ulong"
        }
        if name == "System.Single" {
            return "float"
        }
        if name == "System.Double" {
            return "double"
        }
        if name == "System.Decimal" {
            return "decimal"
        }
        return name
    }

    static func DisplayName(value: ConstantValue): string {
        identity := value.EnumIdentity
        if identity != null {
            return identity
        }
        return ShortName(value.TypeName)
    }

    static func VerbFor(operatorText: string): string {
        if operatorText == "+" {
            return "adding them"
        }
        if operatorText == "-" {
            return "subtracting them"
        }
        if operatorText == "*" {
            return "multiplying them"
        }
        return "dividing them"
    }

    // An `int` or `uint` overflow is usually arithmetic the author meant to do in 64 bits: the
    // operands' type decides the arithmetic's, not the parameter's, exactly as in C#.
    static func Overflowed(verb: string, typeName: string): ConstantFoldResult {
        hint: string? = null
        if typeName == "int" || typeName == "uint" {
            hint = "The arithmetic is done in '" + typeName + "' because that is its operands' type, whatever the parameter's type is. Write an operand with an 'L' suffix (for example '2147483647L') to do it in 'long'."
        }
        return new ConstantFoldResult(null, verb + " overflows '" + typeName + "'", hint)
    }

    static func Unreadable(spelling: string): ConstantFoldResult {
        return ConstantFoldResult.Failed("'" + spelling + "' is not a literal the compiler can read")
    }

    static func Unsupported(operatorText: string, left: ConstantValue, right: ConstantValue?): ConstantFoldResult {
        if right == null {
            return ConstantFoldResult.Failed("'" + operatorText + "' cannot be applied to a constant '" + DisplayName(left) + "'")
        }
        return ConstantFoldResult.Failed("'" + operatorText + "' cannot be applied to constants of type '" + DisplayName(left) + "' and '" + DisplayName(right) + "'")
    }
}

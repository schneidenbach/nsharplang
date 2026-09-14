namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import NSharpLang.Compiler

// WHAT AN ATTRIBUTE ARGUMENT IS, BEFORE ANYTHING KNOWS WHICH PARAMETER IT FILLS.
//
// A custom-attribute blob cannot be written from source text: `1` is four bytes in an `int`
// parameter, one byte in a `byte` parameter, and eight in a `long` one, and `Colors.Red | Colors.Blue`
// is a single integer whose width is the enum's underlying type. The argument therefore has to be
// read into a SHAPE first and encoded second, against the parameter type the constructor declares.
//
// This is the shape. It is deliberately syntactic rather than evaluated: `-1` is a negation of a
// literal, not the number minus one, because the number the blob wants depends on a width nobody
// knows yet. The evaluator that closes that gap is `ColumnarAttributeBlobWriter`, and it is the only
// reader of these nodes.
enum ColumnarAttributeArgumentKind {
    IntLiteral,
    FloatLiteral,
    CharLiteral,
    StringLiteral,
    BoolLiteral,
    NullLiteral,
    TypeOf,
    MemberPath,
    ArrayLiteral,
    Negate,
    BitwiseNot,
    LogicalNot,
    BitwiseOr,
    BitwiseAnd,
    BitwiseXor
}

// ONE NODE. `Text` carries the only thing the kind needs — a literal's decoded value, a dotted
// member path, a `typeof` operand's written type — and `Children` the operands of the operators and
// the elements of an array literal. Nothing else is carried, because nothing else survives into a
// blob.
class ColumnarAttributeArgumentNode {
    Kind: ColumnarAttributeArgumentKind
    Text: string
    Children: List<ColumnarAttributeArgumentNode>

    constructor(kind: ColumnarAttributeArgumentKind, text: string) {
        Kind = kind
        Text = text
        Children = new List<ColumnarAttributeArgumentNode>()
    }

    static func Unary(kind: ColumnarAttributeArgumentKind, operand: ColumnarAttributeArgumentNode): ColumnarAttributeArgumentNode {
        node := new ColumnarAttributeArgumentNode(kind, "")
        node.Children.Add(operand)
        return node
    }

    static func Binary(kind: ColumnarAttributeArgumentKind, left: ColumnarAttributeArgumentNode, right: ColumnarAttributeArgumentNode): ColumnarAttributeArgumentNode {
        node := new ColumnarAttributeArgumentNode(kind, "")
        node.Children.Add(left)
        node.Children.Add(right)
        return node
    }
}

// ONE ARGUMENT AS WRITTEN: the name when the source spelled `Name = value`, and the value's shape.
class ColumnarAttributeArgumentSyntax {
    Name: string?
    Value: ColumnarAttributeArgumentNode

    constructor(name: string?, value: ColumnarAttributeArgumentNode) {
        Name = name
        Value = value
    }
}

// THE ARGUMENT GRAMMAR, READ FROM THE DECLARATION TOKEN TABLE.
//
// It is a recursive-descent reader over a token RANGE rather than a general expression parser,
// because the grammar an attribute argument may use is closed and small: the constant literals, a
// dotted member path, `typeof`, `nameof`, an array literal, three bitwise operators and three unary
// ones. Anything outside it answers false and the attribute declines to become a blob — the analyzer
// has already refused the same program with a sentence that names the offending expression, so a
// second refusal here would be noise.
//
// PRECEDENCE IS C#'s AND IS OBSERVABLE: `&` binds tighter than `^`, which binds tighter than `|`, so
// `A | B & C` combines `A` with `B & C` exactly as the same text does in a C# attribute.
class ColumnarAttributeArgumentReader {
    source: string
    tokens: ParserDeclarationTokenTable
    position: int
    limit: int

    constructor(source: string, tokens: ParserDeclarationTokenTable, start: int, end: int) {
        this.source = source
        this.tokens = tokens
        position = start
        limit = end
    }

    // ONE ARGUMENT FROM A TOKEN RANGE. The range must be consumed ENTIRELY — a trailing token means
    // the reader stopped early on a shape it does not model, and admitting the prefix would write a
    // blob that says something the source did not.
    static func TryRead(source: string, tokens: ParserDeclarationTokenTable, start: int, end: int, out argument: ColumnarAttributeArgumentSyntax): bool {
        argument = new ColumnarAttributeArgumentSyntax(null, new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, ""))
        if start >= end {
            return false
        }

        reader := new ColumnarAttributeArgumentReader(source, tokens, start, end)
        name: string? = null
        if reader.LooksLikeNamedArgument() {
            name = reader.TokenText(reader.position)
            reader.position = reader.position + 2
        }

        value: ColumnarAttributeArgumentNode = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, "")
        if !reader.TryParseOr(out value) || reader.position != end {
            return false
        }

        argument = new ColumnarAttributeArgumentSyntax(name, value)
        return true
    }

    // A NAMED ARGUMENT IS A BARE IDENTIFIER FOLLOWED BY `=` OR `:`, and `==` is never one. The
    // analyzer draws the same line; drawing it differently here would bind a named argument the
    // analyzer validated as positional, or the reverse.
    //
    // BOTH SPELLINGS, BECAUSE THE FRONT END ALREADY ACCEPTS BOTH. `Name: value` is N#'s own named-
    // argument syntax — it is what a call and an object initializer are written with — and the
    // analyzer validates it in an attribute exactly like `Name = value`: an unknown member reports
    // NL303 and a mismatched value reports NL202, under either spelling. This reader knew only `=`,
    // so `[JsonIgnore(Condition: JsonIgnoreCondition.WhenWritingNull)]` read `Condition` and its
    // value as ONE positional argument, failed to decode it, and the WHOLE ATTRIBUTE was then
    // dropped from the emitted metadata with no diagnostic anywhere — a silently missing
    // custom-attribute row, which is the one outcome the attribute rules promise never to produce
    // ("refused by NL310 rather than silently dropped").
    func LooksLikeNamedArgument(): bool {
        if position + 1 >= limit {
            return false
        }

        if tokens.Kinds[position] != (int)TokenType.Identifier {
            return false
        }

        next := tokens.Kinds[position + 1]
        return next == (int)TokenType.Assign || next == (int)TokenType.Colon
    }

    func TokenText(index: int): string {
        return source.Substring(tokens.Starts[index], tokens.ValueLengths[index])
    }

    func Peek(): int {
        if position >= limit {
            return -1
        }

        return tokens.Kinds[position]
    }

    func TryParseOr(out node: ColumnarAttributeArgumentNode): bool {
        node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, "")
        left: ColumnarAttributeArgumentNode = node
        if !TryParseXor(out left) {
            return false
        }

        while Peek() == (int)TokenType.BitwiseOr {
            position = position + 1
            right: ColumnarAttributeArgumentNode = node
            if !TryParseXor(out right) {
                return false
            }

            left = ColumnarAttributeArgumentNode.Binary(ColumnarAttributeArgumentKind.BitwiseOr, left, right)
        }

        node = left
        return true
    }

    func TryParseXor(out node: ColumnarAttributeArgumentNode): bool {
        node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, "")
        left: ColumnarAttributeArgumentNode = node
        if !TryParseAnd(out left) {
            return false
        }

        while Peek() == (int)TokenType.BitwiseXor {
            position = position + 1
            right: ColumnarAttributeArgumentNode = node
            if !TryParseAnd(out right) {
                return false
            }

            left = ColumnarAttributeArgumentNode.Binary(ColumnarAttributeArgumentKind.BitwiseXor, left, right)
        }

        node = left
        return true
    }

    func TryParseAnd(out node: ColumnarAttributeArgumentNode): bool {
        node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, "")
        left: ColumnarAttributeArgumentNode = node
        if !TryParseUnary(out left) {
            return false
        }

        while Peek() == (int)TokenType.BitwiseAnd {
            position = position + 1
            right: ColumnarAttributeArgumentNode = node
            if !TryParseUnary(out right) {
                return false
            }

            left = ColumnarAttributeArgumentNode.Binary(ColumnarAttributeArgumentKind.BitwiseAnd, left, right)
        }

        node = left
        return true
    }

    func TryParseUnary(out node: ColumnarAttributeArgumentNode): bool {
        node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, "")
        kind := Peek()
        if kind == (int)TokenType.Minus || kind == (int)TokenType.BitwiseNot || kind == (int)TokenType.Not {
            position = position + 1
            operand: ColumnarAttributeArgumentNode = node
            if !TryParseUnary(out operand) {
                return false
            }

            if kind == (int)TokenType.Minus {
                node = ColumnarAttributeArgumentNode.Unary(ColumnarAttributeArgumentKind.Negate, operand)
                return true
            }

            if kind == (int)TokenType.BitwiseNot {
                node = ColumnarAttributeArgumentNode.Unary(ColumnarAttributeArgumentKind.BitwiseNot, operand)
                return true
            }

            node = ColumnarAttributeArgumentNode.Unary(ColumnarAttributeArgumentKind.LogicalNot, operand)
            return true
        }

        if kind == (int)TokenType.Plus {
            position = position + 1
            return TryParseUnary(out node)
        }

        return TryParsePrimary(out node)
    }

    func TryParsePrimary(out node: ColumnarAttributeArgumentNode): bool {
        node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, "")
        kind := Peek()
        if kind < 0 {
            return false
        }

        if kind == (int)TokenType.IntLiteral {
            node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.IntLiteral, TokenText(position))
            position = position + 1
            return true
        }

        if kind == (int)TokenType.FloatLiteral {
            node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.FloatLiteral, TokenText(position))
            position = position + 1
            return true
        }

        if kind == (int)TokenType.CharLiteral {
            node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.CharLiteral, TokenText(position))
            position = position + 1
            return true
        }

        if kind == (int)TokenType.StringLiteral || kind == (int)TokenType.TripleQuoteStringLiteral {
            node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.StringLiteral, StringLiteralDecoder.Decode(TokenText(position), false))
            position = position + 1
            return true
        }

        if kind == (int)TokenType.True || kind == (int)TokenType.False {
            boolText := "false"
            if kind == (int)TokenType.True {
                boolText = "true"
            }

            node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.BoolLiteral, boolText)
            position = position + 1
            return true
        }

        if kind == (int)TokenType.Null {
            node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, "")
            position = position + 1
            return true
        }

        if kind == (int)TokenType.Typeof {
            return TryParseTypeOf(out node)
        }

        // `nameof(X.Y)` IS A STRING CONSTANT AND IS ENCODED AS ONE, naming the LAST segment exactly as
        // C# does. Reading it here rather than refusing it keeps `[Obsolete(nameof(Old))]` writable.
        if kind == (int)TokenType.Nameof {
            return TryParseNameOf(out node)
        }

        if kind == (int)TokenType.LeftBracket {
            return TryParseArrayLiteral(out node)
        }

        if kind == (int)TokenType.LeftParen {
            position = position + 1
            if !TryParseOr(out node) {
                return false
            }

            if Peek() != (int)TokenType.RightParen {
                return false
            }

            position = position + 1
            return true
        }

        if kind == (int)TokenType.Identifier {
            path := ""
            if !TryParseDottedName(out path) {
                return false
            }

            node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.MemberPath, path)
            return true
        }

        return false
    }

    func TryParseTypeOf(out node: ColumnarAttributeArgumentNode): bool {
        node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, "")
        position = position + 1
        if Peek() != (int)TokenType.LeftParen {
            return false
        }

        position = position + 1
        operandStart := position
        depth := 1
        while position < limit && depth > 0 {
            current := tokens.Kinds[position]
            if current == (int)TokenType.LeftParen {
                depth = depth + 1
            }

            if current == (int)TokenType.RightParen {
                depth = depth - 1
                if depth == 0 {
                    break
                }
            }

            position = position + 1
        }

        if depth != 0 || position <= operandStart {
            return false
        }

        typeText := SourceRangeText(operandStart, position)
        position = position + 1
        node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.TypeOf, typeText)
        return true
    }

    func TryParseNameOf(out node: ColumnarAttributeArgumentNode): bool {
        node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.NullLiteral, "")
        position = position + 1
        if Peek() != (int)TokenType.LeftParen {
            return false
        }

        position = position + 1
        path := ""
        if !TryParseDottedName(out path) || Peek() != (int)TokenType.RightParen {
            return false
        }

        position = position + 1
        separator := path.LastIndexOf(".", StringComparison.Ordinal)
        if separator >= 0 {
            path = path.Substring(separator + 1)
        }

        node = new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.StringLiteral, path)
        return true
    }

    func TryParseArrayLiteral(out node: ColumnarAttributeArgumentNode): bool {
        array := new ColumnarAttributeArgumentNode(ColumnarAttributeArgumentKind.ArrayLiteral, "")
        node = array
        position = position + 1
        if Peek() == (int)TokenType.RightBracket {
            position = position + 1
            return true
        }

        while true {
            element: ColumnarAttributeArgumentNode = array
            if !TryParseOr(out element) {
                return false
            }

            array.Children.Add(element)
            if Peek() == (int)TokenType.Comma {
                position = position + 1
                continue
            }

            break
        }

        if Peek() != (int)TokenType.RightBracket {
            return false
        }

        position = position + 1
        return true
    }

    func TryParseDottedName(out path: string): bool {
        path = ""
        if Peek() != (int)TokenType.Identifier {
            return false
        }

        path = TokenText(position)
        position = position + 1
        while position + 1 < limit && tokens.Kinds[position] == (int)TokenType.Dot && tokens.Kinds[position + 1] == (int)TokenType.Identifier {
            path = path + "." + TokenText(position + 1)
            position = position + 2
        }

        return true
    }

    // THE SOURCE SLICE A TOKEN RANGE COVERS, delimiters and spacing included. A `typeof` operand is
    // the one place an argument names a TYPE rather than a value, and the type resolver reads
    // spellings, not token tables.
    func SourceRangeText(start: int, end: int): string {
        textStart := tokens.Starts[start]
        textEnd := tokens.Starts[end - 1] + tokens.ValueLengths[end - 1]
        return source.Substring(textStart, textEnd - textStart)
    }
}

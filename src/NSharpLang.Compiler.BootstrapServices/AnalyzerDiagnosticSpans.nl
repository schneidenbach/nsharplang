namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence

// WHERE A SEMANTIC DIAGNOSTIC POINTS, AND HOW FAR IT UNDERLINES.
//
// A `CompilerError` carries a line, a column and a LENGTH, and the length is what turns a caret into
// a squiggle in the editor. Every semantic report in the analyzer therefore has to answer the same
// question — "which characters is this finding ABOUT?" — and the answer is never the AST node's raw
// `(Line, Column)`: a member access reports on the MEMBER NAME, not the receiver; a call reports on
// the callee's written name; a string literal reports on the whole quoted token including its
// quotes; a null-path guard reports on the whole dotted path as the reader WROTE it.
//
// This value is that answer. It is a reference type rather than a value struct for the same reason
// `RecoverySpan` is one in `ColumnarParserRecovery`: the recovery model proved the shape, and the
// analyzer's use is one allocation per REPORT, which is already the rarest thing the walk does.
//
// `Deconstruct` is the whole reason the C# reporting arms did not have to be rewritten. C#'s
// positional deconstruction binds to any accessible instance `void Deconstruct(out …)`, so a caller
// that used to write `var (line, column, length) = GetExpressionDiagnosticSpan(expr)` over a C#
// tuple keeps that line verbatim over this type. The owner moved; the reporting arms did not have
// to.
public class DiagnosticSpan {
    Line: int
    Column: int
    Length: int

    constructor(line: int, column: int, length: int) {
        Line = line
        Column = column
        Length = length
    }

    public func Deconstruct(out line: int, out column: int, out length: int) {
        line = Line
        column = Column
        length = Length
    }
}

// THE SPAN FACTS THAT NEED NO SOURCE TEXT.
//
// Everything here is a pure function of AST node positions and names. They are separated from
// `AnalyzerDiagnosticSpans` because they are answerable without an analysed file at all — which is
// also what makes them directly testable without standing up a diagnostic sink.
public class AnalyzerDiagnosticSpanFacts {

    // A declaration reports on its NAME, and the parser already puts the declaration's column at the
    // name for this shape.
    public static func GetVariableDeclarationNameDiagnosticSpan(
        variableDeclaration: VariableDeclarationStatement): DiagnosticSpan {
        return new DiagnosticSpan(
            variableDeclaration.Line,
            variableDeclaration.Column,
            Math.Max(1, variableDeclaration.Name.Length))
    }

    // A parser-supplied span wins when it is present AND single-line; a multi-line span cannot be
    // rendered as one underlined run, so the caller's fallback anchor is used instead. The fallback
    // LENGTH is always the caller's, because only the caller knows what the finding is about.
    public static func GetSourceSpanDiagnosticSpan(
        span: SourceSpan,
        fallbackLine: int,
        fallbackColumn: int,
        fallbackLength: int): DiagnosticSpan {
        if span.IsValid && span.StartLine == span.EndLine {
            return new DiagnosticSpan(span.StartLine, span.StartColumn, Math.Max(1, span.Length))
        }

        return new DiagnosticSpan(fallbackLine, fallbackColumn, Math.Max(1, fallbackLength))
    }

    // A binary expression's own position IS its operator's, so the operator text's length is the
    // whole span.
    public static func GetBinaryOperatorDiagnosticSpan(expression: BinaryExpression): DiagnosticSpan {
        return new DiagnosticSpan(
            expression.Line,
            expression.Column,
            Math.Max(1, BinaryOperatorTextLength(expression)))
    }

    // Bound to a local first: a property read chained onto a call result is off the .nl surface.
    static func BinaryOperatorTextLength(expression: BinaryExpression): int {
        text := OperatorFacts.GetBinaryText(expression.Operator)
        return text.Length
    }

    public static func GetAttributeTypeDiagnosticSpan(attribute: AttributeNode): DiagnosticSpan {
        return new DiagnosticSpan(attribute.Line, attribute.Column, Math.Max(1, attribute.Name.Length))
    }

    // The attribute has no usable position of its own — the finding is still reported, anchored at
    // the top of the file, rather than dropped.
    public static func GetAttributeFallbackDiagnosticSpan(attribute: AttributeNode): DiagnosticSpan {
        return new DiagnosticSpan(1, 1, Math.Max(1, attribute.Name.Length))
    }

    // An SoA column's TYPE reports on the written type reference when the parser recorded a span for
    // it, and falls back to the column's own position underlining the column NAME's width.
    public static func GetSoaColumnTypeDiagnosticSpan(column: SoaColumnDeclaration): DiagnosticSpan {
        typeSpan := TypeReferenceFacts.GetStartSpan(column.Type)
        return GetSourceSpanDiagnosticSpan(
            typeSpan,
            column.Line,
            column.Column,
            Math.Max(1, column.Name.Length))
    }

    // A column parsed without a position of its own is anchored on its declaring record.
    public static func GetSoaColumnNameDiagnosticSpan(
        column: SoaColumnDeclaration,
        declaration: SoaRecordDeclaration): DiagnosticSpan {
        line := declaration.Line
        if column.Line > 0 {
            line = column.Line
        }

        columnPosition := declaration.Column
        if column.Column > 0 {
            columnPosition = column.Column
        }

        return new DiagnosticSpan(line, columnPosition, Math.Max(1, column.Name.Length))
    }

    public static func GetParameterDiagnosticSpan(
        parameter: Parameter,
        fallbackLine: int,
        fallbackColumn: int): DiagnosticSpan {
        line := fallbackLine
        if parameter.Line > 0 {
            line = parameter.Line
        }

        column := fallbackColumn
        if parameter.Column > 0 {
            column = parameter.Column
        }

        return new DiagnosticSpan(line, column, Math.Max(1, parameter.Name.Length))
    }

    // THE PATH A NULL-STATE DIAGNOSTIC CAN NAME BACK TO THE READER.
    //
    // A path is STABLE when re-reading it cannot change what it denotes and cannot run anything: a
    // local name, `this`, and dotted member reads over those. A call, an index, a null-conditional
    // hop or a parser error placeholder all break stability, and the answer is then null — the
    // diagnostic falls back to describing the expression instead of quoting it.
    public static func TryGetStableNullPath(expression: Expression): string? {
        identifier := expression as IdentifierExpression
        if identifier != null {
            if identifier.Name != "<error>" {
                return identifier.Name
            }

            return null
        }

        thisExpression := expression as ThisExpression
        if thisExpression != null {
            return "this"
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return TryGetStableNullPath(parenthesized.Inner)
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null && !memberAccess.IsNullConditional {
            receiverPath := TryGetStableNullPath(memberAccess.Object)
            if receiverPath != null {
                return receiverPath + "." + memberAccess.MemberName
            }
        }

        return null
    }

    // WHERE THE WRITTEN EXPRESSION STARTS, not where its node claims to be. A member access, an
    // index, a call and a parenthesised group all record their position at the OPERATOR, so walking
    // to the leftmost leaf is what finds the first character the reader typed.
    public static func GetExpressionStartPosition(
        expression: Expression,
        fallbackLine: int,
        fallbackColumn: int,
        out line: int,
        out column: int) {
        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            GetExpressionStartPosition(memberAccess.Object, fallbackLine, fallbackColumn, out line, out column)
            return
        }

        indexAccess := expression as IndexAccessExpression
        if indexAccess != null {
            GetExpressionStartPosition(indexAccess.Object, fallbackLine, fallbackColumn, out line, out column)
            return
        }

        call := expression as CallExpression
        if call != null {
            GetExpressionStartPosition(call.Callee, fallbackLine, fallbackColumn, out line, out column)
            return
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            GetExpressionStartPosition(parenthesized.Inner, fallbackLine, fallbackColumn, out line, out column)
            return
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            GetExpressionStartPosition(checkedExpression.Expression, fallbackLine, fallbackColumn, out line, out column)
            return
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            GetExpressionStartPosition(uncheckedExpression.Expression, fallbackLine, fallbackColumn, out line, out column)
            return
        }

        if expression.Line > 0 && expression.Column > 0 {
            line = expression.Line
            column = expression.Column
            return
        }

        line = fallbackLine
        column = fallbackColumn
    }

    // The identifier-column probe's null guard. Without text there is nothing to search, and the
    // caller's fallback column stands.
    public static func FindIdentifierNameColumn(
        sourceText: string?,
        name: string,
        line: int,
        fallbackColumn: int): int {
        if sourceText == null {
            return fallbackColumn
        }

        return CodeIntelligenceTextUtilities.FindIdentifierNameColumn(sourceText, name, line, fallbackColumn)
    }

    // A quoted token runs to its closing quote, honouring backslash escapes; an UNTERMINATED one
    // runs to the end of the line, so the squiggle still covers what the reader wrote.
    public static func ScanQuotedTokenLength(sourceLine: string, quoteStart: int, quote: char): int {
        index := quoteStart + 1
        while index < sourceLine.Length {
            if sourceLine[index] == quote && sourceLine[index - 1] != '\\' {
                return index - quoteStart + 1
            }

            index = index + 1
        }

        return Math.Max(1, sourceLine.Length - quoteStart)
    }
}

// THE SPAN RESOLVER — the analyzer's single authority for where a semantic diagnostic points.
//
// The source text reaches this owner through exactly ONE door: the diagnostic sink, which already
// resolves the analysed file's text the same way for every report (the caller's own text when it
// supplied one, and otherwise the project snapshot's copy of the current file — the unsaved-editor
// buffer path). Sharing that resolution is not a convenience: a span computed against a DIFFERENT
// snapshot from the one the snippet is rendered from would underline the wrong characters, and the
// two would drift silently. One owner, one text.
public class AnalyzerDiagnosticSpans {

    diagnosticsValue: AnalyzerDiagnosticSink

    constructor(diagnostics: AnalyzerDiagnosticSink) {
        diagnosticsValue = diagnostics
    }

    func SourceSnippet(line: int): string? {
        return diagnosticsValue.SourceSnippet(line)
    }

    // WHAT ONE TOKEN OCCUPIES ON A LINE.
    //
    // Used wherever the AST records a position but no width — a keyword, a statement head, an
    // expression form with no name of its own. A quoted token is measured whole (including an
    // interpolation's `$`); anything else runs to the next whitespace or closing delimiter, so a
    // token followed by `,`, `)`, `]` or `}` does not swallow it.
    public func GetTokenLength(line: int, column: int): int {
        sourceLine := SourceSnippet(line)
        if sourceLine == null {
            return 1
        }

        start := column - 1
        if start < 0 || start >= sourceLine.Length {
            return 1
        }

        if sourceLine[start] == '"' {
            return AnalyzerDiagnosticSpanFacts.ScanQuotedTokenLength(sourceLine, start, '"')
        }

        if sourceLine[start] == '\'' {
            return AnalyzerDiagnosticSpanFacts.ScanQuotedTokenLength(sourceLine, start, '\'')
        }

        if sourceLine[start] == '$' && start + 1 < sourceLine.Length && sourceLine[start + 1] == '"' {
            return 1 + AnalyzerDiagnosticSpanFacts.ScanQuotedTokenLength(sourceLine, start + 1, '"')
        }

        end := start
        while end < sourceLine.Length {
            ch := sourceLine[end]
            if Char.IsWhiteSpace(ch) || ch == ',' || ch == ')' || ch == ']' || ch == '}' {
                break
            }

            end = end + 1
        }

        return Math.Max(1, end - start)
    }

    // The rest of the LINE from a position. The statement-expression fallback uses this rather than
    // `GetTokenLength` because "this statement has no effect" is about the whole written statement,
    // not its first token.
    public func GetExpressionLength(line: int, column: int): int {
        sourceLine := SourceSnippet(line)
        if sourceLine == null {
            return 1
        }

        trimmed := sourceLine.TrimEnd()
        if column <= 0 || column > sourceLine.Length {
            return Math.Max(1, trimmed.Length)
        }

        return Math.Max(1, trimmed.Length - column + 1)
    }

    // WHERE A MEMBER ACCESS REPORTS: on the member NAME, not on the dot and not on the receiver.
    //
    // The AST records the access's position at the dot, so the name's column is found by searching
    // the line for the identifier. The fallback steps past the operator — one character for `.`, two
    // for `?.` — which is what the column would be if the source text were unavailable.
    public func GetMemberNameColumn(member: MemberAccessExpression): int {
        fallbackColumn := member.Column + 1
        if member.IsNullConditional {
            fallbackColumn = member.Column + 2
        }

        return AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(
            diagnosticsValue.ResolvedSourceText(),
            member.MemberName,
            member.Line,
            fallbackColumn)
    }

    // Where a DECLARATION's name starts on its own line. An unnamed declaration keeps the caller's
    // column.
    public func GetDeclarationNameColumn(name: string, line: int, fallbackColumn: int): int {
        if string.IsNullOrWhiteSpace(name) {
            return fallbackColumn
        }

        return AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(
            diagnosticsValue.ResolvedSourceText(),
            name,
            line,
            fallbackColumn)
    }

    // THE SPAN OF AN EXPRESSION A DIAGNOSTIC IS ABOUT. The analyzer's most-used span by an order of
    // magnitude.
    //
    // Each literal form knows its own written width without consulting the text: an integer or float
    // literal keeps its lexeme, `true`/`false` are 4 and 5, `null` is 4, `this` is 4. The quoted
    // forms do not — an escape makes the lexeme shorter than the source — so they measure the token.
    // A member access whose whole dotted path is STABLE underlines the path as written, which is what
    // makes a null-state diagnostic point at `a.b.c` rather than at `c`.
    public func GetExpressionDiagnosticSpan(expression: Expression): DiagnosticSpan {
        identifier := expression as IdentifierExpression
        if identifier != null {
            return new DiagnosticSpan(identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length))
        }

        thisExpression := expression as ThisExpression
        if thisExpression != null {
            return new DiagnosticSpan(thisExpression.Line, thisExpression.Column, 4)
        }

        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            return new DiagnosticSpan(intLiteral.Line, intLiteral.Column, Math.Max(1, intLiteral.Value.Length))
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            return new DiagnosticSpan(floatLiteral.Line, floatLiteral.Column, Math.Max(1, floatLiteral.Value.Length))
        }

        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            return new DiagnosticSpan(
                charLiteral.Line,
                charLiteral.Column,
                GetTokenLength(charLiteral.Line, charLiteral.Column))
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            return new DiagnosticSpan(
                stringLiteral.Line,
                stringLiteral.Column,
                GetTokenLength(stringLiteral.Line, stringLiteral.Column))
        }

        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            return new DiagnosticSpan(
                interpolated.Line,
                interpolated.Column,
                GetTokenLength(interpolated.Line, interpolated.Column))
        }

        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            boolLength := 5
            if boolLiteral.Value {
                boolLength = 4
            }

            return new DiagnosticSpan(boolLiteral.Line, boolLiteral.Column, boolLength)
        }

        nullLiteral := expression as NullLiteralExpression
        if nullLiteral != null {
            return new DiagnosticSpan(nullLiteral.Line, nullLiteral.Column, 4)
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            memberColumn := GetMemberNameColumn(memberAccess)
            path := AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(memberAccess)
            if path != null {
                return GetStablePathDiagnosticSpan(memberAccess, path, memberAccess.Line, memberColumn)
            }

            return new DiagnosticSpan(
                memberAccess.Line,
                memberColumn,
                Math.Max(1, memberAccess.MemberName.Length))
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return GetExpressionDiagnosticSpan(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return GetExpressionDiagnosticSpan(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return GetExpressionDiagnosticSpan(uncheckedExpression.Expression)
        }

        allocExpression := expression as AllocExpression
        if allocExpression != null {
            return GetExpressionDiagnosticSpan(allocExpression.Expression)
        }

        call := expression as CallExpression
        if call != null {
            callName := "call"
            written := AnalyzerSyntheticCallFacts.GetCallTargetName(call)
            if written != null {
                callName = written
            }

            return GetCallDiagnosticSpan(call, callName)
        }

        return new DiagnosticSpan(
            expression.Line,
            expression.Column,
            GetTokenLength(expression.Line, expression.Column))
    }

    // A CALL reports on its callee's written NAME. A call through an arbitrary expression has no
    // written name, so the caller's display name supplies the width instead.
    public func GetCallDiagnosticSpan(call: CallExpression, functionName: string): DiagnosticSpan {
        identifier := call.Callee as IdentifierExpression
        if identifier != null {
            return new DiagnosticSpan(identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length))
        }

        memberAccess := call.Callee as MemberAccessExpression
        if memberAccess != null {
            return new DiagnosticSpan(
                memberAccess.Line,
                GetMemberNameColumn(memberAccess),
                Math.Max(1, memberAccess.MemberName.Length))
        }

        return new DiagnosticSpan(call.Line, call.Column, Math.Max(1, functionName.Length))
    }

    // THE WRITTEN PATH, LOCATED IN THE LINE. The path is found by searching FORWARD from the
    // expression's start, and only then from the start of the line, so a line that mentions `a.b`
    // twice underlines the occurrence this expression actually is. A path the line does not contain
    // at all — a continuation across lines — still reports, anchored at the expression's start.
    public func GetStablePathDiagnosticSpan(
        expression: Expression,
        path: string,
        fallbackLine: int,
        fallbackColumn: int): DiagnosticSpan {
        line := 0
        column := 0
        AnalyzerDiagnosticSpanFacts.GetExpressionStartPosition(
            expression,
            fallbackLine,
            fallbackColumn,
            out line,
            out column)

        sourceLine := SourceSnippet(line)
        if sourceLine != null {
            startIndex := column - 1
            if startIndex < 0 {
                startIndex = 0
            }
            if startIndex > sourceLine.Length {
                startIndex = sourceLine.Length
            }

            index := sourceLine.IndexOf(path, startIndex, StringComparison.Ordinal)
            if index < 0 {
                index = sourceLine.IndexOf(path, StringComparison.Ordinal)
            }

            if index >= 0 {
                return new DiagnosticSpan(line, index + 1, Math.Max(1, path.Length))
            }
        }

        return new DiagnosticSpan(line, column, Math.Max(1, path.Length))
    }

    // A null-receiver diagnostic quotes the receiver when the receiver has a name the reader wrote;
    // `this value` is the describer used when it does not, and a describer is not searchable text.
    public func GetNullReceiverDiagnosticSpan(
        receiver: Expression,
        path: string,
        fallbackLine: int,
        fallbackColumn: int): DiagnosticSpan {
        if path != "this value" {
            return GetStablePathDiagnosticSpan(receiver, path, fallbackLine, fallbackColumn)
        }

        return GetExpressionDiagnosticSpan(receiver)
    }

    // WHICH SIDE OF A BINARY EXPRESSION IS AT FAULT. Exactly one wrong operand reports on that
    // operand; both wrong (or neither identifiable) reports on the operator, because underlining one
    // side would be a claim the analyzer cannot support.
    public func GetBinaryOperandDiagnosticSpan(
        expression: BinaryExpression,
        leftIsWrong: bool,
        rightIsWrong: bool): DiagnosticSpan {
        if leftIsWrong && !rightIsWrong {
            return GetExpressionDiagnosticSpan(expression.Left)
        }

        if rightIsWrong && !leftIsWrong {
            return GetExpressionDiagnosticSpan(expression.Right)
        }

        return AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(expression)
    }

    // A STATEMENT-position expression reports differently from the same expression in a value
    // position: "this has no effect" is about the whole written statement, so the unnamed forms run
    // to the end of the line rather than measuring one token.
    public func GetExpressionStatementDiagnosticSpan(expression: Expression): DiagnosticSpan {
        identifier := expression as IdentifierExpression
        if identifier != null {
            return new DiagnosticSpan(identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length))
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            return new DiagnosticSpan(
                memberAccess.Line,
                GetMemberNameColumn(memberAccess),
                Math.Max(1, memberAccess.MemberName.Length))
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return GetExpressionStatementDiagnosticSpan(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return GetExpressionStatementDiagnosticSpan(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return GetExpressionStatementDiagnosticSpan(uncheckedExpression.Expression)
        }

        return new DiagnosticSpan(
            expression.Line,
            expression.Column,
            GetExpressionLength(expression.Line, expression.Column))
    }

    public func GetStatementDiagnosticSpan(statement: Statement): DiagnosticSpan {
        expressionStatement := statement as ExpressionStatement
        if expressionStatement != null {
            return GetExpressionStatementDiagnosticSpan(expressionStatement.Expression)
        }

        variableDeclaration := statement as VariableDeclarationStatement
        if variableDeclaration != null {
            return AnalyzerDiagnosticSpanFacts.GetVariableDeclarationNameDiagnosticSpan(variableDeclaration)
        }

        localFunction := statement as LocalFunctionStatement
        if localFunction != null {
            return new DiagnosticSpan(
                localFunction.Line,
                localFunction.Column,
                GetTokenLength(localFunction.Line, localFunction.Column))
        }

        return new DiagnosticSpan(
            statement.Line,
            statement.Column,
            GetTokenLength(statement.Line, statement.Column))
    }

    // A function reports on its NAME. A function with no usable name — the parser's error
    // placeholder, or nothing at all — falls back to measuring whatever token is at its position, so
    // a malformed declaration still gets a squiggle rather than a bare caret.
    public func GetFunctionNameDiagnosticSpan(function: FunctionDeclaration): DiagnosticSpan {
        if string.IsNullOrWhiteSpace(function.Name) || function.Name == "<error>" {
            return new DiagnosticSpan(
                function.Line,
                function.Column,
                GetTokenLength(function.Line, function.Column))
        }

        return new DiagnosticSpan(
            function.Line,
            GetDeclarationNameColumn(function.Name, function.Line, function.Column),
            Math.Max(1, function.Name.Length))
    }

    // An ASSIGNMENT TARGET reports on the name being written to. Unlike the general expression span
    // this never widens to a stable PATH — an assignment diagnostic is about the member being
    // assigned, not about the receiver chain that reaches it.
    public func GetAssignmentTargetNameDiagnosticSpan(
        target: Expression,
        fallbackLine: int,
        fallbackColumn: int): DiagnosticSpan {
        identifier := target as IdentifierExpression
        if identifier != null {
            return new DiagnosticSpan(identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length))
        }

        memberAccess := target as MemberAccessExpression
        if memberAccess != null {
            return new DiagnosticSpan(
                memberAccess.Line,
                GetMemberNameColumn(memberAccess),
                Math.Max(1, memberAccess.MemberName.Length))
        }

        parenthesized := target as ParenthesizedExpression
        if parenthesized != null {
            return GetAssignmentTargetNameDiagnosticSpan(parenthesized.Inner, fallbackLine, fallbackColumn)
        }

        return new DiagnosticSpan(
            fallbackLine,
            fallbackColumn,
            GetTokenLength(fallbackLine, fallbackColumn))
    }

    // A PATTERN reports on the name it introduces or matches.
    public func GetPatternNameDiagnosticSpan(pattern: Pattern): DiagnosticSpan {
        identifier := pattern as IdentifierPattern
        if identifier != null {
            return new DiagnosticSpan(identifier.Line, identifier.Column, Math.Max(1, identifier.Name.Length))
        }

        unionCase := pattern as UnionCasePattern
        if unionCase != null {
            return new DiagnosticSpan(unionCase.Line, unionCase.Column, Math.Max(1, unionCase.CaseName.Length))
        }

        typePattern := pattern as TypePattern
        if typePattern != null {
            return new DiagnosticSpan(
                typePattern.Line,
                typePattern.Column,
                GetTypePatternNameLength(typePattern))
        }

        listPattern := pattern as ListPattern
        if listPattern != null {
            return GetListPatternDiagnosticSpan(listPattern)
        }

        return new DiagnosticSpan(
            pattern.Line,
            pattern.Column,
            GetTokenLength(pattern.Line, pattern.Column))
    }

    // A type pattern underlines the type NAME only — not its type arguments, which are written after
    // the name and are not what a pattern diagnostic is about.
    public func GetTypePatternNameLength(typePattern: TypePattern): int {
        simple := typePattern.Type as SimpleTypeReference
        if simple != null {
            return Math.Max(1, simple.Name.Length)
        }

        generic := typePattern.Type as GenericTypeReference
        if generic != null {
            return Math.Max(1, generic.Name.Length)
        }

        return GetTokenLength(typePattern.Line, typePattern.Column)
    }

    // A property pattern with no position of its own is anchored on its enclosing pattern, and the
    // parser's error placeholder measures the token rather than the placeholder's own width.
    public func GetPropertyPatternNameDiagnosticSpan(
        propertyPattern: PropertyPattern,
        fallbackLine: int,
        fallbackColumn: int): DiagnosticSpan {
        line := fallbackLine
        if propertyPattern.Line > 0 {
            line = propertyPattern.Line
        }

        column := fallbackColumn
        if propertyPattern.Column > 0 {
            column = propertyPattern.Column
        }

        length := Math.Max(1, propertyPattern.Name.Length)
        if propertyPattern.Name == "<error>" {
            length = GetTokenLength(line, column)
        }

        return new DiagnosticSpan(line, column, length)
    }

    // A LIST pattern underlines the whole bracketed group, so the diagnostic covers what the reader
    // sees as one pattern.
    public func GetListPatternDiagnosticSpan(listPattern: ListPattern): DiagnosticSpan {
        return new DiagnosticSpan(
            listPattern.Line,
            listPattern.Column,
            GetDelimitedPatternLength(listPattern.Line, listPattern.Column, '[', ']'))
    }

    // A balanced delimiter walk on ONE line. A group that does not close on its line runs to the end
    // of the written text; a position that is not the opening delimiter at all falls back to
    // measuring a token, because the caller's position is then not what it was assumed to be.
    public func GetDelimitedPatternLength(
        line: int,
        column: int,
        openDelimiter: char,
        closeDelimiter: char): int {
        sourceLine := SourceSnippet(line)
        if sourceLine == null {
            return 1
        }

        start := column - 1
        if start < 0 || start >= sourceLine.Length || sourceLine[start] != openDelimiter {
            return GetTokenLength(line, column)
        }

        depth := 0
        index := start
        while index < sourceLine.Length {
            ch := sourceLine[index]
            if ch == openDelimiter {
                depth = depth + 1
            } else if ch == closeDelimiter {
                depth = depth - 1
                if depth == 0 {
                    return index - start + 1
                }
            }

            index = index + 1
        }

        trimmed := sourceLine.TrimEnd()
        return Math.Max(1, trimmed.Length - start)
    }

    // AN `is` EXPRESSION underlines `is` THROUGH THE TESTED TYPE NAME — `is string`, not `is` alone —
    // because the finding is about the test, and the test is not readable without its type. Without
    // source text, or when the type name cannot be scanned, the keyword alone stands.
    public func GetIsExpressionDiagnosticSpan(isExpr: IsExpression): DiagnosticSpan {
        isKeywordLength := 2

        sourceLine := SourceSnippet(isExpr.Line)
        if sourceLine == null {
            return new DiagnosticSpan(isExpr.Line, isExpr.Column, isKeywordLength)
        }

        start := isExpr.Column - 1
        if start < 0 || start >= sourceLine.Length {
            return new DiagnosticSpan(isExpr.Line, isExpr.Column, isKeywordLength)
        }

        typeStart := start + isKeywordLength
        while typeStart < sourceLine.Length && Char.IsWhiteSpace(sourceLine[typeStart]) {
            typeStart = typeStart + 1
        }

        if typeStart >= sourceLine.Length {
            return new DiagnosticSpan(isExpr.Line, isExpr.Column, isKeywordLength)
        }

        typeEnd := typeStart
        while typeEnd < sourceLine.Length && IsTypeNameChar(sourceLine[typeEnd]) {
            typeEnd = typeEnd + 1
        }

        if typeEnd <= typeStart {
            return new DiagnosticSpan(isExpr.Line, isExpr.Column, isKeywordLength)
        }

        return new DiagnosticSpan(isExpr.Line, isExpr.Column, typeEnd - start)
    }

    // The characters a written type reference can be made of: its name, its qualification, its type
    // arguments, its nullable marker and its array rank.
    static func IsTypeNameChar(ch: char): bool {
        if Char.IsLetterOrDigit(ch) {
            return true
        }

        return ch == '_'
            || ch == '.'
            || ch == '<'
            || ch == '>'
            || ch == '?'
            || ch == '['
            || ch == ']'
    }

    // AN ATTRIBUTE ARGUMENT reports on the NAME when the argument is a named one written as an
    // assignment, because that is the part the diagnostic is about; otherwise on the value.
    //
    // The C# owner took the analyzer's private validation record; the N# owner takes the two fields
    // it actually read, so the record stays with the attribute-validation family it belongs to.
    public func GetAttributeArgumentDiagnosticSpan(argument: Argument, value: Expression): DiagnosticSpan {
        if argument.Name == null {
            assignment := argument.Value as AssignmentExpression
            if assignment != null {
                identifier := assignment.Target as IdentifierExpression
                if identifier != null {
                    return new DiagnosticSpan(
                        identifier.Line,
                        identifier.Column,
                        Math.Max(1, identifier.Name.Length))
                }
            }
        }

        return GetExpressionDiagnosticSpan(value)
    }
}

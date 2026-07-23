namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// A diagnostic span (line / column / length) used to anchor recovery diagnostics.
// A local reference type rather than the C#-owned DiagnosticSpan value struct.
public class RecoverySpan {
    Line: int
    Column: int
    Length: int

    constructor(line: int, column: int, length: int) {
        Line = line
        Column = column
        Length = length
    }
}

// Stage 1 of the task-016 parser-front-end arc: a faithful N# reproduction of the
// Parser.cs shared-panic recovery model, carrying the import / namespace / package
// diagnostic family end-to-end.
//
// The model this owner reproduces byte-exact (see Parser.cs):
//   * ONE shared _panicMode flag (here `PanicMode`).
//   * Report() suppresses while panic is set, otherwise records the diagnostic in
//     SOURCE ORDER and sets panic (Parser.cs ReportError, :6845).
//   * Panic is reset ONLY at parse-structure sync points. For the file preamble the
//     sync point is the declaration boundary (Parser.cs :83); cascading diagnostics in
//     the package/import loop are therefore suppressed with no intervening reset.
//   * The import/namespace family funnels every "expected identifier" decision through
//     ConsumeIdentifier (Parser.cs :6720) with the reserved-keyword / end-of-file /
//     found-other message variants and the LastVisibleTokenSpan anchoring.
//
// This owner is NOT wired into production. Parser.cs remains the sole production
// syntax-diagnostic authority until the arc's cutover stage. The deliverable here is
// kernel-side capability + parity proofs (ColumnarParserRecovery.tests.nl). Diagnostic
// CONSTRUCTION is delegated to the already-live shared owner ParserErrorDiagnostics.Create
// (the same call Parser.cs uses), so codes / snippets / docs URLs match automatically.
public class ColumnarParserRecovery {
    Tokens: List<Token>
    FileName: string?
    Source: string
    Position: int
    PanicMode: bool
    // Stage 5: tracks a `>>` (RightShift) token that ConsumeGreater split into two `>` when closing
    // nested generics (Parser.cs `_splitGreaterDepth`, :2141). While > 0 the cursor "owes" a virtual
    // `>` (Check/Advance below honor it, exactly as Parser.cs). Reset at the same sync points Parser.cs
    // resets it (SynchronizeToNextDeclaration/Statement :7042/:7086 → the declaration/member boundaries).
    SplitGreaterDepth: int
    Errors: List<CompilerError>

    constructor(source: string, fileName: string?) {
        Source = source
        FileName = fileName
        Position = 0
        PanicMode = false
        SplitGreaterDepth = 0
        Errors = new List<CompilerError>()

        lexer := new Lexer(source, fileName)
        rawTokens := lexer.Tokenize()

        // Compact the token stream exactly as Parser.cs does (ParserTokenCompactor.TryCompact):
        // drop Newline tokens so the directive/declaration cursor sees a structural stream.
        // Inlined rather than routed through the out-parameter API, which the columnar backend
        // does not yet emit for a reference-typed out argument.
        compacted := new List<Token>()
        i := 0
        while i < rawTokens.Count {
            token := rawTokens[i]
            if token.Type != TokenType.Newline {
                compacted.Add(token)
            }
            i = i + 1
        }
        Tokens = compacted
    }

    // Parse the file preamble (namespace + package/import directives) and cross the
    // declaration boundary, reporting the import/namespace family diagnostics through the
    // shared-panic model. Returns the diagnostics in source order.
    public static func ParseFilePreamble(source: string, fileName: string?): List<CompilerError> {
        recovery := new ColumnarParserRecovery(source, fileName)
        recovery.Run()
        return recovery.Errors
    }

    // ---- token cursor (mirrors Parser.cs Current/Previous/Advance/Check/IsAtEnd) ----

    func Current(): Token {
        if Position < Tokens.Count {
            return Tokens[Position]
        }
        return Tokens[Tokens.Count - 1]
    }

    func Previous(): Token {
        if Position > 0 {
            return Tokens[Position - 1]
        }
        return Tokens[0]
    }

    func IsAtEnd(): bool {
        return Current().Type == TokenType.Eof
    }

    func Check(tokenType: TokenType): bool {
        // Split-`>>` discipline (Parser.cs Check, :6025): while we owe a `>` from a previously split
        // `>>`, a request for `>` is satisfied without consuming a real token.
        if SplitGreaterDepth > 0 {
            if tokenType == TokenType.Greater {
                return true
            }
        }
        return Current().Type == tokenType
    }

    func Advance(): Token {
        // Split-`>>` discipline (Parser.cs Advance, :5860): consuming the owed `>` decrements the debt
        // and returns a virtual `>` positioned one column past the previous token, without moving the
        // real cursor.
        if SplitGreaterDepth > 0 {
            SplitGreaterDepth = SplitGreaterDepth - 1
            prev := Tokens[Position - 1]
            return new Token(TokenType.Greater, ">", prev.Line, prev.Column + 1, prev.FileName)
        }
        if !IsAtEnd() {
            Position = Position + 1
        }
        return Tokens[Position - 1]
    }

    // Look at the token `offset` positions ahead without consuming (Parser.cs LookAhead, :6042).
    func LookAhead(offset: int): Token {
        pos := Position + offset
        if pos < Tokens.Count {
            return Tokens[pos]
        }
        return Tokens[Tokens.Count - 1]
    }

    // ---- shared-panic reporting (mirrors Parser.cs ReportError, :6845) ----

    func Report(
        code: ErrorCode,
        message: string,
        line: int,
        column: int,
        humanExplanation: string?,
        hint: string?,
        suggestions: List<string>?,
        length: int) {
        // In panic mode, suppress cascading errors until we synchronize.
        if PanicMode {
            return
        }

        snippet := GetSourceSnippet(line)
        error := ParserErrorDiagnostics.Create(
            code,
            message,
            FileName,
            line,
            column,
            snippet,
            length,
            humanExplanation,
            hint,
            suggestions)
        Errors.Add(error)
        PanicMode = true
    }

    func GetSourceSnippet(line: int): string? {
        if line < 1 {
            return null
        }
        return CodeIntelligenceTextUtilities.GetSourceLine(Source, line)
    }

    // ---- span helpers (mirror Parser.cs DiagnosticSpanFromToken / LastVisibleTokenSpan) ----

    func TokenLength(token: Token): int {
        return MaxInt(1, token.Value.Length)
    }

    func SpanFromToken(token: Token): RecoverySpan {
        return new RecoverySpan(token.Line, token.Column, TokenLength(token))
    }

    // Anchor an end-of-file diagnostic on the last visible (non-EOF) token so it underlines
    // a real token rather than the empty EOF position (Parser.cs LastVisibleTokenSpan, :6090).
    func LastVisibleTokenSpan(): RecoverySpan {
        index := MinInt(Position, Tokens.Count - 1)
        while index >= 0 {
            token := Tokens[index]
            if token.Type != TokenType.Eof {
                if token.Value.Length > 0 {
                    return SpanFromToken(token)
                }
            }
            index = index - 1
        }

        fallback := Current()
        return new RecoverySpan(fallback.Line, MaxInt(1, fallback.Column), 1)
    }

    // ---- ConsumeIdentifier (mirrors Parser.cs :6720) ----
    // Every import/namespace/package "expected identifier" decision funnels through here.

    func ConsumeIdentifier(message: string): string {
        if Check(TokenType.Identifier) {
            return Advance().Value
        }

        previous := Previous()
        isDotAccess := previous.Type == TokenType.Dot || previous.Type == TokenType.QuestionDot

        // A reserved keyword where an identifier is required gets a precise, keyword-specific
        // diagnostic and is consumed so recovery continues past it.
        if !IsAtEnd() {
            if Lexer.IsReservedKeyword(Current().Type) {
                ReportReservedKeywordAsName(message, SpanFromToken(Current()), isDotAccess)
                Advance()
                return "<error>"
            }
        }

        if IsAtEnd() {
            eofSpan := LastVisibleTokenSpan()
            Report(
                ErrorCode.UnexpectedEndOfFile,
                message + ", but reached the end of the file",
                eofSpan.Line,
                eofSpan.Column,
                DotOrPlainEofExplanation(isDotAccess),
                DotOrPlainEofHint(isDotAccess),
                null,
                eofSpan.Length)
            return "<error>"
        }

        span := SpanFromToken(Current())
        Report(
            ErrorCode.ExpectedToken,
            message + ". Got '" + Current().Value + "'",
            span.Line,
            span.Column,
            DotOrPlainFoundExplanation(isDotAccess, Current().Value),
            DotOrPlainFoundHint(isDotAccess),
            DotAccessFoundSuggestions(isDotAccess),
            span.Length)
        return "<error>"
    }

    func ReportReservedKeywordAsName(contextMessage: string, span: RecoverySpan, isDotAccess: bool) {
        keyword := Current().Value
        suggestions := new List<string>()
        suggestions.Add("Rename it to '" + keyword + "Value' or '_" + keyword + "'")
        suggestions.Add("Pick any name that isn't a reserved N# keyword")

        Report(
            ErrorCode.ReservedKeywordAsName,
            contextMessage + ". Got the reserved keyword '" + keyword + "'",
            span.Line,
            span.Column,
            "'" + keyword + "' is a reserved keyword in N#, so it can't be used as a name here.",
            ReservedKeywordHint(keyword, isDotAccess),
            suggestions,
            span.Length)
    }

    func ReservedKeywordHint(keyword: string, isDotAccess: bool): string {
        if isDotAccess {
            return "After a member access, the name must not be a reserved keyword. To reach a  member literally named '" + keyword + "', access it through a differently-named alias."
        }
        return "Choose a name that isn't a reserved keyword (for example '" + keyword + "Value' or '_" + keyword + "')."
    }

    func DotOrPlainEofExplanation(isDotAccess: bool): string {
        if isDotAccess {
            return "I see a dot (.) operator but no member name after it; the file ended first."
        }
        return "I was expecting an identifier here, but the file ended first."
    }

    func DotOrPlainEofHint(isDotAccess: bool): string {
        if isDotAccess {
            return "After a dot, I need to see a property or method name."
        }
        return "Finish this construct before the end of the file."
    }

    func DotOrPlainFoundExplanation(isDotAccess: bool, found: string): string {
        if isDotAccess {
            return "I see a dot (.) operator but no member name after it. I found '" + found + "' instead."
        }
        return "I was expecting an identifier here, but I found '" + found + "' instead."
    }

    func DotOrPlainFoundHint(isDotAccess: bool): string {
        if isDotAccess {
            return "After a dot, I need to see a property or method name."
        }
        return "An identifier is a name for a variable, function, or type."
    }

    func DotAccessFoundSuggestions(isDotAccess: bool): List<string>? {
        if !isDotAccess {
            return null
        }
        suggestions := new List<string>()
        suggestions.Add("Check if you forgot to finish this line")
        suggestions.Add("Common members: Length, Count, ToString(), GetHashCode()")
        suggestions.Add("If this is end of statement, remove the trailing dot")
        return suggestions
    }

    // ---- ConsumeDeclarationName (Parser.cs ConsumeIdentifier with a keyword anchor, :6720) ----
    // Stage 2's declaration-NAME family funnels through here. It differs from ConsumeIdentifier
    // (the import/namespace family) only in that the caller supplies the DECLARATION-KEYWORD span
    // as the anchor (DiagnosticSpanFromToken(classToken), ...): a missing/invalid name underlines
    // the keyword (`class`, `func`, ...), not the offending token, in ALL THREE variants
    // (reserved-keyword / end-of-file / found-other). A declaration name is never a dot-access, so
    // isDotAccess is always false and the plain (non-dot) message variants apply.

    func ConsumeDeclarationName(message: string, anchor: RecoverySpan): string {
        if Check(TokenType.Identifier) {
            return Advance().Value
        }

        // A reserved keyword where a declaration name is required: keyword-specific diagnostic,
        // anchored on the declaration keyword, and the offender is consumed so recovery continues.
        if !IsAtEnd() {
            if Lexer.IsReservedKeyword(Current().Type) {
                ReportReservedKeywordAsName(message, anchor, false)
                Advance()
                return "<error>"
            }
        }

        if IsAtEnd() {
            Report(
                ErrorCode.UnexpectedEndOfFile,
                message + ", but reached the end of the file",
                anchor.Line,
                anchor.Column,
                DotOrPlainEofExplanation(false),
                DotOrPlainEofHint(false),
                null,
                anchor.Length)
            return "<error>"
        }

        Report(
            ErrorCode.ExpectedToken,
            message + ". Got '" + Current().Value + "'",
            anchor.Line,
            anchor.Column,
            DotOrPlainFoundExplanation(false, Current().Value),
            DotOrPlainFoundHint(false),
            DotAccessFoundSuggestions(false),
            anchor.Length)
        return "<error>"
    }

    // ---- preamble grammar (mirrors Parser.cs ParseCompilationUnit prefix) ----

    func ParseQualifiedName() {
        ConsumeIdentifier("Expected identifier")
        while Check(TokenType.Dot) {
            Advance()
            ConsumeIdentifier("Expected identifier after '.'")
        }
    }

    func ParseNamespace() {
        // The `namespace` keyword presence is guaranteed by the Check at the call site,
        // exactly as Parser.cs's guarded Consume(Namespace).
        Advance()
        ParseQualifiedName()
    }

    func ParsePackage() {
        Advance()
        ParseQualifiedName()
    }

    func ParseImport() {
        Advance()

        // File-based import: import "path/to/file" [as Alias]
        if Check(TokenType.StringLiteral) {
            Advance()
            if Check(TokenType.As) {
                Advance()
                ConsumeIdentifier("Expected alias name after 'as'")
            }
            return
        }

        // Namespace import: import System.Collections.Generic [as Alias]
        ParseQualifiedName()
        if Check(TokenType.As) {
            Advance()
            ConsumeIdentifier("Expected alias name after 'as'")
        }
    }

    func Run() {
        // Namespace (optional, file-scoped)
        if Check(TokenType.Namespace) {
            ParseNamespace()
        }

        // Package/import directives. No panic reset inside this loop: once one directive
        // reports, the rest are suppressed until the declaration boundary (Parser.cs :48-77).
        packageSeen := false
        while Check(TokenType.Package) || Check(TokenType.Import) {
            if Check(TokenType.Package) {
                if packageSeen {
                    Report(
                        ErrorCode.InvalidSyntax,
                        "Only one package declaration is allowed",
                        Current().Line,
                        Current().Column,
                        "A source file can belong to a single package.",
                        "Remove the extra package declaration.",
                        null,
                        MaxInt(1, Current().Value.Length))
                }

                ParsePackage()
                packageSeen = true
                continue
            }

            ParseImport()
        }

        // Declaration boundary. Stage 2 carries the declaration-NAME family through the SAME
        // shared-panic model: each top-level declaration resets panic (Parser.cs
        // ParseCompilationUnit :83), then parses the declaration keyword + name, anchoring a
        // missing/invalid name on the declaration keyword. Bodies are not parsed (a later arc
        // stage); the loop makes progress by consuming the keyword (and, for the reserved-keyword
        // recovery, the offending token) or the stray top-level token.
        while !IsAtEnd() {
            PanicMode = false
            SplitGreaterDepth = 0        // reset with panic at the declaration boundary (Parser.cs :7042)
            startPosition := Position
            ParseTopLevelDeclaration()

            // Force-advance safety net (Parser.cs :99-108): if a declaration parse consumed
            // nothing, advance so recovery cannot loop forever.
            if Position == startPosition {
                if !IsAtEnd() {
                    Advance()
                }
            }
        }
    }

    // Parse one top-level declaration's modifiers + keyword + NAME (Parser.cs ParseDeclaration
    // dispatch, :190-267). Stage 2 does not parse attributes or declaration bodies (later arc
    // stages), nor the contextual test/setup/teardown declarations (not part of the
    // declaration-name family). Every recognized keyword routes to a per-kind name parser that
    // mirrors the exact Parser.cs ConsumeIdentifier site; an unrecognized token hits the terminal
    // unexpected-token arm (Parser.cs ParseDeclaration :241), identical to Stage 1's arm.
    func ParseTopLevelDeclaration() {
        ParseModifiers()

        if Check(TokenType.Func) {
            ParseFunctionName()
            return
        }
        if Check(TokenType.Class) {
            ParseClassName()
            return
        }
        if Check(TokenType.Ref) {
            if LookAhead(1).Type == TokenType.Struct {
                Advance()
                ParseStructName()
                return
            }
        }
        if Check(TokenType.Struct) {
            ParseStructName()
            return
        }
        if IsSoaRecordDeclarationStart() {
            ParseSoaRecordName()
            return
        }
        if Check(TokenType.Record) {
            ParseRecordName()
            return
        }
        if Check(TokenType.Interface) {
            ParseInterfaceName()
            return
        }
        if Check(TokenType.Duck) {
            if LookAhead(1).Type == TokenType.Interface {
                ParseInterfaceName()
                return
            }
        }
        if Check(TokenType.Union) {
            ParseUnionName()
            return
        }
        if Check(TokenType.Enum) {
            ParseEnumName()
            return
        }
        if Check(TokenType.Type) {
            ParseTypeAliasName()
            return
        }

        Report(
            ErrorCode.UnexpectedToken,
            "Unexpected token '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '" + Current().Value + "' instead.",
            "Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.",
            null,
            Current().Value.Length)
        Advance()
    }

    // Consume leading modifier keywords (Parser.cs ParseModifiers, :298) so a modifier-led
    // declaration reaches its keyword.
    func ParseModifiers() {
        scanning := true
        while scanning {
            if !TryConsumeModifier() {
                scanning = false
            }
        }
    }

    func TryConsumeModifier(): bool {
        t := Current().Type
        if t == TokenType.Public {
            Advance()
            return true
        }
        if t == TokenType.Private {
            Advance()
            return true
        }
        if ParserTokenFacts.IsModifierKeyword(t) {
            Advance()
            return true
        }
        return false
    }

    func IsSoaRecordDeclarationStart(): bool {
        if Current().Type != TokenType.Identifier {
            return false
        }
        if Current().Value != "soa" {
            return false
        }
        return LookAhead(1).Type == TokenType.Record
    }

    // ---- per-kind declaration name parsers ----
    // Each mirrors the exact Parser.cs ConsumeIdentifier site: the anchor is
    // DiagnosticSpanFromToken of the declaration keyword, so a missing/invalid name underlines
    // the keyword (Parser.cs :435/939/984/1029/1067/1143/1173/1247/1337).

    func ParseFunctionName() {
        funcToken := Current()
        Advance()
        name := ConsumeDeclarationName("Expected function name", SpanFromToken(funcToken))
        if name == "<error>" {
            // A name error (Stage 2) leaves the offending/absent name for the boundary; do
            // not parse a body. Preserves the Stage-2 declaration-name model exactly.
            return
        }

        // Stage 3: a validly-named function may carry a MALFORMED-LITERAL diagnostic in its
        // expression body (Parser.cs reaches ReportMalformedStringLiteralIfNeeded /
        // ReportMalformedCharLiteralIfNeeded only inside ParsePrimaryExpression). Continue the
        // function head far enough to reach the body and run the literal check.
        ParseFunctionHeadAndBody()
    }

    // Parse the tail of a validly-named function far enough to reach an expression body, so the
    // malformed-LITERAL family (Stage 3) can be exercised through the shared-panic model. This is
    // the MINIMAL literal-reaching vehicle — the malformed-literal corpus uses `func f() => <lit>`
    // (the shallowest byte-exact literal context). General parameter/generic/return-type parsing
    // and the block-body statement grammar are LATER arc stages; here the head is only consumed
    // enough to reach `=> <expr>` for the empty-parameter, expression-bodied shape.
    func ParseFunctionHeadAndBody() {
        // Type parameter list `<T, U>` (Stage 5, Parser.cs :446). Runs BEFORE the parameter list,
        // exactly as ParseFunctionDeclaration does, so a malformed `<>` / `<T,>` / `<return>` list
        // reports its NL102/NL109 here. Absent when the function is non-generic (Check(Less) is false).
        ParseTypeParameters()

        // Parameter list (Parser.cs ParseParameterList :751). Stage 4 carries the parameter
        // name / colon / type diagnostic family through this list; the empty-list `()` shape the
        // Stage-3 malformed-literal corpus relies on is handled identically (Consume '(' … ')').
        ParseParameterListRecovery()

        // Optional return type `: T` (Parser.cs :465-468 then ParseTypeReference). Stage 5 routes the
        // return type through the generic-aware ParseTypeReferenceRecovery so a malformed generic return
        // type (`List<>`, `List<int,>`) reports ReportMissingGenericTypeArgument and an unclosed one
        // (`List<int =>`) reports the ConsumeGreater error. A simple identifier return type consumes
        // identically to the Stage-3/4 vehicle (Check(Less) is false → just the name).
        if Check(TokenType.Colon) {
            Advance()
            ParseTypeReferenceRecovery()
        }

        // Generic constraints `where T: …` (Stage 5, Parser.cs :488). Runs after the return type,
        // exactly as ParseFunctionDeclaration does.
        ParseGenericConstraints()

        // Expression-bodied function `=> <expr>` (Parser.cs :493-497).
        if Check(TokenType.Arrow) {
            Advance()
            ParseLiteralBearingExpression()
        }
    }

    // ---- minimal literal-reaching expression path (Stage 3 vehicle) ----
    // Reaches the literal operands of an expression so the malformed-literal check runs at each,
    // and consumes the flat binary-operator continuation so the shared-panic SUPPRESSION of a
    // following in-region literal error is exercised byte-exact (e.g. `'a + 'b` → only the first
    // reports). It is deliberately NOT a full expression parser: it models `( expr )` grouping,
    // literal primaries, and a flat binary-operator continuation only — enough to reach literals
    // and consume the corpus's trailing tokens identically to Parser.cs's ParseExpression. The
    // expression/statement ERROR families (unexpected-token-in-expression, dangling operator,
    // missing `)`) are a LATER arc stage and are never reported here (Parser.cs suppresses them
    // under the same shared panic, so the diagnostic output stays byte-exact).

    func ParseLiteralBearingExpression() {
        ParseLiteralBearingPrimary()
        while IsBinaryOperatorContinuation(Current().Type) {
            Advance()
            ParseLiteralBearingPrimary()
        }
    }

    func ParseLiteralBearingPrimary() {
        if Check(TokenType.LeftParen) {
            Advance()
            ParseLiteralBearingExpression()
            if Check(TokenType.RightParen) {
                Advance()
            }
            return
        }

        if IsLiteralToken(Current().Type) {
            token := Advance()
            ReportMalformedLiteralIfNeeded(token)
        }
    }

    func IsLiteralToken(t: TokenType): bool {
        if t == TokenType.IntLiteral {
            return true
        }
        if t == TokenType.FloatLiteral {
            return true
        }
        if t == TokenType.CharLiteral {
            return true
        }
        if t == TokenType.StringLiteral {
            return true
        }
        if t == TokenType.TripleQuoteStringLiteral {
            return true
        }
        if t == TokenType.InterpolatedRawStringLiteral {
            return true
        }
        return false
    }

    // The minimal binary-operator set needed to reach subsequent literal operands in the
    // malformed-literal corpus (e.g. `'a + 'b`). Full expression precedence is a later arc stage;
    // for the corpus's flat expressions this reaches the same tokens Parser.cs's ParseExpression does.
    func IsBinaryOperatorContinuation(t: TokenType): bool {
        if t == TokenType.Plus {
            return true
        }
        if t == TokenType.Minus {
            return true
        }
        if t == TokenType.Star {
            return true
        }
        if t == TokenType.Slash {
            return true
        }
        if t == TokenType.Percent {
            return true
        }
        return false
    }

    // ---- malformed-literal reporting (Parser.cs :4830/:4876/:4905) ----
    // The DECISION reuses the LIVE shared owner ParserLiteralFacts (Parser.cs delegates to the
    // identical IsCompleteStringLiteral/IsCompleteCharLiteral), and reporting routes through the
    // shared-panic Report so an in-region cascade is suppressed exactly as Parser.cs's.

    func ReportMalformedLiteralIfNeeded(token: Token) {
        t := token.Type
        if t == TokenType.CharLiteral {
            ReportMalformedCharLiteralIfNeeded(token)
            return
        }
        if t == TokenType.StringLiteral {
            ReportMalformedStringLiteralIfNeeded(token)
            return
        }
        if t == TokenType.TripleQuoteStringLiteral {
            ReportMalformedStringLiteralIfNeeded(token)
            return
        }
        if t == TokenType.InterpolatedRawStringLiteral {
            ReportMalformedStringLiteralIfNeeded(token)
            return
        }
    }

    func ReportMalformedStringLiteralIfNeeded(token: Token) {
        if token.Type == TokenType.TripleQuoteStringLiteral {
            ReportMalformedRawStringLiteralIfNeeded(
                token,
                "Unterminated triple-quoted string literal",
                "This triple-quoted string starts with `\"\"\"` but reaches the end of the file before the closing triple quote.",
                "Add the closing triple quote `\"\"\"` before the end of the file.",
                3)
            return
        }

        if token.Type == TokenType.InterpolatedRawStringLiteral {
            ReportMalformedRawStringLiteralIfNeeded(
                token,
                "Unterminated interpolated raw string literal",
                "This interpolated raw string starts with `$\"\"\"` but reaches the end of the file before the closing triple quote.",
                "Add the closing triple quote `\"\"\"` before the end of the file.",
                4)
            return
        }

        // Parser.cs :4854: only a StringLiteral that is unterminated OR whose value is not a
        // complete string literal is malformed.
        if token.Type != TokenType.StringLiteral {
            return
        }
        if token.IsTerminated && ParserLiteralFacts.IsCompleteStringLiteral(token.Value) {
            return
        }

        isInterpolated := StartsWithInterpolatedPrefix(token.Value)
        message := "Unterminated string literal"
        explanation := "This string starts with a quote but reaches the end of the line before a closing quote."
        if isInterpolated {
            message = "Unterminated interpolated string literal"
            explanation = "This interpolated string starts with `$\"` but reaches the end of the line before a closing quote."
        }

        suggestions := new List<string>()
        suggestions.Add("Add a closing quote")
        suggestions.Add("Use triple quotes for multi-line strings")

        Report(
            ErrorCode.InvalidLiteral,
            message,
            token.Line,
            token.Column,
            explanation,
            "Add the closing quote on this line, or use a triple-quoted string for multi-line text.",
            suggestions,
            MaxInt(1, token.Value.Length))
    }

    func ReportMalformedRawStringLiteralIfNeeded(
        token: Token,
        message: string,
        humanExplanation: string,
        hint: string,
        markerLength: int) {
        if token.IsTerminated {
            return
        }

        suggestions := new List<string>()
        suggestions.Add("Add the closing triple quote")
        suggestions.Add("Check where the raw string should end")

        Report(
            ErrorCode.InvalidLiteral,
            message,
            token.Line,
            token.Column,
            humanExplanation,
            hint,
            suggestions,
            markerLength)
    }

    func ReportMalformedCharLiteralIfNeeded(token: Token) {
        if ParserLiteralFacts.IsCompleteCharLiteral(token.Value) {
            return
        }

        isEmpty := token.Value == "''"
        message := "Unterminated character literal"
        explanation := "This character literal starts with a quote but does not have a closing quote."
        if isEmpty {
            message = "Empty character literal"
            explanation = "A character literal needs exactly one character between the quotes."
        }

        suggestions := new List<string>()
        suggestions.Add("Add the closing quote")
        suggestions.Add("Use double quotes for a string")

        Report(
            ErrorCode.InvalidLiteral,
            message,
            token.Line,
            token.Column,
            explanation,
            "Write a single character like `'a'`, or use a string literal like \"a\" when you need text.",
            suggestions,
            MaxInt(1, token.Value.Length))
    }

    func StartsWithInterpolatedPrefix(value: string): bool {
        if value.Length < 2 {
            return false
        }
        return value[0] == '$' && value[1] == '"'
    }

    // ============================================================================
    // Stage 4: the MEMBER / PARAMETER / FIELD declaration diagnostic family — the `:`/`:=`
    // colon and type-annotation errors — carried through the SAME shared-panic model. The
    // families reached this stage:
    //   * PARAMETERS via `func f(<params>)`  — ConsumeIdentifier + GetMissingParameterNameDiagnosticSpan
    //     (Parser.cs :799/:6476), ConsumeParameterColon (:6625), ParseParameterTypeReference (:6504).
    //   * FIELDS via `class C { … }` / `struct S { … }` — ConsumeIdentifier "Expected field name"
    //     (:1666), ConsumeFieldColon (:6651), ParseFieldTypeReference (:6536) with the
    //     LooksLikeNextFieldAfterMissingType heuristic (:6572).
    //   * the MEMBER-BOUNDARY recovery sync point (ParseMemberList :1365 — panic reset per member).
    //   * the Stage-2-deferred braced-kind found-other name, now reachable for the `{`-offender
    //     variant (`class {` / `struct {`).
    // Diagnostic CONSTRUCTION still delegates to the live shared ParserErrorDiagnostics.Create.
    // ============================================================================

    // ---- parameter list (Parser.cs ParseParameterList :751) ----

    func ParseParameterListRecovery() {
        // Minimal recovery vehicle. Attributes, the params/ref/out/this modifiers, scoped/lifetime
        // annotations, default values, the trailing-comma recovery, and the missing-')'
        // closing-delimiter recovery are LATER arc stages; the member/parameter corpus uses none of
        // them (every corpus parameter list is closed by a present ')').
        if !Check(TokenType.LeftParen) {
            return
        }
        Advance()                               // consume '('

        if !Check(TokenType.RightParen) {
            parsing := true
            while parsing {
                paramLine := Current().Line
                paramColumn := Current().Column
                paramName := ConsumeNameWithSpan("Expected parameter name", GetMissingParameterNameDiagnosticSpan())
                ConsumeParameterColon(paramName, paramLine, paramColumn)
                ParseParameterTypeReference(paramName, paramLine, paramColumn)

                // Parser.cs's `do { … } while (Match(Comma))`.
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    parsing = false
                }
            }
        }

        // Corpus parameter lists are always closed; the missing-')' recovery is a later stage.
        if Check(TokenType.RightParen) {
            Advance()
        }
    }

    // Parser.cs ConsumeIdentifier(message, diagnosticSpan?) overload (:6720). A parameter name is
    // never a dot-access (its previous token is '(' / ',' / a modifier), so isDotAccess is false;
    // the provided span (GetMissingParameterNameDiagnosticSpan) overrides the anchor when present.
    func ConsumeNameWithSpan(message: string, diagnosticSpan: RecoverySpan?): string {
        if Check(TokenType.Identifier) {
            return Advance().Value
        }

        previous := Previous()
        isDotAccess := previous.Type == TokenType.Dot || previous.Type == TokenType.QuestionDot

        if !IsAtEnd() {
            if Lexer.IsReservedKeyword(Current().Type) {
                ReportReservedKeywordAsName(message, diagnosticSpan ?? SpanFromToken(Current()), isDotAccess)
                Advance()
                return "<error>"
            }
        }

        if IsAtEnd() {
            eofSpan := diagnosticSpan ?? LastVisibleTokenSpan()
            Report(
                ErrorCode.UnexpectedEndOfFile,
                message + ", but reached the end of the file",
                eofSpan.Line,
                eofSpan.Column,
                DotOrPlainEofExplanation(isDotAccess),
                DotOrPlainEofHint(isDotAccess),
                null,
                eofSpan.Length)
            return "<error>"
        }

        span := diagnosticSpan ?? SpanFromToken(Current())
        Report(
            ErrorCode.ExpectedToken,
            message + ". Got '" + Current().Value + "'",
            span.Line,
            span.Column,
            DotOrPlainFoundExplanation(isDotAccess, Current().Value),
            DotOrPlainFoundHint(isDotAccess),
            DotAccessFoundSuggestions(isDotAccess),
            span.Length)
        return "<error>"
    }

    // Parser.cs GetMissingParameterNameDiagnosticSpan (:6476): when a `:` (then a type) sits where
    // the parameter name should be, anchor the "expected name" diagnostic on the type token.
    func GetMissingParameterNameDiagnosticSpan(): RecoverySpan? {
        if !Check(TokenType.Colon) {
            return null
        }
        next := LookAhead(1)
        if ParserTokenFacts.IsTypeReferenceStart(next.Type) {
            return SpanFromToken(next)
        }
        return null
    }

    // Parser.cs ConsumeParameterColon (:6625). Anchors the missing-':' diagnostic on the parameter
    // NAME (parameterLine/parameterColumn, length = the name length).
    func ConsumeParameterColon(parameterName: string, parameterLine: int, parameterColumn: int) {
        if Check(TokenType.Colon) {
            Advance()
            return
        }
        if parameterName == "<error>" || parameterLine <= 0 || parameterColumn <= 0 {
            // Generic Consume(':') fallback (Parser.cs :6631). Every '<error>'-name shape has
            // already set panic, so its report would be suppressed; corpus never reaches it.
            return
        }
        nameLength := MaxInt(1, parameterName.Length)
        Report(
            ErrorCode.ExpectedToken,
            "Expected ':' after parameter name. Got '" + Current().Value + "'",
            parameterLine,
            parameterColumn,
            "Parameter '" + parameterName + "' needs a ':' before its type.",
            "Write this parameter as `" + parameterName + ": Type`.",
            SingleSuggestion("Add ':' after '" + parameterName + "'"),
            nameLength)
    }

    // Parser.cs ParseParameterTypeReference (:6504). Consumes a simple type name, or reports the
    // missing-type diagnostic anchored on the parameter name when a type terminator sits where the
    // type should be.
    func ParseParameterTypeReference(parameterName: string, parameterLine: int, parameterColumn: int) {
        if !IsTypeTerminator(Current().Type) {
            ParseSimpleTypeReference()
            return
        }
        visible := IsVisibleName(parameterName)
        span := TypeErrorAnchor(visible, parameterLine, parameterColumn, parameterName)
        explanation := "This parameter needs a type after ':'."
        hint := "Write parameters as `name: Type`."
        if visible {
            explanation = "Parameter '" + parameterName + "' needs a type after ':'."
            hint = "Write this parameter as `" + parameterName + ": Type`."
        }
        Report(
            ErrorCode.ExpectedToken,
            "Expected type name. Got '" + Current().Value + "'",
            span.Line,
            span.Column,
            explanation,
            hint,
            SingleSuggestion("Add a parameter type after ':'"),
            span.Length)
    }

    // ---- braced type body → member list → field family (Parser.cs :1359/:1412/:1637) ----

    // Parse a braced type body far enough to reach the FIELD family. Type parameters, primary-
    // constructor parameters, and base-type lists are LATER arc stages; the member/field corpus
    // types have none, so a valid-named type is immediately followed by '{'. A '<error>'-named type
    // enters the body ONLY when the offending token is '{' — the Stage-2-deferred braced-kind
    // found-other case (`class {` / `struct {`) that the member-list parse now makes reachable;
    // every other '<error>'-name shape keeps the Stage-2 return-early behavior unchanged (the
    // missing-'{' diagnostic for a valid name without a body is the closing-delimiter stage's).
    func ParseTypeBodyIfPresent(name: string) {
        if !Check(TokenType.LeftBrace) {
            return
        }
        Advance()                               // consume '{'
        ParseMemberList()
    }

    // Parser.cs ParseMemberList (:1359): reset panic at each MEMBER boundary (:1365), parse one
    // member, force-advance on no progress (:1379). Stage 4 parses FIELD members only; nested-type /
    // constructor / method / record-positional / union-case member grammars, and the missing-'}'
    // (NL106) end-of-file report, are LATER arc stages (no corpus shape reaches EOF without '}').
    func ParseMemberList() {
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            PanicMode = false                   // reset at each member boundary (Parser.cs :1365)
            SplitGreaterDepth = 0
            startPosition := Position
            ParseFieldMember()

            if Position == startPosition {
                if !IsAtEnd() {
                    Advance()
                }
            }
        }

        if Check(TokenType.RightBrace) {
            Advance()
        }
    }

    // Parser.cs ParseMemberDeclaration (:1412) FIELD/PROPERTY fall-through (:1481) → ParseFieldDeclaration
    // (:1637). Field name errors funnel through the shared no-span ConsumeIdentifier Parser.cs uses at
    // :1666 (a field name is never a dot-access, so its plain message variants apply).
    func ParseFieldMember() {
        line := Current().Line
        column := Current().Column
        name := ConsumeIdentifier("Expected field name")

        // Type inference `Name := value` (Parser.cs :1670): a well-formed inferred field ends the
        // member with no diagnostic. Corpus fields are all explicitly typed.
        if Check(TokenType.ColonAssign) {
            Advance()
            ParseLiteralBearingExpression()
            return
        }

        fieldColonToken := ConsumeFieldColon(name, line, column)
        ParseFieldTypeReference(name, line, column, fieldColonToken)
    }

    // Parser.cs ConsumeFieldColon (:6651). Anchors the missing-':'/':=' diagnostic on the field NAME.
    func ConsumeFieldColon(fieldName: string, fieldLine: int, fieldColumn: int): Token {
        if Check(TokenType.Colon) {
            return Advance()
        }
        if fieldName == "<error>" || fieldLine <= 0 || fieldColumn <= 0 {
            // Generic Consume(':') fallback (Parser.cs :6657); panic-suppressed in the '<error>'
            // cascade, and the synthetic token below is unused. Corpus never reaches it.
            return Current()
        }
        nameLength := MaxInt(1, fieldName.Length)
        Report(
            ErrorCode.ExpectedToken,
            "Expected ':' or ':=' after field name. Got '" + Current().Value + "'",
            fieldLine,
            fieldColumn,
            "Field '" + fieldName + "' needs a ':' before its type, or ':=' before an inferred initializer.",
            "Write this field as `" + fieldName + ": Type` or `" + fieldName + " := value`.",
            FieldColonSuggestions(fieldName),
            nameLength)
        // Parser.cs returns a synthetic ':' token at (fieldLine, fieldColumn + nameLength) (:6675);
        // its only consumer (LooksLikeNextFieldAfterMissingType) compares only the LINE.
        return new Token(TokenType.Colon, ":", fieldLine, fieldColumn + nameLength, FileName)
    }

    // Parser.cs ParseFieldTypeReference (:6536). Consumes a simple type name, or reports the
    // missing-type diagnostic anchored on the field name when a type terminator (and not the start
    // of the NEXT field) sits where the type should be.
    func ParseFieldTypeReference(fieldName: string, fieldLine: int, fieldColumn: int, fieldColonToken: Token) {
        if !IsTypeTerminator(Current().Type) && !LooksLikeNextFieldAfterMissingType(fieldColonToken) {
            ParseSimpleTypeReference()
            return
        }
        visible := IsVisibleName(fieldName)
        span := TypeErrorAnchor(visible, fieldLine, fieldColumn, fieldName)
        explanation := "This field needs a type after ':'."
        hint := "Write fields as `Name: Type`."
        if visible {
            explanation = "Field '" + fieldName + "' needs a type after ':'."
            hint = "Write this field as `" + fieldName + ": Type`."
        }
        Report(
            ErrorCode.ExpectedToken,
            "Expected type name. Got '" + Current().Value + "'",
            span.Line,
            span.Column,
            explanation,
            hint,
            SingleSuggestion("Add a field type after ':'"),
            span.Length)
    }

    // Parser.cs LooksLikeNextFieldAfterMissingType (:6572): a following `Ident (: | :=)` on a LATER
    // line is the next field, not this field's type — so the type parse must not consume it.
    func LooksLikeNextFieldAfterMissingType(fieldColonToken: Token): bool {
        if Current().Line <= fieldColonToken.Line {
            return false
        }
        if !Check(TokenType.Identifier) {
            return false
        }
        nextType := LookAhead(1).Type
        return nextType == TokenType.Colon || nextType == TokenType.ColonAssign
    }

    // ---- shared Stage-4 helpers ----

    func ParseSimpleTypeReference() {
        // Minimal type-reference vehicle: consume a simple identifier type name (e.g. `int`).
        // Generic / array / tuple / qualified type references are a LATER arc stage; the member /
        // parameter corpus uses only simple identifier types.
        if Check(TokenType.Identifier) {
            Advance()
        }
    }

    // The parameter/field type-error anchor (Parser.cs :6509/:6545): the NAME span when the name is
    // visible and positioned, otherwise the current token.
    func TypeErrorAnchor(visible: bool, line: int, column: int, name: string): RecoverySpan {
        if visible && line > 0 && column > 0 {
            return new RecoverySpan(line, column, MaxInt(1, name.Length))
        }
        return SpanFromToken(Current())
    }

    func IsVisibleName(name: string): bool {
        if string.IsNullOrWhiteSpace(name) {
            return false
        }
        return name != "<error>"
    }

    func IsTypeTerminator(t: TokenType): bool {
        if t == TokenType.Comma {
            return true
        }
        if t == TokenType.RightParen {
            return true
        }
        if t == TokenType.RightBracket {
            return true
        }
        if t == TokenType.RightBrace {
            return true
        }
        if t == TokenType.Newline {
            return true
        }
        if t == TokenType.Eof {
            return true
        }
        if t == TokenType.Assign {
            return true
        }
        if t == TokenType.Semicolon {
            return true
        }
        if t == TokenType.Arrow {
            return true
        }
        if t == TokenType.Colon {
            return true
        }
        return false
    }

    func SingleSuggestion(text: string): List<string> {
        suggestions := new List<string>()
        suggestions.Add(text)
        return suggestions
    }

    func FieldColonSuggestions(fieldName: string): List<string> {
        suggestions := new List<string>()
        suggestions.Add("Add ':' after '" + fieldName + "'")
        suggestions.Add("Use ':=' after '" + fieldName + "' if the type should be inferred")
        return suggestions
    }

    func ParseClassName() {
        classToken := Current()
        Advance()
        name := ConsumeDeclarationName("Expected class name", SpanFromToken(classToken))
        // Type parameter list `<T>` (Stage 5, Parser.cs :943) — parsed after the name, before the body,
        // so a malformed `class C<> { }` reports ReportMissingTypeParameterName. A no-op for the
        // non-generic Stage-4 class corpus (Check(Less) is false → returns immediately). Primary-ctor
        // params `(…)` and base lists `: …` are a later arc stage; the Stage-5 class corpus has neither.
        ParseTypeParameters()
        ParseTypeBodyIfPresent(name)
    }

    func ParseStructName() {
        structToken := Current()
        Advance()
        name := ConsumeDeclarationName("Expected struct name", SpanFromToken(structToken))
        ParseTypeParameters()
        ParseTypeBodyIfPresent(name)
    }

    func ParseRecordName() {
        recordToken := Current()
        Advance()
        // `record struct` consumes the contextual `struct` before the name (Parser.cs :1021).
        if Check(TokenType.Struct) {
            Advance()
        }
        ConsumeDeclarationName("Expected record name", SpanFromToken(recordToken))
    }

    func ParseSoaRecordName() {
        Advance()                    // contextual 'soa'
        recordToken := Current()     // the 'record' keyword
        Advance()
        ConsumeDeclarationName("Expected soa record name", SpanFromToken(recordToken))
    }

    func ParseInterfaceName() {
        if Check(TokenType.Duck) {
            Advance()                // contextual 'duck'
        }
        interfaceToken := Current()  // the 'interface' keyword
        Advance()
        ConsumeDeclarationName("Expected interface name", SpanFromToken(interfaceToken))
    }

    func ParseUnionName() {
        unionToken := Current()
        Advance()
        ConsumeDeclarationName("Expected union name", SpanFromToken(unionToken))
    }

    func ParseEnumName() {
        enumToken := Current()
        Advance()
        ConsumeDeclarationName("Expected enum name", SpanFromToken(enumToken))
    }

    func ParseTypeAliasName() {
        typeToken := Current()
        Advance()
        // Parser.cs anchors with new DiagnosticSpan(line, column, Math.Max(1, "type".Length))
        // (:1337); with the keyword value "type" that equals SpanFromToken(typeToken).
        ConsumeDeclarationName("Expected type alias name", new RecoverySpan(typeToken.Line, typeToken.Column, MaxInt(1, 4)))
    }

    // ============================================================================
    // Stage 5: the GENERICS / CONSTRAINTS diagnostic family — carried through the SAME shared-panic
    // model. The families reached this stage (all via the function head + class type-params):
    //   * TYPE PARAMETER names via `<…>` — ReportMissingTypeParameterName (Parser.cs :6439, empty
    //     `<>` / trailing-comma `<T,>`) and the reserved-keyword type-param name (ConsumeIdentifier
    //     reserved variant, Parser.cs :743).
    //   * GENERIC TYPE ARGUMENTS via a generic type reference `Name<…>` — ReportMissingGenericTypeArgument
    //     (:6457, empty / trailing-comma), reached through the function RETURN TYPE.
    //   * the ConsumeGreater split-`>>` discipline (:2101) — the `>>`-split mechanism (so a well-formed
    //     nested generic `List<List<int>>` reports NOTHING) + the "Expected '>'. Got 'X'" ExpectedToken
    //     error when a type-argument list is left unclosed.
    //   * the `where`-clause constraint errors (ParseGenericConstraints :851) — the "Expected type
    //     parameter" name error, the missing-`:` Consume error, and the class/struct mutual-exclusion
    //     and struct/new() redundancy InvalidSyntax validations.
    // Diagnostic CONSTRUCTION still delegates to the live shared ParserErrorDiagnostics.Create, and the
    // constraint DECISIONS mirror Parser.cs exactly, so codes / messages / spans / snippets / hints match.
    // ============================================================================

    // ---- type parameter list (Parser.cs ParseTypeParameters :725) ----

    func ParseTypeParameters() {
        if !Check(TokenType.Less) {
            return
        }
        lessToken := Advance()                  // consume '<'
        parsing := true
        while parsing {
            if Check(TokenType.Greater) {
                // `<>` (empty) or `<T,>` (trailing comma): the name is missing (Parser.cs :735-738).
                ReportMissingTypeParameterName(lessToken)
                parsing = false
            } else {
                // A lifetime `'a` or an identifier type-parameter name (Parser.cs :741-743).
                if Check(TokenType.Lifetime) {
                    Advance()
                } else {
                    ConsumeIdentifier("Expected type parameter name")
                }
                // Parser.cs's `do { … } while (Match(Comma))`.
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    parsing = false
                }
            }
        }
        // Parser.cs closes the type-parameter list with the generic Consume(Greater) (:747), NOT the
        // split-aware ConsumeGreater — so its unclosed-list message uses TokenTypeToString(Greater)
        // ("greater"). Every Stage-5 corpus type-parameter list is closed by a present `>`.
        ConsumeToken(TokenType.Greater, "Expected '>'", "greater")
    }

    // Parser.cs ReportMissingTypeParameterName (:6439). The span runs from the opening `<` to the
    // offending token (DiagnosticSpanFromTokenRange), so it underlines the whole `<>` / `<T,>`.
    func ReportMissingTypeParameterName(lessToken: Token) {
        span := DiagnosticSpanFromTokenRange(lessToken, Current())
        suggestions := new List<string>()
        suggestions.Add("Add a type parameter name")
        suggestions.Add("Remove the trailing comma if the list is complete")
        Report(
            ErrorCode.ExpectedToken,
            "Expected type parameter name. Got '" + Current().Value + "'",
            span.Line,
            span.Column,
            "Generic parameter lists need a type parameter name after each comma.",
            "Write generic parameters as `<T>` or `<T, U>`.",
            suggestions,
            span.Length)
    }

    // ---- generic-aware type reference (Parser.cs ParseTypeReference simple/generic subset :1910-1962) ----
    // Consumes a simple or qualified type name plus an optional `<typeargs>` list, reporting the
    // generic-type-argument and ConsumeGreater diagnostics. The byref `&` / tuple `(` / Func<> / array /
    // nullable forms are a later arc stage; the Stage-5 corpus's return and constraint types are all
    // simple names or generic references over simple names.
    func ParseTypeReferenceRecovery() {
        typeNameToken := Current()
        ConsumeIdentifier("Expected type name")             // Parser.cs :1914
        while Check(TokenType.Dot) {                         // qualified name A.B (Parser.cs :1918)
            Advance()
            ConsumeIdentifier("Expected identifier after '.'")
        }

        if Check(TokenType.Less) {
            lessToken := Advance()                          // consume '<'
            if Check(TokenType.Greater) {
                ReportMissingGenericTypeArgument(typeNameToken, lessToken)  // `Name<>` (Parser.cs :1930)
            } else {
                ParseTypeReferenceRecovery()                // first type argument
                scanning := true
                while scanning {
                    if Check(TokenType.Comma) {
                        Advance()
                        if Check(TokenType.Greater) {
                            // `Name<T,>` trailing comma (Parser.cs :1940-1943).
                            ReportMissingGenericTypeArgument(typeNameToken, lessToken)
                            scanning = false
                        } else {
                            ParseTypeReferenceRecovery()
                        }
                    } else {
                        scanning = false
                    }
                }
            }
            ConsumeGreater("Expected '>'")                  // Parser.cs :1950
        }
    }

    // Parser.cs ReportMissingGenericTypeArgument (:6457). The span runs from the type name to the
    // offending token; the message names the type and its opening `<`.
    func ReportMissingGenericTypeArgument(typeNameToken: Token, lessToken: Token) {
        span := DiagnosticSpanFromTokenRange(typeNameToken, Current())
        typeName := typeNameToken.Value
        suggestions := new List<string>()
        suggestions.Add("Add a type argument")
        suggestions.Add("Remove the empty generic argument list")
        Report(
            ErrorCode.ExpectedToken,
            "Expected type name. Got '" + Current().Value + "'",
            span.Line,
            span.Column,
            "Generic type '" + typeName + "' needs a type argument between '" + lessToken.Value + "' and '>'.",
            "Write this type as `" + typeName + "<T>` or remove the generic argument list.",
            suggestions,
            span.Length)
    }

    // ---- ConsumeGreater (Parser.cs :2101) — closes a type-ARGUMENT list, splitting `>>` ----
    func ConsumeGreater(message: string): Token {
        if Check(TokenType.Greater) {
            return Advance()
        }
        if Check(TokenType.RightShift) {
            // Split `>>` into two `>` by consuming the `>>` and recording that we owe one `>`
            // (Parser.cs :2107-2119); Check/Advance honor the debt on the enclosing generic's close.
            rightShift := Current()
            Position = Position + 1
            SplitGreaterDepth = SplitGreaterDepth + 1
            return new Token(TokenType.Greater, ">", rightShift.Line, rightShift.Column, rightShift.FileName)
        }
        suggestions := new List<string>()
        suggestions.Add("Check if you have matching '<' and '>' in your generic type declaration")
        suggestions.Add("Example: List<int> or Dictionary<string, int>")
        Report(
            ErrorCode.ExpectedToken,
            message + ". Got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "I was parsing generic type parameters and expected to see a closing '>' here.",
            GetHintForMissingToken(TokenType.Greater),
            suggestions,
            Current().Value.Length)
        return Current()
    }

    // ---- generic Consume (Parser.cs Consume :6048), for the type-parameter `>` close and constraint `:` ----
    // The RightParen/RightBracket TryReportMissingClosingDelimiter branch (:6052) is a later
    // closing-delimiter arc stage; the Stage-5 corpus never reaches an unclosed `)` / `]` here.
    func ConsumeToken(tokenType: TokenType, message: string, expected: string): Token {
        if Check(tokenType) {
            return Advance()
        }
        if IsAtEnd() {
            ownerSpan := LastVisibleTokenSpan()
            Report(
                ErrorCode.UnexpectedEndOfFile,
                "Expected '" + expected + "' but reached the end of the file",
                ownerSpan.Line,
                ownerSpan.Column,
                "I was expecting '" + expected + "' here, but the file ended first.",
                HintForMissingTokenOrDefault(tokenType, "Finish this construct before the end of the file."),
                null,
                ownerSpan.Length)
            return Current()
        }
        Report(
            ErrorCode.ExpectedToken,
            message + ". Expected '" + expected + "', got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "I was expecting " + expected + " here, but I found '" + Current().Value + "' instead.",
            GetHintForMissingToken(tokenType),
            null,
            Current().Value.Length)
        return Current()
    }

    // Parser.cs GetHintForMissingToken (:6345): null for `>` and `:` (only the closing-delimiter and
    // semicolon tokens carry a hint, which the Stage-5 corpus does not exercise here).
    func GetHintForMissingToken(tokenType: TokenType): string? {
        return null
    }

    func HintForMissingTokenOrDefault(tokenType: TokenType, fallback: string): string {
        hint := GetHintForMissingToken(tokenType)
        if hint == null {
            return fallback
        }
        return hint ?? fallback
    }

    // ---- generic constraints (Parser.cs ParseGenericConstraints :851) ----
    func ParseGenericConstraints() {
        if !Check(TokenType.Where) {
            return
        }
        while Check(TokenType.Where) {
            Advance()                                       // consume 'where'
            ConsumeIdentifier("Expected type parameter")    // Parser.cs :861
            ConsumeToken(TokenType.Colon, "Expected ':'", ":")  // Parser.cs :862

            classToken: Token? = null
            structToken: Token? = null
            newStartToken: Token? = null
            newEndToken: Token? = null
            hasClass := false
            hasStruct := false
            hasNew := false

            parsing := true
            while parsing {
                if Check(TokenType.Class) {
                    classToken = Current()
                    Advance()
                    hasClass = true
                } else {
                    if Check(TokenType.Struct) {
                        structToken = Current()
                        Advance()
                        hasStruct = true
                    } else {
                        if Check(TokenType.New) && LookAhead(1).Type == TokenType.LeftParen {
                            newStartToken = Current()
                            Advance()                       // consume 'new'
                            Advance()                       // consume '('
                            newEndToken = ConsumeToken(TokenType.RightParen, "Expected ')' after 'new('", ")")
                            hasNew = true
                        } else {
                            ParseTypeReferenceRecovery()    // Parser.cs :892
                        }
                    }
                }
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    parsing = false
                }
            }

            // Validate: class and struct are mutually exclusive (Parser.cs :897-909).
            if hasClass {
                if hasStruct {
                    ReportClassStructConflict(LaterToken(classToken, structToken))
                }
            }
            // Validate: struct implies new(), so combining them is redundant (Parser.cs :912-923).
            if hasStruct {
                if hasNew {
                    ReportStructNewRedundancy(newStartToken, newEndToken)
                }
            }
        }
    }

    func ReportClassStructConflict(diagnosticToken: Token?) {
        line := Current().Line
        column := Current().Column
        length := 1
        if diagnosticToken != null {
            resolved := diagnosticToken ?? Current()
            line = resolved.Line
            column = resolved.Column
        }
        length = TokenLengthOrFallback(diagnosticToken)
        Report(
            ErrorCode.InvalidSyntax,
            "Cannot have both 'class' and 'struct' constraints on the same type parameter — they are mutually exclusive",
            line,
            column,
            "A type parameter cannot be both a reference type (class) and a value type (struct) at the same time.",
            null,
            null,
            length)
    }

    func ReportStructNewRedundancy(newStartToken: Token?, newEndToken: Token?) {
        line := Current().Line
        column := Current().Column
        if newStartToken != null {
            resolved := newStartToken ?? Current()
            line = resolved.Line
            column = resolved.Column
        }
        Report(
            ErrorCode.InvalidSyntax,
            "Cannot combine 'struct' and 'new()' constraints — 'struct' already implies a parameterless constructor",
            line,
            column,
            "The 'struct' constraint already requires a parameterless constructor, so 'new()' is redundant and not permitted in .",
            null,
            null,
            TokenSpanLengthOrFallback(newStartToken, newEndToken))
    }

    // Parser.cs LaterToken (:6010): the token later in source order (higher line, or equal line and
    // column >= the other), with null operands passing through.
    func LaterToken(left: Token?, right: Token?): Token? {
        if left == null {
            return right
        }
        if right == null {
            return left
        }
        r := right ?? left
        l := left ?? right
        if r.Line > l.Line {
            return right
        }
        if r.Line == l.Line {
            if r.Column >= l.Column {
                return right
            }
        }
        return left
    }

    // Parser.cs TokenLengthOrFallback (:5897) / TokenSpanLengthOrFallback (:5900) /
    // DiagnosticSpanFromTokenRange (:5914).
    func TokenLengthOrFallback(token: Token?): int {
        if token == null {
            return 1
        }
        resolved := token ?? Current()
        return MaxInt(1, resolved.Value.Length)
    }

    func TokenSpanLengthOrFallback(start: Token?, end: Token?): int {
        if start == null {
            return 1
        }
        s := start ?? Current()
        if end == null {
            return TokenLengthOrFallback(start)
        }
        e := end ?? Current()
        if e.Line != s.Line {
            return TokenLengthOrFallback(start)
        }
        return MaxInt(1, e.Column + TokenLengthOrFallback(end) - s.Column)
    }

    func DiagnosticSpanFromTokenRange(start: Token, end: Token): RecoverySpan {
        return new RecoverySpan(start.Line, start.Column, TokenSpanLengthOrFallback(start, end))
    }

    func MaxInt(a: int, b: int): int {
        if a > b {
            return a
        }
        return b
    }

    func MinInt(a: int, b: int): int {
        if a < b {
            return a
        }
        return b
    }
}

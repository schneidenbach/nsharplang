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

// Stage 6: the diagnostic-relevant result of parsing a statement expression. The recovery
// model builds no AST, so instead of an Expression node this carries only what the statement
// diagnostics need: the expression's DiagnosticSpanFromToken-equivalent span (used to anchor a
// shorthand `:=` initializer error and a binary/assignment missing-operand error) and whether
// the expression was a bare identifier (used to decide the `identifier :=` shorthand-declaration
// path, exactly as Parser.cs's `expr is IdentifierExpression`). A local reference type rather
// than a value struct.
public class ExprResult {
    Span: RecoverySpan
    IsBareIdentifier: bool

    constructor(span: RecoverySpan, isBareIdentifier: bool) {
        Span = span
        IsBareIdentifier = isBareIdentifier
    }
}

// Stage 9: the outcome of TryReportMissingClosingDelimiter (Parser.cs :6103, whose C# signature
// is `bool Try…(out Token recoveredToken)`). N# has no reference-typed out args, so the shared
// result is carried in an explicit result object (the established recovery-owner precedent):
// Handled mirrors the bool return (the closing-delimiter recovery path was taken — a diagnostic
// was reported subject to the shared panic, and a synthetic closing token stands in), and
// RecoveredToken mirrors the out parameter (the synthesized `)` / `]` the caller returns).
public class ClosingDelimiterRecovery {
    Handled: bool
    RecoveredToken: Token

    constructor(handled: bool, recoveredToken: Token) {
        Handled = handled
        RecoveredToken = recoveredToken
    }
}

// Stage 9: the outcome of TryFindUnmatchedOpeningDelimiter (Parser.cs :6194) and
// TryGetPreviousTokenOnLine (Parser.cs :6290) — both `bool Try…(out Token token)`. Carried as an
// explicit result object for the same reason. When Found is false the Token field carries the
// Parser.cs fallback (the `previous` token) so callers can read it uniformly.
public class TokenLookupResult {
    Found: bool
    Token: Token

    constructor(found: bool, token: Token) {
        Found = found
        Token = token
    }
}

// Stage 9: the outcome of TryGetDelimiterOwnerSpan (Parser.cs :6237, `bool Try…(out (int,int,int) span)`).
public class OwnerSpanResult {
    Found: bool
    Span: RecoverySpan

    constructor(found: bool, span: RecoverySpan) {
        Found = found
        Span = span
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
    // Stage 6: the current statement's recovery-boundary column (Parser.cs `_currentRecoveryBoundaryColumn`,
    // an int?). Set to the starting column of each block statement (Parser.cs ParseBlock :2177) and consulted
    // by IsMissingOperandBoundary so a following token at or left of the statement's column is treated as the
    // start of a new statement (the dangling-operator "does not swallow the following statement" behaviour).
    // Modelled as an int + presence flag rather than int? to keep the comparison arithmetic simple.
    RecoveryBoundaryColumn: int
    HasRecoveryBoundaryColumn: bool
    // Stage 10: scan-state for the IsCastExpression bounded lookahead (Parser.cs :5573 uses nested closures
    // over local `position` / `splitGreaterDepth`; N# has no first-class Func values, so the scan is lowered
    // to methods over these two fields). They are transient — set at the start of each IsCastExpression call
    // and never read outside the scan — so they never interact with the real parser cursor.
    ScanPosition: int
    ScanSplit: int
    Errors: List<CompilerError>

    constructor(source: string, fileName: string?) {
        Source = source
        FileName = fileName
        Position = 0
        PanicMode = false
        SplitGreaterDepth = 0
        RecoveryBoundaryColumn = 0
        HasRecoveryBoundaryColumn = false
        ScanPosition = 0
        ScanSplit = 0
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
        nameToken := Current()          // capture the name token BEFORE it is consumed (Parser.cs :433)
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
        //
        // Stage 6: the block-body owner span is the function-name span (Parser.cs's
        // returnTypeDiagnostic{Line,Column,Length} default, :438-441), used only for the block's
        // own missing-'}' report.
        ownerSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        ParseFunctionHeadAndBody(ownerSpan)
    }

    // Parse the tail of a validly-named function far enough to reach an expression body, so the
    // malformed-LITERAL family (Stage 3) can be exercised through the shared-panic model. This is
    // the MINIMAL literal-reaching vehicle — the malformed-literal corpus uses `func f() => <lit>`
    // (the shallowest byte-exact literal context). General parameter/generic/return-type parsing
    // and the block-body statement grammar are LATER arc stages; here the head is only consumed
    // enough to reach `=> <expr>` for the empty-parameter, expression-bodied shape.
    func ParseFunctionHeadAndBody(ownerSpan: RecoverySpan) {
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

        // Function body (Parser.cs :493-501): an expression body `=> <expr>` (Stage 3 vehicle) or,
        // Stage 6, a real block body `{ <statements> }`.
        if Check(TokenType.Arrow) {
            Advance()
            ParseLiteralBearingExpression()
            return
        }
        if Check(TokenType.LeftBrace) {
            ParseBlockBody(ownerSpan)
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
        // annotations, default values, and the IsParameterListRecoveryBoundary early break are LATER arc
        // stages; the member/parameter corpus uses none of them. Stage 9 carries the trailing-comma
        // recovery (Parser.cs :761) and routes the closing ')' through ConsumeToken so the missing-')'
        // closing-delimiter recovery (NL107) is reachable.
        if !Check(TokenType.LeftParen) {
            return
        }
        Advance()                               // consume '('

        if !Check(TokenType.RightParen) {
            // The start token of the last SUCCESSFULLY-parsed parameter, for the trailing-comma span
            // (Parser.cs `lastParameterStartToken`, :755/:814).
            lastParameterStartToken: Token? = null
            parsing := true
            while parsing {
                // Trailing comma before ')' (Parser.cs :761): `f(a,)` reports "Expected parameter name"
                // spanning the last parameter through the comma, then stops.
                if Check(TokenType.RightParen) && Previous().Type == TokenType.Comma && lastParameterStartToken != null {
                    startToken := lastParameterStartToken ?? Current()
                    ReportMissingParameterAfterTrailingComma(DiagnosticSpanFromTokenRange(startToken, Previous()))
                    parsing = false
                } else {
                    paramStartToken := Current()
                    paramLine := Current().Line
                    paramColumn := Current().Column
                    paramName := ConsumeNameWithSpan("Expected parameter name", GetMissingParameterNameDiagnosticSpan())
                    ConsumeParameterColon(paramName, paramLine, paramColumn)
                    ParseParameterTypeReference(paramName, paramLine, paramColumn)

                    if paramName != "<error>" {
                        lastParameterStartToken = paramStartToken
                    }

                    // Parser.cs's `do { … } while (Match(Comma))`.
                    if Check(TokenType.Comma) {
                        Advance()
                    } else {
                        parsing = false
                    }
                }
            }
        }

        // Parser.cs Consume(RightParen) (:819): a present ')' advances; a missing one routes through the
        // Stage-9 closing-delimiter recovery (NL107) or the standard ExpectedToken path.
        ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
    }

    // Parser.cs ReportMissingParameterAfterTrailingComma (:6487).
    func ReportMissingParameterAfterTrailingComma(span: RecoverySpan) {
        suggestions := new List<string>()
        suggestions.Add("Add a parameter after the comma")
        suggestions.Add("Remove the trailing comma")
        Report(
            ErrorCode.ExpectedToken,
            "Expected parameter name. Got '" + Current().Value + "'",
            span.Line,
            span.Column,
            "Parameter lists need another parameter after a comma.",
            "Add the missing parameter after the comma, or remove the trailing comma.",
            suggestions,
            span.Length)
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
    func ParseTypeBodyIfPresent(name: string, typeBodyDiagnosticSpan: RecoverySpan) {
        if !Check(TokenType.LeftBrace) {
            return
        }
        Advance()                               // consume '{'
        ParseMemberList(typeBodyDiagnosticSpan)
    }

    // Parser.cs ParseMemberList (:1359): reset panic at each MEMBER boundary (:1365), parse one
    // member, force-advance on no progress (:1379). Stage 4 parses FIELD members only; nested-type /
    // constructor / method / record-positional / union-case member grammars are LATER arc stages.
    // Stage 9 carries the type-body end-of-file missing-'}' (NL106) report (:1396), anchored on the
    // type-body diagnostic span (the type name, or the declaration keyword for a '<error>' name).
    func ParseMemberList(ownerSpan: RecoverySpan?) {
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
        } else {
            if IsAtEnd() {
                if ownerSpan != null {
                    span := ownerSpan ?? new RecoverySpan(1, 1, 1)
                    Report(
                        ErrorCode.MissingClosingBrace,
                        "Missing closing '}'",
                        span.Line,
                        span.Column,
                        "The type body that started on line " + IntToString(span.Line) + " is missing its closing brace. I reached the end of the file without finding it.",
                        "Add a '}' to close this type declaration.",
                        null,
                        span.Length)
                }
            }
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
        nameToken := Current()          // capture the name position BEFORE it is consumed (Parser.cs :937)
        name := ConsumeDeclarationName("Expected class name", SpanFromToken(classToken))
        // The type-body missing-'}' diagnostic (Stage 9) anchors on the name, or the declaration keyword
        // for a '<error>' name (Parser.cs :940-942, "class".Length == 5).
        typeBodyDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            typeBodyDiagnosticSpan = new RecoverySpan(classToken.Line, classToken.Column, MaxInt(1, 5))
        }
        // Type parameter list `<T>` (Stage 5, Parser.cs :943) — parsed after the name, before the body,
        // so a malformed `class C<> { }` reports ReportMissingTypeParameterName. A no-op for the
        // non-generic Stage-4 class corpus (Check(Less) is false → returns immediately). Primary-ctor
        // params `(…)` and base lists `: …` are a later arc stage; the Stage-5 class corpus has neither.
        ParseTypeParameters()
        ParseTypeBodyIfPresent(name, typeBodyDiagnosticSpan)
    }

    func ParseStructName() {
        structToken := Current()
        Advance()
        nameToken := Current()          // capture the name position BEFORE it is consumed (Parser.cs :982)
        name := ConsumeDeclarationName("Expected struct name", SpanFromToken(structToken))
        // Parser.cs :985-987 ("struct".Length == 6).
        typeBodyDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            typeBodyDiagnosticSpan = new RecoverySpan(structToken.Line, structToken.Column, MaxInt(1, 6))
        }
        ParseTypeParameters()
        ParseTypeBodyIfPresent(name, typeBodyDiagnosticSpan)
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

    // ---- generic Consume (Parser.cs Consume :6048) ----
    // Stage 9: the closing-delimiter recovery branch (Parser.cs :6052) fires FIRST when the awaited
    // token is a `)` or `]` that is missing at a line/same-line boundary — it reports NL107/NL108 and
    // returns a synthetic closing token so parsing continues past the unclosed construct (the `new(`
    // constraint, the list `]` / positional `)` pattern closes, and any call/index close route here).
    // For every other token, and for a `)`/`]` whose boundary test declines (the offender sits on the
    // same line and is not a same-line boundary token), it falls through to the standard EOF /
    // ExpectedToken path below, exactly as Parser.cs's Consume does.
    func ConsumeToken(tokenType: TokenType, message: string, expected: string): Token {
        if Check(tokenType) {
            return Advance()
        }
        recovery := TryReportMissingClosingDelimiter(tokenType)
        if recovery.Handled {
            return recovery.RecoveredToken
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

    // Parser.cs GetHintForMissingToken (:6345): the closing-delimiter and semicolon tokens carry a hint;
    // every other token (including `>` and `:`) returns null. Stage 8 reaches the RightBrace hint through
    // the match / property-pattern `Consume(RightBrace)` sites — RightBrace is NOT in
    // TryReportMissingClosingDelimiter, so it takes the standard Consume path that consults this hint.
    func GetHintForMissingToken(tokenType: TokenType): string? {
        if tokenType == TokenType.RightParen {
            return "Every opening parenthesis '(' needs a matching closing parenthesis ')'."
        }
        if tokenType == TokenType.RightBrace {
            return "Every opening brace '{' needs a matching closing brace '}'."
        }
        if tokenType == TokenType.RightBracket {
            return "Every opening bracket '[' needs a matching closing bracket ']'."
        }
        if tokenType == TokenType.Semicolon {
            return "Statements can end with a semicolon, though it's optional in N#."
        }
        return null
    }

    func HintForMissingTokenOrDefault(tokenType: TokenType, fallback: string): string {
        hint := GetHintForMissingToken(tokenType)
        if hint == null {
            return fallback
        }
        return hint ?? fallback
    }

    // ============================================================================
    // Stage 9: the CLOSING-DELIMITER recovery family — carried through the SAME shared-panic model.
    // Parser.cs's Consume (:6048) tries this recovery FIRST for a missing `)` / `]`: instead of the
    // plain ExpectedToken diagnostic, it reports the position-aware NL107 (`Missing closing ')'`) /
    // NL108 (`Missing closing ']'`) and returns a SYNTHETIC closing token so the parser can continue
    // past the unclosed construct (Parser.cs TryReportMissingClosingDelimiter :6103). Two triggers:
    //   * we crossed onto a LATER line (or reached EOF) while awaiting the close → the diagnostic is
    //     anchored on the unmatched opening delimiter's OWNER token (the identifier / keyword that owns
    //     it, or the assigned name), falling back to the opening delimiter itself, and the human text
    //     reads "I reached the next line …".
    //   * a same-line BOUNDARY token sits where the close should be (`{`/`}`/`]`/`:`/`=>`/`;` for `)`,
    //     `}`/`)`/`;` for `]`) → the diagnostic is anchored on that offender and reads "I found 'X' …".
    // A `)`/`]` whose offender is mid-line (not a boundary) is NOT recovered here — it falls through to
    // the standard ExpectedToken path (byte-exact with the `new(, IFoo` shape). RightBrace is NEVER
    // handled here (Parser.cs :6119 declines it); the missing-'}' NL106 is reported directly at the
    // block / type-body ends below. DECISIONS + CONSTRUCTION reuse the same primitives Parser.cs uses,
    // so codes / messages / spans / snippets / hints / suggestions match automatically.
    // ============================================================================

    // Parser.cs TryReportMissingClosingDelimiter (:6103). Returns Handled=true (with a synthetic close)
    // whenever the recovery path is taken — the diagnostic itself is still subject to the shared panic.
    func TryReportMissingClosingDelimiter(tokenType: TokenType): ClosingDelimiterRecovery {
        // Only `)` and `]` route here (Parser.cs :6107-6120: `code == default` declines every other
        // token, RightBrace included).
        if tokenType != TokenType.RightParen && tokenType != TokenType.RightBracket {
            return new ClosingDelimiterRecovery(false, Current())
        }

        expected := "]"
        opening := "["
        code := ErrorCode.MissingClosingBracket
        hint := "Every opening bracket '[' needs a matching closing bracket ']'."
        if tokenType == TokenType.RightParen {
            expected = ")"
            opening = "("
            code = ErrorCode.MissingClosingParen
            hint = "Every opening parenthesis '(' needs a matching closing parenthesis ')'."
        }

        previous := Previous()
        if previous.Type == TokenType.Eof {
            return new ClosingDelimiterRecovery(false, Current())
        }

        // A same-line boundary token stands in for the missing close (Parser.cs :6129-6131).
        sameLineBoundary := false
        if Current().Type != TokenType.Eof {
            if Current().Line == previous.Line {
                if IsSameLineMissingClosingDelimiterBoundary(tokenType) {
                    sameLineBoundary = true
                }
            }
        }

        // Recover only when we crossed a line (or reached EOF) or hit a same-line boundary; a mid-line
        // offender takes the standard ExpectedToken path (Parser.cs :6133-6134).
        if Current().Type != TokenType.Eof {
            if Current().Line <= previous.Line {
                if !sameLineBoundary {
                    return new ClosingDelimiterRecovery(false, Current())
                }
            }
        }

        previousLength := MaxInt(1, previous.Value.Length)
        insertionLine := previous.Line
        insertionColumn := previous.Column + previousLength
        if sameLineBoundary {
            insertionLine = Current().Line
            insertionColumn = Current().Column
        }

        span := GetMissingClosingDelimiterDiagnosticSpan(tokenType, previous, sameLineBoundary)

        // The human explanation + the primary suggestion vary by whether we found a same-line offender
        // (Parser.cs :6148-6156).
        explanation := "I reached the next line while looking for the closing '" + expected + "' that matches an earlier '" + opening + "'."
        primarySuggestion := "Add '" + expected + "' before starting the next line"
        if sameLineBoundary {
            found := Current().Value
            explanation = "I found '" + found + "' while looking for the closing '" + expected + "' that matches an earlier '" + opening + "'."
            primarySuggestion = "Add '" + expected + "' before '" + found + "'"
        }

        suggestions := new List<string>()
        suggestions.Add(primarySuggestion)
        suggestions.Add("Check the matching '" + opening + "' in this expression")

        Report(
            code,
            "Missing closing '" + expected + "'",
            span.Line,
            span.Column,
            explanation,
            hint,
            suggestions,
            span.Length)

        recovered := new Token(tokenType, expected, insertionLine, insertionColumn, previous.FileName)
        return new ClosingDelimiterRecovery(true, recovered)
    }

    // Parser.cs GetMissingClosingDelimiterDiagnosticSpan (:6164): the same-line offender's own span, or
    // the unmatched opening delimiter's OWNER span (falling back to the opening delimiter itself), or a
    // one-column span just past the previous token when no opening delimiter is found.
    func GetMissingClosingDelimiterDiagnosticSpan(expectedClosingType: TokenType, previous: Token, sameLineBoundary: bool): RecoverySpan {
        if sameLineBoundary {
            return new RecoverySpan(Current().Line, Current().Column, MaxInt(1, Current().Value.Length))
        }

        if expectedClosingType == TokenType.RightParen {
            opening := TryFindUnmatchedOpeningDelimiter(TokenType.LeftParen, TokenType.RightParen, previous)
            if opening.Found {
                owner := TryGetDelimiterOwnerSpan(opening.Token)
                if owner.Found {
                    return owner.Span
                }
                return new RecoverySpan(opening.Token.Line, opening.Token.Column, MaxInt(1, opening.Token.Value.Length))
            }
        }

        if expectedClosingType == TokenType.RightBracket {
            bracket := TryFindUnmatchedOpeningDelimiter(TokenType.LeftBracket, TokenType.RightBracket, previous)
            if bracket.Found {
                owner := TryGetDelimiterOwnerSpan(bracket.Token)
                if owner.Found {
                    return owner.Span
                }
                return new RecoverySpan(bracket.Token.Line, bracket.Token.Column, MaxInt(1, bracket.Token.Value.Length))
            }
        }

        fallbackLength := MaxInt(1, previous.Value.Length)
        return new RecoverySpan(previous.Line, previous.Column + fallbackLength, 1)
    }

    // Parser.cs TryFindUnmatchedOpeningDelimiter (:6194): scan backward (skipping anything positioned
    // after `previous`) for the opening delimiter whose matching close is missing, tracking nesting depth.
    func TryFindUnmatchedOpeningDelimiter(openingType: TokenType, closingType: TokenType, previous: Token): TokenLookupResult {
        depth := 0
        previousEndColumn := previous.Column + MaxInt(1, previous.Value.Length)
        index := MinInt(Position - 1, Tokens.Count - 1)
        result := new TokenLookupResult(false, previous)
        searching := true
        while searching {
            if index < 0 {
                searching = false
            } else {
                token := Tokens[index]
                consider := true
                if token.Type == TokenType.Eof {
                    consider = false
                }
                if consider {
                    if token.Line > previous.Line {
                        consider = false
                    } else {
                        if token.Line == previous.Line {
                            if token.Column > previousEndColumn {
                                consider = false
                            }
                        }
                    }
                }
                if consider {
                    if token.Type == closingType {
                        depth = depth + 1
                    } else {
                        if token.Type == openingType {
                            if depth == 0 {
                                result = new TokenLookupResult(true, token)
                                searching = false
                            } else {
                                depth = depth - 1
                            }
                        }
                    }
                }
                index = index - 1
            }
        }
        return result
    }

    // Parser.cs TryGetDelimiterOwnerSpan (:6237): anchor on the visible token that owns the opening
    // delimiter (the identifier / keyword immediately before it, or — through an `=`/`:=` — the assigned
    // name). Returns not-found when no such owner sits on the delimiter's line.
    func TryGetDelimiterOwnerSpan(openingToken: Token): OwnerSpanResult {
        tokenIndex := FindTokenIndex(openingToken)
        if tokenIndex > 0 {
            owner := Tokens[tokenIndex - 1]
            if owner.Line == openingToken.Line {
                if IsVisibleDelimiterOwner(owner) {
                    return new OwnerSpanResult(true, new RecoverySpan(owner.Line, owner.Column, MaxInt(1, owner.Value.Length)))
                }
                if IsAssignmentAnchor(owner) {
                    assignedName := TryGetPreviousTokenOnLine(tokenIndex - 1, owner.Line)
                    if assignedName.Found {
                        if IsVisibleDelimiterOwner(assignedName.Token) {
                            return new OwnerSpanResult(true, new RecoverySpan(assignedName.Token.Line, assignedName.Token.Column, MaxInt(1, assignedName.Token.Value.Length)))
                        }
                    }
                }
            }
        }
        return new OwnerSpanResult(false, new RecoverySpan(1, 1, 1))
    }

    // Parser.cs's `_tokens.FindIndex(...)` (:6239): the first token matching the opening delimiter's
    // line / column / type / value. The compacted stream carries no duplicate positions, so this is exact.
    func FindTokenIndex(target: Token): int {
        i := 0
        while i < Tokens.Count {
            t := Tokens[i]
            if t.Line == target.Line {
                if t.Column == target.Column {
                    if t.Type == target.Type {
                        if t.Value == target.Value {
                            return i
                        }
                    }
                }
            }
            i = i + 1
        }
        return -1
    }

    // Parser.cs IsVisibleDelimiterOwner (:6268): an identifier or one of the statement/declaration
    // keywords that legitimately own a `(` / `[` (so a missing close underlines the construct's name).
    func IsVisibleDelimiterOwner(token: Token): bool {
        if token.Type == TokenType.Identifier {
            return true
        }
        return token.Type == TokenType.Print || token.Type == TokenType.If || token.Type == TokenType.Case || token.Type == TokenType.Default || token.Type == TokenType.While || token.Type == TokenType.For || token.Type == TokenType.Foreach || token.Type == TokenType.Switch || token.Type == TokenType.Lock || token.Type == TokenType.Using || token.Type == TokenType.Assert || token.Type == TokenType.Return || token.Type == TokenType.Yield || token.Type == TokenType.Throw || token.Type == TokenType.Func || token.Type == TokenType.Test
    }

    // Parser.cs IsAssignmentAnchor (:6287).
    func IsAssignmentAnchor(token: Token): bool {
        return token.Type == TokenType.Assign || token.Type == TokenType.ColonAssign
    }

    // Parser.cs TryGetPreviousTokenOnLine (:6290): the closest non-EOF token before `beforeIndex` still
    // on `line`; not-found once the scan crosses onto an earlier line.
    func TryGetPreviousTokenOnLine(beforeIndex: int, line: int): TokenLookupResult {
        index := beforeIndex - 1
        while index >= 0 {
            candidate := Tokens[index]
            if candidate.Type == TokenType.Eof {
                index = index - 1
            } else {
                if candidate.Line != line {
                    return new TokenLookupResult(false, Current())
                }
                return new TokenLookupResult(true, candidate)
            }
        }
        return new TokenLookupResult(false, Current())
    }

    // Parser.cs IsSameLineMissingClosingDelimiterBoundary (:6309): the same-line tokens that stand in for
    // a missing `)` / `]`.
    func IsSameLineMissingClosingDelimiterBoundary(tokenType: TokenType): bool {
        if tokenType == TokenType.RightParen {
            return Check(TokenType.LeftBrace) || Check(TokenType.RightBrace) || Check(TokenType.RightBracket) || Check(TokenType.Colon) || Check(TokenType.Arrow) || Check(TokenType.Semicolon)
        }
        if tokenType == TokenType.RightBracket {
            return Check(TokenType.RightBrace) || Check(TokenType.RightParen) || Check(TokenType.Semicolon)
        }
        return false
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

    // ============================================================================
    // Stage 6: the STATEMENT diagnostic family — carried through the SAME shared-panic model.
    // Extends the function head with a real block-body grammar (the `func f() { <statements> }`
    // vehicle Stages 3-5 deliberately left unparsed) and reproduces Parser.cs's statement recovery:
    //   * the SynchronizeToNextStatement sync point + the per-statement panic reset (Parser.cs
    //     ParseBlock :2172 / SynchronizeToNextStatement :7084) and the _currentRecoveryBoundaryColumn
    //     tracking (:2177) that drives the dangling-operator "does not swallow the following statement".
    //   * the dangling-binary-operator / missing-assignment-value shape (ParseRightOperandOrMissing
    //     :3750, "Expected expression after 'X'", the DiagnosticSpanFromExpressionThroughToken span).
    //   * the missing-initializer `:=` / `=` forms (ParseRequiredExpressionAfter :3855, anchored on
    //     the declaration target).
    //   * the missing-condition if/while and missing-`in` for/foreach shapes
    //     (ReportMissingInKeywordAndRecover :3908) and the missing-statement-body report
    //     (ReportMissingStatementBody :3968).
    // Diagnostic CONSTRUCTION still delegates to the live shared ParserErrorDiagnostics.Create, and the
    // boundary DECISIONS reuse the live shared ParserTokenFacts (IsStatementStartKeyword /
    // CanStartExpression / IsExpressionTerminator / IsAssignmentOperator / IsModifierKeyword /
    // IsDeclarationKeyword / IsTypeDeclarationKeyword), identical to Parser.cs, so codes / messages /
    // spans / snippets / hints match automatically. Stage 9 exercises the block's own missing-'}' (NL106)
    // report — both the end-of-file variant (ReportMissingClosingBrace) and the IsBlockClosingDeclarationStart
    // found-declaration break below — as part of the closing-delimiter family.
    // ============================================================================

    // ---- block body (Parser.cs ParseBlock :2143) ----
    // '{' is guaranteed present at every call site (the caller checked Check(LeftBrace)).
    func ParseBlockBody(ownerSpan: RecoverySpan?) {
        line := Current().Line
        column := Current().Column
        Advance()                               // consume '{'
        diagnosticSpan := ownerSpan ?? new RecoverySpan(line, column, 1)

        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            // Stage 9: a type-declaration keyword that can't be a statement signals a missing '}' — report
            // the found-declaration NL106 anchored on the block owner and break so the outer declaration
            // loop parses it as a new declaration (Parser.cs :2156-2170, does NOT advance).
            if IsBlockClosingDeclarationStart() {
                ReportBlockMissingClosingBraceFoundDeclaration(diagnosticSpan, line)
                return
            }

            PanicMode = false                   // reset at each statement boundary (Parser.cs :2172)
            startPosition := Position

            // Track this statement's starting column so IsMissingOperandBoundary can tell a genuine
            // continuation from the start of the next statement (Parser.cs :2174-2182).
            prevBoundary := RecoveryBoundaryColumn
            prevHasBoundary := HasRecoveryBoundaryColumn
            RecoveryBoundaryColumn = Current().Column
            HasRecoveryBoundaryColumn = true
            ParseStatement(null)
            RecoveryBoundaryColumn = prevBoundary
            HasRecoveryBoundaryColumn = prevHasBoundary

            // No-progress guard (Parser.cs :2185-2195): synchronize, then force-advance.
            if Position == startPosition {
                if !IsAtEnd() {
                    SynchronizeToNextStatement()
                    if Position == startPosition {
                        if !IsAtEnd() {
                            Advance()
                        }
                    }
                }
            }
        }

        if Check(TokenType.RightBrace) {
            Advance()
        } else {
            if IsAtEnd() {
                ReportMissingClosingBrace(diagnosticSpan, line)
            }
        }
    }

    // Parser.cs ParseBlock's end-of-file missing-'}' report (:2205). Stage 9 exercises it.
    func ReportMissingClosingBrace(diagnosticSpan: RecoverySpan, openingLine: int) {
        Report(
            ErrorCode.MissingClosingBrace,
            "Missing closing '}'",
            diagnosticSpan.Line,
            diagnosticSpan.Column,
            "The block that started on line " + IntToString(openingLine) + " is missing its closing brace. I reached the end of the file without finding it.",
            "Add a '}' to close this block.",
            null,
            diagnosticSpan.Length)
    }

    // Parser.cs ParseBlock's found-declaration missing-'}' report (:2158). Fired when a type-declaration
    // keyword appears mid-block: the block is presumed unclosed and the offending declaration is left for
    // the outer loop (Stage 9).
    func ReportBlockMissingClosingBraceFoundDeclaration(diagnosticSpan: RecoverySpan, openingLine: int) {
        Report(
            ErrorCode.MissingClosingBrace,
            "Missing closing '}'",
            diagnosticSpan.Line,
            diagnosticSpan.Column,
            "The block that started on line " + IntToString(openingLine) + " appears to be missing its closing brace. I found '" + Current().Value + "' on line " + IntToString(Current().Line) + ", which looks like a new declaration.",
            "Add a '}' before this declaration to close the previous block.",
            null,
            diagnosticSpan.Length)
    }

    // Parser.cs IsBlockClosingDeclarationStart (:6964): a token that begins a top-level type declaration
    // (which cannot appear as a statement), so it signals the enclosing block is unclosed. The modifier-led
    // and attribute-led scans mirror Parser.cs's index walk; the corpus exercises the direct
    // type-declaration-keyword case (`class` mid-block).
    func IsBlockClosingDeclarationStart(): bool {
        if ParserTokenFacts.IsTypeDeclarationKeyword(Current().Type) {
            return true
        }
        if Current().Type == TokenType.Ref && LookAhead(1).Type == TokenType.Struct {
            return true
        }
        if IsSoaRecordDeclarationStart() {
            return true
        }
        if Current().Type == TokenType.Duck && LookAhead(1).Type == TokenType.Interface {
            return true
        }
        if Current().Type == TokenType.Test {
            return true
        }
        if Current().Type == TokenType.Identifier && Current().Value == "test" && LookAhead(1).Type == TokenType.StringLiteral {
            return true
        }
        // Modifier(s) followed by a type declaration keyword (Parser.cs :6987).
        if ParserTokenFacts.IsModifierKeyword(Current().Type) {
            ahead := 1
            while Position + ahead < Tokens.Count && ParserTokenFacts.IsModifierKeyword(Tokens[Position + ahead].Type) {
                ahead = ahead + 1
            }
            if Position + ahead < Tokens.Count {
                if ParserTokenFacts.IsTypeDeclarationKeyword(Tokens[Position + ahead].Type) || IsSoaRecordDeclarationStartAtOffset(ahead) {
                    return true
                }
            }
        }
        // '[' (attribute) followed eventually by a type declaration keyword (Parser.cs :7002).
        if Current().Type == TokenType.LeftBracket {
            ahead := 1
            depth := 1
            while Position + ahead < Tokens.Count && depth > 0 {
                if Tokens[Position + ahead].Type == TokenType.LeftBracket {
                    depth = depth + 1
                } else {
                    if Tokens[Position + ahead].Type == TokenType.RightBracket {
                        depth = depth - 1
                    }
                }
                ahead = ahead + 1
            }
            while Position + ahead < Tokens.Count && ParserTokenFacts.IsModifierKeyword(Tokens[Position + ahead].Type) {
                ahead = ahead + 1
            }
            if Position + ahead < Tokens.Count {
                if ParserTokenFacts.IsTypeDeclarationKeyword(Tokens[Position + ahead].Type) || IsSoaRecordDeclarationStartAtOffset(ahead) {
                    return true
                }
            }
        }
        return false
    }

    // Parser.cs IsSoaRecordDeclarationStartAtOffset (:7028).
    func IsSoaRecordDeclarationStartAtOffset(offset: int): bool {
        if Position + offset + 1 >= Tokens.Count {
            return false
        }
        return Tokens[Position + offset].Type == TokenType.Identifier && Tokens[Position + offset].Value == "soa" && Tokens[Position + offset + 1].Type == TokenType.Record
    }

    // Parser.cs SynchronizeToNextStatement (:7084): reset panic (+ split-`>>` debt) and skip to the
    // next statement boundary — a closing brace, a statement-start keyword, or a type-declaration keyword.
    func SynchronizeToNextStatement() {
        PanicMode = false
        SplitGreaterDepth = 0
        while !IsAtEnd() {
            if Check(TokenType.RightBrace) {
                return
            }
            if ParserTokenFacts.IsStatementStartKeyword(Current().Type) {
                return
            }
            if ParserTokenFacts.IsTypeDeclarationKeyword(Current().Type) {
                return
            }
            Advance()
        }
    }

    // ---- statement dispatch (Parser.cs ParseStatement :2219) ----
    // Stage 6 carries the let/const/readonly, if, for, foreach, while, return, print, block, and
    // expression-statement kinds — the surface the committed ParserErrorTests statement shapes reach.
    // yield / break / continue / throw / try / using / lock / switch / allow / alloc / unsafe / assert /
    // preprocessor / local-function / await-foreach / off statements are later arc stages (the corpus
    // uses none); they would each add their own ReportError sites under the same shared-panic model.
    func ParseStatement(blockOwnerSpan: RecoverySpan?) {
        // A control-flow keyword whose body is missing (Parser.cs :2221): the caller passes its owner
        // span, and if the very next token cannot begin a statement, report the missing body.
        if blockOwnerSpan != null {
            if IsMissingStatementBodyBoundary() {
                owner := blockOwnerSpan ?? SpanFromToken(Current())
                ReportMissingStatementBody(owner)
                return
            }
        }

        if Check(TokenType.Semicolon) {
            Advance()                           // empty statement (Parser.cs :2228)
            return
        }

        if Check(TokenType.Let) {
            ParseVariableDeclaration()
            return
        }
        if Check(TokenType.Const) {
            ParseVariableDeclaration()
            return
        }
        if Check(TokenType.Readonly) {
            ParseVariableDeclaration()
            return
        }
        if Check(TokenType.If) {
            ParseIfStatement()
            return
        }
        if Check(TokenType.For) {
            ParseForStatement()
            return
        }
        if Check(TokenType.Foreach) {
            ParseForeachStatement()
            return
        }
        if Check(TokenType.While) {
            ParseWhileStatement()
            return
        }
        if Check(TokenType.Return) {
            ParseReturnStatement()
            return
        }
        if Check(TokenType.Print) {
            ParsePrintStatement()
            return
        }
        if Check(TokenType.LeftBrace) {
            ParseBlockBody(blockOwnerSpan)
            return
        }

        ParseExpressionStatement()
    }

    // Parser.cs IsMissingStatementBodyBoundary (:3961) / ReportMissingStatementBody (:3968).
    func IsMissingStatementBodyBoundary(): bool {
        if Check(TokenType.RightBrace) {
            return true
        }
        if Check(TokenType.Else) {
            return true
        }
        return IsAtEnd()
    }

    func ReportMissingStatementBody(ownerSpan: RecoverySpan) {
        suggestions := new List<string>()
        suggestions.Add("Add a block body")
        suggestions.Add("Add a statement body")
        Report(
            ErrorCode.ExpectedToken,
            "Expected statement body. Got '" + Current().Value + "'",
            ownerSpan.Line,
            ownerSpan.Column,
            "This control-flow keyword needs a statement or block after its condition.",
            "Add a block like `{ ... }`, or add a single statement after the keyword.",
            suggestions,
            ownerSpan.Length)
    }

    // ---- variable declaration (Parser.cs ParseVariableDeclaration :2531) ----
    // let / const / readonly share one parser; the ownerDescription is always "This variable
    // declaration" regardless of kind. Tuple deconstruction `(x, y) := …` is a later arc stage.
    func ParseVariableDeclaration() {
        Advance()                               // consume let / const / readonly
        line := Current().Line
        column := Current().Column
        name := ConsumeIdentifier("Expected variable name")

        // Optional type annotation `: T` (Parser.cs :2550).
        if Check(TokenType.Colon) {
            Advance()
            ParseSimpleTypeReference()
        }

        if Check(TokenType.Assign) || Check(TokenType.ColonAssign) {
            initializerToken := Advance()
            ParseRequiredExpressionAfter(
                initializerToken,
                "an initializer expression",
                "This variable declaration",
                new RecoverySpan(line, column, MaxInt(1, name.Length)))
        }
    }

    // ---- if / while / for / foreach (Parser.cs :2629 / :2806 / :2651 / :2747) ----

    func ParseIfStatement() {
        ifToken := Current()
        Advance()                               // consume 'if'
        ParseRequiredExpressionAfter(ifToken, "a condition expression", "This if statement", null)
        ParseStatement(SpanFromToken(ifToken))  // then-branch, with the missing-body owner span
        if Check(TokenType.Else) {
            elseToken := Current()
            Advance()
            ParseStatement(SpanFromToken(elseToken))
        }
    }

    func ParseWhileStatement() {
        whileToken := Current()
        Advance()                               // consume 'while'
        ParseRequiredExpressionAfter(whileToken, "a condition expression", "This while statement", null)
        ParseStatement(SpanFromToken(whileToken))
    }

    // The foreach-style `for item in collection` (and its missing-`in` recovery). The C-style
    // `for init; cond; iter` loop is a later arc stage; the Stage-6 corpus uses only the foreach form.
    func ParseForStatement() {
        forToken := Current()
        Advance()                               // consume 'for'

        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.In {
            Advance()                           // loop variable
            inToken := ConsumeToken(TokenType.In, "Expected 'in'", "in")
            ParseRequiredExpressionAfter(inToken, "a collection expression", "This for-in statement", null)
            ParseStatement(SpanFromToken(forToken))
            return
        }

        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Identifier {
            variableToken := Current()
            Advance()                           // loop variable
            inToken := ReportMissingInKeywordAndRecover(forToken, variableToken, "This for-in statement")
            ParseRequiredExpressionAfter(inToken, "a collection expression", "This for-in statement", null)
            ParseStatement(SpanFromToken(forToken))
        }
    }

    func ParseForeachStatement() {
        foreachToken := Current()
        Advance()                               // consume 'foreach'
        // Optional parentheses `foreach (x in y)` are a later arc stage; the corpus uses none.
        variableToken := Current()
        ConsumeIdentifier("Expected variable name")
        inToken := ConsumeForeachInKeyword(foreachToken, variableToken)
        ParseRequiredExpressionAfter(inToken, "a collection expression", "This foreach statement", null)
        ParseStatement(SpanFromToken(foreachToken))
    }

    func ConsumeForeachInKeyword(foreachToken: Token, variableToken: Token): Token {
        if Check(TokenType.In) {
            return ConsumeToken(TokenType.In, "Expected 'in'", "in")
        }
        return ReportMissingInKeywordAndRecover(foreachToken, variableToken, "This foreach statement")
    }

    // Parser.cs ReportMissingInKeywordAndRecover (:3908): report the missing `in` anchored on the loop
    // keyword and return a synthetic `in` token so the collection expression still parses.
    func ReportMissingInKeywordAndRecover(loopKeywordToken: Token, variableToken: Token, ownerDescription: string): Token {
        expected := "in"                        // TokenTypeToString(In) = In.ToString().ToLower()
        suggestions := new List<string>()
        suggestions.Add("Add '" + expected + "' after '" + variableToken.Value + "'")
        Report(
            ErrorCode.ExpectedToken,
            "Expected '" + expected + "' between the loop variable and collection",
            loopKeywordToken.Line,
            loopKeywordToken.Column,
            ownerDescription + " needs the '" + expected + "' keyword between the loop variable and the collection.",
            "Write `" + loopKeywordToken.Value + " " + variableToken.Value + " " + expected + " ...`.",
            suggestions,
            MaxInt(1, loopKeywordToken.Value.Length))
        recoveredColumn := variableToken.Column + MaxInt(1, variableToken.Value.Length) + 1
        return new Token(TokenType.In, expected, variableToken.Line, recoveredColumn, variableToken.FileName)
    }

    // ---- return / print (Parser.cs :2821 / :2862) ----

    func ParseReturnStatement() {
        Advance()                               // consume 'return'
        if !Check(TokenType.RightBrace) && !IsAtEnd() && ParserTokenFacts.CanStartExpression(Current().Type) {
            ParseExprValue()
        }
    }

    func ParsePrintStatement() {
        printToken := Current()
        Advance()                               // consume 'print'
        ParseRequiredExpressionAfter(printToken, "an expression to print", "This print statement", null)
    }

    // ---- expression statement (Parser.cs ParseExpressionStatement :3498) ----
    // Parses the statement's expression, then recognizes the `identifier :=` shorthand declaration
    // (Parser.cs :3621, `expr is IdentifierExpression && Check(ColonAssign)`). The typed-declaration
    // `name: T = value` and the paren/no-paren tuple deconstruction forms are later arc stages.
    func ParseExpressionStatement() {
        result := ParseExprValue()
        if result.IsBareIdentifier {
            if Check(TokenType.ColonAssign) {
                initializerToken := Advance()
                ParseRequiredExpressionAfter(
                    initializerToken,
                    "an initializer expression",
                    "This shorthand variable declaration",
                    result.Span)
            }
        }
    }

    // ============================================================================
    // Stage 7: the EXPRESSIONS / PATTERNS diagnostic family — the FULLER precedence ladder (over the
    // Stage-6 shallow assignment/additive/multiplicative subset) plus the expression ERROR families
    // Stages 3/6 deliberately kept panic-suppressed, all carried through the SAME shared-panic model.
    // The ladder mirrors Parser.cs top-to-bottom (ParseAssignmentExpression :3690 → ParseTernary :4009
    // → ParseNullCoalescing :4033 → ParseLogicalOr/And :4047/:4061 → ParseBitwiseOr/Xor/And
    // :4075/:4089/:4103 → ParseEquality :4117 → ParseRelational :4132 → ParseShift :4205 →
    // ParseAdditive :4220 → ParseMultiplicative :4235 → ParseRange :4280 → ParseUnary :4316 →
    // ParsePostfix :4405 → ParsePrimary :4626). The expression ERROR families reached this stage:
    //   * UNEXPECTED-TOKEN-IN-EXPRESSION — ParsePrimary's terminal arm (:4813) + ShouldSkipUnexpectedExpressionToken (:6943).
    //   * PREFIX `+` — ParseInvalidPrefixPlusExpression (:3816, NL103 InvalidSyntax).
    //   * LEADING `.` — ParseLeadingMemberAccessWithoutReceiver (:6407).
    //   * TERNARY — the missing then / missing `:` / missing else sites (:4016/:4021/:4022).
    //   * DANGLING BINARY OPERATOR across every ladder tier (ParseBinaryRightOperandOrMissing :3778).
    //   * MEMBER-NAME-AFTER-DOT — ReportMissingMemberNameAfterDot (:6385) + the reserved-keyword member (:4433).
    //   * await / must / throw MISSING OPERAND — ParseUnaryOperandOrMissing (:3789).
    // Diagnostic CONSTRUCTION still delegates to the live shared ParserErrorDiagnostics.Create, and the
    // boundary DECISIONS reuse the live shared ParserTokenFacts (IsAssignmentOperator / CanStartExpression /
    // IsExpressionTerminator / …), so codes / messages / spans / snippets / hints match automatically.
    //
    // DEFERRED (recorded, NOT covered — with reasons): the `is`/`as` relational operators (parse a type
    // reference — the type sub-grammar); postfix CALL `(…)` / INDEX `[…]` / generic-call `<…>(…)` / `with {…}`
    // (the call-argument + closing-delimiter families — ParseArgumentList's inline-out, spread, named-args,
    // missing `)`/`]`/`}`); the new / alloc / stackalloc / match / array / cast / tuple / typeof / nameof /
    // sizeof / checked / unchecked / immutable / spread / interpolation / lambda primaries (each opens its own
    // sub-grammar with Consume/closing-delimiter sites); the MATCH / PATTERN family (ParseMatchExpression :5368
    // + ParsePattern/ParsePrimaryPattern :3263/:3335 + ParsePropertyPatterns :3459 — "match / patterns second"
    // per the recut); and the four INVALID-OPERATOR default arms (ParseAssignmentExpression :3718 /
    // ParseRelationalExpression :4177 / ParseMultiplicativeExpression :4253 / ParseUnaryExpression :4348),
    // which are UNREACHABLE dead defaults: each switch is guarded by an exact-match fact (IsAssignmentOperator
    // and the while/if token checks) that admits only tokens the switch already handles, so the default never
    // fires and cannot be reached byte-exact.
    // ============================================================================

    // ---- assignment (Parser.cs ParseAssignmentExpression :3690) ----
    // The single/multi-parameter lambda and `on` subscription prefixes (ParseLambdaOrAssignmentExpression
    // :3641) are the LAMBDA family — a later stage; the corpus uses no lambda/`on` expression.
    func ParseExprValue(): ExprResult {
        left := ParseTernary()

        // Assignment (Parser.cs :3694): only on the same line, only the recognized assignment operators.
        // The invalid-assignment-operator default (:3718) is an unreachable dead arm (IsAssignmentOperator
        // admits only the six operators the switch handles), so it is not modelled.
        if ParserTokenFacts.IsAssignmentOperator(Current().Type) && Current().Line == Previous().Line {
            opToken := Advance()
            // Parser.cs's operand is ParseLambdaOrAssignmentExpression (right-associative); the fallback
            // span is the left expression's DiagnosticSpanFromExpression span (Parser.cs :3740).
            if !RightOperandMissingWithSpan(opToken, left.Span) {
                ParseExprValue()
            }
            // The result is an AssignmentExpression; DiagnosticSpanFromExpression of one falls through
            // to the (line, column, 1) default at the operator position, and it is never a bare identifier.
            return new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }

        return left
    }

    // ---- ternary (Parser.cs ParseTernaryExpression :4009) ----
    func ParseTernary(): ExprResult {
        expr := ParseNullCoalescing()
        if Check(TokenType.Question) {
            questionToken := Advance()
            ParseRequiredExpressionAfter(
                questionToken,
                "a then expression",
                "This ternary expression",
                DiagnosticSpanFromExpressionThroughToken(expr.Span, questionToken))
            colonToken := ConsumeToken(TokenType.Colon, "Expected ':' in ternary expression", ":")
            ParseRequiredExpressionAfter(
                colonToken,
                "an else expression",
                "This ternary expression",
                DiagnosticSpanFromExpressionThroughToken(expr.Span, colonToken))
            // A TernaryExpression is anchored on the `?` token and is never a bare identifier.
            return new ExprResult(new RecoverySpan(questionToken.Line, questionToken.Column, 1), false)
        }
        return expr
    }

    // ---- the left-associative binary tiers (each mirrors one Parser.cs Parse*Expression) ----
    // Every tier accumulates its result span as the operator-position (line, column, 1) default that
    // DiagnosticSpanFromExpression yields for a BinaryExpression, so the through-token span of a following
    // dangling operator is computed byte-exact from the accumulated left expression.

    func ParseNullCoalescing(): ExprResult {
        result := ParseLogicalOr()
        while Check(TokenType.QuestionQuestion) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseLogicalOr()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    func ParseLogicalOr(): ExprResult {
        result := ParseLogicalAnd()
        while Check(TokenType.Or) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseLogicalAnd()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    func ParseLogicalAnd(): ExprResult {
        result := ParseBitwiseOr()
        while Check(TokenType.And) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseBitwiseOr()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    func ParseBitwiseOr(): ExprResult {
        result := ParseBitwiseXor()
        while Check(TokenType.BitwiseOr) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseBitwiseXor()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    func ParseBitwiseXor(): ExprResult {
        result := ParseBitwiseAnd()
        while Check(TokenType.BitwiseXor) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseBitwiseAnd()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    func ParseBitwiseAnd(): ExprResult {
        result := ParseEquality()
        while Check(TokenType.BitwiseAnd) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseEquality()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    func ParseEquality(): ExprResult {
        result := ParseRelational()
        while Check(TokenType.Equal) || Check(TokenType.NotEqual) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseRelational()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    // Parser.cs ParseRelationalExpression (:4132). The `is` / `as` operators (which parse a type reference)
    // are a later arc stage; the corpus uses only the four comparison operators. The invalid-relational
    // default (:4177) is an unreachable dead arm (the switch handles every token the guard admits).
    func ParseRelational(): ExprResult {
        result := ParseShift()
        while Check(TokenType.Less) || Check(TokenType.LessEqual) || Check(TokenType.Greater) || Check(TokenType.GreaterEqual) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseShift()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    func ParseShift(): ExprResult {
        result := ParseAdditive()
        while Check(TokenType.LeftShift) || Check(TokenType.RightShift) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseAdditive()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    func ParseAdditive(): ExprResult {
        result := ParseMultiplicative()
        while Check(TokenType.Plus) || Check(TokenType.Minus) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseMultiplicative()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    // Parser.cs ParseMultiplicativeExpression (:4235). The invalid-multiplicative default (:4253) is an
    // unreachable dead arm (the switch handles Star/Slash/Percent, exactly what the guard admits).
    func ParseMultiplicative(): ExprResult {
        result := ParseRange()
        while Check(TokenType.Star) || Check(TokenType.Slash) || Check(TokenType.Percent) {
            opToken := Advance()
            if !BinaryRightOperandMissing(opToken, result.Span) {
                ParseRange()
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return result
    }

    // Parser.cs ParseRangeExpression (:4280). `..end` / `..` (open start) and `start..end` / `start..`.
    // A RangeExpression is anchored on the `..` token; the end operand is a unary expression, guarded by
    // the same terminator set Parser.cs uses.
    func ParseRange(): ExprResult {
        if Check(TokenType.DotDot) {
            opToken := Advance()
            if RangeHasEndOperand() {
                ParseUnary()
            }
            return new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }

        expr := ParseUnary()
        if Check(TokenType.DotDot) {
            opToken := Advance()
            if RangeHasEndOperand() {
                ParseUnary()
            }
            return new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }
        return expr
    }

    // Parser.cs's range end-operand guard (:4289/:4305): an end expression is present unless the cursor is
    // at end-of-file or a `]` / `,` / `)` / `;`.
    func RangeHasEndOperand(): bool {
        if IsAtEnd() {
            return false
        }
        if Check(TokenType.RightBracket) {
            return false
        }
        if Check(TokenType.Comma) {
            return false
        }
        if Check(TokenType.RightParen) {
            return false
        }
        if Check(TokenType.Semicolon) {
            return false
        }
        return true
    }

    // ---- the missing-right-operand helpers (Parser.cs ParseBinaryRightOperandOrMissing :3778 /
    //      ParseRightOperandOrMissing :3750) ----
    // Returns true when the operator's right operand is missing (and the diagnostic has been reported), so
    // the caller skips the operand parse. A binary operator's fallback span runs from the left operand's
    // DiagnosticSpanFromExpression start through the operator token; an assignment's is the left span itself.

    func BinaryRightOperandMissing(operatorToken: Token, leftSpan: RecoverySpan): bool {
        return RightOperandMissingWithSpan(operatorToken, DiagnosticSpanFromExpressionThroughToken(leftSpan, operatorToken))
    }

    func RightOperandMissingWithSpan(operatorToken: Token, diagnosticSpan: RecoverySpan): bool {
        if IsMissingOperandBoundary(operatorToken) {
            ReportExpectedExpressionAfter(operatorToken, diagnosticSpan)
            return true
        }
        return false
    }

    // Parser.cs ParseRightOperandOrMissing's ReportError (:3759-3772).
    func ReportExpectedExpressionAfter(operatorToken: Token, span: RecoverySpan) {
        opValue := operatorToken.Value
        suggestions := new List<string>()
        suggestions.Add("Add an expression after '" + opValue + "'")
        suggestions.Add("Remove the trailing '" + opValue + "'")
        Report(
            ErrorCode.ExpectedToken,
            "Expected expression after '" + opValue + "'",
            span.Line,
            span.Column,
            "The '" + opValue + "' operator needs an expression on its right side.",
            "Finish the expression after the operator, or remove the operator if the expression is already complete.",
            suggestions,
            span.Length)
    }

    // Parser.cs DiagnosticSpanFromExpressionThroughToken (:3842). The startSpan is the left operand's
    // DiagnosticSpanFromExpression span; the result runs from its start through the operator token.
    func DiagnosticSpanFromExpressionThroughToken(startSpan: RecoverySpan, endToken: Token): RecoverySpan {
        if startSpan.Line != endToken.Line {
            return SpanFromToken(endToken)
        }
        endColumn := endToken.Column + TokenLength(endToken)
        return new RecoverySpan(startSpan.Line, startSpan.Column, MaxInt(startSpan.Length, endColumn - startSpan.Column))
    }

    // ---- unary (Parser.cs ParseUnaryExpression :4316) ----
    // Prefix `+` routes to the invalid-prefix-plus error; the recognized prefixes (! - ~ ++ -- ^) form a
    // UnaryExpression over a recursive unary operand; await / must / throw route through the shared
    // ParseUnaryOperandOrMissing (missing-operand report). The invalid-unary default (:4348) is an
    // unreachable dead arm (the switch handles every token the guard admits).
    func ParseUnary(): ExprResult {
        if Check(TokenType.Plus) {
            return ParseInvalidPrefixPlusExpression()
        }

        if Check(TokenType.Not) || Check(TokenType.Minus) || Check(TokenType.BitwiseNot) || Check(TokenType.Increment) || Check(TokenType.Decrement) || Check(TokenType.BitwiseXor) {
            opToken := Advance()
            ParseUnary()
            // A UnaryExpression is anchored on the operator and is never a bare identifier.
            return new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
        }

        if Check(TokenType.Await) {
            awaitToken := Advance()
            ParseUnaryOperandOrMissing(awaitToken, "an expression to await", "This await expression")
            return new ExprResult(new RecoverySpan(awaitToken.Line, awaitToken.Column, 5), false)
        }
        if Check(TokenType.Must) {
            mustToken := Advance()
            ParseUnaryOperandOrMissing(mustToken, "a nullable expression to unwrap", "This must expression")
            return new ExprResult(new RecoverySpan(mustToken.Line, mustToken.Column, 4), false)
        }
        if Check(TokenType.Throw) {
            throwToken := Advance()
            ParseUnaryOperandOrMissing(throwToken, "an exception expression to throw", "This throw expression")
            return new ExprResult(new RecoverySpan(throwToken.Line, throwToken.Column, 5), false)
        }

        return ParsePostfix()
    }

    // Parser.cs ParseInvalidPrefixPlusExpression (:3816). Reports NL103, then consumes a unary operand
    // when one is present (so a following `+ 3` does not report a second, redundant error under panic).
    func ParseInvalidPrefixPlusExpression(): ExprResult {
        plusToken := Advance()
        span := SpanFromToken(plusToken)
        if Current().Line == plusToken.Line && !ParserTokenFacts.IsExpressionTerminator(Current().Type) {
            span = DiagnosticSpanFromTokenRange(plusToken, Current())
        }
        suggestions := new List<string>()
        suggestions.Add("Remove the leading '+'")
        Report(
            ErrorCode.InvalidSyntax,
            "Prefix '+' is not supported",
            span.Line,
            span.Column,
            "A leading '+' does not change the value in N#, so it is not part of the expression grammar.",
            "Remove the leading '+'. Numeric literals and variables are already positive unless you subtract or negate them.",
            suggestions,
            span.Length)

        if !IsMissingOperandBoundary(plusToken) && ParserTokenFacts.CanStartExpression(Current().Type) {
            ParseUnary()
        }
        // Returns IdentifierExpression("<error>", plus.Line, plus.Column): not a visible name, so its
        // DiagnosticSpanFromExpression is the (line, column, 1) default; it is still an IdentifierExpression.
        return new ExprResult(new RecoverySpan(plusToken.Line, plusToken.Column, 1), true)
    }

    // Parser.cs ParseUnaryOperandOrMissing (:3789). Uses IsMissingRequiredExpressionBoundary and a unary
    // operand; the message / hint differ from the binary ParseRightOperandOrMissing.
    func ParseUnaryOperandOrMissing(operatorToken: Token, expectedDescription: string, ownerDescription: string) {
        if !IsMissingRequiredExpressionBoundary(operatorToken) {
            ParseUnary()
            return
        }
        span := SpanFromToken(operatorToken)
        suggestions := new List<string>()
        suggestions.Add("Add " + expectedDescription + " after '" + operatorToken.Value + "'")
        suggestions.Add("Remove '" + operatorToken.Value + "' until the expression is ready")
        Report(
            ErrorCode.ExpectedToken,
            "Expected " + expectedDescription + " after '" + operatorToken.Value + "'",
            span.Line,
            span.Column,
            ownerDescription + " needs " + expectedDescription + " after '" + operatorToken.Value + "'.",
            "Add " + expectedDescription + " after '" + operatorToken.Value + "', or remove '" + operatorToken.Value + "'.",
            suggestions,
            span.Length)
    }

    // ---- postfix (Parser.cs ParsePostfixExpression :4405) ----
    // Stage 10 carries the member-access `.` / `?.` diagnostics (reserved-keyword member +
    // missing-member-name), the postfix `++` / `--` forms, and now the postfix CALL `(…)`, INDEX `[…]`,
    // generic-call `<…>(…)`, and `with {…}` sub-grammars with their error sites (the call-argument family
    // via ParseArgumentList; the index / call closes route through the Stage-9 closing-delimiter recovery).
    func ParsePostfix(): ExprResult {
        result := ParsePrimaryExprValue()

        looping := true
        while looping {
            // A new line without a continuing `.` / `?.` ends the postfix chain (Parser.cs :4411).
            if Current().Line > Previous().Line && !Check(TokenType.Dot) && !Check(TokenType.QuestionDot) {
                looping = false
            } else {
                if Check(TokenType.Dot) || Check(TokenType.QuestionDot) {
                    result = ParseMemberAccess(result)
                } else {
                    if Check(TokenType.LeftBracket) || Check(TokenType.QuestionBracket) {
                        // Index access `a[i]` / `a?[i]` (Parser.cs :4444). The RightBracket close routes
                        // through the Stage-9 closing-delimiter recovery (NL108 when unclosed). An
                        // IndexAccessExpression's DiagnosticSpanFromExpression is the OBJECT's span (:5948).
                        Advance()
                        ParseExprValue()
                        ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
                        result = new ExprResult(result.Span, false)
                    } else {
                        if Check(TokenType.Less) && IsGenericMethodCall() {
                            // Generic method call `M<T>(…)` (Parser.cs :4452). A CallExpression's span is
                            // the CALLEE's span (:5946), i.e. the current receiver's.
                            ParseCallTypeArguments()
                            if !Check(TokenType.LeftParen) {
                                ReportMissingParenAfterGenericTypeArguments()
                            } else {
                                Advance()
                                ParseArgumentList()
                            }
                            result = new ExprResult(result.Span, false)
                        } else {
                            if Check(TokenType.LeftParen) {
                                // Call `f(…)` (Parser.cs :4484). CallExpression span = callee span.
                                Advance()
                                ParseArgumentList()
                                result = new ExprResult(result.Span, false)
                            } else {
                                if Check(TokenType.Increment) {
                                    opToken := Advance()
                                    result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
                                } else {
                                    if Check(TokenType.Decrement) {
                                        opToken := Advance()
                                        result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
                                    } else {
                                        if Check(TokenType.With) {
                                            result = ParseWithExpression()
                                        } else {
                                            looping = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return result
    }

    // Parser.cs's `with { … }` postfix arm (:4500). A WithExpression is anchored on the `with` keyword and
    // is never a bare identifier (its DiagnosticSpanFromExpression falls to the (line, column, 1) default,
    // :5960). The property loop's EnsureProgress (:4518) does NOT reset panic (unlike the new-object /
    // match-case reset), so a property error cascade-suppresses the rest of the `with` block.
    func ParseWithExpression(): ExprResult {
        withToken := Advance()                              // consume 'with'
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            ConsumeIdentifier("Expected property name")     // Parser.cs :4510
            ConsumeToken(TokenType.Colon, "Expected ':'", ":")
            ParseExprValue()                                // the property value (Parser.cs :4512)
            if !Check(TokenType.RightBrace) {               // optional comma separator (Parser.cs :4515)
                if Check(TokenType.Comma) {
                    Advance()
                }
            }
            EnsureProgress(startPosition)                   // Parser.cs :4518 — NO panic reset
        }
        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
        return new ExprResult(new RecoverySpan(withToken.Line, withToken.Column, 1), false)
    }

    // ============================================================================
    // Stage 10: the CALL-ARGUMENT family (Parser.cs ParseArgumentList :4533) + the generic-call type
    // arguments (ParseCallTypeArguments :2086 / IsGenericMethodCall :2025). The recovery model builds no
    // AST, so ParseArgumentList only reproduces the DIAGNOSTIC-bearing behaviour: the recovery-boundary
    // break, the inline-out NL103, the spread / named-argument / bare alloc-family recognition (each
    // consumes tokens without a diagnostic), and the closing `)` (routed through the Stage-9 recovery).
    // ============================================================================

    // Parser.cs ParseArgumentList (:4533). Consumes `arg, arg, …)`; the closing `)` reaches
    // TryReportMissingClosingDelimiter (NL107 when unclosed) via ConsumeToken.
    func ParseArgumentList() {
        if !Check(TokenType.RightParen) {
            argsLooping := true
            while argsLooping {
                if IsArgumentListRecoveryBoundaryWithOpening(Previous()) {
                    argsLooping = false
                } else {
                    ParseArgument()
                    if Check(TokenType.Comma) {             // Parser.cs do/while Match(Comma) (:4608)
                        Advance()
                    } else {
                        argsLooping = false
                    }
                }
            }
        }
        ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
    }

    // One argument (Parser.cs :4544-4606): the ref/out modifier (with the inline-out NL103), the named
    // `name:` prefix, the spread `...`, the bare alloc/allow/stackalloc identifier, or a plain expression.
    func ParseArgument() {
        // ref / out modifier (Parser.cs :4547).
        if Check(TokenType.Ref) {
            Advance()
        } else {
            if Check(TokenType.Out) {
                Advance()
                // Inline out declaration `out T x` (Parser.cs :4557): two consecutive identifiers.
                if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Identifier {
                    first := Current()
                    second := LookAhead(1)
                    ReportInlineOutDeclaration(first, second)
                    Advance()
                    Advance()
                    return                                  // Parser.cs `continue` — the argument is complete
                }
            }
        }

        // Named argument `name:` (Parser.cs :4579).
        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon {
            Advance()                                       // the name
            Advance()                                       // the colon
        }

        // Spread `...expr` (Parser.cs :4587).
        if Check(TokenType.DotDotDot) {
            Advance()
            ParseExprValue()
            return
        }

        // A bare alloc / allow / stackalloc keyword used as an identifier argument (Parser.cs :4595):
        // only when immediately followed by `,` or `)` (otherwise it opens its own sub-grammar).
        if Check(TokenType.Alloc) || Check(TokenType.Allow) || Check(TokenType.Stackalloc) {
            if LookAhead(1).Type == TokenType.Comma || LookAhead(1).Type == TokenType.RightParen {
                Advance()
                return
            }
        }

        ParseExprValue()
    }

    // Parser.cs's inline-out diagnostic (:4561, NL103 InvalidSyntax). The span runs from the first
    // identifier through the end of the second.
    func ReportInlineOutDeclaration(first: Token, second: Token) {
        length := MaxInt(1, second.Column + second.Value.Length - first.Column)
        Report(
            ErrorCode.InvalidSyntax,
            "Inline out declarations are not supported",
            first.Line,
            first.Column,
            "N# out arguments must refer to a variable that already exists.",
            "Declare '" + second.Value + "' before the call, then pass 'out " + second.Value + "'.",
            null,
            length)
    }

    // Parser.cs IsArgumentListRecoveryBoundary() (:4615) — the unconditional boundary tokens.
    func IsArgumentListRecoveryBoundary(): bool {
        if IsAtEnd() {
            return true
        }
        if Check(TokenType.LeftBrace) {
            return true
        }
        if Check(TokenType.RightBrace) {
            return true
        }
        if Check(TokenType.RightBracket) {
            return true
        }
        if Check(TokenType.Semicolon) {
            return true
        }
        return false
    }

    // Parser.cs IsArgumentListRecoveryBoundary(Token openingToken) (:4622).
    func IsArgumentListRecoveryBoundaryWithOpening(openingToken: Token): bool {
        if IsArgumentListRecoveryBoundary() {
            return true
        }
        return IsContinuationRecoveryBoundary(openingToken)
    }

    // Parser.cs IsContinuationRecoveryBoundary (:6927): a token on a LATER line than the opening delimiter
    // that begins a statement / declaration / modifier, or sits at or left of the statement's recovery
    // boundary column, ends the continuation so the outer recovery can resynchronise.
    func IsContinuationRecoveryBoundary(openingToken: Token): bool {
        if Current().Line <= openingToken.Line {
            return false
        }
        if ParserTokenFacts.IsStatementStartKeyword(Current().Type) {
            return true
        }
        if ParserTokenFacts.IsDeclarationKeyword(Current().Type) {
            return true
        }
        if ParserTokenFacts.IsModifierKeyword(Current().Type) {
            return true
        }
        return HasRecoveryBoundaryColumn && Current().Column <= RecoveryBoundaryColumn
    }

    // Parser.cs IsGenericMethodCall (:2025): a bounded lookahead deciding whether the `<` at the cursor
    // opens a type-argument list for a method call (`Method<Type>(`) rather than a comparison. Pure
    // lookahead — no cursor mutation, no diagnostics.
    func IsGenericMethodCall(): bool {
        lookAheadPos := Position + 1
        if lookAheadPos >= Tokens.Count {
            return false
        }
        next := Tokens[lookAheadPos]
        if next.Type != TokenType.Identifier {
            return false
        }
        lookAheadPos = lookAheadPos + 1
        scanning := true
        while scanning {
            if lookAheadPos >= Tokens.Count {
                scanning = false
            } else {
                token := Tokens[lookAheadPos]
                if token.Type == TokenType.Greater {
                    lookAheadPos = lookAheadPos + 1
                    return lookAheadPos < Tokens.Count && Tokens[lookAheadPos].Type == TokenType.LeftParen
                }
                if token.Type == TokenType.RightShift {
                    lookAheadPos = lookAheadPos + 1
                    return lookAheadPos < Tokens.Count && Tokens[lookAheadPos].Type == TokenType.LeftParen
                }
                if token.Type == TokenType.Comma {
                    return true
                }
                if token.Type == TokenType.Dot || token.Type == TokenType.Less || token.Type == TokenType.LeftBracket || token.Type == TokenType.Question || token.Type == TokenType.QuestionBracket || token.Type == TokenType.Identifier || token.Type == TokenType.RightBracket {
                    lookAheadPos = lookAheadPos + 1
                } else {
                    return false
                }
            }
        }
        return false
    }

    // Parser.cs ParseCallTypeArguments (:2086): `<Type, Type, …>` with the split-`>>`-aware ConsumeGreater.
    func ParseCallTypeArguments() {
        Advance()                                           // consume '<' (Parser.cs Consume(Less) :2088)
        ParseTypeReferenceRecovery()
        while Check(TokenType.Comma) {
            Advance()
            ParseTypeReferenceRecovery()
        }
        ConsumeGreater("Expected '>'")
    }

    // Parser.cs's "Expected '(' after generic type arguments" report (:4460, NL102). IsGenericMethodCall
    // guarantees a `(` follows the closing `>`, so this arm is only reachable if the split-`>>` accounting
    // consumed it; modelled faithfully for parity but not corpus-reachable (recorded in STATUS.md).
    func ReportMissingParenAfterGenericTypeArguments() {
        suggestions := new List<string>()
        suggestions.Add("Add parentheses: Method<int>()")
        suggestions.Add("With arguments: Method<int>(arg1, arg2)")
        suggestions.Add("Example: List.Create<string>(\"hello\")")
        Report(
            ErrorCode.ExpectedToken,
            "Expected '(' after generic type arguments. Got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "Generic method calls need parentheses for the arguments, even if there are no arguments.",
            "After the generic type parameters, you need to provide the method arguments in parentheses.",
            suggestions,
            Current().Value.Length)
    }

    // Parser.cs's `.` / `?.` member-access arm (:4418). Returns the MemberAccessExpression's
    // DiagnosticSpanFromExpression span (:5941): the member-name span when the name is visible, else the
    // (dotLine, dotColumn, 1) default. A MemberAccessExpression is never a bare identifier.
    func ParseMemberAccess(receiver: ExprResult): ExprResult {
        isNullConditional := Check(TokenType.QuestionDot)
        dotToken := Advance()

        if Current().Line == dotToken.Line && Check(TokenType.Identifier) {
            memberToken := Advance()
            memberOffset := 1
            if isNullConditional {
                memberOffset = 2
            }
            return new ExprResult(new RecoverySpan(dotToken.Line, dotToken.Column + memberOffset, MaxInt(1, memberToken.Value.Length)), false)
        }

        if Current().Line == dotToken.Line && Lexer.IsReservedKeyword(Current().Type) {
            // `obj.base`, `this.new`, etc. — a reserved keyword where the member name is required.
            ReportReservedKeywordAsName("Expected member name", SpanFromToken(Current()), true)
            Advance()
            return new ExprResult(new RecoverySpan(dotToken.Line, dotToken.Column, 1), false)
        }

        ReportMissingMemberNameAfterDot(dotToken, receiver.Span)
        return new ExprResult(new RecoverySpan(dotToken.Line, dotToken.Column, 1), false)
    }

    // Parser.cs ReportMissingMemberNameAfterDot (:6385). Anchored on the receiver's DiagnosticSpanFromExpression.
    func ReportMissingMemberNameAfterDot(dotToken: Token, receiverSpan: RecoverySpan) {
        operatorText := dotToken.Value
        operatorDescription := "dot (.)"
        if operatorText != "." {
            operatorDescription = "null-conditional member access (" + operatorText + ")"
        }
        suggestions := new List<string>()
        suggestions.Add("Check if you forgot to finish this line")
        suggestions.Add("Common members: Length, Count, ToString(), GetHashCode()")
        suggestions.Add("If this is end of statement, remove the trailing '" + operatorText + "'")
        Report(
            ErrorCode.ExpectedToken,
            "Expected member name. Got '" + Current().Value + "'",
            receiverSpan.Line,
            receiverSpan.Column,
            "I see a " + operatorDescription + " operator but no member name after it.",
            "After " + operatorDescription + ", I need to see a property or method name.",
            suggestions,
            receiverSpan.Length)
    }

    // ---- primary (Parser.cs ParsePrimaryExpression :4626) ----
    // Returns the DiagnosticSpanFromExpression span (:5917) and whether the primary is a bare identifier.
    // Stage 10 carries the first KEYWORD-LED-PRIMARY tranche: typeof / nameof / sizeof / checked / unchecked
    // (the shared `(…)` paren-wrapped shape), new (ParseNewExpression, incl. the object-initializer
    // panic-reset-on-progress discipline), immutable / array literal `[…]`, cast `(Type)expr`, and the full
    // tuple / parenthesized `(…)` grammar. DEFERRED (recorded): alloc / stackalloc primaries (their own
    // sub-grammar — the next tranche), and interpolation `$"…"` / lambda; the corpus uses none of the
    // deferred forms, so the unexpected-token terminal arm stays byte-exact.
    func ParsePrimaryExprValue(): ExprResult {
        line := Current().Line
        column := Current().Column

        // Leading member access with no receiver: `.Foo` (Parser.cs :4631).
        if Check(TokenType.Dot) || Check(TokenType.QuestionDot) {
            return ParseLeadingMemberAccessWithoutReceiver()
        }

        // Int / float literals carry no malformed check (Parser.cs :4637/:4640).
        if Check(TokenType.IntLiteral) || Check(TokenType.FloatLiteral) {
            token := Advance()
            return new ExprResult(new RecoverySpan(token.Line, token.Column, MaxInt(1, token.Value.Length)), false)
        }

        // Char / string literals run the malformed-literal check (Parser.cs :4643/:4650). The interpolated
        // string hole grammar (ParseInterpolatedString) is a later arc stage; the corpus uses no `$"…"`.
        if Check(TokenType.CharLiteral) {
            token := Advance()
            ReportMalformedCharLiteralIfNeeded(token)
            return new ExprResult(new RecoverySpan(token.Line, token.Column, MaxInt(1, token.Value.Length)), false)
        }
        if Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral) {
            token := Advance()
            ReportMalformedStringLiteralIfNeeded(token)
            return new ExprResult(new RecoverySpan(token.Line, token.Column, MaxInt(1, token.Value.Length)), false)
        }

        if Check(TokenType.True) {
            Advance()
            return new ExprResult(new RecoverySpan(line, column, 4), false)
        }
        if Check(TokenType.False) {
            Advance()
            return new ExprResult(new RecoverySpan(line, column, 5), false)
        }
        if Check(TokenType.Null) {
            Advance()
            return new ExprResult(new RecoverySpan(line, column, 4), false)
        }
        if Check(TokenType.Default) {
            Advance()
            return new ExprResult(new RecoverySpan(line, column, 7), false)
        }
        if Check(TokenType.This) {
            Advance()
            return new ExprResult(new RecoverySpan(line, column, 4), false)
        }
        if Check(TokenType.Base) {
            Advance()
            return new ExprResult(new RecoverySpan(line, column, 4), false)
        }

        // typeof / nameof / sizeof (Parser.cs :4700/:4709/:4718): the `( Type )` / `( expr )` shape. typeof
        // and sizeof wrap a TYPE reference; nameof wraps an expression. Each is a non-identifier primary
        // whose DiagnosticSpanFromExpression falls to the (line, column, 1) default (:5960).
        if Check(TokenType.Typeof) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            ParseTypeReferenceRecovery()
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }
        if Check(TokenType.Nameof) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            ParseExprValue()
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }
        if Check(TokenType.Sizeof) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            ParseTypeReferenceRecovery()
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        // checked / unchecked (Parser.cs :4728/:4738): the same `( expr )` paren-wrapped shape.
        if Check(TokenType.Checked) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            ParseExprValue()
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }
        if Check(TokenType.Unchecked) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            ParseExprValue()
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        // new expression (Parser.cs :4758). alloc / stackalloc (:4747/:4752) are DEFERRED to the next
        // tranche (their own sub-grammar); the corpus uses neither as a primary.
        if Check(TokenType.New) {
            return ParseNewExpression()
        }

        // Match expression `match value { pattern => expr, … }` (Parser.cs :4764). Stage 8's minimal match
        // vehicle, carried here so the match / pattern diagnostic family fires through the shared-panic model.
        if Check(TokenType.Match) {
            return ParseMatchExpression()
        }

        // Immutable array literal `immutable [ … ]` (Parser.cs :4770).
        if Check(TokenType.Immutable) && LookAhead(1).Type == TokenType.LeftBracket {
            Advance()                                       // consume 'immutable'
            return ParseArrayLiteral()
        }

        // Array literal `[ … ]` (Parser.cs :4777). The RightBracket close routes through the Stage-9 recovery.
        if Check(TokenType.LeftBracket) {
            return ParseArrayLiteral()
        }

        // Cast `(Type)expr` — checked BEFORE tuple/paren so `(int)x` is a cast, not a parenthesized `int`
        // (Parser.cs :4783). A CastExpression's DiagnosticSpanFromExpression falls to the (line, column, 1)
        // default (:5960).
        if Check(TokenType.LeftParen) && IsCastExpression() {
            Advance()                                       // consume '('
            ParseTypeReferenceRecovery()                    // the cast type
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            ParseUnary()                                    // the cast operand (Parser.cs ParseUnaryExpression :4788)
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        // Tuple or parenthesized expression `( … )` (Parser.cs :4793).
        if Check(TokenType.LeftParen) {
            return ParseTupleOrParenthesizedExpression()
        }

        // Spread `...expr` (Parser.cs :4799). A SpreadExpression falls to the (line, column, 1) default.
        if Check(TokenType.DotDotDot) {
            Advance()
            ParseExprValue()
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        if Check(TokenType.Identifier) {
            name := Advance().Value
            return new ExprResult(new RecoverySpan(line, column, MaxInt(1, name.Length)), true)
        }

        // Terminal: an unexpected token where an expression was required (Parser.cs :4813).
        Report(
            ErrorCode.UnexpectedToken,
            "Unexpected token '" + Current().Value + "' in expression",
            line,
            column,
            "I was parsing an expression and found '" + Current().Value + "', which I don't know how to handle here.",
            "Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.",
            null,
            Current().Value.Length)

        if ShouldSkipUnexpectedExpressionToken() {
            Advance()
        }

        // Returns IdentifierExpression("<error>", line, column): a (non-visible) IdentifierExpression, so its
        // span is the (line, column, 1) default and it is still an IdentifierExpression.
        return new ExprResult(new RecoverySpan(line, column, 1), true)
    }

    // Parser.cs ParseLeadingMemberAccessWithoutReceiver (:6407). Reports "Expected expression before '.'"
    // and consumes the member name when one follows on the same line.
    func ParseLeadingMemberAccessWithoutReceiver(): ExprResult {
        dotToken := Advance()
        operatorText := dotToken.Value
        operatorDescription := "dot (.)"
        if operatorText != "." {
            operatorDescription = "null-conditional member access (" + operatorText + ")"
        }
        span := SpanFromToken(dotToken)
        if Current().Line == dotToken.Line && Check(TokenType.Identifier) {
            memberToken := Advance()
            span = DiagnosticSpanFromTokenRange(dotToken, memberToken)
        }
        suggestions := new List<string>()
        suggestions.Add("Add a receiver before '" + operatorText + "'")
        suggestions.Add("Remove the member access until the receiver is known")
        Report(
            ErrorCode.ExpectedToken,
            "Expected expression before '" + operatorText + "'",
            span.Line,
            span.Column,
            "I see a " + operatorDescription + " operator, but there is no receiver expression before it.",
            "Put an expression before '" + operatorText + "', or remove the member access.",
            suggestions,
            span.Length)
        // Returns IdentifierExpression("<error>", dot.Line, dot.Column).
        return new ExprResult(new RecoverySpan(dotToken.Line, dotToken.Column, 1), true)
    }

    // Parser.cs ShouldSkipUnexpectedExpressionToken (:6943): skip the offending token unless it is at
    // end-of-file, an expression terminator, or a statement/declaration/modifier keyword (which the
    // enclosing recovery boundary will handle).
    func ShouldSkipUnexpectedExpressionToken(): bool {
        if IsAtEnd() {
            return false
        }
        if ParserTokenFacts.IsExpressionTerminator(Current().Type) {
            return false
        }
        if ParserTokenFacts.IsStatementStartKeyword(Current().Type) {
            return false
        }
        if ParserTokenFacts.IsDeclarationKeyword(Current().Type) {
            return false
        }
        if ParserTokenFacts.IsModifierKeyword(Current().Type) {
            return false
        }
        return true
    }

    // ============================================================================
    // Stage 10: the KEYWORD-LED PRIMARY sub-grammars — new / array / tuple-or-parenthesized / cast — plus the
    // object-initializer discipline and the cast-detection lookahead. Carried through the SAME shared-panic
    // model; CONSTRUCTION delegates to ParserErrorDiagnostics.Create and DECISIONS reuse ParserTokenFacts /
    // IsTypeTerminator, so codes / messages / spans / snippets / hints match Parser.cs automatically.
    // ============================================================================

    // Parser.cs ParseNewExpression (:5209). Target-typed `new(args)` / `new { init }`, or traditional
    // `new Type[len]?(args)?{ init }?`. A NewExpression's DiagnosticSpanFromExpression is (newLine,
    // newColumn, "new".Length) (:5958).
    func ParseNewExpression(): ExprResult {
        newToken := Advance()                               // consume 'new'
        hasArrayLength := false

        if Check(TokenType.LeftParen) {
            // Target-typed new: `new(args)` (Parser.cs :5220).
            Advance()
            ParseArgumentList()
        } else {
            if Check(TokenType.LeftBrace) {
                // Target-typed new with initializer only: `new { … }` (Parser.cs :5226) — parsed below.
            } else {
                // Traditional new: `new TypeName …` (Parser.cs :5233).
                ParseNewTypeReference(newToken)
                if Check(TokenType.LeftBracket) {           // sized array `new Type[len]` (Parser.cs :5237)
                    Advance()
                    ParseExprValue()
                    ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
                    hasArrayLength = true
                }
                if Check(TokenType.LeftParen) {             // constructor args (Parser.cs :5248)
                    Advance()
                    ParseArgumentList()
                }
                if hasArrayLength {
                    // `new Type[len] { … }` sized-array initializer (Parser.cs :5257): bare-value elements
                    // with the per-element panic-reset-on-progress discipline.
                    if Check(TokenType.LeftBrace) {
                        Advance()
                        while !Check(TokenType.RightBrace) && !IsAtEnd() {
                            startPosition := Position
                            ParseExprValue()
                            if !Check(TokenType.RightBrace) {
                                if Check(TokenType.Comma) {
                                    Advance()
                                }
                            }
                            if !EnsureProgress(startPosition) {
                                PanicMode = false           // Parser.cs :5268-5269
                            }
                        }
                        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
                    }
                    return new ExprResult(new RecoverySpan(newToken.Line, newToken.Column, 3), false)
                }
            }
        }

        // Object / collection initializer `{ … }` (Parser.cs :5280).
        if Check(TokenType.LeftBrace) {
            ParseObjectInitializer()
        }
        return new ExprResult(new RecoverySpan(newToken.Line, newToken.Column, 3), false)
    }

    // Parser.cs ParseNewTypeReference (:6579): the type after `new`, or the "Expected type name" NL102
    // (anchored on the `new` keyword) when a type terminator immediately follows.
    func ParseNewTypeReference(newToken: Token) {
        if !IsTypeTerminator(Current().Type) {
            ParseTypeReferenceRecovery()
            return
        }
        span := SpanFromToken(newToken)
        suggestions := new List<string>()
        suggestions.Add("Add a type name after `new`")
        suggestions.Add("Use `new()` for target-typed construction")
        Report(
            ErrorCode.ExpectedToken,
            "Expected type name. Got '" + Current().Value + "'",
            span.Line,
            span.Column,
            "The `new` expression needs a type name, `()`, or an initializer after it.",
            "Write `new TypeName(...)`, `new()`, or `new { Name: value }`.",
            suggestions,
            span.Length)
    }

    // Parser.cs's object / collection initializer loop (:5285-5340). Each element resets panic on natural
    // progress (`if (!EnsureProgress(startPosition)) _panicMode = false;`, :5334) — DISTINCT from the with /
    // match loops that never reset. The recovery model does not know the receiver's array-ness, so it always
    // takes the object-initializer branch (indexer `[i] = v` and bare collection values reuse ParseExprValue),
    // which reproduces the diagnostic-bearing property-name / missing-colon behaviour byte-exact.
    func ParseObjectInitializer() {
        Advance()                                           // consume '{'
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            if Check(TokenType.LeftBracket) {
                // Indexer initializer `[i] = v` (Parser.cs :5299).
                Advance()
                ParseExprValue()
                ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
                ConsumeToken(TokenType.Assign, "Expected '='", "=")
                ParseExprValue()
            } else {
                // Regular property initializer `Name: value` (Parser.cs :5310).
                propNameToken := Current()
                propName := ConsumeIdentifier("Expected property name")
                if Check(TokenType.Colon) {
                    Advance()
                    ParseObjectInitializerMemberValue(propNameToken, propName)
                } else {
                    ReportMissingObjectInitializerColon(propNameToken, propName)
                }
            }
            if !Check(TokenType.RightBrace) {
                if Check(TokenType.Comma) {
                    Advance()
                }
            }
            if !EnsureProgress(startPosition) {
                PanicMode = false                           // Parser.cs :5334-5335
            }
        }
        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
    }

    // Parser.cs ParseObjectInitializerMemberValue (:5345): a required value after the member `:`, or the
    // "Expected a value for object initializer member" NL102 anchored on the property.
    func ParseObjectInitializerMemberValue(propertyToken: Token, propertyName: string) {
        if !IsMissingRequiredExpressionBoundary(propertyToken) {
            ParseExprValue()
            return
        }
        propertyLength := MaxInt(1, propertyName.Length)
        suggestions := new List<string>()
        suggestions.Add("Add a value after '" + propertyName + ":'")
        Report(
            ErrorCode.ExpectedToken,
            "Expected a value for object initializer member '" + propertyName + "'",
            propertyToken.Line,
            propertyToken.Column,
            "Object initializer member '" + propertyName + "' needs a value after ':'.",
            "Write '" + propertyName + ": value'.",
            suggestions,
            propertyLength)
    }

    // Parser.cs ReportMissingObjectInitializerColon (:6605, NL102): anchored on the property token when its
    // name is visible, else on the current offender.
    func ReportMissingObjectInitializerColon(propertyToken: Token, propertyName: string) {
        span := SpanFromToken(Current())
        if IsVisibleName(propertyName) {
            span = SpanFromToken(propertyToken)
        }
        suggestions := new List<string>()
        suggestions.Add("Add ':' after '" + propertyName + "'")
        Report(
            ErrorCode.ExpectedToken,
            "Expected ':' after object initializer member '" + propertyName + "'",
            span.Line,
            span.Column,
            "Object initializer member '" + propertyName + "' needs ':' before its value.",
            "Write '" + propertyName + ": value'.",
            suggestions,
            span.Length)
    }

    // Parser.cs ParseArrayLiteral (:5407). `[ e, e, … ]`; the RightBracket close routes through the Stage-9
    // recovery (NL108 when unclosed). An ArrayLiteralExpression falls to the (bracketLine, bracketColumn, 1)
    // DiagnosticSpanFromExpression default (:5960).
    func ParseArrayLiteral(): ExprResult {
        bracketToken := Current()
        ConsumeToken(TokenType.LeftBracket, "Expected '['", "[")
        if !Check(TokenType.RightBracket) {
            elementsLooping := true
            while elementsLooping {
                ParseExprValue()
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    elementsLooping = false
                }
            }
        }
        ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
        return new ExprResult(new RecoverySpan(bracketToken.Line, bracketToken.Column, 1), false)
    }

    // Parser.cs ParseTupleOrParenthesizedExpression (:5428): empty tuple `()`, the recovery-boundary
    // `<error>`, single parenthesized `(e)`, named tuple `(a: x, b: y)`, or unnamed tuple `(a, b)`. Every
    // closing `)` routes through the Stage-9 recovery. A TupleExpression falls to the (parenLine, parenColumn,
    // 1) default; a ParenthesizedExpression carries its INNER expression's span (:5950).
    func ParseTupleOrParenthesizedExpression(): ExprResult {
        parenToken := Current()
        line := parenToken.Line
        column := parenToken.Column
        ConsumeToken(TokenType.LeftParen, "Expected '('", "(")

        // Empty tuple `()` (Parser.cs :5435).
        if Check(TokenType.RightParen) {
            Advance()
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        // Recovery boundary: a `)` cannot be reached on this construct (Parser.cs :5441). ConsumeToken here
        // takes the closing-delimiter recovery / standard path; the result is a ParenthesizedExpression whose
        // inner `<error>` span is (recoveredToken.Line, recoveredToken.Column, 1).
        if IsArgumentListRecoveryBoundaryWithOpening(Previous()) {
            recoveredToken := ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            return new ExprResult(new RecoverySpan(recoveredToken.Line, recoveredToken.Column, 1), false)
        }

        firstExpr := ParseExprValue()

        // Named tuple `(a: x, …)` — only when the first element is a bare identifier (Parser.cs :5454).
        if Check(TokenType.Colon) && firstExpr.IsBareIdentifier {
            Advance()
            ParseExprValue()                                // the first value
            while Check(TokenType.Comma) {
                Advance()
                ConsumeIdentifier("Expected identifier")    // Parser.cs :5465
                ConsumeToken(TokenType.Colon, "Expected ':'", ":")
                ParseExprValue()
            }
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        // Unnamed tuple `(a, b, …)` (Parser.cs :5476).
        if Check(TokenType.Comma) {
            while Check(TokenType.Comma) {
                Advance()
                ParseExprValue()
            }
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        // Parenthesized expression `(e)` (Parser.cs :5489). Its span is the inner expression's.
        ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        return new ExprResult(firstExpr.Span, false)
    }

    // ---- cast-detection lookahead (Parser.cs IsCastExpression :5573) ----
    // A pure bounded lookahead deciding whether the `(` at the cursor opens a cast `(Type)operand` rather
    // than a tuple / parenthesized expression. N# has no first-class Func values, so Parser.cs's nested
    // scan closures are lowered to methods over two explicit scan-state fields (ScanPosition, ScanSplit).
    // No cursor mutation, no diagnostics.
    func IsCastExpression(): bool {
        ScanPosition = Position + 1                         // skip '(' without mutating the parser cursor
        ScanSplit = 0
        if !ScanTypeReference() {
            return false
        }
        if ScanCurrentType() != TokenType.RightParen {
            return false
        }
        operandType := TokenType.Eof
        if ScanPosition + 1 < Tokens.Count {
            operandType = Tokens[ScanPosition + 1].Type
        }
        return ParserTokenFacts.IsCastOperandStart(operandType)
    }

    func ScanCurrentType(): TokenType {
        if ScanSplit > 0 {
            return TokenType.Greater
        }
        if ScanPosition < Tokens.Count {
            return Tokens[ScanPosition].Type
        }
        return TokenType.Eof
    }

    func ScanAdvance() {
        if ScanSplit > 0 {
            ScanSplit = ScanSplit - 1
            return
        }
        if ScanPosition < Tokens.Count {
            ScanPosition = ScanPosition + 1
        }
    }

    func ScanConsume(t: TokenType): bool {
        if ScanCurrentType() != t {
            return false
        }
        ScanAdvance()
        return true
    }

    func ScanConsumeGreater(): bool {
        if ScanCurrentType() == TokenType.Greater {
            ScanAdvance()
            return true
        }
        if ScanSplit == 0 && ScanPosition < Tokens.Count && Tokens[ScanPosition].Type == TokenType.RightShift {
            ScanPosition = ScanPosition + 1
            ScanSplit = ScanSplit + 1
            return true
        }
        return false
    }

    // Parser.cs ScanTypeReference (:5627): a postfix type reference plus `| T` union alternatives.
    func ScanTypeReference(): bool {
        if !ScanPostfixTypeReference() {
            return false
        }
        while ScanCurrentType() == TokenType.BitwiseOr {
            ScanAdvance()
            if !ScanPostfixTypeReference() {
                return false
            }
        }
        return true
    }

    // Parser.cs ScanPostfixTypeReference (:5642): a base type plus `[]` / `?` / `?[]` suffixes.
    func ScanPostfixTypeReference(): bool {
        if !ScanBaseTypeReference() {
            return false
        }
        suffixLooping := true
        while suffixLooping {
            if ScanCurrentType() == TokenType.LeftBracket && ScanPosition + 1 < Tokens.Count && Tokens[ScanPosition + 1].Type == TokenType.RightBracket {
                ScanAdvance()
                ScanAdvance()
            } else {
                if ScanCurrentType() == TokenType.Question {
                    ScanAdvance()
                } else {
                    if ScanCurrentType() == TokenType.QuestionBracket && ScanPosition + 1 < Tokens.Count && Tokens[ScanPosition + 1].Type == TokenType.RightBracket {
                        ScanAdvance()
                        ScanAdvance()
                    } else {
                        suffixLooping = false
                    }
                }
            }
        }
        return true
    }

    // Parser.cs ScanBaseTypeReference (:5679): `&T`, a parenthesized tuple type, or an identifier with
    // optional qualified `.` segments and a `<…>` generic argument list.
    func ScanBaseTypeReference(): bool {
        if ScanCurrentType() == TokenType.BitwiseAnd {
            ScanAdvance()
            return ScanPostfixTypeReference()
        }
        if ScanCurrentType() == TokenType.LeftParen {
            ScanAdvance()
            if ScanCurrentType() == TokenType.RightParen {
                return false
            }
            tupleLooping := true
            while tupleLooping {
                if ScanCurrentType() == TokenType.Identifier && ScanPosition + 1 < Tokens.Count && Tokens[ScanPosition + 1].Type == TokenType.Colon {
                    ScanAdvance()
                    ScanAdvance()
                }
                if !ScanTypeReference() {
                    return false
                }
                if !ScanConsume(TokenType.Comma) {
                    tupleLooping = false
                }
            }
            return ScanConsume(TokenType.RightParen)
        }
        if ScanCurrentType() != TokenType.Identifier {
            return false
        }
        ScanAdvance()
        while ScanConsume(TokenType.Dot) {
            if ScanCurrentType() != TokenType.Identifier {
                return false
            }
            ScanAdvance()
        }
        if ScanConsume(TokenType.Less) {
            if !ScanTypeReference() {
                return false
            }
            while ScanConsume(TokenType.Comma) {
                if !ScanTypeReference() {
                    return false
                }
            }
            if !ScanConsumeGreater() {
                return false
            }
        }
        return true
    }

    // ============================================================================
    // Stage 8: the MATCH / PATTERN diagnostic family (Stage-7's recorded cut B), carried through the SAME
    // shared-panic model. Reached as the keyword-led `match` primary (Parser.cs :4764), the MINIMAL match
    // vehicle Stage 7 deferred. The match value, each `when` guard, and each case body descend the full
    // ladder (ParseExprValue); the case loop makes progress via EnsureProgress but — unlike the union
    // per-case reset (Parser.cs :1216) or the object-initializer per-element reset (:5269/:5335) — does NOT
    // reset panic (Parser.cs :5399), so a pattern / arrow / comma error cascade-suppresses the rest of the
    // match until the enclosing statement / declaration boundary resets it (proven byte-exact: two bad
    // patterns in one match report ONCE; two separate match statements each report their first).
    //
    // Diagnostic sites carried:
    //   * MATCH — Consume(LeftBrace :5375 / Arrow :5391 / Comma :5397 / RightBrace :5402), all NL102/NL104.
    //   * PATTERN TERMINAL — ParsePrimaryPattern's "Invalid pattern. Got 'X'" (Parser.cs :3440, NL103).
    //   * QUALIFIED NAME — the pattern `A.B` ConsumeIdentifier("Expected identifier after '.'") (:3417).
    //   * PROPERTY PATTERNS — ParsePropertyPatterns' property-name ConsumeIdentifier (:3468, NL102/NL109)
    //     and the closing RightBrace (:3494).
    // Diagnostic CONSTRUCTION still delegates to the live shared ParserErrorDiagnostics.Create, and the
    // decisions reuse the live shared ParserTokenFacts / Lexer.IsReservedKeyword, so codes / messages /
    // spans / snippets / hints match automatically.
    //
    // DEFERRED (recorded, NOT covered — with reasons): the list `]` / positional `)` closes route through
    // TryReportMissingClosingDelimiter (RightBracket→NL108 / RightParen→NL107) — the closing-delimiter
    // recovery family, a later arc stage; ConsumeToken here reproduces the CLOSED (present-delimiter) case
    // byte-exact and the corpus keeps every list / positional / object pattern closed. The `is` / `as`
    // relational operators and the guard's own complex expressions reuse the Stage-7 ladder; the match value
    // and case bodies use only simple expressions in the corpus.
    // ============================================================================

    // Parser.cs ParseMatchExpression (:5368). Consume(Match) always succeeds (reached only under Check(Match)).
    func ParseMatchExpression(): ExprResult {
        matchToken := Current()
        line := matchToken.Line
        column := matchToken.Column
        Advance()                                   // consume 'match'

        ParseExprValue()                            // the match value (Parser.cs ParseExpression :5374)
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")

        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            ParsePattern()

            if Check(TokenType.When) {              // optional guard clause (Parser.cs :5386)
                Advance()
                ParseExprValue()
            }

            ConsumeToken(TokenType.Arrow, "Expected '=>'", "arrow")
            ParseExprValue()                        // the case body (Parser.cs :5392)

            if !Check(TokenType.RightBrace) {       // require a comma between cases (Parser.cs :5396)
                ConsumeToken(TokenType.Comma, "Expected ',' between match cases", ",")
            }

            EnsureProgress(startPosition)           // Parser.cs :5399 — NO panic reset per case
        }

        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
        // A MatchExpression's DiagnosticSpanFromExpression falls to the (line, column, 1) default (Parser.cs
        // :5960, anchored on the `match` keyword); it is never a bare identifier.
        return new ExprResult(new RecoverySpan(line, column, 1), false)
    }

    // Parser.cs EnsureProgress (:6709): force-advance one token when the enclosing loop consumed nothing, so
    // recovery cannot spin. The match-case (:5399) and property-pattern (:3491) loops call it.
    func EnsureProgress(startPosition: int): bool {
        if Position == startPosition {
            if !IsAtEnd() {
                Advance()
                return true
            }
        }
        return false
    }

    // ---- pattern grammar (Parser.cs ParsePattern :3263 → ParseOrPattern :3269 → ParseAndPattern :3285
    //      → ParseNotPattern :3301 → ParseRelationalPattern :3315 → ParsePrimaryPattern :3335) ----
    // The recovery model builds no AST, so each precedence tier only consumes its tokens and recurses; the
    // pattern DIAGNOSTICS all originate in ParsePrimaryPattern (the "Invalid pattern" terminal + the
    // qualified-name ConsumeIdentifier) and ParsePropertyPatterns.

    func ParsePattern() {
        ParseOrPattern()
    }

    func ParseOrPattern() {
        ParseAndPattern()
        while Check(TokenType.OrKeyword) {
            Advance()
            ParseAndPattern()
        }
    }

    func ParseAndPattern() {
        ParseNotPattern()
        while Check(TokenType.AndKeyword) {
            Advance()
            ParseNotPattern()
        }
    }

    func ParseNotPattern() {
        if Check(TokenType.NotKeyword) {
            Advance()
            ParseNotPattern()                       // recursive for multiple `not` (Parser.cs :3308)
            return
        }
        ParseRelationalPattern()
    }

    // Parser.cs ParseRelationalPattern (:3315): a leading comparison operator forms a relational pattern
    // whose value is a PRIMARY expression (:3328 — deliberately NOT the full ladder, so it does not consume
    // the next pattern's operators).
    func ParseRelationalPattern() {
        if Check(TokenType.Less) || Check(TokenType.Greater) || Check(TokenType.LessEqual) || Check(TokenType.GreaterEqual) || Check(TokenType.Equal) || Check(TokenType.NotEqual) {
            Advance()                               // the comparison operator
            ParsePrimaryExprValue()                 // the compared value (Parser.cs ParsePrimaryExpression)
            return
        }
        ParsePrimaryPattern()
    }

    // Parser.cs ParsePrimaryPattern (:3335): list `[…]`, positional `(…)`, literal, object `{…}`, and the
    // identifier-led union-case / type / qualified-name / identifier patterns, terminating in the
    // "Invalid pattern. Got 'X'" NL103. The list `]` / positional `)` closes route through
    // TryReportMissingClosingDelimiter (the deferred closing-delimiter family); ConsumeToken here reproduces
    // the CLOSED case byte-exact and the corpus keeps them closed.
    func ParsePrimaryPattern() {
        line := Current().Line
        column := Current().Column

        // List pattern `[p, .., p]` (Parser.cs :3341).
        if Check(TokenType.LeftBracket) {
            Advance()
            if !Check(TokenType.RightBracket) {
                listParsing := true
                while listParsing {
                    if Check(TokenType.DotDot) {
                        Advance()                   // slice `..` (optionally `.. name`)
                        if Check(TokenType.Identifier) {
                            Advance()
                        }
                    } else {
                        ParsePattern()
                    }
                    if Check(TokenType.Comma) {
                        Advance()
                    } else {
                        listParsing = false
                    }
                }
            }
            ConsumeToken(TokenType.RightBracket, "Expected ']' after list pattern", "]")
            return
        }

        // Positional (tuple) pattern `(p, p)` (Parser.cs :3376).
        if Check(TokenType.LeftParen) {
            Advance()
            if !Check(TokenType.RightParen) {
                positionalParsing := true
                while positionalParsing {
                    ParsePattern()
                    if Check(TokenType.Comma) {
                        Advance()
                    } else {
                        positionalParsing = false
                    }
                }
            }
            ConsumeToken(TokenType.RightParen, "Expected ')' after positional pattern", ")")
            return
        }

        // Literal pattern (Parser.cs :3394): the same primaries the malformed-literal check runs over.
        if Check(TokenType.IntLiteral) || Check(TokenType.CharLiteral) || Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral) || Check(TokenType.True) || Check(TokenType.False) || Check(TokenType.Null) {
            ParsePrimaryExprValue()
            return
        }

        // Object pattern without a type name `{ Prop: p }` (Parser.cs :3402).
        if Check(TokenType.LeftBrace) {
            ParsePropertyPatterns()
            return
        }

        // Identifier-led: qualified name → union-case / type / identifier pattern (Parser.cs :3409).
        if Check(TokenType.Identifier) {
            Advance()                               // first name segment
            while Check(TokenType.Dot) {            // qualified name `A.B.C` (Parser.cs :3414)
                Advance()
                ConsumeIdentifier("Expected identifier after '.'")
            }
            if Check(TokenType.LeftBrace) {         // union-case pattern with properties (Parser.cs :3421)
                ParsePropertyPatterns()
                return
            }
            if Check(TokenType.Identifier) {        // type pattern `TypeName binding` (Parser.cs :3429)
                Advance()
                return
            }
            return                                  // simple identifier pattern (Parser.cs :3437)
        }

        // Terminal (Parser.cs :3440): not a valid pattern. Does NOT advance (leaves the offender in place,
        // exactly as Parser.cs, so a following per-case Consume sees the same token under the same panic).
        suggestions := new List<string>()
        suggestions.Add("Literal pattern: case 5 => ...")
        suggestions.Add("Identifier pattern: case x => ...")
        suggestions.Add("Type pattern: case int x => ...")
        suggestions.Add("Object pattern: case { Name: \"John\" } => ...")
        Report(
            ErrorCode.InvalidSyntax,
            "Invalid pattern. Got '" + Current().Value + "'",
            line,
            column,
            "I couldn't recognize this as a valid pattern for matching.",
            "Patterns can be literals, identifiers, types, or destructuring patterns.",
            suggestions,
            Current().Value.Length)
    }

    // Parser.cs ParsePropertyPatterns (:3459): `{ Name: p, Other }`. Reached only when the caller has
    // already seen `{`, so the leading ConsumeToken(LeftBrace) always advances. The property-NAME site
    // funnels through ConsumeIdentifier (its reserved-keyword NL109 / found-other NL102 variants), and the
    // closing `}` through ConsumeToken(RightBrace), which takes the standard Consume path (RightBrace is NOT
    // in TryReportMissingClosingDelimiter) and consults GetHintForMissingToken(RightBrace).
    func ParsePropertyPatterns() {
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            ConsumeIdentifier("Expected property name")
            if Check(TokenType.Colon) {
                Advance()
                ParsePattern()
            }
            if !Check(TokenType.RightBrace) {
                if Check(TokenType.Comma) {         // Parser.cs Match(Comma) :3489 — optional separator
                    Advance()
                }
            }
            EnsureProgress(startPosition)
        }
        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
    }

    // ---- required-expression + operand boundary helpers (Parser.cs :3855 / :3928 / :6908) ----

    // Parser.cs ParseRequiredExpressionAfter (:3855). When the required expression is present, parse it;
    // otherwise report "Expected <what> after '<anchor>'" anchored on the provided span (or the anchor).
    func ParseRequiredExpressionAfter(anchorToken: Token, expectedDescription: string, ownerDescription: string, diagnosticSpan: RecoverySpan?) {
        if !IsMissingRequiredExpressionBoundary(anchorToken) {
            ParseExprValue()
            return
        }

        markerColumn := anchorToken.Column + MaxInt(1, anchorToken.Value.Length)
        underlineAnchor := ShouldUnderlineAnchorForMissingRequiredExpression(anchorToken)
        fallback := SpanFromToken(anchorToken)          // DiagnosticSpanFromToken(anchorToken)
        if !underlineAnchor {
            fallback = new RecoverySpan(anchorToken.Line, markerColumn, 1)
        }
        span := diagnosticSpan ?? fallback

        suggestions := new List<string>()
        suggestions.Add("Add " + expectedDescription + " after '" + anchorToken.Value + "'")
        suggestions.Add("Remove '" + anchorToken.Value + "' until the expression is ready")
        Report(
            ErrorCode.ExpectedToken,
            "Expected " + expectedDescription + " after '" + anchorToken.Value + "'",
            span.Line,
            span.Column,
            ownerDescription + " needs " + expectedDescription + " after '" + anchorToken.Value + "'.",
            "Finish the expression before starting the next statement.",
            suggestions,
            span.Length)
    }

    // Parser.cs ShouldUnderlineAnchorForMissingRequiredExpression (:3887).
    func ShouldUnderlineAnchorForMissingRequiredExpression(anchorToken: Token): bool {
        t := anchorToken.Type
        if t == TokenType.If {
            return true
        }
        if t == TokenType.While {
            return true
        }
        if t == TokenType.Foreach {
            return true
        }
        if t == TokenType.Switch {
            return true
        }
        if t == TokenType.Print {
            return true
        }
        if t == TokenType.Throw {
            return true
        }
        if t == TokenType.Yield {
            return true
        }
        if t == TokenType.Assert {
            return true
        }
        if t == TokenType.Using {
            return true
        }
        if t == TokenType.Lock {
            return true
        }
        if t == TokenType.In {
            return true
        }
        if t == TokenType.Assign {
            return true
        }
        if t == TokenType.ColonAssign {
            return true
        }
        return false
    }

    // Parser.cs IsMissingRequiredExpressionBoundary (:3928).
    func IsMissingRequiredExpressionBoundary(anchorToken: Token): bool {
        if IsMissingOperandBoundary(anchorToken) {
            return true
        }
        if Current().Line > anchorToken.Line && LooksLikeStatementStartAfterRequiredExpression() {
            return true
        }
        if Current().Line == anchorToken.Line {
            if Check(TokenType.LeftBrace) {
                return true
            }
            if Check(TokenType.RightBrace) {
                return true
            }
            if Check(TokenType.RightParen) {
                return true
            }
            if Check(TokenType.RightBracket) {
                return true
            }
            if Check(TokenType.Colon) {
                return true
            }
            if Check(TokenType.Comma) {
                return true
            }
            if Check(TokenType.Semicolon) {
                return true
            }
        }
        return false
    }

    // Parser.cs LooksLikeStatementStartAfterRequiredExpression (:3946).
    func LooksLikeStatementStartAfterRequiredExpression(): bool {
        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.ColonAssign {
            return true
        }
        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon && LookAhead(2).Type == TokenType.Identifier {
            return true
        }
        return StartsTupleDeconstructionAtCurrentPosition()
    }

    // Parser.cs StartsTupleDeconstructionAtCurrentPosition (:3985).
    func StartsTupleDeconstructionAtCurrentPosition(): bool {
        if !Check(TokenType.Identifier) || LookAhead(1).Type != TokenType.Comma {
            return false
        }
        pos := 1
        while Position + pos < Tokens.Count {
            token := Tokens[Position + pos]
            if token.Line != Current().Line {
                return false
            }
            if token.Type == TokenType.ColonAssign || token.Type == TokenType.Assign {
                return true
            }
            if token.Type != TokenType.Identifier && token.Type != TokenType.Comma {
                return false
            }
            pos = pos + 1
        }
        return false
    }

    // Parser.cs IsMissingOperandBoundary (:6908): the operator's right operand is missing at end of file,
    // at an expression terminator, or — on a LATER line — at a statement/declaration/modifier keyword or a
    // token at/left of the current statement's recovery-boundary column.
    func IsMissingOperandBoundary(operatorToken: Token): bool {
        if IsAtEnd() {
            return true
        }
        if ParserTokenFacts.IsExpressionTerminator(Current().Type) {
            return true
        }
        if Current().Line <= operatorToken.Line {
            return false
        }
        if ParserTokenFacts.IsStatementStartKeyword(Current().Type) {
            return true
        }
        if ParserTokenFacts.IsDeclarationKeyword(Current().Type) {
            return true
        }
        if ParserTokenFacts.IsModifierKeyword(Current().Type) {
            return true
        }
        if HasRecoveryBoundaryColumn && Current().Column <= RecoveryBoundaryColumn {
            return true
        }
        return false
    }

    func IntToString(value: int): string {
        return value.ToString()
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

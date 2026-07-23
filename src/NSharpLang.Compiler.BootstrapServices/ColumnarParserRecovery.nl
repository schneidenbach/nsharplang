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
    Errors: List<CompilerError>

    constructor(source: string, fileName: string?) {
        Source = source
        FileName = fileName
        Position = 0
        PanicMode = false
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
        return Current().Type == tokenType
    }

    func Advance(): Token {
        if !IsAtEnd() {
            Position = Position + 1
        }
        return Tokens[Position - 1]
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

        // Declaration boundary. Stage 1 reproduces the panic reset (Parser.cs :83) and the
        // terminal unexpected-top-level-token arm (Parser.cs ParseDeclaration, :241). It
        // stops at the first real declaration introducer; later arc stages parse declaration
        // bodies and add their own sync-point recovery.
        while !IsAtEnd() {
            PanicMode = false
            if IsDeclarationStart(Current()) {
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
    }

    func IsDeclarationStart(token: Token): bool {
        t := token.Type
        if ParserTokenFacts.IsDeclarationKeyword(t) {
            return true
        }
        if ParserTokenFacts.IsModifierKeyword(t) {
            return true
        }
        if t == TokenType.Public {
            return true
        }
        if t == TokenType.Private {
            return true
        }
        if t == TokenType.LeftBracket {
            return true
        }
        if t == TokenType.PreprocessorDirective {
            return true
        }
        return IsContextualDeclarationStart(token)
    }

    func IsContextualDeclarationStart(token: Token): bool {
        if token.Type != TokenType.Identifier {
            return false
        }
        if token.Value == "test" {
            return true
        }
        if token.Value == "setup" {
            return true
        }
        if token.Value == "teardown" {
            return true
        }
        return false
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

namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Ast

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

// Stage N+1 (the AST/facts BRIDGE, first increment): the recovery owner's file-preamble output
// as PRODUCTION Ast node instances plus the owned diagnostics — the shape a consumer reads from
// Parser.cs's ParseResult.CompilationUnit for the preamble portion (Namespace / Imports / Package)
// alongside ParseResult.Errors.
//
// These three node fields are the production Ast types NSharpLang.Compiler.Ast.NamespaceDeclaration
// / ImportDirective / PackageDeclaration — already N# and owned in THIS assembly (FileHeaderDeclarations.nl,
// ImportDirective.nl), so the recovery owner constructs the SAME instances Parser.cs constructs
// (Parser.cs :71/:127/:136). The remaining CompilationUnit surface — the CompilationUnit container
// itself, the FileImports list (FileImport/NamespaceImport), and the Declarations list — is C# in the
// downstream NSharpLang.Compiler assembly (Ast/Declarations.cs, Ast/Statements.cs), which this
// upstream assembly cannot name (the dependency runs Compiler → BootstrapServices, never the reverse),
// so it is NOT constructed here; see the STATUS N+1 block record. Errors mirror ParseFilePreamble's
// position-sorted diagnostics exactly.
public class PreambleAst {
    Namespace: NamespaceDeclaration?
    Imports: List<ImportDirective>
    Package: PackageDeclaration?
    Errors: List<CompilerError>

    constructor(
        namespaceDecl: NamespaceDeclaration?,
        imports: List<ImportDirective>,
        packageDecl: PackageDeclaration?,
        errors: List<CompilerError>) {
        Namespace = namespaceDecl
        Imports = imports
        Package = packageDecl
        Errors = errors
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
    // Stage N+1 (AST bridge): the preamble AST nodes materialized during Run(), mirroring the
    // instances Parser.cs's ParseCompilationUnit accumulates (:37/:45/:47). Populated as a pure
    // side-effect of the existing preamble grammar, so the diagnostic-only ParseFilePreamble path is
    // unaffected. NamespaceNode/PackageNode default absent; ImportNodes only the NAMESPACE imports
    // (Parser.cs :69-72 — file imports go to the downstream FileImports list, not built here).
    NamespaceNode: NamespaceDeclaration?
    ImportNodes: List<ImportDirective>
    PackageNode: PackageDeclaration?
    // Stage N+1c (full-tree AST materialization, tranche 1): the remaining CompilationUnit surface the
    // owner now constructs — the file-import statements (Parser.cs :73-76 routes each FileImport to the
    // downstream FileImports list) and the top-level declaration nodes (Parser.cs :80-90). Populated as a
    // pure side-effect of the existing grammar exactly like the preamble nodes, so the diagnostic-only path
    // is unperturbed. UnitLine/UnitColumn capture the first token's position (Parser.cs :33-34), the
    // CompilationUnit's Line/Column.
    FileImportNodes: List<Statement>
    DeclarationNodes: List<Declaration>
    UnitLine: int
    UnitColumn: int
    // Stage N+1c tranche 3 (members): a nesting-safe stack of the member list currently being filled. A
    // type body pushes a fresh member list on entry and pops it on exit; AddDeclaration targets the stack
    // top when non-empty (the enclosing type's Members), else the top-level DeclarationNodes. This places a
    // NESTED type declaration in its enclosing type's Members rather than at the top level. The `> >` space
    // is the standard `>>`-tokenizer workaround for a nested-generic type.
    TypeMemberStack: List<List<Declaration> >
    // Stage N+1c tranche 4 (modifiers + primary-ctor params): transient no-stub materialization gates,
    // set by the sub-parsers and captured by the caller into a local IMMEDIATELY. ParamListMaterializable
    // is cleared by ParseParameterListRecovery when a primary-ctor parameter is not byte-exactly
    // representable (a non-simple type, a default value, a modifier/this, or an attribute), so the enclosing
    // declaration declines materialization rather than emitting a partial parameter list. AttributesMaterializable
    // is cleared by ParseAttributes when an attribute carries arguments (Argument/Expression nodes are a later
    // tranche) or its name is `<error>`, so the enclosing declaration declines rather than emitting an
    // argument-free attribute node where Parser.cs would carry arguments.
    ParamListMaterializable: bool
    AttributesMaterializable: bool

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
        NamespaceNode = null
        ImportNodes = new List<ImportDirective>()
        PackageNode = null
        FileImportNodes = new List<Statement>()
        DeclarationNodes = new List<Declaration>()
        UnitLine = 0
        UnitColumn = 0
        TypeMemberStack = new List<List<Declaration> >()
        ParamListMaterializable = true
        AttributesMaterializable = true

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
    // shared-panic model. Returns the diagnostics position-sorted, matching the order the
    // CLI check pipeline presents them (OutputFormatter.DeduplicateAndSortDiagnostics →
    // CodeIntelligenceResultKernels.DiagnosticIndexComesAfter: File, Line, Column, stable).
    // Parser recording order is source order EXCEPT where a nested sub-parse records a hole
    // diagnostic before a following outer-expression diagnostic that is positioned earlier
    // (Stage 12 interpolation), so the sort is what the byte-exact oracle comparison needs;
    // it is a stable no-op for every already-in-order family (Stages 1-11).
    public static func ParseFilePreamble(source: string, fileName: string?): List<CompilerError> {
        recovery := new ColumnarParserRecovery(source, fileName)
        recovery.Run()
        return recovery.SortErrorsByPosition(recovery.Errors)
    }

    // Stage N+1 (AST bridge, first increment): parse the file preamble and return the PRODUCTION
    // Ast node instances (Namespace / Imports / Package) the recovery owner can construct in this
    // assembly, alongside the position-sorted owned diagnostics. This is the first consumer-shaped
    // fact surface the owner produces beyond diagnostics — the same Namespace / Imports / Package
    // subtree Parser.cs hangs on ParseResult.CompilationUnit, built through the identical grammar and
    // node constructors. The CompilationUnit container + FileImports + Declarations remain downstream
    // C# (see PreambleAst) and are the recorded N+1 block.
    public static func ParseFilePreambleAst(source: string, fileName: string?): PreambleAst {
        recovery := new ColumnarParserRecovery(source, fileName)
        recovery.Run()
        return new PreambleAst(
            recovery.NamespaceNode,
            recovery.ImportNodes,
            recovery.PackageNode,
            recovery.SortErrorsByPosition(recovery.Errors))
    }

    // Stage N+1c (full-tree AST materialization): parse a WHOLE file and return the production
    // `CompilationUnit` the owner constructs — the same container Parser.cs's ParseCompilationUnit
    // hangs on ParseResult.CompilationUnit (:111), assembled from the preamble nodes, the file-import
    // statements, and the top-level declaration nodes materialized as a side-effect of the recovery
    // grammar. Line/Column are the first-token position (Parser.cs :33-34). This is a TEST-ONLY entry
    // (consumed only by the AST-bridge parity contracts); Parser.cs remains the sole production authority
    // until the N+2 cutover. Tranche 1 materializes the container + FileImports + the empty-body top-level
    // type declarations; the remaining families (functions/members/statements/expressions) are later
    // tranches, so a whole-file CompilationUnit is byte-stable to Parser.cs only over the tranche corpus.
    public static func ParseFileAst(source: string, fileName: string?): CompilationUnit {
        recovery := new ColumnarParserRecovery(source, fileName)
        recovery.Run()
        return new CompilationUnit(
            recovery.NamespaceNode,
            recovery.ImportNodes,
            recovery.FileImportNodes,
            recovery.PackageNode,
            recovery.DeclarationNodes,
            recovery.UnitLine,
            recovery.UnitColumn)
    }

    // Stable insertion sort by (Line, Column), mirroring the CLI's DiagnosticIndexComesAfter (the File
    // component is constant within a single-file preamble parse, so it is not compared here). Ties preserve
    // recording order, exactly as the CLI's stable sort does.
    func SortErrorsByPosition(errors: List<CompilerError>): List<CompilerError> {
        indices := new List<int>()
        k := 0
        while k < errors.Count {
            indices.Add(k)
            k = k + 1
        }
        i := 1
        while i < indices.Count {
            current := indices[i]
            j := i - 1
            keepMoving := true
            while j >= 0 && keepMoving {
                if ErrorComesAfter(errors, indices[j], current) {
                    indices[j + 1] = indices[j]
                    j = j - 1
                } else {
                    keepMoving = false
                }
            }
            indices[j + 1] = current
            i = i + 1
        }
        sorted := new List<CompilerError>()
        m := 0
        while m < indices.Count {
            sorted.Add(errors[indices[m]])
            m = m + 1
        }
        return sorted
    }

    func ErrorComesAfter(errors: List<CompilerError>, leftIndex: int, rightIndex: int): bool {
        left := errors[leftIndex]
        right := errors[rightIndex]
        if left.Line != right.Line {
            return left.Line > right.Line
        }
        if left.Column != right.Column {
            return left.Column > right.Column
        }
        return leftIndex > rightIndex
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

    // Mirrors Parser.cs ParseQualifiedName (:179): the dot-joined identifier chain. Returns the
    // joined name so the AST-bridge preamble nodes carry the same string Parser.cs's
    // `string.Join(".", parts)` produces (identical on the well-formed path the AST corpus pins;
    // the diagnostic sequence is bit-identical to the previous void form — same ConsumeIdentifier
    // calls in the same order).
    func ParseQualifiedName(): string {
        name := ConsumeIdentifier("Expected identifier")
        while Check(TokenType.Dot) {
            Advance()
            name = name + "." + ConsumeIdentifier("Expected identifier after '.'")
        }
        return name
    }

    func ParseNamespace() {
        // The `namespace` keyword presence is guaranteed by the Check at the call site,
        // exactly as Parser.cs's guarded Consume(Namespace). Capture the keyword position BEFORE
        // consuming it, matching Parser.cs's line/column anchoring (:123-127).
        line := Current().Line
        column := Current().Column
        Advance()
        name := ParseQualifiedName()
        NamespaceNode = new NamespaceDeclaration(name, line, column)
    }

    func ParsePackage() {
        line := Current().Line
        column := Current().Column
        Advance()
        name := ParseQualifiedName()
        PackageNode = new PackageDeclaration(name, line, column)
    }

    func ParseImport() {
        line := Current().Line
        column := Current().Column
        Advance()

        // File-based import: import "path/to/file" [as Alias]. Parser.cs builds a FileImport here
        // (:159-163) and routes it to the FileImports list (:75). N+1c materializes it: the path is the
        // string-literal value with its surrounding quotes trimmed, PathColumn/PathLength anchor the raw
        // literal token, and Line/Column anchor the `import` keyword (captured above).
        if Check(TokenType.StringLiteral) {
            pathToken := Advance()
            path := TrimQuotes(pathToken.Value)
            alias: string? = null
            if Check(TokenType.As) {
                Advance()
                alias = ConsumeIdentifier("Expected alias name after 'as'")
            }
            fileImport := new FileImport(path, alias, line, column)
            fileImport.PathColumn = pathToken.Column
            fileImport.PathLength = MaxInt(1, pathToken.Value.Length)
            FileImportNodes.Add(fileImport)
            return
        }

        // Namespace import: import System.Collections.Generic [as Alias]. Parser.cs materializes this
        // as an ImportDirective anchored on the `import` keyword (:71 — nsImport.Line/Column = the
        // import-keyword position captured above).
        name := ParseQualifiedName()
        alias: string? = null
        if Check(TokenType.As) {
            Advance()
            alias = ConsumeIdentifier("Expected alias name after 'as'")
        }
        ImportNodes.Add(new ImportDirective(name, alias, line, column))
    }

    func Run() {
        // The CompilationUnit's Line/Column are the first token's position, captured BEFORE any parsing
        // (Parser.cs ParseCompilationUnit :33-34).
        UnitLine = Current().Line
        UnitColumn = Current().Column

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
        // Stage 16: the contextual test-DSL declarations (Parser.cs ParseDeclaration :192-202) are
        // dispatched BEFORE attributes/modifiers, so each is its own top-level declaration and
        // participates in the declaration-boundary panic reset (Run's per-iteration PanicMode reset).
        if IsTestDeclarationStart() {
            ParseTestDeclaration()
            return
        }
        if IsSetupDeclarationStart() {
            ParseSetupDeclaration()
            return
        }
        if IsTeardownDeclarationStart() {
            ParseTeardownDeclaration()
            return
        }

        // Top-level preprocessor directive (Parser.cs :205): a bare advance, no diagnostic.
        if Check(TokenType.PreprocessorDirective) {
            Advance()
            return
        }

        // Attributes precede modifiers (Parser.cs :214). Both are captured (attributes as a real
        // AttributeNode list, attrsOk = whether every attribute was byte-exactly materializable) and threaded
        // into the materializing name parsers (Stage N+1c tranche 4). ParseModifiers now returns the exact
        // Modifiers value Parser.cs :215 hangs on the declaration node.
        attributes := ParseAttributes()
        attrsOk := AttributesMaterializable
        modifiers := ParseModifiers()

        if Check(TokenType.Func) {
            ParseFunctionName()
            return
        }
        if Check(TokenType.Class) {
            ParseClassName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Ref) {
            if LookAhead(1).Type == TokenType.Struct {
                Advance()
                ParseStructName(modifiers, attributes, attrsOk)
                return
            }
        }
        if Check(TokenType.Struct) {
            ParseStructName(modifiers, attributes, attrsOk)
            return
        }
        if IsSoaRecordDeclarationStart() {
            ParseSoaRecordName()
            return
        }
        if Check(TokenType.Record) {
            ParseRecordName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Interface) {
            ParseInterfaceName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Duck) {
            if LookAhead(1).Type == TokenType.Interface {
                ParseInterfaceName(modifiers, attributes, attrsOk)
                return
            }
        }
        if Check(TokenType.Union) {
            ParseUnionName()
            return
        }
        if Check(TokenType.Enum) {
            ParseEnumName(modifiers, attributes, attrsOk)
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

    // Consume leading modifier keywords (Parser.cs ParseModifiers, :298) so a modifier-led declaration
    // reaches its keyword, and RETURN the byte-exact Modifiers value Parser.cs hangs on the declaration node.
    // The flags are accumulated as an int bitmask and cast back with `(Modifiers)value` — the emittable idiom
    // (DeclarationFacts.nl :52 / TypeInfoFactories.nl :938; enum bitwise operators route through the C# fenced
    // residual and are avoided in dogfood N#). The VALUE set exactly mirrors Parser.cs's recognized flags and
    // order (Public/Private/Static/Internal/Protected/Virtual/Override/Abstract/Sealed/Partial/Async/File);
    // Readonly (which Parser.cs's ParseModifiers never maps — Const/Readonly/Required/Init/Generator are set
    // elsewhere) is still CONSUMED for recovery robustness via IsModifierKeyword but contributes NO flag,
    // keeping the token consumption identical to the prior owner while the value matches Parser.cs.
    func ParseModifiers(): Modifiers {
        value := 0
        scanning := true
        while scanning {
            t := Current().Type
            flag := ModifierFlagOrZero(t)
            if flag != 0 {
                value = value | flag
                Advance()
            } else if t == TokenType.Public {
                value = value | System.Convert.ToInt32(Modifiers.Public)
                Advance()
            } else if t == TokenType.Private {
                value = value | System.Convert.ToInt32(Modifiers.Private)
                Advance()
            } else if ParserTokenFacts.IsModifierKeyword(t) {
                // A modifier keyword Parser.cs's ParseModifiers does not map to a flag (Readonly): consumed
                // for recovery, no flag contribution.
                Advance()
            } else {
                scanning = false
            }
        }
        return (Modifiers)value
    }

    // The Parser.cs ParseModifiers flag for a modifier token, or 0 when the token is not one of the flags
    // ParseModifiers maps (Public/Private are handled by the caller since they are checked before
    // IsModifierKeyword in the owner's dispatch order).
    func ModifierFlagOrZero(t: TokenType): int {
        if t == TokenType.Static { return System.Convert.ToInt32(Modifiers.Static) }
        if t == TokenType.Internal { return System.Convert.ToInt32(Modifiers.Internal) }
        if t == TokenType.Protected { return System.Convert.ToInt32(Modifiers.Protected) }
        if t == TokenType.Virtual { return System.Convert.ToInt32(Modifiers.Virtual) }
        if t == TokenType.Override { return System.Convert.ToInt32(Modifiers.Override) }
        if t == TokenType.Abstract { return System.Convert.ToInt32(Modifiers.Abstract) }
        if t == TokenType.Sealed { return System.Convert.ToInt32(Modifiers.Sealed) }
        if t == TokenType.Partial { return System.Convert.ToInt32(Modifiers.Partial) }
        if t == TokenType.Async { return System.Convert.ToInt32(Modifiers.Async) }
        if t == TokenType.File { return System.Convert.ToInt32(Modifiers.File) }
        return 0
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

    func ParseParameterListRecovery(): List<Parameter> {
        // Minimal recovery vehicle. The params/ref/out/this modifiers, scoped/lifetime annotations,
        // default values, and the IsParameterListRecoveryBoundary early break are LATER arc stages; the
        // member/parameter corpus uses none of them. Stage 16 carries the per-parameter attribute list
        // (Parser.cs :770). Stage 9 carries the trailing-comma recovery (Parser.cs :761) and routes the
        // closing ')' through ConsumeToken so the missing-')' closing-delimiter recovery (NL107) is reachable.
        // Stage N+1c tranche 4: MATERIALIZE each parameter as a byte-exact `Parameter` node (Parser.cs :811),
        // a PURE side-effect of the existing diagnostic parse. `ParamListMaterializable` is cleared when the
        // list is not byte-exactly representable (an error/missing name, a non-simple type, a per-parameter
        // attribute, a trailing default `=`, or the trailing-comma recovery), so the caller declines the whole
        // declaration rather than comparing a partial list. Non-corpus modifier/this/scoped shapes surface as
        // an `<error>` name (a leading `ref`/`out`/`this` is a reserved keyword to ConsumeNameWithSpan), which
        // the name-error guard already declines.
        ParamListMaterializable = true
        paramNodes := new List<Parameter>()
        if !Check(TokenType.LeftParen) {
            return paramNodes
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
                    ParamListMaterializable = false     // trailing-comma malformed list → decline
                    parsing = false
                } else {
                    // Per-parameter attributes (Parser.cs :770), before the modifier/name.
                    paramAttrs := ParseAttributes()
                    paramStartToken := Current()
                    paramLine := Current().Line
                    paramColumn := Current().Column
                    paramName := ConsumeNameWithSpan("Expected parameter name", GetMissingParameterNameDiagnosticSpan())
                    ConsumeParameterColon(paramName, paramLine, paramColumn)
                    paramType := ParseParameterTypeReference(paramName, paramLine, paramColumn)

                    if paramName != "<error>" {
                        lastParameterStartToken = paramStartToken
                    }

                    // Materialize the byte-exact Parameter (Parser.cs :811) for the simple corpus shape:
                    // a non-error name, a single-token SimpleTypeReference (paramType non-null), no per-parameter
                    // attribute, and no trailing default `=`. DefaultValue null / IsThis false /
                    // ParameterModifier.None / null Attributes / IsScoped false / null Lifetime — the values the
                    // owner's diagnostic parse (which does not consume modifiers/this/defaults) leaves at their
                    // corpus defaults. Line/Column anchor the parameter name (Parser.cs :796-797).
                    if paramName != "<error>" && paramType != null && paramAttrs.Count == 0 && !Check(TokenType.Assign) {
                        paramNodes.Add(new Parameter(
                            paramName, paramType, null, false, ParameterModifier.None,
                            null, paramLine, paramColumn, false, null))
                    } else {
                        ParamListMaterializable = false
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
        return paramNodes
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

    // Parser.cs ParseParameterTypeReference (:6504). Consumes a full type reference (Parser.cs :6507
    // `ParseTypeReference()` — the Stage-15 union / postfix / byref / tuple / Func grammar), or reports
    // the missing-type diagnostic anchored on the parameter name when a type terminator sits where the
    // type should be. Stage N+1c tranche 5: RETURN the byte-exact materialized type node through the shared
    // ParseMaterializedTypeReference gate — the FULL stage-15 grammar (simple / qualified / generic / array /
    // nullable / tuple / Func / union / byref), each construction byte-exact to Parser.cs. Only a malformed,
    // multi-line, or in-panic parse defers (null → the caller declines to materialize the parameter, no-stub).
    func ParseParameterTypeReference(parameterName: string, parameterLine: int, parameterColumn: int): TypeReference? {
        if !IsTypeTerminator(Current().Type) {
            return ParseMaterializedTypeReference()
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
        return null
    }

    // ---- braced type body → member list → field family (Parser.cs :1359/:1412/:1637) ----

    // Parse a class/struct/record/interface type body (Parser.cs :970-971): the body is ALWAYS
    // parsed — Consume the '{' (present → advance; absent mid-line → the standard ExpectedToken
    // NL102; absent at EOF → the ExpectedEndOfFile NL104; suppressed when a prior name error already
    // set panic) then ParseMemberList. A '<error>'-named type whose offending token is '{'
    // (`class {` / `struct {`, Stage 4) consumes that '{' as the opening brace; a '<error>'-named
    // type whose offender is NON-'{' (`class 5` / `struct 5`, Stage-17 residual [5]) leaves the
    // offender for ParseMemberList, which reports the in-body field-name error(s) plus the type-body
    // missing-'}' NL106 (its shared-panic reset in ParseMemberList lets both record). The
    // ParseFilePreamble position-sort (Stage 12) orders the emitted diagnostics to the CLI's display
    // order: for `class 5` the class-name NL102 and the missing-'}' NL106 both anchor at the class
    // keyword (column-tie, stable by emission order) and precede the in-body field-name NL102.
    // Stage N+1c tranche 3 (members): route a declaration node to the member list of the type currently
    // being parsed (the stack top), or the top-level DeclarationNodes when no type body is open. Replaces
    // the direct `DeclarationNodes.Add(...)`, so a NESTED type/member lands in its enclosing type's Members.
    func AddDeclaration(node: Declaration) {
        if TypeMemberStack.Count > 0 {
            TypeMemberStack[TypeMemberStack.Count - 1].Add(node)
        } else {
            DeclarationNodes.Add(node)
        }
    }

    // Stage N+1c tranche 3 (members): ParseTypeBody now RETURNS the member list it parsed, so each type
    // name parser can hang a POPULATED Members list on its declaration node. A fresh list is pushed as the
    // active member target for the duration of the body (so members + nested types append to it) and popped
    // on exit, restoring the enclosing type's target for NESTED-type placement.
    func ParseTypeBody(name: string, typeBodyDiagnosticSpan: RecoverySpan): List<Declaration> {
        members := new List<Declaration>()
        TypeMemberStack.Add(members)
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        ParseMemberList(typeBodyDiagnosticSpan)
        TypeMemberStack.RemoveAt(TypeMemberStack.Count - 1)
        return members
    }

    // Parser.cs ParseMemberList (:1359): reset panic at each MEMBER boundary (:1365), track the
    // member's start column as the recovery boundary (:1367-1376), parse one member, and on no
    // progress synchronize then force-advance (:1379). Stage 14 dispatches the FULL member grammar
    // (ParseMemberDeclaration); Stage 4 parsed FIELD members only. Stage 9 carries the type-body
    // end-of-file missing-'}' (NL106) report (:1396), anchored on the type-body diagnostic span (the
    // type name, or the declaration keyword for a '<error>' name).
    func ParseMemberList(ownerSpan: RecoverySpan?) {
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            PanicMode = false                   // reset at each member boundary (Parser.cs :1365)
            SplitGreaterDepth = 0
            startPosition := Position
            // The member's start column is the recovery boundary for its own body/initializer
            // expression recovery (Parser.cs :1367-1376, saved/restored around ParseMemberDeclaration).
            prevBoundary := RecoveryBoundaryColumn
            prevHasBoundary := HasRecoveryBoundaryColumn
            RecoveryBoundaryColumn = Current().Column
            HasRecoveryBoundaryColumn = true
            ParseMemberDeclaration()
            RecoveryBoundaryColumn = prevBoundary
            HasRecoveryBoundaryColumn = prevHasBoundary

            // No-progress guard (Parser.cs :1379-1388): synchronize, then force-advance.
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
    // :1666 (a field name is never a dot-access, so its plain message variants apply). Stage 14 carries the
    // property forms: the leading required/init/readonly modifiers, the expression-bodied `=> expr` property,
    // and the `{ get/set }` accessor block (with its "Expected 'get' or 'set'" reports).
    func ParseFieldMember() {
        line := Current().Line
        column := Current().Column

        // Property modifiers required/init/readonly (Parser.cs :1644) — combinable, no diagnostic. Seeing
        // any is a tranche-4 shape (PropertyModifier/Modifiers materialization) — decline the field node.
        propModifierSeen := false
        scanningPropModifiers := true
        while scanningPropModifiers {
            if Check(TokenType.Required) || Check(TokenType.Init) || Check(TokenType.Readonly) {
                propModifierSeen = true
                Advance()
            } else {
                scanningPropModifiers = false
            }
        }

        name := ConsumeIdentifier("Expected field name")

        // Type inference `Name := value` (Parser.cs :1670) — an initializer expression, a later tranche.
        if Check(TokenType.ColonAssign) {
            Advance()
            ParseExprValue()
            return
        }

        fieldColonToken := ConsumeFieldColon(name, line, column)
        fieldType := ParseFieldTypeReference(name, line, column, fieldColonToken)

        // Expression-bodied property `name: type => expr` (Parser.cs :1683) — a PropertyDeclaration whose
        // ExpressionBody is a later tranche.
        if Check(TokenType.Arrow) {
            Advance()
            ParseExprValue()
            return
        }

        // Property with `{ get/set }` accessors (Parser.cs :1691).
        if Check(TokenType.LeftBrace) {
            Advance()                           // consume '{'
            while !Check(TokenType.RightBrace) && !IsAtEnd() {
                if Check(TokenType.Identifier) {
                    accessorLine := Current().Line
                    accessorColumn := Current().Column
                    accessor := Current().Value
                    Advance()
                    accessorSpan := new RecoverySpan(accessorLine, accessorColumn, MaxInt(1, accessor.Length))
                    if accessor == "get" {
                        ParseBlock(accessorSpan)
                    } else {
                        if accessor == "set" {
                            ParseBlock(accessorSpan)
                        } else {
                            ReportPropertyAccessorInvalidIdentifier(accessor)
                            // Skip to the next accessor or the closing brace (Parser.cs :1732).
                            while !Check(TokenType.RightBrace) && !Check(TokenType.Identifier) && !IsAtEnd() {
                                Advance()
                            }
                        }
                    }
                } else {
                    ReportPropertyAccessorExpectedGetSet()
                    Advance()                   // skip the invalid token (Parser.cs :1752)
                }
            }
            ConsumeToken(TokenType.RightBrace, "Expected '}' after property accessors", "}")
            return
        }

        // Field `= initializer` (Parser.cs :1762) — the initializer expression is a later tranche, so a
        // field WITH one is not yet byte-exact; parse it (diagnostics) but decline to materialize the node.
        if Check(TokenType.Assign) {
            initializerToken := Advance()
            ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This field declaration", null)
            return
        }

        // N+1c tranche 3: materialize the plain FieldDeclaration for the initializer-free `name: <simple
        // type>` corpus (Parser.cs :1771 — `new FieldDeclaration(name, type, initializer, modifiers,
        // propertyModifier, attributes, line, column)`). Only within the materialized subset: no property
        // modifiers (Modifiers.None / PropertyModifier.None / no attributes), a single-token simple type
        // (fieldType non-null), and no initializer (guarded by the returns above). Line/Column anchor the
        // field-name start (Parser.cs :1639-1640 capture Current before the name). FQN'd — a test-helper
        // `class FieldDeclaration` in NSharpLang.Compiler collides under the tests-enabled build.
        // AddDeclaration routes the field into the enclosing type's Members.
        if !propModifierSeen && fieldType != null {
            AddDeclaration(new NSharpLang.Compiler.Ast.FieldDeclaration(
                name, fieldType, null, Modifiers.None, PropertyModifier.None,
                new List<AttributeNode>(), line, column))
        }
    }

    // Parser.cs ParseFieldDeclaration accessor error (:1718): an identifier that is neither 'get' nor
    // 'set'. Anchored on the CURRENT token (Parser.cs advances past the bad accessor first) but sized to
    // the bad accessor's length.
    func ReportPropertyAccessorInvalidIdentifier(accessor: string) {
        suggestions := new List<string>()
        suggestions.Add("Example: get { return _value; }")
        suggestions.Add("Example: set { _value = value; }")
        Report(
            ErrorCode.ExpectedToken,
            "Expected 'get' or 'set' accessor, got '" + accessor + "'",
            Current().Line,
            Current().Column,
            "Property accessors must be either 'get' (for reading) or 'set' (for writing).",
            "Use 'get' to define how to retrieve the property value, or 'set' to define how to assign a new value.",
            suggestions,
            accessor.Length)
    }

    // Parser.cs ParseFieldDeclaration accessor error (:1738): a non-identifier where an accessor is
    // required. Anchored on and sized to the offending token.
    func ReportPropertyAccessorExpectedGetSet() {
        suggestions := new List<string>()
        suggestions.Add("Add a 'get' accessor to make the property readable")
        suggestions.Add("Add a 'set' accessor to make the property writable")
        suggestions.Add("Example: { get { return _value; } set { _value = value; } }")
        Report(
            ErrorCode.ExpectedToken,
            "Expected 'get' or 'set' accessor. Got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "Inside property declaration braces, I need to see either 'get' or 'set' accessors.",
            "Properties define how to get and/or set their values using accessor blocks.",
            suggestions,
            Current().Value.Length)
    }

    // ============================================================================
    // Stage 14: the MEMBER grammars + the remaining type BODIES (residual map item [2]) — carried through
    // the SAME shared-panic model over the already-owned expression / statement / type / delimiter / block
    // grammars. ParseMemberList now dispatches the full ParseMemberDeclaration (Parser.cs :1412): the
    // preprocessor member, modifiers, the nested-type declarations, the constructor, the indexer, methods
    // (incl. func* generators / async / operator overloads / implicit-explicit conversions), and the
    // field/property fall-through. The record / interface bodies reuse this member list; the union / enum /
    // soa bodies have their OWN loops (carried in their name parsers below).
    // ============================================================================

    // Parser.cs ParseMemberDeclaration (:1412): the member dispatch. Attributes are residual [4] (deferred);
    // the corpus carries no member attributes, so — like the top-level ParseTopLevelDeclaration — this omits
    // ParseAttributes and consumes only the modifier keywords before the member-kind dispatch.
    func ParseMemberDeclaration() {
        // Preprocessor directive member (Parser.cs :1415).
        if Check(TokenType.PreprocessorDirective) {
            Advance()
            return
        }

        // Stage 16: member attributes precede modifiers (Parser.cs :1424). Stage N+1c tranche 4 threads the
        // captured modifiers + attributes into a nested type declaration (same as the top-level dispatch).
        attributes := ParseAttributes()
        attrsOk := AttributesMaterializable
        modifiers := ParseModifiers()

        // Nested type declarations (Parser.cs :1428-1460), in the same dispatch order.
        if Check(TokenType.Class) {
            ParseClassName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Ref) && LookAhead(1).Type == TokenType.Struct {
            Advance()
            ParseStructName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Struct) {
            ParseStructName(modifiers, attributes, attrsOk)
            return
        }
        if IsSoaRecordDeclarationStart() {
            ParseSoaRecordName()
            return
        }
        if Check(TokenType.Record) {
            ParseRecordName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Enum) {
            ParseEnumName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Union) {
            ParseUnionName()
            return
        }
        if Check(TokenType.Interface) {
            ParseInterfaceName(modifiers, attributes, attrsOk)
            return
        }

        // Constructor (Parser.cs :1463): the contextual `constructor` identifier.
        if Check(TokenType.Identifier) && Current().Value == "constructor" {
            ParseConstructorMember()
            return
        }

        // Indexer (Parser.cs :1469): `func this[...]`, checked before the general method.
        if Check(TokenType.Func) && LookAhead(1).Type == TokenType.This {
            ParseIndexerMember()
            return
        }

        // Method / conversion operator (Parser.cs :1475).
        if Check(TokenType.Func) || Check(TokenType.Implicit) || Check(TokenType.Explicit) {
            ParseMethodMember()
            return
        }

        // Field / property (Parser.cs :1481).
        ParseFieldMember()
    }

    // Parser.cs ParseConstructorDeclaration (:1484): `constructor(params) [: this(args) | : base(args)] { body }`.
    // The `constructor` keyword is a contextual identifier; the initializer target must be `this` or `base`,
    // else the ExpectedToken report fires and the offending token is skipped.
    func ParseConstructorMember() {
        line := Current().Line
        column := Current().Column
        Advance()                               // consume the 'constructor' identifier (Parser.cs :1488)
        ParseParameterListRecovery()

        // Optional initializer `: this(args)` / `: base(args)` (Parser.cs :1493).
        if Check(TokenType.Colon) {
            Advance()                           // Match(Colon) — advances past ':'
            if Check(TokenType.This) {
                Advance()
                ConsumeToken(TokenType.LeftParen, "Expected '(' after 'this'", "(")
                ParseArgumentList()
            } else {
                if Check(TokenType.Base) {
                    Advance()
                    ConsumeToken(TokenType.LeftParen, "Expected '(' after 'base'", "(")
                    ParseArgumentList()
                } else {
                    ReportConstructorInitializerTarget()
                    if !IsAtEnd() {
                        Advance()               // skip the invalid token (Parser.cs :1555)
                    }
                }
            }
        }

        // Body (Parser.cs :1559): ParseBlock consumes the '{' first, owner span on the 'constructor' keyword
        // (length 11).
        ParseBlock(new RecoverySpan(line, column, MaxInt(1, 11)))
    }

    // Parser.cs ParseConstructorDeclaration's initializer-target error (:1534).
    func ReportConstructorInitializerTarget() {
        suggestions := new List<string>()
        suggestions.Add("Use 'this' to call another constructor in the same class")
        suggestions.Add("Use 'base' to call a parent class constructor")
        Report(
            ErrorCode.ExpectedToken,
            "Expected 'this' or 'base' after ':'. Got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "In constructor initialization, the colon ':' must be followed by either 'this' (to call another constructor) or 'base' (to call parent constructor).",
            "Constructor chaining syntax: 'constructor(params) : this(args) { }' or 'constructor(params) : base(args) { }'",
            suggestions,
            Current().Value.Length)
    }

    // Parser.cs ParseIndexerDeclaration (:1564): `func this[params]: retType { get/set }`.
    func ParseIndexerMember() {
        line := Current().Line
        column := Current().Column
        ConsumeToken(TokenType.Func, "Expected 'func'", "func")
        ConsumeToken(TokenType.This, "Expected 'this'", "this")
        ConsumeToken(TokenType.LeftBracket, "Expected '['", "[")

        // Indexer parameter list (Parser.cs :1574): `name: Type` entries, comma-separated.
        if !Check(TokenType.RightBracket) {
            parsing := true
            while parsing {
                paramLine := Current().Line
                paramColumn := Current().Column
                paramName := ConsumeIdentifier("Expected parameter name")
                ConsumeParameterColon(paramName, paramLine, paramColumn)
                ParseParameterTypeReference(paramName, paramLine, paramColumn)
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    parsing = false
                }
            }
        }

        ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
        ConsumeToken(TokenType.Colon, "Expected ':'", ":")
        ParseTypeReferenceRecovery()
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")

        // Accessor list (Parser.cs :1596): `get`/`set` blocks, else the "Expected 'get' or 'set' accessor"
        // report + skip.
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            accessorLine := Current().Line
            accessorColumn := Current().Column
            accessor := ConsumeIdentifier("Expected 'get' or 'set'")
            accessorSpan := new RecoverySpan(accessorLine, accessorColumn, MaxInt(1, accessor.Length))
            if accessor == "get" {
                ParseBlock(accessorSpan)
            } else {
                if accessor == "set" {
                    ParseBlock(accessorSpan)
                } else {
                    ReportIndexerAccessorInvalid(accessor)
                    while !Check(TokenType.RightBrace) && !Check(TokenType.Identifier) && !IsAtEnd() {
                        Advance()
                    }
                }
            }
        }

        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
    }

    // Parser.cs ParseIndexerDeclaration's accessor error (:1613).
    func ReportIndexerAccessorInvalid(accessor: string) {
        suggestions := new List<string>()
        suggestions.Add("Example: get { return items[i]; }")
        suggestions.Add("Example: set { items[i] = value; }")
        Report(
            ErrorCode.ExpectedToken,
            "Expected 'get' or 'set' accessor, got '" + accessor + "'",
            Current().Line,
            Current().Column,
            "Indexer accessors must be either 'get' (for reading) or 'set' (for writing).",
            "Use 'get' to define how to retrieve a value, or 'set' to define how to assign a value.",
            suggestions,
            accessor.Length)
    }

    // Parser.cs ParseFunctionDeclaration (:373) reached as a MEMBER method: the func / func* generator /
    // func operator / implicit-explicit conversion forms, the keyword-anchored name (ConsumeDeclarationName,
    // DiagnosticSpanFromToken(funcToken), :435), the type parameters, the parameter list, the `: T` / `-> T`
    // return type (or the missing-return-type-marker report), the returns-lifetime annotation, the generic
    // constraints, and the `=> expr` / `{ }` body. Unlike a LOCAL function, a method with NO body is valid
    // (an abstract / interface method), so there is no missing-body report.
    func ParseMethodMember() {
        line := Current().Line
        column := Current().Column

        isConversionOperator := false
        name := "function"
        markerName := "function"
        markerLine := line
        markerColumn := column
        markerLength := MaxInt(1, Current().Value.Length)

        if Check(TokenType.Implicit) || Check(TokenType.Explicit) {
            // Conversion operator (Parser.cs :393): no 'func' keyword; the return type comes BEFORE params.
            isConversionOperator = true
            Advance()                           // consume 'implicit' / 'explicit'
            ConsumeToken(TokenType.Operator, "Expected 'operator' after 'implicit' or 'explicit'", "operator")
        } else {
            funcToken := Current()
            Advance()                           // consume 'func' (Parser.cs :406)
            if Check(TokenType.Star) {
                Advance()                       // generator func* (Parser.cs :409)
            }
            if Check(TokenType.Operator) {
                // Operator overload (Parser.cs :415): `func operator SYM`. The return-type marker anchors on
                // the `operator` keyword.
                operatorToken := Advance()      // consume 'operator'
                markerName = "operator overload"
                markerLine = operatorToken.Line
                markerColumn = operatorToken.Column
                markerLength = MaxInt(1, operatorToken.Value.Length)
                ParseOperatorSymbol()
            } else {
                nameLine := Current().Line
                nameColumn := Current().Column
                name = ConsumeDeclarationName("Expected function name", SpanFromToken(funcToken))
                if name != "<error>" {
                    markerName = name
                    markerLine = nameLine
                    markerColumn = nameColumn
                    markerLength = MaxInt(1, name.Length)
                }
            }
        }

        ParseTypeParameters()

        // For conversion operators the return type is parsed BEFORE the parameter list (Parser.cs :452).
        if isConversionOperator {
            ParseTypeReferenceRecovery()
        }

        ParseParameterListRecovery()
        parameterListEndToken := Previous()

        // Return type after the params (Parser.cs :462): `: T` or `-> T`, else the missing-marker report.
        if !isConversionOperator {
            if Check(TokenType.Colon) || (Check(TokenType.Minus) && LookAhead(1).Type == TokenType.Greater) {
                if Check(TokenType.Colon) {
                    Advance()
                } else {
                    Advance()                   // consume '-'
                    ConsumeToken(TokenType.Greater, "Expected '>' after '-' in return type arrow", "greater")
                }
                ParseTypeReferenceRecovery()
            } else {
                if IsLikelyMissingReturnTypeMarker(parameterListEndToken) {
                    ReportMissingReturnTypeMarker(markerName, markerLine, markerColumn, markerLength)
                    ParseTypeReferenceRecovery()
                }
            }
        }

        ParseReturnLifetimeAnnotation()
        ParseGenericConstraints()

        // Body (Parser.cs :493): an expression body, a block body, or NOTHING (abstract / interface method).
        if Check(TokenType.Arrow) {
            Advance()
            ParseExprValue()
            return
        }
        if Check(TokenType.LeftBrace) {
            bodySpan := new RecoverySpan(markerLine, markerColumn, markerLength)
            ParseBlock(bodySpan)
        }
    }

    // Parser.cs ParseOperatorSymbol (:5752): maps the operator token to its symbol and advances, reporting
    // the InvalidSyntax "Invalid operator symbol" when the token cannot be an overloadable operator.
    func ParseOperatorSymbol() {
        if IsOverloadableOperator(Current().Type) {
            Advance()
            return
        }
        token := Current()
        suggestions := new List<string>()
        suggestions.Add("Arithmetic: +, -, *, /, %")
        suggestions.Add("Comparison: ==, !=, <, >, <=, >=")
        suggestions.Add("Unary: !, ~, ++, --")
        suggestions.Add("Conversion: true, false")
        Report(
            ErrorCode.InvalidSyntax,
            "Invalid operator symbol '" + token.Value + "' for operator overloading",
            token.Line,
            token.Column,
            "This operator cannot be overloaded, or is not a valid operator symbol.",
            "Only certain operators can be overloaded in operator declarations.",
            suggestions,
            token.Value.Length)
        Advance()
    }

    // Parser.cs ParseOperatorSymbol's overloadable-operator set (:5757-5843), lowered from the switch to a
    // token predicate (the symbol string itself is unused by the recovery model).
    func IsOverloadableOperator(t: TokenType): bool {
        if t == TokenType.Plus { return true }
        if t == TokenType.Minus { return true }
        if t == TokenType.Star { return true }
        if t == TokenType.Slash { return true }
        if t == TokenType.Percent { return true }
        if t == TokenType.Equal { return true }
        if t == TokenType.NotEqual { return true }
        if t == TokenType.Less { return true }
        if t == TokenType.LessEqual { return true }
        if t == TokenType.Greater { return true }
        if t == TokenType.GreaterEqual { return true }
        if t == TokenType.Not { return true }
        if t == TokenType.BitwiseNot { return true }
        if t == TokenType.BitwiseAnd { return true }
        if t == TokenType.BitwiseOr { return true }
        if t == TokenType.BitwiseXor { return true }
        if t == TokenType.LeftShift { return true }
        if t == TokenType.RightShift { return true }
        if t == TokenType.Increment { return true }
        if t == TokenType.Decrement { return true }
        if t == TokenType.True { return true }
        if t == TokenType.False { return true }
        return false
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

    // Parser.cs ParseFieldTypeReference (:6536). Consumes a full type reference (Parser.cs :6543
    // `ParseTypeReference()` — the Stage-15 union / postfix / byref / tuple / Func grammar), or reports
    // the missing-type diagnostic anchored on the field name when a type terminator (and not the start
    // of the NEXT field) sits where the type should be.
    // Stage N+1c tranche 5 (richer types): returns the parsed type reference for the byte-exact FIELD
    // materialization through the shared ParseMaterializedTypeReference gate — the FULL stage-15 grammar
    // (simple / qualified / generic / array / nullable / tuple / Func / union / byref), each construction
    // byte-exact to Parser.cs. Only a malformed / multi-line / in-panic type parse returns null (deferred),
    // and the caller then declines to materialize that field.
    func ParseFieldTypeReference(fieldName: string, fieldLine: int, fieldColumn: int, fieldColonToken: Token): TypeReference? {
        if !IsTypeTerminator(Current().Type) && !LooksLikeNextFieldAfterMissingType(fieldColonToken) {
            return ParseMaterializedTypeReference()
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
        return null
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

    func ParseClassName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
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
        // non-generic class corpus (Check(Less) is false → returns immediately). Its PRESENCE gates
        // materialization (a TypeParameter list is a deferred family — see canMaterialize below).
        hasTypeParams := Check(TokenType.Less)
        ParseTypeParameters()
        // Primary constructor parameters `(…)` (Parser.cs :947) and the base class + interface list
        // `: T, U` (Parser.cs :955). The params are materialized as the byte-exact Parameter list when the
        // list is fully representable (ParamListMaterializable), captured into a local BEFORE the body parse.
        hasParams := Check(TokenType.LeftParen)
        primaryParams := new List<Parameter>()
        paramsOk := true
        if hasParams {
            primaryParams = ParseParameterListRecovery()
            paramsOk = ParamListMaterializable
        }
        hasBaseList := Check(TokenType.Colon)
        ParseBaseTypeList()
        members := ParseTypeBody(name, typeBodyDiagnosticSpan)
        // N+1c tranche 2/3/4: materialize the ClassDeclaration (Parser.cs :973). Line/Column anchor the class
        // keyword (Parser.cs :933-934). Modifiers + Attributes are the tranche-4 threaded values;
        // PrimaryConstructorParameters is the captured Parameter list (or null when absent). TypeParameters
        // stays null and Interfaces/BaseClass empty/null — a generic or base/interface list is a DEFERRED
        // family, so its presence DECLINES materialization (no-stub: never partially compared). Members is the
        // tranche-3 populated list. FULLY QUALIFIED (`NSharpLang.Compiler.Ast.ClassDeclaration`): a test-helper
        // `class ClassDeclaration` in NSharpLang.Compiler collides under the tests-enabled build.
        canMaterialize := attrsOk && paramsOk && !hasTypeParams && !hasBaseList
        if canMaterialize {
            if hasParams {
                AddDeclaration(new NSharpLang.Compiler.Ast.ClassDeclaration(
                    name, null, null, new List<TypeReference>(), members,
                    primaryParams, modifiers, attributes,
                    classToken.Line, classToken.Column))
            } else {
                AddDeclaration(new NSharpLang.Compiler.Ast.ClassDeclaration(
                    name, null, null, new List<TypeReference>(), members,
                    null, modifiers, attributes,
                    classToken.Line, classToken.Column))
            }
        }
    }

    func ParseStructName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        structToken := Current()
        Advance()
        nameToken := Current()          // capture the name position BEFORE it is consumed (Parser.cs :982)
        name := ConsumeDeclarationName("Expected struct name", SpanFromToken(structToken))
        // Parser.cs :985-987 ("struct".Length == 6).
        typeBodyDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            typeBodyDiagnosticSpan = new RecoverySpan(structToken.Line, structToken.Column, MaxInt(1, 6))
        }
        hasTypeParams := Check(TokenType.Less)
        ParseTypeParameters()
        hasParams := Check(TokenType.LeftParen)
        primaryParams := new List<Parameter>()
        paramsOk := true
        if hasParams {
            primaryParams = ParseParameterListRecovery()        // primary ctor params (Parser.cs :992)
            paramsOk = ParamListMaterializable
        }
        hasBaseList := Check(TokenType.Colon)
        ParseBaseTypeList()                     // interface list (Parser.cs :998)
        members := ParseTypeBody(name, typeBodyDiagnosticSpan)
        // N+1c tranche 1/3/4: materialize the StructDeclaration (Parser.cs :1010). isRefStruct is false for
        // the `struct S {}` corpus (`ref struct` is a deferred shape). Modifiers/Attributes/PrimaryConstructor-
        // Parameters are the tranche-4 threaded/captured values; a generic or interface list DECLINES
        // materialization (no-stub). Members is the tranche-3 populated list.
        canMaterialize := attrsOk && paramsOk && !hasTypeParams && !hasBaseList
        if canMaterialize {
            if hasParams {
                AddDeclaration(new StructDeclaration(
                    name, null, new List<TypeReference>(), members,
                    primaryParams, modifiers, attributes,
                    structToken.Line, structToken.Column, false))
            } else {
                AddDeclaration(new StructDeclaration(
                    name, null, new List<TypeReference>(), members,
                    null, modifiers, attributes,
                    structToken.Line, structToken.Column, false))
            }
        }
    }

    func ParseRecordName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        recordToken := Current()
        Advance()
        // `record struct` consumes the contextual `struct` before the name (Parser.cs :1021).
        isStruct := false
        if Check(TokenType.Struct) {
            isStruct = true
            Advance()
        }
        nameToken := Current()          // capture the name position BEFORE it is consumed (Parser.cs :1027)
        name := ConsumeDeclarationName("Expected record name", SpanFromToken(recordToken))
        // Parser.cs :1030-1032 ("record".Length == 6).
        typeBodyDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            typeBodyDiagnosticSpan = new RecoverySpan(recordToken.Line, recordToken.Column, MaxInt(1, 6))
        }
        hasTypeParams := Check(TokenType.Less)
        ParseTypeParameters()                   // Parser.cs :1033
        hasParams := Check(TokenType.LeftParen)
        primaryParams := new List<Parameter>()
        paramsOk := true
        if hasParams {
            primaryParams = ParseParameterListRecovery()        // record positional (primary ctor) params (Parser.cs :1039)
            paramsOk = ParamListMaterializable
        }
        hasBaseList := Check(TokenType.Colon)
        ParseBaseTypeList()                     // interface list (Parser.cs :1043)
        members := ParseTypeBody(name, typeBodyDiagnosticSpan)
        // N+1c tranche 1/3/4: materialize the RecordDeclaration (Parser.cs :1055). IsStruct reflects the
        // consumed `record struct`. Modifiers/Attributes are the tranche-4 threaded values; PrimaryConstructor-
        // Parameters is the captured Parameter list (or null when absent) — THE UNLOCK for the public-positional-
        // record real-corpus files. A generic or interface list DECLINES materialization (no-stub). Members is
        // the tranche-3 populated list.
        canMaterialize := attrsOk && paramsOk && !hasTypeParams && !hasBaseList
        if canMaterialize {
            if hasParams {
                AddDeclaration(new RecordDeclaration(
                    name, null, new List<TypeReference>(), members,
                    primaryParams, isStruct, modifiers, attributes,
                    recordToken.Line, recordToken.Column))
            } else {
                AddDeclaration(new RecordDeclaration(
                    name, null, new List<TypeReference>(), members,
                    null, isStruct, modifiers, attributes,
                    recordToken.Line, recordToken.Column))
            }
        }
    }

    func ParseSoaRecordName() {
        soaLine := Current().Line
        soaColumn := Current().Column
        Advance()                    // contextual 'soa'
        recordToken := Current()     // the 'record' keyword
        Advance()
        nameToken := Current()       // capture the name position BEFORE it is consumed (Parser.cs :1065)
        name := ConsumeDeclarationName("Expected soa record name", SpanFromToken(recordToken))
        // Parser.cs :1068-1070 ("soa".Length == 3, anchored at the soa keyword for a '<error>' name).
        soaDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            soaDiagnosticSpan = new RecoverySpan(soaLine, soaColumn, MaxInt(1, 3))
        }
        // Generic soa records are not supported yet (Parser.cs :1072): report then consume the `<…>` list.
        if Check(TokenType.Less) {
            ReportSoaTypeParametersUnsupported()
            ParseTypeParameters()
        }
        ParseSoaRecordBody(soaDiagnosticSpan, soaLine)
    }

    func ParseInterfaceName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        interfaceLine := Current().Line
        interfaceColumn := Current().Column
        isDuck := false
        if Check(TokenType.Duck) {
            isDuck = true
            interfaceLine = Current().Line      // Parser.cs anchors the '<error>' keyword span on 'duck' or 'interface'
            interfaceColumn = Current().Column
            Advance()                // contextual 'duck'
        }
        interfaceToken := Current()  // the 'interface' keyword
        if !isDuck {
            interfaceLine = interfaceToken.Line
            interfaceColumn = interfaceToken.Column
        }
        Advance()
        nameToken := Current()       // capture the name position BEFORE it is consumed (Parser.cs :1141)
        name := ConsumeDeclarationName("Expected interface name", SpanFromToken(interfaceToken))
        // Parser.cs :1144-1146 ("interface".Length == 9, "duck".Length == 4).
        keywordLength := 9
        if isDuck {
            keywordLength = 4
        }
        typeBodyDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            typeBodyDiagnosticSpan = new RecoverySpan(interfaceLine, interfaceColumn, MaxInt(1, keywordLength))
        }
        hasTypeParams := Check(TokenType.Less)
        ParseTypeParameters()                   // Parser.cs :1147
        hasBaseList := Check(TokenType.Colon)
        ParseBaseTypeList()                     // base interface list (Parser.cs :1150)
        members := ParseTypeBody(name, typeBodyDiagnosticSpan)
        // N+1c tranche 1/3/4: materialize the InterfaceDeclaration (Parser.cs :1150-return). Line/Column = the
        // first-token position (`duck` if present, else `interface`). Modifiers/Attributes are the tranche-4
        // threaded values; a generic or base-interface list is a DEFERRED family that DECLINES materialization
        // (no-stub). Members is the tranche-3 populated list. Interfaces have no primary-ctor params.
        canMaterialize := attrsOk && !hasTypeParams && !hasBaseList
        if canMaterialize {
            AddDeclaration(new InterfaceDeclaration(
                name, null, new List<TypeReference>(), members,
                modifiers, isDuck, attributes,
                interfaceLine, interfaceColumn))
        }
    }

    func ParseUnionName() {
        unionLine := Current().Line
        unionColumn := Current().Column
        unionToken := Current()
        Advance()
        nameToken := Current()       // capture the name position BEFORE it is consumed (Parser.cs :1171)
        name := ConsumeDeclarationName("Expected union name", SpanFromToken(unionToken))
        // Parser.cs :1174-1176 ("union".Length == 5).
        unionDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            unionDiagnosticSpan = new RecoverySpan(unionLine, unionColumn, MaxInt(1, 5))
        }
        ParseTypeParameters()                   // Parser.cs :1177
        ParseUnionBody(unionDiagnosticSpan, unionLine)
    }

    func ParseEnumName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        enumLine := Current().Line
        enumColumn := Current().Column
        enumToken := Current()
        Advance()
        nameToken := Current()       // capture the name position BEFORE it is consumed (Parser.cs :1245)
        name := ConsumeDeclarationName("Expected enum name", SpanFromToken(enumToken))
        // Parser.cs :1248-1250 ("enum".Length == 4).
        enumDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            enumDiagnosticSpan = new RecoverySpan(enumLine, enumColumn, MaxInt(1, 4))
        }
        // Optional `: int|string` backing type (Parser.cs :1255). The default is Int; a `string` backing
        // type selects String (Parser.cs :1114/:1125).
        enumType := EnumType.Int
        if Check(TokenType.Colon) {
            Advance()
            typeTokenLine := Current().Line
            typeTokenColumn := Current().Column
            typeName := ConsumeIdentifier("Expected enum backing type ('int' or 'string')")
            if typeName == "string" {
                enumType = EnumType.String
            }
            if typeName != "string" && typeName != "int" {
                ReportEnumBackingTypeUnsupported(typeName, typeTokenLine, typeTokenColumn)
            }
        }
        ParseEnumBody(enumDiagnosticSpan, enumLine)
        // N+1c tranche 1/3/4: materialize the EnumDeclaration for the empty-body corpus (Parser.cs :1189).
        // Members are the deferred family (member values are expressions) → empty list; the corpus uses
        // valueless empty enums so this is byte-exact. Modifiers/Attributes are the tranche-4 threaded values.
        // The `: int|string` backing type is the EnumType (handled above), not a base list — no base-list gate.
        // An argument-bearing attribute DECLINES materialization (no-stub). AddDeclaration routes it to an
        // enclosing type's Members when the enum is nested, else the top level.
        if attrsOk {
            AddDeclaration(new EnumDeclaration(
                name, new List<EnumMember>(), enumType, modifiers, attributes,
                enumLine, enumColumn))
        }
    }

    // Parser.cs ParseSoaRecordDeclaration's generic-soa report (:1074).
    func ReportSoaTypeParametersUnsupported() {
        Report(
            ErrorCode.InvalidSyntax,
            "soa record type parameters are not supported yet",
            Current().Line,
            Current().Column,
            "This parser slice only accepts non-generic soa records. Generic soa tables need an explicit ABI design before they can be accepted.",
            "Remove the type parameter list for now.",
            null,
            MaxInt(1, Current().Value.Length))
    }

    // Parser.cs ParseEnumDeclaration's unsupported-backing-type report (:1268). ReportError omits the
    // length there, so the default 0 flows through (both paths route through the same Create).
    func ReportEnumBackingTypeUnsupported(typeName: string, typeTokenLine: int, typeTokenColumn: int) {
        Report(
            ErrorCode.UnexpectedToken,
            "Unsupported enum backing type '" + typeName + "'. Only 'int' and 'string' are supported.",
            typeTokenLine,
            typeTokenColumn,
            null,
            null,
            null,
            0)
    }

    // Parser.cs class/struct/record/interface base-type list (:955/:998/:1043/:1150): `: T` then a
    // comma-separated tail. The class form uses `ParseTypeReference()` + `while Match(Comma)`, the others a
    // `do { … } while (Match(Comma))`; both parse the same at-least-one comma-separated list.
    func ParseBaseTypeList() {
        if !Check(TokenType.Colon) {
            return
        }
        Advance()                               // consume ':'
        ParseTypeReferenceRecovery()
        while Check(TokenType.Comma) {
            Advance()
            ParseTypeReferenceRecovery()
        }
    }

    // Parser.cs ParseUnionDeclaration body (:1179): the union-case loop. Each case is a bare name with an
    // optional `{ prop: type, … }` payload; the loop resets panic after EnsureProgress and reports the
    // union-specific missing-'}' (NL106) on the union diagnostic span. Assumes the '{' is next.
    func ParseUnionBody(unionDiagnosticSpan: RecoverySpan, openingLine: int) {
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            ConsumeIdentifier("Expected union case name")      // Parser.cs :1187
            if Check(TokenType.LeftBrace) {
                Advance()                       // consume the payload '{'
                while !Check(TokenType.RightBrace) && !IsAtEnd() {
                    propStart := Position
                    ConsumeIdentifier("Expected property name")   // Parser.cs :1198
                    ConsumeToken(TokenType.Colon, "Expected ':'", ":")
                    ParseTypeReferenceRecovery()
                    if !Check(TokenType.RightBrace) {
                        if Check(TokenType.Comma) {
                            Advance()
                        }
                    }
                    EnsureProgress(propStart)
                }
                ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
            }
            if EnsureProgress(startPosition) {
                PanicMode = false               // reset for the next case (Parser.cs :1216)
            }
        }
        if Check(TokenType.RightBrace) {
            Advance()
        } else {
            if IsAtEnd() {
                ReportTypeBodyMissingClosingBrace(unionDiagnosticSpan, openingLine, "union")
            }
        }
    }

    // Parser.cs ParseEnumDeclaration body (:1274): the enum-member loop. Each member is a name with an
    // optional `= value` initializer; a member without a trailing comma ends the list. Reports the
    // enum-specific missing-'}' (NL106) on the enum diagnostic span. Assumes the '{' is next.
    func ParseEnumBody(enumDiagnosticSpan: RecoverySpan, openingLine: int) {
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        if !Check(TokenType.RightBrace) {
            looping := true
            while looping && !Check(TokenType.RightBrace) && !IsAtEnd() {
                startPosition := Position
                ConsumeIdentifier("Expected enum member name")    // Parser.cs :1284
                if Check(TokenType.Assign) {
                    Advance()
                    ParseExprValue()            // the member value (Parser.cs :1290)
                }
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    looping = false
                }
                if looping {
                    EnsureProgress(startPosition)
                }
            }
        }
        if Check(TokenType.RightBrace) {
            Advance()
        } else {
            if IsAtEnd() {
                ReportTypeBodyMissingClosingBrace(enumDiagnosticSpan, openingLine, "enum")
            }
        }
    }

    // Parser.cs ParseSoaRecordDeclaration body (:1085): the soa-column loop. Each column is `name: Type`;
    // a trailing comma or semicolon is optional between columns. Resets panic at each column boundary and
    // reports the soa-specific missing-'}' (NL106) on the soa diagnostic span. Assumes the '{' is next.
    func ParseSoaRecordBody(soaDiagnosticSpan: RecoverySpan, openingLine: int) {
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            PanicMode = false                   // reset at each column boundary (Parser.cs :1090)
            startPosition := Position
            ConsumeIdentifier("Expected soa column name")         // Parser.cs :1094
            ConsumeToken(TokenType.Colon, "Expected ':'", ":")
            ParseTypeReferenceRecovery()
            if Check(TokenType.Comma) || Check(TokenType.Semicolon) {
                Advance()
            }
            EnsureProgress(startPosition)
        }
        if Check(TokenType.RightBrace) {
            Advance()
        } else {
            if IsAtEnd() {
                ReportTypeBodyMissingClosingBrace(soaDiagnosticSpan, openingLine, "soa record")
            }
        }
    }

    // The union / enum / soa body's own end-of-file missing-'}' report (Parser.cs :1114/:1225/:1317). Each
    // kind's message names its own body kind ("union body" / "enum body" / "soa record body"); the code,
    // span, hint suffix ("union declaration" / "enum declaration" / "soa record declaration"), and length
    // mirror the per-kind ReportError exactly.
    func ReportTypeBodyMissingClosingBrace(span: RecoverySpan, openingLine: int, kind: string) {
        Report(
            ErrorCode.MissingClosingBrace,
            "Missing closing '}'",
            span.Line,
            span.Column,
            "The " + kind + " body that started on line " + IntToString(openingLine) + " is missing its closing brace. I reached the end of the file without finding it.",
            "Add a '}' to close this " + kind + " declaration.",
            null,
            span.Length)
    }

    func ParseTypeAliasName() {
        typeToken := Current()
        Advance()
        // Parser.cs anchors with new DiagnosticSpan(line, column, Math.Max(1, "type".Length))
        // (:1337); with the keyword value "type" that equals SpanFromToken(typeToken).
        ConsumeDeclarationName("Expected type alias name", new RecoverySpan(typeToken.Line, typeToken.Column, MaxInt(1, 4)))

        // Stage 17: the `= <type>` underlying-type body (Parser.cs :1338-1350). The '=' Consume
        // (present → advance; absent mid-line → the standard ExpectedToken NL102 "Expected '='.
        // Expected 'assign', got 'X'"; absent at EOF → the ExpectedEndOfFile NL104 "Expected 'assign'
        // but reached the end of the file"; suppressed when a prior alias-name error set panic), the
        // optional `newtype` keyword (`type X = newtype Y`, a bare advance :1341-1345), and the
        // underlying type via the Stage-15 full ParseTypeReferenceRecovery grammar (union `A | B` /
        // postfix array-nullable / byref / tuple / Func / generic — every error site already owned).
        ConsumeToken(TokenType.Assign, "Expected '='", "assign")
        if Check(TokenType.Newtype) {
            Advance()
        }
        ParseTypeReferenceRecovery()
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

    // ---- span helpers for the materialized type grammar (Stage N+1c tranche 5) ----
    // Reproduce Parser.cs SpanFromTokens(start, end) (:5873) BYTE-EXACT for a SINGLE-LINE span. SourceSpan's
    // only multi-arg factory is FromStartAndLength (single-line), and every corpus type reference is single-
    // line, so the caller gates single-line (start.Line == end.Line — enforced at the field/parameter
    // materialization site) and this reproduces `new SourceSpan(start.Line, start.Column, end.Line,
    // end.Column + Max(1, end.Value.Length))` when start.Line == end.Line: FromStartAndLength(line, col, len)
    // is `new SourceSpan(line, col, line, col + Max(1, len))`, and with len = end.Column + Max(1,
    // end.Value.Length) - start.Column (always >= 1 for an ordered same-line pair) the end column matches.
    // The start.Line<=0/Column<=0 → None guard mirrors SpanFromTokens :5875 (FromStartAndLength :43 shares it).
    func SpanFromTokensSingleLine(start: Token, end: Token): SourceSpan {
        return SourceSpan.FromStartAndLength(start.Line, start.Column, end.Column + MaxInt(1, end.Value.Length) - start.Column)
    }

    // Reproduce Parser.cs ExtendSpan(TypeReference start, Token end) (:5885) BYTE-EXACT for a single-line
    // span: None when the start node's span is invalid, else `new SourceSpan(start.Span.StartLine,
    // start.Span.StartColumn, end.Line, end.Column + Max(1, end.Value.Length))` — reproduced via
    // FromStartAndLength on the (single-line-gated) start line. Used for the `T[]` / `T?` postfix + `A | B`
    // union close, where the extent runs from the inner node's start through the closing suffix / last-arm
    // token.
    func ExtendSpanFromNode(start: TypeReference, end: Token): SourceSpan {
        if !start.Span.IsValid {
            return SourceSpan.None
        }
        return SourceSpan.FromStartAndLength(start.Span.StartLine, start.Span.StartColumn, end.Column + MaxInt(1, end.Value.Length) - start.Span.StartColumn)
    }

    // Stage N+1c tranche 5: the field / parameter type materialization gate. Parses a full type reference
    // through the (now node-returning) recovery grammar and returns its byte-exact node ONLY when the parse
    // was WELL-FORMED and SINGLE-LINE — the corpus shape. Deferral (return null → the caller declines to
    // materialize the field/parameter/declaration, no-stub) fires when: the grammar could not structurally
    // build the node (a non-identifier name, a null sub-part); the parse ENTERED in panic (a prior malformed
    // construct — Report is suppressed, so an error-count delta cannot see it); ANY diagnostic was reported
    // during the parse (a malformed type — Parser.cs materializes an <error>/partial node, deferred here);
    // or the type spans multiple lines (SourceSpan's single-line factory cannot reproduce a multi-line span
    // byte-exact). A well-formed single-line type reports nothing and stays on one line, so every richer
    // form (qualified / generic / array / nullable / tuple / Func / union / byref) now materializes.
    func ParseMaterializedTypeReference(): TypeReference? {
        panicBefore := PanicMode
        errorsBefore := Errors.Count
        startToken := Current()
        node := ParseTypeReferenceRecovery()
        if node == null {
            return null
        }
        if panicBefore {
            return null
        }
        if Errors.Count != errorsBefore {
            return null
        }
        if startToken.Line != Previous().Line {
            return null
        }
        return node
    }

    // ---- full type reference grammar (Parser.cs ParseTypeReference :1774) ----
    // Stage 15: the entry is the UNION layer (Parser.cs `ParseTypeReference` → `ParseUnionTypeReference`
    // :1776) — a `|`-separated list of POSTFIX type references. Every consumer already threaded through
    // ParseTypeReferenceRecovery (is/as / typeof / sizeof / cast / stackalloc / catch / typed-decl /
    // local-func-return / base-lists / member-return-types / parameter / field / new / generic-args /
    // tuple-elements / Func-params) now gets the full grammar, exactly as Parser.cs threads them all
    // through ParseTypeReference. The Stage 5-11 simple / qualified / generic corpus flows straight
    // through union → postfix → base → the identifier arm unchanged (no `|` / `[]` / `?` / `&` / `(` /
    // `Func` ⇒ byte-exact identical output), so no prior contract moves.
    // Stage N+1c tranche 5: each grammar layer now RETURNS the byte-exact TypeReference node it parses (or
    // null for a structurally-unbuildable sub-part) as a PURE side-effect — the Advance/Report/Consume
    // sequence is unchanged, so the diagnostic stream (the 1238 baseline) is unperturbed. The ~30 diagnostic-
    // only callers discard the returned node; the field/parameter sites capture it through
    // ParseMaterializedTypeReference above.
    func ParseTypeReferenceRecovery(): TypeReference? {
        first := ParsePostfixTypeReferenceRecovery()        // first arm (Parser.cs :1781)
        if !Check(TokenType.BitwiseOr) {                    // Parser.cs :1782 early return
            return first
        }
        // Union `A | B | …` (Parser.cs :1785). Arms accumulate; armsOk tracks a null (unbuildable) arm so the
        // union declines. lastToken tracks the last consumed real token, ExtendSpan's end (Parser.cs :1805).
        arms := new List<TypeReference>()
        armsOk := first != null
        if first != null {
            arms.Add(first)
        }
        scanningUnion := true
        while scanningUnion {
            if Check(TokenType.BitwiseOr) {                 // Parser.cs :1788
                Advance()                                   // consume '|' (Parser.cs :1790)
                if IsTypeTerminator(Current().Type) {       // trailing `|` (Parser.cs :1791)
                    ReportUnionMissingTypeArm()             // NL103 (Parser.cs :1793), then break
                    armsOk = false
                    scanningUnion = false
                } else {
                    arm := ParsePostfixTypeReferenceRecovery()   // next arm (Parser.cs :1804)
                    if arm == null {
                        armsOk = false
                    } else {
                        arms.Add(arm)
                    }
                }
            } else {
                scanningUnion = false
            }
        }
        if !armsOk || first == null {
            return null
        }
        // Parser.cs :1808 `new UnionTypeReference(arms) { Span = ExtendSpan(first, lastToken) }`, lastToken =
        // Previous after the last arm (:1805).
        result := new UnionTypeReference(arms)
        result.Span = ExtendSpanFromNode(first, Previous())
        return result
    }

    // Parser.cs ParseUnionTypeReference's missing-arm report (:1793): a `|` immediately followed by a type
    // terminator. Anchored on the terminator token (Current), length Max(1, its value length), no
    // suggestions (Parser.cs's ReportError omits them). After it the loop breaks — only the FIRST trailing
    // `|` reports (and, being in panic after the report, any later `|` would be suppressed regardless).
    func ReportUnionMissingTypeArm() {
        Report(
            ErrorCode.InvalidSyntax,
            "Expected a type after '|' in anonymous union type",
            Current().Line,
            Current().Column,
            "Anonymous union types use the form `A | B`, so every `|` must be followed by another type.",
            "Add the missing type arm, or remove the trailing `|`.",
            null,
            MaxInt(1, Current().Value.Length))
    }

    // Parser.cs ParsePostfixTypeReference (:1814): a base type plus a loop of `[]` / `?[]` / `?` suffixes.
    // The `[` / `?[` array/nullable-array forms are lookahead-guarded (`[` only when `]` immediately
    // follows), so their `Consume(RightBracket)` (:1824/:1846) NEVER fails — no reachable diagnostic. The
    // suffixes only shape the consumed extent so a FOLLOWING error (a trailing union `|`, or the next
    // declaration) anchors byte-exact.
    func ParsePostfixTypeReferenceRecovery(): TypeReference? {
        baseType := ParseBaseTypeReferenceRecovery()
        suffixLooping := true
        while suffixLooping {
            if Check(TokenType.LeftBracket) && LookAhead(1).Type == TokenType.RightBracket {
                Advance()                                   // '[' (Parser.cs :1823)
                rightBracket := Advance()                   // guaranteed ']' (Consume never fails, :1824)
                baseType = WrapArrayType(baseType, rightBracket)   // Parser.cs :1825
            } else {
                if Check(TokenType.QuestionBracket) && LookAhead(1).Type == TokenType.RightBracket {
                    questionBracket := Advance()            // '?[' (Parser.cs :1834)
                    baseType = WrapNullableQuestionBracketType(baseType, questionBracket)   // Parser.cs :1835
                    rightBracket := Advance()               // guaranteed ']' (:1846)
                    baseType = WrapArrayType(baseType, rightBracket)   // Parser.cs :1847
                } else {
                    if Check(TokenType.Question) {
                        question := Advance()               // '?' nullable (Parser.cs :1856)
                        baseType = WrapNullableType(baseType, question)   // Parser.cs :1857
                    } else {
                        suffixLooping = false               // Parser.cs :1864 break
                    }
                }
            }
        }
        return baseType
    }

    // Parser.cs :1825/:1847 `new ArrayTypeReference(baseType) { Span = ExtendSpan(baseType, rightBracket) }`.
    func WrapArrayType(element: TypeReference?, rightBracket: Token): TypeReference? {
        if element == null {
            return null
        }
        result := new ArrayTypeReference(element)
        result.Span = ExtendSpanFromNode(element, rightBracket)
        return result
    }

    // Parser.cs :1857 `new NullableTypeReference(baseType) { Span = ExtendSpan(baseType, question) }`.
    func WrapNullableType(inner: TypeReference?, question: Token): TypeReference? {
        if inner == null {
            return null
        }
        result := new NullableTypeReference(inner)
        result.Span = ExtendSpanFromNode(inner, question)
        return result
    }

    // Parser.cs :1835-1844: the nullable half of `T?[]`. The span ends one column PAST the `?[` token
    // (questionBracket.Column + 1 — the `?`), NOT extended by the token length, so this does not route
    // through ExtendSpanFromNode. Single-line-gated at the site, reproduced via FromStartAndLength.
    func WrapNullableQuestionBracketType(inner: TypeReference?, questionBracket: Token): TypeReference? {
        if inner == null {
            return null
        }
        result := new NullableTypeReference(inner)
        if inner.Span.IsValid {
            result.Span = SourceSpan.FromStartAndLength(inner.Span.StartLine, inner.Span.StartColumn, questionBracket.Column + 1 - inner.Span.StartColumn)
        } else {
            result.Span = SourceSpan.None
        }
        return result
    }

    // Parser.cs ParseBaseTypeReference (:1884): a byref `&T`, a parenthesized / tuple type `( … )`, a
    // `Func<…>` function type, or the simple / qualified / generic identifier arm (owned since Stage 5).
    func ParseBaseTypeReferenceRecovery(): TypeReference? {
        if Check(TokenType.BitwiseAnd) {                    // byref &T (Parser.cs :1886)
            ampersand := Current()
            Advance()
            inner := ParsePostfixTypeReferenceRecovery()    // inner is a POSTFIX type (Parser.cs :1889)
            return MakeByRefType(ampersand, inner)
        }
        if Check(TokenType.LeftParen) {                     // tuple / parenthesized (Parser.cs :1899)
            return ParseParenthesizedOrTupleTypeReferenceRecovery()
        }
        if Check(TokenType.Identifier) && Current().Value == "Func" {   // Func<…> (Parser.cs :1905)
            return ParseFunctionTypeReferenceRecovery()
        }

        // simple / qualified / generic (Parser.cs :1910-1962). Capture the accumulated dotted name + the
        // last name token (ExtendSpan's end for a simple type) so a qualified `A.B.C` materializes byte-exact.
        typeNameToken := Current()
        firstName := ConsumeIdentifier("Expected type name")   // Parser.cs :1914
        name := firstName
        nameOk := firstName != "<error>"
        lastNameToken := typeNameToken
        while Check(TokenType.Dot) {                         // qualified name A.B (Parser.cs :1918)
            Advance()
            lastNameToken = Current()                       // Parser.cs :1921 captures Current BEFORE consuming
            segment := ConsumeIdentifier("Expected identifier after '.'")
            name = name + "." + segment
            if segment == "<error>" {
                nameOk = false
            }
        }

        if Check(TokenType.Less) {
            lessToken := Advance()                          // consume '<'
            typeArgs := new List<TypeReference>()
            argsOk := true
            if Check(TokenType.Greater) {
                ReportMissingGenericTypeArgument(typeNameToken, lessToken)  // `Name<>` (Parser.cs :1930)
                argsOk = false
            } else {
                firstArg := ParseTypeReferenceRecovery()    // first type argument (full grammar, Parser.cs :1936)
                if firstArg == null {
                    argsOk = false
                } else {
                    typeArgs.Add(firstArg)
                }
                scanning := true
                while scanning {
                    if Check(TokenType.Comma) {
                        Advance()
                        if Check(TokenType.Greater) {
                            // `Name<T,>` trailing comma (Parser.cs :1940-1943).
                            ReportMissingGenericTypeArgument(typeNameToken, lessToken)
                            argsOk = false
                            scanning = false
                        } else {
                            nextArg := ParseTypeReferenceRecovery()
                            if nextArg == null {
                                argsOk = false
                            } else {
                                typeArgs.Add(nextArg)
                            }
                        }
                    } else {
                        scanning = false
                    }
                }
            }
            greater := ConsumeGreater("Expected '>'")       // Parser.cs :1950
            if !nameOk || !argsOk {
                return null
            }
            // Parser.cs :1951 `new GenericTypeReference(name, typeArgs) { Line = typeNameLine, Column =
            // typeNameColumn, Span = SpanFromTokens(typeNameToken, greater) }` — the 4-arg ctor sets Line/Column.
            result := new GenericTypeReference(name, typeArgs, typeNameToken.Line, typeNameToken.Column)
            result.Span = SpanFromTokensSingleLine(typeNameToken, greater)
            return result
        }

        if !nameOk {
            return null
        }
        // Parser.cs :1959 `new SimpleTypeReference(name, typeNameLine, typeNameColumn) { Span =
        // SpanFromTokens(typeNameToken, lastNameToken) }` — a single-token type has lastNameToken == typeNameToken.
        simple := new SimpleTypeReference(name, typeNameToken.Line, typeNameToken.Column)
        simple.Span = SpanFromTokensSingleLine(typeNameToken, lastNameToken)
        return simple
    }

    // Parser.cs :1890-1895 `new ByRefTypeReference(inner) { Span = inner.Span.IsValid ? new SourceSpan(
    // ampersand.Line, ampersand.Column, inner.Span.EndLine, inner.Span.EndColumn) : FromStartAndLength(
    // ampersand.Line, ampersand.Column, 1) }`. Single-line-gated, so inner.Span.EndLine == ampersand.Line.
    func MakeByRefType(ampersand: Token, inner: TypeReference?): TypeReference? {
        if inner == null {
            return null
        }
        result := new ByRefTypeReference(inner)
        if inner.Span.IsValid {
            result.Span = SourceSpan.FromStartAndLength(ampersand.Line, ampersand.Column, inner.Span.EndColumn - ampersand.Column)
        } else {
            result.Span = SourceSpan.FromStartAndLength(ampersand.Line, ampersand.Column, 1)
        }
        return result
    }

    // Parser.cs ParseParenthesizedOrTupleTypeReference (:1965): a `( … )` list of comma-separated element
    // types, each optionally `name:`-prefixed. The opening `(` is guarded by the caller's Check (:1899), so
    // its `Consume(LeftParen)` (:1967) never fails; the closing `)` routes through ConsumeToken — a missing
    // `)` reaches the Stage-9 closing-delimiter recovery (NL107 at a line / same-line boundary, else the
    // plain NL102). Each element type descends the full ParseTypeReferenceRecovery (:1981). The
    // single-unnamed-element unwrap and the named-element detection shape the (unbuilt) AST only — no
    // diagnostic — so the recovery model just consumes them.
    func ParseParenthesizedOrTupleTypeReferenceRecovery(): TypeReference? {
        leftParen := Current()
        Advance()                                           // '(' (Consume guarded, Parser.cs :1967)
        elements := new List<TupleTypeElement>()
        elementsOk := true
        tupleLooping := true
        while tupleLooping {
            elementName: string? = null
            if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon {
                elementName = Advance().Value               // element name (Parser.cs :1977)
                Advance()                                   // ':' (Parser.cs :1978)
            }
            elementType := ParseTypeReferenceRecovery()     // element type (Parser.cs :1981)
            if elementType == null {
                elementsOk = false
            } else {
                elements.Add(new TupleTypeElement(elementType, elementName))   // Parser.cs :1982
            }
            if Check(TokenType.Comma) {                     // Parser.cs :1984 `while Match(Comma)`
                Advance()
            } else {
                tupleLooping = false
            }
        }
        rightParen := ConsumeToken(TokenType.RightParen, "Expected ')'", ")")   // Parser.cs :1986
        if !elementsOk {
            return null
        }
        tupleSpan := SpanFromTokensSingleLine(leftParen, rightParen)
        // Parser.cs :1988-1992: a single UNNAMED element unwraps to the inner type (its span reset to the
        // whole parenthesized extent), NOT a TupleTypeReference. The inner type is bound to a LOCAL before the
        // span set — the columnar backend declines a property assignment through a list-index + property chain
        // (`elements[0].Type.Span = …`).
        if elements.Count == 1 && elements[0].Name == null {
            onlyElement := elements[0]
            innerType := onlyElement.Type
            innerType.Span = tupleSpan
            return innerType
        }
        // Parser.cs :1994 `new TupleTypeReference(elements) { Span = SpanFromTokens(leftParen, rightParen) }`.
        result := new TupleTypeReference(elements)
        result.Span = tupleSpan
        return result
    }

    // Parser.cs ParseFunctionTypeReference (:2000): `Func< T, … >`. The leading `Func` identifier is
    // guarded by the caller's Check (:1905), so its `Consume(Identifier)` (:2002) never fails; then
    // `Consume(Less)` (:2003, NL102 "Expected '<'" — expected "less" — when absent, or the ConsumeToken
    // EOF NL104), a comma-separated ParseTypeReference list (:2006/:2011), and the split-`>>`-aware
    // ConsumeGreater (:2014). Unlike the generic identifier arm, `Func` does NOT call
    // ReportMissingGenericTypeArgument — it routes each argument straight through ParseTypeReference, so
    // `Func<>` / `Func<int,>` reach the ConsumeIdentifier NL102 on the `>` (verified against the oracle).
    func ParseFunctionTypeReferenceRecovery(): TypeReference? {
        funcToken := Current()
        Advance()                                           // 'Func' (Consume guarded, Parser.cs :2002)
        ConsumeToken(TokenType.Less, "Expected '<'", "less")   // Parser.cs :2003
        // Parser.cs :2005-2012: the LAST parsed type is the return type; the preceding ones are the parameter
        // types. So each comma pushes the CURRENT returnType into paramTypes before the next parse.
        paramTypes := new List<TypeReference>()
        returnType := ParseTypeReferenceRecovery()          // first type = return (Parser.cs :2006)
        typesOk := returnType != null
        while Check(TokenType.Comma) {                      // Parser.cs :2008 `while Match(Comma)`
            Advance()
            if returnType != null {
                paramTypes.Add(returnType)                  // Parser.cs :2010
            } else {
                typesOk = false
            }
            returnType = ParseTypeReferenceRecovery()       // Parser.cs :2011
            if returnType == null {
                typesOk = false
            }
        }
        greater := ConsumeGreater("Expected '>'")           // Parser.cs :2014
        if !typesOk || returnType == null {
            return null
        }
        // Parser.cs :2017 `new FunctionTypeReference(paramTypes, returnType) { Span = SpanFromTokens(funcToken, greater) }`.
        result := new FunctionTypeReference(paramTypes, returnType)
        result.Span = SpanFromTokensSingleLine(funcToken, greater)
        return result
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
    // The if / while / for body path: the caller already checked Check(LeftBrace), so the opening '{'
    // is consumed unconditionally (Parser.cs's ParseBlock Consume(LeftBrace) always succeeds here).
    func ParseBlockBody(ownerSpan: RecoverySpan?) {
        line := Current().Line
        column := Current().Column
        Advance()                               // consume '{'
        diagnosticSpan := ownerSpan ?? new RecoverySpan(line, column, 1)
        ParseBlockStatementsLoop(diagnosticSpan, line)
    }

    // Parser.cs ParseBlock (:2143): Consume the opening '{' FIRST (reporting a missing '{' through the
    // standard Consume path), then run the shared block-statements loop. This is the entry the
    // block-bearing statement kinds reach — try / catch / finally / using / lock / switch / unsafe /
    // alloc-block / allow / assert-throws / local-function all call ParseBlock directly WITHOUT a
    // preceding Check(LeftBrace) (Stage 13), unlike the if/while/for bodies that route through the
    // block case of ParseStatement.
    func ParseBlock(ownerSpan: RecoverySpan?) {
        line := Current().Line
        column := Current().Column
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        diagnosticSpan := ownerSpan ?? new RecoverySpan(line, column, 1)
        ParseBlockStatementsLoop(diagnosticSpan, line)
    }

    // The shared block-statements loop (Parser.cs ParseBlock's while body, :2151-2214): the
    // per-statement panic reset + _currentRecoveryBoundaryColumn tracking + no-progress synchronize
    // + the closing-'}' / found-declaration / EOF missing-'}' reports. Both ParseBlockBody and
    // ParseBlock funnel through it so the block grammar is modelled once.
    func ParseBlockStatementsLoop(diagnosticSpan: RecoverySpan, openingLine: int) {
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            // Stage 9: a type-declaration keyword that can't be a statement signals a missing '}' — report
            // the found-declaration NL106 anchored on the block owner and break so the outer declaration
            // loop parses it as a new declaration (Parser.cs :2156-2170, does NOT advance).
            if IsBlockClosingDeclarationStart() {
                ReportBlockMissingClosingBraceFoundDeclaration(diagnosticSpan, openingLine)
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
                ReportMissingClosingBrace(diagnosticSpan, openingLine)
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
        // `await foreach` async iteration (Parser.cs :2249) — a compound dispatch before plain `while`.
        if Check(TokenType.Await) && LookAhead(1).Type == TokenType.Foreach {
            ParseAwaitForeachStatement()
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
        if Check(TokenType.Yield) {
            ParseYieldStatement()
            return
        }
        if Check(TokenType.Break) {
            ParseBreakStatement()
            return
        }
        if Check(TokenType.Continue) {
            ParseContinueStatement()
            return
        }
        if Check(TokenType.Throw) {
            ParseThrowStatement()
            return
        }
        if Check(TokenType.Try) {
            ParseTryStatement()
            return
        }
        if Check(TokenType.Using) {
            ParseUsingStatement()
            return
        }
        if Check(TokenType.Lock) {
            ParseLockStatement()
            return
        }
        if Check(TokenType.Switch) {
            ParseSwitchStatement()
            return
        }
        if Check(TokenType.Allow) {
            ParseAllowStatement()
            return
        }
        // alloc BLOCK statement `alloc { … }` — a compound dispatch (Parser.cs :2273); a bare `alloc`
        // is an expression primary (Stage 11), reached through ParseExpressionStatement below.
        if Check(TokenType.Alloc) && LookAhead(1).Type == TokenType.LeftBrace {
            ParseAllocBlockStatement()
            return
        }
        if Check(TokenType.Unsafe) {
            ParseUnsafeBlockStatement()
            return
        }
        if Check(TokenType.Print) {
            ParsePrintStatement()
            return
        }
        if Check(TokenType.Assert) {
            ParseAssertStatement()
            return
        }
        if Check(TokenType.PreprocessorDirective) {
            ParsePreprocessorDirective()
            return
        }
        if Check(TokenType.LeftBrace) {
            ParseBlockBody(blockOwnerSpan)
            return
        }

        // Local function (Parser.cs :2287): [static] [async] func Name(…) … The two-modifier
        // `static async func` and one-modifier `static func` / `async func` and bare `func` forms.
        if (Check(TokenType.Static) || Check(TokenType.Async)) && LookAhead(1).Type == TokenType.Func {
            ParseLocalFunction()
            return
        }
        if Check(TokenType.Static) && LookAhead(1).Type == TokenType.Async && LookAhead(2).Type == TokenType.Func {
            ParseLocalFunction()
            return
        }
        if Check(TokenType.Func) {
            ParseLocalFunction()
            return
        }

        // The contextual `off handle` unsubscription statement (Parser.cs :2294).
        if IsOffStatementStart() {
            ParseOffStatement()
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
    // Returns true when it parsed a TUPLE deconstruction (the `let (a, b) := …` form), false for a
    // plain single-name declaration — the caller (using-statement) needs to distinguish the two,
    // mirroring Parser.cs's `stmt as VariableDeclarationStatement` null check.
    func ParseVariableDeclaration(): bool {
        Advance()                               // consume let / const / readonly

        // Tuple deconstruction `(x, y) := …` (Parser.cs :2536). The paren position anchors it.
        if Check(TokenType.LeftParen) {
            tupleLine := Current().Line
            tupleColumn := Current().Column
            ParseTupleDeconstruction(tupleLine, tupleColumn)
            return true
        }

        line := Current().Line
        column := Current().Column
        name := ConsumeIdentifier("Expected variable name")

        // Optional type annotation `: T` (Parser.cs :2550).
        if Check(TokenType.Colon) {
            Advance()
            ParseTypeReferenceRecovery()
        }

        if Check(TokenType.Assign) || Check(TokenType.ColonAssign) {
            initializerToken := Advance()
            ParseRequiredExpressionAfter(
                initializerToken,
                "an initializer expression",
                "This variable declaration",
                new RecoverySpan(line, column, MaxInt(1, name.Length)))
        }
        return false
    }

    // Parser.cs ParseTupleDeconstruction (:2570): `(a, b, …) := expr` / `(a, b) = expr`. The name list,
    // the ':='/'=' requirement (NL102 when absent, then skip the offender), and the required initializer.
    func ParseTupleDeconstruction(line: int, column: int) {
        ConsumeToken(TokenType.LeftParen, "Expected '('", "(")

        scanning := true
        while scanning {
            ConsumeIdentifier("Expected identifier or '_'")
            if Check(TokenType.Comma) {
                Advance()
            } else {
                scanning = false
            }
        }

        ConsumeToken(TokenType.RightParen, "Expected ')'", ")")

        // Only ':=' / '=' is accepted; otherwise report and skip the offending token (Parser.cs :2584).
        if !Check(TokenType.ColonAssign) && !Check(TokenType.Assign) {
            ReportTupleDeconstructionRequiresAssign()
            if !IsAtEnd() {
                Advance()
            }
        }

        // Anchor the required-initializer recovery on ':='/'=' when present, else the CURRENT token
        // (where the initializer is actually expected) after the skip (Parser.cs :2607-2619).
        if Check(TokenType.ColonAssign) || Check(TokenType.Assign) {
            initializerToken := Advance()
            ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This tuple deconstruction", null)
        } else {
            ParseRequiredExpressionAfter(Current(), "an initializer expression", "This tuple deconstruction", null)
        }
    }

    // Parser.cs ParseTupleDeconstruction's ':='/'=' missing report (:2586).
    func ReportTupleDeconstructionRequiresAssign() {
        suggestions := new List<string>()
        suggestions.Add("Add ':=' for new variables: (x, y) := (1, 2)")
        suggestions.Add("Add '=' for existing variables: (x, y) = tuple")
        suggestions.Add("Example: (name, age) := getPerson()")
        Report(
            ErrorCode.ExpectedToken,
            "Tuple deconstruction requires ':=' or '='. Got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "To unpack a tuple into multiple variables, you need to use ':=' or '=' after the variable list.",
            "Tuple deconstruction syntax: (x, y) := getTuple() or (x, y) = getTuple()",
            suggestions,
            Current().Value.Length)
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
            return
        }

        // C-style `for (init; cond; incr) { … }` (Parser.cs :2684). The parentheses are optional; the
        // two `;` separators are Consume sites and the optional `)` routes through the Stage-9 recovery.
        hasParens := false
        if Check(TokenType.LeftParen) {
            hasParens = true
            Advance()                           // consume '('
        }

        // Initializer (a `let` declaration, a `:=` shorthand, or a bare expression statement).
        if !Check(TokenType.Semicolon) {
            if Check(TokenType.Let) {
                ParseVariableDeclaration()
            } else {
                initResult := ParseExprValue()
                if initResult.IsBareIdentifier && Check(TokenType.ColonAssign) {
                    initializerToken := Advance()
                    ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This for-loop initializer", null)
                }
            }
        }

        ConsumeToken(TokenType.Semicolon, "Expected ';'", ";")

        if !Check(TokenType.Semicolon) {
            ParseExprValue()                    // condition
        }

        ConsumeToken(TokenType.Semicolon, "Expected ';'", ";")

        // Iterator: stop at ')' when parenthesized, else at '{'.
        needIterator := false
        if hasParens {
            needIterator = !Check(TokenType.RightParen)
        } else {
            needIterator = !Check(TokenType.LeftBrace)
        }
        if needIterator {
            ParseExprValue()                    // iterator
        }

        if hasParens {
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        }

        ParseStatement(SpanFromToken(forToken))
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

    // ============================================================================
    // Stage 13: the REMAINING statement kinds (residual map item [1]). Each is a thin dispatch +
    // Consume site over the already-owned expression / type / pattern / delimiter grammars, carried
    // through the SAME shared-panic model. Diagnostic CONSTRUCTION delegates to the shared Report /
    // ParseRequiredExpressionAfter / ConsumeToken / ConsumeIdentifier, and every boundary DECISION
    // reuses the live shared ParserTokenFacts, so codes / messages / spans / snippets / hints match
    // Parser.cs automatically. Semantic diagnostics (loop-context for break/continue/yield, generator-
    // return, undefined name) are NOT parser diagnostics and are not modelled here.
    // ============================================================================

    // ---- yield (Parser.cs ParseYieldStatement :2839) ----
    // `yield <value>` (required-expression) or `yield break` (no value).
    func ParseYieldStatement() {
        yieldToken := Current()
        Advance()                               // consume 'yield'
        if !Check(TokenType.Break) {
            ParseRequiredExpressionAfter(yieldToken, "a value to yield", "This yield statement", null)
        } else {
            Advance()                           // consume 'break' (yield break)
        }
    }

    // ---- break / continue (Parser.cs :2885 / :2967) ----
    // The Consume(Break)/(Continue) never fires (the dispatch guards on the exact token); the
    // loop-context validity is a SEMANTIC check, not a parser one.
    func ParseBreakStatement() {
        Advance()                               // consume 'break'
    }

    func ParseContinueStatement() {
        Advance()                               // consume 'continue'
    }

    // ---- throw (Parser.cs ParseThrowStatement :2975) ----
    func ParseThrowStatement() {
        throwToken := Current()
        Advance()                               // consume 'throw'
        ParseRequiredExpressionAfter(throwToken, "an exception expression", "This throw statement", null)
    }

    // ---- preprocessor directive (Parser.cs ParsePreprocessorDirective :2875) ----
    // The Consume(PreprocessorDirective) never fires (dispatched on the exact token); the directive
    // text carries no diagnostic.
    func ParsePreprocessorDirective() {
        Advance()                               // consume the directive
    }

    // ---- await foreach (Parser.cs ParseAwaitForeachStatement :2776) ----
    func ParseAwaitForeachStatement() {
        Advance()                               // consume 'await'
        foreachToken := Current()
        Advance()                               // consume 'foreach'
        hasParens := false
        if Check(TokenType.LeftParen) {
            Advance()                           // optional '('
            hasParens = true
        }
        variableToken := Current()
        ConsumeIdentifier("Expected variable name")
        inToken := ConsumeInOrReportMissing(foreachToken, variableToken, "This await foreach statement")
        ParseRequiredExpressionAfter(inToken, "a collection expression", "This await foreach statement", null)
        if hasParens {
            ConsumeToken(TokenType.RightParen, "Expected ')' to match opening '('", ")")
        }
        ParseStatement(SpanFromToken(foreachToken))
    }

    // The `Check(In) ? Consume(In) : ReportMissingInKeywordAndRecover` idiom shared by foreach and
    // await-foreach (Parser.cs :2758 / :2788); the owner-description differs per caller.
    func ConsumeInOrReportMissing(loopKeywordToken: Token, variableToken: Token, ownerDescription: string): Token {
        if Check(TokenType.In) {
            return ConsumeToken(TokenType.In, "Expected 'in'", "in")
        }
        return ReportMissingInKeywordAndRecover(loopKeywordToken, variableToken, ownerDescription)
    }

    // ---- unsafe block (Parser.cs ParseUnsafeBlockStatement :2379) ----
    func ParseUnsafeBlockStatement() {
        line := Current().Line
        column := Current().Column
        unsafeToken := Current()
        Advance()                               // consume 'unsafe'
        ParseBlock(new RecoverySpan(line, column, MaxInt(1, unsafeToken.Value.Length)))
    }

    // ---- alloc block (Parser.cs ParseAllocBlockStatement :2301) — dispatched only when `alloc {` ----
    func ParseAllocBlockStatement() {
        line := Current().Line
        column := Current().Column
        allocToken := Current()
        Advance()                               // consume 'alloc'
        ParseBlock(new RecoverySpan(line, column, MaxInt(1, allocToken.Value.Length)))
    }

    // ---- assert (Parser.cs ParseAssertStatement :2388) ----
    // `assert throws ExceptionType { … }` OR `assert <condition> [, <message>]`.
    func ParseAssertStatement() {
        assertToken := Current()
        Advance()                               // consume 'assert'
        if Check(TokenType.Identifier) && Current().Value == "throws" {
            Advance()                           // consume 'throws'
            ParseTypeReferenceRecovery()
            ParseBlock(SpanFromToken(assertToken))
            return
        }
        ParseRequiredExpressionAfter(assertToken, "a condition expression", "This assert statement", null)
        if Check(TokenType.Comma) {
            Advance()                           // consume ','
            ParseExprValue()                    // the optional message expression
        }
    }

    // ---- lock (Parser.cs ParseLockStatement :3128) ----
    // `lock obj { … }` or `lock (obj) { … }`. The "Expected block statement after lock" report
    // (Parser.cs :3151) is UNREACHABLE — ParseBlock always yields a block, so the `bodyStmt == null`
    // guard is dead C#; it is intentionally not modelled.
    func ParseLockStatement() {
        lockToken := Current()
        Advance()                               // consume 'lock'
        hasParens := Check(TokenType.LeftParen)
        expressionAnchor := lockToken
        if hasParens {
            expressionAnchor = ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
        }
        ParseRequiredExpressionAfter(expressionAnchor, "an object expression", "This lock statement", null)
        if hasParens {
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        }
        ParseBlock(SpanFromToken(lockToken))
    }

    // ---- try / catch / finally (Parser.cs ParseTryStatement :2988) ----
    func ParseTryStatement() {
        tryToken := Current()
        Advance()                               // consume 'try'
        ParseBlock(SpanFromToken(tryToken))
        while Check(TokenType.Catch) {
            catchToken := Advance()             // consume 'catch'
            if Check(TokenType.LeftParen) {
                Advance()                       // consume '('
                if !Check(TokenType.RightParen) {
                    if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon {
                        Advance()               // catch variable name
                        Advance()               // consume ':'
                        ParseTypeReferenceRecovery()
                    } else {
                        ParseTypeReferenceRecovery()
                        if Check(TokenType.Identifier) {
                            Advance()           // catch variable name
                        }
                    }
                }
                ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            } else {
                if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon {
                    Advance()                   // catch variable name
                    Advance()                   // consume ':'
                    ParseTypeReferenceRecovery()
                }
            }
            ParseBlock(SpanFromToken(catchToken))
        }
        if Check(TokenType.Finally) {
            finallyToken := Advance()           // consume 'finally'
            ParseBlock(SpanFromToken(finallyToken))
        }
    }

    // ---- using (Parser.cs ParseUsingStatement :3048) ----
    // `using let x := e { … }` / `using x := e { … }` / `using (e) { … }` / `using e { … }`. A
    // `using let (a, b) := …` tuple-deconstruction gets the InvalidSyntax NL103 anchored on the
    // single-line `(…)` pattern span.
    func ParseUsingStatement() {
        usingToken := Current()
        Advance()                               // consume 'using'
        if Check(TokenType.Identifier) || Check(TokenType.Let) {
            if Check(TokenType.Let) {
                spanResult := TryGetSingleLineDelimiterSpanAt(Position + 1, TokenType.LeftParen, TokenType.RightParen)
                wasTuple := ParseVariableDeclaration()
                if wasTuple {
                    diagSpan := SpanFromToken(usingToken)
                    if spanResult.Found {
                        diagSpan = spanResult.Span
                    }
                    ReportUsingRequiresVariableDeclaration(diagSpan)
                }
            } else {
                ConsumeIdentifier("Expected variable name")
                initializerToken := ConsumeToken(TokenType.ColonAssign, "Expected ':='", "colonassign")
                ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This using declaration", null)
            }
            if Check(TokenType.LeftBrace) {
                ParseBlock(SpanFromToken(usingToken))
            }
            return
        }
        ParseRequiredExpressionAfter(usingToken, "a resource expression", "This using statement", null)
        if Check(TokenType.LeftBrace) {
            ParseBlock(SpanFromToken(usingToken))
        }
    }

    func ReportUsingRequiresVariableDeclaration(span: RecoverySpan) {
        suggestions := new List<string>()
        suggestions.Add("Change from tuple deconstruction to single variable")
        suggestions.Add("Example: using let file := File.Open(path) { ... }")
        suggestions.Add("Note: The variable will be automatically disposed when the block ends")
        Report(
            ErrorCode.InvalidSyntax,
            "Using statement requires a variable declaration, not tuple deconstruction",
            span.Line,
            span.Column,
            "The 'using' statement can only work with single variable declarations, not tuple deconstruction.",
            "Use a single variable: using let resource := getResource() { ... }",
            suggestions,
            span.Length)
    }

    // Parser.cs TryGetSingleLineDelimiterSpanAt (:5968): the span of a balanced `(…)` starting at
    // `openingIndex`, provided the delimiters stay on the opening token's line. Returns false only
    // when the opening token is absent / of the wrong type; an unbalanced run falls back to the
    // opening token's own span (still Found).
    func TryGetSingleLineDelimiterSpanAt(openingIndex: int, openingType: TokenType, closingType: TokenType): OwnerSpanResult {
        notFound := new OwnerSpanResult(false, SpanFromToken(Current()))
        if openingIndex < 0 || openingIndex >= Tokens.Count {
            return notFound
        }
        openingToken := Tokens[openingIndex]
        if openingToken.Type != openingType {
            return notFound
        }
        depth := 0
        index := openingIndex
        scanning := true
        while scanning && index < Tokens.Count {
            token := Tokens[index]
            if token.Type == TokenType.Eof || token.Line != openingToken.Line {
                scanning = false
            } else {
                if token.Type == openingType {
                    depth = depth + 1
                } else {
                    if token.Type == closingType {
                        depth = depth - 1
                        if depth == 0 {
                            found := new RecoverySpan(openingToken.Line, openingToken.Column, TokenSpanLengthOrFallback(openingToken, token))
                            return new OwnerSpanResult(true, found)
                        }
                    }
                }
                index = index + 1
            }
        }
        return new OwnerSpanResult(true, SpanFromToken(openingToken))
    }

    // ---- switch (Parser.cs ParseSwitchStatement :3170) ----
    func ParseSwitchStatement() {
        switchLine := Current().Line
        switchToken := Current()
        Advance()                               // consume 'switch'
        ParseRequiredExpressionAfter(switchToken, "a value expression", "This switch statement", null)
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")

        caseLoopActive := true
        while caseLoopActive && !Check(TokenType.RightBrace) && !IsAtEnd() {
            caseDiagnosticSpan := new RecoverySpan(Current().Line, Current().Column, MaxInt(1, Current().Value.Length))
            matchedLabel := false
            if Check(TokenType.Case) {
                Advance()                       // consume 'case'
                ParsePattern()
                matchedLabel = true
            } else {
                if Check(TokenType.Default) {
                    Advance()                   // consume 'default'
                    matchedLabel = true
                } else {
                    ReportSwitchExpectedCaseOrDefault()
                    // Skip to the next case / default / '}' (Parser.cs :3218).
                    while !Check(TokenType.RightBrace) && !Check(TokenType.Case) && !Check(TokenType.Default) && !IsAtEnd() {
                        Advance()
                    }
                    if Check(TokenType.RightBrace) {
                        caseLoopActive = false  // Parser.cs :3221 break
                    }
                    // else: fall through with matchedLabel = false — Parser.cs :3223 continue
                }
            }
            if matchedLabel {
                ConsumeToken(TokenType.Arrow, "Expected '=>'", "arrow")
                if Check(TokenType.LeftBrace) {
                    ParseBlock(caseDiagnosticSpan)
                } else {
                    ParseStatement(null)
                }
            }
        }

        if Check(TokenType.RightBrace) {
            Advance()
        } else {
            ReportSwitchMissingClosingBrace(switchToken, switchLine)
        }
    }

    func ReportSwitchExpectedCaseOrDefault() {
        suggestions := new List<string>()
        suggestions.Add("Add a case: case 1 => { ... }")
        suggestions.Add("Add a default: default => { ... }")
        suggestions.Add("Example: case > 0 => Console.WriteLine(\"positive\")")
        Report(
            ErrorCode.ExpectedToken,
            "Expected 'case' or 'default'. Got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "Switch statements must contain 'case' patterns or a 'default' case.",
            "Each branch in a switch must start with 'case pattern =>' or 'default =>'",
            suggestions,
            Current().Value.Length)
    }

    // Parser.cs's switch-specific missing-'}' report (:3249) — DISTINCT from the block NL106 (its
    // message names the switch body and its line).
    func ReportSwitchMissingClosingBrace(switchToken: Token, switchLine: int) {
        span := SpanFromToken(switchToken)
        Report(
            ErrorCode.MissingClosingBrace,
            "Missing closing '}'",
            span.Line,
            span.Column,
            "The switch body that started on line " + IntToString(switchLine) + " is missing its closing brace. I reached the end of the file without finding it.",
            "Add a '}' to close this switch statement.",
            null,
            span.Length)
    }

    // ---- allow (Parser.cs ParseAllowStatement :2310) ----
    // `allow(effect, reason: "…", owner: "…") { … }`. The effect loop funnels every name through
    // ConsumeSystemsIdentifier and force-advances when a whole iteration made no progress
    // (Parser.cs's `if (Current == nameToken) Advance()`, modelled by the position guard).
    func ParseAllowStatement() {
        line := Current().Line
        column := Current().Column
        allowToken := Current()
        Advance()                               // consume 'allow'
        ConsumeToken(TokenType.LeftParen, "Expected '(' after 'allow'", "(")
        while !Check(TokenType.RightParen) && !IsAtEnd() {
            loopStartPosition := Position
            name := ConsumeSystemsIdentifier("Expected allow effect or named argument")
            if Check(TokenType.Colon) {
                Advance()                       // consume ':'
                // `reason`/`owner` take a string expression; every other effect takes an effect value.
                // Both parse a diagnostic-free value for the corpus, so the OrdinalIgnoreCase in
                // Parser.cs is byte-exact here with a plain compare.
                if name == "reason" {
                    ParseExprValue()
                } else {
                    if name == "owner" {
                        ParseExprValue()
                    } else {
                        ParseAllowEffectValue()
                    }
                }
            }
            if !Check(TokenType.RightParen) {
                ConsumeToken(TokenType.Comma, "Expected ',' between allow arguments", ",")
            }
            if Position == loopStartPosition {
                if !IsAtEnd() {
                    Advance()                   // force progress (Parser.cs :2351)
                }
            }
        }
        ConsumeToken(TokenType.RightParen, "Expected ')' after allow arguments", ")")
        ParseBlock(new RecoverySpan(line, column, MaxInt(1, allowToken.Value.Length)))
    }

    // Parser.cs ConsumeSystemsIdentifier (:6786): an effect name (identifier or an alloc-family
    // keyword) or the NL102 "Expected allow effect or named argument" report.
    func ConsumeSystemsIdentifier(message: string): string {
        if IsSystemsIdentifierToken() {
            return Advance().Value
        }
        Report(
            ErrorCode.ExpectedToken,
            message + ". Got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "Systems policy lists use effect names such as alloc, trap, dispatch, delegate, closure, or a named argument such as reason.",
            "Write allow(alloc, reason: \"...\") { ... } or remove this allow block.",
            null,
            TokenLengthOrFallback(Current()))
        return "<error>"
    }

    // Parser.cs ParseAllowEffectValue (:2362): a bare effect name or a general expression value.
    func ParseAllowEffectValue() {
        if IsSystemsIdentifierToken() {
            Advance()
            return
        }
        ParseExprValue()
    }

    // The shared token set both ConsumeSystemsIdentifier and ParseAllowEffectValue admit (Parser.cs
    // :6788 / :2364).
    func IsSystemsIdentifierToken(): bool {
        if Check(TokenType.Identifier) {
            return true
        }
        if Check(TokenType.Alloc) {
            return true
        }
        if Check(TokenType.Allow) {
            return true
        }
        if Check(TokenType.Stackalloc) {
            return true
        }
        if Check(TokenType.Interface) {
            return true
        }
        if Check(TokenType.Ref) {
            return true
        }
        if Check(TokenType.Out) {
            return true
        }
        if Check(TokenType.Throw) {
            return true
        }
        return false
    }

    // ---- local function (Parser.cs ParseLocalFunction :2419) ----
    // `[static] [async] func Name<…>(…)[: Ret] [where …] { … }` (or `=> expr`). The local func uses
    // plain ConsumeIdentifier for the name (NOT the keyword-anchored ConsumeDeclarationName the
    // top-level func uses), and reaches the missing-return-type-marker and missing-body reports.
    func ParseLocalFunction() {
        line := Current().Line
        column := Current().Column
        scanningModifiers := true
        while scanningModifiers {
            if Check(TokenType.Static) {
                Advance()
            } else {
                if Check(TokenType.Async) {
                    Advance()
                } else {
                    scanningModifiers = false
                }
            }
        }
        ConsumeToken(TokenType.Func, "Expected 'func'", "func")
        if Check(TokenType.Star) {
            Advance()                           // generator func*
        }
        nameLine := Current().Line
        nameColumn := Current().Column
        name := ConsumeIdentifier("Expected function name")
        ParseTypeParameters()
        ParseParameterListRecovery()
        parameterListEndToken := Previous()
        if Check(TokenType.Colon) || (Check(TokenType.Minus) && LookAhead(1).Type == TokenType.Greater) {
            if Check(TokenType.Colon) {
                Advance()
            } else {
                Advance()                       // consume '-'
                ConsumeToken(TokenType.Greater, "Expected '>' after '-' in return type arrow", "greater")
            }
            ParseTypeReferenceRecovery()
        } else {
            if IsLikelyMissingReturnTypeMarker(parameterListEndToken) {
                markerName := name
                markerLine := nameLine
                markerColumn := nameColumn
                markerLength := MaxInt(1, name.Length)
                if name == "<error>" {
                    markerName = "local function"
                    markerLine = line
                    markerColumn = column
                    markerLength = MaxInt(1, 4) // "func".Length
                }
                ReportMissingReturnTypeMarker(markerName, markerLine, markerColumn, markerLength)
                ParseTypeReferenceRecovery()
            }
        }
        ParseReturnLifetimeAnnotation()
        ParseGenericConstraints()
        if Check(TokenType.Arrow) {
            Advance()                           // consume '=>'
            ParseExprValue()                    // expression body
        } else {
            if Check(TokenType.LeftBrace) {
                bodySpan := new RecoverySpan(nameLine, nameColumn, MaxInt(1, name.Length))
                if name == "<error>" {
                    bodySpan = new RecoverySpan(line, column, MaxInt(1, 4))
                }
                ParseBlock(bodySpan)
            } else {
                ReportLocalFunctionMissingBody()
            }
        }
    }

    // Parser.cs IsLikelyMissingReturnTypeMarker (:6678).
    func IsLikelyMissingReturnTypeMarker(parameterListEndToken: Token): bool {
        if parameterListEndToken.Type != TokenType.RightParen {
            return false
        }
        if Current().Line != parameterListEndToken.Line {
            return false
        }
        return ParserTokenFacts.IsTypeReferenceStart(Current().Type)
    }

    // Parser.cs ReportMissingReturnTypeMarker (:6688).
    func ReportMissingReturnTypeMarker(declarationName: string, declarationLine: int, declarationColumn: int, declarationLength: int) {
        suggestions := new List<string>()
        suggestions.Add("Add ':' before '" + Current().Value + "'")
        suggestions.Add("Remove the return type if this function does not return a value")
        Report(
            ErrorCode.ExpectedToken,
            "Expected ':' before return type. Got '" + Current().Value + "'",
            declarationLine,
            declarationColumn,
            "Function '" + declarationName + "' needs a ':' before its return type.",
            "Write the return type as `func name(...): Type { ... }`.",
            suggestions,
            MaxInt(1, declarationLength))
    }

    // Parser.cs ParseLocalFunction's no-body report (:2504).
    func ReportLocalFunctionMissingBody() {
        suggestions := new List<string>()
        suggestions.Add("Add a block: { return value; }")
        suggestions.Add("Use arrow syntax: => value")
        suggestions.Add("Example: func add(x: int, y: int): int => x + y")
        Report(
            ErrorCode.ExpectedToken,
            "Expected function body or '=>' for expression-bodied function. Got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "A function needs a body - either a block with braces { } or an expression after '=>'.",
            "Use '{ ... }' for a block body or '=> expression' for a single expression.",
            suggestions,
            Current().Value.Length)
    }

    // Parser.cs ParseReturnLifetimeAnnotation (:511): the optional Systems `returns 'a` /
    // `returns local|static|unknown` / `returns param(name)` / `returns heap(owner)` annotation.
    // Guarded by the contextual `returns` identifier, so a non-Systems function never reaches it.
    func ParseReturnLifetimeAnnotation() {
        if !(Check(TokenType.Identifier) && Current().Value == "returns") {
            return
        }
        Advance()                               // consume 'returns'
        if Check(TokenType.Lifetime) {
            Advance()
            return
        }
        if Check(TokenType.Identifier) {
            kind := Advance().Value
            if kind == "local" || kind == "static" || kind == "unknown" {
                return
            }
            if kind == "param" || kind == "heap" {
                ConsumeToken(TokenType.LeftParen, "Expected '(' after returns " + kind, "(")
                owner := ConsumeIdentifier("Expected owner name inside returns " + kind + "(...)")
                ConsumeToken(TokenType.RightParen, "Expected ')' after returns " + kind + "(" + owner + ")", ")")
                return
            }
        }
        Report(
            ErrorCode.ExpectedToken,
            "Expected lifetime label after 'returns'. Got '" + Current().Value + "'",
            Current().Line,
            Current().Column,
            "Systems lifetime annotations use `returns 'a`, `returns param(name)`, or `returns heap(owner)` to describe a ref-like return.",
            "Write a lifetime such as `returns 'a`, `returns heap(owner)`, or remove the `returns` annotation.",
            null,
            TokenLengthOrFallback(Current()))
    }

    // ---- off (Parser.cs ParseOffStatement :2957) ----
    // The contextual `off handle` unsubscription: just parses the handle expression.
    func IsOffStatementStart(): bool {
        return Current().Type == TokenType.Identifier && Current().Value == "off" && LookAhead(1).Type == TokenType.Identifier
    }

    func ParseOffStatement() {
        Advance()                               // consume contextual 'off'
        ParseExprValue()                        // the handle expression
    }

    // ---- on subscription (Parser.cs ParseOnSubscriptionExpression :2893) ----
    // `on target.Event (sender, args) => { … }`. Reached as the highest-precedence expression prefix
    // (ParseExprValue), so it works both as a bare statement and composed with `:=`. The event target
    // is a member/index chain that deliberately STOPS before a `(` (so the handler's parameter list is
    // not swallowed as a call); the handler must be a lambda, else the InvalidSyntax NL103 fires.
    func IsOnSubscriptionStart(): bool {
        if Current().Type != TokenType.Identifier || Current().Value != "on" {
            return false
        }
        next := LookAhead(1).Type
        return next == TokenType.Identifier || next == TokenType.This || next == TokenType.Base
    }

    func ParseOnSubscription(): ExprResult {
        onLine := Current().Line
        onColumn := Current().Column
        Advance()                               // consume contextual 'on'
        ParseEventTarget()

        // The handler position + whether it is a lambda (Parser.cs parses then checks
        // `is LambdaExpression`; a lambda is exactly one of the two ParseExprValue lambda prefixes).
        handlerLine := Current().Line
        handlerColumn := Current().Column
        handlerIsLambda := IsLambdaExpression() || (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Arrow)
        ParseExprValue()                        // the handler (ParseLambdaOrAssignmentExpression)
        if !handlerIsLambda {
            ReportExpectedEventHandlerLambda(handlerLine, handlerColumn)
        }
        return new ExprResult(new RecoverySpan(onLine, onColumn, 1), false)
    }

    // Parser.cs ParseEventTarget (:2927): a primary + member-access (and index) chain only, stopping
    // before a `(` so the handler lambda's parameter list is not consumed as a call.
    func ParseEventTarget() {
        ParsePrimaryExprValue()
        scanning := true
        while scanning {
            if Check(TokenType.Dot) || Check(TokenType.QuestionDot) {
                Advance()                       // consume '.' / '?.'
                ConsumeIdentifier("Expected event or member name after '.'")
            } else {
                if Check(TokenType.LeftBracket) || Check(TokenType.QuestionBracket) {
                    Advance()                   // consume '[' / '?['
                    ParseExprValue()            // the index
                    ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
                } else {
                    scanning = false
                }
            }
        }
    }

    func ReportExpectedEventHandlerLambda(handlerLine: int, handlerColumn: int) {
        Report(
            ErrorCode.InvalidSyntax,
            "Expected an event handler lambda after the event",
            handlerLine,
            handlerColumn,
            "`on` subscribes a handler to a .NET event, so it needs a lambda to run when the event fires.",
            "Write the handler inline, e.g. `on widget.Clicked (sender, args) => { ... }`.",
            null,
            1)
    }

    // ---- expression statement (Parser.cs ParseExpressionStatement :3498) ----
    // Parses the typed-declaration (`name: T = value`) and tuple-deconstruction (paren / no-paren)
    // forms (Stage 13), otherwise the statement's expression, then the `identifier :=` shorthand
    // declaration (Parser.cs :3621, `expr is IdentifierExpression && Check(ColonAssign)`).
    func ParseExpressionStatement() {
        line := Current().Line
        column := Current().Column

        // Typed variable declaration without `let` (Parser.cs :3507): `name: Type = value`. Speculative —
        // if the `= value` is absent, rewind and parse as a normal expression statement.
        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon && LookAhead(2).Type == TokenType.Identifier {
            saved := Position
            name := Advance().Value             // the declared name
            Advance()                           // consume ':'
            ParseTypeReferenceRecovery()        // the type
            if Check(TokenType.Assign) {
                Advance()                       // consume '='
                ParseRequiredExpressionAfter(
                    Previous(),
                    "an initializer expression",
                    "This typed variable declaration",
                    new RecoverySpan(line, column, MaxInt(1, name.Length)))
                return
            }
            Position = saved                    // not a declaration — rewind
        }

        // Tuple deconstruction without parens (Parser.cs :3533): `x, y := expr`.
        if Check(TokenType.Identifier) && Position + 1 < Tokens.Count && Tokens[Position + 1].Type == TokenType.Comma {
            offset := 1
            isTuple := false
            scanning := true
            while scanning && Position + offset < Tokens.Count {
                tok := Tokens[Position + offset]
                if tok.Type == TokenType.ColonAssign || tok.Type == TokenType.Assign {
                    isTuple = true
                    scanning = false
                } else {
                    if tok.Type != TokenType.Identifier && tok.Type != TokenType.Comma {
                        scanning = false
                    } else {
                        offset = offset + 1
                    }
                }
            }
            if isTuple {
                namesScanning := true
                while namesScanning {
                    ConsumeIdentifier("Expected identifier or '_'")
                    if Check(TokenType.Comma) {
                        Advance()
                    } else {
                        namesScanning = false
                    }
                }
                initializerToken := Advance()   // consume := or =
                ParseRequiredExpressionAfter(
                    initializerToken,
                    "an initializer expression",
                    "This tuple deconstruction",
                    new RecoverySpan(line, column, MaxInt(1, initializerToken.Column - column)))
                return
            }
        }

        // Tuple deconstruction with parens (Parser.cs :3576): `(x, y) := expr`.
        if Check(TokenType.LeftParen) && Position + 1 < Tokens.Count && Tokens[Position + 1].Type == TokenType.Identifier && Position + 2 < Tokens.Count && Tokens[Position + 2].Type == TokenType.Comma {
            parenDepth := 1
            offset := 1
            isTuple := false
            scanning := true
            while scanning && Position + offset < Tokens.Count {
                tok := Tokens[Position + offset]
                if tok.Type == TokenType.LeftParen {
                    parenDepth = parenDepth + 1
                } else {
                    if tok.Type == TokenType.RightParen {
                        parenDepth = parenDepth - 1
                        if parenDepth == 0 {
                            if Position + offset + 1 < Tokens.Count {
                                next := Tokens[Position + offset + 1]
                                if next.Type == TokenType.ColonAssign || next.Type == TokenType.Assign {
                                    isTuple = true
                                }
                            }
                            scanning = false
                        }
                    }
                }
                offset = offset + 1
            }
            if isTuple {
                ParseTupleDeconstruction(line, column)
                return
            }
        }

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

    // ---- lambda prefixes + assignment (Parser.cs ParseLambdaOrAssignmentExpression :3641 → :3690) ----
    // Stage 11 carries the LAMBDA family: the single-parameter `x => …` (:3652) and multi-parameter
    // `(x, y) => …` (:3681) literals, whose only reachable error site is the missing lambda-body expression
    // (via the already-owned ParseRequiredExpressionAfter — the multi-param parameter list is guarded by
    // IsLambdaExpression, which admits only a well-formed `( ident, … ) =>`, so its ConsumeIdentifier /
    // Consume(RightParen) / Consume(Arrow) sites never fire). The `on` subscription prefix (:3649) is a
    // separate family (deferred); the corpus uses no `on` expression.
    func ParseExprValue(): ExprResult {
        line := Current().Line
        column := Current().Column

        // Event subscription `on target.Event (…) => …` (Parser.cs :3649) — the highest-precedence
        // prefix, so it composes with `:=` and works as a bare statement (Stage 13).
        if IsOnSubscriptionStart() {
            return ParseOnSubscription()
        }

        // Single-parameter lambda `x => expr` (Parser.cs :3652). A LambdaExpression is anchored on this start
        // position, so its DiagnosticSpanFromExpression falls to the (line, column, 1) default (:5960).
        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Arrow {
            paramToken := Advance()                         // the parameter name
            arrowToken := Advance()                         // consume '=>'
            if Check(TokenType.LeftBrace) {
                ParseBlockBody(new RecoverySpan(paramToken.Line, paramToken.Column, MaxInt(1, paramToken.Value.Length)))
            } else {
                ParseRequiredExpressionAfter(
                    arrowToken,
                    "a lambda body expression",
                    "This lambda expression",
                    DiagnosticSpanFromTokenRange(paramToken, arrowToken))
            }
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        // Multi-parameter lambda `(x, y) => expr` (Parser.cs :3681), gated by the IsLambdaExpression lookahead.
        if Check(TokenType.LeftParen) && IsLambdaExpression() {
            return ParseMultiParameterLambda()
        }

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

    // Parser.cs IsLambdaExpression (:5535): a bounded lookahead over `( ident (, ident)* ) =>` (or the empty
    // `() =>`), returning true only when the parenthesized list is a well-formed lambda parameter list. A pure
    // token scan (no cursor mutation), the IsGenericMethodCall idiom. Because this admits ONLY a well-formed
    // parameter list, ParseMultiParameterLambda's ConsumeIdentifier / Consume(RightParen) / Consume(Arrow)
    // sites never report — the reachable error is only the missing lambda body.
    func IsLambdaExpression(): bool {
        pos := Position + 1                                 // skip the '(' at Current
        // Empty lambda `() =>` (Parser.cs :5543).
        if pos < Tokens.Count && Tokens[pos].Type == TokenType.RightParen {
            return pos + 1 < Tokens.Count && Tokens[pos + 1].Type == TokenType.Arrow
        }
        scanning := true
        while scanning {
            if pos >= Tokens.Count || Tokens[pos].Type != TokenType.Identifier {
                return false
            }
            pos = pos + 1
            if pos < Tokens.Count && Tokens[pos].Type == TokenType.RightParen {
                return pos + 1 < Tokens.Count && Tokens[pos + 1].Type == TokenType.Arrow
            }
            if pos >= Tokens.Count || Tokens[pos].Type != TokenType.Comma {
                return false
            }
            pos = pos + 1
        }
        return false
    }

    // Parser.cs ParseMultiParameterLambda (:5494): `( ident, … ) => body`. IsLambdaExpression guards the entry,
    // so the parameter list is always well-formed and only the missing-body error (via ParseRequiredExpressionAfter,
    // span DiagnosticSpanFromTokenRange(leftParen, arrow)) is reachable. A LambdaExpression is anchored on the
    // opening `(`, so its DiagnosticSpanFromExpression falls to the (line, column, 1) default (:5960).
    func ParseMultiParameterLambda(): ExprResult {
        line := Current().Line
        column := Current().Column
        leftParenToken := ConsumeToken(TokenType.LeftParen, "Expected '('", "(")

        hasFirstParam := false
        firstParamLine := line
        firstParamColumn := column
        firstParamLength := 1
        if !Check(TokenType.RightParen) {
            paramLooping := true
            while paramLooping {
                paramToken := Current()
                name := ConsumeIdentifier("Expected parameter name")
                if !hasFirstParam {
                    hasFirstParam = true
                    firstParamLine = paramToken.Line
                    firstParamColumn = paramToken.Column
                    firstParamLength = MaxInt(1, name.Length)
                }
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    paramLooping = false
                }
            }
        }

        ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        arrowToken := ConsumeToken(TokenType.Arrow, "Expected '=>'", "=>")

        if Check(TokenType.LeftBrace) {
            // Parser.cs :5518: the block owner span is the first parameter's name (guaranteed valid here).
            lambdaSpan := new RecoverySpan(line, column, 1)
            if hasFirstParam {
                lambdaSpan = new RecoverySpan(firstParamLine, firstParamColumn, firstParamLength)
            }
            ParseBlockBody(lambdaSpan)
        } else {
            ParseRequiredExpressionAfter(
                arrowToken,
                "a lambda body expression",
                "This lambda expression",
                DiagnosticSpanFromTokenRange(leftParenToken, arrowToken))
        }
        return new ExprResult(new RecoverySpan(line, column, 1), false)
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

    // Parser.cs ParseRelationalExpression (:4132). Carries the four comparison operators plus the `is` / `as`
    // TYPE sub-grammar arms (Stage 11): each parses a type reference through the shared ParseTypeReferenceRecovery
    // (the SAME type-reference vehicle as typeof / sizeof / cast), reporting the type-reference errors it reports
    // (missing type name NL102, qualified `.` NL102, generic-argument NL102, unclosed `>` NL102). Since Stage 15
    // ParseTypeReferenceRecovery is the full grammar, the richer forms (union `A | B`, postfix array `[]` /
    // nullable `?`, byref `&`, tuple `( … )`, `Func<>`) fire here identically. The invalid-relational default
    // (:4177) is an unreachable dead arm (the switch handles every token the guard admits, and the is/as arms are
    // peeled off before it).
    func ParseRelational(): ExprResult {
        result := ParseShift()
        while Check(TokenType.Less) || Check(TokenType.LessEqual) || Check(TokenType.Greater) || Check(TokenType.GreaterEqual) || Check(TokenType.Is) || Check(TokenType.As) {
            if Check(TokenType.Is) {
                // `expr is Type [name]` (Parser.cs :4140). The optional trailing identifier is the pattern
                // variable; consuming it reports nothing. An IsExpression is anchored on the `is` token, so its
                // DiagnosticSpanFromExpression falls to the (isLine, isColumn, 1) default (:5960).
                isToken := Advance()
                ParseTypeReferenceRecovery()
                if Check(TokenType.Identifier) {
                    Advance()
                }
                result = new ExprResult(new RecoverySpan(isToken.Line, isToken.Column, 1), false)
            } else {
                if Check(TokenType.As) {
                    // `expr as Type` (Parser.cs :4153). A safe-cast CastExpression is anchored on the `as`
                    // token, so its DiagnosticSpanFromExpression falls to the (asLine, asColumn, 1) default.
                    asToken := Advance()
                    ParseTypeReferenceRecovery()
                    result = new ExprResult(new RecoverySpan(asToken.Line, asToken.Column, 1), false)
                } else {
                    opToken := Advance()
                    if !BinaryRightOperandMissing(opToken, result.Span) {
                        ParseShift()
                    }
                    result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
                }
            }
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

        // Char / string literals run the malformed-literal check (Parser.cs :4643/:4650). The malformed check
        // runs FIRST (Parser.cs :4653), so an unterminated `$"…` still reports NL105 (Stage 3) before the hole
        // grammar runs. A StringLiteral whose value begins `$"` OR an InterpolatedRawStringLiteral then routes
        // into the interpolated-string HOLE grammar (Parser.cs :4654-4657, Stage 12); every other string is a
        // plain literal.
        if Check(TokenType.CharLiteral) {
            token := Advance()
            ReportMalformedCharLiteralIfNeeded(token)
            return new ExprResult(new RecoverySpan(token.Line, token.Column, MaxInt(1, token.Value.Length)), false)
        }
        if Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral) {
            token := Advance()
            ReportMalformedStringLiteralIfNeeded(token)
            if token.Type == TokenType.StringLiteral && StartsWithInterpolatedPrefix(token.Value) {
                return ParseInterpolatedString(token, line, column, false)
            }
            if token.Type == TokenType.InterpolatedRawStringLiteral {
                return ParseInterpolatedString(token, line, column, true)
            }
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

        // alloc primary (Parser.cs ParseAllocExpression :5178, dispatched at :4747). The `alloc` keyword wraps
        // a new / array-literal / string-primary / unary sub-shape, all of which are already-owned grammars, so
        // alloc adds no new error site of its own (the guarded Consume(Alloc) never fires). An AllocExpression is
        // anchored on the `alloc` keyword, so its DiagnosticSpanFromExpression falls to the (line, column, 1)
        // default (:5960).
        if Check(TokenType.Alloc) {
            Advance()                                       // consume 'alloc'
            if Check(TokenType.New) {
                ParseNewExpression()
            } else {
                if Check(TokenType.LeftBracket) {
                    ParseArrayLiteral()
                } else {
                    if Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral) {
                        ParsePrimaryExprValue()             // Parser.cs :5190 routes a string through ParsePrimaryExpression
                    } else {
                        ParseUnary()                        // Parser.cs :5193 the general unary operand
                    }
                }
            }
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        // stackalloc primary (Parser.cs ParseStackAllocExpression :5197, dispatched at :4752): an element TYPE
        // reference, then `[` length `]`. The `[` uses the distinct "Expected '[' after stackalloc element type"
        // NL102 message; the `]` routes through the Stage-9 closing-delimiter recovery (NL108 next-line / EOF,
        // else the distinct "Expected ']' after stackalloc length" NL102). A StackAllocExpression is anchored on
        // the `stackalloc` keyword, so its DiagnosticSpanFromExpression falls to the (line, column, 1) default.
        if Check(TokenType.Stackalloc) {
            Advance()                                       // consume 'stackalloc'
            ParseTypeReferenceRecovery()                    // the element type (Parser.cs :5202)
            ConsumeToken(TokenType.LeftBracket, "Expected '[' after stackalloc element type", "[")
            ParseExprValue()                                // the length (Parser.cs :5204)
            ConsumeToken(TokenType.RightBracket, "Expected ']' after stackalloc length", "]")
            return new ExprResult(new RecoverySpan(line, column, 1), false)
        }

        // new expression (Parser.cs :4758).
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
    // Stage 12: the interpolated-string `$"…"` HOLE grammar (Parser.cs ParseInterpolatedString :4932),
    // carried through the SAME shared-panic model. Reached from ParsePrimaryExprValue's string-literal arm:
    // a StringLiteral beginning `$"` OR an InterpolatedRawStringLiteral (`$"""…"""`). The whole `$"…"` is ONE
    // outer token; ParseInterpolatedString char-scans the token VALUE, and for each `{expr[:format]}` hole
    // opens a FRESH sub-Lexer + sub-Parser (Parser.cs `new Parser(subTokens, _fileName)`) whose position-
    // adjusted errors are appended to the outer diagnostics. The site inventory (grep of Parser.cs
    // ParseInterpolatedString): ZERO `Consume` sites and exactly ONE explicit ReportError — the NL101
    // "…after interpolated string expression" hole-tail (:5141) — but every HOLE-EXPRESSION error is produced
    // by the sub-parser reaching the owned expression grammar. The malformed-`$"…"` NL105 (unterminated) is
    // already owned (Stage 3, via ReportMalformedStringLiteralIfNeeded, which Parser.cs runs FIRST at :4653).
    //
    // PANIC INDEPENDENCE (verified against the freshly built Release CLI oracle): each hole's sub-parser has
    // its own `_panicMode`, so two bad holes in one string BOTH report (`$"{a +} {b +}"` → two NL102). The
    // OUTER parser's panic is unaffected by hole errors, and a hole error records even when the outer parser is
    // mid-panic — because Parser.cs appends the sub-parser's errors via `_errors.AddRange(...)`, bypassing the
    // outer panic gate (`print + $"{b +}"` → BOTH the outer prefix-plus NL103 AND the hole NL102). WITHIN a
    // hole the sub-panic cascades, so a hole-expression error suppresses the hole-tail NL101 (`$"{+ a b}"` →
    // only the prefix-plus NL103, the trailing `b` is swallowed). The recovery model is a single instance, so
    // a hole is modelled by ParseHoleExpression SAVING the outer cursor/panic state, swapping in the sub-token
    // stream with a fresh panic universe, and RESTORING afterward (see there).
    // ============================================================================

    func ParseInterpolatedString(token: Token, line: int, column: int, isRaw: bool): ExprResult {
        value := token.Value

        // `$"…"` skips 2, `$"""…"""` skips 4 (Parser.cs :4937). end excludes the closing quote(s), or is the
        // full length when unterminated (Parser.cs :4938 — the malformed NL105 was already reported).
        start := 2
        if isRaw {
            start = 4
        }
        end := value.Length - 1
        if isRaw {
            end = value.Length - 3
        }
        closing := "\""
        if isRaw {
            closing = "\"\"\""
        }
        if end < start || !EndsWithString(value, closing) {
            end = value.Length
        }

        currentLine := line
        currentCol := column + start
        i := start

        while i < end {
            ch := value[i]

            // Escape `\x` (non-raw only, Parser.cs :4985): both chars are literal text.
            if !isRaw && ch == '\\' && i + 1 < end {
                if ch == '\n' {
                    currentLine = currentLine + 1
                    currentCol = 1
                } else {
                    currentCol = currentCol + 1
                }
                i = i + 1
                escaped := value[i]
                if escaped == '\n' {
                    currentLine = currentLine + 1
                    currentCol = 1
                } else {
                    currentCol = currentCol + 1
                }
                i = i + 1
                continue
            }

            // `{{` escape (Parser.cs :4997) and `}}` escape (Parser.cs :5007): a literal brace.
            if ch == '{' && i + 1 < end && value[i + 1] == '{' {
                currentCol = currentCol + 1
                i = i + 1
                currentCol = currentCol + 1
                i = i + 1
                continue
            }
            if ch == '}' && i + 1 < end && value[i + 1] == '}' {
                currentCol = currentCol + 1
                i = i + 1
                currentCol = currentCol + 1
                i = i + 1
                continue
            }

            if ch == '{' {
                // Raw `{`-literal heuristic (Parser.cs :5019): inside a raw string a `{` preceded by `:`, or
                // with no closing `}`, or whose content spans lines is literal text, not a hole.
                if isRaw {
                    previous := i - 1
                    while previous >= start && char.IsWhiteSpace(value[previous]) {
                        previous = previous - 1
                    }
                    nextClose := IndexOfCharFrom(value, '}', i + 1)
                    contentSpansLine := false
                    if nextClose >= 0 {
                        contentSpansLine = RangeContainsNewline(value, i + 1, nextClose)
                    }
                    if (previous >= start && value[previous] == ':') || nextClose < 0 || contentSpansLine {
                        currentCol = currentCol + 1
                        i = i + 1
                        continue
                    }
                }

                // A hole. Advance past `{`; the sub-lexer anchors at the position just past it (Parser.cs :5042).
                currentCol = currentCol + 1
                i = i + 1
                exprStartLine := currentLine
                exprStartCol := currentCol

                exprContentStart := i
                braceDepth := 1
                inNestedString := false
                while i < end && braceDepth > 0 {
                    ch = value[i]
                    if inNestedString {
                        if ch == '\\' && i + 1 < end {
                            currentCol = currentCol + 1     // AdvancePosition('\\'); a backslash is never '\n'
                            i = i + 1
                            ch = value[i]
                        } else {
                            if ch == '"' {
                                inNestedString = false
                            }
                        }
                    } else {
                        if ch == '"' {
                            inNestedString = true
                        } else {
                            if ch == '{' {
                                braceDepth = braceDepth + 1
                            } else {
                                if ch == '}' {
                                    braceDepth = braceDepth - 1
                                    if braceDepth == 0 {
                                        break
                                    }
                                }
                            }
                        }
                    }
                    if ch == '\n' {
                        currentLine = currentLine + 1
                        currentCol = 1
                    } else {
                        currentCol = currentCol + 1
                    }
                    i = i + 1
                }

                exprContent := value.Substring(exprContentStart, i - exprContentStart)

                // Raw hole content that spans lines is literal text, not an expression (Parser.cs :5101).
                if isRaw && ContainsNewline(exprContent) {
                    if i < end && value[i] == '}' {
                        currentCol = currentCol + 1
                        i = i + 1
                    }
                    continue
                }

                // Split off a `:format` clause (Parser.cs :5117); only the expression part is sub-parsed.
                colonPos := ParserLiteralFacts.FindFormatSpecifierColon(exprContent)
                if colonPos >= 0 {
                    exprContent = exprContent.Substring(0, colonPos)
                }

                ParseHoleExpression(exprContent, exprStartLine, exprStartCol)

                // Consume the closing `}` (Parser.cs :5154).
                if i < end && value[i] == '}' {
                    currentCol = currentCol + 1
                    i = i + 1
                }
                continue
            }

            // Ordinary text char.
            if ch == '\n' {
                currentLine = currentLine + 1
                currentCol = 1
            } else {
                currentCol = currentCol + 1
            }
            i = i + 1
        }

        // An InterpolatedStringExpression is anchored on (line, column); its DiagnosticSpanFromExpression falls
        // to the (line, column, 1) default and it is never a bare identifier (Parser.cs :5172).
        return new ExprResult(new RecoverySpan(line, column, 1), false)
    }

    // Sub-parse one interpolation hole through a FRESH sub-Lexer + sub-Parser (Parser.cs :5126-5150). Parser.cs
    // builds `new Parser(subTokens, _fileName)` — a wholly separate parser with its OWN _panicMode — parses one
    // expression, reports the hole-tail if extra tokens remain, then appends its errors to the outer parser via
    // `_errors.AddRange(...)`. The recovery model is a single instance, so this SAVES the outer cursor/panic
    // state, swaps in the position-adjusted sub-token stream with a fresh panic universe (PanicMode=false), runs
    // the owned expression grammar + the hole-tail, then RESTORES the outer state. Running with PanicMode=false
    // reproduces the AddRange bypass (the hole records even when the outer parser is mid-panic); restoring the
    // outer panic afterward keeps a hole error from ever affecting the outer panic universe. Errors and Source
    // are SHARED (not saved): hole diagnostics accumulate into the same list, and the CLI's by-line snippet
    // re-attachment (the sub-parser's sourceCode is null) matches the model's Source-based snippet automatically.
    func ParseHoleExpression(exprContent: string, exprStartLine: int, exprStartCol: int) {
        subLexer := new Lexer(exprContent, FileName)
        subRaw := subLexer.Tokenize()

        // Adjust each sub-token's position into the enclosing file (Parser.cs :5129-5135): every token's line is
        // offset by the hole's start line; a FIRST-line token additionally offsets its column by the hole's start
        // column (a later-line token already begins at column 1 in both frames). Then drop Newline tokens exactly
        // as the Parser constructor's compaction does.
        subTokens := new List<Token>()
        t := 0
        while t < subRaw.Count {
            tok := subRaw[t]
            adjustedLine := tok.Line + exprStartLine - 1
            adjustedColumn := tok.Column
            if tok.Line == 1 {
                adjustedColumn = tok.Column + exprStartCol - 1
            }
            if tok.Type != TokenType.Newline {
                subTokens.Add(new Token(tok.Type, tok.Value, adjustedLine, adjustedColumn, tok.FileName, tok.IsTerminated))
            }
            t = t + 1
        }

        savedTokens := Tokens
        savedPosition := Position
        savedPanic := PanicMode
        savedSplit := SplitGreaterDepth
        savedBoundaryColumn := RecoveryBoundaryColumn
        savedHasBoundaryColumn := HasRecoveryBoundaryColumn

        Tokens = subTokens
        Position = 0
        PanicMode = false
        SplitGreaterDepth = 0
        HasRecoveryBoundaryColumn = false

        ParseExprValue()

        // The lone explicit ReportError (Parser.cs :5141): extra syntax after the hole expression. Routed through
        // the SUB-parser's Report, so a hole-expression error that already tripped the sub-panic suppresses this.
        if !IsAtEnd() {
            Report(
                ErrorCode.UnexpectedToken,
                "Unexpected token '" + Current().Value + "' after interpolated string expression",
                Current().Line,
                Current().Column,
                "I parsed a valid expression at the start of this interpolation hole, but there was extra syntax after it.",
                "Keep exactly one expression inside each interpolation hole, or split additional text outside the braces.",
                null,
                MaxInt(1, Current().Value.Length))
        }

        Tokens = savedTokens
        Position = savedPosition
        PanicMode = savedPanic
        SplitGreaterDepth = savedSplit
        RecoveryBoundaryColumn = savedBoundaryColumn
        HasRecoveryBoundaryColumn = savedHasBoundaryColumn
    }

    // Index of `target` in `value` at or after `startIndex`, else -1 (Parser.cs `value.IndexOf('}', i + 1)`).
    func IndexOfCharFrom(value: string, target: char, startIndex: int): int {
        idx := startIndex
        while idx < value.Length {
            if value[idx] == target {
                return idx
            }
            idx = idx + 1
        }
        return -1
    }

    // Whether `value[startIndex, endIndexExclusive)` contains a CR or LF (Parser.cs `.IndexOfAny({'\r','\n'})`).
    func RangeContainsNewline(value: string, startIndex: int, endIndexExclusive: int): bool {
        idx := startIndex
        while idx < endIndexExclusive {
            c := value[idx]
            if c == '\r' || c == '\n' {
                return true
            }
            idx = idx + 1
        }
        return false
    }

    func ContainsNewline(text: string): bool {
        idx := 0
        while idx < text.Length {
            c := text[idx]
            if c == '\r' || c == '\n' {
                return true
            }
            idx = idx + 1
        }
        return false
    }

    // Ordinal EndsWith (Parser.cs uses `value.EndsWith(closing, StringComparison.Ordinal)`); written by hand so
    // the owner needs no `import System` for StringComparison and the comparison is unambiguously ordinal.
    func EndsWithString(text: string, suffix: string): bool {
        if suffix.Length > text.Length {
            return false
        }
        offset := text.Length - suffix.Length
        k := 0
        while k < suffix.Length {
            if text[offset + k] != suffix[k] {
                return false
            }
            k = k + 1
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

    // Mirror Parser.cs's `pathToken.Value.Trim('"')` (:150): strip every leading and trailing
    // double-quote character from the raw string-literal token value.
    func TrimQuotes(value: string): string {
        start := 0
        stop := value.Length
        while start < stop && value[start] == '"' {
            start = start + 1
        }
        while stop > start && value[stop - 1] == '"' {
            stop = stop - 1
        }
        return value.Substring(start, stop - start)
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

    // ============================================================================
    // Stage 16: the TEST DSL + ATTRIBUTES diagnostic family — carried through the SAME shared-panic
    // model. The test-DSL declarations (`test "desc" { … }`, `setup { … }`, `teardown { … }`) are
    // dispatched from ParseTopLevelDeclaration BEFORE attributes/modifiers (Parser.cs ParseDeclaration
    // :192-202), so each is its own declaration and resets panic at the Run() declaration boundary.
    // Attributes (`[Name(args)]`) precede modifiers on top-level declarations (:214), members (:1424),
    // and parameters (:770). Every error site reduces to an already-owned primitive: the description /
    // skip string-literal ExpectedToken reports go straight through Report; the table `[` / row `(`
    // Consumes are plain ConsumeToken; the row `)` / cases `]` / attribute `]` closes route through the
    // Stage-9 closing-delimiter recovery; the attribute name reuses the Stage-1 ConsumeIdentifier; the
    // attribute args reuse the Stage-10 ParseArgumentList; the bodies reuse the Stage-6/13 ParseBlock.
    // ============================================================================

    // Parser.cs IsTestDeclarationStart (:642): the `test` keyword token OR the contextual identifier.
    func IsTestDeclarationStart(): bool {
        if Check(TokenType.Test) {
            return true
        }
        return Check(TokenType.Identifier) && Current().Value == "test"
    }

    // Parser.cs IsSetupDeclarationStart (:667): the contextual `setup` identifier followed by `{`.
    func IsSetupDeclarationStart(): bool {
        return Current().Type == TokenType.Identifier && Current().Value == "setup" && LookAhead(1).Type == TokenType.LeftBrace
    }

    // Parser.cs IsTeardownDeclarationStart (:704): the contextual `teardown` identifier followed by `{`.
    func IsTeardownDeclarationStart(): bool {
        return Current().Type == TokenType.Identifier && Current().Value == "teardown" && LookAhead(1).Type == TokenType.LeftBrace
    }

    // Parser.cs ConsumeTestKeyword (:650): advance past the `test` keyword (Test token or the contextual
    // identifier). The final Consume(Test) fallback never fires — this is only reached when
    // IsTestDeclarationStart already matched — but it is modelled faithfully.
    func ConsumeTestKeyword() {
        if Check(TokenType.Test) {
            Advance()
            return
        }
        if Check(TokenType.Identifier) && Current().Value == "test" {
            Advance()
            return
        }
        ConsumeToken(TokenType.Test, "Expected 'test'", "test")
    }

    // Parser.cs ParseTestDeclaration (:546). The description must be a string literal (else the
    // ExpectedToken report + skip-the-offender); the optional table-driven `with (params) [ rows ]`;
    // the optional `skip "reason"`; then the block body (owner span = the `test` keyword, length 4).
    func ParseTestDeclaration() {
        line := Current().Line
        column := Current().Column
        ConsumeTestKeyword()

        // Test description must be a string literal (Parser.cs :554).
        if Current().Type != TokenType.StringLiteral {
            descSuggestions := new List<string>()
            descSuggestions.Add("Example: test \"should calculate sum correctly\" { ... }")
            descSuggestions.Add("Example: test \"validates user input\" { ... }")
            Report(
                ErrorCode.ExpectedToken,
                "Expected string literal for test description. Got '" + Current().Value + "'",
                Current().Line,
                Current().Column,
                "Test declarations require a string literal describing what the test does.",
                "A test should start with the 'test' keyword followed by a string in quotes.",
                descSuggestions,
                Current().Value.Length)
            if !IsAtEnd() {
                Advance()                               // skip the invalid token (Parser.cs :570)
            }
        } else {
            Advance()
        }

        // Table-driven test syntax `with (params) [ (row), … ]` (Parser.cs :582).
        if Check(TokenType.With) {
            Advance()                                   // consume 'with'
            ParseParameterListRecovery()

            ConsumeToken(TokenType.LeftBracket, "Expected '[' to start test cases", "[")
            while !Check(TokenType.RightBracket) && !IsAtEnd() {
                ConsumeToken(TokenType.LeftParen, "Expected '(' to start test case row", "(")
                while !Check(TokenType.RightParen) && !IsAtEnd() {
                    ParseExprValue()                    // Parser.cs ParseExpression (:596)
                    if !Check(TokenType.RightParen) {
                        if Check(TokenType.Comma) {     // Parser.cs Match(Comma) (:598)
                            Advance()
                        }
                    }
                }
                ConsumeToken(TokenType.RightParen, "Expected ')' to end test case row", ")")
                if !Check(TokenType.RightBracket) {
                    if Check(TokenType.Comma) {         // Parser.cs Match(Comma) (:603)
                        Advance()
                    }
                }
            }
            ConsumeToken(TokenType.RightBracket, "Expected ']' to end test cases", "]")
        }

        // Skip modifier `skip "reason"` (Parser.cs :611). The invalid-reason report does NOT skip the
        // offender (matching Parser.cs), so a following block/EOF continues from that token.
        if Current().Type == TokenType.Identifier && Current().Value == "skip" {
            Advance()                                   // consume 'skip'
            if Current().Type != TokenType.StringLiteral {
                skipSuggestions := new List<string>()
                skipSuggestions.Add("Example: test \"my test\" skip \"needs network\" { ... }")
                Report(
                    ErrorCode.ExpectedToken,
                    "Expected string literal for skip reason. Got '" + Current().Value + "'",
                    Current().Line,
                    Current().Column,
                    "The 'skip' modifier requires a string explaining why the test is skipped.",
                    "Add a reason string after 'skip'.",
                    skipSuggestions,
                    Current().Value.Length)
            } else {
                Advance()
            }
        }

        // Test body (Parser.cs :637). Owner span = the `test` keyword (line, column, "test".Length == 4).
        ParseBlock(new RecoverySpan(line, column, MaxInt(1, 4)))
    }

    // Parser.cs ParseSetupDeclaration (:695): advance past `setup`, then the block body (owner span =
    // the `setup` keyword, length 5). No own error site beyond the block.
    func ParseSetupDeclaration() {
        line := Current().Line
        column := Current().Column
        Advance()                                       // consume 'setup'
        ParseBlock(new RecoverySpan(line, column, MaxInt(1, 5)))
    }

    // Parser.cs ParseTeardownDeclaration (:710): advance past `teardown`, then the block body (owner
    // span = the `teardown` keyword, length 8). No own error site beyond the block.
    func ParseTeardownDeclaration() {
        line := Current().Line
        column := Current().Column
        Advance()                                       // consume 'teardown'
        ParseBlock(new RecoverySpan(line, column, MaxInt(1, 8)))
    }

    // Parser.cs ParseAttributes (:269): a loop of `[ Name(.Name)* (args)? ]`. The name reuses the
    // ConsumeAttributeIdentifier (Identifier/Alloc/Allow, else the owned ConsumeIdentifier NL102); the
    // optional `(args)` reuses the Stage-10 ParseArgumentList; the closing `]` routes through the
    // Stage-9 closing-delimiter recovery (ConsumeToken → NL108 when unclosed, else the plain NL102).
    // Stage N+1c tranche 4: return the materialized `AttributeNode` list (Parser.cs :292 —
    // `new AttributeNode(name, args, attributeLine, attributeColumn)`; the line is the `[` line, the column is
    // the `[` column + 1 — Parser.cs :274-275). The ARGUMENT-FREE shape materializes a byte-exact node with an
    // empty Argument list; an argument-bearing attribute (or an `<error>` name) carries Argument/Expression
    // nodes that are a later tranche, so it clears `AttributesMaterializable` and the enclosing declaration
    // declines materialization (no-stub — never partially compared). Callers capture `AttributesMaterializable`
    // into a local immediately after this returns.
    func ParseAttributes(): List<AttributeNode> {
        AttributesMaterializable = true
        attributes := new List<AttributeNode>()
        while Check(TokenType.LeftBracket) {
            attrLine := Current().Line
            attrColumn := Current().Column + 1          // Parser.cs :275
            Advance()                                   // consume '['
            name := ConsumeAttributeIdentifier("Expected attribute name")
            while Check(TokenType.Dot) {
                Advance()                               // consume '.'
                name = name + "." + ConsumeAttributeIdentifier("Expected identifier after '.'")
            }
            hasArgs := false
            if Check(TokenType.LeftParen) {
                hasArgs = true
                Advance()                               // consume '('
                ParseArgumentList()
            }
            ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
            if hasArgs || name == "<error>" {
                AttributesMaterializable = false        // argument/error attribute → decline the declaration
            } else {
                attributes.Add(new AttributeNode(name, new List<Argument>(), attrLine, attrColumn))
            }
        }
        return attributes
    }

    // Parser.cs ConsumeAttributeIdentifier (:6811): an attribute name may be an Identifier or the
    // contextual Alloc / Allow keywords; anything else falls through to the shared ConsumeIdentifier.
    func ConsumeAttributeIdentifier(message: string): string {
        if Check(TokenType.Identifier) || Check(TokenType.Alloc) || Check(TokenType.Allow) {
            return Advance().Value
        }
        return ConsumeIdentifier(message)
    }
}

namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence


// A diagnostic span (line / column / length) used to anchor recovery diagnostics.
// A local reference type rather than the C#-owned DiagnosticSpan value struct.
class RecoverySpan {
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
class ExprResult {
    Span: RecoverySpan
    IsBareIdentifier: bool
    // Stage N+1c tranche 7 (BEGIN EXPRESSION MATERIALIZATION): the byte-exact Expression node this tier
    // parsed, or null when the value is not yet materializable (a composed operator tier, or a non-leaf
    // primary whose sub-grammar is a later tranche). The ladder's non-operator tiers `return result`/
    // `return expr` UNCHANGED, so a leaf node set by the primary tier propagates up automatically; every
    // operator-composing tier reconstructs `new ExprResult(...)` (Node null by default), so a value that
    // composes any operator declines. A mutable field defaulting to null keeps the ~30 existing
    // constructor call sites untouched — materialization sites set `.Node` explicitly after construction.
    Node: Expression?

    constructor(span: RecoverySpan, isBareIdentifier: bool) {
        Span = span
        IsBareIdentifier = isBareIdentifier
        Node = null
    }
}

// Stage 9: the outcome of TryReportMissingClosingDelimiter (Parser.cs :6103, whose C# signature
// is `bool Try…(out Token recoveredToken)`). N# has no reference-typed out args, so the shared
// result is carried in an explicit result object (the established recovery-owner precedent):
// Handled mirrors the bool return (the closing-delimiter recovery path was taken — a diagnostic
// was reported subject to the shared panic, and a synthetic closing token stands in), and
// RecoveredToken mirrors the out parameter (the synthesized `)` / `]` the caller returns).
class ClosingDelimiterRecovery {
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
class TokenLookupResult {
    Found: bool
    Token: Token

    constructor(found: bool, token: Token) {
        Found = found
        Token = token
    }
}

// Stage 9: the outcome of TryGetDelimiterOwnerSpan (Parser.cs :6237, `bool Try…(out (int,int,int) span)`).
class OwnerSpanResult {
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
class PreambleAst {
    Namespace: NamespaceDeclaration?
    Imports: List<ImportDirective>
    Package: PackageDeclaration?
    Errors: List<CompilerError>

    constructor(namespaceDecl: NamespaceDeclaration?, imports: List<ImportDirective>, packageDecl: PackageDeclaration?, errors: List<CompilerError>) {
        Namespace = namespaceDecl
        Imports = imports
        Package = packageDecl
        Errors = errors
    }
}

// Stage N+2 (the PRODUCTION CUTOVER): the owner's whole-file parse output — exactly the pair every
// consumer of Parser.cs reads off `ParseResult`. The field NAMES mirror ParseResult's (`CompilationUnit`
// / `Errors`) so a routed consumer's downstream reads are unchanged; `Success` is deliberately absent
// because no consumer reads it (verified consumer-by-consumer; see the STATUS N+1 design record).
// Errors are in Parser.cs's RECORDING order — the raw `_errors` order ParseResult carries, NOT the
// position-sorted order ParseFilePreamble returns for the CLI-shaped oracle comparison.
class FileParseAst {
    CompilationUnit: CompilationUnit?
    Errors: List<CompilerError>

    constructor(unit: CompilationUnit?, errors: List<CompilerError>) {
        CompilationUnit = unit
        Errors = errors
    }

    // Stage N+3: the last member `ParseResult` exposed that this type did not, reproduced exactly
    // (`CompilationUnit != null && !Errors.Any(e => e.Severity == ErrorSeverity.Error)`). With it the
    // owner's result is a complete drop-in and the C# `ParseResult` record retires with `Parser.cs`.
    Success: bool {
        get {
            if CompilationUnit == null {
                return false
            }

            index := 0
            while index < Errors.Count {
                if Errors[index].Severity == ErrorSeverity.Error {
                    return false
                }

                index = index + 1
            }

            return true
        }
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
class ColumnarParserRecovery {
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
    TypeMemberStack: List<List<Declaration>>
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
    // Stage N+1c tranche 6 (type-parameter lists + base/interface lists): transient no-stub gates, set by
    // ParseTypeParameters / ParseBaseTypeList and captured by the caller into a local IMMEDIATELY (before any
    // ParseTypeBody, whose nested declarations overwrite these fields). BaseListMaterializable is cleared
    // when a base/interface type is structurally unbuildable (ParseMaterializedTypeReference returns null).
    // An ABSENT list leaves the gate true (the null / empty case Parser.cs also produces).
    // Stage N+1c tranche 11 RETIRED the type-parameter gate: a malformed `<>` / `<T,>` / reserved-keyword
    // list is a Parser.cs RECOVERY ARTIFACT (it keeps the partial list and its `<error>` names, :757), now
    // reproduced rather than declined.
    BaseListMaterializable: bool
    // Stage N+1c tranche 6 (type bodies): the shared no-stub gate for the union / enum / soa body loops, set
    // by ParseUnionBody / ParseEnumBody / ParseSoaRecordBody and captured by the caller into a local
    // IMMEDIATELY. Cleared when the body carries a shape not yet byte-exactly representable (an `<error>` case
    // / member / column name, a structurally-unbuildable / multi-line payload or column type, or the
    // generic-soa error shape). Tranche 7: a value-bearing enum member whose value MATERIALIZES (a leaf/paren
    // atom) NO LONGER clears this — only a value that fails to materialize (a composed / deferred expression
    // form) does. These bodies never nest another body-materialization within themselves (a case payload /
    // soa column type routes through ParseMaterializedTypeReference, which does NOT touch this field; an enum
    // value routes through ParseExprValue), so one shared field is safe.
    TypeBodyMaterializable: bool
    // Stage N+1c tranche 7 (enum string-value inference): Parser.cs :1304 infers EnumType.String when the
    // enum has no explicit `: int|string` backing type AND its FIRST member's value is a StringLiteralExpression.
    // ParseEnumBody sets this from the materialized first-member value; ParseEnumName applies it only when the
    // backing type was not explicit, keeping the owner byte-exact for string-valued enums.
    EnumBodyInferredString: bool
    // Stage N+1c tranche 9b: the verdict of the LAST `ParseGatedTypeReference` call — whether the raw parsed
    // TypeReference also passed the materialization gate (non-null, not entered in panic, no diagnostic during
    // the parse, single-line). Written and read back-to-back at each gated call site, so no nesting hazard.
    TypeReferenceMaterialized: bool
    // Stage N+1c tranche 10 (STATEMENT BODIES): whether the LAST `ParseVariableDeclaration` call took the
    // TUPLE-DECONSTRUCTION arm. Parser.cs's using-statement makes this decision with `stmt as
    // VariableDeclarationStatement` on the RETURNED node (:3078), which cannot be reproduced when the node
    // legitimately DECLINES materialization — so the arm taken is recorded here instead and read by the
    // caller IMMEDIATELY after the call (the established transient-gate idiom; a nested declaration cannot
    // intervene between the write and the read).
    VariableDeclarationWasTuple: bool
    // Stage N+1c tranche 10b (member BODIES): the transient no-stub gate for `ParseGenericConstraints` —
    // cleared when a constraint type is not byte-exactly representable or a `where` type-parameter name is
    // `<error>`. Read by the caller IMMEDIATELY after the call, like the other list gates.
    ConstraintsMaterializable: bool
    // Stage N+1c tranche 10b: the byte-exact `returns …` lifetime string ParseReturnLifetimeAnnotation
    // parsed (Parser.cs :511 returns `string?`). Read IMMEDIATELY after the call. Tranche 11 RETIRED the
    // companion gate: Parser.cs's terminal arm reports and returns a NULL lifetime (:517), and an `<error>`
    // owner name is interpolated verbatim (:510) — neither declines.
    ReturnLifetimeValue: string?
    // Stage N+1c tranche 11: depth of the interpolated-string HOLE sub-parse. Parser.cs builds its hole
    // sub-parser with `new Parser(subTokens, _fileName)` — NO sourceCode — so a hole diagnostic reported with
    // a requested length of 0 (an empty-valued token, i.e. the hole's EOF) resolves through
    // DiagnosticSpanResolver with a NULL source line and lands on (column, 1). The owner SHARES `Source` with
    // the outer parser (so the hole diagnostic still carries the CLI-shaped snippet the Stage-12 contracts
    // pin), which would otherwise let the resolver infer a token width from the line and shift the column.
    // Clamping a 0 length to 1 while inside a hole reproduces the no-source resolution exactly: for every
    // requested length > 0 the resolver already ignores the line.
    HoleDepth: int

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
        TypeMemberStack = new List<List<Declaration>>()
        ParamListMaterializable = true
        AttributesMaterializable = true
        BaseListMaterializable = true
        TypeBodyMaterializable = true
        EnumBodyInferredString = false
        TypeReferenceMaterialized = false
        VariableDeclarationWasTuple = false
        ConstraintsMaterializable = true
        ReturnLifetimeValue = null
        HoleDepth = 0

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
    static func ParseFilePreamble(source: string, fileName: string?): List<CompilerError> {
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
    static func ParseFilePreambleAst(source: string, fileName: string?): PreambleAst {
        recovery := new ColumnarParserRecovery(source, fileName)
        recovery.Run()
        return new PreambleAst(recovery.NamespaceNode, recovery.ImportNodes, recovery.PackageNode, recovery.SortErrorsByPosition(recovery.Errors))
    }

    // Stage N+1c (full-tree AST materialization) / Stage N+2 (the PRODUCTION CUTOVER): parse a WHOLE file
    // and return the production `CompilationUnit` the owner constructs together with the owned diagnostics —
    // the exact pair Parser.cs's ParseCompilationUnit hangs on ParseResult (:111/:115), assembled from the
    // preamble nodes, the file-import statements, and the top-level declaration nodes materialized as a
    // side-effect of the recovery grammar. Line/Column are the first-token position (Parser.cs :33-34);
    // Errors are Parser.cs's RECORDING order, not the position-sorted CLI-oracle order. This is now the
    // PRODUCTION parse entry: every consumer that read `ParseResult` reads this instead, and the tokenizing
    // is internal (the consumer no longer builds a Lexer/Parser pair for parsing).
    static func ParseFileAst(source: string, fileName: string?): FileParseAst {
        recovery := new ColumnarParserRecovery(source, fileName)
        recovery.Run()
        return new FileParseAst(new CompilationUnit(recovery.NamespaceNode, recovery.ImportNodes, recovery.FileImportNodes, recovery.PackageNode, recovery.DeclarationNodes, recovery.UnitLine, recovery.UnitColumn), recovery.Errors)
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
        // Split-`>>` discipline: while we owe a `>` from a previously split `>>`, the owed `>` IS the
        // effective current token — a request for `>` is satisfied without consuming a real token, and
        // a request for ANY other type must answer false, because Advance would hand back the owed `>`
        // first. (Parser.cs :6025 only special-cased `>` and let other requests read the real cursor,
        // which desynced Check/Advance: after splitting the `>>` in `List<List<int>>?`, Check(Question)
        // matched the real `?` but the paired Advance consumed the owed `>` — the inner type got
        // nullable-wrapped twice and the outer close reported a spurious "Expected '>'".)
        if SplitGreaterDepth > 0 {
            return tokenType == TokenType.Greater
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

    func Report(code: ErrorCode, message: string, line: int, column: int, humanExplanation: string?, hint: string?, suggestions: List<string>?, length: int) {
        // In panic mode, suppress cascading errors until we synchronize.
        if PanicMode {
            return
        }

        snippet := GetSourceSnippet(line)
        resolvedLength := length
        if HoleDepth > 0 && resolvedLength <= 0 {
            resolvedLength = 1
        }
        // the no-sourceCode hole sub-parser's span resolution (see HoleDepth)

        error := ParserErrorDiagnostics.Create(code, message, FileName, line, column, snippet, resolvedLength, humanExplanation, hint, suggestions)
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
            Report(ErrorCode.UnexpectedEndOfFile, message + ", but reached the end of the file", eofSpan.Line, eofSpan.Column, DotOrPlainEofExplanation(isDotAccess), DotOrPlainEofHint(isDotAccess), null, eofSpan.Length)
            return "<error>"
        }

        span := SpanFromToken(Current())
        Report(ErrorCode.ExpectedToken, message + ". Got '" + Current().Value + "'", span.Line, span.Column, DotOrPlainFoundExplanation(isDotAccess, Current().Value), DotOrPlainFoundHint(isDotAccess), DotAccessFoundSuggestions(isDotAccess), span.Length)
        return "<error>"
    }

    func ReportReservedKeywordAsName(contextMessage: string, span: RecoverySpan, isDotAccess: bool) {
        keyword := Current().Value
        suggestions := new List<string>()
        suggestions.Add("Rename it to '" + keyword + "Value' or '_" + keyword + "'")
        suggestions.Add("Pick any name that isn't a reserved N# keyword")

        Report(ErrorCode.ReservedKeywordAsName, contextMessage + ". Got the reserved keyword '" + keyword + "'", span.Line, span.Column, "'" + keyword + "' is a reserved keyword in N#, so it can't be used as a name here.", ReservedKeywordHint(keyword, isDotAccess), suggestions, span.Length)
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
            Report(ErrorCode.UnexpectedEndOfFile, message + ", but reached the end of the file", anchor.Line, anchor.Column, DotOrPlainEofExplanation(false), DotOrPlainEofHint(false), null, anchor.Length)
            return "<error>"
        }

        Report(ErrorCode.ExpectedToken, message + ". Got '" + Current().Value + "'", anchor.Line, anchor.Column, DotOrPlainFoundExplanation(false, Current().Value), DotOrPlainFoundHint(false), DotAccessFoundSuggestions(false), anchor.Length)
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

    // The package name is parsed segment-by-segment rather than through ParseQualifiedName so a
    // malformed segment can preserve WHAT THE DEVELOPER WROTE. `package good.9bad` used to report
    // "Expected identifier after '.'" here, leave `9`/`bad` for the top-level loop's
    // unexpected-token + `<error>`-class cascade, and hand the analyzer a name whose bad segment
    // was the `<error>` placeholder — its invalid-package-name report then NAMED THE PLACEHOLDER.
    // Now a word-like run written attached to the name is consumed as the segment, text and span
    // intact, with NO parser diagnostic: the segment fails the analyzer's identifier rule, whose
    // one report names and underlines `9bad` and states the actual naming rule. Segments with no
    // written text to carry (end of file, reserved keyword, detached offender) keep the previous
    // ConsumeIdentifier diagnostics and record an `<error>` placeholder segment, which tells the
    // analyzer the parser has already spoken (AnalyzerDeclarationPolicy.ValidatePackageName).
    func ParsePackage() {
        line := Current().Line
        column := Current().Column
        keyword := Current()
        Advance()
        segments := new List<PackageNameSegment>()
        name := ParsePackageSegment(segments, keyword)
        while Check(TokenType.Dot) {
            dot := Current()
            Advance()
            name = name + "." + ParsePackageSegment(segments, dot)
        }
        declaration := new PackageDeclaration(name, line, column)
        declaration.Segments = segments
        PackageNode = declaration
    }

    // One package-name segment. `preceding` is the token the segment hangs off — the `package`
    // keyword for the first segment, the separating dot for the rest — and decides both the
    // ConsumeIdentifier message variant and whether an offending token counts as written-attached.
    func ParsePackageSegment(segments: List<PackageNameSegment>, preceding: Token): string {
        if Check(TokenType.Identifier) {
            token := Advance()
            segments.Add(new PackageNameSegment(token.Value, token.Line, token.Column, TokenLength(token)))
            return token.Value
        }

        if CanRecoverMalformedPackageSegment(preceding) {
            first := Advance()
            text := first.Value
            endColumn := first.Column + first.Value.Length
            while ContinuesMalformedPackageSegment(first.Line, endColumn) {
                next := Advance()
                text = text + next.Value
                endColumn = next.Column + next.Value.Length
            }
            segments.Add(new PackageNameSegment(text, first.Line, first.Column, endColumn - first.Column))
            return text
        }

        message := preceding.Type == TokenType.Dot ? "Expected identifier after '.'" : "Expected identifier"
        placeholder := ConsumeIdentifier(message)
        segments.Add(new PackageNameSegment(placeholder, preceding.Line, preceding.Column, 0))
        return placeholder
    }

    // A malformed segment is recoverable-with-text when the offender sits on the name's own line
    // and is word-like (`good.9bad`, `package 9bad`). Reserved keywords are excluded: their
    // keyword-specific ConsumeIdentifier diagnostic is more precise than the identifier-shape rule.
    func CanRecoverMalformedPackageSegment(preceding: Token): bool {
        if IsAtEnd() {
            return false
        }
        token := Current()
        if token.Line != preceding.Line {
            return false
        }
        if Lexer.IsReservedKeyword(token.Type) {
            return false
        }
        return IsPackageSegmentRunToken(token)
    }

    // The run keeps consuming only tokens written ADJACENT to it (no gap, same line), so
    // `package good.9bad stray` carries `9bad` and leaves `stray` genuinely unexpected. A dot is
    // never part of a run — it separates segments — and mid-run reserved keywords are plain text
    // (`9class` is one written word, not a keyword use).
    func ContinuesMalformedPackageSegment(runLine: int, endColumn: int): bool {
        if IsAtEnd() {
            return false
        }
        token := Current()
        if token.Type == TokenType.Dot {
            return false
        }
        if token.Line != runLine {
            return false
        }
        if token.Column != endColumn {
            return false
        }
        return IsPackageSegmentRunToken(token)
    }

    // Word-like: a token whose written form is name material. Literal token types are listed
    // because their VALUES can carry non-word characters (`9.5` keeps its dot yet is still one
    // written number); everything else — keywords included — qualifies by spelling alone.
    func IsPackageSegmentRunToken(token: Token): bool {
        if token.Type == TokenType.IntLiteral {
            return true
        }
        if token.Type == TokenType.FloatLiteral {
            return true
        }
        if token.Type == TokenType.Identifier {
            return true
        }
        return TokenTextIsWordLike(token.Value)
    }

    static func TokenTextIsWordLike(text: string): bool {
        if text.Length == 0 {
            return false
        }
        index := 0
        while index < text.Length {
            current := text[index]
            if !char.IsLetterOrDigit(current) && current != '_' {
                return false
            }
            index = index + 1
        }
        return true
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
            path := StripSurroundingQuotes(pathToken.Value)
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
                    Report(ErrorCode.InvalidSyntax, "Only one package declaration is allowed", Current().Line, Current().Column, "A source file can belong to a single package.", "Remove the extra package declaration.", null, MaxInt(1, Current().Value.Length))
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
            // NOTE: Parser.cs's top-level loop resets ONLY panic here (:83). The split-`>>` debt is
            // reset exclusively inside SynchronizeToNextDeclaration/Statement (:7044/:7088), so an
            // owed `>` survives a clean declaration boundary exactly as it does in Parser.cs.
            startPosition := Position
            // Stage N+1c tranche 11: Parser.cs's TOP-LEVEL loop also sets the recovery-boundary column to the
            // declaration's first token and restores it afterwards (:85-95) — the same save/set/restore the
            // member and statement loops do. Without it a top-level `record R(` whose parameters start on a
            // LATER line at or left of the declaration keyword's column does not take the
            // IsContinuationRecoveryBoundary break that Parser.cs takes.
            prevTopBoundary := RecoveryBoundaryColumn
            prevTopHasBoundary := HasRecoveryBoundaryColumn
            RecoveryBoundaryColumn = Current().Column
            HasRecoveryBoundaryColumn = true
            ParseTopLevelDeclaration()
            RecoveryBoundaryColumn = prevTopBoundary
            HasRecoveryBoundaryColumn = prevTopHasBoundary

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

        // Top-level preprocessor directive (Parser.cs :205): a bare advance, no diagnostic. Stage N+1c
        // tranche 10b materializes `new PreprocessorDeclaration(directive, line, column)` (:211).
        if Check(TokenType.PreprocessorDirective) {
            directiveLine := Current().Line
            directiveColumn := Current().Column
            directiveText := Current().Value
            Advance()
            AddDeclaration(new PreprocessorDeclaration(directiveText, directiveLine, directiveColumn))
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
            ParseFunctionName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Class) {
            ParseClassName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Ref) {
            if LookAhead(1).Type == TokenType.Struct {
                Advance()
                ParseStructName(modifiers, attributes, attrsOk, true)
                return
            }
        }
        if Check(TokenType.Struct) {
            ParseStructName(modifiers, attributes, attrsOk, false)
            return
        }
        if IsSoaRecordDeclarationStart() {
            ParseSoaRecordName(modifiers, attributes, attrsOk)
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
            ParseUnionName(modifiers, attributes, attrsOk)
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

        Report(ErrorCode.UnexpectedToken, "Unexpected token '" + Current().Value + "'", Current().Line, Current().Column, "I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '" + Current().Value + "' instead.", "Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.", null, Current().Value.Length)
        Advance()
        // Stage N+1c tranche 11 (ERROR-NODE MATERIALIZATION): Parser.cs does NOT drop the offending token —
        // it returns a synthetic `<error>`-named ClassDeclaration placeholder (:255-266) which the caller
        // ADDS to the declaration list. Line/Column are read AFTER the Advance above, so they name the token
        // FOLLOWING the offender (Eof at end of file). Fully qualified for the tests-enabled
        // `class ClassDeclaration` test-helper collision, exactly like the real class site.
        errorTypeParams: List<TypeParameter>? = null
        errorBaseClass: TypeReference? = null
        AddDeclaration(new NSharpLang.Compiler.Ast.ClassDeclaration("<error>", errorTypeParams, errorBaseClass, new List<TypeReference>(), new List<Declaration>(), NoTableParameters(), Modifiers.None, new List<AttributeNode>(), Current().Line, Current().Column))
    }

    // Consume leading modifier keywords (Parser.cs ParseModifiers, :298) so a modifier-led declaration
    // reaches its keyword, and RETURN the byte-exact Modifiers value Parser.cs hangs on the declaration node.
    // The flags are accumulated as an int bitmask and cast back with `(Modifiers)value` — the emittable idiom
    // (DeclarationFacts.nl :52 / TypeInfoFactories.nl :938; enum bitwise operators route through the C# fenced
    // residual and are avoided in dogfood N#). The VALUE set exactly mirrors Parser.cs's recognized flags and
    // order (Public/Private/Static/Internal/Protected/Virtual/Override/Abstract/Sealed/Partial/Async/File).
    // Stage N+1c tranche 10b RETIRES the extra `IsModifierKeyword` catch-all arm: Parser.cs's ParseModifiers
    // has NO `readonly` case and BREAKS there, leaving the token for ParseFieldDeclaration's property-modifier
    // loop (which sets BOTH PropertyModifier.Readonly and Modifiers.Readonly, :1671-1672). Consuming it here
    // swallowed the flag on every `readonly` field in the corpus.
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
        if t == TokenType.Static {
            return System.Convert.ToInt32(Modifiers.Static)
        }
        if t == TokenType.Internal {
            return System.Convert.ToInt32(Modifiers.Internal)
        }
        if t == TokenType.Protected {
            return System.Convert.ToInt32(Modifiers.Protected)
        }
        if t == TokenType.Virtual {
            return System.Convert.ToInt32(Modifiers.Virtual)
        }
        if t == TokenType.Override {
            return System.Convert.ToInt32(Modifiers.Override)
        }
        if t == TokenType.Abstract {
            return System.Convert.ToInt32(Modifiers.Abstract)
        }
        if t == TokenType.Sealed {
            return System.Convert.ToInt32(Modifiers.Sealed)
        }
        if t == TokenType.Partial {
            return System.Convert.ToInt32(Modifiers.Partial)
        }
        if t == TokenType.Async {
            return System.Convert.ToInt32(Modifiers.Async)
        }
        if t == TokenType.File {
            return System.Convert.ToInt32(Modifiers.File)
        }
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

    // Stage N+1c tranche 10b: the top-level `func` declaration now routes through the SAME full
    // ParseFunctionDeclaration reproduction the MEMBER path uses (Parser.cs :217 and :1475 both call
    // ParseFunctionDeclaration), replacing the Stage-3 reduced "literal-reaching vehicle". That retires
    // three recorded divergences from Parser.cs at once: the `<error>`-name early return (Parser.cs keeps
    // parsing the head + body), the missing `-> T` / missing-return-type-marker arms, and the shallow
    // ParseLiteralBearing* expression body (now the real ParseExprValue, which still runs the identical
    // malformed-literal checks inside ParsePrimaryExprValue).
    func ParseFunctionName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        functionNode := ParseMethodMember(modifiers, attributes, attrsOk)
        if functionNode != null {
            AddDeclaration(functionNode)
        }
    }

    func ReportMalformedStringLiteralIfNeeded(token: Token) {
        if token.Type == TokenType.TripleQuoteStringLiteral {
            ReportMalformedRawStringLiteralIfNeeded(token, "Unterminated triple-quoted string literal", "This triple-quoted string starts with `\"\"\"` but reaches the end of the file before the closing triple quote.", "Add the closing triple quote `\"\"\"` before the end of the file.", 3)
            return
        }

        if token.Type == TokenType.InterpolatedRawStringLiteral {
            ReportMalformedRawStringLiteralIfNeeded(token, "Unterminated interpolated raw string literal", "This interpolated raw string starts with `$\"\"\"` but reaches the end of the file before the closing triple quote.", "Add the closing triple quote `\"\"\"` before the end of the file.", 4)
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

        Report(ErrorCode.InvalidLiteral, message, token.Line, token.Column, explanation, "Add the closing quote on this line, or use a triple-quoted string for multi-line text.", suggestions, MaxInt(1, token.Value.Length))
    }

    func ReportMalformedRawStringLiteralIfNeeded(token: Token, message: string, humanExplanation: string, hint: string, markerLength: int) {
        if token.IsTerminated {
            return
        }

        suggestions := new List<string>()
        suggestions.Add("Add the closing triple quote")
        suggestions.Add("Check where the raw string should end")

        Report(ErrorCode.InvalidLiteral, message, token.Line, token.Column, humanExplanation, hint, suggestions, markerLength)
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

        Report(ErrorCode.InvalidLiteral, message, token.Line, token.Column, explanation, "Write a single character like `'a'`, or use a string literal like \"a\" when you need text.", suggestions, MaxInt(1, token.Value.Length))
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

    // Stage N+1c tranche 10b: the FULL Parser.cs ParseParameterList (:762) — the previously-deferred
    // params/ref/out MODIFIER prefix (:784-798), the `this` extension marker (:801), the
    // scoped/lifetime annotation (:813), the DEFAULT value (:816), and the
    // IsParameterListRecoveryBoundary early break (:778) are all modelled now, so every parameter shape
    // in the corpus both PARSES and MATERIALIZES byte-exact (`new Parameter(paramName, paramType,
    // defaultValue, isThis, modifier, attributes.Count > 0 ? attributes : null, paramLine, paramColumn,
    // isScoped, lifetime)`, :822). `ParamListMaterializable` is cleared only when the list is not
    // byte-exactly representable (an `<error>` name, an unmaterializable type or default value, or the
    // trailing-comma / boundary recovery), so the caller declines the whole declaration rather than
    // comparing a partial list.
    func ParseParameterListRecovery(): List<Parameter> {
        ParamListMaterializable = true
        paramNodes := new List<Parameter>()
        // Stage N+1c tranche 11: Parser.cs OPENS with `Consume(TokenType.LeftParen, "Expected '('")` (:763)
        // and then runs the whole do-loop regardless — an ABSENT `(` reports and still reaches the parameter
        // grammar (`func 5` builds an `<error>`-named parameter with an `<error>` type). The former early
        // return skipped both the report and the parameter, so it is retired.
        ConsumeToken(TokenType.LeftParen, "Expected '('", "(")

        if !Check(TokenType.RightParen) {
            // The start token of the last SUCCESSFULLY-parsed parameter, for the trailing-comma span
            // (Parser.cs `lastParameterStartToken`, :766/:826).
            lastParameterStartToken: Token? = null
            parsing := true
            while parsing {
                // Trailing comma before ')' (Parser.cs :772): `f(a,)` reports "Expected parameter name"
                // spanning the last parameter through the comma, then stops.
                if Check(TokenType.RightParen) && Previous().Type == TokenType.Comma && lastParameterStartToken != null {
                    startToken := lastParameterStartToken ?? Current()
                    ReportMissingParameterAfterTrailingComma(DiagnosticSpanFromTokenRange(startToken, Previous()))
                    // Stage N+1c tranche 11: Parser.cs BREAKS here (:775) and returns the parameters
                    // accumulated so far — a partial list, not a decline.
                    parsing = false
                } else {
                    // Parser.cs anchors this on `Previous` (:778) — the token BEFORE the cursor at each
                    // iteration (the `(` on the first pass, the `,` on every later one), NOT the list's
                    // opening token, so a same-line continuation after a comma is never a boundary.
                    if IsParameterListRecoveryBoundary(Previous()) {
                        parsing = false
                    } else {
                        // Parser.cs :778 break — the partial list is the result

                        // Per-parameter attributes (Parser.cs :781), before the modifier/name.
                        paramAttrs := ParseAttributes()
                        attrsOk := AttributesMaterializable

                        // params / ref / out (Parser.cs :783-798) — mutually exclusive, first match wins.
                        modifier := ParameterModifier.None
                        if Check(TokenType.Params) {
                            modifier = ParameterModifier.Params
                            Advance()
                        } else {
                            if Check(TokenType.Ref) {
                                modifier = ParameterModifier.Ref
                                Advance()
                            } else {
                                if Check(TokenType.Out) {
                                    modifier = ParameterModifier.Out
                                    Advance()
                                }
                            }
                        }

                        // The `this` extension marker (Parser.cs :801).
                        isThis := false
                        if Check(TokenType.This) {
                            isThis = true
                            Advance()
                        }

                        paramStartToken := Current()
                        paramLine := Current().Line
                        paramColumn := Current().Column
                        paramName := ConsumeNameWithSpan("Expected parameter name", GetMissingParameterNameDiagnosticSpan())
                        ConsumeParameterColon(paramName, paramLine, paramColumn)
                        paramType := ParseParameterTypeReference(paramName, paramLine, paramColumn)

                        // The Systems scoped / lifetime annotation (Parser.cs ParseScopedLifetimeAnnotation
                        // :6xxx): `scoped` sets IsScoped; a `'a` lifetime sets BOTH IsScoped and Lifetime.
                        isScoped := false
                        lifetime: string? = null
                        if Check(TokenType.Scoped) {
                            isScoped = true
                            Advance()
                        }
                        if Check(TokenType.Lifetime) {
                            isScoped = true
                            lifetime = Advance().Value
                        }

                        // Default value (Parser.cs :816).
                        defaultValue: Expression? = null
                        hasDefault := false
                        if Check(TokenType.Assign) {
                            hasDefault = true
                            Advance()
                            defaultValue = ParseExprValue().Node
                        }

                        // Parser.cs :823 passes the attribute list only when NON-empty (else null).
                        parameterAttributes: List<AttributeNode>? = null
                        if paramAttrs.Count > 0 {
                            parameterAttributes = paramAttrs
                        }

                        // Stage N+1c tranche 11: an `<error>` parameter name and an `<error>` parameter TYPE
                        // are Parser.cs's own placeholders — it adds the Parameter unconditionally (:822).
                        if paramType != null && attrsOk && !(hasDefault && defaultValue == null) {
                            paramNodes.Add(new Parameter(paramName, paramType, defaultValue, isThis, modifier, parameterAttributes, paramLine, paramColumn, isScoped, lifetime))
                        } else {
                            ParamListMaterializable = false
                        }

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
        }

        // Parser.cs Consume(RightParen) (:830): a present ')' advances; a missing one routes through the
        // Stage-9 closing-delimiter recovery (NL107) or the standard ExpectedToken path.
        ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        return paramNodes
    }

    // Parser.cs IsParameterListRecoveryBoundary (:832): the parameter loop bails when the next token can
    // no longer belong to the list — EOF, a brace, an `=>` / `->` body marker, or a continuation boundary.
    func IsParameterListRecoveryBoundary(openingToken: Token): bool {
        if IsAtEnd() {
            return true
        }
        if Check(TokenType.LeftBrace) {
            return true
        }
        if Check(TokenType.RightBrace) {
            return true
        }
        if Check(TokenType.Arrow) {
            return true
        }
        if Check(TokenType.Minus) && LookAhead(1).Type == TokenType.Greater {
            return true
        }
        return IsContinuationRecoveryBoundary(openingToken)
    }

    // Parser.cs ReportMissingParameterAfterTrailingComma (:6487).
    func ReportMissingParameterAfterTrailingComma(span: RecoverySpan) {
        suggestions := new List<string>()
        suggestions.Add("Add a parameter after the comma")
        suggestions.Add("Remove the trailing comma")
        Report(ErrorCode.ExpectedToken, "Expected parameter name. Got '" + Current().Value + "'", span.Line, span.Column, "Parameter lists need another parameter after a comma.", "Add the missing parameter after the comma, or remove the trailing comma.", suggestions, span.Length)
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
            Report(ErrorCode.UnexpectedEndOfFile, message + ", but reached the end of the file", eofSpan.Line, eofSpan.Column, DotOrPlainEofExplanation(isDotAccess), DotOrPlainEofHint(isDotAccess), null, eofSpan.Length)
            return "<error>"
        }

        span := diagnosticSpan ?? SpanFromToken(Current())
        Report(ErrorCode.ExpectedToken, message + ". Got '" + Current().Value + "'", span.Line, span.Column, DotOrPlainFoundExplanation(isDotAccess, Current().Value), DotOrPlainFoundHint(isDotAccess), DotAccessFoundSuggestions(isDotAccess), span.Length)
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
        Report(ErrorCode.ExpectedToken, "Expected ':' after parameter name. Got '" + Current().Value + "'", parameterLine, parameterColumn, "Parameter '" + parameterName + "' needs a ':' before its type.", "Write this parameter as `" + parameterName + ": Type`.", SingleSuggestion("Add ':' after '" + parameterName + "'"), nameLength)
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
        Report(ErrorCode.ExpectedToken, "Expected type name. Got '" + Current().Value + "'", span.Line, span.Column, explanation, hint, SingleSuggestion("Add a parameter type after ':'"), span.Length)
        // Stage N+1c tranche 11 (ERROR-NODE MATERIALIZATION): Parser.cs substitutes a SYNTHETIC
        // `new SimpleTypeReference("<error>", span.Line, span.Column) { Span = SourceSpan.FromStartAndLength(
        // span.Line, span.Column, span.Length) }` here (:6541) — it does not decline.
        errorType := new SimpleTypeReference("<error>", span.Line, span.Column)
        errorType.Span = SourceSpan.FromStartAndLength(span.Line, span.Column, span.Length)
        return errorType
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
        // Every declaration is routed here AFTER its full extent (including any type/function body) has
        // been consumed, so Previous() is its last token — stamp EndLine for the formatter's
        // end-anchored blank-line gap measurement.
        node.EndLine = TokenEndLine(Previous())
        if TypeMemberStack.Count > 0 {
            TypeMemberStack[TypeMemberStack.Count - 1].Add(node)
        } else {
            DeclarationNodes.Add(node)
        }
    }

    // The line a DELIMITED LIST's closing delimiter sits on, stamped onto the list node.
    //
    // The formatter's wrapping rule is author-preserving: a list the author spread over more than one
    // source line is canonicalised to one element per line, and a list written on one line stays on one
    // line however long. "More than one source line" is a question about the two DELIMITERS — a list
    // whose `)` is below its `(` is wrapped even if every element fits on the opening line — so each
    // list node carries the closer's line as well as the opener's.
    //
    // `EndLine` is the field that already answers "what line does this node end on" (the declaration and
    // statement stamps above and in `ParseStatements`), and it DEFAULTS TO `Line`. That default is what
    // makes this safe to add: a node from a path that never stamps it, and every node in a hand-built
    // AST, reads as single-line — which is exactly the behaviour those trees have today.
    //
    // Call it IMMEDIATELY after the closer is consumed, so `Previous()` is the closer itself.
    func StampListEnd(node: Expression) {
        node.EndLine = Previous().Line
    }

    // THE LAST SOURCE LINE A TOKEN COVERS, WHICH IS NOT ALWAYS THE LINE IT STARTS ON.
    //
    // Almost every token is one line wide, so `Line` is its end as well — which is why the three
    // `EndLine` stamps below could read `Previous().Line` and be right. The exceptions are the two
    // RAW string literals: `"""…"""` and `$"""…"""` carry their own newlines INSIDE a single token,
    // so a statement or declaration that ends in one covers more lines than its last token reports.
    //
    // The formatter is the consumer that notices, because it measures blank-line gaps from
    // construct ENDS. An under-reported end makes the line after a multi-line literal look like it
    // stood across a gap, and a blank line the author never wrote is inserted above it — on every
    // format, for `$"""` as much as for `"""`. Counting the token's own line breaks is the whole
    // correction, and it is the identity on every single-line token.
    func TokenEndLine(token: Token): int {
        line := token.Line
        text := token.Value
        index := 0
        while index < text.Length {
            if text[index] == '\n' {
                line = line + 1
            }

            index = index + 1
        }

        return line
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
            PanicMode = false
            // reset at each member boundary (Parser.cs :1365)
            // Parser.cs resets ONLY panic here; the split-`>>` debt survives the member boundary and
            // is cleared exclusively by SynchronizeToNextDeclaration/Statement (:7044/:7088).
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
                    Report(ErrorCode.MissingClosingBrace, "Missing closing '}'", span.Line, span.Column, "The type body that started on line " + IntToString(span.Line) + " is missing its closing brace. I reached the end of the file without finding it.", "Add a '}' to close this type declaration.", null, span.Length)
                }
            }
        }
    }

    // Parser.cs ParseMemberDeclaration (:1412) FIELD/PROPERTY fall-through (:1481) → ParseFieldDeclaration
    // (:1637). Field name errors funnel through the shared no-span ConsumeIdentifier Parser.cs uses at
    // :1666 (a field name is never a dot-access, so its plain message variants apply). Stage 14 carries the
    // property forms: the leading required/init/readonly modifiers, the expression-bodied `=> expr` property,
    // and the `{ get/set }` accessor block (with its "Expected 'get' or 'set'" reports).
    // Stage N+1c tranche 10b: the field / property member now threads the member's MODIFIERS +
    // ATTRIBUTES and materializes all three shapes Parser.cs builds — the inferred/typed
    // `new FieldDeclaration(name, type, initializer, modifiers, propertyModifier, attributes, line, column)`
    // (Parser.cs :1686/:1782), the expression-bodied
    // `new PropertyDeclaration(name, type, null, null, expressionBody, …)` (:1698), and the accessor-block
    // `new PropertyDeclaration(name, type, getBody, setBody, null, …)` (:1768). The required/init/readonly
    // property modifiers accumulate into BOTH the PropertyModifier value and the Modifiers value
    // (Parser.cs :1659-1673 sets both).
    func ParseFieldMember(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        line := Current().Line
        column := Current().Column
        declined := !attrsOk

        // Property modifiers required/init/readonly (Parser.cs :1655) — combinable, no diagnostic.
        propertyModifierValue := 0
        effectiveModifiers := modifiers
        scanningPropModifiers := true
        while scanningPropModifiers {
            if Check(TokenType.Required) {
                propertyModifierValue = propertyModifierValue | 1
                // PropertyModifier.Required
                effectiveModifiers = AddModifierFlag(effectiveModifiers, 8192)
                // Modifiers.Required
                Advance()
            } else {
                if Check(TokenType.Init) {
                    propertyModifierValue = propertyModifierValue | 2
                    // PropertyModifier.Init
                    effectiveModifiers = AddModifierFlag(effectiveModifiers, 16384)
                    // Modifiers.Init
                    Advance()
                } else {
                    if Check(TokenType.Readonly) {
                        propertyModifierValue = propertyModifierValue | 4
                        // PropertyModifier.Readonly
                        effectiveModifiers = AddModifierFlag(effectiveModifiers, 512)
                        // Modifiers.Readonly
                        Advance()
                    } else {
                        scanningPropModifiers = false
                    }
                }
            }
        }
        propertyModifier := (PropertyModifier)propertyModifierValue

        // Stage N+1c tranche 11: an `<error>` field name is Parser.cs's OWN placeholder (ConsumeIdentifier
        // :6819) and it still builds the FieldDeclaration around it (:1782) — no decline.
        name := ConsumeIdentifier("Expected field name")

        // Type inference `Name := value` (Parser.cs :1681) — a NULL type + the inferred initializer
        // (:1686). FQN'd (a test-helper `class FieldDeclaration` collides under the tests build).
        if Check(TokenType.ColonAssign) {
            Advance()
            inferInit := ParseExprValue().Node
            if !declined && inferInit != null {
                AddDeclaration(new NSharpLang.Compiler.Ast.FieldDeclaration(name, null, inferInit, effectiveModifiers, propertyModifier, attributes, line, column))
            }
            return
        }

        fieldColonToken := ConsumeFieldColon(name, line, column)
        fieldType := ParseFieldTypeReference(name, line, column, fieldColonToken)
        if fieldType == null {
            declined = true
        }

        // Expression-bodied property `name: type => expr` (Parser.cs :1694).
        if Check(TokenType.Arrow) {
            Advance()
            propertyExpressionBody := ParseExprValue().Node
            if !declined && fieldType != null && propertyExpressionBody != null {
                AddDeclaration(new PropertyDeclaration(name, fieldType, null, null, propertyExpressionBody, effectiveModifiers, propertyModifier, attributes, line, column))
            }
            return
        }

        // Property with `{ get/set }` accessors (Parser.cs :1702).
        if Check(TokenType.LeftBrace) {
            Advance()
            // consume '{'
            getBody: BlockStatement? = null
            setBody: BlockStatement? = null
            while !Check(TokenType.RightBrace) && !IsAtEnd() {
                if Check(TokenType.Identifier) {
                    accessorLine := Current().Line
                    accessorColumn := Current().Column
                    accessor := Current().Value
                    Advance()
                    accessorSpan := new RecoverySpan(accessorLine, accessorColumn, MaxInt(1, accessor.Length))
                    if accessor == "get" {
                        getBody = ParseBlock(accessorSpan)
                        if getBody == null {
                            declined = true
                        }
                    } else {
                        if accessor == "set" {
                            setBody = ParseBlock(accessorSpan)
                            if setBody == null {
                                declined = true
                            }
                        } else {
                            // Stage N+1c tranche 11: Parser.cs REPORTS and skips, then still builds the
                            // PropertyDeclaration with whatever accessors it collected (:1768) — no decline.
                            ReportPropertyAccessorInvalidIdentifier(accessor)
                            // Skip to the next accessor or the closing brace (Parser.cs :1743).
                            while !Check(TokenType.RightBrace) && !Check(TokenType.Identifier) && !IsAtEnd() {
                                Advance()
                            }
                        }
                    }
                } else {
                    ReportPropertyAccessorExpectedGetSet()
                    Advance()
                }
            }
            // skip the invalid token (Parser.cs :1763)

            ConsumeToken(TokenType.RightBrace, "Expected '}' after property accessors", "}")
            if !declined && fieldType != null {
                AddDeclaration(new PropertyDeclaration(name, fieldType, getBody, setBody, null, effectiveModifiers, propertyModifier, attributes, line, column))
            }
            return
        }

        // Field `= initializer` (Parser.cs :1773). A missing operand (synthetic error node) or a
        // still-deferred expression form leaves initNode null -> decline (no-stub).
        if Check(TokenType.Assign) {
            initializerToken := Advance()
            initNode := ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This field declaration", null)
            if !declined && fieldType != null && initNode != null {
                AddDeclaration(new NSharpLang.Compiler.Ast.FieldDeclaration(name, fieldType, initNode, effectiveModifiers, propertyModifier, attributes, line, column))
            }
            return
        }

        // The initializer-free `name: <type>` field (Parser.cs :1782). Line/Column anchor the field-name
        // start (Parser.cs :1650-1651 capture Current before the name). AddDeclaration routes the field
        // into the enclosing type's Members.
        if !declined && fieldType != null {
            AddDeclaration(new NSharpLang.Compiler.Ast.FieldDeclaration(name, fieldType, null, effectiveModifiers, propertyModifier, attributes, line, column))
        }
    }

    // Parser.cs ParseFieldDeclaration accessor error (:1718): an identifier that is neither 'get' nor
    // 'set'. Anchored on the CURRENT token (Parser.cs advances past the bad accessor first) but sized to
    // the bad accessor's length.
    func ReportPropertyAccessorInvalidIdentifier(accessor: string) {
        suggestions := new List<string>()
        suggestions.Add("Example: get { return _value; }")
        suggestions.Add("Example: set { _value = value; }")
        Report(ErrorCode.ExpectedToken, "Expected 'get' or 'set' accessor, got '" + accessor + "'", Current().Line, Current().Column, "Property accessors must be either 'get' (for reading) or 'set' (for writing).", "Use 'get' to define how to retrieve the property value, or 'set' to define how to assign a new value.", suggestions, accessor.Length)
    }

    // Parser.cs ParseFieldDeclaration accessor error (:1738): a non-identifier where an accessor is
    // required. Anchored on and sized to the offending token.
    func ReportPropertyAccessorExpectedGetSet() {
        suggestions := new List<string>()
        suggestions.Add("Add a 'get' accessor to make the property readable")
        suggestions.Add("Add a 'set' accessor to make the property writable")
        suggestions.Add("Example: { get { return _value; } set { _value = value; } }")
        Report(ErrorCode.ExpectedToken, "Expected 'get' or 'set' accessor. Got '" + Current().Value + "'", Current().Line, Current().Column, "Inside property declaration braces, I need to see either 'get' or 'set' accessors.", "Properties define how to get and/or set their values using accessor blocks.", suggestions, Current().Value.Length)
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
        // Preprocessor directive member (Parser.cs :1415). Stage N+1c tranche 10b materializes the same
        // `new PreprocessorDeclaration(directive, line, column)` node the top-level dispatch builds.
        if Check(TokenType.PreprocessorDirective) {
            memberDirectiveLine := Current().Line
            memberDirectiveColumn := Current().Column
            memberDirectiveText := Current().Value
            Advance()
            AddDeclaration(new PreprocessorDeclaration(memberDirectiveText, memberDirectiveLine, memberDirectiveColumn))
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
            ParseStructName(modifiers, attributes, attrsOk, true)
            return
        }
        if Check(TokenType.Struct) {
            ParseStructName(modifiers, attributes, attrsOk, false)
            return
        }
        if IsSoaRecordDeclarationStart() {
            ParseSoaRecordName(modifiers, attributes, attrsOk)
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
            ParseUnionName(modifiers, attributes, attrsOk)
            return
        }
        if Check(TokenType.Interface) {
            ParseInterfaceName(modifiers, attributes, attrsOk)
            return
        }

        // Constructor (Parser.cs :1463): the contextual `constructor` identifier.
        if Check(TokenType.Identifier) && Current().Value == "constructor" {
            ParseConstructorMember(modifiers, attributes, attrsOk)
            return
        }

        // Indexer (Parser.cs :1469): `func this[...]`, checked before the general method.
        if Check(TokenType.Func) && LookAhead(1).Type == TokenType.This {
            ParseIndexerMember(modifiers, attributes, attrsOk)
            return
        }

        // Method / conversion operator (Parser.cs :1475).
        if Check(TokenType.Func) || Check(TokenType.Implicit) || Check(TokenType.Explicit) {
            methodNode := ParseMethodMember(modifiers, attributes, attrsOk)
            if methodNode != null {
                AddDeclaration(methodNode)
            }
            return
        }

        // Field / property (Parser.cs :1481).
        ParseFieldMember(modifiers, attributes, attrsOk)
    }

    // Parser.cs ParseConstructorDeclaration (:1484): `constructor(params) [: this(args) | : base(args)] { body }`.
    // The `constructor` keyword is a contextual identifier; the initializer target must be `this` or `base`,
    // else the ExpectedToken report fires and the offending token is skipped.
    // Stage N+1c tranche 10b: `new ConstructorDeclaration(parameters, body, initializer, modifiers,
    // attributes, line, column)` (Parser.cs :1572). The initializer is a `new CallExpression(new
    // ThisExpression(…) / new BaseExpression(…), arguments, null, line, column)` (:1518/:1536) anchored on
    // the `this` / `base` token; the invalid-target arm builds a SYNTHETIC empty this() call (:1559) and
    // therefore declines no-stub.
    func ParseConstructorMember(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        line := Current().Line
        column := Current().Column
        Advance()
        // consume the 'constructor' identifier (Parser.cs :1488)
        parameters := ParseParameterListRecovery()
        declined := !attrsOk || !ParamListMaterializable

        // Optional initializer `: this(args)` / `: base(args)` (Parser.cs :1493).
        initializer: Expression? = null
        if Check(TokenType.Colon) {
            Advance()
            // Match(Colon) — advances past ':'
            if Check(TokenType.This) {
                thisLine := Current().Line
                thisColumn := Current().Column
                Advance()
                ConsumeToken(TokenType.LeftParen, "Expected '(' after 'this'", "(")
                thisArguments := ParseArgumentList()
                if thisArguments == null {
                    declined = true
                } else {
                    initializer = new CallExpression(new ThisExpression(thisLine, thisColumn), thisArguments, NoTypeArguments(), thisLine, thisColumn)
                }
            } else {
                if Check(TokenType.Base) {
                    baseLine := Current().Line
                    baseColumn := Current().Column
                    Advance()
                    ConsumeToken(TokenType.LeftParen, "Expected '(' after 'base'", "(")
                    baseArguments := ParseArgumentList()
                    if baseArguments == null {
                        declined = true
                    } else {
                        initializer = new CallExpression(new BaseExpression(baseLine, baseColumn), baseArguments, NoTypeArguments(), baseLine, baseColumn)
                    }
                } else {
                    ReportConstructorInitializerTarget()
                    // Stage N+1c tranche 11: Parser.cs builds a SYNTHETIC empty `this()` call anchored on the
                    // offending token (:1559-1565) — read BEFORE the skip Advance.
                    errorInitLine := Current().Line
                    errorInitColumn := Current().Column
                    initializer = new CallExpression(new ThisExpression(errorInitLine, errorInitColumn), new List<Argument>(), NoTypeArguments(), errorInitLine, errorInitColumn)
                    if !IsAtEnd() {
                        Advance()
                    }
                }
            }
        }
        // skip the invalid token (Parser.cs :1566)

        // Body (Parser.cs :1559): ParseBlock consumes the '{' first, owner span on the 'constructor' keyword
        // (length 11).
        body := ParseBlock(new RecoverySpan(line, column, MaxInt(1, 11)))
        if declined || body == null {
            return
        }
        AddDeclaration(new ConstructorDeclaration(parameters, body, initializer, modifiers, attributes, line, column))
    }

    // Parser.cs ParseConstructorDeclaration's initializer-target error (:1534).
    func ReportConstructorInitializerTarget() {
        suggestions := new List<string>()
        suggestions.Add("Use 'this' to call another constructor in the same class")
        suggestions.Add("Use 'base' to call a parent class constructor")
        Report(ErrorCode.ExpectedToken, "Expected 'this' or 'base' after ':'. Got '" + Current().Value + "'", Current().Line, Current().Column, "In constructor initialization, the colon ':' must be followed by either 'this' (to call another constructor) or 'base' (to call parent constructor).", "Constructor chaining syntax: 'constructor(params) : this(args) { }' or 'constructor(params) : base(args) { }'", suggestions, Current().Value.Length)
    }

    // Parser.cs ParseIndexerDeclaration (:1564): `func this[params]: retType { get/set }`.
    // Stage N+1c tranche 10b: `new IndexerDeclaration(parameters, returnType, getBody, setBody, modifiers,
    // attributes, line, column)` (Parser.cs :1642), over `new Parameter(paramName, paramType, null, false,
    // Line: paramLine, Column: paramColumn)` (:1594).
    func ParseIndexerMember(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        line := Current().Line
        column := Current().Column
        ConsumeToken(TokenType.Func, "Expected 'func'", "func")
        ConsumeToken(TokenType.This, "Expected 'this'", "this")
        ConsumeToken(TokenType.LeftBracket, "Expected '['", "[")
        declined := !attrsOk
        parameters := new List<Parameter>()

        // Indexer parameter list (Parser.cs :1574): `name: Type` entries, comma-separated.
        if !Check(TokenType.RightBracket) {
            parsing := true
            while parsing {
                paramLine := Current().Line
                paramColumn := Current().Column
                paramName := ConsumeIdentifier("Expected parameter name")
                ConsumeParameterColon(paramName, paramLine, paramColumn)
                paramType := ParseParameterTypeReference(paramName, paramLine, paramColumn)
                // Stage N+1c tranche 11: an `<error>` parameter name is Parser.cs's own placeholder.
                if paramType == null {
                    declined = true
                } else {
                    parameters.Add(new Parameter(paramName, paramType, null, false, ParameterModifier.None, null, paramLine, paramColumn, false, null))
                }
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    parsing = false
                }
            }
        }

        ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
        ConsumeToken(TokenType.Colon, "Expected ':'", ":")
        returnType := ParseMaterializedTypeReference()
        if returnType == null {
            declined = true
        }
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")

        // Accessor list (Parser.cs :1596): `get`/`set` blocks, else the "Expected 'get' or 'set' accessor"
        // report + skip.
        getBody: BlockStatement? = null
        setBody: BlockStatement? = null
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            accessorLine := Current().Line
            accessorColumn := Current().Column
            accessor := ConsumeIdentifier("Expected 'get' or 'set'")
            accessorSpan := new RecoverySpan(accessorLine, accessorColumn, MaxInt(1, accessor.Length))
            if accessor == "get" {
                getBody = ParseBlock(accessorSpan)
                if getBody == null {
                    declined = true
                }
            } else {
                if accessor == "set" {
                    setBody = ParseBlock(accessorSpan)
                    if setBody == null {
                        declined = true
                    }
                } else {
                    // Stage N+1c tranche 11: Parser.cs reports, skips, and still builds the
                    // IndexerDeclaration with the accessors it collected (:1642).
                    ReportIndexerAccessorInvalid(accessor)
                    while !Check(TokenType.RightBrace) && !Check(TokenType.Identifier) && !IsAtEnd() {
                        Advance()
                    }
                }
            }
        }

        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
        if declined || returnType == null {
            return
        }
        AddDeclaration(new IndexerDeclaration(parameters, returnType, getBody, setBody, modifiers, attributes, line, column))
    }

    // Parser.cs ParseIndexerDeclaration's accessor error (:1613).
    func ReportIndexerAccessorInvalid(accessor: string) {
        suggestions := new List<string>()
        suggestions.Add("Example: get { return items[i]; }")
        suggestions.Add("Example: set { items[i] = value; }")
        Report(ErrorCode.ExpectedToken, "Expected 'get' or 'set' accessor, got '" + accessor + "'", Current().Line, Current().Column, "Indexer accessors must be either 'get' (for reading) or 'set' (for writing).", "Use 'get' to define how to retrieve a value, or 'set' to define how to assign a value.", suggestions, accessor.Length)
    }

    // Parser.cs ParseFunctionDeclaration (:373) reached as a MEMBER method: the func / func* generator /
    // func operator / implicit-explicit conversion forms, the keyword-anchored name (ConsumeDeclarationName,
    // DiagnosticSpanFromToken(funcToken), :435), the type parameters, the parameter list, the `: T` / `-> T`
    // return type (or the missing-return-type-marker report), the returns-lifetime annotation, the generic
    // constraints, and the `=> expr` / `{ }` body. Unlike a LOCAL function, a method with NO body is valid
    // (an abstract / interface method), so there is no missing-body report.
    // Stage N+1c tranche 10b (the member-BODY consumers): RETURNS the byte-exact
    // `new FunctionDeclaration(name, parameters, returnType, body, expressionBody, typeParams, constraints,
    // modifiers, attributes, isOperatorOverload, operatorSymbol, isConversionOperator, isImplicitConversion,
    // line, column) { OperatorKeywordSpan, OperatorSymbolSpan, ReturnLifetime }` (Parser.cs :503-508), or
    // null when any present sub-part declined. The SAME entry serves the top-level `func` declaration
    // (Parser.cs routes both through ParseFunctionDeclaration).
    func ParseMethodMember(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool): NSharpLang.Compiler.Ast.FunctionDeclaration? {
        line := Current().Line
        column := Current().Column

        isConversionOperator := false
        isImplicitConversion := false
        isOperatorOverload := false
        operatorSymbol: string? = null
        operatorKeywordSpan := SourceSpan.None
        operatorSymbolSpan := SourceSpan.None
        effectiveModifiers := modifiers
        name := "function"
        markerName := "function"
        markerLine := line
        markerColumn := column
        markerLength := MaxInt(1, Current().Value.Length)

        if Check(TokenType.Implicit) || Check(TokenType.Explicit) {
            // Conversion operator (Parser.cs :393): no 'func' keyword; the return type comes BEFORE params.
            isConversionOperator = true
            isImplicitConversion = Check(TokenType.Implicit)
            Advance()
            // consume 'implicit' / 'explicit'
            ConsumeToken(TokenType.Operator, "Expected 'operator' after 'implicit' or 'explicit'", "operator")
            name = "explicit operator"
            if isImplicitConversion {
                name = "implicit operator"
            }
        } else {
            funcToken := Current()
            Advance()
            // consume 'func' (Parser.cs :406)
            if Check(TokenType.Star) {
                Advance()
                // generator func* (Parser.cs :409)
                effectiveModifiers = AddModifierFlag(effectiveModifiers, 4096)
            }
            // Modifiers.Generator

            if Check(TokenType.Operator) {
                // Operator overload (Parser.cs :415): `func operator SYM`. The return-type marker anchors on
                // the `operator` keyword.
                isOperatorOverload = true
                operatorToken := Advance()
                // consume 'operator'
                operatorKeywordSpan = SpanFromTokensSingleLine(operatorToken, operatorToken)
                markerName = "operator overload"
                markerLine = operatorToken.Line
                markerColumn = operatorToken.Column
                markerLength = MaxInt(1, operatorToken.Value.Length)
                operatorSymbolToken := Current()
                operatorSymbol = ParseOperatorSymbol()
                operatorSymbolSpan = SpanFromTokensSingleLine(operatorSymbolToken, operatorSymbolToken)
                name = "operator " + (operatorSymbol ?? "")
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

        typeParameters := ParseTypeParameters()
        declined := !attrsOk

        // For conversion operators the return type is parsed BEFORE the parameter list (Parser.cs :452).
        returnType: TypeReference? = null
        if isConversionOperator {
            returnType = ParseMaterializedTypeReference()
            if returnType == null {
                declined = true
            }
        }

        parameters := ParseParameterListRecovery()
        if !ParamListMaterializable {
            declined = true
        }
        parameterListEndToken := Previous()

        // Return type after the params (Parser.cs :462): `: T` or `-> T`, else the missing-marker report.
        if !isConversionOperator {
            if Check(TokenType.Colon) || (Check(TokenType.Minus) && LookAhead(1).Type == TokenType.Greater) {
                if Check(TokenType.Colon) {
                    Advance()
                } else {
                    Advance()
                    // consume '-'
                    ConsumeToken(TokenType.Greater, "Expected '>' after '-' in return type arrow", "greater")
                }
                returnType = ParseMaterializedTypeReference()
                if returnType == null {
                    declined = true
                }
            } else {
                if IsLikelyMissingReturnTypeMarker(parameterListEndToken) {
                    ReportMissingReturnTypeMarker(markerName, markerLine, markerColumn, markerLength)
                    returnType = ParseMaterializedTypeReference()
                    if returnType == null {
                        declined = true
                    }
                }
            }
        }

        ParseReturnLifetimeAnnotation()
        returnLifetime := ReturnLifetimeValue
        constraints := ParseGenericConstraints()
        if !ConstraintsMaterializable {
            declined = true
        }

        // Body (Parser.cs :493): an expression body, a block body, or NOTHING (abstract / interface method).
        body: BlockStatement? = null
        expressionBody: Expression? = null
        if Check(TokenType.Arrow) {
            Advance()
            expressionBody = ParseExprValue().Node
            if expressionBody == null {
                declined = true
            }
        } else {
            if Check(TokenType.LeftBrace) {
                bodySpan := new RecoverySpan(markerLine, markerColumn, markerLength)
                body = ParseBlock(bodySpan)
                if body == null {
                    declined = true
                }
            }
        }

        if declined {
            return null
        }
        functionNode := new NSharpLang.Compiler.Ast.FunctionDeclaration(name, parameters, returnType, body, expressionBody, typeParameters, constraints, effectiveModifiers, attributes, isOperatorOverload, operatorSymbol, isConversionOperator, isImplicitConversion, line, column)
        functionNode.OperatorKeywordSpan = operatorKeywordSpan
        functionNode.OperatorSymbolSpan = operatorSymbolSpan
        functionNode.ReturnLifetime = returnLifetime
        return functionNode
    }

    // OR one Modifiers flag into an existing value through the int-bitmask idiom (enum bitwise operators
    // route through the C# fenced residual and are avoided in dogfood N#).
    func AddModifierFlag(current: Modifiers, flag: int): Modifiers {
        return (Modifiers)(System.Convert.ToInt32(current) | flag)
    }

    // Parser.cs ParseOperatorSymbol (:5752): maps the operator token to its symbol and advances, reporting
    // the InvalidSyntax "Invalid operator symbol" when the token cannot be an overloadable operator.
    // Stage N+1c tranche 10b: RETURNS the operator's raw symbol text (Parser.cs's switch maps each token to
    // its symbol string, which is exactly the token's own Value for every overloadable operator), or the
    // literal "+" fallback Parser.cs's switch default installs after reporting (:5854).
    func ParseOperatorSymbol(): string? {
        if IsOverloadableOperator(Current().Type) {
            return Advance().Value
        }
        token := Current()
        suggestions := new List<string>()
        suggestions.Add("Arithmetic: +, -, *, /, %")
        suggestions.Add("Comparison: ==, !=, <, >, <=, >=")
        suggestions.Add("Unary: !, ~, ++, --")
        suggestions.Add("Conversion: true, false")
        Report(ErrorCode.InvalidSyntax, "Invalid operator symbol '" + token.Value + "' for operator overloading", token.Line, token.Column, "This operator cannot be overloaded, or is not a valid operator symbol.", "Only certain operators can be overloaded in operator declarations.", suggestions, token.Value.Length)
        Advance()
        // Stage N+1c tranche 11: Parser.cs's switch DEFAULT falls back to the literal symbol "+" (:5854)
        // and still advances — it does not decline.
        return "+"
    }

    // Parser.cs ParseOperatorSymbol's overloadable-operator set (:5757-5843), lowered from the switch to a
    // token predicate; the symbol STRING is the token's own text for every admitted operator.
    func IsOverloadableOperator(t: TokenType): bool {
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
        if t == TokenType.Equal {
            return true
        }
        if t == TokenType.NotEqual {
            return true
        }
        if t == TokenType.Less {
            return true
        }
        if t == TokenType.LessEqual {
            return true
        }
        if t == TokenType.Greater {
            return true
        }
        if t == TokenType.GreaterEqual {
            return true
        }
        if t == TokenType.Not {
            return true
        }
        if t == TokenType.BitwiseNot {
            return true
        }
        if t == TokenType.BitwiseAnd {
            return true
        }
        if t == TokenType.BitwiseOr {
            return true
        }
        if t == TokenType.BitwiseXor {
            return true
        }
        if t == TokenType.LeftShift {
            return true
        }
        if t == TokenType.RightShift {
            return true
        }
        if t == TokenType.Increment {
            return true
        }
        if t == TokenType.Decrement {
            return true
        }
        if t == TokenType.True {
            return true
        }
        if t == TokenType.False {
            return true
        }
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
        Report(ErrorCode.ExpectedToken, "Expected ':' or ':=' after field name. Got '" + Current().Value + "'", fieldLine, fieldColumn, "Field '" + fieldName + "' needs a ':' before its type, or ':=' before an inferred initializer.", "Write this field as `" + fieldName + ": Type` or `" + fieldName + " := value`.", FieldColonSuggestions(fieldName), nameLength)
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
        Report(ErrorCode.ExpectedToken, "Expected type name. Got '" + Current().Value + "'", span.Line, span.Column, explanation, hint, SingleSuggestion("Add a field type after ':'"), span.Length)
        // Stage N+1c tranche 11 (ERROR-NODE MATERIALIZATION): Parser.cs substitutes a SYNTHETIC
        // `new SimpleTypeReference("<error>", span.Line, span.Column) { Span = SourceSpan.FromStartAndLength(
        // span.Line, span.Column, span.Length) }` here (:6577) — it does not decline.
        errorType := new SimpleTypeReference("<error>", span.Line, span.Column)
        errorType.Span = SourceSpan.FromStartAndLength(span.Line, span.Column, span.Length)
        return errorType
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
        nameToken := Current()
        // capture the name position BEFORE it is consumed (Parser.cs :937)
        name := ConsumeDeclarationName("Expected class name", SpanFromToken(classToken))
        // The type-body missing-'}' diagnostic (Stage 9) anchors on the name, or the declaration keyword
        // for a '<error>' name (Parser.cs :940-942, "class".Length == 5).
        typeBodyDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            typeBodyDiagnosticSpan = new RecoverySpan(classToken.Line, classToken.Column, MaxInt(1, 5))
        }
        // Type parameter list `<T>` (Stage 5, Parser.cs :943) — parsed after the name, before the body,
        // so a malformed `class C<> { }` reports ReportMissingTypeParameterName. N+1c tranche 6: the list is
        // MATERIALIZED (typeParams null when absent, else the byte-exact List<TypeParameter>); a malformed list
        typeParams := ParseTypeParameters()
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
        // N+1c tranche 6: materialize the base/interface list, then apply the CLASS dispatch (Parser.cs :977-978):
        // the FIRST type is the BaseClass, the rest are Interfaces. Captured into locals BEFORE ParseTypeBody.
        baseTypes := ParseBaseTypeList()
        baseListOk := BaseListMaterializable
        baseClass: TypeReference? = null
        interfaces := new List<TypeReference>()
        if baseTypes.Count > 0 {
            baseClass = baseTypes[0]
            baseIndex := 1
            while baseIndex < baseTypes.Count {
                interfaces.Add(baseTypes[baseIndex])
                baseIndex = baseIndex + 1
            }
        }
        members := ParseTypeBody(name, typeBodyDiagnosticSpan)
        // N+1c tranche 2/3/4/6: materialize the ClassDeclaration (Parser.cs :973). Line/Column anchor the class
        // keyword (Parser.cs :933-934). TypeParameters + BaseClass + Interfaces are the tranche-6 materialized
        // values (null / null / empty when absent, matching Parser.cs); Modifiers + Attributes the tranche-4
        // values; PrimaryConstructorParameters the captured Parameter list (or null when absent). Members is the
        // tranche-3 populated list. A malformed type-param or base list DECLINES materialization (no-stub).
        // FULLY QUALIFIED (`NSharpLang.Compiler.Ast.ClassDeclaration`): a test-helper `class ClassDeclaration` in
        // NSharpLang.Compiler collides under the tests-enabled build.
        canMaterialize := attrsOk && paramsOk && baseListOk
        if canMaterialize {
            if hasParams {
                AddDeclaration(new NSharpLang.Compiler.Ast.ClassDeclaration(name, typeParams, baseClass, interfaces, members, primaryParams, modifiers, attributes, classToken.Line, classToken.Column))
            } else {
                AddDeclaration(new NSharpLang.Compiler.Ast.ClassDeclaration(name, typeParams, baseClass, interfaces, members, null, modifiers, attributes, classToken.Line, classToken.Column))
            }
        }
    }

    func ParseStructName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool, isRefStruct: bool) {
        structToken := Current()
        Advance()
        nameToken := Current()
        // capture the name position BEFORE it is consumed (Parser.cs :982)
        name := ConsumeDeclarationName("Expected struct name", SpanFromToken(structToken))
        // Parser.cs :985-987 ("struct".Length == 6).
        typeBodyDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            typeBodyDiagnosticSpan = new RecoverySpan(structToken.Line, structToken.Column, MaxInt(1, 6))
        }
        typeParams := ParseTypeParameters()
        hasParams := Check(TokenType.LeftParen)
        primaryParams := new List<Parameter>()
        paramsOk := true
        if hasParams {
            primaryParams = ParseParameterListRecovery()
            // primary ctor params (Parser.cs :992)
            paramsOk = ParamListMaterializable
        }
        // N+1c tranche 6: a struct's `: T, U` is a pure INTERFACE list (Parser.cs :1008-1015 — no BaseClass
        // split); the whole materialized list is Interfaces. Captured BEFORE ParseTypeBody.
        interfaces := ParseBaseTypeList()
        // interface list (Parser.cs :998)
        baseListOk := BaseListMaterializable
        members := ParseTypeBody(name, typeBodyDiagnosticSpan)
        // N+1c tranche 1/3/4/6: materialize the StructDeclaration (Parser.cs :1010). Stage N+1c tranche 11
        // threads `isRefStruct` from the two `ref struct` dispatch arms (Parser.cs :221-225 top level / :1443-
        // :1447 nested), which consume the `ref` and pass `isRefStruct: true`. TypeParameters + Interfaces are the
        // tranche-6 materialized values; Modifiers/Attributes/PrimaryConstructorParameters the tranche-4
        // values. A malformed type-param or interface list DECLINES materialization (no-stub). Members is the
        // tranche-3 populated list.
        canMaterialize := attrsOk && paramsOk && baseListOk
        if canMaterialize {
            if hasParams {
                AddDeclaration(new StructDeclaration(name, typeParams, interfaces, members, primaryParams, modifiers, attributes, structToken.Line, structToken.Column, isRefStruct))
            } else {
                AddDeclaration(new StructDeclaration(name, typeParams, interfaces, members, null, modifiers, attributes, structToken.Line, structToken.Column, isRefStruct))
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
        nameToken := Current()
        // capture the name position BEFORE it is consumed (Parser.cs :1027)
        name := ConsumeDeclarationName("Expected record name", SpanFromToken(recordToken))
        // Parser.cs :1030-1032 ("record".Length == 6).
        typeBodyDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            typeBodyDiagnosticSpan = new RecoverySpan(recordToken.Line, recordToken.Column, MaxInt(1, 6))
        }
        typeParams := ParseTypeParameters()
        // Parser.cs :1033
        hasParams := Check(TokenType.LeftParen)
        primaryParams := new List<Parameter>()
        paramsOk := true
        if hasParams {
            primaryParams = ParseParameterListRecovery()
            // record positional (primary ctor) params (Parser.cs :1039)
            paramsOk = ParamListMaterializable
        }
        // N+1c tranche 6: a record's `: T, U` is a pure INTERFACE list (Parser.cs :1053-1061). Captured BEFORE
        // ParseTypeBody.
        interfaces := ParseBaseTypeList()
        // interface list (Parser.cs :1043)
        baseListOk := BaseListMaterializable
        members := ParseTypeBody(name, typeBodyDiagnosticSpan)
        // N+1c tranche 1/3/4/6: materialize the RecordDeclaration (Parser.cs :1055). IsStruct reflects the
        // consumed `record struct`. TypeParameters + Interfaces are the tranche-6 materialized values;
        // Modifiers/Attributes the tranche-4 values; PrimaryConstructorParameters the captured Parameter list
        // (or null when absent) — THE UNLOCK for the public-positional-record real-corpus files. A malformed
        // type-param or interface list DECLINES materialization (no-stub). Members is the tranche-3 populated
        // list.
        canMaterialize := attrsOk && paramsOk && baseListOk
        if canMaterialize {
            if hasParams {
                AddDeclaration(new RecordDeclaration(name, typeParams, interfaces, members, primaryParams, isStruct, modifiers, attributes, recordToken.Line, recordToken.Column))
            } else {
                AddDeclaration(new RecordDeclaration(name, typeParams, interfaces, members, null, isStruct, modifiers, attributes, recordToken.Line, recordToken.Column))
            }
        }
    }

    func ParseSoaRecordName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        soaLine := Current().Line
        soaColumn := Current().Column
        Advance()
        // contextual 'soa'
        recordToken := Current()
        // the 'record' keyword
        Advance()
        nameToken := Current()
        // capture the name position BEFORE it is consumed (Parser.cs :1065)
        name := ConsumeDeclarationName("Expected soa record name", SpanFromToken(recordToken))
        // Parser.cs :1068-1070 ("soa".Length == 3, anchored at the soa keyword for a '<error>' name).
        soaDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            soaDiagnosticSpan = new RecoverySpan(soaLine, soaColumn, MaxInt(1, 3))
        }
        // Generic soa records are not supported yet (Parser.cs :1072): report then consume the `<…>` list. This
        // is an ERROR shape — a generic soa DECLINES materialization (no-stub).
        if Check(TokenType.Less) {
            ReportSoaTypeParametersUnsupported()
            ParseTypeParameters()
        }
        columns := ParseSoaRecordBody(soaDiagnosticSpan, soaLine)
        bodyOk := TypeBodyMaterializable
        // N+1c tranche 6: materialize the SoaRecordDeclaration (Parser.cs :1136). Columns is the tranche-6
        // materialized SoaColumnDeclaration list (a column name error / a malformed or multi-line column type
        // clears TypeBodyMaterializable → decline). Modifiers/Attributes are the tranche-4 threaded values (an
        // argument-bearing attribute clears attrsOk → decline). A generic soa is the error shape → decline.
        // Stage N+1c tranche 11: Parser.cs's generic-soa arm REPORTS and then falls through to the same
        // `new SoaRecordDeclaration(...)` (:1136) — the diagnostic does not suppress the node.
        if attrsOk && bodyOk {
            AddDeclaration(new SoaRecordDeclaration(name, columns, modifiers, attributes, soaLine, soaColumn))
        }
    }

    func ParseInterfaceName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        interfaceLine := Current().Line
        interfaceColumn := Current().Column
        isDuck := false
        if Check(TokenType.Duck) {
            isDuck = true
            interfaceLine = Current().Line
            // Parser.cs anchors the '<error>' keyword span on 'duck' or 'interface'
            interfaceColumn = Current().Column
            Advance()
        }
        // contextual 'duck'

        interfaceToken := Current()
        // the 'interface' keyword
        if !isDuck {
            interfaceLine = interfaceToken.Line
            interfaceColumn = interfaceToken.Column
        }
        Advance()
        nameToken := Current()
        // capture the name position BEFORE it is consumed (Parser.cs :1141)
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
        typeParams := ParseTypeParameters()
        // Parser.cs :1147
        // N+1c tranche 6: an interface's `: T, U` is the BASE-INTERFACE list (Parser.cs :1160-1168). Captured
        // BEFORE ParseTypeBody.
        baseInterfaces := ParseBaseTypeList()
        // base interface list (Parser.cs :1150)
        baseListOk := BaseListMaterializable
        members := ParseTypeBody(name, typeBodyDiagnosticSpan)
        // N+1c tranche 1/3/4/6: materialize the InterfaceDeclaration (Parser.cs :1150-return). Line/Column = the
        // first-token position (`duck` if present, else `interface`). TypeParameters + BaseInterfaces are the
        // tranche-6 materialized values; Modifiers/Attributes the tranche-4 values. A malformed type-param or
        // base-interface list DECLINES materialization (no-stub). Members is the tranche-3 populated list.
        // Interfaces have no primary-ctor params.
        canMaterialize := attrsOk && baseListOk
        if canMaterialize {
            AddDeclaration(new InterfaceDeclaration(name, typeParams, baseInterfaces, members, modifiers, isDuck, attributes, interfaceLine, interfaceColumn))
        }
    }

    func ParseUnionName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        unionLine := Current().Line
        unionColumn := Current().Column
        unionToken := Current()
        Advance()
        nameToken := Current()
        // capture the name position BEFORE it is consumed (Parser.cs :1171)
        name := ConsumeDeclarationName("Expected union name", SpanFromToken(unionToken))
        // Parser.cs :1174-1176 ("union".Length == 5).
        unionDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            unionDiagnosticSpan = new RecoverySpan(unionLine, unionColumn, MaxInt(1, 5))
        }
        typeParams := ParseTypeParameters()
        // Parser.cs :1188
        cases := ParseUnionBody(unionDiagnosticSpan, unionLine)
        bodyOk := TypeBodyMaterializable
        // N+1c tranche 6: materialize the UnionDeclaration (Parser.cs :1247). TypeParameters is the tranche-6
        // materialized list; Cases the materialized union-case list (a case name error / a malformed or
        // multi-line payload type clears TypeBodyMaterializable → decline). Modifiers/Attributes the threaded
        // tranche-4 values (an argument-bearing attribute clears attrsOk → decline). AddDeclaration routes it to
        // an enclosing type's Members when nested, else the top level.
        if attrsOk && bodyOk {
            AddDeclaration(new UnionDeclaration(name, typeParams, cases, modifiers, attributes, unionLine, unionColumn))
        }
    }

    func ParseEnumName(modifiers: Modifiers, attributes: List<AttributeNode>, attrsOk: bool) {
        enumLine := Current().Line
        enumColumn := Current().Column
        enumToken := Current()
        Advance()
        nameToken := Current()
        // capture the name position BEFORE it is consumed (Parser.cs :1245)
        name := ConsumeDeclarationName("Expected enum name", SpanFromToken(enumToken))
        // Parser.cs :1248-1250 ("enum".Length == 4).
        enumDiagnosticSpan := new RecoverySpan(nameToken.Line, nameToken.Column, MaxInt(1, name.Length))
        if name == "<error>" {
            enumDiagnosticSpan = new RecoverySpan(enumLine, enumColumn, MaxInt(1, 4))
        }
        // Optional `: int|string` backing type (Parser.cs :1255). The default is Int; a `string` backing
        // type selects String (Parser.cs :1114/:1125).
        enumType := EnumType.Int
        hasExplicitType := false
        if Check(TokenType.Colon) {
            Advance()
            hasExplicitType = true
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
        members := ParseEnumBody(enumDiagnosticSpan, enumLine)
        bodyOk := TypeBodyMaterializable
        // Parser.cs :1304: with no explicit backing type, a first string-literal member value infers String.
        if !hasExplicitType && EnumBodyInferredString {
            enumType = EnumType.String
        }
        // N+1c tranche 1/3/4/6: materialize the EnumDeclaration (Parser.cs :1339). Members is now the tranche-6
        // materialized EnumMember list — VALUELESS members `{ A, B }` materialize byte-exact (Value null); a
        // VALUE-bearing member `A = 1` clears TypeBodyMaterializable (the Value is an Expression, a later
        // tranche) → the enum declines. Modifiers/Attributes are the tranche-4 threaded values (an
        // argument-bearing attribute clears attrsOk → decline). The `: int|string` backing type is the EnumType
        // (handled above), not a base list — no base-list gate. AddDeclaration routes it to an enclosing type's
        // Members when the enum is nested, else the top level.
        if attrsOk && bodyOk {
            AddDeclaration(new EnumDeclaration(name, members, enumType, modifiers, attributes, enumLine, enumColumn))
        }
    }

    // Parser.cs ParseSoaRecordDeclaration's generic-soa report (:1074).
    func ReportSoaTypeParametersUnsupported() {
        Report(ErrorCode.InvalidSyntax, "soa record type parameters are not supported yet", Current().Line, Current().Column, "This parser slice only accepts non-generic soa records. Generic soa tables need an explicit ABI design before they can be accepted.", "Remove the type parameter list for now.", null, MaxInt(1, Current().Value.Length))
    }

    // Parser.cs ParseEnumDeclaration's unsupported-backing-type report (:1268). ReportError omits the
    // length there, so the default 0 flows through (both paths route through the same Create).
    func ReportEnumBackingTypeUnsupported(typeName: string, typeTokenLine: int, typeTokenColumn: int) {
        Report(ErrorCode.UnexpectedToken, "Unsupported enum backing type '" + typeName + "'. Only 'int' and 'string' are supported.", typeTokenLine, typeTokenColumn, null, null, null, 0)
    }

    // Parser.cs class/struct/record/interface base-type list (:955/:998/:1043/:1150): `: T` then a
    // comma-separated tail. The class form uses `ParseTypeReference()` + `while Match(Comma)`, the others a
    // `do { … } while (Match(Comma))`; both parse the same at-least-one comma-separated list.
    // Stage N+1c tranche 6: RETURNS the byte-exact `List<TypeReference>` of base/interface types Parser.cs
    // builds (the ordered `: T, U, …` list — Parser.cs :969/:1014/:1059/:1166) as a PURE side-effect through
    // the shared ParseMaterializedTypeReference gate, so each base type is the full stage-15 grammar
    // (simple / qualified / generic / …), byte-exact to Parser.cs. `BaseListMaterializable` is cleared when a
    // base type is structurally unbuildable or multi-line (the gate returns null), so the caller declines. The
    // class-vs-others DISPATCH (a single colon-entry becomes BaseClass on a class, an Interface elsewhere —
    // the NL010-era finding) is done by the CALLER: the class site splits [0]→BaseClass, [1..]→Interfaces;
    // struct/record/interface take the whole list as their interface list.
    func ParseBaseTypeList(): List<TypeReference> {
        BaseListMaterializable = true
        types := new List<TypeReference>()
        if !Check(TokenType.Colon) {
            return types
        }
        Advance()
        // consume ':'
        first := ParseMaterializedTypeReference()
        if first == null {
            BaseListMaterializable = false
        } else {
            types.Add(first)
        }
        while Check(TokenType.Comma) {
            Advance()
            next := ParseMaterializedTypeReference()
            if next == null {
                BaseListMaterializable = false
            } else {
                types.Add(next)
            }
        }
        return types
    }

    // Parser.cs ParseUnionDeclaration body (:1179): the union-case loop. Each case is a bare name with an
    // optional `{ prop: type, … }` payload; the loop resets panic after EnsureProgress and reports the
    // union-specific missing-'}' (NL106) on the union diagnostic span. Assumes the '{' is next.
    // Stage N+1c tranche 6: RETURNS the byte-exact `List<UnionCase>` Parser.cs :1223 builds — each case
    // `new UnionCase(caseName, properties, caseLine, caseColumn)` with the payload `new UnionCaseProperty(
    // propName, propType)` (Parser.cs :1212, propType through ParseMaterializedTypeReference). A PURE
    // side-effect; the Advance/Report/Consume sequence is unchanged. `TypeBodyMaterializable` clears on an
    // `<error>` case/property name or a structurally-unbuildable / multi-line payload type → the union
    // declines. The no-payload case inlines a `null` Properties (the recorded nullable-list-local workaround).
    func ParseUnionBody(unionDiagnosticSpan: RecoverySpan, openingLine: int): List<UnionCase> {
        TypeBodyMaterializable = true
        cases := new List<UnionCase>()
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            caseLine := Current().Line
            // Parser.cs :1196 (captured BEFORE the name)
            caseColumn := Current().Column
            // Stage N+1c tranche 11: an `<error>` case/property name is Parser.cs's own placeholder and it
            // still builds the UnionCase / UnionCaseProperty around it.
            caseName := ConsumeIdentifier("Expected union case name")
            // Parser.cs :1187
            if Check(TokenType.LeftBrace) {
                Advance()
                // consume the payload '{'
                props := new List<UnionCaseProperty>()
                while !Check(TokenType.RightBrace) && !IsAtEnd() {
                    propStart := Position
                    propName := ConsumeIdentifier("Expected property name")
                    // Parser.cs :1198
                    ConsumeToken(TokenType.Colon, "Expected ':'", ":")
                    propType := ParseMaterializedTypeReference()
                    if propType == null {
                        TypeBodyMaterializable = false
                    } else {
                        props.Add(new UnionCaseProperty(propName, propType))
                    }
                    // Parser.cs :1212

                    if !Check(TokenType.RightBrace) {
                        if Check(TokenType.Comma) {
                            Advance()
                        }
                    }
                    EnsureProgress(propStart)
                }
                ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
                cases.Add(new UnionCase(caseName, props, caseLine, caseColumn))
            } else {
                cases.Add(new UnionCase(caseName, null, caseLine, caseColumn))
            }
            if EnsureProgress(startPosition) {
                PanicMode = false
            }
        }
        // reset for the next case (Parser.cs :1216)

        if Check(TokenType.RightBrace) {
            Advance()
        } else {
            if IsAtEnd() {
                ReportTypeBodyMissingClosingBrace(unionDiagnosticSpan, openingLine, "union")
            }
        }
        return cases
    }

    // Parser.cs ParseEnumDeclaration body (:1274): the enum-member loop. Each member is a name with an
    // optional `= value` initializer; a member without a trailing comma ends the list. Reports the
    // enum-specific missing-'}' (NL106) on the enum diagnostic span. Assumes the '{' is next.
    // Stage N+1c tranche 6: RETURNS the byte-exact `List<EnumMember>` Parser.cs :1310 builds — each member
    // `new EnumMember(memberName, value, memberLine, memberColumn)`. A VALUELESS member materializes with a
    // null Value byte-exact; a VALUE-bearing member `A = 1` clears `TypeBodyMaterializable` (the Value is an
    // Expression, a later tranche) so the enum declines. A PURE side-effect; the Advance/Report sequence is
    // unchanged (ParseExprValue still consumes the value for the diagnostic stream).
    func ParseEnumBody(enumDiagnosticSpan: RecoverySpan, openingLine: int): List<EnumMember> {
        TypeBodyMaterializable = true
        EnumBodyInferredString = false
        members := new List<EnumMember>()
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        if !Check(TokenType.RightBrace) {
            looping := true
            while looping && !Check(TokenType.RightBrace) && !IsAtEnd() {
                startPosition := Position
                memberLine := Current().Line
                // Parser.cs :1293 (captured BEFORE the name)
                memberColumn := Current().Column
                // Stage N+1c tranche 11: an `<error>` member name is Parser.cs's own placeholder and it
                // still builds the EnumMember around it.
                memberName := ConsumeIdentifier("Expected enum member name")
                // Parser.cs :1284
                // Tranche 7: a value-bearing member `A = <expr>` (Parser.cs :1290) now materializes its Value
                // when the expression is a leaf/paren atom (ParseExprValue().Node non-null); a composed /
                // deferred value leaves Node null → the enum declines (no-stub). A valueless member keeps null.
                if Check(TokenType.Assign) {
                    Advance()
                    valueResult := ParseExprValue()
                    // the member value (Parser.cs :1290)
                    if valueResult.Node == null {
                        TypeBodyMaterializable = false
                    }
                    // Parser.cs :1304: the FIRST member's string-literal value infers EnumType.String (applied
                    // by ParseEnumName only when the backing type was not explicit). members.Count is the count
                    // BEFORE this member is added, so this fires only for the very first member.
                    if members.Count == 0 && valueResult.Node is StringLiteralExpression {
                        EnumBodyInferredString = true
                    }
                    members.Add(new EnumMember(memberName, valueResult.Node, memberLine, memberColumn))
                } else {
                    members.Add(new EnumMember(memberName, null, memberLine, memberColumn))
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
        return members
    }

    // Parser.cs ParseSoaRecordDeclaration body (:1085): the soa-column loop. Each column is `name: Type`;
    // a trailing comma or semicolon is optional between columns. Resets panic at each column boundary and
    // reports the soa-specific missing-'}' (NL106) on the soa diagnostic span. Assumes the '{' is next.
    // Stage N+1c tranche 6: RETURNS the byte-exact `List<SoaColumnDeclaration>` Parser.cs :1108 builds — each
    // column `new SoaColumnDeclaration(columnName, columnType, columnLine, columnColumn)` (columnType through
    // ParseMaterializedTypeReference). A PURE side-effect; the Advance/Report/Consume sequence is unchanged.
    // `TypeBodyMaterializable` clears on an `<error>` column name or a structurally-unbuildable / multi-line
    // column type → the soa record declines.
    func ParseSoaRecordBody(soaDiagnosticSpan: RecoverySpan, openingLine: int): List<SoaColumnDeclaration> {
        TypeBodyMaterializable = true
        columns := new List<SoaColumnDeclaration>()
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            PanicMode = false
            // reset at each column boundary (Parser.cs :1090)
            startPosition := Position
            columnLine := Current().Line
            // Parser.cs :1103 (captured BEFORE the name)
            columnColumn := Current().Column
            columnName := ConsumeIdentifier("Expected soa column name")
            // Parser.cs :1094
            ConsumeToken(TokenType.Colon, "Expected ':'", ":")
            columnType := ParseMaterializedTypeReference()
            // Stage N+1c tranche 11: an `<error>` column name is Parser.cs's own placeholder.
            if columnType == null {
                TypeBodyMaterializable = false
            } else {
                columns.Add(new SoaColumnDeclaration(columnName, columnType, columnLine, columnColumn))
            }
            // Parser.cs :1108

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
        return columns
    }

    // The union / enum / soa body's own end-of-file missing-'}' report (Parser.cs :1114/:1225/:1317). Each
    // kind's message names its own body kind ("union body" / "enum body" / "soa record body"); the code,
    // span, hint suffix ("union declaration" / "enum declaration" / "soa record declaration"), and length
    // mirror the per-kind ReportError exactly.
    func ReportTypeBodyMissingClosingBrace(span: RecoverySpan, openingLine: int, kind: string) {
        Report(ErrorCode.MissingClosingBrace, "Missing closing '}'", span.Line, span.Column, "The " + kind + " body that started on line " + IntToString(openingLine) + " is missing its closing brace. I reached the end of the file without finding it.", "Add a '}' to close this " + kind + " declaration.", null, span.Length)
    }

    func ParseTypeAliasName() {
        typeToken := Current()
        Advance()
        // Parser.cs anchors with new DiagnosticSpan(line, column, Math.Max(1, "type".Length))
        // (:1337); with the keyword value "type" that equals SpanFromToken(typeToken).
        aliasName := ConsumeDeclarationName("Expected type alias name", new RecoverySpan(typeToken.Line, typeToken.Column, MaxInt(1, 4)))

        // Stage 17: the `= <type>` underlying-type body (Parser.cs :1338-1350). The '=' Consume
        // (present → advance; absent mid-line → the standard ExpectedToken NL102 "Expected '='.
        // Expected 'assign', got 'X'"; absent at EOF → the ExpectedEndOfFile NL104 "Expected 'assign'
        // but reached the end of the file"; suppressed when a prior alias-name error set panic), the
        // optional `newtype` keyword (`type X = newtype Y`, a bare advance :1341-1345), and the
        // underlying type via the Stage-15 full ParseTypeReferenceRecovery grammar (union `A | B` /
        // postfix array-nullable / byref / tuple / Func / generic — every error site already owned).
        ConsumeToken(TokenType.Assign, "Expected '='", "assign")
        // N+1c tranche 6: the `newtype` variant selects NewtypeDeclaration (Parser.cs :1356) over
        // TypeAliasDeclaration (Parser.cs :1361); both carry Line/Column on the `type` keyword and hang the
        // underlying type via the shared ParseMaterializedTypeReference gate. TypeAliasDeclaration /
        // NewtypeDeclaration carry NO modifiers/attributes (the model has no such fields), so the dispatch's
        // captured modifiers/attributes are correctly discarded, byte-exact to Parser.cs. A missing `=` sets
        // panic → the gate returns null → decline (no-stub); a malformed / multi-line underlying type declines.
        isNewtype := false
        if Check(TokenType.Newtype) {
            isNewtype = true
            Advance()
        }
        underlyingType := ParseMaterializedTypeReference()
        // Stage N+1c tranche 11: an `<error>` alias name is Parser.cs's own placeholder and it still builds
        // the TypeAlias / Newtype declaration around it (:1356/:1361).
        if underlyingType != null {
            if isNewtype {
                // NewtypeDeclaration has no test-stub twin → simple name resolves uniquely.
                AddDeclaration(new NewtypeDeclaration(aliasName, underlyingType, typeToken.Line, typeToken.Column))
            } else {
                // FULLY QUALIFIED: a test-helper `class TypeAliasDeclaration` in NSharpLang.Compiler.TestStubs
                // shares the simple name under the tests-enabled build (the ClassDeclaration/FieldDeclaration idiom).
                AddDeclaration(new NSharpLang.Compiler.Ast.TypeAliasDeclaration(aliasName, underlyingType, typeToken.Line, typeToken.Column))
            }
        }
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

    // Stage N+1c tranche 6: RETURNS the byte-exact `List<TypeParameter>?` Parser.cs :736 builds (null when no
    // `<`, else one `new TypeParameter(name)` per param — Parser.cs :755, name = the lifetime token value or
    // the ConsumeIdentifier result) as a PURE side-effect; the Advance/Report/Consume sequence is unchanged,
    // so the diagnostic stream is unperturbed. The ~4 diagnostic-only callers (function/method heads, the
    // generic-soa report) discard the returned list; the class/struct/record/interface/union sites capture it.
    // Stage N+1c tranche 11 RETIRED the companion materialization gate: a malformed `<>` / `<T,>` /
    // reserved-keyword list is a Parser.cs RECOVERY ARTIFACT — it breaks out of the do-loop and returns the
    // PARTIAL list (with its `<error>` names) from the same `return typeParams` (:757) — so the enclosing
    // declaration materializes over it rather than declining.
    func ParseTypeParameters(): List<TypeParameter>? {
        if !Check(TokenType.Less) {
            return null
        }
        lessToken := Advance()
        // consume '<'
        typeParams := new List<TypeParameter>()
        parsing := true
        while parsing {
            if Check(TokenType.Greater) {
                // `<>` (empty) or `<T,>` (trailing comma): the name is missing (Parser.cs :735-738).
                ReportMissingTypeParameterName(lessToken)
                parsing = false
            } else {
                // A lifetime `'a` or an identifier type-parameter name (Parser.cs :741-743). Parser.cs's
                // `new TypeParameter(name)` takes the lifetime token's VALUE or the ConsumeIdentifier result.
                if Check(TokenType.Lifetime) {
                    lifetimeToken := Advance()
                    typeParams.Add(new TypeParameter(lifetimeToken.Value))
                } else {
                    paramName := ConsumeIdentifier("Expected type parameter name")
                    typeParams.Add(new TypeParameter(paramName))
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
        // Stage N+1c tranche 11: Parser.cs returns the accumulated list unconditionally (:757), including the
        // `<>` / `<T,>` early break and an `<error>` type-parameter name — no decline.
        return typeParams
    }

    // Parser.cs ReportMissingTypeParameterName (:6439). The span runs from the opening `<` to the
    // offending token (DiagnosticSpanFromTokenRange), so it underlines the whole `<>` / `<T,>`.
    func ReportMissingTypeParameterName(lessToken: Token) {
        span := DiagnosticSpanFromTokenRange(lessToken, Current())
        suggestions := new List<string>()
        suggestions.Add("Add a type parameter name")
        suggestions.Add("Remove the trailing comma if the list is complete")
        Report(ErrorCode.ExpectedToken, "Expected type parameter name. Got '" + Current().Value + "'", span.Line, span.Column, "Generic parameter lists need a type parameter name after each comma.", "Write generic parameters as `<T>` or `<T, U>`.", suggestions, span.Length)
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
        if start.Line <= 0 || start.Column <= 0 {
            return SourceSpan.None
        }
        return new SourceSpan(start.Line, start.Column, end.Line, end.Column + MaxInt(1, end.Value.Length))
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
        return new SourceSpan(start.Span.StartLine, start.Span.StartColumn, end.Line, end.Column + MaxInt(1, end.Value.Length))
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
        node := ParseGatedTypeReference()
        if !TypeReferenceMaterialized {
            return null
        }
        return node
    }

    // The same gate, but returning the RAW parsed node (Parser.cs's `type`) and recording the verdict in
    // `TypeReferenceMaterialized`. Stage N+1c tranche 9b needs both halves at the `new` site: the RAW node
    // drives Parser.cs's `type is ArrayTypeReference` collection-initializer decision (:5294) — a DECISION
    // Parser.cs makes on the parsed type regardless of diagnostics — while the gate still decides whether the
    // NewExpression may materialize. The field is written and read back-to-back at each call site.
    func ParseGatedTypeReference(): TypeReference? {
        node := ParseTypeReferenceRecovery()
        TypeReferenceMaterialized = node != null
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
        first := ParsePostfixTypeReferenceRecovery()
        // first arm (Parser.cs :1781)
        if !Check(TokenType.BitwiseOr) {
            // Parser.cs :1782 early return
            return first
        }
        // Union `A | B | …` (Parser.cs :1785). Arms accumulate; lastToken tracks the last consumed real
        // token, ExtendSpan's end (Parser.cs :1805).
        arms := new List<TypeReference>()
        if first != null {
            arms.Add(first)
        }
        // Parser.cs :1786 seeds `lastToken = Current` (the `|` itself), then re-reads `Previous` after each
        // parsed arm (:1805). The trailing-`|` break therefore keeps the PREVIOUS lastToken, not the `|`.
        lastToken := Current()
        scanningUnion := true
        while scanningUnion {
            if Check(TokenType.BitwiseOr) {
                // Parser.cs :1788
                Advance()
                // consume '|' (Parser.cs :1790)
                if IsTypeTerminator(Current().Type) {
                    // trailing `|` (Parser.cs :1791)
                    ReportUnionMissingTypeArm()
                    // NL103 (Parser.cs :1793), then break
                    scanningUnion = false
                } else {
                    arm := ParsePostfixTypeReferenceRecovery()
                    // next arm (Parser.cs :1804)
                    if arm != null {
                        arms.Add(arm)
                    }
                    lastToken = Previous()
                }
            } else {
                // Parser.cs :1805
                scanningUnion = false
            }
        }
        if first == null {
            return null
        }
        // Parser.cs :1808 `new UnionTypeReference(arms) { Span = ExtendSpan(first, lastToken) }`.
        result := new UnionTypeReference(arms)
        result.Span = ExtendSpanFromNode(first, lastToken)
        return result
    }

    // Parser.cs ParseUnionTypeReference's missing-arm report (:1793): a `|` immediately followed by a type
    // terminator. Anchored on the terminator token (Current), length Max(1, its value length), no
    // suggestions (Parser.cs's ReportError omits them). After it the loop breaks — only the FIRST trailing
    // `|` reports (and, being in panic after the report, any later `|` would be suppressed regardless).
    func ReportUnionMissingTypeArm() {
        Report(ErrorCode.InvalidSyntax, "Expected a type after '|' in anonymous union type", Current().Line, Current().Column, "Anonymous union types use the form `A | B`, so every `|` must be followed by another type.", "Add the missing type arm, or remove the trailing `|`.", null, MaxInt(1, Current().Value.Length))
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
                Advance()
                // '[' (Parser.cs :1823)
                rightBracket := Advance()
                // guaranteed ']' (Consume never fails, :1824)
                baseType = WrapArrayType(baseType, rightBracket)
            } else {
                // Parser.cs :1825
                if Check(TokenType.QuestionBracket) && LookAhead(1).Type == TokenType.RightBracket {
                    questionBracket := Advance()
                    // '?[' (Parser.cs :1834)
                    baseType = WrapNullableQuestionBracketType(baseType, questionBracket)
                    // Parser.cs :1835
                    rightBracket := Advance()
                    // guaranteed ']' (:1846)
                    baseType = WrapArrayType(baseType, rightBracket)
                } else {
                    // Parser.cs :1847
                    if Check(TokenType.Question) {
                        question := Advance()
                        // '?' nullable (Parser.cs :1856)
                        baseType = WrapNullableType(baseType, question)
                    } else {
                        // Parser.cs :1857
                        suffixLooping = false
                    }
                }
            }
        }
        // Parser.cs :1864 break

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
            result.Span = new SourceSpan(inner.Span.StartLine, inner.Span.StartColumn, questionBracket.Line, questionBracket.Column + 1)
        } else {
            result.Span = SourceSpan.None
        }
        return result
    }

    // Parser.cs ParseBaseTypeReference (:1884): a byref `&T`, a parenthesized / tuple type `( … )`, a
    // `Func<…>` function type, or the simple / qualified / generic identifier arm (owned since Stage 5).
    func ParseBaseTypeReferenceRecovery(): TypeReference? {
        if Check(TokenType.BitwiseAnd) {
            // byref &T (Parser.cs :1886)
            ampersand := Current()
            Advance()
            inner := ParsePostfixTypeReferenceRecovery()
            // inner is a POSTFIX type (Parser.cs :1889)
            return MakeByRefType(ampersand, inner)
        }
        if Check(TokenType.LeftParen) {
            // tuple / parenthesized (Parser.cs :1899)
            return ParseParenthesizedOrTupleTypeReferenceRecovery()
        }
        if Check(TokenType.Identifier) && Current().Value == "Func" {
            // Func<…> (Parser.cs :1905)
            return ParseFunctionTypeReferenceRecovery()
        }

        // simple / qualified / generic (Parser.cs :1910-1962). Capture the accumulated dotted name + the
        // last name token (ExtendSpan's end for a simple type) so a qualified `A.B.C` materializes byte-exact.
        typeNameToken := Current()
        firstName := ConsumeIdentifier("Expected type name")
        // Parser.cs :1914
        name := firstName
        lastNameToken := typeNameToken
        while Check(TokenType.Dot) {
            // qualified name A.B (Parser.cs :1918)
            Advance()
            lastNameToken = Current()
            // Parser.cs :1921 captures Current BEFORE consuming
            segment := ConsumeIdentifier("Expected identifier after '.'")
            name = name + "." + segment
        }

        if Check(TokenType.Less) {
            lessToken := Advance()
            // consume '<'
            typeArgs := new List<TypeReference>()
            if Check(TokenType.Greater) {
                ReportMissingGenericTypeArgument(typeNameToken, lessToken)
            } else {
                // `Name<>` (Parser.cs :1930)
                firstArg := ParseTypeReferenceRecovery()
                // first type argument (full grammar, Parser.cs :1936)
                if firstArg != null {
                    typeArgs.Add(firstArg)
                }
                scanning := true
                while scanning {
                    if Check(TokenType.Comma) {
                        Advance()
                        if Check(TokenType.Greater) {
                            // `Name<T,>` trailing comma (Parser.cs :1940-1943).
                            ReportMissingGenericTypeArgument(typeNameToken, lessToken)
                            scanning = false
                        } else {
                            nextArg := ParseTypeReferenceRecovery()
                            if nextArg != null {
                                typeArgs.Add(nextArg)
                            }
                        }
                    } else {
                        scanning = false
                    }
                }
            }
            greater := ConsumeGreater("Expected '>'")
            // Parser.cs :1950
            // Parser.cs :1951 `new GenericTypeReference(name, typeArgs) { Line = typeNameLine, Column =
            // typeNameColumn, Span = SpanFromTokens(typeNameToken, greater) }` — the 4-arg ctor sets Line/Column.
            result := new GenericTypeReference(name, typeArgs, typeNameToken.Line, typeNameToken.Column)
            result.Span = SpanFromTokensSingleLine(typeNameToken, greater)
            return result
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
            result.Span = new SourceSpan(ampersand.Line, ampersand.Column, inner.Span.EndLine, inner.Span.EndColumn)
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
        Advance()
        // '(' (Consume guarded, Parser.cs :1967)
        elements := new List<TupleTypeElement>()
        tupleLooping := true
        while tupleLooping {
            elementName: string? = null
            if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon {
                elementName = Advance().Value
                // element name (Parser.cs :1977)
                Advance()
            }
            // ':' (Parser.cs :1978)

            elementType := ParseTypeReferenceRecovery()
            // element type (Parser.cs :1981)
            if elementType != null {
                elements.Add(new TupleTypeElement(elementType, elementName))
            }
            // Parser.cs :1982

            if Check(TokenType.Comma) {
                // Parser.cs :1984 `while Match(Comma)`
                Advance()
            } else {
                tupleLooping = false
            }
        }
        rightParen := ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        // Parser.cs :1986
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
        Advance()
        // 'Func' (Consume guarded, Parser.cs :2002)
        ConsumeToken(TokenType.Less, "Expected '<'", "less")
        // Parser.cs :2003
        // Parser.cs :2005-2012: the LAST parsed type is the return type; the preceding ones are the parameter
        // types. So each comma pushes the CURRENT returnType into paramTypes before the next parse.
        paramTypes := new List<TypeReference>()
        returnType := ParseTypeReferenceRecovery()
        // first type = return (Parser.cs :2006)
        while Check(TokenType.Comma) {
            // Parser.cs :2008 `while Match(Comma)`
            Advance()
            if returnType != null {
                paramTypes.Add(returnType)
            }
            // Parser.cs :2010

            returnType = ParseTypeReferenceRecovery()
        }
        // Parser.cs :2011

        greater := ConsumeGreater("Expected '>'")
        // Parser.cs :2014
        if returnType == null {
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
        Report(ErrorCode.ExpectedToken, "Expected type name. Got '" + Current().Value + "'", span.Line, span.Column, "Generic type '" + typeName + "' needs a type argument between '" + lessToken.Value + "' and '>'.", "Write this type as `" + typeName + "<T>` or remove the generic argument list.", suggestions, span.Length)
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
        Report(ErrorCode.ExpectedToken, message + ". Got '" + Current().Value + "'", Current().Line, Current().Column, "I was parsing generic type parameters and expected to see a closing '>' here.", GetHintForMissingToken(TokenType.Greater), suggestions, Current().Value.Length)
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
            Report(ErrorCode.UnexpectedEndOfFile, "Expected '" + expected + "' but reached the end of the file", ownerSpan.Line, ownerSpan.Column, "I was expecting '" + expected + "' here, but the file ended first.", HintForMissingTokenOrDefault(tokenType, "Finish this construct before the end of the file."), null, ownerSpan.Length)
            return Current()
        }
        Report(ErrorCode.ExpectedToken, message + ". Expected '" + expected + "', got '" + Current().Value + "'", Current().Line, Current().Column, "I was expecting " + expected + " here, but I found '" + Current().Value + "' instead.", GetHintForMissingToken(tokenType), null, Current().Value.Length)
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

        Report(code, "Missing closing '" + expected + "'", span.Line, span.Column, explanation, hint, suggestions, span.Length)

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
    // Stage N+1c tranche 10b: RETURNS the byte-exact `List<GenericConstraint>` (null when the `where`
    // clause is ABSENT — Parser.cs :854 returns null, not an empty list), recording an unmaterializable
    // constraint type / `<error>` type-parameter name in ConstraintsMaterializable (read by the caller
    // IMMEDIATELY after the call).
    func ParseGenericConstraints(): List<GenericConstraint>? {
        ConstraintsMaterializable = true
        if !Check(TokenType.Where) {
            return null
        }
        constraints := new List<GenericConstraint>()
        while Check(TokenType.Where) {
            Advance()
            // consume 'where'
            typeParameterName := ConsumeIdentifier("Expected type parameter")
            // Parser.cs :861
            ConsumeToken(TokenType.Colon, "Expected ':'", ":")
            // Parser.cs :862
            constraintTypes := new List<TypeReference>()
            specialConstraints := 0

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
                    specialConstraints = specialConstraints | 1
                } else {
                    // SpecialConstraintKind.Class
                    if Check(TokenType.Struct) {
                        structToken = Current()
                        Advance()
                        hasStruct = true
                        specialConstraints = specialConstraints | 2
                    } else {
                        // SpecialConstraintKind.Struct
                        if Check(TokenType.New) && LookAhead(1).Type == TokenType.LeftParen {
                            newStartToken = Current()
                            Advance()
                            // consume 'new'
                            Advance()
                            // consume '('
                            newEndToken = ConsumeToken(TokenType.RightParen, "Expected ')' after 'new('", ")")
                            hasNew = true
                            specialConstraints = specialConstraints | 4
                        } else {
                            // SpecialConstraintKind.New
                            constraintType := ParseMaterializedTypeReference()
                            // Parser.cs :892
                            if constraintType == null {
                                ConstraintsMaterializable = false
                            } else {
                                constraintTypes.Add(constraintType)
                            }
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
            // Stage N+1c tranche 10b: `new GenericConstraint(typeParam, constraintTypes, specialConstraints)`
            // (Parser.cs :928). The flag bitmask is accumulated as an int and cast back — the emittable idiom.
            // Stage N+1c tranche 11: an `<error>` type-parameter name is Parser.cs's own placeholder and it
            // still builds the GenericConstraint around it (:936).
            constraints.Add(new GenericConstraint(typeParameterName, constraintTypes, (SpecialConstraintKind)specialConstraints))
        }
        return constraints
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
        Report(ErrorCode.InvalidSyntax, "Cannot have both 'class' and 'struct' constraints on the same type parameter — they are mutually exclusive", line, column, "A type parameter cannot be both a reference type (class) and a value type (struct) at the same time.", null, null, length)
    }

    func ReportStructNewRedundancy(newStartToken: Token?, newEndToken: Token?) {
        line := Current().Line
        column := Current().Column
        if newStartToken != null {
            resolved := newStartToken ?? Current()
            line = resolved.Line
            column = resolved.Column
        }
        Report(ErrorCode.InvalidSyntax, "Cannot combine 'struct' and 'new()' constraints — 'struct' already implies a parameterless constructor", line, column, "The 'struct' constraint already requires a parameterless constructor, so 'new()' is redundant and not permitted in .", null, null, TokenSpanLengthOrFallback(newStartToken, newEndToken))
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
    // Stage N+1c tranche 10 (STATEMENT BODIES): returns the byte-exact `new BlockStatement(statements,
    // line, column)` (Parser.cs :2227) — line/column are the OPENING BRACE's position, captured before the
    // Consume. Declines (null, no-stub) when ANY contained statement declined, so a block never carries a
    // partial statement list.
    func ParseBlockBody(ownerSpan: RecoverySpan?): BlockStatement? {
        line := Current().Line
        column := Current().Column
        Advance()
        // consume '{'
        diagnosticSpan := ownerSpan ?? new RecoverySpan(line, column, 1)
        statements := ParseBlockStatementsLoop(diagnosticSpan, line)
        if statements == null {
            return null
        }
        return new BlockStatement(statements, line, column)
    }

    // Parser.cs ParseBlock (:2143): Consume the opening '{' FIRST (reporting a missing '{' through the
    // standard Consume path), then run the shared block-statements loop. This is the entry the
    // block-bearing statement kinds reach — try / catch / finally / using / lock / switch / unsafe /
    // alloc-block / allow / assert-throws / local-function all call ParseBlock directly WITHOUT a
    // preceding Check(LeftBrace) (Stage 13), unlike the if/while/for bodies that route through the
    // block case of ParseStatement.
    func ParseBlock(ownerSpan: RecoverySpan?): BlockStatement? {
        line := Current().Line
        column := Current().Column
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        diagnosticSpan := ownerSpan ?? new RecoverySpan(line, column, 1)
        statements := ParseBlockStatementsLoop(diagnosticSpan, line)
        if statements == null {
            return null
        }
        return new BlockStatement(statements, line, column)
    }

    // The shared block-statements loop (Parser.cs ParseBlock's while body, :2151-2214): the
    // per-statement panic reset + _currentRecoveryBoundaryColumn tracking + no-progress synchronize
    // + the closing-'}' / found-declaration / EOF missing-'}' reports. Both ParseBlockBody and
    // ParseBlock funnel through it so the block grammar is modelled once.
    // Stage N+1c tranche 10: ACCUMULATES the block's statement list (Parser.cs :2161/:2189
    // `statements.Add(ParseStatement())`) and returns it, or null when any statement declined
    // materialization. A decline does NOT change the parse: the loop keeps running (the same Advance /
    // Report / synchronize sequence), so the diagnostic stream is byte-identical either way.
    func ParseBlockStatementsLoop(diagnosticSpan: RecoverySpan, openingLine: int): List<Statement>? {
        statements := new List<Statement>()
        declined := false
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            // Stage 9: a type-declaration keyword that can't be a statement signals a missing '}' — report
            // the found-declaration NL106 anchored on the block owner and break so the outer declaration
            // loop parses it as a new declaration (Parser.cs :2156-2170, does NOT advance). Parser.cs
            // `break`s here and still returns the statements accumulated so far (the trailing '}' / EOF
            // checks are both no-ops on this path).
            if IsBlockClosingDeclarationStart() {
                ReportBlockMissingClosingBraceFoundDeclaration(diagnosticSpan, openingLine)
                if declined {
                    return null
                }
                return statements
            }

            PanicMode = false
            // reset at each statement boundary (Parser.cs :2172)
            startPosition := Position

            // Track this statement's starting column so IsMissingOperandBoundary can tell a genuine
            // continuation from the start of the next statement (Parser.cs :2174-2182).
            prevBoundary := RecoveryBoundaryColumn
            prevHasBoundary := HasRecoveryBoundaryColumn
            RecoveryBoundaryColumn = Current().Column
            HasRecoveryBoundaryColumn = true
            statement := ParseStatement(null)
            RecoveryBoundaryColumn = prevBoundary
            HasRecoveryBoundaryColumn = prevHasBoundary
            if statement == null {
                declined = true
            } else {
                // Stamp the statement's last covered source line (its final consumed token) so the
                // formatter can measure blank-line gaps from statement ENDS instead of starts.
                statement.EndLine = TokenEndLine(Previous())
                statements.Add(statement)
            }

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
        if declined {
            return null
        }
        return statements
    }

    // Parser.cs ParseBlock's end-of-file missing-'}' report (:2205). Stage 9 exercises it.
    func ReportMissingClosingBrace(diagnosticSpan: RecoverySpan, openingLine: int) {
        Report(ErrorCode.MissingClosingBrace, "Missing closing '}'", diagnosticSpan.Line, diagnosticSpan.Column, "The block that started on line " + IntToString(openingLine) + " is missing its closing brace. I reached the end of the file without finding it.", "Add a '}' to close this block.", null, diagnosticSpan.Length)
    }

    // Parser.cs ParseBlock's found-declaration missing-'}' report (:2158). Fired when a type-declaration
    // keyword appears mid-block: the block is presumed unclosed and the offending declaration is left for
    // the outer loop (Stage 9).
    func ReportBlockMissingClosingBraceFoundDeclaration(diagnosticSpan: RecoverySpan, openingLine: int) {
        Report(ErrorCode.MissingClosingBrace, "Missing closing '}'", diagnosticSpan.Line, diagnosticSpan.Column, "The block that started on line " + IntToString(openingLine) + " appears to be missing its closing brace. I found '" + Current().Value + "' on line " + IntToString(Current().Line) + ", which looks like a new declaration.", "Add a '}' before this declaration to close the previous block.", null, diagnosticSpan.Length)
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
    // expression-statement kinds — the surface the migrated parser-error statement shapes reach
    // (now stated in ColumnarParserErrorRecovery.tests.nl; tests/ParserErrorTests.cs is deleted).
    // yield / break / continue / throw / try / using / lock / switch / allow / alloc / unsafe / assert /
    // preprocessor / local-function / await-foreach / off statements are later arc stages (the corpus
    // uses none); they would each add their own ReportError sites under the same shared-panic model.
    // Stage N+1c tranche 10: each arm now RETURNS its byte-exact Statement node (or null — the
    // established no-stub decline). The dispatch order, the Advance/Report sequence, and every sub-call
    // are UNCHANGED, so the diagnostic stream is byte-identical.
    func ParseStatement(blockOwnerSpan: RecoverySpan?): Statement? {
        // A control-flow keyword whose body is missing (Parser.cs :2221): the caller passes its owner
        // span, and if the very next token cannot begin a statement, report the missing body.
        if blockOwnerSpan != null {
            if IsMissingStatementBodyBoundary() {
                owner := blockOwnerSpan ?? SpanFromToken(Current())
                ReportMissingStatementBody(owner)
                // Parser.cs :2235 `new EmptyStatement(ownerSpan.Line, ownerSpan.Column)`.
                return new EmptyStatement(owner.Line, owner.Column)
            }
        }

        if Check(TokenType.Semicolon) {
            emptyLine := Current().Line
            emptyColumn := Current().Column
            Advance()
            // empty statement (Parser.cs :2228)
            return new EmptyStatement(emptyLine, emptyColumn)
        }

        if Check(TokenType.Let) {
            return ParseVariableDeclaration()
        }
        if Check(TokenType.Const) {
            return ParseVariableDeclaration()
        }
        if Check(TokenType.Readonly) {
            return ParseVariableDeclaration()
        }
        if Check(TokenType.If) {
            return ParseIfStatement()
        }
        if Check(TokenType.For) {
            return ParseForStatement()
        }
        if Check(TokenType.Foreach) {
            return ParseForeachStatement()
        }
        // `await foreach` async iteration (Parser.cs :2249) — a compound dispatch before plain `while`.
        if Check(TokenType.Await) && LookAhead(1).Type == TokenType.Foreach {
            return ParseAwaitForeachStatement()
        }
        if Check(TokenType.While) {
            return ParseWhileStatement()
        }
        if Check(TokenType.Return) {
            return ParseReturnStatement()
        }
        if Check(TokenType.Yield) {
            return ParseYieldStatement()
        }
        if Check(TokenType.Break) {
            return ParseBreakStatement()
        }
        if Check(TokenType.Continue) {
            return ParseContinueStatement()
        }
        if Check(TokenType.Throw) {
            return ParseThrowStatement()
        }
        if Check(TokenType.Try) {
            return ParseTryStatement()
        }
        if Check(TokenType.Using) {
            return ParseUsingStatement()
        }
        if Check(TokenType.Lock) {
            return ParseLockStatement()
        }
        if Check(TokenType.Switch) {
            return ParseSwitchStatement()
        }
        if Check(TokenType.Allow) {
            return ParseAllowStatement()
        }
        // alloc BLOCK statement `alloc { … }` — a compound dispatch (Parser.cs :2273); a bare `alloc`
        // is an expression primary (Stage 11), reached through ParseExpressionStatement below.
        if Check(TokenType.Alloc) && LookAhead(1).Type == TokenType.LeftBrace {
            return ParseAllocBlockStatement()
        }
        if Check(TokenType.Unsafe) {
            return ParseUnsafeBlockStatement()
        }
        if Check(TokenType.Print) {
            return ParsePrintStatement()
        }
        if Check(TokenType.Assert) {
            return ParseAssertStatement()
        }
        if Check(TokenType.PreprocessorDirective) {
            return ParsePreprocessorDirective()
        }
        if Check(TokenType.LeftBrace) {
            return ParseBlockBody(blockOwnerSpan)
        }

        // Local function (Parser.cs :2287): [static] [async] func Name(…) … The two-modifier
        // `static async func` and one-modifier `static func` / `async func` and bare `func` forms.
        if (Check(TokenType.Static) || Check(TokenType.Async)) && LookAhead(1).Type == TokenType.Func {
            return ParseLocalFunction()
        }
        if Check(TokenType.Static) && LookAhead(1).Type == TokenType.Async && LookAhead(2).Type == TokenType.Func {
            return ParseLocalFunction()
        }
        if Check(TokenType.Func) {
            return ParseLocalFunction()
        }

        // The contextual `off handle` unsubscription statement (Parser.cs :2294).
        if IsOffStatementStart() {
            return ParseOffStatement()
        }

        return ParseExpressionStatement()
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
        Report(ErrorCode.ExpectedToken, "Expected statement body. Got '" + Current().Value + "'", ownerSpan.Line, ownerSpan.Column, "This control-flow keyword needs a statement or block after its condition.", "Add a block like `{ ... }`, or add a single statement after the keyword.", suggestions, ownerSpan.Length)
    }

    // ---- variable declaration (Parser.cs ParseVariableDeclaration :2531) ----
    // let / const / readonly share one parser; the ownerDescription is always "This variable
    // declaration" regardless of kind. Tuple deconstruction `(x, y) := …` is a later arc stage.
    // Stage N+1c tranche 10: RETURNS the byte-exact node — `new VariableDeclarationStatement(name, type,
    // initializer, kind, line, column)` (Parser.cs :2578) for the plain form, or the tuple-deconstruction
    // node for the `let (a, b) := …` arm. `kind` is read off the let/const/readonly token Parser.cs's
    // caller passes as VariableKind (:2248-2252). Line/Column anchor the NAME token (Parser.cs :2556).
    // Declines when the name is `<error>`, when a PRESENT type annotation or initializer did not
    // materialize, and (via the tuple arm) whenever that arm declines. The arm taken is recorded in
    // VariableDeclarationWasTuple for the using-statement caller.
    func ParseVariableDeclaration(): Statement? {
        kind := VariableKindFor(Current().Type)
        Advance()
        // consume let / const / readonly
        VariableDeclarationWasTuple = false

        // Tuple deconstruction `(x, y) := …` (Parser.cs :2536). The paren position anchors it.
        if Check(TokenType.LeftParen) {
            tupleLine := Current().Line
            tupleColumn := Current().Column
            tupleNode := ParseTupleDeconstruction(kind, tupleLine, tupleColumn)
            VariableDeclarationWasTuple = true
            return tupleNode
        }

        line := Current().Line
        column := Current().Column
        name := ConsumeIdentifier("Expected variable name")

        // Optional type annotation `: T` (Parser.cs :2550).
        declaredType: TypeReference? = null
        typeDeclined := false
        if Check(TokenType.Colon) {
            Advance()
            declaredType = ParseMaterializedTypeReference()
            typeDeclined = declaredType == null
        }

        initializer: Expression? = null
        initializerDeclined := false
        if Check(TokenType.Assign) || Check(TokenType.ColonAssign) {
            initializerToken := Advance()
            initializer = ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This variable declaration", new RecoverySpan(line, column, MaxInt(1, name.Length)))
            initializerDeclined = initializer == null
        }

        if typeDeclined || initializerDeclined {
            return null
        }
        return new VariableDeclarationStatement(name, declaredType, initializer, kind, line, column)
    }

    // Parser.cs :2248-2252: the let / const / readonly dispatch passes the matching VariableKind.
    func VariableKindFor(tokenType: TokenType): VariableKind {
        if tokenType == TokenType.Const {
            return VariableKind.Const
        }
        if tokenType == TokenType.Readonly {
            return VariableKind.Readonly
        }
        return VariableKind.Let
    }

    // Parser.cs ParseTupleDeconstruction (:2570): `(a, b, …) := expr` / `(a, b) = expr`. The name list,
    // the ':='/'=' requirement (NL102 when absent, then skip the offender), and the required initializer.
    // Stage N+1c tranche 10: RETURNS `new TupleDeconstructionStatement(names, initializer, kind, line,
    // column)` (Parser.cs :2637); declines only when the initializer did not materialize. An `<error>`
    // element name is a RECOVERY ARTIFACT Parser.cs keeps in the list verbatim (:2589 adds every name
    // unconditionally), so it is reproduced rather than declined.
    func ParseTupleDeconstruction(kind: VariableKind, line: int, column: int): Statement? {
        ConsumeToken(TokenType.LeftParen, "Expected '('", "(")

        names := new List<string>()
        scanning := true
        while scanning {
            names.Add(ConsumeIdentifier("Expected identifier or '_'"))
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
        initializer: Expression? = null
        if Check(TokenType.ColonAssign) || Check(TokenType.Assign) {
            initializerToken := Advance()
            initializer = ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This tuple deconstruction", null)
        } else {
            initializer = ParseRequiredExpressionAfter(Current(), "an initializer expression", "This tuple deconstruction", null)
        }

        if initializer == null {
            return null
        }
        return new TupleDeconstructionStatement(names, initializer, kind, line, column)
    }

    // Parser.cs ParseTupleDeconstruction's ':='/'=' missing report (:2586).
    func ReportTupleDeconstructionRequiresAssign() {
        suggestions := new List<string>()
        suggestions.Add("Add ':=' for new variables: (x, y) := (1, 2)")
        suggestions.Add("Add '=' for existing variables: (x, y) = tuple")
        suggestions.Add("Example: (name, age) := getPerson()")
        Report(ErrorCode.ExpectedToken, "Tuple deconstruction requires ':=' or '='. Got '" + Current().Value + "'", Current().Line, Current().Column, "To unpack a tuple into multiple variables, you need to use ':=' or '=' after the variable list.", "Tuple deconstruction syntax: (x, y) := getTuple() or (x, y) = getTuple()", suggestions, Current().Value.Length)
    }

    // ---- if / while / for / foreach (Parser.cs :2629 / :2806 / :2651 / :2747) ----

    // Stage N+1c tranche 10: `new IfStatement(condition, thenStatement, elseStatement, line, column)`
    // (Parser.cs :2659) — line/column are the `if` keyword's. An ABSENT else is a materialized null;
    // a PRESENT-but-declined else declines the whole statement (no-stub).
    func ParseIfStatement(): Statement? {
        ifToken := Current()
        line := ifToken.Line
        column := ifToken.Column
        Advance()
        // consume 'if'
        condition := ParseRequiredExpressionAfter(ifToken, "a condition expression", "This if statement", null)
        thenStatement := ParseStatement(SpanFromToken(ifToken))
        // then-branch, with the missing-body owner span
        elseStatement: Statement? = null
        elseDeclined := false
        if Check(TokenType.Else) {
            elseToken := Current()
            Advance()
            elseStatement = ParseStatement(SpanFromToken(elseToken))
            elseDeclined = elseStatement == null
        }
        if condition == null || thenStatement == null || elseDeclined {
            return null
        }
        return new IfStatement(condition, thenStatement, elseStatement, line, column)
    }

    // Stage N+1c tranche 10: `new WhileStatement(condition, body, line, column)` (Parser.cs :2829).
    func ParseWhileStatement(): Statement? {
        whileToken := Current()
        line := whileToken.Line
        column := whileToken.Column
        Advance()
        // consume 'while'
        condition := ParseRequiredExpressionAfter(whileToken, "a condition expression", "This while statement", null)
        body := ParseStatement(SpanFromToken(whileToken))
        if condition == null || body == null {
            return null
        }
        return new WhileStatement(condition, body, line, column)
    }

    // The foreach-style `for item in collection` (and its missing-`in` recovery). The C-style
    // `for init; cond; iter` loop is a later arc stage; the Stage-6 corpus uses only the foreach form.
    // Stage N+1c tranche 10: the for-in arms wrap a `new ForeachStatement(varName, collection, body, line,
    // column)` in a `new ForStatement(null, null, null, <foreach>, line, column)` (Parser.cs :2678/:2691) —
    // BOTH nodes carry the `for` keyword's line/column. The C-style arm builds
    // `new ForStatement(initializer, condition, iterator, forBody, line, column)` (:2755).
    func ParseForStatement(): Statement? {
        forToken := Current()
        line := forToken.Line
        column := forToken.Column
        Advance()
        // consume 'for'

        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.In {
            loopVariable := Advance().Value
            // loop variable
            inToken := ConsumeToken(TokenType.In, "Expected 'in'", "in")
            collection := ParseRequiredExpressionAfter(inToken, "a collection expression", "This for-in statement", null)
            body := ParseStatement(SpanFromToken(forToken))
            if collection == null || body == null {
                return null
            }
            return new ForStatement(null, null, null, new ForeachStatement(loopVariable, collection, body, line, column), line, column)
        }

        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Identifier {
            variableToken := Current()
            Advance()
            // loop variable
            inToken := ReportMissingInKeywordAndRecover(forToken, variableToken, "This for-in statement")
            recoveredCollection := ParseRequiredExpressionAfter(inToken, "a collection expression", "This for-in statement", null)
            recoveredBody := ParseStatement(SpanFromToken(forToken))
            if recoveredCollection == null || recoveredBody == null {
                return null
            }
            return new ForStatement(null, null, null, new ForeachStatement(variableToken.Value, recoveredCollection, recoveredBody, line, column), line, column)
        }

        // C-style `for (init; cond; incr) { … }` (Parser.cs :2684). The parentheses are optional; the
        // two `;` separators are Consume sites and the optional `)` routes through the Stage-9 recovery.
        hasParens := false
        if Check(TokenType.LeftParen) {
            hasParens = true
            Advance()
        }
        // consume '('

        // Initializer (a `let` declaration, a `:=` shorthand, or a bare expression statement).
        initializerStatement: Statement? = null
        initializerDeclined := false
        if !Check(TokenType.Semicolon) {
            if Check(TokenType.Let) {
                initializerStatement = ParseVariableDeclaration()
                initializerDeclined = initializerStatement == null
            } else {
                initResult := ParseExprValue()
                if initResult.IsBareIdentifier && Check(TokenType.ColonAssign) {
                    initializerToken := Advance()
                    shorthandValue := ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This for-loop initializer", null)
                    // Parser.cs :2723 `new VariableDeclarationStatement(ident.Name, null, init,
                    // VariableKind.Let, ident.Line, ident.Column)` — anchored on the IDENTIFIER node.
                    shorthandTarget := initResult.Node as IdentifierExpression
                    if shorthandValue != null && shorthandTarget != null {
                        initializerStatement = new VariableDeclarationStatement(shorthandTarget.Name, null, shorthandValue, VariableKind.Let, shorthandTarget.Line, shorthandTarget.Column)
                    } else {
                        initializerDeclined = true
                    }
                } else {
                    // Parser.cs :2727 `new ExpressionStatement(expr, expr.Line, expr.Column)` — anchored on
                    // the EXPRESSION node, not the statement start.
                    initializerExpression := initResult.Node
                    if initializerExpression != null {
                        initializerStatement = new ExpressionStatement(initializerExpression, initializerExpression.Line, initializerExpression.Column)
                    } else {
                        initializerDeclined = true
                    }
                }
            }
        }

        ConsumeToken(TokenType.Semicolon, "Expected ';'", ";")

        condition: Expression? = null
        conditionDeclined := false
        if !Check(TokenType.Semicolon) {
            condition = ParseExprValue().Node
            // condition
            conditionDeclined = condition == null
        }

        ConsumeToken(TokenType.Semicolon, "Expected ';'", ";")

        // Iterator: stop at ')' when parenthesized, else at '{'.
        needIterator := false
        if hasParens {
            needIterator = !Check(TokenType.RightParen)
        } else {
            needIterator = !Check(TokenType.LeftBrace)
        }
        iterator: Expression? = null
        iteratorDeclined := false
        if needIterator {
            iterator = ParseExprValue().Node
            // iterator
            iteratorDeclined = iterator == null
        }

        if hasParens {
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        }

        forBody := ParseStatement(SpanFromToken(forToken))
        if initializerDeclined || conditionDeclined || iteratorDeclined || forBody == null {
            return null
        }
        return new ForStatement(initializerStatement, condition, iterator, forBody, line, column)
    }

    // Stage N+1c tranche 10: `new ForeachStatement(varName, collection, body, line, column)` (Parser.cs
    // :2784). The OPTIONAL parentheses `foreach (x in y)` (Parser.cs :2765/:2779) are now modelled too —
    // previously recorded as "a later arc stage"; they are a pure token-consumption branch that reaches
    // the standard Consume(')') recovery, so no corpus diagnostic moves.
    func ParseForeachStatement(): Statement? {
        foreachToken := Current()
        line := foreachToken.Line
        column := foreachToken.Column
        Advance()
        // consume 'foreach'
        hasParens := false
        if Check(TokenType.LeftParen) {
            Advance()
            // optional '('
            hasParens = true
        }
        variableToken := Current()
        variableName := ConsumeIdentifier("Expected variable name")
        inToken := ConsumeForeachInKeyword(foreachToken, variableToken)
        collection := ParseRequiredExpressionAfter(inToken, "a collection expression", "This foreach statement", null)
        if hasParens {
            ConsumeToken(TokenType.RightParen, "Expected ')' to match opening '('", ")")
        }
        body := ParseStatement(SpanFromToken(foreachToken))
        // An `<error>` loop-variable name is a RECOVERY ARTIFACT Parser.cs threads through verbatim
        // (:2784 constructs with whatever ConsumeIdentifier returned), so it is reproduced, not declined.
        if collection == null || body == null {
            return null
        }
        return new ForeachStatement(variableName, collection, body, line, column)
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
        expected := "in"
        // TokenTypeToString(In) = In.ToString().ToLower()
        suggestions := new List<string>()
        suggestions.Add("Add '" + expected + "' after '" + variableToken.Value + "'")
        Report(ErrorCode.ExpectedToken, "Expected '" + expected + "' between the loop variable and collection", loopKeywordToken.Line, loopKeywordToken.Column, ownerDescription + " needs the '" + expected + "' keyword between the loop variable and the collection.", "Write `" + loopKeywordToken.Value + " " + variableToken.Value + " " + expected + " ...`.", suggestions, MaxInt(1, loopKeywordToken.Value.Length))
        recoveredColumn := variableToken.Column + MaxInt(1, variableToken.Value.Length) + 1
        return new Token(TokenType.In, expected, variableToken.Line, recoveredColumn, variableToken.FileName)
    }

    // ---- return / print (Parser.cs :2821 / :2862) ----

    // Stage N+1c tranche 10: `new ReturnStatement(value, line, column)` (Parser.cs :2844) — a bare
    // `return` carries a materialized NULL value; a PRESENT value that declined declines the statement.
    func ParseReturnStatement(): Statement? {
        line := Current().Line
        column := Current().Column
        Advance()
        // consume 'return'
        if !Check(TokenType.RightBrace) && !IsAtEnd() && ParserTokenFacts.CanStartExpression(Current().Type) {
            value := ParseExprValue().Node
            if value == null {
                return null
            }
            return new ReturnStatement(value, line, column)
        }
        return new ReturnStatement(null, line, column)
    }

    // Stage N+1c tranche 10: `new PrintStatement(value, line, column)` (Parser.cs :2883).
    func ParsePrintStatement(): Statement? {
        printToken := Current()
        line := printToken.Line
        column := printToken.Column
        Advance()
        // consume 'print'
        value := ParseRequiredExpressionAfter(printToken, "an expression to print", "This print statement", null)
        if value == null {
            return null
        }
        return new PrintStatement(value, line, column)
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
    // Stage N+1c tranche 10: `new YieldStatement(value, line, column)` (Parser.cs :2870) — `yield break`
    // carries a materialized NULL value.
    func ParseYieldStatement(): Statement? {
        yieldToken := Current()
        line := yieldToken.Line
        column := yieldToken.Column
        Advance()
        // consume 'yield'
        if !Check(TokenType.Break) {
            value := ParseRequiredExpressionAfter(yieldToken, "a value to yield", "This yield statement", null)
            if value == null {
                return null
            }
            return new YieldStatement(value, line, column)
        }
        Advance()
        // consume 'break' (yield break)
        return new YieldStatement(null, line, column)
    }

    // ---- break / continue (Parser.cs :2885 / :2967) ----
    // The Consume(Break)/(Continue) never fires (the dispatch guards on the exact token); the
    // loop-context validity is a SEMANTIC check, not a parser one. Stage N+1c tranche 10:
    // `new BreakStatement(line, column)` (:2901) / `new ContinueStatement(line, column)` (:2983).
    func ParseBreakStatement(): Statement? {
        line := Current().Line
        column := Current().Column
        Advance()
        // consume 'break'
        return new BreakStatement(line, column)
    }

    func ParseContinueStatement(): Statement? {
        line := Current().Line
        column := Current().Column
        Advance()
        // consume 'continue'
        return new ContinueStatement(line, column)
    }

    // ---- throw (Parser.cs ParseThrowStatement :2975) ----
    // Stage N+1c tranche 10: `new ThrowStatement(expr, line, column)` (:2996).
    func ParseThrowStatement(): Statement? {
        throwToken := Current()
        line := throwToken.Line
        column := throwToken.Column
        Advance()
        // consume 'throw'
        thrown := ParseRequiredExpressionAfter(throwToken, "an exception expression", "This throw statement", null)
        if thrown == null {
            return null
        }
        return new ThrowStatement(thrown, line, column)
    }

    // ---- preprocessor directive (Parser.cs ParsePreprocessorDirective :2875) ----
    // The Consume(PreprocessorDirective) never fires (dispatched on the exact token); the directive
    // text carries no diagnostic. Stage N+1c tranche 10: `new PreprocessorDirective(directive, line,
    // column)` (:2893) over the directive token's raw text.
    func ParsePreprocessorDirective(): Statement? {
        line := Current().Line
        column := Current().Column
        directive := Current().Value
        Advance()
        // consume the directive
        return new PreprocessorDirective(directive, line, column)
    }

    // ---- await foreach (Parser.cs ParseAwaitForeachStatement :2776) ----
    // Stage N+1c tranche 10: `new AwaitForEachStatement(varName, collection, body, line, column)`
    // (Parser.cs :2814) — line/column are the `await` keyword's (captured before it is consumed).
    func ParseAwaitForeachStatement(): Statement? {
        line := Current().Line
        column := Current().Column
        Advance()
        // consume 'await'
        foreachToken := Current()
        Advance()
        // consume 'foreach'
        hasParens := false
        if Check(TokenType.LeftParen) {
            Advance()
            // optional '('
            hasParens = true
        }
        variableToken := Current()
        variableName := ConsumeIdentifier("Expected variable name")
        inToken := ConsumeInOrReportMissing(foreachToken, variableToken, "This await foreach statement")
        collection := ParseRequiredExpressionAfter(inToken, "a collection expression", "This await foreach statement", null)
        if hasParens {
            ConsumeToken(TokenType.RightParen, "Expected ')' to match opening '('", ")")
        }
        body := ParseStatement(SpanFromToken(foreachToken))
        // As for foreach: Parser.cs :2814 keeps an `<error>` loop-variable name verbatim.
        if collection == null || body == null {
            return null
        }
        return new AwaitForEachStatement(variableName, collection, body, line, column)
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
    // Stage N+1c tranche 10: `new UnsafeBlockStatement(body, line, column)` (Parser.cs :2396).
    func ParseUnsafeBlockStatement(): Statement? {
        line := Current().Line
        column := Current().Column
        unsafeToken := Current()
        Advance()
        // consume 'unsafe'
        body := ParseBlock(new RecoverySpan(line, column, MaxInt(1, unsafeToken.Value.Length)))
        if body == null {
            return null
        }
        return new UnsafeBlockStatement(body, line, column)
    }

    // ---- alloc block (Parser.cs ParseAllocBlockStatement :2301) — dispatched only when `alloc {` ----
    // Stage N+1c tranche 10: `new AllocBlockStatement(body, line, column)` (Parser.cs :2318).
    func ParseAllocBlockStatement(): Statement? {
        line := Current().Line
        column := Current().Column
        allocToken := Current()
        Advance()
        // consume 'alloc'
        body := ParseBlock(new RecoverySpan(line, column, MaxInt(1, allocToken.Value.Length)))
        if body == null {
            return null
        }
        return new AllocBlockStatement(body, line, column)
    }

    // ---- assert (Parser.cs ParseAssertStatement :2388) ----
    // `assert throws ExceptionType { … }` OR `assert <condition> [, <message>]`.
    // Stage N+1c tranche 10: `new AssertThrowsStatement(exceptionType, body, line, column)` (Parser.cs
    // :2411) / `new AssertStatement(condition, message, line, column)` (:2427). An ABSENT message is a
    // materialized null; a PRESENT-but-declined one declines the statement.
    func ParseAssertStatement(): Statement? {
        assertToken := Current()
        line := assertToken.Line
        column := assertToken.Column
        Advance()
        // consume 'assert'
        if Check(TokenType.Identifier) && Current().Value == "throws" {
            Advance()
            // consume 'throws'
            exceptionType := ParseMaterializedTypeReference()
            throwsBody := ParseBlock(SpanFromToken(assertToken))
            if exceptionType == null || throwsBody == null {
                return null
            }
            return new AssertThrowsStatement(exceptionType, throwsBody, line, column)
        }
        condition := ParseRequiredExpressionAfter(assertToken, "a condition expression", "This assert statement", null)
        message: Expression? = null
        messageDeclined := false
        if Check(TokenType.Comma) {
            Advance()
            // consume ','
            message = ParseExprValue().Node
            // the optional message expression
            messageDeclined = message == null
        }
        if condition == null || messageDeclined {
            return null
        }
        return new AssertStatement(condition, message, line, column)
    }

    // ---- lock (Parser.cs ParseLockStatement :3128) ----
    // `lock obj { … }` or `lock (obj) { … }`. The "Expected block statement after lock" report
    // (Parser.cs :3151) is UNREACHABLE — ParseBlock always yields a block, so the `bodyStmt == null`
    // guard is dead C#; it is intentionally not modelled.
    // Stage N+1c tranche 10: `new LockStatement(lockObject, bodyStmt, line, column)` (Parser.cs :3178).
    func ParseLockStatement(): Statement? {
        lockToken := Current()
        line := lockToken.Line
        column := lockToken.Column
        Advance()
        // consume 'lock'
        hasParens := Check(TokenType.LeftParen)
        expressionAnchor := lockToken
        if hasParens {
            expressionAnchor = ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
        }
        lockObject := ParseRequiredExpressionAfter(expressionAnchor, "an object expression", "This lock statement", null)
        if hasParens {
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        }
        body := ParseBlock(SpanFromToken(lockToken))
        if lockObject == null || body == null {
            return null
        }
        return new LockStatement(lockObject, body, line, column)
    }

    // ---- try / catch / finally (Parser.cs ParseTryStatement :2988) ----
    // Stage N+1c tranche 10: `new TryStatement(tryBlock, catchClauses, finallyBlock, line, column)`
    // (Parser.cs :3056) over `new CatchClause(exceptionType, varName, catchBlock)` (:3046). A catch's
    // exception type / variable name are both OPTIONAL (a bare `catch { }` carries nulls); only a
    // PRESENT-but-unmaterializable one declines.
    func ParseTryStatement(): Statement? {
        tryToken := Current()
        line := tryToken.Line
        column := tryToken.Column
        Advance()
        // consume 'try'
        tryBlock := ParseBlock(SpanFromToken(tryToken))
        declined := tryBlock == null
        catchClauses := new List<CatchClause>()
        while Check(TokenType.Catch) {
            catchToken := Advance()
            // consume 'catch'
            exceptionType: TypeReference? = null
            variableName: string? = null
            if Check(TokenType.LeftParen) {
                Advance()
                // consume '('
                if !Check(TokenType.RightParen) {
                    if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon {
                        variableName = Advance().Value
                        // catch variable name
                        Advance()
                        // consume ':'
                        exceptionType = ParseMaterializedTypeReference()
                        if exceptionType == null {
                            declined = true
                        }
                    } else {
                        exceptionType = ParseMaterializedTypeReference()
                        if exceptionType == null {
                            declined = true
                        }
                        if Check(TokenType.Identifier) {
                            variableName = Advance().Value
                        }
                    }
                }
                // catch variable name

                ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            } else {
                if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon {
                    variableName = Advance().Value
                    // catch variable name
                    Advance()
                    // consume ':'
                    exceptionType = ParseMaterializedTypeReference()
                    if exceptionType == null {
                        declined = true
                    }
                }
            }
            catchBlock := ParseBlock(SpanFromToken(catchToken))
            if catchBlock == null {
                declined = true
            } else {
                catchClauses.Add(new CatchClause(exceptionType, variableName, catchBlock))
            }
        }
        finallyBlock: BlockStatement? = null
        if Check(TokenType.Finally) {
            finallyToken := Advance()
            // consume 'finally'
            finallyBlock = ParseBlock(SpanFromToken(finallyToken))
            if finallyBlock == null {
                declined = true
            }
        }
        if declined || tryBlock == null {
            return null
        }
        return new TryStatement(tryBlock, catchClauses, finallyBlock, line, column)
    }

    // ---- using (Parser.cs ParseUsingStatement :3048) ----
    // `using let x := e { … }` / `using x := e { … }` / `using (e) { … }` / `using e { … }`. A
    // `using let (a, b) := …` tuple-deconstruction gets the InvalidSyntax NL103 anchored on the
    // single-line `(…)` pattern span.
    // Stage N+1c tranche 10: `new UsingStatement(decl, null, body, line, column)` (Parser.cs :3121) for the
    // declaration forms, `new UsingStatement(null, invalidUsingExpression, body, …)` (:3119) for the
    // rejected tuple-deconstruction form (whose Expression is the TUPLE's Initializer), and
    // `new UsingStatement(null, expr, usingBody, …)` (:3136) for the bare-resource form. The `let` arm's
    // `stmt as VariableDeclarationStatement` decision is reproduced through VariableDeclarationWasTuple
    // (read IMMEDIATELY after the call) so it stays correct even when the node itself declines.
    func ParseUsingStatement(): Statement? {
        usingToken := Current()
        line := usingToken.Line
        column := usingToken.Column
        Advance()
        // consume 'using'
        if Check(TokenType.Identifier) || Check(TokenType.Let) {
            declaration: VariableDeclarationStatement? = null
            invalidUsingExpression: Expression? = null
            declined := false
            wasTupleForm := false
            if Check(TokenType.Let) {
                spanResult := TryGetSingleLineDelimiterSpanAt(Position + 1, TokenType.LeftParen, TokenType.RightParen)
                declarationStatement := ParseVariableDeclaration()
                wasTuple := VariableDeclarationWasTuple
                wasTupleForm = wasTuple
                if wasTuple {
                    diagSpan := SpanFromToken(usingToken)
                    if spanResult.Found {
                        diagSpan = spanResult.Span
                    }
                    ReportUsingRequiresVariableDeclaration(diagSpan)
                    // Parser.cs :3097 hangs the tuple's INITIALIZER on the using statement's Expression.
                    tupleStatement := declarationStatement as TupleDeconstructionStatement
                    if tupleStatement == null {
                        declined = true
                    } else {
                        invalidUsingExpression = tupleStatement.Initializer
                    }
                } else {
                    declaration = declarationStatement as VariableDeclarationStatement
                    if declaration == null {
                        declined = true
                    }
                }
            } else {
                variableName := ConsumeIdentifier("Expected variable name")
                initializerToken := ConsumeToken(TokenType.ColonAssign, "Expected ':='", "colonassign")
                initializer := ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This using declaration", null)
                // Parser.cs :3109 anchors this synthesized declaration on the USING keyword's line/column.
                // Parser.cs :3109 keeps an `<error>` variable name verbatim.
                if initializer == null {
                    declined = true
                } else {
                    declaration = new VariableDeclarationStatement(variableName, null, initializer, VariableKind.Let, line, column)
                }
            }
            declarationBody: Statement? = null
            if Check(TokenType.LeftBrace) {
                declarationBody = ParseBlock(SpanFromToken(usingToken))
                if declarationBody == null {
                    declined = true
                }
            }
            if declined {
                return null
            }
            if wasTupleForm {
                return new UsingStatement(null, invalidUsingExpression, declarationBody, line, column)
            }
            return new UsingStatement(declaration, null, declarationBody, line, column)
        }
        resource := ParseRequiredExpressionAfter(usingToken, "a resource expression", "This using statement", null)
        usingBody: Statement? = null
        bodyDeclined := false
        if Check(TokenType.LeftBrace) {
            usingBody = ParseBlock(SpanFromToken(usingToken))
            bodyDeclined = usingBody == null
        }
        if resource == null || bodyDeclined {
            return null
        }
        return new UsingStatement(null, resource, usingBody, line, column)
    }

    func ReportUsingRequiresVariableDeclaration(span: RecoverySpan) {
        suggestions := new List<string>()
        suggestions.Add("Change from tuple deconstruction to single variable")
        suggestions.Add("Example: using let file := File.Open(path) { ... }")
        suggestions.Add("Note: The variable will be automatically disposed when the block ends")
        Report(ErrorCode.InvalidSyntax, "Using statement requires a variable declaration, not tuple deconstruction", span.Line, span.Column, "The 'using' statement can only work with single variable declarations, not tuple deconstruction.", "Use a single variable: using let resource := getResource() { ... }", suggestions, span.Length)
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
    // Stage N+1c tranche 10: `new SwitchStatement(value, cases, line, column)` (Parser.cs :3271) over
    // `new SwitchCase(pattern, statements, caseLine, caseColumn)` (:3250). A `case` carries its Pattern;
    // `default` carries a materialized NULL pattern. A BRACED case FLATTENS the block's statements into the
    // case's own list (Parser.cs :3243 `statements.AddRange(block.Statements)`), so the BlockStatement
    // wrapper does NOT appear in the tree; an unbraced case holds the single statement.
    func ParseSwitchStatement(): Statement? {
        switchLine := Current().Line
        switchColumn := Current().Column
        switchToken := Current()
        Advance()
        // consume 'switch'
        value := ParseRequiredExpressionAfter(switchToken, "a value expression", "This switch statement", null)
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")

        cases := new List<SwitchCase>()
        declined := value == null
        caseLoopActive := true
        while caseLoopActive && !Check(TokenType.RightBrace) && !IsAtEnd() {
            caseLine := Current().Line
            caseColumn := Current().Column
            caseDiagnosticSpan := new RecoverySpan(caseLine, caseColumn, MaxInt(1, Current().Value.Length))
            matchedLabel := false
            casePattern: Pattern? = null
            patternDeclined := false
            if Check(TokenType.Case) {
                Advance()
                // consume 'case'
                casePattern = ParsePattern()
                patternDeclined = casePattern == null
                matchedLabel = true
            } else {
                if Check(TokenType.Default) {
                    Advance()
                    // consume 'default'
                    matchedLabel = true
                } else {
                    ReportSwitchExpectedCaseOrDefault()
                    // Skip to the next case / default / '}' (Parser.cs :3218).
                    while !Check(TokenType.RightBrace) && !Check(TokenType.Case) && !Check(TokenType.Default) && !IsAtEnd() {
                        Advance()
                    }
                    if Check(TokenType.RightBrace) {
                        caseLoopActive = false
                    }
                }
            }
            // Parser.cs :3221 break

            // else: fall through with matchedLabel = false — Parser.cs :3223 continue

            if matchedLabel {
                ConsumeToken(TokenType.Arrow, "Expected '=>'", "arrow")
                caseStatements := new List<Statement>()
                if Check(TokenType.LeftBrace) {
                    caseBlock := ParseBlock(caseDiagnosticSpan)
                    if caseBlock == null {
                        declined = true
                    } else {
                        flattenIndex := 0
                        while flattenIndex < caseBlock.Statements.Count {
                            caseStatements.Add(caseBlock.Statements[flattenIndex])
                            flattenIndex = flattenIndex + 1
                        }
                    }
                } else {
                    caseStatement := ParseStatement(null)
                    if caseStatement == null {
                        declined = true
                    } else {
                        caseStatement.EndLine = TokenEndLine(Previous())
                        caseStatements.Add(caseStatement)
                    }
                }
                if patternDeclined {
                    declined = true
                } else {
                    cases.Add(new SwitchCase(casePattern, caseStatements, caseLine, caseColumn))
                }
            }
        }

        if Check(TokenType.RightBrace) {
            Advance()
        } else {
            ReportSwitchMissingClosingBrace(switchToken, switchLine)
        }
        if declined || value == null {
            return null
        }
        return new SwitchStatement(value, cases, switchLine, switchColumn)
    }

    func ReportSwitchExpectedCaseOrDefault() {
        suggestions := new List<string>()
        suggestions.Add("Add a case: case 1 => { ... }")
        suggestions.Add("Add a default: default => { ... }")
        suggestions.Add("Example: case > 0 => Console.WriteLine(\"positive\")")
        Report(ErrorCode.ExpectedToken, "Expected 'case' or 'default'. Got '" + Current().Value + "'", Current().Line, Current().Column, "Switch statements must contain 'case' patterns or a 'default' case.", "Each branch in a switch must start with 'case pattern =>' or 'default =>'", suggestions, Current().Value.Length)
    }

    // Parser.cs's switch-specific missing-'}' report (:3249) — DISTINCT from the block NL106 (its
    // message names the switch body and its line).
    func ReportSwitchMissingClosingBrace(switchToken: Token, switchLine: int) {
        span := SpanFromToken(switchToken)
        Report(ErrorCode.MissingClosingBrace, "Missing closing '}'", span.Line, span.Column, "The switch body that started on line " + IntToString(switchLine) + " is missing its closing brace. I reached the end of the file without finding it.", "Add a '}' to close this switch statement.", null, span.Length)
    }

    // ---- allow (Parser.cs ParseAllowStatement :2310) ----
    // `allow(effect, reason: "…", owner: "…") { … }`. The effect loop funnels every name through
    // ConsumeSystemsIdentifier and force-advances when a whole iteration made no progress
    // (Parser.cs's `if (Current == nameToken) Advance()`, modelled by the position guard).
    // Stage N+1c tranche 10: `new AllowStatement(effects, reason, owner, body, line, column)` (Parser.cs
    // :2370). `reason`/`owner` are the STRING-LITERAL value with its surrounding quotes stripped
    // (TryGetStringLiteralValue :6834 — null when the value is not a string literal); a plain effect is
    // the bare name and a `name: value` effect is `"name:value"` (:2351).
    func ParseAllowStatement(): Statement? {
        line := Current().Line
        column := Current().Column
        allowToken := Current()
        Advance()
        // consume 'allow'
        ConsumeToken(TokenType.LeftParen, "Expected '(' after 'allow'", "(")
        effects := new List<string>()
        reason: string? = null
        owner: string? = null
        declined := false
        while !Check(TokenType.RightParen) && !IsAtEnd() {
            loopStartPosition := Position
            name := ConsumeSystemsIdentifier("Expected allow effect or named argument")
            if Check(TokenType.Colon) {
                Advance()
                // consume ':'
                // `reason`/`owner` take a string expression; every other effect takes an effect value.
                // Both parse a diagnostic-free value for the corpus, so the OrdinalIgnoreCase in
                // Parser.cs is byte-exact here with a plain compare.
                if name == "reason" {
                    reasonValue := ParseExprValue().Node
                    if reasonValue == null {
                        declined = true
                    } else {
                        reason = TryGetStringLiteralValue(reasonValue)
                    }
                } else {
                    if name == "owner" {
                        ownerValue := ParseExprValue().Node
                        if ownerValue == null {
                            declined = true
                        } else {
                            owner = TryGetStringLiteralValue(ownerValue)
                        }
                    } else {
                        effectValue := ParseAllowEffectValue()
                        if effectValue == null {
                            declined = true
                        } else {
                            effects.Add(name + ":" + effectValue)
                        }
                    }
                }
            } else {
                effects.Add(name)
            }
            if !Check(TokenType.RightParen) {
                ConsumeToken(TokenType.Comma, "Expected ',' between allow arguments", ",")
            }
            if Position == loopStartPosition {
                if !IsAtEnd() {
                    Advance()
                }
            }
        }
        // force progress (Parser.cs :2351)

        ConsumeToken(TokenType.RightParen, "Expected ')' after allow arguments", ")")
        body := ParseBlock(new RecoverySpan(line, column, MaxInt(1, allowToken.Value.Length)))
        if declined || body == null {
            return null
        }
        return new AllowStatement(effects, reason, owner, body, line, column)
    }

    // Parser.cs TryGetStringLiteralValue (:6834): the string literal's value with its surrounding double
    // quotes stripped; null for any other expression node.
    func TryGetStringLiteralValue(expression: Expression): string? {
        literal := expression as StringLiteralExpression
        if literal == null {
            return null
        }
        value := literal.Value
        if value.Length >= 2 && value[0] == '"' && value[value.Length - 1] == '"' {
            return value.Substring(1, value.Length - 2)
        }
        return value
    }

    // Parser.cs FormatAllowValue (:6846): an identifier's Name, a string literal's unquoted value, else the
    // node's type name with the "Expression" suffix removed.
    func FormatAllowValue(expression: Expression): string {
        identifier := expression as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }
        literal := expression as StringLiteralExpression
        if literal != null {
            return TryGetStringLiteralValue(literal) ?? literal.Value
        }
        // The `GetType()` receiver is cast to `object` first — the columnar backend declines a
        // `GetType()` call on a typed receiver (the recorded emitter gap).
        boxed := expression as object
        typeName := boxed.GetType().Name
        return typeName.Replace("Expression", "")
    }

    // Parser.cs ConsumeSystemsIdentifier (:6786): an effect name (identifier or an alloc-family
    // keyword) or the NL102 "Expected allow effect or named argument" report.
    func ConsumeSystemsIdentifier(message: string): string {
        if IsSystemsIdentifierToken() {
            return Advance().Value
        }
        Report(ErrorCode.ExpectedToken, message + ". Got '" + Current().Value + "'", Current().Line, Current().Column, "Systems policy lists use effect names such as alloc, trap, dispatch, delegate, closure, or a named argument such as reason.", "Write allow(alloc, reason: \"...\") { ... } or remove this allow block.", null, TokenLengthOrFallback(Current()))
        return "<error>"
    }

    // Parser.cs ParseAllowEffectValue (:2362): a bare effect name or a general expression value.
    // Stage N+1c tranche 10: RETURNS the effect-value string (null when the expression declined).
    func ParseAllowEffectValue(): string? {
        if IsSystemsIdentifierToken() {
            return Advance().Value
        }
        effectExpression := ParseExprValue().Node
        if effectExpression == null {
            return null
        }
        return FormatAllowValue(effectExpression)
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
    // Stage N+1c tranche 10b: RETURNS `new LocalFunctionStatement(functionDecl, line, column)`
    // (Parser.cs :2539) over the local function's OWN `new FunctionDeclaration(name, parameters,
    // returnType, body, expressionBody, typeParams, constraints, modifiers, new List<AttributeNode>(),
    // false, null, false, false, line, column) { ReturnLifetime = … }` (:2533) — never an operator or a
    // conversion, and always attribute-free. The no-body arm builds a SYNTHETIC empty BlockStatement
    // (:2530), so it declines no-stub.
    func ParseLocalFunction(): Statement? {
        line := Current().Line
        column := Current().Column
        modifierValue := 0
        scanningModifiers := true
        while scanningModifiers {
            if Check(TokenType.Static) {
                modifierValue = modifierValue | 16
                // Modifiers.Static
                Advance()
            } else {
                if Check(TokenType.Async) {
                    modifierValue = modifierValue | 2048
                    // Modifiers.Async
                    Advance()
                } else {
                    scanningModifiers = false
                }
            }
        }
        ConsumeToken(TokenType.Func, "Expected 'func'", "func")
        if Check(TokenType.Star) {
            modifierValue = modifierValue | 4096
            // Modifiers.Generator
            Advance()
        }
        // generator func*

        nameLine := Current().Line
        nameColumn := Current().Column
        name := ConsumeIdentifier("Expected function name")
        declined := false
        typeParameters := ParseTypeParameters()
        parameters := ParseParameterListRecovery()
        if !ParamListMaterializable {
            declined = true
        }
        parameterListEndToken := Previous()
        returnType: TypeReference? = null
        if Check(TokenType.Colon) || (Check(TokenType.Minus) && LookAhead(1).Type == TokenType.Greater) {
            if Check(TokenType.Colon) {
                Advance()
            } else {
                Advance()
                // consume '-'
                ConsumeToken(TokenType.Greater, "Expected '>' after '-' in return type arrow", "greater")
            }
            returnType = ParseMaterializedTypeReference()
            if returnType == null {
                declined = true
            }
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
                    markerLength = MaxInt(1, 4)
                }
                // "func".Length

                ReportMissingReturnTypeMarker(markerName, markerLine, markerColumn, markerLength)
                returnType = ParseMaterializedTypeReference()
                if returnType == null {
                    declined = true
                }
            }
        }
        ParseReturnLifetimeAnnotation()
        returnLifetime := ReturnLifetimeValue
        constraints := ParseGenericConstraints()
        if !ConstraintsMaterializable {
            declined = true
        }
        body: BlockStatement? = null
        expressionBody: Expression? = null
        if Check(TokenType.Arrow) {
            Advance()
            // consume '=>'
            expressionBody = ParseExprValue().Node
            // expression body
            if expressionBody == null {
                declined = true
            }
        } else {
            if Check(TokenType.LeftBrace) {
                bodySpan := new RecoverySpan(nameLine, nameColumn, MaxInt(1, name.Length))
                if name == "<error>" {
                    bodySpan = new RecoverySpan(line, column, MaxInt(1, 4))
                }
                body = ParseBlock(bodySpan)
                if body == null {
                    declined = true
                }
            } else {
                // Stage N+1c tranche 11: Parser.cs substitutes a SYNTHETIC EMPTY BlockStatement anchored on
                // the offending token (:2530) — read AFTER the report, which does not advance.
                ReportLocalFunctionMissingBody()
                body = new BlockStatement(new List<Statement>(), Current().Line, Current().Column)
            }
        }
        if declined {
            return null
        }
        localFunction := new NSharpLang.Compiler.Ast.FunctionDeclaration(name, parameters, returnType, body, expressionBody, typeParameters, constraints, (Modifiers)modifierValue, new List<AttributeNode>(), false, null, false, false, line, column)
        localFunction.ReturnLifetime = returnLifetime
        return new LocalFunctionStatement(localFunction, line, column)
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
        Report(ErrorCode.ExpectedToken, "Expected ':' before return type. Got '" + Current().Value + "'", declarationLine, declarationColumn, "Function '" + declarationName + "' needs a ':' before its return type.", "Write the return type as `func name(...): Type { ... }`.", suggestions, MaxInt(1, declarationLength))
    }

    // Parser.cs ParseLocalFunction's no-body report (:2504).
    func ReportLocalFunctionMissingBody() {
        suggestions := new List<string>()
        suggestions.Add("Add a block: { return value; }")
        suggestions.Add("Use arrow syntax: => value")
        suggestions.Add("Example: func add(x: int, y: int): int => x + y")
        Report(ErrorCode.ExpectedToken, "Expected function body or '=>' for expression-bodied function. Got '" + Current().Value + "'", Current().Line, Current().Column, "A function needs a body - either a block with braces { } or an expression after '=>'.", "Use '{ ... }' for a block body or '=> expression' for a single expression.", suggestions, Current().Value.Length)
    }

    // Parser.cs ParseReturnLifetimeAnnotation (:511): the optional Systems `returns 'a` /
    // `returns local|static|unknown` / `returns param(name)` / `returns heap(owner)` annotation.
    // Guarded by the contextual `returns` identifier, so a non-Systems function never reaches it.
    // Stage N+1c tranche 10b: records the parsed lifetime STRING (Parser.cs returns it) in
    // ReturnLifetimeValue. Tranche 11 retired the companion gate — the terminal error arm reports and
    // returns a NULL lifetime (:517), and an `<error>` owner name is interpolated verbatim (:510).
    func ParseReturnLifetimeAnnotation() {
        ReturnLifetimeValue = null
        if !(Check(TokenType.Identifier) && Current().Value == "returns") {
            return
        }
        Advance()
        // consume 'returns'
        if Check(TokenType.Lifetime) {
            ReturnLifetimeValue = Advance().Value
            return
        }
        if Check(TokenType.Identifier) {
            kind := Advance().Value
            if kind == "local" || kind == "static" || kind == "unknown" {
                ReturnLifetimeValue = kind
                return
            }
            if kind == "param" || kind == "heap" {
                ConsumeToken(TokenType.LeftParen, "Expected '(' after returns " + kind, "(")
                owner := ConsumeIdentifier("Expected owner name inside returns " + kind + "(...)")
                ConsumeToken(TokenType.RightParen, "Expected ')' after returns " + kind + "(" + owner + ")", ")")
                // Stage N+1c tranche 11: Parser.cs interpolates whatever ConsumeIdentifier returned, an
                // `<error>` owner included (:510).
                ReturnLifetimeValue = kind + "(" + owner + ")"
                return
            }
        }
        // Stage N+1c tranche 11: the terminal arm reports and returns a NULL lifetime (:517) — the
        // declaration still materializes with ReturnLifetime null.
        Report(ErrorCode.ExpectedToken, "Expected lifetime label after 'returns'. Got '" + Current().Value + "'", Current().Line, Current().Column, "Systems lifetime annotations use `returns 'a`, `returns param(name)`, or `returns heap(owner)` to describe a ref-like return.", "Write a lifetime such as `returns 'a`, `returns heap(owner)`, or remove the `returns` annotation.", null, TokenLengthOrFallback(Current()))
    }

    // ---- off (Parser.cs ParseOffStatement :2957) ----
    // The contextual `off handle` unsubscription: just parses the handle expression.
    func IsOffStatementStart(): bool {
        return Current().Type == TokenType.Identifier && Current().Value == "off" && LookAhead(1).Type == TokenType.Identifier
    }

    // Stage N+1c tranche 10: `new OffStatement(handle, line, column)` (Parser.cs :2975).
    func ParseOffStatement(): Statement? {
        line := Current().Line
        column := Current().Column
        Advance()
        // consume contextual 'off'
        handle := ParseExprValue().Node
        // the handle expression
        if handle == null {
            return null
        }
        return new OffStatement(handle, line, column)
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

    // Stage N+1c tranche 10: `new OnSubscriptionExpression(target, handler, line, column)` (Parser.cs
    // :2917) — reachable now that the BLOCK-bodied lambda materializes. Tranche 11 adds the RECOVERY arm
    // (:2930): when the handler is not a lambda, Parser.cs substitutes a SYNTHETIC empty-parameter lambda
    // over an EMPTY BlockStatement, both anchored on the PARSED handler expression's own Line/Column.
    func ParseOnSubscription(): ExprResult {
        onLine := Current().Line
        onColumn := Current().Column
        Advance()
        // consume contextual 'on'
        target := ParseEventTarget()

        // The handler position + whether it is a lambda (Parser.cs parses then checks
        // `is LambdaExpression`; a lambda is exactly one of the two ParseExprValue lambda prefixes).
        handlerLine := Current().Line
        handlerColumn := Current().Column
        handlerIsLambda := IsLambdaExpression() || (Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Arrow)
        handlerNode := ParseExprValue().Node
        // the handler (ParseLambdaOrAssignmentExpression)
        if !handlerIsLambda {
            // Parser.cs anchors this report on the PARSED handler expression's OWN Line/Column
            // (:2926-2929), which is not the handler's first token for every node shape — a binary
            // expression, for instance, anchors on its OPERATOR. Fall back to the pre-parse token
            // position only when nothing materialized.
            if handlerNode != null {
                ReportExpectedEventHandlerLambda(handlerNode.Line, handlerNode.Column)
            } else {
                ReportExpectedEventHandlerLambda(handlerLine, handlerColumn)
            }
        }
        onResult := new ExprResult(new RecoverySpan(onLine, onColumn, 1), false)
        handlerLambda := handlerNode as LambdaExpression
        if handlerIsLambda && target != null && handlerLambda != null {
            onResult.Node = new OnSubscriptionExpression(target, handlerLambda, onLine, onColumn)
        } else {
            if !handlerIsLambda && target != null && handlerNode != null {
                recoveryBody := new BlockStatement(new List<Statement>(), handlerNode.Line, handlerNode.Column)
                recoveryHandler := new LambdaExpression(new List<Parameter>(), null, recoveryBody, handlerNode.Line, handlerNode.Column)
                onResult.Node = new OnSubscriptionExpression(target, recoveryHandler, onLine, onColumn)
            }
        }
        return onResult
    }

    // Parser.cs ParseEventTarget (:2927): a primary + member-access (and index) chain only, stopping
    // before a `(` so the handler lambda's parameter list is not consumed as a call. Stage N+1c tranche
    // 10 RETURNS the chain's node (`new MemberAccessExpression(...)` :2949 / `new IndexAccessExpression(...)`
    // :2957), or null when a link declined.
    func ParseEventTarget(): Expression? {
        target := ParsePrimaryExprValue().Node
        scanning := true
        while scanning {
            if Check(TokenType.Dot) || Check(TokenType.QuestionDot) {
                isNullConditional := Check(TokenType.QuestionDot)
                dotToken := Advance()
                // consume '.' / '?.'
                memberName := ConsumeIdentifier("Expected event or member name after '.'")
                // Stage N+1c tranche 11: an `<error>` member name is Parser.cs's own placeholder.
                if target == null {
                    target = null
                } else {
                    target = new MemberAccessExpression(target, memberName, isNullConditional, dotToken.Line, dotToken.Column)
                }
            } else {
                if Check(TokenType.LeftBracket) || Check(TokenType.QuestionBracket) {
                    isNullConditionalIndex := Check(TokenType.QuestionBracket)
                    bracketToken := Advance()
                    // consume '[' / '?['
                    indexNode := ParseExprValue().Node
                    // the index
                    ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
                    if target == null || indexNode == null {
                        target = null
                    } else {
                        target = new IndexAccessExpression(target, indexNode, isNullConditionalIndex, bracketToken.Line, bracketToken.Column)
                    }
                } else {
                    scanning = false
                }
            }
        }
        return target
    }

    func ReportExpectedEventHandlerLambda(handlerLine: int, handlerColumn: int) {
        Report(ErrorCode.InvalidSyntax, "Expected an event handler lambda after the event", handlerLine, handlerColumn, "`on` subscribes a handler to a .NET event, so it needs a lambda to run when the event fires.", "Write the handler inline, e.g. `on widget.Clicked (sender, args) => { ... }`.", null, 1)
    }

    // ---- expression statement (Parser.cs ParseExpressionStatement :3498) ----
    // Parses the typed-declaration (`name: T = value`) and tuple-deconstruction (paren / no-paren)
    // forms (Stage 13), otherwise the statement's expression, then the `identifier :=` shorthand
    // declaration (Parser.cs :3621, `expr is IdentifierExpression && Check(ColonAssign)`).
    // Stage N+1c tranche 10: every arm RETURNS its byte-exact node — the typed declaration
    // (`new VariableDeclarationStatement(name, typeRef, initializer, VariableKind.Let, line, column)`,
    // Parser.cs :3535), the two tuple-deconstruction forms (:3583 / :3625), the `identifier :=`
    // shorthand (`… ident.Line, ident.Column`, :3640) and the plain
    // `new ExpressionStatement(expr, line, column)` (:3643 — anchored on the STATEMENT start, unlike the
    // for-initializer's expression-anchored one).
    func ParseExpressionStatement(): Statement? {
        line := Current().Line
        column := Current().Column

        // Typed variable declaration without `let` (Parser.cs :3507): `name: Type = value`. Speculative —
        // if the `= value` is absent, rewind and parse as a normal expression statement.
        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon && LookAhead(2).Type == TokenType.Identifier {
            saved := Position
            name := Advance().Value
            // the declared name
            Advance()
            // consume ':'
            declaredType := ParseMaterializedTypeReference()
            // the type
            if Check(TokenType.Assign) {
                Advance()
                // consume '='
                typedInitializer := ParseRequiredExpressionAfter(Previous(), "an initializer expression", "This typed variable declaration", new RecoverySpan(line, column, MaxInt(1, name.Length)))
                if declaredType == null || typedInitializer == null {
                    return null
                }
                return new VariableDeclarationStatement(name, declaredType, typedInitializer, VariableKind.Let, line, column)
            }
            Position = saved
        }
        // not a declaration — rewind

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
                names := new List<string>()
                namesScanning := true
                while namesScanning {
                    // Parser.cs :3573 adds EVERY name, `<error>` placeholders included.
                    names.Add(ConsumeIdentifier("Expected identifier or '_'"))
                    if Check(TokenType.Comma) {
                        Advance()
                    } else {
                        namesScanning = false
                    }
                }
                initializerToken := Advance()
                // consume := or =
                tupleInitializer := ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This tuple deconstruction", new RecoverySpan(line, column, MaxInt(1, initializerToken.Column - column)))
                if tupleInitializer == null {
                    return null
                }
                return new TupleDeconstructionStatement(names, tupleInitializer, VariableKind.Let, line, column)
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
                return ParseTupleDeconstruction(VariableKind.Let, line, column)
            }
        }

        result := ParseExprValue()
        if result.IsBareIdentifier {
            if Check(TokenType.ColonAssign) {
                initializerToken := Advance()
                shorthandValue := ParseRequiredExpressionAfter(initializerToken, "an initializer expression", "This shorthand variable declaration", result.Span)
                // Parser.cs :3640: anchored on the IDENTIFIER expression, not the statement start.
                shorthandTarget := result.Node as IdentifierExpression
                if shorthandValue == null || shorthandTarget == null {
                    return null
                }
                return new VariableDeclarationStatement(shorthandTarget.Name, null, shorthandValue, VariableKind.Let, shorthandTarget.Line, shorthandTarget.Column)
            }
        }
        statementExpression := result.Node
        if statementExpression == null {
            return null
        }
        return new ExpressionStatement(statementExpression, line, column)
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
            paramToken := Advance()
            // the parameter name
            arrowToken := Advance()
            // consume '=>'
            lambdaBody: Expression? = null
            lambdaBlockBody: BlockStatement? = null
            hasBlockBody := false
            if Check(TokenType.LeftBrace) {
                hasBlockBody = true
                lambdaBlockBody = ParseBlockBody(new RecoverySpan(paramToken.Line, paramToken.Column, MaxInt(1, paramToken.Value.Length)))
            } else {
                lambdaBody = ParseRequiredExpressionAfter(arrowToken, "a lambda body expression", "This lambda expression", DiagnosticSpanFromTokenRange(paramToken, arrowToken))
            }
            lambdaResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9c: `new LambdaExpression(new List<Parameter> { new Parameter(param,
            // new SimpleTypeReference("var"), null, false, Line: paramLine, Column: paramColumn) }, exprBody,
            // null, line, column)` (Parser.cs :3686). The implicit parameter type is a POSITION-FREE
            // `SimpleTypeReference("var")` (Line/Column 0, invalid Span). Stage N+1c tranche 10 RETIRES the
            // block-bodied decline: a `{ … }` body now materializes the BlockStatement into
            // `new LambdaExpression(parameters, null, blockBody, line, column)` (Parser.cs :3665).
            if hasBlockBody {
                if lambdaBlockBody != null {
                    lambdaResult.Node = new LambdaExpression(SingleImplicitLambdaParameter(paramToken.Value, paramToken.Line, paramToken.Column), null, lambdaBlockBody, line, column)
                }
            } else {
                if lambdaBody != null {
                    lambdaResult.Node = new LambdaExpression(SingleImplicitLambdaParameter(paramToken.Value, paramToken.Line, paramToken.Column), lambdaBody, null, line, column)
                }
            }
            return lambdaResult
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
            op := AssignmentOpFor(opToken.Type)
            // Parser.cs's operand is ParseLambdaOrAssignmentExpression (right-associative); the fallback
            // span is the left expression's DiagnosticSpanFromExpression span (Parser.cs :3740).
            valueNode := RightOperandMissingWithSpan(opToken, left.Span)
            if valueNode == null {
                valueNode = ParseExprValue().Node
            }
            // The result is an AssignmentExpression; DiagnosticSpanFromExpression of one falls through
            // to the (line, column, 1) default at the operator position, and it is never a bare identifier.
            assignResult := new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            // Stage N+1c tranche 8: `new AssignmentExpression(target, op, value, opToken.Line, opToken.Column)`
            // (Parser.cs :3752) when the target and value both materialized.
            if left.Node != null && valueNode != null {
                assignResult.Node = new AssignmentExpression(left.Node, op, valueNode, opToken.Line, opToken.Column)
            }
            return assignResult
        }

        return left
    }

    // Parser.cs's implicit lambda parameter (:3676/:3687/:5520): `new Parameter(name, new
    // SimpleTypeReference("var"), null, false, Line: paramLine, Column: paramColumn)` — the type carries NO
    // position (Line/Column 0, invalid Span) because the ctor's defaults are used.
    func ImplicitLambdaParameter(name: string, line: int, column: int): Parameter {
        return new Parameter(name, new SimpleTypeReference("var", 0, 0), null, false, ParameterModifier.None, null, line, column, false, null)
    }

    func SingleImplicitLambdaParameter(name: string, line: int, column: int): List<Parameter> {
        parameters := new List<Parameter>()
        parameters.Add(ImplicitLambdaParameter(name, line, column))
        return parameters
    }

    // Parser.cs :3710-3726: the assignment-operator token → AssignmentOperator mapping. Default Assign mirrors
    // the invalid-assignment-operator fallback (:3743, an unreachable dead arm the guard never admits).
    func AssignmentOpFor(tokenType: TokenType): AssignmentOperator {
        if tokenType == TokenType.PlusAssign {
            return AssignmentOperator.AddAssign
        }
        if tokenType == TokenType.MinusAssign {
            return AssignmentOperator.SubtractAssign
        }
        if tokenType == TokenType.StarAssign {
            return AssignmentOperator.MultiplyAssign
        }
        if tokenType == TokenType.SlashAssign {
            return AssignmentOperator.DivideAssign
        }
        if tokenType == TokenType.QuestionQuestionAssign {
            return AssignmentOperator.NullCoalesceAssign
        }
        return AssignmentOperator.Assign
    }

    // Parser.cs IsLambdaExpression (:5535): a bounded lookahead over `( ident (, ident)* ) =>` (or the empty
    // `() =>`), returning true only when the parenthesized list is a well-formed lambda parameter list. A pure
    // token scan (no cursor mutation), the IsGenericMethodCall idiom. Because this admits ONLY a well-formed
    // parameter list, ParseMultiParameterLambda's ConsumeIdentifier / Consume(RightParen) / Consume(Arrow)
    // sites never report — the reachable error is only the missing lambda body.
    func IsLambdaExpression(): bool {
        pos := Position + 1
        // skip the '(' at Current
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
        lambdaParameters := new List<Parameter>()
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
                // Parser.cs :5520 `new Parameter(paramName, new SimpleTypeReference("var"), null, false,
                // Line: paramLine, Column: paramColumn)` — unconditional, an `<error>` name included.
                lambdaParameters.Add(ImplicitLambdaParameter(name, paramToken.Line, paramToken.Column))
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    paramLooping = false
                }
            }
        }

        ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        arrowToken := ConsumeToken(TokenType.Arrow, "Expected '=>'", "arrow")

        multiLambdaBody: Expression? = null
        multiLambdaBlockBody: BlockStatement? = null
        hasMultiBlockBody := false
        if Check(TokenType.LeftBrace) {
            // Parser.cs :5518: the block owner span is the first parameter's name (guaranteed valid here).
            hasMultiBlockBody = true
            lambdaSpan := new RecoverySpan(line, column, 1)
            if hasFirstParam {
                lambdaSpan = new RecoverySpan(firstParamLine, firstParamColumn, firstParamLength)
            }
            multiLambdaBlockBody = ParseBlockBody(lambdaSpan)
        } else {
            multiLambdaBody = ParseRequiredExpressionAfter(arrowToken, "a lambda body expression", "This lambda expression", DiagnosticSpanFromTokenRange(leftParenToken, arrowToken))
        }
        multiLambdaResult := new ExprResult(new RecoverySpan(line, column, 1), false)
        // Stage N+1c tranche 9c: `new LambdaExpression(parameters, exprBody, null, line, column)` (:5542),
        // anchored on the opening `(`. Stage N+1c tranche 10 adds the BLOCK-bodied form
        // `new LambdaExpression(parameters, null, body, line, column)` (:5533).
        if hasMultiBlockBody {
            if multiLambdaBlockBody != null {
                multiLambdaResult.Node = new LambdaExpression(lambdaParameters, null, multiLambdaBlockBody, line, column)
            }
        } else {
            if multiLambdaBody != null {
                multiLambdaResult.Node = new LambdaExpression(lambdaParameters, multiLambdaBody, null, line, column)
            }
        }
        return multiLambdaResult
    }

    // ---- ternary (Parser.cs ParseTernaryExpression :4009) ----
    func ParseTernary(): ExprResult {
        expr := ParseNullCoalescing()
        if Check(TokenType.Question) {
            questionToken := Advance()
            thenNode := ParseRequiredExpressionAfter(questionToken, "a then expression", "This ternary expression", DiagnosticSpanFromExpressionThroughToken(expr.Span, questionToken))
            colonToken := ConsumeToken(TokenType.Colon, "Expected ':' in ternary expression", ":")
            elseNode := ParseRequiredExpressionAfter(colonToken, "an else expression", "This ternary expression", DiagnosticSpanFromExpressionThroughToken(expr.Span, colonToken))
            // A TernaryExpression is anchored on the `?` token and is never a bare identifier.
            ternaryResult := new ExprResult(new RecoverySpan(questionToken.Line, questionToken.Column, 1), false)
            // Stage N+1c tranche 8: `new TernaryExpression(cond, then, else, questionToken.Line,
            // questionToken.Column)` (Parser.cs :4038) when the condition + both branches materialized.
            if expr.Node != null && thenNode != null && elseNode != null {
                ternaryResult.Node = new TernaryExpression(expr.Node, thenNode, elseNode, questionToken.Line, questionToken.Column)
            }
            return ternaryResult
        }
        return expr
    }

    // ---- the left-associative binary tiers (each mirrors one Parser.cs Parse*Expression) ----
    // Every tier accumulates its result span as the operator-position (line, column, 1) default that
    // DiagnosticSpanFromExpression yields for a BinaryExpression, so the through-token span of a following
    // dangling operator is computed byte-exact from the accumulated left expression.
    //
    // Stage N+1c tranche 8 (COMPOSED OPERATOR TIERS): each tier now MATERIALIZES its byte-exact
    // `new BinaryExpression(left, op, right, opToken.Line, opToken.Column)` (Parser.cs :4052/:4066/:4080/:4094/
    // :4108/:4122/:4137/:4209/:4225/:4240/:4285) as a PURE side-effect — the leaf node the left operand carried
    // (result.Node) composes with the right operand's node ONLY when BOTH are non-null (ComposeBinary), so a
    // deferred/missing operand leaves Node null → the whole expression declines (the established no-stub gate).
    // A left-associative chain nests naturally: iteration N's BinaryExpression becomes iteration N+1's left node.
    // The BinaryExpression is anchored on the OPERATOR token (opToken.Line/Column), NOT the left operand.

    // Compose a byte-exact BinaryExpression when both operands materialized, else null (decline). Parser.cs
    // always builds the node (with a synthetic error right operand when missing); the owner declines on a
    // missing/deferred operand rather than reconstruct a non-byte-exact stub.
    func ComposeBinary(leftNode: Expression?, op: BinaryOperator, rightNode: Expression?, opToken: Token): Expression? {
        if leftNode != null && rightNode != null {
            return new BinaryExpression(leftNode, op, rightNode, opToken.Line, opToken.Column)
        }
        return null
    }

    func ParseNullCoalescing(): ExprResult {
        result := ParseLogicalOr()
        while Check(TokenType.QuestionQuestion) {
            opToken := Advance()
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseLogicalOr().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, BinaryOperator.NullCoalesce, rightNode, opToken)
        }
        return result
    }

    func ParseLogicalOr(): ExprResult {
        result := ParseLogicalAnd()
        while Check(TokenType.Or) {
            opToken := Advance()
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseLogicalAnd().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, BinaryOperator.Or, rightNode, opToken)
        }
        return result
    }

    func ParseLogicalAnd(): ExprResult {
        result := ParseBitwiseOr()
        while Check(TokenType.And) {
            opToken := Advance()
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseBitwiseOr().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, BinaryOperator.And, rightNode, opToken)
        }
        return result
    }

    func ParseBitwiseOr(): ExprResult {
        result := ParseBitwiseXor()
        while Check(TokenType.BitwiseOr) {
            opToken := Advance()
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseBitwiseXor().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, BinaryOperator.BitwiseOr, rightNode, opToken)
        }
        return result
    }

    func ParseBitwiseXor(): ExprResult {
        result := ParseBitwiseAnd()
        while Check(TokenType.BitwiseXor) {
            opToken := Advance()
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseBitwiseAnd().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, BinaryOperator.BitwiseXor, rightNode, opToken)
        }
        return result
    }

    func ParseBitwiseAnd(): ExprResult {
        result := ParseEquality()
        while Check(TokenType.BitwiseAnd) {
            opToken := Advance()
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseEquality().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, BinaryOperator.BitwiseAnd, rightNode, opToken)
        }
        return result
    }

    func ParseEquality(): ExprResult {
        result := ParseRelational()
        while Check(TokenType.Equal) || Check(TokenType.NotEqual) {
            opToken := Advance()
            // Parser.cs :4134: Equal token → Equal, else NotEqual.
            op := BinaryOperator.Equal
            if opToken.Type == TokenType.NotEqual {
                op = BinaryOperator.NotEqual
            }
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseRelational().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, op, rightNode, opToken)
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
                leftNode := result.Node
                typeNode := ParseMaterializedTypeReference()
                varName: string? = null
                // The pattern variable must sit on the SAME line as the end of the type: statements are
                // newline-terminated, so an identifier opening the next line starts a new statement.
                // (Parser.cs :4157 had no line gate and swallowed it — `flag := x is string` followed by
                // `other := 42` consumed `other` as the pattern variable and orphaned the `:=`.)
                if Check(TokenType.Identifier) && Current().Line == Previous().Line {
                    varName = Advance().Value
                }
                result = new ExprResult(new RecoverySpan(isToken.Line, isToken.Column, 1), false)
                // Stage N+1c tranche 9a: `new IsExpression(expr, type, varName, isToken.Line, isToken.Column)`
                // (Parser.cs :4162) when the receiver + type both materialized (a deferred receiver or a
                // structurally-unbuildable / multi-line type declines — no-stub).
                if leftNode != null && typeNode != null {
                    result.Node = new IsExpression(leftNode, typeNode, varName, isToken.Line, isToken.Column)
                }
            } else {
                if Check(TokenType.As) {
                    // `expr as Type` (Parser.cs :4153). A safe-cast CastExpression is anchored on the `as`
                    // token, so its DiagnosticSpanFromExpression falls to the (asLine, asColumn, 1) default.
                    asToken := Advance()
                    leftNode := result.Node
                    typeNode := ParseMaterializedTypeReference()
                    result = new ExprResult(new RecoverySpan(asToken.Line, asToken.Column, 1), false)
                    // Stage N+1c tranche 9a: `new CastExpression(expr, type, CastKind.Safe, asToken.Line,
                    // asToken.Column)` (Parser.cs :4168) when the receiver + type both materialized.
                    if leftNode != null && typeNode != null {
                        result.Node = new CastExpression(leftNode, typeNode, CastKind.Safe, asToken.Line, asToken.Column)
                    }
                } else {
                    opToken := Advance()
                    // Parser.cs :4176-4185: Less/LessEqual/Greater/GreaterEqual → the matching comparison op.
                    op := RelationalComparisonOp(opToken.Type)
                    leftNode := result.Node
                    rightNode := BinaryRightOperandMissing(opToken, result.Span)
                    if rightNode == null {
                        rightNode = ParseShift().Node
                    }
                    result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
                    result.Node = ComposeBinary(leftNode, op, rightNode, opToken)
                }
            }
        }
        return result
    }

    // Parser.cs :4176-4185. The is/as arms are peeled off before this, so only the four comparisons reach here.
    func RelationalComparisonOp(tokenType: TokenType): BinaryOperator {
        if tokenType == TokenType.LessEqual {
            return BinaryOperator.LessOrEqual
        }
        if tokenType == TokenType.Greater {
            return BinaryOperator.Greater
        }
        if tokenType == TokenType.GreaterEqual {
            return BinaryOperator.GreaterOrEqual
        }
        return BinaryOperator.Less
    }

    func ParseShift(): ExprResult {
        result := ParseAdditive()
        while Check(TokenType.LeftShift) || Check(TokenType.RightShift) {
            opToken := Advance()
            // Parser.cs :4222: LeftShift token → LeftShift, else RightShift.
            op := BinaryOperator.LeftShift
            if opToken.Type == TokenType.RightShift {
                op = BinaryOperator.RightShift
            }
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseAdditive().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, op, rightNode, opToken)
        }
        return result
    }

    func ParseAdditive(): ExprResult {
        result := ParseMultiplicative()
        while Check(TokenType.Plus) || Check(TokenType.Minus) {
            opToken := Advance()
            // Parser.cs :4237: Plus token → Add, else Subtract.
            op := BinaryOperator.Add
            if opToken.Type == TokenType.Minus {
                op = BinaryOperator.Subtract
            }
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseMultiplicative().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, op, rightNode, opToken)
        }
        return result
    }

    // Parser.cs ParseMultiplicativeExpression (:4235). The invalid-multiplicative default (:4253) is an
    // unreachable dead arm (the switch handles Star/Slash/Percent, exactly what the guard admits).
    func ParseMultiplicative(): ExprResult {
        result := ParseRange()
        while Check(TokenType.Star) || Check(TokenType.Slash) || Check(TokenType.Percent) {
            opToken := Advance()
            // Parser.cs :4256-4262: Star → Multiply, Slash → Divide, Percent → Modulo.
            op := BinaryOperator.Multiply
            if opToken.Type == TokenType.Slash {
                op = BinaryOperator.Divide
            } else {
                if opToken.Type == TokenType.Percent {
                    op = BinaryOperator.Modulo
                }
            }
            leftNode := result.Node
            rightNode := BinaryRightOperandMissing(opToken, result.Span)
            if rightNode == null {
                rightNode = ParseRange().Node
            }
            result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            result.Node = ComposeBinary(leftNode, op, rightNode, opToken)
        }
        return result
    }

    // Parser.cs ParseRangeExpression (:4280). `..end` / `..` (open start) and `start..end` / `start..`.
    // A RangeExpression is anchored on the `..` token; the end operand is a unary expression, guarded by
    // the same terminator set Parser.cs uses.
    // Stage N+1c tranche 8: materialize `new RangeExpression(start?, end?, opToken.Line, opToken.Column)`
    // (Parser.cs :4305/:4321). Start/End are legitimately nullable (open ranges), so the gate is "every
    // PRESENT operand carried a node": a fully-open `..` always materializes; `..end` / `start..` / `start..end`
    // materialize only when each present operand's node is non-null (a deferred operand declines, no-stub).
    func ParseRange(): ExprResult {
        if Check(TokenType.DotDot) {
            opToken := Advance()
            endNode: Expression? = null
            hasEnd := RangeHasEndOperand()
            if hasEnd {
                endNode = ParseUnary().Node
            }
            rangeResult := new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            // Open-start range `..` / `..end`: Start is legitimately null.
            canMaterialize := true
            if hasEnd && endNode == null {
                canMaterialize = false
            }
            if canMaterialize {
                rangeResult.Node = new RangeExpression(null, endNode, opToken.Line, opToken.Column)
            }
            return rangeResult
        }

        expr := ParseUnary()
        if Check(TokenType.DotDot) {
            opToken := Advance()
            startNode := expr.Node
            endNode: Expression? = null
            hasEnd := RangeHasEndOperand()
            if hasEnd {
                endNode = ParseUnary().Node
            }
            rangeResult := new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            // `start..` / `start..end`: the start operand is always present, so its node must be non-null.
            canMaterialize := startNode != null
            if hasEnd && endNode == null {
                canMaterialize = false
            }
            if canMaterialize {
                rangeResult.Node = new RangeExpression(startNode, endNode, opToken.Line, opToken.Column)
            }
            return rangeResult
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

    // Stage N+1c tranche 11 (ERROR-NODE MATERIALIZATION): these now RETURN Parser.cs's synthetic operand —
    // `new IdentifierExpression("<error>", operatorToken.Line, operatorToken.Column + Max(1,
    // operatorToken.Value.Length))` (:3785, shared by the binary and assignment arms) — when the right operand
    // is missing, and null when it is PRESENT (the caller then parses the real operand). Parser.cs never
    // declines here, so neither does the owner.
    func BinaryRightOperandMissing(operatorToken: Token, leftSpan: RecoverySpan): Expression? {
        return RightOperandMissingWithSpan(operatorToken, DiagnosticSpanFromExpressionThroughToken(leftSpan, operatorToken))
    }

    func RightOperandMissingWithSpan(operatorToken: Token, diagnosticSpan: RecoverySpan): Expression? {
        if IsMissingOperandBoundary(operatorToken) {
            ReportExpectedExpressionAfter(operatorToken, diagnosticSpan)
            return new IdentifierExpression("<error>", operatorToken.Line, operatorToken.Column + MaxInt(1, operatorToken.Value.Length))
        }
        return null
    }

    // Parser.cs ParseRightOperandOrMissing's ReportError (:3759-3772).
    func ReportExpectedExpressionAfter(operatorToken: Token, span: RecoverySpan) {
        opValue := operatorToken.Value
        suggestions := new List<string>()
        suggestions.Add("Add an expression after '" + opValue + "'")
        suggestions.Add("Remove the trailing '" + opValue + "'")
        Report(ErrorCode.ExpectedToken, "Expected expression after '" + opValue + "'", span.Line, span.Column, "The '" + opValue + "' operator needs an expression on its right side.", "Finish the expression after the operator, or remove the operator if the expression is already complete.", suggestions, span.Length)
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

    // Parser.cs :4340-4356: the prefix-operator token → UnaryOperator mapping. Default Not mirrors the
    // Parser.cs invalid-unary fallback (:4374, an unreachable dead arm the guard never admits).
    func PrefixUnaryOp(tokenType: TokenType): UnaryOperator {
        if tokenType == TokenType.Minus {
            return UnaryOperator.Negate
        }
        if tokenType == TokenType.BitwiseNot {
            return UnaryOperator.BitwiseNot
        }
        if tokenType == TokenType.Increment {
            return UnaryOperator.PreIncrement
        }
        if tokenType == TokenType.Decrement {
            return UnaryOperator.PreDecrement
        }
        if tokenType == TokenType.BitwiseXor {
            return UnaryOperator.IndexFromEnd
        }
        return UnaryOperator.Not
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
            // Stage N+1c tranche 8: materialize `new UnaryExpression(op, operand, opToken.Line, opToken.Column)`
            // (Parser.cs :4380). The operand is the recursive unary; it composes ONLY when its node is non-null.
            op := PrefixUnaryOp(opToken.Type)
            operand := ParseUnary()
            // A UnaryExpression is anchored on the operator and is never a bare identifier.
            unaryResult := new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
            if operand.Node != null {
                unaryResult.Node = new UnaryExpression(op, operand.Node, opToken.Line, opToken.Column)
            }
            return unaryResult
        }

        if Check(TokenType.Await) {
            awaitToken := Advance()
            operandNode := ParseUnaryOperandOrMissing(awaitToken, "an expression to await", "This await expression")
            awaitResult := new ExprResult(new RecoverySpan(awaitToken.Line, awaitToken.Column, 5), false)
            // Stage N+1c tranche 9a: `new AwaitExpression(expr, awaitToken.Line, awaitToken.Column)` (Parser.cs
            // :4390) when the operand materialized (a missing operand declines — no-stub).
            if operandNode != null {
                awaitResult.Node = new AwaitExpression(operandNode, awaitToken.Line, awaitToken.Column)
            }
            return awaitResult
        }
        if Check(TokenType.Must) {
            mustToken := Advance()
            operandNode := ParseUnaryOperandOrMissing(mustToken, "a nullable expression to unwrap", "This must expression")
            mustResult := new ExprResult(new RecoverySpan(mustToken.Line, mustToken.Column, 4), false)
            // Stage N+1c tranche 9a: `new MustExpression(expr, mustToken.Line, mustToken.Column)` (Parser.cs :4400).
            if operandNode != null {
                mustResult.Node = new MustExpression(operandNode, mustToken.Line, mustToken.Column)
            }
            return mustResult
        }
        if Check(TokenType.Throw) {
            throwToken := Advance()
            operandNode := ParseUnaryOperandOrMissing(throwToken, "an exception expression to throw", "This throw expression")
            throwResult := new ExprResult(new RecoverySpan(throwToken.Line, throwToken.Column, 5), false)
            // Stage N+1c tranche 9a: `new ThrowExpression(expr, throwToken.Line, throwToken.Column)` (Parser.cs :4410).
            if operandNode != null {
                throwResult.Node = new ThrowExpression(operandNode, throwToken.Line, throwToken.Column)
            }
            return throwResult
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
        Report(ErrorCode.InvalidSyntax, "Prefix '+' is not supported", span.Line, span.Column, "A leading '+' does not change the value in N#, so it is not part of the expression grammar.", "Remove the leading '+'. Numeric literals and variables are already positive unless you subtract or negate them.", suggestions, span.Length)

        if !IsMissingOperandBoundary(plusToken) && ParserTokenFacts.CanStartExpression(Current().Type) {
            ParseUnary()
        }
        // Stage N+1c tranche 11: Parser.cs returns `new IdentifierExpression("<error>", plusToken.Line,
        // plusToken.Column)` (:3850) — not a visible name, so its DiagnosticSpanFromExpression is the
        // (line, column, 1) default; it is still an IdentifierExpression.
        plusResult := new ExprResult(new RecoverySpan(plusToken.Line, plusToken.Column, 1), true)
        plusResult.Node = new IdentifierExpression("<error>", plusToken.Line, plusToken.Column)
        return plusResult
    }

    // Parser.cs ParseUnaryOperandOrMissing (:3789). Uses IsMissingRequiredExpressionBoundary and a unary
    // operand; the message / hint differ from the binary ParseRightOperandOrMissing.
    // Stage N+1c tranche 11: RETURNS the operand node — present: ParseUnary().Node; missing: Parser.cs's
    // synthetic `new IdentifierExpression("<error>", operatorToken.Line, markerColumn)` (:3824), where
    // markerColumn = operatorToken.Column + Max(1, operatorToken.Value.Length).
    func ParseUnaryOperandOrMissing(operatorToken: Token, expectedDescription: string, ownerDescription: string): Expression? {
        if !IsMissingRequiredExpressionBoundary(operatorToken) {
            return ParseUnary().Node
        }
        span := SpanFromToken(operatorToken)
        suggestions := new List<string>()
        suggestions.Add("Add " + expectedDescription + " after '" + operatorToken.Value + "'")
        suggestions.Add("Remove '" + operatorToken.Value + "' until the expression is ready")
        Report(ErrorCode.ExpectedToken, "Expected " + expectedDescription + " after '" + operatorToken.Value + "'", span.Line, span.Column, ownerDescription + " needs " + expectedDescription + " after '" + operatorToken.Value + "'.", "Add " + expectedDescription + " after '" + operatorToken.Value + "', or remove '" + operatorToken.Value + "'.", suggestions, span.Length)
        return new IdentifierExpression("<error>", operatorToken.Line, operatorToken.Column + MaxInt(1, operatorToken.Value.Length))
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
                        // Index access `a[i]` / `a?[i]` (Parser.cs :4455). The RightBracket close routes
                        // through the Stage-9 closing-delimiter recovery (NL108 when unclosed). An
                        // IndexAccessExpression's DiagnosticSpanFromExpression is the OBJECT's span (:5948).
                        isNullConditional := Check(TokenType.QuestionBracket)
                        objectNode := result.Node
                        objectSpan := result.Span
                        bracketToken := Advance()
                        indexNode := ParseExprValue().Node
                        ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
                        indexResult := new ExprResult(objectSpan, false)
                        // Stage N+1c tranche 9a: `new IndexAccessExpression(expr, index, isNullConditional,
                        // bracketToken.Line, bracketToken.Column)` (Parser.cs :4461) when the object + index
                        // both materialized (a deferred object or index declines — no-stub).
                        if objectNode != null && indexNode != null {
                            indexResult.Node = new IndexAccessExpression(objectNode, indexNode, isNullConditional, bracketToken.Line, bracketToken.Column)
                        }
                        result = indexResult
                    } else {
                        if Check(TokenType.Less) && IsGenericMethodCall() {
                            // Generic method call `M<T>(…)` (Parser.cs :4452). A CallExpression's span is
                            // the CALLEE's span (:5946), i.e. the current receiver's.
                            genericCallee := result.Node
                            genericCalleeSpan := result.Span
                            typeArguments := ParseCallTypeArguments()
                            if !Check(TokenType.LeftParen) {
                                ReportMissingParenAfterGenericTypeArguments()
                                // Parser.cs :4486 builds the EMPTY-argument fallback call anchored on the
                                // offending token (the report does not advance, so Current is unchanged).
                                fallbackToken := Current()
                                fallbackResult := new ExprResult(genericCalleeSpan, false)
                                if genericCallee != null && typeArguments != null {
                                    fallbackResult.Node = new CallExpression(genericCallee, new List<Argument>(), typeArguments, fallbackToken.Line, fallbackToken.Column)
                                }
                                result = fallbackResult
                            } else {
                                genericParenToken := Advance()
                                genericArgs := ParseArgumentList()
                                genericResult := new ExprResult(genericCalleeSpan, false)
                                // Stage N+1c tranche 9b: `new CallExpression(expr, args, typeArgs,
                                // parenToken.Line, parenToken.Column)` (Parser.cs :4492) when the callee, the
                                // type-argument list, and every argument materialized (else declines — no-stub).
                                if genericCallee != null && typeArguments != null && genericArgs != null {
                                    genericCall := new CallExpression(genericCallee, genericArgs, typeArguments, genericParenToken.Line, genericParenToken.Column)
                                    // `ParseArgumentList` has consumed the `)`, so `Previous()` IS the closing
                                    // delimiter — see `StampListEnd`'s note at the plain-call site below.
                                    StampListEnd(genericCall)
                                    genericResult.Node = genericCall
                                }
                                result = genericResult
                            }
                        } else {
                            if Check(TokenType.LeftParen) {
                                // Call `f(…)` (Parser.cs :4484). CallExpression span = callee span.
                                plainCallee := result.Node
                                plainCalleeSpan := result.Span
                                plainParenToken := Advance()
                                plainArgs := ParseArgumentList()
                                plainResult := new ExprResult(plainCalleeSpan, false)
                                // Stage N+1c tranche 9b: `new CallExpression(expr, args, null, parenToken.Line,
                                // parenToken.Column)` (Parser.cs :4499) — a non-generic call carries a NULL
                                // TypeArguments list (not an empty one).
                                if plainCallee != null && plainArgs != null {
                                    plainCall := new CallExpression(plainCallee, plainArgs, NoTypeArguments(), plainParenToken.Line, plainParenToken.Column)
                                    StampListEnd(plainCall)
                                    plainResult.Node = plainCall
                                }
                                result = plainResult
                            } else {
                                if Check(TokenType.Increment) {
                                    // Postfix `x++` (Parser.cs :4504): `new UnaryExpression(PostIncrement,
                                    // expr, opToken.Line, opToken.Column)` over the current receiver node.
                                    opToken := Advance()
                                    operandNode := result.Node
                                    result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
                                    if operandNode != null {
                                        result.Node = new UnaryExpression(UnaryOperator.PostIncrement, operandNode, opToken.Line, opToken.Column)
                                    }
                                } else {
                                    if Check(TokenType.Decrement) {
                                        // Postfix `x--` (Parser.cs :4509).
                                        opToken := Advance()
                                        operandNode := result.Node
                                        result = new ExprResult(new RecoverySpan(opToken.Line, opToken.Column, 1), false)
                                        if operandNode != null {
                                            result.Node = new UnaryExpression(UnaryOperator.PostDecrement, operandNode, opToken.Line, opToken.Column)
                                        }
                                    } else {
                                        if Check(TokenType.With) {
                                            result = ParseWithExpression(result)
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
    func ParseWithExpression(receiver: ExprResult): ExprResult {
        withToken := Advance()
        // consume 'with'
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        properties := new List<PropertyInitializer>()
        propertiesDeclined := false
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            propertyToken := Current()
            propertyName := ConsumeIdentifier("Expected property name")
            // Parser.cs :4510
            ConsumeToken(TokenType.Colon, "Expected ':'", ":")
            propertyValue := ParseExprValue().Node
            // the property value (Parser.cs :4512)
            // Stage N+1c tranche 9b: `new PropertyInitializer(propName, null, propValue, propNameToken.Line,
            // propNameToken.Column)` (Parser.cs :4524). Stage N+1c tranche 11: an `<error>` property name is
            // Parser.cs's own placeholder and it still builds the PropertyInitializer around it.
            if propertyValue == null {
                propertiesDeclined = true
            } else {
                properties.Add(new PropertyInitializer(propertyName, null, propertyValue, propertyToken.Line, propertyToken.Column))
            }
            if !Check(TokenType.RightBrace) {
                // optional comma separator (Parser.cs :4515)
                if Check(TokenType.Comma) {
                    Advance()
                }
            }
            EnsureProgress(startPosition)
        }
        // Parser.cs :4518 — NO panic reset

        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
        withResult := new ExprResult(new RecoverySpan(withToken.Line, withToken.Column, 1), false)
        // `new WithExpression(expr, props, withToken.Line, withToken.Column)` (Parser.cs :4533).
        if receiver.Node != null && !propertiesDeclined {
            withResult.Node = new WithExpression(receiver.Node, properties, withToken.Line, withToken.Column)
        }
        return withResult
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
    // Stage N+1c tranche 9b: RETURNS the byte-exact `List<Argument>` Parser.cs builds, or null when ANY
    // argument failed to materialize (the no-stub gate — the whole call then declines). The recovery-boundary
    // `break` path is NOT a decline: Parser.cs returns the partially collected list there, and so does the
    // owner. The Advance/Report/Consume sequence is untouched, so the diagnostic stream is unchanged.
    func ParseArgumentList(): List<Argument>? {
        arguments := new List<Argument>()
        argumentsDeclined := false
        if !Check(TokenType.RightParen) {
            argsLooping := true
            while argsLooping {
                if IsArgumentListRecoveryBoundaryWithOpening(Previous()) {
                    argsLooping = false
                } else {
                    argument := ParseArgument()
                    if argument == null {
                        argumentsDeclined = true
                    } else {
                        arguments.Add(argument)
                    }
                    if Check(TokenType.Comma) {
                        // Parser.cs do/while Match(Comma) (:4608)
                        Advance()
                    } else {
                        argsLooping = false
                    }
                }
            }
        }
        ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        if argumentsDeclined {
            return null
        }
        return arguments
    }

    // One argument (Parser.cs :4544-4606): the ref/out modifier (with the inline-out NL103), the named
    // `name:` prefix, the spread `...`, the bare alloc/allow/stackalloc identifier, or a plain expression.
    // Stage N+1c tranche 9b: RETURNS `new Argument(argName, argValue, modifier)` (Parser.cs :4617), or null
    // when the value expression is a still-deferred form.
    func ParseArgument(): Argument? {
        // ref / out modifier (Parser.cs :4547).
        modifier := ArgumentModifier.None
        if Check(TokenType.Ref) {
            modifier = ArgumentModifier.Ref
            Advance()
        } else {
            if Check(TokenType.Out) {
                modifier = ArgumentModifier.Out
                Advance()
                // Inline out declaration `out T x` (Parser.cs :4557): two consecutive identifiers. Parser.cs
                // builds a REAL `new Argument(null, new IdentifierExpression(second.Value, second.Line,
                // second.Column), modifier)` (:4582) alongside the NL103 — not synthetic-error content — so
                // the owner materializes it byte-exact.
                if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Identifier {
                    first := Current()
                    second := LookAhead(1)
                    ReportInlineOutDeclaration(first, second)
                    Advance()
                    Advance()
                    return new Argument(null, new IdentifierExpression(second.Value, second.Line, second.Column), modifier)
                }
            }
        }

        // Named argument `name:` (Parser.cs :4579).
        argumentName: string? = null
        if Check(TokenType.Identifier) && LookAhead(1).Type == TokenType.Colon {
            argumentName = Advance().Value
            // the name
            Advance()
        }
        // the colon

        // Spread `...expr` (Parser.cs :4587): `new SpreadExpression(spreadExpr, spreadLine, spreadColumn)`
        // (:4604) anchored on the `...`, then wrapped in the Argument (the name/modifier still apply).
        if Check(TokenType.DotDotDot) {
            spreadToken := Advance()
            spreadValue := ParseExprValue().Node
            if spreadValue == null {
                return null
            }
            return new Argument(argumentName, new SpreadExpression(spreadValue, spreadToken.Line, spreadToken.Column), modifier)
        }

        // A bare alloc / allow / stackalloc keyword used as an identifier argument (Parser.cs :4595):
        // only when immediately followed by `,` or `)` (otherwise it opens its own sub-grammar). Parser.cs
        // :4610 materializes `new IdentifierExpression(token.Value, token.Line, token.Column)`.
        if Check(TokenType.Alloc) || Check(TokenType.Allow) || Check(TokenType.Stackalloc) {
            if LookAhead(1).Type == TokenType.Comma || LookAhead(1).Type == TokenType.RightParen {
                bareToken := Advance()
                return new Argument(argumentName, new IdentifierExpression(bareToken.Value, bareToken.Line, bareToken.Column), modifier)
            }
        }

        argumentValue := ParseExprValue().Node
        if argumentValue == null {
            return null
        }
        return new Argument(argumentName, argumentValue, modifier)
    }

    // A typed null for `CallExpression.TypeArguments` on the non-generic call arm (Parser.cs :4499 passes a
    // literal `null` for the `List<TypeReference>?` parameter).
    func NoTypeArguments(): List<TypeReference>? {
        return null
    }

    // The same null-typed-literal helpers for the test declaration's two OPTIONAL table lists (a bare
    // `null` in a nested-generic nullable argument position is a recorded columnar-emitter gap).
    func NoTableParameters(): List<Parameter>? {
        return null
    }

    func NoTableCases(): List<List<Expression>>? {
        return null
    }

    func NewTableCases(): List<List<Expression>> {
        return new List<List<Expression>>()
    }

    // Parser.cs's inline-out diagnostic (:4561, NL103 InvalidSyntax). The span runs from the first
    // identifier through the end of the second.
    func ReportInlineOutDeclaration(first: Token, second: Token) {
        length := MaxInt(1, second.Column + second.Value.Length - first.Column)
        Report(ErrorCode.InvalidSyntax, "Inline out declarations are not supported", first.Line, first.Column, "N# out arguments must refer to a variable that already exists.", "Declare '" + second.Value + "' before the call, then pass 'out " + second.Value + "'.", null, length)
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
    // Stage N+1c tranche 9b: RETURNS the byte-exact `List<TypeReference>` (:2100/:2104), or null when any
    // argument routes through the shared ParseMaterializedTypeReference gate and declines.
    func ParseCallTypeArguments(): List<TypeReference>? {
        Advance()
        // consume '<' (Parser.cs Consume(Less) :2088)
        typeArguments := new List<TypeReference>()
        typeArgumentsDeclined := false
        firstTypeArgument := ParseMaterializedTypeReference()
        if firstTypeArgument == null {
            typeArgumentsDeclined = true
        } else {
            typeArguments.Add(firstTypeArgument)
        }
        while Check(TokenType.Comma) {
            Advance()
            nextTypeArgument := ParseMaterializedTypeReference()
            if nextTypeArgument == null {
                typeArgumentsDeclined = true
            } else {
                typeArguments.Add(nextTypeArgument)
            }
        }
        ConsumeGreater("Expected '>'")
        if typeArgumentsDeclined {
            return null
        }
        return typeArguments
    }

    // Parser.cs's "Expected '(' after generic type arguments" report (:4460, NL102). IsGenericMethodCall
    // guarantees a `(` follows the closing `>`, so this arm is only reachable if the split-`>>` accounting
    // consumed it; modelled faithfully for parity but not corpus-reachable (recorded in STATUS.md).
    func ReportMissingParenAfterGenericTypeArguments() {
        suggestions := new List<string>()
        suggestions.Add("Add parentheses: Method<int>()")
        suggestions.Add("With arguments: Method<int>(arg1, arg2)")
        suggestions.Add("Example: List.Create<string>(\"hello\")")
        Report(ErrorCode.ExpectedToken, "Expected '(' after generic type arguments. Got '" + Current().Value + "'", Current().Line, Current().Column, "Generic method calls need parentheses for the arguments, even if there are no arguments.", "After the generic type parameters, you need to provide the method arguments in parentheses.", suggestions, Current().Value.Length)
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
            memberResult := new ExprResult(new RecoverySpan(dotToken.Line, dotToken.Column + memberOffset, MaxInt(1, memberToken.Value.Length)), false)
            // Stage N+1c tranche 9a: `new MemberAccessExpression(expr, memberName, isNullConditional,
            // dotToken.Line, dotToken.Column)` (Parser.cs :4453) when the receiver materialized.
            if receiver.Node != null {
                memberResult.Node = new MemberAccessExpression(receiver.Node, memberToken.Value, isNullConditional, dotToken.Line, dotToken.Column)
            }
            return memberResult
        }

        // Stage N+1c tranche 11: the reserved-keyword (:4446) and missing-name (:4451) arms both set
        // `memberName = "<error>"` and fall through to the SAME `new MemberAccessExpression(...)` (:4453).
        if Current().Line == dotToken.Line && Lexer.IsReservedKeyword(Current().Type) {
            // `obj.base`, `this.new`, etc. — a reserved keyword where the member name is required.
            ReportReservedKeywordAsName("Expected member name", SpanFromToken(Current()), true)
            Advance()
            keywordResult := new ExprResult(new RecoverySpan(dotToken.Line, dotToken.Column, 1), false)
            if receiver.Node != null {
                keywordResult.Node = new MemberAccessExpression(receiver.Node, "<error>", isNullConditional, dotToken.Line, dotToken.Column)
            }
            return keywordResult
        }

        ReportMissingMemberNameAfterDot(dotToken, receiver.Span)
        missingResult := new ExprResult(new RecoverySpan(dotToken.Line, dotToken.Column, 1), false)
        if receiver.Node != null {
            missingResult.Node = new MemberAccessExpression(receiver.Node, "<error>", isNullConditional, dotToken.Line, dotToken.Column)
        }
        return missingResult
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
        Report(ErrorCode.ExpectedToken, "Expected member name. Got '" + Current().Value + "'", receiverSpan.Line, receiverSpan.Column, "I see a " + operatorDescription + " operator but no member name after it.", "After " + operatorDescription + ", I need to see a property or method name.", suggestions, receiverSpan.Length)
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

        // Int / float literals carry no malformed check (Parser.cs :4637/:4640). Tranche 7: materialize the
        // byte-exact node — `new IntLiteralExpression(Advance().Value, line, column)` (:4649) / FloatLiteral
        // (:4652). line/column were captured before the advance, so they equal token.Line/token.Column.
        if Check(TokenType.IntLiteral) || Check(TokenType.FloatLiteral) {
            token := Advance()
            literalResult := new ExprResult(new RecoverySpan(token.Line, token.Column, MaxInt(1, token.Value.Length)), false)
            if token.Type == TokenType.FloatLiteral {
                literalResult.Node = new FloatLiteralExpression(token.Value, line, column)
            } else {
                literalResult.Node = new IntLiteralExpression(token.Value, line, column)
            }
            return literalResult
        }

        // Char / string literals run the malformed-literal check (Parser.cs :4643/:4650). The malformed check
        // runs FIRST (Parser.cs :4653), so an unterminated `$"…` still reports NL105 (Stage 3) before the hole
        // grammar runs. A StringLiteral whose value begins `$"` OR an InterpolatedRawStringLiteral then routes
        // into the interpolated-string HOLE grammar (Parser.cs :4654-4657, Stage 12); every other string is a
        // plain literal.
        if Check(TokenType.CharLiteral) {
            token := Advance()
            ReportMalformedCharLiteralIfNeeded(token)
            // Tranche 7: `new CharLiteralExpression(token.Value, line, column)` (Parser.cs :4658) — the node
            // is built regardless of the malformed diagnostic, byte-exact.
            charResult := new ExprResult(new RecoverySpan(token.Line, token.Column, MaxInt(1, token.Value.Length)), false)
            charResult.Node = new CharLiteralExpression(token.Value, line, column)
            return charResult
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
            // Tranche 7: a plain StringLiteral (not `$"`) or a TripleQuoteStringLiteral materializes
            // `new StringLiteralExpression(token.Value, line, column)` (Parser.cs :4669).
            stringResult := new ExprResult(new RecoverySpan(token.Line, token.Column, MaxInt(1, token.Value.Length)), false)
            stringResult.Node = new StringLiteralExpression(token.Value, line, column)
            return stringResult
        }

        // Tranche 7: the keyword leaf atoms materialize their byte-exact nodes (Parser.cs :4675/:4681/:4687/
        // :4694/:4701/:4707). Each keyword token sits at (line, column), so the node's anchor is byte-exact.
        if Check(TokenType.True) {
            Advance()
            trueResult := new ExprResult(new RecoverySpan(line, column, 4), false)
            trueResult.Node = new BoolLiteralExpression(true, line, column)
            return trueResult
        }
        if Check(TokenType.False) {
            Advance()
            falseResult := new ExprResult(new RecoverySpan(line, column, 5), false)
            falseResult.Node = new BoolLiteralExpression(false, line, column)
            return falseResult
        }
        if Check(TokenType.Null) {
            Advance()
            nullResult := new ExprResult(new RecoverySpan(line, column, 4), false)
            nullResult.Node = new NullLiteralExpression(line, column)
            return nullResult
        }
        if Check(TokenType.Default) {
            Advance()
            defaultResult := new ExprResult(new RecoverySpan(line, column, 7), false)
            defaultResult.Node = new DefaultExpression(line, column)
            return defaultResult
        }
        if Check(TokenType.This) {
            Advance()
            thisResult := new ExprResult(new RecoverySpan(line, column, 4), false)
            thisResult.Node = new ThisExpression(line, column)
            return thisResult
        }
        if Check(TokenType.Base) {
            Advance()
            baseResult := new ExprResult(new RecoverySpan(line, column, 4), false)
            baseResult.Node = new BaseExpression(line, column)
            return baseResult
        }

        // typeof / nameof / sizeof (Parser.cs :4700/:4709/:4718): the `( Type )` / `( expr )` shape. typeof
        // and sizeof wrap a TYPE reference; nameof wraps an expression. Each is a non-identifier primary
        // whose DiagnosticSpanFromExpression falls to the (line, column, 1) default (:5960).
        if Check(TokenType.Typeof) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            typeNode := ParseMaterializedTypeReference()
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            typeofResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9a: `new TypeOfExpression(type, line, column)` (Parser.cs :4717) when the
            // wrapped type materialized (a structurally-unbuildable / multi-line type declines — no-stub).
            if typeNode != null {
                typeofResult.Node = new TypeOfExpression(typeNode, line, column)
            }
            return typeofResult
        }
        if Check(TokenType.Nameof) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            targetNode := ParseExprValue().Node
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            nameofResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9a: `new NameofExpression(target, line, column)` (Parser.cs :4726) when the
            // wrapped expression materialized.
            if targetNode != null {
                nameofResult.Node = new NameofExpression(targetNode, line, column)
            }
            return nameofResult
        }
        if Check(TokenType.Sizeof) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            typeNode := ParseMaterializedTypeReference()
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            sizeofResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9a: `new SizeOfExpression(type, line, column)` (Parser.cs :4735).
            if typeNode != null {
                sizeofResult.Node = new SizeOfExpression(typeNode, line, column)
            }
            return sizeofResult
        }

        // checked / unchecked (Parser.cs :4728/:4738): the same `( expr )` paren-wrapped shape.
        if Check(TokenType.Checked) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            exprNode := ParseExprValue().Node
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            checkedResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9a: `new CheckedExpression(expr, line, column)` (Parser.cs :4745).
            if exprNode != null {
                checkedResult.Node = new CheckedExpression(exprNode, line, column)
            }
            return checkedResult
        }
        if Check(TokenType.Unchecked) {
            Advance()
            ConsumeToken(TokenType.LeftParen, "Expected '('", "(")
            exprNode := ParseExprValue().Node
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            uncheckedResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9a: `new UncheckedExpression(expr, line, column)` (Parser.cs :4755).
            if exprNode != null {
                uncheckedResult.Node = new UncheckedExpression(exprNode, line, column)
            }
            return uncheckedResult
        }

        // alloc primary (Parser.cs ParseAllocExpression :5178, dispatched at :4747). The `alloc` keyword wraps
        // a new / array-literal / string-primary / unary sub-shape, all of which are already-owned grammars, so
        // alloc adds no new error site of its own (the guarded Consume(Alloc) never fires). An AllocExpression is
        // anchored on the `alloc` keyword, so its DiagnosticSpanFromExpression falls to the (line, column, 1)
        // default (:5960).
        if Check(TokenType.Alloc) {
            Advance()
            // consume 'alloc'
            allocOperand: Expression? = null
            if Check(TokenType.New) {
                allocOperand = ParseNewExpression().Node
            } else {
                if Check(TokenType.LeftBracket) {
                    allocOperand = ParseArrayLiteral(false).Node
                } else {
                    if Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral) {
                        allocOperand = ParsePrimaryExprValue().Node
                    } else {
                        // Parser.cs :5190 routes a string through ParsePrimaryExpression
                        allocOperand = ParseUnary().Node
                    }
                }
            }
            // Parser.cs :5193 the general unary operand

            allocResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9b: `new AllocExpression(<inner>, line, column)` (Parser.cs :5196/:5199/
            // :5202/:5205) when the wrapped sub-expression materialized.
            if allocOperand != null {
                allocResult.Node = new AllocExpression(allocOperand, line, column)
            }
            return allocResult
        }

        // stackalloc primary (Parser.cs ParseStackAllocExpression :5197, dispatched at :4752): an element TYPE
        // reference, then `[` length `]`. The `[` uses the distinct "Expected '[' after stackalloc element type"
        // NL102 message; the `]` routes through the Stage-9 closing-delimiter recovery (NL108 next-line / EOF,
        // else the distinct "Expected ']' after stackalloc length" NL102). A StackAllocExpression is anchored on
        // the `stackalloc` keyword, so its DiagnosticSpanFromExpression falls to the (line, column, 1) default.
        if Check(TokenType.Stackalloc) {
            Advance()
            // consume 'stackalloc'
            elementTypeNode := ParseMaterializedTypeReference()
            // the element type (Parser.cs :5202)
            ConsumeToken(TokenType.LeftBracket, "Expected '[' after stackalloc element type", "[")
            stackAllocLength := ParseExprValue().Node
            // the length (Parser.cs :5204)
            ConsumeToken(TokenType.RightBracket, "Expected ']' after stackalloc length", "]")
            stackAllocResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9b: `new StackAllocExpression(elementType, length, line, column)` (:5217).
            if elementTypeNode != null && stackAllocLength != null {
                stackAllocResult.Node = new StackAllocExpression(elementTypeNode, stackAllocLength, line, column)
            }
            return stackAllocResult
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
            Advance()
            // consume 'immutable'
            return ParseArrayLiteral(true)
        }
        // Parser.cs :4784 `isImmutable: true`

        // Array literal `[ … ]` (Parser.cs :4777). The RightBracket close routes through the Stage-9 recovery.
        if Check(TokenType.LeftBracket) {
            return ParseArrayLiteral(false)
        }

        // Cast `(Type)expr` — checked BEFORE tuple/paren so `(int)x` is a cast, not a parenthesized `int`
        // (Parser.cs :4783). A CastExpression's DiagnosticSpanFromExpression falls to the (line, column, 1)
        // default (:5960).
        if Check(TokenType.LeftParen) && IsCastExpression() {
            Advance()
            // consume '('
            castTypeNode := ParseMaterializedTypeReference()
            // the cast type
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            castOperandNode := ParseUnary().Node
            // the cast operand (Parser.cs ParseUnaryExpression :4799)
            castResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9a: `new CastExpression(castExpr, castType, CastKind.Hard, line, column)`
            // (Parser.cs :4800) when the cast type + operand both materialized (a deferred operand or an
            // unbuildable / multi-line type declines — no-stub).
            if castTypeNode != null && castOperandNode != null {
                castResult.Node = new CastExpression(castOperandNode, castTypeNode, CastKind.Hard, line, column)
            }
            return castResult
        }

        // Tuple or parenthesized expression `( … )` (Parser.cs :4793).
        if Check(TokenType.LeftParen) {
            return ParseTupleOrParenthesizedExpression()
        }

        // Spread `...expr` (Parser.cs :4799). A SpreadExpression falls to the (line, column, 1) default.
        if Check(TokenType.DotDotDot) {
            Advance()
            spreadNode := ParseExprValue().Node
            spreadResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9a: `new SpreadExpression(spreadExpr, line, column)` (Parser.cs :4814) when
            // the spread operand materialized.
            if spreadNode != null {
                spreadResult.Node = new SpreadExpression(spreadNode, line, column)
            }
            return spreadResult
        }

        if Check(TokenType.Identifier) {
            name := Advance().Value
            // Tranche 7: `new IdentifierExpression(name, line, column)` (Parser.cs :4821). IsBareIdentifier
            // stays true (the named-tuple / shorthand-`:=` decisions read it).
            identResult := new ExprResult(new RecoverySpan(line, column, MaxInt(1, name.Length)), true)
            identResult.Node = new IdentifierExpression(name, line, column)
            return identResult
        }

        // Terminal: an unexpected token where an expression was required (Parser.cs :4813).
        Report(ErrorCode.UnexpectedToken, "Unexpected token '" + Current().Value + "' in expression", line, column, "I was parsing an expression and found '" + Current().Value + "', which I don't know how to handle here.", "Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.", null, Current().Value.Length)

        if ShouldSkipUnexpectedExpressionToken() {
            Advance()
        }

        // Stage N+1c tranche 11: Parser.cs returns the synthetic `new IdentifierExpression("<error>", line,
        // column)` placeholder (:4838) — a (non-visible) IdentifierExpression, so its span is the
        // (line, column, 1) default and it is still an IdentifierExpression.
        terminalResult := new ExprResult(new RecoverySpan(line, column, 1), true)
        terminalResult.Node = new IdentifierExpression("<error>", line, column)
        return terminalResult
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
        Report(ErrorCode.ExpectedToken, "Expected expression before '" + operatorText + "'", span.Line, span.Column, "I see a " + operatorDescription + " operator, but there is no receiver expression before it.", "Put an expression before '" + operatorText + "', or remove the member access.", suggestions, span.Length)
        // Stage N+1c tranche 11: Parser.cs returns `new IdentifierExpression("<error>", dotToken.Line,
        // dotToken.Column)` (:6447).
        leadingDotResult := new ExprResult(new RecoverySpan(dotToken.Line, dotToken.Column, 1), true)
        leadingDotResult.Node = new IdentifierExpression("<error>", dotToken.Line, dotToken.Column)
        return leadingDotResult
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

        // Stage N+1c tranche 9c: Parser.cs's `parts` list + its AppendText / EmitText / AdvancePosition local
        // closures (:4973-4989). N# has no first-class Func, so the three closures are INLINED at each site
        // over plain locals — deliberately NOT parser fields, so a nested interpolated string inside a hole
        // (which re-enters this function through the sub-parse) cannot clobber the outer text buffer.
        parts := new List<InterpolatedStringPart>()
        textBuffer := ""
        textStartLine := line
        textStartCol := column + start
        holesDeclined := false

        currentLine := line
        currentCol := column + start
        i := start

        while i < end {
            ch := value[i]

            // Escape `\x` (non-raw only, Parser.cs :4985): both chars are literal text.
            if !isRaw && ch == '\\' && i + 1 < end {
                if textBuffer.Length == 0 {
                    textStartLine = currentLine
                    textStartCol = currentCol
                }
                textBuffer = textBuffer + ch.ToString()
                if ch == '\n' {
                    currentLine = currentLine + 1
                    currentCol = 1
                } else {
                    currentCol = currentCol + 1
                }
                i = i + 1
                escaped := value[i]
                if textBuffer.Length == 0 {
                    textStartLine = currentLine
                    textStartCol = currentCol
                }
                textBuffer = textBuffer + escaped.ToString()
                if escaped == '\n' {
                    currentLine = currentLine + 1
                    currentCol = 1
                } else {
                    currentCol = currentCol + 1
                }
                i = i + 1
                continue
            }

            // `{{` escape (Parser.cs :4997) and `}}` escape (Parser.cs :5007): a literal brace — ONE brace
            // is appended to the text buffer while BOTH source chars advance the position.
            if ch == '{' && i + 1 < end && value[i + 1] == '{' {
                if textBuffer.Length == 0 {
                    textStartLine = currentLine
                    textStartCol = currentCol
                }
                textBuffer = textBuffer + "{"
                currentCol = currentCol + 1
                i = i + 1
                currentCol = currentCol + 1
                i = i + 1
                continue
            }
            if ch == '}' && i + 1 < end && value[i + 1] == '}' {
                if textBuffer.Length == 0 {
                    textStartLine = currentLine
                    textStartCol = currentCol
                }
                textBuffer = textBuffer + "}"
                currentCol = currentCol + 1
                i = i + 1
                currentCol = currentCol + 1
                i = i + 1
                continue
            }

            if ch == '{' {
                // Raw `{`-literal heuristic: inside a raw string a `{` with no closing `}`, or whose content
                // spans lines, is literal text, not a hole — the leniency that keeps a multi-line JSON or
                // template brace group literal. The ported Parser.cs :5019 heuristic ALSO swallowed a `{`
                // preceded by `:` plus optional whitespace (even across lines) — a format-specifier rule
                // mis-scoped to TEXT context, ruled a DEFECT and removed: `"age": {person.Age}` in a raw
                // JSON template is a HOLE, exactly as in an ordinary `$"…"` string.
                if isRaw {
                    nextClose := IndexOfCharFrom(value, '}', i + 1)
                    contentSpansLine := false
                    if nextClose >= 0 {
                        contentSpansLine = RangeContainsNewline(value, i + 1, nextClose)
                    }
                    if nextClose < 0 || contentSpansLine {
                        if textBuffer.Length == 0 {
                            textStartLine = currentLine
                            textStartCol = currentCol
                        }
                        textBuffer = textBuffer + ch.ToString()
                        currentCol = currentCol + 1
                        i = i + 1
                        continue
                    }
                }

                // EmitText() before the hole (Parser.cs :5047).
                if textBuffer.Length > 0 {
                    parts.Add(new InterpolatedStringText(textBuffer, textStartLine, textStartCol))
                    textBuffer = ""
                }

                holeLine := currentLine
                holeCol := currentCol

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
                            currentCol = currentCol + 1
                            // AdvancePosition('\\'); a backslash is never '\n'
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

                // Raw hole content that spans lines is literal text, not an expression (Parser.cs :5101) —
                // emitted as a TEXT part carrying the braces, anchored on the hole's `{`.
                if isRaw && ContainsNewline(exprContent) {
                    literalText := "{" + exprContent
                    if i < end && value[i] == '}' {
                        literalText = literalText + "}"
                        currentCol = currentCol + 1
                        i = i + 1
                    }
                    parts.Add(new InterpolatedStringText(literalText, holeLine, holeCol))
                    textStartLine = currentLine
                    textStartCol = currentCol
                    continue
                }

                // Split off a `:format` clause (Parser.cs :5117); only the expression part is sub-parsed.
                formatClause: string? = null
                colonPos := ParserLiteralFacts.FindFormatSpecifierColon(exprContent)
                if colonPos >= 0 {
                    formatClause = exprContent.Substring(colonPos + 1)
                    exprContent = exprContent.Substring(0, colonPos)
                }

                holeExpression := ParseHoleExpression(exprContent, exprStartLine, exprStartCol)
                // `new InterpolatedStringHole(expr, formatClause, holeLine, holeCol)` (Parser.cs :5163).
                if holeExpression == null {
                    holesDeclined = true
                } else {
                    parts.Add(new InterpolatedStringHole(holeExpression, formatClause, holeLine, holeCol))
                }

                // Consume the closing `}` (Parser.cs :5154).
                if i < end && value[i] == '}' {
                    currentCol = currentCol + 1
                    i = i + 1
                }
                textStartLine = currentLine
                textStartCol = currentCol
                continue
            }

            // Ordinary text char.
            if textBuffer.Length == 0 {
                textStartLine = currentLine
                textStartCol = currentCol
            }
            textBuffer = textBuffer + ch.ToString()
            if ch == '\n' {
                currentLine = currentLine + 1
                currentCol = 1
            } else {
                currentCol = currentCol + 1
            }
            i = i + 1
        }

        // The trailing EmitText() (Parser.cs :5180).
        if textBuffer.Length > 0 {
            parts.Add(new InterpolatedStringText(textBuffer, textStartLine, textStartCol))
            textBuffer = ""
        }

        // An InterpolatedStringExpression is anchored on (line, column); its DiagnosticSpanFromExpression falls
        // to the (line, column, 1) default and it is never a bare identifier (Parser.cs :5172).
        interpResult := new ExprResult(new RecoverySpan(line, column, 1), false)
        // Stage N+1c tranche 9c: `new InterpolatedStringExpression(parts, line, column, isRaw)` (:5183).
        if !holesDeclined {
            interpResult.Node = new InterpolatedStringExpression(parts, line, column, isRaw)
        }
        return interpResult
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
    // Stage N+1c tranche 9c: RETURNS the hole expression's byte-exact node (Parser.cs's `subParser
    // .ParseExpression()` result), or null when the hole is a still-deferred / failed form.
    func ParseHoleExpression(exprContent: string, exprStartLine: int, exprStartCol: int): Expression? {
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
        HoleDepth = HoleDepth + 1

        holeNode := ParseExprValue().Node

        // The lone explicit ReportError (Parser.cs :5141): extra syntax after the hole expression. Routed through
        // the SUB-parser's Report, so a hole-expression error that already tripped the sub-panic suppresses this.
        if !IsAtEnd() {
            Report(ErrorCode.UnexpectedToken, "Unexpected token '" + Current().Value + "' after interpolated string expression", Current().Line, Current().Column, "I parsed a valid expression at the start of this interpolation hole, but there was extra syntax after it.", "Keep exactly one expression inside each interpolation hole, or split additional text outside the braces.", null, MaxInt(1, Current().Value.Length))
        }

        HoleDepth = HoleDepth - 1
        Tokens = savedTokens
        Position = savedPosition
        PanicMode = savedPanic
        SplitGreaterDepth = savedSplit
        RecoveryBoundaryColumn = savedBoundaryColumn
        HasRecoveryBoundaryColumn = savedHasBoundaryColumn
        return holeNode
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
        newToken := Advance()
        // consume 'new'
        line := newToken.Line
        column := newToken.Column
        hasArrayLength := false
        // Stage N+1c tranche 9b materialization state: Parser.cs's `type` / `args` / `arrayLengthExpression`
        // locals, plus one decline flag per sub-part (the established per-form no-stub gate).
        newType: TypeReference? = null
        typeDeclined := false
        constructorArguments := new List<Argument>()
        argumentsDeclined := false
        arrayLength: Expression? = null
        // The NewExpression's own `EndLine` is the CONSTRUCTOR ARGUMENT LIST's closer, not the whole
        // expression's last token, because those are two different lists: `new Foo(a) { X: 1 }` has a
        // single-line argument list and a wrapped initializer, and the formatter must be able to tell
        // them apart. The initializer carries its own `{`/`}` span. With no parens at all the two stay
        // equal, which reads as "single line" — correct for `new Foo` and `new Foo { … }` alike.
        constructorArgumentsEndLine := line

        if Check(TokenType.LeftParen) {
            // Target-typed new: `new(args)` (Parser.cs :5220).
            Advance()
            targetTypedArguments := ParseArgumentList()
            constructorArgumentsEndLine = Previous().Line
            if targetTypedArguments == null {
                argumentsDeclined = true
            } else {
                constructorArguments = targetTypedArguments
            }
        } else {
            if Check(TokenType.LeftBrace) {
            } else {
                // Target-typed new with initializer only: `new { … }` (Parser.cs :5226) — parsed below.

                // Traditional new: `new TypeName …` (Parser.cs :5233).
                newType = ParseNewTypeReference(newToken)
                if newType == null || !TypeReferenceMaterialized {
                    typeDeclined = true
                }
                if Check(TokenType.LeftBracket) {
                    // sized array `new Type[len]` (Parser.cs :5237)
                    Advance()
                    arrayLength = ParseExprValue().Node
                    ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
                    hasArrayLength = true
                    // Parser.cs :5253 `type = new ArrayTypeReference(type) { Span = type.Span }` — the wrapper
                    // KEEPS the element type's span (unlike the postfix `[]` wrapper, which extends through `]`).
                    newType = WrapNewArrayType(newType)
                }
                if Check(TokenType.LeftParen) {
                    // constructor args (Parser.cs :5248)
                    Advance()
                    typedArguments := ParseArgumentList()
                    constructorArgumentsEndLine = Previous().Line
                    if typedArguments == null {
                        argumentsDeclined = true
                    } else {
                        constructorArguments = typedArguments
                    }
                }
                if hasArrayLength {
                    // `new Type[len] { … }` sized-array initializer (Parser.cs :5257): bare-value elements
                    // with the per-element panic-reset-on-progress discipline.
                    sizedElements := new List<PropertyInitializer>()
                    hasSizedInitializer := false
                    sizedDeclined := false
                    // An initializer is anchored on ITS OWN `{`, never on the `new` keyword. The two differ
                    // whenever the constructor arguments or the array length wrapped, and the formatter asks
                    // the initializer's span whether the initializer wrapped.
                    sizedBraceLine := line
                    sizedBraceColumn := column
                    sizedBraceEndLine := line
                    if Check(TokenType.LeftBrace) {
                        hasSizedInitializer = true
                        sizedBraceToken := Current()
                        sizedBraceLine = sizedBraceToken.Line
                        sizedBraceColumn = sizedBraceToken.Column
                        Advance()
                        while !Check(TokenType.RightBrace) && !IsAtEnd() {
                            startPosition := Position
                            sizedValue := ParseExprValue().Node
                            // `new PropertyInitializer(null, null, value)` (Parser.cs :5276) — a bare element
                            // carries no name / index and the default (0, 0) name anchor.
                            if sizedValue == null {
                                sizedDeclined = true
                            } else {
                                sizedElements.Add(new PropertyInitializer(null, null, sizedValue, 0, 0))
                            }
                            if !Check(TokenType.RightBrace) {
                                if Check(TokenType.Comma) {
                                    Advance()
                                }
                            }
                            if !EnsureProgress(startPosition) {
                                PanicMode = false
                            }
                        }
                        // Parser.cs :5268-5269

                        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
                        sizedBraceEndLine = Previous().Line
                    }
                    sizedResult := new ExprResult(new RecoverySpan(line, column, 3), false)
                    // `new NewExpression(type, args, sizedArrayInitializer, line, column, arrayLengthExpression)`
                    // (Parser.cs :5286); the initializer is null when no `{ … }` followed.
                    if !typeDeclined && !argumentsDeclined && !sizedDeclined && arrayLength != null {
                        if hasSizedInitializer {
                            sizedInitializer := new ObjectInitializerExpression(sizedElements, sizedBraceLine, sizedBraceColumn)
                            sizedInitializer.EndLine = sizedBraceEndLine
                            sizedNew := new NewExpression(newType, constructorArguments, sizedInitializer, line, column, arrayLength)
                            sizedNew.EndLine = constructorArgumentsEndLine
                            sizedResult.Node = sizedNew
                        } else {
                            sizedNewBare := new NewExpression(newType, constructorArguments, null, line, column, arrayLength)
                            sizedNewBare.EndLine = constructorArgumentsEndLine
                            sizedResult.Node = sizedNewBare
                        }
                    }
                    return sizedResult
                }
            }
        }

        // Object / collection initializer `{ … }` (Parser.cs :5280).
        initializerProperties := new List<PropertyInitializer>()
        hasInitializer := false
        initializerDeclined := false
        initializerBraceLine := line
        initializerBraceColumn := column
        initializerBraceEndLine := line
        if Check(TokenType.LeftBrace) {
            hasInitializer = true
            // Anchored on the `{`, not on `new` — see the sized-array note above.
            initializerBraceToken := Current()
            initializerBraceLine = initializerBraceToken.Line
            initializerBraceColumn = initializerBraceToken.Column
            parsedProperties := ParseObjectInitializer(newType)
            initializerBraceEndLine = Previous().Line
            if parsedProperties == null {
                initializerDeclined = true
            } else {
                initializerProperties = parsedProperties
            }
        }
        newResult := new ExprResult(new RecoverySpan(line, column, 3), false)
        // `new NewExpression(type, args, initializer, line, column)` (Parser.cs :5353) — ArrayLengthExpression
        // defaults to null on this path.
        if !typeDeclined && !argumentsDeclined && !initializerDeclined {
            if hasInitializer {
                initializer := new ObjectInitializerExpression(initializerProperties, initializerBraceLine, initializerBraceColumn)
                initializer.EndLine = initializerBraceEndLine
                initializedNew := new NewExpression(newType, constructorArguments, initializer, line, column, null)
                initializedNew.EndLine = constructorArgumentsEndLine
                newResult.Node = initializedNew
            } else {
                bareNew := new NewExpression(newType, constructorArguments, null, line, column, null)
                bareNew.EndLine = constructorArgumentsEndLine
                newResult.Node = bareNew
            }
        }
        return newResult
    }

    // Parser.cs :5253 `new ArrayTypeReference(type) { Span = type.Span }`.
    func WrapNewArrayType(element: TypeReference?): TypeReference? {
        if element == null {
            return null
        }
        wrapped := new ArrayTypeReference(element)
        wrapped.Span = element.Span
        return wrapped
    }

    // Parser.cs ParseNewTypeReference (:6579): the type after `new`, or the "Expected type name" NL102
    // (anchored on the `new` keyword) when a type terminator immediately follows. Stage N+1c tranche 9b:
    // RETURNS the RAW parsed TypeReference (the collection-initializer decision reads it), recording the
    // materialization verdict in `TypeReferenceMaterialized`.
    func ParseNewTypeReference(newToken: Token): TypeReference? {
        if !IsTypeTerminator(Current().Type) {
            return ParseGatedTypeReference()
        }
        TypeReferenceMaterialized = false
        span := SpanFromToken(newToken)
        suggestions := new List<string>()
        suggestions.Add("Add a type name after `new`")
        suggestions.Add("Use `new()` for target-typed construction")
        Report(ErrorCode.ExpectedToken, "Expected type name. Got '" + Current().Value + "'", span.Line, span.Column, "The `new` expression needs a type name, `()`, or an initializer after it.", "Write `new TypeName(...)`, `new()`, or `new { Name: value }`.", suggestions, span.Length)
        TypeReferenceMaterialized = true
        // Stage N+1c tranche 11 (ERROR-NODE MATERIALIZATION): Parser.cs substitutes a SYNTHETIC
        // `new SimpleTypeReference("<error>", span.Line, span.Column) { Span = SourceSpan.FromStartAndLength(
        // span.Line, span.Column, span.Length) }` here (:6610) — it does not decline.
        errorType := new SimpleTypeReference("<error>", span.Line, span.Column)
        errorType.Span = SourceSpan.FromStartAndLength(span.Line, span.Column, span.Length)
        return errorType
    }

    // Parser.cs's object / collection initializer loop (:5285-5340). Each element resets panic on natural
    // progress (`if (!EnsureProgress(startPosition)) _panicMode = false;`, :5334) — DISTINCT from the with /
    // match loops that never reset. Stage N+1c tranche 9b now materializes the RECEIVER TYPE, so the owner can
    // finally take Parser.cs's `type is ArrayTypeReference` COLLECTION-initializer branch (:5294 — bare values,
    // no property name / colon) instead of always taking the object branch; the previously recorded
    // "does not know the receiver's array-ness" approximation is retired, and `new T[] { a, b }` now reports
    // nothing (it previously produced two spurious missing-colon NL102s). Returns the byte-exact
    // `List<PropertyInitializer>`, or null when any element declined.
    func ParseObjectInitializer(newType: TypeReference?): List<PropertyInitializer>? {
        isCollectionInit := newType is ArrayTypeReference
        properties := new List<PropertyInitializer>()
        propertiesDeclined := false
        Advance()
        // consume '{'
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            if isCollectionInit {
                // Collection initializer: bare values (Parser.cs :5306) → `new PropertyInitializer(null, null, value)`.
                collectionValue := ParseExprValue().Node
                if collectionValue == null {
                    propertiesDeclined = true
                } else {
                    properties.Add(new PropertyInitializer(null, null, collectionValue, 0, 0))
                }
            } else {
                if Check(TokenType.LeftBracket) {
                    // Indexer initializer `[i] = v` (Parser.cs :5299) → `new PropertyInitializer(null, indexExpr, indexValue)`.
                    Advance()
                    indexExpression := ParseExprValue().Node
                    ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
                    ConsumeToken(TokenType.Assign, "Expected '='", "assign")
                    indexValue := ParseExprValue().Node
                    if indexExpression == null || indexValue == null {
                        propertiesDeclined = true
                    } else {
                        properties.Add(new PropertyInitializer(null, indexExpression, indexValue, 0, 0))
                    }
                } else {
                    // Regular property initializer `Name: value` (Parser.cs :5310) → `new PropertyInitializer(
                    // propName, null, propValue, propNameToken.Line, propNameToken.Column)` (:5339).
                    propNameToken := Current()
                    propName := ConsumeIdentifier("Expected property name")
                    if Check(TokenType.Colon) {
                        Advance()
                        propertyValue := ParseObjectInitializerMemberValue(propNameToken, propName)
                        // Stage N+1c tranche 11: an `<error>` property NAME is Parser.cs's own placeholder.
                        if propertyValue == null {
                            propertiesDeclined = true
                        } else {
                            properties.Add(new PropertyInitializer(propName, null, propertyValue, propNameToken.Line, propNameToken.Column))
                        }
                    } else {
                        ReportMissingObjectInitializerColon(propNameToken, propName)
                        // Stage N+1c tranche 11: Parser.cs substitutes the synthetic `new IdentifierExpression(
                        // "<error>", propNameToken.Line, propNameToken.Column + TokenLengthOrFallback(
                        // propNameToken))` value (:5334) and still adds the PropertyInitializer (:5340).
                        missingColonValue := new IdentifierExpression("<error>", propNameToken.Line, propNameToken.Column + TokenLength(propNameToken))
                        properties.Add(new PropertyInitializer(propName, null, missingColonValue, propNameToken.Line, propNameToken.Column))
                    }
                }
            }
            if !Check(TokenType.RightBrace) {
                if Check(TokenType.Comma) {
                    Advance()
                }
            }
            if !EnsureProgress(startPosition) {
                PanicMode = false
            }
        }
        // Parser.cs :5334-5335

        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
        if propertiesDeclined {
            return null
        }
        return properties
    }

    // Parser.cs ParseObjectInitializerMemberValue (:5345): a required value after the member `:`, or the
    // "Expected a value for object initializer member" NL102 anchored on the property. Stage N+1c tranche 9b:
    // RETURNS the member value's node (the missing path returns a synthetic `<error>` in Parser.cs → decline).
    func ParseObjectInitializerMemberValue(propertyToken: Token, propertyName: string): Expression? {
        if !IsMissingRequiredExpressionBoundary(propertyToken) {
            return ParseExprValue().Node
        }
        propertyLength := MaxInt(1, propertyName.Length)
        suggestions := new List<string>()
        suggestions.Add("Add a value after '" + propertyName + ":'")
        Report(ErrorCode.ExpectedToken, "Expected a value for object initializer member '" + propertyName + "'", propertyToken.Line, propertyToken.Column, "Object initializer member '" + propertyName + "' needs a value after ':'.", "Write '" + propertyName + ": value'.", suggestions, propertyLength)
        // Stage N+1c tranche 11: Parser.cs returns the synthetic `new IdentifierExpression("<error>",
        // separatorToken.Line, separatorToken.Column + Max(1, separatorToken.Value.Length))` (:5376). The
        // separator is the `:` the caller just consumed, i.e. Previous().
        separatorToken := Previous()
        return new IdentifierExpression("<error>", separatorToken.Line, separatorToken.Column + MaxInt(1, separatorToken.Value.Length))
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
        Report(ErrorCode.ExpectedToken, "Expected ':' after object initializer member '" + propertyName + "'", span.Line, span.Column, "Object initializer member '" + propertyName + "' needs ':' before its value.", "Write '" + propertyName + ": value'.", suggestions, span.Length)
    }

    // Parser.cs ParseArrayLiteral (:5407). `[ e, e, … ]`; the RightBracket close routes through the Stage-9
    // recovery (NL108 when unclosed). An ArrayLiteralExpression falls to the (bracketLine, bracketColumn, 1)
    // DiagnosticSpanFromExpression default (:5960).
    func ParseArrayLiteral(isImmutable: bool): ExprResult {
        bracketToken := Current()
        line := bracketToken.Line
        column := bracketToken.Column
        ConsumeToken(TokenType.LeftBracket, "Expected '['", "[")
        elements := new List<Expression>()
        elementsDeclined := false
        if !Check(TokenType.RightBracket) {
            elementsLooping := true
            while elementsLooping {
                elementValue := ParseExprValue().Node
                if elementValue == null {
                    elementsDeclined = true
                } else {
                    elements.Add(elementValue)
                }
                if Check(TokenType.Comma) {
                    Advance()
                } else {
                    elementsLooping = false
                }
            }
        }
        ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
        arrayResult := new ExprResult(new RecoverySpan(line, column, 1), false)
        // Stage N+1c tranche 9b: `new ArrayLiteralExpression(elements, isImmutable, line, column)` (Parser.cs
        // :5436), anchored on the `[` — the `immutable` keyword arm advances past the keyword FIRST, so the
        // anchor is the bracket in both forms.
        if !elementsDeclined {
            arrayLiteral := new ArrayLiteralExpression(elements, isImmutable, line, column)
            StampListEnd(arrayLiteral)
            arrayResult.Node = arrayLiteral
        }
        return arrayResult
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
            emptyTupleResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // Stage N+1c tranche 9b: `new TupleExpression(new List<TupleElement>(), line, column)` (:5449).
            emptyTupleResult.Node = new TupleExpression(new List<TupleElement>(), line, column)
            return emptyTupleResult
        }

        // Recovery boundary: a `)` cannot be reached on this construct (Parser.cs :5441). ConsumeToken here
        // takes the closing-delimiter recovery / standard path; the result is a ParenthesizedExpression whose
        // inner `<error>` span is (recoveredToken.Line, recoveredToken.Column, 1).
        if IsArgumentListRecoveryBoundaryWithOpening(Previous()) {
            recoveredToken := ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            // Stage N+1c tranche 11: Parser.cs returns `new ParenthesizedExpression(new IdentifierExpression(
            // "<error>", recoveredToken.Line, recoveredToken.Column), line, column)` (:5455-5459).
            recoveredResult := new ExprResult(new RecoverySpan(recoveredToken.Line, recoveredToken.Column, 1), false)
            recoveredResult.Node = new ParenthesizedExpression(new IdentifierExpression("<error>", recoveredToken.Line, recoveredToken.Column), line, column)
            return recoveredResult
        }

        firstExpr := ParseExprValue()

        // Named tuple `(a: x, …)` — only when the first element is a bare identifier (Parser.cs :5454; the
        // live check is `firstExpr is IdentifierExpression firstIdent`, and the NAME comes from that node).
        if Check(TokenType.Colon) && firstExpr.IsBareIdentifier {
            Advance()
            namedElements := new List<TupleElement>()
            namedDeclined := false
            firstValue := ParseExprValue().Node
            // the first value
            firstIdentifier := firstExpr.Node as IdentifierExpression
            // Stage N+1c tranche 9b: `new TupleElement(firstIdent.Name, firstValue)` (:5471). The `<error>`
            // terminal primary is ALSO a bare identifier in the owner but carries no node → declines.
            if firstIdentifier == null || firstValue == null {
                namedDeclined = true
            } else {
                namedElements.Add(new TupleElement(firstIdentifier.Name, firstValue))
            }
            while Check(TokenType.Comma) {
                Advance()
                elementName := ConsumeIdentifier("Expected identifier")
                // Parser.cs :5465
                ConsumeToken(TokenType.Colon, "Expected ':'", ":")
                elementValue := ParseExprValue().Node
                // Stage N+1c tranche 11: an `<error>` element name is Parser.cs's own placeholder (:5476).
                if elementValue == null {
                    namedDeclined = true
                } else {
                    namedElements.Add(new TupleElement(elementName, elementValue))
                }
            }
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            namedTupleResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // `new TupleExpression(elements, line, column)` (Parser.cs :5483), anchored on the `(`.
            if !namedDeclined {
                namedTupleResult.Node = new TupleExpression(namedElements, line, column)
            }
            return namedTupleResult
        }

        // Unnamed tuple `(a, b, …)` (Parser.cs :5476).
        if Check(TokenType.Comma) {
            unnamedElements := new List<TupleElement>()
            unnamedDeclined := false
            // `new TupleElement(null, firstExpr)` (Parser.cs :5489) is the leading element.
            if firstExpr.Node == null {
                unnamedDeclined = true
            } else {
                unnamedElements.Add(new TupleElement(null, firstExpr.Node))
            }
            while Check(TokenType.Comma) {
                Advance()
                unnamedValue := ParseExprValue().Node
                if unnamedValue == null {
                    unnamedDeclined = true
                } else {
                    unnamedElements.Add(new TupleElement(null, unnamedValue))
                }
            }
            ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
            unnamedTupleResult := new ExprResult(new RecoverySpan(line, column, 1), false)
            // `new TupleExpression(elements, line, column)` (Parser.cs :5497).
            if !unnamedDeclined {
                unnamedTupleResult.Node = new TupleExpression(unnamedElements, line, column)
            }
            return unnamedTupleResult
        }

        // Parenthesized expression `(e)` (Parser.cs :5489). Its span is the inner expression's. Tranche 7:
        // materialize `new ParenthesizedExpression(firstExpr, line, column)` (Parser.cs :5502) — but only when
        // the inner expression itself materialized (a leaf/paren atom); a composed/deferred inner leaves
        // firstExpr.Node null → the paren declines too. line/column anchor the opening `(` (Parser.cs :5441).
        ConsumeToken(TokenType.RightParen, "Expected ')'", ")")
        parenResult := new ExprResult(firstExpr.Span, false)
        if firstExpr.Node != null {
            parenResult.Node = new ParenthesizedExpression(firstExpr.Node, line, column)
        }
        return parenResult
    }

    // ---- cast-detection lookahead (Parser.cs IsCastExpression :5573) ----
    // A pure bounded lookahead deciding whether the `(` at the cursor opens a cast `(Type)operand` rather
    // than a tuple / parenthesized expression. N# has no first-class Func values, so Parser.cs's nested
    // scan closures are lowered to methods over two explicit scan-state fields (ScanPosition, ScanSplit).
    // No cursor mutation, no diagnostics.
    //
    // THE CAST OPERAND MUST BEGIN ON THE CLOSING PAREN'S OWN LINE. N# has NO statement terminator
    // ("no semicolons" is a documented promise), so a newline between the `)` and the next token is a
    // STATEMENT BOUNDARY and the following statement must parse INDEPENDENTLY. Without that rule the
    // C#-inherited `(Name)operand` disambiguation reads across the boundary: `print(c.Count)` followed
    // on the NEXT line by `sum := 0` became a cast of `sum` to the type `c.Count`, which swallowed the
    // declaration and produced NL101 at the `:=` plus an NL301 cascade and a false NL001 about the
    // receiver the cast target had demoted to a type name. The line test is deliberately spelled here
    // rather than in a helper: this class is at the columnar front end's per-class member ceiling
    // (§2.1), so a new member function would decline the whole class.
    func IsCastExpression(): bool {
        ScanPosition = Position + 1
        // skip '(' without mutating the parser cursor
        ScanSplit = 0
        if !ScanTypeReference() {
            return false
        }
        if ScanCurrentType() != TokenType.RightParen {
            return false
        }
        if ScanPosition + 1 >= Tokens.Count {
            return false
        }
        // ScanSplit is 0 here (ScanCurrentType answered RightParen), so ScanPosition indexes the `)`.
        if Tokens[ScanPosition + 1].Line != Tokens[ScanPosition].Line {
            return false
        }
        return ParserTokenFacts.IsCastOperandStart(Tokens[ScanPosition + 1].Type)
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
        Advance()
        // consume 'match'

        matchValue := ParseExprValue().Node
        // the match value (Parser.cs ParseExpression :5374)
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")

        cases := new List<MatchCase>()
        casesDeclined := false
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            casePattern := ParsePattern()

            caseGuard: Expression? = null
            hasGuard := false
            if Check(TokenType.When) {
                // optional guard clause (Parser.cs :5386)
                Advance()
                hasGuard = true
                caseGuard = ParseExprValue().Node
            }

            ConsumeToken(TokenType.Arrow, "Expected '=>'", "arrow")
            caseBody := ParseExprValue().Node
            // the case body (Parser.cs :5392)

            // `new MatchCase(pattern, guard, caseExpr)` (Parser.cs :5404). A PRESENT guard must materialize.
            if casePattern == null || caseBody == null {
                casesDeclined = true
            } else {
                if hasGuard && caseGuard == null {
                    casesDeclined = true
                } else {
                    cases.Add(new MatchCase(casePattern, caseGuard, caseBody))
                }
            }

            if !Check(TokenType.RightBrace) {
                // require a comma between cases (Parser.cs :5396)
                ConsumeToken(TokenType.Comma, "Expected ',' between match cases", ",")
            }

            EnsureProgress(startPosition)
        }
        // Parser.cs :5399 — NO panic reset per case

        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
        // A MatchExpression's DiagnosticSpanFromExpression falls to the (line, column, 1) default (Parser.cs
        // :5960, anchored on the `match` keyword); it is never a bare identifier.
        matchResult := new ExprResult(new RecoverySpan(line, column, 1), false)
        // Stage N+1c tranche 9c: `new MatchExpression(value, cases, line, column)` (Parser.cs :5415);
        // IsExhaustive is a later-phase field neither side sets here.
        if matchValue != null && !casesDeclined {
            matchResult.Node = new MatchExpression(matchValue, cases, line, column)
        }
        return matchResult
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

    // Stage N+1c tranche 9c: each tier RETURNS its byte-exact Pattern node (or null when a sub-part is a
    // still-deferred / synthetic-error shape — the established no-stub gate). The Advance/Report/Consume
    // sequence is unchanged, so the diagnostic stream is unperturbed.
    func ParsePattern(): Pattern? {
        return ParseOrPattern()
    }

    func ParseOrPattern(): Pattern? {
        left := ParseAndPattern()
        while Check(TokenType.OrKeyword) {
            orLine := Current().Line
            orColumn := Current().Column
            Advance()
            right := ParseAndPattern()
            // `new OrPattern(left, right, line, column)` (Parser.cs :3290), anchored on the `or` keyword.
            if left != null && right != null {
                left = new OrPattern(left, right, orLine, orColumn)
            } else {
                left = null
            }
        }
        return left
    }

    func ParseAndPattern(): Pattern? {
        left := ParseNotPattern()
        while Check(TokenType.AndKeyword) {
            andLine := Current().Line
            andColumn := Current().Column
            Advance()
            right := ParseNotPattern()
            // `new AndPattern(left, right, line, column)` (Parser.cs :3306).
            if left != null && right != null {
                left = new AndPattern(left, right, andLine, andColumn)
            } else {
                left = null
            }
        }
        return left
    }

    func ParseNotPattern(): Pattern? {
        if Check(TokenType.NotKeyword) {
            notLine := Current().Line
            notColumn := Current().Column
            Advance()
            inner := ParseNotPattern()
            // recursive for multiple `not` (Parser.cs :3308)
            // `new NotPattern(pattern, line, column)` (Parser.cs :3320).
            if inner == null {
                return null
            }
            return new NotPattern(inner, notLine, notColumn)
        }
        return ParseRelationalPattern()
    }

    // Parser.cs ParseRelationalPattern (:3315): a leading comparison operator forms a relational pattern
    // whose value is a PRIMARY expression (:3328 — deliberately NOT the full ladder, so it does not consume
    // the next pattern's operators).
    func ParseRelationalPattern(): Pattern? {
        line := Current().Line
        column := Current().Column
        if Check(TokenType.Less) || Check(TokenType.Greater) || Check(TokenType.LessEqual) || Check(TokenType.GreaterEqual) || Check(TokenType.Equal) || Check(TokenType.NotEqual) {
            operatorText := Advance().Value
            // the comparison operator
            comparedValue := ParsePrimaryExprValue().Node
            // the compared value (Parser.cs ParsePrimaryExpression)
            // `new RelationalPattern(op, value, line, column)` (Parser.cs :3340) — the operator is the raw
            // token TEXT, and the anchor is the tier's entry position (the operator token).
            if comparedValue == null {
                return null
            }
            return new RelationalPattern(operatorText, comparedValue, line, column)
        }
        return ParsePrimaryPattern()
    }

    // Parser.cs ParsePrimaryPattern (:3335): list `[…]`, positional `(…)`, literal, object `{…}`, and the
    // identifier-led union-case / type / qualified-name / identifier patterns, terminating in the
    // "Invalid pattern. Got 'X'" NL103. The list `]` / positional `)` closes route through
    // TryReportMissingClosingDelimiter (the deferred closing-delimiter family); ConsumeToken here reproduces
    // the CLOSED case byte-exact and the corpus keeps them closed.
    func ParsePrimaryPattern(): Pattern? {
        line := Current().Line
        column := Current().Column

        // List pattern `[p, .., p]` (Parser.cs :3341).
        if Check(TokenType.LeftBracket) {
            Advance()
            listElements := new List<Pattern>()
            listDeclined := false
            if !Check(TokenType.RightBracket) {
                listParsing := true
                while listParsing {
                    if Check(TokenType.DotDot) {
                        Advance()
                        // slice `..` (optionally `.. name`)
                        sliceBinding: string? = null
                        if Check(TokenType.Identifier) {
                            sliceBinding = Advance().Value
                        }
                        // `new SlicePattern(bindingName, line, column)` (Parser.cs :3373) — anchored on the
                        // PRIMARY-PATTERN entry position (the `[`), not the `..`.
                        listElements.Add(new SlicePattern(sliceBinding, line, column))
                    } else {
                        listElement := ParsePattern()
                        if listElement == null {
                            listDeclined = true
                        } else {
                            listElements.Add(listElement)
                        }
                    }
                    if Check(TokenType.Comma) {
                        Advance()
                    } else {
                        listParsing = false
                    }
                }
            }
            ConsumeToken(TokenType.RightBracket, "Expected ']' after list pattern", "]")
            // `new ListPattern(patterns, line, column)` (Parser.cs :3383).
            if listDeclined {
                return null
            }
            return new ListPattern(listElements, line, column)
        }

        // Positional (tuple) pattern `(p, p)` (Parser.cs :3376).
        if Check(TokenType.LeftParen) {
            Advance()
            positionalElements := new List<Pattern>()
            positionalDeclined := false
            if !Check(TokenType.RightParen) {
                positionalParsing := true
                while positionalParsing {
                    positionalElement := ParsePattern()
                    if positionalElement == null {
                        positionalDeclined = true
                    } else {
                        positionalElements.Add(positionalElement)
                    }
                    if Check(TokenType.Comma) {
                        Advance()
                    } else {
                        positionalParsing = false
                    }
                }
            }
            ConsumeToken(TokenType.RightParen, "Expected ')' after positional pattern", ")")
            // `new PositionalPattern(patterns, line, column)` (Parser.cs :3401).
            if positionalDeclined {
                return null
            }
            return new PositionalPattern(positionalElements, line, column)
        }

        // Literal pattern (Parser.cs :3394): the same primaries the malformed-literal check runs over.
        if Check(TokenType.IntLiteral) || Check(TokenType.CharLiteral) || Check(TokenType.StringLiteral) || Check(TokenType.TripleQuoteStringLiteral) || Check(TokenType.InterpolatedRawStringLiteral) || Check(TokenType.True) || Check(TokenType.False) || Check(TokenType.Null) {
            literalValue := ParsePrimaryExprValue().Node
            // `new LiteralPattern(literal, line, column)` (Parser.cs :3409).
            if literalValue == null {
                return null
            }
            return new LiteralPattern(literalValue, line, column)
        }

        // Object pattern without a type name `{ Prop: p }` (Parser.cs :3402).
        if Check(TokenType.LeftBrace) {
            objectProperties := ParsePropertyPatterns()
            // `new ObjectPattern(props, line, column)` (Parser.cs :3416).
            if objectProperties == null {
                return null
            }
            return new ObjectPattern(objectProperties, line, column)
        }

        // Identifier-led: qualified name → union-case / type / identifier pattern (Parser.cs :3409).
        if Check(TokenType.Identifier) {
            // Stage N+1c tranche 11: an `<error>` segment is Parser.cs's own placeholder — the dotted name
            // simply carries it (:3414-3417), no decline.
            patternName := Advance().Value
            // first name segment
            while Check(TokenType.Dot) {
                // qualified name `A.B.C` (Parser.cs :3414)
                Advance()
                segment := ConsumeIdentifier("Expected identifier after '.'")
                patternName = patternName + "." + segment
            }
            if Check(TokenType.LeftBrace) {
                // union-case pattern with properties (Parser.cs :3421)
                caseProperties := ParsePropertyPatterns()
                // `new UnionCasePattern(name, props, line, column)` (Parser.cs :3435).
                if caseProperties == null {
                    return null
                }
                return new UnionCasePattern(patternName, caseProperties, line, column)
            }
            if Check(TokenType.Identifier) {
                // type pattern `TypeName binding` (Parser.cs :3429)
                bindingName := Advance().Value
                // `new TypePattern(new SimpleTypeReference(name), bindingName, line, column)` (:3444) — the
                // type reference carries NO position (the ctor's Line/Column defaults) and an invalid Span.
                return new TypePattern(new SimpleTypeReference(patternName, 0, 0), bindingName, line, column)
            }
            // `new IdentifierPattern(name, line, column)` (Parser.cs :3448).
            return new IdentifierPattern(patternName, line, column)
        }

        // Terminal (Parser.cs :3440): not a valid pattern. Does NOT advance (leaves the offender in place,
        // exactly as Parser.cs, so a following per-case Consume sees the same token under the same panic).
        suggestions := new List<string>()
        suggestions.Add("Literal pattern: case 5 => ...")
        suggestions.Add("Identifier pattern: case x => ...")
        suggestions.Add("Type pattern: case int x => ...")
        suggestions.Add("Object pattern: case { Name: \"John\" } => ...")
        Report(ErrorCode.InvalidSyntax, "Invalid pattern. Got '" + Current().Value + "'", line, column, "I couldn't recognize this as a valid pattern for matching.", "Patterns can be literals, identifiers, types, or destructuring patterns.", suggestions, Current().Value.Length)
        // Stage N+1c tranche 11: Parser.cs returns the synthetic `new IdentifierPattern("<error>", line,
        // column)` placeholder (:3467).
        return new IdentifierPattern("<error>", line, column)
    }

    // Parser.cs ParsePropertyPatterns (:3459): `{ Name: p, Other }`. Reached only when the caller has
    // already seen `{`, so the leading ConsumeToken(LeftBrace) always advances. The property-NAME site
    // funnels through ConsumeIdentifier (its reserved-keyword NL109 / found-other NL102 variants), and the
    // closing `}` through ConsumeToken(RightBrace), which takes the standard Consume path (RightBrace is NOT
    // in TryReportMissingClosingDelimiter) and consults GetHintForMissingToken(RightBrace).
    func ParsePropertyPatterns(): List<PropertyPattern>? {
        ConsumeToken(TokenType.LeftBrace, "Expected '{'", "{")
        properties := new List<PropertyPattern>()
        propertiesDeclined := false
        while !Check(TokenType.RightBrace) && !IsAtEnd() {
            startPosition := Position
            propertyToken := Current()
            propertyName := ConsumeIdentifier("Expected property name")
            if Check(TokenType.Colon) {
                Advance()
                nestedPattern := ParsePattern()
                // `new PropertyPattern(propName, pattern, null, propToken.Line, propToken.Column)` (:3487).
                // Stage N+1c tranche 11: an `<error>` property name is Parser.cs's own placeholder.
                if nestedPattern == null {
                    propertiesDeclined = true
                } else {
                    properties.Add(new PropertyPattern(propertyName, nestedPattern, null, propertyToken.Line, propertyToken.Column))
                }
            } else {
                // Implicit binding `{ value }` → `new PropertyPattern(propName, null, null, …)` (:3494).
                properties.Add(new PropertyPattern(propertyName, null, null, propertyToken.Line, propertyToken.Column))
            }
            if !Check(TokenType.RightBrace) {
                if Check(TokenType.Comma) {
                    // Parser.cs Match(Comma) :3489 — optional separator
                    Advance()
                }
            }
            EnsureProgress(startPosition)
        }
        ConsumeToken(TokenType.RightBrace, "Expected '}'", "}")
        if propertiesDeclined {
            return null
        }
        return properties
    }

    // ---- required-expression + operand boundary helpers (Parser.cs :3855 / :3928 / :6908) ----

    // Parser.cs ParseRequiredExpressionAfter (:3855). When the required expression is present, parse it;
    // otherwise report "Expected <what> after '<anchor>'" anchored on the provided span (or the anchor).
    // Stage N+1c tranches 8/11: RETURNS the parsed operand's node (Parser.cs returns `ParseExpression()` on
    // the present path, a synthetic `IdentifierExpression("<error>")` on the missing path — both now
    // reproduced). Statement-context callers ignore the return (a value-returning func may be called as a
    // statement, as ParseExprValue already is); the ternary + field-initializer consumers capture it. The
    // diagnostic stream is unchanged (Report calls are untouched).
    func ParseRequiredExpressionAfter(anchorToken: Token, expectedDescription: string, ownerDescription: string, diagnosticSpan: RecoverySpan?): Expression? {
        if !IsMissingRequiredExpressionBoundary(anchorToken) {
            return ParseExprValue().Node
        }

        markerColumn := anchorToken.Column + MaxInt(1, anchorToken.Value.Length)
        underlineAnchor := ShouldUnderlineAnchorForMissingRequiredExpression(anchorToken)
        fallback := SpanFromToken(anchorToken)
        // DiagnosticSpanFromToken(anchorToken)
        if !underlineAnchor {
            fallback = new RecoverySpan(anchorToken.Line, markerColumn, 1)
        }
        span := diagnosticSpan ?? fallback

        suggestions := new List<string>()
        suggestions.Add("Add " + expectedDescription + " after '" + anchorToken.Value + "'")
        suggestions.Add("Remove '" + anchorToken.Value + "' until the expression is ready")
        Report(ErrorCode.ExpectedToken, "Expected " + expectedDescription + " after '" + anchorToken.Value + "'", span.Line, span.Column, ownerDescription + " needs " + expectedDescription + " after '" + anchorToken.Value + "'.", "Finish the expression before starting the next statement.", suggestions, span.Length)
        // Stage N+1c tranche 11: Parser.cs returns `new IdentifierExpression("<error>", anchorToken.Line,
        // markerColumn)` (:3895).
        return new IdentifierExpression("<error>", anchorToken.Line, markerColumn)
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
    func StripSurroundingQuotes(value: string): string {
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
    // Stage N+1c tranche 10b: `new TestDeclaration(description, body, tableParameters, tableCases,
    // skipReason, line, column)` (Parser.cs :650). The description and the skip reason are the string
    // literal's text with its surrounding quotes TRIMMED (`Trim('"')`, :574/:642); an absent `with`
    // clause leaves BOTH tableParameters and tableCases null (never empty lists).
    func ParseTestDeclaration() {
        line := Current().Line
        column := Current().Column
        ConsumeTestKeyword()
        declined := false
        description := "<error>"

        // Test description must be a string literal (Parser.cs :554).
        if Current().Type != TokenType.StringLiteral {
            descSuggestions := new List<string>()
            descSuggestions.Add("Example: test \"should calculate sum correctly\" { ... }")
            descSuggestions.Add("Example: test \"validates user input\" { ... }")
            Report(ErrorCode.ExpectedToken, "Expected string literal for test description. Got '" + Current().Value + "'", Current().Line, Current().Column, "Test declarations require a string literal describing what the test does.", "A test should start with the 'test' keyword followed by a string in quotes.", descSuggestions, Current().Value.Length)
            // Stage N+1c tranche 11: Parser.cs stores the synthetic "<error>" description (:569) and still
            // builds the TestDeclaration around it — no decline.
            if !IsAtEnd() {
                Advance()
            }
        } else {
            // skip the invalid token (Parser.cs :570)

            // Parser.cs :574 uses `Current.Value.Trim('"')`, which strips EVERY leading and trailing quote
            // — not a paired-quote unwrap. On an UNTERMINATED literal (a file being edited) the two differ,
            // so this routes through the shared StripSurroundingQuotes helper (the import-path idiom).
            description = StripSurroundingQuotes(Current().Value)
            Advance()
        }

        // Table-driven test syntax `with (params) [ (row), … ]` (Parser.cs :582). The two table lists are
        // bound as NON-nullable `:=` locals and only read on the hasTable branch below — an explicitly-typed
        // `List<List<Expression> >?` local is a recorded columnar-emitter gap (nullable generic-list locals).
        hasTable := false
        tableParameters := new List<Parameter>()
        tableCases := NewTableCases()
        if Check(TokenType.With) {
            hasTable = true
            Advance()
            // consume 'with'
            tableParameters = ParseParameterListRecovery()
            if !ParamListMaterializable {
                declined = true
            }

            ConsumeToken(TokenType.LeftBracket, "Expected '[' to start test cases", "[")
            rows := NewTableCases()
            while !Check(TokenType.RightBracket) && !IsAtEnd() {
                rowStartPosition := Position
                ConsumeToken(TokenType.LeftParen, "Expected '(' to start test case row", "(")
                row := new List<Expression>()
                while !Check(TokenType.RightParen) && !IsAtEnd() {
                    itemStartPosition := Position
                    rowItem := ParseExprValue().Node
                    // Parser.cs ParseExpression (:596)
                    if rowItem == null {
                        declined = true
                    } else {
                        row.Add(rowItem)
                    }
                    if !Check(TokenType.RightParen) {
                        if Check(TokenType.Comma) {
                            // Parser.cs Match(Comma) (:598)
                            Advance()
                        }
                    }

                    // If we didn't make progress (a token no expression can start, e.g. the body '{'),
                    // bail out so ConsumeToken(')') reports it (Parser.cs :600).
                    if Position == itemStartPosition {
                        break
                    }
                }
                ConsumeToken(TokenType.RightParen, "Expected ')' to end test case row", ")")
                rows.Add(row)
                if !Check(TokenType.RightBracket) {
                    if Check(TokenType.Comma) {
                        // Parser.cs Match(Comma) (:603)
                        Advance()
                    }
                }

                // If the whole row made no progress, bail out so ConsumeToken(']') reports it (Parser.cs :613).
                if Position == rowStartPosition {
                    break
                }
            }
            ConsumeToken(TokenType.RightBracket, "Expected ']' to end test cases", "]")
            tableCases = rows
        }

        // Skip modifier `skip "reason"` (Parser.cs :611). The invalid-reason report does NOT skip the
        // offender (matching Parser.cs), so a following block/EOF continues from that token.
        skipReason: string? = null
        if Current().Type == TokenType.Identifier && Current().Value == "skip" {
            Advance()
            // consume 'skip'
            if Current().Type != TokenType.StringLiteral {
                skipSuggestions := new List<string>()
                skipSuggestions.Add("Example: test \"my test\" skip \"needs network\" { ... }")
                Report(ErrorCode.ExpectedToken, "Expected string literal for skip reason. Got '" + Current().Value + "'", Current().Line, Current().Column, "The 'skip' modifier requires a string explaining why the test is skipped.", "Add a reason string after 'skip'.", skipSuggestions, Current().Value.Length)
            } else {
                // Parser.cs :642 `Current.Value.Trim('"')` — same all-quote strip as the description.
                skipReason = StripSurroundingQuotes(Current().Value)
                Advance()
            }
        }

        // Test body (Parser.cs :637). Owner span = the `test` keyword (line, column, "test".Length == 4).
        body := ParseBlock(new RecoverySpan(line, column, MaxInt(1, 4)))
        if declined || body == null {
            return
        }
        // An ABSENT `with` clause leaves BOTH lists null (Parser.cs :579-580), never empty lists.
        if hasTable {
            AddDeclaration(new TestDeclaration(description, body, tableParameters, tableCases, skipReason, line, column))
        } else {
            AddDeclaration(new TestDeclaration(description, body, NoTableParameters(), NoTableCases(), skipReason, line, column))
        }
    }

    // Parser.cs ParseSetupDeclaration (:695): advance past `setup`, then the block body (owner span =
    // the `setup` keyword, length 5). No own error site beyond the block.
    // Stage N+1c tranche 10b: `new SetupDeclaration(body, line, column)` (Parser.cs :700).
    func ParseSetupDeclaration() {
        line := Current().Line
        column := Current().Column
        Advance()
        // consume 'setup'
        body := ParseBlock(new RecoverySpan(line, column, MaxInt(1, 5)))
        if body != null {
            AddDeclaration(new SetupDeclaration(body, line, column))
        }
    }

    // Parser.cs ParseTeardownDeclaration (:710): advance past `teardown`, then the block body (owner
    // span = the `teardown` keyword, length 8). No own error site beyond the block.
    // Stage N+1c tranche 10b: `new TeardownDeclaration(body, line, column)` (Parser.cs :715).
    func ParseTeardownDeclaration() {
        line := Current().Line
        column := Current().Column
        Advance()
        // consume 'teardown'
        body := ParseBlock(new RecoverySpan(line, column, MaxInt(1, 8)))
        if body != null {
            AddDeclaration(new TeardownDeclaration(body, line, column))
        }
    }

    // Parser.cs ParseAttributes (:269): a loop of `[ Name(.Name)* (args)? ]`. The name reuses the
    // ConsumeAttributeIdentifier (Identifier/Alloc/Allow, else the owned ConsumeIdentifier NL102); the
    // optional `(args)` reuses the Stage-10 ParseArgumentList; the closing `]` routes through the
    // Stage-9 closing-delimiter recovery (ConsumeToken → NL108 when unclosed, else the plain NL102).
    // Stage N+1c tranche 4: return the materialized `AttributeNode` list (Parser.cs :292 —
    // `new AttributeNode(name, args, attributeLine, attributeColumn)`; the line is the `[` line, the column is
    // the `[` column + 1 — Parser.cs :274-275). Tranche 9b: the ARGUMENT-BEARING shape now materializes too —
    // `ParseArgumentList` returns the byte-exact `List<Argument>` Parser.cs stores (:284/:288), so
    // `[Attr(1)]` / `[Attr(x: 1)]` land in the declaration's Attributes list; only an argument list that
    // DECLINES (a still-deferred argument value) or an `<error>` name clears `AttributesMaterializable`, and
    // the enclosing declaration then declines (no-stub — never partially compared). Callers capture
    // `AttributesMaterializable` into a local immediately after this returns.
    func ParseAttributes(): List<AttributeNode> {
        AttributesMaterializable = true
        attributes := new List<AttributeNode>()
        while Check(TokenType.LeftBracket) {
            attrLine := Current().Line
            attrColumn := Current().Column + 1
            // The `[` itself, which `attrColumn` deliberately steps past (Parser.cs anchors the node on
            // the NAME). The span the formatter re-emits starts here.
            openLine := Current().Line
            openColumn := Current().Column
            // Parser.cs :275
            Advance()
            // consume '['
            name := ConsumeAttributeIdentifier("Expected attribute name")
            while Check(TokenType.Dot) {
                Advance()
                // consume '.'
                name = name + "." + ConsumeAttributeIdentifier("Expected identifier after '.'")
            }
            attributeArguments := new List<Argument>()
            argumentsDeclined := false
            if Check(TokenType.LeftParen) {
                Advance()
                // consume '('
                parsedArguments := ParseArgumentList()
                if parsedArguments == null {
                    argumentsDeclined = true
                } else {
                    attributeArguments = parsedArguments
                }
            }
            closed := Check(TokenType.RightBracket)
            ConsumeToken(TokenType.RightBracket, "Expected ']'", "]")
            attributeSource: string? = null
            if closed {
                attributeSource = AttributeSourceText(openLine, openColumn, Previous())
            }
            if argumentsDeclined {
                AttributesMaterializable = false
            } else {
                // declined-argument attribute → decline the declaration

                // Stage N+1c tranche 11: an `<error>` attribute NAME is Parser.cs's own placeholder and it
                // still builds the AttributeNode around it (:5292).
                attributes.Add(new AttributeNode(name, attributeArguments, attrLine, attrColumn, attributeSource))
            }
        }
        return attributes
    }

    // THE ATTRIBUTE'S OWN SOURCE TEXT, `[` THROUGH `]` INCLUSIVE, OR NULL WHEN THE SPAN CANNOT BE READ.
    //
    // The formatter re-emits this verbatim, because an attribute's arguments are ANNOTATION, not code:
    // they are stored as expressions, so `[aotSafe(mono-wasm)]` re-renders as a subtraction, and their
    // line structure is not stored at all, so a five-line `[trusted(...)]` re-renders as one line and
    // the census that reads it finds nothing.
    //
    // EVERY FAILURE ANSWERS NULL RATHER THAN A WRONG SPAN, and the formatter then falls back to
    // synthesising the attribute from its parts. The last guard is the load-bearing one: the slice must
    // actually begin with `[` and end with `]`, which is what makes a line/column-to-offset mismatch
    // (a `\r\n` file, say) degrade to the fallback instead of writing a mangled span into the user's
    // source.
    func AttributeSourceText(openLine: int, openColumn: int, closeToken: Token): string? {
        if closeToken.Type != TokenType.RightBracket {
            return null
        }

        startOffset := 0
        if !CodeIntelligenceTextUtilities.TryGetEditorOffset(Source, openLine - 1, openColumn - 1, out startOffset) {
            return null
        }

        endOffset := 0
        if !CodeIntelligenceTextUtilities.TryGetEditorOffset(Source, closeToken.Line - 1, closeToken.Column - 1, out endOffset) {
            return null
        }

        if endOffset < startOffset {
            return null
        }

        if endOffset >= Source.Length {
            return null
        }

        text := Source.Substring(startOffset, endOffset - startOffset + 1)
        if text.Length < 2 {
            return null
        }

        if text[0] != '[' {
            return null
        }

        if text[text.Length - 1] != ']' {
            return null
        }

        return text
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

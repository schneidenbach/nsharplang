namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for WHAT A STRUCT-OF-ARRAYS VALUE MAY NOT DO.
//
// Every member of this family was `private` in `Analyzer.cs` and reached from 147 call sites across
// forty-odd statement and expression arms, so its behaviour was pinned only indirectly — through
// whichever arm happened to have an end-to-end fixture. This is its first DIRECT pinning, written
// around the four things the family is easy to get wrong.
//
// (1) THE TWO QUESTIONS HAVE DIFFERENT INPUTS. The row question reads a TYPE; the column question
// reads SYNTAX and a registry. A change that "unified" them would break the column question, because
// no `TypeInfo` says "this is a column".
//
// (2) THE REGISTRY IS REFERENCE-KEYED, and that is behaviour. Two `table.x` reads at different places
// are different nodes; recording one must not answer for the other. An equality-keyed set would
// silently widen every direct-column report.
//
// (3) THE FALLBACK PROBE STOPS AT ONE LEVEL. `a.b.c` is not a column read just because `a.b` is —
// the C# switch had no recursion into the receiver of a non-matching member access, and reintroducing
// one would report the wrong node.
//
// (4) THE THREE TRANSPARENT WRAPPERS ARE SEEN THROUGH, and the RECEIVER walk sees through one more:
// a `ref` binding. Both lists are exact.
class SoaEscHarness {
    Escape: AnalyzerSoaEscape
    Scopes: AnalyzerScopeStack
    Errors: List<CompilerError>
    Model: SemanticModel

    constructor(
        escape: AnalyzerSoaEscape,
        scopes: AnalyzerScopeStack,
        errors: List<CompilerError>,
        model: SemanticModel
    ) {
        Escape = escape
        Scopes = scopes
        Errors = errors
        Model = model
    }
}

func SoaEscPath(): string {
    return Path.GetFullPath("soa-escape-contract.nl")
}

func SoaEscHarnessWith(sourceText: string?): SoaEscHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(SoaEscPath(), sourceText)
    spans := new AnalyzerDiagnosticSpans(diagnostics)
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    return new SoaEscHarness(escape, scopes, errors, model)
}

func SoaEscDefault(): SoaEscHarness {
    return SoaEscHarnessWith(null)
}

// ── the table declaration every contract measures against ────────────────────

func SoaEscColumns(): List<SoaColumnInfo> {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int", 0, 0), 1, 1))
    columns.Add(new SoaColumnInfo("y", new SimpleTypeReference("int", 0, 0), 2, 1))
    return columns
}

func SoaEscDeclaration(): SoaRecordDeclarationInfo {
    return new SoaRecordDeclarationInfo("Points", SoaEscColumns(), 1, 1)
}

func SoaEscTableType(): TypeInfo {
    table: TypeInfo = new SoaRecordTypeInfo(SoaEscDeclaration())
    return table
}

func SoaEscRowType(): TypeInfo {
    row: TypeInfo = new SoaRowTypeInfo(SoaEscDeclaration())
    return row
}

// ── AST builders ─────────────────────────────────────────────────────────────

func SoaEscName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 4, 9)
}

func SoaEscAccess(receiver: Expression, memberName: string): MemberAccessExpression {
    return new MemberAccessExpression(receiver, memberName, false, 4, 9)
}

func SoaEscColumnRead(): MemberAccessExpression {
    return SoaEscAccess(SoaEscName("points"), "x")
}

func SoaEscErrorText(harness: SoaEscHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + "+" + error.Length.ToString()
}

// Declares a name into the harness's scope, which is what makes the DECLARED fallback probe — as
// opposed to the recorded registry — able to answer.
func SoaEscDeclare(harness: SoaEscHarness, name: string, declaredType: TypeInfo) {
    harness.Scopes.Peek().Symbols[name] = declaredType
}

func SoaEscDeclareTable(harness: SoaEscHarness, name: string) {
    SoaEscDeclare(harness, name, SoaEscTableType())
}

func SoaEscFound(harness: SoaEscHarness, expression: Expression): string {
    found := harness.Escape.FindSoaColumnMemberAccess(expression)
    if found == null {
        return "<none>"
    }

    return found.MemberName + "@" + found.Line.ToString() + ":" + found.Column.ToString()
}

// ── the row-view escape ──────────────────────────────────────────────────────

test "THE ROW ESCAPE NAMES THE ACTION AND UNDERLINES THE WHOLE EXPRESSION" {
    harness := SoaEscDefault()

    harness.Escape.ReportSoaRowEscape(SoaEscName("row"), "returned")

    assert harness.Errors.Count == 1
    assert SoaEscErrorText(harness, 0) == "SoA row views cannot be returned; use the table and row index instead|4:9+3"
    assert harness.Errors[0].Suggestion == "Read or write a column with table[index].column in the same expression."
}

test "THE ROW ESCAPE IS ASKED WITH A TYPE, AND ONLY A ROW VIEW ANSWERS YES" {
    harness := SoaEscDefault()

    assert harness.Escape.ReportSoaRowEscapeIfNeeded(SoaEscName("row"), SoaEscRowType(), "thrown")
    assert harness.Errors.Count == 1
    assert SoaEscErrorText(harness, 0) == "SoA row views cannot be thrown; use the table and row index instead|4:9+3"

    // The TABLE is not a row view, and neither is anything else.
    assert !harness.Escape.ReportSoaRowEscapeIfNeeded(SoaEscName("row"), SoaEscTableType(), "thrown")
    assert !harness.Escape.ReportSoaRowEscapeIfNeeded(SoaEscName("row"), BuiltInTypes.Int, "thrown")
    assert !harness.Escape.ReportSoaRowEscapeIfNeeded(SoaEscName("row"), BuiltInTypes.Unknown, "thrown")
    assert harness.Errors.Count == 1
}

test "EVERY ACTION WORD THE ESTATE PASSES REACHES THE MESSAGE VERBATIM" {
    harness := SoaEscDefault()

    harness.Escape.ReportSoaRowEscape(SoaEscName("row"), "used as a foreach collection")
    harness.Escape.ReportSoaRowEscape(SoaEscName("row"), "used as an operator operand")
    harness.Escape.ReportSoaRowEscape(SoaEscName("row"), "stored in a field")

    assert harness.Errors.Count == 3
    assert harness.Errors[0].Message == "SoA row views cannot be used as a foreach collection; use the table and row index instead"
    assert harness.Errors[1].Message == "SoA row views cannot be used as an operator operand; use the table and row index instead"
    assert harness.Errors[2].Message == "SoA row views cannot be stored in a field; use the table and row index instead"
}

// ── the column registry ──────────────────────────────────────────────────────

test "AN UNRECORDED MEMBER ACCESS ON AN UNDECLARED RECEIVER IS NOT A COLUMN" {
    harness := SoaEscDefault()

    assert SoaEscFound(harness, SoaEscColumnRead()) == "<none>"
    assert !harness.Escape.IsSoaColumnMemberAccess(SoaEscColumnRead())
    assert harness.Errors.Count == 0
}

test "THE REGISTRY IS REFERENCE-KEYED: RECORDING ONE READ DOES NOT ANSWER FOR ANOTHER" {
    harness := SoaEscDefault()
    recorded := SoaEscColumnRead()
    twin := SoaEscColumnRead()

    harness.Escape.RecordColumnMemberAccess(recorded)

    assert harness.Escape.IsSoaColumnMemberAccess(recorded)
    // Same receiver name, same member name, same line and column — a DIFFERENT read.
    assert !harness.Escape.IsSoaColumnMemberAccess(twin)
}

test "BeginAnalysis CLEARS THE REGISTRY" {
    harness := SoaEscDefault()
    recorded := SoaEscColumnRead()
    harness.Escape.RecordColumnMemberAccess(recorded)
    assert harness.Escape.IsSoaColumnMemberAccess(recorded)

    harness.Escape.BeginAnalysis()

    assert !harness.Escape.IsSoaColumnMemberAccess(recorded)
}

test "THE RECORDED VERDICT IS READ THROUGH THE THREE TRANSPARENT WRAPPERS" {
    harness := SoaEscDefault()
    recorded := SoaEscColumnRead()
    harness.Escape.RecordColumnMemberAccess(recorded)

    assert harness.Escape.IsSoaColumnMemberAccess(new ParenthesizedExpression(recorded, 4, 8))
    assert harness.Escape.IsSoaColumnMemberAccess(new CheckedExpression(recorded, 4, 8))
    assert harness.Escape.IsSoaColumnMemberAccess(new UncheckedExpression(recorded, 4, 8))
    assert SoaEscFound(harness, new ParenthesizedExpression(recorded, 4, 8)) == "x@4:9"

    // And through a nest of them.
    nested: Expression = new ParenthesizedExpression(new CheckedExpression(recorded, 4, 8), 4, 7)
    assert harness.Escape.IsSoaColumnMemberAccess(nested)
}

test "IsSoaColumnMemberAccess READS THE REGISTRY ALONE, WHERE THE PROBE ALSO ASKS THE DECLARATION" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")
    read := SoaEscColumnRead()

    // The declared fallback answers the probe...
    assert SoaEscFound(harness, read) == "x@4:9"
    // ...and the registry reader still says no, because nothing recorded THIS node.
    assert !harness.Escape.IsSoaColumnMemberAccess(read)
}

// ── the declared fallback probe ──────────────────────────────────────────────

test "A DECLARED TABLE'S COLUMN ANSWERS THE PROBE WITHOUT EVER BEING RECORDED" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")

    assert SoaEscFound(harness, SoaEscAccess(SoaEscName("points"), "x")) == "x@4:9"
    assert SoaEscFound(harness, SoaEscAccess(SoaEscName("points"), "y")) == "y@4:9"
    // A name that is not one of the declared columns is not a column.
    assert SoaEscFound(harness, SoaEscAccess(SoaEscName("points"), "z")) == "<none>"
    // A receiver that is not a table declares nothing.
    assert SoaEscFound(harness, SoaEscAccess(SoaEscName("other"), "x")) == "<none>"
}

test "THE PROBE DOES NOT RECURSE INTO THE RECEIVER OF A NON-MATCHING MEMBER ACCESS" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")

    // `points.x` IS a column; `points.x.Length` is NOT, and must not answer with `points.x`.
    outer := SoaEscAccess(SoaEscAccess(SoaEscName("points"), "x"), "Length")
    assert SoaEscFound(harness, outer) == "<none>"
}

test "THE RECEIVER WALK SEES THROUGH THE THREE WRAPPERS AND THROUGH A ref BINDING" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")

    assert SoaEscFound(
        harness,
        SoaEscAccess(new ParenthesizedExpression(SoaEscName("points"), 4, 8), "x")
    ) == "x@4:9"
    assert SoaEscFound(
        harness,
        SoaEscAccess(new CheckedExpression(SoaEscName("points"), 4, 8), "x")
    ) == "x@4:9"
    assert SoaEscFound(
        harness,
        SoaEscAccess(new UncheckedExpression(SoaEscName("points"), 4, 8), "x")
    ) == "x@4:9"

    // A `ref` to a table is a table.
    byRef := SoaEscDefault()
    byRefTable: TypeInfo = new ByRefTypeInfo(SoaEscTableType())
    SoaEscDeclare(byRef, "points", byRefTable)
    assert SoaEscFound(byRef, SoaEscAccess(SoaEscName("points"), "x")) == "x@4:9"
}

test "A NULLABLE TABLE IS STILL A TABLE TO THE RECEIVER WALK" {
    harness := SoaEscDefault()
    nullableTable: TypeInfo = new NullableTypeInfo(SoaEscTableType())
    SoaEscDeclare(harness, "points", nullableTable)

    assert SoaEscFound(harness, SoaEscAccess(SoaEscName("points"), "x")) == "x@4:9"
}

test "A RECEIVER THAT IS NOT AN IDENTIFIER ANSWERS NOTHING" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")

    // An indexed receiver is a ROW, not a table, and the receiver walk has no arm for it.
    indexed: Expression = new IndexAccessExpression(
        SoaEscName("points"),
        new IntLiteralExpression("0", 4, 16),
        false,
        4,
        9
    )
    assert SoaEscFound(harness, SoaEscAccess(indexed, "x")) == "<none>"
}

// ── the direct-column escape ─────────────────────────────────────────────────

test "THE COLUMN ESCAPE NAMES THE COLUMN AND UNDERLINES THE WHOLE EXPRESSION" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")

    assert harness.Escape.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(
        SoaEscColumnRead(),
        "returned"
    )

    assert harness.Errors.Count == 1
    assert SoaEscErrorText(harness, 0) == "SoA table member 'x' cannot be returned directly|4:9+8"
    assert harness.Errors[0].Suggestion == "Use table.column[row] for element access, Table.wrap for table views, or Array.Fill, Array.Copy, and Array.Clear for supported whole-column operations."
}

test "THE COLUMN ESCAPE IS SILENT FOR ANYTHING THAT IS NOT A COLUMN READ" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")

    assert !harness.Escape.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(
        SoaEscName("points"),
        "returned"
    )
    assert !harness.Escape.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(
        SoaEscAccess(SoaEscName("points"), "z"),
        "returned"
    )
    assert harness.Errors.Count == 0
}

test "A WRAPPED COLUMN REPORTS, AND THE SPAN UNWRAPS TO THE READ ITSELF" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")

    // The wrapper is what escaped; the span reader unwraps parentheses, so the squiggle lands on the
    // read rather than on the bracket — which is what the estate's other reports do too.
    wrapped: Expression = new ParenthesizedExpression(SoaEscColumnRead(), 4, 8)
    assert harness.Escape.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(wrapped, "spread")

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be spread directly"
    assert harness.Errors[0].Column == 9
}

test "THE RAW COLUMN REPORTER TAKES THE SPAN AND THE NAME FROM DIFFERENT NODES" {
    harness := SoaEscDefault()

    harness.Escape.ReportUnsupportedSoaDirectColumnValueEscape(
        SoaEscName("elsewhere"),
        SoaEscColumnRead(),
        "used as the receiver for 'Fill'"
    )

    assert harness.Errors.Count == 1
    assert SoaEscErrorText(harness, 0) == "SoA table member 'x' cannot be used as the receiver for 'Fill' directly|4:9+9"
}

test "A RECORDED COLUMN REPORTS EVEN WHEN NO TABLE IS DECLARED ANYWHERE" {
    harness := SoaEscDefault()
    recorded := SoaEscColumnRead()
    harness.Escape.RecordColumnMemberAccess(recorded)

    assert harness.Escape.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(recorded, "printed")
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be printed directly"
}

test "BOTH REPORTS APPEND TO THE SAME LIST IN CALL ORDER" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")

    harness.Escape.ReportSoaRowEscape(SoaEscName("row"), "printed")
    harness.Escape.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(SoaEscColumnRead(), "printed")

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "SoA row views cannot be printed; use the table and row index instead"
    assert harness.Errors[1].Message == "SoA table member 'x' cannot be printed directly"
}

test "BOTH REPORTS CARRY NL103, THE InvalidSyntax CODE" {
    harness := SoaEscDefault()
    SoaEscDeclareTable(harness, "points")

    harness.Escape.ReportSoaRowEscape(SoaEscName("row"), "printed")
    harness.Escape.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(SoaEscColumnRead(), "printed")

    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert harness.Errors[1].Code == ErrorCode.InvalidSyntax
    assert harness.Errors[0].DiagnosticId == "NL103"
    assert harness.Errors[1].DiagnosticId == "NL103"
}

namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for WHAT IT MEANS FOR A CONDITION TO BE A CONDITION.
//
// The five arms this family serves were five hand-written copies of the same three-part gate in
// `Analyzer.cs`, and nothing pinned them against each other — each was covered only by whichever
// end-to-end fixture happened to reach it, so a change to one could silently diverge from the other
// four. These contracts are written around the five things the family is easy to get wrong.
//
// (1) BOTH ESCAPES ALWAYS RUN. The row report does not short-circuit the column probe. The C# arms
// wrote two separate locals and then read both, so a value that is a row view AND a syntactic column
// read produced TWO diagnostics; an `if`-chain refactor would silently drop one of them.
//
// (2) EITHER ESCAPE SILENCES THE BOOLEAN QUESTION, and that is not an optimisation: a value the
// analyzer has just refused to let leave its record must not ALSO be told it is the wrong type.
//
// (3) THE TEST IS IDENTITY, NOT ASSIGNABILITY — for four of the five. `bool?` is not a boolean
// condition. The `match` guard is the exception, deliberately, and the two must not be unified.
//
// (4) THE `if` ARM REPORTS RICHLY AND FALLS BACK. Same test, same suppressions, a different report
// — and the fallback wording is exactly the plain reporter's with `an 'if'` as the owner.
//
// (5) THE SUPPRESSIONS ARE THE SAME IN ALL FIVE. `unknown` and a parser error placeholder both mean
// the developer has already been told what is wrong.

class CondHarness {
    Conditions: AnalyzerBooleanConditions
    Escape: AnalyzerSoaEscape
    Scopes: AnalyzerScopeStack
    Assignability: AnalyzerAssignability
    Errors: List<CompilerError>

    constructor(
        conditions: AnalyzerBooleanConditions,
        escape: AnalyzerSoaEscape,
        scopes: AnalyzerScopeStack,
        assignability: AnalyzerAssignability,
        errors: List<CompilerError>) {
        Conditions = conditions
        Escape = escape
        Scopes = scopes
        Assignability = assignability
        Errors = errors
    }
}

func CondPath(): string {
    return Path.GetFullPath("boolean-condition-contract.nl")
}

// Four lines, so that a condition anchored at line 4 has a snippet to render and one anchored at a
// line the text does not reach has none.
func CondSourceText(): string {
    return "func main() {\n    count := 3\n    // a comment\n    if count { }\n}\n"
}

func CondAssignability(
    provider: AnalyzerProjectSourceProvider,
    diagnostics: AnalyzerDiagnosticSink): AnalyzerAssignability {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        diagnostics,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        model,
        new BindingMap())
    resolver.BeginAnalysis(CondPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    return new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
}

func CondHarnessWith(sourceText: string?): CondHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(CondPath(), sourceText)
    spans := new AnalyzerDiagnosticSpans(diagnostics)
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    conditions := new AnalyzerBooleanConditions(diagnostics, spans, escape)
    return new CondHarness(
        conditions,
        escape,
        scopes,
        CondAssignability(provider, diagnostics),
        errors)
}

func CondDefault(): CondHarness {
    return CondHarnessWith(null)
}

// ── AST and type builders ────────────────────────────────────────────────────

func CondName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 4, 8)
}

func CondColumns(): List<SoaColumnInfo> {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int", 0, 0), 1, 1))
    return columns
}

func CondDeclaration(): SoaRecordDeclarationInfo {
    return new SoaRecordDeclarationInfo("Points", CondColumns(), 1, 1)
}

func CondTableType(): TypeInfo {
    table: TypeInfo = new SoaRecordTypeInfo(CondDeclaration())
    return table
}

func CondRowType(): TypeInfo {
    row: TypeInfo = new SoaRowTypeInfo(CondDeclaration())
    return row
}

// A member access the harness's scope can resolve to a column, so the syntactic probe answers YES
// without the member walk having recorded anything.
func CondColumnRead(harness: CondHarness): MemberAccessExpression {
    harness.Scopes.Peek().Symbols["points"] = CondTableType()
    return new MemberAccessExpression(CondName("points"), "x", false, 4, 8)
}

func CondErrorText(harness: CondHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString()
        + "+" + error.Length.ToString()
}

func CondPlaceholder(): IdentifierExpression {
    return new IdentifierExpression(AnalyzerParserErrorPlaceholders.PlaceholderName(), 4, 8)
}

// ── the plain report: `while`, `for`, the ternary ────────────────────────────

test "THE PLAIN REPORT NAMES THE OWNER AND THE TYPE AND UNDERLINES THE CONDITION" {
    harness := CondDefault()

    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("count"), "a 'while' loop", "used as a 'while' condition", BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert CondErrorText(harness, 0)
        == "The condition in a 'while' loop must be a boolean, but I found 'int'|4:8+5"
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
}

test "ALL THREE PLAIN OWNERS REACH THE WORDING VERBATIM" {
    harness := CondDefault()

    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("count"), "a 'while' loop", "used as a 'while' condition", BuiltInTypes.Int)
    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("count"), "a 'for' loop", "used as a 'for' condition", BuiltInTypes.String)
    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("count"), "a ternary expression", "used as a ternary condition", BuiltInTypes.Double)

    assert harness.Errors.Count == 3
    assert harness.Errors[0].Message
        == "The condition in a 'while' loop must be a boolean, but I found 'int'"
    assert harness.Errors[1].Message
        == "The condition in a 'for' loop must be a boolean, but I found 'string'"
    assert harness.Errors[2].Message
        == "The condition in a ternary expression must be a boolean, but I found 'double'"
}

test "A BOOLEAN CONDITION IS SILENT, AND THE TEST IS IDENTITY RATHER THAN ASSIGNABILITY" {
    harness := CondDefault()

    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("flag"), "a 'while' loop", "used as a 'while' condition", BuiltInTypes.Bool)
    assert harness.Errors.Count == 0

    // `bool?` is NOT a boolean condition. Neither is anything that merely converts to one.
    nullableBool: TypeInfo = new NullableTypeInfo(BuiltInTypes.Bool)
    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("flag"), "a 'while' loop", "used as a 'while' condition", nullableBool)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "The condition in a 'while' loop must be a boolean, but I found 'bool?'"
}

test "A CONDITION THAT ALREADY CARRIES ITS OWN COMPLAINT IS NOT COMPLAINED ABOUT TWICE" {
    harness := CondDefault()

    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("count"), "a 'for' loop", "used as a 'for' condition", BuiltInTypes.Unknown)
    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondPlaceholder(), "a 'for' loop", "used as a 'for' condition", BuiltInTypes.Int)

    assert harness.Errors.Count == 0
}

// ── the escape gate, which is the part no driver can see ─────────────────────

test "A ROW VIEW CONDITION IS TOLD ONCE, AND NOT ALSO TOLD IT IS NOT A BOOLEAN" {
    harness := CondDefault()

    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("row"), "a 'while' loop", "used as a 'while' condition", CondRowType())

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "SoA row views cannot be used as a 'while' condition; use the table and row index instead"
}

test "A DIRECT COLUMN CONDITION IS TOLD ONCE, AND NOT ALSO TOLD IT IS NOT A BOOLEAN" {
    harness := CondDefault()
    column := CondColumnRead(harness)

    // The column's own type is the plain array type its declaration gives it — an `int[]`, which is
    // not a boolean either. Only the escape is reported.
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)
    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        column, "a 'for' loop", "used as a 'for' condition", arrayType)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "SoA table member 'x' cannot be used as a 'for' condition directly"
}

test "THE ROW REPORT DOES NOT SHORT-CIRCUIT THE COLUMN PROBE" {
    harness := CondDefault()
    column := CondColumnRead(harness)

    // A syntactic column read whose ANSWERED type is a row view asks both questions and is told
    // both things. The five C# arms read two independent locals; an `if`-chain would drop one.
    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        column, "a ternary expression", "used as a ternary condition", CondRowType())

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message
        == "SoA row views cannot be used as a ternary condition; use the table and row index instead"
    assert harness.Errors[1].Message
        == "SoA table member 'x' cannot be used as a ternary condition directly"
}

test "THE ESCAPE ACTION WORD AND THE OWNER NAME ARE DIFFERENT STRINGS" {
    harness := CondDefault()

    // The escape talks about the VALUE; the mismatch talks about the CONSTRUCT. Passing one where
    // the other belongs is the mistake this pins.
    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("row"), "a 'for' loop", "used as a 'for' condition", CondRowType())
    harness.Conditions.ReportConditionTypeMismatchIfNeeded(
        CondName("count"), "a 'for' loop", "used as a 'for' condition", BuiltInTypes.Int)

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message.Contains("used as a 'for' condition")
    assert !harness.Errors[0].Message.Contains("a 'for' loop")
    assert harness.Errors[1].Message.Contains("a 'for' loop")
    assert !harness.Errors[1].Message.Contains("used as a 'for' condition")
}

// ── the `if` arm's richer report ─────────────────────────────────────────────

test "THE `if` CONDITION REPORTS THROUGH THE RICH BUILDER WHEN IT HAS A SNIPPET AND A FILE" {
    harness := CondHarnessWith(CondSourceText())

    harness.Conditions.ReportIfConditionTypeMismatchIfNeeded(CondName("count"), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    error := harness.Errors[0]
    assert error.Code == ErrorCode.TypeMismatch
    // The route that ships says what the plain route says — the rich shape adds to the sentence, it
    // does not replace it with the bare words `Type mismatch`.
    assert error.Message == "The condition in an 'if' must be a boolean, but I found 'int'"
    assert error.ActualType == "int"
    assert error.ExpectedType == "bool"
    assert error.SourceSnippet == "    if count { }"
    assert error.DocsUrl == "https://docs.n-sharp.dev/errors/NL202"
    assert error.HumanExplanation == "I am having trouble with this code on line 4:"
    assert error.Line == 4
    assert error.Column == 8
    assert error.Length == 5
}

test "THE `if` CONDITION FALLS BACK TO THE PLAIN WORDING WITH NO SNIPPET" {
    harness := CondDefault()

    harness.Conditions.ReportIfConditionTypeMismatchIfNeeded(CondName("count"), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert CondErrorText(harness, 0)
        == "The condition in an 'if' must be a boolean, but I found 'int'|4:8+5"
    assert harness.Errors[0].SourceSnippet == null
}

test "THE `if` ARM RUNS THE SAME TEST, THE SAME SUPPRESSIONS AND THE SAME ESCAPE GATE" {
    harness := CondHarnessWith(CondSourceText())

    harness.Conditions.ReportIfConditionTypeMismatchIfNeeded(CondName("flag"), BuiltInTypes.Bool)
    harness.Conditions.ReportIfConditionTypeMismatchIfNeeded(CondName("count"), BuiltInTypes.Unknown)
    harness.Conditions.ReportIfConditionTypeMismatchIfNeeded(CondPlaceholder(), BuiltInTypes.Int)
    assert harness.Errors.Count == 0

    nullableBool: TypeInfo = new NullableTypeInfo(BuiltInTypes.Bool)
    harness.Conditions.ReportIfConditionTypeMismatchIfNeeded(CondName("flag"), nullableBool)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].ActualType == "bool?"

    harness.Conditions.ReportIfConditionTypeMismatchIfNeeded(CondName("row"), CondRowType())
    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message
        == "SoA row views cannot be used as an 'if' condition; use the table and row index instead"
}

// ── the `match` guard, which is the one that differs ─────────────────────────

test "A MATCH GUARD IS MEASURED BY ASSIGNABILITY AND REPORTS UNDER ITS OWN CODE" {
    harness := CondDefault()

    harness.Conditions.ReportMatchGuardTypeMismatchIfNeeded(
        CondName("count"), BuiltInTypes.Int, harness.Assignability)

    assert harness.Errors.Count == 1
    assert CondErrorText(harness, 0)
        == "A match guard must be a boolean, but this expression is 'int'|4:8+5"
    assert harness.Errors[0].Code == ErrorCode.GuardNotBoolean
}

test "A MATCH GUARD ACCEPTS WHAT THE OTHER FOUR REFUSE, AND THAT IS DELIBERATE" {
    harness := CondDefault()

    // `unknown` is assignable to `bool`, so the guard is silent for the SAME reason the other four
    // are — but it reaches that answer through the oracle rather than through a suppression.
    harness.Conditions.ReportMatchGuardTypeMismatchIfNeeded(
        CondName("count"), BuiltInTypes.Unknown, harness.Assignability)
    harness.Conditions.ReportMatchGuardTypeMismatchIfNeeded(
        CondName("flag"), BuiltInTypes.Bool, harness.Assignability)

    assert harness.Errors.Count == 0
}

test "A MATCH GUARD RUNS THE SAME ESCAPE GATE, WITH ITS OWN ACTION WORD" {
    harness := CondDefault()

    harness.Conditions.ReportMatchGuardTypeMismatchIfNeeded(
        CondName("row"), CondRowType(), harness.Assignability)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "SoA row views cannot be used as a match guard; use the table and row index instead"
}

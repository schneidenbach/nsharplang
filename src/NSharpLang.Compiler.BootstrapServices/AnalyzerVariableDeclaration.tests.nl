namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for what a local declaration MEANS.
//
// THE PROTOCOL IS THE CONTRACT, because the driver in `Analyzer.cs` is zero-policy: it switches on
// `Kind`, performs exactly one operation with exactly the carried operands, and hands the answer
// back. So the requests a shape emits — how many, in which ORDER, and with which OPERANDS — are the
// observable behaviour, and every contract below drives the walk the way the driver does.
//
// THE ORDER IS LOAD-BEARING AND IT IS NOT THE OBVIOUS ONE. The type diagnostics land BETWEEN the
// initializer analysis and the SoA escape report; the SoA report lands BEFORE the symbol enters the
// scope; the semantic-model record lands AFTER the scope declaration; and the null state is written
// LAST, onto a name the scope already knows. Getting any of those backwards reorders `_errors` or
// writes a fact about a symbol that does not exist yet, and neither shows up as a crash.
//
// THREE OF THE FIVE OPERATIONS TAKE THE RESOLVED TYPE AS AN OPERAND, and in the inference form that
// type IS the first step's answer — which is why the walk resumes rather than scheduling. The
// contracts pin that by supplying a DIFFERENT type than any annotation and asserting what the later
// steps carry.
//
// THE TWO SoA ESCAPE REPORTS ARE NO LONGER STEPS — they were kinds 2 and 3 until `AnalyzerSoaEscape`
// took the family, and the walk calls them directly now. WHICH of the two the resolved type selects,
// and where in the order they land, are still this walk's decisions; a contract that wants one to
// FIRE builds a real row-view answer or a real declared-table column read and reads the DIAGNOSTIC.
//
// THE CORPUS REACHES ALMOST NONE OF THIS. Over the 72-target corpus this arm runs 27,386 times and
// reports exactly TWICE, always the rich NL202; every declaration in the whole estate is a `let`,
// none is a `const` or a `readonly`, no SoA row is ever stored in a variable and no direct-column
// escape ever fires. So the four other diagnostics, both `const` shapes, the row-view step and the
// declaration-kind arms exist ONLY here and in the fixtures.
class VariableDeclarationHarness {
    Owner: AnalyzerVariableDeclaration
    Scopes: AnalyzerScopeStack
    Context: AnalyzerDeclarationContext
    Diagnostics: AnalyzerDiagnosticSink
    Errors: List<CompilerError>
    Model: SemanticModel
    Steps: List<VdStep>

    constructor(
        owner: AnalyzerVariableDeclaration,
        scopes: AnalyzerScopeStack,
        context: AnalyzerDeclarationContext,
        diagnostics: AnalyzerDiagnosticSink,
        errors: List<CompilerError>,
        model: SemanticModel
    ) {
        Owner = owner
        Scopes = scopes
        Context = context
        Diagnostics = diagnostics
        Errors = errors
        Model = model
        Steps = new List<VdStep>()
    }
}

// Every step the walk asked for, in order, with everything it carried. This is what the driver sees
// and therefore what the contracts read.
class VdStep {
    Kind: int
    Node: Expression?
    Name: string?
    CarriedType: TypeInfo
    ExpectedType: TypeInfo?
    Text: string?
    Line: int
    Column: int
    ErrorsBefore: int

    constructor(
        kind: int,
        node: Expression?,
        name: string?,
        carriedType: TypeInfo,
        expectedType: TypeInfo?,
        text: string?,
        line: int,
        column: int,
        errorsBefore: int
    ) {
        Kind = kind
        Node = node
        Name = name
        CarriedType = carriedType
        ExpectedType = expectedType
        Text = text
        Line = line
        Column = column
        ErrorsBefore = errorsBefore
    }
}

func VdHarness(sourceText: string?): VariableDeclarationHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal)
    )
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(VdPath(), sourceText)
    spans := new AnalyzerDiagnosticSpans(diagnostics)
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        diagnostics,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal),
        model,
        new BindingMap()
    )
    resolver.BeginAnalysis(VdPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    nullFlow := new AnalyzerNullFlow(diagnostics, spans, scopes, context)

    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    return new VariableDeclarationHarness(
        new AnalyzerVariableDeclaration(
            diagnostics,
            spans,
            resolver,
            assignability,
            nullFlow,
            scopes,
            context,
            escape
        ),
        scopes,
        context,
        diagnostics,
        errors,
        model
    )
}

func VdDefault(): VariableDeclarationHarness {
    return VdHarness(null)
}

func VdPath(): string {
    return Path.GetFullPath("variable-declaration-contract.nl")
}

// ── AST builders ──────────────────────────────────────────────────────────

func VdDeclaration(
    name: string,
    typeReference: TypeReference?,
    initializer: Expression?,
    kind: VariableKind
): VariableDeclarationStatement {
    return new VariableDeclarationStatement(name, typeReference, initializer, kind, 7, 5)
}

func VdLet(name: string, typeReference: TypeReference?, initializer: Expression?): VariableDeclarationStatement {
    return VdDeclaration(name, typeReference, initializer, VariableKind.Let)
}

func VdTypeRef(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 7, 12)
}

func VdInt(): IntLiteralExpression {
    return new IntLiteralExpression("42", 7, 20)
}

func VdNull(): NullLiteralExpression {
    return new NullLiteralExpression(7, 20)
}

func VdName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 7, 20)
}

func VdRowType(): SoaRowTypeInfo {
    columns := new List<SoaColumnInfo>()
    return new SoaRowTypeInfo(new SoaRecordDeclarationInfo("Particle", columns, 1, 1))
}

func VdClass(name: string): TypeInfo {
    result: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true
    )
    return result
}

// ── the driver, exactly as `Analyzer.cs` writes it ────────────────────────

// Runs the whole walk, answering every kind-1 step with `answer`, and records what was asked into
// the harness. A null answer means the shape under test has no initializer and the walk never asks.
func VdRun(
    harness: VariableDeclarationHarness,
    declaration: VariableDeclarationStatement,
    answer: TypeInfo?
) {
    steps := harness.Steps
    steps.Clear()
    state := harness.Owner.Begin(declaration)
    step := harness.Owner.NextStep(state)
    while step != null {
        steps.Add(new VdStep(
            step.Kind,
            step.Node,
            step.Name,
            step.CarriedType,
            step.ExpectedType,
            step.Text,
            step.Line,
            step.Column,
            harness.Errors.Count
        ))

        supplied: TypeInfo? = null
        if step.Kind == 1 {
            supplied = answer
        }

        harness.Owner.Supply(state, supplied)
        step = harness.Owner.NextStep(state)
    }
}

// A table declared in the harness's scope, and a `points.x` read against it — the only way to make
// the direct-column escape fire for real now that it is not a driver-answered step.
func VdSoaColumns(): List<SoaColumnInfo> {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int", 0, 0), 1, 1))
    return columns
}

func VdDeclareSoaTable(harness: VariableDeclarationHarness) {
    table: TypeInfo = new SoaRecordTypeInfo(
        new SoaRecordDeclarationInfo("Points", VdSoaColumns(), 1, 1)
    )
    harness.Scopes.Peek().Symbols["points"] = table
}

func VdSoaColumnRead(): Expression {
    read: Expression = new MemberAccessExpression(VdName("points"), "x", false, 7, 20)
    return read
}

func VdKinds(steps: List<VdStep>): string {
    rendered := ""
    index := 0
    while index < steps.Count {
        rendered = rendered + steps[index].Kind.ToString()
        index = index + 1
    }

    return rendered
}

// ── THE STEP PROTOCOL ─────────────────────────────────────────────────────

test "an inferred declaration asks for the initializer, then declares, then records" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    // The escape reports were kinds 2 and 3 and are N#-owned calls now; the numbering keeps its gap.
    assert VdKinds(steps) == "145"
}
test "a declaration with NO initializer never asks for an expression and never asks for an escape" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), null), null)
    steps := harness.Steps

    assert VdKinds(steps) == "45"
}
test "a declaration with neither an annotation nor an initializer still declares and records" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, null), null)
    steps := harness.Steps

    assert VdKinds(steps) == "45"
    assert harness.Errors.Count == 1
}
test "the kind-1 step carries the initializer NODE and nothing else stands in for it" {
    harness := VdDefault()
    initializer := VdInt()

    VdRun(harness, VdLet("x", null, initializer), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[0].Kind == 1
    assert Object.ReferenceEquals(steps[0].Node, initializer)
}
test "the kind-1 step carries the ANNOTATION as the expected type" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[0].Kind == 1
    assert steps[0].ExpectedType != null
    assert BuiltInTypes.Is(steps[0].ExpectedType, BuiltInTypes.Int)
}
test "with no annotation the expected type is NULL rather than unknown" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[0].ExpectedType == null
}
test "only the kind-1 step carries an expected type" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    index := 1
    while index < steps.Count {
        assert steps[index].ExpectedType == null
        index = index + 1
    }
}
test "the escape report carries the SAME initializer node and the analyzer's own wording" {
    harness := VdDefault()
    VdDeclareSoaTable(harness)

    VdRun(harness, VdLet("x", null, VdSoaColumnRead()), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be stored in a variable directly"
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 20
}
test "the declare step carries the declaration's own name, line and column" {
    harness := VdDefault()

    VdRun(harness, VdLet("count", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[1].Kind == 4
    assert steps[1].Name == "count"
    assert steps[1].Line == 7
    assert steps[1].Column == 5
}
test "the declare step carries the declaration kind `local`, so the driver hard-codes nothing" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[1].Text == "local"
}
test "the record step carries the name and the type and no span" {
    harness := VdDefault()

    VdRun(harness, VdLet("total", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[2].Kind == 5
    assert steps[2].Name == "total"
    assert BuiltInTypes.Is(steps[2].CarriedType, BuiltInTypes.Int)
    assert steps[2].Line == 0
    assert steps[2].Column == 0
}
test "`Supply` with a null answer on a kind-1 step leaves the declaration untyped" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), null)
    steps := harness.Steps

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert BuiltInTypes.IsUnknown(steps[1].CarriedType)
}

// ── THE ANSWER IS THE OPERAND: why the walk resumes ───────────────────────

test "with no annotation the DECLARE step is passed the answer the walk did not have at step one" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.String)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[1].CarriedType, BuiltInTypes.String)
}
test "with no annotation the RECORD step is passed the same answer" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.String)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[2].CarriedType, BuiltInTypes.String)
}
test "the answer also CHOOSES which escape report fires — a row view takes the row report" {
    harness := VdDefault()

    rowType: TypeInfo = VdRowType()
    VdRun(harness, VdLet("row", null, VdName("particles")), rowType)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be stored in a variable; use the table and row index instead"
}
test "anything that is not a row view is offered to the direct-column probe instead" {
    harness := VdDefault()
    VdDeclareSoaTable(harness)

    VdRun(harness, VdLet("x", null, VdSoaColumnRead()), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be stored in a variable directly"
}
test "an ANNOTATED declaration takes the row report only when the ANNOTATION is a row view" {
    harness := VdDefault()
    VdDeclareSoaTable(harness)

    // The annotation wins the type, so a row-view ANSWER does not select the row report; the
    // direct-column probe runs and finds the column. The mismatch is reported first, at phase 1.
    rowType: TypeInfo = VdRowType()
    VdRun(harness, VdLet("row", VdTypeRef("int"), VdSoaColumnRead()), rowType)

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[1].Message == "SoA table member 'x' cannot be stored in a variable directly"
}

// ── THE FOUR TYPE OUTCOMES ────────────────────────────────────────────────

test "an annotation WINS the type even when the initializer disagreed" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.String)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[1].CarriedType, BuiltInTypes.Int)
}
test "an annotation with no initializer is the declaration's type" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("string"), null), null)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[0].CarriedType, BuiltInTypes.String)
    assert harness.Errors.Count == 0
}
test "no annotation means the initializer's type is the declaration's type" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Bool)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[1].CarriedType, BuiltInTypes.Bool)
    assert harness.Errors.Count == 0
}
test "a VOID initializer with no annotation falls back to unknown" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Void)
    steps := harness.Steps

    assert BuiltInTypes.IsUnknown(steps[1].CarriedType)
}
test "a VOID initializer under an ANNOTATION is a mismatch, not the void report" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.Void)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[1].CarriedType, BuiltInTypes.Int)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
}
test "neither an annotation nor an initializer falls back to unknown" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, null), null)
    steps := harness.Steps

    assert BuiltInTypes.IsUnknown(steps[0].CarriedType)
}
test "an unresolvable annotation still WINS, because the resolver's answer is the annotation's answer" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("NoSuchType"), null), null)
    steps := harness.Steps

    assert !BuiltInTypes.Is(steps[0].CarriedType, BuiltInTypes.Int)
}

// ── NL202: THE ANNOTATION AND THE VALUE DISAGREE ──────────────────────────

test "an assignable initializer reports NOTHING" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.Int)

    assert harness.Errors.Count == 0
}
test "a non-assignable initializer reports NL202" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
}
test "with no source text the report takes the DETAIL-ONLY shape and names the variable" {
    harness := VdDefault()

    VdRun(harness, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    assert harness.Errors[0].Message == "Variable 'total' is typed as 'int', but the value is 'string'"
}
test "the detail-only shape anchors on the DECLARATION, not on the initializer" {
    harness := VdDefault()

    VdRun(harness, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 5
}
// THE ROUTE THAT SHIPS SAYS THE SAME SENTENCE. `Analyze(unit, path, root, source)` — the only entry
// point `nlc check`, `nlc build` and the language server call — used to collapse this report to the
// bare words `Type mismatch` while the one-argument route nothing ships kept the naming sentence.
// The rich shape now ADDS to that sentence rather than replacing it.
test "with source text the report takes the RICH shape, which is the SAME message plus a docs link" {
    harness := VdHarness("package demo\n\nfunc main() {\n\n\n\n    total: int = 42\n}\n")

    VdRun(harness, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message == "Variable 'total' is typed as 'int', but the value is 'string'"
    assert harness.Errors[0].DocsUrl == "https://docs.n-sharp.dev/errors/NL202"
}
test "the two routes disagree about the ANCHOR and about what is ADDED, never about the SENTENCE" {
    plain := VdDefault()
    VdRun(plain, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    rich := VdHarness("package demo\n\nfunc main() {\n\n\n\n    total: int = 42\n}\n")
    VdRun(rich, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    // The sentence a developer reads is route-independent.
    assert plain.Errors[0].Message == rich.Errors[0].Message

    // The route with source text still underlines the initializer rather than the declaration, and
    // still carries the snippet, the hint and the docs link the other one cannot measure.
    assert plain.Errors[0].Column == 5
    assert rich.Errors[0].Column == 20
    assert plain.Errors[0].SourceSnippet == null
    assert rich.Errors[0].SourceSnippet != null
    assert plain.Errors[0].ContextualHint == null
    assert rich.Errors[0].ContextualHint != null
}
test "the RICH shape carries the actual and expected types the way round the builder names them" {
    harness := VdHarness("package demo\n\nfunc main() {\n\n\n\n    total: int = 42\n}\n")

    VdRun(harness, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    assert harness.Errors[0].ActualType == "string"
    assert harness.Errors[0].ExpectedType == "int"
}
test "the RICH shape underlines the INITIALIZER rather than the declaration" {
    harness := VdHarness("package demo\n\nfunc main() {\n\n\n\n    total: int = 42\n}\n")

    VdRun(harness, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    assert harness.Errors[0].Column == 20
}
test "the RICH shape carries the analysed file's own path" {
    harness := VdHarness("package demo\n\nfunc main() {\n\n\n\n    total: int = 42\n}\n")

    VdRun(harness, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    assert harness.Errors[0].FileName == VdPath()
}
test "a line the source text does not reach has no snippet, so the report falls back" {
    harness := VdHarness("package demo\n")

    VdRun(harness, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    assert harness.Errors[0].Message == "Variable 'total' is typed as 'int', but the value is 'string'"
}
test "the mismatch report happens BEFORE the escape report" {
    harness := VdDefault()
    VdDeclareSoaTable(harness)

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdSoaColumnRead()), BuiltInTypes.String)

    // The type mismatch is raised at phase 1; the escape report at phase 2, so it lands second.
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[1].Message == "SoA table member 'x' cannot be stored in a variable directly"
}
test "the mismatch report happens AFTER the initializer step" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.String)
    steps := harness.Steps

    assert steps[0].Kind == 1
    assert steps[0].ErrorsBefore == 0
}

// ── NL103: A `const` WITH NO INITIAL VALUE ────────────────────────────────

test "a `const` with an annotation and no initializer reports NL103" {
    harness := VdDefault()

    VdRun(harness, VdDeclaration("limit", VdTypeRef("int"), null, VariableKind.Const), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    message := harness.Errors[0].Message
    assert message == "A 'const' must have an initial value — the compiler needs to know its value at compile time"
}
test "the `const` report suggests an initializer spelled with the declared type" {
    harness := VdDefault()

    VdRun(harness, VdDeclaration("limit", VdTypeRef("int"), null, VariableKind.Const), null)

    assert harness.Errors[0].Suggestion == "Add an initializer, for example `const limit: int = 42`."
}
test "the `const` report underlines the declaration's NAME" {
    harness := VdDefault()

    VdRun(harness, VdDeclaration("limit", VdTypeRef("int"), null, VariableKind.Const), null)

    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 5
    assert harness.Errors[0].Length == 5
}
test "a `const` WITH an initializer reports nothing" {
    harness := VdDefault()

    VdRun(harness, VdDeclaration("limit", VdTypeRef("int"), VdInt(), VariableKind.Const), BuiltInTypes.Int)

    assert harness.Errors.Count == 0
}
test "a `readonly` with an annotation and no initializer reports nothing — only `const` must have one" {
    harness := VdDefault()

    VdRun(harness, VdDeclaration("limit", VdTypeRef("int"), null, VariableKind.Readonly), null)

    assert harness.Errors.Count == 0
}
test "a `let` with an annotation and no initializer reports nothing" {
    harness := VdDefault()

    VdRun(harness, VdLet("limit", VdTypeRef("int"), null), null)

    assert harness.Errors.Count == 0
}
test "a `const` with NEITHER takes the undetermined-type arm, not the const arm" {
    harness := VdDefault()

    VdRun(harness, VdDeclaration("limit", null, null, VariableKind.Const), null)

    assert harness.Errors.Count == 1
    message := harness.Errors[0].Message
    assert message == "I can't determine the type of this variable — give it a type annotation or an initial value"
}

// ── NL202: A VOID INITIALIZER ─────────────────────────────────────────────

test "a void initializer with no annotation reports NL202 with its own wording" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Void)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    message := harness.Errors[0].Message
    assert message == "This expression doesn't return a value (it's void) — you can't assign it to a variable"
}
test "the void report passes NO suggestion, so the CODE's default is substituted for it" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Void)

    assert harness.Errors[0].Suggestion == "Ensure types are compatible or add explicit cast"
}
test "the void report underlines the INITIALIZER" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Void)

    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 20
}
test "the void report is NOT the rich shape even when source text is available" {
    harness := VdHarness("package demo\n\nfunc main() {\n\n\n\n    x := doNothing()\n}\n")

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Void)

    message := harness.Errors[0].Message
    assert message == "This expression doesn't return a value (it's void) — you can't assign it to a variable"
}

// ── NL103: NOTHING TO INFER FROM ──────────────────────────────────────────

test "no annotation and no initializer reports NL103" {
    harness := VdDefault()

    VdRun(harness, VdLet("mystery", null, null), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    message := harness.Errors[0].Message
    assert message == "I can't determine the type of this variable — give it a type annotation or an initial value"
}
test "the undetermined report suggests BOTH repairs, spelled with the declaration's own name" {
    harness := VdDefault()

    VdRun(harness, VdLet("mystery", null, null), null)

    message := harness.Errors[0].Suggestion
    assert message == "Add a type annotation like `let mystery: int`, or add an initializer like `let mystery := 0`."
}
test "the undetermined report underlines the declaration's NAME" {
    harness := VdDefault()

    VdRun(harness, VdLet("mystery", null, null), null)

    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 5
    assert harness.Errors[0].Length == 7
}
test "exactly ONE of the five diagnostics can fire per declaration" {
    harness := VdDefault()

    VdRun(harness, VdDeclaration("x", null, null, VariableKind.Const), null)

    assert harness.Errors.Count == 1
}

// ── THE INITIAL NULL STATE ────────────────────────────────────────────────

test "a nullable declaration initialised with a literal `null` is NULL" {
    harness := VdDefault()

    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.String)
    VdRun(harness, VdLet("name", null, VdNull()), nullable)

    assert harness.Scopes.NullStateOrUnknown("name") == NullState.Null
}
test "a nullable declaration initialised with anything else is MAYBE-NULL" {
    harness := VdDefault()

    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.String)
    VdRun(harness, VdLet("name", null, VdName("source")), nullable)

    assert harness.Scopes.NullStateOrUnknown("name") == NullState.MaybeNull
}
test "a nullable declaration with NO initializer is MAYBE-NULL, not the type's default" {
    harness := VdDefault()

    VdRun(harness, VdLet("name", new NullableTypeReference(VdTypeRef("string")), null), null)

    assert harness.Scopes.NullStateOrUnknown("name") == NullState.MaybeNull
}
test "a non-nullable declaration with an initializer asks the null-state owner about the INITIALIZER" {
    harness := VdDefault()

    VdRun(harness, VdLet("count", null, VdInt()), BuiltInTypes.Int)

    assert harness.Scopes.NullStateOrUnknown("count") == NullState.NotNull
}
test "a non-nullable declaration with NO initializer takes the TYPE's default" {
    harness := VdDefault()

    VdRun(harness, VdLet("count", VdTypeRef("int"), null), null)

    assert harness.Scopes.NullStateOrUnknown("count") == NullState.NotNull
}
test "a `null` literal assigned to a NON-nullable declaration is still the initializer's state" {
    harness := VdDefault()

    VdRun(harness, VdLet("value", null, VdNull()), BuiltInTypes.Null)

    assert harness.Scopes.NullStateOrUnknown("value") == NullState.Null
}
test "the null state is written for EVERY declaration, including one that reported" {
    harness := VdDefault()

    VdRun(harness, VdLet("mystery", null, null), null)

    assert harness.Scopes.HasNullState("mystery")
}
test "the null state is written LAST, after the record step" {
    harness := VdDefault()

    declaration := VdLet("count", null, VdInt())
    state := harness.Owner.Begin(declaration)
    step := harness.Owner.NextStep(state)
    seenRecord := false
    while step != null {
        if step.Kind == 5 {
            seenRecord = true
            assert !harness.Scopes.HasNullState("count")
        }

        supplied: TypeInfo? = null
        if step.Kind == 1 {
            supplied = BuiltInTypes.Int
        }

        harness.Owner.Supply(state, supplied)
        step = harness.Owner.NextStep(state)
    }

    assert seenRecord
    assert harness.Scopes.HasNullState("count")
}

// ── THE WALK'S OWN BOOKKEEPING ────────────────────────────────────────────

test "`Begin` produces a fresh state that has decided nothing" {
    harness := VdDefault()

    state := harness.Owner.Begin(VdLet("x", VdTypeRef("int"), VdInt()))

    assert state.Phase == 0
    assert state.Pending == 0
    assert state.DeclaredType == null
    assert state.InferredType == null
    assert BuiltInTypes.IsUnknown(state.FinalType)
}
test "`NextStep` records which kind is outstanding so the answer folds into the right place" {
    harness := VdDefault()

    state := harness.Owner.Begin(VdLet("x", null, VdInt()))
    step := harness.Owner.NextStep(state)

    assert step != null
    assert state.Pending == 1
}
test "`Supply` clears the outstanding kind whether or not it folded anything in" {
    harness := VdDefault()

    state := harness.Owner.Begin(VdLet("x", null, VdInt()))
    harness.Owner.NextStep(state)
    harness.Owner.Supply(state, BuiltInTypes.Int)

    assert state.Pending == 0
}
test "the annotation is resolved ONCE, at the first step, and kept" {
    harness := VdDefault()

    state := harness.Owner.Begin(VdLet("x", VdTypeRef("int"), VdInt()))
    harness.Owner.NextStep(state)

    assert state.DeclaredType != null
    assert BuiltInTypes.Is(state.DeclaredType, BuiltInTypes.Int)
}
test "the inferred type is kept SEPARATELY from the final type, because the null-state rule reads it" {
    harness := VdDefault()

    declaration := VdLet("x", VdTypeRef("int"), VdInt())
    state := harness.Owner.Begin(declaration)
    harness.Owner.NextStep(state)
    harness.Owner.Supply(state, BuiltInTypes.String)
    harness.Owner.NextStep(state)

    assert BuiltInTypes.Is(state.InferredType, BuiltInTypes.String)
    assert BuiltInTypes.Is(state.FinalType, BuiltInTypes.Int)
}
test "the walk ends at phase 99 and stays there" {
    harness := VdDefault()

    declaration := VdLet("x", null, VdInt())
    state := harness.Owner.Begin(declaration)
    step := harness.Owner.NextStep(state)
    while step != null {
        supplied: TypeInfo? = null
        if step.Kind == 1 {
            supplied = BuiltInTypes.Int
        }

        harness.Owner.Supply(state, supplied)
        step = harness.Owner.NextStep(state)
    }

    assert state.Phase == 99
    assert harness.Owner.NextStep(state) == null
}
test "two declarations are two states and neither sees the other's answer" {
    harness := VdDefault()

    first := harness.Owner.Begin(VdLet("a", null, VdInt()))
    second := harness.Owner.Begin(VdLet("b", null, VdInt()))
    harness.Owner.NextStep(first)
    harness.Owner.Supply(first, BuiltInTypes.Int)

    assert second.InferredType == null
    assert second.Phase == 0
}

// ── A USER TYPE, RESOLVED THROUGH THE CANONICAL REGISTRY ──────────────────

test "a declared class annotation resolves and wins the type" {
    harness := VdDefault()
    harness.Scopes.DeclareNestedTypeIfAbsent("Widget", VdClass("Widget"))

    VdRun(harness, VdLet("w", VdTypeRef("Widget"), VdName("make")), BuiltInTypes.Int)
    steps := harness.Steps

    widget := steps[1].CarriedType as ClassTypeInfo
    assert widget != null
    assert widget.Name == "Widget"
}
test "a declared class annotation with an unrelated initializer reports the mismatch" {
    harness := VdDefault()
    harness.Scopes.DeclareNestedTypeIfAbsent("Widget", VdClass("Widget"))

    VdRun(harness, VdLet("w", VdTypeRef("Widget"), VdName("make")), BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Variable 'w' is typed as 'Widget', but the value is 'string'"
}
test "an inferred declaration of a declared class needs no registration at all" {
    harness := VdDefault()

    VdRun(harness, VdLet("w", null, VdName("make")), VdClass("Widget"))
    steps := harness.Steps

    widget := steps[1].CarriedType as ClassTypeInfo
    assert widget != null
    assert widget.Name == "Widget"
}

// ══ THE DECONSTRUCTION FORM: `(a, b) := e` ════════════════════════════════
//
// SAME owner, SAME state, SAME `NextStep`/`Supply`, SAME driver — only the phase family differs, so
// these contracts drive the walk exactly as the annotated ones do. What differs is the kind set the
// walk actually uses (6 instead of 1, because a deconstruction must NOT overwrite the ambient
// target-typing slot), that the declare/record pair REPEATS once per surviving name, and that the
// walk writes the null state or the error-tuple registration itself between the repetitions.
//
// THE CORPUS REACHES ALMOST NONE OF THIS EITHER. Everything below that reports, every `_` discard,
// the reflected-`ValueTuple` arm and the whole error form live here and in the fixtures.

// ── AST and type builders ─────────────────────────────────────────────────

func VdNames1(first: string): List<string> {
    names := new List<string>()
    names.Add(first)
    return names
}

func VdNames2(first: string, second: string): List<string> {
    names := new List<string>()
    names.Add(first)
    names.Add(second)
    return names
}

func VdNames3(first: string, second: string, third: string): List<string> {
    names := new List<string>()
    names.Add(first)
    names.Add(second)
    names.Add(third)
    return names
}

func VdTuple(names: List<string>, initializer: Expression): TupleDeconstructionStatement {
    return new TupleDeconstructionStatement(names, initializer, VariableKind.Let, 9, 3)
}

func VdTupleType(first: TypeInfo, second: TypeInfo): TupleTypeInfo {
    elements := new List<TupleTypeElementInfo>()
    elements.Add(new TupleTypeElementInfo(null, first))
    elements.Add(new TupleTypeElementInfo(null, second))
    return new TupleTypeInfo(elements)
}

func VdValueTupleGeneric(first: TypeInfo, second: TypeInfo): GenericTypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(first)
    arguments.Add(second)
    return new GenericTypeInfo("ValueTuple", arguments)
}

func VdReflectedType(clrType: Type): TypeInfo {
    reflected: TypeInfo = new ReflectionTypeInfo(clrType)
    return reflected
}

// `typeof(Nullable<ValueTuple<int, string>>)` does not emit, so the closed generic is built at run
// time. It is the same `Type` the analyzer sees for a reflected `(int, string)?`, which is the whole
// point: the reader must look THROUGH the nullable wrapper before testing the ValueTuple name.
// A nested generic inside `typeof` does not emit either, so `ValueTuple`8` — the arity at which the
// eighth generic argument is the nested `Rest` rather than an `Item8` field — is also built at run
// time.
func VdBigTuple(): Type {
    definition := Type.GetType("System.ValueTuple`8")
    restDefinition := Type.GetType("System.ValueTuple`1")
    if definition == null || restDefinition == null {
        throw new InvalidOperationException("System.ValueTuple`8 was not loadable.")
    }

    restArguments := new Type[](1)
    restArguments[0] = typeof(int)
    arguments := new Type[](8)
    index := 0
    while index < 7 {
        arguments[index] = typeof(int)
        index = index + 1
    }

    arguments[7] = restDefinition.MakeGenericType(restArguments)
    return definition.MakeGenericType(arguments)
}

func VdNullablePair(): Type {
    definition := Type.GetType("System.Nullable`1")
    if definition == null {
        throw new InvalidOperationException("System.Nullable`1 was not loadable.")
    }

    arguments := new Type[](1)
    arguments[0] = typeof(ValueTuple<int, string>)
    return definition.MakeGenericType(arguments)
}

// ── the driver, exactly as `Analyzer.cs` writes it, for the tuple form ────

// It asks for the SOURCE and the declaration pairs. The escape reports were kinds 2 and 3 and are
// N#-owned calls now, so a contract that wants one to FIRE supplies a row-view TYPE or deconstructs
// a real declared-table column read.
func VdRunTuple(
    harness: VariableDeclarationHarness,
    tuple: TupleDeconstructionStatement,
    answer: TypeInfo?
) {
    steps := harness.Steps
    steps.Clear()
    state := harness.Owner.BeginTuple(tuple)
    step := harness.Owner.NextStep(state)
    while step != null {
        steps.Add(new VdStep(
            step.Kind,
            step.Node,
            step.Name,
            step.CarriedType,
            step.ExpectedType,
            step.Text,
            step.Line,
            step.Column,
            harness.Errors.Count
        ))

        supplied: TypeInfo? = null
        if step.Kind == 6 {
            supplied = answer
        }

        harness.Owner.Supply(state, supplied)
        step = harness.Owner.NextStep(state)
    }
}

// ── THE STEP PROTOCOL ─────────────────────────────────────────────────────

test "a two-name deconstruction asks for the source, then declares and records EACH name" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), VdTupleType(BuiltInTypes.Int, BuiltInTypes.String))

    assert VdKinds(harness.Steps) == "64545"
}
test "a three-name deconstruction repeats the declare/record pair three times" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames3("a", "b", "c"), VdName("triple")), BuiltInTypes.Int)

    assert VdKinds(harness.Steps) == "6454545"
}
test "the source is analysed with kind 6, NOT kind 1 — a deconstruction must not overwrite the ambient expected type" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[0].Kind == 6
    assert steps[0].ExpectedType == null
}
test "the kind-6 step carries the initializer node itself" {
    harness := VdDefault()

    initializer := VdName("pair")
    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), initializer), BuiltInTypes.Int)
    steps := harness.Steps

    assert Object.ReferenceEquals(steps[0].Node, initializer)
}
test "the escape report names the initializer and the action word `deconstructed`" {
    harness := VdDefault()
    VdDeclareSoaTable(harness)

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdSoaColumnRead()), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be deconstructed directly"
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 20
}
test "a row-view source takes the ROW report and never probes for a column at all" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("row")), VdRowType())
    steps := harness.Steps

    assert VdKinds(steps) == "64545"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be deconstructed; use the table and row index instead"
}
test "a deconstruction target is declared WITHOUT a declaration kind, unlike an annotated local" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[1].Kind == 4
    assert steps[1].Text == null
}
test "every target is declared at the DECONSTRUCTION's own line and column, not the name's" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[1].Line == 9
    assert steps[1].Column == 3
    assert steps[3].Line == 9
    assert steps[3].Column == 3
}
test "the declare step and the record step for one name carry the SAME name and the SAME type instance" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), VdTupleType(BuiltInTypes.Int, BuiltInTypes.String))
    steps := harness.Steps

    assert steps[1].Name == "a"
    assert steps[2].Name == "a"
    assert Object.ReferenceEquals(steps[1].CarriedType, steps[2].CarriedType)
}
test "the names are declared in source order" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames3("first", "second", "third"), VdName("t")), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[1].Name == "first"
    assert steps[3].Name == "second"
    assert steps[5].Name == "third"
}

// ── THE `_` DISCARD ───────────────────────────────────────────────────────

test "a `_` target is not declared, not recorded and given no null state" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "_"), VdName("pair")), VdTupleType(BuiltInTypes.Int, BuiltInTypes.String))
    steps := harness.Steps

    assert VdKinds(steps) == "645"
    assert steps[1].Name == "a"
    assert !harness.Scopes.HasNullState("_")
}
test "a `_` in the FIRST position is skipped and the later names still declare" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames3("_", "b", "c"), VdName("t")), BuiltInTypes.Int)
    steps := harness.Steps

    assert VdKinds(steps) == "64545"
    assert steps[1].Name == "b"
    assert steps[3].Name == "c"
}
test "an all-discard deconstruction still analyses the source and still probes the escape" {
    harness := VdDefault()
    VdDeclareSoaTable(harness)

    VdRunTuple(harness, VdTuple(VdNames2("_", "_"), VdSoaColumnRead()), BuiltInTypes.Int)

    // Nothing is declared, but the source is still walked and the escape probe still runs.
    assert VdKinds(harness.Steps) == "6"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be deconstructed directly"
}

// ── WHAT EACH NAME IS ─────────────────────────────────────────────────────

test "a declared tuple type hands each name its own element type" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), VdTupleType(BuiltInTypes.Int, BuiltInTypes.String))
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[1].CarriedType, BuiltInTypes.Int)
    assert BuiltInTypes.Is(steps[3].CarriedType, BuiltInTypes.String)
}
test "a constructed generic named `ValueTuple` hands each name its own type argument" {
    harness := VdDefault()

    source: TypeInfo = VdValueTupleGeneric(BuiltInTypes.String, BuiltInTypes.Int)
    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), source)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[1].CarriedType, BuiltInTypes.String)
    assert BuiltInTypes.Is(steps[3].CarriedType, BuiltInTypes.Int)
}
test "a generic that is NOT named `ValueTuple` is not deconstructable" {
    harness := VdDefault()

    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    arguments.Add(BuiltInTypes.String)
    source: TypeInfo = new GenericTypeInfo("Dictionary", arguments)
    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), source)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Tuple deconstruction needs a tuple value, but this initializer is 'Dictionary<int, string>'"
}
test "a reflected CLR ValueTuple hands each name its converted element type" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), VdReflectedType(typeof(ValueTuple<int, string>)))
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[1].CarriedType, BuiltInTypes.Int)
    assert BuiltInTypes.Is(steps[3].CarriedType, BuiltInTypes.String)
}
test "a reflected NULLABLE ValueTuple is read through its underlying type" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), VdReflectedType(VdNullablePair()))
    steps := harness.Steps

    assert VdKinds(steps) == "64545"
    assert BuiltInTypes.Is(steps[1].CarriedType, BuiltInTypes.Int)
}
test "a reflected NON-tuple value type is not deconstructable" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), VdReflectedType(typeof(DateTime)))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
}
test "a reflected REFERENCE type is not deconstructable" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), VdReflectedType(typeof(string)))

    assert harness.Errors.Count == 1
}
test "a reflected ValueTuple's elements come from its `ItemN` FIELDS, not its generic arguments" {
    harness := VdDefault()

    // `ValueTuple`8` has EIGHT generic arguments but only SEVEN `ItemN` fields — the eighth is the
    // nested `Rest`. Reading arguments would answer 8 and mis-pair every target.
    VdRunTuple(harness, VdTuple(VdNames3("a", "b", "c"), VdName("big")), VdReflectedType(VdBigTuple()))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Tuple deconstruction has 3 target(s), but the initializer has 7 element(s)"
}

// ── THE TWO DIAGNOSTICS ───────────────────────────────────────────────────

test "a source that is not a tuple reports NL103 with the source's rendered type" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("value")), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert harness.Errors[0].Message == "Tuple deconstruction needs a tuple value, but this initializer is 'int'"
    assert harness.Errors[0].Suggestion == "Return or construct a tuple with the same number of elements as the deconstruction targets."
}
test "a count mismatch reports NL103 naming BOTH counts" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames3("a", "b", "c"), VdName("pair")), VdTupleType(BuiltInTypes.Int, BuiltInTypes.String))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert harness.Errors[0].Message == "Tuple deconstruction has 3 target(s), but the initializer has 2 element(s)"
    assert harness.Errors[0].Suggestion == "Match the number of target names to the tuple element count."
}
test "both reports underline the INITIALIZER, not the target list" {
    harness := VdHarness("func f() {\n(a, b) := value\n}\n")

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("value")), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 20
}
test "a report still declares every target, so the names exist for the rest of the scope" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("value")), BuiltInTypes.Int)
    steps := harness.Steps

    assert VdKinds(steps) == "64545"
    assert steps[1].Name == "a"
    assert steps[3].Name == "b"
}
test "a reported deconstruction gives every target UNKNOWN" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("value")), BuiltInTypes.Int)
    steps := harness.Steps

    assert BuiltInTypes.IsUnknown(steps[1].CarriedType)
    assert BuiltInTypes.IsUnknown(steps[3].CarriedType)
}
test "the report is emitted BEFORE the first target is declared" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("value")), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[0].ErrorsBefore == 0
    assert steps[1].ErrorsBefore == 1
}
test "a matching tuple reports NOTHING" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), VdTupleType(BuiltInTypes.Int, BuiltInTypes.String))

    assert harness.Errors.Count == 0
}

// ── THE UNKNOWN AND ESCAPED SOURCES ───────────────────────────────────────

test "an UNKNOWN source declares every target as unknown and reports nothing" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("mystery")), BuiltInTypes.Unknown)
    steps := harness.Steps

    assert harness.Errors.Count == 0
    assert BuiltInTypes.IsUnknown(steps[1].CarriedType)
    assert BuiltInTypes.IsUnknown(steps[3].CarriedType)
}
test "a fired COLUMN escape makes the source unknown even though the source was a real tuple" {
    harness := VdDefault()
    VdDeclareSoaTable(harness)

    VdRunTuple(
        harness,
        VdTuple(VdNames2("a", "b"), VdSoaColumnRead()),
        VdTupleType(BuiltInTypes.Int, BuiltInTypes.String)
    )
    steps := harness.Steps

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be deconstructed directly"
    assert BuiltInTypes.IsUnknown(steps[1].CarriedType)
    assert BuiltInTypes.IsUnknown(steps[3].CarriedType)
}
test "a ROW escape makes the source unknown without any column probe at all" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("row")), VdRowType())
    steps := harness.Steps

    assert VdKinds(steps) == "64545"
    assert BuiltInTypes.IsUnknown(steps[1].CarriedType)
}
test "every unknown target shares ONE unknown instance, exactly as the fallback handed it out" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames3("a", "b", "c"), VdName("mystery")), BuiltInTypes.Unknown)
    steps := harness.Steps

    assert Object.ReferenceEquals(steps[1].CarriedType, steps[3].CarriedType)
    assert Object.ReferenceEquals(steps[3].CarriedType, steps[5].CarriedType)
}

// ── THE ERROR-HANDLING FORM `(result, err := f())` ────────────────────────

test "exactly two names whose second is `err` is the error form, and it never counts elements" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("value", "err"), VdName("call")), BuiltInTypes.Int)

    assert harness.Errors.Count == 0
    assert VdKinds(harness.Steps) == "64545"
}
test "the error form's first name takes the SOURCE's type whole, undeconstructed" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("value", "err"), VdName("call")), BuiltInTypes.String)
    steps := harness.Steps

    assert steps[1].Name == "value"
    assert BuiltInTypes.Is(steps[1].CarriedType, BuiltInTypes.String)
}
test "the error form's second name is always `Exception?`, whatever the source was" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("value", "err"), VdName("call")), BuiltInTypes.String)
    steps := harness.Steps

    assert steps[3].Name == "err"
    external := steps[3].CarriedType as ExternalTypeInfo
    assert external != null
    assert external.Name == "Exception?"
}
test "the error form registers the result under its error name" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("value", "err"), VdName("call")), BuiltInTypes.Int)

    guard := harness.Scopes.FindErrorTupleResultGuard("value")
    assert guard != null
    assert guard.ErrorName == "err"
    assert guard.Line == 9
    assert guard.Column == 3
}
test "the error form gives the ERROR name maybe-null and the result NO null state" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("value", "err"), VdName("call")), BuiltInTypes.Int)

    assert harness.Scopes.NullStateOrUnknown("err") == NullState.MaybeNull
    assert !harness.Scopes.HasNullState("value")
}
test "the error form's registration happens AFTER the result is recorded and BEFORE the error is declared" {
    harness := VdDefault()

    tuple := VdTuple(VdNames2("value", "err"), VdName("call"))
    state := harness.Owner.BeginTuple(tuple)
    step := harness.Owner.NextStep(state)
    seen := ""
    while step != null {
        if step.Kind == 4 && step.Name == "err" {
            registered := harness.Scopes.FindErrorTupleResultGuard("value")
            if registered != null {
                seen = seen + "registered-before-err-declare"
            }
        }

        if step.Kind == 5 && step.Name == "value" {
            registered := harness.Scopes.FindErrorTupleResultGuard("value")
            if registered == null {
                seen = seen + "not-yet;"
            }
        }

        supplied: TypeInfo? = null
        if step.Kind == 6 {
            supplied = BuiltInTypes.Int
        }

        harness.Owner.Supply(state, supplied)
        step = harness.Owner.NextStep(state)
    }

    assert seen == "not-yet;registered-before-err-declare"
}
test "a discarded result in the error form declares only the error name and registers nothing" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("_", "err"), VdName("call")), BuiltInTypes.Int)
    steps := harness.Steps

    assert VdKinds(steps) == "645"
    assert steps[1].Name == "err"
    assert harness.Scopes.FindErrorTupleResultGuard("_") == null
}
test "the error form still folds an escaped source into unknown" {
    harness := VdDefault()
    VdDeclareSoaTable(harness)

    VdRunTuple(harness, VdTuple(VdNames2("value", "err"), VdSoaColumnRead()), BuiltInTypes.String)
    steps := harness.Steps

    assert BuiltInTypes.IsUnknown(steps[1].CarriedType)
}
test "THREE names whose second is `err` is NOT the error form" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames3("value", "err", "extra"), VdName("call")), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Scopes.FindErrorTupleResultGuard("value") == null
}
test "two names whose second is not literally `err` is NOT the error form" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("value", "error"), VdName("call")), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Scopes.FindErrorTupleResultGuard("value") == null
}
test "a ONE-name deconstruction is never the error form" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames1("err"), VdName("call")), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Scopes.FindErrorTupleResultGuard("err") == null
}

// ── THE NULL STATE OF AN ORDINARY TARGET ──────────────────────────────────

test "an ordinary target takes the default null state its own type implies" {
    harness := VdDefault()

    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.String)
    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), VdTupleType(nullable, BuiltInTypes.Int))

    assert harness.Scopes.NullStateOrUnknown("a") == NullState.MaybeNull
    assert harness.Scopes.NullStateOrUnknown("b") == NullState.NotNull
}
test "a target's null state is written AFTER its record step and BEFORE the next name is declared" {
    harness := VdDefault()

    tuple := VdTuple(VdNames2("a", "b"), VdName("pair"))
    state := harness.Owner.BeginTuple(tuple)
    step := harness.Owner.NextStep(state)
    trace := ""
    while step != null {
        if step.Kind == 5 && step.Name == "a" && !harness.Scopes.HasNullState("a") {
            trace = trace + "a-unset-at-record;"
        }

        if step.Kind == 4 && step.Name == "b" && harness.Scopes.HasNullState("a") {
            trace = trace + "a-set-before-b"
        }

        supplied: TypeInfo? = null
        if step.Kind == 6 {
            supplied = BuiltInTypes.Int
        }

        harness.Owner.Supply(state, supplied)
        step = harness.Owner.NextStep(state)
    }

    assert trace == "a-unset-at-record;a-set-before-b"
}
test "every target of a reported deconstruction still gets a null state" {
    harness := VdDefault()

    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("value")), BuiltInTypes.Int)

    assert harness.Scopes.HasNullState("a")
    assert harness.Scopes.HasNullState("b")
}

// ── THE WALK'S OWN BOOKKEEPING ────────────────────────────────────────────

test "`BeginTuple` produces a state in the DECONSTRUCTION phase family" {
    harness := VdDefault()

    state := harness.Owner.BeginTuple(VdTuple(VdNames2("a", "b"), VdName("pair")))

    assert state.Phase == 10
    assert state.Tuple != null
    assert state.Declaration == null
}
test "`Begin` produces a state in the ANNOTATED phase family" {
    harness := VdDefault()

    state := harness.Owner.Begin(VdLet("x", null, VdInt()))

    assert state.Phase == 0
    assert state.Declaration != null
    assert state.Tuple == null
}
test "the deconstruction's outstanding kind is 6, so the answer folds into the inferred type" {
    harness := VdDefault()

    state := harness.Owner.BeginTuple(VdTuple(VdNames2("a", "b"), VdName("pair")))
    harness.Owner.NextStep(state)

    assert state.Pending == 6
    harness.Owner.Supply(state, BuiltInTypes.String)
    assert BuiltInTypes.Is(state.InferredType, BuiltInTypes.String)
}
test "a FIRED column report is what records the escape, and it fires inside the walk" {
    harness := VdDefault()
    VdDeclareSoaTable(harness)

    state := harness.Owner.BeginTuple(VdTuple(VdNames2("a", "b"), VdSoaColumnRead()))
    harness.Owner.NextStep(state)
    assert !state.EscapeFired

    // The answer arrives, the walk advances past the escape phase, and the report fires there.
    harness.Owner.Supply(state, BuiltInTypes.Int)
    harness.Owner.NextStep(state)

    assert state.EscapeFired
    assert harness.Errors.Count == 1
}
test "a source no report fires on records nothing" {
    harness := VdDefault()

    state := harness.Owner.BeginTuple(VdTuple(VdNames2("a", "b"), VdName("pair")))
    harness.Owner.NextStep(state)
    harness.Owner.Supply(state, VdTupleType(BuiltInTypes.Int, BuiltInTypes.String))
    harness.Owner.NextStep(state)

    assert !state.EscapeFired
    assert harness.Errors.Count == 0
}
test "the deconstruction walk ends at phase 99 and stays there" {
    harness := VdDefault()

    tuple := VdTuple(VdNames2("a", "b"), VdName("pair"))
    state := harness.Owner.BeginTuple(tuple)
    step := harness.Owner.NextStep(state)
    while step != null {
        supplied: TypeInfo? = null
        if step.Kind == 6 {
            supplied = BuiltInTypes.Int
        }

        harness.Owner.Supply(state, supplied)
        step = harness.Owner.NextStep(state)
    }

    assert state.Phase == 99
    assert harness.Owner.NextStep(state) == null
}
test "two deconstructions are two states and neither sees the other's answer" {
    harness := VdDefault()

    first := harness.Owner.BeginTuple(VdTuple(VdNames2("a", "b"), VdName("one")))
    second := harness.Owner.BeginTuple(VdTuple(VdNames2("c", "d"), VdName("two")))
    harness.Owner.NextStep(first)
    harness.Owner.Supply(first, BuiltInTypes.Int)

    assert second.InferredType == null
    assert second.Phase == 10
}
test "an annotated declaration and a deconstruction run through the SAME owner without interfering" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Int)
    annotated := VdKinds(harness.Steps)
    VdRunTuple(harness, VdTuple(VdNames2("a", "b"), VdName("pair")), BuiltInTypes.Int)

    assert annotated == "145"
    assert VdKinds(harness.Steps) == "64545"
}

// ── THE ERROR-CAPTURE CONVENTION, AS A NAMED FACT ──────────────────────────────────────────────
//
// `IsErrorCaptureForm` is the whole rule behind `state.ErrorForm`, lifted out of phase 10 so that
// the two other places that decide the same thing — the columnar emitter's `v, err := <call>`
// lowering and the editor's `catchResult` semantic-token modifier — ask ONE owner instead of each
// spelling `== "err"` for itself. The contracts below are about the RULE; the phase-10 contracts
// elsewhere in this file are about the walk that consults it.

test "the error capture form is exactly two names whose second is err" {
    assert AnalyzerVariableDeclaration.IsErrorCaptureForm(2, "err")
}

// THE `>= 2` MISREADING, REFUSED. A three-name deconstruction ending in `err` is an ORDINARY tuple
// deconstruction: the walk counts its elements and types `err` from the source. Any consumer that
// admits it is describing a form the language does not have.
test "a longer deconstruction ending in err is not the error capture form" {
    assert !AnalyzerVariableDeclaration.IsErrorCaptureForm(3, "err")
    assert !AnalyzerVariableDeclaration.IsErrorCaptureForm(4, "err")
}

test "a two name deconstruction whose second name is not err is not the error capture form" {
    assert !AnalyzerVariableDeclaration.IsErrorCaptureForm(2, "error")
    assert !AnalyzerVariableDeclaration.IsErrorCaptureForm(2, "Err")
    assert !AnalyzerVariableDeclaration.IsErrorCaptureForm(2, "e")
    assert !AnalyzerVariableDeclaration.IsErrorCaptureForm(2, "")
}

test "a single name is never the error capture form" {
    assert !AnalyzerVariableDeclaration.IsErrorCaptureForm(1, "err")
    assert !AnalyzerVariableDeclaration.IsErrorCaptureForm(0, "err")
}

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
// THREE OF THE FIVE STEPS TAKE THE RESOLVED TYPE AS AN OPERAND, and in the inference form that type
// IS the first step's answer — which is why the walk resumes rather than scheduling. The contracts
// pin that by supplying a DIFFERENT type than any annotation and asserting what the later steps
// carry.
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
        model: SemanticModel) {
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
        errorsBefore: int) {
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
        new Dictionary<string, string>(StringComparer.Ordinal))
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
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        model,
        new BindingMap())
    resolver.BeginAnalysis(VdPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    nullFlow := new AnalyzerNullFlow(diagnostics, spans, scopes, context)

    return new VariableDeclarationHarness(
        new AnalyzerVariableDeclaration(diagnostics, spans, resolver, assignability, nullFlow, scopes),
        scopes,
        context,
        diagnostics,
        errors,
        model)
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
    kind: VariableKind): VariableDeclarationStatement {
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
        true)
    return result
}

// ── the driver, exactly as `Analyzer.cs` writes it ────────────────────────

// Runs the whole walk, answering every kind-1 step with `answer`, and records what was asked into
// the harness. A null answer means the shape under test has no initializer and the walk never asks.
func VdRun(
    harness: VariableDeclarationHarness,
    declaration: VariableDeclarationStatement,
    answer: TypeInfo?) {
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
            harness.Errors.Count))

        supplied: TypeInfo? = null
        if step.Kind == 1 {
            supplied = answer
        }

        harness.Owner.Supply(state, supplied)
        step = harness.Owner.NextStep(state)
    }
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

test "an inferred declaration asks for the initializer, then the column escape, then declares, then records" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert VdKinds(steps) == "1345"
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
test "the escape step carries the SAME initializer node and the analyzer's own wording" {
    harness := VdDefault()
    initializer := VdInt()

    VdRun(harness, VdLet("x", null, initializer), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[1].Kind == 3
    assert Object.ReferenceEquals(steps[1].Node, initializer)
    assert steps[1].Text == "stored in a variable"
}
test "the declare step carries the declaration's own name, line and column" {
    harness := VdDefault()

    VdRun(harness, VdLet("count", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[2].Kind == 4
    assert steps[2].Name == "count"
    assert steps[2].Line == 7
    assert steps[2].Column == 5
}
test "the declare step carries the declaration kind `local`, so the driver hard-codes nothing" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[2].Text == "local"
}
test "the record step carries the name and the type and no span" {
    harness := VdDefault()

    VdRun(harness, VdLet("total", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[3].Kind == 5
    assert steps[3].Name == "total"
    assert BuiltInTypes.Is(steps[3].CarriedType, BuiltInTypes.Int)
    assert steps[3].Line == 0
    assert steps[3].Column == 0
}
test "`Supply` with a null answer on a kind-1 step leaves the declaration untyped" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), null)
    steps := harness.Steps

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert BuiltInTypes.IsUnknown(steps[2].CarriedType)
}

// ── THE ANSWER IS THE OPERAND: why the walk resumes ───────────────────────

test "with no annotation the DECLARE step is passed the answer the walk did not have at step one" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.String)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[2].CarriedType, BuiltInTypes.String)
}
test "with no annotation the RECORD step is passed the same answer" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.String)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[3].CarriedType, BuiltInTypes.String)
}
test "the answer also CHOOSES which escape report fires — a row view takes the row step" {
    harness := VdDefault()

    rowType: TypeInfo = VdRowType()
    VdRun(harness, VdLet("row", null, VdName("particles")), rowType)
    steps := harness.Steps

    assert steps[1].Kind == 2
    assert steps[1].Text == "stored in a variable"
}
test "anything that is not a row view takes the direct-column step instead" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Int)
    steps := harness.Steps

    assert steps[1].Kind == 3
}
test "an ANNOTATED declaration takes the row step only when the ANNOTATION is a row view" {
    harness := VdDefault()

    rowType: TypeInfo = VdRowType()
    VdRun(harness, VdLet("row", VdTypeRef("int"), VdName("particles")), rowType)
    steps := harness.Steps

    assert steps[1].Kind == 3
}

// ── THE FOUR TYPE OUTCOMES ────────────────────────────────────────────────

test "an annotation WINS the type even when the initializer disagreed" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.String)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[2].CarriedType, BuiltInTypes.Int)
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

    assert BuiltInTypes.Is(steps[2].CarriedType, BuiltInTypes.Bool)
    assert harness.Errors.Count == 0
}
test "a VOID initializer with no annotation falls back to unknown" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", null, VdInt()), BuiltInTypes.Void)
    steps := harness.Steps

    assert BuiltInTypes.IsUnknown(steps[2].CarriedType)
}
test "a VOID initializer under an ANNOTATION is a mismatch, not the void report" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.Void)
    steps := harness.Steps

    assert BuiltInTypes.Is(steps[2].CarriedType, BuiltInTypes.Int)
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
test "with source text the report takes the RICH shape, which is a different message and a docs link" {
    harness := VdHarness("package demo\n\nfunc main() {\n\n\n\n    total: int = 42\n}\n")

    VdRun(harness, VdLet("total", VdTypeRef("int"), VdInt()), BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message == "Type mismatch"
    assert harness.Errors[0].DocsUrl == "https://docs.n-sharp.dev/errors/NL202"
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
test "the mismatch report happens BEFORE the escape step" {
    harness := VdDefault()

    VdRun(harness, VdLet("x", VdTypeRef("int"), VdInt()), BuiltInTypes.String)
    steps := harness.Steps

    assert steps[1].Kind == 3
    assert steps[1].ErrorsBefore == 1
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

    widget := steps[2].CarriedType as ClassTypeInfo
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

    widget := steps[2].CarriedType as ClassTypeInfo
    assert widget != null
    assert widget.Name == "Widget"
}

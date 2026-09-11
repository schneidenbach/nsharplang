namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Threading.Tasks
import NSharpLang.Compiler.Ast


// Native contracts for WHAT AN OPERATOR THAT HANDS ITS OPERAND THROUGH MEANS — `throw`, `is`,
// `spread`, `alloc`, `must`, `stackalloc`, a tuple and `await`, the expression walk's third
// N#-owned territory.
//
// The family is eight operators with one shape: each walks what it is given and then says what that
// makes it. Every form suspends — seven exactly once, a tuple once per element — so every contract
// asserts three things at once: which steps were asked for, in what order, and what the walk
// answered given the answers those steps got.
//
// The seven things it is easy to get wrong:
//
// (1) THE ANSWER IS NOT SETTLED AT `Begin`. This is the first family in the arc for which that is
// true: `spread`, `alloc`, `must`, `tuple` and `await` all derive their answer from the operand, so
// a walk read before its step has been answered says `unknown`, and an implementation that decided
// early would be right only for the three constant-answered forms.
//
// (2) `throw` RUNS BOTH SoA REPORTS AND NEITHER STOPS THE OTHER, which is the opposite of what
// `nameof`, `spread`, `must` and `await` do. A `throw` produces no value for either objection to be
// about, so both are made.
//
// (3) `alloc`'s ROW REFUSAL IS A DIFFERENT DIAGNOSTIC FROM EVERY OTHER ARM'S. It is the
// hidden-allocation report, not the row-escape report, and the message is the proof.
//
// (4) `must` REPORTS A REDUNDANT UNWRAP AND STILL ANSWERS THE OPERAND TYPE. Answering `unknown`
// there would cascade one redundant keyword through every expression built on it.
//
// (5) `stackalloc`'s THREE LENGTH RULES ARE EXCLUSIVE AND ORDERED, and it is a `Span<T>` whichever
// of them fired — including when a SoA diagnostic replaced both of the others.
//
// (6) A TUPLE IS THE ARC'S FIRST PER-STEP AMBIENT WRITE. The surrounding annotation is decomposed
// FOR EACH ELEMENT and pushed for exactly as long as that element is being walked; the slot is read
// at the top of the element and restored before the next one, and matching is by NAME first.
//
// (7) `await` LEAVES A CLASS, STRUCT, RECORD OR INTERFACE ALONE. Those shapes may carry a
// `GetAwaiter` this analyzer has not bound yet; everything else cannot, and is told so.
class OperandStep {
    Kind: int
    NodeName: string
    Line: int
    Column: int
    ErrorsBefore: int
    ResultBefore: string
    ExpectedBefore: string

    constructor(kind: int, nodeName: string, line: int, column: int, errorsBefore: int, resultBefore: string, expectedBefore: string) {
        Kind = kind
        NodeName = nodeName
        Line = line
        Column = column
        ErrorsBefore = errorsBefore
        ResultBefore = resultBefore
        ExpectedBefore = expectedBefore
    }
}

class OperandHarness {
    Operands: AnalyzerPassThroughOperands
    Ambient: AnalyzerAmbientContext
    Context: AnalyzerDeclarationContext
    Reachability: AnalyzerPatternReachability
    Escape: AnalyzerSoaEscape
    Model: SemanticModel
    Errors: List<CompilerError>

    constructor(operands: AnalyzerPassThroughOperands, ambient: AnalyzerAmbientContext, context: AnalyzerDeclarationContext, reachability: AnalyzerPatternReachability, escape: AnalyzerSoaEscape, model: SemanticModel, errors: List<CompilerError>) {
        Operands = operands
        Ambient = ambient
        Context = context
        Reachability = reachability
        Escape = escape
        Model = model
        Errors = errors
    }
}

func OperandPath(): string {
    return Path.GetFullPath("pass-through-operands-contract.nl")
}

func OperandHarnessWith(sourceText: string?): OperandHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(OperandPath(), sourceText)
    spans := new AnalyzerDiagnosticSpans(diagnostics)
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, new List<string>(), new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, diagnostics, new Dictionary<string, string>(StringComparer.Ordinal), new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal), new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal), model, new BindingMap())
    resolver.BeginAnalysis(OperandPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    conditions := new AnalyzerBooleanConditions(diagnostics, spans, escape)
    sequence := new AnalyzerLoopSequence(diagnostics, spans, scopes, context, resolver, ambient, escape, conditions)
    constantFacts := new AnalyzerConstantExpressionFacts(scopes, context)
    reachability := new AnalyzerPatternReachability(diagnostics, spans, context, assignability)
    operands := new AnalyzerPassThroughOperands(diagnostics, spans, escape, resolver, ambient, context, sequence, constantFacts)
    return new OperandHarness(operands, ambient, context, reachability, escape, model, errors)
}

func OperandDefault(): OperandHarness {
    return OperandHarnessWith(null)
}

func OperandTypeText(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    boxed := candidate as object
    rendered := boxed.ToString()
    if rendered != null {
        return rendered
    }

    return "<blank>"
}

func OperandNodeName(node: Expression?): string {
    if node == null {
        return "<null>"
    }

    identifier := node as IdentifierExpression
    if identifier != null {
        return identifier.Name
    }

    boxed := node as object
    return boxed.GetType().Name
}

// ── the pass-through driver, exactly as `Analyzer.cs` writes it ─────────
//
// The one difference is that the expression step is ANSWERED from a supplied list rather than by
// re-entering the analyzer's own walk, which is the one thing a contract cannot replay. Every step
// records the error count, the walk's result AS THE STEP WAS HANDED OUT, and — the row this family
// needed that the last two did not — THE AMBIENT EXPECTED TYPE AT THAT INSTANT, which is what makes
// a tuple's per-element bracket readable off the row stream.
func OperandRun(harness: OperandHarness, state: PassThroughOperandState, answers: List<TypeInfo?>): List<OperandStep> {
    steps := new List<OperandStep>()
    step := harness.Operands.NextStep(state)
    while step != null {
        index := steps.Count
        steps.Add(new OperandStep(step.Kind, OperandNodeName(step.Node), step.Line, step.Column, harness.Errors.Count, OperandTypeText(harness.Operands.Result(state)), OperandTypeText(harness.Ambient.CurrentExpectedType)))
        answer: TypeInfo? = null
        if index < answers.Count {
            answer = answers[index]
        }

        harness.Operands.Supply(state, answer)
        step = harness.Operands.NextStep(state)
    }

    return steps
}

func OperandOne(answer: TypeInfo?): List<TypeInfo?> {
    answers := new List<TypeInfo?>()
    answers.Add(answer)
    return answers
}

func OperandNone(): List<TypeInfo?> {
    return new List<TypeInfo?>()
}

func OperandIdentifier(name: string, line: int, column: int): Expression {
    expression: Expression = new IdentifierExpression(name, line, column)
    return expression
}

func OperandSimpleType(name: string, line: int, column: int): TypeReference {
    reference: TypeReference = new SimpleTypeReference(name, line, column)
    return reference
}

func OperandTupleOf(elements: List<TupleElement>): Expression {
    expression: Expression = new TupleExpression(elements, 4, 9)
    return expression
}

func OperandTupleElement(name: string?, valueName: string, line: int, column: int): TupleElement {
    return new TupleElement(name, OperandIdentifier(valueName, line, column))
}

func OperandExpectedTuple(names: List<string?>, types: List<TypeInfo>): TypeInfo {
    elements := new List<TupleTypeElementInfo>()
    index := 0
    while index < types.Count {
        elements.Add(new TupleTypeElementInfo(names[index], types[index]))
        index = index + 1
    }

    expected: TypeInfo = new TupleTypeInfo(elements)
    return expected
}

func OperandRow(name: string): TypeInfo {
    columns := new List<SoaColumnInfo>()
    row: TypeInfo = new SoaRowTypeInfo(new SoaRecordDeclarationInfo(name, columns, 1, 1))
    return row
}

// A tuple type rendered for a contract. `TupleTypeInfo` carries no `ToString` of its own — the
// analyzer has always rendered one as its CLR type name — so the elements are read directly rather
// than through the text an assertion on `ToString` would be comparing.
func OperandTupleText(candidate: TypeInfo?): string {
    tuple := candidate as TupleTypeInfo
    if tuple == null {
        return "<not a tuple>"
    }

    rendered := "("
    index := 0
    while index < tuple.Elements.Count {
        if index > 0 {
            rendered = rendered + ", "
        }

        element := tuple.Elements[index]
        name := element.Name
        if name != null {
            rendered = rendered + name + ": "
        }

        rendered = rendered + OperandTypeText(element.Type)
        index = index + 1
    }

    return rendered + ")"
}

func OperandErrorText(harness: OperandHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + ":" + error.Length.ToString()
}

func OperandReflected(clrType: Type): TypeInfo {
    reflected: TypeInfo = new ReflectionTypeInfo(clrType)
    return reflected
}

func OperandNullable(inner: TypeInfo): TypeInfo {
    nullable: TypeInfo = new NullableTypeInfo(inner)
    return nullable
}

// The four declared shapes `await` deliberately leaves alone, built the way the rest of the estate
// builds them.
func OperandClassType(): TypeInfo {
    shape: TypeInfo = new ClassTypeInfo("Widget", 1, 1, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
    return shape
}

func OperandStructType(): TypeInfo {
    shape: TypeInfo = new StructTypeInfo("Point", 1, 1, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return shape
}

func OperandRecordType(): TypeInfo {
    shape: TypeInfo = new RecordTypeInfo("Shape", 1, 1, false, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return shape
}

func OperandInterfaceType(): TypeInfo {
    shape: TypeInfo = new InterfaceTypeInfo("IShape", 1, 1, false, new TypeReference[](0), new TypeParameter[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return shape
}

// ── the protocol, which is the same for all eight ───────────────────────

test "EVERY FORM ASKS FOR KIND 1 AND NOTHING ELSE" {
    harness := OperandDefault()
    nodes := new List<Expression>()
    nodes.Add(new ThrowExpression(OperandIdentifier("e", 2, 11), 2, 5))
    nodes.Add(new IsExpression(OperandIdentifier("v", 2, 11), OperandSimpleType("int", 2, 16), null, 2, 5))
    nodes.Add(new SpreadExpression(OperandIdentifier("xs", 2, 11), 2, 5))
    nodes.Add(new AllocExpression(OperandIdentifier("v", 2, 11), 2, 5))
    nodes.Add(new MustExpression(OperandIdentifier("v", 2, 11), 2, 5))
    nodes.Add(new StackAllocExpression(OperandSimpleType("byte", 2, 16), OperandIdentifier("n", 2, 21), 2, 5))
    nodes.Add(new AwaitExpression(OperandIdentifier("t", 2, 11), 2, 5))

    index := 0
    while index < nodes.Count {
        state := harness.Operands.Begin(nodes[index], harness.Reachability)
        steps := OperandRun(harness, state, OperandOne(BuiltInTypes.Int))
        assert steps.Count == 1
        assert steps[0].Kind == 1
        index = index + 1
    }
}

test "THE STEP COUNT IS THE OPERAND COUNT — SEVEN FORMS ONE, A TUPLE ONE PER ELEMENT" {
    harness := OperandDefault()
    empty := OperandTupleOf(new List<TupleElement>())
    emptyState := harness.Operands.Begin(empty, harness.Reachability)

    emptySteps := OperandRun(harness, emptyState, OperandNone())

    assert emptyState.Form == 6
    assert emptySteps.Count == 0

    elements := new List<TupleElement>()
    elements.Add(OperandTupleElement(null, "a", 4, 10))
    elements.Add(OperandTupleElement(null, "b", 4, 13))
    elements.Add(OperandTupleElement(null, "c", 4, 16))
    threeState := harness.Operands.Begin(OperandTupleOf(elements), harness.Reachability)

    answers := new List<TypeInfo?>()
    answers.Add(BuiltInTypes.Int)
    answers.Add(BuiltInTypes.String)
    answers.Add(BuiltInTypes.Bool)
    threeSteps := OperandRun(harness, threeState, answers)

    assert threeSteps.Count == 3
    assert threeSteps[0].NodeName == "a"
    assert threeSteps[1].NodeName == "b"
    assert threeSteps[2].NodeName == "c"
    assert threeSteps[0].Column == 10
    assert threeSteps[2].Column == 16
}

test "A NODE THAT IS NONE OF THE EIGHT TAKES NO STEPS AND ANSWERS unknown" {
    harness := OperandDefault()
    state := harness.Operands.Begin(OperandIdentifier("x", 2, 5), harness.Reachability)

    steps := OperandRun(harness, state, OperandOne(BuiltInTypes.Int))

    assert state.Form == -1
    assert steps.Count == 0
    assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
    assert harness.Errors.Count == 0
}

test "A WALK THAT ASKED FOR NOTHING FOLDS IN NOTHING WHEN SUPPLIED ANYWAY" {
    harness := OperandDefault()
    state := harness.Operands.Begin(OperandIdentifier("x", 2, 5), harness.Reachability)

    harness.Operands.Supply(state, BuiltInTypes.String)

    assert OperandTypeText(state.OperandType) == "unknown"
    assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
}

test "A FINISHED WALK KEEPS ANSWERING null AND ITS RESULT IS STABLE" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new SpreadExpression(OperandIdentifier("xs", 2, 11), 2, 5), harness.Reachability)

    steps := OperandRun(harness, state, OperandOne(BuiltInTypes.String))

    assert steps.Count == 1
    assert harness.Operands.NextStep(state) == null
    assert harness.Operands.NextStep(state) == null
    assert OperandTypeText(harness.Operands.Result(state)) == "string"
    assert OperandTypeText(harness.Operands.Result(state)) == "string"
}

test "THE ANSWER IS NOT SETTLED BEFORE THE STEP — THE ARC'S FIRST FAMILY FOR WHICH THAT IS TRUE" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new MustExpression(OperandIdentifier("v", 2, 11), 2, 5), harness.Reachability)

    steps := OperandRun(harness, state, OperandOne(OperandNullable(BuiltInTypes.Int)))

    assert steps.Count == 1
    assert steps[0].ResultBefore == "unknown"
    assert OperandTypeText(harness.Operands.Result(state)) == "int"
}

test "NO DIAGNOSTIC LANDS AT Begin — EVERY REPORT THIS FAMILY OWNS IS AFTER A STEP" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new MustExpression(OperandIdentifier("v", 2, 11), 2, 5), harness.Reachability)

    assert harness.Errors.Count == 0

    steps := OperandRun(harness, state, OperandOne(BuiltInTypes.Int))

    assert steps[0].ErrorsBefore == 0
    assert harness.Errors.Count == 1
}

// ── throw ───────────────────────────────────────────────────────────────

test "throw IS never WHATEVER IT THREW" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new ThrowExpression(OperandIdentifier("e", 2, 11), 2, 5), harness.Reachability)

    steps := OperandRun(harness, state, OperandOne(BuiltInTypes.String))

    assert steps.Count == 1
    assert steps[0].NodeName == "e"
    assert OperandTypeText(harness.Operands.Result(state)) == "never"
    assert harness.Errors.Count == 0
}

test "A THROWN ROW VIEW IS REFUSED AND THE THROW IS STILL never" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new ThrowExpression(OperandIdentifier("row", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be thrown; use the table and row index instead"
    assert OperandTypeText(harness.Operands.Result(state)) == "never"
}

test "throw RUNS BOTH REPORTS AND NEITHER STOPS THE OTHER — EVERY OTHER ARM STOPS AT THE FIRST" {
    harness := OperandDefault()
    column := new MemberAccessExpression(OperandIdentifier("points", 2, 11), "x", false, 2, 11)
    harness.Escape.RecordColumnMemberAccess(column)
    operand: Expression = column

    thrown := harness.Operands.Begin(new ThrowExpression(operand, 2, 5), harness.Reachability)
    OperandRun(harness, thrown, OperandOne(OperandRow("Points")))

    // BOTH: the row escape AND the direct-column escape, in that order.
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "SoA row views cannot be thrown; use the table and row index instead"
    assert harness.Errors[1].Message == "SoA table member 'x' cannot be thrown directly"

    // The same operand under `must` — which returns on the first — is told ONE thing.
    unwrapped := harness.Operands.Begin(new MustExpression(operand, 3, 5), harness.Reachability)
    OperandRun(harness, unwrapped, OperandOne(OperandRow("Points")))

    assert harness.Errors.Count == 3
    assert harness.Errors[2].Message == "SoA row views cannot be unwrapped with 'must'; use the table and row index instead"
}

// ── is ──────────────────────────────────────────────────────────────────

test "is IS bool ON EVERY PATH INCLUDING ITS REFUSAL" {
    harness := OperandDefault()
    clean := harness.Operands.Begin(new IsExpression(OperandIdentifier("v", 2, 11), OperandSimpleType("int", 2, 16), null, 2, 5), harness.Reachability)

    OperandRun(harness, clean, OperandOne(BuiltInTypes.Int))

    assert OperandTypeText(harness.Operands.Result(clean)) == "bool"

    refused := harness.Operands.Begin(new IsExpression(OperandIdentifier("row", 3, 11), OperandSimpleType("int", 3, 16), null, 3, 5), harness.Reachability)

    OperandRun(harness, refused, OperandOne(OperandRow("Points")))

    assert OperandTypeText(harness.Operands.Result(refused)) == "bool"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be tested with 'is'; use the table and row index instead"
}

test "is RESOLVES ITS WRITTEN TYPE AFTER THE STEP AND NOT AT Begin" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new IsExpression(OperandIdentifier("v", 3, 11), OperandSimpleType("int", 3, 20), null, 3, 5), harness.Reachability)

    step := harness.Operands.NextStep(state)

    // Nothing has been resolved yet — the operand is walked first.
    assert step != null
    assert harness.Model.LookupTypeReferenceAtPosition(3, 20) == null

    harness.Operands.Supply(state, BuiltInTypes.Int)

    assert harness.Operands.NextStep(state) == null
    recorded := harness.Model.LookupTypeReferenceAtPosition(3, 20)
    assert recorded != null
    assert OperandTypeText(recorded) == "int"
}

test "is RESOLVES ITS WRITTEN TYPE EVEN WHEN THE OPERAND IS REFUSED" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new IsExpression(OperandIdentifier("row", 2, 11), OperandSimpleType("int", 2, 20), null, 2, 5), harness.Reachability)

    steps := OperandRun(harness, state, OperandOne(OperandRow("Points")))

    // The resolution runs BEFORE the refusal's early return, so a refused operand does not swallow
    // the written type reference's own binding.
    assert steps.Count == 1
    recorded := harness.Model.LookupTypeReferenceAtPosition(2, 20)
    assert recorded != null
    assert OperandTypeText(recorded) == "int"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be tested with 'is'; use the table and row index instead"
}

test "is ASKS THE PATTERN OWNER ONLY WHEN NEITHER REFUSAL FIRED" {
    harness := OperandDefault()
    // A `string` value tested against `int` can never succeed, and the pattern owner says so.
    impossible := harness.Operands.Begin(new IsExpression(OperandIdentifier("s", 2, 11), OperandSimpleType("int", 2, 16), null, 2, 5), harness.Reachability)

    OperandRun(harness, impossible, OperandOne(BuiltInTypes.String))

    reachabilityReports := harness.Errors.Count
    assert reachabilityReports == 1

    // The same test on a REFUSED value asks nothing of the pattern owner: one report, not two.
    refused := harness.Operands.Begin(new IsExpression(OperandIdentifier("row", 3, 11), OperandSimpleType("int", 3, 16), null, 3, 5), harness.Reachability)

    OperandRun(harness, refused, OperandOne(OperandRow("Points")))

    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "SoA row views cannot be tested with 'is'; use the table and row index instead"
}

// ── spread ──────────────────────────────────────────────────────────────

test "spread IS ITS OPERAND UNCHANGED AND JUDGES NO SHAPE" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new SpreadExpression(OperandIdentifier("xs", 2, 11), 2, 5), harness.Reachability)

    // Deliberately NOT a collection: the shape rule belongs to the use site, not to this walk.
    OperandRun(harness, state, OperandOne(BuiltInTypes.Int))

    assert OperandTypeText(harness.Operands.Result(state)) == "int"
    assert harness.Errors.Count == 0
}

test "A SPREAD ROW VIEW IS REFUSED AND ANSWERS unknown" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new SpreadExpression(OperandIdentifier("row", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be spread; use the table and row index instead"
    assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
}

// ── alloc ───────────────────────────────────────────────────────────────

test "alloc IS ITS OPERAND UNCHANGED" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new AllocExpression(OperandIdentifier("v", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(BuiltInTypes.String))

    assert OperandTypeText(harness.Operands.Result(state)) == "string"
    assert harness.Errors.Count == 0
}

test "A ROW VIEW INSIDE alloc IS THE HIDDEN-ALLOCATION REPORT, NOT THE ROW ESCAPE" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new AllocExpression(OperandIdentifier("row", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "this operation would allocate row objects; use column access instead"
    assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
}

// ── must ────────────────────────────────────────────────────────────────

test "must UNWRAPS EXACTLY ONE LAYER OF NULLABILITY" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new MustExpression(OperandIdentifier("v", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandNullable(OperandNullable(BuiltInTypes.Int))))

    assert OperandTypeText(harness.Operands.Result(state)) == "int?"
    assert harness.Errors.Count == 0
}

test "must PASSES unknown THROUGH IN SILENCE" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new MustExpression(OperandIdentifier("v", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(BuiltInTypes.Unknown))

    assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
    assert harness.Errors.Count == 0
}

test "A REDUNDANT must REPORTS AND STILL ANSWERS THE OPERAND TYPE" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new MustExpression(OperandIdentifier("v", 7, 20), 7, 16), harness.Reachability)

    OperandRun(harness, state, OperandOne(BuiltInTypes.String))

    assert harness.Errors.Count == 1
    assert OperandErrorText(harness, 0) == "This 'must' unwrap is redundant — the expression is already known to be 'string'|7:16:4"
    assert OperandTypeText(harness.Operands.Result(state)) == "string"
}

test "A ROW VIEW UNWRAPPED WITH must IS REFUSED BEFORE THE REDUNDANCY RULE" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new MustExpression(OperandIdentifier("row", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be unwrapped with 'must'; use the table and row index instead"
    assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
}

// ── stackalloc ──────────────────────────────────────────────────────────

test "stackalloc IS A Span OF ITS WRITTEN ELEMENT TYPE" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new StackAllocExpression(OperandSimpleType("byte", 2, 16), OperandIdentifier("n", 2, 21), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(BuiltInTypes.Int))

    assert OperandTypeText(harness.Operands.Result(state)) == "Span<byte>"
    assert harness.Errors.Count == 0
}

test "A stackalloc LENGTH MUST IMPLICITLY WIDEN TO int" {
    harness := OperandDefault()
    accepted := new List<TypeInfo>()
    accepted.Add(BuiltInTypes.Int)
    accepted.Add(BuiltInTypes.Short)
    accepted.Add(BuiltInTypes.SByte)
    accepted.Add(BuiltInTypes.Byte)
    accepted.Add(BuiltInTypes.UShort)
    accepted.Add(BuiltInTypes.Char)

    index := 0
    while index < accepted.Count {
        state := harness.Operands.Begin(new StackAllocExpression(OperandSimpleType("byte", 2, 16), OperandIdentifier("n", 2, 21), 2, 5), harness.Reachability)
        OperandRun(harness, state, OperandOne(accepted[index]))
        index = index + 1
    }

    assert harness.Errors.Count == 0

    refused := new List<TypeInfo>()
    refused.Add(BuiltInTypes.Long)
    refused.Add(BuiltInTypes.UInt)
    refused.Add(BuiltInTypes.ULong)
    refused.Add(BuiltInTypes.Double)
    refused.Add(BuiltInTypes.String)

    index = 0
    while index < refused.Count {
        state := harness.Operands.Begin(new StackAllocExpression(OperandSimpleType("byte", 3, 16), OperandIdentifier("n", 3, 21), 3, 5), harness.Reachability)
        OperandRun(harness, state, OperandOne(refused[index]))
        index = index + 1
    }

    assert harness.Errors.Count == 5
    assert OperandErrorText(harness, 0) == "stackalloc length must be an int, but this is a 'long'|3:21:1"
}

test "A NEGATIVE CONSTANT stackalloc LENGTH IS REFUSED, AND ONLY AFTER THE WIDTH RULE PASSES" {
    harness := OperandDefault()
    negative: Expression = new UnaryExpression(UnaryOperator.Negate, new IntLiteralExpression("1", 4, 22), 4, 21)
    state := harness.Operands.Begin(new StackAllocExpression(OperandSimpleType("byte", 4, 16), negative, 4, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(BuiltInTypes.Int))

    assert harness.Errors.Count == 1
    assert OperandErrorText(harness, 0) == "stackalloc length must not be negative|4:21:1"
    assert OperandTypeText(harness.Operands.Result(state)) == "Span<byte>"

    // The same negative literal typed `long` is told about its WIDTH and not about its sign.
    wide := harness.Operands.Begin(new StackAllocExpression(OperandSimpleType("byte", 5, 16), negative, 5, 5), harness.Reachability)

    OperandRun(harness, wide, OperandOne(BuiltInTypes.Long))

    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "stackalloc length must be an int, but this is a 'long'"
}

test "A stackalloc RESOLVES ITS ELEMENT TYPE LAST, AFTER EVERY LENGTH DIAGNOSTIC" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new StackAllocExpression(OperandSimpleType("byte", 9, 26), OperandIdentifier("n", 9, 31), 9, 15), harness.Reachability)

    step := harness.Operands.NextStep(state)

    assert step != null
    assert harness.Model.LookupTypeReferenceAtPosition(9, 26) == null

    harness.Operands.Supply(state, BuiltInTypes.Long)

    assert harness.Operands.NextStep(state) == null
    recorded := harness.Model.LookupTypeReferenceAtPosition(9, 26)
    assert recorded != null
    assert OperandTypeText(recorded) == "byte"

    // The length was refused and the expression is STILL the Span its element type says.
    assert harness.Errors.Count == 1
    assert OperandTypeText(harness.Operands.Result(state)) == "Span<byte>"
}

test "A SoA DIAGNOSTIC ON A stackalloc LENGTH REPLACES BOTH OTHER RULES AND IT IS STILL A Span" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new StackAllocExpression(OperandSimpleType("byte", 2, 16), OperandIdentifier("row", 2, 21), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as a stackalloc length; use the table and row index instead"
    assert OperandTypeText(harness.Operands.Result(state)) == "Span<byte>"
}

// ── tuple ───────────────────────────────────────────────────────────────

test "A TUPLE IS THE TUPLE OF ITS ELEMENTS IN SOURCE ORDER" {
    harness := OperandDefault()
    elements := new List<TupleElement>()
    elements.Add(OperandTupleElement(null, "a", 4, 10))
    elements.Add(OperandTupleElement("second", "b", 4, 13))
    state := harness.Operands.Begin(OperandTupleOf(elements), harness.Reachability)

    answers := new List<TypeInfo?>()
    answers.Add(BuiltInTypes.Int)
    answers.Add(BuiltInTypes.String)
    OperandRun(harness, state, answers)

    assert OperandTupleText(harness.Operands.Result(state)) == "(int, second: string)"
    assert harness.Errors.Count == 0
}

test "A TUPLE ELEMENT IS WALKED UNDER ITS OWN EXPECTED TYPE — THE ARC'S FIRST PER-STEP AMBIENT WRITE" {
    harness := OperandDefault()
    names := new List<string?>()
    names.Add(null)
    names.Add(null)
    types := new List<TypeInfo>()
    types.Add(BuiltInTypes.Byte)
    types.Add(BuiltInTypes.Long)
    saved := harness.Ambient.EnterExpectedTypeIfProvided(OperandExpectedTuple(names, types))

    elements := new List<TupleElement>()
    elements.Add(OperandTupleElement(null, "a", 4, 10))
    elements.Add(OperandTupleElement(null, "b", 4, 13))
    state := harness.Operands.Begin(OperandTupleOf(elements), harness.Reachability)

    answers := new List<TypeInfo?>()
    answers.Add(BuiltInTypes.Byte)
    answers.Add(BuiltInTypes.Long)
    steps := OperandRun(harness, state, answers)

    // Each element saw ITS OWN decomposed expected type while it was the outstanding step.
    assert steps.Count == 2
    assert steps[0].ExpectedBefore == "byte"
    assert steps[1].ExpectedBefore == "long"

    // And the slot is back to the whole tuple annotation once the walk is over.
    assert OperandTupleText(harness.Ambient.CurrentExpectedType) == "(byte, long)"
    harness.Ambient.ExitExpectedType(saved)
    assert harness.Ambient.CurrentExpectedType == null
}

test "A NAMED TUPLE ELEMENT IS MATCHED BY NAME BEFORE POSITION" {
    harness := OperandDefault()
    names := new List<string?>()
    names.Add("x")
    names.Add("y")
    types := new List<TypeInfo>()
    types.Add(BuiltInTypes.Byte)
    types.Add(BuiltInTypes.String)
    saved := harness.Ambient.EnterExpectedTypeIfProvided(OperandExpectedTuple(names, types))

    // Written out of order: `(y: ..., x: ...)` against `(x: byte, y: string)`.
    elements := new List<TupleElement>()
    elements.Add(OperandTupleElement("y", "b", 4, 10))
    elements.Add(OperandTupleElement("x", "a", 4, 13))
    state := harness.Operands.Begin(OperandTupleOf(elements), harness.Reachability)

    answers := new List<TypeInfo?>()
    answers.Add(BuiltInTypes.String)
    answers.Add(BuiltInTypes.Byte)
    steps := OperandRun(harness, state, answers)

    assert steps[0].ExpectedBefore == "string"
    assert steps[1].ExpectedBefore == "byte"
    harness.Ambient.ExitExpectedType(saved)
}

test "AN ANNOTATION SHORTER THAN THE TUPLE CONTRIBUTES NOTHING PAST ITS END" {
    harness := OperandDefault()
    names := new List<string?>()
    names.Add(null)
    types := new List<TypeInfo>()
    types.Add(BuiltInTypes.Byte)
    saved := harness.Ambient.EnterExpectedTypeIfProvided(OperandExpectedTuple(names, types))

    elements := new List<TupleElement>()
    elements.Add(OperandTupleElement(null, "a", 4, 10))
    elements.Add(OperandTupleElement(null, "b", 4, 13))
    state := harness.Operands.Begin(OperandTupleOf(elements), harness.Reachability)

    answers := new List<TypeInfo?>()
    answers.Add(BuiltInTypes.Byte)
    answers.Add(BuiltInTypes.Int)
    steps := OperandRun(harness, state, answers)

    assert steps[0].ExpectedBefore == "byte"
    // The second element inherits the WHOLE annotation, because nothing was pushed for it —
    // `EnterExpectedTypeIfProvided(null)` leaves the slot alone rather than nulling it.
    assert steps[1].ExpectedBefore != "byte"
    assert harness.Ambient.CurrentExpectedType as TupleTypeInfo != null
    harness.Ambient.ExitExpectedType(saved)
}

test "A NON-TUPLE ANNOTATION DECOMPOSES INTO NOTHING" {
    harness := OperandDefault()
    saved := harness.Ambient.EnterExpectedTypeIfProvided(BuiltInTypes.Int)

    elements := new List<TupleElement>()
    elements.Add(OperandTupleElement(null, "a", 4, 10))
    state := harness.Operands.Begin(OperandTupleOf(elements), harness.Reachability)

    steps := OperandRun(harness, state, OperandOne(BuiltInTypes.Int))

    assert steps[0].ExpectedBefore == "int"
    harness.Ambient.ExitExpectedType(saved)
}

test "A REFUSED TUPLE ELEMENT IS STILL AN ELEMENT" {
    harness := OperandDefault()
    elements := new List<TupleElement>()
    elements.Add(OperandTupleElement(null, "row", 4, 10))
    elements.Add(OperandTupleElement(null, "b", 4, 15))
    state := harness.Operands.Begin(OperandTupleOf(elements), harness.Reachability)

    answers := new List<TypeInfo?>()
    answers.Add(OperandRow("Points"))
    answers.Add(BuiltInTypes.Int)
    OperandRun(harness, state, answers)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be stored in a tuple; use the table and row index instead"
    result := harness.Operands.Result(state) as TupleTypeInfo
    assert result != null
    assert result.Elements.Count == 2
    assert result.Elements[0].Type as SoaRowTypeInfo != null
    assert OperandTypeText(result.Elements[1].Type) == "int"
}

test "A TUPLE ELEMENT'S REPORT LANDS BETWEEN ITS STEP AND THE NEXT ONE" {
    harness := OperandDefault()
    elements := new List<TupleElement>()
    elements.Add(OperandTupleElement(null, "row", 4, 10))
    elements.Add(OperandTupleElement(null, "b", 4, 15))
    state := harness.Operands.Begin(OperandTupleOf(elements), harness.Reachability)

    answers := new List<TypeInfo?>()
    answers.Add(OperandRow("Points"))
    answers.Add(BuiltInTypes.Int)
    steps := OperandRun(harness, state, answers)

    assert steps[0].ErrorsBefore == 0
    assert steps[1].ErrorsBefore == 1
}

// ── await ───────────────────────────────────────────────────────────────

test "await OF A REFLECTED Task<T> IS ITS T" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new AwaitExpression(OperandIdentifier("t", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandReflected(typeof(Task<int>))))

    assert OperandTypeText(harness.Operands.Result(state)) == "int"
    assert harness.Errors.Count == 0
}

test "await OF A UNIT TASK IS void" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new AwaitExpression(OperandIdentifier("t", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandReflected(typeof(Task))))

    assert OperandTypeText(harness.Operands.Result(state)) == "void"
    assert harness.Errors.Count == 0
}

test "await OF A NULLABLE TASK STILL FINDS THE AWAITER" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new AwaitExpression(OperandIdentifier("t", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandNullable(OperandReflected(typeof(Task<int>)))))

    assert OperandTypeText(harness.Operands.Result(state)) == "int"
    assert harness.Errors.Count == 0
}

test "await FINDS A DUCK-TYPED AWAITER THROUGH REFLECTION" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new AwaitExpression(OperandIdentifier("t", 2, 11), 2, 5), harness.Reachability)

    // A ValueTask<string> is not one of the source-known shapes when it arrives reflected under a
    // non-core context; the GetAwaiter()/GetResult() pattern is what answers for it either way.
    OperandRun(harness, state, OperandOne(OperandReflected(typeof(ValueTask<string>))))

    assert OperandTypeText(harness.Operands.Result(state)) == "string"
    assert harness.Errors.Count == 0
}

test "await OF A PLAIN VALUE IS ACCUSED AND ANSWERS unknown" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new AwaitExpression(OperandIdentifier("n", 6, 15), 6, 9), harness.Reachability)

    OperandRun(harness, state, OperandOne(BuiltInTypes.Int))

    assert harness.Errors.Count == 1
    assert OperandErrorText(harness, 0) == "await expression needs an awaitable value, but this expression is 'int'|6:15:1"
    assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
}

test "await LEAVES A CLASS, STRUCT, RECORD AND INTERFACE ALONE" {
    harness := OperandDefault()
    shapes := new List<TypeInfo>()
    shapes.Add(OperandClassType())
    shapes.Add(OperandStructType())
    shapes.Add(OperandRecordType())
    shapes.Add(OperandInterfaceType())

    index := 0
    while index < shapes.Count {
        state := harness.Operands.Begin(new AwaitExpression(OperandIdentifier("v", 2, 11), 2, 5), harness.Reachability)
        OperandRun(harness, state, OperandOne(shapes[index]))
        assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
        index = index + 1
    }

    assert harness.Errors.Count == 0
}

test "await OF unknown IS unknown IN SILENCE" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new AwaitExpression(OperandIdentifier("v", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(BuiltInTypes.Unknown))

    assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
    assert harness.Errors.Count == 0
}

test "AN AWAITED ROW VIEW IS REFUSED AND THE AWAITABLE RULE IS NOT THEN ALSO APPLIED" {
    harness := OperandDefault()
    state := harness.Operands.Begin(new AwaitExpression(OperandIdentifier("row", 2, 11), 2, 5), harness.Reachability)

    OperandRun(harness, state, OperandOne(OperandRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be awaited; use the table and row index instead"
    assert OperandTypeText(harness.Operands.Result(state)) == "unknown"
}

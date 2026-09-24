namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT THE COMPILER KNOWS ABOUT A TYPE WITHOUT EVALUATING ANYTHING — `typeof`,
// `sizeof`, `nameof` and `default`, the expression walk's second N#-owned territory.
//
// The family is four operators with one shape: none of them evaluates its operand, and the only
// walking any of them does is the one `nameof` must do to find out whether its target is nameable.
// So three of the four take NO steps and the fourth takes exactly ONE, and every contract asserts
// three things at once — which steps were asked for, in what order, and what the walk answered.
//
// The six things it is easy to get wrong:
//
// (1) THE TWO TYPE RESOLUTIONS ARE FOR THEIR DIAGNOSTICS, NOT FOR AN ANSWER. `typeof(int)` is a
// `System.Type` and `sizeof(long)` is an `int`; neither answer has anything to do with the resolved
// operand type. An implementation that returned the resolved type would be invisible in most of the
// corpus and wrong everywhere it mattered. The resolution is proved to have HAPPENED by reading the
// semantic model back, and the answer is proved to be unrelated to it.
//
// (2) `typeof` ANSWERS FROM THE PROJECT'S METADATA CONTEXT, NOT THE COMPILER'S. With a real
// MetadataLoadContext it is that context's `System.Type`; with none it is `unknown`. Reaching for
// `typeof(Type)` here would answer with the COMPILER's reference set.
//
// (3) `nameof` REPORTS TWO DIFFERENT MISTAKES AND THE FIRST ONE STOPS. A row-view target is refused
// as an escape and the shape rule is NOT then also reported — one mistake, one report.
//
// (4) `nameof` IS A `string` ON EVERY PATH, including both refusals and including a target that
// answers nothing at all. A broken target must not cascade into the enclosing expression.
//
// (5) `default` IS THE ONLY ONE OF THE FOUR THAT READS THE TARGET-TYPING SLOT, and it reads it AT
// `Begin`. The three syntactic reads `Analyzer.cs` performed — the presence test, the SoA refusal's
// operand and the answer — are one instant, which is only safe because the walk takes no step.
//
// (6) THE SoA REFUSAL LOOKS THROUGH NULLABILITY AND ALIASES, BUT THE ANSWER DOES NOT. `Table?` is
// refused; a nullable `int?` target answers `int?` and not `int`.
class ConstantStep {
    Kind: int
    NodeName: string
    Line: int
    Column: int
    ErrorsBefore: int
    ResultBefore: string

    constructor(kind: int, nodeName: string, line: int, column: int, errorsBefore: int, resultBefore: string) {
        Kind = kind
        NodeName = nodeName
        Line = line
        Column = column
        ErrorsBefore = errorsBefore
        ResultBefore = resultBefore
    }
}

class ConstantHarness {
    Constants: AnalyzerCompileTimeConstants
    Ambient: AnalyzerAmbientContext
    Context: AnalyzerDeclarationContext
    Model: SemanticModel
    Errors: List<CompilerError>

    constructor(constants: AnalyzerCompileTimeConstants, ambient: AnalyzerAmbientContext, context: AnalyzerDeclarationContext, model: SemanticModel, errors: List<CompilerError>) {
        Constants = constants
        Ambient = ambient
        Context = context
        Model = model
        Errors = errors
    }
}

func ConstantPath(): string {
    return Path.GetFullPath("compile-time-constants-contract.nl")
}

func ConstantHarnessWith(sourceText: string?): ConstantHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(ConstantPath(), sourceText)
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
    resolver.BeginAnalysis(ConstantPath(), null, model, new BindingMap())
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    constants := new AnalyzerCompileTimeConstants(diagnostics, spans, context, resolver, ambient, escape)
    return new ConstantHarness(constants, ambient, context, model, errors)
}

func ConstantDefault(): ConstantHarness {
    return ConstantHarnessWith(null)
}

func ConstantTypeText(candidate: TypeInfo?): string {
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

func ConstantNodeName(node: Expression?): string {
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

// ── the constant driver, exactly as `Analyzer.cs` writes it ─────────────
//
// The one difference is that the expression step is ANSWERED with a fixed value rather than by
// re-entering the analyzer's own walk, which is the one thing a contract cannot replay. Every step is
// recorded with the error count AND the walk's result AS THE STEP WAS HANDED OUT, so the two
// invariants that matter — the result is settled before the first step, and the escape report lands
// after it — are readable off the row stream.
func ConstantRun(harness: ConstantHarness, state: CompileTimeConstantState, answer: TypeInfo?): List<ConstantStep> {
    steps := new List<ConstantStep>()
    step := harness.Constants.NextStep(state)
    while step != null {
        steps.Add(new ConstantStep(step.Kind, ConstantNodeName(step.Node), step.Line, step.Column, harness.Errors.Count, ConstantTypeText(harness.Constants.Result(state))))
        harness.Constants.Supply(state, answer)
        step = harness.Constants.NextStep(state)
    }

    return steps
}

func ConstantIdentifier(name: string, line: int, column: int): Expression {
    expression: Expression = new IdentifierExpression(name, line, column)
    return expression
}

func ConstantSimpleType(name: string, line: int, column: int): TypeReference {
    reference: TypeReference = new SimpleTypeReference(name, line, column)
    return reference
}

func ConstantTypeOf(name: string, line: int, column: int): Expression {
    expression: Expression = new TypeOfExpression(ConstantSimpleType(name, line, column), 3, 5)
    return expression
}

func ConstantSizeOf(name: string, line: int, column: int): Expression {
    expression: Expression = new SizeOfExpression(ConstantSimpleType(name, line, column), 3, 5)
    return expression
}

func ConstantNameOf(target: Expression): Expression {
    expression: Expression = new NameofExpression(target, 3, 5)
    return expression
}

func ConstantDefaultAt(line: int, column: int): Expression {
    expression: Expression = new DefaultExpression(line, column)
    return expression
}

func ConstantTable(name: string): TypeInfo {
    columns := new List<SoaColumnInfo>()
    table: TypeInfo = new SoaRecordTypeInfo(new SoaRecordDeclarationInfo(name, columns, 1, 1))
    return table
}

func ConstantRow(name: string): TypeInfo {
    columns := new List<SoaColumnInfo>()
    row: TypeInfo = new SoaRowTypeInfo(new SoaRecordDeclarationInfo(name, columns, 1, 1))
    return row
}

func ConstantErrorText(harness: ConstantHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + ":" + error.Length.ToString()
}

// The fact bag over a real MetadataLoadContext, opened the way the rest of the compiler opens one, so
// the `typeof` contract exercises the true resolution rather than a stub.
func ConstantProbeFacts(context: MetadataLoadContext): AnalyzerWellKnownTypes {
    core := context.LoadFromAssemblyName("System.Runtime")
    return new AnalyzerWellKnownTypes(context, core)
}

// ── the three forms that answer without a step ──────────────────────────

test "typeof ANSWERS unknown WITH NO METADATA CONTEXT AND TAKES NO STEPS" {
    harness := ConstantDefault()
    state := harness.Constants.Begin(ConstantTypeOf("int", 7, 20), null)

    steps := ConstantRun(harness, state, null)

    assert state.Form == 0
    assert steps.Count == 0
    assert ConstantTypeText(harness.Constants.Result(state)) == "unknown"
}

test "typeof ANSWERS THE PROJECT CONTEXT'S System.Type, NOT THE COMPILER'S" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null

        facts := ConstantProbeFacts(context)
        harness := ConstantDefault()
        state := harness.Constants.Begin(ConstantTypeOf("int", 7, 20), facts)

        assert ConstantRun(harness, state, null).Count == 0
        assert ConstantTypeText(harness.Constants.Result(state)) == "Type"

        reflected := harness.Constants.Result(state) as ReflectionTypeInfo
        assert reflected != null
        // The METADATA type, not the compiler's own runtime `System.Type`.
        assert Object.ReferenceEquals(reflected.Type, facts.SystemType)
        assert reflected.Type.FullName == "System.Type"
    } finally {
        scan.Dispose()
    }
}

test "typeof RESOLVES ITS TYPE REFERENCE AND THEN DISCARDS THE RESULT" {
    harness := ConstantDefault()
    state := harness.Constants.Begin(ConstantTypeOf("int", 7, 20), null)

    // The resolution HAPPENED: the semantic model carries it at the reference's own position.
    recorded := harness.Model.LookupTypeReferenceAtPosition(7, 20)
    assert recorded != null
    assert ConstantTypeText(recorded) == "int"

    // And the walk's answer has nothing to do with it.
    assert ConstantTypeText(harness.Constants.Result(state)) != "int"
}

test "sizeof IS int WHATEVER ITS OPERAND TYPE IS, AND TAKES NO STEPS" {
    harness := ConstantDefault()

    small := harness.Constants.Begin(ConstantSizeOf("byte", 7, 20), null)
    wide := harness.Constants.Begin(ConstantSizeOf("long", 8, 20), null)

    assert small.Form == 1
    assert ConstantRun(harness, small, null).Count == 0
    assert ConstantTypeText(harness.Constants.Result(small)) == "int"
    assert ConstantTypeText(harness.Constants.Result(wide)) == "int"
}

test "sizeof RESOLVES ITS TYPE REFERENCE TOO" {
    harness := ConstantDefault()
    harness.Constants.Begin(ConstantSizeOf("long", 9, 14), null)

    recorded := harness.Model.LookupTypeReferenceAtPosition(9, 14)
    assert recorded != null
    assert ConstantTypeText(recorded) == "long"
}

test "NEITHER typeof NOR sizeof READS THE TARGET-TYPING SLOT" {
    harness := ConstantDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)

    typeOf := harness.Constants.Begin(ConstantTypeOf("int", 7, 20), null)
    sizeOf := harness.Constants.Begin(ConstantSizeOf("int", 8, 20), null)

    assert ConstantTypeText(harness.Constants.Result(typeOf)) == "unknown"
    assert ConstantTypeText(harness.Constants.Result(sizeOf)) == "int"
    assert ConstantTypeText(harness.Constants.Result(sizeOf)) != "byte"
}

test "AN EXPRESSION THAT IS NOT ONE OF THE FOUR ANSWERS unknown AND TAKES NO STEPS" {
    harness := ConstantDefault()
    state := harness.Constants.Begin(ConstantIdentifier("x", 3, 9), null)

    steps := ConstantRun(harness, state, null)

    assert state.Form == -1
    assert steps.Count == 0
    assert ConstantTypeText(harness.Constants.Result(state)) == "unknown"
    assert harness.Errors.Count == 0
}

// ── the one form that takes a step ──────────────────────────────────────

test "nameof TAKES EXACTLY ONE STEP, OF KIND 1, CARRYING THE TARGET'S OWN POSITION" {
    harness := ConstantDefault()
    state := harness.Constants.Begin(ConstantNameOf(ConstantIdentifier("value", 11, 27)), null)

    steps := ConstantRun(harness, state, BuiltInTypes.Int)

    assert state.Form == 2
    assert steps.Count == 1
    assert steps[0].Kind == 1
    assert steps[0].NodeName == "value"
    // The TARGET's position, not the `nameof`'s (which is 3:5).
    assert steps[0].Line == 11
    assert steps[0].Column == 27
}

test "nameof IS A string BEFORE ITS STEP AND AFTER IT" {
    harness := ConstantDefault()
    state := harness.Constants.Begin(ConstantNameOf(ConstantIdentifier("value", 11, 27)), null)

    // Settled at `Begin`, before any step is handed out.
    assert ConstantTypeText(harness.Constants.Result(state)) == "string"

    steps := ConstantRun(harness, state, BuiltInTypes.Int)

    assert steps[0].ResultBefore == "string"
    assert ConstantTypeText(harness.Constants.Result(state)) == "string"
}

test "AN IDENTIFIER TARGET AND A MEMBER-ACCESS TARGET ARE BOTH SILENT" {
    harness := ConstantDefault()

    identifier := harness.Constants.Begin(ConstantNameOf(ConstantIdentifier("value", 11, 27)), null)
    ConstantRun(harness, identifier, BuiltInTypes.Int)

    memberTarget: Expression = new MemberAccessExpression(ConstantIdentifier("person", 12, 27), "Name", false, 12, 34)
    member := harness.Constants.Begin(ConstantNameOf(memberTarget), null)
    ConstantRun(harness, member, BuiltInTypes.String)

    assert harness.Errors.Count == 0
    assert ConstantTypeText(harness.Constants.Result(identifier)) == "string"
    assert ConstantTypeText(harness.Constants.Result(member)) == "string"
}

test "A TARGET THAT IS NEITHER AN IDENTIFIER NOR A MEMBER ACCESS IS REFUSED AT ITS OWN SPAN" {
    harness := ConstantDefault()
    target: Expression = new IntLiteralExpression("42", 11, 27)
    state := harness.Constants.Begin(ConstantNameOf(target), null)

    ConstantRun(harness, state, BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    // Position and length are the TARGET's span — the literal `42` is two columns wide.
    assert ConstantErrorText(harness, 0) == "nameof can only name an identifier or member access|11:27:2"
    assert harness.Errors[0].Suggestion == "Use nameof(value) or nameof(value.Member)."
    // And the answer is unmoved.
    assert ConstantTypeText(harness.Constants.Result(state)) == "string"
}

test "THE ROW-VIEW REFUSAL STOPS: ONE MISTAKE IS TOLD ONCE, NOT TWICE" {
    harness := ConstantDefault()
    // A call is not a nameable shape EITHER, so a walk that did not stop would report both.
    target: Expression = new CallExpression(ConstantIdentifier("rowAt", 11, 27), new List<Argument>(), null, 11, 27)
    state := harness.Constants.Begin(ConstantNameOf(target), null)

    ConstantRun(harness, state, ConstantRow("Particle"))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as a nameof target; use the table and row index instead"
    assert ConstantTypeText(harness.Constants.Result(state)) == "string"
}

test "THE ROW REPORT'S OPERAND IS THE STEP'S ANSWER, WHICH IS WHY THE WALK SUSPENDS" {
    harness := ConstantDefault()
    target := ConstantIdentifier("value", 11, 27)

    // Same node, same walk, two different answers — and only one of them reports.
    refused := harness.Constants.Begin(ConstantNameOf(target), null)
    ConstantRun(harness, refused, ConstantRow("Particle"))
    assert harness.Errors.Count == 1

    allowed := harness.Constants.Begin(ConstantNameOf(target), null)
    ConstantRun(harness, allowed, BuiltInTypes.Int)
    assert harness.Errors.Count == 1
}

test "A TARGET THAT ANSWERS NOTHING LEAVES nameof A string AND REPORTS NOTHING" {
    harness := ConstantDefault()
    state := harness.Constants.Begin(ConstantNameOf(ConstantIdentifier("value", 11, 27)), null)

    steps := ConstantRun(harness, state, null)

    assert steps.Count == 1
    assert state.TargetType != null
    assert ConstantTypeText(state.TargetType) == "unknown"
    assert harness.Errors.Count == 0
    assert ConstantTypeText(harness.Constants.Result(state)) == "string"
}

// ── the target-typed form ───────────────────────────────────────────────

test "default IS THE AMBIENT EXPECTED TYPE AND TAKES NO STEPS" {
    harness := ConstantDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)

    state := harness.Constants.Begin(ConstantDefaultAt(4, 17), null)
    steps := ConstantRun(harness, state, null)

    assert state.Form == 3
    assert steps.Count == 0
    assert ConstantTypeText(harness.Constants.Result(state)) == "byte"
    assert harness.Errors.Count == 0
}

test "default WITH NO TARGET IS AN ERROR AT ITS OWN POSITION, SEVEN COLUMNS WIDE" {
    harness := ConstantDefault()
    state := harness.Constants.Begin(ConstantDefaultAt(4, 17), null)

    ConstantRun(harness, state, null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.CannotInferType
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 17
    assert harness.Errors[0].Length == 7
    assert ConstantTypeText(harness.Constants.Result(state)) == "unknown"
}

test "default READS THE TARGET-TYPING SLOT AT Begin, NOT AT Result" {
    harness := ConstantDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)
    state := harness.Constants.Begin(ConstantDefaultAt(4, 17), null)

    // Moving the slot afterwards must not move the answer.
    harness.Ambient.EnterExpectedType(BuiltInTypes.String)
    ConstantRun(harness, state, null)

    assert ConstantTypeText(harness.Constants.Result(state)) == "byte"
}

test "AN SoA TABLE CAN NEVER BE DEFAULT-INITIALIZED, AND THE FIX NAMES BOTH SPELLINGS" {
    harness := ConstantDefault()
    harness.Ambient.EnterExpectedType(ConstantTable("Particle"))

    state := harness.Constants.Begin(ConstantDefaultAt(4, 17), null)
    ConstantRun(harness, state, null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert ConstantErrorText(harness, 0) == "SoA table 'Particle' cannot be default-initialized|4:17:7"
    assert harness.Errors[0].Suggestion == "Use new Particle(capacity) or Particle.wrap(..., length: count) so every backing column array is valid."
    // A refused `default` answers nothing rather than the table.
    assert ConstantTypeText(harness.Constants.Result(state)) == "unknown"
}

test "THE TABLE REFUSAL LOOKS THROUGH ONE LAYER OF NULLABILITY" {
    harness := ConstantDefault()
    nullableTable: TypeInfo = new NullableTypeInfo(ConstantTable("Particle"))
    harness.Ambient.EnterExpectedType(nullableTable)

    state := harness.Constants.Begin(ConstantDefaultAt(4, 17), null)
    ConstantRun(harness, state, null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table 'Particle' cannot be default-initialized"
    assert ConstantTypeText(harness.Constants.Result(state)) == "unknown"
}

test "BUT THE ANSWER DOES NOT LOOK THROUGH NULLABILITY: default OF int? IS int?" {
    harness := ConstantDefault()
    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    harness.Ambient.EnterExpectedType(nullable)

    state := harness.Constants.Begin(ConstantDefaultAt(4, 17), null)

    assert harness.Errors.Count == 0
    assert ConstantTypeText(harness.Constants.Result(state)) == "int?"
}

test "THE NULLABLE UNWRAP IS THIS OWNER'S OWN, AND IT LOOKS THROUGH ALIASES FIRST" {
    harness := ConstantDefault()
    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.Byte)

    assert ConstantTypeText(harness.Constants.NonNullableType(nullable)) == "byte"
    // A non-nullable candidate is answered unchanged rather than resolved away.
    assert ConstantTypeText(harness.Constants.NonNullableType(BuiltInTypes.String)) == "string"
}

// ── the protocol invariants ─────────────────────────────────────────────

test "NO FORM ASKS FOR A KIND OTHER THAN 1" {
    harness := ConstantDefault()

    every := new List<ConstantStep>()
    every.AddRange(ConstantRun(harness, harness.Constants.Begin(ConstantTypeOf("int", 7, 20), null), null))
    every.AddRange(ConstantRun(harness, harness.Constants.Begin(ConstantSizeOf("int", 8, 20), null), null))
    every.AddRange(ConstantRun(harness, harness.Constants.Begin(ConstantNameOf(ConstantIdentifier("v", 9, 20)), null), BuiltInTypes.Int))
    harness.Ambient.EnterExpectedType(BuiltInTypes.Int)
    every.AddRange(ConstantRun(harness, harness.Constants.Begin(ConstantDefaultAt(10, 20), null), null))

    assert every.Count == 1
    for step in every {
        assert step.Kind == 1
    }
}

test "THE STEP COUNT IS THE FORM: THREE OF FOUR ARE ZERO AND nameof IS EXACTLY ONE" {
    harness := ConstantDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.Int)

    assert ConstantRun(harness, harness.Constants.Begin(ConstantTypeOf("int", 7, 20), null), null).Count == 0
    assert ConstantRun(harness, harness.Constants.Begin(ConstantSizeOf("int", 8, 20), null), null).Count == 0
    assert ConstantRun(harness, harness.Constants.Begin(ConstantDefaultAt(10, 20), null), null).Count == 0
    assert ConstantRun(harness, harness.Constants.Begin(ConstantNameOf(ConstantIdentifier("v", 9, 20)), null), BuiltInTypes.Int).Count == 1
}

test "A WALK THAT ASKED FOR NOTHING FOLDS IN NOTHING WHEN SUPPLIED ANYWAY" {
    harness := ConstantDefault()
    state := harness.Constants.Begin(ConstantSizeOf("int", 8, 20), null)

    harness.Constants.Supply(state, ConstantRow("Particle"))

    assert ConstantTypeText(state.TargetType) == "unknown"
    assert ConstantTypeText(harness.Constants.Result(state)) == "int"
    assert harness.Errors.Count == 0
}

test "A FINISHED WALK KEEPS ANSWERING null AND ITS RESULT IS STABLE" {
    harness := ConstantDefault()
    state := harness.Constants.Begin(ConstantNameOf(ConstantIdentifier("value", 11, 27)), null)

    ConstantRun(harness, state, BuiltInTypes.Int)

    assert harness.Constants.NextStep(state) == null
    assert harness.Constants.NextStep(state) == null
    assert ConstantTypeText(harness.Constants.Result(state)) == "string"
    assert ConstantTypeText(harness.Constants.Result(state)) == "string"
}

test "EVERY FORM'S RESULT IS SETTLED BEFORE THE DRIVER RUNS AT ALL" {
    harness := ConstantDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)

    typeOf := harness.Constants.Begin(ConstantTypeOf("int", 7, 20), null)
    sizeOf := harness.Constants.Begin(ConstantSizeOf("int", 8, 20), null)
    nameOf := harness.Constants.Begin(ConstantNameOf(ConstantIdentifier("v", 9, 20)), null)
    defaulted := harness.Constants.Begin(ConstantDefaultAt(10, 20), null)

    before := ConstantTypeText(harness.Constants.Result(typeOf)) + "/" + ConstantTypeText(harness.Constants.Result(sizeOf)) + "/" + ConstantTypeText(harness.Constants.Result(nameOf)) + "/" + ConstantTypeText(harness.Constants.Result(defaulted))

    ConstantRun(harness, typeOf, null)
    ConstantRun(harness, sizeOf, null)
    ConstantRun(harness, nameOf, ConstantRow("Particle"))
    ConstantRun(harness, defaulted, null)

    after := ConstantTypeText(harness.Constants.Result(typeOf)) + "/" + ConstantTypeText(harness.Constants.Result(sizeOf)) + "/" + ConstantTypeText(harness.Constants.Result(nameOf)) + "/" + ConstantTypeText(harness.Constants.Result(defaulted))

    assert before == "unknown/int/string/byte"
    assert after == before
}

test "default'S DIAGNOSTIC LANDS AT Begin, BEFORE THE DRIVER ASKS FOR ANYTHING" {
    harness := ConstantDefault()

    state := harness.Constants.Begin(ConstantDefaultAt(4, 17), null)

    // Not one step has been asked for yet, and the report is already in.
    assert harness.Errors.Count == 1
    assert ConstantRun(harness, state, null).Count == 0
    assert harness.Errors.Count == 1
}

test "nameof'S DIAGNOSTIC LANDS AFTER ITS STEP, NOT BEFORE" {
    harness := ConstantDefault()
    target: Expression = new IntLiteralExpression("42", 11, 27)
    state := harness.Constants.Begin(ConstantNameOf(target), null)

    // Nothing yet: the shape rule cannot run until the target has been walked.
    assert harness.Errors.Count == 0

    steps := ConstantRun(harness, state, BuiltInTypes.Int)

    assert steps[0].ErrorsBefore == 0
    assert harness.Errors.Count == 1
}

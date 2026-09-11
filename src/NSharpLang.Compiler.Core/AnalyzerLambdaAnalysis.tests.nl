namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT A LAMBDA MEANS AND WHAT SUBSCRIBING TO AN EVENT MEANS.
//
// Both members behind these were `private` in `Analyzer.cs`. `AnalyzeLambda` had nine call sites in
// four owners and `AnalyzeOnSubscription` exactly one, so neither had any direct pinning at all —
// only whatever end-to-end diagnostic a broken lambda happened to produce. These go at the six
// things the pair is easy to get wrong:
//
// (1) THE DELEGATE DOOR IS FOUR DOORS AND THE ORDER MATTERS. A function type IS a signature; a
// reflected delegate becomes one; an expression-tree target becomes one THROUGH the delegate it
// wraps; and an N#-written generic becomes one only after converting to a CLR type. Anything else
// names NONE — and "none" is not "unknown": with no signature a lambda's parameters have no
// inference source at all, which is the difference between silence and a hard error.
//
// (2) THE UNINFERABLE-PARAMETER REPORT IS ONCE PER LAMBDA, NOT ONCE PER PARAMETER. A lambda whose
// delegate type nothing names has EVERY parameter uninferable, and the user has made one mistake.
//
// (3) THE PARAMETER'S TYPE LANDS IN THE SIGNATURE ONLY AFTER IT IS DECLARED AND RECORDED, because
// the NEXT parameter's inference index is that list's COUNT. Appending early shifts every remaining
// parameter's inferred type by one — a bug that types a two-parameter lambda plausibly and wrongly.
//
// (4) A BLOCK BODY'S RETURN TYPE IS THE SIGNATURE'S, WHATEVER THE BLOCK DOES. The block's own
// `return`s are measured against it by the nested-body boundary; they do not change the lambda's
// type. An expression body's type IS its body's answer.
//
// (5) THE EXPRESSION-TREE REPORTS ARE ORDERED AGAINST THE BODY AND AGAINST EACH OTHER. The block
// report fires BEFORE the block is walked; the unsupported-expression report fires only when the
// body walk AND both SoA escape rules left the diagnostic count untouched.
//
// (6) `on` ANALYSES ITS HANDLER ON EVERY PATH, and which expected type it hands over is the whole
// difference between the five paths: the four failures pass NONE and switch the inference report
// OFF, because a handler whose delegate type could not be discovered must not ALSO be told its
// parameters are uninferable.
class LambdaHarness {
    Owner: AnalyzerLambdaAnalysis
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Model: SemanticModel
    Diagnostics: AnalyzerDiagnosticSink

    constructor(owner: AnalyzerLambdaAnalysis, errors: List<CompilerError>, scopes: AnalyzerScopeStack, model: SemanticModel, diagnostics: AnalyzerDiagnosticSink) {
        Owner = owner
        Errors = errors
        Scopes = scopes
        Model = model
        Diagnostics = diagnostics
    }
}

// One replayed step, with the scope DEPTH as the step was handed out, which is what pins the window
// each operation happens in rather than only the operation itself.
class LambdaStep {
    Kind: int
    Name: string?
    CarriedType: string
    ExpectedType: string
    Line: int
    Column: int
    Depth: int
    ErrorsBefore: int

    constructor(kind: int, name: string?, carriedType: string, expectedType: string, line: int, column: int, depth: int, errorsBefore: int) {
        Kind = kind
        Name = name
        CarriedType = carriedType
        ExpectedType = expectedType
        Line = line
        Column = column
        Depth = depth
        ErrorsBefore = errorsBefore
    }
}

func LambdaPath(): string {
    return Path.GetFullPath("lambda-contract.nl")
}

func LambdaHarnessOf(): LambdaHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(LambdaPath(), null)
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
    resolver.BeginAnalysis(LambdaPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    expressionTrees := new AnalyzerExpressionTreeValidator(diagnostics, spans, scopes, context, probe, null)
    owner := new AnalyzerLambdaAnalysis(diagnostics, spans, context, resolver, clrConversion, facts, escape, expressionTrees)
    return new LambdaHarness(owner, errors, scopes, model, diagnostics)
}

func LambdaTypeText(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    boxed: object = candidate
    rendered := boxed.ToString()
    if rendered == null {
        return "<blank>"
    }

    return rendered
}

// ── AST shapes ────────────────────────────────────────────────────────────────

func LambdaParams(): List<Parameter> {
    return new List<Parameter>()
}

// The parser writes `var` as the placeholder type for an untyped lambda parameter, so this is the
// shape EVERY lambda a program can spell has.
func LambdaParam(parameters: List<Parameter>, name: string, line: int, column: int) {
    parameters.Add(new Parameter(name, new SimpleTypeReference("var", line, column), null, false, ParameterModifier.None, null, line, column, false, null))
}

func LambdaTypedParam(parameters: List<Parameter>, name: string, typeName: string, line: int, column: int) {
    parameters.Add(new Parameter(name, new SimpleTypeReference(typeName, line, column), null, false, ParameterModifier.None, null, line, column, false, null))
}

func LambdaExpr(parameters: List<Parameter>, body: Expression): LambdaExpression {
    return new LambdaExpression(parameters, body, null, 3, 5)
}

func LambdaBlock(parameters: List<Parameter>, body: BlockStatement): LambdaExpression {
    return new LambdaExpression(parameters, null, body, 3, 5)
}

func LambdaBody(): Expression {
    return new IntLiteralExpression("7", 3, 12)
}

// The smallest body an expression tree REFUSES: a bare identifier that is not one of the lambda's
// own parameters, which is a captured variable or a type name and is neither in a tree.
func LambdaCapturedIdentifier(): Expression {
    return new IdentifierExpression("captured", 3, 12)
}

func LambdaEmptyBlock(): BlockStatement {
    return new BlockStatement(new List<Statement>(), 3, 12)
}

func LambdaSignature(parameterTypes: List<TypeInfo>, returnType: TypeInfo): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.ParameterTypes = parameterTypes
    signature.ReturnType = returnType
    return signature
}

func LambdaTypes(): List<TypeInfo> {
    return new List<TypeInfo>()
}

// ── the driver, exactly as `Analyzer.cs` writes it ────────────────────────────
//
// The scope operations are performed FOR REAL — kind 2 pushes a function scope, kind 3 writes the
// symbol, kind 6 pops — so the depth recorded on every step is the depth the analyzer would have
// been at. Kind 5 records the statement rather than re-entering the statement dispatch, which is
// the one thing a contract cannot replay. The expression-tree validator is NOT a step and is not
// replayed either: the walk holds it and calls it, so what a contract sees of it is its REPORTS.
func LambdaRun(harness: LambdaHarness, state: LambdaAnalysisState, bodyAnswer: TypeInfo?): List<LambdaStep> {
    steps := new List<LambdaStep>()
    step := harness.Owner.NextLambdaStep(state)
    while step != null {
        steps.Add(new LambdaStep(step.Kind, step.Name, LambdaTypeText(step.CarriedType), LambdaTypeText(step.ExpectedType), step.Line, step.Column, harness.Scopes.Count, harness.Errors.Count))

        if step.Kind == 2 {
            harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Function), step.Line, step.Column)
        }

        if step.Kind == 3 {
            name := step.Name
            if name != null {
                harness.Scopes.Peek().Symbols[name] = step.CarriedType
            }
        }

        if step.Kind == 6 {
            harness.Scopes.NoteLine(99)
            harness.Scopes.Pop(harness.Model)
        }

        answer: TypeInfo? = null
        if step.Kind == 1 {
            answer = bodyAnswer
        }

        harness.Owner.SupplyLambdaStep(state, answer)
        step = harness.Owner.NextLambdaStep(state)
    }

    return steps
}

// The same driver, except that the body walk REPORTS while it runs. That is the one thing the
// plain driver cannot show: the tree report's precondition is a diagnostic COUNT taken before the
// body step and compared after it, so a report made by the driver at the right moment is the only
// way a contract can exercise the silencing path.
func LambdaRunReportingBody(harness: LambdaHarness, state: LambdaAnalysisState, bodyAnswer: TypeInfo?): List<LambdaStep> {
    steps := new List<LambdaStep>()
    step := harness.Owner.NextLambdaStep(state)
    while step != null {
        steps.Add(new LambdaStep(step.Kind, step.Name, LambdaTypeText(step.CarriedType), LambdaTypeText(step.ExpectedType), step.Line, step.Column, harness.Scopes.Count, harness.Errors.Count))

        if step.Kind == 2 {
            harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Function), step.Line, step.Column)
        }

        if step.Kind == 6 {
            harness.Scopes.NoteLine(99)
            harness.Scopes.Pop(harness.Model)
        }

        answer: TypeInfo? = null
        if step.Kind == 1 {
            harness.Diagnostics.Report(ErrorCode.TypeMismatch, "the body walk complained", 3, 12, null, 0)
            answer = bodyAnswer
        }

        harness.Owner.SupplyLambdaStep(state, answer)
        step = harness.Owner.NextLambdaStep(state)
    }

    return steps
}

func LambdaTranscript(steps: List<LambdaStep>): string {
    rendered := ""
    index := 0
    while index < steps.Count {
        if rendered.Length > 0 {
            rendered = rendered + " "
        }

        rendered = rendered + steps[index].Kind.ToString()
        index = index + 1
    }

    return rendered
}

// ── the delegate door ─────────────────────────────────────────────────────────

test "a function type IS the signature and its parameter types are handed to the lambda positionally" {
    harness := LambdaHarnessOf()
    parameterTypes := LambdaTypes()
    parameterTypes.Add(BuiltInTypes.Int)
    parameterTypes.Add(BuiltInTypes.String)
    signature := LambdaSignature(parameterTypes, BuiltInTypes.Bool)
    parameters := LambdaParams()
    LambdaParam(parameters, "first", 3, 6)
    LambdaParam(parameters, "second", 3, 13)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), signature, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Bool)

    assert LambdaTranscript(steps) == "2 3 4 3 4 1 6"
    assert steps[1].Name == "first"
    assert steps[1].CarriedType == "int"
    assert steps[3].Name == "second"
    assert steps[3].CarriedType == "string"
    assert harness.Errors.Count == 0
}

// THE REFLECTED-DELEGATE DOOR IS NOT PINNABLE FROM THIS HARNESS, AND THE LIMIT IS RECORDED RATHER
// THAN PAPERED OVER. `AnalyzerAssignabilityFacts.IsDelegateType` answers FALSE whenever its
// well-known-type facts are absent, and they are absent in any harness without a
// `MetadataLoadContext` — so a reflected `Func<int, string>` names NO signature HERE while naming one
// in production. What that means is pinned instead: the door DECLINES, and declining is the same
// answer as "not a delegate at all". The production path is covered end to end by the fixtures, where
// `let add: Func<int, int> = x => x + 1` is silent and an `on` handler is inferred from the event's
// own delegate type.
test "a reflected type whose delegate-ness cannot be established names no signature" {
    harness := LambdaHarnessOf()
    delegateType: TypeInfo = new ReflectionTypeInfo(typeof(Func<int, string>))
    parameters := LambdaParams()
    LambdaParam(parameters, "value", 3, 6)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), delegateType, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.String)

    assert LambdaTranscript(steps) == "2 3 4 1 6"
    assert steps[1].CarriedType == "unknown"
    assert steps[3].ExpectedType == "<null>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.CannotInferType
}

test "a type that is neither a function nor a delegate names no signature at all" {
    harness := LambdaHarnessOf()
    parameters := LambdaParams()
    LambdaParam(parameters, "value", 3, 6)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), BuiltInTypes.Int, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert steps[1].CarriedType == "unknown"
    // NO expected type, which is NOT `unknown`: the analyzer's target-typed door leaves the ambient
    // slot alone when none is provided, and clearing it would change what the body resolves to.
    assert steps[3].ExpectedType == "<null>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.CannotInferType
}

test "no expected type at all is the same door as a type that names no signature" {
    harness := LambdaHarnessOf()
    parameters := LambdaParams()
    LambdaParam(parameters, "value", 3, 6)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), null, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert steps[1].CarriedType == "unknown"
    assert harness.Errors.Count == 1
}

// ── the uninferable-parameter report ──────────────────────────────────────────

test "a lambda whose delegate type nothing names is told ONCE however many parameters it has" {
    harness := LambdaHarnessOf()
    parameters := LambdaParams()
    LambdaParam(parameters, "first", 3, 6)
    LambdaParam(parameters, "second", 3, 13)
    LambdaParam(parameters, "third", 3, 21)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), null, true, false)

    LambdaRun(harness, state, BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "I can't figure out the type of lambda parameter 'first' — nothing here names the lambda's delegate type"
}

test "the inference report is suppressed entirely on an error-recovery path" {
    harness := LambdaHarnessOf()
    parameters := LambdaParams()
    LambdaParam(parameters, "first", 3, 6)
    LambdaParam(parameters, "second", 3, 13)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), null, false, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert harness.Errors.Count == 0
    assert LambdaTranscript(steps) == "2 3 4 3 4 1 6"
}

test "a parameter WITH an inference source is silent even when a later one has none" {
    harness := LambdaHarnessOf()
    parameterTypes := LambdaTypes()
    parameterTypes.Add(BuiltInTypes.Int)
    signature := LambdaSignature(parameterTypes, BuiltInTypes.Int)
    parameters := LambdaParams()
    LambdaParam(parameters, "covered", 3, 6)
    LambdaParam(parameters, "uncovered", 3, 15)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), signature, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert steps[1].CarriedType == "int"
    assert steps[3].CarriedType == "unknown"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "I can't figure out the type of lambda parameter 'uncovered' — nothing here names the lambda's delegate type"
}

// ── `var` is the parser's placeholder, not a type ─────────────────────────────

test "a parameter annotated `var` is UNTYPED and takes the signature's type" {
    harness := LambdaHarnessOf()
    parameterTypes := LambdaTypes()
    parameterTypes.Add(BuiltInTypes.String)
    signature := LambdaSignature(parameterTypes, BuiltInTypes.Int)
    parameters := LambdaParams()
    LambdaParam(parameters, "value", 3, 6)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), signature, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert steps[1].CarriedType == "string"
}

test "a parameter that names a REAL type wins over the signature's" {
    harness := LambdaHarnessOf()
    parameterTypes := LambdaTypes()
    parameterTypes.Add(BuiltInTypes.String)
    signature := LambdaSignature(parameterTypes, BuiltInTypes.Int)
    parameters := LambdaParams()
    LambdaTypedParam(parameters, "value", "int", 3, 6)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), signature, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert steps[1].CarriedType == "int"
    assert harness.Errors.Count == 0
}

test "an explicitly typed parameter needs no inference source and reports nothing" {
    harness := LambdaHarnessOf()
    parameters := LambdaParams()
    LambdaTypedParam(parameters, "value", "int", 3, 6)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), null, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert steps[1].CarriedType == "int"
    assert harness.Errors.Count == 0
}

// ── the parameter's position ──────────────────────────────────────────────────

test "a parameter with its own position is declared there and one without falls back to the lambda's" {
    harness := LambdaHarnessOf()
    parameterTypes := LambdaTypes()
    parameterTypes.Add(BuiltInTypes.Int)
    parameterTypes.Add(BuiltInTypes.Int)
    signature := LambdaSignature(parameterTypes, BuiltInTypes.Int)
    parameters := LambdaParams()
    LambdaParam(parameters, "positioned", 9, 21)
    LambdaParam(parameters, "unpositioned", 0, 0)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), signature, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert steps[1].Line == 9
    assert steps[1].Column == 21
    assert steps[3].Line == 3
    assert steps[3].Column == 5
}

// ── the scope ─────────────────────────────────────────────────────────────────

test "the scope opens at the LAMBDA's position, holds the parameters, and closes again" {
    harness := LambdaHarnessOf()
    parameterTypes := LambdaTypes()
    parameterTypes.Add(BuiltInTypes.Int)
    signature := LambdaSignature(parameterTypes, BuiltInTypes.Int)
    parameters := LambdaParams()
    LambdaParam(parameters, "value", 3, 6)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), signature, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert steps[0].Kind == 2
    assert steps[0].Line == 3
    assert steps[0].Column == 5
    // The scope is open for the declare, the record and the body, and closed on the way out.
    assert steps[0].Depth == 1
    assert steps[1].Depth == 2
    assert steps[4].Depth == 2
    assert harness.Scopes.Count == 1
}

// ── the body shapes ───────────────────────────────────────────────────────────

test "an expression body is walked under the signature's return type and ITS answer is the result" {
    harness := LambdaHarnessOf()
    signature := LambdaSignature(LambdaTypes(), BuiltInTypes.String)
    state := harness.Owner.BeginLambda(LambdaExpr(LambdaParams(), LambdaBody()), signature, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Bool)

    assert LambdaTranscript(steps) == "2 1 6"
    assert steps[1].ExpectedType == "string"
    assert LambdaTypeText(state.Result.ReturnType) == "bool"
}

test "an expression body whose analysis answers nothing falls back to unknown" {
    harness := LambdaHarnessOf()
    signature := LambdaSignature(LambdaTypes(), BuiltInTypes.String)
    state := harness.Owner.BeginLambda(LambdaExpr(LambdaParams(), LambdaBody()), signature, true, false)

    LambdaRun(harness, state, null)

    assert LambdaTypeText(state.Result.ReturnType) == "unknown"
}

test "a BLOCK body's return type is the signature's whatever the block does" {
    harness := LambdaHarnessOf()
    signature := LambdaSignature(LambdaTypes(), BuiltInTypes.String)
    state := harness.Owner.BeginLambda(LambdaBlock(LambdaParams(), LambdaEmptyBlock()), signature, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Bool)

    assert LambdaTranscript(steps) == "2 5 6"
    // The nested-body boundary the driver brackets is entered with the SAME type the lambda answers.
    assert steps[1].CarriedType == "string"
    assert LambdaTypeText(state.Result.ReturnType) == "string"
}

test "a block body with no signature enters the boundary with unknown and answers unknown" {
    harness := LambdaHarnessOf()
    state := harness.Owner.BeginLambda(LambdaBlock(LambdaParams(), LambdaEmptyBlock()), null, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Bool)

    assert steps[1].CarriedType == "unknown"
    assert LambdaTypeText(state.Result.ReturnType) == "unknown"
}

test "a lambda with NEITHER body still opens and closes its scope and answers unknown" {
    harness := LambdaHarnessOf()
    parameterTypes := LambdaTypes()
    parameterTypes.Add(BuiltInTypes.Int)
    signature := LambdaSignature(parameterTypes, BuiltInTypes.String)
    parameters := LambdaParams()
    LambdaParam(parameters, "value", 3, 6)
    state := harness.Owner.BeginLambda(new LambdaExpression(parameters, null, null, 3, 5), signature, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Bool)

    assert LambdaTranscript(steps) == "2 3 4 6"
    assert LambdaTypeText(state.Result.ReturnType) == "unknown"
    assert state.Result.ParameterTypes.Count == 1
}

// ── the resulting signature ───────────────────────────────────────────────────

test "the lambda's own type is its parameter types in order and its body's return type" {
    harness := LambdaHarnessOf()
    parameterTypes := LambdaTypes()
    parameterTypes.Add(BuiltInTypes.Int)
    parameterTypes.Add(BuiltInTypes.String)
    signature := LambdaSignature(parameterTypes, BuiltInTypes.Bool)
    parameters := LambdaParams()
    LambdaParam(parameters, "first", 3, 6)
    LambdaParam(parameters, "second", 3, 13)
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaBody()), signature, true, false)

    LambdaRun(harness, state, BuiltInTypes.Bool)

    assert state.Result.ParameterTypes.Count == 2
    assert LambdaTypeText(state.Result.ParameterTypes[0]) == "int"
    assert LambdaTypeText(state.Result.ParameterTypes[1]) == "string"
    assert LambdaTypeText(state.Result.ReturnType) == "bool"
}

// ── the expression-tree validator, which the walk now calls directly ──────────

test "a BLOCK lambda in an expression-tree position is told BEFORE its body is walked" {
    harness := LambdaHarnessOf()
    state := harness.Owner.BeginLambda(LambdaBlock(LambdaParams(), LambdaEmptyBlock()), null, true, true)

    steps := LambdaRun(harness, state, BuiltInTypes.Bool)

    // The relay steps are GONE — the walk calls the validator itself — so the shape report is
    // measured where it lands: BEFORE the body step, which is what "told before its body is
    // walked" means. The step's own recorded error count is the proof of the order.
    assert LambdaTranscript(steps) == "2 5 6"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Expression-tree lambdas must use an expression body; block bodies are not supported"
    assert steps[1].Kind == 5
    assert steps[1].ErrorsBefore == 1
}

test "an EXPRESSION body in an expression-tree position is checked AFTER it is walked" {
    harness := LambdaHarnessOf()
    // A bare identifier that is not one of the lambda's parameters is the smallest body the
    // validator refuses, so this pins that the validator RAN and that it ran after the body step.
    state := harness.Owner.BeginLambda(LambdaExpr(LambdaParams(), LambdaCapturedIdentifier()), null, true, true)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert LambdaTranscript(steps) == "2 1 6"
    assert steps[1].Kind == 1
    assert steps[1].ErrorsBefore == 0
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Expression-tree lambda body contains unsupported captured or static identifier 'captured'"
}

test "an admissible expression body in an expression-tree position is silent" {
    harness := LambdaHarnessOf()
    state := harness.Owner.BeginLambda(LambdaExpr(LambdaParams(), LambdaBody()), null, true, true)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert LambdaTranscript(steps) == "2 1 6"
    assert harness.Errors.Count == 0
}

test "neither expression-tree report fires when nothing named a tree target" {
    harness := LambdaHarnessOf()
    // The SAME body the tree-targeted contract above refuses. Nothing names a tree, so nothing is
    // said: the transcript alone cannot tell the two apart, and the diagnostic can.
    state := harness.Owner.BeginLambda(LambdaExpr(LambdaParams(), LambdaCapturedIdentifier()), null, true, false)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    assert LambdaTranscript(steps) == "2 1 6"
    assert harness.Errors.Count == 0
}

test "the unsupported-expression report is SILENCED by anything the body walk itself reported" {
    harness := LambdaHarnessOf()
    parameters := LambdaParams()
    LambdaParam(parameters, "value", 3, 6)
    // Nothing names a signature, so the parameter is uninferable and the walk reports before the
    // body is even asked for — which is exactly the count the tree report measures against.
    state := harness.Owner.BeginLambda(LambdaExpr(parameters, LambdaCapturedIdentifier()), null, true, true)

    steps := LambdaRun(harness, state, BuiltInTypes.Int)

    // The report happened BEFORE the mark was taken, so it does NOT silence the tree report, and
    // the refusable body is refused: TWO diagnostics, not one.
    assert LambdaTranscript(steps) == "2 3 4 1 6"
    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "Expression-tree lambda body contains unsupported captured or static identifier 'captured'"
}

test "a report made DURING the body walk silences the unsupported-expression report" {
    harness := LambdaHarnessOf()
    state := harness.Owner.BeginLambda(LambdaExpr(LambdaParams(), LambdaCapturedIdentifier()), null, true, true)

    // The body walk itself complains, which is what the mark is taken to detect.
    steps := LambdaRunReportingBody(harness, state, BuiltInTypes.Int)

    assert LambdaTranscript(steps) == "2 1 6"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "the body walk complained"
}

// ── `on` ──────────────────────────────────────────────────────────────────────

class OnStep {
    Kind: int
    ExpectedType: string
    ReportInferenceFailure: bool

    constructor(kind: int, expectedType: string, reportInferenceFailure: bool) {
        Kind = kind
        ExpectedType = expectedType
        ReportInferenceFailure = reportInferenceFailure
    }
}

func OnTargetExpression(): Expression {
    return new IdentifierExpression("widget", 4, 8)
}

func OnHandler(): LambdaExpression {
    parameters := LambdaParams()
    LambdaParam(parameters, "sender", 4, 20)
    LambdaParam(parameters, "args", 4, 28)
    return LambdaBlock(parameters, LambdaEmptyBlock())
}

func OnExpr(): OnSubscriptionExpression {
    return new OnSubscriptionExpression(OnTargetExpression(), OnHandler(), 4, 5)
}

// A stand-in for the runtime `NSharpEventSubscription`, which this project cannot name because it
// does not reference the runtime — which is exactly why the walk takes the root as an argument. What
// the contracts pin is that the answer is a reflection type over WHATEVER root was handed in.
func OnRoot(): Type {
    return typeof(Type)
}

// A stand-in accessor pair. What the walk reads from them is only whether the ADD is static, so any
// real `MethodInfo` pair with the right staticness is the shape under test.
func OnStaticAccessor(): MethodInfo {
    return typeof(string).GetMethod("IsNullOrEmpty")
}

func OnInstanceAccessor(): MethodInfo {
    return typeof(string).GetMethod("ToUpperInvariant", new Type[](0))
}

func OnHandlerDelegate(): Type {
    return typeof(Action<int, int>)
}

func OnRun(harness: LambdaHarness, state: OnSubscriptionState, targetType: TypeInfo?): List<OnStep> {
    steps := new List<OnStep>()
    step := harness.Owner.NextOnStep(state)
    while step != null {
        steps.Add(new OnStep(step.Kind, LambdaTypeText(step.ExpectedType), step.ReportInferenceFailure))
        answer: TypeInfo? = null
        if step.Kind == 1 {
            answer = targetType
        }

        harness.Owner.SupplyOnStep(state, answer)
        step = harness.Owner.NextOnStep(state)
    }

    return steps
}

// The subscription root is HANDED IN, because this project does not reference the runtime. Every
// contract below uses one stand-in root, and what is pinned is that the answer is a reflection type
// over whatever root was handed in — which is the same agreement `off` relies on.
test "an `on` expression answers the subscription root it was handed, on every path" {
    harness := LambdaHarnessOf()
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    OnRun(harness, state, BuiltInTypes.Int)

    // A reflection type renders as the CLR type's own `Name`, so this IS the root that was handed in.
    assert LambdaTypeText(state.Result) == "Type"
}

test "a target that is not an event at all is told so, and the handler is analysed with NO expected type" {
    harness := LambdaHarnessOf()
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    steps := OnRun(harness, state, BuiltInTypes.Int)

    assert steps.Count == 2
    assert steps[0].Kind == 1
    assert steps[1].Kind == 2
    assert steps[1].ExpectedType == "<null>"
    assert !steps[1].ReportInferenceFailure
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidEventSubscription
    assert harness.Errors[0].Message == "`on` can only subscribe to a .NET event"
}

test "a target that did not resolve is NOT told a second time, and the handler is still analysed" {
    harness := LambdaHarnessOf()
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    steps := OnRun(harness, state, BuiltInTypes.Unknown)

    assert harness.Errors.Count == 0
    assert steps.Count == 2
    assert steps[1].Kind == 2
    assert !steps[1].ReportInferenceFailure
}

test "an event with no accessible accessors cannot be subscribed to" {
    harness := LambdaHarnessOf()
    eventInfo: TypeInfo = new ReflectionEventInfo("Clicked")
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    steps := OnRun(harness, state, eventInfo)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'Clicked' can't be subscribed to — it has no accessible add/remove accessors"
    assert steps[1].ExpectedType == "<null>"
    assert !steps[1].ReportInferenceFailure
}

test "an event missing only its REMOVE accessor cannot be subscribed to either" {
    harness := LambdaHarnessOf()
    eventInfo: TypeInfo = new ReflectionEventInfo("Clicked", OnStaticAccessor(), null, OnHandlerDelegate(), typeof(object), "event Clicked")
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    OnRun(harness, state, eventInfo)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'Clicked' can't be subscribed to — it has no accessible add/remove accessors"
}

test "an event with accessors but NO delegate type cannot be subscribed to either" {
    harness := LambdaHarnessOf()
    eventInfo: TypeInfo = new ReflectionEventInfo("Clicked", OnStaticAccessor(), OnStaticAccessor(), null, typeof(object), "event Clicked")
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    OnRun(harness, state, eventInfo)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'Clicked' can't be subscribed to — it has no accessible add/remove accessors"
}

test "a real event hands its delegate type to the handler and switches the inference report ON" {
    harness := LambdaHarnessOf()
    eventInfo: TypeInfo = new ReflectionEventInfo("Clicked", OnStaticAccessor(), OnStaticAccessor(), OnHandlerDelegate(), typeof(object), "event Clicked")
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    steps := OnRun(harness, state, eventInfo)

    assert harness.Errors.Count == 0
    assert steps.Count == 2
    assert steps[1].Kind == 2
    // `Action`2` is the CLR `Name` of the constructed delegate, which is how a reflection type renders.
    assert steps[1].ExpectedType == "Action`2"
    assert steps[1].ReportInferenceFailure
}

test "a STATIC event on a value type is fine — the rule is about instance receivers" {
    harness := LambdaHarnessOf()
    eventInfo: TypeInfo = new ReflectionEventInfo("Ticked", OnStaticAccessor(), OnStaticAccessor(), OnHandlerDelegate(), typeof(int), "event Ticked")
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    OnRun(harness, state, eventInfo)

    assert harness.Errors.Count == 0
}

test "an INSTANCE event on a value type is refused, and the handler still gets the delegate type" {
    harness := LambdaHarnessOf()
    eventInfo: TypeInfo = new ReflectionEventInfo("Ticked", OnInstanceAccessor(), OnInstanceAccessor(), OnHandlerDelegate(), typeof(int), "event Ticked")
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    steps := OnRun(harness, state, eventInfo)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "subscribing to 'Ticked' isn't supported — it's an instance event on a value type (struct)"
    assert steps[1].ExpectedType == "Action`2"
    assert steps[1].ReportInferenceFailure
}

test "an INSTANCE event on a REFERENCE type is fine" {
    harness := LambdaHarnessOf()
    eventInfo: TypeInfo = new ReflectionEventInfo("Ticked", OnInstanceAccessor(), OnInstanceAccessor(), OnHandlerDelegate(), typeof(object), "event Ticked")
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    OnRun(harness, state, eventInfo)

    assert harness.Errors.Count == 0
}

test "an event whose declaring type is unknown is not measured for value-type-ness at all" {
    harness := LambdaHarnessOf()
    eventInfo: TypeInfo = new ReflectionEventInfo("Ticked", OnInstanceAccessor(), OnInstanceAccessor(), OnHandlerDelegate(), null, "event Ticked")
    state := harness.Owner.BeginOnSubscription(OnExpr(), OnRoot())

    OnRun(harness, state, eventInfo)

    assert harness.Errors.Count == 0
}

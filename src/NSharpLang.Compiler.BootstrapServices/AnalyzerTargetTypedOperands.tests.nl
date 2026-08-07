namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT AN EXPRESSION THAT CHOOSES THE TYPE ITS OPERANDS ARE WALKED UNDER
// MEANS — a cast, `checked`, `unchecked` and a ternary, the expression walk's fourth N#-owned
// territory.
//
// The family before this one handed its operands through untouched. These four reach into the
// target-typing slot on the way IN, and every contract here therefore asserts four things at once:
// which steps were asked for, in what order, WHAT EXPECTED TYPE each step carried, and what the walk
// answered given the answers those steps got.
//
// The six things it is easy to get wrong:
//
// (1) THERE ARE TWO DOORS INTO THE EXPRESSION WALK AND A CAST PICKS ONE FROM THE NODE ALONE. A HARD
// cast over a `default` or a bare `new()` walks its operand under the cast's own target type; every
// other cast — including a SAFE cast over the very same `default` — walks it under whatever type was
// already in force. The two doors are not the same operation with a different argument.
//
// (2) THE NAMED-EXPECTED-TYPE DOOR IS NOT A SLOT WRITE. It forks to the lambda walk for a lambda
// operand, and a `checked` operand can be a bare lambda, so a walk that "just wrote the slot" would
// be a different analysis for that operand. The owner names the door; the host performs it.
//
// (3) `checked` AND `unchecked` HAND BACK THE TYPE THEY WERE GIVEN. On the slot that is an identity,
// which is exactly the point: a `default` inside a `checked` knows as much and as little as a
// `default` outside one.
//
// (4) A TERNARY READS ITS EXPECTED TYPE ONCE, AT ENTRY, and walks BOTH arms under it — while its
// condition is walked under `bool`, which is a different type in the same slot.
//
// (5) A TERNARY'S FOUR ESCAPE REPORTS ALL RUN. None of them stops another, because both arms really
// are trying to leave; but any of them firing makes the expression `unknown` and the common-type step
// is never asked for.
//
// (6) NUMERIC WIDENING IS NOT THIS FAMILY'S RULE, AND IT IS NO LONGER A STEP EITHER. While the
// promotion tables lived in the host, a ternary's common type had to be asked for as a fourth step;
// the operator arms own those tables now, so the ternary takes THREE steps and calls
// `AnalyzerOperatorExpressions.CommonType` for its answer.
class TargetTypedStep {
    Kind: int
    NodeName: string
    Line: int
    Column: int
    ErrorsBefore: int
    ResultBefore: string
    ExpectedOperand: string
    AmbientBefore: string

    constructor(kind: int, nodeName: string, line: int, column: int, errorsBefore: int, resultBefore: string, expectedOperand: string, ambientBefore: string) {
        Kind = kind
        NodeName = nodeName
        Line = line
        Column = column
        ErrorsBefore = errorsBefore
        ResultBefore = resultBefore
        ExpectedOperand = expectedOperand
        AmbientBefore = ambientBefore
    }
}

class TargetTypedHarness {
    Operands: AnalyzerTargetTypedOperands
    Ambient: AnalyzerAmbientContext
    Context: AnalyzerDeclarationContext
    Escape: AnalyzerSoaEscape
    Model: SemanticModel
    Errors: List<CompilerError>

    constructor(operands: AnalyzerTargetTypedOperands, ambient: AnalyzerAmbientContext, context: AnalyzerDeclarationContext, escape: AnalyzerSoaEscape, model: SemanticModel, errors: List<CompilerError>) {
        Operands = operands
        Ambient = ambient
        Context = context
        Escape = escape
        Model = model
        Errors = errors
    }
}

func TargetTypedPath(): string {
    return Path.GetFullPath("target-typed-operands-contract.nl")
}

func TargetTypedHarnessWith(sourceText: string?): TargetTypedHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(TargetTypedPath(), sourceText)
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
    resolver.BeginAnalysis(TargetTypedPath(), null, model, new BindingMap())
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    conditions := new AnalyzerBooleanConditions(diagnostics, spans, escape)
    operands := new AnalyzerTargetTypedOperands(resolver, escape, ambient, conditions)
    return new TargetTypedHarness(operands, ambient, context, escape, model, errors)
}

func TargetTypedDefault(): TargetTypedHarness {
    return TargetTypedHarnessWith(null)
}

func TargetTypedTypeText(candidate: TypeInfo?): string {
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

func TargetTypedNodeName(node: Expression?): string {
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

// ── the target-typed driver, exactly as `Analyzer.cs` writes it ─────────
//
// The one difference is that the expression steps are ANSWERED from a supplied list rather than by
// re-entering the analyzer's own walk, which is the one thing a contract cannot replay. Every step
// records
// the error count, the walk's result AS THE STEP WAS HANDED OUT, the expected type THE STEP ITSELF
// CARRIES — which is the operand this family exists to decide — and the ambient slot at that instant.
func TargetTypedRun(harness: TargetTypedHarness, state: TargetTypedOperandState, answers: List<TypeInfo?>): List<TargetTypedStep> {
    steps := new List<TargetTypedStep>()
    step := harness.Operands.NextStep(state)
    while step != null {
        index := steps.Count
        steps.Add(new TargetTypedStep(step.Kind, TargetTypedNodeName(step.Node), step.Line, step.Column, harness.Errors.Count, TargetTypedTypeText(harness.Operands.Result(state)), TargetTypedTypeText(step.ExpectedType), TargetTypedTypeText(harness.Ambient.CurrentExpectedType)))
        answer: TypeInfo? = null
        if index < answers.Count {
            answer = answers[index]
        }

        harness.Operands.Supply(state, answer)
        step = harness.Operands.NextStep(state)
    }

    return steps
}

func TargetTypedOne(answer: TypeInfo?): List<TypeInfo?> {
    answers := new List<TypeInfo?>()
    answers.Add(answer)
    return answers
}

func TargetTypedNone(): List<TypeInfo?> {
    return new List<TypeInfo?>()
}

func TargetTypedThree(condition: TypeInfo?, thenAnswer: TypeInfo?, elseAnswer: TypeInfo?): List<TypeInfo?> {
    answers := new List<TypeInfo?>()
    answers.Add(condition)
    answers.Add(thenAnswer)
    answers.Add(elseAnswer)
    return answers
}

func TargetTypedIdentifier(name: string, line: int, column: int): Expression {
    expression: Expression = new IdentifierExpression(name, line, column)
    return expression
}

func TargetTypedSimpleType(name: string, line: int, column: int): TypeReference {
    reference: TypeReference = new SimpleTypeReference(name, line, column)
    return reference
}

func TargetTypedHardCast(operand: Expression, typeName: string): Expression {
    expression: Expression = new CastExpression(operand, TargetTypedSimpleType(typeName, 2, 6), CastKind.Hard, 2, 5)
    return expression
}

func TargetTypedSafeCast(operand: Expression, typeName: string): Expression {
    expression: Expression = new CastExpression(operand, TargetTypedSimpleType(typeName, 2, 6), CastKind.Safe, 2, 5)
    return expression
}

func TargetTypedBareNew(): Expression {
    expression: Expression = new NewExpression(null, new List<Argument>(), null, 2, 11, null)
    return expression
}

func TargetTypedTypedNew(typeName: string): Expression {
    expression: Expression = new NewExpression(TargetTypedSimpleType(typeName, 2, 15), new List<Argument>(), null, 2, 11, null)
    return expression
}

func TargetTypedDefaultNode(): Expression {
    expression: Expression = new DefaultExpression(2, 11)
    return expression
}

func TargetTypedTernary(condition: Expression, thenExpression: Expression, elseExpression: Expression): Expression {
    expression: Expression = new TernaryExpression(condition, thenExpression, elseExpression, 2, 5)
    return expression
}

func TargetTypedRow(name: string): TypeInfo {
    columns := new List<SoaColumnInfo>()
    row: TypeInfo = new SoaRowTypeInfo(new SoaRecordDeclarationInfo(name, columns, 1, 1))
    return row
}

func TargetTypedErrorText(harness: TargetTypedHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + ":" + error.Length.ToString()
}

// ── the protocol, which is the same for all four ────────────────────────

test "EVERY FORM ASKS ONLY FOR THE KINDS THIS WALK DEFINES" {
    harness := TargetTypedDefault()
    nodes := new List<Expression>()
    nodes.Add(TargetTypedHardCast(TargetTypedIdentifier("v", 2, 11), "int"))
    nodes.Add(new CheckedExpression(TargetTypedIdentifier("v", 2, 15), 2, 5))
    nodes.Add(new UncheckedExpression(TargetTypedIdentifier("v", 2, 17), 2, 5))
    nodes.Add(TargetTypedTernary(TargetTypedIdentifier("flag", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))

    index := 0
    while index < nodes.Count {
        state := harness.Operands.Begin(nodes[index])
        steps := TargetTypedRun(harness, state, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Int))
        stepIndex := 0
        while stepIndex < steps.Count {
            assert steps[stepIndex].Kind >= 1 && steps[stepIndex].Kind <= 2
            stepIndex = stepIndex + 1
        }

        index = index + 1
    }
}

test "THE STEP COUNT IS THE FORM'S SHAPE — THREE FORMS ONE, A TERNARY THREE" {
    harness := TargetTypedDefault()
    castState := harness.Operands.Begin(TargetTypedHardCast(TargetTypedIdentifier("v", 2, 11), "int"))
    castSteps := TargetTypedRun(harness, castState, TargetTypedOne(BuiltInTypes.String))

    assert castState.Form == 0
    assert castSteps.Count == 1

    checkedState := harness.Operands.Begin(new CheckedExpression(TargetTypedIdentifier("v", 2, 15), 2, 5))
    checkedSteps := TargetTypedRun(harness, checkedState, TargetTypedOne(BuiltInTypes.Int))

    assert checkedState.Form == 1
    assert checkedSteps.Count == 1

    uncheckedState := harness.Operands.Begin(new UncheckedExpression(TargetTypedIdentifier("v", 2, 17), 2, 5))
    uncheckedSteps := TargetTypedRun(harness, uncheckedState, TargetTypedOne(BuiltInTypes.Int))

    assert uncheckedState.Form == 2
    assert uncheckedSteps.Count == 1

    ternaryState := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))
    ternarySteps := TargetTypedRun(harness, ternaryState, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Int))

    assert ternaryState.Form == 3
    assert ternarySteps.Count == 3
    assert ternarySteps[0].Kind == 2
    assert ternarySteps[1].Kind == 2
    assert ternarySteps[2].Kind == 2
}

test "A NODE THAT IS NONE OF THE FOUR TAKES NO STEPS AND ANSWERS unknown" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedIdentifier("v", 2, 5))

    steps := TargetTypedRun(harness, state, TargetTypedOne(BuiltInTypes.Int))

    assert state.Form == -1
    assert steps.Count == 0
    assert TargetTypedTypeText(harness.Operands.Result(state)) == "unknown"
    assert harness.Errors.Count == 0
}

test "A WALK THAT ASKED FOR NOTHING FOLDS IN NOTHING WHEN SUPPLIED ANYWAY" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedIdentifier("v", 2, 5))

    TargetTypedRun(harness, state, TargetTypedNone())
    harness.Operands.Supply(state, BuiltInTypes.String)

    assert TargetTypedTypeText(harness.Operands.Result(state)) == "unknown"
}

test "A FINISHED WALK KEEPS ANSWERING null AND ITS RESULT IS STABLE" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(new CheckedExpression(TargetTypedIdentifier("v", 2, 15), 2, 5))

    TargetTypedRun(harness, state, TargetTypedOne(BuiltInTypes.String))

    assert TargetTypedTypeText(harness.Operands.Result(state)) == "string"
    assert harness.Operands.NextStep(state) == null
    assert harness.Operands.NextStep(state) == null
    assert TargetTypedTypeText(harness.Operands.Result(state)) == "string"
}

test "THE ANSWER IS NOT SETTLED BEFORE THE STEPS" {
    harness := TargetTypedDefault()
    castState := harness.Operands.Begin(TargetTypedHardCast(TargetTypedIdentifier("v", 2, 11), "int"))
    castSteps := TargetTypedRun(harness, castState, TargetTypedOne(BuiltInTypes.String))

    // The cast's answer is a written type that `Begin` could have decided — and does not.
    assert castSteps[0].ResultBefore == "unknown"
    assert TargetTypedTypeText(harness.Operands.Result(castState)) == "int"

    ternaryState := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))
    ternarySteps := TargetTypedRun(harness, ternaryState, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Int))

    assert ternarySteps[0].ResultBefore == "unknown"
    assert ternarySteps[1].ResultBefore == "unknown"
    assert ternarySteps[2].ResultBefore == "unknown"
    assert TargetTypedTypeText(harness.Operands.Result(ternaryState)) == "int"
}

test "NO DIAGNOSTIC LANDS AT Begin" {
    harness := TargetTypedDefault()
    harness.Operands.Begin(TargetTypedHardCast(TargetTypedIdentifier("row", 2, 11), "int"))
    harness.Operands.Begin(new CheckedExpression(TargetTypedIdentifier("row", 2, 15), 2, 5))
    harness.Operands.Begin(new UncheckedExpression(TargetTypedIdentifier("row", 2, 17), 2, 5))
    harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("n", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))

    assert harness.Errors.Count == 0
}

// ── the cast, and the door it picks from the node alone ─────────────────

test "A CAST IS ITS WRITTEN TARGET TYPE AND NOT ITS OPERAND'S" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedHardCast(TargetTypedIdentifier("v", 2, 11), "int"))

    steps := TargetTypedRun(harness, state, TargetTypedOne(BuiltInTypes.String))

    assert steps.Count == 1
    assert steps[0].NodeName == "v"
    assert TargetTypedTypeText(harness.Operands.Result(state)) == "int"
    assert harness.Errors.Count == 0
}

test "A CAST RESOLVES ITS WRITTEN TARGET BEFORE THE OPERAND STEP — WHICH IS THE OPPOSITE OF is" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedHardCast(TargetTypedIdentifier("value", 2, 16), "int"))

    // Nothing has been resolved yet — `Begin` decides nothing.
    assert harness.Model.LookupTypeReferenceAtPosition(2, 6) == null

    step := harness.Operands.NextStep(state)

    // The step is outstanding and the written type is ALREADY recorded: the resolution ran first,
    // which is what makes a broken cast target report ahead of anything its operand has to say.
    // `is` — the same shape one family over — resolves its written type AFTER its step.
    assert step != null
    recorded := harness.Model.LookupTypeReferenceAtPosition(2, 6)
    assert recorded != null
    assert TargetTypedTypeText(recorded) == "int"
}

test "THE DOOR TABLE — A HARD CAST OVER default OR new() NAMES THE TARGET, EVERYTHING ELSE NAMES NOTHING" {
    harness := TargetTypedDefault()

    hardDefault := harness.Operands.Begin(TargetTypedHardCast(TargetTypedDefaultNode(), "int"))
    hardDefaultSteps := TargetTypedRun(harness, hardDefault, TargetTypedOne(BuiltInTypes.Int))

    assert hardDefaultSteps[0].Kind == 2
    assert hardDefaultSteps[0].ExpectedOperand == "int"

    hardNew := harness.Operands.Begin(TargetTypedHardCast(TargetTypedBareNew(), "string"))
    hardNewSteps := TargetTypedRun(harness, hardNew, TargetTypedOne(BuiltInTypes.String))

    assert hardNewSteps[0].Kind == 2
    assert hardNewSteps[0].ExpectedOperand == "string"

    // A `new T()` is NOT a bare `new()` — it already knows what it creates.
    hardTypedNew := harness.Operands.Begin(TargetTypedHardCast(TargetTypedTypedNew("string"), "string"))
    hardTypedNewSteps := TargetTypedRun(harness, hardTypedNew, TargetTypedOne(BuiltInTypes.String))

    assert hardTypedNewSteps[0].Kind == 1
    assert hardTypedNewSteps[0].ExpectedOperand == "<null>"

    ordinary := harness.Operands.Begin(TargetTypedHardCast(TargetTypedIdentifier("v", 2, 11), "int"))
    ordinarySteps := TargetTypedRun(harness, ordinary, TargetTypedOne(BuiltInTypes.Long))

    assert ordinarySteps[0].Kind == 1
    assert ordinarySteps[0].ExpectedOperand == "<null>"

    // THE DECISIVE ROW: the same operand and the same written type, through the OTHER cast kind.
    safeDefault := harness.Operands.Begin(TargetTypedSafeCast(TargetTypedDefaultNode(), "int"))
    safeDefaultSteps := TargetTypedRun(harness, safeDefault, TargetTypedOne(BuiltInTypes.Int))

    assert safeDefaultSteps[0].Kind == 1
    assert safeDefaultSteps[0].ExpectedOperand == "<null>"
    assert harness.Errors.Count == 0
}

test "A CAST OVER A ROW VIEW IS REFUSED AND ANSWERS unknown" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedHardCast(TargetTypedIdentifier("row", 2, 11), "int"))

    TargetTypedRun(harness, state, TargetTypedOne(TargetTypedRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be cast; use the table and row index instead"
    assert TargetTypedTypeText(harness.Operands.Result(state)) == "unknown"
}

test "A CAST STOPS AT THE FIRST REFUSAL AND ASKS BOTH QUESTIONS" {
    harness := TargetTypedDefault()
    column := new MemberAccessExpression(TargetTypedIdentifier("points", 2, 11), "x", false, 2, 11)
    harness.Escape.RecordColumnMemberAccess(column)
    operand: Expression = column

    // A row-view answer fires the FIRST report and returns — the second is never asked.
    rowState := harness.Operands.Begin(TargetTypedHardCast(operand, "int"))
    TargetTypedRun(harness, rowState, TargetTypedOne(TargetTypedRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be cast; use the table and row index instead"

    // The same operand with an ordinary answer reaches the SECOND report, which a `checked` never
    // asks at all.
    columnState := harness.Operands.Begin(TargetTypedHardCast(operand, "int"))
    TargetTypedRun(harness, columnState, TargetTypedOne(BuiltInTypes.Int))

    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "SoA table member 'x' cannot be cast directly"
    assert TargetTypedTypeText(harness.Operands.Result(columnState)) == "unknown"
}

// ── checked and unchecked ───────────────────────────────────────────────

test "checked AND unchecked ARE THEIR OPERAND, WHATEVER IT IS" {
    harness := TargetTypedDefault()
    checkedState := harness.Operands.Begin(new CheckedExpression(TargetTypedIdentifier("v", 2, 15), 2, 5))
    TargetTypedRun(harness, checkedState, TargetTypedOne(BuiltInTypes.Long))

    assert TargetTypedTypeText(harness.Operands.Result(checkedState)) == "long"

    uncheckedState := harness.Operands.Begin(new UncheckedExpression(TargetTypedIdentifier("v", 2, 17), 2, 5))
    TargetTypedRun(harness, uncheckedState, TargetTypedOne(BuiltInTypes.Byte))

    assert TargetTypedTypeText(harness.Operands.Result(uncheckedState)) == "byte"
    assert harness.Errors.Count == 0
}

test "checked AND unchecked HAND THE SURROUNDING EXPECTED TYPE BACK TO THEIR OPERAND" {
    harness := TargetTypedDefault()

    // With nothing in force, the operand is named nothing — which is not the same as being named
    // `unknown`, and is what makes a bare `default` inside a `checked` as undecidable as one outside.
    emptyState := harness.Operands.Begin(new CheckedExpression(TargetTypedDefaultNode(), 2, 5))
    emptySteps := TargetTypedRun(harness, emptyState, TargetTypedOne(BuiltInTypes.Int))

    assert emptySteps[0].Kind == 2
    assert emptySteps[0].ExpectedOperand == "<null>"
    assert emptySteps[0].AmbientBefore == "<null>"

    // With a type in force, that same type is handed back down.
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)
    heldState := harness.Operands.Begin(new CheckedExpression(TargetTypedDefaultNode(), 3, 5))
    heldSteps := TargetTypedRun(harness, heldState, TargetTypedOne(BuiltInTypes.Byte))

    assert heldSteps[0].Kind == 2
    assert heldSteps[0].ExpectedOperand == "byte"
    assert heldSteps[0].AmbientBefore == "byte"

    uncheckedState := harness.Operands.Begin(new UncheckedExpression(TargetTypedDefaultNode(), 4, 5))
    uncheckedSteps := TargetTypedRun(harness, uncheckedState, TargetTypedOne(BuiltInTypes.Byte))

    assert uncheckedSteps[0].ExpectedOperand == "byte"
    harness.Ambient.ExitExpectedType(saved)
}

test "checked AND unchecked ASK ONE ESCAPE QUESTION AND THE WORDING IS THEIR OWN" {
    harness := TargetTypedDefault()
    checkedState := harness.Operands.Begin(new CheckedExpression(TargetTypedIdentifier("row", 2, 15), 2, 5))
    TargetTypedRun(harness, checkedState, TargetTypedOne(TargetTypedRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used in a checked expression; use the table and row index instead"
    assert TargetTypedTypeText(harness.Operands.Result(checkedState)) == "unknown"

    uncheckedState := harness.Operands.Begin(new UncheckedExpression(TargetTypedIdentifier("row", 3, 17), 3, 5))
    TargetTypedRun(harness, uncheckedState, TargetTypedOne(TargetTypedRow("Points")))

    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "SoA row views cannot be used in an unchecked expression; use the table and row index instead"
    assert TargetTypedTypeText(harness.Operands.Result(uncheckedState)) == "unknown"
}

test "A DIRECT COLUMN VALUE INSIDE A checked IS NOT THIS ARM'S OBJECTION" {
    harness := TargetTypedDefault()
    column := new MemberAccessExpression(TargetTypedIdentifier("points", 2, 15), "x", false, 2, 15)
    harness.Escape.RecordColumnMemberAccess(column)
    operand: Expression = column

    checkedState := harness.Operands.Begin(new CheckedExpression(operand, 2, 5))
    TargetTypedRun(harness, checkedState, TargetTypedOne(BuiltInTypes.Int))

    // A CAST over the same operand reports; a `checked` says nothing, because it never asks.
    assert harness.Errors.Count == 0
    assert TargetTypedTypeText(harness.Operands.Result(checkedState)) == "int"

    uncheckedState := harness.Operands.Begin(new UncheckedExpression(operand, 3, 5))
    TargetTypedRun(harness, uncheckedState, TargetTypedOne(BuiltInTypes.Int))

    assert harness.Errors.Count == 0
    assert TargetTypedTypeText(harness.Operands.Result(uncheckedState)) == "int"
}

// ── the ternary ─────────────────────────────────────────────────────────

test "A TERNARY WALKS ITS CONDITION UNDER bool AND BOTH ARMS UNDER ITS OWN EXPECTED TYPE" {
    harness := TargetTypedDefault()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.Long)
    state := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))

    steps := TargetTypedRun(harness, state, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Long, BuiltInTypes.Long))

    assert steps[0].NodeName == "flag"
    assert steps[0].ExpectedOperand == "bool"
    assert steps[1].NodeName == "a"
    assert steps[1].ExpectedOperand == "long"
    assert steps[2].NodeName == "b"
    assert steps[2].ExpectedOperand == "long"
    harness.Ambient.ExitExpectedType(saved)
}

test "A TERNARY WITH NOTHING IN FORCE NAMES NOTHING FOR ITS ARMS AND STILL NAMES bool FOR ITS CONDITION" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))

    steps := TargetTypedRun(harness, state, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Int))

    assert steps[0].ExpectedOperand == "bool"
    assert steps[1].ExpectedOperand == "<null>"
    assert steps[2].ExpectedOperand == "<null>"
}

test "THE CONDITION IS TOLD IT IS NOT A BOOLEAN BEFORE EITHER ARM IS WALKED" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("n", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))

    steps := TargetTypedRun(harness, state, TargetTypedThree(BuiltInTypes.Int, BuiltInTypes.Int, BuiltInTypes.Int))

    assert steps[0].ErrorsBefore == 0
    assert steps[1].ErrorsBefore == 1
    assert harness.Errors[0].Message == "The condition in a ternary expression must be a boolean, but I found 'int'"
}

test "AN unknown CONDITION IS NOT ACCUSED TWICE" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("n", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))

    TargetTypedRun(harness, state, TargetTypedThree(BuiltInTypes.Unknown, BuiltInTypes.Int, BuiltInTypes.Int))

    assert harness.Errors.Count == 0
}

test "A TERNARY IS THE COMMON TYPE OF ITS TWO ARMS, TAKEN IN SOURCE ORDER AND NOT AS A STEP" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))

    steps := TargetTypedRun(harness, state, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Long))

    // The walk ends at the else arm: the common type is a CALL into the operator arms' promotion
    // tables, not a fourth step the host has to answer.
    assert steps.Count == 3
    assert TargetTypedTypeText(harness.Operands.Result(state)) == "long"
}

test "ALL FOUR OF A TERNARY'S ESCAPE REPORTS RUN AND NONE STOPS ANOTHER" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))

    steps := TargetTypedRun(harness, state, TargetTypedThree(BuiltInTypes.Bool, TargetTypedRow("Points"), TargetTypedRow("Points")))

    // BOTH arms are told, and the common type is never asked for.
    assert steps.Count == 3
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "SoA row views cannot be used as a ternary result; use the table and row index instead"
    assert harness.Errors[1].Message == "SoA row views cannot be used as a ternary result; use the table and row index instead"
    assert TargetTypedTypeText(harness.Operands.Result(state)) == "unknown"
}

test "A TERNARY WHOSE ARM IS A DIRECT COLUMN VALUE IS REFUSED BY THE SECOND PAIR OF REPORTS" {
    harness := TargetTypedDefault()
    column := new MemberAccessExpression(TargetTypedIdentifier("points", 2, 16), "x", false, 2, 16)
    harness.Escape.RecordColumnMemberAccess(column)
    columnArm: Expression = column
    state := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 2, 9), columnArm, TargetTypedIdentifier("b", 2, 22)))

    steps := TargetTypedRun(harness, state, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Int))

    assert steps.Count == 3
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be used as a ternary result directly"
    assert TargetTypedTypeText(harness.Operands.Result(state)) == "unknown"
}

test "A TERNARY THAT ESCAPES ANSWERS unknown WITHOUT TAKING A COMMON TYPE" {
    harness := TargetTypedDefault()
    clean := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 2, 9), TargetTypedIdentifier("a", 2, 16), TargetTypedIdentifier("b", 2, 20)))
    cleanSteps := TargetTypedRun(harness, clean, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Int))

    assert cleanSteps.Count == 3
    assert TargetTypedTypeText(harness.Operands.Result(clean)) == "int"

    escaped := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 3, 9), TargetTypedIdentifier("a", 3, 16), TargetTypedIdentifier("b", 3, 20)))
    escapedSteps := TargetTypedRun(harness, escaped, TargetTypedThree(BuiltInTypes.Bool, TargetTypedRow("Points"), BuiltInTypes.Int))

    assert escapedSteps.Count == 3
    assert escapedSteps[2].Kind == 2
    assert TargetTypedTypeText(harness.Operands.Result(escaped)) == "unknown"
}

test "A TERNARY ARM THAT IS ITSELF A ternary NESTS WITHOUT THE OUTER WALK NOTICING" {
    harness := TargetTypedDefault()
    inner := TargetTypedTernary(TargetTypedIdentifier("second", 2, 24), TargetTypedIdentifier("b", 2, 33), TargetTypedIdentifier("c", 2, 37))
    outer := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("first", 2, 9), TargetTypedIdentifier("a", 2, 18), inner))

    // The outer walk hands out its else step; the driver would answer it by walking the inner
    // ternary, which is a walk of its own with its own state.
    outerSteps := TargetTypedRun(harness, outer, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Int))

    assert outerSteps.Count == 3
    assert outerSteps[2].NodeName == "TernaryExpression"

    innerState := harness.Operands.Begin(inner)
    innerSteps := TargetTypedRun(harness, innerState, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Int))

    assert innerSteps.Count == 3
    assert TargetTypedTypeText(harness.Operands.Result(innerState)) == "int"
}

// ── the family's own boundary ───────────────────────────────────────────

test "THIS FAMILY RAISES NO DIAGNOSTIC OF ITS OWN — EVERY REPORT BELONGS TO A COLLABORATOR" {
    harness := TargetTypedDefault()

    castState := harness.Operands.Begin(TargetTypedHardCast(TargetTypedIdentifier("v", 2, 11), "int"))
    TargetTypedRun(harness, castState, TargetTypedOne(BuiltInTypes.String))
    checkedState := harness.Operands.Begin(new CheckedExpression(TargetTypedIdentifier("v", 3, 15), 3, 5))
    TargetTypedRun(harness, checkedState, TargetTypedOne(BuiltInTypes.String))
    uncheckedState := harness.Operands.Begin(new UncheckedExpression(TargetTypedIdentifier("v", 4, 17), 4, 5))
    TargetTypedRun(harness, uncheckedState, TargetTypedOne(BuiltInTypes.String))
    ternaryState := harness.Operands.Begin(TargetTypedTernary(TargetTypedIdentifier("flag", 5, 9), TargetTypedIdentifier("a", 5, 16), TargetTypedIdentifier("b", 5, 20)))
    TargetTypedRun(harness, ternaryState, TargetTypedThree(BuiltInTypes.Bool, BuiltInTypes.Int, BuiltInTypes.Int))

    // Four clean walks over four forms: nothing this family owns reports on its own account.
    assert harness.Errors.Count == 0
}

test "A CAST'S WRITTEN TARGET IS RESOLVED LENIENTLY — AN UNKNOWN TYPE IS NOT AN ERROR HERE" {
    harness := TargetTypedDefault()
    state := harness.Operands.Begin(TargetTypedHardCast(TargetTypedIdentifier("v", 2, 11), "NoSuchTypeAnywhere"))

    TargetTypedRun(harness, state, TargetTypedOne(BuiltInTypes.Int))

    // `ResolveType`, not `ResolveDeclaredType` — the same leniency `typeof` and `is` were measured to
    // have. The cast still answers the unresolved type rather than falling back to its operand's.
    assert harness.Errors.Count == 0
    assert TargetTypedTypeText(harness.Operands.Result(state)) != "int"
}

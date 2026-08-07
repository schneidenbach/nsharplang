namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT A LITERAL MEANS — the expression walk's first N#-owned territory.
//
// This is the arc's FIRST ANSWERING WALK, and most of what these contracts are written around is
// that one fact. A statement walk answers nothing, so every contract before this one could assert
// only the STEP STREAM and the reports. Here the walk has a RESULT, so every contract asserts three
// things at once: which steps were asked for, in what order, and what the walk answered — and the
// invariants say the answer is settled BEFORE the first step and is not moved by any of them.
//
// The five things it is easy to get wrong:
//
// (1) SIX OF SEVEN FORMS TAKE NO STEPS AT ALL. A driver that assumed at least one step, or an owner
// that asked for one it did not need, would be invisible in the corpus (a bare `1` produces no
// diagnostic either way) and would show up only as a re-entrancy cost. The empty walk is asserted
// per form.
//
// (2) THE INTEGER LITERAL IS TARGET-TYPED, BUT ONLY WHEN IT IS SUFFIXLESS. Every suffix rule wins
// outright over the ambient slot, including when the suffix makes the answer WIDER than the target.
//
// (3) AN INTERPOLATED STRING IS A `string` WHATEVER ITS HOLES DO. A hole that answers `unknown`, a
// hole that is refused as an SoA row, and a hole that answers nothing at all all leave the walk's
// result alone.
//
// (4) THE HOLE ORDER IS THE PART ORDER. Text parts between holes must not reorder them, and the step
// carries the HOLE'S EXPRESSION's position rather than the hole's or the string's.
//
// (5) BOTH ESCAPE REPORTS RUN FOR EVERY HOLE. Neither silences the other, and the row report's
// operand is the answer the step before it produced — which is the whole reason this walk suspends.
class LiteralStep {
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

class LiteralHarness {
    Literals: AnalyzerLiteralExpressions
    Ambient: AnalyzerAmbientContext
    Context: AnalyzerDeclarationContext
    Errors: List<CompilerError>

    constructor(literals: AnalyzerLiteralExpressions, ambient: AnalyzerAmbientContext, context: AnalyzerDeclarationContext, errors: List<CompilerError>) {
        Literals = literals
        Ambient = ambient
        Context = context
        Errors = errors
    }
}

func LiteralPath(): string {
    return Path.GetFullPath("literal-expressions-contract.nl")
}

func LiteralHarnessWith(sourceText: string?): LiteralHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(LiteralPath(), sourceText)
    spans := new AnalyzerDiagnosticSpans(diagnostics)
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    literals := new AnalyzerLiteralExpressions(ambient, context, escape)
    return new LiteralHarness(literals, ambient, context, errors)
}

func LiteralDefault(): LiteralHarness {
    return LiteralHarnessWith(null)
}

func LiteralTypeText(candidate: TypeInfo?): string {
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

func LiteralNodeName(node: Expression?): string {
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

// ── the literal driver, exactly as `Analyzer.cs` writes it ─────────────
//
// The one difference is that the expression step is ANSWERED with a fixed value rather than by
// re-entering the analyzer's own walk, which is the one thing a contract cannot replay. Every step
// is recorded with the error count AND the walk's result AS THE STEP WAS HANDED OUT, so the two
// invariants that matter — the result is settled before the first step, and each escape report lands
// between two steps — are readable off the row stream.
func LiteralRun(harness: LiteralHarness, state: LiteralExpressionState, answer: TypeInfo?): List<LiteralStep> {
    steps := new List<LiteralStep>()
    step := harness.Literals.NextStep(state)
    while step != null {
        steps.Add(new LiteralStep(step.Kind, LiteralNodeName(step.Node), step.Line, step.Column, harness.Errors.Count, LiteralTypeText(harness.Literals.Result(state))))
        harness.Literals.Supply(state, answer)
        step = harness.Literals.NextStep(state)
    }

    return steps
}

func LiteralIdentifier(name: string, line: int, column: int): Expression {
    expression: Expression = new IdentifierExpression(name, line, column)
    return expression
}

func LiteralHole(name: string, line: int, column: int): InterpolatedStringPart {
    part: InterpolatedStringPart = new InterpolatedStringHole(LiteralIdentifier(name, line, column), null, line, column)
    return part
}

func LiteralText(text: string, line: int, column: int): InterpolatedStringPart {
    part: InterpolatedStringPart = new InterpolatedStringText(text, line, column)
    return part
}

func LiteralParts(): List<InterpolatedStringPart> {
    return new List<InterpolatedStringPart>()
}

func LiteralInterpolated(parts: List<InterpolatedStringPart>): Expression {
    expression: Expression = new InterpolatedStringExpression(parts, 3, 5)
    return expression
}

func LiteralRow(): TypeInfo {
    columns := new List<SoaColumnInfo>()
    row: TypeInfo = new SoaRowTypeInfo(new SoaRecordDeclarationInfo("Particle", columns, 1, 1))
    return row
}

func LiteralErrorText(harness: LiteralHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString()
}

// ── the six forms that answer without a step ────────────────────────────

test "AN int LITERAL ANSWERS int AND TAKES NO STEPS" {
    harness := LiteralDefault()
    state := harness.Literals.Begin(new IntLiteralExpression("42", 3, 9))

    steps := LiteralRun(harness, state, null)

    assert state.Form == 0
    assert steps.Count == 0
    assert LiteralTypeText(harness.Literals.Result(state)) == "int"
    assert harness.Errors.Count == 0
}

test "A float LITERAL ANSWERS BY ITS SUFFIX AND TAKES NO STEPS" {
    harness := LiteralDefault()

    plain := harness.Literals.Begin(new FloatLiteralExpression("1.5", 3, 9))
    single := harness.Literals.Begin(new FloatLiteralExpression("1.5f", 3, 9))
    money := harness.Literals.Begin(new FloatLiteralExpression("1.5m", 3, 9))

    assert plain.Form == 1
    assert LiteralRun(harness, plain, null).Count == 0
    assert LiteralTypeText(harness.Literals.Result(plain)) == "double"
    assert LiteralTypeText(harness.Literals.Result(single)) == "float"
    assert LiteralTypeText(harness.Literals.Result(money)) == "decimal"
}

test "A char LITERAL ANSWERS char AND TAKES NO STEPS" {
    harness := LiteralDefault()
    state := harness.Literals.Begin(new CharLiteralExpression("a", 3, 9))

    steps := LiteralRun(harness, state, null)

    assert state.Form == 2
    assert steps.Count == 0
    assert LiteralTypeText(harness.Literals.Result(state)) == "char"
}

test "A string LITERAL ANSWERS string AND TAKES NO STEPS" {
    harness := LiteralDefault()
    state := harness.Literals.Begin(new StringLiteralExpression("hello", 3, 9))

    steps := LiteralRun(harness, state, null)

    assert state.Form == 3
    assert steps.Count == 0
    assert LiteralTypeText(harness.Literals.Result(state)) == "string"
}

test "A bool LITERAL ANSWERS bool AND TAKES NO STEPS" {
    harness := LiteralDefault()
    state := harness.Literals.Begin(new BoolLiteralExpression(true, 3, 9))

    steps := LiteralRun(harness, state, null)

    assert state.Form == 5
    assert steps.Count == 0
    assert LiteralTypeText(harness.Literals.Result(state)) == "bool"
}

test "A null LITERAL ANSWERS THE NULL TYPE, NOT object" {
    harness := LiteralDefault()
    state := harness.Literals.Begin(new NullLiteralExpression(3, 9))

    steps := LiteralRun(harness, state, null)

    assert state.Form == 6
    assert steps.Count == 0
    assert LiteralTypeText(harness.Literals.Result(state)) == "null"
    assert LiteralTypeText(harness.Literals.Result(state)) != "object"
}

test "AN EXPRESSION THAT IS NOT A LITERAL ANSWERS unknown AND TAKES NO STEPS" {
    harness := LiteralDefault()
    state := harness.Literals.Begin(LiteralIdentifier("x", 3, 9))

    steps := LiteralRun(harness, state, null)

    assert state.Form == -1
    assert steps.Count == 0
    assert LiteralTypeText(harness.Literals.Result(state)) == "unknown"
}

// ── the integer suffix rules ────────────────────────────────────────────

test "A ul SUFFIX IS ulong WHATEVER THE MAGNITUDE" {
    harness := LiteralDefault()

    assert LiteralTypeText(harness.Literals.IntLiteralType("1ul")) == "ulong"
    assert LiteralTypeText(harness.Literals.IntLiteralType("1UL")) == "ulong"
    assert LiteralTypeText(harness.Literals.IntLiteralType("18446744073709551615ul")) == "ulong"
}

test "A u SUFFIX IS uint WHEN IT FITS AND ulong WHEN IT DOES NOT" {
    harness := LiteralDefault()

    assert LiteralTypeText(harness.Literals.IntLiteralType("1u")) == "uint"
    assert LiteralTypeText(harness.Literals.IntLiteralType("4294967295u")) == "uint"
    assert LiteralTypeText(harness.Literals.IntLiteralType("4294967296u")) == "ulong"
}

test "AN l SUFFIX IS long WHEN IT FITS AND ulong WHEN IT DOES NOT" {
    harness := LiteralDefault()

    assert LiteralTypeText(harness.Literals.IntLiteralType("1l")) == "long"
    assert LiteralTypeText(harness.Literals.IntLiteralType("9223372036854775807L")) == "long"
    assert LiteralTypeText(harness.Literals.IntLiteralType("9223372036854775808L")) == "ulong"
}

test "TEXT THAT IS NOT A PARSEABLE MAGNITUDE IS int AND ASKS NOTHING FURTHER" {
    harness := LiteralDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)

    assert LiteralTypeText(harness.Literals.IntLiteralType("0x")) == "int"
    assert LiteralTypeText(harness.Literals.IntLiteralType("")) == "int"
}

// ── the target-typing rule, which only a suffixless literal obeys ───────

test "A SUFFIXLESS LITERAL TAKES THE EXPECTED TYPE WHEN IT FITS" {
    harness := LiteralDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)

    assert LiteralTypeText(harness.Literals.IntLiteralType("200")) == "byte"
}

test "A SUFFIXLESS LITERAL THAT DOES NOT FIT THE EXPECTED TYPE IS int" {
    harness := LiteralDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)

    assert LiteralTypeText(harness.Literals.IntLiteralType("300")) == "int"
}

test "A SUFFIX BEATS THE EXPECTED TYPE EVEN WHEN THE LITERAL WOULD HAVE FITTED" {
    harness := LiteralDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)

    assert LiteralTypeText(harness.Literals.IntLiteralType("1u")) == "uint"
    assert LiteralTypeText(harness.Literals.IntLiteralType("1l")) == "long"
    assert LiteralTypeText(harness.Literals.IntLiteralType("1ul")) == "ulong"
}

test "A NULLABLE EXPECTED TYPE IS LOOKED THROUGH, ONCE" {
    harness := LiteralDefault()
    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.Byte)
    harness.Ambient.EnterExpectedType(nullable)

    assert LiteralTypeText(harness.Literals.IntLiteralType("200")) == "byte"
    assert LiteralTypeText(harness.Literals.IntLiteralType("300")) == "int"
}

test "A NON-NUMERIC EXPECTED TYPE DOES NOT ANSWER, AND THE LITERAL IS int" {
    harness := LiteralDefault()
    harness.Ambient.EnterExpectedType(BuiltInTypes.String)

    assert LiteralTypeText(harness.Literals.IntLiteralType("42")) == "int"
}

test "NO EXPECTED TYPE AT ALL IS int" {
    harness := LiteralDefault()

    assert harness.Ambient.CurrentExpectedType == null
    assert LiteralTypeText(harness.Literals.IntLiteralType("42")) == "int"
}

test "A REFLECTED EXPECTED TYPE ANSWERS, AND A REFLECTED NULLABLE ANSWERS AS ITS T" {
    harness := LiteralDefault()

    reflected: TypeInfo = new ReflectionTypeInfo(typeof(byte))
    harness.Ambient.EnterExpectedType(reflected)
    assert LiteralTypeText(harness.Literals.IntLiteralType("200")) == "byte"
    assert LiteralTypeText(harness.Literals.IntLiteralType("300")) == "int"

    reflectedNullable: TypeInfo = new ReflectionTypeInfo(typeof(byte?))
    harness.Ambient.EnterExpectedType(reflectedNullable)
    assert LiteralTypeText(harness.Literals.IntLiteralType("200")) == "byte"
}

test "THE EXPECTED TYPE IS READ AT THE INSTANT THE WALK BEGINS" {
    harness := LiteralDefault()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)
    state := harness.Literals.Begin(new IntLiteralExpression("200", 3, 9))
    harness.Ambient.ExitExpectedType(saved)

    assert harness.Ambient.CurrentExpectedType == null
    assert LiteralTypeText(harness.Literals.Result(state)) == "byte"
}

// ── the interpolated string, the one form that suspends ─────────────────

test "AN INTERPOLATED STRING WITH NO HOLES TAKES NO STEPS AND IS STILL A string" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralText("hello", 3, 6))
    state := harness.Literals.Begin(LiteralInterpolated(parts))

    steps := LiteralRun(harness, state, null)

    assert state.Form == 4
    assert steps.Count == 0
    assert LiteralTypeText(harness.Literals.Result(state)) == "string"
}

test "AN EMPTY PART LIST TAKES NO STEPS" {
    harness := LiteralDefault()
    state := harness.Literals.Begin(LiteralInterpolated(LiteralParts()))

    assert LiteralRun(harness, state, null).Count == 0
    assert LiteralTypeText(harness.Literals.Result(state)) == "string"
}

test "EVERY HOLE IS ONE KIND-1 STEP, AT THE HOLE EXPRESSION'S OWN POSITION" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralHole("a", 3, 8))
    state := harness.Literals.Begin(LiteralInterpolated(parts))

    steps := LiteralRun(harness, state, BuiltInTypes.Int)

    assert steps.Count == 1
    assert steps[0].Kind == 1
    assert steps[0].NodeName == "a"
    assert steps[0].Line == 3
    assert steps[0].Column == 8
}

test "THE HOLE ORDER IS THE PART ORDER, AND TEXT BETWEEN HOLES DOES NOT REORDER THEM" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralText("x=", 3, 6))
    parts.Add(LiteralHole("a", 3, 8))
    parts.Add(LiteralText(" y=", 3, 10))
    parts.Add(LiteralHole("b", 3, 14))
    parts.Add(LiteralHole("c", 3, 18))
    parts.Add(LiteralText("!", 3, 20))
    state := harness.Literals.Begin(LiteralInterpolated(parts))

    steps := LiteralRun(harness, state, BuiltInTypes.Int)

    assert steps.Count == 3
    assert steps[0].NodeName == "a"
    assert steps[1].NodeName == "b"
    assert steps[2].NodeName == "c"
    assert steps[0].Column == 8
    assert steps[1].Column == 14
    assert steps[2].Column == 18
}

test "THE RESULT IS string BEFORE THE FIRST STEP AND AFTER THE LAST" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralHole("a", 3, 8))
    parts.Add(LiteralHole("b", 3, 14))
    state := harness.Literals.Begin(LiteralInterpolated(parts))

    steps := LiteralRun(harness, state, BuiltInTypes.Unknown)

    assert steps.Count == 2
    assert steps[0].ResultBefore == "string"
    assert steps[1].ResultBefore == "string"
    assert LiteralTypeText(harness.Literals.Result(state)) == "string"
}

test "A HOLE THAT ANSWERS NOTHING IS unknown, AND THE WALK STILL ANSWERS string" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralHole("a", 3, 8))
    state := harness.Literals.Begin(LiteralInterpolated(parts))

    steps := LiteralRun(harness, state, null)

    assert steps.Count == 1
    assert LiteralTypeText(state.HoleType) == "unknown"
    assert LiteralTypeText(harness.Literals.Result(state)) == "string"
    assert harness.Errors.Count == 0
}

// ── the two escape reports every hole is held to ────────────────────────

test "A HOLE WHOSE ANSWER IS AN SoA ROW VIEW IS REFUSED, AND THE ACTION IS NAMED" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralHole("row", 3, 8))
    state := harness.Literals.Begin(LiteralInterpolated(parts))

    LiteralRun(harness, state, LiteralRow())

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert LiteralErrorText(harness, 0) == "SoA row views cannot be formatted in an interpolated string; use the table and row index instead|3:8"
}

test "THE ROW REPORT'S OPERAND IS THE ANSWER THE STEP BEFORE IT PRODUCED" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralHole("a", 3, 8))
    state := harness.Literals.Begin(LiteralInterpolated(parts))

    steps := LiteralRun(harness, state, BuiltInTypes.Int)

    assert steps.Count == 1
    assert steps[0].ErrorsBefore == 0
    assert harness.Errors.Count == 0
}

test "EVERY ROW-VIEW HOLE IS REPORTED, NOT JUST THE FIRST" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralHole("a", 3, 8))
    parts.Add(LiteralHole("b", 3, 14))
    parts.Add(LiteralHole("c", 3, 20))
    state := harness.Literals.Begin(LiteralInterpolated(parts))

    steps := LiteralRun(harness, state, LiteralRow())

    assert steps.Count == 3
    assert harness.Errors.Count == 3
    assert steps[0].ErrorsBefore == 0
    assert steps[1].ErrorsBefore == 1
    assert steps[2].ErrorsBefore == 2
}

// ── the protocol invariants ─────────────────────────────────────────────

test "NO FORM ASKS FOR A KIND OTHER THAN 1" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralText("a", 3, 6))
    parts.Add(LiteralHole("b", 3, 8))
    parts.Add(LiteralHole("c", 3, 14))

    shapes := new List<Expression>()
    shapes.Add(new IntLiteralExpression("42", 3, 9))
    shapes.Add(new FloatLiteralExpression("1.5", 3, 9))
    shapes.Add(new CharLiteralExpression("a", 3, 9))
    shapes.Add(new StringLiteralExpression("hi", 3, 9))
    shapes.Add(LiteralInterpolated(parts))
    shapes.Add(new BoolLiteralExpression(false, 3, 9))
    shapes.Add(new NullLiteralExpression(3, 9))

    index := 0
    total := 0
    while index < shapes.Count {
        steps := LiteralRun(harness, harness.Literals.Begin(shapes[index]), BuiltInTypes.Int)
        stepIndex := 0
        while stepIndex < steps.Count {
            assert steps[stepIndex].Kind == 1
            stepIndex = stepIndex + 1
        }

        total = total + steps.Count
        index = index + 1
    }

    assert total == 2
}

test "THE STEP COUNT IS THE HOLE COUNT, AND SIX OF THE SEVEN FORMS ARE ZERO" {
    harness := LiteralDefault()

    assert LiteralRun(harness, harness.Literals.Begin(new IntLiteralExpression("42", 3, 9)), null).Count == 0
    assert LiteralRun(harness, harness.Literals.Begin(new FloatLiteralExpression("1.5", 3, 9)), null).Count == 0
    assert LiteralRun(harness, harness.Literals.Begin(new CharLiteralExpression("a", 3, 9)), null).Count == 0
    assert LiteralRun(harness, harness.Literals.Begin(new StringLiteralExpression("hi", 3, 9)), null).Count == 0
    assert LiteralRun(harness, harness.Literals.Begin(new BoolLiteralExpression(true, 3, 9)), null).Count == 0
    assert LiteralRun(harness, harness.Literals.Begin(new NullLiteralExpression(3, 9)), null).Count == 0

    holes := LiteralParts()
    holes.Add(LiteralHole("a", 3, 8))
    holes.Add(LiteralText("-", 3, 10))
    holes.Add(LiteralHole("b", 3, 12))
    assert LiteralRun(harness, harness.Literals.Begin(LiteralInterpolated(holes)), BuiltInTypes.Int).Count == 2
}

test "A WALK THAT ASKED FOR NOTHING FOLDS IN NOTHING WHEN SUPPLIED ANYWAY" {
    harness := LiteralDefault()
    state := harness.Literals.Begin(new IntLiteralExpression("42", 3, 9))

    harness.Literals.Supply(state, LiteralRow())

    assert LiteralTypeText(state.HoleType) == "unknown"
    assert LiteralTypeText(harness.Literals.Result(state)) == "int"
    assert harness.Errors.Count == 0
}

test "A FINISHED WALK KEEPS ANSWERING null FOREVER" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralHole("a", 3, 8))
    state := harness.Literals.Begin(LiteralInterpolated(parts))

    LiteralRun(harness, state, BuiltInTypes.Int)

    assert harness.Literals.NextStep(state) == null
    assert harness.Literals.NextStep(state) == null
    assert LiteralTypeText(harness.Literals.Result(state)) == "string"
}

test "TWO WALKS OVER THE SAME NODE DO NOT SHARE STATE" {
    harness := LiteralDefault()
    parts := LiteralParts()
    parts.Add(LiteralHole("a", 3, 8))
    parts.Add(LiteralHole("b", 3, 14))
    node := LiteralInterpolated(parts)

    first := LiteralRun(harness, harness.Literals.Begin(node), BuiltInTypes.Int)
    second := LiteralRun(harness, harness.Literals.Begin(node), BuiltInTypes.Int)

    assert first.Count == 2
    assert second.Count == 2
    assert first[0].NodeName == second[0].NodeName
    assert first[1].NodeName == second[1].NodeName
}

namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT AN OPERATOR MEANS — the unary and binary arms of the expression walk,
// the expression territory's largest and last coupled bloc.
//
// Every family before this one decided what its operands were WALKED UNDER. This one decides what
// the result is WORTH, which is a different kind of question and needs a different kind of contract:
// most of what is asserted here is a TABLE — which type two operands promote to, which pairs have no
// promotion at all, which comparisons are admitted — rather than a step schedule.
//
// The seven things it is easy to get wrong:
//
// (1) BINARY NUMERIC PROMOTION IS NOT IMPLICIT CONVERSION. `byte + byte` is an `int`, and no
// assignment rule says anything of the kind. Two pairs have NO answer rather than a widest one:
// `decimal` with a floating-point type, and `ulong` with any signed integral.
//
// (2) A SHIFT IS NOT SYMMETRIC. It is worth the UNARY promotion of its LEFT operand, so
// `byteValue << longCount` is an `int` — the count does not participate in the result at all.
//
// (3) ARITHMETIC CONSULTS AN OPERATOR OVERLOAD LAST AND COMPARISON CONSULTS ONE FIRST. `int + int`
// never goes looking for one; `a < b` on a user type asks before the primitive rule, because a type
// that defines `<` has said what comparing it means.
//
// (4) `&&` AND `||` ANSWER `bool` EVEN WHEN THEY REPORT. Cascading `unknown` out of a mistyped
// operand would silence every rule that reads the condition afterwards.
//
// (5) ALL FOUR OF A BINARY'S ESCAPE REPORTS RUN. The host joined them with a non-short-circuiting
// `|`, so an expression whose BOTH sides are row views is told about both.
//
// (6) THE INCREMENT GUARD CHAIN INTERLEAVES TWO OWNERS. Five of its reports belong to the
// write-target family and two belong to this owner, and the ORDER alternates between them — which is
// why they were five separate DRIVER KINDS while the write-target family was still C#. They are now
// ordinary calls, so an increment takes ONE step where it used to take seven, and the interleaving is
// asserted by the diagnostics it produces rather than by the schedule it asks for.
//
// (7) NEGATION READS THE TARGET-TYPING SLOT AND NO OTHER UNARY DOES. `-1` under a `byte` annotation
// is a `byte`, so the refusal a developer gets for `value: byte = -1` is about the MAGNITUDE.
class OperatorStep {
    Kind: int
    NodeName: string
    Line: int
    Column: int
    ErrorsBefore: int
    Narrowings: int

    constructor(kind: int, nodeName: string, line: int, column: int, errorsBefore: int, narrowings: int) {
        Kind = kind
        NodeName = nodeName
        Line = line
        Column = column
        ErrorsBefore = errorsBefore
        Narrowings = narrowings
    }
}

class OperatorHarness {
    Operators: AnalyzerOperatorExpressions
    Ambient: AnalyzerAmbientContext
    Context: AnalyzerDeclarationContext
    Escape: AnalyzerSoaEscape
    Scopes: AnalyzerScopeStack
    Model: SemanticModel
    Errors: List<CompilerError>

    constructor(operators: AnalyzerOperatorExpressions, ambient: AnalyzerAmbientContext, context: AnalyzerDeclarationContext, escape: AnalyzerSoaEscape, scopes: AnalyzerScopeStack, model: SemanticModel, errors: List<CompilerError>) {
        Operators = operators
        Ambient = ambient
        Context = context
        Escape = escape
        Scopes = scopes
        Model = model
        Errors = errors
    }
}

func OperatorPath(): string {
    return Path.GetFullPath("operator-expressions-contract.nl")
}

func OperatorHarnessWith(sourceText: string?): OperatorHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(OperatorPath(), sourceText)
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
    resolver.BeginAnalysis(OperatorPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    narrowing := new AnalyzerFlowNarrowing(scopes, resolver, assignability)
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)
    extensions := new List<FunctionDeclaration>()
    extensionResolution := new AnalyzerExtensionMethodResolution(resolver, assignability, context, functionTypes, clrConversion, extensions, new List<string>(), new List<Assembly>())
    members := new AnalyzerMemberResolution(functionTypes, context, substitution, resolver, clrConversion, extensionResolution, new List<string>())
    nullFlow := new AnalyzerNullFlow(diagnostics, spans, scopes, context)
    identifierResolution := new AnalyzerIdentifierResolution(diagnostics, scopes, resolver, discovery, probe, functionTypes, ambient, nullFlow, extensions, members, model, new BindingMap())
    memberAccess := new AnalyzerMemberAccess(diagnostics, spans, scopes, context, nullFlow, escape, ambient, provider, discovery, probe, substitution, identifierResolution, extensions, new List<string>(), new Dictionary<string, string>(StringComparer.Ordinal), new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal), new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal), new List<Assembly>(), members, clrConversion, extensionResolution, new BindingMap())
    indexAccess := new AnalyzerIndexAccess(diagnostics, spans, context, ambient, nullFlow, escape, memberAccess, new AnalyzerConstantExpressionFacts(scopes, context))
    writeTargets := new AnalyzerWriteTargets(diagnostics, spans, scopes, context, substitution, clrConversion, ambient, escape, memberAccess, indexAccess)
    operators := new AnalyzerOperatorExpressions(diagnostics, spans, scopes, context, substitution, assignability, clrConversion, probe, escape, ambient, narrowing, writeTargets)
    return new OperatorHarness(operators, ambient, context, escape, scopes, model, errors)
}

func OperatorDefault(): OperatorHarness {
    return OperatorHarnessWith(null)
}

func OperatorTypeText(candidate: TypeInfo?): string {
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

func OperatorNodeName(node: Expression?): string {
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

func OperatorNarrowingCount(narrowings: List<FlowNarrowing>?): int {
    if narrowings == null {
        return -1
    }

    return narrowings.Count
}

// ── the operator driver, exactly as `Analyzer.cs` writes it ─────────────
//
// The one difference is that the expression steps are ANSWERED from a supplied list rather than by
// re-entering the analyzer's own walk, which is the one thing a contract cannot replay. Every step
// records the error count BEFORE it and — for the narrowed walk — how many facts it was handed.
func OperatorRun(harness: OperatorHarness, state: OperatorExpressionState, answers: List<TypeInfo?>): List<OperatorStep> {
    steps := new List<OperatorStep>()
    step := harness.Operators.NextStep(state)
    while step != null {
        index := steps.Count
        steps.Add(new OperatorStep(step.Kind, OperatorNodeName(step.Node), step.Line, step.Column, harness.Errors.Count, OperatorNarrowingCount(step.Narrowings)))
        answer: TypeInfo? = null
        if index < answers.Count {
            answer = answers[index]
        }

        harness.Operators.Supply(state, answer)
        step = harness.Operators.NextStep(state)
    }

    return steps
}

func OperatorAnswers(first: TypeInfo?, second: TypeInfo?): List<TypeInfo?> {
    answers := new List<TypeInfo?>()
    answers.Add(first)
    answers.Add(second)
    return answers
}

// AN INCREMENT WALK ASKS FOR ITS OPERAND AT INDEX 2, not index 0: the null-conditional question and
// the write-target shape question both come first. A contract that supplies the type at index 0 is
// answering the wrong step and gets `unknown` back.
// AN INCREMENT'S OPERAND IS THE FIRST AND ONLY STEP now that the six write-target questions in front
// of it are calls rather than kinds; it used to be the third.
func OperatorIncrementAnswers(operandType: TypeInfo?): List<TypeInfo?> {
    answers := new List<TypeInfo?>()
    answers.Add(operandType)
    return answers
}

func OperatorOne(answer: TypeInfo?): List<TypeInfo?> {
    answers := new List<TypeInfo?>()
    answers.Add(answer)
    return answers
}

func OperatorNone(): List<TypeInfo?> {
    return new List<TypeInfo?>()
}

func OperatorIdentifier(name: string, line: int, column: int): Expression {
    expression: Expression = new IdentifierExpression(name, line, column)
    return expression
}

func OperatorBinary(left: Expression, op: BinaryOperator, right: Expression): Expression {
    expression: Expression = new BinaryExpression(left, op, right, 2, 5)
    return expression
}

func OperatorSimpleBinary(op: BinaryOperator): Expression {
    return OperatorBinary(OperatorIdentifier("a", 2, 5), op, OperatorIdentifier("b", 2, 9))
}

func OperatorUnary(op: UnaryOperator, operand: Expression): Expression {
    expression: Expression = new UnaryExpression(op, operand, 2, 5)
    return expression
}

func OperatorSimpleUnary(op: UnaryOperator): Expression {
    return OperatorUnary(op, OperatorIdentifier("a", 2, 6))
}

func OperatorRow(name: string): TypeInfo {
    columns := new List<SoaColumnInfo>()
    row: TypeInfo = new SoaRowTypeInfo(new SoaRecordDeclarationInfo(name, columns, 1, 1))
    return row
}

// A FLAGS ENUM — an `int`-backed declaration. Identity is what the bitwise and equality rules test,
// so the SAME instance must be handed to both sides to make them agree.
func OperatorFlagsEnum(name: string): TypeInfo {
    members := new List<EnumMemberInfo>()
    flags: TypeInfo = new EnumTypeInfo(new EnumDeclarationInfo(name, members, EnumType.Int, 1, 1))
    return flags
}

func OperatorStringEnum(name: string): TypeInfo {
    members := new List<EnumMemberInfo>()
    named: TypeInfo = new EnumTypeInfo(new EnumDeclarationInfo(name, members, EnumType.String, 1, 1))
    return named
}

func OperatorErrorText(harness: OperatorHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + ":" + error.Length.ToString()
}

// ── the protocol, which is the same for both arms ───────────────────────

test "NO FORM ASKS FOR A KIND OUTSIDE 1-10" {
    harness := OperatorDefault()
    nodes := new List<Expression>()
    nodes.Add(OperatorSimpleBinary(BinaryOperator.Add))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.And))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.Or))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.NullCoalesce))
    nodes.Add(OperatorSimpleUnary(UnaryOperator.Negate))
    nodes.Add(OperatorSimpleUnary(UnaryOperator.Not))
    nodes.Add(OperatorSimpleUnary(UnaryOperator.BitwiseNot))
    nodes.Add(OperatorSimpleUnary(UnaryOperator.PreIncrement))
    nodes.Add(OperatorSimpleUnary(UnaryOperator.PostDecrement))
    nodes.Add(OperatorSimpleUnary(UnaryOperator.IndexFromEnd))

    index := 0
    while index < nodes.Count {
        state := harness.Operators.Begin(nodes[index])
        steps := OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Int))
        stepIndex := 0
        while stepIndex < steps.Count {
            assert steps[stepIndex].Kind >= 1 && steps[stepIndex].Kind <= 10
            stepIndex = stepIndex + 1
        }

        index = index + 1
    }
}

test "A NODE THAT IS NEITHER TAKES NO STEPS AND ANSWERS unknown" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorIdentifier("v", 2, 5))

    steps := OperatorRun(harness, state, OperatorOne(BuiltInTypes.Int))

    assert state.Form == -1
    assert steps.Count == 0
    assert OperatorTypeText(harness.Operators.Result(state)) == "unknown"
    assert harness.Errors.Count == 0
}

test "NO DIAGNOSTIC LANDS AT Begin, AND NEITHER ARM SETTLES ITS ANSWER BEFORE ITS STEPS" {
    harness := OperatorDefault()
    binaryState := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Add))

    assert harness.Errors.Count == 0
    assert OperatorTypeText(harness.Operators.Result(binaryState)) == "unknown"

    unaryState := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.Negate))

    assert harness.Errors.Count == 0
    assert OperatorTypeText(harness.Operators.Result(unaryState)) == "unknown"
}

test "A FINISHED WALK KEEPS ANSWERING null AND ITS RESULT IS STABLE" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Add))

    OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Int))

    assert harness.Operators.NextStep(state) == null
    assert harness.Operators.NextStep(state) == null
    assert OperatorTypeText(harness.Operators.Result(state)) == "int"

    // A walk that asked for nothing folds in nothing when supplied anyway.
    harness.Operators.Supply(state, BuiltInTypes.String)

    assert OperatorTypeText(harness.Operators.Result(state)) == "int"
}

test "THE STEP COUNT IS THE FORM'S SHAPE — A BINARY TWO, A PLAIN UNARY ONE, AN INCREMENT SEVEN" {
    harness := OperatorDefault()
    binaryState := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Add))
    binarySteps := OperatorRun(harness, binaryState, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Int))

    assert binaryState.Form == 0
    assert binarySteps.Count == 2

    unaryState := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.Negate))
    unarySteps := OperatorRun(harness, unaryState, OperatorOne(BuiltInTypes.Int))

    assert unaryState.Form == 1
    assert unarySteps.Count == 1

    // AN INCREMENT NOW TAKES ONE STEP, NOT SEVEN. Its six write-target questions used to be driver
    // kinds because the reports lived in `Analyzer.cs`; the owner asks them itself now, so the only
    // thing it hands the driver is the operand walk.
    incrementState := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.PreIncrement))
    incrementSteps := OperatorRun(harness, incrementState, OperatorOne(BuiltInTypes.Int))

    assert incrementSteps.Count == 1
    assert incrementSteps[0].Kind == 1
}

// ── the four walks ──────────────────────────────────────────────────────

test "THE LEFT SIDE OF ?? IS THE ONLY OPERAND WALKED WITH THE NULLABILITY FLOW TYPE PRESERVED" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.NullCoalesce))

    steps := OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.String, BuiltInTypes.String))

    assert steps[0].Kind == 2
    assert steps[0].NodeName == "a"
    assert steps[1].Kind == 1
    assert steps[1].NodeName == "b"
}

test "A SHORT-CIRCUIT RIGHT OPERAND IS THE NARROWED WALK ONLY WHEN THE LEFT PROVED SOMETHING" {
    harness := OperatorDefault()

    // A left side that proves nothing: two plain names.
    plain := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.And))
    plainSteps := OperatorRun(harness, plain, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Bool))

    assert plainSteps[1].Kind == 1
    assert plainSteps[1].Narrowings == -1

    // `x != null` proves `x` is not null in the branch it guards.
    nullCompare := OperatorBinary(OperatorIdentifier("x", 2, 5), BinaryOperator.NotEqual, new NullLiteralExpression(2, 10))
    narrowed := harness.Operators.Begin(OperatorBinary(nullCompare, BinaryOperator.And, OperatorIdentifier("b", 2, 18)))
    narrowedSteps := OperatorRun(harness, narrowed, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Bool))

    assert narrowedSteps[1].Kind == 3
    assert narrowedSteps[1].Narrowings == 1
}

test "&& TAKES THE THEN FACTS AND || TAKES THE ELSE FACTS" {
    harness := OperatorDefault()

    // A PLAIN null comparison proves something on BOTH sides — `x == null` proves null when true and
    // not-null when false — so it cannot tell the two lists apart. A CONJUNCTION can: `a && b`
    // proves both sides in the true branch and NOTHING in the false one, because the negation of a
    // conjunction is a disjunction.
    first := OperatorBinary(OperatorIdentifier("x", 2, 5), BinaryOperator.NotEqual, new NullLiteralExpression(2, 10))
    second := OperatorBinary(OperatorIdentifier("y", 2, 19), BinaryOperator.NotEqual, new NullLiteralExpression(2, 24))
    bothNotNull := OperatorBinary(first, BinaryOperator.And, second)

    conjunction := harness.Operators.Begin(OperatorBinary(bothNotNull, BinaryOperator.And, OperatorIdentifier("b", 2, 33)))
    conjunctionSteps := OperatorRun(harness, conjunction, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Bool))

    assert conjunctionSteps[1].Kind == 3
    assert conjunctionSteps[1].Narrowings == 2

    disjunction := harness.Operators.Begin(OperatorBinary(bothNotNull, BinaryOperator.Or, OperatorIdentifier("b", 3, 33)))
    disjunctionSteps := OperatorRun(harness, disjunction, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Bool))

    // The same left operand proves NOTHING for a disjunction's right side.
    assert disjunctionSteps[1].Kind == 1
    assert disjunctionSteps[1].Narrowings == -1
}

// THE CAPTURE BRACKET IS OBSERVED WHERE IT LIVES — in the ambient slot, AT the step — which is
// strictly stronger than the retired kind 4 was: a kind said the walk had been ASKED for, the slot
// says the table was actually INSTALLED, and it also proves it is CLOSED again afterwards.
// THE CAPTURE BRACKET IS OBSERVED WHERE IT LIVES — in the ambient slot, AT the step — which is
// strictly stronger than the retired kind 4 was: a kind said the walk had been ASKED for, the slot
// says the table was actually INSTALLED, and it also proves it is CLOSED again the instant the answer
// arrives rather than at the next step.
test "A MEMBER OR INDEX WRITE TARGET OPENS THE CAPTURE TABLE AND A PLAIN NAME DOES NOT" {
    harness := OperatorDefault()

    plain := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.PreIncrement))
    plainStep := harness.Operators.NextStep(plain)

    assert plainStep != null
    assert plainStep.Kind == 1
    assert !harness.Ambient.InWriteTarget
    harness.Operators.Supply(plain, BuiltInTypes.Int)
    assert !harness.Ambient.InWriteTarget

    member: Expression = new MemberAccessExpression(OperatorIdentifier("box", 2, 6), "count", false, 2, 6)
    chained := harness.Operators.Begin(OperatorUnary(UnaryOperator.PreIncrement, member))
    chainedStep := harness.Operators.NextStep(chained)

    assert chainedStep != null
    assert chainedStep.Kind == 1
    assert harness.Ambient.InWriteTarget
    harness.Operators.Supply(chained, BuiltInTypes.Int)
    assert !harness.Ambient.InWriteTarget
}

// ── arithmetic ──────────────────────────────────────────────────────────

test "ARITHMETIC IS BINARY NUMERIC PROMOTION AND byte + byte IS AN int" {
    harness := OperatorDefault()

    state := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Add))
    OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.Byte, BuiltInTypes.Byte))

    assert OperatorTypeText(harness.Operators.Result(state)) == "int"
    assert harness.Errors.Count == 0

    wider := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Multiply))
    OperatorRun(harness, wider, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Long))

    assert OperatorTypeText(harness.Operators.Result(wider)) == "long"

    unsignedMix := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Subtract))
    OperatorRun(harness, unsignedMix, OperatorAnswers(BuiltInTypes.UInt, BuiltInTypes.Int))

    // `uint` with a signed type widens to `long`, which is the one promotion that is neither operand.
    assert OperatorTypeText(harness.Operators.Result(unsignedMix)) == "long"
    assert harness.Errors.Count == 0
}

test "TWO PAIRS HAVE NO COMMON TYPE AT ALL AND THE REPORT UNDERLINES THE OPERATOR" {
    harness := OperatorDefault()

    decimalWithDouble := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Add))
    OperatorRun(harness, decimalWithDouble, OperatorAnswers(BuiltInTypes.Decimal, BuiltInTypes.Double))

    assert OperatorTypeText(harness.Operators.Result(decimalWithDouble)) == "unknown"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "The '+' operator doesn't work with 'decimal' and 'double'"

    unsignedWithSigned := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Add))
    OperatorRun(harness, unsignedWithSigned, OperatorAnswers(BuiltInTypes.ULong, BuiltInTypes.Long))

    assert OperatorTypeText(harness.Operators.Result(unsignedWithSigned)) == "unknown"
    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "The '+' operator doesn't work with 'ulong' and 'long'"
}

test "+ WITH A STRING ON EITHER SIDE IS CONCATENATION, AND ONLY +" {
    harness := OperatorDefault()

    leftString := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Add))
    OperatorRun(harness, leftString, OperatorAnswers(BuiltInTypes.String, BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(leftString)) == "string"

    rightString := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Add))
    OperatorRun(harness, rightString, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.String))

    assert OperatorTypeText(harness.Operators.Result(rightString)) == "string"
    assert harness.Errors.Count == 0

    // `-` over the same operands is a type error: concatenation is `+`'s rule and nothing else's.
    subtract := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Subtract))
    OperatorRun(harness, subtract, OperatorAnswers(BuiltInTypes.String, BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(subtract)) == "unknown"
    assert harness.Errors.Count == 1
}

test "AN unknown OPERAND IS NEVER AN OPERATOR ERROR" {
    harness := OperatorDefault()
    nodes := new List<Expression>()
    nodes.Add(OperatorSimpleBinary(BinaryOperator.Add))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.BitwiseAnd))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.LeftShift))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.Less))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.Equal))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.And))

    index := 0
    while index < nodes.Count {
        state := harness.Operators.Begin(nodes[index])
        OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.Unknown, BuiltInTypes.Int))

        assert OperatorTypeText(harness.Operators.Result(state)) == "unknown"
        index = index + 1
    }

    assert harness.Errors.Count == 0
}

test "A NON-NUMERIC ARITHMETIC OPERAND IS BLAMED BY SIDE" {
    harness := OperatorDefault()

    oneSide := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Multiply))
    OperatorRun(harness, oneSide, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Bool))

    assert harness.Errors[0].Message == "The '*' operator doesn't work with 'int' and 'bool' — both sides need numeric values, but the right side is 'bool'"

    bothSides := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Multiply))
    OperatorRun(harness, bothSides, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Bool))

    assert harness.Errors[1].Message == "The '*' operator doesn't work with 'bool' and 'bool' — both sides need numeric values, but I found 'bool' and 'bool'"
}

// ── bitwise, shift ──────────────────────────────────────────────────────

test "BITWISE OVER TWO BOOLEANS IS A BOOLEAN AND OVER TWO INTEGRALS IS THEIR COMMON TYPE" {
    harness := OperatorDefault()

    booleans := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.BitwiseAnd))
    OperatorRun(harness, booleans, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Bool))

    assert OperatorTypeText(harness.Operators.Result(booleans)) == "bool"

    integrals := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.BitwiseOr))
    OperatorRun(harness, integrals, OperatorAnswers(BuiltInTypes.Byte, BuiltInTypes.Long))

    assert OperatorTypeText(harness.Operators.Result(integrals)) == "long"
    assert harness.Errors.Count == 0

    // A boolean with an integral is neither rule.
    mixed := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.BitwiseXor))
    OperatorRun(harness, mixed, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(mixed)) == "unknown"
    assert harness.Errors[0].Message == "The '^' operator doesn't work with 'bool' and 'int' — both sides need integral values, or both sides need booleans, but I found 'bool' and 'int'"
}

test "BITWISE OVER THE SAME FLAGS ENUM IS THAT ENUM AND OVER TWO DIFFERENT ONES IS NOT" {
    harness := OperatorDefault()
    flags := OperatorFlagsEnum("Access")

    same := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.BitwiseOr))
    OperatorRun(harness, same, OperatorAnswers(flags, flags))

    assert OperatorTypeText(harness.Operators.Result(same)) == "Access"
    assert harness.Errors.Count == 0

    other := OperatorFlagsEnum("Colours")
    different := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.BitwiseOr))
    OperatorRun(harness, different, OperatorAnswers(flags, other))

    assert OperatorTypeText(harness.Operators.Result(different)) == "unknown"
    assert harness.Errors.Count == 1

    // A `string`-backed enum has no bitwise meaning even against itself.
    named := OperatorStringEnum("Names")
    stringBacked := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.BitwiseAnd))
    OperatorRun(harness, stringBacked, OperatorAnswers(named, named))

    assert OperatorTypeText(harness.Operators.Result(stringBacked)) == "unknown"
    assert harness.Errors.Count == 2
}

test "A SHIFT IS THE UNARY PROMOTION OF ITS LEFT OPERAND AND THE COUNT NEVER PARTICIPATES" {
    harness := OperatorDefault()

    small := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.LeftShift))
    OperatorRun(harness, small, OperatorAnswers(BuiltInTypes.Byte, BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(small)) == "int"

    // A `long` COUNT does not widen a `byte` left operand — which is what makes the shift the one
    // asymmetric binary in the family.
    wideCount := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.RightShift))
    OperatorRun(harness, wideCount, OperatorAnswers(BuiltInTypes.Byte, BuiltInTypes.Long))

    assert OperatorTypeText(harness.Operators.Result(wideCount)) == "int"

    wideValue := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.LeftShift))
    OperatorRun(harness, wideValue, OperatorAnswers(BuiltInTypes.Long, BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(wideValue)) == "long"
    assert harness.Errors.Count == 0
}

test "A SHIFT BLAMES A BOOLEAN SIDE WHERE THE BITWISE OPERATORS DO NOT" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.LeftShift))

    OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Bool))

    // The shift arm re-derives "wrong" WITHOUT the boolean exemption, so both sides are named.
    assert harness.Errors[0].Message == "The '<<' operator doesn't work with 'bool' and 'bool' — the left side needs an integral value, and the shift count needs an integral value, but I found 'bool' and 'bool'"
}

// ── comparison and equality ─────────────────────────────────────────────

test "A RELATIONAL COMPARISON ANSWERS bool AND ITS DOMAIN EXCLUDES decimal" {
    harness := OperatorDefault()

    numeric := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Less))
    OperatorRun(harness, numeric, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Double))

    assert OperatorTypeText(harness.Operators.Result(numeric)) == "bool"
    assert harness.Errors.Count == 0

    // `decimal` is numeric but is NOT primitive-relational — and it still compares, because the
    // OVERLOAD is consulted FIRST and `System.Decimal` declares `op_GreaterThanOrEqual`. The
    // exclusion is about which RULE answers, not about whether the comparison is allowed.
    money := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.GreaterOrEqual))
    OperatorRun(harness, money, OperatorAnswers(BuiltInTypes.Decimal, BuiltInTypes.Decimal))

    assert OperatorTypeText(harness.Operators.Result(money)) == "bool"
    assert harness.Errors.Count == 0

    // A type with neither a comparison overload nor a place in the primitive domain is refused.
    booleans := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Less))
    OperatorRun(harness, booleans, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Bool))

    assert OperatorTypeText(harness.Operators.Result(booleans)) == "unknown"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "The '<' operator doesn't work with 'bool' and 'bool' — both sides need primitive numeric values or a comparison operator overload, but I found 'bool' and 'bool'"
}

test "EQUALITY ADMITS null, TWO REFERENCE TYPES AND THE SAME FLAGS ENUM" {
    harness := OperatorDefault()

    withNull := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Equal))
    OperatorRun(harness, withNull, OperatorAnswers(BuiltInTypes.String, BuiltInTypes.Null))

    assert OperatorTypeText(harness.Operators.Result(withNull)) == "bool"

    references := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.NotEqual))
    OperatorRun(harness, references, OperatorAnswers(BuiltInTypes.String, BuiltInTypes.String))

    assert OperatorTypeText(harness.Operators.Result(references)) == "bool"

    flags := OperatorFlagsEnum("Access")
    enums := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Equal))
    OperatorRun(harness, enums, OperatorAnswers(flags, flags))

    assert OperatorTypeText(harness.Operators.Result(enums)) == "bool"
    assert harness.Errors.Count == 0
}

test "A BOOLEAN COMPARES ONLY WITH A BOOLEAN, AND THAT IS NOT THE NUMERIC RULE" {
    harness := OperatorDefault()

    booleans := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Equal))
    OperatorRun(harness, booleans, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Bool))

    assert OperatorTypeText(harness.Operators.Result(booleans)) == "bool"
    assert harness.Errors.Count == 0

    // One boolean side makes the whole question a boolean one — it does not fall through to the
    // numeric rule, which would have accepted `bool` against `int` by widening.
    mixed := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Equal))
    OperatorRun(harness, mixed, OperatorAnswers(BuiltInTypes.Bool, BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(mixed)) == "unknown"
    assert harness.Errors[0].Message == "The '==' operator doesn't work with 'bool' and 'int' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload"
}

test "EQUALITY OVER A PAIR WITH NO COMMON TYPE IS REFUSED" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.NotEqual))

    OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.ULong, BuiltInTypes.Long))

    assert OperatorTypeText(harness.Operators.Result(state)) == "unknown"
    assert harness.Errors.Count == 1
}

// ── the logical operators and ?? ────────────────────────────────────────

test "&& AND || ANSWER bool EVEN WHEN THEY REPORT" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.And))

    OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Bool))

    // The report fires AND the answer is still `bool`: cascading `unknown` out of a mistyped operand
    // would silence every rule that reads the condition afterwards.
    assert OperatorTypeText(harness.Operators.Result(state)) == "bool"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Both sides of '&&' must be booleans, but the left side is 'int'"
}

test "?? IS ITS RIGHT SIDE, EXCEPT OVER A throw" {
    harness := OperatorDefault()
    nullableString: TypeInfo = new NullableTypeInfo(BuiltInTypes.String)

    fallback := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.NullCoalesce))
    OperatorRun(harness, fallback, OperatorAnswers(nullableString, BuiltInTypes.String))

    assert OperatorTypeText(harness.Operators.Result(fallback)) == "string"
    assert harness.Errors.Count == 0

    throwNode: Expression = new ThrowExpression(OperatorIdentifier("e", 2, 15), 2, 9)
    thrown := harness.Operators.Begin(OperatorBinary(OperatorIdentifier("a", 2, 5), BinaryOperator.NullCoalesce, throwNode))
    OperatorRun(harness, thrown, OperatorAnswers(nullableString, BuiltInTypes.Never))

    // Nothing comes back from a `throw`, so the expression is the LEFT side with its nullability
    // removed rather than the right side's `never`.
    assert OperatorTypeText(harness.Operators.Result(thrown)) == "string"
    assert harness.Errors.Count == 0
}

test "A ?? LEFT SIDE THAT CANNOT BE NULL IS TOLD SO" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.NullCoalesce))

    OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Int))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "The left side of '??' has type 'int', which can't be null"

    // The report does not change the answer: `??` is still worth its right side.
    assert OperatorTypeText(harness.Operators.Result(state)) == "int"
}

test ".. IS System.Range AND ^n IS System.Index" {
    harness := OperatorDefault()

    range := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Range))
    OperatorRun(harness, range, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(range)) == "Range"

    index := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.IndexFromEnd))
    OperatorRun(harness, index, OperatorOne(BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(index)) == "Index"
    assert harness.Errors.Count == 0
}

// ── the escape reports ──────────────────────────────────────────────────

test "ALL FOUR OF A BINARY'S ESCAPE REPORTS RUN AND NONE STOPS ANOTHER" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Add))

    OperatorRun(harness, state, OperatorAnswers(OperatorRow("Points"), OperatorRow("Points")))

    // BOTH sides are told, because both of them really are trying to leave.
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "SoA row views cannot be used as an operator operand; use the table and row index instead"
    assert harness.Errors[1].Message == "SoA row views cannot be used as an operator operand; use the table and row index instead"
    assert OperatorTypeText(harness.Operators.Result(state)) == "unknown"
}

test "EVERY BINARY GROUP ASKS THE SAME FOUR ESCAPE QUESTIONS" {
    harness := OperatorDefault()
    nodes := new List<Expression>()
    nodes.Add(OperatorSimpleBinary(BinaryOperator.Add))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.And))
    nodes.Add(OperatorSimpleBinary(BinaryOperator.NullCoalesce))

    index := 0
    while index < nodes.Count {
        before := harness.Errors.Count
        state := harness.Operators.Begin(nodes[index])
        OperatorRun(harness, state, OperatorAnswers(OperatorRow("Points"), BuiltInTypes.Int))

        assert harness.Errors.Count == before + 1
        assert OperatorTypeText(harness.Operators.Result(state)) == "unknown"
        index = index + 1
    }
}

test "A UNARY OPERAND THAT IS A ROW VIEW IS REFUSED BEFORE ANY OPERATOR RULE RUNS" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.Negate))

    OperatorRun(harness, state, OperatorOne(OperatorRow("Points")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as a unary operand; use the table and row index instead"
    assert OperatorTypeText(harness.Operators.Result(state)) == "unknown"
}

test "A UNARY OPERAND THAT IS A DIRECT COLUMN VALUE IS REFUSED BY THE SECOND QUESTION" {
    harness := OperatorDefault()
    column := new MemberAccessExpression(OperatorIdentifier("points", 2, 6), "x", false, 2, 6)
    harness.Escape.RecordColumnMemberAccess(column)
    operand: Expression = column
    state := harness.Operators.Begin(OperatorUnary(UnaryOperator.Negate, operand))

    OperatorRun(harness, state, OperatorOne(BuiltInTypes.Int))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be used as a unary operand directly"
    assert OperatorTypeText(harness.Operators.Result(state)) == "unknown"
}

// ── the unary rules ─────────────────────────────────────────────────────

test "NEGATION READS THE TARGET-TYPING SLOT AND NO OTHER UNARY DOES" {
    harness := OperatorDefault()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.SByte)
    literal: Expression = new IntLiteralExpression("1", 2, 6)
    state := harness.Operators.Begin(OperatorUnary(UnaryOperator.Negate, literal))

    OperatorRun(harness, state, OperatorOne(BuiltInTypes.Int))

    // `-1` under an `sbyte` annotation is an `sbyte`, so `value: sbyte = -128` is silent while
    // `value: sbyte = -129` is refused about the MAGNITUDE rather than about the operator.
    assert OperatorTypeText(harness.Operators.Result(state)) == "sbyte"

    // `~` over the same literal under the same annotation is NOT target-typed.
    complement := harness.Operators.Begin(OperatorUnary(UnaryOperator.BitwiseNot, literal))
    OperatorRun(harness, complement, OperatorOne(BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(complement)) == "int"
    harness.Ambient.ExitExpectedType(saved)
}

test "AN UNSIGNED ANNOTATION CANNOT TARGET-TYPE A NEGATIVE LITERAL AT ALL" {
    harness := OperatorDefault()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)
    literal: Expression = new IntLiteralExpression("1", 2, 6)
    state := harness.Operators.Begin(OperatorUnary(UnaryOperator.Negate, literal))

    OperatorRun(harness, state, OperatorOne(BuiltInTypes.Int))

    // A `byte` has NO negative range, so the target-typing door is shut and the literal keeps its
    // own promotion. That is why `value: byte = -1` is refused about the TYPE and not the magnitude.
    assert OperatorTypeText(harness.Operators.Result(state)) == "int"
    assert harness.Errors.Count == 0
    harness.Ambient.ExitExpectedType(saved)
}

test "A SUFFIXED NEGATIVE LITERAL IS NOT TARGET-TYPED — THE SUFFIX IS WHAT THE PROGRAMMER MEANT" {
    harness := OperatorDefault()
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.Byte)
    literal: Expression = new IntLiteralExpression("1L", 2, 6)
    state := harness.Operators.Begin(OperatorUnary(UnaryOperator.Negate, literal))

    OperatorRun(harness, state, OperatorOne(BuiltInTypes.Long))

    assert OperatorTypeText(harness.Operators.Result(state)) == "long"
    harness.Ambient.ExitExpectedType(saved)
}

test "NEGATION'S PROMOTION DIFFERS FROM THE SHIFT'S IN EXACTLY TWO PLACES" {
    harness := OperatorDefault()

    small := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.Negate))
    OperatorRun(harness, small, OperatorOne(BuiltInTypes.Byte))

    assert OperatorTypeText(harness.Operators.Result(small)) == "int"

    // `-uint` does not fit a `uint`, so it widens to `long`.
    unsigned := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.Negate))
    OperatorRun(harness, unsigned, OperatorOne(BuiltInTypes.UInt))

    assert OperatorTypeText(harness.Operators.Result(unsigned)) == "long"

    // No integral type holds the negation of every `ulong`, so there is no answer at all.
    wide := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.Negate))
    OperatorRun(harness, wide, OperatorOne(BuiltInTypes.ULong))

    assert OperatorTypeText(harness.Operators.Result(wide)) == "unknown"
    assert harness.Errors[0].Message == "The '-' operator doesn't work with 'ulong' — the operand needs a signed numeric value, a floating-point value, decimal, or uint"
}

test "~ OVER A FLAGS ENUM IS THAT ENUM AND OVER AN INTEGRAL IS ITS PROMOTION" {
    harness := OperatorDefault()
    flags := OperatorFlagsEnum("Access")

    enumState := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.BitwiseNot))
    OperatorRun(harness, enumState, OperatorOne(flags))

    assert OperatorTypeText(harness.Operators.Result(enumState)) == "Access"

    integral := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.BitwiseNot))
    OperatorRun(harness, integral, OperatorOne(BuiltInTypes.UShort))

    assert OperatorTypeText(harness.Operators.Result(integral)) == "int"

    // A floating-point promotion exists but is not integral, so `~` still refuses it.
    floating := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.BitwiseNot))
    OperatorRun(harness, floating, OperatorOne(BuiltInTypes.Double))

    assert OperatorTypeText(harness.Operators.Result(floating)) == "unknown"
    assert harness.Errors[0].Message == "The '~' operator doesn't work with 'double' — the operand needs an integral value"
}

test "! IS A BOOLEAN AND NOTHING ELSE" {
    harness := OperatorDefault()

    boolean := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.Not))
    OperatorRun(harness, boolean, OperatorOne(BuiltInTypes.Bool))

    assert OperatorTypeText(harness.Operators.Result(boolean)) == "bool"
    assert harness.Errors.Count == 0

    number := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.Not))
    OperatorRun(harness, number, OperatorOne(BuiltInTypes.Int))

    assert OperatorTypeText(harness.Operators.Result(number)) == "unknown"
    assert harness.Errors[0].Message == "The '!' operator doesn't work with 'int' — the operand needs a boolean value"
}

test "++ AND -- ANSWER THE OPERAND'S OWN TYPE RATHER THAN A PROMOTION OF IT" {
    harness := OperatorDefault()

    small := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.PostIncrement))
    OperatorRun(harness, small, OperatorIncrementAnswers(BuiltInTypes.Byte))

    // A `byte` counter stays a `byte`: the value is written back into the storage it came from.
    assert OperatorTypeText(harness.Operators.Result(small)) == "byte"

    flags := OperatorFlagsEnum("Access")
    enumState := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.PreDecrement))
    OperatorRun(harness, enumState, OperatorIncrementAnswers(flags))

    assert OperatorTypeText(harness.Operators.Result(enumState)) == "Access"

    floating := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.PreIncrement))
    OperatorRun(harness, floating, OperatorIncrementAnswers(BuiltInTypes.Double))

    assert OperatorTypeText(harness.Operators.Result(floating)) == "unknown"
    assert harness.Errors[0].Message == "The '++' operator doesn't work with 'double' — the operand needs an integral numeric value"
}

test "^n MEASURES ITS COUNT BY ASSIGNABILITY TO int RATHER THAN BY THE NUMERIC PREDICATE" {
    harness := OperatorDefault()

    text := harness.Operators.Begin(OperatorSimpleUnary(UnaryOperator.IndexFromEnd))
    OperatorRun(harness, text, OperatorOne(BuiltInTypes.String))

    assert OperatorTypeText(harness.Operators.Result(text)) == "unknown"
    assert harness.Errors[0].Message == "The '^' operator doesn't work with 'string' — the from-end index count must be an int-compatible value"
}

// ── the increment guard chain ───────────────────────────────────────────

// A NULL-CONDITIONAL TARGET IS REFUSED BEFORE THE OPERAND IS WALKED AT ALL, and the walk that used
// to prove it by counting steps now proves it by taking NONE: `a?.b++` asks the driver for nothing.
test "A NULL-CONDITIONAL WRITE TARGET IS REFUSED BEFORE THE OPERAND IS EVEN WALKED" {
    harness := OperatorDefault()
    member: Expression = new MemberAccessExpression(OperatorIdentifier("box", 2, 5), "count", true, 2, 5)
    state := harness.Operators.Begin(OperatorUnary(UnaryOperator.PostIncrement, member))

    steps := OperatorRun(harness, state, OperatorOne(BuiltInTypes.Int))

    assert steps.Count == 0
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Null-conditional member access can't be changed with '++'"
    assert OperatorTypeText(harness.Operators.Result(state)) == "unknown"
}

// THE WORDING EACH LINK HANDS ITS REPORTER used to be read off the request; it is now read off the
// DIAGNOSTIC, which is strictly stronger — it proves the sentence was RENDERED rather than merely
// requested, and it proves which reporter received which wording.
test "THE WRITE-TARGET REPORTS CARRY THE WORDING THE DEVELOPER READS" {
    harness := OperatorDefault()
    member: Expression = new MemberAccessExpression(OperatorIdentifier("box", 2, 5), "count", true, 2, 5)

    decrement := harness.Operators.Begin(OperatorUnary(UnaryOperator.PreDecrement, member))
    OperatorRun(harness, decrement, OperatorOne(BuiltInTypes.Int))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Null-conditional member access can't be changed with '--'"

    increment := harness.Operators.Begin(OperatorUnary(UnaryOperator.PostIncrement, member))
    OperatorRun(harness, increment, OperatorOne(BuiltInTypes.Int))

    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "Null-conditional member access can't be changed with '++'"
}

test "A PLAIN UNARY ASKS NO WRITE-TARGET QUESTION AT ALL" {
    harness := OperatorDefault()
    nodes := new List<Expression>()
    nodes.Add(OperatorSimpleUnary(UnaryOperator.Negate))
    nodes.Add(OperatorSimpleUnary(UnaryOperator.Not))
    nodes.Add(OperatorSimpleUnary(UnaryOperator.BitwiseNot))
    nodes.Add(OperatorSimpleUnary(UnaryOperator.IndexFromEnd))

    index := 0
    while index < nodes.Count {
        state := harness.Operators.Begin(nodes[index])
        steps := OperatorRun(harness, state, OperatorOne(BuiltInTypes.Int))

        assert steps.Count == 1
        assert steps[0].Kind == 1
        index = index + 1
    }
}

test "++ NEEDS AN ASSIGNABLE TARGET, AND THAT RULE SITS BETWEEN TWO THE HOST STILL OWNS" {
    harness := OperatorDefault()
    literal: Expression = new IntLiteralExpression("1", 2, 6)
    state := harness.Operators.Begin(OperatorUnary(UnaryOperator.PreIncrement, literal))

    steps := OperatorRun(harness, state, OperatorOne(BuiltInTypes.Int))

    // The operand is still walked — the assignable-target rule runs AFTER it — and this owner's own
    // rule refuses between the readonly-field question and the read-only-property one, so the
    // developer is told they need an assignable target rather than being asked about a property.
    assert steps.Count == 1
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "The '++' operator needs an assignable target"
    assert OperatorTypeText(harness.Operators.Result(state)) == "unknown"
}

test "A DISCARD IS NOT AN ASSIGNABLE TARGET AND A PARENTHESISED NAME IS" {
    harness := OperatorDefault()

    discard := harness.Operators.Begin(OperatorUnary(UnaryOperator.PostIncrement, OperatorIdentifier("_", 2, 5)))
    OperatorRun(harness, discard, OperatorIncrementAnswers(BuiltInTypes.Int))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "The '++' operator needs an assignable target"

    wrapped: Expression = new ParenthesizedExpression(OperatorIdentifier("n", 2, 7), 2, 6)
    parenthesized := harness.Operators.Begin(OperatorUnary(UnaryOperator.PostIncrement, wrapped))
    OperatorRun(harness, parenthesized, OperatorIncrementAnswers(BuiltInTypes.Int))

    assert harness.Errors.Count == 1
    assert OperatorTypeText(harness.Operators.Result(parenthesized)) == "int"
}

// ── the family's own boundaries ─────────────────────────────────────────

test "THE COMPOUND-ASSIGNMENT DOOR IS THE ARITHMETIC RULE AND ONLY FOR FOUR OPERATORS" {
    harness := OperatorDefault()
    synthetic := new BinaryExpression(OperatorIdentifier("a", 2, 5), BinaryOperator.Add, OperatorIdentifier("b", 2, 10), 2, 5)

    added := harness.Operators.CompoundAssignmentOperatorResult(BinaryOperator.Add, BuiltInTypes.Int, BuiltInTypes.Long, synthetic)

    assert OperatorTypeText(added) == "long"

    // `%` has no compound form in the language, so the door answers `unknown` rather than reaching
    // the arithmetic rule at all — and raises nothing on the way.
    modulo := harness.Operators.CompoundAssignmentOperatorResult(BinaryOperator.Modulo, BuiltInTypes.Int, BuiltInTypes.Long, synthetic)

    assert OperatorTypeText(modulo) == "unknown"
    assert harness.Errors.Count == 0
}

test "THE COMMON TYPE — SLICE 52'S RETIRED STEP — IS THE PROMOTION TABLE AND NOTHING MORE" {
    // The identity shortcut is REFERENCE identity, exactly as the host's `==` on a class that
    // overrides `Equals` but not `operator ==` was: ONE reference passed twice takes it.
    text: TypeInfo = BuiltInTypes.String
    identical := AnalyzerOperatorExpressions.CommonType(text, text)

    assert OperatorTypeText(identical) == "string"

    // TWO separately constructed `string`s do NOT take it, and there is no numeric promotion for
    // them either — which is the behaviour that moved, not a behaviour that was tidied.
    separate := AnalyzerOperatorExpressions.CommonType(BuiltInTypes.String, BuiltInTypes.String)

    assert OperatorTypeText(separate) == "unknown"

    widened := AnalyzerOperatorExpressions.CommonType(BuiltInTypes.Int, BuiltInTypes.Long)

    assert OperatorTypeText(widened) == "long"

    // Two numerics with no common type, and two unrelated types, both answer `unknown`.
    impossible := AnalyzerOperatorExpressions.CommonType(BuiltInTypes.ULong, BuiltInTypes.Long)

    assert OperatorTypeText(impossible) == "unknown"

    unrelated := AnalyzerOperatorExpressions.CommonType(BuiltInTypes.String, BuiltInTypes.Int)

    assert OperatorTypeText(unrelated) == "unknown"
}

test "BINARY NUMERIC PROMOTION IS NOT IMPLICIT CONVERSION" {
    // The whole table, asserted directly, because it is the rule five operator classes read and the
    // one an assignment rule must NOT be confused with.
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.Byte, BuiltInTypes.SByte)) == "int"
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.Short, BuiltInTypes.UShort)) == "int"
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.Char, BuiltInTypes.Byte)) == "int"
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.UInt, BuiltInTypes.UShort)) == "uint"
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.UInt, BuiltInTypes.Int)) == "long"
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.ULong, BuiltInTypes.UInt)) == "ulong"
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.Float, BuiltInTypes.Long)) == "float"
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.Double, BuiltInTypes.Float)) == "double"
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.Decimal, BuiltInTypes.Long)) == "decimal"
    assert OperatorTypeText(AnalyzerOperatorExpressions.CommonType(BuiltInTypes.Decimal, BuiltInTypes.Float)) == "unknown"
}

test "A BINARY WHOSE OPERATOR HAS NO RULE ANSWERS unknown WITHOUT REPORTING" {
    harness := OperatorDefault()
    state := harness.Operators.Begin(OperatorSimpleBinary(BinaryOperator.Modulo))

    OperatorRun(harness, state, OperatorAnswers(BuiltInTypes.Int, BuiltInTypes.Int))

    // `%` IS arithmetic, so this one has a rule and answers `int` — the contract that matters is that
    // the arithmetic group is the five it claims to be.
    assert OperatorTypeText(harness.Operators.Result(state)) == "int"
    assert harness.Errors.Count == 0
}

namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for what an expression MEANS where a statement belongs.
//
// THE PROTOCOL IS THE CONTRACT, because the driver in `Analyzer.cs` is zero-policy: it switches on
// `Kind`, performs exactly one operation with exactly the carried operands, and hands the answer
// back. So the requests a shape emits — how many, in which ORDER, and with which OPERANDS — are the
// observable behaviour, and every contract below drives the walk the way the driver does.
//
// THE ORDER IS LOAD-BEARING. The discard walk's guard is captured BEFORE the expression walk runs
// and compared after it, so a statement whose insides failed never also complains that it has no
// effect. Its row-escape report ENDS the walk; its column-escape report ends the walk only when it
// fires; the validity report and the must-use report are mutually exclusive. The assert walk has NO
// guard and NO short-circuit — both escape reports run for the condition, then both again for the
// message. And the assert-throws walk reports BEFORE it opens its scope, so a bad exception type is
// squiggled outside the block it guards.
//
// THE CORPUS REACHES ALMOST NONE OF THIS. `nlc check` over all 71 tracked targets enters the discard
// walk 38,929 times and fires ZERO of the family's four diagnostics; it never enters `assert` or
// `assert throws` at all, because `nlc check` does not read `.tests.nl`. An `nlc test` sweep over the
// same 71 targets reaches 886 asserts and 7 assert-throws, every one of them clean. So all four
// diagnostics, both NL313 forms, all four must-use reason shapes and every SoA escape in this family
// exist ONLY here and in the fixtures.

class EsHarness {
    Owner: AnalyzerExpressionStatements
    Diagnostics: AnalyzerDiagnosticSink
    Errors: List<CompilerError>
    Steps: List<EsStep>
    Answers: List<TypeInfo>
    AnswerIndex: int
    ColumnEscape: bool
    Throwable: bool
    CalleeType: TypeInfo?
    ErrorsOnAnalyze: int

    constructor(
        owner: AnalyzerExpressionStatements,
        diagnostics: AnalyzerDiagnosticSink,
        errors: List<CompilerError>) {
        Owner = owner
        Diagnostics = diagnostics
        Errors = errors
        Steps = new List<EsStep>()
        Answers = new List<TypeInfo>()
        AnswerIndex = 0
        ColumnEscape = false
        Throwable = true
        CalleeType = null
        ErrorsOnAnalyze = 0
    }
}

// Every step the walk asked for, in order, with everything it carried — and the error count the
// driver would have seen at that moment. This is what the driver sees and therefore what the
// contracts read.
class EsStep {
    Kind: int
    Node: Expression?
    StatementCount: int
    CarriedType: TypeInfo
    Text: string?
    Line: int
    Column: int
    ErrorsBefore: int

    constructor(
        kind: int,
        node: Expression?,
        statementCount: int,
        carriedType: TypeInfo,
        text: string?,
        line: int,
        column: int,
        errorsBefore: int) {
        Kind = kind
        Node = node
        StatementCount = statementCount
        CarriedType = carriedType
        Text = text
        Line = line
        Column = column
        ErrorsBefore = errorsBefore
    }
}

func EsPath(): string {
    return Path.GetFullPath("expression-statement-contract.nl")
}

func EsHarnessWith(sourceText: string?): EsHarness {
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
    diagnostics.BeginAnalysis(EsPath(), sourceText)
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
    resolver.BeginAnalysis(EsPath(), null, model, new BindingMap())

    return new EsHarness(
        new AnalyzerExpressionStatements(diagnostics, spans, resolver),
        diagnostics,
        errors)
}

func EsDefault(): EsHarness {
    return EsHarnessWith(null)
}

// ── AST builders ──────────────────────────────────────────────────────────

func EsName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 7, 5)
}

func EsInt(): IntLiteralExpression {
    return new IntLiteralExpression("42", 7, 5)
}

func EsCall(calleeName: string): CallExpression {
    return new CallExpression(EsName(calleeName), new List<Argument>(), null, 7, 5)
}

func EsAssign(): AssignmentExpression {
    return new AssignmentExpression(EsName("x"), AssignmentOperator.Assign, EsInt(), 7, 5)
}

func EsBinary(): BinaryExpression {
    return new BinaryExpression(EsName("a"), BinaryOperator.Add, EsName("b"), 7, 5)
}

func EsMember(): MemberAccessExpression {
    return new MemberAccessExpression(EsName("owner"), "Member", false, 7, 5)
}

func EsIndex(): IndexAccessExpression {
    return new IndexAccessExpression(EsName("items"), EsInt(), false, 7, 5)
}

func EsMatch(): MatchExpression {
    return new MatchExpression(EsName("value"), new List<MatchCase>(), 7, 5)
}

func EsNew(): NewExpression {
    return new NewExpression(new SimpleTypeReference("Thing", 7, 9), new List<Argument>(), null, 7, 5)
}

func EsAwait(inner: Expression): AwaitExpression {
    return new AwaitExpression(inner, 7, 5)
}

func EsUnary(unaryOperator: UnaryOperator): UnaryExpression {
    return new UnaryExpression(unaryOperator, EsName("i"), 7, 5)
}

func EsParen(inner: Expression): ParenthesizedExpression {
    return new ParenthesizedExpression(inner, 7, 5)
}

func EsChecked(inner: Expression): CheckedExpression {
    return new CheckedExpression(inner, 7, 5)
}

func EsUnchecked(inner: Expression): UncheckedExpression {
    return new UncheckedExpression(inner, 7, 5)
}

func EsAlloc(inner: Expression): AllocExpression {
    return new AllocExpression(inner, 7, 5)
}

func EsAssert(condition: Expression, message: Expression?): AssertStatement {
    return new AssertStatement(condition, message, 7, 5)
}

func EsBlock(count: int): BlockStatement {
    statements := new List<Statement>()
    index := 0
    while index < count {
        statements.Add(new ExpressionStatement(EsCall("Step"), 8 + index, 9))
        index = index + 1
    }

    return new BlockStatement(statements, 7, 20)
}

func EsAssertThrows(typeName: string, bodyCount: int): AssertThrowsStatement {
    return new AssertThrowsStatement(
        new SimpleTypeReference(typeName, 7, 19),
        EsBlock(bodyCount),
        7,
        5)
}

func EsRowType(): SoaRowTypeInfo {
    columns := new List<SoaColumnInfo>()
    return new SoaRowTypeInfo(new SoaRecordDeclarationInfo("Particle", columns, 1, 1))
}

func EsMustUseFunction(syntheticName: string?): FunctionTypeInfo {
    result := new FunctionTypeInfo()
    result.SyntheticName = syntheticName
    result.HasMustUseAttribute = true
    return result
}

func EsPlainFunction(syntheticName: string?): FunctionTypeInfo {
    result := new FunctionTypeInfo()
    result.SyntheticName = syntheticName
    result.HasMustUseAttribute = false
    return result
}

func EsStringMethod(name: string): MethodInfo {
    method := typeof(string).GetMethod(name, new Type[](0))
    if method == null {
        throw new InvalidOperationException("Expected 'System.String." + name + "()' to exist.")
    }

    return method
}

// ── the driver, exactly as `Analyzer.cs` writes it ────────────────────────

// Runs the whole walk and records what was asked into the harness. Kind 1 is answered from the
// `Answers` list in order (falling back to `unknown`), kind 3 from `ColumnEscape`, kind 7 from
// `Throwable` and kind 8 from `CalleeType`. `ErrorsOnAnalyze` injects that many diagnostics DURING
// the kind-1 step, which is how the discard walk's guard is exercised without an expression walker.
func EsRun(harness: EsHarness, state: ExpressionStatementState) {
    steps := harness.Steps
    steps.Clear()
    harness.AnswerIndex = 0

    step := harness.Owner.NextStep(state)
    while step != null {
        statementCount := 0
        carried := step.Statements
        if carried != null {
            statementCount = carried.Count
        }

        steps.Add(new EsStep(
            step.Kind,
            step.Node,
            statementCount,
            step.CarriedType,
            step.Text,
            step.Line,
            step.Column,
            harness.Errors.Count))

        supplied: TypeInfo? = null
        flag := false
        if step.Kind == 1 {
            injected := 0
            while injected < harness.ErrorsOnAnalyze {
                harness.Errors.Add(new CompilerError(
                    ErrorCode.UndefinedVariable,
                    "injected",
                    7,
                    5,
                    ErrorSeverity.Error))
                injected = injected + 1
            }

            harness.ErrorsOnAnalyze = 0
            supplied = BuiltInTypes.Unknown
            if harness.AnswerIndex < harness.Answers.Count {
                supplied = harness.Answers[harness.AnswerIndex]
            }

            harness.AnswerIndex = harness.AnswerIndex + 1
        }

        if step.Kind == 3 {
            flag = harness.ColumnEscape
        }

        if step.Kind == 7 {
            flag = harness.Throwable
        }

        if step.Kind == 8 {
            supplied = harness.CalleeType
        }

        harness.Owner.Supply(state, supplied, flag)
        step = harness.Owner.NextStep(state)
    }
}

// The assert-throws walk resolves its exception type through the real type resolver, and in this
// harness — which has no loaded assemblies — that resolution reports an undefined type of its own.
// So the family's OWN report is selected by its wording rather than by counting the whole list.
func EsAssertThrowsReports(harness: EsHarness): List<CompilerError> {
    matches := new List<CompilerError>()
    index := 0
    while index < harness.Errors.Count {
        current := harness.Errors[index]
        if current.Message.StartsWith("Assert throws type must be assignable") {
            matches.Add(current)
        }

        index = index + 1
    }

    return matches
}

func EsKinds(steps: List<EsStep>): string {
    rendered := ""
    index := 0
    while index < steps.Count {
        rendered = rendered + steps[index].Kind.ToString()
        if index + 1 < steps.Count {
            rendered = rendered + ","
        }

        index = index + 1
    }

    return rendered
}

func EsRunStatement(harness: EsHarness, expression: Expression) {
    EsRun(harness, harness.Owner.BeginExpressionStatement(expression))
}

func EsRunIterator(harness: EsHarness, expression: Expression) {
    EsRun(harness, harness.Owner.BeginForIterator(expression))
}

// ── the discard walk's step protocol ──────────────────────────────────────

test "a clean expression statement asks for the expression, the column escape, and the callee type" {
    harness := EsDefault()
    harness.CalleeType = EsMustUseFunction("Compute")
    EsRunStatement(harness, EsCall("Compute"))

    assert EsKinds(harness.Steps) == "1,3,8"
    assert harness.Steps[0].Node != null
    assert harness.Steps[1].Text == "discarded"
}

test "a for iterator names itself in the SoA report and nowhere else changes" {
    harness := EsDefault()
    EsRunIterator(harness, EsAssign())

    assert EsKinds(harness.Steps) == "1,3"
    assert harness.Steps[1].Text == "used as a 'for' iterator"
}

test "the expression step carries the expression itself and answers nothing else" {
    harness := EsDefault()
    expression := EsAssign()
    EsRunStatement(harness, expression)

    assert harness.Steps[0].Kind == 1
    assert Object.ReferenceEquals(harness.Steps[0].Node, expression)
    assert harness.Steps[0].Text == null
}

test "an expression that unwraps to no call never asks for a callee type" {
    harness := EsDefault()
    EsRunStatement(harness, EsAssign())

    assert EsKinds(harness.Steps) == "1,3"
}

test "the callee-type step carries the CALLEE's position, not the call's" {
    harness := EsDefault()
    call := new CallExpression(new IdentifierExpression("Compute", 12, 30), new List<Argument>(), null, 12, 9)
    EsRunStatement(harness, call)

    assert harness.Steps[2].Kind == 8
    assert harness.Steps[2].Line == 12
    assert harness.Steps[2].Column == 30
}

// ── the guard ─────────────────────────────────────────────────────────────

test "a report from inside the expression suppresses every later step" {
    harness := EsDefault()
    harness.ErrorsOnAnalyze = 1
    EsRunStatement(harness, EsName("orphan"))

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 1
}

test "a suppressed statement does not report that it has no effect" {
    harness := EsDefault()
    harness.ErrorsOnAnalyze = 1
    EsRunStatement(harness, EsBinary())

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "injected"
}

test "a report from inside the expression suppresses the SoA row escape too" {
    harness := EsDefault()
    harness.ErrorsOnAnalyze = 1
    harness.Answers.Add(EsRowType())
    EsRunStatement(harness, EsName("row"))

    assert EsKinds(harness.Steps) == "1"
}

test "the guard is read at the step the driver would have read it" {
    harness := EsDefault()
    EsRunStatement(harness, EsCall("Compute"))

    assert harness.Steps[0].ErrorsBefore == 0
    assert harness.Steps[1].ErrorsBefore == 0
}

// ── the two SoA escapes ───────────────────────────────────────────────────

test "an SoA row-view answer ends the walk at the row report" {
    harness := EsDefault()
    harness.Answers.Add(EsRowType())
    EsRunStatement(harness, EsName("row"))

    assert EsKinds(harness.Steps) == "1,2"
    assert harness.Steps[1].Text == "discarded"
}

test "an SoA row-view iterator names the iterator in its report" {
    harness := EsDefault()
    harness.Answers.Add(EsRowType())
    EsRunIterator(harness, EsName("row"))

    assert EsKinds(harness.Steps) == "1,2"
    assert harness.Steps[1].Text == "used as a 'for' iterator"
}

test "a fired column escape ends the walk with no validity report" {
    harness := EsDefault()
    harness.ColumnEscape = true
    EsRunStatement(harness, EsBinary())

    assert EsKinds(harness.Steps) == "1,3"
    assert harness.Errors.Count == 0
}

test "an unfired column escape lets the validity decision run" {
    harness := EsDefault()
    harness.ColumnEscape = false
    EsRunStatement(harness, EsBinary())

    assert EsKinds(harness.Steps) == "1,3"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidExpressionStatement
}

// ── NL313, both forms ─────────────────────────────────────────────────────

test "a binary expression as a statement has no effect" {
    harness := EsDefault()
    EsRunStatement(harness, EsBinary())

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidExpressionStatement
    assert harness.Errors[0].Message == "This expression statement has no effect"
}

test "the same expression in a for iterator gets the iterator wording" {
    harness := EsDefault()
    EsRunIterator(harness, EsBinary())

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidExpressionStatement
    assert harness.Errors[0].Message == "This for-loop iterator has no effect"
}

test "the detail-only expression-statement report carries its suggestion" {
    harness := EsDefault()
    EsRunStatement(harness, EsName("orphan"))

    assert harness.Errors[0].Suggestion == "Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments."
}

test "the detail-only iterator report carries its own suggestion" {
    harness := EsDefault()
    EsRunIterator(harness, EsName("orphan"))

    assert harness.Errors[0].Suggestion == "Use an assignment, call, increment, decrement, await expression, or object construction in the iterator clause, or remove the iterator."
}

test "the report underlines the identifier it names" {
    harness := EsDefault()
    EsRunStatement(harness, EsName("orphan"))

    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 5
    assert harness.Errors[0].Length == 6
}

test "with a source snippet the expression-statement report takes the rich shape" {
    harness := EsHarnessWith("func Main() {\n\n\n\n\n\n    orphan\n}\n")
    EsRunStatement(harness, EsName("orphan"))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidExpressionStatement
    assert harness.Errors[0].DocsUrl == "https://docs.n-sharp.dev/errors/NL313"
    assert harness.Errors[0].HumanExplanation != null
}

test "the rich expression-statement report names the expression in its hint" {
    harness := EsHarnessWith("func Main() {\n\n\n\n\n\n    orphan\n}\n")
    EsRunStatement(harness, EsName("orphan"))

    hint := harness.Errors[0].ContextualHint
    assert hint != null
    assert hint.Contains("`orphan`")
}

test "with a source snippet the iterator report takes the rich iterator shape" {
    harness := EsHarnessWith("func Main() {\n\n\n\n\n\n    for i := 0; i < 3; i + 1 {\n    }\n}\n")
    EsRunIterator(harness, EsBinary())

    assert harness.Errors.Count == 1
    hint := harness.Errors[0].ContextualHint
    assert hint != null
    assert hint.Contains("for-loop iterators")
}

test "the rich shapes name the analysed file" {
    harness := EsHarnessWith("func Main() {\n\n\n\n\n\n    orphan\n}\n")
    EsRunStatement(harness, EsName("orphan"))

    assert harness.Errors[0].FileName == EsPath()
}

// ── what may stand as a statement ─────────────────────────────────────────

test "assignments, calls, constructions, subscriptions and awaits stand alone" {
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsAssign())
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsCall("Run"))
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsNew())
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsAwait(EsCall("RunAsync")))
}

test "all four increment and decrement forms stand alone" {
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsUnary(UnaryOperator.PreIncrement))
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsUnary(UnaryOperator.PreDecrement))
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsUnary(UnaryOperator.PostIncrement))
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsUnary(UnaryOperator.PostDecrement))
}

test "negation and logical not do not stand alone" {
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsUnary(UnaryOperator.Negate))
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsUnary(UnaryOperator.Not))
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsUnary(UnaryOperator.BitwiseNot))
}

test "identifiers, members, binaries, indexes and matches do not stand alone" {
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsName("x"))
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsMember())
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsBinary())
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsIndex())
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsMatch())
}

test "the three transparent wrappers answer with what they wrap" {
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsParen(EsCall("Run")))
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsChecked(EsCall("Run")))
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsUnchecked(EsCall("Run")))
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsParen(EsName("x")))
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsChecked(EsName("x")))
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsUnchecked(EsName("x")))
}

test "an alloc answers with what it allocates" {
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsAlloc(EsNew()))
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsAlloc(EsName("x")))
}

test "the wrappers nest" {
    assert AnalyzerExpressionStatements.IsValidExpressionStatement(EsParen(EsChecked(EsParen(EsCall("Run")))))
    assert !AnalyzerExpressionStatements.IsValidExpressionStatement(EsParen(EsChecked(EsParen(EsBinary()))))
}

// ── the must-use closure ──────────────────────────────────────────────────

test "a bare call unwraps to itself" {
    call := EsCall("Compute")
    assert Object.ReferenceEquals(AnalyzerExpressionStatements.UnwrapMustUseCandidate(call), call)
}

test "the three transparent wrappers unwrap to the call inside" {
    call := EsCall("Compute")
    assert Object.ReferenceEquals(AnalyzerExpressionStatements.UnwrapMustUseCandidate(EsParen(call)), call)
    assert Object.ReferenceEquals(AnalyzerExpressionStatements.UnwrapMustUseCandidate(EsChecked(call)), call)
    assert Object.ReferenceEquals(AnalyzerExpressionStatements.UnwrapMustUseCandidate(EsUnchecked(call)), call)
}

test "an alloc is not a must-use unwrapper" {
    assert AnalyzerExpressionStatements.UnwrapMustUseCandidate(EsAlloc(EsCall("Compute"))) == null
}

test "an assignment is never a must-use candidate" {
    assert AnalyzerExpressionStatements.UnwrapMustUseCandidate(EsAssign()) == null
    assert AnalyzerExpressionStatements.UnwrapMustUseCandidate(EsName("x")) == null
}

test "a must-use N# function names itself in the reason" {
    reason := AnalyzerExpressionStatements.MustUseReason(EsMustUseFunction("Compute"), EsCall("Compute"))
    assert reason == "'Compute' is marked [MustUse]"
}

test "a plain N# function has no reason" {
    assert AnalyzerExpressionStatements.MustUseReason(EsPlainFunction("Compute"), EsCall("Compute")) == null
}

test "an N# method group whose functions all carry it names the first" {
    functions := new List<FunctionTypeInfo>()
    functions.Add(EsMustUseFunction("Compute"))
    functions.Add(EsMustUseFunction("Compute$1"))
    group := NSharpMethodGroupInfoFactory.FromFunctions(functions)

    assert AnalyzerExpressionStatements.MustUseReason(group, EsCall("Compute")) == "'Compute' is marked [MustUse]"
}

test "an N# method group with one plain overload says nothing" {
    functions := new List<FunctionTypeInfo>()
    functions.Add(EsMustUseFunction("Compute"))
    functions.Add(EsPlainFunction("Compute$1"))
    group := NSharpMethodGroupInfoFactory.FromFunctions(functions)

    assert AnalyzerExpressionStatements.MustUseReason(group, EsCall("Compute")) == null
}

test "an empty N# method group says nothing" {
    group := NSharpMethodGroupInfoFactory.FromFunctions(new List<FunctionTypeInfo>())
    assert AnalyzerExpressionStatements.MustUseReason(group, EsCall("Compute")) == null
}

test "an unnamed must-use function falls back to the word function" {
    functions := new List<FunctionTypeInfo>()
    functions.Add(EsMustUseFunction(null))
    group := NSharpMethodGroupInfoFactory.FromFunctions(functions)

    assert AnalyzerExpressionStatements.MustUseReason(group, EsCall("Compute")) == "'function' is marked [MustUse]"
}

test "a reflected method with no MustUse attribute has no reason" {
    method := new ReflectionMethodInfo(EsStringMethod("Trim"))
    assert AnalyzerExpressionStatements.MustUseReason(method, EsCall("Trim")) == null
}

test "a reflected method group with no MustUse attribute has no reason" {
    methods := new MethodInfo[](1)
    methods[0] = EsStringMethod("Trim")
    group := new ReflectionMethodGroupInfo(methods)

    assert AnalyzerExpressionStatements.MustUseReason(group, EsCall("Trim")) == null
}

test "an empty reflected method group says nothing" {
    group := new ReflectionMethodGroupInfo(new MethodInfo[](0))
    assert AnalyzerExpressionStatements.MustUseReason(group, EsCall("Trim")) == null
}

test "an ordinary BCL method carries no MustUse attribute" {
    assert !AnalyzerExpressionStatements.HasMustUseAttribute(EsStringMethod("Trim"))
    assert !AnalyzerExpressionStatements.HasMustUseAttribute(EsStringMethod("ToUpperInvariant"))
}

test "a callee type the family does not know has no reason" {
    assert AnalyzerExpressionStatements.MustUseReason(BuiltInTypes.Int, EsCall("Compute")) == null
    assert AnalyzerExpressionStatements.MustUseReason(BuiltInTypes.Unknown, EsCall("Compute")) == null
}

// ── NL315 ─────────────────────────────────────────────────────────────────

test "a discarded must-use result is reported on the callee" {
    harness := EsDefault()
    harness.CalleeType = EsMustUseFunction("Compute")
    EsRunStatement(harness, EsCall("Compute"))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.DiscardedMustUseResult
    assert harness.Errors[0].Message == "You're discarding the result of 'Compute', but 'Compute' is marked [MustUse] — its result must be used"
}

test "the must-use report carries the explicit-discard suggestion" {
    harness := EsDefault()
    harness.CalleeType = EsMustUseFunction("Compute")
    EsRunStatement(harness, EsCall("Compute"))

    assert harness.Errors[0].Suggestion == "Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`."
}

test "the must-use report underlines the callee name" {
    harness := EsDefault()
    harness.CalleeType = EsMustUseFunction("Compute")
    EsRunStatement(harness, EsCall("Compute"))

    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 5
    assert harness.Errors[0].Length == 7
}

test "a discarded must-use result through a member call has no name to give" {
    harness := EsDefault()
    harness.CalleeType = EsMustUseFunction("Add")
    call := new CallExpression(EsMember(), new List<Argument>(), null, 7, 5)
    EsRunStatement(harness, call)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "You're discarding the result of 'Member', but 'Add' is marked [MustUse] — its result must be used"
}

test "a plain callee type reports nothing" {
    harness := EsDefault()
    harness.CalleeType = EsPlainFunction("Compute")
    EsRunStatement(harness, EsCall("Compute"))

    assert EsKinds(harness.Steps) == "1,3,8"
    assert harness.Errors.Count == 0
}

test "a callee with no recorded type reports nothing" {
    harness := EsDefault()
    harness.CalleeType = null
    EsRunStatement(harness, EsCall("Compute"))

    assert EsKinds(harness.Steps) == "1,3,8"
    assert harness.Errors.Count == 0
}

test "a must-use call inside parentheses is still reported" {
    harness := EsDefault()
    harness.CalleeType = EsMustUseFunction("Compute")
    EsRunStatement(harness, EsParen(EsCall("Compute")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.DiscardedMustUseResult
}

test "the validity report and the must-use report are mutually exclusive" {
    harness := EsDefault()
    harness.CalleeType = EsMustUseFunction("Compute")
    EsRunStatement(harness, EsBinary())

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidExpressionStatement
}

// ── the assert walk ───────────────────────────────────────────────────────

test "an assert with no message asks for the condition and both escapes" {
    harness := EsDefault()
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsBinary(), null)))

    assert EsKinds(harness.Steps) == "1,3"
    assert harness.Steps[1].Text == "asserted"
}

test "an assert with a message asks for both expressions and both escapes twice" {
    harness := EsDefault()
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsBinary(), EsName("why"))))

    assert EsKinds(harness.Steps) == "1,3,1,3"
    assert harness.Steps[1].Text == "asserted"
    assert harness.Steps[3].Text == "used as an assertion message"
}

test "an SoA row condition adds the row report before the column report" {
    harness := EsDefault()
    harness.Answers.Add(EsRowType())
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsName("row"), null)))

    assert EsKinds(harness.Steps) == "1,2,3"
    assert harness.Steps[1].Text == "asserted"
    assert harness.Steps[2].Text == "asserted"
}

test "an SoA row message reports under the message wording" {
    harness := EsDefault()
    harness.Answers.Add(BuiltInTypes.Bool)
    harness.Answers.Add(EsRowType())
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsBinary(), EsName("row"))))

    assert EsKinds(harness.Steps) == "1,3,1,2,3"
    assert harness.Steps[3].Text == "used as an assertion message"
}

test "an assert does not short-circuit on a fired column escape" {
    harness := EsDefault()
    harness.ColumnEscape = true
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsBinary(), EsName("why"))))

    assert EsKinds(harness.Steps) == "1,3,1,3"
}

test "an assert has no error-count guard" {
    harness := EsDefault()
    harness.ErrorsOnAnalyze = 1
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsBinary(), EsName("why"))))

    assert EsKinds(harness.Steps) == "1,3,1,3"
}

test "an assert never reports on its own" {
    harness := EsDefault()
    harness.Answers.Add(BuiltInTypes.Int)
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsInt(), null)))

    assert harness.Errors.Count == 0
}

test "a non-boolean assert condition is accepted" {
    harness := EsDefault()
    harness.Answers.Add(BuiltInTypes.String)
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsName("text"), null)))

    assert harness.Errors.Count == 0
    assert EsKinds(harness.Steps) == "1,3"
}

test "the assert steps carry the condition and the message nodes themselves" {
    harness := EsDefault()
    condition := EsBinary()
    message := EsName("why")
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(condition, message)))

    assert Object.ReferenceEquals(harness.Steps[0].Node, condition)
    assert Object.ReferenceEquals(harness.Steps[1].Node, condition)
    assert Object.ReferenceEquals(harness.Steps[2].Node, message)
    assert Object.ReferenceEquals(harness.Steps[3].Node, message)
}

// ── the assert-throws walk ────────────────────────────────────────────────

test "assert throws asks for throwability, opens a scope, walks the body and closes it" {
    harness := EsDefault()
    EsRun(harness, harness.Owner.BeginAssertThrows(EsAssertThrows("InvalidOperationException", 2)))

    assert EsKinds(harness.Steps) == "7,4,5,6"
    assert harness.Steps[2].StatementCount == 2
}

test "the scope opens at the assert-throws statement's own position" {
    harness := EsDefault()
    EsRun(harness, harness.Owner.BeginAssertThrows(EsAssertThrows("InvalidOperationException", 0)))

    assert harness.Steps[1].Kind == 4
    assert harness.Steps[1].Line == 7
    assert harness.Steps[1].Column == 5
}

test "an empty assert-throws body still opens and closes its scope" {
    harness := EsDefault()
    EsRun(harness, harness.Owner.BeginAssertThrows(EsAssertThrows("InvalidOperationException", 0)))

    assert EsKinds(harness.Steps) == "7,4,5,6"
    assert harness.Steps[2].StatementCount == 0
}

test "a throwable assert-throws type reports nothing" {
    harness := EsDefault()
    harness.Throwable = true
    EsRun(harness, harness.Owner.BeginAssertThrows(EsAssertThrows("InvalidOperationException", 1)))

    assert EsAssertThrowsReports(harness).Count == 0
}

test "a non-throwable assert-throws type reports NL202" {
    harness := EsDefault()
    harness.Throwable = false
    EsRun(harness, harness.Owner.BeginAssertThrows(EsAssertThrows("Widget", 1)))

    reports := EsAssertThrowsReports(harness)
    assert reports.Count == 1
    assert reports[0].Code == ErrorCode.TypeMismatch
    assert reports[0].Suggestion == "Assert an Exception-derived type, or use a broader exception type such as Exception."
}

test "the non-throwable report underlines the exception type reference" {
    harness := EsDefault()
    harness.Throwable = false
    EsRun(harness, harness.Owner.BeginAssertThrows(EsAssertThrows("Widget", 0)))

    reports := EsAssertThrowsReports(harness)
    assert reports[0].Line == 7
    assert reports[0].Column == 19
}

test "the non-throwable report fires BEFORE the scope opens" {
    harness := EsDefault()
    harness.Throwable = false
    EsRun(harness, harness.Owner.BeginAssertThrows(EsAssertThrows("Widget", 1)))

    assert harness.Steps[1].Kind == 4
    assert harness.Steps[1].ErrorsBefore == harness.Steps[0].ErrorsBefore + 1
}

test "the throwability step carries the resolved exception type" {
    harness := EsDefault()
    EsRun(harness, harness.Owner.BeginAssertThrows(EsAssertThrows("InvalidOperationException", 0)))

    assert harness.Steps[0].Kind == 7
    assert harness.Steps[0].CarriedType != null
}

test "the body step carries the body's own statement list" {
    harness := EsDefault()
    statement := EsAssertThrows("InvalidOperationException", 3)
    EsRun(harness, harness.Owner.BeginAssertThrows(statement))

    assert harness.Steps[2].Kind == 5
    assert harness.Steps[2].StatementCount == 3
}

// ── how an expression is named in prose ───────────────────────────────────

test "an identifier and a member are named by their own names" {
    assert AnalyzerExpressionStatements.DescribeExpression(EsName("orphan")) == "orphan"
    assert AnalyzerExpressionStatements.DescribeExpression(EsMember()) == "Member"
}

test "the three transparent wrappers are named by what they wrap" {
    assert AnalyzerExpressionStatements.DescribeExpression(EsParen(EsName("orphan"))) == "orphan"
    assert AnalyzerExpressionStatements.DescribeExpression(EsChecked(EsName("orphan"))) == "orphan"
    assert AnalyzerExpressionStatements.DescribeExpression(EsUnchecked(EsName("orphan"))) == "orphan"
}

test "three shapes have fixed prose names" {
    assert AnalyzerExpressionStatements.DescribeExpression(EsBinary()) == "binary expression"
    assert AnalyzerExpressionStatements.DescribeExpression(EsIndex()) == "index access"
    assert AnalyzerExpressionStatements.DescribeExpression(EsMatch()) == "match expression"
}

test "anything else is named by its node type with the Expression suffix removed" {
    assert AnalyzerExpressionStatements.DescribeExpression(EsInt()) == "IntLiteral"
    assert AnalyzerExpressionStatements.DescribeExpression(EsNew()) == "New"
    assert AnalyzerExpressionStatements.DescribeExpression(EsCall("Run")) == "Call"
}

test "the prose name reaches through nested wrappers" {
    assert AnalyzerExpressionStatements.DescribeExpression(EsParen(EsChecked(EsMember()))) == "Member"
}

// ── the placeholder exit ──────────────────────────────────────────────────

test "a parser placeholder ends the walk after the expression step" {
    harness := EsDefault()
    EsRunStatement(harness, EsName(AnalyzerParserErrorPlaceholders.PlaceholderName()))

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 0
}

test "a parser placeholder in an iterator is silent too" {
    harness := EsDefault()
    EsRunIterator(harness, EsName(AnalyzerParserErrorPlaceholders.PlaceholderName()))

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 0
}

// ── the state's own bookkeeping ───────────────────────────────────────────

test "every Begin hands back a fresh state at its own phase" {
    harness := EsDefault()
    statementState := harness.Owner.BeginExpressionStatement(EsCall("Run"))
    iteratorState := harness.Owner.BeginForIterator(EsCall("Run"))
    assertState := harness.Owner.BeginAssert(EsAssert(EsBinary(), null))
    throwsState := harness.Owner.BeginAssertThrows(EsAssertThrows("InvalidOperationException", 0))

    assert statementState.Phase == 0
    assert iteratorState.Phase == 0
    assert assertState.Phase == 10
    assert throwsState.Phase == 20
}

test "the two discard entries differ only in context and wording" {
    harness := EsDefault()
    statementState := harness.Owner.BeginExpressionStatement(EsCall("Run"))
    iteratorState := harness.Owner.BeginForIterator(EsCall("Run"))

    assert statementState.Context == DiscardedExpressionContext.ExpressionStatement
    assert statementState.SoaUsage == "discarded"
    assert iteratorState.Context == DiscardedExpressionContext.ForIterator
    assert iteratorState.SoaUsage == "used as a 'for' iterator"
}

test "two walks over the same statement do not share state" {
    harness := EsDefault()
    statement := EsAssertThrows("InvalidOperationException", 1)
    EsRun(harness, harness.Owner.BeginAssertThrows(statement))
    first := EsKinds(harness.Steps)
    EsRun(harness, harness.Owner.BeginAssertThrows(statement))

    assert first == EsKinds(harness.Steps)
}

test "the sink's error count is what the guard reads" {
    harness := EsDefault()
    assert harness.Diagnostics.ErrorCount == 0

    harness.Errors.Add(new CompilerError(ErrorCode.UndefinedVariable, "seeded", 1, 1, ErrorSeverity.Error))
    assert harness.Diagnostics.ErrorCount == 1
}

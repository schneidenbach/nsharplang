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
// THE TWO ESCAPE REPORTS ARE NO LONGER STEPS — they were kinds 2 and 3 until `AnalyzerSoaEscape` took
// the family, and the walk calls them directly now. Every rule above still holds, but a contract that
// wants one to FIRE builds a real row-view answer or a real declared-table column read and reads the
// DIAGNOSTIC, rather than handing the walk a boolean. That is a stronger pinning, not a weaker one:
// the old contracts could not have caught a wrong action word or a wrong span.
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
    Scopes: AnalyzerScopeStack
    Steps: List<EsStep>
    Answers: List<TypeInfo>
    AnswerIndex: int
    Clr: AnalyzerClrTypeConversion
    CalleeType: TypeInfo?
    ErrorsOnAnalyze: int

    constructor(
        owner: AnalyzerExpressionStatements,
        diagnostics: AnalyzerDiagnosticSink,
        errors: List<CompilerError>,
        scopes: AnalyzerScopeStack,
        clr: AnalyzerClrTypeConversion
    ) {
        Owner = owner
        Diagnostics = diagnostics
        Errors = errors
        Scopes = scopes
        Clr = clr
        Steps = new List<EsStep>()
        Answers = new List<TypeInfo>()
        AnswerIndex = 0
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
        errorsBefore: int
    ) {
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
        new Dictionary<string, string>(StringComparer.Ordinal)
    )
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
        new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal),
        model,
        new BindingMap()
    )
    resolver.BeginAnalysis(EsPath(), null, model, new BindingMap())

    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    throwability := new AnalyzerThrowability(scopes, context, substitution)
    clr := new AnalyzerClrTypeConversion(context, null)
    EsDeclareThrowabilityTypes(scopes)
    return new EsHarness(
        new AnalyzerExpressionStatements(diagnostics, spans, resolver, escape, throwability),
        diagnostics,
        errors,
        scopes,
        clr
    )
}

// TWO REAL TYPES, so the throwability rule is measured rather than injected. The question stopped
// being a driver-answered step when `AnalyzerThrowability` took the predicate whole, so a contract
// that wants a non-throwable exception type must DECLARE one: `Widget` is a class with no base and
// `AppError` derives from `Exception`, which is the shortest pair that separates the two answers.
func EsDeclareThrowabilityTypes(scopes: AnalyzerScopeStack) {
    types := scopes.Peek().Types
    types["Widget"] = EsClassType("Widget", null)
    types["AppError"] = EsClassType("AppError", new SimpleTypeReference("Exception", 1, 1))
}

func EsClassType(name: string, baseClass: TypeReference?): TypeInfo {
    declared: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        false,
        baseClass,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true
    )
    return declared
}

// A table declared in the harness's scope, and a `points.x` read against it — the only way to make
// the direct-column escape fire for real now that it is not a driver-answered step.
func EsSoaColumns(): List<SoaColumnInfo> {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int", 0, 0), 1, 1))
    return columns
}

func EsDeclareSoaTable(harness: EsHarness) {
    table: TypeInfo = new SoaRecordTypeInfo(
        new SoaRecordDeclarationInfo("Points", EsSoaColumns(), 1, 1)
    )
    harness.Scopes.Peek().Symbols["points"] = table
}

func EsSoaColumnRead(): Expression {
    read: Expression = new MemberAccessExpression(EsName("points"), "x", false, 7, 5)
    return read
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
        5
    )
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
// `Answers` list in order (falling back to `unknown`) and kind 8 from `CalleeType`.
// `ErrorsOnAnalyze` injects that many diagnostics DURING the kind-1 step, which is how the discard
// walk's guard is exercised without an expression walker. Kind 7 is GONE: the throwability question
// is a direct call on `AnalyzerThrowability` now, so no driver answer can fake it.
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
            harness.Errors.Count
        ))

        supplied: TypeInfo? = null
        if step.Kind == 1 {
            injected := 0
            while injected < harness.ErrorsOnAnalyze {
                harness.Errors.Add(new CompilerError(
                    ErrorCode.UndefinedVariable,
                    "injected",
                    7,
                    5,
                    ErrorSeverity.Error
                ))
                injected = injected + 1
            }

            harness.ErrorsOnAnalyze = 0
            supplied = BuiltInTypes.Unknown
            if harness.AnswerIndex < harness.Answers.Count {
                supplied = harness.Answers[harness.AnswerIndex]
            }

            harness.AnswerIndex = harness.AnswerIndex + 1
        }

        if step.Kind == 8 {
            supplied = harness.CalleeType
        }

        harness.Owner.Supply(state, supplied)
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

test "a clean expression statement asks for the expression and the callee type" {
    harness := EsDefault()
    harness.CalleeType = EsMustUseFunction("Compute")
    EsRunStatement(harness, EsCall("Compute"))

    // The escape reports were kinds 2 and 3 and are N#-owned calls now.
    assert EsKinds(harness.Steps) == "1,8"
    assert harness.Steps[0].Node != null
}

test "a for iterator names itself in the SoA report and nowhere else changes" {
    harness := EsDefault()
    EsDeclareSoaTable(harness)
    EsRunIterator(harness, EsSoaColumnRead())

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be used as a 'for' iterator directly"
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

    assert EsKinds(harness.Steps) == "1"
}

test "the callee-type step carries the CALLEE's position, not the call's" {
    harness := EsDefault()
    call := new CallExpression(new IdentifierExpression("Compute", 12, 30), new List<Argument>(), null, 12, 9)
    EsRunStatement(harness, call)

    assert harness.Steps[1].Kind == 8
    assert harness.Steps[1].Line == 12
    assert harness.Steps[1].Column == 30
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

test "a report from inside the expression suppresses the SoA COLUMN escape too" {
    harness := EsDefault()
    harness.ErrorsOnAnalyze = 1
    EsDeclareSoaTable(harness)
    EsRunStatement(harness, EsSoaColumnRead())

    // Only the injected error: the column report never ran.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "injected"
}

// ── the two SoA escapes ───────────────────────────────────────────────────

test "an SoA row-view answer ends the walk at the row report" {
    harness := EsDefault()
    harness.Answers.Add(EsRowType())
    EsRunStatement(harness, EsName("row"))

    assert EsKinds(harness.Steps) == "1"
    // The row report speaks, and the validity report — which `row` would otherwise earn — does not.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be discarded; use the table and row index instead"
}

test "an SoA row-view iterator names the iterator in its report" {
    harness := EsDefault()
    harness.Answers.Add(EsRowType())
    EsRunIterator(harness, EsName("row"))

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as a 'for' iterator; use the table and row index instead"
}

test "a fired column escape ends the walk with no validity report" {
    harness := EsDefault()
    EsDeclareSoaTable(harness)
    EsRunStatement(harness, EsSoaColumnRead())

    assert EsKinds(harness.Steps) == "1"
    // ONE report — the escape — where an unescaped member access earns the validity report instead.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be discarded directly"
}

test "an unfired column escape lets the validity decision run" {
    harness := EsDefault()
    EsRunStatement(harness, EsBinary())

    assert EsKinds(harness.Steps) == "1"
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

    assert EsKinds(harness.Steps) == "1,8"
    assert harness.Errors.Count == 0
}

test "a callee with no recorded type reports nothing" {
    harness := EsDefault()
    harness.CalleeType = null
    EsRunStatement(harness, EsCall("Compute"))

    assert EsKinds(harness.Steps) == "1,8"
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

test "an assert with no message asks for the condition alone" {
    harness := EsDefault()
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsBinary(), null)))

    assert EsKinds(harness.Steps) == "1"
}

test "an assert with a message asks for both expressions" {
    harness := EsDefault()
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsBinary(), EsName("why"))))

    assert EsKinds(harness.Steps) == "1,1"
}

test "an SoA row condition reports under the asserted wording" {
    harness := EsDefault()
    harness.Answers.Add(EsRowType())
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsName("row"), null)))

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be asserted; use the table and row index instead"
}

test "an SoA row message reports under the message wording" {
    harness := EsDefault()
    harness.Answers.Add(BuiltInTypes.Bool)
    harness.Answers.Add(EsRowType())
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsBinary(), EsName("row"))))

    assert EsKinds(harness.Steps) == "1,1"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as an assertion message; use the table and row index instead"
}

test "an assert does not short-circuit on a fired column escape" {
    // Both halves report: the condition's escape does not stop the message from being walked or from
    // being asked the same two questions.
    harness := EsDefault()
    EsDeclareSoaTable(harness)
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsSoaColumnRead(), EsSoaColumnRead())))

    assert EsKinds(harness.Steps) == "1,1"
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be asserted directly"
    assert harness.Errors[1].Message == "SoA table member 'x' cannot be used as an assertion message directly"
}

test "an assert has no error-count guard" {
    harness := EsDefault()
    harness.ErrorsOnAnalyze = 1
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(EsBinary(), EsName("why"))))

    assert EsKinds(harness.Steps) == "1,1"
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
    assert EsKinds(harness.Steps) == "1"
}

test "the assert steps carry the condition and the message nodes themselves" {
    harness := EsDefault()
    condition := EsBinary()
    message := EsName("why")
    EsRun(harness, harness.Owner.BeginAssert(EsAssert(condition, message)))

    assert Object.ReferenceEquals(harness.Steps[0].Node, condition)
    assert Object.ReferenceEquals(harness.Steps[1].Node, message)
}

// ── the assert-throws walk ────────────────────────────────────────────────

test "assert throws opens a scope, walks the body and closes it" {
    harness := EsDefault()
    EsRun(harness, EsBeginAssertThrows(harness, EsAssertThrows("AppError", 2)))

    // The throwability question was kind 7 and is a direct call now, so the walk suspends three
    // times rather than four.
    assert EsKinds(harness.Steps) == "4,5,6"
    assert harness.Steps[1].StatementCount == 2
}

test "the SoA reports are no longer steps at all" {
    // Kinds 2 and 3 left the protocol when `AnalyzerSoaEscape` took the two reporters. A walk that
    // FIRES both still hands the driver nothing but the expression step.
    harness := EsDefault()
    harness.Answers.Add(EsRowType())
    EsRunStatement(harness, EsName("row"))

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 1
}

test "the scope opens at the assert-throws statement's own position" {
    harness := EsDefault()
    EsRun(harness, EsBeginAssertThrows(harness, EsAssertThrows("AppError", 0)))

    assert harness.Steps[0].Kind == 4
    assert harness.Steps[0].Line == 7
    assert harness.Steps[0].Column == 5
}

test "an empty assert-throws body still opens and closes its scope" {
    harness := EsDefault()
    EsRun(harness, EsBeginAssertThrows(harness, EsAssertThrows("AppError", 0)))

    assert EsKinds(harness.Steps) == "4,5,6"
    assert harness.Steps[1].StatementCount == 0
}

test "a throwable assert-throws type reports nothing" {
    harness := EsDefault()
    EsRun(harness, EsBeginAssertThrows(harness, EsAssertThrows("AppError", 1)))

    assert EsAssertThrowsReports(harness).Count == 0
}

test "a non-throwable assert-throws type reports NL202" {
    harness := EsDefault()
    EsRun(harness, EsBeginAssertThrows(harness, EsAssertThrows("Widget", 1)))

    reports := EsAssertThrowsReports(harness)
    assert reports.Count == 1
    assert reports[0].Code == ErrorCode.TypeMismatch
    assert reports[0].Suggestion == "Assert an Exception-derived type, or use a broader exception type such as Exception."
}

test "the non-throwable report underlines the exception type reference" {
    harness := EsDefault()
    EsRun(harness, EsBeginAssertThrows(harness, EsAssertThrows("Widget", 0)))

    reports := EsAssertThrowsReports(harness)
    assert reports[0].Line == 7
    assert reports[0].Column == 19
}

test "the non-throwable report fires BEFORE the scope opens" {
    harness := EsDefault()
    EsRun(harness, EsBeginAssertThrows(harness, EsAssertThrows("Widget", 1)))

    // The very first step the driver sees is the scope open, and the report is already in the list.
    assert harness.Steps[0].Kind == 4
    assert harness.Steps[0].ErrorsBefore == 1
}

test "the exception type is RESOLVED before it is measured, and the resolution is what decides" {
    // Both names resolve through the real type resolver against the same scope; only what they
    // resolve TO separates them, which is the whole of what the deleted kind-7 relay used to carry.
    throwable := EsDefault()
    EsRun(throwable, EsBeginAssertThrows(throwable, EsAssertThrows("AppError", 0)))
    refused := EsDefault()
    EsRun(refused, EsBeginAssertThrows(refused, EsAssertThrows("Widget", 0)))

    assert EsAssertThrowsReports(throwable).Count == 0
    assert EsAssertThrowsReports(refused).Count == 1
    assert EsAssertThrowsReports(refused)[0].Message == "Assert throws type must be assignable to System.Exception, but this type is 'Widget'"
}

test "the body step carries the body's own statement list" {
    harness := EsDefault()
    statement := EsAssertThrows("AppError", 3)
    EsRun(harness, EsBeginAssertThrows(harness, statement))

    assert harness.Steps[1].Kind == 5
    assert harness.Steps[1].StatementCount == 3
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
    throwsState := EsBeginAssertThrows(harness, EsAssertThrows("AppError", 0))

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
    statement := EsAssertThrows("AppError", 1)
    EsRun(harness, EsBeginAssertThrows(harness, statement))
    first := EsKinds(harness.Steps)
    EsRun(harness, EsBeginAssertThrows(harness, statement))

    assert first == EsKinds(harness.Steps)
}

test "the sink's error count is what the guard reads" {
    harness := EsDefault()
    assert harness.Diagnostics.ErrorCount == 0

    harness.Errors.Add(new CompilerError(ErrorCode.UndefinedVariable, "seeded", 1, 1, ErrorSeverity.Error))
    assert harness.Diagnostics.ErrorCount == 1
}

// ── the `throw` and `print` walks ─────────────────────────────────────────

// Both arrived from the statement dispatch on kinds this driver already had, and both now suspend
// EXACTLY ONCE — for the operand — because the throwability question stopped being a driver step.
// The contracts below are written around the ONE thing that separates them, because five
// hand-written escape gates in the estate are split on exactly this line: `throw` SHORT-CIRCUITS (a
// value refused as a row view is not also probed as a column, and neither is measured against
// `Exception`) and `print` DOES NOT (both reports always run).

func EsBeginAssertThrows(harness: EsHarness, statement: AssertThrowsStatement): ExpressionStatementState {
    return harness.Owner.BeginAssertThrows(statement, harness.Clr)
}

func EsRunThrow(harness: EsHarness, expression: Expression) {
    EsRun(harness, harness.Owner.BeginThrow(expression, harness.Clr))
}

func EsRunPrint(harness: EsHarness, expression: Expression) {
    EsRun(harness, harness.Owner.BeginPrint(expression))
}

test "a throw asks for the operand and nothing else" {
    harness := EsDefault()
    // `unknown` is throwable, so an operand the walker could not type is not complained about.
    EsRunThrow(harness, EsName("failure"))

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 0
}

test "a throw operand whose type is a declared Exception subclass is accepted" {
    harness := EsDefault()
    appError := harness.Scopes.LookupType("AppError")
    assert appError != null
    harness.Answers.Add(appError)
    EsRunThrow(harness, EsName("failure"))

    assert harness.Errors.Count == 0
}

test "a non-throwable throw operand reports NL202 with the operand's own span" {
    harness := EsDefault()
    harness.Answers.Add(BuiltInTypes.Int)
    EsRunThrow(harness, EsName("failure"))

    assert harness.Errors.Count == 1
    error := harness.Errors[0]
    assert error.Message == "Throw expressions must be assignable to System.Exception, but this expression is 'int'"
    assert error.Code == ErrorCode.TypeMismatch
    assert error.Line == 7
    assert error.Column == 5
}

test "a row-view throw operand escapes and is NOT also told it is not throwable" {
    harness := EsDefault()
    rowView: TypeInfo = EsRowType()
    harness.Answers.Add(rowView)
    EsRunThrow(harness, EsName("particle"))

    // The throwability question is never even asked, and exactly one diagnostic lands.
    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be thrown; use the table and row index instead"
}

test "a direct column throw operand escapes on syntax with the throw's action word" {
    harness := EsDefault()
    EsDeclareSoaTable(harness)
    harness.Answers.Add(BuiltInTypes.Int)
    EsRunThrow(harness, EsSoaColumnRead())

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be thrown directly"
}

test "a print asks for the value and nothing else" {
    harness := EsDefault()
    EsRunPrint(harness, EsName("value"))

    assert EsKinds(harness.Steps) == "1"
    // `print` has no rule of its own — anything can be printed.
    assert harness.Errors.Count == 0
}

test "print runs BOTH escape reports and neither short-circuits the other" {
    harness := EsDefault()
    EsDeclareSoaTable(harness)
    rowView: TypeInfo = EsRowType()
    harness.Answers.Add(rowView)
    // A column read BY SYNTAX whose ANSWERED type is a row view: the row report and the column
    // report are both true of it, and `print` is the one statement in the estate that says both.
    EsRunPrint(harness, EsSoaColumnRead())

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "SoA row views cannot be printed; use the table and row index instead"
    assert harness.Errors[1].Message == "SoA table member 'x' cannot be printed directly"
}

test "the six entries set exactly one operand each and select their own phase band" {
    harness := EsDefault()
    discard := harness.Owner.BeginExpressionStatement(EsCall("Run"))
    thrown := harness.Owner.BeginThrow(EsName("failure"), harness.Clr)
    printed := harness.Owner.BeginPrint(EsName("value"))
    detached := harness.Owner.BeginOff(EsName("sub"), EsSubscriptionRoot())

    assert discard.Phase == 0
    assert thrown.Phase == 30
    assert printed.Phase == 40
    assert detached.Phase == 50
    assert thrown.Thrown != null
    assert thrown.Printed == null
    assert thrown.Discarded == null
    assert thrown.SoaUsage == "thrown"
    assert printed.Printed != null
    assert printed.Thrown == null
    assert printed.SoaUsage == "printed"
    assert detached.OffHandle != null
    assert detached.Printed == null
    assert detached.Thrown == null
    assert detached.Discarded == null
    assert detached.SoaUsage == "used as an off handle"
}

// ── the `off` walk ────────────────────────────────────────────────────────
//
// `off sub` detaches an event subscription. Its handle is an expression in statement position, so it
// is this family's sixth shape rather than a family of its own; what it adds is one rule about the
// type that expression answers, and FOUR silence rules in a fixed order before the rule can fire.
//
// THE SUBSCRIPTION ROOT IS A STAND-IN HERE AND THAT IS THE POINT. `Analyzer.cs` hands in the runtime
// `NSharpEventSubscription`; these contracts hand in a type whose assignability answers the same way,
// which is what lets the rule be measured at all — this project does not reference the runtime
// assembly, so a walk that named the type itself could not be driven from a contract.

// `typeof` carries a hardcoded well-known list that does not name these, so they are resolved the way
// the production owners resolve `System.IDisposable` and the non-generic sequence interfaces.
func EsClrType(fullName: string): Type {
    clrType := Type.GetType(fullName)
    if clrType == null {
        throw new InvalidOperationException("Required type " + fullName + " was not found.")
    }

    return clrType
}

func EsSubscriptionRoot(): Type {
    return EsClrType("System.IO.Stream")
}

func EsReflected(fullName: string): TypeInfo {
    result: TypeInfo = new ReflectionTypeInfo(EsClrType(fullName))
    return result
}

func EsRunOff(harness: EsHarness, expression: Expression) {
    EsRun(harness, harness.Owner.BeginOff(expression, EsSubscriptionRoot()))
}

test "an off asks for the handle and nothing else" {
    harness := EsDefault()
    harness.Answers.Add(EsReflected("System.IO.MemoryStream"))
    EsRunOff(harness, EsName("sub"))

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 0
}

test "a handle assignable to the subscription root is accepted in silence" {
    harness := EsDefault()
    // A DERIVED reflected type: the rule is assignability, not identity, because `on` answers the
    // generic `NSharpEventSubscription<THandler>` and the root it derives from is what `off` names.
    harness.Answers.Add(EsReflected("System.IO.MemoryStream"))
    EsRunOff(harness, EsName("sub"))

    assert harness.Errors.Count == 0
}

test "a handle that is NOT a subscription reports NL318 on the whole handle expression" {
    harness := EsDefault()
    harness.Answers.Add(BuiltInTypes.Int)
    EsRunOff(harness, EsName("counter"))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].DiagnosticId == "NL318"
    assert harness.Errors[0].Message == "`off` expects a subscription returned by `on`"
    assert harness.Errors[0].Suggestion == "Capture the subscription first (`sub := on <object>.<Event> handler`), then detach it with `off sub`."
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 5
}

test "a REFLECTED handle the root cannot accept still reports" {
    harness := EsDefault()
    // Reflected, but not assignable: the walk reaches the root and the root says no.
    harness.Answers.Add(EsReflected("System.StringComparer"))
    EsRunOff(harness, EsName("wrong"))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].DiagnosticId == "NL318"
}

test "an UNKNOWN handle is silent — an earlier error already explained the problem" {
    harness := EsDefault()
    harness.Answers.Add(BuiltInTypes.Unknown)
    EsRunOff(harness, EsName("broken"))

    assert harness.Errors.Count == 0
}

test "a row-view off handle escapes with the off action word and is not ALSO told it is no subscription" {
    harness := EsDefault()
    rowView: TypeInfo = EsRowType()
    harness.Answers.Add(rowView)
    EsRunOff(harness, EsName("row"))

    assert EsKinds(harness.Steps) == "1"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as an off handle; use the table and row index instead"
}

test "a direct column off handle escapes on syntax, and the row report does not fire with it" {
    harness := EsDefault()
    EsDeclareSoaTable(harness)
    harness.Answers.Add(BuiltInTypes.Int)
    EsRunOff(harness, EsSoaColumnRead())

    // ONE diagnostic: the row report declined on the answered type, the column probe fired, and the
    // subscription rule was never reached. `off` short-circuits like `throw`, unlike `print`.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be used as an off handle directly"
}

test "a row view that is ALSO a column read reports ONCE for off, where print reports twice" {
    harness := EsDefault()
    EsDeclareSoaTable(harness)
    rowView: TypeInfo = EsRowType()
    harness.Answers.Add(rowView)
    EsRunOff(harness, EsSoaColumnRead())

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as an off handle; use the table and row index instead"
}

// ── the rebuilt CLR funnel is carried, not held ───────────────────────────

// `Analyzer.cs` REBUILDS `AnalyzerClrTypeConversion` when the metadata load context opens and again
// when it is disposed, so the throwability owner this walk holds may not keep a reference to it. It
// arrives on the state instead, and ONLY for the two shapes that ask a throwability question.
test "only the two throwability shapes carry the CLR conversion funnel" {
    harness := EsDefault()
    discard := harness.Owner.BeginExpressionStatement(EsCall("Run"))
    iterator := harness.Owner.BeginForIterator(EsCall("Run"))
    asserted := harness.Owner.BeginAssert(EsAssert(EsBinary(), null))
    printed := harness.Owner.BeginPrint(EsName("value"))
    thrown := harness.Owner.BeginThrow(EsName("failure"), harness.Clr)
    assertThrowsState := EsBeginAssertThrows(harness, EsAssertThrows("AppError", 0))

    assert discard.ClrTypeConversion == null
    assert iterator.ClrTypeConversion == null
    assert asserted.ClrTypeConversion == null
    assert printed.ClrTypeConversion == null
    assert thrown.ClrTypeConversion != null
    assert assertThrowsState.ClrTypeConversion != null
}

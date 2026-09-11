namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT A TEST, A `setup`, A `teardown` AND A CONSTRUCTOR MEAN.
//
// The twelve members this replaces were all `private` in `Analyzer.cs` and nothing named any of
// them, so their behaviour was pinned only through whatever end-to-end diagnostic a broken
// declaration happened to produce. This is their first DIRECT pinning, and it is written around the
// six things this family is easy to get wrong.
//
// (1) THE INJECTED NAMES CARRY THE `setup`'s POSITION, NOT THE TEST'S. A hover over a setup-declared
// name inside a test must point at the `setup` line. A walk that declared them at the test's
// position would silently move every one of those hovers.
//
// (2) THE TWO SCAFFOLDING RULES ARE WRITTEN DIFFERENTLY AND THE DIFFERENCE IS SHIPPED. A duplicate
// `setup` does not collect its symbols; a duplicate `teardown` sets its flag unconditionally
// because it has nothing to collect. Levelling them would change which `setup`'s names a file gets.
//
// (3) A TABLE ROW'S CONSTANT CHECK ALWAYS RUNS, AND ONLY THEN IS A SURPLUS VALUE SKIPPED. The two
// conditions are `||`-ordered in that order, so a non-constant value in a too-wide row is STILL
// told it is not constant.
//
// (4) A `typeof` ROW VALUE IS MEASURED BY THE SoA ROW RULE FIRST AND IS THEN SILENT. If that rule
// spoke, the value is refused without a second sentence about the same token.
//
// (5) THE EXPECTED-TYPE BRACKET AROUND A ROW VALUE IS THE OWNER'S AND IS LEFT BEFORE THE COMPARISON.
// The value is analysed UNDER its column's type; the comparison that follows is not part of that
// analysis and must not see the slot.
//
// (6) A CONSTRUCTOR'S DEFINITE-ASSIGNMENT CHECK IS GATED ON *BOTH* A DECLARING CLASS AND NO
// INITIALIZER. A constructor that chains has handed the duty to the one it chains to.
class DeclarationWalkHarness {
    Walkers: AnalyzerDeclarationWalkers
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Errors: List<CompilerError>
    Assignability: AnalyzerAssignability
    Model: SemanticModel

    constructor(walkers: AnalyzerDeclarationWalkers, ambient: AnalyzerAmbientContext, scopes: AnalyzerScopeStack, errors: List<CompilerError>, assignability: AnalyzerAssignability, model: SemanticModel) {
        Walkers = walkers
        Ambient = ambient
        Scopes = scopes
        Errors = errors
        Assignability = assignability
        Model = model
    }
}

// One replayed step, with the scope DEPTH and the error count AS THE STEP WAS HANDED OUT, which is
// what pins the window each operation happens in rather than only the operation itself.
class DeclarationWalkStep {
    Kind: int
    Name: string?
    CarriedType: string
    HasNode: bool
    HasBody: bool
    HasStatements: bool
    ParameterCount: int
    Line: int
    Column: int
    Depth: int
    ErrorsBefore: int
    InConstructor: bool

    constructor(kind: int, name: string?, carriedType: string, hasNode: bool, hasBody: bool, hasStatements: bool, parameterCount: int, line: int, column: int, depth: int, errorsBefore: int, inConstructor: bool) {
        Kind = kind
        Name = name
        CarriedType = carriedType
        HasNode = hasNode
        HasBody = hasBody
        HasStatements = hasStatements
        ParameterCount = parameterCount
        Line = line
        Column = column
        Depth = depth
        ErrorsBefore = errorsBefore
        InConstructor = inConstructor
    }
}

func DeclWalkPath(): string {
    return Path.GetFullPath("declaration-walkers-contract.nl")
}

func DeclWalkHarnessOf(): DeclarationWalkHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(DeclWalkPath(), null)
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
    resolver.BeginAnalysis(DeclWalkPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    definiteAssignment := new AnalyzerDefiniteAssignment(diagnostics, resolver)
    walkers := new AnalyzerDeclarationWalkers(diagnostics, spans, resolver, ambient, definiteAssignment)
    return new DeclarationWalkHarness(walkers, ambient, scopes, errors, assignability, model)
}

func DeclWalkTypeText(candidate: TypeInfo?): string {
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

// The driver, exactly as `Analyzer.cs` writes it. The scope operations are performed FOR REAL, so
// the depth recorded on every step is the depth the analyzer would have been at. Kinds 5 and 8
// record the body rather than re-entering the statement dispatch, which is the one thing a contract
// cannot replay.
func DeclWalkRun(harness: DeclarationWalkHarness, state: DeclarationWalkState, valueAnswer: TypeInfo?): List<DeclarationWalkStep> {
    steps := new List<DeclarationWalkStep>()
    step := harness.Walkers.NextStep(state)
    while step != null {
        parameters := step.Parameters
        parameterCount := 0
        if parameters != null {
            parameterCount = parameters.Count
        }

        steps.Add(new DeclarationWalkStep(step.Kind, step.Name, DeclWalkTypeText(step.CarriedType), step.Node != null, step.Body != null, step.Statements != null, parameterCount, step.Line, step.Column, harness.Scopes.Count, harness.Errors.Count, harness.Ambient.InConstructor))

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
            answer = valueAnswer
        }

        harness.Walkers.Supply(state, answer)
        step = harness.Walkers.NextStep(state)
    }

    return steps
}

func DeclWalkTranscript(steps: List<DeclarationWalkStep>): string {
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

// ── AST shapes ────────────────────────────────────────────────────────────────

func DeclWalkStatements(): List<Statement> {
    return new List<Statement>()
}

func DeclWalkBlock(statements: List<Statement>): BlockStatement {
    return new BlockStatement(statements, 3, 12)
}

func DeclWalkEmptyBlock(): BlockStatement {
    return DeclWalkBlock(DeclWalkStatements())
}

func DeclWalkParams(): List<Parameter> {
    return new List<Parameter>()
}

func DeclWalkParam(parameters: List<Parameter>, name: string, typeName: string, line: int, column: int) {
    parameters.Add(new Parameter(name, new SimpleTypeReference(typeName, line, column), null, false, ParameterModifier.None, null, line, column, false, null))
}

func DeclWalkTest(parameters: List<Parameter>?, cases: List<List<Expression>>?): TestDeclaration {
    return new TestDeclaration("a test", DeclWalkEmptyBlock(), parameters, cases, null, 3, 1)
}

func DeclWalkRows(): List<List<Expression>> {
    return new List<List<Expression>>()
}

func DeclWalkRow(rows: List<List<Expression>>, values: List<Expression>) {
    rows.Add(values)
}

func DeclWalkValues(): List<Expression> {
    return new List<Expression>()
}

func DeclWalkVariable(name: string, typeReference: TypeReference?, initializer: Expression?, line: int, column: int): VariableDeclarationStatement {
    return new VariableDeclarationStatement(name, typeReference, initializer, VariableKind.Let, line, column)
}

// ── the file's test scaffolding ───────────────────────────────────────────────

test "a lone setup collects its top-level variables, in written order, at their own positions" {
    harness := DeclWalkHarnessOf()
    statements := DeclWalkStatements()
    statements.Add(DeclWalkVariable("count", new SimpleTypeReference("int", 4, 9), null, 4, 5))
    statements.Add(DeclWalkVariable("label", null, new StringLiteralExpression("hi", 5, 14), 5, 5))
    declarations := new List<Declaration>()
    declarations.Add(new SetupDeclaration(DeclWalkBlock(statements), 3, 1))

    harness.Walkers.CollectTestScaffolding(declarations)
    teardown := new TeardownDeclaration(DeclWalkEmptyBlock(), 9, 1)
    steps := DeclWalkRun(harness, harness.Walkers.BeginTeardown(teardown, harness.Assignability), null)

    assert harness.Errors.Count == 0
    assert DeclWalkTranscript(steps) == "2 3 4 3 4 5 6"
    assert steps[1].Name == "count"
    assert steps[1].CarriedType == "int"
    assert steps[1].Line == 4
    assert steps[1].Column == 5
    assert steps[3].Name == "label"
    assert steps[3].CarriedType == "string"
    assert steps[3].Line == 5
}

test "a SECOND setup is reported and does NOT replace the first one's symbols" {
    harness := DeclWalkHarnessOf()
    first := DeclWalkStatements()
    first.Add(DeclWalkVariable("kept", new SimpleTypeReference("int", 4, 9), null, 4, 5))
    second := DeclWalkStatements()
    second.Add(DeclWalkVariable("dropped", new SimpleTypeReference("int", 8, 9), null, 8, 5))
    declarations := new List<Declaration>()
    declarations.Add(new SetupDeclaration(DeclWalkBlock(first), 3, 1))
    declarations.Add(new SetupDeclaration(DeclWalkBlock(second), 7, 1))

    harness.Walkers.CollectTestScaffolding(declarations)
    steps := DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(null, null), harness.Assignability), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.DuplicateDeclaration
    assert harness.Errors[0].Message == "Only one setup block is allowed per test file"
    assert harness.Errors[0].Line == 7
    assert DeclWalkTranscript(steps) == "2 3 4 5 6"
    assert steps[1].Name == "kept"
}

test "a SECOND teardown is reported" {
    harness := DeclWalkHarnessOf()
    declarations := new List<Declaration>()
    declarations.Add(new TeardownDeclaration(DeclWalkEmptyBlock(), 3, 1))
    declarations.Add(new TeardownDeclaration(DeclWalkEmptyBlock(), 7, 1))

    harness.Walkers.CollectTestScaffolding(declarations)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Only one teardown block is allowed per test file"
    assert harness.Errors[0].Line == 7
}

test "the symbol list is REPLACED by each collection pass" {
    harness := DeclWalkHarnessOf()
    statements := DeclWalkStatements()
    statements.Add(DeclWalkVariable("first", new SimpleTypeReference("int", 4, 9), null, 4, 5))
    withSetup := new List<Declaration>()
    withSetup.Add(new SetupDeclaration(DeclWalkBlock(statements), 3, 1))

    harness.Walkers.CollectTestScaffolding(withSetup)
    harness.Walkers.CollectTestScaffolding(new List<Declaration>())
    steps := DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(null, null), harness.Assignability), null)

    assert DeclWalkTranscript(steps) == "2 5 6"
}

test "only the setup block's TOP-LEVEL variables are the file's" {
    harness := DeclWalkHarnessOf()
    nested := DeclWalkStatements()
    nested.Add(DeclWalkVariable("inner", new SimpleTypeReference("int", 5, 13), null, 5, 9))
    statements := DeclWalkStatements()
    statements.Add(DeclWalkBlock(nested))
    declarations := new List<Declaration>()
    declarations.Add(new SetupDeclaration(DeclWalkBlock(statements), 3, 1))

    harness.Walkers.CollectTestScaffolding(declarations)
    steps := DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(null, null), harness.Assignability), null)

    assert DeclWalkTranscript(steps) == "2 5 6"
}

// ── the setup symbol's type ───────────────────────────────────────────────────

test "an initializer's SHAPE decides an unannotated setup symbol's type" {
    harness := DeclWalkHarnessOf()

    assert DeclWalkTypeText(harness.Walkers.InferSetupInitializerType(new IntLiteralExpression("1", 4, 9))) == "int"
    assert DeclWalkTypeText(harness.Walkers.InferSetupInitializerType(new FloatLiteralExpression("1.0", 4, 9))) == "double"
    assert DeclWalkTypeText(harness.Walkers.InferSetupInitializerType(new CharLiteralExpression("a", 4, 9))) == "char"
    assert DeclWalkTypeText(harness.Walkers.InferSetupInitializerType(new StringLiteralExpression("s", 4, 9))) == "string"
    assert DeclWalkTypeText(harness.Walkers.InferSetupInitializerType(new BoolLiteralExpression(true, 4, 9))) == "bool"
    assert DeclWalkTypeText(harness.Walkers.InferSetupInitializerType(new ParenthesizedExpression(new IntLiteralExpression("1", 4, 9), 4, 9))) == "int"
    assert DeclWalkTypeText(harness.Walkers.InferSetupInitializerType(new CheckedExpression(new IntLiteralExpression("1", 4, 9), 4, 9))) == "int"
    assert DeclWalkTypeText(harness.Walkers.InferSetupInitializerType(new UncheckedExpression(new IntLiteralExpression("1", 4, 9), 4, 9))) == "int"
}

test "an ARRAY literal answers an array of its FIRST element's shape, and an empty one answers nothing" {
    harness := DeclWalkHarnessOf()
    elements := new List<Expression>()
    elements.Add(new IntLiteralExpression("1", 4, 9))
    elements.Add(new StringLiteralExpression("s", 4, 12))

    assert DeclWalkTypeText(harness.Walkers.InferSetupInitializerType(new ArrayLiteralExpression(elements, false, 4, 9))) == "int[]"
    assert harness.Walkers.InferSetupInitializerType(new ArrayLiteralExpression(new List<Expression>(), false, 4, 9)) == null
}

test "a shape with no usable type falls back to OBJECT rather than to unknown" {
    harness := DeclWalkHarnessOf()
    // A call has no shape this pass reads, so the declared name still exists and is `object`.
    variable := DeclWalkVariable("value", null, new CallExpression(new IdentifierExpression("f", 4, 9), new List<Argument>(), null, 4, 9), 4, 5)

    assert DeclWalkTypeText(harness.Walkers.ResolveSetupSymbolType(variable)) == "object"
}

test "a WRITTEN type wins over the initializer's shape" {
    harness := DeclWalkHarnessOf()
    variable := DeclWalkVariable("value", new SimpleTypeReference("string", 4, 9), new IntLiteralExpression("1", 4, 18), 4, 5)

    assert DeclWalkTypeText(harness.Walkers.ResolveSetupSymbolType(variable)) == "string"
}

// ── the test walk ─────────────────────────────────────────────────────────────

test "a plain test opens a function scope, walks its statements and closes it" {
    harness := DeclWalkHarnessOf()

    steps := DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(null, null), harness.Assignability), null)

    assert DeclWalkTranscript(steps) == "2 5 6"
    assert steps[0].Line == 3
    assert steps[0].Column == 1
    assert steps[1].HasStatements
    assert steps[0].Depth == 1
    assert steps[1].Depth == 2
    assert steps[2].Depth == 2
}

test "a table header is VALIDATED before any of its names exists, then declared and recorded" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 3, 12)
    DeclWalkParam(parameters, "label", "string", 3, 24)

    steps := DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(parameters, null), harness.Assignability), null)

    assert DeclWalkTranscript(steps) == "2 7 3 4 3 4 5 6"
    assert steps[1].ParameterCount == 2
    assert steps[2].Name == "value"
    assert steps[2].CarriedType == "int"
    assert steps[2].Line == 3
    assert steps[2].Column == 12
    assert steps[4].Name == "label"
    assert steps[4].CarriedType == "string"
    assert steps[4].Column == 24
}

test "a header parameter with no position of its own is declared at the TEST's" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 0, 0)

    steps := DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(parameters, null), harness.Assignability), null)

    assert steps[2].Line == 3
    assert steps[2].Column == 1
}

test "a row whose width does not match the header is reported ONCE, at the TEST" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 3, 12)
    values := DeclWalkValues()
    values.Add(new IntLiteralExpression("1", 5, 5))
    values.Add(new IntLiteralExpression("2", 5, 8))
    rows := DeclWalkRows()
    DeclWalkRow(rows, values)

    steps := DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(parameters, rows), harness.Assignability), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message == "This test case has 2 values but the table header declares 1 parameters — each row must have exactly one value per parameter"
    assert harness.Errors[0].Line == 3
    assert harness.Errors[0].Column == 1
    // The FIRST value is still checked; the surplus one has no column and is not.
    assert DeclWalkTranscript(steps) == "2 7 3 4 1 5 6"
}

test "each row value is analysed once, in order, and both rows are walked" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 3, 12)
    rows := DeclWalkRows()
    firstRow := DeclWalkValues()
    firstRow.Add(new IntLiteralExpression("1", 5, 5))
    DeclWalkRow(rows, firstRow)
    secondRow := DeclWalkValues()
    secondRow.Add(new IntLiteralExpression("2", 6, 5))
    DeclWalkRow(rows, secondRow)

    steps := DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(parameters, rows), harness.Assignability), BuiltInTypes.Int)

    assert harness.Errors.Count == 0
    assert DeclWalkTranscript(steps) == "2 7 3 4 1 1 5 6"
    assert steps[4].HasNode
    assert steps[5].HasNode
}

test "a row value that does not match its column is scolded by NAME and by both types" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 3, 12)
    rows := DeclWalkRows()
    row := DeclWalkValues()
    row.Add(new StringLiteralExpression("nope", 5, 5))
    DeclWalkRow(rows, row)

    DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(parameters, rows), harness.Assignability), BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message == "Table-driven test case value for 'value' is 'string', but the table header declares 'int'"
    assert harness.Errors[0].Line == 5
    assert harness.Errors[0].Column == 5
}

test "an UNKNOWN on either side of the comparison is not scolded" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 3, 12)
    rows := DeclWalkRows()
    row := DeclWalkValues()
    row.Add(new IntLiteralExpression("1", 5, 5))
    DeclWalkRow(rows, row)

    DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(parameters, rows), harness.Assignability), BuiltInTypes.Unknown)

    assert harness.Errors.Count == 0
}

test "the expected-type bracket is opened around the value and LEFT before the comparison" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 3, 12)
    rows := DeclWalkRows()
    row := DeclWalkValues()
    row.Add(new IntLiteralExpression("1", 5, 5))
    DeclWalkRow(rows, row)
    state := harness.Walkers.BeginTest(DeclWalkTest(parameters, rows), harness.Assignability)

    // Drive by hand so the slot can be read WHILE the value step is outstanding.
    step := harness.Walkers.NextStep(state)
    duringValue := "<never>"
    while step != null {
        if step.Kind == 1 {
            duringValue = DeclWalkTypeText(harness.Ambient.CurrentExpectedType)
        }

        answer: TypeInfo? = null
        if step.Kind == 1 {
            answer = BuiltInTypes.Int
        }

        harness.Walkers.Supply(state, answer)
        step = harness.Walkers.NextStep(state)
    }

    assert duringValue == "int"
    assert harness.Ambient.CurrentExpectedType == null
}

// ── the row value's constant rule ─────────────────────────────────────────────

test "the six literals, a parenthesised one and a negated numeric are constants" {
    assert AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new IntLiteralExpression("1", 5, 5))
    assert AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new FloatLiteralExpression("1.0", 5, 5))
    assert AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new CharLiteralExpression("a", 5, 5))
    assert AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new StringLiteralExpression("s", 5, 5))
    assert AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new BoolLiteralExpression(true, 5, 5))
    assert AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new NullLiteralExpression(5, 5))
    assert AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new ParenthesizedExpression(new IntLiteralExpression("1", 5, 6), 5, 5))
    assert AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new UnaryExpression(UnaryOperator.Negate, new IntLiteralExpression("1", 5, 6), 5, 5))
    assert AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new UnaryExpression(UnaryOperator.Negate, new FloatLiteralExpression("1.0", 5, 6), 5, 5))
}

test "a negated NON-numeric and every other shape are not constants" {
    assert !AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new UnaryExpression(UnaryOperator.Negate, new IdentifierExpression("x", 5, 6), 5, 5))
    assert !AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new UnaryExpression(UnaryOperator.Not, new BoolLiteralExpression(true, 5, 6), 5, 5))
    assert !AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new IdentifierExpression("x", 5, 5))
    assert !AnalyzerDeclarationWalkers.IsSupportedTableCaseValue(new CallExpression(new IdentifierExpression("f", 5, 5), new List<Argument>(), null, 5, 5))
}

test "a NON-CONSTANT row value is refused by name and is NOT then type-checked" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 3, 12)
    rows := DeclWalkRows()
    row := DeclWalkValues()
    row.Add(new CallExpression(new IdentifierExpression("f", 5, 5), new List<Argument>(), null, 5, 5))
    DeclWalkRow(rows, row)

    steps := DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(parameters, rows), harness.Assignability), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ConstantRequired
    assert harness.Errors[0].Message == "Table-driven test case values must be compile-time constants; call is not supported here"
    // No kind-1 step: a value that is not constant is never measured against a column.
    assert DeclWalkTranscript(steps) == "2 7 3 4 5 6"
}

test "THE CONSTANT CHECK STILL RUNS FOR A SURPLUS VALUE" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 3, 12)
    rows := DeclWalkRows()
    row := DeclWalkValues()
    row.Add(new IntLiteralExpression("1", 5, 5))
    row.Add(new CallExpression(new IdentifierExpression("f", 5, 8), new List<Argument>(), null, 5, 8))
    DeclWalkRow(rows, row)

    DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkTest(parameters, rows), harness.Assignability), BuiltInTypes.Int)

    // Two reports: the row's width, and the surplus value's non-constancy — which is the `||`
    // ORDER, and would be one report if the surplus test came first.
    assert harness.Errors.Count == 2
    assert harness.Errors[1].Code == ErrorCode.ConstantRequired
}

test "the refusal names the shape the user wrote" {
    harness := DeclWalkHarnessOf()

    assert !harness.Walkers.ValidateTableCaseValue(new IdentifierExpression("x", 5, 5))
    assert harness.Errors[0].Message == "Table-driven test case values must be compile-time constants; x expression is not supported here"

    assert !harness.Walkers.ValidateTableCaseValue(new BinaryExpression(new IntLiteralExpression("1", 5, 9), BinaryOperator.Add, new IntLiteralExpression("2", 5, 13), 5, 9))
    assert harness.Errors[1].Message == "Table-driven test case values must be compile-time constants; binary expression is not supported here"

    assert !harness.Walkers.ValidateTableCaseValue(new TypeOfExpression(new SimpleTypeReference("int", 5, 12), 5, 5))
    assert harness.Errors[2].Message == "Table-driven test case values must be compile-time constants; typeof expression is not supported here"
}

// ── the `setup` and `teardown` walks ──────────────────────────────────────────

test "a setup block opens its own scope and gets NO injected names" {
    harness := DeclWalkHarnessOf()
    statements := DeclWalkStatements()
    statements.Add(DeclWalkVariable("count", new SimpleTypeReference("int", 4, 9), null, 4, 5))
    declarations := new List<Declaration>()
    setup := new SetupDeclaration(DeclWalkBlock(statements), 3, 1)
    declarations.Add(setup)
    harness.Walkers.CollectTestScaffolding(declarations)

    steps := DeclWalkRun(harness, harness.Walkers.BeginSetup(setup, harness.Assignability), null)

    assert DeclWalkTranscript(steps) == "2 5 6"
    assert steps[0].Line == 3
}

test "a teardown gets the injected names and then walks its body" {
    harness := DeclWalkHarnessOf()
    statements := DeclWalkStatements()
    statements.Add(DeclWalkVariable("count", new SimpleTypeReference("int", 4, 9), null, 4, 5))
    declarations := new List<Declaration>()
    declarations.Add(new SetupDeclaration(DeclWalkBlock(statements), 3, 1))
    harness.Walkers.CollectTestScaffolding(declarations)
    teardown := new TeardownDeclaration(DeclWalkEmptyBlock(), 9, 1)

    steps := DeclWalkRun(harness, harness.Walkers.BeginTeardown(teardown, harness.Assignability), null)

    assert DeclWalkTranscript(steps) == "2 3 4 5 6"
    assert steps[0].Line == 9
    assert steps[1].Name == "count"
    assert steps[1].Line == 4
}

// ── the constructor walk ──────────────────────────────────────────────────────

func DeclWalkConstructor(parameters: List<Parameter>, initializer: Expression?): ConstructorDeclaration {
    return new ConstructorDeclaration(parameters, DeclWalkEmptyBlock(), initializer, Modifiers.None, new List<AttributeNode>(), 6, 5)
}

test "a constructor validates, declares and records its parameters, then walks its BODY as a statement" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 6, 17)

    steps := DeclWalkRun(harness, harness.Walkers.BeginConstructor(DeclWalkConstructor(parameters, null), harness.Assignability), null)

    assert DeclWalkTranscript(steps) == "2 7 3 4 8 6"
    assert steps[1].ParameterCount == 1
    assert steps[2].Name == "value"
    assert steps[2].CarriedType == "int"
    assert steps[2].Column == 17
    assert steps[4].HasBody
}

test "the CONSTRUCTOR ambient boundary is entered before the scope and left after it" {
    harness := DeclWalkHarnessOf()
    state := harness.Walkers.BeginConstructor(DeclWalkConstructor(DeclWalkParams(), null), harness.Assignability)

    assert !harness.Ambient.InConstructor
    steps := DeclWalkRun(harness, state, null)

    assert steps[0].InConstructor
    assert steps[steps.Count - 1].InConstructor
    assert !harness.Ambient.InConstructor
}

test "an INITIALIZER is analysed BEFORE the body" {
    harness := DeclWalkHarnessOf()
    initializer := new CallExpression(new IdentifierExpression("this", 7, 9), new List<Argument>(), null, 7, 9)

    steps := DeclWalkRun(harness, harness.Walkers.BeginConstructor(DeclWalkConstructor(DeclWalkParams(), initializer), harness.Assignability), BuiltInTypes.Void)

    assert DeclWalkTranscript(steps) == "2 7 1 8 6"
    assert steps[2].HasNode
    assert steps[3].HasBody
}

test "the definite-assignment check needs BOTH a declaring class and no initializer" {
    harness := DeclWalkHarnessOf()
    fields := new List<Declaration>()
    fields.Add(new FieldDeclaration("Value", new SimpleTypeReference("int", 5, 12), null, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), 5, 5))
    classDeclaration := new ClassDeclaration("Thing", null, null, new List<TypeReference>(), fields, null, Modifiers.None, new List<AttributeNode>(), 4, 1)
    harness.Ambient.EnterClassDeclaration(classDeclaration)

    DeclWalkRun(harness, harness.Walkers.BeginConstructor(DeclWalkConstructor(DeclWalkParams(), null), harness.Assignability), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.DefiniteAssignmentError
}

test "a CHAINING constructor hands the definite-assignment duty over and is silent" {
    harness := DeclWalkHarnessOf()
    fields := new List<Declaration>()
    fields.Add(new FieldDeclaration("Value", new SimpleTypeReference("int", 5, 12), null, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), 5, 5))
    classDeclaration := new ClassDeclaration("Thing", null, null, new List<TypeReference>(), fields, null, Modifiers.None, new List<AttributeNode>(), 4, 1)
    harness.Ambient.EnterClassDeclaration(classDeclaration)
    initializer := new CallExpression(new IdentifierExpression("this", 7, 9), new List<Argument>(), null, 7, 9)

    DeclWalkRun(harness, harness.Walkers.BeginConstructor(DeclWalkConstructor(DeclWalkParams(), initializer), harness.Assignability), BuiltInTypes.Void)

    assert harness.Errors.Count == 0
}

test "with NO declaring class the check does not run at all" {
    harness := DeclWalkHarnessOf()

    DeclWalkRun(harness, harness.Walkers.BeginConstructor(DeclWalkConstructor(DeclWalkParams(), null), harness.Assignability), null)

    assert harness.Errors.Count == 0
}

// ── THE `skip "reason"` CLAUSE — REFUSED, NOT SERVED ──────────────────────────
//
// PRODUCT DEFECT, PINNED: "the documented `skip` form fails to emit". `test "d" skip "r" { }` is the
// spelling `website/docs` published; it parses, it analyses, the formatter renders it and the LSP
// lists it — and it used to take the WHOLE FILE down at the columnar emit scan with
// `This product path requires successful N# columnar emission after analysis passes.`: no code, no
// line, no column, no reason, and every PASSING test in the same file lost with it.
//
// These contracts pin the refusal, and a refusal is all they pin. 020 slice 2 measured the skip
// CAPABILITY (zero consumers across 2,818 attributed test methods; a STATIC modifier cannot express
// the runtime preconditions the only candidates wanted) and declined it; nothing here emits, skips,
// or reports a skipped test, and nothing here should be read as a step toward one.

func DeclWalkSkippedTest(reason: string?): TestDeclaration {
    return new TestDeclaration("a test", DeclWalkEmptyBlock(), null, null, reason, 3, 1)
}

test "a test that declares skip is refused BY NAME, IN POSITION, with a suggestion" {
    harness := DeclWalkHarnessOf()

    DeclWalkRun(harness, harness.Walkers.BeginTest(DeclWalkSkippedTest("CI has no network"), harness.Assignability), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.FeatureNotImplemented
    assert harness.Errors[0].DiagnosticId == "NL323"
    assert harness.Errors[0].Message == "test 'a test' declares 'skip', which is parsed for forward compatibility but is not compiled by 'nlc test'"
    assert harness.Errors[0].Suggestion == "Delete the skip clause and its reason, or comment out the whole test declaration — nlc test cannot report a skipped test."
    assert harness.Errors[0].Severity == ErrorSeverity.Error

    // The declaration head, four characters wide: the `test` keyword. `TestDeclaration` carries the
    // reason but not the clause's own position, so the message names the clause and the span points
    // at the declaration that carries it.
    assert harness.Errors[0].Line == 3
    assert harness.Errors[0].Column == 1
    assert harness.Errors[0].Length == 4
}

test "the refusal is the ONLY thing skip changes — the walk itself is byte-for-byte the plain one" {
    skipped := DeclWalkHarnessOf()
    plain := DeclWalkHarnessOf()

    skippedSteps := DeclWalkRun(skipped, skipped.Walkers.BeginTest(DeclWalkSkippedTest("reason"), skipped.Assignability), null)
    plainSteps := DeclWalkRun(plain, plain.Walkers.BeginTest(DeclWalkTest(null, null), plain.Assignability), null)

    assert DeclWalkTranscript(skippedSteps) == DeclWalkTranscript(plainSteps)
    assert DeclWalkTranscript(skippedSteps) == "2 5 6"
    assert skipped.Errors.Count == 1
    assert plain.Errors.Count == 0
}

test "an EMPTY skip reason is still a skip clause, and a null one is still no clause" {
    empty := DeclWalkHarnessOf()
    absent := DeclWalkHarnessOf()

    DeclWalkRun(empty, empty.Walkers.BeginTest(DeclWalkSkippedTest(""), empty.Assignability), null)
    DeclWalkRun(absent, absent.Walkers.BeginTest(DeclWalkSkippedTest(null), absent.Assignability), null)

    assert empty.Errors.Count == 1
    assert empty.Errors[0].Code == ErrorCode.FeatureNotImplemented
    assert absent.Errors.Count == 0
}

test "a TABLE-DRIVEN test that also declares skip is refused ONCE, before its rows are walked" {
    harness := DeclWalkHarnessOf()
    parameters := DeclWalkParams()
    DeclWalkParam(parameters, "value", "int", 3, 12)
    rows := DeclWalkRows()
    row := DeclWalkValues()
    row.Add(new IntLiteralExpression("1", 5, 5))
    DeclWalkRow(rows, row)
    declaration := new TestDeclaration("a test", DeclWalkEmptyBlock(), parameters, rows, "reason", 3, 1)

    DeclWalkRun(harness, harness.Walkers.BeginTest(declaration, harness.Assignability), BuiltInTypes.Int)

    // One report for the declaration, not one per row: the lowering that turns R rows into R tests
    // happens at emit, and the clause is written once.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.FeatureNotImplemented
}

namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHICH LAMBDA BODIES AN EXPRESSION TREE ADMITS.
//
// The seven members this replaces were all `private` in `Analyzer.cs` and nothing in `src/`,
// `tests/` or `editors/` named any of them, so their behaviour was pinned only through whichever
// end-to-end diagnostic an inadmissible tree body happened to produce. This is their first DIRECT
// pinning, and it is written around the five things this family is easy to get wrong.
//
// (1) BOTH REPORTS DEDUPE, AND THE SECOND VISIT MUST STAY SILENT. A lambda can be reached twice —
// once through the expression dispatch and once through a target-typed door — and identity is code +
// line + column + message. A port that dropped the dedupe would double every expression-tree
// sentence in a program that target-types its lambdas.
//
// (2) THE REFUSAL IS THE FIRST ONE IN EVALUATION ORDER, NOT ANY ONE. The walk returns the first
// inadmissible node it meets, and the report anchors on THAT node's span — not on the lambda's — so
// a body with two problems complains about the one the reader reaches first.
//
// (3) A CALL'S RECEIVER IS THE ONE NON-SYNTACTIC QUESTION, AND THE VALUE PROBE COMES FIRST. `x.Trim()`
// and `Path.Combine(...)` are the same AST shape. A receiver that starts with a lambda parameter or
// with any name the scope stack knows as a SYMBOL is a value whatever else that name might also
// mean; only then is the dotted name asked of the well-known table, the declared types and the
// external probe. Reversing that order would make a local named `Path` disappear behind the type.
//
// (4) THE FIVE CALL DISQUALIFIERS FIRE BEFORE THE ARGUMENTS ARE WALKED, AND IN ORDER. A non-member
// callee, a null-conditional one, explicit type arguments, a `ref`/`out` argument and a NAMED
// argument each refuse the call itself rather than anything inside it.
//
// (5) `default`, `nameof` AND `typeof` ARE ADMISSIBLE *AND* HAVE DESCRIPTIONS. They are in the leaf
// set — an expression tree holds their value — and they also appear in the description table, which
// is not a contradiction: the table is only reached through the default arm.
class ExpressionTreeHarness {
    Validator: AnalyzerExpressionTreeValidator
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Diagnostics: AnalyzerDiagnosticSink

    constructor(validator: AnalyzerExpressionTreeValidator, errors: List<CompilerError>, scopes: AnalyzerScopeStack, diagnostics: AnalyzerDiagnosticSink) {
        Validator = validator
        Errors = errors
        Scopes = scopes
        Diagnostics = diagnostics
    }
}

func TreePath(): string {
    return Path.GetFullPath("expression-tree-contract.nl")
}

func TreeHarness(): ExpressionTreeHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(TreePath(), null)
    spans := new AnalyzerDiagnosticSpans(diagnostics)
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    probe := new AnalyzerExternalTypeProbe(assemblies, new List<string>())
    validator := new AnalyzerExpressionTreeValidator(diagnostics, spans, scopes, context, probe, null)
    return new ExpressionTreeHarness(validator, errors, scopes, diagnostics)
}

func TreeNames(): HashSet<string> {
    return new HashSet<string>(StringComparer.Ordinal)
}

func TreeNamesOf(first: string): HashSet<string> {
    names := new HashSet<string>(StringComparer.Ordinal)
    names.Add(first)
    return names
}

func TreeId(name: string): Expression {
    return new IdentifierExpression(name, 4, 9)
}

func TreeInt(text: string): Expression {
    return new IntLiteralExpression(text, 4, 9)
}

func TreeMember(receiver: Expression, name: string, nullConditional: bool): MemberAccessExpression {
    return new MemberAccessExpression(receiver, name, nullConditional, 4, 11)
}

func TreeArgs(): List<Argument> {
    return new List<Argument>()
}

func TreeArg(arguments: List<Argument>, value: Expression, name: string?, modifier: ArgumentModifier) {
    arguments.Add(new Argument(name, value, modifier))
}

func TreeCall(callee: Expression, arguments: List<Argument>, typeArguments: List<TypeReference>?): CallExpression {
    return new CallExpression(callee, arguments, typeArguments, 4, 13)
}

// The refusal a body produces, or "<none>" when the body is admissible — which is the whole answer
// this family gives, in one string.
func TreeRefusal(harness: ExpressionTreeHarness, body: Expression, parameterNames: HashSet<string>): string {
    finding := harness.Validator.FindUnsupportedExpression(body, parameterNames)
    if finding == null {
        return "<none>"
    }

    return finding.Description
}

// ── the two reports ───────────────────────────────────────────────────────────

test "the block-body report names the shape and points at the lambda" {
    harness := TreeHarness()
    lambda := new LambdaExpression(new List<Parameter>(), null, new BlockStatement(new List<Statement>(), 3, 12), 3, 5)

    harness.Validator.ReportBlockLambdaIfNeeded(lambda)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.FeatureNotImplemented
    assert harness.Errors[0].Message == "Expression-tree lambdas must use an expression body; block bodies are not supported"
    assert harness.Errors[0].Line == 3
    assert harness.Errors[0].Column == 5
}

test "the block-body report DEDUPES against a report already made at the same position" {
    harness := TreeHarness()
    lambda := new LambdaExpression(new List<Parameter>(), null, new BlockStatement(new List<Statement>(), 3, 12), 3, 5)

    harness.Validator.ReportBlockLambdaIfNeeded(lambda)
    harness.Validator.ReportBlockLambdaIfNeeded(lambda)
    harness.Validator.ReportBlockLambdaIfNeeded(lambda)

    assert harness.Errors.Count == 1
}

test "a lambda at a DIFFERENT position is a different report" {
    harness := TreeHarness()
    first := new LambdaExpression(new List<Parameter>(), null, new BlockStatement(new List<Statement>(), 3, 12), 3, 5)
    second := new LambdaExpression(new List<Parameter>(), null, new BlockStatement(new List<Statement>(), 9, 12), 9, 5)

    harness.Validator.ReportBlockLambdaIfNeeded(first)
    harness.Validator.ReportBlockLambdaIfNeeded(second)

    assert harness.Errors.Count == 2
}

test "the unsupported-expression report ANSWERS whether it reported, and dedupes to false" {
    harness := TreeHarness()

    first := harness.Validator.ReportUnsupportedExpressionIfNeeded(TreeId("captured"), TreeNames())
    second := harness.Validator.ReportUnsupportedExpressionIfNeeded(TreeId("captured"), TreeNames())

    assert first
    assert !second
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Expression-tree lambda body contains unsupported captured or static identifier 'captured'"
}

test "an admissible body reports nothing and answers false" {
    harness := TreeHarness()

    reported := harness.Validator.ReportUnsupportedExpressionIfNeeded(TreeInt("7"), TreeNames())

    assert !reported
    assert harness.Errors.Count == 0
}

test "the report anchors on the OFFENDING node rather than on the body's root" {
    harness := TreeHarness()
    // `x + captured` — the binary is admissible, its right operand is not, and the span is the
    // operand's.
    body := new BinaryExpression(TreeId("x"), BinaryOperator.Add, new IdentifierExpression("captured", 7, 21), 4, 9)

    harness.Validator.ReportUnsupportedExpressionIfNeeded(body, TreeNamesOf("x"))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 21
}

// ── the admissible set ────────────────────────────────────────────────────────

test "a lambda parameter is admissible and any other identifier is not" {
    harness := TreeHarness()

    assert TreeRefusal(harness, TreeId("x"), TreeNamesOf("x")) == "<none>"
    assert TreeRefusal(harness, TreeId("y"), TreeNamesOf("x")) == "captured or static identifier 'y'"
}

test "the nine leaf forms are admissible" {
    harness := TreeHarness()

    assert TreeRefusal(harness, new IntLiteralExpression("1", 4, 9), TreeNames()) == "<none>"
    assert TreeRefusal(harness, new FloatLiteralExpression("1.0", 4, 9), TreeNames()) == "<none>"
    assert TreeRefusal(harness, new CharLiteralExpression("a", 4, 9), TreeNames()) == "<none>"
    assert TreeRefusal(harness, new StringLiteralExpression("s", 4, 9), TreeNames()) == "<none>"
    assert TreeRefusal(harness, new BoolLiteralExpression(true, 4, 9), TreeNames()) == "<none>"
    assert TreeRefusal(harness, new NullLiteralExpression(4, 9), TreeNames()) == "<none>"
    assert TreeRefusal(harness, new DefaultExpression(4, 9), TreeNames()) == "<none>"
    assert TreeRefusal(harness, new NameofExpression(TreeId("x"), 4, 9), TreeNames()) == "<none>"
    assert TreeRefusal(harness, new TypeOfExpression(new SimpleTypeReference("int", 4, 16), 4, 9), TreeNames()) == "<none>"
}

test "member access walks INTO its receiver and a null-conditional one is refused outright" {
    harness := TreeHarness()

    assert TreeRefusal(harness, TreeMember(TreeId("x"), "Length", false), TreeNamesOf("x")) == "<none>"
    assert TreeRefusal(harness, TreeMember(TreeId("captured"), "Length", false), TreeNamesOf("x")) == "captured or static identifier 'captured'"
    assert TreeRefusal(harness, TreeMember(TreeId("x"), "Length", true), TreeNamesOf("x")) == "null-conditional member access"
}

test "index access walks BOTH halves and a null-conditional one is refused outright" {
    harness := TreeHarness()

    assert TreeRefusal(harness, new IndexAccessExpression(TreeId("x"), TreeInt("0"), false, 4, 9), TreeNamesOf("x")) == "<none>"
    assert TreeRefusal(harness, new IndexAccessExpression(TreeId("captured"), TreeInt("0"), false, 4, 9), TreeNamesOf("x")) == "captured or static identifier 'captured'"
    assert TreeRefusal(harness, new IndexAccessExpression(TreeId("x"), TreeId("captured"), false, 4, 9), TreeNamesOf("x")) == "captured or static identifier 'captured'"
    assert TreeRefusal(harness, new IndexAccessExpression(TreeId("x"), TreeInt("0"), true, 4, 9), TreeNamesOf("x")) == "null-conditional index access"
}

test "parentheses are transparent" {
    harness := TreeHarness()

    assert TreeRefusal(harness, new ParenthesizedExpression(TreeId("captured"), 4, 9), TreeNamesOf("x")) == "captured or static identifier 'captured'"
}

test "a supported binary operator walks both operands and an unsupported one names itself" {
    harness := TreeHarness()

    assert TreeRefusal(harness, new BinaryExpression(TreeId("x"), BinaryOperator.Add, TreeInt("1"), 4, 9), TreeNamesOf("x")) == "<none>"
    assert TreeRefusal(harness, new BinaryExpression(TreeId("x"), BinaryOperator.NullCoalesce, TreeInt("1"), 4, 9), TreeNamesOf("x")) == "binary operator '??'"
}

test "a supported unary operator walks its operand and an unsupported one names itself" {
    harness := TreeHarness()

    assert TreeRefusal(harness, new UnaryExpression(UnaryOperator.Negate, TreeId("x"), 4, 9), TreeNamesOf("x")) == "<none>"
    assert TreeRefusal(harness, new UnaryExpression(UnaryOperator.PreIncrement, TreeId("x"), 4, 9), TreeNamesOf("x")) == "unary operator '++'"
}

test "the ternary walks all three arms in order" {
    harness := TreeHarness()
    admissible := new TernaryExpression(TreeId("x"), TreeInt("1"), TreeInt("2"), 4, 9)
    inElse := new TernaryExpression(TreeId("x"), TreeInt("1"), TreeId("captured"), 4, 9)

    assert TreeRefusal(harness, admissible, TreeNamesOf("x")) == "<none>"
    assert TreeRefusal(harness, inElse, TreeNamesOf("x")) == "captured or static identifier 'captured'"
}

// A FINDING RECORDED RATHER THAN ASSERTED: the walk's "cast expression" refusal cannot fire.
// `CastKind` has exactly TWO members, `Hard` and `Safe`, and the guard admits both — so no cast a
// program can spell reaches that arm. The guard is kept because it is what `Analyzer.cs` wrote and
// because a third kind would arrive already refused rather than silently admitted; the contract
// says what IS reachable, and the description table's own "cast expression" row is pinned
// separately below.
test "BOTH cast kinds are admissible and walk their operand" {
    harness := TreeHarness()
    hard := new CastExpression(TreeId("x"), new SimpleTypeReference("int", 4, 10), CastKind.Hard, 4, 9)
    safe := new CastExpression(TreeId("captured"), new SimpleTypeReference("int", 4, 10), CastKind.Safe, 4, 9)

    assert TreeRefusal(harness, hard, TreeNamesOf("x")) == "<none>"
    assert TreeRefusal(harness, safe, TreeNamesOf("x")) == "captured or static identifier 'captured'"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(hard) == "cast expression"
}

// ── calls ─────────────────────────────────────────────────────────────────────

test "an instance call on a parameter receiver is admissible" {
    harness := TreeHarness()
    call := TreeCall(TreeMember(TreeId("x"), "Trim", false), TreeArgs(), null)

    assert TreeRefusal(harness, call, TreeNamesOf("x")) == "<none>"
}

test "the five call disqualifiers each name themselves" {
    harness := TreeHarness()

    bareCallee := TreeCall(TreeId("x"), TreeArgs(), null)
    assert TreeRefusal(harness, bareCallee, TreeNamesOf("x")) == "non-instance method call"

    nullConditional := TreeCall(TreeMember(TreeId("x"), "Trim", true), TreeArgs(), null)
    assert TreeRefusal(harness, nullConditional, TreeNamesOf("x")) == "null-conditional method call"

    typeArguments := new List<TypeReference>()
    typeArguments.Add(new SimpleTypeReference("int", 4, 16))
    generic := TreeCall(TreeMember(TreeId("x"), "Cast", false), TreeArgs(), typeArguments)
    assert TreeRefusal(harness, generic, TreeNamesOf("x")) == "generic method call"

    refArguments := TreeArgs()
    TreeArg(refArguments, TreeId("x"), null, ArgumentModifier.Ref)
    byRef := TreeCall(TreeMember(TreeId("x"), "Try", false), refArguments, null)
    assert TreeRefusal(harness, byRef, TreeNamesOf("x")) == "ref/out method argument"

    namedArguments := TreeArgs()
    TreeArg(namedArguments, TreeInt("1"), "count", ArgumentModifier.None)
    named := TreeCall(TreeMember(TreeId("x"), "Take", false), namedArguments, null)
    assert TreeRefusal(harness, named, TreeNamesOf("x")) == "named method argument"
}

test "a call's ARGUMENTS are walked, and an inadmissible one refuses the call" {
    harness := TreeHarness()
    arguments := TreeArgs()
    TreeArg(arguments, TreeInt("1"), null, ArgumentModifier.None)
    TreeArg(arguments, TreeId("captured"), null, ArgumentModifier.None)
    call := TreeCall(TreeMember(TreeId("x"), "Substring", false), arguments, null)

    assert TreeRefusal(harness, call, TreeNamesOf("x")) == "captured or static identifier 'captured'"
}

test "a STATIC call through a DECLARED type name is admissible and its receiver is not walked" {
    harness := TreeHarness()
    scope := harness.Scopes.Peek()
    scope.Types["Helper"] = BuiltInTypes.String
    call := TreeCall(TreeMember(TreeId("Helper"), "Combine", false), TreeArgs(), null)

    assert TreeRefusal(harness, call, TreeNames()) == "<none>"
}

test "a STATIC call through an EXTERNAL metadata type is admissible" {
    harness := TreeHarness()
    // `System.String` is resolved by the THIRD probe, the referenced-assembly one, from the same
    // core library the harness hands the probe. Nothing declares it and no scope knows it.
    call := TreeCall(TreeMember(TreeMember(TreeId("System"), "String", false), "Join", false), TreeArgs(), null)

    assert TreeRefusal(harness, call, TreeNames()) == "<none>"
}

// A HARNESS LIMIT, PINNED AS A DECLINE RATHER THAN LEFT UNSAID. The FIRST probe — the built-in
// keyword table — answers null whenever the well-known-type bag is absent, and it is absent in any
// harness built without a `MetadataLoadContext`. So `string.Join(...)` names NO type HERE while
// naming one in production, where the bag is built as the metadata context opens. The production
// path is covered end to end by the fixtures; this says what the contract can and cannot see.
test "the built-in keyword probe DECLINES without a well-known-type bag" {
    harness := TreeHarness()
    call := TreeCall(TreeMember(TreeId("string"), "Join", false), TreeArgs(), null)

    assert TreeRefusal(harness, call, TreeNames()) == "captured or static identifier 'string'"
}

test "A VALUE OF THE SAME NAME WINS: a scope symbol shadows a type as a call receiver" {
    harness := TreeHarness()
    scope := harness.Scopes.Peek()
    scope.Types["Helper"] = BuiltInTypes.String
    scope.Symbols["Helper"] = BuiltInTypes.String
    call := TreeCall(TreeMember(TreeId("Helper"), "Combine", false), TreeArgs(), null)

    // The receiver is now a VALUE, so it is walked — and a value that is not a lambda parameter is
    // a capture.
    assert TreeRefusal(harness, call, TreeNames()) == "captured or static identifier 'Helper'"
}

test "a lambda parameter is a value receiver even when a type of that name exists" {
    harness := TreeHarness()
    scope := harness.Scopes.Peek()
    scope.Types["x"] = BuiltInTypes.String
    call := TreeCall(TreeMember(TreeId("x"), "Trim", false), TreeArgs(), null)

    assert TreeRefusal(harness, call, TreeNamesOf("x")) == "<none>"
}

test "a receiver that is neither a value nor a resolvable type is walked and refused" {
    harness := TreeHarness()
    call := TreeCall(TreeMember(TreeId("Nowhere"), "Combine", false), TreeArgs(), null)

    assert TreeRefusal(harness, call, TreeNames()) == "captured or static identifier 'Nowhere'"
}

test "the value probe walks the DOTTED chain down to its root" {
    harness := TreeHarness()

    assert harness.Validator.ReceiverStartsWithValueIdentifier(TreeMember(TreeMember(TreeId("x"), "A", false), "B", false), TreeNamesOf("x"))
    assert !harness.Validator.ReceiverStartsWithValueIdentifier(TreeMember(TreeMember(TreeId("Type"), "A", false), "B", false), TreeNamesOf("x"))
    // A null-conditional link is not a name, so the chain stops being one.
    assert !harness.Validator.ReceiverStartsWithValueIdentifier(TreeMember(TreeMember(TreeId("x"), "A", true), "B", false), TreeNamesOf("x"))
    assert !harness.Validator.ReceiverStartsWithValueIdentifier(TreeInt("1"), TreeNamesOf("x"))
}

// ── object creation ───────────────────────────────────────────────────────────

func TreeAnonymous(properties: List<PropertyInitializer>): NewExpression {
    return new NewExpression(null, new List<Argument>(), new ObjectInitializerExpression(properties, 4, 9), 4, 9)
}

func TreeProperty(properties: List<PropertyInitializer>, name: string?, value: Expression, indexExpression: Expression?) {
    properties.Add(new PropertyInitializer(name, indexExpression, value, 4, 11))
}

test "an anonymous-object projection is the only admissible construction" {
    harness := TreeHarness()
    properties := new List<PropertyInitializer>()
    TreeProperty(properties, "A", TreeMember(TreeId("x"), "A", false), null)

    assert TreeRefusal(harness, TreeAnonymous(properties), TreeNamesOf("x")) == "<none>"
    assert AnalyzerExpressionTreeValidator.IsAnonymousObjectCreation(TreeAnonymous(properties))
}

test "a projection's property VALUES are walked" {
    harness := TreeHarness()
    properties := new List<PropertyInitializer>()
    TreeProperty(properties, "A", TreeId("captured"), null)

    assert TreeRefusal(harness, TreeAnonymous(properties), TreeNamesOf("x")) == "captured or static identifier 'captured'"
}

test "the four things that stop a construction being a projection" {
    typed := new NewExpression(new SimpleTypeReference("Thing", 4, 13), new List<Argument>(), new ObjectInitializerExpression(new List<PropertyInitializer>(), 4, 9), 4, 9)
    assert !AnalyzerExpressionTreeValidator.IsAnonymousObjectCreation(typed)

    constructorArguments := new List<Argument>()
    constructorArguments.Add(new Argument(null, new IntLiteralExpression("1", 4, 13), ArgumentModifier.None))
    positional := new NewExpression(null, constructorArguments, new ObjectInitializerExpression(new List<PropertyInitializer>(), 4, 9), 4, 9)
    assert !AnalyzerExpressionTreeValidator.IsAnonymousObjectCreation(positional)

    bare := new NewExpression(null, new List<Argument>(), null, 4, 9)
    assert !AnalyzerExpressionTreeValidator.IsAnonymousObjectCreation(bare)

    unnamed := new List<PropertyInitializer>()
    TreeProperty(unnamed, null, new IntLiteralExpression("1", 4, 13), null)
    assert !AnalyzerExpressionTreeValidator.IsAnonymousObjectCreation(TreeAnonymous(unnamed))

    indexed := new List<PropertyInitializer>()
    TreeProperty(indexed, "A", new IntLiteralExpression("1", 4, 13), new IntLiteralExpression("0", 4, 15))
    assert !AnalyzerExpressionTreeValidator.IsAnonymousObjectCreation(TreeAnonymous(indexed))
}

// ── the description table ─────────────────────────────────────────────────────

test "the description table names the seventeen shapes it knows" {
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new AssignmentExpression(TreeId("x"), AssignmentOperator.Assign, TreeInt("1"), 4, 9)) == "assignment expression"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new AwaitExpression(TreeId("x"), 4, 9)) == "await expression"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new CheckedExpression(TreeId("x"), 4, 9)) == "checked expression"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new UncheckedExpression(TreeId("x"), 4, 9)) == "unchecked expression"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new DefaultExpression(4, 9)) == "default expression"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new NameofExpression(TreeId("x"), 4, 9)) == "nameof expression"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new TypeOfExpression(new SimpleTypeReference("int", 4, 16), 4, 9)) == "typeof expression"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new LambdaExpression(new List<Parameter>(), TreeInt("1"), null, 4, 9)) == "nested lambda"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new SpreadExpression(TreeId("x"), 4, 9)) == "spread expression"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new ThrowExpression(TreeId("x"), 4, 9)) == "throw expression"
    assert AnalyzerExpressionTreeValidator.DescribeExpression(new SizeOfExpression(new SimpleTypeReference("int", 4, 16), 4, 9)) == "sizeof expression"
}

test "a shape the table does not know is named by its AST node type" {
    // Reached through the DEFAULT arm rather than the table, which is the fallback that keeps an
    // unnamed refusal from being silent.
    described := AnalyzerExpressionTreeValidator.DescribeExpression(new IsExpression(TreeId("x"), new SimpleTypeReference("int", 4, 16), null, 4, 9))

    assert described == "IsExpression"
}

test "the shapes the WALK refuses through the description table carry it into the report" {
    harness := TreeHarness()

    assert TreeRefusal(harness, new AwaitExpression(TreeId("x"), 4, 9), TreeNamesOf("x")) == "await expression"
    assert TreeRefusal(harness, new LambdaExpression(new List<Parameter>(), TreeInt("1"), null, 4, 9), TreeNames()) == "nested lambda"
    assert TreeRefusal(harness, new AssignmentExpression(TreeId("x"), AssignmentOperator.Assign, TreeInt("1"), 4, 9), TreeNamesOf("x")) == "assignment expression"
}

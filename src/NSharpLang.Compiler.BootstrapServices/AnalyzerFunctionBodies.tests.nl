namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT A DECLARED FUNCTION'S BODY MEANS.
//
// `AnalyzeLocalFunction` was `private` in `Analyzer.cs`, so nothing named it: its behaviour was
// pinned only indirectly, through whatever end-to-end diagnostic a broken local function happened to
// produce. So were both generator reports. This is their first DIRECT pinning, and it is written
// around the five things this family is easy to get wrong.
//
// (1) THE NAME IS DECLARED BEFORE THE SCOPE OPENS, AND THAT ORDER IS THE FEATURE. Its symbol lands in
// the ENCLOSING scope one step before the function scope is pushed, which is what makes a RECURSIVE
// call inside the body resolve and what keeps the name alive for the statements below it. It is NOT a
// hoist: the name lands when the STATEMENT is walked, so a call written ABOVE the declaration does not
// resolve (fixture f01 pins that, and fixture f26 pins the recursion). A driver that opened the scope
// first would compile most programs and silently break recursion, so the step ORDER is asserted rather
// than the end state.
//
// (2) THE PARAMETER LIST IS VALIDATED BEFORE ANY PARAMETER EXISTS, AND AFTER THE TYPE PARAMETERS ARE
// DECLARED. Both edges matter: a list rule that ran after the declarations would report against a
// name that already resolves, and a type parameter declared after the parameters would make
// `func f<T>(x: T)` resolve `T` to nothing.
//
// (3) AN EXPRESSION BODY IS WALKED UNDER AN EXPECTED TYPE, AND THREE DIFFERENT SHAPES ASK FOR NONE.
// A generator asks for none because it is about to be refused; a `void` return asks for none because
// there is nothing to target; an OMITTED return type is `void` and asks for none for the same reason.
// The expected type is carried on the request rather than installed in the ambient slot, because the
// analyzer's target-typed entry point short-circuits a lambda with the expected type as an ARGUMENT
// and leaves the slot alone — a difference that is observable whenever the expected type is absent.
//
// (4) THE GENERATOR EXPRESSION-BODY REPORT SILENCES THE RETURN-TYPE RULE. A `func*` written with an
// expression body has already been told the shape is wrong; measuring its expression against the
// sequence type it was ALSO told is wrong would be a second complaint about one mistake.
//
// (5) THE REFLECTED SEQUENCE ARM COMPARES RUNTIME IDENTITIES, NOT NAMES. A type loaded into the
// analyzer's MetadataLoadContext is a different object from its runtime twin, so it answers NO and
// falls through — which is what `Analyzer.cs` did, and which a later "simplification" to a name
// comparison would silently change.
class FunctionBodyHarness {
    Bodies: AnalyzerFunctionBodies
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Errors: List<CompilerError>
    Assignability: AnalyzerAssignability
    Model: SemanticModel

    constructor(bodies: AnalyzerFunctionBodies, ambient: AnalyzerAmbientContext, scopes: AnalyzerScopeStack, errors: List<CompilerError>, assignability: AnalyzerAssignability, model: SemanticModel) {
        Bodies = bodies
        Ambient = ambient
        Scopes = scopes
        Errors = errors
        Assignability = assignability
        Model = model
    }
}

// One replayed step, with the scope DEPTH and the error count AS THE STEP WAS HANDED OUT — which is
// what pins the window each operation happens in rather than only the operation itself.
class FunctionBodyStep {
    Kind: int
    Node: Expression?
    ExpectedType: string
    Name: string?
    CarriedType: string
    ParameterCount: int
    StatementCount: int
    Line: int
    Column: int
    Depth: int
    InLoop: bool
    ErrorsBefore: int

    constructor(kind: int, node: Expression?, expectedType: string, name: string?, carriedType: string, parameterCount: int, statementCount: int, line: int, column: int, depth: int, inLoop: bool, errorsBefore: int) {
        Kind = kind
        Node = node
        ExpectedType = expectedType
        Name = name
        CarriedType = carriedType
        ParameterCount = parameterCount
        StatementCount = statementCount
        Line = line
        Column = column
        Depth = depth
        InLoop = inLoop
        ErrorsBefore = errorsBefore
    }
}

func BodyPath(): string {
    return Path.GetFullPath("function-bodies-contract.nl")
}

func BodyHarnessWith(sourceText: string?): FunctionBodyHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(BodyPath(), sourceText)
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
    resolver.BeginAnalysis(BodyPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    factory := new AnalyzerFunctionTypeFactory(context, substitution)
    definite := new AnalyzerDefiniteAssignment(diagnostics, resolver)
    bodies := new AnalyzerFunctionBodies(diagnostics, spans, scopes, context, resolver, factory, ambient, escape, definite)
    return new FunctionBodyHarness(bodies, ambient, scopes, errors, assignability, model)
}

func BodyDefault(): FunctionBodyHarness {
    return BodyHarnessWith(null)
}

func BodyTypeText(candidate: TypeInfo?): string {
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

// ── the local-function driver, exactly as `Analyzer.cs` writes it ─────────────
//
// The scope operations are performed FOR REAL — kind 2 pushes a function scope, kind 3 writes the
// symbol, kind 6 pops — so that the depth recorded on every step is the depth the analyzer would
// have been at, and so that a name declared in the function scope stops resolving when the walk
// ends. Kind 5 records the statement list rather than re-entering the statement dispatch, which is
// the one thing a contract cannot replay.
func BodyRun(harness: FunctionBodyHarness, state: FunctionBodyState, answer: TypeInfo?): List<FunctionBodyStep> {
    steps := new List<FunctionBodyStep>()
    step := harness.Bodies.NextStep(state)
    while step != null {
        parameterCount := 0
        parameters := step.Parameters
        if parameters != null {
            parameterCount = parameters.Count
        }

        statementCount := -1
        statements := step.Statements
        if statements != null {
            statementCount = statements.Count
        }

        steps.Add(new FunctionBodyStep(step.Kind, step.Node, BodyTypeText(step.ExpectedType), step.Name, BodyTypeText(step.CarriedType), parameterCount, statementCount, step.Line, step.Column, harness.Scopes.Count, harness.Ambient.InLoop, harness.Errors.Count))

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

        harness.Bodies.Supply(state, answer)
        step = harness.Bodies.NextStep(state)
    }

    return steps
}

func BodyStepKinds(steps: List<FunctionBodyStep>): string {
    rendered := ""
    index := 0
    while index < steps.Count {
        if index > 0 {
            rendered = rendered + ","
        }

        rendered = rendered + steps[index].Kind.ToString()
        index = index + 1
    }

    return rendered
}

func BodyParameter(name: string, typeName: string, line: int, column: int): Parameter {
    return new Parameter(name, new SimpleTypeReference(typeName, line, column), null, false, ParameterModifier.None, null, line, column, false, null)
}

func BodyParameters(): List<Parameter> {
    return new List<Parameter>()
}

func BodyOneParameter(parameter: Parameter): List<Parameter> {
    parameters := new List<Parameter>()
    parameters.Add(parameter)
    return parameters
}

func BodyStatements(statement: Statement): List<Statement> {
    statements := new List<Statement>()
    statements.Add(statement)
    return statements
}

func BodyBareReturn(): Statement {
    bare: Statement = new ReturnStatement(null, 9, 9)
    return bare
}

func BodyBlock(): BlockStatement {
    return new BlockStatement(BodyStatements(BodyBareReturn()), 8, 5)
}

func BodyIntLiteral(): Expression {
    literal: Expression = new IntLiteralExpression("1", 7, 30)
    return literal
}

func BodyIntType(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("int", 7, 20)
    return reference
}

func BodyStringType(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("string", 7, 20)
    return reference
}

func BodyDeclaration(name: string, parameters: List<Parameter>, returnType: TypeReference?, body: BlockStatement?, expressionBody: Expression?, typeParameters: List<TypeParameter>?, modifiers: Modifiers): FunctionDeclaration {
    return new FunctionDeclaration(name, parameters, returnType, body, expressionBody, typeParameters, null, modifiers, new List<AttributeNode>(), false, null, false, false, 7, 10)
}

func BodyLocal(declaration: FunctionDeclaration): LocalFunctionStatement {
    return new LocalFunctionStatement(declaration, 7, 5)
}

func BodyBegin(harness: FunctionBodyHarness, declaration: FunctionDeclaration): FunctionBodyState {
    return harness.Bodies.BeginLocalFunction(BodyLocal(declaration), null, harness.Assignability)
}

func BodyErrorText(harness: FunctionBodyHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + "+" + error.Length.ToString()
}

func BodyReflected(clrType: Type): TypeInfo {
    reflected: TypeInfo = new ReflectionTypeInfo(clrType)
    return reflected
}

func BodyTypeArgs(argument: TypeInfo): List<TypeInfo> {
    arguments := new List<TypeInfo>()
    arguments.Add(argument)
    return arguments
}

func BodyGeneric(name: string, argument: TypeInfo): TypeInfo {
    generic: TypeInfo = new GenericTypeInfo(name, BodyTypeArgs(argument))
    return generic
}

// ---------------------------------------------------------------------------------------------
// THE STEP TRANSCRIPT, AND THE ORDER THAT IS THE FEATURE
// ---------------------------------------------------------------------------------------------

test "A BLOCK-BODIED LOCAL FUNCTION WITH NO PARAMETERS ASKS FOR FIVE STEPS IN ONE ORDER" {
    harness := BodyDefault()
    declaration := BodyDeclaration("helper", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    // Declare the name, open the function scope, validate the list, walk the statements, close.
    assert BodyStepKinds(steps) == "3,2,7,5,6"
    assert harness.Errors.Count == 0
}

test "THE NAME IS DECLARED IN THE ENCLOSING SCOPE, ONE STEP BEFORE THE FUNCTION SCOPE OPENS" {
    harness := BodyDefault()
    declaration := BodyDeclaration("helper", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    // Step 0 is the declaration and it happens at the OUTER depth; step 1 opens the scope and is the
    // last step still at that depth. That is what makes a recursive call inside the body resolve, and
    // what keeps the name visible to the statements that follow the declaration.
    assert steps[0].Kind == 3
    assert steps[0].Name == "helper"
    assert steps[0].Depth == 1
    assert steps[1].Kind == 2
    assert steps[1].Depth == 1
    assert steps[2].Depth == 2
}

test "THE NAME AND THE SCOPE BOTH LAND AT THE STATEMENT'S POSITION, NOT THE DECLARATION'S" {
    harness := BodyDefault()
    // The inner declaration carries 7:10; the statement carries 7:5, and the statement is what wins.
    declaration := BodyDeclaration("helper", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    assert steps[0].Line == 7
    assert steps[0].Column == 5
    assert steps[1].Line == 7
    assert steps[1].Column == 5
}

test "THE NAME IS DECLARED UNDER ITS FUNCTION TYPE, NOT UNDER ITS RETURN TYPE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("helper", BodyOneParameter(BodyParameter("a", "int", 7, 18)), BodyStringType(), BodyBlock(), null, null, Modifiers.None)

    BodyRun(harness, BodyBegin(harness, declaration), null)

    // What lands in the enclosing scope is the CALLABLE, built by the function-type factory from the
    // whole declaration — not the return type, which is what a naive port would have declared.
    declared := harness.Scopes.Peek().Symbols["helper"] as FunctionTypeInfo
    assert declared != null
    assert BodyTypeText(declared.ReturnType) == "string"
    assert declared.SourceParameterCount == 1
}

test "THE PARAMETER-LIST RULES RUN AFTER THE SCOPE OPENS AND BEFORE ANY PARAMETER IS DECLARED" {
    harness := BodyDefault()
    parameters := BodyOneParameter(BodyParameter("a", "int", 7, 18))
    declaration := BodyDeclaration("helper", parameters, BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    assert BodyStepKinds(steps) == "3,2,7,3,4,5,6"
    assert steps[2].Kind == 7
    assert steps[2].ParameterCount == 1
    // Inside the function scope, and at the STATEMENT's position rather than at the list's.
    assert steps[2].Depth == 2
    assert steps[2].Line == 7
    assert steps[2].Column == 5
}

test "EACH PARAMETER IS A DECLARE STEP AND THEN A RECORD STEP, IN LIST ORDER" {
    harness := BodyDefault()
    parameters := BodyOneParameter(BodyParameter("a", "int", 7, 18))
    parameters.Add(BodyParameter("b", "string", 7, 26))
    declaration := BodyDeclaration("helper", parameters, BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    assert BodyStepKinds(steps) == "3,2,7,3,4,3,4,5,6"
    assert steps[3].Name == "a"
    assert steps[3].CarriedType == "int"
    assert steps[4].Name == "a"
    assert steps[4].CarriedType == "int"
    assert steps[5].Name == "b"
    assert steps[5].CarriedType == "string"
    assert steps[6].Name == "b"
    assert steps[6].CarriedType == "string"
}

test "A PARAMETER IS DECLARED AT ITS OWN POSITION WHEN IT HAS ONE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("helper", BodyOneParameter(BodyParameter("a", "int", 7, 18)), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    assert steps[3].Line == 7
    assert steps[3].Column == 18
}

test "A PARAMETER WITH NO POSITION FALLS BACK TO THE STATEMENT'S, NOT TO LINE ZERO" {
    harness := BodyDefault()
    // A synthesised parameter — the shape a desugaring produces — carries 0:0.
    declaration := BodyDeclaration("helper", BodyOneParameter(BodyParameter("a", "int", 0, 0)), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    assert steps[3].Line == 7
    assert steps[3].Column == 5
}

test "THE BLOCK BODY IS HANDED OVER AS A STATEMENT LIST, NOT AS THE BLOCK" {
    harness := BodyDefault()
    body := BodyBlock()
    declaration := BodyDeclaration("helper", BodyParameters(), BodyIntType(), body, null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    // A list of one, walked INSIDE the function scope. Handing the block itself to the statement
    // dispatch would have opened a second scope, which is not what a function body is.
    assert steps[3].Kind == 5
    assert steps[3].StatementCount == 1
    assert steps[3].Depth == 2
}

test "THE SCOPE CLOSES LAST, AND THE NAMES DECLARED INSIDE IT STOP RESOLVING" {
    harness := BodyDefault()
    declaration := BodyDeclaration("helper", BodyOneParameter(BodyParameter("a", "int", 7, 18)), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    BodyRun(harness, BodyBegin(harness, declaration), null)

    // Back at the global scope, with the function's own name still visible and its parameter gone.
    assert harness.Scopes.Count == 1
    assert harness.Scopes.Peek().Symbols.ContainsKey("helper")
    assert !harness.Scopes.Peek().Symbols.ContainsKey("a")
}

test "A DECLARATION WITH NEITHER BODY SHAPE STILL OPENS AND CLOSES ITS SCOPE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("helper", BodyParameters(), BodyIntType(), null, null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    assert BodyStepKinds(steps) == "3,2,7,6"
    assert harness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// THE AMBIENT BOUNDARY
// ---------------------------------------------------------------------------------------------

test "ENTERING A LOCAL FUNCTION ZEROES THE AMBIENT LOOP, AND LEAVING IT RESTORES THE LOOP" {
    harness := BodyDefault()
    outerFrame := harness.Ambient.EnterLoop()
    declaration := BodyDeclaration("helper", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), null)

    // The body step is the one that matters: a `break` written inside a local function declared
    // inside a loop cannot reach that loop.
    assert steps[3].Kind == 5
    assert !steps[3].InLoop
    // And the enclosing loop is back the moment the walk ends.
    assert harness.Ambient.InLoop
    harness.Ambient.ExitLoop(outerFrame)
}

test "THE AMBIENT FUNCTION IS THE LOCAL DECLARATION INSIDE, AND IS RESTORED AFTER" {
    harness := BodyDefault()
    outer := BodyDeclaration("outer", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)
    outerFrame := harness.Ambient.EnterFunctionDeclaration(outer, BuiltInTypes.Int)
    declaration := BodyDeclaration("helper", BodyParameters(), BodyStringType(), BodyBlock(), null, null, Modifiers.None)

    state := BodyBegin(harness, declaration)
    step := harness.Bodies.NextStep(state)
    seenInside := false
    while step != null {
        if step.Kind == 5 {
            current := harness.Ambient.CurrentFunction as object
            expected := declaration as object
            seenInside = Object.ReferenceEquals(current, expected)
        }

        if step.Kind == 2 {
            harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Function), step.Line, step.Column)
        }

        if step.Kind == 6 {
            harness.Scopes.NoteLine(99)
            harness.Scopes.Pop(harness.Model)
        }

        harness.Bodies.Supply(state, null)
        step = harness.Bodies.NextStep(state)
    }

    assert seenInside
    restored := harness.Ambient.CurrentFunction as object
    outerBoxed := outer as object
    assert Object.ReferenceEquals(restored, outerBoxed)
    harness.Ambient.ExitFunctionDeclaration(outerFrame)
}

test "AN OMITTED RETURN TYPE MEANS void INSIDE THE BODY" {
    harness := BodyDefault()
    declaration := BodyDeclaration("helper", BodyParameters(), null, BodyBlock(), null, null, Modifiers.None)

    state := BodyBegin(harness, declaration)
    step := harness.Bodies.NextStep(state)
    insideReturnType := "<unseen>"
    while step != null {
        if step.Kind == 5 {
            insideReturnType = BodyTypeText(harness.Ambient.CurrentReturnType)
        }

        if step.Kind == 2 {
            harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Function), step.Line, step.Column)
        }

        if step.Kind == 6 {
            harness.Scopes.NoteLine(99)
            harness.Scopes.Pop(harness.Model)
        }

        harness.Bodies.Supply(state, null)
        step = harness.Bodies.NextStep(state)
    }

    assert insideReturnType == "void"
}

// ---------------------------------------------------------------------------------------------
// THE EXPRESSION BODY AND ITS EXPECTED TYPE
// ---------------------------------------------------------------------------------------------

test "AN EXPRESSION BODY IS WALKED UNDER THE DECLARED RETURN TYPE" {
    harness := BodyDefault()
    expressionBody := BodyIntLiteral()
    declaration := BodyDeclaration("doubled", BodyParameters(), BodyIntType(), null, expressionBody, null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), BuiltInTypes.Int)

    assert BodyStepKinds(steps) == "3,2,7,1,6"
    walkedNode := steps[3].Node as object
    bodyNode := expressionBody as object
    assert Object.ReferenceEquals(walkedNode, bodyNode)
    assert steps[3].ExpectedType == "int"
    assert harness.Errors.Count == 0
}

test "A void EXPRESSION BODY IS WALKED UNDER NO EXPECTED TYPE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("shout", BodyParameters(), new SimpleTypeReference("void", 7, 20), null, BodyIntLiteral(), null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), BuiltInTypes.Int)

    assert steps[3].Kind == 1
    assert steps[3].ExpectedType == "<null>"
}

test "AN OMITTED RETURN TYPE IS void AND ALSO ASKS FOR NO EXPECTED TYPE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("shout", BodyParameters(), null, null, BodyIntLiteral(), null, Modifiers.None)

    steps := BodyRun(harness, BodyBegin(harness, declaration), BuiltInTypes.Int)

    assert steps[3].Kind == 1
    assert steps[3].ExpectedType == "<null>"
}

test "A GENERATOR'S EXPRESSION BODY IS WALKED UNDER NO EXPECTED TYPE EVEN WITH A SEQUENCE RETURN" {
    harness := BodyDefault()
    declaration := BodyDeclaration("numbers", BodyParameters(), new GenericTypeReference("IEnumerable", BodyGenericArgs(), 7, 20), null, BodyIntLiteral(), null, Modifiers.Generator)

    steps := BodyRun(harness, BodyBegin(harness, declaration), BuiltInTypes.Int)

    assert steps[3].Kind == 1
    assert steps[3].ExpectedType == "<null>"
}

test "AN EXPRESSION BODY THAT DOES NOT FIT REPORTS AGAINST THE EXPRESSION, WITH THE LOCAL WORDING" {
    harness := BodyDefault()
    declaration := BodyDeclaration("doubled", BodyParameters(), BodyStringType(), null, BodyIntLiteral(), null, Modifiers.None)

    BodyRun(harness, BodyBegin(harness, declaration), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    // The span is the EXPRESSION's, not the declaration's — and the wording is the local function's
    // own, which differs from the top-level declaration's "This function should return".
    assert BodyErrorText(harness, 0) == "Function 'doubled' should return 'string' but the expression body gives 'int'|7:30+1"
}

test "AN EXPRESSION BODY THAT FITS IS SILENT, AND SO IS A void ONE THAT ANSWERS A VALUE" {
    harness := BodyDefault()
    fitting := BodyDeclaration("doubled", BodyParameters(), BodyIntType(), null, BodyIntLiteral(), null, Modifiers.None)
    BodyRun(harness, BodyBegin(harness, fitting), BuiltInTypes.Int)
    assert harness.Errors.Count == 0

    // A `void` local function with an expression body that produces a value is NOT reported here —
    // that report belongs to the top-level declaration arm, and this arm never had it.
    voided := BodyDeclaration("shout", BodyParameters(), new SimpleTypeReference("void", 7, 20), null, BodyIntLiteral(), null, Modifiers.None)
    BodyRun(harness, BodyBegin(harness, voided), BuiltInTypes.Int)
    assert harness.Errors.Count == 0
}

test "AN UNANSWERED EXPRESSION BODY FOLDS IN AS unknown AND IS NOT REPORTED AGAINST" {
    harness := BodyDefault()
    declaration := BodyDeclaration("doubled", BodyParameters(), BodyStringType(), null, BodyIntLiteral(), null, Modifiers.None)

    BodyRun(harness, BodyBegin(harness, declaration), null)

    // `unknown` is assignable to everything, so a walk that could not type the expression produces
    // no second complaint about it.
    assert harness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// THE TWO GENERATOR REPORTS
// ---------------------------------------------------------------------------------------------

func BodyGenericArgs(): List<TypeReference> {
    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("int", 7, 32))
    return arguments
}

test "A GENERATOR WITH AN EXPRESSION BODY IS REFUSED, AND THE REFUSAL SILENCES THE TYPE RULE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("numbers", BodyParameters(), BodyStringType(), null, BodyIntLiteral(), null, Modifiers.Generator)

    BodyRun(harness, BodyBegin(harness, declaration), BuiltInTypes.Int)

    // Two reports and not three: the return type is wrong for a generator AND the expression body is
    // the wrong shape — but the expression is NOT also measured against `string`.
    assert harness.Errors.Count == 2
    assert BodyErrorText(harness, 0) == "Generator function 'numbers' must return a synchronous enumerable sequence type, but it returns 'string'|7:20+6"
    assert BodyErrorText(harness, 1) == "Generator functions must use a block body|7:30+1"
}

test "A NON-GENERATOR WITH AN EXPRESSION BODY IS NEVER TOLD ABOUT BLOCK BODIES" {
    harness := BodyDefault()
    declaration := BodyDeclaration("doubled", BodyParameters(), BodyIntType(), null, BodyIntLiteral(), null, Modifiers.None)

    assert !harness.Bodies.ReportGeneratorExpressionBodyIfNeeded(declaration)
    assert harness.Errors.Count == 0
}

test "A GENERATOR WITH A BLOCK BODY IS NEVER TOLD ABOUT BLOCK BODIES EITHER" {
    harness := BodyDefault()
    declaration := BodyDeclaration("numbers", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.Generator)

    assert !harness.Bodies.ReportGeneratorExpressionBodyIfNeeded(declaration)
    assert harness.Errors.Count == 0
}

test "A GENERATOR RETURNING A SEQUENCE IS SILENT, AND ONE RETURNING A SCALAR IS NOT" {
    harness := BodyDefault()
    sequence := BodyGeneric("IEnumerable", BuiltInTypes.Int)
    generator := BodyDeclaration("numbers", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.Generator)

    assert !harness.Bodies.ReportGeneratorReturnTypeIfNeeded(generator, sequence)
    assert harness.Errors.Count == 0

    assert harness.Bodies.ReportGeneratorReturnTypeIfNeeded(generator, BuiltInTypes.Int)
    assert harness.Errors.Count == 1
    assert BodyErrorText(harness, 0) == "Generator function 'numbers' must return a synchronous enumerable sequence type, but it returns 'int'|7:20+3"
}

test "A NON-GENERATOR IS NEVER ASKED WHETHER ITS RETURN TYPE IS A SEQUENCE" {
    harness := BodyDefault()
    plain := BodyDeclaration("helper", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    assert !harness.Bodies.ReportGeneratorReturnTypeIfNeeded(plain, BuiltInTypes.Int)
    assert harness.Errors.Count == 0
}

test "A GENERATOR WHOSE RETURN TYPE IS unknown IS SILENT — ONE COMPLAINT PER MISTAKE" {
    harness := BodyDefault()
    generator := BodyDeclaration("numbers", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.Generator)

    assert !harness.Bodies.ReportGeneratorReturnTypeIfNeeded(generator, BuiltInTypes.Unknown)
    assert harness.Errors.Count == 0
}

test "A NULLABLE SEQUENCE IS STILL A SEQUENCE" {
    harness := BodyDefault()
    generator := BodyDeclaration("numbers", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.Generator)
    nullableSequence: TypeInfo = new NullableTypeInfo(BodyGeneric("IEnumerable", BuiltInTypes.Int))

    assert !harness.Bodies.ReportGeneratorReturnTypeIfNeeded(generator, nullableSequence)
    assert harness.Errors.Count == 0
}

test "async func* OWES AN ASYNC SEQUENCE, AND A SYNCHRONOUS ONE DOES NOT SATISFY IT" {
    harness := BodyDefault()
    asyncGenerator := BodyDeclaration("numbers", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.Generator | Modifiers.Async)

    assert harness.Bodies.ReportGeneratorReturnTypeIfNeeded(asyncGenerator, BodyGeneric("IEnumerable", BuiltInTypes.Int))
    assert BodyErrorText(harness, 0) == "Generator function 'numbers' must return an async enumerable sequence type, but it returns 'IEnumerable<int>'|7:20+3"

    assert !harness.Bodies.ReportGeneratorReturnTypeIfNeeded(asyncGenerator, BodyGeneric("IAsyncEnumerable", BuiltInTypes.Int))
    assert harness.Errors.Count == 1
}

test "func* OWES A SYNCHRONOUS SEQUENCE, AND AN ASYNC ONE DOES NOT SATISFY IT" {
    harness := BodyDefault()
    generator := BodyDeclaration("numbers", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.Generator)

    assert harness.Bodies.ReportGeneratorReturnTypeIfNeeded(generator, BodyGeneric("IAsyncEnumerable", BuiltInTypes.Int))
    assert harness.Errors.Count == 1
}

test "THE SQUIGGLE LANDS ON THE FUNCTION'S NAME WHEN THE RETURN TYPE WAS OMITTED" {
    harness := BodyHarnessWith("    func* numbers() {\n")
    generator := BodyDeclaration("numbers", BodyParameters(), null, BodyBlock(), null, null, Modifiers.Generator)

    assert harness.Bodies.ReportGeneratorReturnTypeIfNeeded(generator, BuiltInTypes.Void)
    // There is no written return type to underline, so the name is what carries the report.
    assert harness.Errors[0].Line == 7
}

// ---------------------------------------------------------------------------------------------
// THE REFLECTED SEQUENCE ARM
// ---------------------------------------------------------------------------------------------

test "A REFLECTED List<int> AND IEnumerable<int> ARE SYNCHRONOUS SEQUENCES" {
    assert AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BodyReflected(typeof(List<int>)), false)
    assert AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BodyReflected(typeof(System.Collections.Generic.IEnumerable<int>)), false)
}

test "A REFLECTED ARRAY IS NOT A SEQUENCE A GENERATOR MAY DECLARE" {
    // Enumerable, but not one of the six shapes — and refused BEFORE the generic question is asked.
    assert !AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BodyReflected(typeof(int[])), false)
}

test "A REFLECTED NON-GENERIC TYPE IS NOT A SEQUENCE" {
    assert !AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BodyReflected(typeof(string)), false)
}

test "A REFLECTED SYNCHRONOUS SEQUENCE DOES NOT SATISFY AN ASYNC GENERATOR" {
    assert !AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BodyReflected(typeof(List<int>)), true)
}

test "A DECLARED GENERIC ANSWERS BY NAME, SO A USER-WRITTEN List BEHAVES LIKE THE BCL ONE" {
    assert AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BodyGeneric("List", BuiltInTypes.Int), false)
    assert AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BodyGeneric("System.Collections.Generic.IReadOnlyList", BuiltInTypes.Int), false)
    assert !AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BodyGeneric("Dictionary", BuiltInTypes.Int), false)
}

test "A TYPE THAT IS NEITHER DECLARED-GENERIC NOR REFLECTED ANSWERS NO" {
    assert !AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BuiltInTypes.Int, false)
    assert !AnalyzerFunctionBodies.IsGeneratorSequenceReturnType(BuiltInTypes.Unknown, false)
}

// ---------------------------------------------------------------------------------------------
// THE EXPECTED-TYPE HELPER, ASKED DIRECTLY
// ---------------------------------------------------------------------------------------------

test "THE EXPECTED TYPE IS THE RETURN TYPE, EXCEPT FOR A GENERATOR OR A void" {
    plain := BodyDeclaration("helper", BodyParameters(), BodyIntType(), null, BodyIntLiteral(), null, Modifiers.None)
    generator := BodyDeclaration("numbers", BodyParameters(), BodyIntType(), null, BodyIntLiteral(), null, Modifiers.Generator)

    assert BodyTypeText(AnalyzerFunctionBodies.ExpressionBodyExpectedType(plain, BuiltInTypes.Int)) == "int"
    assert BodyTypeText(AnalyzerFunctionBodies.ExpressionBodyExpectedType(plain, BuiltInTypes.Void)) == "<null>"
    assert BodyTypeText(AnalyzerFunctionBodies.ExpressionBodyExpectedType(generator, BuiltInTypes.Int)) == "<null>"
}

// ---------------------------------------------------------------------------------------------
// THE BALANCE INVARIANTS, ASSERTED OVER EVERY SHAPE THE WALK HAS
// ---------------------------------------------------------------------------------------------

func BodyCountKind(steps: List<FunctionBodyStep>, kind: int): int {
    count := 0
    index := 0
    while index < steps.Count {
        if steps[index].Kind == kind {
            count = count + 1
        }

        index = index + 1
    }

    return count
}

func BodyShapes(): List<FunctionDeclaration> {
    shapes := new List<FunctionDeclaration>()
    // block body, no parameters
    shapes.Add(BodyDeclaration("a", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None))
    // block body, two parameters
    twoParameters := BodyOneParameter(BodyParameter("p", "int", 7, 18))
    twoParameters.Add(BodyParameter("q", "string", 7, 26))
    shapes.Add(BodyDeclaration("b", twoParameters, BodyIntType(), BodyBlock(), null, null, Modifiers.None))
    // expression body that fits
    shapes.Add(BodyDeclaration("c", BodyParameters(), BodyIntType(), null, BodyIntLiteral(), null, Modifiers.None))
    // expression body that does not fit
    shapes.Add(BodyDeclaration("d", BodyParameters(), BodyStringType(), null, BodyIntLiteral(), null, Modifiers.None))
    // generator with an expression body — the two-report shape
    shapes.Add(BodyDeclaration("e", BodyParameters(), BodyStringType(), null, BodyIntLiteral(), null, Modifiers.Generator))
    // generator with a block body and a bad return type — the one-report shape
    shapes.Add(BodyDeclaration("f", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.Generator))
    // omitted return type
    shapes.Add(BodyDeclaration("g", BodyParameters(), null, BodyBlock(), null, null, Modifiers.None))
    // neither body shape
    shapes.Add(BodyDeclaration("h", BodyParameters(), BodyIntType(), null, null, null, Modifiers.None))
    return shapes
}

test "EVERY SHAPE OPENS EXACTLY ONE SCOPE AND CLOSES EXACTLY ONE, AND ENDS WHERE IT STARTED" {
    index := 0
    shapes := BodyShapes()
    while index < shapes.Count {
        harness := BodyDefault()
        steps := BodyRun(harness, BodyBegin(harness, shapes[index]), BuiltInTypes.Int)

        assert BodyCountKind(steps, 2) == 1
        assert BodyCountKind(steps, 6) == 1
        // The close is always the LAST step, and the depth is back where it started.
        assert steps[steps.Count - 1].Kind == 6
        assert harness.Scopes.Count == 1
        index = index + 1
    }
}

test "EVERY SHAPE DECLARES ITS NAME ONCE AND VALIDATES ITS LIST ONCE" {
    index := 0
    shapes := BodyShapes()
    while index < shapes.Count {
        harness := BodyDefault()
        declaration := shapes[index]
        steps := BodyRun(harness, BodyBegin(harness, declaration), BuiltInTypes.Int)

        // One declare for the name plus one per parameter, and exactly one list validation.
        assert BodyCountKind(steps, 3) == 1 + declaration.Parameters.Count
        assert BodyCountKind(steps, 4) == declaration.Parameters.Count
        assert BodyCountKind(steps, 7) == 1
        index = index + 1
    }
}

test "NO REPORT IS RAISED BEFORE THE BODY IS REACHED, IN ANY SHAPE" {
    index := 0
    shapes := BodyShapes()
    while index < shapes.Count {
        harness := BodyDefault()
        steps := BodyRun(harness, BodyBegin(harness, shapes[index]), BuiltInTypes.Int)

        // Every step up to and including the parameter-list relay was handed out with a clean error
        // list: this family's own reports all fire at or after the body phase, and the relay's
        // reports belong to the driver rather than to the walk.
        stepIndex := 0
        while stepIndex < steps.Count {
            if steps[stepIndex].Kind == 7 {
                assert steps[stepIndex].ErrorsBefore == 0
            }

            stepIndex = stepIndex + 1
        }

        index = index + 1
    }
}

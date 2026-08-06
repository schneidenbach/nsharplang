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
    Extensions: List<FunctionDeclaration>
    Factory: AnalyzerFunctionTypeFactory

    constructor(bodies: AnalyzerFunctionBodies, ambient: AnalyzerAmbientContext, scopes: AnalyzerScopeStack, errors: List<CompilerError>, assignability: AnalyzerAssignability, model: SemanticModel, extensions: List<FunctionDeclaration>, factory: AnalyzerFunctionTypeFactory) {
        Bodies = bodies
        Ambient = ambient
        Scopes = scopes
        Errors = errors
        Assignability = assignability
        Model = model
        Extensions = extensions
        Factory = factory
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
    extensions := new List<FunctionDeclaration>()
    bodies := new AnalyzerFunctionBodies(diagnostics, spans, scopes, context, resolver, factory, ambient, escape, definite, extensions)
    return new FunctionBodyHarness(bodies, ambient, scopes, errors, assignability, model, extensions, factory)
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

// The index of the FIRST step of a kind, or -1. It is what pins a step's place in the order without
// spelling the whole transcript out, which matters where a shape matrix has different transcripts.
func BodyIndexOfKind(steps: List<FunctionBodyStep>, kind: int): int {
    index := 0
    while index < steps.Count {
        if steps[index].Kind == kind {
            return index
        }

        index = index + 1
    }

    return -1
}

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

// ---------------------------------------------------------------------------------------------
// FORM 1 — THE TOP-LEVEL `func` DECLARATION
// ---------------------------------------------------------------------------------------------
//
// `AnalyzeFunctionDeclaration` was `private` in `Analyzer.cs` too, and it is the widest thing this
// family does. What follows is written around the six things it is easy to get wrong, and every one
// of them is a decision the C# made silently.
//
// (1) THE NAME IS NOT ALWAYS DECLARED. A class's first pass registers its methods before their bodies
// are walked, so the walk asks the ENCLOSING scope what it already holds: a method group means the
// overloads are already merged, an identically-signed function means this is that declaration, and
// anything else means declare. Declaring unconditionally would either duplicate a symbol or re-merge
// a group, and neither shows up until a program has two overloads.
//
// (2) AN OPERATOR OVERLOAD TAKES A DIFFERENT ENTRY. Its three rules run before anything else, and it
// takes NO naming-convention step at all — an operator has no name of its own to get right.
//
// (3) THE BLOCK BODY GOES THROUGH THE DISPATCH, NOT THROUGH THE STATEMENT LIST. The step carries the
// BLOCK, so the block arm opens a block scope inside the function scope; a local function's body
// carries the LIST and opens none. That single difference is why the two forms cannot share phase 6.
//
// (4) LEAVING RESTORES THE RETURN TYPE TO NULL RATHER THAN TO THE SAVED ONE. That asymmetry is the
// original behaviour: leaving a declaration leaves "inside a function" entirely, so a stray `return`
// between two declarations is told it has no function to return from. A symmetric restore would look
// more correct and would be a behaviour change.
//
// (5) THE MISSING-RETURN RULE IS THIS FORM'S ALONE, AND IT HAS FOUR SILENCERS: a `void` return type,
// a generator, an `async` function owing a unit task, and a body that already always returns.
//
// (6) THE SCOPE AND THE BOUNDARY ARE OPENED FOR A DECLARATION WITH NO BODY AT ALL, and both are
// closed again — an interface member or an abstract method still balances.

func BodyOperator(symbol: string?, parameters: List<Parameter>, modifiers: Modifiers): FunctionDeclaration {
    return new FunctionDeclaration("op", parameters, BodyIntType(), BodyBlock(), null, null, null, modifiers, new List<AttributeNode>(), true, symbol, false, false, 7, 10)
}

func BodyConstrained(typeParameters: List<TypeParameter>?, constraints: List<GenericConstraint>?): FunctionDeclaration {
    return new FunctionDeclaration("gen", BodyParameters(), BodyIntType(), BodyBlock(), null, typeParameters, constraints, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 7, 10)
}

func BodyTypeParameters(names: List<string>): List<TypeParameter> {
    parameters := new List<TypeParameter>()
    index := 0
    while index < names.Count {
        parameters.Add(new TypeParameter(names[index]))
        index = index + 1
    }

    return parameters
}

func BodyNames(first: string, second: string?): List<string> {
    names := new List<string>()
    names.Add(first)
    if second != null {
        names.Add(second)
    }

    return names
}

func BodyConstraint(typeParameter: string, target: string): GenericConstraint {
    targets := new List<TypeReference>()
    reference: TypeReference = new SimpleTypeReference(target, 7, 20)
    targets.Add(reference)
    return new GenericConstraint(typeParameter, targets, SpecialConstraintKind.None)
}

func BodyConstraints(first: GenericConstraint, second: GenericConstraint?): List<GenericConstraint> {
    constraints := new List<GenericConstraint>()
    constraints.Add(first)
    if second != null {
        constraints.Add(second)
    }

    return constraints
}

// A NON-VOID return type nothing in the harness can resolve. It is what separates a rule silenced by
// the void check from one silenced by its own modifier.
func BodyUnknownType(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("Widget", 7, 20)
    return reference
}

// Seven blank lines and a declaration on line 7, so the reports that need a source line have one.
func BodySourceText(): string {
    return "\n\n\n\n\n\n    func Top(): string => 1\n"
}

func BodyCountCode(harness: FunctionBodyHarness, code: ErrorCode): int {
    total := 0
    index := 0
    while index < harness.Errors.Count {
        if harness.Errors[index].Code == code {
            total = total + 1
        }

        index = index + 1
    }

    return total
}

func BodyThisParameter(): Parameter {
    return new Parameter("self", new SimpleTypeReference("int", 7, 20), null, true, ParameterModifier.None, null, 7, 20, false, null)
}

// A block that does NOT always return: one bare expression statement and nothing else.
func BodyOpenBlock(): BlockStatement {
    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(BodyIntLiteral(), 8, 9))
    return new BlockStatement(statements, 8, 5)
}

func BodyDeclarationBegin(harness: FunctionBodyHarness, declaration: FunctionDeclaration): FunctionBodyState {
    return harness.Bodies.BeginFunctionDeclaration(declaration, null, harness.Assignability)
}

// The eight declaration shapes the balance invariants are asserted over.
func BodyDeclarationShapes(): List<FunctionDeclaration> {
    shapes := new List<FunctionDeclaration>()
    shapes.Add(BodyDeclaration("plain", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None))
    shapes.Add(BodyDeclaration("withParam", BodyOneParameter(BodyParameter("a", "int", 7, 20)), BodyIntType(), BodyBlock(), null, null, Modifiers.None))
    shapes.Add(BodyDeclaration("voidBody", BodyParameters(), null, BodyOpenBlock(), null, null, Modifiers.None))
    shapes.Add(BodyDeclaration("expression", BodyParameters(), BodyIntType(), null, BodyIntLiteral(), null, Modifiers.None))
    shapes.Add(BodyDeclaration("empty", BodyParameters(), BodyIntType(), null, null, null, Modifiers.None))
    shapes.Add(BodyDeclaration("generator", BodyParameters(), null, BodyBlock(), null, null, Modifiers.Generator))
    shapes.Add(BodyOperator("+", BodyOneParameter(BodyParameter("a", "int", 7, 20)), Modifiers.Static))
    shapes.Add(BodyConstrained(BodyTypeParameters(BodyNames("T", null)), BodyConstraints(BodyConstraint("T", "T"), null)))
    return shapes
}

test "A PLAIN BLOCK-BODIED DECLARATION ASKS FOR SEVEN STEPS IN ONE ORDER" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Top", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    // Declare the name, check the naming convention, open the function scope, validate the list,
    // record the function for the IDE, hand the BLOCK to the dispatch, close.
    assert BodyStepKinds(steps) == "3,10,2,7,8,9,6"
}

test "A PARAMETER ADDS THE DECLARE/RECORD PAIR BETWEEN THE LIST RULES AND THE IDE RECORD" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Top", BodyOneParameter(BodyParameter("a", "int", 7, 20)), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    assert BodyStepKinds(steps) == "3,10,2,7,3,4,8,9,6"
    // The parameter is declared at ITS OWN position, inside the function scope.
    assert steps[4].Name == "a"
    assert steps[4].Line == 7
    assert steps[4].Column == 20
    assert steps[4].Depth == 2
}

test "AN EXPRESSION BODY REPLACES THE DISPATCH STEP WITH THE TARGET-TYPED WALK" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Top", BodyParameters(), BodyIntType(), null, BodyIntLiteral(), null, Modifiers.None)

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), BuiltInTypes.Int)

    assert BodyStepKinds(steps) == "3,10,2,7,8,1,6"
    // Walked UNDER the declared return type, exactly as the nested form is.
    assert steps[5].ExpectedType == "int"
}

test "A DECLARATION WITH NEITHER BODY STILL OPENS AND CLOSES BOTH THE SCOPE AND THE BOUNDARY" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Abstract", BodyParameters(), BodyIntType(), null, null, null, Modifiers.None)

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    assert BodyStepKinds(steps) == "3,10,2,7,8,6"
    assert harness.Scopes.Count == 1
    assert harness.Ambient.CurrentFunction == null
    // No body means no missing-return report: there is no code path to judge.
    assert harness.Errors.Count == 0
}

test "THE BLOCK BODY IS HANDED OVER AS A BLOCK, NOT AS A STATEMENT LIST" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Top", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    // Kind 9 carries the block itself and NO statement list — which is what makes the dispatch open a
    // block scope inside the function scope. A local function's kind 5 does the opposite.
    assert steps[5].Kind == 9
    assert steps[5].StatementCount == -1
    assert BodyCountKind(steps, 5) == 0
}

test "THE NAME IS DECLARED AT THE DECLARATION'S POSITION, ONE STEP BEFORE ANYTHING ELSE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Top", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    assert steps[0].Kind == 3
    assert steps[0].Name == "Top"
    assert steps[0].Line == 7
    assert steps[0].Column == 10
    assert steps[0].Depth == 1
    assert steps[0].CarriedType != "<null>"
}

test "A NAME ALREADY HELD AS A METHOD GROUP IS NOT DECLARED AGAIN" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Merged", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)
    group: TypeInfo = NSharpMethodGroupInfoFactory.FromFunctions(new List<FunctionTypeInfo>())
    harness.Scopes.Peek().Symbols["Merged"] = group

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    // The first pass already merged every overload of this name; declaring into it again is what the
    // merge would have to undo.
    assert BodyStepKinds(steps) == "10,2,7,8,9,6"
}

test "A NAME ALREADY HELD AS AN IDENTICALLY-SIGNED FUNCTION IS NOT DECLARED AGAIN" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Same", BodyOneParameter(BodyParameter("a", "int", 7, 20)), BodyIntType(), BodyBlock(), null, null, Modifiers.None)
    existing := BodyDeclaration("Same", BodyOneParameter(BodyParameter("b", "int", 7, 20)), BodyIntType(), BodyBlock(), null, null, Modifiers.None)
    existingType: TypeInfo = harness.Factory.CreateFromDeclaration(existing, null)
    harness.Scopes.Peek().Symbols["Same"] = existingType

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    // Parameter NAMES do not distinguish signatures — this is the same declaration, already
    // registered by the first pass.
    assert BodyCountKind(steps, 3) == 1
    assert steps[0].Kind == 10
}

test "A NAME HELD AS A DIFFERENTLY-SIGNED FUNCTION IS DECLARED, AND SO IS ONE HELD AS A VALUE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Over", BodyOneParameter(BodyParameter("a", "int", 7, 20)), BodyIntType(), BodyBlock(), null, null, Modifiers.None)
    other := BodyDeclaration("Over", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)
    otherType: TypeInfo = harness.Factory.CreateFromDeclaration(other, null)
    harness.Scopes.Peek().Symbols["Over"] = otherType

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    // A real overload: the declaration still lands, and DeclareSymbol is what merges the group.
    assert steps[0].Kind == 3

    valueHarness := BodyDefault()
    valueHarness.Scopes.Peek().Symbols["Over"] = BuiltInTypes.Int
    valueSteps := BodyRun(valueHarness, BodyDeclarationBegin(valueHarness, declaration), null)

    // A field or property under the same name is not this rule's business — the duplicate is
    // DeclareSymbol's decision, not the walk's.
    assert valueSteps[0].Kind == 3
}

test "A FIRST PARAMETER MARKED `this` REGISTERS THE DECLARATION AS AN EXTENSION METHOD" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Ext", BodyOneParameter(BodyThisParameter()), BodyIntType(), BodyBlock(), null, null, Modifiers.None)

    BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    assert harness.Extensions.Count == 1
    assert harness.Extensions[0].Name == "Ext"
}

test "A PARAMETERLESS DECLARATION AND A PLAIN FIRST PARAMETER REGISTER NOTHING" {
    bare := BodyDefault()
    BodyRun(bare, BodyDeclarationBegin(bare, BodyDeclaration("Plain", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)), null)
    assert bare.Extensions.Count == 0

    plain := BodyDefault()
    BodyRun(plain, BodyDeclarationBegin(plain, BodyDeclaration("Plain", BodyOneParameter(BodyParameter("a", "int", 7, 20)), BodyIntType(), BodyBlock(), null, null, Modifiers.None)), null)
    assert plain.Extensions.Count == 0
}

test "THE NAMING-CONVENTION RELAY CARRIES THE NAME, THE MODIFIERS AND THE DECLARATION'S POSITION" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Top", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.Static)

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    assert steps[1].Kind == 10
    assert steps[1].Name == "Top"
    assert steps[1].Line == 7
    assert steps[1].Column == 10
    // It is asked BEFORE the scope opens, so the report lands outside the function's own scope.
    assert steps[1].Depth == 1
}

test "AN OPERATOR OVERLOAD TAKES NO NAMING-CONVENTION STEP AT ALL" {
    harness := BodyDefault()
    declaration := BodyOperator("+", BodyOneParameter(BodyParameter("a", "int", 7, 20)), Modifiers.Static)

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    assert BodyCountKind(steps, 10) == 0
    assert BodyStepKinds(steps) == "3,2,7,3,4,8,9,6"
}

test "AN OPERATOR THAT IS NOT `static` IS REPORTED ON THE `operator` KEYWORD, BEFORE ANY STEP" {
    harness := BodyDefault()
    declaration := BodyOperator("+", BodyOneParameter(BodyParameter("a", "int", 7, 20)), Modifiers.None)

    steps := BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidOperatorOverload
    // The very first step was already handed out with the report in place: the operator rules run
    // before the name is even computed.
    assert steps[0].ErrorsBefore == 1
}

test "AN UNSUPPORTED OPERATOR SYMBOL IS REPORTED ONCE AND SILENCES THE ARITY RULE" {
    harness := BodyDefault()
    declaration := BodyOperator("**", BodyParameters(), Modifiers.Static)

    BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    // One complaint about one mistake: there is no arity to check for an operator the language does
    // not have.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidOperatorOverload
}

test "`+` AND `-` MAY BE UNARY OR BINARY AND NOTHING ELSE MAY" {
    unary := BodyDefault()
    BodyRun(unary, BodyDeclarationBegin(unary, BodyOperator("-", BodyOneParameter(BodyParameter("a", "int", 7, 20)), Modifiers.Static)), null)
    assert unary.Errors.Count == 0

    ternary := BodyDefault()
    three := BodyOneParameter(BodyParameter("a", "int", 7, 20))
    three.Add(BodyParameter("b", "int", 7, 24))
    three.Add(BodyParameter("c", "int", 7, 28))
    BodyRun(ternary, BodyDeclarationBegin(ternary, BodyOperator("+", three, Modifiers.Static)), null)
    assert ternary.Errors.Count == 1
    assert ternary.Errors[0].Code == ErrorCode.OperatorParameterCount

    binaryOnly := BodyDefault()
    BodyRun(binaryOnly, BodyDeclarationBegin(binaryOnly, BodyOperator("==", BodyOneParameter(BodyParameter("a", "int", 7, 20)), Modifiers.Static)), null)
    assert binaryOnly.Errors.Count == 1
    assert binaryOnly.Errors[0].Code == ErrorCode.OperatorParameterCount

    unaryOnly := BodyDefault()
    BodyRun(unaryOnly, BodyDeclarationBegin(unaryOnly, BodyOperator("!", BodyOneParameter(BodyParameter("a", "int", 7, 20)), Modifiers.Static)), null)
    assert unaryOnly.Errors.Count == 0
}

test "TWO TYPE PARAMETERS CONSTRAINED TO EACH OTHER ARE REPORTED ONCE" {
    harness := BodyDefault()
    declaration := BodyConstrained(BodyTypeParameters(BodyNames("T", "U")), BodyConstraints(BodyConstraint("T", "U"), BodyConstraint("U", "T")))

    BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    // Two parameters are in the cycle and it is ONE mistake in one `where` clause set.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.GenericConstraintViolation
}

test "A TYPE PARAMETER CONSTRAINED TO ITSELF IS A CYCLE AND A CONSTRAINT TO A TYPE IS NOT" {
    direct := BodyDefault()
    BodyRun(direct, BodyDeclarationBegin(direct, BodyConstrained(BodyTypeParameters(BodyNames("T", null)), BodyConstraints(BodyConstraint("T", "T"), null))), null)
    assert direct.Errors.Count == 1
    assert direct.Errors[0].Code == ErrorCode.GenericConstraintViolation

    // `where T: IComparable` names a TYPE, not a sibling parameter, so it is not an edge and cannot
    // close a cycle.
    named := BodyDefault()
    BodyRun(named, BodyDeclarationBegin(named, BodyConstrained(BodyTypeParameters(BodyNames("T", "U")), BodyConstraints(BodyConstraint("T", "IComparable"), BodyConstraint("U", "T")))), null)
    assert named.Errors.Count == 0

    // A constraint naming a parameter this declaration does not have is not this rule's business.
    foreign := BodyDefault()
    BodyRun(foreign, BodyDeclarationBegin(foreign, BodyConstrained(BodyTypeParameters(BodyNames("T", null)), BodyConstraints(BodyConstraint("V", "T"), null))), null)
    assert foreign.Errors.Count == 0

    // No type parameters at all, or no constraints at all, is silent before anything is built.
    none := BodyDefault()
    BodyRun(none, BodyDeclarationBegin(none, BodyConstrained(null, BodyConstraints(BodyConstraint("T", "T"), null))), null)
    assert none.Errors.Count == 0
}

test "LEAVING A DECLARATION SETS THE RETURN TYPE TO NULL RATHER THAN RESTORING THE SAVED ONE" {
    harness := BodyDefault()
    outer := BodyDeclaration("Outer", BodyParameters(), BodyStringType(), BodyBlock(), null, null, Modifiers.None)
    harness.Ambient.EnterFunctionDeclaration(outer, BuiltInTypes.String)
    assert BodyTypeText(harness.Ambient.CurrentReturnType) == "string"

    declaration := BodyDeclaration("Inner", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)
    BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    // THE ASYMMETRY, PINNED. The enclosing FUNCTION and its flags come back, but the return type does
    // NOT: leaving a declaration leaves "inside a function" entirely, so a stray `return` written
    // between two declarations is told it has no function to return from.
    assert harness.Ambient.CurrentReturnType == null
    assert harness.Ambient.CurrentFunction != null
    assert harness.Ambient.CurrentFunction.Name == "Outer"
}

test "THE BOUNDARY IS ENTERED BEFORE THE BODY AND CARRIES THE DECLARED RETURN TYPE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Top", BodyParameters(), BodyStringType(), BodyBlock(), null, null, Modifiers.None)
    state := BodyDeclarationBegin(harness, declaration)

    // Walk to the IDE record — the last step before the body — and read the ambient there.
    step := harness.Bodies.NextStep(state)
    seen := 0
    while step != null && step.Kind != 8 {
        if step.Kind == 2 {
            harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Function), step.Line, step.Column)
        }

        seen = seen + 1
        harness.Bodies.Supply(state, null)
        step = harness.Bodies.NextStep(state)
    }

    assert step != null
    assert step.Kind == 8
    assert step.Name == "Top"
    assert BodyTypeText(harness.Ambient.CurrentReturnType) == "string"
    assert harness.Ambient.CurrentFunction != null
}

test "A NON-VOID BODY THAT DOES NOT ALWAYS RETURN IS REPORTED, AND FOUR SHAPES SILENCE IT" {
    open := BodyDefault()
    BodyRun(open, BodyDeclarationBegin(open, BodyDeclaration("Top", BodyParameters(), BodyIntType(), BodyOpenBlock(), null, null, Modifiers.None)), null)
    assert open.Errors.Count == 1
    assert open.Errors[0].Code == ErrorCode.MissingReturn

    // (a) every path already returns.
    closed := BodyDefault()
    BodyRun(closed, BodyDeclarationBegin(closed, BodyDeclaration("Top", BodyParameters(), BodyIntType(), BodyBlock(), null, null, Modifiers.None)), null)
    assert BodyCountCode(closed, ErrorCode.MissingReturn) == 0

    // (b) the function returns nothing.
    voided := BodyDefault()
    BodyRun(voided, BodyDeclarationBegin(voided, BodyDeclaration("Top", BodyParameters(), null, BodyOpenBlock(), null, null, Modifiers.None)), null)
    assert BodyCountCode(voided, ErrorCode.MissingReturn) == 0

    // (c) a generator produces its values with `yield` and never returns one. Its return type is a
    // NON-VOID one the walk cannot resolve, so the rule has to be silenced by the generator modifier
    // rather than by the void check — which is the thing being pinned.
    generator := BodyDefault()
    BodyRun(generator, BodyDeclarationBegin(generator, BodyDeclaration("Top", BodyParameters(), BodyUnknownType(), BodyOpenBlock(), null, null, Modifiers.Generator)), null)
    assert BodyCountCode(generator, ErrorCode.MissingReturn) == 0

    // (d) an `async` function whose declared type is a unit task owes no value.
    asyncUnit := BodyDefault()
    taskType: TypeReference = new SimpleTypeReference("Task", 7, 20)
    BodyRun(asyncUnit, BodyDeclarationBegin(asyncUnit, BodyDeclaration("Top", BodyParameters(), taskType, BodyOpenBlock(), null, null, Modifiers.Async)), null)
    assert BodyCountCode(asyncUnit, ErrorCode.MissingReturn) == 0

    // An `async` function owing a VALUE-carrying task is not silenced.
    asyncValue := BodyDefault()
    BodyRun(asyncValue, BodyDeclarationBegin(asyncValue, BodyDeclaration("Top", BodyParameters(), BodyIntType(), BodyOpenBlock(), null, null, Modifiers.Async)), null)
    assert BodyCountCode(asyncValue, ErrorCode.MissingReturn) == 1
}

test "THE MISSING-RETURN REPORT UNDERLINES `func ` PLUS THE NAME ON THE DECLARATION'S LINE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Total", BodyParameters(), BodyIntType(), BodyOpenBlock(), null, null, Modifiers.None)

    BodyRun(harness, BodyDeclarationBegin(harness, declaration), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 10
}

test "AN EXPRESSION BODY THAT DOES NOT FIT ITS RETURN TYPE REPORTS IN BOTH SHAPES, ONE POSITION EACH" {
    // WITH source text: the RICH builder, pointing at the EXPRESSION's own span.
    rich := BodyHarnessWith(BodySourceText())
    declaration := BodyDeclaration("Top", BodyParameters(), BodyStringType(), null, BodyIntLiteral(), null, Modifiers.None)
    BodyRun(rich, BodyDeclarationBegin(rich, declaration), BuiltInTypes.Int)

    assert rich.Errors.Count == 1
    assert rich.Errors[0].Code == ErrorCode.TypeMismatch
    assert rich.Errors[0].Line == 7
    assert rich.Errors[0].Column == 30

    // WITHOUT it: the detail-only shape, pointing at the DECLARATION, because there is no source line
    // to narrow to. Same report, same code, one door.
    plain := BodyDefault()
    BodyRun(plain, BodyDeclarationBegin(plain, declaration), BuiltInTypes.Int)

    assert plain.Errors.Count == 1
    assert plain.Errors[0].Code == ErrorCode.TypeMismatch
    assert plain.Errors[0].Line == 7
    assert plain.Errors[0].Column == 10

    fits := BodyDefault()
    BodyRun(fits, BodyDeclarationBegin(fits, BodyDeclaration("Top", BodyParameters(), BodyIntType(), null, BodyIntLiteral(), null, Modifiers.None)), BuiltInTypes.Int)
    assert fits.Errors.Count == 0
}

test "A VOID DECLARATION WHOSE EXPRESSION BODY HANDS BACK A VALUE IS TOLD SO, UNLIKE A LOCAL FUNCTION" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Top", BodyParameters(), null, null, BodyIntLiteral(), null, Modifiers.None)

    BodyRun(harness, BodyDeclarationBegin(harness, declaration), BuiltInTypes.Int)

    // The nested form is SILENT here; this form reports through the ambient context. That difference
    // is the reason the two phases are separate.
    assert harness.Errors.Count == 1

    local := BodyDefault()
    BodyRun(local, BodyBegin(local, BodyDeclaration("helper", BodyParameters(), null, null, BodyIntLiteral(), null, Modifiers.None)), BuiltInTypes.Int)
    assert local.Errors.Count == 0

    // A void declaration whose expression body hands back nothing is silent in both.
    silent := BodyDefault()
    BodyRun(silent, BodyDeclarationBegin(silent, BodyDeclaration("Top", BodyParameters(), null, null, BodyIntLiteral(), null, Modifiers.None)), BuiltInTypes.Void)
    assert silent.Errors.Count == 0
}

test "A GENERATOR'S EXPRESSION BODY IS REFUSED ONCE AND SILENCES THE RETURN-TYPE RULE" {
    harness := BodyDefault()
    declaration := BodyDeclaration("Top", BodyParameters(), BodyStringType(), null, BodyIntLiteral(), null, Modifiers.Generator)

    BodyRun(harness, BodyDeclarationBegin(harness, declaration), BuiltInTypes.Int)

    // The generator RETURN-TYPE report fires at phase 15 and the expression-body refusal at phase 18;
    // the type mismatch that would otherwise follow does not, because one mistake gets one complaint.
    assert harness.Errors.Count == 2
    assert harness.Errors[1].Code == ErrorCode.InvalidSyntax
}

test "EVERY DECLARATION SHAPE OPENS EXACTLY ONE SCOPE, CLOSES IT LAST, AND RETURNS TO ITS DEPTH" {
    index := 0
    shapes := BodyDeclarationShapes()
    while index < shapes.Count {
        harness := BodyDefault()
        before := harness.Scopes.Count
        steps := BodyRun(harness, BodyDeclarationBegin(harness, shapes[index]), BuiltInTypes.Int)

        assert BodyCountKind(steps, 2) == 1
        assert BodyCountKind(steps, 6) == 1
        assert steps[steps.Count - 1].Kind == 6
        assert harness.Scopes.Count == before
        index = index + 1
    }
}

test "EVERY DECLARATION SHAPE VALIDATES ITS LIST ONCE, RECORDS ITSELF ONCE, AND LEAVES NO FUNCTION BEHIND" {
    index := 0
    shapes := BodyDeclarationShapes()
    while index < shapes.Count {
        harness := BodyDefault()
        steps := BodyRun(harness, BodyDeclarationBegin(harness, shapes[index]), BuiltInTypes.Int)

        assert BodyCountKind(steps, 7) == 1
        assert BodyCountKind(steps, 8) == 1
        // The list rules are asked before any parameter exists, and the IDE record after all of them.
        assert BodyIndexOfKind(steps, 7) < BodyIndexOfKind(steps, 8)
        assert harness.Ambient.CurrentReturnType == null
        assert harness.Ambient.CurrentFunction == null
        index = index + 1
    }
}

test "EVERY DECLARATION SHAPE ASKS FOR AT MOST ONE BODY STEP, AND NEVER BOTH SHAPES" {
    index := 0
    shapes := BodyDeclarationShapes()
    while index < shapes.Count {
        harness := BodyDefault()
        steps := BodyRun(harness, BodyDeclarationBegin(harness, shapes[index]), BuiltInTypes.Int)

        assert BodyCountKind(steps, 9) + BodyCountKind(steps, 1) <= 1
        // A local function's statement-LIST step never appears in this form.
        assert BodyCountKind(steps, 5) == 0
        index = index + 1
    }
}

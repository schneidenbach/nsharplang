namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for what a guarded region is: `try`, `using` and `lock`.
//
// THE PROTOCOL IS THE CONTRACT, because the driver in `Analyzer.cs` is zero-policy: it switches on
// `Kind`, performs exactly one operation with exactly the carried operands, and hands the answer
// back. So the requests a shape emits — how many, in which ORDER, and with which OPERANDS — are the
// observable behaviour, and every contract below drives the walk the way the driver does.
//
// FIVE THINGS ARE EASY TO GET WRONG WHEN THREE STATEMENTS SHARE ONE PROTOCOL, and the contracts are
// written around them:
//   * a catch clause opens its scope and declares its variable at the TRY statement's position, not
//     at its own — so a `catch` in a two-clause `try` reports against the same line as the first;
//   * the catch loop SUSPENDS, so its cursor lives on the state and a second clause must replay the
//     whole sequence rather than continue the first;
//   * the `finally` depth must come back down, and it must be raised for exactly the finally body —
//     a `return` in a `try` block is legal and a `return` in its `finally` is not;
//   * `using`'s two resource forms share the scope, the body and the report and NOTHING else, and
//     the declaration form is measured only when its own declaration was clean;
//   * `lock`'s gate is an else-if CHAIN, so a direct-column escape does NOT stop the value-type
//     report while a type-parameter answer DOES.

class ResHarness {
    Owner: AnalyzerResourceStatements
    Diagnostics: AnalyzerDiagnosticSink
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Ambient: AnalyzerAmbientContext
    Assignability: AnalyzerAssignability
    Clr: AnalyzerClrTypeConversion
    Steps: List<ResStep>
    Answers: List<TypeInfo>
    AnswerIndex: int
    ScopeDepth: int
    MaxScopeDepth: int
    DeclaredResourceType: TypeInfo?
    ErrorsOnDeclaration: int
    FinallyDepthInBody: int

    constructor(
        owner: AnalyzerResourceStatements,
        diagnostics: AnalyzerDiagnosticSink,
        errors: List<CompilerError>,
        scopes: AnalyzerScopeStack,
        ambient: AnalyzerAmbientContext,
        assignability: AnalyzerAssignability,
        clr: AnalyzerClrTypeConversion) {
        Owner = owner
        Diagnostics = diagnostics
        Errors = errors
        Scopes = scopes
        Ambient = ambient
        Assignability = assignability
        Clr = clr
        Steps = new List<ResStep>()
        Answers = new List<TypeInfo>()
        AnswerIndex = 0
        ScopeDepth = 0
        MaxScopeDepth = 0
        DeclaredResourceType = null
        ErrorsOnDeclaration = 0
        FinallyDepthInBody = -1
    }
}

// Every step the walk asked for, in order, with everything it carried — plus the ambient finally
// depth and the error count the driver would have seen at that moment.
class ResStep {
    Kind: int
    Node: Expression?
    HasBody: bool
    HasDeclaration: bool
    Name: string?
    CarriedType: TypeInfo
    Line: int
    Column: int
    ErrorsBefore: int
    FinallyDepth: int

    constructor(
        kind: int,
        node: Expression?,
        hasBody: bool,
        hasDeclaration: bool,
        name: string?,
        carriedType: TypeInfo,
        line: int,
        column: int,
        errorsBefore: int,
        finallyDepth: int) {
        Kind = kind
        Node = node
        HasBody = hasBody
        HasDeclaration = hasDeclaration
        Name = name
        CarriedType = carriedType
        Line = line
        Column = column
        ErrorsBefore = errorsBefore
        FinallyDepth = finallyDepth
    }
}

func ResPath(): string {
    return Path.GetFullPath("resource-statement-contract.nl")
}

func ResHarnessNew(): ResHarness {
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
    diagnostics.BeginAnalysis(ResPath(), null)
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
    resolver.BeginAnalysis(ResPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    throwability := new AnalyzerThrowability(scopes, context, substitution)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    facts := new AnalyzerAssignabilityFacts(context, null)
    assignability := new AnalyzerAssignability(
        context,
        facts,
        structural,
        substitution,
        new AnalyzerClrTypeConversion(context, null),
        new AnalyzerImplicitConversionGuard())
    owner := new AnalyzerResourceStatements(
        diagnostics,
        spans,
        scopes,
        context,
        resolver,
        substitution,
        ambient,
        escape,
        throwability)
    ResDeclareTypes(scopes)
    return new ResHarness(
        owner,
        diagnostics,
        errors,
        scopes,
        ambient,
        assignability,
        new AnalyzerClrTypeConversion(context, null))
}

// The type vocabulary every contract below shares: a throwable class, a plain class, a class that
// carries the structural `Dispose` pattern, and a plain struct.
func ResDeclareTypes(scopes: AnalyzerScopeStack) {
    types := scopes.Peek().Types
    types["AppError"] = ResClass("AppError", new SimpleTypeReference("Exception", 1, 1), new DeclaredMemberInfo[](0))
    types["Widget"] = ResClass("Widget", null, new DeclaredMemberInfo[](0))
    types["Handle"] = ResClass("Handle", null, ResDisposeMembers())
}

func ResClass(name: string, baseClass: TypeReference?, members: DeclaredMemberInfo[]): TypeInfo {
    declared: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        false,
        baseClass,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        members,
        new NestedTypeInfo[](0),
        true)
    return declared
}

func ResDisposeMembers(): DeclaredMemberInfo[] {
    members := new DeclaredMemberInfo[](1)
    members[0] = new DeclaredMemberInfo(
        "Dispose",
        "Handle",
        DeclaredMemberKind.Function,
        "function",
        null,
        false,
        false,
        false,
        true,
        0,
        new string[](0),
        new TypeReference[](0),
        new ParameterModifier[](0),
        0,
        false,
        false,
        new SimpleTypeReference("void", 1, 1),
        0,
        new TypeParameter[](0),
        new GenericConstraint[](0),
        0,
        false,
        false,
        false,
        false,
        "",
        false,
        false,
        1,
        1)
    return members
}

// ── the driver, exactly as `Analyzer.cs` writes it ────────────────────────

// Kind 1 is answered from the `Answers` list in order (falling back to `unknown`). Kind 7 — the
// nested local-declaration walk — is simulated at the level the resource walk can actually observe:
// it may inject diagnostics (a declaration that failed) and it may bind a symbol (a declaration that
// succeeded), which is exactly the pair of facts phase 12 reads back.
func ResRun(harness: ResHarness, state: ResourceStatementState) {
    steps := harness.Steps
    steps.Clear()
    harness.AnswerIndex = 0
    harness.ScopeDepth = 0
    harness.MaxScopeDepth = 0

    step := harness.Owner.NextResourceStep(state)
    while step != null {
        steps.Add(new ResStep(
            step.Kind,
            step.Node,
            step.Body != null,
            step.Declaration != null,
            step.Name,
            step.CarriedType,
            step.Line,
            step.Column,
            harness.Errors.Count,
            harness.Ambient.FinallyDepth))

        supplied: TypeInfo? = null
        if step.Kind == 1 {
            supplied = BuiltInTypes.Unknown
            if harness.AnswerIndex < harness.Answers.Count {
                supplied = harness.Answers[harness.AnswerIndex]
            }

            harness.AnswerIndex = harness.AnswerIndex + 1
        }

        if step.Kind == 2 {
            harness.ScopeDepth = harness.ScopeDepth + 1
            if harness.ScopeDepth > harness.MaxScopeDepth {
                harness.MaxScopeDepth = harness.ScopeDepth
            }
        }

        if step.Kind == 6 {
            harness.ScopeDepth = harness.ScopeDepth - 1
        }

        if step.Kind == 5 {
            harness.FinallyDepthInBody = harness.Ambient.FinallyDepth
        }

        if step.Kind == 7 {
            ResSimulateDeclaration(harness, step)
        }

        harness.Owner.SupplyResource(state, supplied)
        step = harness.Owner.NextResourceStep(state)
    }
}

func ResSimulateDeclaration(harness: ResHarness, step: ResourceStatementRequest) {
    injected := 0
    while injected < harness.ErrorsOnDeclaration {
        harness.Errors.Add(new CompilerError(
            ErrorCode.UndefinedVariable,
            "injected",
            7,
            5,
            ErrorSeverity.Error))
        injected = injected + 1
    }

    declaredType := harness.DeclaredResourceType
    declaration := step.Declaration
    if declaredType != null && declaration != null {
        harness.Scopes.Peek().Symbols[declaration.Name] = declaredType
    }
}

func ResKinds(steps: List<ResStep>): string {
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

// ── AST builders ──────────────────────────────────────────────────────────

func ResName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 7, 5)
}

func ResBlock(count: int): BlockStatement {
    statements := new List<Statement>()
    index := 0
    while index < count {
        statements.Add(new ExpressionStatement(
            new CallExpression(ResName("Step"), new List<Argument>(), null, 8 + index, 9),
            8 + index,
            9))
        index = index + 1
    }

    return new BlockStatement(statements, 7, 20)
}

func ResCatch(typeName: string?, variableName: string?): CatchClause {
    declaredType: TypeReference? = null
    if typeName != null {
        declaredType = new SimpleTypeReference(typeName, 9, 11)
    }

    return new CatchClause(declaredType, variableName, ResBlock(1))
}

func ResTry(clauses: List<CatchClause>, hasFinally: bool): TryStatement {
    finallyBlock: BlockStatement? = null
    if hasFinally {
        finallyBlock = ResBlock(1)
    }

    return new TryStatement(ResBlock(2), clauses, finallyBlock, 7, 5)
}

func ResNoCatches(): List<CatchClause> {
    return new List<CatchClause>()
}

func ResOneCatch(typeName: string?, variableName: string?): List<CatchClause> {
    clauses := new List<CatchClause>()
    clauses.Add(ResCatch(typeName, variableName))
    return clauses
}

func ResUsingDeclaration(name: string): VariableDeclarationStatement {
    return new VariableDeclarationStatement(
        name,
        null,
        new CallExpression(ResName("Open"), new List<Argument>(), null, 7, 20),
        VariableKind.Let,
        7,
        11)
}

func ResUsingWithDeclaration(name: string, hasBody: bool): UsingStatement {
    body: Statement? = null
    if hasBody {
        body = ResBlock(1)
    }

    return new UsingStatement(ResUsingDeclaration(name), null, body, 7, 5)
}

func ResUsingWithExpression(expression: Expression, hasBody: bool): UsingStatement {
    body: Statement? = null
    if hasBody {
        body = ResBlock(1)
    }

    return new UsingStatement(null, expression, body, 7, 5)
}

func ResLock(lockee: Expression): LockStatement {
    return new LockStatement(lockee, ResBlock(1), 7, 5)
}

// A REFLECTED type named through `Type.GetType`. The columnar `typeof` surface carries a hardcoded
// well-known list, and `System.IO.MemoryStream` is not on it — the same door `AnalyzerLoopSequence`
// opens for the non-generic sequence interfaces.
func ResReflected(fullName: string): TypeInfo {
    clrType := Type.GetType(fullName)
    if clrType == null {
        throw new InvalidOperationException("Required type " + fullName + " was not found.")
    }

    resolved: TypeInfo = new ReflectionTypeInfo(clrType)
    return resolved
}

func ResRowType(): SoaRowTypeInfo {
    columns := new List<SoaColumnInfo>()
    return new SoaRowTypeInfo(new SoaRecordDeclarationInfo("Particle", columns, 1, 1))
}

func ResSoaColumns(): List<SoaColumnInfo> {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int", 0, 0), 1, 1))
    return columns
}

func ResDeclareSoaTable(harness: ResHarness) {
    table: TypeInfo = new SoaRecordTypeInfo(
        new SoaRecordDeclarationInfo("Points", ResSoaColumns(), 1, 1))
    harness.Scopes.Peek().Symbols["points"] = table
}

func ResSoaColumnRead(): Expression {
    read: Expression = new MemberAccessExpression(ResName("points"), "x", false, 7, 5)
    return read
}

func ResFunction(name: string, typeParameters: List<TypeParameter>?, constraints: List<GenericConstraint>?): FunctionDeclaration {
    return new FunctionDeclaration(
        name,
        new List<Parameter>(),
        null,
        null,
        null,
        typeParameters,
        constraints,
        Modifiers.None,
        new List<AttributeNode>(),
        false,
        null,
        false,
        false,
        1,
        1)
}

func ResTypeParameters(name: string): List<TypeParameter> {
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter(name))
    return parameters
}

func ResClassConstraint(name: string): List<GenericConstraint> {
    constraints := new List<GenericConstraint>()
    constraints.Add(new GenericConstraint(name, new List<TypeReference>(), SpecialConstraintKind.Class))
    return constraints
}

// ── the `try` walk ────────────────────────────────────────────────────────

test "a try with no catch and no finally is one statement step" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResNoCatches(), false), harness.Clr))

    assert ResKinds(harness.Steps) == "5"
    assert harness.Steps[0].HasBody
}

test "a bare catch opens a scope, walks the block and closes it" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResOneCatch(null, null), false), harness.Clr))

    assert ResKinds(harness.Steps) == "5,2,5,6"
}

test "a catch WITH a variable declares it and records it before the block runs" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResOneCatch("AppError", "e"), false), harness.Clr))

    assert ResKinds(harness.Steps) == "5,2,3,4,5,6"
    assert harness.Steps[2].Name == "e"
    assert harness.Steps[3].Name == "e"
}

test "a bare catch declares its variable as Exception" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResOneCatch(null, "e"), false), harness.Clr))

    declared := harness.Steps[2]
    assert declared.Kind == 3
    boxed := declared.CarriedType as object
    assert boxed.ToString() == "Exception"
}

test "the catch scope and the catch variable are positioned at the TRY, not at the clause" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResOneCatch("AppError", "e"), false), harness.Clr))

    // The clause's own type reference is at 9:11; the try statement is at 7:5.
    assert harness.Steps[1].Kind == 2
    assert harness.Steps[1].Line == 7
    assert harness.Steps[1].Column == 5
    assert harness.Steps[2].Line == 7
    assert harness.Steps[2].Column == 5
}

test "two catch clauses replay the whole sequence and every scope is closed" {
    harness := ResHarnessNew()
    clauses := ResOneCatch("AppError", "first")
    clauses.Add(ResCatch(null, null))
    ResRun(harness, harness.Owner.BeginTry(ResTry(clauses, false), harness.Clr))

    assert ResKinds(harness.Steps) == "5,2,3,4,5,6,2,5,6"
    assert harness.ScopeDepth == 0
    assert harness.MaxScopeDepth == 1
}

test "a non-throwable catch type reports NL202 against the type reference" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResOneCatch("Widget", "e"), false), harness.Clr))

    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Code == ErrorCode.TypeMismatch
    assert reported.Message
        == "Catch type must be assignable to System.Exception, but this type is 'Widget'"
    assert reported.Suggestion
        == "Catch Exception or an Exception-derived type, or use a bare catch for all exceptions."
    assert reported.Line == 9
    assert reported.Column == 11
}

test "a throwable catch type and a bare catch both report nothing" {
    typed := ResHarnessNew()
    ResRun(typed, typed.Owner.BeginTry(ResTry(ResOneCatch("AppError", "e"), false), typed.Clr))
    bare := ResHarnessNew()
    ResRun(bare, bare.Owner.BeginTry(ResTry(ResOneCatch(null, "e"), false), bare.Clr))

    assert typed.Errors.Count == 0
    assert bare.Errors.Count == 0
}

test "the catch report fires BEFORE the variable is declared" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResOneCatch("Widget", "e"), false), harness.Clr))

    // The scope open is still clean; the declare step already sees the diagnostic.
    assert harness.Steps[1].ErrorsBefore == 0
    assert harness.Steps[2].ErrorsBefore == 1
}

test "a finally raises the ambient depth for exactly its own body and lowers it after" {
    harness := ResHarnessNew()
    before := harness.Ambient.FinallyDepth
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResNoCatches(), true), harness.Clr))

    assert ResKinds(harness.Steps) == "5,5"
    // The try block runs at the entry depth; the finally block runs one deeper.
    assert harness.Steps[0].FinallyDepth == before
    assert harness.Steps[1].FinallyDepth == before + 1
    assert harness.Ambient.FinallyDepth == before
}

test "a try with no finally never touches the ambient depth" {
    harness := ResHarnessNew()
    before := harness.Ambient.FinallyDepth
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResOneCatch(null, null), false), harness.Clr))

    index := 0
    while index < harness.Steps.Count {
        assert harness.Steps[index].FinallyDepth == before
        index = index + 1
    }

    assert harness.Ambient.FinallyDepth == before
}

test "catch clauses and a finally run in that order" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginTry(ResTry(ResOneCatch(null, null), true), harness.Clr))

    assert ResKinds(harness.Steps) == "5,2,5,6,5"
    assert harness.Steps[4].FinallyDepth == 1
}

// ── the `using` walk ──────────────────────────────────────────────────────

test "a using DECLARATION runs the nested local-declaration walk inside the scope" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithDeclaration("handle", true), harness.Assignability))

    assert ResKinds(harness.Steps) == "2,7,5,6"
    assert harness.Steps[1].HasDeclaration
    assert harness.ScopeDepth == 0
}

test "a using EXPRESSION is analysed instead, and never asks for a declaration walk" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithExpression(ResName("handle"), true), harness.Assignability))

    assert ResKinds(harness.Steps) == "2,1,5,6"
}

test "a using with no body still opens and closes its scope" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithExpression(ResName("handle"), false), harness.Assignability))

    assert ResKinds(harness.Steps) == "2,1,6"
}

test "the using scope opens at the using statement's own position" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithDeclaration("handle", true), harness.Assignability))

    assert harness.Steps[0].Kind == 2
    assert harness.Steps[0].Line == 7
    assert harness.Steps[0].Column == 5
}

test "a declared resource whose own declaration FAILED is not also told it is not disposable" {
    harness := ResHarnessNew()
    harness.ErrorsOnDeclaration = 1
    harness.DeclaredResourceType = harness.Scopes.LookupType("Widget")
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithDeclaration("handle", true), harness.Assignability))

    // Exactly the injected one — the disposability rule is suppressed by the error-count guard.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "injected"
}

test "a clean declaration of a non-disposable type reports NL103 at the declared NAME" {
    harness := ResHarnessNew()
    harness.DeclaredResourceType = harness.Scopes.LookupType("Widget")
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithDeclaration("handle", true), harness.Assignability))

    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Code == ErrorCode.InvalidSyntax
    assert reported.Message
        == "Using resource of type 'Widget' must implement IDisposable or provide Dispose(): void"
    assert reported.Suggestion
        == "Use a resource type with a parameterless void Dispose method, or remove the using statement."
    assert reported.Line == 7
    assert reported.Column == 11
}

test "a declared type that carries the Dispose PATTERN is accepted without naming IDisposable" {
    harness := ResHarnessNew()
    harness.DeclaredResourceType = harness.Scopes.LookupType("Handle")
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithDeclaration("handle", true), harness.Assignability))

    assert harness.Errors.Count == 0
}

test "a reflected IDisposable resource expression is accepted" {
    harness := ResHarnessNew()
    harness.Answers.Add(ResReflected("System.IO.MemoryStream"))
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithExpression(ResName("stream"), true), harness.Assignability))

    assert harness.Errors.Count == 0
}

test "an unknown resource type is accepted, because it already carries its own error" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithExpression(ResName("mystery"), true), harness.Assignability))

    assert harness.Errors.Count == 0
}

test "a non-disposable resource EXPRESSION reports against the whole expression" {
    harness := ResHarnessNew()
    widget := harness.Scopes.LookupType("Widget")
    assert widget != null
    harness.Answers.Add(widget)
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithExpression(ResName("widget"), true), harness.Assignability))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 5
}

test "a row-view resource escapes and the column probe does NOT also run" {
    harness := ResHarnessNew()
    ResDeclareSoaTable(harness)
    rowView: TypeInfo = ResRowType()
    harness.Answers.Add(rowView)
    // A column read BY SYNTAX whose ANSWERED type is a row view. `print` says both; `using`
    // short-circuits at the first, and it is not told about disposability either.
    ResRun(harness, harness.Owner.BeginUsing(ResUsingWithExpression(ResSoaColumnRead(), true), harness.Assignability))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "SoA row views cannot be used as a using resource; use the table and row index instead"
}

// ── the `lock` walk ───────────────────────────────────────────────────────

test "a lock analyses the lockee, then opens a scope, walks the body and closes it" {
    harness := ResHarnessNew()
    ResRun(harness, harness.Owner.BeginLock(ResLock(ResName("gate")), null))

    assert ResKinds(harness.Steps) == "1,2,5,6"
    assert harness.Steps[1].Line == 7
    assert harness.Steps[1].Column == 5
}

test "a value-typed lockee reports NL320 with the plain suggestion" {
    harness := ResHarnessNew()
    harness.Answers.Add(BuiltInTypes.Int)
    ResRun(harness, harness.Owner.BeginLock(ResLock(ResName("counter")), null))

    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Code == ErrorCode.LockRequiresReferenceType
    assert reported.Message == "'int' is not a reference type as required by the lock statement"
    assert reported.Suggestion
        == "Lock on a dedicated `object` field instead: `sync: object = new object()`"
}

test "the lockee report fires BEFORE the body scope opens" {
    harness := ResHarnessNew()
    harness.Answers.Add(BuiltInTypes.Int)
    ResRun(harness, harness.Owner.BeginLock(ResLock(ResName("counter")), null))

    assert harness.Steps[0].ErrorsBefore == 0
    assert harness.Steps[1].Kind == 2
    assert harness.Steps[1].ErrorsBefore == 1
}

test "a class lockee and an unclassifiable lockee are both silent" {
    declared := ResHarnessNew()
    widget := declared.Scopes.LookupType("Widget")
    assert widget != null
    declared.Answers.Add(widget)
    ResRun(declared, declared.Owner.BeginLock(ResLock(ResName("gate")), null))

    external := ResHarnessNew()
    externalType: TypeInfo = new ExternalTypeInfo("Some.Package.Gate")
    external.Answers.Add(externalType)
    ResRun(external, external.Owner.BeginLock(ResLock(ResName("gate")), null))

    unknown := ResHarnessNew()
    ResRun(unknown, unknown.Owner.BeginLock(ResLock(ResName("gate")), null))

    assert declared.Errors.Count == 0
    assert external.Errors.Count == 0
    assert unknown.Errors.Count == 0
}

test "an UNCONSTRAINED type parameter lockee reports the type-parameter suggestion" {
    harness := ResHarnessNew()
    harness.Ambient.EnterFunctionDeclaration(ResFunction("run", ResTypeParameters("T"), null), BuiltInTypes.Void)
    lockeeType: TypeInfo = new SimpleTypeInfo("T")
    harness.Answers.Add(lockeeType)
    ResRun(harness, harness.Owner.BeginLock(ResLock(ResName("gate")), null))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'T' is not a reference type as required by the lock statement"
    assert harness.Errors[0].Suggestion
        == "Constrain `T` to a reference type (`where T: class`), or lock on a dedicated `object` field instead: `sync: object = new object()`"
}

test "a `where T: class` type parameter lockee is silent" {
    harness := ResHarnessNew()
    harness.Ambient.EnterFunctionDeclaration(
        ResFunction("run", ResTypeParameters("T"), ResClassConstraint("T")),
        BuiltInTypes.Void)
    lockeeType: TypeInfo = new SimpleTypeInfo("T")
    harness.Answers.Add(lockeeType)
    ResRun(harness, harness.Owner.BeginLock(ResLock(ResName("gate")), null))

    assert harness.Errors.Count == 0
}

func ResGenericClass(name: string, typeParameterName: string): ClassDeclaration {
    return new ClassDeclaration(
        name,
        ResTypeParameters(typeParameterName),
        null,
        new List<TypeReference>(),
        new List<Declaration>(),
        null,
        Modifiers.None,
        new List<AttributeNode>(),
        1,
        1)
}

test "a type parameter of the enclosing CLASS is recognised too" {
    harness := ResHarnessNew()
    lockeeType: TypeInfo = new SimpleTypeInfo("T")
    harness.Answers.Add(lockeeType)
    ResRun(harness, harness.Owner.BeginLock(ResLock(ResName("gate")), ResGenericClass("Box", "T")))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'T' is not a reference type as required by the lock statement"
}

test "a row-view lockee escapes and is NOT also told it is not a reference type" {
    harness := ResHarnessNew()
    rowView: TypeInfo = ResRowType()
    harness.Answers.Add(rowView)
    ResRun(harness, harness.Owner.BeginLock(ResLock(ResName("particle")), null))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "SoA row views cannot be locked; use the table and row index instead"
}

test "a direct-column lockee escapes AND the value-type arm still reports" {
    harness := ResHarnessNew()
    ResDeclareSoaTable(harness)
    harness.Answers.Add(BuiltInTypes.Int)
    ResRun(harness, harness.Owner.BeginLock(ResLock(ResSoaColumnRead()), null))

    // The gate is an else-if CHAIN: the column escape kills only the type-parameter arm, and an
    // `int` column read gets BOTH squiggles. This is the one line that no diagnostic diff over
    // compiling code could ever catch.
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be locked directly"
    assert harness.Errors[1].Code == ErrorCode.LockRequiresReferenceType
}

// ── the state's own bookkeeping ───────────────────────────────────────────

test "every Begin hands back a fresh state in its own phase band" {
    harness := ResHarnessNew()
    tryState := harness.Owner.BeginTry(ResTry(ResNoCatches(), false), harness.Clr)
    usingState := harness.Owner.BeginUsing(ResUsingWithExpression(ResName("handle"), true), harness.Assignability)
    lockState := harness.Owner.BeginLock(ResLock(ResName("gate")), null)

    assert tryState.Phase == 0
    assert usingState.Phase == 10
    assert lockState.Phase == 20
    assert tryState.Form == 0
    assert usingState.Form == 1
    assert lockState.Form == 2
}

test "each form carries ONLY the collaborators its own walk asks for" {
    harness := ResHarnessNew()
    tryState := harness.Owner.BeginTry(ResTry(ResNoCatches(), false), harness.Clr)
    usingState := harness.Owner.BeginUsing(ResUsingWithExpression(ResName("handle"), true), harness.Assignability)
    lockState := harness.Owner.BeginLock(ResLock(ResName("gate")), null)

    assert tryState.ClrTypeConversion != null
    assert tryState.Assignability == null
    assert usingState.Assignability != null
    assert usingState.ClrTypeConversion == null
    assert lockState.ClrTypeConversion == null
    assert lockState.Assignability == null
    assert tryState.TryNode != null
    assert usingState.UsingNode != null
    assert lockState.LockNode != null
}

test "two walks over the same try do not share state" {
    harness := ResHarnessNew()
    statement := ResTry(ResOneCatch("AppError", "e"), true)
    ResRun(harness, harness.Owner.BeginTry(statement, harness.Clr))
    first := ResKinds(harness.Steps)
    ResRun(harness, harness.Owner.BeginTry(statement, harness.Clr))

    assert first == ResKinds(harness.Steps)
    assert harness.Ambient.FinallyDepth == 0
}

namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT A PROPERTY'S AND AN INDEXER'S ACCESSORS MEAN.
//
// `AnalyzePropertyDeclaration`, `AnalyzeIndexerDeclaration` and `DeclareIndexerParameters` were all
// `private` in `Analyzer.cs`, so nothing named them: their behaviour was pinned only indirectly,
// through whatever end-to-end diagnostic a broken accessor happened to produce. This is their first
// DIRECT pinning, and it is written around the six things this family is easy to get wrong.
//
// (1) THE FAMILY IS A PAIR, SO THE SCOPE BALANCE IS PER ACCESSOR AND NOT PER DECLARATION. A
// `{ get set }` property opens TWO function scopes and closes TWO, in strict alternation; a getter-only
// property opens one; a property with no accessors at all opens none and still declares its name and
// records itself twice. A walk that opened one scope for the pair would compile every program and
// silently let a getter's locals leak into the setter.
//
// (2) THE SETTER'S BOUNDARY AND THE SETTER'S `value` CARRY TWO DIFFERENT TYPES AT THE SAME INSTANT.
// The accessor return type is `void` — which is what makes a bare `return` legal inside a setter and
// `return x` not — while `value` is declared under the PROPERTY's type. Getting that backwards would
// type every setter's `value` as `void` and be invisible until someone assigned it.
//
// (3) `value` IS DECLARED WITHOUT A BINDING DECLARATION. It has no position in the source, so
// go-to-definition has nothing to land on; the operand that says so is carried on the declare step
// rather than inferred from the name.
//
// (4) AN INDEXER DECLARES ITS PARAMETERS ONCE PER ACCESSOR, INSIDE THAT ACCESSOR'S SCOPE — but
// VALIDATES its list exactly once, OUTSIDE both. A function does the opposite: validates inside its one
// scope and declares once. Both halves are asserted, because a walk that validated per accessor would
// double every parameter-list diagnostic on a `{ get set }` indexer.
//
// (5) THE NAMING CONVENTION IS ASKED FOR BEFORE THE TYPE IS RESOLVED. The type resolver REPORTS, and
// `_errors` is one list whose order is the reported order, so resolving first would move the
// convention report behind an unknown-type report.
//
// (6) THE EXPRESSION-BODY MISMATCH HAS TWO SHAPES WITH TWO DIFFERENT CODES. The rich shape points at
// the EXPRESSION and reports a type mismatch; the detail-only shape points at the DECLARATION and
// reports invalid syntax, because that is what the three-argument `Error` overload it replaces
// defaulted to.
class AccessorHarness {
    Accessors: AnalyzerAccessorBodies
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Errors: List<CompilerError>
    Assignability: AnalyzerAssignability
    Model: SemanticModel

    constructor(accessors: AnalyzerAccessorBodies, ambient: AnalyzerAmbientContext, scopes: AnalyzerScopeStack, errors: List<CompilerError>, assignability: AnalyzerAssignability, model: SemanticModel) {
        Accessors = accessors
        Ambient = ambient
        Scopes = scopes
        Errors = errors
        Assignability = assignability
        Model = model
    }
}

// One replayed step, with the scope DEPTH, the ambient RETURN TYPE and the error count AS THE STEP WAS
// HANDED OUT — which is what pins the window each operation happens in rather than only the operation
// itself. The ambient return type is on every row because the `EnterAccessorReturnType` /
// `ExitAccessorReturnType` transitions are protocol events: they are the whole reason this family did
// not fit the function walk's state.
class AccessorStep {
    Kind: int
    Node: Expression?
    ExpectedType: string
    Name: string?
    ContainingType: string?
    CarriedType: string
    RecordsBinding: bool
    ParameterCount: int
    HasBody: bool
    Line: int
    Column: int
    Depth: int
    ReturnType: string
    ErrorsBefore: int

    constructor(kind: int, node: Expression?, expectedType: string, name: string?, containingType: string?, carriedType: string, recordsBinding: bool, parameterCount: int, hasBody: bool, line: int, column: int, depth: int, returnType: string, errorsBefore: int) {
        Kind = kind
        Node = node
        ExpectedType = expectedType
        Name = name
        ContainingType = containingType
        CarriedType = carriedType
        RecordsBinding = recordsBinding
        ParameterCount = parameterCount
        HasBody = hasBody
        Line = line
        Column = column
        Depth = depth
        ReturnType = returnType
        ErrorsBefore = errorsBefore
    }
}

func AccessorPath(): string {
    return Path.GetFullPath("accessor-bodies-contract.nl")
}

func AccessorHarnessWith(sourceText: string?): AccessorHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(AccessorPath(), sourceText)
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
    resolver.BeginAnalysis(AccessorPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    accessors := new AnalyzerAccessorBodies(diagnostics, spans, resolver, ambient, escape)
    return new AccessorHarness(accessors, ambient, scopes, errors, assignability, model)
}

func AccessorDefault(): AccessorHarness {
    return AccessorHarnessWith(null)
}

func AccessorTypeText(candidate: TypeInfo?): string {
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

// ── the accessor driver, exactly as `Analyzer.cs` writes it ─────────────
//
// The scope operations are performed FOR REAL — kind 2 pushes a function scope, kind 3 writes the
// symbol, kind 5 pops — so that the depth recorded on every step is the depth the analyzer would have
// been at, and so that a name declared inside one accessor stops resolving in the next. Kind 7 records
// the body rather than re-entering the statement dispatch, which is the one thing a contract cannot
// replay.
func AccessorRun(harness: AccessorHarness, state: AccessorBodyState, answer: TypeInfo?): List<AccessorStep> {
    steps := new List<AccessorStep>()
    step := harness.Accessors.NextStep(state)
    while step != null {
        parameterCount := 0
        parameters := step.Parameters
        if parameters != null {
            parameterCount = parameters.Count
        }

        steps.Add(new AccessorStep(step.Kind, step.Node, AccessorTypeText(step.ExpectedType), step.Name, step.ContainingType, AccessorTypeText(step.CarriedType), step.RecordsBinding, parameterCount, step.Body != null, step.Line, step.Column, harness.Scopes.Count, AccessorTypeText(harness.Ambient.CurrentReturnType), harness.Errors.Count))

        if step.Kind == 2 {
            harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Function), step.Line, step.Column)
        }

        if step.Kind == 3 {
            name := step.Name
            if name != null {
                harness.Scopes.Peek().Symbols[name] = step.CarriedType
            }
        }

        if step.Kind == 5 {
            harness.Scopes.NoteLine(99)
            harness.Scopes.Pop(harness.Model)
        }

        if step.Kind == 8 {
            containing := step.ContainingType
            memberName := step.Name
            if containing != null && memberName != null {
                harness.Model.RecordTypeMember(containing, memberName, step.CarriedType)
            }
        }

        if step.Kind == 9 {
            propertyName := step.Name
            if propertyName != null {
                harness.Model.RecordProperty(propertyName, step.CarriedType)
            }
        }

        harness.Accessors.Supply(state, answer)
        step = harness.Accessors.NextStep(state)
    }

    return steps
}

func AccessorStepKinds(steps: List<AccessorStep>): string {
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

func AccessorCountKind(steps: List<AccessorStep>, kind: int): int {
    total := 0
    index := 0
    while index < steps.Count {
        if steps[index].Kind == kind {
            total = total + 1
        }

        index = index + 1
    }

    return total
}

func AccessorIntType(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("int", 7, 20)
    return reference
}

// A type reference nothing can resolve. The resolver REPORTS when it fails, which is what makes the
// convention's ordering observable in the sink now that it is no longer a step.
func AccessorMissingType(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("NoSuchTypeAnywhere", 7, 20)
    return reference
}

func AccessorStringType(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("string", 7, 20)
    return reference
}

func AccessorBareReturn(): Statement {
    bare: Statement = new ReturnStatement(null, 9, 9)
    return bare
}

func AccessorStatements(statement: Statement): List<Statement> {
    statements := new List<Statement>()
    statements.Add(statement)
    return statements
}

func AccessorBlock(line: int): BlockStatement {
    return new BlockStatement(AccessorStatements(AccessorBareReturn()), line, 5)
}

func AccessorIntLiteral(): Expression {
    literal: Expression = new IntLiteralExpression("1", 7, 30)
    return literal
}

func AccessorStringLiteral(): Expression {
    literal: Expression = new StringLiteralExpression("hi", 7, 30)
    return literal
}

func AccessorProperty(name: string, typeReference: TypeReference, getBody: BlockStatement?, setBody: BlockStatement?, expressionBody: Expression?, modifiers: Modifiers): PropertyDeclaration {
    return new PropertyDeclaration(name, typeReference, getBody, setBody, expressionBody, modifiers, PropertyModifier.None, new List<AttributeNode>(), 7, 10)
}

func AccessorParameter(name: string, typeName: string, line: int, column: int): Parameter {
    return new Parameter(name, new SimpleTypeReference(typeName, line, column), null, false, ParameterModifier.None, null, line, column, false, null)
}

func AccessorParameters(): List<Parameter> {
    return new List<Parameter>()
}

func AccessorOneParameter(parameter: Parameter): List<Parameter> {
    parameters := new List<Parameter>()
    parameters.Add(parameter)
    return parameters
}

func AccessorIndexer(parameters: List<Parameter>, typeReference: TypeReference, getBody: BlockStatement?, setBody: BlockStatement?): IndexerDeclaration {
    return new IndexerDeclaration(parameters, typeReference, getBody, setBody, Modifiers.None, new List<AttributeNode>(), 7, 10)
}

func AccessorBeginProperty(harness: AccessorHarness, declaration: PropertyDeclaration, containingType: string?): AccessorBodyState {
    return harness.Accessors.BeginProperty(declaration, containingType, harness.Assignability)
}

func AccessorBeginIndexer(harness: AccessorHarness, declaration: IndexerDeclaration, containingType: string?): AccessorBodyState {
    return harness.Accessors.BeginIndexer(declaration, containingType, harness.Assignability)
}

func AccessorErrorText(harness: AccessorHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + "+" + error.Length.ToString()
}

// ---------------------------------------------------------------------------------------------
// THE PROPERTY ENTRY, AND THE ORDER THAT IS THE FEATURE
// ---------------------------------------------------------------------------------------------

test "A PROPERTY WITH NEITHER ACCESSOR STILL DECLARES ITS NAME AND WRITES BOTH IDE RECORDS" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), null, null, null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    // The name, the type member, the property. No scope, no body, nothing else — and `X: int { }` is
    // a shape the parser really does produce. The convention is checked too, but it is no longer a
    // STEP: it moved to `AnalyzerDeclarationConventions` and this walk calls it directly, so a
    // convention-clean name leaves no trace here at all.
    assert AccessorStepKinds(steps) == "3,8,9"
    assert harness.Errors.Count == 0
}

test "THE NAMING CONVENTION IS CHECKED BEFORE THE TYPE IS RESOLVED, AND IT IS NO LONGER A STEP" {
    harness := AccessorDefault()
    unclassifiable := AccessorProperty("_hidden", AccessorMissingType(), null, null, null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, unclassifiable, "Box"), null)

    // The convention report is made by the walk ITSELF now, so it lands in the sink rather than in
    // the step stream — and it lands FIRST, ahead of the unresolved-type report the resolver makes,
    // which is exactly the ordering the step used to guarantee. `_errors` is one list whose order is
    // the reported order.
    assert harness.Errors.Count >= 2
    assert harness.Errors[0].Code == ErrorCode.VisibilityConventionWarning
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 10
    assert harness.Errors[1].Code != ErrorCode.VisibilityConventionWarning
    // And the FIRST step is the name declaration, carrying the resolved type: nothing precedes it.
    assert steps[0].Kind == 3
    assert steps[0].Name == "_hidden"

    clean := AccessorDefault()
    cleanSteps := AccessorRun(clean, AccessorBeginProperty(clean, AccessorProperty("Total", AccessorIntType(), null, null, null, Modifiers.None), "Box"), null)
    assert clean.Errors.Count == 0
    assert cleanSteps[0].Kind == 3
    assert cleanSteps[0].CarriedType == "int"
}

test "THE PROPERTY'S NAME IS DECLARED IN THE ENCLOSING SCOPE, NOT IN EITHER ACCESSOR'S" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), AccessorBlock(8), AccessorBlock(9), null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    // The declare step is at the OUTER depth, before any scope has opened.
    assert steps[0].Kind == 3
    assert steps[0].Depth == 1
    assert steps[0].RecordsBinding
    // And it is still visible after the whole walk, while nothing the accessors declared is.
    assert harness.Scopes.Count == 1
    assert harness.Scopes.Peek().Symbols.ContainsKey("Total")
    assert !harness.Scopes.Peek().Symbols.ContainsKey("value")
}

test "THE TWO IDE RECORDS HAPPEN IN ONE ORDER: THE TYPE MEMBER, THEN THE PROPERTY" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), null, null, null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    assert steps[1].Kind == 8
    assert steps[1].ContainingType == "Box"
    assert steps[1].Name == "Total"
    assert steps[1].CarriedType == "int"
    assert steps[2].Kind == 9
    assert steps[2].ContainingType == null
    assert steps[2].Name == "Total"
    assert steps[2].CarriedType == "int"
    // Both tables the IDE reads, written for real by the replay driver.
    members := harness.Model.GetTypeMembers("Box")
    assert members != null
    assert members.ContainsKey("Total")
    assert harness.Model.Properties.ContainsKey("Total")
}

test "A PROPERTY OUTSIDE EVERY TYPE ASKS FOR NO TYPE-MEMBER STEP AT ALL" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), null, null, null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, null), null)

    // The step is not asked for and then ignored — it is never asked for, so the driver decides
    // nothing.
    assert AccessorStepKinds(steps) == "3,9"
    assert AccessorCountKind(steps, 8) == 0
    assert harness.Model.Properties.ContainsKey("Total")
}

// ---------------------------------------------------------------------------------------------
// THE EXPRESSION BODY
// ---------------------------------------------------------------------------------------------

test "AN EXPRESSION-BODIED PROPERTY IS WALKED UNDER ITS OWN TYPE, AFTER BOTH IDE RECORDS" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), null, null, AccessorIntLiteral(), Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), BuiltInTypes.Int)

    assert AccessorStepKinds(steps) == "3,8,9,1"
    assert steps[3].Kind == 1
    assert steps[3].ExpectedType == "int"
    assert steps[3].Node != null
    assert steps[3].Depth == 1
    assert harness.Errors.Count == 0
}

test "AN EXPRESSION BODY THAT DOES NOT FIT IS REPORTED AT THE EXPRESSION WITH THE RICH BUILDER" {
    harness := AccessorHarnessWith("\n\n\n\n\n\n    Total: int => \"hi\"\n")
    declaration := AccessorProperty("Total", AccessorIntType(), null, null, AccessorStringLiteral(), Modifiers.None)

    AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), BuiltInTypes.String)

    // With source text the report lands on the EXPRESSION's span, not on the declaration's.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 30

    // The CODE and the ANCHOR differ between the two shapes; the SENTENCE does not. The rich route
    // used to say only the bare words `Type mismatch`.
    assert harness.Errors[0].Message == "Property 'Total' is typed as 'int', but the expression body returns 'string'"
}

test "WITHOUT SOURCE TEXT THE SAME MISMATCH IS INVALID-SYNTAX AT THE DECLARATION, NOT TYPE-MISMATCH" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), null, null, AccessorStringLiteral(), Modifiers.None)

    AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), BuiltInTypes.String)

    // The three-argument `Error` overload this replaces defaulted to InvalidSyntax, and the detail-only
    // shape is exactly what an unsaved editor buffer produces — so the code difference is a shipped
    // difference rather than an accident.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert AccessorErrorText(harness, 0) == "Property 'Total' is typed as 'int', but the expression body returns 'string'|7:10+1"
}

test "AN EXPRESSION BODY THAT FITS IS SILENT" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), null, null, AccessorIntLiteral(), Modifiers.None)

    AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), BuiltInTypes.Int)

    assert harness.Errors.Count == 0
}

test "AN UNANSWERED EXPRESSION BODY IS MEASURED AS UNKNOWN RATHER THAN CRASHING" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), null, null, AccessorIntLiteral(), Modifiers.None)

    AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    // `unknown` is assignable to everything, so a walk that answered nothing stays silent — which is
    // what keeps a first failure from producing a second complaint.
    assert harness.Errors.Count == 0
}

test "AN EXPRESSION BODY AND ACCESSORS COEXIST, AND THE EXPRESSION BODY GOES FIRST" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), AccessorBlock(8), null, AccessorIntLiteral(), Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), BuiltInTypes.Int)

    assert AccessorStepKinds(steps) == "3,8,9,1,2,7,5"
}

// ---------------------------------------------------------------------------------------------
// THE ACCESSOR PAIR
// ---------------------------------------------------------------------------------------------

test "A GETTER OPENS A FUNCTION SCOPE, WALKS ITS BLOCK THROUGH THE DISPATCH AND CLOSES" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), AccessorBlock(8), null, null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    assert AccessorStepKinds(steps) == "3,8,9,2,7,5"
    assert steps[3].Kind == 2
    assert steps[3].Line == 7
    assert steps[3].Column == 10
    // The body is ONE statement through the dispatch, inside the accessor's own scope — not a list.
    assert steps[4].Kind == 7
    assert steps[4].HasBody
    assert steps[4].Depth == 2
    assert steps[5].Kind == 5
}

test "A SETTER DECLARES `value` BETWEEN ITS BOUNDARY AND ITS BODY, AND RECORDS IT NEXT" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), null, AccessorBlock(9), null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    assert AccessorStepKinds(steps) == "3,8,9,2,3,4,7,5"
    assert steps[4].Kind == 3
    assert steps[4].Name == "value"
    assert steps[4].Depth == 2
    assert steps[5].Kind == 4
    assert steps[5].Name == "value"
}

test "`value` IS DECLARED WITHOUT A BINDING DECLARATION, AND EVERY OTHER NAME WITH ONE" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), null, AccessorBlock(9), null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    // The property's own name records a binding; `value` does not, because there is no position in the
    // source for go-to-definition to land on.
    assert steps[0].Name == "Total"
    assert steps[0].RecordsBinding
    assert steps[4].Name == "value"
    assert !steps[4].RecordsBinding
}

test "`value` IS TYPED BY THE PROPERTY WHILE THE BOUNDARY HOLDS VOID — TWO TYPES AT ONE INSTANT" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorStringType(), null, AccessorBlock(9), null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    // The declare step carries `string` — the property's type — while the ambient return type recorded
    // on the SAME row is `void`, which is what makes `return x` inside a setter wrong and `value = x`
    // right.
    assert steps[4].Name == "value"
    assert steps[4].CarriedType == "string"
    assert steps[4].ReturnType == "void"
    assert steps[5].CarriedType == "string"
    assert steps[5].ReturnType == "void"
}

test "A GETTER'S BOUNDARY HOLDS THE PROPERTY TYPE AND A SETTER'S HOLDS VOID" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorStringType(), AccessorBlock(8), AccessorBlock(9), null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    // Row 5 is the getter's body and row 10 is the setter's; the boundary transition is visible in the
    // row stream rather than only in the implementation.
    assert steps[4].Kind == 7
    assert steps[4].ReturnType == "string"
    assert steps[9].Kind == 7
    assert steps[9].ReturnType == "void"
}

test "A GET-AND-SET PROPERTY OPENS TWO SCOPES AND CLOSES TWO, STRICTLY ALTERNATING" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), AccessorBlock(8), AccessorBlock(9), null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    assert AccessorStepKinds(steps) == "3,8,9,2,7,5,2,3,4,7,5"
    assert AccessorCountKind(steps, 2) == 2
    assert AccessorCountKind(steps, 5) == 2
    // The getter's scope is CLOSED before the setter's opens: neither accessor can see the other's
    // names, which a single shared scope would silently allow.
    assert steps[5].Kind == 5
    assert steps[6].Kind == 2
    assert steps[6].Depth == 1
}

test "THE GETTER IS WALKED BEFORE THE SETTER, AND A MISSING ACCESSOR IS SKIPPED ENTIRELY" {
    harness := AccessorDefault()
    getterOnly := AccessorProperty("A", AccessorIntType(), AccessorBlock(8), null, null, Modifiers.None)
    setterOnly := AccessorProperty("B", AccessorIntType(), null, AccessorBlock(9), null, Modifiers.None)

    getterSteps := AccessorRun(harness, AccessorBeginProperty(harness, getterOnly, "Box"), null)
    setterSteps := AccessorRun(harness, AccessorBeginProperty(harness, setterOnly, "Box"), null)

    // A getter-only property never asks for a `value` declaration; a setter-only one always does.
    assert AccessorCountKind(getterSteps, 3) == 1
    assert AccessorCountKind(setterSteps, 3) == 2
    assert AccessorCountKind(getterSteps, 2) == 1
    assert AccessorCountKind(setterSteps, 2) == 1
}

// ---------------------------------------------------------------------------------------------
// THE BOUNDARY'S SAVE AND RESTORE
// ---------------------------------------------------------------------------------------------

test "THE BOUNDARY RESTORES THE ENCLOSING RETURN TYPE AFTER EVERY ACCESSOR" {
    harness := AccessorDefault()
    saved := harness.Ambient.EnterAccessorReturnType(BuiltInTypes.Double)
    declaration := AccessorProperty("Total", AccessorIntType(), AccessorBlock(8), AccessorBlock(9), null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    // Inside the getter it is `int`, inside the setter `void`, and after the walk it is `double` again
    // — the enclosing value, restored rather than nulled. That is the difference from the FUNCTION
    // DECLARATION boundary, which deliberately restores null.
    assert steps[4].ReturnType == "int"
    assert steps[9].ReturnType == "void"
    assert AccessorTypeText(harness.Ambient.CurrentReturnType) == "double"
    harness.Ambient.ExitAccessorReturnType(saved)
}

test "AN ACCESSOR ANALYSED OUTSIDE EVERY FUNCTION RESTORES A NULL RETURN TYPE, NOT NOTHING" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), AccessorBlock(8), null, null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    // The rows before the scope opens read `<null>`, the body row reads the property's type, and the
    // close row reads `<null>` again — the save/restore is a bare `TypeInfo?` and its null is real.
    assert steps[0].ReturnType == "<null>"
    assert steps[4].ReturnType == "int"
    assert steps[5].ReturnType == "<null>"
    assert AccessorTypeText(harness.Ambient.CurrentReturnType) == "<null>"
}

// ---------------------------------------------------------------------------------------------
// THE INDEXER ENTRY
// ---------------------------------------------------------------------------------------------

test "AN INDEXER DECLARES NO NAME, CHECKS NO CONVENTION AND RECORDS NOTHING FOR THE IDE" {
    harness := AccessorDefault()
    declaration := AccessorIndexer(AccessorOneParameter(AccessorParameter("i", "int", 7, 18)), AccessorStringType(), AccessorBlock(8), null)

    steps := AccessorRun(harness, AccessorBeginIndexer(harness, declaration, "Box"), null)

    assert AccessorStepKinds(steps) == "6,2,3,4,7,5"
    assert AccessorCountKind(steps, 8) == 0
    assert AccessorCountKind(steps, 9) == 0
}

test "THE INDEXER'S PARAMETER LIST IS VALIDATED ONCE, OUTSIDE BOTH ACCESSOR SCOPES" {
    harness := AccessorDefault()
    declaration := AccessorIndexer(AccessorOneParameter(AccessorParameter("i", "int", 7, 18)), AccessorStringType(), AccessorBlock(8), AccessorBlock(9))

    steps := AccessorRun(harness, AccessorBeginIndexer(harness, declaration, "Box"), null)

    // ONE relay step, at the outer depth and before any scope opens — a function validates its list
    // INSIDE its scope, and validating per accessor would double every list diagnostic here.
    assert AccessorCountKind(steps, 6) == 1
    assert steps[0].Kind == 6
    assert steps[0].Depth == 1
    assert steps[0].ParameterCount == 1
    assert steps[0].Line == 7
    assert steps[0].Column == 10
}

test "THE INDEXER'S PARAMETERS ARE DECLARED AGAIN INSIDE EACH ACCESSOR'S OWN SCOPE" {
    harness := AccessorDefault()
    parameters := AccessorOneParameter(AccessorParameter("i", "int", 7, 18))
    parameters.Add(AccessorParameter("j", "int", 7, 26))
    declaration := AccessorIndexer(parameters, AccessorStringType(), AccessorBlock(8), AccessorBlock(9))

    steps := AccessorRun(harness, AccessorBeginIndexer(harness, declaration, "Box"), null)

    // Two parameters, two accessors: the declare/record pair runs FOUR times, and every one of them is
    // inside a scope. The setter adds `value` on top.
    assert AccessorStepKinds(steps) == "6,2,3,4,3,4,7,5,2,3,4,3,4,3,4,7,5"
    assert steps[2].Name == "i"
    assert steps[2].Depth == 2
    assert steps[4].Name == "j"
    assert steps[10].Name == "i"
    assert steps[10].Depth == 2
    assert steps[12].Name == "j"
    assert steps[13].Name == "value"
}

test "AN INDEXER PARAMETER IS DECLARED AT ITS OWN POSITION, AND FALLS BACK TO THE DECLARATION'S" {
    harness := AccessorDefault()
    parameters := AccessorOneParameter(AccessorParameter("i", "int", 7, 18))
    parameters.Add(AccessorParameter("j", "int", 0, 0))
    declaration := AccessorIndexer(parameters, AccessorStringType(), AccessorBlock(8), null)

    steps := AccessorRun(harness, AccessorBeginIndexer(harness, declaration, "Box"), null)

    assert steps[2].Line == 7
    assert steps[2].Column == 18
    // A synthesised parameter squiggles the declaration rather than line zero.
    assert steps[4].Line == 7
    assert steps[4].Column == 10
}

test "AN INDEXER SETTER'S `value` IS TYPED BY THE INDEXER, AFTER ITS PARAMETERS" {
    harness := AccessorDefault()
    declaration := AccessorIndexer(AccessorOneParameter(AccessorParameter("i", "int", 7, 18)), AccessorStringType(), null, AccessorBlock(9))

    steps := AccessorRun(harness, AccessorBeginIndexer(harness, declaration, "Box"), null)

    assert AccessorStepKinds(steps) == "6,2,3,4,3,4,7,5"
    assert steps[2].Name == "i"
    assert steps[2].CarriedType == "int"
    assert steps[4].Name == "value"
    assert steps[4].CarriedType == "string"
    assert !steps[4].RecordsBinding
    assert steps[4].ReturnType == "void"
}

test "AN INDEXER WITH NO PARAMETERS STILL VALIDATES ITS EMPTY LIST AND OPENS ITS SCOPE" {
    harness := AccessorDefault()
    declaration := AccessorIndexer(AccessorParameters(), AccessorStringType(), AccessorBlock(8), null)

    steps := AccessorRun(harness, AccessorBeginIndexer(harness, declaration, "Box"), null)

    assert AccessorStepKinds(steps) == "6,2,7,5"
    assert steps[0].ParameterCount == 0
}

test "AN INDEXER WITH NEITHER ACCESSOR VALIDATES ITS LIST AND STOPS" {
    harness := AccessorDefault()
    declaration := AccessorIndexer(AccessorOneParameter(AccessorParameter("i", "int", 7, 18)), AccessorStringType(), null, null)

    steps := AccessorRun(harness, AccessorBeginIndexer(harness, declaration, "Box"), null)

    assert AccessorStepKinds(steps) == "6"
    assert harness.Scopes.Count == 1
}

test "AN INDEXER'S PARAMETERS STOP RESOLVING WHEN ITS ACCESSOR CLOSES" {
    harness := AccessorDefault()
    declaration := AccessorIndexer(AccessorOneParameter(AccessorParameter("i", "int", 7, 18)), AccessorStringType(), AccessorBlock(8), null)

    AccessorRun(harness, AccessorBeginIndexer(harness, declaration, "Box"), null)

    assert harness.Scopes.Count == 1
    assert !harness.Scopes.Peek().Symbols.ContainsKey("i")
}

// ---------------------------------------------------------------------------------------------
// THE BALANCE INVARIANTS, OVER A MATRIX OF SHAPES
// ---------------------------------------------------------------------------------------------

func AccessorShapeMatrix(): List<AccessorBodyState> {
    return new List<AccessorBodyState>()
}

test "EVERY SHAPE OPENS EXACTLY AS MANY SCOPES AS IT CLOSES, AND THE DEPTH COMES BACK" {
    harness := AccessorDefault()
    shapes := AccessorShapeMatrix()
    shapes.Add(AccessorBeginProperty(harness, AccessorProperty("A", AccessorIntType(), null, null, null, Modifiers.None), "Box"))
    shapes.Add(AccessorBeginProperty(harness, AccessorProperty("B", AccessorIntType(), AccessorBlock(8), null, null, Modifiers.None), "Box"))
    shapes.Add(AccessorBeginProperty(harness, AccessorProperty("C", AccessorIntType(), null, AccessorBlock(9), null, Modifiers.None), "Box"))
    shapes.Add(AccessorBeginProperty(harness, AccessorProperty("D", AccessorIntType(), AccessorBlock(8), AccessorBlock(9), null, Modifiers.None), "Box"))
    shapes.Add(AccessorBeginProperty(harness, AccessorProperty("E", AccessorIntType(), null, null, AccessorIntLiteral(), Modifiers.None), null))
    shapes.Add(AccessorBeginIndexer(harness, AccessorIndexer(AccessorOneParameter(AccessorParameter("i", "int", 7, 18)), AccessorStringType(), AccessorBlock(8), AccessorBlock(9)), "Box"))
    shapes.Add(AccessorBeginIndexer(harness, AccessorIndexer(AccessorParameters(), AccessorStringType(), null, null), "Box"))
    shapes.Add(AccessorBeginIndexer(harness, AccessorIndexer(AccessorOneParameter(AccessorParameter("i", "int", 0, 0)), AccessorStringType(), null, AccessorBlock(9)), null))

    index := 0
    while index < shapes.Count {
        startDepth := harness.Scopes.Count
        steps := AccessorRun(harness, shapes[index], BuiltInTypes.Int)
        assert AccessorCountKind(steps, 2) == AccessorCountKind(steps, 5)
        assert harness.Scopes.Count == startDepth
        index = index + 1
    }
}

test "IN EVERY SHAPE THE LAST STEP OF EACH ACCESSOR IS ITS CLOSE, AND NO CLOSE PRECEDES ITS OPEN" {
    harness := AccessorDefault()
    shapes := AccessorShapeMatrix()
    shapes.Add(AccessorBeginProperty(harness, AccessorProperty("A", AccessorIntType(), AccessorBlock(8), AccessorBlock(9), null, Modifiers.None), "Box"))
    shapes.Add(AccessorBeginProperty(harness, AccessorProperty("B", AccessorIntType(), null, AccessorBlock(9), null, Modifiers.None), "Box"))
    shapes.Add(AccessorBeginIndexer(harness, AccessorIndexer(AccessorOneParameter(AccessorParameter("i", "int", 7, 18)), AccessorStringType(), AccessorBlock(8), AccessorBlock(9)), "Box"))

    index := 0
    while index < shapes.Count {
        steps := AccessorRun(harness, shapes[index], null)
        open := 0
        position := 0
        while position < steps.Count {
            kind := steps[position].Kind
            if kind == 2 {
                open = open + 1
            }

            if kind == 5 {
                open = open - 1
            }

            // The running balance never goes negative and never exceeds one: accessors nest not at all.
            assert open >= 0
            assert open <= 1
            position = position + 1
        }

        assert open == 0
        assert steps[steps.Count - 1].Kind == 5
        index = index + 1
    }
}

test "NO SHAPE EVER ASKS FOR A STEP OUTSIDE THE TEN KINDS THIS PROTOCOL DEFINES" {
    harness := AccessorDefault()
    shapes := AccessorShapeMatrix()
    shapes.Add(AccessorBeginProperty(harness, AccessorProperty("A", AccessorIntType(), AccessorBlock(8), AccessorBlock(9), AccessorIntLiteral(), Modifiers.None), "Box"))
    shapes.Add(AccessorBeginIndexer(harness, AccessorIndexer(AccessorOneParameter(AccessorParameter("i", "int", 7, 18)), AccessorStringType(), AccessorBlock(8), AccessorBlock(9)), "Box"))

    index := 0
    while index < shapes.Count {
        steps := AccessorRun(harness, shapes[index], BuiltInTypes.Int)
        position := 0
        while position < steps.Count {
            kind := steps[position].Kind
            assert kind >= 1
            assert kind <= 10
            position = position + 1
        }

        index = index + 1
    }
}

test "AT MOST ONE `value` IS DECLARED PER ACCESSOR, AND NEVER IN A GETTER" {
    harness := AccessorDefault()
    declaration := AccessorProperty("Total", AccessorIntType(), AccessorBlock(8), AccessorBlock(9), null, Modifiers.None)

    steps := AccessorRun(harness, AccessorBeginProperty(harness, declaration, "Box"), null)

    valueDeclares := 0
    index := 0
    while index < steps.Count {
        if steps[index].Kind == 3 && steps[index].Name == "value" {
            valueDeclares = valueDeclares + 1
            // Every one of them is inside a scope whose boundary holds `void`.
            assert steps[index].ReturnType == "void"
        }

        index = index + 1
    }

    assert valueDeclares == 1
}

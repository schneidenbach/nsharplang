namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for what a pattern MEANS — the family's root walk and its thirteen arms.
//
// WHAT THE CORPUS CAN AND CANNOT DECIDE, MEASURED RATHER THAN ASSUMED. Instrumenting the baseline
// over all 72 corpus targets counted 424 entries across SIX arms — a plain identifier binding 152, a
// union-case pattern 92, a dotted union-case name 54, a list 34, an object 33, a literal 32, a
// non-union case pattern 14 and a type pattern 13 — and NOT ONE of this walk's four diagnostics
// fires anywhere in it: every dotted name names a real case, every case pattern names a real case
// carrying real properties. The 275 accumulated fixtures add the relational, and, or, not,
// positional and nullable-narrowing arms and exactly four reporting entries. So the corpus proves
// the SILENT paths, the fixtures prove the reporting ones from the outside, and what is pinned here
// is the step TRANSCRIPT: which request each arm emits, in what order, carrying which operands, and
// where its reports land relative to them.
//
// THE SCHEDULE IS NOT HOISTABLE AND THE MEASUREMENT SAYS SO ON TWO SEPARATE COUNTS. A literal
// pattern's second step is passed the type its FIRST step answered, so no schedule computed up front
// carries the operand. A relational pattern's steps are joined by `&&` over their negations, so a
// TRUE answer to the row-escape report removes both the direct-column step and the comparability
// judgement — a length that is a function of a boolean the driver produces. Both are pinned here by
// driving the walk with each answer in turn.
//
// THREE ARMS CANNOT BE REACHED FROM SOURCE AT ALL, WHICH IS WHY THEY ARE CONTRACTS. The recovery
// parser builds a `SlicePattern` only INSIDE a list pattern, so the bare slice arm is unreachable;
// it builds a `TypePattern` only when an identifier follows the type name, so a type pattern with no
// binding name is unreachable; and `Pattern` itself has no other subclass, so the terminal arm is
// unreachable. All three are live code a later parser change can reach and all three are pinned by
// construction. So is the union-case property's EXPLICIT binding name, for the same reason slice 28
// pinned the object pattern's: both parser productions pass null.
class PatternAnalysisHarness {
    Analysis: AnalyzerPatternAnalysis
    Errors: List<CompilerError>
    Context: AnalyzerDeclarationContext
    SoaEscape: AnalyzerSoaEscape
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack

    constructor(
        analysis: AnalyzerPatternAnalysis,
        errors: List<CompilerError>,
        context: AnalyzerDeclarationContext,
        soaEscape: AnalyzerSoaEscape,
        ambient: AnalyzerAmbientContext,
        scopes: AnalyzerScopeStack
    ) {
        Analysis = analysis
        Errors = errors
        Context = context
        SoaEscape = soaEscape
        Ambient = ambient
        Scopes = scopes
    }
}

func PatternAnalysisPath(): string {
    return "/tmp/pattern-analysis.nl"
}

func PatternAnalysisDefault(): PatternAnalysisHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    context.AddCompilationUnit(PatternAnalysisPath(), new AnalyzerContextTestUnit(new List<object>()))
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
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
        new SemanticModel(),
        new BindingMap()
    )
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    exhaustiveness := new AnalyzerMatchExhaustiveness(diagnostics, substitution, assignability, resolver)
    shapes := new AnalyzerPatternShapes(diagnostics, spans, context, assignability)
    reachability := new AnalyzerPatternReachability(diagnostics, spans, context, assignability)
    propertyBinding := new AnalyzerPropertyPatternBinding(diagnostics, spans, context, substitution)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)

    return new PatternAnalysisHarness(
        new AnalyzerPatternAnalysis(
            diagnostics,
            spans,
            resolver,
            substitution,
            exhaustiveness,
            shapes,
            reachability,
            propertyBinding,
            escape,
            ambient
        ),
        errors,
        context,
        escape,
        ambient,
        scopes
    )
}

// ---------------------------------------------------------------------------------------------
// NODE BUILDERS
// ---------------------------------------------------------------------------------------------

func PatternIdent(name: string, line: int, column: int): Pattern {
    result: Pattern = new IdentifierPattern(name, line, column)
    return result
}

func PatternLiteralOf(value: int): Pattern {
    literal: Expression = new IntLiteralExpression(value.ToString(), 7, 11)
    result: Pattern = new LiteralPattern(literal, 7, 9)
    return result
}

func PatternRelationalOf(op: string, value: int): Pattern {
    bound: Expression = new IntLiteralExpression(value.ToString(), 7, 11)
    result: Pattern = new RelationalPattern(op, bound, 7, 9)
    return result
}

func PatternLiteralOfNode(literal: Expression): Pattern {
    result: Pattern = new LiteralPattern(literal, 7, 9)
    return result
}

func PatternRelationalOfNode(op: string, bound: Expression): Pattern {
    result: Pattern = new RelationalPattern(op, bound, 7, 9)
    return result
}

func PatternUnionCaseOf(caseName: string, properties: List<PropertyPattern>?): Pattern {
    result: Pattern = new UnionCasePattern(caseName, properties, 7, 9)
    return result
}

func PatternObjectOf(properties: List<PropertyPattern>): Pattern {
    result: Pattern = new ObjectPattern(properties, 7, 5)
    return result
}

func PatternListOf(elements: List<Pattern>): Pattern {
    result: Pattern = new ListPattern(elements, 7, 9)
    return result
}

func PatternSliceOf(bindingName: string?): Pattern {
    result: Pattern = new SlicePattern(bindingName, 7, 9)
    return result
}

func PatternTypeOf(typeName: string, bindingName: string?): Pattern {
    result: Pattern = new TypePattern(new SimpleTypeReference(typeName, 0, 0), bindingName, 7, 9)
    return result
}

func PatternAndOf(left: Pattern, right: Pattern): Pattern {
    result: Pattern = new AndPattern(left, right, 7, 9)
    return result
}

func PatternOrOf(left: Pattern, right: Pattern): Pattern {
    result: Pattern = new OrPattern(left, right, 7, 9)
    return result
}

func PatternNotOf(inner: Pattern): Pattern {
    result: Pattern = new NotPattern(inner, 7, 9)
    return result
}

func PatternPositionalOf(elements: List<Pattern>): Pattern {
    result: Pattern = new PositionalPattern(elements, 7, 9)
    return result
}

// A pattern node of no known kind: the terminal arm's only possible input, and one the recovery
// parser never builds.
func PatternBaseNode(): Pattern {
    result: Pattern = new Pattern(7, 9)
    return result
}

func PatternNodeList0(): List<Pattern> {
    return new List<Pattern>()
}

func PatternNodeList1(a: Pattern): List<Pattern> {
    result := new List<Pattern>()
    result.Add(a)
    return result
}

func PatternNodeList2(a: Pattern, b: Pattern): List<Pattern> {
    result := PatternNodeList1(a)
    result.Add(b)
    return result
}

func PatternNodeList3(a: Pattern, b: Pattern, c: Pattern): List<Pattern> {
    result := PatternNodeList2(a, b)
    result.Add(c)
    return result
}

func PatternPropertyList0(): List<PropertyPattern> {
    return new List<PropertyPattern>()
}

func PatternPropertyNested(name: string, nested: Pattern): PropertyPattern {
    return new PropertyPattern(name, nested, null, 7, 11)
}

func PatternPropertyImplicit(name: string): PropertyPattern {
    return new PropertyPattern(name, null, null, 7, 11)
}

func PatternPropertyNamed(name: string, bindingName: string): PropertyPattern {
    return new PropertyPattern(name, null, bindingName, 7, 11)
}

func PatternPropertyAt(name: string, line: int, column: int): PropertyPattern {
    return new PropertyPattern(name, null, null, line, column)
}

// ---------------------------------------------------------------------------------------------
// TYPE BUILDERS
// ---------------------------------------------------------------------------------------------

func PatternUnionCaseBare(name: string): UnionCase {
    return new UnionCase(name, null, 1, 1)
}

func PatternUnionCaseEmpty(name: string): UnionCase {
    return new UnionCase(name, new List<UnionCaseProperty>(), 1, 1)
}

func PatternUnionCaseWith(name: string, propertyName: string, propertyTypeName: string): UnionCase {
    properties := new List<UnionCaseProperty>()
    properties.Add(new UnionCaseProperty(propertyName, new SimpleTypeReference(propertyTypeName, 1, 1)))
    return new UnionCase(name, properties, 1, 1)
}

func PatternUnionCaseWithTwo(
    name: string,
    firstName: string,
    firstTypeName: string,
    secondName: string,
    secondTypeName: string
): UnionCase {
    properties := new List<UnionCaseProperty>()
    properties.Add(new UnionCaseProperty(firstName, new SimpleTypeReference(firstTypeName, 1, 1)))
    properties.Add(new UnionCaseProperty(secondName, new SimpleTypeReference(secondTypeName, 1, 1)))
    return new UnionCase(name, properties, 1, 1)
}

func PatternCaseList1(a: UnionCase): List<UnionCase> {
    result := new List<UnionCase>()
    result.Add(a)
    return result
}

func PatternCaseList2(a: UnionCase, b: UnionCase): List<UnionCase> {
    result := PatternCaseList1(a)
    result.Add(b)
    return result
}

// A union the harness's context OWNS. Registration is what makes a case property's declared TYPE
// resolvable — an unregistered owner answers `unknown` silently, which is slice 28's gotcha.
func PatternUnion(
    harness: PatternAnalysisHarness,
    declaredName: string,
    typeParameters: List<TypeParameter>?,
    cases: List<UnionCase>
): UnionTypeInfo {
    declared := new UnionTypeInfo(new UnionDeclarationInfo(declaredName, typeParameters, cases, 1, 1))
    declaredAsType: TypeInfo = declared
    harness.Context.RegisterCanonicalType(PatternAnalysisPath(), declaredName, declaredAsType)
    return declared
}

func PatternOneTypeParameter(name: string): List<TypeParameter> {
    result := new List<TypeParameter>()
    result.Add(new TypeParameter(name))
    return result
}

func PatternClass(harness: PatternAnalysisHarness, name: string): TypeInfo {
    owner: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true
    )
    harness.Context.RegisterCanonicalType(PatternAnalysisPath(), name, owner)
    return owner
}

func PatternClassWithProperty(
    harness: PatternAnalysisHarness,
    name: string,
    propertyName: string,
    propertyTypeName: string
): TypeInfo {
    members := new DeclaredMemberInfo[](1)
    members[0] = new DeclaredMemberInfo(
        propertyName,
        name,
        DeclaredMemberKind.Property,
        "member",
        new SimpleTypeReference(propertyTypeName, 0, 0),
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
        null,
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
        1
    )
    owner: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        members,
        new NestedTypeInfo[](0),
        true
    )
    harness.Context.RegisterCanonicalType(PatternAnalysisPath(), name, owner)
    return owner
}

// A closed instantiation that CARRIES its definition. `ResolveGenericDefinition` reads the carried
// definition first and only then falls back to a scope lookup, and the harness declares no scope, so
// an instantiation built without it is not a union here at all — which is itself pinned below.
func PatternGenericOf(definitionName: string, argument: TypeInfo, definition: TypeInfo?): TypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(argument)
    result: TypeInfo = new GenericTypeInfo(definitionName, arguments, definition)
    return result
}

func PatternNullableOf(inner: TypeInfo): TypeInfo {
    result: TypeInfo = new NullableTypeInfo(inner)
    return result
}

func PatternArrayOf(element: TypeInfo): TypeInfo {
    result: TypeInfo = new ArrayTypeInfo(element)
    return result
}

func PatternTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<none>"
    }

    asObject := candidate as object
    return asObject.ToString()
}

// ---------------------------------------------------------------------------------------------
// THE DRIVER, AS A CONTRACT READS IT
// ---------------------------------------------------------------------------------------------

func PatternRenderStep(step: PatternAnalysisRequest): string {
    if step.Kind == 1 {
        node := step.Node
        nodeObject := node as object
        return "expr:" + nodeObject.GetType().Name
    }

    if step.Kind == 4 {
        return "declare:" + step.Name + ":" + PatternTypeName(step.CarriedType) + ":" + step.Line.ToString() + ":" + step.Column.ToString()
    }

    if step.Kind == 6 {
        return "scope+:" + step.Line.ToString() + ":" + step.Column.ToString()
    }

    if step.Kind == 7 {
        statements := step.Statements
        return "stmts:" + statements.Count.ToString()
    }

    if step.Kind == 8 {
        return "scope-"
    }

    nested := step.Pattern
    nestedObject := nested as object
    return "analyze:" + nestedObject.GetType().Name + ":" + PatternTypeName(step.CarriedType)
}

// Pulls the walk the way the driver pulls it and renders the whole request sequence as one string.
// `answer` is what every expression analysis is told the type is — the one answer the walk's
// schedule depends on now that both escape reports are direct calls on the held reporter.
func PatternTranscriptAnswering(
    harness: PatternAnalysisHarness,
    patternNode: Pattern,
    valueType: TypeInfo,
    answer: TypeInfo?
): string {
    state := harness.Analysis.Begin(patternNode, valueType)
    rendered := ""
    step := harness.Analysis.NextStep(state)
    while step != null {
        if rendered.Length > 0 {
            rendered = rendered + "|"
        }
        rendered = rendered + PatternRenderStep(step)
        harness.Analysis.Supply(state, answer)
        step = harness.Analysis.NextStep(state)
    }

    if rendered.Length == 0 {
        return "<none>"
    }

    return rendered
}

// The ordinary driver: nothing escapes, and an expression analyses to `int`.
func PatternTranscript(
    harness: PatternAnalysisHarness,
    patternNode: Pattern,
    valueType: TypeInfo
): string {
    return PatternTranscriptAnswering(harness, patternNode, valueType, BuiltInTypes.Int)
}

// The same pull over a `switch` STATEMENT rather than a pattern node. The value's answered type is
// what every case pattern below it is measured against, so it is the one answer this driver gives.
func PatternSwitchTranscript(
    harness: PatternAnalysisHarness,
    switchNode: SwitchStatement,
    answer: TypeInfo?
): string {
    state := harness.Analysis.BeginSwitch(switchNode)
    rendered := ""
    step := harness.Analysis.NextStep(state)
    while step != null {
        if rendered.Length > 0 {
            rendered = rendered + "|"
        }
        rendered = rendered + PatternRenderStep(step)
        harness.Analysis.Supply(state, answer)
        step = harness.Analysis.NextStep(state)
    }

    if rendered.Length == 0 {
        return "<none>"
    }

    return rendered
}

// ---------------------------------------------------------------------------------------------
// SWITCH AND SoA BUILDERS
// ---------------------------------------------------------------------------------------------

func PatternStatementList0(): List<Statement> {
    return new List<Statement>()
}

func PatternPrintOf(text: string): Statement {
    literal: Expression = new StringLiteralExpression(text, 9, 9)
    result: Statement = new PrintStatement(literal, 9, 5)
    return result
}

func PatternStatementList1(text: string): List<Statement> {
    result := PatternStatementList0()
    result.Add(PatternPrintOf(text))
    return result
}

func PatternCaseOf(pattern: Pattern?, statements: List<Statement>, line: int, column: int): SwitchCase {
    return new SwitchCase(pattern, statements, line, column)
}

func PatternSwitchCases0(): List<SwitchCase> {
    return new List<SwitchCase>()
}

func PatternSwitchOf(cases: List<SwitchCase>): SwitchStatement {
    value: Expression = new IdentifierExpression("scrutinee", 4, 12)
    return new SwitchStatement(value, cases, 4, 5)
}

func PatternSoaColumns(): List<SoaColumnInfo> {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int", 0, 0), 1, 1))
    return columns
}

func PatternRowType(): TypeInfo {
    row: TypeInfo = new SoaRowTypeInfo(
        new SoaRecordDeclarationInfo("Particle", PatternSoaColumns(), 1, 1)
    )
    return row
}

// A member access the SoA escape reporter has RECORDED as a resolved column read. The syntactic
// probe consults that record, so registering the node is what makes the direct-column report fire.
func PatternRecordedColumnRead(harness: PatternAnalysisHarness): Expression {
    member := new MemberAccessExpression(
        new IdentifierExpression("points", 7, 11),
        "x",
        false,
        7,
        11
    )
    harness.SoaEscape.RecordColumnMemberAccess(member)
    read: Expression = member
    return read
}

// ---------------------------------------------------------------------------------------------
// THE IDENTIFIER ARM'S THREE-WAY SPLIT
// ---------------------------------------------------------------------------------------------

test "a plain name binds the scrutinee at the name's own position" {
    harness := PatternAnalysisDefault()

    assert PatternTranscript(harness, PatternIdent("bound", 7, 9), BuiltInTypes.Int) == "declare:bound:int:7:9"
    assert harness.Errors.Count == 0
}

test "a NULLABLE scrutinee narrows an undotted name to the INNER type" {
    harness := PatternAnalysisDefault()
    box := PatternClass(harness, "Box")

    assert PatternTranscript(harness, PatternIdent("inner", 7, 9), PatternNullableOf(box)) == "declare:inner:Box:7:9"
    assert harness.Errors.Count == 0
}

test "the discard binds NOTHING under a nullable scrutinee" {
    harness := PatternAnalysisDefault()
    box := PatternClass(harness, "Box")

    assert PatternTranscript(harness, PatternIdent("_", 7, 9), PatternNullableOf(box)) == "<none>"
    assert harness.Errors.Count == 0
}

test "the discard is special ONLY under a nullable scrutinee — elsewhere it binds like any name" {
    harness := PatternAnalysisDefault()

    assert PatternTranscript(harness, PatternIdent("_", 7, 9), BuiltInTypes.Int) == "declare:_:int:7:9"
    assert harness.Errors.Count == 0
}

test "a DOTTED name naming a real case binds nothing and says nothing" {
    harness := PatternAnalysisDefault()
    status := PatternUnion(
        harness,
        "Status",
        null,
        PatternCaseList2(PatternUnionCaseBare("Open"), PatternUnionCaseBare("Closed"))
    )
    statusType: TypeInfo = status

    assert PatternTranscript(harness, PatternIdent("Status.Open", 7, 9), statusType) == "<none>"
    assert harness.Errors.Count == 0
}

test "a DOTTED name naming NO case reports and still binds nothing" {
    harness := PatternAnalysisDefault()
    status := PatternUnion(
        harness,
        "Status",
        null,
        PatternCaseList2(PatternUnionCaseBare("Open"), PatternUnionCaseBare("Closed"))
    )
    statusType: TypeInfo = status

    assert PatternTranscript(harness, PatternIdent("Status.Pending", 7, 9), statusType) == "<none>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'Status.Pending' is not a case of union 'Status' — check the union definition for available cases"
    assert harness.Errors[0].DiagnosticId == "NL503"
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 9
    assert harness.Errors[0].Length == 14
}

test "a DOTTED name over a NON-union falls through to the plain binding" {
    harness := PatternAnalysisDefault()
    dog := PatternClass(harness, "Dog")

    assert PatternTranscript(harness, PatternIdent("Dog.Puppy", 7, 9), dog) == "declare:Dog.Puppy:Dog:7:9"
    assert harness.Errors.Count == 0
}

test "a DOTTED name skips the nullable narrowing and takes the union arm" {
    harness := PatternAnalysisDefault()
    status := PatternUnion(harness, "Status", null, PatternCaseList1(PatternUnionCaseBare("Open")))
    statusType: TypeInfo = status

    // A nullable is neither a union nor a generic instantiation, so `ResolveDeclaredUnionType`
    // declines and the dotted name falls all the way through to the plain binding — of the NULLABLE,
    // not of its inner type, because the narrowing guard was skipped by the dot.
    assert PatternTranscript(harness, PatternIdent("Status.Open", 7, 9), PatternNullableOf(statusType)) == "declare:Status.Open:Status?:7:9"
    assert harness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// THE UNION-CASE ARM
// ---------------------------------------------------------------------------------------------

test "a scrutinee that declares NO union makes the whole case arm silent, properties and all" {
    harness := PatternAnalysisDefault()
    dog := PatternClass(harness, "Dog")
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyImplicit("r"))

    assert PatternTranscript(harness, PatternUnionCaseOf("Circle", properties), dog) == "<none>"
    assert harness.Errors.Count == 0
}

test "a case the union does not declare reports and yields no step" {
    harness := PatternAnalysisDefault()
    shape := PatternUnion(
        harness,
        "Shape",
        null,
        PatternCaseList1(PatternUnionCaseWith("Circle", "r", "int"))
    )
    shapeType: TypeInfo = shape
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyImplicit("b"))

    assert PatternTranscript(harness, PatternUnionCaseOf("Triangle", properties), shapeType) == "<none>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'Triangle' is not a case of union 'Shape' — check the union definition for available cases"
    assert harness.Errors[0].DiagnosticId == "NL503"
    assert harness.Errors[0].Length == 8
}

test "a case pattern with NO property list binds nothing and says nothing" {
    harness := PatternAnalysisDefault()
    shape := PatternUnion(
        harness,
        "Shape",
        null,
        PatternCaseList1(PatternUnionCaseWith("Circle", "r", "int"))
    )
    shapeType: TypeInfo = shape

    assert PatternTranscript(harness, PatternUnionCaseOf("Circle", null), shapeType) == "<none>"
    assert harness.Errors.Count == 0
}

test "a case with a NULL payload cannot be destructured" {
    harness := PatternAnalysisDefault()
    signal := PatternUnion(
        harness,
        "Signal",
        null,
        PatternCaseList1(PatternUnionCaseBare("Stop"))
    )
    signalType: TypeInfo = signal
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyImplicit("speed"))

    assert PatternTranscript(harness, PatternUnionCaseOf("Stop", properties), signalType) == "<none>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Union case 'Stop' doesn't carry any data — you can't destructure it with property patterns"
    assert harness.Errors[0].DiagnosticId == "NL503"
}

test "a case with an EMPTY payload reports the SAME message at the same span" {
    harness := PatternAnalysisDefault()
    signal := PatternUnion(
        harness,
        "Signal",
        null,
        PatternCaseList1(PatternUnionCaseEmpty("Stop"))
    )
    signalType: TypeInfo = signal
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyImplicit("speed"))

    assert PatternTranscript(harness, PatternUnionCaseOf("Stop", properties), signalType) == "<none>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Union case 'Stop' doesn't carry any data — you can't destructure it with property patterns"
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 9
    assert harness.Errors[0].Length == 4
}

test "the case's properties arrive in WRITTEN order, one step each" {
    harness := PatternAnalysisDefault()
    shape := PatternUnion(
        harness,
        "Shape",
        null,
        PatternCaseList1(PatternUnionCaseWithTwo("Box", "width", "int", "label", "string"))
    )
    shapeType: TypeInfo = shape
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyNested("width", PatternIdent("w", 7, 20)))
    properties.Add(PatternPropertyImplicit("label"))

    assert PatternTranscript(harness, PatternUnionCaseOf("Box", properties), shapeType) == "analyze:IdentifierPattern:int|declare:label:string:7:11"
    assert harness.Errors.Count == 0
}

test "a case property the case does not carry reports and yields no step" {
    harness := PatternAnalysisDefault()
    shape := PatternUnion(
        harness,
        "Shape",
        null,
        PatternCaseList1(PatternUnionCaseWith("Circle", "r", "int"))
    )
    shapeType: TypeInfo = shape
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyAt("diameter", 7, 20))

    assert PatternTranscript(harness, PatternUnionCaseOf("Circle", properties), shapeType) == "<none>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Union case 'Circle' doesn't have a property named 'diameter' — check the case definition for available properties"
    assert harness.Errors[0].DiagnosticId == "NL503"
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 20
    assert harness.Errors[0].Length == 8
}

test "a missing case property REPORTS WHERE IT SITS — between the step before it and the step after" {
    harness := PatternAnalysisDefault()
    shape := PatternUnion(
        harness,
        "Shape",
        null,
        PatternCaseList1(PatternUnionCaseWithTwo("Box", "width", "int", "label", "string"))
    )
    shapeType: TypeInfo = shape
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyNested("width", PatternIdent("w", 7, 20)))
    properties.Add(PatternPropertyAt("depth", 7, 30))
    properties.Add(PatternPropertyImplicit("label"))

    state := harness.Analysis.Begin(PatternUnionCaseOf("Box", properties), shapeType)

    first := harness.Analysis.NextStep(state)
    assert first != null
    assert first.Kind == 5
    // Nothing has been reported yet: the walk has not passed the missing property.
    assert harness.Errors.Count == 0
    harness.Analysis.Supply(state, null)

    second := harness.Analysis.NextStep(state)
    assert second != null
    assert second.Kind == 4
    assert second.Name == "label"
    // The report landed while advancing PAST `depth` — after the first step was handed over and
    // before the second was. A schedule computed up front would have reported before either.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Union case 'Box' doesn't have a property named 'depth' — check the case definition for available properties"
    harness.Analysis.Supply(state, null)
    assert harness.Analysis.NextStep(state) == null
}

test "two missing case properties report twice, in written order, and neither stops the walk" {
    harness := PatternAnalysisDefault()
    shape := PatternUnion(
        harness,
        "Shape",
        null,
        PatternCaseList1(PatternUnionCaseWith("Circle", "r", "int"))
    )
    shapeType: TypeInfo = shape
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyAt("diameter", 7, 20))
    properties.Add(PatternPropertyImplicit("r"))
    properties.Add(PatternPropertyAt("girth", 7, 40))

    assert PatternTranscript(harness, PatternUnionCaseOf("Circle", properties), shapeType) == "declare:r:int:7:11"
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Column == 20
    assert harness.Errors[1].Column == 40
}

test "the SUBSTITUTION is what closes a generic union's case property" {
    harness := PatternAnalysisDefault()
    result := PatternUnion(
        harness,
        "Result",
        PatternOneTypeParameter("T"),
        PatternCaseList1(PatternUnionCaseWith("Ok", "value", "T"))
    )
    resultType: TypeInfo = result
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyImplicit("value"))

    // The open union types its own case property by the type PARAMETER; the closed instantiation
    // types it by the argument, and nothing else about the arm changes.
    assert PatternTranscript(harness, PatternUnionCaseOf("Ok", properties), resultType) == "declare:value:T:7:11"
    assert PatternTranscript(
        harness,
        PatternUnionCaseOf("Ok", properties),
        PatternGenericOf("Result", BuiltInTypes.Int, resultType)
    ) == "declare:value:int:7:11"
    assert PatternTranscript(
        harness,
        PatternUnionCaseOf("Ok", properties),
        PatternGenericOf("Result", BuiltInTypes.String, resultType)
    ) == "declare:value:string:7:11"
    // An instantiation whose definition does not resolve is NOT a union here, and the whole arm is
    // silent rather than partially bound.
    assert PatternTranscript(
        harness,
        PatternUnionCaseOf("Ok", properties),
        PatternGenericOf("Result", BuiltInTypes.Int, null)
    ) == "<none>"
    assert harness.Errors.Count == 0
}

test "an EXPLICIT case-property binding name wins — an arm no parser production reaches" {
    harness := PatternAnalysisDefault()
    shape := PatternUnion(
        harness,
        "Shape",
        null,
        PatternCaseList1(PatternUnionCaseWith("Circle", "r", "int"))
    )
    shapeType: TypeInfo = shape
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyNamed("r", "radius"))

    assert PatternTranscript(harness, PatternUnionCaseOf("Circle", properties), shapeType) == "declare:radius:int:7:11"
    assert harness.Errors.Count == 0
}

test "a case property with no position of its own is anchored on the ENCLOSING pattern" {
    harness := PatternAnalysisDefault()
    shape := PatternUnion(
        harness,
        "Shape",
        null,
        PatternCaseList1(PatternUnionCaseWith("Circle", "r", "int"))
    )
    shapeType: TypeInfo = shape
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyAt("r", 0, 0))

    assert PatternTranscript(harness, PatternUnionCaseOf("Circle", properties), shapeType) == "declare:r:int:7:9"
    assert harness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// THE LITERAL ARM — ONE SUSPENSION, THEN TWO REPORTS THE WALK MAKES ITSELF
// ---------------------------------------------------------------------------------------------

test "a literal pattern suspends ONCE — its two escape reports are no longer driver steps" {
    harness := PatternAnalysisDefault()

    assert PatternTranscript(harness, PatternLiteralOf(3), BuiltInTypes.Int) == "expr:IntLiteralExpression"
    assert harness.Errors.Count == 0
}

test "the literal arm's row report MEASURES the type the analysis before it answered" {
    harness := PatternAnalysisDefault()

    // The operand is the DRIVER's answer, not the scrutinee: a walk handed a row view reports even
    // though the scrutinee is `int`, which is precisely why the report cannot be hoisted above the
    // step. This is a strictly stronger pinning than the driver boolean it replaced — the reporter
    // itself decides now.
    assert PatternTranscriptAnswering(
        harness,
        PatternLiteralOf(3),
        BuiltInTypes.Int,
        PatternRowType()
    ) == "expr:IntLiteralExpression"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as a pattern value; use the table and row index instead"
}

test "the literal arm never short-circuits — a row view AND a column read both report" {
    harness := PatternAnalysisDefault()
    columnRead := PatternRecordedColumnRead(harness)

    assert PatternTranscriptAnswering(
        harness,
        PatternLiteralOfNode(columnRead),
        BuiltInTypes.Int,
        PatternRowType()
    ) == "expr:MemberAccessExpression"
    // TWO diagnostics on one literal. Every other arm in this family and in the loop family stops at
    // the first; the literal arm does not, and that is `Analyzer.cs`'s behaviour preserved.
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "SoA row views cannot be used as a pattern value; use the table and row index instead"
    assert harness.Errors[1].Message == "SoA table member 'x' cannot be used as a pattern value directly"
}

// ---------------------------------------------------------------------------------------------
// THE RELATIONAL ARM — A REPORT CHAIN WHOSE LENGTH IS A FUNCTION OF AN ANSWER
// ---------------------------------------------------------------------------------------------

test "a relational pattern suspends once, then judges comparability" {
    harness := PatternAnalysisDefault()

    assert PatternTranscriptAnswering(
        harness,
        PatternRelationalOf(">", 3),
        BuiltInTypes.Int,
        BuiltInTypes.Int
    ) == "expr:IntLiteralExpression"
    assert harness.Errors.Count == 0
}

test "an ESCAPING bound stops the chain before the column probe and before the judgement" {
    harness := PatternAnalysisDefault()

    // The row report fires, so the direct-column probe is not run and the comparability judgement is
    // not asked at all — ONE diagnostic, not two, and no NL202 for the `int` versus row-view pair.
    assert PatternTranscriptAnswering(
        harness,
        PatternRelationalOf(">", 3),
        BuiltInTypes.Int,
        PatternRowType()
    ) == "expr:IntLiteralExpression"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as a relational pattern value; use the table and row index instead"
}

test "a DIRECT-COLUMN bound reports once, with the row report silent and the judgement skipped" {
    harness := PatternAnalysisDefault()
    columnRead := PatternRecordedColumnRead(harness)

    // The ROW report declines — the answered type is `string`, not a row view — so the column probe
    // is still run, and IT fires. No pattern grammar reaches this shape (a relational bound is a
    // primary expression and a column access is a member access), so it is pinned here rather than
    // by a fixture, and what it must do is suppress the comparability report that `int` versus
    // `string` would otherwise raise.
    assert PatternTranscriptAnswering(
        harness,
        PatternRelationalOfNode(">", columnRead),
        BuiltInTypes.Int,
        BuiltInTypes.String
    ) == "expr:MemberAccessExpression"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be used as a relational pattern value directly"
}

test "the comparability judgement is handed the ANSWERED type, not the scrutinee" {
    harness := PatternAnalysisDefault()

    // `int` against a bound the driver typed `string` is exactly the mismatch the judgement reports.
    assert PatternTranscriptAnswering(
        harness,
        PatternRelationalOf(">", 3),
        BuiltInTypes.Int,
        BuiltInTypes.String
    ) == "expr:IntLiteralExpression"
    assert harness.Errors.Count == 1
    // The comparability report belongs to the SHAPE owner and carries the general type-mismatch
    // code, not the pattern family's own NL503/NL504.
    assert harness.Errors[0].DiagnosticId == "NL202"
    assert harness.Errors[0].Message == "Relational pattern '>' can't compare 'int' with 'string' before IL emission"
}

// ---------------------------------------------------------------------------------------------
// THE LOGICAL ARMS
// ---------------------------------------------------------------------------------------------

test "an AND pattern analyses left then right, both against the scrutinee" {
    harness := PatternAnalysisDefault()
    node := PatternAndOf(PatternIdent("a", 7, 9), PatternIdent("b", 7, 15))

    assert PatternTranscript(harness, node, BuiltInTypes.Int) == "analyze:IdentifierPattern:int|analyze:IdentifierPattern:int"
    assert harness.Errors.Count == 0
}

test "an OR pattern analyses left then right, both against the scrutinee" {
    harness := PatternAnalysisDefault()
    node := PatternOrOf(PatternIdent("a", 7, 9), PatternIdent("b", 7, 15))

    assert PatternTranscript(harness, node, BuiltInTypes.String) == "analyze:IdentifierPattern:string|analyze:IdentifierPattern:string"
    assert harness.Errors.Count == 0
}

test "a NOT pattern yields exactly one step" {
    harness := PatternAnalysisDefault()

    assert PatternTranscript(harness, PatternNotOf(PatternIdent("a", 7, 9)), BuiltInTypes.Int) == "analyze:IdentifierPattern:int"
    assert harness.Errors.Count == 0
}

test "a POSITIONAL pattern analyses every element against the SCRUTINEE, not a per-position type" {
    harness := PatternAnalysisDefault()
    elements := PatternNodeList3(
        PatternIdent("a", 7, 9),
        PatternLiteralOf(1),
        PatternIdent("c", 7, 20)
    )

    assert PatternTranscript(harness, PatternPositionalOf(elements), BuiltInTypes.Int) == "analyze:IdentifierPattern:int|analyze:LiteralPattern:int|analyze:IdentifierPattern:int"
    assert harness.Errors.Count == 0
}

test "an EMPTY positional pattern yields no step" {
    harness := PatternAnalysisDefault()

    assert PatternTranscript(harness, PatternPositionalOf(PatternNodeList0()), BuiltInTypes.Int) == "<none>"
    assert harness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// THE OBJECT ARM — THE TWO BINDING WALKS COMPOSED
// ---------------------------------------------------------------------------------------------

test "the object arm forwards the property walk's two requests as its own" {
    harness := PatternAnalysisDefault()
    dog := PatternClassWithProperty(harness, "Dog", "Age", "int")
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyNested("Age", PatternIdent("a", 7, 20)))
    properties.Add(PatternPropertyImplicit("Age"))

    assert PatternTranscript(harness, PatternObjectOf(properties), dog) == "analyze:IdentifierPattern:int|declare:Age:int:7:11"
    assert harness.Errors.Count == 0
}

test "the property walk's own report lands between two forwarded steps" {
    harness := PatternAnalysisDefault()
    dog := PatternClassWithProperty(harness, "Dog", "Age", "int")
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyNested("Age", PatternIdent("a", 7, 20)))
    properties.Add(PatternPropertyAt("Weight", 7, 30))
    properties.Add(PatternPropertyImplicit("Age"))

    state := harness.Analysis.Begin(PatternObjectOf(properties), dog)
    first := harness.Analysis.NextStep(state)
    assert first != null
    assert first.Kind == 5
    assert harness.Errors.Count == 0
    harness.Analysis.Supply(state, null)

    second := harness.Analysis.NextStep(state)
    assert second != null
    assert second.Kind == 4
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'Dog' doesn't have a property named 'Weight'"
}

test "an object pattern over a scrutinee with no such property yields no step at all" {
    harness := PatternAnalysisDefault()
    dog := PatternClass(harness, "Dog")
    properties := PatternPropertyList0()
    properties.Add(PatternPropertyImplicit("Age"))

    assert PatternTranscript(harness, PatternObjectOf(properties), dog) == "<none>"
    assert harness.Errors.Count == 1
}

// ---------------------------------------------------------------------------------------------
// THE LIST ARM AND ITS SLICE
// ---------------------------------------------------------------------------------------------

test "a list pattern analyses every element against the ONE element type" {
    harness := PatternAnalysisDefault()
    elements := PatternNodeList2(PatternIdent("a", 7, 11), PatternLiteralOf(2))

    assert PatternTranscript(harness, PatternListOf(elements), PatternArrayOf(BuiltInTypes.String)) == "analyze:IdentifierPattern:string|analyze:LiteralPattern:string"
    assert harness.Errors.Count == 0
}

test "a slice element binds an ARRAY of the element type at the LIST pattern's position" {
    harness := PatternAnalysisDefault()
    elements := PatternNodeList2(PatternLiteralOf(1), PatternSliceOf("rest"))

    assert PatternTranscript(harness, PatternListOf(elements), PatternArrayOf(BuiltInTypes.Int)) == "analyze:LiteralPattern:int|declare:rest:int[]:7:9"
    assert harness.Errors.Count == 0
}

test "a slice element with NO binding name is passed over in silence" {
    harness := PatternAnalysisDefault()
    elements := PatternNodeList2(PatternLiteralOf(1), PatternSliceOf(null))

    assert PatternTranscript(harness, PatternListOf(elements), PatternArrayOf(BuiltInTypes.Int)) == "analyze:LiteralPattern:int"
    assert harness.Errors.Count == 0
}

test "two bound slices both declare, and the element between them is still analysed" {
    harness := PatternAnalysisDefault()
    elements := PatternNodeList3(
        PatternSliceOf("head"),
        PatternLiteralOf(1),
        PatternSliceOf("tail")
    )

    assert PatternTranscript(harness, PatternListOf(elements), PatternArrayOf(BuiltInTypes.Int)) == "declare:head:int[]:7:9|analyze:LiteralPattern:int|declare:tail:int[]:7:9"
    assert harness.Errors.Count == 0
}

test "an EMPTY list pattern yields no step" {
    harness := PatternAnalysisDefault()

    assert PatternTranscript(harness, PatternListOf(PatternNodeList0()), PatternArrayOf(BuiltInTypes.Int)) == "<none>"
    assert harness.Errors.Count == 0
}

test "a list pattern over a NON-list scrutinee still analyses its elements, against unknown" {
    harness := PatternAnalysisDefault()
    dog := PatternClass(harness, "Dog")
    elements := PatternNodeList1(PatternIdent("a", 7, 11))

    // The shape owner reports the bad scrutinee ONCE and answers `unknown`, so the elements are
    // still analysed and one bad list does not cascade into one report per element.
    assert PatternTranscript(harness, PatternListOf(elements), dog) == "analyze:IdentifierPattern:unknown"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].DiagnosticId == "NL504"
}

// ---------------------------------------------------------------------------------------------
// THE TYPE ARM
// ---------------------------------------------------------------------------------------------

test "a type pattern binds the TARGET type at the pattern's position" {
    harness := PatternAnalysisDefault()

    // The witness is a built-in name: `AnalyzerTypeResolver` resolves through the SCOPES and the
    // project discovery, not through the declaration context's canonical registry, so a class
    // registered on the harness resolves to a different `TypeInfo` than the scrutinee and the
    // reachability judgement then refuses a type against itself.
    assert PatternTranscript(harness, PatternTypeOf("int", "d"), BuiltInTypes.Int) == "declare:d:int:7:9"
    assert harness.Errors.Count == 0
}

test "a type pattern with NO binding name asks reachability and binds nothing" {
    harness := PatternAnalysisDefault()

    // The recovery parser builds a TypePattern only when an identifier follows the type name, so
    // this arm is unreachable from source and is pinned by construction.
    assert PatternTranscript(harness, PatternTypeOf("int", null), BuiltInTypes.Int) == "<none>"
    assert harness.Errors.Count == 0
}

test "an IMPOSSIBLE type pattern reports and STILL binds" {
    harness := PatternAnalysisDefault()

    // An `int` is never a `string`, and the binding happens anyway — the reachability report does
    // not suppress the declaration.
    assert PatternTranscript(harness, PatternTypeOf("string", "s"), BuiltInTypes.Int) == "declare:s:string:7:9"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].DiagnosticId == "NL506"
}

// ---------------------------------------------------------------------------------------------
// THE THREE ARMS NO PARSER PRODUCTION REACHES
// ---------------------------------------------------------------------------------------------

test "a BARE slice binds an array of the SCRUTINEE, not of an element type" {
    harness := PatternAnalysisDefault()

    // The recovery parser builds a SlicePattern only INSIDE a list pattern, so this arm is
    // unreachable from source; it is live code a later parser change can reach.
    assert PatternTranscript(harness, PatternSliceOf("rest"), BuiltInTypes.Int) == "declare:rest:int[]:7:9"
    assert harness.Errors.Count == 0
}

test "a BARE slice with no binding name does nothing" {
    harness := PatternAnalysisDefault()

    assert PatternTranscript(harness, PatternSliceOf(null), BuiltInTypes.Int) == "<none>"
    assert harness.Errors.Count == 0
}

test "a pattern node of no known kind takes the terminal arm and does nothing" {
    harness := PatternAnalysisDefault()

    assert PatternTranscript(harness, PatternBaseNode(), BuiltInTypes.Int) == "<none>"
    assert harness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// THE PROTOCOL ITSELF
// ---------------------------------------------------------------------------------------------

test "an exhausted walk keeps answering null rather than restarting" {
    harness := PatternAnalysisDefault()
    state := harness.Analysis.Begin(PatternIdent("bound", 7, 9), BuiltInTypes.Int)

    first := harness.Analysis.NextStep(state)
    assert first != null
    assert first.Kind == 4
    harness.Analysis.Supply(state, null)

    assert harness.Analysis.NextStep(state) == null
    assert harness.Analysis.NextStep(state) == null
    assert harness.Errors.Count == 0
}

test "a NULL answer to an analysis leaves the walk's carried type alone" {
    harness := PatternAnalysisDefault()
    state := harness.Analysis.Begin(PatternLiteralOf(3), BuiltInTypes.Int)

    first := harness.Analysis.NextStep(state)
    assert first != null
    assert first.Kind == 1
    harness.Analysis.Supply(state, null)

    // `unknown` is the state's own starting value — a driver that answers nothing does not make the
    // walk carry a null type onwards, and the row report it is handed to therefore declines.
    assert PatternTypeName(state.AnalyzedType) == "unknown"
    assert harness.Analysis.NextStep(state) == null
    assert harness.Errors.Count == 0
}

test "a fresh state starts at the dispatch and carries no arm's working set" {
    harness := PatternAnalysisDefault()
    state := harness.Analysis.Begin(PatternIdent("bound", 7, 9), BuiltInTypes.Int)

    assert state.Form == 0
    assert state.Phase == 0
    assert state.Pending == 0
    assert state.Index == 0
    assert state.Escaped == false
    assert PatternTypeName(state.AnalyzedType) == "unknown"
    assert state.PropertyState == null
    assert state.CaseProperties == null
    assert state.PatternProperties == null
    assert state.SwitchNode == null
}

// ---------------------------------------------------------------------------------------------
// THE `switch` STATEMENT — THE PATTERN FAMILY'S SECOND FORM
// ---------------------------------------------------------------------------------------------

test "a fresh switch state opens in its own form and its own phase band" {
    harness := PatternAnalysisDefault()
    state := harness.Analysis.BeginSwitch(PatternSwitchOf(PatternSwitchCases0()))

    assert state.Form == 1
    assert state.Phase == 70
    assert state.PatternNode == null
    assert state.SwitchNode != null
    // The scrutinee type is not known until the walk's own first step answers it.
    assert PatternTypeName(state.SwitchValueType) == "unknown"
    assert state.SavedBreakDepth == 0
}

test "a switch with no cases analyses its value and nothing else" {
    harness := PatternAnalysisDefault()

    assert PatternSwitchTranscript(harness, PatternSwitchOf(PatternSwitchCases0()), BuiltInTypes.Int) == "expr:IdentifierExpression"
    assert harness.Errors.Count == 0
}

test "one case opens a scope, analyses its pattern, analyses its body, closes the scope" {
    harness := PatternAnalysisDefault()
    cases := PatternSwitchCases0()
    cases.Add(PatternCaseOf(PatternIdent("bound", 7, 9), PatternStatementList1("hit"), 6, 5))

    assert PatternSwitchTranscript(harness, PatternSwitchOf(cases), BuiltInTypes.Int) == "expr:IdentifierExpression|scope+:4:5|analyze:IdentifierPattern:int|stmts:1|scope-"
    assert harness.Errors.Count == 0
}

test "the case scope is positioned at the SWITCH, not at the case and not at the pattern" {
    harness := PatternAnalysisDefault()
    cases := PatternSwitchCases0()
    // The case is at 6:5 and its pattern at 7:9; the switch is at 4:5, and 4:5 is what the scope
    // step carries. `AnalyzeMatchExpression` uses the PATTERN's position for its arms — this walk
    // deliberately does not, because `Analyzer.cs` did not.
    cases.Add(PatternCaseOf(PatternIdent("bound", 7, 9), PatternStatementList0(), 6, 5))

    assert PatternSwitchTranscript(harness, PatternSwitchOf(cases), BuiltInTypes.Int) == "expr:IdentifierExpression|scope+:4:5|analyze:IdentifierPattern:int|stmts:0|scope-"
}

test "a DEFAULT case still opens and closes its own scope, with no pattern step between" {
    harness := PatternAnalysisDefault()
    cases := PatternSwitchCases0()
    cases.Add(PatternCaseOf(null, PatternStatementList1("fallback"), 6, 5))

    assert PatternSwitchTranscript(harness, PatternSwitchOf(cases), BuiltInTypes.Int) == "expr:IdentifierExpression|scope+:4:5|stmts:1|scope-"
    assert harness.Errors.Count == 0
}

test "three cases replay the four operations three times, and every scope is balanced" {
    harness := PatternAnalysisDefault()
    cases := PatternSwitchCases0()
    cases.Add(PatternCaseOf(PatternIdent("a", 7, 9), PatternStatementList1("a"), 6, 5))
    cases.Add(PatternCaseOf(PatternIdent("b", 8, 9), PatternStatementList0(), 7, 5))
    cases.Add(PatternCaseOf(null, PatternStatementList1("d"), 8, 5))

    assert PatternSwitchTranscript(harness, PatternSwitchOf(cases), BuiltInTypes.Int) == "expr:IdentifierExpression" + "|scope+:4:5|analyze:IdentifierPattern:int|stmts:1|scope-" + "|scope+:4:5|analyze:IdentifierPattern:int|stmts:0|scope-" + "|scope+:4:5|stmts:1|scope-"
    assert harness.Errors.Count == 0
}

test "every case pattern is measured against the value's ANSWERED type, not the state's opening one" {
    harness := PatternAnalysisDefault()
    cases := PatternSwitchCases0()
    cases.Add(PatternCaseOf(PatternIdent("a", 7, 9), PatternStatementList0(), 6, 5))

    assert PatternSwitchTranscript(harness, PatternSwitchOf(cases), BuiltInTypes.String) == "expr:IdentifierExpression|scope+:4:5|analyze:IdentifierPattern:string|stmts:0|scope-"
}

test "a ROW-VIEW switch value reports once and collapses every case pattern to unknown" {
    harness := PatternAnalysisDefault()
    cases := PatternSwitchCases0()
    cases.Add(PatternCaseOf(PatternIdent("a", 7, 9), PatternStatementList0(), 6, 5))

    assert PatternSwitchTranscript(harness, PatternSwitchOf(cases), PatternRowType()) == "expr:IdentifierExpression|scope+:4:5|analyze:IdentifierPattern:unknown|stmts:0|scope-"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as a switch value; use the table and row index instead"
}

test "the switch value's row report SHORT-CIRCUITS the column probe" {
    harness := PatternAnalysisDefault()
    columnRead := PatternRecordedColumnRead(harness)
    switchNode := new SwitchStatement(columnRead, PatternSwitchCases0(), 4, 5)

    // The value is BOTH a row view by type and a recorded column read by syntax. `switch` joins its
    // two reports with `||`, so only the first fires — unlike `print`, which reports both.
    assert PatternSwitchTranscript(harness, switchNode, PatternRowType()) == "expr:MemberAccessExpression"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as a switch value; use the table and row index instead"
}

test "a DIRECT-COLUMN switch value reports the column form and also collapses to unknown" {
    harness := PatternAnalysisDefault()
    columnRead := PatternRecordedColumnRead(harness)
    cases := PatternSwitchCases0()
    cases.Add(PatternCaseOf(PatternIdent("a", 7, 9), PatternStatementList0(), 6, 5))
    switchNode := new SwitchStatement(columnRead, cases, 4, 5)

    assert PatternSwitchTranscript(harness, switchNode, BuiltInTypes.Int) == "expr:MemberAccessExpression|scope+:4:5|analyze:IdentifierPattern:unknown|stmts:0|scope-"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be used as a switch value directly"
}

test "the switch moves ONLY the break target's finally depth, and restores it on the way out" {
    harness := PatternAnalysisDefault()
    harness.Ambient.EnterFinally()
    cases := PatternSwitchCases0()
    cases.Add(PatternCaseOf(null, PatternStatementList0(), 6, 5))
    switchNode := PatternSwitchOf(cases)

    beforeBreak := harness.Ambient.BreakTargetFinallyDepth
    beforeContinue := harness.Ambient.ContinueTargetFinallyDepth
    beforeInLoop := harness.Ambient.InLoop

    state := harness.Analysis.BeginSwitch(switchNode)
    step := harness.Analysis.NextStep(state)
    harness.Analysis.Supply(state, BuiltInTypes.Int)

    // Inside the walk the break target has moved to the switch's ENTRY depth — which is what makes
    // NL319 fire on a `break` out of a `finally` — while `continue` and the loop flag are untouched.
    step = harness.Analysis.NextStep(state)
    assert harness.Ambient.BreakTargetFinallyDepth == harness.Ambient.FinallyDepth
    assert harness.Ambient.ContinueTargetFinallyDepth == beforeContinue
    assert harness.Ambient.InLoop == beforeInLoop

    while step != null {
        harness.Analysis.Supply(state, null)
        step = harness.Analysis.NextStep(state)
    }

    assert harness.Ambient.BreakTargetFinallyDepth == beforeBreak
    assert harness.Ambient.ContinueTargetFinallyDepth == beforeContinue
    assert harness.Ambient.InLoop == beforeInLoop
}

test "an exhausted switch walk keeps answering null rather than replaying its cases" {
    harness := PatternAnalysisDefault()
    cases := PatternSwitchCases0()
    cases.Add(PatternCaseOf(null, PatternStatementList0(), 6, 5))
    state := harness.Analysis.BeginSwitch(PatternSwitchOf(cases))

    step := harness.Analysis.NextStep(state)
    while step != null {
        harness.Analysis.Supply(state, BuiltInTypes.Int)
        step = harness.Analysis.NextStep(state)
    }

    assert state.Phase == 99
    assert harness.Analysis.NextStep(state) == null
    assert harness.Analysis.NextStep(state) == null
}

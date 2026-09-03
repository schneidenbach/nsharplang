namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT A TYPE DECLARATION MEANS.
//
// The eight walkers this replaces were all `private` in `Analyzer.cs`, so nothing named them: their
// behaviour was pinned only through whatever end-to-end diagnostic a broken declaration happened to
// produce. This is their first DIRECT pinning, and it is written around the seven things this family
// is easy to get wrong.
//
// (1) THE FORWARD-REFERENCE PASS IS A CLASS'S ALONE. Only the class walk pre-declared its member
// functions before walking any member; the struct, record and interface walks went straight to their
// members. Levelling that would silently make a forward reference between two struct methods resolve
// where it does not today.
//
// (2) A CLASS MOVES BOTH AMBIENT SLOTS AND EVERYTHING ELSE MOVES ONE. A struct, record or interface
// sets only the ambient type NAME, so a struct nested inside a class is analysed with that class
// still current — which is what the constructor's definite-assignment walk and the `lock` rule read.
//
// (3) THE MEMBER WALK RE-ENTERS THE DISPATCH THIS WALK IS REACHED THROUGH. A nested type declaration
// is a SECOND state and a SECOND driver frame; the outer walk's phase, member index and saved ambient
// slots must survive it untouched. This is the arc's first re-entrant driver and the contracts say so.
//
// (4) THE SCOPE BALANCE IS PER DECLARATION AND NESTS. Five of the eight forms open exactly one scope
// and close it; the enum, the `soa record` and the field open none. A nested declaration's balance is
// its own.
//
// (5) THE CONVENTION IS CHECKED BY SEVEN FORMS AND NOT BY THE EIGHTH. A `soa record` is never held to
// it — that asymmetry is shipped behaviour, and it is asserted rather than assumed.
//
// (6) THE FIELD'S TWO INITIALIZER ARMS TREAT THE SoA ESCAPES DIFFERENTLY. The inference arm is a
// CHAIN — the second report only runs if the first did not fire — while the checked arm runs BOTH
// unconditionally. A walk that levelled them would change how many diagnostics a bad field produces.
//
// (7) TWO REPORTS HAVE TWO SHAPES WITH TWO DIFFERENT CODES. The field's initializer mismatch and the
// duplicate union case / enum member each have a rich builder shape and a detail-only fallback, and
// the fallback's code is INVALID SYNTAX for the field because that is what the three-argument `Error`
// overload it replaces defaulted to.
class TypeDeclarationHarness {
    Declarations: AnalyzerTypeDeclarations
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Errors: List<CompilerError>
    Assignability: AnalyzerAssignability
    Model: SemanticModel

    constructor(declarations: AnalyzerTypeDeclarations, ambient: AnalyzerAmbientContext, scopes: AnalyzerScopeStack, errors: List<CompilerError>, assignability: AnalyzerAssignability, model: SemanticModel) {
        Declarations = declarations
        Ambient = ambient
        Scopes = scopes
        Errors = errors
        Assignability = assignability
        Model = model
    }
}

// One replayed step, with the scope DEPTH, the ambient TYPE NAME and the error count AS THE STEP WAS
// HANDED OUT — the ambient name is on every row because entering and leaving the type context are
// protocol events even though they are not steps: they are what makes a member a member.
class TypeDeclarationStep {
    Kind: int
    Name: string?
    ContainingType: string?
    CarriedType: string
    ScopeKindName: string
    RecordsBinding: bool
    ParameterCount: int
    HasMember: bool
    HasNode: bool
    Line: int
    Column: int
    Depth: int
    AmbientTypeName: string
    AmbientClassName: string
    ErrorCount: int

    constructor(kind: int, name: string?, containingType: string?, carriedType: string, scopeKindName: string, recordsBinding: bool, parameterCount: int, hasMember: bool, hasNode: bool, line: int, column: int, depth: int, ambientTypeName: string, ambientClassName: string, errorCount: int) {
        Kind = kind
        Name = name
        ContainingType = containingType
        CarriedType = carriedType
        ScopeKindName = scopeKindName
        RecordsBinding = recordsBinding
        ParameterCount = parameterCount
        HasMember = hasMember
        HasNode = hasNode
        Line = line
        Column = column
        Depth = depth
        AmbientTypeName = ambientTypeName
        AmbientClassName = ambientClassName
        ErrorCount = errorCount
    }
}

func TypeDeclPath(): string {
    return Path.GetFullPath("type-declarations-contract.nl")
}

func TypeDeclHarnessWith(sourceText: string?): TypeDeclarationHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(TypeDeclPath(), sourceText)
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
    resolver.BeginAnalysis(TypeDeclPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    factory := new AnalyzerFunctionTypeFactory(context, substitution)
    declarations := new AnalyzerTypeDeclarations(diagnostics, spans, scopes, context, resolver, factory, ambient, escape)
    return new TypeDeclarationHarness(declarations, ambient, scopes, errors, assignability, model)
}

func TypeDeclDefault(): TypeDeclarationHarness {
    return TypeDeclHarnessWith(null)
}

func TypeDeclText(candidate: TypeInfo?): string {
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

func TypeDeclName(candidate: string?): string {
    if candidate == null {
        return "<null>"
    }

    return candidate
}

// The type-declaration driver, exactly as `Analyzer.cs` writes it, with the scope and semantic-model
// operations performed FOR REAL so that the depth recorded on every step is the depth the analyzer
// would have been at and a name declared into a type's scope stops resolving once it closes. Kind 7
// RECORDS the member rather than re-entering the declaration dispatch — except in the re-entrancy
// contracts, which re-enter this same function deliberately.
func TypeDeclRun(harness: TypeDeclarationHarness, state: TypeDeclarationState, answer: TypeInfo?): List<TypeDeclarationStep> {
    steps := new List<TypeDeclarationStep>()
    step := harness.Declarations.NextStep(state)
    while step != null {
        parameterCount := 0
        parameters := step.Parameters
        if parameters != null {
            parameterCount = parameters.Count
        }

        scopeKindName := step.CarriedScopeKind as object
        steps.Add(new TypeDeclarationStep(step.Kind, step.Name, step.ContainingType, TypeDeclText(step.CarriedType), scopeKindName.ToString() ?? "", step.RecordsBinding, parameterCount, step.Member != null, step.Node != null, step.Line, step.Column, harness.Scopes.Count, TypeDeclName(harness.Ambient.CurrentTypeName), TypeDeclClassName(harness.Ambient.CurrentClass), harness.Errors.Count))

        if step.Kind == 2 {
            harness.Scopes.Push(harness.Model, new Scope(step.CarriedScopeKind), step.Line, step.Column)
        }

        if step.Kind == 3 {
            declaredName := step.Name
            if declaredName != null {
                harness.Scopes.Peek().Symbols[declaredName] = step.CarriedType
            }
        }

        if step.Kind == 4 {
            recordedName := step.Name
            if recordedName != null {
                harness.Scopes.RecordVariable(harness.Model, recordedName, step.CarriedType)
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
            fieldName := step.Name
            if fieldName != null {
                harness.Model.RecordField(fieldName, step.CarriedType)
            }
        }

        harness.Declarations.Supply(state, answer)
        step = harness.Declarations.NextStep(state)
    }

    return steps
}

func TypeDeclClassName(candidate: ClassDeclaration?): string {
    if candidate == null {
        return "<null>"
    }

    return candidate.Name
}

func TypeDeclKinds(steps: List<TypeDeclarationStep>): string {
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

func TypeDeclCountKind(steps: List<TypeDeclarationStep>, kind: int): int {
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

// ── declaration builders ────────────────────────────────────────────────

func TypeDeclInt(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("int", 7, 20)
    return reference
}

func TypeDeclString(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("string", 7, 20)
    return reference
}

func TypeDeclMissing(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("NoSuchTypeAnywhere", 7, 20)
    return reference
}

func TypeDeclNoMembers(): List<Declaration> {
    return new List<Declaration>()
}

func TypeDeclMembers(member: Declaration): List<Declaration> {
    members := new List<Declaration>()
    members.Add(member)
    return members
}

func TypeDeclNoInterfaces(): List<TypeReference> {
    return new List<TypeReference>()
}

func TypeDeclNoAttributes(): List<AttributeNode> {
    return new List<AttributeNode>()
}

func TypeDeclParameters(): List<Parameter> {
    return new List<Parameter>()
}

func TypeDeclOneParameter(parameter: Parameter): List<Parameter> {
    parameters := new List<Parameter>()
    parameters.Add(parameter)
    return parameters
}

func TypeDeclParameter(name: string, typeName: string, line: int, column: int): Parameter {
    return new Parameter(name, new SimpleTypeReference(typeName, line, column), null, false, ParameterModifier.None, null, line, column, false, null)
}

func TypeDeclTypeParameters(name: string): List<TypeParameter> {
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter(name))
    return parameters
}

func TypeDeclClass(name: string, members: List<Declaration>, typeParameters: List<TypeParameter>?, primary: List<Parameter>?, modifiers: Modifiers): ClassDeclaration {
    return new ClassDeclaration(name, typeParameters, null, TypeDeclNoInterfaces(), members, primary, modifiers, TypeDeclNoAttributes(), 7, 10)
}

func TypeDeclStruct(name: string, members: List<Declaration>, typeParameters: List<TypeParameter>?, primary: List<Parameter>?, modifiers: Modifiers): StructDeclaration {
    return new StructDeclaration(name, typeParameters, TypeDeclNoInterfaces(), members, primary, modifiers, TypeDeclNoAttributes(), 7, 10, false)
}

func TypeDeclRecord(name: string, members: List<Declaration>, primary: List<Parameter>?, modifiers: Modifiers): RecordDeclaration {
    return new RecordDeclaration(name, null, TypeDeclNoInterfaces(), members, primary, false, modifiers, TypeDeclNoAttributes(), 7, 10)
}

func TypeDeclInterface(name: string, members: List<Declaration>, modifiers: Modifiers): InterfaceDeclaration {
    return new InterfaceDeclaration(name, null, TypeDeclNoInterfaces(), members, modifiers, false, TypeDeclNoAttributes(), 7, 10)
}

func TypeDeclUnionCase(name: string, line: int): UnionCase {
    return new UnionCase(name, null, line, 12)
}

func TypeDeclUnion(name: string, cases: List<UnionCase>, modifiers: Modifiers): UnionDeclaration {
    return new UnionDeclaration(name, null, cases, modifiers, TypeDeclNoAttributes(), 7, 10)
}

func TypeDeclEnumMember(name: string, value: Expression?, line: int): EnumMember {
    return new EnumMember(name, value, line, 12)
}

func TypeDeclEnum(name: string, members: List<EnumMember>, backing: EnumType, modifiers: Modifiers): EnumDeclaration {
    return new EnumDeclaration(name, members, backing, modifiers, TypeDeclNoAttributes(), 7, 10)
}

func TypeDeclColumn(name: string, typeName: string, line: int): SoaColumnDeclaration {
    reference: TypeReference = new SimpleTypeReference(typeName, line, 20)
    return new SoaColumnDeclaration(name, reference, line, 12)
}

func TypeDeclSoaRecord(name: string, columns: List<SoaColumnDeclaration>, modifiers: Modifiers): SoaRecordDeclaration {
    return new SoaRecordDeclaration(name, columns, modifiers, TypeDeclNoAttributes(), 7, 10)
}

func TypeDeclField(name: string, typeReference: TypeReference?, initializer: Expression?, modifiers: Modifiers): FieldDeclaration {
    return new FieldDeclaration(name, typeReference, initializer, modifiers, PropertyModifier.None, TypeDeclNoAttributes(), 7, 10)
}

func TypeDeclFunction(name: string, modifiers: Modifiers): FunctionDeclaration {
    return new FunctionDeclaration(name, TypeDeclParameters(), TypeDeclInt(), new BlockStatement(new List<Statement>(), 8, 5), null, null, null, modifiers, TypeDeclNoAttributes(), false, null, false, false, 8, 5)
}

func TypeDeclIntLiteral(): Expression {
    literal: Expression = new IntLiteralExpression("1", 7, 30)
    return literal
}

// ---------------------------------------------------------------------------------------------
// THE SHAPES: WHICH FORM ASKS FOR WHAT
// ---------------------------------------------------------------------------------------------

test "A PLAIN CLASS OPENS ITS SCOPE, DECLARES `this`, WALKS ITS MEMBERS AND CLOSES" {
    harness := TypeDeclDefault()
    declaration := TypeDeclClass("Box", TypeDeclNoMembers(), null, null, Modifiers.None)

    steps := TypeDeclRun(harness, harness.Declarations.BeginClass(declaration, harness.Assignability), null)

    // Open the CLASS scope, declare `this`, close. No members, no primary constructor, no report.
    assert TypeDeclKinds(steps) == "2,3,5"
    assert steps[0].ScopeKindName == "Class"
    assert steps[0].Line == 7
    assert steps[0].Column == 10
    assert steps[1].Name == "this"
    assert steps[1].Depth == 2
    assert harness.Errors.Count == 0
}

test "`this` IS DECLARED WITHOUT A BINDING DECLARATION, AND AN INTERFACE DECLARES NO `this` AT ALL" {
    harness := TypeDeclDefault()
    steps := TypeDeclRun(harness, harness.Declarations.BeginClass(TypeDeclClass("Box", TypeDeclNoMembers(), null, null, Modifiers.None), harness.Assignability), null)
    assert steps[1].Name == "this"
    assert !steps[1].RecordsBinding

    interfaceHarness := TypeDeclDefault()
    interfaceSteps := TypeDeclRun(interfaceHarness, interfaceHarness.Declarations.BeginInterface(TypeDeclInterface("Shape", TypeDeclNoMembers(), Modifiers.None), interfaceHarness.Assignability), null)
    assert TypeDeclKinds(interfaceSteps) == "2,5"
    assert interfaceSteps[0].ScopeKindName == "Interface"
}

test "EACH TYPE FORM OPENS THE SCOPE KIND NAMED FOR IT, AND A UNION OPENS A BLOCK" {
    classHarness := TypeDeclDefault()
    classSteps := TypeDeclRun(classHarness, classHarness.Declarations.BeginClass(TypeDeclClass("Box", TypeDeclNoMembers(), null, null, Modifiers.None), classHarness.Assignability), null)
    assert classSteps[0].ScopeKindName == "Class"

    structHarness := TypeDeclDefault()
    structSteps := TypeDeclRun(structHarness, structHarness.Declarations.BeginStruct(TypeDeclStruct("Point", TypeDeclNoMembers(), null, null, Modifiers.None), structHarness.Assignability), null)
    assert structSteps[0].ScopeKindName == "Struct"

    recordHarness := TypeDeclDefault()
    recordSteps := TypeDeclRun(recordHarness, recordHarness.Declarations.BeginRecord(TypeDeclRecord("Pair", TypeDeclNoMembers(), null, Modifiers.None), recordHarness.Assignability), null)
    assert recordSteps[0].ScopeKindName == "Record"

    unionHarness := TypeDeclDefault()
    cases := new List<UnionCase>()
    cases.Add(TypeDeclUnionCase("Some", 8))
    unionSteps := TypeDeclRun(unionHarness, unionHarness.Declarations.BeginUnion(TypeDeclUnion("Option", cases, Modifiers.None), unionHarness.Assignability), null)
    assert TypeDeclKinds(unionSteps) == "2,5"
    assert unionSteps[0].ScopeKindName == "Block"
}

test "AN ENUM OPENS NO SCOPE AND ASKS ONLY FOR THE MEMBERS THAT HAVE INITIALIZERS" {
    harness := TypeDeclDefault()
    members := new List<EnumMember>()
    members.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    members.Add(TypeDeclEnumMember("B", null, 9))
    members.Add(TypeDeclEnumMember("C", TypeDeclIntLiteral(), 10))

    steps := TypeDeclRun(harness, harness.Declarations.BeginEnum(TypeDeclEnum("Colour", members, EnumType.Int, Modifiers.None), harness.Assignability), BuiltInTypes.Int)

    assert TypeDeclKinds(steps) == "1,1"
    assert steps[0].Line == 8
    assert steps[1].Line == 10
    assert steps[0].HasNode
    assert harness.Scopes.Count == 1
}

test "A `soa record` ASKS FOR NOTHING AT ALL — EVERY RULE IT HAS IS A PURE FUNCTION OF ITS COLUMNS" {
    harness := TypeDeclDefault()
    columns := new List<SoaColumnDeclaration>()
    columns.Add(TypeDeclColumn("id", "int", 8))

    steps := TypeDeclRun(harness, harness.Declarations.BeginSoaRecord(TypeDeclSoaRecord("Rows", columns, Modifiers.None), harness.Assignability), null)

    assert steps.Count == 0
    // Outside the experimental gate the walk reports and stops — one report, not one per column.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.FeatureNotImplemented
    assert harness.Errors[0].Length == 3
}

test "A CLASS WITH A PRIMARY CONSTRUCTOR VALIDATES THE LIST ONCE, THEN DECLARES AND RECORDS EACH" {
    harness := TypeDeclDefault()
    parameters := TypeDeclOneParameter(TypeDeclParameter("size", "int", 7, 24))
    declaration := TypeDeclClass("Box", TypeDeclNoMembers(), null, parameters, Modifiers.None)

    steps := TypeDeclRun(harness, harness.Declarations.BeginClass(declaration, harness.Assignability), null)

    assert TypeDeclKinds(steps) == "2,3,6,3,4,5"
    assert steps[2].ParameterCount == 1
    assert steps[2].Line == 7
    assert steps[2].Column == 10
    // The parameter is declared at ITS OWN position, inside the type's scope, and recorded next.
    assert steps[3].Name == "size"
    assert steps[3].Line == 7
    assert steps[3].Column == 24
    assert steps[3].Depth == 2
    assert steps[4].Kind == 4
    assert steps[4].Name == "size"
}

test "A PARAMETER WITHOUT A POSITION OF ITS OWN FALLS BACK TO THE DECLARATION'S" {
    harness := TypeDeclDefault()
    parameters := TypeDeclOneParameter(TypeDeclParameter("size", "int", 0, 0))
    declaration := TypeDeclClass("Box", TypeDeclNoMembers(), null, parameters, Modifiers.None)

    steps := TypeDeclRun(harness, harness.Declarations.BeginClass(declaration, harness.Assignability), null)

    assert steps[3].Name == "size"
    assert steps[3].Line == 7
    assert steps[3].Column == 10
}

test "THE FORWARD-REFERENCE PASS IS A CLASS'S ALONE — A STRUCT AND A RECORD GO STRAIGHT TO MEMBERS" {
    classHarness := TypeDeclDefault()
    classDeclaration := TypeDeclClass("Box", TypeDeclMembers(TypeDeclFunction("Area", Modifiers.None)), null, null, Modifiers.None)
    classSteps := TypeDeclRun(classHarness, classHarness.Declarations.BeginClass(classDeclaration, classHarness.Assignability), null)

    // Open, `this`, PRE-DECLARE the member function, walk it, close.
    assert TypeDeclKinds(classSteps) == "2,3,3,7,5"
    assert classSteps[2].Name == "Area"
    assert classSteps[2].Line == 8
    assert classSteps[3].HasMember

    structHarness := TypeDeclDefault()
    structDeclaration := TypeDeclStruct("Point", TypeDeclMembers(TypeDeclFunction("Area", Modifiers.None)), null, null, Modifiers.None)
    structSteps := TypeDeclRun(structHarness, structHarness.Declarations.BeginStruct(structDeclaration, structHarness.Assignability), null)
    assert TypeDeclKinds(structSteps) == "2,3,7,5"

    recordHarness := TypeDeclDefault()
    recordDeclaration := TypeDeclRecord("Pair", TypeDeclMembers(TypeDeclFunction("Area", Modifiers.None)), null, Modifiers.None)
    recordSteps := TypeDeclRun(recordHarness, recordHarness.Declarations.BeginRecord(recordDeclaration, recordHarness.Assignability), null)
    assert TypeDeclKinds(recordSteps) == "2,3,7,5"

    interfaceHarness := TypeDeclDefault()
    interfaceDeclaration := TypeDeclInterface("Shape", TypeDeclMembers(TypeDeclFunction("Area", Modifiers.None)), Modifiers.None)
    interfaceSteps := TypeDeclRun(interfaceHarness, interfaceHarness.Declarations.BeginInterface(interfaceDeclaration, interfaceHarness.Assignability), null)
    assert TypeDeclKinds(interfaceSteps) == "2,7,5"
}

test "THE FORWARD-REFERENCE PASS DECLARES ONLY FUNCTIONS, AND THE MEMBER WALK TAKES EVERY MEMBER" {
    harness := TypeDeclDefault()
    members := new List<Declaration>()
    members.Add(TypeDeclField("count", TypeDeclInt(), null, Modifiers.None))
    members.Add(TypeDeclFunction("Area", Modifiers.None))
    declaration := TypeDeclClass("Box", members, null, null, Modifiers.None)

    steps := TypeDeclRun(harness, harness.Declarations.BeginClass(declaration, harness.Assignability), null)

    // One pre-declaration (the function only) and TWO member steps, in source order.
    assert TypeDeclKinds(steps) == "2,3,3,7,7,5"
    assert steps[2].Name == "Area"
    assert TypeDeclCountKind(steps, 7) == 2
}

// ---------------------------------------------------------------------------------------------
// THE AMBIENT TYPE CONTEXT
// ---------------------------------------------------------------------------------------------

test "A CLASS ENTERS BOTH AMBIENT SLOTS AND RESTORES BOTH WHEN IT LEAVES" {
    harness := TypeDeclDefault()
    assert harness.Ambient.CurrentTypeName == null
    assert harness.Ambient.CurrentClass == null

    declaration := TypeDeclClass("Box", TypeDeclMembers(TypeDeclFunction("Area", Modifiers.None)), null, null, Modifiers.None)
    steps := TypeDeclRun(harness, harness.Declarations.BeginClass(declaration, harness.Assignability), null)

    // Every step inside the walk sees the class as current — which is what makes a member a member.
    assert steps[0].AmbientTypeName == "Box"
    assert steps[0].AmbientClassName == "Box"
    assert steps[3].AmbientTypeName == "Box"
    // And the walk leaves them exactly as it found them.
    assert harness.Ambient.CurrentTypeName == null
    assert harness.Ambient.CurrentClass == null
}

test "A STRUCT, RECORD AND INTERFACE MOVE ONLY THE NAME — A NESTED ONE KEEPS THE OUTER CLASS CURRENT" {
    harness := TypeDeclDefault()
    outer := TypeDeclClass("Outer", TypeDeclNoMembers(), null, null, Modifiers.None)
    savedClass := harness.Ambient.EnterClassDeclaration(outer)
    savedName := harness.Ambient.EnterTypeName("Outer")

    structSteps := TypeDeclRun(harness, harness.Declarations.BeginStruct(TypeDeclStruct("Point", TypeDeclNoMembers(), null, null, Modifiers.None), harness.Assignability), null)

    // The NAME is the struct's; the CLASS is still the enclosing one. That asymmetry is what the
    // constructor's definite-assignment walk and the `lock` rule read.
    assert structSteps[0].AmbientTypeName == "Point"
    assert structSteps[0].AmbientClassName == "Outer"
    assert harness.Ambient.CurrentTypeName == "Outer"
    assert harness.Ambient.CurrentClass != null

    harness.Ambient.ExitTypeName(savedName)
    harness.Ambient.ExitClassDeclaration(savedClass)
    assert harness.Ambient.CurrentTypeName == null
    assert harness.Ambient.CurrentClass == null
}

test "A UNION, AN ENUM AND A FIELD NEVER WRITE THE AMBIENT TYPE NAME" {
    harness := TypeDeclDefault()
    savedName := harness.Ambient.EnterTypeName("Outer")

    cases := new List<UnionCase>()
    cases.Add(TypeDeclUnionCase("Some", 8))
    unionSteps := TypeDeclRun(harness, harness.Declarations.BeginUnion(TypeDeclUnion("Option", cases, Modifiers.None), harness.Assignability), null)
    assert unionSteps[0].AmbientTypeName == "Outer"

    members := new List<EnumMember>()
    members.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    enumSteps := TypeDeclRun(harness, harness.Declarations.BeginEnum(TypeDeclEnum("Colour", members, EnumType.Int, Modifiers.None), harness.Assignability), BuiltInTypes.Int)
    assert enumSteps[0].AmbientTypeName == "Outer"

    fieldSteps := TypeDeclRun(harness, harness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), null, Modifiers.None), harness.Assignability), null)
    assert fieldSteps[0].AmbientTypeName == "Outer"
    assert harness.Ambient.CurrentTypeName == "Outer"

    harness.Ambient.ExitTypeName(savedName)
}

// ---------------------------------------------------------------------------------------------
// THE RE-ENTRANT DRIVER
// ---------------------------------------------------------------------------------------------

test "A NESTED TYPE IS A SECOND STATE AND A SECOND FRAME, AND THE OUTER WALK RESUMES UNTOUCHED" {
    harness := TypeDeclDefault()
    inner := TypeDeclClass("Inner", TypeDeclNoMembers(), null, null, Modifiers.None)
    outerMembers := new List<Declaration>()
    outerMembers.Add(inner)
    outerMembers.Add(TypeDeclField("count", TypeDeclInt(), null, Modifiers.None))
    outer := TypeDeclClass("Outer", outerMembers, null, null, Modifiers.None)

    outerState := harness.Declarations.BeginClass(outer, harness.Assignability)
    outerSteps := new List<TypeDeclarationStep>()
    innerSteps := new List<TypeDeclarationStep>()
    step := harness.Declarations.NextStep(outerState)
    while step != null {
        scopeKindName := step.CarriedScopeKind as object
        outerSteps.Add(new TypeDeclarationStep(step.Kind, step.Name, step.ContainingType, TypeDeclText(step.CarriedType), scopeKindName.ToString() ?? "", step.RecordsBinding, 0, step.Member != null, step.Node != null, step.Line, step.Column, harness.Scopes.Count, TypeDeclName(harness.Ambient.CurrentTypeName), TypeDeclClassName(harness.Ambient.CurrentClass), harness.Errors.Count))

        if step.Kind == 2 {
            harness.Scopes.Push(harness.Model, new Scope(step.CarriedScopeKind), step.Line, step.Column)
        }

        if step.Kind == 3 {
            declaredName := step.Name
            if declaredName != null {
                harness.Scopes.Peek().Symbols[declaredName] = step.CarriedType
            }
        }

        if step.Kind == 5 {
            harness.Scopes.NoteLine(99)
            harness.Scopes.Pop(harness.Model)
        }

        // THE RE-ENTRY: the member step hands a nested class back to the SAME walk.
        if step.Kind == 7 {
            nested := step.Member as ClassDeclaration
            if nested != null {
                innerSteps = TypeDeclRun(harness, harness.Declarations.BeginClass(nested, harness.Assignability), null)
            }
        }

        harness.Declarations.Supply(outerState, null)
        step = harness.Declarations.NextStep(outerState)
    }

    // The inner walk ran to completion INSIDE the outer's member step, at depth 3, and the outer
    // walk resumed with its member index intact and walked its second member.
    assert TypeDeclKinds(innerSteps) == "2,3,5"
    assert innerSteps[1].Depth == 3
    assert innerSteps[1].AmbientTypeName == "Inner"
    assert TypeDeclKinds(outerSteps) == "2,3,7,7,5"
    assert outerSteps[3].AmbientTypeName == "Outer"
    assert outerSteps[3].AmbientClassName == "Outer"
    assert outerSteps[3].Depth == 2
    // Both walks closed everything they opened, and the ambient context came all the way back.
    assert harness.Scopes.Count == 1
    assert harness.Ambient.CurrentTypeName == null
    assert harness.Ambient.CurrentClass == null
}

test "THE MEMBER STEP ANSWERS NOTHING, SO A RE-ENTRY CANNOT DISTURB THE OUTER WALK'S FOLD" {
    harness := TypeDeclDefault()
    members := new List<Declaration>()
    members.Add(TypeDeclField("count", TypeDeclInt(), null, Modifiers.None))
    declaration := TypeDeclClass("Box", members, null, null, Modifiers.None)

    // Supplying a bogus answer to EVERY step of the outer walk changes nothing: only kind 1 folds,
    // and the type band never asks for it.
    steps := TypeDeclRun(harness, harness.Declarations.BeginClass(declaration, harness.Assignability), BuiltInTypes.String)

    assert TypeDeclKinds(steps) == "2,3,7,5"
    assert steps[1].CarriedType != "string"
}

// ---------------------------------------------------------------------------------------------
// THE BALANCE INVARIANTS
// ---------------------------------------------------------------------------------------------

test "EVERY FORM OPENS EXACTLY AS MANY SCOPES AS IT CLOSES, AND THE DEPTH COMES BACK" {
    classHarness := TypeDeclDefault()
    classSteps := TypeDeclRun(classHarness, classHarness.Declarations.BeginClass(TypeDeclClass("Box", TypeDeclMembers(TypeDeclFunction("Area", Modifiers.None)), null, TypeDeclOneParameter(TypeDeclParameter("size", "int", 7, 24)), Modifiers.None), classHarness.Assignability), null)
    assert TypeDeclCountKind(classSteps, 2) == TypeDeclCountKind(classSteps, 5)
    assert TypeDeclCountKind(classSteps, 2) == 1
    assert classHarness.Scopes.Count == 1

    structHarness := TypeDeclDefault()
    structSteps := TypeDeclRun(structHarness, structHarness.Declarations.BeginStruct(TypeDeclStruct("Point", TypeDeclNoMembers(), null, null, Modifiers.None), structHarness.Assignability), null)
    assert TypeDeclCountKind(structSteps, 2) == TypeDeclCountKind(structSteps, 5)
    assert structHarness.Scopes.Count == 1

    interfaceHarness := TypeDeclDefault()
    interfaceSteps := TypeDeclRun(interfaceHarness, interfaceHarness.Declarations.BeginInterface(TypeDeclInterface("Shape", TypeDeclNoMembers(), Modifiers.None), interfaceHarness.Assignability), null)
    assert TypeDeclCountKind(interfaceSteps, 2) == TypeDeclCountKind(interfaceSteps, 5)
    assert interfaceHarness.Scopes.Count == 1

    unionHarness := TypeDeclDefault()
    unionCases := new List<UnionCase>()
    unionCases.Add(TypeDeclUnionCase("Some", 8))
    unionSteps := TypeDeclRun(unionHarness, unionHarness.Declarations.BeginUnion(TypeDeclUnion("Option", unionCases, Modifiers.None), unionHarness.Assignability), null)
    assert TypeDeclCountKind(unionSteps, 2) == TypeDeclCountKind(unionSteps, 5)
    assert unionHarness.Scopes.Count == 1

    enumHarness := TypeDeclDefault()
    enumMembers := new List<EnumMember>()
    enumMembers.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    enumSteps := TypeDeclRun(enumHarness, enumHarness.Declarations.BeginEnum(TypeDeclEnum("Colour", enumMembers, EnumType.Int, Modifiers.None), enumHarness.Assignability), BuiltInTypes.Int)
    assert TypeDeclCountKind(enumSteps, 2) == 0
    assert TypeDeclCountKind(enumSteps, 5) == 0
    assert enumHarness.Scopes.Count == 1

    fieldHarness := TypeDeclDefault()
    fieldSteps := TypeDeclRun(fieldHarness, fieldHarness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), null, Modifiers.None), fieldHarness.Assignability), null)
    assert TypeDeclCountKind(fieldSteps, 2) == 0
    assert TypeDeclCountKind(fieldSteps, 5) == 0
    assert fieldHarness.Scopes.Count == 1
}

test "NO FORM ASKS FOR A KIND OUTSIDE 1..9, AND THE LAST STEP OF EVERY SCOPED FORM IS ITS CLOSE" {
    harness := TypeDeclDefault()
    steps := TypeDeclRun(harness, harness.Declarations.BeginClass(TypeDeclClass("Box", TypeDeclMembers(TypeDeclFunction("Area", Modifiers.None)), null, TypeDeclOneParameter(TypeDeclParameter("size", "int", 7, 24)), Modifiers.None), harness.Assignability), null)

    index := 0
    while index < steps.Count {
        assert steps[index].Kind >= 1
        assert steps[index].Kind <= 9
        index = index + 1
    }

    assert steps[steps.Count - 1].Kind == 5
    assert steps[steps.Count - 1].Depth == 2
}

// ---------------------------------------------------------------------------------------------
// THE NAMING CONVENTION, ACROSS THE FORMS
// ---------------------------------------------------------------------------------------------

test "SEVEN FORMS CHECK THE NAMING CONVENTION AND THE `soa record` DOES NOT" {
    classHarness := TypeDeclDefault()
    TypeDeclRun(classHarness, classHarness.Declarations.BeginClass(TypeDeclClass("_box", TypeDeclNoMembers(), null, null, Modifiers.None), classHarness.Assignability), null)
    assert classHarness.Errors.Count == 1
    assert classHarness.Errors[0].Code == ErrorCode.VisibilityConventionWarning

    structHarness := TypeDeclDefault()
    TypeDeclRun(structHarness, structHarness.Declarations.BeginStruct(TypeDeclStruct("_point", TypeDeclNoMembers(), null, null, Modifiers.None), structHarness.Assignability), null)
    assert structHarness.Errors.Count == 1

    recordHarness := TypeDeclDefault()
    TypeDeclRun(recordHarness, recordHarness.Declarations.BeginRecord(TypeDeclRecord("_pair", TypeDeclNoMembers(), null, Modifiers.None), recordHarness.Assignability), null)
    assert recordHarness.Errors.Count == 1

    interfaceHarness := TypeDeclDefault()
    TypeDeclRun(interfaceHarness, interfaceHarness.Declarations.BeginInterface(TypeDeclInterface("_shape", TypeDeclNoMembers(), Modifiers.None), interfaceHarness.Assignability), null)
    assert interfaceHarness.Errors.Count == 1

    unionHarness := TypeDeclDefault()
    unionCases := new List<UnionCase>()
    unionCases.Add(TypeDeclUnionCase("Some", 8))
    TypeDeclRun(unionHarness, unionHarness.Declarations.BeginUnion(TypeDeclUnion("_option", unionCases, Modifiers.None), unionHarness.Assignability), null)
    assert unionHarness.Errors.Count == 1

    enumHarness := TypeDeclDefault()
    TypeDeclRun(enumHarness, enumHarness.Declarations.BeginEnum(TypeDeclEnum("_colour", new List<EnumMember>(), EnumType.Int, Modifiers.None), enumHarness.Assignability), null)
    assert enumHarness.Errors.Count == 1

    fieldHarness := TypeDeclDefault()
    TypeDeclRun(fieldHarness, fieldHarness.Declarations.BeginField(TypeDeclField("_count", TypeDeclInt(), null, Modifiers.None), fieldHarness.Assignability), null)
    assert fieldHarness.Errors.Count == 1
    assert fieldHarness.Errors[0].Code == ErrorCode.VisibilityConventionWarning

    // The `soa record` is never held to it, and that asymmetry is shipped behaviour: the only report
    // here is the experimental gate's.
    soaHarness := TypeDeclDefault()
    soaColumns := new List<SoaColumnDeclaration>()
    soaColumns.Add(TypeDeclColumn("id", "int", 8))
    TypeDeclRun(soaHarness, soaHarness.Declarations.BeginSoaRecord(TypeDeclSoaRecord("_rows", soaColumns, Modifiers.None), soaHarness.Assignability), null)
    assert soaHarness.Errors.Count == 1
    assert soaHarness.Errors[0].Code == ErrorCode.FeatureNotImplemented
}

test "AN EXPLICIT VISIBILITY MODIFIER OPTS OUT, AND A LOWERCASE NAME IS SIMPLY UNEXPORTED" {
    explicitHarness := TypeDeclDefault()
    TypeDeclRun(explicitHarness, explicitHarness.Declarations.BeginClass(TypeDeclClass("_box", TypeDeclNoMembers(), null, null, Modifiers.Private), explicitHarness.Assignability), null)
    assert explicitHarness.Errors.Count == 0

    lowerHarness := TypeDeclDefault()
    TypeDeclRun(lowerHarness, lowerHarness.Declarations.BeginClass(TypeDeclClass("box", TypeDeclNoMembers(), null, null, Modifiers.None), lowerHarness.Assignability), null)
    assert lowerHarness.Errors.Count == 0

    upperHarness := TypeDeclDefault()
    TypeDeclRun(upperHarness, upperHarness.Declarations.BeginClass(TypeDeclClass("Box", TypeDeclNoMembers(), null, null, Modifiers.None), upperHarness.Assignability), null)
    assert upperHarness.Errors.Count == 0
}

test "THE CONVENTION IS CHECKED BEFORE THE DECLARED TYPE IS LOOKED UP OR THE SCOPE OPENS" {
    harness := TypeDeclDefault()

    steps := TypeDeclRun(harness, harness.Declarations.BeginClass(TypeDeclClass("_box", TypeDeclNoMembers(), null, null, Modifiers.None), harness.Assignability), null)

    // The report is already in the sink when the very first step is handed out, and that step is the
    // scope push — so the report lands OUTSIDE the type's own scope.
    assert steps[0].Kind == 2
    assert steps[0].ErrorCount == 1
    assert steps[0].Depth == 1
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 10
    assert harness.Errors[0].Length == 4
}

// ---------------------------------------------------------------------------------------------
// THE GENERIC-STATIC RULE
// ---------------------------------------------------------------------------------------------

test "A GENERIC TYPE MAY NOT CARRY A STATIC MEMBER, AND THE REPORT NAMES ITS PARAMETERS" {
    harness := TypeDeclDefault()
    members := new List<Declaration>()
    members.Add(TypeDeclField("Cache", TypeDeclInt(), null, Modifiers.Static))
    declaration := TypeDeclClass("Box", members, TypeDeclTypeParameters("T"), null, Modifiers.None)

    TypeDeclRun(harness, harness.Declarations.BeginClass(declaration, harness.Assignability), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.FeatureNotImplemented
    assert harness.Errors[0].Message.Contains("Static field 'Cache'")
    assert harness.Errors[0].Message.Contains("'Box<T>'")
}

test "A STATIC METHOD AND A NON-GENERIC TYPE ANSWER THE GENERIC-STATIC RULE DIFFERENTLY" {
    methodHarness := TypeDeclDefault()
    methodMembers := new List<Declaration>()
    methodMembers.Add(TypeDeclFunction("Make", Modifiers.Static))
    TypeDeclRun(methodHarness, methodHarness.Declarations.BeginClass(TypeDeclClass("Box", methodMembers, TypeDeclTypeParameters("T"), null, Modifiers.None), methodHarness.Assignability), null)
    assert methodHarness.Errors.Count == 1
    assert methodHarness.Errors[0].Message.Contains("Static method 'Make'")

    plainHarness := TypeDeclDefault()
    plainMembers := new List<Declaration>()
    plainMembers.Add(TypeDeclFunction("Make", Modifiers.Static))
    TypeDeclRun(plainHarness, plainHarness.Declarations.BeginClass(TypeDeclClass("Box", plainMembers, null, null, Modifiers.None), plainHarness.Assignability), null)
    assert plainHarness.Errors.Count == 0

    // An INTERFACE is never asked at all, generic or not.
    interfaceHarness := TypeDeclDefault()
    interfaceMembers := new List<Declaration>()
    interfaceMembers.Add(TypeDeclFunction("Make", Modifiers.Static))
    TypeDeclRun(interfaceHarness, interfaceHarness.Declarations.BeginInterface(TypeDeclInterface("Shape", interfaceMembers, Modifiers.None), interfaceHarness.Assignability), null)
    assert interfaceHarness.Errors.Count == 0
}

test "A TYPE PARAMETER IS DECLARED INTO THE SCOPE THE WALK JUST OPENED" {
    harness := TypeDeclDefault()
    declaration := TypeDeclClass("Box", TypeDeclNoMembers(), TypeDeclTypeParameters("T"), null, Modifiers.None)

    state := harness.Declarations.BeginClass(declaration, harness.Assignability)
    first := harness.Declarations.NextStep(state)
    assert first != null
    assert first.Kind == 2
    harness.Scopes.Push(harness.Model, new Scope(first.CarriedScopeKind), first.Line, first.Column)
    harness.Declarations.Supply(state, null)

    second := harness.Declarations.NextStep(state)
    // By the time `this` is asked for, `T` is a type in the OPEN scope — which is what makes a base
    // type or a member signature written in terms of it resolve.
    assert second != null
    assert second.Kind == 3
    assert harness.Scopes.LookupType("T") != null
}

// ---------------------------------------------------------------------------------------------
// THE UNION AND ENUM MEMBER RULES
// ---------------------------------------------------------------------------------------------

test "A DUPLICATED UNION CASE IS REPORTED ONCE, AT ITS OWN POSITION" {
    harness := TypeDeclDefault()
    cases := new List<UnionCase>()
    cases.Add(TypeDeclUnionCase("Some", 8))
    cases.Add(TypeDeclUnionCase("Some", 9))
    cases.Add(TypeDeclUnionCase("None", 10))

    TypeDeclRun(harness, harness.Declarations.BeginUnion(TypeDeclUnion("Option", cases, Modifiers.None), harness.Assignability), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.DuplicateDeclaration
    assert harness.Errors[0].Line == 9
    assert harness.Errors[0].Column == 12
    assert harness.Errors[0].Message.Contains("Union case 'Some'")
}

test "THE UNION CASE'S POSITION FALLS BACK PER AXIS, NOT AS A PAIR" {
    harness := TypeDeclDefault()
    cases := new List<UnionCase>()
    cases.Add(TypeDeclUnionCase("Some", 8))
    cases.Add(TypeDeclUnionCase("Some", 0))

    TypeDeclRun(harness, harness.Declarations.BeginUnion(TypeDeclUnion("Option", cases, Modifiers.None), harness.Assignability), null)

    // The LINE falls back to the union's because the case carries none; the COLUMN does not, because
    // the case carries one. The two axes are independent guards in the C# this replaces, and a walk
    // that fell back as a PAIR would move this squiggle.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 12

    bothHarness := TypeDeclDefault()
    bothCases := new List<UnionCase>()
    bothCases.Add(TypeDeclUnionCase("Some", 8))
    bothCases.Add(new UnionCase("Some", null, 0, 0))
    TypeDeclRun(bothHarness, bothHarness.Declarations.BeginUnion(TypeDeclUnion("Option", bothCases, Modifiers.None), bothHarness.Assignability), null)
    assert bothHarness.Errors[0].Line == 7
    assert bothHarness.Errors[0].Column == 10
}

test "A DUPLICATED ENUM MEMBER IS REPORTED, AND EVERY MEMBER'S INITIALIZER IS STILL WALKED" {
    harness := TypeDeclDefault()
    members := new List<EnumMember>()
    members.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    members.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 9))

    steps := TypeDeclRun(harness, harness.Declarations.BeginEnum(TypeDeclEnum("Colour", members, EnumType.Int, Modifiers.None), harness.Assignability), BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.DuplicateDeclaration
    assert harness.Errors[0].Message.Contains("Enum member 'A'")
    // The duplicate rule does not stop the walk: both initializers are still analysed.
    assert TypeDeclKinds(steps) == "1,1"
}

test "AN INT ENUM TAKES A NUMERIC VALUE AND A STRING ENUM TAKES A STRING ONE" {
    intHarness := TypeDeclDefault()
    intMembers := new List<EnumMember>()
    intMembers.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    TypeDeclRun(intHarness, intHarness.Declarations.BeginEnum(TypeDeclEnum("Colour", intMembers, EnumType.Int, Modifiers.None), intHarness.Assignability), BuiltInTypes.Int)
    assert intHarness.Errors.Count == 0

    wrongHarness := TypeDeclDefault()
    wrongMembers := new List<EnumMember>()
    wrongMembers.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    TypeDeclRun(wrongHarness, wrongHarness.Declarations.BeginEnum(TypeDeclEnum("Colour", wrongMembers, EnumType.Int, Modifiers.None), wrongHarness.Assignability), BuiltInTypes.String)
    assert wrongHarness.Errors.Count == 1
    assert wrongHarness.Errors[0].Code == ErrorCode.TypeMismatch
    assert wrongHarness.Errors[0].Message.Contains("must have a numeric value")

    stringHarness := TypeDeclDefault()
    stringMembers := new List<EnumMember>()
    stringMembers.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    TypeDeclRun(stringHarness, stringHarness.Declarations.BeginEnum(TypeDeclEnum("Colour", stringMembers, EnumType.String, Modifiers.None), stringHarness.Assignability), BuiltInTypes.String)
    assert stringHarness.Errors.Count == 0

    wrongStringHarness := TypeDeclDefault()
    wrongStringMembers := new List<EnumMember>()
    wrongStringMembers.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    TypeDeclRun(wrongStringHarness, wrongStringHarness.Declarations.BeginEnum(TypeDeclEnum("Colour", wrongStringMembers, EnumType.String, Modifiers.None), wrongStringHarness.Assignability), BuiltInTypes.Int)
    assert wrongStringHarness.Errors.Count == 1
    assert wrongStringHarness.Errors[0].Message.Contains("must have a string value")
}

test "`char` COUNTS AS NUMERIC FOR AN INT ENUM, WHICH IS THE TWELVE-TYPE SET THE SHELL LISTS" {
    charHarness := TypeDeclDefault()
    charMembers := new List<EnumMember>()
    charMembers.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    TypeDeclRun(charHarness, charHarness.Declarations.BeginEnum(TypeDeclEnum("Colour", charMembers, EnumType.Int, Modifiers.None), charHarness.Assignability), BuiltInTypes.Char)
    assert charHarness.Errors.Count == 0

    decimalHarness := TypeDeclDefault()
    decimalMembers := new List<EnumMember>()
    decimalMembers.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    TypeDeclRun(decimalHarness, decimalHarness.Declarations.BeginEnum(TypeDeclEnum("Colour", decimalMembers, EnumType.Int, Modifiers.None), decimalHarness.Assignability), BuiltInTypes.Decimal)
    assert decimalHarness.Errors.Count == 0

    boolHarness := TypeDeclDefault()
    boolMembers := new List<EnumMember>()
    boolMembers.Add(TypeDeclEnumMember("A", TypeDeclIntLiteral(), 8))
    TypeDeclRun(boolHarness, boolHarness.Declarations.BeginEnum(TypeDeclEnum("Colour", boolMembers, EnumType.Int, Modifiers.None), boolHarness.Assignability), BuiltInTypes.Bool)
    assert boolHarness.Errors.Count == 1
}

// ---------------------------------------------------------------------------------------------
// THE `soa record` RULES
// ---------------------------------------------------------------------------------------------

test "A NESTED `soa record` IS REFUSED BY THE AMBIENT TYPE NAME THIS FAMILY ITSELF SETS" {
    harness := TypeDeclDefault()
    previous := Environment.GetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA")
    Environment.SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", "1")
    saved := harness.Ambient.EnterTypeName("Outer")

    columns := new List<SoaColumnDeclaration>()
    columns.Add(TypeDeclColumn("id", "int", 8))
    TypeDeclRun(harness, harness.Declarations.BeginSoaRecord(TypeDeclSoaRecord("Rows", columns, Modifiers.None), harness.Assignability), null)

    harness.Ambient.ExitTypeName(saved)
    Environment.SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", previous)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message.Contains("nested soa record 'Rows'")
    assert harness.Errors[0].Length == 3
}

test "A COLUMN NAME IS TWO RULES, AND A NAME THAT BREAKS BOTH IS REPORTED TWICE" {
    harness := TypeDeclDefault()
    previous := Environment.GetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA")
    Environment.SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", "1")

    columns := new List<SoaColumnDeclaration>()
    columns.Add(TypeDeclColumn("length", "int", 8))
    columns.Add(TypeDeclColumn("length", "int", 9))
    TypeDeclRun(harness, harness.Declarations.BeginSoaRecord(TypeDeclSoaRecord("Rows", columns, Modifiers.None), harness.Assignability), null)

    Environment.SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", previous)

    // Column 1 collides with a generated member; column 2 collides with column 1 AND with the
    // generated member. Three reports, in that order.
    assert harness.Errors.Count == 3
    assert harness.Errors[0].Message.Contains("conflicts with a generated table member")
    assert harness.Errors[1].Message.Contains("is already defined")
    assert harness.Errors[2].Message.Contains("conflicts with a generated table member")
}

test "AN UNSUPPORTED COLUMN TYPE IS REPORTED AND A SUPPORTED ONE IS NOT" {
    harness := TypeDeclDefault()
    previous := Environment.GetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA")
    Environment.SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", "1")

    columns := new List<SoaColumnDeclaration>()
    columns.Add(TypeDeclColumn("id", "int", 8))
    columns.Add(TypeDeclColumn("name", "string", 9))
    columns.Add(TypeDeclColumn("ratio", "double", 10))
    TypeDeclRun(harness, harness.Declarations.BeginSoaRecord(TypeDeclSoaRecord("Rows", columns, Modifiers.None), harness.Assignability), null)

    Environment.SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", previous)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message.Contains("SoA column type 'double'")
    assert harness.Errors[0].Line == 10
}

// ---------------------------------------------------------------------------------------------
// THE FIELD DECLARATION
// ---------------------------------------------------------------------------------------------

test "A FIELD WITH NEITHER A TYPE NOR AN INITIALIZER IS TOLD SO, AND IS STILL DECLARED" {
    harness := TypeDeclDefault()

    steps := TypeDeclRun(harness, harness.Declarations.BeginField(TypeDeclField("count", null, null, Modifiers.None), harness.Assignability), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert harness.Errors[0].Message.Contains("I can't determine the type of 'count'")
    // Declared anyway, as unknown, plus the unconditional top-level record. No containing type here.
    assert TypeDeclKinds(steps) == "3,9"
    assert steps[0].CarriedType == "unknown"
}

test "AN INFERRED FIELD TAKES ITS INITIALIZER'S TYPE, WALKED UNTARGETED" {
    harness := TypeDeclDefault()

    steps := TypeDeclRun(harness, harness.Declarations.BeginField(TypeDeclField("count", null, TypeDeclIntLiteral(), Modifiers.None), harness.Assignability), BuiltInTypes.Int)

    assert TypeDeclKinds(steps) == "1,3,9"
    assert steps[0].HasNode
    assert steps[1].CarriedType == "int"
    assert harness.Errors.Count == 0
}

test "AN INFERRED FIELD WHOSE INITIALIZER IS UNKNOWN IS TOLD TO ANNOTATE" {
    harness := TypeDeclDefault()

    steps := TypeDeclRun(harness, harness.Declarations.BeginField(TypeDeclField("count", null, TypeDeclIntLiteral(), Modifiers.None), harness.Assignability), BuiltInTypes.Unknown)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message.Contains("I can't figure out the type of 'count'")
    assert TypeDeclKinds(steps) == "1,3,9"
}

test "A DECLARED FIELD KEEPS ITS DECLARED TYPE EVEN WHEN THE INITIALIZER DOES NOT FIT" {
    harness := TypeDeclDefault()

    steps := TypeDeclRun(harness, harness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), TypeDeclIntLiteral(), Modifiers.None), harness.Assignability), BuiltInTypes.String)

    assert harness.Errors.Count == 1
    // No source text in this harness, so the DETAIL-ONLY shape — and it carries INVALID SYNTAX
    // rather than TYPE MISMATCH, which is what the three-argument `Error` overload defaulted to.
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert harness.Errors[0].Message.Contains("Field 'count' is typed as 'int'")
    assert harness.Errors[0].Message.Contains("initializer gives 'string'")
    assert harness.Errors[0].Line == 7
    assert TypeDeclKinds(steps) == "1,3,9"
    assert steps[1].CarriedType == "int"
}

test "WITH SOURCE TEXT THE SAME MISMATCH IS THE RICH TYPE-MISMATCH SHAPE AT THE INITIALIZER" {
    harness := TypeDeclHarnessWith("line one\nline two\nline three\nline four\nline five\nline six\nlet count: int = value\n")

    TypeDeclRun(harness, harness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), TypeDeclIntLiteral(), Modifiers.None), harness.Assignability), BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Column == 30

    // The CODE differs between the two shapes and the ANCHOR differs; the SENTENCE does not. The
    // rich route used to say only the bare words `Type mismatch`.
    assert harness.Errors[0].Message == "Field 'count' is typed as 'int', but the initializer gives 'string'"
}

test "A DECLARED FIELD WHOSE INITIALIZER FITS IS SILENT, AND ONE WITH NO INITIALIZER TAKES NO STEP" {
    fitHarness := TypeDeclDefault()
    fitSteps := TypeDeclRun(fitHarness, fitHarness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), TypeDeclIntLiteral(), Modifiers.None), fitHarness.Assignability), BuiltInTypes.Int)
    assert fitHarness.Errors.Count == 0
    assert TypeDeclKinds(fitSteps) == "1,3,9"

    bareHarness := TypeDeclDefault()
    bareSteps := TypeDeclRun(bareHarness, bareHarness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), null, Modifiers.None), bareHarness.Assignability), null)
    assert TypeDeclKinds(bareSteps) == "3,9"
    assert bareHarness.Errors.Count == 0
}

test "THE TARGET-TYPING SLOT IS OPEN ACROSS THE CHECKED ARM'S WALK AND CLOSED BEFORE ANY RULE" {
    harness := TypeDeclDefault()
    state := harness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), TypeDeclIntLiteral(), Modifiers.None), harness.Assignability)

    step := harness.Declarations.NextStep(state)
    // The initializer is asked for with the field's type HELD in the ambient slot — which is what
    // makes a collection literal, a `default` or an untyped `new()` take the field's type.
    assert step != null
    assert step.Kind == 1
    assert TypeDeclText(harness.Ambient.CurrentExpectedType) == "int"

    harness.Declarations.Supply(state, BuiltInTypes.Int)
    next := harness.Declarations.NextStep(state)
    // And it is closed again the moment the answer is folded in, before the declare step.
    assert next != null
    assert next.Kind == 3
    assert harness.Ambient.CurrentExpectedType == null
}

test "A FIELD INSIDE A TYPE WRITES BOTH IDE RECORDS AND ONE OUTSIDE WRITES ONLY THE TOP-LEVEL ONE" {
    insideHarness := TypeDeclDefault()
    saved := insideHarness.Ambient.EnterTypeName("Box")
    insideSteps := TypeDeclRun(insideHarness, insideHarness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), null, Modifiers.None), insideHarness.Assignability), null)
    insideHarness.Ambient.ExitTypeName(saved)

    assert TypeDeclKinds(insideSteps) == "3,8,9"
    assert insideSteps[1].ContainingType == "Box"
    assert insideSteps[1].Name == "count"
    assert insideSteps[1].CarriedType == "int"
    assert insideSteps[2].ContainingType == null
    assert insideSteps[2].CarriedType == "int"

    outsideHarness := TypeDeclDefault()
    outsideSteps := TypeDeclRun(outsideHarness, outsideHarness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), null, Modifiers.None), outsideHarness.Assignability), null)
    assert TypeDeclKinds(outsideSteps) == "3,9"
}

test "THE FIELD'S NAME IS DECLARED AFTER EVERY RULE, SO A REFUSED INITIALIZER STILL LEAVES A NAME" {
    harness := TypeDeclDefault()

    steps := TypeDeclRun(harness, harness.Declarations.BeginField(TypeDeclField("count", TypeDeclInt(), TypeDeclIntLiteral(), Modifiers.None), harness.Assignability), BuiltInTypes.String)

    declareIndex := 0
    index := 0
    while index < steps.Count {
        if steps[index].Kind == 3 {
            declareIndex = index
        }

        index = index + 1
    }

    // The report is already in the sink when the declare step is handed out.
    assert steps[declareIndex].ErrorCount == 1
    assert steps[declareIndex].Name == "count"
}

// ---------------------------------------------------------------------------------------------
// THE OVERRIDE-TARGET RULE
//
// `override` was accepted with NO check at all before this: a member declared `override` over a
// plain base method, or over a base member that does not exist, produced not one diagnostic (020/34
// measured it with two independent probes and filed it). The rule has three verdicts and a fourth
// that is SILENCE, and every one of them is pinned here — because the dangerous failure mode of a
// new declaration rule is not the fault it misses, it is the correct program it rejects.
// ---------------------------------------------------------------------------------------------

func TypeDeclMemberInfo(name: string, modifierBits: int): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        name,
        "Owner",
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
        1,
        modifierBits
    )
}

// The property sibling of `TypeDeclMemberInfo`. A separate builder rather than a widened one, because
// the existing five call sites spell the two-argument form and an N# caller cannot omit a defaulted
// parameter of a free function.
func TypeDeclPropertyMemberInfo(name: string, modifierBits: int): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        name,
        "Owner",
        DeclaredMemberKind.Property,
        "property",
        null,
        false,
        false,
        true,
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
        1,
        modifierBits
    )
}

func TypeDeclProperty(name: string, modifiers: Modifiers): PropertyDeclaration {
    body: Expression = new StringLiteralExpression("\"v\"", 8, 20, false)
    return new PropertyDeclaration(name, TypeDeclInt(), null, null, body, modifiers, PropertyModifier.None, TypeDeclNoAttributes(), 8, 5)
}

// A member that CARRIES A BODY — the `hasBody` trailing argument the interface rule reads. Built as a
// separate helper for the same reason `TypeDeclPropertyMemberInfo` is: the existing call sites spell
// the shorter form and an N# caller cannot omit a defaulted parameter of a FREE FUNCTION.
func TypeDeclDefaultedMemberInfo(name: string, kind: DeclaredMemberKind): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        name,
        "Owner",
        kind,
        "member",
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
        1,
        0,
        true
    )
}

func TypeDeclSourceInterface(name: string, members: DeclaredMemberInfo[]): TypeInfo {
    owner: TypeInfo = new InterfaceTypeInfo(name, 1, 1, false, new TypeReference[](0), new TypeParameter[](0), members, new NestedTypeInfo[](0))
    return owner
}

func TypeDeclClosedGeneric(name: string, definition: TypeInfo?): TypeInfo {
    owner: TypeInfo = new GenericTypeInfo(name, new List<TypeInfo>(), definition)
    return owner
}

func TypeDeclAbstractBits(): int {
    return Convert.ToInt32(Modifiers.Abstract)
}

func TypeDeclMemberInfos2(first: DeclaredMemberInfo, second: DeclaredMemberInfo): DeclaredMemberInfo[] {
    members := new DeclaredMemberInfo[](2)
    members[0] = first
    members[1] = second
    return members
}

func TypeDeclNames(names: List<string>): string {
    joined := ""
    index := 0
    while index < names.Count {
        if index > 0 {
            joined = joined + ","
        }

        joined = joined + names[index]
        index = index + 1
    }

    return joined
}

func TypeDeclEmptyNames(): HashSet<string> {
    return new HashSet<string>(StringComparer.Ordinal)
}

func TypeDeclNamesOf(name: string): HashSet<string> {
    seen := new HashSet<string>(StringComparer.Ordinal)
    seen.Add(name)
    return seen
}

func TypeDeclMemberInfos(first: DeclaredMemberInfo): DeclaredMemberInfo[] {
    members := new DeclaredMemberInfo[](1)
    members[0] = first
    return members
}

func TypeDeclSourceOwner(name: string, members: DeclaredMemberInfo[]): TypeInfo {
    owner: TypeInfo = new ClassTypeInfo(name, 1, 1, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), members, new NestedTypeInfo[](0), true)
    return owner
}

func TypeDeclVirtualBits(): int {
    return Convert.ToInt32(Modifiers.Virtual)
}

func TypeDeclOverrideBits(): int {
    return Convert.ToInt32(Modifiers.Override)
}

func TypeDeclSealedOverrideBits(): int {
    return Convert.ToInt32(Modifiers.Override) + Convert.ToInt32(Modifiers.Sealed)
}

test "A MEMBER IS OVERRIDABLE WHEN IT OPENS A SLOT, AND A SEALED OVERRIDE CLOSES ONE" {
    assert !TypeDeclMemberInfo("Speak", 0).IsOverridable
    assert TypeDeclMemberInfo("Speak", TypeDeclVirtualBits()).IsOverridable
    assert TypeDeclMemberInfo("Speak", Convert.ToInt32(Modifiers.Abstract)).IsOverridable
    assert TypeDeclMemberInfo("Speak", TypeDeclOverrideBits()).IsOverridable
    assert !TypeDeclMemberInfo("Speak", TypeDeclSealedOverrideBits()).IsOverridable

    // The whole modifier word survives the factory, which is what makes the question askable at all.
    assert TypeDeclMemberInfo("Speak", TypeDeclSealedOverrideBits()).DeclaredModifiers == 65664
}

test "THE SOURCE ARM READS THE BASE MEMBER'S OWN MODIFIERS, AND ONLY A FUNCTION ANSWERS" {
    assert AnalyzerTypeDeclarations.ClassifyDeclaredOverrideTarget(
        TypeDeclMemberInfos(TypeDeclMemberInfo("Speak", TypeDeclVirtualBits())),
        "Speak"
    ) == 1
    assert AnalyzerTypeDeclarations.ClassifyDeclaredOverrideTarget(
        TypeDeclMemberInfos(TypeDeclMemberInfo("Speak", 0)),
        "Speak"
    ) == 2

    // A member of another name is not this one's slot, and the walk must keep going rather than
    // answer — 0 is "not found HERE", which is what sends the walk to the base above.
    assert AnalyzerTypeDeclarations.ClassifyDeclaredOverrideTarget(
        TypeDeclMemberInfos(TypeDeclMemberInfo("Bark", TypeDeclVirtualBits())),
        "Speak"
    ) == 0
}

test "METADATA ANSWERS FOR AN EXTERNAL BASE, AND `object` IS THE IMPLICIT ROOT" {
    // `ToString` is virtual on every CLR type; `GetType` is not, and never was — which is why
    // `override func GetType()` is a real fault rather than a tolerated one.
    assert AnalyzerTypeDeclarations.ClassifyReflectionOverrideTarget(typeof(Exception), "ToString") == 1
    assert AnalyzerTypeDeclarations.ClassifyReflectionOverrideTarget(typeof(Exception), "GetType") == 2
    assert AnalyzerTypeDeclarations.ClassifyReflectionOverrideTarget(typeof(Exception), "Speak") == 3

    assert AnalyzerTypeDeclarations.ClassifyObjectOverrideTarget("ToString") == 1
    assert AnalyzerTypeDeclarations.ClassifyObjectOverrideTarget("GetHashCode") == 1
    assert AnalyzerTypeDeclarations.ClassifyObjectOverrideTarget("GetType") == 2
    assert AnalyzerTypeDeclarations.ClassifyObjectOverrideTarget("Speak") == 3
}

test "THE WALK ENDS AT `object` WHEN A SOURCE CHAIN NAMES NO FURTHER BASE" {
    harness := TypeDeclDefault()

    virtualBase := TypeDeclSourceOwner("Animal", TypeDeclMemberInfos(TypeDeclMemberInfo("Speak", TypeDeclVirtualBits())))
    assert harness.Declarations.ClassifyOverrideTarget(virtualBase, "Speak", 0) == 1

    plainBase := TypeDeclSourceOwner("Animal", TypeDeclMemberInfos(TypeDeclMemberInfo("Speak", 0)))
    assert harness.Declarations.ClassifyOverrideTarget(plainBase, "Speak", 0) == 2

    // Not on the source shape, so the walk falls through to `object`: `ToString` is open there and
    // `Speak` is nowhere at all.
    assert harness.Declarations.ClassifyOverrideTarget(plainBase, "ToString", 0) == 1
    assert harness.Declarations.ClassifyOverrideTarget(plainBase, "Speak2", 0) == 3

    // SILENCE IS THE DEFAULT. A base that resolved to nothing, and a depth past the cycle brake,
    // both answer "cannot tell" — the two ways this rule refuses to guess.
    assert harness.Declarations.ClassifyOverrideTarget(BuiltInTypes.Unknown, "Speak", 0) == 0
    assert harness.Declarations.ClassifyOverrideTarget(plainBase, "Speak", 25) == 0
}

test "AN `override` WITH NO SLOT TO TAKE IS `NL311`, AND THE REPORT NAMES WHICH HALF FAILED" {
    missingHarness := TypeDeclDefault()
    missingMembers := new List<Declaration>()
    missingMembers.Add(TypeDeclFunction("Speak", Modifiers.Override))
    TypeDeclRun(missingHarness, missingHarness.Declarations.BeginClass(TypeDeclClass("Dog", missingMembers, null, null, Modifiers.None), missingHarness.Assignability), null)

    assert missingHarness.Errors.Count == 1
    assert missingHarness.Errors[0].Code == ErrorCode.InvalidModifier
    assert missingHarness.Errors[0].Message == "'Speak' is declared 'override', but it has no base member of that name"
    assert missingHarness.Errors[0].Length == 5

    sealedHarness := TypeDeclDefault()
    sealedMembers := new List<Declaration>()
    sealedMembers.Add(TypeDeclFunction("GetType", Modifiers.Override))
    TypeDeclRun(sealedHarness, sealedHarness.Declarations.BeginClass(TypeDeclClass("Dog", sealedMembers, null, null, Modifiers.None), sealedHarness.Assignability), null)

    assert sealedHarness.Errors.Count == 1
    assert sealedHarness.Errors[0].Code == ErrorCode.InvalidModifier
    assert sealedHarness.Errors[0].Message == "'GetType' is declared 'override', but it is not marked 'virtual', 'abstract' or 'override'"
}

// ---------------------------------------------------------------------------------------------
// A DECLARED INTERFACE THE TYPE DOES NOT IMPLEMENT (`NL325`)
//
// NOTHING EVER CHECKED THIS. `interface Greeter { func Greet(): string }` with
// `class English : Greeter { }` was silent, and so were `class Resource : IDisposable { }`,
// `struct Point : Greeter { }` and `record Person : Greeter { }`. A declared interface is a promise to
// callers, and an unkept one is a type that cannot satisfy the calls its own declaration invites.
//
// TWO THINGS THIS RULE HAD TO GET RIGHT THAT THE ABSTRACT RULE DID NOT.
//   (1) WHERE THE INTERFACES ARE IS A SYNTACTIC ACCIDENT. The parser splits a class's `: A, B, C` by
//       POSITION — `[0]` to `BaseClass`, the rest to `Interfaces` — so `class R : IDisposable` carries
//       its interface in the base-CLASS slot. Both slots are read and each kept only if it RESOLVES to
//       an interface, which is the semantic question the parser could not answer.
//   (2) A MEMBER WITH A BODY IS A DEFAULT IMPLEMENTATION. The first estate census caught this and
//       nothing else: `examples/06-classes-and-records/RecordsAndInterfaces.nl` is correct N# and was
//       accused of not implementing the very member its interface had written out.
// ---------------------------------------------------------------------------------------------

test "an interface is recognised through a reflection type, a source shape AND a closed generic" {
    assert AnalyzerTypeDeclarations.IsInterfaceType(TypeDeclSourceInterface("Greeter", new DeclaredMemberInfo[](0)))
    assert !AnalyzerTypeDeclarations.IsInterfaceType(TypeDeclSourceOwner("Base", new DeclaredMemberInfo[](0)))

    disposableType := Type.GetType("System.IDisposable")
    assert disposableType != null
    if disposableType != null {
        reflected: TypeInfo = new ReflectionTypeInfo(disposableType)
        assert AnalyzerTypeDeclarations.IsInterfaceType(reflected)
    }

    exceptionType: TypeInfo = new ReflectionTypeInfo(typeof(Exception))
    assert !AnalyzerTypeDeclarations.IsInterfaceType(exceptionType)

    // A CLOSED GENERIC IS A WRAPPER and every question here is answered by NAME, which no type argument
    // can change — so the wrapper is opened once and both callers work on what comes out.
    closed := TypeDeclClosedGeneric("Greeter", TypeDeclSourceInterface("Greeter", new DeclaredMemberInfo[](0)))
    assert AnalyzerTypeDeclarations.IsInterfaceType(closed)

    // A wrapper with NO definition is not opened: it answers "cannot tell", never "not an interface
    // and therefore fine".
    opaque := TypeDeclClosedGeneric("Greeter", null)
    assert !AnalyzerTypeDeclarations.IsInterfaceType(opaque)
    assert AnalyzerTypeDeclarations.OpenGenericInstantiation(opaque) == null

    plain := TypeDeclSourceOwner("Base", new DeclaredMemberInfo[](0))
    assert AnalyzerTypeDeclarations.OpenGenericInstantiation(plain) == plain
}

test "A MEMBER WITH A BODY SUPPLIES ITSELF; A MEMBER WITHOUT ONE IS A SLOT" {
    // The one line the first census found. A defaulted interface member requires nothing AND counts as
    // supplied, so a second interface demanding the same name does not re-report it.
    defaultedFunctions := TypeDeclEmptyNames()
    defaultedMissing := new List<string>()
    AnalyzerTypeDeclarations.RequireInterfaceMember(TypeDeclDefaultedMemberInfo("Describe", DeclaredMemberKind.Function), defaultedFunctions, TypeDeclEmptyNames(), defaultedMissing)
    assert defaultedMissing.Count == 0
    assert defaultedFunctions.Contains("Describe")

    defaultedValues := TypeDeclEmptyNames()
    valueMissing := new List<string>()
    AnalyzerTypeDeclarations.RequireInterfaceMember(TypeDeclDefaultedMemberInfo("Name", DeclaredMemberKind.Property), TypeDeclEmptyNames(), defaultedValues, valueMissing)
    assert valueMissing.Count == 0
    assert defaultedValues.Contains("Name")

    // NON-VACUITY: the same member WITHOUT a body is required.
    slotMissing := new List<string>()
    AnalyzerTypeDeclarations.RequireInterfaceMember(TypeDeclMemberInfo("Describe", 0), TypeDeclEmptyNames(), TypeDeclEmptyNames(), slotMissing)
    assert TypeDeclNames(slotMissing) == "Describe"

    // A name the implementer already supplies is not required.
    suppliedMissing := new List<string>()
    AnalyzerTypeDeclarations.RequireInterfaceMember(TypeDeclMemberInfo("Describe", 0), TypeDeclNamesOf("Describe"), TypeDeclEmptyNames(), suppliedMissing)
    assert suppliedMissing.Count == 0

    // The default is FALSE, so every one of the model's existing callers is unaffected.
    assert !TypeDeclMemberInfo("Describe", 0).HasBody
    assert TypeDeclDefaultedMemberInfo("Describe", DeclaredMemberKind.Function).HasBody
}

test "a CLR interface's requirements come from itself plus GetInterfaces, in one pass" {
    disposableType := Type.GetType("System.IDisposable")
    assert disposableType != null
    if disposableType != null {
        missing := new List<string>()
        AnalyzerTypeDeclarations.CollectReflectedInterfaceRequirements(disposableType, TypeDeclEmptyNames(), TypeDeclEmptyNames(), missing)
        assert TypeDeclNames(missing) == "Dispose"

        // Supplied by the implementer -> not required.
        supplied := new List<string>()
        AnalyzerTypeDeclarations.CollectReflectedInterfaceRequirements(disposableType, TypeDeclNamesOf("Dispose"), TypeDeclEmptyNames(), supplied)
        assert supplied.Count == 0
    }

    // `IEnumerable<T>` inherits the non-generic `IEnumerable`, and BOTH spell `GetEnumerator` — the
    // name is demanded ONCE because the supplied set is written as the walk goes.
    enumerableType := Type.GetType("System.Collections.Generic.IEnumerable`1")
    assert enumerableType != null
    if enumerableType != null {
        enumerableMissing := new List<string>()
        AnalyzerTypeDeclarations.CollectReflectedInterfaceRequirements(enumerableType, TypeDeclEmptyNames(), TypeDeclEmptyNames(), enumerableMissing)
        assert TypeDeclNames(enumerableMissing) == "GetEnumerator"
    }
}

test "a base class SUPPLIES its concrete members and supplies none of its abstract ones" {
    // The supply half of the same reflection pair. `MemoryStream` implements `Read`, so a
    // `class X : MemoryStream, ISomething` demanding `Read` is already satisfied.
    memoryStreamType := Type.GetType("System.IO.MemoryStream")
    assert memoryStreamType != null
    if memoryStreamType != null {
        suppliedFunctions := TypeDeclEmptyNames()
        suppliedValues := TypeDeclEmptyNames()
        AnalyzerTypeDeclarations.CollectReflectedMemberNames(memoryStreamType, suppliedFunctions, suppliedValues)
        assert suppliedFunctions.Contains("Read")
        assert suppliedValues.Contains("Length")
    }

    // `Stream`'s ABSTRACT members supply nothing — a slot is not a body — or a
    // `class X : Stream, ISomething` would look as if `Stream` had implemented them. `Flush` is the
    // clean case: one declaration, abstract.
    streamType := Type.GetType("System.IO.Stream")
    assert streamType != null
    if streamType != null {
        streamFunctions := TypeDeclEmptyNames()
        streamValues := TypeDeclEmptyNames()
        AnalyzerTypeDeclarations.CollectReflectedMemberNames(streamType, streamFunctions, streamValues)
        assert !streamFunctions.Contains("Flush")
        assert !streamValues.Contains("Length")
        assert !streamValues.Contains("Position")
        assert streamFunctions.Contains("CopyTo")

        // MEASURED, AND RECORDED AS A LIMITATION RATHER THAN ASSERTED AWAY: matching is by NAME, and
        // `Stream.Read` has TWO overloads — `Read(byte[], int, int)` is abstract while
        // `Read(Span<byte>)` is concrete. A name with any concrete overload therefore counts as
        // SUPPLIED. That is the under-reporting direction, which is the safe one for a rule whose
        // worst failure is the correct program it rejects; N# cannot spell overloads in a class body
        // anyway (a class with overloaded methods does not parse), so no N# source shape can reach it.
        assert streamFunctions.Contains("Read")
    }
}

test "the supply set splits FUNCTIONS from VALUE MEMBERS, and fields count as values" {
    // N# writes an interface's value member bare (`Id: int`, which the AST calls a FIELD) and an
    // implementer may spell it bare or with an accessor. Splitting those into different slots would
    // report correct programs, so fields and properties share one set.
    members := new List<Declaration>()
    members.Add(TypeDeclFunction("Greet", Modifiers.None))
    members.Add(TypeDeclProperty("Name", Modifiers.None))
    members.Add(TypeDeclField("Id", TypeDeclInt(), null, Modifiers.None))
    suppliedFunctions := TypeDeclEmptyNames()
    suppliedValues := TypeDeclEmptyNames()
    AnalyzerTypeDeclarations.AddDeclaredMemberNames(members, suppliedFunctions, suppliedValues)
    assert suppliedFunctions.Contains("Greet")
    assert !suppliedFunctions.Contains("Name")
    assert suppliedValues.Contains("Name")
    assert suppliedValues.Contains("Id")
}

test "`NL325` NAMES EVERY MISSING MEMBER IN ONE DIAGNOSTIC, on the TYPE name" {
    oneHarness := TypeDeclDefault()
    oneMissing := new List<string>()
    oneMissing.Add("Greet")
    oneState := oneHarness.Declarations.BeginClass(TypeDeclClass("English", new List<Declaration>(), null, null, Modifiers.None), oneHarness.Assignability)
    oneHarness.Declarations.ReportUnimplementedInterfaceMembers(oneState, oneMissing)
    assert oneHarness.Errors.Count == 1
    assert oneHarness.Errors[0].Code == ErrorCode.InterfaceMemberNotImplemented
    assert oneHarness.Errors[0].Message == "'English' declares an interface but does not implement its member 'Greet'"
    assert oneHarness.Errors[0].Suggestion == "Implement it in 'English', inherit it from a base class, or drop the interface from the declaration."
    assert oneHarness.Errors[0].Length == 7

    manyHarness := TypeDeclDefault()
    manyMissing := new List<string>()
    manyMissing.Add("Greet")
    manyMissing.Add("Farewell")
    manyState := manyHarness.Declarations.BeginClass(TypeDeclClass("English", new List<Declaration>(), null, null, Modifiers.None), manyHarness.Assignability)
    manyHarness.Declarations.ReportUnimplementedInterfaceMembers(manyState, manyMissing)
    assert manyHarness.Errors.Count == 1
    assert manyHarness.Errors[0].Message == "'English' declares an interface but does not implement 2 of its members: 'Greet', 'Farewell'"
    assert manyHarness.Errors[0].Suggestion == "Implement all 2 in 'English', inherit them from a base class, or drop the interface from the declaration."
}

test "a type that declares NO interface is never asked, whatever else is wrong with it" {
    harness := TypeDeclDefault()
    members := new List<Declaration>()
    members.Add(TypeDeclFunction("F", Modifiers.None))
    TypeDeclRun(harness, harness.Declarations.BeginClass(TypeDeclClass("Plain", members, null, null, Modifiers.None), harness.Assignability), null)
    assert harness.Errors.Count == 0

    // An ABSTRACT class may leave an interface member to its subclasses, exactly as it may leave an
    // abstract one.
    abstractHarness := TypeDeclDefault()
    abstractState := abstractHarness.Declarations.BeginClass(TypeDeclClass("PartialGreeter", new List<Declaration>(), null, null, Modifiers.Abstract), abstractHarness.Assignability)
    assert abstractHarness.Declarations.IsAbstractDeclaration(abstractState)
    TypeDeclRun(abstractHarness, abstractState, null)
    assert abstractHarness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// AN INHERITED ABSTRACT MEMBER THAT NOBODY IMPLEMENTED (`NL324`)
//
// A CONCRETE CLASS WITH AN UNIMPLEMENTED ABSTRACT SLOT IS NOT A STYLE PROBLEM, IT IS THE CS0534 HOLE.
// `abstract class Shape { abstract Area: double => … }` with `class Circle : Shape { }` beneath it
// reported nothing and EMITTED. The method spelling was equally silent. Both are measured below at the
// pieces, and end to end through `nlc check --json` in the commit message.
//
// The exemptions carry as much weight as the report: silence for a fully implemented class, for an
// ABSTRACT derived class, for a class with no written base, for a concrete CLR base, and for an
// intermediate concrete override that already discharged the obligation. And the walk abandons
// entirely — reporting nothing at all — the moment any link in the chain cannot be opened, because a
// missing set computed from half a chain is not a missing set.
// ---------------------------------------------------------------------------------------------

test "a first sighting that is ABSTRACT is missing; a first sighting that is not CLOSES the slot" {
    // `RecordAbstractCandidate` is the whole rule in one step: nearest-first, first sighting wins.
    missing := new List<string>()
    seenFunctions := TypeDeclEmptyNames()
    seenProperties := TypeDeclEmptyNames()
    AnalyzerTypeDeclarations.RecordAbstractCandidate(TypeDeclMemberInfo("Area", TypeDeclAbstractBits()), seenFunctions, seenProperties, missing)
    assert TypeDeclNames(missing) == "Area"

    // Seen already — an implementation in the derived type, or a nearer concrete override — is silent.
    closed := new List<string>()
    AnalyzerTypeDeclarations.RecordAbstractCandidate(TypeDeclMemberInfo("Area", TypeDeclAbstractBits()), TypeDeclNamesOf("Area"), TypeDeclEmptyNames(), closed)
    assert closed.Count == 0

    // A non-abstract first sighting records the name WITHOUT requiring it: that is how an intermediate
    // class that already overrode the member discharges the obligation for everything below it.
    concrete := new List<string>()
    concreteSeen := TypeDeclEmptyNames()
    AnalyzerTypeDeclarations.RecordAbstractCandidate(TypeDeclMemberInfo("Area", 0), concreteSeen, TypeDeclEmptyNames(), concrete)
    assert concrete.Count == 0
    assert concreteSeen.Contains("Area")

    // A PROPERTY answers the property slot and a FUNCTION answers the function slot — a field named
    // `Area` does not implement `abstract func Area()`, so the two name sets stay disjoint.
    propertyMissing := new List<string>()
    AnalyzerTypeDeclarations.RecordAbstractCandidate(TypeDeclPropertyMemberInfo("Area", TypeDeclAbstractBits()), TypeDeclNamesOf("Area"), TypeDeclEmptyNames(), propertyMissing)
    assert TypeDeclNames(propertyMissing) == "Area"
}

test "METADATA's abstract members come from ONE call, which already walks the CLR chain" {
    // `Stream` is the canonical shape: abstract METHODS and abstract PROPERTIES on the same type. It is
    // reached through `Type.GetType` rather than `typeof` because `typeof` of a non-core-library type
    // does not emit as a static-call argument (the wall the estate hits everywhere).
    streamType := Type.GetType("System.IO.Stream")
    assert streamType != null
    if streamType != null {
        streamMissing := new List<string>()
        AnalyzerTypeDeclarations.CollectReflectedAbstractMembers(streamType, TypeDeclEmptyNames(), TypeDeclEmptyNames(), streamMissing)
        assert streamMissing.Count == 10
        assert streamMissing.Contains("Read")
        assert streamMissing.Contains("Write")
        assert streamMissing.Contains("Seek")
        assert streamMissing.Contains("SetLength")
        assert streamMissing.Contains("Flush")
        assert streamMissing.Contains("CanRead")
        assert streamMissing.Contains("CanWrite")
        assert streamMissing.Contains("CanSeek")
        assert streamMissing.Contains("Length")
        assert streamMissing.Contains("Position")

        // A name the derived type already declares is not required, whatever metadata says — one from
        // the method half and one from the property half, so both subtractions are proven.
        suppliedMissing := new List<string>()
        AnalyzerTypeDeclarations.CollectReflectedAbstractMembers(streamType, TypeDeclNamesOf("Read"), TypeDeclNamesOf("Length"), suppliedMissing)
        assert suppliedMissing.Count == 8
        assert !suppliedMissing.Contains("Read")
        assert !suppliedMissing.Contains("Length")
    }

    // A CONCRETE CLR base requires nothing, and this is the row that keeps the rule off every
    // `class X : Exception` in the estate. `GetMethods` returns the MOST DERIVED implementation of each
    // slot, so `MemoryStream`'s overrides come back non-abstract without any chain walk of our own.
    memoryStreamType := Type.GetType("System.IO.MemoryStream")
    assert memoryStreamType != null
    if memoryStreamType != null {
        concreteMissing := new List<string>()
        AnalyzerTypeDeclarations.CollectReflectedAbstractMembers(memoryStreamType, TypeDeclEmptyNames(), TypeDeclEmptyNames(), concreteMissing)
        assert concreteMissing.Count == 0
    }

    exceptionMissing := new List<string>()
    AnalyzerTypeDeclarations.CollectReflectedAbstractMembers(typeof(Exception), TypeDeclEmptyNames(), TypeDeclEmptyNames(), exceptionMissing)
    assert exceptionMissing.Count == 0

    assert !AnalyzerTypeDeclarations.IsAbstractPropertyAccessor(null)
}

test "the chain walk answers CANNOT TELL rather than reporting from half a chain" {
    harness := TypeDeclDefault()

    // A base that is present and readable: the abstract member is required.
    readable := TypeDeclSourceOwner("Shape", TypeDeclMemberInfos(TypeDeclMemberInfo("Area", TypeDeclAbstractBits())))
    readableMissing := new List<string>()
    assert harness.Declarations.CollectUnimplementedAbstractMembers(readable, TypeDeclEmptyNames(), TypeDeclEmptyNames(), readableMissing, 0)
    assert TypeDeclNames(readableMissing) == "Area"

    // An UNKNOWN link abandons the whole report — false, and the caller reports nothing.
    unknownMissing := new List<string>()
    assert !harness.Declarations.CollectUnimplementedAbstractMembers(BuiltInTypes.Unknown, TypeDeclEmptyNames(), TypeDeclEmptyNames(), unknownMissing, 0)

    // So does a chain deeper than the cycle brake.
    deepMissing := new List<string>()
    assert !harness.Declarations.CollectUnimplementedAbstractMembers(readable, TypeDeclEmptyNames(), TypeDeclEmptyNames(), deepMissing, 25)

    // A null candidate is the END of a chain, not a failure: `object` requires nothing.
    endMissing := new List<string>()
    assert harness.Declarations.CollectUnimplementedAbstractMembers(null, TypeDeclEmptyNames(), TypeDeclEmptyNames(), endMissing, 0)
    assert endMissing.Count == 0
}

test "`NL324` NAMES EVERY MISSING MEMBER IN ONE DIAGNOSTIC, and the singular is not a truncated plural" {
    oneHarness := TypeDeclDefault()
    oneMissing := new List<string>()
    oneMissing.Add("Area")
    oneHarness.Declarations.ReportUnimplementedAbstractMembers(TypeDeclClass("Circle", new List<Declaration>(), null, null, Modifiers.None), oneMissing)
    assert oneHarness.Errors.Count == 1
    assert oneHarness.Errors[0].Code == ErrorCode.AbstractMemberNotImplemented
    assert oneHarness.Errors[0].Message == "'Circle' does not implement inherited abstract member 'Area'"
    assert oneHarness.Errors[0].Suggestion == "Implement it in 'Circle', or declare 'Circle' abstract so a subclass must."
    assert oneHarness.Errors[0].Length == 6

    manyHarness := TypeDeclDefault()
    manyMissing := new List<string>()
    manyMissing.Add("Area")
    manyMissing.Add("Perimeter")
    manyMissing.Add("Name")
    manyHarness.Declarations.ReportUnimplementedAbstractMembers(TypeDeclClass("Circle", new List<Declaration>(), null, null, Modifiers.None), manyMissing)
    assert manyHarness.Errors.Count == 1
    assert manyHarness.Errors[0].Message == "'Circle' does not implement 3 inherited abstract members: 'Area', 'Perimeter', 'Name'"
    assert manyHarness.Errors[0].Suggestion == "Implement all 3 in 'Circle', or declare 'Circle' abstract so a subclass must."
}

test "the four outright exemptions are checked before any chain is walked" {
    // An ABSTRACT derived class may pass the obligation down, so it is never asked.
    abstractHarness := TypeDeclDefault()
    abstractMembers := new List<Declaration>()
    TypeDeclRun(abstractHarness, abstractHarness.Declarations.BeginClass(TypeDeclClass("Partial", abstractMembers, null, null, Modifiers.Abstract), abstractHarness.Assignability), null)
    assert abstractHarness.Errors.Count == 0

    // A class with no written base inherits `object`, which is concrete.
    rootHarness := TypeDeclDefault()
    rootMembers := new List<Declaration>()
    rootMembers.Add(TypeDeclFunction("F", Modifiers.None))
    TypeDeclRun(rootHarness, rootHarness.Declarations.BeginClass(TypeDeclClass("Plain", rootMembers, null, null, Modifiers.None), rootHarness.Assignability), null)
    assert rootHarness.Errors.Count == 0

    // A STRUCT and a RECORD are not class forms and inherit no abstract slot.
    structHarness := TypeDeclDefault()
    structMembers := new List<Declaration>()
    TypeDeclRun(structHarness, structHarness.Declarations.BeginStruct(TypeDeclStruct("Point", structMembers, null, null, Modifiers.None), structHarness.Assignability), null)
    assert structHarness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// THE PROPERTY HALF OF THE SAME RULE, AND THE FIELD THAT CAN NEVER TAKE PART IN INHERITANCE
//
// `ValidateOverrideTargets` walked `FunctionDeclaration` and `continue`d past everything else, so an
// `override` PROPERTY was accepted with no check at all — and unlike the method hole, two of its
// shapes COMPILED AND RAN: `class MyError : Exception { override NotThere: int => 5 }` emitted and
// printed 5, overriding nothing. The property walk could not borrow either half of the method walk:
// the source classifier matches `DeclaredMemberKind.Function` on purpose, and the reflection
// classifier walks `GetMethods` while SKIPPING every `IsSpecialName`, which is exactly what a property
// accessor is — so borrowing it would have answered "no base member" for every correct program.
//
// MEASURED, and it decided the third rule below: the parser chooses field or property from what
// FOLLOWS the type, never from the modifiers. `virtual Label: string`, `abstract Label: string` and
// `override Label: string` all build a `FieldDeclaration`; only `=> expr` and `{ get/set }` build a
// `PropertyDeclaration`. The emitted metadata agrees — a bare `Auto: string` comes out a CLR FIELD and
// only the accessor forms come out properties — and a CLR field can never be virtual, abstract or
// overridden. So those three words on a bare member are meaningless and are now reported.
// ---------------------------------------------------------------------------------------------

test "a source shape's PROPERTY members answer the property question, and its functions do not" {
    virtualProperty := TypeDeclMemberInfos(TypeDeclPropertyMemberInfo("Label", TypeDeclVirtualBits()))
    assert AnalyzerTypeDeclarations.ClassifyDeclaredOverridePropertyTarget(virtualProperty, "Label") == 1

    plainProperty := TypeDeclMemberInfos(TypeDeclPropertyMemberInfo("Label", 0))
    assert AnalyzerTypeDeclarations.ClassifyDeclaredOverridePropertyTarget(plainProperty, "Label") == 2

    sealedProperty := TypeDeclMemberInfos(TypeDeclPropertyMemberInfo("Label", TypeDeclSealedOverrideBits()))
    assert AnalyzerTypeDeclarations.ClassifyDeclaredOverridePropertyTarget(sealedProperty, "Label") == 2

    assert AnalyzerTypeDeclarations.ClassifyDeclaredOverridePropertyTarget(virtualProperty, "Other") == 0

    // A base FUNCTION of the same name is not a property slot, and the two classifiers stay disjoint
    // in both directions — this is the assertion that would fail if either borrowed the other.
    virtualFunction := TypeDeclMemberInfos(TypeDeclMemberInfo("Label", TypeDeclVirtualBits()))
    assert AnalyzerTypeDeclarations.ClassifyDeclaredOverridePropertyTarget(virtualFunction, "Label") == 0
    assert AnalyzerTypeDeclarations.ClassifyDeclaredOverrideTarget(virtualProperty, "Label") == 0
}

test "METADATA answers through GetProperties and the ACCESSORS, which GetMethods structurally cannot" {
    // `Exception.Message` is `public override string Message { get; }` — virtual and not final.
    assert AnalyzerTypeDeclarations.ClassifyReflectionOverridePropertyTarget(typeof(Exception), "Message") == 1
    // `Exception.HResult` is a plain non-virtual property: present, but sealed shut.
    assert AnalyzerTypeDeclarations.ClassifyReflectionOverridePropertyTarget(typeof(Exception), "HResult") == 2
    assert AnalyzerTypeDeclarations.ClassifyReflectionOverridePropertyTarget(typeof(Exception), "NotThere") == 3

    // NON-VACUITY, and the whole reason this function exists: the METHOD walk cannot see `Message` at
    // all, because a property accessor is `IsSpecialName` and it skips those.
    assert AnalyzerTypeDeclarations.ClassifyReflectionOverrideTarget(typeof(Exception), "Message") == 3

    // `object` declares no properties, so the implicit root can never supply a property slot.
    assert AnalyzerTypeDeclarations.ClassifyObjectOverridePropertyTarget("Message") == 3
    assert AnalyzerTypeDeclarations.ClassifyObjectOverridePropertyTarget("ToString") == 3

    assert !AnalyzerTypeDeclarations.IsOverridablePropertyAccessor(null)
}

test "the property walk climbs the base chain and refuses to guess on the same three shapes" {
    harness := TypeDeclDefault()
    virtualBase := TypeDeclSourceOwner("Base", TypeDeclMemberInfos(TypeDeclPropertyMemberInfo("Label", TypeDeclVirtualBits())))
    assert harness.Declarations.ClassifyOverridePropertyTarget(virtualBase, "Label", 0) == 1

    plainBase := TypeDeclSourceOwner("Base", TypeDeclMemberInfos(TypeDeclPropertyMemberInfo("Label", 0)))
    assert harness.Declarations.ClassifyOverridePropertyTarget(plainBase, "Label", 0) == 2
    assert harness.Declarations.ClassifyOverridePropertyTarget(plainBase, "Other", 0) == 3

    // SILENCE IS THE DEFAULT here too: an unresolvable base and a depth past the cycle brake both
    // answer "cannot tell", and a null candidate walks to the implicit root rather than giving up.
    assert harness.Declarations.ClassifyOverridePropertyTarget(BuiltInTypes.Unknown, "Label", 0) == 0
    assert harness.Declarations.ClassifyOverridePropertyTarget(plainBase, "Label", 25) == 0
    assert harness.Declarations.ClassifyOverridePropertyTarget(null, "Label", 0) == 3
}

test "AN `override` PROPERTY WITH NO SLOT TO TAKE IS `NL311`, WITH THE METHOD RULE'S TWO SENTENCES" {
    missingHarness := TypeDeclDefault()
    missingMembers := new List<Declaration>()
    missingMembers.Add(TypeDeclProperty("Label", Modifiers.Override))
    TypeDeclRun(missingHarness, missingHarness.Declarations.BeginClass(TypeDeclClass("Dog", missingMembers, null, null, Modifiers.None), missingHarness.Assignability), null)

    assert missingHarness.Errors.Count == 1
    assert missingHarness.Errors[0].Code == ErrorCode.InvalidModifier
    assert missingHarness.Errors[0].Message == "'Label' is declared 'override', but it has no base member of that name"
    assert missingHarness.Errors[0].Length == 5

    // A property WITHOUT the modifier is never asked, and neither is a plain field beside it.
    silentHarness := TypeDeclDefault()
    silentMembers := new List<Declaration>()
    silentMembers.Add(TypeDeclProperty("Label", Modifiers.None))
    silentMembers.Add(TypeDeclField("Count", TypeDeclInt(), null, Modifiers.None))
    TypeDeclRun(silentHarness, silentHarness.Declarations.BeginClass(TypeDeclClass("Dog", silentMembers, null, null, Modifiers.None), silentHarness.Assignability), null)
    assert silentHarness.Errors.Count == 0
}

test "A FIELD DECLARED `override`, `virtual` OR `abstract` IS `NL311` — it can be none of them" {
    overrideHarness := TypeDeclDefault()
    overrideMembers := new List<Declaration>()
    overrideMembers.Add(TypeDeclField("Label", TypeDeclInt(), null, Modifiers.Override))
    TypeDeclRun(overrideHarness, overrideHarness.Declarations.BeginClass(TypeDeclClass("Dog", overrideMembers, null, null, Modifiers.None), overrideHarness.Assignability), null)
    assert overrideHarness.Errors.Count == 1
    assert overrideHarness.Errors[0].Code == ErrorCode.InvalidModifier
    assert overrideHarness.Errors[0].Message == "'Label' is declared 'override', but a field cannot be virtual, abstract or overridden"

    virtualHarness := TypeDeclDefault()
    virtualMembers := new List<Declaration>()
    virtualMembers.Add(TypeDeclField("Label", TypeDeclInt(), null, Modifiers.Virtual))
    TypeDeclRun(virtualHarness, virtualHarness.Declarations.BeginClass(TypeDeclClass("Dog", virtualMembers, null, null, Modifiers.None), virtualHarness.Assignability), null)
    assert virtualHarness.Errors.Count == 1
    assert virtualHarness.Errors[0].Message == "'Label' is declared 'virtual', but a field cannot be virtual, abstract or overridden"

    abstractHarness := TypeDeclDefault()
    abstractMembers := new List<Declaration>()
    abstractMembers.Add(TypeDeclField("Label", TypeDeclInt(), null, Modifiers.Abstract))
    TypeDeclRun(abstractHarness, abstractHarness.Declarations.BeginClass(TypeDeclClass("Dog", abstractMembers, null, null, Modifiers.None), abstractHarness.Assignability), null)
    assert abstractHarness.Errors.Count == 1
    assert abstractHarness.Errors[0].Message == "'Label' is declared 'abstract', but a field cannot be virtual, abstract or overridden"

    // THE MODIFIERS A FIELD LEGITIMATELY CARRIES ARE UNTOUCHED. This is the row that keeps the rule
    // from failing live files: `static`, `readonly` and `required` fields are the estate's own shapes.
    plainHarness := TypeDeclDefault()
    plainMembers := new List<Declaration>()
    plainMembers.Add(TypeDeclField("Shared", TypeDeclInt(), TypeDeclIntLiteral(), Modifiers.Static))
    plainMembers.Add(TypeDeclField("Fixed", TypeDeclInt(), TypeDeclIntLiteral(), Modifiers.Readonly))
    plainMembers.Add(TypeDeclField("Needed", TypeDeclInt(), null, Modifiers.Required))
    plainMembers.Add(TypeDeclField("Plain", TypeDeclInt(), null, Modifiers.None))
    TypeDeclRun(plainHarness, plainHarness.Declarations.BeginClass(TypeDeclClass("Dog", plainMembers, null, null, Modifiers.None), plainHarness.Assignability), null)
    assert plainHarness.Errors.Count == 0
}

test "THE RULE STAYS SILENT FOR EVERY CORRECT SPELLING IT CAN SEE" {
    // `override func ToString()` on a class with no `:` clause is the estate's own commonest shape —
    // it overrides `object.ToString`, and a rule that reported it would fail hundreds of live files.
    objectHarness := TypeDeclDefault()
    objectMembers := new List<Declaration>()
    objectMembers.Add(TypeDeclFunction("ToString", Modifiers.Override))
    TypeDeclRun(objectHarness, objectHarness.Declarations.BeginClass(TypeDeclClass("Shape", objectMembers, null, null, Modifiers.None), objectHarness.Assignability), null)
    assert objectHarness.Errors.Count == 0

    // A member WITHOUT the modifier is never asked the question, whatever its name.
    plainHarness := TypeDeclDefault()
    plainMembers := new List<Declaration>()
    plainMembers.Add(TypeDeclFunction("Speak", Modifiers.None))
    TypeDeclRun(plainHarness, plainHarness.Declarations.BeginClass(TypeDeclClass("Dog", plainMembers, null, null, Modifiers.None), plainHarness.Assignability), null)
    assert plainHarness.Errors.Count == 0

    // A STRUCT and a RECORD override `object`'s members through `ValueType` and are equally silent.
    structHarness := TypeDeclDefault()
    structMembers := new List<Declaration>()
    structMembers.Add(TypeDeclFunction("GetHashCode", Modifiers.Override))
    TypeDeclRun(structHarness, structHarness.Declarations.BeginStruct(TypeDeclStruct("Point", structMembers, null, null, Modifiers.None), structHarness.Assignability), null)
    assert structHarness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// A BASE CLASS THAT CANNOT BE EXTENDED (`NL802`)
//
// `sealed class Base { }` with `class Derived : Base { }` beneath it CHECKED CLEAN — `ok: true`,
// zero rows — and had done since the codes were written. `sealed` is a promise the declaration makes
// to every reader, "nothing extends this", and the compiler was not keeping it; the CLR refuses the
// derivation outright, so what shipped was a program that could not load.
//
// TWO THINGS THIS RULE HAD TO GET RIGHT.
//   (1) THE BASE-CLASS SLOT MAY HOLD AN INTERFACE. The parser splits `: A, B, C` by POSITION, so
//       `class Resource : IDisposable` arrives with an interface in the base-CLASS slot — and an
//       interface is exactly what a class is allowed to write there. Reporting it would accuse
//       correct N#.
//   (2) EVERY VALUE TYPE IS SEALED IN METADATA. A struct, an enum or a delegate in the base slot is a
//       different fault with a different sentence, and calling one "a sealed class" would name the
//       wrong thing — so only reference types answer.
// ---------------------------------------------------------------------------------------------

func TypeDeclCodes(errors: List<CompilerError>): string {
    joined := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            joined = joined + ","
        }

        codeValue: int = (int)errors[index].Code
        joined = joined + codeValue.ToString()
        index = index + 1
    }

    return joined
}

func TypeDeclSealedOwner(name: string): TypeInfo {
    owner: TypeInfo = new ClassTypeInfo(name, 1, 1, true, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
    return owner
}

func TypeDeclClrOwner(metadataName: string): TypeInfo {
    resolved := Type.GetType(metadataName)
    if resolved == null {
        throw new InvalidOperationException("Could not resolve '" + metadataName + "'.")
    }

    owner: TypeInfo = new ReflectionTypeInfo(resolved)
    return owner
}

func TypeDeclClassWithBase(name: string, baseName: string, baseLine: int, baseColumn: int): ClassDeclaration {
    baseReference: TypeReference = new SimpleTypeReference(baseName, baseLine, baseColumn)
    return new ClassDeclaration(name, null, baseReference, TypeDeclNoInterfaces(), new List<Declaration>(), null, Modifiers.None, TypeDeclNoAttributes(), 7, 10)
}

test "the shut shapes are named as what the READER would call them, not as what metadata says" {
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclSealedOwner("Leaf")) == "sealed class"
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclSourceOwner("Base", new DeclaredMemberInfo[](0))) == ""

    // An external sealed class, and a STATIC one — `abstract sealed` in metadata, a word pair the
    // reader never wrote.
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclClrOwner("System.String")) == "sealed class"
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclClrOwner("System.Math")) == "static class"

    // Open shapes answer "" and are not this rule's business.
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclClrOwner("System.Exception")) == ""
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclClrOwner("System.IO.Stream")) == ""

    // EVERY VALUE TYPE IS SEALED IN METADATA and none of them answers here.
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclClrOwner("System.Int32")) == ""
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclClrOwner("System.DayOfWeek")) == ""

    // An interface is not refused BY THIS ARM — the base-slot guard drops it before the question is
    // asked, because a class writing one interface is correct N#.
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclClrOwner("System.IDisposable")) == ""

    // A CLOSED GENERIC is opened first: `Box<int>` is extendable exactly when `Box<T>` is. A wrapper
    // with no definition answers "cannot tell" and is left alone.
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclClosedGeneric("Box", TypeDeclSealedOwner("Box"))) == "sealed class"
    assert AnalyzerTypeDeclarations.UnextendableBaseKind(TypeDeclClosedGeneric("Box", null)) == ""
}

test "the way out COMPILES, and a static base gets a different one" {
    assert AnalyzerTypeDeclarations.UnextendableBaseSuggestion("sealed class", "Base", "Derived") == "Remove `sealed` from `Base` if it is meant to be extended, or hold one instead of inheriting one — give `Derived` a field `inner: Base`."
    assert AnalyzerTypeDeclarations.UnextendableBaseSuggestion("static class", "Math", "Helpers") == "A static class has no instances and cannot be a base. Call its members directly, as `Math.Member(...)`."
}

test "`NL802` is reported at the BASE NAME, not at the deriving class's header" {
    harness := TypeDeclDefault()
    harness.Scopes.DeclareNestedTypeIfAbsent("Base", TypeDeclSealedOwner("Base"))
    TypeDeclRun(harness, harness.Declarations.BeginClass(TypeDeclClassWithBase("Derived", "Base", 12, 17), harness.Assignability), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.SealedInheritance
    assert harness.Errors[0].Message == "Cannot inherit from 'Base' because it is a sealed class"
    // The class header is at (7,10) and the base reference at (12,17). The squiggle goes on the base.
    assert harness.Errors[0].Line == 12
    assert harness.Errors[0].Column == 17
    assert harness.Errors[0].Length == 4
}

test "an EXTERNAL sealed base is refused through the same walk" {
    harness := TypeDeclDefault()
    harness.Scopes.DeclareNestedTypeIfAbsent("String", TypeDeclClrOwner("System.String"))
    TypeDeclRun(harness, harness.Declarations.BeginClass(TypeDeclClassWithBase("MyString", "String", 3, 18), harness.Assignability), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.SealedInheritance
    assert harness.Errors[0].Message == "Cannot inherit from 'String' because it is a sealed class"
}

test "a base reference the parser gave NO position falls back to the class header, never to line 0" {
    positionedReference: TypeReference = new SimpleTypeReference("Base", 12, 17)
    positioned := AnalyzerTypeDeclarations.BaseReferenceSpan(positionedReference, "Base", TypeDeclClass("Derived", new List<Declaration>(), null, null, Modifiers.None))
    assert positioned.Line == 12
    assert positioned.Column == 17
    assert positioned.Length == 4

    unpositionedReference: TypeReference = new SimpleTypeReference("Base")
    unpositioned := AnalyzerTypeDeclarations.BaseReferenceSpan(unpositionedReference, "Base", TypeDeclClass("Derived", new List<Declaration>(), null, null, Modifiers.None))
    assert unpositioned.Line == 7
    assert unpositioned.Column == 10
    assert unpositioned.Length == 7

    // Both spellings a base clause can take answer their own written name.
    simpleReference: TypeReference = new SimpleTypeReference("Base", 1, 1)
    genericReference: TypeReference = new GenericTypeReference("Box", new List<TypeReference>(), 1, 1)
    assert AnalyzerTypeDeclarations.BaseReferenceName(simpleReference) == "Base"
    assert AnalyzerTypeDeclarations.BaseReferenceName(genericReference) == "Box"
}

test "the legal spellings stay SILENT" {
    // An OPEN base class is the ordinary case and says nothing.
    openHarness := TypeDeclDefault()
    openHarness.Scopes.DeclareNestedTypeIfAbsent("Base", TypeDeclSourceOwner("Base", new DeclaredMemberInfo[](0)))
    TypeDeclRun(openHarness, openHarness.Declarations.BeginClass(TypeDeclClassWithBase("Derived", "Base", 12, 17), openHarness.Assignability), null)
    assert openHarness.Errors.Count == 0

    // AN INTERFACE IN THE BASE-CLASS SLOT IS CORRECT N#. `class Resource : IDisposable` puts the
    // interface at `[0]` by position, and accusing it would report a correct program.
    interfaceHarness := TypeDeclDefault()
    interfaceHarness.Scopes.DeclareNestedTypeIfAbsent("Greeter", TypeDeclSourceInterface("Greeter", new DeclaredMemberInfo[](0)))
    TypeDeclRun(interfaceHarness, interfaceHarness.Declarations.BeginClass(TypeDeclClassWithBase("English", "Greeter", 12, 17), interfaceHarness.Assignability), null)
    assert interfaceHarness.Errors.Count == 0

    // A class with NO written base inherits `object` and is never asked.
    rootHarness := TypeDeclDefault()
    TypeDeclRun(rootHarness, rootHarness.Declarations.BeginClass(TypeDeclClass("Plain", new List<Declaration>(), null, null, Modifiers.None), rootHarness.Assignability), null)
    assert rootHarness.Errors.Count == 0

    // A base that DID NOT RESOLVE is `NL201`'s report, not this one — and the walk must not invent a
    // second diagnostic about a name nobody could find.
    unresolvedHarness := TypeDeclDefault()
    TypeDeclRun(unresolvedHarness, unresolvedHarness.Declarations.BeginClass(TypeDeclClassWithBase("Derived", "NoSuchBase", 12, 17), unresolvedHarness.Assignability), null)
    assert TypeDeclCodes(unresolvedHarness.Errors) == "201"

    // A SEALED CLASS USED AS A VALUE — not as a base — is untouched: the rule is about the `:` clause.
    valueHarness := TypeDeclDefault()
    valueHarness.Scopes.DeclareNestedTypeIfAbsent("Leaf", TypeDeclSealedOwner("Leaf"))
    fieldType: TypeReference = new SimpleTypeReference("Leaf", 8, 12)
    TypeDeclRun(valueHarness, valueHarness.Declarations.BeginClass(TypeDeclClass("Holder", TypeDeclMembers(TypeDeclField("value", fieldType, null, Modifiers.None)), null, null, Modifiers.None), valueHarness.Assignability), null)
    assert valueHarness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// MORE THAN ONE BASE CLASS (`NL801`)
//
// `class Both : Left, Right` over two classes REACHED THE EMITTER and died there as an `NL103`
// columnar decline, which names the backend and not the mistake. N# is a CLR language: a class has
// exactly one base and any number of interfaces, and that is a rule of the runtime.
//
// THE PARSER CANNOT ANSWER THIS. `: A, B, C` is split by POSITION — `[0]` to `BaseClass`, the rest to
// `Interfaces` — so "how many of these are classes" is a question only resolution can answer, and it
// is asked over BOTH slots as ONE written list. Which is also why the COUNT decides and not the slot:
// `class X : IFoo, Base` names one base class in an unusual position and is not this rule's business.
// ---------------------------------------------------------------------------------------------

func TypeDeclClassWithBases(name: string, first: string, firstColumn: int, second: string, secondColumn: int): ClassDeclaration {
    baseReference: TypeReference = new SimpleTypeReference(first, 12, firstColumn)
    interfaces := new List<TypeReference>()
    secondReference: TypeReference = new SimpleTypeReference(second, 12, secondColumn)
    interfaces.Add(secondReference)
    return new ClassDeclaration(name, null, baseReference, interfaces, new List<Declaration>(), null, Modifiers.None, TypeDeclNoAttributes(), 7, 10)
}

test "only a CLASS occupies the one base-class slot" {
    assert AnalyzerTypeDeclarations.IsBaseClassShape(TypeDeclSourceOwner("Base", new DeclaredMemberInfo[](0)))
    assert AnalyzerTypeDeclarations.IsBaseClassShape(TypeDeclSealedOwner("Leaf"))
    assert AnalyzerTypeDeclarations.IsBaseClassShape(TypeDeclClrOwner("System.Exception"))
    assert AnalyzerTypeDeclarations.IsBaseClassShape(TypeDeclClosedGeneric("Box", TypeDeclSourceOwner("Box", new DeclaredMemberInfo[](0))))

    // An interface is free — a class may write as many as it likes.
    assert !AnalyzerTypeDeclarations.IsBaseClassShape(TypeDeclSourceInterface("Greeter", new DeclaredMemberInfo[](0)))
    assert !AnalyzerTypeDeclarations.IsBaseClassShape(TypeDeclClrOwner("System.IDisposable"))

    // A struct or an enum in a base list is a different fault with a different sentence.
    assert !AnalyzerTypeDeclarations.IsBaseClassShape(TypeDeclClrOwner("System.Int32"))
    assert !AnalyzerTypeDeclarations.IsBaseClassShape(TypeDeclClrOwner("System.DayOfWeek"))

    // AN ENTRY THAT DID NOT RESOLVE ANSWERS NO. A count computed from a name nobody could find would
    // report a program whose real problem is `NL201`.
    assert !AnalyzerTypeDeclarations.IsBaseClassShape(null)
    assert !AnalyzerTypeDeclarations.IsBaseClassShape(BuiltInTypes.Unknown)
    assert !AnalyzerTypeDeclarations.IsBaseClassShape(TypeDeclClosedGeneric("Box", null))
}

test "`NL801` is reported ONCE, on the SECOND base class" {
    harness := TypeDeclDefault()
    harness.Scopes.DeclareNestedTypeIfAbsent("Left", TypeDeclSourceOwner("Left", new DeclaredMemberInfo[](0)))
    harness.Scopes.DeclareNestedTypeIfAbsent("Right", TypeDeclSourceOwner("Right", new DeclaredMemberInfo[](0)))
    TypeDeclRun(harness, harness.Declarations.BeginClass(TypeDeclClassWithBases("Both", "Left", 15, "Right", 21), harness.Assignability), null)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.MultipleInheritance
    assert harness.Errors[0].Message == "'Both' declares more than one base class: 'Left' and 'Right'"
    assert harness.Errors[0].Suggestion == "A class has exactly one base class, followed by any number of interfaces. Keep 'Left' as the base and make 'Right' an `interface` that 'Both' implements, or hold one — give 'Both' a field `inner: Right`."
    assert harness.Errors[0].Line == 12
    assert harness.Errors[0].Column == 21
    assert harness.Errors[0].Length == 5
}

test "one base plus any number of INTERFACES is silent, in either slot order" {
    baseFirst := TypeDeclDefault()
    baseFirst.Scopes.DeclareNestedTypeIfAbsent("Base", TypeDeclSourceOwner("Base", new DeclaredMemberInfo[](0)))
    baseFirst.Scopes.DeclareNestedTypeIfAbsent("Greeter", TypeDeclSourceInterface("Greeter", new DeclaredMemberInfo[](0)))
    TypeDeclRun(baseFirst, baseFirst.Declarations.BeginClass(TypeDeclClassWithBases("English", "Base", 15, "Greeter", 21), baseFirst.Assignability), null)
    assert TypeDeclCodes(baseFirst.Errors) == ""

    // `class X : IFoo, Base` names ONE base class, in an unusual position. The count decides, not the
    // slot, so it is silent about inheritance.
    interfaceFirst := TypeDeclDefault()
    interfaceFirst.Scopes.DeclareNestedTypeIfAbsent("Base", TypeDeclSourceOwner("Base", new DeclaredMemberInfo[](0)))
    interfaceFirst.Scopes.DeclareNestedTypeIfAbsent("Greeter", TypeDeclSourceInterface("Greeter", new DeclaredMemberInfo[](0)))
    TypeDeclRun(interfaceFirst, interfaceFirst.Declarations.BeginClass(TypeDeclClassWithBases("English", "Greeter", 15, "Base", 21), interfaceFirst.Assignability), null)
    assert TypeDeclCodes(interfaceFirst.Errors) == ""

    // TWO interfaces and no base at all: the ordinary shape, and never this rule's business.
    twoInterfaces := TypeDeclDefault()
    twoInterfaces.Scopes.DeclareNestedTypeIfAbsent("Greeter", TypeDeclSourceInterface("Greeter", new DeclaredMemberInfo[](0)))
    twoInterfaces.Scopes.DeclareNestedTypeIfAbsent("Namer", TypeDeclSourceInterface("Namer", new DeclaredMemberInfo[](0)))
    TypeDeclRun(twoInterfaces, twoInterfaces.Declarations.BeginClass(TypeDeclClassWithBases("English", "Greeter", 15, "Namer", 21), twoInterfaces.Assignability), null)
    assert twoInterfaces.Errors.Count == 0

    // And a class with ONE written base is not asked at all — the list is shorter than two.
    single := TypeDeclDefault()
    single.Scopes.DeclareNestedTypeIfAbsent("Base", TypeDeclSourceOwner("Base", new DeclaredMemberInfo[](0)))
    TypeDeclRun(single, single.Declarations.BeginClass(TypeDeclClassWithBase("Derived", "Base", 12, 17), single.Assignability), null)
    assert single.Errors.Count == 0
}

// A DECLARATION WITH TWO BASES HAS A SHAPE PROBLEM, and being told the second one is also sealed
// would be a second sentence about the same broken line.
test "`NL801` runs BEFORE the sealed rule, so a doubly-broken base list gets ONE sentence" {
    harness := TypeDeclDefault()
    harness.Scopes.DeclareNestedTypeIfAbsent("Left", TypeDeclSourceOwner("Left", new DeclaredMemberInfo[](0)))
    harness.Scopes.DeclareNestedTypeIfAbsent("Leaf", TypeDeclSealedOwner("Leaf"))
    TypeDeclRun(harness, harness.Declarations.BeginClass(TypeDeclClassWithBases("Both", "Left", 15, "Leaf", 21), harness.Assignability), null)

    assert TypeDeclCodes(harness.Errors) == "801"
}

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

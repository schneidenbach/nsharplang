namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for what an object pattern's property list resolves to and binds.
//
// THE CORPUS DECIDES ONE ARM OF THIS MEMBER AND NO MORE. Instrumenting the baseline over all 72
// corpus targets counted 33 entries and 48 property patterns — every one of them a nested pattern
// over a source-declared `ClassTypeInfo`, NEVER an implicit binding, NEVER a missing property,
// NEVER the generic arm and NEVER the reflected arm. So what is pinned here is the decision itself:
// which owner the properties are looked up on, what the substitution does to a property's type,
// which of the two sources answers, which of the three outcomes each property takes, and the exact
// text and span of the diagnostic.
//
// THE STEP TRANSCRIPT IS THE CONTRACT, not just the answers. `NextStep` is pulled the way the
// driver pulls it, and what is asserted is the ORDERED sequence of requests with a report landing
// between two of them — because the whole reason this walk yields instead of handing back a
// schedule is that `_errors` is one list and the walk's own report must not overtake a diagnostic
// that a preceding property's nested pattern already produced.
class PropertyPatternHarness {
    Binding: AnalyzerPropertyPatternBinding
    Errors: List<CompilerError>
    Context: AnalyzerDeclarationContext
    Scopes: AnalyzerScopeStack

    constructor(
        binding: AnalyzerPropertyPatternBinding,
        errors: List<CompilerError>,
        context: AnalyzerDeclarationContext,
        scopes: AnalyzerScopeStack
    ) {
        Binding = binding
        Errors = errors
        Context = context
        Scopes = scopes
    }
}

func PropertyPatternPath(): string {
    return "/tmp/property-pattern-binding.nl"
}

func PropertyPatternDefault(): PropertyPatternHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    context.AddCompilationUnit(PropertyPatternPath(), new AnalyzerContextTestUnit(new List<object>()))
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

    return new PropertyPatternHarness(
        new AnalyzerPropertyPatternBinding(diagnostics, spans, context, substitution),
        errors,
        context,
        scopes
    )
}

// A declared VALUE member — the only kind `TryResolveDeclaredValueMember` answers for.
func PropertyPatternMember(
    kind: DeclaredMemberKind,
    name: string,
    memberType: TypeReference?
): DeclaredMemberInfo {
    return new DeclaredMemberInfo(
        name,
        "Owner",
        kind,
        "member",
        memberType,
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
}

func PropertyPatternProperty(name: string, typeName: string): DeclaredMemberInfo {
    return PropertyPatternMember(
        DeclaredMemberKind.Property,
        name,
        new SimpleTypeReference(typeName, 0, 0)
    )
}

func PropertyPatternMembers(members: DeclaredMemberInfo[]): DeclaredMemberInfo[] {
    return members
}

func PropertyPatternOneMember(member: DeclaredMemberInfo): DeclaredMemberInfo[] {
    result := new DeclaredMemberInfo[](1)
    result[0] = member
    return result
}

func PropertyPatternTwoMembers(
    first: DeclaredMemberInfo,
    second: DeclaredMemberInfo
): DeclaredMemberInfo[] {
    result := new DeclaredMemberInfo[](2)
    result[0] = first
    result[1] = second
    return result
}

func PropertyPatternOneTypeParameter(name: string): TypeParameter[] {
    result := new TypeParameter[](1)
    result[0] = new TypeParameter(name)
    return result
}

// A source type the harness's context OWNS. Registration is what makes a declared member's TYPE
// resolvable: `TryResolveTypeForOwner` looks the owner's declaring FILE up first, and an owner it
// cannot find answers `unknown` — the member is still found, it just has no type. So every builder
// here registers, and the unowned case is pinned separately.
func PropertyPatternUnownedClass(
    name: string,
    typeParameters: TypeParameter[],
    members: DeclaredMemberInfo[]
): TypeInfo {
    owner: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        typeParameters,
        new ParameterDeclarationInfo[](0),
        members,
        new NestedTypeInfo[](0),
        true
    )
    return owner
}

func PropertyPatternOwn(
    harness: PropertyPatternHarness,
    name: string,
    owner: TypeInfo
): TypeInfo {
    harness.Context.RegisterCanonicalType(PropertyPatternPath(), name, owner)
    return owner
}

func PropertyPatternClass(
    harness: PropertyPatternHarness,
    name: string,
    typeParameters: TypeParameter[],
    members: DeclaredMemberInfo[]
): TypeInfo {
    return PropertyPatternOwn(
        harness,
        name,
        PropertyPatternUnownedClass(name, typeParameters, members)
    )
}

func PropertyPatternPlainClass(
    harness: PropertyPatternHarness,
    name: string,
    members: DeclaredMemberInfo[]
): TypeInfo {
    return PropertyPatternClass(harness, name, new TypeParameter[](0), members)
}

func PropertyPatternStruct(
    harness: PropertyPatternHarness,
    name: string,
    members: DeclaredMemberInfo[]
): TypeInfo {
    owner: TypeInfo = new StructTypeInfo(
        name,
        1,
        1,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        members,
        new NestedTypeInfo[](0)
    )
    return PropertyPatternOwn(harness, name, owner)
}

// A record whose primary constructor carries `Count` and whose declared members carry only what is
// passed — the shape that proves a primary parameter is not a value member here.
func PropertyPatternRecord(
    harness: PropertyPatternHarness,
    name: string,
    primary: ParameterDeclarationInfo[],
    members: DeclaredMemberInfo[]
): TypeInfo {
    owner: TypeInfo = new RecordTypeInfo(
        name,
        1,
        1,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        primary,
        members,
        new NestedTypeInfo[](0)
    )
    return PropertyPatternOwn(harness, name, owner)
}

func PropertyPatternOneParameter(name: string, typeName: string): ParameterDeclarationInfo[] {
    result := new ParameterDeclarationInfo[](1)
    result[0] = new ParameterDeclarationInfo(
        name,
        new SimpleTypeReference(typeName, 0, 0),
        1,
        1
    )
    return result
}

func PropertyPatternGeneric(
    name: string,
    definition: TypeInfo?,
    arguments: List<TypeInfo>
): TypeInfo {
    generic: TypeInfo = new GenericTypeInfo(name, arguments, definition)
    return generic
}

func PropertyPatternOneArgument(argument: TypeInfo): List<TypeInfo> {
    result := new List<TypeInfo>()
    result.Add(argument)
    return result
}

func PropertyPatternProperties(properties: List<PropertyPattern>): List<PropertyPattern> {
    return properties
}

func PropertyPatternList(): List<PropertyPattern> {
    return new List<PropertyPattern>()
}

func PropertyPatternNested(name: string, nested: Pattern): PropertyPattern {
    return new PropertyPattern(name, nested, null, 7, 11)
}

func PropertyPatternImplicit(name: string): PropertyPattern {
    return new PropertyPattern(name, null, null, 7, 11)
}

func PropertyPatternAt(name: string, line: int, column: int): PropertyPattern {
    return new PropertyPattern(name, null, null, line, column)
}

func PropertyPatternSomePattern(): Pattern {
    nested: Pattern = new IdentifierPattern("bound", 7, 20)
    return nested
}

func PropertyPatternTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<none>"
    }

    asObject := candidate as object
    return asObject.ToString()
}

// Pulls the walk the way the driver pulls it and renders the request sequence as one string, so a
// contract can assert the whole transcript rather than one field of one step.
func PropertyPatternTranscript(
    harness: PropertyPatternHarness,
    properties: List<PropertyPattern>,
    valueType: TypeInfo,
    line: int,
    column: int
): string {
    state := harness.Binding.Begin(properties, valueType, line, column)
    rendered := ""
    step := harness.Binding.NextStep(state)
    while step != null {
        if rendered.Length > 0 {
            rendered = rendered + "|"
        }
        if step.Kind == 1 {
            rendered = rendered + "analyze:" + PropertyPatternTypeName(step.CarriedType)
        } else {
            rendered = rendered + "declare:" + step.Name + ":" + PropertyPatternTypeName(step.CarriedType) + ":" + step.Line.ToString() + ":" + step.Column.ToString()
        }
        step = harness.Binding.NextStep(state)
    }

    if rendered.Length == 0 {
        return "<none>"
    }

    return rendered
}

// ---------------------------------------------------------------------------------------------
// THE OWNER AND THE SUBSTITUTION, DERIVED ONCE FROM THE SCRUTINEE
// ---------------------------------------------------------------------------------------------

test "a plain source scrutinee is its own owner under no substitution" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )

    state := harness.Binding.Begin(PropertyPatternList(), dog, 7, 5)

    assert state.DeclarationOwner == dog
    assert state.Substitution == null
    assert state.ValueType == dog
    assert state.Line == 7
    assert state.Column == 5
    assert state.Index == 0
}

test "a closed generic scrutinee answers the DEFINITION and the substitution its arguments induce" {
    harness := PropertyPatternDefault()
    definition: TypeInfo = PropertyPatternClass(
        harness,
        "Box",
        PropertyPatternOneTypeParameter("T"),
        PropertyPatternOneMember(PropertyPatternProperty("Value", "T"))
    )
    closed := PropertyPatternGeneric(
        "Box",
        definition,
        PropertyPatternOneArgument(BuiltInTypes.Int)
    )

    state := harness.Binding.Begin(PropertyPatternList(), closed, 7, 5)
    substitution := state.Substitution

    assert state.DeclarationOwner == definition
    assert substitution != null
    assert substitution.Count == 1
    assert BuiltInTypes.Is(substitution["T"], BuiltInTypes.Int)
    // The SCRUTINEE is still the instantiation — it is what the diagnostic renders and what the
    // reflected fall-back is asked about.
    assert state.ValueType == closed
}

test "a generic whose definition carries no type parameters answers a NULL substitution and still owns" {
    harness := PropertyPatternDefault()
    definition: TypeInfo = new ReflectionTypeInfo(typeof(List<int>))
    closed := PropertyPatternGeneric(
        "List",
        definition,
        PropertyPatternOneArgument(BuiltInTypes.Int)
    )

    state := harness.Binding.Begin(PropertyPatternList(), closed, 7, 5)

    assert state.DeclarationOwner == definition
    assert state.Substitution == null
}

test "a generic with no resolvable definition keeps the instantiation as its own owner" {
    harness := PropertyPatternDefault()
    closed := PropertyPatternGeneric(
        "Nowhere",
        null,
        PropertyPatternOneArgument(BuiltInTypes.Int)
    )

    state := harness.Binding.Begin(PropertyPatternList(), closed, 7, 5)

    assert state.DeclarationOwner == closed
    assert state.Substitution == null
}

test "the generic arm is asked of GENERIC scrutinees only" {
    harness := PropertyPatternDefault()
    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    array: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)
    reflected: TypeInfo = new ReflectionTypeInfo(typeof(string))

    assert harness.Binding.Begin(PropertyPatternList(), nullable, 1, 1).DeclarationOwner == nullable
    assert harness.Binding.Begin(PropertyPatternList(), array, 1, 1).DeclarationOwner == array
    assert harness.Binding.Begin(PropertyPatternList(), reflected, 1, 1).DeclarationOwner == reflected
    assert harness.Binding.Begin(PropertyPatternList(), nullable, 1, 1).Substitution == null
}

// ---------------------------------------------------------------------------------------------
// THE THREE OUTCOMES
// ---------------------------------------------------------------------------------------------

test "a nested pattern yields ONE analyse step carrying the property's resolved type" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    nested := PropertyPatternSomePattern()
    properties := PropertyPatternList()
    properties.Add(PropertyPatternNested("Age", nested))

    state := harness.Binding.Begin(properties, dog, 7, 5)
    step := harness.Binding.NextStep(state)

    assert step != null
    assert step.Kind == 1
    assert step.Pattern == nested
    assert BuiltInTypes.Is(step.CarriedType, BuiltInTypes.Int)
    assert step.Name == null
    assert harness.Binding.NextStep(state) == null
    assert harness.Errors.Count == 0
}

test "a property with no nested pattern yields ONE declare step naming the property" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Age"))

    state := harness.Binding.Begin(properties, dog, 7, 5)
    step := harness.Binding.NextStep(state)

    assert step != null
    assert step.Kind == 2
    assert step.Name == "Age"
    assert step.Pattern == null
    assert BuiltInTypes.Is(step.CarriedType, BuiltInTypes.Int)
    assert step.Line == 7
    assert step.Column == 11
    assert harness.Errors.Count == 0
}

test "a property the scrutinee does not have yields NO step and reports" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternNested("Weight", PropertyPatternSomePattern()))

    state := harness.Binding.Begin(properties, dog, 7, 5)

    assert harness.Binding.NextStep(state) == null
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidPattern
    assert harness.Errors[0].Message == "'Dog' doesn't have a property named 'Weight'"
}

test "an empty property list finishes immediately and says nothing" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        new DeclaredMemberInfo[](0)
    )

    state := harness.Binding.Begin(PropertyPatternList(), dog, 7, 5)

    assert harness.Binding.NextStep(state) == null
    assert harness.Binding.NextStep(state) == null
    assert harness.Errors.Count == 0
}

test "an exhausted walk keeps answering null rather than restarting" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Age"))

    state := harness.Binding.Begin(properties, dog, 7, 5)

    assert harness.Binding.NextStep(state) != null
    assert harness.Binding.NextStep(state) == null
    assert harness.Binding.NextStep(state) == null
    assert state.Index == 1
}

// ---------------------------------------------------------------------------------------------
// THE ORDER, AND WHY THE WALK YIELDS INSTEAD OF HANDING BACK A SCHEDULE
// ---------------------------------------------------------------------------------------------

test "the steps arrive in WRITTEN order, one per property" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternTwoMembers(
            PropertyPatternProperty("Age", "int"),
            PropertyPatternProperty("Name", "string")
        )
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternNested("Age", PropertyPatternSomePattern()))
    properties.Add(PropertyPatternImplicit("Name"))

    assert PropertyPatternTranscript(harness, properties, dog, 7, 5) == "analyze:int|declare:Name:string:7:11"
    assert harness.Errors.Count == 0
}

test "a missing property REPORTS WHERE IT SITS — between the step before it and the step after it" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternTwoMembers(
            PropertyPatternProperty("Age", "int"),
            PropertyPatternProperty("Name", "string")
        )
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternNested("Age", PropertyPatternSomePattern()))
    properties.Add(PropertyPatternAt("Weight", 7, 20))
    properties.Add(PropertyPatternImplicit("Name"))

    state := harness.Binding.Begin(properties, dog, 7, 5)

    first := harness.Binding.NextStep(state)
    assert first != null
    assert first.Kind == 1
    // NOTHING has been reported yet: the walk has not passed the missing property.
    assert harness.Errors.Count == 0

    second := harness.Binding.NextStep(state)
    assert second != null
    assert second.Kind == 2
    assert second.Name == "Name"
    // The report landed while advancing PAST `Weight` — after the first step was handed over and
    // before the second was. A schedule computed up front would have reported before either.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'Dog' doesn't have a property named 'Weight'"
    assert harness.Binding.NextStep(state) == null
}

test "two missing properties report twice, in written order, and neither stops the walk" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternAt("Alpha", 7, 11))
    properties.Add(PropertyPatternAt("Beta", 7, 21))
    properties.Add(PropertyPatternImplicit("Age"))

    assert PropertyPatternTranscript(harness, properties, dog, 7, 5) == "declare:Age:int:7:11"
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "'Dog' doesn't have a property named 'Alpha'"
    assert harness.Errors[0].Column == 11
    assert harness.Errors[1].Message == "'Dog' doesn't have a property named 'Beta'"
    assert harness.Errors[1].Column == 21
}

// ---------------------------------------------------------------------------------------------
// WHERE A PROPERTY TYPE COMES FROM
// ---------------------------------------------------------------------------------------------

test "a declared member of a class, a struct and a record all resolve" {
    harness := PropertyPatternDefault()
    dogClass: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    point: TypeInfo = PropertyPatternStruct(
        harness,
        "Point",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    item: TypeInfo = PropertyPatternRecord(
        harness,
        "Item",
        new ParameterDeclarationInfo[](0),
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Age"))

    assert PropertyPatternTranscript(harness, properties, dogClass, 7, 5) == "declare:Age:int:7:11"
    assert PropertyPatternTranscript(harness, properties, point, 7, 5) == "declare:Age:int:7:11"
    assert PropertyPatternTranscript(harness, properties, item, 7, 5) == "declare:Age:int:7:11"
    assert harness.Errors.Count == 0
}

test "a FIELD is a value member and a FUNCTION is not" {
    harness := PropertyPatternDefault()
    withField: TypeInfo = PropertyPatternPlainClass(
        harness,
        "WithField",
        PropertyPatternOneMember(PropertyPatternMember(
            DeclaredMemberKind.Field,
            "Age",
            new SimpleTypeReference("int", 0, 0)
        ))
    )
    withFunction: TypeInfo = PropertyPatternPlainClass(
        harness,
        "WithFunction",
        PropertyPatternOneMember(PropertyPatternMember(
            DeclaredMemberKind.Function,
            "Age",
            new SimpleTypeReference("int", 0, 0)
        ))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Age"))

    assert PropertyPatternTranscript(harness, properties, withField, 7, 5) == "declare:Age:int:7:11"
    assert harness.Errors.Count == 0
    assert PropertyPatternTranscript(harness, properties, withFunction, 7, 5) == "<none>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'WithFunction' doesn't have a property named 'Age'"
}

test "a record's PRIMARY CONSTRUCTOR PARAMETER is not a value member here, and it reports" {
    // MEASURED AND PRESERVED, not improved: `record Item(Name: string, Count: int)` matched
    // `{ Count: 1 }` reports, because this member asks for DECLARED members only. Changing that is
    // a behaviour change and belongs to a slice that can prove it.
    harness := PropertyPatternDefault()
    item: TypeInfo = PropertyPatternRecord(
        harness,
        "Item",
        PropertyPatternOneParameter("Count", "int"),
        new DeclaredMemberInfo[](0)
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Count"))

    assert PropertyPatternTranscript(harness, properties, item, 7, 5) == "<none>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'Item' doesn't have a property named 'Count'"
}

test "the SUBSTITUTION is what gives a generic property its closed type" {
    harness := PropertyPatternDefault()
    definition: TypeInfo = PropertyPatternClass(
        harness,
        "Box",
        PropertyPatternOneTypeParameter("T"),
        PropertyPatternOneMember(PropertyPatternProperty("Value", "T"))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Value"))

    intBox := PropertyPatternGeneric("Box", definition, PropertyPatternOneArgument(BuiltInTypes.Int))
    stringBox := PropertyPatternGeneric(
        "Box",
        definition,
        PropertyPatternOneArgument(BuiltInTypes.String)
    )

    assert PropertyPatternTranscript(harness, properties, intBox, 7, 5) == "declare:Value:int:7:11"
    assert PropertyPatternTranscript(harness, properties, stringBox, 7, 5) == "declare:Value:string:7:11"
    // The OPEN definition, matched directly, answers the parameter itself.
    assert PropertyPatternTranscript(harness, properties, definition, 7, 5) == "declare:Value:T:7:11"
    assert harness.Errors.Count == 0
}

test "a REFLECTED scrutinee is asked its metadata, and the NULLABILITY conversion types the answer" {
    // Real BCL metadata rather than a stand-in, because the whole content of this arm is what
    // `GetProperty` answers on a real type — and `System.Type` is the case that proves the
    // conversion is the nullability-aware one: `Name` is a plain `string` while `FullName` carries
    // a nullable annotation and must come back as `string?`.
    harness := PropertyPatternDefault()
    reflected: TypeInfo = new ReflectionTypeInfo(typeof(Type))
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Name"))

    assert PropertyPatternTranscript(harness, properties, reflected, 7, 5) == "declare:Name:string:7:11"
    assert harness.Errors.Count == 0

    nullableProperties := PropertyPatternList()
    nullableProperties.Add(PropertyPatternImplicit("FullName"))
    assert PropertyPatternTranscript(harness, nullableProperties, reflected, 7, 5) == "declare:FullName:string?:7:11"
    assert harness.Errors.Count == 0

    boolProperties := PropertyPatternList()
    boolProperties.Add(PropertyPatternImplicit("IsAbstract"))
    assert PropertyPatternTranscript(harness, boolProperties, reflected, 7, 5) == "declare:IsAbstract:bool:7:11"
    assert harness.Errors.Count == 0
}

test "a reflected scrutinee with no such property reports like any other" {
    harness := PropertyPatternDefault()
    reflected: TypeInfo = new ReflectionTypeInfo(typeof(Type))
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Nope"))

    assert PropertyPatternTranscript(harness, properties, reflected, 7, 5) == "<none>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'" + PropertyPatternTypeName(reflected) + "' doesn't have a property named 'Nope'"
}

test "the DECLARED shape is asked before reflection, and only a declared MISS falls through" {
    // A source scrutinee never reaches the reflected arm at all — it is not a `ReflectionTypeInfo`,
    // so a name the source shape does not carry reports rather than being looked up anywhere else.
    // The source shape here deliberately names a BCL type and re-types its property.
    harness := PropertyPatternDefault()
    shadowing: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Type",
        PropertyPatternOneMember(PropertyPatternProperty("Name", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Name"))
    missingProperties := PropertyPatternList()
    missingProperties.Add(PropertyPatternImplicit("FullName"))

    assert PropertyPatternTranscript(harness, properties, shadowing, 7, 5) == "declare:Name:int:7:11"
    assert harness.Errors.Count == 0
    assert PropertyPatternTranscript(harness, missingProperties, shadowing, 7, 5) == "<none>"
    assert harness.Errors.Count == 1
}

test "a scrutinee with neither a source shape nor reflected metadata reports every property" {
    harness := PropertyPatternDefault()
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Length"))

    nullable: TypeInfo = new NullableTypeInfo(
        PropertyPatternPlainClass(harness, "Box", new DeclaredMemberInfo[](0))
    )
    array: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    assert PropertyPatternTranscript(harness, properties, BuiltInTypes.Int, 7, 5) == "<none>"
    assert PropertyPatternTranscript(harness, properties, nullable, 7, 5) == "<none>"
    assert PropertyPatternTranscript(harness, properties, array, 7, 5) == "<none>"
    assert harness.Errors.Count == 3
    assert harness.Errors[0].Message == "'int' doesn't have a property named 'Length'"
    // A NULLABLE renders with its `?`, which is the honest message: a nullable really has no
    // declared members until it is narrowed.
    assert harness.Errors[1].Message == "'Box?' doesn't have a property named 'Length'"
    assert harness.Errors[2].Message == "'int[]' doesn't have a property named 'Length'"
}

test "an UNKNOWN-typed declared member still resolves — it is a member, just not a typed one" {
    harness := PropertyPatternDefault()
    untyped: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Untyped",
        PropertyPatternOneMember(PropertyPatternMember(
            DeclaredMemberKind.Property,
            "Age",
            null
        ))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Age"))

    state := harness.Binding.Begin(properties, untyped, 7, 5)
    step := harness.Binding.NextStep(state)

    assert step != null
    assert step.Kind == 2
    assert BuiltInTypes.IsUnknown(step.CarriedType)
    assert harness.Errors.Count == 0
}

test "an UNOWNED owner still FINDS its member — it just cannot type it" {
    // Registration is what makes a member's type resolvable, and the two answers are different
    // failures: a name the shape does not carry REPORTS, while a name it carries on an owner the
    // context does not own binds as `unknown` and stays silent.
    harness := PropertyPatternDefault()
    unowned := PropertyPatternUnownedClass(
        "Stranger",
        new TypeParameter[](0),
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternImplicit("Age"))

    assert PropertyPatternTranscript(harness, properties, unowned, 7, 5) == "declare:Age:unknown:7:11"
    assert harness.Errors.Count == 0

    owned := PropertyPatternPlainClass(
        harness,
        "Owned",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    assert PropertyPatternTranscript(harness, properties, owned, 7, 5) == "declare:Age:int:7:11"
    assert harness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// THE BINDING NAME AND THE SPAN
// ---------------------------------------------------------------------------------------------

test "the implicit binding takes the PROPERTY NAME, which is the only shape the parser builds" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(new PropertyPattern("Age", null, null, 7, 11))

    state := harness.Binding.Begin(properties, dog, 7, 5)
    step := harness.Binding.NextStep(state)

    assert step != null
    assert step.Name == "Age"
}

test "an EXPLICIT binding name wins — an arm no parser production reaches, pinned by construction" {
    // BOTH parser productions build a `PropertyPattern` with a null `BindingName` (the nested form
    // and the implicit `{ value }` form alike), so `BindingName ?? Name` always takes the fallback
    // in production. The arm is live code a later parser change can reach, so it is pinned here
    // rather than deleted.
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(new PropertyPattern("Age", null, "renamed", 7, 11))

    state := harness.Binding.Begin(properties, dog, 7, 5)
    step := harness.Binding.NextStep(state)

    assert step != null
    assert step.Name == "renamed"
    // The SPAN still measures the PROPERTY's name, not the binding's.
    assert step.Line == 7
    assert step.Column == 11
}

test "a property with no position of its own is anchored on the ENCLOSING pattern" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    properties := PropertyPatternList()
    properties.Add(new PropertyPattern("Age", null, null, 0, 0))

    state := harness.Binding.Begin(properties, dog, 9, 7)
    step := harness.Binding.NextStep(state)

    assert step != null
    assert step.Line == 9
    assert step.Column == 7
}

test "the missing-property diagnostic carries the property NAME's own span" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        new DeclaredMemberInfo[](0)
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternAt("Weight", 12, 21))

    state := harness.Binding.Begin(properties, dog, 7, 5)

    assert harness.Binding.NextStep(state) == null
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 12
    assert harness.Errors[0].Column == 21
    assert harness.Errors[0].Length == 6
}

test "an unpositioned missing property falls back to the enclosing pattern's position" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        new DeclaredMemberInfo[](0)
    )
    properties := PropertyPatternList()
    properties.Add(new PropertyPattern("Weight", null, null, 0, 0))

    state := harness.Binding.Begin(properties, dog, 9, 7)

    assert harness.Binding.NextStep(state) == null
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 9
    assert harness.Errors[0].Column == 7
}

test "the diagnostic renders the SCRUTINEE, not the owner the members were found on" {
    // A closed generic reports as `Box<int>` even though the lookup happened on the open `Box`.
    harness := PropertyPatternDefault()
    definition: TypeInfo = PropertyPatternClass(
        harness,
        "Box",
        PropertyPatternOneTypeParameter("T"),
        PropertyPatternOneMember(PropertyPatternProperty("Value", "T"))
    )
    closed := PropertyPatternGeneric(
        "Box",
        definition,
        PropertyPatternOneArgument(BuiltInTypes.Int)
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternAt("Nope", 7, 11))

    state := harness.Binding.Begin(properties, closed, 7, 5)

    assert harness.Binding.NextStep(state) == null
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'" + PropertyPatternTypeName(closed) + "' doesn't have a property named 'Nope'"
    assert harness.Errors[0].Message != "'Box' doesn't have a property named 'Nope'"
}

test "the diagnostic is NL503 with no suggestion line" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        new DeclaredMemberInfo[](0)
    )
    properties := PropertyPatternList()
    properties.Add(PropertyPatternAt("Weight", 7, 11))

    state := harness.Binding.Begin(properties, dog, 7, 5)

    assert harness.Binding.NextStep(state) == null
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidPattern
    assert harness.Errors[0].Suggestion == null
}

// ---- `BoundName`, the ONE answer to what a property pattern binds (playground union-shorthand chip) ----
//
// The rule had three spellings before this chip: this walk's, the union arm's in
// `AnalyzerPatternAnalysis`, and the browser runner's — and the runner's was WRONG. It bound only
// when `BindingName` was non-null, which no parser production sets, so `Found { name, score }` bound
// nothing and a SHIPPED tutorial example answered `PG208` where `nlc run` printed its own declared
// `ExpectedOutput`. There is one spelling now and it is pinned here, directly, rather than only
// through the two walks that call it.

test "BoundName: the implicit `{ value }` form binds the PROPERTY's own name — the production form, and the one the browser runner used to drop" {
    assert AnalyzerPropertyPatternBinding.BoundName(new PropertyPattern("Radius", null, null, 7, 11)) == "Radius"
    assert AnalyzerPropertyPatternBinding.BoundName(new PropertyPattern("name", null, null, 10, 30)) == "name"
    assert AnalyzerPropertyPatternBinding.BoundName(new PropertyPattern("score", null, null, 10, 36)) == "score"
}

test "BoundName: an EXPLICIT binding name wins — the arm no parser production reaches, pinned by construction" {
    assert AnalyzerPropertyPatternBinding.BoundName(new PropertyPattern("Age", null, "renamed", 7, 11)) == "renamed"
    // An empty explicit name is a NAME, not an absence: only null takes the fallback.
    assert AnalyzerPropertyPatternBinding.BoundName(new PropertyPattern("Age", null, "", 7, 11)) == ""
}

test "BoundName: a property carrying a NESTED pattern still answers by the same order of preference — the nested form is decided by the CALLER, not by this rule" {
    nested: Pattern = new IdentifierPattern("r", 7, 20)
    assert AnalyzerPropertyPatternBinding.BoundName(new PropertyPattern("Radius", nested, null, 7, 11)) == "Radius"
    assert AnalyzerPropertyPatternBinding.BoundName(new PropertyPattern("Radius", nested, "renamed", 7, 11)) == "renamed"
}

test "BoundName is what the object-pattern walk itself uses — the walk's step name and the rule agree on the same property" {
    harness := PropertyPatternDefault()
    dog: TypeInfo = PropertyPatternPlainClass(
        harness,
        "Dog",
        PropertyPatternOneMember(PropertyPatternProperty("Age", "int"))
    )
    property := PropertyPatternAt("Age", 7, 11)
    properties := PropertyPatternList()
    properties.Add(property)

    state := harness.Binding.Begin(properties, dog, 7, 5)
    step := harness.Binding.NextStep(state)

    assert step != null
    assert step.Name == AnalyzerPropertyPatternBinding.BoundName(property)
    assert step.Name == "Age"
}

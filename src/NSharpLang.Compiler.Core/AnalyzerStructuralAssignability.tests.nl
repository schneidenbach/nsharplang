namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the two assignability arms that have to look something up.
//
// Both were `private` in Analyzer.cs and neither was named by a test: the duck arm was pinned only
// through end-to-end `NL202` diagnostics on a duck-interface assignment, and the ActionResult arm
// only through a single ASP.NET example. This is their first DIRECT pinning, and it goes at the
// decisions a reader would otherwise have to infer:
//
//   * a source with NO declared members satisfies nothing — including the EMPTY duck interface,
//     because the member list is consulted before the interface's demands are;
//   * only FUNCTION members are demanded and only function members can satisfy them, in both
//     directions;
//   * signature equality is by the RESOLVED type's display form, and an absent return type is
//     `void` rather than "unknown";
//   * the resolution ORDER — a name or arity mismatch resolves NOTHING, so a rejected candidate
//     writes no semantic-model record;
//   * the ActionResult arm's four refusals, and that it needs the probe to actually find the type.
func StructuralScopes(): AnalyzerScopeStack {
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    return scopes
}

func StructuralResolver(scopes: AnalyzerScopeStack, model: SemanticModel): AnalyzerTypeResolver {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal)
    )
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    return new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        new AnalyzerDiagnosticSink(new List<CompilerError>(), provider),
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal),
        model,
        new BindingMap()
    )
}

func StructuralOwnerWith(probe: AnalyzerExternalTypeProbe, model: SemanticModel): AnalyzerStructuralAssignability {
    return new AnalyzerStructuralAssignability(StructuralResolver(StructuralScopes(), model), probe)
}

func StructuralOwner(model: SemanticModel): AnalyzerStructuralAssignability {
    return StructuralOwnerWith(new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>()), model)
}

// A declared member shaped only where these contracts read it: kind, name, parameter list and
// return type.
func StructuralMember(
    kind: DeclaredMemberKind,
    name: string,
    parameterTypes: TypeReference[],
    returnType: TypeReference?
): DeclaredMemberInfo {
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
        parameterTypes.Length,
        new string[](parameterTypes.Length),
        parameterTypes,
        new ParameterModifier[](parameterTypes.Length),
        parameterTypes.Length,
        false,
        false,
        returnType,
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

func StructuralNoParameters(): TypeReference[] {
    return new TypeReference[](0)
}

func StructuralOneParameter(name: string): TypeReference[] {
    result := new TypeReference[](1)
    element: TypeReference = new SimpleTypeReference(name, 0, 0)
    result[0] = element
    return result
}

func StructuralMembers(members: DeclaredMemberInfo[]): DeclaredMemberInfo[] {
    return members
}

func StructuralClass(name: string, members: DeclaredMemberInfo[]): ClassTypeInfo {
    return new ClassTypeInfo(
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
}

func StructuralStruct(name: string, members: DeclaredMemberInfo[]): StructTypeInfo {
    return new StructTypeInfo(
        name,
        1,
        1,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        members,
        new NestedTypeInfo[](0)
    )
}

func StructuralRecord(name: string, members: DeclaredMemberInfo[]): RecordTypeInfo {
    return new RecordTypeInfo(
        name,
        1,
        1,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        members,
        new NestedTypeInfo[](0)
    )
}

func StructuralInterface(name: string, isDuck: bool, members: DeclaredMemberInfo[]): InterfaceTypeInfo {
    return new InterfaceTypeInfo(
        name,
        1,
        1,
        isDuck,
        new TypeReference[](0),
        new TypeParameter[](0),
        members,
        new NestedTypeInfo[](0)
    )
}

// `func Area(): int` — the shape most of these contracts demand and satisfy.
func StructuralAreaMember(): DeclaredMemberInfo {
    return StructuralMember(
        DeclaredMemberKind.Function,
        "Area",
        StructuralNoParameters(),
        new SimpleTypeReference("int", 0, 0)
    )
}

func StructuralOneMember(member: DeclaredMemberInfo): DeclaredMemberInfo[] {
    result := new DeclaredMemberInfo[](1)
    result[0] = member
    return result
}

func StructuralTwoMembers(first: DeclaredMemberInfo, second: DeclaredMemberInfo): DeclaredMemberInfo[] {
    result := new DeclaredMemberInfo[](2)
    result[0] = first
    result[1] = second
    return result
}

test "a source with no declared members satisfies NOTHING — including the empty duck interface" {
    owner := StructuralOwner(new SemanticModel())
    empty := StructuralInterface("IEmpty", true, new DeclaredMemberInfo[](0))

    assert !owner.ImplementsDuckInterface(BuiltInTypes.Int, empty)
    assert !owner.ImplementsDuckInterface(new ArrayTypeInfo(BuiltInTypes.Int), empty)
    assert !owner.ImplementsDuckInterface(new ReflectionTypeInfo(typeof(string)), empty)
    assert !owner.ImplementsDuckInterface(StructuralInterface("IOther", true, new DeclaredMemberInfo[](0)), empty)
}

test "a declaring family with an empty member list DOES satisfy the empty duck interface" {
    owner := StructuralOwner(new SemanticModel())
    empty := StructuralInterface("IEmpty", true, new DeclaredMemberInfo[](0))

    assert owner.ImplementsDuckInterface(StructuralClass("Bare", new DeclaredMemberInfo[](0)), empty)
    assert owner.ImplementsDuckInterface(StructuralStruct("Bare", new DeclaredMemberInfo[](0)), empty)
    assert owner.ImplementsDuckInterface(StructuralRecord("Bare", new DeclaredMemberInfo[](0)), empty)
}

test "all three declaring families satisfy a duck interface they match" {
    owner := StructuralOwner(new SemanticModel())
    shape := StructuralInterface("IShape", true, StructuralOneMember(StructuralAreaMember()))
    members := StructuralOneMember(StructuralAreaMember())

    assert owner.ImplementsDuckInterface(StructuralClass("Square", members), shape)
    assert owner.ImplementsDuckInterface(StructuralStruct("Dot", members), shape)
    assert owner.ImplementsDuckInterface(StructuralRecord("Box", members), shape)
}

test "a missing function, a wrong return type and a wrong arity each refuse" {
    owner := StructuralOwner(new SemanticModel())
    source := StructuralClass("Square", StructuralOneMember(StructuralAreaMember()))

    missing := StructuralInterface("IMissing", true, StructuralOneMember(StructuralMember(
        DeclaredMemberKind.Function,
        "Perimeter",
        StructuralNoParameters(),
        new SimpleTypeReference("int", 0, 0)
    )))
    wrongReturn := StructuralInterface("IWrong", true, StructuralOneMember(StructuralMember(
        DeclaredMemberKind.Function,
        "Area",
        StructuralNoParameters(),
        new SimpleTypeReference("string", 0, 0)
    )))
    wrongArity := StructuralInterface("IArity", true, StructuralOneMember(StructuralMember(
        DeclaredMemberKind.Function,
        "Area",
        StructuralOneParameter("int"),
        new SimpleTypeReference("int", 0, 0)
    )))

    assert !owner.ImplementsDuckInterface(source, missing)
    assert !owner.ImplementsDuckInterface(source, wrongReturn)
    assert !owner.ImplementsDuckInterface(source, wrongArity)
}

test "NON-function members impose nothing and satisfy nothing, in both directions" {
    owner := StructuralOwner(new SemanticModel())
    property := StructuralMember(
        DeclaredMemberKind.Property,
        "Area",
        StructuralNoParameters(),
        new SimpleTypeReference("int", 0, 0)
    )

    // A property on the INTERFACE is not a demand: a class with only the matching method still wins.
    demandsProperty := StructuralInterface(
        "IValued",
        true,
        StructuralTwoMembers(property, StructuralAreaMember())
    )
    assert owner.ImplementsDuckInterface(
        StructuralClass("Square", StructuralOneMember(StructuralAreaMember())),
        demandsProperty
    )

    // A property on the SOURCE cannot satisfy a demanded function.
    demandsArea := StructuralInterface("IShape", true, StructuralOneMember(StructuralAreaMember()))
    assert !owner.ImplementsDuckInterface(StructuralClass("Holder", StructuralOneMember(property)), demandsArea)
}

test "signature equality is by name, arity, parameter types and return type" {
    owner := StructuralOwner(new SemanticModel())
    area := StructuralAreaMember()

    assert owner.MethodSignaturesMatch(area, StructuralAreaMember())
    assert !owner.MethodSignaturesMatch(area, StructuralMember(
        DeclaredMemberKind.Function,
        "Other",
        StructuralNoParameters(),
        new SimpleTypeReference("int", 0, 0)
    ))
    assert !owner.MethodSignaturesMatch(area, StructuralMember(
        DeclaredMemberKind.Function,
        "Area",
        StructuralOneParameter("int"),
        new SimpleTypeReference("int", 0, 0)
    ))
    assert !owner.MethodSignaturesMatch(area, StructuralMember(
        DeclaredMemberKind.Function,
        "Area",
        StructuralNoParameters(),
        new SimpleTypeReference("string", 0, 0)
    ))

    matchingParameters := StructuralMember(
        DeclaredMemberKind.Function,
        "Scale",
        StructuralOneParameter("int"),
        null
    )
    assert owner.MethodSignaturesMatch(matchingParameters, StructuralMember(
        DeclaredMemberKind.Function,
        "Scale",
        StructuralOneParameter("int"),
        null
    ))
    assert !owner.MethodSignaturesMatch(matchingParameters, StructuralMember(
        DeclaredMemberKind.Function,
        "Scale",
        StructuralOneParameter("string"),
        null
    ))
}

test "an ABSENT return type is `void`, not unknown — so it matches a declared `void` and nothing else" {
    owner := StructuralOwner(new SemanticModel())
    absent := StructuralMember(DeclaredMemberKind.Function, "Scale", StructuralNoParameters(), null)

    assert owner.MethodSignaturesMatch(absent, StructuralMember(
        DeclaredMemberKind.Function,
        "Scale",
        StructuralNoParameters(),
        null
    ))
    assert owner.MethodSignaturesMatch(absent, StructuralMember(
        DeclaredMemberKind.Function,
        "Scale",
        StructuralNoParameters(),
        new SimpleTypeReference("void", 0, 0)
    ))
    assert !owner.MethodSignaturesMatch(absent, StructuralMember(
        DeclaredMemberKind.Function,
        "Scale",
        StructuralNoParameters(),
        new SimpleTypeReference("int", 0, 0)
    ))
}

test "a name or arity mismatch resolves NOTHING — a rejected candidate writes no record" {
    model := new SemanticModel()
    owner := StructuralOwner(model)

    positioned := StructuralMember(
        DeclaredMemberKind.Function,
        "Area",
        StructuralNoParameters(),
        new SimpleTypeReference("int", 21, 4)
    )
    otherName := StructuralMember(
        DeclaredMemberKind.Function,
        "Perimeter",
        StructuralNoParameters(),
        new SimpleTypeReference("int", 22, 4)
    )

    assert !owner.MethodSignaturesMatch(positioned, otherName)
    assert model.TypeReferenceTypes.Count == 0

    // The same two members WITH matching names do resolve both return types.
    assert owner.MethodSignaturesMatch(positioned, StructuralMember(
        DeclaredMemberKind.Function,
        "Area",
        StructuralNoParameters(),
        new SimpleTypeReference("int", 22, 4)
    ))
    assert model.TypeReferenceTypes.Count == 2
}

test "the ActionResult arm refuses everything that is not a one-argument ActionResult over a CLR source" {
    owner := StructuralOwner(new SemanticModel())
    source := new ReflectionTypeInfo(typeof(ArgumentException))

    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    twoArguments := new List<TypeInfo>()
    twoArguments.Add(BuiltInTypes.Int)
    twoArguments.Add(BuiltInTypes.Int)

    assert !owner.IsAspNetActionResultGenericAssignable(BuiltInTypes.Int, source)
    assert !owner.IsAspNetActionResultGenericAssignable(
        new GenericTypeInfo("ActionResult", twoArguments, null),
        source
    )
    assert !owner.IsAspNetActionResultGenericAssignable(
        new GenericTypeInfo("SomethingElse", arguments, null),
        source
    )
    // Both accepted spellings still refuse while the probe cannot find the type.
    assert !owner.IsAspNetActionResultGenericAssignable(
        new GenericTypeInfo("ActionResult", arguments, null),
        source
    )
    assert !owner.IsAspNetActionResultGenericAssignable(
        new GenericTypeInfo("Microsoft.AspNetCore.Mvc.ActionResult", arguments, null),
        source
    )
    // A source that is not a CLR type refuses before the probe is consulted at all.
    assert !owner.IsAspNetActionResultGenericAssignable(
        new GenericTypeInfo("ActionResult", arguments, null),
        BuiltInTypes.Int
    )
}

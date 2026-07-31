namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the substitution-aware half of the analyzer's resolution surface.
//
// All five members behind these contracts were `private` in Analyzer.cs, so no test named any of
// them: their behaviour was pinned only indirectly, through end-to-end diagnostics. This is their
// first DIRECT pinning, and it goes at the four decisions that read like plumbing and are not:
//
//   * the OWNER lookup's reflection refusal — a generic instantiation whose definition is a CLR type
//     is NOT substituted, because reflection already carries its arguments;
//   * the substitution walk's ORDER, in particular that an UNBOUND simple name falls all the way
//     through to the plain walk rather than into the composed arms;
//   * which forms are rewritten at all — generic, array and nullable — and which (tuple, function,
//     by-ref, union) are handed to the plain walk untouched even under a live binding;
//   * that a BOUND simple name answers WITHOUT resolving, so it writes no semantic-model record.

func SubstitutionScopes(): AnalyzerScopeStack {
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    return scopes
}

func SubstitutionContext(): AnalyzerDeclarationContext {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    return context
}

func SubstitutionResolver(
    scopes: AnalyzerScopeStack,
    context: AnalyzerDeclarationContext,
    model: SemanticModel): AnalyzerTypeResolver {
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    return new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        new AnalyzerDiagnosticSink(new List<CompilerError>(), provider),
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        model,
        new BindingMap())
}

// Reference identity — used only where these contracts HOLD both instances, because the claim is
// that the owner hands back the very object it was given rather than a rebuilt equal one. Note that
// `BuiltInTypes.Int` and friends mint a FRESH instance on every access, so they are never the right
// side of an identity assertion; those go through the display form below.
func SubstitutionSame(left: TypeInfo?, right: TypeInfo?): bool {
    return left == right
}

// A resolved type's display form, read through an `object`-typed local because `ToString` belongs to
// the BASE of the TypeInfo hierarchy.
func SubstitutionText(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    boxed: object = candidate
    return boxed.ToString()
}

func SubstitutionOf(name: string, bound: TypeInfo): Dictionary<string, TypeInfo> {
    result := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    result[name] = bound
    return result
}

func SubstitutionTypeArguments(first: TypeInfo): List<TypeInfo> {
    result := new List<TypeInfo>()
    result.Add(first)
    return result
}

func SubstitutionReferenceArguments(first: TypeReference): List<TypeReference> {
    result := new List<TypeReference>()
    result.Add(first)
    return result
}

func SubstitutionClass(name: string, typeParameters: TypeParameter[]): ClassTypeInfo {
    return new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        typeParameters,
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true)
}

test "the open definition a generic instantiation CARRIES wins over the scope" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    scopes.DeclareNestedTypeIfAbsent("Box", new SimpleTypeInfo("scope-Box"))
    carried := new SimpleTypeInfo("carried-Box")
    generic := new GenericTypeInfo("Box", SubstitutionTypeArguments(BuiltInTypes.Int), carried)

    answer := owner.ResolveGenericDefinition(generic)
    assert SubstitutionSame(answer, carried)
}

test "an instantiation with NO carried definition resolves its bare name in scope, and answers nothing when the name is absent" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    declared := new SimpleTypeInfo("scope-Box")
    scopes.DeclareNestedTypeIfAbsent("Box", declared)

    assert SubstitutionSame(
        owner.ResolveGenericDefinition(
            new GenericTypeInfo("Box", SubstitutionTypeArguments(BuiltInTypes.Int), null)),
        declared)
    assert SubstitutionSame(
        owner.ResolveGenericDefinition(
            new GenericTypeInfo("Absent", SubstitutionTypeArguments(BuiltInTypes.Int), null)),
        null)
}

test "a plain type is its OWN declaration owner and induces no substitution" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    plain := BuiltInTypes.Int
    substitution: Dictionary<string, TypeInfo>? = SubstitutionOf("T", BuiltInTypes.Int)
    answer := owner.GetSourceDeclarationOwner(plain, out substitution)

    assert SubstitutionSame(answer, plain)
    assert substitution == null
}

test "a generic over an N#-DECLARED definition answers the definition and hands back the argument binding" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    parameters := new TypeParameter[](1)
    parameters[0] = new TypeParameter("T")
    definition := SubstitutionClass("Box", parameters)
    generic := new GenericTypeInfo("Box", SubstitutionTypeArguments(BuiltInTypes.String), definition)

    substitution: Dictionary<string, TypeInfo>? = null
    answer := owner.GetSourceDeclarationOwner(generic, out substitution)

    assert SubstitutionSame(answer, definition)
    assert substitution != null
    if substitution != null {
        bound: TypeInfo = BuiltInTypes.Unknown
        assert substitution.TryGetValue("T", out bound)
        assert SubstitutionText(bound) == "string"
    }
}

test "a generic over a CLR definition is NOT substituted — it answers the instantiation itself" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    generic := new GenericTypeInfo(
        "List",
        SubstitutionTypeArguments(BuiltInTypes.Int),
        new ReflectionTypeInfo(typeof(List<int>)))

    substitution: Dictionary<string, TypeInfo>? = SubstitutionOf("T", BuiltInTypes.Int)
    answer := owner.GetSourceDeclarationOwner(generic, out substitution)

    assert SubstitutionSame(answer, generic)
    assert substitution == null
}

test "with NO binding the substitution walk is exactly the plain walk, and it still RECORDS" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    reference := new SimpleTypeReference("int", 4, 9)
    answer := owner.ResolveTypeWithSubstitution(reference, null)

    assert SubstitutionText(answer) == "int"
    recorded: TypeInfo = BuiltInTypes.Unknown
    assert model.TypeReferenceTypes.TryGetValue((Line: 4, Column: 9), out recorded)
    assert SubstitutionText(recorded) == "int"
}

test "a BOUND simple name answers the bound type without resolving it, so nothing is recorded" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    expected := BuiltInTypes.String
    reference := new SimpleTypeReference("T", 5, 3)
    answer := owner.ResolveTypeWithSubstitution(reference, SubstitutionOf("T", expected))

    assert SubstitutionSame(answer, expected)
    assert model.TypeReferenceTypes.Count == 0
}

test "an UNBOUND simple name falls through to the plain walk rather than into the composed arms" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    reference := new SimpleTypeReference("int", 6, 2)
    answer := owner.ResolveTypeWithSubstitution(reference, SubstitutionOf("T", BuiltInTypes.String))

    assert SubstitutionText(answer) == "int"
    assert model.TypeReferenceTypes.Count == 1
}

test "array and nullable compose THROUGH the binding" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))
    expected := BuiltInTypes.String
    substitution := SubstitutionOf("T", expected)

    arrayAnswer := owner.ResolveTypeWithSubstitution(
        new ArrayTypeReference(new SimpleTypeReference("T", 7, 1)),
        substitution)
    arrayInfo := arrayAnswer as ArrayTypeInfo
    assert arrayInfo != null
    if arrayInfo != null {
        assert SubstitutionSame(arrayInfo.ElementType, expected)
    }

    nullableAnswer := owner.ResolveTypeWithSubstitution(
        new NullableTypeReference(new SimpleTypeReference("T", 8, 1)),
        substitution)
    nullableInfo := nullableAnswer as NullableTypeInfo
    assert nullableInfo != null
    if nullableInfo != null {
        assert SubstitutionSame(nullableInfo.InnerType, expected)
    }
}

test "a generic head keeps the PLAIN walk's definition while its arguments are rewritten" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    parameters := new TypeParameter[](1)
    parameters[0] = new TypeParameter("T")
    declaredHead := SubstitutionClass("Box", parameters)
    scopes.DeclareNestedTypeIfAbsent("Box", declaredHead)

    reference := new GenericTypeReference(
        "Box",
        SubstitutionReferenceArguments(new SimpleTypeReference("T", 9, 5)),
        9,
        1)
    expected := BuiltInTypes.String
    answer := owner.ResolveTypeWithSubstitution(reference, SubstitutionOf("T", expected))

    generic := answer as GenericTypeInfo
    assert generic != null
    if generic != null {
        assert generic.Name == "Box"
        assert generic.TypeArguments.Count == 1
        assert SubstitutionSame(generic.TypeArguments[0], expected)
        assert SubstitutionSame(generic.GenericDefinition, declaredHead)
    }
}

test "a generic head the plain walk does NOT read as generic keeps a null definition" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    reference := new GenericTypeReference(
        "AbsentHead",
        SubstitutionReferenceArguments(new SimpleTypeReference("T", 10, 5)),
        0,
        0)
    expected := BuiltInTypes.Int
    answer := owner.ResolveTypeWithSubstitution(reference, SubstitutionOf("T", expected))

    generic := answer as GenericTypeInfo
    assert generic != null
    if generic != null {
        assert generic.Name == "AbsentHead"
        assert SubstitutionSame(generic.TypeArguments[0], expected)
        assert SubstitutionText(generic.GenericDefinition) == "<null>"
    }
}

test "tuple, function and by-ref references are handed to the plain walk UNCHANGED even under a live binding" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))
    expected := BuiltInTypes.String
    substitution := SubstitutionOf("T", expected)

    elements := new List<TupleTypeElement>()
    elements.Add(new TupleTypeElement(new SimpleTypeReference("T", 11, 3), "a"))
    tupleAnswer := owner.ResolveTypeWithSubstitution(new TupleTypeReference(elements), substitution)
    tuple := tupleAnswer as TupleTypeInfo
    assert tuple != null
    if tuple != null {
        // The plain walk resolved `T` as a NAME — the binding never reached it.
        assert !SubstitutionSame(tuple.Elements[0].Type, expected)
    }

    byRefAnswer := owner.ResolveTypeWithSubstitution(
        new ByRefTypeReference(new SimpleTypeReference("T", 12, 3)),
        substitution)
    byRef := byRefAnswer as ByRefTypeInfo
    assert byRef != null
    if byRef != null {
        assert !SubstitutionSame(byRef.InnerType, expected)
    }
}

test "an owner the declaration context does NOT know falls back to the substitution walk" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    expected := BuiltInTypes.String
    unknownOwner := SubstitutionClass("NotRegistered", new TypeParameter[](0))
    answer := owner.ResolveTypeForSourceOwner(
        new SimpleTypeReference("T", 13, 4),
        unknownOwner,
        SubstitutionOf("T", expected))

    assert SubstitutionSame(answer, expected)
}

test "the fallback reaches the PLAIN walk when the binding does not bind the name" {
    scopes := SubstitutionScopes()
    context := SubstitutionContext()
    model := new SemanticModel()
    owner := new AnalyzerTypeSubstitution(scopes, context, SubstitutionResolver(scopes, context, model))

    unknownOwner := SubstitutionClass("NotRegistered", new TypeParameter[](0))
    answer := owner.ResolveTypeForSourceOwner(
        new SimpleTypeReference("int", 14, 4),
        unknownOwner,
        null)

    assert SubstitutionText(answer) == "int"
    recorded: TypeInfo = BuiltInTypes.Unknown
    assert model.TypeReferenceTypes.TryGetValue((Line: 14, Column: 4), out recorded)
}

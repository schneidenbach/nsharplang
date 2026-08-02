namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the analyzer's extension surface.
//
// Every member here was `private` in Analyzer.cs, so nothing named it: whether an extension method
// was OFFERED for a receiver was pinned only indirectly, through end-to-end diagnostics on calls
// that happened to reach it. These are its first DIRECT contracts, and they go at the properties no
// single call site reveals — that a type-parameter receiver is accepted WITHOUT being resolved,
// that a resolved receiver matches by assignability and not only by identity, that a NAMED source
// extension which rejects the receiver still falls through to the external scan, that the
// containing type name is read at the CALL, and that the three collections are LIVE.

class ExtensionReceiverHarness {
    Resolution: AnalyzerExtensionMethodResolution
    Resolver: AnalyzerTypeResolver
    Declared: List<FunctionDeclaration>
    Namespaces: List<string>
    Assemblies: List<Assembly>

    constructor(
        resolution: AnalyzerExtensionMethodResolution,
        resolver: AnalyzerTypeResolver,
        declared: List<FunctionDeclaration>,
        namespaces: List<string>,
        assemblies: List<Assembly>) {
        Resolution = resolution
        Resolver = resolver
        Declared = declared
        Namespaces = namespaces
        Assemblies = assemblies
    }
}

func ExtensionReceiverDefault(): ExtensionReceiverHarness {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        new AnalyzerDiagnosticSink(new List<CompilerError>(), provider),
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        new SemanticModel(),
        new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)

    // The three LIVE collections. They are handed over by REFERENCE, exactly as the analyzer's own
    // `readonly` fields are, and the contracts below mutate them AFTER construction to prove it.
    declared := new List<FunctionDeclaration>()
    namespaces := new List<string>()
    assemblies := new List<Assembly>()

    return new ExtensionReceiverHarness(
        new AnalyzerExtensionMethodResolution(
            resolver,
            assignability,
            context,
            functionTypes,
            clrConversion,
            declared,
            namespaces,
            assemblies),
        resolver,
        declared,
        namespaces,
        assemblies)
}

func ExtensionReceiverParameter(name: string, typeName: string): Parameter {
    reference: TypeReference = new SimpleTypeReference(typeName)
    return new Parameter(name, reference, null, false, ParameterModifier.None, null, 1, 1, false, null)
}

func ExtensionReceiverDeclaration(
    name: string,
    parameters: List<Parameter>,
    typeParameters: List<TypeParameter>?): FunctionDeclaration {
    return new FunctionDeclaration(
        name, parameters, null, null, null, typeParameters, null, Modifiers.Public,
        new List<AttributeNode>(), false, null, false, false, 1, 1)
}

func ExtensionReceiverOn(receiverTypeName: string, typeParameterNames: string[]): FunctionDeclaration {
    parameters := new List<Parameter>()
    parameters.Add(ExtensionReceiverParameter("self", receiverTypeName))

    typeParameters: List<TypeParameter>? = null
    if typeParameterNames.Length > 0 {
        collected := new List<TypeParameter>()
        index := 0
        while index < typeParameterNames.Length {
            collected.Add(new TypeParameter(typeParameterNames[index]))
            index = index + 1
        }
        typeParameters = collected
    }

    return ExtensionReceiverDeclaration("Probe", parameters, typeParameters)
}

func ExtensionReceiverNoNames(): string[] {
    return new string[](0)
}

func ExtensionReceiverNames(first: string): string[] {
    result := new string[](1)
    result[0] = first
    return result
}

test "a declaration with no parameters is never applicable" {
    harness := ExtensionReceiverDefault()

    // The receiver comes from the FIRST parameter, so a parameterless declaration has no receiver
    // to test and cannot be an extension. This is the guard the caller's own filter relies on: it
    // must hold here too, because the two are not always both applied.
    empty := ExtensionReceiverDeclaration("Probe", new List<Parameter>(), null)
    assert !harness.Resolution.IsExtensionReceiverApplicable(empty, BuiltInTypes.Int)
    assert !harness.Resolution.IsExtensionReceiverApplicable(empty, BuiltInTypes.String)

    // Not even when the declaration is generic — a type parameter is not a receiver.
    emptyGeneric := ExtensionReceiverDeclaration(
        "Probe", new List<Parameter>(), ExtensionReceiverTypeParameterList("T"))
    assert !harness.Resolution.IsExtensionReceiverApplicable(emptyGeneric, BuiltInTypes.Int)
}

func ExtensionReceiverTypeParameterList(name: string): List<TypeParameter> {
    result := new List<TypeParameter>()
    result.Add(new TypeParameter(name))
    return result
}

test "an unconstrained receiver accepts every receiver type" {
    harness := ExtensionReceiverDefault()

    // `func Probe<T>(self: T)` — the receiver spelling IS the function's own type parameter, so the
    // extension is offered for anything.
    unconstrained := ExtensionReceiverOn("T", ExtensionReceiverNames("T"))
    assert harness.Resolution.IsExtensionReceiverApplicable(unconstrained, BuiltInTypes.Int)
    assert harness.Resolution.IsExtensionReceiverApplicable(unconstrained, BuiltInTypes.String)
    assert harness.Resolution.IsExtensionReceiverApplicable(unconstrained, BuiltInTypes.Bool)
    assert harness.Resolution.IsExtensionReceiverApplicable(unconstrained, BuiltInTypes.Object)
    assert harness.Resolution.IsExtensionReceiverApplicable(
        unconstrained, new ArrayTypeInfo(BuiltInTypes.Int))
}

test "the type-parameter test is by NAME against this declaration only" {
    harness := ExtensionReceiverDefault()

    // The same spelling, but the declaration does not declare it: the spelling is now an ordinary
    // type reference and must be RESOLVED. Nothing in scope is called `T`, so it resolves to
    // `unknown`, which no real receiver equals — the extension is offered to nothing.
    foreign := ExtensionReceiverOn("T", ExtensionReceiverNames("U"))
    assert !harness.Resolution.IsExtensionReceiverApplicable(foreign, BuiltInTypes.Int)
    assert !harness.Resolution.IsExtensionReceiverApplicable(foreign, BuiltInTypes.String)

    // A NON-generic declaration has no type parameter list at all, and the same spelling is again
    // an ordinary reference. The null list must not be mistaken for "matches everything".
    nonGeneric := ExtensionReceiverOn("T", ExtensionReceiverNoNames())
    assert !harness.Resolution.IsExtensionReceiverApplicable(nonGeneric, BuiltInTypes.Int)

    // A generic declaration whose receiver is NOT one of its type parameters resolves normally.
    concrete := ExtensionReceiverOn("int", ExtensionReceiverNames("T"))
    assert harness.Resolution.IsExtensionReceiverApplicable(concrete, BuiltInTypes.Int)
    assert !harness.Resolution.IsExtensionReceiverApplicable(concrete, BuiltInTypes.String)
}

test "a resolved receiver matches by identity" {
    harness := ExtensionReceiverDefault()

    intReceiver := ExtensionReceiverOn("int", ExtensionReceiverNoNames())
    assert harness.Resolution.IsExtensionReceiverApplicable(intReceiver, BuiltInTypes.Int)
    assert !harness.Resolution.IsExtensionReceiverApplicable(intReceiver, BuiltInTypes.String)
    assert !harness.Resolution.IsExtensionReceiverApplicable(intReceiver, BuiltInTypes.Bool)

    stringReceiver := ExtensionReceiverOn("string", ExtensionReceiverNoNames())
    assert harness.Resolution.IsExtensionReceiverApplicable(stringReceiver, BuiltInTypes.String)
    assert !harness.Resolution.IsExtensionReceiverApplicable(stringReceiver, BuiltInTypes.Int)
}

test "a resolved receiver also matches by ASSIGNABILITY, not identity alone" {
    harness := ExtensionReceiverDefault()

    // `object` is not IDENTICAL to any of these, so an identity-only test would offer an
    // `object`-receiver extension to nothing at all. Assignability is what makes it universal.
    objectReceiver := ExtensionReceiverOn("object", ExtensionReceiverNoNames())
    assert harness.Resolution.IsExtensionReceiverApplicable(objectReceiver, BuiltInTypes.String)
    assert harness.Resolution.IsExtensionReceiverApplicable(objectReceiver, BuiltInTypes.Int)
    assert harness.Resolution.IsExtensionReceiverApplicable(
        objectReceiver, new ArrayTypeInfo(BuiltInTypes.String))

    // And the direction is receiver-accepts-target, not the reverse: a `string` receiver does not
    // accept an `object`.
    stringReceiver := ExtensionReceiverOn("string", ExtensionReceiverNoNames())
    assert !harness.Resolution.IsExtensionReceiverApplicable(stringReceiver, BuiltInTypes.Object)
}

test "an UNRESOLVABLE receiver spelling answers for `unknown` and nothing else" {
    harness := ExtensionReceiverDefault()

    // A spelling nothing in scope defines resolves to `unknown`, and `unknown` is IDENTICAL to
    // itself — so the extension is offered for an unknown receiver and for no real one. This is the
    // arm that makes the type-parameter pre-check load-bearing: without it, every generic
    // extension would land here.
    unresolvable := ExtensionReceiverOn("Unknown_Type_Name", ExtensionReceiverNoNames())
    assert harness.Resolution.IsExtensionReceiverApplicable(unresolvable, BuiltInTypes.Unknown)
    assert !harness.Resolution.IsExtensionReceiverApplicable(unresolvable, BuiltInTypes.Int)
    assert !harness.Resolution.IsExtensionReceiverApplicable(unresolvable, BuiltInTypes.String)
    assert !harness.Resolution.IsExtensionReceiverApplicable(unresolvable, BuiltInTypes.Object)

    // And the type-parameter spelling reaches the same place when the declaration does not declare
    // it — measured, not assumed.
    foreign := ExtensionReceiverOn("T", ExtensionReceiverNames("U"))
    assert harness.Resolution.IsExtensionReceiverApplicable(foreign, BuiltInTypes.Unknown)
    assert !harness.Resolution.IsExtensionReceiverApplicable(foreign, BuiltInTypes.Object)
}

func ExtensionSurfaceNamed(name: string, receiverTypeName: string): FunctionDeclaration {
    parameters := new List<Parameter>()
    parameters.Add(ExtensionReceiverParameter("self", receiverTypeName))
    return ExtensionReceiverDeclaration(name, parameters, null)
}

// The core assembly is the one reference every project has, it declares `System.MemoryExtensions`
// (a `sealed abstract` host under the `System` namespace whose members carry `[Extension]`), and it
// also declares `System.Convert` — a host that is static under the same namespace but whose members
// are NOT extensions. Both arms of the scan are therefore reachable from one loaded assembly.
func ExtensionSurfaceCoreAssembly(): Assembly {
    coreType := typeof(object)
    return coreType.get_Assembly()
}

test "one applicable source extension answers with that function's type" {
    harness := ExtensionReceiverDefault()
    harness.Declared.Add(ExtensionSurfaceNamed("Twice", "int"))

    answer := harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.Int, "Twice", "Owner")
    functionType := answer as FunctionTypeInfo
    assert functionType != null
    assert functionType.SourceName == "Twice"

    // A name nothing declares is not this extension; with no reference assemblies loaded the
    // external scan has nowhere to look, so the answer is `unknown` rather than a wrong function.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.Int, "Thrice", "Owner"))
}

test "several applicable source extensions answer as a method GROUP" {
    harness := ExtensionReceiverDefault()
    harness.Declared.Add(ExtensionSurfaceNamed("Twice", "int"))
    harness.Declared.Add(ExtensionSurfaceNamed("Twice", "object"))

    // Both accept an `int` — the second by assignability — so neither can be chosen here; overload
    // resolution picks later, and the answer must carry BOTH candidates rather than the first.
    answer := harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.Int, "Twice", "Owner")
    group := answer as NSharpMethodGroupInfo
    assert group != null
    assert NSharpMethodGroupInfoFactory.GetFunctions(group).Count == 2
}

test "a NAMED source extension that REJECTS the receiver falls through to the external scan" {
    harness := ExtensionReceiverDefault()

    // THE ARM THAT AN "IS THE NAME DECLARED?" TEST WOULD GET WRONG. `AsSpan` IS declared as a source
    // extension here, but on a receiver this target does not satisfy — so the external scan must
    // still run, exactly as it would for a name no source extension mentions at all.
    harness.Declared.Add(ExtensionSurfaceNamed("AsSpan", "bool"))
    harness.Namespaces.Add("System")
    harness.Assemblies.Add(ExtensionSurfaceCoreAssembly())

    answer := harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.String, "AsSpan", "Owner")
    assert !BuiltInTypes.IsUnknown(answer)
    assert (answer as FunctionTypeInfo) == null

    // And the fall-through is not unconditional: make the SAME name applicable and the source
    // extension wins outright, with the external candidates never consulted.
    harness.Declared.Add(ExtensionSurfaceNamed("AsSpan", "object"))
    sourceAnswer := harness.Resolution.TryResolveExtensionMethod(
        BuiltInTypes.String, "AsSpan", "Owner")
    sourceFunction := sourceAnswer as FunctionTypeInfo
    assert sourceFunction != null
    assert sourceFunction.SourceName == "AsSpan"
}

test "the containing type name is read at the CALL and never held" {
    harness := ExtensionReceiverDefault()
    harness.Declared.Add(ExtensionSurfaceNamed("Twice", "int"))

    // `_currentTypeName` is a plain mutable field that changes every time the analyzer's walk enters
    // or leaves a type. If this owner HELD it, the second answer would carry the first walk's type.
    first := harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.Int, "Twice", "Alpha")
    firstFunction := first as FunctionTypeInfo
    assert firstFunction != null
    assert firstFunction.SourceContainingType == "Alpha"

    second := harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.Int, "Twice", "Beta")
    secondFunction := second as FunctionTypeInfo
    assert secondFunction != null
    assert secondFunction.SourceContainingType == "Beta"

    third := harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.Int, "Twice", null)
    thirdFunction := third as FunctionTypeInfo
    assert thirdFunction != null
    assert thirdFunction.SourceContainingType == null
}

test "the declaration list is LIVE, not a snapshot taken at construction" {
    harness := ExtensionReceiverDefault()

    // Constructed over an EMPTY list. The analyzer clears and refills `_extensionMethods` on every
    // `Analyze`, and appends to it as the declaration walk proceeds — so an extension declared later
    // in the same file must be visible to a resolution that happens after it.
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.Int, "Twice", null))

    harness.Declared.Add(ExtensionSurfaceNamed("Twice", "int"))
    assert !BuiltInTypes.IsUnknown(
        harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.Int, "Twice", null))

    harness.Declared.Clear()
    assert BuiltInTypes.IsUnknown(
        harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.Int, "Twice", null))
}

test "the external scan finds a `[Extension]` static only under an IMPORTED namespace" {
    harness := ExtensionReceiverDefault()
    harness.Assemblies.Add(ExtensionSurfaceCoreAssembly())

    // The assembly is loaded but its namespace is not imported: nothing is a candidate.
    assert harness.Resolution.FindExternalExtensionMethods(BuiltInTypes.String, "AsSpan").Count == 0

    // The namespace list is LIVE too — importing it later makes the same scan answer.
    harness.Namespaces.Add("System")
    found := harness.Resolution.FindExternalExtensionMethods(BuiltInTypes.String, "AsSpan")
    assert found.Count > 0

    index := 0
    while index < found.Count {
        candidate := found[index]
        assert candidate.get_Name() == "AsSpan"
        assert AnalyzerOverloadFacts.HasExtensionAttribute(candidate)

        // Every host is a static class — `sealed abstract` in metadata — under the imported
        // namespace, and nothing else may declare an extension.
        host := candidate.get_DeclaringType()
        assert host != null
        assert host.get_IsSealed()
        assert host.get_IsAbstract()
        assert host.get_Namespace() == "System"
        index = index + 1
    }
}

test "a matching PUBLIC STATIC with no `[Extension]` attribute is not a candidate" {
    harness := ExtensionReceiverDefault()
    harness.Assemblies.Add(ExtensionSurfaceCoreAssembly())
    harness.Namespaces.Add("System")

    // `System.Convert.ToBoolean(string)` is public, static, on a `sealed abstract` host, under an
    // imported namespace, and its first parameter accepts a `string` — every test but the attribute
    // passes. Without the attribute test, `"x".ToBoolean()` would bind.
    assert harness.Resolution.FindExternalExtensionMethods(
        BuiltInTypes.String, "ToBoolean").Count == 0

    // The control: the same scan over a name that IS an extension answers on the same receiver.
    assert harness.Resolution.FindExternalExtensionMethods(BuiltInTypes.String, "AsSpan").Count > 0
}

test "the assembly list is LIVE, and the scan does not deduplicate or reorder" {
    harness := ExtensionReceiverDefault()
    harness.Namespaces.Add("System")

    assert harness.Resolution.FindExternalExtensionMethods(BuiltInTypes.String, "AsSpan").Count == 0

    coreAssembly := ExtensionSurfaceCoreAssembly()
    harness.Assemblies.Add(coreAssembly)
    single := harness.Resolution.FindExternalExtensionMethods(BuiltInTypes.String, "AsSpan")
    assert single.Count > 0

    // The SAME assembly twice yields each candidate twice, in assembly order — the scan does not
    // deduplicate, and the caller's method group keeps whatever order it is given.
    harness.Assemblies.Add(coreAssembly)
    doubled := harness.Resolution.FindExternalExtensionMethods(BuiltInTypes.String, "AsSpan")
    assert doubled.Count == single.Count * 2

    orderIndex := 0
    while orderIndex < single.Count {
        assert Object.ReferenceEquals(doubled[orderIndex], single[orderIndex])
        assert Object.ReferenceEquals(doubled[single.Count + orderIndex], single[orderIndex])
        orderIndex = orderIndex + 1
    }
}

// The count → shape mapping, asserted for every name rather than for a hand-picked one: none is
// `unknown`, one is a method INFO, several are a method GROUP. The names are chosen so that the
// zero arm and the many arm are both reached on any runtime; the one arm is asserted wherever the
// running framework happens to declare exactly one.
func ExtensionSurfaceProbeNames(): List<string> {
    names := new List<string>()
    names.Add("AsSpan")
    names.Add("AsMemory")
    names.Add("ToBoolean")
    names.Add("NoSuchExtensionNameAnywhere")
    return names
}

test "the external answer's SHAPE follows the candidate count exactly" {
    harness := ExtensionReceiverDefault()
    harness.Namespaces.Add("System")
    harness.Assemblies.Add(ExtensionSurfaceCoreAssembly())

    names := ExtensionSurfaceProbeNames()
    sawNone := false
    sawMany := false

    index := 0
    while index < names.Count {
        name := names[index]
        candidates := harness.Resolution.FindExternalExtensionMethods(BuiltInTypes.String, name)
        answer := harness.Resolution.TryResolveExtensionMethod(BuiltInTypes.String, name, null)

        if candidates.Count == 0 {
            assert BuiltInTypes.IsUnknown(answer)
            sawNone = true
        } else if candidates.Count == 1 {
            single := answer as ReflectionMethodInfo
            assert single != null
            assert Object.ReferenceEquals(single.Method, candidates[0])
            answerObject := single as object
            assert answerObject.ToString() == name + "(...)"
        } else {
            group := answer as ReflectionMethodGroupInfo
            assert group != null
            assert group.Methods.Length == candidates.Count
            groupObject := group as object
            assert groupObject.ToString() == name + "(...)"
            sawMany = true
        }

        index = index + 1
    }

    assert sawNone
    assert sawMany
}

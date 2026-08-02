namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for extension-receiver applicability.
//
// This predicate was `private` in Analyzer.cs, so nothing named it: whether an extension method was
// OFFERED for a receiver was pinned only indirectly, through end-to-end diagnostics on calls that
// happened to reach it. These are its first DIRECT contracts, and they go at the two properties no
// single call site reveals — that a type-parameter receiver is accepted WITHOUT being resolved, and
// that a resolved receiver matches by assignability and not only by identity.

class ExtensionReceiverHarness {
    Resolution: AnalyzerExtensionMethodResolution
    Resolver: AnalyzerTypeResolver

    constructor(resolution: AnalyzerExtensionMethodResolution, resolver: AnalyzerTypeResolver) {
        Resolution = resolution
        Resolver = resolver
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

    return new ExtensionReceiverHarness(
        new AnalyzerExtensionMethodResolution(resolver, assignability),
        resolver)
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

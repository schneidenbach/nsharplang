namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for what it means for a type to be throwable.
//
// THIS IS THE PREDICATE THREE CONSTRUCTS SHARE — a `throw` operand, an `assert throws` type and a
// `catch` clause's exception type — and it was the LAST thing the statement-level expression family
// had to ask `Analyzer.cs` for. Every arm below is either a WIDENING (the analyzer does not yet know
// what this is, so do not complain) or a real assignability answer, and the ORDER matters: the
// oblivious unwrap runs before every other test, the two well-known spellings answer before the
// scope stack is consulted, and the CLR funnel is the last door rather than the first.
//
// THE MetadataLoadContext DIMENSION IS DELIBERATE AND IS PINNED HERE. The reflected arm compares
// against the RUNTIME `System.Exception`, so a type loaded into the analyzer's own load context
// answers NO and falls through to the arms that do not depend on runtime identity. That is what
// `Analyzer.cs` did, character for character.

class ThrowHarness {
    Owner: AnalyzerThrowability
    Scopes: AnalyzerScopeStack
    Clr: AnalyzerClrTypeConversion

    constructor(
        owner: AnalyzerThrowability,
        scopes: AnalyzerScopeStack,
        clr: AnalyzerClrTypeConversion) {
        Owner = owner
        Scopes = scopes
        Clr = clr
    }
}

func ThrowHarnessNew(): ThrowHarness {
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
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    return new ThrowHarness(
        new AnalyzerThrowability(scopes, context, substitution),
        scopes,
        new AnalyzerClrTypeConversion(context, null))
}

func ThrowAsk(harness: ThrowHarness, candidate: TypeInfo): bool {
    return harness.Owner.IsThrowable(candidate, harness.Clr)
}

func ThrowClass(name: string, baseClass: TypeReference?): TypeInfo {
    declared: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        false,
        baseClass,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true)
    return declared
}

func ThrowDeclare(harness: ThrowHarness, name: string, declared: TypeInfo) {
    harness.Scopes.Peek().Types[name] = declared
}

func ThrowSimple(name: string): TypeInfo {
    named: TypeInfo = new SimpleTypeInfo(name)
    return named
}

// ── the four widenings ────────────────────────────────────────────────────

test "null and never are throwable" {
    harness := ThrowHarnessNew()

    // `throw null` is a runtime concern rather than a type error, and a `never` value cannot exist.
    assert ThrowAsk(harness, BuiltInTypes.Null)
    assert ThrowAsk(harness, BuiltInTypes.Never)
}

test "an unknown type is throwable, because it already carries its own error" {
    harness := ThrowHarnessNew()

    assert ThrowAsk(harness, BuiltInTypes.Unknown)
}

test "an external type is throwable, because the analyzer has not finished resolving it" {
    harness := ThrowHarnessNew()
    external: TypeInfo = new ExternalTypeInfo("Some.Package.Failure")

    assert ThrowAsk(harness, external)
}

test "a nullable answers for what it wraps" {
    harness := ThrowHarnessNew()
    ThrowDeclare(harness, "AppError", ThrowClass("AppError", new SimpleTypeReference("Exception", 1, 1)))
    ThrowDeclare(harness, "Widget", ThrowClass("Widget", null))
    throwable: TypeInfo = new NullableTypeInfo(ThrowSimple("AppError"))
    refused: TypeInfo = new NullableTypeInfo(ThrowSimple("Widget"))

    assert ThrowAsk(harness, throwable)
    assert !ThrowAsk(harness, refused)
}

// ── the oblivious unwrap is a LOOP, not one pass ──────────────────────────

test "nested oblivious wrappers all unwrap before anything else is asked" {
    harness := ThrowHarnessNew()
    ThrowDeclare(harness, "Widget", ThrowClass("Widget", null))
    once: TypeInfo = new ObliviousTypeInfo(ThrowSimple("Exception"))
    twice: TypeInfo = new ObliviousTypeInfo(new ObliviousTypeInfo(ThrowSimple("Exception")))
    refused: TypeInfo = new ObliviousTypeInfo(new ObliviousTypeInfo(ThrowSimple("Widget")))

    assert ThrowAsk(harness, once)
    assert ThrowAsk(harness, twice)
    assert !ThrowAsk(harness, refused)
}

// ── the two well-known spellings ──────────────────────────────────────────

test "both spellings of the exception root answer yes without any lookup" {
    harness := ThrowHarnessNew()

    assert ThrowAsk(harness, ThrowSimple("Exception"))
    assert ThrowAsk(harness, ThrowSimple("System.Exception"))
}

test "an unresolvable bare name is NOT throwable" {
    harness := ThrowHarnessNew()

    // Nothing declares it and the CLR funnel cannot name it, so the answer is no rather than a
    // silent yes — this is the arm that makes `throw 1` and `catch Widget` report at all.
    assert !ThrowAsk(harness, ThrowSimple("NothingDeclaresThis"))
}

// ── declared types, and the base-class walk ───────────────────────────────

test "a declared class with no base class is not throwable" {
    harness := ThrowHarnessNew()
    ThrowDeclare(harness, "Widget", ThrowClass("Widget", null))

    assert !ThrowAsk(harness, ThrowSimple("Widget"))
}

test "a declared class deriving from Exception is throwable" {
    harness := ThrowHarnessNew()
    ThrowDeclare(harness, "AppError", ThrowClass("AppError", new SimpleTypeReference("Exception", 1, 1)))

    assert ThrowAsk(harness, ThrowSimple("AppError"))
}

test "the base-class walk is TRANSITIVE" {
    harness := ThrowHarnessNew()
    ThrowDeclare(harness, "AppError", ThrowClass("AppError", new SimpleTypeReference("Exception", 1, 1)))
    ThrowDeclare(harness, "NotFound", ThrowClass("NotFound", new SimpleTypeReference("AppError", 1, 1)))
    ThrowDeclare(harness, "Widget", ThrowClass("Widget", null))
    ThrowDeclare(harness, "Gadget", ThrowClass("Gadget", new SimpleTypeReference("Widget", 1, 1)))

    assert ThrowAsk(harness, ThrowSimple("NotFound"))
    assert !ThrowAsk(harness, ThrowSimple("Gadget"))
}

test "a name that resolves to ITSELF does not spin" {
    harness := ThrowHarnessNew()
    selfNamed: TypeInfo = ThrowSimple("Loop")
    harness.Scopes.Peek().Types["Loop"] = selfNamed

    // The redirect guard is a reference comparison, and without it this is an infinite recursion.
    assert !ThrowAsk(harness, selfNamed)
}

// ── the reflected arm ─────────────────────────────────────────────────────

test "a reflected exception answers yes and a reflected value type answers no" {
    harness := ThrowHarnessNew()
    exception: TypeInfo = new ReflectionTypeInfo(typeof(InvalidOperationException))
    integer: TypeInfo = new ReflectionTypeInfo(typeof(int))

    assert ThrowAsk(harness, exception)
    assert !ThrowAsk(harness, integer)
}

test "the reflected root itself answers yes" {
    harness := ThrowHarnessNew()
    root: TypeInfo = new ReflectionTypeInfo(typeof(Exception))

    assert ThrowAsk(harness, root)
}

// ── everything else ───────────────────────────────────────────────────────

func ThrowStruct(): TypeInfo {
    declared: TypeInfo = new StructTypeInfo(
        "Point",
        1,
        1,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
    return declared
}

test "a struct and the primitives are not throwable" {
    harness := ThrowHarnessNew()

    assert !ThrowAsk(harness, ThrowStruct())
    assert !ThrowAsk(harness, BuiltInTypes.Int)
    assert !ThrowAsk(harness, BuiltInTypes.Bool)
}

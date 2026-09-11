namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for what a condition proves about the code it guards.
//
// THE NEGATION RULES ARE WHERE THIS GOES WRONG IF IT GOES WRONG. `x != null` and `x == null` are
// mirrors and both narrow BOTH branches; `a && b` narrows only the TRUE branch, because the
// negation of a conjunction is a disjunction and a disjunction proves nothing about either operand;
// `a || b` is the exact mirror of that. Each of the four is pinned in both directions — what it
// yields AND what it deliberately leaves empty — because an over-eager else-list is a silent
// unsoundness rather than a visible one.
//
// THE ARM SUBTRACTION IS THE ONLY PLACE A TYPE IS COMPUTED. It is assignability, not identity, so
// a test against a base type removes every derived arm; and its three collapses — none removed,
// all removed, exactly one left — are separate contracts, because each returns a different KIND of
// answer (no narrowing, `never`, and the bare arm rather than a one-armed union).
//
// INSTALLATION INTERSECTS. Two conditions can narrow the same name and the MORE SPECIFIC type wins
// regardless of order; the null fact is installed for every path but the TYPE only for a simple
// name, because a member path's declared member type is not the scope's to rewrite.
class FlowNarrowingHarness {
    Owner: AnalyzerFlowNarrowing
    Scopes: AnalyzerScopeStack
    Context: AnalyzerDeclarationContext

    constructor(
        owner: AnalyzerFlowNarrowing,
        scopes: AnalyzerScopeStack,
        context: AnalyzerDeclarationContext
    ) {
        Owner = owner
        Scopes = scopes
        Context = context
    }
}

func FlowNarrowingDefault(): FlowNarrowingHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
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

    return new FlowNarrowingHarness(
        new AnalyzerFlowNarrowing(scopes, resolver, assignability),
        scopes,
        context
    )
}

func FnName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 3, 5)
}

func FnNull(): NullLiteralExpression {
    return new NullLiteralExpression(3, 9)
}

func FnBinary(left: Expression, operatorKind: BinaryOperator, right: Expression): BinaryExpression {
    return new BinaryExpression(left, operatorKind, right, 3, 5)
}

func FnNotEqualNull(name: string): BinaryExpression {
    return FnBinary(FnName(name), BinaryOperator.NotEqual, FnNull())
}

func FnEqualNull(name: string): BinaryExpression {
    return FnBinary(FnName(name), BinaryOperator.Equal, FnNull())
}

func FnIs(target: Expression, typeName: string, variableName: string?): IsExpression {
    return new IsExpression(target, new SimpleTypeReference(typeName, 0, 0), variableName, 3, 5)
}

func FnArms(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    arms := new List<TypeInfo>()
    arms.Add(first)
    arms.Add(second)
    return arms
}

// A declared class, and a declared class WITH a base. `IsSubtypeOf` decides an inheritance chain
// and nothing else in a bare harness — `int` is not a subtype of `object` here, because that answer
// needs the CLR conversion funnel the toolset rebuild supplies — so the intersection contracts are
// written over a real hierarchy.
func FnClass(name: string): TypeInfo {
    result: TypeInfo = new ClassTypeInfo(
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
    return result
}

func FnDerivedClass(name: string, baseName: string): TypeInfo {
    result: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        false,
        new SimpleTypeReference(baseName),
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true
    )
    return result
}

func FnAliasPath(): string {
    return "/tmp/flow-narrowing.nl"
}

func FnNarrowings(): List<FlowNarrowing> {
    return new List<FlowNarrowing>()
}

func FnOneNarrowing(narrowing: FlowNarrowing): List<FlowNarrowing> {
    narrowings := FnNarrowings()
    narrowings.Add(narrowing)
    return narrowings
}

// ── the null-comparison shapes ────────────────────────────────────────────

test "`x != null` proves NOT-NULL when true and NULL when false" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(FnNotEqualNull("x"))

    assert split.Then.Count == 1
    assert split.Then[0].Path == "x"
    assert split.Then[0].NullState == NullState.NotNull
    assert split.Then[0].NarrowedType == null
    assert split.Else.Count == 1
    assert split.Else[0].NullState == NullState.Null
}
test "`x == null` is the exact mirror" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(FnEqualNull("x"))

    assert split.Then.Count == 1
    assert split.Then[0].NullState == NullState.Null
    assert split.Else.Count == 1
    assert split.Else[0].NullState == NullState.NotNull
}
test "the LITERAL may be written on either side" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(
        FnBinary(FnNull(), BinaryOperator.NotEqual, FnName("x"))
    )

    assert split.Then.Count == 1
    assert split.Then[0].Path == "x"
    assert split.Then[0].NullState == NullState.NotNull
}
test "a comparison against something that is NOT the null literal narrows nothing" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(
        FnBinary(FnName("x"), BinaryOperator.NotEqual, new IntLiteralExpression("0", 3, 9))
    )

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}
test "a null comparison against a receiver with NO stable path narrows nothing" {
    harness := FlowNarrowingDefault()
    call := new CallExpression(FnName("Get"), new List<Argument>(), null, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(call, BinaryOperator.NotEqual, FnNull()))

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}
test "a MEMBER PATH narrows its own null fact" {
    harness := FlowNarrowingDefault()
    member := new MemberAccessExpression(FnName("box"), "Value", false, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(member, BinaryOperator.NotEqual, FnNull()))

    assert split.Then.Count == 1
    assert split.Then[0].Path == "box.Value"
}
test "an operator that is neither equality nor a connective narrows nothing" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(
        FnBinary(FnName("x"), BinaryOperator.Less, new IntLiteralExpression("3", 3, 9))
    )

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}

// ── the connectives, in both directions ───────────────────────────────────

test "`a && b` unions BOTH then-lists and yields an EMPTY else-list" {
    harness := FlowNarrowingDefault()
    condition := FnBinary(FnNotEqualNull("a"), BinaryOperator.And, FnNotEqualNull("b"))

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 2
    assert split.Then[0].Path == "a"
    assert split.Then[1].Path == "b"
    assert split.Else.Count == 0
}
test "`a || b` unions BOTH else-lists and yields an EMPTY then-list" {
    harness := FlowNarrowingDefault()
    condition := FnBinary(FnEqualNull("a"), BinaryOperator.Or, FnEqualNull("b"))

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 0
    assert split.Else.Count == 2
    assert split.Else[0].Path == "a"
    assert split.Else[0].NullState == NullState.NotNull
    assert split.Else[1].Path == "b"
}
test "the connectives NEST, and the order is left then right" {
    harness := FlowNarrowingDefault()
    inner := FnBinary(FnNotEqualNull("b"), BinaryOperator.And, FnNotEqualNull("c"))
    condition := FnBinary(FnNotEqualNull("a"), BinaryOperator.And, inner)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 3
    assert split.Then[0].Path == "a"
    assert split.Then[1].Path == "b"
    assert split.Then[2].Path == "c"
}

// ── the type test ─────────────────────────────────────────────────────────

test "`x is T v` DECLARES the binding name at T and not-null" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(FnIs(FnName("x"), "int", "n"))

    assert split.Then.Count == 1
    assert split.Then[0].Path == "n"
    assert split.Then[0].NullState == NullState.NotNull
    assert BuiltInTypes.Is(split.Then[0].NarrowedType, BuiltInTypes.Int)
}
test "`x is T` with no binding narrows the TESTED PATH instead" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(FnIs(FnName("x"), "int", null))

    assert split.Then.Count == 1
    assert split.Then[0].Path == "x"
    assert BuiltInTypes.Is(split.Then[0].NarrowedType, BuiltInTypes.Int)
}
test "`x is T` over an operand with NO stable path narrows nothing" {
    harness := FlowNarrowingDefault()
    call := new CallExpression(FnName("Get"), new List<Argument>(), null, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(FnIs(call, "int", null))

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}
test "a type test over a name that is NOT an anonymous union gives the else branch nothing" {
    harness := FlowNarrowingDefault()
    harness.Scopes.Peek().Symbols["x"] = BuiltInTypes.String

    split := harness.Owner.ExtractFlowNarrowings(FnIs(FnName("x"), "int", null))

    assert split.Then.Count == 1
    assert split.Else.Count == 0
}
test "AN ANONYMOUS UNION loses the matched arm in the ELSE branch" {
    harness := FlowNarrowingDefault()
    unionType: TypeInfo = new AnonymousUnionTypeInfo(FnArms(BuiltInTypes.Int, BuiltInTypes.String))
    harness.Scopes.Peek().Symbols["x"] = unionType

    split := harness.Owner.ExtractFlowNarrowings(FnIs(FnName("x"), "int", null))

    assert split.Else.Count == 1
    assert split.Else[0].Path == "x"
    assert split.Else[0].NullState == NullState.NotNull
    // Two arms minus one leaves the bare arm, not a one-armed union.
    assert BuiltInTypes.Is(split.Else[0].NarrowedType, BuiltInTypes.String)
}
test "the arm subtraction also runs for the BINDING form" {
    harness := FlowNarrowingDefault()
    unionType: TypeInfo = new AnonymousUnionTypeInfo(FnArms(BuiltInTypes.Int, BuiltInTypes.String))
    harness.Scopes.Peek().Symbols["x"] = unionType

    split := harness.Owner.ExtractFlowNarrowings(FnIs(FnName("x"), "int", "n"))

    assert split.Then.Count == 1
    assert split.Then[0].Path == "n"
    assert split.Else.Count == 1
    assert split.Else[0].Path == "x"
}
test "a union that loses EVERY arm narrows to `never`" {
    harness := FlowNarrowingDefault()
    unionType: TypeInfo = new AnonymousUnionTypeInfo(FnArms(BuiltInTypes.Int, BuiltInTypes.Int))
    harness.Scopes.Peek().Symbols["x"] = unionType

    split := harness.Owner.ExtractFlowNarrowings(FnIs(FnName("x"), "int", null))

    assert split.Else.Count == 1
    assert BuiltInTypes.Is(split.Else[0].NarrowedType, BuiltInTypes.Never)
}
test "a union that loses NO arm gives the else branch nothing — the test told us nothing" {
    harness := FlowNarrowingDefault()
    unionType: TypeInfo = new AnonymousUnionTypeInfo(FnArms(BuiltInTypes.String, BuiltInTypes.Bool))
    harness.Scopes.Peek().Symbols["x"] = unionType

    split := harness.Owner.ExtractFlowNarrowings(FnIs(FnName("x"), "int", null))

    assert split.Then.Count == 1
    assert split.Else.Count == 0
}
test "a union with THREE arms losing one stays a union" {
    harness := FlowNarrowingDefault()
    arms := FnArms(BuiltInTypes.Int, BuiltInTypes.String)
    arms.Add(BuiltInTypes.Bool)
    unionType: TypeInfo = new AnonymousUnionTypeInfo(arms)
    harness.Scopes.Peek().Symbols["x"] = unionType

    split := harness.Owner.ExtractFlowNarrowings(FnIs(FnName("x"), "int", null))

    assert split.Else.Count == 1
    remaining := split.Else[0].NarrowedType as AnonymousUnionTypeInfo
    assert remaining != null
    assert remaining.Arms.Count == 2
}
test "a DOTTED path is never arm-subtracted, because the symbol lookup is by simple name" {
    harness := FlowNarrowingDefault()
    unionType: TypeInfo = new AnonymousUnionTypeInfo(FnArms(BuiltInTypes.Int, BuiltInTypes.String))
    harness.Scopes.Peek().Symbols["box.Value"] = unionType
    member := new MemberAccessExpression(FnName("box"), "Value", false, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(FnIs(member, "int", null))

    assert split.Then.Count == 1
    assert split.Then[0].Path == "box.Value"
    assert split.Else.Count == 0
}

// ── the HasValue shapes ───────────────────────────────────────────────────

test "`x.HasValue` proves the nullable's INNER type in the then branch" {
    harness := FlowNarrowingDefault()
    harness.Scopes.Peek().Symbols["x"] = new NullableTypeInfo(BuiltInTypes.Int)
    condition := new MemberAccessExpression(FnName("x"), "HasValue", false, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 1
    assert split.Then[0].Path == "x"
    assert split.Then[0].NullState == NullState.NotNull
    assert BuiltInTypes.Is(split.Then[0].NarrowedType, BuiltInTypes.Int)
    assert split.Else.Count == 0
}
test "`!x.HasValue` puts the SAME narrowing in the ELSE branch" {
    harness := FlowNarrowingDefault()
    harness.Scopes.Peek().Symbols["x"] = new NullableTypeInfo(BuiltInTypes.Int)
    access := new MemberAccessExpression(FnName("x"), "HasValue", false, 3, 5)
    condition := new UnaryExpression(UnaryOperator.Not, access, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 0
    assert split.Else.Count == 1
    assert split.Else[0].Path == "x"
    assert BuiltInTypes.Is(split.Else[0].NarrowedType, BuiltInTypes.Int)
}
test "HasValue on a NON-nullable symbol narrows nothing" {
    harness := FlowNarrowingDefault()
    harness.Scopes.Peek().Symbols["x"] = BuiltInTypes.Int
    condition := new MemberAccessExpression(FnName("x"), "HasValue", false, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 0
}
test "a member named something OTHER than HasValue narrows nothing" {
    harness := FlowNarrowingDefault()
    harness.Scopes.Peek().Symbols["x"] = new NullableTypeInfo(BuiltInTypes.Int)
    condition := new MemberAccessExpression(FnName("x"), "Value", false, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 0
}
test "HasValue on something that is not a bare NAME narrows nothing" {
    harness := FlowNarrowingDefault()
    inner := new MemberAccessExpression(FnName("box"), "Item", false, 3, 5)
    condition := new MemberAccessExpression(inner, "HasValue", false, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 0
}
test "a NOT over something that is not a member access narrows nothing" {
    harness := FlowNarrowingDefault()
    condition := new UnaryExpression(UnaryOperator.Not, FnName("flag"), 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}
test "a condition of no recognised shape at all narrows nothing" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(FnName("flag"))

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}

// ── installation ──────────────────────────────────────────────────────────

test "installing a narrowing writes the NULL FACT and the TYPE into the current scope" {
    harness := FlowNarrowingDefault()

    harness.Owner.ApplyNarrowingsToScope(
        FnOneNarrowing(new FlowNarrowing("x", BuiltInTypes.Int, NullState.NotNull))
    )

    assert harness.Scopes.Peek().NullStates["x"] == NullState.NotNull
    assert BuiltInTypes.Is(harness.Scopes.Peek().Symbols["x"], BuiltInTypes.Int)
}
test "a narrowing with a NULL type installs only the fact" {
    harness := FlowNarrowingDefault()

    harness.Owner.ApplyNarrowingsToScope(
        FnOneNarrowing(new FlowNarrowing("x", null, NullState.NotNull))
    )

    assert harness.Scopes.Peek().NullStates["x"] == NullState.NotNull
    assert !harness.Scopes.Peek().Symbols.ContainsKey("x")
}
test "a DOTTED path gets the fact but never a rewritten type" {
    harness := FlowNarrowingDefault()

    harness.Owner.ApplyNarrowingsToScope(
        FnOneNarrowing(new FlowNarrowing("box.Value", BuiltInTypes.Int, NullState.NotNull))
    )

    assert harness.Scopes.Peek().NullStates["box.Value"] == NullState.NotNull
    assert !harness.Scopes.Peek().Symbols.ContainsKey("box.Value")
}
test "a NULL narrowing marks the path's error-tuple results available" {
    harness := FlowNarrowingDefault()
    harness.Scopes.Peek().ErrorTupleResults["err"] = new ErrorTupleResultGuard("value", "err", 1, 1)

    harness.Owner.ApplyNarrowingsToScope(
        FnOneNarrowing(new FlowNarrowing("err", null, NullState.Null))
    )

    assert harness.Scopes.Peek().AvailableErrorTupleResults.Contains("value")
}
test "a NOT-NULL narrowing does NOT mark error-tuple results available" {
    harness := FlowNarrowingDefault()
    harness.Scopes.Peek().ErrorTupleResults["err"] = new ErrorTupleResultGuard("value", "err", 1, 1)

    harness.Owner.ApplyNarrowingsToScope(
        FnOneNarrowing(new FlowNarrowing("err", null, NullState.NotNull))
    )

    assert !harness.Scopes.Peek().AvailableErrorTupleResults.Contains("value")
}
test "installing over an EXISTING symbol keeps the MORE SPECIFIC type" {
    harness := FlowNarrowingDefault()
    animal := FnClass("Animal")
    dog := FnDerivedClass("Dog", "Animal")
    harness.Context.RegisterCanonicalType(FnAliasPath(), "Animal", animal)
    harness.Context.RegisterCanonicalType(FnAliasPath(), "Dog", dog)
    harness.Scopes.Peek().Symbols["x"] = animal

    harness.Owner.ApplyNarrowingsToScope(FnOneNarrowing(new FlowNarrowing("x", dog, NullState.NotNull)))

    assert harness.Scopes.Peek().Symbols["x"] == dog
}
test "an EXISTING type that is already more specific is KEPT, even though the narrowing came later" {
    harness := FlowNarrowingDefault()
    animal := FnClass("Animal")
    dog := FnDerivedClass("Dog", "Animal")
    harness.Context.RegisterCanonicalType(FnAliasPath(), "Animal", animal)
    harness.Context.RegisterCanonicalType(FnAliasPath(), "Dog", dog)
    harness.Scopes.Peek().Symbols["x"] = dog

    harness.Owner.ApplyNarrowingsToScope(FnOneNarrowing(new FlowNarrowing("x", animal, NullState.NotNull)))

    assert harness.Scopes.Peek().Symbols["x"] == dog
}
test "UNRELATED types take the newer one — it came from a later condition" {
    harness := FlowNarrowingDefault()
    harness.Scopes.Peek().Symbols["x"] = BuiltInTypes.String

    harness.Owner.ApplyNarrowingsToScope(
        FnOneNarrowing(new FlowNarrowing("x", BuiltInTypes.Bool, NullState.NotNull))
    )

    assert BuiltInTypes.Is(harness.Scopes.Peek().Symbols["x"], BuiltInTypes.Bool)
}
test "every narrowing in the list is installed, in order" {
    harness := FlowNarrowingDefault()
    narrowings := FnNarrowings()
    narrowings.Add(new FlowNarrowing("a", BuiltInTypes.Int, NullState.NotNull))
    narrowings.Add(new FlowNarrowing("b", null, NullState.Null))

    harness.Owner.ApplyNarrowingsToScope(narrowings)

    assert harness.Scopes.Peek().NullStates["a"] == NullState.NotNull
    assert harness.Scopes.Peek().NullStates["b"] == NullState.Null
    assert BuiltInTypes.Is(harness.Scopes.Peek().Symbols["a"], BuiltInTypes.Int)
}
test "an EMPTY narrowing list installs nothing" {
    harness := FlowNarrowingDefault()

    harness.Owner.ApplyNarrowingsToScope(FnNarrowings())

    assert harness.Scopes.Peek().NullStates.Count == 0
}
test "END TO END: `x != null` extracted and installed makes the scope say not-null" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(FnNotEqualNull("x"))
    harness.Owner.ApplyNarrowingsToScope(split.Then)

    assert harness.Scopes.Peek().NullStates["x"] == NullState.NotNull

    harness.Owner.ApplyNarrowingsToScope(split.Else)

    assert harness.Scopes.Peek().NullStates["x"] == NullState.Null
}

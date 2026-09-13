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
    Postconditions: AnalyzerNullabilityPostconditions

    constructor(
        owner: AnalyzerFlowNarrowing,
        scopes: AnalyzerScopeStack,
        context: AnalyzerDeclarationContext,
        postconditions: AnalyzerNullabilityPostconditions
    ) {
        Owner = owner
        Scopes = scopes
        Context = context
        Postconditions = postconditions
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

    postconditions := new AnalyzerNullabilityPostconditions(scopes, context)
    return new FlowNarrowingHarness(
        new AnalyzerFlowNarrowing(scopes, resolver, assignability, postconditions),
        scopes,
        context,
        postconditions
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

func FnBool(value: bool): BoolLiteralExpression {
    return new BoolLiteralExpression(value, 3, 9)
}

// A call with `value` filed as present in its TRUE branch and absent in its false one — the shape
// `Dictionary<K, V>.TryGetValue`'s own metadata produces.
func FnFiledCall(harness: FlowNarrowingHarness, name: string): CallExpression {
    return FnFileFacts(harness, new CallExpression(FnName(name), new List<Argument>(), null, 3, 5))
}

// The same call written through a `?.` guard, so the comparison's operand is LIFTED.
func FnFiledConditionalCall(harness: FlowNarrowingHarness, receiverName: string, memberName: string): CallExpression {
    callee: Expression = new MemberAccessExpression(FnName(receiverName), memberName, true, 3, 5)
    return FnFileFacts(harness, new CallExpression(callee, new List<Argument>(), null, 3, 5))
}

func FnFileFacts(harness: FlowNarrowingHarness, call: CallExpression): CallExpression {
    facts := new List<NullabilityPostcondition>()
    facts.Add(new NullabilityPostcondition("value", 1, NullState.NotNull))
    facts.Add(new NullabilityPostcondition("value", 2, NullState.MaybeNull))
    harness.Postconditions.Commit(call, facts)
    return call
}

func FnPaths(narrowings: List<FlowNarrowing>): string {
    text := ""
    index := 0
    while index < narrowings.Count {
        if index > 0 {
            text = text + ","
        }

        text = text + narrowings[index].Path
        index = index + 1
    }

    return text
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

// ── the null-conditional chain ────────────────────────────────────────────

test "`x?.M == null` proves NOTHING when true and the WHOLE CHAIN when false" {
    harness := FlowNarrowingDefault()
    chain := new MemberAccessExpression(FnName("doc"), "Text", true, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(chain, BinaryOperator.Equal, FnNull()))

    assert split.Then.Count == 0
    assert split.Else.Count == 2
    assert split.Else[0].Path == "doc"
    assert split.Else[0].NullState == NullState.NotNull
    assert split.Else[1].Path == "doc.Text"
    assert split.Else[1].NullState == NullState.NotNull
}
test "`x?.M != null` is the mirror" {
    harness := FlowNarrowingDefault()
    chain := new MemberAccessExpression(FnName("doc"), "Text", true, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(chain, BinaryOperator.NotEqual, FnNull()))

    assert split.Then.Count == 2
    assert split.Then[0].Path == "doc"
    assert split.Then[1].Path == "doc.Text"
    assert split.Else.Count == 0
}
test "EVERY conditional hop in the chain is proved, in receiver order" {
    harness := FlowNarrowingDefault()
    inner := new MemberAccessExpression(FnName("outer"), "Inner", true, 3, 5)
    chain := new MemberAccessExpression(inner, "Text", true, 3, 11)

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(chain, BinaryOperator.Equal, FnNull()))

    assert split.Else.Count == 3
    assert split.Else[0].Path == "outer"
    assert split.Else[1].Path == "outer.Inner"
    assert split.Else[2].Path == "outer.Inner.Text"
}
test "a chain whose LAST hop alone is conditional still proves its receiver" {
    harness := FlowNarrowingDefault()
    inner := new MemberAccessExpression(FnName("outer"), "Inner", false, 3, 5)
    chain := new MemberAccessExpression(inner, "Text", true, 3, 11)

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(chain, BinaryOperator.NotEqual, FnNull()))

    assert split.Then.Count == 2
    assert split.Then[0].Path == "outer.Inner"
    assert split.Then[1].Path == "outer.Inner.Text"
}
test "a conditional chain over an UNSTABLE receiver narrows nothing" {
    harness := FlowNarrowingDefault()
    call := new CallExpression(FnName("Get"), new List<Argument>(), null, 3, 5)
    chain := new MemberAccessExpression(call, "Text", true, 3, 11)

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(chain, BinaryOperator.Equal, FnNull()))

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}

// ── parentheses and negation ──────────────────────────────────────────────

test "a PARENTHESISED condition proves exactly what its inner condition proves" {
    harness := FlowNarrowingDefault()
    condition := new ParenthesizedExpression(FnNotEqualNull("x"), 3, 4)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 1
    assert split.Then[0].Path == "x"
    assert split.Then[0].NullState == NullState.NotNull
    assert split.Else.Count == 1
    assert split.Else[0].NullState == NullState.Null
}
test "an `&&` reaches a PARENTHESISED operand" {
    harness := FlowNarrowingDefault()
    inner := new ParenthesizedExpression(
        FnBinary(FnNotEqualNull("b"), BinaryOperator.And, FnNotEqualNull("c")),
        3,
        4
    )
    condition := FnBinary(FnNotEqualNull("a"), BinaryOperator.And, inner)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 3
    assert split.Then[0].Path == "a"
    assert split.Then[1].Path == "b"
    assert split.Then[2].Path == "c"
}
test "`!c` SWAPS the two lists" {
    harness := FlowNarrowingDefault()
    condition := new UnaryExpression(
        UnaryOperator.Not,
        new ParenthesizedExpression(FnNotEqualNull("x"), 3, 4),
        3,
        3
    )

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 1
    assert split.Then[0].NullState == NullState.Null
    assert split.Else.Count == 1
    assert split.Else[0].Path == "x"
    assert split.Else[0].NullState == NullState.NotNull
}
test "`!(a && b)` proves NOTHING when TRUE and BOTH operands when false" {
    harness := FlowNarrowingDefault()
    inner := FnBinary(FnNotEqualNull("a"), BinaryOperator.And, FnNotEqualNull("b"))
    condition := new UnaryExpression(UnaryOperator.Not, inner, 3, 3)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 0
    assert split.Else.Count == 2
    assert split.Else[0].Path == "a"
    assert split.Else[0].NullState == NullState.NotNull
    assert split.Else[1].Path == "b"
}
test "a unary that is NOT `!` narrows nothing" {
    harness := FlowNarrowingDefault()
    condition := new UnaryExpression(UnaryOperator.Negate, FnNotEqualNull("x"), 3, 3)

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}

// ── the one thing a CONSTANT operand changes ──────────────────────────────

test "`true && b` lets the else branch narrow by `!b`" {
    harness := FlowNarrowingDefault()
    condition := FnBinary(
        new BoolLiteralExpression(true, 3, 5),
        BinaryOperator.And,
        FnNotEqualNull("b")
    )

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 1
    assert split.Then[0].Path == "b"
    assert split.Else.Count == 1
    assert split.Else[0].Path == "b"
    assert split.Else[0].NullState == NullState.Null
}
test "`b && true` is the mirror" {
    harness := FlowNarrowingDefault()
    condition := FnBinary(
        FnNotEqualNull("b"),
        BinaryOperator.And,
        new BoolLiteralExpression(true, 3, 5)
    )

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Else.Count == 1
    assert split.Else[0].Path == "b"
    assert split.Else[0].NullState == NullState.Null
}
test "`false || b` lets the then branch narrow by `b`" {
    harness := FlowNarrowingDefault()
    condition := FnBinary(
        new BoolLiteralExpression(false, 3, 5),
        BinaryOperator.Or,
        FnNotEqualNull("b")
    )

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 1
    assert split.Then[0].Path == "b"
    assert split.Then[0].NullState == NullState.NotNull
    assert split.Else.Count == 1
}
test "a NON-constant operand leaves `&&` proving nothing when false" {
    harness := FlowNarrowingDefault()
    condition := FnBinary(FnNotEqualNull("a"), BinaryOperator.And, FnEqualNull("b"))

    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Else.Count == 0
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

// A CALL CAN PROVE SOMETHING NO TYPE SPELLS, and this writer does not work it out — it COLLECTS it.
// The call's own analysis reads the nullability postcondition attributes off the binding it chose
// and files the conditional facts against the node; a condition that IS that node hands each branch
// its own list. A call nothing was filed for proves nothing, which is the common case and the one a
// guess would get wrong.
test "a call condition yields the postconditions its own analysis filed against it" {
    harness := FlowNarrowingDefault()
    call := new CallExpression(FnName("TryGet"), new List<Argument>(), null, 3, 5)
    facts := new List<NullabilityPostcondition>()
    facts.Add(new NullabilityPostcondition("value", 1, NullState.NotNull))
    facts.Add(new NullabilityPostcondition("value", 2, NullState.MaybeNull))
    harness.Postconditions.Commit(call, facts)

    split := harness.Owner.ExtractFlowNarrowings(call)

    assert split.Then.Count == 1
    assert split.Then[0].Path == "value"
    assert split.Then[0].NullState == NullState.NotNull
    assert split.Else.Count == 1
    assert split.Else[0].NullState == NullState.MaybeNull
}

test "a call nothing was filed for proves nothing in either branch" {
    harness := FlowNarrowingDefault()
    call := new CallExpression(FnName("Unrelated"), new List<Argument>(), null, 3, 5)

    split := harness.Owner.ExtractFlowNarrowings(call)

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}

test "a negated call condition swaps the two branches the postconditions named" {
    harness := FlowNarrowingDefault()
    call := new CallExpression(FnName("TryGet"), new List<Argument>(), null, 3, 5)
    facts := new List<NullabilityPostcondition>()
    facts.Add(new NullabilityPostcondition("value", 1, NullState.NotNull))
    harness.Postconditions.Commit(call, facts)

    negated: Expression = new UnaryExpression(UnaryOperator.Not, call, 3, 5)
    split := harness.Owner.ExtractFlowNarrowings(negated)

    assert split.Then.Count == 0
    assert split.Else.Count == 1
    assert split.Else[0].NullState == NullState.NotNull
}

// CENSUS §FLOW5 — `c == true` IS `c`, AND THE OTHER THREE SPELLINGS ARE ITS NEGATION OR ITS MIRROR.
//
// A converter writes `== true` wherever the source compared a LIFTED boolean, and without this rule
// the comparison proved nothing at all — including the postconditions the call inside it had already
// established. The four spellings are pinned separately because getting one of the two `!=` forms
// backwards is a silent unsoundness rather than a visible one.
test "`call == true` proves what the call proves" {
    harness := FlowNarrowingDefault()
    call := FnFiledCall(harness, "TryGet")

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(call, BinaryOperator.Equal, FnBool(true)))

    assert split.Then.Count == 1
    assert split.Then[0].Path == "value"
    assert split.Then[0].NullState == NullState.NotNull
    assert split.Else.Count == 1
    assert split.Else[0].NullState == NullState.MaybeNull
}

test "`call == false` swaps the two branches" {
    harness := FlowNarrowingDefault()
    call := FnFiledCall(harness, "TryGet")

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(call, BinaryOperator.Equal, FnBool(false)))

    assert split.Then.Count == 1
    assert split.Then[0].NullState == NullState.MaybeNull
    assert split.Else.Count == 1
    assert split.Else[0].NullState == NullState.NotNull
}

test "`call != true` is `call == false`, and `call != false` is `call == true`" {
    harness := FlowNarrowingDefault()

    notTrue := harness.Owner.ExtractFlowNarrowings(
        FnBinary(FnFiledCall(harness, "TryGet"), BinaryOperator.NotEqual, FnBool(true))
    )
    assert notTrue.Then.Count == 1
    assert notTrue.Then[0].NullState == NullState.MaybeNull
    assert notTrue.Else.Count == 1
    assert notTrue.Else[0].NullState == NullState.NotNull

    notFalse := harness.Owner.ExtractFlowNarrowings(
        FnBinary(FnFiledCall(harness, "TryGet"), BinaryOperator.NotEqual, FnBool(false))
    )
    assert notFalse.Then.Count == 1
    assert notFalse.Then[0].NullState == NullState.NotNull
    assert notFalse.Else.Count == 1
    assert notFalse.Else[0].NullState == NullState.MaybeNull
}

test "the boolean literal may be written on either side" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(
        FnBinary(FnBool(true), BinaryOperator.Equal, FnFiledCall(harness, "TryGet"))
    )

    assert split.Then.Count == 1
    assert split.Then[0].NullState == NullState.NotNull
}

// A LIFTED OPERAND ONLY PROVES THE SIDE THE COMPARISON DECIDED. `x?.TryGet(out v) == true` holds
// ONLY when `x` was non-null AND the call answered true, so that branch carries the chain's tested
// receivers as well. Its other branch is `x is null OR the call answered false` — a disjunction, and
// a disjunction proves nothing about either side.
test "a LIFTED `== true` proves the chain's receiver as well as the call's true branch" {
    harness := FlowNarrowingDefault()
    call := FnFiledConditionalCall(harness, "map", "TryGet")

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(call, BinaryOperator.Equal, FnBool(true)))

    assert split.Then.Count == 2
    assert FnPaths(split.Then) == "value,map"
    assert split.Then[0].NullState == NullState.NotNull
    assert split.Then[1].NullState == NullState.NotNull
    assert split.Else.Count == 0
}

test "a LIFTED `!= true` proves everything on the branch where it did NOT hold" {
    harness := FlowNarrowingDefault()
    call := FnFiledConditionalCall(harness, "map", "TryGet")

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(call, BinaryOperator.NotEqual, FnBool(true)))

    assert split.Then.Count == 0
    assert FnPaths(split.Else) == "value,map"
}

test "a LIFTED `== false` decides its TRUE branch, and that branch is the call's false one" {
    harness := FlowNarrowingDefault()
    call := FnFiledConditionalCall(harness, "map", "TryGet")

    split := harness.Owner.ExtractFlowNarrowings(FnBinary(call, BinaryOperator.Equal, FnBool(false)))

    assert FnPaths(split.Then) == "value,map"
    assert split.Then[0].NullState == NullState.MaybeNull
    assert split.Then[1].NullState == NullState.NotNull
    assert split.Else.Count == 0
}

test "two boolean literals compared to each other narrow nothing" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(
        FnBinary(FnBool(true), BinaryOperator.Equal, FnBool(false))
    )

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}

test "a comparison against a NON-boolean literal keeps the null-comparison reading" {
    harness := FlowNarrowingDefault()

    split := harness.Owner.ExtractFlowNarrowings(
        FnBinary(FnName("x"), BinaryOperator.NotEqual, new IntLiteralExpression("1", 3, 9))
    )

    assert split.Then.Count == 0
    assert split.Else.Count == 0
}

test "an && whose right operand is a call carries that call's true-branch facts" {
    harness := FlowNarrowingDefault()
    call := new CallExpression(FnName("TryGet"), new List<Argument>(), null, 3, 5)
    facts := new List<NullabilityPostcondition>()
    facts.Add(new NullabilityPostcondition("value", 1, NullState.NotNull))
    harness.Postconditions.Commit(call, facts)

    condition := FnBinary(FnNotEqualNull("map"), BinaryOperator.And, call)
    split := harness.Owner.ExtractFlowNarrowings(condition)

    assert split.Then.Count == 2
    assert split.Else.Count == 0
}

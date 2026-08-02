namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the exhaustiveness DECISION.
//
// Every member under test was `private` in Analyzer.cs and every one of them REPORTS, so what was
// pinned before was the message text at the end of a whole compilation — never the decision that
// produced it. These contracts go at the decision: which of the five questions a scrutinee's type
// selects, what each question counts as coverage, and — the two facts the measurement showed the
// corpus cannot reach at all — the NULLABLE and ANONYMOUS-UNION questions, which fired ZERO times
// across all 71 corpus targets, and the nested partial-coverage HINT, which fired zero times too.
//
// EXHAUSTIVENESS IS AN AST WRITE, so every contract that expects coverage asserts
// `IsExhaustive` rather than merely "no diagnostic": a walk that silently declined to decide would
// pass the second check and fail the first.

class MatchExhaustivenessHarness {
    Exhaustiveness: AnalyzerMatchExhaustiveness
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Context: AnalyzerDeclarationContext

    constructor(
        exhaustiveness: AnalyzerMatchExhaustiveness,
        errors: List<CompilerError>,
        scopes: AnalyzerScopeStack,
        context: AnalyzerDeclarationContext) {
        Exhaustiveness = exhaustiveness
        Errors = errors
        Scopes = scopes
        Context = context
    }
}

func MatchExhaustivenessDefault(): MatchExhaustivenessHarness {
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
        new SemanticModel(),
        new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)

    return new MatchExhaustivenessHarness(
        new AnalyzerMatchExhaustiveness(diagnostics, substitution, assignability, resolver),
        errors,
        scopes,
        context)
}

func MatchArmBody(): Expression {
    return new IntLiteralExpression("0", 1, 1)
}

func MatchArm(pattern: Pattern): MatchCase {
    return new MatchCase(pattern, null, MatchArmBody())
}

func MatchGuardedArm(pattern: Pattern): MatchCase {
    return new MatchCase(pattern, new BoolLiteralExpression(true, 1, 1), MatchArmBody())
}

func MatchOf(cases: List<MatchCase>): MatchExpression {
    return new MatchExpression(new IdentifierExpression("scrutinee", 1, 1), cases, 4, 12)
}

func MatchArms1(a: MatchCase): List<MatchCase> {
    result := new List<MatchCase>()
    result.Add(a)
    return result
}

func MatchArms2(a: MatchCase, b: MatchCase): List<MatchCase> {
    result := MatchArms1(a)
    result.Add(b)
    return result
}

func MatchArms3(a: MatchCase, b: MatchCase, c: MatchCase): List<MatchCase> {
    result := MatchArms2(a, b)
    result.Add(c)
    return result
}

func MatchIdent(name: string): Pattern {
    return new IdentifierPattern(name, 1, 1)
}

func MatchCasePattern(caseName: string, properties: List<PropertyPattern>?): Pattern {
    return new UnionCasePattern(caseName, properties, 1, 1)
}

func MatchPropertyList(name: string, nested: Pattern?): List<PropertyPattern> {
    result := new List<PropertyPattern>()
    result.Add(new PropertyPattern(name, nested, null, 1, 1))
    return result
}

func MatchUnionCase(name: string): UnionCase {
    return new UnionCase(name, null, 1, 1)
}

func MatchUnionCaseWith(name: string, propertyName: string, propertyTypeName: string): UnionCase {
    properties := new List<UnionCaseProperty>()
    properties.Add(new UnionCaseProperty(propertyName, new SimpleTypeReference(propertyTypeName, 1, 1)))
    return new UnionCase(name, properties, 1, 1)
}

func MatchUnionOf(declaredName: string, cases: List<UnionCase>): UnionTypeInfo {
    return new UnionTypeInfo(new UnionDeclarationInfo(declaredName, null, cases, 1, 1))
}

func MatchCaseList2(a: UnionCase, b: UnionCase): List<UnionCase> {
    result := new List<UnionCase>()
    result.Add(a)
    result.Add(b)
    return result
}

func MatchCaseList3(a: UnionCase, b: UnionCase, c: UnionCase): List<UnionCase> {
    result := MatchCaseList2(a, b)
    result.Add(c)
    return result
}

func MatchEnumOf(declaredName: string, members: List<EnumMemberInfo>): EnumTypeInfo {
    return new EnumTypeInfo(new EnumDeclarationInfo(declaredName, members, EnumType.Int, 1, 1))
}

func MatchEnumMembers2(a: EnumMemberInfo, b: EnumMemberInfo): List<EnumMemberInfo> {
    result := new List<EnumMemberInfo>()
    result.Add(a)
    result.Add(b)
    return result
}

func MatchIntMember(name: string, value: string): EnumMemberInfo {
    return new EnumMemberInfo(name, 1, 1, EnumMemberValueKind.Integer, value)
}

func MatchStringMember(name: string, value: string): EnumMemberInfo {
    return new EnumMemberInfo(name, 1, 1, EnumMemberValueKind.String, value)
}

func MatchTypeArguments(first: TypeInfo): List<TypeInfo> {
    result := new List<TypeInfo>()
    result.Add(first)
    return result
}

func MatchTypeArguments2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    result := MatchTypeArguments(first)
    result.Add(second)
    return result
}

func MatchOnlyMessage(errors: List<CompilerError>): string {
    if errors.Count != 1 {
        return "expected exactly one report, saw " + errors.Count.ToString()
    }

    return errors[0].Message
}

test "a union covered by unguarded case arms is exhaustive and silent" {
    harness := MatchExhaustivenessDefault()
    unionType := MatchUnionOf("Shape", MatchCaseList2(MatchUnionCase("Circle"), MatchUnionCase("Square")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(MatchCasePattern("Shape.Circle", null)),
        MatchArm(MatchCasePattern("Shape.Square", null))))

    harness.Exhaustiveness.Check(matchExpression, unionType)

    assert matchExpression.IsExhaustive
    assert harness.Errors.Count == 0
}

test "a union missing one case reports it, in DECLARATION order" {
    // The missing list is produced by walking the DECLARATION, so the message names cases in the
    // order the union declares them rather than the order the arms happen to appear.
    harness := MatchExhaustivenessDefault()
    unionType := MatchUnionOf("Shape", MatchCaseList3(
        MatchUnionCase("Circle"), MatchUnionCase("Square"), MatchUnionCase("Tri")))
    matchExpression := MatchOf(MatchArms1(MatchArm(MatchCasePattern("Shape.Square", null))))

    harness.Exhaustiveness.Check(matchExpression, unionType)

    assert !matchExpression.IsExhaustive
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.NonExhaustiveMatch
    assert MatchOnlyMessage(harness.Errors) == "This match doesn't cover all cases — missing: Circle, Tri"
}

test "an unguarded wildcard makes a union exhaustive and stops the walk" {
    // The wildcard RETURNS rather than setting a flag, so the arms after it are never examined —
    // which is why a later malformed arm cannot change the verdict.
    harness := MatchExhaustivenessDefault()
    unionType := MatchUnionOf("Shape", MatchCaseList2(MatchUnionCase("Circle"), MatchUnionCase("Square")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(MatchIdent("_")),
        MatchArm(MatchCasePattern("Other.Nonsense", null))))

    harness.Exhaustiveness.Check(matchExpression, unionType)

    assert matchExpression.IsExhaustive
    assert harness.Errors.Count == 0
}

test "an undotted binding arm covers a union exactly like the wildcard" {
    harness := MatchExhaustivenessDefault()
    unionType := MatchUnionOf("Shape", MatchCaseList2(MatchUnionCase("Circle"), MatchUnionCase("Square")))
    matchExpression := MatchOf(MatchArms1(MatchArm(MatchIdent("other"))))

    harness.Exhaustiveness.Check(matchExpression, unionType)

    assert matchExpression.IsExhaustive
    assert harness.Errors.Count == 0
}

test "a GUARDED arm never covers — not even a guarded wildcard" {
    // A guard may be false at run time, so a guarded arm contributes nothing to coverage. This is
    // uniform across all five questions and is checked BEFORE the pattern is looked at.
    harness := MatchExhaustivenessDefault()
    unionType := MatchUnionOf("Shape", MatchCaseList2(MatchUnionCase("Circle"), MatchUnionCase("Square")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(MatchCasePattern("Shape.Circle", null)),
        MatchGuardedArm(MatchIdent("_"))))

    harness.Exhaustiveness.Check(matchExpression, unionType)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors) == "This match doesn't cover all cases — missing: Square"
}

test "a qualified identifier arm covers its case without a property list" {
    harness := MatchExhaustivenessDefault()
    unionType := MatchUnionOf("Shape", MatchCaseList2(MatchUnionCase("Circle"), MatchUnionCase("Square")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(MatchIdent("Shape.Circle")),
        MatchArm(MatchIdent("Shape.Square"))))

    harness.Exhaustiveness.Check(matchExpression, unionType)

    assert matchExpression.IsExhaustive
    assert harness.Errors.Count == 0
}

test "an arm qualified by a FOREIGN type covers nothing" {
    // `Other.Circle` names a case this union declares, but through the wrong qualifier. The
    // coverage walk must not credit it — the corpus never produces this shape, so only a contract
    // holds the line.
    harness := MatchExhaustivenessDefault()
    unionType := MatchUnionOf("Shape", MatchCaseList2(MatchUnionCase("Circle"), MatchUnionCase("Square")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(MatchIdent("Other.Circle")),
        MatchArm(MatchCasePattern("Shape.Square", null))))

    harness.Exhaustiveness.Check(matchExpression, unionType)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors) == "This match doesn't cover all cases — missing: Circle"
}

test "a constrained arm partially covers its case and names the missing nested arm" {
    // THE HINT PATH. `Bad { kind: Kind.Io }` does not cover `Bad`, but the walk sees that the
    // constraint ranges over a nested union and says exactly which nested arm would close it. Zero
    // corpus targets reach this; the whole behaviour rests here and on the fixture set.
    harness := MatchExhaustivenessDefault()
    kind := MatchUnionOf("Kind", MatchCaseList2(MatchUnionCase("Io"), MatchUnionCase("Parse")))
    harness.Scopes.DeclareNestedTypeIfAbsent("Kind", kind)

    outcome := MatchUnionOf("Outcome", MatchCaseList2(
        MatchUnionCase("Ok"),
        MatchUnionCaseWith("Bad", "kind", "Kind")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(MatchCasePattern("Outcome.Ok", null)),
        MatchArm(MatchCasePattern("Outcome.Bad", MatchPropertyList("kind", MatchIdent("Kind.Io"))))))

    harness.Exhaustiveness.Check(matchExpression, outcome)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors)
        == "This match doesn't cover all cases — partially covered: Bad (missing nested arm: Outcome.Bad { kind: Kind.Parse }). add 'Outcome.Bad { kind: Kind.Parse }', an unconstrained 'Outcome.Bad' arm, or a wildcard '_' arm."
}

test "constrained arms that between them cover every nested case DO cover the outer case" {
    // Two constrained arms are exhaustive over the nested union, so the outer case is covered
    // outright — the one shape in which a case with no total arm is still not missing.
    harness := MatchExhaustivenessDefault()
    kind := MatchUnionOf("Kind", MatchCaseList2(MatchUnionCase("Io"), MatchUnionCase("Parse")))
    harness.Scopes.DeclareNestedTypeIfAbsent("Kind", kind)

    outcome := MatchUnionOf("Outcome", MatchCaseList2(
        MatchUnionCase("Ok"),
        MatchUnionCaseWith("Bad", "kind", "Kind")))
    matchExpression := MatchOf(MatchArms3(
        MatchArm(MatchCasePattern("Outcome.Ok", null)),
        MatchArm(MatchCasePattern("Outcome.Bad", MatchPropertyList("kind", MatchIdent("Kind.Io")))),
        MatchArm(MatchCasePattern("Outcome.Bad", MatchPropertyList("kind", MatchIdent("Kind.Parse"))))))

    harness.Exhaustiveness.Check(matchExpression, outcome)

    assert matchExpression.IsExhaustive
    assert harness.Errors.Count == 0
}

test "a never-covered case and a partially covered one compose ONE message, missing first" {
    harness := MatchExhaustivenessDefault()
    kind := MatchUnionOf("Kind", MatchCaseList2(MatchUnionCase("Io"), MatchUnionCase("Parse")))
    harness.Scopes.DeclareNestedTypeIfAbsent("Kind", kind)

    outcome := MatchUnionOf("Outcome", MatchCaseList3(
        MatchUnionCase("Ok"),
        MatchUnionCaseWith("Bad", "kind", "Kind"),
        MatchUnionCase("Skipped")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(MatchCasePattern("Outcome.Ok", null)),
        MatchArm(MatchCasePattern("Outcome.Bad", MatchPropertyList("kind", MatchIdent("Kind.Io"))))))

    harness.Exhaustiveness.Check(matchExpression, outcome)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors)
        == "This match doesn't cover all cases — missing: Skipped; partially covered: Bad (missing nested arm: Outcome.Bad { kind: Kind.Parse }). add 'Outcome.Bad { kind: Kind.Parse }', an unconstrained 'Outcome.Bad' arm, or a wildcard '_' arm."
}

test "a total arm anywhere in the group settles the case, whatever the constrained ones say" {
    harness := MatchExhaustivenessDefault()
    kind := MatchUnionOf("Kind", MatchCaseList2(MatchUnionCase("Io"), MatchUnionCase("Parse")))
    harness.Scopes.DeclareNestedTypeIfAbsent("Kind", kind)

    outcome := MatchUnionOf("Outcome", MatchCaseList2(
        MatchUnionCase("Ok"),
        MatchUnionCaseWith("Bad", "kind", "Kind")))
    matchExpression := MatchOf(MatchArms3(
        MatchArm(MatchCasePattern("Outcome.Ok", null)),
        MatchArm(MatchCasePattern("Outcome.Bad", MatchPropertyList("kind", MatchIdent("Kind.Io")))),
        MatchArm(MatchCasePattern("Outcome.Bad", MatchPropertyList("kind", MatchIdent("k"))))))

    harness.Exhaustiveness.Check(matchExpression, outcome)

    assert matchExpression.IsExhaustive
    assert harness.Errors.Count == 0
}

test "a GENERIC union instantiation resolves to its definition and is asked the union question" {
    // A closed `Box<int>` is a GenericTypeInfo, not a UnionTypeInfo, so the dispatch reaches it only
    // through the definition lookup — and the substitution it produces is what lets nested case
    // property types close.
    harness := MatchExhaustivenessDefault()
    definition := MatchUnionOf("Box", MatchCaseList2(MatchUnionCase("Full"), MatchUnionCase("Empty")))
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter("T"))
    generic := new GenericTypeInfo(
        "Box",
        MatchTypeArguments(BuiltInTypes.Int),
        new UnionTypeInfo(new UnionDeclarationInfo(
            "Box", parameters, MatchCaseList2(MatchUnionCase("Full"), MatchUnionCase("Empty")), 1, 1)))

    matchExpression := MatchOf(MatchArms1(MatchArm(MatchCasePattern("Box.Full", null))))

    harness.Exhaustiveness.Check(matchExpression, generic)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors) == "This match doesn't cover all cases — missing: Empty"
}

test "a generic instantiation whose ARGUMENT COUNT disagrees is not a union at all" {
    // A definition with one parameter and an instantiation with two is a mismatch, and the answer is
    // "not a union" rather than a partially-bound one — so the match falls through to the
    // catch-all question instead of reporting missing cases.
    harness := MatchExhaustivenessDefault()
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter("T"))
    generic := new GenericTypeInfo(
        "Box",
        MatchTypeArguments2(BuiltInTypes.Int, BuiltInTypes.String),
        new UnionTypeInfo(new UnionDeclarationInfo(
            "Box", parameters, MatchCaseList2(MatchUnionCase("Full"), MatchUnionCase("Empty")), 1, 1)))

    matchExpression := MatchOf(MatchArms1(MatchArm(MatchIdent("anything"))))

    harness.Exhaustiveness.Check(matchExpression, generic)

    assert matchExpression.IsExhaustive
    assert harness.Errors.Count == 0
}

test "an enum is covered by qualified member names and reports the rest in declaration order" {
    harness := MatchExhaustivenessDefault()
    enumType := MatchEnumOf("Status", MatchEnumMembers2(
        MatchIntMember("Pending", "0"), MatchIntMember("Active", "1")))
    matchExpression := MatchOf(MatchArms1(MatchArm(MatchIdent("Status.Active"))))

    harness.Exhaustiveness.Check(matchExpression, enumType)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors)
        == "This match doesn't cover all enum members — missing: Pending"
}

test "an enum member qualified by a FOREIGN type covers nothing" {
    // The enum question compares the qualifier to the DECLARED NAME exactly — unlike the union
    // question's three-way lenient match. The asymmetry is deliberate and this pins it.
    harness := MatchExhaustivenessDefault()
    enumType := MatchEnumOf("Status", MatchEnumMembers2(
        MatchIntMember("Pending", "0"), MatchIntMember("Active", "1")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(MatchIdent("Status.Pending")),
        MatchArm(MatchIdent("Other.Active"))))

    harness.Exhaustiveness.Check(matchExpression, enumType)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors)
        == "This match doesn't cover all enum members — missing: Active"
}

test "an enum is covered by LITERALS in its declared value kind, and only that kind" {
    // An int-valued member is covered by an int literal equal to its value; a string literal of the
    // same text is a different kind and covers nothing.
    harness := MatchExhaustivenessDefault()
    enumType := MatchEnumOf("Status", MatchEnumMembers2(
        MatchIntMember("Pending", "0"), MatchIntMember("Active", "1")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(new LiteralPattern(new IntLiteralExpression("0", 1, 1), 1, 1)),
        MatchArm(new LiteralPattern(new StringLiteralExpression("1", 1, 1), 1, 1))))

    harness.Exhaustiveness.Check(matchExpression, enumType)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors)
        == "This match doesn't cover all enum members — missing: Active"
}

test "a STRING enum is covered by string literals equal to its declared text" {
    harness := MatchExhaustivenessDefault()
    enumType := MatchEnumOf("Status", MatchEnumMembers2(
        MatchStringMember("Pending", "pending"), MatchStringMember("Active", "active")))
    matchExpression := MatchOf(MatchArms2(
        MatchArm(new LiteralPattern(new StringLiteralExpression("pending", 1, 1), 1, 1)),
        MatchArm(new LiteralPattern(new StringLiteralExpression("active", 1, 1), 1, 1))))

    harness.Exhaustiveness.Check(matchExpression, enumType)

    assert matchExpression.IsExhaustive
    assert harness.Errors.Count == 0
}

test "an enum catch-all binding covers everything, an enum wildcard too" {
    harness := MatchExhaustivenessDefault()
    enumType := MatchEnumOf("Status", MatchEnumMembers2(
        MatchIntMember("Pending", "0"), MatchIntMember("Active", "1")))

    binding := MatchOf(MatchArms1(MatchArm(MatchIdent("other"))))
    harness.Exhaustiveness.Check(binding, enumType)
    assert binding.IsExhaustive

    wildcard := MatchOf(MatchArms1(MatchArm(MatchIdent("_"))))
    harness.Exhaustiveness.Check(wildcard, enumType)
    assert wildcard.IsExhaustive

    assert harness.Errors.Count == 0
}

test "a NULLABLE match needs both the absent and the present arm — the corpus reaches neither" {
    // Zero of the 71 corpus targets ever asked this question. All three missing shapes are pinned
    // here, and the message names the INNER type for the present half.
    harness := MatchExhaustivenessDefault()
    nullableType := new NullableTypeInfo(BuiltInTypes.String)

    presentOnly := MatchOf(MatchArms1(MatchArm(MatchIdent("value"))))
    harness.Exhaustiveness.Check(presentOnly, nullableType)
    assert !presentOnly.IsExhaustive
    assert harness.Errors[0].Message
        == "This nullable match doesn't cover null — handle both 'null' and a non-null value arm"

    nullOnly := MatchOf(MatchArms1(
        MatchArm(new LiteralPattern(new NullLiteralExpression(1, 1), 1, 1))))
    harness.Exhaustiveness.Check(nullOnly, nullableType)
    assert !nullOnly.IsExhaustive
    assert harness.Errors[1].Message
        == "This nullable match doesn't cover present string — handle both 'null' and a non-null value arm"

    neither := MatchOf(MatchArms1(
        MatchArm(new LiteralPattern(new StringLiteralExpression("x", 1, 1), 1, 1))))
    harness.Exhaustiveness.Check(neither, nullableType)
    assert !neither.IsExhaustive
    assert harness.Errors[2].Message
        == "This nullable match doesn't cover null and present string — handle both 'null' and a non-null value arm"

    assert harness.Errors.Count == 3
}

test "the PRESENT half of a nullable is covered by four pattern kinds, not only a binding" {
    // A type test, an object pattern, a positional pattern and a list pattern all mean "there is a
    // value here", so any of them pairs with a `null` arm to make the match exhaustive.
    harness := MatchExhaustivenessDefault()
    nullableType := new NullableTypeInfo(BuiltInTypes.String)
    nullArm := MatchArm(new LiteralPattern(new NullLiteralExpression(1, 1), 1, 1))

    typeTest := MatchOf(MatchArms2(nullArm,
        MatchArm(new TypePattern(new SimpleTypeReference("string", 1, 1), "s", 1, 1))))
    harness.Exhaustiveness.Check(typeTest, nullableType)
    assert typeTest.IsExhaustive

    objectShape := MatchOf(MatchArms2(nullArm,
        MatchArm(new ObjectPattern(new List<PropertyPattern>(), 1, 1))))
    harness.Exhaustiveness.Check(objectShape, nullableType)
    assert objectShape.IsExhaustive

    positional := MatchOf(MatchArms2(nullArm,
        MatchArm(new PositionalPattern(new List<Pattern>(), 1, 1))))
    harness.Exhaustiveness.Check(positional, nullableType)
    assert positional.IsExhaustive

    listShape := MatchOf(MatchArms2(nullArm,
        MatchArm(new ListPattern(new List<Pattern>(), 1, 1))))
    harness.Exhaustiveness.Check(listShape, nullableType)
    assert listShape.IsExhaustive

    assert harness.Errors.Count == 0
}

test "a DOTTED identifier covers neither half of a nullable" {
    // In the nullable question a dotted identifier is a qualified name, not a binding, so it is not
    // the present half — and it is not `_`, so it is not both halves either.
    harness := MatchExhaustivenessDefault()
    nullableType := new NullableTypeInfo(BuiltInTypes.String)
    matchExpression := MatchOf(MatchArms2(
        MatchArm(new LiteralPattern(new NullLiteralExpression(1, 1), 1, 1)),
        MatchArm(MatchIdent("Status.Active"))))

    harness.Exhaustiveness.Check(matchExpression, nullableType)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors)
        == "This nullable match doesn't cover present string — handle both 'null' and a non-null value arm"
}

test "an ANONYMOUS UNION is covered by ASSIGNABILITY, so one pattern can cover several arms" {
    // The other question the corpus never asks. `object` is assignable-from every arm, so a single
    // type pattern covers a two-arm union — a name-matched walk could not produce that.
    harness := MatchExhaustivenessDefault()
    arms := new List<TypeInfo>()
    arms.Add(BuiltInTypes.String)
    arms.Add(BuiltInTypes.Int)
    unionType := new AnonymousUnionTypeInfo(arms)

    matchExpression := MatchOf(MatchArms1(
        MatchArm(new TypePattern(new SimpleTypeReference("object", 1, 1), "o", 1, 1))))

    harness.Exhaustiveness.Check(matchExpression, unionType)

    assert matchExpression.IsExhaustive
    assert harness.Errors.Count == 0
}

test "an anonymous union names its UNCOVERED arms, in arm order" {
    harness := MatchExhaustivenessDefault()
    arms := new List<TypeInfo>()
    arms.Add(BuiltInTypes.Int)
    arms.Add(BuiltInTypes.String)
    unionType := new AnonymousUnionTypeInfo(arms)

    matchExpression := MatchOf(MatchArms1(
        MatchArm(new TypePattern(new SimpleTypeReference("int", 1, 1), "i", 1, 1))))

    harness.Exhaustiveness.Check(matchExpression, unionType)

    assert !matchExpression.IsExhaustive
    assert MatchOnlyMessage(harness.Errors)
        == "This match doesn't cover all anonymous union arms — missing: string"
}

test "an anonymous union's catch-all binding covers it, and a guarded type test does not" {
    harness := MatchExhaustivenessDefault()
    arms := new List<TypeInfo>()
    arms.Add(BuiltInTypes.Int)
    arms.Add(BuiltInTypes.String)

    covered := MatchOf(MatchArms1(MatchArm(MatchIdent("anything"))))
    harness.Exhaustiveness.Check(covered, new AnonymousUnionTypeInfo(arms))
    assert covered.IsExhaustive
    assert harness.Errors.Count == 0

    guarded := MatchOf(MatchArms2(
        MatchArm(new TypePattern(new SimpleTypeReference("int", 1, 1), "i", 1, 1)),
        MatchGuardedArm(new TypePattern(new SimpleTypeReference("string", 1, 1), "s", 1, 1))))
    harness.Exhaustiveness.Check(guarded, new AnonymousUnionTypeInfo(arms))
    assert !guarded.IsExhaustive
    assert harness.Errors.Count == 1
}

test "a scrutinee with no closed alternative set is exhaustive only through a catch-all" {
    // The fifth question. There is nothing to enumerate, so the walk looks for a catch-all and
    // NEVER reports — an `int` match with no wildcard is simply not marked exhaustive.
    harness := MatchExhaustivenessDefault()

    withCatchAll := MatchOf(MatchArms2(
        MatchArm(new LiteralPattern(new IntLiteralExpression("1", 1, 1), 1, 1)),
        MatchArm(MatchIdent("rest"))))
    harness.Exhaustiveness.Check(withCatchAll, BuiltInTypes.Int)
    assert withCatchAll.IsExhaustive

    without := MatchOf(MatchArms1(
        MatchArm(new LiteralPattern(new IntLiteralExpression("1", 1, 1), 1, 1))))
    harness.Exhaustiveness.Check(without, BuiltInTypes.Int)
    assert !without.IsExhaustive

    guardedOnly := MatchOf(MatchArms1(MatchGuardedArm(MatchIdent("_"))))
    harness.Exhaustiveness.Check(guardedOnly, BuiltInTypes.Int)
    assert !guardedOnly.IsExhaustive

    assert harness.Errors.Count == 0
}

test "the declared-union resolution answers a bare union under NO substitution" {
    harness := MatchExhaustivenessDefault()
    unionType := MatchUnionOf("Shape", MatchCaseList2(MatchUnionCase("Circle"), MatchUnionCase("Square")))

    substitution: Dictionary<string, TypeInfo>? = null
    resolved := harness.Exhaustiveness.ResolveDeclaredUnionType(unionType, out substitution)

    assert resolved != null
    assert resolved.Declaration.Name == "Shape"
    assert substitution == null
}

test "the declared-union resolution binds a generic instantiation's arguments by parameter name" {
    // The substitution is what a nested case property type is resolved under, so its KEYS must be
    // the definition's parameter names and its values the instantiation's arguments, in order.
    harness := MatchExhaustivenessDefault()
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter("T"))
    generic := new GenericTypeInfo(
        "Box",
        MatchTypeArguments(BuiltInTypes.Int),
        new UnionTypeInfo(new UnionDeclarationInfo(
            "Box", parameters, MatchCaseList2(MatchUnionCase("Full"), MatchUnionCase("Empty")), 1, 1)))

    substitution: Dictionary<string, TypeInfo>? = null
    resolved := harness.Exhaustiveness.ResolveDeclaredUnionType(generic, out substitution)

    assert resolved != null
    assert resolved.Declaration.Name == "Box"
    assert substitution != null
    assert substitution.Count == 1
    bound: TypeInfo = BuiltInTypes.Unknown
    assert substitution.TryGetValue("T", out bound)
    assert BuiltInTypes.Is(bound, BuiltInTypes.Int)
}

test "a non-union type resolves to no declared union" {
    harness := MatchExhaustivenessDefault()
    substitution: Dictionary<string, TypeInfo>? = null
    assert harness.Exhaustiveness.ResolveDeclaredUnionType(BuiltInTypes.Int, out substitution) == null
    assert substitution == null
}

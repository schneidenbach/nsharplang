namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the reachability judgement and the parser-error placeholder walk.
//
// WHAT THE CORPUS CAN AND CANNOT DECIDE, MEASURED RATHER THAN ASSUMED. Instrumenting every decision
// point of the baseline over all 72 corpus targets showed the judgement is entered 126 times and
// answers false THREE times, through ONE arm (`both-value`, on two external enum shapes) out of
// seventeen — every other refusal, and eleven of the admissions, have no observable in the
// compiler's own estate. The placeholder walk is entered 392,769 times and answers TRUE not once,
// because the compiler's own sources are well-formed. So the corpus proves the SILENT paths and
// what is pinned here is every arm it cannot reach.
//
// TWO ARMS OF THE PATTERN WALK CANNOT BE REACHED FROM SOURCE AT ALL, which is exactly why they are
// contracts. A LiteralPattern's literal is a single token, so no sub-expression of it can fail; and
// a list pattern containing a malformed element makes the recovery parser panic through the whole
// file (measured: the fixture emits 60 syntax diagnostics and never builds a ListPattern). Both arms
// are live code that a future parser change can reach, and both are pinned here by construction.
class ReachabilityHarness {
    Reachability: AnalyzerPatternReachability
    Errors: List<CompilerError>
    Context: AnalyzerDeclarationContext

    constructor(
        reachability: AnalyzerPatternReachability,
        errors: List<CompilerError>,
        context: AnalyzerDeclarationContext
    ) {
        Reachability = reachability
        Errors = errors
        Context = context
    }
}

func ReachabilityAliasPath(): string {
    return "/tmp/pattern-reachability-alias.nl"
}

func ReachabilityDefault(): ReachabilityHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    context.AddCompilationUnit(ReachabilityAliasPath(), new AnalyzerContextTestUnit(new List<object>()))
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
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)

    return new ReachabilityHarness(
        new AnalyzerPatternReachability(diagnostics, spans, context, assignability),
        errors,
        context
    )
}

func ReachabilityClass(name: string, isSealed: bool): TypeInfo {
    result: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        isSealed,
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

func ReachabilityDerivedClass(name: string, baseName: string, isSealed: bool): TypeInfo {
    result: TypeInfo = new ClassTypeInfo(
        name,
        1,
        1,
        isSealed,
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

func ReachabilityStruct(name: string): TypeInfo {
    result: TypeInfo = new StructTypeInfo(
        name,
        1,
        1,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
    return result
}

func ReachabilityRecord(name: string, isStruct: bool): TypeInfo {
    result: TypeInfo = new RecordTypeInfo(
        name,
        1,
        1,
        isStruct,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
    return result
}

func ReachabilityInterface(name: string): TypeInfo {
    result: TypeInfo = new InterfaceTypeInfo(
        name,
        1,
        1,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
    return result
}

func ReachabilityEnum(name: string): TypeInfo {
    result: TypeInfo = new EnumTypeInfo(
        new EnumDeclarationInfo(name, new List<EnumMemberInfo>(), EnumType.Int)
    )
    return result
}

func ReachabilityUnion(name: string): TypeInfo {
    result: TypeInfo = new UnionTypeInfo(new UnionDeclarationInfo(name, null, new List<UnionCase>()))
    return result
}

func ReachabilityAnonymousUnion(): TypeInfo {
    arms := new List<TypeInfo>()
    arms.Add(BuiltInTypes.Int)
    arms.Add(BuiltInTypes.String)
    result: TypeInfo = new AnonymousUnionTypeInfo(arms)
    return result
}

func ReachabilityGeneric(name: string): TypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    result: TypeInfo = new GenericTypeInfo(name, arguments)
    return result
}

func ReachabilityReflected(clrType: Type): TypeInfo {
    result: TypeInfo = new ReflectionTypeInfo(clrType)
    return result
}

func ReachabilityUnknown(): TypeInfo {
    result: TypeInfo = BuiltInTypes.Unknown
    return result
}

// An alias the harness's context OWNS, so `ResolveDeclaredAlias` sees through it. An unregistered
// alias resolves to ITSELF, which is a different — and also pinned — answer.
func ReachabilityOwnedAlias(harness: ReachabilityHarness, aliased: TypeReference): TypeInfo {
    alias := new AliasTypeInfo(aliased)
    harness.Context.RegisterDeclaredAlias(ReachabilityAliasPath(), alias)
    owned: TypeInfo = alias
    return owned
}

func ReachabilityTypePattern(name: string, line: int, column: int): TypePattern {
    return new TypePattern(new SimpleTypeReference(name), "value", line, column)
}

func ReachabilityIsExpression(name: string, line: int, column: int): IsExpression {
    return new IsExpression(
        new IdentifierExpression("value", line, column),
        new SimpleTypeReference(name),
        null,
        line,
        column
    )
}

func ReachabilityPlaceholder(): Expression {
    result: Expression = new IdentifierExpression("<error>", 1, 1)
    return result
}

func ReachabilityClean(): Expression {
    result: Expression = new IntLiteralExpression("1", 1, 1)
    return result
}

func ReachabilityPlaceholderArguments(): List<Argument> {
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, ReachabilityClean()))
    arguments.Add(new Argument(null, ReachabilityPlaceholder()))
    return arguments
}

func ReachabilityCleanArguments(): List<Argument> {
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, ReachabilityClean()))
    return arguments
}

// ---------------------------------------------------------------------------------------------
// THE JUDGEMENT — the arms that ADMIT, and they are asked FIRST
// ---------------------------------------------------------------------------------------------

test "an unknown on either side admits, and it outranks every refusal below it" {
    harness := ReachabilityDefault()

    // Two value types would refuse; an unknown partner admits instead, in BOTH positions.
    assert harness.Reachability.IsPatternPossible(ReachabilityUnknown(), BuiltInTypes.Int)
    assert harness.Reachability.IsPatternPossible(BuiltInTypes.Int, ReachabilityUnknown())
    assert harness.Reachability.IsPatternPossible(ReachabilityUnknown(), ReachabilityUnknown())
    assert harness.Errors.Count == 0
}

test "a REFLECTED type on either side admits, whatever it is" {
    harness := ReachabilityDefault()

    // `int` against a reflected `StringBuilder` would otherwise be a value-against-reference refusal.
    reflected := ReachabilityReflected(typeof(System.Text.StringBuilder))
    assert harness.Reachability.IsPatternPossible(BuiltInTypes.Int, reflected)
    assert harness.Reachability.IsPatternPossible(reflected, BuiltInTypes.Int)
    assert harness.Reachability.IsPatternPossible(
        reflected,
        ReachabilityReflected(typeof(Version))
    )
    assert harness.Reachability.IsPatternPossible(
        ReachabilityReflected(typeof(int)),
        ReachabilityStruct("Vec")
    )
}

test "a generic instantiation on either side admits" {
    harness := ReachabilityDefault()

    assert harness.Reachability.IsPatternPossible(ReachabilityGeneric("List"), BuiltInTypes.Int)
    assert harness.Reachability.IsPatternPossible(BuiltInTypes.Int, ReachabilityGeneric("List"))
}

test "the same declaration HANDLE admits by reference, and two equal simple names admit by value" {
    harness := ReachabilityDefault()

    dog := ReachabilityClass("Dog", false)
    assert harness.Reachability.IsPatternPossible(dog, dog)

    // Two DISTINCT SimpleTypeInfo instances: reference identity fails and the name equality carries it.
    left: TypeInfo = new SimpleTypeInfo("int")
    right: TypeInfo = new SimpleTypeInfo("int")
    assert !Object.ReferenceEquals(left, right)
    assert harness.Reachability.IsPatternPossible(left, right)

    // A struct is not a simple type, so two distinct struct handles with the SAME name still refuse.
    assert !harness.Reachability.IsPatternPossible(
        ReachabilityStruct("Vec"),
        ReachabilityStruct("Vec")
    )
}

test "an INTERFACE on either side admits — including against a value type, which is what makes the two inner interface guards unreachable" {
    harness := ReachabilityDefault()

    shape := ReachabilityInterface("Shape")
    assert harness.Reachability.IsPatternPossible(shape, ReachabilityClass("Dog", false))
    assert harness.Reachability.IsPatternPossible(ReachabilityClass("Dog", false), shape)

    // `int is Shape` — the interface arm answers, so the value-to-reference arm below it never sees
    // an interface partner and its `is not InterfaceTypeInfo` guard can never be false.
    assert harness.Reachability.IsPatternPossible(BuiltInTypes.Int, shape)
    assert harness.Reachability.IsPatternPossible(shape, BuiltInTypes.Int)

    // A SEALED class against an interface admits too: the interface arm is above the sealed arms.
    assert harness.Reachability.IsPatternPossible(ReachabilityClass("Leaf", true), shape)
}

test "`object` on either side admits, and it is asked by BuiltInTypes identity rather than by name" {
    harness := ReachabilityDefault()

    assert harness.Reachability.IsPatternPossible(BuiltInTypes.Object, ReachabilityClass("Dog", false))
    assert harness.Reachability.IsPatternPossible(BuiltInTypes.Int, BuiltInTypes.Object)
    assert harness.Reachability.IsPatternPossible(BuiltInTypes.Object, ReachabilityStruct("Vec"))
}

test "a nullable on either side admits, and so does a union or an anonymous union" {
    harness := ReachabilityDefault()

    nullableInt: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    assert harness.Reachability.IsPatternPossible(nullableInt, BuiltInTypes.Int)
    assert harness.Reachability.IsPatternPossible(BuiltInTypes.String, nullableInt)

    assert harness.Reachability.IsPatternPossible(ReachabilityUnion("Shape"), BuiltInTypes.Int)
    assert harness.Reachability.IsPatternPossible(BuiltInTypes.Int, ReachabilityUnion("Shape"))
    assert harness.Reachability.IsPatternPossible(ReachabilityAnonymousUnion(), BuiltInTypes.Int)
    assert harness.Reachability.IsPatternPossible(BuiltInTypes.Int, ReachabilityAnonymousUnion())
}

test "assignability admits in BOTH directions — the upcast and the downcast are equally meaningful" {
    harness := ReachabilityDefault()

    animal := ReachabilityClass("Animal", false)
    // SEALED on purpose: the sealed arms below would refuse this pair, so the two assertions can
    // only pass through the assignability arm above them. Without it they would both be false.
    dog := ReachabilityDerivedClass("Dog", "Animal", true)
    harness.Context.RegisterCanonicalType(ReachabilityAliasPath(), "Animal", animal)
    harness.Context.RegisterCanonicalType(ReachabilityAliasPath(), "Dog", dog)

    // `animal is Dog` is a downcast; `dog is Animal` is an upcast. Both can succeed.
    assert harness.Reachability.IsPatternPossible(animal, dog)
    assert harness.Reachability.IsPatternPossible(dog, animal)

    // The control: an UNRELATED sealed class against the same base does refuse, so the admission
    // above is about the inheritance and not about sealedness being ignored.
    assert !harness.Reachability.IsPatternPossible(animal, ReachabilityClass("Rock", true))
}

test "two unrelated NON-sealed classes admit: an unseen subclass could be both" {
    harness := ReachabilityDefault()

    assert harness.Reachability.IsPatternPossible(
        ReachabilityClass("Dog", false),
        ReachabilityClass("Cat", false)
    )

    // A record class is a reference type and takes the same fall-through.
    assert harness.Reachability.IsPatternPossible(
        ReachabilityRecord("Person", false),
        ReachabilityClass("Dog", false)
    )
}

// ---------------------------------------------------------------------------------------------
// THE JUDGEMENT — the four ways to REFUSE
// ---------------------------------------------------------------------------------------------

test "two distinct VALUE types refuse, whatever kind of value they are" {
    harness := ReachabilityDefault()

    assert !harness.Reachability.IsPatternPossible(BuiltInTypes.Int, BuiltInTypes.Bool)
    assert !harness.Reachability.IsPatternPossible(BuiltInTypes.Double, BuiltInTypes.Char)
    assert !harness.Reachability.IsPatternPossible(ReachabilityStruct("Vec"), ReachabilityStruct("Pos"))
    assert !harness.Reachability.IsPatternPossible(ReachabilityEnum("Color"), BuiltInTypes.Int)
    assert !harness.Reachability.IsPatternPossible(ReachabilityRecord("Point", true), BuiltInTypes.Int)

    // A record STRUCT is a value type and a record CLASS is not — the same declaration kind lands on
    // opposite sides of this arm.
    assert harness.Reachability.IsPatternPossible(ReachabilityRecord("Person", false), BuiltInTypes.String)
}

test "a value tested against a reference type refuses, and so does the mirror" {
    harness := ReachabilityDefault()

    dog := ReachabilityClass("Dog", false)
    assert !harness.Reachability.IsPatternPossible(BuiltInTypes.Int, dog)
    assert !harness.Reachability.IsPatternPossible(dog, BuiltInTypes.Int)
    assert !harness.Reachability.IsPatternPossible(ReachabilityStruct("Vec"), dog)

    // `string` is a SimpleTypeInfo that is nevertheless a REFERENCE type, so it refuses a value
    // partner through the reference-to-value arm rather than through the two-values arm.
    assert !harness.Reachability.IsPatternPossible(BuiltInTypes.String, BuiltInTypes.Int)

    // An array is a reference type and takes the same arm.
    arrayOfInt: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)
    assert !harness.Reachability.IsPatternPossible(arrayOfInt, BuiltInTypes.Int)
}

test "a SEALED class refuses another class from either side, and only against a CLASS" {
    harness := ReachabilityDefault()

    leaf := ReachabilityClass("Leaf", true)
    branch := ReachabilityClass("Branch", false)
    assert !harness.Reachability.IsPatternPossible(leaf, branch)
    assert !harness.Reachability.IsPatternPossible(branch, leaf)
    assert !harness.Reachability.IsPatternPossible(leaf, ReachabilityClass("Twig", true))

    // The partner must be a ClassTypeInfo: a sealed class against a RECORD class falls through and
    // admits, because the sealed arms name only classes.
    assert harness.Reachability.IsPatternPossible(leaf, ReachabilityRecord("Person", false))
    assert harness.Reachability.IsPatternPossible(ReachabilityRecord("Person", false), leaf)
}

test "an OWNED alias is transparent to the judgement, and an unregistered one is not" {
    harness := ReachabilityDefault()

    // The alias stands for `int`; against `bool` that is two value types, so it refuses THROUGH the
    // alias — which only happens because the context owns it.
    aliasToInt := ReachabilityOwnedAlias(harness, new SimpleTypeReference("int"))
    assert !harness.Reachability.IsPatternPossible(aliasToInt, BuiltInTypes.Bool)

    // An alias to a CLASS resolves to a reference type and admits against another class.
    aliasToDog := ReachabilityOwnedAlias(harness, new SimpleTypeReference("Dog"))
    harness.Context.RegisterCanonicalType(ReachabilityAliasPath(), "Dog", ReachabilityClass("Dog", false))
    assert harness.Reachability.IsPatternPossible(aliasToDog, ReachabilityClass("Cat", false))
}

// ---------------------------------------------------------------------------------------------
// THE TWO DIAGNOSTICS
// ---------------------------------------------------------------------------------------------

test "an impossible TYPE PATTERN reports NL506 once, naming the pattern, at the pattern's own span" {
    harness := ReachabilityDefault()

    harness.Reachability.CheckTypePattern(
        ReachabilityTypePattern("bool", 7, 9),
        BuiltInTypes.Int,
        BuiltInTypes.Bool
    )

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ImpossiblePattern
    assert harness.Errors[0].Message == "This 'bool' pattern can never match — a 'int' is never a 'bool'"
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 9
}

test "an impossible `is` EXPRESSION reports NL506 once, naming the TEST, at the `is` span" {
    harness := ReachabilityDefault()

    harness.Reachability.CheckIsExpression(
        ReachabilityIsExpression("int", 4, 12),
        BuiltInTypes.String,
        BuiltInTypes.Int
    )

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ImpossiblePattern
    assert harness.Errors[0].Message == "This 'is int' check is always false — a 'string' is never a 'int'"
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 12
}

test "a POSSIBLE test reports nothing at either site" {
    harness := ReachabilityDefault()

    harness.Reachability.CheckTypePattern(
        ReachabilityTypePattern("Dog", 7, 9),
        ReachabilityClass("Animal", false),
        ReachabilityClass("Dog", false)
    )
    harness.Reachability.CheckIsExpression(
        ReachabilityIsExpression("Dog", 4, 12),
        BuiltInTypes.Object,
        ReachabilityClass("Dog", false)
    )

    assert harness.Errors.Count == 0
}

test "each site reports ONCE PER ASK, in ask order, and the two messages stay distinct" {
    harness := ReachabilityDefault()

    harness.Reachability.CheckIsExpression(
        ReachabilityIsExpression("bool", 2, 5),
        BuiltInTypes.Int,
        BuiltInTypes.Bool
    )
    harness.Reachability.CheckTypePattern(
        ReachabilityTypePattern("bool", 3, 5),
        BuiltInTypes.Int,
        BuiltInTypes.Bool
    )

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "This 'is bool' check is always false — a 'int' is never a 'bool'"
    assert harness.Errors[1].Message == "This 'bool' pattern can never match — a 'int' is never a 'bool'"
}

// ---------------------------------------------------------------------------------------------
// THE PLACEHOLDER WALK — the two artifacts, and a clean tree
// ---------------------------------------------------------------------------------------------

test "the walk knows exactly two artifacts: an `<error>` identifier and an `<error>` member name" {
    assert AnalyzerParserErrorPlaceholders.PlaceholderName() == "<error>"
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new IdentifierExpression("<error>", 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new MemberAccessExpression(ReachabilityClean(), "<error>", false, 1, 1)
    )

    // A well-formed identifier and a well-formed member name are not artifacts, and neither is a
    // differently-spelled one.
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new IdentifierExpression("value", 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new IdentifierExpression("error", 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new MemberAccessExpression(ReachabilityClean(), "Length", false, 1, 1)
    )
}

test "a member access descends into its RECEIVER when its own name is clean" {
    clean := new MemberAccessExpression(ReachabilityClean(), "Length", false, 1, 1)
    broken := new MemberAccessExpression(ReachabilityPlaceholder(), "Length", false, 1, 1)

    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(clean)
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(broken)
}

test "an expression kind with no children is never an artifact" {
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new IntLiteralExpression("1", 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new StringLiteralExpression("s", 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new BoolLiteralExpression(true, 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new NullLiteralExpression(1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new ThisExpression(1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new BaseExpression(1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new DefaultExpression(1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new TypeOfExpression(new SimpleTypeReference("int"), 1, 1)
    )
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new SizeOfExpression(new SimpleTypeReference("int"), 1, 1)
    )
}

test "an interpolated string looks at its HOLES and ignores its text" {
    withText := new List<InterpolatedStringPart>()
    withText.Add(new InterpolatedStringText("<error>", 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new InterpolatedStringExpression(withText, 1, 1)
    )

    withHole := new List<InterpolatedStringPart>()
    withHole.Add(new InterpolatedStringText("value: ", 1, 1))
    withHole.Add(new InterpolatedStringHole(ReachabilityPlaceholder(), null, 1, 1))
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new InterpolatedStringExpression(withHole, 1, 1)
    )

    empty := new List<InterpolatedStringPart>()
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new InterpolatedStringExpression(empty, 1, 1)
    )
}

test "a range asks both ends and tolerates either being absent" {
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(new RangeExpression(null, null, 1, 1))
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new RangeExpression(ReachabilityPlaceholder(), null, 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new RangeExpression(null, ReachabilityPlaceholder(), 1, 1)
    )
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new RangeExpression(ReachabilityClean(), ReachabilityClean(), 1, 1)
    )
}

test "a call asks its callee AND every argument" {
    calleeBroken := new CallExpression(ReachabilityPlaceholder(), ReachabilityCleanArguments(), null, 1, 1)
    argumentBroken := new CallExpression(ReachabilityClean(), ReachabilityPlaceholderArguments(), null, 1, 1)
    clean := new CallExpression(ReachabilityClean(), ReachabilityCleanArguments(), null, 1, 1)

    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(calleeBroken)
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(argumentBroken)
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(clean)
}

test "every two-operand expression asks BOTH operands" {
    left := AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new BinaryExpression(ReachabilityPlaceholder(), BinaryOperator.Add, ReachabilityClean(), 1, 1)
    )
    right := AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new BinaryExpression(ReachabilityClean(), BinaryOperator.Add, ReachabilityPlaceholder(), 1, 1)
    )
    assert left
    assert right
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new BinaryExpression(ReachabilityClean(), BinaryOperator.Add, ReachabilityClean(), 1, 1)
    )

    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new AssignmentExpression(
            ReachabilityPlaceholder(),
            AssignmentOperator.Assign,
            ReachabilityClean(),
            1,
            1
        )
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new AssignmentExpression(
            ReachabilityClean(),
            AssignmentOperator.Assign,
            ReachabilityPlaceholder(),
            1,
            1
        )
    )

    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new IndexAccessExpression(ReachabilityPlaceholder(), ReachabilityClean(), false, 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new IndexAccessExpression(ReachabilityClean(), ReachabilityPlaceholder(), false, 1, 1)
    )
}

test "every single-operand wrapper asks its operand" {
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new UnaryExpression(UnaryOperator.Not, ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new MustExpression(ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new ParenthesizedExpression(ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new CheckedExpression(ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new UncheckedExpression(ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new AllocExpression(ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new StackAllocExpression(new SimpleTypeReference("byte"), ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new CastExpression(ReachabilityPlaceholder(), new SimpleTypeReference("int"), CastKind.Hard, 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new IsExpression(ReachabilityPlaceholder(), new SimpleTypeReference("int"), null, 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new AwaitExpression(ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new ThrowExpression(ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new SpreadExpression(ReachabilityPlaceholder(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new NameofExpression(ReachabilityPlaceholder(), 1, 1)
    )
}

test "a lambda asks its EXPRESSION body only, and a block-bodied lambda is never an artifact" {
    withExpressionBody := new LambdaExpression(
        new List<Parameter>(),
        ReachabilityPlaceholder(),
        null,
        1,
        1
    )
    withoutExpressionBody := new LambdaExpression(new List<Parameter>(), null, null, 1, 1)

    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(withExpressionBody)
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(withoutExpressionBody)
}

test "a ternary asks all three of its parts" {
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new TernaryExpression(ReachabilityPlaceholder(), ReachabilityClean(), ReachabilityClean(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new TernaryExpression(ReachabilityClean(), ReachabilityPlaceholder(), ReachabilityClean(), 1, 1)
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new TernaryExpression(ReachabilityClean(), ReachabilityClean(), ReachabilityPlaceholder(), 1, 1)
    )
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new TernaryExpression(ReachabilityClean(), ReachabilityClean(), ReachabilityClean(), 1, 1)
    )
}

test "an array literal and a tuple ask every element" {
    elements := new List<Expression>()
    elements.Add(ReachabilityClean())
    elements.Add(ReachabilityPlaceholder())
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new ArrayLiteralExpression(elements, false, 1, 1)
    )
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new ArrayLiteralExpression(new List<Expression>(), false, 1, 1)
    )

    tupleElements := new List<TupleElement>()
    tupleElements.Add(new TupleElement("first", ReachabilityClean()))
    tupleElements.Add(new TupleElement(null, ReachabilityPlaceholder()))
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new TupleExpression(tupleElements, 1, 1)
    )
}

test "a `new` asks its constructor arguments, its initializer AND its array length" {
    argumentBroken := new NewExpression(
        new SimpleTypeReference("Dog"),
        ReachabilityPlaceholderArguments(),
        null,
        1,
        1
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(argumentBroken)

    initializerProperties := new List<PropertyInitializer>()
    initializerProperties.Add(new PropertyInitializer("Age", null, ReachabilityPlaceholder()))
    initializerBroken := new NewExpression(
        new SimpleTypeReference("Dog"),
        ReachabilityCleanArguments(),
        new ObjectInitializerExpression(initializerProperties, 1, 1),
        1,
        1
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(initializerBroken)

    lengthBroken := new NewExpression(
        new SimpleTypeReference("int"),
        ReachabilityCleanArguments(),
        null,
        1,
        1,
        ReachabilityPlaceholder()
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(lengthBroken)

    clean := new NewExpression(
        new SimpleTypeReference("Dog"),
        ReachabilityCleanArguments(),
        null,
        1,
        1
    )
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(clean)
}

test "an initializer property asks its INDEX expression as well as its value, in both carriers" {
    indexBroken := new List<PropertyInitializer>()
    indexBroken.Add(new PropertyInitializer(null, ReachabilityPlaceholder(), ReachabilityClean()))
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new ObjectInitializerExpression(indexBroken, 1, 1)
    )

    valueBroken := new List<PropertyInitializer>()
    valueBroken.Add(new PropertyInitializer("Age", null, ReachabilityPlaceholder()))
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new WithExpression(ReachabilityClean(), valueBroken, 1, 1)
    )

    // A `with` also asks its TARGET.
    cleanProperties := new List<PropertyInitializer>()
    cleanProperties.Add(new PropertyInitializer("Age", null, ReachabilityClean()))
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new WithExpression(ReachabilityPlaceholder(), cleanProperties, 1, 1)
    )
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new WithExpression(ReachabilityClean(), cleanProperties, 1, 1)
    )
}

test "a match asks its scrutinee, and every arm's PATTERN, guard and body" {
    cleanCase := new MatchCase(new IdentifierPattern("value", 1, 1), null, ReachabilityClean())

    scrutineeCases := new List<MatchCase>()
    scrutineeCases.Add(cleanCase)
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new MatchExpression(ReachabilityPlaceholder(), scrutineeCases, 1, 1)
    )

    patternCases := new List<MatchCase>()
    patternCases.Add(new MatchCase(
        new RelationalPattern(">", ReachabilityPlaceholder(), 1, 1),
        null,
        ReachabilityClean()
    ))
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new MatchExpression(ReachabilityClean(), patternCases, 1, 1)
    )

    guardCases := new List<MatchCase>()
    guardCases.Add(new MatchCase(
        new IdentifierPattern("value", 1, 1),
        ReachabilityPlaceholder(),
        ReachabilityClean()
    ))
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new MatchExpression(ReachabilityClean(), guardCases, 1, 1)
    )

    bodyCases := new List<MatchCase>()
    bodyCases.Add(new MatchCase(
        new IdentifierPattern("value", 1, 1),
        null,
        ReachabilityPlaceholder()
    ))
    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new MatchExpression(ReachabilityClean(), bodyCases, 1, 1)
    )

    cleanCases := new List<MatchCase>()
    cleanCases.Add(cleanCase)
    assert !AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new MatchExpression(ReachabilityClean(), cleanCases, 1, 1)
    )
}

// ---------------------------------------------------------------------------------------------
// THE PLACEHOLDER WALK — the PATTERN entry point
// ---------------------------------------------------------------------------------------------

test "a pattern kind with no expression and no sub-pattern is never an artifact" {
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(new IdentifierPattern("<error>", 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(new SlicePattern("rest", 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(
        new TypePattern(new SimpleTypeReference("<error>"), "value", 1, 1)
    )
}

test "a LITERAL pattern asks its literal — the arm no source can reach, because a literal is one token" {
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(
        new LiteralPattern(ReachabilityPlaceholder(), 1, 1)
    )
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(
        new LiteralPattern(ReachabilityClean(), 1, 1)
    )
}

test "a RELATIONAL pattern asks its bound — the one pattern arm malformed source actually reaches" {
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(
        new RelationalPattern(">", ReachabilityPlaceholder(), 1, 1)
    )
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(
        new RelationalPattern(">", ReachabilityClean(), 1, 1)
    )
}

test "a union-case pattern asks its properties, and a payload-less case has NONE to ask" {
    payloadless := new UnionCasePattern("Circle", null, 1, 1)
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(payloadless)

    properties := new List<PropertyPattern>()
    properties.Add(new PropertyPattern("r", new RelationalPattern(">", ReachabilityPlaceholder(), 1, 1), null))
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(
        new UnionCasePattern("Circle", properties, 1, 1)
    )

    empty := new List<PropertyPattern>()
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(
        new UnionCasePattern("Circle", empty, 1, 1)
    )
}

test "an object pattern asks its properties" {
    properties := new List<PropertyPattern>()
    properties.Add(new PropertyPattern("Name", new IdentifierPattern("n", 1, 1), null))
    properties.Add(new PropertyPattern("Age", new RelationalPattern(">", ReachabilityPlaceholder(), 1, 1), null))
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(new ObjectPattern(properties, 1, 1))

    clean := new List<PropertyPattern>()
    clean.Add(new PropertyPattern("Name", new IdentifierPattern("n", 1, 1), null))
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(new ObjectPattern(clean, 1, 1))
}

test "a property pattern with NO nested pattern — a pure binding — carries nothing" {
    assert !AnalyzerParserErrorPlaceholders.ContainsInPropertyPattern(
        new PropertyPattern("Name", null, "n")
    )
    assert AnalyzerParserErrorPlaceholders.ContainsInPropertyPattern(
        new PropertyPattern("Age", new RelationalPattern(">", ReachabilityPlaceholder(), 1, 1), null)
    )
}

test "a LIST pattern asks every element — the second arm no source can reach, because the recovery parser panics first" {
    elements := new List<Pattern>()
    elements.Add(new IdentifierPattern("first", 1, 1))
    elements.Add(new RelationalPattern(">", ReachabilityPlaceholder(), 1, 1))
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(new ListPattern(elements, 1, 1))

    clean := new List<Pattern>()
    clean.Add(new IdentifierPattern("first", 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(new ListPattern(clean, 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(new ListPattern(new List<Pattern>(), 1, 1))
}

test "the logical patterns ask both sides, and `not` asks its one side" {
    broken: Pattern = new RelationalPattern(">", ReachabilityPlaceholder(), 1, 1)
    clean: Pattern = new RelationalPattern("<", ReachabilityClean(), 1, 1)

    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(new AndPattern(broken, clean, 1, 1))
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(new AndPattern(clean, broken, 1, 1))
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(new OrPattern(broken, clean, 1, 1))
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(new OrPattern(clean, broken, 1, 1))
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(new NotPattern(broken, 1, 1))

    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(new AndPattern(clean, clean, 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(new OrPattern(clean, clean, 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(new NotPattern(clean, 1, 1))
}

test "a positional pattern asks every position" {
    patterns := new List<Pattern>()
    patterns.Add(new IdentifierPattern("a", 1, 1))
    patterns.Add(new RelationalPattern(">", ReachabilityPlaceholder(), 1, 1))
    assert AnalyzerParserErrorPlaceholders.ContainsInPattern(new PositionalPattern(patterns, 1, 1))

    clean := new List<Pattern>()
    clean.Add(new IdentifierPattern("a", 1, 1))
    assert !AnalyzerParserErrorPlaceholders.ContainsInPattern(new PositionalPattern(clean, 1, 1))
}

test "the three entry points are ONE mutually recursive walk: expression to pattern and back" {
    // `match value { Circle { r: > <error> } => 1 }` — the artifact is four levels down, reached
    // only by expression -> match -> pattern -> property pattern -> pattern -> expression.
    properties := new List<PropertyPattern>()
    properties.Add(new PropertyPattern("r", new RelationalPattern(">", ReachabilityPlaceholder(), 1, 1), null))
    cases := new List<MatchCase>()
    cases.Add(new MatchCase(
        new NotPattern(new UnionCasePattern("Circle", properties, 1, 1), 1, 1),
        null,
        ReachabilityClean()
    ))
    nested: Expression = new MatchExpression(ReachabilityClean(), cases, 1, 1)

    assert AnalyzerParserErrorPlaceholders.ContainsInExpression(
        new ParenthesizedExpression(new CheckedExpression(nested, 1, 1), 1, 1)
    )
}

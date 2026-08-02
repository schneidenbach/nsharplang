namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the two pattern SHAPE questions.
//
// THE CORPUS CANNOT DECIDE EITHER OF THEM. The slice-25 measurement counted, over all 71 corpus
// targets, **34 list patterns and ZERO list-pattern mismatches**, and **ZERO relational patterns of
// any kind** — so the whole relational family and every reporting arm of the list family have no
// observable in the compiler's own estate. What is pinned here is therefore the decision itself:
// which types have a list shape, where the shape is found when it is split across two interfaces,
// which primitives can be compared before IL emission, and the exact text and span of the two
// diagnostics.
//
// THE REFLECTED ARM IS EXERCISED WITH REAL BCL METADATA rather than a stand-in, because its whole
// content is what `GetProperty` / `GetProperties` / `GetIndexParameters` answer on real types:
// `IReadOnlyList<int>` is the case that proves the inherited-interface walk, since its `Count` is
// declared on `IReadOnlyCollection<T>` and interfaces do not inherit members in reflection.

class PatternShapesHarness {
    Shapes: AnalyzerPatternShapes
    Errors: List<CompilerError>
    Context: AnalyzerDeclarationContext

    constructor(
        shapes: AnalyzerPatternShapes,
        errors: List<CompilerError>,
        context: AnalyzerDeclarationContext) {
        Shapes = shapes
        Errors = errors
        Context = context
    }
}

func PatternShapesAliasPath(): string {
    return "/tmp/pattern-shapes-alias.nl"
}

func PatternShapesDefault(): PatternShapesHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    context.AddCompilationUnit(PatternShapesAliasPath(), new AnalyzerContextTestUnit(new List<object>()))
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
    spans := new AnalyzerDiagnosticSpans(diagnostics)
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

    return new PatternShapesHarness(
        new AnalyzerPatternShapes(diagnostics, spans, context, assignability),
        errors,
        context)
}

func PatternShapesList(elementTypeName: string): TypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(new SimpleTypeInfo(elementTypeName))
    generic: TypeInfo = new GenericTypeInfo("List", arguments)
    return generic
}

func PatternShapesGeneric(name: string, elementTypeName: string): TypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(new SimpleTypeInfo(elementTypeName))
    generic: TypeInfo = new GenericTypeInfo(name, arguments)
    return generic
}

func PatternShapesEmptyGeneric(name: string): TypeInfo {
    generic: TypeInfo = new GenericTypeInfo(name, new List<TypeInfo>())
    return generic
}

func PatternShapesListPattern(line: int, column: int): ListPattern {
    return new ListPattern(new List<Pattern>(), line, column)
}

func PatternShapesRelational(operatorText: string): RelationalPattern {
    return new RelationalPattern(operatorText, new IntLiteralExpression("1", 7, 9), 7, 5)
}

func PatternShapesName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<none>"
    }

    asObject := candidate as object
    return asObject.ToString()
}

// An alias the harness's context OWNS, so `ResolveDeclaredAlias` is transparent through it. An
// unregistered alias resolves to itself, which is a different (and also pinned) answer.
func PatternShapesOwnedAlias(
    harness: PatternShapesHarness,
    aliased: TypeReference): TypeInfo {
    alias := new AliasTypeInfo(aliased)
    harness.Context.RegisterDeclaredAlias(PatternShapesAliasPath(), alias)
    owned: TypeInfo = alias
    return owned
}

// ---------------------------------------------------------------------------------------------
// THE LIST SHAPE
// ---------------------------------------------------------------------------------------------

test "an array answers its own element type, whatever the element is" {
    harness := PatternShapesDefault()

    intArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)
    stringArray: TypeInfo = new ArrayTypeInfo(BuiltInTypes.String)
    nestedArray: TypeInfo = new ArrayTypeInfo(new ArrayTypeInfo(BuiltInTypes.Int))

    assert PatternShapesName(harness.Shapes.FindListPatternElementType(intArray)) == "int"
    assert PatternShapesName(harness.Shapes.FindListPatternElementType(stringArray)) == "string"
    assert PatternShapesName(harness.Shapes.FindListPatternElementType(nestedArray)) == "int[]"
    assert harness.Errors.Count == 0
}

test "exactly three generic names carry a list shape, and the test is case-sensitive" {
    assert AnalyzerPatternShapes.IsIndexableGenericListPatternType("List")
    assert AnalyzerPatternShapes.IsIndexableGenericListPatternType("IList")
    assert AnalyzerPatternShapes.IsIndexableGenericListPatternType("IReadOnlyList")

    // The near misses are the point: a collection interface without an int indexer is NOT a list
    // shape, and neither is a differently-cased spelling of one that is.
    assert !AnalyzerPatternShapes.IsIndexableGenericListPatternType("IEnumerable")
    assert !AnalyzerPatternShapes.IsIndexableGenericListPatternType("ICollection")
    assert !AnalyzerPatternShapes.IsIndexableGenericListPatternType("IReadOnlyCollection")
    assert !AnalyzerPatternShapes.IsIndexableGenericListPatternType("Dictionary")
    assert !AnalyzerPatternShapes.IsIndexableGenericListPatternType("list")
    assert !AnalyzerPatternShapes.IsIndexableGenericListPatternType("")
}

test "an indexable generic answers its FIRST type argument" {
    harness := PatternShapesDefault()

    assert PatternShapesName(harness.Shapes.FindListPatternElementType(
        PatternShapesList("int"))) == "int"
    assert PatternShapesName(harness.Shapes.FindListPatternElementType(
        PatternShapesGeneric("IList", "string"))) == "string"
    assert PatternShapesName(harness.Shapes.FindListPatternElementType(
        PatternShapesGeneric("IReadOnlyList", "double"))) == "double"
}

test "an indexable generic with NO type argument answers unknown, not `no shape`" {
    // Unreachable from source and reachable here: the shape is accepted on its NAME, so the missing
    // argument degrades the element type rather than rejecting the pattern. The distinction is
    // visible only as `unknown` versus a report.
    harness := PatternShapesDefault()

    answer := harness.Shapes.FindListPatternElementType(PatternShapesEmptyGeneric("List"))

    assert answer != null
    assert BuiltInTypes.IsUnknown(answer)
    assert harness.Errors.Count == 0
}

test "a generic that is not one of the three has no list shape at all" {
    harness := PatternShapesDefault()

    assert harness.Shapes.FindListPatternElementType(
        PatternShapesGeneric("IEnumerable", "int")) == null
    assert harness.Shapes.FindListPatternElementType(
        PatternShapesGeneric("IReadOnlyCollection", "int")) == null
    assert harness.Shapes.FindListPatternElementType(
        PatternShapesGeneric("Dictionary", "string")) == null
}

test "a simple type has no list shape" {
    harness := PatternShapesDefault()

    assert harness.Shapes.FindListPatternElementType(BuiltInTypes.Int) == null
    assert harness.Shapes.FindListPatternElementType(BuiltInTypes.String) == null
    assert harness.Shapes.FindListPatternElementType(BuiltInTypes.Bool) == null
}

test "a DECLARED ALIAS of an array resolves through to the array's element type" {
    harness := PatternShapesDefault()
    rowAlias := PatternShapesOwnedAlias(
        harness,
        new ArrayTypeReference(new SimpleTypeReference("int")))

    assert PatternShapesName(harness.Shapes.FindListPatternElementType(rowAlias)) == "int"

    // Registration is what makes it transparent: an alias this context does not own resolves to
    // ITSELF, and an alias is not a list shape.
    unowned: TypeInfo = new AliasTypeInfo(new ArrayTypeReference(new SimpleTypeReference("int")))
    assert harness.Shapes.FindListPatternElementType(unowned) == null
}

test "a reflected ARRAY answers a reflected element type" {
    answer := AnalyzerPatternShapes.FindReflectionListPatternElementType(typeof(int[]))

    assert answer != null
    reflected := answer as ReflectionTypeInfo
    assert reflected != null
    assert reflected.Type == typeof(int)
}

test "a reflected CLASS with an int Count and an int indexer is list-shaped" {
    answer := AnalyzerPatternShapes.FindReflectionListPatternElementType(typeof(List<string>))

    assert answer != null
    reflected := answer as ReflectionTypeInfo
    assert reflected != null
    assert reflected.Type == typeof(string)
}

test "a reflected INTERFACE finds its Count on an INHERITED interface" {
    // `IReadOnlyList<T>` declares the indexer; `Count` is declared on `IReadOnlyCollection<T>`, and
    // reflection does NOT surface it through the derived interface. Without the inherited-interface
    // walk this answers `no list shape` and every `[first]` over an `IReadOnlyList<int>` would
    // report NL505.
    assert typeof(IReadOnlyList<int>).GetProperty(
        "Count",
        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance) == null

    answer := AnalyzerPatternShapes.FindReflectionListPatternElementType(typeof(IReadOnlyList<int>))

    assert answer != null
    reflected := answer as ReflectionTypeInfo
    assert reflected != null
    assert reflected.Type == typeof(int)
}

test "the shape types are the type itself, plus inherited interfaces for an INTERFACE only" {
    classShape := AnalyzerPatternShapes.GetListPatternShapeTypes(typeof(List<int>))
    assert classShape.Count == 1
    assert classShape[0] == typeof(List<int>)

    interfaceShape := AnalyzerPatternShapes.GetListPatternShapeTypes(typeof(IReadOnlyList<int>))
    assert interfaceShape.Count > 1
    assert interfaceShape[0] == typeof(IReadOnlyList<int>)
}

test "a reflected type with a Length but no int indexer is not list-shaped" {
    // `System.Text.StringBuilder` HAS both (`Length` and `this[int]`), so it IS list-shaped and its element is
    // `char`; `Version` has neither and is not. Both directions are asserted so the probe is not
    // vacuously negative.
    builder := AnalyzerPatternShapes.FindReflectionListPatternElementType(typeof(System.Text.StringBuilder))
    assert builder != null
    builderElement := builder as ReflectionTypeInfo
    assert builderElement != null
    assert builderElement.Type == typeof(char)

    assert AnalyzerPatternShapes.FindReflectionListPatternElementType(typeof(Version)) == null
    assert AnalyzerPatternShapes.FindReflectionListPatternElementType(typeof(IEnumerable<int>)) == null
}

test "a list pattern over a shapeless value reports NL505 ONCE and answers unknown" {
    harness := PatternShapesDefault()
    listPattern := PatternShapesListPattern(12, 21)

    answer := harness.Shapes.ResolveListPatternElementType(
        listPattern,
        PatternShapesGeneric("IEnumerable", "int"))

    assert BuiltInTypes.IsUnknown(answer)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.PatternTypeMismatch
    assert harness.Errors[0].Message
        == "A list pattern can only match arrays or indexable collections, but this value is 'IEnumerable<int>'"
    assert harness.Errors[0].Line == 12
    assert harness.Errors[0].Column == 21
}

test "a list pattern over a shaped value answers the element type and stays silent" {
    harness := PatternShapesDefault()

    answer := harness.Shapes.ResolveListPatternElementType(
        PatternShapesListPattern(3, 5),
        new ArrayTypeInfo(BuiltInTypes.String))

    assert PatternShapesName(answer) == "string"
    assert harness.Errors.Count == 0
}

test "the NL505 message renders the ORIGINAL spelling, not the alias-resolved one" {
    // `TryGetListPatternElementType` resolved a LOCAL copy of the type; the message was always
    // built from the caller's own `valueType`. An alias whose target is also shapeless must print
    // the alias name.
    harness := PatternShapesDefault()
    nameAlias := PatternShapesOwnedAlias(harness, new SimpleTypeReference("string"))

    harness.Shapes.ResolveListPatternElementType(PatternShapesListPattern(1, 1), nameAlias)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "A list pattern can only match arrays or indexable collections, but this value is '"
            + PatternShapesName(nameAlias) + "'"
}

// ---------------------------------------------------------------------------------------------
// RELATIONAL COMPARABILITY
// ---------------------------------------------------------------------------------------------

test "exactly two operators admit a bool" {
    assert AnalyzerPatternShapes.IsEqualityPatternOperator("==")
    assert AnalyzerPatternShapes.IsEqualityPatternOperator("!=")
    assert !AnalyzerPatternShapes.IsEqualityPatternOperator("<")
    assert !AnalyzerPatternShapes.IsEqualityPatternOperator("<=")
    assert !AnalyzerPatternShapes.IsEqualityPatternOperator(">")
    assert !AnalyzerPatternShapes.IsEqualityPatternOperator(">=")
    assert !AnalyzerPatternShapes.IsEqualityPatternOperator("=")
}

test "every ordered primitive is comparable, and decimal is NOT" {
    harness := PatternShapesDefault()

    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Int, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Long, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Float, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Double, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Byte, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.SByte, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Short, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.UShort, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.UInt, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.ULong, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Char, false)

    // The exclusion is deliberate and comes BEFORE the numeric test, which would otherwise admit it.
    assert !harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Decimal, false)
    assert !harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Decimal, true)

    assert !harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.String, false)
    assert !harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Object, false)
}

test "a bool is comparable ONLY when the operator is an equality one" {
    harness := PatternShapesDefault()

    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Bool, true)
    assert !harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Bool, false)
}

test "an ALIAS of an ordered primitive is comparable through its target" {
    harness := PatternShapesDefault()
    meters := PatternShapesOwnedAlias(harness, new SimpleTypeReference("int"))
    names := PatternShapesOwnedAlias(harness, new SimpleTypeReference("string"))

    assert harness.Shapes.IsRelationalPatternComparableType(meters, false)
    assert !harness.Shapes.IsRelationalPatternComparableType(names, false)
}

test "a NULLABLE spelling is stripped before the comparability test" {
    // `int?` is comparable AS A TYPE — the nullable REJECTION is a separate test in the judgement,
    // and conflating the two would make the judgement unable to distinguish `int?` from `string?`.
    harness := PatternShapesDefault()

    assert harness.Shapes.IsRelationalPatternComparableType(
        new NullableTypeInfo(BuiltInTypes.Int), false)
    assert !harness.Shapes.IsRelationalPatternComparableType(
        new NullableTypeInfo(BuiltInTypes.String), false)
}

test "the REFLECTED arm admits the same primitives and rejects decimal" {
    harness := PatternShapesDefault()

    assert harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(int)), false)
    assert harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(byte)), false)
    assert harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(char)), false)
    assert harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(ulong)), false)
    assert harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(double)), false)

    assert !harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(decimal)), false)
    assert !harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(decimal)), true)
    assert !harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(DateTime)), false)
    assert !harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(MethodAttributes)), false)

    assert harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(bool)), true)
    assert !harness.Shapes.IsRelationalPatternComparableType(new ReflectionTypeInfo(typeof(bool)), false)
}

test "a reflected Nullable<T> is unwrapped by the reflected arm, and IS the nullable question's yes" {
    // The two members disagree on purpose: comparability looks THROUGH `Nullable<int>` and says
    // yes, while the nullable question says yes too — and it is the nullable question that makes
    // the judgement report. Losing either one changes which shapes are rejected.
    harness := PatternShapesDefault()
    reflectedNullable: TypeInfo = new ReflectionTypeInfo(typeof(int?))

    assert harness.Shapes.IsRelationalPatternComparableType(reflectedNullable, false)
    assert harness.Shapes.IsNullableRelationalPatternType(reflectedNullable)
    assert !harness.Shapes.IsNullableRelationalPatternType(new ReflectionTypeInfo(typeof(int)))
}

test "the nullable question answers both spellings, and resolves aliases first" {
    harness := PatternShapesDefault()
    maybeInt := PatternShapesOwnedAlias(
        harness,
        new NullableTypeReference(new SimpleTypeReference("int")))

    assert harness.Shapes.IsNullableRelationalPatternType(new NullableTypeInfo(BuiltInTypes.Int))
    assert harness.Shapes.IsNullableRelationalPatternType(maybeInt)
    assert !harness.Shapes.IsNullableRelationalPatternType(BuiltInTypes.Int)
    assert !harness.Shapes.IsNullableRelationalPatternType(BuiltInTypes.String)
}

test "an ordered comparison of two ints is silent" {
    harness := PatternShapesDefault()

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        BuiltInTypes.Int,
        BuiltInTypes.Int)

    assert harness.Errors.Count == 0
}

test "an UNKNOWN on either side returns before any judgement is made" {
    // A relational pattern whose value expression failed to analyse must not add a second report on
    // top of the one the expression already produced.
    harness := PatternShapesDefault()

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        BuiltInTypes.Unknown,
        BuiltInTypes.String)
    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        BuiltInTypes.String,
        BuiltInTypes.Unknown)

    assert harness.Errors.Count == 0
}

test "a decimal comparison reports, with the verbatim message, suggestion and OPERATOR span" {
    harness := PatternShapesDefault()

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational(">="),
        BuiltInTypes.Decimal,
        BuiltInTypes.Decimal)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message
        == "Relational pattern '>=' can't compare 'decimal' with 'decimal' before IL emission"
    assert harness.Errors[0].Suggestion
        == "Use numeric operands with a supported common type, use a literal pattern for string equality, or move custom comparisons into a match guard."
    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 5
    assert harness.Errors[0].Length == 2
}

test "the span is at least one character even for a one-character operator" {
    harness := PatternShapesDefault()

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        BuiltInTypes.String,
        BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Length == 1
}

test "a string comparison reports under EVERY operator, equality included" {
    harness := PatternShapesDefault()

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("=="),
        BuiltInTypes.String,
        BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "Relational pattern '==' can't compare 'string' with 'string' before IL emission"
}

test "a bool comparison is silent under equality and reports under ordering" {
    harness := PatternShapesDefault()

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("!="),
        BuiltInTypes.Bool,
        BuiltInTypes.Bool)
    assert harness.Errors.Count == 0

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational(">"),
        BuiltInTypes.Bool,
        BuiltInTypes.Bool)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "Relational pattern '>' can't compare 'bool' with 'bool' before IL emission"
}

test "a NULLABLE scrutinee reports even though its underlying type is comparable" {
    harness := PatternShapesDefault()
    nullableInt: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        nullableInt,
        BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "Relational pattern '<' can't compare 'int?' with 'int' before IL emission"
}

test "a nullable PATTERN VALUE reports the same way the scrutinee does" {
    harness := PatternShapesDefault()

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        BuiltInTypes.Int,
        new NullableTypeInfo(BuiltInTypes.Int))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "Relational pattern '<' can't compare 'int' with 'int?' before IL emission"
}

test "two comparable primitives that are NOT assignable still report" {
    // The assignability test is the LAST of the four and it is not implied by the other three:
    // `int` and `double` are both ordered primitives, and the direction of the widening is what
    // decides. `IsAssignable(int, double)` is false, so an `int` scrutinee cannot take a `double`
    // pattern value even though both are comparable.
    harness := PatternShapesDefault()

    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Int, false)
    assert harness.Shapes.IsRelationalPatternComparableType(BuiltInTypes.Double, false)

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        BuiltInTypes.Int,
        BuiltInTypes.Double)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message
        == "Relational pattern '<' can't compare 'int' with 'double' before IL emission"
}

test "the widening that DOES hold is silent" {
    harness := PatternShapesDefault()

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        BuiltInTypes.Double,
        BuiltInTypes.Int)
    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        BuiltInTypes.Long,
        BuiltInTypes.Int)

    assert harness.Errors.Count == 0
}

test "each judgement reports at most ONCE, however many of the four tests fail" {
    // `string` versus `decimal` fails comparability on BOTH sides and assignability as well; the
    // four tests are OR-ed into one report rather than accumulated.
    harness := PatternShapesDefault()

    harness.Shapes.ValidateRelationalPattern(
        PatternShapesRelational("<"),
        BuiltInTypes.String,
        BuiltInTypes.Decimal)

    assert harness.Errors.Count == 1
}

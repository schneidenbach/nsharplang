namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the array-literal arm — what `[a, b, c]` MEANS.
//
// Every member behind these contracts was `private` in `Analyzer.cs`. This is their first DIRECT
// pinning, and it goes at the decisions that read like plumbing and are not:
//
//   * the TWO FORMS and that the choice between them is made ONCE — a named element type is the
//     answer whatever the elements turn out to be, and an unnamed one is decided by the FIRST
//     element and never revised;
//   * the EMPTY literal, which answers before either form and takes no steps at all;
//   * the BRACKET, which is open for every element of a targeted literal and for NONE of an inferred
//     one — the reason a lambda inside `xs := [...]` has nothing to infer from;
//   * WHICH WORD a mismatched element is scolded with, because a `List<T>` literal is not an array;
//   * the COLLECTION-TARGET rule, seventeen members of reflection predicate, and in particular the
//     four ways a target can be materialised and the one that is refused outright.
class ArrayLiteralHarness {
    Arm: AnalyzerArrayLiteral
    Errors: List<CompilerError>
    Ambient: AnalyzerAmbientContext

    constructor(arm: AnalyzerArrayLiteral, errors: List<CompilerError>, ambient: AnalyzerAmbientContext) {
        Arm = arm
        Errors = errors
        Ambient = ambient
    }
}

func ArrayArmOf(): ArrayLiteralHarness {
    errors := new List<CompilerError>()
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    scopes := new AnalyzerScopeStack()
    model := new SemanticModel()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    bindings := new BindingMap()
    provider := new AnalyzerProjectSourceProvider()
    sink := new AnalyzerDiagnosticSink(errors, provider)
    spans := new AnalyzerDiagnosticSpans(sink)
    usingAliases := new Dictionary<string, string>(StringComparer.Ordinal)
    importedSymbols := new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal)
    importedDeclarations := new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal)
    namespaces := new List<string>()
    assemblies := new List<Assembly>()
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, usingAliases)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, usingAliases, importedSymbols, importedDeclarations, model, bindings)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    soaEscape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, soaEscape)

    arm := new AnalyzerArrayLiteral(sink, spans, context, ambient, soaEscape, assignability, facts)
    return new ArrayLiteralHarness(arm, errors, ambient)
}

func ArrayCodes(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + ","
        }

        codeValue: int = (int)errors[index].Code
        text = text + codeValue.ToString()
        index = index + 1
    }

    return text
}

func ArrayTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    if BuiltInTypes.IsUnknown(candidate) {
        return "unknown"
    }

    simple := candidate as SimpleTypeInfo
    if simple != null {
        return "simple:" + simple.Name
    }

    reflection := candidate as ReflectionTypeInfo
    if reflection != null {
        return "reflection:" + reflection.Type.get_Name()
    }

    arrayType := candidate as ArrayTypeInfo
    if arrayType != null {
        return "array(" + ArrayTypeName(arrayType.ElementType) + ")"
    }

    generic := candidate as GenericTypeInfo
    if generic != null {
        return "generic:" + generic.Name
    }

    return "<other>"
}

func ArrayLiteralOf(count: int): ArrayLiteralExpression {
    elements := new List<Expression>()
    index := 0
    while index < count {
        element: Expression = new IdentifierExpression("e" + index.ToString(), 4, 8 + index)
        elements.Add(element)
        index = index + 1
    }

    return new ArrayLiteralExpression(elements, false, 4, 1)
}

func ArrayOneArgument(argument: TypeInfo): List<TypeInfo> {
    arguments := new List<TypeInfo>()
    arguments.Add(argument)
    return arguments
}

func ArrayClosedOf(definitionName: string, argument: Type): Type {
    // Several closed generics the collection-target rule is about are not on the columnar `typeof`
    // surface (`Queue<>` and the `System.Linq` interfaces above all), so they are built BY NAME — the
    // compiler's own route-around, yielding the identical runtime type.
    definition := Type.GetType(definitionName)
    typeArguments := new Type[](1)
    typeArguments[0] = argument
    return definition.MakeGenericType(typeArguments)
}

func ArrayClosedQueryable(): Type {
    // `typeof(IQueryable<int>)` is not on the columnar `typeof` surface, so the closed type is built
    // by name — the compiler's own route-around, and the identical runtime type.
    definition := Type.GetType("System.Linq.IQueryable`1, System.Linq.Expressions")
    typeArguments := new Type[](1)
    typeArguments[0] = typeof(int)
    return definition.MakeGenericType(typeArguments)
}

class ArrayDriveTrace {
    Steps: int
    ExpectedAtStep: string
    Answer: string
    Reports: int

    constructor() {
        Steps = 0
        ExpectedAtStep = ""
        Answer = ""
        Reports = 0
    }
}

// One full turn of the protocol. Each element is answered from `answers` in order (the last answer
// repeats if the literal is longer), and the ambient expected type is recorded AT each step — the
// only way to observe a bracket that opens and closes entirely inside the owner.
func ArrayDrive(harness: ArrayLiteralHarness, node: Expression, answers: List<TypeInfo>): ArrayDriveTrace {
    trace := new ArrayDriveTrace()
    before := harness.Errors.Count
    state := harness.Arm.Begin(node)
    step := harness.Arm.NextStep(state)
    while step != null {
        if trace.Steps > 0 {
            trace.ExpectedAtStep = trace.ExpectedAtStep + ","
        }

        trace.ExpectedAtStep = trace.ExpectedAtStep + ArrayTypeName(harness.Ambient.CurrentExpectedType)
        answerIndex := trace.Steps
        if answerIndex >= answers.Count {
            answerIndex = answers.Count - 1
        }

        harness.Arm.Supply(state, answers[answerIndex])
        trace.Steps = trace.Steps + 1
        step = harness.Arm.NextStep(state)
    }

    trace.Answer = ArrayTypeName(harness.Arm.Result(state))
    trace.Reports = harness.Errors.Count - before
    return trace
}

func ArrayAnswers(first: TypeInfo): List<TypeInfo> {
    answers := new List<TypeInfo>()
    answers.Add(first)
    return answers
}

// ---- the empty literal ---------------------------------------------------------------------------

test "an EMPTY literal takes no steps and answers an array of the expected element" {
    harness := ArrayArmOf()
    saved := harness.Ambient.EnterExpectedType(new ArrayTypeInfo(BuiltInTypes.String))
    trace := ArrayDrive(harness, ArrayLiteralOf(0), ArrayAnswers(BuiltInTypes.Int))

    assert trace.Steps == 0
    assert trace.Answer == "array(simple:string)"
    harness.Ambient.ExitExpectedType(saved)
}

test "an EMPTY literal with no annotation answers an array of unknown" {
    harness := ArrayArmOf()
    trace := ArrayDrive(harness, ArrayLiteralOf(0), ArrayAnswers(BuiltInTypes.Int))

    assert trace.Steps == 0
    assert trace.Answer == "array(unknown)"
}

test "a node that is not an array literal finishes at Begin" {
    harness := ArrayArmOf()
    state := harness.Arm.Begin(new IdentifierExpression("xs", 1, 1))

    assert harness.Arm.NextStep(state) == null
    assert ArrayTypeName(harness.Arm.Result(state)) == "unknown"
}

// ---- the inferred form ---------------------------------------------------------------------------

test "an INFERRED literal walks every element with the slot UNTOUCHED and answers the first" {
    harness := ArrayArmOf()
    trace := ArrayDrive(harness, ArrayLiteralOf(3), ArrayAnswers(BuiltInTypes.String))

    assert trace.Steps == 3
    assert trace.ExpectedAtStep == "<null>,<null>,<null>"
    assert trace.Answer == "array(simple:string)"
    assert trace.Reports == 0
}

test "an inferred literal measures every LATER element against the FIRST" {
    harness := ArrayArmOf()
    answers := new List<TypeInfo>()
    answers.Add(BuiltInTypes.Int)
    answers.Add(BuiltInTypes.String)
    trace := ArrayDrive(harness, ArrayLiteralOf(2), answers)

    assert trace.Reports == 1
    assert ArrayCodes(harness.Errors) == "202"
    assert harness.Errors[0].Message.Contains("All elements in an array must be the same type")

    // The ANSWER is still the first element's: widening it would hide the report.
    assert trace.Answer == "array(simple:int)"
}

test "an inferred literal never accuses its FIRST element" {
    harness := ArrayArmOf()
    trace := ArrayDrive(harness, ArrayLiteralOf(1), ArrayAnswers(BuiltInTypes.Unknown))

    assert trace.Steps == 1
    assert trace.Reports == 0
}

// ---- the targeted form ---------------------------------------------------------------------------

test "a TARGETED literal brackets EVERY element and restores the slot afterwards" {
    harness := ArrayArmOf()
    saved := harness.Ambient.EnterExpectedType(new ArrayTypeInfo(BuiltInTypes.Int))
    trace := ArrayDrive(harness, ArrayLiteralOf(2), ArrayAnswers(BuiltInTypes.Int))

    assert trace.ExpectedAtStep == "simple:int,simple:int"
    assert trace.Answer == "array(simple:int)"
    assert ArrayTypeName(harness.Ambient.CurrentExpectedType) == "array(simple:int)"
    harness.Ambient.ExitExpectedType(saved)
}

test "a targeted literal answers its TARGET even when every element disagrees" {
    harness := ArrayArmOf()
    saved := harness.Ambient.EnterExpectedType(new ArrayTypeInfo(BuiltInTypes.Int))
    trace := ArrayDrive(harness, ArrayLiteralOf(2), ArrayAnswers(BuiltInTypes.String))

    assert trace.Reports == 2
    assert trace.Answer == "array(simple:int)"
    assert harness.Errors[0].Message.Contains("Array element")
    assert harness.Errors[0].Message.Contains("the target array expects")
    harness.Ambient.ExitExpectedType(saved)
}

test "a COLLECTION target is scolded in collection words, not array words" {
    harness := ArrayArmOf()
    listTarget: TypeInfo = new ReflectionTypeInfo(ArrayClosedOf("System.Collections.Generic.List`1", typeof(int)))
    saved := harness.Ambient.EnterExpectedType(listTarget)
    trace := ArrayDrive(harness, ArrayLiteralOf(1), ArrayAnswers(BuiltInTypes.String))

    assert trace.Reports == 1
    assert harness.Errors[0].Message.Contains("Collection element")
    assert harness.Errors[0].Message.Contains("the target collection expects")

    // The ANSWER is still an ARRAY of the collection's element — the literal's own shape.
    assert trace.Answer == "array(reflection:Int32)"
    harness.Ambient.ExitExpectedType(saved)
}

// ---- the annotation decomposition ----------------------------------------------------------------

test "the element type is read from a collection FIRST and an array shape second" {
    harness := ArrayArmOf()
    elementType: TypeInfo = BuiltInTypes.Unknown
    targetKind := ""

    assert harness.Arm.TryGetExpectedElementType(new ArrayTypeInfo(BuiltInTypes.String), out elementType, out targetKind)
    assert ArrayTypeName(elementType) == "simple:string"
    assert targetKind == "array"

    // A collection target must carry a KNOWN RUNTIME generic definition — a bare same-named
    // `GenericTypeInfo` is a source type that merely looks like a list, and answering for it would let
    // any user type called `List` claim collection-literal semantics.
    bareList: TypeInfo = new GenericTypeInfo("List", ArrayOneArgument(BuiltInTypes.Int))
    assert !harness.Arm.TryGetExpectedElementType(bareList, out elementType, out targetKind)

    listTarget: TypeInfo = new ReflectionTypeInfo(ArrayClosedOf("System.Collections.Generic.List`1", typeof(int)))
    assert harness.Arm.TryGetExpectedElementType(listTarget, out elementType, out targetKind)
    assert ArrayTypeName(elementType) == "reflection:Int32"
    assert targetKind == "collection"
}

test "a REFLECTED array annotation decomposes, and a non-sequence annotation does not" {
    harness := ArrayArmOf()
    elementType: TypeInfo = BuiltInTypes.Unknown
    targetKind := ""

    reflectedArray: TypeInfo = new ReflectionTypeInfo(typeof(int[]))
    assert harness.Arm.TryGetExpectedElementType(reflectedArray, out elementType, out targetKind)
    assert targetKind == "array"

    assert !harness.Arm.TryGetExpectedElementType(BuiltInTypes.Int, out elementType, out targetKind)
    assert !harness.Arm.TryGetExpectedElementType(null, out elementType, out targetKind)
    assert targetKind == "array"
}

// ---- the collection-target rule ------------------------------------------------------------------

test "an IQueryable target is refused outright, by either shape" {
    harness := ArrayArmOf()
    targetName := ""

    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    queryable: TypeInfo = new GenericTypeInfo("IQueryable", arguments)
    assert harness.Arm.IsUnsupportedCollectionExpressionTarget(queryable, out targetName)

    reflectedQueryable: TypeInfo = new ReflectionTypeInfo(ArrayClosedQueryable())
    assert harness.Arm.IsUnsupportedCollectionExpressionTarget(reflectedQueryable, out targetName)
}

test "the four MATERIALISABLE shapes are accepted and `object` is not" {
    // An array; a concrete type with a single IEnumerable<T> constructor; a concrete type with a
    // parameterless constructor and an Add; and a supported interface.
    assert AnalyzerArrayLiteral.CanMaterializeReflectionCollectionExpressionTarget(typeof(int[]))
    assert AnalyzerArrayLiteral.CanMaterializeReflectionCollectionExpressionTarget(typeof(List<int>))
    assert AnalyzerArrayLiteral.CanMaterializeReflectionCollectionExpressionTarget(typeof(HashSet<int>))
    assert AnalyzerArrayLiteral.CanMaterializeReflectionCollectionExpressionTarget(ArrayClosedOf("System.Collections.Generic.Queue`1, System.Collections", typeof(int)))
    assert AnalyzerArrayLiteral.CanMaterializeReflectionCollectionExpressionTarget(typeof(IEnumerable<int>))
    assert AnalyzerArrayLiteral.CanMaterializeReflectionCollectionExpressionTarget(ArrayClosedOf("System.Collections.Generic.IReadOnlyList`1", typeof(int)))

    assert !AnalyzerArrayLiteral.CanMaterializeReflectionCollectionExpressionTarget(typeof(object))
    assert !AnalyzerArrayLiteral.CanMaterializeReflectionCollectionExpressionTarget(typeof(int))
}

test "the sequence element type is read from the type itself before its interfaces" {
    elementType: Type = typeof(object)

    assert AnalyzerArrayLiteral.TryGetReflectionCollectionExpressionElementType(typeof(int[]), out elementType)
    assert elementType == typeof(int)

    assert AnalyzerArrayLiteral.TryGetReflectionCollectionExpressionElementType(ArrayClosedOf("System.Collections.Generic.List`1", typeof(string)), out elementType)
    assert elementType == typeof(string)

    assert AnalyzerArrayLiteral.TryGetReflectionCollectionExpressionElementType(typeof(IEnumerable<bool>), out elementType)
    assert elementType == typeof(bool)

    assert !AnalyzerArrayLiteral.TryGetReflectionCollectionExpressionElementType(typeof(int), out elementType)
    assert elementType == typeof(object)
}

test "the supported INTERFACE list is exactly seven definitions" {
    assert AnalyzerArrayLiteral.IsSupportedCollectionExpressionInterfaceTarget(typeof(IEnumerable<int>))
    assert AnalyzerArrayLiteral.IsSupportedCollectionExpressionInterfaceTarget(ArrayClosedOf("System.Collections.Generic.ICollection`1", typeof(int)))
    assert AnalyzerArrayLiteral.IsSupportedCollectionExpressionInterfaceTarget(ArrayClosedOf("System.Collections.Generic.IList`1", typeof(int)))
    assert AnalyzerArrayLiteral.IsSupportedCollectionExpressionInterfaceTarget(ArrayClosedOf("System.Collections.Generic.IReadOnlyCollection`1", typeof(int)))
    assert AnalyzerArrayLiteral.IsSupportedCollectionExpressionInterfaceTarget(ArrayClosedOf("System.Collections.Generic.IReadOnlyList`1", typeof(int)))
    assert AnalyzerArrayLiteral.IsSupportedCollectionExpressionInterfaceTarget(ArrayClosedOf("System.Collections.Generic.ISet`1", typeof(int)))

    // A non-interface and an unrelated interface are both out.
    assert !AnalyzerArrayLiteral.IsSupportedCollectionExpressionInterfaceTarget(typeof(List<int>))
    assert !AnalyzerArrayLiteral.IsSupportedCollectionExpressionInterfaceTarget(Type.GetType("System.IDisposable"))
}

test "the mutator rule holds a VALUE element to identity and lets a REFERENCE element widen" {
    // `List<int>.Add(int)` matches for `int`; `List<object>.Add(object)` does NOT match for `int`,
    // because boxing every element is not what the literal asked for.
    assert AnalyzerArrayLiteral.HasCollectionExpressionMutator(typeof(List<int>), typeof(int))
    assert !AnalyzerArrayLiteral.HasCollectionExpressionMutator(ArrayClosedOf("System.Collections.Generic.List`1", typeof(object)), typeof(int))

    // A reference element may widen to `object`.
    assert AnalyzerArrayLiteral.HasCollectionExpressionMutator(ArrayClosedOf("System.Collections.Generic.List`1", typeof(object)), typeof(string))

    // `Enqueue` counts as a mutator, and a type with neither does not.
    assert AnalyzerArrayLiteral.HasCollectionExpressionMutator(ArrayClosedOf("System.Collections.Generic.Queue`1, System.Collections", typeof(int)), typeof(int))
    assert !AnalyzerArrayLiteral.HasCollectionExpressionMutator(typeof(int), typeof(int))
}

test "the constructor rules see a parameterless and a single-IEnumerable constructor" {
    assert AnalyzerArrayLiteral.HasParameterlessConstructor(typeof(List<int>))
    assert AnalyzerArrayLiteral.HasSingleEnumerableConstructor(typeof(List<int>), typeof(int))

    // The enumerable constructor must accept THIS element type.
    assert !AnalyzerArrayLiteral.HasSingleEnumerableConstructor(typeof(List<int>), typeof(string))
}

test "the open-definition name test is exact" {
    assert AnalyzerArrayLiteral.IsGenericDefinition(typeof(List<int>), "System.Collections.Generic.List`1")
    assert !AnalyzerArrayLiteral.IsGenericDefinition(typeof(List<int>), "System.Collections.Generic.IList`1")

    // A non-generic type has no definition name at all.
    assert AnalyzerArrayLiteral.GetGenericDefinitionFullName(typeof(int)) == null
    assert !AnalyzerArrayLiteral.IsGenericDefinition(typeof(int), "System.Collections.Generic.List`1")
}

test "an unsupported collection target reports FeatureNotImplemented and names the target" {
    harness := ArrayArmOf()
    queryable: TypeInfo = new ReflectionTypeInfo(ArrayClosedQueryable())

    harness.Arm.ReportUnsupportedCollectionExpressionTargetIfNeeded(ArrayLiteralOf(1), queryable)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message.Contains("Collection expressions for")
    assert harness.Errors[0].Message.Contains("are not implemented yet")
}

test "a SUPPORTED collection target reports nothing, and a missing annotation reports nothing" {
    harness := ArrayArmOf()

    harness.Arm.ReportUnsupportedCollectionExpressionTargetIfNeeded(ArrayLiteralOf(1), new ArrayTypeInfo(BuiltInTypes.Int))
    harness.Arm.ReportUnsupportedCollectionExpressionTargetIfNeeded(ArrayLiteralOf(1), null)
    assert harness.Errors.Count == 0
}

test "the unsupported-target report runs BEFORE any element is walked" {
    harness := ArrayArmOf()
    queryable: TypeInfo = new ReflectionTypeInfo(ArrayClosedQueryable())
    saved := harness.Ambient.EnterExpectedType(queryable)

    state := harness.Arm.Begin(ArrayLiteralOf(2))
    harness.Arm.NextStep(state)

    // One `NextStep` — no element has been answered yet — and the report has already landed.
    assert harness.Errors.Count == 1
    harness.Ambient.ExitExpectedType(saved)
}

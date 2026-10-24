namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

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

func RequiredArrayRuntimeType(typeName: string): Type {
    runtimeType := Type.GetType(typeName)
    if runtimeType == null {
        throw new InvalidOperationException("Required runtime type '" + typeName + "' was not found.")
    }

    return runtimeType
}

func ArrayClosedOf(definitionName: string, argument: Type): Type {
    // Several closed generics the collection-target rule is about are not on the columnar `typeof`
    // surface (`Queue<>` and the `System.Linq` interfaces above all), so they are built BY NAME — the
    // compiler's own route-around, yielding the identical runtime type.
    definition := RequiredArrayRuntimeType(definitionName)
    typeArguments := new Type[](1)
    typeArguments[0] = argument
    return definition.MakeGenericType(typeArguments)
}

func ArrayClosedQueryable(): Type {
    // `typeof(IQueryable<int>)` is not on the columnar `typeof` surface, so the closed type is built
    // by name — the compiler's own route-around, and the identical runtime type.
    definition := RequiredArrayRuntimeType("System.Linq.IQueryable`1, System.Linq.Expressions")
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

// AN EMPTY LITERAL WITH NOTHING TO BE IS NL203, on `default`'s rule. It still answers an array of
// unknown, so nothing downstream reports again; with no site open the hint is the general one.
test "an EMPTY literal with no annotation is NL203, and still answers an array of unknown" {
    harness := ArrayArmOf()
    trace := ArrayDrive(harness, ArrayLiteralOf(0), ArrayAnswers(BuiltInTypes.Int))

    assert trace.Steps == 0
    assert trace.Answer == "array(unknown)"
    assert ArrayCodes(harness.Errors) == "203"
    assert harness.Errors[0].Message == "I can't figure out what type of array '[]' is — it has no elements to infer from, and nothing here says what it should hold"
    assert harness.Errors[0].Suggestion == "Write the type where the value is declared, for example 'items: int[] = []'."
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 1
}

// THE HINT NAMES THE SITE when the literal IS the site's value, writes `...` when it is one arm of
// it, and falls back to the general hint when the literal is anywhere else under the site.
test "an EMPTY literal's hint names the local it was going to, and only when it is that local's value" {
    harness := ArrayArmOf()
    literal := ArrayLiteralOf(0)
    saved := harness.Ambient.EnterInferenceSite(new AmbientInferenceSite(literal, "scores", false, false))
    ArrayDrive(harness, literal, ArrayAnswers(BuiltInTypes.Int))
    harness.Ambient.ExitInferenceSite(saved)

    other := ArrayLiteralOf(1)
    arm := ArrayLiteralOf(0)
    conditional := new TernaryExpression(new IdentifierExpression("flag", 4, 1), arm, other, 4, 6)
    saved = harness.Ambient.EnterInferenceSite(new AmbientInferenceSite(conditional, "scores", false, true))
    ArrayDrive(harness, arm, ArrayAnswers(BuiltInTypes.Int))
    ArrayDrive(harness, ArrayLiteralOf(0), ArrayAnswers(BuiltInTypes.Int))
    harness.Ambient.ExitInferenceSite(saved)

    assert ArrayCodes(harness.Errors) == "203,203,203"
    assert harness.Errors[0].Suggestion == "Say what type 'scores' is, for example 'scores: int[] = []'."
    assert harness.Errors[1].Suggestion == "Say what type 'scores' is, for example 'let scores: int[] = ...'."
    assert harness.Errors[2].Suggestion == "Write the type where the value is declared, for example 'items: int[] = []'."
}

// AN ARGUMENT WHOSE CALLEE IS STILL CHOOSING IS NOT AN ABSENT TARGET — the parameter will say what the
// literal is — and a target that names no element type is the assignability judgement's to refuse.
test "an EMPTY literal is silent as a pending argument and under a target that is not a collection" {
    harness := ArrayArmOf()
    argument := ArrayLiteralOf(0)
    savedArgument := harness.Ambient.EnterPendingTargetArgument(argument)
    pending := ArrayDrive(harness, argument, ArrayAnswers(BuiltInTypes.Int))
    harness.Ambient.ExitPendingTargetArgument(savedArgument)

    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.Object)
    ArrayDrive(harness, ArrayLiteralOf(0), ArrayAnswers(BuiltInTypes.Int))
    harness.Ambient.ExitExpectedType(saved)

    assert pending.Answer == "array(unknown)"
    assert ArrayCodes(harness.Errors) == ""
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

// A FIRST ELEMENT WITH NO TYPE OF ITS OWN IS NOT A YARDSTICK. `[[], [1]]` already reported its empty
// `[]`; telling the reader that `int[]` is not `unknown[]` would be a second report about the same
// missing type, in words that name a type nobody wrote.
test "an inferred literal whose FIRST element is untyped does not accuse the rest" {
    harness := ArrayArmOf()
    answers := new List<TypeInfo>()
    answers.Add(new ArrayTypeInfo(BuiltInTypes.Unknown))
    answers.Add(new ArrayTypeInfo(BuiltInTypes.Int))
    trace := ArrayDrive(harness, ArrayLiteralOf(2), answers)

    assert trace.Steps == 2
    assert trace.Reports == 0
    assert AnalyzerArrayLiteral.IsUntypedAnswer(new ArrayTypeInfo(new ArrayTypeInfo(BuiltInTypes.Unknown)))
    assert !AnalyzerArrayLiteral.IsUntypedAnswer(new ArrayTypeInfo(BuiltInTypes.Int))
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

// The annotation `System.Collections.Generic.List<string>` and the imported `List<string>` are ONE
// type, so they are one target: the decomposition reads the head the definition proved, and the
// literal's elements are walked expecting `string` in collection words under either spelling.
test "a namespace-qualified collection annotation decomposes exactly as the imported spelling" {
    harness := ArrayArmOf()
    elementType: TypeInfo = BuiltInTypes.Unknown
    targetKind := ""

    listDefinition: TypeInfo = new ReflectionTypeInfo(RequiredArrayRuntimeType("System.Collections.Generic.List`1"))
    qualifiedList: TypeInfo = new GenericTypeInfo("System.Collections.Generic.List", ArrayOneArgument(BuiltInTypes.String), listDefinition)
    assert harness.Arm.TryGetExpectedElementType(qualifiedList, out elementType, out targetKind)
    assert ArrayTypeName(elementType) == "simple:string"
    assert targetKind == "collection"

    nullableQualified: TypeInfo = new NullableTypeInfo(qualifiedList)
    assert harness.Arm.TryGetExpectedElementType(nullableQualified, out elementType, out targetKind)
    assert targetKind == "collection"

    // The EMPTY literal answers the target's element type, not `unknown`, under the qualified
    // spelling too — the shape whose `unknown[]` used to be refused against its own annotation.
    saved := harness.Ambient.EnterExpectedType(qualifiedList)
    trace := ArrayDrive(harness, ArrayLiteralOf(0), ArrayOneArgument(BuiltInTypes.String))
    harness.Ambient.ExitExpectedType(saved)
    assert trace.Answer == "array(simple:string)"
    assert trace.Reports == 0
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

test "A TARGET THAT MAY BE NULL IS STILL A TARGET" {
    harness := ArrayArmOf()
    elementType: TypeInfo = BuiltInTypes.Unknown
    targetKind := ""

    // `values: object?[]? = ["a", 1]` and `MethodInfo.Invoke`'s `object?[]?` parameter both name an
    // element type: the `?` says the ARRAY may be absent, not that its elements are unknown. Without
    // the shell being looked through, the literal was inferred from its first element and then
    // refused against the very slot it was written into.
    nullableArray: TypeInfo = new NullableTypeInfo(new ArrayTypeInfo(BuiltInTypes.String))
    assert harness.Arm.TryGetExpectedElementType(nullableArray, out elementType, out targetKind)
    assert ArrayTypeName(elementType) == "simple:string"
    assert targetKind == "array"

    // A nullable COLLECTION answers the same way, and in collection words.
    nullableList: TypeInfo = new NullableTypeInfo(new ReflectionTypeInfo(ArrayClosedOf("System.Collections.Generic.List`1", typeof(int))))
    assert harness.Arm.TryGetExpectedElementType(nullableList, out elementType, out targetKind)
    assert ArrayTypeName(elementType) == "reflection:Int32"
    assert targetKind == "collection"

    // The shell is looked through ONCE, and a nullable non-sequence is still not a target.
    nullableInt: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    assert !harness.Arm.TryGetExpectedElementType(nullableInt, out elementType, out targetKind)
}

// ---- the collection-target rule ------------------------------------------------------------------

test "an IQueryable target is refused outright, by either shape" {
    harness := ArrayArmOf()
    targetName := ""

    queryableDefinition: TypeInfo = new ReflectionTypeInfo(RequiredArrayRuntimeType("System.Linq.IQueryable`1, System.Linq.Expressions"))
    queryable: TypeInfo = new GenericTypeInfo("IQueryable", ArrayOneArgument(BuiltInTypes.Int), queryableDefinition)
    assert harness.Arm.IsUnsupportedCollectionExpressionTarget(queryable, out targetName)

    // The generic shape is judged by the definition it proved, so the spelled-out name is the same
    // refusal and a program's own `IQueryable<T>` — no runtime definition — is not this one.
    qualifiedQueryable: TypeInfo = new GenericTypeInfo("System.Linq.IQueryable", ArrayOneArgument(BuiltInTypes.Int), queryableDefinition)
    assert harness.Arm.IsUnsupportedCollectionExpressionTarget(qualifiedQueryable, out targetName)
    sourceQueryable: TypeInfo = new GenericTypeInfo("IQueryable", ArrayOneArgument(BuiltInTypes.Int))
    assert !harness.Arm.IsUnsupportedCollectionExpressionTarget(sourceQueryable, out targetName)

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
    disposableType := Type.GetType("System.IDisposable")
    if disposableType == null {
        throw new InvalidOperationException("System.IDisposable must exist in the loaded runtime.")
    }

    assert !AnalyzerArrayLiteral.IsSupportedCollectionExpressionInterfaceTarget(disposableType)
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

// ---- end to end over real source ------------------------------------------------------------------

// THE FRAMEWORK IS LOADED, because every target here is a runtime collection: a bare `Analyzer` has no
// reference assemblies, so `System.Collections.Generic` would be NL704 and no spelling would resolve.
func ArrayLiteralSourceErrors(source: string): string {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-array-literal-" + Guid.NewGuid().ToString("N"))
    filePath := Path.Combine(projectRoot, "Probe.nl")
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    assert parsed.Errors.Count == 0
    unit := parsed.CompilationUnit
    assert unit != null
    Directory.CreateDirectory(projectRoot)
    analyzer := new Analyzer()
    report := ""
    try {
        analyzer.LoadSystemAssemblies()
        result := analyzer.Analyze(unit, filePath, projectRoot, source)
        for error in result.Errors {
            if error.Severity == ErrorSeverity.Error {
                codeValue: int = (int)error.Code
                report = report + "[" + error.Line.ToString() + "] NL" + codeValue.ToString() + " " + error.Message + " | "
            }
        }
    } finally {
        analyzer.Dispose()
        Directory.Delete(projectRoot, true)
    }

    return report
}

// THE SPELLING OF A COLLECTION TARGET NEVER DECIDES WHETHER A LITERAL FITS IT. Every position a
// literal is target-typed from — an annotated local, an assignment, an object-initializer member, an
// argument, a return and a field default — is written three ways (imported, namespace-qualified and
// through a namespace alias), and each one is clean. Before the head was read from the definition,
// every qualified line here was `NL202` with "but the value is 'string[]'" or "'unknown[]'".
test "a collection literal fits its target however the target type is spelled" {
    report := ArrayLiteralSourceErrors("namespace Probe\n\nimport System.Collections.Generic\nimport System.Collections.Generic as Scg\n\nclass ImportedBasket { Items: List<string> }\nclass QualifiedBasket {\n    Items: System.Collections.Generic.List<string>\n    Tags: System.Collections.Generic.HashSet<int>\n    Names: System.Collections.Generic.IEnumerable<string>\n    Defaulted: System.Collections.Generic.List<string> = [\"d\"]\n}\nclass AliasedBasket { Items: Scg.List<string> }\n\nfunc TakeQualified(xs: System.Collections.Generic.List<string>): int => xs.Count\nfunc TakeAliased(xs: Scg.IReadOnlyList<int>): int => xs.Count\nfunc MakeQualified(): System.Collections.Generic.List<string> {\n    return []\n}\n\nfunc Use(): int {\n    a: List<string> = []\n    b: System.Collections.Generic.List<string> = []\n    c: System.Collections.Generic.List<string> = [\"x\", \"y\"]\n    d: Scg.List<string> = [\"z\"]\n    e: System.Collections.Generic.HashSet<int> = []\n    f: System.Collections.Generic.Queue<int> = [1, 2]\n    g: System.Collections.Generic.IEnumerable<string> = []\n    h: HashSet<int> = []\n    i: IEnumerable<string> = []\n    widened: System.Collections.Generic.IEnumerable<string> = c\n    imported := new ImportedBasket { Items: [] }\n    qualified := new QualifiedBasket { Items: [], Tags: [1, 2], Names: [] }\n    aliased := new AliasedBasket { Items: [\"q\"] }\n    assigned := new QualifiedBasket()\n    assigned.Items = [\"a\"]\n    assigned.Tags = []\n    total := a.Count + b.Count + c.Count + d.Count + e.Count + f.Count + h.Count\n    total = total + imported.Items.Count + qualified.Items.Count + aliased.Items.Count + assigned.Items.Count\n    total = total + TakeQualified([\"m\", \"n\"]) + TakeAliased([1]) + MakeQualified().Count\n    for item in g { total = total + item.Length }\n    for item in i { total = total + item.Length }\n    for item in widened { total = total + item.Length }\n    return total\n}\n")
    assert report == ""
}

// A wrong ELEMENT is still refused under the qualified spelling, in collection words — reading the
// head semantically widened which spellings are targets, not what a target accepts.
test "a qualified collection target still refuses an element of the wrong type" {
    report := ArrayLiteralSourceErrors("namespace Probe\n\nfunc Use(): int {\n    xs: System.Collections.Generic.List<string> = [1]\n    return xs.Count\n}\n")
    assert report == "[4] NL202 Collection element is 'int', but the target collection expects 'string' | "
}

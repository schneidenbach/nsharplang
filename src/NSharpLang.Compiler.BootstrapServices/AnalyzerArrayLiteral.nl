namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// THE ONE STEP AN ARRAY LITERAL TAKES, TAKEN ONCE PER ELEMENT.
//
// `[a, b, c]` has as many operands as it has elements and every one of them is walked by the ordinary
// expression dispatch, so the walk has ONE kind performed N times. What differs between the two forms
// is not the operation but the AMBIENT SLOT: when the surrounding annotation names an element type,
// every element is walked expecting it, and that bracket is opened and closed by THIS OWNER around
// the step it hands out; when nothing names one, the FIRST element decides and no element is walked
// under an expected type at all.
//
//   1  analyse an ELEMENT expression, bracketed by the expected element type when there is one.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class ArrayLiteralRequest {
    Kind: int
    Node: Expression?

    constructor(kind: int, node: Expression?) {
        Kind = kind
        Node = node
    }
}

// THE WHOLE STATE, SUSPENDED ACROSS ONE STEP PER ELEMENT.
//
// `Phase` runs 0 (nothing asked) → 10 (ready to hand out the next element) → 11 (an element step is
// outstanding) → 99 (finished). `Mode` is 1 when the surrounding annotation named an element type and
// 2 when the first element decides; it is settled at phase 0 and never changes, because the C#
// branched ONCE on the expected type and then never re-read it.
//
// `ExpectedElementType` and `TargetKind` are the annotation's decomposition; `FirstType` is what mode
// 2 measures every later element against. `SavedExpectedType` holds the slot's previous value and is
// non-null only while a mode-1 step is outstanding.
class ArrayLiteralState {
    arrayValue: ArrayLiteralExpression?

    Array: ArrayLiteralExpression? => arrayValue

    Phase: int
    Mode: int
    ElementIndex: int
    ResultType: TypeInfo
    ExpectedElementType: TypeInfo?
    TargetKind: string
    FirstType: TypeInfo
    SavedExpectedType: TypeInfo?

    constructor(array: ArrayLiteralExpression?) {
        arrayValue = array
        Phase = 0
        Mode = 0
        ElementIndex = 0
        ResultType = BuiltInTypes.Unknown
        ExpectedElementType = null
        TargetKind = "array"
        FirstType = BuiltInTypes.Unknown
        SavedExpectedType = null
    }
}

// WHAT AN ARRAY LITERAL MEANS — the whole of the expression walk's `array` arm, the element type it
// answers, and the two things it refuses.
//
// THE TWO FORMS ARE DECIDED BY THE ANNOTATION, ONCE:
//   * TARGETED. `xs: int[] = [1, 2]` and `xs: List<int> = [1, 2]` both name an element type, and the
//     literal answers THAT type's array regardless of what its elements turned out to be. Each
//     element is walked expecting it, and one that does not fit is reported with the label the target
//     earned — "Collection element" for a collection literal, "Array element" for an array — because
//     a developer writing a `List<T>` literal is not writing an array and should not be told they
//     are.
//   * INFERRED. `xs := [1, 2]` has no annotation, so the FIRST element decides and every later one is
//     measured against it. No element is walked under an expected type, which is why a lambda inside
//     an inferred literal has nothing to infer from.
// An EMPTY literal answers before either form: `[]` is an array of whatever was expected, or of
// `unknown`, and it takes no steps at all.
//
// THE ONE CODE IT OWNS IS NL202, in two shapes — an element that does not fit the target and an
// element that does not fit the first — plus NL903's FeatureNotImplemented for a collection target
// the backend cannot materialise. WHAT IT DOES NOT OWN: both SoA escapes, which are
// `AnalyzerSoaEscape`'s and are merely asked, once per element, in the order the C# asked them.
//
// THE COLLECTION-TARGET RULE MOVES WHOLE, AND IT IS THE LARGER HALF OF THIS OWNER. Whether a
// collection expression's target can be MATERIALISED — an array, a type with a single
// `IEnumerable<T>` constructor, a type with a parameterless constructor and an `Add`/`Enqueue`, or one
// of the six supported interfaces plus anything `List<T>`, `HashSet<T>` or `Queue<T>` satisfies — is
// seventeen members of pure reflection predicate, every one of them exclusive to this arm by
// caller attribution. It moves rather than staying behind because a report the arm raises is the
// arm's, and because leaving it would have made the move a callback.
class AnalyzerArrayLiteral {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    declarationContextValue: AnalyzerDeclarationContext
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape
    assignabilityValue: AnalyzerAssignability
    assignabilityFactsValue: AnalyzerAssignabilityFacts

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, declarationContext: AnalyzerDeclarationContext, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape, assignability: AnalyzerAssignability, assignabilityFacts: AnalyzerAssignabilityFacts) {
        diagnosticsValue = diagnostics
        spansValue = spans
        declarationContextValue = declarationContext
        ambientValue = ambient
        soaEscapeValue = soaEscape
        assignabilityValue = assignability
        assignabilityFactsValue = assignabilityFacts
    }

    func Begin(expression: Expression): ArrayLiteralState {
        array := expression as ArrayLiteralExpression
        state := new ArrayLiteralState(array)
        if array == null {
            state.Phase = 99
        }

        return state
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    //
    // Phase 0 does everything that happens before the first element: the annotation is decomposed,
    // the unsupported-target report runs, and an empty literal answers outright. Both reads of the
    // expected-type slot happen HERE, in the order the C# read them.
    func NextStep(state: ArrayLiteralState): ArrayLiteralRequest? {
        node := state.Array
        if node == null {
            state.Phase = 99
            return null
        }

        if state.Phase == 0 {
            BeginWalk(state, node)
        }

        if state.Phase != 10 {
            return null
        }

        if state.ElementIndex >= node.Elements.Count {
            FinishWalk(state)
            return null
        }

        element := node.Elements[state.ElementIndex]
        state.Phase = 11
        if state.Mode == 1 {
            state.SavedExpectedType = ambientValue.EnterExpectedType(state.ExpectedElementType)
        }

        return new ArrayLiteralRequest(1, element)
    }

    func BeginWalk(state: ArrayLiteralState, node: ArrayLiteralExpression) {
        expectedElementType: TypeInfo = BuiltInTypes.Unknown
        targetKind := "array"
        hasExpectedElement := TryGetExpectedElementType(ambientValue.CurrentExpectedType, out expectedElementType, out targetKind)
        ReportUnsupportedCollectionExpressionTargetIfNeeded(node, ambientValue.CurrentExpectedType)

        if node.Elements.Count == 0 {
            emptyElement: TypeInfo = BuiltInTypes.Unknown
            if hasExpectedElement {
                emptyElement = expectedElementType
            }

            answered: TypeInfo = new ArrayTypeInfo(emptyElement)
            state.ResultType = answered
            state.Phase = 99
            return
        }

        if hasExpectedElement {
            state.Mode = 1
            state.ExpectedElementType = expectedElementType
            state.TargetKind = targetKind
        } else {
            state.Mode = 2
        }

        state.Phase = 10
    }

    // THE ANSWER TO THE OUTSTANDING ELEMENT. The bracket closes FIRST, before the two escape reports
    // and the assignability judgement, which is the order `Analyzer.cs` used and the reason it matters
    // is that a report is free to look at the ambient context.
    func Supply(state: ArrayLiteralState, answer: TypeInfo?) {
        if state.Phase != 11 {
            return
        }

        node := state.Array
        if node == null {
            state.Phase = 99
            return
        }

        if state.Mode == 1 {
            ambientValue.ExitExpectedType(state.SavedExpectedType)
            state.SavedExpectedType = null
        }

        elementType: TypeInfo = BuiltInTypes.Unknown
        if answer != null {
            elementType = answer
        }

        element := node.Elements[state.ElementIndex]
        if state.Mode == 1 {
            storageContext := "stored in an array"
            elementLabel := "Array element"
            if state.TargetKind == "collection" {
                storageContext = "stored in a collection literal"
                elementLabel = "Collection element"
            }

            soaEscapeValue.ReportSoaRowEscapeIfNeeded(element, elementType, storageContext)
            soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(element, storageContext)
            expected := state.ExpectedElementType
            if expected != null && !assignabilityValue.IsAssignable(expected, elementType) {
                span := spansValue.GetExpressionDiagnosticSpan(element)
                diagnosticsValue.Report(ErrorCode.TypeMismatch, elementLabel + " is '" + TypeText(elementType) + "', but the target " + state.TargetKind + " expects '" + TypeText(expected) + "'", span.Line, span.Column, null, span.Length)
            }
        } else {
            soaEscapeValue.ReportSoaRowEscapeIfNeeded(element, elementType, "stored in an array")
            soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(element, "stored in an array")
            if state.ElementIndex == 0 {
                state.FirstType = elementType
            } else if !assignabilityValue.IsAssignable(state.FirstType, elementType) {
                span := spansValue.GetExpressionDiagnosticSpan(element)
                diagnosticsValue.Report(ErrorCode.TypeMismatch, "All elements in an array must be the same type — the first element is '" + TypeText(state.FirstType) + "' but I found '" + TypeText(elementType) + "'", span.Line, span.Column, null, span.Length)
            }
        }

        state.ElementIndex = state.ElementIndex + 1
        state.Phase = 10
    }

    // A TARGETED LITERAL IS ITS TARGET'S ELEMENT TYPE, AND AN INFERRED ONE IS ITS FIRST ELEMENT'S —
    // whatever the later elements turned out to be. An element that did not fit was already reported;
    // widening the answer to accommodate it would hide the report.
    func FinishWalk(state: ArrayLiteralState) {
        state.Phase = 99
        decided: TypeInfo = BuiltInTypes.Unknown
        if state.Mode == 1 {
            expected := state.ExpectedElementType
            if expected != null {
                decided = expected
            }
        } else {
            decided = state.FirstType
        }

        answered: TypeInfo = new ArrayTypeInfo(decided)
        state.ResultType = answered
    }

    func Result(state: ArrayLiteralState): TypeInfo {
        return state.ResultType
    }

    // WHAT THE SURROUNDING ANNOTATION EXPECTS OF ONE ELEMENT, and which WORD to call the target in a
    // report. A collection target is asked FIRST, because an array is also a collection to the
    // assignability facts and the array shape must not claim a `List<T>`'s literal.
    //
    // PUBLISHED, because the object-initializer walk decomposes the same annotation for the same
    // reason.
    func TryGetExpectedElementType(expectedType: TypeInfo?, out elementType: TypeInfo, out targetKind: string): bool {
        elementType = BuiltInTypes.Unknown
        targetKind = "array"
        if expectedType == null {
            return false
        }

        resolvedExpectedType := declarationContextValue.ResolveDeclaredAlias(expectedType)
        collectionElementType: TypeInfo = BuiltInTypes.Unknown
        if assignabilityFactsValue.TryGetCollectionElementType(resolvedExpectedType, out collectionElementType) {
            elementType = collectionElementType
            targetKind = "collection"
            return true
        }

        arrayType := resolvedExpectedType as ArrayTypeInfo
        if arrayType != null {
            elementType = arrayType.ElementType
            targetKind = "array"
            return true
        }

        reflectionType := resolvedExpectedType as ReflectionTypeInfo
        if reflectionType != null && reflectionType.Type.get_IsArray() {
            reflectedElement := reflectionType.Type.GetElementType()
            if reflectedElement != null {
                elementType = AnalyzerReflectionTypeConversion.ConvertReflectionType(reflectedElement)
                targetKind = "array"
                return true
            }
        }

        return false
    }

    // A COLLECTION EXPRESSION WHOSE TARGET THE BACKEND CANNOT BUILD IS SAID SO, BY NAME, BEFORE ANY
    // ELEMENT IS WALKED. It is a FeatureNotImplemented and not a type error, because the literal the
    // developer wrote is well-formed and it is the compiler that is not ready.
    func ReportUnsupportedCollectionExpressionTargetIfNeeded(node: ArrayLiteralExpression, expectedType: TypeInfo?) {
        if expectedType == null {
            return
        }

        resolvedExpectedType := declarationContextValue.ResolveDeclaredAlias(expectedType)
        targetName := ""
        if !IsUnsupportedCollectionExpressionTarget(resolvedExpectedType, out targetName) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(node)
        diagnosticsValue.Report(ErrorCode.FeatureNotImplemented, "Collection expressions for '" + targetName + "' are not implemented yet", span.Line, span.Column, "Use an array, List<T>, HashSet<T>, Queue<T>, or construct the queryable value explicitly.", span.Length)
    }

    // AN `IQueryable` IS ALWAYS REFUSED — a collection literal has no provider to query — and any
    // other reflected sequence target is refused only when it cannot be MATERIALISED.
    func IsUnsupportedCollectionExpressionTarget(candidate: TypeInfo, out targetName: string): bool {
        targetName = TypeText(candidate)

        genericType := candidate as GenericTypeInfo
        if genericType != null {
            return genericType.Name == "IQueryable"
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType == null {
            return false
        }

        reflected := reflectionType.Type
        if IsIQueryableType(reflected) {
            return true
        }

        return IsReflectionCollectionExpressionTarget(reflected) && !CanMaterializeReflectionCollectionExpressionTarget(reflected)
    }

    static func IsIQueryableType(candidate: Type): bool {
        return IsGenericDefinition(candidate, "System.Linq.IQueryable`1")
    }

    static func IsReflectionCollectionExpressionTarget(candidate: Type): bool {
        elementType: Type = typeof(object)
        return TryGetReflectionCollectionExpressionElementType(candidate, out elementType)
    }

    // THE FOUR WAYS A COLLECTION TARGET CAN BE BUILT. `object` is refused outright, an array is always
    // buildable, a CONCRETE type needs either a single-`IEnumerable<T>` constructor or a
    // parameterless constructor plus an `Add`/`Enqueue`, and an INTERFACE needs to be one of the six
    // supported shapes or to be satisfiable by `List<T>`, `HashSet<T>` or `Queue<T>`.
    static func CanMaterializeReflectionCollectionExpressionTarget(targetType: Type): bool {
        if targetType == typeof(object) {
            return false
        }

        if targetType.get_IsArray() {
            return true
        }

        elementType: Type = typeof(object)
        if !TryGetReflectionCollectionExpressionElementType(targetType, out elementType) {
            return false
        }

        if !targetType.get_IsInterface() && !targetType.get_IsAbstract() {
            return HasSingleEnumerableConstructor(targetType, elementType) || (HasParameterlessConstructor(targetType) && HasCollectionExpressionMutator(targetType, elementType))
        }

        // `Queue<T>` is reached by NAME rather than by `typeof`: the columnar `typeof` surface is a
        // closed list that carries `List<>` and `HashSet<>` but not `Queue<>`. The spelling is the
        // compiler's own — an assembly-qualified open definition — and it yields the identical runtime
        // definition, so the three checks stay one rule.
        queueDefinition := Type.GetType("System.Collections.Generic.Queue`1, System.Collections")
        return IsSupportedCollectionExpressionInterfaceTarget(targetType) || IsAssignableFromConstructed(targetType, typeof(List<int>).GetGenericTypeDefinition(), elementType) || IsAssignableFromConstructed(targetType, typeof(HashSet<int>).GetGenericTypeDefinition(), elementType) || (queueDefinition != null && IsAssignableFromConstructed(targetType, queueDefinition, elementType))
    }

    // THE ELEMENT TYPE OF ANY SEQUENCE SHAPE, THE TYPE ITSELF FIRST AND THEN ITS INTERFACES. An array
    // answers from its element type without looking at an interface at all, which is what makes
    // `int[]` answer `int` rather than whichever `IEnumerable<T>` it happens to implement first.
    static func TryGetReflectionCollectionExpressionElementType(candidate: Type, out elementType: Type): bool {
        elementType = typeof(object)
        if candidate.get_IsArray() {
            arrayElement := candidate.GetElementType()
            if arrayElement != null {
                elementType = arrayElement
            }

            return true
        }

        if TryReadSequenceElementType(candidate, out elementType) {
            return true
        }

        interfaces := candidate.GetInterfaces()
        for interfaceType in interfaces {
            if TryReadSequenceElementType(interfaceType, out elementType) {
                return true
            }
        }

        elementType = typeof(object)
        return false
    }

    // ONE CANDIDATE OF THE SEQUENCE WALK. The eight recognised definitions are the synchronous and
    // asynchronous sequence and enumerator shapes; anything else contributes nothing and the walk
    // moves on.
    static func TryReadSequenceElementType(candidate: Type, out elementType: Type): bool {
        elementType = typeof(object)
        if !candidate.get_IsGenericType() {
            return false
        }

        if !IsGenericDefinition(candidate, "System.Collections.Generic.IEnumerable`1") && !IsGenericDefinition(candidate, "System.Collections.Generic.ICollection`1") && !IsGenericDefinition(candidate, "System.Collections.Generic.IList`1") && !IsGenericDefinition(candidate, "System.Collections.Generic.IReadOnlyCollection`1") && !IsGenericDefinition(candidate, "System.Collections.Generic.IReadOnlyList`1") && !IsGenericDefinition(candidate, "System.Collections.Generic.IEnumerator`1") && !IsGenericDefinition(candidate, "System.Collections.Generic.IAsyncEnumerable`1") && !IsGenericDefinition(candidate, "System.Collections.Generic.IAsyncEnumerator`1") {
            return false
        }

        arguments := candidate.GetGenericArguments()
        if arguments.Length == 0 {
            return false
        }

        elementType = arguments[0]
        return true
    }

    static func HasParameterlessConstructor(targetType: Type): bool {
        flags := BindingFlags.Public | BindingFlags.Instance
        constructors := targetType.GetConstructors(flags)
        for constructor in constructors {
            if constructor.GetParameters().Length == 0 {
                return true
            }
        }

        return false
    }

    static func HasSingleEnumerableConstructor(targetType: Type, elementType: Type): bool {
        flags := BindingFlags.Public | BindingFlags.Instance
        constructors := targetType.GetConstructors(flags)
        for constructor in constructors {
            parameters := constructor.GetParameters()
            if parameters.Length == 1 {
                parameter := parameters[0]
                parameterType := parameter.get_ParameterType()
                if IsGenericDefinition(parameterType, "System.Collections.Generic.IEnumerable`1") && AnalyzerConversionFacts.IsReflectionAssignableFrom(parameterType, ConstructEnumerableOf(elementType)) {
                    return true
                }
            }
        }

        return false
    }

    // AN `Add` OR AN `Enqueue` THAT TAKES EXACTLY THE ELEMENT. A VALUE element must match by
    // IDENTITY — `List<int>.Add(int)` is a mutator for `int` and `List<object>.Add(object)` is not,
    // because boxing every element is not what the literal asked for — while a REFERENCE element may
    // widen.
    static func HasCollectionExpressionMutator(targetType: Type, elementType: Type): bool {
        flags := BindingFlags.Public | BindingFlags.Instance
        methods := targetType.GetMethods(flags)
        for method in methods {
            name := method.get_Name()
            if name == "Add" || name == "Enqueue" {
                parameters := method.GetParameters()
                if parameters.Length == 1 {
                    parameter := parameters[0]
                    parameterType := parameter.get_ParameterType()
                    if elementType.get_IsValueType() {
                        if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(parameterType, elementType) {
                            return true
                        }
                    } else if AnalyzerConversionFacts.IsReflectionAssignableFrom(parameterType, elementType) {
                        return true
                    }
                }
            }
        }

        return false
    }

    static func IsSupportedCollectionExpressionInterfaceTarget(targetType: Type): bool {
        if !targetType.get_IsInterface() {
            return false
        }

        definitionName := GetGenericDefinitionFullName(targetType)
        if definitionName == null {
            return false
        }

        return definitionName == "System.Collections.Generic.IEnumerable`1" || definitionName == "System.Collections.Generic.ICollection`1" || definitionName == "System.Collections.Generic.IList`1" || definitionName == "System.Collections.Generic.IReadOnlyCollection`1" || definitionName == "System.Collections.Generic.IReadOnlyList`1" || definitionName == "System.Collections.Generic.ISet`1" || definitionName == "System.Collections.Generic.IReadOnlySet`1"
    }

    // THE OPEN DEFINITION'S NAME, BY STRING. `Analyzer.cs` compared it against `typeof(IQueryable<>)`
    // and friends; the name is the same comparison without needing an open generic `typeof`, which the
    // columnar surface does not carry.
    static func IsGenericDefinition(candidate: Type, openGenericFullName: string): bool {
        definitionName := GetGenericDefinitionFullName(candidate)
        return definitionName != null && definitionName == openGenericFullName
    }

    static func GetGenericDefinitionFullName(candidate: Type): string? {
        if !candidate.get_IsGenericType() {
            return null
        }

        return candidate.GetGenericTypeDefinition().get_FullName()
    }

    static func IsAssignableFromConstructed(targetType: Type, definition: Type, elementType: Type): bool {
        typeArguments := new Type[](1)
        typeArguments[0] = elementType
        return targetType.IsAssignableFrom(definition.MakeGenericType(typeArguments))
    }

    static func ConstructEnumerableOf(elementType: Type): Type {
        definition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
        typeArguments := new Type[](1)
        typeArguments[0] = elementType
        return definition.MakeGenericType(typeArguments)
    }

    // A `TypeInfo`'s display text. It is read through `object` because the columnar surface does not
    // model `ToString` on the model types directly — the estate's standing idiom, four owners over.
    static func TypeText(candidate: TypeInfo): string {
        boxed := candidate as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}

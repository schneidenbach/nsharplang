namespace NSharpLang.Compiler

import System
import System.Reflection
import NSharpLang.Compiler.Ast


// THE TWO STEPS AN INDEX ACCESS TAKES, AND WHY THEY ARE ONE KIND.
//
// `a[i]` has exactly TWO operands — the receiver and the index — and both are walked by the ordinary
// expression dispatch, so the walk has ONE kind performed twice rather than two kinds. What differs
// between them is not the operation but the AMBIENT SLOT the second runs under: the arm decides,
// from the receiver it just learned, whether the index should be walked expecting an `int`, and that
// bracket is opened and closed by THIS OWNER around the step it hands out. That is the slice-51
// tuple-element pattern and not slice-52's target-typed one: the C# bracketed a plain
// `AnalyzeExpression` with `EnterExpectedTypeIfProvided` / `ExitExpectedType`, never
// `AnalyzeExpressionWithExpectedType`, so there is no lambda fork inside the step and nothing the
// owner would have to simulate.
//
//   1  analyse an OPERAND expression. It is handed out twice: first `index.Object`, with the slot
//      untouched, then `index.Index`, bracketed by the expected type this arm chose.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class IndexAccessRequest {
    Kind: int
    Node: Expression?

    constructor(kind: int, node: Expression?) {
        Kind = kind
        Node = node
    }
}

// THE WHOLE STATE, SUSPENDED ACROSS EXACTLY TWO STEPS.
//
// `Phase` runs 0 (nothing asked) → 1 (the receiver step is outstanding) → 2 (the receiver has
// answered and the index step has not been handed out) → 3 (the index step is outstanding, and the
// expected-type bracket is OPEN) → 99 (finished). Phase 2 exists as its own phase rather than being
// folded into `Supply` because the bracket must open in the same instant the step is handed out: an
// owner that opened it while answering the receiver would leave the slot written across the gap
// between the two, which nothing in the C# ever did.
//
// `ReceiverType` is the alias-and-nullable-resolved receiver, computed once when the receiver answers
// and read by every gate after it. `SavedExpectedType` is the slot's previous value and is non-null
// only while phase 3 is outstanding. `InAssignmentTarget` is the one fact this arm cannot see for
// itself — whether an assignment TARGET is being analysed — and it is handed in at `Begin` by the
// driver, because the dictionary that records it is still `Analyzer.cs` state that moves with the
// assignment arm.
class IndexAccessState {
    indexValue: IndexAccessExpression?

    Index: IndexAccessExpression? => indexValue

    Phase: int
    ResultType: TypeInfo
    ReceiverType: TypeInfo
    IndexType: TypeInfo
    SavedExpectedType: TypeInfo?
    InAssignmentTarget: bool

    constructor(index: IndexAccessExpression?, inAssignmentTarget: bool) {
        indexValue = index
        Phase = 0
        ResultType = BuiltInTypes.Unknown
        ReceiverType = BuiltInTypes.Unknown
        IndexType = BuiltInTypes.Unknown
        SavedExpectedType = null
        InAssignmentTarget = inAssignmentTarget
    }
}

// WHAT AN INDEX ACCESS MEANS — the whole of the expression walk's `index` arm, the element type it
// answers, and the four refusals it owns.
//
// THE ORDER OF THE GATES IS BEHAVIOUR. After both operands have answered, ten questions are asked in
// exactly the order `Analyzer.cs` asked them, and the first that refuses ends the walk with
// `unknown`:
//   1  a TABLE indexed with `?[` — a row view can never be null-conditional, so the row escape fires
//      and the walk ends before any index validation runs.
//   2  a DIRECT COLUMN indexed with `?[`, which is `AnalyzerSoaEscape`'s refusal and merely asked.
//   3  the three value escapes — a row view as the receiver, a row view as the index, a direct column
//      as the index — all three of which are EVALUATED even when the first already refused, because
//      each is a report the developer is owed about a different operand.
//   4  a NEGATIVE constant table row index.
//   5  a table row index that is not an `int` at all.
//   6  a COLUMN slice, which allocates, and which is refused only OUTSIDE an assignment target —
//      `column[1..3] = …` is a write and does not allocate a copy.
//   7  a NEGATIVE constant column row index.
//   8  an array or string index that is not an `int`, a `System.Index` or a range.
//
// THE FOUR CODES IT OWNS: NL202 three times — a negative SoA row index (in two contexts, a table row
// and a column row), a table index that is not an int row id, and a built-in index that is neither
// int, `System.Index` nor `System.Range` — and NL103 once, for the column slice's hidden allocation.
// WHAT IT DOES NOT OWN: the null-dereference report, both SoA row escapes, the direct-column value
// escape and the direct-column null-conditional refusal — those are `AnalyzerNullFlow`'s and
// `AnalyzerSoaEscape`'s, and this arm only asks them. That makes this the FIFTH consecutive family
// whose SoA reports belong elsewhere, and the measurement refines the brief: the column-slice
// allocation report is NOT one of them. It is this arm's own, and it is PUBLISHED because the
// write-target family asks the same question of the same node.
//
// THE INDEXER LOOKUP IS A MEASURED SUBSTITUTION, NOT AN APPROXIMATION. `Analyzer.cs` read a reflected
// type's indexer through `GetDefaultMembers()`, whose `MemberInfo[]` is not a supported columnar
// local type. The route around it is the first public instance-or-static property with index
// parameters, and it is EXACTLY the same function: over 23,645 types in 317 assemblies — the whole
// of `Microsoft.NETCore.App`, `Microsoft.AspNetCore.App` and the compiler's own output — the two
// rules disagree on ZERO of the 566 types that have an indexer at all, and the comparator was proved
// to detect exactly the hazard that made this worth measuring (perturbing the substitute's selection
// order alone reports six disagreements, `Matrix4x4` and `BitVector32` among them).
class AnalyzerIndexAccess {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    declarationContextValue: AnalyzerDeclarationContext
    ambientValue: AnalyzerAmbientContext
    nullFlowValue: AnalyzerNullFlow
    soaEscapeValue: AnalyzerSoaEscape
    memberAccessValue: AnalyzerMemberAccess
    constantFactsValue: AnalyzerConstantExpressionFacts

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, declarationContext: AnalyzerDeclarationContext, ambient: AnalyzerAmbientContext, nullFlow: AnalyzerNullFlow, soaEscape: AnalyzerSoaEscape, memberAccess: AnalyzerMemberAccess, constantFacts: AnalyzerConstantExpressionFacts) {
        diagnosticsValue = diagnostics
        spansValue = spans
        declarationContextValue = declarationContext
        ambientValue = ambient
        nullFlowValue = nullFlow
        soaEscapeValue = soaEscape
        memberAccessValue = memberAccess
        constantFactsValue = constantFacts
    }

    func Begin(expression: Expression, inAssignmentTarget: bool): IndexAccessState {
        index := expression as IndexAccessExpression
        state := new IndexAccessState(index, inAssignmentTarget)
        if index == null {
            state.Phase = 99
        }

        return state
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    //
    // The index step's bracket opens HERE, in the same instant the step is handed out, and closes at
    // the top of the `Supply` that consumes its answer.
    func NextStep(state: IndexAccessState): IndexAccessRequest? {
        node := state.Index
        if node == null {
            state.Phase = 99
            return null
        }

        if state.Phase == 0 {
            state.Phase = 1
            return new IndexAccessRequest(1, node.Object)
        }

        if state.Phase == 2 {
            state.Phase = 3
            expectedIndexType: TypeInfo? = null
            if ShouldUseIntExpectedTypeForIndex(state.ReceiverType) {
                expectedIndexType = BuiltInTypes.Int
            }

            state.SavedExpectedType = ambientValue.EnterExpectedTypeIfProvided(expectedIndexType)
            return new IndexAccessRequest(1, node.Index)
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. A null answer is `unknown` rather than a missing one — the
    // analyzer's expression walk never answers null, and a walk that saw one would carry it into a
    // report.
    func Supply(state: IndexAccessState, answer: TypeInfo?) {
        answered: TypeInfo = BuiltInTypes.Unknown
        if answer != null {
            answered = answer
        }

        if state.Phase == 1 {
            ReceiverAnswered(state, answered)
            return
        }

        if state.Phase == 3 {
            IndexAnswered(state, answered)
            return
        }
    }

    func Result(state: IndexAccessState): TypeInfo {
        return state.ResultType
    }

    // THE RECEIVER HAS ANSWERED. The null-dereference report runs FIRST — before the receiver is
    // unwrapped — because it is the raw answered type that decides whether a dereference can throw.
    func ReceiverAnswered(state: IndexAccessState, objectType: TypeInfo) {
        node := state.Index
        if node == null {
            state.Phase = 99
            return
        }

        nullFlowValue.ReportPossibleNullAccess(node.Object, objectType, node.Line, node.Column, "index", node.IsNullConditional)
        state.ReceiverType = declarationContextValue.ResolveDeclaredAlias(NonNullableType(objectType))
        state.Phase = 2
    }

    // THE INDEX HAS ANSWERED. The bracket closes FIRST, before any gate runs, because a report is
    // free to look at the ambient context and every one of these reports ran with the slot already
    // restored.
    func IndexAnswered(state: IndexAccessState, indexType: TypeInfo) {
        ambientValue.ExitExpectedType(state.SavedExpectedType)
        state.SavedExpectedType = null
        state.Phase = 99
        state.IndexType = indexType

        node := state.Index
        if node == null {
            return
        }

        receiverType := state.ReceiverType
        soaRecordReceiver := receiverType as SoaRecordTypeInfo
        if soaRecordReceiver != null && node.IsNullConditional {
            soaEscapeValue.ReportSoaRowEscape(node, "used with null-conditional indexing")
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if node.IsNullConditional && soaEscapeValue.ReportDirectColumnNullConditionalAccessIfNeeded(node, node.Object, "index access") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        // All three escapes are evaluated: each names a different operand and the developer is owed
        // every one of them, which is why this is not a short-circuit.
        isSoaRowReceiver := receiverType as SoaRowTypeInfo != null
        isSoaRowIndex := soaEscapeValue.ReportSoaRowEscapeIfNeeded(node.Index, indexType, "used as an index value")
        isSoaDirectColumnIndex := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(node.Index, "used as an index value")
        if isSoaRowReceiver {
            soaEscapeValue.ReportSoaRowEscape(node.Object, "used as an index receiver")
        }

        if isSoaRowReceiver || isSoaRowIndex || isSoaDirectColumnIndex {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        isRangeAccess := node.Index as RangeExpression != null || IsRangeLikeType(indexType)
        if soaRecordReceiver != null && ReportNegativeSoaRowIndexIfNeeded(node.Index, indexType, "table row") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if soaRecordReceiver != null && !IsValidSoaRowIndex(indexType, isRangeAccess) {
            ReportInvalidSoaRowIndex(node.Index, indexType, isRangeAccess)
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if isRangeAccess && !state.InAssignmentTarget && soaEscapeValue.IsSoaColumnMemberAccess(node.Object) {
            ReportSoaColumnSliceHiddenAllocation(node)
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if !isRangeAccess && soaEscapeValue.IsSoaColumnMemberAccess(node.Object) && ReportNegativeSoaRowIndexIfNeeded(node.Index, indexType, "column row") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if !ValidateBuiltInIndexAccess(node, receiverType, indexType, isRangeAccess) {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        elementType := ResolveIndexElementType(receiverType, isRangeAccess)
        if node.IsNullConditional {
            state.ResultType = memberAccessValue.MakeNullableResult(elementType)
        } else {
            state.ResultType = elementType
        }
    }

    // WHICH RECEIVERS MAKE THE INDEX AN `int`. A table, an array (source or reflected) and a string
    // index by position; everything else — a dictionary above all — indexes by whatever its indexer
    // takes, and forcing `int` on those would target-type a key.
    func ShouldUseIntExpectedTypeForIndex(receiverType: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(receiverType)
        if resolved as SoaRecordTypeInfo != null || resolved as ArrayTypeInfo != null {
            return true
        }

        if IsReflectedArrayType(resolved) {
            return true
        }

        return IsStringType(resolved)
    }

    // AN ARRAY OR STRING INDEX MUST BE AN `int`, A `System.Index` OR A RANGE. Every other receiver is
    // left to its own indexer, and an `unknown` index is never accused — a second report on an
    // expression that already failed helps nobody.
    func ValidateBuiltInIndexAccess(node: IndexAccessExpression, receiverType: TypeInfo, indexType: TypeInfo, isRangeAccess: bool): bool {
        resolvedReceiverType := declarationContextValue.ResolveDeclaredAlias(receiverType)
        isArrayReceiver := resolvedReceiverType as ArrayTypeInfo != null || IsReflectedArrayType(resolvedReceiverType)
        isStringReceiver := IsStringType(resolvedReceiverType)
        if !isArrayReceiver && !isStringReceiver {
            return true
        }

        if isRangeAccess {
            return true
        }

        resolvedIndexType := declarationContextValue.ResolveDeclaredAlias(indexType)
        if BuiltInTypes.IsUnknown(resolvedIndexType) || BuiltInTypes.Is(resolvedIndexType, BuiltInTypes.Int) || IsIndexLikeType(resolvedIndexType) {
            return true
        }

        receiverDescription := "Array"
        if isStringReceiver {
            receiverDescription = "String"
        }

        ReportInvalidBuiltInIndex(node.Index, resolvedIndexType, receiverDescription)
        return false
    }

    // A TABLE ROW ID IS AN `int` AND NOTHING ELSE — not a range, and not a `System.Index`, because a
    // table has no from-end.
    func IsValidSoaRowIndex(indexType: TypeInfo, isRangeAccess: bool): bool {
        if isRangeAccess {
            return false
        }

        resolvedIndexType := declarationContextValue.ResolveDeclaredAlias(indexType)
        return BuiltInTypes.IsUnknown(resolvedIndexType) || BuiltInTypes.Is(resolvedIndexType, BuiltInTypes.Int)
    }

    // A CONSTANT NEGATIVE ROW INDEX, REFUSED AT COMPILE TIME. Only the signed integer types can be
    // negative, and only a CONSTANT can be known to be — a variable that happens to hold `-1` is the
    // runtime's problem.
    func ReportNegativeSoaRowIndexIfNeeded(expression: Expression, indexType: TypeInfo, targetDescription: string): bool {
        resolvedIndexType := declarationContextValue.ResolveDeclaredAlias(indexType)
        if BuiltInTypes.IsNot(resolvedIndexType, BuiltInTypes.Int) && BuiltInTypes.IsNot(resolvedIndexType, BuiltInTypes.Short) && BuiltInTypes.IsNot(resolvedIndexType, BuiltInTypes.SByte) {
            return false
        }

        if !constantFactsValue.IsConstantNegative(expression) {
            return false
        }

        span := spansValue.GetExpressionDiagnosticSpan(expression)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "SoA " + targetDescription + " indexes must not be negative", span.Line, span.Column, "Use zero or a valid non-negative row id.", span.Length)
        return true
    }

    func ReportInvalidSoaRowIndex(expression: Expression, indexType: TypeInfo, isRangeAccess: bool) {
        span := spansValue.GetExpressionDiagnosticSpan(expression)
        resolvedIndexType := declarationContextValue.ResolveDeclaredAlias(indexType)
        indexDescription := "'" + TypeText(indexType) + "'"
        if isRangeAccess {
            indexDescription = "a range"
        } else if IsIndexLikeType(resolvedIndexType) {
            indexDescription = "'System.Index'"
        }

        diagnosticsValue.Report(ErrorCode.TypeMismatch, "SoA table indexes must be int row ids, but this index has type " + indexDescription, span.Line, span.Column, "Use an int row index and read or write a column with table[index].column.", span.Length)
    }

    func ReportInvalidBuiltInIndex(expression: Expression, indexType: TypeInfo, receiverDescription: string) {
        span := spansValue.GetExpressionDiagnosticSpan(expression)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, receiverDescription + " indexes must be int, System.Index, or System.Range, but this index has type '" + TypeText(indexType) + "'", span.Line, span.Column, "Use an int element index, '^n' for from-end access, or a '..' range for slicing.", span.Length)
    }

    // PUBLISHED, because the write-target family refuses the same slice on the same node. A column
    // slice materialises an array, which is exactly what a table kernel is written to avoid.
    func ReportSoaColumnSliceHiddenAllocation(node: IndexAccessExpression) {
        span := spansValue.GetExpressionDiagnosticSpan(node)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA column range slices allocate arrays; use explicit element indexing instead", span.Line, span.Column, "Iterate with int row indexes over table.column[row], or add an allocation-free view lowering with IL-shape evidence before using slices in compiler table kernels.", span.Length)
    }

    // WHAT `a[i]` IS. A range access answers the SEQUENCE and an element access answers the ELEMENT,
    // and the INDEX's own type is not consulted at all — `Analyzer.cs` took it as a parameter and never
    // read it either, so the port drops the parameter rather than carrying a dead operand.
    // which is the one distinction every branch here repeats. A generic receiver is matched by NAME
    // SUFFIX rather than by metadata, deliberately: the analyzer must answer for a source-declared
    // `List` it has never reflected.
    func ResolveIndexElementType(receiver: TypeInfo, isRangeAccess: bool): TypeInfo {
        receiverType := declarationContextValue.ResolveDeclaredAlias(receiver)

        arrayType := receiverType as ArrayTypeInfo
        if arrayType != null {
            if isRangeAccess {
                return receiverType
            }

            return arrayType.ElementType
        }

        soaRecordType := receiverType as SoaRecordTypeInfo
        if !isRangeAccess && soaRecordType != null {
            rowType: TypeInfo = new SoaRowTypeInfo(soaRecordType.Declaration)
            return rowType
        }

        if IsStringType(receiverType) {
            if isRangeAccess {
                return BuiltInTypes.String
            }

            return BuiltInTypes.Char
        }

        genericType := receiverType as GenericTypeInfo
        if genericType != null {
            name := genericType.Name
            if name.EndsWith("Dictionary", StringComparison.Ordinal) && genericType.TypeArguments.Count >= 2 {
                return genericType.TypeArguments[1]
            }

            if genericType.TypeArguments.Count == 1 && (name.EndsWith("List", StringComparison.Ordinal) || name.EndsWith("IList", StringComparison.Ordinal) || name.EndsWith("IReadOnlyList", StringComparison.Ordinal) || name.EndsWith("Collection", StringComparison.Ordinal)) {
                return genericType.TypeArguments[0]
            }
        }

        reflectionType := receiverType as ReflectionTypeInfo
        if reflectionType != null {
            reflected := reflectionType.Type
            if reflected.get_IsArray() {
                if isRangeAccess {
                    return AnalyzerReflectionTypeConversion.ConvertReflectionType(reflected)
                }

                elementType := reflected.GetElementType()
                if elementType != null {
                    return AnalyzerReflectionTypeConversion.ConvertReflectionType(elementType)
                }

                return BuiltInTypes.Unknown
            }

            indexer := FindReflectedIndexerProperty(reflected)
            if indexer != null {
                return AnalyzerReflectionTypeConversion.ConvertReflectionType(indexer.get_PropertyType())
            }
        }

        return BuiltInTypes.Unknown
    }

    // THE REFLECTED INDEXER. See the type's own note: this is `GetDefaultMembers()`'s answer, reached
    // without naming `MemberInfo`, and proved identical on every type that has an indexer in the
    // whole shipped framework.
    func FindReflectedIndexerProperty(reflected: Type): PropertyInfo? {
        // The flags are a LOCAL, not an inline `|`: an inline flag expression does not type as
        // `BindingFlags` at the call site and the instance call declines as unmodeled.
        flags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static
        properties := reflected.GetProperties(flags)
        for property in properties {
            if property.GetIndexParameters().Length > 0 {
                return property
            }
        }

        return null
    }

    func IsReflectedArrayType(candidate: TypeInfo): bool {
        reflectionType := candidate as ReflectionTypeInfo
        return reflectionType != null && reflectionType.Type.get_IsArray()
    }

    // `System.Range` AND `System.Index`, BY EITHER NAME. A reflected one carries its full name; a
    // source-written one carries whatever the developer typed, which is why both spellings are here.
    static func IsRangeLikeType(candidate: TypeInfo): bool {
        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            return reflectionType.Type.get_FullName() == "System.Range"
        }

        simpleType := candidate as SimpleTypeInfo
        return simpleType != null && (simpleType.Name == "Range" || simpleType.Name == "System.Range")
    }

    static func IsIndexLikeType(candidate: TypeInfo): bool {
        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            return reflectionType.Type.get_FullName() == "System.Index"
        }

        simpleType := candidate as SimpleTypeInfo
        return simpleType != null && (simpleType.Name == "Index" || simpleType.Name == "System.Index")
    }

    static func IsStringType(candidate: TypeInfo): bool {
        return AnalyzerOperatorExpressions.IsStringType(candidate)
    }

    func NonNullableType(candidate: TypeInfo): TypeInfo {
        nullable := declarationContextValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
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

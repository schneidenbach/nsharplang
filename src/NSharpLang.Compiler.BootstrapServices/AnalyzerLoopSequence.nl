namespace NSharpLang.Compiler

import System
import System.Reflection
import NSharpLang.Compiler.Ast

// THE STEP THE `yield` WALK CANNOT TAKE FOR ITSELF.
//
//   1  analyse the YIELDED expression. ANSWERS a type, and that type is the operand of the row-escape
//      report, of the element-type comparison and of the mismatch wording.
//
// IT ASKED FOR THREE AND NOW ASKS FOR ONE. Kinds 2 and 3 were the two SoA escape reports; both are
// now direct calls on `AnalyzerSoaEscape`, whose answers this walk still READS — either escape
// suppresses the element-type rule, because a value the analyzer has already refused to let leave its
// record must not also be measured against the sequence element type. The walk stays a suspendable
// walk rather than one call because the answer to step 1 is the operand of both reports and of the
// rule that follows them.
public class YieldStatementRequest {

    public Kind: int
    public Node: Expression?
    public Text: string?
    public CarriedType: TypeInfo

    constructor(kind: int) {
        Kind = kind
        Node = null
        Text = null
        CarriedType = BuiltInTypes.Unknown
    }
}

// THE `yield` STATEMENT'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Phase` is the walk's program counter: 0 reports a `yield` outside a generator and either finishes
// the bare form or asks for the value; 1 folds the yielded type in and runs the row escape; 2 runs
// the direct-column escape; 3 applies the element-type rule. 99 is done.
//
// `DeclaresGenerator` IS CAPTURED AT ENTRY, not read at the rule. That is not tidiness: the C# arm
// read `CurrentFunctionDeclaresGenerator` into a local BEFORE walking the yielded expression, and a
// lambda inside that expression opens and closes a nested function context while the walk is
// suspended. The enclosing function's RETURN TYPE and its `async` modifier are read LATER, at the
// rule, because that is where the C# condition read them.
//
// The assignability oracle is carried on the state for the reason `ReturnStatementState` records:
// `Analyzer.cs` rebuilds it at metadata-load and dispose, so it is read at `Begin` rather than held.
public class YieldStatementState {

    statementValue: YieldStatement
    assignabilityValue: AnalyzerAssignability

    Statement: YieldStatement => statementValue
    Assignability: AnalyzerAssignability => assignabilityValue

    public Phase: int
    public Pending: int
    public DeclaresGenerator: bool
    public YieldedType: TypeInfo
    public EscapedAsRow: bool
    public EscapedAsDirectColumn: bool

    constructor(statement: YieldStatement, assignability: AnalyzerAssignability) {
        statementValue = statement
        assignabilityValue = assignability
        Phase = 0
        Pending = 0
        DeclaresGenerator = false
        YieldedType = BuiltInTypes.Unknown
        EscapedAsRow = false
        EscapedAsDirectColumn = false
    }
}

// THE SIX STEPS A `foreach` LOOP CANNOT TAKE FOR ITSELF, AND EVERYTHING EACH STEP NEEDS.
//
// The walk owns what N#'s TWO iteration statements MEAN — `foreach x in e { … }` and
// `await foreach x in e { … }`: which escape report the collection's type selects and with which
// action word, that an escaped collection collapses to `unknown` before anything else looks at it,
// which of the two element-type questions is asked, what the loop variable's type therefore is,
// which scope kind opens and at which position, the ORDER of the six replayed operations, and that
// the body runs inside an open loop. What it cannot do is run the analyzer's own EXPRESSION walk,
// open or close a scope on the analyzer's scope stack, declare a name into that stack, write the
// semantic model the IDE reads, or re-enter the STATEMENT dispatch — so it ASKS: one request at a
// time, each naming a kind and carrying every value the step needs. Nothing here is a policy the
// driver may reinterpret — the driver switches on `Kind`, performs exactly the one operation with
// exactly these operands, and hands the answer back.
//
// The kinds:
//   1  analyse the COLLECTION expression, WITHOUT touching the analyzer's ambient target-typing
//      slot — neither arm ever set it. ANSWERS a type, and that type is the operand of both escape
//      reports and of the element-type question that settles every step after it.
//   2  open a block scope on the analyzer's scope stack at `Line` / `Column`.
//   3  declare the loop variable into the analyzer's scope stack, under `CarriedType`. No
//      declaration kind is carried: neither arm tagged one, so the analyzer derives it.
//   4  record the loop variable in the semantic model the IDE's hover and completion read.
//   5  analyse the loop BODY, which re-enters the statement dispatch and therefore this walk itself.
//      This is ONE statement, not a list — it is deliberately NOT
//      `ExpressionStatementRequest`'s kind 5, because the list walk also runs the unreachable-code
//      rule, and a loop body that is a single statement never had that rule applied to it.
//   6  close the scope kind 2 opened.
//
// The numbering is this walk's own protocol with its own driver and starts at 1 with no gaps; the
// other walks' numbers mean different operations, and none of them is a shared vocabulary.
public class ForeachStatementRequest {

    public Kind: int
    public Node: Expression?
    public Body: Statement?
    public Name: string?
    public CarriedType: TypeInfo
    public Line: int
    public Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        Body = null
        Name = null
        CarriedType = carriedType
        Line = 0
        Column = 0
    }
}

// THE LOOP'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// ONE state serves BOTH iteration statements, because ONE driver serves both. `ForeachStatement` and
// `AwaitForEachStatement` are structurally identical but share no base beyond `Statement`, so the
// state carries the five OPERANDS rather than the node, and `IsAsync` is the single bit that
// separates the two walks: it selects the action word the escape reports use and which of the two
// element-type entries is asked. Nothing else about them differs.
//
// `Phase` is the walk's program counter: 0 asks for the collection; 1 folds the answer in, runs the
// two escape reports in order and settles the element type; 2 through 5 are the four replayed
// operations, with the loop opened at 4 and closed at 5; and 6 finishes. 99 is done.
//
// `LoopFrame` is the ambient snapshot `EnterLoop` hands back. It is held on the state rather than in
// a local because the walk SUSPENDS between opening the loop and closing it — the body runs in the
// driver — and it is nullable only because a state exists before phase 4 has run.
public class ForeachStatementState {

    variableNameValue: string
    collectionValue: Expression
    bodyValue: Statement
    lineValue: int
    columnValue: int
    isAsyncValue: bool

    VariableName: string => variableNameValue
    Collection: Expression => collectionValue
    Body: Statement => bodyValue
    Line: int => lineValue
    Column: int => columnValue
    IsAsync: bool => isAsyncValue

    public Phase: int
    public Pending: int
    public CollectionType: TypeInfo
    public ElementType: TypeInfo
    public LoopFrame: AmbientContextFrame?

    constructor(
        variableName: string,
        collection: Expression,
        body: Statement,
        line: int,
        column: int,
        isAsync: bool) {
        variableNameValue = variableName
        collectionValue = collection
        bodyValue = body
        lineValue = line
        columnValue = column
        isAsyncValue = isAsync
        Phase = 0
        Pending = 0
        CollectionType = BuiltInTypes.Unknown
        ElementType = BuiltInTypes.Unknown
        LoopFrame = null
    }
}

// WHAT ITERATING A VALUE PRODUCES — the one question `foreach`, `await foreach` and a generator's
// `yield` all ask, and the reports that are pure functions of its answer.
//
// THE FAMILY IS NOT A PURE FUNCTION OF A TYPE, WHICH IS WHY IT IS AN OBJECT RATHER THAN A STATIC.
// The shape normaliser consults the SCOPE STACK (a simple name may resolve to a declared type that
// is not itself) and the DECLARATION CONTEXT (aliases, and the nullable unwrap); the source arm
// consults the TYPE RESOLVER to turn a declared interface REFERENCE into a type; the generator façade
// consults the AMBIENT CONTEXT for the enclosing function's `async` modifier; and the mismatch report
// needs the span reader and the diagnostic sink. Every one of those six collaborators is constructed
// exactly once by `Analyzer.cs` and is never rebuilt with the metadata load context, so holding them
// is safe in a way that holding the assignability oracle would not be.
//
// THE ANSWER IS FOUND IN A FIXED ORDER, AND THE ORDER IS BEHAVIOUR. An array answers its element
// type and a `string` answers `char`, but only for a SYNCHRONOUS loop — `await foreach` over an array
// is not an async sequence and must fall through to the mismatch report rather than quietly
// succeeding. A declared generic answers by NAME through `LoopSequenceTypeFacts`, which is why a
// user-written `List` behaves like the BCL one. A reflected type answers through four probes in
// order — array, `Span`/`ReadOnlySpan`, the `IEnumerable<T>` / `IAsyncEnumerable<T>` interface, then
// the duck-typed `GetEnumerator`/`MoveNext`/`Current` pattern — and only then falls back to the
// non-generic `IEnumerable`, whose element type is `object`. A declared class, struct, record or
// interface answers by asking the SAME question of each interface it names, in declaration order.
//
// THE REFLECTION PROBES COMPARE TYPE IDENTITIES, NOT NAMES, AND THAT IS DELIBERATE UNDER THE
// METADATA LOAD CONTEXT. `GetGenericTypeDefinition() == typeof(IEnumerable<>)` and
// `MoveNext().ReturnType == typeof(bool)` are reference comparisons against RUNTIME types. A type
// loaded into the analyzer's MetadataLoadContext is a different object from its runtime twin, so
// these probes answer NO for it and the walk falls through to the arms that do not depend on runtime
// identity. That is the behaviour `Analyzer.cs` had, character for character, and it is preserved
// rather than "fixed": widening it here would change which foreach loops compile.
//
// ALL THREE STATEMENTS THAT ASK THE QUESTION ALSO LIVE HERE — `yield`, `foreach` and
// `await foreach` — for the same reason each: the rule that ends the walk is a question about the
// ELEMENT TYPE, and that family is this one. Both walks reach their collaborators through the
// objects this type already holds; neither needs anything `Analyzer.cs` rebuilds with the metadata
// load context, which is why neither has to be handed one at `Begin` the way the assignability
// oracle is.
public class AnalyzerLoopSequence {

    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    typeResolverValue: AnalyzerTypeResolver
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape

    constructor(
        diagnostics: AnalyzerDiagnosticSink,
        spans: AnalyzerDiagnosticSpans,
        scopes: AnalyzerScopeStack,
        declarationContext: AnalyzerDeclarationContext,
        typeResolver: AnalyzerTypeResolver,
        ambient: AnalyzerAmbientContext,
        soaEscape: AnalyzerSoaEscape) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
        ambientValue = ambient
        soaEscapeValue = soaEscape
    }

    // THE `foreach` COLLECTION'S ELEMENT TYPE, plus the report when there is not one. The declared
    // variable's type is `unknown` when the collection is not enumerable, and the report is SILENT
    // for a collection whose type is already unknown or still external — a second complaint about a
    // value nothing could type is noise.
    public func ResolveForeachElementType(collection: Expression, collectionType: TypeInfo): TypeInfo {
        return ResolveLoopElementType(
            collection,
            collectionType,
            false,
            "foreach",
            "enumerable",
            "Use an array, Span<T>, or IEnumerable<T> value as the foreach collection.")
    }

    // THE `await foreach` COLLECTION'S ELEMENT TYPE. Same shape, different question: only an async
    // sequence answers, so an array or a `List<T>` reaches the report here.
    public func ResolveAwaitForeachElementType(collection: Expression, collectionType: TypeInfo): TypeInfo {
        return ResolveLoopElementType(
            collection,
            collectionType,
            true,
            "await foreach",
            "async enumerable",
            "Use an IAsyncEnumerable<T> value as the await foreach collection.")
    }

    func ResolveLoopElementType(
        collection: Expression,
        collectionType: TypeInfo,
        requireAsync: bool,
        loopKind: string,
        expectedKind: string,
        suggestion: string): TypeInfo {
        elementType := GetLoopSequenceElementType(collectionType, requireAsync)
        if elementType != null {
            return elementType
        }

        if ShouldReportLoopSequenceTypeMismatch(collectionType) {
            span := spansValue.GetExpressionDiagnosticSpan(collection)
            diagnosticsValue.Report(
                ErrorCode.TypeMismatch,
                loopKind + " collection must be " + expectedKind + ", but this collection is '"
                    + TypeText(collectionType) + "'",
                span.Line,
                span.Column,
                suggestion,
                span.Length)
        }

        return BuiltInTypes.Unknown
    }

    // WHETHER A FAILED LOOKUP IS WORTH REPORTING. An unknown type already carries whatever error made
    // it unknown, and an external type is one the analyzer has not finished resolving.
    public func ShouldReportLoopSequenceTypeMismatch(collectionType: TypeInfo): bool {
        resolved := NormalizeShapeType(collectionType)
        if BuiltInTypes.IsUnknown(resolved) {
            return false
        }

        external := resolved as ExternalTypeInfo
        return external == null
    }

    // WHAT ITERATING THIS TYPE PRODUCES, or null when it produces nothing. `requireAsync` selects
    // between the two questions; it is not a preference but a filter, and the synchronous arms are
    // gated on it individually rather than up front because a reflected type reaches the SAME probe
    // list either way.
    public func GetLoopSequenceElementType(collectionType: TypeInfo, requireAsync: bool): TypeInfo? {
        resolved := NormalizeShapeType(collectionType)

        arrayType := resolved as ArrayTypeInfo
        if arrayType != null {
            if requireAsync {
                return null
            }

            return arrayType.ElementType
        }

        simpleType := resolved as SimpleTypeInfo
        if simpleType != null {
            if !requireAsync && BuiltInTypes.Is(simpleType, BuiltInTypes.String) {
                return BuiltInTypes.Char
            }

            return null
        }

        genericType := resolved as GenericTypeInfo
        if genericType != null {
            return LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(genericType, requireAsync)
        }

        reflectionType := resolved as ReflectionTypeInfo
        if reflectionType != null {
            return GetReflectionLoopSequenceElementType(reflectionType.Type, requireAsync)
        }

        classType := resolved as ClassTypeInfo
        if classType != null {
            return GetSourceLoopSequenceElementType(classType.Interfaces, requireAsync)
        }

        structType := resolved as StructTypeInfo
        if structType != null {
            return GetSourceLoopSequenceElementType(structType.Interfaces, requireAsync)
        }

        recordType := resolved as RecordTypeInfo
        if recordType != null {
            return GetSourceLoopSequenceElementType(recordType.Interfaces, requireAsync)
        }

        interfaceType := resolved as InterfaceTypeInfo
        if interfaceType != null {
            return GetSourceLoopSequenceElementType(interfaceType.BaseInterfaces, requireAsync)
        }

        return null
    }

    // A TYPE STRIPPED DOWN TO THE SHAPE THAT ANSWERS STRUCTURAL QUESTIONS: aliases resolved, nullable
    // and oblivious wrappers removed, `ref`-ness removed, and a simple NAME replaced by whatever the
    // scope stack says that name declares. The walk is a fixed point rather than one pass because
    // each unwrap can expose another wrapper, and the simple-name arm guards against a name that
    // resolves to itself — without that guard a self-referential declaration would spin here.
    //
    // The nullable unwrap resolves aliases FIRST and then returns the ORIGINAL type when the result
    // is not nullable, which is what `Analyzer.cs` did; the outer resolve then runs on that original.
    // The double resolve is not redundant — it is the reason an alias for a nullable alias settles.
    public func NormalizeShapeType(candidate: TypeInfo): TypeInfo {
        resolved := declarationContextValue.ResolveDeclaredAlias(NonNullableType(candidate))
        settled := false
        while !settled {
            next := ShapeRedirectTarget(resolved)
            if next != null {
                resolved = declarationContextValue.ResolveDeclaredAlias(NonNullableType(next))
            } else {
                settled = true
            }
        }

        return resolved
    }

    // THE ONE UNWRAP THIS TYPE STILL OWES, or null when it is already a shape. `oblivious` and `ref`
    // hand back what they wrap; a simple NAME hands back what the scope stack says it declares, but
    // only when that is a DIFFERENT object — a name that resolves to itself contributes nothing and
    // would otherwise spin the fixed point forever.
    func ShapeRedirectTarget(resolved: TypeInfo): TypeInfo? {
        oblivious := resolved as ObliviousTypeInfo
        if oblivious != null {
            return oblivious.InnerType
        }

        byRef := resolved as ByRefTypeInfo
        if byRef != null {
            return byRef.InnerType
        }

        simple := resolved as SimpleTypeInfo
        if simple == null {
            return null
        }

        named := scopesValue.LookupType(simple.Name)
        if named == null {
            return null
        }

        if Object.ReferenceEquals(named, resolved) {
            return null
        }

        return named
    }

    // A TYPE WITHOUT ITS NULLABLE WRAPPER. The alias resolve happens on the way IN so that an alias
    // for a nullable type unwraps, and the ORIGINAL type is returned when there is nothing to unwrap
    // so that the caller's own resolve is the one that settles it.
    func NonNullableType(candidate: TypeInfo): TypeInfo {
        nullable := declarationContextValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
    }

    // THE FIRST DECLARED INTERFACE THAT ANSWERS, in declaration order. The recursion is through the
    // top-level question, so an interface that inherits a sequence interface answers too.
    func GetSourceLoopSequenceElementType(
        interfaceReferences: TypeReference[],
        requireAsync: bool): TypeInfo? {
        index := 0
        while index < interfaceReferences.Length {
            interfaceType := typeResolverValue.ResolveType(interfaceReferences[index])
            elementType := GetLoopSequenceElementType(interfaceType, requireAsync)
            if elementType != null {
                return elementType
            }

            index = index + 1
        }

        return null
    }

    // THE REFLECTED PROBE LIST, IN ORDER. A nullable reflected type is unwrapped first, exactly as
    // the CLR-facing arms elsewhere do. An array whose element type reflection cannot name falls
    // THROUGH to the remaining probes rather than failing outright.
    func GetReflectionLoopSequenceElementType(clrType: Type, requireAsync: bool): TypeInfo? {
        runtimeType := StripNullableRuntimeType(clrType)

        if !requireAsync && runtimeType.get_IsArray() {
            elementReflectionType := runtimeType.GetElementType()
            if elementReflectionType != null {
                return AnalyzerReflectionTypeConversion.ConvertReflectionType(elementReflectionType)
            }
        }

        if !requireAsync {
            spanElement := GetReflectionGenericElementType(runtimeType, "System.Span`1")
            if spanElement != null {
                return spanElement
            }

            readOnlySpanElement := GetReflectionGenericElementType(runtimeType, "System.ReadOnlySpan`1")
            if readOnlySpanElement != null {
                return readOnlySpanElement
            }
        }

        expectedInterface := SynchronousSequenceDefinition()
        if requireAsync {
            expectedInterface = AsynchronousSequenceDefinition()
        }

        interfaceElement := GetReflectionInterfaceElementType(runtimeType, expectedInterface)
        if interfaceElement != null {
            return interfaceElement
        }

        if !requireAsync {
            patternElement := GetReflectionEnumeratorPatternElementType(runtimeType)
            if patternElement != null {
                return patternElement
            }

            if NonGenericSequenceType().IsAssignableFrom(runtimeType) {
                return BuiltInTypes.Object
            }
        }

        return null
    }

    // A reflected type whose OPEN definition is named exactly, with exactly one argument. The name
    // comparison is on the definition's full name rather than on an identity, because `Span<T>` and
    // `ReadOnlySpan<T>` are matched by shape wherever they were loaded from.
    func GetReflectionGenericElementType(clrType: Type, genericDefinitionFullName: string): TypeInfo? {
        if !clrType.get_IsGenericType() {
            return null
        }

        definition := clrType.GetGenericTypeDefinition()
        if definition.get_FullName() != genericDefinitionFullName {
            return null
        }

        arguments := clrType.get_GenericTypeArguments()
        if arguments.Length != 1 {
            return null
        }

        return AnalyzerReflectionTypeConversion.ConvertReflectionType(arguments[0])
    }

    // The sequence interface itself, or the first one among the type's interfaces. Identity, not
    // name — see the type's banner for why that is deliberate under the MetadataLoadContext.
    func GetReflectionInterfaceElementType(clrType: Type, expectedInterfaceDefinition: Type): TypeInfo? {
        sequenceInterface := FindReflectionSequenceInterface(clrType, expectedInterfaceDefinition)
        if sequenceInterface == null {
            return null
        }

        arguments := sequenceInterface.get_GenericTypeArguments()
        if arguments.Length != 1 {
            return null
        }

        return AnalyzerReflectionTypeConversion.ConvertReflectionType(arguments[0])
    }

    func FindReflectionSequenceInterface(clrType: Type, expectedInterfaceDefinition: Type): Type? {
        if clrType.get_IsGenericType() && clrType.GetGenericTypeDefinition() == expectedInterfaceDefinition {
            return clrType
        }

        interfaces := clrType.GetInterfaces()
        index := 0
        while index < interfaces.Length {
            candidate := interfaces[index]
            if candidate.get_IsGenericType()
                && candidate.GetGenericTypeDefinition() == expectedInterfaceDefinition {
                return candidate
            }

            index = index + 1
        }

        return null
    }

    // THE DUCK-TYPED ENUMERATOR PATTERN: a parameterless `GetEnumerator` whose return type carries a
    // parameterless `MoveNext` returning `bool` and a readable `Current`. Visibility is deliberately
    // wide — a non-public member satisfies the pattern here, as it did in `Analyzer.cs` — and BOTH
    // enumerator members are looked up before either is judged, so an ambiguous `Current` throws
    // where it always threw.
    func GetReflectionEnumeratorPatternElementType(clrType: Type): TypeInfo? {
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        noParameters := new Type[](0)
        getEnumeratorMethod := clrType.GetMethod("GetEnumerator", flags, null, noParameters, null)
        if getEnumeratorMethod == null {
            return null
        }

        enumeratorType := getEnumeratorMethod.get_ReturnType()
        moveNextMethod := enumeratorType.GetMethod("MoveNext", flags, null, noParameters, null)
        currentProperty := enumeratorType.GetProperty("Current", flags)
        if moveNextMethod == null || moveNextMethod.get_ReturnType() != typeof(bool) {
            return null
        }

        if currentProperty == null || currentProperty.get_GetMethod() == null {
            return null
        }

        return AnalyzerReflectionTypeConversion.ConvertReflectionType(currentProperty.get_PropertyType())
    }

    func StripNullableRuntimeType(clrType: Type): Type {
        underlying := Nullable.GetUnderlyingType(clrType)
        if underlying != null {
            return underlying
        }

        return clrType
    }

    // THE THREE RUNTIME IDENTITIES THE PROBES COMPARE AGAINST, and their spellings are forced rather
    // than chosen. `typeof(IEnumerable<int>).GetGenericTypeDefinition()` is the estate's way to name
    // an open definition and it emits; the pinned toolset DECLINES `typeof` on the non-generic
    // `System.Collections.IEnumerable` and on `IAsyncEnumerable<T>` in every spelling tried — bare,
    // fully qualified, and through a local — so those two are named through `Type.GetType`, which is
    // the same door `LoopSequenceTypeFacts` already opens for `KeyValuePair`2`. All three resolve to
    // `System.Private.CoreLib`, so the identity the probes compare is the one `typeof` would have
    // given; that was verified by running the lookups rather than by reasoning about them.
    static func SynchronousSequenceDefinition(): Type {
        return typeof(System.Collections.Generic.IEnumerable<int>).GetGenericTypeDefinition()
    }

    static func AsynchronousSequenceDefinition(): Type {
        definition := Type.GetType("System.Collections.Generic.IAsyncEnumerable`1")
        if definition == null {
            throw new InvalidOperationException(
                "Required async sequence interface System.Collections.Generic.IAsyncEnumerable`1 was not found.")
        }

        return definition
    }

    static func NonGenericSequenceType(): Type {
        sequence := Type.GetType("System.Collections.IEnumerable")
        if sequence == null {
            throw new InvalidOperationException(
                "Required sequence interface System.Collections.IEnumerable was not found.")
        }

        return sequence
    }

    // WHAT A GENERATOR'S `yield` MUST PRODUCE: the element type of the function's own declared return
    // type, asked as an ASYNC sequence when the function is `async func*` and as a synchronous one
    // otherwise. The `async` modifier is read from the ambient context at the moment of asking.
    public func GetGeneratorYieldElementType(returnType: TypeInfo): TypeInfo? {
        return GetLoopSequenceElementType(returnType, ambientValue.CurrentFunctionDeclaresAsync)
    }

    // THE `yield` STATEMENT'S ENTRY. The assignability oracle is read from the caller's field HERE,
    // for the reason `YieldStatementState` records.
    public func BeginYield(
        statement: YieldStatement,
        assignability: AnalyzerAssignability): YieldStatementState {
        return new YieldStatementState(statement, assignability)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this `yield` is finished.
    public func NextStep(state: YieldStatementState): YieldStatementRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 remains, and it answers the yielded type. The
    // two escape answers used to arrive here; they are read directly from the reporters now.
    public func Supply(state: YieldStatementState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending == 1 {
            if answer != null {
                state.YieldedType = answer
            }
        }
    }

    func Advance(state: YieldStatementState): YieldStatementRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceEntry(state)
        }

        if phase == 1 {
            return AdvanceRowEscape(state)
        }

        if phase == 2 {
            return AdvanceDirectColumnEscape(state)
        }

        if phase == 3 {
            return AdvanceElementTypeRule(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 0 — IS THIS A GENERATOR AT ALL. The report fires and the walk CONTINUES: a `yield` in an
    // ordinary function still has its value analysed, so a second error in the same expression is
    // still found. A bare `yield` — `yield break` — ends here.
    func AdvanceEntry(state: YieldStatementState): YieldStatementRequest? {
        statement := state.Statement
        state.DeclaresGenerator = ambientValue.CurrentFunctionDeclaresGenerator
        if !state.DeclaresGenerator {
            diagnosticsValue.Report(
                ErrorCode.InvalidSyntax,
                "'yield' can only be used inside a generator function",
                statement.Line,
                statement.Column,
                "Mark the function as `func*`/`async func*`, or replace `yield` with `return` in an ordinary function.",
                5)
        }

        value := statement.Value
        if value == null {
            state.Phase = 99
            return null
        }

        state.Phase = 1
        state.Pending = 1
        request := new YieldStatementRequest(1)
        request.Node = value
        return request
    }

    func AdvanceRowEscape(state: YieldStatementState): YieldStatementRequest? {
        value := state.Statement.Value
        if value == null {
            state.Phase = 99
            return null
        }

        state.Phase = 2
        state.EscapedAsRow = soaEscapeValue.ReportSoaRowEscapeIfNeeded(
            value,
            state.YieldedType,
            "yielded")
        return null
    }

    func AdvanceDirectColumnEscape(state: YieldStatementState): YieldStatementRequest? {
        value := state.Statement.Value
        if value == null {
            state.Phase = 99
            return null
        }

        state.Phase = 3
        state.EscapedAsDirectColumn = soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(
            value,
            "yielded")
        return null
    }

    // PHASE 3 — DOES THE YIELDED VALUE FIT THE SEQUENCE. Six conditions gate the report and every one
    // of them is a silence rule: a non-generator has already been told what is wrong; either escape
    // has already reported; a function with no return type at all has nothing to compare against; a
    // return type that names no sequence is a different error; and an unknown on either side would
    // make the wording meaningless.
    func AdvanceElementTypeRule(state: YieldStatementState): YieldStatementRequest? {
        state.Phase = 99
        if !state.DeclaresGenerator || state.EscapedAsRow || state.EscapedAsDirectColumn {
            return null
        }

        returnType := ambientValue.CurrentReturnType
        if returnType == null {
            return null
        }

        elementType := GetGeneratorYieldElementType(returnType)
        if elementType == null {
            return null
        }

        yieldedType := state.YieldedType
        if BuiltInTypes.IsUnknown(yieldedType) || BuiltInTypes.IsUnknown(elementType) {
            return null
        }

        if state.Assignability.IsAssignable(elementType, yieldedType) {
            return null
        }

        value := state.Statement.Value
        if value != null {
            elementText := TypeText(elementType)
            span := spansValue.GetExpressionDiagnosticSpan(value)
            diagnosticsValue.Report(
                ErrorCode.TypeMismatch,
                "Generator yield value is '" + TypeText(yieldedType)
                    + "', but the sequence element type is '" + elementText + "'",
                span.Line,
                span.Column,
                "Yield a value assignable to '" + elementText
                    + "', or change the generator return type.",
                span.Length)
        }

        return null
    }

    // THE `foreach` STATEMENT'S ENTRY. The five operands are read off the node here, so the walk
    // never holds an AST node whose type is one of two unrelated classes.
    public func BeginForeach(statement: ForeachStatement): ForeachStatementState {
        return new ForeachStatementState(
            statement.VariableName,
            statement.Collection,
            statement.Body,
            statement.Line,
            statement.Column,
            false)
    }

    // THE `await foreach` STATEMENT'S ENTRY — the same walk with `IsAsync` set, which is the whole
    // difference between the two arms.
    public func BeginAwaitForeach(statement: AwaitForEachStatement): ForeachStatementState {
        return new ForeachStatementState(
            statement.VariableName,
            statement.Collection,
            statement.Body,
            statement.Line,
            statement.Column,
            true)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this loop is finished.
    public func NextForeachStep(state: ForeachStatementState): ForeachStatementRequest? {
        while state.Phase != 99 {
            request := AdvanceForeach(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything: the collection's type. The
    // four replayed operations and the body walk answer nothing, and nothing is folded in for them.
    public func SupplyForeach(state: ForeachStatementState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending == 1 {
            if answer != null {
                state.CollectionType = answer
            }
        }
    }

    func AdvanceForeach(state: ForeachStatementState): ForeachStatementRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceForeachCollection(state)
        }

        if phase == 1 {
            return AdvanceForeachElementType(state)
        }

        if phase == 2 {
            return AdvanceForeachDeclare(state)
        }

        if phase == 3 {
            return AdvanceForeachRecord(state)
        }

        if phase == 4 {
            return AdvanceForeachBody(state)
        }

        if phase == 5 {
            return AdvanceForeachClose(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 0 — the collection, and nothing before it. The scope opens only after its type is known,
    // so an expression that mentions the loop variable's name resolves to whatever that name meant
    // OUTSIDE the loop, which is what `Analyzer.cs` did.
    func AdvanceForeachCollection(state: ForeachStatementState): ForeachStatementRequest? {
        state.Phase = 1
        state.Pending = 1
        request := new ForeachStatementRequest(1, BuiltInTypes.Unknown)
        request.Node = state.Collection
        return request
    }

    // PHASE 1 — THE TWO ESCAPES AND THE ELEMENT TYPE. The reports run in order and the second is
    // SHORT-CIRCUITED by the first: a row view that has already been refused must not also be told
    // it is a direct column read. Either report collapses the collection to `unknown`, which is what
    // silences the element-type mismatch that would otherwise follow — one bad collection is one
    // diagnostic, not two.
    func AdvanceForeachElementType(state: ForeachStatementState): ForeachStatementRequest? {
        collection := state.Collection
        usage := "used as a foreach collection"
        if state.IsAsync {
            usage = "used as an async foreach collection"
        }

        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(collection, state.CollectionType, usage) {
            state.CollectionType = BuiltInTypes.Unknown
        } else if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(collection, usage) {
            state.CollectionType = BuiltInTypes.Unknown
        }

        if state.IsAsync {
            state.ElementType = ResolveAwaitForeachElementType(collection, state.CollectionType)
        } else {
            state.ElementType = ResolveForeachElementType(collection, state.CollectionType)
        }

        state.Phase = 2
        request := new ForeachStatementRequest(2, BuiltInTypes.Unknown)
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 2 — the loop variable, declared at the STATEMENT's position rather than the variable's,
    // because that is the position `Analyzer.cs` passed and it is what the binding map records.
    func AdvanceForeachDeclare(state: ForeachStatementState): ForeachStatementRequest? {
        state.Phase = 3
        request := new ForeachStatementRequest(3, state.ElementType)
        request.Name = state.VariableName
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 3 — the semantic model the IDE's hover and completion read. A separate step from the
    // scope declaration for the reason `AnalyzerVariableDeclaration` records: it writes a different
    // store, keyed by the semantic scope id rather than by the analyzer's own stack.
    func AdvanceForeachRecord(state: ForeachStatementState): ForeachStatementRequest? {
        state.Phase = 4
        request := new ForeachStatementRequest(4, state.ElementType)
        request.Name = state.VariableName
        return request
    }

    // PHASE 4 — the loop opens, THEN the body runs. The frame is taken here rather than at entry
    // because the collection expression is not inside the loop: a `break` written in it is as
    // illegal as one written outside.
    func AdvanceForeachBody(state: ForeachStatementState): ForeachStatementRequest? {
        state.Phase = 5
        state.LoopFrame = ambientValue.EnterLoop()
        request := new ForeachStatementRequest(5, BuiltInTypes.Unknown)
        request.Body = state.Body
        return request
    }

    // PHASE 5 — the loop closes BEFORE the scope does, which is the order `Analyzer.cs` used.
    func AdvanceForeachClose(state: ForeachStatementState): ForeachStatementRequest? {
        state.Phase = 6
        frame := state.LoopFrame
        if frame != null {
            ambientValue.ExitLoop(frame)
        }

        return new ForeachStatementRequest(6, BuiltInTypes.Unknown)
    }

    // A TYPE'S RENDERED TEXT, TAKEN THROUGH `object`. Same helper, same reason, as
    // `AnalyzerAmbientContext.TypeText`.
    static func TypeText(typeInfo: TypeInfo): string {
        boxed := typeInfo as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}

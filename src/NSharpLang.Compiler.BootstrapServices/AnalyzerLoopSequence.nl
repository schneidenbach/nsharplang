namespace NSharpLang.Compiler

import System
import System.Collections.Generic
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
class YieldStatementRequest {
    Kind: int
    Node: Expression?
    Text: string?
    CarriedType: TypeInfo

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
class YieldStatementState {
    statementValue: YieldStatement
    assignabilityValue: AnalyzerAssignability

    Statement: YieldStatement => statementValue
    Assignability: AnalyzerAssignability => assignabilityValue

    Phase: int
    Pending: int
    DeclaresGenerator: bool
    YieldedType: TypeInfo
    EscapedAsRow: bool
    EscapedAsDirectColumn: bool

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

// THE SEVEN STEPS A CONDITION-AND-BODY STATEMENT CANNOT TAKE FOR ITSELF, AND EVERYTHING EACH STEP
// NEEDS.
//
// The walk owns what ALL FOUR of N#'s loop statements MEAN — `foreach x in e { … }`,
// `await foreach x in e { … }`, `while c { … }` and `for i := 0; c; u { … }` — AND what `if c { … }
// else { … }` means, because an `if` is the `while` walk with a second branch and no loop frame:
// which escape report an iterated collection's type selects and with which action word, that an
// escaped collection collapses to `unknown` before anything else looks at it, which of the two
// element-type questions is asked, what the loop variable's type therefore is, which scope kind
// opens and at which position, whether a condition is asked to be a boolean and under whose name,
// what a condition PROVES about the branch it guards and in which scope those facts are installed,
// that a branch which always leaves hands the SURVIVING flow the OTHER branch's facts, the ORDER of
// every replayed operation, and that a loop body — and only a loop body — runs inside an open loop.
// What it cannot do is run the analyzer's own EXPRESSION walk, open or close a scope on the
// analyzer's scope stack, declare a name into that stack, write the semantic model the IDE reads,
// re-enter the STATEMENT dispatch, or run the statement-level expression walk that owns a `for`
// iterator — so it ASKS: one request at a time, each naming a kind and carrying every value the step
// needs. Nothing here is a policy the driver may reinterpret — the driver switches on `Kind`,
// performs exactly the one operation with exactly these operands, and hands the answer back.
//
// The kinds:
//   1  analyse an EXPRESSION — a `foreach` collection or a `while`/`for`/`if` condition — WITHOUT
//      touching the analyzer's ambient target-typing slot, which no arm in this family ever set.
//      ANSWERS a type: for `foreach` it is the operand of both escape reports and of the
//      element-type question that settles every step after it; for a condition it is the operand of
//      the boolean gate.
//   2  open a block scope on the analyzer's scope stack at `Line` / `Column`.
//   3  declare the loop variable into the analyzer's scope stack, under `CarriedType`. No
//      declaration kind is carried: no arm tagged one, so the analyzer derives it. `foreach` only.
//   4  record the loop variable in the semantic model the IDE's hover and completion read.
//      `foreach` only.
//   5  analyse ONE STATEMENT — a loop body, a `for` initializer, or an `if` branch — which re-enters
//      the statement dispatch and therefore this walk itself. This is ONE statement, not a list: it
//      is deliberately NOT `ExpressionStatementRequest`'s kind 5, because the list walk also runs the
//      unreachable-code rule, and none of a loop body, a `for` initializer or an `if` branch ever had
//      that rule applied to it. An `else if` needs nothing of its own: it IS an `if` statement in the
//      else slot, so this step hands it back to the dispatch and the chain walks itself.
//   6  close a scope kind 2 opened.
//   7  run the STATEMENT-LEVEL EXPRESSION walk over a `for` loop's update clause — the one step in
//      this estate where a driver drives a driver. It is here rather than in the dispatch because
//      the arm that used to write it is gone: WHETHER a `for` has an iterator, WHEN in the eight
//      replayed operations it runs, and that it runs as the for-iterator form of that family rather
//      than as a bare expression statement are all this walk's decisions. What the driver adds is
//      only the two things N# cannot do for itself — construct that family's state and run its
//      loop — and it performs them with the expression it is handed and nothing else.
//
// The numbering is this walk's own protocol with its own driver and starts at 1 with no gaps; the
// other walks' numbers mean different operations, and none of them is a shared vocabulary.
class LoopStatementRequest {
    Kind: int
    Node: Expression?
    Body: Statement?
    Name: string?
    CarriedType: TypeInfo
    Line: int
    Column: int

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

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// ONE state serves ALL FIVE statements, because ONE driver serves them all. The five AST nodes are
// structurally unrelated — `ForeachStatement` and `AwaitForEachStatement` share no base beyond
// `Statement`, and `WhileStatement`, `ForStatement` and `IfStatement` share none with them — so the
// state carries the OPERANDS rather than the node, and `Form` says which walk is running: 0 is the
// iteration family (`IsAsync` separates its two members), 1 is `while`, 2 is `for`, 3 is `if`.
// Exactly the operands that form uses are non-null.
//
// `Phase` is the walk's program counter, and each form owns a BAND of it so a phase number never
// means two things. The ITERATION family runs 0..6: 0 asks for the collection; 1 folds the answer
// in, runs the two escape reports in order and settles the element type; 2 through 5 are the four
// replayed operations, with the loop opened at 4 and closed at 5; and 6 finishes. `while` runs
// 10..14. `for` runs 20..29. `if` runs 30..37. 99 is done for all four.
//
// `LoopFrame` is the ambient snapshot `EnterLoop` hands back. It is held on the state rather than in
// a local because the walk SUSPENDS between opening the loop and closing it — the body runs in the
// driver — and it is nullable only because a state exists before the loop has been opened. An `if`
// never opens one: `break` and `continue` are no more legal inside an `if` than outside it.
//
// `BodyNarrowings` is what the condition PROVED when it is TRUE, held because the facts are
// extracted at one phase, installed at a second and the branch runs at a third, with the driver in
// between. `ElseNarrowings` is what it proved when it is FALSE, and only `if` has one — a loop's
// false branch is the code after the loop, which no loop arm ever narrowed. `ElseBody` is the `if`'s
// second branch, and it is the ONLY optional body in the family.
//
// THE FLOW-NARROWING WRITER IS PASSED IN AT `Begin` RATHER THAN HELD, and it is the third member of
// this estate to be handed that way after the assignability oracle in `BeginYield` and `BeginReturn`.
// `Analyzer.cs` REBUILDS it when the metadata load context opens and again when it is disposed —
// it holds assignability, which the rebuild replaces — so an owner constructed once may not keep a
// reference to it. The iteration family passes null: neither `foreach` arm ever narrowed anything.
class LoopStatementState {
    formValue: int
    variableNameValue: string?
    collectionValue: Expression?
    conditionValue: Expression?
    initializerValue: Statement?
    iteratorValue: Expression?
    bodyValue: Statement
    elseBodyValue: Statement?
    lineValue: int
    columnValue: int
    isAsyncValue: bool
    narrowingValue: AnalyzerFlowNarrowing?

    Form: int => formValue
    VariableName: string? => variableNameValue
    Collection: Expression? => collectionValue
    Condition: Expression? => conditionValue
    Initializer: Statement? => initializerValue
    Iterator: Expression? => iteratorValue
    Body: Statement => bodyValue
    ElseBody: Statement? => elseBodyValue
    Line: int => lineValue
    Column: int => columnValue
    IsAsync: bool => isAsyncValue
    Narrowing: AnalyzerFlowNarrowing? => narrowingValue

    Phase: int
    Pending: int
    CollectionType: TypeInfo
    ElementType: TypeInfo
    ConditionType: TypeInfo
    BodyNarrowings: List<FlowNarrowing>?
    ElseNarrowings: List<FlowNarrowing>?
    LoopFrame: AmbientContextFrame?

    constructor(form: int, variableName: string?, collection: Expression?, condition: Expression?, initializer: Statement?, iterator: Expression?, body: Statement, elseBody: Statement?, line: int, column: int, isAsync: bool, narrowing: AnalyzerFlowNarrowing?) {
        formValue = form
        variableNameValue = variableName
        collectionValue = collection
        conditionValue = condition
        initializerValue = initializer
        iteratorValue = iterator
        bodyValue = body
        elseBodyValue = elseBody
        lineValue = line
        columnValue = column
        isAsyncValue = isAsync
        narrowingValue = narrowing
        Phase = 0
        if form == 1 {
            Phase = 10
        }

        if form == 2 {
            Phase = 20
        }

        if form == 3 {
            Phase = 30
        }

        Pending = 0
        CollectionType = BuiltInTypes.Unknown
        ElementType = BuiltInTypes.Unknown
        ConditionType = BuiltInTypes.Unknown
        BodyNarrowings = null
        ElseNarrowings = null
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
// EVERY STATEMENT BUILT FROM A CONDITION AND A BODY LIVES HERE, and so does the `yield` that feeds a
// generator. `foreach`, `await foreach`, `while`, `for`, `if` and `yield` are six walks over one
// request type, one state and one driver. The element-type question is why the iteration arms are
// here; `while` and `for` are here because they are the SAME WALK as `foreach` with a condition in
// place of a collection, and `if` is here because it is the `while` walk with a second branch and no
// loop frame — cutting a second protocol for any of them would have been more request types for one
// shape. The family therefore owns the whole of what a loop is in N# — what iterating a value
// produces, what a loop condition must be, what it proves about the body, and that `break` and
// `continue` are legal inside exactly the body and nothing else — and the whole of what a
// CONDITIONAL is: what each branch is told, and what survives the statement when a branch leaves.
//
// WHAT IT HOLDS AND WHAT IT IS HANDED. Every collaborator below is constructed exactly once by
// `Analyzer.cs` and never rebuilt with the metadata load context, which is why holding them is safe:
// the diagnostic sink, the span reader, the scope stack, the declaration context, the type resolver,
// the ambient context and the SoA escape owner — and now the BOOLEAN-CONDITION owner, whose gate the
// `while` and `for` arms each ran by hand. The two things `Analyzer.cs` DOES rebuild are handed in at
// `Begin` instead: the assignability oracle for `yield`, and the flow-narrowing writer for `while`
// and `for`.
class AnalyzerLoopSequence {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    typeResolverValue: AnalyzerTypeResolver
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape
    conditionsValue: AnalyzerBooleanConditions

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, typeResolver: AnalyzerTypeResolver, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape, conditions: AnalyzerBooleanConditions) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
        ambientValue = ambient
        soaEscapeValue = soaEscape
        conditionsValue = conditions
    }

    // THE `foreach` COLLECTION'S ELEMENT TYPE, plus the report when there is not one. The declared
    // variable's type is `unknown` when the collection is not enumerable, and the report is SILENT
    // for a collection whose type is already unknown or still external — a second complaint about a
    // value nothing could type is noise.
    func ResolveForeachElementType(collection: Expression, collectionType: TypeInfo): TypeInfo {
        return ResolveLoopElementType(collection, collectionType, false, "foreach", "enumerable", "Use an array, Span<T>, or IEnumerable<T> value as the foreach collection.")
    }

    // THE `await foreach` COLLECTION'S ELEMENT TYPE. Same shape, different question: only an async
    // sequence answers, so an array or a `List<T>` reaches the report here.
    func ResolveAwaitForeachElementType(collection: Expression, collectionType: TypeInfo): TypeInfo {
        return ResolveLoopElementType(collection, collectionType, true, "await foreach", "async enumerable", "Use an IAsyncEnumerable<T> value as the await foreach collection.")
    }

    func ResolveLoopElementType(collection: Expression, collectionType: TypeInfo, requireAsync: bool, loopKind: string, expectedKind: string, suggestion: string): TypeInfo {
        elementType := GetLoopSequenceElementType(collectionType, requireAsync)
        if elementType != null {
            return elementType
        }

        if ShouldReportLoopSequenceTypeMismatch(collectionType) {
            span := spansValue.GetExpressionDiagnosticSpan(collection)
            diagnosticsValue.Report(ErrorCode.TypeMismatch, loopKind + " collection must be " + expectedKind + ", but this collection is '" + TypeText(collectionType) + "'", span.Line, span.Column, suggestion, span.Length)
        }

        return BuiltInTypes.Unknown
    }

    // WHETHER A FAILED LOOKUP IS WORTH REPORTING. An unknown type already carries whatever error made
    // it unknown, and an external type is one the analyzer has not finished resolving.
    func ShouldReportLoopSequenceTypeMismatch(collectionType: TypeInfo): bool {
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
    func GetLoopSequenceElementType(collectionType: TypeInfo, requireAsync: bool): TypeInfo? {
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
    func NormalizeShapeType(candidate: TypeInfo): TypeInfo {
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
    func GetSourceLoopSequenceElementType(interfaceReferences: TypeReference[], requireAsync: bool): TypeInfo? {
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
            if candidate.get_IsGenericType() && candidate.GetGenericTypeDefinition() == expectedInterfaceDefinition {
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
            throw new InvalidOperationException("Required async sequence interface System.Collections.Generic.IAsyncEnumerable`1 was not found.")
        }

        return definition
    }

    static func NonGenericSequenceType(): Type {
        sequence := Type.GetType("System.Collections.IEnumerable")
        if sequence == null {
            throw new InvalidOperationException("Required sequence interface System.Collections.IEnumerable was not found.")
        }

        return sequence
    }

    // WHAT A GENERATOR'S `yield` MUST PRODUCE: the element type of the function's own declared return
    // type, asked as an ASYNC sequence when the function is `async func*` and as a synchronous one
    // otherwise. The `async` modifier is read from the ambient context at the moment of asking.
    func GetGeneratorYieldElementType(returnType: TypeInfo): TypeInfo? {
        return GetLoopSequenceElementType(returnType, ambientValue.CurrentFunctionDeclaresAsync)
    }

    // THE `yield` STATEMENT'S ENTRY. The assignability oracle is read from the caller's field HERE,
    // for the reason `YieldStatementState` records.
    func BeginYield(statement: YieldStatement, assignability: AnalyzerAssignability): YieldStatementState {
        return new YieldStatementState(statement, assignability)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this `yield` is finished.
    func NextStep(state: YieldStatementState): YieldStatementRequest? {
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
    func Supply(state: YieldStatementState, answer: TypeInfo?) {
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
            diagnosticsValue.Report(ErrorCode.InvalidSyntax, "'yield' can only be used inside a generator function", statement.Line, statement.Column, "Mark the function as `func*`/`async func*`, or replace `yield` with `return` in an ordinary function.", 5)
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
        state.EscapedAsRow = soaEscapeValue.ReportSoaRowEscapeIfNeeded(value, state.YieldedType, "yielded")
        return null
    }

    func AdvanceDirectColumnEscape(state: YieldStatementState): YieldStatementRequest? {
        value := state.Statement.Value
        if value == null {
            state.Phase = 99
            return null
        }

        state.Phase = 3
        state.EscapedAsDirectColumn = soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(value, "yielded")
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
            diagnosticsValue.Report(ErrorCode.TypeMismatch, "Generator yield value is '" + TypeText(yieldedType) + "', but the sequence element type is '" + elementText + "'", span.Line, span.Column, "Yield a value assignable to '" + elementText + "', or change the generator return type.", span.Length)
        }

        return null
    }

    // THE `foreach` STATEMENT'S ENTRY. The operands are read off the node here, so the walk never
    // holds an AST node whose type is one of four unrelated classes.
    func BeginForeach(statement: ForeachStatement): LoopStatementState {
        return new LoopStatementState(0, statement.VariableName, statement.Collection, null, null, null, statement.Body, null, statement.Line, statement.Column, false, null)
    }

    // THE `await foreach` STATEMENT'S ENTRY — the same walk with `IsAsync` set, which is the whole
    // difference between the two arms.
    func BeginAwaitForeach(statement: AwaitForEachStatement): LoopStatementState {
        return new LoopStatementState(0, statement.VariableName, statement.Collection, null, null, null, statement.Body, null, statement.Line, statement.Column, true, null)
    }

    // THE `while` STATEMENT'S ENTRY. It carries no position of its own: the only scope a `while` ever
    // opens is the narrowing scope, and that opens at the BODY's position rather than the keyword's.
    func BeginWhile(statement: WhileStatement, narrowing: AnalyzerFlowNarrowing): LoopStatementState {
        return new LoopStatementState(1, null, null, statement.Condition, null, null, statement.Body, null, statement.Line, statement.Column, false, narrowing)
    }

    // THE `for` STATEMENT'S ENTRY. All three clauses are OPTIONAL and each one's absence changes the
    // walk: no initializer skips a statement, no condition skips both the boolean gate AND the
    // narrowing that a condition would otherwise prove, and no iterator skips the nested walk.
    func BeginFor(statement: ForStatement, narrowing: AnalyzerFlowNarrowing): LoopStatementState {
        return new LoopStatementState(2, null, null, statement.Condition, statement.Initializer, statement.Iterator, statement.Body, null, statement.Line, statement.Column, false, narrowing)
    }

    // THE `if` STATEMENT'S ENTRY, AND THE FAMILY'S ONLY TWO-BRANCH FORM. It carries no position of
    // its own for the same reason `while` does not: the only scopes an `if` ever opens are its two
    // narrowing scopes, and each opens at ITS OWN BRANCH's position rather than at the keyword's.
    // `else if` needs no entry of its own — the parser puts an `IfStatement` in the else slot, and
    // the branch step hands it back to the statement dispatch, which arrives here again.
    func BeginIf(statement: IfStatement, narrowing: AnalyzerFlowNarrowing): LoopStatementState {
        return new LoopStatementState(3, null, null, statement.Condition, null, null, statement.ThenStatement, statement.ElseStatement, statement.Line, statement.Column, false, narrowing)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this loop is finished.
    func NextLoopStep(state: LoopStatementState): LoopStatementRequest? {
        while state.Phase != 99 {
            request := AdvanceLoop(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything, and which slot it lands in
    // is the FORM's business: the iteration family folds a collection type, and `while`, `for` and
    // `if` fold a condition type. The replayed operations, the branch walks and the nested iterator
    // walk answer nothing, and nothing is folded in for them.
    func SupplyLoop(state: LoopStatementState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending != 1 {
            return
        }

        if state.Form == 0 {
            if answer != null {
                state.CollectionType = answer
            }

            return
        }

        if answer != null {
            state.ConditionType = answer
        } else {
            state.ConditionType = BuiltInTypes.Unknown
        }
    }

    func AdvanceLoop(state: LoopStatementState): LoopStatementRequest? {
        form := state.Form
        if form == 1 {
            return AdvanceWhile(state)
        }

        if form == 2 {
            return AdvanceFor(state)
        }

        if form == 3 {
            return AdvanceIf(state)
        }

        return AdvanceForeach(state)
    }

    func AdvanceForeach(state: LoopStatementState): LoopStatementRequest? {
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
    func AdvanceForeachCollection(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 1
        state.Pending = 1
        request := new LoopStatementRequest(1, BuiltInTypes.Unknown)
        request.Node = state.Collection
        return request
    }

    // PHASE 1 — THE TWO ESCAPES AND THE ELEMENT TYPE. The reports run in order and the second is
    // SHORT-CIRCUITED by the first: a row view that has already been refused must not also be told
    // it is a direct column read. Either report collapses the collection to `unknown`, which is what
    // silences the element-type mismatch that would otherwise follow — one bad collection is one
    // diagnostic, not two.
    func AdvanceForeachElementType(state: LoopStatementState): LoopStatementRequest? {
        collection := state.Collection
        if collection == null {
            state.Phase = 99
            return null
        }

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
        request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 2 — the loop variable, declared at the STATEMENT's position rather than the variable's,
    // because that is the position `Analyzer.cs` passed and it is what the binding map records.
    func AdvanceForeachDeclare(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 3
        request := new LoopStatementRequest(3, state.ElementType)
        request.Name = state.VariableName
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 3 — the semantic model the IDE's hover and completion read. A separate step from the
    // scope declaration for the reason `AnalyzerVariableDeclaration` records: it writes a different
    // store, keyed by the semantic scope id rather than by the analyzer's own stack.
    func AdvanceForeachRecord(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 4
        request := new LoopStatementRequest(4, state.ElementType)
        request.Name = state.VariableName
        return request
    }

    // PHASE 4 — the loop opens, THEN the body runs. The frame is taken here rather than at entry
    // because the collection expression is not inside the loop: a `break` written in it is as
    // illegal as one written outside.
    func AdvanceForeachBody(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 5
        state.LoopFrame = ambientValue.EnterLoop()
        request := new LoopStatementRequest(5, BuiltInTypes.Unknown)
        request.Body = state.Body
        return request
    }

    // PHASE 5 — the loop closes BEFORE the scope does, which is the order `Analyzer.cs` used.
    func AdvanceForeachClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 6
        frame := state.LoopFrame
        if frame != null {
            ambientValue.ExitLoop(frame)
        }

        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // ── THE `while` WALK ───────────────────────────────────────────────────────────────────────
    //
    // Five phases for a loop that has no variable, no collection and no scope of its own. The one
    // scope it can open is the NARROWING scope, and it opens only when the condition actually proved
    // something — `while x != null { … }` gets one, `while i < n { … }` does not, and that difference
    // is visible to every name lookup inside the body.
    func AdvanceWhile(state: LoopStatementState): LoopStatementRequest? {
        phase := state.Phase
        if phase == 10 {
            return AdvanceWhileCondition(state)
        }

        if phase == 11 {
            return AdvanceWhileGate(state)
        }

        if phase == 12 {
            return AdvanceWhileNarrowedBody(state)
        }

        if phase == 13 {
            return AdvanceWhileNarrowedClose(state)
        }

        if phase == 14 {
            return AdvanceWhileClose(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 10 — the condition, and nothing before it. The loop is NOT open yet: a `break` written
    // inside the condition is as illegal as one written outside, exactly as for a `foreach`
    // collection.
    func AdvanceWhileCondition(state: LoopStatementState): LoopStatementRequest? {
        condition := state.Condition
        if condition == null {
            state.Phase = 99
            return null
        }

        state.Phase = 11
        state.Pending = 1
        request := new LoopStatementRequest(1, BuiltInTypes.Unknown)
        request.Node = condition
        return request
    }

    // PHASE 11 — WHAT THE CONDITION IS AND WHAT IT PROVES, IN THAT ORDER OF EXECUTION AND NOT OF
    // READING. The narrowings are extracted BEFORE the boolean gate reports, which is the order
    // `Analyzer.cs` wrote and is preserved rather than tidied: the extractor consults the scope stack,
    // and a report that changed it would change what a later extraction saw. Then the loop opens, and
    // only then does the body run — with the proved facts installed in their own scope when there
    // are any.
    func AdvanceWhileGate(state: LoopStatementState): LoopStatementRequest? {
        condition := state.Condition
        if condition == null {
            state.Phase = 99
            return null
        }

        narrowing := state.Narrowing
        if narrowing != null {
            state.BodyNarrowings = narrowing.ExtractFlowNarrowings(condition).Then
        }

        conditionsValue.ReportConditionTypeMismatchIfNeeded(condition, "a 'while' loop", "used as a 'while' condition", state.ConditionType)
        state.LoopFrame = ambientValue.EnterLoop()

        if NarrowingCount(state) > 0 {
            state.Phase = 12
            request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
            request.Line = state.Body.Line
            request.Column = state.Body.Column
            return request
        }

        state.Phase = 14
        return NewBodyRequest(state)
    }

    // PHASE 12 — the proved facts are installed in the scope phase 11 just opened, and then the body
    // runs inside them.
    func AdvanceWhileNarrowedBody(state: LoopStatementState): LoopStatementRequest? {
        ApplyBodyNarrowings(state)
        state.Phase = 13
        return NewBodyRequest(state)
    }

    // PHASE 13 — the narrowing scope closes. The loop is still open: `Analyzer.cs` closed the scope
    // first and the loop second.
    func AdvanceWhileNarrowedClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 14
        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 14 — the loop closes. Both paths reach it, which is what makes the frame balanced whether
    // or not the condition proved anything.
    func AdvanceWhileClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 99
        ExitLoopFrame(state)
        return null
    }

    // ── THE `for` WALK ─────────────────────────────────────────────────────────────────────────
    //
    // The SAME walk as `while` with three optional clauses around it, which is why they share a state
    // and a driver rather than each getting one. `for` differs in four things and nothing else: it
    // opens an OUTER scope at the keyword — so a variable the initializer declares dies at the closing
    // brace and not before — it runs an initializer STATEMENT inside that scope, it runs an update
    // expression through the statement-level expression family, and every one of its condition-shaped
    // steps is skipped when there is no condition. A `for` with no condition narrows nothing, because
    // there is nothing to prove.
    func AdvanceFor(state: LoopStatementState): LoopStatementRequest? {
        phase := state.Phase
        if phase == 20 {
            return AdvanceForOuterScope(state)
        }

        if phase == 21 {
            return AdvanceForInitializer(state)
        }

        if phase == 22 {
            return AdvanceForCondition(state)
        }

        if phase == 23 {
            return AdvanceForGate(state)
        }

        if phase == 24 {
            return AdvanceForIterator(state)
        }

        if phase == 25 {
            return AdvanceForBody(state)
        }

        if phase == 26 {
            return AdvanceForNarrowedBody(state)
        }

        if phase == 27 {
            return AdvanceForNarrowedClose(state)
        }

        if phase == 28 {
            return AdvanceForClose(state)
        }

        if phase == 29 {
            return AdvanceForOuterClose(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 20 — the outer scope, opened at the `for` KEYWORD rather than at the body. That position
    // is the whole reason this scope exists: it is what makes `for i := 0; …` declare `i` for the
    // loop and not for the enclosing block.
    func AdvanceForOuterScope(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 21
        request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // PHASE 21 — the initializer, which is a STATEMENT and re-enters the statement dispatch. It runs
    // inside the outer scope and OUTSIDE the loop, so a `break` written in it is illegal.
    func AdvanceForInitializer(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 22
        initializer := state.Initializer
        if initializer == null {
            return null
        }

        request := new LoopStatementRequest(5, BuiltInTypes.Unknown)
        request.Body = initializer
        return request
    }

    // PHASE 22 — the condition, when there is one.
    func AdvanceForCondition(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 23
        condition := state.Condition
        if condition == null {
            return null
        }

        state.Pending = 1
        request := new LoopStatementRequest(1, BuiltInTypes.Unknown)
        request.Node = condition
        return request
    }

    // PHASE 23 — the boolean gate. Unlike `while`, the narrowings are NOT extracted here: the `for`
    // arm extracted them after the loop opened, which is phase 25, and the order is preserved.
    func AdvanceForGate(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 24
        condition := state.Condition
        if condition == null {
            return null
        }

        conditionsValue.ReportConditionTypeMismatchIfNeeded(condition, "a 'for' loop", "used as a 'for' condition", state.ConditionType)
        return null
    }

    // PHASE 24 — the update clause, run through the statement-level expression family as a `for`
    // ITERATOR rather than as a bare expression statement, which is what selects that family's
    // for-iterator wordings. It runs BEFORE the body and OUTSIDE the loop, which is what
    // `Analyzer.cs` did: the update expression is analysed once, in declaration order, and a `break`
    // written in it is illegal.
    func AdvanceForIterator(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 25
        iterator := state.Iterator
        if iterator == null {
            return null
        }

        request := new LoopStatementRequest(7, BuiltInTypes.Unknown)
        request.Node = iterator
        return request
    }

    // PHASE 25 — the loop opens, THEN the condition's facts are extracted, THEN the body runs. A
    // `for` with no condition proves nothing and takes the plain body path.
    func AdvanceForBody(state: LoopStatementState): LoopStatementRequest? {
        state.LoopFrame = ambientValue.EnterLoop()
        condition := state.Condition
        narrowing := state.Narrowing
        if condition != null && narrowing != null {
            state.BodyNarrowings = narrowing.ExtractFlowNarrowings(condition).Then
        }

        if NarrowingCount(state) > 0 {
            state.Phase = 26
            request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
            request.Line = state.Body.Line
            request.Column = state.Body.Column
            return request
        }

        state.Phase = 28
        return NewBodyRequest(state)
    }

    // PHASE 26 — the proved facts, installed in the scope phase 25 opened.
    func AdvanceForNarrowedBody(state: LoopStatementState): LoopStatementRequest? {
        ApplyBodyNarrowings(state)
        state.Phase = 27
        return NewBodyRequest(state)
    }

    // PHASE 27 — the narrowing scope closes.
    func AdvanceForNarrowedClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 28
        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 28 — the loop closes, and the OUTER scope closes after it. That is the order
    // `Analyzer.cs` used, and it matters: the ambient loop depth is restored before the scope stack
    // is popped.
    func AdvanceForClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 29
        ExitLoopFrame(state)
        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 29 — done.
    func AdvanceForOuterClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 99
        return null
    }

    // ── THE `if` WALK ──────────────────────────────────────────────────────────────────────────
    //
    // THE `while` WALK WITH A SECOND BRANCH AND NO LOOP FRAME, which is why it is here rather than in
    // an owner of its own. It asks the same condition question of the same gate, extracts the same
    // narrowings from the same writer, and opens the same kind of narrowing scope at the same kind of
    // position — and it differs in exactly three things.
    //
    // FIRST, IT NEVER OPENS A LOOP. `break` and `continue` are no more legal inside an `if` than
    // outside one, so no ambient frame is entered and none is restored; the branch simply runs in
    // whatever frame the `if` was written in.
    //
    // SECOND, IT HAS TWO BRANCHES AND EACH GETS ITS OWN FACTS. `ExtractFlowNarrowings` yields both
    // lists at once — what the condition proves when TRUE and what it proves when FALSE — and each
    // branch is walked inside its own scope only when its own list is non-empty. An `if` whose
    // condition proves nothing opens NO scope at all, which is why a variable declared directly in an
    // un-narrowed branch behaves differently from one declared in a narrowed branch; that is the
    // behaviour `Analyzer.cs` had and it is preserved rather than regularised.
    //
    // THIRD, AND ONLY HERE IN THE WHOLE FAMILY, A BRANCH THAT ALWAYS LEAVES CHANGES THE FLOW AFTER
    // THE STATEMENT. `if x == null { return }` is a GUARD CLAUSE: the reader experiences its facts
    // AFTER the `if` rather than inside it, so when the then-branch always leaves and the else-branch
    // does not, the ELSE facts are installed into the surviving flow — into the ENCLOSING scope, with
    // no scope of their own, because there is no branch left to scope them to. The mirror case
    // installs the THEN facts when the else-branch always leaves. The two are NOT symmetric: the
    // first arm additionally requires that the else-branch does NOT always leave, so an `if` whose
    // BOTH branches leave installs nothing — there is no surviving flow to inform. That asymmetry is
    // `Analyzer.cs`'s, character for character.
    //
    // THE TERMINATION QUESTION IS ASKED LAST, AFTER BOTH BRANCHES HAVE BEEN WALKED, because that is
    // where `Analyzer.cs` asked it. It is a PURE question about the AST — `AnalyzerStatementTermination`
    // reads no analysis state — so the position is preserved for readability rather than for
    // behaviour, and it is a direct call rather than a step because nothing about it needs the driver.
    //
    // AN `else if` IS NOT A SHAPE THIS WALK KNOWS. The parser puts an `IfStatement` in the else slot,
    // so the else branch step hands it to the statement dispatch and this walk is entered again for
    // it, one level down, with its own condition, its own two narrowing lists and its own guard-clause
    // rule. A chain of any length therefore needs nothing here at all.
    func AdvanceIf(state: LoopStatementState): LoopStatementRequest? {
        phase := state.Phase
        if phase == 30 {
            return AdvanceIfCondition(state)
        }

        if phase == 31 {
            return AdvanceIfGate(state)
        }

        if phase == 32 {
            return AdvanceIfThenNarrowedBody(state)
        }

        if phase == 33 {
            return AdvanceIfThenNarrowedClose(state)
        }

        if phase == 34 {
            return AdvanceIfElse(state)
        }

        if phase == 35 {
            return AdvanceIfElseNarrowedBody(state)
        }

        if phase == 36 {
            return AdvanceIfElseNarrowedClose(state)
        }

        if phase == 37 {
            return AdvanceIfGuardClause(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 30 — the condition, and nothing before it.
    func AdvanceIfCondition(state: LoopStatementState): LoopStatementRequest? {
        condition := state.Condition
        if condition == null {
            state.Phase = 99
            return null
        }

        state.Phase = 31
        state.Pending = 1
        request := new LoopStatementRequest(1, BuiltInTypes.Unknown)
        request.Node = condition
        return request
    }

    // PHASE 31 — WHAT THE CONDITION IS AND WHAT IT PROVES, IN THAT ORDER OF EXECUTION AND NOT OF
    // READING. BOTH narrowing lists are extracted BEFORE the boolean gate reports, which is the order
    // `Analyzer.cs` wrote and is preserved rather than tidied: the extractor consults the scope stack,
    // and a report that changed it would change what a later extraction saw. The gate is the RICH `if`
    // report — the only one of the five conditions that earns the underline and the conversion hint.
    // Then the then-branch runs, inside its proved facts when it has any.
    func AdvanceIfGate(state: LoopStatementState): LoopStatementRequest? {
        condition := state.Condition
        if condition == null {
            state.Phase = 99
            return null
        }

        narrowing := state.Narrowing
        if narrowing != null {
            split := narrowing.ExtractFlowNarrowings(condition)
            state.BodyNarrowings = split.Then
            state.ElseNarrowings = split.Else
        }

        conditionsValue.ReportIfConditionTypeMismatchIfNeeded(condition, state.ConditionType)

        if NarrowingCount(state) > 0 {
            state.Phase = 32
            request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
            request.Line = state.Body.Line
            request.Column = state.Body.Column
            return request
        }

        state.Phase = 34
        return NewBodyRequest(state)
    }

    // PHASE 32 — the true-branch facts are installed in the scope phase 31 just opened, and then the
    // then-branch runs inside them.
    func AdvanceIfThenNarrowedBody(state: LoopStatementState): LoopStatementRequest? {
        ApplyBodyNarrowings(state)
        state.Phase = 33
        return NewBodyRequest(state)
    }

    // PHASE 33 — the then-branch's narrowing scope closes, and the facts it carried die with it.
    func AdvanceIfThenNarrowedClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 34
        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 34 — the else branch, which is the family's only optional body. No else branch skips
    // straight to the guard-clause rule; an else branch with proved facts opens its own scope at ITS
    // OWN position rather than at the then-branch's.
    func AdvanceIfElse(state: LoopStatementState): LoopStatementRequest? {
        elseBody := state.ElseBody
        if elseBody == null {
            state.Phase = 37
            return null
        }

        if ElseNarrowingCount(state) > 0 {
            state.Phase = 35
            request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
            request.Line = elseBody.Line
            request.Column = elseBody.Column
            return request
        }

        state.Phase = 37
        return NewElseBodyRequest(elseBody)
    }

    // PHASE 35 — the false-branch facts are installed in the scope phase 34 just opened, and then the
    // else branch runs inside them.
    func AdvanceIfElseNarrowedBody(state: LoopStatementState): LoopStatementRequest? {
        ApplyElseNarrowings(state)
        state.Phase = 36
        elseBody := state.ElseBody
        if elseBody == null {
            return null
        }

        return NewElseBodyRequest(elseBody)
    }

    // PHASE 36 — the else branch's narrowing scope closes.
    func AdvanceIfElseNarrowedClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 37
        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 37 — THE GUARD-CLAUSE RULE, and the one place in this family where facts outlive the
    // statement that proved them. Both branches have already been walked; what is decided here is
    // what the code AFTER the `if` knows. The termination questions are asked in the then/else order
    // `Analyzer.cs` asked them, and the else question is not asked at all when there is no else
    // branch — which is the same answer, and is preserved as the same shape.
    func AdvanceIfGuardClause(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 99
        thenAlwaysReturns := AnalyzerStatementTermination.AlwaysReturns(state.Body)
        elseBody := state.ElseBody
        elseAlwaysReturns := elseBody != null && AnalyzerStatementTermination.AlwaysReturns(elseBody)

        if thenAlwaysReturns && !elseAlwaysReturns && ElseNarrowingCount(state) > 0 {
            ApplyElseNarrowings(state)
            return null
        }

        if elseAlwaysReturns && NarrowingCount(state) > 0 {
            ApplyBodyNarrowings(state)
        }

        return null
    }

    // ── WHAT THE CONDITION FORMS SHARE ─────────────────────────────────────────────────────────

    // HOW MANY FACTS THE CONDITION PROVED WHEN TRUE. Zero when it proved none and zero when there was
    // no narrowing writer to ask, which is the same answer for the walk's purposes: no narrowing
    // scope.
    func NarrowingCount(state: LoopStatementState): int {
        narrowings := state.BodyNarrowings
        if narrowings == null {
            return 0
        }

        return narrowings.Count
    }

    // HOW MANY FACTS THE CONDITION PROVED WHEN FALSE. Only `if` ever has any: a loop's false branch is
    // the code after the loop, and no loop arm ever narrowed it.
    func ElseNarrowingCount(state: LoopStatementState): int {
        narrowings := state.ElseNarrowings
        if narrowings == null {
            return 0
        }

        return narrowings.Count
    }

    // INSTALL WHAT THE CONDITION PROVED WHEN TRUE into the scope that is currently open for it — the
    // branch's own narrowing scope for `while`, `for` and an `if`'s then-branch, and the ENCLOSING
    // scope when an `if`'s else-branch always leaves and the facts outlive the statement.
    func ApplyBodyNarrowings(state: LoopStatementState) {
        narrowings := state.BodyNarrowings
        narrowing := state.Narrowing
        if narrowings != null && narrowing != null {
            narrowing.ApplyNarrowingsToScope(narrowings)
        }
    }

    // INSTALL WHAT THE CONDITION PROVED WHEN FALSE, into the else-branch's own narrowing scope or —
    // for a guard clause whose then-branch always leaves — into the enclosing scope.
    func ApplyElseNarrowings(state: LoopStatementState) {
        narrowings := state.ElseNarrowings
        narrowing := state.Narrowing
        if narrowings != null && narrowing != null {
            narrowing.ApplyNarrowingsToScope(narrowings)
        }
    }

    // THE BODY STEP, which is the same request for every walk: a loop body, a `for` initializer, or
    // an `if`'s then-branch.
    func NewBodyRequest(state: LoopStatementState): LoopStatementRequest {
        request := new LoopStatementRequest(5, BuiltInTypes.Unknown)
        request.Body = state.Body
        return request
    }

    // THE ELSE-BRANCH STEP. It is the same kind as the body step and differs only in which statement
    // it carries, which is why it takes the statement rather than reading it back off the state.
    func NewElseBodyRequest(elseBody: Statement): LoopStatementRequest {
        request := new LoopStatementRequest(5, BuiltInTypes.Unknown)
        request.Body = elseBody
        return request
    }

    // CLOSE THE AMBIENT LOOP the walk opened, which is what makes `break` and `continue` illegal
    // again on the far side of the closing brace.
    func ExitLoopFrame(state: LoopStatementState) {
        frame := state.LoopFrame
        if frame != null {
            ambientValue.ExitLoop(frame)
            state.LoopFrame = null
        }
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

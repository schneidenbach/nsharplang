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
// A DECLARED MEMBER TOGETHER WITH THE DECLARATION THAT WROTE IT. A `Current` inherited from a base
// class is spelled against THAT base's type parameters, not against the receiver's, so the owner and
// the substitution its arguments induced have to travel with the member — reading the member's type
// against the wrong owner is how an inherited `T Current` silently becomes the derived type's `T`.
class DeclaredSequenceMember {
    Member: DeclaredMemberInfo
    Owner: TypeInfo
    Substitution: Dictionary<string, TypeInfo>?

    constructor(member: DeclaredMemberInfo, owner: TypeInfo, substitution: Dictionary<string, TypeInfo>?) {
        if member == null || owner == null {
            throw new InvalidOperationException("A declared sequence member cannot be recorded without its declaration.")
        }

        Member = member
        Owner = owner
        Substitution = substitution
    }
}

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
    SavedExpectedType: TypeInfo?

    constructor(statement: YieldStatement, assignability: AnalyzerAssignability) {
        statementValue = statement
        assignabilityValue = assignability
        Phase = 0
        Pending = 0
        DeclaresGenerator = false
        YieldedType = BuiltInTypes.Unknown
        EscapedAsRow = false
        EscapedAsDirectColumn = false
        SavedExpectedType = null
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
//   8  analyse a BRANCH BLOCK'S STATEMENT LIST directly, in the scope this walk already opened, so
//      the block does NOT open one of its own. That is what makes the branch's exit state readable:
//      the facts a branch ends with live in a scope, and a join after the `if` can only read them if
//      the scope they live in is the one this walk owns. The list walk is the same one a block runs —
//      the same local-function hoist, the same unreachable rule — minus the scope it would have
//      pushed. A branch that is NOT a block (the `if` in an `else if`) still goes through kind 5,
//      because a statement that scopes itself must keep doing so.
//
// The numbering is this walk's own protocol with its own driver and starts at 1 with no gaps; the
// other walks' numbers mean different operations, and none of them is a shared vocabulary.
class LoopStatementRequest {
    Kind: int
    Node: Expression?
    Body: Statement?
    Statements: List<Statement>?
    Name: string?
    CarriedType: TypeInfo
    Line: int
    Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        Body = null
        Statements = null
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
    variableTypeValue: TypeReference?
    assignabilityValue: AnalyzerAssignability?

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

    // The loop variable's WRITTEN annotation (`for m: Match in …`), null for the inferred spelling,
    // and the oracle the conversion rule consults. Only the `foreach` form ever carries either.
    VariableType: TypeReference? => variableTypeValue
    Assignability: AnalyzerAssignability? => assignabilityValue

    Phase: int
    Pending: int
    CollectionType: TypeInfo
    ElementType: TypeInfo
    ConditionType: TypeInfo
    BodyNarrowings: List<FlowNarrowing>?
    ElseNarrowings: List<FlowNarrowing>?
    LoopFrame: AmbientContextFrame?

    // THE TWO BRANCHES' EXIT STATES, READ WHILE THEIR SCOPES WERE STILL OPEN. A branch's exit state is
    // the fact table it ended with, and the join that decides what the code below the `if` knows runs
    // after both branches are over — so each branch's facts are read at the moment it ends and carried
    // here. A narrowed branch ends with TWO open scopes, its narrowing scope and the block scope
    // inside it, so the tables are overlaid in that order: what the branch ASSIGNED wins over what the
    // condition PROVED. `ElseExitFacts` is null when there is no else branch, and the implicit else
    // path's facts are read off the condition instead.
    ThenExitFacts: Dictionary<string, NullState>?
    ElseExitFacts: Dictionary<string, NullState>?

    // Whether this walk opened a NARROWING scope for each branch, which it does only when that
    // branch's own list is non-empty — exactly as it always has, so a variable declared directly in a
    // narrowed branch is a SHADOW of the narrowed binding rather than a redeclaration of it.
    ThenNarrowingScopeOpened: bool
    ElseNarrowingScopeOpened: bool

    constructor(form: int, variableName: string?, collection: Expression?, condition: Expression?, initializer: Statement?, iterator: Expression?, body: Statement, elseBody: Statement?, line: int, column: int, isAsync: bool, narrowing: AnalyzerFlowNarrowing?, variableType: TypeReference? = null, assignability: AnalyzerAssignability? = null) {
        variableTypeValue = variableType
        assignabilityValue = assignability
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
        ThenExitFacts = null
        ElseExitFacts = null
        ThenNarrowingScopeOpened = false
        ElseNarrowingScopeOpened = false
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
    typeSubstitutionValue: AnalyzerTypeSubstitution
    terminatingCallsValue: AnalyzerTerminatingCalls

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, typeResolver: AnalyzerTypeResolver, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape, conditions: AnalyzerBooleanConditions, typeSubstitution: AnalyzerTypeSubstitution, terminatingCalls: AnalyzerTerminatingCalls) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
        ambientValue = ambient
        soaEscapeValue = soaEscape
        conditionsValue = conditions
        typeSubstitutionValue = typeSubstitution
        terminatingCallsValue = terminatingCalls
    }

    // THE `foreach` COLLECTION'S ELEMENT TYPE, plus the report when there is not one. The declared
    // variable's type is `unknown` when the collection is not enumerable, and the report is SILENT
    // for a collection whose type is already unknown or still external — a second complaint about a
    // value nothing could type is noise.
    func ResolveForeachElementType(collection: Expression, collectionType: TypeInfo): TypeInfo {
        return ResolveLoopElementType(collection, collectionType, false, "foreach", "enumerable", "A foreach collection needs an accessible parameterless GetEnumerator() whose result has a readable Current and a bool MoveNext(), or it must be an array, a string, an IEnumerable<T> or an IEnumerable.")
    }

    // THE `await foreach` COLLECTION'S ELEMENT TYPE. Same shape, different question: only an async
    // sequence answers, so an array or a `List<T>` reaches the report here.
    func ResolveAwaitForeachElementType(collection: Expression, collectionType: TypeInfo): TypeInfo {
        return ResolveLoopElementType(collection, collectionType, true, "await foreach", "async enumerable", "An await foreach collection must be an IAsyncEnumerable<T>; a synchronous sequence is iterated with plain foreach.")
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
    // gated on it individually rather than up front because a declared or reflected type reaches the
    // SAME pattern walk either way.
    //
    // THE DEPTH GUARD IS NOT DEFENSIVENESS. A declaration may name itself — `class Loop: ILoop` where
    // `ILoop` inherits `ILoop` — and the interface walk below recurses through this entry point, so
    // an unbounded walk would spin. The limit is the nesting any real sequence declaration reaches
    // several times over.
    func GetLoopSequenceElementType(collectionType: TypeInfo, requireAsync: bool): TypeInfo? {
        return GetLoopSequenceElementTypeAt(collectionType, requireAsync, 0)
    }

    func GetLoopSequenceElementTypeAt(collectionType: TypeInfo, requireAsync: bool, depth: int): TypeInfo? {
        if depth > 16 {
            return null
        }

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
            return GetGenericLoopSequenceElementType(genericType, requireAsync, depth)
        }

        reflectionType := resolved as ReflectionTypeInfo
        if reflectionType != null {
            return GetReflectionLoopSequenceElementType(reflectionType.Type, requireAsync)
        }

        if LoopSequenceTypeFacts.IsDeclaredShape(resolved) {
            return GetDeclaredLoopSequenceElementType(resolved, null, requireAsync, depth)
        }

        return null
    }

    // A GENERIC INSTANTIATION ANSWERS THROUGH ITS DEFINITION, AND THE ANSWER IS SUBSTITUTED BY
    // POSITION. `Dictionary<string, Widget>` reads `KeyValuePair<TKey, TValue>` off the OPEN
    // `Dictionary<,>` and rewrites `TKey`/`TValue` with the arguments the instantiation supplied —
    // which is how a `Widget` the CLR has no handle for survives into the element type. An
    // instantiation over an N#-DECLARED definition takes the declared walk under the same
    // substitution, spelled by parameter NAME because that is what a source declaration binds.
    func GetGenericLoopSequenceElementType(genericType: GenericTypeInfo, requireAsync: bool, depth: int): TypeInfo? {
        definition := typeSubstitutionValue.ResolveGenericDefinition(genericType)
        if definition == null {
            return null
        }

        reflectionDefinition := definition as ReflectionTypeInfo
        if reflectionDefinition != null {
            openElement := LoopSequenceTypeFacts.SequenceElementType(reflectionDefinition.Type, requireAsync)
            if openElement == null {
                return null
            }

            return AnalyzerReflectionTypeOverride.ForGenericArguments(reflectionDefinition.Type, genericType).Answer(openElement)
        }

        if !LoopSequenceTypeFacts.IsDeclaredShape(definition) {
            return null
        }

        substitution := declarationContextValue.CreateGenericSubstitution(definition, genericType.TypeArguments)
        return GetDeclaredLoopSequenceElementType(definition, substitution, requireAsync, depth)
    }

    // A DECLARED CLASS, STRUCT, RECORD OR INTERFACE, asked the same two questions in the same order
    // as a reflected one: the enumerator pattern first, then the sequence interfaces it names. The
    // pattern arm is what lets a user type iterate WITHOUT implementing `IEnumerable<T>`, which is
    // the C# rule and the reason `for row in table` works for a type that only wants a struct
    // enumerator. `await foreach` skips the pattern: N# resolves an async sequence through
    // `IAsyncEnumerable<T>` alone.
    func GetDeclaredLoopSequenceElementType(declaration: TypeInfo, substitution: Dictionary<string, TypeInfo>?, requireAsync: bool, depth: int): TypeInfo? {
        if !requireAsync {
            patternElement := GetDeclaredPatternElementType(declaration, substitution, depth)
            if patternElement != null {
                return patternElement
            }
        }

        interfaceElement := GetDeclaredInterfaceElementType(declaration, substitution, requireAsync, depth)
        if interfaceElement != null {
            return interfaceElement
        }

        baseReference := LoopSequenceTypeFacts.DeclaredBaseClassOf(declaration)
        if baseReference == null {
            return null
        }

        baseType := typeSubstitutionValue.ResolveTypeForSourceOwner(baseReference, declaration, substitution)
        return GetLoopSequenceElementTypeAt(baseType, requireAsync, depth + 1)
    }

    // THE FIRST DECLARED INTERFACE THAT ANSWERS, in declaration order. The recursion is through the
    // top-level question, so an interface that inherits a sequence interface answers too.
    func GetDeclaredInterfaceElementType(declaration: TypeInfo, substitution: Dictionary<string, TypeInfo>?, requireAsync: bool, depth: int): TypeInfo? {
        interfaceReferences := LoopSequenceTypeFacts.DeclaredInterfacesOf(declaration)
        for interfaceReference in interfaceReferences {
            interfaceType := typeSubstitutionValue.ResolveTypeForSourceOwner(interfaceReference, declaration, substitution)
            elementType := GetLoopSequenceElementTypeAt(interfaceType, requireAsync, depth + 1)
            if elementType != null {
                return elementType
            }
        }

        return null
    }

    // THE PATTERN ON A DECLARED TYPE: a parameterless `GetEnumerator` whose returned type carries a
    // readable `Current` and a parameterless `bool MoveNext()`. The enumerator it names may itself be
    // declared or reflected — a source collection returning `IEnumerator<T>` is as ordinary as one
    // returning its own struct — so the enumerator's members are asked through the same fan-out the
    // collection was.
    func GetDeclaredPatternElementType(declaration: TypeInfo, substitution: Dictionary<string, TypeInfo>?, depth: int): TypeInfo? {
        getEnumerator := FindDeclaredParameterlessFunction(declaration, substitution, "GetEnumerator", depth)
        if getEnumerator == null {
            return null
        }

        returnReference := getEnumerator.Member.ReturnType
        if returnReference == null {
            return null
        }

        enumeratorType := typeSubstitutionValue.ResolveTypeForSourceOwner(returnReference, getEnumerator.Owner, getEnumerator.Substitution)
        return GetEnumeratorCurrentType(enumeratorType, depth)
    }

    // WHAT AN ENUMERATOR'S `Current` IS, once `MoveNext` has proved it is one. A reflected enumerator
    // answers through the shared pattern facts; a declared one answers from its own members.
    func GetEnumeratorCurrentType(enumeratorType: TypeInfo, depth: int): TypeInfo? {
        if depth > 16 {
            return null
        }

        resolved := NormalizeShapeType(enumeratorType)

        generic := resolved as GenericTypeInfo
        if generic != null {
            definition := typeSubstitutionValue.ResolveGenericDefinition(generic)
            if definition == null {
                return null
            }

            reflectionDefinition := definition as ReflectionTypeInfo
            if reflectionDefinition != null {
                openCurrent := ReflectedEnumeratorCurrentType(reflectionDefinition.Type)
                if openCurrent == null {
                    return null
                }

                return AnalyzerReflectionTypeOverride.ForGenericArguments(reflectionDefinition.Type, generic).Answer(openCurrent)
            }

            if !LoopSequenceTypeFacts.IsDeclaredShape(definition) {
                return null
            }

            return GetDeclaredEnumeratorCurrentType(definition, declarationContextValue.CreateGenericSubstitution(definition, generic.TypeArguments), depth)
        }

        reflectionType := resolved as ReflectionTypeInfo
        if reflectionType != null {
            openCurrent := ReflectedEnumeratorCurrentType(reflectionType.Type)
            if openCurrent == null {
                return null
            }

            return AnalyzerReflectionTypeConversion.ConvertReflectionType(openCurrent)
        }

        if LoopSequenceTypeFacts.IsDeclaredShape(resolved) {
            return GetDeclaredEnumeratorCurrentType(resolved, null, depth)
        }

        return null
    }

    func ReflectedEnumeratorCurrentType(clrType: Type): Type? {
        moveNext := ForeachPatternFacts.FindParameterlessInstanceMethod(clrType, "MoveNext")
        if moveNext == null || !ForeachPatternFacts.IsBoolean(moveNext.ReturnType) {
            return null
        }

        currentGetter := ForeachPatternFacts.FindCurrentGetter(clrType)
        if currentGetter == null {
            return null
        }

        currentType := currentGetter.ReturnType
        if currentType.IsByRef {
            return currentType.GetElementType()
        }

        return currentType
    }

    func GetDeclaredEnumeratorCurrentType(declaration: TypeInfo, substitution: Dictionary<string, TypeInfo>?, depth: int): TypeInfo? {
        moveNext := FindDeclaredParameterlessFunction(declaration, substitution, "MoveNext", depth)
        if moveNext == null || moveNext.Member.ReturnType == null {
            return null
        }

        moveNextType := typeSubstitutionValue.ResolveTypeForSourceOwner(moveNext.Member.ReturnType, moveNext.Owner, moveNext.Substitution)
        if !BuiltInTypes.Is(moveNextType, BuiltInTypes.Bool) {
            return null
        }

        current := FindDeclaredReadableMember(declaration, substitution, "Current", depth)
        if current == null || current.Member.Type == null {
            return null
        }

        return typeSubstitutionValue.ResolveTypeForSourceOwner(current.Member.Type, current.Owner, current.Substitution)
    }

    // A DECLARED MEMBER FOUND WITH THE DECLARATION THAT OWNS IT. A member inherited from a base class
    // is spelled against THAT base's type parameters, so the owner and its substitution travel with
    // the member rather than being re-derived at the use site.
    func FindDeclaredParameterlessFunction(declaration: TypeInfo, substitution: Dictionary<string, TypeInfo>?, name: string, depth: int): DeclaredSequenceMember? {
        owner := declaration
        ownerSubstitution := substitution
        remaining := 16 - depth
        while remaining > 0 {
            member := LoopSequenceTypeFacts.FindDeclaredParameterlessFunction(LoopSequenceTypeFacts.DeclaredMembersOf(owner), name)
            if member != null {
                return new DeclaredSequenceMember(member, owner, ownerSubstitution)
            }

            baseReference := LoopSequenceTypeFacts.DeclaredBaseClassOf(owner)
            if baseReference == null {
                return null
            }

            baseType := NormalizeShapeType(typeSubstitutionValue.ResolveTypeForSourceOwner(baseReference, owner, ownerSubstitution))
            nextOwner := typeSubstitutionValue.GetSourceDeclarationOwner(baseType, out ownerSubstitution)
            if !LoopSequenceTypeFacts.IsDeclaredShape(nextOwner) {
                return null
            }

            owner = nextOwner
            remaining = remaining - 1
        }

        return null
    }

    func FindDeclaredReadableMember(declaration: TypeInfo, substitution: Dictionary<string, TypeInfo>?, name: string, depth: int): DeclaredSequenceMember? {
        owner := declaration
        ownerSubstitution := substitution
        remaining := 16 - depth
        while remaining > 0 {
            member := LoopSequenceTypeFacts.FindDeclaredReadableProperty(LoopSequenceTypeFacts.DeclaredMembersOf(owner), name)
            if member != null {
                return new DeclaredSequenceMember(member, owner, ownerSubstitution)
            }

            baseReference := LoopSequenceTypeFacts.DeclaredBaseClassOf(owner)
            if baseReference == null {
                return null
            }

            baseType := NormalizeShapeType(typeSubstitutionValue.ResolveTypeForSourceOwner(baseReference, owner, ownerSubstitution))
            nextOwner := typeSubstitutionValue.GetSourceDeclarationOwner(baseType, out ownerSubstitution)
            if !LoopSequenceTypeFacts.IsDeclaredShape(nextOwner) {
                return null
            }

            owner = nextOwner
            remaining = remaining - 1
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

    // THE REFLECTED WALK. A nullable reflected type is unwrapped first, exactly as the CLR-facing
    // arms elsewhere do; an ARRAY and a `string` are answered here rather than in the shared facts
    // because their lowering is an INDEX loop and only this walk knows the loop it is typing. An
    // array whose element type reflection cannot name falls THROUGH to the pattern walk rather than
    // failing outright.
    func GetReflectionLoopSequenceElementType(clrType: Type, requireAsync: bool): TypeInfo? {
        runtimeType := StripNullableRuntimeType(clrType)

        if !requireAsync && runtimeType.IsArray {
            elementReflectionType := runtimeType.GetElementType()
            if elementReflectionType != null {
                return AnalyzerReflectionTypeConversion.ConvertReflectionType(elementReflectionType)
            }
        }

        if !requireAsync && ForeachPatternFacts.IsString(runtimeType) {
            return BuiltInTypes.Char
        }

        elementType := LoopSequenceTypeFacts.SequenceElementType(runtimeType, requireAsync)
        if elementType == null {
            return null
        }

        return AnalyzerReflectionTypeConversion.ConvertReflectionType(elementType)
    }

    func StripNullableRuntimeType(clrType: Type): Type {
        underlying := Nullable.GetUnderlyingType(clrType)
        if underlying != null {
            return underlying
        }

        return clrType
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
            ambientValue.ExitExpectedType(state.SavedExpectedType)
            state.SavedExpectedType = null
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
        // A YIELDED VALUE IS TARGET-TYPED BY THE SEQUENCE IT JOINS, exactly as a returned value is
        // target-typed by the return type. Without this the value was walked with NO expected type,
        // so `yield ["a", ["b", "c"]]` in an `IEnumerable<object[]>` generator inferred its array
        // literal from the FIRST element and reported "All elements in an array must be the same
        // type", while the identical literal in a `return`, an argument or an annotated assignment
        // took the target's element type and converted each element to it. A `yield` in a function
        // that is not a generator, or whose return type names no sequence, leaves the slot ALONE
        // rather than clearing it — there is no target to impose, and the surrounding one is still
        // the truth.
        state.SavedExpectedType = ambientValue.EnterExpectedTypeIfProvided(YieldValueTargetType(state))
        request := new YieldStatementRequest(1)
        request.Node = value
        return request
    }

    // WHAT THE YIELDED EXPRESSION IS ASKED FOR: the sequence's ELEMENT type, and only when this
    // function really is a generator whose declared return type names a sequence. `unknown` is not a
    // target — imposing it would silence the inference the element walk would otherwise do — so it
    // answers null and the slot is left untouched.
    func YieldValueTargetType(state: YieldStatementState): TypeInfo? {
        if !state.DeclaresGenerator {
            return null
        }

        returnType := ambientValue.CurrentReturnType
        if returnType == null {
            return null
        }

        elementType := GetGeneratorYieldElementType(returnType)
        if elementType == null || BuiltInTypes.IsUnknown(elementType) {
            return null
        }

        return elementType
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
    func BeginForeach(statement: ForeachStatement, assignability: AnalyzerAssignability): LoopStatementState {
        return new LoopStatementState(0, statement.VariableName, statement.Collection, null, null, null, statement.Body, null, statement.Line, statement.Column, false, null, statement.VariableType, assignability)
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

        // THE WRITTEN ANNOTATION REPLACES THE INFERRED ELEMENT TYPE — after it is checked, and
        // whether or not it passes. `for m: Match in matches` declares `m` as a `Match` for every
        // reader downstream: the scope, the semantic model the IDE hovers, the binding map, and the
        // body's own type checking. Taking the declared type even when the conversion was refused is
        // what keeps ONE diagnostic about one mistake — the body then type-checks against the type
        // the author wrote instead of cascading against the one they did not.
        ApplyForeachVariableAnnotation(state)

        state.Phase = 2
        request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
        request.Line = state.Line
        request.Column = state.Column
        return request
    }

    // THE ANNOTATION, RESOLVED AND CHECKED — NL330.
    //
    // The report is SILENT for a conversion `ForeachElementConversionFacts` cannot measure, which is
    // every case where a type is `unknown` or is held only by name; those are already-reported or
    // unknowable, and a sentence about them would name types the author cannot act on. The span is
    // the ANNOTATION's, not the loop keyword's, because the annotation is the thing that is wrong.
    func ApplyForeachVariableAnnotation(state: LoopStatementState) {
        typeReference := state.VariableType
        if typeReference == null {
            return
        }

        declaredType := typeResolverValue.ResolveDeclaredType(typeReference)
        elementType := state.ElementType
        state.ElementType = declaredType

        assignability := state.Assignability
        if assignability == null || ForeachElementConversionFacts.IsConvertible(elementType, declaredType, assignability) {
            return
        }

        span := TypeReferenceFacts.GetStartSpan(typeReference)
        variableName := state.VariableName ?? ""
        elementText := TypeText(elementType)
        declaredText := TypeText(declaredType)
        reportLine := span.StartLine
        reportColumn := span.StartColumn
        reportLength := span.Length
        sourceSnippet := diagnosticsValue.SourceSnippet(reportLine)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet == null || currentFilePath == null {
            diagnosticsValue.Report(ErrorCode.ForeachElementConversion, "A '" + elementText + "' cannot be read as a '" + declaredText + "'", reportLine, reportColumn, "Annotate '" + variableName + "' with '" + elementText + "' or a type it converts to, or drop the annotation.", reportLength)
            return
        }

        diagnosticsValue.ReportBuilt(ErrorMessageBuilder.ForeachElementConversion(currentFilePath ?? "", reportLine, reportColumn, sourceSnippet ?? "", reportLength, variableName, elementText, declaredText))
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
        JoinLoopBackEdge(state.Body, null)
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

    // THE JOIN AT A LOOP'S HEAD, AND THE ONLY PLACE FOUR LOOP FORMS NEED IT.
    //
    // A loop's entry state is the join of the code before it and of its OWN back edge, and the back
    // edge carries every write the body made. The analyzer walks that body once, forward, so a read
    // written above a write would otherwise be judged against the state the FIRST turn had — which
    // is exactly how `while more { use(doc.Error); doc.Error = maybeNull }` passed while being wrong
    // on every turn but the first.
    //
    // The join is performed BEFORE the condition is analysed, so a condition that re-proves the fact
    // — `while doc.Error != null { … }` — installs its narrowing on top of the joined state and the
    // body reads it. That ordering is the whole reason this is a separate step rather than a line
    // inside the body phase.
    //
    // A `for`'s UPDATE CLAUSE is part of the back edge and its initializer is not: the initializer
    // runs once, ahead of the first test, and its facts survive.
    func JoinLoopBackEdge(body: Statement?, iterator: Expression?) {
        writtenPaths := new List<string>()
        AnalyzerLoopCarriedNullFacts.CollectWrittenPaths(body, iterator, writtenPaths)
        for writtenPath in writtenPaths {
            scopesValue.InvalidateNullFactsForAssignment(writtenPath)
        }
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

        JoinLoopBackEdge(state.Body, null)
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
            split := narrowing.ExtractFlowNarrowings(condition)
            state.BodyNarrowings = split.Then
            state.ElseNarrowings = split.Else
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
    // or not the condition proved anything. And the code BELOW the loop takes what the condition
    // proved when it was FALSE: a loop is left through the bottom only when its condition failed, so
    // `while x == null { x = Make() }` leaves `x` not-null for everything after it.
    func AdvanceWhileClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 99
        ExitLoopFrame(state)
        ApplyLoopExitNarrowings(state)
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

    // PHASE 22 — the condition, when there is one. The back edge is joined FIRST and it is joined
    // here rather than at phase 20, because the initializer runs exactly ONCE, before the loop: a
    // fact it establishes is true at the first condition test whatever the body later writes.
    func AdvanceForCondition(state: LoopStatementState): LoopStatementRequest? {
        JoinLoopBackEdge(state.Body, state.Iterator)
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
            split := narrowing.ExtractFlowNarrowings(condition)
            state.BodyNarrowings = split.Then
            state.ElseNarrowings = split.Else
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

    // PHASE 29 — done, and the code below the loop takes what the condition proved when it was FALSE,
    // for the same reason a `while` exit does. It is installed HERE rather than at phase 28 because
    // the outer scope — the one that holds a variable the initializer declared — closes at phase 28,
    // and a fact about the surviving flow belongs to the scope that survives.
    func AdvanceForOuterClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 99
        ApplyLoopExitNarrowings(state)
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
    // SECOND, IT HAS TWO BRANCHES AND EACH GETS ITS OWN SCOPE AND ITS OWN FACTS.
    // `ExtractFlowNarrowings` yields both lists at once — what the condition proves when TRUE and what
    // it proves when FALSE — and each branch runs inside a scope THIS WALK opens, at the branch's own
    // position. A BLOCK branch then runs its statements directly in that scope (kind 8) rather than
    // pushing a second one at the same brace, which is what makes its EXIT STATE readable: the facts a
    // branch ends with are the entries of a scope, and the join below needs to read them after the
    // branch is over.
    //
    // THIRD, AND ONLY HERE IN THE WHOLE FAMILY, WHAT SURVIVES THE STATEMENT IS DECIDED BY A JOIN.
    // `if x == null { return }` is a GUARD CLAUSE: one of the two paths is deleted, so the surviving
    // flow INHERITS the other branch outright — its exit state, or, when this walk did not own its
    // scope, the facts the condition proved for it. When BOTH branches leave there is no surviving
    // flow to inform, and when NEITHER does both paths are live and the answer is their MEET:
    // `join(exit(S), exit(T))`, or `join(exit(S), falseFacts(c))` when there is no else branch,
    // because the implicit else path is exactly the path on which the condition was false. That is
    // `NullableWalker.VisitIfStatement`'s rule, and it is what lets the TryGetValue-or-create idiom
    // read its variable on the line below without a squiggle.
    //
    // THE TERMINATION QUESTION IS ASKED LAST, AFTER BOTH BRANCHES HAVE BEEN WALKED, because that is
    // where `Analyzer.cs` asked it. It is a PURE question about the AST — `AnalyzerStatementTermination`
    // reads no analysis state — so the position is preserved for readability rather than for
    // behaviour, and it is a direct call rather than a step because nothing about it needs the driver.
    //
    // AN `else if` IS NOT A SHAPE THIS WALK KNOWS. The parser puts an `IfStatement` in the else slot,
    // so the else branch step hands it to the statement dispatch and this walk is entered again for
    // it, one level down, with its own condition, its own two narrowing lists and its own join. A
    // chain of any length therefore needs nothing here at all — and it still runs inside the scope
    // this walk opened for the else branch, so what the NESTED join installs is the else branch's
    // exit state, joined here rather than escaping the outer statement as an unconditional fact.
    func AdvanceIf(state: LoopStatementState): LoopStatementRequest? {
        phase := state.Phase
        if phase == 30 {
            return AdvanceIfCondition(state)
        }

        if phase == 31 {
            return AdvanceIfGate(state)
        }

        if phase == 38 {
            return AdvanceIfThenNarrowings(state)
        }

        if phase == 32 {
            return AdvanceIfThenBranchScope(state)
        }

        if phase == 39 {
            return AdvanceIfThenBody(state)
        }

        if phase == 33 {
            return AdvanceIfThenClose(state)
        }

        if phase == 40 {
            return AdvanceIfThenNarrowingClose(state)
        }

        if phase == 34 {
            return AdvanceIfElse(state)
        }

        if phase == 41 {
            return AdvanceIfElseNarrowings(state)
        }

        if phase == 35 {
            return AdvanceIfElseBranchScope(state)
        }

        if phase == 42 {
            return AdvanceIfElseBody(state)
        }

        if phase == 36 {
            return AdvanceIfElseClose(state)
        }

        if phase == 43 {
            return AdvanceIfElseNarrowingClose(state)
        }

        if phase == 37 {
            return AdvanceIfJoin(state)
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
    // Then the then-branch's scope opens.
    //
    // A BRANCH NOW HAS TWO SCOPES WHEN THE CONDITION PROVED SOMETHING AND ONE WHEN IT DID NOT, and
    // that is the SAME count, at the same positions, that the walk has always produced — what changed
    // is only WHO opens the inner one. The NARROWING scope is still opened here and only for a branch
    // whose own list is non-empty; the branch's own scope is opened by this walk at phase 32 rather
    // than by the block inside it, and the block then runs its statements IN it (kind 8). Keeping the
    // two apart is not tidiness: a narrowing writes the narrowed TYPE into its scope's symbol table,
    // so a branch that DECLARES a name the condition narrowed must still be a SHADOW of that binding
    // and not a redeclaration in the same scope. What the split buys is the branch's EXIT STATE: the
    // facts it ends with are the entries of scopes this walk reads before it closes them, which is the
    // whole input to the join at phase 37.
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

        state.Phase = 32
        if NarrowingCount(state) == 0 {
            return null
        }

        state.ThenNarrowingScopeOpened = true
        state.Phase = 38
        request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
        request.Line = state.Body.Line
        request.Column = state.Body.Column
        return request
    }

    // PHASE 38 — the true-branch facts are installed in the narrowing scope phase 31 opened.
    func AdvanceIfThenNarrowings(state: LoopStatementState): LoopStatementRequest? {
        ApplyBodyNarrowings(state)
        state.Phase = 32
        return null
    }

    // PHASE 32 — THE BRANCH'S OWN SCOPE, opened by this walk rather than by the block inside it, and
    // at the block's own position so nothing about where it starts changes. It is what the branch's
    // statements run in (phase 39) and what its EXIT STATE is read from (phase 33).
    func AdvanceIfThenBranchScope(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 39
        request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
        request.Line = state.Body.Line
        request.Column = state.Body.Column
        return request
    }

    // PHASE 39 — the then-branch runs, inside the scope phase 32 opened and inside whatever facts
    // phase 38 installed above it.
    func AdvanceIfThenBody(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 33
        return NewBranchRequest(state.Body)
    }

    // PHASE 33 — THE THEN-BRANCH'S EXIT STATE IS READ, AND ONLY THEN DOES ITS SCOPE CLOSE. The order
    // is the whole point: the facts are the scope's, and after the pop the stack no longer walks
    // through it.
    func AdvanceIfThenClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 40
        state.ThenExitFacts = AnalyzerConditionalJoin.ExitFacts(scopesValue, scopesValue.Peek())
        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 40 — the narrowing scope closes, and what it still held is read first and laid UNDER the
    // branch's own facts: a path the branch assigned has already overwritten what the condition
    // proved, and a path it did not keeps the proof.
    func AdvanceIfThenNarrowingClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 34
        if !state.ThenNarrowingScopeOpened {
            return null
        }

        state.ThenExitFacts = AnalyzerConditionalJoin.OverlayFacts(AnalyzerConditionalJoin.ExitFacts(scopesValue, scopesValue.Peek()), state.ThenExitFacts)
        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 34 — the else branch, which is the family's only optional body. No else branch skips
    // straight to the join; an else branch opens its own scope at ITS OWN position rather than at the
    // then-branch's.
    func AdvanceIfElse(state: LoopStatementState): LoopStatementRequest? {
        elseBody := state.ElseBody
        if elseBody == null {
            state.Phase = 37
            return null
        }

        state.Phase = 35
        if ElseNarrowingCount(state) == 0 {
            return null
        }

        state.ElseNarrowingScopeOpened = true
        state.Phase = 41
        request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
        request.Line = elseBody.Line
        request.Column = elseBody.Column
        return request
    }

    // PHASE 41 — the false-branch facts are installed in the narrowing scope phase 34 opened.
    func AdvanceIfElseNarrowings(state: LoopStatementState): LoopStatementRequest? {
        ApplyElseNarrowings(state)
        state.Phase = 35
        return null
    }

    // PHASE 35 — the else branch's own scope, at ITS OWN position rather than at the then-branch's.
    func AdvanceIfElseBranchScope(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 42
        elseBody := state.ElseBody
        if elseBody == null {
            return null
        }

        request := new LoopStatementRequest(2, BuiltInTypes.Unknown)
        request.Line = elseBody.Line
        request.Column = elseBody.Column
        return request
    }

    // PHASE 42 — the else branch runs.
    func AdvanceIfElseBody(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 36
        elseBody := state.ElseBody
        if elseBody == null {
            return null
        }

        return NewBranchRequest(elseBody)
    }

    // PHASE 36 — the else branch's exit state is read, and only then does its scope close.
    func AdvanceIfElseClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 43
        elseBody := state.ElseBody
        if elseBody == null {
            return null
        }

        state.ElseExitFacts = AnalyzerConditionalJoin.ExitFacts(scopesValue, scopesValue.Peek())
        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 43 — the else branch's narrowing scope closes, laid under its own facts.
    func AdvanceIfElseNarrowingClose(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 37
        if !state.ElseNarrowingScopeOpened {
            return null
        }

        state.ElseExitFacts = AnalyzerConditionalJoin.OverlayFacts(AnalyzerConditionalJoin.ExitFacts(scopesValue, scopesValue.Peek()), state.ElseExitFacts)
        return new LoopStatementRequest(6, BuiltInTypes.Unknown)
    }

    // PHASE 37 — WHAT THE CODE AFTER THE `if` KNOWS. Both branches have already been walked and both
    // scopes are closed; what is decided here is the state the next statement starts from.
    //
    // A BRANCH THAT ALWAYS LEAVES IS NOT A JOIN. `if x == null { return }` deletes one of the two
    // paths, so the surviving flow INHERITS the other one outright — its exit state when this walk
    // owned its scope, and otherwise the facts the condition proved for it, which is what this rule
    // has always installed. The termination questions are asked in the then/else order `Analyzer.cs`
    // asked them, and the else question is not asked at all when there is no else branch.
    //
    // THE QUESTION IS `AlwaysLeaves`, NOT `AlwaysReturns`, and the difference is the whole rule. What
    // the surviving flow knows depends on whether the BRANCH is gone, not on whether the FUNCTION is
    // over: `if x == null { break }` and `if x == null { continue }` remove the branch exactly as
    // `return` and `throw` do, and the code after them is reached only when the condition was false.
    // The missing-return rule cannot use this answer and does not ask for it.
    //
    // WHEN NEITHER BRANCH LEAVES, BOTH PATHS ARE LIVE AND THE ANSWER IS THEIR MEET —
    // `join(exit(S), exit(T))` for a two-branch `if`, and `join(exit(S), falseFacts(c))` when there
    // is no else branch, because the implicit else path is exactly the path on which the condition
    // was false. That is the rule Roslyn's `NullableWalker.VisitIfStatement` states and the one N#
    // was missing.
    func AdvanceIfJoin(state: LoopStatementState): LoopStatementRequest? {
        state.Phase = 99
        thenAlwaysLeaves := AnalyzerStatementTermination.AlwaysLeaves(state.Body, terminatingCallsValue)
        elseBody := state.ElseBody
        elseAlwaysLeaves := elseBody != null && AnalyzerStatementTermination.AlwaysLeaves(elseBody, terminatingCallsValue)

        if thenAlwaysLeaves && !elseAlwaysLeaves {
            InstallInheritedFacts(state, state.ElseExitFacts, state.ElseNarrowings, ElseNarrowingCount(state))
            return null
        }

        if elseAlwaysLeaves {
            InstallInheritedFacts(state, state.ThenExitFacts, state.BodyNarrowings, NarrowingCount(state))
            return null
        }

        InstallJoinedFacts(state)
        return null
    }

    // THE SURVIVING FLOW INHERITS A BRANCH THAT IS THE ONLY PATH LEFT. Its exit state when this walk
    // observed one, and otherwise the facts the condition proved for it — which is the case when
    // there is no else branch at all.
    func InstallInheritedFacts(state: LoopStatementState, exitFacts: Dictionary<string, NullState>?, narrowings: List<FlowNarrowing>?, narrowingCount: int) {
        narrowing := state.Narrowing
        if narrowing == null {
            return
        }

        if exitFacts != null {
            inherited := AnalyzerConditionalJoin.InheritedFacts(exitFacts)
            if inherited.Count > 0 {
                narrowing.ApplyNarrowingsToScope(inherited)
            }

            return
        }

        if narrowings != null && narrowingCount > 0 {
            narrowing.ApplyNarrowingsToScope(narrowings)
        }
    }

    // THE MEET OF TWO LIVE PATHS. The then-branch's exit state joins either the else-branch's exit
    // state or — with no else branch — what the condition proved when it was FALSE, which is the
    // whole of what the implicit else path knows.
    func InstallJoinedFacts(state: LoopStatementState) {
        narrowing := state.Narrowing
        thenExit := state.ThenExitFacts
        if narrowing == null || thenExit == null {
            return
        }

        elseFacts := AnalyzerConditionalJoin.NarrowingFacts(state.ElseNarrowings)
        elseExit := state.ElseExitFacts
        if elseExit != null {
            elseFacts = elseExit
        }

        joined := AnalyzerConditionalJoin.JoinFacts(scopesValue, thenExit, elseFacts)
        if joined.Count > 0 {
            narrowing.ApplyNarrowingsToScope(joined)
        }
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

    // WHAT A LOOP PROVES ON ITS WAY OUT. A `while` or `for` that fell out of the bottom tested its
    // condition one last time and it was FALSE, so the condition's false facts hold below the loop
    // exactly as an `if`'s do below a guard clause. A `break` is the one thing that takes it away: it
    // leaves with the condition untested, so a loop that contains one proves nothing on its way out.
    func ApplyLoopExitNarrowings(state: LoopStatementState) {
        narrowings := state.ElseNarrowings
        narrowing := state.Narrowing
        if narrowings == null || narrowing == null || narrowings.Count == 0 {
            return
        }

        if AnalyzerConditionalJoin.ContainsLoopBreak(state.Body) {
            return
        }

        narrowing.ApplyNarrowingsToScope(narrowings)
    }

    // THE BODY STEP, which is the same request for every walk: a loop body, a `for` initializer, or
    // an `if`'s then-branch.
    func NewBodyRequest(state: LoopStatementState): LoopStatementRequest {
        request := new LoopStatementRequest(5, BuiltInTypes.Unknown)
        request.Body = state.Body
        return request
    }

    // AN `if` BRANCH'S STEP. A BLOCK branch is handed out as its STATEMENT LIST (kind 8), so the
    // block runs inside the scope this walk opened instead of pushing a second one at the same brace,
    // and the facts it ends with stay where the join at phase 37 can read them. An `else if` is a
    // statement that scopes itself and takes the ordinary one-statement step — inside this walk's
    // scope all the same, so what its own join installs into the surviving flow is the else branch's
    // exit state and is joined rather than escaping to the level above.
    static func NewBranchRequest(branch: Statement): LoopStatementRequest {
        block := branch as BlockStatement
        if block != null {
            request := new LoopStatementRequest(8, BuiltInTypes.Unknown)
            request.Statements = block.Statements
            request.Line = block.Line
            request.Column = block.Column
            return request
        }

        request := new LoopStatementRequest(5, BuiltInTypes.Unknown)
        request.Body = branch
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

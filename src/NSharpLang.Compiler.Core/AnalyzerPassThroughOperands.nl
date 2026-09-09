namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// THE STEPS AN OPERATOR TAKES ON ITS OPERANDS, AND NOTHING ELSE.
//
// EVERY ONE OF THESE EIGHT FORMS EVALUATES SOMETHING. That is what separates this family from the
// literals and the compile-time constants: those two answered from the node, and their walks could
// be empty. Here the operand IS the question, so every form suspends at least once — seven of them
// exactly once, and a tuple once per element.
//
// The kinds:
//   1  analyse an EXPRESSION — the operator's operand. It ANSWERS a type, and that answer is what
//      the phase after the step reasons about: the row-escape report's second argument for all
//      eight, and for five of them the walk's own answer as well. There is no kind 2, and in
//      particular a tuple element is NOT a second kind: the driver performs exactly the same
//      operation for it. What differs is that the owner brackets that step with an expected type,
//      which is the owner's business and invisible to the driver.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class PassThroughOperandRequest {
    Kind: int
    Node: Expression?
    Line: int
    Column: int

    constructor(kind: int, node: Expression?, line: int, column: int) {
        Kind = kind
        Node = node
        Line = line
        Column = column
    }
}

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` names which operator this is — 0 `throw`, 1 `is`, 2 `spread`, 3 `alloc`, 4 `must`,
// 5 `stackalloc`, 6 `tuple`, 7 `await`, and -1 for a node that is none of them.
//
// `ResultType` IS THE ANSWER THE DISPATCH GETS BACK, AND UNLIKE THE TWO FAMILIES BEFORE IT, IT IS
// NOT DECIDED AT `Begin`. A literal and a compile-time constant both settled their answer before
// their first step and no step could move it. Here `spread`, `alloc`, `must`, `tuple` and `await`
// all DERIVE their answer from what the operand turned out to be, so `ResultType` starts `unknown`
// and is decided in the phase that runs AFTER the step. `throw` (`never`), `is` (`bool`) and
// `stackalloc` (`Span<T>`) are constant-answered, but they are decided in the same place as the
// others so that one phase owns "what this operator means" for all eight.
//
// `OperandType` is the outstanding step's answer, folded in by `Supply`. For seven forms it is
// consumed once; for a tuple it is consumed and replaced once per element.
//
// `ElementIndex`, `SavedExpectedType` and `Elements` exist only for the tuple: the cursor, the
// target-typing slot's value from BEFORE this element was entered, and the elements decided so far.
//
// `Reachability` is CARRIED rather than held by the owner, because `Analyzer.cs` REBUILDS
// `_patternReachability` whenever the metadata load context creates the well-known types and again
// on dispose. An owner that held it would hold a stale one. It is read at the instant the dispatch
// reached the node and carried across the single step `is` takes — both rebuild sites are
// metadata-context setup and teardown, neither of which an expression walk can reach.
class PassThroughOperandState {
    formValue: int
    nodeValue: Expression?
    reachabilityValue: AnalyzerPatternReachability

    Form: int => formValue
    Node: Expression? => nodeValue
    Reachability: AnalyzerPatternReachability => reachabilityValue

    Phase: int
    Pending: int
    ElementIndex: int
    SavedExpectedType: TypeInfo?
    OperandType: TypeInfo
    ResultType: TypeInfo
    Elements: List<TupleTypeElementInfo>

    constructor(form: int, node: Expression?, reachability: AnalyzerPatternReachability) {
        formValue = form
        nodeValue = node
        reachabilityValue = reachability
        Phase = 0
        Pending = 0
        ElementIndex = 0
        SavedExpectedType = null
        OperandType = BuiltInTypes.Unknown
        ResultType = BuiltInTypes.Unknown
        Elements = new List<TupleTypeElementInfo>()
    }
}

// WHAT AN OPERATOR THAT HANDS ITS OPERAND THROUGH MEANS.
//
// EIGHT OPERATORS, ONE QUESTION. `throw`, `is`, `spread`, `alloc`, `must`, `stackalloc`, a tuple and
// `await` are the expression walk's arms that do nothing but walk what they are given and then say
// what that makes them. They are one family rather than eight arms because they share the shape that
// decides the cost: each takes exactly the steps its operand count implies, consumes the answer, and
// has no second re-entry into anything.
//
// IT OWNS WHAT EACH OF THE EIGHT IS:
//   * that `throw` is `never` — the type of an expression that does not produce a value — and that
//     BOTH of its SoA reports run and neither stops the other, so a row view that is thrown is told
//     both things. That is deliberate and it is not what `nameof` does;
//   * that `is` is `bool` on every path including both refusals, that its written type reference is
//     resolved AFTER its operand is walked and BEFORE either refusal is considered — the resolution
//     reports, so its position is observable — and that the reachability of the test itself is a
//     question for the pattern owner, asked only when neither refusal fired;
//   * that `spread` is its operand's type unchanged: the collection shape is somebody else's rule,
//     and this walk deliberately does not pre-judge it;
//   * that `alloc` is its operand's type unchanged, and that a row view inside one is refused with
//     the HIDDEN-ALLOCATION report rather than the row-escape report — a different rule with a
//     different message, because the objection is the allocation and not the escape;
//   * that `must` unwraps exactly one layer of nullability, passes `unknown` through untouched, and
//     otherwise reports a redundant unwrap AND STILL ANSWERS THE OPERAND TYPE — the diagnostic does
//     not poison the expression, because the programmer's intent is unambiguous;
//   * that a `stackalloc` is a `Span<T>` of its written element type whatever its length turned out
//     to be, that the length must implicitly widen to `int` (so `long` is refused where `byte` is
//     accepted) and must not be a negative constant, and that a SoA diagnostic on the length
//     REPLACES both of those — one mistake, one report;
//   * that a tuple is the tuple of its elements' types in source order, and that each element is
//     walked under the expected type the surrounding annotation implies FOR THAT ELEMENT, matched by
//     NAME first and by position second;
//   * that `await` is the awaited value's result type — `Task<T>`'s `T`, a unit task's `void`, or a
//     reflected `GetAwaiter().GetResult()`'s return — and `unknown` with a diagnostic when the value
//     is not awaitable at all, except that a shape which could still turn out to be awaitable is
//     left alone rather than accused.
//
// IT IS AN OBJECT RATHER THAN A STATIC because eight of its facts are ambient: the diagnostic sink
// and span reader its four own reports are written to, the SoA escape reporter, the type resolver,
// the target-typing slot a tuple decomposes, the declared-alias resolver that slot and the
// stackalloc length are read through, the shape normaliser `await` asks first, and the constant
// facts `stackalloc` asks about its length. All eight are constructed exactly once by `Analyzer.cs`
// and none is rebuilt with the metadata load context, so holding them is safe. THE PATTERN
// REACHABILITY CHECKER IS NOT HELD: `Analyzer.cs` rebuilds it with the metadata load context, so it
// arrives at `Begin` as an argument, read at the instant the dispatch reached the node.
class AnalyzerPassThroughOperands {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    soaEscapeValue: AnalyzerSoaEscape
    typeResolverValue: AnalyzerTypeResolver
    ambientValue: AnalyzerAmbientContext
    declarationContextValue: AnalyzerDeclarationContext
    loopSequenceValue: AnalyzerLoopSequence
    constantFactsValue: AnalyzerConstantExpressionFacts

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, soaEscape: AnalyzerSoaEscape, typeResolver: AnalyzerTypeResolver, ambient: AnalyzerAmbientContext, declarationContext: AnalyzerDeclarationContext, loopSequence: AnalyzerLoopSequence, constantFacts: AnalyzerConstantExpressionFacts) {
        diagnosticsValue = diagnostics
        spansValue = spans
        soaEscapeValue = soaEscape
        typeResolverValue = typeResolver
        ambientValue = ambient
        declarationContextValue = declarationContext
        loopSequenceValue = loopSequence
        constantFactsValue = constantFacts
    }

    // THE ENTRY, AND IT DECIDES NOTHING. Unlike the compile-time constants, no form in this family
    // can answer or report before its operand has been walked — there is nothing to say about an
    // operator until you know what it was given. So `Begin` names the form and stops, and every
    // diagnostic this family owns lands in the phase AFTER a step.
    //
    // A node that is not one of the eight answers `unknown` and takes no steps — the dispatch never
    // hands one over, and the walk says so rather than guessing.
    func Begin(expression: Expression, patternReachability: AnalyzerPatternReachability): PassThroughOperandState {
        return new PassThroughOperandState(FormOf(expression), expression, patternReachability)
    }

    // WHICH OF THE EIGHT THIS NODE IS. It is derived from the NODE rather than carried by anything
    // else, which is the rule slice 50 paid for: an instrument that reads the form off the state
    // measures it one report too late.
    static func FormOf(expression: Expression): int {
        throwNode := expression as ThrowExpression
        if throwNode != null {
            return 0
        }

        isNode := expression as IsExpression
        if isNode != null {
            return 1
        }

        spreadNode := expression as SpreadExpression
        if spreadNode != null {
            return 2
        }

        allocNode := expression as AllocExpression
        if allocNode != null {
            return 3
        }

        mustNode := expression as MustExpression
        if mustNode != null {
            return 4
        }

        stackAllocNode := expression as StackAllocExpression
        if stackAllocNode != null {
            return 5
        }

        tupleNode := expression as TupleExpression
        if tupleNode != null {
            return 6
        }

        awaitNode := expression as AwaitExpression
        if awaitNode != null {
            return 7
        }

        return -1
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    func NextStep(state: PassThroughOperandState): PassThroughOperandRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP: the operand's type. A walk that asked for nothing folds in
    // nothing, and a null answer is `unknown` rather than a missing one — the analyzer's expression
    // walk never answers null, and a walk that saw one would otherwise carry it into a report.
    func Supply(state: PassThroughOperandState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending == 0 {
            return
        }

        if answer != null {
            state.OperandType = answer
        } else {
            state.OperandType = BuiltInTypes.Unknown
        }
    }

    // WHAT THE WALK ANSWERS, which is what the dispatch hands to its caller. For five of the eight it
    // is a function of the step's answer, which is why it is read here and not decided at `Begin`.
    func Result(state: PassThroughOperandState): TypeInfo {
        return state.ResultType
    }

    func Advance(state: PassThroughOperandState): PassThroughOperandRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceEntry(state)
        }

        if phase == 1 {
            return AdvanceOperandFinish(state)
        }

        if phase == 2 {
            return AdvanceTupleElement(state)
        }

        if phase == 3 {
            return AdvanceTupleElementFinish(state)
        }

        state.Phase = 99
        return null
    }

    // THE FORK, AND IT IS BETWEEN "ONE OPERAND" AND "AS MANY AS THERE ARE ELEMENTS". Seven forms ask
    // once; a tuple joins the element loop, which asks zero times for `()` and once per element
    // otherwise.
    func AdvanceEntry(state: PassThroughOperandState): PassThroughOperandRequest? {
        if state.Form == 6 {
            state.Phase = 2
            return null
        }

        operand := OperandNode(state.Node)
        if operand == null {
            state.Phase = 99
            return null
        }

        state.Pending = 1
        state.Phase = 1
        return new PassThroughOperandRequest(1, operand, operand.Line, operand.Column)
    }

    // THE ONE SUB-EXPRESSION EACH SINGLE-OPERAND FORM WALKS. `stackalloc`'s is its LENGTH and not its
    // element type: the element type is a written type reference, resolved without walking anything.
    static func OperandNode(node: Expression?): Expression? {
        throwNode := node as ThrowExpression
        if throwNode != null {
            return throwNode.Expression
        }

        isNode := node as IsExpression
        if isNode != null {
            return isNode.Expression
        }

        spreadNode := node as SpreadExpression
        if spreadNode != null {
            return spreadNode.Expression
        }

        allocNode := node as AllocExpression
        if allocNode != null {
            return allocNode.Expression
        }

        mustNode := node as MustExpression
        if mustNode != null {
            return mustNode.Expression
        }

        stackAllocNode := node as StackAllocExpression
        if stackAllocNode != null {
            return stackAllocNode.LengthExpression
        }

        awaitNode := node as AwaitExpression
        if awaitNode != null {
            return awaitNode.Expression
        }

        return null
    }

    // WHAT THE OPERATOR MEANS, ASKED ONCE THE OPERAND IS KNOWN. Every diagnostic this family owns is
    // raised from here or from the tuple's element phase, and every answer is decided here.
    func AdvanceOperandFinish(state: PassThroughOperandState): PassThroughOperandRequest? {
        state.Phase = 99
        node := state.Node

        throwNode := node as ThrowExpression
        if throwNode != null {
            FinishThrow(state, throwNode)
            return null
        }

        isNode := node as IsExpression
        if isNode != null {
            FinishIs(state, isNode)
            return null
        }

        spreadNode := node as SpreadExpression
        if spreadNode != null {
            FinishSpread(state, spreadNode)
            return null
        }

        allocNode := node as AllocExpression
        if allocNode != null {
            FinishAlloc(state, allocNode)
            return null
        }

        mustNode := node as MustExpression
        if mustNode != null {
            FinishMust(state, mustNode)
            return null
        }

        stackAllocNode := node as StackAllocExpression
        if stackAllocNode != null {
            FinishStackAlloc(state, stackAllocNode)
            return null
        }

        awaitNode := node as AwaitExpression
        if awaitNode != null {
            FinishAwait(state, awaitNode)
            return null
        }

        return null
    }

    // A THROW EXPRESSION IS `never`, AND BOTH OF ITS REPORTS RUN. Neither answer is consulted: a
    // thrown row view is told that a row view cannot be thrown AND that a direct column value cannot
    // be, because a `throw` produces no value for either objection to be about — there is no result
    // to poison, so there is no reason to stop at the first.
    func FinishThrow(state: PassThroughOperandState, throwNode: ThrowExpression) {
        soaEscapeValue.ReportSoaRowEscapeIfNeeded(throwNode.Expression, state.OperandType, "thrown")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(throwNode.Expression, "thrown")
        state.ResultType = BuiltInTypes.Never
    }

    // AN `is` TEST IS A `bool` WHATEVER HAPPENS, and its written type reference is resolved BEFORE
    // either refusal is considered. That order is observable: resolving an unknown type reports, so a
    // row-view test against a misspelled type is told BOTH things, in that order.
    //
    // The reachability of the test — whether it can ever succeed, and whether it is already implied —
    // is the pattern owner's question, and it is asked only when the value is a real one.
    func FinishIs(state: PassThroughOperandState, isNode: IsExpression) {
        targetType := typeResolverValue.ResolveType(isNode.Type)
        state.ResultType = BuiltInTypes.Bool
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(isNode.Expression, state.OperandType, "tested with 'is'") {
            return
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(isNode.Expression, "tested with 'is'") {
            return
        }

        state.Reachability.CheckIsExpression(isNode, state.OperandType, targetType)
    }

    // A SPREAD IS ITS OPERAND. Whether that operand is actually spreadable is decided where the
    // spread is USED — in a call's argument list or an array literal — because the answer depends on
    // what it is being spread into, which this walk cannot see.
    func FinishSpread(state: PassThroughOperandState, spreadNode: SpreadExpression) {
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(spreadNode.Expression, state.OperandType, "spread") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(spreadNode.Expression, "spread") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        state.ResultType = state.OperandType
    }

    // AN `alloc` IS ITS OPERAND, AND ITS ROW REFUSAL IS NOT THE ROW ESCAPE. `alloc` marks a
    // deliberate allocation, so a row view inside one is objected to on the ground that materialising
    // rows is the allocation the marker is hiding — a different rule with a different message from
    // the escape every other arm here raises, which is why this arm tests the type itself rather than
    // asking the escape reporter.
    func FinishAlloc(state: PassThroughOperandState, allocNode: AllocExpression) {
        rowView := state.OperandType as SoaRowTypeInfo
        if rowView != null {
            ReportSoaRowHiddenAllocation(allocNode.Expression)
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(allocNode.Expression, "used in an alloc expression") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        state.ResultType = state.OperandType
    }

    // WHY MATERIALISING A ROW IS THE OBJECTION. A row view is a table plus an index; producing one as
    // a value means building the object the columnar layout exists to avoid. The suggestion names the
    // spelling that does not: reach the column in the same expression.
    func ReportSoaRowHiddenAllocation(expression: Expression) {
        span := spansValue.GetExpressionDiagnosticSpan(expression)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "this operation would allocate row objects; use column access instead", span.Line, span.Column, "Read or write a column with table[index].column in the same expression.", span.Length)
    }

    // `must` UNWRAPS EXACTLY ONE LAYER, AND A REDUNDANT UNWRAP STILL ANSWERS. An `unknown` operand is
    // passed through in silence — the programmer has already been told about whatever made it unknown
    // — and a non-nullable operand is told that the unwrap says nothing, but is STILL given the
    // operand's own type, because refusing to answer would cascade one redundant keyword into every
    // expression built on it.
    func FinishMust(state: PassThroughOperandState, mustNode: MustExpression) {
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(mustNode.Expression, state.OperandType, "unwrapped with 'must'") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(mustNode.Expression, "unwrapped with 'must'") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        nullable := state.OperandType as NullableTypeInfo
        if nullable != null {
            state.ResultType = nullable.InnerType
            return
        }

        if BuiltInTypes.IsUnknown(state.OperandType) {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        diagnosticsValue.Report(ErrorCode.NullabilityWarning, "This 'must' unwrap is redundant — the expression is already known to be '" + TypeText(state.OperandType) + "'", mustNode.Line, mustNode.Column, "Remove the 'must' keyword, or keep the original nullable value until the point where you need to unwrap it.", 4)
        state.ResultType = state.OperandType
    }

    // A `stackalloc` IS A `Span<T>` OF ITS WRITTEN ELEMENT TYPE, WHATEVER ITS LENGTH TURNED OUT TO
    // BE. The element type is resolved LAST, after every diagnostic, so a broken length never
    // suppresses the type reference's own report and never changes what the expression is.
    //
    // THE THREE LENGTH RULES ARE EXCLUSIVE, IN THIS ORDER. A SoA diagnostic REPLACES both of the
    // others, because "this is a row view" is more useful than "this is not an int"; and the two SoA
    // probes are joined so that the second is not even asked once the first has fired. Then the width
    // rule: an element count must implicitly widen to `int`, so `short`, `sbyte`, `byte`, `ushort`
    // and `char` are accepted and `long`, `uint`, `ulong` and the floating-point types are not. Only
    // a length that PASSES the width rule is asked whether it is a negative constant, which is why
    // `stackalloc byte[-1L]` is told about its width and not about its sign.
    func FinishStackAlloc(state: PassThroughOperandState, stackAllocNode: StackAllocExpression) {
        lengthNode := stackAllocNode.LengthExpression
        lengthType := state.OperandType
        escaped := soaEscapeValue.ReportSoaRowEscapeIfNeeded(lengthNode, lengthType, "used as a stackalloc length") || soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(lengthNode, "used as a stackalloc length")
        if !escaped {
            if !BuiltInTypes.IsUnknown(lengthType) && !IsImplicitlyIntStackAllocLength(lengthType) {
                diagnosticsValue.Report(ErrorCode.TypeMismatch, "stackalloc length must be an int, but this is a '" + TypeText(lengthType) + "'", lengthNode.Line, lengthNode.Column, "Use an int-typed length, or cast explicitly with '(int)' if the value is known to fit.", 0)
            } else if constantFactsValue.IsConstantNegative(lengthNode) {
                diagnosticsValue.Report(ErrorCode.TypeMismatch, "stackalloc length must not be negative", lengthNode.Line, lengthNode.Column, "Use a length of zero or more.", 0)
            }
        }

        arguments := new List<TypeInfo>()
        arguments.Add(typeResolverValue.ResolveType(stackAllocNode.ElementType))
        spanType: TypeInfo = new GenericTypeInfo("Span", arguments, new ReflectionTypeInfo(typeof(Span<int>).GetGenericTypeDefinition()))
        state.ResultType = spanType
    }

    // WHICH LENGTHS ARE AN ELEMENT COUNT. The rule is implicit widening to `int` and nothing wider:
    // the analyzer will not silently accept a `long` count for a stack buffer, because the value that
    // does not fit is the one that overflows the frame.
    func IsImplicitlyIntStackAllocLength(candidate: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        return BuiltInTypes.Is(resolved, BuiltInTypes.Int) || BuiltInTypes.Is(resolved, BuiltInTypes.Short) || BuiltInTypes.Is(resolved, BuiltInTypes.SByte) || BuiltInTypes.Is(resolved, BuiltInTypes.Byte) || BuiltInTypes.Is(resolved, BuiltInTypes.UShort) || BuiltInTypes.Is(resolved, BuiltInTypes.Char)
    }

    // THE NEXT TUPLE ELEMENT, WALKED UNDER ITS OWN EXPECTED TYPE. This is the one place in the family
    // where the target-typing slot is not merely read but WRITTEN, and it is written per STEP: the
    // surrounding annotation is decomposed for element `i` and pushed for exactly as long as element
    // `i` is being walked. The slot is read HERE — at the top of the element, after the previous
    // element restored it — which is the same instant `Analyzer.cs` read it.
    func AdvanceTupleElement(state: PassThroughOperandState): PassThroughOperandRequest? {
        tupleNode := state.Node as TupleExpression
        if tupleNode == null {
            state.Phase = 99
            return null
        }

        if state.ElementIndex >= tupleNode.Elements.Count {
            decided: TypeInfo = new TupleTypeInfo(state.Elements)
            state.ResultType = decided
            state.Phase = 99
            return null
        }

        element := tupleNode.Elements[state.ElementIndex]
        state.SavedExpectedType = ambientValue.EnterExpectedTypeIfProvided(ExpectedTupleElementType(tupleNode, state.ElementIndex))
        state.Pending = 1
        state.Phase = 3
        return new PassThroughOperandRequest(1, element.Value, element.Value.Line, element.Value.Column)
    }

    // THE ELEMENT'S BRACKET CLOSES BEFORE ANYTHING ELSE HAPPENS. The expected type is restored FIRST,
    // then the two escape reports run, then the element is recorded — the order `Analyzer.cs` used,
    // and the reason it matters is that a report is free to look at the ambient context.
    //
    // Neither report's answer is consulted: an element that is refused is still an element, and the
    // tuple is still the tuple of what its elements turned out to be.
    func AdvanceTupleElementFinish(state: PassThroughOperandState): PassThroughOperandRequest? {
        state.Phase = 2
        tupleNode := state.Node as TupleExpression
        if tupleNode == null {
            state.Phase = 99
            return null
        }

        ambientValue.ExitExpectedType(state.SavedExpectedType)
        state.SavedExpectedType = null
        element := tupleNode.Elements[state.ElementIndex]
        soaEscapeValue.ReportSoaRowEscapeIfNeeded(element.Value, state.OperandType, "stored in a tuple")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(element.Value, "stored in a tuple")
        state.Elements.Add(new TupleTypeElementInfo(element.Name, state.OperandType))
        state.ElementIndex = state.ElementIndex + 1
        return null
    }

    // WHAT THE SURROUNDING ANNOTATION EXPECTS OF ONE ELEMENT. Only a tuple annotation decomposes; a
    // shorter one contributes nothing to the elements past its end. A NAMED element is matched by
    // NAME first, wherever that name appears in the annotation, and falls back to its position when
    // the name is not there — which is what makes `p: (x: int, y: int) = (y: 1, x: 2)` type both
    // elements the way the writer meant.
    //
    // The slot is read ONCE here. `Analyzer.cs` read it twice — the presence test and the
    // decomposition — with nothing between them that could move it.
    func ExpectedTupleElementType(tupleNode: TupleExpression, elementIndex: int): TypeInfo? {
        expected := ambientValue.CurrentExpectedType
        if expected == null {
            return null
        }

        expectedTuple := declarationContextValue.ResolveDeclaredAlias(expected) as TupleTypeInfo
        if expectedTuple == null || elementIndex >= expectedTuple.Elements.Count {
            return null
        }

        element := tupleNode.Elements[elementIndex]
        if element.Name != null {
            index := 0
            while index < expectedTuple.Elements.Count {
                expectedElement := expectedTuple.Elements[index]
                if expectedElement.Name == element.Name {
                    return expectedElement.Type
                }

                index = index + 1
            }
        }

        return expectedTuple.Elements[elementIndex].Type
    }

    // WHAT AWAITING SOMETHING HANDS BACK. Three answers are recognised and a fourth case is
    // deliberately left alone: a class, struct, record or interface that this analyzer cannot see a
    // `GetAwaiter` on may still have one at run time or through a source it has not bound yet, so it
    // is not accused. Everything else — an `int`, a `string`, a function type — is told plainly.
    func FinishAwait(state: PassThroughOperandState, awaitNode: AwaitExpression) {
        state.ResultType = BuiltInTypes.Unknown
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(awaitNode.Expression, state.OperandType, "awaited") {
            return
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(awaitNode.Expression, "awaited") {
            return
        }

        awaited: TypeInfo = BuiltInTypes.Unknown
        if TryAwaitResultType(state.OperandType, out awaited) {
            state.ResultType = awaited
            return
        }

        if ShouldReportAwaitMismatch(state.OperandType) {
            span := spansValue.GetExpressionDiagnosticSpan(awaitNode.Expression)
            diagnosticsValue.Report(ErrorCode.TypeMismatch, "await expression needs an awaitable value, but this expression is '" + TypeText(state.OperandType) + "'", span.Line, span.Column, "Await a Task, ValueTask, or another value with a GetAwaiter() pattern.", span.Length)
        }
    }

    // THE THREE WAYS A VALUE CAN BE AWAITABLE, IN THE ONLY ORDER THAT WORKS. An UNRESOLVED shape and
    // an EXTERNAL type both answer "no" before anything is asked of them — the first because there is
    // nothing to ask, the second because an external type's members are not this analyzer's to
    // enumerate. Then the source-known task shapes, then the unit task shapes, and only then the
    // reflected `GetAwaiter` pattern, which is the expensive one.
    func TryAwaitResultType(awaitableType: TypeInfo, out resultType: TypeInfo): bool {
        resultType = BuiltInTypes.Unknown
        resolved := loopSequenceValue.NormalizeShapeType(awaitableType)
        if BuiltInTypes.IsUnknown(resolved) {
            return false
        }

        external := resolved as ExternalTypeInfo
        if external != null {
            return false
        }

        taskResult: TypeInfo = BuiltInTypes.Unknown
        if AnalyzerFunctionTypeFactory.TryGetTaskLikeResultTypeInfo(resolved, out taskResult) {
            resultType = taskResult
            return true
        }

        if AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(resolved) {
            resultType = BuiltInTypes.Void
            return true
        }

        reflected := resolved as ReflectionTypeInfo
        if reflected != null {
            reflectedResult: TypeInfo = BuiltInTypes.Unknown
            if TryReflectionAwaitResultType(reflected.Type, out reflectedResult) {
                resultType = reflectedResult
                return true
            }
        }

        return false
    }

    // WHEN A NON-AWAITABLE VALUE IS ACCUSED. Only when its shape leaves no room for a `GetAwaiter`
    // this analyzer has not seen: a class, struct, record or interface is left alone, and so is an
    // unresolved shape. The remaining shapes — the built-ins, arrays, functions, tuples, unions —
    // cannot carry the pattern, so awaiting one is always the mistake it looks like.
    func ShouldReportAwaitMismatch(awaitableType: TypeInfo): bool {
        resolved := loopSequenceValue.NormalizeShapeType(awaitableType)
        if BuiltInTypes.IsUnknown(resolved) {
            return false
        }

        classType := resolved as ClassTypeInfo
        if classType != null {
            return false
        }

        structType := resolved as StructTypeInfo
        if structType != null {
            return false
        }

        recordType := resolved as RecordTypeInfo
        if recordType != null {
            return false
        }

        interfaceType := resolved as InterfaceTypeInfo
        if interfaceType != null {
            return false
        }

        return true
    }

    // THE DUCK-TYPED AWAITER PATTERN: a parameterless `GetAwaiter` whose return type carries a
    // parameterless `GetResult`. Visibility is deliberately wide — a non-public member satisfies the
    // pattern here, as it did in `Analyzer.cs` — and a `Nullable<T>` is unwrapped first so that
    // `Task<int>?` finds the awaiter `Task<int>` has.
    //
    // `System.Void` is compared by IDENTITY against the LIVE one rather than by name, which is the
    // comparison `Analyzer.cs` made with `typeof(void)`; a type read through a MetadataLoadContext
    // answers with THAT context's void and is deliberately not recognised, because recognising it
    // would change what an awaited external unit task answers.
    static func TryReflectionAwaitResultType(clrType: Type, out resultType: TypeInfo): bool {
        resultType = BuiltInTypes.Unknown
        runtimeType := clrType
        underlying := Nullable.GetUnderlyingType(clrType)
        if underlying != null {
            runtimeType = underlying
        }

        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        noParameters := new Type[](0)
        getAwaiterMethod := runtimeType.GetMethod("GetAwaiter", flags, null, noParameters, null)
        if getAwaiterMethod == null {
            return false
        }

        awaiterType := getAwaiterMethod.get_ReturnType()
        getResultMethod := awaiterType.GetMethod("GetResult", flags, null, noParameters, null)
        if getResultMethod == null {
            return false
        }

        returnType := getResultMethod.get_ReturnType()
        if returnType == AnalyzerReflectionArgumentBinder.LiveVoidType() {
            resultType = BuiltInTypes.Void
            return true
        }

        resultType = AnalyzerReflectionTypeConversion.ConvertReflectionType(returnType)
        return true
    }

    // A TYPE'S RENDERED TEXT, TAKEN THROUGH `object`. `Analyzer.cs` wrote `$"{type}"`; the columnar
    // backend declines a virtual `ToString` called directly on a `TypeInfo`, so the estate's spelling
    // is to box first. Same helper, same reason, as `AnalyzerAmbientContext.TypeText` and its
    // siblings.
    static func TypeText(typeInfo: TypeInfo): string {
        boxed := typeInfo as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}

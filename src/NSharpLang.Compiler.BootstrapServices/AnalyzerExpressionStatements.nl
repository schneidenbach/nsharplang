namespace NSharpLang.Compiler

import System.Collections
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// THE SEVEN STEPS THE STATEMENT-LEVEL EXPRESSION FAMILY CANNOT TAKE FOR ITSELF.
//
// This walk owns what it MEANS to write an expression where a statement belongs — a bare `f()` or
// `x = 1` as a statement, the update clause of a `for`, an `assert`, and an `assert throws` — which
// of those expressions actually DO anything, which of the family's four diagnostics fires and with
// which span, suggestion and wording, and whether a discarded result was one the callee said must
// be used. What it cannot do is run the analyzer's own EXPRESSION walk, call the two SoA escape
// reporters that belong to a different family, open or close a scope on the analyzer's scope stack,
// re-enter the STATEMENT dispatch for an `assert throws` body, read the recorded type of an
// already-analysed callee out of the semantic model (which the analysis reset REPLACES, so it
// cannot be captured here), or decide whether a type is throwable (a predicate two other families
// still share) — so it ASKS: one request at a time, each naming a kind and carrying every value the
// step needs. Nothing here is a policy the driver may reinterpret — the driver switches on `Kind`,
// performs exactly the one operation with exactly these operands, and hands the answer back.
//
// The kinds:
//   1  analyse an expression WITHOUT touching the analyzer's ambient target-typing slot. No arm in
//      this family ever set it — a discarded expression, an assert condition and an assert message
//      are all analysed inside whatever target typing already surrounds them — so this is
//      `AnalyzerVariableDeclaration`'s kind 6, not its kind 1. ANSWERS a type.
//   2  the SoA row-view escape report. Answers nothing the walk reads; the walk makes the
//      `is SoaRowTypeInfo` test for itself, exactly as `ReportSoaRowEscapeIfNeeded` did.
//   3  the SoA direct-column escape report. ANSWERS a boolean: whether it fired.
//   4  open a block scope on the analyzer's scope stack at `Line` / `Column`.
//   5  analyse a statement LIST — the `assert throws` body — which re-enters the statement dispatch
//      and therefore this walk itself. Every `Begin` hands back a fresh state, so a nested
//      `assert throws` suspends independently of the one that contains it.
//   6  close the scope kind 4 opened.
//   7  ANSWERS whether `CarriedType` is throwable. The predicate stays in `Analyzer.cs` because the
//      catch-clause and throw-operand families still share it; the DECISION to report, the wording,
//      the suggestion and the span are here.
//   8  ANSWERS the type the semantic model recorded for the expression at `Line` / `Column` — the
//      callee of a discarded call — or null when nothing was recorded. The call was already
//      analysed by kind 1, so re-analysing the AST would double-record bindings and references and
//      corrupt find-references; this reads the answer back instead.
public class ExpressionStatementRequest {

    public Kind: int
    public Node: Expression?
    public Statements: List<Statement>?
    public CarriedType: TypeInfo
    public Text: string?
    public Line: int
    public Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        Statements = null
        CarriedType = carriedType
        Text = null
        Line = 0
        Column = 0
    }
}

// THE STATEMENT'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// ONE state serves all three statement shapes, because ONE driver serves them all: exactly one of
// `discardedValue`, `assertValue` and `assertThrowsValue` is set, and which one is set selects the
// phase family.
//
// `Phase` is the walk's program counter. The DISCARD family runs 0..3: 0 captures the error count
// and asks for the expression, 1 folds the answer in and chooses between the placeholder exit, the
// row-escape report and the column-escape report, 2 folds the escape answer and reaches the
// validity decision, and 3 folds the recorded callee type and settles the must-use report. The
// ASSERT family runs 10..13 — condition, condition escapes, message, message escapes. The
// ASSERT-THROWS family runs 20..23 — throwability, report and scope open, body, scope close. 99 is
// done for all three.
//
// `ErrorsBefore` is the discard walk's guard, captured at phase 0 from the diagnostic sink's own
// count. Every later report in that walk is suppressed the instant the count differs, which is what
// keeps a statement from complaining that it "has no effect" on top of the real error inside it.
// The sink OWNS the error list, so the count is its own answer and not something the driver carries.
public class ExpressionStatementState {

    discardedValue: Expression?
    assertValue: AssertStatement?
    assertThrowsValue: AssertThrowsStatement?
    contextValue: DiscardedExpressionContext
    soaUsageValue: string

    Discarded: Expression? => discardedValue
    Assert: AssertStatement? => assertValue
    AssertThrows: AssertThrowsStatement? => assertThrowsValue
    Context: DiscardedExpressionContext => contextValue
    SoaUsage: string => soaUsageValue

    public Phase: int
    public Pending: int

    public ErrorsBefore: int
    public AnsweredType: TypeInfo
    public EscapeFired: bool
    public Throwable: bool
    public ExceptionType: TypeInfo
    public CalleeType: TypeInfo?
    public MustUseCandidate: CallExpression?

    constructor(
        discarded: Expression?,
        assertStatement: AssertStatement?,
        assertThrows: AssertThrowsStatement?,
        context: DiscardedExpressionContext,
        soaUsage: string) {
        discardedValue = discarded
        assertValue = assertStatement
        assertThrowsValue = assertThrows
        contextValue = context
        soaUsageValue = soaUsage

        Phase = 0
        if assertStatement != null {
            Phase = 10
        }

        if assertThrows != null {
            Phase = 20
        }

        Pending = 0
        ErrorsBefore = 0
        AnsweredType = BuiltInTypes.Unknown
        EscapeFired = false
        Throwable = false
        ExceptionType = BuiltInTypes.Unknown
        CalleeType = null
        MustUseCandidate = null
    }
}

// WHAT AN EXPRESSION MEANS WHERE A STATEMENT BELONGS, as a walk that suspends at each step it cannot
// take itself.
//
// This is the analyzer's expression/statement walker territory, and it owns the family that has no
// value to hand anywhere: the bare expression statement, the `for` loop's update clause, `assert`
// and `assert throws`. `Analyzer.cs` kept the family as FOURTEEN members of which ELEVEN had no
// caller outside it — the must-use closure (unwrap, reason, the reflected-attribute test), the
// validity predicate, the two rich invalid-statement reporters and their context selector, and the
// assert-throws type reporter — so they are here rather than left behind as callbacks.
//
// WHY A SEPARATE DRIVER FROM `DriveLocalDeclaration`, WHICH THIS OVERLAPS ON THREE KINDS. Kinds 1,
// 2 and 3 here ARE that driver's kinds 6, 2 and 3 — the same expression walk with the ambient
// target-typing slot left alone, and the same two SoA escape reporters. But kinds 4, 5, 6 and 7 are
// re-entries NO local declaration makes: a `let` never opens a scope, never re-enters the statement
// dispatch and never asks whether a type is throwable. Sharing would mean widening
// `VariableDeclarationState` with a statement list and a scope program counter it can never use, and
// coupling two statement families through one request type. So the overlap is stated rather than
// forced, and this family gets its own request, its own state and its own loop.
//
// WHY A RESUMABLE WALK RATHER THAN A SCHEDULE COMPUTED UP FRONT. The discard walk's step COUNT is
// not knowable before the first step: whether the row-escape report runs is decided by the ANSWERED
// type; whether the column-escape report runs is decided by whether the row report fired AND by
// whether the error count still matches; whether the validity report runs is decided by the column
// report's ANSWER; and whether the semantic-model lookup happens at all is decided by whether the
// expression unwrapped to a call. The assert-throws walk's REPORT is decided by an answer too. So
// no schedule computed before the first step can name the later steps, and the walk suspends and
// RESUMES WITH THE ANSWER, like slice 24's call walk, slice 29's pattern walk and slice 31/32's
// local-declaration walk.
//
// THE FOUR DIAGNOSTICS ARE `Analyzer.cs`'s VERBATIM. NL313 has TWO forms selected by
// `DiscardedExpressionContext` — the expression-statement form and the for-iterator form — each
// with a rich `ErrorMessageBuilder` shape when the file has a snippet and a detail-only fallback
// when it does not. NL315 is the must-use report, whose REASON has four shapes, one per callee kind.
// NL202 is the assert-throws non-throwable report. `assert` itself reports NOTHING of its own: it
// deliberately does not require a boolean condition, because N# supports several comparison shapes
// there, so everything it can raise comes from the two SoA reporters it re-enters.
public class AnalyzerExpressionStatements {

    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    typeResolverValue: AnalyzerTypeResolver

    constructor(
        diagnostics: AnalyzerDiagnosticSink,
        spans: AnalyzerDiagnosticSpans,
        typeResolver: AnalyzerTypeResolver) {
        diagnosticsValue = diagnostics
        spansValue = spans
        typeResolverValue = typeResolver
    }

    // A BARE EXPRESSION USED AS A STATEMENT. The SoA reports call it "discarded" and an invalid one
    // reports the expression-statement form of NL313.
    public func BeginExpressionStatement(expression: Expression): ExpressionStatementState {
        return new ExpressionStatementState(
            expression,
            null,
            null,
            DiscardedExpressionContext.ExpressionStatement,
            "discarded")
    }

    // THE `for` LOOP'S UPDATE CLAUSE. The same walk with two different constants: the SoA reports
    // name the iterator, and an invalid one reports the for-iterator form of NL313.
    public func BeginForIterator(expression: Expression): ExpressionStatementState {
        return new ExpressionStatementState(
            expression,
            null,
            null,
            DiscardedExpressionContext.ForIterator,
            "used as a 'for' iterator")
    }

    public func BeginAssert(assertStatement: AssertStatement): ExpressionStatementState {
        return new ExpressionStatementState(
            null,
            assertStatement,
            null,
            DiscardedExpressionContext.ExpressionStatement,
            "asserted")
    }

    public func BeginAssertThrows(assertThrows: AssertThrowsStatement): ExpressionStatementState {
        return new ExpressionStatementState(
            null,
            null,
            assertThrows,
            DiscardedExpressionContext.ExpressionStatement,
            "asserted")
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this statement is finished. Every phase
    // either decides something and advances, or emits exactly one request; the walk never advances
    // past a point whose answer it has not been given.
    public func NextStep(state: ExpressionStatementState): ExpressionStatementRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Kind 1 answers a type — the discard walk's escape choice
    // and the assert walk's escape choice both read it. Kind 3 answers whether the column report
    // fired, which is what ends the discard walk. Kind 7 answers throwability. Kind 8 answers the
    // recorded callee type, which selects the must-use reason. Kinds 2, 4, 5 and 6 answer nothing.
    public func Supply(state: ExpressionStatementState, answer: TypeInfo?, flag: bool) {
        pending := state.Pending
        state.Pending = 0

        if pending == 1 {
            if answer != null {
                state.AnsweredType = answer
            } else {
                state.AnsweredType = BuiltInTypes.Unknown
            }

            return
        }

        if pending == 3 {
            state.EscapeFired = flag
            return
        }

        if pending == 7 {
            state.Throwable = flag
            return
        }

        if pending == 8 {
            state.CalleeType = answer
        }
    }

    func Advance(state: ExpressionStatementState): ExpressionStatementRequest? {
        assertThrows := state.AssertThrows
        if assertThrows != null {
            return AdvanceAssertThrows(state, assertThrows)
        }

        assertStatement := state.Assert
        if assertStatement != null {
            return AdvanceAssert(state, assertStatement)
        }

        discarded := state.Discarded
        if discarded != null {
            return AdvanceDiscarded(state, discarded)
        }

        state.Phase = 99
        return null
    }

    // ── THE DISCARD WALK ───────────────────────────────────────────────────────────────────────

    func AdvanceDiscarded(
        state: ExpressionStatementState,
        expression: Expression): ExpressionStatementRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceDiscardedExpression(state, expression)
        }

        if phase == 1 {
            return AdvanceDiscardedEscapes(state, expression)
        }

        if phase == 2 {
            return AdvanceDiscardedValidity(state, expression)
        }

        if phase == 3 {
            return AdvanceDiscardedMustUse(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 0 — the guard and the one step everything else depends on. The error count is captured
    // BEFORE the expression walk runs, so that anything the walk itself reports silences the rest.
    func AdvanceDiscardedExpression(
        state: ExpressionStatementState,
        expression: Expression): ExpressionStatementRequest? {
        state.ErrorsBefore = diagnosticsValue.ErrorCount
        state.Phase = 1
        state.Pending = 1
        return NewExpressionRequest(expression)
    }

    // PHASE 1 — the placeholder exit and the row-escape report. A parser placeholder means the
    // expression was never really written, so nothing after this point may speak. The row report
    // ENDS the walk when it fires, which is what `ReportSoaRowEscapeIfNeeded`'s returned `true`
    // meant at the call site.
    func AdvanceDiscardedEscapes(
        state: ExpressionStatementState,
        expression: Expression): ExpressionStatementRequest? {
        if AnalyzerParserErrorPlaceholders.ContainsInExpression(expression) {
            state.Phase = 99
            return null
        }

        if diagnosticsValue.ErrorCount == state.ErrorsBefore {
            rowView := state.AnsweredType as SoaRowTypeInfo
            if rowView != null {
                state.Phase = 99
                return NewEscapeRequest(2, expression, state.SoaUsage)
            }
        }

        if diagnosticsValue.ErrorCount != state.ErrorsBefore {
            state.Phase = 2
            return null
        }

        state.Phase = 2
        state.Pending = 3
        return NewEscapeRequest(3, expression, state.SoaUsage)
    }

    // PHASE 2 — the validity decision. An expression that cannot stand as a statement reports the
    // form its context selects; anything else falls through to the must-use question.
    func AdvanceDiscardedValidity(
        state: ExpressionStatementState,
        expression: Expression): ExpressionStatementRequest? {
        if state.EscapeFired {
            state.Phase = 99
            return null
        }

        suppressed := diagnosticsValue.ErrorCount != state.ErrorsBefore
        if !IsValidExpressionStatement(expression) && !suppressed {
            ReportInvalidDiscardedExpression(expression, state.Context)
            state.Phase = 99
            return null
        }

        if suppressed {
            state.Phase = 99
            return null
        }

        candidate := UnwrapMustUseCandidate(expression)
        if candidate == null {
            state.Phase = 99
            return null
        }

        state.MustUseCandidate = candidate
        state.Phase = 3
        state.Pending = 8

        request := new ExpressionStatementRequest(8, BuiltInTypes.Unknown)
        request.Node = candidate.Callee
        request.Line = candidate.Callee.Line
        request.Column = candidate.Callee.Column
        return request
    }

    // PHASE 3 — the must-use report. The callee's type came back off the semantic model rather than
    // from a second analysis of the same AST.
    func AdvanceDiscardedMustUse(state: ExpressionStatementState): ExpressionStatementRequest? {
        state.Phase = 99

        candidate := state.MustUseCandidate
        if candidate == null {
            return null
        }

        calleeType := state.CalleeType
        if calleeType == null {
            return null
        }

        reason := MustUseReason(calleeType, candidate)
        if reason == null {
            return null
        }

        ReportDiscardedMustUseResult(candidate, reason)
        return null
    }

    // ── THE ASSERT WALK ────────────────────────────────────────────────────────────────────────

    // SIX PHASES, and every one of them runs unconditionally except the message pair. The assert arm
    // has NO error-count guard and NO short-circuit: both escape reports are called for the
    // condition, and then both again for the message when there is one, in exactly that order, and
    // neither answer is read. `Pending` stays 0 for the row and column steps for that reason.
    func AdvanceAssert(
        state: ExpressionStatementState,
        assertStatement: AssertStatement): ExpressionStatementRequest? {
        phase := state.Phase
        if phase == 10 {
            state.Phase = 11
            state.Pending = 1
            return NewExpressionRequest(assertStatement.Condition)
        }

        if phase == 11 {
            state.Phase = 12
            rowView := state.AnsweredType as SoaRowTypeInfo
            if rowView != null {
                return NewEscapeRequest(2, assertStatement.Condition, "asserted")
            }

            return null
        }

        if phase == 12 {
            state.Phase = 13
            return NewEscapeRequest(3, assertStatement.Condition, "asserted")
        }

        if phase == 13 {
            message := assertStatement.Message
            if message == null {
                state.Phase = 99
                return null
            }

            state.Phase = 14
            state.Pending = 1
            return NewExpressionRequest(message)
        }

        if phase == 14 {
            state.Phase = 15
            message := assertStatement.Message
            rowView := state.AnsweredType as SoaRowTypeInfo
            if message != null && rowView != null {
                return NewEscapeRequest(2, message, "used as an assertion message")
            }

            return null
        }

        if phase == 15 {
            state.Phase = 99
            message := assertStatement.Message
            if message != null {
                return NewEscapeRequest(3, message, "used as an assertion message")
            }

            return null
        }

        state.Phase = 99
        return null
    }

    // ── THE ASSERT-THROWS WALK ─────────────────────────────────────────────────────────────────

    func AdvanceAssertThrows(
        state: ExpressionStatementState,
        assertThrows: AssertThrowsStatement): ExpressionStatementRequest? {
        phase := state.Phase
        if phase == 20 {
            state.ExceptionType = typeResolverValue.ResolveDeclaredType(assertThrows.ExceptionType)
            state.Phase = 21
            state.Pending = 7

            request := new ExpressionStatementRequest(7, state.ExceptionType)
            return request
        }

        if phase == 21 {
            if !state.Throwable {
                ReportNonThrowableAssertThrowsType(assertThrows.ExceptionType, state.ExceptionType)
            }

            state.Phase = 22

            request := new ExpressionStatementRequest(4, BuiltInTypes.Unknown)
            request.Line = assertThrows.Line
            request.Column = assertThrows.Column
            return request
        }

        if phase == 22 {
            state.Phase = 23

            request := new ExpressionStatementRequest(5, BuiltInTypes.Unknown)
            request.Statements = assertThrows.Body.Statements
            return request
        }

        if phase == 23 {
            state.Phase = 99
            return new ExpressionStatementRequest(6, BuiltInTypes.Unknown)
        }

        state.Phase = 99
        return null
    }

    func NewExpressionRequest(expression: Expression): ExpressionStatementRequest {
        request := new ExpressionStatementRequest(1, BuiltInTypes.Unknown)
        request.Node = expression
        return request
    }

    func NewEscapeRequest(kind: int, expression: Expression, usage: string): ExpressionStatementRequest {
        request := new ExpressionStatementRequest(kind, BuiltInTypes.Unknown)
        request.Node = expression
        request.Text = usage
        return request
    }

    // ── WHAT MAY STAND AS A STATEMENT ──────────────────────────────────────────────────────────

    // Only the expressions that DO something: an assignment, a call, a construction, an event
    // subscription, an await, and the four increment/decrement forms. The three transparent wrappers
    // — parentheses, `checked` and `unchecked` — and an `alloc` are answered by what they wrap.
    public static func IsValidExpressionStatement(expression: Expression): bool {
        assignment := expression as AssignmentExpression
        if assignment != null {
            return true
        }

        call := expression as CallExpression
        if call != null {
            return true
        }

        construction := expression as NewExpression
        if construction != null {
            return true
        }

        subscription := expression as OnSubscriptionExpression
        if subscription != null {
            return true
        }

        allocation := expression as AllocExpression
        if allocation != null {
            return IsValidExpressionStatement(allocation.Expression)
        }

        awaited := expression as AwaitExpression
        if awaited != null {
            return true
        }

        unary := expression as UnaryExpression
        if unary != null {
            unaryOperator := unary.Operator
            return unaryOperator == UnaryOperator.PreIncrement
                || unaryOperator == UnaryOperator.PreDecrement
                || unaryOperator == UnaryOperator.PostIncrement
                || unaryOperator == UnaryOperator.PostDecrement
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return IsValidExpressionStatement(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return IsValidExpressionStatement(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return IsValidExpressionStatement(uncheckedExpression.Expression)
        }

        return false
    }

    // ── THE MUST-USE CLOSURE ───────────────────────────────────────────────────────────────────

    // The underlying call when the statement is a BARE call whose result would be silently dropped.
    // An explicit discard (`_ = call()`) is an assignment and never reaches here, and any other use
    // of the value is not a statement at all.
    public static func UnwrapMustUseCandidate(expression: Expression): CallExpression? {
        call := expression as CallExpression
        if call != null {
            return call
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return UnwrapMustUseCandidate(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return UnwrapMustUseCandidate(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return UnwrapMustUseCandidate(uncheckedExpression.Expression)
        }

        return null
    }

    // WHY THE RESULT MUST BE USED, or null when it need not be. FOUR shapes, one per callee kind: a
    // single N# function that carries `[MustUse]`; an N# method group whose functions ALL carry it;
    // a single reflected method whose CLR attributes name it; and a reflected method group whose
    // methods ALL carry it. A group with a single non-must-use member says nothing, because calling
    // it might have resolved to that member.
    public static func MustUseReason(calleeType: TypeInfo, call: CallExpression): string? {
        functionType := calleeType as FunctionTypeInfo
        if functionType != null {
            if functionType.HasMustUseAttribute {
                return "'" + AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call)
                    + "' is marked [MustUse]"
            }

            return null
        }

        group := calleeType as NSharpMethodGroupInfo
        if group != null {
            return NSharpMethodGroupMustUseReason(group)
        }

        method := calleeType as ReflectionMethodInfo
        if method != null {
            // The reflected method is read into a local first (the columnar backend declines the
            // property chain `method.Method.Name`), and its name through `get_Name()`, which is the
            // estate's spelling for a `MemberInfo` name on the columnar surface.
            reflected := method.Method
            if HasMustUseAttribute(reflected) {
                return "'" + reflected.get_Name() + "' is marked [MustUse]"
            }

            return null
        }

        methodGroup := calleeType as ReflectionMethodGroupInfo
        if methodGroup != null {
            return ReflectionMethodGroupMustUseReason(methodGroup)
        }

        return null
    }

    static func NSharpMethodGroupMustUseReason(group: NSharpMethodGroupInfo): string? {
        functions := NSharpMethodGroupInfoFactory.GetFunctions(group)
        if functions.Count == 0 {
            return null
        }

        index := 0
        while index < functions.Count {
            candidate := functions[index]
            if !candidate.HasMustUseAttribute {
                return null
            }

            index = index + 1
        }

        first := functions[0]
        name := first.SyntheticName
        if name == null {
            name = "function"
        }

        return "'" + name + "' is marked [MustUse]"
    }

    static func ReflectionMethodGroupMustUseReason(methodGroup: ReflectionMethodGroupInfo): string? {
        methods := methodGroup.Methods
        if methods.Length == 0 {
            return null
        }

        index := 0
        while index < methods.Length {
            candidate := methods[index]
            if !HasMustUseAttribute(candidate) {
                return null
            }

            index = index + 1
        }

        first := methods[0]
        return "'" + first.get_Name() + "' is marked [MustUse]"
    }

    // The CLR side of the same question, read off the reflected method's own attribute data. Both
    // the short name and the full name are offered to the shared name test, because a method
    // compiled against a differently-namespaced `MustUse` still means it.
    public static func HasMustUseAttribute(method: MethodInfo): bool {
        attributes := method.GetCustomAttributesData()
        count := SequenceCount(attributes)
        index := 0
        while index < count {
            attributeType := attributes.get_Item(index).get_AttributeType()
            if NominalTypeInfoFactory.IsMustUseAttributeName(attributeType.Name) {
                return true
            }

            fullName := attributeType.FullName
            if fullName != null && NominalTypeInfoFactory.IsMustUseAttributeName(fullName) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // The count comes through `object` deliberately: a closed generic `IList<T>` answered by
    // reflection does not cast to the non-generic `IList` on the columnar surface, but an `object`
    // does. This is `AnalyzerOverloadScoring`'s spelling, for the same reason.
    static func SequenceCount(sequence: object): int {
        list := (IList)sequence
        return list.Count
    }

    // NL315. The span is the CALL's, so the underline lands on the callee rather than on the whole
    // statement, and the subject names the callee when one can be named.
    func ReportDiscardedMustUseResult(call: CallExpression, reason: string) {
        calleeName := AnalyzerSyntheticCallFacts.GetCallTargetName(call)
        spanName := "call"
        subject := "this result"
        if calleeName != null {
            spanName = calleeName
            subject = "the result of '" + calleeName + "'"
        }

        span := spansValue.GetCallDiagnosticSpan(call, spanName)
        diagnosticsValue.Report(
            ErrorCode.DiscardedMustUseResult,
            "You're discarding " + subject + ", but " + reason + " — its result must be used",
            span.Line,
            span.Column,
            "Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.",
            span.Length)
    }

    // ── THE TWO NL313 FORMS ────────────────────────────────────────────────────────────────────

    func ReportInvalidDiscardedExpression(expression: Expression, context: DiscardedExpressionContext) {
        if context == DiscardedExpressionContext.ForIterator {
            ReportInvalidForIteratorExpression(expression)
            return
        }

        ReportInvalidExpressionStatement(expression)
    }

    func ReportInvalidExpressionStatement(expression: Expression) {
        span := spansValue.GetExpressionStatementDiagnosticSpan(expression)
        description := DescribeExpression(expression)

        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.InvalidExpressionStatement(
                currentFilePath,
                span.Line,
                span.Column,
                sourceSnippet,
                span.Length,
                description))
            return
        }

        diagnosticsValue.Report(
            ErrorCode.InvalidExpressionStatement,
            "This expression statement has no effect",
            span.Line,
            span.Column,
            "Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.",
            span.Length)
    }

    func ReportInvalidForIteratorExpression(expression: Expression) {
        span := spansValue.GetExpressionStatementDiagnosticSpan(expression)
        description := DescribeExpression(expression)

        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.InvalidForIteratorExpression(
                currentFilePath,
                span.Line,
                span.Column,
                sourceSnippet,
                span.Length,
                description))
            return
        }

        diagnosticsValue.Report(
            ErrorCode.InvalidExpressionStatement,
            "This for-loop iterator has no effect",
            span.Line,
            span.Column,
            "Use an assignment, call, increment, decrement, await expression, or object construction in the iterator clause, or remove the iterator.",
            span.Length)
    }

    // ── NL202, THE ASSERT-THROWS TYPE ──────────────────────────────────────────────────────────

    func ReportNonThrowableAssertThrowsType(typeReference: TypeReference, exceptionType: TypeInfo) {
        span := TypeReferenceFacts.GetStartSpan(typeReference)
        diagnosticsValue.Report(
            ErrorCode.TypeMismatch,
            "Assert throws type must be assignable to System.Exception, but this type is '"
                + TypeText(exceptionType) + "'",
            span.StartLine,
            span.StartColumn,
            "Assert an Exception-derived type, or use a broader exception type such as Exception.",
            span.Length)
    }

    // ── HOW AN EXPRESSION IS NAMED IN PROSE ────────────────────────────────────────────────────

    // The short human name a diagnostic uses for an expression. This is the family's, but two
    // attribute/table reporters that stay in `Analyzer.cs` still read it, so it is public and they
    // route here rather than keeping a second copy.
    public static func DescribeExpression(expression: Expression): string {
        identifier := expression as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            return memberAccess.MemberName
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return DescribeExpression(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return DescribeExpression(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return DescribeExpression(uncheckedExpression.Expression)
        }

        binary := expression as BinaryExpression
        if binary != null {
            return "binary expression"
        }

        indexAccess := expression as IndexAccessExpression
        if indexAccess != null {
            return "index access"
        }

        matchExpression := expression as MatchExpression
        if matchExpression != null {
            return "match expression"
        }

        // The `GetType()` receiver is cast to `object` first — the columnar backend declines a
        // `GetType()` call on a typed receiver (the recorded emitter gap).
        boxed := expression as object
        typeName := boxed.GetType().Name
        return typeName.Replace("Expression", "")
    }

    // `TypeInfo.ToString()` through a boxed receiver, which is what `$"{type}"` did in `Analyzer.cs`.
    static func TypeText(typeInfo: TypeInfo): string {
        boxed := typeInfo as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}

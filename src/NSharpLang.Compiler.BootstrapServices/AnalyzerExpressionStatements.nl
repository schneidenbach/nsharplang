namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// THE SIX STEPS THE STATEMENT-LEVEL EXPRESSION FAMILY CANNOT TAKE FOR ITSELF.
//
// This walk owns what it MEANS to write an expression where a statement belongs — a bare `f()` or
// `x = 1` as a statement, the update clause of a `for`, an `assert`, an `assert throws`, the operand
// of a `throw`, the value of a `print` and the handle of an `off` — which of those expressions
// actually DO anything, which of the family's five diagnostics fires and with which span, suggestion
// and wording, and whether a discarded result was one the callee said must be used. What it cannot
// do is run the analyzer's own EXPRESSION walk, open or close a scope on the
// analyzer's scope stack, re-enter the STATEMENT dispatch for an `assert throws` body, read the
// recorded type of an already-analysed callee out of the semantic model (which the analysis reset
// REPLACES, so it cannot be captured here) — so it ASKS: one request at a time, each naming a kind
// and carrying every value the step needs. Nothing here is a policy the driver may reinterpret — the driver
// switches on `Kind`, performs exactly the one operation with exactly these operands, and hands the
// answer back.
//
// THE TWO SoA ESCAPE REPORTS ARE NO LONGER STEPS. They were kinds 2 and 3 and are now direct calls
// on `AnalyzerSoaEscape`, which this walk holds: the reports moved to N# whole, so asking a driver
// to perform them would be asking C# to relay one N# call to another.
//
// The kinds:
//   1  analyse an expression WITHOUT touching the analyzer's ambient target-typing slot. No arm in
//      this family ever set it — a discarded expression, an assert condition and an assert message
//      are all analysed inside whatever target typing already surrounds them — so this is
//      `AnalyzerVariableDeclaration`'s kind 6, not its kind 1. ANSWERS a type.
//   4  open a block scope on the analyzer's scope stack at `Line` / `Column`.
//   5  analyse a statement LIST — the `assert throws` body — which re-enters the statement dispatch
//      and therefore this walk itself. Every `Begin` hands back a fresh state, so a nested
//      `assert throws` suspends independently of the one that contains it.
//   6  close the scope kind 4 opened.
//   8  ANSWERS the type the semantic model recorded for the expression at `Line` / `Column` — the
//      callee of a discarded call — or null when nothing was recorded. The call was already
//      analysed by kind 1, so re-analysing the AST would double-record bindings and references and
//      corrupt find-references; this reads the answer back instead.
//
// The numbering has GAPS at 2, 3 and 7 rather than closing up, because the kind number is a protocol
// between this walk and one driver, and a renumber would silently re-point every contract that pins
// a step's kind. The gaps say what left: 2 and 3 were the two SoA escape reports, and 7 asked the
// driver whether a type was throwable until `AnalyzerThrowability` took that predicate whole — this
// walk holds that owner now and asks it directly, which is why the `throw` and `assert throws` walks
// each lost a suspension.
class ExpressionStatementRequest {
    Kind: int
    Node: Expression?
    Statements: List<Statement>?
    CarriedType: TypeInfo
    Text: string?
    Line: int
    Column: int

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
// ONE state serves all six statement shapes, because ONE driver serves them all: exactly one of
// `discardedValue`, `assertValue`, `assertThrowsValue`, `thrownValue`, `printedValue` and
// `offHandleValue` is set, and which one is set selects the phase family.
//
// `Phase` is the walk's program counter. The DISCARD family runs 0..3: 0 captures the error count
// and asks for the expression, 1 folds the answer in and chooses between the placeholder exit, the
// row-escape report and the column-escape report, 2 folds the escape answer and reaches the
// validity decision, and 3 folds the recorded callee type and settles the must-use report. The
// ASSERT family runs 10..13 — condition, condition escapes, message, message escapes. The
// ASSERT-THROWS family runs 20, 22 and 23 — type resolution, the throwability report and the scope
// open, then the body, then the scope close; 21 is a GAP, and it is the phase the throwability
// round trip used to occupy. The THROW family runs 30..31 — the operand, then its two escapes and
// the throwability rule together, for the same reason. The PRINT family runs 40..41 — the value and
// its two escapes. The OFF family runs 50..51 — the handle, then its two escapes and the
// subscription rule together. 99 is done for all six.
//
// `ErrorsBefore` is the discard walk's guard, captured at phase 0 from the diagnostic sink's own
// count. Every later report in that walk is suppressed the instant the count differs, which is what
// keeps a statement from complaining that it "has no effect" on top of the real error inside it.
// The sink OWNS the error list, so the count is its own answer and not something the driver carries.
//
// THE CLR CONVERSION FUNNEL IS PASSED IN AT `Begin` for the two shapes that ask about throwability
// and is null for the other three. `Analyzer.cs` REBUILDS it when the metadata load context opens and
// again when it is disposed, so the throwability owner this walk HOLDS may not keep a reference to
// it — the same reason the loop family carries the flow-narrowing writer and the yield walk carries
// the assignability oracle.
class ExpressionStatementState {
    discardedValue: Expression?
    assertValue: AssertStatement?
    assertThrowsValue: AssertThrowsStatement?
    thrownValue: Expression?
    printedValue: Expression?
    offHandleValue: Expression?
    contextValue: DiscardedExpressionContext
    soaUsageValue: string
    clrTypeConversionValue: AnalyzerClrTypeConversion?
    subscriptionRootValue: Type?

    Discarded: Expression? => discardedValue
    Assert: AssertStatement? => assertValue
    AssertThrows: AssertThrowsStatement? => assertThrowsValue
    Thrown: Expression? => thrownValue
    Printed: Expression? => printedValue
    OffHandle: Expression? => offHandleValue
    Context: DiscardedExpressionContext => contextValue
    SoaUsage: string => soaUsageValue
    ClrTypeConversion: AnalyzerClrTypeConversion? => clrTypeConversionValue
    SubscriptionRoot: Type? => subscriptionRootValue

    Phase: int
    Pending: int

    ErrorsBefore: int
    AnsweredType: TypeInfo
    EscapeFired: bool
    ExceptionType: TypeInfo
    CalleeType: TypeInfo?
    MustUseCandidate: CallExpression?

    constructor(discarded: Expression?, assertStatement: AssertStatement?, assertThrows: AssertThrowsStatement?, thrown: Expression?, printed: Expression?, offHandle: Expression?, context: DiscardedExpressionContext, soaUsage: string, clrTypeConversion: AnalyzerClrTypeConversion?, subscriptionRoot: Type?) {
        discardedValue = discarded
        assertValue = assertStatement
        assertThrowsValue = assertThrows
        thrownValue = thrown
        printedValue = printed
        offHandleValue = offHandle
        contextValue = context
        soaUsageValue = soaUsage
        clrTypeConversionValue = clrTypeConversion
        subscriptionRootValue = subscriptionRoot

        Phase = 0
        if assertStatement != null {
            Phase = 10
        }

        if assertThrows != null {
            Phase = 20
        }

        if thrown != null {
            Phase = 30
        }

        if printed != null {
            Phase = 40
        }

        if offHandle != null {
            Phase = 50
        }

        Pending = 0
        ErrorsBefore = 0
        AnsweredType = BuiltInTypes.Unknown
        EscapeFired = false
        ExceptionType = BuiltInTypes.Unknown
        CalleeType = null
        MustUseCandidate = null
    }
}

// WHAT AN EXPRESSION MEANS WHERE A STATEMENT BELONGS, as a walk that suspends at each step it cannot
// take itself.
//
// This is the analyzer's expression/statement walker territory, and it owns the family that has no
// value to hand anywhere: the bare expression statement, the `for` loop's update clause, `assert`,
// `assert throws`, `throw`, `print` and `off`. `Analyzer.cs` kept the family as FOURTEEN members of
// which ELEVEN had no
// caller outside it — the must-use closure (unwrap, reason, the reflected-attribute test), the
// validity predicate, the two rich invalid-statement reporters and their context selector, and the
// assert-throws type reporter — so they are here rather than left behind as callbacks.
//
// WHY A SEPARATE DRIVER FROM `DriveLocalDeclaration`, WHICH THIS ONCE OVERLAPPED ON THREE KINDS.
// Kind 1 here IS that driver's kind 6 — the same expression walk with the ambient target-typing slot
// left alone. The other two shared kinds were the SoA escape reports, and they are gone from BOTH
// drivers now that the reports are N#-owned; what is left, kinds 4, 5, 6 and 8, are re-entries NO
// local declaration makes: a `let` never opens a scope, never re-enters the statement dispatch and
// never reads a callee type back out of the semantic model. Sharing would mean widening `VariableDeclarationState`
// with a statement list and a scope program counter it can never use, and coupling two statement
// families through one request type. So the overlap is stated rather than forced, and this family
// keeps its own request, its own state and its own loop.
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
// THE THROWABILITY QUESTION IS NO LONGER A DRIVER STEP. It was kind 7, relayed to a predicate that
// stayed in `Analyzer.cs` because the catch-clause family shared it; that predicate is
// `AnalyzerThrowability` now, this walk holds it, and both questions ask it directly. The DECISION to
// report, the wording, the suggestion and the span were always here and are unchanged — the two
// reports differ in every one of those four things.
//
// THE FIVE DIAGNOSTICS ARE `Analyzer.cs`'s VERBATIM. NL318 is the `off` handle report, whose
// suggestion names the two-step shape that works. NL313 has TWO forms selected by
// `DiscardedExpressionContext` — the expression-statement form and the for-iterator form — each
// with a rich `ErrorMessageBuilder` shape when the file has a snippet and a detail-only fallback
// when it does not. NL315 is the must-use report, whose REASON has four shapes, one per callee kind.
// NL202 is the assert-throws non-throwable report. `assert` itself reports NOTHING of its own: it
// deliberately does not require a boolean condition, because N# supports several comparison shapes
// there, so everything it can raise comes from the two SoA reporters it re-enters.
class AnalyzerExpressionStatements {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    typeResolverValue: AnalyzerTypeResolver
    soaEscapeValue: AnalyzerSoaEscape
    throwabilityValue: AnalyzerThrowability

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, typeResolver: AnalyzerTypeResolver, soaEscape: AnalyzerSoaEscape, throwability: AnalyzerThrowability) {
        diagnosticsValue = diagnostics
        spansValue = spans
        typeResolverValue = typeResolver
        soaEscapeValue = soaEscape
        throwabilityValue = throwability
    }

    // A BARE EXPRESSION USED AS A STATEMENT. The SoA reports call it "discarded" and an invalid one
    // reports the expression-statement form of NL313.
    func BeginExpressionStatement(expression: Expression): ExpressionStatementState {
        return new ExpressionStatementState(expression, null, null, null, null, null, DiscardedExpressionContext.ExpressionStatement, "discarded", null, null)
    }

    // THE `for` LOOP'S UPDATE CLAUSE. The same walk with two different constants: the SoA reports
    // name the iterator, and an invalid one reports the for-iterator form of NL313.
    func BeginForIterator(expression: Expression): ExpressionStatementState {
        return new ExpressionStatementState(expression, null, null, null, null, null, DiscardedExpressionContext.ForIterator, "used as a 'for' iterator", null, null)
    }

    func BeginAssert(assertStatement: AssertStatement): ExpressionStatementState {
        return new ExpressionStatementState(null, assertStatement, null, null, null, null, DiscardedExpressionContext.ExpressionStatement, "asserted", null, null)
    }

    // AN `assert throws`. The CLR conversion funnel is read from the caller's field HERE, because the
    // declared exception type is measured for throwability.
    func BeginAssertThrows(assertThrows: AssertThrowsStatement, clrTypeConversion: AnalyzerClrTypeConversion): ExpressionStatementState {
        return new ExpressionStatementState(null, null, assertThrows, null, null, null, DiscardedExpressionContext.ExpressionStatement, "asserted", clrTypeConversion, null)
    }

    // A `throw` STATEMENT'S OPERAND. The SoA reports call it "thrown", and a value that survives both
    // of them is measured against `System.Exception`.
    func BeginThrow(expression: Expression, clrTypeConversion: AnalyzerClrTypeConversion): ExpressionStatementState {
        return new ExpressionStatementState(null, null, null, expression, null, null, DiscardedExpressionContext.ExpressionStatement, "thrown", clrTypeConversion, null)
    }

    // A `print` STATEMENT'S VALUE. The shortest walk in the family: `print` has no rule of its own —
    // anything can be printed — so everything it can raise comes from the two SoA reporters, and BOTH
    // of them always run.
    func BeginPrint(expression: Expression): ExpressionStatementState {
        return new ExpressionStatementState(null, null, null, null, expression, null, DiscardedExpressionContext.ExpressionStatement, "printed", null, null)
    }

    // AN `off` STATEMENT'S HANDLE. `off sub` detaches an event subscription, and its handle is an
    // expression in statement position exactly as a `throw` operand and a `print` value are — one
    // keyword, one expression, and a rule about the type that expression answers. The SoA reports
    // name it `used as an off handle`, and a handle that survives both of them is measured against
    // the runtime subscription root.
    //
    // THE SUBSCRIPTION ROOT IS PASSED IN rather than named here, and the reason is agreement rather
    // than convenience. `Analyzer.cs`'s `on` expression PRODUCES a handle's type as a reflection type
    // over the RUNTIME `NSharpEventSubscription`; `off` must measure against that same identity, and
    // handing it from the one place that already names it makes the two halves agree structurally
    // instead of by two independent spellings. It is also the only door that is testable: this
    // project does not reference `NSharpLang.Runtime`, so a `Type.GetType` here would resolve only
    // because the analyzer's HOST happens to carry the assembly.
    func BeginOff(expression: Expression, subscriptionRoot: Type): ExpressionStatementState {
        return new ExpressionStatementState(null, null, null, null, null, expression, DiscardedExpressionContext.ExpressionStatement, "used as an off handle", null, subscriptionRoot)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this statement is finished. Every phase
    // either decides something and advances, or emits exactly one request; the walk never advances
    // past a point whose answer it has not been given.
    func NextStep(state: ExpressionStatementState): ExpressionStatementRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Kind 1 answers a type — the discard walk's escape choice
    // and the assert walk's escape choice both read it. Kind 8 answers the recorded callee type,
    // which selects the must-use reason. Kinds 4, 5 and 6 answer nothing.
    func Supply(state: ExpressionStatementState, answer: TypeInfo?) {
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

        thrown := state.Thrown
        if thrown != null {
            return AdvanceThrow(state, thrown)
        }

        printed := state.Printed
        if printed != null {
            return AdvancePrint(state, printed)
        }

        offHandle := state.OffHandle
        if offHandle != null {
            return AdvanceOff(state, offHandle)
        }

        discarded := state.Discarded
        if discarded != null {
            return AdvanceDiscarded(state, discarded)
        }

        state.Phase = 99
        return null
    }

    // ── THE `throw` WALK ───────────────────────────────────────────────────────────────────────
    //
    // Two phases, and the second one is the whole reason this is a walk rather than a call: the
    // operand's ANSWERED type is what the row-escape report measures, and whether that report fired
    // is what decides if the column probe runs at all — which is what the `&&` chain in the arm this
    // replaced meant. A value already refused as a row view is not also told it is a direct column
    // read, and a value refused as either is not ALSO told it is not throwable: one bad operand is
    // one diagnostic. The throwability question used to be a THIRD phase and a driver round trip; it
    // is a direct call on the owner now, so the walk suspends once instead of twice.
    func AdvanceThrow(state: ExpressionStatementState, expression: Expression): ExpressionStatementRequest? {
        phase := state.Phase
        if phase == 30 {
            state.Phase = 31
            state.Pending = 1
            return NewExpressionRequest(expression)
        }

        if phase == 31 {
            state.Phase = 99
            if soaEscapeValue.ReportSoaRowEscapeIfNeeded(expression, state.AnsweredType, "thrown") {
                state.EscapeFired = true
                return null
            }

            if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expression, "thrown") {
                state.EscapeFired = true
                return null
            }

            if !IsThrowable(state, state.AnsweredType) {
                ReportNonThrowableThrowOperand(expression, state.AnsweredType)
            }

            return null
        }

        state.Phase = 99
        return null
    }

    // WHETHER THIS TYPE MAY BE THROWN OR CAUGHT, asked of the owner that answers it for all three of
    // the language's questions. A state built without the CLR conversion funnel cannot reach here:
    // only `BeginThrow` and `BeginAssertThrows` carry one, and they are the only two shapes that ask.
    func IsThrowable(state: ExpressionStatementState, candidate: TypeInfo): bool {
        clrTypeConversion := state.ClrTypeConversion
        if clrTypeConversion == null {
            return true
        }

        return throwabilityValue.IsThrowable(candidate, clrTypeConversion)
    }

    // NL202 ON A `throw` OPERAND. The span is the whole thrown expression, so the underline lands on
    // the value rather than on the keyword.
    func ReportNonThrowableThrowOperand(expression: Expression, thrownType: TypeInfo) {
        span := spansValue.GetExpressionDiagnosticSpan(expression)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "Throw expressions must be assignable to System.Exception, but this expression is '" + TypeText(thrownType) + "'", span.Line, span.Column, "Throw an Exception-derived value, or wrap this value in an exception type.", span.Length)
    }

    // ── THE `print` WALK ───────────────────────────────────────────────────────────────────────
    //
    // Two phases and no rule of its own. BOTH escape reports run and NEITHER short-circuits the
    // other — which is the one thing about `print` that is easy to get wrong, because every other
    // member of this family and of the loop family stops at the first one that fires. `print` did
    // not, and the difference is a second squiggle on a value that is both a row view by type and a
    // column read by syntax.
    func AdvancePrint(state: ExpressionStatementState, expression: Expression): ExpressionStatementRequest? {
        phase := state.Phase
        if phase == 40 {
            state.Phase = 41
            state.Pending = 1
            return NewExpressionRequest(expression)
        }

        if phase == 41 {
            state.Phase = 99
            rowFired := soaEscapeValue.ReportSoaRowEscapeIfNeeded(expression, state.AnsweredType, "printed")
            columnFired := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expression, "printed")
            state.EscapeFired = rowFired || columnFired
            return null
        }

        state.Phase = 99
        return null
    }

    // ── THE `off` WALK ─────────────────────────────────────────────────────────────────────────
    //
    // Two phases, and FOUR silence rules in a fixed order before the one report it can make. The
    // handle's answered type is what the row report measures, so the walk suspends once; everything
    // after that is a chain of exits. A handle already refused as a row view is not ALSO probed as a
    // direct column read — unlike `print`, and like `throw` — and a handle refused as either is not
    // told it is not a subscription. An `unknown` handle is silent because an earlier error already
    // explained the problem, and only a handle that is none of those four things reaches NL318.
    func AdvanceOff(state: ExpressionStatementState, expression: Expression): ExpressionStatementRequest? {
        phase := state.Phase
        if phase == 50 {
            state.Phase = 51
            state.Pending = 1
            return NewExpressionRequest(expression)
        }

        if phase == 51 {
            state.Phase = 99
            handleType := state.AnsweredType
            if soaEscapeValue.ReportSoaRowEscapeIfNeeded(expression, handleType, state.SoaUsage) {
                state.EscapeFired = true
                return null
            }

            if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expression, state.SoaUsage) {
                state.EscapeFired = true
                return null
            }

            if BuiltInTypes.IsUnknown(handleType) {
                return null
            }

            if IsEventSubscriptionHandle(handleType, state.SubscriptionRoot) {
                return null
            }

            ReportInvalidOffHandle(expression)
            return null
        }

        state.Phase = 99
        return null
    }

    // WHETHER A HANDLE IS A SUBSCRIPTION `on` PRODUCED. `AnalyzeOnExpression` types its result as the
    // RUNTIME `NSharpEventSubscription`, so the test is RAW CLR assignability against that runtime
    // identity — deliberately NOT `AnalyzerConversionFacts.IsReflectionAssignableFrom`, whose
    // cross-context identity comparison would ALSO accept a type of the same name loaded into the
    // analyzer's MetadataLoadContext. `Analyzer.cs` asked `typeof(...).IsAssignableFrom(...)` and that
    // answered NO for an MLC twin; this answers NO for the same reason. A non-reflected handle never
    // reaches the root at all, which is what keeps the whole question off `int` and `string`.
    static func IsEventSubscriptionHandle(handleType: TypeInfo, subscriptionRoot: Type?): bool {
        reflected := handleType as ReflectionTypeInfo
        if reflected == null {
            return false
        }

        if subscriptionRoot == null {
            return false
        }

        return subscriptionRoot.IsAssignableFrom(reflected.Type)
    }

    // NL318. The span is the whole handle expression, so the underline lands on the value rather than
    // on the `off` keyword, and the suggestion shows the two-step shape that works.
    func ReportInvalidOffHandle(expression: Expression) {
        span := spansValue.GetExpressionDiagnosticSpan(expression)
        diagnosticsValue.Report(ErrorCode.InvalidEventSubscription, "`off` expects a subscription returned by `on`", span.Line, span.Column, "Capture the subscription first (`sub := on <object>.<Event> handler`), then detach it with `off sub`.", span.Length)
    }

    // ── THE DISCARD WALK ───────────────────────────────────────────────────────────────────────

    func AdvanceDiscarded(state: ExpressionStatementState, expression: Expression): ExpressionStatementRequest? {
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
    func AdvanceDiscardedExpression(state: ExpressionStatementState, expression: Expression): ExpressionStatementRequest? {
        state.ErrorsBefore = diagnosticsValue.ErrorCount
        state.Phase = 1
        state.Pending = 1
        return NewExpressionRequest(expression)
    }

    // PHASE 1 — the placeholder exit and the row-escape report. A parser placeholder means the
    // expression was never really written, so nothing after this point may speak. The row report
    // ENDS the walk when it fires, which is what `ReportSoaRowEscapeIfNeeded`'s returned `true`
    // meant at the call site.
    //
    // The error-count guard is read TWICE and neither read is redundant. The FIRST gates the row
    // report; the SECOND gates the column report, and it is only ever reached when the row report did
    // NOT fire, because that branch ends the walk itself. So a value the walk already rejected as a
    // row view is never also offered to the column probe — which is what
    // `ReportSoaRowEscapeIfNeeded`'s returned `true` meant at the C# call site.
    func AdvanceDiscardedEscapes(state: ExpressionStatementState, expression: Expression): ExpressionStatementRequest? {
        if AnalyzerParserErrorPlaceholders.ContainsInExpression(expression) {
            state.Phase = 99
            return null
        }

        if diagnosticsValue.ErrorCount == state.ErrorsBefore {
            rowView := state.AnsweredType as SoaRowTypeInfo
            if rowView != null {
                state.Phase = 99
                soaEscapeValue.ReportSoaRowEscape(expression, state.SoaUsage)
                return null
            }
        }

        if diagnosticsValue.ErrorCount != state.ErrorsBefore {
            state.Phase = 2
            return null
        }

        state.Phase = 2
        state.EscapeFired = soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expression, state.SoaUsage)
        return null
    }

    // PHASE 2 — the validity decision. An expression that cannot stand as a statement reports the
    // form its context selects; anything else falls through to the must-use question.
    func AdvanceDiscardedValidity(state: ExpressionStatementState, expression: Expression): ExpressionStatementRequest? {
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
    // neither answer is read. The phases survive the reports becoming direct calls because the
    // EXPRESSION steps between them are still suspensions.
    func AdvanceAssert(state: ExpressionStatementState, assertStatement: AssertStatement): ExpressionStatementRequest? {
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
                soaEscapeValue.ReportSoaRowEscape(assertStatement.Condition, "asserted")
            }

            return null
        }

        if phase == 12 {
            state.Phase = 13
            soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(assertStatement.Condition, "asserted")
            return null
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
                soaEscapeValue.ReportSoaRowEscape(message, "used as an assertion message")
            }

            return null
        }

        if phase == 15 {
            state.Phase = 99
            message := assertStatement.Message
            if message != null {
                soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(message, "used as an assertion message")
            }

            return null
        }

        state.Phase = 99
        return null
    }

    // ── THE ASSERT-THROWS WALK ─────────────────────────────────────────────────────────────────

    func AdvanceAssertThrows(state: ExpressionStatementState, assertThrows: AssertThrowsStatement): ExpressionStatementRequest? {
        phase := state.Phase
        if phase == 20 {
            state.ExceptionType = typeResolverValue.ResolveDeclaredType(assertThrows.ExceptionType)
            if !IsThrowable(state, state.ExceptionType) {
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

    // ── WHAT MAY STAND AS A STATEMENT ──────────────────────────────────────────────────────────

    // Only the expressions that DO something: an assignment, a call, a construction, an event
    // subscription, an await, and the four increment/decrement forms. The three transparent wrappers
    // — parentheses, `checked` and `unchecked` — and an `alloc` are answered by what they wrap.
    static func IsValidExpressionStatement(expression: Expression): bool {
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
            return unaryOperator == UnaryOperator.PreIncrement || unaryOperator == UnaryOperator.PreDecrement || unaryOperator == UnaryOperator.PostIncrement || unaryOperator == UnaryOperator.PostDecrement
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
    static func UnwrapMustUseCandidate(expression: Expression): CallExpression? {
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
    static func MustUseReason(calleeType: TypeInfo, call: CallExpression): string? {
        functionType := calleeType as FunctionTypeInfo
        if functionType != null {
            if functionType.HasMustUseAttribute {
                return "'" + AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call) + "' is marked [MustUse]"
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
    static func HasMustUseAttribute(method: MethodInfo): bool {
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
        diagnosticsValue.Report(ErrorCode.DiscardedMustUseResult, "You're discarding " + subject + ", but " + reason + " — its result must be used", span.Line, span.Column, "Use the result (assign it, return it, or pass it to a call), or discard it explicitly with `_ = ...`.", span.Length)
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
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.InvalidExpressionStatement(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, description))
            return
        }

        diagnosticsValue.Report(ErrorCode.InvalidExpressionStatement, "This expression statement has no effect", span.Line, span.Column, "Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.", span.Length)
    }

    func ReportInvalidForIteratorExpression(expression: Expression) {
        span := spansValue.GetExpressionStatementDiagnosticSpan(expression)
        description := DescribeExpression(expression)

        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.InvalidForIteratorExpression(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, description))
            return
        }

        diagnosticsValue.Report(ErrorCode.InvalidExpressionStatement, "This for-loop iterator has no effect", span.Line, span.Column, "Use an assignment, call, increment, decrement, await expression, or object construction in the iterator clause, or remove the iterator.", span.Length)
    }

    // ── NL202, THE ASSERT-THROWS TYPE ──────────────────────────────────────────────────────────

    func ReportNonThrowableAssertThrowsType(typeReference: TypeReference, exceptionType: TypeInfo) {
        span := TypeReferenceFacts.GetStartSpan(typeReference)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "Assert throws type must be assignable to System.Exception, but this type is '" + TypeText(exceptionType) + "'", span.StartLine, span.StartColumn, "Assert an Exception-derived type, or use a broader exception type such as Exception.", span.Length)
    }

    // ── HOW AN EXPRESSION IS NAMED IN PROSE ────────────────────────────────────────────────────

    // The short human name a diagnostic uses for an expression. This is the family's, but two
    // attribute/table reporters that stay in `Analyzer.cs` still read it, so it is public and they
    // route here rather than keeping a second copy.
    static func DescribeExpression(expression: Expression): string {
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

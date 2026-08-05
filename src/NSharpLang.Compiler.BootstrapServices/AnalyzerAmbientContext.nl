namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast


// A SNAPSHOT OF THE WHOLE AMBIENT CONTEXT, HELD BY THE CALLER FOR THE LENGTH OF ONE NESTED WALK.
//
// The frame is handed BACK to the C# caller rather than pushed onto a stack inside the context, and
// that is a deliberate lifetime decision, not a convenience. Of the seven save/restore idioms the
// analyzer uses, exactly ONE — the block-bodied lambda — restores from a `finally`; the other six
// restore on the straight line and are SKIPPED when the walk throws. An internal stack would pop in
// `Exit`, so a throw would leave a stale frame on it and the NEXT `Exit` would restore the wrong
// one; worse, it would quietly make six idioms exception-safe that are not. A frame in the caller's
// own local is abandoned by a throw exactly as the C# locals were.
class AmbientContextFrame {
    ReturnType: TypeInfo?
    Function: FunctionDeclaration?
    ReturnTypeWasOmitted: bool
    IsAsync: bool
    InLoop: bool
    FinallyDepth: int
    BreakTargetFinallyDepth: int
    ContinueTargetFinallyDepth: int

    constructor(returnType: TypeInfo?, declaration: FunctionDeclaration?, returnTypeWasOmitted: bool, isAsync: bool, inLoop: bool, finallyDepth: int, breakTargetFinallyDepth: int, continueTargetFinallyDepth: int) {
        ReturnType = returnType
        Function = declaration
        ReturnTypeWasOmitted = returnTypeWasOmitted
        IsAsync = isAsync
        InLoop = inLoop
        FinallyDepth = finallyDepth
        BreakTargetFinallyDepth = breakTargetFinallyDepth
        ContinueTargetFinallyDepth = continueTargetFinallyDepth
    }
}

// THE ONE STEP A `return` STATEMENT CANNOT TAKE FOR ITSELF.
//
// The walk owns what a `return` MEANS: whether there is a function to return from at all, whether the
// statement leaves a `finally`, what type the returned expression is asked for (the AWAITED result
// type in an `async` function, the declared type otherwise), which of the two SoA escape reports the
// returned type selects, whether a generator may return a value, and whether the value fits — plus
// the bare-`return` arm's "not all code paths return a value" pair. What it cannot do is run the
// analyzer's own EXPRESSION walk — so it ASKS, once.
//
// IT ASKED THREE THINGS AND NOW ASKS ONE. Kinds 2 and 3 were the two SoA escape reports, and they are
// now direct calls on `AnalyzerSoaEscape`, which this owner holds. WHICH of the two the returned type
// selects was always this walk's decision and still is; only the round trip through C# is gone. Kind
// 1 remains a suspension because the analyzer's expression walk is still C#'s.
//
//   1  analyse the RETURNED expression. ANSWERS a type, and that type decides which escape report
//      runs, whether the generator report fires and whether the value fits. It does NOT carry an
//      expected type for the driver to install: this owner IS the ambient context, so it sets its own
//      target-typing slot before emitting the request and restores it when the answer arrives — the
//      transition never leaves N#.
class ReturnStatementRequest {
    Kind: int
    Node: Expression?
    Text: string?

    constructor(kind: int) {
        Kind = kind
        Node = null
        Text = null
    }
}

// THE `return` STATEMENT'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Phase` is the walk's program counter: 0 decides whether there is a function at all, reports a
// `return` out of a `finally`, and either finishes the bare form or opens the target type and asks
// for the value; 1 folds the answer in, closes the target type and chooses ONE escape report; 2
// applies the generator rule and the assignability rule. 99 is done.
//
// The ASSIGNABILITY ORACLE IS CARRIED ON THE STATE rather than held as a field, and that is a
// lifetime decision: `Analyzer.cs` REBUILDS its assignability whenever the metadata load context is
// created or disposed, while the ambient context is constructed once and never rebuilt because it
// holds live walk state that a rebuild would silently reset. Reading the field at `Begin` gets
// whichever instance is current at the moment the statement is analysed — exactly what the C# call
// site read — without making this owner rebuildable.
//
// `SavedExpectedType` is the caller-held frame of the target-typing slot, kept HERE because the
// boundary opens in one phase and closes in the next. A throw inside the expression walk abandons it
// exactly as the C# local was abandoned: `Supply` is never reached, so the slot is not restored, and
// the analyzer unwinds out of the whole statement either way.
class ReturnStatementState {
    statementValue: ReturnStatement
    assignabilityValue: AnalyzerAssignability

    Statement: ReturnStatement => statementValue
    Assignability: AnalyzerAssignability => assignabilityValue

    Phase: int
    Pending: int
    ValueNode: Expression?
    ExpectedReturnValueType: TypeInfo
    ReturnedType: TypeInfo
    SavedExpectedType: TypeInfo?

    constructor(statement: ReturnStatement, assignability: AnalyzerAssignability) {
        statementValue = statement
        assignabilityValue = assignability
        Phase = 0
        Pending = 0
        ValueNode = null
        ExpectedReturnValueType = BuiltInTypes.Unknown
        ReturnedType = BuiltInTypes.Unknown
        SavedExpectedType = null
    }
}

// WHERE THE WALK CURRENTLY IS — THE THREE AMBIENT FAMILIES, AND EVERYTHING THAT IS A PURE FUNCTION OF
// THEM.
//
// The FUNCTION family answers "what may a `return` do here": the enclosing function's declaration,
// the type it returns, whether that type was written down or inferred as `void`, and whether the
// function is `async`. The CONTROL-FLOW family answers "what may a `break`, a `continue` or a
// `return` do here": whether a loop is open, how deep inside `finally` handlers the walk is, and the
// depth at which the innermost `break` and `continue` targets were entered. The EXPECTED-TYPE family
// answers "what is this expression being asked for" — the target-typing slot that `default`, `new()`,
// a collection literal, an integer literal's width, a lambda's parameters and an unbound callable
// reference all resolve against.
//
// The first two families are ONE object because they are saved and restored TOGETHER at the two
// boundaries that matter — a lambda's block body and a local function's body — where a nested body
// gets a fresh function context AND a zeroed control-flow context in the same breath. Splitting them
// would make those two sites pay twice and would let the two halves drift out of step. The
// expected-type family joins them because it moves at the SAME KIND of boundary, with the same
// snapshot-to-caller lifetime — and because the `return` arm is the one place all three meet: the
// function family says what type the value is asked for, the control-flow family says whether the
// statement may leave, and the expected-type family carries the answer into the expression walk.
//
// The context also OWNS the reports that are pure functions of it and nothing else: `break` and
// `continue` outside a loop, all three flavours of control leaving a `finally` (NL319), and the
// four return-value-mismatch shapes, whose wording turns entirely on the enclosing function's name,
// its declared-versus-omitted return type and whether that type is `void`. Nothing here needs the
// expression walk, the scope stack or the type resolver — which is exactly why they belong with the
// state rather than with the statement arms that happen to trigger them.
//
// AND IT OWNS THE `return` STATEMENT ITSELF, as a suspendable walk. That arm reads FIVE things this
// object already answers and reports through TWO members it already owns; hosting it anywhere else
// would mean exporting all seven. What it does not own it asks for, three kinds at a time.
//
// WHAT THIS OBJECT DELIBERATELY DOES NOT DO: it never decides WHEN a boundary opens. The caller
// still chooses to enter a loop, a nested body, a `finally` or a target type; the context only
// records that it happened, hands back the frame to undo it, and answers questions about where the
// walk now is.
class AnalyzerAmbientContext {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    soaEscapeValue: AnalyzerSoaEscape

    currentReturnTypeValue: TypeInfo?
    currentFunctionValue: FunctionDeclaration?
    returnTypeWasOmittedValue: bool
    isAsyncValue: bool
    inLoopValue: bool
    finallyDepthValue: int
    breakTargetFinallyDepthValue: int
    continueTargetFinallyDepthValue: int
    currentExpectedTypeValue: TypeInfo?

    // THE ENCLOSING FUNCTION'S RETURN TYPE, and `null` when there is no enclosing function at all —
    // which is the ONLY thing that distinguishes "a `return` is illegal here" from "a `return` must
    // produce a value of this type".
    CurrentReturnType: TypeInfo? => currentReturnTypeValue

    // The enclosing function's DECLARATION, or `null` inside a lambda's block body (a lambda has no
    // declaration to name, so a diagnostic about it says "this function").
    CurrentFunction: FunctionDeclaration? => currentFunctionValue

    // Whether the enclosing function's return type was OMITTED rather than written. Every
    // return-value diagnostic changes both its wording and its SPAN on this — an omitted return type
    // squiggles the function's NAME, because that is where the fix goes.
    CurrentFunctionReturnTypeWasOmitted: bool => returnTypeWasOmittedValue

    // Whether the enclosing function is `async`, recorded from its modifiers when the body was
    // entered. A `return` in an async function is checked against the AWAITED result type.
    CurrentFunctionIsAsync: bool => isAsyncValue

    // Whether the enclosing function is declared `generator` (`func*`). Read off the declaration
    // rather than recorded separately, exactly as the two C# readers did.
    CurrentFunctionDeclaresGenerator: bool => HasModifier(currentFunctionValue, Modifiers.Generator)

    // Whether the enclosing function is declared `async`, read off the declaration. This is a
    // DIFFERENT question from `CurrentFunctionIsAsync` even though the two always agree today: one
    // asks the declaration, the other reads what was recorded when the body was entered, and the
    // generator-element walk asks the declaration.
    CurrentFunctionDeclaresAsync: bool => HasModifier(currentFunctionValue, Modifiers.Async)

    // Whether a loop body is currently open. `break` and `continue` are legal only here.
    InLoop: bool => inLoopValue

    // How many `finally` blocks enclose the walk. Depth, not immediate parent: a `return` inside a
    // `try` nested in a `finally` still leaves the handler.
    FinallyDepth: int => finallyDepthValue

    // The finally depth at which the innermost `break` target — a loop, or a `switch` — was entered.
    // A `break` written deeper than this would have to leave a handler to reach it.
    BreakTargetFinallyDepth: int => breakTargetFinallyDepthValue

    // The same for `continue`, whose target is always a LOOP: a `switch` moves the break target and
    // leaves this one alone.
    ContinueTargetFinallyDepth: int => continueTargetFinallyDepthValue

    // Whether a `return` at this point would leave a `finally` handler — illegal IL (ECMA-335: a
    // finally may only complete via its own end).
    ReturnWouldLeaveFinally: bool => finallyDepthValue > 0

    // WHAT TYPE THE SURROUNDING CODE IS ASKING THIS EXPRESSION FOR, or `null` when nothing is asking.
    // This is the TARGET-TYPING slot: the whole answer to `default`, `new()`, a collection literal's
    // element type, an integer literal's width, a negative literal's signedness, a lambda's parameter
    // types, `Ok`/`Err`'s arms, a generic union case's arguments and whether a bare method name is an
    // unbound callable reference. Twenty-two sites READ it and sixteen save/set/restore it around a
    // nested walk.
    CurrentExpectedType: TypeInfo? => currentExpectedTypeValue

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, soaEscape: AnalyzerSoaEscape) {
        diagnosticsValue = diagnostics
        spansValue = spans
        soaEscapeValue = soaEscape
        currentReturnTypeValue = null
        currentFunctionValue = null
        returnTypeWasOmittedValue = false
        isAsyncValue = false
        inLoopValue = false
        finallyDepthValue = 0
        breakTargetFinallyDepthValue = 0
        continueTargetFinallyDepthValue = 0
        currentExpectedTypeValue = null
    }

    // One call per analysis, from the same reset block that clears the scope stack and the null-flow
    // state. A compilation unit starts outside every function, every loop and every `finally`.
    //
    // THE EXPECTED TYPE IS DELIBERATELY NOT RESET HERE. `Analyzer.cs` reset the other eight fields in
    // its `Analyze` prologue and left the target-typing slot alone, and that is preserved verbatim: it
    // is only ever written inside a matched save/restore pair, so it is already `null` at every point
    // a new analysis can begin, and resetting it would be a write this family never performed.
    func BeginAnalysis() {
        currentReturnTypeValue = null
        currentFunctionValue = null
        returnTypeWasOmittedValue = false
        isAsyncValue = false
        inLoopValue = false
        finallyDepthValue = 0
        breakTargetFinallyDepthValue = 0
        continueTargetFinallyDepthValue = 0
    }

    // Everything the context holds, as one value. Every `Enter` takes one of these first; each
    // matching `Exit` restores exactly the subset ITS boundary is responsible for, and the doc on
    // each pair names that subset.
    func Snapshot(): AmbientContextFrame {
        return new AmbientContextFrame(currentReturnTypeValue, currentFunctionValue, returnTypeWasOmittedValue, isAsyncValue, inLoopValue, finallyDepthValue, breakTargetFinallyDepthValue, continueTargetFinallyDepthValue)
    }

    // A TOP-LEVEL FUNCTION DECLARATION'S BODY. Sets the whole function family and leaves the
    // control-flow family alone: a declaration is never analysed from inside a loop or a `finally`,
    // so there is nothing there to reset.
    func EnterFunctionDeclaration(declaration: FunctionDeclaration, returnType: TypeInfo): AmbientContextFrame {
        saved := Snapshot()
        currentReturnTypeValue = returnType
        currentFunctionValue = declaration
        returnTypeWasOmittedValue = declaration.ReturnType == null
        isAsyncValue = HasModifier(declaration, Modifiers.Async)
        return saved
    }

    // Restores the function, the omitted flag and the async flag — and sets the return type to
    // `null` rather than to the saved one. That ASYMMETRY is the original behaviour and is preserved
    // deliberately: leaving a declaration leaves "inside a function" entirely, so a stray `return`
    // between declarations is reported as having no function to return from.
    func ExitFunctionDeclaration(saved: AmbientContextFrame) {
        currentReturnTypeValue = null
        currentFunctionValue = saved.Function
        returnTypeWasOmittedValue = saved.ReturnTypeWasOmitted
        isAsyncValue = saved.IsAsync
    }

    // A PROPERTY OR INDEXER ACCESSOR BODY. An accessor changes what a `return` must produce and
    // NOTHING else — not the enclosing function's identity, which is what a diagnostic still names,
    // and not the omitted flag, because an accessor's type is always written. The saved value is a
    // bare type rather than a frame: the C# it replaces held exactly one local too.
    func EnterAccessorReturnType(returnType: TypeInfo): TypeInfo? {
        saved := currentReturnTypeValue
        currentReturnTypeValue = returnType
        return saved
    }

    func ExitAccessorReturnType(saved: TypeInfo?) {
        currentReturnTypeValue = saved
    }

    // A NESTED BODY — a local function, or a lambda's block body. Sets the function family from the
    // nested declaration (a lambda passes `null`, and then answers "this function" and an omitted
    // return type of `false`) and ZEROES the control-flow family, which is the whole point: a
    // `return` inside a nested body exits the NESTED body, not any `finally` the declaration happens
    // to sit inside, and `break`/`continue` cannot target a loop in the enclosing method at all.
    func EnterNestedBody(declaration: FunctionDeclaration?, returnType: TypeInfo?): AmbientContextFrame {
        saved := Snapshot()
        currentReturnTypeValue = returnType
        currentFunctionValue = declaration
        returnTypeWasOmittedValue = DeclaresOmittedReturnType(declaration)
        isAsyncValue = HasModifier(declaration, Modifiers.Async)
        inLoopValue = false
        finallyDepthValue = 0
        breakTargetFinallyDepthValue = 0
        continueTargetFinallyDepthValue = 0
        return saved
    }

    // Restores ALL EIGHT. A nested body is the only boundary that saved all of them.
    func ExitNestedBody(saved: AmbientContextFrame) {
        currentReturnTypeValue = saved.ReturnType
        currentFunctionValue = saved.Function
        returnTypeWasOmittedValue = saved.ReturnTypeWasOmitted
        isAsyncValue = saved.IsAsync
        inLoopValue = saved.InLoop
        finallyDepthValue = saved.FinallyDepth
        breakTargetFinallyDepthValue = saved.BreakTargetFinallyDepth
        continueTargetFinallyDepthValue = saved.ContinueTargetFinallyDepth
    }

    // A LOOP BODY — `while`, `for`, `foreach` or `await foreach`. Opens the loop and records the
    // CURRENT finally depth as both branch targets: a `break` or `continue` written deeper than this
    // is inside a `finally` the branch would have to leave.
    func EnterLoop(): AmbientContextFrame {
        saved := Snapshot()
        inLoopValue = true
        breakTargetFinallyDepthValue = finallyDepthValue
        continueTargetFinallyDepthValue = finallyDepthValue
        return saved
    }

    // Restores the loop flag and BOTH branch-target depths — never the finally depth itself, which
    // a loop body cannot change on its own.
    func ExitLoop(saved: AmbientContextFrame) {
        inLoopValue = saved.InLoop
        breakTargetFinallyDepthValue = saved.BreakTargetFinallyDepth
        continueTargetFinallyDepthValue = saved.ContinueTargetFinallyDepth
    }

    // A SWITCH BODY. A `break` in a case body targets the SWITCH — the emitter pushes a break label
    // per switch — so the break target's depth becomes the switch's entry depth. `continue` still
    // targets the enclosing loop, so its depth is untouched, and the loop flag is untouched too: a
    // switch does not make `continue` legal where it was not.
    func EnterSwitch(): int {
        saved := breakTargetFinallyDepthValue
        breakTargetFinallyDepthValue = finallyDepthValue
        return saved
    }

    func ExitSwitch(saved: int) {
        breakTargetFinallyDepthValue = saved
    }

    // A `finally` BLOCK. Finallys nest, so this is a counter rather than a flag.
    func EnterFinally() {
        finallyDepthValue = finallyDepthValue + 1
    }

    func ExitFinally() {
        finallyDepthValue = finallyDepthValue - 1
    }

    // A NESTED WALK UNDER A TARGET TYPE. The saved value is a bare type rather than a frame, exactly
    // as the accessor pair's is: the C# this replaces held one local per site too. Sixteen sites open
    // one of these; THREE of them restore from a `finally` and thirteen restore on the straight line,
    // and that difference is the caller's to keep — the frame lives in the caller's own local, so the
    // exception path is whatever the caller writes, unchanged by construction.
    func EnterExpectedType(expected: TypeInfo?): TypeInfo? {
        saved := currentExpectedTypeValue
        currentExpectedTypeValue = expected
        return saved
    }

    // THE SAME BOUNDARY, OPENED ONLY WHEN THERE IS SOMETHING TO ASK FOR. Five sites compute a
    // candidate expected type that may not exist — a tuple element with no matching element in the
    // target, a constructor argument that is not the SoA count, an index that is not an integer
    // index, an initializer element of a non-collection target, an explicit `null` passed to
    // `AnalyzeExpressionWithExpectedType` — and LEAVE the slot alone when it does not. That is NOT
    // the same as setting it to `null`: leaving it keeps whatever target typing already surrounds the
    // walk, and nulling it would change what `default`, `new()`, a lambda and a negative integer
    // literal resolve to inside it. Restored by `ExitExpectedType` either way, because the saved
    // value round-trips unchanged when nothing was set.
    func EnterExpectedTypeIfProvided(expected: TypeInfo?): TypeInfo? {
        saved := currentExpectedTypeValue
        if expected != null {
            currentExpectedTypeValue = expected
        }

        return saved
    }

    func ExitExpectedType(saved: TypeInfo?) {
        currentExpectedTypeValue = saved
    }

    // `break`: illegal outside a loop, and illegal when it would leave a `finally` to reach one.
    // The two are exclusive — a `break` with no loop at all is told THAT, not told about handlers.
    func ReportBreakIfNeeded(line: int, column: int) {
        if !inLoopValue {
            diagnosticsValue.Report(ErrorCode.InvalidSyntax, "'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here", line, column, "Move this `break` inside a loop, or remove it if there is no loop to exit.", 5)
            return
        }

        if finallyDepthValue > breakTargetFinallyDepthValue {
            ReportControlTransferOutOfFinally("break", line, column)
        }
    }

    // `continue`: the same two rules against the CONTINUE target's depth, which a switch does not
    // move.
    func ReportContinueIfNeeded(line: int, column: int) {
        if !inLoopValue {
            diagnosticsValue.Report(ErrorCode.InvalidSyntax, "'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here", line, column, "Move this `continue` inside a loop, or remove it if there is no loop to continue.", 8)
            return
        }

        if finallyDepthValue > continueTargetFinallyDepthValue {
            ReportControlTransferOutOfFinally("continue", line, column)
        }
    }

    // `return`: any depth at all is a violation, because a return leaves every handler it is inside.
    func ReportReturnOutOfFinallyIfNeeded(line: int, column: int) {
        if finallyDepthValue > 0 {
            ReportControlTransferOutOfFinally("return", line, column)
        }
    }

    // NL319, in the rich shape when the file has a snippet and the detail-only shape otherwise.
    func ReportControlTransferOutOfFinally(keyword: string, line: int, column: int) {
        sourceSnippet := diagnosticsValue.SourceSnippet(line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.ControlTransferOutOfFinally(currentFilePath, line, column, sourceSnippet, keyword.Length, keyword))
            return
        }

        diagnosticsValue.Report(ErrorCode.ControlTransferOutOfFinally, "Control cannot leave a 'finally' block with '" + keyword + "'", line, column, "Move the `" + keyword + "` outside the `finally` block.", keyword.Length)
    }

    // THE `return` STATEMENT'S ENTRY. The assignability oracle is read from the caller's field HERE,
    // at the moment the statement is analysed, rather than held — see `ReturnStatementState`.
    func BeginReturn(statement: ReturnStatement, assignability: AnalyzerAssignability): ReturnStatementState {
        return new ReturnStatementState(statement, assignability)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this `return` is finished. Every phase
    // either decides something and advances, or emits exactly one request; the walk never advances
    // past a point whose answer it has not been given.
    func NextStep(state: ReturnStatementState): ReturnStatementRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 remains, and it answers the returned
    // expression's type, which is the operand of the escape-report choice, the generator report and
    // the assignability check. Kind 1 is ALSO where the target-typing slot closes, because the C# it
    // replaces restored the slot on the line after the expression walk returned.
    func Supply(state: ReturnStatementState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending == 1 {
            ExitExpectedType(state.SavedExpectedType)
            state.SavedExpectedType = null
            if answer != null {
                state.ReturnedType = answer
            }
        }
    }

    func Advance(state: ReturnStatementState): ReturnStatementRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceEntry(state)
        }

        if phase == 1 {
            return AdvanceEscapeReport(state)
        }

        if phase == 2 {
            return AdvanceValueRules(state)
        }

        state.Phase = 99
        return null
    }

    // PHASE 0 — IS THERE A FUNCTION TO RETURN FROM. This is the ONLY question asked before the
    // out-of-`finally` report, and a `return` with no enclosing function is told THAT and nothing
    // else: the arm returns immediately, so it never reports leaving a handler and never walks the
    // value.
    func AdvanceEntry(state: ReturnStatementState): ReturnStatementRequest? {
        statement := state.Statement
        returnType := currentReturnTypeValue
        if returnType != null {
            return AdvanceInsideFunction(state, statement, returnType)
        }

        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "'return' can only be used inside a function — there's no function to return from here", statement.Line, statement.Column, "Move this `return` inside a function, or remove it if there is no function to return from.", 6)
        state.Phase = 99
        return null
    }

    // The out-of-`finally` report fires for EVERY `return` inside a handler, with or without a value,
    // and BEFORE the value is walked — so a `return` that is both illegal here and ill-typed reports
    // the handler violation first.
    func AdvanceInsideFunction(state: ReturnStatementState, statement: ReturnStatement, returnType: TypeInfo): ReturnStatementRequest? {
        ReportReturnOutOfFinallyIfNeeded(statement.Line, statement.Column)

        value := statement.Value
        if value != null {
            expected := ReturnValueTargetType(returnType)
            state.ValueNode = value
            state.ExpectedReturnValueType = expected
            state.SavedExpectedType = EnterExpectedType(expected)
            state.Phase = 1
            state.Pending = 1
            request := new ReturnStatementRequest(1)
            request.Node = value
            request.Text = "returned"
            return request
        }

        ReportMissingReturnValueIfNeeded(statement, returnType)
        state.Phase = 99
        return null
    }

    // WHAT THE RETURNED EXPRESSION IS ASKED FOR. In an `async` function whose return type is a
    // task-like WITH a result, the value is checked against the AWAITED result rather than the task —
    // and an `async` function whose return type is not task-like at all (an error the declaration
    // reports elsewhere) falls back to the declared type, because the unwrap simply does not fire.
    func ReturnValueTargetType(returnType: TypeInfo): TypeInfo {
        asyncResultType: TypeInfo = BuiltInTypes.Unknown
        if isAsyncValue && AnalyzerFunctionTypeFactory.TryGetTaskLikeResultTypeInfo(returnType, out asyncResultType) {
            return asyncResultType
        }

        return returnType
    }

    // PHASE 1 — EXACTLY ONE ESCAPE REPORT, chosen by the answer. A row view is reported as a row
    // escape; everything else is offered to the direct-column reporter. The two are never both asked.
    // The direct-column reporter's boolean is DELIBERATELY discarded: the C# arm called it in
    // statement position and ignored its result, so — unlike a local declaration, where a fired escape
    // turns the declared type unknown — nothing later in a `return` is suppressed by it.
    func AdvanceEscapeReport(state: ReturnStatementState): ReturnStatementRequest? {
        state.Phase = 2
        value := state.ValueNode
        if value != null {
            rowView := state.ReturnedType as SoaRowTypeInfo
            if rowView != null {
                soaEscapeValue.ReportSoaRowEscape(value, "returned")
            } else {
                soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(value, "returned")
            }
        }

        return null
    }

    // PHASE 2 — THE TWO VALUE RULES, IN ORDER. A generator may not return a value at all, and that
    // report ENDS the arm: the assignability check never runs after it, because a generator's declared
    // type is the SEQUENCE and comparing the yielded value against it would pile a second, wrong
    // diagnostic onto the same expression.
    func AdvanceValueRules(state: ReturnStatementState): ReturnStatementRequest? {
        state.Phase = 99
        value := state.ValueNode
        if value != null {
            ReportReturnedValue(state, value)
        }

        return null
    }

    func ReportReturnedValue(state: ReturnStatementState, value: Expression) {
        if CurrentFunctionDeclaresGenerator {
            span := spansValue.GetExpressionDiagnosticSpan(value)
            diagnosticsValue.Report(ErrorCode.InvalidSyntax, "Generator functions cannot return a value", span.Line, span.Column, "Use `yield value` to produce sequence values, or a bare `return`/`yield break` to stop iteration.", span.Length)
            return
        }

        expected := state.ExpectedReturnValueType
        returnedType := state.ReturnedType
        if !state.Assignability.IsAssignable(expected, returnedType) {
            ReportReturnValueMismatch(state.Statement, returnedType, expected)
        }
    }

    // A BARE `return` IN A FUNCTION THAT OWES A VALUE. Silent for `void`, and silent for an `async`
    // function whose return type is a UNIT task-like (`Task`/`ValueTask`), which owes nothing either.
    // The span is the `return` keyword — six characters — in both shapes.
    func ReportMissingReturnValueIfNeeded(statement: ReturnStatement, returnType: TypeInfo) {
        if BuiltInTypes.Is(returnType, BuiltInTypes.Void) {
            return
        }

        if isAsyncValue && AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(returnType) {
            return
        }

        returnTypeName := TypeText(returnType)
        sourceSnippet := diagnosticsValue.SourceSnippet(statement.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.MissingReturn(currentFilePath, statement.Line, statement.Column, sourceSnippet, 6, returnTypeName))
            return
        }

        diagnosticsValue.Report(ErrorCode.MissingReturn, "This function should return '" + returnTypeName + "', but this 'return' doesn't provide a value", statement.Line, statement.Column, null, 0)
    }

    // A `return` STATEMENT WHOSE VALUE DOES NOT FIT. Three rich shapes and one detail-only fallback,
    // all selected by the ambient function context alone: a `void` return type with the annotation
    // OMITTED asks the author to add one and squiggles the function's NAME; a `void` return type
    // that was WRITTEN says the function is declared to return nothing; anything else is an ordinary
    // type mismatch against the expected type. The span falls back through the returned expression
    // to the `return` keyword itself.
    func ReportReturnValueMismatch(returnStatement: ReturnStatement, returnedType: TypeInfo, expectedReturnValueType: TypeInfo) {
        statementSnippet := diagnosticsValue.SourceSnippet(returnStatement.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if statementSnippet != null && currentFilePath != null {
            declaration := currentFunctionValue
            span: DiagnosticSpan = new DiagnosticSpan(returnStatement.Line, returnStatement.Column, 6)
            returnedValue := returnStatement.Value
            if returnTypeWasOmittedValue && declaration != null {
                span = spansValue.GetFunctionNameDiagnosticSpan(declaration)
            } else if returnedValue != null {
                span = spansValue.GetExpressionDiagnosticSpan(returnedValue)
            }

            diagnosticSourceSnippet := statementSnippet
            spanLineSnippet := diagnosticsValue.SourceSnippet(span.Line)
            if spanLineSnippet != null {
                diagnosticSourceSnippet = spanLineSnippet
            }

            diagnosticsValue.ReportBuilt(BuildReturnValueMismatchError(currentFilePath, span, diagnosticSourceSnippet, returnedType, expectedReturnValueType))
            return
        }

        diagnosticsValue.Report(ErrorCode.TypeMismatch, FormatReturnValueMismatchMessage(returnedType, expectedReturnValueType), returnStatement.Line, returnStatement.Column, null, 0)
    }

    // AN EXPRESSION-BODIED FUNCTION whose expression gives back a value the `void` return type
    // cannot take. The same two `void` shapes as a `return` statement, spanned on the function's
    // NAME when the return type was omitted and on the expression otherwise.
    func ReportExpressionBodyReturn(declaration: FunctionDeclaration, expressionType: TypeInfo) {
        span: DiagnosticSpan = new DiagnosticSpan(declaration.Line, declaration.Column, 1)
        expressionBody := declaration.ExpressionBody
        if returnTypeWasOmittedValue {
            span = spansValue.GetFunctionNameDiagnosticSpan(declaration)
        } else if expressionBody != null {
            span = spansValue.GetExpressionDiagnosticSpan(expressionBody)
        }

        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(BuildVoidReturnValueError(currentFilePath, span, sourceSnippet, declaration.Name, expressionType))
            return
        }

        diagnosticsValue.Report(ErrorCode.TypeMismatch, FormatReturnValueMismatchMessage(expressionType, BuiltInTypes.Void), span.Line, span.Column, null, 0)
    }

    // The rich builder choice for a `return` statement: the two `void` shapes, or the general
    // mismatch against the expected type.
    func BuildReturnValueMismatchError(currentFilePath: string, span: DiagnosticSpan, sourceSnippet: string, returnedType: TypeInfo, expectedReturnValueType: TypeInfo): CompilerError {
        if BuiltInTypes.Is(currentReturnTypeValue, BuiltInTypes.Void) {
            return BuildVoidReturnValueError(currentFilePath, span, sourceSnippet, EnclosingFunctionName(), returnedType)
        }

        actualTypeName := TypeText(returnedType)
        expectedTypeName := TypeText(expectedReturnValueType)
        return ErrorMessageBuilder.ReturnTypeMismatch(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, EnclosingFunctionName(), actualTypeName, expectedTypeName)
    }

    // The `void` pair, shared by the `return` statement and the expression body: an OMITTED return
    // type is a missing annotation the author should add, a WRITTEN `void` is a deliberate choice
    // the returned value contradicts.
    func BuildVoidReturnValueError(currentFilePath: string, span: DiagnosticSpan, sourceSnippet: string, functionName: string, returnedType: TypeInfo): CompilerError {
        actualTypeName := TypeText(returnedType)
        if returnTypeWasOmittedValue {
            return ErrorMessageBuilder.ReturnValueRequiresReturnType(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, functionName, actualTypeName)
        }

        return ErrorMessageBuilder.ReturnValueInVoidFunction(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, functionName, actualTypeName)
    }

    // The detail-only wording, used when the file has no snippet to underline. Three shapes, chosen
    // by the same two questions the rich builders ask.
    func FormatReturnValueMismatchMessage(returnedType: TypeInfo, expectedReturnValueType: TypeInfo): string {
        functionName := EnclosingFunctionName()
        actualTypeName := TypeText(returnedType)

        if BuiltInTypes.Is(currentReturnTypeValue, BuiltInTypes.Void) {
            if returnTypeWasOmittedValue {
                return "Function '" + functionName + "' has no return type annotation, so it is treated as 'void', but this code gives back '" + actualTypeName + "'"
            }

            return "Function '" + functionName + "' is declared to return 'void', but this code gives back '" + actualTypeName + "'"
        }

        expectedTypeName := TypeText(expectedReturnValueType)
        return "Function '" + functionName + "' should return '" + expectedTypeName + "', but this return statement gives back '" + actualTypeName + "'"
    }

    // What a diagnostic calls the enclosing function. A lambda's block body has no declaration to
    // name.
    func EnclosingFunctionName(): string {
        declaration := currentFunctionValue
        if declaration != null {
            return declaration.Name
        }

        return "this function"
    }

    // A TYPE'S RENDERED TEXT, TAKEN THROUGH `object`. `Analyzer.cs` wrote `$"{type}"` and
    // `type.ToString()`; the columnar backend declines a virtual `ToString` called directly on a
    // `TypeInfo`, so the estate's spelling is to box first. Same helper, same reason, as
    // `AnalyzerVariableDeclaration.TypeText` and `AnalyzerExpressionStatements.TypeText`.
    static func TypeText(typeInfo: TypeInfo): string {
        boxed := typeInfo as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }

    static func DeclaresOmittedReturnType(declaration: FunctionDeclaration?): bool {
        if declaration != null {
            return declaration.ReturnType == null
        }

        return false
    }

    static func HasModifier(declaration: FunctionDeclaration?, modifier: Modifiers): bool {
        if declaration != null {
            modifierBits := Convert.ToInt32(declaration.Modifiers)
            flagBits := Convert.ToInt32(modifier)
            return (modifierBits & flagBits) == flagBits
        }

        return false
    }
}

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
public class AmbientContextFrame {

    public ReturnType: TypeInfo?
    public Function: FunctionDeclaration?
    public ReturnTypeWasOmitted: bool
    public IsAsync: bool
    public InLoop: bool
    public FinallyDepth: int
    public BreakTargetFinallyDepth: int
    public ContinueTargetFinallyDepth: int

    constructor(
        returnType: TypeInfo?,
        declaration: FunctionDeclaration?,
        returnTypeWasOmitted: bool,
        isAsync: bool,
        inLoop: bool,
        finallyDepth: int,
        breakTargetFinallyDepth: int,
        continueTargetFinallyDepth: int) {
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

// WHERE THE WALK CURRENTLY IS — THE TWO AMBIENT FAMILIES, AND EVERYTHING THAT IS A PURE FUNCTION OF
// THEM.
//
// The FUNCTION family answers "what may a `return` do here": the enclosing function's declaration,
// the type it returns, whether that type was written down or inferred as `void`, and whether the
// function is `async`. The CONTROL-FLOW family answers "what may a `break`, a `continue` or a
// `return` do here": whether a loop is open, how deep inside `finally` handlers the walk is, and the
// depth at which the innermost `break` and `continue` targets were entered.
//
// The two families are ONE object because they are saved and restored TOGETHER at the two boundaries
// that matter — a lambda's block body and a local function's body — where a nested body gets a fresh
// function context AND a zeroed control-flow context in the same breath. Splitting them would make
// those two sites pay twice and would let the two halves drift out of step.
//
// The context also OWNS the reports that are pure functions of it and nothing else: `break` and
// `continue` outside a loop, all three flavours of control leaving a `finally` (NL319), and the
// four return-value-mismatch shapes, whose wording turns entirely on the enclosing function's name,
// its declared-versus-omitted return type and whether that type is `void`. Nothing here needs the
// expression walk, the scope stack or the type resolver — which is exactly why they belong with the
// state rather than with the statement arms that happen to trigger them.
//
// WHAT THIS OBJECT DELIBERATELY DOES NOT DO: it never decides WHEN a boundary opens. The caller
// still chooses to enter a loop, a nested body or a `finally`; the context only records that it
// happened, hands back the frame to undo it, and answers questions about where the walk now is.
public class AnalyzerAmbientContext {

    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans

    currentReturnTypeValue: TypeInfo?
    currentFunctionValue: FunctionDeclaration?
    returnTypeWasOmittedValue: bool
    isAsyncValue: bool
    inLoopValue: bool
    finallyDepthValue: int
    breakTargetFinallyDepthValue: int
    continueTargetFinallyDepthValue: int

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

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans) {
        diagnosticsValue = diagnostics
        spansValue = spans
        currentReturnTypeValue = null
        currentFunctionValue = null
        returnTypeWasOmittedValue = false
        isAsyncValue = false
        inLoopValue = false
        finallyDepthValue = 0
        breakTargetFinallyDepthValue = 0
        continueTargetFinallyDepthValue = 0
    }

    // One call per analysis, from the same reset block that clears the scope stack and the null-flow
    // state. A compilation unit starts outside every function, every loop and every `finally`.
    public func BeginAnalysis() {
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
    public func Snapshot(): AmbientContextFrame {
        return new AmbientContextFrame(
            currentReturnTypeValue,
            currentFunctionValue,
            returnTypeWasOmittedValue,
            isAsyncValue,
            inLoopValue,
            finallyDepthValue,
            breakTargetFinallyDepthValue,
            continueTargetFinallyDepthValue)
    }

    // A TOP-LEVEL FUNCTION DECLARATION'S BODY. Sets the whole function family and leaves the
    // control-flow family alone: a declaration is never analysed from inside a loop or a `finally`,
    // so there is nothing there to reset.
    public func EnterFunctionDeclaration(
        declaration: FunctionDeclaration,
        returnType: TypeInfo): AmbientContextFrame {
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
    public func ExitFunctionDeclaration(saved: AmbientContextFrame) {
        currentReturnTypeValue = null
        currentFunctionValue = saved.Function
        returnTypeWasOmittedValue = saved.ReturnTypeWasOmitted
        isAsyncValue = saved.IsAsync
    }

    // A PROPERTY OR INDEXER ACCESSOR BODY. An accessor changes what a `return` must produce and
    // NOTHING else — not the enclosing function's identity, which is what a diagnostic still names,
    // and not the omitted flag, because an accessor's type is always written. The saved value is a
    // bare type rather than a frame: the C# it replaces held exactly one local too.
    public func EnterAccessorReturnType(returnType: TypeInfo): TypeInfo? {
        saved := currentReturnTypeValue
        currentReturnTypeValue = returnType
        return saved
    }

    public func ExitAccessorReturnType(saved: TypeInfo?) {
        currentReturnTypeValue = saved
    }

    // A NESTED BODY — a local function, or a lambda's block body. Sets the function family from the
    // nested declaration (a lambda passes `null`, and then answers "this function" and an omitted
    // return type of `false`) and ZEROES the control-flow family, which is the whole point: a
    // `return` inside a nested body exits the NESTED body, not any `finally` the declaration happens
    // to sit inside, and `break`/`continue` cannot target a loop in the enclosing method at all.
    public func EnterNestedBody(
        declaration: FunctionDeclaration?,
        returnType: TypeInfo?): AmbientContextFrame {
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
    public func ExitNestedBody(saved: AmbientContextFrame) {
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
    public func EnterLoop(): AmbientContextFrame {
        saved := Snapshot()
        inLoopValue = true
        breakTargetFinallyDepthValue = finallyDepthValue
        continueTargetFinallyDepthValue = finallyDepthValue
        return saved
    }

    // Restores the loop flag and BOTH branch-target depths — never the finally depth itself, which
    // a loop body cannot change on its own.
    public func ExitLoop(saved: AmbientContextFrame) {
        inLoopValue = saved.InLoop
        breakTargetFinallyDepthValue = saved.BreakTargetFinallyDepth
        continueTargetFinallyDepthValue = saved.ContinueTargetFinallyDepth
    }

    // A SWITCH BODY. A `break` in a case body targets the SWITCH — the emitter pushes a break label
    // per switch — so the break target's depth becomes the switch's entry depth. `continue` still
    // targets the enclosing loop, so its depth is untouched, and the loop flag is untouched too: a
    // switch does not make `continue` legal where it was not.
    public func EnterSwitch(): int {
        saved := breakTargetFinallyDepthValue
        breakTargetFinallyDepthValue = finallyDepthValue
        return saved
    }

    public func ExitSwitch(saved: int) {
        breakTargetFinallyDepthValue = saved
    }

    // A `finally` BLOCK. Finallys nest, so this is a counter rather than a flag.
    public func EnterFinally() {
        finallyDepthValue = finallyDepthValue + 1
    }

    public func ExitFinally() {
        finallyDepthValue = finallyDepthValue - 1
    }

    // `break`: illegal outside a loop, and illegal when it would leave a `finally` to reach one.
    // The two are exclusive — a `break` with no loop at all is told THAT, not told about handlers.
    public func ReportBreakIfNeeded(line: int, column: int) {
        if !inLoopValue {
            diagnosticsValue.Report(
                ErrorCode.InvalidSyntax,
                "'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here",
                line,
                column,
                "Move this `break` inside a loop, or remove it if there is no loop to exit.",
                5)
            return
        }

        if finallyDepthValue > breakTargetFinallyDepthValue {
            ReportControlTransferOutOfFinally("break", line, column)
        }
    }

    // `continue`: the same two rules against the CONTINUE target's depth, which a switch does not
    // move.
    public func ReportContinueIfNeeded(line: int, column: int) {
        if !inLoopValue {
            diagnosticsValue.Report(
                ErrorCode.InvalidSyntax,
                "'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here",
                line,
                column,
                "Move this `continue` inside a loop, or remove it if there is no loop to continue.",
                8)
            return
        }

        if finallyDepthValue > continueTargetFinallyDepthValue {
            ReportControlTransferOutOfFinally("continue", line, column)
        }
    }

    // `return`: any depth at all is a violation, because a return leaves every handler it is inside.
    public func ReportReturnOutOfFinallyIfNeeded(line: int, column: int) {
        if finallyDepthValue > 0 {
            ReportControlTransferOutOfFinally("return", line, column)
        }
    }

    // NL319, in the rich shape when the file has a snippet and the detail-only shape otherwise.
    func ReportControlTransferOutOfFinally(keyword: string, line: int, column: int) {
        sourceSnippet := diagnosticsValue.SourceSnippet(line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.ControlTransferOutOfFinally(
                currentFilePath,
                line,
                column,
                sourceSnippet,
                keyword.Length,
                keyword))
            return
        }

        diagnosticsValue.Report(
            ErrorCode.ControlTransferOutOfFinally,
            "Control cannot leave a 'finally' block with '" + keyword + "'",
            line,
            column,
            "Move the `" + keyword + "` outside the `finally` block.",
            keyword.Length)
    }

    // A `return` STATEMENT WHOSE VALUE DOES NOT FIT. Three rich shapes and one detail-only fallback,
    // all selected by the ambient function context alone: a `void` return type with the annotation
    // OMITTED asks the author to add one and squiggles the function's NAME; a `void` return type
    // that was WRITTEN says the function is declared to return nothing; anything else is an ordinary
    // type mismatch against the expected type. The span falls back through the returned expression
    // to the `return` keyword itself.
    public func ReportReturnValueMismatch(
        returnStatement: ReturnStatement,
        returnedType: TypeInfo,
        expectedReturnValueType: TypeInfo) {
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

            diagnosticsValue.ReportBuilt(BuildReturnValueMismatchError(
                currentFilePath,
                span,
                diagnosticSourceSnippet,
                returnedType,
                expectedReturnValueType))
            return
        }

        diagnosticsValue.Report(
            ErrorCode.TypeMismatch,
            FormatReturnValueMismatchMessage(returnedType, expectedReturnValueType),
            returnStatement.Line,
            returnStatement.Column,
            null,
            0)
    }

    // AN EXPRESSION-BODIED FUNCTION whose expression gives back a value the `void` return type
    // cannot take. The same two `void` shapes as a `return` statement, spanned on the function's
    // NAME when the return type was omitted and on the expression otherwise.
    public func ReportExpressionBodyReturn(declaration: FunctionDeclaration, expressionType: TypeInfo) {
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
            diagnosticsValue.ReportBuilt(BuildVoidReturnValueError(
                currentFilePath,
                span,
                sourceSnippet,
                declaration.Name,
                expressionType))
            return
        }

        diagnosticsValue.Report(
            ErrorCode.TypeMismatch,
            FormatReturnValueMismatchMessage(expressionType, BuiltInTypes.Void),
            span.Line,
            span.Column,
            null,
            0)
    }

    // The rich builder choice for a `return` statement: the two `void` shapes, or the general
    // mismatch against the expected type.
    func BuildReturnValueMismatchError(
        currentFilePath: string,
        span: DiagnosticSpan,
        sourceSnippet: string,
        returnedType: TypeInfo,
        expectedReturnValueType: TypeInfo): CompilerError {
        if BuiltInTypes.Is(currentReturnTypeValue, BuiltInTypes.Void) {
            return BuildVoidReturnValueError(
                currentFilePath,
                span,
                sourceSnippet,
                EnclosingFunctionName(),
                returnedType)
        }

        actualTypeName := TypeText(returnedType)
        expectedTypeName := TypeText(expectedReturnValueType)
        return ErrorMessageBuilder.ReturnTypeMismatch(
            currentFilePath,
            span.Line,
            span.Column,
            sourceSnippet,
            span.Length,
            EnclosingFunctionName(),
            actualTypeName,
            expectedTypeName)
    }

    // The `void` pair, shared by the `return` statement and the expression body: an OMITTED return
    // type is a missing annotation the author should add, a WRITTEN `void` is a deliberate choice
    // the returned value contradicts.
    func BuildVoidReturnValueError(
        currentFilePath: string,
        span: DiagnosticSpan,
        sourceSnippet: string,
        functionName: string,
        returnedType: TypeInfo): CompilerError {
        actualTypeName := TypeText(returnedType)
        if returnTypeWasOmittedValue {
            return ErrorMessageBuilder.ReturnValueRequiresReturnType(
                currentFilePath,
                span.Line,
                span.Column,
                sourceSnippet,
                span.Length,
                functionName,
                actualTypeName)
        }

        return ErrorMessageBuilder.ReturnValueInVoidFunction(
            currentFilePath,
            span.Line,
            span.Column,
            sourceSnippet,
            span.Length,
            functionName,
            actualTypeName)
    }

    // The detail-only wording, used when the file has no snippet to underline. Three shapes, chosen
    // by the same two questions the rich builders ask.
    public func FormatReturnValueMismatchMessage(
        returnedType: TypeInfo,
        expectedReturnValueType: TypeInfo): string {
        functionName := EnclosingFunctionName()
        actualTypeName := TypeText(returnedType)

        if BuiltInTypes.Is(currentReturnTypeValue, BuiltInTypes.Void) {
            if returnTypeWasOmittedValue {
                return "Function '" + functionName
                    + "' has no return type annotation, so it is treated as 'void', but this code gives back '"
                    + actualTypeName + "'"
            }

            return "Function '" + functionName + "' is declared to return 'void', but this code gives back '"
                + actualTypeName + "'"
        }

        expectedTypeName := TypeText(expectedReturnValueType)
        return "Function '" + functionName + "' should return '" + expectedTypeName
            + "', but this return statement gives back '" + actualTypeName + "'"
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

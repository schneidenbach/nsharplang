namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast

// Native contracts for WHERE THE WALK CURRENTLY IS.
//
// THE SAVE/RESTORE TRANSITIONS ARE THE CONTRACT. Eight ambient values used to live as fields on
// `Analyzer.cs`, mutated in place by seven different idioms; what is observable about them is not
// any single read but the TRANSITIONS — which values an `Enter` changes, which ones it leaves alone,
// and which subset the matching `Exit` puts back. Each contract below drives one boundary and pins
// the whole context on both sides of it.
//
// THREE ASYMMETRIES ARE LOAD-BEARING AND ARE PINNED INDIVIDUALLY. (1) Leaving a FUNCTION DECLARATION
// sets the return type to `null` rather than restoring the saved one — leaving a declaration leaves
// "inside a function" entirely. (2) A NESTED BODY zeroes the control-flow family on entry and
// restores all eight on exit, because a `return` there exits the nested body rather than any
// enclosing `finally`, and `break`/`continue` cannot reach an enclosing method's loop. (3) A SWITCH
// moves the BREAK target only — `continue` still belongs to the enclosing loop, and a switch does
// not make either legal where it was not.
//
// THE FRAME IS THE CALLER'S. Every `Enter` hands its snapshot BACK rather than pushing it onto a
// stack inside the context. Six of the seven C# idioms restore on the straight line and are skipped
// when the walk throws; an internal stack would silently make them exception-safe and would restore
// the WRONG frame after a throw. The contracts drive `Enter`/`Exit` in the caller's order, which is
// the only order the analyzer uses.
//
// THE CORPUS DOES NOT REACH THE DIAGNOSTICS. `break`/`continue` outside a loop, all three NL319
// shapes and all four return-value-mismatch wordings are compile errors, so a corpus of COMPILING
// sources fires none of them. They exist here and in the fixtures.

class AmbientHarness {
    Context: AnalyzerAmbientContext
    Errors: List<CompilerError>

    constructor(context: AnalyzerAmbientContext, errors: List<CompilerError>) {
        Context = context
        Errors = errors
    }
}

func AmbientPath(): string {
    return Path.GetFullPath("ambient-context-contract.nl")
}

func AmbientHarnessWith(sourceText: string?): AmbientHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(AmbientPath(), sourceText)
    spans := new AnalyzerDiagnosticSpans(diagnostics)
    return new AmbientHarness(new AnalyzerAmbientContext(diagnostics, spans), errors)
}

func AmbientDefault(): AmbientHarness {
    return AmbientHarnessWith(null)
}

// The whole context as one comparable line, so a transition is pinned as a single assertion rather
// than as eight that can drift apart.
func AmbientState(context: AnalyzerAmbientContext): string {
    returnTypeText := "<null>"
    returnType := context.CurrentReturnType
    if returnType != null {
        boxed := returnType as object
        rendered := boxed.ToString()
        if rendered != null {
            returnTypeText = rendered
        }
    }

    functionText := "<null>"
    declaration := context.CurrentFunction
    if declaration != null {
        functionText = declaration.Name
    }

    return returnTypeText
        + "|" + functionText
        + "|" + AmbientFlag(context.CurrentFunctionReturnTypeWasOmitted)
        + "|" + AmbientFlag(context.CurrentFunctionIsAsync)
        + "|" + AmbientFlag(context.InLoop)
        + "|" + context.FinallyDepth.ToString()
        + "|" + context.BreakTargetFinallyDepth.ToString()
        + "|" + context.ContinueTargetFinallyDepth.ToString()
}

func AmbientFlag(value: bool): string {
    if value {
        return "1"
    }

    return "0"
}

func AmbientFunction(name: string, returnType: TypeReference?, modifiers: Modifiers): FunctionDeclaration {
    return new FunctionDeclaration(
        name,
        new List<Parameter>(),
        returnType,
        null,
        null,
        null,
        null,
        modifiers,
        new List<AttributeNode>(),
        false,
        null,
        false,
        false,
        7,
        1)
}

func AmbientIntType(): TypeReference {
    return new SimpleTypeReference("int", 7, 6)
}

func AmbientReturn(value: Expression?): ReturnStatement {
    return new ReturnStatement(value, 9, 5)
}

// ---------------------------------------------------------------------------------------------
// THE RESET
// ---------------------------------------------------------------------------------------------

test "A FRESH CONTEXT IS OUTSIDE EVERY FUNCTION, LOOP AND FINALLY" {
    harness := AmbientDefault()

    assert harness.Context.CurrentReturnType == null
    assert harness.Context.CurrentFunction == null
    assert harness.Context.CurrentFunctionReturnTypeWasOmitted == false
    assert harness.Context.CurrentFunctionIsAsync == false
    assert harness.Context.InLoop == false
    assert harness.Context.FinallyDepth == 0
    assert harness.Context.ReturnWouldLeaveFinally == false
}

test "BeginAnalysis PUTS EVERY VALUE BACK, WHATEVER THE PREVIOUS FILE LEFT BEHIND" {
    // The analyzer is reused across files. A file that threw mid-walk leaves the context mutated;
    // the next file must not inherit it.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.Async), BuiltInTypes.Int)
    harness.Context.EnterLoop()
    harness.Context.EnterFinally()

    harness.Context.BeginAnalysis()

    assert AmbientState(harness.Context) == "<null>|<null>|0|0|0|0|0|0"
}

// ---------------------------------------------------------------------------------------------
// THE FUNCTION-DECLARATION BOUNDARY
// ---------------------------------------------------------------------------------------------

test "ENTERING A DECLARATION SETS THE WHOLE FUNCTION FAMILY AND TOUCHES NOTHING ELSE" {
    harness := AmbientDefault()
    harness.Context.EnterFinally()

    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    assert AmbientState(harness.Context) == "int|f|0|0|0|1|0|0"
}

test "AN OMITTED RETURN TYPE IS RECORDED FROM THE DECLARATION, NOT FROM THE RESOLVED TYPE" {
    // The resolved type is `void` either way; only the DECLARATION says whether the author wrote it.
    harness := AmbientDefault()

    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", null, Modifiers.None), BuiltInTypes.Void)

    assert harness.Context.CurrentFunctionReturnTypeWasOmitted == true
}

test "async IS READ OFF THE DECLARATION'S MODIFIERS" {
    harness := AmbientDefault()

    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.Async), BuiltInTypes.Int)

    assert harness.Context.CurrentFunctionIsAsync == true
    assert harness.Context.CurrentFunctionDeclaresAsync == true
    assert harness.Context.CurrentFunctionDeclaresGenerator == false
}

test "generator IS A SEPARATE MODIFIER QUESTION FROM async" {
    harness := AmbientDefault()

    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.Generator), BuiltInTypes.Int)

    assert harness.Context.CurrentFunctionDeclaresGenerator == true
    assert harness.Context.CurrentFunctionDeclaresAsync == false
    assert harness.Context.CurrentFunctionIsAsync == false
}

test "LEAVING A DECLARATION CLEARS THE RETURN TYPE RATHER THAN RESTORING IT" {
    // THE ASYMMETRY. Leaving a declaration leaves "inside a function" entirely, so a stray `return`
    // between declarations is told there is no function to return from — even though the other three
    // function values ARE restored.
    harness := AmbientDefault()
    outer := harness.Context.EnterFunctionDeclaration(AmbientFunction("outer", AmbientIntType(), Modifiers.Async), BuiltInTypes.Int)
    inner := harness.Context.EnterFunctionDeclaration(AmbientFunction("inner", null, Modifiers.None), BuiltInTypes.Void)

    harness.Context.ExitFunctionDeclaration(inner)

    assert harness.Context.CurrentReturnType == null
    assert harness.Context.CurrentFunction != null
    assert AmbientState(harness.Context) == "<null>|outer|0|1|0|0|0|0"

    harness.Context.ExitFunctionDeclaration(outer)
    assert AmbientState(harness.Context) == "<null>|<null>|0|0|0|0|0|0"
}

// ---------------------------------------------------------------------------------------------
// THE ACCESSOR BOUNDARY
// ---------------------------------------------------------------------------------------------

test "AN ACCESSOR CHANGES WHAT A return MUST PRODUCE AND NOTHING ELSE" {
    // A property getter inside a class still reports diagnostics that NAME the enclosing function
    // context, so the accessor must not clear it.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("Owner", null, Modifiers.None), BuiltInTypes.Void)

    saved := harness.Context.EnterAccessorReturnType(BuiltInTypes.Int)

    assert AmbientState(harness.Context) == "int|Owner|1|0|0|0|0|0"

    harness.Context.ExitAccessorReturnType(saved)
    assert AmbientState(harness.Context) == "void|Owner|1|0|0|0|0|0"
}

test "A SETTER'S void RETURN TYPE RESTORES TO WHATEVER THE GETTER'S LEFT" {
    harness := AmbientDefault()
    getterSaved := harness.Context.EnterAccessorReturnType(BuiltInTypes.Int)
    setterSaved := harness.Context.EnterAccessorReturnType(BuiltInTypes.Void)

    assert BuiltInTypes.Is(harness.Context.CurrentReturnType, BuiltInTypes.Void)

    harness.Context.ExitAccessorReturnType(setterSaved)
    assert BuiltInTypes.Is(harness.Context.CurrentReturnType, BuiltInTypes.Int)

    harness.Context.ExitAccessorReturnType(getterSaved)
    assert harness.Context.CurrentReturnType == null
}

// ---------------------------------------------------------------------------------------------
// THE NESTED-BODY BOUNDARY
// ---------------------------------------------------------------------------------------------

test "A NESTED BODY ZEROES THE WHOLE CONTROL-FLOW FAMILY" {
    // A local function declared inside a loop inside a finally starts clean: its `return` exits
    // ITSELF, and its `break` has no loop to reach.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("outer", AmbientIntType(), Modifiers.Async), BuiltInTypes.Int)
    harness.Context.EnterFinally()
    harness.Context.EnterLoop()

    harness.Context.EnterNestedBody(AmbientFunction("local", null, Modifiers.None), BuiltInTypes.Void)

    assert AmbientState(harness.Context) == "void|local|1|0|0|0|0|0"
    assert harness.Context.ReturnWouldLeaveFinally == false
}

test "A NESTED BODY RESTORES ALL EIGHT VALUES" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("outer", AmbientIntType(), Modifiers.Async), BuiltInTypes.Int)
    harness.Context.EnterFinally()
    harness.Context.EnterLoop()
    before := AmbientState(harness.Context)

    frame := harness.Context.EnterNestedBody(AmbientFunction("local", null, Modifiers.None), BuiltInTypes.Void)
    harness.Context.EnterLoop()
    harness.Context.EnterFinally()
    harness.Context.ExitNestedBody(frame)

    assert AmbientState(harness.Context) == before
    assert before == "int|outer|0|1|1|1|1|1"
}

test "A LAMBDA HAS NO DECLARATION TO NAME AND IS NEVER async OR OMITTED" {
    // `EnterNestedBody(null, ...)` is the lambda spelling: the diagnostics fall back to "this
    // function", and both declaration-derived flags read false.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("outer", null, Modifiers.Async), BuiltInTypes.Void)

    harness.Context.EnterNestedBody(null, BuiltInTypes.Unknown)

    assert harness.Context.CurrentFunction == null
    assert harness.Context.CurrentFunctionReturnTypeWasOmitted == false
    assert harness.Context.CurrentFunctionIsAsync == false
    assert harness.Context.CurrentFunctionDeclaresGenerator == false
}

// ---------------------------------------------------------------------------------------------
// THE LOOP, SWITCH AND FINALLY BOUNDARIES
// ---------------------------------------------------------------------------------------------

test "ENTERING A LOOP OPENS IT AND ANCHORS BOTH BRANCH TARGETS AT THE CURRENT DEPTH" {
    harness := AmbientDefault()
    harness.Context.EnterFinally()
    harness.Context.EnterFinally()

    harness.Context.EnterLoop()

    assert harness.Context.InLoop == true
    assert AmbientState(harness.Context) == "<null>|<null>|0|0|1|2|2|2"
}

test "LEAVING A LOOP RESTORES THE FLAG AND BOTH TARGETS BUT NEVER THE FINALLY DEPTH" {
    harness := AmbientDefault()
    outer := harness.Context.EnterLoop()
    harness.Context.EnterFinally()
    inner := harness.Context.EnterLoop()

    assert AmbientState(harness.Context) == "<null>|<null>|0|0|1|1|1|1"

    harness.Context.ExitLoop(inner)
    assert AmbientState(harness.Context) == "<null>|<null>|0|0|1|1|0|0"

    harness.Context.ExitLoop(outer)
    assert harness.Context.InLoop == false
    assert harness.Context.FinallyDepth == 1
}

test "A SWITCH MOVES THE BREAK TARGET AND LEAVES continue WITH THE ENCLOSING LOOP" {
    // A `break` in a case body targets the switch; a `continue` still targets the loop around it.
    // Inside a `finally` opened by the loop body, that difference is the whole diagnostic.
    harness := AmbientDefault()
    harness.Context.EnterLoop()
    harness.Context.EnterFinally()

    saved := harness.Context.EnterSwitch()
    harness.Context.ReportBreakIfNeeded(9, 5)
    harness.Context.ReportContinueIfNeeded(10, 5)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ControlTransferOutOfFinally
    assert harness.Errors[0].Line == 10

    harness.Context.ExitSwitch(saved)
    assert harness.Context.InLoop == true
}

test "A SWITCH DOES NOT MAKE break LEGAL WHERE THERE IS NO LOOP" {
    harness := AmbientDefault()

    harness.Context.EnterSwitch()
    harness.Context.ReportBreakIfNeeded(9, 5)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
}

test "FINALLY DEPTH IS A COUNTER BECAUSE FINALLYS NEST" {
    harness := AmbientDefault()

    harness.Context.EnterFinally()
    harness.Context.EnterFinally()
    assert harness.Context.FinallyDepth == 2
    assert harness.Context.ReturnWouldLeaveFinally == true

    harness.Context.ExitFinally()
    assert harness.Context.FinallyDepth == 1

    harness.Context.ExitFinally()
    assert harness.Context.FinallyDepth == 0
    assert harness.Context.ReturnWouldLeaveFinally == false
}

// ---------------------------------------------------------------------------------------------
// NL319 AND THE LOOP-LEGALITY REPORTS
// ---------------------------------------------------------------------------------------------

test "break OUTSIDE A LOOP IS TOLD THERE IS NO LOOP, NOT TOLD ABOUT HANDLERS" {
    harness := AmbientDefault()
    harness.Context.EnterFinally()

    harness.Context.ReportBreakIfNeeded(9, 5)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert harness.Errors[0].Message == "'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here"
    assert harness.Errors[0].Suggestion == "Move this `break` inside a loop, or remove it if there is no loop to exit."
    assert harness.Errors[0].Line == 9
    assert harness.Errors[0].Column == 5
    assert harness.Errors[0].Length == 5
}

test "continue OUTSIDE A LOOP HAS ITS OWN WORDING AND ITS OWN KEYWORD LENGTH" {
    harness := AmbientDefault()

    harness.Context.ReportContinueIfNeeded(9, 5)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here"
    assert harness.Errors[0].Suggestion == "Move this `continue` inside a loop, or remove it if there is no loop to continue."
    assert harness.Errors[0].Length == 8
}

test "A break INSIDE ITS OWN LOOP'S FINALLY IS SILENT" {
    // The loop was opened INSIDE the finally, so breaking out of it does not leave the handler.
    harness := AmbientDefault()
    harness.Context.EnterFinally()
    harness.Context.EnterLoop()

    harness.Context.ReportBreakIfNeeded(9, 5)

    assert harness.Errors.Count == 0
}

test "A break THAT WOULD LEAVE A FINALLY IS NL319" {
    harness := AmbientDefault()
    harness.Context.EnterLoop()
    harness.Context.EnterFinally()

    harness.Context.ReportBreakIfNeeded(9, 5)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ControlTransferOutOfFinally
    assert harness.Errors[0].Message == "Control cannot leave a 'finally' block with 'break'"
    assert harness.Errors[0].Suggestion == "Move the `break` outside the `finally` block."
    assert harness.Errors[0].Length == 5
}

test "A continue THAT WOULD LEAVE A FINALLY IS NL319 WITH ITS OWN KEYWORD" {
    harness := AmbientDefault()
    harness.Context.EnterLoop()
    harness.Context.EnterFinally()

    harness.Context.ReportContinueIfNeeded(9, 5)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Control cannot leave a 'finally' block with 'continue'"
    assert harness.Errors[0].Length == 8
}

test "A return AT ANY DEPTH AT ALL LEAVES EVERY HANDLER IT IS INSIDE" {
    harness := AmbientDefault()
    harness.Context.EnterFinally()

    harness.Context.ReportReturnOutOfFinallyIfNeeded(9, 5)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Control cannot leave a 'finally' block with 'return'"
    assert harness.Errors[0].Length == 6
}

test "A return OUTSIDE EVERY FINALLY IS SILENT" {
    harness := AmbientDefault()

    harness.Context.ReportReturnOutOfFinallyIfNeeded(9, 5)

    assert harness.Errors.Count == 0
}

test "NL319 TAKES THE RICH SHAPE WHEN THE FILE HAS A SNIPPET" {
    harness := AmbientHarnessWith("func f() {\n    try {\n    } finally {\n        return\n    }\n}\n")
    harness.Context.EnterFinally()

    harness.Context.ReportReturnOutOfFinallyIfNeeded(4, 9)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ControlTransferOutOfFinally
    assert harness.Errors[0].DocsUrl == "https://docs.n-sharp.dev/errors/NL319"
    assert harness.Errors[0].HumanExplanation != null
    assert harness.Errors[0].FileName == AmbientPath()
}

test "THE RICH NL319 NAMES WHAT THE TRANSFER WOULD REACH" {
    harness := AmbientHarnessWith("func f() {\n    try {\n    } finally {\n        return\n    }\n}\n")
    harness.Context.EnterFinally()
    harness.Context.EnterLoop()
    harness.Context.EnterFinally()

    harness.Context.ReportReturnOutOfFinallyIfNeeded(4, 9)
    harness.Context.ReportBreakIfNeeded(4, 9)

    returnHint := harness.Errors[0].ContextualHint
    breakHint := harness.Errors[1].ContextualHint
    assert returnHint != null
    assert breakHint != null
    assert returnHint.Contains("the function")
    assert breakHint.Contains("a loop outside the `finally`")
}

// ---------------------------------------------------------------------------------------------
// THE RETURN-VALUE MISMATCH SHAPES
// ---------------------------------------------------------------------------------------------

test "A MISMATCH IN A TYPED FUNCTION NAMES BOTH TYPES AND THE FUNCTION" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    harness.Context.ReportReturnValueMismatch(AmbientReturn(null), BuiltInTypes.String, BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message == "Function 'f' should return 'int', but this return statement gives back 'string'"
}

test "A MISMATCH IN A DECLARED-void FUNCTION SAYS SO" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", new SimpleTypeReference("void", 7, 6), Modifiers.None), BuiltInTypes.Void)

    harness.Context.ReportReturnValueMismatch(AmbientReturn(null), BuiltInTypes.Int, BuiltInTypes.Void)

    assert harness.Errors[0].Message == "Function 'f' is declared to return 'void', but this code gives back 'int'"
}

test "A MISMATCH IN AN OMITTED-RETURN-TYPE FUNCTION ASKS FOR THE ANNOTATION" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", null, Modifiers.None), BuiltInTypes.Void)

    harness.Context.ReportReturnValueMismatch(AmbientReturn(null), BuiltInTypes.Int, BuiltInTypes.Void)

    assert harness.Errors[0].Message == "Function 'f' has no return type annotation, so it is treated as 'void', but this code gives back 'int'"
}

test "A LAMBDA'S MISMATCH CALLS THE FUNCTION 'this function'" {
    harness := AmbientDefault()
    harness.Context.EnterNestedBody(null, BuiltInTypes.Int)

    harness.Context.ReportReturnValueMismatch(AmbientReturn(null), BuiltInTypes.String, BuiltInTypes.Int)

    assert harness.Errors[0].Message == "Function 'this function' should return 'int', but this return statement gives back 'string'"
}

test "THE DETAIL-ONLY MISMATCH REPORTS AT THE return KEYWORD" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    harness.Context.ReportReturnValueMismatch(AmbientReturn(null), BuiltInTypes.String, BuiltInTypes.Int)

    assert harness.Errors[0].Line == 9
    assert harness.Errors[0].Column == 5
}

test "WITH A SNIPPET THE MISMATCH TAKES THE RICH ReturnTypeMismatch SHAPE" {
    harness := AmbientHarnessWith("func f(): int {\n\n\n\n\n\n\n\n    return \"x\"\n}\n")
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    harness.Context.ReportReturnValueMismatch(AmbientReturn(null), BuiltInTypes.String, BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].ActualType == "string"
    assert harness.Errors[0].ExpectedType == "int"
    assert harness.Errors[0].FileName == AmbientPath()
}

test "AN OMITTED RETURN TYPE SQUIGGLES THE FUNCTION'S NAME, NOT THE RETURNED EXPRESSION" {
    // The fix goes on the declaration, so the underline goes there too — a return three lines away
    // reports on line 7, where `f` is.
    harness := AmbientHarnessWith("func f() {\n\n\n\n\n\nfunc f() {\n\n    return 1\n}\n")
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", null, Modifiers.None), BuiltInTypes.Void)

    harness.Context.ReportReturnValueMismatch(AmbientReturn(new IdentifierExpression("x", 9, 12)), BuiltInTypes.Int, BuiltInTypes.Void)

    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 6
    assert harness.Errors[0].Length == 1
}

test "A WRITTEN RETURN TYPE SQUIGGLES THE RETURNED EXPRESSION" {
    harness := AmbientHarnessWith("func f(): int {\n\n\n\n\n\n\n\n    return x\n}\n")
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    harness.Context.ReportReturnValueMismatch(AmbientReturn(new IdentifierExpression("x", 9, 12)), BuiltInTypes.String, BuiltInTypes.Int)

    assert harness.Errors[0].Line == 9
    assert harness.Errors[0].Column == 12
    assert harness.Errors[0].Length == 1
}

test "AN EXPRESSION BODY THAT GIVES BACK A VALUE FROM A void FUNCTION REPORTS THE void PAIR" {
    harness := AmbientDefault()
    declaration := AmbientFunction("f", null, Modifiers.None)
    harness.Context.EnterFunctionDeclaration(declaration, BuiltInTypes.Void)

    harness.Context.ReportExpressionBodyReturn(declaration, BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message == "Function 'f' has no return type annotation, so it is treated as 'void', but this code gives back 'int'"
}

test "AN EXPRESSION BODY WITH A WRITTEN void SAYS SO INSTEAD" {
    harness := AmbientDefault()
    declaration := AmbientFunction("f", new SimpleTypeReference("void", 7, 6), Modifiers.None)
    harness.Context.EnterFunctionDeclaration(declaration, BuiltInTypes.Void)

    harness.Context.ReportExpressionBodyReturn(declaration, BuiltInTypes.Int)

    assert harness.Errors[0].Message == "Function 'f' is declared to return 'void', but this code gives back 'int'"
}

test "THE EXPRESSION BODY'S TWO PATHS NAME THE FUNCTION DIFFERENTLY, AND THAT IS INHERITED" {
    // AN ASYMMETRY CARRIED OVER VERBATIM. The RICH shape names the declaration it was PASSED; the
    // detail-only fallback shares the `return`-statement wording, which names the AMBIENT function.
    // The single production caller passes the function it has just entered, so the two always agree
    // there — but the two paths do not ask the same question, and the contract says so rather than
    // pretending they do.
    rich := AmbientHarnessWith("func f() {\n\n\n\n\n\nfunc inner() = 1\n}\n")
    rich.Context.EnterFunctionDeclaration(AmbientFunction("outer", null, Modifiers.None), BuiltInTypes.Void)
    rich.Context.ReportExpressionBodyReturn(AmbientFunction("inner", null, Modifiers.None), BuiltInTypes.Int)

    assert rich.Errors[0].Message == "Function 'inner' returns int but has no return type"

    detail := AmbientDefault()
    detail.Context.EnterFunctionDeclaration(AmbientFunction("outer", null, Modifiers.None), BuiltInTypes.Void)
    detail.Context.ReportExpressionBodyReturn(AmbientFunction("inner", null, Modifiers.None), BuiltInTypes.Int)

    assert detail.Errors[0].Message == "Function 'outer' has no return type annotation, so it is treated as 'void', but this code gives back 'int'"
}

test "THE EXPRESSION-BODY FALLBACK SPAN IS THE DECLARATION'S OWN POSITION" {
    // No expression body and a written return type: the span is the declaration position with a
    // length of one, which still puts a caret somewhere real.
    harness := AmbientDefault()
    declaration := AmbientFunction("f", new SimpleTypeReference("void", 7, 6), Modifiers.None)
    harness.Context.EnterFunctionDeclaration(declaration, BuiltInTypes.Void)

    harness.Context.ReportExpressionBodyReturn(declaration, BuiltInTypes.Int)

    assert harness.Errors[0].Line == 7
    assert harness.Errors[0].Column == 1
    assert harness.Errors[0].Length == 1
}

test "THE MISMATCH WORDING IS AVAILABLE WITHOUT REPORTING ANYTHING" {
    // The detail-only wording is a pure function of the context, and the return arm's fallback path
    // reads it directly.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    message := harness.Context.FormatReturnValueMismatchMessage(BuiltInTypes.String, BuiltInTypes.Int)

    assert message == "Function 'f' should return 'int', but this return statement gives back 'string'"
    assert harness.Errors.Count == 0
}

// ---------------------------------------------------------------------------------------------
// THE FRAME ITSELF
// ---------------------------------------------------------------------------------------------

test "A SNAPSHOT IS A VALUE, NOT A VIEW" {
    // The frame the caller holds must not track later mutations, or an `Exit` would restore the
    // state it was supposed to undo.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    frame := harness.Context.Snapshot()
    harness.Context.EnterLoop()
    harness.Context.EnterFinally()

    assert frame.InLoop == false
    assert frame.FinallyDepth == 0
    assert frame.Function != null
    assert BuiltInTypes.Is(frame.ReturnType, BuiltInTypes.Int)
}

test "TWO NESTED FRAMES ARE INDEPENDENT OBJECTS" {
    // Each `Enter` hands back its OWN snapshot; nothing is shared, so an inner `Exit` cannot damage
    // an outer frame the caller is still holding.
    harness := AmbientDefault()
    outer := harness.Context.EnterLoop()
    harness.Context.EnterFinally()
    inner := harness.Context.EnterLoop()

    harness.Context.ExitLoop(inner)

    assert outer.InLoop == false
    assert inner.InLoop == true
    assert outer.FinallyDepth == 0
    assert inner.FinallyDepth == 1
}

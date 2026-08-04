namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
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
    Assignability: AnalyzerAssignability

    constructor(
        context: AnalyzerAmbientContext,
        errors: List<CompilerError>,
        assignability: AnalyzerAssignability) {
        Context = context
        Errors = errors
        Assignability = assignability
    }
}

// One replayed step of the `return` walk, with the whole target-typing slot and the error count
// pinned AS THE STEP WAS HANDED OUT. The slot is the point: a `return` opens it before asking for the
// value and closes it the instant the answer arrives, and no other step may see it open.
class AmbientStep {
    Kind: int
    Node: Expression?
    Text: string?
    ExpectedAtStep: string
    ErrorsBefore: int

    constructor(kind: int, node: Expression?, text: string?, expectedAtStep: string, errorsBefore: int) {
        Kind = kind
        Node = node
        Text = text
        ExpectedAtStep = expectedAtStep
        ErrorsBefore = errorsBefore
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
    return new AmbientHarness(
        new AnalyzerAmbientContext(diagnostics, spans),
        errors,
        AmbientAssignability(provider, diagnostics))
}

// The assignability oracle the `return` walk is HANDED at `BeginReturn` — built here exactly as
// `Analyzer.cs` builds the instance it passes, and deliberately NOT held by the context.
func AmbientAssignability(
    provider: AnalyzerProjectSourceProvider,
    diagnostics: AnalyzerDiagnosticSink): AnalyzerAssignability {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        diagnostics,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        model,
        new BindingMap())
    resolver.BeginAnalysis(AmbientPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    return new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
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

func AmbientValue(): Expression {
    return new IntLiteralExpression("1", 9, 12)
}

// A one-argument type list, built by `Add` rather than by a collection initializer: an initializer
// inside a `test` declaration declines at `parse.test`.
func AmbientTypeArgs(argument: TypeInfo): List<TypeInfo> {
    arguments := new List<TypeInfo>()
    arguments.Add(argument)
    return arguments
}

func AmbientTaskOf(argument: TypeInfo): TypeInfo {
    return new GenericTypeInfo("Task", AmbientTypeArgs(argument))
}

func AmbientRowType(): SoaRowTypeInfo {
    columns := new List<SoaColumnInfo>()
    return new SoaRowTypeInfo(new SoaRecordDeclarationInfo("Particle", columns, 1, 1))
}

// The target-typing slot as one comparable token, so a transition is pinned as a single assertion.
func AmbientExpected(context: AnalyzerAmbientContext): string {
    expected := context.CurrentExpectedType
    if expected != null {
        boxed := expected as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }
    }

    return "<null>"
}

// ── the `return` driver, exactly as `Analyzer.cs` writes it ────────────────
//
// Answers every kind-1 step with `answer` and records what was asked, INCLUDING the target-typing
// slot as it stood when the step was handed out. Kind 3's boolean is answered `escaped` so the
// contract can prove the walk ignores it.
func AmbientRunReturn(
    harness: AmbientHarness,
    statement: ReturnStatement,
    answer: TypeInfo?,
    escaped: bool): List<AmbientStep> {
    steps := new List<AmbientStep>()
    state := harness.Context.BeginReturn(statement, harness.Assignability)
    step := harness.Context.NextStep(state)
    while step != null {
        steps.Add(new AmbientStep(
            step.Kind,
            step.Node,
            step.Text,
            AmbientExpected(harness.Context),
            harness.Errors.Count))

        supplied: TypeInfo? = null
        if step.Kind == 1 {
            supplied = answer
        }

        harness.Context.Supply(state, supplied, escaped)
        step = harness.Context.NextStep(state)
    }

    return steps
}

func AmbientKinds(steps: List<AmbientStep>): string {
    rendered := ""
    index := 0
    while index < steps.Count {
        rendered = rendered + steps[index].Kind.ToString()
        index = index + 1
    }

    return rendered
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

// ---------------------------------------------------------------------------------------------
// THE EXPECTED-TYPE FAMILY — THE THIRD AMBIENT FAMILY
// ---------------------------------------------------------------------------------------------

test "A FRESH CONTEXT IS ASKED FOR NOTHING" {
    harness := AmbientDefault()

    assert harness.Context.CurrentExpectedType == null
    assert AmbientExpected(harness.Context) == "<null>"
}

test "ENTERING A TARGET TYPE SETS THE SLOT AND HANDS BACK WHAT WAS THERE" {
    harness := AmbientDefault()

    saved := harness.Context.EnterExpectedType(BuiltInTypes.Int)

    assert saved == null
    assert AmbientExpected(harness.Context) == "int"
}

test "LEAVING A TARGET TYPE PUTS BACK EXACTLY THE FRAME THE CALLER HOLDS" {
    harness := AmbientDefault()
    outer := harness.Context.EnterExpectedType(BuiltInTypes.String)
    inner := harness.Context.EnterExpectedType(BuiltInTypes.Int)

    harness.Context.ExitExpectedType(inner)
    assert AmbientExpected(harness.Context) == "string"

    harness.Context.ExitExpectedType(outer)
    assert AmbientExpected(harness.Context) == "<null>"
}

test "ENTERING WITH NULL IS A REAL SET, NOT A NO-OP" {
    // `AnalyzeExpressionWithoutExpectedType` DELIBERATELY nulls the slot: a match value, and the
    // `AnalyzeExpression` a discard walk performs, must not inherit the surrounding target type.
    harness := AmbientDefault()
    harness.Context.EnterExpectedType(BuiltInTypes.Int)

    saved := harness.Context.EnterExpectedType(null)

    assert AmbientExpected(harness.Context) == "<null>"
    assert BuiltInTypes.Is(saved, BuiltInTypes.Int)
}

test "THE IF-PROVIDED FORM LEAVES THE SLOT ALONE WHEN THERE IS NOTHING TO ASK FOR" {
    // THE DISTINCTION IS SEMANTIC, NOT COSMETIC. A tuple element with no matching element in the
    // target, or a constructor argument that is not the SoA count, keeps whatever target typing
    // already surrounds the walk — nulling it would change what `default`, `new()`, a lambda and a
    // negative integer literal resolve to inside it.
    harness := AmbientDefault()
    harness.Context.EnterExpectedType(BuiltInTypes.Int)

    saved := harness.Context.EnterExpectedTypeIfProvided(null)

    assert AmbientExpected(harness.Context) == "int"
    assert BuiltInTypes.Is(saved, BuiltInTypes.Int)
}

test "THE IF-PROVIDED FORM SETS THE SLOT WHEN THERE IS" {
    harness := AmbientDefault()
    harness.Context.EnterExpectedType(BuiltInTypes.String)

    saved := harness.Context.EnterExpectedTypeIfProvided(BuiltInTypes.Int)

    assert AmbientExpected(harness.Context) == "int"
    assert BuiltInTypes.Is(saved, BuiltInTypes.String)
}

test "THE IF-PROVIDED FORM'S FRAME ROUND-TRIPS EVEN WHEN NOTHING WAS SET" {
    // The caller restores unconditionally — `AnalyzeIndexAccess` writes the restore outside the `if`
    // — so the saved value must be usable whether or not the set happened.
    harness := AmbientDefault()
    harness.Context.EnterExpectedType(BuiltInTypes.String)

    saved := harness.Context.EnterExpectedTypeIfProvided(null)
    harness.Context.ExitExpectedType(saved)

    assert AmbientExpected(harness.Context) == "string"
}

test "BeginAnalysis DELIBERATELY LEAVES THE TARGET TYPE ALONE" {
    // `Analyzer.cs` reset the other eight fields in its `Analyze` prologue and never wrote this one
    // outside a matched save/restore pair. Resetting it here would be a write the family never made.
    harness := AmbientDefault()
    harness.Context.EnterExpectedType(BuiltInTypes.Int)

    harness.Context.BeginAnalysis()

    assert AmbientExpected(harness.Context) == "int"
}

test "THE TARGET TYPE IS NOT PART OF ANY OTHER BOUNDARY'S FRAME" {
    // Not the function frame, not the nested-body frame, not the loop frame: no C# idiom ever saved
    // the target type alongside the other eight, and a nested body inherits whatever is being asked
    // for at its declaration site.
    harness := AmbientDefault()
    harness.Context.EnterExpectedType(BuiltInTypes.Int)

    frame := harness.Context.EnterNestedBody(null, BuiltInTypes.String)
    assert AmbientExpected(harness.Context) == "int"

    harness.Context.ExitNestedBody(frame)
    assert AmbientExpected(harness.Context) == "int"
}

// ---------------------------------------------------------------------------------------------
// THE return WALK — THE PROTOCOL
// ---------------------------------------------------------------------------------------------

test "A return WITH NO FUNCTION AT ALL ASKS FOR NOTHING AND IS TOLD ONLY THAT" {
    harness := AmbientDefault()

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert steps.Count == 0
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert harness.Errors[0].Message == "'return' can only be used inside a function — there's no function to return from here"
    assert harness.Errors[0].Length == 6
    assert harness.Errors[0].Line == 9
    assert harness.Errors[0].Column == 5
}

test "A return WITH NO FUNCTION IS NEVER ALSO TOLD IT LEAVES A finally" {
    // The C# arm returned immediately. The two reports are exclusive by control flow, not by rule.
    harness := AmbientDefault()
    harness.Context.EnterFinally()

    AmbientRunReturn(harness, AmbientReturn(null), null, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
}

test "A VALUED return ASKS FOR THE EXPRESSION AND THEN EXACTLY ONE ESCAPE REPORT" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert AmbientKinds(steps) == "13"
    assert steps[0].Text == "returned"
    assert steps[1].Text == "returned"
    assert steps[0].Node != null
    assert steps[1].Node != null
}

test "A ROW-VIEW ANSWER SELECTS THE ROW REPORT INSTEAD OF THE DIRECT-COLUMN ONE" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), AmbientRowType(), false)

    assert AmbientKinds(steps) == "12"
}

test "A BARE return ASKS FOR NOTHING" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", new SimpleTypeReference("void", 7, 6), Modifiers.None), BuiltInTypes.Void)

    steps := AmbientRunReturn(harness, AmbientReturn(null), null, false)

    assert steps.Count == 0
    assert harness.Errors.Count == 0
}

test "THE TARGET TYPE IS OPEN FOR THE EXPRESSION STEP AND CLOSED FOR THE ESCAPE STEP" {
    // THE TRANSITION IS THE CONTRACT. The C# set the slot on the line before `AnalyzeExpression` and
    // restored it on the line after; the walk must open it for kind 1 ONLY.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert steps[0].ExpectedAtStep == "int"
    assert steps[1].ExpectedAtStep == "<null>"
    assert AmbientExpected(harness.Context) == "<null>"
}

test "THE TARGET TYPE PUTS BACK WHATEVER SURROUNDED THE STATEMENT" {
    // A `return` nested inside an already-target-typed walk — a lambda body inside an annotated
    // initializer — must not leave the outer slot cleared.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)
    harness.Context.EnterExpectedType(BuiltInTypes.String)

    AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert AmbientExpected(harness.Context) == "string"
}

test "AN async FUNCTION ASKS THE VALUE FOR THE AWAITED RESULT, NOT THE TASK" {
    harness := AmbientDefault()
    taskOfInt := AmbientTaskOf(BuiltInTypes.Int)
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.Async), taskOfInt)

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert steps[0].ExpectedAtStep == "int"
}

test "A NON-async FUNCTION ASKS FOR THE DECLARED TYPE EVEN WHEN IT IS TASK-LIKE" {
    // The unwrap is gated on the AMBIENT async flag, not on the shape of the type.
    harness := AmbientDefault()
    taskOfInt := AmbientTaskOf(BuiltInTypes.Int)
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), taskOfInt)

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), taskOfInt, false)

    assert steps[0].ExpectedAtStep == "Task<int>"
}

test "THE WALK IGNORES THE DIRECT-COLUMN REPORT'S ANSWER" {
    // Unlike a local declaration, where a fired escape turns the declared type unknown, a `return`
    // called the reporter in statement position and ignored it — so a fired escape suppresses
    // nothing.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.String, true)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
}

test "A NULL ANSWER ON THE EXPRESSION STEP LEAVES THE RETURNED TYPE UNKNOWN" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), null, false)

    assert AmbientKinds(steps) == "13"
    assert harness.Errors.Count == 0
}

test "THE WALK IS FINISHED AFTER ITS LAST STEP AND STAYS FINISHED" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)
    state := harness.Context.BeginReturn(AmbientReturn(AmbientValue()), harness.Assignability)

    harness.Context.NextStep(state)
    harness.Context.Supply(state, BuiltInTypes.Int, false)
    harness.Context.NextStep(state)
    harness.Context.Supply(state, null, false)

    assert harness.Context.NextStep(state) == null
    assert harness.Context.NextStep(state) == null
}

// ---------------------------------------------------------------------------------------------
// THE return WALK — WHAT IT REPORTS
// ---------------------------------------------------------------------------------------------

test "A VALUE THAT DOES NOT FIT IS REPORTED AFTER THE ESCAPE STEP, NOT BEFORE" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.String, false)

    assert steps[1].ErrorsBefore == 0
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Function 'f' should return 'int', but this return statement gives back 'string'"
}

test "A VALUE THAT FITS IS SILENT" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert harness.Errors.Count == 0
}

test "A GENERATOR CANNOT RETURN A VALUE, AND THAT REPORT ENDS THE ARM" {
    // The assignability check never runs after it: a generator's declared type is the SEQUENCE, and
    // comparing the returned value against it would pile a second, wrong diagnostic on the same span.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.Generator), BuiltInTypes.Int)

    AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.String, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidSyntax
    assert harness.Errors[0].Message == "Generator functions cannot return a value"
    assert harness.Errors[0].Suggestion == "Use `yield value` to produce sequence values, or a bare `return`/`yield break` to stop iteration."
}

test "THE GENERATOR REPORT IS SPANNED ON THE RETURNED EXPRESSION, NOT THE KEYWORD" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.Generator), BuiltInTypes.Int)

    AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert harness.Errors[0].Line == 9
    assert harness.Errors[0].Column == 12
}

test "A GENERATOR STILL WALKS ITS VALUE AND STILL RUNS AN ESCAPE REPORT" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.Generator), BuiltInTypes.Int)

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert AmbientKinds(steps) == "13"
}

test "A BARE return IN A TYPED FUNCTION IS NL305 MissingReturn AT THE KEYWORD" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    AmbientRunReturn(harness, AmbientReturn(null), null, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.MissingReturn
    assert harness.Errors[0].Message == "This function should return 'int', but this 'return' doesn't provide a value"
    assert harness.Errors[0].Line == 9
    assert harness.Errors[0].Column == 5
}

test "WITH A SNIPPET THE BARE return TAKES THE RICH MissingReturn SHAPE" {
    harness := AmbientHarnessWith("func f(): int {\n\n\n\n\n\n\n\n    return\n}\n")
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    AmbientRunReturn(harness, AmbientReturn(null), null, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.MissingReturn
    assert harness.Errors[0].ExpectedType == "int"
    assert harness.Errors[0].Length == 6
    assert harness.Errors[0].Message == "Not all code paths return a value of type 'int'"
}

test "A BARE return IN A void FUNCTION IS SILENT" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", new SimpleTypeReference("void", 7, 6), Modifiers.None), BuiltInTypes.Void)

    AmbientRunReturn(harness, AmbientReturn(null), null, false)

    assert harness.Errors.Count == 0
}

test "A BARE return IN AN async FUNCTION RETURNING A UNIT TASK IS SILENT" {
    // `async func f(): void` resolves to `Task`, which owes no value — the same silence as `void`,
    // reached by a DIFFERENT question.
    harness := AmbientDefault()
    unitTask: TypeInfo = new SimpleTypeInfo("Task")
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.Async), unitTask)

    AmbientRunReturn(harness, AmbientReturn(null), null, false)

    assert harness.Errors.Count == 0
}

test "A BARE return IN AN async FUNCTION THAT OWES A RESULT IS NOT SILENT" {
    harness := AmbientDefault()
    taskOfInt := AmbientTaskOf(BuiltInTypes.Int)
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.Async), taskOfInt)

    AmbientRunReturn(harness, AmbientReturn(null), null, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.MissingReturn
}

test "A return INSIDE A finally IS REPORTED BEFORE ITS VALUE IS EVEN ASKED FOR" {
    // The handler violation is about WHERE the statement sits, so it lands before anything the
    // expression can say.
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)
    harness.Context.EnterFinally()

    steps := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.String, false)

    assert steps[0].ErrorsBefore == 1
    assert harness.Errors[0].Code == ErrorCode.ControlTransferOutOfFinally
    assert harness.Errors.Count == 2
    assert harness.Errors[1].Code == ErrorCode.TypeMismatch
}

test "A BARE return INSIDE A finally IS STILL REPORTED FOR THE HANDLER" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", new SimpleTypeReference("void", 7, 6), Modifiers.None), BuiltInTypes.Void)
    harness.Context.EnterFinally()

    AmbientRunReturn(harness, AmbientReturn(null), null, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ControlTransferOutOfFinally
}

test "A return IN A LAMBDA'S BODY IS CHECKED AGAINST THE LAMBDA'S TYPE AND NAMES NO DECLARATION" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)
    harness.Context.EnterNestedBody(null, BuiltInTypes.String)

    AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Function 'this function' should return 'string', but this return statement gives back 'int'"
}

test "AN OMITTED RETURN TYPE MAKES THE VALUED return ASK FOR THE ANNOTATION" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", null, Modifiers.None), BuiltInTypes.Void)

    AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Function 'f' has no return type annotation, so it is treated as 'void', but this code gives back 'int'"
}

test "A VALUE RETURNED FROM A DECLARED-void FUNCTION SAYS SO" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", new SimpleTypeReference("void", 7, 6), Modifiers.None), BuiltInTypes.Void)

    AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Function 'f' is declared to return 'void', but this code gives back 'int'"
}

test "A return STATEMENT DOES NOT DISTURB THE OTHER TWO AMBIENT FAMILIES" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)
    harness.Context.EnterLoop()
    harness.Context.EnterFinally()
    before := AmbientState(harness.Context)

    AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.String, false)

    assert AmbientState(harness.Context) == before
}

test "TWO return STATEMENTS IN A ROW ARE INDEPENDENT WALKS" {
    harness := AmbientDefault()
    harness.Context.EnterFunctionDeclaration(AmbientFunction("f", AmbientIntType(), Modifiers.None), BuiltInTypes.Int)

    first := AmbientRunReturn(harness, AmbientReturn(AmbientValue()), BuiltInTypes.Int, false)
    second := AmbientRunReturn(harness, AmbientReturn(null), null, false)

    // The first fits and is silent; the second is bare in a function that owes an `int`, so the two
    // walks reach DIFFERENT arms from the same context without either one carrying state into the
    // other.
    assert AmbientKinds(first) == "13"
    assert second.Count == 0
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.MissingReturn
    assert AmbientExpected(harness.Context) == "<null>"
}

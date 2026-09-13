namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// ONE STEP A LAMBDA'S ANALYSIS CANNOT TAKE FOR ITSELF, AND EVERYTHING THAT STEP NEEDS.
//
// The walk owns what a LAMBDA MEANS: that its expected type is read through the DELEGATE door rather
// than taken as written, so `Func<int, int>`, a runtime delegate, an expression-tree target and an
// N#-declared generic delegate all name the same signature; that a parameter written WITHOUT a type
// takes its type from that signature POSITIONALLY, and that `var` is the parser's placeholder for
// "untyped" rather than a type a user may write; that a parameter with NEITHER an explicit type NOR
// an inference source is a HARD ERROR reported ONCE per lambda — because letting the unknown type
// flow on emits a delegate with a garbage signature whose invocation corrupts memory at runtime;
// that the scope a lambda opens is a FUNCTION scope; that each parameter is declared at its own
// position when it has one and at the lambda's otherwise; that an EXPRESSION body is analysed under
// the signature's RETURN type and is then measured by both SoA escape rules; that a BLOCK body's
// return type is the signature's regardless of what the block does, and that the block runs inside a
// NESTED-BODY ambient boundary; that a lambda with NEITHER body answers `unknown`; and that the
// expression-tree rules apply to whichever body shape there is, with the block-body report firing
// BEFORE the body is walked and the unsupported-expression report firing only when the body walk and
// both escape rules left the diagnostic count untouched.
//
// What it cannot do is run the analyzer's own expression or statement walk, open or close a scope on
// the analyzer's scope stack, declare a name into that stack, write the semantic model the IDE
// reads, or run the expression-tree VALIDATOR that has not moved yet — so it ASKS: one request at a
// time, each naming a kind and carrying every value the step needs. Nothing here is a policy the
// driver may reinterpret; the driver switches on `Kind`, performs exactly the one operation with
// exactly these operands, and hands the answer back.
//
// The kinds:
//   1  analyse an EXPRESSION under an EXPECTED TYPE — the expression body, measured against the
//      signature's return type. ANSWERS a type, which becomes the lambda's return type and is the
//      operand of both escape rules.
//   2  open a FUNCTION scope on the analyzer's scope stack at `Line` / `Column`. A function scope,
//      not a block scope: a lambda body is a body.
//   3  declare a parameter into that scope under `CarriedType` at `Line` / `Column`.
//   4  record that same parameter in the semantic model the IDE's hover and completion read.
//   5  analyse the BLOCK body — ONE statement, the block itself, which opens its own block scope
//      inside the function scope. `CarriedType` is the ambient NESTED-BODY return type the driver
//      brackets the analysis with; see the note on that bracket below.
//   6  close the scope kind 2 opened.
//
// KINDS 7 AND 8 ARE GONE, AND THAT IS THE MEASUREMENT THE VALIDATOR'S OWN SLICE TOOK. They were
// RELAYS to the expression-tree validator while it was still C#; the validator is now
// `AnalyzerExpressionTreeValidator` and every collaborator it needs — the diagnostic sink, the
// spans, the scope stack, the declaration context, the external metadata probe and the well-known
// types — is N#-owned, so this walk asks it DIRECTLY and the driver never learns it exists. The
// division of labour is unchanged and is still the reason they are two owners: this walk owns WHEN
// the question is asked, the validator owns WHAT the answer is.
//
// THE NESTED-BODY AMBIENT BRACKET IS THE DRIVER'S, DELIBERATELY, AND IT IS THE ARC'S ONE EXCEPTION
// TO THE OWNER-HELD BRACKET. Every other bracket this arc has moved spans a SUSPENSION and therefore
// has to be owner-held. This one spans exactly ONE operation, and the C# it replaces wrote it as a
// `try`/`finally` whose guarantee — the ambient boundary is restored even if the body analysis
// THROWS — an owner-held pair opened before the request and closed on the answer could not keep.
// The kind carries the return type the boundary is entered with, so which boundary and with what is
// still this walk's decision; only the `finally` is the driver's.
class LambdaAnalysisRequest {
    Kind: int
    Node: Expression?
    Body: Statement?
    ExpectedType: TypeInfo?
    CarriedType: TypeInfo
    Name: string?
    Line: int
    Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Node = null
        Body = null
        ExpectedType = null
        CarriedType = carriedType
        Name = null
        Line = 0
        Column = 0
    }
}

// THE LAMBDA WALK'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Phase` is the walk's program counter and `Pending` names the answer it is waiting for. Everything
// else is what the C# member this replaces held in locals. `ExpectedSignature` and
// `TargetsExpressionTree` are computed ONCE at entry, before the scope opens, because both are
// functions of the expected type alone and the C# read them before its first side effect.
class LambdaAnalysisState {
    lambdaValue: LambdaExpression
    parameterTypesValue: List<TypeInfo>

    Lambda: LambdaExpression => lambdaValue
    ParameterTypes: List<TypeInfo> => parameterTypesValue

    ExpectedSignature: FunctionTypeInfo?
    TargetsExpressionTree: bool
    ReportInferenceFailure: bool

    // The parameter-inference failure is reported ONCE PER LAMBDA, not once per parameter: a lambda
    // whose delegate type nothing names has EVERY parameter uninferable, and one sentence about the
    // lambda is the report the user needs.
    ReportedInferenceFailure: bool

    // NL334 is reported once per lambda for the same reason: `async` is written once, and its target
    // is one fact about the whole lambda. NL335 is the mirror — the keyword that is MISSING — and it
    // is one sentence about the lambda too.
    ReportedAsyncTarget: bool
    ReportedMissingAsync: bool

    ParameterIndex: int
    ParameterType: TypeInfo

    Phase: int
    Pending: int

    // The diagnostic count taken BEFORE the expression body is analysed. The unsupported-expression
    // report fires only when the body walk AND both escape rules left it untouched, so it is a
    // measurement of "nothing else already complained" rather than of the body walk alone.
    ErrorsBeforeBody: int

    ReturnType: TypeInfo
    Result: FunctionTypeInfo?

    constructor(lambda: LambdaExpression, reportInferenceFailure: bool) {
        lambdaValue = lambda
        parameterTypesValue = new List<TypeInfo>()
        ExpectedSignature = null
        TargetsExpressionTree = false
        ReportInferenceFailure = reportInferenceFailure
        ReportedInferenceFailure = false
        ReportedAsyncTarget = false
        ReportedMissingAsync = false
        ParameterIndex = 0
        ParameterType = BuiltInTypes.Unknown
        Phase = 0
        Pending = 0
        ErrorsBeforeBody = 0
        ReturnType = BuiltInTypes.Unknown
        Result = null
    }
}

// ONE STEP AN `on` SUBSCRIPTION CANNOT TAKE FOR ITSELF.
//
// The kinds:
//   1  analyse the SUBSCRIPTION TARGET with the bare-event guard OPEN, so the diagnostics this walk
//      writes are the ones the user sees rather than the generic "events need `on`/`off`" report.
//      The driver brackets it in a `try`/`finally` for the same reason kind 5 of the lambda walk is
//      bracketed there: the C# it replaces guarantees the guard is closed even if the analysis
//      throws, and it wrote the guarantee down. ANSWERS the target's type.
//   2  analyse the HANDLER LAMBDA with `ExpectedType` as its expected type and
//      `ReportInferenceFailure` as its inference-failure switch. The driver performs it by
//      re-entering the lambda walk through its own mechanical driver. The answer is deliberately NOT
//      read: the handler is analysed for its diagnostics and for the bindings it records, and an
//      `on` expression's type is the subscription root whatever the handler turns out to be.
class OnSubscriptionRequest {
    Kind: int
    Node: Expression?
    Lambda: LambdaExpression?
    ExpectedType: TypeInfo?
    ReportInferenceFailure: bool

    constructor(kind: int) {
        Kind = kind
        Node = null
        Lambda = null
        ExpectedType = null
        ReportInferenceFailure = true
    }
}

// THE `on` WALK'S WHOLE STATE, SUSPENDED ACROSS THE TARGET'S ANALYSIS.
//
// `Result` is the subscription root from the first turn onward, because EVERY path through this walk
// answers it — the ones that report and the one that succeeds alike. A subscription is what `on`
// evaluates to, and a failed subscription is still a subscription-shaped hole rather than `unknown`;
// typing it otherwise would make the handle a second error at the `off` that consumes it.
class OnSubscriptionState {
    onValue: OnSubscriptionExpression

    On: OnSubscriptionExpression => onValue

    Phase: int
    Pending: int
    TargetType: TypeInfo
    Result: TypeInfo

    // THE PARAMETER IS NOT CALLED `on`, AND THAT IS A LANGUAGE WALL ROUTED AROUND. `on` is a
    // CONTEXTUAL KEYWORD: a statement that begins with it is parsed as a subscription, so
    // `onValue = on` followed by any line at all reads as `on <target> …` and dies on the next `=`.
    // The compiler's own build tolerated it; the FORMATTER's parse did not, which is what found it.
    constructor(subscription: OnSubscriptionExpression, subscriptionType: TypeInfo) {
        onValue = subscription
        Phase = 0
        Pending = 0
        TargetType = BuiltInTypes.Unknown
        Result = subscriptionType
    }
}

// WHAT A LAMBDA MEANS, AND WHAT SUBSCRIBING TO AN EVENT MEANS.
//
// The two live together because `on` is a LAMBDA SITE and nothing else. Its exclusive tail is empty,
// six of its statements are handler analyses, and the only thing it decides that a lambda does not
// is WHICH expected type the handler gets — the event's delegate type when the target really is a
// subscribable event, and none at all on each of the four paths that already reported. Splitting
// them would put that choice one file away from the walk that consumes it.
class AnalyzerLambdaAnalysis {
    diagnostics: AnalyzerDiagnosticSink
    spans: AnalyzerDiagnosticSpans
    declarationContext: AnalyzerDeclarationContext
    typeResolver: AnalyzerTypeResolver
    clrTypeConversion: AnalyzerClrTypeConversion
    assignabilityFacts: AnalyzerAssignabilityFacts
    soaEscape: AnalyzerSoaEscape
    expressionTrees: AnalyzerExpressionTreeValidator

    constructor(diagnosticSink: AnalyzerDiagnosticSink, spansOwner: AnalyzerDiagnosticSpans, declarations: AnalyzerDeclarationContext, resolver: AnalyzerTypeResolver, conversion: AnalyzerClrTypeConversion, facts: AnalyzerAssignabilityFacts, escape: AnalyzerSoaEscape, expressionTreeValidator: AnalyzerExpressionTreeValidator) {
        diagnostics = diagnosticSink
        spans = spansOwner
        declarationContext = declarations
        typeResolver = resolver
        clrTypeConversion = conversion
        assignabilityFacts = facts
        soaEscape = escape
        expressionTrees = expressionTreeValidator
    }

    // THE LAMBDA'S PARAMETER NAMES, which is the whole of what the expression-tree validator needs
    // from the lambda beyond the body itself: a bare identifier inside an expression tree is legal
    // when it is one of these and a captured variable when it is not.
    static func LambdaParameterNames(lambda: LambdaExpression): HashSet<string> {
        names := new HashSet<string>(StringComparer.Ordinal)
        index := 0
        while index < lambda.Parameters.Count {
            names.Add(lambda.Parameters[index].Name)
            index = index + 1
        }

        return names
    }

    // THE LAMBDA'S ENTRY. The expected type is read through the delegate door and the expression-tree
    // question is asked ONCE, both before the scope opens — which is the order `Analyzer.cs` wrote
    // and matters, because resolving a type reference RECORDS it and the recording order is
    // observable in the semantic model the IDE reads.
    func BeginLambda(lambda: LambdaExpression, expectedType: TypeInfo?, reportInferenceFailure: bool, isExpressionTreeTarget: bool): LambdaAnalysisState {
        state := new LambdaAnalysisState(lambda, reportInferenceFailure)
        state.ExpectedSignature = FunctionSignature(expectedType)
        state.TargetsExpressionTree = isExpressionTreeTarget || AnalyzerFunctionTypeFactory.IsExpressionTreeLambdaTargetTypeInfo(expectedType, declarationContext, clrTypeConversion)
        return state
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when the lambda's type is decided.
    func NextLambdaStep(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        while state.Phase != 99 {
            request := AdvanceLambda(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything the walk reads: the expression
    // body's type. The declare, record, scope, statement and report steps answer nothing.
    func SupplyLambdaStep(state: LambdaAnalysisState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending != 1 {
            return
        }

        if answer != null {
            state.ReturnType = answer
        } else {
            state.ReturnType = BuiltInTypes.Unknown
        }
    }

    // ONE TURN OF THE WALK: a request when the next thing to happen is the driver's, otherwise null
    // with the phase moved on.
    func AdvanceLambda(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        phase := state.Phase
        if phase == 0 {
            return OpenLambdaScope(state)
        }

        if phase == 1 {
            return DeclareLambdaParameter(state)
        }

        if phase == 2 {
            return RecordLambdaParameter(state)
        }

        if phase == 3 {
            return CompleteLambdaParameter(state)
        }

        if phase == 4 {
            return EnterLambdaBody(state)
        }

        if phase == 5 {
            return CompleteExpressionBody(state)
        }

        if phase == 6 {
            return EnterBlockBody(state)
        }

        if phase == 7 {
            return CompleteBlockBody(state)
        }

        if phase == 8 {
            return CloseLambdaScope(state)
        }

        return FinishLambda(state)
    }

    // PHASE 0 — THE FUNCTION SCOPE. A lambda's parameters are not visible outside it and its body is
    // a body, so the scope is a FUNCTION scope opened at the LAMBDA's own position.
    func OpenLambdaScope(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        lambda := state.Lambda
        state.Phase = 1
        request := new LambdaAnalysisRequest(2, BuiltInTypes.Unknown)
        request.Line = lambda.Line
        request.Column = lambda.Column
        return request
    }

    // PHASE 1 — ONE PARAMETER'S TYPE, ITS POSITION AND ITS DECLARATION.
    //
    // A parameter is EXPLICITLY typed when it has a type reference that is not the parser's `var`
    // placeholder; it has an INFERENCE SOURCE when the expected signature carries a type at this
    // parameter's index. With neither, the type is `unknown` AND that is an error rather than a
    // silence: a delegate emitted from an unknown parameter type has a garbage signature, and
    // invoking it corrupts memory. The report is made once per lambda and is suppressed entirely on
    // the error-recovery paths that already diagnosed the surrounding statement.
    func DeclareLambdaParameter(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        parameters := state.Lambda.Parameters
        if state.ParameterIndex >= parameters.Count {
            state.Phase = 4
            return null
        }

        parameter := parameters[state.ParameterIndex]
        parameterIndex := state.ParameterTypes.Count
        hasExplicitType := HasExplicitParameterType(parameter)
        signature := state.ExpectedSignature
        hasInferenceSource := false
        if signature != null {
            signatureParameters := signature.ParameterTypes
            if signatureParameters != null && parameterIndex < signatureParameters.Count {
                hasInferenceSource = true
            }
        }

        parameterType: TypeInfo = BuiltInTypes.Unknown
        if hasExplicitType {
            parameterType = typeResolver.ResolveType(parameter.Type)
        } else if hasInferenceSource {
            parameterType = signature.ParameterTypes[parameterIndex]
        }

        state.ParameterType = parameterType
        position := AnalyzerBindingFacts.GetParameterDeclarationPosition(parameter.Line, parameter.Column, state.Lambda.Line, state.Lambda.Column)
        if !hasExplicitType && !hasInferenceSource && state.ReportInferenceFailure && !state.ReportedInferenceFailure {
            diagnostics.Report(ErrorCode.CannotInferType, "I can't figure out the type of lambda parameter '" + parameter.Name + "' — nothing here names the lambda's delegate type", position.Item1, position.Item2, "Give the lambda a typed home (e.g., 'let f: Func<int, int> = " + parameter.Name + " => ...') or pass it directly where a delegate type is expected.", parameter.Name.Length)
            state.ReportedInferenceFailure = true
        }

        state.Phase = 2
        request := new LambdaAnalysisRequest(3, parameterType)
        request.Name = parameter.Name
        request.Line = position.Item1
        request.Column = position.Item2
        return request
    }

    // WHETHER A LAMBDA PARAMETER NAMES ITS OWN TYPE. The parser writes `var` as the placeholder for
    // an untyped parameter, so a `var` annotation is the ABSENCE of a type rather than a type — and
    // the check is on the SIMPLE form only, because a user cannot spell `var` any other way.
    static func HasExplicitParameterType(parameter: Parameter): bool {
        typeReference := parameter.Type
        if typeReference == null {
            return false
        }

        simple := typeReference as SimpleTypeReference
        return simple == null || simple.Name != "var"
    }

    // PHASE 2 — THE SAME PARAMETER, RECORDED FOR THE IDE. It carries the type phase 1 resolved
    // rather than resolving it again, which also keeps the recording side effect to one.
    func RecordLambdaParameter(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        parameter := state.Lambda.Parameters[state.ParameterIndex]
        state.Phase = 3
        request := new LambdaAnalysisRequest(4, state.ParameterType)
        request.Name = parameter.Name
        return request
    }

    // PHASE 3 — THE PARAMETER'S TYPE JOINS THE SIGNATURE. It is appended AFTER both steps because
    // the next parameter's inference index is this list's COUNT, so appending early would shift it.
    func CompleteLambdaParameter(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        state.ParameterTypes.Add(state.ParameterType)
        state.ParameterIndex = state.ParameterIndex + 1
        state.Phase = 1
        return null
    }

    // PHASE 4 — WHICH BODY SHAPE THERE IS.
    //
    // An EXPRESSION body is analysed under the signature's return type and its answer IS the lambda's
    // return type. A BLOCK body's return type is the signature's whatever the block does — a lambda
    // does not infer a block's return type — and the expression-tree block report fires BEFORE the
    // block is walked, so a block lambda in an expression-tree position is told the shape is wrong
    // before it is told anything about its contents. NEITHER body answers `unknown`.
    func EnterLambdaBody(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        lambda := state.Lambda
        if lambda.IsAsync && state.TargetsExpressionTree {
            expressionTrees.ReportAsyncLambdaIfNeeded(lambda)
        }

        ReportAsyncTargetIfNeeded(state)
        expressionBody := lambda.ExpressionBody
        if expressionBody != null {
            state.ErrorsBeforeBody = diagnostics.ErrorCount
            state.Phase = 5
            state.Pending = 1
            request := new LambdaAnalysisRequest(1, BuiltInTypes.Unknown)
            request.Node = expressionBody
            request.ExpectedType = SignatureReturnType(state)
            return request
        }

        if lambda.BlockBody != null {
            state.Phase = 6
            if state.TargetsExpressionTree {
                expressionTrees.ReportBlockLambdaIfNeeded(lambda)
            }

            return null
        }

        state.ReturnType = BuiltInTypes.Unknown
        state.Phase = 8
        return null
    }

    // PHASE 5 — THE EXPRESSION BODY'S ANSWER, MEASURED. Both SoA escape rules run over the body's
    // value BEFORE the expression-tree question is asked, and they run for their reports rather than
    // for their verdicts: whether they fired is read only through the diagnostic COUNT, which is what
    // makes "nothing complained about this body" the precondition for the tree report.
    func CompleteExpressionBody(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        lambda := state.Lambda
        expressionBody := lambda.ExpressionBody
        // The guard cannot fire — this phase is only reached from the arm that found an expression
        // body — and it is written out so the three reports below read a non-null body.
        if expressionBody == null {
            state.Phase = 8
            return null
        }

        soaEscape.ReportSoaRowEscapeIfNeeded(expressionBody, state.ReturnType, "returned")
        soaEscape.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expressionBody, "returned")
        ReportMissingAsyncIfNeeded(state)
        state.Phase = 8
        if !state.TargetsExpressionTree || diagnostics.ErrorCount != state.ErrorsBeforeBody {
            return null
        }

        expressionTrees.ReportUnsupportedExpressionIfNeeded(expressionBody, LambdaParameterNames(lambda))
        return null
    }

    // PHASE 6 — THE BLOCK BODY, INSIDE THE NESTED-BODY BOUNDARY. The boundary's return type is the
    // signature's, or `unknown` when nothing names one; the driver enters and leaves it around the
    // one statement.
    func EnterBlockBody(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        state.Phase = 7
        request := new LambdaAnalysisRequest(5, BlockBodyReturnType(state))
        request.Body = state.Lambda.BlockBody
        return request
    }

    // PHASE 7 — A BLOCK LAMBDA'S RETURN TYPE, WHICH IS THE SIGNATURE'S. What the block RETURNS is
    // checked against this by the return-statement rules inside the boundary; the lambda's own type
    // does not change to match it.
    func CompleteBlockBody(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        state.ReturnType = BlockBodyReturnType(state)
        state.Phase = 8
        return null
    }

    func CloseLambdaScope(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        state.Phase = 9
        return new LambdaAnalysisRequest(6, BuiltInTypes.Unknown)
    }

    // AN `async` LAMBDA'S OWN TYPE IS A TASK OF WHAT ITS BODY ANSWERED. The body produced the task's
    // RESULT — `42`, not `Task<int>` — and what the lambda converts to is the task, so the two are
    // put back together here: the TARGET names the task family (`Task` or `ValueTask`), the BODY
    // names the result, and the lambda's type is the one built from both. Taking the target's return
    // verbatim instead would be enough to pass the conversion and NOT enough to infer through it:
    // `Task.Run(async () => await F())` has to fix `TResult` from the body, and folding
    // `Task<TResult>` against `Task<TResult>` fixes nothing.
    func FinishLambda(state: LambdaAnalysisState): LambdaAnalysisRequest? {
        result := new FunctionTypeInfo()
        result.ParameterTypes = state.ParameterTypes
        result.ReturnType = state.ReturnType
        signature := state.ExpectedSignature
        if state.Lambda.IsAsync && signature != null {
            signatureReturn := signature.ReturnType
            if signatureReturn != null {
                result.ReturnType = AsyncWrappedReturnType(signatureReturn, state.ReturnType)
            }
        }

        state.Result = result
        state.Phase = 99
        return null
    }

    // THE TASK THE BODY'S VALUE TRAVELS IN: the target's own task family over the body's result type.
    // A unit task carries no result and is returned unchanged; so is a target whose result the body
    // could not name (a block body infers nothing, which is the pre-existing lambda rule), and so is
    // any shape whose CLR type cannot be constructed — in each case the target's own return is the
    // truthful answer and the conversion is judged on it.
    func AsyncWrappedReturnType(signatureReturn: TypeInfo, bodyResult: TypeInfo): TypeInfo {
        reflection := signatureReturn as ReflectionTypeInfo
        if reflection == null {
            return signatureReturn
        }

        reflectedTask := reflection.Type
        if !reflectedTask.get_IsGenericType() {
            return signatureReturn
        }

        if BuiltInTypes.IsUnknown(bodyResult) || BuiltInTypes.Is(bodyResult, BuiltInTypes.Void) {
            return signatureReturn
        }

        bodyClrType := clrTypeConversion.TryConvertTypeInfoToClrType(bodyResult)
        if bodyClrType == null {
            return signatureReturn
        }

        taskArguments := new Type[](1)
        taskArguments[0] = bodyClrType
        constructedTask := reflectedTask.GetGenericTypeDefinition().MakeGenericType(taskArguments)
        return AnalyzerReflectionTypeConversion.ConvertReflectionType(constructedTask)
    }

    // THE SIGNATURE'S RETURN TYPE AS AN EXPECTED TYPE — null when nothing names a signature, which is
    // NOT the same as `unknown`: an absent expected type leaves the ambient slot alone, and a body
    // analysed with no expectation is a different analysis from one expected to answer `unknown`.
    //
    // AN `async` LAMBDA'S BODY IS MEASURED AGAINST THE TASK'S RESULT, not against the task. The
    // delegate says `Func<Task<int>>`; the body says `42`. That is the same relation an `async func`
    // has with its own declaration — an N# `async func f(): int` writes the INNER type and the
    // signature wraps it — read in the other direction, because here the wrapped type is the one
    // that was written.
    func SignatureReturnType(state: LambdaAnalysisState): TypeInfo? {
        signature := state.ExpectedSignature
        if signature == null {
            return null
        }

        if state.Lambda.IsAsync {
            return AsyncBodyReturnType(signature.ReturnType)
        }

        return signature.ReturnType
    }

    // THE BLOCK BODY'S BOUNDARY AND RESULT TYPE, where an absent signature IS `unknown` — the ambient
    // boundary takes a type rather than an expectation, so there is nothing to leave alone.
    func BlockBodyReturnType(state: LambdaAnalysisState): TypeInfo {
        signature := state.ExpectedSignature
        if signature == null {
            return BuiltInTypes.Unknown
        }

        returnType := signature.ReturnType
        if returnType == null {
            return BuiltInTypes.Unknown
        }

        if state.Lambda.IsAsync {
            unwrapped := AsyncBodyReturnType(returnType)
            if unwrapped == null {
                return BuiltInTypes.Unknown
            }

            return unwrapped
        }

        return returnType
    }

    // A TYPE AS THE READER WROTE IT, for a message. `TypeInfo.ToString` is the one rendering every
    // other analyzer report uses.
    static func LambdaTypeText(typeInfo: TypeInfo?): string {
        if typeInfo == null {
            return "void"
        }

        boxed := typeInfo as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }

    // WHAT AN `async` LAMBDA'S BODY MUST PRODUCE, given the delegate's return type: `Task<T>` and
    // `ValueTask<T>` unwrap to `T`; `Task` and `ValueTask` carry no value, so the body is a `void` one.
    //
    // A `void`-RETURNING DELEGATE IS NOT A TARGET, and that is a DELIBERATE DEPARTURE FROM C#, which
    // accepts `async void` lambdas. N#'s `await` is lowered synchronously (there is no state machine
    // in either pipeline), so an async body with nowhere to put its task is EXACTLY its own body: the
    // keyword would change nothing, and an exception would reach the caller rather than the task, so
    // the C# meaning is not on offer. Refusing it also keeps overload resolution honest — `Task.Run`
    // declares both `Action` and `Func<Task>`, and an `async` lambda that could be an `Action` would
    // silently bind to the fire-and-forget overload. The caller reports NL334 with the fix.
    static func AsyncBodyReturnType(signatureReturn: TypeInfo?): TypeInfo? {
        if signatureReturn == null {
            return null
        }

        taskResult: TypeInfo = BuiltInTypes.Unknown
        if AnalyzerFunctionTypeFactory.TryGetTaskLikeResultTypeInfo(signatureReturn, out taskResult) {
            return taskResult
        }

        // The REFLECTED spelling counts: a delegate's `Invoke` return arrives as a
        // `ReflectionTypeInfo`, which the source-shape tables do not name, and `Func<Task>` is exactly
        // that. `IsUnitTaskLikeTypeInfo` is the reading that answers both.
        if AnalyzerFunctionTypeFactory.IsUnitTaskLikeTypeInfo(signatureReturn) {
            return BuiltInTypes.Void
        }

        return null
    }

    // Whether a delegate's return type can take an `async` lambda at all — the question NL334 asks,
    // and the one the overload scorer needs so a `void` candidate is not silently preferred.
    static func IsAsyncLambdaTarget(signatureReturn: TypeInfo?): bool {
        return AsyncBodyReturnType(signatureReturn) != null
    }

    // NL335: THE DELEGATE WANTS A TASK AND THE BODY DID NOT PRODUCE ONE, which is what writing the
    // `async` keyword would have fixed. `let load: Func<Task<int>> = () => await readAsync()` awaits
    // its way to an `int` and hands an `int` to a position that takes a `Task<int>`; the generic
    // mismatch that follows names two delegate types and leaves the reader to spot the missing word.
    //
    // THE RULE IS ABOUT THE CONVERSION, NOT ABOUT `await`. N# allows `await` in a body that is not
    // declared `async` — the lowering is identical — so "you awaited without saying async" would be a
    // rule this language does not have. What IS wrong here is narrower and certain: the target's
    // return is task-like, and the body's value is not a task, so there is no conversion at all.
    // A body that already produces a task (`() => Task.FromResult(1)`) is correct and says nothing.
    //
    // A BLOCK BODY IS NOT ASKED, because a lambda does not infer a block's return type: its `return`s
    // are measured against the signature by the nested-body boundary, and that is where their own
    // mismatch is already reported.
    func ReportMissingAsyncIfNeeded(state: LambdaAnalysisState) {
        lambda := state.Lambda
        if lambda.IsAsync || state.ReportedMissingAsync || !state.ReportInferenceFailure {
            return
        }

        signature := state.ExpectedSignature
        if signature == null || !AnalyzerFunctionTypeFactory.IsTaskLikeTypeInfo(signature.ReturnType) {
            return
        }

        bodyType := state.ReturnType
        if BuiltInTypes.IsUnknown(bodyType) || AnalyzerFunctionTypeFactory.IsTaskLikeTypeInfo(bodyType) {
            return
        }

        state.ReportedMissingAsync = true
        diagnostics.Report(ErrorCode.LambdaBodyNeedsAsync, "This lambda has to produce '" + LambdaTypeText(signature.ReturnType) + "', but its body produces '" + LambdaTypeText(bodyType) + "' — it is missing the 'async' keyword", lambda.Line, lambda.Column, "Write `async` in front of the lambda and its body's value becomes the task's result, or return a task the body builds itself (for example with `Task.FromResult(...)`).", 1)
    }

    // NL334, ONCE PER LAMBDA, AT THE `async` KEYWORD. An `async` lambda produces a task, so a target
    // that is not a task-like delegate cannot take one — and a lambda with NO target at all has
    // nothing to produce a task of. Both are reported with the fix that applies, and only on the
    // reporting pass: an overload candidate being measured must not speak.
    func ReportAsyncTargetIfNeeded(state: LambdaAnalysisState) {
        lambda := state.Lambda
        if !lambda.IsAsync || state.ReportedAsyncTarget || !state.ReportInferenceFailure {
            return
        }

        state.ReportedAsyncTarget = true
        signature := state.ExpectedSignature
        if signature == null {
            diagnostics.Report(ErrorCode.AsyncLambdaTargetNotTaskLike, "An 'async' lambda produces a task, and nothing here names the delegate type it should produce one of", lambda.Line, lambda.Column, "Give the lambda a typed home (e.g., 'let run: Func<Task<int>> = async () => ...') or pass it directly where a delegate returning `Task`, `Task<T>`, `ValueTask` or `ValueTask<T>` is expected.", 5)
            return
        }

        if AsyncBodyReturnType(signature.ReturnType) != null {
            return
        }

        diagnostics.Report(ErrorCode.AsyncLambdaTargetNotTaskLike, "An 'async' lambda produces a task, but this delegate returns '" + LambdaTypeText(signature.ReturnType) + "'", lambda.Line, lambda.Column, "An `async` body's value is wrapped in the task the delegate returns. Change the target to return `Task`, `Task<T>`, `ValueTask` or `ValueTask<T>`, or drop the `async` keyword and return the value directly.", 5)
    }

    // THE DELEGATE DOOR: WHAT SIGNATURE, IF ANY, AN EXPECTED TYPE NAMES FOR A LAMBDA.
    //
    // Four things can name one and they are asked in this order: a function type IS a signature; a
    // reflected type is one when the CLR says it is a delegate or when it is an expression-tree
    // target, both read from the RUNTIME delegate's own `Invoke`; and an N#-written generic
    // (`Func<int, int>`, `Action<string>`) is one when it converts to a CLR type that passes the same
    // two tests. Everything else names none, and a lambda with no signature infers nothing.
    func FunctionSignature(expectedType: TypeInfo?): FunctionTypeInfo? {
        if expectedType == null {
            return null
        }

        // A MAYBE-NULL TARGET NAMES THE SAME DELEGATE. `Func<int, int>?` is the declared type of a
        // field that may hold no handler, and a lambda written there is still that delegate's shape —
        // a lambda literal is never the null. Without this, a delegate FIELD (which is written `?`
        // whenever it has no initializer) could not take a lambda in an object initializer at all.
        nullableExpected := expectedType as NullableTypeInfo
        if nullableExpected != null {
            return FunctionSignature(nullableExpected.InnerType)
        }

        resolved := declarationContext.ResolveDeclaredAlias(expectedType)
        functionType := resolved as FunctionTypeInfo
        if functionType != null {
            return functionType
        }

        reflectionType := resolved as ReflectionTypeInfo
        if reflectionType != null && IsDelegateOrExpressionTreeTarget(reflectionType.Type) {
            return AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(reflectionType.Type)
        }

        generic := resolved as GenericTypeInfo
        if generic != null {
            clrType := clrTypeConversion.TryConvertTypeInfoToClrType(resolved)
            if clrType != null && IsDelegateOrExpressionTreeTarget(clrType) {
                return AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(clrType)
            }
        }

        return null
    }

    func IsDelegateOrExpressionTreeTarget(candidate: Type): bool {
        return assignabilityFacts.IsDelegateType(candidate) || AnalyzerFunctionTypeFactory.IsExpressionTreeLambdaTarget(candidate)
    }

    // THE `on` SUBSCRIPTION'S ENTRY. THE SUBSCRIPTION ROOT IS PASSED IN rather than named here, for
    // the same reason `off` takes it: this project does not reference `NSharpLang.Runtime`, so naming
    // the type here would resolve only because the analyzer's HOST happens to carry the assembly —
    // and the two halves of one feature agree structurally when the identity comes from one place.
    func BeginOnSubscription(subscription: OnSubscriptionExpression, subscriptionRoot: Type): OnSubscriptionState {
        return new OnSubscriptionState(subscription, new ReflectionTypeInfo(subscriptionRoot))
    }

    func NextOnStep(state: OnSubscriptionState): OnSubscriptionRequest? {
        while state.Phase != 99 {
            request := AdvanceOn(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. Only kind 1 answers anything: the target's type, on which
    // every remaining decision turns. Kind 2's answer is deliberately dropped.
    func SupplyOnStep(state: OnSubscriptionState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending != 1 {
            return
        }

        if answer != null {
            state.TargetType = answer
        } else {
            state.TargetType = BuiltInTypes.Unknown
        }
    }

    func AdvanceOn(state: OnSubscriptionState): OnSubscriptionRequest? {
        if state.Phase == 0 {
            state.Phase = 1
            state.Pending = 1
            request := new OnSubscriptionRequest(1)
            request.Node = state.On.Target
            return request
        }

        return ClassifyOnTarget(state)
    }

    // WHAT `on` MAY SUBSCRIBE TO, IN THE ORDER THE USER NEEDS TO HEAR IT.
    //
    // A target that is not an event at all is told so — but only after the two SoA escape rules have
    // had their say, because "a row view cannot be used as an event target" names the real problem
    // and "`on` can only subscribe to a .NET event" would name a symptom; and only when the target
    // resolved to something, because piling a second report on an already-failed resolution is noise.
    // A target that IS an event can still fail twice more: an event with no accessible add/remove
    // accessors cannot be bound at all, and an INSTANCE event on a value type cannot be bound safely,
    // both of which are caught here with a sentence rather than left to throw in the IL backend.
    //
    // THE HANDLER IS ANALYSED ON EVERY PATH, and which expected type it gets is the whole difference
    // between them: the four failing paths pass NONE and switch the inference-failure report OFF,
    // because a handler whose delegate type could not be discovered must not also be told that its
    // parameters have no inferable type — that is one problem, reported once, at the target.
    func ClassifyOnTarget(state: OnSubscriptionState): OnSubscriptionRequest? {
        target := state.On.Target
        eventInfo := state.TargetType as ReflectionEventInfo
        if eventInfo == null {
            if soaEscape.ReportSoaRowEscapeIfNeeded(target, state.TargetType, "used as an event target") {
                return EmitHandler(state, null, false)
            }

            if soaEscape.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(target, "used as an event target") {
                return EmitHandler(state, null, false)
            }

            if !BuiltInTypes.IsUnknown(state.TargetType) {
                span := spans.GetExpressionDiagnosticSpan(target)
                diagnostics.Report(ErrorCode.InvalidEventSubscription, "`on` can only subscribe to a .NET event", span.Line, span.Column, "Write `on <object>.<Event> (sender, args) => { ... }`. To combine plain delegates, use `+=` on a Func/Action field instead.", span.Length)
            }

            return EmitHandler(state, null, false)
        }

        handlerDelegateType := eventInfo.HandlerDelegateType
        addMethod := eventInfo.AddMethod
        if addMethod == null || eventInfo.RemoveMethod == null || handlerDelegateType == null {
            span := spans.GetExpressionDiagnosticSpan(target)
            diagnostics.Report(ErrorCode.InvalidEventSubscription, "'" + eventInfo.Name + "' can't be subscribed to — it has no accessible add/remove accessors", span.Line, span.Column, "This usually means the event is compiler-generated or inaccessible from N#.", span.Length)
            return EmitHandler(state, null, false)
        }

        if !addMethod.get_IsStatic() && HasValueTypeDeclaringType(eventInfo) {
            span := spans.GetExpressionDiagnosticSpan(target)
            diagnostics.Report(ErrorCode.InvalidEventSubscription, "subscribing to '" + eventInfo.Name + "' isn't supported — it's an instance event on a value type (struct)", span.Line, span.Column, "Events on struct receivers can't be bound safely. Subscribe through a reference-type instance instead.", span.Length)
        }

        return EmitHandler(state, new ReflectionTypeInfo(handlerDelegateType), true)
    }

    // WHETHER THE EVENT IS DECLARED BY A VALUE TYPE. An unknown declaring type answers NO: the rule
    // exists to catch a receiver that cannot be bound safely, and a type nothing names is not one.
    static func HasValueTypeDeclaringType(eventInfo: ReflectionEventInfo): bool {
        declaringType := eventInfo.DeclaringType
        return declaringType != null && declaringType.get_IsValueType()
    }

    // THE LAST STEP ON EVERY PATH. The walk ends here whatever the handler answers, so the phase is
    // set to its terminal value BEFORE the request is handed out.
    func EmitHandler(state: OnSubscriptionState, expectedType: TypeInfo?, reportInferenceFailure: bool): OnSubscriptionRequest? {
        state.Phase = 99
        state.Pending = 2
        request := new OnSubscriptionRequest(2)
        request.Lambda = state.On.Handler
        request.ExpectedType = expectedType
        request.ReportInferenceFailure = reportInferenceFailure
        return request
    }
}

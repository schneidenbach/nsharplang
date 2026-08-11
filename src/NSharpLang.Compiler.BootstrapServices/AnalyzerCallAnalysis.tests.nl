namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the CALL WALK — the schedule, the dispatch and the receiver protocol.
//
// The member behind these was `private` in Analyzer.cs with exactly one call site, so nothing in
// `src/` or `tests/` ever named it and the only pinning it had was end-to-end diagnostic text. These
// go at the decisions a reader cannot recover from a single arm, and above all at the one thing a
// driver could get wrong:
//
//   * THE RECEIVER COUNT. A receiver-style generic call reads the member-access receiver THREE
//     times — once to close the inference before the arguments, then again for validation and again
//     for the return type — and each read reports again. An overload group whose winner is NOT
//     receiver-style generic reads it ONCE. That difference is why the walk suspends instead of
//     scheduling: the winner is not known until the first read has already happened.
//   * the SoA direct-column rule is ONE step whose verdict ENDS the call at `unknown` — the four
//     gates under it are `AnalyzerSoaDirectColumnCalls`'s and are pinned in its own contracts;
//   * a method-group LAMBDA argument is deliberately not analysed here — it folds `unknown` and
//     still runs the ref/out target report, because binding will analyse it later with a real
//     delegate type;
//   * the expected type of each argument comes from the placement the binder computed, not from the
//     argument's own position, and it is computed from bindings closed ONCE before the loop;
//   * a reflected call that binds to nothing answers `unknown` THROUGH the reporter, so the report
//     and the answer cannot drift apart;
//   * `Ok`/`Err` short-circuits the whole walk with the factory's own answer, and is a PROBE with
//     four exits: not those two names, no `Result` being asked for, the name bound to a real symbol
//     (marked refused), and taken — which is why `IsResultFactory` is three-valued;
//   * a BARE callee is RESOLVED by the walk through the call-target door and is never a step at all,
//     while any other callee is one plain step taken under three suppressions the walk opens before
//     it asks and closes when the answer arrives — a bracket that spans a suspension;
//   * a `ref`/`out` argument is analysed against the BYREF's INNER type and folded back WRAPPED,
//     its write-target table is open across the analysis, and the target rule that follows it is
//     SILENCED by anything the analysis itself reported.

func CallWalkErrors(): List<CompilerError> {
    return new List<CompilerError>()
}

// The walk plus the three things a contract has to reach to script it: the scope stack (because a
// BARE callee is resolved through the call-target door and not handed in), the ambient context
// (because the expected type decides whether `Ok` is a factory at all) and the error list.
class CallWalkHarness {
    Owner: AnalyzerCallAnalysis
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Ambient: AnalyzerAmbientContext

    constructor(owner: AnalyzerCallAnalysis, errors: List<CompilerError>, scopes: AnalyzerScopeStack, ambient: AnalyzerAmbientContext) {
        Owner = owner
        Errors = errors
        Scopes = scopes
        Ambient = ambient
    }
}

func CallWalkHarnessOf(errors: List<CompilerError>): CallWalkHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    scopes := new AnalyzerScopeStack()
    model := new SemanticModel()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    bindings := new BindingMap()
    provider := new AnalyzerProjectSourceProvider()
    namespaces := new List<string>()
    usingAliases := new Dictionary<string, string>(StringComparer.Ordinal)
    importedSymbols := new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal)
    importedDeclarations := new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal)
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, usingAliases)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    sink := new AnalyzerDiagnosticSink(errors, provider)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, usingAliases, importedSymbols, importedDeclarations, model, bindings)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    scoring := new AnalyzerOverloadScoring(context, clrConversion, assignability, resolver, null)
    binder := new AnalyzerSyntheticCallBinder(context, scoring, assignability, clrConversion)
    spans := new AnalyzerDiagnosticSpans(sink)
    reporter := new AnalyzerSyntheticCallReporter(sink, spans)
    walk := new AnalyzerSyntheticCallWalk(
        resolver, binder, reporter, scoring, assignability, spans, sink)
    constants := new AnalyzerConstantExpressionFacts(scopes, context)
    validator := new AnalyzerSyntheticCallValidator(
        context, resolver, assignability, scoring, walk, reporter, spans, sink, constants)
    reflectionReporter := new AnalyzerReflectionCallReporter(
        scopes, context, facts, spans, sink, new AnalyzerCallableReferenceReportLog())
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)
    extensions := new List<FunctionDeclaration>()
    extensionResolution := new AnalyzerExtensionMethodResolution(resolver, assignability, context, functionTypes, clrConversion, extensions, namespaces, assemblies)
    members := new AnalyzerMemberResolution(functionTypes, context, substitution, resolver, clrConversion, extensionResolution, namespaces)
    soaEscape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, soaEscape)
    nullFlow := new AnalyzerNullFlow(sink, spans, scopes, context)
    identifierResolution := new AnalyzerIdentifierResolution(sink, scopes, resolver, discovery, probe, functionTypes, ambient, nullFlow, extensions, members, model, bindings)
    memberAccess := new AnalyzerMemberAccess(sink, spans, scopes, context, nullFlow, soaEscape, ambient, provider, discovery, probe, substitution, identifierResolution, extensions, namespaces, usingAliases, importedSymbols, importedDeclarations, assemblies, members, clrConversion, extensionResolution, bindings)
    indexAccess := new AnalyzerIndexAccess(sink, spans, context, ambient, nullFlow, soaEscape, memberAccess, constants)
    writeTargets := new AnalyzerWriteTargets(sink, spans, scopes, context, substitution, clrConversion, ambient, soaEscape, memberAccess, indexAccess)
    owner := new AnalyzerCallAnalysis(
        reporter, walk, validator, reflectionReporter, substitution, assignability, sink, spans,
        scopes, ambient, writeTargets, identifierResolution)
    return new CallWalkHarness(owner, errors, scopes, ambient)
}

// A BARE CALLEE IS NOT HANDED TO THE WALK — it is RESOLVED by it, through the call-target door. A
// contract that wants the walk to see a particular callee type therefore declares the name, exactly
// as a program would.
func CallWalkDeclare(harness: CallWalkHarness, name: string, declaredType: TypeInfo) {
    harness.Scopes.Peek().Symbols[name] = declaredType
}

// ------------------------------------------------------------------ signature and call shapes

func CallWalkNames(count: int): List<string> {
    names := new List<string>()
    index := 0
    while index < count {
        ordinal := index + 1
        names.Add("p" + ordinal.ToString())
        index = index + 1
    }

    return names
}

func CallWalkModifiers(count: int): List<ParameterModifier> {
    modifiers := new List<ParameterModifier>()
    index := 0
    while index < count {
        modifiers.Add(ParameterModifier.None)
        index = index + 1
    }

    return modifiers
}

func CallWalkTypes1(first: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    return types
}

func CallWalkTypes2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    types := new List<TypeInfo>()
    types.Add(first)
    types.Add(second)
    return types
}

func CallWalkReferences2(first: TypeReference, second: TypeReference): List<TypeReference> {
    references := new List<TypeReference>()
    references.Add(first)
    references.Add(second)
    return references
}

func CallWalkSignature(parameterTypes: List<TypeInfo>, returnType: TypeInfo?): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.SyntheticName = "f"
    signature.ParameterNames = CallWalkNames(parameterTypes.Count)
    signature.ParameterTypes = parameterTypes
    signature.ParameterModifiers = CallWalkModifiers(parameterTypes.Count)
    signature.ReturnType = returnType
    return signature
}

// `this p1: T, p2: <second>` — the receiver-style GENERIC shape the whole protocol is about.
func CallWalkReceiverGeneric(second: TypeInfo, secondReference: TypeReference): FunctionTypeInfo {
    signature := CallWalkSignature(
        CallWalkTypes2(BuiltInTypes.Int, second), BuiltInTypes.String)
    signature.SourceHasReceiverParameter = true
    signature.SourceParameterTypes = CallWalkReferences2(new SimpleTypeReference("T"), secondReference)
    typeParameters := new List<TypeParameter>()
    typeParameters.Add(new TypeParameter("T"))
    signature.TypeParameters = typeParameters
    return signature
}

// `this p1: int, p2: string` — receiver-style but NOT generic, so it never reads the receiver.
func CallWalkReceiverPlain(): FunctionTypeInfo {
    signature := CallWalkSignature(
        CallWalkTypes2(BuiltInTypes.Int, BuiltInTypes.String), BuiltInTypes.String)
    signature.SourceHasReceiverParameter = true
    signature.SourceParameterTypes = CallWalkReferences2(
        new SimpleTypeReference("int"), new SimpleTypeReference("string"))
    return signature
}

func CallWalkIdentifier(name: string): Expression {
    return new IdentifierExpression(name, 1, 1)
}

func CallWalkArgs(): List<Argument> {
    return new List<Argument>()
}

func CallWalkArgs1(name: string): List<Argument> {
    arguments := CallWalkArgs()
    arguments.Add(new Argument(null, CallWalkIdentifier(name), ArgumentModifier.None))
    return arguments
}

func CallWalkLambdaArgs1(): List<Argument> {
    arguments := CallWalkArgs()
    lambda: Expression = new LambdaExpression(new List<Parameter>(), null, null, 1, 1)
    arguments.Add(new Argument(null, lambda, ArgumentModifier.None))
    return arguments
}

func CallWalkMemberCall(arguments: List<Argument>): CallExpression {
    receiver: Expression = CallWalkIdentifier("receiver")
    callee: Expression = new MemberAccessExpression(receiver, "f", false, 1, 1)
    return new CallExpression(callee, arguments, null, 1, 1)
}

func CallWalkBareCall(arguments: List<Argument>): CallExpression {
    return new CallExpression(CallWalkIdentifier("f"), arguments, null, 1, 1)
}

func CallWalkGroup2(first: FunctionTypeInfo, second: FunctionTypeInfo): NSharpMethodGroupInfo {
    functions := new List<FunctionTypeInfo>()
    functions.Add(first)
    functions.Add(second)
    return new NSharpMethodGroupInfo(functions)
}

// ------------------------------------------------------------------ the scripted driver

func CallWalkTypeText(resolved: TypeInfo?): string {
    if resolved == null {
        return "<null>"
    }

    boxed: object = resolved
    rendered := boxed.ToString()
    if rendered == null {
        return "<null>"
    }

    return rendered
}

// The step transcript a driver would produce, in order, with the expected type of every
// expected-type analysis and the action of every escape report written out. This IS the protocol:
// any change to which step happens, in what order, or how many times, changes this string.
//
// KIND 6 IS RENDERED IN TWO FORMS BECAUSE THE WALK ASKS IT FOR TWO REASONS. `6(callee)` is the
// callee's own analysis, taken under the three callee-position suppressions the walk opens and
// closes around it; a bare `6` is a member-access RECEIVER. The DRIVER cannot tell them apart and
// does not need to — both are `AnalyzeExpression(node)` — but a contract about how many times the
// receiver is read must not count the callee as one of them.
func CallWalkStepText(step: CallAnalysisRequest, call: CallExpression): string {
    kind := step.Kind
    if kind == 4 {
        return "4(" + CallWalkTypeText(step.CarriedType) + ")"
    }

    if kind == 6 {
        if Object.ReferenceEquals(step.Node, call.Callee) {
            return "6(callee)"
        }

        return "6"
    }

    if kind == 7 {
        action := step.Text
        if action == null {
            action = "<null>"
        }

        return "7(" + action + ")"
    }

    return kind.ToString()
}

// A driver that performs nothing and answers everything from a script, so the transcript is the
// walk's own decisions and not the analyzer's.
func CallWalkRun(
    owner: AnalyzerCallAnalysis,
    state: CallAnalysisState,
    calleeType: TypeInfo?,
    receiverType: TypeInfo?,
    argumentAnswer: TypeInfo,
    boundReflection: TypeInfo?,
    firedGate: int): string {
    call := state.Call
    transcript := ""
    step := owner.NextCallStep(state)
    while step != null {
        kind := step.Kind
        if transcript.Length > 0 {
            transcript = transcript + " "
        }

        transcript = transcript + CallWalkStepText(step, call)
        answer: TypeInfo? = null
        handled := false
        if kind == 4 {
            answer = argumentAnswer
        } else if kind == 6 {
            if Object.ReferenceEquals(step.Node, call.Callee) {
                answer = calleeType
            } else {
                answer = receiverType
            }
        } else if kind == 12 || kind == 13 {
            answer = boundReflection
        } else if kind == firedGate {
            handled = true
        }

        owner.SupplyCallStep(state, answer, handled)
        step = owner.NextCallStep(state)
    }

    return transcript
}

func CallWalkCount(transcript: string, token: string): int {
    total := 0
    parts := transcript.Split(' ')
    index := 0
    while index < parts.Length {
        if parts[index] == token {
            total = total + 1
        }

        index = index + 1
    }

    return total
}

// ------------------------------------------------------------------ result-constructor shapes

func CallWalkFactoryCall(name: string, arguments: List<Argument>): CallExpression {
    return new CallExpression(CallWalkIdentifier(name), arguments, null, 1, 1)
}

// THE THREE-VALUED FACTORY MARK, read through `object` because a `bool?` compares against neither
// `true` nor `false` on the columnar surface. `unasked` is a node the probe never had an opinion
// about; `False` is one it considered and refused; `True` is one it took.
func CallWalkFactoryMark(call: CallExpression): string {
    boxed: object? = call.IsResultFactory
    if boxed == null {
        return "unasked"
    }

    rendered := boxed.ToString()
    if rendered == null {
        return "unasked"
    }

    return rendered
}

// ------------------------------------------------------------------ ref/out argument shapes

func CallWalkRefArgs1(name: string, modifier: ArgumentModifier): List<Argument> {
    arguments := CallWalkArgs()
    arguments.Add(new Argument(null, CallWalkIdentifier(name), modifier))
    return arguments
}

func CallWalkRefLiteralArgs1(modifier: ArgumentModifier): List<Argument> {
    arguments := CallWalkArgs()
    literal: Expression = new IntLiteralExpression("1", 1, 7)
    arguments.Add(new Argument(null, literal, modifier))
    return arguments
}

func CallWalkRefNullConditionalArgs1(modifier: ArgumentModifier): List<Argument> {
    arguments := CallWalkArgs()
    hop: Expression = new MemberAccessExpression(CallWalkIdentifier("holder"), "field", true, 1, 7)
    arguments.Add(new Argument(null, hop, modifier))
    return arguments
}

func CallWalkRefLambdaArgs1(modifier: ArgumentModifier): List<Argument> {
    arguments := CallWalkArgs()
    lambda: Expression = new LambdaExpression(new List<Parameter>(), null, null, 1, 7)
    arguments.Add(new Argument(null, lambda, modifier))
    return arguments
}

// A one-parameter signature whose parameter is `ref T`, which is what makes the walk unwrap the
// expected type before it hands the argument out.
func CallWalkByRefSignature(inner: TypeInfo): FunctionTypeInfo {
    byRef: TypeInfo = new ByRefTypeInfo(inner)
    return CallWalkSignature(CallWalkTypes1(byRef), BuiltInTypes.Int)
}

func CallWalkMessages(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + " | "
        }

        text = text + errors[index].Message
        index = index + 1
    }

    return text
}

// ------------------------------------------------------------------ contracts

test "the walk's prologue is the callee, the null-call report, then the gates" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    call := CallWalkBareCall(CallWalkArgs())
    signature := CallWalkSignature(new List<TypeInfo>(), BuiltInTypes.Int)
    CallWalkDeclare(harness, "f", signature)
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 0)

    // 3 the null-call report, 8 the SoA direct-column rule (ONE step: its four gates are one
    // owner's). The `Ok`/`Err` probe and the callee's own resolution are the WALK's now — the probe
    // never leaves N# and a BARE callee is answered through the call-target door — so neither shows
    // up as a step at all. No argument steps (there are none), no receiver steps (the signature is
    // not generic).
    assert transcript == "3 8"
    assert CallWalkTypeText(state.Result) == "int"
}

// The callee fork is the grammar's: a bare name is a CALL TARGET, resolved without leaving N#, and
// anything else is an expression the driver must analyse.
test "a bare callee is resolved through the call-target door and is never a step" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    call := CallWalkBareCall(CallWalkArgs())
    signature := CallWalkSignature(new List<TypeInfo>(), BuiltInTypes.Bool)
    CallWalkDeclare(harness, "f", signature)
    state := harness.Owner.BeginCall(call)

    // The scripted callee answer is DELIBERATELY a different type: if the walk had asked for the
    // callee it would have got `string`, and the result would not be `bool`.
    transcript := CallWalkRun(harness.Owner, state, BuiltInTypes.String, null, BuiltInTypes.Int, null, 0)

    assert CallWalkCount(transcript, "6(callee)") == 0
    assert CallWalkTypeText(state.Result) == "bool"
}

test "a member-access callee is analysed as one plain step under the callee suppressions" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    call := CallWalkMemberCall(CallWalkArgs())
    signature := CallWalkSignature(new List<TypeInfo>(), BuiltInTypes.Int)
    state := harness.Owner.BeginCall(call)

    // The suppressions are CLOSED before the walk starts, OPEN while the callee step is outstanding
    // and CLOSED again once its answer has been folded — the bracket spans a suspension, which is
    // why it is held in the walk's state rather than in a driver local.
    assert !harness.Ambient.AnalyzingCallCallee
    step := harness.Owner.NextCallStep(state)
    assert step != null
    assert step.Kind == 6
    assert harness.Ambient.AnalyzingCallCallee
    assert harness.Ambient.AllowUnboundCallableReference
    assert harness.Ambient.AllowSyntheticSoaOperationReference
    harness.Owner.SupplyCallStep(state, signature, false)
    assert !harness.Ambient.AnalyzingCallCallee
    assert !harness.Ambient.AllowUnboundCallableReference
    assert !harness.Ambient.AllowSyntheticSoaOperationReference
    assert CallWalkTypeText(state.CalleeType) == CallWalkTypeText(signature)
}

// WHAT THIS TEST HOST CAN AND CANNOT REACH, STATED ONCE. The probe answers `true` only for a
// `GenericTypeInfo` whose definition IS `NSharpLang.Runtime.Result<,>` — full name, arity and
// declaring assembly — and this assembly does not reference the runtime, so no contract here can
// construct one. The probe's POSITIVE paths (which arm each name selects, the arity report, the
// mismatch report and the shadow rule) are therefore pinned END TO END by the slice's `Ok`/`Err`
// fixtures under the real CLI, where the runtime is loaded. What IS pinned here is every way the
// probe declines, which is what a reader cannot recover from the arm.
test "an expected type that is not the runtime Result leaves the node unasked" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    impostor: TypeInfo = new GenericTypeInfo("Result", CallWalkTypes2(BuiltInTypes.Int, BuiltInTypes.String))
    signature := CallWalkSignature(CallWalkTypes1(BuiltInTypes.Int), BuiltInTypes.Bool)
    CallWalkDeclare(harness, "Ok", signature)
    saved := harness.Ambient.EnterExpectedType(impostor)
    call := CallWalkFactoryCall("Ok", CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 0)
    harness.Ambient.ExitExpectedType(saved)

    // The name is spelled `Ok` and the expected type is even spelled `Result` over two arguments —
    // and it is STILL an ordinary call, because the definition is not the runtime's.
    assert CallWalkFactoryMark(call) == "unasked"
    assert transcript == "3 4(int) 8"
    assert CallWalkTypeText(state.Result) == "bool"
}

test "Ok with no expected type at all is an ordinary call" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := CallWalkSignature(CallWalkTypes1(BuiltInTypes.Int), BuiltInTypes.Bool)
    CallWalkDeclare(harness, "Ok", signature)
    call := CallWalkFactoryCall("Ok", CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 0)

    assert CallWalkFactoryMark(call) == "unasked"
    assert transcript == "3 4(int) 8"
}

test "a name that is neither Ok nor Err is never probed" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    impostor: TypeInfo = new GenericTypeInfo("Result", CallWalkTypes2(BuiltInTypes.Int, BuiltInTypes.String))
    signature := CallWalkSignature(CallWalkTypes1(BuiltInTypes.Int), BuiltInTypes.Bool)
    CallWalkDeclare(harness, "Fine", signature)
    saved := harness.Ambient.EnterExpectedType(impostor)
    call := CallWalkFactoryCall("Fine", CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)

    _ = CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 0)
    harness.Ambient.ExitExpectedType(saved)

    assert CallWalkFactoryMark(call) == "unasked"
}

// THE ARM LOOKUP ITSELF, pinned directly on every shape that declines. `Ok`/`Err` are only the
// factory where a `Result` is being asked for, so each of these is a program where the two names
// mean whatever the user made them mean.
test "the result-arm lookup declines every shape that is not a runtime Result" {
    okType: TypeInfo = BuiltInTypes.Unknown
    errType: TypeInfo = BuiltInTypes.Unknown

    assert !AnalyzerCallAnalysis.TryGetResultArmTypes(null, out okType, out errType)
    assert CallWalkTypeText(okType) == "unknown"
    assert CallWalkTypeText(errType) == "unknown"

    // not generic at all
    assert !AnalyzerCallAnalysis.TryGetResultArmTypes(BuiltInTypes.Int, out okType, out errType)

    // generic, spelled `Result`, but with ONE argument
    oneArm: TypeInfo = new GenericTypeInfo("Result", CallWalkTypes1(BuiltInTypes.Int))
    assert !AnalyzerCallAnalysis.TryGetResultArmTypes(oneArm, out okType, out errType)

    // generic with two arguments and no definition at all
    noDefinition: TypeInfo = new GenericTypeInfo("Result", CallWalkTypes2(BuiltInTypes.Int, BuiltInTypes.String))
    assert !AnalyzerCallAnalysis.TryGetResultArmTypes(noDefinition, out okType, out errType)

    // generic with two arguments and a definition that is a REAL type — just not the runtime's
    wrongDefinition: TypeInfo = new GenericTypeInfo("Result", CallWalkTypes2(BuiltInTypes.Int, BuiltInTypes.String), new ReflectionTypeInfo(typeof(Dictionary<int, string>)))
    assert !AnalyzerCallAnalysis.TryGetResultArmTypes(wrongDefinition, out okType, out errType)
}

// ------------------------------------------------------------------ the ref/out argument

// A `ref T` parameter asks for a `T`. The walk unwraps the BYREF before handing the argument out and
// wraps the answer back up, so the call's argument list carries `ref int` while the expression was
// analysed against plain `int`.
test "a ref argument is analysed against the BYREF's inner type and folded back as a ByRef" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := CallWalkByRefSignature(BuiltInTypes.Int)
    CallWalkDeclare(harness, "f", signature)
    CallWalkDeclare(harness, "slot", BuiltInTypes.Int)
    call := CallWalkBareCall(CallWalkRefArgs1("slot", ArgumentModifier.Ref))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 0)

    assert transcript == "3 4(int) 8"
    assert state.ArgTypes.Count == 1
    assert CallWalkTypeText(state.ArgTypes[0]) == "&int"
    assert errors.Count == 0
}

// An `unknown` answer is NOT wrapped: `ref <error>` would be a second, invented type for a target
// that has already failed.
test "a ref argument whose analysis answered unknown is not wrapped" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := CallWalkByRefSignature(BuiltInTypes.Int)
    CallWalkDeclare(harness, "f", signature)
    CallWalkDeclare(harness, "slot", BuiltInTypes.Int)
    call := CallWalkBareCall(CallWalkRefArgs1("slot", ArgumentModifier.Ref))
    state := harness.Owner.BeginCall(call)

    _ = CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Unknown, null, 0)

    assert state.ArgTypes.Count == 1
    assert CallWalkTypeText(state.ArgTypes[0]) == "unknown"
}

test "an out argument that names no assignable target is refused with the modifier in the sentence" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := CallWalkByRefSignature(BuiltInTypes.Int)
    CallWalkDeclare(harness, "f", signature)
    call := CallWalkBareCall(CallWalkRefLiteralArgs1(ArgumentModifier.Out))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 0)

    assert transcript == "3 4(int) 8"
    assert errors.Count == 1
    assert errors[0].Message == "The 'out' argument needs an assignable target"
    assert errors[0].Suggestion == "Use a variable, field, or indexed array/SoA column element as the out argument."
}

// A `?.` chain is refused BEFORE anything is analysed: there is no kind-4 step at all, and the
// follow-up rule stays silent because this report already fired.
test "a null-conditional ref target is refused without being analysed at all" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := CallWalkByRefSignature(BuiltInTypes.Int)
    CallWalkDeclare(harness, "f", signature)
    CallWalkDeclare(harness, "holder", BuiltInTypes.String)
    call := CallWalkBareCall(CallWalkRefNullConditionalArgs1(ArgumentModifier.Ref))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 0)

    assert transcript == "3 8"
    assert state.ArgTypes.Count == 1
    assert CallWalkTypeText(state.ArgTypes[0]) == "unknown"
    assert errors.Count == 1
    assert CallWalkMessages(errors).Contains("used as the ref argument")
}

// THE SILENCE RULE. A target whose own analysis reported is not ALSO told it is unassignable —
// telling the developer both would name the wrong problem twice. The scripted driver reports here
// exactly as a real analysis would.
test "a ref target whose own analysis reported is not also told it is unassignable" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := CallWalkByRefSignature(BuiltInTypes.Int)
    CallWalkDeclare(harness, "f", signature)
    call := CallWalkBareCall(CallWalkRefLiteralArgs1(ArgumentModifier.Out))
    state := harness.Owner.BeginCall(call)

    step := harness.Owner.NextCallStep(state)
    while step != null {
        if step.Kind == 4 {
            errors.Add(AnalyzerDiagnostics.Create(ErrorCode.UndefinedVariable, "the analysis said so", null, 1, 7, null, null, 0, ErrorSeverity.Error))
        }

        harness.Owner.SupplyCallStep(state, BuiltInTypes.Int, false)
        step = harness.Owner.NextCallStep(state)
    }

    assert errors.Count == 1
    assert errors[0].Message == "the analysis said so"
}

// An ORDINARY argument is untouched by any of it: no bracket, no wrap, no target rule.
test "an ordinary argument keeps its own type and raises no target report" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := CallWalkSignature(CallWalkTypes1(BuiltInTypes.Int), BuiltInTypes.Int)
    CallWalkDeclare(harness, "f", signature)
    call := CallWalkBareCall(CallWalkRefLiteralArgs1(ArgumentModifier.None))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 0)

    assert transcript == "3 4(int) 8"
    assert CallWalkTypeText(state.ArgTypes[0]) == "int"
    assert errors.Count == 0
}

// ------------------------------------------------------------------ the receiver protocol

test "a receiver-style generic call reads the member-access receiver EXACTLY three times" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    call := CallWalkMemberCall(CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)
    signature := CallWalkReceiverGeneric(BuiltInTypes.String, new SimpleTypeReference("string"))

    transcript := CallWalkRun(
        harness.Owner, state, signature, BuiltInTypes.Int, BuiltInTypes.String, null, 0)

    // 6 before the arguments (closing the inference), then 6 again for validation and 6 again for
    // the return type. Each one is a real analysis that reports again. The leading `6(callee)` is
    // the callee itself and is NOT one of them.
    assert CallWalkCount(transcript, "6") == 3
    assert transcript == "6(callee) 3 6 4(string) 8 6 6"
}

test "the same signature called WITHOUT a member access reads no receiver at all" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := CallWalkReceiverGeneric(BuiltInTypes.String, new SimpleTypeReference("string"))
    CallWalkDeclare(harness, "f", signature)
    call := CallWalkBareCall(CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(
        harness.Owner, state, signature, BuiltInTypes.Int, BuiltInTypes.String, null, 0)

    assert CallWalkCount(transcript, "6") == 0
    assert CallWalkCount(transcript, "6(callee)") == 0
}

// THE COUNTEREXAMPLE THAT DECIDED THE SHAPE. The group holds a receiver-style GENERIC candidate and
// a plain one; the plain one wins the scoring, and only the WINNER decides whether the receiver is
// read for validation and for the return type. One read, not three — and the winner is not known
// until the first read has already been made.
test "an overload group whose winner is not receiver-style generic reads the receiver ONCE" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    call := CallWalkMemberCall(CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)
    plain := CallWalkReceiverPlain()
    generic := CallWalkReceiverGeneric(BuiltInTypes.Object, new SimpleTypeReference("object"))

    transcript := CallWalkRun(
        harness.Owner,
        state,
        CallWalkGroup2(plain, generic),
        BuiltInTypes.Int,
        BuiltInTypes.String,
        null,
        0)

    assert CallWalkCount(transcript, "6") == 1
    // 14 is the semantic-model record for the chosen overload, and it happens between the binding
    // read and the validation the winner did not need.
    assert transcript == "6(callee) 3 4(<null>) 8 6 14"
    assert CallWalkTypeText(state.Result) == "string"
}

test "an overload group whose winner IS receiver-style generic reads the receiver three times" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    call := CallWalkMemberCall(CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)
    generic := CallWalkReceiverGeneric(BuiltInTypes.String, new SimpleTypeReference("string"))
    other := CallWalkReceiverGeneric(BuiltInTypes.Object, new SimpleTypeReference("object"))

    transcript := CallWalkRun(
        harness.Owner,
        state,
        CallWalkGroup2(generic, other),
        BuiltInTypes.Int,
        BuiltInTypes.String,
        null,
        0)

    assert CallWalkCount(transcript, "6") == 3
    assert transcript == "6(callee) 3 4(<null>) 8 6 14 6 6"
}

// ------------------------------------------------------------------ dispatch and the gates

// The direct-column rule reporting ENDS the call at `unknown` and nothing after it — not the
// dispatch, not the binding — is ever asked. The ORDER of the four gates under it is the rule's own
// and is pinned in `AnalyzerSoaDirectColumnCalls.tests.nl`; what the WALK owns is that one verdict
// stops it, which is why kinds 9, 10 and 11 no longer exist and their numbers are left as a gap.
test "the SoA direct-column verdict ends the call at unknown and the dispatch is never asked" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := CallWalkSignature(new List<TypeInfo>(), BuiltInTypes.Int)
    CallWalkDeclare(harness, "f", signature)
    call := CallWalkBareCall(CallWalkArgs())
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 8)

    assert CallWalkTypeText(state.Result) == "unknown"
    assert transcript == "3 8"
}

test "a method-group lambda argument is not analysed here and folds unknown" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    methods := new MethodInfo[0]
    group: TypeInfo = new ReflectionMethodGroupInfo(methods)
    CallWalkDeclare(harness, "f", group)
    call := CallWalkBareCall(CallWalkLambdaArgs1())
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(
        harness.Owner,
        state,
        group,
        null,
        BuiltInTypes.String,
        null,
        0)

    // The skipped argument is no longer a STEP at all — kind 5 was a round trip that relayed a
    // report the walk now makes itself — so the transcript goes straight from the null-call report
    // to the gates and then to the group binding that will analyse the lambda with a real delegate
    // type.
    assert transcript == "3 8 13"
    assert state.ArgTypes.Count == 1
    assert CallWalkTypeText(state.ArgTypes[0]) == "unknown"
    assert errors.Count == 0
}

// AND THE TARGET RULE STILL RUNS ON IT. Nothing was analysed, so nothing could have reported, and
// whether a thing may be written through is a question about the SPELLING rather than about the type
// the lambda would have turned out to have.
test "a ref method-group lambda argument is still refused as a write target" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    methods := new MethodInfo[0]
    group: TypeInfo = new ReflectionMethodGroupInfo(methods)
    CallWalkDeclare(harness, "f", group)
    call := CallWalkBareCall(CallWalkRefLambdaArgs1(ArgumentModifier.Ref))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(
        harness.Owner,
        state,
        group,
        null,
        BuiltInTypes.String,
        null,
        0)

    assert transcript == "3 8 13"
    assert errors.Count == 1
    assert errors[0].Message == "The 'ref' argument needs an assignable target"
}

test "a reflected call that binds to nothing answers unknown through the reporter" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    methods := new MethodInfo[0]
    group: TypeInfo = new ReflectionMethodGroupInfo(methods)
    CallWalkDeclare(harness, "f", group)
    call := CallWalkBareCall(CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(
        harness.Owner,
        state,
        group,
        null,
        BuiltInTypes.String,
        null,
        0)

    assert transcript == "3 4(<null>) 8 13"
    assert CallWalkTypeText(state.Result) == "unknown"
}

test "a newtype construction checks arity first and the underlying type second" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    newtypeInfo: TypeInfo = new NewtypeInfo("UserId", new SimpleTypeReference("int"))
    CallWalkDeclare(harness, "f", newtypeInfo)
    call := CallWalkBareCall(CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(
        harness.Owner, state, newtypeInfo, null, BuiltInTypes.String, null, 0)

    assert transcript == "3 4(<null>) 8"
    assert CallWalkTypeText(state.Result) == "UserId"
    assert errors.Count == 1
    assert errors[0].Message.Contains("is not assignable to underlying type")

    twoArguments := CallWalkArgs1("a")
    twoArguments.Add(new Argument(null, CallWalkIdentifier("b"), ArgumentModifier.None))
    arityErrors := CallWalkErrors()
    arityHarness := CallWalkHarnessOf(arityErrors)
    CallWalkDeclare(arityHarness, "f", newtypeInfo)
    arityCall := CallWalkBareCall(twoArguments)
    arityState := arityHarness.Owner.BeginCall(arityCall)

    _ = CallWalkRun(
        arityHarness.Owner, arityState, newtypeInfo, null, BuiltInTypes.Int, null, 0)

    assert arityErrors.Count == 1
    assert arityErrors[0].Message.Contains("expects exactly 1 argument but got 2")
}

test "a callee the walk does not recognise answers unknown after the whole schedule has run" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    CallWalkDeclare(harness, "f", BuiltInTypes.Unknown)
    call := CallWalkBareCall(CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(
        harness.Owner, state, BuiltInTypes.Unknown, null, BuiltInTypes.String, null, 0)

    // The arguments are still analysed and the gates still run — an unrecognised callee must not
    // silence the diagnostics its arguments would have produced.
    assert transcript == "3 4(<null>) 8"
    assert CallWalkTypeText(state.Result) == "unknown"
}

test "a declared signature with no parameter list answers its return type without validating" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    signature := new FunctionTypeInfo()
    signature.SyntheticName = "f"
    signature.ReturnType = BuiltInTypes.Bool
    CallWalkDeclare(harness, "f", signature)
    call := CallWalkBareCall(CallWalkArgs())
    state := harness.Owner.BeginCall(call)

    transcript := CallWalkRun(harness.Owner, state, signature, null, BuiltInTypes.Int, null, 0)

    assert transcript == "3 8"
    assert CallWalkTypeText(state.Result) == "bool"
}

test "an argument's expected type comes from the signature, closed once before the loop" {
    errors := CallWalkErrors()
    harness := CallWalkHarnessOf(errors)
    call := CallWalkMemberCall(CallWalkArgs1("a"))
    state := harness.Owner.BeginCall(call)
    typeParameter: TypeInfo = new SimpleTypeInfo("T")
    signature := CallWalkReceiverGeneric(typeParameter, new SimpleTypeReference("T"))

    transcript := CallWalkRun(
        harness.Owner, state, signature, BuiltInTypes.Int, BuiltInTypes.String, null, 0)

    // `p2: T` with the receiver binding `T = int` — the expected type is the CLOSED one, and it is
    // closed from the receiver read before the loop rather than from the arguments analysed so far.
    assert transcript == "6(callee) 3 6 4(int) 8 6 6"
}

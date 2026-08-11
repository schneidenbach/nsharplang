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
//   * `Ok`/`Err` short-circuits the whole walk with the factory's own answer.

func CallWalkErrors(): List<CompilerError> {
    return new List<CompilerError>()
}

func CallWalkOwner(errors: List<CompilerError>): AnalyzerCallAnalysis {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    sink := new AnalyzerDiagnosticSink(errors, provider)
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        sink,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        new SemanticModel(),
        new BindingMap())
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
    return new AnalyzerCallAnalysis(
        reporter, walk, validator, reflectionReporter, substitution, assignability, sink)
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

// The step transcript a driver would produce, in order, with the expected type of every argument
// step and the action of every escape report written out. This IS the protocol: any change to which
// step happens, in what order, or how many times, changes this string.
func CallWalkStepText(step: CallAnalysisRequest): string {
    kind := step.Kind
    if kind == 4 {
        return "4(" + CallWalkTypeText(step.CarriedType) + ")"
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
    calleeType: TypeInfo,
    receiverType: TypeInfo?,
    argumentAnswer: TypeInfo,
    boundReflection: TypeInfo?,
    factoryAnswer: TypeInfo?,
    firedGate: int): string {
    transcript := ""
    step := owner.NextCallStep(state)
    while step != null {
        kind := step.Kind
        if transcript.Length > 0 {
            transcript = transcript + " "
        }

        transcript = transcript + CallWalkStepText(step)
        answer: TypeInfo? = null
        handled := false
        if kind == 1 {
            if factoryAnswer != null {
                handled = true
                answer = factoryAnswer
            }
        } else if kind == 2 {
            answer = calleeType
        } else if kind == 4 {
            answer = argumentAnswer
        } else if kind == 6 {
            answer = receiverType
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

// ------------------------------------------------------------------ contracts

test "the walk's prologue is the factory probe, the callee, the null-call report, then the gates" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkBareCall(CallWalkArgs())
    state := owner.BeginCall(call)
    signature := CallWalkSignature(new List<TypeInfo>(), BuiltInTypes.Int)

    transcript := CallWalkRun(owner, state, signature, null, BuiltInTypes.Int, null, null, 0)

    // 1 factory probe, 2 callee, 3 null-call report, 8 the SoA direct-column rule (ONE step: its
    // four gates are one owner's). No argument steps (there are none), no receiver steps (the
    // signature is not generic).
    assert transcript == "1 2 3 8"
    assert CallWalkTypeText(state.Result) == "int"
}

test "the result-constructor factory short-circuits the whole walk with its own answer" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkBareCall(CallWalkArgs1("a"))
    state := owner.BeginCall(call)
    signature := CallWalkSignature(CallWalkTypes1(BuiltInTypes.Int), BuiltInTypes.Int)

    transcript := CallWalkRun(
        owner, state, signature, null, BuiltInTypes.Int, null, BuiltInTypes.String, 0)

    assert transcript == "1"
    assert CallWalkTypeText(state.Result) == "string"
}

test "a receiver-style generic call reads the member-access receiver EXACTLY three times" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkMemberCall(CallWalkArgs1("a"))
    state := owner.BeginCall(call)
    signature := CallWalkReceiverGeneric(BuiltInTypes.String, new SimpleTypeReference("string"))

    transcript := CallWalkRun(
        owner, state, signature, BuiltInTypes.Int, BuiltInTypes.String, null, null, 0)

    // 6 before the arguments (closing the inference), then 6 again for validation and 6 again for
    // the return type. Each one is a real analysis that reports again.
    assert CallWalkCount(transcript, "6") == 3
    assert transcript == "1 2 3 6 4(string) 8 6 6"
}

test "the same signature called WITHOUT a member access reads no receiver at all" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkBareCall(CallWalkArgs1("a"))
    state := owner.BeginCall(call)
    signature := CallWalkReceiverGeneric(BuiltInTypes.String, new SimpleTypeReference("string"))

    transcript := CallWalkRun(
        owner, state, signature, BuiltInTypes.Int, BuiltInTypes.String, null, null, 0)

    assert CallWalkCount(transcript, "6") == 0
}

// THE COUNTEREXAMPLE THAT DECIDED THE SHAPE. The group holds a receiver-style GENERIC candidate and
// a plain one; the plain one wins the scoring, and only the WINNER decides whether the receiver is
// read for validation and for the return type. One read, not three — and the winner is not known
// until the first read has already been made.
test "an overload group whose winner is not receiver-style generic reads the receiver ONCE" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkMemberCall(CallWalkArgs1("a"))
    state := owner.BeginCall(call)
    plain := CallWalkReceiverPlain()
    generic := CallWalkReceiverGeneric(BuiltInTypes.Object, new SimpleTypeReference("object"))

    transcript := CallWalkRun(
        owner,
        state,
        CallWalkGroup2(plain, generic),
        BuiltInTypes.Int,
        BuiltInTypes.String,
        null,
        null,
        0)

    assert CallWalkCount(transcript, "6") == 1
    // 14 is the semantic-model record for the chosen overload, and it happens between the binding
    // read and the validation the winner did not need.
    assert transcript == "1 2 3 4(<null>) 8 6 14"
    assert CallWalkTypeText(state.Result) == "string"
}

test "an overload group whose winner IS receiver-style generic reads the receiver three times" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkMemberCall(CallWalkArgs1("a"))
    state := owner.BeginCall(call)
    generic := CallWalkReceiverGeneric(BuiltInTypes.String, new SimpleTypeReference("string"))
    other := CallWalkReceiverGeneric(BuiltInTypes.Object, new SimpleTypeReference("object"))

    transcript := CallWalkRun(
        owner,
        state,
        CallWalkGroup2(generic, other),
        BuiltInTypes.Int,
        BuiltInTypes.String,
        null,
        null,
        0)

    assert CallWalkCount(transcript, "6") == 3
    assert transcript == "1 2 3 4(<null>) 8 6 14 6 6"
}

// The direct-column rule reporting ENDS the call at `unknown` and nothing after it — not the
// dispatch, not the binding — is ever asked. The ORDER of the four gates under it is the rule's own
// and is pinned in `AnalyzerSoaDirectColumnCalls.tests.nl`; what the WALK owns is that one verdict
// stops it, which is why kinds 9, 10 and 11 no longer exist and their numbers are left as a gap.
test "the SoA direct-column verdict ends the call at unknown and the dispatch is never asked" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkBareCall(CallWalkArgs())
    state := owner.BeginCall(call)
    signature := CallWalkSignature(new List<TypeInfo>(), BuiltInTypes.Int)

    transcript := CallWalkRun(owner, state, signature, null, BuiltInTypes.Int, null, null, 8)

    assert CallWalkTypeText(state.Result) == "unknown"
    assert transcript == "1 2 3 8"
}

test "a method-group lambda argument is not analysed here and folds unknown" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkBareCall(CallWalkLambdaArgs1())
    state := owner.BeginCall(call)
    methods := new MethodInfo[0]

    transcript := CallWalkRun(
        owner,
        state,
        new ReflectionMethodGroupInfo(methods),
        null,
        BuiltInTypes.String,
        null,
        null,
        0)

    // 5 is the SKIPPED argument: no analysis, but the ref/out target report still runs, and 13 is
    // the group binding that will analyse the lambda with a real delegate type.
    assert transcript == "1 2 3 5 8 13"
    assert state.ArgTypes.Count == 1
    assert CallWalkTypeText(state.ArgTypes[0]) == "unknown"
}

test "a reflected call that binds to nothing answers unknown through the reporter" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkBareCall(CallWalkArgs1("a"))
    state := owner.BeginCall(call)
    methods := new MethodInfo[0]

    transcript := CallWalkRun(
        owner,
        state,
        new ReflectionMethodGroupInfo(methods),
        null,
        BuiltInTypes.String,
        null,
        null,
        0)

    assert transcript == "1 2 3 4(<null>) 8 13"
    assert CallWalkTypeText(state.Result) == "unknown"
}

test "a newtype construction checks arity first and the underlying type second" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkBareCall(CallWalkArgs1("a"))
    state := owner.BeginCall(call)
    newtypeInfo := new NewtypeInfo("UserId", new SimpleTypeReference("int"))

    transcript := CallWalkRun(
        owner, state, newtypeInfo, null, BuiltInTypes.String, null, null, 0)

    assert transcript == "1 2 3 4(<null>) 8"
    assert CallWalkTypeText(state.Result) == "UserId"
    assert errors.Count == 1
    assert errors[0].Message.Contains("is not assignable to underlying type")

    twoArguments := CallWalkArgs1("a")
    twoArguments.Add(new Argument(null, CallWalkIdentifier("b"), ArgumentModifier.None))
    arityErrors := CallWalkErrors()
    arityOwner := CallWalkOwner(arityErrors)
    arityCall := CallWalkBareCall(twoArguments)
    arityState := arityOwner.BeginCall(arityCall)

    _ = CallWalkRun(
        arityOwner, arityState, newtypeInfo, null, BuiltInTypes.Int, null, null, 0)

    assert arityErrors.Count == 1
    assert arityErrors[0].Message.Contains("expects exactly 1 argument but got 2")
}

test "a callee the walk does not recognise answers unknown after the whole schedule has run" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkBareCall(CallWalkArgs1("a"))
    state := owner.BeginCall(call)

    transcript := CallWalkRun(
        owner, state, BuiltInTypes.Unknown, null, BuiltInTypes.String, null, null, 0)

    // The arguments are still analysed and the gates still run — an unrecognised callee must not
    // silence the diagnostics its arguments would have produced.
    assert transcript == "1 2 3 4(<null>) 8"
    assert CallWalkTypeText(state.Result) == "unknown"
}

test "a declared signature with no parameter list answers its return type without validating" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkBareCall(CallWalkArgs())
    state := owner.BeginCall(call)
    signature := new FunctionTypeInfo()
    signature.SyntheticName = "f"
    signature.ReturnType = BuiltInTypes.Bool

    transcript := CallWalkRun(owner, state, signature, null, BuiltInTypes.Int, null, null, 0)

    assert transcript == "1 2 3 8"
    assert CallWalkTypeText(state.Result) == "bool"
}

test "an argument's expected type comes from the signature, closed once before the loop" {
    errors := CallWalkErrors()
    owner := CallWalkOwner(errors)
    call := CallWalkMemberCall(CallWalkArgs1("a"))
    state := owner.BeginCall(call)
    typeParameter: TypeInfo = new SimpleTypeInfo("T")
    signature := CallWalkReceiverGeneric(typeParameter, new SimpleTypeReference("T"))

    transcript := CallWalkRun(
        owner, state, signature, BuiltInTypes.Int, BuiltInTypes.String, null, null, 0)

    // `p2: T` with the receiver binding `T = int` — the expected type is the CLOSED one, and it is
    // closed from the receiver read before the loop rather than from the arguments analysed so far.
    assert transcript == "1 2 3 6 4(int) 8 6 6"
}

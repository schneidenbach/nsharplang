namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// ONE STEP THE CALL WALK CANNOT TAKE FOR ITSELF, AND EVERYTHING THAT STEP NEEDS.
//
// The walk owns what a call MEANS — which branch it takes, which expression is analysed next, with
// which expected type, how many times the receiver is read, which report fires where, and what the
// call's type finally is. What it cannot do is run the analyzer's own expression walk or the C#
// reporters that have not moved yet, so it ASKS: one request at a time, each naming a kind and
// carrying every value the step needs. Nothing here is a policy the driver may reinterpret — the
// driver switches on `Kind` and performs exactly the one operation, with exactly these operands.
//
// A KIND IS AN OPERATION, NOT A PURPOSE, which is why there are fewer kinds than there are things
// the walk does with them. Two places need a plain expression analysed and both ask for kind 6; two
// places need one analysed against an expected type and both ask for kind 4. What differs between
// them is ambient state this owner sets and clears ITSELF, on its own side of the boundary.
//
// The kinds, in the order the walk can emit them:
//   3  the possible-null-call report
//   4  one expression analysed with `CarriedType` as its expected type and `Flag` as the
//      method-group suppression — an ordinary argument, the BYREF-unwrapped target of a `ref`/`out`
//      argument, the single argument of an `Ok`/`Err` factory, a reflected call's non-lambda
//      argument pre-pass (no expected type, suppression ON), or one of the reflected bind's
//      finalising analyses. A NULL `CarriedType` is not the same as `unknown`: the analyzer's
//      target-typed door leaves the ambient slot ALONE when no expected type is provided.
//   6  a plain expression analysis: the CALLEE, under the callee-position suppressions, which this
//      owner opens before asking and closes when the answer arrives
//   7  one SoA row-view escape report
//   8  the SoA direct-column call rule (answers only whether it reported)
//   14 the semantic-model record for a bound N# overload
//   15 one LAMBDA analysed with `CarriedType` as its expected type and `Flag` as the
//      EXPRESSION-TREE flag. It is a kind of its own rather than a widening of kind 4 because the
//      operations differ: kind 4's door short-circuits a lambda with the expected type as an
//      argument and NO tree flag, and a tree target is exactly what changes which expressions the
//      body may contain.
//   16 the MEMBER-ACCESS RECEIVER, read again after the callee walk has already analysed it. It is a
//      kind of its own rather than a kind 6 precisely because the driver may answer it WITHOUT
//      re-walking the receiver: the callee walk kept the receiver's dispatched type, so the driver
//      re-runs the expression tail on it where it stands. That is a different operation from kind 6,
//      and a driver that treated the two alike would put the exponential back.
//
// THE GAPS AT 1, 2, 5, 9, 10, 11, 12 AND 13 ARE KEPT ON PURPOSE. Each was a round trip that relayed
// a decision this walk now makes for itself — the `Ok`/`Err` probe (1), the callee's own fork between
// a bound name and an analysed expression (2), the un-analysed method-group lambda whose `ref`/`out`
// target is still checked (5), the four direct-column gates before they became one owner (9, 10, 11),
// and the reflected bind of a single method (12) and of a method GROUP (13), which are now this
// walk's own five-stage bind. A step kind is a VALUE the contracts pin, so renumbering would silently
// re-point every one of them.
class CallAnalysisRequest {
    Kind: int
    Node: Expression?
    Lambda: LambdaExpression?
    CarriedType: TypeInfo?
    Text: string?
    Line: int
    Column: int
    Flag: bool

    constructor(kind: int) {
        Kind = kind
        Node = null
        Lambda = null
        CarriedType = null
        Text = null
        Line = 0
        Column = 0
        Flag = false
    }
}

// THE CALL WALK'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Phase` is the walk's program counter and `Pending` names the answer it is waiting for. Everything
// else is what the C# member this replaces held in locals.
class CallAnalysisState {
    callValue: CallExpression
    argTypesValue: List<TypeInfo>
    candidateMethodsValue: List<MethodInfo>

    Call: CallExpression => callValue
    ArgTypes: List<TypeInfo> => argTypesValue
    CandidateMethods: List<MethodInfo> => candidateMethodsValue

    Phase: int
    Pending: int
    CalleeType: TypeInfo?
    SyntheticFunctionType: FunctionTypeInfo?
    SyntheticParameterIndexByArgument: int[]?
    SyntheticExpectedBindings: Dictionary<string, TypeInfo>?
    GroupFunctions: List<FunctionTypeInfo>?
    BoundFunction: FunctionTypeInfo?
    ReceiverType: TypeInfo?
    ParameterStartIndex: int
    ArgumentIndex: int
    EscapeIndex: int
    IsMethodGroup: bool

    // THE `Ok`/`Err` FACTORY'S TWO ARMS AND THE OPEN GENERIC THEY CLOSE, held across the one analysis
    // the probe needs. The expected arm is the one the spelled name selects; the other three are kept
    // because the call's own type is rebuilt from them when nothing else names it.
    ResultOkType: TypeInfo?
    ResultErrType: TypeInfo?
    ResultDefinition: TypeInfo?
    ResultExpectedArm: TypeInfo?

    // THE CALLEE-POSITION SUPPRESSIONS, open across the callee's analysis. Held here rather than in
    // a C# local because the analysis is a SUSPENSION: the bracket opens in one turn of the walk and
    // closes in the next.
    CalleeFrame: AmbientCallCalleeFrame?

    // THE `ref`/`out` ARGUMENT CURRENTLY OUT FOR ANALYSIS, and everything its follow-up report needs.
    // `RefOutArgument` being non-null is what distinguishes the two answers kind 4 can carry: an
    // ordinary argument's type, or a write target's, which comes back wrapped in `ByRefTypeInfo` and
    // is then checked for assignability against the count of diagnostics taken BEFORE the analysis.
    RefOutArgument: Argument?
    RefOutModifier: string?
    RefOutErrorsBefore: int
    RefOutSavedExpressionTypes: Dictionary<object, TypeInfo>?
    RefOutExpressionTypes: Dictionary<object, TypeInfo>?

    // THE REFLECTED BIND, WHICH IS A WALK INSIDE THIS WALK.
    //
    // `ReflectionSingleMethod` and `ReflectionMethodGroup` are exclusive and name which of the two
    // reflected forms is being bound: one named method, or a group whose candidates are pre-bound,
    // ordered and tried in turn. The receiver is analysed AGAIN here — the callee analysis already
    // read it once, and the second read is what `Analyzer.cs` did and is user-visible, so it is
    // preserved rather than shared. The non-lambda arguments are analysed ONCE, up front, into
    // `AnalyzedNonLambdaArguments`, because pre-binding scores against them; a LAMBDA argument is
    // left null there deliberately, since its signature is not known until a candidate is chosen.
    //
    // `FinalizeState` is the INNER walk's whole state. Its requests are re-emitted as this walk's
    // own kinds, which is why the two walks compose instead of nesting: one driver, one loop, one
    // protocol. `ReflectionErrorsBefore` is the rollback mark for the candidate currently being
    // finalised, and it is re-taken for each candidate.
    ReflectionSingleMethod: MethodInfo?
    ReflectionMethodGroup: ReflectionMethodGroupInfo?
    ReflectionReceiverTypeInfo: TypeInfo?
    ReflectionReceiverClrType: Type?
    AnalyzedNonLambdaArguments: TypeInfo?[]?
    ReflectionArgumentIndex: int
    ReflectionCandidates: List<ReflectionPreBoundCandidate>?
    ReflectionCandidateIndex: int

    // WHETHER THE CANDIDATE RUN NOW UNDER WAY IS THE EXACT-MATCH ONE. A group whose call carries a
    // LAMBDA argument is walked twice: first demanding that every lambda's own type BE the delegate
    // the candidate declares (§12.6.4.4's "E exactly matches T"), then — only if that found nothing —
    // accepting every conversion, which is what the walk always did. The second run is the fallback,
    // so a call with no exact match behaves exactly as it did before the clause existed.
    ReflectionRequireExactLambdaMatch: bool
    ReflectionErrorsBefore: int
    ReflectionArgumentErrorsBefore: int
    ReflectionArgumentIsUntargeted: bool
    FinalizeState: ReflectionCallFinalizeState?

    // The call expression's type. `unknown` is the walk's own final answer for a callee it does not
    // recognise, so it is the honest starting value rather than a null placeholder.
    Result: TypeInfo

    // The written argument a `[NotNullIfNotNull(...)]` on the chosen signature's return names, or -1.
    NotNullIfNotNullArgumentIndex: int

    constructor(call: CallExpression) {
        callValue = call
        argTypesValue = new List<TypeInfo>()
        candidateMethodsValue = new List<MethodInfo>()
        Phase = 0
        Pending = 0
        CalleeType = null
        SyntheticFunctionType = null
        SyntheticParameterIndexByArgument = null
        SyntheticExpectedBindings = null
        GroupFunctions = null
        BoundFunction = null
        ReceiverType = null
        ParameterStartIndex = 0
        ArgumentIndex = 0
        EscapeIndex = 0
        IsMethodGroup = false
        ResultOkType = null
        ResultErrType = null
        ResultDefinition = null
        ResultExpectedArm = null
        CalleeFrame = null
        RefOutArgument = null
        RefOutModifier = null
        RefOutErrorsBefore = 0
        RefOutSavedExpressionTypes = null
        RefOutExpressionTypes = null
        ReflectionSingleMethod = null
        ReflectionMethodGroup = null
        ReflectionReceiverTypeInfo = null
        ReflectionReceiverClrType = null
        AnalyzedNonLambdaArguments = null
        ReflectionArgumentIndex = 0
        ReflectionCandidates = null
        ReflectionCandidateIndex = 0
        ReflectionRequireExactLambdaMatch = false
        ReflectionErrorsBefore = 0
        ReflectionArgumentErrorsBefore = 0
        ReflectionArgumentIsUntargeted = false
        FinalizeState = null
        Result = BuiltInTypes.Unknown
        NotNullIfNotNullArgumentIndex = -1
    }
}

// EVERYTHING THE ANALYZER DECIDES ABOUT A CALL EXPRESSION, as a walk that suspends at each step it
// cannot take itself.
//
// WHY A RESUMABLE WALK RATHER THAN A HOISTED SCHEDULE, AND IT WAS SETTLED BY COUNTEREXAMPLE.
// The one thing a driver could get wrong is HOW MANY TIMES the member-access receiver is analysed,
// because each analysis reports again. Instrumenting the six receiver sites over the whole corpus
// could not decide it — 96,502 receiver-site evaluations across 48,611 calls in 71 project targets
// and NOT ONE fired, because the corpus declares no receiver-style generic function. Purpose-built
// fixtures decided it. The common shapes are bimodal, 0 or 3, which a hoisted count could have
// reproduced; but an overload group holding BOTH a receiver-style generic candidate and a
// non-generic one that wins the scoring fires the receiver ONCE — the first analysis feeds
// `BindNSharpCall`, and only the CHOSEN overload decides whether the other two happen. The count is
// therefore a function of an answer the walk does not have until it has already suspended once, so
// no schedule computed up front reproduces it.
//
// THE COUNT IS STILL THE WALK'S, BUT A REPEAT IS NO LONGER A RE-WALK. The repeats used to re-analyse
// the receiver's whole subtree, and a fluent chain's receiver IS a call whose receiver is a call, so
// a chain of N links was analysed once per PATH through it — 2^N — and a 27-link
// `.WithHandler<T>()` registration never finished. The receiver sites therefore ask for KIND 16, and
// the driver answers them from the walk the callee already did: the same value-misuse guards run, at
// each site's own ambient position, and the subtree is not walked again. What that deletes is the
// DUPLICATE REPORT the old repeat produced — `nlc build` rendered the same NL401 twelve times on a
// `Bad(1, 2).Tag("x")` receiver where the analyses were four per pass, while `nlc check` distincted
// its result set and hid it. One report per fault is the contract now, in both commands.
//
// The receiver's own GUARD stays here for the same reason it did in `AnalyzerSyntheticCallWalk`:
// the driver may not analyse an expression the walk would not have analysed, nor skip one it would.
class AnalyzerCallAnalysis {
    syntheticCallReporter: AnalyzerSyntheticCallReporter
    syntheticCallWalk: AnalyzerSyntheticCallWalk
    syntheticCallValidator: AnalyzerSyntheticCallValidator
    reflectionCallReporter: AnalyzerReflectionCallReporter
    reflectionArgumentBinder: AnalyzerReflectionArgumentBinder
    clrTypeConversion: AnalyzerClrTypeConversion
    typeSubstitution: AnalyzerTypeSubstitution
    assignability: AnalyzerAssignability
    diagnostics: AnalyzerDiagnosticSink
    spans: AnalyzerDiagnosticSpans
    scopes: AnalyzerScopeStack
    ambient: AnalyzerAmbientContext
    writeTargets: AnalyzerWriteTargets
    identifierResolution: AnalyzerIdentifierResolution
    declarationContext: AnalyzerDeclarationContext
    postconditions: AnalyzerNullabilityPostconditions
    terminatingCalls: AnalyzerTerminatingCalls
    nullFlow: AnalyzerNullFlow

    constructor(callReporter: AnalyzerSyntheticCallReporter, callWalk: AnalyzerSyntheticCallWalk, callValidator: AnalyzerSyntheticCallValidator, reflectionReporter: AnalyzerReflectionCallReporter, argumentBinder: AnalyzerReflectionArgumentBinder, conversion: AnalyzerClrTypeConversion, substitution: AnalyzerTypeSubstitution, assignabilityOwner: AnalyzerAssignability, diagnosticSink: AnalyzerDiagnosticSink, spansOwner: AnalyzerDiagnosticSpans, scopeStack: AnalyzerScopeStack, ambientContext: AnalyzerAmbientContext, writeTargetsOwner: AnalyzerWriteTargets, identifierResolutionOwner: AnalyzerIdentifierResolution, declarationContextOwner: AnalyzerDeclarationContext, postconditionOwner: AnalyzerNullabilityPostconditions, terminatingCallOwner: AnalyzerTerminatingCalls, nullFlowOwner: AnalyzerNullFlow) {
        syntheticCallReporter = callReporter
        syntheticCallWalk = callWalk
        syntheticCallValidator = callValidator
        reflectionCallReporter = reflectionReporter
        reflectionArgumentBinder = argumentBinder
        clrTypeConversion = conversion
        typeSubstitution = substitution
        assignability = assignabilityOwner
        diagnostics = diagnosticSink
        spans = spansOwner
        scopes = scopeStack
        ambient = ambientContext
        writeTargets = writeTargetsOwner
        identifierResolution = identifierResolutionOwner
        declarationContext = declarationContextOwner
        postconditions = postconditionOwner
        terminatingCalls = terminatingCallOwner
        nullFlow = nullFlowOwner
    }

    func BeginCall(call: CallExpression): CallAnalysisState {
        return new CallAnalysisState(call)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when the call's type is decided. Every phase
    // either computes something and advances, or emits exactly one request; the walk never advances
    // past a point whose answer it has not been given.
    func NextCallStep(state: CallAnalysisState): CallAnalysisRequest? {
        while state.Phase != 99 {
            request := AdvanceCall(state)
            if request != null {
                return request
            }
        }

        // THE CHAIN'S RESULT IS DECIDED WHERE THE CHAIN ENDS, and for `s?.Trim()` that is the
        // INVOCATION rather than the member access: `.Trim` resolves to a method group, which has no
        // nullable form, so the lift has to wait until the call has produced a value. The walk's own
        // exit is the one place every arm of it passes through.
        state.Result = LiftNullConditionalChainResult(state, ApplyNotNullIfNotNullResult(state))
        return null
    }

    // `Path.GetFileName(path)` IS AS NULL AS `path` WAS. Its return is declared `string?` and carries
    // `[NotNullIfNotNull("path")]`, which is the signature's way of saying the nullable annotation is
    // there for ONE argument's sake. The argument's analysed type is the answer: the flow has already
    // collapsed a narrowed nullable to its inner type by the time it reaches here, so a non-nullable
    // argument type IS the proof that the argument was not null.
    func ApplyNotNullIfNotNullResult(state: CallAnalysisState): TypeInfo {
        result := state.Result
        argumentIndex := state.NotNullIfNotNullArgumentIndex
        if argumentIndex < 0 || argumentIndex >= state.ArgTypes.Count {
            return result
        }

        if declarationContext.ResolveDeclaredAlias(state.ArgTypes[argumentIndex]) as NullableTypeInfo != null {
            return result
        }

        nullableResult := declarationContext.ResolveDeclaredAlias(result) as NullableTypeInfo
        if nullableResult == null {
            return result
        }

        return nullableResult.InnerType
    }

    // `s?.Trim()` IS `string?`, AND SO IS EVERY OTHER INVOCATION A `?.` GUARDS. The emitter already
    // reads the chain this way — it short-circuits to a null reference or an empty `Nullable<T>` —
    // so an analyzer that reported the unlifted type was describing a value the program cannot
    // produce, and a `string` local could be assigned a null the flow never admitted.
    func LiftNullConditionalChainResult(state: CallAnalysisState, result: TypeInfo): TypeInfo {
        if !IsNullConditionalInvocationTarget(state.Call.Callee) {
            return result
        }

        resolved := declarationContext.ResolveDeclaredAlias(result)
        if BuiltInTypes.Is(resolved, BuiltInTypes.Void) || BuiltInTypes.Is(resolved, BuiltInTypes.Never) || resolved as UnknownTypeInfo != null || resolved as NullableTypeInfo != null {
            return result
        }

        return new NullableTypeInfo(result)
    }

    // THE ANSWER TO THE OUTSTANDING STEP, folded in according to what was asked. `Pending` is the
    // WALK's own marker for what the outstanding answer MEANS, which is not the same thing as the
    // `Kind` the driver was given: two answers can arrive from the same operation and mean different
    // things here. `handled` is the boolean verdict of the one probe step that remains — the
    // direct-column rule — and it ENDS the walk, exactly as the early `return` it replaces did.
    func SupplyCallStep(state: CallAnalysisState, answer: TypeInfo?, handled: bool) {
        pending := state.Pending
        state.Pending = 0

        if pending == 1 {
            CompleteResultConstructorProbe(state, answer)
            return
        }

        if pending == 2 {
            frame := state.CalleeFrame
            if frame != null {
                ambient.ExitCallCallee(frame)
                state.CalleeFrame = null
            }

            state.CalleeType = answer
            return
        }

        if pending == 4 {
            CompleteArgument(state, answer)
            return
        }

        if pending == 6 {
            state.ReceiverType = answer
            return
        }

        if pending == 8 {
            if handled {
                state.Result = BuiltInTypes.Unknown
                state.Phase = 99
            }

            return
        }

        if pending == 30 {
            state.ReflectionReceiverTypeInfo = answer
            return
        }

        if pending == 32 {
            arguments := state.AnalyzedNonLambdaArguments
            if arguments != null {
                arguments[state.ReflectionArgumentIndex] = answer
            }

            WithdrawUntargetedCollectionReports(state)
            state.ReflectionArgumentIndex = state.ReflectionArgumentIndex + 1
            return
        }

        if pending == 36 {
            finalizeState := state.FinalizeState
            if finalizeState != null {
                supplied: TypeInfo = BuiltInTypes.Unknown
                if answer != null {
                    supplied = answer
                }

                reflectionArgumentBinder.SupplyReflectionAnalysis(finalizeState, supplied)
            }
        }
    }

    // ONE TURN OF THE WALK: a request when the next thing to happen is the driver's, otherwise null
    // with the phase moved on.
    func AdvanceCall(state: CallAnalysisState): CallAnalysisRequest? {
        phase := state.Phase
        if phase == 0 {
            return BeginResultConstructorProbe(state)
        }

        if phase == 1 {
            return BeginCallee(state)
        }

        if phase == 2 {
            return EmitPossibleNullCall(state)
        }

        if phase == 3 {
            return BeginArguments(state)
        }

        if phase == 4 {
            functionType := state.SyntheticFunctionType
            if functionType == null {
                state.Phase = 6
                return null
            }

            return AcquireReceiver(state, AnalyzerSyntheticCallWalk.NeedsReceiverType(functionType, state.Call), 5)
        }

        if phase == 5 {
            return InferArgumentBindings(state)
        }

        if phase == 6 {
            return EmitSyntheticArgument(state)
        }

        if phase == 7 {
            return EmitGroupArgument(state)
        }

        if phase == 8 {
            return EmitSoaRowEscape(state)
        }

        if phase == 9 {
            return EmitSoaGate(state)
        }

        if phase == 13 {
            return Dispatch(state)
        }

        if phase >= 30 && phase <= 36 {
            return AdvanceReflectionBind(state, phase)
        }

        if phase >= 14 && phase <= 17 {
            return AdvanceFunctionTypeReturn(state, phase)
        }

        return AdvanceMethodGroupReturn(state, phase)
    }

    // THE REFLECTED BIND, WHICH IS THE OTHER HALF OF WHAT A CALL MEANS.
    //
    // A callee that resolved to a .NET method — one named method, or a GROUP of overloads — is bound
    // here, in five ordered stages: the receiver is analysed, the non-lambda arguments are analysed,
    // every candidate is pre-bound and scored, the candidates are ORDERED, and each in turn is
    // FINALISED until one succeeds. Only the last stage can report, and what it reports is what makes
    // the ORDER user-visible.
    //
    // IT STARTS AT 30, NOT AT THE NEXT FREE NUMBER, AND THAT IS A MEASUREMENT. This walk's phase
    // space is NOT dense: `AdvanceCall` routes 13, then 14-17 to the function-type return, and then
    // FALLS THROUGH to the N#-method-group return — which owns 18 through 23 and reads them from the
    // fall-through rather than from a listed range. Numbering this stage 20-26 silently STOLE four of
    // them, and the only thing that noticed was one N# overload group in the compiler's own source
    // becoming ambiguous. A range routed BEFORE a fall-through must be disjoint from everything the
    // fall-through can see, so the gap between 23 and 30 is deliberate headroom rather than tidiness.
    func AdvanceReflectionBind(state: CallAnalysisState, phase: int): CallAnalysisRequest? {
        if phase == 30 {
            return AcquireReflectionReceiver(state)
        }

        if phase == 31 {
            return ConvertReflectionReceiver(state)
        }

        if phase == 32 {
            return EmitReflectionArgument(state)
        }

        if phase == 34 {
            return PreBindReflectionCandidates(state)
        }

        if phase == 35 {
            return BeginNextReflectionCandidate(state)
        }

        return AdvanceFinalizeReflectionCall(state)
    }

    // PHASE 30 — THE RECEIVER, READ AGAIN. The callee walk already analysed the whole member access,
    // which analysed this receiver once; the bind needs the same receiver as a value a second time.
    // It asks for it as KIND 16 rather than kind 6, which is what lets the driver answer from the
    // walk it already did: a re-walk of the receiver's subtree costs whatever that subtree costs and
    // a chained receiver is itself a call, so re-walking here made the analysis exponential in the
    // length of a fluent chain. What the repeat cost that was WORTH keeping — the receiver's own
    // value-misuse guards, judged at THIS ambient position rather than the callee's — the driver
    // still runs; what it cost that was not is a second copy of every diagnostic the subtree already
    // reported, which `nlc check` distincted away and `nlc build` rendered twice.
    func AcquireReflectionReceiver(state: CallAnalysisState): CallAnalysisRequest? {
        memberAccess := state.Call.Callee as MemberAccessExpression
        if memberAccess == null {
            state.Phase = 32
            return null
        }

        state.Phase = 31
        state.Pending = 30
        request := new CallAnalysisRequest(16)
        request.Node = memberAccess.Object
        return request
    }

    // PHASE 31 — THE RECEIVER AS A CLR TYPE, BY EITHER OF TWO DOORS. The ordinary conversion answers
    // for a type the CLR already holds; the binding-only conversion answers for one that exists only
    // as a shape the binder can measure against. The second is a FALLBACK rather than an alternative,
    // and the order is preserved.
    func ConvertReflectionReceiver(state: CallAnalysisState): CallAnalysisRequest? {
        state.Phase = 32
        receiverTypeInfo := state.ReflectionReceiverTypeInfo
        if receiverTypeInfo == null {
            return null
        }

        restoredReceiver := TryRestoreNarrowedNullableReceiver(state, receiverTypeInfo)
        if restoredReceiver != null {
            receiverTypeInfo = restoredReceiver
            state.ReflectionReceiverTypeInfo = restoredReceiver
        }

        // A CONSTRAINED TYPE PARAMETER BINDS AS THE ONE THING ITS CLAUSE SAYS IT IS. The member
        // surface was already resolved through the same substitution, so the two must agree: an
        // extension's receiver slot is matched against `IEnumerable<string>`, not against `T`, and
        // the type arguments that match fixes are what type a lambda argument at the same call.
        constrainedReceiver := scopes.ConstrainedReceiverType(receiverTypeInfo)
        if !Object.ReferenceEquals(constrainedReceiver, receiverTypeInfo) {
            receiverTypeInfo = constrainedReceiver
            state.ReflectionReceiverTypeInfo = constrainedReceiver
        }

        clrType := clrTypeConversion.TryConvertTypeInfoToClrType(receiverTypeInfo)
        if clrType == null {
            clrType = clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(receiverTypeInfo)
        }

        state.ReflectionReceiverClrType = clrType
        return null
    }

    // THE RECEIVER THE BIND NEEDS IS THE TYPE THE MEMBER WAS FOUND ON, and for a NARROWED nullable
    // VALUE type those are two different CLR types. Inside `if v == null { return }` the receiver of
    // `v.GetValueOrDefault()` reads as `int` — that is what the flow proved — while the member it
    // resolved to is declared on `Nullable<int>`, and an `int` receiver binds against `Nullable<T>`'s
    // signature no better than any unrelated type would. The receiver's DECLARED type is handed to
    // the binder instead.
    //
    // IT ONLY FIRES WHEN A CANDIDATE IS ACTUALLY DECLARED ON THE NULLABLE, which is what keeps it from
    // being a rule about nullables at all: every member `int` itself declares still binds against
    // `int`, with `int`'s own overloads, and an extension method's declaring type is its static class
    // and matches neither reading.
    func TryRestoreNarrowedNullableReceiver(state: CallAnalysisState, receiverTypeInfo: TypeInfo): TypeInfo? {
        memberAccess := state.Call.Callee as MemberAccessExpression
        if memberAccess == null {
            return null
        }

        if !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(receiverTypeInfo) {
            return null
        }

        origin := nullFlow.NarrowedNullableOrigin(memberAccess.Object, receiverTypeInfo)
        if origin == null {
            return null
        }

        originClrType := clrTypeConversion.TryConvertTypeInfoToClrType(origin)
        if originClrType == null {
            return null
        }

        methods := state.CandidateMethods
        for method in methods {
            declaringType := method.get_DeclaringType()
            if declaringType != null && TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(declaringType, originClrType) {
                return origin
            }
        }

        return null
    }

    // PHASE 32 — EVERY NON-LAMBDA ARGUMENT, ANALYSED ONCE, BEFORE ANY CANDIDATE IS SCORED.
    //
    // A LAMBDA argument is deliberately left unanalysed and its slot left null: its parameter types
    // come from the candidate's signature, so analysing it here would type it against nothing and
    // report an inference failure for a lambda that is about to be given a delegate type. Every other
    // argument is analysed with the METHOD-GROUP suppression open, because a method group named as an
    // argument is exactly what this bind may be about to convert to a delegate — kind 4 with no
    // expected type is that operation, and the analyzer's target-typed door leaves an absent expected
    // type alone rather than clearing the slot.
    func EmitReflectionArgument(state: CallAnalysisState): CallAnalysisRequest? {
        arguments := state.Call.Arguments
        if state.AnalyzedNonLambdaArguments == null {
            state.AnalyzedNonLambdaArguments = new TypeInfo?[](arguments.Count)
        }

        while state.ReflectionArgumentIndex < arguments.Count {
            argument := arguments[state.ReflectionArgumentIndex]
            if argument.Value as LambdaExpression != null {
                state.ReflectionArgumentIndex = state.ReflectionArgumentIndex + 1
                continue
            }

            state.Pending = 32
            state.ReflectionArgumentIsUntargeted = argument.Value as ArrayLiteralExpression != null
            state.ReflectionArgumentErrorsBefore = diagnostics.ErrorCount
            request := new CallAnalysisRequest(4)
            request.Node = argument.Value
            request.Flag = true
            return request
        }

        state.Phase = 34
        return null
    }

    // PHASE 34 — EVERY CANDIDATE PRE-BOUND AND SCORED, THEN ORDERED.
    //
    // The single-method form has exactly one candidate and no ordering question. The GROUP form
    // pre-binds every overload, drops the ones that cannot accept this call at all, and ORDERS what
    // is left: highest score first, then the ones that do not need `params`, then the ones that need
    // fewer defaults. Neither form reports here — a group with no surviving candidate is an unbound
    // call, which is one report at the end rather than one per overload.
    func PreBindReflectionCandidates(state: CallAnalysisState): CallAnalysisRequest? {
        arguments := state.AnalyzedNonLambdaArguments
        if arguments == null {
            arguments = new TypeInfo?[](0)
        }

        singleMethod := state.ReflectionSingleMethod
        if singleMethod != null {
            candidate := reflectionArgumentBinder.PreBindReflectionMethod(singleMethod, state.Call, state.ReflectionReceiverClrType, state.ReflectionReceiverTypeInfo, arguments)
            if candidate == null {
                return FailReflectionBind(state)
            }

            state.FinalizeState = reflectionArgumentBinder.BeginFinalizeReflectionCall(candidate, false)
            state.Phase = 36
            return null
        }

        methodGroup := state.ReflectionMethodGroup
        candidates := new List<ReflectionPreBoundCandidate>()
        if methodGroup != null {
            methods := methodGroup.Methods
            for method in methods {
                candidate := reflectionArgumentBinder.PreBindReflectionMethod(method, state.Call, state.ReflectionReceiverClrType, state.ReflectionReceiverTypeInfo, arguments)
                if candidate != null {
                    candidates.Add(candidate)
                }
            }
        }

        if candidates.Count == 0 {
            return FailReflectionBind(state)
        }

        SortReflectionCandidates(candidates)
        PromoteBestReflectionCandidate(state, candidates)
        state.ReflectionCandidates = candidates
        state.ReflectionCandidateIndex = 0
        state.ReflectionRequireExactLambdaMatch = CallHasLambdaArgument(state.Call)
        state.Phase = 35
        return null
    }

    // WHICH CANDIDATE THE LANGUAGE PREFERS, DECIDED WITHOUT REFERENCE TO THE ORDER THEY ARRIVED IN.
    //
    // The sort above orders the RETRY sequence and it is a total order over three keys, so it always
    // produces some first element — which for a genuine tie was whichever candidate the metadata
    // happened to yield first. `Assert.Single(x.EnumerateArray())` is what that costs: the
    // non-generic `Single(IEnumerable): object?` and the generic `Single<T>(IEnumerable<T>): T` score
    // the same 4, tie on `params` and on defaults, and the call's type silently became `object?`.
    //
    // "Better function member" is a PARTIAL order and is answered here instead, against the whole
    // candidate list, by `AnalyzerOverloadSpecificity.FindMaximalIndexes`: the candidates NOTHING
    // beats. That set is the same however the list was ordered, which is the property a reflected
    // candidate list needs — it comes out of a MetadataLoadContext in no guaranteed order. Exactly
    // one maximal candidate is MOVED TO THE FRONT and bound; two or more is NL414, because a tie the
    // language cannot break is the reader's to break and never the compiler's to guess.
    //
    // A SURROGATE GROUP IS EXEMPT FROM THE REPORT. Its candidates are read off an instantiation
    // closed over `object` because the real type argument has no CLR handle yet, so two of them
    // looking alike is the surrogate failing to represent the call rather than the program being
    // ambiguous — the same reason `FailReflectionBind` answers `unknown` for one.
    func PromoteBestReflectionCandidate(state: CallAnalysisState, candidates: List<ReflectionPreBoundCandidate>) {
        count := candidates.Count
        if count < 2 {
            return
        }

        argumentClrTypes := BuildReflectionArgumentClrTypes(state)
        argumentTypeInfos := BuildReflectionArgumentTypeInfos(state)
        argumentIsAnonymousFunction := BuildReflectionArgumentAnonymousFunctionFlags(state, argumentClrTypes.Length)
        parameterTypesByCandidate := new List<Type?[]>()
        openParameterTypesByCandidate := new List<Type?[]>()
        candidateIndex := 0
        while candidateIndex < count {
            parameterTypesByCandidate.Add(BuildReflectionParameterTypesByArgument(candidates[candidateIndex], state, argumentClrTypes.Length))
            openParameterTypesByCandidate.Add(BuildReflectionOpenParameterTypesByArgument(candidates[candidateIndex], state, argumentClrTypes.Length))
            candidateIndex = candidateIndex + 1
        }

        comparisons := new int[count * count]
        row := 0
        while row < count {
            column := 0
            while column < count {
                if row != column {
                    comparisons[row * count + column] = CompareReflectionCandidates(candidates[row], candidates[column], parameterTypesByCandidate[row], parameterTypesByCandidate[column], openParameterTypesByCandidate[row], openParameterTypesByCandidate[column], argumentClrTypes, argumentTypeInfos, argumentIsAnonymousFunction)
                }

                column = column + 1
            }

            row = row + 1
        }

        maximal := AnalyzerOverloadSpecificity.FindMaximalIndexes(comparisons, count)
        if maximal.Count == 0 {
            return
        }

        if maximal.Count > 1 {
            group := state.ReflectionMethodGroup
            if (group == null || !group.IsSurrogateBinding) && ReflectionComparisonIsFullyInformed(parameterTypesByCandidate[maximal[0]], parameterTypesByCandidate[maximal[1]], argumentClrTypes, argumentTypeInfos) {
                reflectionCallReporter.ReportAmbiguousCall(state.Call, state.CandidateMethods, candidates[maximal[0]].SignatureMethod, candidates[maximal[1]].SignatureMethod)
            }
        }

        // EVERY MAXIMAL CANDIDATE MOVES TO THE FRONT, in the order the list already had them. The
        // first one is the same candidate a single promotion would have moved, so nothing about a
        // resolved call changes; what changes is the RETRY order behind it — a candidate that
        // something beats is now tried after every candidate that nothing beats, instead of
        // wherever the score sort left it. That matters as soon as the leading candidate can fail
        // (the exact-match run below), because the fallback must be the next-best member and not
        // simply the next row of the sort.
        promoted := new List<ReflectionPreBoundCandidate>()
        for maximalItem in maximal {
            promoted.Add(candidates[maximalItem])
        }

        remainingIndex := 0
        while remainingIndex < count {
            if !maximal.Contains(remainingIndex) {
                promoted.Add(candidates[remainingIndex])
            }

            remainingIndex = remainingIndex + 1
        }

        candidates.Clear()
        candidateIndex = 0
        while candidateIndex < promoted.Count {
            candidates.Add(promoted[candidateIndex])
            candidateIndex = candidateIndex + 1
        }
    }

    // EVERY POSITION'S ARGUMENT TYPE, THE EXTENSION RECEIVER INCLUDED AT SLOT 0.
    //
    // THE RECEIVER IS AN ARGUMENT. `values.AsQueryable()` writes NO arguments at all and chooses
    // between `AsQueryable(IEnumerable): IQueryable` and `AsQueryable<T>(IEnumerable<T>): IQueryable<T>`
    // entirely on the receiver — so a comparison that looked only at the written list saw two
    // candidates with nothing to tell them apart, fell through to "non-generic beats generic" and
    // typed the result as the non-generic `IQueryable`, after which `query.Where(x => x > 1)` had no
    // element type to give the lambda. Slot 0 is the receiver's own type, or null for a call that has
    // none.
    //
    // A lambda was deliberately left unanalysed by phase 32 and a method group has no type of its own,
    // so both land here as null and the specificity walk simply asks nothing about those positions —
    // which is exactly why a group with two ARITIES makes both `Enumerable.Select` overloads tie and
    // reports NL414 rather than picking one.
    func BuildReflectionArgumentClrTypes(state: CallAnalysisState): Type?[] {
        analyzed := state.AnalyzedNonLambdaArguments
        analyzedCount := 0
        if analyzed != null {
            analyzedCount = analyzed.Length
        }

        clrTypes := new Type?[](analyzedCount + 1)
        clrTypes[0] = state.ReflectionReceiverClrType
        index := 0
        while index < analyzedCount && analyzed != null {
            argumentType := analyzed[index]
            if argumentType != null {
                clrTypes[index + 1] = clrTypeConversion.TryConvertTypeInfoToClrType(argumentType)
            }

            index = index + 1
        }

        return clrTypes
    }

    // WHICH POSITIONS HOLD AN ANONYMOUS FUNCTION, in the same slot numbering the type arrays use —
    // slot 0 is the extension receiver and never a lambda. A lambda is the one argument that reaches
    // the comparison with NO type and still has a betterness rule of its own (§12.6.4.4), so the
    // comparison has to be able to tell it apart from an argument whose type is merely unknown.
    func BuildReflectionArgumentAnonymousFunctionFlags(state: CallAnalysisState, positionCount: int): bool[] {
        flags := new bool[positionCount]
        arguments := state.Call.Arguments
        index := 0
        while index < arguments.Count && index + 1 < positionCount {
            flags[index + 1] = arguments[index].Value as LambdaExpression != null
            index = index + 1
        }

        return flags
    }

    // WHETHER THE TIE IS THE PROGRAM'S OR THE COMPILER'S.
    //
    // NL414 accuses the reader of writing a call the LANGUAGE cannot resolve, and that accusation is
    // only honest when the comparison had something to compare. A position whose argument has no type
    // at all — an anonymous object, which types as `unknown` and is therefore assignable to every
    // parameter, or a lambda phase 32 deliberately left unanalysed — tells the rule nothing, so two
    // candidates that differ THERE are tied for want of information rather than by the language's own
    // rules. `BadRequest(new { errors: errors })` is exactly that: `BadRequest(object?)` and
    // `BadRequest(ModelStateDictionary)` both survive applicability because nothing can reject either,
    // and reporting an ambiguity would be blaming the user for a gap in the analyzer.
    //
    // A position both candidates spell the SAME way is not a difference and does not disqualify the
    // report; neither is a method group, which HAS a type — that is the `Enumerable.Select` case NL414
    // exists for.
    func ReflectionComparisonIsFullyInformed(leftParameterTypes: Type?[], rightParameterTypes: Type?[], argumentClrTypes: Type?[], argumentTypeInfos: TypeInfo?[]): bool {
        index := 0
        while index < argumentClrTypes.Length {
            currentIndex := index
            index = index + 1

            leftParameterType := leftParameterTypes[currentIndex]
            rightParameterType := rightParameterTypes[currentIndex]
            if leftParameterType == null && rightParameterType == null {
                continue
            }

            if leftParameterType != null && rightParameterType != null && TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(leftParameterType, rightParameterType) {
                continue
            }

            if argumentClrTypes[currentIndex] != null {
                continue
            }

            argumentTypeInfo: TypeInfo? = null
            if currentIndex < argumentTypeInfos.Length {
                argumentTypeInfo = argumentTypeInfos[currentIndex]
            }

            if argumentTypeInfo == null {
                return false
            }

            if BuiltInTypes.IsUnknown(argumentTypeInfo) {
                return false
            }
        }

        return true
    }

    // THE SAME POSITIONS, AS N# TYPES. An argument the CLR has no type for — an anonymous object, a
    // constructed source generic, a method group — still has a `TypeInfo`, and the assignability
    // relation over those is the only oracle that can say whether a parameter accepts it at all.
    // `BadRequest(new { errors: errors })` is the case: `BadRequest(object?)` and
    // `BadRequest(ModelStateDictionary)` both survived applicability because the anonymous argument had
    // no CLR form to reject either with, and the two then tied on every key.
    func BuildReflectionArgumentTypeInfos(state: CallAnalysisState): TypeInfo?[] {
        analyzed := state.AnalyzedNonLambdaArguments
        analyzedCount := 0
        if analyzed != null {
            analyzedCount = analyzed.Length
        }

        typeInfos := new TypeInfo?[](analyzedCount + 1)
        typeInfos[0] = state.ReflectionReceiverTypeInfo
        index := 0
        while index < analyzedCount && analyzed != null {
            typeInfos[index + 1] = analyzed[index]
            index = index + 1
        }

        return typeInfos
    }

    // ONE CANDIDATE'S PARAMETER TYPE PER POSITION, with this candidate's own inference substituted in —
    // the comparison is between the types the call would actually convert to, not between the open
    // signatures. Slot 0 is the RECEIVER parameter of a receiver-style extension, and null for every
    // other candidate shape. A position filled from a DEFAULT has no written argument and is absent; an
    // EXPANDED params tail contributes its ELEMENT type once per element, which is the type each of
    // those arguments is really converted to.
    func BuildReflectionParameterTypesByArgument(candidate: ReflectionPreBoundCandidate, state: CallAnalysisState, positionCount: int): Type?[] {
        parameterTypes := new Type?[](positionCount)
        if AnalyzerOverloadFacts.IsExtensionMethodCallOnReceiver(candidate.SignatureMethod, state.Call, state.ReflectionReceiverClrType) {
            receiverParameters := candidate.SignatureMethod.GetParameters()
            if receiverParameters.Length > 0 && positionCount > 0 {
                parameterTypes[0] = AnalyzerReflectionTypeConversion.ApplyReflectionBindings(receiverParameters[0].get_ParameterType(), candidate.Bindings)
            }
        }

        boundArguments := candidate.BoundArguments
        index := 0
        while index < boundArguments.Count {
            boundArgument := boundArguments[index]
            index = index + 1

            supplied := boundArgument as SuppliedReflectionBoundArgument
            if supplied != null {
                if supplied.ArgumentIndex >= 0 && supplied.ArgumentIndex + 1 < positionCount {
                    parameterTypes[supplied.ArgumentIndex + 1] = AnalyzerReflectionTypeConversion.ApplyReflectionBindings(supplied.OpenParameterType, candidate.Bindings)
                }

                continue
            }

            expanded := boundArgument as ParamsReflectionBoundArgument
            if expanded != null {
                elements := expanded.Arguments
                elementIndex := 0
                while elementIndex < elements.Count {
                    element := elements[elementIndex]
                    elementIndex = elementIndex + 1
                    if element.ArgumentIndex >= 0 && element.ArgumentIndex + 1 < positionCount {
                        parameterTypes[element.ArgumentIndex + 1] = AnalyzerReflectionTypeConversion.ApplyReflectionBindings(element.OpenParameterType, candidate.Bindings)
                    }
                }
            }
        }

        return parameterTypes
    }

    // THE SAME POSITIONS, UNINSTANTIATED. Every rule but the last reads the closed parameter types
    // above; "more specific parameter types" reads the signature the declaration WROTE, which is the
    // only way a pair closing to the identical parameter types can still be ordered
    // (`Task.Run<TResult>(Func<TResult>)` against `Task.Run<TResult>(Func<Task<TResult>>)`, both
    // `Func<Task<int>>` once inferred). The two arrays are built by the same walk so that position
    // `i` names the same argument in both.
    func BuildReflectionOpenParameterTypesByArgument(candidate: ReflectionPreBoundCandidate, state: CallAnalysisState, positionCount: int): Type?[] {
        parameterTypes := new Type?[](positionCount)
        if AnalyzerOverloadFacts.IsExtensionMethodCallOnReceiver(candidate.SignatureMethod, state.Call, state.ReflectionReceiverClrType) {
            receiverParameters := candidate.SignatureMethod.GetParameters()
            if receiverParameters.Length > 0 && positionCount > 0 {
                parameterTypes[0] = receiverParameters[0].get_ParameterType()
            }
        }

        boundArguments := candidate.BoundArguments
        index := 0
        while index < boundArguments.Count {
            boundArgument := boundArguments[index]
            index = index + 1

            supplied := boundArgument as SuppliedReflectionBoundArgument
            if supplied != null {
                if supplied.ArgumentIndex >= 0 && supplied.ArgumentIndex + 1 < positionCount {
                    parameterTypes[supplied.ArgumentIndex + 1] = supplied.OpenParameterType
                }

                continue
            }

            expanded := boundArgument as ParamsReflectionBoundArgument
            if expanded != null {
                elements := expanded.Arguments
                elementIndex := 0
                while elementIndex < elements.Count {
                    element := elements[elementIndex]
                    elementIndex = elementIndex + 1
                    if element.ArgumentIndex >= 0 && element.ArgumentIndex + 1 < positionCount {
                        parameterTypes[element.ArgumentIndex + 1] = element.OpenParameterType
                    }
                }
            }
        }

        return parameterTypes
    }

    // THE REFLECTED WORLD'S "BETTER FUNCTION MEMBER", answered by supplying this world's conversion
    // oracle to `AnalyzerOverloadSpecificity`.
    //
    // THE SCORE STILL DECIDES FIRST. It is the applicability ladder, and it carries facts the type
    // comparison below cannot see at all — the extension-method penalty that keeps an instance method
    // ahead of an extension, and the lambda rules that prefer a delegate which KEEPS a result over
    // one that throws it away. Specificity separates candidates the ladder rated the same, which is
    // exactly the case it was introduced for.
    //
    // A position is SKIPPED rather than guessed at when either candidate left it unfilled, when a
    // type parameter stayed open (there is no type to compare), or when the argument has no CLR form.
    //
    // AN ANONYMOUS FUNCTION IS THE ONE ARGUMENT WITH NO TYPE THAT STILL ANSWERS THIS QUESTION.
    // "Better conversion from expression" (§12.6.4.4) asks first whether the lambda EXACTLY MATCHES
    // one delegate and not the other — its inferred return type is that delegate's — which needs the
    // body typed against a target and is therefore not available here; phase 32 leaves a lambda
    // unanalysed on purpose. Its SECOND clause needs nothing about the argument at all: where the
    // lambda matches both delegates or neither, the BETTER CONVERSION TARGET wins, and that is the
    // ordinary §12.6.4.6 comparison between the two parameter types. `Task.Run(() => Task.FromResult(11))`
    // is exactly that pair: `Func<Task<int>>` converts to `Func<Task>` by covariance and not back, so
    // the delegate that keeps the result is the better target — the answer C# gives by the first
    // clause, reached here by the second. An argument that has no type for a different reason (an
    // anonymous object, which types as `unknown`) is NOT asked, because for it the parameter-type
    // comparison would be a guess dressed as a rule.
    func CompareReflectionCandidates(left: ReflectionPreBoundCandidate, right: ReflectionPreBoundCandidate, leftParameterTypes: Type?[], rightParameterTypes: Type?[], leftOpenParameterTypes: Type?[], rightOpenParameterTypes: Type?[], argumentClrTypes: Type?[], argumentTypeInfos: TypeInfo?[], argumentIsAnonymousFunction: bool[]): int {
        if left.Score != right.Score {
            if left.Score > right.Score {
                return AnalyzerOverloadSpecificity.LeftIsBetter
            }

            return AnalyzerOverloadSpecificity.RightIsBetter
        }

        verdicts := new List<int>()
        parameterTypesIdentical := true
        index := 0
        while index < argumentClrTypes.Length {
            currentIndex := index
            index = index + 1

            leftParameterType := leftParameterTypes[currentIndex]
            rightParameterType := rightParameterTypes[currentIndex]

            // A POSITION NEITHER CANDIDATE FILLS IS NOT A DIFFERENCE. Slot 0 is null for every
            // non-extension call, and a defaulted tail is absent from both; treating that as "the
            // parameter lists differ" would silently switch off the non-generic tie-break for every
            // ordinary static call.
            if leftParameterType == null && rightParameterType == null {
                continue
            }

            if leftParameterType == null || rightParameterType == null || leftParameterType.get_ContainsGenericParameters() || rightParameterType.get_ContainsGenericParameters() {
                parameterTypesIdentical = false
                continue
            }

            if !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(leftParameterType, rightParameterType) {
                parameterTypesIdentical = false
            }

            argumentClrType := argumentClrTypes[currentIndex]
            if argumentClrType == null {
                // NO CLR FORM, BUT STILL A TYPE. The N# relation answers whether each parameter accepts
                // this argument at all, and a parameter that accepts it is a better conversion target
                // than one that does not — which is applicability stated as a betterness verdict,
                // because applicability could not reject either candidate without a CLR type to ask
                // about. A position where both accept (or neither does) says nothing, which is how a
                // method group with two arities stays tied.
                argumentTypeInfo: TypeInfo? = null
                if currentIndex < argumentTypeInfos.Length {
                    argumentTypeInfo = argumentTypeInfos[currentIndex]
                }

                if argumentTypeInfo == null {
                    if currentIndex < argumentIsAnonymousFunction.Length && argumentIsAnonymousFunction[currentIndex] {
                        verdicts.Add(AnalyzerOverloadSpecificity.CompareConversionTargets(
                            false,
                            false,
                            HasImplicitReflectionConversion(leftParameterType, rightParameterType),
                            HasImplicitReflectionConversion(rightParameterType, leftParameterType)
                        ))
                    }

                    continue
                }

                leftAccepts := assignability.IsAssignable(AnalyzerReflectionTypeConversion.ConvertReflectionType(leftParameterType), argumentTypeInfo)
                rightAccepts := assignability.IsAssignable(AnalyzerReflectionTypeConversion.ConvertReflectionType(rightParameterType), argumentTypeInfo)
                if leftAccepts != rightAccepts {
                    if leftAccepts {
                        verdicts.Add(AnalyzerOverloadSpecificity.LeftIsBetter)
                    } else {
                        verdicts.Add(AnalyzerOverloadSpecificity.RightIsBetter)
                    }
                }

                continue
            }

            verdicts.Add(AnalyzerOverloadSpecificity.CompareConversionTargets(
                TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(leftParameterType, argumentClrType),
                TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(rightParameterType, argumentClrType),
                HasImplicitReflectionConversion(leftParameterType, rightParameterType),
                HasImplicitReflectionConversion(rightParameterType, leftParameterType)
            ))
        }

        conversionVerdict := AnalyzerOverloadSpecificity.FoldArgumentVerdicts(verdicts)
        if conversionVerdict != AnalyzerOverloadSpecificity.NeitherIsBetter {
            return conversionVerdict
        }

        if parameterTypesIdentical {
            hidingVerdict := CompareReflectionDeclaringDepth(left, right)
            if hidingVerdict != AnalyzerOverloadSpecificity.NeitherIsBetter {
                return hidingVerdict
            }
        }

        return AnalyzerOverloadSpecificity.CompareTieBreaks(
            parameterTypesIdentical,
            left.SignatureMethod.get_IsGenericMethodDefinition(),
            right.SignatureMethod.get_IsGenericMethodDefinition(),
            left.UsesParams,
            right.UsesParams,
            left.DefaultsUsed,
            right.DefaultsUsed,
            AnalyzerOpenTypeSpecificity.CompareReflectionParameterLists(leftOpenParameterTypes, rightOpenParameterTypes)
        )
    }

    // A MEMBER DECLARED ON A MORE DERIVED TYPE HIDES THE ONE IT SHADOWS (§12.6.4.4), and the two are
    // otherwise indistinguishable: the same name, the same parameter types, the same score. Asked
    // only when the parameter types ARE identical, because that is the only shape where hiding is
    // what separates the pair — every other difference is a conversion question already answered.
    // The RUNTIME method's declaring type is the one that matters: it is the type the call dispatches
    // on, not the definition its open signature was read from.
    func CompareReflectionDeclaringDepth(left: ReflectionPreBoundCandidate, right: ReflectionPreBoundCandidate): int {
        leftDeclaringType := left.RuntimeMethod.get_DeclaringType()
        rightDeclaringType := right.RuntimeMethod.get_DeclaringType()
        if leftDeclaringType == null || rightDeclaringType == null {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }

        if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(leftDeclaringType, rightDeclaringType) {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }

        leftDerivesFromRight := AnalyzerConversionFacts.IsReflectionAssignableFrom(rightDeclaringType, leftDeclaringType)
        rightDerivesFromLeft := AnalyzerConversionFacts.IsReflectionAssignableFrom(leftDeclaringType, rightDeclaringType)
        if leftDerivesFromRight == rightDerivesFromLeft {
            return AnalyzerOverloadSpecificity.NeitherIsBetter
        }

        if leftDerivesFromRight {
            return AnalyzerOverloadSpecificity.LeftIsBetter
        }

        return AnalyzerOverloadSpecificity.RightIsBetter
    }

    // WHETHER ONE PARAMETER TYPE CONVERTS IMPLICITLY TO ANOTHER — the relation "more specific" is
    // read from. Reference and interface conversions (which is how `IEnumerable<Task<int>>` reaches
    // `IEnumerable<Task>`) plus the numeric widening table, which is how `int` beats `long` as the
    // target for a `short` argument.
    static func HasImplicitReflectionConversion(sourceType: Type, targetType: Type): bool {
        if AnalyzerConversionFacts.IsReflectionAssignableFrom(targetType, sourceType) {
            return true
        }

        return AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(sourceType, targetType)
    }

    // THE CANDIDATE ORDER, AND IT IS SORTED BY HAND BECAUSE ITS STABILITY IS USER-VISIBLE.
    //
    // Equal-key candidates must keep the order the method group gave them, because the LAST candidate
    // tried is the one whose diagnostics survive — every earlier failure is rolled back — so a sort
    // that reordered ties would change which sentence the user reads. An INSERTION sort driven by a
    // STRICTLY-precedes predicate is stable by construction: an element never moves past one it does
    // not strictly precede, so equal keys cannot cross. It reproduces
    // `OrderByDescending(Score).ThenBy(UsesParams).ThenBy(DefaultsUsed)` exactly, including that
    // ordering `false` before `true` means a candidate that does NOT need `params` wins a tie.
    func SortReflectionCandidates(candidates: List<ReflectionPreBoundCandidate>) {
        index := 1
        while index < candidates.Count {
            current := candidates[index]
            position := index
            while position > 0 && PrecedesReflectionCandidate(current, candidates[position - 1]) {
                candidates[position] = candidates[position - 1]
                position = position - 1
            }

            candidates[position] = current
            index = index + 1
        }
    }

    static func PrecedesReflectionCandidate(candidate: ReflectionPreBoundCandidate, existing: ReflectionPreBoundCandidate): bool {
        if candidate.Score != existing.Score {
            return candidate.Score > existing.Score
        }

        if candidate.UsesParams != existing.UsesParams {
            return !candidate.UsesParams
        }

        return candidate.DefaultsUsed < existing.DefaultsUsed
    }

    // WHETHER ANY ARGUMENT IS AN ANONYMOUS FUNCTION, which is the only thing the exact-match run has
    // to say anything about.
    static func CallHasLambdaArgument(call: CallExpression): bool {
        arguments := call.Arguments
        for argument in arguments {
            if argument.Value as LambdaExpression != null {
                return true
            }
        }

        return false
    }

    // PHASE 35 — THE NEXT CANDIDATE IN PREFERENCE ORDER, WITH ITS ROLLBACK MARK TAKEN FIRST.
    //
    // A GROUP WHOSE CALL CARRIES A LAMBDA IS WALKED TWICE. §12.6.4.4 prefers the delegate the lambda
    // EXACTLY matches over one it merely converts to, and N# cannot ask that where C# does — a lambda
    // argument has no type until an overload is chosen. So the first run demands the match and the
    // second, reached only when the first bound nothing, accepts every conversion exactly as the walk
    // always did. Nothing a single run used to bind stops binding; a call whose lambda fits one
    // candidate exactly simply stops preferring one that would have swallowed the body's type.
    func BeginNextReflectionCandidate(state: CallAnalysisState): CallAnalysisRequest? {
        candidates := state.ReflectionCandidates
        if candidates == null {
            return FailReflectionBind(state)
        }

        if state.ReflectionCandidateIndex >= candidates.Count {
            if !state.ReflectionRequireExactLambdaMatch {
                return FailReflectionBind(state)
            }

            state.ReflectionRequireExactLambdaMatch = false
            state.ReflectionCandidateIndex = 0
        }

        candidate := candidates[state.ReflectionCandidateIndex]
        state.ReflectionErrorsBefore = diagnostics.ErrorCount
        state.FinalizeState = reflectionArgumentBinder.BeginFinalizeReflectionCall(candidate, state.ReflectionRequireExactLambdaMatch)
        state.Phase = 36
        return null
    }

    // PHASE 36 — ONE CANDIDATE FINALISED, WHICH IS THE INNER WALK RE-EMITTED AS THIS WALK'S OWN STEPS.
    //
    // The finalising walk suspends at every expression it needs analysed, and each of its requests
    // becomes a step of THIS protocol: a lambda request becomes kind 15, which carries the expected
    // type AND the expression-tree flag; anything else becomes kind 4, the target-typed door. That
    // translation is why the two walks COMPOSE rather than nest — there is still one driver, one loop
    // and one protocol, and the driver never learns that an inner walk exists.
    //
    // When the inner walk ends, the candidate either bound or did not. A SINGLE method that did not
    // bind is an unbound call. A GROUP candidate that did not bind has its diagnostics WITHDRAWN and
    // the next candidate is tried — which is the whole reason the sink has a rollback door, and the
    // whole reason the order above must be stable.
    func AdvanceFinalizeReflectionCall(state: CallAnalysisState): CallAnalysisRequest? {
        finalizeState := state.FinalizeState
        if finalizeState == null {
            return FailReflectionBind(state)
        }

        request := reflectionArgumentBinder.NextReflectionAnalysis(finalizeState)
        if request != null {
            state.Pending = 36
            lambda := request.Lambda
            if lambda != null {
                step := new CallAnalysisRequest(15)
                step.Lambda = lambda
                step.CarriedType = request.ExpectedType
                step.Flag = request.IsExpressionTreeTarget
                return step
            }

            step := new CallAnalysisRequest(4)
            step.Node = request.Expression
            step.CarriedType = request.ExpectedType
            return step
        }

        bound := finalizeState.Result
        acceptedPostconditions := finalizeState.Postconditions
        state.FinalizeState = null
        if bound != null {
            // FINALIZER REFUSAL FOLLOWS THE SELECTED METHOD, not the unresolved group. A legal
            // overload may share the name with object.Finalize, and only ordinary overload binding
            // can establish which member this call names.
            if AnalyzerMemberResolution.IsRuntimeFinalizerMethod(finalizeState.RuntimeMethod) {
                ReportFinalizerCall(state.Call)
            }

            // The candidate is the call's now, so its postconditions become the flow's. A candidate
            // that failed has already had its diagnostics withdrawn and leaves nothing behind.
            if acceptedPostconditions != null {
                postconditions.Commit(state.Call, acceptedPostconditions)
            }

            // And so do its reachability facts: a `[DoesNotReturn]` signature ends the path the call
            // is written on, and a `[DoesNotReturnIf(b)]` parameter ends it on the branch its
            // argument selected.
            terminatingGuardArgument: Expression? = null
            guardArgumentIndex := finalizeState.TerminatingGuardArgumentIndex
            if guardArgumentIndex >= 0 && guardArgumentIndex < state.Call.Arguments.Count {
                terminatingGuardArgument = state.Call.Arguments[guardArgumentIndex].Value
            }

            terminatingCalls.Commit(state.Call, finalizeState.TerminatingMethodFacts, terminatingGuardArgument, finalizeState.TerminatingGuardFacts)

            state.NotNullIfNotNullArgumentIndex = finalizeState.NotNullIfNotNullArgumentIndex
            return CompleteReflectionBind(state, bound)
        }

        if state.ReflectionCandidates == null {
            return FailReflectionBind(state)
        }

        if diagnostics.ErrorCount > state.ReflectionErrorsBefore {
            diagnostics.RollbackErrorsTo(state.ReflectionErrorsBefore)
        }

        state.ReflectionCandidateIndex = state.ReflectionCandidateIndex + 1
        state.Phase = 35
        return null
    }

    // NL341, THE RENDERING. The sentence names what the runtime does instead, and the suggestion
    // points at the release mechanism a program can call deterministically.
    func ReportFinalizerCall(call: CallExpression) {
        member := call.Callee as MemberAccessExpression
        if member == null {
            return
        }

        diagnostics.Report(ErrorCode.FinalizerNotCallable, "`" + member.MemberName + "` is the runtime's finalizer and cannot be called from source — the garbage collector calls it, on its own schedule", member.Line, spans.GetMemberNameColumn(member), "Release resources deterministically instead: implement `IDisposable` and call `Dispose()`, or wrap the value in a `using` statement.", Math.Max(1, member.MemberName.Length))
    }

    // A BOUND REFLECTED CALL IS ITS RETURN TYPE — and a bound call with no return type at all is
    // still an unbound call, because there is nothing for the expression to be.
    func CompleteReflectionBind(state: CallAnalysisState, bound: FunctionTypeInfo): CallAnalysisRequest? {
        returnType := bound.ReturnType
        if returnType != null {
            state.Result = returnType
        } else {
            state.Result = reflectionCallReporter.ReportUnboundCall(state.Call, state.CandidateMethods, state.ArgTypes)
        }

        state.Phase = 99
        return null
    }

    // NO CANDIDATE BOUND. The report names every method that was considered and the argument types
    // that were offered, which is one sentence about the CALL rather than one per rejected overload.
    func FailReflectionBind(state: CallAnalysisState): CallAnalysisRequest? {
        // A SURROGATE GROUP THAT BINDS NOTHING SAYS NOTHING. Its candidates are read off an
        // instantiation closed over `object` because the real type argument has no CLR handle yet, so
        // a refusal is the SURROGATE failing to represent the argument and not the program failing to
        // type-check. This is the answer the callee had before the group was resolved at all.
        group := state.ReflectionMethodGroup
        if group != null && group.IsSurrogateBinding {
            state.Result = BuiltInTypes.Unknown
            state.Phase = 99
            return null
        }

        state.Result = reflectionCallReporter.ReportUnboundCall(state.Call, state.CandidateMethods, state.ArgTypes)
        state.Phase = 99
        return null
    }

    // `Ok(x)` AND `Err(e)`, AND THEY ARE A PROBE RATHER THAN A RULE BECAUSE THREE SEPARATE THINGS
    // MAKE THE SAME TWO NAMES AN ORDINARY CALL.
    //
    // The names are only the compiler-known factory where a `Result<T, E>` is being ASKED for — the
    // decision is the expected type's, not the spelling's — and even there only when the name is not
    // bound to a real in-scope symbol. A user who declares their own `Ok` gets their own `Ok`; the
    // resolution is semantic, and hijacking the call on the strength of a name would be exactly the
    // string matching this compiler refuses. All three declining exits leave the walk to carry on as
    // if the probe had never run, and only the LAST of them marks the node — which is why
    // `IsResultFactory` is three-valued: never asked, asked and refused, asked and taken.
    func BeginResultConstructorProbe(state: CallAnalysisState): CallAnalysisRequest? {
        state.Phase = 1
        call := state.Call
        identifier := call.Callee as IdentifierExpression
        if identifier == null {
            return null
        }

        name := identifier.Name
        if name != "Ok" && name != "Err" {
            return null
        }

        okType: TypeInfo = BuiltInTypes.Unknown
        errType: TypeInfo = BuiltInTypes.Unknown
        if !TryGetResultArmTypes(ambient.CurrentExpectedType, out okType, out errType) {
            return null
        }

        // `IsResultFactory` is a THREE-VALUED annotation and the two writes below are the only
        // things that ever narrow it, so each goes through a typed local: a bare `false` is a `bool`
        // and the field is a `bool?`.
        if scopes.LookupSymbol(name) != null {
            refused: bool? = false
            call.IsResultFactory = refused
            return null
        }

        taken: bool? = true
        call.IsResultFactory = taken

        // The arity report comes with the EXPECTED type as the call's answer rather than the
        // constructed one: the program said what it wanted, and a wrong-arity factory should not
        // also change the type everything downstream sees.
        if call.Arguments.Count != 1 {
            diagnostics.Report(ErrorCode.WrongArgumentCount, name + " needs exactly 1 argument, but you passed " + call.Arguments.Count.ToString(), call.Line, call.Column, null, name.Length)
            expectedResult := ambient.CurrentExpectedType
            if expectedResult != null {
                state.Result = expectedResult
            } else {
                state.Result = BuiltInTypes.Unknown
            }

            state.Phase = 99
            return null
        }

        expectedArm := errType
        if name == "Ok" {
            expectedArm = okType
        }

        state.ResultOkType = okType
        state.ResultErrType = errType
        state.ResultExpectedArm = expectedArm
        expectedGeneric := ambient.CurrentExpectedType as GenericTypeInfo
        if expectedGeneric != null {
            state.ResultDefinition = expectedGeneric.GenericDefinition
        }

        state.Phase = 99
        state.Pending = 1
        request := new CallAnalysisRequest(4)
        request.Node = call.Arguments[0].Value
        request.CarriedType = expectedArm
        request.Flag = false
        return request
    }

    // The factory's one argument, typed. A mismatch is reported against the ARM the spelled name
    // selected, and the call still answers a `Result` — a wrong `Ok` value is one error, not two.
    func CompleteResultConstructorProbe(state: CallAnalysisState, answer: TypeInfo?) {
        call := state.Call
        expectedArm: TypeInfo = BuiltInTypes.Unknown
        declaredArm := state.ResultExpectedArm
        if declaredArm != null {
            expectedArm = declaredArm
        }

        actualArm: TypeInfo = BuiltInTypes.Unknown
        if answer != null {
            actualArm = answer
        }

        if !assignability.IsAssignable(expectedArm, actualArm) {
            identifier := call.Callee as IdentifierExpression
            name := "Ok"
            if identifier != null {
                name = identifier.Name
            }

            argumentValue := call.Arguments[0].Value
            diagnostics.Report(ErrorCode.TypeMismatch, name + " expects '" + TypeText(expectedArm) + "', but this argument has type '" + TypeText(actualArm) + "'", argumentValue.Line, argumentValue.Column, null, 0)
        }

        expectedResult := ambient.CurrentExpectedType
        if expectedResult != null {
            state.Result = expectedResult
            return
        }

        okType: TypeInfo = BuiltInTypes.Unknown
        recordedOk := state.ResultOkType
        if recordedOk != null {
            okType = recordedOk
        }

        errType: TypeInfo = BuiltInTypes.Unknown
        recordedErr := state.ResultErrType
        if recordedErr != null {
            errType = recordedErr
        }

        arms := new List<TypeInfo>()
        arms.Add(okType)
        arms.Add(errType)
        state.Result = new GenericTypeInfo("Result", arms, state.ResultDefinition)
    }

    // WHETHER A TYPE IS A `Result<T, E>`, AND ITS TWO ARMS. The definition is checked by DEFINITION
    // IDENTITY — full name, arity and declaring assembly — and never by the spelled name alone, which
    // would accept any two-parameter type someone called `Result`. The NAME is then checked as well,
    // because the same definition reaches the analyzer under three spellings depending on which door
    // resolved it.
    //
    // THE IDENTITY IS ASKED OF THE DEFINITION ITSELF RATHER THAN AGAINST A `Type` FETCHED FROM THE
    // HOST, and that is deliberate. `Analyzer.cs` compared against `typeof(Result<,>)`, a
    // COMPILE-TIME reference that resolves in every host that can run the compiler at all; the
    // nearest N# spelling — an assembly-qualified `Type.GetType` — is a RUNTIME assembly load and
    // answers `null` in any host that has not already loaded the runtime, which would silently turn
    // every `Ok` in the program back into an ordinary call. `AnalyzerDeclarationContext` already owns
    // this exact question for this exact type, needs no anchor, and cannot fail that way.
    static func TryGetResultArmTypes(expected: TypeInfo?, out okType: TypeInfo, out errType: TypeInfo): bool {
        okType = BuiltInTypes.Unknown
        errType = BuiltInTypes.Unknown
        generic := expected as GenericTypeInfo
        if generic == null {
            return false
        }

        arguments := generic.TypeArguments
        if arguments.Count != 2 {
            return false
        }

        if !AnalyzerDeclarationContext.IsRuntimeResultDefinition(generic) {
            return false
        }

        name := generic.Name
        if name != "Result" && name != "NSharpLang.Runtime.Result" && name != "NSharpLang.Runtime.Result`2" {
            return false
        }

        okType = arguments[0]
        errType = arguments[1]
        return true
    }

    // WHAT IS BEING CALLED, and the fork is the grammar's rather than the walk's: a bare name is a
    // CALL TARGET, which is a different resolution from reading the same name as a value — it admits
    // method groups, prefers functions over locals of the same name and reports differently when it
    // finds nothing. Anything else is an expression, analysed under the three callee-position
    // suppressions this owner opens now and closes when the answer comes back.
    func BeginCallee(state: CallAnalysisState): CallAnalysisRequest? {
        call := state.Call
        state.Phase = 2
        identifier := call.Callee as IdentifierExpression
        if identifier != null {
            state.CalleeType = identifierResolution.CallTarget(identifier)
            return null
        }

        state.CalleeFrame = ambient.EnterCallCallee(call.Callee)
        state.Pending = 2
        request := new CallAnalysisRequest(6)
        request.Node = call.Callee
        return request
    }

    // The call's own possible-null report, anchored on the CALLEE.
    //
    // AN INVOCATION HAS NO `?.` OF ITS OWN, BUT ITS CALLEE CAN CARRY ONE, and when it does the whole
    // invocation is guarded: `current?.Invoke(handler)` calls nothing when `current` is null, which
    // is the entire point of writing it that way. Reporting a possible-null call there accused the
    // guard of the fault it prevents, and — because a nullable delegate field is the ordinary way to
    // write "unsubscribe at most once" — it fired on correct code that had no other spelling.
    //
    // The whole receiver SPINE is asked, not just the outermost link: `handler?.Target.Invoke()`
    // short-circuits at the `?.` even though the `.Target` between it and the call does not carry
    // one. Each link's own dereference report is a separate question and is unaffected.
    func EmitPossibleNullCall(state: CallAnalysisState): CallAnalysisRequest? {
        call := state.Call
        state.Phase = 3
        state.Pending = 3
        request := new CallAnalysisRequest(3)
        request.Node = call.Callee
        request.CarriedType = state.CalleeType
        request.Line = call.Line
        request.Column = call.Column
        request.Text = "call"
        request.Flag = IsNullConditionalInvocationTarget(call.Callee)
        return request
    }

    // Whether a null-conditional access anywhere along the callee's receiver spine short-circuits
    // this invocation. The spine walk itself belongs to the chain facts, because the member-access
    // arm and the index arm ask the very same question about their own receivers.
    static func IsNullConditionalInvocationTarget(callee: Expression?): bool {
        return AnalyzerNullConditionalChainFacts.SpineReachesNullGuard(callee)
    }

    // WHICH ARGUMENT SCHEDULE THIS CALL GETS, and it is decided by the callee alone.
    //
    // A function type that declares its parameters can say what each argument is EXPECTED to be, so
    // the placement is bound once here — with `reportErrors: false`, because this is the schedule's
    // question and not its report — and every argument is analysed against a real expected type.
    // Anything else has no expected types to offer.
    func BeginArguments(state: CallAnalysisState): CallAnalysisRequest? {
        call := state.Call
        calleeType := state.CalleeType
        functionType := calleeType as FunctionTypeInfo
        if functionType != null && functionType.ParameterTypes != null {
            state.SyntheticFunctionType = functionType
            state.ParameterStartIndex = AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call)
            functionName := AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call)
            placement: int[] = new int[0]
            if syntheticCallReporter.TryBindAndReport(functionType, functionName, call, out placement, state.ParameterStartIndex, false) {
                state.SyntheticParameterIndexByArgument = placement
            }

            state.Phase = 4
            return null
        }

        // A method group's lambda arguments are analysed LATER, during binding, with a real delegate
        // type in hand. Analysing them here with no expected type would give every lambda parameter
        // `unknown` and produce spurious operator errors inside the body.
        methodGroup := calleeType as ReflectionMethodGroupInfo
        nsharpGroup := calleeType as NSharpMethodGroupInfo
        singleMethod := calleeType as ReflectionMethodInfo
        state.IsMethodGroup = methodGroup != null || nsharpGroup != null || singleMethod != null
        state.ArgumentIndex = 0
        state.Phase = 7
        return null
    }

    // The bindings the argument loop STARTS from: the call's written type arguments and the
    // receiver, and nothing else, because nothing else has been analysed yet. Each argument then
    // re-infers from everything before it — see `EmitSyntheticArgument`.
    func InferArgumentBindings(state: CallAnalysisState): CallAnalysisRequest? {
        functionType := state.SyntheticFunctionType
        if functionType != null {
            state.SyntheticExpectedBindings = syntheticCallWalk.InferGenericBindings(functionType, state.Call, new List<TypeInfo>(), state.ReceiverType)
        }

        state.ArgumentIndex = 0
        state.Phase = 6
        return null
    }

    func EmitSyntheticArgument(state: CallAnalysisState): CallAnalysisRequest? {
        call := state.Call
        functionType := state.SyntheticFunctionType
        index := state.ArgumentIndex
        if functionType == null || index >= call.Arguments.Count {
            state.Phase = 8
            return null
        }

        expectedIndex := index + state.ParameterStartIndex
        placement := state.SyntheticParameterIndexByArgument
        if placement != null {
            expectedIndex = placement[index]
        }

        // C#'s TWO PHASES, RUN AS THE WALK GOES. The bindings are re-inferred from every argument
        // analysed SO FAR before this one's expected type is read, so `Apply(values, v => v.Length)`
        // fixes `T` from `values` and only then hands the lambda `Func<string, R>` to be analysed
        // under. Inferring once up front left every argument measured against a signature nothing
        // had bound: the lambda's parameter had no type, and the first argument was accused of not
        // being a `List<object>`.
        state.SyntheticExpectedBindings = syntheticCallWalk.InferGenericBindings(functionType, call, state.ArgTypes, state.ReceiverType)

        expectedArgumentType := syntheticCallValidator.GetExpectedArgumentType(functionType, call, index, expectedIndex, state.SyntheticExpectedBindings)
        if expectedArgumentType == null {
            return EmitArgument(state, call.Arguments[index], null, false)
        }

        // A POSITION THAT IS STILL OPEN OFFERS NO TARGET, because the surrogate it would offer is a
        // type the program never wrote. The one exception is a DELEGATE: its open position is
        // precisely what the lambda written there is being asked to decide, and its CLOSED positions
        // are what that lambda's parameters need.
        narrowedExpectedType := AnalyzerSyntheticCallFacts.NarrowOpenExpectedArgumentType(expectedArgumentType, functionType.TypeParameters)
        return EmitArgument(state, call.Arguments[index], narrowedExpectedType, false)
    }

    func EmitGroupArgument(state: CallAnalysisState): CallAnalysisRequest? {
        call := state.Call
        index := state.ArgumentIndex
        if index >= call.Arguments.Count {
            state.Phase = 8
            return null
        }

        argument := call.Arguments[index]
        lambda := argument.Value as LambdaExpression
        if state.IsMethodGroup && lambda != null {
            // A method group's lambda argument is DELIBERATELY not analysed here — binding will
            // analyse it later against a real delegate type — but its `ref`/`out` target is still
            // checked, because whether a thing can be written through is a question about the
            // SPELLING and not about the type the lambda turns out to have.
            SkipMethodGroupLambdaArgument(state, argument)
            return null
        }

        // AN ARRAY LITERAL'S VERDICT HERE IS PROVISIONAL, SO ITS COMPLAINTS ARE TOO. A collection
        // expression has no type of its own until a parameter names its element type, and no
        // parameter has been chosen yet: `m.Invoke(null, [1, "two"])` is a perfectly ordinary
        // `object[]`, and inferring it from its FIRST element reported "all elements in an array must
        // be the same type" about a call that is correct. The provisional TYPE is kept — scoring
        // reads it to rank candidates — and the reports are withdrawn, because the bound candidate
        // analyses the same literal again with its own element type and says whatever is true then.
        state.ReflectionArgumentIsUntargeted = state.IsMethodGroup && argument.Value as ArrayLiteralExpression != null
        state.ReflectionArgumentErrorsBefore = diagnostics.ErrorCount
        return EmitArgument(state, argument, null, state.IsMethodGroup)
    }

    // ONE ARGUMENT, AND THE `ref`/`out` FORM IS THIS WALK'S OWN BUSINESS RATHER THAN THE DRIVER'S.
    //
    // An ordinary argument is analysed against its expected type and nothing else happens. A `ref`
    // or `out` argument is four more things: a `?.` chain is refused before anything is analysed at
    // all; the expected type is the BYREF's INNER type, because the program writes a `T` through a
    // `ref T`; the write-target table is open across the analysis so the classifiers read the chain
    // the walk already produced instead of re-walking it and reporting twice; and the answer comes
    // back wrapped in `ByRefTypeInfo`. The DRIVER performs the same operation either way — analyse
    // this expression with that expected type — which is why there is one kind and not two.
    func EmitArgument(state: CallAnalysisState, argument: Argument, expectedType: TypeInfo?, allowUnbound: bool): CallAnalysisRequest? {
        errorsBefore := diagnostics.ErrorCount
        modifier := RefOutModifier(argument)
        if modifier == null {
            state.Pending = 4
            plain := new CallAnalysisRequest(4)
            plain.Node = argument.Value
            plain.CarriedType = expectedType
            plain.Flag = allowUnbound
            return plain
        }

        // A null-conditional target ENDS this argument: the C# returned `unknown` without analysing
        // it, and the follow-up report stays silent because this one already fired.
        if writeTargets.ReportNullConditionalWriteTargetIfNeeded(argument.Value, "used as the " + modifier + " argument") {
            // This argument ends here, so the withdrawal bracket a group pass may have opened around
            // it is CLOSED rather than applied: the report just made is about the spelling and is not
            // the provisional verdict the bracket exists to withdraw.
            state.ReflectionArgumentIsUntargeted = false
            state.ArgTypes.Add(BuiltInTypes.Unknown)
            state.ArgumentIndex = state.ArgumentIndex + 1
            return null
        }

        targetExpectedType := expectedType
        expectedByRef := expectedType as ByRefTypeInfo
        if expectedByRef != null {
            targetExpectedType = expectedByRef.InnerType
        }

        state.RefOutArgument = argument
        state.RefOutModifier = modifier
        state.RefOutErrorsBefore = errorsBefore
        state.RefOutSavedExpressionTypes = ambient.EnterWriteTargetExpressionTypes()
        state.RefOutExpressionTypes = ambient.WriteTargetExpressionTypes
        state.Pending = 4
        request := new CallAnalysisRequest(4)
        request.Node = argument.Value
        request.CarriedType = targetExpectedType
        request.Flag = allowUnbound
        return request
    }

    // The answer to one argument analysis. The `ref`/`out` form closes its bracket FIRST, wraps, and
    // only then asks whether the target could have been written through — the order the two C#
    // members ran in, and it matters: the report reads the table the bracket collected.
    func CompleteArgument(state: CallAnalysisState, answer: TypeInfo?) {
        WithdrawUntargetedCollectionReports(state)
        argument := state.RefOutArgument
        if argument == null {
            ordinary: TypeInfo = BuiltInTypes.Unknown
            if answer != null {
                ordinary = answer
            }

            state.ArgTypes.Add(ordinary)
            state.ArgumentIndex = state.ArgumentIndex + 1
            return
        }

        ambient.ExitWriteTargetExpressionTypes(state.RefOutSavedExpressionTypes)
        modifier := "ref"
        recordedModifier := state.RefOutModifier
        if recordedModifier != null {
            modifier = recordedModifier
        }

        resolved: TypeInfo = BuiltInTypes.Unknown
        if answer != null {
            resolved = answer
            if !BuiltInTypes.IsUnknown(resolved) {
                // The `out` SPELLING TRAVELS WITH THE ARGUMENT'S TYPE, because assignability is where
                // the two sides of a by-ref position meet and it has no other way to learn which of
                // `ref` and `out` was written. An `out` variable's incoming nullability is the
                // callee's to replace; a `ref` one's is part of the contract.
                resolved = new ByRefTypeInfo(resolved, argument.Modifier == ArgumentModifier.Out)
            }
        }

        ReportRefOutTargetIfNeeded(argument, modifier, state.RefOutErrorsBefore, state.RefOutExpressionTypes)
        state.RefOutArgument = null
        state.RefOutModifier = null
        state.RefOutSavedExpressionTypes = null
        state.RefOutExpressionTypes = null
        state.ArgTypes.Add(resolved)
        state.ArgumentIndex = state.ArgumentIndex + 1
    }

    // THE WITHDRAWAL ITSELF, shared by the two passes that analyse an argument with nothing in the
    // target-typing slot. It runs on EVERY completion and does nothing unless the flag was set, so
    // neither pass can leave a bracket open for the argument after it.
    func WithdrawUntargetedCollectionReports(state: CallAnalysisState) {
        if !state.ReflectionArgumentIsUntargeted {
            return
        }

        state.ReflectionArgumentIsUntargeted = false
        if diagnostics.ErrorCount > state.ReflectionArgumentErrorsBefore {
            diagnostics.RollbackErrorsTo(state.ReflectionArgumentErrorsBefore)
        }
    }

    // The un-analysed method-group lambda. Its argument type is `unknown` — nothing was analysed —
    // and the target report runs against the CURRENT diagnostic count, so it is never suppressed by
    // something an earlier argument reported.
    func SkipMethodGroupLambdaArgument(state: CallAnalysisState, argument: Argument) {
        modifier := RefOutModifier(argument)
        if modifier != null {
            ReportRefOutTargetIfNeeded(argument, modifier, diagnostics.ErrorCount, null)
        }

        state.ArgTypes.Add(BuiltInTypes.Unknown)
        state.ArgumentIndex = state.ArgumentIndex + 1
    }

    // WHETHER A `ref`/`out` ARGUMENT NAMES SOMETHING THAT CAN BE WRITTEN THROUGH, in the one order
    // the four refusals have always run.
    //
    // THE FIRST GUARD IS NOT A SHAPE TEST BUT A SILENCE ONE: if the argument's own analysis already
    // reported, this rule says nothing. A target that failed to resolve is not ALSO an unassignable
    // target, and telling the developer both would name the wrong problem twice. Everything after it
    // is `AnalyzerWriteTargets`' — the same four rules the assignment arm and the increment operand
    // ask, with `used as the ref argument` as the action — and the generic refusal is what is left
    // when all four decline and the target is still not addressable.
    func ReportRefOutTargetIfNeeded(argument: Argument, modifier: string, errorsBefore: int, expressionTypes: Dictionary<object, TypeInfo>?): bool {
        if diagnostics.ErrorCount != errorsBefore {
            return false
        }

        action := "used as the " + modifier + " argument"
        if writeTargets.ReportNullConditionalWriteTargetIfNeeded(argument.Value, action) {
            return true
        }

        if writeTargets.ReportSoaTableMemberMutationIfNeeded(argument.Value, expressionTypes, action) || writeTargets.ReportUnsupportedBuiltInIndexedMutationIfNeeded(argument.Value, expressionTypes, action) {
            return true
        }

        if writeTargets.ReportReadonlyFieldRefOutArgumentIfNeeded(argument.Value, modifier, expressionTypes) {
            return true
        }

        // A READ-ONLY REFERENCE MAY NOT BE HANDED ON AS A WRITABLE ONE. Passing an `in` parameter as a
        // `ref` or an `out` would let the next callee write storage this one promised not to.
        if (modifier == "ref" || modifier == "out") && writeTargets.ReportInParameterRefOutArgumentIfNeeded(argument.Value, modifier) {
            return true
        }

        if writeTargets.IsRefOutArgumentTarget(argument.Value, expressionTypes) {
            return false
        }

        span := spans.GetExpressionDiagnosticSpan(argument.Value)
        diagnostics.Report(ErrorCode.InvalidSyntax, "The '" + modifier + "' argument needs an assignable target", span.Line, span.Column, "Use a variable, field, or indexed array/SoA column element as the " + modifier + " argument.", span.Length)
        return true
    }

    // `ref` or `out` as the diagnostics spell it, and `null` for every other argument — which is the
    // test for "this is an ordinary argument" as well as the word the sentences are built from.
    static func RefOutModifier(argument: Argument): string? {
        if argument.Modifier == ArgumentModifier.Ref {
            return "ref"
        }

        if argument.Modifier == ArgumentModifier.Out {
            return "out"
        }

        return null
    }

    // An SoA row view passed as an argument escapes the table it views, one report per offending
    // argument in argument order.
    func EmitSoaRowEscape(state: CallAnalysisState): CallAnalysisRequest? {
        call := state.Call
        while state.EscapeIndex < state.ArgTypes.Count {
            index := state.EscapeIndex
            state.EscapeIndex = index + 1
            soaRow := state.ArgTypes[index] as SoaRowTypeInfo
            if soaRow != null {
                state.Pending = 7
                request := new CallAnalysisRequest(7)
                request.Node = call.Arguments[index].Value
                request.Text = "passed as an argument"
                return request
            }
        }

        state.Phase = 9
        return null
    }

    // THE SoA DIRECT-COLUMN CALL RULE. Its four gates run in the one order they have always run and
    // the first that fires ends the call at `unknown`, but that ordering is now the RULE's and not
    // the walk's — the walk needs one verdict, so it asks once.
    func EmitSoaGate(state: CallAnalysisState): CallAnalysisRequest? {
        state.Phase = 13
        state.Pending = 8
        request := new CallAnalysisRequest(8)
        request.CarriedType = state.CalleeType
        return request
    }

    // WHAT THE CALL'S TYPE COMES FROM, chosen by the callee's own type and nothing else.
    func Dispatch(state: CallAnalysisState): CallAnalysisRequest? {
        call := state.Call
        calleeType := state.CalleeType

        funcType := calleeType as FunctionTypeInfo
        if funcType != null {
            if funcType.ParameterTypes != null {
                state.SyntheticFunctionType = funcType
                state.Phase = 14
                return null
            }

            declaredReturnType := funcType.ReturnType
            if declaredReturnType != null {
                state.Result = declaredReturnType
            } else {
                state.Result = BuiltInTypes.Void
            }

            state.Phase = 99
            return null
        }

        singleMethod := calleeType as ReflectionMethodInfo
        if singleMethod != null {
            state.CandidateMethods.Add(singleMethod.Method)
            state.ReflectionSingleMethod = singleMethod.Method
            state.Phase = 30
            return null
        }

        methodGroup := calleeType as ReflectionMethodGroupInfo
        if methodGroup != null {
            methods := methodGroup.Methods
            for method in methods {
                state.CandidateMethods.Add(method)
            }

            state.ReflectionMethodGroup = methodGroup
            state.Phase = 30
            return null
        }

        newtypeInfo := calleeType as NewtypeInfo
        if newtypeInfo != null {
            ValidateNewtypeConstruction(state, newtypeInfo)
            state.Result = newtypeInfo
            state.Phase = 99
            return null
        }

        nsharpGroup := calleeType as NSharpMethodGroupInfo
        if nsharpGroup != null {
            functions := NSharpMethodGroupInfoFactory.GetFunctions(nsharpGroup)
            if functions.Count > 0 {
                state.GroupFunctions = functions
                state.Phase = 18
                return null
            }
        }

        state.Result = BuiltInTypes.Unknown
        state.Phase = 99
        return null
    }

    // A NEWTYPE CONSTRUCTION IS ONE ARGUMENT ASSIGNABLE TO THE UNDERLYING TYPE, and the arity check
    // comes first: an argument-type report against a construction the user did not even spell with
    // one argument would name the wrong problem.
    func ValidateNewtypeConstruction(state: CallAnalysisState, newtypeInfo: NewtypeInfo) {
        call := state.Call
        if call.Arguments.Count != 1 {
            diagnostics.Report(ErrorCode.InvalidSyntax, "Newtype '" + newtypeInfo.Name + "' constructor expects exactly 1 argument but got " + call.Arguments.Count.ToString(), call.Line, call.Column, null, 0)
            return
        }

        underlyingType := typeSubstitution.ResolveTypeForSourceOwner(newtypeInfo.UnderlyingType, newtypeInfo, null)
        argumentType := state.ArgTypes[0]
        if assignability.IsAssignable(underlyingType, argumentType) {
            return
        }

        diagnostics.Report(ErrorCode.TypeMismatch, "Cannot construct '" + newtypeInfo.Name + "': argument of type '" + TypeText(argumentType) + "' is not assignable to underlying type '" + TypeText(underlyingType) + "'", call.Line, call.Column, null, 0)
    }

    // THE DECLARED-FUNCTION TAIL. Validation reads the receiver, then the return type reads it
    // AGAIN — two separate analyses, because that is what the two calls have always done and each
    // one reports.
    func AdvanceFunctionTypeReturn(state: CallAnalysisState, phase: int): CallAnalysisRequest? {
        functionType := state.SyntheticFunctionType
        if functionType == null {
            state.Result = BuiltInTypes.Unknown
            state.Phase = 99
            return null
        }

        if phase == 14 {
            return AcquireReceiver(state, AnalyzerSyntheticCallWalk.NeedsReceiverType(functionType, state.Call), 15)
        }

        if phase == 15 {
            syntheticCallValidator.ValidateCall(functionType, state.Call, state.ArgTypes, state.ReceiverType)
            state.Phase = 16
            return null
        }

        if phase == 16 {
            return AcquireReceiver(state, AnalyzerSyntheticCallWalk.NeedsReceiverType(functionType, state.Call), 17)
        }

        state.Result = syntheticCallValidator.ResolveReturnType(functionType, state.Call, state.ArgTypes, state.ReceiverType)
        state.Phase = 99
        return null
    }

    // THE N#-DECLARED OVERLOAD-GROUP TAIL, and the reason this whole owner is a resumable walk.
    //
    // The receiver is read once so the GROUP can be scored, and the winner decides whether it is
    // read the other two times: a chosen overload that is not receiver-style generic never reaches
    // the inference arm, so a call whose group holds one candidate that needs the receiver and one
    // that does not fires the receiver ONCE, not three times. Measured, not assumed.
    func AdvanceMethodGroupReturn(state: CallAnalysisState, phase: int): CallAnalysisRequest? {
        functions := state.GroupFunctions
        if functions == null {
            state.Result = BuiltInTypes.Unknown
            state.Phase = 99
            return null
        }

        if phase == 18 {
            return AcquireReceiver(state, syntheticCallWalk.AnyCandidateNeedsReceiverType(functions, state.Call, state.ArgTypes), 19)
        }

        if phase == 19 {
            bound := syntheticCallWalk.BindNSharpCall(functions, state.Call, state.ArgTypes, state.ReceiverType)
            if bound == null {
                syntheticCallValidator.ReportNoMatchingOverload(functions, state.Call, state.ArgTypes)
                state.Result = BuiltInTypes.Unknown
                state.Phase = 99
                return null
            }

            state.BoundFunction = bound
            state.Phase = 20
            state.Pending = 14
            request := new CallAnalysisRequest(14)
            request.CarriedType = bound
            return request
        }

        boundFunction := state.BoundFunction
        if boundFunction == null {
            state.Result = BuiltInTypes.Unknown
            state.Phase = 99
            return null
        }

        if phase == 20 {
            return AcquireReceiver(state, AnalyzerSyntheticCallWalk.NeedsReceiverType(boundFunction, state.Call), 21)
        }

        if phase == 21 {
            syntheticCallValidator.ValidateCall(boundFunction, state.Call, state.ArgTypes, state.ReceiverType)
            state.Phase = 22
            return null
        }

        if phase == 22 {
            return AcquireReceiver(state, AnalyzerSyntheticCallWalk.NeedsReceiverType(boundFunction, state.Call), 23)
        }

        state.Result = syntheticCallValidator.ResolveReturnType(boundFunction, state.Call, state.ArgTypes, state.ReceiverType)
        state.Phase = 99
        return null
    }

    // THE RECEIVER GUARD, STATED ONCE. A receiver is read only when the inference walk will read it
    // AND the call is spelled through a member access; anything else leaves the receiver type null,
    // which is the same answer the inline expression it replaces produced.
    func AcquireReceiver(state: CallAnalysisState, needed: bool, nextPhase: int): CallAnalysisRequest? {
        state.ReceiverType = null
        state.Phase = nextPhase
        if !needed {
            return null
        }

        memberAccess := state.Call.Callee as MemberAccessExpression
        if memberAccess == null {
            return null
        }

        state.Pending = 6
        request := new CallAnalysisRequest(16)
        request.Node = memberAccess.Object
        return request
    }

    // A resolved type's own display form, read through an `object`-typed local because `ToString`
    // is declared by the BASE of the TypeInfo hierarchy rather than by the hierarchy itself.
    static func TypeText(resolved: TypeInfo): string {
        boxed: object = resolved
        rendered := boxed.ToString()
        if rendered == null {
            return ""
        }

        return rendered
    }
}

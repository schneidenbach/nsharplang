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
// The kinds, in the order the walk can emit them:
//   1  the `Ok`/`Err` result-constructor probe (answers a type AND whether it applied)
//   2  the callee's own analysis
//   3  the possible-null-call report
//   4  one argument analysed with `CarriedType` as its expected type
//   5  one argument DELIBERATELY NOT analysed — the method-group lambda, which is analysed later
//      during binding with a real delegate type; the ref/out target report still runs
//   6  the member-access RECEIVER's analysis
//   7  one SoA row-view escape report
//   8  the SoA direct-column call rule (answers only whether it reported). The four gates under it
//      are ONE owner's, so the walk asks once; kinds 9, 10 and 11 are the round trips that relayed
//      them one at a time before that owner existed, and the gap is left where they were because a
//      step kind is a value the contracts pin.
//   12 a single reflected method's binding
//   13 a reflected method GROUP's binding
//   14 the semantic-model record for a bound N# overload
class CallAnalysisRequest {
    Kind: int
    Node: Expression?
    ArgumentNode: Argument?
    CarriedType: TypeInfo?
    Method: MethodInfo?
    MethodGroup: ReflectionMethodGroupInfo?
    Text: string?
    Line: int
    Column: int
    Flag: bool

    constructor(kind: int) {
        Kind = kind
        Node = null
        ArgumentNode = null
        CarriedType = null
        Method = null
        MethodGroup = null
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

    // The call expression's type. `unknown` is the walk's own final answer for a callee it does not
    // recognise, so it is the honest starting value rather than a null placeholder.
    Result: TypeInfo

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
        Result = BuiltInTypes.Unknown
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
// AND THE COUNT IS USER-VISIBLE, WHICH IS WHY IT IS PRESERVED EXACTLY. A receiver whose own analysis
// reports — an arity error, a missing member, an unbound name, a bad argument — reports again on
// every repeat: 27 of 30 measured triple-fires reported THREE times, and `nlc build` renders the
// same NL401 twelve times on a `Bad(1, 2).Tag("x")` receiver where the analyses are four per pass.
// `nlc check` distincts its result set and hides this; the unsorted build transcript does not.
//
// The receiver's own GUARD stays here for the same reason it did in `AnalyzerSyntheticCallWalk`:
// the driver may not analyse an expression the walk would not have analysed, nor skip one it would.
class AnalyzerCallAnalysis {
    syntheticCallReporter: AnalyzerSyntheticCallReporter
    syntheticCallWalk: AnalyzerSyntheticCallWalk
    syntheticCallValidator: AnalyzerSyntheticCallValidator
    reflectionCallReporter: AnalyzerReflectionCallReporter
    typeSubstitution: AnalyzerTypeSubstitution
    assignability: AnalyzerAssignability
    diagnostics: AnalyzerDiagnosticSink

    constructor(callReporter: AnalyzerSyntheticCallReporter, callWalk: AnalyzerSyntheticCallWalk, callValidator: AnalyzerSyntheticCallValidator, reflectionReporter: AnalyzerReflectionCallReporter, substitution: AnalyzerTypeSubstitution, assignabilityOwner: AnalyzerAssignability, diagnosticSink: AnalyzerDiagnosticSink) {
        syntheticCallReporter = callReporter
        syntheticCallWalk = callWalk
        syntheticCallValidator = callValidator
        reflectionCallReporter = reflectionReporter
        typeSubstitution = substitution
        assignability = assignabilityOwner
        diagnostics = diagnosticSink
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

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP, folded in according to what was asked. `handled` is the
    // boolean verdict of the probe steps — the result-constructor factory and the direct-column rule —
    // and each of those ENDS the walk, exactly as the early `return` it replaces did.
    func SupplyCallStep(state: CallAnalysisState, answer: TypeInfo?, handled: bool) {
        pending := state.Pending
        state.Pending = 0

        if pending == 1 {
            if handled {
                if answer != null {
                    state.Result = answer
                }

                state.Phase = 99
            }

            return
        }

        if pending == 2 {
            state.CalleeType = answer
            return
        }

        if pending == 4 || pending == 5 {
            argumentType: TypeInfo = BuiltInTypes.Unknown
            if pending == 4 && answer != null {
                argumentType = answer
            }

            state.ArgTypes.Add(argumentType)
            state.ArgumentIndex = state.ArgumentIndex + 1
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

        if pending == 12 || pending == 13 {
            bound := answer as FunctionTypeInfo
            returnType: TypeInfo? = null
            if bound != null {
                returnType = bound.ReturnType
            }

            if returnType != null {
                state.Result = returnType
            } else {
                state.Result = reflectionCallReporter.ReportUnboundCall(state.Call, state.CandidateMethods, state.ArgTypes)
            }
        }
    }

    // ONE TURN OF THE WALK: a request when the next thing to happen is the driver's, otherwise null
    // with the phase moved on.
    func AdvanceCall(state: CallAnalysisState): CallAnalysisRequest? {
        phase := state.Phase
        if phase == 0 {
            state.Phase = 1
            state.Pending = 1
            return new CallAnalysisRequest(1)
        }

        if phase == 1 {
            state.Phase = 2
            state.Pending = 2
            return new CallAnalysisRequest(2)
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

        if phase >= 14 && phase <= 17 {
            return AdvanceFunctionTypeReturn(state, phase)
        }

        return AdvanceMethodGroupReturn(state, phase)
    }

    // The call's own possible-null report, anchored on the CALLEE and never null-conditional: a
    // call has no `?.` form of its own.
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
        request.Flag = false
        return request
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

    // The per-argument expected types, computed ONCE from the receiver-closed bindings and never
    // rewritten inside the argument loop: an argument's expected type is a function of the
    // signature and the call's own type arguments, not of the arguments analysed before it.
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

        state.Pending = 4
        request := new CallAnalysisRequest(4)
        request.ArgumentNode = call.Arguments[index]
        request.CarriedType = syntheticCallValidator.GetExpectedArgumentType(functionType, call, index, expectedIndex, state.SyntheticExpectedBindings)
        request.Flag = false
        return request
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
            state.Pending = 5
            skipped := new CallAnalysisRequest(5)
            skipped.ArgumentNode = argument
            return skipped
        }

        state.Pending = 4
        request := new CallAnalysisRequest(4)
        request.ArgumentNode = argument
        request.CarriedType = null
        request.Flag = state.IsMethodGroup
        return request
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
            state.Phase = 99
            state.Pending = 12
            request := new CallAnalysisRequest(12)
            request.Method = singleMethod.Method
            return request
        }

        methodGroup := calleeType as ReflectionMethodGroupInfo
        if methodGroup != null {
            methods := methodGroup.Methods
            methodIndex := 0
            while methodIndex < methods.Length {
                state.CandidateMethods.Add(methods[methodIndex])
                methodIndex = methodIndex + 1
            }

            state.Phase = 99
            state.Pending = 13
            request := new CallAnalysisRequest(13)
            request.MethodGroup = methodGroup
            return request
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
        request := new CallAnalysisRequest(6)
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

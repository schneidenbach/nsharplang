namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// WHAT A CALL PROVES ABOUT ITS ARGUMENTS ONCE IT HAS RETURNED — the postcondition authority.
//
// THREE RULES, AND THEY COMPOSE IN THIS ORDER. An `out` (or `ref`) argument's variable is written by
// the callee, so after the call it holds whatever the PARAMETER's declared nullability says: `out
// string` leaves a non-null string, `out string?` leaves a maybe-null one. A `[NotNull]` on any
// parameter overrides that and holds unconditionally, which is the whole of `Assert.NotNull`. And a
// `[NotNullWhen(b)]` / `[MaybeNullWhen(b)]` makes the fact CONDITIONAL on the call's own boolean
// result — the named branch gets the attribute's state, and the other branch keeps what the
// declaration alone already said.
//
// `[MaybeNull]` IS ASYMMETRIC ON PURPOSE. On an `out` or `ref` parameter it is a postcondition and
// leaves the variable maybe-null. On an INPUT parameter it is a statement about what the callee will
// do with the value, not about the caller's variable, so it proves nothing here. `[NotNull]` has no
// such split: on an input parameter it is exactly the `Assert.NotNull` guarantee.
//
// CONDITIONAL FACTS, AND THE UNCONDITIONAL FACTS THAT ARE SAFE ON BOTH BRANCHES, ARE FILED AGAINST
// THE CALL NODE. A call in a condition is analysed BEFORE the `if` walk asks what the condition
// proves, so those facts have to survive the gap between the two; the flow-narrowing writer reads
// them back when it meets the same node. Unconditional maybe-null facts are deliberately NOT filed:
// branch narrowings are installed over the whole condition and would otherwise erase a fact that
// must hold when a right operand was skipped. Unconditional facts are also written into the live
// flow the moment the call is decided — including the invalidation an ordinary assignment performs,
// because an `out` argument IS an assignment and every fact derived from that path is stale
// afterwards.
//
// A CANDIDATE THAT LOSES LEAVES NOTHING BEHIND. Facts are produced while a candidate is being bound
// and COMMITTED only when the call's walk accepts one, so a reflected overload that was tried,
// reported and rolled back cannot leave a fact about a binding that did not happen.
class AnalyzerNullabilityPostconditions {
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    branchFactsByCall: Dictionary<object, List<NullabilityPostcondition>>

    constructor(scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext) {
        scopesValue = scopes
        declarationContextValue = declarationContext
        branchFactsByCall = new Dictionary<object, List<NullabilityPostcondition>>()
    }

    // One call per analysis, from the same reset block that clears the error list.
    func BeginAnalysis() {
        branchFactsByCall.Clear()
    }

    // THE FACTS ONE ARGUMENT POSITION PRODUCES. `parameterType` is the parameter as the call site
    // resolved it — generic bindings applied, by-ref shell already removed — and `flowFacts` is what
    // its attributes said.
    func AddArgumentFacts(facts: List<NullabilityPostcondition>, argument: Argument, parameterType: TypeInfo, isByRefParameter: bool, flowFacts: int) {
        path := AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(argument.Value)
        if path == null {
            return
        }

        if NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.NotNull()) {
            facts.Add(new NullabilityPostcondition(path, 0, NullState.NotNull, isByRefParameter))
            return
        }

        if isByRefParameter && NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.MaybeNull()) {
            facts.Add(new NullabilityPostcondition(path, 0, NullState.MaybeNull, true))
            return
        }

        declaredState := DeclaredParameterState(parameterType)
        conditional := false
        if NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.NotNullWhenTrue()) {
            facts.Add(new NullabilityPostcondition(path, 1, NullState.NotNull))
            conditional = true
        }

        if NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.NotNullWhenFalse()) {
            facts.Add(new NullabilityPostcondition(path, 2, NullState.NotNull))
            conditional = true
        }

        if NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.MaybeNullWhenTrue()) {
            facts.Add(new NullabilityPostcondition(path, 1, NullState.MaybeNull))
            conditional = true
        }

        if NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.MaybeNullWhenFalse()) {
            facts.Add(new NullabilityPostcondition(path, 2, NullState.MaybeNull))
            conditional = true
        }

        if !isByRefParameter || declaredState == NullState.Unknown {
            return
        }

        // The DECLARATION's own answer. Unconditional when no attribute spoke, and otherwise the
        // fact the branch the attribute did NOT name falls back to.
        if !conditional {
            facts.Add(new NullabilityPostcondition(path, 0, declaredState, true))
            return
        }

        AddFallbackBranchFact(facts, path, declaredState, flowFacts)
    }

    // The branch an attribute left unspoken keeps what the declaration said. Written as two explicit
    // questions rather than as a negation, because an attribute may name BOTH branches and then
    // neither fallback applies.
    func AddFallbackBranchFact(facts: List<NullabilityPostcondition>, path: string, declaredState: NullState, flowFacts: int) {
        trueSpoken := NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.NotNullWhenTrue()) || NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.MaybeNullWhenTrue())
        falseSpoken := NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.NotNullWhenFalse()) || NullabilityFlowFacts.Has(flowFacts, NullabilityFlowFacts.MaybeNullWhenFalse())
        if !trueSpoken {
            facts.Add(new NullabilityPostcondition(path, 1, declaredState))
        }

        if !falseSpoken {
            facts.Add(new NullabilityPostcondition(path, 2, declaredState))
        }
    }

    // WHAT A PARAMETER'S DECLARED TYPE SAYS ITS VALUE WILL BE — the SAME question a dereference is
    // judged against, so it is the same rule: `NullStateFacts.DefaultFor`. A nullable annotation is
    // maybe-null, metadata written without a nullable context is OBLIVIOUS rather than confidently
    // either, and only an error-recovery `unknown` says nothing at all.
    func DeclaredParameterState(parameterType: TypeInfo): NullState {
        return NullStateFacts.DefaultFor(declarationContextValue.ResolveDeclaredAlias(parameterType))
    }

    // `[MemberNotNull]` names members on the instance the method was called on. The same parsed
    // facts are used for source signatures and reflected CustomAttributeData; only the receiver is a
    // call-site fact. Unqualified source instance calls denote `this` and are recognized from their
    // source member signature. A static method never contributes a receiver fact.
    func AddMemberPostconditions(call: CallExpression, memberFacts: NullabilityMemberPostcondition[]?, isStatic: bool, sourceContainingType: string?, facts: List<NullabilityPostcondition>) {
        if isStatic || memberFacts == null || memberFacts.Length == 0 {
            return
        }

        receiverPath: string? = null
        memberAccess := call.Callee as MemberAccessExpression
        if memberAccess != null {
            receiverPath = AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(memberAccess.Object)
        } else if sourceContainingType != null && (call.Callee as IdentifierExpression) != null {
            receiverPath = "this"
        }

        if receiverPath == null {
            return
        }

        for memberFact in memberFacts {
            condition := memberFact.Condition
            if condition < NullabilityMemberPostconditions.Always() || condition > NullabilityMemberPostconditions.WhenFalse() {
                continue
            }

            facts.Add(new NullabilityPostcondition(receiverPath + "." + memberFact.MemberName, condition, NullState.NotNull))
        }
    }

    // A reflected method uses the exact same fact parser as source declarations. `sourceContainingType`
    // is null because the receiver comes only from the written member-access expression.
    func AddReflectedMemberPostconditions(call: CallExpression, attributes: IList<CustomAttributeData>, isStatic: bool, facts: List<NullabilityPostcondition>) {
        memberFacts := NullabilityMemberPostconditions.FromReflectionAttributes(attributes)
        AddMemberPostconditions(call, memberFacts, isStatic, null, facts)
    }

    // THE CALL'S VERDICT. The unconditional facts go into the flow now; branch facts are also filed
    // against the node so a containing condition can recover them after the call's walk has ended.
    func Commit(call: CallExpression, facts: List<NullabilityPostcondition>) {
        branchFacts: List<NullabilityPostcondition>? = null
        index := 0
        while index < facts.Count {
            fact := facts[index]
            index = index + 1
            if fact.Condition != 0 {
                if branchFacts == null {
                    branchFacts = new List<NullabilityPostcondition>()
                }

                branchFacts.Add(fact)
                continue
            }

            // These states are valid whenever the call ran, regardless of its boolean result. The
            // condition writer chooses the appropriate side of a short-circuit operator; maybe-null
            // is intentionally absent because that branch fact could cover a path where the call
            // never ran.
            if fact.State == NullState.NotNull || fact.State == NullState.Oblivious {
                if branchFacts == null {
                    branchFacts = new List<NullabilityPostcondition>()
                }

                branchFacts.Add(new NullabilityPostcondition(fact.Path, 1, fact.State))
                branchFacts.Add(new NullabilityPostcondition(fact.Path, 2, fact.State))
            }

            if fact.Assigned {
                scopesValue.InvalidateNullFactsForAssignment(fact.Path)
            }

            scopesValue.SetNullStateInCurrentScope(fact.Path, fact.State)
        }

        if branchFacts != null {
            branchFactsByCall[call] = branchFacts
        } else {
            branchFactsByCall.Remove(call)
        }
    }

    // The narrowings a condition that IS a call proves on one of its two branches. Null when the call
    // established nothing, which is the overwhelmingly common case and the one the narrowing writer
    // must not pay for.
    func BranchNarrowings(call: CallExpression, whenTrue: bool): List<FlowNarrowing>? {
        facts: List<NullabilityPostcondition>? = null
        if !branchFactsByCall.TryGetValue(call, out facts) || facts == null {
            return null
        }

        wanted := 2
        if whenTrue {
            wanted = 1
        }

        narrowings: List<FlowNarrowing>? = null
        index := 0
        while index < facts.Count {
            fact := facts[index]
            index = index + 1
            if fact.Condition != wanted {
                continue
            }

            if narrowings == null {
                narrowings = new List<FlowNarrowing>()
            }

            narrowings.Add(new FlowNarrowing(fact.Path, null, fact.State))
        }

        return narrowings
    }
}

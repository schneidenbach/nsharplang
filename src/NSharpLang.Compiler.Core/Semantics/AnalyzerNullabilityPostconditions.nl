namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
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
// THE CONDITIONAL FACTS ARE FILED AGAINST THE CALL NODE, NOT APPLIED. A call in a condition is
// analysed BEFORE the `if` walk asks what the condition proves, so the facts have to survive the gap
// between the two; the flow-narrowing writer reads them back when it meets the same node. The
// unconditional ones have no such gap and are written into the flow the moment the call is decided —
// including the invalidation an ordinary assignment performs, because an `out` argument IS an
// assignment and every fact derived from that path is stale afterwards.
//
// A CANDIDATE THAT LOSES LEAVES NOTHING BEHIND. Facts are produced while a candidate is being bound
// and COMMITTED only when the call's walk accepts one, so a reflected overload that was tried,
// reported and rolled back cannot leave a fact about a binding that did not happen.
class AnalyzerNullabilityPostconditions {
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    conditionalByCall: Dictionary<object, List<NullabilityPostcondition>>

    constructor(scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext) {
        scopesValue = scopes
        declarationContextValue = declarationContext
        conditionalByCall = new Dictionary<object, List<NullabilityPostcondition>>()
    }

    // One call per analysis, from the same reset block that clears the error list.
    func BeginAnalysis() {
        conditionalByCall.Clear()
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

    // THE CALL'S VERDICT. The unconditional facts go into the flow now; the conditional ones are
    // filed against the node so the condition that contains it can read them back.
    func Commit(call: CallExpression, facts: List<NullabilityPostcondition>) {
        conditional: List<NullabilityPostcondition>? = null
        index := 0
        while index < facts.Count {
            fact := facts[index]
            index = index + 1
            if fact.Condition != 0 {
                if conditional == null {
                    conditional = new List<NullabilityPostcondition>()
                }

                conditional.Add(fact)
                continue
            }

            if fact.Assigned {
                scopesValue.InvalidateNullFactsForAssignment(fact.Path)
            }

            scopesValue.SetNullStateInCurrentScope(fact.Path, fact.State)
        }

        if conditional != null {
            conditionalByCall[call] = conditional
        } else {
            conditionalByCall.Remove(call)
        }
    }

    // The narrowings a condition that IS a call proves on one of its two branches. Null when the call
    // established nothing, which is the overwhelmingly common case and the one the narrowing writer
    // must not pay for.
    func BranchNarrowings(call: CallExpression, whenTrue: bool): List<FlowNarrowing>? {
        facts: List<NullabilityPostcondition>? = null
        if !conditionalByCall.TryGetValue(call, out facts) || facts == null {
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

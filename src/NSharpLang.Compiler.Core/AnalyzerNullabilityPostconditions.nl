namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// THE NULLABILITY ATTRIBUTES A SIGNATURE USES TO SAY WHAT IT LEAVES BEHIND, as a bit set.
//
// A DECLARED TYPE SAYS WHAT A VALUE IS; THESE SAY WHAT IT BECOMES. `Dictionary<K, V>.TryGetValue`
// hands back a `V` that is present only when the call returned true, and no type spells that —
// `[MaybeNullWhen(false)]` does. `Assert.NotNull(object? value)` takes something that may be null and
// guarantees it is not once the call returns, which is `[NotNull]`. `string.IsNullOrEmpty` proves its
// argument non-null in the branch where it answered FALSE, which is `[NotNullWhen(false)]`.
//
// THE BITS ARE READ FROM BOTH SIDES OF THE SAME FENCE. A reflected member carries them as
// `CustomAttributeData` and a source-declared one as `AttributeNode`s the parser kept; the same
// vocabulary is produced from either, so one rule reads both and a source signature can say exactly
// what a BCL signature says.
class NullabilityFlowFacts {
    static func None(): int {
        return 0
    }

    static func NotNull(): int {
        return 1
    }

    static func MaybeNull(): int {
        return 2
    }

    static func NotNullWhenTrue(): int {
        return 4
    }

    static func NotNullWhenFalse(): int {
        return 8
    }

    static func MaybeNullWhenTrue(): int {
        return 16
    }

    static func MaybeNullWhenFalse(): int {
        return 32
    }

    static func Has(facts: int, bit: int): bool {
        return (facts & bit) != 0
    }

    // The bit a `[NotNullWhen(b)]` / `[MaybeNullWhen(b)]` contributes, given which boolean it names.
    static func WhenBit(notNull: bool, whenTrue: bool): int {
        if notNull {
            if whenTrue {
                return NotNullWhenTrue()
            }

            return NotNullWhenFalse()
        }

        if whenTrue {
            return MaybeNullWhenTrue()
        }

        return MaybeNullWhenFalse()
    }

    // THE ATTRIBUTE NAMES, MATCHED THE WAY EVERY OTHER ATTRIBUTE IN THIS COMPILER IS MATCHED: the
    // bare name, the `Attribute`-suffixed name, and either of those namespace-qualified.
    static func IsNotNullName(name: string): bool {
        return MatchesAttributeName(name, "NotNull")
    }

    static func IsMaybeNullName(name: string): bool {
        return MatchesAttributeName(name, "MaybeNull")
    }

    static func IsNotNullWhenName(name: string): bool {
        return MatchesAttributeName(name, "NotNullWhen")
    }

    static func IsMaybeNullWhenName(name: string): bool {
        return MatchesAttributeName(name, "MaybeNullWhen")
    }

    static func IsNotNullIfNotNullName(name: string): bool {
        return MatchesAttributeName(name, "NotNullIfNotNull")
    }

    static func MatchesAttributeName(name: string, bareName: string): bool {
        return NominalTypeInfoFactory.AttributeNameEquals(name, bareName) || NominalTypeInfoFactory.AttributeNameEquals(name, bareName + "Attribute") || NominalTypeInfoFactory.AttributeNameEndsWith(name, "." + bareName) || NominalTypeInfoFactory.AttributeNameEndsWith(name, "." + bareName + "Attribute")
    }

    // The facts a SOURCE declaration's attribute list carries. An attribute whose boolean argument is
    // not a literal contributes nothing: a condition this reader cannot see is not one it may invent.
    static func FromSourceAttributes(attributes: List<AttributeNode>?): int {
        if attributes == null {
            return None()
        }

        facts := None()
        index := 0
        while index < attributes.Count {
            attribute := attributes[index]
            index = index + 1
            name := attribute.Name
            if IsNotNullName(name) {
                facts = facts | NotNull()
                continue
            }

            if IsMaybeNullName(name) {
                facts = facts | MaybeNull()
                continue
            }

            isNotNullWhen := IsNotNullWhenName(name)
            if !isNotNullWhen && !IsMaybeNullWhenName(name) {
                continue
            }

            literal: bool = false
            if TryReadSourceBooleanArgument(attribute, out literal) {
                facts = facts | WhenBit(isNotNullWhen, literal)
            }
        }

        return facts
    }

    static func TryReadSourceBooleanArgument(attribute: AttributeNode, out value: bool): bool {
        value = false
        if attribute.Arguments.Count != 1 {
            return false
        }

        literal := attribute.Arguments[0].Value as BoolLiteralExpression
        if literal == null {
            return false
        }

        value = literal.Value
        return true
    }
}

// The reflection half of the same reader. It is separate for the reason the nullability metadata
// reader is separate: everything above is a pure function of names and literals, and everything here
// touches `CustomAttributeData`, whose `Count` lives on a non-generic interface and whose boolean
// argument arrives BOXED — under a MetadataLoadContext the argument's own `ArgumentType` is a
// projected `System.Boolean` that is not `typeof(bool)`, so the value is compared against a boxed
// constant instead.
class NullabilityFlowAttributeReflection {
    static func FromParameter(parameter: ParameterInfo): int {
        return FromAttributes(parameter.GetCustomAttributesData())
    }

    static func FromAttributes(attributes: IList<CustomAttributeData>): int {
        facts := NullabilityFlowFacts.None()
        falseValue: object = false
        trueValue: object = true
        count := NullabilityMetadataReflection.SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            index = index + 1
            name := attribute.get_AttributeType().FullName ?? ""
            if NullabilityFlowFacts.IsNotNullName(name) {
                facts = facts | NullabilityFlowFacts.NotNull()
                continue
            }

            if NullabilityFlowFacts.IsMaybeNullName(name) {
                facts = facts | NullabilityFlowFacts.MaybeNull()
                continue
            }

            isNotNullWhen := NullabilityFlowFacts.IsNotNullWhenName(name)
            if !isNotNullWhen && !NullabilityFlowFacts.IsMaybeNullWhenName(name) {
                continue
            }

            constructorArguments := attribute.get_ConstructorArguments()
            if NullabilityMetadataReflection.SequenceCount(constructorArguments) != 1 {
                continue
            }

            argumentValue := constructorArguments.get_Item(0).get_Value()
            if argumentValue == null {
                continue
            }

            boxedValue: object = argumentValue
            if boxedValue.Equals(trueValue) {
                facts = facts | NullabilityFlowFacts.WhenBit(isNotNullWhen, true)
            } else if boxedValue.Equals(falseValue) {
                facts = facts | NullabilityFlowFacts.WhenBit(isNotNullWhen, false)
            }
        }

        return facts
    }

    // The parameter name a `[NotNullIfNotNull("x")]` on a RETURN points at.
    static func NotNullIfNotNull(attributes: IList<CustomAttributeData>): string? {
        count := NullabilityMetadataReflection.SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            index = index + 1
            if !NullabilityFlowFacts.IsNotNullIfNotNullName(attribute.get_AttributeType().FullName ?? "") {
                continue
            }

            constructorArguments := attribute.get_ConstructorArguments()
            if NullabilityMetadataReflection.SequenceCount(constructorArguments) != 1 {
                continue
            }

            argumentName := constructorArguments.get_Item(0).get_Value() as string
            if argumentName != null {
                return argumentName
            }
        }

        return null
    }
}

// ONE FACT A CALL LEAVES BEHIND ABOUT A NAME IT WAS HANDED.
//
// `Condition` is what makes this more than a null state: a postcondition can hold unconditionally
// (`Assert.NotNull(x)` — `x` is not null from here on), or only on the branch the call's own boolean
// result selects (`dict.TryGetValue(k, out v)` — `v` is present in the TRUE branch and absent in the
// false one). The two are recorded the same way and applied in different places, which is why the
// distinction lives in the fact rather than in two collections.
class NullabilityPostcondition {
    pathValue: string
    conditionValue: int
    stateValue: NullState
    assignedValue: bool

    Path: string => pathValue

    // 0 — holds however the call turned out. 1 — holds when the call returned true. 2 — when false.
    Condition: int => conditionValue
    State: NullState => stateValue

    // Whether the callee WROTE this path. An `out`/`ref` argument is an assignment and everything
    // derived from the path is stale afterwards; `Assert.NotNull(x)` writes nothing, so a fact
    // already proved about `x.y` survives it.
    Assigned: bool => assignedValue

    constructor(path: string, condition: int, state: NullState, assigned: bool = false) {
        pathValue = path
        conditionValue = condition
        stateValue = state
        assignedValue = assigned
    }
}

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

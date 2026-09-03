namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// THE STEPS AN EXPRESSION TAKES WHEN IT CHOOSES WHAT ITS OPERANDS ARE TYPED AGAINST.
//
// The two kinds are the two DOORS into the expression walk, and which door a step takes is the whole
// of what this family decides:
//   1  analyse an expression under WHATEVER TARGET TYPE IS ALREADY IN FORCE. The surrounding slot is
//      left exactly as it was found — this is the ordinary walk every other driver's kind 1 is.
//   2  analyse an expression under a NAMED expected type. This is not the same operation with an
//      extra argument: it forks to the lambda walk for a lambda operand, it brackets the
//      target-typing slot for everything else, and it saves and restores the unbound-callable
//      permission around the walk. A `checked` operand CAN be a bare lambda — the grammar parses the
//      parenthesised operand with the full expression production, whose first alternative is
//      `x => …` — so this kind cannot be simulated by the owner writing the slot itself around a
//      kind 1.
//
// THERE WAS A THIRD KIND AND IT IS GONE. A ternary's answer is the COMMON TYPE of its two arms, and
// while numeric widening lived in the host that common type had to be asked for as a step. The
// operator arms and their promotion tables are N#-owned now, so the ternary calls
// `AnalyzerOperatorExpressions.CommonType` directly and the driver lost a kind.
//
// `ExpectedType` is the operand of kind 2 and is null for kind 1. The numbering is this walk's own
// protocol with its own driver and starts at 1; the other walks' numbers mean different operations.
class TargetTypedOperandRequest {
    Kind: int
    Node: Expression?
    ExpectedType: TypeInfo?
    Line: int
    Column: int

    constructor(kind: int, node: Expression?, expectedType: TypeInfo?, line: int, column: int) {
        Kind = kind
        Node = node
        ExpectedType = expectedType
        Line = line
        Column = column
    }
}

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` names which of the four this is — 0 a cast, 1 `checked`, 2 `unchecked`, 3 a ternary, and -1
// for a node that is none of them.
//
// `ResultType` is decided AFTER the steps, never at `Begin`: a cast answers its written target type,
// `checked` and `unchecked` answer their operand, and a ternary answers the common type of its two
// arms — or `unknown` when a row view escaped through any of them.
//
// `OperandType` is the outstanding step's answer, folded in by `Supply`. A ternary consumes it three
// times and keeps two of them: `ThenType` and `ElseType` are the two the common type is taken over,
// and they are kept because both escape reports run over BOTH arms before either is used.
//
// `CastTargetType` is the cast's written target resolved BEFORE its operand is walked — the order is
// observable, because resolving a type reference reports. `ExpectedResultType` is the ternary's copy
// of the target-typing slot as it stood when the walk was entered, which is the type both arms are
// walked under; it is read once, at entry, because the condition's own bracket restores the slot and
// a walk that read it later would be reading a value that had been out and back.
class TargetTypedOperandState {
    formValue: int
    nodeValue: Expression?

    Form: int => formValue
    Node: Expression? => nodeValue

    Phase: int
    Pending: int
    OperandType: TypeInfo
    ResultType: TypeInfo
    CastTargetType: TypeInfo
    ExpectedResultType: TypeInfo?
    ThenType: TypeInfo
    ElseType: TypeInfo

    reachabilityValue: AnalyzerPatternReachability?

    // THE CONVERSION ORACLE, CARRIED RATHER THAN HELD, for the same reason `AnalyzerPassThroughOperands`
    // carries it: `Analyzer.cs` REBUILDS `_patternReachability` whenever the metadata load context
    // creates the well-known types, so an owner that held one would hold a stale one. It is optional
    // because a walk driven without it — every hand-built contract in the estate — still answers every
    // question about types; only the conversion REPORT needs an oracle.
    Reachability: AnalyzerPatternReachability? => reachabilityValue

    constructor(form: int, node: Expression?, reachability: AnalyzerPatternReachability?) {
        formValue = form
        nodeValue = node
        reachabilityValue = reachability
        Phase = 0
        Pending = 0
        OperandType = BuiltInTypes.Unknown
        ResultType = BuiltInTypes.Unknown
        CastTargetType = BuiltInTypes.Unknown
        ExpectedResultType = null
        ThenType = BuiltInTypes.Unknown
        ElseType = BuiltInTypes.Unknown
    }
}

// WHAT AN EXPRESSION THAT CHOOSES THE TYPE ITS OPERANDS ARE WALKED UNDER MEANS.
//
// FOUR FORMS, ONE QUESTION. A cast, a `checked`, an `unchecked` and a ternary are the expression
// walk's arms whose steps are TARGET-TYPED: each of them decides, from the node alone, what expected
// type each operand is analysed against, and that decision is the whole of what separates them from
// the arms that came before. The family before this one handed its operands through untouched; these
// four reach into the target-typing slot on the way in.
//
// IT OWNS WHAT EACH OF THE FOUR IS:
//   * that a CAST is its written target type whatever its operand turned out to be, that the target
//     is resolved BEFORE the operand is walked — leniently, so a cast to a type that does not exist
//     is not an error here — and that its operand is walked under that target ONLY when the cast is
//     a hard one over a `default` or a `new()`. That restriction is the one place in the estate that
//     picks a door from the node alone, and it is observable: `(int)default` knows what to be and
//     `default as int` does not, because the second is a SAFE cast and takes the other door;
//   * that a `checked` and an `unchecked` are their operand's type unchanged, and that they hand the
//     surrounding expected type BACK to the walk rather than replacing or clearing it — which on the
//     slot alone is an identity, and is not one for a lambda operand, whose walk the named-expected-
//     type door forks to;
//   * that a TERNARY walks its condition under `bool` and BOTH arms under the type the ternary
//     itself was asked for — read once, at entry — that its condition is told when it is not a
//     boolean, that all four of its row-escape reports run and none of them stops another, and that
//     its answer is the common type of the two arms, or `unknown` when any of the four fired.
//
// THIS FAMILY RAISES NO DIAGNOSTIC OF ITS OWN. Every report it makes belongs to a collaborator — the
// SoA escape reporter, the boolean-condition reporter, and whatever the type resolver says about a
// written type reference — which is why it holds no diagnostic sink and no span reader.
//
// IT IS AN OBJECT RATHER THAN A STATIC because its four facts are ambient: the type resolver a cast's
// target is read through, the SoA escape reporter all four forms use, the target-typing slot two of
// them read, and the condition reporter the ternary asks. All four are constructed exactly once by
// `Analyzer.cs` and none is rebuilt with the metadata load context, so holding them is safe.
class AnalyzerTargetTypedOperands {
    typeResolverValue: AnalyzerTypeResolver
    soaEscapeValue: AnalyzerSoaEscape
    ambientValue: AnalyzerAmbientContext
    conditionsValue: AnalyzerBooleanConditions

    constructor(typeResolver: AnalyzerTypeResolver, soaEscape: AnalyzerSoaEscape, ambient: AnalyzerAmbientContext, conditions: AnalyzerBooleanConditions) {
        typeResolverValue = typeResolver
        soaEscapeValue = soaEscape
        ambientValue = ambient
        conditionsValue = conditions
    }

    // THE ENTRY, AND IT DECIDES NOTHING. No form in this family can answer or report before its first
    // operand has been walked, so `Begin` names the form and stops. A node that is none of the four
    // answers `unknown` and takes no steps.
    func Begin(expression: Expression, patternReachability: AnalyzerPatternReachability? = null): TargetTypedOperandState {
        return new TargetTypedOperandState(FormOf(expression), expression, patternReachability)
    }

    // WHICH OF THE FOUR THIS NODE IS, derived from the NODE rather than from anything carried, which
    // is the rule slice 50 paid for: an instrument that reads the form off the state measures it one
    // report too late.
    static func FormOf(expression: Expression): int {
        castNode := expression as CastExpression
        if castNode != null {
            return 0
        }

        checkedNode := expression as CheckedExpression
        if checkedNode != null {
            return 1
        }

        uncheckedNode := expression as UncheckedExpression
        if uncheckedNode != null {
            return 2
        }

        ternaryNode := expression as TernaryExpression
        if ternaryNode != null {
            return 3
        }

        return -1
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    func NextStep(state: TargetTypedOperandState): TargetTypedOperandRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. A walk that asked for nothing folds in nothing, and a null
    // answer is `unknown` rather than a missing one — the expression walk never answers null, and a
    // walk that saw one would otherwise carry it into a report.
    func Supply(state: TargetTypedOperandState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending == 0 {
            return
        }

        if answer != null {
            state.OperandType = answer
        } else {
            state.OperandType = BuiltInTypes.Unknown
        }
    }

    // WHAT THE WALK ANSWERS, which is what the dispatch hands to its caller.
    func Result(state: TargetTypedOperandState): TypeInfo {
        return state.ResultType
    }

    func Advance(state: TargetTypedOperandState): TargetTypedOperandRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceEntry(state)
        }

        if phase == 1 {
            return AdvanceWrapperFinish(state)
        }

        if phase == 2 {
            return AdvanceTernaryCondition(state)
        }

        if phase == 3 {
            return AdvanceTernaryThen(state)
        }

        if phase == 4 {
            return AdvanceTernaryElse(state)
        }

        state.Phase = 99
        return null
    }

    // THE FORK, AND IT IS BETWEEN "ONE OPERAND UNDER A CHOSEN TYPE" AND "A CONDITION AND TWO ARMS".
    // The three single-operand forms differ only in WHICH type they choose: a cast its own target
    // behind the door test, `checked` and `unchecked` the type already in force.
    //
    // A cast resolves its target FIRST. That is not bookkeeping: the resolution can report, so a cast
    // to a broken type reference is told about it before anything its operand has to say.
    func AdvanceEntry(state: TargetTypedOperandState): TargetTypedOperandRequest? {
        node := state.Node

        castNode := node as CastExpression
        if castNode != null {
            targetType := typeResolverValue.ResolveType(castNode.TargetType)
            state.CastTargetType = targetType
            state.Pending = 1
            state.Phase = 1
            operand := castNode.Expression
            if UsesCastTargetExpectedType(castNode) {
                return new TargetTypedOperandRequest(2, operand, targetType, operand.Line, operand.Column)
            }

            return new TargetTypedOperandRequest(1, operand, null, operand.Line, operand.Column)
        }

        checkedNode := node as CheckedExpression
        if checkedNode != null {
            state.Pending = 1
            state.Phase = 1
            checkedOperand := checkedNode.Expression
            return new TargetTypedOperandRequest(2, checkedOperand, ambientValue.CurrentExpectedType, checkedOperand.Line, checkedOperand.Column)
        }

        uncheckedNode := node as UncheckedExpression
        if uncheckedNode != null {
            state.Pending = 1
            state.Phase = 1
            uncheckedOperand := uncheckedNode.Expression
            return new TargetTypedOperandRequest(2, uncheckedOperand, ambientValue.CurrentExpectedType, uncheckedOperand.Line, uncheckedOperand.Column)
        }

        ternaryNode := node as TernaryExpression
        if ternaryNode != null {
            state.ExpectedResultType = ambientValue.CurrentExpectedType
            state.Pending = 1
            state.Phase = 2
            condition := ternaryNode.Condition
            return new TargetTypedOperandRequest(2, condition, BuiltInTypes.Bool, condition.Line, condition.Column)
        }

        state.Phase = 99
        return null
    }

    // WHAT THE THREE SINGLE-OPERAND FORMS MEAN, ASKED ONCE THE OPERAND IS KNOWN.
    func AdvanceWrapperFinish(state: TargetTypedOperandState): TargetTypedOperandRequest? {
        state.Phase = 99
        node := state.Node

        castNode := node as CastExpression
        if castNode != null {
            FinishCast(state, castNode)
            return null
        }

        checkedNode := node as CheckedExpression
        if checkedNode != null {
            FinishChecked(state, checkedNode)
            return null
        }

        uncheckedNode := node as UncheckedExpression
        if uncheckedNode != null {
            FinishUnchecked(state, uncheckedNode)
            return null
        }

        return null
    }

    // WHICH DOOR A CAST'S OPERAND GOES THROUGH, DECIDED FROM THE NODE ALONE. A hard cast over a
    // `default` or a bare `new()` is the one shape where the cast's own target is the only thing that
    // can tell the operand what to be, so it is pushed. Everything else — including a SAFE cast over
    // the very same operand — is walked under whatever type was already in force, because a cast is
    // an assertion about the RESULT and not an instruction about the operand.
    static func UsesCastTargetExpectedType(castNode: CastExpression): bool {
        if castNode.Kind != CastKind.Hard {
            return false
        }

        defaultNode := castNode.Expression as DefaultExpression
        if defaultNode != null {
            return true
        }

        newNode := castNode.Expression as NewExpression
        return newNode != null && newNode.Type == null
    }

    // A CAST IS ITS WRITTEN TARGET TYPE, and neither escape changes that except by refusing outright.
    // The operand's own type is consulted for exactly one thing — whether it is a row view — and is
    // never the answer.
    func FinishCast(state: TargetTypedOperandState, castNode: CastExpression) {
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(castNode.Expression, state.OperandType, "cast") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(castNode.Expression, "cast") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        // AND THE ONE QUESTION A CAST WAS NEVER ASKED: does any conversion exist at all? The escapes
        // above are about a row VIEW leaving its table; this is about the assertion the cast makes.
        // It is asked last, so a value that already escaped is not also told about its type.
        reachability := state.Reachability
        if reachability != null {
            reachability.CheckCastExpression(castNode, state.OperandType, state.CastTargetType)
        }

        state.ResultType = state.CastTargetType
    }

    // A `checked` IS ITS OPERAND. Overflow behaviour is a code-generation question; to the analyzer
    // the wrapper changes nothing about the type, and its ONE refusal is the row escape — a direct
    // column value inside a `checked` is somebody else's objection, which is why this arm asks only
    // the first of the two questions the cast asks.
    func FinishChecked(state: TargetTypedOperandState, checkedNode: CheckedExpression) {
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(checkedNode.Expression, state.OperandType, "used in a checked expression") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        state.ResultType = state.OperandType
    }

    // AN `unchecked` IS ITS OPERAND, on the same terms and with the same single refusal. The two are
    // separate members rather than one because the wording they hand the escape reporter is part of
    // what the programmer reads.
    func FinishUnchecked(state: TargetTypedOperandState, uncheckedNode: UncheckedExpression) {
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(uncheckedNode.Expression, state.OperandType, "used in an unchecked expression") {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        state.ResultType = state.OperandType
    }

    // THE CONDITION HAS ANSWERED. It is told whether it is a boolean BEFORE either arm is walked, so
    // a ternary on a non-boolean reports once, in front of anything its arms have to say.
    func AdvanceTernaryCondition(state: TargetTypedOperandState): TargetTypedOperandRequest? {
        ternaryNode := state.Node as TernaryExpression
        if ternaryNode == null {
            state.Phase = 99
            return null
        }

        conditionsValue.ReportConditionTypeMismatchIfNeeded(ternaryNode.Condition, "a ternary expression", "used as a ternary condition", state.OperandType)
        state.Pending = 1
        state.Phase = 3
        thenExpression := ternaryNode.ThenExpression
        return new TargetTypedOperandRequest(2, thenExpression, state.ExpectedResultType, thenExpression.Line, thenExpression.Column)
    }

    // THE THEN ARM HAS ANSWERED, and the else arm is walked under the SAME expected type. Neither arm
    // is measured against the other: a ternary is not an assignment, and the two arms are two
    // independent answers to the same question until the common type is taken.
    func AdvanceTernaryThen(state: TargetTypedOperandState): TargetTypedOperandRequest? {
        ternaryNode := state.Node as TernaryExpression
        if ternaryNode == null {
            state.Phase = 99
            return null
        }

        state.ThenType = state.OperandType
        state.Pending = 1
        state.Phase = 4
        elseExpression := ternaryNode.ElseExpression
        return new TargetTypedOperandRequest(2, elseExpression, state.ExpectedResultType, elseExpression.Line, elseExpression.Column)
    }

    // BOTH ARMS HAVE ANSWERED, AND ALL FOUR REPORTS RUN. None of them stops another: a ternary whose
    // arms are both row views is told about both, because both of them really are trying to leave.
    // Any of the four firing makes the whole expression `unknown` and the common type is not even
    // asked for — there is nothing left to take a common type OF.
    func AdvanceTernaryElse(state: TargetTypedOperandState): TargetTypedOperandRequest? {
        ternaryNode := state.Node as TernaryExpression
        if ternaryNode == null {
            state.Phase = 99
            return null
        }

        state.ElseType = state.OperandType
        thenEscaped := soaEscapeValue.ReportSoaRowEscapeIfNeeded(ternaryNode.ThenExpression, state.ThenType, "used as a ternary result")
        elseEscaped := soaEscapeValue.ReportSoaRowEscapeIfNeeded(ternaryNode.ElseExpression, state.ElseType, "used as a ternary result")
        thenColumnEscaped := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(ternaryNode.ThenExpression, "used as a ternary result")
        elseColumnEscaped := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(ternaryNode.ElseExpression, "used as a ternary result")
        if thenEscaped || elseEscaped || thenColumnEscaped || elseColumnEscaped {
            state.ResultType = BuiltInTypes.Unknown
            state.Phase = 99
            return null
        }

        // THE COMMON TYPE IS THE ANSWER. A ternary is worth exactly what both of its arms can be at
        // once. This was a STEP while numeric widening lived in the host; the operator arms own the
        // promotion tables now, so it is a call and the walk ends here.
        state.ResultType = AnalyzerOperatorExpressions.CommonType(state.ThenType, state.ElseType)
        state.Phase = 99
        return null
    }
}

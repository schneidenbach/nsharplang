namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHICH CALLS END THE PATH THEY ARE WRITTEN ON — the one owner both the diagnostics pass and the
// emitter ask, so `[DoesNotReturn]` means the same thing on both sides of the compiler.
//
// A CALL THAT NEVER RETURNS IS A `throw` THE SIGNATURE SPELLS. `ThrowHelper.Fail(message)` is
// declared `void`, and the only thing that says it never gets there is `[DoesNotReturn]`. Once that
// is believed, the function whose last statement is such a call is COMPLETE — there is nothing after
// it to return from — and a statement written after one is unreachable exactly as it is after a
// `throw`. Both of those are `AnalyzerStatementTermination`'s questions, which is why they are
// answered here rather than at either of the rules that ask.
//
// A CALL THAT NEVER RETURNS ON ONE BRANCH IS A GUARD CLAUSE THE SIGNATURE SPELLS.
// `Debug.Assert(condition)` is `[DoesNotReturnIf(false)] bool condition`: the call returns only when
// the condition held, so the statement AFTER it knows what the condition proved. That is exactly
// `assert`'s rule, and it reaches the same flow-narrowing writer through the same request the
// `assert` statement uses — an argument node and the branch the surviving flow took.
//
// THE FACTS ARE FILED AGAINST THE CALL NODE, AND COMMITTED ONLY WHEN A CANDIDATE IS ACCEPTED. A
// reflected overload that was tried, reported and rolled back must leave nothing behind, which is
// the same discipline `AnalyzerNullabilityPostconditions` follows for the same reason.
//
// IT IS ANALYSIS STATE, AND THAT IS WHY THE TERMINATION JUDGEMENT TAKES IT AS A PARAMETER. Every
// rule that asks the judgement asks it AFTER the statement in question has been analysed — the
// missing-return rule after the whole body, the unreachable rule after each statement, the
// guard-clause rule after both branches — so all three see the same answer, which is what keeps a
// pure-AST judgement and a fact-bearing one from disagreeing.
class AnalyzerTerminatingCalls {
    neverReturningCalls: HashSet<object>
    guardArgumentByCall: Dictionary<object, Expression>
    guardSurvivesWhenTrue: Dictionary<object, bool>

    constructor() {
        neverReturningCalls = new HashSet<object>()
        guardArgumentByCall = new Dictionary<object, Expression>()
        guardSurvivesWhenTrue = new Dictionary<object, bool>()
    }

    // One call per analysis, from the same reset block that clears the error list.
    func BeginAnalysis() {
        neverReturningCalls.Clear()
        guardArgumentByCall.Clear()
        guardSurvivesWhenTrue.Clear()
    }

    // THE CALL'S VERDICT, from whichever binder accepted a candidate. A signature with neither
    // attribute clears both facts rather than leaving an older one standing, because the same node
    // is re-analysed whenever the file is.
    func Commit(call: CallExpression, methodFacts: int, guardArgument: Expression?, guardFacts: int) {
        if call == null {
            return
        }

        if ReachabilityFlowFacts.Has(methodFacts, ReachabilityFlowFacts.DoesNotReturn()) {
            neverReturningCalls.Add(call)
        } else {
            neverReturningCalls.Remove(call)
        }

        guardArgumentByCall.Remove(call)
        guardSurvivesWhenTrue.Remove(call)
        if guardArgument == null {
            return
        }

        // `[DoesNotReturnIf(false)]` leaves the surviving flow on the TRUE branch, and
        // `[DoesNotReturnIf(true)]` on the false one. A parameter that somehow carries both says the
        // call never returns at all, which no flow can act on, so neither fact is filed.
        doesNotReturnIfTrue := ReachabilityFlowFacts.Has(guardFacts, ReachabilityFlowFacts.DoesNotReturnIfTrue())
        doesNotReturnIfFalse := ReachabilityFlowFacts.Has(guardFacts, ReachabilityFlowFacts.DoesNotReturnIfFalse())
        if doesNotReturnIfTrue == doesNotReturnIfFalse {
            return
        }

        guardArgumentByCall[call] = guardArgument
        guardSurvivesWhenTrue[call] = doesNotReturnIfFalse
    }

    // DOES THIS STATEMENT'S EXPRESSION END THE PATH? A parenthesised call is the same call, and
    // anything that is not a call answers no.
    func NeverReturns(expression: Expression?): bool {
        call := UnwrapCall(expression)
        return call != null && neverReturningCalls.Contains(call)
    }

    // THE ARGUMENT A `[DoesNotReturnIf]` NAMED, and the branch the surviving flow is on. Null when
    // the call guards nothing, which is the overwhelmingly common case.
    func TryGetGuard(expression: Expression?, out guardArgument: Expression, out survivesWhenTrue: bool): bool {
        guardArgument = null
        survivesWhenTrue = false
        call := UnwrapCall(expression)
        if call == null || !guardArgumentByCall.TryGetValue(call, out guardArgument) {
            return false
        }

        return guardSurvivesWhenTrue.TryGetValue(call, out survivesWhenTrue)
    }

    static func UnwrapCall(expression: Expression?): CallExpression? {
        current := expression
        steps := 0
        while current != null && steps < 64 {
            call := current as CallExpression
            if call != null {
                return call
            }

            parenthesized := current as ParenthesizedExpression
            if parenthesized == null {
                return null
            }

            current = parenthesized.Inner
            steps = steps + 1
        }

        return null
    }
}

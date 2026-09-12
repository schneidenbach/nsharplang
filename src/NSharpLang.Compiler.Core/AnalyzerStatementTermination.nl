namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHETHER A STATEMENT ALWAYS LEAVES — the analyzer's one control-flow-termination judgement, the two
// questions it answers, and the three unrelated rules that read it.
//
// THE FIRST QUESTION IS "DOES EVERY PATH THROUGH THIS STATEMENT END IN A `return` OR A `throw`", and
// two rules ask it. A function body is asked so a non-void function that can fall off its end is told
// to return something. Every statement in a LIST is asked so the statement after one that always
// leaves is reported as unreachable. That is `AlwaysReturns`.
//
// THE SECOND QUESTION IS "DOES EVERY PATH THROUGH THIS STATEMENT LEAVE THE BLOCK THAT CONTAINS IT",
// and one rule asks it: the GUARD CLAUSE. `if x == null { return }` hands the surviving flow the
// facts the branch it did not take proved, and `if x == null { break }` and `if x == null { continue }`
// hand it exactly the same facts for exactly the same reason — the branch is gone, so what survives is
// the flow the condition was false on. C# narrows all three (the branch's end point is unreachable in
// every case), and the loop spelling is what converted C# is made of: one converted project had 66
// sites of it. That is `AlwaysLeaves`.
//
// THE TWO ARE ONE WALK WITH TWO ENTRY POINTS, and that is the whole design. `AlwaysReturns` is
// `AlwaysLeaves` with `break` and `continue` NOT counted as leaving, so the two can never disagree
// about any shape that contains neither. A second walk would be two things to keep in step.
//
// `break` AND `continue` TRAVEL SEPARATELY BECAUSE THEY BIND TO DIFFERENT CONSTRUCTS. A `break` inside
// a `switch` inside the branch leaves the SWITCH and not the branch, so descending into a switch stops
// counting `break` — while a `continue` inside that same switch still leaves the enclosing loop, which
// is outside the branch, so it keeps counting. A `finally` block counts neither, because a jump out of
// one is not legal IL. And a loop body is never descended into at all, so the question never arises
// there.
//
// IT IS PURE OVER THE AST AND THEREFORE STATIC. It declares no symbol, opens no scope, re-enters no
// walk, reads no scope stack and reports no diagnostic. It is asked at points that are far apart in
// the analysis — the `if` walk asks after both branches have run, the list walk asks after each
// statement, the function rule asks after the whole body — and it must answer the same thing at all
// three, which it does because nothing it reads is analysis state.
//
// A PARSER ERROR PLACEHOLDER IS NOT A RETURN. `return <error>` and `throw <error>` are text the
// recovery parser could not read, and a SYNTAX diagnostic has already been reported about them. They
// answer FALSE, which means the function that contains one is ALSO told it is missing a return —
// deliberately, because the alternative is to silently accept a body whose only return is broken
// text. This is the one thing in the judgement that is not structural.
//
// THE UNMODELLED ANSWER IS "NO", AND THAT IS THE SAFE DIRECTION. Every statement shape this walk does
// not name — a loop, a `using`, a bare expression, a local function — answers FALSE. A `while true`
// whose body never breaks does leave every path, and this walk says it does not; the cost is a
// missing-return complaint a developer resolves by writing the return, which is a false POSITIVE on a
// rule whose false NEGATIVE would be unverifiable IL.
//
// `try` IS THE ONE SHAPE WHERE THAT CONSERVATISM WOULD BE WRONG RATHER THAN MERELY COSTLY, because
// C#'s `using` lowers to it. It follows C#'s end-point rule exactly: the guarded block and every
// handler must leave, OR the `finally` must leave by itself. A `try` with a `finally` and no handler
// therefore leaves whenever its body does.
//
// A SWITCH IS THE ONLY SHAPE THAT REASONS ABOUT COMPLETENESS. It leaves only when it has a `default`
// case and EVERY case — the default included — contains at least one statement that leaves. A case
// whose body is empty therefore refutes the whole switch, and so does a switch with no default, no
// matter how exhaustive its patterns look: exhaustiveness over a union is the MATCH family's
// judgement, and this one deliberately does not borrow it.
class AnalyzerStatementTermination {

    // DOES EVERY PATH THROUGH THIS STATEMENT END IN A `return` OR A `throw`? The missing-return rule
    // and the unreachable-code rule ask this one, and neither of them may treat a `break` out of a
    // loop as a way out of the FUNCTION — so both jumps are off.
    static func AlwaysReturns(statement: Statement): bool {
        return Walk(statement, false, false)
    }

    // DOES EVERY PATH THROUGH THIS STATEMENT LEAVE THE BLOCK THAT CONTAINS IT? The guard-clause rule
    // asks this one about an `if` branch, where a `break` and a `continue` are as final as a `return`.
    static func AlwaysLeaves(statement: Statement): bool {
        return Walk(statement, true, true)
    }

    // THE WALK. The shapes are tested in the order `Analyzer.cs` wrote them. That order is not
    // behaviour — every shape named here is a direct subclass of `Statement` and no two of them can
    // match the same node — but it is preserved so the two walks are readable against each other.
    static func Walk(statement: Statement, breakLeaves: bool, continueLeaves: bool): bool {
        returnStatement := statement as ReturnStatement
        if returnStatement != null {
            returnedValue := returnStatement.Value
            if returnedValue == null {
                return true
            }

            return !AnalyzerParserErrorPlaceholders.ContainsInExpression(returnedValue)
        }

        throwStatement := statement as ThrowStatement
        if throwStatement != null {
            return !AnalyzerParserErrorPlaceholders.ContainsInExpression(throwStatement.Expression)
        }

        breakStatement := statement as BreakStatement
        if breakStatement != null {
            return breakLeaves
        }

        continueStatement := statement as ContinueStatement
        if continueStatement != null {
            return continueLeaves
        }

        block := statement as BlockStatement
        if block != null {
            return AnyStatementLeaves(block.Statements, breakLeaves, continueLeaves)
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            return Walk(allocBlock.Body, breakLeaves, continueLeaves)
        }

        allowBlock := statement as AllowStatement
        if allowBlock != null {
            return Walk(allowBlock.Body, breakLeaves, continueLeaves)
        }

        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            return Walk(unsafeBlock.Body, breakLeaves, continueLeaves)
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            elseStatement := ifStatement.ElseStatement
            if elseStatement == null {
                return false
            }

            return Walk(ifStatement.ThenStatement, breakLeaves, continueLeaves) && Walk(elseStatement, breakLeaves, continueLeaves)
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            return Walk(lockStatement.Body, breakLeaves, continueLeaves)
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            return SwitchLeaves(switchStatement, continueLeaves)
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            return TryLeaves(tryStatement, breakLeaves, continueLeaves)
        }

        return false
    }

    // A STATEMENT LIST LEAVES AS SOON AS ONE OF ITS STATEMENTS DOES, and everything after that one is
    // unreachable — which is the same fact the list walk reports about. It is deliberately not "the
    // LAST statement leaves": `return x` followed by dead code still leaves.
    static func AnyStatementAlwaysReturns(statements: List<Statement>): bool {
        return AnyStatementLeaves(statements, false, false)
    }

    static func AnyStatementLeaves(statements: List<Statement>, breakLeaves: bool, continueLeaves: bool): bool {
        index := 0
        while index < statements.Count {
            if Walk(statements[index], breakLeaves, continueLeaves) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // A `switch` LEAVES ONLY WHEN IT IS COMPLETE AND EVERY CASE LEAVES. The default case is found by
    // its ABSENT pattern, which is what `default =>` is in the tree, and it is measured for its own
    // body like every other case.
    //
    // A `break` INSIDE A CASE LEAVES THE SWITCH AND NOTHING FURTHER, so it stops counting here — a
    // `switch` whose every case ends in `break` falls out of its own end and leaves nothing. A
    // `continue` is unaffected: it still belongs to whatever loop encloses the switch.
    static func SwitchAlwaysReturns(switchStatement: SwitchStatement): bool {
        return SwitchLeaves(switchStatement, false)
    }

    static func SwitchLeaves(switchStatement: SwitchStatement, continueLeaves: bool): bool {
        cases := switchStatement.Cases
        if !HasDefaultCase(cases) {
            return false
        }

        index := 0
        while index < cases.Count {
            if !AnyStatementLeaves(cases[index].Statements, false, continueLeaves) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func HasDefaultCase(cases: List<SwitchCase>): bool {
        index := 0
        while index < cases.Count {
            if cases[index].Pattern == null {
                return true
            }

            index = index + 1
        }

        return false
    }

    // A `try` LEAVES WHEN ITS END POINT IS UNREACHABLE — C#'s rule (§13.2 "End points and
    // reachability"), spelled here as the two ways an end point can be unreachable.
    //
    // THE `finally` ALONE CAN SETTLE IT. If the finally block leaves on every path — it throws, or it
    // returns — then nothing can fall out of the `try` statement whatever the guarded body did, so
    // the statement leaves. A finally block is measured with BOTH jumps off, because a `break` or a
    // `continue` out of one is not legal IL and the analyzer reports it.
    //
    // OTHERWISE EVERY WAY OUT OF THE BODY MUST LEAVE: the guarded block, and each handler that could
    // catch for it. A `try` with NO handlers is settled by the guarded block alone, which is why
    // `try { return x } finally { ... }` leaves — and it is why every C# `using` that returns
    // compiles, because `using` lowers to exactly that shape. The exception the body might raise is
    // not a way out of the FUNCTION that falls off its end; it unwinds past the caller, and a rule
    // about missing returns has nothing to say about it.
    static func TryAlwaysReturns(tryStatement: TryStatement): bool {
        return TryLeaves(tryStatement, false, false)
    }

    static func TryLeaves(tryStatement: TryStatement, breakLeaves: bool, continueLeaves: bool): bool {
        finallyBlock := tryStatement.FinallyBlock
        if finallyBlock != null && Walk(finallyBlock, false, false) {
            return true
        }

        if !Walk(tryStatement.TryBlock, breakLeaves, continueLeaves) {
            return false
        }

        catchClauses := tryStatement.CatchClauses
        index := 0
        while index < catchClauses.Count {
            if !Walk(catchClauses[index].Block, breakLeaves, continueLeaves) {
                return false
            }

            index = index + 1
        }

        return true
    }
}

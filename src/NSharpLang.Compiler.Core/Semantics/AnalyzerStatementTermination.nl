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
// IT IS PURE OVER THE AST WITH ONE EXCEPTION, AND THE EXCEPTION IS WHY THE FACT IS A PARAMETER. It
// declares no symbol, opens no scope, re-enters no walk, reads no scope stack and reports no
// diagnostic. The one thing it cannot read off the syntax is whether a CALL returns: `ThrowHelper.Fail(m)`
// is a `throw` its `[DoesNotReturn]` signature spells, and only the binder that chose the callee
// knows that. So the answer is handed in — `AnalyzerTerminatingCalls`, filled by the call analysis —
// and every rule that asks passes it. It is asked at points that are far apart in the analysis — the
// `if` walk asks after both branches have run, the list walk asks after each statement, the function
// rule asks after the whole body — and it must answer the same thing at all three, which it does
// because all three ask AFTER the statements in question have been analysed and the facts filed.
// Asked with no fact-holder at all it answers the pure-syntax judgement, which is the same judgement
// for every shape that contains no call.
//
// A PARSER ERROR PLACEHOLDER IS NOT A RETURN. `return <error>` and `throw <error>` are text the
// recovery parser could not read, and a SYNTAX diagnostic has already been reported about them. They
// answer FALSE, which means the function that contains one is ALSO told it is missing a return —
// deliberately, because the alternative is to silently accept a body whose only return is broken
// text. This is the one thing in the judgement that is not structural.
//
// THE UNMODELLED ANSWER IS "NO", AND THAT IS THE SAFE DIRECTION. Every statement shape this walk does
// not name — a `foreach`, a `using`, a local function — answers FALSE. A bare EXPRESSION statement is
// the one that can answer yes, and only when the call it holds was bound to a `[DoesNotReturn]`
// signature.
//
// AN ENDLESS LOOP IS THE ONE LOOP SHAPE THAT ANSWERS YES, and it is C#'s rule rather than a
// concession (§13.2 "End points and reachability"): the end point of a `while` whose condition is the
// constant `true` — and of a `for` with no condition at all, which is the same statement spelled
// differently — is unreachable unless a reachable `break` TARGETS that loop. So
// `while true { … return … }` needs no return after it, and neither does a body that only throws.
// A `break` written inside a NESTED loop targets that loop and does not restore this one's end point;
// a `break` inside a `switch` leaves the switch; and a `break` inside a `finally` is not legal IL at
// all. All three fall out of the same jump-ownership rules the two entry points already carry, which
// is why the search is one walk rather than a second analysis.
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
        return Walk(statement, false, false, null)
    }

    static func AlwaysReturns(statement: Statement, terminatingCalls: AnalyzerTerminatingCalls?): bool {
        return Walk(statement, false, false, terminatingCalls)
    }

    // DOES EVERY PATH THROUGH THIS STATEMENT LEAVE THE BLOCK THAT CONTAINS IT? The guard-clause rule
    // asks this one about an `if` branch, where a `break` and a `continue` are as final as a `return`.
    static func AlwaysLeaves(statement: Statement): bool {
        return Walk(statement, true, true, null)
    }

    static func AlwaysLeaves(statement: Statement, terminatingCalls: AnalyzerTerminatingCalls?): bool {
        return Walk(statement, true, true, terminatingCalls)
    }

    // THE WALK. The shapes are tested in the order `Analyzer.cs` wrote them. That order is not
    // behaviour — every shape named here is a direct subclass of `Statement` and no two of them can
    // match the same node — but it is preserved so the two walks are readable against each other.
    static func Walk(statement: Statement, breakLeaves: bool, continueLeaves: bool): bool {
        return Walk(statement, breakLeaves, continueLeaves, null)
    }

    static func Walk(statement: Statement, breakLeaves: bool, continueLeaves: bool, terminatingCalls: AnalyzerTerminatingCalls?): bool {
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
            thrownExpression := throwStatement.Expression
            if thrownExpression == null {
                return true
            }

            return !AnalyzerParserErrorPlaceholders.ContainsInExpression(thrownExpression)
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
            return AnyStatementLeaves(block.Statements, breakLeaves, continueLeaves, terminatingCalls)
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            return Walk(allocBlock.Body, breakLeaves, continueLeaves, terminatingCalls)
        }

        allowBlock := statement as AllowStatement
        if allowBlock != null {
            return Walk(allowBlock.Body, breakLeaves, continueLeaves, terminatingCalls)
        }

        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            return Walk(unsafeBlock.Body, breakLeaves, continueLeaves, terminatingCalls)
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            elseStatement := ifStatement.ElseStatement
            if elseStatement == null {
                return false
            }

            return Walk(ifStatement.ThenStatement, breakLeaves, continueLeaves, terminatingCalls) && Walk(elseStatement, breakLeaves, continueLeaves, terminatingCalls)
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            return Walk(lockStatement.Body, breakLeaves, continueLeaves, terminatingCalls)
        }

        // A `using` BLOCK ends the function when its body does — the release in the `finally` runs on
        // the way out and changes nothing about whether control leaves. A using DECLARATION carries no
        // body at all and terminates nothing; the statements it guards are its SIBLINGS, and the block
        // walk measures those on its own.
        usingTerminationStatement := statement as UsingStatement
        if usingTerminationStatement != null {
            usingTerminationBody := usingTerminationStatement.Body
            if usingTerminationBody == null {
                return false
            }

            return Walk(usingTerminationBody, breakLeaves, continueLeaves, terminatingCalls)
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            return EndlessLoopLeaves(whileStatement.Condition, whileStatement.Body)
        }

        // A `for` is endless when it has NO condition. A `for` whose condition is written is measured
        // by the same constant test, so `for i := 0; true; i++ {}` is endless too.
        //
        // A `for <name> in <collection>` IS NOT ONE OF THOSE. The parser wraps a for-in in a
        // `ForStatement` with all three clauses null and the `ForeachStatement` as its BODY, so a
        // missing condition alone does not mean endless — the body's shape is what tells the two
        // apart, and a `foreach` over an empty collection runs its body zero times.
        forStatement := statement as ForStatement
        if forStatement != null {
            if (forStatement.Body as ForeachStatement) != null {
                return false
            }

            return EndlessLoopLeaves(forStatement.Condition, forStatement.Body)
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            return SwitchLeaves(switchStatement, continueLeaves, terminatingCalls)
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            return TryLeaves(tryStatement, breakLeaves, continueLeaves, terminatingCalls)
        }

        // A CALL THE SIGNATURE SAID NEVER RETURNS. `ThrowHelper.Fail(message)` is a `throw` the
        // signature spells, so the statement holding it leaves exactly as a `throw` statement does —
        // the one arm of this walk that reads a fact rather than a shape, and the reason the judgement
        // takes the fact-holder as a parameter.
        expressionStatement := statement as ExpressionStatement
        if expressionStatement != null {
            return terminatingCalls != null && terminatingCalls.NeverReturns(expressionStatement.Expression)
        }

        return false
    }

    // AN ENDLESS LOOP LEAVES WHEN NOTHING CAN BREAK OUT OF IT. The condition must be ABSENT or the
    // constant `true` — nothing here evaluates an expression, because a loop wrongly called endless
    // would accept a body that really can fall out of it — and the body must contain no `break` bound
    // to this loop.
    static func EndlessLoopLeaves(condition: Expression?, body: Statement): bool {
        if condition != null && !IsConstantTrueCondition(condition) {
            return false
        }

        return !ContainsBreakTargetingThisLoop(body)
    }

    // THE CONSTANT `true`, THROUGH THE SPELLINGS THAT ARE TRANSPARENTLY IT. A parenthesis and a
    // double `!` change nothing about the value; an operator would have to be evaluated and is not.
    static func IsConstantTrueCondition(condition: Expression): bool {
        boolLiteral := condition as BoolLiteralExpression
        if boolLiteral != null {
            return boolLiteral.Value
        }

        parenthesized := condition as ParenthesizedExpression
        if parenthesized != null {
            return IsConstantTrueCondition(parenthesized.Inner)
        }

        negation := condition as UnaryExpression
        if negation != null && negation.Operator == UnaryOperator.Not {
            return IsConstantFalseCondition(negation.Operand)
        }

        return false
    }

    static func IsConstantFalseCondition(condition: Expression): bool {
        boolLiteral := condition as BoolLiteralExpression
        if boolLiteral != null {
            return !boolLiteral.Value
        }

        parenthesized := condition as ParenthesizedExpression
        if parenthesized != null {
            return IsConstantFalseCondition(parenthesized.Inner)
        }

        negation := condition as UnaryExpression
        if negation != null && negation.Operator == UnaryOperator.Not {
            return IsConstantTrueCondition(negation.Operand)
        }

        return false
    }

    // A `break` THAT TARGETS THE LOOP THIS BODY BELONGS TO. The walk descends through everything a
    // `break` can be written inside WITHOUT changing what it binds to, and stops at the three things
    // that DO change it: a nested loop (the `break` is that loop's), a `switch` (the `break` leaves
    // the switch), and a `finally` (a jump out of one is not legal IL and is reported elsewhere).
    // Expressions are not walked at all, so a lambda body — a method of its own — is out of reach by
    // construction.
    static func ContainsBreakTargetingThisLoop(statement: Statement): bool {
        breakStatement := statement as BreakStatement
        if breakStatement != null {
            return true
        }

        block := statement as BlockStatement
        if block != null {
            index := 0
            while index < block.Statements.Count {
                if ContainsBreakTargetingThisLoop(block.Statements[index]) {
                    return true
                }

                index = index + 1
            }

            return false
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            if ContainsBreakTargetingThisLoop(ifStatement.ThenStatement) {
                return true
            }

            elseStatement := ifStatement.ElseStatement
            return elseStatement != null && ContainsBreakTargetingThisLoop(elseStatement)
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            return ContainsBreakTargetingThisLoop(lockStatement.Body)
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            usingBody := usingStatement.Body
            return usingBody != null && ContainsBreakTargetingThisLoop(usingBody)
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            return ContainsBreakTargetingThisLoop(allocBlock.Body)
        }

        allowBlock := statement as AllowStatement
        if allowBlock != null {
            return ContainsBreakTargetingThisLoop(allowBlock.Body)
        }

        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            return ContainsBreakTargetingThisLoop(unsafeBlock.Body)
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            if ContainsBreakTargetingThisLoop(tryStatement.TryBlock) {
                return true
            }

            catchClauses := tryStatement.CatchClauses
            index := 0
            while index < catchClauses.Count {
                if ContainsBreakTargetingThisLoop(catchClauses[index].Block) {
                    return true
                }

                index = index + 1
            }

            return false
        }

        return false
    }

    // A STATEMENT LIST LEAVES AS SOON AS ONE OF ITS STATEMENTS DOES, and everything after that one is
    // unreachable — which is the same fact the list walk reports about. It is deliberately not "the
    // LAST statement leaves": `return x` followed by dead code still leaves.
    static func AnyStatementAlwaysReturns(statements: List<Statement>): bool {
        return AnyStatementLeaves(statements, false, false, null)
    }

    static func AnyStatementLeaves(statements: List<Statement>, breakLeaves: bool, continueLeaves: bool): bool {
        return AnyStatementLeaves(statements, breakLeaves, continueLeaves, null)
    }

    static func AnyStatementLeaves(statements: List<Statement>, breakLeaves: bool, continueLeaves: bool, terminatingCalls: AnalyzerTerminatingCalls?): bool {
        for statement in statements {
            if Walk(statement, breakLeaves, continueLeaves, terminatingCalls) {
                return true
            }
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
        return SwitchLeaves(switchStatement, false, null)
    }

    static func SwitchLeaves(switchStatement: SwitchStatement, continueLeaves: bool): bool {
        return SwitchLeaves(switchStatement, continueLeaves, null)
    }

    static func SwitchLeaves(switchStatement: SwitchStatement, continueLeaves: bool, terminatingCalls: AnalyzerTerminatingCalls?): bool {
        cases := switchStatement.Cases
        if !HasDefaultCase(cases) {
            return false
        }

        for caseItem in cases {
            if !AnyStatementLeaves(caseItem.Statements, false, continueLeaves, terminatingCalls) {
                return false
            }
        }

        return true
    }

    static func HasDefaultCase(cases: List<SwitchCase>): bool {
        for caseItem in cases {
            if caseItem.Pattern == null {
                return true
            }
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
        return TryLeaves(tryStatement, false, false, null)
    }

    static func TryLeaves(tryStatement: TryStatement, breakLeaves: bool, continueLeaves: bool): bool {
        return TryLeaves(tryStatement, breakLeaves, continueLeaves, null)
    }

    static func TryLeaves(tryStatement: TryStatement, breakLeaves: bool, continueLeaves: bool, terminatingCalls: AnalyzerTerminatingCalls?): bool {
        finallyBlock := tryStatement.FinallyBlock
        if finallyBlock != null && Walk(finallyBlock, false, false, terminatingCalls) {
            return true
        }

        if !Walk(tryStatement.TryBlock, breakLeaves, continueLeaves, terminatingCalls) {
            return false
        }

        catchClauses := tryStatement.CatchClauses
        for catchClause in catchClauses {
            if !Walk(catchClause.Block, breakLeaves, continueLeaves, terminatingCalls) {
                return false
            }
        }

        return true
    }
}

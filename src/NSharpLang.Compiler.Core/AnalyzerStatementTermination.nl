namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHETHER A STATEMENT ALWAYS LEAVES — the analyzer's one control-flow-termination judgement, and the
// three unrelated rules that read it.
//
// The question is "does every path through this statement end in a `return` or a `throw`", and THREE
// rules ask it about three different things. A function body is asked so a non-void function that can
// fall off its end is told to return something. Every statement in a LIST is asked so the statement
// after one that always leaves is reported as unreachable. And an `if` branch is asked so a GUARD
// CLAUSE — `if x == null { return }` — hands the surviving flow the facts the branch it did not take
// proved. The three read the same answer and none of them may disagree with the others, which is why
// the judgement is ONE function rather than three.
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
// rule whose false NEGATIVE would be unverifiable IL. `try` is the same argument in miniature: it
// answers true only when the try block AND every catch block leave, and a `try` with no catch clauses
// answers FALSE regardless of what its body does, because a `finally` alone does not stop the
// exception.
//
// A SWITCH IS THE ONLY SHAPE THAT REASONS ABOUT COMPLETENESS. It leaves only when it has a `default`
// case and EVERY case — the default included — contains at least one statement that leaves. A case
// whose body is empty therefore refutes the whole switch, and so does a switch with no default, no
// matter how exhaustive its patterns look: exhaustiveness over a union is the MATCH family's
// judgement, and this one deliberately does not borrow it.
class AnalyzerStatementTermination {

    // DOES EVERY PATH THROUGH THIS STATEMENT END IN A `return` OR A `throw`?
    //
    // The shapes are tested in the order `Analyzer.cs` wrote them. That order is not behaviour — every
    // shape named here is a direct subclass of `Statement` and no two of them can match the same node
    // — but it is preserved so the two walks are readable against each other.
    static func AlwaysReturns(statement: Statement): bool {
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

        block := statement as BlockStatement
        if block != null {
            return AnyStatementAlwaysReturns(block.Statements)
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            return AlwaysReturns(allocBlock.Body)
        }

        allowBlock := statement as AllowStatement
        if allowBlock != null {
            return AlwaysReturns(allowBlock.Body)
        }

        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            return AlwaysReturns(unsafeBlock.Body)
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            elseStatement := ifStatement.ElseStatement
            if elseStatement == null {
                return false
            }

            return AlwaysReturns(ifStatement.ThenStatement) && AlwaysReturns(elseStatement)
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            return AlwaysReturns(lockStatement.Body)
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            return SwitchAlwaysReturns(switchStatement)
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            return TryAlwaysReturns(tryStatement)
        }

        return false
    }

    // A STATEMENT LIST LEAVES AS SOON AS ONE OF ITS STATEMENTS DOES, and everything after that one is
    // unreachable — which is the same fact the list walk reports about. It is deliberately not "the
    // LAST statement leaves": `return x` followed by dead code still leaves.
    static func AnyStatementAlwaysReturns(statements: List<Statement>): bool {
        index := 0
        while index < statements.Count {
            if AlwaysReturns(statements[index]) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // A `switch` LEAVES ONLY WHEN IT IS COMPLETE AND EVERY CASE LEAVES. The default case is found by
    // its ABSENT pattern, which is what `default =>` is in the tree, and it is measured for its own
    // body like every other case.
    static func SwitchAlwaysReturns(switchStatement: SwitchStatement): bool {
        cases := switchStatement.Cases
        if !HasDefaultCase(cases) {
            return false
        }

        index := 0
        while index < cases.Count {
            if !AnyStatementAlwaysReturns(cases[index].Statements) {
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

    // A `try` LEAVES ONLY WHEN THE GUARDED BODY AND EVERY HANDLER LEAVE. With no handler at all it
    // does not leave, because the exception it might raise has nowhere to go and the `finally` that
    // may follow does not stop it.
    static func TryAlwaysReturns(tryStatement: TryStatement): bool {
        if !AlwaysReturns(tryStatement.TryBlock) {
            return false
        }

        catchClauses := tryStatement.CatchClauses
        if catchClauses.Count == 0 {
            return false
        }

        index := 0
        while index < catchClauses.Count {
            if !AlwaysReturns(catchClauses[index].Block) {
                return false
            }

            index = index + 1
        }

        return true
    }
}

namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// Native contracts for WHETHER A STATEMENT ALWAYS LEAVES.
//
// THE JUDGEMENT WAS `private static` IN `Analyzer.cs`, SO NOTHING NAMED IT: its behaviour was pinned
// only indirectly, through end-to-end missing-return, unreachable-code and guard-clause diagnostics —
// three rules that each see a different slice of it and none of which can reach the shapes below
// exhaustively. This is its first DIRECT pinning, and it is written around the five things the
// judgement is easy to get wrong.
//
// (1) THE UNMODELLED ANSWER IS "NO", AND SILENTLY SO. Every statement shape the walk does not name
// answers false, including a `foreach` over a non-empty collection. That is the SAFE direction for the
// rules that read it, and it is pinned here so a later "improvement" that starts reasoning about loops
// is a red test rather than a quiet change in which functions compile. The ONE loop shape that is
// modelled is the ENDLESS one — a `while` on the constant `true`, or a `for` with no condition, that
// no reachable `break` targets — which is C# §13.2's rule and is pinned in both directions below.
//
// (2) A BLOCK ANSWERS ON ITS FIRST LEAVING STATEMENT, NOT ITS LAST STATEMENT. `return x` followed by
// dead code still leaves — which is the same fact the unreachable-code rule reports about, and the
// reason the two rules can never disagree.
//
// (3) A PARSER ERROR PLACEHOLDER IS NOT A RETURN. `return <error>` and `throw <error>` answer FALSE,
// so a function whose only return is broken text is told it is missing a return. A BARE `return` has
// no expression to be broken and always answers true.
//
// (4) `try` AND `switch` ARE THE TWO ARMS THAT REASON ABOUT COMPLETENESS. A `try` follows C#'s
// end-point rule — the guarded body and every handler leave, or the `finally` leaves by itself — so a
// zero-catch `try { return } finally { ... }` DOES leave. A `switch` still refuses by default: with no
// default case it answers false however exhaustive its patterns look.
//
// (5) THE THREE WRAPPER BLOCKS ARE TRANSPARENT AND THE `if` ARM IS NOT. `alloc`, `allow` and `unsafe`
// answer exactly what their body answers; an `if` answers only when it has an else AND both branches
// leave.
func TerminationBlock(statements: List<Statement>): Statement {
    block: Statement = new BlockStatement(statements, 1, 1)
    return block
}

func TerminationEmptyBlock(): BlockStatement {
    return new BlockStatement(new List<Statement>(), 1, 1)
}

func TerminationOneOf(statement: Statement): List<Statement> {
    statements := new List<Statement>()
    statements.Add(statement)
    return statements
}

func TerminationReturningBlock(): BlockStatement {
    return new BlockStatement(TerminationOneOf(TerminationBareReturn()), 1, 1)
}

func TerminationBareReturn(): Statement {
    bare: Statement = new ReturnStatement(null, 1, 1)
    return bare
}

func TerminationValueReturn(): Statement {
    valued: Statement = new ReturnStatement(new IntLiteralExpression("1", 1, 8), 1, 1)
    return valued
}

func TerminationBrokenReturn(): Statement {
    broken: Statement = new ReturnStatement(new IdentifierExpression(AnalyzerParserErrorPlaceholders.PlaceholderName(), 1, 8), 1, 1)
    return broken
}

func TerminationThrow(): Statement {
    thrown: Statement = new ThrowStatement(new IdentifierExpression("ex", 1, 7), 1, 1)
    return thrown
}

func TerminationBrokenThrow(): Statement {
    thrown: Statement = new ThrowStatement(new IdentifierExpression(AnalyzerParserErrorPlaceholders.PlaceholderName(), 1, 7), 1, 1)
    return thrown
}

func TerminationExpression(): Statement {
    plain: Statement = new ExpressionStatement(new IdentifierExpression("work", 1, 1), 1, 1)
    return plain
}

func TerminationIf(thenStatement: Statement, elseStatement: Statement?): Statement {
    conditional: Statement = new IfStatement(new BoolLiteralExpression(true, 1, 4), thenStatement, elseStatement, 1, 1)
    return conditional
}

func TerminationCase(pattern: Pattern?, statements: List<Statement>): SwitchCase {
    return new SwitchCase(pattern, statements, 1, 1)
}

func TerminationTypePattern(): Pattern {
    pattern: Pattern = new TypePattern(new SimpleTypeReference("int", 1, 10), null, 1, 10)
    return pattern
}

func TerminationSwitch(cases: List<SwitchCase>): Statement {
    switched: Statement = new SwitchStatement(new IdentifierExpression("value", 1, 8), cases, 1, 1)
    return switched
}

func TerminationCatch(block: BlockStatement): CatchClause {
    return new CatchClause(null, "ex", block)
}

func TerminationTry(tryBlock: BlockStatement, catches: List<CatchClause>, finallyBlock: BlockStatement?): Statement {
    guarded: Statement = new TryStatement(tryBlock, catches, finallyBlock, 1, 1)
    return guarded
}

// ---------------------------------------------------------------------------------------------
// THE TWO THINGS THAT LEAVE
// ---------------------------------------------------------------------------------------------

test "A BARE return LEAVES, AND SO DOES ONE WITH A WELL-FORMED VALUE" {
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationBareReturn())
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationValueReturn())
}

test "A throw LEAVES EXACTLY AS A return DOES" {
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationThrow())
}

test "A RETURN OR THROW OF BROKEN TEXT DOES NOT LEAVE, BUT A BARE return STILL DOES" {
    // The recovery parser minted the operand and a SYNTAX diagnostic already exists for it, so this
    // is not a return the semantic rules may rely on.
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationBrokenReturn())
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationBrokenThrow())
    // A bare `return` has no operand to be broken.
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationBareReturn())
}

// ---------------------------------------------------------------------------------------------
// THE BLOCK RULE
// ---------------------------------------------------------------------------------------------

test "A BLOCK LEAVES ON ITS FIRST LEAVING STATEMENT, NOT ON ITS LAST STATEMENT" {
    statements := new List<Statement>()
    statements.Add(TerminationBareReturn())
    statements.Add(TerminationExpression())

    // The trailing statement is unreachable, which is precisely why the block still leaves.
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationBlock(statements))
}

test "A BLOCK WITH NO LEAVING STATEMENT, AND AN EMPTY BLOCK, DO NOT LEAVE" {
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationBlock(TerminationOneOf(TerminationExpression())))
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationBlock(new List<Statement>()))
}

test "THE BLOCK RULE IS RECURSIVE — A NESTED BLOCK THAT LEAVES MAKES ITS PARENT LEAVE" {
    inner: Statement = TerminationBlock(TerminationOneOf(TerminationBareReturn()))

    assert AnalyzerStatementTermination.AlwaysReturns(TerminationBlock(TerminationOneOf(inner)))
}

// ---------------------------------------------------------------------------------------------
// THE THREE TRANSPARENT WRAPPERS
// ---------------------------------------------------------------------------------------------

test "alloc, allow AND unsafe ANSWER EXACTLY WHAT THEIR BODY ANSWERS" {
    allocLeaves: Statement = new AllocBlockStatement(TerminationReturningBlock(), 1, 1)
    allocFalls: Statement = new AllocBlockStatement(TerminationEmptyBlock(), 1, 1)
    allowLeaves: Statement = new AllowStatement(new List<string>(), null, null, TerminationReturningBlock(), 1, 1)
    allowFalls: Statement = new AllowStatement(new List<string>(), null, null, TerminationEmptyBlock(), 1, 1)
    unsafeLeaves: Statement = new UnsafeBlockStatement(TerminationReturningBlock(), 1, 1)
    unsafeFalls: Statement = new UnsafeBlockStatement(TerminationEmptyBlock(), 1, 1)

    assert AnalyzerStatementTermination.AlwaysReturns(allocLeaves)
    assert !AnalyzerStatementTermination.AlwaysReturns(allocFalls)
    assert AnalyzerStatementTermination.AlwaysReturns(allowLeaves)
    assert !AnalyzerStatementTermination.AlwaysReturns(allowFalls)
    assert AnalyzerStatementTermination.AlwaysReturns(unsafeLeaves)
    assert !AnalyzerStatementTermination.AlwaysReturns(unsafeFalls)
}

test "A lock ANSWERS WHAT ITS BODY ANSWERS — IT IS A GUARDED REGION, NOT A BRANCH" {
    leaves: Statement = new LockStatement(new IdentifierExpression("gate", 1, 6), TerminationReturningBlock(), 1, 1)
    falls: Statement = new LockStatement(new IdentifierExpression("gate", 1, 6), TerminationEmptyBlock(), 1, 1)

    assert AnalyzerStatementTermination.AlwaysReturns(leaves)
    assert !AnalyzerStatementTermination.AlwaysReturns(falls)
}

// ---------------------------------------------------------------------------------------------
// THE `if` ARM
// ---------------------------------------------------------------------------------------------

test "AN if LEAVES ONLY WITH AN ELSE AND ONLY WHEN BOTH BRANCHES LEAVE" {
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationIf(TerminationBareReturn(), TerminationBareReturn()))
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationIf(TerminationBareReturn(), TerminationExpression()))
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationIf(TerminationExpression(), TerminationBareReturn()))
}

test "AN if WITH NO ELSE NEVER LEAVES, HOWEVER ITS THEN BRANCH ENDS" {
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationIf(TerminationBareReturn(), null))
}

test "AN else if CHAIN LEAVES ONLY WHEN ITS LAST LINK HAS AN ELSE THAT LEAVES" {
    // `if … return else if … return else return` — every link answers, so the chain answers.
    closed := TerminationIf(TerminationBareReturn(), TerminationIf(TerminationBareReturn(), TerminationBareReturn()))
    // The same chain with the final `else` removed answers false all the way up.
    open := TerminationIf(TerminationBareReturn(), TerminationIf(TerminationBareReturn(), null))

    assert AnalyzerStatementTermination.AlwaysReturns(closed)
    assert !AnalyzerStatementTermination.AlwaysReturns(open)
}

// ---------------------------------------------------------------------------------------------
// THE `switch` ARM — COMPLETENESS, AND THE REFUSAL BY DEFAULT
// ---------------------------------------------------------------------------------------------

test "A switch LEAVES ONLY WITH A default CASE AND ONLY WHEN EVERY CASE LEAVES" {
    complete := new List<SwitchCase>()
    complete.Add(TerminationCase(TerminationTypePattern(), TerminationOneOf(TerminationBareReturn())))
    complete.Add(TerminationCase(null, TerminationOneOf(TerminationThrow())))

    assert AnalyzerStatementTermination.AlwaysReturns(TerminationSwitch(complete))
}

test "A switch WITH NO default DOES NOT LEAVE, HOWEVER ITS CASES END" {
    patterned := new List<SwitchCase>()
    patterned.Add(TerminationCase(TerminationTypePattern(), TerminationOneOf(TerminationBareReturn())))

    // Exhaustiveness over a union is the MATCH family's judgement; this one deliberately does not
    // borrow it.
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationSwitch(patterned))
}

test "ONE CASE THAT FALLS THROUGH REFUTES THE WHOLE switch, AND SO DOES AN EMPTY CASE BODY" {
    falling := new List<SwitchCase>()
    falling.Add(TerminationCase(TerminationTypePattern(), TerminationOneOf(TerminationExpression())))
    falling.Add(TerminationCase(null, TerminationOneOf(TerminationBareReturn())))

    empty := new List<SwitchCase>()
    empty.Add(TerminationCase(TerminationTypePattern(), new List<Statement>()))
    empty.Add(TerminationCase(null, TerminationOneOf(TerminationBareReturn())))

    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationSwitch(falling))
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationSwitch(empty))
}

test "A CASE LEAVES ON ANY ONE OF ITS STATEMENTS, NOT ONLY ON ITS LAST" {
    statements := new List<Statement>()
    statements.Add(TerminationBareReturn())
    statements.Add(TerminationExpression())
    onlyDefault := new List<SwitchCase>()
    onlyDefault.Add(TerminationCase(null, statements))

    assert AnalyzerStatementTermination.AlwaysReturns(TerminationSwitch(onlyDefault))
}

// ---------------------------------------------------------------------------------------------
// THE `try` ARM — THE HANDLERS, AND WHAT A `finally` DOES NOT DO
// ---------------------------------------------------------------------------------------------

test "A try LEAVES ONLY WHEN THE GUARDED BODY AND EVERY HANDLER LEAVE" {
    catches := new List<CatchClause>()
    catches.Add(TerminationCatch(TerminationReturningBlock()))

    assert AnalyzerStatementTermination.AlwaysReturns(TerminationTry(TerminationReturningBlock(), catches, null))
}

test "A try WITH NO CATCH CLAUSES LEAVES WHEN ITS GUARDED BODY DOES, finally OR NOT" {
    // C#'s end-point rule, and the shape every `using` that returns lowers to. The exception the
    // body might raise unwinds past the caller; it is not a path that falls off the end.
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationTry(TerminationReturningBlock(), new List<CatchClause>(), TerminationReturningBlock()))
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationTry(TerminationReturningBlock(), new List<CatchClause>(), TerminationEmptyBlock()))
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationTry(TerminationEmptyBlock(), new List<CatchClause>(), TerminationEmptyBlock()))
}

test "A finally THAT LEAVES SETTLES THE WHOLE try BY ITSELF" {
    // Nothing can fall out of the statement once the finally block leaves on every path, whatever
    // the guarded body and the handlers did.
    fallingCatch := new List<CatchClause>()
    fallingCatch.Add(TerminationCatch(TerminationEmptyBlock()))

    assert AnalyzerStatementTermination.AlwaysReturns(TerminationTry(TerminationEmptyBlock(), fallingCatch, TerminationReturningBlock()))
}

test "A FALLING BODY OR ONE FALLING HANDLER REFUTES THE WHOLE try" {
    leavingCatch := new List<CatchClause>()
    leavingCatch.Add(TerminationCatch(TerminationReturningBlock()))

    mixedCatches := new List<CatchClause>()
    mixedCatches.Add(TerminationCatch(TerminationReturningBlock()))
    mixedCatches.Add(TerminationCatch(TerminationEmptyBlock()))

    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationTry(TerminationEmptyBlock(), leavingCatch, null))
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationTry(TerminationReturningBlock(), mixedCatches, null))
}

// ---------------------------------------------------------------------------------------------
// THE UNMODELLED SHAPES
// ---------------------------------------------------------------------------------------------

test "EVERY SHAPE THE WALK DOES NOT NAME ANSWERS NO, AND THE ENDLESS LOOP IS THE ONE IT DOES" {
    // A `foreach` may run zero times, so it never completes a value function; `while true` with no
    // break is the exception the walk DOES model, because its end point is unreachable (C# §13.2).
    infinite: Statement = new WhileStatement(new BoolLiteralExpression(true, 1, 7), TerminationReturningBlock(), 1, 1)
    iterating: Statement = new ForeachStatement("item", new IdentifierExpression("items", 1, 14), TerminationReturningBlock(), 1, 1)
    breaking: Statement = new BreakStatement(1, 1)
    yielding: Statement = new YieldStatement(new IntLiteralExpression("1", 1, 7), 1, 1)
    empty: Statement = new EmptyStatement(1, 1)

    assert AnalyzerStatementTermination.AlwaysReturns(infinite)
    assert !AnalyzerStatementTermination.AlwaysReturns(iterating)
    assert !AnalyzerStatementTermination.AlwaysReturns(breaking)
    assert !AnalyzerStatementTermination.AlwaysReturns(yielding)
    assert !AnalyzerStatementTermination.AlwaysReturns(empty)
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationExpression())
}

// ---------------------------------------------------------------------------------------------
// THE SECOND ENTRY POINT — `AlwaysLeaves`, WHICH THE GUARD-CLAUSE RULE ASKS
// ---------------------------------------------------------------------------------------------
//
// `AlwaysLeaves` is `AlwaysReturns` with `break` and `continue` counted, because the guard-clause
// rule cares whether the BRANCH is gone and not whether the function is over. The two must agree
// about every shape that contains neither jump, which is what the first test below pins; the rest
// pin where they differ and — more importantly — where a jump does NOT escape the branch.

func TerminationBreak(): Statement {
    jumped: Statement = new BreakStatement(1, 1)
    return jumped
}

func TerminationContinue(): Statement {
    jumped: Statement = new ContinueStatement(1, 1)
    return jumped
}

func TerminationLoop(body: BlockStatement): Statement {
    looped: Statement = new WhileStatement(new BoolLiteralExpression(true, 1, 7), body, 1, 1)
    return looped
}

func TerminationBlockOf(statement: Statement): BlockStatement {
    return new BlockStatement(TerminationOneOf(statement), 1, 1)
}

test "THE TWO ENTRY POINTS AGREE ABOUT EVERY SHAPE THAT CONTAINS NEITHER JUMP" {
    catches := new List<CatchClause>()
    catches.Add(TerminationCatch(TerminationReturningBlock()))

    assert AnalyzerStatementTermination.AlwaysLeaves(TerminationBareReturn())
    assert AnalyzerStatementTermination.AlwaysLeaves(TerminationThrow())
    assert AnalyzerStatementTermination.AlwaysLeaves(TerminationTry(TerminationReturningBlock(), catches, null))
    assert !AnalyzerStatementTermination.AlwaysLeaves(TerminationBrokenReturn())
    assert !AnalyzerStatementTermination.AlwaysLeaves(TerminationExpression())
    assert !AnalyzerStatementTermination.AlwaysLeaves(TerminationIf(TerminationReturningBlock(), null))
}

test "break AND continue LEAVE THE BRANCH BUT NOT THE FUNCTION" {
    assert AnalyzerStatementTermination.AlwaysLeaves(TerminationBreak())
    assert AnalyzerStatementTermination.AlwaysLeaves(TerminationContinue())
    assert AnalyzerStatementTermination.AlwaysLeaves(TerminationBlockOf(TerminationBreak()))
    assert AnalyzerStatementTermination.AlwaysLeaves(TerminationIf(TerminationBlockOf(TerminationBreak()), TerminationBlockOf(TerminationContinue())))

    // The missing-return rule must not see any of that as a return.
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationBreak())
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationContinue())
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationBlockOf(TerminationBreak()))
}

test "A JUMP BOUND TO A CONSTRUCT INSIDE THE BRANCH DOES NOT ESCAPE THE BRANCH" {
    // A `break` inside a loop that is itself inside the branch leaves the LOOP. The branch is still
    // there afterwards, so the guard-clause rule must learn nothing from it.
    assert !AnalyzerStatementTermination.AlwaysLeaves(TerminationLoop(TerminationBlockOf(TerminationBreak())))

    // A `break` inside a `switch` leaves the SWITCH, so a switch whose every case breaks falls out
    // of its own end — while a `continue` in the same place still belongs to the enclosing loop.
    breaking := new List<SwitchCase>()
    breaking.Add(TerminationCase(TerminationTypePattern(), TerminationOneOf(TerminationBreak())))
    breaking.Add(TerminationCase(null, TerminationOneOf(TerminationBreak())))
    assert !AnalyzerStatementTermination.AlwaysLeaves(TerminationSwitch(breaking))

    continuing := new List<SwitchCase>()
    continuing.Add(TerminationCase(TerminationTypePattern(), TerminationOneOf(TerminationContinue())))
    continuing.Add(TerminationCase(null, TerminationOneOf(TerminationContinue())))
    assert AnalyzerStatementTermination.AlwaysLeaves(TerminationSwitch(continuing))
}

test "A finally COUNTS NEITHER JUMP, BECAUSE NEITHER MAY LEAVE ONE" {
    // A `break` out of a finally handler is not legal IL, so a finally block full of them settles
    // nothing — while a guarded block full of them settles the statement as any other exit would.
    assert !AnalyzerStatementTermination.AlwaysLeaves(TerminationTry(TerminationEmptyBlock(), new List<CatchClause>(), TerminationBlockOf(TerminationBreak())))
    assert AnalyzerStatementTermination.AlwaysLeaves(TerminationTry(TerminationBlockOf(TerminationContinue()), new List<CatchClause>(), TerminationEmptyBlock()))
}

// ── the endless loop ──────────────────────────────────────────────────────

func TerminationWhile(condition: Expression, body: BlockStatement): Statement {
    looped: Statement = new WhileStatement(condition, body, 1, 1)
    return looped
}

func TerminationFor(condition: Expression?, body: BlockStatement): Statement {
    counted: Statement = new ForStatement(null, condition, null, body, 1, 1)
    return counted
}

func TerminationForIn(body: BlockStatement): Statement {
    each: Statement = new ForeachStatement("item", new IdentifierExpression("items", 1, 9), body, 1, 1)
    wrapped: Statement = new ForStatement(null, null, null, each, 1, 1)
    return wrapped
}

test "A `while true` WITH NO BREAK LEAVES ON EVERY PATH" {
    endless := TerminationWhile(new BoolLiteralExpression(true, 1, 7), TerminationBlockOf(TerminationBareReturn()))

    assert AnalyzerStatementTermination.AlwaysReturns(endless)
    assert AnalyzerStatementTermination.AlwaysLeaves(endless)
}

test "A `while true` WHOSE BODY ONLY THROWS LEAVES TOO, AND ONE THAT DOES NEITHER STILL LEAVES" {
    // The END POINT is what the rule is about: nothing can fall out of the loop, whatever the body
    // does inside it.
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(new BoolLiteralExpression(true, 1, 7), TerminationBlockOf(TerminationThrow())))
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(new BoolLiteralExpression(true, 1, 7), TerminationEmptyBlock()))
}

test "A REACHABLE `break` RESTORES THE END POINT" {
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(new BoolLiteralExpression(true, 1, 7), TerminationBlockOf(TerminationBreak())))
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(new BoolLiteralExpression(true, 1, 7), TerminationBlockOf(TerminationIf(TerminationBlockOf(TerminationBreak()), null))))
}

test "A `break` BOUND TO A NESTED LOOP OR A SWITCH DOES NOT RESTORE IT" {
    nested := TerminationBlockOf(TerminationWhile(new BoolLiteralExpression(true, 1, 7), TerminationBlockOf(TerminationBreak())))

    assert AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(new BoolLiteralExpression(true, 1, 7), nested))

    switched := new List<SwitchCase>()
    switched.Add(TerminationCase(null, TerminationOneOf(TerminationBreak())))
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(new BoolLiteralExpression(true, 1, 7), TerminationBlockOf(TerminationSwitch(switched))))
}

test "A NON-CONSTANT CONDITION IS NOT ENDLESS, AND NEITHER IS `while false`" {
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(new IdentifierExpression("running", 1, 7), TerminationBlockOf(TerminationBareReturn())))
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(new BoolLiteralExpression(false, 1, 7), TerminationBlockOf(TerminationBareReturn())))
}

test "THE CONSTANT IS READ THROUGH PARENTHESES AND A DOUBLE `!`" {
    parenthesised := new ParenthesizedExpression(new BoolLiteralExpression(true, 1, 8), 1, 7)
    negatedFalse := new UnaryExpression(UnaryOperator.Not, new BoolLiteralExpression(false, 1, 8), 1, 7)

    assert AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(parenthesised, TerminationBlockOf(TerminationBareReturn())))
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationWhile(negatedFalse, TerminationBlockOf(TerminationBareReturn())))
}

test "A `for` WITH NO CONDITION IS ENDLESS, AND A `for <name> in <collection>` IS NOT" {
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationFor(null, TerminationBlockOf(TerminationBareReturn())))
    assert AnalyzerStatementTermination.AlwaysReturns(TerminationFor(new BoolLiteralExpression(true, 1, 7), TerminationBlockOf(TerminationBareReturn())))
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationFor(new IdentifierExpression("more", 1, 7), TerminationBlockOf(TerminationBareReturn())))

    // The parser wraps a for-in in a `ForStatement` with all three clauses null, so a missing
    // condition alone must not be read as endless: a collection can be empty.
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationForIn(TerminationBlockOf(TerminationBareReturn())))
}

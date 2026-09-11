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
// answers false, including a `while true` that provably never falls through and a `foreach` over a
// non-empty collection. That is the SAFE direction for the rules that read it, and it is pinned here
// so a later "improvement" that starts reasoning about loops is a red test rather than a quiet change
// in which functions compile.
//
// (2) A BLOCK ANSWERS ON ITS FIRST LEAVING STATEMENT, NOT ITS LAST STATEMENT. `return x` followed by
// dead code still leaves — which is the same fact the unreachable-code rule reports about, and the
// reason the two rules can never disagree.
//
// (3) A PARSER ERROR PLACEHOLDER IS NOT A RETURN. `return <error>` and `throw <error>` answer FALSE,
// so a function whose only return is broken text is told it is missing a return. A BARE `return` has
// no expression to be broken and always answers true.
//
// (4) `try` AND `switch` ARE THE TWO ARMS THAT REASON ABOUT COMPLETENESS, AND BOTH REFUSE BY DEFAULT.
// A `try` with no catch clauses answers false however its body ends; a `switch` with no default
// answers false however exhaustive its patterns look.
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

test "A try WITH NO CATCH CLAUSES DOES NOT LEAVE, EVEN WITH A LEAVING BODY AND A finally" {
    // A `finally` does not stop the exception, so there is a path out that does not return.
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationTry(TerminationReturningBlock(), new List<CatchClause>(), TerminationReturningBlock()))
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

test "EVERY SHAPE THE WALK DOES NOT NAME ANSWERS NO, INCLUDING A LOOP THAT PROVABLY LEAVES" {
    // `while true { return }` leaves on every path a program can take, and this walk says it does
    // not. The cost is a missing-return complaint a developer resolves by writing the return; the
    // opposite error would be unverifiable IL.
    infinite: Statement = new WhileStatement(new BoolLiteralExpression(true, 1, 7), TerminationReturningBlock(), 1, 1)
    iterating: Statement = new ForeachStatement("item", new IdentifierExpression("items", 1, 14), TerminationReturningBlock(), 1, 1)
    breaking: Statement = new BreakStatement(1, 1)
    yielding: Statement = new YieldStatement(new IntLiteralExpression("1", 1, 7), 1, 1)
    empty: Statement = new EmptyStatement(1, 1)

    assert !AnalyzerStatementTermination.AlwaysReturns(infinite)
    assert !AnalyzerStatementTermination.AlwaysReturns(iterating)
    assert !AnalyzerStatementTermination.AlwaysReturns(breaking)
    assert !AnalyzerStatementTermination.AlwaysReturns(yielding)
    assert !AnalyzerStatementTermination.AlwaysReturns(empty)
    assert !AnalyzerStatementTermination.AlwaysReturns(TerminationExpression())
}

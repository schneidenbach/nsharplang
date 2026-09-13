namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Native contracts for the kill set a loop's back edge carries.
//
// WHAT IS PINNED HERE IS COVERAGE, and the failure mode is SILENT. A write this walk does not see
// is a fact that outlives the turn that invalidated it, and the symptom is a MISSING NL905 on a real
// null dereference — nothing goes red, the compiler just stops objecting. So every container shape
// that can hold a write is exercised with a write inside it, and the three write forms (assignment,
// increment, `ref`/`out` argument) are each pinned on their own.
//
// AND THE OVER-APPROXIMATION IS PINNED TOO, in both directions: an unstable target records nothing
// because there was no fact to invalidate, a `:=` deconstruction declares rather than writes, and a
// METHOD CALL on a receiver is not a write at all — that last one is C#'s optimistic rule and the
// reason path narrowing is usable.
func LcnName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 2, 5)
}

func LcnMember(receiver: string, memberName: string): MemberAccessExpression {
    return new MemberAccessExpression(LcnName(receiver), memberName, false, 2, 5)
}

func LcnAssign(target: Expression): Expression {
    return new AssignmentExpression(target, AssignmentOperator.Assign, LcnName("source"), 2, 5)
}

func LcnAssignStatement(target: Expression): Statement {
    return new ExpressionStatement(LcnAssign(target), 2, 5)
}

func LcnBlock(statement: Statement): BlockStatement {
    statements := new List<Statement>()
    statements.Add(statement)
    return new BlockStatement(statements, 2, 1)
}

func LcnCall(callee: Expression, arguments: List<Argument>): CallExpression {
    return new CallExpression(callee, arguments, null, 2, 5)
}

func LcnArguments(modifier: ArgumentModifier, value: Expression): List<Argument> {
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, value, modifier))
    return arguments
}

// The collected paths, in order, as one comparable string. Duplicates are kept: the caller
// invalidates each entry and invalidating twice costs nothing, so the walk does not pay to dedupe.
func LcnPaths(body: Statement?, iterator: Expression?): string {
    paths := new List<string>()
    AnalyzerLoopCarriedNullFacts.CollectWrittenPaths(body, iterator, paths)
    return string.Join("|", paths)
}

func LcnStatementPaths(body: Statement): string {
    return LcnPaths(body, null)
}

func LcnExpressionPaths(expression: Expression): string {
    return LcnPaths(new ExpressionStatement(expression, 2, 5), null)
}

// ── the three write forms ──────────────────────────────────────────────────

test "an assignment names the STABLE PATH it targets, not just the name" {
    assert LcnExpressionPaths(LcnAssign(LcnName("value"))) == "value"
    assert LcnExpressionPaths(LcnAssign(LcnMember("doc", "Error"))) == "doc.Error"
    assert LcnExpressionPaths(
        LcnAssign(new MemberAccessExpression(LcnMember("doc", "Error"), "Detail", false, 2, 5))
    ) == "doc.Error.Detail"
}

test "an increment and a decrement are writes; a negation and a `!` are not" {
    assert LcnExpressionPaths(new UnaryExpression(UnaryOperator.PreIncrement, LcnName("i"), 2, 5)) == "i"
    assert LcnExpressionPaths(new UnaryExpression(UnaryOperator.PostIncrement, LcnName("i"), 2, 5)) == "i"
    assert LcnExpressionPaths(new UnaryExpression(UnaryOperator.PreDecrement, LcnName("i"), 2, 5)) == "i"
    assert LcnExpressionPaths(new UnaryExpression(UnaryOperator.PostDecrement, LcnName("i"), 2, 5)) == "i"
    assert LcnExpressionPaths(new UnaryExpression(UnaryOperator.Negate, LcnName("i"), 2, 5)) == ""
    assert LcnExpressionPaths(new UnaryExpression(UnaryOperator.Not, LcnName("i"), 2, 5)) == ""
}

test "a `ref` or `out` argument is a write; a plain one is a read" {
    outCall := LcnCall(LcnName("Fill"), LcnArguments(ArgumentModifier.Out, LcnMember("doc", "Error")))
    refCall := LcnCall(LcnName("Fill"), LcnArguments(ArgumentModifier.Ref, LcnName("value")))
    plainCall := LcnCall(LcnName("Fill"), LcnArguments(ArgumentModifier.None, LcnName("value")))

    assert LcnExpressionPaths(outCall) == "doc.Error"
    assert LcnExpressionPaths(refCall) == "value"
    assert LcnExpressionPaths(plainCall) == ""
}

test "A METHOD CALL ON A RECEIVER IS NOT A WRITE — the optimistic rule, stated once" {
    call := LcnCall(LcnMember("doc", "Touch"), new List<Argument>())

    assert LcnExpressionPaths(call) == ""
}

test "an UNSTABLE target records nothing: there was no fact about it to invalidate" {
    indexTarget: Expression = new IndexAccessExpression(LcnName("rows"), LcnName("i"), false, 2, 5)
    overCall: Expression = new MemberAccessExpression(
        LcnCall(LcnName("Load"), new List<Argument>()),
        "Error",
        false,
        2,
        5
    )

    assert LcnExpressionPaths(LcnAssign(indexTarget)) == ""
    assert LcnExpressionPaths(LcnAssign(overCall)) == ""
}

// ── the containers a write can hide in ─────────────────────────────────────

test "a nested block, an `if` and both of its branches are walked" {
    thenBranch := LcnBlock(LcnAssignStatement(LcnName("a")))
    elseBranch := LcnBlock(LcnAssignStatement(LcnName("b")))
    ifStatement: Statement = new IfStatement(LcnName("flag"), thenBranch, elseBranch, 2, 1)

    assert LcnStatementPaths(LcnBlock(ifStatement)) == "a|b"
}

test "every nested loop form carries its body's writes outward" {
    whileStatement: Statement = new WhileStatement(LcnName("flag"), LcnBlock(LcnAssignStatement(LcnName("a"))), 2, 1)
    forStatement: Statement = new ForStatement(
        LcnAssignStatement(LcnName("init")),
        LcnName("flag"),
        LcnAssign(LcnName("step")),
        LcnBlock(LcnAssignStatement(LcnName("b"))),
        2,
        1
    )
    foreachStatement: Statement = new ForeachStatement(
        "item",
        LcnName("items"),
        LcnBlock(LcnAssignStatement(LcnName("c"))),
        2,
        1,
        null
    )
    awaitForeachStatement: Statement = new AwaitForEachStatement(
        "item",
        LcnName("items"),
        LcnBlock(LcnAssignStatement(LcnName("d"))),
        2,
        1
    )

    assert LcnStatementPaths(whileStatement) == "a"
    assert LcnStatementPaths(forStatement) == "init|step|b"
    assert LcnStatementPaths(foreachStatement) == "c"
    assert LcnStatementPaths(awaitForeachStatement) == "d"
}

test "a `try`, its catches and its finally are all walked" {
    clauses := new List<CatchClause>()
    clauses.Add(new CatchClause(null, "error", LcnBlock(LcnAssignStatement(LcnName("b")))))
    tryStatement: Statement = new TryStatement(
        LcnBlock(LcnAssignStatement(LcnName("a"))),
        clauses,
        LcnBlock(LcnAssignStatement(LcnName("c"))),
        2,
        1
    )

    assert LcnStatementPaths(tryStatement) == "a|b|c"
}

test "a `switch` walks every case's statements" {
    cases := new List<SwitchCase>()
    cases.Add(new SwitchCase(null, LcnBlock(LcnAssignStatement(LcnName("a"))).Statements, 2, 1))
    cases.Add(new SwitchCase(null, LcnBlock(LcnAssignStatement(LcnName("b"))).Statements, 3, 1))
    switchStatement: Statement = new SwitchStatement(LcnName("value"), cases, 2, 1)

    assert LcnStatementPaths(switchStatement) == "a|b"
}

test "a `using`, a `lock`, an `unsafe` block and an `assert throws` body are walked" {
    usingStatement: Statement = new UsingStatement(
        null,
        LcnAssign(LcnName("resource")),
        LcnBlock(LcnAssignStatement(LcnName("a"))),
        2,
        1,
        false
    )
    lockStatement: Statement = new LockStatement(LcnName("gate"), LcnBlock(LcnAssignStatement(LcnName("b"))), 2, 1)
    unsafeStatement: Statement = new UnsafeBlockStatement(LcnBlock(LcnAssignStatement(LcnName("c"))), 2, 1)
    assertThrows: Statement = new AssertThrowsStatement(
        new SimpleTypeReference("InvalidOperationException"),
        LcnBlock(LcnAssignStatement(LcnName("d"))),
        2,
        1
    )

    assert LcnStatementPaths(usingStatement) == "resource|a"
    assert LcnStatementPaths(lockStatement) == "b"
    assert LcnStatementPaths(unsafeStatement) == "c"
    assert LcnStatementPaths(assertThrows) == "d"
}

test "A CLOSURE'S WRITE IS THE LOOP'S WRITE: lambdas and local functions are walked" {
    blockLambda: Expression = new LambdaExpression(
        new List<Parameter>(),
        null,
        LcnBlock(LcnAssignStatement(LcnName("captured"))),
        2,
        5,
        false
    )
    expressionLambda: Expression = new LambdaExpression(
        new List<Parameter>(),
        LcnAssign(LcnName("shortForm")),
        null,
        2,
        5,
        false
    )
    localFunction: Statement = new LocalFunctionStatement(
        new FunctionDeclaration(
            "Inner",
            new List<Parameter>(),
            null,
            LcnBlock(LcnAssignStatement(LcnName("inner"))),
            null,
            null,
            null,
            Modifiers.None,
            new List<AttributeNode>(),
            false,
            null,
            false,
            false,
            2,
            1
        ),
        2,
        1
    )

    assert LcnExpressionPaths(blockLambda) == "captured"
    assert LcnExpressionPaths(expressionLambda) == "shortForm"
    assert LcnStatementPaths(localFunction) == "inner"
}

test "a write inside an interpolation hole, a ternary arm and a match arm is still a write" {
    parts := new List<InterpolatedStringPart>()
    parts.Add(new InterpolatedStringText("value: ", 2, 5))
    parts.Add(new InterpolatedStringHole(LcnAssign(LcnName("hole")), null, 2, 5))
    interpolated: Expression = new InterpolatedStringExpression(parts, 2, 5)
    ternary: Expression = new TernaryExpression(
        LcnName("flag"),
        LcnAssign(LcnName("thenArm")),
        LcnAssign(LcnName("elseArm")),
        2,
        5
    )
    cases := new List<MatchCase>()
    cases.Add(new MatchCase(new IdentifierPattern("other", 2, 5), null, LcnAssign(LcnName("armValue"))))
    matchExpression: Expression = new MatchExpression(LcnName("subject"), cases, 2, 5)

    assert LcnExpressionPaths(interpolated) == "hole"
    assert LcnExpressionPaths(ternary) == "thenArm|elseArm"
    assert LcnExpressionPaths(matchExpression) == "armValue"
}

test "a `new`'s arguments and initializer, and an array or tuple element, are walked" {
    initializerProperties := new List<PropertyInitializer>()
    initializerProperties.Add(new PropertyInitializer("Name", null, LcnAssign(LcnName("propertyValue")), 2, 5))
    construction: Expression = new NewExpression(
        new SimpleTypeReference("Widget"),
        LcnArguments(ArgumentModifier.Out, LcnName("outArgument")),
        new ObjectInitializerExpression(initializerProperties, 2, 5),
        2,
        5,
        null
    )

    elements := new List<Expression>()
    elements.Add(LcnAssign(LcnName("element")))
    array: Expression = new ArrayLiteralExpression(elements, false, 2, 5)

    tupleElements := new List<TupleElement>()
    tupleElements.Add(new TupleElement(null, LcnAssign(LcnName("tupleValue"))))
    tuple: Expression = new TupleExpression(tupleElements, 2, 5)

    assert LcnExpressionPaths(construction) == "outArgument|propertyValue"
    assert LcnExpressionPaths(array) == "element"
    assert LcnExpressionPaths(tuple) == "tupleValue"
}

test "the single-operand wrappers are transparent, not opaque" {
    assert LcnExpressionPaths(new ParenthesizedExpression(LcnAssign(LcnName("a")), 2, 5)) == "a"
    assert LcnExpressionPaths(new MustExpression(LcnAssign(LcnName("b")), 2, 5)) == "b"
    assert LcnExpressionPaths(new AwaitExpression(LcnAssign(LcnName("c")), 2, 5)) == "c"
    assert LcnExpressionPaths(new CheckedExpression(LcnAssign(LcnName("d")), 2, 5)) == "d"
    assert LcnExpressionPaths(new SpreadExpression(LcnAssign(LcnName("e")), 2, 5)) == "e"
}

// ── declarations are not writes ────────────────────────────────────────────

test "a declaration introduces a name; only its initializer can write" {
    declaration: Statement = new VariableDeclarationStatement(
        "fresh",
        null,
        LcnAssign(LcnName("nested")),
        VariableKind.Let,
        2,
        1,
        false
    )

    assert LcnStatementPaths(declaration) == "nested"
}

test "`(x, y) = pair` writes both names and `(x, y) := pair` writes neither" {
    names := new List<string>()
    names.Add("first")
    names.Add("second")
    assignment: Statement = new TupleDeconstructionStatement(names, LcnName("pair"), VariableKind.Let, 2, 1, true, true)
    declaration: Statement = new TupleDeconstructionStatement(names, LcnName("pair"), VariableKind.Let, 2, 1, false, true)

    assert LcnStatementPaths(assignment) == "first|second"
    assert LcnStatementPaths(declaration) == ""
}

// ── the entry point ────────────────────────────────────────────────────────

test "a `for`'s UPDATE CLAUSE is part of the back edge and a null body contributes nothing" {
    assert LcnPaths(LcnBlock(LcnAssignStatement(LcnName("a"))), LcnAssign(LcnName("step"))) == "a|step"
    assert LcnPaths(null, LcnAssign(LcnName("step"))) == "step"
    assert LcnPaths(null, null) == ""
}

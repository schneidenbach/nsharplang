namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE LINT WALK (task 019 slice 11). These are the semantic assertions that came out of
// `LintVisitor`'s five mutually recursive walker arms: the function arm, the statement arm and the
// three expression members that guard, dispatch and descend.
//
// THE WALK WAS ONLY ASSERTABLE END-TO-END BEFORE THE MOVE. Every one of these members was a private
// of an `internal` visitor, so "a `for` owns a scope" or "an empty catch block is not walked" could
// only be asked by parsing a file and reading whatever diagnostics fell out. Below, each arm is
// handed an AST it could not otherwise be given — including a CYCLIC one, which no parser produces
// and no end-to-end test could ever have built.
//
// THREE THINGS THAT WERE PROSE OR UNREACHABLE ARE STATED HERE AS CONTRACTS:
//   (a) the recursion guard is a STACK, not a visited-set. A subtree reachable twice is walked
//       twice; only a node that is its own ANCESTOR is skipped. The difference is observable
//       because NL002 reports once per visit, and it is asserted both ways.
//   (b) the two guards answer different questions. The depth counter bounds a deep tree; the
//       visiting set bounds a CIRCULAR one. A cycle without the set would trip the counter and turn
//       a recoverable shape into a throw, so both are asserted alone.
//   (c) a parser-error placeholder suppresses a declaration's BINDING as well as its initializer
//       walk — the linter must not report a name the parser could not read as unused.
func LwkState(): LinterWalkState {
    return new LinterWalkState("test.nl", null, LinterConfig.Default())
}

func LwkCodes(state: LinterWalkState): string {
    codes := ""
    for diagnostic in state.Diagnostics {
        codes = codes + diagnostic.Code + "@" + diagnostic.Location.Line.ToString() + ":" + diagnostic.Location.Column.ToString() + ";"
    }

    return codes
}

func LwkSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

// A type reference stamped where the parser would stamp it, so a contract can tell the TYPE's
// position apart from the `new` keyword's.
func LwkSimpleAt(name: string, line: int, column: int): SimpleTypeReference {
    return new SimpleTypeReference(name, line, column)
}

func LwkId(name: string, line: int, column: int): IdentifierExpression {
    return new IdentifierExpression(name, line, column)
}

func LwkStatements(): List<Statement> {
    return new List<Statement>()
}

func LwkBlockOf(statements: List<Statement>, line: int, column: int): BlockStatement {
    return new BlockStatement(statements, line, column)
}

func LwkBlock1(statement: Statement, line: int, column: int): BlockStatement {
    statements := LwkStatements()
    statements.Add(statement)
    return LwkBlockOf(statements, line, column)
}

func LwkEmptyBlock(line: int, column: int): BlockStatement {
    return LwkBlockOf(LwkStatements(), line, column)
}

func LwkVar(name: string, initializer: Expression?, line: int, column: int): VariableDeclarationStatement {
    return new VariableDeclarationStatement(name, null, initializer, VariableKind.Let, line, column)
}

func LwkRead(name: string, line: int, column: int): ExpressionStatement {
    identifier := LwkId(name, line, column)
    return new ExpressionStatement(identifier, line, column)
}

func LwkReturn(line: int, column: int): ReturnStatement {
    return new ReturnStatement(null, line, column)
}

func LwkThrow(line: int, column: int): ThrowStatement {
    thrown := LwkId("failure", line, column)
    return new ThrowStatement(thrown, line, column)
}

func LwkParam(name: string, line: int, column: int): Parameter {
    return new Parameter(name, LwkSimple("int"), null, false, ParameterModifier.None, null, line, column, false, null)
}

func LwkParams(names: string[]): List<Parameter> {
    parameters := new List<Parameter>()
    index := 0
    while index < names.Length {
        parameters.Add(LwkParam(names[index], 10 + index, 5))
        index = index + 1
    }

    return parameters
}

func LwkFunction(name: string, parameters: List<Parameter>, body: BlockStatement?, expressionBody: Expression?, isAsync: bool): FunctionDeclaration {
    modifiers := Modifiers.None
    if isAsync {
        modifiers = Modifiers.Async
    }

    attributes := new List<AttributeNode>()
    return new FunctionDeclaration(name, parameters, null, body, expressionBody, null, null, modifiers, attributes, false, null, false, false, 7, 1)
}

// A placeholder-bearing initializer: the name the recovery parser mints for a token it could not read.
func LwkBroken(line: int, column: int): IdentifierExpression {
    return LwkId(AnalyzerParserErrorPlaceholders.PlaceholderName(), line, column)
}

func LwkArray(elements: List<Expression>, line: int, column: int): ArrayLiteralExpression {
    return new ArrayLiteralExpression(elements, false, line, column)
}

// A file that writes one namespace import, so the NL010 ledger has something to answer about.
func LwkUnitImporting(namespaceName: string): CompilationUnit {
    imports := new List<ImportDirective>()
    imports.Add(new ImportDirective(namespaceName, null, 1, 1))
    return new CompilationUnit(null, imports, new List<Statement>(), null, new List<Declaration>(), 1, 1)
}

// ── the recursion guard ──────────────────────────────────────────────────────────────────────

test "two structurally identical nodes are two different nodes to the guard" {
    // (a) The guard asks "is this the same NODE", never "is this an equal node". Two identifiers with
    // the same name and the same position are distinct, so both are walked and both report.
    state := LwkState()
    walk := new LinterWalk(state)
    elements := new List<Expression>()
    elements.Add(LwkId("StringBuilder", 3, 5))
    elements.Add(LwkId("StringBuilder", 3, 5))
    walk.VisitExpression(LwkArray(elements, 3, 1))
    assert LwkCodes(state) == "NL002@3:5;NL002@3:5;"
}

test "a SHARED subtree is walked once per occurrence — the guard is a stack, not a visited-set" {
    // (a) The same instance in two child slots is walked twice, because the first walk has already
    // popped it off the guard by the time the second begins.
    state := LwkState()
    walk := new LinterWalk(state)
    shared := LwkId("StringBuilder", 3, 5)
    elements := new List<Expression>()
    elements.Add(shared)
    elements.Add(shared)
    walk.VisitExpression(LwkArray(elements, 3, 1))
    assert LwkCodes(state) == "NL002@3:5;NL002@3:5;"
}

test "a node that is its OWN descendant is entered once and not re-entered" {
    // (b) The cycle arm. A parser cannot build this; the contract can, by mutating the child LIST
    // after the node that owns it has been constructed.
    state := LwkState()
    walk := new LinterWalk(state)
    elements := new List<Expression>()
    cyclic := LwkArray(elements, 3, 1)
    elements.Add(cyclic)
    elements.Add(LwkId("StringBuilder", 3, 5))
    walk.VisitExpression(cyclic)
    assert LwkCodes(state) == "NL002@3:5;"
}

test "the cycle arm's IDENTIFIER half is preserved but cannot be reached by the child walk" {
    // The guard's cycle branch still credits an identifier as READ before skipping it, and that half
    // is reproduced exactly rather than tidied away. It is also UNREACHABLE through the child
    // enumeration, and the reason is executable rather than argued: an identifier is a LEAF, so it
    // has no children and can never be its own ancestor. Only a node with children can be.
    assert AstChildrenCore.IsLeafExpression("IdentifierExpression")
    assert AstChildrenCore.Of(LwkId("value", 1, 1)).Count == 0

    // Non-vacuity: the node kinds the cycle contracts above use are NOT leaves.
    assert !AstChildrenCore.IsLeafExpression("ArrayLiteralExpression")
    assert !AstChildrenCore.IsLeafExpression("BinaryExpression")
}

test "the DEPTH guard trips on a tree deeper than the limit" {
    // (b) The counter's own question, asked without a cycle: a legal but very deep tree.
    state := LwkState()
    walk := new LinterWalk(state)
    node: Expression = LwkId("leaf", 1, 1)
    index := 0
    while index < LinterWalk.MaxRecursionDepth() + 5 {
        elements := new List<Expression>()
        elements.Add(node)
        node = LwkArray(elements, 1, 1)
        index = index + 1
    }

    assert throws InvalidOperationException {
        walk.VisitExpression(node)
    }
}

test "a tree AT the limit is walked, and the counter is restored afterwards" {
    // Non-vacuity for the guard above, plus the `finally`: the same walker answers a second time.
    state := LwkState()
    walk := new LinterWalk(state)
    node: Expression = LwkId("StringBuilder", 4, 2)
    index := 0
    while index < 50 {
        elements := new List<Expression>()
        elements.Add(node)
        node = LwkArray(elements, 1, 1)
        index = index + 1
    }

    walk.VisitExpression(node)
    walk.VisitExpression(node)
    assert LwkCodes(state) == "NL002@4:2;NL002@4:2;"
}

test "a throw out of the walk still unwinds the guard" {
    // The `finally` is load-bearing: after the depth guard trips, the walker is usable again only
    // because every frame decremented and un-marked on the way out.
    state := LwkState()
    walk := new LinterWalk(state)
    deep: Expression = LwkId("leaf", 1, 1)
    index := 0
    while index < LinterWalk.MaxRecursionDepth() + 5 {
        elements := new List<Expression>()
        elements.Add(deep)
        deep = LwkArray(elements, 1, 1)
        index = index + 1
    }

    assert throws InvalidOperationException {
        walk.VisitExpression(deep)
    }

    walk.VisitExpression(LwkId("StringBuilder", 9, 9))
    assert LwkCodes(state) == "NL002@9:9;"
}

// ── the expression arm ───────────────────────────────────────────────────────────────────────

test "an identifier is a read, a mentioned name and a possible missing import, in that order" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.PushScope()
    state.DeclareVariable("value", 2, 3)
    walk.VisitExpression(LwkId("value", 5, 9))
    state.PopScope()
    assert state.Diagnostics.Count == 0
}

test "an identifier the code mentions makes its import used" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.RegisterImports(LwkUnitImporting("System.Text"))
    walk.VisitExpression(LwkId("StringBuilder", 5, 9))
    state.Diagnostics.Clear()
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0
}

test "a string literal's holes are reads, and the RAW literal text is what is scanned" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.PushScope()
    state.DeclareVariable("name", 2, 3)
    walk.VisitExpression(new StringLiteralExpression("$\"hello {name}\"", 5, 1))
    state.PopScope()
    assert state.Diagnostics.Count == 0

    // Non-vacuity: the same declaration with no interpolation reading it.
    idle := LwkState()
    idleWalk := new LinterWalk(idle)
    idle.PushScope()
    idle.DeclareVariable("name", 2, 3)
    idleWalk.VisitExpression(new StringLiteralExpression("$\"hello world\"", 5, 1))
    idle.PopScope()
    assert LwkCodes(idle) == "NL001@2:3;"
}

test "a NEW expression reports its type as a missing import and records it as mentioned" {
    state := LwkState()
    walk := new LinterWalk(state)
    arguments := new List<Argument>()
    constructed := new NewExpression(LwkSimple("StringBuilder"), arguments, null, 4, 7, null)
    walk.VisitExpression(constructed)
    assert LwkCodes(state) == "NL002@1:1;"
}

test "the NEW expression's NL002 lands on the TYPE, not on the `new` keyword" {
    // The walk hands `CheckMissingImportForType` the NewExpression's own position, because that is
    // the only position the arm has. It is the `new` keyword's, and the message is about the type —
    // so the reported span comes from the TYPE REFERENCE and the keyword's position is only the
    // fallback. Here the two are deliberately far apart: `new` at 4:7, `StringBuilder` at 4:11.
    state := LwkState()
    walk := new LinterWalk(state)
    arguments := new List<Argument>()
    constructed := new NewExpression(LwkSimpleAt("StringBuilder", 4, 11), arguments, null, 4, 7, null)
    walk.VisitExpression(constructed)
    assert LwkCodes(state) == "NL002@4:11;"

    // NON-VACUITY: the keyword's position is not simply being ignored in favour of a constant. Move
    // the type and only the report moves; the `new` stays where it was.
    moved := LwkState()
    movedWalk := new LinterWalk(moved)
    movedConstructed := new NewExpression(LwkSimpleAt("StringBuilder", 9, 24), new List<Argument>(), null, 4, 7, null)
    movedWalk.VisitExpression(movedConstructed)
    assert LwkCodes(moved) == "NL002@9:24;"
}

test "a NEW expression with no written type reports nothing and still walks its arguments" {
    state := LwkState()
    walk := new LinterWalk(state)
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, LwkId("StringBuilder", 4, 20), ArgumentModifier.None))
    untyped := new NewExpression(null, arguments, null, 4, 7, null)
    walk.VisitExpression(untyped)
    assert LwkCodes(state) == "NL002@4:20;"
}

test "a member access records the member NAME and walks its receiver" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.RegisterImports(LwkUnitImporting("System.Linq"))
    receiver := LwkId("items", 6, 1)
    walk.VisitExpression(new MemberAccessExpression(receiver, "Select", false, 6, 7))
    state.Diagnostics.Clear()
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0
}

test "an AWAIT expression records the await, so its enclosing async function is not NL004" {
    state := LwkState()
    walk := new LinterWalk(state)
    body := LwkEmptyBlock(8, 1)
    declaration := LwkFunction("f", new List<Parameter>(), body, null, true)
    frame := state.EnterFunction(true)
    awaited := LwkId("task", 9, 5)
    walk.VisitExpression(new AwaitExpression(awaited, 9, 1))
    state.CheckAsyncWithoutAwait(declaration)
    state.ExitFunction(frame)
    assert state.Diagnostics.Count == 0
}

test "a TYPEOF operand is tracked explicitly, because the structural walk never reaches it" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.RegisterImports(LwkUnitImporting("System.Text"))
    walk.VisitExpression(new TypeOfExpression(LwkSimple("StringBuilder"), 5, 1))
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0
}

test "a LAMBDA owns a scope and its parameters are exempt from NL001" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.PushScope()
    parameters := new List<Parameter>()
    parameters.Add(LwkParam("item", 5, 10))
    lambda := new LambdaExpression(parameters, LwkId("item", 5, 20), null, 5, 8)
    walk.VisitExpression(lambda)
    state.PopScope()
    assert state.Diagnostics.Count == 0
}

test "a LAMBDA's BLOCK body is walked as a statement" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.PushScope()
    body := LwkBlock1(LwkVar("unused", null, 6, 9), 5, 30)
    lambda := new LambdaExpression(new List<Parameter>(), null, body, 5, 8)
    walk.VisitExpression(lambda)
    state.PopScope()
    assert LwkCodes(state) == "NL001@6:9;"
}

test "everything else is walked structurally, through the fail-safe child enumeration" {
    // A binary expression has no arm of its own: both operands are reached by the default child walk.
    state := LwkState()
    walk := new LinterWalk(state)
    left := LwkId("StringBuilder", 3, 1)
    right := LwkId("StringBuilder", 3, 20)
    walk.VisitExpression(new BinaryExpression(left, BinaryOperator.Add, right, 3, 10))
    assert LwkCodes(state) == "NL002@3:1;NL002@3:20;"
}

// ── the statement arm ────────────────────────────────────────────────────────────────────────

test "a declaration binds its name and walks its initializer" {
    state := LwkState()
    walk := new LinterWalk(state)
    initializer := LwkId("StringBuilder", 4, 12)
    walk.VisitStatement(LwkBlock1(LwkVar("value", initializer, 4, 5), 3, 1))
    assert LwkCodes(state) == "NL002@4:12;NL001@4:5;"
}

test "(c) a parser-error placeholder suppresses BOTH the binding and the walk" {
    state := LwkState()
    walk := new LinterWalk(state)
    walk.VisitStatement(LwkBlock1(LwkVar("value", LwkBroken(4, 12), 4, 5), 3, 1))
    assert state.Diagnostics.Count == 0
}

test "a block owns a scope, so its bindings do not leak past it" {
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkVar("inner", null, 4, 5))
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert LwkCodes(state) == "NL001@4:5;"
}

test "NL006 is reported ONCE per block and the unreachable statements are not walked" {
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkReturn(4, 5))
    statements.Add(LwkVar("first", null, 5, 5))
    statements.Add(LwkVar("second", null, 6, 5))
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert LwkCodes(state) == "NL006@5:5;"
}

test "a THROW makes the rest of a block unreachable too" {
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkThrow(4, 5))
    statements.Add(LwkVar("after", null, 5, 5))
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert LwkCodes(state) == "NL006@5:5;"
}

test "an ordinary statement does NOT make the rest unreachable" {
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkRead("value", 4, 5))
    statements.Add(LwkVar("after", null, 5, 5))
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert LwkCodes(state) == "NL001@5:5;"
}

test "an IF walks its condition, both branches and the two null-check rules" {
    state := LwkState()
    walk := new LinterWalk(state)
    condition := LwkId("StringBuilder", 4, 8)
    thenStatement: Statement = LwkVar("taken", null, 5, 9)
    elseStatement: Statement = LwkVar("other", null, 7, 9)
    walk.VisitStatement(new IfStatement(condition, thenStatement, elseStatement, 4, 5))
    assert LwkCodes(state) == "NL002@4:8;"

    // The bindings themselves are reported when the enclosing scope closes.
    state.PushScope()
    state.PopScope()
    assert state.Diagnostics.Count == 1
}

test "an IF with no ELSE walks only the taken branch" {
    state := LwkState()
    walk := new LinterWalk(state)
    condition := LwkId("flag", 4, 8)
    thenStatement: Statement = LwkBlock1(LwkVar("taken", null, 5, 9), 4, 20)
    walk.VisitStatement(new IfStatement(condition, thenStatement, null, 4, 5))
    assert LwkCodes(state) == "NL001@5:9;"
}

test "a FOR owns a scope, so its initializer's binding does not leak" {
    state := LwkState()
    walk := new LinterWalk(state)
    initializer: Statement = LwkVar("index", null, 4, 9)
    body: Statement = LwkEmptyBlock(4, 30)
    iterator := LwkId("StringBuilder", 4, 25)
    walk.VisitStatement(new ForStatement(initializer, LwkId("condition", 4, 18), iterator, body, 4, 5))
    assert LwkCodes(state) == "NL002@4:25;NL001@4:9;"
}

test "a FOREACH reads its collection in the OUTER scope and its variable is exempt from NL001" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.PushScope()
    state.DeclareVariable("items", 3, 5)
    collection := LwkId("items", 4, 20)
    body: Statement = LwkEmptyBlock(4, 30)
    walk.VisitStatement(new ForeachStatement("item", collection, body, 4, 5))
    state.PopScope()
    assert state.Diagnostics.Count == 0
}

test "a WHILE walks its condition and body and asks the two null-check rules" {
    state := LwkState()
    walk := new LinterWalk(state)
    body: Statement = LwkBlock1(LwkVar("inner", null, 5, 9), 4, 20)
    walk.VisitStatement(new WhileStatement(LwkId("StringBuilder", 4, 11), body, 4, 5))
    assert LwkCodes(state) == "NL002@4:11;NL001@5:9;"
}

test "a RETURN with no value walks nothing" {
    state := LwkState()
    walk := new LinterWalk(state)
    walk.VisitStatement(LwkReturn(4, 5))
    assert state.Diagnostics.Count == 0

    // Non-vacuity: a return WITH a value walks it.
    valued := LwkState()
    valuedWalk := new LinterWalk(valued)
    valuedWalk.VisitStatement(new ReturnStatement(LwkId("StringBuilder", 4, 12), 4, 5))
    assert LwkCodes(valued) == "NL002@4:12;"
}

test "an EMPTY catch block is NL011 and is not walked" {
    state := LwkState()
    walk := new LinterWalk(state)
    clauses := new List<CatchClause>()
    clauses.Add(new CatchClause(null, null, LwkEmptyBlock(6, 5)))
    walk.VisitStatement(new TryStatement(LwkEmptyBlock(4, 5), clauses, null, 4, 1))
    assert LwkCodes(state) == "NL011@6:5;"
}

test "a catch VARIABLE is bound in its own scope and is exempt from NL001" {
    state := LwkState()
    walk := new LinterWalk(state)
    clauses := new List<CatchClause>()
    caught := LwkBlock1(LwkVar("inner", null, 7, 9), 6, 5)
    clauses.Add(new CatchClause(null, "error", caught))
    walk.VisitStatement(new TryStatement(LwkEmptyBlock(4, 5), clauses, null, 4, 1))
    assert LwkCodes(state) == "NL001@7:9;"
}

test "a FINALLY block is walked" {
    state := LwkState()
    walk := new LinterWalk(state)
    finallyBlock := LwkBlock1(LwkVar("cleanup", null, 9, 9), 8, 5)
    walk.VisitStatement(new TryStatement(LwkEmptyBlock(4, 5), new List<CatchClause>(), finallyBlock, 4, 1))
    assert LwkCodes(state) == "NL001@9:9;"
}

test "a USING owns a scope covering its declaration, its expression and its body" {
    state := LwkState()
    walk := new LinterWalk(state)
    declaration := LwkVar("handle", null, 4, 11)
    resource := LwkId("StringBuilder", 4, 20)
    body: Statement = LwkEmptyBlock(4, 40)
    walk.VisitStatement(new UsingStatement(declaration, resource, body, 4, 5))
    assert LwkCodes(state) == "NL002@4:20;NL001@4:11;"
}

test "every SWITCH case owns its own scope" {
    state := LwkState()
    walk := new LinterWalk(state)
    firstStatements := LwkStatements()
    firstStatements.Add(LwkVar("value", null, 6, 9))
    secondStatements := LwkStatements()
    secondStatements.Add(LwkVar("value", null, 8, 9))
    cases := new List<SwitchCase>()
    cases.Add(new SwitchCase(null, firstStatements, 5, 5))
    cases.Add(new SwitchCase(null, secondStatements, 7, 5))
    walk.VisitStatement(new SwitchStatement(LwkId("subject", 4, 12), cases, 4, 5))

    // Two sibling scopes, so the second binding does not SHADOW the first: two NL001s and no NL020.
    assert LwkCodes(state) == "NL001@6:9;NL001@8:9;"
}

test "a LOCAL FUNCTION opens a function frame of its own" {
    state := LwkState()
    walk := new LinterWalk(state)
    local := LwkFunction("helper", LwkParams(["unused"]), LwkEmptyBlock(8, 20), null, false)
    walk.VisitStatement(new LocalFunctionStatement(local, 8, 5))
    assert LwkCodes(state) == "NL012@10:5;"
}

test "a PRINT, a LOCK, a YIELD and a THROW each walk their operand" {
    state := LwkState()
    walk := new LinterWalk(state)
    walk.VisitStatement(new PrintStatement(LwkId("StringBuilder", 4, 11), 4, 5))
    walk.VisitStatement(new LockStatement(LwkId("StringBuilder", 5, 10), LwkEmptyBlock(5, 20), 5, 5))
    walk.VisitStatement(new YieldStatement(LwkId("StringBuilder", 6, 11), 6, 5))
    walk.VisitStatement(new ThrowStatement(LwkId("StringBuilder", 7, 11), 7, 5))
    assert LwkCodes(state) == "NL002@4:11;NL002@5:10;NL002@6:11;NL002@7:11;"
}

test "a YIELD BREAK carries no value and walks nothing" {
    state := LwkState()
    walk := new LinterWalk(state)
    walk.VisitStatement(new YieldStatement(null, 6, 5))
    assert state.Diagnostics.Count == 0
}

test "an ASSERT walks its condition and its optional message" {
    state := LwkState()
    walk := new LinterWalk(state)
    walk.VisitStatement(new AssertStatement(LwkId("StringBuilder", 4, 12), LwkId("StringBuilder", 4, 30), 4, 5))
    assert LwkCodes(state) == "NL002@4:12;NL002@4:30;"

    // Non-vacuity: the message is optional.
    bare := LwkState()
    bareWalk := new LinterWalk(bare)
    bareWalk.VisitStatement(new AssertStatement(LwkId("StringBuilder", 4, 12), null, 4, 5))
    assert LwkCodes(bare) == "NL002@4:12;"
}

test "an ASSERT THROWS tracks its exception type and walks its body" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.RegisterImports(LwkUnitImporting("System.Text"))
    body := LwkBlock1(LwkVar("inner", null, 6, 9), 5, 20)
    walk.VisitStatement(new AssertThrowsStatement(LwkSimple("StringBuilder"), body, 5, 5))
    state.CheckUnusedImports()
    assert LwkCodes(state) == "NL001@6:9;"
}

test "a TUPLE DECONSTRUCTION binds every name but the discard" {
    state := LwkState()
    walk := new LinterWalk(state)
    names := new List<string>()
    names.Add("first")
    names.Add("_")
    statement := new TupleDeconstructionStatement(names, LwkId("pair", 4, 20), VariableKind.Let, 4, 5)
    walk.VisitStatement(LwkBlock1(statement, 3, 1))
    assert LwkCodes(state) == "NL001@4:5;"
}

test "(c) a parser-error placeholder suppresses a whole deconstruction, bindings included" {
    state := LwkState()
    walk := new LinterWalk(state)
    names := new List<string>()
    names.Add("first")
    statement := new TupleDeconstructionStatement(names, LwkBroken(4, 20), VariableKind.Let, 4, 5)
    walk.VisitStatement(LwkBlock1(statement, 3, 1))
    assert state.Diagnostics.Count == 0
}

test "an AWAIT FOREACH counts as an await, so its async function is not NL004" {
    state := LwkState()
    walk := new LinterWalk(state)
    declaration := LwkFunction("f", new List<Parameter>(), LwkEmptyBlock(8, 1), null, true)
    frame := state.EnterFunction(true)
    body: Statement = LwkEmptyBlock(9, 30)
    walk.VisitStatement(new AwaitForEachStatement("row", LwkId("rows", 9, 20), body, 9, 5))
    state.CheckAsyncWithoutAwait(declaration)
    state.ExitFunction(frame)
    assert state.Diagnostics.Count == 0

    // Non-vacuity: an ordinary foreach over the same collection does NOT record an await.
    idle := LwkState()
    idleWalk := new LinterWalk(idle)
    idleFrame := idle.EnterFunction(true)
    idleBody: Statement = LwkEmptyBlock(9, 30)
    idleWalk.VisitStatement(new ForeachStatement("row", LwkId("rows", 9, 20), idleBody, 9, 5))
    idle.CheckAsyncWithoutAwait(declaration)
    idle.ExitFunction(idleFrame)
    assert LwkCodes(idle) == "NL004@7:1;"
}

test "the shapes NAMED bodyless are silent — and naming them is what makes the tail throw safe" {
    // RETITLED AND RE-PINNED. This used to read "a statement shape with no arm is walked no further",
    // which stated the FAIL-OPEN rule as a fact; that rule is what let `unsafe`/`alloc`/`allow` bodies
    // go unwalked for every lint rule. These six shapes are silent because `IsBodylessStatement` NAMES
    // them silent — they carry no binding, no expression and no nested body — not because nobody wrote
    // their arm.
    state := LwkState()
    walk := new LinterWalk(state)
    walk.VisitStatement(new BreakStatement(4, 5))
    walk.VisitStatement(new ContinueStatement(5, 5))
    walk.VisitStatement(new EmptyStatement(6, 5))
    walk.VisitStatement(new PreprocessorDirective("#if DEBUG", 7, 1))
    walk.VisitStatement(new FileImport("helpers.nl", null, 8, 1))
    walk.VisitStatement(new NamespaceImport("System.Text", null, 9, 1))
    assert state.Diagnostics.Count == 0

    assert LinterWalk.IsBodylessStatement(new BreakStatement(4, 5))
    assert LinterWalk.IsBodylessStatement(new ContinueStatement(5, 5))
    assert LinterWalk.IsBodylessStatement(new EmptyStatement(6, 5))
    assert LinterWalk.IsBodylessStatement(new PreprocessorDirective("#if DEBUG", 7, 1))
    assert LinterWalk.IsBodylessStatement(new FileImport("helpers.nl", null, 8, 1))
    assert LinterWalk.IsBodylessStatement(new NamespaceImport("System.Text", null, 9, 1))

    // Non-vacuity, and the whole point of the list: a shape that is NOT named is not silently skipped.
    assert !LinterWalk.IsBodylessStatement(new UnsafeBlockStatement(LwkEmptyBlock(4, 12), 4, 5))
    assert !LinterWalk.IsBodylessStatement(LwkEmptyBlock(4, 5))
}

test "A STATEMENT KIND WITH NO ARM NOW THROWS — the walk cannot be switched off by a new node kind" {
    // The future-subclass simulation, which is the only way to reach the tail now that every shipped
    // `Statement` is either walked or named bodyless. Before this slice the walk RETURNED here, and a
    // returning tail is how `off`, `unsafe`, `alloc` and `allow` each shipped with the linter blind
    // inside them.
    state := LwkState()
    walk := new LinterWalk(state)
    assert throws InvalidOperationException {
        walk.VisitStatement(new LwkUnknownStatement(11, 7))
    }
}

// ── the three body-carrying wrappers (`unsafe`, `alloc`, `allow`) ────────────────────────────────
//
// EACH OF THESE HAD NO ARM, AND A MISSING ARM DOES NOT WEAKEN ONE RULE — IT SWITCHES THE WHOLE LINTER
// OFF FOR THE SUBTREE. Measured on the shipped CLI before the fix: a local read only inside such a
// body was reported NL001 (an ERROR, so it blocked `nlc build` on correct source), a local declared
// and never read INSIDE one was never reported at all, an import used only inside one was reported
// NL010, and an empty catch block inside one was never NL011. Both directions are pinned below,
// through the source-text census rather than a hand-built tree, because the defect was reachable from
// ordinary source and no hand-built contract had caught it.

test "a local read only inside an `unsafe` body is NOT NL001, and one unread INSIDE it IS" {
    assert LnieCensus("\nfunc F() {\n    a := 1\n    unsafe {\n        print a\n    }\n}\n") == ""
    assert LnieCensus("\nfunc F() {\n    unsafe {\n        b := 2\n    }\n}\n") == "NL001@4:9+1;"
}

test "a local read only inside an `alloc` body is NOT NL001, and one unread INSIDE it IS" {
    assert LnieCensus("\nfunc F() {\n    c := 3\n    alloc {\n        print c\n    }\n}\n") == ""
    assert LnieCensus("\nfunc F() {\n    alloc {\n        d := 4\n    }\n}\n") == "NL001@4:9+1;"
}

test "a local read only inside an `allow(...)` body is NOT NL001, and one unread INSIDE it IS" {
    assert LnieCensus("\nfunc F() {\n    e := 5\n    allow(alloc, reason: \"probe\") {\n        print e\n    }\n}\n") == ""
    assert LnieCensus("\nfunc F() {\n    allow(alloc, reason: \"probe\") {\n        f := 6\n    }\n}\n") == "NL001@4:9+1;"
}

test "the blindness was never NL001-only: NL010 and NL011 were lost inside a wrapper body too" {
    // An import used ONLY inside an `unsafe` body was reported unused, and an empty catch block inside
    // one was never reported. Both are the same missing arm.
    assert LnieCensus("\nimport System.Text\n\nfunc F() {\n    unsafe {\n        sb := new StringBuilder()\n        print sb\n    }\n}\n") == ""
    assert LnieCensus("\nfunc F() {\n    unsafe {\n        try {\n            print 1\n        } catch ex: Exception {\n        }\n    }\n}\n") == "NL011@6:11+5;"
}

test "a wrapper body owns its scope, so a binding inside one does not leak past it" {
    // The arm hands the body to `VisitStatement`, which reaches `VisitBlock` and pushes a scope — so
    // the inner name is reported at the wrapper's close and is NOT visible to the statement after it.
    state := LwkState()
    walk := new LinterWalk(state)
    inner := LwkStatements()
    inner.Add(LwkVar("scoped", null, 5, 9))
    body := LwkBlockOf(inner, 4, 12)
    outer := LwkStatements()
    outer.Add(new UnsafeBlockStatement(body, 4, 5))
    outer.Add(LwkRead("scoped", 8, 5))
    walk.VisitStatement(LwkBlockOf(outer, 3, 1))
    assert LwkCodes(state) == "NL001@5:9;"
}

test "`alloc` and `allow` walk their bodies through the same arm shape as `unsafe`" {
    allocState := LwkState()
    allocWalk := new LinterWalk(allocState)
    allocWalk.VisitStatement(new AllocBlockStatement(LwkBlock1(LwkVar("dead", null, 5, 9), 4, 12), 4, 5))
    assert LwkCodes(allocState) == "NL001@5:9;"

    allowState := LwkState()
    allowWalk := new LinterWalk(allowState)
    effects := new List<string>()
    effects.Add("alloc")
    allowWalk.VisitStatement(new AllowStatement(effects, "probe", null, LwkBlock1(LwkVar("dead", null, 5, 9), 4, 12), 4, 5))
    assert LwkCodes(allowState) == "NL001@5:9;"
}

// ── the operand slots a read-walk must see (the `off` / pattern family) ──────────────────────────
//
// One rule, three sites: EVERY EXPRESSION AN OPERAND SLOT CARRIES IS A READ. `off`'s handle had no
// statement arm at all; a switch case's pattern and a match case's pattern are not `Expression`s, so
// neither `VisitSwitch` nor `AstChildrenCore.Of` ever reached the expressions they hold. All three
// reported a false NL001 against a variable the code plainly reads, and NL001 is an ERROR — it blocks
// `nlc build`. The negatives below are what keep the rule from over-silencing: a name a pattern BINDS
// is not credited as a read, because the used-name set is file-wide.

test "an OFF statement's handle is a READ — a subscription consumed only by `off` is not NL001" {
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkVar("sub", null, 4, 5))
    statements.Add(new OffStatement(LwkId("sub", 5, 9), 5, 5))
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert state.Diagnostics.Count == 0
}

test "a variable NOTHING reads is still NL001 beside an `off`" {
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkVar("sub", null, 4, 5))
    statements.Add(LwkVar("dead", null, 5, 5))
    statements.Add(new OffStatement(LwkId("sub", 6, 9), 6, 5))
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert LwkCodes(state) == "NL001@5:5;"
}

test "a SWITCH case pattern's compared value is a READ" {
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkVar("limit", null, 4, 5))
    cases := new List<SwitchCase>()
    cases.Add(new SwitchCase(new RelationalPattern(">", LwkId("limit", 6, 16), 6, 14), LwkStatements(), 6, 9))
    // `default` carries a NULL pattern, which walks nothing rather than throwing.
    cases.Add(new SwitchCase(null, LwkStatements(), 7, 9))
    switchStatement: Statement = new SwitchStatement(LwkId("value", 5, 12), cases, 5, 5)
    statements.Add(switchStatement)
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert state.Diagnostics.Count == 0
}

test "a MATCH case pattern's compared value is a READ, and the structural walk still runs" {
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkVar("limit", null, 4, 5))
    cases := new List<MatchCase>()
    cases.Add(new MatchCase(new RelationalPattern(">", LwkId("limit", 6, 11), 6, 9), null, LwkId("big", 6, 20)))
    matchExpression: Expression = new MatchExpression(LwkId("value", 5, 14), cases, 5, 5)
    statements.Add(new ExpressionStatement(matchExpression, 5, 5))
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert state.Diagnostics.Count == 0

    // Non-vacuity: the arm still routes through the child walk, so a guard and an arm expression are
    // read exactly as they were before the pattern arm existed.
    guarded := LwkState()
    guardedWalk := new LinterWalk(guarded)
    guardedCases := new List<MatchCase>()
    guardedCases.Add(new MatchCase(new IdentifierPattern("bound", 6, 9), LwkId("StringBuilder", 6, 20), LwkId("StringBuilder", 6, 40)))
    guardedMatch: Expression = new MatchExpression(LwkId("value", 5, 14), guardedCases, 5, 5)
    guardedWalk.VisitExpression(guardedMatch)
    assert LwkCodes(guarded) == "NL002@6:20;NL002@6:40;"
}

test "a pattern's BINDING name is NOT credited as a read" {
    // The used-name set is file-wide, so crediting `case bound =>` would silence the NL001 that the
    // unread LOCAL named `bound` has earned.
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkVar("bound", null, 4, 5))
    cases := new List<SwitchCase>()
    cases.Add(new SwitchCase(new IdentifierPattern("bound", 6, 14), LwkStatements(), 6, 9))
    switchStatement: Statement = new SwitchStatement(LwkId("value", 5, 12), cases, 5, 5)
    statements.Add(switchStatement)
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert LwkCodes(state) == "NL001@4:5;"
}

test "a NESTED pattern's compared value is reached through every composite shape" {
    // and / or / not / positional / list / object / union-case each recurse; a slice pattern and a
    // type pattern carry no expression at all and walk nothing.
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkVar("low", null, 4, 5))
    statements.Add(LwkVar("high", null, 5, 5))
    statements.Add(LwkVar("edge", null, 6, 5))
    statements.Add(LwkVar("tail", null, 7, 5))

    properties := new List<PropertyPattern>()
    properties.Add(new PropertyPattern("Radius", new RelationalPattern(">", LwkId("low", 9, 30), 9, 28), null, 9, 20))
    positionalElements := new List<Pattern>()
    positionalElements.Add(new NotPattern(new RelationalPattern("<", LwkId("high", 9, 50), 9, 48), 9, 44))
    listElements := new List<Pattern>()
    listElements.Add(new SlicePattern("rest", 9, 60))
    listElements.Add(new RelationalPattern(">=", LwkId("tail", 9, 70), 9, 67))

    combined: Pattern = new AndPattern(new UnionCasePattern("Shape.Circle", properties, 9, 14), new OrPattern(new PositionalPattern(positionalElements, 9, 44), new ListPattern(listElements, 9, 58), 9, 44), 9, 14)
    objectProperties := new List<PropertyPattern>()
    objectProperties.Add(new PropertyPattern("Count", new RelationalPattern("==", LwkId("edge", 10, 30), 10, 28), null, 10, 20))

    cases := new List<SwitchCase>()
    cases.Add(new SwitchCase(combined, LwkStatements(), 9, 9))
    cases.Add(new SwitchCase(new ObjectPattern(objectProperties, 10, 14), LwkStatements(), 10, 9))
    switchStatement: Statement = new SwitchStatement(LwkId("value", 8, 12), cases, 8, 5)
    statements.Add(switchStatement)
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert state.Diagnostics.Count == 0
}

// ── the function arm ─────────────────────────────────────────────────────────────────────────

test "a function's signature type references are mentioned names" {
    state := LwkState()
    walk := new LinterWalk(state)
    state.RegisterImports(LwkUnitImporting("System.Text"))
    parameters := new List<Parameter>()
    parameters.Add(new Parameter("builder", LwkSimple("StringBuilder"), null, false, ParameterModifier.None, null, 7, 10, false, null))
    declaration := LwkFunction("f", parameters, LwkEmptyBlock(7, 30), null, false)
    walk.VisitFunction(declaration)
    state.Diagnostics.Clear()
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0
}

test "an unread parameter is NL012 and never NL001" {
    state := LwkState()
    walk := new LinterWalk(state)
    declaration := LwkFunction("f", LwkParams(["unused"]), LwkEmptyBlock(7, 30), null, false)
    walk.VisitFunction(declaration)
    assert LwkCodes(state) == "NL012@10:5;"
}

test "a read parameter is silent" {
    state := LwkState()
    walk := new LinterWalk(state)
    body := LwkBlock1(LwkRead("used", 8, 9), 7, 30)
    declaration := LwkFunction("f", LwkParams(["used"]), body, null, false)
    walk.VisitFunction(declaration)
    assert state.Diagnostics.Count == 0
}

test "an EXPRESSION-bodied function declares its parameters too" {
    state := LwkState()
    walk := new LinterWalk(state)
    declaration := LwkFunction("f", LwkParams(["unused"]), null, LwkId("constant", 7, 20), false)
    walk.VisitFunction(declaration)
    assert LwkCodes(state) == "NL012@10:5;"
}

test "a function with NEITHER body opens no scope and reports nothing" {
    state := LwkState()
    walk := new LinterWalk(state)
    declaration := LwkFunction("f", LwkParams(["unused"]), null, null, false)
    walk.VisitFunction(declaration)
    assert state.Diagnostics.Count == 0
}

test "an async function with a block body and no await is NL004" {
    state := LwkState()
    walk := new LinterWalk(state)
    declaration := LwkFunction("f", new List<Parameter>(), LwkEmptyBlock(7, 30), null, true)
    walk.VisitFunction(declaration)
    assert LwkCodes(state) == "NL004@7:1;"
}

test "the async flag is read from the modifier bits" {
    assert LinterWalk.IsAsync(LwkFunction("f", new List<Parameter>(), null, null, true))
    assert !LinterWalk.IsAsync(LwkFunction("f", new List<Parameter>(), null, null, false))
}

test "a NESTED function's await does not silence the ENCLOSING function's NL004" {
    // The frame is per-function: the inner walk's await belongs to the inner function alone.
    state := LwkState()
    walk := new LinterWalk(state)
    inner := LwkFunction("inner", new List<Parameter>(), LwkBlock1(new ExpressionStatement(new AwaitExpression(LwkId("task", 9, 20), 9, 14), 9, 9), 8, 30), null, true)
    innerStatement: Statement = new LocalFunctionStatement(inner, 8, 5)
    outer := LwkFunction("outer", new List<Parameter>(), LwkBlock1(innerStatement, 7, 30), null, true)
    walk.VisitFunction(outer)
    assert LwkCodes(state) == "NL004@7:1;"
}

test "a CAPTURED parameter read inside a nested function counts as read" {
    state := LwkState()
    walk := new LinterWalk(state)
    innerBody := LwkBlock1(LwkRead("captured", 9, 9), 8, 30)
    inner := LwkFunction("inner", new List<Parameter>(), innerBody, null, false)
    innerStatement: Statement = new LocalFunctionStatement(inner, 8, 5)
    outer := LwkFunction("outer", LwkParams(["captured"]), LwkBlock1(innerStatement, 7, 30), null, false)
    walk.VisitFunction(outer)
    assert state.Diagnostics.Count == 0
}

// ── a type NAMED in a pattern, an `is`, an `as` (the written-type family) ───────────────────────
//
// A `TypeReference` IS NOT AN `Expression`, so `AstChildrenCore.Of` cannot hand one over and no walk
// reaches it without an explicit arm. `typeof` had that arm; the other six type slots did not, and a
// type written in one of them was invisible to BOTH import rules: NL010 reported the import that
// supplies it as unused (an ERROR — it fails `nlc check` on correct source), and NL002 was never asked
// whether the import was missing at all. Measured before the fix on four source-reachable positions:
// `match x { Foo f => … }`, `switch x { case Foo f => … }`, `x is Foo` (with and without a binding) and
// `x as Foo` each reported a false NL010, while `new Foo()` and `typeof(Foo)` — the two tracked
// controls — did not.
//
// THE PATTERN'S TYPE REFERENCE ALSO HAD TO BE GIVEN A POSITION. The recovery parser built it at 0,0,
// and NL002 refuses to report without one, so tracking the pattern alone fixed NL010 and left NL002
// still silent there. Both halves are pinned below: the import present (silent) and the import absent
// (NL002 under the type name, at the exact column the type is written).

test "a type named ONLY in a `match` type pattern makes its import used, and needs one when absent" {
    assert LnieCensus("\nimport System.Text\n\nfunc F(o: object): string {\n    return match o {\n        StringBuilder sb => \"sb\",\n        _ => \"x\"\n    }\n}\n") == ""
    assert LnieCensus("\nfunc F(o: object): string {\n    return match o {\n        StringBuilder sb => \"sb\",\n        _ => \"x\"\n    }\n}\n") == "NL002@4:9+13;"
}

test "a type named ONLY in a `switch` case type pattern behaves identically" {
    assert LnieCensus("\nimport System.Text\n\nfunc F(o: object): int {\n    switch o {\n        case StringBuilder sb => return 1\n        default => return 0\n    }\n}\n") == ""
    assert LnieCensus("\nfunc F(o: object): int {\n    switch o {\n        case StringBuilder sb => return 1\n        default => return 0\n    }\n}\n") == "NL002@4:14+13;"
}

test "a type named ONLY in an `is` test makes its import used, and needs one when absent" {
    assert LnieCensus("\nimport System.Text\n\nfunc F(o: object): bool {\n    return o is StringBuilder\n}\n") == ""
    assert LnieCensus("\nfunc F(o: object): bool {\n    return o is StringBuilder\n}\n") == "NL002@3:17+13;"
}

test "a type named ONLY in an `as` cast makes its import used, and needs one when absent" {
    assert LnieCensus("\nimport System.Text\n\nfunc F(o: object): int {\n    sb := o as StringBuilder\n    if sb != null {\n        return 1\n    }\n\n    return 0\n}\n") == ""
    assert LnieCensus("\nfunc F(o: object): int {\n    sb := o as StringBuilder\n    if sb != null {\n        return 1\n    }\n\n    return 0\n}\n") == "NL002@3:16+13;"
}

test "a pattern's BINDING is still not a read — the widening credits the TYPE and nothing else" {
    // Non-vacuity for the banner: `Foo f` mentions `Foo` and introduces `f`. If the binding were
    // credited as a read, the unrelated `f` below would stop being NL001.
    assert LnieCensus("\nimport System.Text\n\nfunc F(o: object): string {\n    f := 1\n    return match o {\n        StringBuilder f => \"sb\",\n        _ => \"x\"\n    }\n}\n") == "NL001@5:5+1;"
}

test "the three type slots no source spelling reaches today are tracked all the same" {
    // `sizeof(T)` and `stackalloc T[n]` make the columnar parser decline the enclosing function, which
    // suppresses the whole file's lint pass, and an explicit call type argument parses as a comparison
    // — so none of the three can be reached from source right now. They are contracted through the walk
    // directly, so that fixing either front end cannot silently reopen the hole for them.
    sizeState := LwkState()
    sizeWalk := new LinterWalk(sizeState)
    sizeWalk.VisitExpression(new SizeOfExpression(LwkSimpleAt("StringBuilder", 4, 12), 4, 5))
    assert LwkCodes(sizeState) == "NL002@4:12;"

    stackState := LwkState()
    stackWalk := new LinterWalk(stackState)
    stackWalk.VisitExpression(new StackAllocExpression(LwkSimpleAt("StringBuilder", 5, 16), LwkId("count", 5, 31), 5, 5))
    assert LwkCodes(stackState) == "NL002@5:16;"

    callState := LwkState()
    callWalk := new LinterWalk(callState)
    typeArguments := new List<TypeReference>()
    typeArguments.Add(LwkSimpleAt("StringBuilder", 6, 14))
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, LwkId("value", 6, 29), ArgumentModifier.None))
    callWalk.VisitExpression(new CallExpression(LwkId("Echo", 6, 9), arguments, typeArguments, 6, 9))
    assert LwkCodes(callState) == "NL002@6:14;"
}

test "each type-slot arm still walks its operand — the type is IN ADDITION, never instead" {
    // The arms return early, so the child walk has to be called explicitly in each one. A dropped
    // `VisitChildExpressions` would turn every `(Foo)bar` and `bar is Foo` into a lost read of `bar`,
    // which is the exact NL001 false positive this family exists to prevent.
    state := LwkState()
    walk := new LinterWalk(state)
    statements := LwkStatements()
    statements.Add(LwkVar("subject", null, 4, 5))
    statements.Add(new ExpressionStatement(new IsExpression(LwkId("subject", 5, 5), LwkSimple("int"), null, 5, 5), 5, 5))
    walk.VisitStatement(LwkBlockOf(statements, 3, 1))
    assert state.Diagnostics.Count == 0

    castState := LwkState()
    castWalk := new LinterWalk(castState)
    castStatements := LwkStatements()
    castStatements.Add(LwkVar("subject", null, 4, 5))
    castExpression: Expression = new CastExpression(LwkId("subject", 5, 12), LwkSimple("int"), CastKind.Safe, 5, 5)
    castStatements.Add(new ExpressionStatement(castExpression, 5, 5))
    castWalk.VisitStatement(LwkBlockOf(castStatements, 3, 1))
    assert castState.Diagnostics.Count == 0
}

test "A PATTERN KIND WITH NO ARM NOW THROWS, and the two binding-only kinds are NAMED silent" {
    assert LinterWalk.IsBindingOnlyPattern(new IdentifierPattern("bound", 4, 9))
    assert LinterWalk.IsBindingOnlyPattern(new SlicePattern("rest", 4, 9))
    assert !LinterWalk.IsBindingOnlyPattern(new TypePattern(LwkSimple("int"), "n", 4, 9))

    state := LwkState()
    walk := new LinterWalk(state)
    walk.VisitPattern(new IdentifierPattern("bound", 4, 9))
    walk.VisitPattern(new SlicePattern("rest", 5, 9))
    assert state.Diagnostics.Count == 0

    assert throws InvalidOperationException {
        walk.VisitPattern(new LwkUnknownPattern(6, 9))
    }
}

// A `Statement` subclass the walk has never heard of — the stand-in for the NEXT node kind someone
// adds. It exists so the fail-safe tail can be asserted rather than described; every shipped
// `Statement` is now either walked or named bodyless, so nothing else can reach that throw.
class LwkUnknownStatement: Statement {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// The pattern sibling of `LwkUnknownStatement`, for the pattern arm's own fail-safe tail.
class LwkUnknownPattern: Pattern {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

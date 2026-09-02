namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for whether a value exists by the time something reads it.
//
// TWO ANALYSES, PINNED SEPARATELY, BECAUSE THEY DISAGREE. The CONSTRUCTOR collector and the LOCAL
// walk both answer "is this definitely assigned?" and they answer it with different rules — the
// collector does not enter a single-branch `if` at all and counts nothing inside a loop or a `try`,
// while the local walk enters everything and merges by intersection. That disagreement is behaviour
// `Analyzer.cs` shipped, so it is pinned rather than reconciled.
//
// WHAT THE CORPUS DOES NOT DECIDE IS MOST OF IT. The 72-target corpus compiles clean, so neither of
// this owner's two NL304 reports fires in the oracle at all; every reporting shape, every merge
// rule and every exit rule had to be built here.
//
// THE MERGE RULES ARE THE POINT. A branch that always exits contributes NOTHING to the merge, a
// loop body contributes nothing because it may run zero times, a `try` block contributes nothing
// because it may throw partway, and a `switch` contributes only when it has a default. Each of
// those is a separate contract, because each is a separate way to be wrong.
class DefiniteAssignmentHarness {
    Owner: AnalyzerDefiniteAssignment
    Errors: List<CompilerError>
    Context: AnalyzerDeclarationContext

    constructor(
        owner: AnalyzerDefiniteAssignment,
        errors: List<CompilerError>,
        context: AnalyzerDeclarationContext
    ) {
        Owner = owner
        Errors = errors
        Context = context
    }
}

func DefiniteAssignmentDefault(): DefiniteAssignmentHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal)
    )
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        diagnostics,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal),
        new SemanticModel(),
        new BindingMap()
    )

    return new DefiniteAssignmentHarness(
        new AnalyzerDefiniteAssignment(diagnostics, resolver),
        errors,
        context
    )
}

// ── AST builders ──────────────────────────────────────────────────────────

func DaStatements(): List<Statement> {
    return new List<Statement>()
}

func DaBlock(statements: List<Statement>): BlockStatement {
    return new BlockStatement(statements, 1, 1)
}

func DaEmptyBlock(): BlockStatement {
    return DaBlock(DaStatements())
}

func DaOneBlock(statement: Statement): BlockStatement {
    statements := DaStatements()
    statements.Add(statement)
    return DaBlock(statements)
}

func DaTwoBlock(first: Statement, second: Statement): BlockStatement {
    statements := DaStatements()
    statements.Add(first)
    statements.Add(second)
    return DaBlock(statements)
}

func DaThreeBlock(first: Statement, second: Statement, third: Statement): BlockStatement {
    statements := DaStatements()
    statements.Add(first)
    statements.Add(second)
    statements.Add(third)
    return DaBlock(statements)
}

// A local declared WITHOUT an initializer — the only shape the walk tracks.
func DaDeclare(name: string): VariableDeclarationStatement {
    return new VariableDeclarationStatement(name, null, null, VariableKind.Let, 1, 1)
}

func DaDeclareWith(name: string, initializer: Expression): VariableDeclarationStatement {
    return new VariableDeclarationStatement(name, null, initializer, VariableKind.Let, 1, 1)
}

func DaName(name: string, line: int, column: int): IdentifierExpression {
    return new IdentifierExpression(name, line, column)
}

func DaRead(name: string, line: int, column: int): ExpressionStatement {
    return new ExpressionStatement(DaName(name, line, column), line, column)
}

func DaAssign(name: string, value: Expression): ExpressionStatement {
    target := DaName(name, 1, 1)
    assignment := new AssignmentExpression(target, AssignmentOperator.Assign, value, 1, 1)
    return new ExpressionStatement(assignment, 1, 1)
}

func DaCompoundRead(name: string, line: int, column: int): ExpressionStatement {
    target := DaName(name, line, column)
    assignment := new AssignmentExpression(target, AssignmentOperator.AddAssign, DaInt(1), line, column)
    return new ExpressionStatement(assignment, line, column)
}

func DaInt(value: int): IntLiteralExpression {
    return new IntLiteralExpression(value.ToString(), 1, 1)
}

func DaIf(condition: Expression, thenStatement: Statement, elseStatement: Statement?): IfStatement {
    return new IfStatement(condition, thenStatement, elseStatement, 1, 1)
}

func DaTrue(): BoolLiteralExpression {
    return new BoolLiteralExpression(true, 1, 1)
}

func DaReturn(): ReturnStatement {
    return new ReturnStatement(null, 1, 1)
}

func DaThrow(): ThrowStatement {
    return new ThrowStatement(DaInt(1), 1, 1)
}

func DaCase(pattern: Pattern?, statements: List<Statement>): SwitchCase {
    return new SwitchCase(pattern, statements, 1, 1)
}

func DaOneCaseStatements(statement: Statement): List<Statement> {
    statements := DaStatements()
    statements.Add(statement)
    return statements
}

func DaTwoCaseStatements(first: Statement, second: Statement): List<Statement> {
    statements := DaStatements()
    statements.Add(first)
    statements.Add(second)
    return statements
}

func DaSwitch(cases: List<SwitchCase>): SwitchStatement {
    return new SwitchStatement(DaInt(0), cases, 1, 1)
}

func DaCases(): List<SwitchCase> {
    return new List<SwitchCase>()
}

func DaFunction(name: string): FunctionDeclaration {
    return new FunctionDeclaration(
        name,
        new List<Parameter>(),
        null,
        DaEmptyBlock(),
        null,
        null,
        null,
        Modifiers.None,
        new List<AttributeNode>(),
        false,
        null,
        false,
        false,
        1,
        1
    )
}

func DaWildcard(): IdentifierPattern {
    return new IdentifierPattern("value", 1, 1)
}

// ── the local walk: the basic report ──────────────────────────────────────

test "a local declared WITH an initializer is assigned and reading it is silent" {
    harness := DefiniteAssignmentDefault()
    body := DaTwoBlock(DaDeclareWith("x", DaInt(1)), DaRead("x", 5, 3))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "a local declared WITHOUT an initializer reports NL304 at the READ" {
    harness := DefiniteAssignmentDefault()
    body := DaTwoBlock(DaDeclare("x"), DaRead("x", 5, 3))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.DefiniteAssignmentError
    assert harness.Errors[0].Line == 5
    assert harness.Errors[0].Column == 3
}
test "the read-before-assignment message and suggestion name the local" {
    harness := DefiniteAssignmentDefault()
    body := DaTwoBlock(DaDeclare("total"), DaRead("total", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors[0].Message == "'total' is used here before it has been assigned a value on every path that reaches this point"
    assert harness.Errors[0].Suggestion == "Give 'total' an initial value where you declare it, or assign it on every branch before this use."
}
test "the span is the NAME's length, never shorter than one" {
    harness := DefiniteAssignmentDefault()
    body := DaTwoBlock(DaDeclare("abcd"), DaRead("abcd", 2, 2))

    harness.Owner.CheckLocals(body)

    assert harness.Errors[0].Length == 4
}
test "assigning before the read silences it" {
    harness := DefiniteAssignmentDefault()
    body := DaThreeBlock(DaDeclare("x"), DaAssign("x", DaInt(1)), DaRead("x", 5, 3))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "an untracked name — never declared without an initializer — never reports" {
    harness := DefiniteAssignmentDefault()
    body := DaOneBlock(DaRead("free", 3, 3))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "TWO DISTINCT reads of the same unassigned local both report" {
    harness := DefiniteAssignmentDefault()
    body := DaThreeBlock(DaDeclare("x"), DaRead("x", 5, 3), DaRead("x", 6, 3))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 2
}
test "the SAME read reports once even though a loop body walks it twice" {
    harness := DefiniteAssignmentDefault()
    loop := new WhileStatement(DaTrue(), DaOneBlock(DaRead("x", 7, 4)), 1, 1)
    body := DaTwoBlock(DaDeclare("x"), loop)

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 7
}

// ── the local walk: the merge rules ───────────────────────────────────────

test "an if that assigns on BOTH branches leaves the local assigned afterwards" {
    harness := DefiniteAssignmentDefault()
    branchIf := DaIf(DaTrue(), DaAssign("x", DaInt(1)), DaAssign("x", DaInt(2)))
    body := DaThreeBlock(DaDeclare("x"), branchIf, DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "an if that assigns on ONE branch leaves the local unassigned afterwards" {
    harness := DefiniteAssignmentDefault()
    branchIf := DaIf(DaTrue(), DaAssign("x", DaInt(1)), null)
    body := DaThreeBlock(DaDeclare("x"), branchIf, DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 9
}
test "a THEN branch that always exits hands the ELSE branch's assignments to the survivor" {
    harness := DefiniteAssignmentDefault()
    thenBranch := DaOneBlock(DaReturn())
    elseBranch := DaOneBlock(DaAssign("x", DaInt(2)))
    body := DaThreeBlock(DaDeclare("x"), DaIf(DaTrue(), thenBranch, elseBranch), DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "an ELSE branch that always exits hands the THEN branch's assignments to the survivor" {
    harness := DefiniteAssignmentDefault()
    thenBranch := DaOneBlock(DaAssign("x", DaInt(1)))
    elseBranch := DaOneBlock(DaThrow())
    body := DaThreeBlock(DaDeclare("x"), DaIf(DaTrue(), thenBranch, elseBranch), DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "a guard clause with no else does NOT survive: a single-branch if that returns assigns nothing" {
    harness := DefiniteAssignmentDefault()
    body := DaThreeBlock(
        DaDeclare("x"),
        DaIf(DaTrue(), DaOneBlock(DaReturn()), null),
        DaRead("x", 9, 1)
    )

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
}
test "when BOTH branches exit the statement itself always exits and stops the block" {
    harness := DefiniteAssignmentDefault()
    exitingIf := DaIf(DaTrue(), DaOneBlock(DaReturn()), DaOneBlock(DaThrow()))
    body := DaThreeBlock(DaDeclare("x"), exitingIf, DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    // The read is UNREACHABLE and the block stops before it, so nothing is reported.
    assert harness.Errors.Count == 0
}
test "an assignment inside a while body does not survive the loop" {
    harness := DefiniteAssignmentDefault()
    loop := new WhileStatement(DaTrue(), DaOneBlock(DaAssign("x", DaInt(1))), 1, 1)
    body := DaThreeBlock(DaDeclare("x"), loop, DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 9
}
test "a read inside a loop body of a local assigned BEFORE the loop is silent" {
    harness := DefiniteAssignmentDefault()
    loop := new WhileStatement(DaTrue(), DaOneBlock(DaRead("x", 7, 4)), 1, 1)
    body := DaThreeBlock(DaDeclare("x"), DaAssign("x", DaInt(1)), loop)

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "a for statement's INITIALIZER assigns, and its condition and iterator are read" {
    harness := DefiniteAssignmentDefault()
    loop := new ForStatement(
        DaAssign("x", DaInt(0)),
        DaName("x", 4, 4),
        DaName("y", 5, 5),
        DaEmptyBlock(),
        1,
        1
    )
    body := DaThreeBlock(DaDeclare("x"), DaDeclare("y"), loop)

    harness.Owner.CheckLocals(body)

    // `x` is assigned by the initializer before the condition reads it; `y` is not.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 5
}
test "a foreach reads its COLLECTION and its body does not survive" {
    harness := DefiniteAssignmentDefault()
    loop := new ForeachStatement("item", DaName("items", 3, 7), DaOneBlock(DaAssign("x", DaInt(1))), 1, 1)
    body := DaThreeBlock(DaDeclare("items"), loop, DaRead("items", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Line == 3
    assert harness.Errors[1].Line == 9
}
test "an await-foreach reads its collection the same way" {
    harness := DefiniteAssignmentDefault()
    loop := new AwaitForEachStatement("item", DaName("items", 3, 7), DaEmptyBlock(), 1, 1)
    body := DaTwoBlock(DaDeclare("items"), loop)

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 3
}

// ── the local walk: switch, try, using, lock ──────────────────────────────

test "a switch WITHOUT a default keeps only the pre-switch assignments" {
    harness := DefiniteAssignmentDefault()
    cases := DaCases()
    cases.Add(DaCase(DaWildcard(), DaOneCaseStatements(DaAssign("x", DaInt(1)))))
    body := DaThreeBlock(DaDeclare("x"), DaSwitch(cases), DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
}
test "a switch WITH a default keeps the intersection of its non-exiting cases" {
    harness := DefiniteAssignmentDefault()
    cases := DaCases()
    cases.Add(DaCase(DaWildcard(), DaOneCaseStatements(DaAssign("x", DaInt(1)))))
    cases.Add(DaCase(null, DaOneCaseStatements(DaAssign("x", DaInt(2)))))
    body := DaThreeBlock(DaDeclare("x"), DaSwitch(cases), DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "a case that does NOT assign drops the name from the intersection" {
    harness := DefiniteAssignmentDefault()
    cases := DaCases()
    cases.Add(DaCase(DaWildcard(), DaOneCaseStatements(DaAssign("x", DaInt(1)))))
    cases.Add(DaCase(null, DaOneCaseStatements(DaAssign("y", DaInt(2)))))
    body := DaThreeBlock(DaDeclare("x"), DaSwitch(cases), DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
}
test "a switch with a default whose every case exits always exits itself" {
    harness := DefiniteAssignmentDefault()
    cases := DaCases()
    cases.Add(DaCase(DaWildcard(), DaOneCaseStatements(DaReturn())))
    cases.Add(DaCase(null, DaOneCaseStatements(DaThrow())))
    body := DaThreeBlock(DaDeclare("x"), DaSwitch(cases), DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    // The read after the switch is unreachable, so the block stops before it.
    assert harness.Errors.Count == 0
}
test "a case's statements stop at the first one that exits" {
    harness := DefiniteAssignmentDefault()
    cases := DaCases()
    cases.Add(DaCase(null, DaTwoCaseStatements(DaReturn(), DaRead("x", 7, 7))))
    body := DaTwoBlock(DaDeclare("x"), DaSwitch(cases))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "a try block's assignments are DISCARDED afterwards" {
    harness := DefiniteAssignmentDefault()
    tryStmt := new TryStatement(
        DaOneBlock(DaAssign("x", DaInt(1))),
        new List<CatchClause>(),
        null,
        1,
        1
    )
    body := DaThreeBlock(DaDeclare("x"), tryStmt, DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
}
test "a CATCH clause starts from the PRE-TRY state, not from the try block's" {
    harness := DefiniteAssignmentDefault()
    catches := new List<CatchClause>()
    catches.Add(new CatchClause(null, "e", DaOneBlock(DaRead("x", 6, 6))))
    tryStmt := new TryStatement(DaOneBlock(DaAssign("x", DaInt(1))), catches, null, 1, 1)
    body := DaTwoBlock(DaDeclare("x"), tryStmt)

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 6
}
test "a FINALLY block also runs against the pre-try state" {
    harness := DefiniteAssignmentDefault()
    tryStmt := new TryStatement(
        DaOneBlock(DaAssign("x", DaInt(1))),
        new List<CatchClause>(),
        DaOneBlock(DaRead("x", 8, 2)),
        1,
        1
    )
    body := DaTwoBlock(DaDeclare("x"), tryStmt)

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 8
}
test "a try statement never itself always-exits" {
    harness := DefiniteAssignmentDefault()
    tryStmt := new TryStatement(DaOneBlock(DaReturn()), new List<CatchClause>(), null, 1, 1)
    body := DaThreeBlock(DaDeclare("x"), tryStmt, DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
}
test "a using statement reads its expression, flows its declaration and RETURNS its body's verdict" {
    harness := DefiniteAssignmentDefault()
    usingStmt := new UsingStatement(
        DaDeclareWith("handle", DaInt(1)),
        DaName("source", 3, 3),
        DaOneBlock(DaReturn()),
        1,
        1
    )
    body := DaThreeBlock(DaDeclare("source"), usingStmt, DaRead("source", 9, 1))

    harness.Owner.CheckLocals(body)

    // The expression read reports; the read AFTER the using is unreachable.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 3
}
test "a lock statement reads its object and its body flows through without exiting" {
    harness := DefiniteAssignmentDefault()
    lockStmt := new LockStatement(DaName("gate", 4, 4), DaOneBlock(DaReturn()), 1, 1)
    body := DaThreeBlock(DaDeclare("gate"), lockStmt, DaRead("gate", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 2
}
test "an assert statement reads its condition and its message" {
    harness := DefiniteAssignmentDefault()
    assertStmt := new AssertStatement(DaName("a", 3, 3), DaName("b", 4, 4), 1, 1)
    body := DaThreeBlock(DaDeclare("a"), DaDeclare("b"), assertStmt)

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 2
}
test "alloc, allow and unsafe blocks flow their bodies through" {
    harness := DefiniteAssignmentDefault()
    allocBlock := new AllocBlockStatement(DaOneBlock(DaRead("a", 3, 3)), 1, 1)
    allowBlock := new AllowStatement(new List<string>(), null, null, DaOneBlock(DaRead("b", 4, 4)), 1, 1)
    unsafeBlock := new UnsafeBlockStatement(DaOneBlock(DaRead("c", 5, 5)), 1, 1)
    statements := DaStatements()
    statements.Add(DaDeclare("a"))
    statements.Add(DaDeclare("b"))
    statements.Add(DaDeclare("c"))
    statements.Add(allocBlock)
    statements.Add(allowBlock)
    statements.Add(unsafeBlock)

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 3
}

// ── the local walk: the two arms that are not recursion ───────────────────

test "an OUT argument ASSIGNS its target rather than reading it" {
    harness := DefiniteAssignmentDefault()
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, DaName("x", 3, 3), ArgumentModifier.Out))
    call := new CallExpression(DaName("TryGet", 3, 1), arguments, null, 3, 1)
    body := DaThreeBlock(
        DaDeclare("x"),
        new ExpressionStatement(call, 3, 1),
        DaRead("x", 9, 1)
    )

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "a REF argument is an ordinary read and reports" {
    harness := DefiniteAssignmentDefault()
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, DaName("x", 3, 3), ArgumentModifier.Ref))
    call := new CallExpression(DaName("Use", 3, 1), arguments, null, 3, 1)
    body := DaTwoBlock(DaDeclare("x"), new ExpressionStatement(call, 3, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 3
}
test "nameof does not read the value of its operand" {
    harness := DefiniteAssignmentDefault()
    nameofExpr := new NameofExpression(DaName("x", 3, 3), 3, 1)
    body := DaTwoBlock(DaDeclare("x"), new ExpressionStatement(nameofExpr, 3, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "a lambda body does not consume the enclosing flow state" {
    harness := DefiniteAssignmentDefault()
    lambda := new LambdaExpression(new List<Parameter>(), DaName("x", 3, 3), null, 3, 1)
    body := DaTwoBlock(DaDeclare("x"), new ExpressionStatement(lambda, 3, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "a COMPOUND assignment reads its target first and reports" {
    harness := DefiniteAssignmentDefault()
    body := DaTwoBlock(DaDeclare("x"), DaCompoundRead("x", 4, 2))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 4
}
test "a PLAIN assignment to an unassigned local does not read it" {
    harness := DefiniteAssignmentDefault()
    body := DaTwoBlock(DaDeclare("x"), DaAssign("x", DaInt(1)))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 0
}
test "an assignment whose TARGET is not an identifier is walked as a read" {
    harness := DefiniteAssignmentDefault()
    target := new MemberAccessExpression(DaName("box", 3, 3), "Value", false, 3, 1)
    assignment := new AssignmentExpression(target, AssignmentOperator.Assign, DaInt(1), 3, 1)
    body := DaTwoBlock(DaDeclare("box"), new ExpressionStatement(assignment, 3, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 3
}
test "tuple deconstruction assigns every name except the discard" {
    harness := DefiniteAssignmentDefault()
    names := new List<string>()
    names.Add("a")
    names.Add("_")
    deconstruction := new TupleDeconstructionStatement(names, DaInt(1), VariableKind.Let, 1, 1)
    statements := DaStatements()
    statements.Add(DaDeclare("a"))
    statements.Add(DaDeclare("_"))
    statements.Add(deconstruction)
    statements.Add(DaRead("a", 8, 1))
    statements.Add(DaRead("_", 9, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 9
}
test "return and throw are exits; yield is NOT" {
    harness := DefiniteAssignmentDefault()
    yieldStmt := new YieldStatement(DaInt(1), 1, 1)
    body := DaThreeBlock(DaDeclare("x"), yieldStmt, DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
}
test "break and continue are exits and stop the block" {
    harness := DefiniteAssignmentDefault()
    statements := DaStatements()
    statements.Add(DaDeclare("x"))
    statements.Add(new BreakStatement(1, 1))
    statements.Add(DaRead("x", 9, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 0
}
test "a local function statement contributes nothing and does not exit" {
    harness := DefiniteAssignmentDefault()
    local := new LocalFunctionStatement(DaFunction("inner"), 1, 1)
    body := DaThreeBlock(DaDeclare("x"), local, DaRead("x", 9, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
}

// ── the local walk: the recursion arms that carry a read ──────────────────

test "every wrapping expression arm carries the read through to the identifier" {
    harness := DefiniteAssignmentDefault()
    statements := DaStatements()
    statements.Add(DaDeclare("x"))
    statements.Add(new ExpressionStatement(new ParenthesizedExpression(DaName("x", 3, 1), 3, 1), 3, 1))
    statements.Add(new ExpressionStatement(new AwaitExpression(DaName("x", 4, 1), 4, 1), 4, 1))
    statements.Add(new ExpressionStatement(new MustExpression(DaName("x", 5, 1), 5, 1), 5, 1))
    statements.Add(new ExpressionStatement(new CheckedExpression(DaName("x", 6, 1), 6, 1), 6, 1))
    statements.Add(new ExpressionStatement(new UncheckedExpression(DaName("x", 7, 1), 7, 1), 7, 1))
    statements.Add(new ExpressionStatement(new AllocExpression(DaName("x", 8, 1), 8, 1), 8, 1))
    statements.Add(new ExpressionStatement(new SpreadExpression(DaName("x", 9, 1), 9, 1), 9, 1))
    statements.Add(new ExpressionStatement(new ThrowExpression(DaName("x", 10, 1), 10, 1), 10, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 8
}
test "a binary expression reads both sides and a ternary reads all three" {
    harness := DefiniteAssignmentDefault()
    binary := new BinaryExpression(DaName("a", 3, 1), BinaryOperator.Add, DaName("b", 3, 5), 3, 1)
    ternary := new TernaryExpression(DaName("a", 4, 1), DaName("b", 4, 5), DaName("c", 4, 9), 4, 1)
    statements := DaStatements()
    statements.Add(DaDeclare("a"))
    statements.Add(DaDeclare("b"))
    statements.Add(DaDeclare("c"))
    statements.Add(new ExpressionStatement(binary, 3, 1))
    statements.Add(new ExpressionStatement(ternary, 4, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 5
}
test "an index access reads its object AND its index" {
    harness := DefiniteAssignmentDefault()
    index := new IndexAccessExpression(DaName("a", 3, 1), DaName("b", 3, 3), false, 3, 1)
    statements := DaStatements()
    statements.Add(DaDeclare("a"))
    statements.Add(DaDeclare("b"))
    statements.Add(new ExpressionStatement(index, 3, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 2
}
test "an interpolated string reads its HOLES and not its text" {
    harness := DefiniteAssignmentDefault()
    parts := new List<InterpolatedStringPart>()
    parts.Add(new InterpolatedStringText("literal", 3, 1))
    parts.Add(new InterpolatedStringHole(DaName("x", 3, 9), null, 3, 9))
    interpolated := new InterpolatedStringExpression(parts, 3, 1)
    body := DaTwoBlock(DaDeclare("x"), new ExpressionStatement(interpolated, 3, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
}
test "a new expression reads its arguments, its array length and its initializer" {
    harness := DefiniteAssignmentDefault()
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, DaName("a", 3, 1), ArgumentModifier.None))
    properties := new List<PropertyInitializer>()
    properties.Add(new PropertyInitializer("P", DaName("b", 4, 1), DaName("c", 4, 5), 0, 0))
    initializer := new ObjectInitializerExpression(properties, 4, 1)
    newExpr := new NewExpression(null, arguments, initializer, 3, 1, DaName("d", 5, 1))
    statements := DaStatements()
    statements.Add(DaDeclare("a"))
    statements.Add(DaDeclare("b"))
    statements.Add(DaDeclare("c"))
    statements.Add(DaDeclare("d"))
    statements.Add(new ExpressionStatement(newExpr, 3, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 4
}
test "a with expression reads its target and every property" {
    harness := DefiniteAssignmentDefault()
    properties := new List<PropertyInitializer>()
    properties.Add(new PropertyInitializer("P", DaName("b", 4, 1), DaName("c", 4, 5), 0, 0))
    withExpr := new WithExpression(DaName("a", 3, 1), properties, 3, 1)
    statements := DaStatements()
    statements.Add(DaDeclare("a"))
    statements.Add(DaDeclare("b"))
    statements.Add(DaDeclare("c"))
    statements.Add(new ExpressionStatement(withExpr, 3, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 3
}
test "an array literal, a tuple and a range each read their elements" {
    harness := DefiniteAssignmentDefault()
    elements := new List<Expression>()
    elements.Add(DaName("a", 3, 1))
    arrayLiteral := new ArrayLiteralExpression(elements, false, 3, 1)
    tupleElements := new List<TupleElement>()
    tupleElements.Add(new TupleElement(null, DaName("b", 4, 1)))
    tuple := new TupleExpression(tupleElements, 4, 1)
    range := new RangeExpression(DaName("c", 5, 1), DaName("d", 5, 5), 5, 1)
    statements := DaStatements()
    statements.Add(DaDeclare("a"))
    statements.Add(DaDeclare("b"))
    statements.Add(DaDeclare("c"))
    statements.Add(DaDeclare("d"))
    statements.Add(new ExpressionStatement(arrayLiteral, 3, 1))
    statements.Add(new ExpressionStatement(tuple, 4, 1))
    statements.Add(new ExpressionStatement(range, 5, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 4
}
test "a print statement reads its value and an is-expression reads its operand" {
    harness := DefiniteAssignmentDefault()
    isExpr := new IsExpression(DaName("b", 4, 1), new SimpleTypeReference("int", 0, 0), null, 4, 1)
    statements := DaStatements()
    statements.Add(DaDeclare("a"))
    statements.Add(DaDeclare("b"))
    statements.Add(new PrintStatement(DaName("a", 3, 1), 3, 1))
    statements.Add(new ExpressionStatement(isExpr, 4, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 2
}
test "a return with a value reads it before it exits" {
    harness := DefiniteAssignmentDefault()
    body := DaTwoBlock(DaDeclare("x"), new ReturnStatement(DaName("x", 3, 8), 3, 1))

    harness.Owner.CheckLocals(body)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Column == 8
}
test "a re-declaration without an initializer CLEARS a previous assignment" {
    harness := DefiniteAssignmentDefault()
    statements := DaStatements()
    statements.Add(DaDeclare("x"))
    statements.Add(DaAssign("x", DaInt(1)))
    statements.Add(DaDeclare("x"))
    statements.Add(DaRead("x", 9, 1))

    harness.Owner.CheckLocals(DaBlock(statements))

    assert harness.Errors.Count == 1
}

// ── the constructor collector ─────────────────────────────────────────────

func DaField(name: string, typeName: string?, initializer: Expression?, modifiers: Modifiers): FieldDeclaration {
    fieldType: TypeReference? = null
    if typeName != null {
        fieldType = new SimpleTypeReference(typeName, 0, 0)
    }

    return new FieldDeclaration(
        name,
        fieldType,
        initializer,
        modifiers,
        PropertyModifier.None,
        new List<AttributeNode>(),
        1,
        1
    )
}

func DaClass(members: List<Declaration>): ClassDeclaration {
    return new ClassDeclaration(
        "Widget",
        null,
        null,
        new List<TypeReference>(),
        members,
        null,
        Modifiers.Public,
        new List<AttributeNode>(),
        1,
        1
    )
}

func DaOneMember(member: Declaration): List<Declaration> {
    members := new List<Declaration>()
    members.Add(member)
    return members
}

func DaConstructor(body: BlockStatement, line: int, column: int): ConstructorDeclaration {
    return new ConstructorDeclaration(
        new List<Parameter>(),
        body,
        null,
        Modifiers.Public,
        new List<AttributeNode>(),
        line,
        column
    )
}

func DaThisAssign(memberName: string): ExpressionStatement {
    target := new MemberAccessExpression(new ThisExpression(1, 1), memberName, false, 1, 1)
    assignment := new AssignmentExpression(target, AssignmentOperator.Assign, DaInt(1), 1, 1)
    return new ExpressionStatement(assignment, 1, 1)
}

test "an unassigned non-nullable field reports NL304 on the CONSTRUCTOR" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", null, Modifiers.Public)))

    harness.Owner.CheckConstructorFields(DaConstructor(DaEmptyBlock(), 12, 5), classDecl)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.DefiniteAssignmentError
    assert harness.Errors[0].Line == 12
    assert harness.Errors[0].Column == 5
    assert harness.Errors[0].Length == 11
    assert harness.Errors[0].Message == "Field 'Count' is non-nullable but isn't assigned in this constructor — either assign it here or give it a default value in its declaration"
    // The report passes NO suggestion, so the sink substitutes the CODE's default. That is the
    // shape `Analyzer.cs` shipped and it is pinned rather than reproduced by passing the text.
    assert harness.Errors[0].Suggestion == "Initialize property in constructor or provide default value"
}
test "a field assigned through `this` counts as assigned" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", null, Modifiers.Public)))

    harness.Owner.CheckConstructorFields(DaConstructor(DaOneBlock(DaThisAssign("Count")), 12, 5), classDecl)

    assert harness.Errors.Count == 0
}
test "a field assigned through a BARE name counts as assigned" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", null, Modifiers.Public)))

    harness.Owner.CheckConstructorFields(
        DaConstructor(DaOneBlock(DaAssign("Count", DaInt(1))), 12, 5),
        classDecl
    )

    assert harness.Errors.Count == 0
}
test "a STATIC field is not part of any instance constructor's contract" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Shared", "int", null, Modifiers.Static)))

    harness.Owner.CheckConstructorFields(DaConstructor(DaEmptyBlock(), 12, 5), classDecl)

    assert harness.Errors.Count == 0
}
test "a field WITH an initializer is skipped" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", DaInt(0), Modifiers.Public)))

    harness.Owner.CheckConstructorFields(DaConstructor(DaEmptyBlock(), 12, 5), classDecl)

    assert harness.Errors.Count == 0
}
test "a field with an INFERRED type is skipped — it always has an initializer" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", null, null, Modifiers.Public)))

    harness.Owner.CheckConstructorFields(DaConstructor(DaEmptyBlock(), 12, 5), classDecl)

    assert harness.Errors.Count == 0
}
test "a NULLABLE field is skipped" {
    harness := DefiniteAssignmentDefault()
    nullableInt: TypeReference = new NullableTypeReference(new SimpleTypeReference("int", 0, 0))
    field := new FieldDeclaration(
        "Count",
        nullableInt,
        null,
        Modifiers.Public,
        PropertyModifier.None,
        new List<AttributeNode>(),
        1,
        1
    )
    classDecl := DaClass(DaOneMember(field))

    harness.Owner.CheckConstructorFields(DaConstructor(DaEmptyBlock(), 12, 5), classDecl)

    assert harness.Errors.Count == 0
}
test "a non-field member is not a field and is ignored" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaFunction("Run")))

    harness.Owner.CheckConstructorFields(DaConstructor(DaEmptyBlock(), 12, 5), classDecl)

    assert harness.Errors.Count == 0
}
test "an assignment in a NESTED BLOCK counts" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", null, Modifiers.Public)))
    body := DaOneBlock(DaOneBlock(DaThisAssign("Count")))

    harness.Owner.CheckConstructorFields(DaConstructor(body, 12, 5), classDecl)

    assert harness.Errors.Count == 0
}
test "an assignment on BOTH branches of an if counts" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", null, Modifiers.Public)))
    branchIf := DaIf(DaTrue(), DaThisAssign("Count"), DaThisAssign("Count"))

    harness.Owner.CheckConstructorFields(DaConstructor(DaOneBlock(branchIf), 12, 5), classDecl)

    assert harness.Errors.Count == 0
}
test "an assignment on ONE branch of a two-branch if does NOT count" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", null, Modifiers.Public)))
    branchIf := DaIf(DaTrue(), DaThisAssign("Count"), DaThisAssign("Other"))

    harness.Owner.CheckConstructorFields(DaConstructor(DaOneBlock(branchIf), 12, 5), classDecl)

    assert harness.Errors.Count == 1
}
test "a SINGLE-branch if is not entered at all, even for an unconditional assignment inside it" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", null, Modifiers.Public)))
    branchIf := DaIf(DaTrue(), DaThisAssign("Count"), null)

    harness.Owner.CheckConstructorFields(DaConstructor(DaOneBlock(branchIf), 12, 5), classDecl)

    assert harness.Errors.Count == 1
}
test "an assignment inside a while, a for, a foreach, a try, a using or a lock counts for NOTHING" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", null, Modifiers.Public)))
    statements := DaStatements()
    statements.Add(new WhileStatement(DaTrue(), DaOneBlock(DaThisAssign("Count")), 1, 1))
    statements.Add(new ForStatement(null, null, null, DaOneBlock(DaThisAssign("Count")), 1, 1))
    statements.Add(new ForeachStatement("i", DaInt(1), DaOneBlock(DaThisAssign("Count")), 1, 1))
    statements.Add(new TryStatement(DaOneBlock(DaThisAssign("Count")), new List<CatchClause>(), null, 1, 1))
    statements.Add(new UsingStatement(null, null, DaOneBlock(DaThisAssign("Count")), 1, 1))
    statements.Add(new LockStatement(DaInt(1), DaOneBlock(DaThisAssign("Count")), 1, 1))

    harness.Owner.CheckConstructorFields(DaConstructor(DaBlock(statements), 12, 5), classDecl)

    assert harness.Errors.Count == 1
}
test "an assignment whose target is neither `this.X` nor a bare name counts for nothing" {
    harness := DefiniteAssignmentDefault()
    classDecl := DaClass(DaOneMember(DaField("Count", "int", null, Modifiers.Public)))
    target := new MemberAccessExpression(DaName("other", 1, 1), "Count", false, 1, 1)
    assignment := new AssignmentExpression(target, AssignmentOperator.Assign, DaInt(1), 1, 1)
    body := DaOneBlock(new ExpressionStatement(assignment, 1, 1))

    harness.Owner.CheckConstructorFields(DaConstructor(body, 12, 5), classDecl)

    assert harness.Errors.Count == 1
}
test "every unassigned field gets its OWN report" {
    harness := DefiniteAssignmentDefault()
    members := new List<Declaration>()
    members.Add(DaField("Alpha", "int", null, Modifiers.Public))
    members.Add(DaField("Beta", "int", null, Modifiers.Public))
    classDecl := DaClass(members)

    harness.Owner.CheckConstructorFields(DaConstructor(DaEmptyBlock(), 12, 5), classDecl)

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "Field 'Alpha' is non-nullable but isn't assigned in this constructor — either assign it here or give it a default value in its declaration"
    assert harness.Errors[1].Message == "Field 'Beta' is non-nullable but isn't assigned in this constructor — either assign it here or give it a default value in its declaration"
}

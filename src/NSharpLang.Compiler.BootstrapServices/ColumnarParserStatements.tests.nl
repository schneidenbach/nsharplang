namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL STATEMENT-SHAPE CONTRACTS FOR `ColumnarParserRecovery.ParseFileAst`, IN N#.
//
// These replace the STATEMENT tranche of `tests/ParserTests.cs` — 23 of its remaining 162 `[Fact]`s,
// 608 C# lines, 140 `Assert.` occurrences — which task 020 slice 18 deletes. The tranche is the
// statement family proper (`let`/`:=`, `if`/`else`, `for`, `foreach`, `try`/`catch`/`finally`,
// `yield`, `using`, `lock`, `switch`, `print`) plus the ten test-DSL declarations that carry
// statement bodies (`test`, `setup`, `teardown`, the table-driven and skip forms, and the `assert` /
// `assert throws` statements). The declaration family moved in slice 17 to
// `ColumnarParserDeclarations.tests.nl` and the four NON-EXPRESSION families — patterns and `match`,
// parameter and argument modifiers, operator and conversion overloads, constructor initializers — in
// slice 19 to `ColumnarParserPatterns.tests.nl`, and the four SMALL families — the file header,
// literals and interpolation, attributes and the preprocessor — in slice 20 to
// `ColumnarParserSmallFamilies.tests.nl`; and the CALL-AND-ACCESS tier of the expression family —
// member access, call, index, range, `new` and its initializers, and generic calls — in slice 21 to
// `ColumnarParserCallAccess.tests.nl`. `tests/ParserTests.cs` survives at 30 methods carrying the
// other half of the expressions, which is the arc's last tranche and deletes the file.
//
// THE STATEMENT KINDS THIS FAMILY NEVER TESTED ARE NOT MISSING — THEY ARE PINNED NEXT DOOR.
// `while`, `const`/`readonly` locals, `break`, `continue`, `throw`, `unsafe`, `alloc`, `allow`, local
// functions, tuple deconstruction, the empty statement and `await foreach` appear ZERO times in all
// 4,729 lines of `ParserTests.cs`, and every one of them already has whole-tree contracts in
// `ColumnarParserAst.tests.nl`'s stage-N+1c tranche 10. Nothing is added here for them, because a
// second copy of an existing pin is not additional coverage.
//
// THE ROUTE IS THE WHOLE-TREE GOLDEN, AND IT IS STRICTLY STRONGER THAN WHAT IT REPLACES.
// Twenty of the twenty-three migrated cases went through one private helper:
//
//     private static CompilationUnit Parse(string source)
//         => ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit!;
//
// followed by a handful of member reads — `funcDecl!.Body.Statements[0] as IfStatement`,
// `Assert.NotNull(ifStmt!.ElseStatement)`. (The other three — the table-driven, skip and
// `TestTestDeclaration` cases — called `ParseFileAst(source, null)` inline with a NULL file name;
// `CompilationUnit` carries no file field, so the tree is identical and these contracts pass
// "test.nl" like the rest.) A whole-tree diff pins every node, every registered field and every
// anchor at once, so a parser that answered the right statement KIND with the wrong nesting, or the
// right condition with the wrong Line/Column, was invisible to the deleted assertions and is not
// invisible here. `AstEq.Diff` and the `Golden.*` builders both live in `ColumnarParserAst.tests.nl`
// next door; the registry there already covered the whole statement family, and this slice added only
// the RETURNING list-element builders (`ArgF` / `CatchF` / `CaseF` / `TextPart` / `HolePart`) and the
// three test-DSL declaration builders (`TestF` / `SetupF` / `TeardownF`), because an APPENDER cannot
// be nested inside the argument list of the node that contains it.
//
// THE SECOND CLAIM IN EVERY CONTRACT IS THAT THE SOURCE PARSES CLEANLY, AND THAT CLAIM IS NEW.
// `Parse()` above reads `.CompilationUnit` and DISCARDS `.Errors` entirely, so every positive case in
// `ParserTests.cs` is silent about whether the source it calls "valid" produces any diagnostic at
// all. Each contract below pins `PsCensus(source) == ""` first. **MEASURED RESULT FOR THIS TRANCHE:
// all 23 sources parse with an EMPTY diagnostic list**, which is the same verdict slice 17 measured
// over its 50 — the pin has now found no defect over 73 real-world fixtures and is kept, because it
// is the guard that makes the silence impossible to re-introduce.
//
// THE CENSUS IS IN RECORDING ORDER, WHICH IS THE ORDER `ParseFileAst` RETURNS AND NOT THE ORDER THE
// CLI SHOWS. `ColumnarParserRecovery.ParseFilePreamble` sorts by position; `ParseFileAst` does not.
// It is empty for all 23 sources today, so no ordering is observable here — the convention is stated
// because a future contract in this file will be the first to observe it.
//
// THE SOURCES ARE THE DELETED FIXTURES BYTE-FOR-BYTE, leading newline, twelve-space indentation and
// trailing eight spaces included, so every pinned Line/Column is a claim about the SAME text the C#
// parsed. That is why the columns are large: `func` sits at column 13, not column 1.
//
// WHAT THE WHOLE-TREE PINS MEASURED THAT THE DELETED ASSERTIONS COULD NOT SEE is recorded per
// contract below and summarised in `memory/components/parser.md`.

// The return type is `CompilationUnit?` because `FileParseAst.CompilationUnit` IS nullable, and
// declaring it non-null is what puts an NL202 row on the sibling `RunAst` next door. `AstEq.Diff`
// takes `object?` on both sides, so the nullable handle is never dereferenced here and no NL905
// follows it either — this file reports ZERO `nlc check` rows, tests included.
func PsAst(source: string): CompilationUnit? {
    return ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit
}

// Every diagnostic's code and span, in `ParseFileAst`'s recording order. Empty for a clean parse.
// A string kernel rather than a nullable `CompilerError?` handle, because a `.tests.nl` must produce
// ZERO `nlc check` rows and a nullable node handle produces NL905s.
func PsCensus(source: string): string {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    builder := new StringBuilder()
    index := 0
    while index < parsed.Errors.Count {
        e := parsed.Errors[index]
        builder.Append(e.DiagnosticId)
        builder.Append("@")
        builder.Append(e.Line.ToString())
        builder.Append(":")
        builder.Append(e.Column.ToString())
        builder.Append("+")
        builder.Append(e.Length.ToString())
        builder.Append(";")
        index = index + 1
    }
    return builder.ToString()
}


// ---- contracts ----

test "020 s18 parser statements: `let x: int = 42` and `y := \"hello\"` are the SAME node with the SAME Kind=Let — the shorthand differs only in a null Type (was ParserTests.TestVariableDeclaration)" {
    source := "\n            func Test() {\n                let x: int = 42\n                y := \"hello\"\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("x", Golden.SimpleT("int", 3, 24, 27), Golden.IntLit("42", 3, 30), VariableKind.Let, 3, 21))
    stmts2.Add(Golden.VarDecl("y", null, Golden.StrLit("\"hello\"", 4, 22), VariableKind.Let, 4, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: an if/else materializes both arms as BlockStatements anchored on their own `{`, and the condition anchors on `>`, not on its left operand (was ParserTests.TestIfStatement)" {
    source := "\n            func Test() {\n                if x > 5 {\n                    return true\n                } else {\n                    return false\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.BoolLit(true, 4, 28), 4, 21))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.Return(Golden.BoolLit(false, 6, 28), 6, 21))
    stmts2.Add(Golden.If(Golden.Bin(Golden.Ident("x", 3, 20), BinaryOperator.Greater, Golden.IntLit("5", 3, 24), 3, 22), Golden.Block(stmts3, 3, 26), Golden.Block(stmts4, 5, 24), 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: a three-clause `for` carries a VariableDeclarationStatement initializer, a binary condition, and a PostIncrement iterator anchored on `++` rather than on `i` (was ParserTests.TestForLoop)" {
    source := "\n            func Test() {\n                for i := 0; i < 10; i++ {\n                    Console.WriteLine(i)\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts3 := new List<Statement>()
    args4 := new List<Argument>()
    args4.Add(Golden.ArgF(null, Golden.Ident("i", 4, 39), ArgumentModifier.None))
    stmts3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 4, 21), "WriteLine", false, 4, 28), args4, Golden.NoTypeArgs(), 4, 38), 4, 21))
    stmts2.Add(Golden.For(Golden.VarDecl("i", null, Golden.IntLit("0", 3, 26), VariableKind.Let, 3, 21), Golden.Bin(Golden.Ident("i", 3, 29), BinaryOperator.Less, Golden.IntLit("10", 3, 33), 3, 31), Golden.Un(UnaryOperator.PostIncrement, Golden.Ident("i", 3, 37), 3, 38), Golden.Block(stmts3, 3, 41), 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `foreach item in items` stores the loop variable as a bare NAME, with no node and no anchor of its own (was ParserTests.TestForeachLoop)" {
    source := "\n            func Test() {\n                foreach item in items {\n                    Console.WriteLine(item)\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts3 := new List<Statement>()
    args4 := new List<Argument>()
    args4.Add(Golden.ArgF(null, Golden.Ident("item", 4, 39), ArgumentModifier.None))
    stmts3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 4, 21), "WriteLine", false, 4, 28), args4, Golden.NoTypeArgs(), 4, 38), 4, 21))
    stmts2.Add(Golden.Foreach("item", Golden.Ident("items", 3, 33), Golden.Block(stmts3, 3, 39), 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: try / catch / finally: the CatchClause has NO Line/Column at all, and the finally block anchors on its own `{` (was ParserTests.TestTryCatchFinally)" {
    source := "\n            func Test() {\n                try {\n                    DoSomething()\n                } catch (Exception ex) {\n                    Console.WriteLine(ex)\n                } finally {\n                    Cleanup()\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.ExprStmt(Golden.Call(Golden.Ident("DoSomething", 4, 21), Golden.NoArgs(), Golden.NoTypeArgs(), 4, 32), 4, 21))
    catches4 := new List<CatchClause>()
    stmts5 := new List<Statement>()
    args6 := new List<Argument>()
    args6.Add(Golden.ArgF(null, Golden.Ident("ex", 6, 39), ArgumentModifier.None))
    stmts5.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 6, 21), "WriteLine", false, 6, 28), args6, Golden.NoTypeArgs(), 6, 38), 6, 21))
    catches4.Add(Golden.CatchF(Golden.SimpleT("Exception", 5, 26, 35), "ex", Golden.Block(stmts5, 5, 40)))
    stmts7 := new List<Statement>()
    stmts7.Add(Golden.ExprStmt(Golden.Call(Golden.Ident("Cleanup", 8, 21), Golden.NoArgs(), Golden.NoTypeArgs(), 8, 28), 8, 21))
    stmts2.Add(Golden.Try(Golden.Block(stmts3, 3, 21), catches4, Golden.Block(stmts7, 7, 27), 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: the N# `catch ex: T` form produces exactly the C# `catch (T ex)` CatchClause shape, and leaves FinallyBlock null (was ParserTests.TestCatchClauseNSharpParameterSyntax)" {
    source := "\n            func Parse(): int {\n                try {\n                    return 1\n                } catch ex: FormatException {\n                    return -1\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.IntLit("1", 4, 28), 4, 21))
    catches4 := new List<CatchClause>()
    stmts5 := new List<Statement>()
    stmts5.Add(Golden.Return(Golden.Un(UnaryOperator.Negate, Golden.IntLit("1", 6, 29), 6, 28), 6, 21))
    catches4.Add(Golden.CatchF(Golden.SimpleT("FormatException", 5, 29, 44), "ex", Golden.Block(stmts5, 5, 45)))
    stmts2.Add(Golden.Try(Golden.Block(stmts3, 3, 21), catches4, null, 3, 17))
    decls1.Add(Golden.Func("Parse", Golden.NoParams(), Golden.SimpleT("int", 2, 27, 30), Golden.Block(stmts2, 2, 31), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `func*` sets Modifiers.Generator on the FUNCTION, and each `yield` anchors on the keyword, not on its value (was ParserTests.TestIteratorFunction)" {
    source := "\n            func* GetNumbers(): IEnumerable<int> {\n                yield 1\n                yield 2\n                yield 3\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    typerefs2 := new List<TypeReference>()
    typerefs2.Add(Golden.SimpleT("int", 2, 45, 48))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Yield(Golden.IntLit("1", 3, 23), 3, 17))
    stmts3.Add(Golden.Yield(Golden.IntLit("2", 4, 23), 4, 17))
    stmts3.Add(Golden.Yield(Golden.IntLit("3", 5, 23), 5, 17))
    decls1.Add(Golden.Func("GetNumbers", Golden.NoParams(), Golden.GenericT("IEnumerable", typerefs2, 2, 33, 49), Golden.Block(stmts3, 2, 50), null, null, null, Modifiers.Generator, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `yield break` is a YieldStatement with a null Value sitting in the same list as the valued ones (was ParserTests.TestYieldBreak)" {
    source := "\n            func* GetNumbers(): IEnumerable<int> {\n                yield 1\n                yield break\n                yield 2\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    typerefs2 := new List<TypeReference>()
    typerefs2.Add(Golden.SimpleT("int", 2, 45, 48))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Yield(Golden.IntLit("1", 3, 23), 3, 17))
    stmts3.Add(Golden.Yield(null, 4, 17))
    stmts3.Add(Golden.Yield(Golden.IntLit("2", 5, 23), 5, 17))
    decls1.Add(Golden.Func("GetNumbers", Golden.NoParams(), Golden.GenericT("IEnumerable", typerefs2, 2, 33, 49), Golden.Block(stmts3, 2, 50), null, null, null, Modifiers.Generator, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `using stream := …` anchors its DECLARATION on the `using` keyword, not on the name, and leaves the Expression arm null (was ParserTests.TestUsingStatement)" {
    source := "\n            func Test() {\n                using stream := File.OpenRead(\"file.txt\") {\n                    data := stream.Read()\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    args3 := new List<Argument>()
    args3.Add(Golden.ArgF(null, Golden.StrLit("\"file.txt\"", 3, 47), ArgumentModifier.None))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.VarDecl("data", null, Golden.Call(Golden.Member(Golden.Ident("stream", 4, 29), "Read", false, 4, 35), Golden.NoArgs(), Golden.NoTypeArgs(), 4, 40), VariableKind.Let, 4, 21))
    stmts2.Add(Golden.Using(Golden.VarDecl("stream", null, Golden.Call(Golden.Member(Golden.Ident("File", 3, 33), "OpenRead", false, 3, 37), args3, Golden.NoTypeArgs(), 3, 46), VariableKind.Let, 3, 17), null, Golden.Block(stmts4, 3, 59), 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `lock obj { … }` anchors the lock object on the identifier and the body on its `{` (was ParserTests.TestLockStatement)" {
    source := "\n            func Increment() {\n                lock _lockObject {\n                    _counter++\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.ExprStmt(Golden.Un(UnaryOperator.PostIncrement, Golden.Ident("_counter", 4, 21), 4, 29), 4, 21))
    stmts2.Add(Golden.Lock(Golden.Ident("_lockObject", 3, 22), Golden.Block(stmts3, 3, 34), 3, 17))
    decls1.Add(Golden.Func("Increment", Golden.NoParams(), null, Golden.Block(stmts2, 2, 30), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `lock (obj)` materializes NO ParenthesizedExpression — the parens are consumed by the statement and only the column moves (was ParserTests.TestLockStatementWithParens)" {
    source := "\n            func Increment() {\n                lock (_lockObject) {\n                    _counter++\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.ExprStmt(Golden.Un(UnaryOperator.PostIncrement, Golden.Ident("_counter", 4, 21), 4, 29), 4, 21))
    stmts2.Add(Golden.Lock(Golden.Ident("_lockObject", 3, 23), Golden.Block(stmts3, 3, 36), 3, 17))
    decls1.Add(Golden.Func("Increment", Golden.NoParams(), null, Golden.Block(stmts2, 2, 30), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: a `default =>` arm is a SwitchCase with a NULL Pattern, `case 1 =>` carries a LiteralPattern, and every case anchors on its own keyword (was ParserTests.TestSwitchStatement)" {
    source := "\n            func Test(value: int) {\n                switch value {\n                    case 1 => Console.WriteLine(\"One\")\n                    case 2 => Console.WriteLine(\"Two\")\n                    default => Console.WriteLine(\"Other\")\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("value", Golden.SimpleT("int", 2, 30, 33), null, false, ParameterModifier.None, 2, 23))
    stmts3 := new List<Statement>()
    cases4 := new List<SwitchCase>()
    stmts5 := new List<Statement>()
    args6 := new List<Argument>()
    args6.Add(Golden.ArgF(null, Golden.StrLit("\"One\"", 4, 49), ArgumentModifier.None))
    stmts5.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 4, 31), "WriteLine", false, 4, 38), args6, Golden.NoTypeArgs(), 4, 48), 4, 31))
    cases4.Add(Golden.CaseF(Golden.PLit(Golden.IntLit("1", 4, 26), 4, 26), stmts5, 4, 21))
    stmts7 := new List<Statement>()
    args8 := new List<Argument>()
    args8.Add(Golden.ArgF(null, Golden.StrLit("\"Two\"", 5, 49), ArgumentModifier.None))
    stmts7.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 5, 31), "WriteLine", false, 5, 38), args8, Golden.NoTypeArgs(), 5, 48), 5, 31))
    cases4.Add(Golden.CaseF(Golden.PLit(Golden.IntLit("2", 5, 26), 5, 26), stmts7, 5, 21))
    stmts9 := new List<Statement>()
    args10 := new List<Argument>()
    args10.Add(Golden.ArgF(null, Golden.StrLit("\"Other\"", 6, 50), ArgumentModifier.None))
    stmts9.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 6, 32), "WriteLine", false, 6, 39), args10, Golden.NoTypeArgs(), 6, 49), 6, 32))
    cases4.Add(Golden.CaseF(null, stmts9, 6, 21))
    stmts3.Add(Golden.Switch(Golden.Ident("value", 3, 24), cases4, 3, 17))
    decls1.Add(Golden.Func("Test", params2, null, Golden.Block(stmts3, 2, 35), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `print` takes a whole expression: a plain literal keeps its quotes in Value, and `$\"…\"` splits into a text part and a hole with a null format clause (was ParserTests.TestPrintStatement)" {
    source := "\nfunc main() {\n    print \"Hello\"\n    print $\"Value: {x}\"\n}\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.Print(Golden.StrLit("\"Hello\"", 3, 11), 3, 5))
    parts3 := new List<InterpolatedStringPart>()
    parts3.Add(Golden.TextPart("Value: ", 4, 13))
    parts3.Add(Golden.HolePart(Golden.Ident("x", 4, 21), null, 4, 20))
    stmts2.Add(Golden.Print(Golden.Interp(parts3, false, 4, 11), 4, 5))
    decls1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(stmts2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: a `test \"…\" { … }` stores its description UNQUOTED, with null TableParameters, null TableCases and null SkipReason (was ParserTests.TestTestDeclaration)" {
    source := "\ntest \"should add two numbers\" {\n    result := Add(2, 3)\n    assert result == 5\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    args3 := new List<Argument>()
    args3.Add(Golden.ArgF(null, Golden.IntLit("2", 3, 19), ArgumentModifier.None))
    args3.Add(Golden.ArgF(null, Golden.IntLit("3", 3, 22), ArgumentModifier.None))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Call(Golden.Ident("Add", 3, 15), args3, Golden.NoTypeArgs(), 3, 18), VariableKind.Let, 3, 5))
    stmts2.Add(Golden.Assert(Golden.Bin(Golden.Ident("result", 4, 12), BinaryOperator.Equal, Golden.IntLit("5", 4, 22), 4, 19), null, 4, 5))
    decls1.Add(Golden.TestF("should add two numbers", Golden.Block(stmts2, 2, 31), null, null, null, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: a bare `assert cond` has a null Message, and `!= null` materializes a NullLiteralExpression operand (was ParserTests.TestAssertStatement)" {
    source := "\nfunc TestFunc() {\n    value := 10\n    assert value > 5\n    assert value != null\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("value", null, Golden.IntLit("10", 3, 14), VariableKind.Let, 3, 5))
    stmts2.Add(Golden.Assert(Golden.Bin(Golden.Ident("value", 4, 12), BinaryOperator.Greater, Golden.IntLit("5", 4, 20), 4, 18), null, 4, 5))
    stmts2.Add(Golden.Assert(Golden.Bin(Golden.Ident("value", 5, 12), BinaryOperator.NotEqual, Golden.NullLit(5, 21), 5, 18), null, 5, 5))
    decls1.Add(Golden.Func("TestFunc", Golden.NoParams(), null, Golden.Block(stmts2, 2, 17), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `assert cond, \"msg\"` puts the message in Message as a StringLiteralExpression that KEEPS its quotes — the opposite of the description (was ParserTests.TestAssertWithMessage)" {
    source := "\ntest \"should add\" {\n    result := Add(2, 3)\n    assert result == 5, \"addition should work\"\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    args3 := new List<Argument>()
    args3.Add(Golden.ArgF(null, Golden.IntLit("2", 3, 19), ArgumentModifier.None))
    args3.Add(Golden.ArgF(null, Golden.IntLit("3", 3, 22), ArgumentModifier.None))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Call(Golden.Ident("Add", 3, 15), args3, Golden.NoTypeArgs(), 3, 18), VariableKind.Let, 3, 5))
    stmts2.Add(Golden.Assert(Golden.Bin(Golden.Ident("result", 4, 12), BinaryOperator.Equal, Golden.IntLit("5", 4, 22), 4, 19), Golden.StrLit("\"addition should work\"", 4, 25), 4, 5))
    decls1.Add(Golden.TestF("should add", Golden.Block(stmts2, 2, 19), null, null, null, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `assert throws T { … }` materializes an AssertThrowsStatement anchored on `assert`, with a SimpleTypeReference and a block body (was ParserTests.TestAssertThrows)" {
    source := "\ntest \"should throw on divide by zero\" {\n    assert throws DivideByZeroException {\n        Calculator.Divide(10, 0)\n    }\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts3 := new List<Statement>()
    args4 := new List<Argument>()
    args4.Add(Golden.ArgF(null, Golden.IntLit("10", 4, 27), ArgumentModifier.None))
    args4.Add(Golden.ArgF(null, Golden.IntLit("0", 4, 31), ArgumentModifier.None))
    stmts3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Calculator", 4, 9), "Divide", false, 4, 19), args4, Golden.NoTypeArgs(), 4, 26), 4, 9))
    stmts2.Add(Golden.AssertThrows(Golden.SimpleT("DivideByZeroException", 3, 19, 40), Golden.Block(stmts3, 3, 41), 3, 5))
    decls1.Add(Golden.TestF("should throw on divide by zero", Golden.Block(stmts2, 2, 39), null, null, null, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: a table's cases are a LIST OF LISTS in row order, and `(-1, …)` is a Negate unary over a POSITIVE literal, not a negative literal (was ParserTests.TestTableDrivenTest)" {
    source := "\ntest \"should add correctly\" with (a: int, b: int, expected: int) [\n    (1, 2, 3),\n    (0, 0, 0),\n    (-1, 1, 0)\n] {\n    result := Add(a, b)\n    assert result == expected\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    args3 := new List<Argument>()
    args3.Add(Golden.ArgF(null, Golden.Ident("a", 7, 19), ArgumentModifier.None))
    args3.Add(Golden.ArgF(null, Golden.Ident("b", 7, 22), ArgumentModifier.None))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Call(Golden.Ident("Add", 7, 15), args3, Golden.NoTypeArgs(), 7, 18), VariableKind.Let, 7, 5))
    stmts2.Add(Golden.Assert(Golden.Bin(Golden.Ident("result", 8, 12), BinaryOperator.Equal, Golden.Ident("expected", 8, 22), 8, 19), null, 8, 5))
    tparams4 := new List<Parameter>()
    tparams4.Add(Golden.Param("a", Golden.SimpleT("int", 2, 38, 41), null, false, ParameterModifier.None, 2, 35))
    tparams4.Add(Golden.Param("b", Golden.SimpleT("int", 2, 46, 49), null, false, ParameterModifier.None, 2, 43))
    tparams4.Add(Golden.Param("expected", Golden.SimpleT("int", 2, 61, 64), null, false, ParameterModifier.None, 2, 51))
    rows5 := new List<List<Expression> >()
    exprs6 := new List<Expression>()
    exprs6.Add(Golden.IntLit("1", 3, 6))
    exprs6.Add(Golden.IntLit("2", 3, 9))
    exprs6.Add(Golden.IntLit("3", 3, 12))
    rows5.Add(exprs6)
    exprs7 := new List<Expression>()
    exprs7.Add(Golden.IntLit("0", 4, 6))
    exprs7.Add(Golden.IntLit("0", 4, 9))
    exprs7.Add(Golden.IntLit("0", 4, 12))
    rows5.Add(exprs7)
    exprs8 := new List<Expression>()
    exprs8.Add(Golden.Un(UnaryOperator.Negate, Golden.IntLit("1", 5, 7), 5, 6))
    exprs8.Add(Golden.IntLit("1", 5, 10))
    exprs8.Add(Golden.IntLit("0", 5, 13))
    rows5.Add(exprs8)
    decls1.Add(Golden.TestF("should add correctly", Golden.Block(stmts2, 6, 3), tparams4, rows5, null, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: `skip \"…\"` stores the reason UNQUOTED, and the body block anchors after the skip clause (was ParserTests.TestSkipTest)" {
    source := "\ntest \"needs network\" skip \"CI has no network\" {\n    assert true\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.Assert(Golden.BoolLit(true, 3, 12), null, 3, 5))
    decls1.Add(Golden.TestF("needs network", Golden.Block(stmts2, 2, 47), null, null, "CI has no network", 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: a `setup` block is a top-level DECLARATION that shares the Declarations list with the tests, in source order (was ParserTests.TestSetupBlock)" {
    source := "\nsetup {\n    store := new TaskStore()\n}\n\ntest \"should add task\" {\n    assert store != null\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("store", null, Golden.NewE(Golden.SimpleT("TaskStore", 3, 18, 27), Golden.NoArgs(), null, null, 3, 14), VariableKind.Let, 3, 5))
    decls1.Add(Golden.SetupF(Golden.Block(stmts2, 2, 7), 2, 1))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Assert(Golden.Bin(Golden.Ident("store", 7, 12), BinaryOperator.NotEqual, Golden.NullLit(7, 21), 7, 18), null, 7, 5))
    decls1.Add(Golden.TestF("should add task", Golden.Block(stmts3, 6, 24), null, null, null, 6, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: a `teardown` block is a top-level declaration too, and the unit anchors on the FIRST declaration (was ParserTests.TestTeardownBlock)" {
    source := "\nteardown {\n    store.Dispose()\n}\n\ntest \"should work\" {\n    assert true\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("store", 3, 5), "Dispose", false, 3, 10), Golden.NoArgs(), Golden.NoTypeArgs(), 3, 18), 3, 5))
    decls1.Add(Golden.TeardownF(Golden.Block(stmts2, 2, 10), 2, 1))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Assert(Golden.BoolLit(true, 7, 12), null, 7, 5))
    decls1.Add(Golden.TestF("should work", Golden.Block(stmts3, 6, 20), null, null, null, 6, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: setup, teardown and test land in Declarations in SOURCE order, each anchored on its own keyword (was ParserTests.TestSetupAndTeardownTogether)" {
    source := "\nsetup {\n    db := new Database()\n}\n\nteardown {\n    db.Dispose()\n}\n\ntest \"should query\" {\n    assert db != null\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("db", null, Golden.NewE(Golden.SimpleT("Database", 3, 15, 23), Golden.NoArgs(), null, null, 3, 11), VariableKind.Let, 3, 5))
    decls1.Add(Golden.SetupF(Golden.Block(stmts2, 2, 7), 2, 1))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("db", 7, 5), "Dispose", false, 7, 7), Golden.NoArgs(), Golden.NoTypeArgs(), 7, 15), 7, 5))
    decls1.Add(Golden.TeardownF(Golden.Block(stmts3, 6, 10), 6, 1))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.Assert(Golden.Bin(Golden.Ident("db", 11, 12), BinaryOperator.NotEqual, Golden.NullLit(11, 18), 11, 15), null, 11, 5))
    decls1.Add(Golden.TestF("should query", Golden.Block(stmts4, 10, 21), null, null, null, 10, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s18 parser statements: a table-driven test carries BOTH its rows and a skip reason, and the body block anchors after the `skip` clause (was ParserTests.TestTableDrivenWithSkip)" {
    source := "\ntest \"should add\" with (a: int, b: int, expected: int) [\n    (1, 2, 3)\n] skip \"disabled\" {\n    assert Add(a, b) == expected\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    args3 := new List<Argument>()
    args3.Add(Golden.ArgF(null, Golden.Ident("a", 5, 16), ArgumentModifier.None))
    args3.Add(Golden.ArgF(null, Golden.Ident("b", 5, 19), ArgumentModifier.None))
    stmts2.Add(Golden.Assert(Golden.Bin(Golden.Call(Golden.Ident("Add", 5, 12), args3, Golden.NoTypeArgs(), 5, 15), BinaryOperator.Equal, Golden.Ident("expected", 5, 25), 5, 22), null, 5, 5))
    tparams4 := new List<Parameter>()
    tparams4.Add(Golden.Param("a", Golden.SimpleT("int", 2, 28, 31), null, false, ParameterModifier.None, 2, 25))
    tparams4.Add(Golden.Param("b", Golden.SimpleT("int", 2, 36, 39), null, false, ParameterModifier.None, 2, 33))
    tparams4.Add(Golden.Param("expected", Golden.SimpleT("int", 2, 51, 54), null, false, ParameterModifier.None, 2, 41))
    rows5 := new List<List<Expression> >()
    exprs6 := new List<Expression>()
    exprs6.Add(Golden.IntLit("1", 3, 6))
    exprs6.Add(Golden.IntLit("2", 3, 9))
    exprs6.Add(Golden.IntLit("3", 3, 12))
    rows5.Add(exprs6)
    decls1.Add(Golden.TestF("should add", Golden.Block(stmts2, 4, 19), tparams4, rows5, "disabled", 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

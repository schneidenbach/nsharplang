namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL KEYWORD-PRIMARY, LAMBDA, TYPE-REFERENCE AND OPERATOR CONTRACTS FOR
// `ColumnarParserRecovery.ParseFileAst`, IN N#.
//
// THIS FILE FINISHES `tests/ParserTests.cs`. It replaces the SIXTH and last tranche — the whole
// remainder, all 30 surviving `[Fact]`s, 824 method lines and 197 in-method `Assert.` occurrences —
// and task 020 slice 22 DELETES the C# file, both its private helpers (`Parse`, used by all 30, and
// `AssertHasParseError`, used by the one negative below) and the class around them. Over six tranches
// the arc moved 210 xUnit cases and 6,130 C# lines into the native estate; nothing of it is left.
//
// THE CUT IS BY ASSERTED NODE TYPE, and this tranche is the residue of the five before it: keyword and
// primary expressions (15 / 477 / 119), lambdas (7 / 147 / 18), type references (4 / 100 / 42, carrying
// the residue's ONE negative) and operators (4 / 100 / 18). Slice 21 priced all four sizes AND all four
// assertion counts from a measurement of the surviving file, and re-measuring at `76873437b` reproduces
// every one of the eight numbers exactly — the first tranche of the six whose inherited estimate needed
// no correction in either column.
//
// THE ROUTE IS THE WHOLE-TREE GOLDEN, AND IT IS STRICTLY STRONGER THAN WHAT IT REPLACES. Twenty-nine of
// the thirty went through one private helper:
//
//     private static CompilationUnit Parse(string source)
//         => ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit!;
//
// followed by a chain of `as`-casts, `Assert.IsType<T>` calls and a handful of member reads. A
// whole-tree diff pins every node, every registered field and every ANCHOR at once.
//
// THE SECOND CLAIM IN EVERY POSITIVE CONTRACT IS THAT THE SOURCE PARSES CLEANLY, AND `Parse()` ABOVE
// COULD NOT MAKE IT: it reads `.CompilationUnit` and DISCARDS `.Errors`. Each positive pins
// `PsCensus(source) == ""` FIRST. MEASURED RESULT: all 29 positives parse with an EMPTY diagnostic
// list — the same verdict slices 17-21 measured over their 50, 23, 44, 31 and 30, so across the whole
// campaign the pin has found no defect over **207** real-world fixtures. It stays because it is the
// guard that makes the silence impossible to re-introduce. One of the thirty carried a WEAKER form of
// the claim itself: `TestNullableArrayPostfixOrder` asserted `result.Success`, which a
// WARNING-severity diagnostic satisfies and the census does not.
//
// THE HELPERS ARE REUSED, NOT RE-COPIED. `PsAst` / `PsCensus` live in `ColumnarParserStatements.tests.nl`;
// `PeParse` / `PeCensus` / `PeRow` / `PeDecls` live in `ColumnarParserErrorRecovery.tests.nl`;
// `AstEq.Diff` and the `Golden.*` builders live in `ColumnarParserAst.tests.nl`. **This tranche adds
// ZERO new `AstEq.FieldNames` entries and ZERO new `Golden` builders** — the second of the six to need
// neither, and the slice-21 prediction that a returning LAMBDA-PARAMETER builder would be needed is
// recorded here as WRONG: `Golden.Param(name, Golden.BareT("var"), null, false, ParameterModifier.None,
// line, column)` constructs the identical `Parameter` the appender `AddLambdaParam` does, at the same
// arity, and the nested lambda lists below are built with it.
//
// THE SOURCES ARE THE DELETED FIXTURES BYTE-FOR-BYTE — leading newline, twelve-space indentation and
// trailing eight spaces included where the C# spelled them that way. This tranche uses THREE C# literal
// forms, and it is the first of the six to use all three: 25 verbatim `@"…"`, 4 raw `"""…"""` and 1
// REGULAR `"…"`. That is why the byte-identity check is run with the C# COMPILER as the decoder rather
// than a hand-rolled reader: C# strips the CLOSING DELIMITER'S indentation from every line of a raw
// literal and honours no escapes inside it, while a regular literal honours every escape. All 30 were
// decoded by the compiler and all 30 are byte-identical to the literals below.
//
// WHAT THESE PINS MEASURED THAT THE DELETED ASSERTIONS COULD NOT SEE is recorded per section below,
// AND THE SIBLING SWEEP WAS RUN BEFORE ANYTHING WAS CALLED A FINDING — it moved every anchor rule in
// section (a) and all four lambda-anchor rules in section (b) into the RESTATEMENT column, and it
// confirmed each of the fourteen shapes labelled new at exactly ZERO prior occurrences.


// ---- (a) KEYWORD AND PRIMARY EXPRESSIONS — 15 contracts ----
//
// WHAT THESE FIFTEEN PIN, SPLIT INTO RESTATEMENTS AND WHAT IS NEW — THE SIBLING SWEEP WAS RUN FIRST.
// `ColumnarParserAst.tests.nl`'s stage-N+1c corpus already pins EVERY anchor rule this family uses,
// over one-line synthetic enum-member sources: `a as string` anchored on the `as` with CastKind.Safe
// (:3390, which says so in its own title), `(int)x` anchored on the paren with CastKind.Hard (:3480),
// `must x` on the keyword (:3410), `nameof(x)` (:3440), `...x` on the `...` (:3490), `await x`
// (:3400), `typeof(int)` (:3430), `checked(x)` / `unchecked(x)` (:3460, :3470), `r with { … }` on the
// `with` (:3841), and an ObjectInitializerExpression carrying its NewExpression anchor. **All of those
// are RESTATEMENTS here and are not claimed as findings.**
//
// WHAT IS NEW TO THE LEDGER IS THE OPERAND. Every synthetic site above wraps a BARE IDENTIFIER or a
// bare `int`; measured across the whole estate, the count of contracts pinning `checked` over a
// BinaryExpression, `unchecked` over a BinaryExpression, `await` over a CallExpression, `nameof` over a
// MemberAccessExpression, `typeof` over a GenericTypeReference, a MemberAccessExpression over a
// ThisExpression, the same over a BaseExpression, and a SpreadExpression inside an ArrayLiteral element
// list is **ZERO in every one of the eight**. This family gives all eight a real operand. A ninth is
// new for a different reason: a SimpleTypeReference whose Name is DOTTED (`Result.Success`) occurs
// twice in the estate, and neither is a CAST TARGET — so `(Result.Success)r` pins for the first time
// that the qualified name stays ONE node with ONE span rather than becoming a nested member access.
//
// AND ONE MEASURED FACT ABOUT MODIFIERS IS RECORDED AS A DIVERGENCE RATHER THAN A RULE. A TOP-LEVEL
// `async func FetchData` anchors its FunctionDeclaration on the `func` keyword (column 19) while the
// enclosing CompilationUnit anchors on the `async` (column 13). The estate's one sibling —
// `ColumnarParserAst.tests.nl` :5828, an `async` LOCAL function — anchors the declaration on the
// `async` itself. Both are pinned as measured; neither is claimed to be the right one.

test "020 s22 parser primary: `[1, 2, 3]` builds an ArrayLiteralExpression anchored on its `[` with IsImmutable FALSE and three IntLiteralExpression elements, each anchored on its own digit and each holding its literal TEXT rather than a parsed number (was ParserTests.TestArrayLiteral)" {
    source := "\n            func Test() {\n                arr := [1, 2, 3]\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    expression3 := new List<Expression>()
    expression3.Add(Golden.IntLit("1", 3, 25))
    expression3.Add(Golden.IntLit("2", 3, 28))
    expression3.Add(Golden.IntLit("3", 3, 31))
    statement2.Add(Golden.VarDecl("arr", null, Golden.ArrayLit(expression3, false, 3, 24), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: a cast to a DOTTED type — `(Result.Success)r` — is a CastExpression of Kind Hard anchored on the OPEN PAREN whose TargetType is ONE SimpleTypeReference named Result.Success spanning the whole dotted name, not two nested nodes (was ParserTests.TestQualifiedTypeCast)" {
    source := "\n            func Test() {\n                s := (Result.Success)r\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("s", null, Golden.Cast(Golden.Ident("r", 3, 38), Golden.SimpleT("Result.Success", 3, 23, 37), CastKind.Hard, 3, 22), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `p1 with { Age: 31 }` is a WithExpression anchored on the `with` KEYWORD — not on the target and not on the brace — carrying one PropertyInitializer anchored on its own NAME (was ParserTests.TestWithExpression)" {
    source := "\n            func Test() {\n                p2 := p1 with { Age: 31 }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    propertyinitializer3 := new List<PropertyInitializer>()
    propertyinitializer3.Add(Golden.PropInit("Age", null, Golden.IntLit("31", 3, 38), 3, 33))
    statement2.Add(Golden.VarDecl("p2", null, Golden.With(Golden.Ident("p1", 3, 23), propertyinitializer3, 3, 26), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `await GetDataAsync()` is an AwaitExpression anchored on the `await` over a CallExpression anchored on its open paren — and the TOP-LEVEL `async func` anchors on the `func` keyword at column 19 while the CompilationUnit anchors on the `async` at column 13, so the modifier sits OUTSIDE the declaration anchor (was ParserTests.TestAsyncAwait)" {
    source := "\n            async func FetchData(): Task<string> {\n                result := await GetDataAsync()\n                return result\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    typereference2 := new List<TypeReference>()
    typereference2.Add(Golden.SimpleT("string", 2, 42, 48))
    statement3 := new List<Statement>()
    statement3.Add(Golden.VarDecl("result", null, Golden.Await(Golden.Call(Golden.Ident("GetDataAsync", 3, 33), Golden.NoArgs(), Golden.NoTypeArgs(), 3, 45), 3, 27), VariableKind.Let, 3, 17))
    statement3.Add(Golden.Return(Golden.Ident("result", 4, 24), 4, 17))
    declaration1.Add(Golden.Func("FetchData", Golden.NoParams(), Golden.GenericT("Task", typereference2, 2, 37, 49), Golden.Block(statement3, 2, 50), null, null, null, Modifiers.Async, 2, 19))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: inside `[...arr1, 4, 5]` the spread is an ELEMENT — a SpreadExpression anchored on the FIRST dot of the three — and the literal reports THREE elements, so a spread counts as one element and does not flatten at parse time (was ParserTests.TestSpreadOperator)" {
    source := "\n            func Test() {\n                arr1 := [1, 2, 3]\n                arr2 := [...arr1, 4, 5]\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    expression3 := new List<Expression>()
    expression3.Add(Golden.IntLit("1", 3, 26))
    expression3.Add(Golden.IntLit("2", 3, 29))
    expression3.Add(Golden.IntLit("3", 3, 32))
    statement2.Add(Golden.VarDecl("arr1", null, Golden.ArrayLit(expression3, false, 3, 25), VariableKind.Let, 3, 17))
    expression4 := new List<Expression>()
    expression4.Add(Golden.Spread(Golden.Ident("arr1", 4, 29), 4, 26))
    expression4.Add(Golden.IntLit("4", 4, 35))
    expression4.Add(Golden.IntLit("5", 4, 38))
    statement2.Add(Golden.VarDecl("arr2", null, Golden.ArrayLit(expression4, false, 4, 25), VariableKind.Let, 4, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: in `Sum(...items)` the spread is the argument VALUE and the Argument itself keeps ArgumentModifier.None, while the callee `func Sum(params numbers: int[])` carries ParameterModifier.Params with an ArrayTypeReference whose span COVERS its own brackets (was ParserTests.TestSpreadOperatorInFunctionCall)" {
    source := "\n            func Sum(params numbers: int[]): int {\n                return 0\n            }\n\n            func Test() {\n                items := [1, 2, 3]\n                result := Sum(...items)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    parameter2 := new List<Parameter>()
    parameter2.Add(Golden.Param("numbers", Golden.ArrayT(Golden.SimpleT("int", 2, 38, 41), 2, 38, 43), null, false, ParameterModifier.Params, 2, 29))
    statement3 := new List<Statement>()
    statement3.Add(Golden.Return(Golden.IntLit("0", 3, 24), 3, 17))
    declaration1.Add(Golden.Func("Sum", parameter2, Golden.SimpleT("int", 2, 46, 49), Golden.Block(statement3, 2, 50), null, null, null, Modifiers.None, 2, 13))
    statement4 := new List<Statement>()
    expression5 := new List<Expression>()
    expression5.Add(Golden.IntLit("1", 7, 27))
    expression5.Add(Golden.IntLit("2", 7, 30))
    expression5.Add(Golden.IntLit("3", 7, 33))
    statement4.Add(Golden.VarDecl("items", null, Golden.ArrayLit(expression5, false, 7, 26), VariableKind.Let, 7, 17))
    argument6 := new List<Argument>()
    argument6.Add(Golden.ArgF(null, Golden.Spread(Golden.Ident("items", 8, 34), 8, 31), ArgumentModifier.None))
    statement4.Add(Golden.VarDecl("result", null, Golden.Call(Golden.Ident("Sum", 8, 27), argument6, Golden.NoTypeArgs(), 8, 30), VariableKind.Let, 8, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement4, 6, 25), null, null, null, Modifiers.None, 6, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `obj as string` is the SAME CastExpression node the parenthesized form builds, separated only by Kind Safe, and it anchors on the `as` KEYWORD rather than on either operand — three of them in one body, where the deleted test read only the first (was ParserTests.TestSafeCastOperator)" {
    source := "\n            func Test() {\n                let obj = GetObject()\n                str := obj as string\n                person := obj as Person\n                num := value as int\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("obj", null, Golden.Call(Golden.Ident("GetObject", 3, 27), Golden.NoArgs(), Golden.NoTypeArgs(), 3, 36), VariableKind.Let, 3, 21))
    statement2.Add(Golden.VarDecl("str", null, Golden.Cast(Golden.Ident("obj", 4, 24), Golden.SimpleT("string", 4, 31, 37), CastKind.Safe, 4, 28), VariableKind.Let, 4, 17))
    statement2.Add(Golden.VarDecl("person", null, Golden.Cast(Golden.Ident("obj", 5, 27), Golden.SimpleT("Person", 5, 34, 40), CastKind.Safe, 5, 31), VariableKind.Let, 5, 17))
    statement2.Add(Golden.VarDecl("num", null, Golden.Cast(Golden.Ident("value", 6, 24), Golden.SimpleT("int", 6, 33, 36), CastKind.Safe, 6, 30), VariableKind.Let, 6, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `obj is string s` fills IsExpression.VariableName while `value is int` leaves it NULL, both anchored on the `is`, and a third form proves the same node parses in a `:=` initializer as well as in an if condition (was ParserTests.TestIsPattern)" {
    source := "\n            func Test() {\n                if obj is string s {\n                    Console.WriteLine(s)\n                }\n\n                if value is int {\n                    Console.WriteLine(\"is int\")\n                }\n\n                result := obj is Person\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement3 := new List<Statement>()
    argument4 := new List<Argument>()
    argument4.Add(Golden.ArgF(null, Golden.Ident("s", 4, 39), ArgumentModifier.None))
    statement3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 4, 21), "WriteLine", false, 4, 28), argument4, Golden.NoTypeArgs(), 4, 38), 4, 21))
    statement2.Add(Golden.If(Golden.Is(Golden.Ident("obj", 3, 20), Golden.SimpleT("string", 3, 27, 33), "s", 3, 24), Golden.Block(statement3, 3, 36), null, 3, 17))
    statement5 := new List<Statement>()
    argument6 := new List<Argument>()
    argument6.Add(Golden.ArgF(null, Golden.StrLit("\"is int\"", 8, 39), ArgumentModifier.None))
    statement5.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 8, 21), "WriteLine", false, 8, 28), argument6, Golden.NoTypeArgs(), 8, 38), 8, 21))
    statement2.Add(Golden.If(Golden.Is(Golden.Ident("value", 7, 20), Golden.SimpleT("int", 7, 29, 32), null, 7, 26), Golden.Block(statement5, 7, 33), null, 7, 17))
    statement2.Add(Golden.VarDecl("result", null, Golden.Is(Golden.Ident("obj", 11, 27), Golden.SimpleT("Person", 11, 34, 40), null, 11, 31), VariableKind.Let, 11, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `this.name = name` puts a ThisExpression under MemberAccessExpression.Object while `return this` puts the identical node straight into ReturnStatement.Value — the member access anchors on its DOT and the assignment on its `=` (was ParserTests.TestThisKeyword)" {
    source := "\n            class MyClass {\n                name: string\n\n                func SetName(name: string) {\n                    this.name = name\n                }\n\n                func GetThis(): MyClass {\n                    return this\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    declaration2 := new List<Declaration>()
    declaration2.Add(Golden.FieldF("name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    parameter3 := new List<Parameter>()
    parameter3.Add(Golden.Param("name", Golden.SimpleT("string", 5, 36, 42), null, false, ParameterModifier.None, 5, 30))
    statement4 := new List<Statement>()
    statement4.Add(Golden.ExprStmt(Golden.Assign(Golden.Member(Golden.ThisE(6, 21), "name", false, 6, 25), AssignmentOperator.Assign, Golden.Ident("name", 6, 33), 6, 31), 6, 21))
    declaration2.Add(Golden.Func("SetName", parameter3, null, Golden.Block(statement4, 5, 44), null, null, null, Modifiers.None, 5, 17))
    statement5 := new List<Statement>()
    statement5.Add(Golden.Return(Golden.ThisE(10, 28), 10, 21))
    declaration2.Add(Golden.Func("GetThis", Golden.NoParams(), Golden.SimpleT("MyClass", 9, 33, 40), Golden.Block(statement5, 9, 41), null, null, null, Modifiers.None, 9, 17))
    declaration1.Add(Golden.ClassF("MyClass", null, null, Golden.NoTypeRefs(), declaration2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `base.MakeSound()` nests BaseExpression under a MemberAccessExpression under a CallExpression, and the two-class fixture around it pins a `virtual func` member and a derived class whose BaseClass is a SimpleTypeReference, both bodies intact (was ParserTests.TestBaseKeyword)" {
    source := "\n            class Animal {\n                virtual func MakeSound() {\n                    Console.WriteLine(\"Sound\")\n                }\n            }\n\n            class Dog : Animal {\n                func MakeSound() {\n                    base.MakeSound()\n                    Console.WriteLine(\"Bark\")\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    declaration2 := new List<Declaration>()
    statement3 := new List<Statement>()
    argument4 := new List<Argument>()
    argument4.Add(Golden.ArgF(null, Golden.StrLit("\"Sound\"", 4, 39), ArgumentModifier.None))
    statement3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 4, 21), "WriteLine", false, 4, 28), argument4, Golden.NoTypeArgs(), 4, 38), 4, 21))
    declaration2.Add(Golden.Func("MakeSound", Golden.NoParams(), null, Golden.Block(statement3, 3, 42), null, null, null, Modifiers.Virtual, 3, 25))
    declaration1.Add(Golden.ClassF("Animal", null, null, Golden.NoTypeRefs(), declaration2, null, Modifiers.None, 2, 13))
    declaration5 := new List<Declaration>()
    statement6 := new List<Statement>()
    statement6.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.BaseE(10, 21), "MakeSound", false, 10, 25), Golden.NoArgs(), Golden.NoTypeArgs(), 10, 35), 10, 21))
    argument7 := new List<Argument>()
    argument7.Add(Golden.ArgF(null, Golden.StrLit("\"Bark\"", 11, 39), ArgumentModifier.None))
    statement6.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 11, 21), "WriteLine", false, 11, 28), argument7, Golden.NoTypeArgs(), 11, 38), 11, 21))
    declaration5.Add(Golden.Func("MakeSound", Golden.NoParams(), null, Golden.Block(statement6, 9, 34), null, null, null, Modifiers.None, 9, 17))
    declaration1.Add(Golden.ClassF("Dog", null, Golden.SimpleT("Animal", 8, 25, 31), Golden.NoTypeRefs(), declaration5, null, Modifiers.None, 8, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `nameof(myVariable)` and `nameof(person.Name)` are the same NameofExpression anchored on the keyword and differ ONLY in whether Target is an IdentifierExpression or a MemberAccessExpression — the deleted test read the target type and nothing under it (was ParserTests.TestNameofExpression)" {
    source := "\nfunc main() {\n    name := nameof(myVariable)\n    prop := nameof(person.Name)\n}\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("name", null, Golden.Nameof(Golden.Ident("myVariable", 3, 20), 3, 13), VariableKind.Let, 3, 5))
    statement2.Add(Golden.VarDecl("prop", null, Golden.Nameof(Golden.Member(Golden.Ident("person", 4, 20), "Name", false, 4, 26), 4, 13), VariableKind.Let, 4, 5))
    declaration1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statement2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `typeof(int)`, `typeof(Person)` and `typeof(List<string>)` all build TypeOfExpression anchored on the keyword, and the third carries a GenericTypeReference whose Span INCLUDES its own closing angle bracket (was ParserTests.TestTypeofExpression)" {
    source := "\nfunc main() {\n    t1 := typeof(int)\n    t2 := typeof(Person)\n    t3 := typeof(List<string>)\n}\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("t1", null, Golden.TypeOf(Golden.SimpleT("int", 3, 18, 21), 3, 11), VariableKind.Let, 3, 5))
    statement2.Add(Golden.VarDecl("t2", null, Golden.TypeOf(Golden.SimpleT("Person", 4, 18, 24), 4, 11), VariableKind.Let, 4, 5))
    typereference3 := new List<TypeReference>()
    typereference3.Add(Golden.SimpleT("string", 5, 23, 29))
    statement2.Add(Golden.VarDecl("t3", null, Golden.TypeOf(Golden.GenericT("List", typereference3, 5, 18, 30), 5, 11), VariableKind.Let, 5, 5))
    declaration1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statement2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `checked(a + b)` and `checked(int.MaxValue + 1)` wrap a BinaryExpression DIRECTLY — the CheckedExpression anchors on the keyword and adds no ParenthesizedExpression of its own, so the parens the syntax requires leave no node behind (was ParserTests.TestCheckedExpression)" {
    source := "\nfunc main() {\n    result := checked(a + b)\n    overflow := checked(int.MaxValue + 1)\n}\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("result", null, Golden.Checked(Golden.Bin(Golden.Ident("a", 3, 23), BinaryOperator.Add, Golden.Ident("b", 3, 27), 3, 25), 3, 15), VariableKind.Let, 3, 5))
    statement2.Add(Golden.VarDecl("overflow", null, Golden.Checked(Golden.Bin(Golden.Member(Golden.Ident("int", 4, 25), "MaxValue", false, 4, 28), BinaryOperator.Add, Golden.IntLit("1", 4, 40), 4, 38), 4, 17), VariableKind.Let, 4, 5))
    declaration1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statement2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `unchecked(a - b)` and `unchecked(int.MinValue - 1)` are the UncheckedExpression mirror of the checked pair — same shape, same vanished parens, BinaryOperator.Subtract inside (was ParserTests.TestUncheckedExpression)" {
    source := "\nfunc main() {\n    result := unchecked(a - b)\n    wrap := unchecked(int.MinValue - 1)\n}\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("result", null, Golden.Unchecked(Golden.Bin(Golden.Ident("a", 3, 25), BinaryOperator.Subtract, Golden.Ident("b", 3, 29), 3, 27), 3, 15), VariableKind.Let, 3, 5))
    statement2.Add(Golden.VarDecl("wrap", null, Golden.Unchecked(Golden.Bin(Golden.Member(Golden.Ident("int", 4, 23), "MinValue", false, 4, 26), BinaryOperator.Subtract, Golden.IntLit("1", 4, 38), 4, 36), 4, 13), VariableKind.Let, 4, 5))
    declaration1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statement2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser primary: `must input` is a MustExpression anchored on the keyword — its OWN node type, not a UnaryExpression, despite the deleted test name — over a parameter whose declared type is a NullableTypeReference spanning int? (was ParserTests.MustExpression_ParsesAsUnaryExpression)" {
    source := "func Test(input: int?) {\n    value := must input\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    parameter2 := new List<Parameter>()
    parameter2.Add(Golden.Param("input", Golden.NullableT(Golden.SimpleT("int", 1, 18, 21), 1, 18, 22), null, false, ParameterModifier.None, 1, 11))
    statement3 := new List<Statement>()
    statement3.Add(Golden.VarDecl("value", null, Golden.Must(Golden.Ident("input", 2, 19), 2, 14), VariableKind.Let, 2, 5))
    declaration1.Add(Golden.Func("Test", parameter2, null, Golden.Block(statement3, 1, 24), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}


// ---- (b) LAMBDAS — 7 contracts ----
//
// THE ANCHOR RULE IS A RESTATEMENT AND THE NESTING IS NOT. `ColumnarParserAst.tests.nl` already pins
// that `x => 1` anchors on the PARAMETER NAME (:4245), `(x, y) => 1` on the OPEN PAREN (:4258) and
// `() => 1` on the paren with an empty list (:4272), and that a block-bodied lambda fills BlockBody
// (:3283). All four are restated here over real receivers.
//
// TWO SHAPES ARE MEASURED AT **ZERO** OCCURRENCES ANYWHERE IN THE ESTATE BEFORE THIS FILE. (1) A
// LAMBDA IN A CALL-ARGUMENT POSITION, expression- or block-bodied: every synthetic lambda above sits in
// an enum-member or field initializer, and `Golden.ArgF(… Golden.Lambda(` and its BlockLambda sibling
// occur zero times. FIVE of these seven carry it. (2) A LAMBDA NESTED INSIDE A LAMBDA: `x => y => x + y`
// puts a LambdaExpression in another one's ExpressionBody, and that nesting occurs zero times.
//
// A THIRD THING IS NEW ABOUT THE FIXTURES RATHER THAN THE PARSER: `Lambda_MultipleParams_RequiresParens`
// carries an ANONYMOUS OBJECT — `new { Item: item, Index: index }` — which materializes as a
// NewExpression with a NULL Type and an ObjectInitializerExpression sharing the `new` anchor. The
// deleted test asserted only that the declaration had a non-null Initializer.

test "020 s22 parser lambda: `x => x * 2` anchors on its PARAMETER NAME while `(x, y) => x + y` anchors on its OPEN PAREN, and every implicit parameter of both gets the same synthetic var-named type reference at line 0 column 0 (was ParserTests.TestLambdaExpression)" {
    source := "\n            func Test() {\n                f := x => x * 2\n                g := (x, y) => x + y\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    parameter3 := new List<Parameter>()
    parameter3.Add(Golden.Param("x", Golden.BareT("var"), null, false, ParameterModifier.None, 3, 22))
    statement2.Add(Golden.VarDecl("f", null, Golden.Lambda(parameter3, Golden.Bin(Golden.Ident("x", 3, 27), BinaryOperator.Multiply, Golden.IntLit("2", 3, 31), 3, 29), 3, 22), VariableKind.Let, 3, 17))
    parameter4 := new List<Parameter>()
    parameter4.Add(Golden.Param("x", Golden.BareT("var"), null, false, ParameterModifier.None, 4, 23))
    parameter4.Add(Golden.Param("y", Golden.BareT("var"), null, false, ParameterModifier.None, 4, 26))
    statement2.Add(Golden.VarDecl("g", null, Golden.Lambda(parameter4, Golden.Bin(Golden.Ident("x", 4, 32), BinaryOperator.Add, Golden.Ident("y", 4, 36), 4, 34), 4, 22), VariableKind.Let, 4, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser lambda: a parenless single-parameter lambda in a CALL-ARGUMENT position — `items.Where(x => x % 2 == 0)` — is the argument VALUE, and the fixture pins that `import System.Linq` lands in CompilationUnit.Imports while the unit itself anchors on the import rather than on the function (was ParserTests.Lambda_SingleParamWithoutParens_Parses)" {
    source := "\n            import System.Linq\n\n            func Test() {\n                items := [1, 2, 3, 4, 5]\n                evens := items.Where(x => x % 2 == 0)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    importdirective1 := new List<ImportDirective>()
    importdirective1.Add(Golden.ImportF("System.Linq", null, 2, 13))
    declaration2 := new List<Declaration>()
    statement3 := new List<Statement>()
    expression4 := new List<Expression>()
    expression4.Add(Golden.IntLit("1", 5, 27))
    expression4.Add(Golden.IntLit("2", 5, 30))
    expression4.Add(Golden.IntLit("3", 5, 33))
    expression4.Add(Golden.IntLit("4", 5, 36))
    expression4.Add(Golden.IntLit("5", 5, 39))
    statement3.Add(Golden.VarDecl("items", null, Golden.ArrayLit(expression4, false, 5, 26), VariableKind.Let, 5, 17))
    argument5 := new List<Argument>()
    parameter6 := new List<Parameter>()
    parameter6.Add(Golden.Param("x", Golden.BareT("var"), null, false, ParameterModifier.None, 6, 38))
    argument5.Add(Golden.ArgF(null, Golden.Lambda(parameter6, Golden.Bin(Golden.Bin(Golden.Ident("x", 6, 43), BinaryOperator.Modulo, Golden.IntLit("2", 6, 47), 6, 45), BinaryOperator.Equal, Golden.IntLit("0", 6, 52), 6, 49), 6, 38), ArgumentModifier.None))
    statement3.Add(Golden.VarDecl("evens", null, Golden.Call(Golden.Member(Golden.Ident("items", 6, 26), "Where", false, 6, 31), argument5, Golden.NoTypeArgs(), 6, 37), VariableKind.Let, 6, 17))
    declaration2.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement3, 4, 25), null, null, null, Modifiers.None, 4, 13))
    expected := Golden.Unit(null, importdirective1, NoFileImports(), null, declaration2, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser lambda: `(x) => …` and `x => …` build the identical single-parameter list and differ ONLY in where the two nodes sit — the lambda stays on column 38 either way, on the paren or on the name, while the PARAMETER shifts one column right when the parens are there (was ParserTests.Lambda_SingleParamWithParens_StillWorks)" {
    source := "\n            import System.Linq\n\n            func Test() {\n                items := [1, 2, 3, 4, 5]\n                evens := items.Where((x) => x % 2 == 0)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    importdirective1 := new List<ImportDirective>()
    importdirective1.Add(Golden.ImportF("System.Linq", null, 2, 13))
    declaration2 := new List<Declaration>()
    statement3 := new List<Statement>()
    expression4 := new List<Expression>()
    expression4.Add(Golden.IntLit("1", 5, 27))
    expression4.Add(Golden.IntLit("2", 5, 30))
    expression4.Add(Golden.IntLit("3", 5, 33))
    expression4.Add(Golden.IntLit("4", 5, 36))
    expression4.Add(Golden.IntLit("5", 5, 39))
    statement3.Add(Golden.VarDecl("items", null, Golden.ArrayLit(expression4, false, 5, 26), VariableKind.Let, 5, 17))
    argument5 := new List<Argument>()
    parameter6 := new List<Parameter>()
    parameter6.Add(Golden.Param("x", Golden.BareT("var"), null, false, ParameterModifier.None, 6, 39))
    argument5.Add(Golden.ArgF(null, Golden.Lambda(parameter6, Golden.Bin(Golden.Bin(Golden.Ident("x", 6, 45), BinaryOperator.Modulo, Golden.IntLit("2", 6, 49), 6, 47), BinaryOperator.Equal, Golden.IntLit("0", 6, 54), 6, 51), 6, 38), ArgumentModifier.None))
    statement3.Add(Golden.VarDecl("evens", null, Golden.Call(Golden.Member(Golden.Ident("items", 6, 26), "Where", false, 6, 31), argument5, Golden.NoTypeArgs(), 6, 37), VariableKind.Let, 6, 17))
    declaration2.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement3, 4, 25), null, null, null, Modifiers.None, 4, 13))
    expected := Golden.Unit(null, importdirective1, NoFileImports(), null, declaration2, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser lambda: `(item, index) => new { Item: item, Index: index }` gives a two-parameter lambda whose body is a TARGET-TYPED NewExpression — a NULL Type with an ObjectInitializerExpression sharing the `new` anchor — which is how an anonymous object parses (was ParserTests.Lambda_MultipleParams_RequiresParens)" {
    source := "\n            func Test() {\n                items := [1, 2, 3]\n                indexed := items.Select((item, index) => new { Item: item, Index: index })\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    expression3 := new List<Expression>()
    expression3.Add(Golden.IntLit("1", 3, 27))
    expression3.Add(Golden.IntLit("2", 3, 30))
    expression3.Add(Golden.IntLit("3", 3, 33))
    statement2.Add(Golden.VarDecl("items", null, Golden.ArrayLit(expression3, false, 3, 26), VariableKind.Let, 3, 17))
    argument4 := new List<Argument>()
    parameter5 := new List<Parameter>()
    parameter5.Add(Golden.Param("item", Golden.BareT("var"), null, false, ParameterModifier.None, 4, 42))
    parameter5.Add(Golden.Param("index", Golden.BareT("var"), null, false, ParameterModifier.None, 4, 48))
    propertyinitializer6 := new List<PropertyInitializer>()
    propertyinitializer6.Add(Golden.PropInit("Item", null, Golden.Ident("item", 4, 70), 4, 64))
    propertyinitializer6.Add(Golden.PropInit("Index", null, Golden.Ident("index", 4, 83), 4, 76))
    argument4.Add(Golden.ArgF(null, Golden.Lambda(parameter5, Golden.NewE(null, Golden.NoArgs(), Golden.ObjInit(propertyinitializer6, 4, 58), null, 4, 58), 4, 41), ArgumentModifier.None))
    statement2.Add(Golden.VarDecl("indexed", null, Golden.Call(Golden.Member(Golden.Ident("items", 4, 28), "Select", false, 4, 33), argument4, Golden.NoTypeArgs(), 4, 40), VariableKind.Let, 4, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser lambda: `() => { print Hello }` is a BLOCK-bodied lambda with an EMPTY parameter list, anchored on its open paren, whose ExpressionBody is null and whose BlockBody anchors on the brace two columns later (was ParserTests.Lambda_NoParams_RequiresParens)" {
    source := "\n            func Test() {\n                Task.Run(() => { print \"Hello\" })\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    argument3 := new List<Argument>()
    statement4 := new List<Statement>()
    statement4.Add(Golden.Print(Golden.StrLit("\"Hello\"", 3, 40), 3, 34))
    argument3.Add(Golden.ArgF(null, Golden.BlockLambda(Golden.NoParams(), Golden.Block(statement4, 3, 32), 3, 26), ArgumentModifier.None))
    statement2.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Task", 3, 17), "Run", false, 3, 21), argument3, Golden.NoTypeArgs(), 3, 25), 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser lambda: a block-bodied lambda in a call argument — `items.Where(x => { print x; return x % 2 == 0 })` — keeps the parenless parameter anchor AND fills BlockBody instead of ExpressionBody, with both statements inside (was ParserTests.Lambda_SingleParamWithBlockBody)" {
    source := "\n            func Test() {\n                items := [1, 2, 3]\n                evens := items.Where(x => {\n                    print x\n                    return x % 2 == 0\n                })\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    expression3 := new List<Expression>()
    expression3.Add(Golden.IntLit("1", 3, 27))
    expression3.Add(Golden.IntLit("2", 3, 30))
    expression3.Add(Golden.IntLit("3", 3, 33))
    statement2.Add(Golden.VarDecl("items", null, Golden.ArrayLit(expression3, false, 3, 26), VariableKind.Let, 3, 17))
    argument4 := new List<Argument>()
    parameter5 := new List<Parameter>()
    parameter5.Add(Golden.Param("x", Golden.BareT("var"), null, false, ParameterModifier.None, 4, 38))
    statement6 := new List<Statement>()
    statement6.Add(Golden.Print(Golden.Ident("x", 5, 27), 5, 21))
    statement6.Add(Golden.Return(Golden.Bin(Golden.Bin(Golden.Ident("x", 6, 28), BinaryOperator.Modulo, Golden.IntLit("2", 6, 32), 6, 30), BinaryOperator.Equal, Golden.IntLit("0", 6, 37), 6, 34), 6, 21))
    argument4.Add(Golden.ArgF(null, Golden.BlockLambda(parameter5, Golden.Block(statement6, 4, 43), 4, 38), ArgumentModifier.None))
    statement2.Add(Golden.VarDecl("evens", null, Golden.Call(Golden.Member(Golden.Ident("items", 4, 26), "Where", false, 4, 31), argument4, Golden.NoTypeArgs(), 4, 37), VariableKind.Let, 4, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser lambda: `x => y => x + y` nests a LambdaExpression inside a LambdaExpression ExpressionBody, each with its own single parameter, and the inner one anchors five columns right of the outer (was ParserTests.Lambda_NestedLambdas)" {
    source := "\n            func Test() {\n                mapper := x => y => x + y\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    parameter3 := new List<Parameter>()
    parameter3.Add(Golden.Param("x", Golden.BareT("var"), null, false, ParameterModifier.None, 3, 27))
    parameter4 := new List<Parameter>()
    parameter4.Add(Golden.Param("y", Golden.BareT("var"), null, false, ParameterModifier.None, 3, 32))
    statement2.Add(Golden.VarDecl("mapper", null, Golden.Lambda(parameter3, Golden.Lambda(parameter4, Golden.Bin(Golden.Ident("x", 3, 37), BinaryOperator.Add, Golden.Ident("y", 3, 41), 3, 39), 3, 32), 3, 27), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}


// ---- (c) TYPE REFERENCES — 4 contracts, and the residue's ONE negative ----
//
// THIS IS THE ONLY FAMILY OF THE FOUR WHOSE DELETED TESTS STATED POSITIONS.
// `TypeReferenceSpans_CoverCompositeTypeShapes` asserted six `SourceSpan` values outright; every other
// position in the whole 824-line residue is unstated. The six are restatements here — what the golden
// adds is the THREE type spans that same file leaves unstated — the record field, the function type's
// return arm and the function's own `void` — plus every anchor and every field of the whole unit.
//
// THREE COMPOSITE NESTINGS ARE MEASURED AT ZERO OCCURRENCES BEFORE THIS FILE: an ArrayTypeReference
// over a NullableTypeReference, a NullableTypeReference over an ArrayTypeReference, and an
// ArrayTypeReference over a UnionTypeReference. The first two are the postfix-order PAIR, and pinning
// both together is what makes the rule observable: `string?[]` and `string[]?` start at the SAME
// column at all three levels, so only the span WIDTHS separate them — 6, 7 and 9 columns in one order,
// 6, 8 and 9 in the other. The deleted test asserted the nesting and no span at all.
//
// A UNION TYPE REFERENCE IN A CAST TARGET AND IN AN `is` TYPE also occurs zero times before this file;
// `AnonymousUnionType_ParsesInSupportedTypePositions` carries both, plus the alias, array-element,
// parameter and generic-argument positions, in ONE fixture.
//
// THE NEGATIVE IS THE ARC'S LAST, AND IT IS THE FIRST TO PIN A WHOLE RECOVERED TREE.
// `AssertHasParseError(source, message)` asserted `!Success` plus `Errors.Any(e =>
// e.Message.Contains(message))` — a substring of one message. The successor states the whole census,
// the whole ROW (span, message, snippet, explanation, hint, suggestions, docs URL), the recovered top
// level, AND the whole AST the recovery produced. That last part is new to the arc: the five earlier
// negatives stated `PeDecls` and stopped.

test "020 s22 parser type: `string?[]` and `string[]?` differ ONLY in nesting order — Array over Nullable over Simple against Nullable over Array over Simple — and all three levels of each start at the SAME column, so the shapes are separable by SPAN WIDTH alone: 6, 7, 9 columns (was ParserTests.TestNullableArrayPostfixOrder)" {
    source := "func Use(names: string?[], maybeNames: string[]?) { }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    parameter2 := new List<Parameter>()
    parameter2.Add(Golden.Param("names", Golden.ArrayT(Golden.NullableT(Golden.SimpleT("string", 1, 17, 23), 1, 17, 24), 1, 17, 26), null, false, ParameterModifier.None, 1, 10))
    parameter2.Add(Golden.Param("maybeNames", Golden.NullableT(Golden.ArrayT(Golden.SimpleT("string", 1, 40, 46), 1, 40, 48), 1, 40, 49), null, false, ParameterModifier.None, 1, 28))
    declaration1.Add(Golden.Func("Use", parameter2, null, Golden.Block(Golden.NoStmts(), 1, 51), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser type: the composite spans of `List<Person?>[]` and `Func<Person, string>` measured whole — the array covers its own brackets, the generic covers its own closing angle, the nullable covers its own question mark, and the function type covers both its parameter and return arms (was ParserTests.TypeReferenceSpans_CoverCompositeTypeShapes)" {
    source := "record Person {\n    Name: string\n}\n\nfunc Use(items: List<Person?>[], callback: Func<Person, string>): void {\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    declaration2 := new List<Declaration>()
    declaration2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 2, 11, 17), null, Modifiers.None, PropertyModifier.None, 2, 5))
    declaration1.Add(Golden.RecordF("Person", null, Golden.NoTypeRefs(), declaration2, null, false, Modifiers.None, 1, 1))
    parameter3 := new List<Parameter>()
    typereference4 := new List<TypeReference>()
    typereference4.Add(Golden.NullableT(Golden.SimpleT("Person", 5, 22, 28), 5, 22, 29))
    parameter3.Add(Golden.Param("items", Golden.ArrayT(Golden.GenericT("List", typereference4, 5, 17, 30), 5, 17, 32), null, false, ParameterModifier.None, 5, 10))
    typereference5 := new List<TypeReference>()
    typereference5.Add(Golden.SimpleT("Person", 5, 49, 55))
    parameter3.Add(Golden.Param("callback", Golden.FuncT(typereference5, Golden.SimpleT("string", 5, 57, 63), 5, 44, 64), null, false, ParameterModifier.None, 5, 34))
    declaration1.Add(Golden.Func("Use", parameter3, Golden.SimpleT("void", 5, 67, 71), Golden.Block(Golden.NoStmts(), 5, 72), null, null, null, Modifiers.None, 5, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser type: an anonymous union parses in FIVE positions at once — a type alias, an array ELEMENT type, a parameter type, a generic type ARGUMENT and both a cast target and an `is` type — and one of its arms is itself an ArrayTypeReference, which the deleted test asserted by index and nothing more (was ParserTests.AnonymousUnionType_ParsesInSupportedTypePositions)" {
    source := "type Greeting = PrebakedGreeting | string\n\nrecord Holder {\n    Value: (int | string)[]\n}\n\nfunc Hi(greeting: PrebakedGreeting | string): List<int | string[]> {\n    casted := (PrebakedGreeting | string)greeting\n    ok := greeting is PrebakedGreeting | string\n    return new List<int | string[]>()\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    typereference2 := new List<TypeReference>()
    typereference2.Add(Golden.SimpleT("PrebakedGreeting", 1, 17, 33))
    typereference2.Add(Golden.SimpleT("string", 1, 36, 42))
    declaration1.Add(Golden.TypeAliasF("Greeting", Golden.UnionT(typereference2, 1, 17, 42), 1, 1))
    declaration3 := new List<Declaration>()
    typereference4 := new List<TypeReference>()
    typereference4.Add(Golden.SimpleT("int", 4, 13, 16))
    typereference4.Add(Golden.SimpleT("string", 4, 19, 25))
    declaration3.Add(Golden.FieldF("Value", Golden.ArrayT(Golden.UnionT(typereference4, 4, 12, 26), 4, 12, 28), null, Modifiers.None, PropertyModifier.None, 4, 5))
    declaration1.Add(Golden.RecordF("Holder", null, Golden.NoTypeRefs(), declaration3, null, false, Modifiers.None, 3, 1))
    parameter5 := new List<Parameter>()
    typereference6 := new List<TypeReference>()
    typereference6.Add(Golden.SimpleT("PrebakedGreeting", 7, 19, 35))
    typereference6.Add(Golden.SimpleT("string", 7, 38, 44))
    parameter5.Add(Golden.Param("greeting", Golden.UnionT(typereference6, 7, 19, 44), null, false, ParameterModifier.None, 7, 9))
    typereference7 := new List<TypeReference>()
    typereference8 := new List<TypeReference>()
    typereference8.Add(Golden.SimpleT("int", 7, 52, 55))
    typereference8.Add(Golden.ArrayT(Golden.SimpleT("string", 7, 58, 64), 7, 58, 66))
    typereference7.Add(Golden.UnionT(typereference8, 7, 52, 66))
    statement9 := new List<Statement>()
    typereference10 := new List<TypeReference>()
    typereference10.Add(Golden.SimpleT("PrebakedGreeting", 8, 16, 32))
    typereference10.Add(Golden.SimpleT("string", 8, 35, 41))
    statement9.Add(Golden.VarDecl("casted", null, Golden.Cast(Golden.Ident("greeting", 8, 42), Golden.UnionT(typereference10, 8, 16, 41), CastKind.Hard, 8, 15), VariableKind.Let, 8, 5))
    typereference11 := new List<TypeReference>()
    typereference11.Add(Golden.SimpleT("PrebakedGreeting", 9, 23, 39))
    typereference11.Add(Golden.SimpleT("string", 9, 42, 48))
    statement9.Add(Golden.VarDecl("ok", null, Golden.Is(Golden.Ident("greeting", 9, 11), Golden.UnionT(typereference11, 9, 23, 48), null, 9, 20), VariableKind.Let, 9, 5))
    typereference12 := new List<TypeReference>()
    typereference13 := new List<TypeReference>()
    typereference13.Add(Golden.SimpleT("int", 10, 21, 24))
    typereference13.Add(Golden.ArrayT(Golden.SimpleT("string", 10, 27, 33), 10, 27, 35))
    typereference12.Add(Golden.UnionT(typereference13, 10, 21, 35))
    statement9.Add(Golden.Return(Golden.NewE(Golden.GenericT("List", typereference12, 10, 16, 36), Golden.NoArgs(), null, null, 10, 12), 10, 5))
    declaration1.Add(Golden.Func("Hi", parameter5, Golden.GenericT("List", typereference7, 7, 47, 67), Golden.Block(statement9, 7, 68), null, null, null, Modifiers.None, 7, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser type NEGATIVE: `int |` with no right arm is refused ONCE at the closing paren, and the refusal costs nothing — the function comes back whole, and the half-built UnionTypeReference keeps its ONE arm with a span stretched to where the missing arm would have started (was ParserTests.AnonymousUnionType_ReportsMissingRightArm)" {
    source := "func Bad(value: int |): void {\n}"
    assert !PeParse(source).Success
    assert PeCensus(source) == "NL103@1:22+1;", PeCensus(source)
    assert PeRow(source, 0) == "NL103@1:22+1|Expected a type after '|' in anonymous union type|func Bad(value: int |): void {|Anonymous union types use the form `A | B`, so every `|` must be followed by another type.|Add the missing type arm, or remove the trailing `|`.|<null>|https://docs.n-sharp.dev/errors/NL103", PeRow(source, 0)
    assert PeRow(source, 1) == "<no-such-error>", PeRow(source, 1)
    assert PeDecls(source) == "FunctionDeclaration[Bad/s0]", PeDecls(source)
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    parameter2 := new List<Parameter>()
    typereference3 := new List<TypeReference>()
    typereference3.Add(Golden.SimpleT("int", 1, 17, 20))
    parameter2.Add(Golden.Param("value", Golden.UnionT(typereference3, 1, 17, 22), null, false, ParameterModifier.None, 1, 10))
    declaration1.Add(Golden.Func("Bad", parameter2, Golden.SimpleT("void", 1, 25, 29), Golden.Block(Golden.NoStmts(), 1, 30), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}


// ---- (d) OPERATORS — 4 contracts ----
//
// PRECEDENCE, THE TERNARY ANCHOR AND `??` ARE RESTATEMENTS. `ColumnarParserAst.tests.nl` pins a
// ternary anchored on its `?` (:3133) and a `??` BinaryExpression (:3120 region), and
// `ColumnarParserSmallFamilies.tests.nl` restates both. What this family adds is real operands —
// string arms on the ternary, a whole BinaryExpression as its condition — and the precedence tree.
//
// ONE OPERATOR IS GENUINELY NEW TO THE PARSER LEDGER, AND THE MEASUREMENT IS EXACT.
// `AssignmentOperator.NullCoalesceAssign` appears in the estate only in `AnalyzerAssignment.tests.nl`
// (4 sites, over `new AssignmentExpression(…)` nodes built by hand) and `OperatorFacts.tests.nl`
// (3 sites, in the operator-TEXT table). **No parser contract anywhere builds a `??=` from source**,
// so its node type, its operator value and its anchor on the FIRST question mark are all new here.

test "020 s22 parser operator: `1 + 2 * 3` binds `*` tighter than `+` — the multiply is the Add node RIGHT operand, not its left — and each BinaryExpression anchors on its own operator token (was ParserTests.TestBinaryExpression)" {
    source := "\n            func Test(): int {\n                return 1 + 2 * 3\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.Return(Golden.Bin(Golden.IntLit("1", 3, 24), BinaryOperator.Add, Golden.Bin(Golden.IntLit("2", 3, 28), BinaryOperator.Multiply, Golden.IntLit("3", 3, 32), 3, 30), 3, 26), 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), Golden.SimpleT("int", 2, 26, 29), Golden.Block(statement2, 2, 30), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser operator: `x > 5 ? big : small` is a TernaryExpression anchored on the QUESTION MARK whose Condition is a whole BinaryExpression, with both arms StringLiteralExpressions whose Value keeps the surrounding quotes (was ParserTests.TestTernaryExpression)" {
    source := "\n            func Test() {\n                result := x > 5 ? \"big\" : \"small\"\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("result", null, Golden.Tern(Golden.Bin(Golden.Ident("x", 3, 27), BinaryOperator.Greater, Golden.IntLit("5", 3, 31), 3, 29), Golden.StrLit("\"big\"", 3, 35), Golden.StrLit("\"small\"", 3, 43), 3, 33), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser operator: `??` is a BinaryExpression with BinaryOperator.NullCoalesce — not a node of its own — anchored on the FIRST of the two question marks (was ParserTests.TestNullCoalescingExpression)" {
    source := "\n            func Test() {\n                value := maybeNull ?? \"default\"\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("value", null, Golden.Bin(Golden.Ident("maybeNull", 3, 26), BinaryOperator.NullCoalesce, Golden.StrLit("\"default\"", 3, 39), 3, 36), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s22 parser operator: `??=` is an AssignmentExpression with AssignmentOperator.NullCoalesceAssign anchored on the first question mark, and the two statements around it pin that `let cache = null` is a VariableKind.Let declaration with a NullLiteralExpression initializer rather than an assignment (was ParserTests.TestNullCoalescingAssignment)" {
    source := "\n            func Test() {\n                let cache = null\n                cache ??= ExpensiveOperation()\n\n                let dict = null\n                dict ??= new Dictionary<string, int>()\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("cache", null, Golden.NullLit(3, 29), VariableKind.Let, 3, 21))
    statement2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("cache", 4, 17), AssignmentOperator.NullCoalesceAssign, Golden.Call(Golden.Ident("ExpensiveOperation", 4, 27), Golden.NoArgs(), Golden.NoTypeArgs(), 4, 45), 4, 23), 4, 17))
    statement2.Add(Golden.VarDecl("dict", null, Golden.NullLit(6, 28), VariableKind.Let, 6, 21))
    typereference3 := new List<TypeReference>()
    typereference3.Add(Golden.SimpleT("string", 7, 41, 47))
    typereference3.Add(Golden.SimpleT("int", 7, 49, 52))
    statement2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("dict", 7, 17), AssignmentOperator.NullCoalesceAssign, Golden.NewE(Golden.GenericT("Dictionary", typereference3, 7, 30, 53), Golden.NoArgs(), null, null, 7, 26), 7, 22), 7, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL PARSE CONTRACTS FOR THE `on` / `off` EVENT-SUBSCRIPTION SYNTAX, IN N#.
//
// These replace the PARSE HALF of `tests/EventSubscriptionTests.cs`, which task 020 slice 24 deletes.
// That file had ten `[Fact]`s and 28 `Assert.` occurrences decoding to 55 claim rows; the 49 rows
// made by its five `Parse_*` methods are restated here, and the 6 made by its five `Analyze_*`
// methods moved to `tests/native/analyzer-event-subscription`, because those drive `Analyzer`, the C#
// class in `Compiler.dll`, and `Compiler.dll` depends on this assembly rather than the other way
// round. The split is by SUBJECT and was re-measured before any edit: five methods reach only
// `ColumnarParserRecovery.ParseFileAst` and assert over AST node types, five reach `Analyzer.Analyze`
// and assert over `AnalysisResult`.
//
// THE ROUTE IS THE WHOLE-TREE GOLDEN, AS IT IS FOR EVERY OTHER PARSER FAMILY IN THIS ESTATE, AND IT
// IS STRICTLY STRONGER THAN WHAT IT REPLACES. All five deleted methods went through one helper:
//
//     private static CompilationUnit Parse(string source)
//     {
//         return ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit!;
//     }
//
// followed by a `MainBody` helper that asserted the first declaration was a function with a body, and
// then one to four `Assert.IsType` / `Assert.Equal` reads. Not one of them stated a single Line or
// Column, so a parser that produced the right node KIND at the wrong position passed all five. Every
// anchor below is pinned, and every anchor was TRANSCRIBED FROM THE PARSER ITSELF by a generator
// probe rather than counted by hand.
//
// THE FIRST CLAIM IN EVERY CONTRACT IS THE PARSE CENSUS, AND THE DELETED HELPER COULD NOT MAKE IT —
// it read `.CompilationUnit` and discarded `.Errors` outright. MEASURED RESULT: all five fixtures
// parse with an EMPTY diagnostic list. (The five ANALYSIS fixtures parse cleanly too, and their
// native successors pin that separately, which is what makes their NL317 / NL318 rows the ANALYZER's
// and not the parser's.)
//
// THE FIXTURES ARE THE DELETED ONES BYTE-FOR-BYTE, decoded by the C# compiler itself rather than by a
// hand-rolled literal reader: all ten literals in the deleted file are verbatim `@"…"` forms, and
// each was pasted unmodified into a generated console program that printed its sha256 and its N#
// spelling.
//
// WHAT THE SIBLING FILE ALREADY COVERED, SWEPT BEFORE THIS ONE WAS WRITTEN.
// `ColumnarParserAst.tests.nl`'s stage-N+1c tranche 10 pins `off handle` and
// `s := on t.E (a, b) => { g() }` over SYNTHETIC one-line bodies. Neither is duplicated here: these
// contracts are over the real fixtures, and they add the four shapes the tranche never reached — an
// `on` subscription as a bare EXPRESSION STATEMENT, a `this` receiver, a handler with an EMPTY block
// body, and `on` / `off` used as ORDINARY IDENTIFIERS.

// ---- contracts ----

// WHAT THE GOLDEN ADDS HERE: the deleted method asserted three node types and one parameter count.
// The golden additionally pins that the `on` expression and its enclosing statement BOTH anchor on
// the `on` keyword at column 5, that the member access anchors on its DOT at column 14 rather than on
// either operand, that the handler lambda anchors on its `(` at column 23 and its block on the `{` at
// column 41, and the whole print statement inside the handler body — which the deleted assertion
// never looked at.
test "020 s24 parser events: an `on` subscription is an EXPRESSION STATEMENT whose expression and statement share the `on` anchor, over a member access anchored on its dot, with a two-parameter block handler (was EventSubscriptionTests.Parse_OnSubscription_AsStatement)" {
    source := "func main() {\n    on widget.Clicked (sender, args) => { print \"hi\" }\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    handlerParams3 := Golden.NoParams()
    Golden.AddLambdaParam(handlerParams3, "sender", 2, 24)
    Golden.AddLambdaParam(handlerParams3, "args", 2, 32)
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.Print(Golden.StrLit("\"hi\"", 2, 49), 2, 43))
    stmts2.Add(Golden.ExprStmt(Golden.OnSub(Golden.Member(Golden.Ident("widget", 2, 8), "Clicked", false, 2, 14), Golden.BlockLambda(handlerParams3, Golden.Block(stmts4, 2, 41), 2, 23), 2, 5), 2, 5))
    decls1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(stmts2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: the deleted method asserted the declaration's name and that its
// initializer was an `on` expression. The golden pins that the shorthand carries a NULL declared type
// and `VariableKind.Let` — the same node the `let` form produces — and that the `on` expression
// anchors on the `on` keyword at column 12, seven columns right of the statement it initializes. The
// handler's block body is EMPTY, a shape the sibling tranche never parsed.
test "020 s24 parser events: `sub := on …` is the ordinary shorthand VariableDeclarationStatement — null type, Kind=Let — whose initializer is the `on` expression anchored on its own keyword, with an EMPTY handler block (was EventSubscriptionTests.Parse_OnSubscription_AsShorthandDeclaration)" {
    source := "func main() {\n    sub := on widget.Clicked (sender, args) => { }\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    handlerParams3 := Golden.NoParams()
    Golden.AddLambdaParam(handlerParams3, "sender", 2, 31)
    Golden.AddLambdaParam(handlerParams3, "args", 2, 39)
    stmts4 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("sub", null, Golden.OnSub(Golden.Member(Golden.Ident("widget", 2, 15), "Clicked", false, 2, 21), Golden.BlockLambda(handlerParams3, Golden.Block(stmts4, 2, 48), 2, 30), 2, 12), VariableKind.Let, 2, 5))
    decls1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(stmts2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: the deleted method asserted the receiver was a `ThisExpression` and the
// member name was `Clicked`. The golden pins that `this` is a node with its OWN anchor at column 8 —
// not a flag on the member access — and that the member access still anchors on its dot at column 12,
// four columns right, exactly as it does over an identifier receiver.
test "020 s24 parser events: a `this` receiver is a ThisExpression node with its own anchor, and the member access over it anchors on its dot exactly as it does over an identifier (was EventSubscriptionTests.Parse_OnSubscription_AllowsThisTarget)" {
    source := "func main() {\n    on this.Clicked (sender, args) => { }\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    handlerParams3 := Golden.NoParams()
    Golden.AddLambdaParam(handlerParams3, "sender", 2, 22)
    Golden.AddLambdaParam(handlerParams3, "args", 2, 30)
    stmts4 := new List<Statement>()
    stmts2.Add(Golden.ExprStmt(Golden.OnSub(Golden.Member(Golden.ThisE(2, 8), "Clicked", false, 2, 12), Golden.BlockLambda(handlerParams3, Golden.Block(stmts4, 2, 39), 2, 21), 2, 5), 2, 5))
    decls1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(stmts2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: the deleted method asserted the statement kind and the handle's name.
// The golden pins that `off` is a STATEMENT anchored on its keyword at column 5 while its handle is a
// separate expression node at column 9 — so the statement and its operand are distinguishable by
// position, which is what a fix or a rename has to preserve.
test "020 s24 parser events: `off sub` is an OffStatement anchored on the keyword with its handle a separate IdentifierExpression four columns right (was EventSubscriptionTests.Parse_OffStatement)" {
    source := "func main() {\n    off sub\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.Off(Golden.Ident("sub", 2, 9), 2, 5))
    decls1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(stmts2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: the deleted method asserted three declaration kinds and two names, and
// said nothing at all about the third statement's initializer or the fourth statement. The golden
// pins that `on` and `off` are ORDINARY IdentifierExpressions inside `total := on + off` — the binary
// expression anchors on its `+` at column 17 with the two contextual keywords as its operands — and
// that the print statement that follows reads the local rather than re-parsing a keyword.
test "020 s24 parser events: `on` and `off` used as names produce ordinary Let declarations AND ordinary IdentifierExpression operands of a `+` anchored on the operator, with the following print statement pinned too (was EventSubscriptionTests.Parse_OnAndOff_RemainUsableAsIdentifiers)" {
    source := "func main() {\n    on := 5\n    off := 10\n    total := on + off\n    print total\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("on", null, Golden.IntLit("5", 2, 11), VariableKind.Let, 2, 5))
    stmts2.Add(Golden.VarDecl("off", null, Golden.IntLit("10", 3, 12), VariableKind.Let, 3, 5))
    stmts2.Add(Golden.VarDecl("total", null, Golden.Bin(Golden.Ident("on", 4, 14), BinaryOperator.Add, Golden.Ident("off", 4, 19), 4, 17), VariableKind.Let, 4, 5))
    stmts2.Add(Golden.Print(Golden.Ident("total", 5, 11), 5, 5))
    decls1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(stmts2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// THE CONTEXT CONTROL, AND IT STATES NOTHING THE DELETED FILE STATED. Its two `on` fixtures were
// separate sources: one where `on` opens a subscription and one where `on` is a local. This fixture
// is BOTH, in that order — `on := 5` binds the name on line 2, and line 3 still parses
// `on widget.Clicked …` as a subscription rather than as a use of the local, with `off sub` after it.
// So the contextual keyword is decided by the SYNTAX that follows it and not by what the name is
// already bound to, which is the property a future parser change is most likely to break and which
// neither deleted method could observe.
test "020 s24 parser events: `on` bound as a LOCAL on one line does not stop the NEXT line parsing `on <target> <handler>` as a subscription — both shapes, and an `off`, in one function body" {
    source := "func main() {\n    on := 5\n    sub := on widget.Clicked (sender, args) => { }\n    off sub\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("on", null, Golden.IntLit("5", 2, 11), VariableKind.Let, 2, 5))
    handlerParams3 := Golden.NoParams()
    Golden.AddLambdaParam(handlerParams3, "sender", 3, 31)
    Golden.AddLambdaParam(handlerParams3, "args", 3, 39)
    stmts4 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("sub", null, Golden.OnSub(Golden.Member(Golden.Ident("widget", 3, 15), "Clicked", false, 3, 21), Golden.BlockLambda(handlerParams3, Golden.Block(stmts4, 3, 48), 3, 30), 3, 12), VariableKind.Let, 3, 5))
    stmts2.Add(Golden.Off(Golden.Ident("sub", 4, 9), 4, 5))
    decls1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(stmts2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

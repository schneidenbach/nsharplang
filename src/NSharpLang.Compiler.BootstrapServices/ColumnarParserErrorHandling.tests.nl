namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL ERROR-HANDLING PARSE CONTRACTS FOR `ColumnarParserRecovery.ParseFileAst`, IN N#.
//
// These replace the PARSE HALF of `tests/ErrorHandlingTests.cs`, which task 020 slice 25 deletes.
// That file had 39 `[Fact]`s and 54 `Assert.` occurrences. The split is by SUBJECT and was
// RE-MEASURED by decoding the file before any edit: 24 methods reach only
// `ColumnarParserRecovery.ParseFileAst` and are restated here; the other 15 construct an `Analyzer`
// (three of them also a `Linter`) and moved to `tests/native/analyzer-error-handling`, because
// `Analyzer` is the C# class in `Compiler.dll` and `Compiler.dll` depends on this assembly rather
// than the other way round. The subject test does not follow the method NAMES: three methods called
// `Parser_*` — duplicate declarations, `break` outside a loop, `continue` outside a loop — assert
// only over `AnalysisResult` and are in the native half.
//
// WHAT THE 24 DELETED METHODS ACTUALLY ASSERTED. All of them went through one helper:
//
//     private static CompilationUnit Parse(string code)
//     {
//         var result = ColumnarParserRecovery.ParseFileAst(code, "test.nl");
//         return result.CompilationUnit!;
//     }
//
// and then 21 of them asserted `Assert.NotNull(unit)` and NOTHING ELSE. Three asserted one more
// thing: `Assert.Empty(unit.Declarations)` (three times) and one `Assert.Contains(…, decl.Name ==
// "after")`. A parser that produced an empty unit for every one of the 21 passed all 21.
//
// THIS IS THE FIRST TRANCHE WHOSE CLEAN-PARSE PIN IS NON-EMPTY BY DESIGN. These are RECOVERY
// fixtures: 13 of the 24 report diagnostics, 17 diagnostics in all, and every one of them is named
// below by code, line, column and length, plus a whole-row pin carrying its message, its source
// snippet, its human explanation, its contextual hint, every suggestion and its docs URL. The other
// 11 fixtures pin an EMPTY census, which is a claim in the opposite direction and just as new — four
// of them (`func main() `, `func getValue() { return 42 }`, the 1000-character identifier and the
// 100-deep parenthesis nest) are fixtures whose NAMES say the parser should be complaining.
//
// THE FIXTURES ARE THE DELETED ONES BYTE-FOR-BYTE, decoded by the C# compiler itself rather than by
// a hand-rolled literal reader: each deleted method's fixture-construction prefix was pasted
// unmodified into a generated console program that printed the resulting string's sha256, its length
// and its N# spelling. Three fixtures are CONSTRUCTED rather than literal in the deleted file (a
// 1000-character identifier, 100 nested parentheses, 50 nested blocks); those three are constructed
// here by the mirror loop and each asserts its own byte LENGTH against the C# decoder's count before
// it parses anything, so the constructed source is provably the deleted one.
//
// EVERY GOLDEN WAS TRANSCRIBED FROM THE PARSER, NOT COUNTED BY HAND. A scratch walker read the same
// production assembly this estate compiles to, parsed each fixture, dumped the recovered tree
// generically, and a generator turned each dump into the `Golden.*` body below; a node type the
// generator did not model came back as a MARKER rather than a plausible value, and ZERO markers came
// back across all 24.
//
// THE ONE STRUCTURAL FACT THAT EXPLAINS MOST OF THIS FILE. `var x = 5` is C# and not N#. The N#
// parser reads `var` as an ordinary IdentifierExpression statement and `x = 5` as a separate
// AssignmentExpression statement, so nearly every fixture in the deleted file has TWICE the
// statements its author intended and none of them is a VariableDeclarationStatement. `Assert.NotNull`
// could not see that; every golden below states it.
//
// WHY THIS FILE AND NOT AN APPEND TO `ColumnarParserErrorRecovery.tests.nl`. That file is the
// task-016 migration of `tests/ParserErrorTests.cs` and its contracts are DIAGNOSTIC censuses over
// deliberately malformed N#. This tranche's subject is different: it is what the recovered TREE looks
// like after C#-shaped source goes in, and its route is the whole-tree golden. The two files share
// the `Pe*` kernels — this one calls `PeCensus` and `PeRow` from next door and `PsAst` from
// `ColumnarParserStatements.tests.nl` — and add no kernels of their own.

// ---- contracts ----

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only that the unit was not null. The golden pins that `var x = …`
// is NOT a declaration in N# at all: `var` parses as a bare IdentifierExpression statement at 2:5 and
// `s = "unterminated` as a separate AssignmentExpression statement at 2:9, so this fixture's real
// subject is two statements, not one. It also pins that the recovered string literal's Value KEEPS its
// opening quote (`"unterminated`) — the lexer hands the unterminated text through rather than
// discarding it — and the whole NL105 row, whose two suggestions the deleted assertion never read.
test "020 s25 error handling: an unterminated string literal is ONE NL105 over the 13 columns from the opening quote to end of line, and the recovered body is `var` as a bare identifier statement plus an assignment whose value is the unterminated text INCLUDING its opening quote (was ErrorHandlingTests.Parser_HandlesUnterminatedString)" {
    source := "func main() {\n    var s = \"unterminated\n}"
    assert PeCensus(source) == "NL105@2:13+13;"
    assert PeRow(source, 0) == "NL105@2:13+13|Unterminated string literal|    var s = \"unterminated|This string starts with a quote but reaches the end of the line before a closing quote.|Add the closing quote on this line, or use a triple-quoted string for multi-line text.|{Add a closing quote}{Use triple quotes for multi-line strings}|https://docs.n-sharp.dev/errors/NL105"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("s", 2, 9), AssignmentOperator.Assign, Golden.StrLit("\"unterminated", 2, 13), 2, 11), 2, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: THIS IS THE SHARPEST THING IN THE TRANCHE AND THE DELETED ASSERTION COULD NOT SEE IT.
// `Assert.NotNull(unit)` passed, and the unit it passed on is EMPTY: the `func main()` inside the
// unterminated comment is gone and the parser reports NO diagnostic about it. The census pins the
// silence and the golden pins the emptiness, so a future parser that starts reporting NL1xx here — or
// that starts recovering the function — moves this contract. The unit's own anchor is 4:2, which is
// where the lexer stopped; nothing had ever written that down.
test "020 s25 error handling: an unterminated block comment SWALLOWS THE WHOLE FILE AND REPORTS NOTHING — zero declarations, zero diagnostics, and a CompilationUnit anchored at 4:2, past the last line (was ErrorHandlingTests.Parser_HandlesUnterminatedComment)" {
    source := "/* This comment never ends\nfunc main() {\n    print(\"hello\")\n}"
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 4, 2)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. The golden pins that recovery does NOT drop the
// unclosed `if`: the body has three statements and the third is a real IfStatement whose condition is
// `x > 0` anchored on its `>` at 3:10, with the `print(x)` inside it. The NL106 row's explanation names
// line 3 as the block that started — the same line the anchor is on, not the file end.
test "020 s25 error handling: a block left open at end of file is ONE NL106 anchored on the `if` KEYWORD two lines below the brace it is about, and the recovered body still carries all three statements including the if (was ErrorHandlingTests.Parser_HandlesMissingClosingBrace)" {
    source := "func main() {\n    var x = 5\n    if x > 0 {\n        print(x)\n    // Missing closing brace\n"
    assert PeCensus(source) == "NL106@3:5+2;"
    assert PeRow(source, 0) == "NL106@3:5+2|Missing closing '}'|    if x > 0 {|The block that started on line 3 is missing its closing brace. I reached the end of the file without finding it.|Add a '}' to close this block.|<null>|https://docs.n-sharp.dev/errors/NL106"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("x", 2, 9), AssignmentOperator.Assign, Golden.IntLit("5", 2, 13), 2, 11), 2, 9))
    statements3 := new List<Statement>()
    statements3.Add(Golden.Print(Golden.Paren(Golden.Ident("x", 4, 15), 4, 14), 4, 9))
    statements2.Add(Golden.If(Golden.Bin(Golden.Ident("x", 3, 8), BinaryOperator.Greater, Golden.IntLit("0", 3, 12), 3, 10), Golden.Block(statements3, 3, 14), null, 3, 5))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. The golden pins that the unclosed `add(1, 2`
// recovers as a real CallExpression with TWO arguments at 2:22 and 2:25 and nothing synthetic in the
// list — so this diagnostic is about the missing `)` alone. The NL107 anchor is at 2:18, the `add`
// token, three columns left of the `(`; the whole row including both suggestions is pinned.
test "020 s25 error handling: a call left unclosed at end of line is ONE NL107 anchored on the CALLEE `add`, and the call still recovers both of its arguments (was ErrorHandlingTests.Parser_HandlesMissingClosingParen)" {
    source := "func main() {\n    var result = add(1, 2\n}"
    assert PeCensus(source) == "NL107@2:18+3;"
    assert PeRow(source, 0) == "NL107@2:18+3|Missing closing ')'|    var result = add(1, 2|I reached the next line while looking for the closing ')' that matches an earlier '('.|Every opening parenthesis '(' needs a matching closing parenthesis ')'.|{Add ')' before starting the next line}{Check the matching '(' in this expression}|https://docs.n-sharp.dev/errors/NL107"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    args3 := Golden.NoArgs()
    Golden.AddArg(args3, null, Golden.IntLit("1", 2, 22), ArgumentModifier.None)
    Golden.AddArg(args3, null, Golden.IntLit("2", 2, 25), ArgumentModifier.None)
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("result", 2, 9), AssignmentOperator.Assign, Golden.Call(Golden.Ident("add", 2, 18), args3, null, 2, 21), 2, 16), 2, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null over a fixture with two independent trailing
// commas. The golden pins the consequence the census cannot: the array literal has FOUR elements, the
// fourth being an `<error>` identifier at 2:24, and the argument list has THREE arguments, the third
// being an `<error>` identifier at 3:27. So a trailing comma is not silently dropped — it produces a
// placeholder element the analyzer will later see.
test "020 s25 error handling: a trailing comma in an ARRAY literal and one in an ARGUMENT list report TWO separate NL101s, and each leaves a synthetic `<error>` IdentifierExpression in the list it terminated (was ErrorHandlingTests.Parser_HandlesTrailingComma)" {
    source := "func main() {\n    var arr = [1, 2, 3,]\n    var result = add(1, 2,)\n}"
    assert PeCensus(source) == "NL101@2:24+1;NL101@3:27+1;"
    assert PeRow(source, 0) == "NL101@2:24+1|Unexpected token ']' in expression|    var arr = [1, 2, 3,]|I was parsing an expression and found ']', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://docs.n-sharp.dev/errors/NL101"
    assert PeRow(source, 1) == "NL101@3:27+1|Unexpected token ')' in expression|    var result = add(1, 2,)|I was parsing an expression and found ')', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://docs.n-sharp.dev/errors/NL101"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    elements3 := new List<Expression>()
    elements3.Add(Golden.IntLit("1", 2, 16))
    elements3.Add(Golden.IntLit("2", 2, 19))
    elements3.Add(Golden.IntLit("3", 2, 22))
    elements3.Add(Golden.Ident("<error>", 2, 24))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("arr", 2, 9), AssignmentOperator.Assign, Golden.ArrayLit(elements3, false, 2, 15), 2, 13), 2, 9))
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 3, 5), 3, 5))
    args4 := Golden.NoArgs()
    Golden.AddArg(args4, null, Golden.IntLit("1", 3, 22), ArgumentModifier.None)
    Golden.AddArg(args4, null, Golden.IntLit("2", 3, 25), ArgumentModifier.None)
    Golden.AddArg(args4, null, Golden.Ident("<error>", 3, 27), ArgumentModifier.None)
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("result", 3, 9), AssignmentOperator.Assign, Golden.Call(Golden.Ident("add", 3, 18), args4, null, 3, 21), 3, 16), 3, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null and its name says `HandlesInvalidOperator`. The
// golden pins what handling means here: the `@` does not poison the assignment. `x = 5` is a complete
// AssignmentExpression, the `@` becomes an `<error>` IdentifierExpression statement at 2:15, and the
// `3` after it becomes its own IntLiteral statement at 2:17. One NL101, three consequences.
test "020 s25 error handling: an invalid infix operator SPLITS the statement — `var x = 5` completes, and `@ 3` becomes a synthetic `<error>` statement plus a bare `3`, for a body of FOUR statements from two source lines (was ErrorHandlingTests.Parser_HandlesInvalidOperator)" {
    source := "func main() {\n    var x = 5 @ 3  // @ is not a valid operator\n}"
    assert PeCensus(source) == "NL101@2:15+1;"
    assert PeRow(source, 0) == "NL101@2:15+1|Unexpected token '@' in expression|    var x = 5 @ 3  // @ is not a valid operator|I was parsing an expression and found '@', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://docs.n-sharp.dev/errors/NL101"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("x", 2, 9), AssignmentOperator.Assign, Golden.IntLit("5", 2, 13), 2, 11), 2, 9))
    statements2.Add(Golden.ExprStmt(Golden.Ident("<error>", 2, 15), 2, 15))
    statements2.Add(Golden.ExprStmt(Golden.IntLit("3", 2, 17), 2, 17))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. The census is the find: the third diagnostic is
// an NL106 `Missing closing '}'` anchored at 1:6, the `main` token, because the stray `{` at 2:11 opened
// a block that end-of-file closed. The golden pins that block as a REAL BlockStatement inside the
// function body carrying two statements of its own, which is the shape that produced the NL106.
test "020 s25 error handling: a garbage token run reports THREE diagnostics — two NL101s and an NL106 anchored back on the function NAME at 1:6 — and the stray `{` opens a real BlockStatement that becomes the function's third statement (was ErrorHandlingTests.Parser_HandlesInvalidTokenSequence)" {
    source := "func main() {\n    var ] { = 5\n}"
    assert PeCensus(source) == "NL101@2:9+1;NL101@2:13+1;NL106@1:6+4;"
    assert PeRow(source, 0) == "NL101@2:9+1|Unexpected token ']' in expression|    var ] { = 5|I was parsing an expression and found ']', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://docs.n-sharp.dev/errors/NL101"
    assert PeRow(source, 1) == "NL101@2:13+1|Unexpected token '=' in expression|    var ] { = 5|I was parsing an expression and found '=', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://docs.n-sharp.dev/errors/NL101"
    assert PeRow(source, 2) == "NL106@1:6+4|Missing closing '}'|func main() {|The block that started on line 1 is missing its closing brace. I reached the end of the file without finding it.|Add a '}' to close this block.|<null>|https://docs.n-sharp.dev/errors/NL106"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Ident("<error>", 2, 9), 2, 9))
    statements3 := new List<Statement>()
    statements3.Add(Golden.ExprStmt(Golden.Ident("<error>", 2, 13), 2, 13))
    statements3.Add(Golden.ExprStmt(Golden.IntLit("5", 2, 15), 2, 15))
    statements2.Add(Golden.Block(statements3, 2, 11))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted non-null and `Empty(unit.Declarations)`. The golden adds that
// Imports, FileImports, Namespace and Package are empty/null too, and the census adds that the empty
// file is not merely declaration-free but DIAGNOSTIC-free.
test "020 s25 error handling: the empty file is a CompilationUnit at 1:1 with zero declarations, zero imports and zero file imports, and ZERO diagnostics (was ErrorHandlingTests.Parser_HandlesEmptyFile)" {
    source := ""
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted non-null and `Empty(unit.Declarations)`. The golden pins the
// unit's own anchor, and it is NOT 1:1: it is 2:22, one past the end of `/* Another comment */`. That
// distinguishes this fixture from the empty file, which the deleted pair of assertions could not.
test "020 s25 error handling: a file of only comments parses to an empty unit anchored at 2:22 — the position where the last comment ends, not 1:1 (was ErrorHandlingTests.Parser_HandlesOnlyComments)" {
    source := "// Just a comment\n/* Another comment */"
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 2, 22)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted non-null and `Empty(unit.Declarations)`, which is exactly what
// the empty-file and only-comments methods asserted, so all three were interchangeable. The three
// goldens are not: their units anchor at 1:1, 2:22 and 3:4 respectively.
test "020 s25 error handling: a file of only whitespace parses to an empty unit anchored at 3:4 — the end of the trailing spaces, and again not 1:1 (was ErrorHandlingTests.Parser_HandlesOnlyWhitespace)" {
    source := "   \n\t\r\n   "
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 3, 4)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method built the name with `new string('a', 1000)` and asserted only non-null.
// This contract CONSTRUCTS the same 1000 characters, asserts the fixture is 1028 bytes so the
// construction is provably the deleted one, and then pins the identifier's Name to that exact string
// and the `=` at column 1010 and the `5` at 1012. A parser that truncated the name at any length, or
// that lost column precision past 999, moves this contract; nothing could observe either before.
test "020 s25 error handling: a 1000-character identifier is carried WHOLE into the tree with no truncation, and the assignment after it anchors at column 1010 — the parser's columns are not capped (was ErrorHandlingTests.Parser_HandlesVeryLongIdentifier)" {
    builder := new StringBuilder()
    index := 0
    while index < 1000 {
        builder.Append("a")
        index = index + 1
    }
    longName := builder.ToString()
    source := "func main() {\n    var " + longName + " = 5\n}"
    assert longName.Length == 1000
    assert source.Length == 1028
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident(longName, 2, 9), AssignmentOperator.Assign, Golden.IntLit("5", 2, 1012), 2, 1010), 2, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method built the nesting with a C# loop and asserted only non-null. This
// contract builds the same 100 pairs, asserts the fixture is 229 bytes, and builds the EXPECTED tree
// with the mirror loop — so the claim is that the parser produces exactly 100 nodes at exactly the 100
// columns arithmetic predicts, with an IntLiteral `1` at the centre at 2:113. A parser that collapsed
// redundant parentheses, or that stopped nesting at some depth, moves this contract.
test "020 s25 error handling: 100 nested parentheses produce 100 REAL ParenthesizedExpression nodes, one per pair, at columns 112 down to 13 — the tree is not flattened and the depth is not capped (was ErrorHandlingTests.Parser_HandlesDeeplyNestedExpressions)" {
    nested := "1"
    index := 0
    while index < 100 {
        nested = "(" + nested + ")"
        index = index + 1
    }
    source := "func main() {\n    var x = " + nested + "\n}"
    assert source.Length == 229
    assert PeCensus(source) == ""
    actual := PsAst(source)
    inner := Golden.IntLit("1", 2, 113)
    depth := 0
    while depth < 100 {
        inner = Golden.Paren(inner, 2, 112 - depth)
        depth = depth + 1
    }
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("x", 2, 9), AssignmentOperator.Assign, inner, 2, 11), 2, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method built the nesting with two C# loops and asserted only non-null. This
// contract builds the same source, asserts it is 624 bytes, and builds the expected tree with the
// mirror loop: level k has its `if` at column 15+10k, its `true` at 18+10k and its block at 23+10k, so
// the innermost is at 505 / 508 / 513 and the innermost body is `var` plus `x = 1` at 515 and 519.
// Every one of those 150 positions is stated by the arithmetic, and none was observable before.
test "020 s25 error handling: 50 nested `if true { … }` blocks produce 50 real IfStatements and 51 BlockStatements on ONE source line, at columns spaced exactly 10 apart, with the innermost body at column 513 (was ErrorHandlingTests.Parser_HandlesDeeplyNestedBlocks)" {
    builder := new StringBuilder()
    builder.Append("func main() {")
    index := 0
    while index < 50 {
        builder.Append(" if true {")
        index = index + 1
    }
    builder.Append(" var x = 1")
    index = 0
    while index < 50 {
        builder.Append(" }")
        index = index + 1
    }
    builder.Append("}")
    source := builder.ToString()
    assert source.Length == 624
    assert PeCensus(source) == ""
    actual := PsAst(source)
    statements := new List<Statement>()
    statements.Add(Golden.ExprStmt(Golden.Ident("var", 1, 515), 1, 515))
    statements.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("x", 1, 519), AssignmentOperator.Assign, Golden.IntLit("1", 1, 523), 1, 521), 1, 519))
    depth := 49
    while depth >= 0 {
        wrapper := new List<Statement>()
        wrapper.Add(Golden.If(Golden.BoolLit(true, 1, 18 + depth * 10), Golden.Block(statements, 1, 23 + depth * 10), null, 1, 15 + depth * 10))
        statements = wrapper
        depth = depth - 1
    }
    declarations1 := new List<Declaration>()
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. The golden pins that all three names survive
// verbatim, that `3.14` becomes a FloatLiteralExpression while `42` becomes an IntLiteral, and — the
// part nothing could see — that the column arithmetic is over UTF-16 units: `café` is 4 units so its
// `=` is at 14, `π` is 1 unit so its `=` is at 11, `数字` is 2 units so its `=` is at 12.
test "020 s25 error handling: non-ASCII identifiers are carried whole — `café`, `π` and `数字` are three ordinary IdentifierExpressions — and the columns COUNT UTF-16 UNITS, so the two-character `数字` puts the following `=` at 12 (was ErrorHandlingTests.Parser_HandlesUnicodeIdentifiers)" {
    source := "func main() {\n    var café = \"coffee\"\n    var π = 3.14\n    var 数字 = 42\n}"
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("café", 2, 9), AssignmentOperator.Assign, Golden.StrLit("\"coffee\"", 2, 16), 2, 14), 2, 9))
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 3, 5), 3, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("π", 3, 9), AssignmentOperator.Assign, Golden.FloatLit("3.14", 3, 13), 3, 11), 3, 9))
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 4, 5), 4, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("数字", 4, 9), AssignmentOperator.Assign, Golden.IntLit("42", 4, 14), 4, 12), 4, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. The golden pins the parser's actual contract for
// string literals, which is that it does NOT decode escapes: `Value` is the raw source text including
// both quotes. So `\n` is still two characters at this layer, and the escaped quote in `s3` did not
// terminate the literal early — the statement after it is intact.
test "020 s25 error handling: escape sequences inside string literals are carried through UNDECODED — the literal's Value keeps its own quotes and its literal backslash-n, backslash-t, backslash-quote and backslash-backslash (was ErrorHandlingTests.Parser_HandlesSpecialCharactersInStrings)" {
    source := "func main() {\n    var s1 = \"Hello\\nWorld\"\n    var s2 = \"Tab\\tSeparated\"\n    var s3 = \"Quote:\\\" \"\n    var s4 = \"Backslash:\\\\\"\n}"
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("s1", 2, 9), AssignmentOperator.Assign, Golden.StrLit("\"Hello\\nWorld\"", 2, 14), 2, 12), 2, 9))
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 3, 5), 3, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("s2", 3, 9), AssignmentOperator.Assign, Golden.StrLit("\"Tab\\tSeparated\"", 3, 14), 3, 12), 3, 9))
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 4, 5), 4, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("s3", 4, 9), AssignmentOperator.Assign, Golden.StrLit("\"Quote:\\\" \"", 4, 14), 4, 12), 4, 9))
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 5, 5), 5, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("s4", 5, 9), AssignmentOperator.Assign, Golden.StrLit("\"Backslash:\\\\\"", 5, 14), 5, 12), 5, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. Two findings: the parser accepts `func main() `
// SILENTLY, with no diagnostic at all, and what it produces is a declaration with a NULL Body. The
// control below pins the other side — `func main() {}` produces a Body that is an EMPTY BlockStatement
// — so null-body and empty-body are provably different trees, which nothing stated.
test "020 s25 error handling: a function with no body at all recovers as a FunctionDeclaration whose Body is NULL — not an empty block — and reports ZERO diagnostics (was ErrorHandlingTests.Parser_HandlesMissingFunctionBody)" {
    source := "func main() "
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, null, null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. The golden pins that `print("hello")` is not a
// call at all: `print` is a statement keyword in N# and the parentheses become a
// ParenthesizedExpression around the literal. It also pins that the recovered function's body opens at
// column 11 — the `{` — because there is no parameter list to open it at 12.
test "020 s25 error handling: a function declared without a parameter list is ONE NL102 anchored on the `{`, and the body still recovers — a parenthesised `print` argument becomes a PrintStatement over a PARENTHESIZED string, not a call (was ErrorHandlingTests.Parser_HandlesMissingFunctionParameters)" {
    source := "func main {\n    print(\"hello\")\n}"
    assert PeCensus(source) == "NL102@1:11+1;"
    assert PeRow(source, 0) == "NL102@1:11+1|Expected '('. Expected '(', got '{'|func main {|I was expecting ( here, but I found '{' instead.|<null>|<null>|https://docs.n-sharp.dev/errors/NL102"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.Print(Golden.Paren(Golden.StrLit("\"hello\"", 2, 11), 2, 10), 2, 5))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 11), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null and its name says `MissingVariableInitializer`.
// The golden shows the fixture is not about initializers at all: `var x: int` is C# syntax, and in N#
// the `:` is what fails, producing NL101 at 2:10 and leaving the type name `int` behind as an ordinary
// IdentifierExpression statement at 2:12.
test "020 s25 error handling: a typed declaration with no initializer breaks into FOUR statements — `var`, `x`, a synthetic `<error>` for the colon, and `int` as a bare identifier (was ErrorHandlingTests.Parser_HandlesMissingVariableInitializer)" {
    source := "func main() {\n    var x: int\n}"
    assert PeCensus(source) == "NL101@2:10+1;"
    assert PeRow(source, 0) == "NL101@2:10+1|Unexpected token ':' in expression|    var x: int|I was parsing an expression and found ':', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://docs.n-sharp.dev/errors/NL101"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Ident("x", 2, 9), 2, 9))
    statements2.Add(Golden.ExprStmt(Golden.Ident("<error>", 2, 10), 2, 10))
    statements2.Add(Golden.ExprStmt(Golden.Ident("int", 2, 12), 2, 12))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null and its name says `MissingReturnType`. Nothing is
// missing: N# infers it, the census is EMPTY, and the golden pins ReturnType null with the return's
// IntLiteral at 2:12.
test "020 s25 error handling: a function with no declared return type parses CLEANLY — ReturnType is null and there is no diagnostic — and its `return 42` is a real ReturnStatement (was ErrorHandlingTests.Parser_HandlesMissingReturnType)" {
    source := "func getValue() {\n    return 42\n}"
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.Return(Golden.IntLit("42", 2, 12), 2, 5))
    declarations1.Add(Golden.Func("getValue", Golden.NoParams(), null, Golden.Block(statements2, 1, 17), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. The golden pins that the expression is NOT
// abandoned: `5 + <error>` is a complete BinaryExpression anchored on its `+` at 2:15, with the
// placeholder at 2:16. The NL102 row's two suggestions were never read.
test "020 s25 error handling: a binary operator with no right operand is ONE NL102 whose span covers THREE columns from the `+`, and the recovered BinaryExpression keeps a synthetic `<error>` identifier as its right operand (was ErrorHandlingTests.Parser_HandlesIncompleteBinaryExpression)" {
    source := "func main() {\n    var x = 5 +\n}"
    assert PeCensus(source) == "NL102@2:13+3;"
    assert PeRow(source, 0) == "NL102@2:13+3|Expected expression after '+'|    var x = 5 +|The '+' operator needs an expression on its right side.|Finish the expression after the operator, or remove the operator if the expression is already complete.|{Add an expression after '+'}{Remove the trailing '+'}|https://docs.n-sharp.dev/errors/NL102"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("x", 2, 9), AssignmentOperator.Assign, Golden.Bin(Golden.IntLit("5", 2, 13), BinaryOperator.Add, Golden.Ident("<error>", 2, 16), 2, 15), 2, 11), 2, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. The find is the anchor: the parser consumed the
// newline looking for the index expression and reported on the `}` at 4:1, so this diagnostic's line
// is not the line of the mistake. The golden pins the recovered IndexAccessExpression whose Index is
// the `<error>` placeholder AT 4:1 as well, which is what carried the position.
test "020 s25 error handling: an index access left unclosed reports NL101 on the CLOSING BRACE OF THE FUNCTION at 4:1 — a line the erroneous statement is not on — and recovers `arr[<error>]` as a real IndexAccessExpression (was ErrorHandlingTests.Parser_HandlesInvalidArrayAccess)" {
    source := "func main() {\n    var arr = [1, 2, 3]\n    var x = arr[\n}"
    assert PeCensus(source) == "NL101@4:1+1;"
    assert PeRow(source, 0) == "NL101@4:1+1|Unexpected token '}' in expression|}|I was parsing an expression and found '}', which I don't know how to handle here.|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax.|<null>|https://docs.n-sharp.dev/errors/NL101"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    elements3 := new List<Expression>()
    elements3.Add(Golden.IntLit("1", 2, 16))
    elements3.Add(Golden.IntLit("2", 2, 19))
    elements3.Add(Golden.IntLit("3", 2, 22))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("arr", 2, 9), AssignmentOperator.Assign, Golden.ArrayLit(elements3, false, 2, 15), 2, 13), 2, 9))
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 3, 5), 3, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("x", 3, 9), AssignmentOperator.Assign, Golden.Index(Golden.Ident("arr", 3, 13), Golden.Ident("<error>", 4, 1), false, 3, 16), 3, 11), 3, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null. The golden pins that the member access is built
// anyway — Object is `obj` at 2:13, MemberName is the literal string `<error>`, IsNullConditional is
// false, and the node anchors on its DOT at 2:16 — so a later stage sees a member access, not a hole.
// The NL102 row carries THREE suggestions, including a list of common member names.
test "020 s25 error handling: a dot with no member name is ONE NL102 spanning three columns, and the MemberAccessExpression survives with `<error>` as its MemberName (was ErrorHandlingTests.Parser_HandlesInvalidMemberAccess)" {
    source := "func main() {\n    var x = obj.\n}"
    assert PeCensus(source) == "NL102@2:13+3;"
    assert PeRow(source, 0) == "NL102@2:13+3|Expected member name. Got '}'|    var x = obj.|I see a dot (.) operator but no member name after it.|After dot (.), I need to see a property or method name.|{Check if you forgot to finish this line}{Common members: Length, Count, ToString(), GetHashCode()}{If this is end of statement, remove the trailing '.'}|https://docs.n-sharp.dev/errors/NL102"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("x", 2, 9), AssignmentOperator.Assign, Golden.Member(Golden.Ident("obj", 2, 13), "<error>", false, 2, 16), 2, 11), 2, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted only non-null and its name says `ChainedErrors`. There is no
// chain: exactly one diagnostic is reported, and it is NL103 `Prefix '+' is not supported` — a rule
// about N# grammar rather than a recovery artefact. The golden pins the precedence of what survives:
// the `*` binds tighter, so the `<error>` placeholder is the LEFT operand of the multiply.
test "020 s25 error handling: a chain of malformed operators is ONE NL103 about the PREFIX `+`, not a cascade, and the recovered tree is a right-nested `5 + (<error> * 3)` (was ErrorHandlingTests.Parser_HandlesChainedErrors)" {
    source := "func main() {\n    var x = 5 + + * 3  // Multiple syntax errors\n}"
    assert PeCensus(source) == "NL103@2:17+3;"
    assert PeRow(source, 0) == "NL103@2:17+3|Prefix '+' is not supported|    var x = 5 + + * 3  // Multiple syntax errors|A leading '+' does not change the value in N#, so it is not part of the expression grammar.|Remove the leading '+'. Numeric literals and variables are already positive unless you subtract or negate them.|{Remove the leading '+'}|https://docs.n-sharp.dev/errors/NL103"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.ExprStmt(Golden.Ident("var", 2, 5), 2, 5))
    statements2.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("x", 2, 9), AssignmentOperator.Assign, Golden.Bin(Golden.IntLit("5", 2, 13), BinaryOperator.Add, Golden.Bin(Golden.Ident("<error>", 2, 17), BinaryOperator.Multiply, Golden.IntLit("3", 2, 21), 2, 19), 2, 15), 2, 11), 2, 9))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// WHAT THE GOLDEN ADDS HERE: The deleted method asserted the following `func after` exists by name. The golden pins
// everything else: the union is still named `Result`, its four cases are Success (with `value: int`
// spanning 4:16-19), TWO synthetic `<error>` cases at 6:5 and 6:6 with NULL Properties, and Failure
// (with `error: string` spanning 8:16-22). Two `@` characters, two cases, two diagnostics — one each,
// not one for the pair.
test "020 s25 error handling: a `@@` inside a union body reports TWO NL102s one column apart and synthesises TWO `<error>` union CASES, while `Success`, `Failure` and the function after the union all survive intact (was ErrorHandlingTests.Parser_RecoversFromMalformedUnionAndParsesFollowingDeclaration)" {
    source := "\nunion Result {\n    Success {\n        value: int\n    }\n    @@\n    Failure {\n        error: string\n    }\n}\n\nfunc after() {\n    print(\"ok\")\n}"
    assert PeCensus(source) == "NL102@6:5+1;NL102@6:6+1;"
    assert PeRow(source, 0) == "NL102@6:5+1|Expected union case name. Got '@'|    @@|I was expecting an identifier here, but I found '@' instead.|An identifier is a name for a variable, function, or type.|<null>|https://docs.n-sharp.dev/errors/NL102"
    assert PeRow(source, 1) == "NL102@6:6+1|Expected union case name. Got '@'|    @@|I was expecting an identifier here, but I found '@' instead.|An identifier is a name for a variable, function, or type.|<null>|https://docs.n-sharp.dev/errors/NL102"
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    cases2 := new List<UnionCase>()
    props3 := new List<UnionCaseProperty>()
    Golden.AddUProp(props3, "value", Golden.SimpleT("int", 4, 16, 19))
    Golden.AddUCaseProps(cases2, "Success", props3, 3, 5)
    Golden.AddUCaseBare(cases2, "<error>", 6, 5)
    Golden.AddUCaseBare(cases2, "<error>", 6, 6)
    props4 := new List<UnionCaseProperty>()
    Golden.AddUProp(props4, "error", Golden.SimpleT("string", 8, 16, 22))
    Golden.AddUCaseProps(cases2, "Failure", props4, 7, 5)
    declarations1.Add(Golden.UnionF("Result", null, cases2, Modifiers.None, 2, 1))
    statements5 := new List<Statement>()
    statements5.Add(Golden.Print(Golden.Paren(Golden.StrLit("\"ok\"", 13, 11), 13, 10), 13, 5))
    declarations1.Add(Golden.Func("after", Golden.NoParams(), null, Golden.Block(statements5, 12, 14), null, null, null, Modifiers.None, 12, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// THE FIRST CONTROL, AND IT IS WHAT MAKES THE UNTERMINATED-COMMENT FINDING A CAUSE RATHER THAN A
// COINCIDENCE. The same source with the comment CLOSED parses the whole file: one function, one
// print statement, and still zero diagnostics. So the empty unit above is caused by the unterminated
// `/*` and by nothing else, and the parser's silence about it is a silence about a real loss. Neither
// deleted method could compare the two, because the file had only the broken one.
test "020 s25 error handling: closing the block comment that swallowed the file recovers the WHOLE file — the only difference is the `*/`, and it is the difference between zero declarations and one" {
    source := "/* This comment now ends */\nfunc main() {\n    print(\"hello\")\n}"
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    statements2.Add(Golden.Print(Golden.Paren(Golden.StrLit("\"hello\"", 3, 11), 3, 10), 3, 5))
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// THE SECOND CONTROL, AND IT IS THE OTHER HALF OF THE NULL-BODY FINDING. `func main() ` produces a
// declaration whose Body is NULL; `func main() {}` produces one whose Body is an EMPTY BlockStatement
// at 1:13. Both parse silently, and they are DIFFERENT trees — which is the distinction a consumer
// that asks `Body != null` depends on, and which the deleted `Assert.NotNull(unit)` erased.
test "020 s25 error handling: a function with an EMPTY body is a Body that is an empty BlockStatement, not the NULL Body the body-less form produces — both silent, and distinguishable" {
    source := "func main() {}"
    assert PeCensus(source) == ""
    actual := PsAst(source)
    declarations1 := new List<Declaration>()
    statements2 := new List<Statement>()
    declarations1.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(statements2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declarations1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL PATTERN / PARAMETER-MODIFIER / OPERATOR-OVERLOAD / CONSTRUCTOR-INITIALIZER CONTRACTS
// FOR `ColumnarParserRecovery.ParseFileAst`, IN N#.
//
// These replace the third tranche of `tests/ParserTests.cs` — 46 of its remaining 139 `[Fact]`s,
// 1,397 C# lines, 345 `Assert.` occurrences — which task 020 slice 19 deletes. The tranche is the
// four NON-EXPRESSION families the slice-18 sketch left behind: patterns and `match` (23),
// parameter and argument modifiers (14, including the family's two negatives), operator and
// conversion overloads (6), and constructor initializers (3). The declaration family moved in slice
// 17 to `ColumnarParserDeclarations.tests.nl` and the statement family in slice 18 to
// `ColumnarParserStatements.tests.nl`; the four SMALL families — the file header, literals and
// interpolation, attributes and the preprocessor — moved in slice 20 to
// `ColumnarParserSmallFamilies.tests.nl`, and expressions and operator precedence are the last
// tranche of the same arc, which `tests/ParserTests.cs` survives carrying.
//
// THE SLICE-18 SKETCH PRICED THIS TRANCHE AT 47 AND THE MEASUREMENT SAYS 46. `ConstructorDeclaration`
// occurs in exactly THREE method bodies in the whole file, not four: `TestConstructorDeclaration`
// itself moved in slice 17, and the two residual methods whose NAMES carry "Constructor" or
// "Initializer" (`TestNewExpression_ObjectInitializerWithoutEmptyConstructorParens`,
// `TestTargetTypedNewWithInitializer`) assert object-initializer EXPRESSIONS and belong to the
// expression tranche. The residue arithmetic is unchanged — 60 expression methods where the sketch
// said 59 — so the split moved one method and lost none.
//
// THE ROUTE IS THE WHOLE-TREE GOLDEN, AND IT IS STRICTLY STRONGER THAN WHAT IT REPLACES.
// All 44 positive cases went through one private helper:
//
//     private static CompilationUnit Parse(string source)
//         => ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit!;
//
// followed by a handful of member reads — `varDecl!.Initializer as MatchExpression`,
// `Assert.IsType<ListPattern>(firstCase.Pattern)`. A whole-tree diff pins every node, every
// registered field and every anchor at once. That matters more here than in either earlier tranche,
// because the pattern family is where the deleted assertions were thinnest: 212 of the tranche's 345
// `Assert.` occurrences belong to it, and almost all of them state a node TYPE and nothing else.
//
// THE ANCHOR CLAIMS ARE THE MARGIN, AND THE MARGIN IS TOTAL: the tranche's 1,397 C# lines contain
// exactly THREE `.Line` and THREE `.Column` assertions, all three of them in
// `TestPropertyPatternSourceLocations` and all three about the same three property names. Every other
// position in every other fixture — every pattern anchor, every operator span, every parameter
// column — was unstated. `AstEq.Diff` and the `Golden.*` builders live in
// `ColumnarParserAst.tests.nl` next door; the registry there already covered every pattern and
// operator node type, so this slice added ZERO registry entries and five builders (the four RETURNING
// list-element forms `CaseM` / `PatPropF` / `PropInit` / `TupleElemF`, and `OpFunc` for the whole
// operator-overload flag word).
//
// THE SECOND CLAIM IN EVERY POSITIVE CONTRACT IS THAT THE SOURCE PARSES CLEANLY, AND THAT CLAIM IS
// NEW. `Parse()` above reads `.CompilationUnit` and DISCARDS `.Errors` entirely, so every positive
// case in `ParserTests.cs` is silent about whether the source it calls "valid" produces any
// diagnostic at all. Each contract below pins `PsCensus(source) == ""` first. **MEASURED RESULT FOR
// THIS TRANCHE: all 44 sources parse with an EMPTY diagnostic list** — the same verdict slices 17 and
// 18 measured over their 50 and 23, so the pin has now found no defect over 117 real-world fixtures,
// and it is kept because it is the guard that makes the silence impossible to re-introduce.
//
// THE NEGATIVE HALF IS TWO CONTRACTS, AND IT IS THE FIRST ONE THIS ARC HAS HAD. Slices 17 and 18 had
// no `AssertHasParseError` call in their tranches; this one takes two of the five. Those two asserted
// `Assert.False(result.Success)` plus `Assert.Contains(result.Errors, e => e.Message.Contains(…))` —
// satisfied by a parse that reported the message ten times, or that threw both functions away while
// recovering. The successors state the WHOLE census (one row, exact span), the WHOLE diagnostic row
// (message, snippet, explanation, hint, suggestions, docs URL) and the recovered top level.
//
// THE CENSUS IS IN RECORDING ORDER, WHICH IS THE ORDER `ParseFileAst` RETURNS AND NOT THE ORDER THE
// CLI SHOWS. `ColumnarParserRecovery.ParseFilePreamble` sorts by position; `ParseFileAst` does not.
// Each negative here reports exactly ONE diagnostic, so no ordering is observable today either — the
// convention is restated because a future contract in this file will be the first to observe it.
//
// THE HELPERS ARE REUSED, NOT RE-COPIED. `PsAst` / `PsCensus` live in
// `ColumnarParserStatements.tests.nl` and `PeParse` / `PeCensus` / `PeRow` / `PeDecls` in
// `ColumnarParserErrorRecovery.tests.nl`; both sets are public free functions in this project and
// this file calls them across the file boundary rather than adding a third copy of either census.
//
// THE SOURCES ARE THE DELETED FIXTURES BYTE-FOR-BYTE — leading newline, twelve-space indentation and
// trailing eight spaces included where the C# spelled them that way, and flush-left where it used a
// raw literal or a concatenation instead. That is why some fixtures anchor `func` at column 13 and
// others at column 1: both spellings are in the deleted file, and both are preserved. The tranche
// uses FOUR different C# literal forms — 25 verbatim `@"…"`, 9 single-line `"…"`, 11 multi-line
// `"…" + "…"` concatenations and 1 C# RAW `"""…"""` — so the byte-identity check that produced these
// literals was run with the C# COMPILER as the decoder rather than a hand-rolled literal reader,
// because a raw literal's indentation is stripped by its closing delimiter and a reader that gets
// that wrong makes the check circular.
//
// WHAT THE WHOLE-TREE PINS MEASURED THAT THE DELETED ASSERTIONS COULD NOT SEE is recorded per
// contract below and summarised in `memory/components/parser.md`.

// ---- (a) PATTERNS AND `match` — 23 contracts ----
//
// The deleted family asserted node TYPES almost exclusively: 212 `Assert.` occurrences over 23
// methods, of which the overwhelming majority are `Assert.IsType<XPattern>(…)` or a bare
// `Assert.NotNull` after an `as`. Not one of them stated where a pattern SITS, except the three
// property-name positions in `TestPropertyPatternSourceLocations`. Every anchor below is therefore a
// claim the DELETED FILE never made.
//
// THAT IS NOT THE SAME AS A CLAIM NOTHING HAD MADE, AND THE DIFFERENCE IS CHECKED RATHER THAN
// ASSUMED. `ColumnarParserAst.tests.nl`'s stage-N+1c tranches 9c and 10 already pin several of the
// same shapes over synthetic one-line sources: a `SlicePattern` anchored on the `[` rather than on
// its own `..` (`[1, .. rest]`, citing Parser.cs :3373), an implicit-binding property pattern
// (`{ N }`) that leaves `Pattern` null (:3494), a `TypePattern` whose type reference is
// `SimpleTypeReference(name, 0, 0)` (the `BareT` helper, :3444), and a two-element positional pattern
// (`(1, 2)`, :3401). What these contracts add over those is the REAL-WORLD corpus — nested three
// levels deep, mixed with guards and union cases, over the exact fixtures the C# used — and the
// shapes tranche 9c never reached: a ONE-element positional pattern (which is what a parenthesized
// pattern turns out to be), a slice in the MIDDLE of a list, and every pattern kind composed with
// every other.

test "020 s19 parser patterns: a `match` arm's LiteralPattern anchors on the literal it wraps, at the same Line/Column, and the parser leaves IsExhaustive FALSE on every MatchExpression it builds (was ParserTests.TestMatchExpression)" {
    source := "\n            func Test() {\n                result := match x {\n                    1 => \"one\",\n                    2 => \"two\"\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    mcases3 := new List<MatchCase>()
    mcases3.Add(Golden.CaseM(Golden.PLit(Golden.IntLit("1", 4, 21), 4, 21), null, Golden.StrLit("\"one\"", 4, 26)))
    mcases3.Add(Golden.CaseM(Golden.PLit(Golden.IntLit("2", 5, 21), 5, 21), null, Golden.StrLit("\"two\"", 5, 26)))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("x", 3, 33), mcases3, 3, 27), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `Result.Success { value }` keeps the DOTTED case name in one string, and its `{ value }` property leaves BOTH Pattern and BindingName null — the property's own Name is the binding (was ParserTests.TestMatchExpressionWithUnionPattern)" {
    source := "\n            func Test() {\n                msg := match result {\n                    Result.Success { value } => \"ok\",\n                    Result.Failure { error } => \"fail\"\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    mcases3 := new List<MatchCase>()
    patprops4 := new List<PropertyPattern>()
    patprops4.Add(Golden.PatPropF("value", null, null, 4, 38))
    mcases3.Add(Golden.CaseM(Golden.PUnion("Result.Success", patprops4, 4, 21), null, Golden.StrLit("\"ok\"", 4, 49)))
    patprops5 := new List<PropertyPattern>()
    patprops5.Add(Golden.PatPropF("error", null, null, 5, 38))
    mcases3.Add(Golden.CaseM(Golden.PUnion("Result.Failure", patprops5, 5, 21), null, Golden.StrLit("\"fail\"", 5, 49)))
    stmts2.Add(Golden.VarDecl("msg", null, Golden.Match(Golden.Ident("result", 3, 30), mcases3, 3, 24), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `n when n > 0` binds an IdentifierPattern and hangs the guard off the CASE, not off the pattern; the wildcard arm is an IdentifierPattern literally named `_` (was ParserTests.TestMatchExpressionWithGuard)" {
    source := "\n            func Test() {\n                result := match x {\n                    n when n > 0 => \"positive\",\n                    n when n < 0 => \"negative\",\n                    _ => \"zero\"\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    mcases3 := new List<MatchCase>()
    mcases3.Add(Golden.CaseM(Golden.PIdent("n", 4, 21), Golden.Bin(Golden.Ident("n", 4, 28), BinaryOperator.Greater, Golden.IntLit("0", 4, 32), 4, 30), Golden.StrLit("\"positive\"", 4, 37)))
    mcases3.Add(Golden.CaseM(Golden.PIdent("n", 5, 21), Golden.Bin(Golden.Ident("n", 5, 28), BinaryOperator.Less, Golden.IntLit("0", 5, 32), 5, 30), Golden.StrLit("\"negative\"", 5, 37)))
    mcases3.Add(Golden.CaseM(Golden.PIdent("_", 6, 21), null, Golden.StrLit("\"zero\"", 6, 26)))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("x", 3, 33), mcases3, 3, 27), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a guarded and an unguarded arm over the SAME union case differ only in MatchCase.Guard — every other field, anchors included, is identical (was ParserTests.TestMatchExpressionWithUnionPatternAndGuard)" {
    source := "\n            func Test() {\n                msg := match result {\n                    Result.Success { value } when value > 10 => \"big success\",\n                    Result.Success { value } => \"small success\",\n                    Result.Failure { error } => \"fail\"\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    mcases3 := new List<MatchCase>()
    patprops4 := new List<PropertyPattern>()
    patprops4.Add(Golden.PatPropF("value", null, null, 4, 38))
    mcases3.Add(Golden.CaseM(Golden.PUnion("Result.Success", patprops4, 4, 21), Golden.Bin(Golden.Ident("value", 4, 51), BinaryOperator.Greater, Golden.IntLit("10", 4, 59), 4, 57), Golden.StrLit("\"big success\"", 4, 65)))
    patprops5 := new List<PropertyPattern>()
    patprops5.Add(Golden.PatPropF("value", null, null, 5, 38))
    mcases3.Add(Golden.CaseM(Golden.PUnion("Result.Success", patprops5, 5, 21), null, Golden.StrLit("\"small success\"", 5, 49)))
    patprops6 := new List<PropertyPattern>()
    patprops6.Add(Golden.PatPropF("error", null, null, 6, 38))
    mcases3.Add(Golden.CaseM(Golden.PUnion("Result.Failure", patprops6, 6, 21), null, Golden.StrLit("\"fail\"", 6, 49)))
    stmts2.Add(Golden.VarDecl("msg", null, Golden.Match(Golden.Ident("result", 3, 30), mcases3, 3, 24), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `< 13` anchors the RelationalPattern on the OPERATOR and keeps the operator as a string, with the literal one column further on (was ParserTests.TestRelationalPattern)" {
    source := "func classify(age: int): string {\n    result := match age {\n        < 13 => \"child\",\n        >= 65 => \"senior\",\n        _ => \"adult\"\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("age", Golden.SimpleT("int", 1, 20, 23), null, false, ParameterModifier.None, 1, 15))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    mcases4.Add(Golden.CaseM(Golden.PRel("<", Golden.IntLit("13", 3, 11), 3, 9), null, Golden.StrLit("\"child\"", 3, 17)))
    mcases4.Add(Golden.CaseM(Golden.PRel(">=", Golden.IntLit("65", 4, 12), 4, 9), null, Golden.StrLit("\"senior\"", 4, 18)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 5, 9), null, Golden.StrLit("\"adult\"", 5, 14)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("age", 2, 21), mcases4, 2, 15), VariableKind.Let, 2, 5))
    stmts3.Add(Golden.Return(Golden.Ident("result", 7, 12), 7, 5))
    decls1.Add(Golden.Func("classify", params2, Golden.SimpleT("string", 1, 26, 32), Golden.Block(stmts3, 1, 33), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `> 0 and < 100` anchors the AndPattern on the `and` keyword, between its two operands rather than at the start of the pattern (was ParserTests.TestAndPattern)" {
    source := "\n            func check(x: int): bool {\n                result := match x {\n                    > 0 and < 100 => true,\n                    _ => false\n                }\n                return result\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("x", Golden.SimpleT("int", 2, 27, 30), null, false, ParameterModifier.None, 2, 24))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    mcases4.Add(Golden.CaseM(Golden.PAnd(Golden.PRel(">", Golden.IntLit("0", 4, 23), 4, 21), Golden.PRel("<", Golden.IntLit("100", 4, 31), 4, 29), 4, 25), null, Golden.BoolLit(true, 4, 38)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 5, 21), null, Golden.BoolLit(false, 5, 26)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("x", 3, 33), mcases4, 3, 27), VariableKind.Let, 3, 17))
    stmts3.Add(Golden.Return(Golden.Ident("result", 7, 24), 7, 17))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("bool", 2, 33, 37), Golden.Block(stmts3, 2, 38), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `< 0 or > 100` anchors the OrPattern on the `or` keyword, the same between-the-operands rule the AndPattern follows (was ParserTests.TestOrPattern)" {
    source := "\n            func check(x: int): bool {\n                result := match x {\n                    < 0 or > 100 => true,\n                    _ => false\n                }\n                return result\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("x", Golden.SimpleT("int", 2, 27, 30), null, false, ParameterModifier.None, 2, 24))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    mcases4.Add(Golden.CaseM(Golden.POr(Golden.PRel("<", Golden.IntLit("0", 4, 23), 4, 21), Golden.PRel(">", Golden.IntLit("100", 4, 30), 4, 28), 4, 25), null, Golden.BoolLit(true, 4, 37)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 5, 21), null, Golden.BoolLit(false, 5, 26)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("x", 3, 33), mcases4, 3, 27), VariableKind.Let, 3, 17))
    stmts3.Add(Golden.Return(Golden.Ident("result", 7, 24), 7, 17))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("bool", 2, 33, 37), Golden.Block(stmts3, 2, 38), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `not 0` anchors the NotPattern on `not` and its operand on the literal, so the two nodes have different columns on one line (was ParserTests.TestNotPattern)" {
    source := "\n            func check(x: int): bool {\n                result := match x {\n                    not 0 => true,\n                    _ => false\n                }\n                return result\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("x", Golden.SimpleT("int", 2, 27, 30), null, false, ParameterModifier.None, 2, 24))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    mcases4.Add(Golden.CaseM(Golden.PNot(Golden.PLit(Golden.IntLit("0", 4, 25), 4, 25), 4, 21), null, Golden.BoolLit(true, 4, 30)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 5, 21), null, Golden.BoolLit(false, 5, 26)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("x", 3, 33), mcases4, 3, 27), VariableKind.Let, 3, 17))
    stmts3.Add(Golden.Return(Golden.Ident("result", 7, 24), 7, 17))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("bool", 2, 33, 37), Golden.Block(stmts3, 2, 38), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a positional arm is a PositionalPattern anchored on its `(`, whose elements interleave LiteralPattern and the `_` IdentifierPattern in source order (was ParserTests.TestPositionalPattern)" {
    source := "func check(point: (int, int)): string {\n    result := match point {\n        (0, 0) => \"origin\",\n        (0, _) => \"y-axis\",\n        (_, 0) => \"x-axis\",\n        _ => \"other\"\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    ttelems3 := new List<TupleTypeElement>()
    ttelems3.Add(Golden.TupleElem(Golden.SimpleT("int", 1, 20, 23), null))
    ttelems3.Add(Golden.TupleElem(Golden.SimpleT("int", 1, 25, 28), null))
    params2.Add(Golden.Param("point", Golden.TupleT(ttelems3, 1, 19, 29), null, false, ParameterModifier.None, 1, 12))
    stmts4 := new List<Statement>()
    mcases5 := new List<MatchCase>()
    pats6 := new List<Pattern>()
    pats6.Add(Golden.PLit(Golden.IntLit("0", 3, 10), 3, 10))
    pats6.Add(Golden.PLit(Golden.IntLit("0", 3, 13), 3, 13))
    mcases5.Add(Golden.CaseM(Golden.PPos(pats6, 3, 9), null, Golden.StrLit("\"origin\"", 3, 19)))
    pats7 := new List<Pattern>()
    pats7.Add(Golden.PLit(Golden.IntLit("0", 4, 10), 4, 10))
    pats7.Add(Golden.PIdent("_", 4, 13))
    mcases5.Add(Golden.CaseM(Golden.PPos(pats7, 4, 9), null, Golden.StrLit("\"y-axis\"", 4, 19)))
    pats8 := new List<Pattern>()
    pats8.Add(Golden.PIdent("_", 5, 10))
    pats8.Add(Golden.PLit(Golden.IntLit("0", 5, 13), 5, 13))
    mcases5.Add(Golden.CaseM(Golden.PPos(pats8, 5, 9), null, Golden.StrLit("\"x-axis\"", 5, 19)))
    mcases5.Add(Golden.CaseM(Golden.PIdent("_", 6, 9), null, Golden.StrLit("\"other\"", 6, 14)))
    stmts4.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("point", 2, 21), mcases5, 2, 15), VariableKind.Let, 2, 5))
    stmts4.Add(Golden.Return(Golden.Ident("result", 8, 12), 8, 5))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("string", 1, 32, 38), Golden.Block(stmts4, 1, 39), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `[]` is a ListPattern with an EMPTY element list, not a null one (was ParserTests.TestListPatternEmpty)" {
    source := "func check(arr: int[]): bool {\n    result := match arr {\n        [] => true,\n        _ => false\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("arr", Golden.ArrayT(Golden.SimpleT("int", 1, 17, 20), 1, 17, 22), null, false, ParameterModifier.None, 1, 12))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    mcases4.Add(Golden.CaseM(Golden.PList(Golden.NoPatterns(), 3, 9), null, Golden.BoolLit(true, 3, 15)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 4, 9), null, Golden.BoolLit(false, 4, 14)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("arr", 2, 21), mcases4, 2, 15), VariableKind.Let, 2, 5))
    stmts3.Add(Golden.Return(Golden.Ident("result", 6, 12), 6, 5))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("bool", 1, 25, 29), Golden.Block(stmts3, 1, 30), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `[1, 2, 3]` gives three LiteralPatterns, each anchored on its own literal, inside one ListPattern anchored on the `[` (was ParserTests.TestListPatternLiteral)" {
    source := "func check(arr: int[]): bool {\n    result := match arr {\n        [1, 2, 3] => true,\n        _ => false\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("arr", Golden.ArrayT(Golden.SimpleT("int", 1, 17, 20), 1, 17, 22), null, false, ParameterModifier.None, 1, 12))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    pats5 := new List<Pattern>()
    pats5.Add(Golden.PLit(Golden.IntLit("1", 3, 10), 3, 10))
    pats5.Add(Golden.PLit(Golden.IntLit("2", 3, 13), 3, 13))
    pats5.Add(Golden.PLit(Golden.IntLit("3", 3, 16), 3, 16))
    mcases4.Add(Golden.CaseM(Golden.PList(pats5, 3, 9), null, Golden.BoolLit(true, 3, 22)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 4, 9), null, Golden.BoolLit(false, 4, 14)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("arr", 2, 21), mcases4, 2, 15), VariableKind.Let, 2, 5))
    stmts3.Add(Golden.Return(Golden.Ident("result", 6, 12), 6, 5))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("bool", 1, 25, 29), Golden.Block(stmts3, 1, 30), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a bare `..` is a SlicePattern with a NULL BindingName that inherits the LIST's anchor rather than carrying the `..`'s own (was ParserTests.TestListPatternWithSlice)" {
    source := "func check(arr: int[]): int {\n    result := match arr {\n        [first, ..] => first,\n        _ => 0\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("arr", Golden.ArrayT(Golden.SimpleT("int", 1, 17, 20), 1, 17, 22), null, false, ParameterModifier.None, 1, 12))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    pats5 := new List<Pattern>()
    pats5.Add(Golden.PIdent("first", 3, 10))
    pats5.Add(Golden.PSlice(null, 3, 9))
    mcases4.Add(Golden.CaseM(Golden.PList(pats5, 3, 9), null, Golden.Ident("first", 3, 24)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 4, 9), null, Golden.IntLit("0", 4, 14)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("arr", 2, 21), mcases4, 2, 15), VariableKind.Let, 2, 5))
    stmts3.Add(Golden.Return(Golden.Ident("result", 6, 12), 6, 5))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("int", 1, 25, 28), Golden.Block(stmts3, 1, 29), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `.. rest` names the slice but keeps the list's anchor, and the `_ => []` arm materializes an EMPTY ArrayLiteralExpression (was ParserTests.TestListPatternWithNamedSlice)" {
    source := "func check(arr: int[]): int[] {\n    result := match arr {\n        [first, .. rest] => rest,\n        _ => []\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("arr", Golden.ArrayT(Golden.SimpleT("int", 1, 17, 20), 1, 17, 22), null, false, ParameterModifier.None, 1, 12))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    pats5 := new List<Pattern>()
    pats5.Add(Golden.PIdent("first", 3, 10))
    pats5.Add(Golden.PSlice("rest", 3, 9))
    mcases4.Add(Golden.CaseM(Golden.PList(pats5, 3, 9), null, Golden.Ident("rest", 3, 29)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 4, 9), null, Golden.ArrayLit(Golden.NoExprs(), false, 4, 14)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("arr", 2, 21), mcases4, 2, 15), VariableKind.Let, 2, 5))
    stmts3.Add(Golden.Return(Golden.Ident("result", 6, 12), 6, 5))
    decls1.Add(Golden.Func("check", params2, Golden.ArrayT(Golden.SimpleT("int", 1, 25, 28), 1, 25, 30), Golden.Block(stmts3, 1, 31), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a slice in the MIDDLE keeps the list's anchor while the elements on either side keep their own, so three of the four positions on that line differ (was ParserTests.TestListPatternWithMiddleSlice)" {
    source := "func check(arr: int[]): (int, int) {\n    result := match arr {\n        [first, .. middle, last] => (first, last),\n        _ => (0, 0)\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("arr", Golden.ArrayT(Golden.SimpleT("int", 1, 17, 20), 1, 17, 22), null, false, ParameterModifier.None, 1, 12))
    ttelems3 := new List<TupleTypeElement>()
    ttelems3.Add(Golden.TupleElem(Golden.SimpleT("int", 1, 26, 29), null))
    ttelems3.Add(Golden.TupleElem(Golden.SimpleT("int", 1, 31, 34), null))
    stmts4 := new List<Statement>()
    mcases5 := new List<MatchCase>()
    pats6 := new List<Pattern>()
    pats6.Add(Golden.PIdent("first", 3, 10))
    pats6.Add(Golden.PSlice("middle", 3, 9))
    pats6.Add(Golden.PIdent("last", 3, 28))
    telems7 := new List<TupleElement>()
    telems7.Add(Golden.TupleElemF(null, Golden.Ident("first", 3, 38)))
    telems7.Add(Golden.TupleElemF(null, Golden.Ident("last", 3, 45)))
    mcases5.Add(Golden.CaseM(Golden.PList(pats6, 3, 9), null, Golden.Tuple(telems7, 3, 37)))
    telems8 := new List<TupleElement>()
    telems8.Add(Golden.TupleElemF(null, Golden.IntLit("0", 4, 15)))
    telems8.Add(Golden.TupleElemF(null, Golden.IntLit("0", 4, 18)))
    mcases5.Add(Golden.CaseM(Golden.PIdent("_", 4, 9), null, Golden.Tuple(telems8, 4, 14)))
    stmts4.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("arr", 2, 21), mcases5, 2, 15), VariableKind.Let, 2, 5))
    stmts4.Add(Golden.Return(Golden.Ident("result", 6, 12), 6, 5))
    decls1.Add(Golden.Func("check", params2, Golden.TupleT(ttelems3, 1, 25, 35), Golden.Block(stmts4, 1, 36), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a PARENTHESIZED pattern is a one-element PositionalPattern — there is no parenthesized-pattern node — so `(> 0 and < 10) or (…)` nests PAnd inside PPos inside POr (was ParserTests.TestComplexCombinedPatterns)" {
    source := "func check(value: int): string {\n    result := match value {\n        (> 0 and < 10) or (> 90 and < 100) => \"valid\",\n        not (>= 50 and <= 60) => \"not middle\",\n        _ => \"other\"\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("value", Golden.SimpleT("int", 1, 19, 22), null, false, ParameterModifier.None, 1, 12))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    pats5 := new List<Pattern>()
    pats5.Add(Golden.PAnd(Golden.PRel(">", Golden.IntLit("0", 3, 12), 3, 10), Golden.PRel("<", Golden.IntLit("10", 3, 20), 3, 18), 3, 14))
    pats6 := new List<Pattern>()
    pats6.Add(Golden.PAnd(Golden.PRel(">", Golden.IntLit("90", 3, 30), 3, 28), Golden.PRel("<", Golden.IntLit("100", 3, 39), 3, 37), 3, 33))
    mcases4.Add(Golden.CaseM(Golden.POr(Golden.PPos(pats5, 3, 9), Golden.PPos(pats6, 3, 27), 3, 24), null, Golden.StrLit("\"valid\"", 3, 47)))
    pats7 := new List<Pattern>()
    pats7.Add(Golden.PAnd(Golden.PRel(">=", Golden.IntLit("50", 4, 17), 4, 14), Golden.PRel("<=", Golden.IntLit("60", 4, 27), 4, 24), 4, 20))
    mcases4.Add(Golden.CaseM(Golden.PNot(Golden.PPos(pats7, 4, 13), 4, 9), null, Golden.StrLit("\"not middle\"", 4, 34)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 5, 9), null, Golden.StrLit("\"other\"", 5, 14)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("value", 2, 21), mcases4, 2, 15), VariableKind.Let, 2, 5))
    stmts3.Add(Golden.Return(Golden.Ident("result", 7, 12), 7, 5))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("string", 1, 25, 31), Golden.Block(stmts3, 1, 32), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a TypePattern's TYPE REFERENCE carries NO position at all: Line 0, Column 0 and a zero-length span, while the pattern itself anchors on the type name (was ParserTests.TestTypePatternSimple)" {
    source := "func check(obj: object): string {\n    result := match obj {\n        string s => s,\n        int n => n.ToString(),\n        _ => \"unknown\"\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("obj", Golden.SimpleT("object", 1, 17, 23), null, false, ParameterModifier.None, 1, 12))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    mcases4.Add(Golden.CaseM(Golden.PType(Golden.SimpleT("string", 0, 0, 0), "s", 3, 9), null, Golden.Ident("s", 3, 21)))
    mcases4.Add(Golden.CaseM(Golden.PType(Golden.SimpleT("int", 0, 0, 0), "n", 4, 9), null, Golden.Call(Golden.Member(Golden.Ident("n", 4, 18), "ToString", false, 4, 19), Golden.NoArgs(), Golden.NoTypeArgs(), 4, 28)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 5, 9), null, Golden.StrLit("\"unknown\"", 5, 14)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("obj", 2, 21), mcases4, 2, 15), VariableKind.Let, 2, 5))
    stmts3.Add(Golden.Return(Golden.Ident("result", 7, 12), 7, 5))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("string", 1, 26, 32), Golden.Block(stmts3, 1, 33), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `System.String s` keeps the qualified name in ONE SimpleTypeReference — still at Line 0, Column 0 — rather than splitting it into a member access (was ParserTests.TestTypePatternWithQualifiedName)" {
    source := "func check(obj: object): string {\n    result := match obj {\n        System.String s => s,\n        _ => \"unknown\"\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("obj", Golden.SimpleT("object", 1, 17, 23), null, false, ParameterModifier.None, 1, 12))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    mcases4.Add(Golden.CaseM(Golden.PType(Golden.SimpleT("System.String", 0, 0, 0), "s", 3, 9), null, Golden.Ident("s", 3, 28)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 4, 9), null, Golden.StrLit("\"unknown\"", 4, 14)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("obj", 2, 21), mcases4, 2, 15), VariableKind.Let, 2, 5))
    stmts3.Add(Golden.Return(Golden.Ident("result", 6, 12), 6, 5))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("string", 1, 26, 32), Golden.Block(stmts3, 1, 33), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: two arms binding the SAME name over the same type differ only in Guard, and the guarded one's guard is a whole binary expression over a member access (was ParserTests.TestTypePatternWithGuard)" {
    source := "func check(obj: object): string {\n    result := match obj {\n        string s when s.Length > 5 => \"long\",\n        string s => \"short\",\n        _ => \"not string\"\n    }\n    return result\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("obj", Golden.SimpleT("object", 1, 17, 23), null, false, ParameterModifier.None, 1, 12))
    stmts3 := new List<Statement>()
    mcases4 := new List<MatchCase>()
    mcases4.Add(Golden.CaseM(Golden.PType(Golden.SimpleT("string", 0, 0, 0), "s", 3, 9), Golden.Bin(Golden.Member(Golden.Ident("s", 3, 23), "Length", false, 3, 24), BinaryOperator.Greater, Golden.IntLit("5", 3, 34), 3, 32), Golden.StrLit("\"long\"", 3, 39)))
    mcases4.Add(Golden.CaseM(Golden.PType(Golden.SimpleT("string", 0, 0, 0), "s", 4, 9), null, Golden.StrLit("\"short\"", 4, 21)))
    mcases4.Add(Golden.CaseM(Golden.PIdent("_", 5, 9), null, Golden.StrLit("\"not string\"", 5, 14)))
    stmts3.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("obj", 2, 21), mcases4, 2, 15), VariableKind.Let, 2, 5))
    stmts3.Add(Golden.Return(Golden.Ident("result", 7, 12), 7, 5))
    decls1.Add(Golden.Func("check", params2, Golden.SimpleT("string", 1, 26, 32), Golden.Block(stmts3, 1, 33), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `{ Address: { City: \"NYC\" } }` nests ObjectPattern inside PropertyPattern inside ObjectPattern, each anchored on its own `{` or property NAME (was ParserTests.TestNestedPropertyPatternWithLiteral)" {
    source := "\n            func Test() {\n                result := match person {\n                    { Address: { City: \"NYC\" } } => \"New Yorker\"\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    mcases3 := new List<MatchCase>()
    patprops4 := new List<PropertyPattern>()
    patprops5 := new List<PropertyPattern>()
    patprops5.Add(Golden.PatPropF("City", Golden.PLit(Golden.StrLit("\"NYC\"", 4, 40), 4, 40), null, 4, 34))
    patprops4.Add(Golden.PatPropF("Address", Golden.PObj(patprops5, 4, 32), null, 4, 23))
    mcases3.Add(Golden.CaseM(Golden.PObj(patprops4, 4, 21), null, Golden.StrLit("\"New Yorker\"", 4, 53)))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("person", 3, 33), mcases3, 3, 27), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a binding property (`City: city`) and a literal property (`State: \"NY\"`) are the same PropertyPattern shape — the difference is entirely in the child Pattern (was ParserTests.TestNestedPropertyPatternWithBinding)" {
    source := "\n            func Test() {\n                result := match person {\n                    { Address: { City: city, State: \"NY\" } } => city\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    mcases3 := new List<MatchCase>()
    patprops4 := new List<PropertyPattern>()
    patprops5 := new List<PropertyPattern>()
    patprops5.Add(Golden.PatPropF("City", Golden.PIdent("city", 4, 40), null, 4, 34))
    patprops5.Add(Golden.PatPropF("State", Golden.PLit(Golden.StrLit("\"NY\"", 4, 53), 4, 53), null, 4, 46))
    patprops4.Add(Golden.PatPropF("Address", Golden.PObj(patprops5, 4, 32), null, 4, 23))
    mcases3.Add(Golden.CaseM(Golden.PObj(patprops4, 4, 21), null, Golden.Ident("city", 4, 65)))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("person", 3, 33), mcases3, 3, 27), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: the un-indented spelling of the same tree, whose three property anchors (3:11, 3:22, 3:34) are the only positions the deleted file ever stated (was ParserTests.TestPropertyPatternSourceLocations)" {
    source := "func Test() {\n    result := match person {\n        { Address: { City: city, State: \"NY\" } } => city\n    }\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    mcases3 := new List<MatchCase>()
    patprops4 := new List<PropertyPattern>()
    patprops5 := new List<PropertyPattern>()
    patprops5.Add(Golden.PatPropF("City", Golden.PIdent("city", 3, 28), null, 3, 22))
    patprops5.Add(Golden.PatPropF("State", Golden.PLit(Golden.StrLit("\"NY\"", 3, 41), 3, 41), null, 3, 34))
    patprops4.Add(Golden.PatPropF("Address", Golden.PObj(patprops5, 3, 20), null, 3, 11))
    mcases3.Add(Golden.CaseM(Golden.PObj(patprops4, 3, 9), null, Golden.Ident("city", 3, 53)))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("person", 2, 21), mcases3, 2, 15), VariableKind.Let, 2, 5))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: three levels of `{ … }` nest without flattening, and every level's ObjectPattern anchors on its own brace (was ParserTests.TestThreeLevelNestedPropertyPattern)" {
    source := "\n            func Test() {\n                result := match company {\n                    { HQ: { Address: { City: \"NYC\" } } } => \"NYC HQ\"\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    mcases3 := new List<MatchCase>()
    patprops4 := new List<PropertyPattern>()
    patprops5 := new List<PropertyPattern>()
    patprops6 := new List<PropertyPattern>()
    patprops6.Add(Golden.PatPropF("City", Golden.PLit(Golden.StrLit("\"NYC\"", 4, 46), 4, 46), null, 4, 40))
    patprops5.Add(Golden.PatPropF("Address", Golden.PObj(patprops6, 4, 38), null, 4, 29))
    patprops4.Add(Golden.PatPropF("HQ", Golden.PObj(patprops5, 4, 27), null, 4, 23))
    mcases3.Add(Golden.CaseM(Golden.PObj(patprops4, 4, 21), null, Golden.StrLit("\"NYC HQ\"", 4, 61)))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("company", 3, 33), mcases3, 3, 27), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a union case's property list carries a full ObjectPattern, so `Result.Success { value: { Count: count } }` mixes both pattern families in one arm (was ParserTests.TestUnionCaseWithNestedPropertyPattern)" {
    source := "\n            func Test() {\n                result := match result {\n                    Result.Success { value: { Count: count } } => count,\n                    _ => 0\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    mcases3 := new List<MatchCase>()
    patprops4 := new List<PropertyPattern>()
    patprops5 := new List<PropertyPattern>()
    patprops5.Add(Golden.PatPropF("Count", Golden.PIdent("count", 4, 54), null, 4, 47))
    patprops4.Add(Golden.PatPropF("value", Golden.PObj(patprops5, 4, 45), null, 4, 38))
    mcases3.Add(Golden.CaseM(Golden.PUnion("Result.Success", patprops4, 4, 21), null, Golden.Ident("count", 4, 67)))
    mcases3.Add(Golden.CaseM(Golden.PIdent("_", 5, 21), null, Golden.IntLit("0", 5, 26)))
    stmts2.Add(Golden.VarDecl("result", null, Golden.Match(Golden.Ident("result", 3, 33), mcases3, 3, 27), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- (b) PARAMETER AND ARGUMENT MODIFIERS — 12 positive contracts ----
//
// THE ONE FACT THIS FAMILY TURNS ON, AND IT IS NOT WHAT THE TESTS SUGGEST: a modified parameter
// anchors on its NAME, not on its modifier keyword. `ref a: int` puts the Parameter at the column
// where `a` starts, exactly where an unmodified `a: int` in the same position would sit, and the
// `ref` / `out` / `params` keyword leaves NO trace in the node beyond the `Modifier` field itself.
// An `Argument` goes further and carries no position at all — its three registered fields are
// `Name`, `Value` and `Modifier`.
//
// THE PARAMETER HALF OF THAT IS ALREADY PINNED NEXT DOOR AND IS RESTATED HERE RATHER THAN CLAIMED:
// `ColumnarParserAst.tests.nl`'s tranche 10 pins `func f(ref a: int, out b: int)` with the parameters
// at columns 12 and 24 — the names — and `func f(params xs: int[], …)` at column 15. What is added
// here is the seven-way `params` matrix over the REAL type shapes the C# used (array, `ReadOnlySpan`,
// `Span`, `IEnumerable`, `List`, `IReadOnlyList`) and the whole ARGUMENT half, whose `Modifier` and
// `Name` fields have no synthetic-corpus contract at all.

test "020 s19 parser patterns: a `ref` parameter anchors on its NAME, not on the `ref` keyword — the modifier leaves NO trace in the position, so only Parameter.Modifier tells `ref a` from `a` (was ParserTests.TestRefParameter)" {
    source := "func Swap(ref a: int, ref b: int) { }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("a", Golden.SimpleT("int", 1, 18, 21), null, false, ParameterModifier.Ref, 1, 15))
    params2.Add(Golden.Param("b", Golden.SimpleT("int", 1, 30, 33), null, false, ParameterModifier.Ref, 1, 27))
    decls1.Add(Golden.Func("Swap", params2, null, Golden.Block(Golden.NoStmts(), 1, 35), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: an `out` parameter and its unmodified neighbour are the SAME node shape at the same kind of anchor — its column is where `result` starts, not where `out` does (was ParserTests.TestOutParameter)" {
    source := "func TryParse(input: string, out result: int): bool { }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("input", Golden.SimpleT("string", 1, 22, 28), null, false, ParameterModifier.None, 1, 15))
    params2.Add(Golden.Param("result", Golden.SimpleT("int", 1, 42, 45), null, false, ParameterModifier.Out, 1, 34))
    decls1.Add(Golden.Func("TryParse", params2, Golden.SimpleT("bool", 1, 48, 52), Golden.Block(Golden.NoStmts(), 1, 53), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `params numbers: int[]` pairs ParameterModifier.Params with an ArrayTypeReference, and again anchors on `numbers` rather than on `params` (was ParserTests.TestParamsParameter)" {
    source := "func Sum(params numbers: int[]) { }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("numbers", Golden.ArrayT(Golden.SimpleT("int", 1, 26, 29), 1, 26, 31), null, false, ParameterModifier.Params, 1, 17))
    decls1.Add(Golden.Func("Sum", params2, null, Golden.Block(Golden.NoStmts(), 1, 33), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a `params` parameter after an ordinary one keeps both modifiers distinct on the same list (was ParserTests.TestParamsWithOtherParameters)" {
    source := "func Format(format: string, params args: object[]) { }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("format", Golden.SimpleT("string", 1, 21, 27), null, false, ParameterModifier.None, 1, 13))
    params2.Add(Golden.Param("args", Golden.ArrayT(Golden.SimpleT("object", 1, 42, 48), 1, 42, 50), null, false, ParameterModifier.Params, 1, 36))
    decls1.Add(Golden.Func("Format", params2, null, Golden.Block(Golden.NoStmts(), 1, 52), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `params items: ReadOnlySpan<int>` keeps the GenericTypeReference whole, with its own span covering the closing `>` (was ParserTests.TestParamsWithReadOnlySpan)" {
    source := "func Process(params items: ReadOnlySpan<int>) { }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    typerefs3 := new List<TypeReference>()
    typerefs3.Add(Golden.SimpleT("int", 1, 41, 44))
    params2.Add(Golden.Param("items", Golden.GenericT("ReadOnlySpan", typerefs3, 1, 28, 45), null, false, ParameterModifier.Params, 1, 21))
    decls1.Add(Golden.Func("Process", params2, null, Golden.Block(Golden.NoStmts(), 1, 47), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `params items: Span<string>` is the same shape with a different element type — the parser does not special-case the span types (was ParserTests.TestParamsWithSpan)" {
    source := "func Process(params items: Span<string>) { }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    typerefs3 := new List<TypeReference>()
    typerefs3.Add(Golden.SimpleT("string", 1, 33, 39))
    params2.Add(Golden.Param("items", Golden.GenericT("Span", typerefs3, 1, 28, 40), null, false, ParameterModifier.Params, 1, 21))
    decls1.Add(Golden.Func("Process", params2, null, Golden.Block(Golden.NoStmts(), 1, 42), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a `params IEnumerable<int>` function with an expression-carrying body proves the modifier does not disturb the body's own anchors (was ParserTests.TestParamsWithIEnumerable)" {
    source := "func Sum(params numbers: IEnumerable<int>): int { return 0 }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    typerefs3 := new List<TypeReference>()
    typerefs3.Add(Golden.SimpleT("int", 1, 38, 41))
    params2.Add(Golden.Param("numbers", Golden.GenericT("IEnumerable", typerefs3, 1, 26, 42), null, false, ParameterModifier.Params, 1, 17))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.Return(Golden.IntLit("0", 1, 58), 1, 51))
    decls1.Add(Golden.Func("Sum", params2, Golden.SimpleT("int", 1, 45, 48), Golden.Block(stmts4, 1, 49), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `params items: List<string>` — a plain BCL generic in params position (was ParserTests.TestParamsWithList)" {
    source := "func Process(params items: List<string>) { }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    typerefs3 := new List<TypeReference>()
    typerefs3.Add(Golden.SimpleT("string", 1, 33, 39))
    params2.Add(Golden.Param("items", Golden.GenericT("List", typerefs3, 1, 28, 40), null, false, ParameterModifier.Params, 1, 21))
    decls1.Add(Golden.Func("Process", params2, null, Golden.Block(Golden.NoStmts(), 1, 42), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `params items: IReadOnlyList<int>` — the interface spelling, same shape again (was ParserTests.TestParamsWithIReadOnlyList)" {
    source := "func Process(params items: IReadOnlyList<int>) { }"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    typerefs3 := new List<TypeReference>()
    typerefs3.Add(Golden.SimpleT("int", 1, 42, 45))
    params2.Add(Golden.Param("items", Golden.GenericT("IReadOnlyList", typerefs3, 1, 28, 46), null, false, ParameterModifier.Params, 1, 21))
    decls1.Add(Golden.Func("Process", params2, null, Golden.Block(Golden.NoStmts(), 1, 48), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `Swap(ref x, ref x)` sets Argument.Modifier on both arguments, and an Argument carries NO Line/Column of its own at all (was ParserTests.TestRefArgument)" {
    source := "\n            func Main() {\n                x := 5\n                Swap(ref x, ref x)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("x", null, Golden.IntLit("5", 3, 22), VariableKind.Let, 3, 17))
    args3 := new List<Argument>()
    args3.Add(Golden.ArgF(null, Golden.Ident("x", 4, 26), ArgumentModifier.Ref))
    args3.Add(Golden.ArgF(null, Golden.Ident("x", 4, 33), ArgumentModifier.Ref))
    stmts2.Add(Golden.ExprStmt(Golden.Call(Golden.Ident("Swap", 4, 17), args3, Golden.NoTypeArgs(), 4, 21), 4, 17))
    decls1.Add(Golden.Func("Main", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `out result` sets ArgumentModifier.Out on the SECOND argument only, and the preceding `let result: int` is a declaration with a null Initializer (was ParserTests.TestOutArgument)" {
    source := "\n            func Main() {\n                let result: int\n                success := int.TryParse(\"123\", out result)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("result", Golden.SimpleT("int", 3, 29, 32), null, VariableKind.Let, 3, 21))
    args3 := new List<Argument>()
    args3.Add(Golden.ArgF(null, Golden.StrLit("\"123\"", 4, 41), ArgumentModifier.None))
    args3.Add(Golden.ArgF(null, Golden.Ident("result", 4, 52), ArgumentModifier.Out))
    stmts2.Add(Golden.VarDecl("success", null, Golden.Call(Golden.Member(Golden.Ident("int", 4, 28), "TryParse", false, 4, 31), args3, Golden.NoTypeArgs(), 4, 40), VariableKind.Let, 4, 17))
    decls1.Add(Golden.Func("Main", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `CreateUser(name: \"John\", age: 30)` puts the label in Argument.Name and leaves Modifier at None — the two non-Value fields of the same node (was ParserTests.TestNamedArguments)" {
    source := "\n            func Test() {\n                CreateUser(name: \"John\", age: 30)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    args3 := new List<Argument>()
    args3.Add(Golden.ArgF("name", Golden.StrLit("\"John\"", 3, 34), ArgumentModifier.None))
    args3.Add(Golden.ArgF("age", Golden.IntLit("30", 3, 47), ArgumentModifier.None))
    stmts2.Add(Golden.ExprStmt(Golden.Call(Golden.Ident("CreateUser", 3, 17), args3, Golden.NoTypeArgs(), 3, 27), 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- (b, continued) THE NEGATIVE HALF — the two inline-`out` refusals ----
//
// `AssertHasParseError(source, message)` asserted `!Success` plus `Errors.Any(e =>
// e.Message.Contains(message))`. Both successors state the whole census instead — ONE diagnostic,
// exact span — the whole row, and the recovered top level, which is where the real finding is: the
// refusal costs NOTHING. Both functions come back with their bodies intact.

test "020 s19 parser patterns: `out var num` is refused ONCE, at the inline declaration rather than at the `out`, and BOTH functions survive recovery with their bodies intact (was ParserTests.TestInlineOutVarDeclarationReportsParseError)" {
    source := "\n            func TryParse(input: string, out result: int): bool {\n                result = 42\n                return true\n            }\n\n            func Main() {\n                if TryParse(\"123\", out var num) {\n                    print num\n                }\n            }\n        "
    assert !PeParse(source).Success
    assert PeCensus(source) == "NL103@8:40+7;", PeCensus(source)
    assert PeRow(source, 0) == "NL103@8:40+7|Inline out declarations are not supported|                if TryParse(\"123\", out var num) {|N# out arguments must refer to a variable that already exists.|Declare 'num' before the call, then pass 'out num'.|<null>|https://docs.n-sharp.dev/errors/NL103", PeRow(source, 0)
    assert PeRow(source, 1) == "<no-such-error>", PeRow(source, 1)
    assert PeDecls(source) == "FunctionDeclaration[TryParse/s2]FunctionDeclaration[Main/s1]", PeDecls(source)
}

test "020 s19 parser patterns: `out int value` gets the same one diagnostic with a span two columns wider, and the same fully recovered top level (was ParserTests.TestInlineOutExplicitTypeDeclarationReportsParseError)" {
    source := "\n            func TryParse(input: string, out result: int): bool {\n                result = 42\n                return true\n            }\n\n            func Main() {\n                if TryParse(\"456\", out int value) {\n                    print value\n                }\n            }\n        "
    assert !PeParse(source).Success
    assert PeCensus(source) == "NL103@8:40+9;", PeCensus(source)
    assert PeRow(source, 0) == "NL103@8:40+9|Inline out declarations are not supported|                if TryParse(\"456\", out int value) {|N# out arguments must refer to a variable that already exists.|Declare 'value' before the call, then pass 'out value'.|<null>|https://docs.n-sharp.dev/errors/NL103", PeRow(source, 0)
    assert PeRow(source, 1) == "<no-such-error>", PeRow(source, 1)
    assert PeDecls(source) == "FunctionDeclaration[TryParse/s2]FunctionDeclaration[Main/s1]", PeDecls(source)
}

// ---- (c) OPERATOR AND CONVERSION OVERLOADS — 6 contracts ----
//
// THE TWO SHAPES ARE NOT VARIANTS OF EACH OTHER, AND THE DELETED TESTS COULD NOT SEE IT. A
// `static func operator +` sets IsOperatorOverload, carries `Modifiers.Static`, keeps the symbol in
// `OperatorSymbol` and fills BOTH `OperatorKeywordSpan` and `OperatorSymbolSpan`. An
// `implicit operator` sets IsConversionOperator, leaves IsOperatorOverload FALSE, carries
// `Modifiers.None`, leaves `OperatorSymbol` NULL, and leaves both spans at their zero default. The
// deleted six asserted `IsOperatorOverload` / `IsConversionOperator` / `OperatorSymbol` and — in
// exactly one of the six — `Modifiers.HasFlag(Static)`; the spans, the names and the
// conversion-side flag word were never read.
//
// WHAT WAS ALREADY PINNED NEXT DOOR, AND WHAT IS NOT — CHECKED, NOT ASSUMED.
// `ColumnarParserAst.tests.nl`'s tranche 10 pins `func operator +` with its symbol and both spans
// (Parser.cs :505-506), and tranche 11 pins an `implicit operator`'s whole flag word
// (`false, null, true, true`). Both use the sources WITHOUT a `static` modifier, so what those
// contracts could not state is the one thing these six turn on: **`static func operator +` carries
// `Modifiers.Static` while the conversion form carries `Modifiers.None`** — which is exactly why
// `Golden.OperatorFunc`, whose `Modifiers.None` is hardcoded, could not express this corpus and
// `Golden.OpFunc` had to be added. The conversion form's two operator spans are also STATED here
// (`Golden.SpanOf(0, 0, 0)`) where tranche 11 only left them at a constructor default.

test "020 s19 parser patterns: `static func operator +` anchors the declaration on `func` — not on `static` and not on `operator` — while OperatorKeywordSpan covers `operator` and OperatorSymbolSpan covers the `+` (was ParserTests.TestOperatorOverloadBinaryPlus)" {
    source := "\n            class Vector {\n                X: int\n                Y: int\n\n                static func operator +(a: Vector, b: Vector): Vector {\n                    return new Vector { X: a.X + b.X, Y: a.Y + b.Y }\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("X", Golden.SimpleT("int", 3, 20, 23), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Y", Golden.SimpleT("int", 4, 20, 23), null, Modifiers.None, PropertyModifier.None, 4, 17))
    params3 := new List<Parameter>()
    params3.Add(Golden.Param("a", Golden.SimpleT("Vector", 6, 43, 49), null, false, ParameterModifier.None, 6, 40))
    params3.Add(Golden.Param("b", Golden.SimpleT("Vector", 6, 54, 60), null, false, ParameterModifier.None, 6, 51))
    stmts4 := new List<Statement>()
    props5 := new List<PropertyInitializer>()
    props5.Add(Golden.PropInit("X", null, Golden.Bin(Golden.Member(Golden.Ident("a", 7, 44), "X", false, 7, 45), BinaryOperator.Add, Golden.Member(Golden.Ident("b", 7, 50), "X", false, 7, 51), 7, 48), 7, 41))
    props5.Add(Golden.PropInit("Y", null, Golden.Bin(Golden.Member(Golden.Ident("a", 7, 58), "Y", false, 7, 59), BinaryOperator.Add, Golden.Member(Golden.Ident("b", 7, 64), "Y", false, 7, 65), 7, 62), 7, 55))
    stmts4.Add(Golden.Return(Golden.NewE(Golden.SimpleT("Vector", 7, 32, 38), Golden.NoArgs(), Golden.ObjInit(props5, 7, 28), null, 7, 28), 7, 21))
    members2.Add(Golden.OpFunc("operator +", params3, Golden.SimpleT("Vector", 6, 63, 69), Golden.Block(stmts4, 6, 70), Modifiers.Static, true, "+", false, false, Golden.SpanOf(6, 29, 37), Golden.SpanOf(6, 38, 39), 6, 24))
    decls1.Add(Golden.ClassF("Vector", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a UNARY overload is the same node as a binary one with one parameter, and `-v.X` in its body is a Negate UnaryExpression over a member access (was ParserTests.TestOperatorOverloadUnaryMinus)" {
    source := "\n            class Vector {\n                X: int\n                Y: int\n\n                static func operator -(v: Vector): Vector {\n                    return new Vector { X: -v.X, Y: -v.Y }\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("X", Golden.SimpleT("int", 3, 20, 23), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Y", Golden.SimpleT("int", 4, 20, 23), null, Modifiers.None, PropertyModifier.None, 4, 17))
    params3 := new List<Parameter>()
    params3.Add(Golden.Param("v", Golden.SimpleT("Vector", 6, 43, 49), null, false, ParameterModifier.None, 6, 40))
    stmts4 := new List<Statement>()
    props5 := new List<PropertyInitializer>()
    props5.Add(Golden.PropInit("X", null, Golden.Un(UnaryOperator.Negate, Golden.Member(Golden.Ident("v", 7, 45), "X", false, 7, 46), 7, 44), 7, 41))
    props5.Add(Golden.PropInit("Y", null, Golden.Un(UnaryOperator.Negate, Golden.Member(Golden.Ident("v", 7, 54), "Y", false, 7, 55), 7, 53), 7, 50))
    stmts4.Add(Golden.Return(Golden.NewE(Golden.SimpleT("Vector", 7, 32, 38), Golden.NoArgs(), Golden.ObjInit(props5, 7, 28), null, 7, 28), 7, 21))
    members2.Add(Golden.OpFunc("operator -", params3, Golden.SimpleT("Vector", 6, 52, 58), Golden.Block(stmts4, 6, 59), Modifiers.Static, true, "-", false, false, Golden.SpanOf(6, 29, 37), Golden.SpanOf(6, 38, 39), 6, 24))
    decls1.Add(Golden.ClassF("Vector", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `==` and `!=` produce two OperatorSymbol strings of TWO characters, and their symbol spans are two columns wide where `+`'s is one (was ParserTests.TestOperatorOverloadComparison)" {
    source := "\n            class Money {\n                Amount: decimal\n\n                static func operator ==(a: Money, b: Money): bool {\n                    return a.Amount == b.Amount\n                }\n\n                static func operator !=(a: Money, b: Money): bool {\n                    return a.Amount != b.Amount\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Amount", Golden.SimpleT("decimal", 3, 25, 32), null, Modifiers.None, PropertyModifier.None, 3, 17))
    params3 := new List<Parameter>()
    params3.Add(Golden.Param("a", Golden.SimpleT("Money", 5, 44, 49), null, false, ParameterModifier.None, 5, 41))
    params3.Add(Golden.Param("b", Golden.SimpleT("Money", 5, 54, 59), null, false, ParameterModifier.None, 5, 51))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.Return(Golden.Bin(Golden.Member(Golden.Ident("a", 6, 28), "Amount", false, 6, 29), BinaryOperator.Equal, Golden.Member(Golden.Ident("b", 6, 40), "Amount", false, 6, 41), 6, 37), 6, 21))
    members2.Add(Golden.OpFunc("operator ==", params3, Golden.SimpleT("bool", 5, 62, 66), Golden.Block(stmts4, 5, 67), Modifiers.Static, true, "==", false, false, Golden.SpanOf(5, 29, 37), Golden.SpanOf(5, 38, 40), 5, 24))
    params5 := new List<Parameter>()
    params5.Add(Golden.Param("a", Golden.SimpleT("Money", 9, 44, 49), null, false, ParameterModifier.None, 9, 41))
    params5.Add(Golden.Param("b", Golden.SimpleT("Money", 9, 54, 59), null, false, ParameterModifier.None, 9, 51))
    stmts6 := new List<Statement>()
    stmts6.Add(Golden.Return(Golden.Bin(Golden.Member(Golden.Ident("a", 10, 28), "Amount", false, 10, 29), BinaryOperator.NotEqual, Golden.Member(Golden.Ident("b", 10, 40), "Amount", false, 10, 41), 10, 37), 10, 21))
    members2.Add(Golden.OpFunc("operator !=", params5, Golden.SimpleT("bool", 9, 62, 66), Golden.Block(stmts6, 9, 67), Modifiers.Static, true, "!=", false, false, Golden.SpanOf(9, 29, 37), Golden.SpanOf(9, 38, 40), 9, 24))
    decls1.Add(Golden.ClassF("Money", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: the `&` and `|` overloads on a STRUCT carry the same Modifiers.Static and the same span shape as the class-hosted ones (was ParserTests.TestOperatorOverloadBitwise)" {
    source := "\n            struct Flags {\n                Value: int\n\n                static func operator &(a: Flags, b: Flags): Flags {\n                    return new Flags { Value: a.Value & b.Value }\n                }\n\n                static func operator |(a: Flags, b: Flags): Flags {\n                    return new Flags { Value: a.Value | b.Value }\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Value", Golden.SimpleT("int", 3, 24, 27), null, Modifiers.None, PropertyModifier.None, 3, 17))
    params3 := new List<Parameter>()
    params3.Add(Golden.Param("a", Golden.SimpleT("Flags", 5, 43, 48), null, false, ParameterModifier.None, 5, 40))
    params3.Add(Golden.Param("b", Golden.SimpleT("Flags", 5, 53, 58), null, false, ParameterModifier.None, 5, 50))
    stmts4 := new List<Statement>()
    props5 := new List<PropertyInitializer>()
    props5.Add(Golden.PropInit("Value", null, Golden.Bin(Golden.Member(Golden.Ident("a", 6, 47), "Value", false, 6, 48), BinaryOperator.BitwiseAnd, Golden.Member(Golden.Ident("b", 6, 57), "Value", false, 6, 58), 6, 55), 6, 40))
    stmts4.Add(Golden.Return(Golden.NewE(Golden.SimpleT("Flags", 6, 32, 37), Golden.NoArgs(), Golden.ObjInit(props5, 6, 28), null, 6, 28), 6, 21))
    members2.Add(Golden.OpFunc("operator &", params3, Golden.SimpleT("Flags", 5, 61, 66), Golden.Block(stmts4, 5, 67), Modifiers.Static, true, "&", false, false, Golden.SpanOf(5, 29, 37), Golden.SpanOf(5, 38, 39), 5, 24))
    params6 := new List<Parameter>()
    params6.Add(Golden.Param("a", Golden.SimpleT("Flags", 9, 43, 48), null, false, ParameterModifier.None, 9, 40))
    params6.Add(Golden.Param("b", Golden.SimpleT("Flags", 9, 53, 58), null, false, ParameterModifier.None, 9, 50))
    stmts7 := new List<Statement>()
    props8 := new List<PropertyInitializer>()
    props8.Add(Golden.PropInit("Value", null, Golden.Bin(Golden.Member(Golden.Ident("a", 10, 47), "Value", false, 10, 48), BinaryOperator.BitwiseOr, Golden.Member(Golden.Ident("b", 10, 57), "Value", false, 10, 58), 10, 55), 10, 40))
    stmts7.Add(Golden.Return(Golden.NewE(Golden.SimpleT("Flags", 10, 32, 37), Golden.NoArgs(), Golden.ObjInit(props8, 10, 28), null, 10, 28), 10, 21))
    members2.Add(Golden.OpFunc("operator |", params6, Golden.SimpleT("Flags", 9, 61, 66), Golden.Block(stmts7, 9, 67), Modifiers.Static, true, "|", false, false, Golden.SpanOf(9, 29, 37), Golden.SpanOf(9, 38, 39), 9, 24))
    decls1.Add(Golden.StructF("Flags", null, Golden.NoTypeRefs(), members2, null, Modifiers.None, false, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: an `implicit operator` is NOT an operator overload: IsOperatorOverload is FALSE, Modifiers is None rather than Static, OperatorSymbol is null and BOTH operator spans stay at their zero default (was ParserTests.TestImplicitConversionOperator)" {
    source := "\n            class Celsius {\n                Value: double\n\n                implicit operator Fahrenheit(c: Celsius) {\n                    return new Fahrenheit { Value: c.Value * 9.0 / 5.0 + 32.0 }\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Value", Golden.SimpleT("double", 3, 24, 30), null, Modifiers.None, PropertyModifier.None, 3, 17))
    params3 := new List<Parameter>()
    params3.Add(Golden.Param("c", Golden.SimpleT("Celsius", 5, 49, 56), null, false, ParameterModifier.None, 5, 46))
    stmts4 := new List<Statement>()
    props5 := new List<PropertyInitializer>()
    props5.Add(Golden.PropInit("Value", null, Golden.Bin(Golden.Bin(Golden.Bin(Golden.Member(Golden.Ident("c", 6, 52), "Value", false, 6, 53), BinaryOperator.Multiply, Golden.FloatLit("9.0", 6, 62), 6, 60), BinaryOperator.Divide, Golden.FloatLit("5.0", 6, 68), 6, 66), BinaryOperator.Add, Golden.FloatLit("32.0", 6, 74), 6, 72), 6, 45))
    stmts4.Add(Golden.Return(Golden.NewE(Golden.SimpleT("Fahrenheit", 6, 32, 42), Golden.NoArgs(), Golden.ObjInit(props5, 6, 28), null, 6, 28), 6, 21))
    members2.Add(Golden.OpFunc("implicit operator", params3, Golden.SimpleT("Fahrenheit", 5, 35, 45), Golden.Block(stmts4, 5, 58), Modifiers.None, false, null, true, true, Golden.SpanOf(0, 0, 0), Golden.SpanOf(0, 0, 0), 5, 17))
    decls1.Add(Golden.ClassF("Celsius", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `explicit operator` differs from `implicit` in exactly one flag — IsImplicitConversion — and the name keeps the keyword (`explicit operator`) with the target type in ReturnType (was ParserTests.TestExplicitConversionOperator)" {
    source := "\n            struct Fraction {\n                Numerator: int\n                Denominator: int\n\n                explicit operator double(f: Fraction) {\n                    return f.Numerator / (double)f.Denominator\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Numerator", Golden.SimpleT("int", 3, 28, 31), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Denominator", Golden.SimpleT("int", 4, 30, 33), null, Modifiers.None, PropertyModifier.None, 4, 17))
    params3 := new List<Parameter>()
    params3.Add(Golden.Param("f", Golden.SimpleT("Fraction", 6, 45, 53), null, false, ParameterModifier.None, 6, 42))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.Return(Golden.Bin(Golden.Member(Golden.Ident("f", 7, 28), "Numerator", false, 7, 29), BinaryOperator.Divide, Golden.Cast(Golden.Member(Golden.Ident("f", 7, 50), "Denominator", false, 7, 51), Golden.SimpleT("double", 7, 43, 49), CastKind.Hard, 7, 42), 7, 40), 7, 21))
    members2.Add(Golden.OpFunc("explicit operator", params3, Golden.SimpleT("double", 6, 35, 41), Golden.Block(stmts4, 6, 55), Modifiers.None, false, null, true, false, Golden.SpanOf(0, 0, 0), Golden.SpanOf(0, 0, 0), 6, 17))
    decls1.Add(Golden.StructF("Fraction", null, Golden.NoTypeRefs(), members2, null, Modifiers.None, false, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- (d) CONSTRUCTOR INITIALIZERS — 3 contracts ----
//
// `: this(name, 0)` and `: base(name)` are ordinary `CallExpression`s in
// `ConstructorDeclaration.Initializer`, and BOTH the call and its `this`/`base` callee anchor on the
// keyword rather than on the `(`. The deleted trio asserted the callee TYPE and the argument count.
// `ColumnarParserAst.tests.nl`'s tranche 10 already pins the `: base(x)` anchor over a synthetic
// one-liner and tranche 11 pins the SYNTHETIC `this()` a malformed initializer recovers to; what
// these three add is the REAL `: this(args)` delegation with two and three arguments, the delegating
// constructor's EMPTY body, and the overload sitting beside it in the same Members list.

test "020 s19 parser patterns: `: this(name, 0)` is a CallExpression whose Callee is a ThisExpression, and BOTH anchor on the `this` keyword rather than on the `(` (was ParserTests.TestConstructorWithThisInitializer)" {
    source := "\n            class Person {\n                Name: string\n                Age: int\n\n                constructor(name: string): this(name, 0) {\n                }\n\n                constructor(name: string, age: int) {\n                    Name = name\n                    Age = age\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Age", Golden.SimpleT("int", 4, 22, 25), null, Modifiers.None, PropertyModifier.None, 4, 17))
    params3 := new List<Parameter>()
    params3.Add(Golden.Param("name", Golden.SimpleT("string", 6, 35, 41), null, false, ParameterModifier.None, 6, 29))
    args4 := new List<Argument>()
    args4.Add(Golden.ArgF(null, Golden.Ident("name", 6, 49), ArgumentModifier.None))
    args4.Add(Golden.ArgF(null, Golden.IntLit("0", 6, 55), ArgumentModifier.None))
    members2.Add(Golden.CtorF(params3, Golden.Block(Golden.NoStmts(), 6, 58), Golden.Call(Golden.ThisE(6, 44), args4, Golden.NoTypeArgs(), 6, 44), Modifiers.None, 6, 17))
    params5 := new List<Parameter>()
    params5.Add(Golden.Param("name", Golden.SimpleT("string", 9, 35, 41), null, false, ParameterModifier.None, 9, 29))
    params5.Add(Golden.Param("age", Golden.SimpleT("int", 9, 48, 51), null, false, ParameterModifier.None, 9, 43))
    stmts6 := new List<Statement>()
    stmts6.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("Name", 10, 21), AssignmentOperator.Assign, Golden.Ident("name", 10, 28), 10, 26), 10, 21))
    stmts6.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("Age", 11, 21), AssignmentOperator.Assign, Golden.Ident("age", 11, 27), 11, 25), 11, 21))
    members2.Add(Golden.CtorF(params5, Golden.Block(stmts6, 9, 53), null, Modifiers.None, 9, 17))
    decls1.Add(Golden.ClassF("Person", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: `: base(name)` is the same CallExpression shape with a BaseExpression callee, on a class that also carries a BaseClass type reference (was ParserTests.TestConstructorWithBaseInitializer)" {
    source := "\n            class Employee : Person {\n                EmployeeId: string\n\n                constructor(name: string, id: string): base(name) {\n                    EmployeeId = id\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("EmployeeId", Golden.SimpleT("string", 3, 29, 35), null, Modifiers.None, PropertyModifier.None, 3, 17))
    params3 := new List<Parameter>()
    params3.Add(Golden.Param("name", Golden.SimpleT("string", 5, 35, 41), null, false, ParameterModifier.None, 5, 29))
    params3.Add(Golden.Param("id", Golden.SimpleT("string", 5, 47, 53), null, false, ParameterModifier.None, 5, 43))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("EmployeeId", 6, 21), AssignmentOperator.Assign, Golden.Ident("id", 6, 34), 6, 32), 6, 21))
    args5 := new List<Argument>()
    args5.Add(Golden.ArgF(null, Golden.Ident("name", 5, 61), ArgumentModifier.None))
    members2.Add(Golden.CtorF(params3, Golden.Block(stmts4, 5, 67), Golden.Call(Golden.BaseE(5, 56), args5, Golden.NoTypeArgs(), 5, 56), Modifiers.None, 5, 17))
    decls1.Add(Golden.ClassF("Employee", null, Golden.SimpleT("Person", 2, 30, 36), Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s19 parser patterns: a three-argument `this(name, 0.0, 0)` keeps its arguments in source order with a FloatLiteral between two others, and the delegating constructor's body is an EMPTY block (was ParserTests.TestConstructorWithMultipleArguments)" {
    source := "\n            class Product {\n                Name: string\n                Price: double\n                Stock: int\n\n                constructor(name: string): this(name, 0.0, 0) {\n                }\n\n                constructor(name: string, price: double, stock: int) {\n                    Name = name\n                    Price = price\n                    Stock = stock\n                }\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Price", Golden.SimpleT("double", 4, 24, 30), null, Modifiers.None, PropertyModifier.None, 4, 17))
    members2.Add(Golden.FieldF("Stock", Golden.SimpleT("int", 5, 24, 27), null, Modifiers.None, PropertyModifier.None, 5, 17))
    params3 := new List<Parameter>()
    params3.Add(Golden.Param("name", Golden.SimpleT("string", 7, 35, 41), null, false, ParameterModifier.None, 7, 29))
    args4 := new List<Argument>()
    args4.Add(Golden.ArgF(null, Golden.Ident("name", 7, 49), ArgumentModifier.None))
    args4.Add(Golden.ArgF(null, Golden.FloatLit("0.0", 7, 55), ArgumentModifier.None))
    args4.Add(Golden.ArgF(null, Golden.IntLit("0", 7, 60), ArgumentModifier.None))
    members2.Add(Golden.CtorF(params3, Golden.Block(Golden.NoStmts(), 7, 63), Golden.Call(Golden.ThisE(7, 44), args4, Golden.NoTypeArgs(), 7, 44), Modifiers.None, 7, 17))
    params5 := new List<Parameter>()
    params5.Add(Golden.Param("name", Golden.SimpleT("string", 10, 35, 41), null, false, ParameterModifier.None, 10, 29))
    params5.Add(Golden.Param("price", Golden.SimpleT("double", 10, 50, 56), null, false, ParameterModifier.None, 10, 43))
    params5.Add(Golden.Param("stock", Golden.SimpleT("int", 10, 65, 68), null, false, ParameterModifier.None, 10, 58))
    stmts6 := new List<Statement>()
    stmts6.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("Name", 11, 21), AssignmentOperator.Assign, Golden.Ident("name", 11, 28), 11, 26), 11, 21))
    stmts6.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("Price", 12, 21), AssignmentOperator.Assign, Golden.Ident("price", 12, 29), 12, 27), 12, 21))
    stmts6.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("Stock", 13, 21), AssignmentOperator.Assign, Golden.Ident("stock", 13, 29), 13, 27), 13, 21))
    members2.Add(Golden.CtorF(params5, Golden.Block(stmts6, 10, 70), null, Modifiers.None, 10, 17))
    decls1.Add(Golden.ClassF("Product", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

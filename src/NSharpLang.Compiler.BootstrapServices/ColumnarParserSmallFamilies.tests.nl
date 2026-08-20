namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL FILE-HEADER / LITERAL AND INTERPOLATION / ATTRIBUTE / PREPROCESSOR CONTRACTS FOR
// `ColumnarParserRecovery.ParseFileAst`, IN N#.
//
// These replace the fourth tranche of `tests/ParserTests.cs` — 33 of its remaining 93 `[Fact]`s,
// 711 C# lines, 209 `Assert.` occurrences — which task 020 slice 20 deletes. The tranche is the four
// SMALL families left after slices 17, 18 and 19 took declarations, statements and
// patterns/modifiers/operators: the file header (package, namespace and both kinds of import — 12),
// literals and interpolation (9, including one of the family's negatives), attributes (8, including
// the other) and the preprocessor (4). They are taken TOGETHER because the only other residue is the
// expression family at 1,822 lines, over the ~1,500-line cap the slice-16 sketch set, and padding a
// small family out of the expression half would defeat the family split that makes each successor a
// coherent file. `tests/ParserTests.cs` survives this slice at 60 methods carrying exactly that half.
//
// THE ROUTE IS THE WHOLE-TREE GOLDEN, AND IT IS STRICTLY STRONGER THAN WHAT IT REPLACES. All 31
// positive cases went through one private helper:
//
//     private static CompilationUnit Parse(string source)
//         => ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit!;
//
// followed by a handful of member reads — `cu.Imports[0].Namespace`, `param0.Attributes![0].Name`.
// A whole-tree diff pins every node, every registered field and every anchor at once. The margin is
// widest in this tranche's two most opinionated families: the attribute family never once stated
// where an attribute SITS, and the interpolation family never stated what the parts around a hole
// CONTAIN. Both turn out to matter, and both are recorded per contract below.
//
// THE SECOND CLAIM IN EVERY POSITIVE CONTRACT IS THAT THE SOURCE PARSES CLEANLY, AND `Parse()` ABOVE
// COULD NOT MAKE IT: it reads `.CompilationUnit` and DISCARDS `.Errors`. Each contract pins
// `PsCensus(source) == ""` first. MEASURED RESULT FOR THIS TRANCHE: all 31 positive sources parse
// with an EMPTY diagnostic list — the same verdict slices 17, 18 and 19 measured over their 50, 23
// and 44, so the pin has now found no defect over 148 real-world fixtures. It is kept because it is
// the guard that makes the silence impossible to re-introduce.
//
// THE NEGATIVE HALF IS TWO CONTRACTS, ONE FROM EACH OF TWO DIFFERENT FAMILIES, AND ONE OF THEM IS
// THE FIRST MULTI-DIAGNOSTIC NEGATIVE THIS ARC HAS PINNED. `AssertHasParseError` asserted
// `!Success` plus "SOME error message contains this text". The interpolation refusal really does
// report exactly one diagnostic; the attribute-after-name refusal reports EIGHT and leaves seven
// synthetic `<error>` classes behind it, which the deleted assertion could not distinguish from a
// clean single-error recovery. Each successor states the whole census, EVERY row (message, snippet,
// explanation, hint, suggestions, docs URL), the no-more-rows guard and the recovered top level.
//
// THE HELPERS ARE REUSED, NOT RE-COPIED. `PsAst` / `PsCensus` live in
// `ColumnarParserStatements.tests.nl` and `PeParse` / `PeCensus` / `PeRow` / `PeDecls` in
// `ColumnarParserErrorRecovery.tests.nl`; both sets are public free functions in this project and
// this file calls them across the file boundary rather than adding a third copy of either census.
// `AstEq.Diff` and the `Golden.*` builders live in `ColumnarParserAst.tests.nl`. That file needed
// ZERO new `AstEq.FieldNames` entries — every header, attribute, interpolation and preprocessor node
// type was already registered — and NINE new builders: four RETURNING list-element forms
// (`ImportF` / `FileImportF` / `AttrF` / `PreprocF`, the returning siblings of the four existing
// appenders at the same arity) and five ATTRIBUTE-CARRYING declaration forms (`ClassA` / `StructA` /
// `FieldA` / `FuncA` / `ParamA`), because the full-arity `*F` builders the three earlier tranches
// added all hardcode an EMPTY attribute list and this tranche IS the attribute family.
//
// THIS FILE IS ABOUT THE PARSER'S INTERPOLATED-STRING AST, NOT THE EMITTER'S HOLE PLAN.
// `ColumnarInterpolationSplitter.tests.nl` next door owns `ColumnarInterpolationSplitter.TrySplit`,
// which re-scans a LITERAL for the columnar backend's hole plan; its subject is which hole SHAPES the
// emitter models. The contracts below are about `InterpolatedStringExpression.Parts` — what the
// PARSER built. Neither duplicates the other, and neither should grow into the other's subject.
//
// THE SOURCES ARE THE DELETED FIXTURES BYTE-FOR-BYTE — leading newline, twelve-space indentation and
// trailing eight spaces included where the C# spelled them that way, and flush-left where it did not.
// The tranche uses two C# literal forms, 32 verbatim `@"…"` and 1 single-line `"…"`, and the
// byte-identity check that produced these literals was run with the C# COMPILER as the decoder rather
// than a hand-rolled literal reader.
//
// WHAT THESE PINS MEASURED THAT THE DELETED ASSERTIONS COULD NOT SEE is recorded per contract below,
// and the four shapes that were ALREADY pinned next door by the synthetic stage-N+1c corpus are
// labelled as restatements rather than findings — the sibling sweep is part of the method, not an
// afterthought.

// ---- (a) THE FILE HEADER — package, namespace and imports — 12 contracts ----
//
// THE COMPILATION UNIT'S OWN ANCHOR IS THE FIRST HEADER LINE, WHATEVER KIND IT IS, and that is
// what the deleted twelve never stated: they read `cu.Namespace`, `cu.Package`, `cu.Imports[i]`
// and `cu.FileImports[i]` and asserted names, aliases and counts. Every contract below also pins
// where the unit sits, and the three orderings in this family (namespace-first, package-first,
// import-first) put it on three different lines.
//
// FOUR OF THESE SHAPES ARE RESTATEMENTS AND ARE LABELLED SO. `ColumnarParserAst.tests.nl`'s
// stage-N+1c tranche-1 contracts already pin a file-scoped namespace, a package with an aliased
// namespace import, an aliased file import's PathColumn/PathLength, and a whole file combining
// namespace + import + file-import + declarations, all over synthetic one-line sources. What the
// contracts below add is the REAL-WORLD corpus — indented headers, three imports at once, both
// import kinds interleaved, and the two package orderings.

test "020 s20 parser header: a file-scoped namespace, three imports (one aliased) and a declaration all hang off ONE CompilationUnit whose own anchor is the NAMESPACE's, and every import anchors on its own `import` keyword (was ParserTests.TestNamespaceAndUsings)" {
    source := "\n            namespace MyApp.Services\n\n            import System\n            import System.Collections.Generic\n            import System.Text.Json as Json\n\n            func Test() {}\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    imports1 := new List<ImportDirective>()
    imports1.Add(Golden.ImportF("System", null, 4, 13))
    imports1.Add(Golden.ImportF("System.Collections.Generic", null, 5, 13))
    imports1.Add(Golden.ImportF("System.Text.Json", "Json", 6, 13))
    decls2 := new List<Declaration>()
    decls2.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(Golden.NoStmts(), 8, 25), null, null, null, Modifiers.None, 8, 13))
    expected := Golden.Unit(Golden.Ns("MyApp.Services", 2, 13), imports1, NoFileImports(), null, decls2, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: a quoted file import (import 'Models/Person' with real double quotes) lands in FileImports and not in Imports, keeps the path WITHOUT its quotes, leaves Alias null, and anchors PathColumn on the opening quote with PathLength counting BOTH quotes (was ParserTests.TestFileImport)" {
    source := "\n            import \"Models/Person\"\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    fileImports1 := new List<Statement>()
    fileImports1.Add(Golden.FileImportF("Models/Person", null, 20, 15, 2, 13))
    expected := Golden.Unit(null, NoImports(), fileImports1, null, NoDecls(), 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: a flush-left file import puts PathColumn at 8 and PathLength at 15 — the quote-inclusive span the C# recomputed with IndexOf, stated as literals (was ParserTests.TestFileImportTracksQuotedPathSpan)" {
    source := "import \"Models/Person\""
    assert PsCensus(source) == ""
    actual := PsAst(source)
    fileImports1 := new List<Statement>()
    fileImports1.Add(Golden.FileImportF("Models/Person", null, 8, 15, 1, 1))
    expected := Golden.Unit(null, NoImports(), fileImports1, null, NoDecls(), 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: `as AuthService` fills FileImport.Alias while PathColumn/PathLength stay on the quoted path and do not grow to cover the alias (was ParserTests.TestFileImportWithAlias)" {
    source := "\n            import \"Services/Auth\" as AuthService\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    fileImports1 := new List<Statement>()
    fileImports1.Add(Golden.FileImportF("Services/Auth", "AuthService", 20, 15, 2, 13))
    expected := Golden.Unit(null, NoImports(), fileImports1, null, NoDecls(), 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: an unquoted dotted `import System.Collections.Generic` lands in Imports with the whole dotted name in ONE string and a null Alias (was ParserTests.TestNamespaceImport)" {
    source := "\n            import System.Collections.Generic\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    imports1 := new List<ImportDirective>()
    imports1.Add(Golden.ImportF("System.Collections.Generic", null, 2, 13))
    expected := Golden.Unit(null, imports1, NoFileImports(), null, NoDecls(), 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: `import System.Text.Json as Json` splits the dotted namespace from the alias (restates the synthetic tranche-1 contract over the real corpus) (was ParserTests.TestNamespaceImportWithAlias)" {
    source := "\n            import System.Text.Json as Json\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    imports1 := new List<ImportDirective>()
    imports1.Add(Golden.ImportF("System.Text.Json", "Json", 2, 13))
    expected := Golden.Unit(null, imports1, NoFileImports(), null, NoDecls(), 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: file imports and namespace imports interleaved in source order land in two SEPARATE lists, each keeping its own relative order, and the unit anchors on the FIRST header line whichever kind it is (was ParserTests.TestMultipleImports)" {
    source := "\n            import \"Models/Person\"\n            import System.Linq\n            import \"Services/Auth\" as AuthService\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    imports1 := new List<ImportDirective>()
    imports1.Add(Golden.ImportF("System.Linq", null, 3, 13))
    fileImports2 := new List<Statement>()
    fileImports2.Add(Golden.FileImportF("Models/Person", null, 20, 15, 2, 13))
    fileImports2.Add(Golden.FileImportF("Services/Auth", "AuthService", 20, 15, 4, 13))
    expected := Golden.Unit(null, imports1, fileImports2, null, NoDecls(), 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: `package MathUtils` fills CompilationUnit.Package and leaves Namespace null — the two header slots are independent, not alternatives (was ParserTests.TestPackageDeclaration)" {
    source := "\n            package MathUtils\n\n            func Add(a: int, b: int): int {\n                return a + b\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("a", Golden.SimpleT("int", 4, 25, 28), null, false, ParameterModifier.None, 4, 22))
    params2.Add(Golden.Param("b", Golden.SimpleT("int", 4, 33, 36), null, false, ParameterModifier.None, 4, 30))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.Bin(Golden.Ident("a", 5, 24), BinaryOperator.Add, Golden.Ident("b", 5, 28), 5, 26), 5, 17))
    decls1.Add(Golden.Func("Add", params2, Golden.SimpleT("int", 4, 39, 42), Golden.Block(stmts3, 4, 43), null, null, null, Modifiers.None, 4, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), Golden.Pkg("MathUtils", 2, 13), decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: package first then imports keeps the unit anchored on the PACKAGE line, and the record body underneath is unaffected by either (was ParserTests.TestPackageBeforeImports)" {
    source := "\n            package NSharp.Http\n\n            import System\n            import System.Collections.Generic\n\n            record HttpRequest {\n                Method: string\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    imports1 := new List<ImportDirective>()
    imports1.Add(Golden.ImportF("System", null, 4, 13))
    imports1.Add(Golden.ImportF("System.Collections.Generic", null, 5, 13))
    decls2 := new List<Declaration>()
    members3 := new List<Declaration>()
    members3.Add(Golden.FieldF("Method", Golden.SimpleT("string", 8, 25, 31), null, Modifiers.None, PropertyModifier.None, 8, 17))
    decls2.Add(Golden.RecordF("HttpRequest", null, Golden.NoTypeRefs(), members3, null, false, Modifiers.None, 7, 13))
    expected := Golden.Unit(null, imports1, NoFileImports(), Golden.Pkg("NSharp.Http", 2, 13), decls2, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: an import BEFORE the package still fills Package, and the unit then anchors on the IMPORT line — the order is accepted and the anchor follows the first header line, not the package (was ParserTests.TestImportsBeforePackageRemainSupported)" {
    source := "\n            import System\n\n            package Compat\n\n            func main() {}\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    imports1 := new List<ImportDirective>()
    imports1.Add(Golden.ImportF("System", null, 2, 13))
    decls2 := new List<Declaration>()
    decls2.Add(Golden.Func("main", Golden.NoParams(), null, Golden.Block(Golden.NoStmts(), 6, 25), null, null, null, Modifiers.None, 6, 13))
    expected := Golden.Unit(null, imports1, NoFileImports(), Golden.Pkg("Compat", 4, 13), decls2, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: a three-segment `package MyCompany.Utils.Math` keeps the whole dotted name in one PackageDeclaration.Name string (was ParserTests.TestDottedPackageName)" {
    source := "\n            package MyCompany.Utils.Math\n\n            func Multiply(a: int, b: int): int {\n                return a * b\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("a", Golden.SimpleT("int", 4, 30, 33), null, false, ParameterModifier.None, 4, 27))
    params2.Add(Golden.Param("b", Golden.SimpleT("int", 4, 38, 41), null, false, ParameterModifier.None, 4, 35))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.Bin(Golden.Ident("a", 5, 24), BinaryOperator.Multiply, Golden.Ident("b", 5, 28), 5, 26), 5, 17))
    decls1.Add(Golden.Func("Multiply", params2, Golden.SimpleT("int", 4, 44, 47), Golden.Block(stmts3, 4, 48), null, null, null, Modifiers.None, 4, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), Golden.Pkg("MyCompany.Utils.Math", 2, 13), decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser header: a file with no package and no namespace leaves BOTH null and both header lists EMPTY, and anchors the unit on its first declaration (was ParserTests.TestNoPackageDeclaration)" {
    source := "\n            func Add(a: int, b: int): int {\n                return a + b\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    params2.Add(Golden.Param("a", Golden.SimpleT("int", 2, 25, 28), null, false, ParameterModifier.None, 2, 22))
    params2.Add(Golden.Param("b", Golden.SimpleT("int", 2, 33, 36), null, false, ParameterModifier.None, 2, 30))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.Bin(Golden.Ident("a", 3, 24), BinaryOperator.Add, Golden.Ident("b", 3, 28), 3, 26), 3, 17))
    decls1.Add(Golden.Func("Add", params2, Golden.SimpleT("int", 2, 39, 42), Golden.Block(stmts3, 2, 43), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- (b) LITERALS AND INTERPOLATION — 8 positive contracts and 1 negative ----
//
// THE DELETED FAMILY READ THE HOLES AND NEVER THE TEXT AROUND THEM, AND THAT IS WHERE THE FINDING
// IS. `TestInterpolatedRawString` asserted `Assert.Single(parts.OfType<InterpolatedStringHole>())`
// over a four-line JSON template containing TWO brace groups, and it passed — because in a RAW
// interpolated string a `:` followed by whitespace SWALLOWS the next brace group into the text
// run. `"name": "{person.Name}"` is a hole (the `{` follows a quote); `"age": {person.Age}` is
// literal TEXT (the `{` follows `: `). The whole-tree golden states all three parts, so the text
// part carrying `{person.Age}` is now a claim rather than an omission.
//
// THE RAW LITERAL ITSELF KEEPS ITS INDENTATION. N#'s `"""…"""` is not C#'s: the closing delimiter
// does not strip the common indent, so `Value` carries the leading newline, every line's leading
// spaces and the trailing indentation. The deleted `Assert.Contains("multi-line", …)` could not
// distinguish that from any other whitespace treatment.
//
// THE FOUR ORDINARY-STRING CONTRACTS RESTATE tranche 9c's synthetic shapes (a single hole, text
// around a hole, brace escapes, a format clause) over real print statements and real hole
// EXPRESSIONS — a member access, a ternary, a `??` binary — rather than bare identifiers. What is
// new in them is that a hole's expression carries REAL source positions (including on the second
// line of a multi-line raw literal), that a top-level `?:` inside a hole does NOT start a format
// clause, and that `{value ?? fallback:N2}` splits at the LAST colon. The char literal restates
// tranche 7's contract over an inferred local instead of an enum member value.

test "020 s20 parser literals: an N# raw string literal keeps its OWN text verbatim — leading newline, every line's indentation and the trailing indentation before the closing delimiter are all in Value, and the quotes are stripped (the C# raw-literal indent-stripping rule does NOT apply) (was ParserTests.TestMultiLineTemplateString)" {
    source := "\n            func Test() {\n                template := \"\"\"\n                This is a multi-line\n                string literal\n                with multiple lines\n                \"\"\"\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("template", null, Golden.StrLit("\n                This is a multi-line\n                string literal\n                with multiple lines\n                ", 3, 29), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser literals: in a RAW interpolated string a colon followed by whitespace SWALLOWS the next brace group into the text run, so the JSON line whose brace group follows a colon stays literal TEXT while the one whose brace group follows a quote is a hole — one hole and two text parts, which is why the deleted Assert.Single passed (was ParserTests.TestInterpolatedRawString)" {
    source := "\n            func Test() {\n                json := $\"\"\"\n                {\n                    \"name\": \"{person.Name}\",\n                    \"age\": {person.Age}\n                }\n                \"\"\"\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    parts3 := new List<InterpolatedStringPart>()
    parts3.Add(Golden.TextPart("\n                {\n                    \"name\": \"", 3, 29))
    parts3.Add(Golden.HolePart(Golden.Member(Golden.Ident("person", 5, 31), "Name", false, 5, 37), null, 5, 30))
    parts3.Add(Golden.TextPart("\",\n                    \"age\": {person.Age}\n                }\n                ", 5, 43))
    stmts2.Add(Golden.VarDecl("json", null, Golden.Interp(parts3, true, 3, 25), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser literals: an interpolation hole's expression carries REAL source positions — the member access at the dot and its receiver at the identifier — while the hole itself anchors on the `{` one column earlier (was ParserTests.TestInterpolatedStringHoleParsesSemanticExpressionWithSourcePosition)" {
    source := "\nfunc Test() {\n    print $\"Hello, {person.Name}!\"\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    parts3 := new List<InterpolatedStringPart>()
    parts3.Add(Golden.TextPart("Hello, ", 3, 13))
    parts3.Add(Golden.HolePart(Golden.Member(Golden.Ident("person", 3, 21), "Name", false, 3, 27), null, 3, 20))
    parts3.Add(Golden.TextPart("!", 3, 33))
    stmts2.Add(Golden.Print(Golden.Interp(parts3, false, 3, 11), 3, 5))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser literals: `{{` and `}}` around a live hole each collapse to ONE brace in the surrounding text run while advancing TWO source columns, so the three parts anchor at 13, 16 and 22 (was ParserTests.TestInterpolatedStringEscapedBracesRemainTextAroundSemanticHole)" {
    source := "\nfunc Test() {\n    print $\"{{ {name} }}\"\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    parts3 := new List<InterpolatedStringPart>()
    parts3.Add(Golden.TextPart("{ ", 3, 13))
    parts3.Add(Golden.HolePart(Golden.Ident("name", 3, 17), null, 3, 16))
    parts3.Add(Golden.TextPart(" }", 3, 22))
    stmts2.Add(Golden.Print(Golden.Interp(parts3, false, 3, 11), 3, 5))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser literals: a top-level `?:` inside a hole parses as a TernaryExpression and its `:` does NOT start a format clause — FormatClause stays null and all three arms keep their own anchors (was ParserTests.TestInterpolatedStringHoleParsesTopLevelTernaryAsExpressionNotFormatClause)" {
    source := "\nfunc Test() {\n    print $\"{ok ? yes : no}\"\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    parts3 := new List<InterpolatedStringPart>()
    parts3.Add(Golden.HolePart(Golden.Tern(Golden.Ident("ok", 3, 14), Golden.Ident("yes", 3, 19), Golden.Ident("no", 3, 25), 3, 17), null, 3, 13))
    stmts2.Add(Golden.Print(Golden.Interp(parts3, false, 3, 11), 3, 5))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser literals: `{value ?? fallback:N2}` splits at the LAST colon — the `??` binary is the hole expression and `N2` is the FormatClause (was ParserTests.TestInterpolatedStringHoleKeepsNullCoalescingFormatClause)" {
    source := "\nfunc Test() {\n    print $\"{value ?? fallback:N2}\"\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    parts3 := new List<InterpolatedStringPart>()
    parts3.Add(Golden.HolePart(Golden.Bin(Golden.Ident("value", 3, 14), BinaryOperator.NullCoalesce, Golden.Ident("fallback", 3, 23), 3, 20), "N2", 3, 13))
    stmts2.Add(Golden.Print(Golden.Interp(parts3, false, 3, 11), 3, 5))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser literals: `{name extra}` reports exactly ONE NL101 underlining the TRAILING token only, with a null Suggestions list, and recovery still returns the function with its body intact (was ParserTests.TestInterpolatedStringHoleReportsTrailingExpressionSyntax)" {
    source := "\nfunc Test() {\n    print $\"{name extra}\"\n}"
    assert !PeParse(source).Success
    assert PeCensus(source) == "NL101@3:19+5;", PeCensus(source)
    assert PeRow(source, 0) == "NL101@3:19+5|Unexpected token 'extra' after interpolated string expression|    print $\"{name extra}\"|I parsed a valid expression at the start of this interpolation hole, but there was extra syntax after it.|Keep exactly one expression inside each interpolation hole, or split additional text outside the braces.|<null>|https://docs.n-sharp.dev/errors/NL101", PeRow(source, 0)
    assert PeRow(source, 1) == "<no-such-error>", PeRow(source, 1)
    assert PeDecls(source) == "FunctionDeclaration[Test/s1]", PeDecls(source)
}

test "020 s20 parser literals: a hole on the SECOND line of a raw interpolated string carries that line's real Line/Column, and the leading and trailing newlines stay in the surrounding text parts (was ParserTests.TestInterpolatedRawStringHoleParsesSemanticExpressionWithMultilineSourcePosition)" {
    source := "\nfunc Test() {\n    print $\"\"\"\nHello, {person.Name}!\n\"\"\"\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    parts3 := new List<InterpolatedStringPart>()
    parts3.Add(Golden.TextPart("\nHello, ", 3, 15))
    parts3.Add(Golden.HolePart(Golden.Member(Golden.Ident("person", 4, 9), "Name", false, 4, 15), null, 4, 8))
    parts3.Add(Golden.TextPart("!\n", 4, 21))
    stmts2.Add(Golden.Print(Golden.Interp(parts3, true, 3, 11), 3, 5))
    decls1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(stmts2, 2, 13), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser literals: a char literal keeps its single quotes inside Value (restates the synthetic tranche-7 contract over an inferred local instead of an enum member) (was ParserTests.TestCharLiteralExpression)" {
    source := "\n            func Main() {\n                delimiter := '|'\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("delimiter", null, Golden.CharLit("'|'", 3, 30), VariableKind.Let, 3, 17))
    decls1.Add(Golden.Func("Main", Golden.NoParams(), null, Golden.Block(stmts2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- (c) ATTRIBUTES — 7 positive contracts and 1 negative ----
//
// AN ATTRIBUTE ANCHORS ON ITS OWN `[` COLUMN PLUS ONE, ON ITS OWN LINE, AND ITS OWNER KEEPS ITS
// OWN ANCHOR. None of the deleted seven read `.Line` or `.Column` on anything, so every position
// below is a claim the deleted file never made — including the fact that a declaration whose
// attribute sits on the previous line still anchors on the DECLARATION line.
//
// THE WHOLE PARAMETER-ATTRIBUTE HALF HAD NO CONTRACT AT ALL. `ColumnarParserAst.tests.nl` pins
// attributes on a STRUCT declaration (tranche 4, and tranche 9b for the argument-bearing and
// colon-named forms); nothing anywhere pinned `Parameter.Attributes`. These contracts state that
// an attribute-free parameter carries a NULL list rather than an empty one, that two bracket
// groups on one parameter flatten into ONE list in source order, that an attribute and a `ref` /
// `params` modifier coexist without moving the parameter's NAME anchor, and that
// `[FromQuery(Name = "q")]` parses its argument as an ASSIGNMENT EXPRESSION with a null
// `Argument.Name` — where the `[Attr(x: 1)]` colon form tranche 9b pins fills `Name` instead.

test "020 s20 parser attributes: attributes on a CLASS, on two of its FIELDS and on a top-level FUNCTION stay on their own owners, each anchored on the attribute's own line at the `[` column plus one while the owner keeps its own line (was ParserTests.TestAttributes)" {
    source := "\n            [Serializable]\n            class Person {\n                [JsonProperty(\"user_name\")]\n                UserName: string\n\n                [Required]\n                Email: string\n            }\n\n            [HttpGet(\"/api/users\")]\n            func GetUsers(): User[] {\n                return []\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    attrs3 := new List<AttributeNode>()
    args4 := new List<Argument>()
    args4.Add(Golden.ArgF(null, Golden.StrLit("\"user_name\"", 4, 31), ArgumentModifier.None))
    attrs3.Add(Golden.AttrF("JsonProperty", args4, 4, 18))
    members2.Add(Golden.FieldA("UserName", Golden.SimpleT("string", 5, 27, 33), null, Modifiers.None, PropertyModifier.None, attrs3, 5, 17))
    attrs5 := new List<AttributeNode>()
    attrs5.Add(Golden.AttrF("Required", Golden.NoArgs(), 7, 18))
    members2.Add(Golden.FieldA("Email", Golden.SimpleT("string", 8, 24, 30), null, Modifiers.None, PropertyModifier.None, attrs5, 8, 17))
    attrs6 := new List<AttributeNode>()
    attrs6.Add(Golden.AttrF("Serializable", Golden.NoArgs(), 2, 14))
    decls1.Add(Golden.ClassA("Person", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, attrs6, 3, 13))
    stmts7 := new List<Statement>()
    stmts7.Add(Golden.Return(Golden.ArrayLit(Golden.NoExprs(), false, 13, 24), 13, 17))
    attrs8 := new List<AttributeNode>()
    args9 := new List<Argument>()
    args9.Add(Golden.ArgF(null, Golden.StrLit("\"/api/users\"", 11, 22), ArgumentModifier.None))
    attrs8.Add(Golden.AttrF("HttpGet", args9, 11, 14))
    decls1.Add(Golden.FuncA("GetUsers", Golden.NoParams(), Golden.ArrayT(Golden.SimpleT("User", 12, 30, 34), 12, 30, 36), Golden.Block(stmts7, 12, 37), null, null, null, Modifiers.None, attrs8, 12, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser attributes: a dotted attribute name is kept WHOLE in AttributeNode.Name — one, three and four segments — and never split into a member access (was ParserTests.TestQualifiedAttributes)" {
    source := "\n            [System.Serializable]\n            class Person {\n                Name: string\n            }\n\n            [System.Runtime.CompilerServices.InlineArray(10)]\n            struct Buffer {\n                element: int\n            }\n\n            [System.Diagnostics.CodeAnalysis.SuppressMessage(\"Category\", \"CheckId\")]\n            func DoWork() {\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 4, 23, 29), null, Modifiers.None, PropertyModifier.None, 4, 17))
    attrs3 := new List<AttributeNode>()
    attrs3.Add(Golden.AttrF("System.Serializable", Golden.NoArgs(), 2, 14))
    decls1.Add(Golden.ClassA("Person", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, attrs3, 3, 13))
    members4 := new List<Declaration>()
    members4.Add(Golden.FieldF("element", Golden.SimpleT("int", 9, 26, 29), null, Modifiers.None, PropertyModifier.None, 9, 17))
    attrs5 := new List<AttributeNode>()
    args6 := new List<Argument>()
    args6.Add(Golden.ArgF(null, Golden.IntLit("10", 7, 58), ArgumentModifier.None))
    attrs5.Add(Golden.AttrF("System.Runtime.CompilerServices.InlineArray", args6, 7, 14))
    decls1.Add(Golden.StructA("Buffer", null, Golden.NoTypeRefs(), members4, null, Modifiers.None, false, attrs5, 8, 13))
    attrs7 := new List<AttributeNode>()
    args8 := new List<Argument>()
    args8.Add(Golden.ArgF(null, Golden.StrLit("\"Category\"", 12, 62), ArgumentModifier.None))
    args8.Add(Golden.ArgF(null, Golden.StrLit("\"CheckId\"", 12, 74), ArgumentModifier.None))
    attrs7.Add(Golden.AttrF("System.Diagnostics.CodeAnalysis.SuppressMessage", args8, 12, 14))
    decls1.Add(Golden.FuncA("DoWork", Golden.NoParams(), null, Golden.Block(Golden.NoStmts(), 13, 27), null, null, null, Modifiers.None, attrs7, 13, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser attributes: a PARAMETER's attribute list is non-null and anchored inside the parameter list, and the parameter's own anchor is its NAME, past the attribute (was ParserTests.TestParameterAttributes)" {
    source := "\n            func Create([FromBody] dto: TaskDto, [Required] name: string): void {\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    attrs3 := new List<AttributeNode>()
    attrs3.Add(Golden.AttrF("FromBody", Golden.NoArgs(), 2, 26))
    params2.Add(Golden.ParamA("dto", Golden.SimpleT("TaskDto", 2, 41, 48), null, false, ParameterModifier.None, attrs3, 2, 36))
    attrs4 := new List<AttributeNode>()
    attrs4.Add(Golden.AttrF("Required", Golden.NoArgs(), 2, 51))
    params2.Add(Golden.ParamA("name", Golden.SimpleT("string", 2, 67, 73), null, false, ParameterModifier.None, attrs4, 2, 61))
    decls1.Add(Golden.Func("Create", params2, Golden.SimpleT("void", 2, 76, 80), Golden.Block(Golden.NoStmts(), 2, 81), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser attributes: an attribute argument spelled with = (Name = q) parses as an AssignmentExpression, NOT as a named Argument — Argument.Name stays null where the colon form fills it (was ParserTests.TestParameterAttributesWithArguments)" {
    source := "\n            func Search([FromQuery(Name = \"q\")] query: string, [Range(1, 100)] page: int): void {\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    attrs3 := new List<AttributeNode>()
    args4 := new List<Argument>()
    args4.Add(Golden.ArgF(null, Golden.Assign(Golden.Ident("Name", 2, 36), AssignmentOperator.Assign, Golden.StrLit("\"q\"", 2, 43), 2, 41), ArgumentModifier.None))
    attrs3.Add(Golden.AttrF("FromQuery", args4, 2, 26))
    params2.Add(Golden.ParamA("query", Golden.SimpleT("string", 2, 56, 62), null, false, ParameterModifier.None, attrs3, 2, 49))
    attrs5 := new List<AttributeNode>()
    args6 := new List<Argument>()
    args6.Add(Golden.ArgF(null, Golden.IntLit("1", 2, 71), ArgumentModifier.None))
    args6.Add(Golden.ArgF(null, Golden.IntLit("100", 2, 74), ArgumentModifier.None))
    attrs5.Add(Golden.AttrF("Range", args6, 2, 65))
    params2.Add(Golden.ParamA("page", Golden.SimpleT("int", 2, 86, 89), null, false, ParameterModifier.None, attrs5, 2, 80))
    decls1.Add(Golden.Func("Search", params2, Golden.SimpleT("void", 2, 92, 96), Golden.Block(Golden.NoStmts(), 2, 97), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser attributes: two bracket groups on one parameter produce TWO AttributeNodes in source order in ONE list, not a nested one (was ParserTests.TestParameterMultipleAttributes)" {
    source := "\n            func Create([FromBody] [Required] dto: TaskDto): void {\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    attrs3 := new List<AttributeNode>()
    attrs3.Add(Golden.AttrF("FromBody", Golden.NoArgs(), 2, 26))
    attrs3.Add(Golden.AttrF("Required", Golden.NoArgs(), 2, 37))
    params2.Add(Golden.ParamA("dto", Golden.SimpleT("TaskDto", 2, 52, 59), null, false, ParameterModifier.None, attrs3, 2, 47))
    decls1.Add(Golden.Func("Create", params2, Golden.SimpleT("void", 2, 62, 66), Golden.Block(Golden.NoStmts(), 2, 67), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser attributes: an attribute and a `ref` / `params` modifier coexist on one parameter — the attribute anchors on its own `[` and the parameter still anchors on its NAME, past both (was ParserTests.TestParameterAttributesWithModifiers)" {
    source := "\n            func Process([Required] ref data: byte[], [FromBody] params items: string[]): void {\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    attrs3 := new List<AttributeNode>()
    attrs3.Add(Golden.AttrF("Required", Golden.NoArgs(), 2, 27))
    params2.Add(Golden.ParamA("data", Golden.ArrayT(Golden.SimpleT("byte", 2, 47, 51), 2, 47, 53), null, false, ParameterModifier.Ref, attrs3, 2, 41))
    attrs4 := new List<AttributeNode>()
    attrs4.Add(Golden.AttrF("FromBody", Golden.NoArgs(), 2, 56))
    params2.Add(Golden.ParamA("items", Golden.ArrayT(Golden.SimpleT("string", 2, 80, 86), 2, 80, 88), null, false, ParameterModifier.Params, attrs4, 2, 73))
    decls1.Add(Golden.Func("Process", params2, Golden.SimpleT("void", 2, 91, 95), Golden.Block(Golden.NoStmts(), 2, 96), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser attributes: a method attribute and a parameter attribute never leak into each other, and an attribute-FREE parameter carries a NULL Attributes list rather than an empty one (was ParserTests.TestMethodAndParameterAttributesStayScoped)" {
    source := "\n            [InlineData(1, 2)]\n            func Theory([FromServices] service: Calculator, value: int): void {\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    params2 := new List<Parameter>()
    attrs3 := new List<AttributeNode>()
    attrs3.Add(Golden.AttrF("FromServices", Golden.NoArgs(), 3, 26))
    params2.Add(Golden.ParamA("service", Golden.SimpleT("Calculator", 3, 49, 59), null, false, ParameterModifier.None, attrs3, 3, 40))
    params2.Add(Golden.Param("value", Golden.SimpleT("int", 3, 68, 71), null, false, ParameterModifier.None, 3, 61))
    attrs4 := new List<AttributeNode>()
    args5 := new List<Argument>()
    args5.Add(Golden.ArgF(null, Golden.IntLit("1", 2, 25), ArgumentModifier.None))
    args5.Add(Golden.ArgF(null, Golden.IntLit("2", 2, 28), ArgumentModifier.None))
    attrs4.Add(Golden.AttrF("InlineData", args5, 2, 14))
    decls1.Add(Golden.FuncA("Theory", params2, Golden.SimpleT("void", 3, 74, 78), Golden.Block(Golden.NoStmts(), 3, 79), null, null, null, Modifiers.None, attrs4, 3, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser attributes: an attribute after the parameter NAME reports NL102 with a repair suggestion and then CASCADES into seven NL101s, leaving a body-less function and seven synthetic `<error>` classes behind (was ParserTests.TestParameterAttributesAfterNameReportParseError)" {
    source := "\n            func Create(dto [FromBody]: TaskDto): void {\n            }\n        "
    assert !PeParse(source).Success
    assert PeCensus(source) == "NL102@2:25+3;NL101@2:39+1;NL101@2:41+7;NL101@2:48+1;NL101@2:49+1;NL101@2:51+4;NL101@2:56+1;NL101@3:13+1;", PeCensus(source)
    assert PeRow(source, 0) == "NL102@2:25+3|Expected ':' after parameter name. Got '['|            func Create(dto [FromBody]: TaskDto): void {|Parameter 'dto' needs a ':' before its type.|Write this parameter as `dto: Type`.|{Add ':' after 'dto'}|https://docs.n-sharp.dev/errors/NL102", PeRow(source, 0)
    assert PeRow(source, 1) == "NL101@2:39+1|Unexpected token ':'|            func Create(dto [FromBody]: TaskDto): void {|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found ':' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://docs.n-sharp.dev/errors/NL101", PeRow(source, 1)
    assert PeRow(source, 2) == "NL101@2:41+7|Unexpected token 'TaskDto'|            func Create(dto [FromBody]: TaskDto): void {|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found 'TaskDto' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://docs.n-sharp.dev/errors/NL101", PeRow(source, 2)
    assert PeRow(source, 3) == "NL101@2:48+1|Unexpected token ')'|            func Create(dto [FromBody]: TaskDto): void {|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found ')' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://docs.n-sharp.dev/errors/NL101", PeRow(source, 3)
    assert PeRow(source, 4) == "NL101@2:49+1|Unexpected token ':'|            func Create(dto [FromBody]: TaskDto): void {|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found ':' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://docs.n-sharp.dev/errors/NL101", PeRow(source, 4)
    assert PeRow(source, 5) == "NL101@2:51+4|Unexpected token 'void'|            func Create(dto [FromBody]: TaskDto): void {|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found 'void' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://docs.n-sharp.dev/errors/NL101", PeRow(source, 5)
    assert PeRow(source, 6) == "NL101@2:56+1|Unexpected token '{'|            func Create(dto [FromBody]: TaskDto): void {|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '{' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://docs.n-sharp.dev/errors/NL101", PeRow(source, 6)
    assert PeRow(source, 7) == "NL101@3:13+1|Unexpected token '}'|            }|I was expecting a declaration here (like 'func', 'class', 'enum', etc.), but I found '}' instead.|Top-level declarations must be functions, classes, structs, records, soa records, enums, interfaces, unions, or type aliases.|<null>|https://docs.n-sharp.dev/errors/NL101", PeRow(source, 7)
    assert PeRow(source, 8) == "<no-such-error>", PeRow(source, 8)
    assert PeDecls(source) == "FunctionDeclaration[Create/nobody]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]ClassDeclaration[<error>/m0]", PeDecls(source)
}

// ---- (d) THE PREPROCESSOR — 4 contracts ----
//
// THE SAME DIRECTIVE TEXT LANDS IN TWO DIFFERENT NODE TYPES depending on where it sits: a
// `PreprocessorDeclaration` in the declaration list at top level, a `PreprocessorDirective`
// STATEMENT inside a block. Both keep the WHOLE directive line — condition, region name and all —
// in one `Directive` string, and neither is paired with its closing form by the parser: `#endif`
// and `#endregion` are independent nodes in the same list. Tranche 10 pins the top-level
// declaration form over `#if DEBUG`; the STATEMENT form, `#region` with a multi-word argument and
// `#define` are all new here.

test "020 s20 parser preprocessor: `#if` / `#endif` at top level become PreprocessorDeclarations in the declaration list, keeping the WHOLE directive text including its condition, and the class between them parses normally (was ParserTests.TestPreprocessorDirectiveTopLevel)" {
    source := "\n#if DEBUG\nclass DebugHelper {\n    DebugFlag: bool = true\n}\n#endif\n"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    decls1.Add(Golden.PreprocF("#if DEBUG", 2, 1))
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("DebugFlag", Golden.SimpleT("bool", 4, 16, 20), Golden.BoolLit(true, 4, 23), Modifiers.None, PropertyModifier.None, 4, 5))
    decls1.Add(Golden.ClassF("DebugHelper", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 3, 1))
    decls1.Add(Golden.PreprocF("#endif", 6, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser preprocessor: the same directives inside a function body become PreprocessorDirective STATEMENTS in the block, so the block has three statements and the print keeps its own (was ParserTests.TestPreprocessorDirectiveInFunction)" {
    source := "\nfunc TestFunc() {\n    #if DEBUG\n    print \"Debug mode\"\n    #endif\n}"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.Preproc("#if DEBUG", 3, 5))
    stmts2.Add(Golden.Print(Golden.StrLit("\"Debug mode\"", 4, 11), 4, 5))
    stmts2.Add(Golden.Preproc("#endif", 5, 5))
    decls1.Add(Golden.Func("TestFunc", Golden.NoParams(), null, Golden.Block(stmts2, 2, 17), null, null, null, Modifiers.None, 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser preprocessor: `#region Helper Functions` keeps its multi-word argument in the directive text, and `#endregion` closes it as a separate declaration (was ParserTests.TestPreprocessorRegion)" {
    source := "\n#region Helper Functions\nfunc Helper(): int {\n    return 42\n}\n#endregion\n"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    decls1.Add(Golden.PreprocF("#region Helper Functions", 2, 1))
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.Return(Golden.IntLit("42", 4, 12), 4, 5))
    decls1.Add(Golden.Func("Helper", Golden.NoParams(), Golden.SimpleT("int", 3, 16, 19), Golden.Block(stmts2, 3, 20), null, null, null, Modifiers.None, 3, 1))
    decls1.Add(Golden.PreprocF("#endregion", 6, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s20 parser preprocessor: `#define FEATURE_X` is a lone PreprocessorDeclaration and produces no other declaration (was ParserTests.TestPreprocessorDefine)" {
    source := "\n#define FEATURE_X\n"
    assert PsCensus(source) == ""
    actual := PsAst(source)
    decls1 := new List<Declaration>()
    decls1.Add(Golden.PreprocF("#define FEATURE_X", 2, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

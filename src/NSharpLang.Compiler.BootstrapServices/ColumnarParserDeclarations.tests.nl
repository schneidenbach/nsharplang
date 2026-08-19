namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL DECLARATION-SHAPE CONTRACTS FOR `ColumnarParserRecovery.ParseFileAst`, IN N#.
//
// These replace the DECLARATION tranche of `tests/ParserTests.cs` — 50 of its 212 `[Fact]`s, 1,358
// C# lines, 350 `Assert.` statements — which task 020 slice 17 deletes. The tranche is the type and
// function DECLARATION family: class / struct / record / interface / enum / union / type-alias /
// newtype / soa-record headers, their members (fields, properties, indexers, constructors, member
// functions), modifiers, generics and `where` constraints. The 162 methods it left behind are later
// tranches of the same arc: slice 18 took the STATEMENT family plus the test DSL (23 methods) to
// `ColumnarParserStatements.tests.nl`, and `tests/ParserTests.cs` survives at 139 methods carrying
// expressions and operator precedence, patterns, literals and interpolation, the preprocessor and
// file-header families, attributes, parameter modifiers, operator overloads, generic calls and
// lambdas.
//
// THE ROUTE IS THE WHOLE-TREE GOLDEN, AND IT IS STRICTLY STRONGER THAN WHAT IT REPLACES.
// Every migrated C# case went through one private helper:
//
//     private static CompilationUnit Parse(string source)
//         => ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit!;
//
// followed by a handful of member reads — `cu.Declarations[0] as ClassDeclaration`, `Assert.Equal(2,
// classDecl.Members.Count)`, `Assert.True(mods.HasFlag(Modifiers.Partial))`. A whole-tree diff pins
// every node, every registered field and every anchor at once, so a parser that answered the right
// member COUNT with the wrong member ORDER, or the right modifier with the wrong Line/Column, was
// invisible to the deleted assertions and is not invisible here. `AstEq.Diff` and the `Golden.*`
// builders both live in `ColumnarParserAst.tests.nl` next door; this slice extended `Golden` with
// the FULL-ARITY declaration builders (`ClassF` … `CtorF`, `AddConstraint`) that a real-world corpus
// needs, because the narrow `Add*` builders there were each cut for one parity tranche and do not
// combine.
//
// THE SECOND CLAIM IN EVERY CONTRACT IS THAT THE SOURCE PARSES CLEANLY, AND THAT CLAIM IS NEW.
// `Parse()` above reads `.CompilationUnit` and DISCARDS `.Errors` entirely, so all 212 of the C#
// positive cases were silent about whether the source each of them calls "valid" produces any
// diagnostic at all: a parser that recovered the right tree while reporting a spurious error would
// have passed every one of them. Each contract below pins `PdCensus(source) == ""` first.
// **MEASURED RESULT FOR THIS TRANCHE: all 50 sources parse with an EMPTY diagnostic list.** The pin
// is kept rather than dropped as redundant — it is the guard that makes the silence impossible to
// re-introduce, and later tranches inherit it over sources this one has not seen.
//
// THE CENSUS IS IN RECORDING ORDER, WHICH IS THE ORDER `ParseFileAst` RETURNS AND NOT THE ORDER THE
// CLI SHOWS. `ColumnarParserRecovery.ParseFilePreamble` sorts by position; `ParseFileAst` does not
// (`ColumnarParserErrorRecovery.tests.nl` pins one source whose two diagnostics come back in
// opposite orders from the two entry points). Every census in this file is `ParseFileAst` order.
// It is empty for all 50 sources today, so no ordering is currently observable here — the
// convention is stated because a future contract in this file will be the first to observe it.
//
// THE SOURCES ARE THE DELETED FIXTURES BYTE-FOR-BYTE, leading newline, twelve-space indentation and
// trailing eight spaces included, so every pinned Line/Column is a claim about the SAME text the C#
// parsed. That is why the columns are large: `class` sits at column 13, not column 1.
//
// WHAT THE WHOLE-TREE PINS MEASURED THAT THE DELETED ASSERTIONS COULD NOT SEE is recorded per
// contract below and summarised in `memory/components/parser.md`.

// The return type is `CompilationUnit?` because `FileParseAst.CompilationUnit` IS nullable, and
// declaring it non-null is what puts an NL202 row on the sibling `RunAst` next door. `AstEq.Diff`
// takes `object?` on both sides, so the nullable handle is never dereferenced here and no NL905
// follows it either — this file reports ZERO `nlc check` rows, tests included.
func PdAst(source: string): CompilationUnit? {
    return ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit
}

// Every diagnostic's code and span, in `ParseFileAst`'s recording order. Empty for a clean parse.
// A string kernel rather than a nullable `CompilerError?` handle, because a `.tests.nl` must
// produce ZERO `nlc check` rows and a nullable node handle produces NL905s.
func PdCensus(source: string): string {
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

test "020 s17 parser declarations: a class body materializes both of its fields, and the node anchors on the `class` keyword (was ParserTests.TestClassDeclaration)" {
    source := "\n            class Person {\n                Name: string\n                Age: int\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Age", Golden.SimpleT("int", 4, 22, 25), null, Modifiers.None, PropertyModifier.None, 4, 17))
    decls1.Add(Golden.ClassF("Person", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `partial` lands in Modifiers while Line/Column stay on `class`, not on the modifier (was ParserTests.TestPartialClass)" {
    source := "\n            partial class User {\n                Name: string\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    decls1.Add(Golden.ClassF("User", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.Partial, 2, 21))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `abstract` and `sealed` classes, and an abstract member function with a null Body (was ParserTests.TestAbstractAndSealedClasses)" {
    source := "\n            abstract class Animal {\n                abstract func MakeSound()\n            }\n\n            sealed class FinalClass {\n                Name: string\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.Func("MakeSound", Golden.NoParams(), null, null, null, null, Golden.NoConstraints(), Modifiers.Abstract, 3, 26))
    decls1.Add(Golden.ClassF("Animal", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.Abstract, 2, 22))
    members3 := new List<Declaration>()
    members3.Add(Golden.FieldF("Name", Golden.SimpleT("string", 7, 23, 29), null, Modifiers.None, PropertyModifier.None, 7, 17))
    decls1.Add(Golden.ClassF("FinalClass", null, null, Golden.NoTypeRefs(), members3, null, Modifiers.Sealed, 6, 20))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a `static` class carries Static on itself and on both of its member functions (was ParserTests.TestStaticClass)" {
    source := "\n            static class Helpers {\n                static func DoThing() {\n                    Console.WriteLine(\"done\")\n                }\n\n                static func Calculate(x: int): int {\n                    return x * 2\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    stmts3 := new List<Statement>()
    args4 := new List<Argument>()
    Golden.AddArg(args4, null, Golden.StrLit("\"done\"", 4, 39), ArgumentModifier.None)
    stmts3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 4, 21), "WriteLine", false, 4, 28), args4, Golden.NoTypeArgs(), 4, 38), 4, 21))
    members2.Add(Golden.Func("DoThing", Golden.NoParams(), null, Golden.Block(stmts3, 3, 39), null, null, Golden.NoConstraints(), Modifiers.Static, 3, 24))
    plist5 := new List<Parameter>()
    plist5.Add(Golden.Param("x", Golden.SimpleT("int", 7, 42, 45), null, false, ParameterModifier.None, 7, 39))
    stmts6 := new List<Statement>()
    stmts6.Add(Golden.Return(Golden.Bin(Golden.Ident("x", 8, 28), BinaryOperator.Multiply, Golden.IntLit("2", 8, 32), 8, 30), 8, 21))
    members2.Add(Golden.Func("Calculate", plist5, Golden.SimpleT("int", 7, 48, 51), Golden.Block(stmts6, 7, 52), null, null, Golden.NoConstraints(), Modifiers.Static, 7, 24))
    decls1.Add(Golden.ClassF("Helpers", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.Static, 2, 20))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `file class` sets Modifiers.File (was ParserTests.TestFileClassModifier)" {
    source := "\n            file class InternalHelper {\n                Name: string\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    decls1.Add(Golden.ClassF("InternalHelper", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.File, 2, 18))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `file struct` sets Modifiers.File (was ParserTests.TestFileStructModifier)" {
    source := "\n            file struct Point {\n                X: double\n                Y: double\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("X", Golden.SimpleT("double", 3, 20, 26), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Y", Golden.SimpleT("double", 4, 20, 26), null, Modifiers.None, PropertyModifier.None, 4, 17))
    decls1.Add(Golden.StructF("Point", null, Golden.NoTypeRefs(), members2, null, Modifiers.File, false, 2, 18))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `file record` sets Modifiers.File (was ParserTests.TestFileRecordModifier)" {
    source := "\n            file record Person {\n                Name: string\n                Age: int\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Age", Golden.SimpleT("int", 4, 22, 25), null, Modifiers.None, PropertyModifier.None, 4, 17))
    decls1.Add(Golden.RecordF("Person", null, Golden.NoTypeRefs(), members2, null, false, Modifiers.File, 2, 18))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `file interface` sets Modifiers.File (was ParserTests.TestFileInterfaceModifier)" {
    source := "\n            file interface IHelper {\n                func DoWork(): void\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.Func("DoWork", Golden.NoParams(), Golden.SimpleT("void", 3, 32, 36), null, null, null, Golden.NoConstraints(), Modifiers.None, 3, 17))
    decls1.Add(Golden.InterfaceF("IHelper", null, Golden.NoTypeRefs(), members2, Modifiers.File, false, 2, 18))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `record struct` sets IsStruct=true and anchors on the `record` keyword (was ParserTests.TestRecordStruct)" {
    source := "\n            record struct Point {\n                X: double\n                Y: double\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("X", Golden.SimpleT("double", 3, 20, 26), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Y", Golden.SimpleT("double", 4, 20, 26), null, Modifiers.None, PropertyModifier.None, 4, 17))
    decls1.Add(Golden.RecordF("Point", null, Golden.NoTypeRefs(), members2, null, true, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a bare `record` is a reference type (IsStruct=false) (was ParserTests.TestRecordClass)" {
    source := "\n            record Person {\n                Name: string\n                Age: int\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Age", Golden.SimpleT("int", 4, 22, 25), null, Modifiers.None, PropertyModifier.None, 4, 17))
    decls1.Add(Golden.RecordF("Person", null, Golden.NoTypeRefs(), members2, null, false, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: an interface body materializes a body-less member function (was ParserTests.TestInterfaceDeclaration)" {
    source := "\n            interface IReader {\n                func Read(): string\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.Func("Read", Golden.NoParams(), Golden.SimpleT("string", 3, 30, 36), null, null, null, Golden.NoConstraints(), Modifiers.None, 3, 17))
    decls1.Add(Golden.InterfaceF("IReader", null, Golden.NoTypeRefs(), members2, Modifiers.None, false, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `duck interface` sets IsDuckInterface and anchors on the `duck` keyword (was ParserTests.TestDuckInterface)" {
    source := "\n            duck interface IReaderDuck {\n                func Read(): string\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.Func("Read", Golden.NoParams(), Golden.SimpleT("string", 3, 30, 36), null, null, null, Golden.NoConstraints(), Modifiers.None, 3, 17))
    decls1.Add(Golden.InterfaceF("IReaderDuck", null, Golden.NoTypeRefs(), members2, Modifiers.None, true, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a value-less enum defaults to EnumType.Int with three null-valued members (was ParserTests.TestEnumDeclaration)" {
    source := "\n            enum Status {\n                Pending,\n                Active,\n                Done\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    emems2 := new List<EnumMember>()
    Golden.AddEMem(emems2, "Pending", 3, 17)
    Golden.AddEMem(emems2, "Active", 4, 17)
    Golden.AddEMem(emems2, "Done", 5, 17)
    decls1.Add(Golden.EnumF("Status", emems2, EnumType.Int, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a string-backed enum's member values are StringLiteralExpressions that keep their quotes (was ParserTests.TestEnumDeclarationWithExplicitStringType)" {
    source := "\n            enum Status: string {\n                Pending = \"pending\",\n                Active = \"active\",\n                Done = \"done\"\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    emems2 := new List<EnumMember>()
    Golden.AddEMemV(emems2, "Pending", Golden.StrLit("\"pending\"", 3, 27), 3, 17)
    Golden.AddEMemV(emems2, "Active", Golden.StrLit("\"active\"", 4, 26), 4, 17)
    Golden.AddEMemV(emems2, "Done", Golden.StrLit("\"done\"", 5, 24), 5, 17)
    decls1.Add(Golden.EnumF("Status", emems2, EnumType.String, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: an int-backed enum's member values are IntLiteralExpressions (was ParserTests.TestEnumDeclarationWithExplicitIntType)" {
    source := "\n            enum Priority: int {\n                Low = 0,\n                Medium = 1,\n                High = 2\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    emems2 := new List<EnumMember>()
    Golden.AddEMemV(emems2, "Low", Golden.IntLit("0", 3, 23), 3, 17)
    Golden.AddEMemV(emems2, "Medium", Golden.IntLit("1", 4, 26), 4, 17)
    Golden.AddEMemV(emems2, "High", Golden.IntLit("2", 5, 24), 5, 17)
    decls1.Add(Golden.EnumF("Priority", emems2, EnumType.Int, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a nested enum lands in the enclosing class's Members, before the field declared after it (was ParserTests.TestNestedEnum)" {
    source := "\n            class Container {\n                enum Status {\n                    Active,\n                    Inactive\n                }\n\n                CurrentStatus: Status\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    emems3 := new List<EnumMember>()
    Golden.AddEMem(emems3, "Active", 4, 21)
    Golden.AddEMem(emems3, "Inactive", 5, 21)
    members2.Add(Golden.EnumF("Status", emems3, EnumType.Int, Modifiers.None, 3, 17))
    members2.Add(Golden.FieldF("CurrentStatus", Golden.SimpleT("Status", 8, 32, 38), null, Modifiers.None, PropertyModifier.None, 8, 17))
    decls1.Add(Golden.ClassF("Container", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a nested class lands in the enclosing class's Members, after the field declared before it (was ParserTests.TestNestedClass)" {
    source := "\n            class Outer {\n                Name: string\n\n                class Inner {\n                    Value: int\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members3 := new List<Declaration>()
    members3.Add(Golden.FieldF("Value", Golden.SimpleT("int", 6, 28, 31), null, Modifiers.None, PropertyModifier.None, 6, 21))
    members2.Add(Golden.ClassF("Inner", null, null, Golden.NoTypeRefs(), members3, null, Modifiers.None, 5, 17))
    decls1.Add(Golden.ClassF("Outer", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a union's two cases carry their own property lists (was ParserTests.TestUnionDeclaration)" {
    source := "\n            union Result {\n                Success { value: int }\n                Failure { error: string, code: int }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    ucases2 := new List<UnionCase>()
    uprops3 := new List<UnionCaseProperty>()
    Golden.AddUProp(uprops3, "value", Golden.SimpleT("int", 3, 34, 37))
    Golden.AddUCaseProps(ucases2, "Success", uprops3, 3, 17)
    uprops4 := new List<UnionCaseProperty>()
    Golden.AddUProp(uprops4, "error", Golden.SimpleT("string", 4, 34, 40))
    Golden.AddUProp(uprops4, "code", Golden.SimpleT("int", 4, 48, 51))
    Golden.AddUCaseProps(ucases2, "Failure", uprops4, 4, 17)
    decls1.Add(Golden.UnionF("Result", null, ucases2, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a generic union carries TypeParameters and per-case properties typed by them (was ParserTests.TestGenericUnionDeclaration)" {
    source := "\n            union Either<L, R> {\n                Left { value: L }\n                Right { value: R }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    ucases2 := new List<UnionCase>()
    uprops3 := new List<UnionCaseProperty>()
    Golden.AddUProp(uprops3, "value", Golden.SimpleT("L", 3, 31, 32))
    Golden.AddUCaseProps(ucases2, "Left", uprops3, 3, 17)
    uprops4 := new List<UnionCaseProperty>()
    Golden.AddUProp(uprops4, "value", Golden.SimpleT("R", 4, 32, 33))
    Golden.AddUCaseProps(ucases2, "Right", uprops4, 4, 17)
    tps5 := new List<TypeParameter>()
    Golden.AddTP(tps5, "L")
    Golden.AddTP(tps5, "R")
    decls1.Add(Golden.UnionF("Either", tps5, ucases2, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: three type aliases select the Simple, Function and Generic type-reference nodes (was ParserTests.TestTypeAlias)" {
    source := "\n            type UserId = int\n            type Handler = Func<string, void>\n            type StringDict = Dictionary<string, string>\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    decls1.Add(Golden.TypeAliasF("UserId", Golden.SimpleT("int", 2, 27, 30), 2, 13))
    ftypes2 := new List<TypeReference>()
    ftypes2.Add(Golden.SimpleT("string", 3, 33, 39))
    decls1.Add(Golden.TypeAliasF("Handler", Golden.FuncT(ftypes2, Golden.SimpleT("void", 3, 41, 45), 3, 28, 46), 3, 13))
    targs3 := new List<TypeReference>()
    targs3.Add(Golden.SimpleT("string", 4, 42, 48))
    targs3.Add(Golden.SimpleT("string", 4, 50, 56))
    decls1.Add(Golden.TypeAliasF("StringDict", Golden.GenericT("Dictionary", targs3, 4, 31, 57), 4, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `type X = newtype T` materializes a NewtypeDeclaration, not a TypeAliasDeclaration (was ParserTests.TestNewtypeDeclaration)" {
    source := "\n            type UserId = newtype int\n            type Email = newtype string\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    decls1.Add(Golden.NewtypeF("UserId", Golden.SimpleT("int", 2, 35, 38), 2, 13))
    decls1.Add(Golden.NewtypeF("Email", Golden.SimpleT("string", 3, 34, 40), 3, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a `soa record` materializes three columns across bare, comma and semicolon separators (was ParserTests.SoaRecordDeclaration_ParsesColumns)" {
    source := "\n            soa record NodeTable {\n                kind: int\n                valueStart: int,\n                valueLength: int;\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    scols2 := new List<SoaColumnDeclaration>()
    Golden.AddSCol(scols2, "kind", Golden.SimpleT("int", 3, 23, 26), 3, 17)
    Golden.AddSCol(scols2, "valueStart", Golden.SimpleT("int", 4, 29, 32), 4, 17)
    Golden.AddSCol(scols2, "valueLength", Golden.SimpleT("int", 5, 30, 33), 5, 17)
    decls1.Add(Golden.SoaF("NodeTable", scols2, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `soa` is contextual and stays usable as an ordinary identifier (was ParserTests.SoaRecordDeclaration_ContextualKeywordStillAllowsSoaIdentifier)" {
    source := "\n            func Value(): int {\n                soa := 5\n                return soa\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    stmts2 := new List<Statement>()
    stmts2.Add(Golden.VarDecl("soa", null, Golden.IntLit("5", 3, 24), VariableKind.Let, 3, 17))
    stmts2.Add(Golden.Return(Golden.Ident("soa", 4, 24), 4, 17))
    decls1.Add(Golden.Func("Value", Golden.NoParams(), Golden.SimpleT("int", 2, 27, 30), Golden.Block(stmts2, 2, 31), null, null, Golden.NoConstraints(), Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a base list splits into BaseClass + Interfaces, and the FIRST entry always becomes the base class (was ParserTests.TestMultipleInterfaceImplementation)" {
    source := "\n            class MyClass : BaseClass, IFoo, IBar, IBaz {\n                Name: string\n            }\n\n            class SimpleClass : IFoo, IBar {\n                Id: int\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    ifaces2 := new List<TypeReference>()
    ifaces2.Add(Golden.SimpleT("IFoo", 2, 40, 44))
    ifaces2.Add(Golden.SimpleT("IBar", 2, 46, 50))
    ifaces2.Add(Golden.SimpleT("IBaz", 2, 52, 56))
    members3 := new List<Declaration>()
    members3.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    decls1.Add(Golden.ClassF("MyClass", null, Golden.SimpleT("BaseClass", 2, 29, 38), ifaces2, members3, null, Modifiers.None, 2, 13))
    ifaces4 := new List<TypeReference>()
    ifaces4.Add(Golden.SimpleT("IBar", 6, 39, 43))
    members5 := new List<Declaration>()
    members5.Add(Golden.FieldF("Id", Golden.SimpleT("int", 7, 21, 24), null, Modifiers.None, PropertyModifier.None, 7, 17))
    decls1.Add(Golden.ClassF("SimpleClass", null, Golden.SimpleT("IFoo", 6, 33, 37), ifaces4, members5, null, Modifiers.None, 6, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: one GenericConstraint materializes per `where` clause, on one and on two type parameters (was ParserTests.TestGenericConstraints)" {
    source := "\n            func Process<T>(item: T): T where T : IComparable {\n                return item\n            }\n\n            func Transform<K, V>(key: K, value: V): V where K : IKey where V : IValue {\n                return value\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    plist2 := new List<Parameter>()
    plist2.Add(Golden.Param("item", Golden.SimpleT("T", 2, 35, 36), null, false, ParameterModifier.None, 2, 29))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.Ident("item", 3, 24), 3, 17))
    tps4 := new List<TypeParameter>()
    Golden.AddTP(tps4, "T")
    cons5 := new List<GenericConstraint>()
    ctypes6 := new List<TypeReference>()
    ctypes6.Add(Golden.SimpleT("IComparable", 2, 51, 62))
    Golden.AddConstraint(cons5, "T", ctypes6, SpecialConstraintKind.None)
    decls1.Add(Golden.Func("Process", plist2, Golden.SimpleT("T", 2, 39, 40), Golden.Block(stmts3, 2, 63), null, tps4, cons5, Modifiers.None, 2, 13))
    plist7 := new List<Parameter>()
    plist7.Add(Golden.Param("key", Golden.SimpleT("K", 6, 39, 40), null, false, ParameterModifier.None, 6, 34))
    plist7.Add(Golden.Param("value", Golden.SimpleT("V", 6, 49, 50), null, false, ParameterModifier.None, 6, 42))
    stmts8 := new List<Statement>()
    stmts8.Add(Golden.Return(Golden.Ident("value", 7, 24), 7, 17))
    tps9 := new List<TypeParameter>()
    Golden.AddTP(tps9, "K")
    Golden.AddTP(tps9, "V")
    cons10 := new List<GenericConstraint>()
    ctypes11 := new List<TypeReference>()
    ctypes11.Add(Golden.SimpleT("IKey", 6, 65, 69))
    Golden.AddConstraint(cons10, "K", ctypes11, SpecialConstraintKind.None)
    ctypes12 := new List<TypeReference>()
    ctypes12.Add(Golden.SimpleT("IValue", 6, 80, 86))
    Golden.AddConstraint(cons10, "V", ctypes12, SpecialConstraintKind.None)
    decls1.Add(Golden.Func("Transform", plist7, Golden.SimpleT("V", 6, 53, 54), Golden.Block(stmts8, 6, 87), null, tps9, cons10, Modifiers.None, 6, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a class primary-constructor parameter list with its typed parameters (was ParserTests.TestClassWithPrimaryConstructor)" {
    source := "\n            class UserService(logger: ILogger, db: IDatabase) {\n                func DoWork() {\n                    logger.Log(\"Working\")\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    stmts3 := new List<Statement>()
    args4 := new List<Argument>()
    Golden.AddArg(args4, null, Golden.StrLit("\"Working\"", 4, 32), ArgumentModifier.None)
    stmts3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("logger", 4, 21), "Log", false, 4, 27), args4, Golden.NoTypeArgs(), 4, 31), 4, 21))
    members2.Add(Golden.Func("DoWork", Golden.NoParams(), null, Golden.Block(stmts3, 3, 31), null, null, Golden.NoConstraints(), Modifiers.None, 3, 17))
    plist5 := new List<Parameter>()
    plist5.Add(Golden.Param("logger", Golden.SimpleT("ILogger", 2, 39, 46), null, false, ParameterModifier.None, 2, 31))
    plist5.Add(Golden.Param("db", Golden.SimpleT("IDatabase", 2, 52, 61), null, false, ParameterModifier.None, 2, 48))
    decls1.Add(Golden.ClassF("UserService", null, null, Golden.NoTypeRefs(), members2, plist5, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a struct primary-constructor parameter list (was ParserTests.TestStructWithPrimaryConstructor)" {
    source := "\n            struct Point(x: double, y: double) {\n                func GetDistance(): double {\n                    return Math.Sqrt(x * x + y * y)\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    stmts3 := new List<Statement>()
    args4 := new List<Argument>()
    Golden.AddArg(args4, null, Golden.Bin(Golden.Bin(Golden.Ident("x", 4, 38), BinaryOperator.Multiply, Golden.Ident("x", 4, 42), 4, 40), BinaryOperator.Add, Golden.Bin(Golden.Ident("y", 4, 46), BinaryOperator.Multiply, Golden.Ident("y", 4, 50), 4, 48), 4, 44), ArgumentModifier.None)
    stmts3.Add(Golden.Return(Golden.Call(Golden.Member(Golden.Ident("Math", 4, 28), "Sqrt", false, 4, 32), args4, Golden.NoTypeArgs(), 4, 37), 4, 21))
    members2.Add(Golden.Func("GetDistance", Golden.NoParams(), Golden.SimpleT("double", 3, 37, 43), Golden.Block(stmts3, 3, 44), null, null, Golden.NoConstraints(), Modifiers.None, 3, 17))
    plist5 := new List<Parameter>()
    plist5.Add(Golden.Param("x", Golden.SimpleT("double", 2, 29, 35), null, false, ParameterModifier.None, 2, 26))
    plist5.Add(Golden.Param("y", Golden.SimpleT("double", 2, 40, 46), null, false, ParameterModifier.None, 2, 37))
    decls1.Add(Golden.StructF("Point", null, Golden.NoTypeRefs(), members2, plist5, Modifiers.None, false, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a record primary constructor beside an expression-bodied property over an interpolated string (was ParserTests.TestRecordWithPrimaryConstructor)" {
    source := "\n            record Person(name: string, age: int) {\n                FullInfo: string => $\"{name} is {age} years old\"\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    parts3 := new List<InterpolatedStringPart>()
    Golden.AddHole(parts3, Golden.Ident("name", 3, 40), null, 3, 39)
    Golden.AddText(parts3, " is ", 3, 45)
    Golden.AddHole(parts3, Golden.Ident("age", 3, 50), null, 3, 49)
    Golden.AddText(parts3, " years old", 3, 54)
    members2.Add(Golden.PropF("FullInfo", Golden.SimpleT("string", 3, 27, 33), null, null, Golden.Interp(parts3, false, 3, 37), Modifiers.None, PropertyModifier.None, 3, 17))
    plist4 := new List<Parameter>()
    plist4.Add(Golden.Param("name", Golden.SimpleT("string", 2, 33, 39), null, false, ParameterModifier.None, 2, 27))
    plist4.Add(Golden.Param("age", Golden.SimpleT("int", 2, 46, 49), null, false, ParameterModifier.None, 2, 41))
    decls1.Add(Golden.RecordF("Person", null, Golden.NoTypeRefs(), members2, plist4, false, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `record struct` with a primary constructor and an expression-bodied property (was ParserTests.TestRecordStructWithPrimaryConstructor)" {
    source := "\n            record struct Point(x: double, y: double) {\n                Length: double => Math.Sqrt(x * x + y * y)\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    args3 := new List<Argument>()
    Golden.AddArg(args3, null, Golden.Bin(Golden.Bin(Golden.Ident("x", 3, 45), BinaryOperator.Multiply, Golden.Ident("x", 3, 49), 3, 47), BinaryOperator.Add, Golden.Bin(Golden.Ident("y", 3, 53), BinaryOperator.Multiply, Golden.Ident("y", 3, 57), 3, 55), 3, 51), ArgumentModifier.None)
    members2.Add(Golden.PropF("Length", Golden.SimpleT("double", 3, 25, 31), null, null, Golden.Call(Golden.Member(Golden.Ident("Math", 3, 35), "Sqrt", false, 3, 39), args3, Golden.NoTypeArgs(), 3, 44), Modifiers.None, PropertyModifier.None, 3, 17))
    plist4 := new List<Parameter>()
    plist4.Add(Golden.Param("x", Golden.SimpleT("double", 2, 36, 42), null, false, ParameterModifier.None, 2, 33))
    plist4.Add(Golden.Param("y", Golden.SimpleT("double", 2, 47, 53), null, false, ParameterModifier.None, 2, 44))
    decls1.Add(Golden.RecordF("Point", null, Golden.NoTypeRefs(), members2, plist4, true, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `readonly` on a field, beside a constructor member (was ParserTests.TestReadonlyField)" {
    source := "\n            class MyClass {\n                readonly id: string\n\n                constructor() {\n                    id = Guid.NewGuid().ToString()\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("id", Golden.SimpleT("string", 3, 30, 36), null, Modifiers.Readonly, PropertyModifier.Readonly, 3, 17))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("id", 6, 21), AssignmentOperator.Assign, Golden.Call(Golden.Member(Golden.Call(Golden.Member(Golden.Ident("Guid", 6, 26), "NewGuid", false, 6, 30), Golden.NoArgs(), Golden.NoTypeArgs(), 6, 38), "ToString", false, 6, 40), Golden.NoArgs(), Golden.NoTypeArgs(), 6, 49), 6, 24), 6, 21))
    members2.Add(Golden.CtorF(Golden.NoParams(), Golden.Block(stmts3, 5, 31), null, Modifiers.None, 5, 17))
    decls1.Add(Golden.ClassF("MyClass", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a get/set property materializes both accessor blocks (was ParserTests.TestPropertyWithGetSet)" {
    source := "\n            class Counter {\n                count: int\n\n                Count: int {\n                    get { return count }\n                    set { count = value }\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("count", Golden.SimpleT("int", 3, 24, 27), null, Modifiers.None, PropertyModifier.None, 3, 17))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.Ident("count", 6, 34), 6, 27))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("count", 7, 27), AssignmentOperator.Assign, Golden.Ident("value", 7, 35), 7, 33), 7, 27))
    members2.Add(Golden.PropF("Count", Golden.SimpleT("int", 5, 24, 27), Golden.Block(stmts3, 6, 25), Golden.Block(stmts4, 7, 25), null, Modifiers.None, PropertyModifier.None, 5, 17))
    decls1.Add(Golden.ClassF("Counter", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a get-only property leaves SetBody null (was ParserTests.TestPropertyWithGetOnly)" {
    source := "\n            class Data {\n                value: int\n\n                Value: int {\n                    get { return value }\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("value", Golden.SimpleT("int", 3, 24, 27), null, Modifiers.None, PropertyModifier.None, 3, 17))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.Ident("value", 6, 34), 6, 27))
    members2.Add(Golden.PropF("Value", Golden.SimpleT("int", 5, 24, 27), Golden.Block(stmts3, 6, 25), null, null, Modifiers.None, PropertyModifier.None, 5, 17))
    decls1.Add(Golden.ClassF("Data", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a set-only property leaves GetBody null and keeps both statements of its setter (was ParserTests.TestPropertyWithSetOnly)" {
    source := "\n            class Logger {\n                message: string\n\n                Message: string {\n                    set {\n                        message = value\n                        Console.WriteLine(value)\n                    }\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("message", Golden.SimpleT("string", 3, 26, 32), null, Modifiers.None, PropertyModifier.None, 3, 17))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("message", 7, 25), AssignmentOperator.Assign, Golden.Ident("value", 7, 35), 7, 33), 7, 25))
    args4 := new List<Argument>()
    Golden.AddArg(args4, null, Golden.Ident("value", 8, 43), ArgumentModifier.None)
    stmts3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 8, 25), "WriteLine", false, 8, 32), args4, Golden.NoTypeArgs(), 8, 42), 8, 25))
    members2.Add(Golden.PropF("Message", Golden.SimpleT("string", 5, 26, 32), null, Golden.Block(stmts3, 6, 25), null, Modifiers.None, PropertyModifier.None, 5, 17))
    decls1.Add(Golden.ClassF("Logger", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `required` fields beside a defaulted one that is not required (was ParserTests.TestRequiredProperty)" {
    source := "\n            class Person {\n                required Name: string\n                required Email: string\n                Age: int = 0\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 32, 38), null, Modifiers.Required, PropertyModifier.Required, 3, 17))
    members2.Add(Golden.FieldF("Email", Golden.SimpleT("string", 4, 33, 39), null, Modifiers.Required, PropertyModifier.Required, 4, 17))
    members2.Add(Golden.FieldF("Age", Golden.SimpleT("int", 5, 22, 25), Golden.IntLit("0", 5, 28), Modifiers.None, PropertyModifier.None, 5, 17))
    decls1.Add(Golden.ClassF("Person", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `init` fields in a record body (was ParserTests.TestInitOnlyProperty)" {
    source := "\n            record Person {\n                init Name: string\n                init Age: int\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 28, 34), null, Modifiers.Init, PropertyModifier.Init, 3, 17))
    members2.Add(Golden.FieldF("Age", Golden.SimpleT("int", 4, 27, 30), null, Modifiers.Init, PropertyModifier.Init, 4, 17))
    decls1.Add(Golden.RecordF("Person", null, Golden.NoTypeRefs(), members2, null, false, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `required init` sets BOTH flags on one field (was ParserTests.TestRequiredAndInitProperty)" {
    source := "\n            class User {\n                required init Id: string\n                required init Email: string\n                Name: string = \"\"\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Id", Golden.SimpleT("string", 3, 35, 41), null, Golden.Mods2(Modifiers.Required, Modifiers.Init), Golden.PropMods2(PropertyModifier.Required, PropertyModifier.Init), 3, 17))
    members2.Add(Golden.FieldF("Email", Golden.SimpleT("string", 4, 38, 44), null, Golden.Mods2(Modifiers.Required, Modifiers.Init), Golden.PropMods2(PropertyModifier.Required, PropertyModifier.Init), 4, 17))
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 5, 23, 29), Golden.StrLit("\"\"", 5, 32), Modifiers.None, PropertyModifier.None, 5, 17))
    decls1.Add(Golden.ClassF("User", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a `:=` member leaves Type null and carries its literal initializer (was ParserTests.TestPropertyWithTypeInference)" {
    source := "\n            class Person {\n                Name := \"Alice\"\n                Age := 30\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", null, Golden.StrLit("\"Alice\"", 3, 25), Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Age", null, Golden.IntLit("30", 4, 24), Modifiers.None, PropertyModifier.None, 4, 17))
    decls1.Add(Golden.ClassF("Person", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: an explicitly typed member beside an inferred one in the same body (was ParserTests.TestPropertyWithMixedTypesAndInference)" {
    source := "\n            class Data {\n                ExplicitType: string = \"test\"\n                InferredType := \"inferred\"\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("ExplicitType", Golden.SimpleT("string", 3, 31, 37), Golden.StrLit("\"test\"", 3, 40), Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("InferredType", null, Golden.StrLit("\"inferred\"", 4, 33), Modifiers.None, PropertyModifier.None, 4, 17))
    decls1.Add(Golden.ClassF("Data", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `=>` on a property fills ExpressionBody and leaves both accessor bodies null (was ParserTests.TestExpressionBodiedProperty)" {
    source := "\n            class Person {\n                FirstName: string\n                LastName: string\n                FullName: string => FirstName + \" \" + LastName\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("FirstName", Golden.SimpleT("string", 3, 28, 34), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("LastName", Golden.SimpleT("string", 4, 27, 33), null, Modifiers.None, PropertyModifier.None, 4, 17))
    members2.Add(Golden.PropF("FullName", Golden.SimpleT("string", 5, 27, 33), null, null, Golden.Bin(Golden.Bin(Golden.Ident("FirstName", 5, 37), BinaryOperator.Add, Golden.StrLit("\" \"", 5, 49), 5, 47), BinaryOperator.Add, Golden.Ident("LastName", 5, 55), 5, 53), Modifiers.None, PropertyModifier.None, 5, 17))
    decls1.Add(Golden.ClassF("Person", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: an expression-bodied property over an int product (was ParserTests.TestExpressionBodiedPropertyWithExplicitType)" {
    source := "\n            class Calculator {\n                Value: int\n                DoubleValue: int => Value * 2\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Value", Golden.SimpleT("int", 3, 24, 27), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.PropF("DoubleValue", Golden.SimpleT("int", 4, 30, 33), null, null, Golden.Bin(Golden.Ident("Value", 4, 37), BinaryOperator.Multiply, Golden.IntLit("2", 4, 45), 4, 43), Modifiers.None, PropertyModifier.None, 4, 17))
    decls1.Add(Golden.ClassF("Calculator", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `func this[...]` materializes an IndexerDeclaration with both accessors (was ParserTests.TestIndexerDeclaration)" {
    source := "\n            class Dictionary<K, V> {\n                func this[key: K]: V {\n                    get { return storage[key] }\n                    set { storage[key] = value }\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    tps2 := new List<TypeParameter>()
    Golden.AddTP(tps2, "K")
    Golden.AddTP(tps2, "V")
    members3 := new List<Declaration>()
    plist4 := new List<Parameter>()
    plist4.Add(Golden.Param("key", Golden.SimpleT("K", 3, 32, 33), null, false, ParameterModifier.None, 3, 27))
    stmts5 := new List<Statement>()
    stmts5.Add(Golden.Return(Golden.Index(Golden.Ident("storage", 4, 34), Golden.Ident("key", 4, 42), false, 4, 41), 4, 27))
    stmts6 := new List<Statement>()
    stmts6.Add(Golden.ExprStmt(Golden.Assign(Golden.Index(Golden.Ident("storage", 5, 27), Golden.Ident("key", 5, 35), false, 5, 34), AssignmentOperator.Assign, Golden.Ident("value", 5, 42), 5, 40), 5, 27))
    members3.Add(Golden.IndexerF(plist4, Golden.SimpleT("V", 3, 36, 37), Golden.Block(stmts5, 4, 25), Golden.Block(stmts6, 5, 25), Modifiers.None, 3, 17))
    decls1.Add(Golden.ClassF("Dictionary", tps2, null, Golden.NoTypeRefs(), members3, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a constructor lands as the third member with its two parameters (was ParserTests.TestConstructorDeclaration)" {
    source := "\n            class Person {\n                Name: string\n                Age: int\n\n                constructor(name: string, age: int) {\n                    Name = name\n                    Age = age\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("Name", Golden.SimpleT("string", 3, 23, 29), null, Modifiers.None, PropertyModifier.None, 3, 17))
    members2.Add(Golden.FieldF("Age", Golden.SimpleT("int", 4, 22, 25), null, Modifiers.None, PropertyModifier.None, 4, 17))
    plist3 := new List<Parameter>()
    plist3.Add(Golden.Param("name", Golden.SimpleT("string", 6, 35, 41), null, false, ParameterModifier.None, 6, 29))
    plist3.Add(Golden.Param("age", Golden.SimpleT("int", 6, 48, 51), null, false, ParameterModifier.None, 6, 43))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("Name", 7, 21), AssignmentOperator.Assign, Golden.Ident("name", 7, 28), 7, 26), 7, 21))
    stmts4.Add(Golden.ExprStmt(Golden.Assign(Golden.Ident("Age", 8, 21), AssignmentOperator.Assign, Golden.Ident("age", 8, 27), 8, 25), 8, 21))
    members2.Add(Golden.CtorF(plist3, Golden.Block(stmts4, 6, 53), null, Modifiers.None, 6, 17))
    decls1.Add(Golden.ClassF("Person", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `virtual` on a member function, and a derived class's BaseClass (was ParserTests.TestVirtualMethods)" {
    source := "\n            class Animal {\n                virtual func MakeSound() {\n                    Console.WriteLine(\"Sound\")\n                }\n            }\n\n            class Dog : Animal {\n                func MakeSound() {\n                    Console.WriteLine(\"Bark\")\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    stmts3 := new List<Statement>()
    args4 := new List<Argument>()
    Golden.AddArg(args4, null, Golden.StrLit("\"Sound\"", 4, 39), ArgumentModifier.None)
    stmts3.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 4, 21), "WriteLine", false, 4, 28), args4, Golden.NoTypeArgs(), 4, 38), 4, 21))
    members2.Add(Golden.Func("MakeSound", Golden.NoParams(), null, Golden.Block(stmts3, 3, 42), null, null, Golden.NoConstraints(), Modifiers.Virtual, 3, 25))
    decls1.Add(Golden.ClassF("Animal", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    members5 := new List<Declaration>()
    stmts6 := new List<Statement>()
    args7 := new List<Argument>()
    Golden.AddArg(args7, null, Golden.StrLit("\"Bark\"", 10, 39), ArgumentModifier.None)
    stmts6.Add(Golden.ExprStmt(Golden.Call(Golden.Member(Golden.Ident("Console", 10, 21), "WriteLine", false, 10, 28), args7, Golden.NoTypeArgs(), 10, 38), 10, 21))
    members5.Add(Golden.Func("MakeSound", Golden.NoParams(), null, Golden.Block(stmts6, 9, 34), null, null, Golden.NoConstraints(), Modifiers.None, 9, 17))
    decls1.Add(Golden.ClassF("Dog", null, Golden.SimpleT("Animal", 8, 25, 31), Golden.NoTypeRefs(), members5, null, Modifiers.None, 8, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: three same-named member functions with different parameter lists (was ParserTests.TestMethodOverloading)" {
    source := "\n            class Calculator {\n                func Add(x: int): int {\n                    return x + 1\n                }\n\n                func Add(x: int, y: int): int {\n                    return x + y\n                }\n\n                func Add(x: double, y: double): double {\n                    return x + y\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    plist3 := new List<Parameter>()
    plist3.Add(Golden.Param("x", Golden.SimpleT("int", 3, 29, 32), null, false, ParameterModifier.None, 3, 26))
    stmts4 := new List<Statement>()
    stmts4.Add(Golden.Return(Golden.Bin(Golden.Ident("x", 4, 28), BinaryOperator.Add, Golden.IntLit("1", 4, 32), 4, 30), 4, 21))
    members2.Add(Golden.Func("Add", plist3, Golden.SimpleT("int", 3, 35, 38), Golden.Block(stmts4, 3, 39), null, null, Golden.NoConstraints(), Modifiers.None, 3, 17))
    plist5 := new List<Parameter>()
    plist5.Add(Golden.Param("x", Golden.SimpleT("int", 7, 29, 32), null, false, ParameterModifier.None, 7, 26))
    plist5.Add(Golden.Param("y", Golden.SimpleT("int", 7, 37, 40), null, false, ParameterModifier.None, 7, 34))
    stmts6 := new List<Statement>()
    stmts6.Add(Golden.Return(Golden.Bin(Golden.Ident("x", 8, 28), BinaryOperator.Add, Golden.Ident("y", 8, 32), 8, 30), 8, 21))
    members2.Add(Golden.Func("Add", plist5, Golden.SimpleT("int", 7, 43, 46), Golden.Block(stmts6, 7, 47), null, null, Golden.NoConstraints(), Modifiers.None, 7, 17))
    plist7 := new List<Parameter>()
    plist7.Add(Golden.Param("x", Golden.SimpleT("double", 11, 29, 35), null, false, ParameterModifier.None, 11, 26))
    plist7.Add(Golden.Param("y", Golden.SimpleT("double", 11, 40, 46), null, false, ParameterModifier.None, 11, 37))
    stmts8 := new List<Statement>()
    stmts8.Add(Golden.Return(Golden.Bin(Golden.Ident("x", 12, 28), BinaryOperator.Add, Golden.Ident("y", 12, 32), 12, 30), 12, 21))
    members2.Add(Golden.Func("Add", plist7, Golden.SimpleT("double", 11, 49, 55), Golden.Block(stmts8, 11, 56), null, null, Golden.NoConstraints(), Modifiers.None, 11, 17))
    decls1.Add(Golden.ClassF("Calculator", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: all five visibility spellings on fields and on member functions, including `protected internal` (was ParserTests.TestExplicitVisibilityModifiers)" {
    source := "\n            public class VisibilityBox {\n                public shown: int\n                private hidden: int\n                protected guarded: int\n                internal shared: int\n                protected internal bridge: int\n\n                public func Show() {\n                }\n\n                private func Hide() {\n                }\n\n                protected func Guard() {\n                }\n\n                internal func Share() {\n                }\n\n                protected internal func Bridge() {\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    members2.Add(Golden.FieldF("shown", Golden.SimpleT("int", 3, 31, 34), null, Modifiers.Public, PropertyModifier.None, 3, 24))
    members2.Add(Golden.FieldF("hidden", Golden.SimpleT("int", 4, 33, 36), null, Modifiers.Private, PropertyModifier.None, 4, 25))
    members2.Add(Golden.FieldF("guarded", Golden.SimpleT("int", 5, 36, 39), null, Modifiers.Protected, PropertyModifier.None, 5, 27))
    members2.Add(Golden.FieldF("shared", Golden.SimpleT("int", 6, 34, 37), null, Modifiers.Internal, PropertyModifier.None, 6, 26))
    members2.Add(Golden.FieldF("bridge", Golden.SimpleT("int", 7, 44, 47), null, Golden.Mods2(Modifiers.Internal, Modifiers.Protected), PropertyModifier.None, 7, 36))
    members2.Add(Golden.Func("Show", Golden.NoParams(), null, Golden.Block(Golden.NoStmts(), 9, 36), null, null, Golden.NoConstraints(), Modifiers.Public, 9, 24))
    members2.Add(Golden.Func("Hide", Golden.NoParams(), null, Golden.Block(Golden.NoStmts(), 12, 37), null, null, Golden.NoConstraints(), Modifiers.Private, 12, 25))
    members2.Add(Golden.Func("Guard", Golden.NoParams(), null, Golden.Block(Golden.NoStmts(), 15, 40), null, null, Golden.NoConstraints(), Modifiers.Protected, 15, 27))
    members2.Add(Golden.Func("Share", Golden.NoParams(), null, Golden.Block(Golden.NoStmts(), 18, 39), null, null, Golden.NoConstraints(), Modifiers.Internal, 18, 26))
    members2.Add(Golden.Func("Bridge", Golden.NoParams(), null, Golden.Block(Golden.NoStmts(), 21, 50), null, null, Golden.NoConstraints(), Golden.Mods2(Modifiers.Internal, Modifiers.Protected), 21, 36))
    decls1.Add(Golden.ClassF("VisibilityBox", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.Public, 2, 20))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `=>` on a member function fills ExpressionBody and leaves Body null (was ParserTests.TestExpressionBodiedMethod)" {
    source := "\n            class Calculator {\n                func Add(a: int, b: int): int => a + b\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    plist3 := new List<Parameter>()
    plist3.Add(Golden.Param("a", Golden.SimpleT("int", 3, 29, 32), null, false, ParameterModifier.None, 3, 26))
    plist3.Add(Golden.Param("b", Golden.SimpleT("int", 3, 37, 40), null, false, ParameterModifier.None, 3, 34))
    members2.Add(Golden.Func("Add", plist3, Golden.SimpleT("int", 3, 43, 46), null, Golden.Bin(Golden.Ident("a", 3, 50), BinaryOperator.Add, Golden.Ident("b", 3, 54), 3, 52), null, Golden.NoConstraints(), Modifiers.None, 3, 17))
    decls1.Add(Golden.ClassF("Calculator", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: an expression-bodied member function over a product (was ParserTests.TestExpressionBodiedMethodWithComplexExpression)" {
    source := "\n            class Calculator {\n                func Square(x: int): int => x * x\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    members2 := new List<Declaration>()
    plist3 := new List<Parameter>()
    plist3.Add(Golden.Param("x", Golden.SimpleT("int", 3, 32, 35), null, false, ParameterModifier.None, 3, 29))
    members2.Add(Golden.Func("Square", plist3, Golden.SimpleT("int", 3, 38, 41), null, Golden.Bin(Golden.Ident("x", 3, 45), BinaryOperator.Multiply, Golden.Ident("x", 3, 49), 3, 47), null, Golden.NoConstraints(), Modifiers.None, 3, 17))
    decls1.Add(Golden.ClassF("Calculator", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a top-level function's parameters, return type and block body (was ParserTests.TestSimpleFunctionDeclaration)" {
    source := "\n            func Add(x: int, y: int): int {\n                return x + y\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    plist2 := new List<Parameter>()
    plist2.Add(Golden.Param("x", Golden.SimpleT("int", 2, 25, 28), null, false, ParameterModifier.None, 2, 22))
    plist2.Add(Golden.Param("y", Golden.SimpleT("int", 2, 33, 36), null, false, ParameterModifier.None, 2, 30))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.Bin(Golden.Ident("x", 3, 24), BinaryOperator.Add, Golden.Ident("y", 3, 28), 3, 26), 3, 17))
    decls1.Add(Golden.Func("Add", plist2, Golden.SimpleT("int", 2, 39, 42), Golden.Block(stmts3, 2, 43), null, null, Golden.NoConstraints(), Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: a defaulted parameter carries its StringLiteralExpression while an undefaulted one carries null (was ParserTests.TestDefaultParameterValues)" {
    source := "\n            func Greet(name: string, greeting: string = \"Hello\") {\n                return greeting\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    plist2 := new List<Parameter>()
    plist2.Add(Golden.Param("name", Golden.SimpleT("string", 2, 30, 36), null, false, ParameterModifier.None, 2, 24))
    plist2.Add(Golden.Param("greeting", Golden.SimpleT("string", 2, 48, 54), Golden.StrLit("\"Hello\"", 2, 57), false, ParameterModifier.None, 2, 38))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.Ident("greeting", 3, 24), 3, 17))
    decls1.Add(Golden.Func("Greet", plist2, null, Golden.Block(stmts3, 2, 66), null, null, Golden.NoConstraints(), Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "020 s17 parser declarations: `this` parameters on a top-level function and on a static class's member (was ParserTests.TestExtensionMethod)" {
    source := "\n            func IsEmpty(this s: string): bool {\n                return s.Length == 0\n            }\n\n            static class StringExtensions {\n                static func ToUpperFirst(this s: string): string {\n                    return s.Substring(0, 1).ToUpper() + s.Substring(1)\n                }\n            }\n        "
    assert PdCensus(source) == ""
    actual := PdAst(source)
    decls1 := new List<Declaration>()
    plist2 := new List<Parameter>()
    plist2.Add(Golden.Param("s", Golden.SimpleT("string", 2, 34, 40), null, true, ParameterModifier.None, 2, 31))
    stmts3 := new List<Statement>()
    stmts3.Add(Golden.Return(Golden.Bin(Golden.Member(Golden.Ident("s", 3, 24), "Length", false, 3, 25), BinaryOperator.Equal, Golden.IntLit("0", 3, 36), 3, 33), 3, 17))
    decls1.Add(Golden.Func("IsEmpty", plist2, Golden.SimpleT("bool", 2, 43, 47), Golden.Block(stmts3, 2, 48), null, null, Golden.NoConstraints(), Modifiers.None, 2, 13))
    members4 := new List<Declaration>()
    plist5 := new List<Parameter>()
    plist5.Add(Golden.Param("s", Golden.SimpleT("string", 7, 50, 56), null, true, ParameterModifier.None, 7, 47))
    stmts6 := new List<Statement>()
    args7 := new List<Argument>()
    Golden.AddArg(args7, null, Golden.IntLit("0", 8, 40), ArgumentModifier.None)
    Golden.AddArg(args7, null, Golden.IntLit("1", 8, 43), ArgumentModifier.None)
    args8 := new List<Argument>()
    Golden.AddArg(args8, null, Golden.IntLit("1", 8, 70), ArgumentModifier.None)
    stmts6.Add(Golden.Return(Golden.Bin(Golden.Call(Golden.Member(Golden.Call(Golden.Member(Golden.Ident("s", 8, 28), "Substring", false, 8, 29), args7, Golden.NoTypeArgs(), 8, 39), "ToUpper", false, 8, 45), Golden.NoArgs(), Golden.NoTypeArgs(), 8, 53), BinaryOperator.Add, Golden.Call(Golden.Member(Golden.Ident("s", 8, 58), "Substring", false, 8, 59), args8, Golden.NoTypeArgs(), 8, 69), 8, 56), 8, 21))
    members4.Add(Golden.Func("ToUpperFirst", plist5, Golden.SimpleT("string", 7, 59, 65), Golden.Block(stmts6, 7, 66), null, null, Golden.NoConstraints(), Modifiers.Static, 7, 24))
    decls1.Add(Golden.ClassF("StringExtensions", null, null, Golden.NoTypeRefs(), members4, null, Modifiers.Static, 6, 20))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

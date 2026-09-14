namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL CONTRACTS FOR THE CONSTRUCTED-GENERIC-TYPE RECEIVER — `Vector<int>.Count`,
// `Box<int>.Create(42)`, `PerTypeState<int>.Count = 0`.
//
// THE WHOLE FEATURE IS ONE LOOKAHEAD, AND ITS NEGATIVE HALF IS THE POINT. `<` after a name is
// ambiguous, and until this node existed every reading of it was a comparison: `Vector<int>.Count`
// parsed as `Vector < int > .Count` and reported an NL202 about comparing a `Vector` with an
// `Int32` followed by an NL102 about a `.` with no receiver in front of it. The new rule adds
// exactly one shape — a well-formed type-argument list whose close is followed DIRECTLY by a `.` —
// and this file states BOTH halves: the shapes that now build a `GenericTypeExpression`, and the
// four comparison shapes that must keep building the `BinaryExpression` they always built.
//
// `lower < value && value > upper` IS PINNED WITH ITS LITERAL BODY, not with a corrected one: it is
// the shape whose two angle brackets look most like a type-argument list, and a reading that
// "fixed" its logic would hide exactly the regression it exists to catch.
//
// THE RECEIVER'S `GenericTypeReference` IS BYTE-IDENTICAL TO AN ANNOTATION'S. It comes from the same
// `ParseCallTypeArguments` / `ParseMaterializedTypeReference` pair a generic CALL uses, so the
// nested / array / nullable argument spans restated here are the spans the generic-call tranche
// already pins next door — the new claim is that a `.` close reaches them at all.
//
// THE HELPERS ARE REUSED, NOT RE-COPIED: `PsAst` / `PsCensus` from `ColumnarParserStatements.tests.nl`,
// `AstEq.Diff` and `Golden.*` from `ColumnarParserAst.tests.nl`. Two entries were added there — the
// `GenericTypeExpression` field list and the `Golden.GenericTypeE` builder.

// ---- (a) THE POSITIVE SHAPES ----
test "generic type receiver: `Vector<int>.Count` is a MemberAccessExpression over a GenericTypeExpression anchored on the type NAME, not a comparison chain" {
    source := "\n            func Test() {\n                result := Vector<int>.Count\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    typereference3 := new List<TypeReference>()
    typereference3.Add(Golden.SimpleT("int", 3, 34, 37))
    statement2.Add(Golden.VarDecl("result", null, Golden.Member(Golden.GenericTypeE("Vector", typereference3, 3, 27, 38), "Count", false, 3, 38), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver: a NESTED argument list closes on a SPLIT `>>` — `Dictionary<string, List<int>>.Count` gives the inner `List<int>` the first angle and the outer receiver both" {
    source := "\n            func Test() {\n                result := Dictionary<string, List<int>>.Count\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    typereference3 := new List<TypeReference>()
    typereference4 := new List<TypeReference>()
    typereference4.Add(Golden.SimpleT("int", 3, 51, 54))
    typereference3.Add(Golden.SimpleT("string", 3, 38, 44))
    typereference3.Add(Golden.GenericT("List", typereference4, 3, 46, 55))
    statement2.Add(Golden.VarDecl("result", null, Golden.Member(Golden.GenericTypeE("Dictionary", typereference3, 3, 27, 56), "Count", false, 3, 56), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver: a QUALIFIED head — `System.Numerics.Vector<int>.Count` — folds the whole dotted name into the type reference and leaves ONE member access behind" {
    source := "\n            func Test() {\n                result := System.Numerics.Vector<int>.Count\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    typereference3 := new List<TypeReference>()
    typereference3.Add(Golden.SimpleT("int", 3, 50, 53))
    statement2.Add(Golden.VarDecl("result", null, Golden.Member(Golden.GenericTypeE("System.Numerics.Vector", typereference3, 3, 27, 54), "Count", false, 3, 54), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver: an ARRAY type argument `Box<int[]>.Value` keeps the bracket-blind element span the generic-call tranche pins" {
    source := "\n            func Test() {\n                result := Box<int[]>.Value\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    typereference3 := new List<TypeReference>()
    typereference3.Add(Golden.ArrayT(Golden.SimpleT("int", 3, 31, 34), 3, 31, 36))
    statement2.Add(Golden.VarDecl("result", null, Golden.Member(Golden.GenericTypeE("Box", typereference3, 3, 27, 37), "Value", false, 3, 37), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver: a NULLABLE type argument `Box<int?>.Value` covers its question mark while the inner simple type stops at the name" {
    source := "\n            func Test() {\n                result := Box<int?>.Value\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    typereference3 := new List<TypeReference>()
    typereference3.Add(Golden.NullableT(Golden.SimpleT("int", 3, 31, 34), 3, 31, 35))
    statement2.Add(Golden.VarDecl("result", null, Golden.Member(Golden.GenericTypeE("Box", typereference3, 3, 27, 36), "Value", false, 3, 36), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver: `Box<int>.Create(42)` is a CALL whose callee is the member access — the receiver continues through the ordinary postfix loop, and the call's own TypeArguments stay NULL" {
    source := "\n            func Test() {\n                result := Box<int>.Create(42)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    argument3 := new List<Argument>()
    argument3.Add(Golden.ArgF(null, Golden.IntLit("42", 3, 43), ArgumentModifier.None))
    typereference4 := new List<TypeReference>()
    typereference4.Add(Golden.SimpleT("int", 3, 31, 34))
    statement2.Add(Golden.VarDecl("result", null, Golden.Call(Golden.Member(Golden.GenericTypeE("Box", typereference4, 3, 27, 35), "Create", false, 3, 35), argument3, Golden.NoTypeArgs(), 3, 42), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver: `PerTypeState<int>.Count = 0` is an ASSIGNMENT whose target is the member access, so a static field on a constructed type is a write target" {
    source := "\n            func Test() {\n                PerTypeState<int>.Count = 0\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    typereference3 := new List<TypeReference>()
    typereference3.Add(Golden.SimpleT("int", 3, 30, 33))
    statement2.Add(Golden.ExprStmt(Golden.Assign(Golden.Member(Golden.GenericTypeE("PerTypeState", typereference3, 3, 17, 34), "Count", false, 3, 34), AssignmentOperator.Assign, Golden.IntLit("0", 3, 43), 3, 41), 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver: `EqualityComparer<int>.Default.Equals(a, b)` chains a SECOND member access over the static one before the call" {
    source := "\n            func Test() {\n                result := EqualityComparer<int>.Default.Equals(a, b)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    argument3 := new List<Argument>()
    argument3.Add(Golden.ArgF(null, Golden.Ident("a", 3, 64), ArgumentModifier.None))
    argument3.Add(Golden.ArgF(null, Golden.Ident("b", 3, 67), ArgumentModifier.None))
    typereference4 := new List<TypeReference>()
    typereference4.Add(Golden.SimpleT("int", 3, 44, 47))
    statement2.Add(Golden.VarDecl("result", null, Golden.Call(Golden.Member(Golden.Member(Golden.GenericTypeE("EqualityComparer", typereference4, 3, 27, 48), "Default", false, 3, 48), "Equals", false, 3, 56), argument3, Golden.NoTypeArgs(), 3, 63), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- (b) THE COMPARISON CONTROLS ----

test "generic type receiver control: `lower < value && value > upper` stays two comparisons under an `&&` — the shape whose angle brackets look most like a type-argument list" {
    source := "\n            func Test() {\n                result := lower < value && value > upper\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    left3 := Golden.Bin(Golden.Ident("lower", 3, 27), BinaryOperator.Less, Golden.Ident("value", 3, 35), 3, 33)
    right4 := Golden.Bin(Golden.Ident("value", 3, 44), BinaryOperator.Greater, Golden.Ident("upper", 3, 52), 3, 50)
    statement2.Add(Golden.VarDecl("result", null, Golden.Bin(left3, BinaryOperator.And, right4, 3, 41), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver control: `x < y.Z` stays a comparison against a member access — a DOT inside the candidate argument list is not the dot the rule is looking for" {
    source := "\n            func Test() {\n                result := x < y.Z\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    statement2.Add(Golden.VarDecl("result", null, Golden.Bin(Golden.Ident("x", 3, 27), BinaryOperator.Less, Golden.Member(Golden.Ident("y", 3, 31), "Z", false, 3, 32), 3, 29), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver control: `i < n.Length && j > m.Count` stays two comparisons — both operands END in a member access and neither `>` is a type-argument close" {
    source := "\n            func Test() {\n                result := i < n.Length && j > m.Count\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    left3 := Golden.Bin(Golden.Ident("i", 3, 27), BinaryOperator.Less, Golden.Member(Golden.Ident("n", 3, 31), "Length", false, 3, 32), 3, 29)
    right4 := Golden.Bin(Golden.Ident("j", 3, 43), BinaryOperator.Greater, Golden.Member(Golden.Ident("m", 3, 47), "Count", false, 3, 48), 3, 45)
    statement2.Add(Golden.VarDecl("result", null, Golden.Bin(left3, BinaryOperator.And, right4, 3, 40), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver control: `a < b > (c)` still reads as the GENERIC CALL it read as before — the new rule fires only on a `.` close, so the `(` close is untouched" {
    source := "\n            func Test() {\n                result := a < b > (c)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    argument3 := new List<Argument>()
    argument3.Add(Golden.ArgF(null, Golden.Ident("c", 3, 36), ArgumentModifier.None))
    typereference4 := new List<TypeReference>()
    typereference4.Add(Golden.SimpleT("b", 3, 31, 32))
    statement2.Add(Golden.VarDecl("result", null, Golden.Call(Golden.Ident("a", 3, 27), argument3, typereference4, 3, 35), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "generic type receiver control: `Method<int>(42)` is still a generic CALL with its type arguments on the call, not a receiver followed by an orphan paren" {
    source := "\n            func Test() {\n                result := Method<int>(42)\n            }\n        "
    assert PsCensus(source) == ""
    actual := PsAst(source)
    declaration1 := new List<Declaration>()
    statement2 := new List<Statement>()
    argument3 := new List<Argument>()
    argument3.Add(Golden.ArgF(null, Golden.IntLit("42", 3, 39), ArgumentModifier.None))
    typereference4 := new List<TypeReference>()
    typereference4.Add(Golden.SimpleT("int", 3, 34, 37))
    statement2.Add(Golden.VarDecl("result", null, Golden.Call(Golden.Ident("Method", 3, 27), argument3, typereference4, 3, 38), VariableKind.Let, 3, 17))
    declaration1.Add(Golden.Func("Test", Golden.NoParams(), null, Golden.Block(statement2, 2, 25), null, null, null, Modifiers.None, 2, 13))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, declaration1, 2, 13)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- (c) THE FORMATTER ROUND TRIP ----
//
// A NODE THE FORMATTER CANNOT SPELL IS A FILE THAT WILL NOT RE-PARSE, and `FormatterWalk`'s unhandled
// arm THROWS rather than emitting something plausible — so a missing arm here is a crash, not a
// silent corruption. These pin the text as well as the survival: the nested form must come back with
// its `>>` unspaced, because that is what the developer wrote and what the split-`>>` reader accepts.

func GtrFormat(source: string): string {
    formatted := ""
    ast := PsAst(source)
    if ast != null {
        formatter := new Formatter(new FormatterConfig())
        formatted = formatter.Format(ast, null)
    }

    return formatted
}

test "generic type receiver: the formatter round-trips every receiver shape byte-exactly" {
    source := "func Lanes(): int {\n    return Vector<int>.Count\n}\n\nfunc Make(): int {\n    return Box<int>.Create(42)\n}\n\nfunc Pair(): int {\n    return Dictionary<string, List<int>>.Count\n}\n\nfunc Between(value: int, lower: int, upper: int): bool {\n    return lower < value && value > upper\n}\n"
    assert GtrFormat(source) == source
}

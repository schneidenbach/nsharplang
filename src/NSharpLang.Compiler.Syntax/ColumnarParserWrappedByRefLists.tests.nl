namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// A BY-REFERENCE ELEMENT AT THE HEAD OF A LINE OF A WRAPPED LIST.
//
// The parser ends a parameter or argument list early when a LATER line begins with a token that
// starts a statement, a declaration or a modifier (`IsContinuationRecoveryBoundary`), so the outer
// recovery can resynchronise on an unclosed `(`. `ref` is in the declaration-keyword table because it
// heads `ref struct`, and the boundary asked the table alone: a list wrapped one element per line
// stopped just before its `ref` line, reported NL107 for the unclosed `(` and NL101 on the `ref`,
// and the author's only way out was to write the whole signature on one line. The boundary now
// reads `ref` as a declaration only when `struct` follows it.
//
// The rows pin each position a `ref` line can take (first, middle, last), every modifier a parameter
// can lead with (`ref`, `out`, `in`, `params`, `this`) and the `&T` spelling, comments between the
// lines, a constructor's list, a call's argument list, and the three shapes that must STILL end the
// list: a trailing comma, a real `ref struct`, and a `ref` element at or left of the column the
// declaration opened on. Each positive row also pins that the source parses with NO diagnostic.
test "a wrapped parameter list reads a `ref` parameter on its LAST line" {
    source := "func F(\n    a: int,\n    ref b: int\n) { }"
    assert PsCensus(source) == "", PsCensus(source)
    params1 := new List<Parameter>()
    params1.Add(Golden.Param("a", Golden.SimpleT("int", 2, 8, 11), null, false, ParameterModifier.None, 2, 5))
    params1.Add(Golden.Param("b", Golden.SimpleT("int", 3, 12, 15), null, false, ParameterModifier.Ref, 3, 9))
    decls2 := new List<Declaration>()
    decls2.Add(Golden.Func("F", params1, null, Golden.Block(Golden.NoStmts(), 4, 3), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls2, 1, 1)
    assert AstEq.Diff(expected, PsAst(source), "unit") == ""
}

test "a wrapped parameter list reads a `ref` parameter on its FIRST line" {
    source := "func F(\n    ref a: int,\n    b: int\n) { }"
    assert PsCensus(source) == "", PsCensus(source)
    params1 := new List<Parameter>()
    params1.Add(Golden.Param("a", Golden.SimpleT("int", 2, 12, 15), null, false, ParameterModifier.Ref, 2, 9))
    params1.Add(Golden.Param("b", Golden.SimpleT("int", 3, 8, 11), null, false, ParameterModifier.None, 3, 5))
    decls2 := new List<Declaration>()
    decls2.Add(Golden.Func("F", params1, null, Golden.Block(Golden.NoStmts(), 4, 3), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls2, 1, 1)
    assert AstEq.Diff(expected, PsAst(source), "unit") == ""
}

test "a wrapped parameter list reads a `ref` parameter on a MIDDLE line, and keeps the parameter after it" {
    source := "func F(\n    a: int,\n    ref b: int,\n    c: int\n) { }"
    assert PsCensus(source) == "", PsCensus(source)
    params1 := new List<Parameter>()
    params1.Add(Golden.Param("a", Golden.SimpleT("int", 2, 8, 11), null, false, ParameterModifier.None, 2, 5))
    params1.Add(Golden.Param("b", Golden.SimpleT("int", 3, 12, 15), null, false, ParameterModifier.Ref, 3, 9))
    params1.Add(Golden.Param("c", Golden.SimpleT("int", 4, 8, 11), null, false, ParameterModifier.None, 4, 5))
    decls2 := new List<Declaration>()
    decls2.Add(Golden.Func("F", params1, null, Golden.Block(Golden.NoStmts(), 5, 3), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls2, 1, 1)
    assert AstEq.Diff(expected, PsAst(source), "unit") == ""
}

test "every parameter modifier leads its own line of a wrapped list: `out`, `in`, `ref` and `params`" {
    source := "func F(\n    out a: int,\n    in b: int,\n    ref c: int,\n    params d: int[]\n) { }"
    assert PsCensus(source) == "", PsCensus(source)
    params1 := new List<Parameter>()
    params1.Add(Golden.Param("a", Golden.SimpleT("int", 2, 12, 15), null, false, ParameterModifier.Out, 2, 9))
    params1.Add(Golden.Param("b", Golden.SimpleT("int", 3, 11, 14), null, false, ParameterModifier.In, 3, 8))
    params1.Add(Golden.Param("c", Golden.SimpleT("int", 4, 12, 15), null, false, ParameterModifier.Ref, 4, 9))
    params1.Add(Golden.Param("d", Golden.ArrayT(Golden.SimpleT("int", 5, 15, 18), 5, 15, 20), null, false, ParameterModifier.Params, 5, 12))
    decls2 := new List<Declaration>()
    decls2.Add(Golden.Func("F", params1, null, Golden.Block(Golden.NoStmts(), 6, 3), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls2, 1, 1)
    assert AstEq.Diff(expected, PsAst(source), "unit") == ""
}

test "an extension receiver's `this` and a `ref` parameter each lead a line of a wrapped list" {
    source := "func Bump(\n    this s: string,\n    ref n: int\n) { }"
    assert PsCensus(source) == "", PsCensus(source)
    params1 := new List<Parameter>()
    params1.Add(Golden.Param("s", Golden.SimpleT("string", 2, 13, 19), null, true, ParameterModifier.None, 2, 10))
    params1.Add(Golden.Param("n", Golden.SimpleT("int", 3, 12, 15), null, false, ParameterModifier.Ref, 3, 9))
    decls2 := new List<Declaration>()
    decls2.Add(Golden.Func("Bump", params1, null, Golden.Block(Golden.NoStmts(), 4, 3), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls2, 1, 1)
    assert AstEq.Diff(expected, PsAst(source), "unit") == ""
}

test "the `&T` spelling of a by-reference parameter reads on its own line of a wrapped list" {
    source := "func F(\n    a: int,\n    b: &int\n) { }"
    assert PsCensus(source) == "", PsCensus(source)
    params1 := new List<Parameter>()
    params1.Add(Golden.Param("a", Golden.SimpleT("int", 2, 8, 11), null, false, ParameterModifier.None, 2, 5))
    params1.Add(Golden.Param("b", Golden.ByRefT(Golden.SimpleT("int", 3, 9, 12), 3, 8, 12), null, false, ParameterModifier.None, 3, 5))
    decls2 := new List<Declaration>()
    decls2.Add(Golden.Func("F", params1, null, Golden.Block(Golden.NoStmts(), 4, 3), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls2, 1, 1)
    assert AstEq.Diff(expected, PsAst(source), "unit") == ""
}

test "line and block comments between the lines of a wrapped list leave a `ref` parameter after them intact" {
    source := "func F(\n    a: int, // the value\n    // the slot it lands in\n    /* by reference */\n    ref b: int\n) { }"
    assert PsCensus(source) == "", PsCensus(source)
    params1 := new List<Parameter>()
    params1.Add(Golden.Param("a", Golden.SimpleT("int", 2, 8, 11), null, false, ParameterModifier.None, 2, 5))
    params1.Add(Golden.Param("b", Golden.SimpleT("int", 5, 12, 15), null, false, ParameterModifier.Ref, 5, 9))
    decls2 := new List<Declaration>()
    decls2.Add(Golden.Func("F", params1, null, Golden.Block(Golden.NoStmts(), 6, 3), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls2, 1, 1)
    assert AstEq.Diff(expected, PsAst(source), "unit") == ""
}

test "a constructor's wrapped parameter list reads a `ref` parameter on its own line" {
    source := "class Box {\n    constructor(\n        a: int,\n        ref b: int\n    ) { }\n}"
    assert PsCensus(source) == "", PsCensus(source)
    params1 := new List<Parameter>()
    params1.Add(Golden.Param("a", Golden.SimpleT("int", 3, 12, 15), null, false, ParameterModifier.None, 3, 9))
    params1.Add(Golden.Param("b", Golden.SimpleT("int", 4, 16, 19), null, false, ParameterModifier.Ref, 4, 13))
    members2 := new List<Declaration>()
    members2.Add(Golden.CtorF(params1, Golden.Block(Golden.NoStmts(), 5, 7), null, Modifiers.None, 2, 5))
    decls3 := new List<Declaration>()
    decls3.Add(Golden.ClassF("Box", null, null, Golden.NoTypeRefs(), members2, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls3, 1, 1)
    assert AstEq.Diff(expected, PsAst(source), "unit") == ""
}

test "a call's wrapped argument list reads a `ref` argument at the head of each line" {
    source := "func Main() {\n    x := 1\n    y := 2\n    Swap(\n        ref x,\n        ref y\n    )\n}"
    assert PsCensus(source) == "", PsCensus(source)
    stmts1 := new List<Statement>()
    stmts1.Add(Golden.VarDecl("x", null, Golden.IntLit("1", 2, 10), VariableKind.Let, 2, 5))
    stmts1.Add(Golden.VarDecl("y", null, Golden.IntLit("2", 3, 10), VariableKind.Let, 3, 5))
    args2 := new List<Argument>()
    args2.Add(Golden.ArgF(null, Golden.Ident("x", 5, 13), ArgumentModifier.Ref))
    args2.Add(Golden.ArgF(null, Golden.Ident("y", 6, 13), ArgumentModifier.Ref))
    stmts1.Add(Golden.ExprStmt(Golden.Call(Golden.Ident("Swap", 4, 5), args2, Golden.NoTypeArgs(), 4, 9), 4, 5))
    decls3 := new List<Declaration>()
    decls3.Add(Golden.Func("Main", Golden.NoParams(), null, Golden.Block(stmts1, 1, 13), null, null, null, Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls3, 1, 1)
    assert AstEq.Diff(expected, PsAst(source), "unit") == ""
}

// ---- the shapes that still END the list ----------------------------------------------------------

test "a trailing comma after a wrapped `ref` parameter is the one trailing-comma NL102, exactly as after an unmodified one" {
    // N# rejects a trailing comma in a parameter list. What the fix owes is that a `ref` last line
    // reaches THAT diagnostic — spanning the last parameter's name through the comma — rather than
    // the NL107/NL101 cascade the early boundary produced before the `,` was ever read.
    refForm := "func F(\n    a: int,\n    ref b: int,\n) { }"
    plainForm := "func F(\n    a: int,\n    b: int,\n) { }"
    assert PsCensus(refForm) == "NL102@3:9+7;", PsCensus(refForm)
    assert PsCensus(plainForm) == "NL102@3:5+7;", PsCensus(plainForm)
}

test "a real `ref struct` on a later line still ends an unclosed parameter list" {
    // The lookahead is what separates the two readings: `ref` followed by `struct` is a declaration,
    // so the list stops before it exactly as it stops before `class` or `func`.
    refStruct := "func F(\n    a: int,\n    ref struct S { }"
    classForm := "func F(\n    a: int,\n    class S { }"
    assert PsCensus(refStruct) == "NL107@1:6+1;", PsCensus(refStruct)
    assert PsCensus(classForm) == PsCensus(refStruct), PsCensus(classForm)
}

test "a `ref` parameter at or left of the declaration's own column still ends the list, as any element there does" {
    // The column rule is unchanged: an element must sit strictly right of the line that opened the
    // list. `ref b` at the member's own column ends the list exactly where an unmodified `b` does.
    refForm := "class C {\n    func F(\n    ref b: int\n    ) { }\n}"
    plainForm := "class C {\n    func F(\n    b: int\n    ) { }\n}"
    assert PsCensus(refForm).StartsWith("NL107@2:10+1;"), PsCensus(refForm)
    assert PsCensus(plainForm).StartsWith("NL107@2:10+1;"), PsCensus(plainForm)
}

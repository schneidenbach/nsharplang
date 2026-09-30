namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE CANONICAL CONTRACTS FOR `SemanticModel`, IN N#.
//
// These replace `tests/SemanticModelTests.cs`, the last canonical C# assertion layer over
// `SemanticModel.nl`. The model is what the analyser hands the LANGUAGE SERVER: every name it
// bound, every expression type it computed, and the scope tree that says which of those names is
// visible at a given line and column.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. The model is constructed, its values are
// dependency-assembly `TypeInfo`s, and both decline at emit from a `tests/native` project.
//
// WHY THE ANSWERS ARE READ THROUGH `SemModelText`. `ToString()` on a user N# class needs the
// receiver to cross as `object` first, and every answer here is a nullable `TypeInfo?` — so one
// helper narrows, converts and renders, and answers `null` for an absent binding. That makes the
// "no such name" assertions and the "this name has this type" assertions the same shape.
//
// WHY A LOCAL IS NEVER CALLED `scoped`. `scoped` is `TokenType.Scoped`, a reserved word; a local of
// that name takes the WHOLE FILE down at `parse.test` with no further detail.
//
// THE FIVE THINGS IT IS EASY TO GET WRONG:
//
// (1) THE FLAT LOOKUP IS ORDERED, AND THE ORDER IS VARIABLES, PROPERTIES, FIELDS, FUNCTIONS, TYPES.
// The deleted file pinned one pair of that chain (a variable outranks a type). All five ranks are
// pinned here, because the chain is what makes a local shadow a field of the same name.
//
// (2) A FUNCTION DOES NOT LOOK UP AS ITSELF. `LookupIdentifier` routes a `FunctionTypeInfo`
// through `GetFunctionLookupType`, which answers its RETURN type when it has one — so `getName`
// bound to a function returning `string` looks up as `string`. A function with no return type
// answers the function itself.
//
// (3) SCOPE LOOKUP PICKS THE DEEPEST CONTAINING SCOPE, NOT THE LAST ONE WRITTEN. Every scope
// containing the position is considered and the one with the greatest DEPTH wins, so shadowing
// works at any nesting and in any recording order.
//
// (4) AN UNCLOSED SCOPE CONTAINS NOTHING. `ContainsPosition` answers false while `EndLine` is 0, so
// a scope that was opened and never closed is invisible to position lookup — which is what stops a
// half-parsed file from reporting a binding that does not exist yet.
//
// (5) THE SCOPE BOUNDS ARE INCLUSIVE AT BOTH ENDS, AND COLUMNS ONLY MATTER ON THE BOUNDARY LINES.
// A position exactly at the start or exactly at the end is INSIDE; one column earlier or later is
// outside; and on any line strictly between them the column is not consulted at all.

// The one reader every assertion goes through: narrow, cross as `object`, render -- and answer
// `null` for an absent binding, so "no such name" is the same assertion shape as "this type".
func SemModelText(typeInfo: TypeInfo?): string? {
    if typeInfo != null {
        typeObject := typeInfo as object
        return typeObject.ToString()
    }

    return null
}

func SemModelFunctionReturning(returnType: TypeInfo): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.ReturnType = returnType
    return signature
}

// ---- the flat tables ------------------------------------------------------------------------------

// Successor to SemanticModel_RecordVariable_CanLookupVariable.
test "semantic model records a variable that can be looked up" {
    model := new SemanticModel()
    model.RecordVariable("x", BuiltInTypes.Int)

    result := model.LookupIdentifier("x")

    assert result != null
    assert SemModelText(result) == "int"
}

// Successor to SemanticModel_RecordFunction_CanLookupFunction.
test "semantic model records a function that can be looked up" {
    model := new SemanticModel()
    model.RecordFunction("getName", BuiltInTypes.String)

    result := model.LookupIdentifier("getName")

    assert result != null
    assert SemModelText(result) == "string"
}

// Successor to SemanticModel_RecordProperty_CanLookupProperty.
test "semantic model records a property that can be looked up" {
    model := new SemanticModel()
    model.RecordProperty("IsActive", BuiltInTypes.Bool)

    result := model.LookupIdentifier("IsActive")

    assert result != null
    assert SemModelText(result) == "bool"
}

// Successor to SemanticModel_RecordField_CanLookupField.
test "semantic model records a field that can be looked up" {
    model := new SemanticModel()
    model.RecordField("temperature", BuiltInTypes.Double)

    result := model.LookupIdentifier("temperature")

    assert result != null
    assert SemModelText(result) == "double"
}

// Successor to SemanticModel_LookupIdentifier_ReturnsNullForUnknownIdentifier.
test "semantic model looks up nothing for an unknown identifier" {
    model := new SemanticModel()

    assert model.LookupIdentifier("unknownVariable") == null

    // Not in the deleted file: recording OTHER names does not make this one resolvable, and the
    // tables are case-sensitive.
    model.RecordVariable("known", BuiltInTypes.Int)
    assert model.LookupIdentifier("unknownVariable") == null
    assert model.LookupIdentifier("Known") == null
    assert model.LookupIdentifier("") == null
}

// Successor to SemanticModel_MultipleVariables_AllLookupable.
test "semantic model looks up every recorded variable" {
    model := new SemanticModel()

    model.RecordVariable("x", BuiltInTypes.Int)
    model.RecordVariable("name", BuiltInTypes.String)
    model.RecordVariable("active", BuiltInTypes.Bool)

    assert SemModelText(model.LookupIdentifier("x")) == "int"
    assert SemModelText(model.LookupIdentifier("name")) == "string"
    assert SemModelText(model.LookupIdentifier("active")) == "bool"
}

// Successor to SemanticModel_OverwriteVariable_UsesLatestType.
test "semantic model uses the latest type for an overwritten variable" {
    model := new SemanticModel()

    model.RecordVariable("x", BuiltInTypes.Int)
    model.RecordVariable("x", BuiltInTypes.String)

    assert SemModelText(model.LookupIdentifier("x")) == "string"

    // Not in the deleted file: the same last-write-wins rule holds for every other flat table.
    model.RecordProperty("p", BuiltInTypes.Int)
    model.RecordProperty("p", BuiltInTypes.Bool)
    assert SemModelText(model.LookupIdentifier("p")) == "bool"

    model.RecordField("f", BuiltInTypes.Int)
    model.RecordField("f", BuiltInTypes.Double)
    assert SemModelText(model.LookupIdentifier("f")) == "double"
}

// Successor to SemanticModel_LookupIdentifier_PrioritizesVariablesOverTypes.
test "semantic model prioritizes variables over types" {
    model := new SemanticModel()

    model.RecordVariable("Foo", BuiltInTypes.Int)
    model.RecordType("Foo", BuiltInTypes.String)

    result := model.LookupIdentifier("Foo")

    assert result != null
    assert SemModelText(result) == "int"
}

// NOT IN THE DELETED FILE. All FIVE ranks of the chain, each pinned against the rank below it —
// the deleted file pinned only the outermost pair.
test "semantic model ranks the five flat tables in order" {
    model := new SemanticModel()
    model.RecordVariable("n", BuiltInTypes.Int)
    model.RecordProperty("n", BuiltInTypes.String)
    model.RecordField("n", BuiltInTypes.Bool)
    model.RecordFunction("n", BuiltInTypes.Double)
    model.RecordType("n", BuiltInTypes.Char)
    assert SemModelText(model.LookupIdentifier("n")) == "int"

    withoutVariable := new SemanticModel()
    withoutVariable.RecordProperty("n", BuiltInTypes.String)
    withoutVariable.RecordField("n", BuiltInTypes.Bool)
    withoutVariable.RecordFunction("n", BuiltInTypes.Double)
    withoutVariable.RecordType("n", BuiltInTypes.Char)
    assert SemModelText(withoutVariable.LookupIdentifier("n")) == "string"

    withoutProperty := new SemanticModel()
    withoutProperty.RecordField("n", BuiltInTypes.Bool)
    withoutProperty.RecordFunction("n", BuiltInTypes.Double)
    withoutProperty.RecordType("n", BuiltInTypes.Char)
    assert SemModelText(withoutProperty.LookupIdentifier("n")) == "bool"

    withoutField := new SemanticModel()
    withoutField.RecordFunction("n", BuiltInTypes.Double)
    withoutField.RecordType("n", BuiltInTypes.Char)
    assert SemModelText(withoutField.LookupIdentifier("n")) == "double"

    typeOnly := new SemanticModel()
    typeOnly.RecordType("n", BuiltInTypes.Char)
    assert SemModelText(typeOnly.LookupIdentifier("n")) == "char"
}

// NOT IN THE DELETED FILE. A function looks up as what CALLING it yields, which is the rule that
// makes `getName` usable as a `string` in a completion list.
test "semantic model looks a function up as its return type" {
    model := new SemanticModel()
    model.RecordFunction("getName", SemModelFunctionReturning(BuiltInTypes.String))

    assert SemModelText(model.LookupIdentifier("getName")) == "string"

    // A function with no return type answers the function itself rather than null.
    noReturn := new SemanticModel()
    noReturn.RecordFunction("run", new FunctionTypeInfo())
    assert noReturn.LookupIdentifier("run") != null

    // The rule is the FUNCTION table's alone: a variable bound to a function type is not unwrapped.
    variableBound := new SemanticModel()
    variableBound.RecordVariable("handler", SemModelFunctionReturning(BuiltInTypes.String))
    assert SemModelText(variableBound.LookupIdentifier("handler")) != "string"
}

// NOT IN THE DELETED FILE AT ALL. The per-type member table, which nothing in the C# reached.
test "semantic model records and reads type members" {
    model := new SemanticModel()

    assert model.GetTypeMembers("Widget") == null

    model.RecordTypeMember("Widget", "Size", BuiltInTypes.Int)
    model.RecordTypeMember("Widget", "Name", BuiltInTypes.String)

    members := model.GetTypeMembers("Widget")
    assert members != null
    if members != null {
        assert members.Count == 2
        assert members.ContainsKey("Size")
        assert SemModelText(members["Size"]) == "int"
        assert SemModelText(members["Name"]) == "string"
    }

    // A second type keeps its own table, and a re-recorded member is replaced in place.
    model.RecordTypeMember("Gadget", "Size", BuiltInTypes.Double)
    model.RecordTypeMember("Widget", "Size", BuiltInTypes.Bool)

    widget := model.GetTypeMembers("Widget")
    gadget := model.GetTypeMembers("Gadget")
    assert widget != null
    assert gadget != null
    if widget != null {
        assert widget.Count == 2
        assert SemModelText(widget["Size"]) == "bool"
    }
    if gadget != null {
        assert gadget.Count == 1
        assert SemModelText(gadget["Size"]) == "double"
    }

    assert model.GetTypeMembers("Missing") == null
}

// ---- the position tables --------------------------------------------------------------------------

// Successor to SemanticModel_RecordExpressionType_CanLookupByPosition.
test "semantic model records an expression type that can be looked up by position" {
    model := new SemanticModel()

    model.RecordExpressionType(4, 12, BuiltInTypes.Bool)

    result := model.LookupTypeAtPosition(4, 12)

    assert result != null
    assert SemModelText(result) == "bool"
}

// NOT IN THE DELETED FILE. The position key is exact in BOTH coordinates, and the expression table
// is a different table from the type-reference one — a lookup in one never answers from the other.
test "semantic model keys expression types by the exact position" {
    model := new SemanticModel()
    model.RecordExpressionType(4, 12, BuiltInTypes.Bool)
    model.RecordExpressionType(4, 13, BuiltInTypes.Int)

    assert SemModelText(model.LookupTypeAtPosition(4, 12)) == "bool"
    assert SemModelText(model.LookupTypeAtPosition(4, 13)) == "int"
    assert model.LookupTypeAtPosition(5, 12) == null
    assert model.LookupTypeAtPosition(4, 11) == null

    // Last write wins here too.
    model.RecordExpressionType(4, 12, BuiltInTypes.String)
    assert SemModelText(model.LookupTypeAtPosition(4, 12)) == "string"

    // The type-reference table is separate in both directions.
    assert model.LookupTypeReferenceAtPosition(4, 12) == null
    model.RecordTypeReference(9, 3, BuiltInTypes.Double)
    assert SemModelText(model.LookupTypeReferenceAtPosition(9, 3)) == "double"
    assert model.LookupTypeAtPosition(9, 3) == null
}

// NOT IN THE DELETED FILE. `RecordTypeReference` REFUSES a non-positive position rather than
// storing an anchor at (0, 0) — the gate that keeps synthesised references out of go-to-definition.
test "semantic model refuses a type reference with no position" {
    model := new SemanticModel()

    model.RecordTypeReference(0, 3, BuiltInTypes.Int)
    model.RecordTypeReference(3, 0, BuiltInTypes.Int)
    model.RecordTypeReference(-1, -1, BuiltInTypes.Int)

    assert model.TypeReferenceTypes.Count == 0
    assert model.LookupTypeReferenceAtPosition(0, 3) == null
    assert model.LookupTypeReferenceAtPosition(3, 0) == null

    model.RecordTypeReference(1, 1, BuiltInTypes.Int)
    assert model.TypeReferenceTypes.Count == 1
    assert SemModelText(model.LookupTypeReferenceAtPosition(1, 1)) == "int"

    // The expression table has no such gate: it records what it is given.
    model.RecordExpressionNullState(2, 2, NullState.NotNull)
    assert model.ExpressionNullStates.Count == 1
}

// ---- the scope tree -------------------------------------------------------------------------------

// Successor to SemanticModel_ScopedVariable_LookupAtPositionFindsInnerScope.
test "semantic model finds the inner scope at a position" {
    model := new SemanticModel()

    outerScope := model.OpenScope(-1, 1, 1)
    model.RecordScopedVariable(outerScope, "x", BuiltInTypes.Int)
    innerScope := model.OpenScope(outerScope, 3, 1)
    model.RecordScopedVariable(innerScope, "x", BuiltInTypes.String)
    model.CloseScope(innerScope, 6, 1)
    model.CloseScope(outerScope, 10, 1)

    inner := model.LookupIdentifierAtPosition("x", 4, 5)
    assert inner != null
    assert SemModelText(inner) == "string"

    outer := model.LookupIdentifierAtPosition("x", 8, 5)
    assert outer != null
    assert SemModelText(outer) == "int"
}

// Successor to SemanticModel_ScopedVariable_DifferentVariablesInDifferentScopes.
test "semantic model keeps different variables in different scopes" {
    model := new SemanticModel()

    scopeA := model.OpenScope(-1, 1, 1)
    model.RecordScopedVariable(scopeA, "a", BuiltInTypes.Int)
    model.CloseScope(scopeA, 5, 1)

    scopeB := model.OpenScope(-1, 7, 1)
    model.RecordScopedVariable(scopeB, "b", BuiltInTypes.String)
    model.CloseScope(scopeB, 12, 1)

    assert model.LookupIdentifierAtPosition("a", 3, 1) != null
    assert model.LookupIdentifierAtPosition("a", 9, 1) == null
    assert model.LookupIdentifierAtPosition("b", 9, 1) != null
    assert model.LookupIdentifierAtPosition("b", 3, 1) == null
}

// Successor to SemanticModel_ScopedVariable_TripleNestingShadowing.
test "semantic model shadows through three nesting levels" {
    model := new SemanticModel()

    level0 := model.OpenScope(-1, 1, 1)
    model.RecordScopedVariable(level0, "x", BuiltInTypes.Int)

    level1 := model.OpenScope(level0, 3, 1)
    model.RecordScopedVariable(level1, "x", BuiltInTypes.String)

    level2 := model.OpenScope(level1, 5, 1)
    model.RecordScopedVariable(level2, "x", BuiltInTypes.Bool)
    model.CloseScope(level2, 10, 1)

    model.CloseScope(level1, 15, 1)
    model.CloseScope(level0, 20, 1)

    assert SemModelText(model.LookupIdentifierAtPosition("x", 7, 1)) == "bool"
    assert SemModelText(model.LookupIdentifierAtPosition("x", 12, 1)) == "string"
    assert SemModelText(model.LookupIdentifierAtPosition("x", 18, 1)) == "int"
}

// Successor to SemanticModel_GetVisibleVariablesAtPosition_RespectsScopes.
test "semantic model reports the visible variables at a position" {
    model := new SemanticModel()

    outer := model.OpenScope(-1, 1, 1)
    model.RecordScopedVariable(outer, "x", BuiltInTypes.Int)
    model.RecordScopedVariable(outer, "y", BuiltInTypes.String)

    inner := model.OpenScope(outer, 5, 1)
    model.RecordScopedVariable(inner, "x", BuiltInTypes.Bool)
    model.RecordScopedVariable(inner, "z", BuiltInTypes.Double)
    model.CloseScope(inner, 8, 1)

    model.CloseScope(outer, 12, 1)

    visible := model.GetVisibleVariablesAtPosition(6, 1)
    assert SemModelText(visible["x"]) == "bool"
    assert SemModelText(visible["y"]) == "string"
    assert SemModelText(visible["z"]) == "double"

    outside := model.GetVisibleVariablesAtPosition(10, 1)
    assert SemModelText(outside["x"]) == "int"
    assert SemModelText(outside["y"]) == "string"
    assert !outside.ContainsKey("z")
}

// Successor to SemanticModel_ScopeContainsPosition_BoundaryCheck.
test "semantic model includes both scope boundaries" {
    model := new SemanticModel()

    scopeId := model.OpenScope(-1, 5, 10)
    model.RecordScopedVariable(scopeId, "x", BuiltInTypes.Int)
    model.CloseScope(scopeId, 10, 20)

    assert model.LookupIdentifierAtPosition("x", 5, 10) != null
    assert model.LookupIdentifierAtPosition("x", 10, 20) != null
    assert model.LookupIdentifierAtPosition("x", 5, 9) == null
    assert model.LookupIdentifierAtPosition("x", 10, 21) == null
}

// NOT IN THE DELETED FILE. The column is consulted ONLY on the two boundary lines; on any line
// strictly inside, every column is contained — and outside the line range nothing is.
test "semantic model ignores the column between the boundary lines" {
    model := new SemanticModel()

    scopeId := model.OpenScope(-1, 5, 10)
    model.RecordScopedVariable(scopeId, "x", BuiltInTypes.Int)
    model.CloseScope(scopeId, 10, 20)

    assert model.LookupIdentifierAtPosition("x", 6, 1) != null
    assert model.LookupIdentifierAtPosition("x", 6, 999) != null
    assert model.LookupIdentifierAtPosition("x", 9, 21) != null
    assert model.LookupIdentifierAtPosition("x", 5, 11) != null
    assert model.LookupIdentifierAtPosition("x", 10, 19) != null

    assert model.LookupIdentifierAtPosition("x", 4, 10) == null
    assert model.LookupIdentifierAtPosition("x", 11, 1) == null
}

// NOT IN THE DELETED FILE. An UNCLOSED scope contains no position at all, which is what stops a
// half-parsed file from answering with a binding whose extent is not known yet.
test "semantic model keeps an unclosed scope out of position lookup" {
    model := new SemanticModel()

    openScope := model.OpenScope(-1, 1, 1)
    model.RecordScopedVariable(openScope, "x", BuiltInTypes.Int)

    assert model.LookupIdentifierAtPosition("x", 2, 1) == null
    assert model.GetVisibleVariablesAtPosition(2, 1).Count == 0

    // The flat table still holds it -- `RecordScopedVariable` writes BOTH.
    assert SemModelText(model.LookupIdentifier("x")) == "int"

    model.CloseScope(openScope, 4, 1)
    assert model.LookupIdentifierAtPosition("x", 2, 1) != null
}

// NOT IN THE DELETED FILE. The deepest CONTAINING scope wins regardless of the order the scopes
// were recorded in, and regardless of which of them is closed first.
test "semantic model picks the deepest containing scope" {
    model := new SemanticModel()

    outer := model.OpenScope(-1, 1, 1)
    inner := model.OpenScope(outer, 3, 1)
    innermost := model.OpenScope(inner, 4, 1)

    // Recorded innermost-first and closed outermost-first: neither order is the contract.
    model.RecordScopedVariable(innermost, "x", BuiltInTypes.Bool)
    model.RecordScopedVariable(inner, "x", BuiltInTypes.String)
    model.RecordScopedVariable(outer, "x", BuiltInTypes.Int)
    model.CloseScope(outer, 20, 1)
    model.CloseScope(inner, 10, 1)
    model.CloseScope(innermost, 6, 1)

    assert SemModelText(model.LookupIdentifierAtPosition("x", 5, 1)) == "bool"
    assert SemModelText(model.LookupIdentifierAtPosition("x", 8, 1)) == "string"
    assert SemModelText(model.LookupIdentifierAtPosition("x", 15, 1)) == "int"

    assert model.GetScopeDepth(outer) == 0
    assert model.GetScopeDepth(inner) == 1
    assert model.GetScopeDepth(innermost) == 2
}

// NOT IN THE DELETED FILE. Scoped FUNCTIONS are visible exactly as scoped variables are, and they
// are unwrapped to their return type by the same rule the flat table uses.
test "semantic model resolves scoped functions at a position" {
    model := new SemanticModel()

    outer := model.OpenScope(-1, 1, 1)
    model.RecordScopedFunction(outer, "compute", SemModelFunctionReturning(BuiltInTypes.Int))
    model.RecordScopedVariable(outer, "total", BuiltInTypes.Double)
    model.CloseScope(outer, 9, 1)

    assert SemModelText(model.LookupIdentifierAtPosition("compute", 5, 1)) == "int"
    assert model.LookupIdentifierAtPosition("compute", 12, 1) == null

    visible := model.GetVisibleVariablesAtPosition(5, 1)
    assert visible.ContainsKey("compute")
    assert visible.ContainsKey("total")
    assert visible.Count == 2

    // A variable outranks a function of the same name in the same scope.
    model.RecordScopedVariable(outer, "compute", BuiltInTypes.String)
    assert SemModelText(model.LookupIdentifierAtPosition("compute", 5, 1)) == "string"
}

// NOT IN THE DELETED FILE. The scope table's own bookkeeping: ids are handed out in order, an
// out-of-range id is a no-op rather than a throw, and every structural write bumps the version the
// language server caches on.
test "semantic model keeps its scope bookkeeping" {
    model := new SemanticModel()

    assert model.Scopes.Count == 0
    assert model.ScopeVersion == 0

    first := model.OpenScope(-1, 1, 1)
    second := model.OpenScope(first, 2, 1)
    assert first == 0
    assert second == 1
    assert model.Scopes.Count == 2
    assert model.ScopeVersion == 2

    model.RecordScopedVariable(second, "x", BuiltInTypes.Int)
    assert model.ScopeVersion == 3

    model.CloseScope(second, 5, 1)
    assert model.ScopeVersion == 4

    // Out-of-range ids are ignored by both writers, and the version does not move.
    model.CloseScope(99, 6, 1)
    model.RecordScopedVariable(99, "y", BuiltInTypes.String)
    model.CloseScope(-3, 6, 1)
    assert model.ScopeVersion == 4
    assert model.Scopes.Count == 2

    // The flat table still took the write, so the name resolves without a position.
    assert SemModelText(model.LookupIdentifier("y")) == "string"
    assert model.LookupIdentifierAtPosition("y", 3, 1) == null

    assert model.Scopes[0].Id == first
    assert model.Scopes[1].ParentId == first
    assert model.Scopes[1].StartLine == 2
    assert model.Scopes[1].EndLine == 5
    assert model.Scopes[0].EndLine == 0
}

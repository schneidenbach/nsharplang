using System.Collections.Generic;
using Xunit;
using NSharpLang.Compiler;

namespace Tests;

public class SemanticModelTests
{
    [Fact]
    public void SemanticModel_RecordVariable_CanLookupVariable()
    {
        var model = new SemanticModel();
        var intType = BuiltInTypes.Int;

        model.RecordVariable("x", intType);

        var result = model.LookupIdentifier("x");
        Assert.NotNull(result);
        Assert.Equal("int", result.ToString());
    }

    [Fact]
    public void SemanticModel_RecordFunction_CanLookupFunction()
    {
        var model = new SemanticModel();
        var stringType = BuiltInTypes.String;

        model.RecordFunction("getName", stringType);

        var result = model.LookupIdentifier("getName");
        Assert.NotNull(result);
        Assert.Equal("string", result.ToString());
    }

    [Fact]
    public void SemanticModel_LookupIdentifier_PrioritizesVariablesOverTypes()
    {
        var model = new SemanticModel();
        var intType = BuiltInTypes.Int;
        var stringType = BuiltInTypes.String;

        // Record both a variable and a type with same name (edge case)
        model.RecordVariable("Foo", intType);
        model.RecordType("Foo", stringType);

        // Variables should be looked up first
        var result = model.LookupIdentifier("Foo");
        Assert.NotNull(result);
        Assert.Equal("int", result.ToString());
    }

    [Fact]
    public void SemanticModel_LookupIdentifier_ReturnsNullForUnknownIdentifier()
    {
        var model = new SemanticModel();

        var result = model.LookupIdentifier("unknownVariable");
        Assert.Null(result);
    }

    [Fact]
    public void SemanticModel_RecordProperty_CanLookupProperty()
    {
        var model = new SemanticModel();
        var boolType = BuiltInTypes.Bool;

        model.RecordProperty("IsActive", boolType);

        var result = model.LookupIdentifier("IsActive");
        Assert.NotNull(result);
        Assert.Equal("bool", result.ToString());
    }

    [Fact]
    public void SemanticModel_RecordField_CanLookupField()
    {
        var model = new SemanticModel();
        var doubleType = BuiltInTypes.Double;

        model.RecordField("temperature", doubleType);

        var result = model.LookupIdentifier("temperature");
        Assert.NotNull(result);
        Assert.Equal("double", result.ToString());
    }

    [Fact]
    public void SemanticModel_MultipleVariables_AllLookupable()
    {
        var model = new SemanticModel();

        model.RecordVariable("x", BuiltInTypes.Int);
        model.RecordVariable("name", BuiltInTypes.String);
        model.RecordVariable("active", BuiltInTypes.Bool);

        Assert.Equal("int", model.LookupIdentifier("x")?.ToString());
        Assert.Equal("string", model.LookupIdentifier("name")?.ToString());
        Assert.Equal("bool", model.LookupIdentifier("active")?.ToString());
    }

    [Fact]
    public void SemanticModel_OverwriteVariable_UsesLatestType()
    {
        var model = new SemanticModel();

        model.RecordVariable("x", BuiltInTypes.Int);
        model.RecordVariable("x", BuiltInTypes.String);  // Overwrite

        var result = model.LookupIdentifier("x");
        Assert.Equal("string", result?.ToString());
    }

    [Fact]
    public void SemanticModel_RecordExpressionType_CanLookupByPosition()
    {
        var model = new SemanticModel();

        model.RecordExpressionType(4, 12, BuiltInTypes.Bool);

        var result = model.LookupTypeAtPosition(4, 12);
        Assert.NotNull(result);
        Assert.Equal("bool", result!.ToString());
    }

    // ── Scope-aware lookup tests ────────────────────────────────────────

    [Fact]
    public void SemanticModel_ScopedVariable_LookupAtPositionFindsInnerScope()
    {
        var model = new SemanticModel();

        // Outer scope: lines 1-10
        var outerScope = model.OpenScope(-1, 1, 1);
        model.RecordScopedVariable(outerScope, "x", BuiltInTypes.Int);
        // Inner scope: lines 3-6 (shadows x)
        var innerScope = model.OpenScope(outerScope, 3, 1);
        model.RecordScopedVariable(innerScope, "x", BuiltInTypes.String);
        model.CloseScope(innerScope, 6, 1);
        model.CloseScope(outerScope, 10, 1);

        // At line 4 (inside inner scope), x should be string
        var result = model.LookupIdentifierAtPosition("x", 4, 5);
        Assert.NotNull(result);
        Assert.Equal("string", result!.ToString());

        // At line 8 (outside inner scope), x should be int
        result = model.LookupIdentifierAtPosition("x", 8, 5);
        Assert.NotNull(result);
        Assert.Equal("int", result!.ToString());
    }

    [Fact]
    public void SemanticModel_ScopedVariable_DifferentVariablesInDifferentScopes()
    {
        var model = new SemanticModel();

        // Scope A: lines 1-5
        var scopeA = model.OpenScope(-1, 1, 1);
        model.RecordScopedVariable(scopeA, "a", BuiltInTypes.Int);
        model.CloseScope(scopeA, 5, 1);

        // Scope B: lines 7-12
        var scopeB = model.OpenScope(-1, 7, 1);
        model.RecordScopedVariable(scopeB, "b", BuiltInTypes.String);
        model.CloseScope(scopeB, 12, 1);

        // 'a' visible at line 3 but not at line 9
        Assert.NotNull(model.LookupIdentifierAtPosition("a", 3, 1));
        Assert.Null(model.LookupIdentifierAtPosition("a", 9, 1));

        // 'b' visible at line 9 but not at line 3
        Assert.NotNull(model.LookupIdentifierAtPosition("b", 9, 1));
        Assert.Null(model.LookupIdentifierAtPosition("b", 3, 1));
    }

    [Fact]
    public void SemanticModel_ScopedVariable_TripleNestingShadowing()
    {
        var model = new SemanticModel();

        // Level 0: lines 1-20
        var l0 = model.OpenScope(-1, 1, 1);
        model.RecordScopedVariable(l0, "x", BuiltInTypes.Int);

        // Level 1: lines 3-15
        var l1 = model.OpenScope(l0, 3, 1);
        model.RecordScopedVariable(l1, "x", BuiltInTypes.String);

        // Level 2: lines 5-10
        var l2 = model.OpenScope(l1, 5, 1);
        model.RecordScopedVariable(l2, "x", BuiltInTypes.Bool);
        model.CloseScope(l2, 10, 1);

        model.CloseScope(l1, 15, 1);
        model.CloseScope(l0, 20, 1);

        // Level 2: x is bool
        Assert.Equal("bool", model.LookupIdentifierAtPosition("x", 7, 1)!.ToString());
        // Level 1 (after inner scope closes): x is string
        Assert.Equal("string", model.LookupIdentifierAtPosition("x", 12, 1)!.ToString());
        // Level 0 (after all inner scopes close): x is int
        Assert.Equal("int", model.LookupIdentifierAtPosition("x", 18, 1)!.ToString());
    }

    [Fact]
    public void SemanticModel_GetVisibleVariablesAtPosition_RespectsScopes()
    {
        var model = new SemanticModel();

        var outer = model.OpenScope(-1, 1, 1);
        model.RecordScopedVariable(outer, "x", BuiltInTypes.Int);
        model.RecordScopedVariable(outer, "y", BuiltInTypes.String);

        var inner = model.OpenScope(outer, 5, 1);
        model.RecordScopedVariable(inner, "x", BuiltInTypes.Bool); // shadows outer x
        model.RecordScopedVariable(inner, "z", BuiltInTypes.Double);
        model.CloseScope(inner, 8, 1);

        model.CloseScope(outer, 12, 1);

        // Inside inner scope: x=bool (shadowed), y=string (from outer), z=double
        var visible = model.GetVisibleVariablesAtPosition(6, 1);
        Assert.Equal("bool", visible["x"].ToString());
        Assert.Equal("string", visible["y"].ToString());
        Assert.Equal("double", visible["z"].ToString());

        // Outside inner scope: x=int (original), y=string, no z
        visible = model.GetVisibleVariablesAtPosition(10, 1);
        Assert.Equal("int", visible["x"].ToString());
        Assert.Equal("string", visible["y"].ToString());
        Assert.False(visible.ContainsKey("z"));
    }

    [Fact]
    public void SemanticModel_LookupIdentifierAtPosition_FallsBackToFlatLookup()
    {
        var model = new SemanticModel();

        // Record in flat dict only (no scopes)
        model.RecordProperty("Name", BuiltInTypes.String);

        // Should still find it via flat fallback
        var result = model.LookupIdentifierAtPosition("Name", 5, 1);
        Assert.NotNull(result);
        Assert.Equal("string", result!.ToString());
    }

    [Fact]
    public void SemanticModel_LookupIdentifierAtPosition_NoScopes_FallsBackToFlatLookup()
    {
        var model = new SemanticModel();
        model.RecordVariable("x", BuiltInTypes.Int);

        // No scopes recorded — should use flat Variables dict
        var result = model.LookupIdentifierAtPosition("x", 1, 1);
        Assert.NotNull(result);
        Assert.Equal("int", result!.ToString());
    }

    [Fact]
    public void SemanticModel_ScopeContainsPosition_BoundaryCheck()
    {
        var model = new SemanticModel();

        var scope = model.OpenScope(-1, 5, 10);
        model.RecordScopedVariable(scope, "x", BuiltInTypes.Int);
        model.CloseScope(scope, 10, 20);

        // Exactly at start boundary
        Assert.NotNull(model.LookupIdentifierAtPosition("x", 5, 10));
        // Exactly at end boundary
        Assert.NotNull(model.LookupIdentifierAtPosition("x", 10, 20));
        // Just before start
        Assert.Null(model.LookupIdentifierAtPosition("x", 5, 9));
        // Just after end
        Assert.Null(model.LookupIdentifierAtPosition("x", 10, 21));
    }
}

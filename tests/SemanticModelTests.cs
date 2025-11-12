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
}

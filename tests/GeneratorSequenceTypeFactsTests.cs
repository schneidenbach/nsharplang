using System.Collections.Generic;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class GeneratorSequenceTypeFactsTests
{
    [Theory]
    [InlineData("IEnumerable", false)]
    [InlineData("System.Collections.Generic.ICollection", false)]
    [InlineData("List", false)]
    [InlineData("IList`1", false)]
    [InlineData("System.Collections.Generic.IReadOnlyCollection`1", false)]
    [InlineData("IReadOnlyList", false)]
    [InlineData("IAsyncEnumerable", true)]
    [InlineData("System.Collections.Generic.IAsyncEnumerable`1", true)]
    public void GeneratorSequenceTypeFacts_AcceptsSequenceReturnTypes(string name, bool isAsyncGenerator)
    {
        var typeInfo = new GenericTypeInfo(name, new List<TypeInfo> { BuiltInTypes.Int });

        Assert.True(GeneratorSequenceTypeFacts.IsSequenceReturnType(typeInfo, isAsyncGenerator));
    }

    [Theory]
    [InlineData("IEnumerator", false)]
    [InlineData("IAsyncEnumerable", false)]
    [InlineData("IEnumerable", true)]
    [InlineData("Task", true)]
    [InlineData("Task", false)]
    public void GeneratorSequenceTypeFacts_RejectsNonSequenceReturnTypes(string name, bool isAsyncGenerator)
    {
        var typeInfo = new GenericTypeInfo(name, new List<TypeInfo> { BuiltInTypes.Int });

        Assert.False(GeneratorSequenceTypeFacts.IsSequenceReturnType(typeInfo, isAsyncGenerator));
    }

    [Fact]
    public void GeneratorSequenceTypeFacts_RejectsWrongArity()
    {
        Assert.False(GeneratorSequenceTypeFacts.IsSequenceReturnType(
            new GenericTypeInfo("IEnumerable", new List<TypeInfo>()),
            false));
        Assert.False(GeneratorSequenceTypeFacts.IsSequenceReturnType(
            new GenericTypeInfo("IAsyncEnumerable", new List<TypeInfo> { BuiltInTypes.Int, BuiltInTypes.String }),
            true));
    }

    [Fact]
    public void GeneratorSequenceTypeFacts_OwnsDiagnosticText()
    {
        Assert.Equal("a synchronous enumerable sequence type", GeneratorSequenceTypeFacts.ExpectedSequenceKind(false));
        Assert.Equal("an async enumerable sequence type", GeneratorSequenceTypeFacts.ExpectedSequenceKind(true));
        Assert.Contains("IEnumerable<T>", GeneratorSequenceTypeFacts.ReturnTypeSuggestion(false));
        Assert.Contains("IAsyncEnumerable<T>", GeneratorSequenceTypeFacts.ReturnTypeSuggestion(true));
    }
}

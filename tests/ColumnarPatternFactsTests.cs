using System;
using System.Reflection;
using NSharpLang.Compiler.Columnar;
using Xunit;

namespace NSharpLang.Tests;

public class ColumnarPatternFactsTests
{
    [Theory]
    [InlineData(-1, false)]
    [InlineData(0, true)]
    [InlineData(1, true)]
    [InlineData(2, true)]
    [InlineData(3, true)]
    [InlineData(4, true)]
    [InlineData(5, false)]
    public void IsLiteralPatternKind_ClassifiesColumnarLiteralNodes(int kind, bool expected)
    {
        Assert.Equal(expected, ColumnarPatternFacts.IsLiteralPatternKind(kind));
    }

    [Theory]
    [InlineData(typeof(int), true)]
    [InlineData(typeof(long), true)]
    [InlineData(typeof(ulong), true)]
    [InlineData(typeof(char), true)]
    [InlineData(typeof(double), true)]
    [InlineData(typeof(float), true)]
    [InlineData(typeof(bool), false)]
    [InlineData(typeof(string), false)]
    public void IsOrderedMatchType_ClassifiesRelationalPatternSet(Type type, bool expected)
    {
        Assert.Equal(expected, ColumnarPatternFacts.IsOrderedMatchType(type));
    }

    [Fact]
    public void ColumnarCompiler_MatchPatterns_UseNSharpPatternFacts()
    {
        Assert.True(ColumnarCompiler.TryEmitProgram(
            """
func Value(x: int): int {
    return match x {
        0 => 10,
        < 5 => 20,
        _ => 30
    }
}
""",
            "ColumnarPatternFacts",
            "Program",
            out var assembly,
            out _,
            out _));

        using var scope = CollectibleAssemblyScope.Load(assembly);
        var type = scope.Assembly.GetType("Program");
        Assert.NotNull(type);
        var method = type.GetMethod("Value", BindingFlags.Public | BindingFlags.Static);
        Assert.NotNull(method);

        Assert.Equal(10, method.Invoke(null, new object[] { 0 }));
        Assert.Equal(20, method.Invoke(null, new object[] { 3 }));
        Assert.Equal(30, method.Invoke(null, new object[] { 7 }));
    }
}

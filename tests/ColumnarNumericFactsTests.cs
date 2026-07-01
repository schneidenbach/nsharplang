using System;
using System.Reflection;
using NSharpLang.Compiler.Columnar;
using Xunit;

namespace NSharpLang.Tests;

public class ColumnarNumericFactsTests
{
    [Theory]
    [InlineData(typeof(int), true)]
    [InlineData(typeof(char), true)]
    [InlineData(typeof(byte), true)]
    [InlineData(typeof(sbyte), true)]
    [InlineData(typeof(short), true)]
    [InlineData(typeof(ushort), true)]
    [InlineData(typeof(long), false)]
    [InlineData(typeof(uint), false)]
    [InlineData(typeof(bool), false)]
    public void IsIntPromotable_ClassifiesColumnarPromotionSet(Type type, bool expected)
    {
        Assert.Equal(expected, ColumnarNumericFacts.IsIntPromotable(type));
    }

    [Fact]
    public void ColumnarCompiler_IntPromotableArithmetic_UsesNSharpNumericFacts()
    {
        Assert.True(ColumnarCompiler.TryEmitProgram(
            """
func Value(): int {
    let a: byte = 1
    let b: short = 2
    return a + b
}
""",
            "ColumnarNumericFacts",
            "Program",
            out var assembly,
            out _,
            out _));

        using var scope = CollectibleAssemblyScope.Load(assembly);
        var type = scope.Assembly.GetType("Program");
        Assert.NotNull(type);
        var method = type.GetMethod("Value", BindingFlags.Public | BindingFlags.Static);
        Assert.NotNull(method);

        Assert.Equal(3, method.Invoke(null, null));
    }
}

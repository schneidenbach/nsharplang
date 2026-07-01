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

    [Theory]
    [InlineData(typeof(int), true)]
    [InlineData(typeof(long), true)]
    [InlineData(typeof(char), true)]
    [InlineData(typeof(double), true)]
    [InlineData(typeof(float), true)]
    [InlineData(typeof(byte), true)]
    [InlineData(typeof(sbyte), true)]
    [InlineData(typeof(short), true)]
    [InlineData(typeof(ushort), true)]
    [InlineData(typeof(uint), true)]
    [InlineData(typeof(ulong), true)]
    [InlineData(typeof(decimal), true)]
    [InlineData(typeof(bool), false)]
    [InlineData(typeof(string), false)]
    public void IsCastableScalar_ClassifiesColumnarExplicitCastSet(Type type, bool expected)
    {
        Assert.Equal(expected, ColumnarNumericFacts.IsCastableScalar(type));
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

    [Fact]
    public void ColumnarCompiler_ExplicitNumericCasts_UseNSharpNumericFacts()
    {
        Assert.True(ColumnarCompiler.TryEmitProgram(
            """
func Narrow(value: double): int {
    return (int)value
}

func Widen(value: int): long {
    return (long)value
}
""",
            "ColumnarNumericCastFacts",
            "Program",
            out var assembly,
            out _,
            out _));

        using var scope = CollectibleAssemblyScope.Load(assembly);
        var type = scope.Assembly.GetType("Program");
        Assert.NotNull(type);
        var narrow = type.GetMethod("Narrow", BindingFlags.Public | BindingFlags.Static);
        var widen = type.GetMethod("Widen", BindingFlags.Public | BindingFlags.Static);
        Assert.NotNull(narrow);
        Assert.NotNull(widen);

        Assert.Equal(3, narrow.Invoke(null, new object[] { 3.75 }));
        Assert.Equal(42L, widen.Invoke(null, new object[] { 42 }));
    }
}

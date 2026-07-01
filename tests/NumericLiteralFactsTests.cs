using System;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class NumericLiteralFactsTests
{
    [Theory]
    [InlineData("1.0", "double")]
    [InlineData("1.0d", "double")]
    [InlineData("1.0f", "float")]
    [InlineData("1.0F", "float")]
    [InlineData("1.0m", "decimal")]
    [InlineData("1.0M", "decimal")]
    public void NumericLiteralFacts_ClassifiesFloatLiteralSuffixes(string literal, string expectedType)
    {
        Assert.Equal(expectedType, NumericLiteralFacts.GetFloatLiteralTypeInfo(literal).ToString());
    }

    [Theory]
    [InlineData(typeof(byte), "byte")]
    [InlineData(typeof(sbyte), "sbyte")]
    [InlineData(typeof(short), "short")]
    [InlineData(typeof(ushort), "ushort")]
    [InlineData(typeof(int), "int")]
    [InlineData(typeof(uint), "uint")]
    [InlineData(typeof(long), "long")]
    [InlineData(typeof(ulong), "ulong")]
    [InlineData(typeof(char), "char")]
    public void NumericLiteralFacts_MapsClrIntegerLiteralTypes(Type type, string expectedType)
    {
        Assert.True(NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(type, out var typeInfo));
        Assert.Equal(expectedType, typeInfo.Name);
    }

    [Fact]
    public void NumericLiteralFacts_RejectsNonIntegerClrTypes()
    {
        Assert.False(NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(string), out var typeInfo));
        Assert.Equal(BuiltInTypes.Int, typeInfo);
    }

    [Theory]
    [InlineData("sbyte", 128UL)]
    [InlineData("short", 32768UL)]
    [InlineData("int", 2147483648UL)]
    [InlineData("long", 9223372036854775808UL)]
    public void NumericLiteralFacts_ProvidesNegativeIntegerLiteralMaxMagnitude(string typeName, ulong expected)
    {
        Assert.True(NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude(typeName, out var maxMagnitude));
        Assert.Equal(expected, maxMagnitude);
    }

    [Theory]
    [InlineData("byte", 255UL)]
    [InlineData("sbyte", 127UL)]
    [InlineData("short", 32767UL)]
    [InlineData("ushort", 65535UL)]
    [InlineData("char", 65535UL)]
    [InlineData("int", 2147483647UL)]
    [InlineData("uint", 4294967295UL)]
    [InlineData("long", 9223372036854775807UL)]
    [InlineData("ulong", ulong.MaxValue)]
    public void NumericLiteralFacts_ProvidesUnsignedIntegerLiteralMaxValue(string typeName, ulong expected)
    {
        Assert.True(NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue(typeName, out var maxValue));
        Assert.Equal(expected, maxValue);
    }

    [Fact]
    public void NumericLiteralFacts_RejectsUnsupportedIntegerLiteralBounds()
    {
        Assert.False(NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("uint", out var negativeMax));
        Assert.Equal(0UL, negativeMax);

        Assert.False(NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("string", out var unsignedMax));
        Assert.Equal(0UL, unsignedMax);
    }
}

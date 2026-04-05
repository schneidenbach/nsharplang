using NSharpInteropLib;
using Xunit;

namespace NSharpLang.CSharpInteropTests;

/// <summary>
/// Tests that C# code can call N# static methods, including ref/out parameters.
/// Validates that N#'s function emissions are natural to call from C#.
/// </summary>
public class UtilityInteropTests
{
    [Fact]
    public void StaticAdd()
    {
        Assert.Equal(5, MathUtils.Add(2, 3));
        Assert.Equal(0, MathUtils.Add(-1, 1));
        Assert.Equal(-3, MathUtils.Add(-1, -2));
    }

    [Fact]
    public void StaticMultiply()
    {
        Assert.Equal(6.0, MathUtils.Multiply(2.0, 3.0));
        Assert.Equal(0.0, MathUtils.Multiply(0.0, 100.0));
    }

    [Fact]
    public void StaticIsEven()
    {
        Assert.True(MathUtils.IsEven(0));
        Assert.True(MathUtils.IsEven(2));
        Assert.True(MathUtils.IsEven(100));
        Assert.False(MathUtils.IsEven(1));
        Assert.False(MathUtils.IsEven(99));
    }

    [Fact]
    public void StaticClamp()
    {
        Assert.Equal(5, MathUtils.Clamp(5, 0, 10));
        Assert.Equal(0, MathUtils.Clamp(-5, 0, 10));
        Assert.Equal(10, MathUtils.Clamp(15, 0, 10));
    }

    [Fact]
    public void StaticFactorial()
    {
        Assert.Equal(1L, MathUtils.Factorial(0));
        Assert.Equal(1L, MathUtils.Factorial(1));
        Assert.Equal(120L, MathUtils.Factorial(5));
        Assert.Equal(3628800L, MathUtils.Factorial(10));
    }

    [Fact]
    public void OutParameter()
    {
        Assert.True(StringUtils.TryParseInt("42", out var result));
        Assert.Equal(42, result);

        Assert.False(StringUtils.TryParseInt("not-a-number", out var failed));
        Assert.Equal(0, failed);
    }

    [Fact]
    public void RefParameter()
    {
        var a = "hello";
        var b = "world";

        StringUtils.Swap(ref a, ref b);

        Assert.Equal("world", a);
        Assert.Equal("hello", b);
    }

    [Fact]
    public void StringReverse()
    {
        Assert.Equal("olleh", StringUtils.Reverse("hello"));
        Assert.Equal("", StringUtils.Reverse(""));
        Assert.Equal("a", StringUtils.Reverse("a"));
    }

    [Fact]
    public void StringTruncate()
    {
        Assert.Equal("hello", StringUtils.Truncate("hello", 10));
        Assert.Equal("hel...", StringUtils.Truncate("hello world", 3));
        Assert.Equal("", StringUtils.Truncate("", 5));
    }
}

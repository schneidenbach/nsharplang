using System.Reflection;
using NSharpLang.Compiler.Columnar;
using Xunit;

namespace NSharpLang.Tests;

public class ColumnarTypeCanonicalizerTests
{
    [Fact]
    public void StripTupleElementNames_RemovesOnlyTopLevelNames()
    {
        var result = ColumnarTypeCanonicalizer.StripTupleElementNames("(x:List<int>,y:(string,int[]))");

        Assert.Equal("(List<int>,(string,int[]))", result.Canonical);
        Assert.NotNull(result.Names);
        Assert.Equal(new[] { "x", "y" }, result.Names);
    }

    [Fact]
    public void RemoveWhitespace_StripsDeclaredTypeSpan()
    {
        Assert.Equal(
            "Func<int,(string,int[])>",
            ColumnarTypeCanonicalizer.RemoveWhitespace("Func<int, (string, int[])>"));
    }

    [Fact]
    public void StripTupleElementNames_LeavesPositionalTupleUnchanged()
    {
        var result = ColumnarTypeCanonicalizer.StripTupleElementNames("(int,(string,int[]))");

        Assert.Equal("(int,(string,int[]))", result.Canonical);
        Assert.Null(result.Names);
    }

    [Fact]
    public void ColumnarCompiler_NamedTupleLocal_UsesNSharpCanonicalizer()
    {
        Assert.True(ColumnarCompiler.TryEmitProgram(
            """
func Value(): int {
    let pair: (x: int, y: int) = (1, 2)
    return pair.x
}
""",
            "ColumnarNamedTuple",
            "Program",
            out var assembly,
            out _,
            out _));

        using var scope = CollectibleAssemblyScope.Load(assembly);
        var type = scope.Assembly.GetType("Program");
        Assert.NotNull(type);
        var method = type.GetMethod("Value", BindingFlags.Public | BindingFlags.Static);
        Assert.NotNull(method);

        Assert.Equal(1, method.Invoke(null, null));
    }
}

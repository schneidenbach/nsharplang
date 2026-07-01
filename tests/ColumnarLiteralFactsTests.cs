using System.Reflection;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Columnar;
using Xunit;

namespace NSharpLang.Tests;

public class ColumnarLiteralFactsTests
{
    [Fact]
    public void StringLiteralDecoder_TryDecodeBody_DecodesColumnarCharEscapes()
    {
        Assert.True(StringLiteralDecoder.TryDecodeBody(@"line\n", out var decoded));
        Assert.Equal("line\n", decoded);

        Assert.True(StringLiteralDecoder.TryDecodeBody(@"quote\'slash\\", out decoded));
        Assert.Equal("quote'slash\\", decoded);
    }

    [Fact]
    public void StringLiteralDecoder_TryDecodeBody_RejectsUnsupportedColumnarEscapes()
    {
        Assert.False(StringLiteralDecoder.TryDecodeBody(@"\u1234", out _));
        Assert.False(StringLiteralDecoder.TryDecodeBody(@"trailing\", out _));
    }

    [Fact]
    public void ColumnarCompiler_CharLiteralEscape_UsesNSharpDecoder()
    {
        Assert.True(ColumnarCompiler.TryEmitProgram(
            """
func Value(): char {
    return '\n'
}
""",
            "ColumnarCharLiteral",
            "Program",
            out var assembly,
            out var emittedTypeName,
            out var methodNames));

        Assert.Equal("Program", emittedTypeName);
        Assert.Contains("Value", methodNames);

        using var scope = CollectibleAssemblyScope.Load(assembly);
        var type = scope.Assembly.GetType("Program");
        Assert.NotNull(type);
        var method = type.GetMethod("Value", BindingFlags.Public | BindingFlags.Static);
        Assert.NotNull(method);

        var value = Assert.IsType<char>(method.Invoke(null, null));
        Assert.Equal('\n', value);
    }
}

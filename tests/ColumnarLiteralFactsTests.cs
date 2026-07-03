using System.Collections.Generic;
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
    public void StringLiteralDecoder_Decode_PreservesRawStringBackslashes()
    {
        Assert.Equal("slash\n", StringLiteralDecoder.Decode("\"slash\\n\""));
        Assert.Equal(@"slash\n", StringLiteralDecoder.Decode("\"\"\"slash\\n\"\"\""));
        Assert.Equal(@"slash\n", StringLiteralDecoder.Decode("$\"\"\"slash\\n\"\"\""));
        Assert.Equal("\n", StringLiteralDecoder.DecodeInterpolatedText("$\"x\"", @"\n"));
        Assert.Equal(@"\n", StringLiteralDecoder.DecodeInterpolatedText("$\"\"\"x\"\"\"", @"\n"));
    }

    [Fact]
    public void ColumnarInterpolationSplitter_SplitsInterpolatedRawStringBody()
    {
        var parts = new List<ColumnarInterpolationPart>();

        Assert.True(ColumnarInterpolationSplitter.TrySplit("$\"\"\"a\\n{name}{{name}}\"\"\"", parts));

        Assert.Equal(3, parts.Count);
        Assert.False(parts[0].IsHole);
        Assert.Equal(@"a\n", parts[0].Text);
        Assert.True(parts[1].IsHole);
        Assert.Equal("name", parts[1].Text);
        Assert.False(parts[2].IsHole);
        Assert.Equal("{name}", parts[2].Text);
    }

    [Fact]
    public void ColumnarInterpolationSplitter_AcceptsSimpleCoalesceHole()
    {
        var parts = new List<ColumnarInterpolationPart>();

        Assert.True(ColumnarInterpolationSplitter.TrySplit("$\"email: {email ?? missingEmail}\"", parts));

        Assert.Equal(2, parts.Count);
        Assert.False(parts[0].IsHole);
        Assert.Equal("email: ", parts[0].Text);
        Assert.True(parts[1].IsHole);
        Assert.Equal("email ?? missingEmail", parts[1].Text);
    }

    [Fact]
    public void ColumnarInterpolationSplitter_RejectsMultipleCoalesceHole()
    {
        var parts = new List<ColumnarInterpolationPart>();

        Assert.False(ColumnarInterpolationSplitter.TrySplit("$\"email: {primary ?? fallback ?? missing}\"", parts));
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

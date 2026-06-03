using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using NSharpLang.Cli;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class CompilerDogfoodProjectTests
{
    [Fact]
    public void LexerTokenKindScanner_ProjectCompilesAndMatchesProductionLexer()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(
            Path.GetTempPath(),
            $"NSharpLang.Compiler.Dogfood.Tests.{Guid.NewGuid():N}.dll");

        try
        {
            var compiler = new MultiFileCompiler(projectRoot, config);
            var result = compiler.CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            Assert.True(File.Exists(outputPath));

            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenizeCount = programType.GetMethod(
                    "TokenizeCount",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeCount.");
            var tokenizeKinds = programType.GetMethod(
                    "TokenizeKinds",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeKinds.");
            var tokenizeKindsInto = programType.GetMethod(
                    "TokenizeKindsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeKindsInto.");
            var tokenizeMetadataInto = programType.GetMethod(
                    "TokenizeMetadataInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeMetadataInto.");
            var splitLogicalLines = programType.GetMethod(
                    "SplitLogicalLines",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SplitLogicalLines.");
            var splitLogicalLineRangesInto = programType.GetMethod(
                    "SplitLogicalLineRangesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SplitLogicalLineRangesInto.");
            var buildLogicalLineStartsInto = programType.GetMethod(
                    "BuildLogicalLineStartsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BuildLogicalLineStartsInto.");
            var getLineIndexFromOffset = programType.GetMethod(
                    "GetLineIndexFromOffset",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit GetLineIndexFromOffset.");
            var getColumnFromOffset = programType.GetMethod(
                    "GetColumnFromOffset",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit GetColumnFromOffset.");
            var getOffsetFromLineColumn = programType.GetMethod(
                    "GetOffsetFromLineColumn",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit GetOffsetFromLineColumn.");

            const string source = """"
import System
package CompilerDogfood.Tests

func score(value: int): int {
    if value == 0 {
        return 1
    }

    text := $"score:{value}"
    raw := """
hello
world
"""
    return text.Length + raw.Length + value
}
"""";
            AssertTokenizesLikeProductionLexer(source, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(source, tokenizeMetadataInto);

            const string keywordSource = """
func class struct interface duck union record enum namespace using import package let must const readonly
if else for foreach while in return yield match switch case default break continue throw try catch finally
new this base true false null is as typeof nameof sizeof print where when and or not
virtual override abstract sealed partial static public private internal protected async await immutable
with type assert operator required init ref out lock file params checked unchecked implicit explicit newtype
throws
""";
            AssertTokenizesLikeProductionLexer(keywordSource, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(keywordSource, tokenizeMetadataInto);

            const string metadataSource = """
package CompilerDogfood.Metadata

func values(): int {
    decimal := 1_234
    hex := 0xCA_FE
    binary := 0b1010_0101
    floating := 1.5_0e+2
    /* block
       comment */
    return decimal + hex + binary + floating
}
""";
            AssertTokenMetadataLikeProductionLexer(metadataSource, tokenizeMetadataInto);

            AssertSourceTextLineMapLikeProduction(
                "",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn);
            AssertSourceTextLineMapLikeProduction(
                "one",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn);
            AssertSourceTextLineMapLikeProduction(
                "one\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn);
            AssertSourceTextLineMapLikeProduction(
                "one\r\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn);
            AssertSourceTextLineMapLikeProduction(
                "one\rtwo",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn);
            AssertSourceTextLineMapLikeProduction(
                "one\r\ntwo\rthree\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn);
            AssertSourceTextLineMapLikeProduction(
                "\r\n\r\n\n\r",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn);
        }
        finally
        {
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    private static void AssertTokenizesLikeProductionLexer(
        string source,
        MethodInfo tokenizeCount,
        MethodInfo tokenizeKinds,
        MethodInfo tokenizeKindsInto)
    {
        var expectedKinds = new Lexer(source, "dogfood-test.nl")
            .Tokenize()
            .Select(static token => (int)token.Type)
            .ToArray();

        var count = (int)(tokenizeCount.Invoke(null, new object[] { source }) ?? -1);
        var kinds = (int[])(tokenizeKinds.Invoke(null, new object[] { source })
            ?? throw new InvalidOperationException("TokenizeKinds returned null."));
        var buffer = new int[source.Length + 1];
        var bufferedCount = (int)(tokenizeKindsInto.Invoke(null, new object[] { source, buffer }) ?? -1);

        Assert.Equal(expectedKinds.Length, count);
        Assert.Equal(expectedKinds, kinds);
        Assert.Equal(expectedKinds.Length, bufferedCount);
        Assert.Equal(expectedKinds, buffer.Take(bufferedCount).ToArray());
    }

    private static void AssertTokenMetadataLikeProductionLexer(
        string source,
        MethodInfo tokenizeMetadataInto)
    {
        var expectedTokens = new Lexer(source, "dogfood-test.nl").Tokenize();
        var capacity = source.Length + 1;
        var kinds = new int[capacity];
        var starts = new int[capacity];
        var valueLengths = new int[capacity];
        var lines = new int[capacity];
        var columns = new int[capacity];

        var count = (int)(tokenizeMetadataInto.Invoke(
            null,
            new object[] { source, kinds, starts, valueLengths, lines, columns }) ?? -1);

        Assert.Equal(expectedTokens.Count, count);

        var lineStarts = BuildLineStarts(source);
        for (var i = 0; i < expectedTokens.Count; i++)
        {
            var token = expectedTokens[i];
            Assert.Equal((int)token.Type, kinds[i]);
            Assert.Equal(TokenStartFromLineColumn(lineStarts, token.Line, token.Column, source.Length), starts[i]);
            Assert.Equal(token.Value.Length, valueLengths[i]);
            Assert.Equal(token.Line, lines[i]);
            Assert.Equal(token.Column, columns[i]);
        }
    }

    private static int[] BuildLineStarts(string source)
    {
        var starts = new List<int> { 0 };
        var position = 0;
        while (position < source.Length)
        {
            if (source[position] == '\r')
            {
                position++;
                if (position < source.Length && source[position] == '\n')
                {
                    position++;
                }

                starts.Add(position);
                continue;
            }

            if (source[position] == '\n')
            {
                position++;
                starts.Add(position);
                continue;
            }

            position++;
        }

        return starts.ToArray();
    }

    private static int TokenStartFromLineColumn(int[] lineStarts, int line, int column, int sourceLength)
    {
        var lineIndex = line - 1;
        if (lineIndex < 0 || lineIndex >= lineStarts.Length)
        {
            return sourceLength;
        }

        return Math.Min(sourceLength, lineStarts[lineIndex] + column - 1);
    }

    private static void AssertSourceTextLineMapLikeProduction(
        string source,
        MethodInfo splitLogicalLines,
        MethodInfo splitLogicalLineRangesInto,
        MethodInfo buildLogicalLineStartsInto,
        MethodInfo getLineIndexFromOffset,
        MethodInfo getColumnFromOffset,
        MethodInfo getOffsetFromLineColumn)
    {
        var expected = SourceTextLines.SplitLogicalLines(source);
        var actual = (string[])(splitLogicalLines.Invoke(null, new object[] { source })
            ?? throw new InvalidOperationException("SplitLogicalLines returned null."));

        Assert.Equal(expected, actual);

        var starts = new int[source.Length + 1];
        var lengths = new int[source.Length + 1];
        var count = (int)(splitLogicalLineRangesInto.Invoke(null, new object[] { source, starts, lengths }) ?? -1);
        Assert.Equal(expected.Length, count);
        for (var i = 0; i < count; i++)
        {
            Assert.Equal(expected[i], source.Substring(starts[i], lengths[i]));
        }

        var expectedStarts = BuildLineStarts(source);
        var startOnlyBuffer = new int[source.Length + 1];
        var startOnlyCount = (int)(buildLogicalLineStartsInto.Invoke(null, new object[] { source, startOnlyBuffer }) ?? -1);
        Assert.Equal(expectedStarts.Length, startOnlyCount);
        Assert.Equal(expectedStarts, startOnlyBuffer.Take(startOnlyCount).ToArray());

        for (var offset = -1; offset <= source.Length + 1; offset++)
        {
            var expectedLineIndex = LineIndexFromOffset(expectedStarts, source.Length, offset);
            var expectedColumn = ColumnFromOffset(expectedStarts, source.Length, offset);
            var actualLineIndex = (int)(getLineIndexFromOffset.Invoke(
                null,
                new object[] { startOnlyBuffer, startOnlyCount, source.Length, offset }) ?? -1);
            var actualColumn = (int)(getColumnFromOffset.Invoke(
                null,
                new object[] { startOnlyBuffer, startOnlyCount, source.Length, offset }) ?? -1);

            Assert.Equal(expectedLineIndex, actualLineIndex);
            Assert.Equal(expectedColumn, actualColumn);
        }

        for (var line = 1; line <= expected.Length; line++)
        {
            var lineLength = expected[line - 1].Length;
            for (var column = 0; column <= lineLength; column++)
            {
                var actualOffset = (int)(getOffsetFromLineColumn.Invoke(
                    null,
                    new object[] { starts, lengths, count, source.Length, line, column }) ?? -2);
                Assert.Equal(expectedStarts[line - 1] + column, actualOffset);
            }

            var invalidColumnOffset = (int)(getOffsetFromLineColumn.Invoke(
                null,
                new object[] { starts, lengths, count, source.Length, line, lineLength + 1 }) ?? -2);
            Assert.Equal(-1, invalidColumnOffset);
        }

        var invalidLineOffset = (int)(getOffsetFromLineColumn.Invoke(
            null,
            new object[] { starts, lengths, count, source.Length, expected.Length + 1, 0 }) ?? -2);
        Assert.Equal(-1, invalidLineOffset);
    }

    private static int LineIndexFromOffset(int[] starts, int sourceLength, int offset)
    {
        if (offset < 0)
        {
            offset = 0;
        }

        if (offset > sourceLength)
        {
            offset = sourceLength;
        }

        var result = 0;
        for (var i = 0; i < starts.Length; i++)
        {
            if (starts[i] <= offset)
            {
                result = i;
            }
        }

        return result;
    }

    private static int ColumnFromOffset(int[] starts, int sourceLength, int offset)
    {
        if (offset < 0)
        {
            offset = 0;
        }

        if (offset > sourceLength)
        {
            offset = sourceLength;
        }

        return offset - starts[LineIndexFromOffset(starts, sourceLength, offset)];
    }

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
            {
                return dir;
            }

            dir = Path.GetDirectoryName(dir);
        }

        throw new InvalidOperationException(
            "Could not find repository root (NSharpLang.sln). "
                + $"Searched upward from {AppContext.BaseDirectory}");
    }
}

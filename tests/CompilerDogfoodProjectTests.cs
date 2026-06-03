using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using NSharpLang.Cli;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

public class CompilerDogfoodProjectTests
{
    [Fact]
    public void CodeIntelligenceDogfoodAdapter_LoadsPackagedNSharpAssembly()
    {
        var source = """
func main() {
    value := input.Count

    print value
}
""";
        var filePath = Path.GetFullPath(Path.Combine(Path.GetTempPath(), $"dogfood-adapter-{Guid.NewGuid():N}.nl"));
        var snapshot = new ProjectSnapshot(
            Path.GetTempPath(),
            new Dictionary<string, CompilationUnit>(),
            new Dictionary<string, SemanticModel>(),
            Array.Empty<CompilerError>(),
            new Analyzer(),
            new[] { filePath },
            sourceTexts: new Dictionary<string, string> { [filePath] = source });

        var adapterType = typeof(CodeIntelligenceService).Assembly.GetType(
                "NSharpLang.Compiler.CodeIntelligence.NSharpCodeIntelligenceDogfoodAdapter")
            ?? throw new InvalidOperationException("Dogfood code-intelligence adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryExtractIdentifierName = adapterType.GetMethod(
                "TryExtractIdentifierName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractIdentifierName.");
        var identifierArgs = new object?[] { snapshot, filePath, source, 2, 15, null };
        Assert.True((bool)(tryExtractIdentifierName.Invoke(null, identifierArgs) ?? false));
        Assert.Equal("input", identifierArgs[5]);

        var tryExtractMemberReceiverName = adapterType.GetMethod(
                "TryExtractMemberReceiverName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractMemberReceiverName.");
        var receiverArgs = new object?[] { snapshot, filePath, source, 2, 20, null };
        Assert.True((bool)(tryExtractMemberReceiverName.Invoke(null, receiverArgs) ?? false));
        Assert.Equal("input", receiverArgs[5]);

        var tryExtractSourceContext = adapterType.GetMethod(
                "TryExtractSourceContext",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractSourceContext.");

        var contextArgs = new object?[] { snapshot, filePath, source, 2, null };
        Assert.True((bool)(tryExtractSourceContext.Invoke(null, contextArgs) ?? false));
        Assert.Equal("value := input.Count", contextArgs[4]);

        var blankContextArgs = new object?[] { snapshot, filePath, source, 3, null };
        Assert.True((bool)(tryExtractSourceContext.Invoke(null, blankContextArgs) ?? false));
        Assert.Equal(string.Empty, blankContextArgs[4]);

        var tryExtractSourceLine = adapterType.GetMethod(
                "TryExtractSourceLine",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[] { typeof(ProjectSnapshot), typeof(string), typeof(string), typeof(int), typeof(string).MakeByRefType() },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit snapshot TryExtractSourceLine.");

        var rawLineArgs = new object?[] { snapshot, filePath, source, 2, null };
        Assert.True((bool)(tryExtractSourceLine.Invoke(null, rawLineArgs) ?? false));
        Assert.Equal("    value := input.Count", rawLineArgs[4]);

        var blankLineArgs = new object?[] { snapshot, filePath, source, 3, null };
        Assert.True((bool)(tryExtractSourceLine.Invoke(null, blankLineArgs) ?? false));
        Assert.Equal(string.Empty, blankLineArgs[4]);

        var tryExtractVariableDeclarationName = adapterType.GetMethod(
                "TryExtractVariableDeclarationName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractVariableDeclarationName.");

        var variableNameArgs = new object?[] { snapshot, filePath, source, 2, null };
        Assert.True((bool)(tryExtractVariableDeclarationName.Invoke(null, variableNameArgs) ?? false));
        Assert.Equal("value", variableNameArgs[4]);

        var noVariableNameArgs = new object?[] { snapshot, filePath, source, 3, null };
        Assert.True((bool)(tryExtractVariableDeclarationName.Invoke(null, noVariableNameArgs) ?? false));
        Assert.Null(noVariableNameArgs[4]);
    }

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
            var lineMapCachedChecksumInto = programType.GetMethod(
                    "LineMapCachedChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit LineMapCachedChecksumInto.");
            var lineMapCachedQueryChecksumInto = programType.GetMethod(
                    "LineMapCachedQueryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit LineMapCachedQueryChecksumInto.");
            var lineMapTrustedCachedQueryChecksumInto = programType.GetMethod(
                    "LineMapTrustedCachedQueryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit LineMapTrustedCachedQueryChecksumInto.");
            var codeIntelligenceIdentifierSpanChecksumInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierSpanChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierSpanChecksumInto.");
            var codeIntelligenceIdentifierSpansInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierSpansInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierSpansInto.");
            var codeIntelligenceMemberReceiverChecksumInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiverChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiverChecksumInto.");
            var codeIntelligenceMemberReceiversInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiversInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiversInto.");
            var codeIntelligenceMemberReceiverCachedChecksumInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiverCachedChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiverCachedChecksumInto.");
            var codeIntelligenceMemberReceiversCachedInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiversCachedInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiversCachedInto.");
            var codeIntelligenceSourceContextChecksumInto = programType.GetMethod(
                    "CodeIntelligenceSourceContextChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceContextChecksumInto.");
            var codeIntelligenceSourceContextsInto = programType.GetMethod(
                    "CodeIntelligenceSourceContextsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceContextsInto.");
            var codeIntelligenceSourceLineChecksumInto = programType.GetMethod(
                    "CodeIntelligenceSourceLineChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceLineChecksumInto.");
            var codeIntelligenceSourceLinesInto = programType.GetMethod(
                    "CodeIntelligenceSourceLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceLinesInto.");
            var codeIntelligenceSourceLinesFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceSourceLinesFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceLinesFromLinesInto.");
            var codeIntelligenceVariableDeclarationNameChecksumInto = programType.GetMethod(
                    "CodeIntelligenceVariableDeclarationNameChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceVariableDeclarationNameChecksumInto.");
            var codeIntelligenceVariableDeclarationNamesInto = programType.GetMethod(
                    "CodeIntelligenceVariableDeclarationNamesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceVariableDeclarationNamesInto.");
            var buildCodeIntelligenceVariableDeclarationNameCacheInto = programType.GetMethod(
                    "BuildCodeIntelligenceVariableDeclarationNameCacheInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BuildCodeIntelligenceVariableDeclarationNameCacheInto.");
            var codeIntelligenceVariableDeclarationNamesFromCacheInto = programType.GetMethod(
                    "CodeIntelligenceVariableDeclarationNamesFromCacheInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceVariableDeclarationNamesFromCacheInto.");

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
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\r\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\rtwo",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\r\ntwo\rthree\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "\r\n\r\n\n\r",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);

            AssertIdentifierSpansLikeProduction(
                """
func main() {
    value := input.Count
    print value
}
""",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertIdentifierSpansLikeProduction(
                "package CompilerDogfood.Tests\r\nfunc main(): int {\r\n    return value\r\n}\r\n",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertIdentifierSpansLikeProduction(
                "func main() {\r    value := input.Count\r}\n",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertIdentifierSpansLikeProduction(
                "func main() {\n    café42 := résumé.Count\n    print café42\n}\n",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);

            AssertMemberReceiversLikeProduction(
                """
func main(customer: Customer, résumé: Profile) {
    print customer.Name
    print customer   .Name
    print customer?.Name
    print résumé.Count
}
""",
                codeIntelligenceMemberReceiverChecksumInto,
                codeIntelligenceMemberReceiversInto,
                codeIntelligenceMemberReceiverCachedChecksumInto,
                codeIntelligenceMemberReceiversCachedInto);
            AssertSourceContextsLikeProduction(
                "  first line  \n\tsecond line\r\n   \n\n café42  \n",
                codeIntelligenceSourceContextChecksumInto,
                codeIntelligenceSourceContextsInto);
            AssertSourceLinesLikeProduction(
                "  first line  \n\tsecond line\r\n   \n\n café42  \n",
                codeIntelligenceSourceLineChecksumInto,
                codeIntelligenceSourceLinesInto,
                codeIntelligenceSourceLinesFromLinesInto);
            AssertVariableDeclarationNamesLikeProduction(
                """
func main() {
    value := 1
	résumé_42 := value
    customer.Name := "Ada"
    spaced    := 4
    := missing
    noAssign
}
""",
                codeIntelligenceVariableDeclarationNameChecksumInto,
                codeIntelligenceVariableDeclarationNamesInto,
                buildCodeIntelligenceVariableDeclarationNameCacheInto,
                codeIntelligenceVariableDeclarationNamesFromCacheInto);
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
        MethodInfo getOffsetFromLineColumn,
        MethodInfo lineMapCachedChecksumInto,
        MethodInfo lineMapCachedQueryChecksumInto,
        MethodInfo lineMapTrustedCachedQueryChecksumInto)
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

        var offsets = Enumerable.Range(-1, source.Length + 3).ToArray();
        var queryLines = new List<int>();
        var queryColumns = new List<int>();
        for (var line = 1; line <= expected.Length; line++)
        {
            var lineLength = expected[line - 1].Length;
            for (var column = 0; column <= lineLength + 1; column++)
            {
                queryLines.Add(line);
                queryColumns.Add(column);
            }
        }

        queryLines.Add(0);
        queryColumns.Add(0);
        queryLines.Add(expected.Length + 1);
        queryColumns.Add(0);

        var expectedChecksum = expected.Length;
        foreach (var offset in offsets)
        {
            var expectedLineIndex = LineIndexFromOffset(expectedStarts, source.Length, offset);
            var expectedColumn = ColumnFromOffset(expectedStarts, source.Length, offset);
            expectedChecksum += expectedLineIndex * 31 + expectedColumn;
        }

        for (var i = 0; i < queryLines.Count; i++)
        {
            var line = queryLines[i];
            var column = queryColumns[i];
            var expectedOffset = -1;
            if (line >= 1 && line <= expected.Length && column >= 0 && column <= expected[line - 1].Length)
            {
                expectedOffset = expectedStarts[line - 1] + column;
            }

            expectedChecksum += expectedOffset * 17;
        }

        var cachedStarts = new int[source.Length + 1];
        var cachedLengths = new int[source.Length + 1];
        var offsetLineIndices = new int[source.Length + 1];
        var cachedChecksum = (int)(lineMapCachedChecksumInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedStarts,
                cachedLengths,
                offsetLineIndices,
                offsets,
                queryLines.ToArray(),
                queryColumns.ToArray()
            }) ?? -1);

        Assert.Equal(expectedChecksum, cachedChecksum);

        var queryOffsetLineIndices = BuildOffsetLineIndices(expectedStarts, expected.Length, source.Length);
        var queryChecksum = (int)(lineMapCachedQueryChecksumInto.Invoke(
            null,
            new object[]
            {
                expectedStarts,
                lengths,
                expected.Length,
                source.Length,
                queryOffsetLineIndices,
                offsets,
                queryLines.ToArray(),
                queryColumns.ToArray()
            }) ?? -1);

        Assert.Equal(expectedChecksum, queryChecksum);

        var trustedOffsets = Enumerable.Range(0, source.Length + 1).ToArray();
        var trustedQueryLines = new List<int>();
        var trustedQueryColumns = new List<int>();
        for (var line = 1; line <= expected.Length; line++)
        {
            var lineLength = expected[line - 1].Length;
            for (var column = 0; column <= lineLength; column++)
            {
                trustedQueryLines.Add(line);
                trustedQueryColumns.Add(column);
            }
        }

        var trustedQueryLineArray = trustedQueryLines.ToArray();
        var trustedQueryColumnArray = trustedQueryColumns.ToArray();
        var expectedTrustedChecksum = expected.Length;
        foreach (var offset in trustedOffsets)
        {
            var expectedLineIndex = LineIndexFromOffset(expectedStarts, source.Length, offset);
            var expectedColumn = ColumnFromOffset(expectedStarts, source.Length, offset);
            expectedTrustedChecksum += expectedLineIndex * 31 + expectedColumn;
        }

        for (var i = 0; i < trustedQueryLineArray.Length; i++)
        {
            expectedTrustedChecksum += (expectedStarts[trustedQueryLineArray[i] - 1] + trustedQueryColumnArray[i]) * 17;
        }

        var trustedChecksum = (int)(lineMapTrustedCachedQueryChecksumInto.Invoke(
            null,
            new object[]
            {
                expectedStarts,
                expected.Length,
                queryOffsetLineIndices,
                trustedOffsets,
                trustedQueryLineArray,
                trustedQueryColumnArray
            }) ?? -1);

        Assert.Equal(expectedTrustedChecksum, trustedChecksum);
    }

    private static void AssertIdentifierSpansLikeProduction(
        string source,
        MethodInfo codeIntelligenceIdentifierSpanChecksumInto,
        MethodInfo codeIntelligenceIdentifierSpansInto)
    {
        var lines = source.Split('\n');
        var queries = new List<(int Line, int Column)>
        {
            (0, 0),
            (lines.Length + 1, 1)
        };

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var line = lineIndex + 1;
            var lineText = lines[lineIndex];
            queries.Add((line, 0));
            queries.Add((line, 1));
            queries.Add((line, lineText.Length));
            queries.Add((line, lineText.Length + 8));

            var identifier = FindFirstIdentifierSpan(lineText);
            queries.Add((line, identifier.StartColumn));
            queries.Add((line, Math.Max(1, identifier.StartColumn - 1)));
            queries.Add((line, Math.Min(Math.Max(1, lineText.Length), identifier.StartColumn + identifier.Length)));
            queries.Add((line, Math.Min(Math.Max(1, lineText.Length), identifier.StartColumn + identifier.Length + 1)));
        }

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var queryColumns = queries.Select(static query => query.Column).ToArray();
        var expectedStarts = new int[queries.Count];
        var expectedLengths = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;
        for (var i = 0; i < queries.Count; i++)
        {
            var span = ExtractIdentifierSpanAtPosition(source, queryLines[i], queryColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
                expectedCount++;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualStarts = new int[queries.Count];
        var actualLengths = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceIdentifierSpanChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, queryColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queries.Count];
        var productionLengths = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceIdentifierSpansInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                queryColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);
    }

    private static void AssertMemberReceiversLikeProduction(
        string source,
        MethodInfo codeIntelligenceMemberReceiverChecksumInto,
        MethodInfo codeIntelligenceMemberReceiversInto,
        MethodInfo codeIntelligenceMemberReceiverCachedChecksumInto,
        MethodInfo codeIntelligenceMemberReceiversCachedInto)
    {
        var lines = source.Split('\n');
        var queries = new List<(int Line, int MemberStartColumn)>
        {
            (0, 0),
            (lines.Length + 1, 1)
        };

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var line = lineIndex + 1;
            var lineText = lines[lineIndex];
            queries.Add((line, 0));
            queries.Add((line, 1));
            queries.Add((line, lineText.Length + 8));

            for (var i = 0; i < lineText.Length - 1; i++)
            {
                if (lineText[i] == '.' && IsIdentifierChar(lineText[i + 1]))
                {
                    queries.Add((line, i + 2));
                }
            }
        }

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var memberStartColumns = queries.Select(static query => query.MemberStartColumn).ToArray();
        var expectedStarts = new int[queries.Count];
        var expectedLengths = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;
        for (var i = 0; i < queries.Count; i++)
        {
            var span = ExtractMemberReceiverSpan(source, queryLines[i], memberStartColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
                expectedCount++;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualStarts = new int[queries.Count];
        var actualLengths = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceMemberReceiverChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, memberStartColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queries.Count];
        var productionLengths = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceMemberReceiversInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                memberStartColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var receiverStartsBySeparator = new int[source.Length + 1];
        var receiverLengthsBySeparator = new int[source.Length + 1];
        var cachedStarts = new int[queries.Count];
        var cachedLengths = new int[queries.Count];
        var cachedChecksum = (int)(codeIntelligenceMemberReceiverCachedChecksumInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                receiverStartsBySeparator,
                receiverLengthsBySeparator,
                queryLines,
                memberStartColumns,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedChecksum, cachedChecksum);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);

        var productionCachedLineStarts = new int[source.Length + 1];
        var productionCachedLineLengths = new int[source.Length + 1];
        var productionReceiverStartsBySeparator = new int[source.Length + 1];
        var productionReceiverLengthsBySeparator = new int[source.Length + 1];
        var productionCachedStarts = new int[queries.Count];
        var productionCachedLengths = new int[queries.Count];
        var actualCachedCount = (int)(codeIntelligenceMemberReceiversCachedInto.Invoke(
            null,
            new object[]
            {
                source,
                productionCachedLineStarts,
                productionCachedLineLengths,
                productionReceiverStartsBySeparator,
                productionReceiverLengthsBySeparator,
                queryLines,
                memberStartColumns,
                productionCachedStarts,
                productionCachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCachedCount);
        Assert.Equal(expectedStarts, productionCachedStarts);
        Assert.Equal(expectedLengths, productionCachedLengths);
    }

    private static void AssertSourceContextsLikeProduction(
        string source,
        MethodInfo codeIntelligenceSourceContextChecksumInto,
        MethodInfo codeIntelligenceSourceContextsInto)
    {
        var lines = source.Split('\n');
        var queries = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queries.Add(line);
        }

        var queryLines = queries.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;
        var lineStarts = BuildLfLineStarts(source);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var start = -1;
            var length = 0;

            if (line >= 1 && line <= lines.Length)
            {
                var lineText = lines[line - 1];
                var trimStart = 0;
                var trimEnd = lineText.Length - 1;
                while (trimStart <= trimEnd && char.IsWhiteSpace(lineText[trimStart]))
                {
                    trimStart++;
                }

                while (trimEnd >= trimStart && char.IsWhiteSpace(lineText[trimEnd]))
                {
                    trimEnd--;
                }

                start = lineStarts[line - 1] + trimStart;
                if (trimEnd >= trimStart)
                {
                    length = trimEnd - trimStart + 1;
                }

                expectedCount++;
            }

            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceSourceContextChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var expectedContext = line >= 1 && line <= lines.Length
                ? lines[line - 1].Trim()
                : null;
            var actualContext = actualStarts[i] >= 0
                ? source.Substring(actualStarts[i], actualLengths[i])
                : null;
            Assert.Equal(expectedContext, actualContext);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceSourceContextsInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);
    }

    private static void AssertSourceLinesLikeProduction(
        string source,
        MethodInfo codeIntelligenceSourceLineChecksumInto,
        MethodInfo codeIntelligenceSourceLinesInto,
        MethodInfo codeIntelligenceSourceLinesFromLinesInto)
    {
        var lines = source.Split('\n');
        var queries = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queries.Add(line);
        }

        var queryLines = queries.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;
        var lineStarts = BuildLfLineStarts(source);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var start = -1;
            var length = 0;

            if (line >= 1 && line <= lines.Length)
            {
                start = lineStarts[line - 1];
                length = lines[line - 1].Length;
                expectedCount++;
            }

            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceSourceLineChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var expectedLine = line >= 1 && line <= lines.Length
                ? lines[line - 1]
                : null;
            var actualLine = actualStarts[i] >= 0
                ? source.Substring(actualStarts[i], actualLengths[i])
                : null;
            Assert.Equal(expectedLine, actualLine);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceSourceLinesInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var cachedStarts = new int[queryLines.Length];
        var cachedLengths = new int[queryLines.Length];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedCount = (int)(codeIntelligenceSourceLinesFromLinesInto.Invoke(
            null,
            new object[]
            {
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                queryLines,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, cachedCount);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);
    }

    private static void AssertVariableDeclarationNamesLikeProduction(
        string source,
        MethodInfo codeIntelligenceVariableDeclarationNameChecksumInto,
        MethodInfo codeIntelligenceVariableDeclarationNamesInto,
        MethodInfo buildCodeIntelligenceVariableDeclarationNameCacheInto,
        MethodInfo codeIntelligenceVariableDeclarationNamesFromCacheInto)
    {
        var lines = source.Split('\n');
        var queries = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queries.Add(line);
        }

        var queryLines = queries.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;

        for (var i = 0; i < queryLines.Length; i++)
        {
            var span = ExtractVariableDeclarationNameSpan(source, queryLines[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
            {
                expectedCount++;
            }
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceVariableDeclarationNameChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var expectedName = ExtractVariableDeclarationName(source, line);
            var actualName = actualStarts[i] >= 0
                ? lines[line - 1].Substring(actualStarts[i] - 1, actualLengths[i])
                : null;
            Assert.Equal(expectedName, actualName);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceVariableDeclarationNamesInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var cachedNameStartsByLine = new int[source.Length + 1];
        var cachedNameLengthsByLine = new int[source.Length + 1];
        var cachedStarts = new int[queryLines.Length];
        var cachedLengths = new int[queryLines.Length];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedDeclarationCount = (int)(buildCodeIntelligenceVariableDeclarationNameCacheInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                cachedNameStartsByLine,
                cachedNameLengthsByLine
            }) ?? -1);

        Assert.Equal(expectedCount, cachedDeclarationCount);

        var cachedMatchCount = (int)(codeIntelligenceVariableDeclarationNamesFromCacheInto.Invoke(
            null,
            new object[]
            {
                lineCount,
                cachedNameStartsByLine,
                cachedNameLengthsByLine,
                queryLines,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, cachedMatchCount);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);
    }

    private static (int StartColumn, int Length) FindFirstIdentifierSpan(string lineText)
    {
        for (var i = 0; i < lineText.Length; i++)
        {
            if (!IsIdentifierChar(lineText[i]))
                continue;

            var start = i;
            while (i + 1 < lineText.Length && IsIdentifierChar(lineText[i + 1]))
                i++;

            return (start + 1, i - start + 1);
        }

        return (1, 1);
    }

    private static (int StartColumn, int Length)? ExtractIdentifierSpanAtPosition(string source, int line, int col)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            if (lineText.Length == 0)
                return null;

            var index = FindNearestIdentifierIndex(lineText, Math.Clamp(col - 1, 0, lineText.Length - 1));
            if (index < 0)
                return null;

            var start = index;
            while (start > 0 && IsIdentifierChar(lineText[start - 1]))
                start--;

            var end = index;
            while (end + 1 < lineText.Length && IsIdentifierChar(lineText[end + 1]))
                end++;

            return (start + 1, end - start + 1);
        }
        catch
        {
            return null;
        }
    }

    private static int FindNearestIdentifierIndex(string lineText, int index)
    {
        if (lineText.Length == 0)
            return -1;

        if (index >= 0 && index < lineText.Length && IsIdentifierChar(lineText[index]))
            return index;

        const int MaxDistance = 3;
        for (var distance = 1; distance <= MaxDistance; distance++)
        {
            var left = index - distance;
            if (left >= 0 && IsIdentifierChar(lineText[left]) && IsSnapFriendlyNeighbor(lineText, left + 1, index))
                return left;

            var right = index + distance;
            if (right < lineText.Length && IsIdentifierChar(lineText[right]) && IsSnapFriendlyNeighbor(lineText, index, right - 1))
                return right;
        }

        return -1;
    }

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';

    private static bool IsSnapFriendlyNeighbor(string lineText, int start, int end)
    {
        if (start > end)
            return true;

        for (var i = start; i <= end; i++)
        {
            if (i < 0 || i >= lineText.Length)
                continue;

            var ch = lineText[i];
            if (char.IsWhiteSpace(ch))
                continue;

            if (ch is '.' or '?' or '(' or ')' or '[' or ']' or '{' or '}' or ',' or ';' or ':')
                continue;

            return false;
        }

        return true;
    }

    private static (int StartColumn, int Length)? ExtractMemberReceiverSpan(string source, int line, int memberStartColumn)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            var memberStartIndex = memberStartColumn - 1;
            if (memberStartIndex <= 0 || memberStartIndex > lineText.Length)
                return null;

            var separatorIndex = memberStartIndex - 1;
            if (separatorIndex >= 0 && lineText[separatorIndex] == '.')
            {
                var receiverEnd = separatorIndex - 1;
                while (receiverEnd >= 0 && char.IsWhiteSpace(lineText[receiverEnd]))
                    receiverEnd--;
                if (receiverEnd < 0)
                    return null;

                var receiverStart = receiverEnd;
                while (receiverStart >= 0 && IsIdentifierChar(lineText[receiverStart]))
                    receiverStart--;

                receiverStart++;
                return receiverStart <= receiverEnd
                    ? (receiverStart + 1, receiverEnd - receiverStart + 1)
                    : null;
            }

            if (separatorIndex >= 1 && lineText[separatorIndex - 1] == '?' && lineText[separatorIndex] == '.')
            {
                var receiverEnd = separatorIndex - 2;
                while (receiverEnd >= 0 && char.IsWhiteSpace(lineText[receiverEnd]))
                    receiverEnd--;
                if (receiverEnd < 0)
                    return null;

                var receiverStart = receiverEnd;
                while (receiverStart >= 0 && IsIdentifierChar(lineText[receiverStart]))
                    receiverStart--;

                receiverStart++;
                return receiverStart <= receiverEnd
                    ? (receiverStart + 1, receiverEnd - receiverStart + 1)
                    : null;
            }

            return null;
        }
        catch
        {
            return null;
        }
    }

    private static string? ExtractVariableDeclarationName(string source, int line)
    {
        var span = ExtractVariableDeclarationNameSpan(source, line);
        if (span == null)
            return null;

        var lineText = source.Split('\n')[line - 1];
        return lineText.Substring(span.Value.StartColumn - 1, span.Value.Length);
    }

    private static (int StartColumn, int Length)? ExtractVariableDeclarationNameSpan(string source, int line)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            var assignIndex = lineText.IndexOf(":=", StringComparison.Ordinal);
            if (assignIndex <= 0)
                return null;

            var end = assignIndex - 1;
            while (end >= 0 && char.IsWhiteSpace(lineText[end]))
                end--;
            if (end < 0)
                return null;

            var start = end;
            while (start >= 0 && IsIdentifierChar(lineText[start]))
                start--;

            start++;
            return start <= end
                ? (start + 1, end - start + 1)
                : null;
        }
        catch
        {
            return null;
        }
    }

    private static int BuildLineRanges(string source, int[] starts, int[] lengths)
    {
        var lineStart = 0;
        var count = 0;

        for (var position = 0; position < source.Length; position++)
        {
            if (source[position] != '\n')
                continue;

            starts[count] = lineStart;
            lengths[count] = position - lineStart;
            count++;
            lineStart = position + 1;
        }

        starts[count] = lineStart;
        lengths[count] = source.Length - lineStart;
        return count + 1;
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

    private static int[] BuildOffsetLineIndices(int[] starts, int lineCount, int sourceLength)
    {
        var offsetLineIndices = new int[sourceLength + 1];
        for (var lineIndex = 0; lineIndex < lineCount; lineIndex++)
        {
            var lineStart = starts[lineIndex];
            var endExclusive = lineIndex + 1 < lineCount ? starts[lineIndex + 1] : sourceLength + 1;
            for (var offset = lineStart; offset < endExclusive && offset <= sourceLength; offset++)
            {
                offsetLineIndices[offset] = lineIndex;
            }
        }

        return offsetLineIndices;
    }

    private static int[] BuildLfLineStarts(string source)
    {
        var starts = new List<int> { 0 };
        for (var i = 0; i < source.Length; i++)
        {
            if (source[i] == '\n')
            {
                starts.Add(i + 1);
            }
        }

        return starts.ToArray();
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

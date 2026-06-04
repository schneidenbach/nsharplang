using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Baseline corpus for rewriting compiler services in N#.
///
/// This benchmark tracks the current C# lexer as the full allocating implementation. A ported N#
/// lexer candidate must add a matching benchmark over the same corpus and return the same token
/// sequence, not just the same count.
/// The dogfood rewrite gate is C# mean / N# mean >= <see cref="RequiredNSharpSpeedup"/>.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceLexerBenchmarks
{
    public const double RequiredNSharpSpeedup = 5.0;

    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus);
    }

    [Benchmark(Baseline = true)]
    public int CSharpLexer_Tokenize()
    {
        var lexer = new Lexer(_source, $"{Corpus}.nl");
        return lexer.Tokenize().Count;
    }
}

/// <summary>
/// First dogfood scanner benchmark for N#-emitted IL.
///
/// This is intentionally a count-only scanner, paired with a count-only C# implementation over the
/// same algorithm. It does not replace the full lexer-token benchmark above; it measures whether the
/// N# systems-oriented hot loop can beat the comparable C# loop before the production token objects
/// and trivia model are ported.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceLexerScannerBenchmarks
{
    private Func<string, int> _nsharpCountTokens = _ => throw new InvalidOperationException("Benchmark not initialized.");
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus);
        _nsharpCountTokens = NSharpCompiledMethod.Bind<Func<string, int>>(NSharpScannerSource, "TokenizeCount");

        var expectedTokenCount = new Lexer(_source, $"{Corpus}.nl").Tokenize().Count;
        var csharpCount = CompilerLexerCountingScanner.CountTokens(_source);
        if (csharpCount != expectedTokenCount)
        {
            throw new InvalidOperationException(
                $"C# scanner count mismatch for {Corpus}: expected {expectedTokenCount}, got {csharpCount}.");
        }

        var nsharpCount = _nsharpCountTokens(_source);
        if (nsharpCount != expectedTokenCount)
        {
            throw new InvalidOperationException(
                $"N# scanner count mismatch for {Corpus}: expected {expectedTokenCount}, got {nsharpCount}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpScanner_CountTokens() => CompilerLexerCountingScanner.CountTokens(_source);

    [Benchmark]
    public int NSharpScanner_CountTokens() => _nsharpCountTokens(_source);

    internal static string NSharpScannerSource => DogfoodCompilerSources.LexerTokenKindScanner;
}

/// <summary>
/// Token-kind sequence benchmark for the N# lexer candidate.
///
/// This is a stricter step than count parity: the N# scanner must emit the same TokenType sequence
/// as the current C# lexer over the shared corpora. It still is not the production lexer rewrite
/// because it does not emit token text, positions, comments, or diagnostics.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceLexerTokenKindBenchmarks
{
    private Func<string, int[]> _nsharpTokenizeKinds =
        _ => throw new InvalidOperationException("Benchmark not initialized.");
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus);
        _nsharpTokenizeKinds = NSharpCompiledMethod.Bind<Func<string, int[]>>(
            CompilerServiceLexerScannerBenchmarks.NSharpScannerSource,
            "TokenizeKinds");

        var expected = CSharpLexer_TokenKinds();
        var actual = _nsharpTokenizeKinds(_source);
        if (!expected.SequenceEqual(actual))
        {
            var mismatch = FirstMismatch(expected, actual);
            throw new InvalidOperationException(
                $"N# token-kind sequence mismatch for {Corpus} at index {mismatch}: " +
                $"expected {FormatKindAt(expected, mismatch)}, got {FormatKindAt(actual, mismatch)}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int[] CSharpLexer_TokenKinds()
    {
        var lexer = new Lexer(_source, $"{Corpus}.nl");
        return lexer.Tokenize().Select(static token => (int)token.Type).ToArray();
    }

    [Benchmark]
    public int[] NSharpScanner_TokenKinds() => _nsharpTokenizeKinds(_source);

    private static int FirstMismatch(int[] expected, int[] actual)
    {
        var length = Math.Min(expected.Length, actual.Length);
        for (var i = 0; i < length; i++)
        {
            if (expected[i] != actual[i])
            {
                return i;
            }
        }

        return length;
    }

    private static string FormatKindAt(int[] kinds, int index) =>
        index < kinds.Length
            ? $"{(TokenType)kinds[index]}({kinds[index]})"
            : "<missing>";
}

/// <summary>
/// Token-kind benchmark for the caller-owned buffer shape the production lexer needs.
///
/// This keeps the token-kind parity requirement while removing the known N# pressure point where
/// returning an exact array forces a second copy of the filled prefix. The benchmark still compares
/// against the current C# lexer as the production baseline; the N# path writes compact token kinds
/// into a reusable buffer and returns the filled count.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceLexerReusableTokenKindBenchmarks
{
    private Func<string, int[], int> _nsharpTokenizeKindsInto =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpBuffer = Array.Empty<int>();
    private int[] _expectedKinds = Array.Empty<int>();
    private int[] _nsharpBuffer = Array.Empty<int>();
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus);
        _nsharpTokenizeKindsInto = NSharpCompiledMethod.Bind<Func<string, int[], int>>(
            CompilerServiceLexerScannerBenchmarks.NSharpScannerSource,
            "TokenizeKindsInto");
        _csharpBuffer = new int[_source.Length + 1];
        _nsharpBuffer = new int[_source.Length + 1];
        _expectedKinds = BuildExpectedKinds();

        var csharpCount = CSharpLexer_TokenKindsIntoBuffer();
        VerifyBuffer("C# lexer buffer", _expectedKinds, _csharpBuffer, csharpCount, Corpus);

        var nsharpCount = _nsharpTokenizeKindsInto(_source, _nsharpBuffer);
        VerifyBuffer("N# token-kind buffer", _expectedKinds, _nsharpBuffer, nsharpCount, Corpus);
    }

    [Benchmark(Baseline = true)]
    public int CSharpLexer_TokenKindsIntoBuffer()
    {
        var tokens = new Lexer(_source, $"{Corpus}.nl").Tokenize();
        for (var i = 0; i < tokens.Count; i++)
        {
            _csharpBuffer[i] = (int)tokens[i].Type;
        }

        return tokens.Count;
    }

    [Benchmark]
    public int NSharpScanner_TokenKindsIntoBuffer() => _nsharpTokenizeKindsInto(_source, _nsharpBuffer);

    private int[] BuildExpectedKinds()
    {
        var lexer = new Lexer(_source, $"{Corpus}.nl");
        return lexer.Tokenize().Select(static token => (int)token.Type).ToArray();
    }

    private static void VerifyBuffer(
        string label,
        int[] expected,
        int[] actual,
        int actualCount,
        CompilerLexerCorpus corpus)
    {
        if (actualCount != expected.Length)
        {
            throw new InvalidOperationException(
                $"{label} count mismatch for {corpus}: expected {expected.Length}, got {actualCount}.");
        }

        for (var i = 0; i < expected.Length; i++)
        {
            if (expected[i] != actual[i])
            {
                throw new InvalidOperationException(
                    $"{label} mismatch for {corpus} at index {i}: " +
                    $"expected {(TokenType)expected[i]}({expected[i]}), got {(TokenType)actual[i]}({actual[i]}).");
            }
        }
    }
}

/// <summary>
/// Production-shaped lexer metadata benchmark for the N# scanner candidate.
///
/// This advances beyond token-kind parity: the N# path writes token kind, source start, token value
/// length, line, and column into caller-owned buffers. It still does not model comment trivia,
/// diagnostics, or indentation-token insertion for indentation-only corpora.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceLexerMetadataBenchmarks
{
    private Func<string, int[], int[], int[], int[], int[], int> _nsharpTokenizeMetadataInto =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpColumns = Array.Empty<int>();
    private int[] _csharpKinds = Array.Empty<int>();
    private int[] _csharpLines = Array.Empty<int>();
    private int[] _csharpStarts = Array.Empty<int>();
    private int[] _csharpValueLengths = Array.Empty<int>();
    private int _expectedCount;
    private int[] _expectedColumns = Array.Empty<int>();
    private int[] _expectedKinds = Array.Empty<int>();
    private int[] _expectedLines = Array.Empty<int>();
    private int[] _expectedStarts = Array.Empty<int>();
    private int[] _expectedValueLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int[] _nsharpColumns = Array.Empty<int>();
    private int[] _nsharpKinds = Array.Empty<int>();
    private int[] _nsharpLines = Array.Empty<int>();
    private int[] _nsharpStarts = Array.Empty<int>();
    private int[] _nsharpValueLengths = Array.Empty<int>();
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus);
        _lineStarts = BuildLineStarts(_source);
        _nsharpTokenizeMetadataInto = NSharpCompiledMethod.Bind<Func<string, int[], int[], int[], int[], int[], int>>(
            CompilerServiceLexerScannerBenchmarks.NSharpScannerSource,
            "TokenizeMetadataInto");

        var capacity = _source.Length + 1;
        _csharpKinds = new int[capacity];
        _csharpStarts = new int[capacity];
        _csharpValueLengths = new int[capacity];
        _csharpLines = new int[capacity];
        _csharpColumns = new int[capacity];
        _expectedKinds = new int[capacity];
        _expectedStarts = new int[capacity];
        _expectedValueLengths = new int[capacity];
        _expectedLines = new int[capacity];
        _expectedColumns = new int[capacity];
        _nsharpKinds = new int[capacity];
        _nsharpStarts = new int[capacity];
        _nsharpValueLengths = new int[capacity];
        _nsharpLines = new int[capacity];
        _nsharpColumns = new int[capacity];

        _expectedCount = FillCSharpMetadata(
            _expectedKinds,
            _expectedStarts,
            _expectedValueLengths,
            _expectedLines,
            _expectedColumns);

        var csharpCount = CSharpLexer_TokenMetadataIntoBuffers();
        VerifyMetadata(
            "C# lexer metadata",
            _expectedCount,
            _expectedKinds,
            _expectedStarts,
            _expectedValueLengths,
            _expectedLines,
            _expectedColumns,
            csharpCount,
            _csharpKinds,
            _csharpStarts,
            _csharpValueLengths,
            _csharpLines,
            _csharpColumns,
            Corpus);

        var nsharpCount = _nsharpTokenizeMetadataInto(
            _source,
            _nsharpKinds,
            _nsharpStarts,
            _nsharpValueLengths,
            _nsharpLines,
            _nsharpColumns);
        VerifyMetadata(
            "N# lexer metadata",
            _expectedCount,
            _expectedKinds,
            _expectedStarts,
            _expectedValueLengths,
            _expectedLines,
            _expectedColumns,
            nsharpCount,
            _nsharpKinds,
            _nsharpStarts,
            _nsharpValueLengths,
            _nsharpLines,
            _nsharpColumns,
            Corpus);
    }

    [Benchmark(Baseline = true)]
    public int CSharpLexer_TokenMetadataIntoBuffers() =>
        FillCSharpMetadata(_csharpKinds, _csharpStarts, _csharpValueLengths, _csharpLines, _csharpColumns);

    [Benchmark]
    public int NSharpScanner_TokenMetadataIntoBuffers() =>
        _nsharpTokenizeMetadataInto(
            _source,
            _nsharpKinds,
            _nsharpStarts,
            _nsharpValueLengths,
            _nsharpLines,
            _nsharpColumns);

    private int FillCSharpMetadata(
        int[] kinds,
        int[] starts,
        int[] valueLengths,
        int[] lines,
        int[] columns)
    {
        var tokens = new Lexer(_source, $"{Corpus}.nl").Tokenize();
        for (var i = 0; i < tokens.Count; i++)
        {
            var token = tokens[i];
            kinds[i] = (int)token.Type;
            starts[i] = TokenStartFromLineColumn(_lineStarts, token.Line, token.Column, _source.Length);
            valueLengths[i] = token.Value.Length;
            lines[i] = token.Line;
            columns[i] = token.Column;
        }

        return tokens.Count;
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

    private static void VerifyMetadata(
        string label,
        int expectedCount,
        int[] expectedKinds,
        int[] expectedStarts,
        int[] expectedValueLengths,
        int[] expectedLines,
        int[] expectedColumns,
        int actualCount,
        int[] actualKinds,
        int[] actualStarts,
        int[] actualValueLengths,
        int[] actualLines,
        int[] actualColumns,
        CompilerLexerCorpus corpus)
    {
        if (actualCount != expectedCount)
        {
            throw new InvalidOperationException(
                $"{label} count mismatch for {corpus}: expected {expectedCount}, got {actualCount}.");
        }

        for (var i = 0; i < expectedCount; i++)
        {
            if (expectedKinds[i] != actualKinds[i] ||
                expectedStarts[i] != actualStarts[i] ||
                expectedValueLengths[i] != actualValueLengths[i] ||
                expectedLines[i] != actualLines[i] ||
                expectedColumns[i] != actualColumns[i])
            {
                throw new InvalidOperationException(
                    $"{label} mismatch for {corpus} at index {i}: " +
                    $"expected kind/start/length/line/column " +
                    $"{(TokenType)expectedKinds[i]}({expectedKinds[i]})/{expectedStarts[i]}/" +
                    $"{expectedValueLengths[i]}/{expectedLines[i]}/{expectedColumns[i]}, got " +
                    $"{(TokenType)actualKinds[i]}({actualKinds[i]})/{actualStarts[i]}/" +
                    $"{actualValueLengths[i]}/{actualLines[i]}/{actualColumns[i]}.");
            }
        }
    }
}

internal static class CompilerLexerCorpusSources
{
    public static string Build(CompilerLexerCorpus corpus) => corpus switch
    {
        CompilerLexerCorpus.Representative => BuildRepresentativeCorpus(),
        CompilerLexerCorpus.LargeGenerated => BuildLargeGeneratedCorpus(),
        _ => throw new InvalidOperationException($"Unknown lexer corpus: {corpus}")
    };

    private static string BuildRepresentativeCorpus()
    {
        var builder = new StringBuilder(capacity: 8 * 1024);
        builder.AppendLine("import System");
        builder.AppendLine("import System.Collections.Generic");
        builder.AppendLine();
        builder.AppendLine("package CompilerDogfood");
        builder.AppendLine();
        builder.AppendLine("// Single-line comments and doc comments are preserved for formatter trivia.");
        builder.AppendLine("/// <summary>A representative lexer service input.</summary>");
        builder.AppendLine("class DiagnosticFormatter {");
        builder.AppendLine("    cache: Dictionary<string, string> = new Dictionary<string, string>()");
        builder.AppendLine("    readonly prefix: string");
        builder.AppendLine();
        builder.AppendLine("    constructor(prefix: string) {");
        builder.AppendLine("        this.prefix = prefix");
        builder.AppendLine("    }");
        builder.AppendLine();
        builder.AppendLine("    func Format(code: string, message: string, line: int, column: int): string {");
        builder.AppendLine("        if code == \"\" {");
        builder.AppendLine("            return $\"[{prefix}] {line}:{column} {message}\"");
        builder.AppendLine("        }");
        builder.AppendLine();
        builder.AppendLine("        return $\"[{prefix}:{code}] {line}:{column} {message}\"");
        builder.AppendLine("    }");
        builder.AppendLine();
        builder.AppendLine("    func Classify(severity: int): string {");
        builder.AppendLine("        return match severity {");
        builder.AppendLine("            0 => \"info\",");
        builder.AppendLine("            1 => \"warning\",");
        builder.AppendLine("            2 => \"error\",");
        builder.AppendLine("            _ => \"unknown\"");
        builder.AppendLine("        }");
        builder.AppendLine("    }");
        builder.AppendLine("}");
        builder.AppendLine();
        builder.AppendLine("func tokenizeProbe(input: string): int {");
        builder.AppendLine("    total := 0");
        builder.AppendLine("    for i := 0; i < input.Length; i++ {");
        builder.AppendLine("        ch := input[i]");
        builder.AppendLine("        if ch == ' ' || ch == '\\n' || ch == '\\t' {");
        builder.AppendLine("            continue");
        builder.AppendLine("        }");
        builder.AppendLine();
        builder.AppendLine("        total += 1");
        builder.AppendLine("    }");
        builder.AppendLine();
        builder.AppendLine("    return total");
        builder.AppendLine("}");
        builder.AppendLine();
        builder.AppendLine("func rawText(): string {");
        builder.AppendLine("    return \"\"\"");
        builder.AppendLine("This block forces raw-string scanning, CR/LF accounting, and indentation retention.");
        builder.AppendLine("{ \"diagnostic\": \"NL001\", \"message\": \"unused local\" }");
        builder.AppendLine("\"\"\"");
        builder.AppendLine("}");
        return builder.ToString();
    }

    private static string BuildLargeGeneratedCorpus()
    {
        var builder = new StringBuilder(capacity: 512 * 1024);
        builder.AppendLine("import System");
        builder.AppendLine("import System.Collections.Generic");
        builder.AppendLine("package CompilerDogfood.Generated");
        builder.AppendLine();

        for (var i = 0; i < 500; i++)
        {
            builder.AppendLine($"class GeneratedService{i} {{");
            builder.AppendLine("    readonly name: string");
            builder.AppendLine("    items: List<string> = new List<string>()");
            builder.AppendLine();
            builder.AppendLine($"    constructor() {{");
            builder.AppendLine($"        name = \"GeneratedService{i}\"");
            builder.AppendLine("    }");
            builder.AppendLine();
            builder.AppendLine("    func Add(value: string) {");
            builder.AppendLine("        if value == null || value.Length == 0 {");
            builder.AppendLine("            return");
            builder.AppendLine("        }");
            builder.AppendLine();
            builder.AppendLine("        items.Add($\"{name}:{value}\")");
            builder.AppendLine("    }");
            builder.AppendLine();
            builder.AppendLine("    func Score(seed: int): int {");
            builder.AppendLine("        total := seed");
            builder.AppendLine("        foreach item in items {");
            builder.AppendLine("            total = total + item.Length");
            builder.AppendLine("        }");
            builder.AppendLine();
            builder.AppendLine("        return match total {");
            builder.AppendLine("            0 => 0,");
            builder.AppendLine("            x when x < 10 => x + 1,");
            builder.AppendLine("            x when x < 100 => x + 10,");
            builder.AppendLine("            _ => total");
            builder.AppendLine("        }");
            builder.AppendLine("    }");
            builder.AppendLine("}");
            builder.AppendLine();
        }

        return builder.ToString();
    }
}

internal static class DogfoodCompilerSources
{
    private const string LexerTokenKindScannerResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.LexerTokenKindScanner.nl";
    private const string SourceTextLinesResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.SourceTextLines.nl";
    private const string IdentifierSpansResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.IdentifierSpans.nl";
    private const string DiagnosticClustersResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.DiagnosticClusters.nl";
    private const string DiagnosticDeduplicationResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.DiagnosticDeduplication.nl";
    private const string TextEditOrderingResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.TextEditOrdering.nl";
    private const string BindingLookupResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.BindingLookup.nl";
    private const string SemanticScopesResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.SemanticScopes.nl";
    private const string CompletionReceiversResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.CompletionReceivers.nl";
    private const string CompletionGroupingResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.CompletionGrouping.nl";
    private const string CliQueryParsingResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.CliQueryParsing.nl";
    private const string CliDocOrderingResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.CliDocOrdering.nl";
    private const string CliTreeDependenciesResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.CliTreeDependencies.nl";
    private const string ErrorSuggestionsResourceName =
        "NSharpLang.Benchmarks.Dogfood.CompilerServices.ErrorSuggestions.nl";

    public static string LexerTokenKindScanner => ReadResource(LexerTokenKindScannerResourceName);
    public static string SourceTextLines => ReadResource(SourceTextLinesResourceName);
    public static string CodeIntelligenceIdentifierSpans =>
        ReadResource(IdentifierSpansResourceName) + Environment.NewLine + SourceTextLines;
    public static string CodeIntelligenceDiagnosticClusters => ReadResource(DiagnosticClustersResourceName);
    public static string CodeIntelligenceDiagnosticDeduplication => ReadResource(DiagnosticDeduplicationResourceName);
    public static string CodeIntelligenceTextEditOrdering => ReadResource(TextEditOrderingResourceName);
    public static string CodeIntelligenceBindingLookup => ReadResource(BindingLookupResourceName);
    public static string CodeIntelligenceSemanticScopes => ReadResource(SemanticScopesResourceName);
    public static string CodeIntelligenceCompletionReceivers => ReadResource(CompletionReceiversResourceName);
    public static string CodeIntelligenceCompletionGrouping => ReadResource(CompletionGroupingResourceName);
    public static string CliQueryParsing => ReadResource(CliQueryParsingResourceName);
    public static string CliDocOrdering => ReadResource(CliDocOrderingResourceName);
    public static string CliTreeDependencies => ReadResource(CliTreeDependenciesResourceName);
    public static string ErrorSuggestions => ReadResource(ErrorSuggestionsResourceName);

    private static string ReadResource(string resourceName)
    {
        var assembly = typeof(DogfoodCompilerSources).GetTypeInfo().Assembly;
        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Missing embedded N# dogfood source '{resourceName}'.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}

internal static class CompilerLexerCountingScanner
{
    public static int CountTokens(string source)
    {
        var position = 0;
        var count = 0;
        var length = source.Length;

        while (position < length)
        {
            var ch = source[position];

            if (IsWhitespaceExceptNewline(ch))
            {
                position++;
                continue;
            }

            if (ch == '\n')
            {
                count++;
                position++;
                continue;
            }

            if (ch == '\r')
            {
                count++;
                position++;
                if (position < length && source[position] == '\n')
                {
                    position++;
                }
                continue;
            }

            if (ch == '/' && position + 1 < length)
            {
                var next = source[position + 1];
                if (next == '/')
                {
                    position += 2;
                    while (position < length && source[position] != '\n' && source[position] != '\r')
                    {
                        position++;
                    }
                    continue;
                }

                if (next == '*')
                {
                    position += 2;
                    while (position < length)
                    {
                        if (source[position] == '*' && position + 1 < length && source[position + 1] == '/')
                        {
                            position += 2;
                            break;
                        }

                        position++;
                    }
                    continue;
                }
            }

            if (ch == '$' && position + 1 < length && source[position + 1] == '"')
            {
                count++;
                position = position + 3 < length && source[position + 2] == '"' && source[position + 3] == '"'
                    ? ScanRawString(source, position + 4)
                    : ScanString(source, position + 1, isInterpolated: true);
                continue;
            }

            if (ch == '"')
            {
                count++;
                position = position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"'
                    ? ScanRawString(source, position + 3)
                    : ScanString(source, position, isInterpolated: false);
                continue;
            }

            if (ch == '\'')
            {
                count++;
                position = ScanCharLiteral(source, position);
                continue;
            }

            if (IsDigit(ch))
            {
                count++;
                position = ScanNumber(source, position);
                continue;
            }

            if (IsIdentifierStart(ch))
            {
                count++;
                position++;
                while (position < length && IsIdentifierPart(source[position]))
                {
                    position++;
                }
                continue;
            }

            count++;
            position = ScanOperator(source, position);
        }

        return count + 1;
    }

    private static int ScanString(string source, int position, bool isInterpolated)
    {
        position++;
        var interpolationDepth = 0;
        var nestedStringDepth = 0;

        while (position < source.Length)
        {
            var ch = source[position];
            if (ch is '\n' or '\r')
            {
                return position;
            }

            if (isInterpolated)
            {
                if (nestedStringDepth > 0)
                {
                    if (ch == '\\')
                    {
                        position += 2;
                        continue;
                    }

                    if (ch == '"')
                    {
                        nestedStringDepth--;
                    }

                    position++;
                    continue;
                }

                if (ch == '{')
                {
                    interpolationDepth++;
                    position++;
                    continue;
                }

                if (ch == '}' && interpolationDepth > 0)
                {
                    interpolationDepth--;
                    position++;
                    continue;
                }

                if (ch == '"' && interpolationDepth > 0)
                {
                    nestedStringDepth++;
                    position++;
                    continue;
                }

                if (ch == '"' && interpolationDepth == 0)
                {
                    return position + 1;
                }
            }
            else if (ch == '"')
            {
                return position + 1;
            }

            position += ch == '\\' ? 2 : 1;
        }

        return position;
    }

    private static int ScanRawString(string source, int position)
    {
        while (position < source.Length)
        {
            if (source[position] == '"' &&
                position + 2 < source.Length &&
                source[position + 1] == '"' &&
                source[position + 2] == '"')
            {
                return position + 3;
            }

            position++;
        }

        return position;
    }

    private static int ScanCharLiteral(string source, int position)
    {
        position++;
        if (position >= source.Length || source[position] is '\n' or '\r')
        {
            return position;
        }

        position += source[position] == '\\' ? 2 : 1;
        if (position < source.Length && source[position] == '\'')
        {
            position++;
        }

        return position;
    }

    private static int ScanNumber(string source, int position)
    {
        if (source[position] == '0' &&
            position + 1 < source.Length &&
            (source[position + 1] == 'x' || source[position + 1] == 'X'))
        {
            position += 2;
            while (position < source.Length && (IsHexDigit(source[position]) || source[position] == '_'))
            {
                position++;
            }

            return ConsumeIntegerSuffix(source, position);
        }

        if (source[position] == '0' &&
            position + 1 < source.Length &&
            (source[position + 1] == 'b' || source[position + 1] == 'B'))
        {
            position += 2;
            while (position < source.Length &&
                   (source[position] == '0' || source[position] == '1' || source[position] == '_'))
            {
                position++;
            }

            return ConsumeIntegerSuffix(source, position);
        }

        var isFloat = false;
        while (position < source.Length &&
               (IsDigit(source[position]) || source[position] == '.' || source[position] == '_'))
        {
            if (source[position] == '.')
            {
                if (position + 1 < source.Length && source[position + 1] == '.')
                {
                    break;
                }

                if (position + 1 >= source.Length || !IsDigit(source[position + 1]))
                {
                    break;
                }

                isFloat = true;
            }

            position++;
        }

        if (position < source.Length && (source[position] == 'e' || source[position] == 'E'))
        {
            isFloat = true;
            position++;
            if (position < source.Length && (source[position] == '+' || source[position] == '-'))
            {
                position++;
            }

            while (position < source.Length && (IsDigit(source[position]) || source[position] == '_'))
            {
                position++;
            }
        }

        if (isFloat)
        {
            return ConsumeFloatSuffix(source, position);
        }

        if (position < source.Length && (source[position] == 'm' || source[position] == 'M'))
        {
            return position + 1;
        }

        return ConsumeIntegerSuffix(source, position);
    }

    private static int ConsumeFloatSuffix(string source, int position)
    {
        return position < source.Length &&
               (source[position] == 'f' || source[position] == 'F' ||
                source[position] == 'd' || source[position] == 'D' ||
                source[position] == 'm' || source[position] == 'M')
            ? position + 1
            : position;
    }

    private static int ConsumeIntegerSuffix(string source, int position)
    {
        if (position < source.Length && (source[position] == 'u' || source[position] == 'U'))
        {
            position++;
            if (position < source.Length && (source[position] == 'l' || source[position] == 'L'))
            {
                position++;
            }
            return position;
        }

        if (position < source.Length && (source[position] == 'l' || source[position] == 'L'))
        {
            position++;
            if (position < source.Length && (source[position] == 'u' || source[position] == 'U'))
            {
                position++;
            }
            return position;
        }

        return position;
    }

    private static int ScanOperator(string source, int position)
    {
        var ch = source[position];
        if (position + 1 >= source.Length)
        {
            return position + 1;
        }

        var next = source[position + 1];
        return ch switch
        {
            ':' when next is '=' or ':' => position + 2,
            '=' when next is '=' or '>' => position + 2,
            '!' when next == '=' => position + 2,
            '<' when next is '=' or '<' => position + 2,
            '>' when next is '=' or '>' => position + 2,
            '&' when next == '&' => position + 2,
            '|' when next == '|' => position + 2,
            '+' when next is '+' or '=' => position + 2,
            '-' when next is '-' or '=' => position + 2,
            '*' when next == '=' => position + 2,
            '/' when next == '=' => position + 2,
            '?' when next is '.' or '[' => position + 2,
            '?' when next == '?' && position + 2 < source.Length && source[position + 2] == '=' => position + 3,
            '?' when next == '?' => position + 2,
            '.' when next == '.' && position + 2 < source.Length && source[position + 2] == '.' => position + 3,
            '.' when next == '.' => position + 2,
            _ => position + 1
        };
    }

    private static bool IsWhitespaceExceptNewline(char ch) => ch is ' ' or '\t' or '\f' or '\v';
    private static bool IsIdentifierStart(char ch) => ch == '_' || ch is >= 'A' and <= 'Z' || ch is >= 'a' and <= 'z';
    private static bool IsIdentifierPart(char ch) => IsIdentifierStart(ch) || IsDigit(ch);
    private static bool IsDigit(char ch) => ch is >= '0' and <= '9';
    private static bool IsHexDigit(char ch) => IsDigit(ch) || ch is >= 'a' and <= 'f' || ch is >= 'A' and <= 'F';
}

public enum CompilerLexerCorpus
{
    Representative,
    LargeGenerated
}

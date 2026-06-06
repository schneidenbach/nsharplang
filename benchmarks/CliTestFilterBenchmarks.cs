using System;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc test --filter</c> test-case selection. The C# baseline mirrors the
/// previous production predicate: each test case splits the filter on <c>|</c>, trims entries, and
/// scans display/fully-qualified names with ordinal-ignore-case matching. The N# candidate scans the
/// filter segments directly once per candidate and writes selected source indices to caller-owned
/// storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliTestFilterMatchingBenchmarks
{
    private const int LargeCaseCount = 8192;
    private const int RepresentativeCaseCount = 1024;

    private Func<string[], string[], string[], string[], int, int[], int> _nsharpMatchIndices =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private string _filter = string.Empty;
    private string[] _filterParts = Array.Empty<string>();
    private string[] _displayNames = Array.Empty<string>();
    private string[] _rawDisplayNames = Array.Empty<string>();
    private string[] _fullyQualifiedNames = Array.Empty<string>();
    private int[] _resultIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        CliTestFilterPattern.SinglePart,
        CliTestFilterPattern.MultiPart,
        CliTestFilterPattern.NoMatch)]
    public CliTestFilterPattern Pattern { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpMatchIndices =
            NSharpCompiledMethod.Bind<Func<string[], string[], string[], string[], int, int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliTestFilterMatchIndicesInto");

        var caseCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeCaseCount
            : LargeCaseCount;
        _displayNames = new string[caseCount];
        _rawDisplayNames = new string[caseCount];
        _fullyQualifiedNames = new string[caseCount];
        _resultIndices = new int[caseCount];
        for (var i = 0; i < caseCount; i++)
        {
            _displayNames[i] = i % 11 == 0
                ? $"checks generated API shape {i}"
                : $"Case {i}";
            _rawDisplayNames[i] = $"GeneratedTests.Feature{i % 37}.Case{i}";
            _fullyQualifiedNames[i] = $"NSharp.Generated.Feature{i % 37}.Tests.Case{i}";
        }

        _filter = Pattern switch
        {
            CliTestFilterPattern.SinglePart => "Feature17",
            CliTestFilterPattern.MultiPart => " generated api | CASE513 | MissingCase ",
            _ => "will-not-match-any-test-case"
        };
        _filterParts = _filter.Split(
            '|',
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var expectedChecksum = CSharpTestFilter_PerCaseSplit();
        var actualChecksum = NSharpTestFilter_IndexSelection();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# test filter checksum mismatch for {Corpus}/{Pattern}: expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTestFilter_PerCaseSplit()
    {
        var checksum = 0;
        var matchCount = 0;
        for (var i = 0; i < _displayNames.Length; i++)
        {
            if (MatchesCSharpFilter(_displayNames[i], _rawDisplayNames[i], _fullyQualifiedNames[i], _filter))
            {
                checksum += (i + 1) * 17;
                matchCount++;
            }
        }

        return checksum + matchCount * 31;
    }

    [Benchmark]
    public int NSharpTestFilter_IndexSelection()
    {
        var matchCount = _nsharpMatchIndices(
            _filterParts,
            _displayNames,
            _rawDisplayNames,
            _fullyQualifiedNames,
            _displayNames.Length,
            _resultIndices);

        var checksum = 0;
        for (var i = 0; i < matchCount; i++)
        {
            checksum += (_resultIndices[i] + 1) * 17;
        }

        return checksum + matchCount * 31;
    }

    private static bool MatchesCSharpFilter(
        string displayName,
        string rawDisplayName,
        string fullyQualifiedName,
        string filter)
    {
        return filter.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Any(part =>
                displayName.Contains(part, StringComparison.OrdinalIgnoreCase)
                || rawDisplayName.Contains(part, StringComparison.OrdinalIgnoreCase)
                || fullyQualifiedName.Contains(part, StringComparison.OrdinalIgnoreCase));
    }
}

public enum CliTestFilterPattern
{
    SinglePart,
    MultiPart,
    NoMatch
}

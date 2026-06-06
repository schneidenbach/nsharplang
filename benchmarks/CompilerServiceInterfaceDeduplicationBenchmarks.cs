using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for first-source interface de-duplication in the IL compiler after direct
/// and inherited interfaces have been expanded. The C# baseline mirrors the fallback shape:
/// group by ordinal type key, keep the first interface in each group, and materialize the result.
/// The N# candidate runs after the host has assigned dense type-key ranks and writes first-source
/// indices into caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceInterfaceDeduplicationBenchmarks
{
    private const int LargeInterfaceCount = 8192;
    private const int RepresentativeInterfaceCount = 1024;

    private int _interfaceCount;
    private int _uniqueRankCount;
    private string[] _typeKeys = Array.Empty<string>();
    private int[] _typeRanks = Array.Empty<int>();
    private int[] _rankWeights = Array.Empty<int>();
    private int[] _nsharpSeenRanks = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int _csharpResultCount;
    private Func<int[], int, int[], int[], int[], int> _nsharpFirstDistinctRankChecksumInto =
        (_, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _interfaceCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeInterfaceCount
            : LargeInterfaceCount;
        _nsharpFirstDistinctRankChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticDeduplication,
                "FirstDistinctRankChecksumInto");

        _typeKeys = new string[_interfaceCount];
        _typeRanks = new int[_interfaceCount];
        _nsharpSeenRanks = new int[_interfaceCount + 1];
        _nsharpResultIndices = new int[_interfaceCount];
        _csharpResultIndices = new int[_interfaceCount];

        BuildInterfaceKeys();
        AssignRanks();

        var expectedChecksum = CSharpInterfaces_DeduplicateFirstTypeKey();
        var actualChecksum = NSharpInterfaces_DeduplicateFirstTypeKey();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# interface deduplication checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < _csharpResultCount; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# interface deduplication mismatch for {Corpus} at result {i}: " +
                    $"expected index {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpInterfaces_DeduplicateFirstTypeKey()
    {
        Array.Clear(_csharpResultIndices);

        var resultIndices = Enumerable.Range(0, _interfaceCount)
            .GroupBy(index => _typeKeys[index], StringComparer.Ordinal)
            .Select(group => group.First())
            .ToArray();

        _csharpResultCount = resultIndices.Length;
        var checksum = resultIndices.Length;
        for (var i = 0; i < resultIndices.Length; i++)
        {
            var sourceIndex = resultIndices[i];
            _csharpResultIndices[i] = sourceIndex;
            var rank = _typeRanks[sourceIndex];
            checksum += (i + 1) * 97
                + (sourceIndex + 1) * 31
                + rank * 17
                + _rankWeights[rank] * 13;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpInterfaces_DeduplicateFirstTypeKey() =>
        _nsharpFirstDistinctRankChecksumInto(
            _typeRanks,
            _uniqueRankCount,
            _nsharpSeenRanks,
            _nsharpResultIndices,
            _rankWeights);

    private void BuildInterfaceKeys()
    {
        var uniqueCount = _interfaceCount / 4;
        for (var i = 0; i < _interfaceCount; i++)
        {
            var key = i % uniqueCount;
            _typeKeys[i] = (key % 9) switch
            {
                0 => $"System.Collections.Generic.IEnumerable`1[[NSharp.Generated.Type{key % 97}]]",
                1 => $"System.Collections.Generic.IReadOnlyList`1[[NSharp.Generated.Type{key % 89}]]",
                2 => $"System.IComparable`1[[NSharp.Generated.Type{key % 83}]]",
                3 => $"NSharp.Generated.Contracts.IShape{key % 79}",
                4 => $"NSharp.Generated.Contracts.IHasArea{key % 73}",
                5 => $"NSharp.Generated.Contracts.IEntity`1[[System.Int32,{key % 67}]]",
                6 => "System.IDisposable",
                7 => "System.Collections.IEnumerable",
                _ => $"NSharp.Generated.Contracts.IVisitor`2[[NSharp.Node{key % 61}],[NSharp.Result{key % 59}]]"
            };
        }
    }

    private void AssignRanks()
    {
        var ranksByKey = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < _typeKeys.Length; i++)
        {
            if (!ranksByKey.TryGetValue(_typeKeys[i], out var rank))
            {
                rank = ranksByKey.Count + 1;
                ranksByKey.Add(_typeKeys[i], rank);
            }

            _typeRanks[i] = rank;
        }

        _uniqueRankCount = ranksByKey.Count;
        _rankWeights = new int[_uniqueRankCount + 1];
        foreach (var (key, rank) in ranksByKey)
        {
            _rankWeights[rank] = key.Length;
        }
    }
}

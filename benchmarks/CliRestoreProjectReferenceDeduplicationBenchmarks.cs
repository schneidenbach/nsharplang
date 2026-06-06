using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for project-reference de-duplication in <c>nlc restore</c> after project
/// references have been resolved to MSBuild project paths. The C# baseline mirrors the restore
/// command's fallback shape: ordinal-ignore-case <c>Distinct</c> and array materialization. The N#
/// candidate runs after the host has assigned compact equality ranks and writes first-source
/// indices through caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliRestoreProjectReferenceDeduplicationBenchmarks
{
    private const int LargeReferenceCount = 8192;
    private const int RepresentativeReferenceCount = 1024;

    private readonly Dictionary<string, int> _rankByReference = new(StringComparer.OrdinalIgnoreCase);
    private Func<int[], int, int[], int[], int[], int> _nsharpStableDistinctRankChecksumInto =
        (_, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpResultIndices = Array.Empty<int>();
    private int[] _firstSourceIndexByRank = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _nsharpSeenRanks = Array.Empty<int>();
    private int[] _rankWeights = Array.Empty<int>();
    private int[] _referenceRanks = Array.Empty<int>();
    private string[] _references = Array.Empty<string>();
    private int _referenceCount;
    private int _uniqueRankCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _referenceCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeReferenceCount
            : LargeReferenceCount;
        _nsharpStableDistinctRankChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliStableDistinctRankChecksumInto");

        _references = new string[_referenceCount];
        _referenceRanks = new int[_referenceCount];
        _rankWeights = new int[_referenceCount + 1];
        _firstSourceIndexByRank = new int[_referenceCount + 1];
        _csharpResultIndices = new int[_referenceCount];
        _nsharpSeenRanks = new int[_referenceCount + 1];
        _nsharpResultIndices = new int[_referenceCount];

        BuildProjectReferences();
        AssignRanks();

        var expectedCount = BuildCSharpExpectedIndices();
        var expectedChecksum = CSharpRestoreProjectReferences_DeduplicateOrdinalIgnoreCase();
        var actualChecksum = NSharpRestoreProjectReferences_DeduplicateOrdinalIgnoreCase();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# restore project-reference checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        for (var i = 0; i < expectedCount; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# restore project-reference mismatch for {Corpus} at result {i}: " +
                    $"expected index {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpRestoreProjectReferences_DeduplicateOrdinalIgnoreCase()
    {
        var distinctReferences = _references
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var checksum = distinctReferences.Length;
        for (var i = 0; i < distinctReferences.Length; i++)
        {
            var rank = _rankByReference[distinctReferences[i]];
            var sourceIndex = _firstSourceIndexByRank[rank];
            checksum += (i + 1) * 97
                + (sourceIndex + 1) * 31
                + rank * 17
                + _rankWeights[rank] * 13;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpRestoreProjectReferences_DeduplicateOrdinalIgnoreCase() =>
        _nsharpStableDistinctRankChecksumInto(
            _referenceRanks,
            _uniqueRankCount,
            _nsharpSeenRanks,
            _nsharpResultIndices,
            _rankWeights);

    private void BuildProjectReferences()
    {
        var uniqueCount = _referenceCount / 4;
        for (var i = 0; i < _referenceCount; i++)
        {
            var key = i % uniqueCount;
            var reference = (key % 5) switch
            {
                0 => $"/repo/services/Shared{key % 127}/Shared{key % 127}.csproj",
                1 => $"/repo/libraries/Model{key % 113}/Model{key % 113}.csproj",
                2 => $"/repo/tools/Generator{key % 109}/Generator{key % 109}.csproj",
                3 => $"/repo/features/Billing{key % 103}/Billing{key % 103}.csproj",
                _ => $"/repo/tests/Fixture{key % 97}/Fixture{key % 97}.csproj"
            };

            _references[i] = ApplyCaseVariant(reference, i / uniqueCount);
        }
    }

    private void AssignRanks()
    {
        _rankByReference.Clear();
        _uniqueRankCount = 0;
        Array.Clear(_rankWeights);
        Array.Clear(_firstSourceIndexByRank);

        for (var i = 0; i < _references.Length; i++)
        {
            var reference = _references[i];
            if (!_rankByReference.TryGetValue(reference, out var rank))
            {
                rank = ++_uniqueRankCount;
                _rankByReference.Add(reference, rank);
                _rankWeights[rank] = reference.Length;
                _firstSourceIndexByRank[rank] = i;
            }

            _referenceRanks[i] = rank;
        }
    }

    private int BuildCSharpExpectedIndices()
    {
        Array.Clear(_csharpResultIndices);

        var seenReferences = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var resultCount = 0;
        for (var i = 0; i < _references.Length; i++)
        {
            if (seenReferences.Add(_references[i]))
            {
                _csharpResultIndices[resultCount] = i;
                resultCount++;
            }
        }

        return resultCount;
    }

    private static string ApplyCaseVariant(string value, int variant) =>
        (variant % 3) switch
        {
            0 => value,
            1 => value.ToUpperInvariant(),
            _ => value.ToLowerInvariant()
        };
}

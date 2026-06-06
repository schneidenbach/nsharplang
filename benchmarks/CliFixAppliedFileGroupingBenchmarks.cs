using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for grouping applied <c>nlc fix</c> entries by file in text output.
/// The C# baseline mirrors the current CLI <c>applied.GroupBy(f => f.File)</c> shape.
/// The N# candidate runs after the host has assigned first-seen dense file ranks, then writes
/// group ranks, group spans, and grouped source indices into caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliFixAppliedFileGroupingBenchmarks
{
    private const int LargeAppliedCount = 8192;
    private const int RepresentativeAppliedCount = 1024;

    private Func<int[], int, int[], int[], int[], int[], int[], int[], int[], int> _nsharpCliFixAppliedFileGroupChecksumInto =
        (_, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private BenchmarkAppliedFixEntry[] _applied = Array.Empty<BenchmarkAppliedFixEntry>();
    private int[] _countsByRank = Array.Empty<int>();
    private int[] _csharpGroupCounts = Array.Empty<int>();
    private int[] _csharpGroupRanks = Array.Empty<int>();
    private int[] _csharpGroupStarts = Array.Empty<int>();
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int[] _fileRanks = Array.Empty<int>();
    private int[] _nsharpGroupCounts = Array.Empty<int>();
    private int[] _nsharpGroupRanks = Array.Empty<int>();
    private int[] _nsharpGroupStarts = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _offsetsByRank = Array.Empty<int>();
    private Dictionary<string, int> _ranksByFile = new(StringComparer.Ordinal);
    private int _uniqueFileRankCount;
    private int[] _writeOffsetsByRank = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpCliFixAppliedFileGroupChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliFixAppliedFileGroupChecksumInto");

        var appliedCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeAppliedCount
            : LargeAppliedCount;

        _applied = BuildAppliedFixes(appliedCount);
        _fileRanks = new int[appliedCount];
        _ranksByFile = new Dictionary<string, int>(StringComparer.Ordinal);

        for (var i = 0; i < _applied.Length; i++)
        {
            var file = _applied[i].File;
            if (!_ranksByFile.TryGetValue(file, out var rank))
            {
                rank = _ranksByFile.Count + 1;
                _ranksByFile.Add(file, rank);
            }

            _fileRanks[i] = rank;
        }

        _uniqueFileRankCount = _ranksByFile.Count;
        var rankCapacity = _uniqueFileRankCount + 1;
        _countsByRank = new int[rankCapacity];
        _offsetsByRank = new int[rankCapacity];
        _writeOffsetsByRank = new int[rankCapacity];
        _csharpGroupCounts = new int[_uniqueFileRankCount];
        _csharpGroupRanks = new int[_uniqueFileRankCount];
        _csharpGroupStarts = new int[_uniqueFileRankCount];
        _csharpResultIndices = new int[appliedCount];
        _nsharpGroupCounts = new int[_uniqueFileRankCount];
        _nsharpGroupRanks = new int[_uniqueFileRankCount];
        _nsharpGroupStarts = new int[_uniqueFileRankCount];
        _nsharpResultIndices = new int[appliedCount];

        var expectedChecksum = CSharpFixAppliedFileGrouping_OutputText();
        var actualChecksum = NSharpFixAppliedFileGrouping_OutputText();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# fix applied-file grouping checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        AssertSameGroups();
    }

    [Benchmark(Baseline = true)]
    public int CSharpFixAppliedFileGrouping_OutputText()
    {
        var groups = _applied.GroupBy(static fix => fix.File).ToList();

        var checksum = groups.Count;
        var resultOffset = 0;
        for (var groupIndex = 0; groupIndex < groups.Count; groupIndex++)
        {
            var group = groups[groupIndex];
            var rank = _ranksByFile[group.Key];
            var groupCount = 0;
            _csharpGroupRanks[groupIndex] = rank;
            _csharpGroupStarts[groupIndex] = resultOffset;

            foreach (var fix in group)
            {
                _csharpResultIndices[resultOffset + groupCount] = fix.SourceIndex;
                checksum += (fix.SourceIndex + 1) * 11 + rank * 7 + (groupCount + 1) * 5;
                groupCount++;
            }

            _csharpGroupCounts[groupIndex] = groupCount;
            checksum += (groupIndex + 1) * 97 + rank * 31 + (resultOffset + 1) * 17 + groupCount * 13;
            resultOffset += groupCount;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpFixAppliedFileGrouping_OutputText() =>
        _nsharpCliFixAppliedFileGroupChecksumInto(
            _fileRanks,
            _uniqueFileRankCount,
            _countsByRank,
            _offsetsByRank,
            _writeOffsetsByRank,
            _nsharpGroupRanks,
            _nsharpGroupStarts,
            _nsharpGroupCounts,
            _nsharpResultIndices);

    private static BenchmarkAppliedFixEntry[] BuildAppliedFixes(int count)
    {
        var applied = new BenchmarkAppliedFixEntry[count];
        for (var i = 0; i < count; i++)
        {
            var fileIndex = i % 64;
            if ((i & 7) == 0)
            {
                fileIndex = (i / 8) % 64;
            }
            else if ((i & 3) == 0)
            {
                fileIndex = (i / 4 + 17) % 64;
            }

            var file = $"src/Feature{fileIndex / 8}/File{fileIndex:00}.nl";
            var code = $"NL{(i % 37) + 1:000}";
            var title = $"Fix generated issue {i}";
            applied[i] = new BenchmarkAppliedFixEntry(i, file, code, title);
        }

        return applied;
    }

    private void AssertSameGroups()
    {
        if (!_csharpGroupRanks.SequenceEqual(_nsharpGroupRanks)
            || !_csharpGroupStarts.SequenceEqual(_nsharpGroupStarts)
            || !_csharpGroupCounts.SequenceEqual(_nsharpGroupCounts)
            || !_csharpResultIndices.SequenceEqual(_nsharpResultIndices))
        {
            throw new InvalidOperationException($"N# fix applied-file grouping output mismatch for {Corpus}.");
        }
    }

    private sealed record BenchmarkAppliedFixEntry(int SourceIndex, string File, string DiagnosticCode, string Title);
}

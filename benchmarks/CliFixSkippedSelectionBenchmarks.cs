using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for skipped-fix selection in <c>nlc fix --text</c>.
/// The C# baseline mirrors the previous text-output shape: scan all discovered fixes and use
/// <c>applied.Contains(result)</c> to remove fixes that were written or would be written. The N#
/// candidate runs after the host has projected fix safety strings into compact ranks, then writes
/// skipped result indices through caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliFixSkippedSelectionBenchmarks
{
    private const int LargeFixCount = 8192;
    private const int RepresentativeFixCount = 1024;

    private Func<int[], int, int[], int> _nsharpCliFixSkippedChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private List<BenchmarkFixEntry> _applied = new();
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int _fixCount;
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private BenchmarkFixEntry[] _results = Array.Empty<BenchmarkFixEntry>();
    private int[] _safetyRanks = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(false, true)]
    public bool IncludeReviewNeeded { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _fixCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeFixCount
            : LargeFixCount;
        _nsharpCliFixSkippedChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliFixSkippedChecksumInto");

        _results = BuildFixes(_fixCount);
        _applied = _results
            .Where(entry => ShouldApply(entry.SafetyRank, IncludeReviewNeeded))
            .ToList();
        _safetyRanks = _results.Select(entry => entry.SafetyRank).ToArray();
        _csharpResultIndices = new int[_fixCount];
        _nsharpResultIndices = new int[_fixCount];

        var expectedChecksum = CSharpFixSkipped_SelectTextOutput();
        var actualChecksum = NSharpFixSkipped_SelectTextOutput();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# skipped-fix checksum mismatch for {Corpus}/{IncludeReviewNeeded}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpFixSkipped_SelectTextOutput()
    {
        var skipped = _results
            .Where(result => !_applied.Contains(result))
            .ToList();

        var checksum = skipped.Count;
        for (var i = 0; i < skipped.Count; i++)
        {
            var index = skipped[i].Index;
            _csharpResultIndices[i] = index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + skipped[i].SafetyRank * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpFixSkipped_SelectTextOutput() =>
        _nsharpCliFixSkippedChecksumInto(
            _safetyRanks,
            IncludeReviewNeeded ? 1 : 0,
            _nsharpResultIndices);

    private static BenchmarkFixEntry[] BuildFixes(int count)
    {
        var fixes = new BenchmarkFixEntry[count];
        for (var i = 0; i < count; i++)
        {
            var safetyRank = ((i * 11 + i / 19) % 7) switch
            {
                0 or 5 => 1,
                1 or 4 => 2,
                _ => 3
            };
            fixes[i] = new BenchmarkFixEntry(
                i,
                $"src/File{i % 19}.nl",
                $"NL{i % 17:000}",
                $"Fix generated issue {i}",
                safetyRank);
        }

        return fixes;
    }

    private static bool ShouldApply(int safetyRank, bool includeReviewNeeded) =>
        safetyRank == 1 || (includeReviewNeeded && safetyRank == 2);

    private sealed record BenchmarkFixEntry(
        int Index,
        string File,
        string DiagnosticCode,
        string Title,
        int SafetyRank);
}

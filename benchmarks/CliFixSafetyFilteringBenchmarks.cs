using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for the <c>nlc fix</c> safety gate.
///
/// The C# baseline mirrors the current CLI shape: enum safety checks and list materialization over
/// fix objects. The N# candidate runs after the host projects <see cref="FixSafety" /> values into
/// compact ranks and writes matching fix indices into caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliFixSafetyFilterBenchmarks
{
    private const int LargeFixCount = 8192;
    private const int RepresentativeFixCount = 1024;

    private Func<int[], int, int[], int> _nsharpCliFixSafetyFilterChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpResultIndices = Array.Empty<int>();
    private FixActionEntry[] _fixes = Array.Empty<FixActionEntry>();
    private int _fixCount;
    private int[] _nsharpResultIndices = Array.Empty<int>();
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
        _nsharpCliFixSafetyFilterChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliFixSafetyFilterChecksumInto");

        _fixes = BuildFixes(_fixCount);
        _safetyRanks = new int[_fixCount];
        _csharpResultIndices = new int[_fixCount];
        _nsharpResultIndices = new int[_fixCount];
        BuildSafetyRanks();

        var expectedChecksum = CSharpFixSafetyFilter_Cli();
        var actualChecksum = NSharpFixSafetyFilter_Cli();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# fix safety filter checksum mismatch for {Corpus}/{IncludeReviewNeeded}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expectedIndices = _fixes
            .Where(fix => ShouldApply(fix.Safety, IncludeReviewNeeded))
            .Select(fix => fix.Index)
            .ToArray();
        if (expectedIndices.Length == 0)
        {
            throw new InvalidOperationException(
                $"Fix safety filter benchmark corpus {Corpus}/{IncludeReviewNeeded} has no matching fixes.");
        }

        for (var i = 0; i < expectedIndices.Length; i++)
        {
            if (_csharpResultIndices[i] != expectedIndices[i] || _nsharpResultIndices[i] != expectedIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# fix safety filter mismatch for {Corpus}/{IncludeReviewNeeded} at result {i}: " +
                    $"expected source index {expectedIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpFixSafetyFilter_Cli()
    {
        var filtered = _fixes
            .Where(fix => ShouldApply(fix.Safety, IncludeReviewNeeded))
            .ToList();

        var checksum = filtered.Count;
        for (var i = 0; i < filtered.Count; i++)
        {
            var index = filtered[i].Index;
            _csharpResultIndices[i] = index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + _safetyRanks[index] * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpFixSafetyFilter_Cli() =>
        _nsharpCliFixSafetyFilterChecksumInto(
            _safetyRanks,
            IncludeReviewNeeded ? 1 : 0,
            _nsharpResultIndices);

    private void BuildSafetyRanks()
    {
        for (var i = 0; i < _fixes.Length; i++)
        {
            _safetyRanks[i] = GetSafetyRank(_fixes[i].Safety);
        }
    }

    private static FixActionEntry[] BuildFixes(int count)
    {
        var fixes = new FixActionEntry[count];
        for (var i = 0; i < count; i++)
        {
            var safety = ((i * 11 + i / 19) % 7) switch
            {
                0 or 5 => FixSafety.Safe,
                1 or 4 => FixSafety.ReviewNeeded,
                _ => FixSafety.SuggestionOnly
            };
            fixes[i] = new FixActionEntry(i, safety);
        }

        return fixes;
    }

    private static bool ShouldApply(FixSafety safety, bool includeReviewNeeded) =>
        safety == FixSafety.Safe || (includeReviewNeeded && safety == FixSafety.ReviewNeeded);

    private static int GetSafetyRank(FixSafety safety) =>
        safety switch
        {
            FixSafety.Safe => 1,
            FixSafety.ReviewNeeded => 2,
            FixSafety.SuggestionOnly => 3,
            _ => 0
        };

    private sealed record FixActionEntry(int Index, FixSafety Safety);
}

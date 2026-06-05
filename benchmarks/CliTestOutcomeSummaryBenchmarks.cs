using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc test</c> outcome summary counts.
/// The C# baseline mirrors the current text-output path: one <c>All(...)</c> pass for ok plus
/// three <c>Count(...)</c> passes for passed/failed/skipped. The production-shaped N# row projects
/// public outcome strings into compact ranks, then computes all summary fields in one N# pass.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliTestOutcomeSummaryBenchmarks
{
    private const int LargeResultCount = 8192;
    private const int RepresentativeResultCount = 1024;

    private Func<int[], int, int[], int> _nsharpSummaryChecksum =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private List<BenchmarkNativeTestResult> _results = new();
    private int[] _outcomeRanks = Array.Empty<int>();
    private int[] _projectedOutcomeRanks = Array.Empty<int>();
    private int[] _nsharpCounts = Array.Empty<int>();
    private int[] _projectedCounts = Array.Empty<int>();
    private int _resultCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        CliTestOutcomePattern.AllPassed,
        CliTestOutcomePattern.MostlyPassed,
        CliTestOutcomePattern.MixedWithUnknowns)]
    public CliTestOutcomePattern Pattern { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _resultCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeResultCount
            : LargeResultCount;
        _nsharpSummaryChecksum =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliTestOutcomeSummaryChecksumInto");

        _results = BuildResults(_resultCount, Pattern);
        _outcomeRanks = new int[_resultCount];
        _projectedOutcomeRanks = new int[_resultCount];
        _nsharpCounts = new int[4];
        _projectedCounts = new int[4];
        for (var i = 0; i < _results.Count; i++)
        {
            _outcomeRanks[i] = GetOutcomeRank(_results[i].Outcome);
        }

        var expectedChecksum = CSharpTestOutcomeSummary_TextOutput();
        var actualChecksum = NSharpTestOutcomeSummary_PreRanked();
        var projectedChecksum = NSharpTestOutcomeSummary_Projected();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# test outcome summary checksum mismatch for {Corpus}/{Pattern}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (expectedChecksum != projectedChecksum)
        {
            throw new InvalidOperationException(
                $"N# projected test outcome summary checksum mismatch for {Corpus}/{Pattern}: " +
                $"expected {expectedChecksum}, got {projectedChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTestOutcomeSummary_TextOutput()
    {
        var ok = _results.All(result => result.Outcome is "passed" or "skipped");
        var passed = _results.Count(result => result.Outcome == "passed");
        var failed = _results.Count(result => result.Outcome == "failed");
        var skipped = _results.Count(result => result.Outcome == "skipped");
        var nonOk = ok ? 0 : _results.Count - passed - skipped;
        return _results.Count + (ok ? 7 : 13) + passed * 31 + failed * 17 + skipped * 11 + nonOk * 5;
    }

    [Benchmark]
    public int NSharpTestOutcomeSummary_PreRanked() =>
        _nsharpSummaryChecksum(_outcomeRanks, _resultCount, _nsharpCounts);

    [Benchmark]
    public int NSharpTestOutcomeSummary_Projected()
    {
        for (var i = 0; i < _results.Count; i++)
        {
            _projectedOutcomeRanks[i] = GetOutcomeRank(_results[i].Outcome);
        }

        return _nsharpSummaryChecksum(_projectedOutcomeRanks, _results.Count, _projectedCounts);
    }

    private static List<BenchmarkNativeTestResult> BuildResults(int count, CliTestOutcomePattern pattern)
    {
        var results = new List<BenchmarkNativeTestResult>(count);
        for (var i = 0; i < count; i++)
        {
            var outcome = pattern switch
            {
                CliTestOutcomePattern.AllPassed => "passed",
                CliTestOutcomePattern.MostlyPassed => i % 29 == 0
                    ? "skipped"
                    : i % 97 == 0
                        ? "failed"
                        : "passed",
                _ => i % 43 == 0
                    ? "timed-out"
                    : i % 17 == 0
                        ? "skipped"
                        : i % 13 == 0
                            ? "failed"
                            : "passed"
            };
            results.Add(new BenchmarkNativeTestResult(outcome));
        }

        return results;
    }

    private static int GetOutcomeRank(string outcome) =>
        outcome switch
        {
            "passed" => 1,
            "failed" => 2,
            "skipped" => 3,
            _ => 0
        };

    private sealed record BenchmarkNativeTestResult(string Outcome);
}

public enum CliTestOutcomePattern
{
    AllPassed,
    MostlyPassed,
    MixedWithUnknowns
}

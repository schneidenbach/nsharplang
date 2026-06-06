using System;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for the score-selection kernel inside CLI compilation reference resolution.
/// The C# baseline mirrors the current asset-directory candidate shape: filter candidates with a
/// non-negative compatibility score, sort by descending score, and take the first candidate. The
/// N# candidate runs after the host has projected compatibility scores into primitive arrays and
/// selects the first highest-scoring candidate with one allocation-free scan.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliReferenceResolutionBestScoreBenchmarks
{
    private const int LargeCandidateCount = 8192;
    private const int RepresentativeCandidateCount = 128;

    private Func<int[], int[], int, int> _nsharpBestScoreChecksum =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private ReferenceResolutionCandidate[] _candidates = Array.Empty<ReferenceResolutionCandidate>();
    private int[] _scores = Array.Empty<int>();
    private int[] _weights = Array.Empty<int>();
    private int _candidateCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _candidateCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeCandidateCount
            : LargeCandidateCount;
        _nsharpBestScoreChecksum =
            NSharpCompiledMethod.Bind<Func<int[], int[], int, int>>(
                DogfoodCompilerSources.CliArguments,
                "CliReferenceResolutionBestScoreChecksum");

        _candidates = BuildCandidates(_candidateCount);
        _scores = new int[_candidateCount];
        _weights = new int[_candidateCount];
        for (var i = 0; i < _candidateCount; i++)
        {
            _scores[i] = _candidates[i].Score;
            _weights[i] = _candidates[i].Weight;
        }

        var expectedChecksum = CSharpReferenceResolution_SelectBestCandidate();
        var actualChecksum = NSharpReferenceResolution_SelectBestCandidate();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# reference-resolution best-score checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpReferenceResolution_SelectBestCandidate()
    {
        var best = _candidates
            .Where(candidate => candidate.Score >= 0)
            .OrderByDescending(candidate => candidate.Score)
            .FirstOrDefault();

        return best == null ? -1 : Checksum(best.Index);
    }

    [Benchmark]
    public int NSharpReferenceResolution_SelectBestCandidate() =>
        _nsharpBestScoreChecksum(_scores, _weights, _candidateCount);

    private int Checksum(int index) =>
        (index + 1) * 97 + _scores[index] * 31 + _weights[index] * 17;

    private static ReferenceResolutionCandidate[] BuildCandidates(int count)
    {
        var candidates = new ReferenceResolutionCandidate[count];
        for (var i = 0; i < count; i++)
        {
            var family = (i * 17 + i / 7) % 23;
            var score = family switch
            {
                0 => -1,
                1 => 0,
                2 => 10,
                3 => 20,
                4 => 30,
                5 => 40,
                _ => 100 + ((i * 37 + i / 11) % 700)
            };
            var weight = 32 + ((i * 13 + i / 5) % 257);
            candidates[i] = new ReferenceResolutionCandidate(i, score, weight);
        }

        if (count > 10)
        {
            candidates[3] = new ReferenceResolutionCandidate(3, 1900, 41);
            candidates[count / 2] = new ReferenceResolutionCandidate(count / 2, 1900, 83);
        }

        return candidates;
    }

    private sealed record ReferenceResolutionCandidate(
        int Index,
        int Score,
        int Weight);
}

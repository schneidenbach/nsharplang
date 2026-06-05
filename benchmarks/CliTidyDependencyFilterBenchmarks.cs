using System;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc tidy --fix</c> dependency removal selection.
/// The C# baseline mirrors the command fallback shape: filter dependency status records with
/// <c>Status == "possibly-unused"</c> and materialize the list. The N# candidate reuses the
/// accepted compact-rank filter after the host projects tidy status strings into integer ranks.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliTidyDependencyFilterBenchmarks
{
    private const int LargeDependencyCount = 8192;
    private const int RepresentativeDependencyCount = 1024;
    private const int TargetStatusRank = 1;

    private Func<int[], int, int[], int> _nsharpStatusFilterChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpResultIndices = Array.Empty<int>();
    private int _dependencyCount;
    private TidyDependencyEntry[] _dependencies = Array.Empty<TidyDependencyEntry>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _statusRanks = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _dependencyCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDependencyCount
            : LargeDependencyCount;
        _nsharpStatusFilterChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticClusters,
                "DiagnosticSeverityFilterChecksumInto");

        _dependencies = BuildDependencies(_dependencyCount);
        _statusRanks = new int[_dependencyCount];
        _csharpResultIndices = new int[_dependencyCount];
        _nsharpResultIndices = new int[_dependencyCount];
        BuildStatusRanks();

        var expectedChecksum = CSharpTidy_FilterPossiblyUnusedDependencies();
        var actualChecksum = NSharpTidy_FilterPossiblyUnusedDependencies();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# tidy dependency filter checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expectedIndices = _dependencies
            .Where(dependency => dependency.Status == "possibly-unused")
            .Select(dependency => dependency.Index)
            .ToArray();
        if (expectedIndices.Length == 0)
        {
            throw new InvalidOperationException(
                $"Tidy dependency filter benchmark corpus {Corpus} has no possibly-unused dependencies.");
        }

        for (var i = 0; i < expectedIndices.Length; i++)
        {
            if (_csharpResultIndices[i] != expectedIndices[i] || _nsharpResultIndices[i] != expectedIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# tidy dependency filter mismatch for {Corpus} at result {i}: " +
                    $"expected source index {expectedIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTidy_FilterPossiblyUnusedDependencies()
    {
        var possiblyUnused = _dependencies
            .Where(dependency => dependency.Status == "possibly-unused")
            .ToList();

        var checksum = possiblyUnused.Count;
        for (var i = 0; i < possiblyUnused.Count; i++)
        {
            var index = possiblyUnused[i].Index;
            _csharpResultIndices[i] = index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + _statusRanks[index] * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpTidy_FilterPossiblyUnusedDependencies() =>
        _nsharpStatusFilterChecksumInto(
            _statusRanks,
            TargetStatusRank,
            _nsharpResultIndices);

    private void BuildStatusRanks()
    {
        for (var i = 0; i < _dependencies.Length; i++)
            _statusRanks[i] = GetStatusRank(_dependencies[i].Status);
    }

    private static TidyDependencyEntry[] BuildDependencies(int count)
    {
        var dependencies = new TidyDependencyEntry[count];
        for (var i = 0; i < count; i++)
        {
            var status = ((i * 17 + i / 11) % 9) switch
            {
                0 or 5 => "possibly-unused",
                1 or 4 or 7 => "unknown",
                _ => "used"
            };

            dependencies[i] = new TidyDependencyEntry(
                i,
                $"Package.{i % 257}",
                status);
        }

        return dependencies;
    }

    private static int GetStatusRank(string status) =>
        status switch
        {
            "possibly-unused" => TargetStatusRank,
            "used" => 2,
            "unknown" => 3,
            _ => 0
        };

    private sealed record TidyDependencyEntry(
        int Index,
        string Name,
        string Status);
}

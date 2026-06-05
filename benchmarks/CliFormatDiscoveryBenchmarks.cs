using System;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc format</c> discovered-file filtering after filesystem traversal has
/// produced normalized project-relative paths. The C# baseline mirrors the current split/segment
/// helper; the N# candidates scan path segments without allocating but remain unrouted until they
/// clear the speed gate.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliFormatDiscoveryBenchmarks
{
    private const int LargePathCount = 8192;
    private const int RepresentativePathCount = 1024;

    private Func<string, int> _nsharpShouldFormatDiscoveredPath =
        _ => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<string[], int[], int> _nsharpFormatPathChecksumInto =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _relativePaths = Array.Empty<string>();
    private int[] _csharpFlags = Array.Empty<int>();
    private int[] _nsharpFlags = Array.Empty<int>();
    private int[] _batchFlags = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpShouldFormatDiscoveredPath =
            NSharpCompiledMethod.Bind<Func<string, int>>(
                DogfoodCompilerSources.CliArguments,
                "CliShouldFormatDiscoveredPath");
        _nsharpFormatPathChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliFormatDiscoveredPathChecksumInto");

        var pathCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativePathCount
            : LargePathCount;
        _relativePaths = BuildRelativePaths(pathCount);
        _csharpFlags = new int[pathCount];
        _nsharpFlags = new int[pathCount];
        _batchFlags = new int[pathCount];

        var expectedChecksum = CSharpFormatDiscovery_CurrentSplitHelper();
        var actualSingleChecksum = NSharpFormatDiscovery_PerPathCandidate();
        var actualBatchChecksum = NSharpFormatDiscovery_BatchUpperBound();
        if (expectedChecksum != actualSingleChecksum)
        {
            throw new InvalidOperationException(
                $"N# format discovery checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualSingleChecksum}.");
        }

        if (expectedChecksum != actualBatchChecksum)
        {
            throw new InvalidOperationException(
                $"N# batched format discovery checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualBatchChecksum}.");
        }

        var singleMismatch = FirstMismatch(_csharpFlags, _nsharpFlags);
        if (singleMismatch >= 0)
        {
            throw new InvalidOperationException(
                $"N# format discovery mismatch for {Corpus} at path {singleMismatch} " +
                $"({_relativePaths[singleMismatch]}): expected {_csharpFlags[singleMismatch]}, " +
                $"got {_nsharpFlags[singleMismatch]}.");
        }

        var batchMismatch = FirstMismatch(_csharpFlags, _batchFlags);
        if (batchMismatch >= 0)
        {
            throw new InvalidOperationException(
                $"N# batched format discovery mismatch for {Corpus} at path {batchMismatch} " +
                $"({_relativePaths[batchMismatch]}): expected {_csharpFlags[batchMismatch]}, " +
                $"got {_batchFlags[batchMismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpFormatDiscovery_CurrentSplitHelper()
    {
        for (var i = 0; i < _relativePaths.Length; i++)
        {
            _csharpFlags[i] = CSharpShouldFormatDiscoveredRelativePath(_relativePaths[i]) ? 1 : 0;
        }

        return ChecksumFlags(_csharpFlags);
    }

    [Benchmark]
    public int NSharpFormatDiscovery_PerPathCandidate()
    {
        for (var i = 0; i < _relativePaths.Length; i++)
        {
            _nsharpFlags[i] = _nsharpShouldFormatDiscoveredPath(_relativePaths[i]);
        }

        return ChecksumFlags(_nsharpFlags);
    }

    [Benchmark]
    public int NSharpFormatDiscovery_BatchUpperBound() =>
        _nsharpFormatPathChecksumInto(_relativePaths, _batchFlags);

    private int ChecksumFlags(int[] flags)
    {
        var count = Math.Min(_relativePaths.Length, flags.Length);
        var checksum = count;
        for (var i = 0; i < count; i++)
        {
            checksum += (i + 1) * 31 + flags[i] * 17 + _relativePaths[i].Length * 7;
        }

        return checksum;
    }

    private static bool CSharpShouldFormatDiscoveredRelativePath(string relativePath)
    {
        var segments = relativePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Any(segment => segment.Equals(".git", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".hg", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".svn", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".worktrees", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".hermes", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".nlc", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("bin", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("obj", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("node_modules", StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        for (var i = 0; i <= segments.Length - 2; i++)
        {
            var isFixtureRoot = string.Equals(segments[i], "test", StringComparison.OrdinalIgnoreCase)
                || string.Equals(segments[i], "tests", StringComparison.OrdinalIgnoreCase);
            if (isFixtureRoot && string.Equals(segments[i + 1], "fixtures", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        return true;
    }

    private static string[] BuildRelativePaths(int count)
    {
        var paths = new string[count];
        for (var i = 0; i < count; i++)
        {
            paths[i] = (i % 16) switch
            {
                0 => $"src/Feature{i}/Program.nl",
                1 => $"tests/Unit{i}/Spec.nl",
                2 => $"test/fixtures/parser/case{i}.nl",
                3 => $"Tests/FIXTURES/format/case{i}.nl",
                4 => $"bin/Debug/net10.0/generated{i}.nl",
                5 => $"src/binocular/File{i}.nl",
                6 => $"node_modules/pkg{i}/index.nl",
                7 => $".nlc/cache/file{i}.nl",
                8 => $"src/.git/hooks/file{i}.nl",
                9 => $"src/obj/Generated/file{i}.nl",
                10 => $"src/test//fixtures/case{i}.nl",
                11 => $"src/tests/fixturesExtra/case{i}.nl",
                12 => $"src/.worktrees/tmp/file{i}.nl",
                13 => $"src/.hermes/cache/file{i}.nl",
                14 => $"src/.hg/store/file{i}.nl",
                _ => $"src/.svn/tmp/file{i}.nl"
            };
        }

        return paths;
    }

    private static int FirstMismatch(int[] left, int[] right)
    {
        var count = Math.Min(left.Length, right.Length);
        for (var i = 0; i < count; i++)
        {
            if (left[i] != right[i])
                return i;
        }

        return left.Length == right.Length ? -1 : count;
    }
}

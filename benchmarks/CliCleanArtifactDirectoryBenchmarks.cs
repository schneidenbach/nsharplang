using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for artifact directory selection in <c>nlc clean</c>.
/// The C# baseline mirrors the post-IO production shape: ordinal distinct, exclude node_modules,
/// keep bin/obj/.nlc directories, then stably order by descending path length before deletion. The
/// N# candidate runs after the host has projected path ranks, artifact-kind flags, node_modules
/// flags, and path lengths into compact arrays.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliCleanArtifactDirectoryBenchmarks
{
    private static readonly string[] ArtifactDirectories = { "bin", "obj", ".nlc" };

    private const int LargeDirectoryCount = 8192;
    private const int RepresentativeDirectoryCount = 1024;

    private CliCleanArtifactDirectoryChecksumInto _nsharpCleanArtifactDirectoryChecksumInto =
        (_, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private Dictionary<string, int> _firstSourceIndexByPath = new(StringComparer.Ordinal);
    private int[] _kindRanks = Array.Empty<int>();
    private int[] _lengthCounts = Array.Empty<int>();
    private int[] _lengthOffsets = Array.Empty<int>();
    private int[] _nodeModuleFlags = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _pathLengths = Array.Empty<int>();
    private int[] _pathRanks = Array.Empty<int>();
    private int[] _seenPathRanks = Array.Empty<int>();
    private int[] _tempIndices = Array.Empty<int>();
    private string[] _directories = Array.Empty<string>();
    private int _directoryCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _directoryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDirectoryCount
            : LargeDirectoryCount;
        _nsharpCleanArtifactDirectoryChecksumInto =
            NSharpCompiledMethod.Bind<CliCleanArtifactDirectoryChecksumInto>(
                DogfoodCompilerSources.CliArguments,
                "CliCleanArtifactDirectoryChecksumInto");

        _directories = BuildDirectories(_directoryCount);
        BuildCompactFacts();

        var expectedChecksum = CSharpCleanArtifacts_OrderDirectories();
        var actualChecksum = NSharpCleanArtifacts_OrderDirectories();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# clean artifact directory checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expected = OrderWithCSharp();
        for (var i = 0; i < expected.Length; i++)
        {
            var expectedIndex = _firstSourceIndexByPath[expected[i]];
            if (_nsharpResultIndices[i] != expectedIndex)
            {
                throw new InvalidOperationException(
                    $"N# clean artifact directory mismatch for {Corpus} at ordered item {i}: " +
                    $"expected source index {expectedIndex}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCleanArtifacts_OrderDirectories()
    {
        var ordered = OrderWithCSharp();
        return ChecksumOrderedDirectories(ordered);
    }

    [Benchmark]
    public int NSharpCleanArtifacts_OrderDirectories() =>
        _nsharpCleanArtifactDirectoryChecksumInto(
            _kindRanks,
            _nodeModuleFlags,
            _pathRanks,
            _pathLengths,
            _seenPathRanks,
            _lengthCounts,
            _lengthOffsets,
            _tempIndices,
            _nsharpResultIndices);

    private void BuildCompactFacts()
    {
        _firstSourceIndexByPath = new Dictionary<string, int>(StringComparer.Ordinal);
        var pathRanks = new Dictionary<string, int>(StringComparer.Ordinal);
        _kindRanks = new int[_directoryCount];
        _nodeModuleFlags = new int[_directoryCount];
        _pathRanks = new int[_directoryCount];
        _pathLengths = new int[_directoryCount];
        _tempIndices = new int[_directoryCount];
        _nsharpResultIndices = new int[_directoryCount];

        var uniquePathCount = 0;
        var maxPathLength = 0;
        for (var i = 0; i < _directories.Length; i++)
        {
            var directory = _directories[i];
            _kindRanks[i] = ArtifactDirectories.Contains(Path.GetFileName(directory), StringComparer.Ordinal)
                ? 1
                : 0;
            _nodeModuleFlags[i] = NormalizePath(directory).Contains("/node_modules/", StringComparison.Ordinal)
                ? 1
                : 0;
            _pathLengths[i] = directory.Length;
            if (directory.Length > maxPathLength)
                maxPathLength = directory.Length;

            if (!pathRanks.TryGetValue(directory, out var pathRank))
            {
                uniquePathCount++;
                pathRank = uniquePathCount;
                pathRanks.Add(directory, pathRank);
                _firstSourceIndexByPath.Add(directory, i);
            }

            _pathRanks[i] = pathRank;
        }

        _seenPathRanks = new int[uniquePathCount + 1];
        _lengthCounts = new int[maxPathLength + 1];
        _lengthOffsets = new int[maxPathLength + 1];
    }

    private string[] OrderWithCSharp() =>
        _directories
            .Distinct(StringComparer.Ordinal)
            .Where(directory => !NormalizePath(directory).Contains("/node_modules/", StringComparison.Ordinal))
            .Where(directory => ArtifactDirectories.Contains(Path.GetFileName(directory), StringComparer.Ordinal))
            .OrderByDescending(directory => directory.Length)
            .ToArray();

    private int ChecksumOrderedDirectories(IReadOnlyList<string> ordered)
    {
        var checksum = ordered.Count;
        for (var i = 0; i < ordered.Count; i++)
        {
            var index = _firstSourceIndexByPath[ordered[i]];
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + _kindRanks[index] * 17
                + _pathRanks[index] * 13
                + _pathLengths[index] * 7;
        }

        return checksum;
    }

    private static string[] BuildDirectories(int count)
    {
        var directories = new string[count];
        var names = new[] { "bin", "obj", ".nlc", "generated", "tmp", "artifacts" };
        for (var i = 0; i < count; i++)
        {
            if (i > 12 && i % 29 == 0)
            {
                directories[i] = directories[i - 11];
                continue;
            }

            var name = names[(i * 7 + i / 13) % names.Length];
            var path = $"/repo/project/src/module{i % 37}/area{i % 11}/feature{i % 53}/{name}";
            if (i % 17 == 0)
                path = $"/repo/project/node_modules/pkg{i % 23}/nested/{name}";
            if (i % 19 == 0)
                path = $"/repo/project/{name}";
            if (i % 31 == 0)
                path = $"/repo/project/src/deep/{i % 7}/very/long/generated/path/{name}";

            directories[i] = path;
        }

        return directories;
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private delegate int CliCleanArtifactDirectoryChecksumInto(
        int[] kindRanks,
        int[] nodeModuleFlags,
        int[] pathRanks,
        int[] pathLengths,
        int[] seenPathRanks,
        int[] lengthCounts,
        int[] lengthOffsets,
        int[] tempIndices,
        int[] resultIndices);
}

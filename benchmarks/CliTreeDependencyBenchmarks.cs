using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for dependency deduplication in <c>nlc tree</c>.
///
/// The C# baseline mirrors the current CLI shape: LINQ <c>GroupBy</c> over
/// <c>(Kind, Name)</c>, keep the first dependency in each group, then order by kind using ordinal
/// comparison and name using ordinal-ignore-case comparison. The N# candidate runs after the host
/// has assigned compact kind/name ranks and uses stable counting passes to return the first source
/// index for each unique dependency key in public output order.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliTreeDependencyDeduplicationBenchmarks
{
    private const int LargeDependencyCount = 8192;
    private const int RepresentativeDependencyCount = 1024;

    private CliTreeDependencyDeduplicateChecksumInto _nsharpTreeDependencyDeduplicateChecksumInto =
        (_, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _kindCounts = Array.Empty<int>();
    private int[] _kindOffsets = Array.Empty<int>();
    private int[] _kindRanks = Array.Empty<int>();
    private int[] _nameCounts = Array.Empty<int>();
    private int[] _nameOffsets = Array.Empty<int>();
    private int[] _nameRanks = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _sortedIndices = Array.Empty<int>();
    private int[] _tempIndices = Array.Empty<int>();
    private TreeDependencyEntry[] _dependencies = Array.Empty<TreeDependencyEntry>();
    private int _dependencyCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _dependencyCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDependencyCount
            : LargeDependencyCount;
        _nsharpTreeDependencyDeduplicateChecksumInto =
            NSharpCompiledMethod.Bind<CliTreeDependencyDeduplicateChecksumInto>(
                DogfoodCompilerSources.CliTreeDependencies,
                "CliTreeDependencyDeduplicateChecksumInto");

        _dependencies = BuildDependencies(_dependencyCount);
        _kindRanks = new int[_dependencyCount];
        _nameRanks = new int[_dependencyCount];
        _tempIndices = new int[_dependencyCount];
        _sortedIndices = new int[_dependencyCount];
        _nsharpResultIndices = new int[_dependencyCount];

        BuildCompactRanks(out var uniqueKindCount, out var uniqueNameCount);
        _kindCounts = new int[uniqueKindCount + 1];
        _kindOffsets = new int[uniqueKindCount + 1];
        _nameCounts = new int[uniqueNameCount + 1];
        _nameOffsets = new int[uniqueNameCount + 1];

        var expectedChecksum = CSharpTreeDependencies_DeduplicateForTree();
        var actualChecksum = NSharpTreeDependencies_DeduplicateForTree();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# CLI tree dependency checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expected = DeduplicateWithCSharp();
        for (var i = 0; i < expected.Count; i++)
        {
            if (_nsharpResultIndices[i] != expected[i].Index)
            {
                throw new InvalidOperationException(
                    $"N# CLI tree dependency mismatch for {Corpus} at ordered item {i}: " +
                    $"expected source index {expected[i].Index}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTreeDependencies_DeduplicateForTree()
    {
        var ordered = DeduplicateWithCSharp();
        return ChecksumOrderedDependencies(ordered);
    }

    [Benchmark]
    public int NSharpTreeDependencies_DeduplicateForTree() =>
        _nsharpTreeDependencyDeduplicateChecksumInto(
            _kindRanks,
            _nameRanks,
            _nameCounts,
            _nameOffsets,
            _kindCounts,
            _kindOffsets,
            _tempIndices,
            _sortedIndices,
            _nsharpResultIndices);

    private void BuildCompactRanks(out int uniqueKindCount, out int uniqueNameCount)
    {
        var kindRanks = new Dictionary<string, int>(StringComparer.Ordinal);
        var nameRanks = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var kinds = new string[_dependencies.Length];
        var names = new string[_dependencies.Length];

        uniqueKindCount = 0;
        uniqueNameCount = 0;
        for (var i = 0; i < _dependencies.Length; i++)
        {
            var dependency = _dependencies[i];
            if (!kindRanks.ContainsKey(dependency.Kind))
            {
                kindRanks.Add(dependency.Kind, 0);
                kinds[uniqueKindCount] = dependency.Kind;
                uniqueKindCount++;
            }

            if (!nameRanks.ContainsKey(dependency.Name))
            {
                nameRanks.Add(dependency.Name, 0);
                names[uniqueNameCount] = dependency.Name;
                uniqueNameCount++;
            }
        }

        Array.Sort(kinds, 0, uniqueKindCount, StringComparer.Ordinal);
        for (var i = 0; i < uniqueKindCount; i++)
        {
            kindRanks[kinds[i]] = i + 1;
        }

        Array.Sort(names, 0, uniqueNameCount, StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < uniqueNameCount; i++)
        {
            nameRanks[names[i]] = i + 1;
        }

        for (var i = 0; i < _dependencies.Length; i++)
        {
            _kindRanks[i] = kindRanks[_dependencies[i].Kind];
            _nameRanks[i] = nameRanks[_dependencies[i].Name];
        }
    }

    private List<TreeDependencyEntry> DeduplicateWithCSharp() =>
        _dependencies
            .GroupBy(
                dependency => (dependency.Kind, dependency.Name),
                dependency => dependency,
                TreeDependencyKeyComparer.Instance)
            .Select(group => group.First())
            .OrderBy(dependency => dependency.Kind, StringComparer.Ordinal)
            .ThenBy(dependency => dependency.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();

    private int ChecksumOrderedDependencies(IReadOnlyList<TreeDependencyEntry> ordered)
    {
        var checksum = ordered.Count;
        for (var i = 0; i < ordered.Count; i++)
        {
            var index = ordered[i].Index;
            checksum += (i + 1) * 97 + (index + 1) * 31 + _kindRanks[index] * 17 + _nameRanks[index] * 13;
        }

        return checksum;
    }

    private static TreeDependencyEntry[] BuildDependencies(int count)
    {
        var kinds = new[] { "nuget", "framework", "project", "dll" };
        var names = new[]
        {
            "Serilog",
            "Newtonsoft.Json",
            "System.Text.Json",
            "Microsoft.AspNetCore.App",
            "Microsoft.NETCore.App",
            "../Shared/Shared.csproj",
            "../Runtime/Runtime.csproj",
            "Lib/Analyzers.dll",
            "Lib/Generators.dll",
            "NSharpLang.Runtime",
            "NSharpLang.Compiler",
            "BenchmarkDotNet",
            "Xunit",
            "Microsoft.Extensions.Logging",
            "YamlDotNet",
            "OmniSharp.Extensions.LanguageServer"
        };

        var dependencies = new TreeDependencyEntry[count];
        for (var i = 0; i < count; i++)
        {
            var kind = kinds[(i * 7 + i / 19) % kinds.Length];
            var baseName = names[(i * 11 + i / 5) % names.Length];
            var name = i % 23 == 0
                ? baseName.ToUpperInvariant()
                : i % 29 == 0
                    ? baseName.ToLowerInvariant()
                    : baseName;

            if (i % 17 != 0)
                name = $"{name}.{i % 389}";

            dependencies[i] = new TreeDependencyEntry(i, kind, name);
        }

        return dependencies;
    }

    private sealed record TreeDependencyEntry(int Index, string Kind, string Name);

    private sealed class TreeDependencyKeyComparer : IEqualityComparer<(string Kind, string Name)>
    {
        public static readonly TreeDependencyKeyComparer Instance = new();

        public bool Equals((string Kind, string Name) x, (string Kind, string Name) y) =>
            string.Equals(x.Kind, y.Kind, StringComparison.Ordinal) &&
            string.Equals(x.Name, y.Name, StringComparison.OrdinalIgnoreCase);

        public int GetHashCode((string Kind, string Name) obj) =>
            HashCode.Combine(
                StringComparer.Ordinal.GetHashCode(obj.Kind),
                StringComparer.OrdinalIgnoreCase.GetHashCode(obj.Name));
    }

    private delegate int CliTreeDependencyDeduplicateChecksumInto(
        int[] kindRanks,
        int[] nameRanks,
        int[] nameCounts,
        int[] nameOffsets,
        int[] kindCounts,
        int[] kindOffsets,
        int[] tempIndices,
        int[] sortedIndices,
        int[] resultIndices);
}

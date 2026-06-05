using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for target-package NuGet dependency selection in <c>nlc update</c>.
/// The C# baseline mirrors the command fallback shape for a named package: filter NuGet
/// dependencies with a case-insensitive package-name comparison. The N# candidate runs after the
/// host has projected case-insensitive package-name ranks, with rank 0 reserved for non-NuGet
/// dependencies.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliUpdateDependencyFilterBenchmarks
{
    private const int LargeDependencyCount = 8192;
    private const int RepresentativeDependencyCount = 1024;

    private Func<int[], int, int[], int> _nsharpUpdateTargetNuGetDependencyChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private BenchmarkDependency[] _dependencies = Array.Empty<BenchmarkDependency>();
    private int[] _nameRanks = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int _dependencyCount;
    private int _targetNameRank;
    private string? _targetPackage;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(CliUpdateTargetMode.Existing, CliUpdateTargetMode.Missing)]
    public CliUpdateTargetMode TargetMode { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _dependencyCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDependencyCount
            : LargeDependencyCount;
        _nsharpUpdateTargetNuGetDependencyChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliUpdateTargetNuGetDependencyChecksumInto");

        _dependencies = BuildDependencies(_dependencyCount);
        _nameRanks = new int[_dependencyCount];
        _nsharpResultIndices = new int[_dependencyCount];
        BuildCompactRanks();

        _targetPackage = TargetMode == CliUpdateTargetMode.Existing
            ? "Serilog"
            : "Missing.Package";
        _targetNameRank = GetTargetRank(_targetPackage);

        var expectedChecksum = CSharpUpdateDependencies_FilterTargetNuGet();
        var actualChecksum = NSharpUpdateDependencies_FilterTargetNuGet();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# update dependency checksum mismatch for {Corpus}/{TargetMode}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpUpdateDependencies_FilterTargetNuGet()
    {
        var nugetDeps = _dependencies
            .Where(dependency =>
                dependency.Nuget != null &&
                string.Equals(dependency.Nuget, _targetPackage, StringComparison.OrdinalIgnoreCase))
            .ToList();

        return ChecksumDependencies(nugetDeps);
    }

    [Benchmark]
    public int NSharpUpdateDependencies_FilterTargetNuGet() =>
        _nsharpUpdateTargetNuGetDependencyChecksumInto(
            _nameRanks,
            _targetNameRank,
            _nsharpResultIndices);

    private void BuildCompactRanks()
    {
        var nameRanks = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var uniqueNameCount = 0;

        for (var i = 0; i < _dependencies.Length; i++)
        {
            var dependency = _dependencies[i];
            if (dependency.Nuget == null)
            {
                _nameRanks[i] = 0;
                continue;
            }

            if (!nameRanks.TryGetValue(dependency.Nuget, out var nameRank))
            {
                uniqueNameCount++;
                nameRank = uniqueNameCount;
                nameRanks.Add(dependency.Nuget, nameRank);
            }

            _nameRanks[i] = nameRank;
        }
    }

    private int GetTargetRank(string targetPackage)
    {
        for (var i = 0; i < _dependencies.Length; i++)
        {
            if (string.Equals(_dependencies[i].Nuget, targetPackage, StringComparison.OrdinalIgnoreCase))
                return _nameRanks[i];
        }

        return -1;
    }

    private int ChecksumDependencies(IReadOnlyList<BenchmarkDependency> dependencies)
    {
        var checksum = dependencies.Count;
        for (var i = 0; i < dependencies.Count; i++)
        {
            var index = dependencies[i].Index;
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + 17
                + _nameRanks[index] * 13;
        }

        return checksum;
    }

    private static BenchmarkDependency[] BuildDependencies(int count)
    {
        var packages = new[]
        {
            "Serilog",
            "Newtonsoft.Json",
            "System.Text.Json",
            "NSharpLang.Runtime",
            "Microsoft.Extensions.Logging",
            "YamlDotNet",
            "BenchmarkDotNet",
            "xunit"
        };
        var dependencies = new BenchmarkDependency[count];
        for (var i = 0; i < count; i++)
        {
            var selector = (i * 7 + i / 11) % 8;
            if (selector == 0)
            {
                dependencies[i] = new BenchmarkDependency(i, null, null, "Microsoft.AspNetCore.App", null, null);
                continue;
            }

            if (selector == 1)
            {
                dependencies[i] = new BenchmarkDependency(i, null, null, null, $"lib/Analyzer{i % 17}.dll", null);
                continue;
            }

            if (selector == 2)
            {
                dependencies[i] = new BenchmarkDependency(i, null, null, null, null, "../Shared/project.yml");
                continue;
            }

            var package = packages[(i * 13 + i / 5) % packages.Length];
            if (i % 23 == 0)
                package = package.ToUpperInvariant();
            else if (i % 29 == 0)
                package = package.ToLowerInvariant();

            dependencies[i] = new BenchmarkDependency(i, package, $"{1 + i % 5}.{i % 17}.{i % 31}", null, null, null);
        }

        return dependencies;
    }

    private sealed record BenchmarkDependency(
        int Index,
        string? Nuget,
        string? Version,
        string? Framework,
        string? Dll,
        string? Project);
}

public enum CliUpdateTargetMode
{
    Existing,
    Missing
}

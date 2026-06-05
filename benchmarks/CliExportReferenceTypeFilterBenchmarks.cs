using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for dependency reference-type selection in <c>nlc export csharp</c>.
/// The C# baseline mirrors the export command fallback shape: filter dependencies by reference
/// type and materialize the list. The N# candidate runs after the host has projected compact
/// reference-type ranks with rank 0 reserved for invalid/non-selected values.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliExportReferenceTypeFilterBenchmarks
{
    private const int LargeDependencyCount = 8192;
    private const int RepresentativeDependencyCount = 1024;

    private Func<int[], int, int[], int> _nsharpReferenceTypeFilterChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private BenchmarkDependency[] _dependencies = Array.Empty<BenchmarkDependency>();
    private int[] _typeRanks = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int _dependencyCount;
    private int _targetTypeRank;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        CliExportReferenceTypeTarget.NuGet,
        CliExportReferenceTypeTarget.Dll,
        CliExportReferenceTypeTarget.Project,
        CliExportReferenceTypeTarget.Framework)]
    public CliExportReferenceTypeTarget Target { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _dependencyCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDependencyCount
            : LargeDependencyCount;
        _targetTypeRank = (int)Target;
        _nsharpReferenceTypeFilterChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliReferenceTypeFilterChecksumInto");

        _dependencies = CliUpdateDependencyCorpus.BuildDependencies(_dependencyCount);
        _typeRanks = new int[_dependencyCount];
        _nsharpResultIndices = new int[_dependencyCount];
        BuildTypeRanks();

        var expectedChecksum = CSharpExportReferences_FilterByType();
        var actualChecksum = NSharpExportReferences_FilterByType();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# export reference-type checksum mismatch for {Corpus}/{Target}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpExportReferences_FilterByType()
    {
        var selectedReferences = _dependencies
            .Where(dependency => GetTypeRank(dependency) == _targetTypeRank)
            .ToList();

        return ChecksumDependencies(selectedReferences);
    }

    [Benchmark]
    public int NSharpExportReferences_FilterByType() =>
        _nsharpReferenceTypeFilterChecksumInto(
            _typeRanks,
            _targetTypeRank,
            _nsharpResultIndices);

    private void BuildTypeRanks()
    {
        for (var i = 0; i < _dependencies.Length; i++)
            _typeRanks[i] = GetTypeRank(_dependencies[i]);
    }

    private int ChecksumDependencies(IReadOnlyList<BenchmarkDependency> dependencies)
    {
        var checksum = dependencies.Count;
        for (var i = 0; i < dependencies.Count; i++)
        {
            var index = dependencies[i].Index;
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + _typeRanks[index] * 17;
        }

        return checksum;
    }

    private static int GetTypeRank(BenchmarkDependency dependency)
    {
        if (dependency.Nuget != null)
            return (int)CliExportReferenceTypeTarget.NuGet;
        if (dependency.Dll != null)
            return (int)CliExportReferenceTypeTarget.Dll;
        if (dependency.Project != null)
            return (int)CliExportReferenceTypeTarget.Project;
        if (dependency.Framework != null)
            return (int)CliExportReferenceTypeTarget.Framework;

        return 0;
    }
}

public enum CliExportReferenceTypeTarget
{
    NuGet = 1,
    Dll = 2,
    Project = 3,
    Framework = 4
}

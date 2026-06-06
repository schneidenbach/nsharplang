using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc tidy</c> dependency usage classification.
/// The C# baseline mirrors <c>TidyCommand.ClassifyDependency</c>: split every package id,
/// materialize the first two namespace segments, and scan imported namespaces with
/// ordinal-ignore-case prefix checks. The N# candidate receives caller-owned package/import
/// arrays and writes compact status ranks in one allocation-free pass over the same data.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliTidyDependencyClassificationBenchmarks
{
    private const int LargeDependencyCount = 4096;
    private const int LargeImportCount = 512;
    private const int RepresentativeDependencyCount = 512;
    private const int RepresentativeImportCount = 128;

    private Func<string[], string[], int[], int> _nsharpStatusRankChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpStatusRanks = Array.Empty<int>();
    private string[] _importNamespaces = Array.Empty<string>();
    private int[] _nsharpStatusRanks = Array.Empty<int>();
    private string[] _packageNames = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpStatusRankChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], string[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliTidyDependencyStatusRankChecksumInto");

        var dependencyCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDependencyCount
            : LargeDependencyCount;
        var importCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeImportCount
            : LargeImportCount;

        _packageNames = BuildPackageNames(dependencyCount);
        _importNamespaces = BuildImportNamespaces(importCount);
        _csharpStatusRanks = new int[dependencyCount];
        _nsharpStatusRanks = new int[dependencyCount];

        var csharp = CSharpTidy_ClassifyDependencies();
        var nsharp = NSharpTidy_ClassifyDependencies();
        if (csharp != nsharp)
        {
            throw new InvalidOperationException(
                $"N# tidy dependency classification checksum mismatch for {Corpus}: " +
                $"expected {csharp}, got {nsharp}.");
        }

        if (!_csharpStatusRanks.SequenceEqual(_nsharpStatusRanks))
        {
            var mismatch = FirstMismatch();
            throw new InvalidOperationException(
                $"N# tidy dependency classification mismatch for {Corpus} at {mismatch}: " +
                $"{_packageNames[mismatch]} expected {_csharpStatusRanks[mismatch]}, " +
                $"got {_nsharpStatusRanks[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTidy_ClassifyDependencies()
    {
        var checksum = _packageNames.Length;
        for (var i = 0; i < _packageNames.Length; i++)
        {
            var rank = ClassifyDependencyWithCSharp(_packageNames[i], _importNamespaces);
            _csharpStatusRanks[i] = rank;
            checksum += (i + 1) * 97 + rank * 31 + _packageNames[i].Length * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpTidy_ClassifyDependencies() =>
        _nsharpStatusRankChecksumInto(
            _packageNames,
            _importNamespaces,
            _nsharpStatusRanks);

    private static int ClassifyDependencyWithCSharp(
        string packageName,
        IReadOnlyCollection<string> importedNamespaces)
    {
        var segments = packageName.Split('.');
        if (segments.Length < 2)
            return 3;

        var prefix1 = segments[0];
        var prefix2 = string.Join(".", segments.Take(2));

        var matched = importedNamespaces.Any(ns =>
            ns.StartsWith(prefix1 + ".", StringComparison.OrdinalIgnoreCase) ||
            ns.Equals(prefix1, StringComparison.OrdinalIgnoreCase) ||
            ns.StartsWith(prefix2 + ".", StringComparison.OrdinalIgnoreCase) ||
            ns.Equals(prefix2, StringComparison.OrdinalIgnoreCase));

        return matched ? 2 : 1;
    }

    private static string[] BuildPackageNames(int count)
    {
        var packages = new string[count];
        for (var i = 0; i < count; i++)
        {
            packages[i] = (i % 17) switch
            {
                0 => $"Polly{i}",
                1 or 2 or 3 => $"Newtonsoft.Json.Extension{i % 19}",
                4 or 5 => $"Serilog.Sinks.Console{i % 23}",
                6 or 7 => $"Microsoft.Extensions.Logging{i % 29}",
                8 => $"Humanizer.Core{i % 31}",
                9 or 10 or 11 => $"Contoso.Feature{i % 37}.Client",
                12 or 13 => $"ACME.Tools.Package{i % 41}",
                _ => $"Unused.Package{i % 43}.Library"
            };
        }

        return packages;
    }

    private static string[] BuildImportNamespaces(int count)
    {
        var imports = new List<string>(count)
        {
            "System",
            "Newtonsoft.Json",
            "Newtonsoft.Json.Linq",
            "Serilog",
            "Serilog.Sinks.Console",
            "Microsoft.Extensions.Logging",
            "Humanizer",
            "Contoso.Feature0",
            "Contoso.Feature1.Client",
            "Acme.Tools"
        };

        var i = 0;
        while (imports.Count < count)
        {
            imports.Add((i % 5) switch
            {
                0 => $"Contoso.Feature{i % 37}.Models",
                1 => $"Company.Product{i % 53}.Services",
                2 => $"UnusedButSimilar.Package{i % 43}",
                3 => $"Microsoft.Extensions.Configuration{i % 11}",
                _ => $"Vendor.Library{i % 67}.Runtime"
            });
            i++;
        }

        return imports.ToArray();
    }

    private int FirstMismatch()
    {
        for (var i = 0; i < _csharpStatusRanks.Length; i++)
        {
            if (_csharpStatusRanks[i] != _nsharpStatusRanks[i])
                return i;
        }

        return _csharpStatusRanks.Length;
    }
}

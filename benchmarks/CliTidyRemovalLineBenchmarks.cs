using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc tidy --fix</c> project.yml dependency-line removal.
/// The C# baseline mirrors <c>TidyCommand.RemoveDependencies</c>: trim each line, check dependency
/// list syntax, then scan every package with case-insensitive interpolated prefix/contains
/// patterns. The N# candidate scans ASCII lines and package names directly and writes keep flags
/// through caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliTidyRemovalLineBenchmarks
{
    private const int LargeLineCount = 8192;
    private const int LargePackageCount = 256;
    private const int RepresentativeLineCount = 1024;
    private const int RepresentativePackageCount = 64;

    private int[] _csharpKeepFlags = Array.Empty<int>();
    private string[] _lines = Array.Empty<string>();
    private int[] _nsharpKeepFlags = Array.Empty<int>();
    private Func<string[], string[], int[], int> _nsharpRemovalKeepChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private string[] _packageNames = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpRemovalKeepChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], string[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliTidyRemovalLineKeepChecksumInto");

        var lineCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeLineCount
            : LargeLineCount;
        var packageCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativePackageCount
            : LargePackageCount;

        _packageNames = BuildPackageNames(packageCount);
        _lines = BuildProjectLines(lineCount, _packageNames);
        _csharpKeepFlags = new int[lineCount];
        _nsharpKeepFlags = new int[lineCount];

        var expectedChecksum = CSharpTidy_RemoveDependencyLines();
        var actualChecksum = NSharpTidy_RemoveDependencyLines();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# tidy removal-line checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpKeepFlags.SequenceEqual(_nsharpKeepFlags))
        {
            var mismatch = FirstMismatch();
            throw new InvalidOperationException(
                $"N# tidy removal-line mismatch for {Corpus} at {mismatch}: " +
                $"{_lines[mismatch]} expected {_csharpKeepFlags[mismatch]}, got {_nsharpKeepFlags[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTidy_RemoveDependencyLines()
    {
        var toRemove = new HashSet<string>(_packageNames, StringComparer.OrdinalIgnoreCase);
        var filtered = _lines.Where(line =>
        {
            var trimmed = line.TrimStart();
            if (!trimmed.StartsWith("- "))
                return true;

            foreach (var packageName in toRemove)
            {
                if (trimmed.StartsWith($"- {packageName}@", StringComparison.OrdinalIgnoreCase)
                    || trimmed.StartsWith($"- {packageName}", StringComparison.OrdinalIgnoreCase)
                    || trimmed.Contains($"nuget: {packageName}", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }
            }

            return true;
        }).ToList();

        var checksum = _lines.Length;
        var filteredIndex = 0;
        for (var i = 0; i < _lines.Length; i++)
        {
            var keep = filteredIndex < filtered.Count
                && string.Equals(filtered[filteredIndex], _lines[i], StringComparison.Ordinal);
            if (keep)
                filteredIndex++;

            var flag = keep ? 1 : 0;
            _csharpKeepFlags[i] = flag;
            checksum += (i + 1) * 97 + flag * 31 + _lines[i].Length * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpTidy_RemoveDependencyLines() =>
        _nsharpRemovalKeepChecksumInto(_lines, _packageNames, _nsharpKeepFlags);

    private static string[] BuildPackageNames(int count)
    {
        var packages = new string[count];
        for (var i = 0; i < count; i++)
        {
            packages[i] = (i % 5) switch
            {
                0 => $"Serilog.Sinks.Console{i}",
                1 => $"Newtonsoft.Json{i}",
                2 => $"Polly{i}",
                3 => $"Humanizer.Core{i}",
                _ => $"Contoso.Package{i}"
            };
        }

        return packages;
    }

    private static string[] BuildProjectLines(int count, string[] packageNames)
    {
        var lines = new string[count];
        for (var i = 0; i < count; i++)
        {
            var packageName = packageNames[(i * 17) % packageNames.Length];
            lines[i] = (i % 11) switch
            {
                0 => "dependencies:",
                1 => $"  - {packageName}@1.{i % 10}.0",
                2 => $"  - nuget: {packageName}",
                3 => $"    version: {i % 3}.0.0",
                4 => $"  - nuget: Kept.Package{i}",
                5 => $"  - framework: Microsoft.AspNetCore.App",
                6 => $"  - {packageName}",
                7 => $"  - project: ../Shared{i % 7}/Shared.csproj",
                8 => $"  - dll: ./lib/Library{i % 13}.dll",
                9 => $"  - NUGET: {packageName}",
                _ => $"name: TidyProject{i}"
            };
        }

        return lines;
    }

    private int FirstMismatch()
    {
        for (var i = 0; i < _csharpKeepFlags.Length; i++)
        {
            if (_csharpKeepFlags[i] != _nsharpKeepFlags[i])
                return i;
        }

        return _csharpKeepFlags.Length;
    }
}

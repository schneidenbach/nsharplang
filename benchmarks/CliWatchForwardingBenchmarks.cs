using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc watch</c> forwarded-argument selection. The C# baseline mirrors the
/// current command path: copy <c>args.Skip(1).ToArray()</c>, scan with a list, then materialize the
/// forwarded argument array. The N# candidate scans the original argv from index one and returns
/// source indices for host materialization.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliWatchForwardingBenchmarks
{
    private const int LargeArgumentCount = 8192;
    private const int RepresentativeArgumentCount = 1024;

    private Func<string[], int[], int> _nsharpWatchForwardedArgIndicesInto =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _args = Array.Empty<string>();
    private string[] _csharpForwarded = Array.Empty<string>();
    private string[] _nsharpForwarded = Array.Empty<string>();
    private int[] _resultIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpWatchForwardedArgIndicesInto =
            NSharpCompiledMethod.Bind<Func<string[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliWatchForwardedArgIndicesInto");

        var argumentCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeArgumentCount
            : LargeArgumentCount;
        _args = BuildWatchArguments(argumentCount);
        _resultIndices = new int[argumentCount];

        var expectedChecksum = CSharpWatchForwardedArgs_CurrentCommand();
        var actualChecksum = NSharpWatchForwardedArgs_SourceIndices();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# watch forwarded-argument checksum mismatch for {Corpus}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpForwarded.SequenceEqual(_nsharpForwarded, StringComparer.Ordinal))
        {
            var mismatch = FirstMismatch(_csharpForwarded, _nsharpForwarded);
            throw new InvalidOperationException(
                $"N# watch forwarded-argument mismatch for {Corpus} at result {mismatch}: " +
                $"expected {FormatAt(_csharpForwarded, mismatch)}, got {FormatAt(_nsharpForwarded, mismatch)}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpWatchForwardedArgs_CurrentCommand()
    {
        var tail = _args.Skip(1).ToArray();
        var forwarded = new List<string>();

        for (var i = 0; i < tail.Length; i++)
        {
            if (tail[i] is "--project" or "--debounce-ms" or "--max-runs")
            {
                i++;
                continue;
            }

            if (tail[i] is "--help" or "-h")
                continue;

            forwarded.Add(tail[i]);
        }

        _csharpForwarded = forwarded.ToArray();
        return ChecksumForwardedArgs(_csharpForwarded);
    }

    [Benchmark]
    public int NSharpWatchForwardedArgs_SourceIndices()
    {
        var resultCount = _nsharpWatchForwardedArgIndicesInto(_args, _resultIndices);
        _nsharpForwarded = new string[resultCount];
        for (var i = 0; i < resultCount; i++)
        {
            _nsharpForwarded[i] = _args[_resultIndices[i]];
        }

        return ChecksumForwardedArgs(_nsharpForwarded);
    }

    private static string[] BuildWatchArguments(int targetCount)
    {
        var args = new List<string>(targetCount) { "test" };
        var seeds = new[]
        {
            "--project", "samples/demo",
            "--filter", "AddPerson",
            "--debounce-ms", "50",
            "--json",
            "--max-runs", "2",
            "--coverage",
            "--backend", "il",
            "--help",
            "SpecificTest",
            "-h",
            "--", "literal",
            "--max-runs",
            "--project", "--filter",
            "value-after-missing-project",
            "--unknown", "unknown-value"
        };

        var i = 0;
        while (args.Count < targetCount)
        {
            args.Add(seeds[i % seeds.Length]);
            i++;
        }

        return args.ToArray();
    }

    private static int ChecksumForwardedArgs(IReadOnlyList<string> args)
    {
        var checksum = args.Count;
        for (var i = 0; i < args.Count; i++)
        {
            checksum += (i + 1) * 97 + args[i].Length * 31;
        }

        return checksum;
    }

    private static int FirstMismatch(IReadOnlyList<string> left, IReadOnlyList<string> right)
    {
        var count = Math.Min(left.Count, right.Count);
        for (var i = 0; i < count; i++)
        {
            if (!string.Equals(left[i], right[i], StringComparison.Ordinal))
                return i;
        }

        return left.Count == right.Count ? -1 : count;
    }

    private static string FormatAt(IReadOnlyList<string> args, int index) =>
        index >= 0 && index < args.Count ? $"\"{args[index]}\"" : "<missing>";
}

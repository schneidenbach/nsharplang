using System;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc build</c> option discovery. The C# baseline mirrors the current
/// command shape: multiple <c>args.Contains(...)</c> scans for boolean flags plus separate
/// <c>GetOptionValue</c> scans for value-taking options. The N# candidate scans argv once and
/// writes option value indices and flags into caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliBuildOptionSummaryBenchmarks
{
    private const int LargeArgumentCount = 8192;
    private const int RepresentativeArgumentCount = 1024;

    private Func<string[], int[], int> _nsharpBuildOptionSummaryInto =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _args = Array.Empty<string>();
    private int[] _resultIndices = Array.Empty<int>();

    private BuildOptionSummary _csharpSummary;
    private BuildOptionSummary _nsharpSummary;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpBuildOptionSummaryInto =
            NSharpCompiledMethod.Bind<Func<string[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliBuildOptionSummaryInto");

        var argumentCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeArgumentCount
            : LargeArgumentCount;
        _args = BuildBuildOptionArguments(argumentCount);
        _resultIndices = new int[9];

        var expectedChecksum = CSharpBuildOptions_CurrentCommand();
        var actualChecksum = NSharpBuildOptions_OnePassSummary();
        if (expectedChecksum != actualChecksum || !_csharpSummary.Equals(_nsharpSummary))
        {
            throw new InvalidOperationException(
                $"N# CLI build option summary mismatch for {Corpus}: " +
                $"expected {_csharpSummary}, got {_nsharpSummary}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpBuildOptions_CurrentCommand()
    {
        _csharpSummary = new BuildOptionSummary(
            Help: _args.Contains("--help") || _args.Contains("-h") || (_args.Length > 0 && _args[0] == "help"),
            Release: _args.Contains("--release"),
            Verbose: _args.Contains("--verbose"),
            Timings: _args.Contains("--timings"),
            PerfReport: _args.Contains("--perf-report"),
            Aot: _args.Contains("--aot"),
            OutputDir: GetOptionValue(_args, "--output") ?? GetOptionValue(_args, "-o"),
            Backend: GetOptionValue(_args, "--backend"),
            Project: GetOptionValue(_args, "--project"));

        return ChecksumSummary(_args.Length, _csharpSummary);
    }

    [Benchmark]
    public int NSharpBuildOptions_OnePassSummary()
    {
        var code = _nsharpBuildOptionSummaryInto(_args, _resultIndices);
        if (code != 0)
            throw new InvalidOperationException($"N# CLI build option summary returned {code}.");

        _nsharpSummary = new BuildOptionSummary(
            Help: _resultIndices[8] != 0,
            Release: _resultIndices[3] != 0,
            Verbose: _resultIndices[4] != 0,
            Timings: _resultIndices[5] != 0,
            PerfReport: _resultIndices[6] != 0,
            Aot: _resultIndices[7] != 0,
            OutputDir: GetArgAt(_resultIndices[0]),
            Backend: GetArgAt(_resultIndices[1]),
            Project: GetArgAt(_resultIndices[2]));

        return ChecksumSummary(_args.Length, _nsharpSummary);
    }

    private string? GetArgAt(int index) =>
        index >= 0 && index < _args.Length ? _args[index] : null;

    private static string? GetOptionValue(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == flag)
                return args[i + 1];
        }

        return null;
    }

    private static string[] BuildBuildOptionArguments(int targetCount)
    {
        var args = new string[targetCount];
        for (var i = 0; i < args.Length; i++)
        {
            args[i] = $"generated/File{i}.nl";
        }

        var tail = new[]
        {
            "--unknown",
            "value-after-unknown",
            "--output",
            "dist",
            "-o",
            "ignored-short-output",
            "--backend",
            "il",
            "--project",
            "samples/demo",
            "--release",
            "--verbose",
            "--timings",
            "--perf-report",
            "--aot",
            "tail-operand",
            "--other",
            "last"
        };

        var start = Math.Max(0, args.Length - tail.Length);
        for (var i = 0; i < tail.Length && start + i < args.Length; i++)
        {
            args[start + i] = tail[i];
        }

        return args;
    }

    private static int ChecksumSummary(int argCount, BuildOptionSummary summary)
    {
        var checksum = argCount + 23;
        checksum += summary.Help ? 29 : 3;
        checksum += summary.Release ? 31 : 5;
        checksum += summary.Verbose ? 37 : 7;
        checksum += summary.Timings ? 41 : 11;
        checksum += summary.PerfReport ? 43 : 13;
        checksum += summary.Aot ? 47 : 17;
        checksum += StringChecksum(summary.OutputDir, 53);
        checksum += StringChecksum(summary.Backend, 59);
        checksum += StringChecksum(summary.Project, 61);
        return checksum;
    }

    private static int StringChecksum(string? value, int multiplier)
    {
        if (value == null)
            return multiplier;

        var checksum = value.Length * multiplier;
        for (var i = 0; i < value.Length; i++)
        {
            checksum += value[i] * (i + 1);
        }

        return checksum;
    }

    private readonly record struct BuildOptionSummary(
        bool Help,
        bool Release,
        bool Verbose,
        bool Timings,
        bool PerfReport,
        bool Aot,
        string? OutputDir,
        string? Backend,
        string? Project);
}

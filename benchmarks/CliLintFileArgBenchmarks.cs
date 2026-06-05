using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for positional file-argument extraction in <c>nlc lint</c>.
/// The C# baseline mirrors the current command shape: filter non-flags with LINQ, then rescan the
/// full argument array for each candidate to remove values belonging to <c>--project</c>.
/// The N# candidate records <c>--project</c> value indices once, writes matching file-argument
/// indices through caller-owned buffers, and lets the host materialize the final file array.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliLintFileArgBenchmarks
{
    private const int LargeArgumentCount = 8192;
    private const int RepresentativeArgumentCount = 1024;

    private Func<string[], int[], int[], int> _nsharpCliLintFileArgIndicesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _args = Array.Empty<string>();
    private string[] _csharpFiles = Array.Empty<string>();
    private string[] _nsharpFiles = Array.Empty<string>();
    private int[] _projectValueIndices = Array.Empty<int>();
    private int[] _resultIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpCliLintFileArgIndicesInto =
            NSharpCompiledMethod.Bind<Func<string[], int[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliLintFileArgIndicesInto");

        var argumentCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeArgumentCount
            : LargeArgumentCount;

        _args = BuildArgs(argumentCount);
        _projectValueIndices = new int[argumentCount];
        _resultIndices = new int[argumentCount];

        var csharp = CSharpLintFileArgs_Command();
        var nsharp = NSharpLintFileArgs_Command();
        if (csharp != nsharp)
        {
            throw new InvalidOperationException(
                $"N# lint file-argument checksum mismatch for {Corpus}: expected {csharp}, got {nsharp}.");
        }

        if (!_csharpFiles.SequenceEqual(_nsharpFiles, StringComparer.Ordinal))
        {
            var mismatch = FirstMismatch(_csharpFiles, _nsharpFiles);
            throw new InvalidOperationException(
                $"N# lint file-argument mismatch for {Corpus} at result {mismatch}: " +
                $"expected {FormatAt(_csharpFiles, mismatch)}, got {FormatAt(_nsharpFiles, mismatch)}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpLintFileArgs_Command()
    {
        _csharpFiles = _args
            .Where(static arg => !arg.StartsWith("-", StringComparison.Ordinal) && arg != "help")
            .Where(arg => !IsOptionValue(_args, arg, "--project"))
            .ToArray();

        return ChecksumFiles(_csharpFiles);
    }

    [Benchmark]
    public int NSharpLintFileArgs_Command()
    {
        var resultCount = _nsharpCliLintFileArgIndicesInto(
            _args,
            _projectValueIndices,
            _resultIndices);

        if (resultCount < 0 || resultCount > _args.Length)
            throw new InvalidOperationException($"N# lint file-argument count out of range: {resultCount}.");

        _nsharpFiles = new string[resultCount];
        for (var i = 0; i < resultCount; i++)
        {
            var sourceIndex = _resultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= _args.Length)
                throw new InvalidOperationException($"N# lint file-argument index out of range: {sourceIndex}.");

            _nsharpFiles[i] = _args[sourceIndex];
        }

        return ChecksumFiles(_nsharpFiles);
    }

    private static string[] BuildArgs(int count)
    {
        var args = new List<string>(count);
        var i = 0;
        while (args.Count < count)
        {
            if (i % 47 == 0 && args.Count + 2 <= count)
            {
                args.Add("--project");
                args.Add($"projects/project-{i % 29}");
            }
            else if (i % 31 == 0)
            {
                args.Add("--json");
            }
            else if (i % 37 == 0)
            {
                args.Add("--text");
            }
            else if (i % 53 == 0)
            {
                args.Add("help");
            }
            else if (i % 19 == 0)
            {
                args.Add("-v");
            }
            else
            {
                args.Add($"src/Feature{i % 211}/File{i}.nl");
            }

            i++;
        }

        return args.ToArray();
    }

    private static bool IsOptionValue(string[] args, string value, params string[] flags)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (flags.Contains(args[i]) && args[i + 1] == value)
                return true;
        }

        return false;
    }

    private static int ChecksumFiles(string[] files)
    {
        var checksum = files.Length;
        for (var i = 0; i < files.Length; i++)
        {
            var file = files[i];
            checksum += (i + 1) * 97 + file.Length * 31;
            if (file.Length > 0)
                checksum += file[0] * 17 + file[^1] * 13;
        }

        return checksum;
    }

    private static int FirstMismatch(string[] left, string[] right)
    {
        var count = Math.Min(left.Length, right.Length);
        for (var i = 0; i < count; i++)
        {
            if (!string.Equals(left[i], right[i], StringComparison.Ordinal))
                return i;
        }

        return count;
    }

    private static string FormatAt(string[] files, int index) =>
        index >= 0 && index < files.Length ? $"\"{files[index]}\"" : "<missing>";
}

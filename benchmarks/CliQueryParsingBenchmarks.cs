using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for CLI query position parsing used by <c>nlc query --pos line:col</c>
/// and daemon query dispatch.
///
/// The C# baseline mirrors the current command parser shape: split on ':' and parse the two
/// segments with <see cref="int.TryParse(string?, out int)" />. The N# candidate scans the string
/// once, parses signed/whitespace-trimmed 32-bit integers directly, and writes line/column values
/// into caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliQueryPositionParsingBenchmarks
{
    private const int LargePositionCount = 8192;
    private const int RepresentativePositionCount = 1024;

    private Func<string[], int[], int[], int> _nsharpCliQueryPositionChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpColumns = Array.Empty<int>();
    private int[] _csharpLines = Array.Empty<int>();
    private int[] _nsharpColumns = Array.Empty<int>();
    private int[] _nsharpLines = Array.Empty<int>();
    private string[] _positions = Array.Empty<string>();
    private int _positionCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _positionCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativePositionCount
            : LargePositionCount;
        _nsharpCliQueryPositionChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], int[], int[], int>>(
                DogfoodCompilerSources.CliQueryParsing,
                "CliQueryPositionChecksumInto");

        _positions = BuildPositions(_positionCount);
        _csharpLines = new int[_positionCount];
        _csharpColumns = new int[_positionCount];
        _nsharpLines = new int[_positionCount];
        _nsharpColumns = new int[_positionCount];

        var expectedChecksum = CSharpCliQueryPositions_QueryBatch();
        var actualChecksum = NSharpCliQueryPositions_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# CLI query position checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpLines.SequenceEqual(_nsharpLines) || !_csharpColumns.SequenceEqual(_nsharpColumns))
        {
            var mismatch = FirstMismatch();
            throw new InvalidOperationException(
                $"N# CLI query position mismatch for {Corpus} at item {mismatch}: " +
                $"position {FormatPosition(_positions[mismatch])}, " +
                $"expected {_csharpLines[mismatch]}:{_csharpColumns[mismatch]}, " +
                $"got {_nsharpLines[mismatch]}:{_nsharpColumns[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCliQueryPositions_QueryBatch()
    {
        var checksum = _positions.Length;
        for (var i = 0; i < _positions.Length; i++)
        {
            var parsed = TryParsePositionWithSplit(_positions[i], out var line, out var column);
            _csharpLines[i] = line;
            _csharpColumns[i] = column;
            checksum += (parsed ? 1 : 0) * 97 + line * 31 + column * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpCliQueryPositions_QueryBatch() =>
        _nsharpCliQueryPositionChecksumInto(_positions, _nsharpLines, _nsharpColumns);

    private static bool TryParsePositionWithSplit(string position, out int line, out int column)
    {
        line = 0;
        column = 0;
        var parts = position.Split(':');
        if (parts.Length != 2)
            return false;

        return int.TryParse(parts[0], out line) && int.TryParse(parts[1], out column);
    }

    private static string[] BuildPositions(int count)
    {
        var positions = new string[count];
        var seeds = new[]
        {
            "1:1",
            "42:17",
            " 42 : 17 ",
            "+64:+10",
            "-1:5",
            "2147483647:2147483647",
            "-2147483648:-2147483648",
            "0:0",
            "99999:12345",
            "12:",
            ":34",
            "12:abc",
            "abc:12",
            "12:34:56",
            "2147483648:1",
            "1:-2147483649",
            "1_000:2",
            "7 :\t8"
        };

        for (var i = 0; i < count; i++)
        {
            if (i % 11 == 0)
            {
                positions[i] = $"{i + 1}:{(i * 17) % 100000 + 1}";
                continue;
            }

            if (i % 29 == 0)
            {
                positions[i] = $" {(i % 4096) + 1} :\t{(i * 31) % 2048 + 1} ";
                continue;
            }

            positions[i] = seeds[i % seeds.Length];
        }

        return positions;
    }

    private int FirstMismatch()
    {
        for (var i = 0; i < _csharpLines.Length; i++)
        {
            if (_csharpLines[i] != _nsharpLines[i] || _csharpColumns[i] != _nsharpColumns[i])
                return i;
        }

        return _csharpLines.Length;
    }

    private static string FormatPosition(string position) => $"\"{position}\"";
}

/// <summary>
/// Dogfood benchmark for shared CLI positional argument filtering used by commands that accept
/// file/project operands alongside value-taking options.
///
/// The C# baseline mirrors <c>Program.GetPositionalArgs</c>: allocate a HashSet for value-taking
/// options, append positional strings to a List, then materialize a string array. The N# candidate
/// scans the argument array once, writes positional source indices into caller-owned storage, and
/// lets the host materialize the final string array.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliPositionalArgumentFilteringBenchmarks
{
    private const int LargeArgumentCount = 8192;
    private const int RepresentativeArgumentCount = 1024;

    private static readonly string[] OptionsWithValues =
    [
        "--project",
        "--output",
        "-o",
        "--backend"
    ];

    private Func<string[], string[], int[], int> _nsharpCliPositionalArgIndicesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _args = Array.Empty<string>();
    private string[] _csharpResult = Array.Empty<string>();
    private int[] _nsharpIndices = Array.Empty<int>();
    private string[] _nsharpResult = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var argumentCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeArgumentCount
            : LargeArgumentCount;
        _nsharpCliPositionalArgIndicesInto =
            NSharpCompiledMethod.Bind<Func<string[], string[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliPositionalArgIndicesInto");

        _args = BuildArguments(argumentCount);
        _nsharpIndices = new int[argumentCount];

        var expectedChecksum = CSharpCliPositionalArgs_SharedHelper();
        var actualChecksum = NSharpCliPositionalArgs_SharedHelper();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# CLI positional argument checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpResult.SequenceEqual(_nsharpResult))
        {
            var mismatch = FirstMismatch();
            throw new InvalidOperationException(
                $"N# CLI positional argument mismatch for {Corpus} at result {mismatch}: " +
                $"expected {FormatArgAt(_csharpResult, mismatch)}, got {FormatArgAt(_nsharpResult, mismatch)}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCliPositionalArgs_SharedHelper()
    {
        var positional = new List<string>();
        var options = new HashSet<string>(OptionsWithValues, StringComparer.Ordinal);

        for (var i = 0; i < _args.Length; i++)
        {
            if (options.Contains(_args[i]))
            {
                i++;
                continue;
            }

            if (_args[i] is "--check" or "--verify-no-changes" or "--diff" or "--stdin" or "--verbose")
                continue;

            if (!_args[i].StartsWith("-", StringComparison.Ordinal))
                positional.Add(_args[i]);
        }

        _csharpResult = positional.ToArray();
        return ChecksumArgs(_csharpResult);
    }

    [Benchmark]
    public int NSharpCliPositionalArgs_SharedHelper()
    {
        var count = _nsharpCliPositionalArgIndicesInto(_args, OptionsWithValues, _nsharpIndices);
        if (count < 0 || count > _args.Length || count > _nsharpIndices.Length)
            throw new InvalidOperationException($"N# CLI positional argument count out of range: {count}.");

        _nsharpResult = new string[count];
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = _nsharpIndices[i];
            if (sourceIndex < 0 || sourceIndex >= _args.Length)
                throw new InvalidOperationException($"N# CLI positional argument index out of range: {sourceIndex}.");

            _nsharpResult[i] = _args[sourceIndex];
        }

        return ChecksumArgs(_nsharpResult);
    }

    private static string[] BuildArguments(int count)
    {
        var args = new string[count];
        var seeds = new[]
        {
            "src/App.nl",
            "--project",
            "samples/demo",
            "--check",
            "--unknown",
            "README.md",
            "--output",
            "dist",
            "-o",
            "bin/out",
            "--stdin",
            "",
            "examples/hello.nl",
            "--backend",
            "il",
            "--verify-no-changes",
            "tests/fixture.nl",
            "--diff",
            "--verbose",
            "relative/path.nl",
            "-x",
            "value-after-unknown",
            "help",
            "--"
        };

        for (var i = 0; i < count; i++)
        {
            if (i % 37 == 0)
            {
                args[i] = $"generated/File{i}.nl";
                continue;
            }

            if (i % 53 == 0)
            {
                args[i] = $"operand-{i}";
                continue;
            }

            args[i] = seeds[i % seeds.Length];
        }

        return args;
    }

    private int FirstMismatch()
    {
        var count = Math.Min(_csharpResult.Length, _nsharpResult.Length);
        for (var i = 0; i < count; i++)
        {
            if (_csharpResult[i] != _nsharpResult[i])
                return i;
        }

        return count;
    }

    private static int ChecksumArgs(string[] args)
    {
        var checksum = args.Length;
        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            checksum += (i + 1) * 97 + arg.Length * 31;
            if (arg.Length > 0)
                checksum += arg[0] * 17 + arg[^1] * 13;
        }

        return checksum;
    }

    private static string FormatArgAt(string[] args, int index) =>
        index >= 0 && index < args.Length ? $"\"{args[index]}\"" : "<missing>";
}

/// <summary>
/// Dogfood benchmark for CLI commands that only need the first positional operand. The C#
/// baseline mirrors the previous shared helper shape: build every positional string, materialize
/// the array, then read index zero. The N# candidate returns the first positional source index and
/// lets the host read only that string.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliFirstPositionalArgumentBenchmarks
{
    private const int LargeArgumentCount = 8192;
    private const int RepresentativeArgumentCount = 1024;

    private static readonly string[] OptionsWithValues =
    [
        "--project",
        "--output",
        "-o",
        "--backend",
        "--template",
        "--type",
        "--file"
    ];

    private Func<string[], string[], int> _nsharpCliFirstPositionalArgIndex =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _args = Array.Empty<string>();
    private string? _csharpFirst;
    private string? _nsharpFirst;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var argumentCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeArgumentCount
            : LargeArgumentCount;
        _nsharpCliFirstPositionalArgIndex =
            NSharpCompiledMethod.Bind<Func<string[], string[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliFirstPositionalArgIndex");

        _args = BuildFirstPositionalArguments(argumentCount);

        var expectedChecksum = CSharpCliFirstPositionalArg_CurrentSharedHelper();
        var actualChecksum = NSharpCliFirstPositionalArg_FirstIndex();
        if (expectedChecksum != actualChecksum || _csharpFirst != _nsharpFirst)
        {
            throw new InvalidOperationException(
                $"N# CLI first positional argument mismatch for {Corpus}: " +
                $"expected {FormatArg(_csharpFirst)}, got {FormatArg(_nsharpFirst)}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCliFirstPositionalArg_CurrentSharedHelper()
    {
        var positional = new List<string>();
        var options = new HashSet<string>(OptionsWithValues, StringComparer.Ordinal);

        for (var i = 0; i < _args.Length; i++)
        {
            if (options.Contains(_args[i]))
            {
                i++;
                continue;
            }

            if (_args[i] is "--check" or "--verify-no-changes" or "--diff" or "--stdin" or "--verbose")
                continue;

            if (!_args[i].StartsWith("-", StringComparison.Ordinal))
                positional.Add(_args[i]);
        }

        var result = positional.ToArray();
        _csharpFirst = result.Length == 0 ? null : result[0];
        return ChecksumFirst(_csharpFirst);
    }

    [Benchmark]
    public int NSharpCliFirstPositionalArg_FirstIndex()
    {
        var index = _nsharpCliFirstPositionalArgIndex(_args, OptionsWithValues);
        if (index < -1 || index >= _args.Length)
            throw new InvalidOperationException($"N# CLI first positional argument index out of range: {index}.");

        _nsharpFirst = index < 0 ? null : _args[index];
        return ChecksumFirst(_nsharpFirst);
    }

    private static string[] BuildFirstPositionalArguments(int count)
    {
        var args = new string[count];
        var prefix = new[]
        {
            "--project",
            "samples/demo",
            "--check",
            "--unknown",
            "--output",
            "dist",
            "--verbose",
            "--backend",
            "il",
            "--stdin",
            "target/project"
        };

        for (var i = 0; i < count; i++)
        {
            if (i < prefix.Length)
            {
                args[i] = prefix[i];
                continue;
            }

            args[i] = i % 3 == 0
                ? $"generated/File{i}.nl"
                : i % 3 == 1
                    ? "--verbose"
                    : $"operand-{i}";
        }

        return args;
    }

    private static int ChecksumFirst(string? first)
    {
        var checksum = first == null ? 0 : 1;
        if (first == null)
            return checksum;

        checksum += first.Length * 31;
        if (first.Length > 0)
            checksum += first[0] * 17 + first[^1] * 13;

        return checksum;
    }

    private static string FormatArg(string? arg) => arg == null ? "<none>" : $"\"{arg}\"";
}

/// <summary>
/// Dogfood benchmark for <c>nlc build</c> operand normalization. The C# baseline mirrors the
/// current command parser: remove value-less build flags with LINQ, then run four
/// option-with-value stripping passes that allocate intermediate arrays. The N# candidate returns
/// only the first operand needed by <c>BuildCommand</c>, with a source-first fast path and an exact
/// linked-list fallback for leading options.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliBuildArgumentNormalizationBenchmarks
{
    private const int LargeArgumentCount = 8192;
    private const int RepresentativeArgumentCount = 1024;

    private Func<string[], int[], int[], int[], int[], int[], int> _nsharpCliBuildFirstOperandIndexInto =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _args = Array.Empty<string>();
    private int _csharpCount;
    private string? _csharpFirstOperand;
    private string[] _csharpResult = Array.Empty<string>();
    private int[] _nsharpKindIds = Array.Empty<int>();
    private int[] _nsharpNextIndices = Array.Empty<int>();
    private int[] _nsharpNextOptionIndices = Array.Empty<int>();
    private int[] _nsharpPreviousIndices = Array.Empty<int>();
    private int _nsharpCount;
    private string? _nsharpFirstOperand;
    private int[] _nsharpResultIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var argumentCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeArgumentCount
            : LargeArgumentCount;
        _nsharpCliBuildFirstOperandIndexInto =
            NSharpCompiledMethod.Bind<Func<string[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliBuildFirstOperandIndexInto");

        _args = BuildBuildArguments(argumentCount);
        _nsharpKindIds = new int[argumentCount];
        _nsharpNextIndices = new int[argumentCount];
        _nsharpNextOptionIndices = new int[argumentCount];
        _nsharpPreviousIndices = new int[argumentCount];
        _nsharpResultIndices = new int[argumentCount];

        var expectedChecksum = CSharpBuildArgs_NormalizeOperands();
        var actualChecksum = NSharpBuildArgs_FindFirstOperand();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# CLI build argument checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (_csharpCount != _nsharpCount || _csharpFirstOperand != _nsharpFirstOperand)
        {
            throw new InvalidOperationException(
                $"N# CLI build argument first-operand mismatch for {Corpus}: " +
                $"expected ({_csharpCount}, {FormatArg(_csharpFirstOperand)}), " +
                $"got ({_nsharpCount}, {FormatArg(_nsharpFirstOperand)}).");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpBuildArgs_NormalizeOperands()
    {
        var args = _args
            .Where(a => a is not "--release" and not "--verbose" and not "--timings" and not "--perf-report" and not "--aot")
            .ToArray();
        args = StripOptionWithValue(args, "--output");
        args = StripOptionWithValue(args, "-o");
        args = StripOptionWithValue(args, "--backend");
        args = StripOptionWithValue(args, "--project");
        _csharpResult = args;
        _csharpCount = args.Length > 0 ? 1 : 0;
        _csharpFirstOperand = args.Length > 0 ? args[0] : null;
        return ChecksumBuildOperandSummary(_csharpCount, _csharpFirstOperand);
    }

    [Benchmark]
    public int NSharpBuildArgs_FindFirstOperand()
    {
        var sourceIndex = _nsharpCliBuildFirstOperandIndexInto(
            _args,
            _nsharpKindIds,
            _nsharpNextIndices,
            _nsharpPreviousIndices,
            _nsharpNextOptionIndices,
            _nsharpResultIndices);
        if (sourceIndex < -1 || sourceIndex >= _args.Length)
            throw new InvalidOperationException($"N# CLI build argument source index out of range: {sourceIndex}.");

        _nsharpCount = sourceIndex >= 0 ? 1 : 0;
        _nsharpFirstOperand = null;
        if (sourceIndex >= 0)
        {
            _nsharpFirstOperand = _args[sourceIndex];
        }

        return ChecksumBuildOperandSummary(_nsharpCount, _nsharpFirstOperand);
    }

    private static string[] StripOptionWithValue(string[] args, string flag)
    {
        var result = new List<string>();
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == flag && i + 1 < args.Length)
            {
                i++;
                continue;
            }

            result.Add(args[i]);
        }

        return result.ToArray();
    }

    private static string[] BuildBuildArguments(int count)
    {
        var args = new string[count];
        var seeds = new[]
        {
            "--release",
            "--verbose",
            "--timings",
            "--perf-report",
            "--aot",
            "--output",
            "dist",
            "-o",
            "bin/out",
            "--backend",
            "il",
            "--project",
            "samples/demo",
            "Program.nl",
            "Extra.nl",
            "--unknown",
            "value-after-unknown",
            "--output",
            "--backend",
            "nested-edge.nl"
        };

        for (var i = 0; i < count; i++)
        {
            if (i % 41 == 0)
            {
                args[i] = $"generated/File{i}.nl";
                continue;
            }

            if (i % 67 == 0)
            {
                args[i] = $"operand-{i}";
                continue;
            }

            args[i] = seeds[i % seeds.Length];
        }

        return args;
    }

    private static int ChecksumBuildOperandSummary(int count, string? firstOperand)
    {
        var checksum = count * 397;
        if (firstOperand == null)
            return checksum;

        checksum += firstOperand.Length * 31;
        for (var i = 0; i < firstOperand.Length; i++)
        {
            checksum += firstOperand[i] * (i + 1);
        }

        return checksum;
    }

    private static string FormatArg(string? arg) => arg == null ? "<missing>" : $"\"{arg}\"";
}

/// <summary>
/// Dogfood benchmark for <c>nlc export csharp</c> input operand discovery. The C# baseline
/// mirrors the current command parser: run three option-with-value stripping passes for
/// <c>--output</c>, <c>-o</c>, and <c>--project</c>, then scan for the first positional operand.
/// The N# candidate returns the first source operand index directly, with a source-first fast path
/// and an exact linked-list fallback for option-leading edge cases.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliExportCSharpArgumentNormalizationBenchmarks
{
    private const int LargeArgumentCount = 8192;
    private const int RepresentativeArgumentCount = 1024;

    private Func<string[], int[], int[], int[], int[], int[], int> _nsharpCliExportFirstOperandIndexInto =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _args = Array.Empty<string>();
    private string? _csharpFirstOperand;
    private int[] _nsharpKindIds = Array.Empty<int>();
    private int[] _nsharpNextIndices = Array.Empty<int>();
    private int[] _nsharpNextOptionIndices = Array.Empty<int>();
    private int[] _nsharpPreviousIndices = Array.Empty<int>();
    private string? _nsharpFirstOperand;
    private int[] _nsharpResultIndices = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var argumentCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeArgumentCount
            : LargeArgumentCount;
        _nsharpCliExportFirstOperandIndexInto =
            NSharpCompiledMethod.Bind<Func<string[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliExportCSharpFirstOperandIndexInto");

        _args = BuildExportArguments(argumentCount);
        _nsharpKindIds = new int[argumentCount];
        _nsharpNextIndices = new int[argumentCount];
        _nsharpNextOptionIndices = new int[argumentCount];
        _nsharpPreviousIndices = new int[argumentCount];
        _nsharpResultIndices = new int[argumentCount];

        var expectedChecksum = CSharpExportCSharpArgs_FindInputOperand();
        var actualChecksum = NSharpExportCSharpArgs_FindInputOperand();
        if (expectedChecksum != actualChecksum || _csharpFirstOperand != _nsharpFirstOperand)
        {
            throw new InvalidOperationException(
                $"N# CLI export csharp argument mismatch for {Corpus}: " +
                $"expected {FormatArg(_csharpFirstOperand)}, got {FormatArg(_nsharpFirstOperand)}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpExportCSharpArgs_FindInputOperand()
    {
        var args = StripOptionWithValue(_args, "--output");
        args = StripOptionWithValue(args, "-o");
        args = StripOptionWithValue(args, "--project");
        _csharpFirstOperand = GetFirstPositionalArg(args);
        return ChecksumFirst(_csharpFirstOperand);
    }

    [Benchmark]
    public int NSharpExportCSharpArgs_FindInputOperand()
    {
        var sourceIndex = _nsharpCliExportFirstOperandIndexInto(
            _args,
            _nsharpKindIds,
            _nsharpNextIndices,
            _nsharpPreviousIndices,
            _nsharpNextOptionIndices,
            _nsharpResultIndices);
        if (sourceIndex < -1 || sourceIndex >= _args.Length)
            throw new InvalidOperationException($"N# CLI export csharp argument source index out of range: {sourceIndex}.");

        _nsharpFirstOperand = sourceIndex >= 0 ? _args[sourceIndex] : null;
        return ChecksumFirst(_nsharpFirstOperand);
    }

    private static string[] StripOptionWithValue(string[] args, string option)
    {
        var result = new List<string>(args.Length);
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == option && i + 1 < args.Length)
            {
                i++;
                continue;
            }

            result.Add(args[i]);
        }

        return result.ToArray();
    }

    private static string? GetFirstPositionalArg(string[] args)
    {
        for (var i = 0; i < args.Length; i++)
        {
            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                return args[i];
        }

        return null;
    }

    private static string[] BuildExportArguments(int count)
    {
        var args = new string[count];
        var seeds = new[]
        {
            "Program.nl",
            "--output",
            "dist/Program.cs",
            "-o",
            "bin/out",
            "--project",
            "samples/demo",
            "--unknown",
            "value-after-unknown",
            "src/Feature.nl",
            "--output",
            "--project",
            "edge-after-output.nl",
            "-o",
            "--output",
            "edge-hidden-by-short-output.nl"
        };

        for (var i = 0; i < count; i++)
        {
            if (i == 0)
            {
                args[i] = "Program.nl";
                continue;
            }

            if (i % 47 == 0)
            {
                args[i] = $"generated/File{i}.nl";
                continue;
            }

            if (i % 71 == 0)
            {
                args[i] = $"operand-{i}";
                continue;
            }

            args[i] = seeds[i % seeds.Length];
        }

        return args;
    }

    private static int ChecksumFirst(string? first)
    {
        var checksum = first == null ? 0 : 1;
        if (first == null)
            return checksum;

        checksum += first.Length * 31;
        for (var i = 0; i < first.Length; i++)
        {
            checksum += first[i] * (i + 1);
        }

        return checksum;
    }

    private static string FormatArg(string? arg) => arg == null ? "<missing>" : $"\"{arg}\"";
}

/// <summary>
/// Dogfood benchmark for duplicate request-id validation in <c>nlc query batch</c>.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliQueryBatchDuplicateIdBenchmarks
{
    private const int LargeRequestCount = 8192;
    private const int RepresentativeRequestCount = 1024;

    private Func<int[], int, int[], int[], int[], int> _nsharpDuplicateIdChecksumInto =
        (_, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _countsByRank = Array.Empty<int>();
    private string[] _ids = Array.Empty<string>();
    private int[] _idLengthsByRank = Array.Empty<int>();
    private int[] _idRanks = Array.Empty<int>();
    private Dictionary<string, int> _ranksById = new(StringComparer.Ordinal);
    private int[] _csharpResultRanks = Array.Empty<int>();
    private int[] _nsharpResultRanks = Array.Empty<int>();
    private int _requestCount;
    private int _uniqueIdCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _requestCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeRequestCount
            : LargeRequestCount;
        _nsharpDuplicateIdChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int[], int[], int>>(
                DogfoodCompilerSources.CliQueryParsing,
                "CliBatchDuplicateIdRankChecksumInto");

        _ids = BuildRequestIds(_requestCount);
        _idRanks = new int[_requestCount];
        _countsByRank = new int[_requestCount + 1];
        _csharpResultRanks = new int[_requestCount];
        _nsharpResultRanks = new int[_requestCount];

        BuildRanks();

        var expectedChecksum = CSharpBatchDuplicateIds_QueryBatch();
        var actualChecksum = NSharpBatchDuplicateIds_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# CLI batch duplicate-id checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expectedCount = CountFilledResultRanks(_csharpResultRanks);
        var actualCount = CountFilledResultRanks(_nsharpResultRanks);
        if (expectedCount != actualCount)
        {
            throw new InvalidOperationException(
                $"N# CLI batch duplicate-id count mismatch for {Corpus}: expected {expectedCount}, got {actualCount}.");
        }

        for (var i = 0; i < expectedCount; i++)
        {
            if (_csharpResultRanks[i] != _nsharpResultRanks[i])
            {
                throw new InvalidOperationException(
                    $"N# CLI batch duplicate-id mismatch for {Corpus} at result {i}: " +
                    $"expected rank {_csharpResultRanks[i]}, got {_nsharpResultRanks[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpBatchDuplicateIds_QueryBatch()
    {
        Array.Clear(_csharpResultRanks);

        var duplicateRanks = _ids
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .GroupBy(id => id, StringComparer.Ordinal)
            .Where(group => group.Count() > 1)
            .Select(group => _ranksById[group.Key])
            .OrderBy(rank => rank)
            .ToArray();

        var checksum = duplicateRanks.Length;
        for (var i = 0; i < duplicateRanks.Length; i++)
        {
            var rank = duplicateRanks[i];
            _csharpResultRanks[i] = rank;
            checksum += rank * 31 + _idLengthsByRank[rank] * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpBatchDuplicateIds_QueryBatch() =>
        _nsharpDuplicateIdChecksumInto(
            _idRanks,
            _uniqueIdCount,
            _countsByRank,
            _nsharpResultRanks,
            _idLengthsByRank);

    private void BuildRanks()
    {
        var uniqueIds = _ids
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .OrderBy(id => id, StringComparer.Ordinal)
            .ToArray();

        _uniqueIdCount = uniqueIds.Length;
        _idLengthsByRank = new int[_uniqueIdCount + 1];
        _ranksById = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < uniqueIds.Length; i++)
        {
            var rank = i + 1;
            _ranksById.Add(uniqueIds[i], rank);
            _idLengthsByRank[rank] = uniqueIds[i].Length;
        }

        for (var i = 0; i < _ids.Length; i++)
        {
            _idRanks[i] = string.IsNullOrWhiteSpace(_ids[i])
                ? 0
                : _ranksById[_ids[i]];
        }
    }

    private static string[] BuildRequestIds(int count)
    {
        var ids = new string[count];
        var uniqueCount = count / 4;
        for (var i = 0; i < count; i++)
        {
            if (i % 17 == 0)
            {
                ids[i] = string.Empty;
                continue;
            }

            if (i % 23 == 0)
            {
                ids[i] = " \t";
                continue;
            }

            var key = i % uniqueCount;
            ids[i] = (key % 7) switch
            {
                0 => $"inspect-{key % 97:00}",
                1 => $"diagnostics/{key % 89}",
                2 => $"Type:{key % 83}",
                3 => $"definition {key % 79}",
                4 => $"référence-{key % 73}",
                5 => $"zeta-{key % 67}",
                _ => $"alpha-{key % 61}"
            };
        }

        return ids;
    }

    private static int CountFilledResultRanks(int[] ranks)
    {
        var count = 0;
        while (count < ranks.Length && ranks[count] > 0)
        {
            count++;
        }

        return count;
    }
}

/// <summary>
/// Dogfood benchmark for batch query envelope result counting.
/// The C# baseline mirrors <c>BatchQueryRunner.Execute</c>: count successful item objects with
/// <c>items.Count(item =&gt; item.Ok)</c>, then derive the failure count. The N# candidate runs after
/// the host has projected successful-item flags into a compact caller-owned buffer.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliQueryBatchResultCountBenchmarks
{
    private const int LargeRequestCount = 8192;
    private const int RepresentativeRequestCount = 1024;

    private Func<ulong[], int, int> _nsharpResultCountChecksum =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private List<BenchmarkBatchQueryItem> _items = new();
    private ulong[] _okWords = Array.Empty<ulong>();
    private ulong[] _projectedOkWords = Array.Empty<ulong>();
    private int _requestCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        CliBatchResultPattern.Mixed,
        CliBatchResultPattern.AllSuccess,
        CliBatchResultPattern.AllFailure)]
    public CliBatchResultPattern Pattern { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _requestCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeRequestCount
            : LargeRequestCount;
        _nsharpResultCountChecksum =
            NSharpCompiledMethod.Bind<Func<ulong[], int, int>>(
                DogfoodCompilerSources.CliQueryParsing,
                "CliBatchResultPackedCountChecksum");

        _items = BuildItems(_requestCount, Pattern);
        _okWords = new ulong[(_requestCount + 63) >> 6];
        _projectedOkWords = new ulong[_okWords.Length];
        for (var i = 0; i < _items.Count; i++)
        {
            if (_items[i].Ok)
                _okWords[i >> 6] |= 1UL << (i & 63);
        }

        var expectedChecksum = CSharpBatchResultCounts_QueryBatch();
        var actualChecksum = NSharpBatchResultCounts_QueryBatch();
        var projectedChecksum = NSharpProjectedBatchResultCounts_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# CLI batch result-count checksum mismatch for {Corpus}/{Pattern}: " +
                $"expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (expectedChecksum != projectedChecksum)
        {
            throw new InvalidOperationException(
                $"N# projected CLI batch result-count checksum mismatch for {Corpus}/{Pattern}: " +
                $"expected {expectedChecksum}, got {projectedChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpBatchResultCounts_QueryBatch()
    {
        var successCount = _items.Count(item => item.Ok);
        var failureCount = _items.Count - successCount;
        return _items.Count * 31 + successCount * 17 + failureCount * 13;
    }

    [Benchmark]
    public int NSharpBatchResultCounts_QueryBatch() =>
        _nsharpResultCountChecksum(_okWords, _requestCount);

    [Benchmark]
    public int NSharpProjectedBatchResultCounts_QueryBatch()
    {
        Array.Clear(_projectedOkWords, 0, _projectedOkWords.Length);
        for (var i = 0; i < _items.Count; i++)
        {
            if (_items[i].Ok)
                _projectedOkWords[i >> 6] |= 1UL << (i & 63);
        }

        return _nsharpResultCountChecksum(_projectedOkWords, _items.Count);
    }

    private static List<BenchmarkBatchQueryItem> BuildItems(int count, CliBatchResultPattern pattern)
    {
        var items = new List<BenchmarkBatchQueryItem>(count);
        for (var i = 0; i < count; i++)
        {
            var ok = pattern switch
            {
                CliBatchResultPattern.AllSuccess => true,
                CliBatchResultPattern.AllFailure => false,
                _ => (i * 17 + i / 7) % 11 is not 0 and not 5
            };
            items.Add(new BenchmarkBatchQueryItem(ok));
        }

        return items;
    }

    private sealed record BenchmarkBatchQueryItem(bool Ok);
}

public enum CliBatchResultPattern
{
    Mixed,
    AllSuccess,
    AllFailure
}

using System;
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

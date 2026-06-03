using System;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for the identifier span extraction used by query, hover, definition, and
/// reference flows.
///
/// The current C# code-intelligence helper splits the whole file on every position query. The N#
/// candidate builds line ranges once into caller-owned buffers, then scans all queried positions
/// without allocating line strings.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceIdentifierSpanBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int[], int[], int[], int[], int> _nsharpIdentifierSpanChecksumInto =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpSpanLengths = Array.Empty<int>();
    private int[] _csharpSpanStarts = Array.Empty<int>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int[] _nsharpSpanLengths = Array.Empty<int>();
    private int[] _nsharpSpanStarts = Array.Empty<int>();
    private int[] _queryColumns = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int _queryCount;
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus);
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpIdentifierSpanChecksumInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceIdentifierSpanChecksumInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpSpanStarts = new int[_queryCount];
        _csharpSpanLengths = new int[_queryCount];
        _nsharpSpanStarts = new int[_queryCount];
        _nsharpSpanLengths = new int[_queryCount];

        BuildQueries();

        var expectedChecksum = CSharpCodeIntelligenceIdentifierSpans_QueryBatch();
        var actualChecksum = NSharpCodeIntelligenceIdentifierSpans_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# identifier span checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpSpanStarts.SequenceEqual(_nsharpSpanStarts)
            || !_csharpSpanLengths.SequenceEqual(_nsharpSpanLengths))
        {
            var mismatch = FirstMismatch(_csharpSpanStarts, _csharpSpanLengths, _nsharpSpanStarts, _nsharpSpanLengths);
            throw new InvalidOperationException(
                $"N# identifier span mismatch for {Corpus} at query {mismatch}: " +
                $"line {_queryLines[mismatch]}, column {_queryColumns[mismatch]}, " +
                $"expected {_csharpSpanStarts[mismatch]}/{_csharpSpanLengths[mismatch]}, " +
                $"got {_nsharpSpanStarts[mismatch]}/{_nsharpSpanLengths[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceIdentifierSpans_QueryBatch()
    {
        var checksum = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var span = ExtractIdentifierSpanAtPosition(_source, _queryLines[i], _queryColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            _csharpSpanStarts[i] = start;
            _csharpSpanLengths[i] = length;
            checksum += start * 31 + length * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceIdentifierSpans_QueryBatch() =>
        _nsharpIdentifierSpanChecksumInto(
            _source,
            _lineStarts,
            _lineLengths,
            _queryLines,
            _queryColumns,
            _nsharpSpanStarts,
            _nsharpSpanLengths);

    private void BuildQueries()
    {
        _queryLines = new int[_queryCount];
        _queryColumns = new int[_queryCount];

        var lines = _source.Split('\n');
        for (var i = 0; i < _queryCount; i++)
        {
            if (i % 37 == 0)
            {
                _queryLines[i] = i % 2 == 0 ? 0 : lines.Length + 1;
                _queryColumns[i] = i % 11;
                continue;
            }

            var lineIndex = i * 17 % lines.Length;
            var lineText = lines[lineIndex];
            var identifier = FindFirstIdentifierSpan(lineText);
            _queryLines[i] = lineIndex + 1;

            if (lineText.Length == 0)
            {
                _queryColumns[i] = 1;
                continue;
            }

            _queryColumns[i] = i % 8 switch
            {
                0 => i * 31 % lineText.Length + 1,
                1 => identifier.StartColumn,
                2 => Math.Max(1, identifier.StartColumn - 1),
                3 => Math.Min(lineText.Length, identifier.StartColumn + identifier.Length),
                4 => Math.Min(lineText.Length, identifier.StartColumn + identifier.Length + 1),
                5 => lineText.Length + 8,
                6 => 0,
                _ => Math.Max(1, lineText.IndexOf('.') + 1)
            };
        }
    }

    private static (int StartColumn, int Length) FindFirstIdentifierSpan(string lineText)
    {
        for (var i = 0; i < lineText.Length; i++)
        {
            if (!IsIdentifierChar(lineText[i]))
            {
                continue;
            }

            var start = i;
            while (i + 1 < lineText.Length && IsIdentifierChar(lineText[i + 1]))
            {
                i++;
            }

            return (start + 1, i - start + 1);
        }

        return (1, 1);
    }

    private static (int StartColumn, int Length)? ExtractIdentifierSpanAtPosition(string source, int line, int col)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
            {
                return null;
            }

            var lineText = lines[line - 1];
            if (lineText.Length == 0)
            {
                return null;
            }

            var index = FindNearestIdentifierIndex(lineText, Math.Clamp(col - 1, 0, lineText.Length - 1));
            if (index < 0)
            {
                return null;
            }

            var start = index;
            while (start > 0 && IsIdentifierChar(lineText[start - 1]))
            {
                start--;
            }

            var end = index;
            while (end + 1 < lineText.Length && IsIdentifierChar(lineText[end + 1]))
            {
                end++;
            }

            return (start + 1, end - start + 1);
        }
        catch
        {
            return null;
        }
    }

    private static int FindNearestIdentifierIndex(string lineText, int index)
    {
        if (lineText.Length == 0)
        {
            return -1;
        }

        if (index >= 0 && index < lineText.Length && IsIdentifierChar(lineText[index]))
        {
            return index;
        }

        const int MaxDistance = 3;
        for (var distance = 1; distance <= MaxDistance; distance++)
        {
            var left = index - distance;
            if (left >= 0 && IsIdentifierChar(lineText[left]) && IsSnapFriendlyNeighbor(lineText, left + 1, index))
            {
                return left;
            }

            var right = index + distance;
            if (right < lineText.Length && IsIdentifierChar(lineText[right]) && IsSnapFriendlyNeighbor(lineText, index, right - 1))
            {
                return right;
            }
        }

        return -1;
    }

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';

    private static bool IsSnapFriendlyNeighbor(string lineText, int start, int end)
    {
        if (start > end)
        {
            return true;
        }

        for (var i = start; i <= end; i++)
        {
            if (i < 0 || i >= lineText.Length)
            {
                continue;
            }

            var ch = lineText[i];
            if (char.IsWhiteSpace(ch))
            {
                continue;
            }

            if (ch is '.' or '?' or '(' or ')' or '[' or ']' or '{' or '}' or ',' or ';' or ':')
            {
                continue;
            }

            return false;
        }

        return true;
    }

    private static int FirstMismatch(
        int[] expectedStarts,
        int[] expectedLengths,
        int[] actualStarts,
        int[] actualLengths)
    {
        for (var i = 0; i < expectedStarts.Length; i++)
        {
            if (expectedStarts[i] != actualStarts[i] || expectedLengths[i] != actualLengths[i])
            {
                return i;
            }
        }

        return expectedStarts.Length;
    }
}

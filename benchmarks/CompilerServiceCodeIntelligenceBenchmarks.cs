using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

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

    private Func<string, int[], int[], int[], int[], int[], int[], int> _nsharpIdentifierSpansInto =
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
        _nsharpIdentifierSpansInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceIdentifierSpansInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpSpanStarts = new int[_queryCount];
        _csharpSpanLengths = new int[_queryCount];
        _nsharpSpanStarts = new int[_queryCount];
        _nsharpSpanLengths = new int[_queryCount];

        BuildQueries();

        var expectedCount = CSharpCodeIntelligenceIdentifierSpans_QueryBatch();
        var actualCount = NSharpCodeIntelligenceIdentifierSpans_QueryBatch();
        if (expectedCount != actualCount)
        {
            throw new InvalidOperationException(
                $"N# identifier span match count mismatch for {Corpus}: expected {expectedCount}, got {actualCount}.");
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
        var foundCount = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var span = ExtractIdentifierSpanAtPosition(_source, _queryLines[i], _queryColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            _csharpSpanStarts[i] = start;
            _csharpSpanLengths[i] = length;
            if (start >= 0)
            {
                foundCount++;
            }
        }

        return foundCount;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceIdentifierSpans_QueryBatch() =>
        _nsharpIdentifierSpansInto(
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

/// <summary>
/// Dogfood benchmark for strict editor identifier extraction used by LSP hover, definition,
/// references, and rename entry points.
///
/// The C# baseline is the previous editor utility shape: split the full source for each request and
/// scan only when the cursor is directly on an identifier or at the end of one. The N# candidate
/// reuses cached line ranges and writes identifier spans into caller-owned result buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceEditorIdentifierSpanBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int> _nsharpBuildLineRangesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<string, int[], int[], int, int[], int[], int[], int[], int> _nsharpEditorIdentifierSpansFromLinesInto =
        (_, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpSpanLengths = Array.Empty<int>();
    private int[] _csharpSpanStarts = Array.Empty<int>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int[] _nsharpSpanLengths = Array.Empty<int>();
    private int[] _nsharpSpanStarts = Array.Empty<int>();
    private int[] _queryColumns = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int _lineCount;
    private int _queryCount;
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus)
            + "\n    value := input.Count\n"
            + "    other := value\n";
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpBuildLineRangesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "BuildCodeIntelligenceLineRangesInto");
        _nsharpEditorIdentifierSpansFromLinesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int, int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceEditorIdentifierSpansFromLinesInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpSpanStarts = new int[_queryCount];
        _csharpSpanLengths = new int[_queryCount];
        _nsharpSpanStarts = new int[_queryCount];
        _nsharpSpanLengths = new int[_queryCount];

        BuildQueries();
        _lineCount = _nsharpBuildLineRangesInto(_source, _lineStarts, _lineLengths);

        var expectedCount = CSharpCodeIntelligenceEditorIdentifierSpans_QueryBatch();
        var actualCount = NSharpCodeIntelligenceEditorIdentifierSpans_CachedLineRanges_QueryBatch();
        if (expectedCount != actualCount)
        {
            throw new InvalidOperationException(
                $"N# editor identifier span match count mismatch for {Corpus}: expected {expectedCount}, got {actualCount}.");
        }

        if (!_csharpSpanStarts.SequenceEqual(_nsharpSpanStarts)
            || !_csharpSpanLengths.SequenceEqual(_nsharpSpanLengths))
        {
            var mismatch = FirstMismatch(_csharpSpanStarts, _csharpSpanLengths, _nsharpSpanStarts, _nsharpSpanLengths);
            throw new InvalidOperationException(
                $"N# editor identifier span mismatch for {Corpus} at query {mismatch}: " +
                $"line {_queryLines[mismatch]}, column {_queryColumns[mismatch]}, " +
                $"expected {_csharpSpanStarts[mismatch]}/{_csharpSpanLengths[mismatch]}, " +
                $"got {_nsharpSpanStarts[mismatch]}/{_nsharpSpanLengths[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceEditorIdentifierSpans_QueryBatch()
    {
        var foundCount = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var span = ExtractEditorIdentifierSpanAtPosition(_source, _queryLines[i], _queryColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            _csharpSpanStarts[i] = start;
            _csharpSpanLengths[i] = length;
            if (start >= 0)
            {
                foundCount++;
            }
        }

        return foundCount;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceEditorIdentifierSpans_CachedLineRanges_QueryBatch() =>
        _nsharpEditorIdentifierSpansFromLinesInto(
            _source,
            _lineStarts,
            _lineLengths,
            _lineCount,
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

            var lineIndex = i * 19 % lines.Length;
            var lineText = lines[lineIndex];
            var identifier = FindFirstIdentifierSpan(lineText);
            _queryLines[i] = lineIndex + 1;

            if (lineText.Length == 0)
            {
                _queryColumns[i] = 1;
                continue;
            }

            var dotColumn = lineText.IndexOf('.', StringComparison.Ordinal) + 1;
            _queryColumns[i] = i % 7 switch
            {
                0 => identifier.StartColumn,
                1 => identifier.StartColumn + Math.Max(0, identifier.Length - 1),
                2 => identifier.StartColumn + identifier.Length,
                3 => lineText.Length + 8,
                4 => 0,
                5 => dotColumn > 0 ? dotColumn : Math.Min(lineText.Length, identifier.StartColumn + identifier.Length),
                _ => Math.Min(lineText.Length, i * 29 % lineText.Length + 1)
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

    private static (int StartColumn, int Length)? ExtractEditorIdentifierSpanAtPosition(string source, int line, int column)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length || column <= 0)
            {
                return null;
            }

            var lineText = lines[line - 1];
            if (lineText.Length == 0)
            {
                return null;
            }

            var character = column - 1;
            if (character >= lineText.Length)
            {
                character = lineText.Length - 1;
                if (!IsIdentifierChar(lineText[character]))
                {
                    return null;
                }
            }
            else if (!IsIdentifierChar(lineText[character]))
            {
                return null;
            }

            var start = character;
            while (start > 0 && IsIdentifierChar(lineText[start - 1]))
            {
                start--;
            }

            var end = character;
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

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';

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

/// <summary>
/// Dogfood benchmark for the declaration-name span guard used by strict reference and rename flows.
///
/// The current C# guard splits the whole file for each candidate declaration, searches the selected
/// line for the declaration name at or after the declaration column, and checks whether the selected
/// identifier span exactly covers that occurrence. The N# candidate reuses cached line ranges and
/// runs the same ordinal name search into caller-owned match buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDeclarationNameMatchBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int> _nsharpBuildLineRangesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<string, int[], int[], int, int[], int[], string[], int[], int[], int[], int> _nsharpDeclarationNameMatchChecksumFromLinesInto =
        (_, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpMatches = Array.Empty<int>();
    private int[] _declarationColumns = Array.Empty<int>();
    private string[] _declarationNames = Array.Empty<string>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int _lineCount;
    private int[] _nsharpMatches = Array.Empty<int>();
    private int _queryCount;
    private int[] _queryLines = Array.Empty<int>();
    private int[] _selectedEndColumns = Array.Empty<int>();
    private int[] _selectedStartColumns = Array.Empty<int>();
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus) + """

func declarationMatchProbe() {
    value := value + 1
    prefixvalue := value
    café := café
}
""";
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpBuildLineRangesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "BuildCodeIntelligenceLineRangesInto");
        _nsharpDeclarationNameMatchChecksumFromLinesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int, int[], int[], string[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceDeclarationNameMatchChecksumFromLinesInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpMatches = new int[_queryCount];
        _nsharpMatches = new int[_queryCount];

        BuildQueries();
        _lineCount = _nsharpBuildLineRangesInto(_source, _lineStarts, _lineLengths);

        var expectedChecksum = CSharpCodeIntelligenceDeclarationNameMatches_QueryBatch();
        var actualChecksum = NSharpCodeIntelligenceDeclarationNameMatches_CachedLineRanges_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# declaration-name match checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpMatches.SequenceEqual(_nsharpMatches))
        {
            var mismatch = FirstMismatch(_csharpMatches, _nsharpMatches);
            throw new InvalidOperationException(
                $"N# declaration-name match mismatch for {Corpus} at query {mismatch}: " +
                $"line {_queryLines[mismatch]}, declaration column {_declarationColumns[mismatch]}, " +
                $"name {_declarationNames[mismatch]}, selected {_selectedStartColumns[mismatch]}-{_selectedEndColumns[mismatch]}, " +
                $"expected {_csharpMatches[mismatch]}, got {_nsharpMatches[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceDeclarationNameMatches_QueryBatch()
    {
        var checksum = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var matches = SelectedSpanMatchesDeclarationName(
                _source,
                _queryLines[i],
                _declarationColumns[i],
                _declarationNames[i],
                _selectedStartColumns[i],
                _selectedEndColumns[i]);
            _csharpMatches[i] = matches ? 1 : 0;
            checksum += _csharpMatches[i] * (i + 1);
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceDeclarationNameMatches_CachedLineRanges_QueryBatch() =>
        _nsharpDeclarationNameMatchChecksumFromLinesInto(
            _source,
            _lineStarts,
            _lineLengths,
            _lineCount,
            _queryLines,
            _declarationColumns,
            _declarationNames,
            _selectedStartColumns,
            _selectedEndColumns,
            _nsharpMatches);

    private void BuildQueries()
    {
        _queryLines = new int[_queryCount];
        _declarationColumns = new int[_queryCount];
        _declarationNames = new string[_queryCount];
        _selectedStartColumns = new int[_queryCount];
        _selectedEndColumns = new int[_queryCount];

        var lines = _source.Split('\n');
        var valueLine = FindLine(lines, "value := value + 1");
        var prefixLine = FindLine(lines, "prefixvalue := value");
        var cafeLine = FindLine(lines, "café := café");
        var firstValueColumn = FindNameStartColumn(lines[valueLine - 1], "value", 1);
        var secondValueColumn = FindNameStartColumn(lines[valueLine - 1], "value", firstValueColumn + "value".Length);
        var prefixValueColumn = FindNameStartColumn(lines[prefixLine - 1], "value", 1);
        var cafeColumn = FindNameStartColumn(lines[cafeLine - 1], "café", 1);

        for (var i = 0; i < _queryCount; i++)
        {
            switch (i % 9)
            {
                case 0:
                    _queryLines[i] = 0;
                    _declarationColumns[i] = 1;
                    _declarationNames[i] = "value";
                    _selectedStartColumns[i] = 1;
                    _selectedEndColumns[i] = 5;
                    break;
                case 1:
                    _queryLines[i] = valueLine;
                    _declarationColumns[i] = firstValueColumn;
                    _declarationNames[i] = "value";
                    _selectedStartColumns[i] = firstValueColumn;
                    _selectedEndColumns[i] = firstValueColumn + "value".Length - 1;
                    break;
                case 2:
                    _queryLines[i] = valueLine;
                    _declarationColumns[i] = firstValueColumn;
                    _declarationNames[i] = "value";
                    _selectedStartColumns[i] = secondValueColumn;
                    _selectedEndColumns[i] = secondValueColumn + "value".Length - 1;
                    break;
                case 3:
                    _queryLines[i] = valueLine;
                    _declarationColumns[i] = secondValueColumn;
                    _declarationNames[i] = "value";
                    _selectedStartColumns[i] = secondValueColumn;
                    _selectedEndColumns[i] = secondValueColumn + "value".Length - 1;
                    break;
                case 4:
                    _queryLines[i] = prefixLine;
                    _declarationColumns[i] = 1;
                    _declarationNames[i] = "value";
                    _selectedStartColumns[i] = prefixValueColumn;
                    _selectedEndColumns[i] = prefixValueColumn + "value".Length - 1;
                    break;
                case 5:
                    _queryLines[i] = prefixLine;
                    _declarationColumns[i] = prefixValueColumn + "value".Length;
                    _declarationNames[i] = "value";
                    _selectedStartColumns[i] = prefixValueColumn;
                    _selectedEndColumns[i] = prefixValueColumn + "value".Length - 1;
                    break;
                case 6:
                    _queryLines[i] = cafeLine;
                    _declarationColumns[i] = cafeColumn;
                    _declarationNames[i] = "café";
                    _selectedStartColumns[i] = cafeColumn;
                    _selectedEndColumns[i] = cafeColumn + "café".Length - 1;
                    break;
                case 7:
                    _queryLines[i] = i * 17 % lines.Length + 1;
                    _declarationColumns[i] = i % 23 + 1;
                    _declarationNames[i] = "missing";
                    _selectedStartColumns[i] = 1;
                    _selectedEndColumns[i] = 7;
                    break;
                default:
                    _queryLines[i] = lines.Length + 1;
                    _declarationColumns[i] = 1;
                    _declarationNames[i] = "value";
                    _selectedStartColumns[i] = 1;
                    _selectedEndColumns[i] = 5;
                    break;
            }
        }
    }

    private static bool SelectedSpanMatchesDeclarationName(
        string source,
        int line,
        int declarationColumn,
        string declarationName,
        int selectedStartColumn,
        int selectedEndColumn)
    {
        var lines = source.Split('\n');
        if (line <= 0 || line > lines.Length)
        {
            return false;
        }

        var lineText = lines[line - 1];
        var searchStart = Math.Max(0, Math.Min(declarationColumn - 1, lineText.Length));
        var nameIndex = lineText.IndexOf(declarationName, searchStart, StringComparison.Ordinal);
        if (nameIndex < 0)
        {
            return false;
        }

        var nameStartColumn = nameIndex + 1;
        var nameEndColumn = nameStartColumn + declarationName.Length - 1;
        return selectedStartColumn == nameStartColumn && selectedEndColumn == nameEndColumn;
    }

    private static int FindLine(string[] lines, string text)
    {
        for (var i = 0; i < lines.Length; i++)
        {
            if (lines[i].Contains(text, StringComparison.Ordinal))
            {
                return i + 1;
            }
        }

        throw new InvalidOperationException($"Could not find benchmark line containing {text}.");
    }

    private static int FindNameStartColumn(string lineText, string name, int searchStartColumn)
    {
        var searchStart = Math.Max(0, searchStartColumn - 1);
        var index = lineText.IndexOf(name, searchStart, StringComparison.Ordinal);
        if (index < 0)
        {
            throw new InvalidOperationException(
                $"Could not find benchmark name {name} in {lineText} at or after column {searchStartColumn}.");
        }

        return index + 1;
    }

    private static int FirstMismatch(int[] expected, int[] actual)
    {
        for (var i = 0; i < expected.Length; i++)
        {
            if (expected[i] != actual[i])
            {
                return i;
            }
        }

        return expected.Length;
    }
}

/// <summary>
/// Dogfood benchmark for analyzer declaration-name column lookup before binding-map declaration
/// recording.
///
/// The current C# helper splits the whole source for each declaration, trims a trailing CR from the
/// selected line, then searches for the whole identifier at or after the parser fallback column. The
/// N# candidate reuses cached line ranges and writes resolved columns into caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDeclarationNameColumnBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int> _nsharpBuildLineRangesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<string, int[], int[], int, int[], string[], int[], int[], int> _nsharpIdentifierNameColumnChecksumFromLinesInto =
        (_, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpColumns = Array.Empty<int>();
    private int[] _fallbackColumns = Array.Empty<int>();
    private string[] _declarationNames = Array.Empty<string>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int _lineCount;
    private int[] _nsharpColumns = Array.Empty<int>();
    private int _queryCount;
    private int[] _queryLines = Array.Empty<int>();
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus) + """

func declarationColumnProbe(value: int): int {
    prefixvalue := value
    café := café + value
    spaced    := 4
    return value
}
""";
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpBuildLineRangesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "BuildCodeIntelligenceLineRangesInto");
        _nsharpIdentifierNameColumnChecksumFromLinesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int, int[], string[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceIdentifierNameColumnChecksumFromLinesInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpColumns = new int[_queryCount];
        _nsharpColumns = new int[_queryCount];

        BuildQueries();
        _lineCount = _nsharpBuildLineRangesInto(_source, _lineStarts, _lineLengths);

        var expectedChecksum = CSharpCodeIntelligenceDeclarationNameColumns_QueryBatch();
        var actualChecksum = NSharpCodeIntelligenceDeclarationNameColumns_CachedLineRanges_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# declaration-name column checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpColumns.SequenceEqual(_nsharpColumns))
        {
            var mismatch = FirstMismatch(_csharpColumns, _nsharpColumns);
            throw new InvalidOperationException(
                $"N# declaration-name column mismatch for {Corpus} at query {mismatch}: " +
                $"line {_queryLines[mismatch]}, fallback {_fallbackColumns[mismatch]}, name {_declarationNames[mismatch]}, " +
                $"expected {_csharpColumns[mismatch]}, got {_nsharpColumns[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceDeclarationNameColumns_QueryBatch()
    {
        var foundCount = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            if (TryFindIdentifierNameColumnWithSplit(
                    _source,
                    _declarationNames[i],
                    _queryLines[i],
                    _fallbackColumns[i],
                    out var column))
            {
                foundCount++;
            }

            _csharpColumns[i] = column;
        }

        var checksum = foundCount;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            checksum += _csharpColumns[i] * 31 + _fallbackColumns[i] * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceDeclarationNameColumns_CachedLineRanges_QueryBatch() =>
        _nsharpIdentifierNameColumnChecksumFromLinesInto(
            _source,
            _lineStarts,
            _lineLengths,
            _lineCount,
            _queryLines,
            _declarationNames,
            _fallbackColumns,
            _nsharpColumns);

    private void BuildQueries()
    {
        _queryLines = new int[_queryCount];
        _declarationNames = new string[_queryCount];
        _fallbackColumns = new int[_queryCount];

        var lines = _source.Split('\n');
        var functionLine = FindLine(lines, "func declarationColumnProbe");
        var prefixLine = FindLine(lines, "prefixvalue := value");
        var cafeLine = FindLine(lines, "café := café + value");
        var spacedLine = FindLine(lines, "spaced    := 4");
        var returnLine = FindLine(lines, "return value");
        var functionColumn = FindWholeIdentifierColumn(lines[functionLine - 1], "declarationColumnProbe", 1);
        var prefixWholeValueColumn = FindWholeIdentifierColumn(lines[prefixLine - 1], "value", 1);
        var prefixIdentifierColumn = FindWholeIdentifierColumn(lines[prefixLine - 1], "prefixvalue", 1);
        var cafeColumn = FindWholeIdentifierColumn(lines[cafeLine - 1], "café", 1);
        var cafeSecondColumn = FindWholeIdentifierColumn(lines[cafeLine - 1], "café", cafeColumn + "café".Length);
        var spacedColumn = FindWholeIdentifierColumn(lines[spacedLine - 1], "spaced", 1);
        var returnValueColumn = FindWholeIdentifierColumn(lines[returnLine - 1], "value", 1);

        for (var i = 0; i < _queryCount; i++)
        {
            switch (i % 11)
            {
                case 0:
                    _queryLines[i] = 0;
                    _declarationNames[i] = "value";
                    _fallbackColumns[i] = 99;
                    break;
                case 1:
                    _queryLines[i] = functionLine;
                    _declarationNames[i] = "declarationColumnProbe";
                    _fallbackColumns[i] = functionColumn;
                    break;
                case 2:
                    _queryLines[i] = functionLine;
                    _declarationNames[i] = "declarationColumnProbe";
                    _fallbackColumns[i] = functionColumn + 8;
                    break;
                case 3:
                    _queryLines[i] = prefixLine;
                    _declarationNames[i] = "value";
                    _fallbackColumns[i] = 1;
                    break;
                case 4:
                    _queryLines[i] = prefixLine;
                    _declarationNames[i] = "prefixvalue";
                    _fallbackColumns[i] = prefixIdentifierColumn;
                    break;
                case 5:
                    _queryLines[i] = prefixLine;
                    _declarationNames[i] = "value";
                    _fallbackColumns[i] = prefixWholeValueColumn;
                    break;
                case 6:
                    _queryLines[i] = cafeLine;
                    _declarationNames[i] = "café";
                    _fallbackColumns[i] = cafeSecondColumn;
                    break;
                case 7:
                    _queryLines[i] = spacedLine;
                    _declarationNames[i] = "spaced";
                    _fallbackColumns[i] = spacedColumn + 20;
                    break;
                case 8:
                    _queryLines[i] = returnLine;
                    _declarationNames[i] = "value";
                    _fallbackColumns[i] = returnValueColumn;
                    break;
                case 9:
                    _queryLines[i] = i * 17 % lines.Length + 1;
                    _declarationNames[i] = "missing";
                    _fallbackColumns[i] = i % 29 + 1;
                    break;
                default:
                    _queryLines[i] = lines.Length + 1;
                    _declarationNames[i] = "value";
                    _fallbackColumns[i] = 7;
                    break;
            }
        }
    }

    private static bool TryFindIdentifierNameColumnWithSplit(
        string? sourceText,
        string name,
        int line,
        int fallbackColumn,
        out int column)
    {
        column = fallbackColumn;
        if (string.IsNullOrWhiteSpace(sourceText) || line <= 0)
        {
            return false;
        }

        var lines = sourceText.Split('\n');
        if (line > lines.Length)
        {
            return false;
        }

        var lineText = lines[line - 1].TrimEnd('\r');
        if (lineText.Length == 0)
        {
            return false;
        }

        var start = Math.Clamp(fallbackColumn - 1, 0, lineText.Length);
        var index = FindWholeIdentifier(lineText, name, start);
        if (index < 0)
        {
            index = FindWholeIdentifier(lineText, name, 0);
        }

        if (index < 0)
        {
            return false;
        }

        column = index + 1;
        return true;
    }

    private static int FindWholeIdentifier(string line, string name, int startIndex)
    {
        var searchStart = Math.Clamp(startIndex, 0, line.Length);
        while (searchStart <= line.Length)
        {
            var index = line.IndexOf(name, searchStart, StringComparison.Ordinal);
            if (index < 0)
            {
                return -1;
            }

            var before = index > 0 ? line[index - 1] : '\0';
            var afterIndex = index + name.Length;
            var after = afterIndex < line.Length ? line[afterIndex] : '\0';
            if (!IsIdentifierChar(before) && !IsIdentifierChar(after))
            {
                return index;
            }

            searchStart = index + Math.Max(1, name.Length);
        }

        return -1;
    }

    private static int FindWholeIdentifierColumn(string lineText, string name, int searchStartColumn)
    {
        var index = FindWholeIdentifier(lineText, name, searchStartColumn - 1);
        if (index < 0)
        {
            throw new InvalidOperationException(
                $"Could not find benchmark whole identifier {name} in {lineText} at or after column {searchStartColumn}.");
        }

        return index + 1;
    }

    private static int FindLine(string[] lines, string text)
    {
        for (var i = 0; i < lines.Length; i++)
        {
            if (lines[i].Contains(text, StringComparison.Ordinal))
            {
                return i + 1;
            }
        }

        throw new InvalidOperationException($"Could not find benchmark line containing {text}.");
    }

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';

    private static int FirstMismatch(int[] expected, int[] actual)
    {
        for (var i = 0; i < expected.Length; i++)
        {
            if (expected[i] != actual[i])
            {
                return i;
            }
        }

        return expected.Length;
    }
}

/// <summary>
/// Dogfood benchmark for extracting the receiver name before a member access.
///
/// The current C# helper splits the whole file and returns a receiver substring for each query. The
/// N# candidate reuses line ranges and writes receiver start/length pairs into caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceMemberReceiverBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int[], int[], int[], int[], int[], int[], int> _nsharpMemberReceiversCachedInto =
        (_, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpReceiverLengths = Array.Empty<int>();
    private int[] _csharpReceiverStarts = Array.Empty<int>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int[] _memberStartColumns = Array.Empty<int>();
    private int[] _nsharpReceiverLengths = Array.Empty<int>();
    private int[] _nsharpReceiverStarts = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int[] _receiverLengthsBySeparator = Array.Empty<int>();
    private int[] _receiverStartsBySeparator = Array.Empty<int>();
    private int _queryCount;
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus) + """

func memberReceiverProbe(customer: Customer, résumé: Profile) {
    print customer   .Name
    print customer?.Name
    print résumé.Count
}
""";
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpMemberReceiversCachedInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceMemberReceiversCachedInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpReceiverStarts = new int[_queryCount];
        _csharpReceiverLengths = new int[_queryCount];
        _nsharpReceiverStarts = new int[_queryCount];
        _nsharpReceiverLengths = new int[_queryCount];
        _receiverStartsBySeparator = new int[_source.Length + 1];
        _receiverLengthsBySeparator = new int[_source.Length + 1];

        BuildQueries();

        var expectedCount = CSharpCodeIntelligenceMemberReceivers_QueryBatch();
        var actualCount = NSharpCodeIntelligenceMemberReceivers_QueryBatch();
        if (expectedCount != actualCount)
        {
            throw new InvalidOperationException(
                $"N# member receiver match count mismatch for {Corpus}: expected {expectedCount}, got {actualCount}.");
        }

        if (!_csharpReceiverStarts.SequenceEqual(_nsharpReceiverStarts)
            || !_csharpReceiverLengths.SequenceEqual(_nsharpReceiverLengths))
        {
            var mismatch = FirstMismatch(_csharpReceiverStarts, _csharpReceiverLengths, _nsharpReceiverStarts, _nsharpReceiverLengths);
            throw new InvalidOperationException(
                $"N# member receiver mismatch for {Corpus} at query {mismatch}: " +
                $"line {_queryLines[mismatch]}, member column {_memberStartColumns[mismatch]}, " +
                $"expected {_csharpReceiverStarts[mismatch]}/{_csharpReceiverLengths[mismatch]}, " +
                $"got {_nsharpReceiverStarts[mismatch]}/{_nsharpReceiverLengths[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceMemberReceivers_QueryBatch()
    {
        var foundCount = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var span = ExtractMemberReceiverSpan(_source, _queryLines[i], _memberStartColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            _csharpReceiverStarts[i] = start;
            _csharpReceiverLengths[i] = length;
            if (start >= 0)
            {
                foundCount++;
            }
        }

        return foundCount;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceMemberReceivers_QueryBatch() =>
        _nsharpMemberReceiversCachedInto(
            _source,
            _lineStarts,
            _lineLengths,
            _receiverStartsBySeparator,
            _receiverLengthsBySeparator,
            _queryLines,
            _memberStartColumns,
            _nsharpReceiverStarts,
            _nsharpReceiverLengths);

    private void BuildQueries()
    {
        _queryLines = new int[_queryCount];
        _memberStartColumns = new int[_queryCount];

        var candidates = FindMemberStartCandidates(_source);
        if (candidates.Count == 0)
        {
            throw new InvalidOperationException($"No member receiver candidates found for {Corpus}.");
        }

        var lines = _source.Split('\n');
        for (var i = 0; i < _queryCount; i++)
        {
            if (i % 37 == 0)
            {
                _queryLines[i] = i % 2 == 0 ? 0 : lines.Length + 1;
                _memberStartColumns[i] = i % 11;
                continue;
            }

            if (i % 11 == 0)
            {
                var lineIndex = i * 19 % lines.Length;
                _queryLines[i] = lineIndex + 1;
                _memberStartColumns[i] = Math.Max(1, lines[lineIndex].Length + 8);
                continue;
            }

            var candidate = candidates[i * 17 % candidates.Count];
            _queryLines[i] = candidate.Line;
            _memberStartColumns[i] = candidate.MemberStartColumn;
        }
    }

    private static List<(int Line, int MemberStartColumn)> FindMemberStartCandidates(string source)
    {
        var candidates = new List<(int Line, int MemberStartColumn)>();
        var lines = source.Split('\n');
        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var lineText = lines[lineIndex];
            for (var i = 0; i < lineText.Length - 1; i++)
            {
                if (lineText[i] != '.')
                {
                    continue;
                }

                var memberStart = i + 1;
                if (memberStart < lineText.Length && IsIdentifierChar(lineText[memberStart]))
                {
                    candidates.Add((lineIndex + 1, memberStart + 1));
                }
            }
        }

        return candidates;
    }

    private static (int StartColumn, int Length)? ExtractMemberReceiverSpan(string source, int line, int memberStartColumn)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
            {
                return null;
            }

            var lineText = lines[line - 1];
            var memberStartIndex = memberStartColumn - 1;
            if (memberStartIndex <= 0 || memberStartIndex > lineText.Length)
            {
                return null;
            }

            var separatorIndex = memberStartIndex - 1;
            if (separatorIndex >= 0 && lineText[separatorIndex] == '.')
            {
                var receiverEnd = separatorIndex - 1;
                while (receiverEnd >= 0 && char.IsWhiteSpace(lineText[receiverEnd]))
                {
                    receiverEnd--;
                }

                if (receiverEnd < 0)
                {
                    return null;
                }

                var receiverStart = receiverEnd;
                while (receiverStart >= 0 && IsIdentifierChar(lineText[receiverStart]))
                {
                    receiverStart--;
                }

                receiverStart++;
                if (receiverStart <= receiverEnd)
                {
                    var receiver = lineText.Substring(receiverStart, receiverEnd - receiverStart + 1);
                    return (receiverStart + 1, receiver.Length);
                }

                return null;
            }

            if (separatorIndex >= 1 && lineText[separatorIndex - 1] == '?' && lineText[separatorIndex] == '.')
            {
                var receiverEnd = separatorIndex - 2;
                while (receiverEnd >= 0 && char.IsWhiteSpace(lineText[receiverEnd]))
                {
                    receiverEnd--;
                }

                if (receiverEnd < 0)
                {
                    return null;
                }

                var receiverStart = receiverEnd;
                while (receiverStart >= 0 && IsIdentifierChar(lineText[receiverStart]))
                {
                    receiverStart--;
                }

                receiverStart++;
                if (receiverStart <= receiverEnd)
                {
                    var receiver = lineText.Substring(receiverStart, receiverEnd - receiverStart + 1);
                    return (receiverStart + 1, receiver.Length);
                }

                return null;
            }

            return null;
        }
        catch
        {
            return null;
        }
    }

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';

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

/// <summary>
/// Dogfood benchmark for source context extraction used by references, diagnostics, hover, and
/// query output.
///
/// The current C# helper splits the whole file and trims the selected line for each query. The N#
/// candidate reuses caller-owned line ranges and writes trimmed absolute source spans into buffers,
/// allowing callers to materialize only the contexts they actually return.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceSourceContextBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int[], int[], int[], int> _nsharpSourceContextsInto =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpContextLengths = Array.Empty<int>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int[] _nsharpContextLengths = Array.Empty<int>();
    private int[] _nsharpContextStarts = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int _queryCount;
    private string _source = string.Empty;
    private string?[] _expectedContexts = Array.Empty<string?>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus) + """

func sourceContextProbe() {
       print "trim me"

	  print "tabs"
}
""";
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpSourceContextsInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceSourceContextsInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpContextLengths = new int[_queryCount];
        _nsharpContextStarts = new int[_queryCount];
        _nsharpContextLengths = new int[_queryCount];

        BuildQueries();

        _expectedContexts = new string?[_queryLines.Length];
        for (var i = 0; i < _queryLines.Length; i++)
        {
            _expectedContexts[i] = ExtractSourceContext(_source, _queryLines[i]);
        }

        var expectedCount = CSharpCodeIntelligenceSourceContexts_QueryBatch();
        var actualCount = NSharpCodeIntelligenceSourceContexts_QueryBatch();
        if (expectedCount != actualCount)
        {
            throw new InvalidOperationException(
                $"N# source context count mismatch for {Corpus}: expected {expectedCount}, got {actualCount}.");
        }

        for (var i = 0; i < _queryLines.Length; i++)
        {
            var actual = _nsharpContextStarts[i] >= 0
                ? _source.Substring(_nsharpContextStarts[i], _nsharpContextLengths[i])
                : null;
            if (!string.Equals(_expectedContexts[i], actual, StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    $"N# source context mismatch for {Corpus} at query {i}: line {_queryLines[i]}, " +
                    $"expected {FormatContext(_expectedContexts[i])}, got {FormatContext(actual)}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceSourceContexts_QueryBatch()
    {
        var foundCount = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var context = ExtractSourceContext(_source, _queryLines[i]);
            _csharpContextLengths[i] = context?.Length ?? -1;
            if (context != null)
            {
                foundCount++;
            }
        }

        return foundCount;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceSourceContexts_QueryBatch() =>
        _nsharpSourceContextsInto(
            _source,
            _lineStarts,
            _lineLengths,
            _queryLines,
            _nsharpContextStarts,
            _nsharpContextLengths);

    private void BuildQueries()
    {
        _queryLines = new int[_queryCount];

        var lines = _source.Split('\n');
        for (var i = 0; i < _queryCount; i++)
        {
            if (i % 37 == 0)
            {
                _queryLines[i] = i % 2 == 0 ? 0 : lines.Length + 1;
                continue;
            }

            _queryLines[i] = i * 17 % lines.Length + 1;
        }
    }

    private static string? ExtractSourceContext(string source, int line)
    {
        var lines = source.Split('\n');
        return line <= 0 || line > lines.Length
            ? null
            : lines[line - 1].Trim();
    }

    private static string FormatContext(string? context) =>
        context == null ? "<null>" : $"\"{context}\"";
}

/// <summary>
/// Dogfood benchmark for raw source-line extraction used by diagnostic and lint snippets.
///
/// The current C# helper splits the whole file and returns the selected untrimmed line for each
/// query. The N# candidate reuses caller-owned line ranges and writes absolute source-line spans
/// into buffers, preserving the current LF split behavior including trailing CR characters on CRLF
/// input.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceSourceLineBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int> _nsharpBuildLineRangesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<int[], int[], int, int[], int[], int[], int> _nsharpSourceLinesFromLinesInto =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpLineLengths = Array.Empty<int>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int[] _nsharpLineLengths = Array.Empty<int>();
    private int[] _nsharpLineStarts = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int _lineCount;
    private int _queryCount;
    private string _source = string.Empty;
    private string?[] _expectedLines = Array.Empty<string?>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus)
            + "    rawLineProbe := 1\r\n"
            + "\tindentedLine := rawLineProbe\n"
            + "\n";
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpBuildLineRangesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "BuildCodeIntelligenceLineRangesInto");
        _nsharpSourceLinesFromLinesInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int, int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceSourceLinesFromLinesInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpLineLengths = new int[_queryCount];
        _nsharpLineStarts = new int[_queryCount];
        _nsharpLineLengths = new int[_queryCount];

        BuildQueries();
        _lineCount = _nsharpBuildLineRangesInto(_source, _lineStarts, _lineLengths);

        _expectedLines = new string?[_queryLines.Length];
        for (var i = 0; i < _queryLines.Length; i++)
        {
            _expectedLines[i] = ExtractSourceLine(_source, _queryLines[i]);
        }

        var expectedCount = CSharpCodeIntelligenceSourceLines_QueryBatch();
        var actualCount = NSharpCodeIntelligenceSourceLines_CachedLineRanges_QueryBatch();
        if (expectedCount != actualCount)
        {
            throw new InvalidOperationException(
                $"N# source line count mismatch for {Corpus}: expected {expectedCount}, got {actualCount}.");
        }

        for (var i = 0; i < _queryLines.Length; i++)
        {
            var actual = _nsharpLineStarts[i] >= 0
                ? _source.Substring(_nsharpLineStarts[i], _nsharpLineLengths[i])
                : null;
            if (!string.Equals(_expectedLines[i], actual, StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    $"N# source line mismatch for {Corpus} at query {i}: line {_queryLines[i]}, " +
                    $"expected {FormatContext(_expectedLines[i])}, got {FormatContext(actual)}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceSourceLines_QueryBatch()
    {
        var foundCount = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var line = ExtractSourceLine(_source, _queryLines[i]);
            _csharpLineLengths[i] = line?.Length ?? -1;
            if (line != null)
            {
                foundCount++;
            }
        }

        return foundCount;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceSourceLines_CachedLineRanges_QueryBatch() =>
        _nsharpSourceLinesFromLinesInto(
            _lineStarts,
            _lineLengths,
            _lineCount,
            _queryLines,
            _nsharpLineStarts,
            _nsharpLineLengths);

    private void BuildQueries()
    {
        _queryLines = new int[_queryCount];

        var lines = _source.Split('\n');
        for (var i = 0; i < _queryCount; i++)
        {
            if (i % 37 == 0)
            {
                _queryLines[i] = i % 2 == 0 ? 0 : lines.Length + 1;
                continue;
            }

            _queryLines[i] = i * 17 % lines.Length + 1;
        }
    }

    private static string? ExtractSourceLine(string source, int line)
    {
        var lines = source.Split('\n');
        return line <= 0 || line > lines.Length
            ? null
            : lines[line - 1];
    }

    private static string FormatContext(string? context) =>
        context == null ? "<null>" : $"\"{context}\"";
}

/// <summary>
/// Dogfood benchmark for completion prefix extraction used before deciding identifier vs member
/// access completion.
///
/// The current C# completion engine splits the whole file and materializes the text before the
/// cursor for each request. The N# candidate reuses cached line ranges and writes absolute prefix
/// spans into caller-owned result buffers, preserving completion's current column behavior: columns
/// less than one or past the line return the whole selected line.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceCompletionPrefixBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int> _nsharpBuildLineRangesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<int[], int[], int, int[], int[], int[], int[], int> _nsharpCompletionPrefixesFromLinesInto =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpPrefixLengths = Array.Empty<int>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int[] _nsharpPrefixLengths = Array.Empty<int>();
    private int[] _nsharpPrefixStarts = Array.Empty<int>();
    private int[] _queryColumns = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int _lineCount;
    private int _queryCount;
    private string _source = string.Empty;
    private string?[] _expectedPrefixes = Array.Empty<string?>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus)
            + "    Console.\r\n"
            + "\tname.ToUpper().\n"
            + "\n";
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpBuildLineRangesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "BuildCodeIntelligenceLineRangesInto");
        _nsharpCompletionPrefixesFromLinesInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int, int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceCompletionPrefixesFromLinesInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpPrefixLengths = new int[_queryCount];
        _nsharpPrefixStarts = new int[_queryCount];
        _nsharpPrefixLengths = new int[_queryCount];

        BuildQueries();
        _lineCount = _nsharpBuildLineRangesInto(_source, _lineStarts, _lineLengths);

        _expectedPrefixes = new string?[_queryLines.Length];
        for (var i = 0; i < _queryLines.Length; i++)
        {
            _expectedPrefixes[i] = ExtractCompletionPrefix(_source, _queryLines[i], _queryColumns[i]);
        }

        var expectedCount = CSharpCodeIntelligenceCompletionPrefixes_QueryBatch();
        var actualCount = NSharpCodeIntelligenceCompletionPrefixes_CachedLineRanges_QueryBatch();
        if (expectedCount != actualCount)
        {
            throw new InvalidOperationException(
                $"N# completion prefix count mismatch for {Corpus}: expected {expectedCount}, got {actualCount}.");
        }

        for (var i = 0; i < _queryLines.Length; i++)
        {
            var actual = _nsharpPrefixStarts[i] >= 0
                ? _source.Substring(_nsharpPrefixStarts[i], _nsharpPrefixLengths[i])
                : null;
            if (!string.Equals(_expectedPrefixes[i], actual, StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    $"N# completion prefix mismatch for {Corpus} at query {i}: line {_queryLines[i]}, column {_queryColumns[i]}, " +
                    $"expected {FormatContext(_expectedPrefixes[i])}, got {FormatContext(actual)}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceCompletionPrefixes_QueryBatch()
    {
        var foundCount = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var prefix = ExtractCompletionPrefix(_source, _queryLines[i], _queryColumns[i]);
            _csharpPrefixLengths[i] = prefix?.Length ?? -1;
            if (prefix != null)
            {
                foundCount++;
            }
        }

        return foundCount;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceCompletionPrefixes_CachedLineRanges_QueryBatch() =>
        _nsharpCompletionPrefixesFromLinesInto(
            _lineStarts,
            _lineLengths,
            _lineCount,
            _queryLines,
            _queryColumns,
            _nsharpPrefixStarts,
            _nsharpPrefixLengths);

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
                _queryColumns[i] = 1;
                continue;
            }

            var line = i * 17 % lines.Length + 1;
            var lineLength = lines[line - 1].Length;
            _queryLines[i] = line;
            _queryColumns[i] = i % 5 switch
            {
                0 => 0,
                1 => 1,
                2 => Math.Max(1, lineLength >> 1),
                3 => lineLength,
                _ => lineLength + 10
            };
        }
    }

    private static string? ExtractCompletionPrefix(string source, int line, int column)
    {
        var lines = source.Split('\n');
        if (line <= 0 || line > lines.Length)
        {
            return null;
        }

        var lineText = lines[line - 1];
        return column > 0 && column <= lineText.Length
            ? lineText.Substring(0, column)
            : lineText;
    }

    private static string FormatContext(string? context) =>
        context == null ? "<null>" : $"\"{context}\"";
}

/// <summary>
/// Dogfood benchmark for classifying completion receiver context after prefix extraction.
///
/// The current C# helper trims the prefix, scans for member-access dots, tokenizes candidate literal
/// receivers with the full lexer, and normalizes call arguments with a StringBuilder. The N# candidate
/// keeps the same output contract but uses direct prefix scans and caller-owned result arrays.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceCompletionReceiverBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string[], int[], string[], int> _nsharpCompletionReceiverChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpContexts = Array.Empty<int>();
    private string[] _csharpReceivers = Array.Empty<string>();
    private int[] _nsharpContexts = Array.Empty<int>();
    private string[] _nsharpReceivers = Array.Empty<string>();
    private string[] _prefixes = Array.Empty<string>();
    private int _queryCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpCompletionReceiverChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], int[], string[], int>>(
                DogfoodCompilerSources.CodeIntelligenceCompletionReceivers,
                "CodeIntelligenceCompletionReceiverChecksumInto");

        _prefixes = BuildPrefixes(_queryCount, Corpus);
        _csharpContexts = new int[_queryCount];
        _csharpReceivers = CreateEmptyStrings(_queryCount);
        _nsharpContexts = new int[_queryCount];
        _nsharpReceivers = CreateEmptyStrings(_queryCount);

        var expectedChecksum = CSharpCodeIntelligenceCompletionReceivers_QueryBatch();
        var actualChecksum = NSharpCodeIntelligenceCompletionReceivers_QueryBatch();
        if (!_csharpContexts.SequenceEqual(_nsharpContexts)
            || !_csharpReceivers.SequenceEqual(_nsharpReceivers, StringComparer.Ordinal))
        {
            var mismatch = FirstMismatch(_csharpContexts, _csharpReceivers, _nsharpContexts, _nsharpReceivers);
            throw new InvalidOperationException(
                $"N# completion receiver mismatch for {Corpus} at query {mismatch}: " +
                $"prefix {FormatContext(_prefixes[mismatch])}, " +
                $"expected {_csharpContexts[mismatch]}/{FormatContext(_csharpReceivers[mismatch])}, " +
                $"got {_nsharpContexts[mismatch]}/{FormatContext(_nsharpReceivers[mismatch])}.");
        }

        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# completion receiver checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceCompletionReceivers_QueryBatch()
    {
        var checksum = _prefixes.Length;
        for (var i = 0; i < _prefixes.Length; i++)
        {
            var prefix = _prefixes[i];
            var context = IsMemberAccessContext(prefix) ? 1 : 0;
            var receiver = context != 0 ? ExtractReceiver(prefix) ?? string.Empty : string.Empty;

            _csharpContexts[i] = context;
            _csharpReceivers[i] = receiver;
            checksum += context * 31 + receiver.Length * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceCompletionReceivers_QueryBatch() =>
        _nsharpCompletionReceiverChecksumInto(
            _prefixes,
            _nsharpContexts,
            _nsharpReceivers);

    private static string[] BuildPrefixes(int queryCount, CompilerLexerCorpus corpus)
    {
        var prefixes = new string[queryCount];
        var generated = CompilerLexerCorpusSources.Build(corpus).Split('\n');
        var seeds = new[]
        {
            "people.",
            "people.Add",
            "factory.Create(name).",
            "factory.Create(name, other.Value).Co",
            "System.Console.",
            "System.Collections.Generic.List.",
            "message.ToUpper().",
            "message.ToUpper().Len",
            "    \"abc\".",
            "    $\"hello {name}\".",
            "    \"a.b\".Len",
            "    \"unterminated.",
            "    true.",
            "    false.ToString().",
            "    42.",
            "    1.5.",
            "    0xCAFE.",
            "    'x'.",
            "    return people",
            "    name",
            "    call(value.withDot).",
            "    namespace.Type.Member",
            "    Console.WriteLine(factory.Create(name, other.Value)).",
            "    items.Where(item => item.Enabled).",
            "    résumé.Count"
        };

        for (var i = 0; i < queryCount; i++)
        {
            var seed = seeds[i % seeds.Length];
            if (i % 7 == 0)
            {
                var generatedLine = generated[i * 17 % generated.Length].TrimEnd();
                prefixes[i] = generatedLine.Length == 0
                    ? seed
                    : generatedLine + "." + seed.TrimStart();
                continue;
            }

            if (i % 11 == 0)
            {
                prefixes[i] = $"    builder{i}.Create(customer{i}, factory.Get({i})).";
                continue;
            }

            prefixes[i] = seed;
        }

        return prefixes;
    }

    private static string[] CreateEmptyStrings(int count)
    {
        var values = new string[count];
        Array.Fill(values, string.Empty);
        return values;
    }

    private static bool IsMemberAccessContext(string beforeCursor)
    {
        var trimmed = beforeCursor.TrimEnd();
        if (trimmed.EndsWith(".", StringComparison.Ordinal)) return true;

        var lastDot = trimmed.LastIndexOf('.');
        if (lastDot > 0)
        {
            var beforeDot = trimmed.Substring(0, lastDot).TrimEnd();
            if (beforeDot.Length > 0 && (char.IsLetterOrDigit(beforeDot[^1]) || beforeDot[^1] == '_'))
                return true;
        }

        return false;
    }

    private static string? ExtractReceiver(string beforeCursor)
    {
        var trimmed = beforeCursor.TrimEnd();
        var dotIndex = FindLastTopLevelDot(trimmed);
        if (dotIndex < 0) return null;

        var withoutDot = trimmed.Substring(0, dotIndex).TrimEnd();
        return ExtractExpressionSuffix(withoutDot);
    }

    private static string? ExtractExpressionSuffix(string text)
    {
        if (TryExtractLiteralExpressionSuffix(text, out var literalReceiver))
        {
            return literalReceiver;
        }

        var end = text.Length;
        var start = end - 1;
        var parenDepth = 0;
        var consumed = false;

        while (start >= 0)
        {
            var current = text[start];
            if (current == ')')
            {
                parenDepth++;
                consumed = true;
                start--;
                continue;
            }

            if (current == '(')
            {
                if (parenDepth == 0)
                {
                    break;
                }

                parenDepth--;
                start--;
                continue;
            }

            if (parenDepth > 0)
            {
                start--;
                continue;
            }

            if (char.IsLetterOrDigit(current) || current == '_' || current == '.')
            {
                consumed = true;
                start--;
                continue;
            }

            break;
        }

        if (!consumed || parenDepth != 0)
        {
            return null;
        }

        start++;
        return start < end ? NormalizeReceiverCalls(text[start..end]) : null;
    }

    private static bool TryExtractLiteralExpressionSuffix(string text, out string literalReceiver)
    {
        literalReceiver = string.Empty;
        var tokens = TokenizeCompletionPrefix(text);
        if (tokens.Count == 0 || !IsLiteralReceiverToken(tokens[^1].Type))
        {
            return false;
        }

        var token = tokens[^1];
        var tokenStart = Math.Clamp(token.Column - 1, 0, text.Length);
        literalReceiver = text[tokenStart..].Trim();
        if (literalReceiver.Length == 0)
        {
            literalReceiver = token.Value;
        }

        return IsCompleteLiteralReceiverToken(token, literalReceiver);
    }

    private static List<Token> TokenizeCompletionPrefix(string text)
    {
        try
        {
            return new Lexer(text, "<completion>")
                .Tokenize()
                .Where(token => token.Type is not TokenType.Eof
                    and not TokenType.Newline
                    and not TokenType.Comment
                    and not TokenType.MultiLineComment
                    and not TokenType.XmlDocComment)
                .ToList();
        }
        catch
        {
            return new List<Token>();
        }
    }

    private static bool IsLiteralReceiverToken(TokenType type)
        => type is TokenType.StringLiteral
            or TokenType.TripleQuoteStringLiteral
            or TokenType.InterpolatedRawStringLiteral
            or TokenType.CharLiteral
            or TokenType.IntLiteral
            or TokenType.FloatLiteral
            or TokenType.True
            or TokenType.False;

    private static bool IsCompleteLiteralReceiverToken(Token token, string sourceSuffix)
        => token.Type switch
        {
            TokenType.StringLiteral => token.IsTerminated,
            TokenType.TripleQuoteStringLiteral => token.IsTerminated && sourceSuffix.EndsWith("\"\"\"", StringComparison.Ordinal),
            TokenType.InterpolatedRawStringLiteral => token.IsTerminated,
            TokenType.CharLiteral => token.IsTerminated,
            _ => true
        };

    private static string NormalizeReceiverCalls(string expression)
    {
        var builder = new StringBuilder(expression.Length);
        for (var index = 0; index < expression.Length; index++)
        {
            var current = expression[index];
            builder.Append(current);
            if (current != '(')
            {
                continue;
            }

            var parenDepth = 1;
            index++;
            while (index < expression.Length && parenDepth > 0)
            {
                if (expression[index] == '(')
                {
                    parenDepth++;
                }
                else if (expression[index] == ')')
                {
                    parenDepth--;
                }

                index++;
            }

            builder.Append(')');
            index--;
        }

        return builder.ToString();
    }

    private static int FindLastTopLevelDot(string expression)
    {
        var parenDepth = 0;
        for (var index = expression.Length - 1; index >= 0; index--)
        {
            var current = expression[index];
            if (current == ')')
            {
                parenDepth++;
            }
            else if (current == '(')
            {
                parenDepth = Math.Max(0, parenDepth - 1);
            }
            else if (current == '.' && parenDepth == 0)
            {
                return index;
            }
        }

        return -1;
    }

    private static int FirstMismatch(
        int[] expectedContexts,
        string[] expectedReceivers,
        int[] actualContexts,
        string[] actualReceivers)
    {
        for (var i = 0; i < expectedContexts.Length; i++)
        {
            if (expectedContexts[i] != actualContexts[i]
                || !string.Equals(expectedReceivers[i], actualReceivers[i], StringComparison.Ordinal))
            {
                return i;
            }
        }

        return expectedContexts.Length;
    }

    private static string FormatContext(string? context) =>
        context == null ? "<null>" : $"\"{context}\"";
}

/// <summary>
/// Dogfood benchmark for grouping completion items by kind before CLI/daemon completion output.
///
/// The C# baseline mirrors the current member-completion shape: LINQ <c>GroupBy</c> over item kind
/// followed by <c>ToList</c> materialization for each public completion group. The N# candidate
/// runs after the host has assigned compact first-seen kind ids and writes group starts/counts and
/// stable source indices into caller-owned buffers.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceCompletionItemGroupingBenchmarks
{
    private const int LargeItemCount = 8192;
    private const int RepresentativeItemCount = 1024;

    private Func<int[], int[], int[], int[], int[], int[], int[], int> _nsharpCompletionItemKindGroupChecksum =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Dictionary<string, int> _itemIndices = new(StringComparer.Ordinal);
    private CompletionItem[] _items = Array.Empty<CompletionItem>();
    private Dictionary<string, int> _kindIds = new(StringComparer.Ordinal);
    private int[] _kindCounts = Array.Empty<int>();
    private int[] _kindIdsByItem = Array.Empty<int>();
    private int[] _kindOffsets = Array.Empty<int>();
    private int[] _nsharpResultCounts = Array.Empty<int>();
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _nsharpResultKindIds = Array.Empty<int>();
    private int[] _nsharpResultStarts = Array.Empty<int>();
    private int _itemCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _itemCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeItemCount
            : LargeItemCount;
        _nsharpCompletionItemKindGroupChecksum =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceCompletionGrouping,
                "CompletionItemKindGroupChecksumInto");

        _items = BuildItems(_itemCount);
        _kindIdsByItem = new int[_itemCount];
        _kindCounts = new int[_itemCount + 1];
        _kindOffsets = new int[_itemCount + 1];
        _nsharpResultKindIds = new int[_itemCount];
        _nsharpResultStarts = new int[_itemCount];
        _nsharpResultCounts = new int[_itemCount];
        _nsharpResultIndices = new int[_itemCount];

        BuildCompactKindIds();

        var expectedChecksum = CSharpCompletionItems_GroupByKind();
        var actualChecksum = NSharpCompletionItems_GroupByKind();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# completion item grouping checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        VerifyNSharpGroupsAgainstCSharp();
    }

    [Benchmark(Baseline = true)]
    public int CSharpCompletionItems_GroupByKind()
    {
        var completions = new Dictionary<string, List<CompletionItem>>();
        var groups = _items.GroupBy(static item => item.Kind).ToList();
        var checksum = groups.Count;
        var offset = 0;

        foreach (var group in groups)
        {
            var list = group.ToList();
            completions[Pluralize(group.Key)] = list;
            checksum += _kindIds[group.Key] * 97 + offset * 31 + list.Count * 17;

            for (var i = 0; i < list.Count; i++)
            {
                var sourceIndex = _itemIndices[list[i].Name];
                checksum += (sourceIndex + 1) * 13 + (i + 1) * 7;
            }

            offset += list.Count;
        }

        GC.KeepAlive(completions);
        return checksum;
    }

    [Benchmark]
    public int NSharpCompletionItems_GroupByKind() =>
        _nsharpCompletionItemKindGroupChecksum(
            _kindIdsByItem,
            _kindCounts,
            _kindOffsets,
            _nsharpResultKindIds,
            _nsharpResultStarts,
            _nsharpResultCounts,
            _nsharpResultIndices);

    private void BuildCompactKindIds()
    {
        _kindIds = new Dictionary<string, int>(StringComparer.Ordinal);
        _itemIndices = new Dictionary<string, int>(StringComparer.Ordinal);

        for (var i = 0; i < _items.Length; i++)
        {
            var item = _items[i];
            if (!_kindIds.TryGetValue(item.Kind, out var kindId))
            {
                kindId = _kindIds.Count + 1;
                _kindIds.Add(item.Kind, kindId);
            }

            _kindIdsByItem[i] = kindId;
            _itemIndices.Add(item.Name, i);
        }
    }

    private void VerifyNSharpGroupsAgainstCSharp()
    {
        var groups = _items.GroupBy(static item => item.Kind).ToList();
        if (_nsharpResultKindIds.Take(groups.Count).Any(id => id <= 0))
        {
            throw new InvalidOperationException($"N# completion item grouping returned invalid kind ids for {Corpus}.");
        }

        var offset = 0;
        for (var groupIndex = 0; groupIndex < groups.Count; groupIndex++)
        {
            var group = groups[groupIndex];
            var expected = group.ToList();
            if (_nsharpResultKindIds[groupIndex] != _kindIds[group.Key]
                || _nsharpResultStarts[groupIndex] != offset
                || _nsharpResultCounts[groupIndex] != expected.Count)
            {
                throw new InvalidOperationException(
                    $"N# completion item grouping segment mismatch for {Corpus} at group {groupIndex}.");
            }

            for (var i = 0; i < expected.Count; i++)
            {
                var expectedIndex = _itemIndices[expected[i].Name];
                var actualIndex = _nsharpResultIndices[offset + i];
                if (expectedIndex != actualIndex)
                {
                    throw new InvalidOperationException(
                        $"N# completion item grouping member mismatch for {Corpus} at group {groupIndex}, item {i}: " +
                        $"expected {expectedIndex}, got {actualIndex}.");
                }
            }

            offset += expected.Count;
        }
    }

    private static CompletionItem[] BuildItems(int count)
    {
        var names = new[]
        {
            "WriteLine",
            "Write",
            "ReadLine",
            "ToString",
            "ToUpper",
            "ToLower",
            "Length",
            "Count",
            "Capacity",
            "Chars",
            "Empty",
            "MaxValue",
            "MinValue",
            "Add",
            "Remove",
            "Contains",
            "IndexOf",
            "Substring"
        };
        var kinds = new[] { "method", "property", "method", "field", "property" };
        var items = new CompletionItem[count];

        for (var i = 0; i < count; i++)
        {
            var kind = kinds[(i * 7 + i / 13) % kinds.Length];
            var baseName = names[(i * 11 + i / 5) % names.Length];
            var type = kind switch
            {
                "method" => i % 3 == 0 ? "void" : "string",
                "property" => i % 2 == 0 ? "int" : "string",
                _ => i % 2 == 0 ? "bool" : "long"
            };
            var parameters = kind == "method" ? "(value string)" : null;
            items[i] = new CompletionItem(
                $"{baseName}{i}",
                kind,
                type,
                parameters,
                null,
                i % 17 == 0);
        }

        return items;
    }

    private static string Pluralize(string kind) => kind switch
    {
        "property" => "properties",
        "class" => "classes",
        _ => kind + "s"
    };
}

/// <summary>
/// Dogfood benchmark for leading doc-comment extraction used by hover documentation.
///
/// The current C# helper reads logical lines, walks backward from the declaration line, trims each
/// candidate line, strips leading slashes, and materializes the joined documentation string. The N#
/// candidate reuses cached line ranges and computes the same doc-line count and joined text length
/// without allocating intermediate line strings; the production adapter materializes only the final
/// hover documentation string.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDocCommentBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int> _nsharpBuildLineRangesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<string, int[], int[], int, int[], int[], int[], int> _nsharpDocCommentChecksumFromLinesInto =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpLineCounts = Array.Empty<int>();
    private int[] _csharpTextLengths = Array.Empty<int>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int[] _nsharpLineCounts = Array.Empty<int>();
    private int[] _nsharpTextLengths = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int _lineCount;
    private int _queryCount;
    private string _source = string.Empty;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus)
            + "\n// Adds two values\n"
            + "///   Returns the sum  \n"
            + "\n"
            + "func documentedAdd(left: int, right: int): int {\n"
            + "    return left + right\n"
            + "}\n"
            + "\n"
            + "///\n"
            + "func documentedEmpty(): int {\n"
            + "    return 0\n"
            + "}\n";
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpBuildLineRangesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "BuildCodeIntelligenceLineRangesInto");
        _nsharpDocCommentChecksumFromLinesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int, int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceDocCommentChecksumFromLinesInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _csharpLineCounts = new int[_queryCount];
        _csharpTextLengths = new int[_queryCount];
        _nsharpLineCounts = new int[_queryCount];
        _nsharpTextLengths = new int[_queryCount];

        BuildQueries();
        _lineCount = _nsharpBuildLineRangesInto(_source, _lineStarts, _lineLengths);

        var expectedChecksum = CSharpCodeIntelligenceDocComments_QueryBatch();
        var actualChecksum = NSharpCodeIntelligenceDocComments_CachedLineRanges_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# doc-comment checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpLineCounts.SequenceEqual(_nsharpLineCounts)
            || !_csharpTextLengths.SequenceEqual(_nsharpTextLengths))
        {
            var mismatch = FirstMismatch(_csharpLineCounts, _csharpTextLengths, _nsharpLineCounts, _nsharpTextLengths);
            throw new InvalidOperationException(
                $"N# doc-comment mismatch for {Corpus} at query {mismatch}: line {_queryLines[mismatch]}, " +
                $"expected {_csharpLineCounts[mismatch]}/{_csharpTextLengths[mismatch]}, " +
                $"got {_nsharpLineCounts[mismatch]}/{_nsharpTextLengths[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceDocComments_QueryBatch()
    {
        var checksum = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var documentation = ExtractDocComment(_source, _queryLines[i]);
            var lineCount = CountDocLines(documentation);
            var textLength = documentation?.Length ?? -1;
            _csharpLineCounts[i] = lineCount;
            _csharpTextLengths[i] = textLength;
            checksum += lineCount * 13 + textLength * 7;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceDocComments_CachedLineRanges_QueryBatch() =>
        _nsharpDocCommentChecksumFromLinesInto(
            _source,
            _lineStarts,
            _lineLengths,
            _lineCount,
            _queryLines,
            _nsharpLineCounts,
            _nsharpTextLengths);

    private void BuildQueries()
    {
        _queryLines = new int[_queryCount];

        var lines = _source.Split('\n');
        for (var i = 0; i < _queryCount; i++)
        {
            if (i % 37 == 0)
            {
                _queryLines[i] = i % 2 == 0 ? 0 : lines.Length + 1;
                continue;
            }

            _queryLines[i] = i * 17 % lines.Length + 1;
        }

        for (var i = 0; i < lines.Length; i++)
        {
            if (lines[i].Contains("func documentedAdd", StringComparison.Ordinal)
                || lines[i].Contains("func documentedEmpty", StringComparison.Ordinal))
            {
                _queryLines[i % _queryLines.Length] = i + 1;
            }
        }
    }

    private static string? ExtractDocComment(string source, int definitionLine)
    {
        try
        {
            if (definitionLine <= 1)
            {
                return null;
            }

            var lines = source.Split('\n');
            var commentLines = new List<string>();

            for (var i = definitionLine - 2; i >= 0; i--)
            {
                var trimmed = lines[i].Trim();
                if (trimmed.StartsWith("//", StringComparison.Ordinal))
                {
                    commentLines.Insert(0, trimmed.TrimStart('/').Trim());
                }
                else if (string.IsNullOrWhiteSpace(trimmed) && commentLines.Count == 0)
                {
                    continue;
                }
                else
                {
                    break;
                }
            }

            return commentLines.Count > 0 ? string.Join("\n", commentLines) : null;
        }
        catch
        {
            return null;
        }
    }

    private static int CountDocLines(string? documentation)
    {
        if (documentation == null)
        {
            return 0;
        }

        var count = 1;
        foreach (var current in documentation)
        {
            if (current == '\n')
            {
                count++;
            }
        }

        return count;
    }

    private static int FirstMismatch(int[] expectedStarts, int[] expectedLengths, int[] actualStarts, int[] actualLengths)
    {
        for (var i = 0; i < expectedStarts.Length; i++)
        {
            if (expectedStarts[i] != actualStarts[i] || expectedLengths[i] != actualLengths[i])
            {
                return i;
            }
        }

        return -1;
    }
}

/// <summary>
/// Dogfood benchmark for variable declaration name extraction used by type/definition query
/// candidate resolution on declaration lines.
///
/// The current C# helper splits the whole file for each queried line and allocates the declaration
/// name substring. The N# candidate builds a per-source declaration-name cache and writes cached
/// declaration-name column/length pairs into buffers, letting the production adapter materialize
/// only the requested name.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceVariableDeclarationBenchmarks
{
    private const int LargeQueryCount = 128;
    private const int RepresentativeQueryCount = 1024;

    private Func<string, int[], int[], int> _nsharpBuildLineRangesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<string, int[], int[], int, int[], int[], int> _nsharpBuildVariableDeclarationNameCacheInto =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private Func<int, int[], int[], int[], int[], int[], int> _nsharpVariableDeclarationNamesFromCacheInto =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpNameLengths = Array.Empty<int>();
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int[] _nameLengthsByLine = Array.Empty<int>();
    private int[] _nameStartsByLine = Array.Empty<int>();
    private int[] _nsharpNameLengths = Array.Empty<int>();
    private int[] _nsharpNameStarts = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private int _lineCount;
    private int _queryCount;
    private string _source = string.Empty;
    private string?[] _expectedNames = Array.Empty<string?>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = CompilerLexerCorpusSources.Build(Corpus) + """

func variableDeclarationProbe(customer: Customer, résumé: Profile) {
    value := customer.Name
	résumé_42 := résumé.Count
    customer.Name := "Ada"
    spaced    := 4
}
""";
        _queryCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeQueryCount
            : LargeQueryCount;
        _nsharpBuildLineRangesInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "BuildCodeIntelligenceLineRangesInto");
        _nsharpBuildVariableDeclarationNameCacheInto =
            NSharpCompiledMethod.Bind<Func<string, int[], int[], int, int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "BuildCodeIntelligenceVariableDeclarationNameCacheInto");
        _nsharpVariableDeclarationNamesFromCacheInto =
            NSharpCompiledMethod.Bind<Func<int, int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceIdentifierSpans,
                "CodeIntelligenceVariableDeclarationNamesFromCacheInto");

        _lineStarts = new int[_source.Length + 1];
        _lineLengths = new int[_source.Length + 1];
        _nameStartsByLine = new int[_source.Length + 1];
        _nameLengthsByLine = new int[_source.Length + 1];
        _csharpNameLengths = new int[_queryCount];
        _nsharpNameStarts = new int[_queryCount];
        _nsharpNameLengths = new int[_queryCount];

        BuildQueries();
        _lineCount = _nsharpBuildLineRangesInto(_source, _lineStarts, _lineLengths);
        _nsharpBuildVariableDeclarationNameCacheInto(
            _source,
            _lineStarts,
            _lineLengths,
            _lineCount,
            _nameStartsByLine,
            _nameLengthsByLine);

        _expectedNames = new string?[_queryLines.Length];
        for (var i = 0; i < _queryLines.Length; i++)
        {
            _expectedNames[i] = ExtractVariableDeclarationName(_source, _queryLines[i]);
        }

        var expectedCount = CSharpCodeIntelligenceVariableDeclarationNames_QueryBatch();
        var actualCount = NSharpCodeIntelligenceVariableDeclarationNames_Cached_QueryBatch();
        if (expectedCount != actualCount)
        {
            throw new InvalidOperationException(
                $"N# variable declaration name count mismatch for {Corpus}: expected {expectedCount}, got {actualCount}.");
        }

        var lines = _source.Split('\n');
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var line = _queryLines[i];
            var actual = _nsharpNameStarts[i] >= 0 && line >= 1 && line <= lines.Length
                ? lines[line - 1].Substring(_nsharpNameStarts[i] - 1, _nsharpNameLengths[i])
                : null;
            if (!string.Equals(_expectedNames[i], actual, StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    $"N# variable declaration name mismatch for {Corpus} at query {i}: line {line}, " +
                    $"expected {FormatContext(_expectedNames[i])}, got {FormatContext(actual)}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpCodeIntelligenceVariableDeclarationNames_QueryBatch()
    {
        var foundCount = 0;
        for (var i = 0; i < _queryLines.Length; i++)
        {
            var name = ExtractVariableDeclarationName(_source, _queryLines[i]);
            _csharpNameLengths[i] = name?.Length ?? -1;
            if (name != null)
            {
                foundCount++;
            }
        }

        return foundCount;
    }

    [Benchmark]
    public int NSharpCodeIntelligenceVariableDeclarationNames_Cached_QueryBatch() =>
        _nsharpVariableDeclarationNamesFromCacheInto(
            _lineCount,
            _nameStartsByLine,
            _nameLengthsByLine,
            _queryLines,
            _nsharpNameStarts,
            _nsharpNameLengths);

    private void BuildQueries()
    {
        _queryLines = new int[_queryCount];

        var lines = _source.Split('\n');
        var candidateLines = new List<int>();
        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            if (ExtractVariableDeclarationNameFromLine(lines[lineIndex]) != null)
            {
                candidateLines.Add(lineIndex + 1);
            }
        }

        if (candidateLines.Count == 0)
        {
            throw new InvalidOperationException($"No variable declaration candidates found for {Corpus}.");
        }

        for (var i = 0; i < _queryCount; i++)
        {
            if (i % 37 == 0)
            {
                _queryLines[i] = i % 2 == 0 ? 0 : lines.Length + 1;
                continue;
            }

            if (i % 11 == 0)
            {
                _queryLines[i] = i * 17 % lines.Length + 1;
                continue;
            }

            _queryLines[i] = candidateLines[i * 19 % candidateLines.Count];
        }
    }

    private static string? ExtractVariableDeclarationName(string source, int line)
    {
        var lines = source.Split('\n');
        return line <= 0 || line > lines.Length
            ? null
            : ExtractVariableDeclarationNameFromLine(lines[line - 1]);
    }

    private static string? ExtractVariableDeclarationNameFromLine(string lineText)
    {
        var assignIndex = lineText.IndexOf(":=", StringComparison.Ordinal);
        if (assignIndex <= 0)
        {
            return null;
        }

        var end = assignIndex - 1;
        while (end >= 0 && char.IsWhiteSpace(lineText[end]))
        {
            end--;
        }

        if (end < 0)
        {
            return null;
        }

        var start = end;
        while (start >= 0 && IsIdentifierChar(lineText[start]))
        {
            start--;
        }

        start++;
        return start <= end
            ? lineText.Substring(start, end - start + 1)
            : null;
    }

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';

    private static string FormatContext(string? context) =>
        context == null ? "<null>" : $"\"{context}\"";
}

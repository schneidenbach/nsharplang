using System;
using System.Collections.Generic;
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

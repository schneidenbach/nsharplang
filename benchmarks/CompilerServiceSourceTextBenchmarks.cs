using System;
using System.Linq;
using System.Text;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

internal delegate int NSharpLineMapTrustedCachedQueryChecksum(
    int[] starts,
    int lineCount,
    int[] offsetLineIndices,
    int[] offsets,
    int[] queryLines,
    int[] queryColumns);

/// <summary>
/// Dogfood benchmark for source text line splitting used by editor-facing fixes and diagnostics.
///
/// The current C# helper normalizes line endings through whole-source string replacements before
/// splitting. The N# candidate performs one pass and materializes only the returned line strings.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceSourceTextLineBenchmarks
{
    private Func<string, string[]> _nsharpSplitLogicalLines =
        _ => throw new InvalidOperationException("Benchmark not initialized.");
    private string _source = string.Empty;

    [Params(SourceTextLineCorpus.Representative, SourceTextLineCorpus.LargeMixedNewlines)]
    public SourceTextLineCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = SourceTextLineCorpusSources.Build(Corpus);
        _nsharpSplitLogicalLines = NSharpCompiledMethod.Bind<Func<string, string[]>>(
            DogfoodCompilerSources.SourceTextLines,
            "SplitLogicalLines");

        var expected = CSharpSourceTextLines_SplitLogicalLines();
        var actual = _nsharpSplitLogicalLines(_source);
        if (!expected.SequenceEqual(actual))
        {
            var mismatch = FirstMismatch(expected, actual);
            throw new InvalidOperationException(
                $"N# source line split mismatch for {Corpus} at index {mismatch}: " +
                $"expected {FormatLineAt(expected, mismatch)}, got {FormatLineAt(actual, mismatch)}.");
        }
    }

    [Benchmark(Baseline = true)]
    public string[] CSharpSourceTextLines_SplitLogicalLines() =>
        SourceTextLines.SplitLogicalLines(_source);

    [Benchmark]
    public string[] NSharpSourceTextLines_SplitLogicalLines() => _nsharpSplitLogicalLines(_source);

    private static int FirstMismatch(string[] expected, string[] actual)
    {
        var length = Math.Min(expected.Length, actual.Length);
        for (var i = 0; i < length; i++)
        {
            if (expected[i] != actual[i])
            {
                return i;
            }
        }

        return length;
    }

    private static string FormatLineAt(string[] lines, int index) =>
        index < lines.Length
            ? $"\"{lines[index]}\""
            : "<missing>";
}

/// <summary>
/// Source line benchmark for the lower-level range shape needed by line maps.
///
/// The C# baseline goes through the current production helper and copies line lengths into a
/// caller-owned buffer. The N# candidate writes source starts and line lengths directly, avoiding
/// line string materialization.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceSourceTextLineRangeBenchmarks
{
    private Func<string, int[], int[], int> _nsharpSplitLogicalLineRangesInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpLineLengths = Array.Empty<int>();
    private int[] _nsharpLineLengths = Array.Empty<int>();
    private int[] _nsharpLineStarts = Array.Empty<int>();
    private string[] _expectedLines = Array.Empty<string>();
    private string _source = string.Empty;

    [Params(SourceTextLineCorpus.Representative, SourceTextLineCorpus.LargeMixedNewlines)]
    public SourceTextLineCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = SourceTextLineCorpusSources.Build(Corpus);
        _nsharpSplitLogicalLineRangesInto = NSharpCompiledMethod.Bind<Func<string, int[], int[], int>>(
            DogfoodCompilerSources.SourceTextLines,
            "SplitLogicalLineRangesInto");
        _expectedLines = SourceTextLines.SplitLogicalLines(_source);
        _csharpLineLengths = new int[_expectedLines.Length];
        _nsharpLineStarts = new int[_source.Length + 1];
        _nsharpLineLengths = new int[_source.Length + 1];

        var csharpCount = CSharpSourceTextLines_WriteLengthsIntoBuffer();
        if (csharpCount != _expectedLines.Length)
        {
            throw new InvalidOperationException(
                $"C# source line length count mismatch for {Corpus}: expected {_expectedLines.Length}, got {csharpCount}.");
        }

        var nsharpCount = _nsharpSplitLogicalLineRangesInto(_source, _nsharpLineStarts, _nsharpLineLengths);
        VerifyRanges("N# source line ranges", _expectedLines, _source, _nsharpLineStarts, _nsharpLineLengths, nsharpCount, Corpus);
    }

    [Benchmark(Baseline = true)]
    public int CSharpSourceTextLines_WriteLengthsIntoBuffer()
    {
        var lines = SourceTextLines.SplitLogicalLines(_source);
        for (var i = 0; i < lines.Length; i++)
        {
            _csharpLineLengths[i] = lines[i].Length;
        }

        return lines.Length;
    }

    [Benchmark]
    public int NSharpSourceTextLines_WriteRangesIntoBuffer() =>
        _nsharpSplitLogicalLineRangesInto(_source, _nsharpLineStarts, _nsharpLineLengths);

    private static void VerifyRanges(
        string label,
        string[] expectedLines,
        string source,
        int[] starts,
        int[] lengths,
        int count,
        SourceTextLineCorpus corpus)
    {
        if (count != expectedLines.Length)
        {
            throw new InvalidOperationException(
                $"{label} count mismatch for {corpus}: expected {expectedLines.Length}, got {count}.");
        }

        for (var i = 0; i < count; i++)
        {
            var actual = source.Substring(starts[i], lengths[i]);
            if (expectedLines[i] != actual)
            {
                throw new InvalidOperationException(
                    $"{label} mismatch for {corpus} at index {i}: expected \"{expectedLines[i]}\", got \"{actual}\".");
            }
        }
    }
}

/// <summary>
/// Source line-map benchmark for diagnostics, fixes, query, and LSP position conversion.
///
/// The C# baseline starts from the current production split helper and then derives line starts and
/// line lengths. The N# path builds compact line ranges in caller-owned buffers and performs the
/// same offset and line/column query workload inside the compiled N# method.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceSourceTextLineMapBenchmarks
{
    private Func<string, int[], int[], int[], int[], int[], int[], int> _nsharpLineMapCachedChecksumInto =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _csharpLineLengths = Array.Empty<int>();
    private int[] _csharpLineStarts = Array.Empty<int>();
    private int[] _expectedLineLengths = Array.Empty<int>();
    private int[] _expectedLineStarts = Array.Empty<int>();
    private int[] _nsharpLineLengths = Array.Empty<int>();
    private int[] _nsharpLineStarts = Array.Empty<int>();
    private int[] _offsetQueries = Array.Empty<int>();
    private int[] _offsetLineIndices = Array.Empty<int>();
    private int[] _queryColumns = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private string[] _expectedLines = Array.Empty<string>();
    private string _source = string.Empty;

    [Params(SourceTextLineCorpus.Representative, SourceTextLineCorpus.LargeMixedNewlines)]
    public SourceTextLineCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = SourceTextLineCorpusSources.Build(Corpus);
        _nsharpLineMapCachedChecksumInto = NSharpCompiledMethod.Bind<Func<string, int[], int[], int[], int[], int[], int[], int>>(
            DogfoodCompilerSources.SourceTextLines,
            "LineMapCachedChecksumInto");

        var capacity = _source.Length + 1;
        _csharpLineStarts = new int[capacity];
        _csharpLineLengths = new int[capacity];
        _expectedLineStarts = new int[capacity];
        _expectedLineLengths = new int[capacity];
        _nsharpLineStarts = new int[capacity];
        _nsharpLineLengths = new int[capacity];
        _offsetLineIndices = new int[capacity];

        _expectedLines = SourceTextLines.SplitLogicalLines(_source);
        var expectedLineCount = FillLineStartsFromSource(_source, _expectedLineStarts);
        if (expectedLineCount != _expectedLines.Length)
        {
            throw new InvalidOperationException(
                $"Line-start count mismatch for {Corpus}: expected {_expectedLines.Length}, got {expectedLineCount}.");
        }

        for (var i = 0; i < _expectedLines.Length; i++)
        {
            _expectedLineLengths[i] = _expectedLines[i].Length;
        }

        BuildQueries(_expectedLineLengths, _expectedLines.Length);

        var expectedChecksum = CSharpSourceTextLineMap_BuildAndQuery();
        var actualChecksum = NSharpSourceTextLineMap_BuildAndQuery();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# source line-map checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpSourceTextLineMap_BuildAndQuery()
    {
        var lines = SourceTextLines.SplitLogicalLines(_source);
        var lineCount = FillLineStartsFromSource(_source, _csharpLineStarts);
        if (lineCount != lines.Length)
        {
            throw new InvalidOperationException(
                $"C# source line-map count mismatch for {Corpus}: expected {lines.Length}, got {lineCount}.");
        }

        for (var i = 0; i < lineCount; i++)
        {
            _csharpLineLengths[i] = lines[i].Length;
        }

        return LineMapChecksum(_csharpLineStarts, _csharpLineLengths, lineCount, _source.Length, _offsetQueries, _queryLines, _queryColumns);
    }

    [Benchmark]
    public int NSharpSourceTextLineMap_BuildAndQuery() =>
        _nsharpLineMapCachedChecksumInto(
            _source,
            _nsharpLineStarts,
            _nsharpLineLengths,
            _offsetLineIndices,
            _offsetQueries,
            _queryLines,
            _queryColumns);

    private void BuildQueries(int[] lengths, int lineCount)
    {
        const int QueryCount = 4096;
        _offsetQueries = new int[QueryCount];
        _queryLines = new int[QueryCount];
        _queryColumns = new int[QueryCount];

        var sourceExtent = Math.Max(1, _source.Length + 1);
        for (var i = 0; i < QueryCount; i++)
        {
            _offsetQueries[i] = i * 37 % sourceExtent;

            var lineIndex = i * 17 % lineCount;
            var lineLength = lengths[lineIndex];
            _queryLines[i] = lineIndex + 1;
            _queryColumns[i] = lineLength == 0
                ? 0
                : i * 31 % (lineLength + 1);
        }
    }

    private static int FillLineStartsFromSource(string source, int[] starts)
    {
        var sourceLength = source.Length;
        var position = 0;
        var count = 0;

        starts[count++] = 0;

        while (position < sourceLength)
        {
            var cr = source.IndexOf('\r', position);
            var lf = source.IndexOf('\n', position);
            if (cr < 0 && lf < 0)
            {
                break;
            }

            var separator = lf;
            var isCr = false;
            if (cr >= 0 && (lf < 0 || cr < lf))
            {
                separator = cr;
                isCr = true;
            }

            position = separator + 1;
            if (isCr && position < sourceLength && source[position] == '\n')
            {
                position++;
            }

            starts[count++] = position;
        }

        return count;
    }

    private static int LineMapChecksum(
        int[] starts,
        int[] lengths,
        int lineCount,
        int sourceLength,
        int[] offsets,
        int[] queryLines,
        int[] queryColumns)
    {
        var checksum = lineCount;
        for (var i = 0; i < offsets.Length; i++)
        {
            var offset = offsets[i];
            var lineIndex = GetLineIndexFromOffset(starts, lineCount, sourceLength, offset);
            var column = GetColumnFromOffset(starts, lineCount, sourceLength, offset);
            checksum += lineIndex * 31 + column;
        }

        for (var i = 0; i < queryLines.Length; i++)
        {
            var offset = GetOffsetFromLineColumn(starts, lengths, lineCount, sourceLength, queryLines[i], queryColumns[i]);
            checksum += offset * 17;
        }

        return checksum;
    }

    private static int GetLineIndexFromOffset(int[] starts, int lineCount, int sourceLength, int offset)
    {
        if (lineCount <= 0)
        {
            return 0;
        }

        offset = Math.Clamp(offset, 0, sourceLength);
        var low = 0;
        var high = lineCount - 1;
        var result = 0;

        while (low <= high)
        {
            var mid = (low + high) / 2;
            if (starts[mid] <= offset)
            {
                result = mid;
                low = mid + 1;
            }
            else
            {
                high = mid - 1;
            }
        }

        return result;
    }

    private static int GetColumnFromOffset(int[] starts, int lineCount, int sourceLength, int offset)
    {
        offset = Math.Clamp(offset, 0, sourceLength);
        var lineIndex = GetLineIndexFromOffset(starts, lineCount, sourceLength, offset);
        return offset - starts[lineIndex];
    }

    private static int GetOffsetFromLineColumn(
        int[] starts,
        int[] lengths,
        int lineCount,
        int sourceLength,
        int line,
        int column)
    {
        if (line < 1 || line > lineCount || column < 0)
        {
            return -1;
        }

        var index = line - 1;
        if (column > lengths[index])
        {
            return -1;
        }

        var offset = starts[index] + column;
        return offset <= sourceLength ? offset : -1;
    }
}

/// <summary>
/// Source line-map benchmark for the steady-state query path after a document line map has been
/// built once.
///
/// The C# baseline queries compact line starts with binary search. The N# path receives the same
/// line starts and lengths plus a caller-owned offset-to-line index and answers offset queries with
/// direct indexed lookup.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceSourceTextLineMapCachedQueryBenchmarks
{
    private Func<int[], int[], int, int, int[], int[], int[], int[], int> _nsharpLineMapCachedQueryChecksumInto =
        (_, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private NSharpLineMapTrustedCachedQueryChecksum _nsharpLineMapTrustedCachedQueryChecksumInto =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private int[] _lineLengths = Array.Empty<int>();
    private int[] _lineStarts = Array.Empty<int>();
    private int _lineCount;
    private int[] _offsetLineIndices = Array.Empty<int>();
    private int[] _offsetQueries = Array.Empty<int>();
    private int[] _queryColumns = Array.Empty<int>();
    private int[] _queryLines = Array.Empty<int>();
    private string _source = string.Empty;

    [Params(SourceTextLineCorpus.Representative, SourceTextLineCorpus.LargeMixedNewlines)]
    public SourceTextLineCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = SourceTextLineCorpusSources.Build(Corpus);
        _nsharpLineMapCachedQueryChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int, int, int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.SourceTextLines,
                "LineMapCachedQueryChecksumInto");
        _nsharpLineMapTrustedCachedQueryChecksumInto =
            NSharpCompiledMethod.Bind<NSharpLineMapTrustedCachedQueryChecksum>(
                DogfoodCompilerSources.SourceTextLines,
                "LineMapTrustedCachedQueryChecksumInto");

        var capacity = _source.Length + 1;
        _lineStarts = new int[capacity];
        _lineLengths = new int[capacity];
        _offsetLineIndices = new int[capacity];

        var lines = SourceTextLines.SplitLogicalLines(_source);
        _lineCount = FillLineStartsFromSource(_source, _lineStarts);
        if (_lineCount != lines.Length)
        {
            throw new InvalidOperationException(
                $"Line-start count mismatch for {Corpus}: expected {lines.Length}, got {_lineCount}.");
        }

        for (var i = 0; i < lines.Length; i++)
        {
            _lineLengths[i] = lines[i].Length;
        }

        BuildOffsetLineIndices(_lineStarts, _lineCount, _source.Length, _offsetLineIndices);
        BuildQueries(_lineLengths, _lineCount);

        var expectedChecksum = CSharpSourceTextLineMap_QueryCachedInputs();
        var actualChecksum = NSharpSourceTextLineMap_QueryCachedInputs();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# cached source line-map query checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var trustedExpectedChecksum = CSharpSourceTextLineMap_TrustedQueryCachedInputs();
        if (expectedChecksum != trustedExpectedChecksum)
        {
            throw new InvalidOperationException(
                $"Trusted C# cached source line-map query checksum mismatch for {Corpus}: expected {expectedChecksum}, got {trustedExpectedChecksum}.");
        }

        var trustedActualChecksum = NSharpSourceTextLineMap_TrustedQueryCachedInputs();
        if (trustedExpectedChecksum != trustedActualChecksum)
        {
            throw new InvalidOperationException(
                $"N# trusted cached source line-map query checksum mismatch for {Corpus}: expected {trustedExpectedChecksum}, got {trustedActualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpSourceTextLineMap_QueryCachedInputs() =>
        LineMapChecksum(_lineStarts, _lineLengths, _lineCount, _source.Length, _offsetQueries, _queryLines, _queryColumns);

    [Benchmark]
    public int NSharpSourceTextLineMap_QueryCachedInputs() =>
        _nsharpLineMapCachedQueryChecksumInto(
            _lineStarts,
            _lineLengths,
            _lineCount,
            _source.Length,
            _offsetLineIndices,
            _offsetQueries,
            _queryLines,
            _queryColumns);

    [Benchmark]
    public int CSharpSourceTextLineMap_TrustedQueryCachedInputs() =>
        TrustedLineMapChecksum(_lineStarts, _lineCount, _offsetQueries, _queryLines, _queryColumns);

    [Benchmark]
    public int NSharpSourceTextLineMap_TrustedQueryCachedInputs() =>
        _nsharpLineMapTrustedCachedQueryChecksumInto(
            _lineStarts,
            _lineCount,
            _offsetLineIndices,
            _offsetQueries,
            _queryLines,
            _queryColumns);

    private void BuildQueries(int[] lengths, int lineCount)
    {
        const int QueryCount = 4096;
        _offsetQueries = new int[QueryCount];
        _queryLines = new int[QueryCount];
        _queryColumns = new int[QueryCount];

        var sourceExtent = Math.Max(1, _source.Length + 1);
        for (var i = 0; i < QueryCount; i++)
        {
            _offsetQueries[i] = i * 37 % sourceExtent;

            var lineIndex = i * 17 % lineCount;
            var lineLength = lengths[lineIndex];
            _queryLines[i] = lineIndex + 1;
            _queryColumns[i] = lineLength == 0
                ? 0
                : i * 31 % (lineLength + 1);
        }
    }

    private static int FillLineStartsFromSource(string source, int[] starts)
    {
        var sourceLength = source.Length;
        var position = 0;
        var count = 0;

        starts[count++] = 0;

        while (position < sourceLength)
        {
            var cr = source.IndexOf('\r', position);
            var lf = source.IndexOf('\n', position);
            if (cr < 0 && lf < 0)
            {
                break;
            }

            var separator = lf;
            var isCr = false;
            if (cr >= 0 && (lf < 0 || cr < lf))
            {
                separator = cr;
                isCr = true;
            }

            position = separator + 1;
            if (isCr && position < sourceLength && source[position] == '\n')
            {
                position++;
            }

            starts[count++] = position;
        }

        return count;
    }

    private static void BuildOffsetLineIndices(int[] starts, int lineCount, int sourceLength, int[] offsetLineIndices)
    {
        for (var lineIndex = 0; lineIndex < lineCount; lineIndex++)
        {
            var lineStart = starts[lineIndex];
            var endExclusive = lineIndex + 1 < lineCount ? starts[lineIndex + 1] : sourceLength + 1;
            for (var offset = lineStart; offset < endExclusive && offset <= sourceLength; offset++)
            {
                offsetLineIndices[offset] = lineIndex;
            }
        }
    }

    private static int LineMapChecksum(
        int[] starts,
        int[] lengths,
        int lineCount,
        int sourceLength,
        int[] offsets,
        int[] queryLines,
        int[] queryColumns)
    {
        var checksum = lineCount;
        for (var i = 0; i < offsets.Length; i++)
        {
            var offset = offsets[i];
            var lineIndex = GetLineIndexFromOffset(starts, lineCount, sourceLength, offset);
            var column = GetColumnFromOffset(starts, lineCount, sourceLength, offset);
            checksum += lineIndex * 31 + column;
        }

        for (var i = 0; i < queryLines.Length; i++)
        {
            var offset = GetOffsetFromLineColumn(starts, lengths, lineCount, sourceLength, queryLines[i], queryColumns[i]);
            checksum += offset * 17;
        }

        return checksum;
    }

    private static int TrustedLineMapChecksum(
        int[] starts,
        int lineCount,
        int[] offsets,
        int[] queryLines,
        int[] queryColumns)
    {
        var checksum = lineCount;
        for (var i = 0; i < offsets.Length; i++)
        {
            var offset = offsets[i];
            var lineIndex = GetLineIndexFromOffsetTrusted(starts, lineCount, offset);
            var column = offset - starts[lineIndex];
            checksum += lineIndex * 31 + column;
        }

        for (var i = 0; i < queryLines.Length; i++)
        {
            var offset = starts[queryLines[i] - 1] + queryColumns[i];
            checksum += offset * 17;
        }

        return checksum;
    }

    private static int GetLineIndexFromOffsetTrusted(int[] starts, int lineCount, int offset)
    {
        var low = 0;
        var high = lineCount - 1;
        var result = 0;

        while (low <= high)
        {
            var mid = (low + high) / 2;
            if (starts[mid] <= offset)
            {
                result = mid;
                low = mid + 1;
            }
            else
            {
                high = mid - 1;
            }
        }

        return result;
    }

    private static int GetLineIndexFromOffset(int[] starts, int lineCount, int sourceLength, int offset)
    {
        if (lineCount <= 0)
        {
            return 0;
        }

        offset = Math.Clamp(offset, 0, sourceLength);
        var low = 0;
        var high = lineCount - 1;
        var result = 0;

        while (low <= high)
        {
            var mid = (low + high) / 2;
            if (starts[mid] <= offset)
            {
                result = mid;
                low = mid + 1;
            }
            else
            {
                high = mid - 1;
            }
        }

        return result;
    }

    private static int GetColumnFromOffset(int[] starts, int lineCount, int sourceLength, int offset)
    {
        offset = Math.Clamp(offset, 0, sourceLength);
        var lineIndex = GetLineIndexFromOffset(starts, lineCount, sourceLength, offset);
        return offset - starts[lineIndex];
    }

    private static int GetOffsetFromLineColumn(
        int[] starts,
        int[] lengths,
        int lineCount,
        int sourceLength,
        int line,
        int column)
    {
        if (line < 1 || line > lineCount || column < 0)
        {
            return -1;
        }

        var index = line - 1;
        if (column > lengths[index])
        {
            return -1;
        }

        var offset = starts[index] + column;
        return offset <= sourceLength ? offset : -1;
    }
}

internal static class SourceTextLineCorpusSources
{
    public static string Build(SourceTextLineCorpus corpus) => corpus switch
    {
        SourceTextLineCorpus.Representative => BuildRepresentativeCorpus(),
        SourceTextLineCorpus.LargeMixedNewlines => BuildLargeMixedNewlineCorpus(),
        _ => throw new InvalidOperationException($"Unknown source text line corpus: {corpus}")
    };

    private static string BuildRepresentativeCorpus()
    {
        var builder = new StringBuilder(capacity: 8 * 1024);
        builder.Append("import System\r\n");
        builder.Append("package CompilerDogfood.SourceText\n");
        builder.Append("\r");
        builder.Append("func main() {\r\n");
        builder.Append("    message := \"hello\"\n");
        builder.Append("    print message\r");
        builder.Append("}\n");
        builder.Append("\r\n");
        return builder.ToString();
    }

    private static string BuildLargeMixedNewlineCorpus()
    {
        var builder = new StringBuilder(capacity: 512 * 1024);
        for (var i = 0; i < 10_000; i++)
        {
            builder.Append("line ");
            builder.Append(i);
            builder.Append(": ");
            builder.Append("alpha beta gamma delta epsilon");

            if (i % 5 == 0)
            {
                builder.Append("\r\n");
            }
            else if (i % 5 == 1)
            {
                builder.Append('\n');
            }
            else if (i % 5 == 2)
            {
                builder.Append('\r');
            }
            else if (i % 5 == 3)
            {
                builder.Append("\r\n\r");
            }
            else
            {
                builder.Append("\n\n");
            }
        }

        return builder.ToString();
    }
}

public enum SourceTextLineCorpus
{
    Representative,
    LargeMixedNewlines
}

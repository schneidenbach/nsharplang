using System;
using System.Linq;
using System.Text;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

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

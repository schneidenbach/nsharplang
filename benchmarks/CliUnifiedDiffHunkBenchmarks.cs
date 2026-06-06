using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for <c>nlc format --diff</c> hunk construction after line diffing.
/// The C# baseline mirrors the current LINQ-shaped <c>UnifiedDiff.BuildHunks</c> helper.
/// The N# candidate writes hunk ranges and line counts into caller-owned buffers; the host then
/// renders/checksums directly from the source diff lines instead of materializing hunk slices.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CliUnifiedDiffHunkBenchmarks
{
    private const int ContextLines = 3;
    private const int LargeLineCount = 8192;
    private const int RepresentativeLineCount = 1024;

    private Func<int[], int[], int[], int, int[], int[], int[], int[], int[], int[], int> _nsharpCliUnifiedDiffHunkRangesInto =
        (_, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private BenchmarkDiffLine[] _lines = Array.Empty<BenchmarkDiffLine>();
    private int[] _kindIds = Array.Empty<int>();
    private int[] _newLines = Array.Empty<int>();
    private int[] _oldLines = Array.Empty<int>();
    private int[] _resultLengths = Array.Empty<int>();
    private int[] _resultNewCounts = Array.Empty<int>();
    private int[] _resultNewStarts = Array.Empty<int>();
    private int[] _resultOldCounts = Array.Empty<int>();
    private int[] _resultOldStarts = Array.Empty<int>();
    private int[] _resultStarts = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpCliUnifiedDiffHunkRangesInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int, int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CliArguments,
                "CliUnifiedDiffHunkRangesInto");

        var lineCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeLineCount
            : LargeLineCount;

        _lines = BuildLines(lineCount);
        _kindIds = new int[lineCount];
        _oldLines = new int[lineCount];
        _newLines = new int[lineCount];
        _resultStarts = new int[lineCount];
        _resultLengths = new int[lineCount];
        _resultOldStarts = new int[lineCount];
        _resultOldCounts = new int[lineCount];
        _resultNewStarts = new int[lineCount];
        _resultNewCounts = new int[lineCount];

        for (var i = 0; i < lineCount; i++)
        {
            _kindIds[i] = (int)_lines[i].Kind;
            _oldLines[i] = _lines[i].OldLine;
            _newLines[i] = _lines[i].NewLine;
        }

        var csharp = CSharpUnifiedDiffHunks_BuildHunks();
        var nsharp = NSharpUnifiedDiffHunkRanges_RenderDirectly();
        if (csharp != nsharp)
        {
            throw new InvalidOperationException(
                $"N# unified-diff hunk checksum mismatch for {Corpus}: expected {csharp}, got {nsharp}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpUnifiedDiffHunks_BuildHunks()
    {
        var changedIndices = _lines
            .Select(static (line, index) => (line, index))
            .Where(static item => item.line.Kind != BenchmarkDiffKind.Equal)
            .Select(static item => item.index)
            .ToArray();

        if (changedIndices.Length == 0)
            return 0;

        var ranges = new List<(int Start, int End)>();
        var rangeStart = Math.Max(0, changedIndices[0] - ContextLines);
        var rangeEnd = Math.Min(_lines.Length - 1, changedIndices[0] + ContextLines);

        foreach (var changedIndex in changedIndices.Skip(1))
        {
            var nextStart = Math.Max(0, changedIndex - ContextLines);
            var nextEnd = Math.Min(_lines.Length - 1, changedIndex + ContextLines);

            if (nextStart <= rangeEnd + 1)
            {
                rangeEnd = Math.Max(rangeEnd, nextEnd);
                continue;
            }

            ranges.Add((rangeStart, rangeEnd));
            rangeStart = nextStart;
            rangeEnd = nextEnd;
        }

        ranges.Add((rangeStart, rangeEnd));

        var hunks = ranges
            .Select(range =>
            {
                var slice = _lines.Skip(range.Start).Take(range.End - range.Start + 1).ToArray();
                var oldStart = slice.FirstOrDefault(static line => line.OldLine > 0).OldLine;
                var newStart = slice.FirstOrDefault(static line => line.NewLine > 0).NewLine;
                if (oldStart == 0)
                    oldStart = 1;
                if (newStart == 0)
                    newStart = 1;

                var oldCount = slice.Count(static line => line.Kind != BenchmarkDiffKind.Added);
                var newCount = slice.Count(static line => line.Kind != BenchmarkDiffKind.Removed);
                return new BenchmarkHunk(slice, oldStart, oldCount, newStart, newCount);
            })
            .ToList();

        return ChecksumHunks(hunks);
    }

    [Benchmark]
    public int NSharpUnifiedDiffHunkRanges_RenderDirectly()
    {
        var hunkCount = _nsharpCliUnifiedDiffHunkRangesInto(
            _kindIds,
            _oldLines,
            _newLines,
            ContextLines,
            _resultStarts,
            _resultLengths,
            _resultOldStarts,
            _resultOldCounts,
            _resultNewStarts,
            _resultNewCounts);

        if (hunkCount < 0 || hunkCount > _lines.Length)
            throw new InvalidOperationException($"N# unified-diff hunk count out of range: {hunkCount}.");

        return ChecksumRanges(hunkCount);
    }

    private static BenchmarkDiffLine[] BuildLines(int count)
    {
        var lines = new BenchmarkDiffLine[count];
        var oldLine = 1;
        var newLine = 1;
        for (var i = 0; i < count; i++)
        {
            var kind = (i % 97) switch
            {
                0 => BenchmarkDiffKind.Removed,
                1 => BenchmarkDiffKind.Added,
                2 => BenchmarkDiffKind.Added,
                41 => BenchmarkDiffKind.Removed,
                42 => BenchmarkDiffKind.Removed,
                43 => BenchmarkDiffKind.Added,
                73 => BenchmarkDiffKind.Added,
                _ => BenchmarkDiffKind.Equal
            };

            var old = kind == BenchmarkDiffKind.Added ? oldLine : oldLine++;
            var @new = kind == BenchmarkDiffKind.Removed ? newLine : newLine++;
            lines[i] = new BenchmarkDiffLine(kind, $"line {i}", old, @new);
        }

        return lines;
    }

    private static int ChecksumHunks(IReadOnlyList<BenchmarkHunk> hunks)
    {
        var checksum = hunks.Count;
        for (var hunkIndex = 0; hunkIndex < hunks.Count; hunkIndex++)
        {
            var hunk = hunks[hunkIndex];
            checksum += (hunkIndex + 1) * 97
                + hunk.OldStart * 31
                + hunk.OldCount * 17
                + hunk.NewStart * 13
                + hunk.NewCount * 11
                + hunk.Lines.Length * 7;

            for (var i = 0; i < hunk.Lines.Length; i++)
            {
                var line = hunk.Lines[i];
                checksum += ((int)line.Kind + 1) * 5 + line.OldLine * 3 + line.NewLine;
            }
        }

        return checksum;
    }

    private int ChecksumRanges(int hunkCount)
    {
        var checksum = hunkCount;
        for (var hunkIndex = 0; hunkIndex < hunkCount; hunkIndex++)
        {
            var start = _resultStarts[hunkIndex];
            var length = _resultLengths[hunkIndex];
            if (start < 0 || length < 0 || start + length > _lines.Length)
                throw new InvalidOperationException($"N# unified-diff hunk range out of bounds: {start}+{length}.");

            checksum += (hunkIndex + 1) * 97
                + _resultOldStarts[hunkIndex] * 31
                + _resultOldCounts[hunkIndex] * 17
                + _resultNewStarts[hunkIndex] * 13
                + _resultNewCounts[hunkIndex] * 11
                + length * 7;

            var end = start + length;
            for (var i = start; i < end; i++)
            {
                var line = _lines[i];
                checksum += ((int)line.Kind + 1) * 5 + line.OldLine * 3 + line.NewLine;
            }
        }

        return checksum;
    }

    private enum BenchmarkDiffKind
    {
        Equal = 0,
        Added = 1,
        Removed = 2
    }

    private readonly record struct BenchmarkDiffLine(BenchmarkDiffKind Kind, string Text, int OldLine, int NewLine);

    private sealed record BenchmarkHunk(
        BenchmarkDiffLine[] Lines,
        int OldStart,
        int OldCount,
        int NewStart,
        int NewCount);
}

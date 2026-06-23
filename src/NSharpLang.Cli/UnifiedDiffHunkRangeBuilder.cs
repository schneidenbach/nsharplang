using System;
using System.Collections.Generic;

namespace NSharpLang.Cli;

internal static class UnifiedDiffHunkRangeBuilder
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static UnifiedDiff.HunkRanges Build(
        IReadOnlyList<UnifiedDiff.DiffLine> lines,
        int contextLines)
    {
        if (contextLines < 0)
            throw new ArgumentOutOfRangeException(nameof(contextLines), "Context line count must be non-negative.");

        var bindings = RequiredBindings;
        var lineCount = lines.Count;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(lineCount);

        for (var i = 0; i < lineCount; i++)
        {
            var line = lines[i];
            scratch.KindIds[i] = (int)line.Kind;
            scratch.OldLines[i] = line.OldLine;
            scratch.NewLines[i] = line.NewLine;
        }

        var hunkCount = bindings.HunkRanges(
            scratch.KindIds,
            scratch.OldLines,
            scratch.NewLines,
            contextLines,
            scratch.Ranges.Starts,
            scratch.Ranges.Lengths,
            scratch.Ranges.OldStarts,
            scratch.Ranges.OldCounts,
            scratch.Ranges.NewStarts,
            scratch.Ranges.NewCounts);

        if (hunkCount < 0 || hunkCount > lineCount)
            throw new InvalidOperationException("N# unified diff hunk range kernel returned an invalid hunk count.");

        for (var hunkIndex = 0; hunkIndex < hunkCount; hunkIndex++)
        {
            var start = scratch.Ranges.Starts[hunkIndex];
            var length = scratch.Ranges.Lengths[hunkIndex];
            if (start < 0 ||
                length <= 0 ||
                start + length > lineCount ||
                scratch.Ranges.OldStarts[hunkIndex] <= 0 ||
                scratch.Ranges.NewStarts[hunkIndex] <= 0 ||
                scratch.Ranges.OldCounts[hunkIndex] < 0 ||
                scratch.Ranges.NewCounts[hunkIndex] < 0 ||
                scratch.Ranges.OldCounts[hunkIndex] > length ||
                scratch.Ranges.NewCounts[hunkIndex] > length)
            {
                throw new InvalidOperationException("N# unified diff hunk range kernel returned an invalid hunk range.");
            }
        }

        scratch.Ranges.Count = hunkCount;
        return scratch.Ranges;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliUnifiedDiffHunkRangesInto>(
                programType,
                "CliUnifiedDiffHunkRangesInto")));

    private static Bindings RequiredBindings
        => s_bindings.Value
            ?? throw new InvalidOperationException("N# unified diff hunk range kernels are unavailable.");

    private delegate int CliUnifiedDiffHunkRangesInto(
        int[] kindIds,
        int[] oldLines,
        int[] newLines,
        int contextLines,
        int[] resultStarts,
        int[] resultLengths,
        int[] resultOldStarts,
        int[] resultOldCounts,
        int[] resultNewStarts,
        int[] resultNewCounts);

    private sealed record Bindings(CliUnifiedDiffHunkRangesInto HunkRanges);

    private sealed class Scratch
    {
        internal int[] KindIds = Array.Empty<int>();
        internal int[] NewLines = Array.Empty<int>();
        internal int[] OldLines = Array.Empty<int>();
        internal UnifiedDiff.HunkRanges Ranges { get; } = new();

        internal void EnsureCapacity(int lineCount)
        {
            if (KindIds.Length == lineCount)
            {
                Ranges.Count = 0;
                return;
            }

            KindIds = new int[lineCount];
            OldLines = new int[lineCount];
            NewLines = new int[lineCount];
            Ranges.Starts = new int[lineCount];
            Ranges.Lengths = new int[lineCount];
            Ranges.OldStarts = new int[lineCount];
            Ranges.OldCounts = new int[lineCount];
            Ranges.NewStarts = new int[lineCount];
            Ranges.NewCounts = new int[lineCount];
            Ranges.Count = 0;
        }
    }
}

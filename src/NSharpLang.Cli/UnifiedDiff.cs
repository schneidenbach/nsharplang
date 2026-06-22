using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace NSharpLang.Cli;

internal static class UnifiedDiff
{
    internal enum DiffKind
    {
        Equal,
        Added,
        Removed
    }

    internal readonly record struct DiffLine(DiffKind Kind, string Text, int OldLine, int NewLine);
    private readonly record struct Hunk(IReadOnlyList<DiffLine> Lines, int OldStart, int OldCount, int NewStart, int NewCount);

    internal sealed class HunkRanges
    {
        internal static readonly HunkRanges Empty = new();

        internal int Count { get; set; }
        internal int[] Starts { get; set; } = Array.Empty<int>();
        internal int[] Lengths { get; set; } = Array.Empty<int>();
        internal int[] OldStarts { get; set; } = Array.Empty<int>();
        internal int[] OldCounts { get; set; } = Array.Empty<int>();
        internal int[] NewStarts { get; set; } = Array.Empty<int>();
        internal int[] NewCounts { get; set; } = Array.Empty<int>();
    }

    public static string Create(string before, string after, string beforeLabel, string afterLabel, int contextLines = 3)
    {
        if (string.Equals(before, after, StringComparison.Ordinal))
            return string.Empty;

        var diffLines = Diff(before, after);

        var sb = new StringBuilder();
        sb.AppendLine(UnifiedDiffTextKernels.GetBeforeHeaderText(beforeLabel));
        sb.AppendLine(UnifiedDiffTextKernels.GetAfterHeaderText(afterLabel));

        if (UnifiedDiffHunkRangeBuilder.TryBuild(diffLines, contextLines, out var ranges))
        {
            AppendHunks(sb, diffLines, ranges);
            return sb.ToString();
        }

        foreach (var hunk in BuildHunks(diffLines, contextLines))
        {
            AppendHunk(sb, hunk);
        }

        return sb.ToString();
    }

    private static List<DiffLine> Diff(string before, string after)
    {
        var oldLines = SplitLines(before);
        var newLines = SplitLines(after);
        var lcs = new int[oldLines.Length + 1, newLines.Length + 1];

        for (var i = oldLines.Length - 1; i >= 0; i--)
        {
            for (var j = newLines.Length - 1; j >= 0; j--)
            {
                lcs[i, j] = string.Equals(oldLines[i], newLines[j], StringComparison.Ordinal)
                    ? lcs[i + 1, j + 1] + 1
                    : Math.Max(lcs[i + 1, j], lcs[i, j + 1]);
            }
        }

        var result = new List<DiffLine>();
        var oldIndex = 0;
        var newIndex = 0;

        while (oldIndex < oldLines.Length && newIndex < newLines.Length)
        {
            if (string.Equals(oldLines[oldIndex], newLines[newIndex], StringComparison.Ordinal))
            {
                result.Add(new DiffLine(DiffKind.Equal, oldLines[oldIndex], oldIndex + 1, newIndex + 1));
                oldIndex++;
                newIndex++;
            }
            else if (lcs[oldIndex + 1, newIndex] >= lcs[oldIndex, newIndex + 1])
            {
                result.Add(new DiffLine(DiffKind.Removed, oldLines[oldIndex], oldIndex + 1, newIndex + 1));
                oldIndex++;
            }
            else
            {
                result.Add(new DiffLine(DiffKind.Added, newLines[newIndex], oldIndex + 1, newIndex + 1));
                newIndex++;
            }
        }

        while (oldIndex < oldLines.Length)
        {
            result.Add(new DiffLine(DiffKind.Removed, oldLines[oldIndex], oldIndex + 1, newIndex + 1));
            oldIndex++;
        }

        while (newIndex < newLines.Length)
        {
            result.Add(new DiffLine(DiffKind.Added, newLines[newIndex], oldIndex + 1, newIndex + 1));
            newIndex++;
        }

        return result;
    }

    private static List<Hunk> BuildHunks(IReadOnlyList<DiffLine> lines, int contextLines)
    {
        var changedIndices = lines
            .Select((line, index) => (line, index))
            .Where(item => item.line.Kind != DiffKind.Equal)
            .Select(item => item.index)
            .ToArray();

        if (changedIndices.Length == 0)
            return new List<Hunk>();

        var ranges = new List<(int Start, int End)>();
        var rangeStart = Math.Max(0, changedIndices[0] - contextLines);
        var rangeEnd = Math.Min(lines.Count - 1, changedIndices[0] + contextLines);

        foreach (var changedIndex in changedIndices.Skip(1))
        {
            var nextStart = Math.Max(0, changedIndex - contextLines);
            var nextEnd = Math.Min(lines.Count - 1, changedIndex + contextLines);

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

        return ranges
            .Select(range =>
            {
                var slice = lines.Skip(range.Start).Take(range.End - range.Start + 1).ToArray();
                var oldStart = slice.FirstOrDefault(line => line.OldLine > 0).OldLine;
                var newStart = slice.FirstOrDefault(line => line.NewLine > 0).NewLine;
                if (oldStart == 0)
                    oldStart = 1;
                if (newStart == 0)
                    newStart = 1;

                var oldCount = slice.Count(line => line.Kind != DiffKind.Added);
                var newCount = slice.Count(line => line.Kind != DiffKind.Removed);
                return new Hunk(slice, oldStart, oldCount, newStart, newCount);
            })
            .ToList();
    }

    private static void AppendHunks(
        StringBuilder sb,
        IReadOnlyList<DiffLine> lines,
        HunkRanges ranges)
    {
        for (var hunkIndex = 0; hunkIndex < ranges.Count; hunkIndex++)
        {
            sb.AppendLine(UnifiedDiffTextKernels.GetHunkHeaderText(
                ranges.OldStarts[hunkIndex],
                ranges.OldCounts[hunkIndex],
                ranges.NewStarts[hunkIndex],
                ranges.NewCounts[hunkIndex]));

            var start = ranges.Starts[hunkIndex];
            var end = start + ranges.Lengths[hunkIndex];
            for (var lineIndex = start; lineIndex < end; lineIndex++)
            {
                AppendLine(sb, lines[lineIndex]);
            }
        }
    }

    private static void AppendHunk(StringBuilder sb, Hunk hunk)
    {
        sb.AppendLine(UnifiedDiffTextKernels.GetHunkHeaderText(
            hunk.OldStart,
            hunk.OldCount,
            hunk.NewStart,
            hunk.NewCount));
        foreach (var line in hunk.Lines)
        {
            AppendLine(sb, line);
        }
    }

    private static void AppendLine(StringBuilder sb, DiffLine line)
    {
        sb.Append(UnifiedDiffTextKernels.GetLinePrefixText(line.Kind));
        sb.AppendLine(line.Text);
    }

    private static string[] SplitLines(string text)
    {
        var normalized = text.Replace("\r\n", "\n", StringComparison.Ordinal);
        return normalized.Split('\n');
    }
}

using System;
using System.Collections.Generic;
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

        var ranges = UnifiedDiffHunkRangeBuilder.Build(diffLines, contextLines);
        AppendHunks(sb, diffLines, ranges);

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

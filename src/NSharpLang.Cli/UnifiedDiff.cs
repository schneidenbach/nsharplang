using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace NSharpLang.Cli;

internal static class UnifiedDiff
{
    private enum DiffKind
    {
        Equal,
        Added,
        Removed
    }

    private readonly record struct DiffLine(DiffKind Kind, string Text, int OldLine, int NewLine);
    private readonly record struct Hunk(IReadOnlyList<DiffLine> Lines, int OldStart, int OldCount, int NewStart, int NewCount);

    public static string Create(string before, string after, string beforeLabel, string afterLabel, int contextLines = 3)
    {
        if (string.Equals(before, after, StringComparison.Ordinal))
            return string.Empty;

        var diffLines = Diff(before, after);
        var hunks = BuildHunks(diffLines, contextLines);

        var sb = new StringBuilder();
        sb.AppendLine($"--- {beforeLabel}");
        sb.AppendLine($"+++ {afterLabel}");

        foreach (var hunk in hunks)
        {
            sb.AppendLine($"@@ -{hunk.OldStart},{hunk.OldCount} +{hunk.NewStart},{hunk.NewCount} @@");
            foreach (var line in hunk.Lines)
            {
                var prefix = line.Kind switch
                {
                    DiffKind.Added => '+',
                    DiffKind.Removed => '-',
                    _ => ' '
                };

                sb.Append(prefix);
                sb.AppendLine(line.Text);
            }
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

    private static string[] SplitLines(string text)
    {
        var normalized = text.Replace("\r\n", "\n", StringComparison.Ordinal);
        return normalized.Split('\n');
    }
}

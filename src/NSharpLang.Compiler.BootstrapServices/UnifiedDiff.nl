namespace NSharpLang.Cli

import System
import System.Text

class UnifiedDiffLineTable {
    Kinds: int[]
    Texts: string[]
    OldLines: int[]
    NewLines: int[]
    Count: int
}

class UnifiedDiffHunkRangeTable {
    Starts: int[]
    Lengths: int[]
    OldStarts: int[]
    OldCounts: int[]
    NewStarts: int[]
    NewCounts: int[]
    Count: int
}

public class UnifiedDiff {
    public static func Create(before: string, after: string, beforeLabel: string, afterLabel: string, contextLines: int = 3): string {
        if String.Compare(before, after, StringComparison.Ordinal) == 0 {
            return ""
        }

        if contextLines < 0 {
            throw new ArgumentOutOfRangeException("contextLines", "Context line count must be non-negative.")
        }

        diffLines := Diff(before, after)
        ranges := BuildHunkRanges(diffLines, contextLines)

        builder := new StringBuilder()
        builder.AppendLine(BeforeHeaderText(beforeLabel))
        builder.AppendLine(AfterHeaderText(afterLabel))
        AppendHunks(builder, diffLines, ranges)
        return builder.ToString()
    }

    static func Diff(before: string, after: string): UnifiedDiffLineTable {
        oldLines := SplitLines(before)
        newLines := SplitLines(after)
        oldCount := oldLines.Length
        newCount := newLines.Length
        columnCount := newCount + 1
        lcs := new int[]((oldCount + 1) * columnCount)

        i := oldCount - 1
        while i >= 0 {
            j := newCount - 1
            while j >= 0 {
                index := LcsIndex(i, j, columnCount)
                if String.Compare(oldLines[i], newLines[j], StringComparison.Ordinal) == 0 {
                    lcs[index] = lcs[LcsIndex(i + 1, j + 1, columnCount)] + 1
                } else {
                    down := lcs[LcsIndex(i + 1, j, columnCount)]
                    right := lcs[LcsIndex(i, j + 1, columnCount)]
                    if down >= right {
                        lcs[index] = down
                    } else {
                        lcs[index] = right
                    }
                }

                j = j - 1
            }

            i = i - 1
        }

        capacity := oldCount + newCount
        kinds := new int[](capacity)
        texts := new string[](capacity)
        oldLineNumbers := new int[](capacity)
        newLineNumbers := new int[](capacity)
        resultCount := 0
        oldIndex := 0
        newIndex := 0

        while oldIndex < oldCount && newIndex < newCount {
            if String.Compare(oldLines[oldIndex], newLines[newIndex], StringComparison.Ordinal) == 0 {
                kinds[resultCount] = 0
                texts[resultCount] = oldLines[oldIndex]
                oldLineNumbers[resultCount] = oldIndex + 1
                newLineNumbers[resultCount] = newIndex + 1
                resultCount = resultCount + 1
                oldIndex = oldIndex + 1
                newIndex = newIndex + 1
            } else if lcs[LcsIndex(oldIndex + 1, newIndex, columnCount)] >= lcs[LcsIndex(oldIndex, newIndex + 1, columnCount)] {
                kinds[resultCount] = 2
                texts[resultCount] = oldLines[oldIndex]
                oldLineNumbers[resultCount] = oldIndex + 1
                newLineNumbers[resultCount] = newIndex + 1
                resultCount = resultCount + 1
                oldIndex = oldIndex + 1
            } else {
                kinds[resultCount] = 1
                texts[resultCount] = newLines[newIndex]
                oldLineNumbers[resultCount] = oldIndex + 1
                newLineNumbers[resultCount] = newIndex + 1
                resultCount = resultCount + 1
                newIndex = newIndex + 1
            }
        }

        while oldIndex < oldCount {
            kinds[resultCount] = 2
            texts[resultCount] = oldLines[oldIndex]
            oldLineNumbers[resultCount] = oldIndex + 1
            newLineNumbers[resultCount] = newIndex + 1
            resultCount = resultCount + 1
            oldIndex = oldIndex + 1
        }

        while newIndex < newCount {
            kinds[resultCount] = 1
            texts[resultCount] = newLines[newIndex]
            oldLineNumbers[resultCount] = oldIndex + 1
            newLineNumbers[resultCount] = newIndex + 1
            resultCount = resultCount + 1
            newIndex = newIndex + 1
        }

        return new UnifiedDiffLineTable {
            Kinds: kinds,
            Texts: texts,
            OldLines: oldLineNumbers,
            NewLines: newLineNumbers,
            Count: resultCount
        }
    }

    static func BuildHunkRanges(lines: UnifiedDiffLineTable, contextLines: int): UnifiedDiffHunkRangeTable {
        lineCount := lines.Count
        ranges := new UnifiedDiffHunkRangeTable {
            Starts: new int[](lineCount),
            Lengths: new int[](lineCount),
            OldStarts: new int[](lineCount),
            OldCounts: new int[](lineCount),
            NewStarts: new int[](lineCount),
            NewCounts: new int[](lineCount),
            Count: 0
        }

        rangeStart := -1
        rangeEnd := -1
        i := 0
        while i < lineCount {
            if lines.Kinds[i] != 0 {
                nextStart := i - contextLines
                if nextStart < 0 {
                    nextStart = 0
                }

                nextEnd := i + contextLines
                if nextEnd >= lineCount {
                    nextEnd = lineCount - 1
                }

                if rangeStart < 0 {
                    rangeStart = nextStart
                    rangeEnd = nextEnd
                } else if nextStart <= rangeEnd + 1 {
                    if nextEnd > rangeEnd {
                        rangeEnd = nextEnd
                    }
                } else {
                    WriteHunkRange(lines, rangeStart, rangeEnd, ranges)
                    rangeStart = nextStart
                    rangeEnd = nextEnd
                }
            }

            i = i + 1
        }

        if rangeStart >= 0 {
            WriteHunkRange(lines, rangeStart, rangeEnd, ranges)
        }

        return ranges
    }

    static func WriteHunkRange(lines: UnifiedDiffLineTable, rangeStart: int, rangeEnd: int, ranges: UnifiedDiffHunkRangeTable) {
        oldStart := 0
        newStart := 0
        oldCount := 0
        newCount := 0

        i := rangeStart
        while i <= rangeEnd {
            kind := lines.Kinds[i]
            if oldStart == 0 && lines.OldLines[i] > 0 {
                oldStart = lines.OldLines[i]
            }

            if newStart == 0 && lines.NewLines[i] > 0 {
                newStart = lines.NewLines[i]
            }

            if kind != 1 {
                oldCount = oldCount + 1
            }

            if kind != 2 {
                newCount = newCount + 1
            }

            i = i + 1
        }

        if oldStart == 0 {
            oldStart = 1
        }

        if newStart == 0 {
            newStart = 1
        }

        hunkIndex := ranges.Count
        ranges.Starts[hunkIndex] = rangeStart
        ranges.Lengths[hunkIndex] = rangeEnd - rangeStart + 1
        ranges.OldStarts[hunkIndex] = oldStart
        ranges.OldCounts[hunkIndex] = oldCount
        ranges.NewStarts[hunkIndex] = newStart
        ranges.NewCounts[hunkIndex] = newCount
        ranges.Count = ranges.Count + 1
    }

    static func AppendHunks(builder: StringBuilder, lines: UnifiedDiffLineTable, ranges: UnifiedDiffHunkRangeTable) {
        hunkIndex := 0
        while hunkIndex < ranges.Count {
            builder.AppendLine(HunkHeaderText(
                ranges.OldStarts[hunkIndex],
                ranges.OldCounts[hunkIndex],
                ranges.NewStarts[hunkIndex],
                ranges.NewCounts[hunkIndex]))

            start := ranges.Starts[hunkIndex]
            end := start + ranges.Lengths[hunkIndex]
            lineIndex := start
            while lineIndex < end {
                builder.Append(LinePrefixText(lines.Kinds[lineIndex]))
                builder.AppendLine(lines.Texts[lineIndex])
                lineIndex = lineIndex + 1
            }

            hunkIndex = hunkIndex + 1
        }
    }

    static func SplitLines(text: string): string[] {
        normalized := NormalizeNewlines(text)
        return normalized.Split('\n')
    }

    static func NormalizeNewlines(text: string): string {
        result := ""
        i := 0
        while i < text.Length {
            if text[i] == '\r' {
                hasNext := i + 1 < text.Length
                if hasNext {
                    if text[i + 1] == '\n' {
                        result = result + ((char)10).ToString()
                        i = i + 2
                        continue
                    }
                }
            }

            result = result + text.Substring(i, 1)
            i = i + 1
        }

        return result
    }

    static func LcsIndex(row: int, column: int, columnCount: int): int {
        return row * columnCount + column
    }

    static func BeforeHeaderText(label: string): string {
        return "--- " + label
    }

    static func AfterHeaderText(label: string): string {
        return "+++ " + label
    }

    static func HunkHeaderText(oldStart: int, oldCount: int, newStart: int, newCount: int): string {
        return "@@ -" + oldStart.ToString()
            + "," + oldCount.ToString()
            + " +" + newStart.ToString()
            + "," + newCount.ToString()
            + " @@"
    }

    static func LinePrefixText(kind: int): string {
        if kind == 1 {
            return "+"
        }

        if kind == 2 {
            return "-"
        }

        return " "
    }
}

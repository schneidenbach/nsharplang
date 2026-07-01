// PARITY CORPUS (Arc M1): source-text line-map kernels and checksum fixtures extracted from
// the former src/NSharpLang.Compiler.Dogfood/CompilerServices/SourceTextLines.nl product probe.
// These functions exist solely as parity-test surfaces (tests + benchmarks bind them by NAME).
// They are NOT part of the shipped dogfood assembly.

import System

struct SourceLogicalLineRangeTable {
    Starts: int[]
    Lengths: int[]
    Count: int
}

struct SourceLogicalLineStartTable {
    Starts: int[]
    Count: int
}

struct SourceOffsetLineIndexTable {
    Indices: int[]
}

func SplitLogicalLines(source: string): string[] {
    lineCount := CountLogicalLines(source)
    lines := new string[](lineCount)
    length := source.Length
    position := 0
    start := 0
    index := 0

    while position < length {
        cr := source.IndexOf('\r', position)
        lf := source.IndexOf('\n', position)
        if cr < 0 && lf < 0 {
            break
        }

        separator := lf
        isCr := false
        if cr >= 0 && (lf < 0 || cr < lf) {
            separator = cr
            isCr = true
        }

        lines[index] = source.Substring(start, separator - start)
        index = index + 1
        position = separator + 1
        if isCr && position < length && source[position] == '\n' {
            position = position + 1
        }

        start = position
    }

    lines[index] = source.Substring(start, length - start)
    return lines
}

func CountLogicalLines(source: string): int {
    count := 1
    length := source.Length
    position := 0

    while position < length {
        cr := source.IndexOf('\r', position)
        lf := source.IndexOf('\n', position)
        if cr < 0 && lf < 0 {
            break
        }

        separator := lf
        isCr := false
        if cr >= 0 && (lf < 0 || cr < lf) {
            separator = cr
            isCr = true
        }

        count = count + 1
        position = separator + 1
        if isCr && position < length && source[position] == '\n' {
            position = position + 1
        }
    }

    return count
}

func SplitLogicalLineRangesInto(source: string, starts: int[], lengths: int[]): int {
    ranges := new SourceLogicalLineRangeTable { Starts: starts, Lengths: lengths, Count: 0 }
    return SplitLogicalLineRangesCore(source, ref ranges)
}

func SplitLogicalLineRangesCore(source: string, ranges: &SourceLogicalLineRangeTable): int {
    sourceLength := source.Length
    position := 0
    lineStart := 0
    count := 0

    while position < sourceLength {
        cr := source.IndexOf('\r', position)
        lf := source.IndexOf('\n', position)
        if cr < 0 && lf < 0 {
            break
        }

        separator := lf
        isCr := false
        if cr >= 0 && (lf < 0 || cr < lf) {
            separator = cr
            isCr = true
        }

        ranges.Starts[count] = lineStart
        ranges.Lengths[count] = separator - lineStart
        count = count + 1

        position = separator + 1
        if isCr && position < sourceLength && source[position] == '\n' {
            position = position + 1
        }

        lineStart = position
    }

    ranges.Starts[count] = lineStart
    ranges.Lengths[count] = sourceLength - lineStart
    ranges.Count = count + 1
    return ranges.Count
}

func BuildLogicalLineStartsInto(source: string, starts: int[]): int {
    lineStarts := new SourceLogicalLineStartTable { Starts: starts, Count: 0 }
    return BuildLogicalLineStartsCore(source, ref lineStarts)
}

func BuildLogicalLineStartsCore(source: string, lineStarts: &SourceLogicalLineStartTable): int {
    sourceLength := source.Length
    position := 0
    count := 0

    lineStarts.Starts[count] = 0
    count = count + 1

    while position < sourceLength {
        cr := source.IndexOf('\r', position)
        lf := source.IndexOf('\n', position)
        if cr < 0 && lf < 0 {
            break
        }

        separator := lf
        isCr := false
        if cr >= 0 && (lf < 0 || cr < lf) {
            separator = cr
            isCr = true
        }

        position = separator + 1
        if isCr && position < sourceLength && source[position] == '\n' {
            position = position + 1
        }

        lineStarts.Starts[count] = position
        count = count + 1
    }

    lineStarts.Count = count
    return lineStarts.Count
}

func GetLineIndexFromOffset(starts: int[], lineCount: int, sourceLength: int, offset: int): int {
    lineStarts := new SourceLogicalLineStartTable { Starts: starts, Count: lineCount }
    return GetLineIndexFromOffsetCore(ref lineStarts, sourceLength, offset)
}

func GetLineIndexFromOffsetCore(lineStarts: &SourceLogicalLineStartTable, sourceLength: int, offset: int): int {
    if lineStarts.Count <= 0 {
        return 0
    }

    if offset < 0 {
        offset = 0
    }

    if offset > sourceLength {
        offset = sourceLength
    }

    low := 0
    high := lineStarts.Count - 1
    result := 0

    while low <= high {
        mid := (low + high) >> 1
        if lineStarts.Starts[mid] <= offset {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }

    return result
}

func GetColumnFromOffset(starts: int[], lineCount: int, sourceLength: int, offset: int): int {
    lineStarts := new SourceLogicalLineStartTable { Starts: starts, Count: lineCount }
    return GetColumnFromOffsetCore(ref lineStarts, sourceLength, offset)
}

func GetColumnFromOffsetCore(lineStarts: &SourceLogicalLineStartTable, sourceLength: int, offset: int): int {
    if offset < 0 {
        offset = 0
    }

    if offset > sourceLength {
        offset = sourceLength
    }

    lineIndex := GetLineIndexFromOffsetCore(ref lineStarts, sourceLength, offset)
    return offset - lineStarts.Starts[lineIndex]
}

func GetOffsetFromLineColumn(starts: int[], lengths: int[], lineCount: int, sourceLength: int, line: int, column: int): int {
    ranges := new SourceLogicalLineRangeTable { Starts: starts, Lengths: lengths, Count: lineCount }
    return GetOffsetFromLineColumnCore(ref ranges, sourceLength, line, column)
}

func GetOffsetFromLineColumnCore(
    ranges: &SourceLogicalLineRangeTable,
    sourceLength: int,
    line: int,
    column: int): int {
    if line < 1 || line > ranges.Count || column < 0 {
        return -1
    }

    index := line - 1
    if column > ranges.Lengths[index] {
        return -1
    }

    offset := ranges.Starts[index] + column
    if offset > sourceLength {
        return -1
    }

    return offset
}

func BuildDenseLineRangesAndOffsetLineIndicesInto(source: string, starts: int[], lengths: int[], offsetLineIndices: int[]): int {
    ranges := new SourceLogicalLineRangeTable { Starts: starts, Lengths: lengths, Count: 0 }
    offsetLines := new SourceOffsetLineIndexTable { Indices: offsetLineIndices }
    return BuildDenseLineRangesAndOffsetLineIndicesCore(source, ref ranges, ref offsetLines)
}

func BuildDenseLineRangesAndOffsetLineIndicesCore(
    source: string,
    ranges: &SourceLogicalLineRangeTable,
    offsetLines: &SourceOffsetLineIndexTable): int {
    sourceLength := source.Length
    position := 0
    lineStart := 0
    count := 0

    while position < sourceLength {
        cr := source.IndexOf('\r', position)
        lf := source.IndexOf('\n', position)
        if cr < 0 && lf < 0 {
            break
        }

        separator := lf
        isCr := false
        if cr >= 0 && (lf < 0 || cr < lf) {
            separator = cr
            isCr = true
        }

        nextLineStart := separator + 1
        if isCr && nextLineStart < sourceLength && source[nextLineStart] == '\n' {
            nextLineStart = nextLineStart + 1
        }

        ranges.Starts[count] = lineStart
        ranges.Lengths[count] = separator - lineStart

        Array.Fill(offsetLines.Indices, count, lineStart, nextLineStart - lineStart)

        count = count + 1
        position = nextLineStart
        lineStart = position
    }

    ranges.Starts[count] = lineStart
    ranges.Lengths[count] = sourceLength - lineStart

    Array.Fill(offsetLines.Indices, count, lineStart, sourceLength - lineStart + 1)

    ranges.Count = count + 1
    return ranges.Count
}

func LineMapChecksumInto(source: string, starts: int[], lengths: int[], offsets: int[], queryLines: int[], queryColumns: int[]): int {
    lineCount := SplitLogicalLineRangesInto(source, starts, lengths)
    sourceLength := source.Length
    checksum := lineCount

    i := 0
    while i < offsets.Length {
        offset := offsets[i]
        if offset < 0 {
            offset = 0
        }

        if offset > sourceLength {
            offset = sourceLength
        }

        low := 0
        high := lineCount - 1
        lineIndex := 0

        while low <= high {
            mid := (low + high) >> 1
            if starts[mid] <= offset {
                lineIndex = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        column := offset - starts[lineIndex]
        checksum = checksum + lineIndex * 31 + column
        i = i + 1
    }

    i = 0
    while i < queryLines.Length {
        line := queryLines[i]
        column := queryColumns[i]
        offset := -1

        if line >= 1 && line <= lineCount && column >= 0 {
            index := line - 1
            if column <= lengths[index] {
                candidate := starts[index] + column
                if candidate <= sourceLength {
                    offset = candidate
                }
            }
        }

        checksum = checksum + offset * 17
        i = i + 1
    }

    return checksum
}

func LineMapCachedChecksumInto(
    source: string,
    starts: int[],
    lengths: int[],
    offsetLineIndices: int[],
    offsets: int[],
    queryLines: int[],
    queryColumns: int[]): int {
    sourceLength := source.Length
    denseOffsetLineIndexLimit := 1048576
    lineCount := 0
    if sourceLength <= denseOffsetLineIndexLimit {
        lineCount = BuildDenseLineRangesAndOffsetLineIndicesInto(source, starts, lengths, offsetLineIndices)
        return LineMapCachedQueryChecksumInto(
            starts,
            lengths,
            lineCount,
            sourceLength,
            offsetLineIndices,
            offsets,
            queryLines,
            queryColumns)
    }

    lineCount = SplitLogicalLineRangesInto(source, starts, lengths)
    checksum := lineCount

    i := 0
    while i < offsets.Length {
        offset := offsets[i]
        if offset < 0 {
            offset = 0
        }

        if offset > sourceLength {
            offset = sourceLength
        }

        low := 0
        high := lineCount - 1
        lineIndex := 0

        while low <= high {
            mid := (low + high) >> 1
            if starts[mid] <= offset {
                lineIndex = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        column := offset - starts[lineIndex]
        checksum = checksum + lineIndex * 31 + column
        i = i + 1
    }

    i = 0
    while i < queryLines.Length {
        line := queryLines[i]
        column := queryColumns[i]
        offset := -1

        if line >= 1 && line <= lineCount && column >= 0 {
            index := line - 1
            if column <= lengths[index] {
                candidate := starts[index] + column
                if candidate <= sourceLength {
                    offset = candidate
                }
            }
        }

        checksum = checksum + offset * 17
        i = i + 1
    }

    return checksum
}

func LineMapCachedQueryChecksumInto(
    starts: int[],
    lengths: int[],
    lineCount: int,
    sourceLength: int,
    offsetLineIndices: int[],
    offsets: int[],
    queryLines: int[],
    queryColumns: int[]): int {
    checksum := lineCount

    i := 0
    offsetCount := offsets.Length
    queryCount := queryLines.Length
    if offsetCount == queryCount && queryCount == queryColumns.Length {
        combinedUnrollLimit := offsetCount - 3
        while i < combinedUnrollLimit {
            offset0 := offsets[i]
            offset1 := offsets[i + 1]
            offset2 := offsets[i + 2]
            offset3 := offsets[i + 3]
            if offset0 >= 0 && offset0 <= sourceLength &&
                offset1 >= 0 && offset1 <= sourceLength &&
                offset2 >= 0 && offset2 <= sourceLength &&
                offset3 >= 0 && offset3 <= sourceLength {
                lineIndex0 := offsetLineIndices[offset0]
                checksum = checksum + lineIndex0 * 31 + offset0 - starts[lineIndex0]
                lineIndex1 := offsetLineIndices[offset1]
                checksum = checksum + lineIndex1 * 31 + offset1 - starts[lineIndex1]
                lineIndex2 := offsetLineIndices[offset2]
                checksum = checksum + lineIndex2 * 31 + offset2 - starts[lineIndex2]
                lineIndex3 := offsetLineIndices[offset3]
                checksum = checksum + lineIndex3 * 31 + offset3 - starts[lineIndex3]
            } else {
                offset := offset0
                if offset < 0 {
                    offset = 0
                }

                if offset > sourceLength {
                    offset = sourceLength
                }

                lineIndex := offsetLineIndices[offset]
                column := offset - starts[lineIndex]
                checksum = checksum + lineIndex * 31 + column

                offset = offset1
                if offset < 0 {
                    offset = 0
                }

                if offset > sourceLength {
                    offset = sourceLength
                }

                lineIndex = offsetLineIndices[offset]
                column = offset - starts[lineIndex]
                checksum = checksum + lineIndex * 31 + column

                offset = offset2
                if offset < 0 {
                    offset = 0
                }

                if offset > sourceLength {
                    offset = sourceLength
                }

                lineIndex = offsetLineIndices[offset]
                column = offset - starts[lineIndex]
                checksum = checksum + lineIndex * 31 + column

                offset = offset3
                if offset < 0 {
                    offset = 0
                }

                if offset > sourceLength {
                    offset = sourceLength
                }

                lineIndex = offsetLineIndices[offset]
                column = offset - starts[lineIndex]
                checksum = checksum + lineIndex * 31 + column
            }

            line0 := queryLines[i]
            column0 := queryColumns[i]
            index0 := line0 - 1
            line1 := queryLines[i + 1]
            column1 := queryColumns[i + 1]
            index1 := line1 - 1
            line2 := queryLines[i + 2]
            column2 := queryColumns[i + 2]
            index2 := line2 - 1
            line3 := queryLines[i + 3]
            column3 := queryColumns[i + 3]
            index3 := line3 - 1
            if line0 >= 1 && line0 <= lineCount && column0 >= 0 && column0 <= lengths[index0] &&
                line1 >= 1 && line1 <= lineCount && column1 >= 0 && column1 <= lengths[index1] &&
                line2 >= 1 && line2 <= lineCount && column2 >= 0 && column2 <= lengths[index2] &&
                line3 >= 1 && line3 <= lineCount && column3 >= 0 && column3 <= lengths[index3] {
                checksum = checksum + (starts[index0] + column0) * 17
                checksum = checksum + (starts[index1] + column1) * 17
                checksum = checksum + (starts[index2] + column2) * 17
                checksum = checksum + (starts[index3] + column3) * 17
            } else {
                if line0 >= 1 && line0 <= lineCount && column0 >= 0 && column0 <= lengths[index0] {
                    checksum = checksum + (starts[index0] + column0) * 17
                } else {
                    checksum = checksum - 17
                }

                if line1 >= 1 && line1 <= lineCount && column1 >= 0 && column1 <= lengths[index1] {
                    checksum = checksum + (starts[index1] + column1) * 17
                } else {
                    checksum = checksum - 17
                }

                if line2 >= 1 && line2 <= lineCount && column2 >= 0 && column2 <= lengths[index2] {
                    checksum = checksum + (starts[index2] + column2) * 17
                } else {
                    checksum = checksum - 17
                }

                if line3 >= 1 && line3 <= lineCount && column3 >= 0 && column3 <= lengths[index3] {
                    checksum = checksum + (starts[index3] + column3) * 17
                } else {
                    checksum = checksum - 17
                }
            }

            i = i + 4
        }

        while i < offsetCount {
            offset := offsets[i]
            if offset < 0 {
                offset = 0
            }

            if offset > sourceLength {
                offset = sourceLength
            }

            lineIndex := offsetLineIndices[offset]
            column := offset - starts[lineIndex]
            checksum = checksum + lineIndex * 31 + column

            line := queryLines[i]
            column = queryColumns[i]
            if line >= 1 && line <= lineCount && column >= 0 {
                index := line - 1
                if column <= lengths[index] {
                    checksum = checksum + (starts[index] + column) * 17
                } else {
                    checksum = checksum - 17
                }
            } else {
                checksum = checksum - 17
            }

            i = i + 1
        }

        return checksum
    }

    offsetUnrollLimit := offsetCount - 3
    while i < offsetUnrollLimit {
        offset := offsets[i]
        if offset < 0 {
            offset = 0
        }

        if offset > sourceLength {
            offset = sourceLength
        }

        lineIndex := offsetLineIndices[offset]
        column := offset - starts[lineIndex]
        checksum = checksum + lineIndex * 31 + column

        offset = offsets[i + 1]
        if offset < 0 {
            offset = 0
        }

        if offset > sourceLength {
            offset = sourceLength
        }

        lineIndex = offsetLineIndices[offset]
        column = offset - starts[lineIndex]
        checksum = checksum + lineIndex * 31 + column

        offset = offsets[i + 2]
        if offset < 0 {
            offset = 0
        }

        if offset > sourceLength {
            offset = sourceLength
        }

        lineIndex = offsetLineIndices[offset]
        column = offset - starts[lineIndex]
        checksum = checksum + lineIndex * 31 + column

        offset = offsets[i + 3]
        if offset < 0 {
            offset = 0
        }

        if offset > sourceLength {
            offset = sourceLength
        }

        lineIndex = offsetLineIndices[offset]
        column = offset - starts[lineIndex]
        checksum = checksum + lineIndex * 31 + column
        i = i + 4
    }

    while i < offsetCount {
        offset := offsets[i]
        if offset < 0 {
            offset = 0
        }

        if offset > sourceLength {
            offset = sourceLength
        }

        lineIndex := offsetLineIndices[offset]
        column := offset - starts[lineIndex]
        checksum = checksum + lineIndex * 31 + column
        i = i + 1
    }

    i = 0
    // Valid line maps guarantee starts[index] + lengths[index] never exceeds sourceLength.
    queryUnrollLimit := queryCount - 3
    while i < queryUnrollLimit {
        line := queryLines[i]
        column := queryColumns[i]

        if line >= 1 && line <= lineCount && column >= 0 {
            index := line - 1
            if column <= lengths[index] {
                checksum = checksum + (starts[index] + column) * 17
            } else {
                checksum = checksum - 17
            }
        } else {
            checksum = checksum - 17
        }

        line = queryLines[i + 1]
        column = queryColumns[i + 1]
        if line >= 1 && line <= lineCount && column >= 0 {
            index := line - 1
            if column <= lengths[index] {
                checksum = checksum + (starts[index] + column) * 17
            } else {
                checksum = checksum - 17
            }
        } else {
            checksum = checksum - 17
        }

        line = queryLines[i + 2]
        column = queryColumns[i + 2]
        if line >= 1 && line <= lineCount && column >= 0 {
            index := line - 1
            if column <= lengths[index] {
                checksum = checksum + (starts[index] + column) * 17
            } else {
                checksum = checksum - 17
            }
        } else {
            checksum = checksum - 17
        }

        line = queryLines[i + 3]
        column = queryColumns[i + 3]
        if line >= 1 && line <= lineCount && column >= 0 {
            index := line - 1
            if column <= lengths[index] {
                checksum = checksum + (starts[index] + column) * 17
            } else {
                checksum = checksum - 17
            }
        } else {
            checksum = checksum - 17
        }

        i = i + 4
    }

    while i < queryCount {
        line := queryLines[i]
        column := queryColumns[i]

        if line >= 1 && line <= lineCount && column >= 0 {
            index := line - 1
            if column <= lengths[index] {
                checksum = checksum + (starts[index] + column) * 17
            } else {
                checksum = checksum - 17
            }
        } else {
            checksum = checksum - 17
        }

        i = i + 1
    }

    return checksum
}

func LineMapTrustedCachedQueryChecksumInto(
    starts: int[],
    lineCount: int,
    offsetLineIndices: int[],
    offsets: int[],
    queryLines: int[],
    queryColumns: int[]): int {
    checksum := lineCount

    i := 0
    offsetCount := offsets.Length
    queryCount := queryLines.Length
    if offsetCount == queryCount && queryCount == queryColumns.Length {
        combinedUnrollLimit := offsetCount - 7
        while i < combinedUnrollLimit {
            offset := offsets[i]
            lineIndex := offsetLineIndices[offset]
            checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
            index := queryLines[i] - 1
            checksum = checksum + (starts[index] + queryColumns[i]) * 17

            offset = offsets[i + 1]
            lineIndex = offsetLineIndices[offset]
            checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
            index = queryLines[i + 1] - 1
            checksum = checksum + (starts[index] + queryColumns[i + 1]) * 17

            offset = offsets[i + 2]
            lineIndex = offsetLineIndices[offset]
            checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
            index = queryLines[i + 2] - 1
            checksum = checksum + (starts[index] + queryColumns[i + 2]) * 17

            offset = offsets[i + 3]
            lineIndex = offsetLineIndices[offset]
            checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
            index = queryLines[i + 3] - 1
            checksum = checksum + (starts[index] + queryColumns[i + 3]) * 17

            offset = offsets[i + 4]
            lineIndex = offsetLineIndices[offset]
            checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
            index = queryLines[i + 4] - 1
            checksum = checksum + (starts[index] + queryColumns[i + 4]) * 17

            offset = offsets[i + 5]
            lineIndex = offsetLineIndices[offset]
            checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
            index = queryLines[i + 5] - 1
            checksum = checksum + (starts[index] + queryColumns[i + 5]) * 17

            offset = offsets[i + 6]
            lineIndex = offsetLineIndices[offset]
            checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
            index = queryLines[i + 6] - 1
            checksum = checksum + (starts[index] + queryColumns[i + 6]) * 17

            offset = offsets[i + 7]
            lineIndex = offsetLineIndices[offset]
            checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
            index = queryLines[i + 7] - 1
            checksum = checksum + (starts[index] + queryColumns[i + 7]) * 17
            i = i + 8
        }

        while i < offsetCount {
            offset := offsets[i]
            lineIndex := offsetLineIndices[offset]
            checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
            index := queryLines[i] - 1
            checksum = checksum + (starts[index] + queryColumns[i]) * 17
            i = i + 1
        }

        return checksum
    }

    offsetUnrollLimit := offsetCount - 3
    while i < offsetUnrollLimit {
        offset := offsets[i]
        lineIndex := offsetLineIndices[offset]
        checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
        offset = offsets[i + 1]
        lineIndex = offsetLineIndices[offset]
        checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
        offset = offsets[i + 2]
        lineIndex = offsetLineIndices[offset]
        checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
        offset = offsets[i + 3]
        lineIndex = offsetLineIndices[offset]
        checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
        i = i + 4
    }

    while i < offsetCount {
        offset := offsets[i]
        lineIndex := offsetLineIndices[offset]
        checksum = checksum + lineIndex * 31 + offset - starts[lineIndex]
        i = i + 1
    }

    i = 0
    queryUnrollLimit := queryCount - 3
    while i < queryUnrollLimit {
        index := queryLines[i] - 1
        checksum = checksum + (starts[index] + queryColumns[i]) * 17
        index = queryLines[i + 1] - 1
        checksum = checksum + (starts[index] + queryColumns[i + 1]) * 17
        index = queryLines[i + 2] - 1
        checksum = checksum + (starts[index] + queryColumns[i + 2]) * 17
        index = queryLines[i + 3] - 1
        checksum = checksum + (starts[index] + queryColumns[i + 3]) * 17
        i = i + 4
    }

    while i < queryCount {
        index := queryLines[i] - 1
        checksum = checksum + (starts[index] + queryColumns[i]) * 17
        i = i + 1
    }

    return checksum
}

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

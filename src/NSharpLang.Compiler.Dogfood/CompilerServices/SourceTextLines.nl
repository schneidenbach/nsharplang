import System

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

        starts[count] = lineStart
        lengths[count] = separator - lineStart
        count = count + 1

        position = separator + 1
        if isCr && position < sourceLength && source[position] == '\n' {
            position = position + 1
        }

        lineStart = position
    }

    starts[count] = lineStart
    lengths[count] = sourceLength - lineStart
    return count + 1
}

func BuildLogicalLineStartsInto(source: string, starts: int[]): int {
    sourceLength := source.Length
    position := 0
    count := 0

    starts[count] = 0
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

        starts[count] = position
        count = count + 1
    }

    return count
}

func GetLineIndexFromOffset(starts: int[], lineCount: int, sourceLength: int, offset: int): int {
    if lineCount <= 0 {
        return 0
    }

    if offset < 0 {
        offset = 0
    }

    if offset > sourceLength {
        offset = sourceLength
    }

    low := 0
    high := lineCount - 1
    result := 0

    while low <= high {
        mid := (low + high) >> 1
        if starts[mid] <= offset {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }

    return result
}

func GetColumnFromOffset(starts: int[], lineCount: int, sourceLength: int, offset: int): int {
    if offset < 0 {
        offset = 0
    }

    if offset > sourceLength {
        offset = sourceLength
    }

    lineIndex := GetLineIndexFromOffset(starts, lineCount, sourceLength, offset)
    return offset - starts[lineIndex]
}

func GetOffsetFromLineColumn(starts: int[], lengths: int[], lineCount: int, sourceLength: int, line: int, column: int): int {
    if line < 1 || line > lineCount || column < 0 {
        return -1
    }

    index := line - 1
    if column > lengths[index] {
        return -1
    }

    offset := starts[index] + column
    if offset > sourceLength {
        return -1
    }

    return offset
}

func BuildDenseLineRangesAndOffsetLineIndicesInto(source: string, starts: int[], lengths: int[], offsetLineIndices: int[]): int {
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

        starts[count] = lineStart
        lengths[count] = separator - lineStart

        Array.Fill(offsetLineIndices, count, lineStart, nextLineStart - lineStart)

        count = count + 1
        position = nextLineStart
        lineStart = position
    }

    starts[count] = lineStart
    lengths[count] = sourceLength - lineStart

    Array.Fill(offsetLineIndices, count, lineStart, sourceLength - lineStart + 1)

    return count + 1
}

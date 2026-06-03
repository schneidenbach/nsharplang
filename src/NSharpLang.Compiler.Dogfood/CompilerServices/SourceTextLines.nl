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
        mid := (low + high) / 2
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
            mid := (low + high) / 2
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

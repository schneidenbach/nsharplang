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

import System

func CliQueryPositionChecksumInto(
    positions: string[],
    resultLines: int[],
    resultColumns: int[]): int {
    count := CliQueryMinInt(positions.Length, resultLines.Length)
    count = CliQueryMinInt(count, resultColumns.Length)
    checksum := count
    i := 0

    while i < count {
        parsed := CliTryParsePositionPartsInto(positions[i], resultLines, i, resultColumns, i)
        checksum = checksum + parsed * 97 + resultLines[i] * 31 + resultColumns[i] * 17
        i = i + 1
    }

    return checksum
}

func CliQueryPositionsInto(
    positions: string[],
    resultLines: int[],
    resultColumns: int[]): int {
    count := CliQueryMinInt(positions.Length, resultLines.Length)
    count = CliQueryMinInt(count, resultColumns.Length)

    i := 0
    while i < count {
        CliTryParsePositionPartsInto(positions[i], resultLines, i, resultColumns, i)
        i = i + 1
    }

    return count
}

func CliTryParsePositionInto(position: string, result: int[]): int {
    if result.Length < 2 {
        return 0
    }

    return CliTryParsePositionPartsInto(position, result, 0, result, 1)
}

func CliTryParsePositionPartsInto(
    position: string,
    resultLines: int[],
    lineIndex: int,
    resultColumns: int[],
    columnIndex: int): int {
    resultLines[lineIndex] = 0
    resultColumns[columnIndex] = 0
    colon := -1
    i := 0
    while i < position.Length {
        if position[i] == ':' {
            if colon >= 0 {
                return 0
            }

            colon = i
        }

        i = i + 1
    }

    if colon < 0 {
        return 0
    }

    if !CliTryParseIntSegmentInto(position, 0, colon, resultLines, lineIndex) {
        resultLines[lineIndex] = 0
        resultColumns[columnIndex] = 0
        return 0
    }

    if !CliTryParseIntSegmentInto(position, colon + 1, position.Length, resultColumns, columnIndex) {
        resultColumns[columnIndex] = 0
        return 0
    }

    return 1
}

func CliTryParseIntSegmentInto(text: string, start: int, end: int, result: int[], resultIndex: int): bool {
    while start < end && Char.IsWhiteSpace(text[start]) {
        start = start + 1
    }

    while end > start && Char.IsWhiteSpace(text[end - 1]) {
        end = end - 1
    }

    if start >= end {
        return false
    }

    negative := false
    if text[start] == '+' || text[start] == '-' {
        negative = text[start] == '-'
        start = start + 1
        if start >= end {
            return false
        }
    }

    value := 0
    index := start
    while index < end {
        ch := text[index]
        if ch < '0' || ch > '9' {
            return false
        }

        digit := ch - '0'
        if negative && value == 214748364 && digit == 8 && index == end - 1 {
            result[resultIndex] = 0 - 2147483647 - 1
            return true
        }

        if value > (2147483647 - digit) / 10 {
            return false
        }

        value = value * 10 + digit
        index = index + 1
    }

    if negative {
        result[resultIndex] = 0 - value
    } else {
        result[resultIndex] = value
    }

    return true
}

func CliQueryMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

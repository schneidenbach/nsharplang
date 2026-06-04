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

func CliBatchDuplicateIdRanksInto(
    idRanks: int[],
    uniqueIdCount: int,
    countsByRank: int[],
    resultRanks: int[]): int {
    clearCount := uniqueIdCount + 1
    if clearCount > countsByRank.Length {
        clearCount = countsByRank.Length
    }

    i := 0
    while i < clearCount {
        countsByRank[i] = 0
        i = i + 1
    }

    i = 0
    while i < idRanks.Length {
        rank := idRanks[i]
        if rank > 0 && rank <= uniqueIdCount && rank < countsByRank.Length {
            countsByRank[rank] = countsByRank[rank] + 1
        }

        i = i + 1
    }

    duplicateCount := 0
    rank := 1
    while rank <= uniqueIdCount && rank < countsByRank.Length {
        if countsByRank[rank] > 1 {
            if duplicateCount < resultRanks.Length {
                resultRanks[duplicateCount] = rank
            }

            duplicateCount = duplicateCount + 1
        }

        rank = rank + 1
    }

    return duplicateCount
}

func CliBatchDuplicateIdRankChecksumInto(
    idRanks: int[],
    uniqueIdCount: int,
    countsByRank: int[],
    resultRanks: int[],
    idLengthsByRank: int[]): int {
    duplicateCount := CliBatchDuplicateIdRanksInto(
        idRanks,
        uniqueIdCount,
        countsByRank,
        resultRanks)

    checksum := duplicateCount
    i := 0
    while i < duplicateCount && i < resultRanks.Length {
        rank := resultRanks[i]
        length := 0
        if rank >= 0 && rank < idLengthsByRank.Length {
            length = idLengthsByRank[rank]
        }

        checksum = checksum + rank * 31 + length * 17
        i = i + 1
    }

    return checksum
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

    fastParsed := CliTryParseSimplePositivePositionInto(
        position,
        resultLines,
        lineIndex,
        resultColumns,
        columnIndex)
    if fastParsed >= 0 {
        return fastParsed
    }

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

func CliTryParseSimplePositivePositionInto(
    position: string,
    resultLines: int[],
    lineIndex: int,
    resultColumns: int[],
    columnIndex: int): int {
    if position.Length < 3 {
        return -1
    }

    line := 0
    column := 0
    sawColon := false
    lineDigits := 0
    columnDigits := 0

    i := 0
    while i < position.Length {
        ch := position[i]
        if ch == ':' {
            if sawColon || lineDigits == 0 {
                return -1
            }

            sawColon = true
        } else if ch >= '0' && ch <= '9' {
            digit := ch - '0'
            if sawColon {
                if column > 214748364 {
                    return -1
                }

                if column == 214748364 && digit > 7 {
                    return -1
                }

                column = column * 10 + digit
                columnDigits = columnDigits + 1
            } else {
                if line > 214748364 {
                    return -1
                }

                if line == 214748364 && digit > 7 {
                    return -1
                }

                line = line * 10 + digit
                lineDigits = lineDigits + 1
            }
        } else {
            return -1
        }

        i = i + 1
    }

    if !sawColon || columnDigits == 0 {
        return -1
    }

    resultLines[lineIndex] = line
    resultColumns[columnIndex] = column
    return 1
}

func CliTryParseIntSegmentInto(text: string, start: int, end: int, result: int[], resultIndex: int): bool {
    while start < end && CliQueryIsWhiteSpace(text[start]) {
        start = start + 1
    }

    while end > start && CliQueryIsWhiteSpace(text[end - 1]) {
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
        if value > 214748364 {
            return false
        }

        if value == 214748364 {
            if negative {
                if digit == 8 && index == end - 1 {
                    result[resultIndex] = 0 - 2147483647 - 1
                    return true
                }

                return false
            }

            if digit > 7 {
                return false
            }
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

func CliQueryIsWhiteSpace(ch: char): bool {
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
        return true
    }

    return Char.IsWhiteSpace(ch)
}

func CliQueryMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

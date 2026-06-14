// PARITY CORPUS (Arc M1): checksum oracles and query-position parser probes extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/CliQueryParsing.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

struct CliQueryPositionResultTable {
    Lines: int[]
    Columns: int[]
}

struct CliQueryPositionInputTable {
    Positions: string[]
}

struct CliQueryIntResultTable {
    Values: int[]
}

func CliTryParsePositionInto(position: string, result: int[]): int {
    if result.Length < 2 {
        return 0
    }

    results := new CliQueryPositionResultTable { Lines: result, Columns: result }
    return CliTryParsePositionPartsCore(position, ref results, 0, 1)
}

func CliTryParsePositionPartsCore(
    position: string,
    results: &CliQueryPositionResultTable,
    lineIndex: int,
    columnIndex: int): int {
    results.Lines[lineIndex] = 0
    results.Columns[columnIndex] = 0

    fastParsed := CliTryParseSimplePositivePositionCore(position, ref results, lineIndex, columnIndex)
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

    lineResult := new CliQueryIntResultTable { Values: results.Lines }
    if !CliTryParseIntSegmentCore(position, 0, colon, ref lineResult, lineIndex) {
        results.Lines[lineIndex] = 0
        results.Columns[columnIndex] = 0
        return 0
    }

    columnResult := new CliQueryIntResultTable { Values: results.Columns }
    if !CliTryParseIntSegmentCore(position, colon + 1, position.Length, ref columnResult, columnIndex) {
        results.Columns[columnIndex] = 0
        return 0
    }

    return 1
}

func CliTryParseSimplePositivePositionCore(
    position: string,
    results: &CliQueryPositionResultTable,
    lineIndex: int,
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

    results.Lines[lineIndex] = line
    results.Columns[columnIndex] = column
    return 1
}

func CliTryParseIntSegmentCore(
    text: string,
    start: int,
    end: int,
    result: &CliQueryIntResultTable,
    resultIndex: int): bool {
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
                    result.Values[resultIndex] = 0 - 2147483647 - 1
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
        result.Values[resultIndex] = 0 - value
    } else {
        result.Values[resultIndex] = value
    }

    return true
}

func CliQueryIsWhiteSpace(ch: char): bool {
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
        return true
    }

    return char.IsWhiteSpace(ch)
}

func CliQueryMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

func CliQueryPositionsInto(
    positions: string[],
    resultLines: int[],
    resultColumns: int[]): int {
    input := new CliQueryPositionInputTable { Positions: positions }
    results := new CliQueryPositionResultTable { Lines: resultLines, Columns: resultColumns }
    return CliQueryPositionsCore(ref input, ref results)
}

func CliQueryPositionsCore(input: &CliQueryPositionInputTable, results: &CliQueryPositionResultTable): int {
    count := CliQueryMinInt(input.Positions.Length, results.Lines.Length)
    count = CliQueryMinInt(count, results.Columns.Length)

    i := 0
    while i < count {
        CliTryParsePositionPartsCore(input.Positions[i], ref results, i, i)
        i = i + 1
    }

    return count
}

func CliQueryPositionChecksumInto(
    positions: string[],
    resultLines: int[],
    resultColumns: int[]): int {
    count := CliQueryMinInt(positions.Length, resultLines.Length)
    count = CliQueryMinInt(count, resultColumns.Length)
    results := new CliQueryPositionResultTable { Lines: resultLines, Columns: resultColumns }
    checksum := count
    i := 0

    while i < count {
        parsed := CliTryParsePositionPartsCore(positions[i], ref results, i, i)
        checksum = checksum + parsed * 97 + resultLines[i] * 31 + resultColumns[i] * 17
        i = i + 1
    }

    return checksum
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

func CliBatchResultPackedCountChecksum(okWords: ulong[], itemCount: int): int {
    successCount := CliBatchResultPackedSuccessCount(okWords, itemCount)
    failureCount := itemCount - successCount
    return itemCount * 31 + successCount * 17 + failureCount * 13
}

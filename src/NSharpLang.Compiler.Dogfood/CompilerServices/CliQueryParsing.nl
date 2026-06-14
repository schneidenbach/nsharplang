import System
import System.Numerics

struct CliQueryPositionResultTable {
    Lines: int[]
    Columns: int[]
}

struct CliBatchDuplicateIdRankTable {
    IdRanks: int[]
    UniqueIdCount: int
}

struct CliBatchDuplicateScratchTable {
    CountsByRank: int[]
    ResultRanks: int[]
}

struct CliBatchResultWordTable {
    OkWords: ulong[]
    ItemCount: int
}

struct CliQueryIntResultTable {
    Values: int[]
}

func CliBatchDuplicateIdRanksInto(
    idRanks: int[],
    uniqueIdCount: int,
    countsByRank: int[],
    resultRanks: int[]): int {
    ranks := new CliBatchDuplicateIdRankTable { IdRanks: idRanks, UniqueIdCount: uniqueIdCount }
    scratch := new CliBatchDuplicateScratchTable { CountsByRank: countsByRank, ResultRanks: resultRanks }
    return CliBatchDuplicateIdRanksCore(ref ranks, ref scratch)
}

func CliBatchDuplicateIdRanksCore(ranks: &CliBatchDuplicateIdRankTable, scratch: &CliBatchDuplicateScratchTable): int {
    clearCount := ranks.UniqueIdCount + 1
    if clearCount > scratch.CountsByRank.Length {
        clearCount = scratch.CountsByRank.Length
    }

    i := 0
    while i < clearCount {
        scratch.CountsByRank[i] = 0
        i = i + 1
    }

    i = 0
    while i < ranks.IdRanks.Length {
        rank := ranks.IdRanks[i]
        if rank > 0 && rank <= ranks.UniqueIdCount && rank < scratch.CountsByRank.Length {
            scratch.CountsByRank[rank] = scratch.CountsByRank[rank] + 1
        }

        i = i + 1
    }

    duplicateCount := 0
    rank := 1
    while rank <= ranks.UniqueIdCount && rank < scratch.CountsByRank.Length {
        if scratch.CountsByRank[rank] > 1 {
            if duplicateCount < scratch.ResultRanks.Length {
                scratch.ResultRanks[duplicateCount] = rank
            }

            duplicateCount = duplicateCount + 1
        }

        rank = rank + 1
    }

    return duplicateCount
}

func CliBatchResultPackedSuccessCount(okWords: ulong[], itemCount: int): int {
    results := new CliBatchResultWordTable { OkWords: okWords, ItemCount: itemCount }
    return CliBatchResultPackedSuccessCountCore(ref results)
}

func CliBatchResultPackedSuccessCountCore(results: &CliBatchResultWordTable): int {
    if results.ItemCount <= 0 {
        return 0
    }

    fullWordCount := results.ItemCount >> 6
    if fullWordCount > results.OkWords.Length {
        fullWordCount = results.OkWords.Length
    }

    successCount := 0
    i := 0
    while i < fullWordCount {
        successCount = successCount + CliBatchResultPopCount64(results.OkWords[i])
        i = i + 1
    }

    lastBits := results.ItemCount & 63
    if lastBits != 0 && fullWordCount < results.OkWords.Length {
        shift := 64 - lastBits
        lastWord := (results.OkWords[fullWordCount] << shift) >> shift
        successCount = successCount + CliBatchResultPopCount64(lastWord)
    }

    return successCount
}

func CliBatchResultPopCount64(value: ulong): int {
    return BitOperations.PopCount(value)
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

    return Char.IsWhiteSpace(ch)
}

func CliQueryMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

struct DiagnosticDeduplicationKeyTable {
    CodeIds: int[]
    FileIds: int[]
    LineNumbers: int[]
    Columns: int[]
    MessageIds: int[]
}

struct ReferenceDeduplicationKeyTable {
    FileIds: int[]
    LineNumbers: int[]
    Columns: int[]
}

struct DeduplicationIndexScratchTable {
    SlotIndices: int[]
    ResultIndices: int[]
}

struct DeduplicationRankInputTable {
    Ranks: int[]
}

struct DeduplicationRankCountTable {
    Counts: int[]
}

struct DeduplicationRankResultTable {
    Ranks: int[]
}

struct DeduplicationRankSeenTable {
    Seen: int[]
}

struct DeduplicationIndexResultTable {
    Indices: int[]
}

func DiagnosticDeduplicationKeyCount(keys: &DiagnosticDeduplicationKeyTable): int {
    count := DiagnosticDeduplicationMinInt(keys.CodeIds.Length, keys.FileIds.Length)
    count = DiagnosticDeduplicationMinInt(count, keys.LineNumbers.Length)
    count = DiagnosticDeduplicationMinInt(count, keys.Columns.Length)
    count = DiagnosticDeduplicationMinInt(count, keys.MessageIds.Length)
    return count
}

func ReferenceDeduplicationKeyCount(keys: &ReferenceDeduplicationKeyTable): int {
    count := DiagnosticDeduplicationMinInt(keys.FileIds.Length, keys.LineNumbers.Length)
    count = DiagnosticDeduplicationMinInt(count, keys.Columns.Length)
    return count
}

func DiagnosticDeduplicateCompactInto(
    codeIds: int[],
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    messageIds: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    keys := new DiagnosticDeduplicationKeyTable { CodeIds: codeIds, FileIds: fileRanks, LineNumbers: lineNumbers, Columns: columns, MessageIds: messageIds }
    scratch := new DeduplicationIndexScratchTable { SlotIndices: slotIndices, ResultIndices: resultIndices }
    return DiagnosticDeduplicateIntoCore(ref keys, ref scratch, true)
}

func DiagnosticDeduplicateIntoCore(
    keys: &DiagnosticDeduplicationKeyTable,
    scratch: &DeduplicationIndexScratchTable,
    sortResults: bool): int {
    count := DiagnosticDeduplicationKeyCount(ref keys)

    maxResults := scratch.ResultIndices.Length
    capacity := scratch.SlotIndices.Length
    if count == 0 || maxResults == 0 || capacity == 0 {
        return 0
    }

    i := 0
    while i < capacity {
        scratch.SlotIndices[i] = -1
        i = i + 1
    }

    uniqueCount := 0
    index := 0
    while index < count {
        hash := HashDiagnosticDeduplicationKey(
            keys.CodeIds[index],
            keys.FileIds[index],
            keys.LineNumbers[index],
            keys.Columns[index],
            keys.MessageIds[index])
        slot := DiagnosticDeduplicationPositiveModulo(hash, capacity)
        probes := 0
        duplicate := false

        while probes < capacity {
            candidateIndex := scratch.SlotIndices[slot]
            if candidateIndex < 0 {
                break
            }

            if DiagnosticDeduplicationKeysEqualCore(index, candidateIndex, ref keys) {
                duplicate = true
                break
            }

            slot = slot + 1
            if slot == capacity {
                slot = 0
            }
            probes = probes + 1
        }

        if !duplicate {
            if uniqueCount >= maxResults || probes >= capacity {
                if sortResults {
                    earlySortKeys := new ReferenceDeduplicationKeyTable { FileIds: keys.FileIds, LineNumbers: keys.LineNumbers, Columns: keys.Columns }
                    SortDiagnosticDeduplicationIndicesCore(ref scratch, uniqueCount, ref earlySortKeys)
                }

                return uniqueCount
            }

            scratch.SlotIndices[slot] = index
            scratch.ResultIndices[uniqueCount] = index
            uniqueCount = uniqueCount + 1
        }

        index = index + 1
    }

    if sortResults {
        finalSortKeys := new ReferenceDeduplicationKeyTable { FileIds: keys.FileIds, LineNumbers: keys.LineNumbers, Columns: keys.Columns }
        SortDiagnosticDeduplicationIndicesCore(ref scratch, uniqueCount, ref finalSortKeys)
    }

    return uniqueCount
}

func DiagnosticDeduplicateStableInto(
    codeIds: int[],
    fileIds: int[],
    lineNumbers: int[],
    columns: int[],
    messageIds: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    keys := new DiagnosticDeduplicationKeyTable { CodeIds: codeIds, FileIds: fileIds, LineNumbers: lineNumbers, Columns: columns, MessageIds: messageIds }
    scratch := new DeduplicationIndexScratchTable { SlotIndices: slotIndices, ResultIndices: resultIndices }
    return DiagnosticDeduplicateIntoCore(ref keys, ref scratch, false)
}

func ReferenceDeduplicateCompactInto(
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    keys := new ReferenceDeduplicationKeyTable { FileIds: fileRanks, LineNumbers: lineNumbers, Columns: columns }
    scratch := new DeduplicationIndexScratchTable { SlotIndices: slotIndices, ResultIndices: resultIndices }
    return ReferenceDeduplicateCompactCore(ref keys, ref scratch)
}

func ReferenceDeduplicateCompactCore(
    keys: &ReferenceDeduplicationKeyTable,
    scratch: &DeduplicationIndexScratchTable): int {
    count := ReferenceDeduplicationKeyCount(ref keys)

    maxResults := scratch.ResultIndices.Length
    capacity := scratch.SlotIndices.Length
    if count == 0 || maxResults == 0 || capacity == 0 {
        return 0
    }

    i := 0
    while i < capacity {
        scratch.SlotIndices[i] = -1
        i = i + 1
    }

    uniqueCount := 0
    index := 0
    while index < count {
        hash := HashReferenceDeduplicationKey(
            keys.FileIds[index],
            keys.LineNumbers[index],
            keys.Columns[index])
        slot := DiagnosticDeduplicationPositiveModulo(hash, capacity)
        probes := 0
        duplicate := false

        while probes < capacity {
            candidateIndex := scratch.SlotIndices[slot]
            if candidateIndex < 0 {
                break
            }

            if ReferenceDeduplicationKeysEqualCore(index, candidateIndex, ref keys) {
                duplicate = true
                break
            }

            slot = slot + 1
            if slot == capacity {
                slot = 0
            }
            probes = probes + 1
        }

        if !duplicate {
            if uniqueCount >= maxResults || probes >= capacity {
                SortDiagnosticDeduplicationIndicesCore(ref scratch, uniqueCount, ref keys)
                return uniqueCount
            }

            scratch.SlotIndices[slot] = index
            scratch.ResultIndices[uniqueCount] = index
            uniqueCount = uniqueCount + 1
        }

        index = index + 1
    }

    SortDiagnosticDeduplicationIndicesCore(ref scratch, uniqueCount, ref keys)
    return uniqueCount
}

func ReferenceFileSummaryRanksInto(
    fileRanks: int[],
    uniqueFileCount: int,
    countsByRank: int[],
    resultRanks: int[]): int {
    ranks := new DeduplicationRankInputTable { Ranks: fileRanks }
    counts := new DeduplicationRankCountTable { Counts: countsByRank }
    result := new DeduplicationRankResultTable { Ranks: resultRanks }
    return ReferenceFileSummaryRanksCore(ref ranks, uniqueFileCount, ref counts, ref result)
}

func ReferenceFileSummaryRanksCore(
    ranks: &DeduplicationRankInputTable,
    uniqueFileCount: int,
    counts: &DeduplicationRankCountTable,
    result: &DeduplicationRankResultTable): int {
    clearCount := uniqueFileCount + 1
    if clearCount > counts.Counts.Length {
        clearCount = counts.Counts.Length
    }

    i := 0
    while i < clearCount {
        counts.Counts[i] = 0
        i = i + 1
    }

    i = 0
    while i < ranks.Ranks.Length {
        rank := ranks.Ranks[i]
        if rank > 0 && rank <= uniqueFileCount && rank < counts.Counts.Length {
            counts.Counts[rank] = counts.Counts[rank] + 1
        }

        i = i + 1
    }

    resultCount := 0
    rank := 1
    while rank <= uniqueFileCount && rank < counts.Counts.Length {
        if counts.Counts[rank] > 0 {
            if resultCount < result.Ranks.Length {
                result.Ranks[resultCount] = rank
            }

            resultCount = resultCount + 1
        }

        rank = rank + 1
    }

    return resultCount
}

func FirstDistinctRankIndicesInto(
    ranks: int[],
    uniqueRankCount: int,
    seenRanks: int[],
    resultIndices: int[]): int {
    rankInput := new DeduplicationRankInputTable { Ranks: ranks }
    seen := new DeduplicationRankSeenTable { Seen: seenRanks }
    result := new DeduplicationIndexResultTable { Indices: resultIndices }
    return FirstDistinctRankIndicesCore(ref rankInput, uniqueRankCount, ref seen, ref result)
}

func FirstDistinctRankIndicesCore(
    ranks: &DeduplicationRankInputTable,
    uniqueRankCount: int,
    seen: &DeduplicationRankSeenTable,
    result: &DeduplicationIndexResultTable): int {
    clearCount := uniqueRankCount + 1
    if clearCount > seen.Seen.Length {
        clearCount = seen.Seen.Length
    }

    i := 0
    while i < clearCount {
        seen.Seen[i] = 0
        i = i + 1
    }

    resultCount := 0
    i = 0
    while i < ranks.Ranks.Length {
        rank := ranks.Ranks[i]
        if rank > 0 && rank <= uniqueRankCount && rank < seen.Seen.Length {
            if seen.Seen[rank] == 0 {
                seen.Seen[rank] = 1
                if resultCount < result.Indices.Length {
                    result.Indices[resultCount] = i
                }

                resultCount = resultCount + 1
            }
        }

        i = i + 1
    }

    return resultCount
}

func HashDiagnosticDeduplicationKey(
    codeId: int,
    fileId: int,
    line: int,
    column: int,
    messageId: int): int {
    hash := 17
    hash = hash * 31 + codeId
    hash = hash * 31 + fileId
    hash = hash * 31 + line
    hash = hash * 31 + column
    hash = hash * 31 + messageId
    return hash
}

func HashReferenceDeduplicationKey(
    fileId: int,
    line: int,
    column: int): int {
    hash := 17
    hash = hash * 31 + fileId
    hash = hash * 31 + line
    hash = hash * 31 + column
    return hash
}

func DiagnosticDeduplicationKeysEqualCore(
    left: int,
    right: int,
    keys: &DiagnosticDeduplicationKeyTable): bool {
    return keys.CodeIds[left] == keys.CodeIds[right]
        && keys.FileIds[left] == keys.FileIds[right]
        && keys.LineNumbers[left] == keys.LineNumbers[right]
        && keys.Columns[left] == keys.Columns[right]
        && keys.MessageIds[left] == keys.MessageIds[right]
}

func ReferenceDeduplicationKeysEqualCore(
    left: int,
    right: int,
    keys: &ReferenceDeduplicationKeyTable): bool {
    return keys.FileIds[left] == keys.FileIds[right]
        && keys.LineNumbers[left] == keys.LineNumbers[right]
        && keys.Columns[left] == keys.Columns[right]
}

func SortDiagnosticDeduplicationIndicesCore(
    scratch: &DeduplicationIndexScratchTable,
    count: int,
    keys: &ReferenceDeduplicationKeyTable): void {
    if count < 2 {
        return
    }

    start := count / 2 - 1
    while start >= 0 {
        SiftDownDiagnosticDeduplicationIndicesCore(ref scratch, start, count - 1, ref keys)
        start = start - 1
    }

    end := count - 1
    while end > 0 {
        temp := scratch.ResultIndices[end]
        scratch.ResultIndices[end] = scratch.ResultIndices[0]
        scratch.ResultIndices[0] = temp

        end = end - 1
        SiftDownDiagnosticDeduplicationIndicesCore(ref scratch, 0, end, ref keys)
    }
}

func SiftDownDiagnosticDeduplicationIndicesCore(
    scratch: &DeduplicationIndexScratchTable,
    start: int,
    end: int,
    keys: &ReferenceDeduplicationKeyTable): void {
    root := start

    while root * 2 + 1 <= end {
        child := root * 2 + 1
        swapIndex := root

        if IsDiagnosticDeduplicationIndexBeforeCore(scratch.ResultIndices[swapIndex], scratch.ResultIndices[child], ref keys) {
            swapIndex = child
        }

        if child + 1 <= end && IsDiagnosticDeduplicationIndexBeforeCore(scratch.ResultIndices[swapIndex], scratch.ResultIndices[child + 1], ref keys) {
            swapIndex = child + 1
        }

        if swapIndex == root {
            return
        }

        temp := scratch.ResultIndices[root]
        scratch.ResultIndices[root] = scratch.ResultIndices[swapIndex]
        scratch.ResultIndices[swapIndex] = temp
        root = swapIndex
    }
}

func IsDiagnosticDeduplicationIndexBeforeCore(
    left: int,
    right: int,
    keys: &ReferenceDeduplicationKeyTable): bool {
    if keys.FileIds[left] != keys.FileIds[right] {
        return keys.FileIds[left] < keys.FileIds[right]
    }

    if keys.LineNumbers[left] != keys.LineNumbers[right] {
        return keys.LineNumbers[left] < keys.LineNumbers[right]
    }

    if keys.Columns[left] != keys.Columns[right] {
        return keys.Columns[left] < keys.Columns[right]
    }

    return left < right
}

func DiagnosticDeduplicationPositiveModulo(value: int, divisor: int): int {
    result := value % divisor
    if result < 0 {
        return result + divisor
    }

    return result
}

func DiagnosticDeduplicationMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

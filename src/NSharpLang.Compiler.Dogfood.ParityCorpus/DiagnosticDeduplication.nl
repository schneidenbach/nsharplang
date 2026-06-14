// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/DiagnosticDeduplication.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func SortDiagnosticDeduplicationIndices(
    resultIndices: int[],
    count: int,
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[]): void {
    keys := new ReferenceDeduplicationKeyTable { FileIds: fileRanks, LineNumbers: lineNumbers, Columns: columns }
    SortDiagnosticDeduplicationIndicesCore(resultIndices, count, ref keys)
}

func DiagnosticDeduplicateCompactChecksumInto(
    codeIds: int[],
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    messageIds: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    uniqueCount := DiagnosticDeduplicateCompactInto(
        codeIds,
        fileRanks,
        lineNumbers,
        columns,
        messageIds,
        slotIndices,
        resultIndices)

    checksum := uniqueCount
    i := 0
    while i < uniqueCount {
        index := resultIndices[i]
        checksum = checksum + (index + 1) * 31 + lineNumbers[index] * 17 + columns[index] * 13
        i = i + 1
    }

    return checksum
}

func DiagnosticDeduplicateStableChecksumInto(
    codeIds: int[],
    fileIds: int[],
    lineNumbers: int[],
    columns: int[],
    messageIds: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    uniqueCount := DiagnosticDeduplicateStableInto(
        codeIds,
        fileIds,
        lineNumbers,
        columns,
        messageIds,
        slotIndices,
        resultIndices)

    checksum := uniqueCount
    i := 0
    while i < uniqueCount {
        index := resultIndices[i]
        checksum = checksum + (index + 1) * 31 + lineNumbers[index] * 17 + columns[index] * 13
        i = i + 1
    }

    return checksum
}

func ReferenceDeduplicateCompactChecksumInto(
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    slotIndices: int[],
    resultIndices: int[]): int {
    uniqueCount := ReferenceDeduplicateCompactInto(
        fileRanks,
        lineNumbers,
        columns,
        slotIndices,
        resultIndices)

    checksum := uniqueCount
    i := 0
    while i < uniqueCount {
        index := resultIndices[i]
        checksum = checksum + (index + 1) * 31 + lineNumbers[index] * 17 + columns[index] * 13
        i = i + 1
    }

    return checksum
}

func ReferenceFileSummaryChecksumInto(
    fileRanks: int[],
    uniqueFileCount: int,
    countsByRank: int[],
    resultRanks: int[],
    fileLengthsByRank: int[]): int {
    resultCount := ReferenceFileSummaryRanksInto(
        fileRanks,
        uniqueFileCount,
        countsByRank,
        resultRanks)

    checksum := resultCount
    i := 0
    while i < resultCount && i < resultRanks.Length {
        rank := resultRanks[i]
        length := 0
        if rank >= 0 && rank < fileLengthsByRank.Length {
            length = fileLengthsByRank[rank]
        }

        checksum = checksum + rank * 31 + length * 17 + (i + 1) * 13
        i = i + 1
    }

    return checksum
}

func FirstDistinctRankChecksumInto(
    ranks: int[],
    uniqueRankCount: int,
    seenRanks: int[],
    resultIndices: int[],
    rankWeights: int[]): int {
    resultCount := FirstDistinctRankIndicesInto(
        ranks,
        uniqueRankCount,
        seenRanks,
        resultIndices)

    checksum := resultCount
    i := 0
    while i < resultCount && i < resultIndices.Length {
        sourceIndex := resultIndices[i]
        rank := 0
        weight := 0
        if sourceIndex >= 0 && sourceIndex < ranks.Length {
            rank = ranks[sourceIndex]
            if rank >= 0 && rank < rankWeights.Length {
                weight = rankWeights[rank]
            }
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + rank * 17 + weight * 13
        i = i + 1
    }

    return checksum
}

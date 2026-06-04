func CliDocSymbolOrderCountingIndicesInto(
    kindRanks: int[],
    nameRanks: int[],
    includeFlags: int[],
    nameCounts: int[],
    nameOffsets: int[],
    kindCounts: int[],
    kindOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    count := CliDocOrderingMinInt(kindRanks.Length, nameRanks.Length)
    count = CliDocOrderingMinInt(count, includeFlags.Length)
    nameBucketCount := CliDocOrderingMinInt(nameCounts.Length, nameOffsets.Length)
    kindBucketCount := CliDocOrderingMinInt(kindCounts.Length, kindOffsets.Length)

    i := 0
    while i < nameBucketCount {
        nameCounts[i] = 0
        nameOffsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < kindBucketCount {
        kindCounts[i] = 0
        kindOffsets[i] = 0
        i = i + 1
    }

    includedCount := 0
    i = 0
    while i < count {
        if includeFlags[i] != 0 {
            nameRank := nameRanks[i]
            kindRank := kindRanks[i]
            if nameRank <= 0 || nameRank >= nameBucketCount || kindRank <= 0 || kindRank >= kindBucketCount {
                return -1
            }

            if includedCount >= tempIndices.Length || includedCount >= resultIndices.Length {
                return -1
            }

            nameCounts[nameRank] = nameCounts[nameRank] + 1
            kindCounts[kindRank] = kindCounts[kindRank] + 1
            includedCount = includedCount + 1
        }

        i = i + 1
    }

    offset := 0
    rank := 0
    while rank < nameBucketCount {
        nameOffsets[rank] = offset
        offset = offset + nameCounts[rank]
        rank = rank + 1
    }

    i = 0
    while i < count {
        if includeFlags[i] != 0 {
            nameRank := nameRanks[i]
            writeIndex := nameOffsets[nameRank]
            tempIndices[writeIndex] = i
            nameOffsets[nameRank] = writeIndex + 1
        }

        i = i + 1
    }

    offset = 0
    rank = 0
    while rank < kindBucketCount {
        kindOffsets[rank] = offset
        offset = offset + kindCounts[rank]
        rank = rank + 1
    }

    i = 0
    while i < includedCount {
        sourceIndex := tempIndices[i]
        kindRank := kindRanks[sourceIndex]
        writeIndex := kindOffsets[kindRank]
        resultIndices[writeIndex] = sourceIndex
        kindOffsets[kindRank] = writeIndex + 1
        i = i + 1
    }

    return includedCount
}

func CliDocSymbolOrderCountingChecksumInto(
    kindRanks: int[],
    nameRanks: int[],
    includeFlags: int[],
    nameCounts: int[],
    nameOffsets: int[],
    kindCounts: int[],
    kindOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    orderedCount := CliDocSymbolOrderCountingIndicesInto(
        kindRanks,
        nameRanks,
        includeFlags,
        nameCounts,
        nameOffsets,
        kindCounts,
        kindOffsets,
        tempIndices,
        resultIndices)
    checksum := orderedCount

    i := 0
    while i < orderedCount {
        index := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + kindRanks[index] * 17 + nameRanks[index] * 13
        i = i + 1
    }

    return checksum
}

func CliDocOrderingMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

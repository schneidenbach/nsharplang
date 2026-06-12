func CliTreeDependencyDeduplicateIndicesInto(
    kindRanks: int[],
    nameRanks: int[],
    nameCounts: int[],
    nameOffsets: int[],
    kindCounts: int[],
    kindOffsets: int[],
    tempIndices: int[],
    sortedIndices: int[],
    resultIndices: int[]): int {
    count := CliTreeMinInt(kindRanks.Length, nameRanks.Length)
    nameBucketCount := CliTreeMinInt(nameCounts.Length, nameOffsets.Length)
    kindBucketCount := CliTreeMinInt(kindCounts.Length, kindOffsets.Length)

    if count > tempIndices.Length || count > sortedIndices.Length || count > resultIndices.Length {
        return -1
    }

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

    i = 0
    while i < count {
        nameRank := nameRanks[i]
        kindRank := kindRanks[i]
        if nameRank <= 0 || nameRank >= nameBucketCount || kindRank <= 0 || kindRank >= kindBucketCount {
            return -1
        }

        nameCounts[nameRank] = nameCounts[nameRank] + 1
        kindCounts[kindRank] = kindCounts[kindRank] + 1
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
        nameRank := nameRanks[i]
        writeIndex := nameOffsets[nameRank]
        tempIndices[writeIndex] = i
        nameOffsets[nameRank] = writeIndex + 1
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
    while i < count {
        sourceIndex := tempIndices[i]
        kindRank := kindRanks[sourceIndex]
        writeIndex := kindOffsets[kindRank]
        sortedIndices[writeIndex] = sourceIndex
        kindOffsets[kindRank] = writeIndex + 1
        i = i + 1
    }

    uniqueCount := 0
    previousKindRank := -1
    previousNameRank := -1
    i = 0
    while i < count {
        sourceIndex := sortedIndices[i]
        kindRank := kindRanks[sourceIndex]
        nameRank := nameRanks[sourceIndex]
        if i == 0 || kindRank != previousKindRank || nameRank != previousNameRank {
            resultIndices[uniqueCount] = sourceIndex
            uniqueCount = uniqueCount + 1
            previousKindRank = kindRank
            previousNameRank = nameRank
        }

        i = i + 1
    }

    return uniqueCount
}

func CliTreeMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

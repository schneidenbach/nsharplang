func TextEditOrderIndicesInto(
    startPositionRanks: int[],
    endPositionRanks: int[],
    startPositionRankCount: int,
    endPositionRankCount: int,
    bucketCounts: int[],
    bucketOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    count := TextEditOrderMinInt(startPositionRanks.Length, endPositionRanks.Length)

    if count > tempIndices.Length || count > resultIndices.Length {
        return -1
    }

    i := 0
    while i < count {
        resultIndices[i] = count - i - 1
        i = i + 1
    }

    passResult := TextEditOrderCountingPass(
        resultIndices,
        tempIndices,
        count,
        endPositionRanks,
        endPositionRankCount,
        bucketCounts,
        bucketOffsets,
        0)
    if passResult < 0 {
        return -1
    }

    passResult = TextEditOrderCountingPass(
        tempIndices,
        resultIndices,
        count,
        startPositionRanks,
        startPositionRankCount,
        bucketCounts,
        bucketOffsets,
        1)
    if passResult < 0 {
        return -1
    }

    return count
}

func TextEditOrderChecksumInto(
    startPositionRanks: int[],
    endPositionRanks: int[],
    startPositionRankCount: int,
    endPositionRankCount: int,
    bucketCounts: int[],
    bucketOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    count := TextEditOrderIndicesInto(
        startPositionRanks,
        endPositionRanks,
        startPositionRankCount,
        endPositionRankCount,
        bucketCounts,
        bucketOffsets,
        tempIndices,
        resultIndices)

    checksum := count
    i := 0
    while i < count {
        index := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (index + 1) * 31
        checksum = checksum + startPositionRanks[index] * 17 + endPositionRanks[index] * 13
        i = i + 1
    }

    return checksum
}

func TextEditOrderCountingPass(
    sourceIndices: int[],
    targetIndices: int[],
    count: int,
    ranks: int[],
    rankCount: int,
    bucketCounts: int[],
    bucketOffsets: int[],
    descending: int): int {
    bucketCapacity := TextEditOrderMinInt(bucketCounts.Length, bucketOffsets.Length)
    if rankCount <= 0 || rankCount + 1 > bucketCapacity || count > sourceIndices.Length || count > targetIndices.Length {
        return -1
    }

    i := 0
    while i <= rankCount {
        bucketCounts[i] = 0
        bucketOffsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < count {
        sourceIndex := sourceIndices[i]
        if sourceIndex < 0 || sourceIndex >= ranks.Length {
            return -1
        }

        rank := ranks[sourceIndex]
        if rank <= 0 || rank > rankCount {
            return -1
        }

        bucket := rank
        if descending != 0 {
            bucket = rankCount - rank + 1
        }

        bucketCounts[bucket] = bucketCounts[bucket] + 1
        i = i + 1
    }

    offset := 0
    bucketIndex := 0
    while bucketIndex <= rankCount {
        bucketOffsets[bucketIndex] = offset
        offset = offset + bucketCounts[bucketIndex]
        bucketIndex = bucketIndex + 1
    }

    i = 0
    while i < count {
        sourceIndex := sourceIndices[i]
        rank := ranks[sourceIndex]
        bucket := rank
        if descending != 0 {
            bucket = rankCount - rank + 1
        }

        writeIndex := bucketOffsets[bucket]
        targetIndices[writeIndex] = sourceIndex
        bucketOffsets[bucket] = writeIndex + 1
        i = i + 1
    }

    return count
}

func TextEditOrderMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

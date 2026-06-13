struct TextEditOrderRankTable {
    Ranks: int[]
    RankCount: int
}

struct TextEditOrderBucketTable {
    Counts: int[]
    Offsets: int[]
}

struct TextEditOrderIndexTable {
    Indices: int[]
}

func TextEditOrderIndicesInto(
    startPositionRanks: int[],
    endPositionRanks: int[],
    startPositionRankCount: int,
    endPositionRankCount: int,
    bucketCounts: int[],
    bucketOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    startRanks := new TextEditOrderRankTable { Ranks: startPositionRanks, RankCount: startPositionRankCount }
    endRanks := new TextEditOrderRankTable { Ranks: endPositionRanks, RankCount: endPositionRankCount }
    buckets := new TextEditOrderBucketTable { Counts: bucketCounts, Offsets: bucketOffsets }
    temp := new TextEditOrderIndexTable { Indices: tempIndices }
    result := new TextEditOrderIndexTable { Indices: resultIndices }
    return TextEditOrderIndicesCore(ref startRanks, ref endRanks, ref buckets, ref temp, ref result)
}

func TextEditOrderIndicesCore(
    startRanks: &TextEditOrderRankTable,
    endRanks: &TextEditOrderRankTable,
    buckets: &TextEditOrderBucketTable,
    temp: &TextEditOrderIndexTable,
    result: &TextEditOrderIndexTable): int {
    count := TextEditOrderMinInt(startRanks.Ranks.Length, endRanks.Ranks.Length)

    if count > temp.Indices.Length || count > result.Indices.Length {
        return -1
    }

    i := 0
    while i < count {
        result.Indices[i] = count - i - 1
        i = i + 1
    }

    passResult := TextEditOrderCountingPassCore(ref result, ref temp, count, ref endRanks, ref buckets, 0)
    if passResult < 0 {
        return -1
    }

    passResult = TextEditOrderCountingPassCore(ref temp, ref result, count, ref startRanks, ref buckets, 1)
    if passResult < 0 {
        return -1
    }

    return count
}

func TextEditOrderCountingPassCore(
    source: &TextEditOrderIndexTable,
    target: &TextEditOrderIndexTable,
    count: int,
    rankTable: &TextEditOrderRankTable,
    buckets: &TextEditOrderBucketTable,
    descending: int): int {
    bucketCapacity := TextEditOrderMinInt(buckets.Counts.Length, buckets.Offsets.Length)
    if rankTable.RankCount <= 0 || rankTable.RankCount + 1 > bucketCapacity || count > source.Indices.Length || count > target.Indices.Length {
        return -1
    }

    i := 0
    while i <= rankTable.RankCount {
        buckets.Counts[i] = 0
        buckets.Offsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < count {
        sourceIndex := source.Indices[i]
        if sourceIndex < 0 || sourceIndex >= rankTable.Ranks.Length {
            return -1
        }

        rank := rankTable.Ranks[sourceIndex]
        if rank <= 0 || rank > rankTable.RankCount {
            return -1
        }

        bucket := rank
        if descending != 0 {
            bucket = rankTable.RankCount - rank + 1
        }

        buckets.Counts[bucket] = buckets.Counts[bucket] + 1
        i = i + 1
    }

    offset := 0
    bucketIndex := 0
    while bucketIndex <= rankTable.RankCount {
        buckets.Offsets[bucketIndex] = offset
        offset = offset + buckets.Counts[bucketIndex]
        bucketIndex = bucketIndex + 1
    }

    i = 0
    while i < count {
        sourceIndex := source.Indices[i]
        rank := rankTable.Ranks[sourceIndex]
        bucket := rank
        if descending != 0 {
            bucket = rankTable.RankCount - rank + 1
        }

        writeIndex := buckets.Offsets[bucket]
        target.Indices[writeIndex] = sourceIndex
        buckets.Offsets[bucket] = writeIndex + 1
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

struct CliTreeDependencyRankTable {
    KindRanks: int[]
    NameRanks: int[]
}

struct CliTreeDependencyBucketTable {
    Counts: int[]
    Offsets: int[]
}

struct CliTreeDependencyIndexTable {
    Indices: int[]
}

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
    ranks := new CliTreeDependencyRankTable { KindRanks: kindRanks, NameRanks: nameRanks }
    nameBuckets := new CliTreeDependencyBucketTable { Counts: nameCounts, Offsets: nameOffsets }
    kindBuckets := new CliTreeDependencyBucketTable { Counts: kindCounts, Offsets: kindOffsets }
    temp := new CliTreeDependencyIndexTable { Indices: tempIndices }
    sorted := new CliTreeDependencyIndexTable { Indices: sortedIndices }
    result := new CliTreeDependencyIndexTable { Indices: resultIndices }
    return CliTreeDependencyDeduplicateIndicesCore(ref ranks, ref nameBuckets, ref kindBuckets, ref temp, ref sorted, ref result)
}

func CliTreeDependencyDeduplicateIndicesCore(
    ranks: &CliTreeDependencyRankTable,
    nameBuckets: &CliTreeDependencyBucketTable,
    kindBuckets: &CliTreeDependencyBucketTable,
    temp: &CliTreeDependencyIndexTable,
    sorted: &CliTreeDependencyIndexTable,
    result: &CliTreeDependencyIndexTable): int {
    count := CliTreeMinInt(ranks.KindRanks.Length, ranks.NameRanks.Length)
    nameBucketCount := CliTreeMinInt(nameBuckets.Counts.Length, nameBuckets.Offsets.Length)
    kindBucketCount := CliTreeMinInt(kindBuckets.Counts.Length, kindBuckets.Offsets.Length)

    if count > temp.Indices.Length || count > sorted.Indices.Length || count > result.Indices.Length {
        return -1
    }

    i := 0
    while i < nameBucketCount {
        nameBuckets.Counts[i] = 0
        nameBuckets.Offsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < kindBucketCount {
        kindBuckets.Counts[i] = 0
        kindBuckets.Offsets[i] = 0
        i = i + 1
    }

    i = 0
    while i < count {
        nameRank := ranks.NameRanks[i]
        kindRank := ranks.KindRanks[i]
        if nameRank <= 0 || nameRank >= nameBucketCount || kindRank <= 0 || kindRank >= kindBucketCount {
            return -1
        }

        nameBuckets.Counts[nameRank] = nameBuckets.Counts[nameRank] + 1
        kindBuckets.Counts[kindRank] = kindBuckets.Counts[kindRank] + 1
        i = i + 1
    }

    offset := 0
    rank := 0
    while rank < nameBucketCount {
        nameBuckets.Offsets[rank] = offset
        offset = offset + nameBuckets.Counts[rank]
        rank = rank + 1
    }

    i = 0
    while i < count {
        nameRank := ranks.NameRanks[i]
        writeIndex := nameBuckets.Offsets[nameRank]
        temp.Indices[writeIndex] = i
        nameBuckets.Offsets[nameRank] = writeIndex + 1
        i = i + 1
    }

    offset = 0
    rank = 0
    while rank < kindBucketCount {
        kindBuckets.Offsets[rank] = offset
        offset = offset + kindBuckets.Counts[rank]
        rank = rank + 1
    }

    i = 0
    while i < count {
        sourceIndex := temp.Indices[i]
        kindRank := ranks.KindRanks[sourceIndex]
        writeIndex := kindBuckets.Offsets[kindRank]
        sorted.Indices[writeIndex] = sourceIndex
        kindBuckets.Offsets[kindRank] = writeIndex + 1
        i = i + 1
    }

    uniqueCount := 0
    previousKindRank := -1
    previousNameRank := -1
    i = 0
    while i < count {
        sourceIndex := sorted.Indices[i]
        kindRank := ranks.KindRanks[sourceIndex]
        nameRank := ranks.NameRanks[sourceIndex]
        if i == 0 || kindRank != previousKindRank || nameRank != previousNameRank {
            result.Indices[uniqueCount] = sourceIndex
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

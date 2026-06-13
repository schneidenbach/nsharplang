struct CompletionKindInputTable {
    KindIds: int[]
}

struct CompletionGroupingBucketTable {
    Counts: int[]
    Offsets: int[]
}

struct CompletionKindGroupResultTable {
    KindIds: int[]
    Starts: int[]
    Counts: int[]
    Indices: int[]
}

struct CompletionMethodInputTable {
    NameIds: int[]
    IncludeFlags: int[]
}

struct CompletionNameCountTable {
    Counts: int[]
}

struct CompletionMethodGroupResultTable {
    NameIds: int[]
    FirstIndices: int[]
    Counts: int[]
}

func CompletionItemKindGroupsInto(
    kindIds: int[],
    kindCounts: int[],
    kindOffsets: int[],
    resultKindIds: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultIndices: int[]): int {
    input := new CompletionKindInputTable { KindIds: kindIds }
    buckets := new CompletionGroupingBucketTable { Counts: kindCounts, Offsets: kindOffsets }
    result := new CompletionKindGroupResultTable { KindIds: resultKindIds, Starts: resultStarts, Counts: resultCounts, Indices: resultIndices }
    return CompletionItemKindGroupsCore(ref input, ref buckets, ref result)
}

func CompletionItemKindGroupsCore(
    input: &CompletionKindInputTable,
    buckets: &CompletionGroupingBucketTable,
    result: &CompletionKindGroupResultTable): int {
    count := CompletionGroupingMinInt(input.KindIds.Length, result.Indices.Length)
    bucketCount := CompletionGroupingMinInt(buckets.Counts.Length, buckets.Offsets.Length)

    i := 0
    while i < bucketCount {
        buckets.Counts[i] = 0
        buckets.Offsets[i] = 0
        i = i + 1
    }

    groupCount := 0
    i = 0
    while i < count {
        kindId := input.KindIds[i]
        if kindId <= 0 || kindId >= bucketCount {
            return -1
        }

        if buckets.Counts[kindId] == 0 {
            if groupCount >= result.KindIds.Length
                || groupCount >= result.Starts.Length
                || groupCount >= result.Counts.Length {
                return -1
            }

            result.KindIds[groupCount] = kindId
            groupCount = groupCount + 1
        }

        buckets.Counts[kindId] = buckets.Counts[kindId] + 1
        i = i + 1
    }

    offset := 0
    groupIndex := 0
    while groupIndex < groupCount {
        kindId := result.KindIds[groupIndex]
        result.Starts[groupIndex] = offset
        result.Counts[groupIndex] = buckets.Counts[kindId]
        buckets.Offsets[kindId] = offset
        offset = offset + buckets.Counts[kindId]
        groupIndex = groupIndex + 1
    }

    i = 0
    while i < count {
        kindId := input.KindIds[i]
        writeIndex := buckets.Offsets[kindId]
        if writeIndex < 0 || writeIndex >= result.Indices.Length {
            return -1
        }

        result.Indices[writeIndex] = i
        buckets.Offsets[kindId] = writeIndex + 1
        i = i + 1
    }

    return groupCount
}

func CompletionMethodOverloadGroupsInto(
    nameIds: int[],
    includeFlags: int[],
    nameCounts: int[],
    resultNameIds: int[],
    resultFirstIndices: int[],
    resultCounts: int[]): int {
    input := new CompletionMethodInputTable { NameIds: nameIds, IncludeFlags: includeFlags }
    buckets := new CompletionNameCountTable { Counts: nameCounts }
    result := new CompletionMethodGroupResultTable { NameIds: resultNameIds, FirstIndices: resultFirstIndices, Counts: resultCounts }
    return CompletionMethodOverloadGroupsCore(ref input, ref buckets, ref result)
}

func CompletionMethodOverloadGroupsCore(
    input: &CompletionMethodInputTable,
    buckets: &CompletionNameCountTable,
    result: &CompletionMethodGroupResultTable): int {
    count := CompletionGroupingMinInt(input.NameIds.Length, input.IncludeFlags.Length)
    bucketCount := buckets.Counts.Length

    i := 0
    while i < bucketCount {
        buckets.Counts[i] = 0
        i = i + 1
    }

    groupCount := 0
    i = 0
    while i < count {
        if input.IncludeFlags[i] != 0 {
            nameId := input.NameIds[i]
            if nameId <= 0 || nameId >= bucketCount {
                return -1
            }

            if buckets.Counts[nameId] == 0 {
                if groupCount >= result.NameIds.Length
                    || groupCount >= result.FirstIndices.Length
                    || groupCount >= result.Counts.Length {
                    return -1
                }

                result.NameIds[groupCount] = nameId
                result.FirstIndices[groupCount] = i
                groupCount = groupCount + 1
            }

            buckets.Counts[nameId] = buckets.Counts[nameId] + 1
        }

        i = i + 1
    }

    groupIndex := 0
    while groupIndex < groupCount {
        nameId := result.NameIds[groupIndex]
        result.Counts[groupIndex] = buckets.Counts[nameId]
        groupIndex = groupIndex + 1
    }

    return groupCount
}

func CompletionGroupingMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

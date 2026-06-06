func CompletionItemKindGroupsInto(
    kindIds: int[],
    kindCounts: int[],
    kindOffsets: int[],
    resultKindIds: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultIndices: int[]): int {
    count := CompletionGroupingMinInt(kindIds.Length, resultIndices.Length)
    bucketCount := CompletionGroupingMinInt(kindCounts.Length, kindOffsets.Length)

    i := 0
    while i < bucketCount {
        kindCounts[i] = 0
        kindOffsets[i] = 0
        i = i + 1
    }

    groupCount := 0
    i = 0
    while i < count {
        kindId := kindIds[i]
        if kindId <= 0 || kindId >= bucketCount {
            return -1
        }

        if kindCounts[kindId] == 0 {
            if groupCount >= resultKindIds.Length
                || groupCount >= resultStarts.Length
                || groupCount >= resultCounts.Length {
                return -1
            }

            resultKindIds[groupCount] = kindId
            groupCount = groupCount + 1
        }

        kindCounts[kindId] = kindCounts[kindId] + 1
        i = i + 1
    }

    offset := 0
    groupIndex := 0
    while groupIndex < groupCount {
        kindId := resultKindIds[groupIndex]
        resultStarts[groupIndex] = offset
        resultCounts[groupIndex] = kindCounts[kindId]
        kindOffsets[kindId] = offset
        offset = offset + kindCounts[kindId]
        groupIndex = groupIndex + 1
    }

    i = 0
    while i < count {
        kindId := kindIds[i]
        writeIndex := kindOffsets[kindId]
        if writeIndex < 0 || writeIndex >= resultIndices.Length {
            return -1
        }

        resultIndices[writeIndex] = i
        kindOffsets[kindId] = writeIndex + 1
        i = i + 1
    }

    return groupCount
}

func CompletionItemKindGroupChecksumInto(
    kindIds: int[],
    kindCounts: int[],
    kindOffsets: int[],
    resultKindIds: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultIndices: int[]): int {
    groupCount := CompletionItemKindGroupsInto(
        kindIds,
        kindCounts,
        kindOffsets,
        resultKindIds,
        resultStarts,
        resultCounts,
        resultIndices)
    if groupCount < 0 {
        return groupCount
    }

    checksum := groupCount
    groupIndex := 0
    while groupIndex < groupCount {
        start := resultStarts[groupIndex]
        count := resultCounts[groupIndex]
        kindId := resultKindIds[groupIndex]
        checksum = checksum + kindId * 97 + start * 31 + count * 17

        itemIndex := 0
        while itemIndex < count {
            sourceIndex := resultIndices[start + itemIndex]
            checksum = checksum + (sourceIndex + 1) * 13 + (itemIndex + 1) * 7
            itemIndex = itemIndex + 1
        }

        groupIndex = groupIndex + 1
    }

    return checksum
}

func CompletionMethodOverloadGroupsInto(
    nameIds: int[],
    includeFlags: int[],
    nameCounts: int[],
    resultNameIds: int[],
    resultFirstIndices: int[],
    resultCounts: int[]): int {
    count := CompletionGroupingMinInt(nameIds.Length, includeFlags.Length)
    bucketCount := nameCounts.Length

    i := 0
    while i < bucketCount {
        nameCounts[i] = 0
        i = i + 1
    }

    groupCount := 0
    i = 0
    while i < count {
        if includeFlags[i] != 0 {
            nameId := nameIds[i]
            if nameId <= 0 || nameId >= bucketCount {
                return -1
            }

            if nameCounts[nameId] == 0 {
                if groupCount >= resultNameIds.Length
                    || groupCount >= resultFirstIndices.Length
                    || groupCount >= resultCounts.Length {
                    return -1
                }

                resultNameIds[groupCount] = nameId
                resultFirstIndices[groupCount] = i
                groupCount = groupCount + 1
            }

            nameCounts[nameId] = nameCounts[nameId] + 1
        }

        i = i + 1
    }

    groupIndex := 0
    while groupIndex < groupCount {
        nameId := resultNameIds[groupIndex]
        resultCounts[groupIndex] = nameCounts[nameId]
        groupIndex = groupIndex + 1
    }

    return groupCount
}

func CompletionMethodOverloadGroupChecksumInto(
    nameIds: int[],
    includeFlags: int[],
    nameCounts: int[],
    resultNameIds: int[],
    resultFirstIndices: int[],
    resultCounts: int[]): int {
    groupCount := CompletionMethodOverloadGroupsInto(
        nameIds,
        includeFlags,
        nameCounts,
        resultNameIds,
        resultFirstIndices,
        resultCounts)
    if groupCount < 0 {
        return groupCount
    }

    checksum := groupCount
    groupIndex := 0
    while groupIndex < groupCount {
        checksum = checksum
            + resultNameIds[groupIndex] * 97
            + resultFirstIndices[groupIndex] * 31
            + resultCounts[groupIndex] * 17
            + (groupIndex + 1) * 13
        groupIndex = groupIndex + 1
    }

    return checksum
}

func CompletionGroupingMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

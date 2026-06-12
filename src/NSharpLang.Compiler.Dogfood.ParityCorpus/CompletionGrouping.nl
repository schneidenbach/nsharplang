// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/CompletionGrouping.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

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

// PARITY CORPUS (Arc M1): checksum fixtures extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/DocQuery.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func DocQueryBestTypeChecksumInto(scores: int[], namespaceLengths: int[], fullNames: string[], count: int): int {
    bestIndex := DocQueryBestTypeIndex(scores, namespaceLengths, fullNames, count)
    if bestIndex < 0 {
        return bestIndex
    }

    return (bestIndex + 1) * 97 + scores[bestIndex] * 31 + namespaceLengths[bestIndex] * 17
}

func DocQueryMemberOrderChecksumInto(
    kindRanks: int[],
    nameRanks: int[],
    nameCounts: int[],
    nameOffsets: int[],
    kindCounts: int[],
    kindOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    orderedCount := DocQueryMemberOrderIndicesInto(
        kindRanks,
        nameRanks,
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

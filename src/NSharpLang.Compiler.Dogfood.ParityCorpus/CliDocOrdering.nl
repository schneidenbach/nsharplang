// PARITY CORPUS (Arc M1): checksum fixtures extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/CliDocOrdering.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func CliDocSlugInto(raw: string, length: int, buffer: char[]): string {
    slugBuffer := new CliDocSlugBufferTable { Chars: buffer }
    return CliDocSlugCore(raw, length, ref slugBuffer)
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

func SymbolKindFilterChecksumInto(kindIds: int[], targetKindId: int, resultIndices: int[]): int {
    length := kindIds.Length
    if resultIndices.Length < length {
        filteredCount := SymbolKindFilterIndicesInto(kindIds, targetKindId, resultIndices)
        checksum := filteredCount

        i := 0
        while i < filteredCount {
            index := resultIndices[i]
            checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + kindIds[index] * 17
            i = i + 1
        }

        return checksum
    }

    filteredCount := 0
    checksum := 0
    i := 0
    unrolledLimit := length - 8
    while i <= unrolledLimit {
        if kindIds[i] == targetKindId {
            resultIndices[filteredCount] = i
            checksum = checksum + (filteredCount + 1) * 97 + (i + 1) * 31 + targetKindId * 17
            filteredCount = filteredCount + 1
        }

        next := i + 1
        if kindIds[next] == targetKindId {
            resultIndices[filteredCount] = next
            checksum = checksum + (filteredCount + 1) * 97 + (next + 1) * 31 + targetKindId * 17
            filteredCount = filteredCount + 1
        }

        next = i + 2
        if kindIds[next] == targetKindId {
            resultIndices[filteredCount] = next
            checksum = checksum + (filteredCount + 1) * 97 + (next + 1) * 31 + targetKindId * 17
            filteredCount = filteredCount + 1
        }

        next = i + 3
        if kindIds[next] == targetKindId {
            resultIndices[filteredCount] = next
            checksum = checksum + (filteredCount + 1) * 97 + (next + 1) * 31 + targetKindId * 17
            filteredCount = filteredCount + 1
        }

        next = i + 4
        if kindIds[next] == targetKindId {
            resultIndices[filteredCount] = next
            checksum = checksum + (filteredCount + 1) * 97 + (next + 1) * 31 + targetKindId * 17
            filteredCount = filteredCount + 1
        }

        next = i + 5
        if kindIds[next] == targetKindId {
            resultIndices[filteredCount] = next
            checksum = checksum + (filteredCount + 1) * 97 + (next + 1) * 31 + targetKindId * 17
            filteredCount = filteredCount + 1
        }

        next = i + 6
        if kindIds[next] == targetKindId {
            resultIndices[filteredCount] = next
            checksum = checksum + (filteredCount + 1) * 97 + (next + 1) * 31 + targetKindId * 17
            filteredCount = filteredCount + 1
        }

        next = i + 7
        if kindIds[next] == targetKindId {
            resultIndices[filteredCount] = next
            checksum = checksum + (filteredCount + 1) * 97 + (next + 1) * 31 + targetKindId * 17
            filteredCount = filteredCount + 1
        }

        i = i + 8
    }

    while i < length {
        if kindIds[i] == targetKindId {
            resultIndices[filteredCount] = i
            checksum = checksum + (filteredCount + 1) * 97 + (i + 1) * 31 + targetKindId * 17
            filteredCount = filteredCount + 1
        }

        i = i + 1
    }

    return checksum + filteredCount
}

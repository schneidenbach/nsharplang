// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/FormatterImportOrdering.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func FormatterImportOrderChecksumInto(
    systemFlags: int[],
    nameRanks: int[],
    nameRankCount: int,
    bucketCounts: int[],
    bucketOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    count := FormatterImportOrderIndicesInto(
        systemFlags,
        nameRanks,
        nameRankCount,
        bucketCounts,
        bucketOffsets,
        tempIndices,
        resultIndices)

    checksum := count
    i := 0
    while i < count {
        index := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (index + 1) * 31
        checksum = checksum + systemFlags[index] * 17 + nameRanks[index] * 13
        i = i + 1
    }

    return checksum
}

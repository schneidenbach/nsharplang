// PARITY CORPUS (Arc M1): checksum fixtures extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/CliTreeDependencies.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func CliTreeDependencyDeduplicateChecksumInto(
    kindRanks: int[],
    nameRanks: int[],
    nameCounts: int[],
    nameOffsets: int[],
    kindCounts: int[],
    kindOffsets: int[],
    tempIndices: int[],
    sortedIndices: int[],
    resultIndices: int[]): int {
    uniqueCount := CliTreeDependencyDeduplicateIndicesInto(
        kindRanks,
        nameRanks,
        nameCounts,
        nameOffsets,
        kindCounts,
        kindOffsets,
        tempIndices,
        sortedIndices,
        resultIndices)

    checksum := uniqueCount
    i := 0
    while i < uniqueCount {
        index := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + kindRanks[index] * 17 + nameRanks[index] * 13
        i = i + 1
    }

    return checksum
}

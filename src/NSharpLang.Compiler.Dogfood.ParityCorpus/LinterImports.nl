// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/LinterImports.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func LinterUnusedKnownNamespaceImportChecksumInto(
    importNamespaceRanks: int[],
    importCount: int,
    usedTypeNamespaceRanks: int[],
    usedTypeRankCount: int,
    usedMemberNamespaceRanks: int[],
    usedMemberRankCount: int,
    knownNamespaceCount: int,
    usedNamespaceFlags: int[],
    touchedNamespaceRanks: int[],
    resultIndices: int[]): int {
    resultCount := LinterUnusedKnownNamespaceImportIndicesInto(
        importNamespaceRanks,
        importCount,
        usedTypeNamespaceRanks,
        usedTypeRankCount,
        usedMemberNamespaceRanks,
        usedMemberRankCount,
        knownNamespaceCount,
        usedNamespaceFlags,
        touchedNamespaceRanks,
        resultIndices)

    if resultCount < 0 {
        return resultCount
    }

    checksum := resultCount
    writtenCount := LinterImportsMinInt(resultCount, resultIndices.Length)
    i := 0
    while i < writtenCount {
        index := resultIndices[i]
        checksum = checksum + (index + 1) * 31
        i = i + 1
    }

    return checksum
}

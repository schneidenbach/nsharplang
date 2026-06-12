// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/AotRequirements.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func AotRequirementGroupChecksumInto(
    declarationRanks: int[],
    kindIds: int[],
    constructRanks: int[],
    uniqueDeclarationCount: int,
    uniqueConstructCount: int,
    declarationCounts: int[],
    requiresUnreferencedByRank: int[],
    requiresDynamicByRank: int[],
    constructSeenByDeclaration: int[],
    resultDeclarationRanks: int[],
    resultRequiresUnreferenced: int[],
    resultRequiresDynamic: int[],
    resultConstructStarts: int[],
    resultConstructCounts: int[],
    resultConstructRanks: int[]): int {
    groupCount := AotRequirementGroupsInto(
        declarationRanks,
        kindIds,
        constructRanks,
        uniqueDeclarationCount,
        uniqueConstructCount,
        declarationCounts,
        requiresUnreferencedByRank,
        requiresDynamicByRank,
        constructSeenByDeclaration,
        resultDeclarationRanks,
        resultRequiresUnreferenced,
        resultRequiresDynamic,
        resultConstructStarts,
        resultConstructCounts,
        resultConstructRanks)
    if groupCount < 0 {
        return groupCount
    }

    checksum := groupCount
    groupIndex := 0
    while groupIndex < groupCount {
        declarationRank := resultDeclarationRanks[groupIndex]
        start := resultConstructStarts[groupIndex]
        count := resultConstructCounts[groupIndex]
        checksum = checksum
            + (groupIndex + 1) * 97
            + declarationRank * 31
            + resultRequiresUnreferenced[groupIndex] * 17
            + resultRequiresDynamic[groupIndex] * 13
            + count * 7

        offset := 0
        while offset < count {
            checksum = checksum + resultConstructRanks[start + offset] * (offset + 1) * 11
            offset = offset + 1
        }

        groupIndex = groupIndex + 1
    }

    return checksum
}

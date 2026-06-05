func AotRequirementGroupsInto(
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
    blockerCount := declarationRanks.Length
    if kindIds.Length != blockerCount || constructRanks.Length != blockerCount {
        return -1
    }

    if uniqueDeclarationCount < 0 || uniqueConstructCount < 0 {
        return -1
    }

    if declarationCounts.Length <= uniqueDeclarationCount
        || requiresUnreferencedByRank.Length <= uniqueDeclarationCount
        || requiresDynamicByRank.Length <= uniqueDeclarationCount
        || resultDeclarationRanks.Length < uniqueDeclarationCount
        || resultRequiresUnreferenced.Length < uniqueDeclarationCount
        || resultRequiresDynamic.Length < uniqueDeclarationCount
        || resultConstructStarts.Length < uniqueDeclarationCount
        || resultConstructCounts.Length < uniqueDeclarationCount
        || resultConstructRanks.Length < uniqueDeclarationCount * 3 {
        return -1
    }

    constructStride := uniqueConstructCount + 1
    seenLength := (uniqueDeclarationCount + 1) * constructStride
    if constructSeenByDeclaration.Length < seenLength {
        return -1
    }

    rank := 0
    while rank <= uniqueDeclarationCount {
        declarationCounts[rank] = 0
        requiresUnreferencedByRank[rank] = 0
        requiresDynamicByRank[rank] = 0
        rank = rank + 1
    }

    seenIndex := 0
    while seenIndex < seenLength {
        constructSeenByDeclaration[seenIndex] = 0
        seenIndex = seenIndex + 1
    }

    groupCount := 0
    i := 0
    while i < blockerCount {
        declarationRank := declarationRanks[i]
        if declarationRank > 0 && declarationRank <= uniqueDeclarationCount {
            if declarationCounts[declarationRank] == 0 {
                resultDeclarationRanks[groupCount] = declarationRank
                groupCount = groupCount + 1
            }

            declarationCounts[declarationRank] = declarationCounts[declarationRank] + 1

            kind := kindIds[i]
            if kind == 1 {
                requiresUnreferencedByRank[declarationRank] = 1
            } else if kind == 2 || kind == 3 {
                requiresDynamicByRank[declarationRank] = 1
            }

            constructRank := constructRanks[i]
            if constructRank > 0 && constructRank <= uniqueConstructCount {
                constructSeenByDeclaration[declarationRank * constructStride + constructRank] = 1
            }
        }

        i = i + 1
    }

    constructResultCount := 0
    groupIndex := 0
    while groupIndex < groupCount {
        declarationRank := resultDeclarationRanks[groupIndex]
        resultRequiresUnreferenced[groupIndex] = requiresUnreferencedByRank[declarationRank]
        resultRequiresDynamic[groupIndex] = requiresDynamicByRank[declarationRank]

        start := constructResultCount
        written := 0
        constructRank := 1
        while constructRank <= uniqueConstructCount && written < 3 {
            if constructSeenByDeclaration[declarationRank * constructStride + constructRank] != 0 {
                resultConstructRanks[constructResultCount] = constructRank
                constructResultCount = constructResultCount + 1
                written = written + 1
            }

            constructRank = constructRank + 1
        }

        resultConstructStarts[groupIndex] = start
        resultConstructCounts[groupIndex] = written
        groupIndex = groupIndex + 1
    }

    return groupCount
}

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

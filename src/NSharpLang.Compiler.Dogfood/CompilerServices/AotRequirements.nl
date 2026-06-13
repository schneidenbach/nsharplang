struct AotRequirementBlockerTable {
    DeclarationRanks: int[]
    KindIds: int[]
    ConstructRanks: int[]
}

struct AotRequirementDeclarationScratchTable {
    Counts: int[]
    RequiresUnreferenced: int[]
    RequiresDynamic: int[]
}

struct AotRequirementConstructSeenTable {
    Seen: int[]
}

struct AotRequirementGroupResultTable {
    DeclarationRanks: int[]
    RequiresUnreferenced: int[]
    RequiresDynamic: int[]
    ConstructStarts: int[]
    ConstructCounts: int[]
    ConstructRanks: int[]
}

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
    blockers := new AotRequirementBlockerTable { DeclarationRanks: declarationRanks, KindIds: kindIds, ConstructRanks: constructRanks }
    scratch := new AotRequirementDeclarationScratchTable { Counts: declarationCounts, RequiresUnreferenced: requiresUnreferencedByRank, RequiresDynamic: requiresDynamicByRank }
    seen := new AotRequirementConstructSeenTable { Seen: constructSeenByDeclaration }
    result := new AotRequirementGroupResultTable { DeclarationRanks: resultDeclarationRanks, RequiresUnreferenced: resultRequiresUnreferenced, RequiresDynamic: resultRequiresDynamic, ConstructStarts: resultConstructStarts, ConstructCounts: resultConstructCounts, ConstructRanks: resultConstructRanks }
    return AotRequirementGroupsCore(ref blockers, uniqueDeclarationCount, uniqueConstructCount, ref scratch, ref seen, ref result)
}

func AotRequirementGroupsCore(
    blockers: &AotRequirementBlockerTable,
    uniqueDeclarationCount: int,
    uniqueConstructCount: int,
    scratch: &AotRequirementDeclarationScratchTable,
    seen: &AotRequirementConstructSeenTable,
    result: &AotRequirementGroupResultTable): int {
    blockerCount := blockers.DeclarationRanks.Length
    if blockers.KindIds.Length != blockerCount || blockers.ConstructRanks.Length != blockerCount {
        return -1
    }

    if uniqueDeclarationCount < 0 || uniqueConstructCount < 0 {
        return -1
    }

    if scratch.Counts.Length <= uniqueDeclarationCount
        || scratch.RequiresUnreferenced.Length <= uniqueDeclarationCount
        || scratch.RequiresDynamic.Length <= uniqueDeclarationCount
        || result.DeclarationRanks.Length < uniqueDeclarationCount
        || result.RequiresUnreferenced.Length < uniqueDeclarationCount
        || result.RequiresDynamic.Length < uniqueDeclarationCount
        || result.ConstructStarts.Length < uniqueDeclarationCount
        || result.ConstructCounts.Length < uniqueDeclarationCount
        || result.ConstructRanks.Length < uniqueDeclarationCount * 3 {
        return -1
    }

    constructStride := uniqueConstructCount + 1
    seenLength := (uniqueDeclarationCount + 1) * constructStride
    if seen.Seen.Length < seenLength {
        return -1
    }

    rank := 0
    while rank <= uniqueDeclarationCount {
        scratch.Counts[rank] = 0
        scratch.RequiresUnreferenced[rank] = 0
        scratch.RequiresDynamic[rank] = 0
        rank = rank + 1
    }

    seenIndex := 0
    while seenIndex < seenLength {
        seen.Seen[seenIndex] = 0
        seenIndex = seenIndex + 1
    }

    groupCount := 0
    i := 0
    while i < blockerCount {
        declarationRank := blockers.DeclarationRanks[i]
        if declarationRank > 0 && declarationRank <= uniqueDeclarationCount {
            if scratch.Counts[declarationRank] == 0 {
                result.DeclarationRanks[groupCount] = declarationRank
                groupCount = groupCount + 1
            }

            scratch.Counts[declarationRank] = scratch.Counts[declarationRank] + 1

            kind := blockers.KindIds[i]
            if kind == 1 {
                scratch.RequiresUnreferenced[declarationRank] = 1
            } else if kind == 2 || kind == 3 {
                scratch.RequiresDynamic[declarationRank] = 1
            }

            constructRank := blockers.ConstructRanks[i]
            if constructRank > 0 && constructRank <= uniqueConstructCount {
                seen.Seen[declarationRank * constructStride + constructRank] = 1
            }
        }

        i = i + 1
    }

    constructResultCount := 0
    groupIndex := 0
    while groupIndex < groupCount {
        declarationRank := result.DeclarationRanks[groupIndex]
        result.RequiresUnreferenced[groupIndex] = scratch.RequiresUnreferenced[declarationRank]
        result.RequiresDynamic[groupIndex] = scratch.RequiresDynamic[declarationRank]

        start := constructResultCount
        written := 0
        constructRank := 1
        while constructRank <= uniqueConstructCount && written < 3 {
            if seen.Seen[declarationRank * constructStride + constructRank] != 0 {
                result.ConstructRanks[constructResultCount] = constructRank
                constructResultCount = constructResultCount + 1
                written = written + 1
            }

            constructRank = constructRank + 1
        }

        result.ConstructStarts[groupIndex] = start
        result.ConstructCounts[groupIndex] = written
        groupIndex = groupIndex + 1
    }

    return groupCount
}

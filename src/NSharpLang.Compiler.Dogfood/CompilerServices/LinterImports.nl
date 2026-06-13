struct LinterImportNamespaceTable {
    NamespaceRanks: int[]
    Count: int
}

struct LinterUsedNamespaceTable {
    TypeNamespaceRanks: int[]
    TypeRankCount: int
    MemberNamespaceRanks: int[]
    MemberRankCount: int
    KnownNamespaceCount: int
}

struct LinterNamespaceScratchTable {
    UsedFlags: int[]
    TouchedRanks: int[]
}

struct LinterImportResultTable {
    Indices: int[]
}

func LinterUnusedKnownNamespaceImportIndicesInto(
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
    imports := new LinterImportNamespaceTable { NamespaceRanks: importNamespaceRanks, Count: importCount }
    usedNamespaces := new LinterUsedNamespaceTable { TypeNamespaceRanks: usedTypeNamespaceRanks, TypeRankCount: usedTypeRankCount, MemberNamespaceRanks: usedMemberNamespaceRanks, MemberRankCount: usedMemberRankCount, KnownNamespaceCount: knownNamespaceCount }
    scratch := new LinterNamespaceScratchTable { UsedFlags: usedNamespaceFlags, TouchedRanks: touchedNamespaceRanks }
    result := new LinterImportResultTable { Indices: resultIndices }
    return LinterUnusedKnownNamespaceImportIndicesCore(ref imports, ref usedNamespaces, ref scratch, ref result)
}

func LinterUnusedKnownNamespaceImportIndicesCore(
    imports: &LinterImportNamespaceTable,
    usedNamespaces: &LinterUsedNamespaceTable,
    scratch: &LinterNamespaceScratchTable,
    result: &LinterImportResultTable): int {
    effectiveImportCount := LinterImportsMinInt(imports.Count, imports.NamespaceRanks.Length)
    if effectiveImportCount <= 0 || usedNamespaces.KnownNamespaceCount <= 0 || scratch.UsedFlags.Length <= 1 {
        return 0
    }

    effectiveKnownCount := usedNamespaces.KnownNamespaceCount
    maxFlagRank := scratch.UsedFlags.Length - 1
    if maxFlagRank < effectiveKnownCount {
        effectiveKnownCount = maxFlagRank
    }

    touchedCount := 0
    effectiveTypeRankCount := LinterImportsMinInt(usedNamespaces.TypeRankCount, usedNamespaces.TypeNamespaceRanks.Length)
    i := 0
    while i < effectiveTypeRankCount {
        rank := usedNamespaces.TypeNamespaceRanks[i]
        if rank > 0 && rank <= effectiveKnownCount && scratch.UsedFlags[rank] == 0 {
            if touchedCount >= scratch.TouchedRanks.Length {
                LinterImportsClearAllUsedFlagsCore(ref scratch, effectiveKnownCount)
                return -1
            }

            scratch.UsedFlags[rank] = 1
            scratch.TouchedRanks[touchedCount] = rank
            touchedCount = touchedCount + 1
        }

        i = i + 1
    }

    effectiveMemberRankCount := LinterImportsMinInt(usedNamespaces.MemberRankCount, usedNamespaces.MemberNamespaceRanks.Length)
    i = 0
    while i < effectiveMemberRankCount {
        rank := usedNamespaces.MemberNamespaceRanks[i]
        if rank > 0 && rank <= effectiveKnownCount && scratch.UsedFlags[rank] == 0 {
            if touchedCount >= scratch.TouchedRanks.Length {
                LinterImportsClearAllUsedFlagsCore(ref scratch, effectiveKnownCount)
                return -1
            }

            scratch.UsedFlags[rank] = 1
            scratch.TouchedRanks[touchedCount] = rank
            touchedCount = touchedCount + 1
        }

        i = i + 1
    }

    resultCount := 0
    i = 0
    while i < effectiveImportCount {
        rank := imports.NamespaceRanks[i]
        if rank > 0 && rank <= effectiveKnownCount && scratch.UsedFlags[rank] == 0 {
            if resultCount < result.Indices.Length {
                result.Indices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    i = 0
    while i < touchedCount {
        rank := scratch.TouchedRanks[i]
        if rank > 0 && rank < scratch.UsedFlags.Length {
            scratch.UsedFlags[rank] = 0
        }

        i = i + 1
    }

    return resultCount
}

func LinterImportsClearAllUsedFlags(usedNamespaceFlags: int[], effectiveKnownCount: int): int {
    scratch := new LinterNamespaceScratchTable { UsedFlags: usedNamespaceFlags, TouchedRanks: usedNamespaceFlags }
    return LinterImportsClearAllUsedFlagsCore(ref scratch, effectiveKnownCount)
}

func LinterImportsClearAllUsedFlagsCore(scratch: &LinterNamespaceScratchTable, effectiveKnownCount: int): int {
    count := effectiveKnownCount
    if count >= scratch.UsedFlags.Length {
        count = scratch.UsedFlags.Length - 1
    }

    i := 1
    while i <= count {
        scratch.UsedFlags[i] = 0
        i = i + 1
    }

    return 0
}

func LinterImportsMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

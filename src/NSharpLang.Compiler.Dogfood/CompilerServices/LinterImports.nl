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
    effectiveImportCount := LinterImportsMinInt(importCount, importNamespaceRanks.Length)
    if effectiveImportCount <= 0 || knownNamespaceCount <= 0 || usedNamespaceFlags.Length <= 1 {
        return 0
    }

    effectiveKnownCount := knownNamespaceCount
    maxFlagRank := usedNamespaceFlags.Length - 1
    if maxFlagRank < effectiveKnownCount {
        effectiveKnownCount = maxFlagRank
    }

    touchedCount := 0
    effectiveTypeRankCount := LinterImportsMinInt(usedTypeRankCount, usedTypeNamespaceRanks.Length)
    i := 0
    while i < effectiveTypeRankCount {
        rank := usedTypeNamespaceRanks[i]
        if rank > 0 && rank <= effectiveKnownCount && usedNamespaceFlags[rank] == 0 {
            if touchedCount >= touchedNamespaceRanks.Length {
                LinterImportsClearAllUsedFlags(usedNamespaceFlags, effectiveKnownCount)
                return -1
            }

            usedNamespaceFlags[rank] = 1
            touchedNamespaceRanks[touchedCount] = rank
            touchedCount = touchedCount + 1
        }

        i = i + 1
    }

    effectiveMemberRankCount := LinterImportsMinInt(usedMemberRankCount, usedMemberNamespaceRanks.Length)
    i = 0
    while i < effectiveMemberRankCount {
        rank := usedMemberNamespaceRanks[i]
        if rank > 0 && rank <= effectiveKnownCount && usedNamespaceFlags[rank] == 0 {
            if touchedCount >= touchedNamespaceRanks.Length {
                LinterImportsClearAllUsedFlags(usedNamespaceFlags, effectiveKnownCount)
                return -1
            }

            usedNamespaceFlags[rank] = 1
            touchedNamespaceRanks[touchedCount] = rank
            touchedCount = touchedCount + 1
        }

        i = i + 1
    }

    resultCount := 0
    i = 0
    while i < effectiveImportCount {
        rank := importNamespaceRanks[i]
        if rank > 0 && rank <= effectiveKnownCount && usedNamespaceFlags[rank] == 0 {
            if resultCount < resultIndices.Length {
                resultIndices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    i = 0
    while i < touchedCount {
        rank := touchedNamespaceRanks[i]
        if rank > 0 && rank < usedNamespaceFlags.Length {
            usedNamespaceFlags[rank] = 0
        }

        i = i + 1
    }

    return resultCount
}

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

func LinterImportsClearAllUsedFlags(usedNamespaceFlags: int[], effectiveKnownCount: int): int {
    count := effectiveKnownCount
    if count >= usedNamespaceFlags.Length {
        count = usedNamespaceFlags.Length - 1
    }

    i := 1
    while i <= count {
        usedNamespaceFlags[i] = 0
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

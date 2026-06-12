// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/DiagnosticClusters.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func DiagnosticSeveritySummaryChecksumInto(severities: string[], count: int, resultCounts: int[]): int {
    count = DiagnosticSeveritySummaryInto(severities, count, resultCounts)
    if resultCounts.Length < 3 {
        return count
    }

    return count + resultCounts[0] * 31 + resultCounts[1] * 17 + resultCounts[2] * 13
}

func DiagnosticSeverityFilterChecksumInto(
    severityRanks: int[],
    targetRank: int,
    resultIndices: int[]): int {
    if targetRank <= 0 {
        return 0
    }

    length := severityRanks.Length
    if resultIndices.Length < length {
        matchCount := DiagnosticSeverityFilterIndicesInto(severityRanks, targetRank, resultIndices)
        checksum := matchCount
        i := 0
        while i < matchCount && i < resultIndices.Length {
            index := resultIndices[i]
            checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + severityRanks[index] * 17
            i = i + 1
        }

        return checksum
    }

    matchCount := 0
    checksum := 0
    i := 0
    unrolledLimit := length - 8
    while i <= unrolledLimit {
        if severityRanks[i] == targetRank {
            resultIndices[matchCount] = i
            checksum = checksum + (matchCount + 1) * 97 + (i + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next := i + 1
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 2
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 3
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 4
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 5
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 6
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 7
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        i = i + 8
    }

    while i < length {
        if severityRanks[i] == targetRank {
            resultIndices[matchCount] = i
            checksum = checksum + (matchCount + 1) * 97 + (i + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return checksum + matchCount
}

func DiagnosticShadowSuppressionChecksumInto(
    codeIds: int[],
    fileRanks: int[],
    targetCodeId: int,
    shadowFileFlags: int[],
    resultIndices: int[]): int {
    count := MinInt(codeIds.Length, fileRanks.Length)
    if count == 0 {
        return 0
    }

    keptCount := 0
    checksum := 0
    i := 0
    while i < count {
        fileRank := fileRanks[i]
        suppress := targetCodeId > 0 &&
            codeIds[i] == targetCodeId &&
            fileRank > 0 &&
            fileRank < shadowFileFlags.Length &&
            shadowFileFlags[fileRank] != 0

        if !suppress {
            if keptCount < resultIndices.Length {
                resultIndices[keptCount] = i
            }

            checksum = checksum + (keptCount + 1) * 97 + (i + 1) * 31 + codeIds[i] * 17 + fileRank * 13
            keptCount = keptCount + 1
        }

        i = i + 1
    }

    return checksum + keptCount
}

func DiagnosticClusterTraitChecksumInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[]): int {
    count := DiagnosticClusterTraitsInto(
        codes,
        messages,
        snippets,
        resultCategories,
        resultSourceConstructs)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultCategories[i] * 31 + resultSourceConstructs[i] * 17
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterTraitPatternChecksumInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[],
    resultPatterns: string[]): int {
    count := DiagnosticClusterTraitsAndPatternsInto(
        codes,
        messages,
        snippets,
        resultCategories,
        resultSourceConstructs,
        resultPatterns)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultCategories[i] * 31 + resultSourceConstructs[i] * 17 + resultPatterns[i].Length
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterIdChecksumInto(
    codes: string[],
    severities: string[],
    categories: string[],
    sourceConstructs: string[],
    recipes: string[],
    messagePatterns: string[],
    resultIds: string[]): int {
    count := DiagnosticClusterIdsInto(
        codes,
        severities,
        categories,
        sourceConstructs,
        recipes,
        messagePatterns,
        resultIds)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultIds[i].Length * 31
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterNextCommandChecksumInto(
    files: string[],
    lines: int[],
    columns: int[],
    resultCommands: string[]): int {
    count := DiagnosticClusterNextCommandsInto(files, lines, columns, resultCommands)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultCommands[i].Length * 31
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterCompactGroupChecksumInto(
    codeIds: int[],
    severityIds: int[],
    categoryIds: int[],
    sourceConstructIds: int[],
    recipeIds: int[],
    riskIds: int[],
    messagePatternIds: int[],
    files: string[],
    lines: int[],
    columns: int[],
    slotGroups: int[],
    groupKeyIndices: int[],
    resultRootIndices: int[],
    resultCounts: int[]): int {
    groupCount := DiagnosticClusterCompactGroupsInto(
        codeIds,
        severityIds,
        categoryIds,
        sourceConstructIds,
        recipeIds,
        riskIds,
        messagePatternIds,
        files,
        lines,
        columns,
        slotGroups,
        groupKeyIndices,
        resultRootIndices,
        resultCounts)

    checksum := groupCount
    i := 0
    while i < groupCount {
        checksum = checksum + (resultRootIndices[i] + 1) * 31 + resultCounts[i] * 17
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterCompactGroupMemberChecksumInto(
    codeIds: int[],
    severityIds: int[],
    categoryIds: int[],
    sourceConstructIds: int[],
    recipeIds: int[],
    riskIds: int[],
    messagePatternIds: int[],
    files: string[],
    lines: int[],
    columns: int[],
    groupRootIndices: int[],
    groupCounts: int[],
    groupCount: int,
    slotGroups: int[],
    groupFirstMemberIndices: int[],
    memberNextIndices: int[],
    resultStarts: int[],
    resultMemberIndices: int[]): int {
    total := DiagnosticClusterCompactGroupMembersInto(
        codeIds,
        severityIds,
        categoryIds,
        sourceConstructIds,
        recipeIds,
        riskIds,
        messagePatternIds,
        files,
        lines,
        columns,
        groupRootIndices,
        groupCounts,
        groupCount,
        slotGroups,
        groupFirstMemberIndices,
        memberNextIndices,
        resultStarts,
        resultMemberIndices)

    if total < 0 {
        return total
    }

    checksum := total
    groupIndex := 0
    while groupIndex < groupCount {
        checksum = checksum + (resultStarts[groupIndex] + 1) * 31 + groupCounts[groupIndex] * 17
        groupIndex = groupIndex + 1
    }

    i := 0
    while i < total {
        index := resultMemberIndices[i]
        checksum = checksum + (index + 1) * 13 + lines[index] * 7 + columns[index] * 5
        i = i + 1
    }

    return checksum
}

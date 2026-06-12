// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/CliArguments.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func CliWatchForwardedArgChecksumInto(args: string[], resultIndices: int[]): int {
    resultCount := CliWatchForwardedArgIndicesInto(args, resultIndices)
    checksum := resultCount
    i := 0

    while i < resultCount && i < resultIndices.Length {
        sourceIndex := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + args[sourceIndex].Length * 17
        i = i + 1
    }

    return checksum
}

func CliTestOptionSummaryChecksumInto(args: string[], resultIndices: int[]): int {
    code := CliTestOptionSummaryInto(args, resultIndices)
    if code < 0 {
        return code
    }

    checksum := args.Length + 17
    i := 0
    while i < 10 {
        value := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (value + 1) * 31
        if value >= 0 && value < args.Length {
            checksum = checksum + args[value].Length * 13
        }

        i = i + 1
    }

    return checksum
}

func CliLintFileArgChecksumInto(
    args: string[],
    projectValueIndices: int[],
    resultIndices: int[]): int {
    resultCount := CliLintFileArgIndicesInto(args, projectValueIndices, resultIndices)
    checksum := resultCount
    i := 0
    while i < resultCount {
        index := resultIndices[i]
        length := 0
        if index >= 0 && index < args.Length {
            length = args[index].Length
        }

        checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + length * 17
        i = i + 1
    }

    return checksum
}

func CliTidyDependencyStatusRankChecksumInto(
    packageNames: string[],
    importNamespaces: string[],
    resultStatusRanks: int[]): int {
    count := CliTidyDependencyStatusRanksInto(packageNames, importNamespaces, resultStatusRanks)
    checksum := count
    i := 0
    while i < count && i < resultStatusRanks.Length {
        rank := resultStatusRanks[i]
        checksum = checksum + (i + 1) * 97 + rank * 31 + packageNames[i].Length * 17
        i = i + 1
    }

    return checksum
}

func CliTidyRemovalLineKeepChecksumInto(lines: string[], packageNames: string[], resultFlags: int[]): int {
    count := CliTidyRemovalLineKeepFlagsInto(lines, packageNames, resultFlags)
    checksum := count
    i := 0
    while i < count && i < resultFlags.Length {
        checksum = checksum + (i + 1) * 97 + resultFlags[i] * 31 + lines[i].Length * 17
        i = i + 1
    }

    return checksum
}

func CliBuildOptionSummaryChecksumInto(args: string[], resultIndices: int[]): int {
    code := CliBuildOptionSummaryInto(args, resultIndices)
    if code < 0 {
        return code
    }

    checksum := args.Length + 23
    i := 0
    while i < 9 {
        value := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (value + 1) * 31
        if i < 3 && value >= 0 && value < args.Length {
            checksum = checksum + args[value].Length * 13
        }

        i = i + 1
    }

    return checksum
}

func CliFixSafetyFilterChecksumInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    maxAppliedRank := 1
    if includeReviewNeeded != 0 {
        maxAppliedRank = 2
    }

    length := safetyRanks.Length
    if resultIndices.Length < length {
        matchCount := CliFixSafetyFilterIndicesInto(safetyRanks, includeReviewNeeded, resultIndices)
        checksum := matchCount
        i := 0
        while i < matchCount && i < resultIndices.Length {
            index := resultIndices[i]
            rank := 0
            if index >= 0 && index < length {
                rank = safetyRanks[index]
            }

            checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + rank * 17
            i = i + 1
        }

        return checksum
    }

    matchCount := 0
    checksum := 0
    i := 0
    unrolledLimit := length - 8
    while i <= unrolledLimit {
        rank := safetyRanks[i]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = i
            checksum = checksum + (matchCount + 1) * 97 + (i + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next := i + 1
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 2
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 3
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 4
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 5
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 6
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        next = i + 7
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        i = i + 8
    }

    while i < length {
        rank := safetyRanks[i]
        if rank > 0 && rank <= maxAppliedRank {
            resultIndices[matchCount] = i
            checksum = checksum + (matchCount + 1) * 97 + (i + 1) * 31 + rank * 17
            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return checksum + matchCount
}

func CliFixEditFlattenChecksumInto(
    editCounts: int[],
    resultActionIndices: int[],
    resultEditIndices: int[]): int {
    flattenedCount := CliFixEditFlattenIndicesInto(editCounts, resultActionIndices, resultEditIndices)
    if flattenedCount < 0 {
        return flattenedCount
    }

    checksum := flattenedCount
    i := 0
    while i < flattenedCount {
        actionIndex := resultActionIndices[i]
        editIndex := resultEditIndices[i]
        editCount := 0
        if actionIndex >= 0 && actionIndex < editCounts.Length {
            editCount = editCounts[actionIndex]
        }

        checksum = checksum + (i + 1) * 97 + (actionIndex + 1) * 31 + (editIndex + 1) * 17 + editCount * 13
        i = i + 1
    }

    return checksum
}

func CliFixSkippedChecksumInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    skippedCount := CliFixSkippedIndicesInto(safetyRanks, includeReviewNeeded, resultIndices)
    checksum := skippedCount
    i := 0
    while i < skippedCount && i < resultIndices.Length {
        index := resultIndices[i]
        rank := 0
        if index >= 0 && index < safetyRanks.Length {
            rank = safetyRanks[index]
        }

        checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + rank * 17
        i = i + 1
    }

    return checksum
}

func CliFixAppliedFileGroupChecksumInto(
    fileRanks: int[],
    uniqueFileRankCount: int,
    countsByRank: int[],
    offsetsByRank: int[],
    writeOffsetsByRank: int[],
    resultRanks: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultIndices: int[]): int {
    groupCount := CliFixAppliedFileGroupsInto(
        fileRanks,
        uniqueFileRankCount,
        countsByRank,
        offsetsByRank,
        writeOffsetsByRank,
        resultRanks,
        resultStarts,
        resultCounts,
        resultIndices)

    checksum := groupCount
    groupIndex := 0
    while groupIndex < groupCount {
        rank := resultRanks[groupIndex]
        start := resultStarts[groupIndex]
        count := resultCounts[groupIndex]
        checksum = checksum + (groupIndex + 1) * 97 + rank * 31 + (start + 1) * 17 + count * 13

        i := 0
        while i < count {
            sourceIndex := resultIndices[start + i]
            checksum = checksum + (sourceIndex + 1) * 11 + fileRanks[sourceIndex] * 7 + (i + 1) * 5
            i = i + 1
        }

        groupIndex = groupIndex + 1
    }

    return checksum
}

func CliUnifiedDiffHunkRangeChecksumInto(
    kindIds: int[],
    oldLines: int[],
    newLines: int[],
    contextLines: int,
    resultStarts: int[],
    resultLengths: int[],
    resultOldStarts: int[],
    resultOldCounts: int[],
    resultNewStarts: int[],
    resultNewCounts: int[]): int {
    hunkCount := CliUnifiedDiffHunkRangesInto(
        kindIds,
        oldLines,
        newLines,
        contextLines,
        resultStarts,
        resultLengths,
        resultOldStarts,
        resultOldCounts,
        resultNewStarts,
        resultNewCounts)

    checksum := hunkCount
    i := 0
    while i < hunkCount {
        checksum = checksum
            + (i + 1) * 97
            + (resultStarts[i] + 1) * 31
            + resultLengths[i] * 17
            + resultOldStarts[i] * 13
            + resultOldCounts[i] * 11
            + resultNewStarts[i] * 7
            + resultNewCounts[i] * 5
        i = i + 1
    }

    return checksum
}

func CliCleanArtifactDirectoryChecksumInto(
    kindRanks: int[],
    nodeModuleFlags: int[],
    pathRanks: int[],
    pathLengths: int[],
    seenPathRanks: int[],
    lengthCounts: int[],
    lengthOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    orderedCount := CliCleanArtifactDirectoryIndicesInto(
        kindRanks,
        nodeModuleFlags,
        pathRanks,
        pathLengths,
        seenPathRanks,
        lengthCounts,
        lengthOffsets,
        tempIndices,
        resultIndices)
    if orderedCount < 0 {
        return orderedCount
    }

    checksum := orderedCount
    i := 0
    while i < orderedCount && i < resultIndices.Length {
        sourceIndex := resultIndices[i]
        kindRank := 0
        pathRank := 0
        pathLength := 0
        if sourceIndex >= 0 && sourceIndex < kindRanks.Length {
            kindRank = kindRanks[sourceIndex]
            pathRank = pathRanks[sourceIndex]
            pathLength = pathLengths[sourceIndex]
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + kindRank * 17 + pathRank * 13 + pathLength * 7
        i = i + 1
    }

    return checksum
}

func CliUpdateAllNuGetDependencyChecksumInto(
    nugetFlags: int[],
    resultIndices: int[]): int {
    length := nugetFlags.Length
    if resultIndices.Length < length {
        matchCount := CliUpdateAllNuGetDependencyIndicesInto(nugetFlags, resultIndices)
        if matchCount < 0 {
            return matchCount
        }

        checksum := matchCount
        i := 0
        while i < matchCount && i < resultIndices.Length {
            sourceIndex := resultIndices[i]
            flag := 0
            if sourceIndex >= 0 && sourceIndex < length {
                flag = nugetFlags[sourceIndex]
            }

            checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + flag * 17
            i = i + 1
        }

        return checksum
    }

    matchCount := 0
    checksum := 0
    i := 0
    unrolledLimit := length - 16
    while i <= unrolledLimit {
        if nugetFlags[i] != 0 {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + 17
        }

        next := i + 1
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 2
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 3
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 4
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 5
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 6
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 7
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 8
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 9
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 10
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 11
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 12
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 13
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 14
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        next = i + 15
        if nugetFlags[next] != 0 {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + 17
        }

        i = i + 16
    }

    while i < length {
        if nugetFlags[i] != 0 {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + 17
        }

        i = i + 1
    }

    return checksum + matchCount
}

func CliUpdateTargetNuGetDependencyChecksumInto(
    nameRanks: int[],
    targetNameRank: int,
    resultIndices: int[]): int {
    if targetNameRank <= 0 {
        return 0
    }

    length := nameRanks.Length
    if resultIndices.Length < length {
        matchCount := CliUpdateTargetNuGetDependencyIndicesInto(nameRanks, targetNameRank, resultIndices)
        if matchCount < 0 {
            return matchCount
        }

        checksum := matchCount
        i := 0
        while i < matchCount && i < resultIndices.Length {
            sourceIndex := resultIndices[i]
            nameRank := 0
            if sourceIndex >= 0 && sourceIndex < length {
                nameRank = nameRanks[sourceIndex]
            }

            checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + 17 + nameRank * 13
            i = i + 1
        }

        return checksum
    }

    matchCount := 0
    checksum := matchCount
    i := 0
    targetScore := 17 + targetNameRank * 13

    unrolledLimit := length - 16
    while i <= unrolledLimit {
        if nameRanks[i] == targetNameRank {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + targetScore
        }

        next := i + 1
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 2
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 3
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 4
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 5
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 6
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 7
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 8
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 9
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 10
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 11
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 12
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 13
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 14
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 15
        if nameRanks[next] == targetNameRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        i = i + 16
    }

    while i < length {
        if nameRanks[i] == targetNameRank {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + targetScore
        }

        i = i + 1
    }

    return checksum + matchCount
}

func CliReferenceTypeFilterChecksumInto(
    typeRanks: int[],
    targetTypeRank: int,
    resultIndices: int[]): int {
    if targetTypeRank <= 0 {
        return 0
    }

    length := typeRanks.Length
    if resultIndices.Length < length {
        matchCount := CliReferenceTypeFilterIndicesInto(typeRanks, targetTypeRank, resultIndices)
        if matchCount < 0 {
            return matchCount
        }

        checksum := matchCount
        i := 0
        while i < matchCount && i < resultIndices.Length {
            sourceIndex := resultIndices[i]
            typeRank := 0
            if sourceIndex >= 0 && sourceIndex < length {
                typeRank = typeRanks[sourceIndex]
            }

            checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + typeRank * 17
            i = i + 1
        }

        return checksum
    }

    matchCount := 0
    checksum := matchCount
    i := 0
    targetScore := targetTypeRank * 17

    unrolledLimit := length - 16
    while i <= unrolledLimit {
        if typeRanks[i] == targetTypeRank {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + targetScore
        }

        next := i + 1
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 2
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 3
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 4
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 5
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 6
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 7
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 8
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 9
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 10
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 11
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 12
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 13
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 14
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        next = i + 15
        if typeRanks[next] == targetTypeRank {
            resultIndices[matchCount] = next
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (next + 1) * 31 + targetScore
        }

        i = i + 16
    }

    while i < length {
        if typeRanks[i] == targetTypeRank {
            resultIndices[matchCount] = i
            matchCount = matchCount + 1
            checksum = checksum + matchCount * 97 + (i + 1) * 31 + targetScore
        }

        i = i + 1
    }

    return checksum + matchCount
}

func CliStableDistinctRankChecksumInto(
    ranks: int[],
    uniqueRankCount: int,
    seenRanks: int[],
    resultIndices: int[],
    rankWeights: int[]): int {
    resultCount := CliStableDistinctRankIndicesInto(
        ranks,
        uniqueRankCount,
        seenRanks,
        resultIndices)

    checksum := resultCount
    i := 0
    while i < resultCount && i < resultIndices.Length {
        sourceIndex := resultIndices[i]
        rank := 0
        weight := 0
        if sourceIndex >= 0 && sourceIndex < ranks.Length {
            rank = ranks[sourceIndex]
            if rank >= 0 && rank < rankWeights.Length {
                weight = rankWeights[rank]
            }
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + rank * 17 + weight * 13
        i = i + 1
    }

    return checksum
}

func CliReferenceResolutionBestScoreChecksum(
    scores: int[],
    weights: int[],
    count: int): int {
    bestIndex := CliReferenceResolutionBestScoreIndex(scores, count)
    if bestIndex < 0 {
        return bestIndex
    }

    weight := 0
    if bestIndex < weights.Length {
        weight = weights[bestIndex]
    }

    return (bestIndex + 1) * 97 + scores[bestIndex] * 31 + weight * 17
}

func CliPositionalArgChecksumInto(
    args: string[],
    optionsWithValues: string[],
    resultIndices: int[]): int {
    count := CliPositionalArgIndicesInto(args, optionsWithValues, resultIndices)
    checksum := count
    i := 0
    while i < count && i < resultIndices.Length {
        sourceIndex := resultIndices[i]
        length := 0
        if sourceIndex >= 0 && sourceIndex < args.Length {
            length = args[sourceIndex].Length
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + length * 17
        i = i + 1
    }

    return checksum
}

func CliExportCSharpFirstOperandChecksumInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    sourceIndex := CliExportCSharpFirstOperandIndexInto(
        args,
        kindIds,
        nextIndices,
        previousIndices,
        nextOptionIndices,
        resultIndices)
    checksum := sourceIndex + 1
    if sourceIndex >= 0 && sourceIndex < args.Length {
        arg := args[sourceIndex]
        checksum = checksum + arg.Length * 31
        i := 0
        while i < arg.Length {
            checksum = checksum + arg[i] * (i + 1)
            i = i + 1
        }
    }

    return checksum
}

func CliTidyDependencyStatusSummaryChecksumInto(statusRanks: int[], resultCounts: int[]): int {
    count := CliTidyDependencyStatusSummaryInto(statusRanks, resultCounts)
    if count < 0 {
        return count
    }

    okValue := 13
    if resultCounts[0] == 0 {
        okValue = 7
    }

    return count + okValue + resultCounts[0] * 31 + resultCounts[1] * 17
}

func CliTestOutcomeSummaryChecksumInto(outcomeRanks: int[], count: int, resultCounts: int[]): int {
    count = CliTestOutcomeSummaryInto(outcomeRanks, count, resultCounts)
    if count < 0 {
        return count
    }

    okValue := 7
    if resultCounts[3] != 0 {
        okValue = 13
    }

    return count + okValue + resultCounts[0] * 31 + resultCounts[1] * 17 + resultCounts[2] * 11 + resultCounts[3] * 5
}

func CliFormatDiscoveredPathChecksumInto(relativePaths: string[], resultFlags: int[]): int {
    count := CliFormatDiscoveredPathFlagsInto(relativePaths, resultFlags)
    checksum := count
    i := 0

    while i < count {
        checksum = checksum + (i + 1) * 31 + resultFlags[i] * 17 + relativePaths[i].Length * 7
        i = i + 1
    }

    return checksum
}

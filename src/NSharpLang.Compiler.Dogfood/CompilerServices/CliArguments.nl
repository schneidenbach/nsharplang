func CliPositionalArgIndicesInto(
    args: string[],
    optionsWithValues: string[],
    resultIndices: int[]): int {
    resultCount := 0
    i := 0
    while i < args.Length {
        arg := args[i]
        if CliArgumentIsOptionWithValue(arg, optionsWithValues) {
            i = i + 2
            continue
        }

        if CliArgumentIsValueLessFlag(arg) {
            i = i + 1
            continue
        }

        if arg.Length == 0 || arg[0] != '-' {
            if resultCount < resultIndices.Length {
                resultIndices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func CliFirstPositionalArgIndex(args: string[], optionsWithValues: string[]): int {
    i := 0
    while i < args.Length {
        arg := args[i]
        if CliArgumentIsOptionWithValue(arg, optionsWithValues) {
            i = i + 2
            continue
        }

        if CliArgumentIsValueLessFlag(arg) {
            i = i + 1
            continue
        }

        if arg.Length == 0 || arg[0] != '-' {
            return i
        }

        i = i + 1
    }

    return -1
}

func CliBuildFirstOperandIndexInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    i := 0
    while i < args.Length {
        kind := CliBuildArgumentKind(args[i])
        if kind == 5 {
            i = i + 1
            continue
        }

        if kind == 0 {
            return i
        }

        break
    }

    count := CliBuildOperandSummaryInto(args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices)
    if count <= 0 {
        return -1
    }

    return resultIndices[0]
}

func CliExportCSharpFirstOperandIndexInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    if args.Length == 0 {
        return -1
    }

    firstArg := args[0]
    if firstArg.Length == 0 || firstArg[0] != '-' {
        return 0
    }

    if kindIds.Length < args.Length
        || nextIndices.Length < args.Length
        || previousIndices.Length < args.Length
        || nextOptionIndices.Length < args.Length
        || (args.Length > 0 && resultIndices.Length < 1) {
        return -2
    }

    first := -1
    last := -1
    outputHead := -1
    outputTail := -1
    shortOutputHead := -1
    shortOutputTail := -1
    projectHead := -1
    projectTail := -1
    count := 0
    i := 0
    while i < args.Length {
        kind := CliBuildArgumentKind(args[i])
        kindIds[i] = kind
        nextIndices[i] = -1
        previousIndices[i] = -1
        nextOptionIndices[i] = -1

        if last >= 0 {
            nextIndices[last] = i
            previousIndices[i] = last
        } else {
            first = i
        }

        last = i
        count = count + 1

        if kind == 1 {
            if outputTail >= 0 {
                nextOptionIndices[outputTail] = i
            } else {
                outputHead = i
            }

            outputTail = i
        } else if kind == 2 {
            if shortOutputTail >= 0 {
                nextOptionIndices[shortOutputTail] = i
            } else {
                shortOutputHead = i
            }

            shortOutputTail = i
        } else if kind == 4 {
            if projectTail >= 0 {
                nextOptionIndices[projectTail] = i
            } else {
                projectHead = i
            }

            projectTail = i
        }

        i = i + 1
    }

    resultIndices[0] = first
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, outputHead, 1, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, shortOutputHead, 2, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, projectHead, 4, resultIndices, count)

    sourceIndex := resultIndices[0]
    while sourceIndex >= 0 {
        arg := args[sourceIndex]
        if arg.Length == 0 || arg[0] != '-' {
            return sourceIndex
        }

        sourceIndex = nextIndices[sourceIndex]
    }

    return -1
}

func CliBuildOperandSummaryInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    if kindIds.Length < args.Length
        || nextIndices.Length < args.Length
        || previousIndices.Length < args.Length
        || nextOptionIndices.Length < args.Length
        || (args.Length > 0 && resultIndices.Length < 1) {
        return -1
    }

    first := -1
    last := -1
    count := 0
    outputHead := -1
    outputTail := -1
    shortOutputHead := -1
    shortOutputTail := -1
    backendHead := -1
    backendTail := -1
    projectHead := -1
    projectTail := -1
    i := 0
    while i < args.Length {
        kind := CliBuildArgumentKind(args[i])
        kindIds[i] = kind
        nextIndices[i] = -1
        previousIndices[i] = -1
        nextOptionIndices[i] = -1

        if kind == 5 {
            kindIds[i] = -1
            i = i + 1
            continue
        }

        if last >= 0 {
            nextIndices[last] = i
            previousIndices[i] = last
        } else {
            first = i
        }

        last = i
        count = count + 1

        if kind == 1 {
            if outputTail >= 0 {
                nextOptionIndices[outputTail] = i
            } else {
                outputHead = i
            }

            outputTail = i
        } else if kind == 2 {
            if shortOutputTail >= 0 {
                nextOptionIndices[shortOutputTail] = i
            } else {
                shortOutputHead = i
            }

            shortOutputTail = i
        } else if kind == 3 {
            if backendTail >= 0 {
                nextOptionIndices[backendTail] = i
            } else {
                backendHead = i
            }

            backendTail = i
        } else if kind == 4 {
            if projectTail >= 0 {
                nextOptionIndices[projectTail] = i
            } else {
                projectHead = i
            }

            projectTail = i
        }

        i = i + 1
    }

    if resultIndices.Length > 0 {
        resultIndices[0] = first
    }

    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, outputHead, 1, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, shortOutputHead, 2, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, backendHead, 3, resultIndices, count)
    count = CliBuildRemoveOptionKindPairs(kindIds, nextIndices, previousIndices, nextOptionIndices, projectHead, 4, resultIndices, count)
    return count
}

func CliBuildOperandIndicesInto(
    args: string[],
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    resultIndices: int[]): int {
    count := CliBuildOperandSummaryInto(args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices)
    if count <= 0 {
        return count
    }

    sourceIndex := resultIndices[0]
    resultCount := 0
    while sourceIndex >= 0 {
        resultIndices[resultCount] = sourceIndex
        resultCount = resultCount + 1
        sourceIndex = nextIndices[sourceIndex]
    }

    return resultCount
}

func CliFixSafetyFilterIndicesInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    maxAppliedRank := 1
    if includeReviewNeeded != 0 {
        maxAppliedRank = 2
    }

    matchCount := 0
    length := safetyRanks.Length
    i := 0

    if resultIndices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            rank := safetyRanks[i]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = i
                matchCount = matchCount + 1
            }

            next := i + 1
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 2
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 3
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 4
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 5
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 6
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 7
            rank = safetyRanks[next]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = next
                matchCount = matchCount + 1
            }

            i = i + 8
        }

        while i < length {
            rank := safetyRanks[i]
            if rank > 0 && rank <= maxAppliedRank {
                resultIndices[matchCount] = i
                matchCount = matchCount + 1
            }

            i = i + 1
        }

        return matchCount
    }

    unrolledLimit := length - 4
    while i <= unrolledLimit {
        rank := safetyRanks[i]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        next := i + 1
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 2
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 3
        rank = safetyRanks[next]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        i = i + 4
    }

    while i < length {
        rank := safetyRanks[i]
        if rank > 0 && rank <= maxAppliedRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return matchCount
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

func CliFixSkippedIndicesInto(
    safetyRanks: int[],
    includeReviewNeeded: int,
    resultIndices: int[]): int {
    maxAppliedRank := 1
    if includeReviewNeeded != 0 {
        maxAppliedRank = 2
    }

    skippedCount := 0
    length := safetyRanks.Length
    i := 0
    while i < length {
        rank := safetyRanks[i]
        if rank == 0 || rank > maxAppliedRank {
            if skippedCount < resultIndices.Length {
                resultIndices[skippedCount] = i
            }

            skippedCount = skippedCount + 1
        }

        i = i + 1
    }

    return skippedCount
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

func CliCleanArtifactDirectoryIndicesInto(
    kindRanks: int[],
    nodeModuleFlags: int[],
    pathRanks: int[],
    pathLengths: int[],
    seenPathRanks: int[],
    lengthCounts: int[],
    lengthOffsets: int[],
    tempIndices: int[],
    resultIndices: int[]): int {
    length := kindRanks.Length
    if nodeModuleFlags.Length < length
        || pathRanks.Length < length
        || pathLengths.Length < length
        || tempIndices.Length < length
        || resultIndices.Length < length {
        return -1
    }

    i := 0
    while i < seenPathRanks.Length {
        seenPathRanks[i] = 0
        i = i + 1
    }

    i = 0
    while i < lengthCounts.Length {
        lengthCounts[i] = 0
        lengthOffsets[i] = 0
        i = i + 1
    }

    selectedCount := 0
    i = 0
    while i < length {
        kindRank := kindRanks[i]
        if kindRank > 0 && nodeModuleFlags[i] == 0 {
            pathRank := pathRanks[i]
            if pathRank <= 0 || pathRank >= seenPathRanks.Length {
                return -1
            }

            if seenPathRanks[pathRank] == 0 {
                pathLength := pathLengths[i]
                if pathLength < 0 || pathLength >= lengthCounts.Length {
                    return -1
                }

                seenPathRanks[pathRank] = 1
                tempIndices[selectedCount] = i
                lengthCounts[pathLength] = lengthCounts[pathLength] + 1
                selectedCount = selectedCount + 1
            }
        }

        i = i + 1
    }

    running := 0
    lengthRank := lengthCounts.Length - 1
    while lengthRank >= 0 {
        count := lengthCounts[lengthRank]
        lengthOffsets[lengthRank] = running
        running = running + count
        lengthRank = lengthRank - 1
    }

    i = 0
    while i < selectedCount {
        sourceIndex := tempIndices[i]
        pathLength := pathLengths[sourceIndex]
        outputIndex := lengthOffsets[pathLength]
        resultIndices[outputIndex] = sourceIndex
        lengthOffsets[pathLength] = outputIndex + 1
        i = i + 1
    }

    return selectedCount
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

func CliUpdateTargetNuGetDependencyIndicesInto(
    nameRanks: int[],
    targetNameRank: int,
    resultIndices: int[]): int {
    if targetNameRank <= 0 {
        return 0
    }

    length := nameRanks.Length
    resultCount := 0
    i := 0
    if resultIndices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            if nameRanks[i] == targetNameRank {
                resultIndices[resultCount] = i
                resultCount = resultCount + 1
            }

            next := i + 1
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 2
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 3
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 4
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 5
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 6
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            next = i + 7
            if nameRanks[next] == targetNameRank {
                resultIndices[resultCount] = next
                resultCount = resultCount + 1
            }

            i = i + 8
        }

        while i < length {
            if nameRanks[i] == targetNameRank {
                resultIndices[resultCount] = i
                resultCount = resultCount + 1
            }

            i = i + 1
        }

        return resultCount
    }

    while i < length {
        if nameRanks[i] == targetNameRank {
            if resultCount < resultIndices.Length {
                resultIndices[resultCount] = i
            }

            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
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

func CliArgumentIsOptionWithValue(arg: string, optionsWithValues: string[]): bool {
    i := 0
    while i < optionsWithValues.Length {
        if arg == optionsWithValues[i] {
            return true
        }

        i = i + 1
    }

    return false
}

func CliBuildRemoveOptionKindPairs(
    kindIds: int[],
    nextIndices: int[],
    previousIndices: int[],
    nextOptionIndices: int[],
    optionHead: int,
    optionKind: int,
    resultIndices: int[],
    count: int): int {
    sourceIndex := optionHead
    while sourceIndex >= 0 {
        nextOptionIndex := nextOptionIndices[sourceIndex]
        if kindIds[sourceIndex] == optionKind {
            valueIndex := nextIndices[sourceIndex]
            if valueIndex >= 0 {
                previousIndex := previousIndices[sourceIndex]
                afterIndex := nextIndices[valueIndex]
                if previousIndex >= 0 {
                    nextIndices[previousIndex] = afterIndex
                } else {
                    resultIndices[0] = afterIndex
                }

                if afterIndex >= 0 {
                    previousIndices[afterIndex] = previousIndex
                }

                kindIds[sourceIndex] = -1
                kindIds[valueIndex] = -1
                count = count - 2
            }
        }

        sourceIndex = nextOptionIndex
    }

    return count
}

func CliBuildArgumentKind(arg: string): int {
    length := arg.Length
    if length < 2 || arg[0] != '-' {
        return 0
    }

    if length == 2 {
        if arg[1] == 'o' {
            return 2
        }

        return 0
    }

    if arg[1] != '-' {
        return 0
    }

    if length == 5 {
        if arg[2] == 'a' && arg[3] == 'o' && arg[4] == 't' {
            return 5
        }

        return 0
    }

    if length == 8 {
        if arg[2] == 'o'
            && arg[3] == 'u'
            && arg[4] == 't'
            && arg[5] == 'p'
            && arg[6] == 'u'
            && arg[7] == 't' {
            return 1
        }

        return 0
    }

    if length == 9 {
        marker := arg[2]
        if marker == 'b'
            && arg[3] == 'a'
            && arg[4] == 'c'
            && arg[5] == 'k'
            && arg[6] == 'e'
            && arg[7] == 'n'
            && arg[8] == 'd' {
            return 3
        }

        if marker == 'p'
            && arg[3] == 'r'
            && arg[4] == 'o'
            && arg[5] == 'j'
            && arg[6] == 'e'
            && arg[7] == 'c'
            && arg[8] == 't' {
            return 4
        }

        if marker == 'r'
            && arg[3] == 'e'
            && arg[4] == 'l'
            && arg[5] == 'e'
            && arg[6] == 'a'
            && arg[7] == 's'
            && arg[8] == 'e' {
            return 5
        }

        if marker == 't'
            && arg[3] == 'i'
            && arg[4] == 'm'
            && arg[5] == 'i'
            && arg[6] == 'n'
            && arg[7] == 'g'
            && arg[8] == 's' {
            return 5
        }

        if marker == 'v'
            && arg[3] == 'e'
            && arg[4] == 'r'
            && arg[5] == 'b'
            && arg[6] == 'o'
            && arg[7] == 's'
            && arg[8] == 'e' {
            return 5
        }

        return 0
    }

    if length == 13
        && arg[2] == 'p'
        && arg[3] == 'e'
        && arg[4] == 'r'
        && arg[5] == 'f'
        && arg[6] == '-'
        && arg[7] == 'r'
        && arg[8] == 'e'
        && arg[9] == 'p'
        && arg[10] == 'o'
        && arg[11] == 'r'
        && arg[12] == 't' {
        return 5
    }

    return 0
}

func CliArgumentIsValueLessFlag(arg: string): bool {
    if arg == "--check" {
        return true
    }

    if arg == "--verify-no-changes" {
        return true
    }

    if arg == "--diff" {
        return true
    }

    if arg == "--stdin" {
        return true
    }

    if arg == "--verbose" {
        return true
    }

    return false
}

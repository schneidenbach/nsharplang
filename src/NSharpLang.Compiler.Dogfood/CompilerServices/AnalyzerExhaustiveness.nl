func AnalyzerMissingMemberIndicesInto(
    coveredFlags: int[],
    count: int,
    resultIndices: int[]): int {
    if count < 0 || count > coveredFlags.Length || count > resultIndices.Length {
        return -1
    }

    resultCount := 0
    i := 0
    while i < count {
        if coveredFlags[i] == 0 {
            resultIndices[resultCount] = i
            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func AnalyzerMissingMemberChecksumInto(
    coveredFlags: int[],
    count: int,
    nameWeights: int[],
    resultIndices: int[]): int {
    missingCount := AnalyzerMissingMemberIndicesInto(coveredFlags, count, resultIndices)
    if missingCount < 0 {
        return missingCount
    }

    checksum := missingCount
    i := 0
    while i < missingCount {
        sourceIndex := resultIndices[i]
        weight := 0
        if sourceIndex >= 0 && sourceIndex < nameWeights.Length {
            weight = nameWeights[sourceIndex]
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + weight * 17
        i = i + 1
    }

    return checksum
}

func AnalyzerUnionMissingCaseIndicesInto(
    coveredFlags: int[],
    partialFlags: int[],
    count: int,
    missingIndices: int[],
    partialMissingIndices: int[],
    neverCoveredIndices: int[],
    resultCounts: int[]): int {
    if count < 0 ||
        count > coveredFlags.Length ||
        count > partialFlags.Length ||
        count > missingIndices.Length ||
        count > partialMissingIndices.Length ||
        count > neverCoveredIndices.Length ||
        resultCounts.Length < 3 {
        return -1
    }

    missingCount := 0
    partialMissingCount := 0
    neverCoveredCount := 0
    i := 0
    while i < count {
        if coveredFlags[i] == 0 {
            missingIndices[missingCount] = i
            missingCount = missingCount + 1

            if partialFlags[i] != 0 {
                partialMissingIndices[partialMissingCount] = i
                partialMissingCount = partialMissingCount + 1
            } else {
                neverCoveredIndices[neverCoveredCount] = i
                neverCoveredCount = neverCoveredCount + 1
            }
        }

        i = i + 1
    }

    resultCounts[0] = missingCount
    resultCounts[1] = partialMissingCount
    resultCounts[2] = neverCoveredCount
    return missingCount
}

func AnalyzerUnionMissingCaseChecksumInto(
    coveredFlags: int[],
    partialFlags: int[],
    count: int,
    nameWeights: int[],
    missingIndices: int[],
    partialMissingIndices: int[],
    neverCoveredIndices: int[],
    resultCounts: int[]): int {
    missingCount := AnalyzerUnionMissingCaseIndicesInto(
        coveredFlags,
        partialFlags,
        count,
        missingIndices,
        partialMissingIndices,
        neverCoveredIndices,
        resultCounts)
    if missingCount < 0 {
        return missingCount
    }

    checksum := missingCount * 31 + resultCounts[1] * 17 + resultCounts[2] * 13
    i := 0
    while i < missingCount {
        sourceIndex := missingIndices[i]
        weight := 0
        if sourceIndex >= 0 && sourceIndex < nameWeights.Length {
            weight = nameWeights[sourceIndex]
        }

        checksum = checksum + (i + 1) * 97 + (sourceIndex + 1) * 31 + weight * 17
        i = i + 1
    }

    i = 0
    while i < resultCounts[1] {
        sourceIndex := partialMissingIndices[i]
        checksum = checksum + (i + 1) * 43 + (sourceIndex + 1) * 19
        i = i + 1
    }

    i = 0
    while i < resultCounts[2] {
        sourceIndex := neverCoveredIndices[i]
        checksum = checksum + (i + 1) * 37 + (sourceIndex + 1) * 23
        i = i + 1
    }

    return checksum
}

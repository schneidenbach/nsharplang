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

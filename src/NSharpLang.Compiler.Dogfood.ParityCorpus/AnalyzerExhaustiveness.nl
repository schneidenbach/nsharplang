// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/AnalyzerExhaustiveness.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

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

// Batched distinctness checksum used for benchmark/parity. Each candidate row is projected like the
// single-shot kernel above (ranks in candidateRanks, per-candidate start in candidateOffsets, length
// in candidateLengths). For each candidate the kernel scans the same packed existing-overload table
// and folds the distinct/duplicate verdict into a stable checksum, also recording 1/0 verdicts into a
// caller-owned results buffer. Returns the checksum, or -1 on a malformed request.
func AnalyzerOverloadSignatureDistinctChecksumInto(
    candidateRanks: int[],
    candidateOffsets: int[],
    candidateLengths: int[],
    candidateCount: int,
    existingRanks: int[],
    existingOffsets: int[],
    existingLengths: int[],
    existingCount: int,
    results: int[]): int {
    if candidateCount < 0 ||
        candidateCount > candidateOffsets.Length ||
        candidateCount > candidateLengths.Length ||
        candidateCount > results.Length {
        return -1
    }

    checksum := candidateCount
    distinctCount := 0
    c := 0
    while c < candidateCount {
        candidateLength := candidateLengths[c]
        candidateOffset := candidateOffsets[c]
        if candidateLength < 0 ||
            candidateOffset < 0 ||
            candidateLength > candidateRanks.Length ||
            candidateOffset > candidateRanks.Length - candidateLength {
            return -1
        }

        verdict := AnalyzerOverloadSignatureDistinctSlice(
            candidateRanks,
            candidateOffset,
            candidateLength,
            existingRanks,
            existingOffsets,
            existingLengths,
            existingCount)
        if verdict < 0 {
            return -1
        }

        results[c] = verdict
        if verdict == 1 {
            distinctCount = distinctCount + 1
        }

        checksum = checksum + (c + 1) * 131 + (verdict + 1) * 17 + (candidateLength + 1) * 7
        c = c + 1
    }

    checksum = checksum + distinctCount * 9973
    return checksum
}

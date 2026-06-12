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

// Overload parameter-signature distinctness, compact-rank form.
//
// Each function declaration's parameter list is projected by the caller into a row of stable
// parameter-type ranks (one int per parameter; distinct .NET/N# type signatures map to distinct
// ranks). The candidate row lives at candidateRanks[0..candidateLength). Existing overload rows are
// packed contiguously into existingRanks with per-row start offsets in existingOffsets and per-row
// lengths in existingLengths (existingCount rows total).
//
// Returns 1 when the candidate signature is distinct from every existing row (a new overload),
// 0 when some existing row has the same arity and identical rank sequence (a duplicate), and -1 on
// a malformed request. This replaces the C# GetParameterTypeSignature string build + string `!=`
// comparison with a single integer-rank scan over caller-owned buffers.
func AnalyzerOverloadSignatureDistinct(
    candidateRanks: int[],
    candidateLength: int,
    existingRanks: int[],
    existingOffsets: int[],
    existingLengths: int[],
    existingCount: int): int {
    if candidateLength < 0 ||
        candidateLength > candidateRanks.Length ||
        existingCount < 0 ||
        existingCount > existingOffsets.Length ||
        existingCount > existingLengths.Length {
        return -1
    }

    row := 0
    while row < existingCount {
        existingLength := existingLengths[row]
        if existingLength == candidateLength {
            offset := existingOffsets[row]
            // Subtraction-form bounds check avoids int overflow on offset + length for
            // adversarial descriptors; offset and length are already known non-negative here
            // (candidateLength >= 0 was validated and existingLength == candidateLength).
            if offset < 0 || existingLength > existingRanks.Length || offset > existingRanks.Length - existingLength {
                return -1
            }

            matches := true
            i := 0
            while i < existingLength {
                if existingRanks[offset + i] != candidateRanks[i] {
                    matches = false
                    i = existingLength
                } else {
                    i = i + 1
                }
            }

            if matches {
                return 0
            }
        }

        row = row + 1
    }

    return 1
}

// Distinctness verdict for a candidate row stored at an arbitrary offset inside candidateRanks. Used
// by the batched checksum kernel so each candidate can share one packed candidate-rank buffer.
func AnalyzerOverloadSignatureDistinctSlice(
    candidateRanks: int[],
    candidateOffset: int,
    candidateLength: int,
    existingRanks: int[],
    existingOffsets: int[],
    existingLengths: int[],
    existingCount: int): int {
    if candidateOffset < 0 ||
        candidateLength < 0 ||
        candidateLength > candidateRanks.Length ||
        candidateOffset > candidateRanks.Length - candidateLength ||
        existingCount < 0 ||
        existingCount > existingOffsets.Length ||
        existingCount > existingLengths.Length {
        return -1
    }

    row := 0
    while row < existingCount {
        existingLength := existingLengths[row]
        if existingLength == candidateLength {
            offset := existingOffsets[row]
            // Subtraction-form bounds check (offset/length already non-negative) avoids
            // int overflow on offset + length for adversarial existing-row descriptors.
            if offset < 0 || existingLength > existingRanks.Length || offset > existingRanks.Length - existingLength {
                return -1
            }

            matches := true
            i := 0
            while i < existingLength {
                if existingRanks[offset + i] != candidateRanks[candidateOffset + i] {
                    matches = false
                    i = existingLength
                } else {
                    i = i + 1
                }
            }

            if matches {
                return 0
            }
        }

        row = row + 1
    }

    return 1
}

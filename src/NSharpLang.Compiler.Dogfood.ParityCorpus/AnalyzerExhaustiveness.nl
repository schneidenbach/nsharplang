// PARITY CORPUS (Arc M1): checksum fixtures extracted from
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

struct AnalyzerSignatureRankBuffer {
    Ranks: int[]
}

struct AnalyzerOverloadSignatureTable {
    Ranks: int[]
    Offsets: int[]
    Lengths: int[]
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
// a malformed request. This replaces the old string-signature build + string `!=`
// comparison with a single integer-rank scan over caller-owned buffers.
func AnalyzerOverloadSignatureDistinct(
    candidateRanks: int[],
    candidateLength: int,
    existingRanks: int[],
    existingOffsets: int[],
    existingLengths: int[],
    existingCount: int): int {
    candidate := new AnalyzerSignatureRankBuffer { Ranks: candidateRanks }
    existing := new AnalyzerOverloadSignatureTable { Ranks: existingRanks, Offsets: existingOffsets, Lengths: existingLengths }
    return AnalyzerOverloadSignatureDistinctCore(ref candidate, 0, candidateLength, ref existing, existingCount)
}

func AnalyzerOverloadSignatureDistinctCore(
    candidate: &AnalyzerSignatureRankBuffer,
    candidateOffset: int,
    candidateLength: int,
    existing: &AnalyzerOverloadSignatureTable,
    existingCount: int): int {
    if candidateOffset < 0 ||
        candidateLength < 0 ||
        candidateLength > candidate.Ranks.Length ||
        candidateOffset > candidate.Ranks.Length - candidateLength ||
        existingCount < 0 ||
        existingCount > existing.Offsets.Length ||
        existingCount > existing.Lengths.Length {
        return -1
    }

    row := 0
    while row < existingCount {
        existingLength := existing.Lengths[row]
        if existingLength == candidateLength {
            offset := existing.Offsets[row]
            // Subtraction-form bounds check (offset/length already non-negative) avoids
            // int overflow on offset + length for adversarial existing-row descriptors.
            if offset < 0 || existingLength > existing.Ranks.Length || offset > existing.Ranks.Length - existingLength {
                return -1
            }

            matches := true
            i := 0
            while i < existingLength {
                if existing.Ranks[offset + i] != candidate.Ranks[candidateOffset + i] {
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

    candidate := new AnalyzerSignatureRankBuffer { Ranks: candidateRanks }
    existing := new AnalyzerOverloadSignatureTable { Ranks: existingRanks, Offsets: existingOffsets, Lengths: existingLengths }

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

        verdict := AnalyzerOverloadSignatureDistinctCore(ref candidate, candidateOffset, candidateLength, ref existing, existingCount)
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

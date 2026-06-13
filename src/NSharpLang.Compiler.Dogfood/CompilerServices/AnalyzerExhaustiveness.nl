struct AnalyzerMemberCoverageTable {
    CoveredFlags: int[]
}

struct AnalyzerUnionCoverageTable {
    CoveredFlags: int[]
    PartialFlags: int[]
}

struct AnalyzerMissingMemberResultTable {
    Indices: int[]
}

struct AnalyzerUnionMissingCaseResultTable {
    MissingIndices: int[]
    PartialMissingIndices: int[]
    NeverCoveredIndices: int[]
    Counts: int[]
}

struct AnalyzerSignatureRankBuffer {
    Ranks: int[]
}

struct AnalyzerOverloadSignatureTable {
    Ranks: int[]
    Offsets: int[]
    Lengths: int[]
}

func AnalyzerMissingMemberIndicesInto(
    coveredFlags: int[],
    count: int,
    resultIndices: int[]): int {
    coverage := new AnalyzerMemberCoverageTable { CoveredFlags: coveredFlags }
    result := new AnalyzerMissingMemberResultTable { Indices: resultIndices }
    return AnalyzerMissingMemberIndicesCore(ref coverage, count, ref result)
}

func AnalyzerMissingMemberIndicesCore(
    coverage: &AnalyzerMemberCoverageTable,
    count: int,
    result: &AnalyzerMissingMemberResultTable): int {
    if count < 0 || count > coverage.CoveredFlags.Length || count > result.Indices.Length {
        return -1
    }

    resultCount := 0
    i := 0
    while i < count {
        if coverage.CoveredFlags[i] == 0 {
            result.Indices[resultCount] = i
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
    coverage := new AnalyzerUnionCoverageTable { CoveredFlags: coveredFlags, PartialFlags: partialFlags }
    result := new AnalyzerUnionMissingCaseResultTable {
        MissingIndices: missingIndices,
        PartialMissingIndices: partialMissingIndices,
        NeverCoveredIndices: neverCoveredIndices,
        Counts: resultCounts
    }
    return AnalyzerUnionMissingCaseIndicesCore(ref coverage, count, ref result)
}

func AnalyzerUnionMissingCaseIndicesCore(
    coverage: &AnalyzerUnionCoverageTable,
    count: int,
    result: &AnalyzerUnionMissingCaseResultTable): int {
    if count < 0 ||
        count > coverage.CoveredFlags.Length ||
        count > coverage.PartialFlags.Length ||
        count > result.MissingIndices.Length ||
        count > result.PartialMissingIndices.Length ||
        count > result.NeverCoveredIndices.Length ||
        result.Counts.Length < 3 {
        return -1
    }

    missingCount := 0
    partialMissingCount := 0
    neverCoveredCount := 0
    i := 0
    while i < count {
        if coverage.CoveredFlags[i] == 0 {
            result.MissingIndices[missingCount] = i
            missingCount = missingCount + 1

            if coverage.PartialFlags[i] != 0 {
                result.PartialMissingIndices[partialMissingCount] = i
                partialMissingCount = partialMissingCount + 1
            } else {
                result.NeverCoveredIndices[neverCoveredCount] = i
                neverCoveredCount = neverCoveredCount + 1
            }
        }

        i = i + 1
    }

    result.Counts[0] = missingCount
    result.Counts[1] = partialMissingCount
    result.Counts[2] = neverCoveredCount
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
    candidate := new AnalyzerSignatureRankBuffer { Ranks: candidateRanks }
    existing := new AnalyzerOverloadSignatureTable { Ranks: existingRanks, Offsets: existingOffsets, Lengths: existingLengths }
    return AnalyzerOverloadSignatureDistinctCore(ref candidate, 0, candidateLength, ref existing, existingCount)
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
    candidate := new AnalyzerSignatureRankBuffer { Ranks: candidateRanks }
    existing := new AnalyzerOverloadSignatureTable { Ranks: existingRanks, Offsets: existingOffsets, Lengths: existingLengths }
    return AnalyzerOverloadSignatureDistinctCore(ref candidate, candidateOffset, candidateLength, ref existing, existingCount)
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

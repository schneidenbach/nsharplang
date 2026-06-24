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

func AnalyzerMissingMemberNamesInto(memberNames: string[], coveredNames: string[], resultNames: string[]): int {
    count := AnalyzerExhaustivenessMinInt(memberNames.Length, resultNames.Length)

    resultCount := 0
    i := 0
    while i < count {
        memberName := memberNames[i]
        if !AnalyzerExhaustivenessContainsName(coveredNames, memberName) {
            resultNames[resultCount] = memberName
            resultCount = resultCount + 1
        }

        i = i + 1
    }

    return resultCount
}

func AnalyzerExhaustivenessContainsName(names: string[], target: string): bool {
    i := 0
    while i < names.Length {
        if names[i] == target {
            return true
        }

        i = i + 1
    }

    return false
}

struct AnalyzerUnionMissingCaseResultTable {
    MissingIndices: int[]
    PartialMissingIndices: int[]
    NeverCoveredIndices: int[]
    Counts: int[]
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

func AnalyzerExhaustivenessMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

// PARITY CORPUS (Arc M1): checksum fixtures extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/OverloadCandidates.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

struct OverloadCandidateParameterTypeTable {
    Offsets: int[]
    Counts: int[]
    TypeIds: int[]
}

struct OverloadArgumentTypeTable {
    TypeIds: int[]
}

struct OverloadCallSliceTable {
    Offsets: int[]
    Counts: int[]
}

struct OverloadSelectionResultTable {
    Indices: int[]
}

func OverloadCandidateTableCountFits(
    candidates: &OverloadCandidateScoreTable,
    parameterTypes: &OverloadCandidateParameterTypeTable,
    count: int): bool {
    return OverloadCandidateCountFits(ref candidates, count)
        && count <= parameterTypes.Offsets.Length
        && count <= parameterTypes.Counts.Length
}

func OverloadCandidateParameterRangeFits(parameterTypes: &OverloadCandidateParameterTypeTable, index: int): bool {
    offset := parameterTypes.Offsets[index]
    count := parameterTypes.Counts[index]
    return offset >= 0 && count >= 0 && offset + count <= parameterTypes.TypeIds.Length
}

func OverloadSelectBestCandidateFromTableCore(
    candidates: &OverloadCandidateScoreTable,
    parameterTypes: &OverloadCandidateParameterTypeTable,
    arguments: &OverloadArgumentTypeTable,
    argCount: int,
    count: int): int {
    if !OverloadCandidateTableCountFits(ref candidates, ref parameterTypes, count) {
        return -2
    }

    if argCount < 0 || argCount > arguments.TypeIds.Length {
        return -2
    }

    bestIndex := -1
    bestScore := -1
    bestIsGeneric := 1
    bestUsesParams := 1
    bestDefaultsUsed := 2147483647

    i := 0
    while i < count {
        candidateValid := candidates.ValidFlags[i] != 0
        if candidateValid {
            if !OverloadCandidateParameterRangeFits(ref parameterTypes, i) {
                candidateValid = false
            }
        }

        if candidateValid {
            score := candidates.Scores[i]
            isGeneric := candidates.GenericFlags[i]
            usesParams := candidates.ParamsFlags[i]
            defaults := candidates.DefaultsUsed[i]

            if OverloadCandidateShouldTake(bestIndex, bestScore, bestIsGeneric, bestUsesParams, bestDefaultsUsed, score, isGeneric, usesParams, defaults) {
                bestIndex = i
                bestScore = score
                bestIsGeneric = isGeneric
                bestUsesParams = usesParams
                bestDefaultsUsed = defaults
            }
        }

        i = i + 1
    }

    return bestIndex
}

func OverloadSelectBatchCore(
    candidates: &OverloadCandidateScoreTable,
    calls: &OverloadCallSliceTable,
    callCount: int,
    result: &OverloadSelectionResultTable): int {
    if callCount < 0 || callCount > calls.Offsets.Length || callCount > calls.Counts.Length
        || callCount > result.Indices.Length {
        return -1
    }

    resolvedCount := 0
    c := 0
    while c < callCount {
        offset := calls.Offsets[c]
        candidateCount := calls.Counts[c]
        bestIndex := -1

        if offset >= 0 && candidateCount >= 0
            && offset <= candidates.ValidFlags.Length - candidateCount
            && offset <= candidates.Scores.Length - candidateCount
            && offset <= candidates.GenericFlags.Length - candidateCount
            && offset <= candidates.ParamsFlags.Length - candidateCount
            && offset <= candidates.DefaultsUsed.Length - candidateCount {
            bestScore := -1
            bestIsGeneric := 1
            bestUsesParams := 1
            bestDefaultsUsed := 2147483647

            i := 0
            while i < candidateCount {
                slot := offset + i
                if candidates.ValidFlags[slot] != 0 {
                    score := candidates.Scores[slot]
                    isGeneric := candidates.GenericFlags[slot]
                    usesParams := candidates.ParamsFlags[slot]
                    defaults := candidates.DefaultsUsed[slot]

                    if OverloadCandidateShouldTake(bestIndex, bestScore, bestIsGeneric, bestUsesParams, bestDefaultsUsed, score, isGeneric, usesParams, defaults) {
                        bestIndex = i
                        bestScore = score
                        bestIsGeneric = isGeneric
                        bestUsesParams = usesParams
                        bestDefaultsUsed = defaults
                    }
                }

                i = i + 1
            }
        }

        result.Indices[c] = bestIndex
        if bestIndex >= 0 {
            resolvedCount = resolvedCount + 1
        }

        c = c + 1
    }

    return resolvedCount
}

// Checksum wrapper used by parity benchmarks/tests. Folds the selected candidate index together
// with its rank columns so a single returned int proves both selection and the resolved rank tuple.
func OverloadSelectBestCandidateChecksum(
    validFlags: int[],
    scores: int[],
    genericFlags: int[],
    paramsFlags: int[],
    defaultsUsed: int[],
    paramTypeOffsets: int[],
    paramTypeCounts: int[],
    paramTypeIds: int[],
    argTypeIds: int[],
    argCount: int,
    count: int): int {
    candidates := new OverloadCandidateScoreTable { ValidFlags: validFlags, Scores: scores, GenericFlags: genericFlags, ParamsFlags: paramsFlags, DefaultsUsed: defaultsUsed }
    parameterTypes := new OverloadCandidateParameterTypeTable { Offsets: paramTypeOffsets, Counts: paramTypeCounts, TypeIds: paramTypeIds }
    arguments := new OverloadArgumentTypeTable { TypeIds: argTypeIds }
    bestIndex := OverloadSelectBestCandidateFromTableCore(ref candidates, ref parameterTypes, ref arguments, argCount, count)

    if bestIndex < 0 {
        return bestIndex
    }

    checksum := (bestIndex + 1) * 97
        + scores[bestIndex] * 31
        + genericFlags[bestIndex] * 17
        + paramsFlags[bestIndex] * 13
        + defaultsUsed[bestIndex] * 7
        + paramTypeCounts[bestIndex] * 3
    return checksum
}

func OverloadSelectBatchChecksumInto(
    validFlags: int[],
    scores: int[],
    genericFlags: int[],
    paramsFlags: int[],
    defaultsUsed: int[],
    callOffsets: int[],
    callCounts: int[],
    callCount: int,
    resultIndices: int[]): int {
    candidates := new OverloadCandidateScoreTable { ValidFlags: validFlags, Scores: scores, GenericFlags: genericFlags, ParamsFlags: paramsFlags, DefaultsUsed: defaultsUsed }
    calls := new OverloadCallSliceTable { Offsets: callOffsets, Counts: callCounts }
    result := new OverloadSelectionResultTable { Indices: resultIndices }
    resolvedCount := OverloadSelectBatchCore(ref candidates, ref calls, callCount, ref result)

    if resolvedCount < 0 {
        return resolvedCount
    }

    checksum := resolvedCount
    c := 0
    while c < callCount {
        localIndex := resultIndices[c]
        if localIndex >= 0 {
            slot := callOffsets[c] + localIndex
            checksum = checksum
                + (c + 1) * 97
                + (localIndex + 1) * 31
                + scores[slot] * 17
                + genericFlags[slot] * 13
                + paramsFlags[slot] * 7
                + defaultsUsed[slot] * 3
        }

        c = c + 1
    }

    return checksum
}

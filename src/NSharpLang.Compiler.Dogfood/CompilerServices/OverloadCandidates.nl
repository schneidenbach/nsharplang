// Compact overload-candidate ranking for the IL compiler declared-method binder.
//
// The C# baseline (ILCompiler.BindDeclaredMethodCall) materializes the overload set with
// `.ToList()`, projects `GetParameters().Select(...).ToArray()` per candidate, and runs a
// four-level tie-break (score > non-generic > non-params > fewer-defaults) while allocating a
// BoundDeclaredMethodCall per improving candidate. This kernel represents the overload set as
// compact primitive columns computed once by the host and selects the winning candidate index by
// scanning those columns, with the EXACT same first-wins-on-tie order as the C# loop.
//
// Compact candidate columns (one entry per candidate, candidate order = source overload order):
//   validFlags[i]    - 1 when the candidate bound successfully (predicate + parameter bind), else 0
//   scores[i]        - bind score (higher is better)
//   genericFlags[i]  - 1 when the declaration is generic, else 0 (non-generic preferred)
//   paramsFlags[i]   - 1 when the candidate uses a params expansion, else 0 (non-params preferred)
//   defaultsUsed[i]  - count of parameters filled from defaults (fewer preferred)
//
// The broader compact table also carries the per-candidate parameter type ids, flattened into a
// single array with per-candidate offsets and counts, so callers can verify and reuse a single
// owned buffer instead of re-projecting GetParameters() per candidate:
//   paramTypeOffsets[i] - start index of candidate i's parameter type ids in paramTypeIds
//   paramTypeCounts[i]  - number of parameter type ids for candidate i
//   paramTypeIds[]      - flattened parameter type ids for all candidates
//   argTypeIds[]        - the call-site argument type ids (length = argCount)

struct OverloadCandidateScoreTable {
    ValidFlags: int[]
    Scores: int[]
    GenericFlags: int[]
    ParamsFlags: int[]
    DefaultsUsed: int[]
}

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

func OverloadCandidateCountFits(candidates: &OverloadCandidateScoreTable, count: int): bool {
    return count >= 0
        && count <= candidates.ValidFlags.Length
        && count <= candidates.Scores.Length
        && count <= candidates.GenericFlags.Length
        && count <= candidates.ParamsFlags.Length
        && count <= candidates.DefaultsUsed.Length
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

func OverloadCandidateShouldTake(
    bestIndex: int,
    bestScore: int,
    bestIsGeneric: int,
    bestUsesParams: int,
    bestDefaultsUsed: int,
    score: int,
    isGeneric: int,
    usesParams: int,
    defaults: int): bool {
    if bestIndex < 0 {
        return true
    }

    if score > bestScore {
        return true
    }

    if score == bestScore && bestIsGeneric != 0 && isGeneric == 0 {
        return true
    }

    if score == bestScore
        && bestIsGeneric == isGeneric
        && bestUsesParams != 0
        && usesParams == 0 {
        return true
    }

    return score == bestScore
        && bestIsGeneric == isGeneric
        && bestUsesParams == usesParams
        && defaults < bestDefaultsUsed
}

func OverloadSelectBestCandidate(
    validFlags: int[],
    scores: int[],
    genericFlags: int[],
    paramsFlags: int[],
    defaultsUsed: int[],
    count: int): int {
    candidates := new OverloadCandidateScoreTable { ValidFlags: validFlags, Scores: scores, GenericFlags: genericFlags, ParamsFlags: paramsFlags, DefaultsUsed: defaultsUsed }
    return OverloadSelectBestCandidateCore(ref candidates, count)
}

func OverloadSelectBestCandidateCore(candidates: &OverloadCandidateScoreTable, count: int): int {
    if !OverloadCandidateCountFits(ref candidates, count) {
        return -2
    }

    bestIndex := -1
    bestScore := -1
    bestIsGeneric := 1
    bestUsesParams := 1
    bestDefaultsUsed := 2147483647

    i := 0
    while i < count {
        if candidates.ValidFlags[i] != 0 {
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

// Broader compact-table entry point: validates the flattened parameter-type-id table bounds before
// selecting, then returns the winning candidate index. This is the table-owning shape the IL binder
// uses: parameter type ids are stored once in a flat buffer instead of re-projecting
// GetParameters() per candidate. The supplied argument-type-id array is bounds-validated so a single
// caller-owned buffer can be reused across call sites.
func OverloadSelectBestCandidateFromTable(
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
    return OverloadSelectBestCandidateFromTableCore(ref candidates, ref parameterTypes, ref arguments, argCount, count)
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

// Batch entry point: resolves a whole stream of call sites against a shared compact candidate table
// in one N#-owned loop, writing the selected candidate index per call into caller-owned storage.
// callOffsets[c]/callCounts[c] describe the contiguous candidate slice for call site c inside the
// shared candidate columns. Returns the number of call sites that resolved to a candidate.
func OverloadSelectBatchInto(
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
    return OverloadSelectBatchCore(ref candidates, ref calls, callCount, ref result)
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

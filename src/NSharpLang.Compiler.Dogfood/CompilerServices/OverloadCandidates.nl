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

func OverloadSelectBestCandidate(
    validFlags: int[],
    scores: int[],
    genericFlags: int[],
    paramsFlags: int[],
    defaultsUsed: int[],
    count: int): int {
    if count < 0
        || count > validFlags.Length
        || count > scores.Length
        || count > genericFlags.Length
        || count > paramsFlags.Length
        || count > defaultsUsed.Length {
        return -2
    }

    bestIndex := -1
    bestScore := -1
    bestIsGeneric := 1
    bestUsesParams := 1
    bestDefaultsUsed := 2147483647

    i := 0
    while i < count {
        if validFlags[i] != 0 {
            score := scores[i]
            isGeneric := genericFlags[i]
            usesParams := paramsFlags[i]
            defaults := defaultsUsed[i]

            takeCandidate := false
            if bestIndex < 0 {
                takeCandidate = true
            } else if score > bestScore {
                takeCandidate = true
            } else if score == bestScore && bestIsGeneric != 0 && isGeneric == 0 {
                takeCandidate = true
            } else if score == bestScore
                && bestIsGeneric == isGeneric
                && bestUsesParams != 0
                && usesParams == 0 {
                takeCandidate = true
            } else if score == bestScore
                && bestIsGeneric == isGeneric
                && bestUsesParams == usesParams
                && defaults < bestDefaultsUsed {
                takeCandidate = true
            }

            if takeCandidate {
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
    if count < 0
        || count > validFlags.Length
        || count > scores.Length
        || count > genericFlags.Length
        || count > paramsFlags.Length
        || count > defaultsUsed.Length
        || count > paramTypeOffsets.Length
        || count > paramTypeCounts.Length {
        return -2
    }

    if argCount < 0 || argCount > argTypeIds.Length {
        return -2
    }

    bestIndex := -1
    bestScore := -1
    bestIsGeneric := 1
    bestUsesParams := 1
    bestDefaultsUsed := 2147483647

    i := 0
    while i < count {
        candidateValid := validFlags[i] != 0
        if candidateValid {
            offset := paramTypeOffsets[i]
            paramCount := paramTypeCounts[i]
            if offset < 0 || paramCount < 0 || offset + paramCount > paramTypeIds.Length {
                candidateValid = false
            }
        }

        if candidateValid {
            score := scores[i]
            isGeneric := genericFlags[i]
            usesParams := paramsFlags[i]
            defaults := defaultsUsed[i]

            takeCandidate := false
            if bestIndex < 0 {
                takeCandidate = true
            } else if score > bestScore {
                takeCandidate = true
            } else if score == bestScore && bestIsGeneric != 0 && isGeneric == 0 {
                takeCandidate = true
            } else if score == bestScore
                && bestIsGeneric == isGeneric
                && bestUsesParams != 0
                && usesParams == 0 {
                takeCandidate = true
            } else if score == bestScore
                && bestIsGeneric == isGeneric
                && bestUsesParams == usesParams
                && defaults < bestDefaultsUsed {
                takeCandidate = true
            }

            if takeCandidate {
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
    if callCount < 0 || callCount > callOffsets.Length || callCount > callCounts.Length
        || callCount > resultIndices.Length {
        return -1
    }

    resolvedCount := 0
    c := 0
    while c < callCount {
        offset := callOffsets[c]
        candidateCount := callCounts[c]
        bestIndex := -1

        if offset >= 0 && candidateCount >= 0
            && offset <= validFlags.Length - candidateCount
            && offset <= scores.Length - candidateCount
            && offset <= genericFlags.Length - candidateCount
            && offset <= paramsFlags.Length - candidateCount
            && offset <= defaultsUsed.Length - candidateCount {
            bestScore := -1
            bestIsGeneric := 1
            bestUsesParams := 1
            bestDefaultsUsed := 2147483647

            i := 0
            while i < candidateCount {
                slot := offset + i
                if validFlags[slot] != 0 {
                    score := scores[slot]
                    isGeneric := genericFlags[slot]
                    usesParams := paramsFlags[slot]
                    defaults := defaultsUsed[slot]

                    takeCandidate := false
                    if bestIndex < 0 {
                        takeCandidate = true
                    } else if score > bestScore {
                        takeCandidate = true
                    } else if score == bestScore && bestIsGeneric != 0 && isGeneric == 0 {
                        takeCandidate = true
                    } else if score == bestScore
                        && bestIsGeneric == isGeneric
                        && bestUsesParams != 0
                        && usesParams == 0 {
                        takeCandidate = true
                    } else if score == bestScore
                        && bestIsGeneric == isGeneric
                        && bestUsesParams == usesParams
                        && defaults < bestDefaultsUsed {
                        takeCandidate = true
                    }

                    if takeCandidate {
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

        resultIndices[c] = bestIndex
        if bestIndex >= 0 {
            resolvedCount = resolvedCount + 1
        }

        c = c + 1
    }

    return resolvedCount
}

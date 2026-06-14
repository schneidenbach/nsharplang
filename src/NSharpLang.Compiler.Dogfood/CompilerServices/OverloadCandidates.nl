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
// Wider table and batch-selection parity probes live in the parity corpus so the shipped dogfood
// assembly exposes only the scalar route used by the compiler adapter.

struct OverloadCandidateScoreTable {
    ValidFlags: int[]
    Scores: int[]
    GenericFlags: int[]
    ParamsFlags: int[]
    DefaultsUsed: int[]
}

func OverloadCandidateCountFits(candidates: &OverloadCandidateScoreTable, count: int): bool {
    return count >= 0
        && count <= candidates.ValidFlags.Length
        && count <= candidates.Scores.Length
        && count <= candidates.GenericFlags.Length
        && count <= candidates.ParamsFlags.Length
        && count <= candidates.DefaultsUsed.Length
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

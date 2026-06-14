// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/OverloadCandidates.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

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

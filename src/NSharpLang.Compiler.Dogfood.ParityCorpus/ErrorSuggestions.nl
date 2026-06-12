// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/ErrorSuggestions.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func TypoSuggestionChecksumInto(
    typos: string[],
    candidates: string[],
    maxSuggestions: int,
    previousDistances: int[],
    currentDistances: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultIndices: int[]): int {
    queryCount := TypoSuggestionMinInt(typos.Length, resultStarts.Length)
    queryCount = TypoSuggestionMinInt(queryCount, resultCounts.Length)
    total := TypoSuggestionIndicesInto(
        typos,
        candidates,
        maxSuggestions,
        previousDistances,
        currentDistances,
        resultStarts,
        resultCounts,
        resultIndices)

    checksum := total
    i := 0
    while i < queryCount {
        start := resultStarts[i]
        count := resultCounts[i]
        checksum = checksum + start * 7 + count * 97

        j := 0
        while j < count {
            index := start + j
            if index >= 0 && index < resultIndices.Length {
                checksum = checksum + resultIndices[index] * 31 + (j + 1) * 17
            }

            j = j + 1
        }

        i = i + 1
    }

    return checksum
}

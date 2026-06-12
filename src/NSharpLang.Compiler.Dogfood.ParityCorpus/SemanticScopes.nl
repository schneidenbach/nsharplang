// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/SemanticScopes.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func SemanticScopeVisibleSymbolChecksumInto(
    scopeParentIds: int[],
    scopeStartLines: int[],
    scopeStartColumns: int[],
    scopeEndLines: int[],
    scopeEndColumns: int[],
    scopeDepths: int[],
    scopeSymbolStarts: int[],
    scopeSymbolCounts: int[],
    symbolNameIds: int[],
    symbolNameLengths: int[],
    symbolTypeNameLengths: int[],
    sortedScopeIds: int[],
    sortedScopeStartLines: int[],
    sortedScopeStartColumns: int[],
    sortedScopeMaxEndLines: int[],
    queryLines: int[],
    queryColumns: int[],
    resultScopeIds: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultSymbolIndices: int[],
    slotNameIds: int[],
    touchedSlots: int[]): int {
    total := SemanticScopeVisibleSymbolIndicesInto(
        scopeParentIds,
        scopeStartLines,
        scopeStartColumns,
        scopeEndLines,
        scopeEndColumns,
        scopeDepths,
        scopeSymbolStarts,
        scopeSymbolCounts,
        symbolNameIds,
        sortedScopeIds,
        sortedScopeStartLines,
        sortedScopeStartColumns,
        sortedScopeMaxEndLines,
        queryLines,
        queryColumns,
        resultScopeIds,
        resultStarts,
        resultCounts,
        resultSymbolIndices,
        slotNameIds,
        touchedSlots)

    if total < 0 {
        return total
    }

    queryCount := SemanticScopeMinInt(queryLines.Length, resultScopeIds.Length)
    queryCount = SemanticScopeMinInt(queryCount, resultStarts.Length)
    queryCount = SemanticScopeMinInt(queryCount, resultCounts.Length)
    symbolCount := SemanticScopeMinInt(symbolNameLengths.Length, symbolTypeNameLengths.Length)

    checksum := total * 17
    queryIndex := 0
    while queryIndex < queryCount {
        scopeId := resultScopeIds[queryIndex]
        checksum = checksum + (scopeId + 1) * 31

        start := resultStarts[queryIndex]
        count := resultCounts[queryIndex]
        i := 0
        while i < count {
            resultIndex := start + i
            if resultIndex >= 0 && resultIndex < total && resultIndex < resultSymbolIndices.Length {
                symbolIndex := resultSymbolIndices[resultIndex]
                if symbolIndex >= 0 && symbolIndex < symbolCount {
                    checksum = checksum
                        + symbolNameLengths[symbolIndex] * 13
                        + symbolTypeNameLengths[symbolIndex] * 7
                        + (i + 1)
                }
            }

            i = i + 1
        }

        queryIndex = queryIndex + 1
    }

    return checksum
}

func SemanticScopeLookupSymbolChecksumInto(
    scopeParentIds: int[],
    scopeStartLines: int[],
    scopeStartColumns: int[],
    scopeEndLines: int[],
    scopeEndColumns: int[],
    scopeDepths: int[],
    scopeSymbolStarts: int[],
    scopeSymbolCounts: int[],
    symbolNameIds: int[],
    symbolNameLengths: int[],
    symbolTypeNameLengths: int[],
    sortedScopeIds: int[],
    sortedScopeStartLines: int[],
    sortedScopeStartColumns: int[],
    sortedScopeMaxEndLines: int[],
    queryNameIds: int[],
    queryLines: int[],
    queryColumns: int[],
    resultScopeIds: int[],
    resultSymbolIndices: int[]): int {
    foundCount := SemanticScopeLookupSymbolIndicesInto(
        scopeParentIds,
        scopeStartLines,
        scopeStartColumns,
        scopeEndLines,
        scopeEndColumns,
        scopeDepths,
        scopeSymbolStarts,
        scopeSymbolCounts,
        symbolNameIds,
        sortedScopeIds,
        sortedScopeStartLines,
        sortedScopeStartColumns,
        sortedScopeMaxEndLines,
        queryNameIds,
        queryLines,
        queryColumns,
        resultScopeIds,
        resultSymbolIndices)

    if foundCount < 0 {
        return foundCount
    }

    queryCount := SemanticScopeMinInt(queryNameIds.Length, queryLines.Length)
    queryCount = SemanticScopeMinInt(queryCount, queryColumns.Length)
    queryCount = SemanticScopeMinInt(queryCount, resultScopeIds.Length)
    queryCount = SemanticScopeMinInt(queryCount, resultSymbolIndices.Length)
    symbolCount := SemanticScopeMinInt(symbolNameLengths.Length, symbolTypeNameLengths.Length)

    checksum := foundCount * 17
    queryIndex := 0
    while queryIndex < queryCount {
        scopeId := resultScopeIds[queryIndex]
        checksum = checksum + (scopeId + 1) * 31

        symbolIndex := resultSymbolIndices[queryIndex]
        if symbolIndex >= 0 && symbolIndex < symbolCount {
            checksum = checksum
                + symbolNameLengths[symbolIndex] * 13
                + symbolTypeNameLengths[symbolIndex] * 7
        }

        queryIndex = queryIndex + 1
    }

    return checksum
}

func SemanticScopeBuildDepthChecksumInto(
    scopeParentIds: int[],
    scopeDepths: int[]): int {
    count := SemanticScopeBuildDepthsInto(scopeParentIds, scopeDepths)
    if count < 0 {
        return count
    }

    checksum := count * 17
    i := 0
    while i < count {
        checksum = checksum + (i + 1) * 31 + scopeDepths[i] * 7
        i = i + 1
    }

    return checksum
}

func SemanticScopeBuildSortedIndexChecksumInto(
    scopeStartLines: int[],
    scopeStartColumns: int[],
    scopeEndLines: int[],
    tempScopeIds: int[],
    stackLefts: int[],
    stackRights: int[],
    sortedScopeIds: int[],
    sortedScopeStartLines: int[],
    sortedScopeStartColumns: int[],
    sortedScopeMaxEndLines: int[]): int {
    count := SemanticScopeBuildSortedIndexInto(
        scopeStartLines,
        scopeStartColumns,
        scopeEndLines,
        tempScopeIds,
        stackLefts,
        stackRights,
        sortedScopeIds,
        sortedScopeStartLines,
        sortedScopeStartColumns,
        sortedScopeMaxEndLines)

    if count < 0 {
        return count
    }

    checksum := count * 17
    i := 0
    while i < count {
        checksum = checksum
            + (i + 1) * 97
            + (sortedScopeIds[i] + 1) * 31
            + sortedScopeStartLines[i] * 13
            + sortedScopeStartColumns[i] * 7
            + sortedScopeMaxEndLines[i] * 3
        i = i + 1
    }

    return checksum
}

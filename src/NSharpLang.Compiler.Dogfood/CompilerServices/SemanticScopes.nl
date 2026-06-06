func SemanticScopeVisibleSymbolIndicesInto(
    scopeParentIds: int[],
    scopeStartLines: int[],
    scopeStartColumns: int[],
    scopeEndLines: int[],
    scopeEndColumns: int[],
    scopeDepths: int[],
    scopeSymbolStarts: int[],
    scopeSymbolCounts: int[],
    symbolNameIds: int[],
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
    scopeCount := SemanticScopeMinInt(scopeParentIds.Length, scopeStartLines.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeStartColumns.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeEndLines.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeEndColumns.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeDepths.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeSymbolStarts.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeSymbolCounts.Length)

    queryCount := SemanticScopeMinInt(queryLines.Length, queryColumns.Length)
    queryCount = SemanticScopeMinInt(queryCount, resultScopeIds.Length)
    queryCount = SemanticScopeMinInt(queryCount, resultStarts.Length)
    queryCount = SemanticScopeMinInt(queryCount, resultCounts.Length)

    if scopeCount == 0 || queryCount == 0 {
        return 0
    }

    symbolCount := symbolNameIds.Length
    if symbolCount > 0 && (slotNameIds.Length == 0 || touchedSlots.Length == 0) {
        return -1
    }

    total := 0
    queryIndex := 0
    while queryIndex < queryCount {
        line := queryLines[queryIndex]
        column := queryColumns[queryIndex]
        bestScope := -1

        bestScope = SemanticScopeFindBestContainingScope(
            scopeStartLines,
            scopeStartColumns,
            scopeEndLines,
            scopeEndColumns,
            scopeDepths,
            sortedScopeIds,
            sortedScopeStartLines,
            sortedScopeStartColumns,
            sortedScopeMaxEndLines,
            scopeCount,
            line,
            column)

        resultScopeIds[queryIndex] = bestScope
        resultStarts[queryIndex] = total
        resultCounts[queryIndex] = 0

        if bestScope >= 0 {
            touchedCount := 0
            current := bestScope
            while current >= 0 && current < scopeCount {
                symbolStart := scopeSymbolStarts[current]
                symbolEnd := symbolStart + scopeSymbolCounts[current]
                symbolIndex := symbolStart

                while symbolIndex < symbolEnd {
                    if symbolIndex >= 0 && symbolIndex < symbolCount {
                        nameId := symbolNameIds[symbolIndex]
                        nextTouchedCount := SemanticScopeAddNameToSet(
                            nameId,
                            slotNameIds,
                            touchedSlots,
                            touchedCount)

                        if nextTouchedCount < 0 {
                            SemanticScopeClearTouched(slotNameIds, touchedSlots, touchedCount)
                            return -1
                        }

                        if nextTouchedCount > touchedCount {
                            if total >= resultSymbolIndices.Length {
                                SemanticScopeClearTouched(slotNameIds, touchedSlots, nextTouchedCount)
                                return -1
                            }

                            resultSymbolIndices[total] = symbolIndex
                            total = total + 1
                            resultCounts[queryIndex] = resultCounts[queryIndex] + 1
                            touchedCount = nextTouchedCount
                        }
                    }

                    symbolIndex = symbolIndex + 1
                }

                parent := scopeParentIds[current]
                if parent == current {
                    break
                }

                current = parent
            }

            SemanticScopeClearTouched(slotNameIds, touchedSlots, touchedCount)
        }

        queryIndex = queryIndex + 1
    }

    return total
}

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

func SemanticScopeLookupSymbolIndicesInto(
    scopeParentIds: int[],
    scopeStartLines: int[],
    scopeStartColumns: int[],
    scopeEndLines: int[],
    scopeEndColumns: int[],
    scopeDepths: int[],
    scopeSymbolStarts: int[],
    scopeSymbolCounts: int[],
    symbolNameIds: int[],
    sortedScopeIds: int[],
    sortedScopeStartLines: int[],
    sortedScopeStartColumns: int[],
    sortedScopeMaxEndLines: int[],
    queryNameIds: int[],
    queryLines: int[],
    queryColumns: int[],
    resultScopeIds: int[],
    resultSymbolIndices: int[]): int {
    scopeCount := SemanticScopeMinInt(scopeParentIds.Length, scopeStartLines.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeStartColumns.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeEndLines.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeEndColumns.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeDepths.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeSymbolStarts.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeSymbolCounts.Length)

    queryCount := SemanticScopeMinInt(queryNameIds.Length, queryLines.Length)
    queryCount = SemanticScopeMinInt(queryCount, queryColumns.Length)
    queryCount = SemanticScopeMinInt(queryCount, resultScopeIds.Length)
    queryCount = SemanticScopeMinInt(queryCount, resultSymbolIndices.Length)

    if scopeCount == 0 || queryCount == 0 {
        return 0
    }

    symbolCount := symbolNameIds.Length
    foundCount := 0
    queryIndex := 0
    while queryIndex < queryCount {
        queryNameId := queryNameIds[queryIndex]
        line := queryLines[queryIndex]
        column := queryColumns[queryIndex]
        bestScope := -1
        resultSymbol := -1

        bestScope = SemanticScopeFindBestContainingScope(
            scopeStartLines,
            scopeStartColumns,
            scopeEndLines,
            scopeEndColumns,
            scopeDepths,
            sortedScopeIds,
            sortedScopeStartLines,
            sortedScopeStartColumns,
            sortedScopeMaxEndLines,
            scopeCount,
            line,
            column)

        if bestScope >= 0 && queryNameId > 0 {
            current := bestScope
            while current >= 0 && current < scopeCount && resultSymbol < 0 {
                symbolStart := scopeSymbolStarts[current]
                symbolEnd := symbolStart + scopeSymbolCounts[current]
                symbolIndex := symbolStart

                while symbolIndex < symbolEnd && resultSymbol < 0 {
                    if symbolIndex >= 0 && symbolIndex < symbolCount {
                        if symbolNameIds[symbolIndex] == queryNameId {
                            resultSymbol = symbolIndex
                            foundCount = foundCount + 1
                        }
                    }

                    symbolIndex = symbolIndex + 1
                }

                parent := scopeParentIds[current]
                if parent == current {
                    break
                }

                current = parent
            }
        }

        resultScopeIds[queryIndex] = bestScope
        resultSymbolIndices[queryIndex] = resultSymbol
        queryIndex = queryIndex + 1
    }

    return foundCount
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

func SemanticScopeBuildDepthsInto(
    scopeParentIds: int[],
    scopeDepths: int[]): int {
    scopeCount := SemanticScopeMinInt(scopeParentIds.Length, scopeDepths.Length)

    i := 0
    while i < scopeCount {
        parent := scopeParentIds[i]
        if parent < 0 || parent == i {
            scopeDepths[i] = 0
        } else {
            if parent >= 0 && parent < i {
                scopeDepths[i] = scopeDepths[parent] + 1
            } else {
                computedDepth := SemanticScopeComputeDepthByWalk(scopeParentIds, scopeCount, i)
                if computedDepth < 0 {
                    return -1
                }

                scopeDepths[i] = computedDepth
            }
        }

        i = i + 1
    }

    return scopeCount
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

func SemanticScopeBuildSortedIndexInto(
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
    scopeCount := SemanticScopeMinInt(scopeStartLines.Length, scopeStartColumns.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, scopeEndLines.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, tempScopeIds.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, sortedScopeIds.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, sortedScopeStartLines.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, sortedScopeStartColumns.Length)
    scopeCount = SemanticScopeMinInt(scopeCount, sortedScopeMaxEndLines.Length)

    if scopeCount == 0 {
        return 0
    }

    if stackLefts.Length < scopeCount || stackRights.Length < scopeCount {
        return -1
    }

    sorted := true
    maxEndLine := 0
    previousLine := -1
    previousColumn := -1
    i := 0
    while i < scopeCount {
        line := scopeStartLines[i]
        column := scopeStartColumns[i]
        if i > 0 && (line < previousLine || (line == previousLine && column < previousColumn)) {
            sorted = false
        }

        sortedScopeIds[i] = i
        sortedScopeStartLines[i] = line
        sortedScopeStartColumns[i] = column
        endLine := scopeEndLines[i]
        if endLine > maxEndLine {
            maxEndLine = endLine
        }

        sortedScopeMaxEndLines[i] = maxEndLine
        previousLine = line
        previousColumn = column
        i = i + 1
    }

    if sorted {
        return scopeCount
    }

    i = 0
    while i < scopeCount {
        tempScopeIds[i] = i
        i = i + 1
    }

    SemanticScopeSortIdsByStart(
        tempScopeIds,
        scopeCount,
        scopeStartLines,
        scopeStartColumns,
        stackLefts,
        stackRights)

    maxEnd := 0
    i = 0
    while i < scopeCount {
        scopeId := tempScopeIds[i]
        if scopeId < 0 || scopeId >= scopeCount {
            return -1
        }

        sortedScopeIds[i] = scopeId
        sortedScopeStartLines[i] = scopeStartLines[scopeId]
        sortedScopeStartColumns[i] = scopeStartColumns[scopeId]
        endLine := scopeEndLines[scopeId]
        if endLine > maxEnd {
            maxEnd = endLine
        }

        sortedScopeMaxEndLines[i] = maxEnd
        i = i + 1
    }

    return scopeCount
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

func SemanticScopeSortIdsByStart(
    ids: int[],
    count: int,
    scopeStartLines: int[],
    scopeStartColumns: int[],
    stackLefts: int[],
    stackRights: int[]) {
    stackCount := 0
    stackLefts[stackCount] = 0
    stackRights[stackCount] = count - 1
    stackCount = stackCount + 1

    while stackCount > 0 {
        stackCount = stackCount - 1
        left := stackLefts[stackCount]
        right := stackRights[stackCount]

        while left < right {
            i := left
            j := right
            pivot := ids[(left + right) >> 1]

            while i <= j {
                while SemanticScopeIdStartsBefore(ids[i], pivot, scopeStartLines, scopeStartColumns) {
                    i = i + 1
                }

                while SemanticScopeIdStartsBefore(pivot, ids[j], scopeStartLines, scopeStartColumns) {
                    j = j - 1
                }

                if i <= j {
                    temp := ids[i]
                    ids[i] = ids[j]
                    ids[j] = temp
                    i = i + 1
                    j = j - 1
                }
            }

            leftPartitionSize := j - left
            rightPartitionSize := right - i
            if leftPartitionSize < rightPartitionSize {
                if i < right {
                    stackLefts[stackCount] = i
                    stackRights[stackCount] = right
                    stackCount = stackCount + 1
                }

                right = j
            } else {
                if left < j {
                    stackLefts[stackCount] = left
                    stackRights[stackCount] = j
                    stackCount = stackCount + 1
                }

                left = i
            }
        }
    }
}

func SemanticScopeIdStartsBefore(
    left: int,
    right: int,
    scopeStartLines: int[],
    scopeStartColumns: int[]): bool {
    leftLine := scopeStartLines[left]
    rightLine := scopeStartLines[right]
    if leftLine < rightLine {
        return true
    }

    if leftLine > rightLine {
        return false
    }

    leftColumn := scopeStartColumns[left]
    rightColumn := scopeStartColumns[right]
    if leftColumn < rightColumn {
        return true
    }

    if leftColumn > rightColumn {
        return false
    }

    return left < right
}

func SemanticScopeComputeDepthByWalk(
    scopeParentIds: int[],
    scopeCount: int,
    scopeIndex: int): int {
    depth := 0
    current := scopeIndex
    guard := 0
    while current >= 0 && current < scopeCount && guard <= scopeCount {
        parent := scopeParentIds[current]
        if parent < 0 || parent == current {
            break
        }

        depth = depth + 1
        current = parent
        guard = guard + 1
    }

    if guard > scopeCount {
        return -1
    }

    return depth
}

func SemanticScopeFindBestContainingScope(
    scopeStartLines: int[],
    scopeStartColumns: int[],
    scopeEndLines: int[],
    scopeEndColumns: int[],
    scopeDepths: int[],
    sortedScopeIds: int[],
    sortedScopeStartLines: int[],
    sortedScopeStartColumns: int[],
    sortedScopeMaxEndLines: int[],
    scopeCount: int,
    line: int,
    column: int): int {
    sortedCount := SemanticScopeMinInt(sortedScopeIds.Length, sortedScopeStartLines.Length)
    sortedCount = SemanticScopeMinInt(sortedCount, sortedScopeStartColumns.Length)
    sortedCount = SemanticScopeMinInt(sortedCount, sortedScopeMaxEndLines.Length)

    if sortedCount <= 0 {
        return SemanticScopeFindBestContainingScopeByScan(
            scopeStartLines,
            scopeStartColumns,
            scopeEndLines,
            scopeEndColumns,
            scopeDepths,
            scopeCount,
            line,
            column)
    }

    upper := SemanticScopeStartUpperBound(
        sortedScopeStartLines,
        sortedScopeStartColumns,
        sortedCount,
        line,
        column) - 1

    bestScope := -1
    bestDepth := -1
    while upper >= 0 {
        if sortedScopeMaxEndLines[upper] < line {
            break
        }

        scopeIndex := sortedScopeIds[upper]
        if scopeIndex >= 0 && scopeIndex < scopeCount {
            if SemanticScopeContainsPosition(
                scopeStartLines[scopeIndex],
                scopeStartColumns[scopeIndex],
                scopeEndLines[scopeIndex],
                scopeEndColumns[scopeIndex],
                line,
                column) {
                depth := scopeDepths[scopeIndex]
                if depth > bestDepth {
                    bestScope = scopeIndex
                    bestDepth = depth
                }
            }
        }

        upper = upper - 1
    }

    return bestScope
}

func SemanticScopeFindBestContainingScopeByScan(
    scopeStartLines: int[],
    scopeStartColumns: int[],
    scopeEndLines: int[],
    scopeEndColumns: int[],
    scopeDepths: int[],
    scopeCount: int,
    line: int,
    column: int): int {
    bestScope := -1
    bestDepth := -1
    scopeIndex := 0
    while scopeIndex < scopeCount {
        if SemanticScopeContainsPosition(
            scopeStartLines[scopeIndex],
            scopeStartColumns[scopeIndex],
            scopeEndLines[scopeIndex],
            scopeEndColumns[scopeIndex],
            line,
            column) {
            depth := scopeDepths[scopeIndex]
            if depth > bestDepth {
                bestScope = scopeIndex
                bestDepth = depth
            }
        }

        scopeIndex = scopeIndex + 1
    }

    return bestScope
}

func SemanticScopeStartUpperBound(
    sortedScopeStartLines: int[],
    sortedScopeStartColumns: int[],
    sortedCount: int,
    line: int,
    column: int): int {
    low := 0
    high := sortedCount
    while low < high {
        mid := (low + high) >> 1
        if SemanticScopeStartBeforeOrAt(
            sortedScopeStartLines[mid],
            sortedScopeStartColumns[mid],
            line,
            column) {
            low = mid + 1
        } else {
            high = mid
        }
    }

    return low
}

func SemanticScopeStartBeforeOrAt(
    startLine: int,
    startColumn: int,
    line: int,
    column: int): bool {
    if startLine < line {
        return true
    }

    if startLine > line {
        return false
    }

    return startColumn <= column
}

func SemanticScopeAddNameToSet(
    nameId: int,
    slotNameIds: int[],
    touchedSlots: int[],
    touchedCount: int): int {
    if nameId <= 0 {
        return touchedCount
    }

    capacity := slotNameIds.Length
    if capacity == 0 {
        return -1
    }

    slot := SemanticScopePositiveModulo(nameId, capacity)
    probes := 0
    while probes < capacity {
        existing := slotNameIds[slot]
        if existing == nameId {
            return touchedCount
        }

        if existing == 0 {
            if touchedCount >= touchedSlots.Length {
                return -1
            }

            slotNameIds[slot] = nameId
            touchedSlots[touchedCount] = slot
            return touchedCount + 1
        }

        slot = slot + 1
        if slot == capacity {
            slot = 0
        }
        probes = probes + 1
    }

    return -1
}

func SemanticScopeClearTouched(slotNameIds: int[], touchedSlots: int[], touchedCount: int) {
    i := 0
    while i < touchedCount {
        slot := touchedSlots[i]
        if slot >= 0 && slot < slotNameIds.Length {
            slotNameIds[slot] = 0
        }

        i = i + 1
    }
}

func SemanticScopeContainsPosition(
    startLine: int,
    startColumn: int,
    endLine: int,
    endColumn: int,
    line: int,
    column: int): bool {
    if endLine == 0 {
        return false
    }

    if line < startLine || line > endLine {
        return false
    }

    if line == startLine && column < startColumn {
        return false
    }

    if line == endLine && column > endColumn {
        return false
    }

    return true
}

func SemanticScopePositiveModulo(value: int, divisor: int): int {
    result := value % divisor
    if result < 0 {
        return result + divisor
    }

    return result
}

func SemanticScopeMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

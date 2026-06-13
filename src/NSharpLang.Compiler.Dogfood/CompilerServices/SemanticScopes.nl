struct SemanticScopePositionTable {
    StartLines: int[]
    StartColumns: int[]
    EndLines: int[]
    EndColumns: int[]
    Depths: int[]
}

struct SemanticScopeRelationTable {
    ParentIds: int[]
    SymbolStarts: int[]
    SymbolCounts: int[]
}

struct SemanticScopeDepthTable {
    ParentIds: int[]
    Depths: int[]
}

struct SemanticScopeSortSourceTable {
    StartLines: int[]
    StartColumns: int[]
    EndLines: int[]
}

struct SemanticScopeSortedIndexTable {
    ScopeIds: int[]
    StartLines: int[]
    StartColumns: int[]
    MaxEndLines: int[]
}

struct SemanticSymbolTable {
    NameIds: int[]
}

struct SemanticScopeNameSetScratch {
    SlotNameIds: int[]
    TouchedSlots: int[]
}

struct SemanticScopeVisibleQueryTable {
    Lines: int[]
    Columns: int[]
}

struct SemanticScopeVisibleResultTable {
    ScopeIds: int[]
    Starts: int[]
    Counts: int[]
    SymbolIndices: int[]
}

struct SemanticScopeLookupQueryTable {
    NameIds: int[]
    Lines: int[]
    Columns: int[]
}

struct SemanticScopeLookupResultTable {
    ScopeIds: int[]
    SymbolIndices: int[]
}

struct SemanticScopeSortScratchTable {
    TempScopeIds: int[]
    StackLefts: int[]
    StackRights: int[]
}

func SemanticScopePositionCount(positions: &SemanticScopePositionTable): int {
    count := SemanticScopeMinInt(positions.StartLines.Length, positions.StartColumns.Length)
    count = SemanticScopeMinInt(count, positions.EndLines.Length)
    count = SemanticScopeMinInt(count, positions.EndColumns.Length)
    count = SemanticScopeMinInt(count, positions.Depths.Length)
    return count
}

func SemanticScopeRelationCount(relations: &SemanticScopeRelationTable): int {
    count := SemanticScopeMinInt(relations.ParentIds.Length, relations.SymbolStarts.Length)
    count = SemanticScopeMinInt(count, relations.SymbolCounts.Length)
    return count
}

func SemanticScopeDepthCount(depths: &SemanticScopeDepthTable): int {
    return SemanticScopeMinInt(depths.ParentIds.Length, depths.Depths.Length)
}

func SemanticScopeSortedIndexCount(sorted: &SemanticScopeSortedIndexTable): int {
    count := SemanticScopeMinInt(sorted.ScopeIds.Length, sorted.StartLines.Length)
    count = SemanticScopeMinInt(count, sorted.StartColumns.Length)
    count = SemanticScopeMinInt(count, sorted.MaxEndLines.Length)
    return count
}

func SemanticScopeSortSourceOutputCount(source: &SemanticScopeSortSourceTable, scratch: &SemanticScopeSortScratchTable, sorted: &SemanticScopeSortedIndexTable): int {
    count := SemanticScopeMinInt(source.StartLines.Length, source.StartColumns.Length)
    count = SemanticScopeMinInt(count, source.EndLines.Length)
    count = SemanticScopeMinInt(count, scratch.TempScopeIds.Length)
    count = SemanticScopeMinInt(count, SemanticScopeSortedIndexCount(ref sorted))
    return count
}

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
    positions := new SemanticScopePositionTable { StartLines: scopeStartLines, StartColumns: scopeStartColumns, EndLines: scopeEndLines, EndColumns: scopeEndColumns, Depths: scopeDepths }
    relations := new SemanticScopeRelationTable { ParentIds: scopeParentIds, SymbolStarts: scopeSymbolStarts, SymbolCounts: scopeSymbolCounts }
    symbols := new SemanticSymbolTable { NameIds: symbolNameIds }
    sorted := new SemanticScopeSortedIndexTable { ScopeIds: sortedScopeIds, StartLines: sortedScopeStartLines, StartColumns: sortedScopeStartColumns, MaxEndLines: sortedScopeMaxEndLines }
    queries := new SemanticScopeVisibleQueryTable { Lines: queryLines, Columns: queryColumns }
    results := new SemanticScopeVisibleResultTable { ScopeIds: resultScopeIds, Starts: resultStarts, Counts: resultCounts, SymbolIndices: resultSymbolIndices }
    scratch := new SemanticScopeNameSetScratch { SlotNameIds: slotNameIds, TouchedSlots: touchedSlots }
    return SemanticScopeVisibleSymbolIndicesCore(ref positions, ref relations, ref symbols, ref sorted, ref queries, ref results, ref scratch)
}

func SemanticScopeVisibleSymbolIndicesCore(
    positions: &SemanticScopePositionTable,
    relations: &SemanticScopeRelationTable,
    symbols: &SemanticSymbolTable,
    sorted: &SemanticScopeSortedIndexTable,
    queries: &SemanticScopeVisibleQueryTable,
    results: &SemanticScopeVisibleResultTable,
    scratch: &SemanticScopeNameSetScratch): int {
    scopeCount := SemanticScopeMinInt(SemanticScopePositionCount(ref positions), SemanticScopeRelationCount(ref relations))

    queryCount := SemanticScopeMinInt(queries.Lines.Length, queries.Columns.Length)
    queryCount = SemanticScopeMinInt(queryCount, results.ScopeIds.Length)
    queryCount = SemanticScopeMinInt(queryCount, results.Starts.Length)
    queryCount = SemanticScopeMinInt(queryCount, results.Counts.Length)

    if scopeCount == 0 || queryCount == 0 {
        return 0
    }

    symbolCount := symbols.NameIds.Length
    if symbolCount > 0 && (scratch.SlotNameIds.Length == 0 || scratch.TouchedSlots.Length == 0) {
        return -1
    }

    total := 0
    queryIndex := 0
    while queryIndex < queryCount {
        line := queries.Lines[queryIndex]
        column := queries.Columns[queryIndex]
        bestScope := -1

        bestScope = SemanticScopeFindBestContainingScopeCore(ref positions, ref sorted, scopeCount, line, column)

        results.ScopeIds[queryIndex] = bestScope
        results.Starts[queryIndex] = total
        results.Counts[queryIndex] = 0

        if bestScope >= 0 {
            touchedCount := 0
            current := bestScope
            while current >= 0 && current < scopeCount {
                symbolStart := relations.SymbolStarts[current]
                symbolEnd := symbolStart + relations.SymbolCounts[current]
                symbolIndex := symbolStart

                while symbolIndex < symbolEnd {
                    if symbolIndex >= 0 && symbolIndex < symbolCount {
                        nameId := symbols.NameIds[symbolIndex]
                        nextTouchedCount := SemanticScopeAddNameToSetCore(nameId, ref scratch, touchedCount)

                        if nextTouchedCount < 0 {
                            SemanticScopeClearTouchedCore(ref scratch, touchedCount)
                            return -1
                        }

                        if nextTouchedCount > touchedCount {
                            if total >= results.SymbolIndices.Length {
                                SemanticScopeClearTouchedCore(ref scratch, nextTouchedCount)
                                return -1
                            }

                            results.SymbolIndices[total] = symbolIndex
                            total = total + 1
                            results.Counts[queryIndex] = results.Counts[queryIndex] + 1
                            touchedCount = nextTouchedCount
                        }
                    }

                    symbolIndex = symbolIndex + 1
                }

                parent := relations.ParentIds[current]
                if parent == current {
                    break
                }

                current = parent
            }

            SemanticScopeClearTouchedCore(ref scratch, touchedCount)
        }

        queryIndex = queryIndex + 1
    }

    return total
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
    positions := new SemanticScopePositionTable { StartLines: scopeStartLines, StartColumns: scopeStartColumns, EndLines: scopeEndLines, EndColumns: scopeEndColumns, Depths: scopeDepths }
    relations := new SemanticScopeRelationTable { ParentIds: scopeParentIds, SymbolStarts: scopeSymbolStarts, SymbolCounts: scopeSymbolCounts }
    symbols := new SemanticSymbolTable { NameIds: symbolNameIds }
    sorted := new SemanticScopeSortedIndexTable { ScopeIds: sortedScopeIds, StartLines: sortedScopeStartLines, StartColumns: sortedScopeStartColumns, MaxEndLines: sortedScopeMaxEndLines }
    queries := new SemanticScopeLookupQueryTable { NameIds: queryNameIds, Lines: queryLines, Columns: queryColumns }
    results := new SemanticScopeLookupResultTable { ScopeIds: resultScopeIds, SymbolIndices: resultSymbolIndices }
    return SemanticScopeLookupSymbolIndicesCore(ref positions, ref relations, ref symbols, ref sorted, ref queries, ref results)
}

func SemanticScopeLookupSymbolIndicesCore(
    positions: &SemanticScopePositionTable,
    relations: &SemanticScopeRelationTable,
    symbols: &SemanticSymbolTable,
    sorted: &SemanticScopeSortedIndexTable,
    queries: &SemanticScopeLookupQueryTable,
    results: &SemanticScopeLookupResultTable): int {
    scopeCount := SemanticScopeMinInt(SemanticScopePositionCount(ref positions), SemanticScopeRelationCount(ref relations))

    queryCount := SemanticScopeMinInt(queries.NameIds.Length, queries.Lines.Length)
    queryCount = SemanticScopeMinInt(queryCount, queries.Columns.Length)
    queryCount = SemanticScopeMinInt(queryCount, results.ScopeIds.Length)
    queryCount = SemanticScopeMinInt(queryCount, results.SymbolIndices.Length)

    if scopeCount == 0 || queryCount == 0 {
        return 0
    }

    symbolCount := symbols.NameIds.Length
    foundCount := 0
    queryIndex := 0
    while queryIndex < queryCount {
        queryNameId := queries.NameIds[queryIndex]
        line := queries.Lines[queryIndex]
        column := queries.Columns[queryIndex]
        bestScope := -1
        resultSymbol := -1

        bestScope = SemanticScopeFindBestContainingScopeCore(ref positions, ref sorted, scopeCount, line, column)

        if bestScope >= 0 && queryNameId > 0 {
            current := bestScope
            while current >= 0 && current < scopeCount && resultSymbol < 0 {
                symbolStart := relations.SymbolStarts[current]
                symbolEnd := symbolStart + relations.SymbolCounts[current]
                symbolIndex := symbolStart

                while symbolIndex < symbolEnd && resultSymbol < 0 {
                    if symbolIndex >= 0 && symbolIndex < symbolCount {
                        if symbols.NameIds[symbolIndex] == queryNameId {
                            resultSymbol = symbolIndex
                            foundCount = foundCount + 1
                        }
                    }

                    symbolIndex = symbolIndex + 1
                }

                parent := relations.ParentIds[current]
                if parent == current {
                    break
                }

                current = parent
            }
        }

        results.ScopeIds[queryIndex] = bestScope
        results.SymbolIndices[queryIndex] = resultSymbol
        queryIndex = queryIndex + 1
    }

    return foundCount
}

func SemanticScopeBuildDepthsInto(
    scopeParentIds: int[],
    scopeDepths: int[]): int {
    depths := new SemanticScopeDepthTable { ParentIds: scopeParentIds, Depths: scopeDepths }
    return SemanticScopeBuildDepthsCore(ref depths)
}

func SemanticScopeBuildDepthsCore(depths: &SemanticScopeDepthTable): int {
    scopeCount := SemanticScopeDepthCount(ref depths)

    i := 0
    while i < scopeCount {
        parent := depths.ParentIds[i]
        if parent < 0 || parent == i {
            depths.Depths[i] = 0
        } else {
            if parent >= 0 && parent < i {
                depths.Depths[i] = depths.Depths[parent] + 1
            } else {
                computedDepth := SemanticScopeComputeDepthByWalk(ref depths, scopeCount, i)
                if computedDepth < 0 {
                    return -1
                }

                depths.Depths[i] = computedDepth
            }
        }

        i = i + 1
    }

    return scopeCount
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
    source := new SemanticScopeSortSourceTable { StartLines: scopeStartLines, StartColumns: scopeStartColumns, EndLines: scopeEndLines }
    scratch := new SemanticScopeSortScratchTable { TempScopeIds: tempScopeIds, StackLefts: stackLefts, StackRights: stackRights }
    sortedIndex := new SemanticScopeSortedIndexTable { ScopeIds: sortedScopeIds, StartLines: sortedScopeStartLines, StartColumns: sortedScopeStartColumns, MaxEndLines: sortedScopeMaxEndLines }
    return SemanticScopeBuildSortedIndexCore(ref source, ref scratch, ref sortedIndex)
}

func SemanticScopeBuildSortedIndexCore(
    source: &SemanticScopeSortSourceTable,
    scratch: &SemanticScopeSortScratchTable,
    sortedIndex: &SemanticScopeSortedIndexTable): int {
    scopeCount := SemanticScopeSortSourceOutputCount(ref source, ref scratch, ref sortedIndex)

    if scopeCount == 0 {
        return 0
    }

    if scratch.StackLefts.Length < scopeCount || scratch.StackRights.Length < scopeCount {
        return -1
    }

    sorted := true
    maxEndLine := 0
    previousLine := -1
    previousColumn := -1
    i := 0
    while i < scopeCount {
        line := source.StartLines[i]
        column := source.StartColumns[i]
        if i > 0 && (line < previousLine || (line == previousLine && column < previousColumn)) {
            sorted = false
        }

        sortedIndex.ScopeIds[i] = i
        sortedIndex.StartLines[i] = line
        sortedIndex.StartColumns[i] = column
        endLine := source.EndLines[i]
        if endLine > maxEndLine {
            maxEndLine = endLine
        }

        sortedIndex.MaxEndLines[i] = maxEndLine
        previousLine = line
        previousColumn = column
        i = i + 1
    }

    if sorted {
        return scopeCount
    }

    i = 0
    while i < scopeCount {
        scratch.TempScopeIds[i] = i
        i = i + 1
    }

    SemanticScopeSortIdsByStart(ref scratch, scopeCount, ref source)

    maxEnd := 0
    i = 0
    while i < scopeCount {
        scopeId := scratch.TempScopeIds[i]
        if scopeId < 0 || scopeId >= scopeCount {
            return -1
        }

        sortedIndex.ScopeIds[i] = scopeId
        sortedIndex.StartLines[i] = source.StartLines[scopeId]
        sortedIndex.StartColumns[i] = source.StartColumns[scopeId]
        endLine := source.EndLines[scopeId]
        if endLine > maxEnd {
            maxEnd = endLine
        }

        sortedIndex.MaxEndLines[i] = maxEnd
        i = i + 1
    }

    return scopeCount
}

func SemanticScopeSortIdsByStart(
    scratch: &SemanticScopeSortScratchTable,
    count: int,
    source: &SemanticScopeSortSourceTable) {
    ids := scratch.TempScopeIds
    stackLefts := scratch.StackLefts
    stackRights := scratch.StackRights
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
                while SemanticScopeIdStartsBeforeCore(ids[i], pivot, ref source) {
                    i = i + 1
                }

                while SemanticScopeIdStartsBeforeCore(pivot, ids[j], ref source) {
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
    source := new SemanticScopeSortSourceTable { StartLines: scopeStartLines, StartColumns: scopeStartColumns, EndLines: scopeStartLines }
    return SemanticScopeIdStartsBeforeCore(left, right, ref source)
}

func SemanticScopeIdStartsBeforeCore(
    left: int,
    right: int,
    source: &SemanticScopeSortSourceTable): bool {
    leftLine := source.StartLines[left]
    rightLine := source.StartLines[right]
    if leftLine < rightLine {
        return true
    }

    if leftLine > rightLine {
        return false
    }

    leftColumn := source.StartColumns[left]
    rightColumn := source.StartColumns[right]
    if leftColumn < rightColumn {
        return true
    }

    if leftColumn > rightColumn {
        return false
    }

    return left < right
}

func SemanticScopeComputeDepthByWalk(
    depths: &SemanticScopeDepthTable,
    scopeCount: int,
    scopeIndex: int): int {
    depth := 0
    current := scopeIndex
    guard := 0
    while current >= 0 && current < scopeCount && guard <= scopeCount {
        parent := depths.ParentIds[current]
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
    positions := new SemanticScopePositionTable { StartLines: scopeStartLines, StartColumns: scopeStartColumns, EndLines: scopeEndLines, EndColumns: scopeEndColumns, Depths: scopeDepths }
    sorted := new SemanticScopeSortedIndexTable { ScopeIds: sortedScopeIds, StartLines: sortedScopeStartLines, StartColumns: sortedScopeStartColumns, MaxEndLines: sortedScopeMaxEndLines }
    return SemanticScopeFindBestContainingScopeCore(ref positions, ref sorted, scopeCount, line, column)
}

func SemanticScopeFindBestContainingScopeCore(
    positions: &SemanticScopePositionTable,
    sorted: &SemanticScopeSortedIndexTable,
    scopeCount: int,
    line: int,
    column: int): int {
    sortedCount := SemanticScopeSortedIndexCount(ref sorted)

    if sortedCount <= 0 {
        return SemanticScopeFindBestContainingScopeByScanCore(ref positions, scopeCount, line, column)
    }

    upper := SemanticScopeStartUpperBound(ref sorted, sortedCount, line, column) - 1

    bestScope := -1
    bestDepth := -1
    while upper >= 0 {
        if sorted.MaxEndLines[upper] < line {
            break
        }

        scopeIndex := sorted.ScopeIds[upper]
        if scopeIndex >= 0 && scopeIndex < scopeCount {
            if SemanticScopeContainsPosition(
                positions.StartLines[scopeIndex],
                positions.StartColumns[scopeIndex],
                positions.EndLines[scopeIndex],
                positions.EndColumns[scopeIndex],
                line,
                column) {
                depth := positions.Depths[scopeIndex]
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
    positions := new SemanticScopePositionTable { StartLines: scopeStartLines, StartColumns: scopeStartColumns, EndLines: scopeEndLines, EndColumns: scopeEndColumns, Depths: scopeDepths }
    return SemanticScopeFindBestContainingScopeByScanCore(ref positions, scopeCount, line, column)
}

func SemanticScopeFindBestContainingScopeByScanCore(
    positions: &SemanticScopePositionTable,
    scopeCount: int,
    line: int,
    column: int): int {
    bestScope := -1
    bestDepth := -1
    scopeIndex := 0
    while scopeIndex < scopeCount {
        if SemanticScopeContainsPosition(
            positions.StartLines[scopeIndex],
            positions.StartColumns[scopeIndex],
            positions.EndLines[scopeIndex],
            positions.EndColumns[scopeIndex],
            line,
            column) {
            depth := positions.Depths[scopeIndex]
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
    sorted: &SemanticScopeSortedIndexTable,
    sortedCount: int,
    line: int,
    column: int): int {
    low := 0
    high := sortedCount
    while low < high {
        mid := (low + high) >> 1
        if SemanticScopeStartBeforeOrAt(
            sorted.StartLines[mid],
            sorted.StartColumns[mid],
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
    scratch := new SemanticScopeNameSetScratch { SlotNameIds: slotNameIds, TouchedSlots: touchedSlots }
    return SemanticScopeAddNameToSetCore(nameId, ref scratch, touchedCount)
}

func SemanticScopeAddNameToSetCore(
    nameId: int,
    scratch: &SemanticScopeNameSetScratch,
    touchedCount: int): int {
    if nameId <= 0 {
        return touchedCount
    }

    capacity := scratch.SlotNameIds.Length
    if capacity == 0 {
        return -1
    }

    slot := SemanticScopePositiveModulo(nameId, capacity)
    probes := 0
    while probes < capacity {
        existing := scratch.SlotNameIds[slot]
        if existing == nameId {
            return touchedCount
        }

        if existing == 0 {
            if touchedCount >= scratch.TouchedSlots.Length {
                return -1
            }

            scratch.SlotNameIds[slot] = nameId
            scratch.TouchedSlots[touchedCount] = slot
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
    scratch := new SemanticScopeNameSetScratch { SlotNameIds: slotNameIds, TouchedSlots: touchedSlots }
    SemanticScopeClearTouchedCore(ref scratch, touchedCount)
}

func SemanticScopeClearTouchedCore(scratch: &SemanticScopeNameSetScratch, touchedCount: int) {
    i := 0
    while i < touchedCount {
        slot := scratch.TouchedSlots[i]
        if slot >= 0 && slot < scratch.SlotNameIds.Length {
            scratch.SlotNameIds[slot] = 0
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

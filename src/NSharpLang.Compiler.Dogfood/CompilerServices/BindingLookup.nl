struct BindingLookupLocationTable {
    FileRanks: int[]
    LineNumbers: int[]
    Columns: int[]
}

struct BindingLookupSlotTable {
    Indices: int[]
}

struct BindingLookupDeclarationLinkTable {
    DeclarationIndices: int[]
}

struct BindingLookupDeclarationResultTable {
    DeclarationIndices: int[]
}

struct BindingLookupCandidateSpanTable {
    QueryColumns: int[]
    SpanStartColumns: int[]
    SpanEndColumns: int[]
}

struct BindingLookupCandidateColumnOutputTable {
    Starts: int[]
    Counts: int[]
    Columns: int[]
}

struct BindingLookupCandidateColumnTable {
    Columns: int[]
}

struct BindingLookupNearestDeclarationSourceTable {
    NameIds: int[]
    FileRanks: int[]
    LineNumbers: int[]
    Columns: int[]
}

struct BindingLookupNearestDeclarationSortedTable {
    NameIds: int[]
    FileRanks: int[]
    LineNumbers: int[]
    Columns: int[]
    DeclarationIndices: int[]
}

struct BindingLookupNearestDeclarationScratchTable {
    TempDeclarationIndices: int[]
    StackLefts: int[]
}

struct BindingLookupNearestQueryTable {
    NameIds: int[]
    FileRanks: int[]
    LineNumbers: int[]
}

func BindingLookupLocationCount(locations: &BindingLookupLocationTable): int {
    count := BindingLookupMinInt(locations.FileRanks.Length, locations.LineNumbers.Length)
    count = BindingLookupMinInt(count, locations.Columns.Length)
    return count
}

func BindingLookupCandidateSpanCount(spans: &BindingLookupCandidateSpanTable, output: &BindingLookupCandidateColumnOutputTable): int {
    count := BindingLookupMinInt(spans.QueryColumns.Length, spans.SpanStartColumns.Length)
    count = BindingLookupMinInt(count, spans.SpanEndColumns.Length)
    count = BindingLookupMinInt(count, output.Starts.Length)
    count = BindingLookupMinInt(count, output.Counts.Length)
    return count
}

func BindingLookupNearestDeclarationSourceCount(source: &BindingLookupNearestDeclarationSourceTable): int {
    count := BindingLookupMinInt(source.NameIds.Length, source.FileRanks.Length)
    count = BindingLookupMinInt(count, source.LineNumbers.Length)
    count = BindingLookupMinInt(count, source.Columns.Length)
    return count
}

func BindingLookupNearestDeclarationSortedCount(sorted: &BindingLookupNearestDeclarationSortedTable): int {
    count := BindingLookupMinInt(sorted.NameIds.Length, sorted.FileRanks.Length)
    count = BindingLookupMinInt(count, sorted.LineNumbers.Length)
    count = BindingLookupMinInt(count, sorted.Columns.Length)
    count = BindingLookupMinInt(count, sorted.DeclarationIndices.Length)
    return count
}

func BindingLookupNearestDeclarationSourceOutputCount(source: &BindingLookupNearestDeclarationSourceTable, sorted: &BindingLookupNearestDeclarationSortedTable): int {
    return BindingLookupMinInt(BindingLookupNearestDeclarationSourceCount(ref source), BindingLookupNearestDeclarationSortedCount(ref sorted))
}

func BindingLookupNearestQueryResultCount(query: &BindingLookupNearestQueryTable, result: &BindingLookupDeclarationResultTable): int {
    count := BindingLookupMinInt(query.NameIds.Length, query.FileRanks.Length)
    count = BindingLookupMinInt(count, query.LineNumbers.Length)
    count = BindingLookupMinInt(count, result.DeclarationIndices.Length)
    return count
}

func HashBindingLookupKeyAt(index: int, locations: &BindingLookupLocationTable): int {
    return HashBindingLookupKey(locations.FileRanks[index], locations.LineNumbers[index], locations.Columns[index])
}

func BindingLookupBuildSlotsInto(
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    slotIndices: int[]): int {
    locations := new BindingLookupLocationTable { FileRanks: fileRanks, LineNumbers: lineNumbers, Columns: columns }
    slots := new BindingLookupSlotTable { Indices: slotIndices }
    return BindingLookupBuildSlotsCore(ref locations, ref slots)
}

func BindingLookupBuildSlotsCore(
    locations: &BindingLookupLocationTable,
    slots: &BindingLookupSlotTable): int {
    count := BindingLookupLocationCount(ref locations)

    capacity := slots.Indices.Length
    if count == 0 || capacity == 0 {
        return 0
    }

    i := 0
    while i < capacity {
        slots.Indices[i] = -1
        i = i + 1
    }

    insertedCount := 0
    index := 0
    while index < count {
        hash := HashBindingLookupKeyAt(index, ref locations)
        slot := BindingLookupPositiveModulo(hash, capacity)
        probes := 0

        while probes < capacity {
            candidateIndex := slots.Indices[slot]
            if candidateIndex < 0 {
                slots.Indices[slot] = index
                insertedCount = insertedCount + 1
                break
            }

            if BindingLookupKeysEqualCore(index, candidateIndex, ref locations) {
                break
            }

            slot = slot + 1
            if slot == capacity {
                slot = 0
            }
            probes = probes + 1
        }

        index = index + 1
    }

    return insertedCount
}

func BindingLookupQueryDeclarationIndicesInto(
    declarationFileRanks: int[],
    declarationLineNumbers: int[],
    declarationColumns: int[],
    declarationSlotIndices: int[],
    bindingFileRanks: int[],
    bindingLineNumbers: int[],
    bindingColumns: int[],
    bindingDeclarationIndices: int[],
    bindingSlotIndices: int[],
    queryFileRanks: int[],
    queryLineNumbers: int[],
    queryColumns: int[],
    resultDeclarationIndices: int[]): int {
    declarations := new BindingLookupLocationTable { FileRanks: declarationFileRanks, LineNumbers: declarationLineNumbers, Columns: declarationColumns }
    declarationSlots := new BindingLookupSlotTable { Indices: declarationSlotIndices }
    bindings := new BindingLookupLocationTable { FileRanks: bindingFileRanks, LineNumbers: bindingLineNumbers, Columns: bindingColumns }
    bindingLinks := new BindingLookupDeclarationLinkTable { DeclarationIndices: bindingDeclarationIndices }
    bindingSlots := new BindingLookupSlotTable { Indices: bindingSlotIndices }
    queries := new BindingLookupLocationTable { FileRanks: queryFileRanks, LineNumbers: queryLineNumbers, Columns: queryColumns }
    result := new BindingLookupDeclarationResultTable { DeclarationIndices: resultDeclarationIndices }
    return BindingLookupQueryDeclarationIndicesCore(ref declarations, ref declarationSlots, ref bindings, ref bindingLinks, ref bindingSlots, ref queries, ref result)
}

func BindingLookupQueryDeclarationIndicesCore(
    declarations: &BindingLookupLocationTable,
    declarationSlots: &BindingLookupSlotTable,
    bindings: &BindingLookupLocationTable,
    bindingLinks: &BindingLookupDeclarationLinkTable,
    bindingSlots: &BindingLookupSlotTable,
    queries: &BindingLookupLocationTable,
    result: &BindingLookupDeclarationResultTable): int {
    queryCount := BindingLookupMinInt(BindingLookupLocationCount(ref queries), result.DeclarationIndices.Length)

    foundCount := 0
    i := 0
    while i < queryCount {
        declarationIndex := BindingLookupFindIndexCore(ref declarations, ref declarationSlots, queries.FileRanks[i], queries.LineNumbers[i], queries.Columns[i])

        if declarationIndex < 0 {
            bindingIndex := BindingLookupFindIndexCore(ref bindings, ref bindingSlots, queries.FileRanks[i], queries.LineNumbers[i], queries.Columns[i])

            if bindingIndex >= 0 && bindingIndex < bindingLinks.DeclarationIndices.Length {
                declarationIndex = bindingLinks.DeclarationIndices[bindingIndex]
                if declarationIndex < 0 || declarationIndex >= declarations.FileRanks.Length {
                    declarationIndex = -1
                }
            }
        }

        result.DeclarationIndices[i] = declarationIndex
        if declarationIndex >= 0 {
            foundCount = foundCount + 1
        }

        i = i + 1
    }

    return foundCount
}

func BindingLookupCandidateColumnsInto(
    queryColumns: int[],
    spanStartColumns: int[],
    spanEndColumns: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultColumns: int[]): int {
    spans := new BindingLookupCandidateSpanTable { QueryColumns: queryColumns, SpanStartColumns: spanStartColumns, SpanEndColumns: spanEndColumns }
    output := new BindingLookupCandidateColumnOutputTable { Starts: resultStarts, Counts: resultCounts, Columns: resultColumns }
    return BindingLookupCandidateColumnsCore(ref spans, ref output)
}

func BindingLookupCandidateColumnsCore(
    spans: &BindingLookupCandidateSpanTable,
    output: &BindingLookupCandidateColumnOutputTable): int {
    queryCount := BindingLookupCandidateSpanCount(ref spans, ref output)

    writeIndex := 0
    i := 0
    while i < queryCount {
        output.Starts[i] = writeIndex
        segmentStart := writeIndex
        column := spans.QueryColumns[i]
        spanStart := spans.SpanStartColumns[i]
        spanEnd := spans.SpanEndColumns[i]

        maxDistance := BindingLookupCandidateColumnMaxDistance(column, spanStart, spanEnd)
        if maxDistance > 64 {
            columns := new BindingLookupCandidateColumnTable { Columns: output.Columns }
            writeIndex = BindingLookupCandidateColumnsByCompactSortCore(column, spanStart, spanEnd, ref columns, writeIndex)
        } else {
            distance := 0
            while distance <= maxDistance {
                left := column - distance
                if BindingLookupCandidateColumnInSet(left, column, spanStart, spanEnd) {
                    if writeIndex < output.Columns.Length {
                        output.Columns[writeIndex] = left
                        writeIndex = writeIndex + 1
                    }
                }

                if distance > 0 {
                    right := column + distance
                    if BindingLookupCandidateColumnInSet(right, column, spanStart, spanEnd) {
                        if writeIndex < output.Columns.Length {
                            output.Columns[writeIndex] = right
                            writeIndex = writeIndex + 1
                        }
                    }
                }

                distance = distance + 1
            }
        }

        output.Counts[i] = writeIndex - segmentStart
        i = i + 1
    }

    return writeIndex
}

func BindingLookupFindNearestDeclarationIndicesInto(
    sortedNameIds: int[],
    sortedFileRanks: int[],
    sortedLineNumbers: int[],
    sortedColumns: int[],
    sortedDeclarationIndices: int[],
    queryNameIds: int[],
    queryFileRanks: int[],
    queryLineNumbers: int[],
    resultDeclarationIndices: int[]): int {
    sorted := new BindingLookupNearestDeclarationSortedTable { NameIds: sortedNameIds, FileRanks: sortedFileRanks, LineNumbers: sortedLineNumbers, Columns: sortedColumns, DeclarationIndices: sortedDeclarationIndices }
    queries := new BindingLookupNearestQueryTable { NameIds: queryNameIds, FileRanks: queryFileRanks, LineNumbers: queryLineNumbers }
    result := new BindingLookupDeclarationResultTable { DeclarationIndices: resultDeclarationIndices }
    return BindingLookupFindNearestDeclarationIndicesCore(ref sorted, ref queries, ref result)
}

func BindingLookupFindNearestDeclarationIndicesCore(
    sorted: &BindingLookupNearestDeclarationSortedTable,
    queries: &BindingLookupNearestQueryTable,
    result: &BindingLookupDeclarationResultTable): int {
    queryCount := BindingLookupNearestQueryResultCount(ref queries, ref result)
    declarationCount := BindingLookupNearestDeclarationSortedCount(ref sorted)

    foundCount := 0
    i := 0
    while i < queryCount {
        queryNameId := queries.NameIds[i]
        queryFileRank := queries.FileRanks[i]
        queryLine := queries.LineNumbers[i]
        declarationIndex := -1

        if queryNameId >= 0 && queryFileRank >= 0 && declarationCount > 0 {
            lower := 0
            upper := declarationCount

            while lower < upper {
                middle := (lower + upper) >> 1
                if BindingLookupNearestKeyIsBeforeOrAtQuery(
                    sorted.NameIds[middle],
                    sorted.FileRanks[middle],
                    sorted.LineNumbers[middle],
                    queryNameId,
                    queryFileRank,
                    queryLine) {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }

            candidate := lower - 1
            if candidate >= 0
                && sorted.NameIds[candidate] == queryNameId
                && sorted.FileRanks[candidate] == queryFileRank
                && sorted.LineNumbers[candidate] <= queryLine {
                declarationIndex = sorted.DeclarationIndices[candidate]
            }
        }

        result.DeclarationIndices[i] = declarationIndex
        if declarationIndex >= 0 {
            foundCount = foundCount + 1
        }

        i = i + 1
    }

    return foundCount
}

func BindingLookupBuildNearestDeclarationIndexInto(
    declarationNameIds: int[],
    declarationFileRanks: int[],
    declarationLineNumbers: int[],
    declarationColumns: int[],
    tempDeclarationIndices: int[],
    stackLefts: int[],
    sortedNameIds: int[],
    sortedFileRanks: int[],
    sortedLineNumbers: int[],
    sortedColumns: int[],
    sortedDeclarationIndices: int[]): int {
    source := new BindingLookupNearestDeclarationSourceTable { NameIds: declarationNameIds, FileRanks: declarationFileRanks, LineNumbers: declarationLineNumbers, Columns: declarationColumns }
    scratch := new BindingLookupNearestDeclarationScratchTable { TempDeclarationIndices: tempDeclarationIndices, StackLefts: stackLefts }
    sorted := new BindingLookupNearestDeclarationSortedTable { NameIds: sortedNameIds, FileRanks: sortedFileRanks, LineNumbers: sortedLineNumbers, Columns: sortedColumns, DeclarationIndices: sortedDeclarationIndices }
    return BindingLookupBuildNearestDeclarationIndexCore(ref source, ref scratch, ref sorted)
}

func BindingLookupBuildNearestDeclarationIndexCore(
    source: &BindingLookupNearestDeclarationSourceTable,
    scratch: &BindingLookupNearestDeclarationScratchTable,
    sorted: &BindingLookupNearestDeclarationSortedTable): int {
    declarationCount := BindingLookupNearestDeclarationSourceOutputCount(ref source, ref sorted)

    if declarationCount == 0 {
        return 0
    }

    maxNameId := 0
    i := 0
    while i < declarationCount {
        nameId := source.NameIds[i]
        if nameId < 0 {
            return -1
        }

        if nameId > maxNameId {
            maxNameId = nameId
        }

        i = i + 1
    }

    if maxNameId >= scratch.StackLefts.Length || maxNameId >= scratch.TempDeclarationIndices.Length {
        return -1
    }

    i = 0
    while i <= maxNameId {
        scratch.StackLefts[i] = 0
        i = i + 1
    }

    i = 0
    while i < declarationCount {
        nameId := source.NameIds[i]
        scratch.StackLefts[nameId] = scratch.StackLefts[nameId] + 1
        i = i + 1
    }

    offset := 0
    i = 0
    while i <= maxNameId {
        countForName := scratch.StackLefts[i]
        scratch.StackLefts[i] = offset
        offset = offset + countForName
        i = i + 1
    }

    i = 0
    while i <= maxNameId {
        scratch.TempDeclarationIndices[i] = -1
        i = i + 1
    }

    i = 0
    while i < declarationCount {
        nameId := source.NameIds[i]
        previousDeclarationIndex := scratch.TempDeclarationIndices[nameId]
        if previousDeclarationIndex >= 0 {
            fileRank := source.FileRanks[i]
            previousFileRank := source.FileRanks[previousDeclarationIndex]
            if fileRank < previousFileRank {
                return -1
            }

            if fileRank == previousFileRank {
                lineNumber := source.LineNumbers[i]
                previousLineNumber := source.LineNumbers[previousDeclarationIndex]
                if lineNumber < previousLineNumber {
                    return -1
                }

                if lineNumber == previousLineNumber {
                    column := source.Columns[i]
                    previousColumn := source.Columns[previousDeclarationIndex]
                    if column < previousColumn {
                        return -1
                    }
                }
            }
        }

        target := scratch.StackLefts[nameId]
        sorted.NameIds[target] = nameId
        sorted.FileRanks[target] = source.FileRanks[i]
        sorted.LineNumbers[target] = source.LineNumbers[i]
        sorted.Columns[target] = source.Columns[i]
        sorted.DeclarationIndices[target] = i
        scratch.StackLefts[nameId] = target + 1
        scratch.TempDeclarationIndices[nameId] = i
        i = i + 1
    }

    return declarationCount
}

func BindingLookupFindIndex(
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    slotIndices: int[],
    fileRank: int,
    line: int,
    column: int): int {
    locations := new BindingLookupLocationTable { FileRanks: fileRanks, LineNumbers: lineNumbers, Columns: columns }
    slots := new BindingLookupSlotTable { Indices: slotIndices }
    return BindingLookupFindIndexCore(ref locations, ref slots, fileRank, line, column)
}

func BindingLookupFindIndexCore(
    locations: &BindingLookupLocationTable,
    slots: &BindingLookupSlotTable,
    fileRank: int,
    line: int,
    column: int): int {
    count := BindingLookupLocationCount(ref locations)
    capacity := slots.Indices.Length
    if count == 0 || capacity == 0 {
        return -1
    }

    hash := HashBindingLookupKey(fileRank, line, column)
    slot := BindingLookupPositiveModulo(hash, capacity)
    probes := 0

    while probes < capacity {
        index := slots.Indices[slot]
        if index < 0 {
            return -1
        }

        if index < count
            && locations.FileRanks[index] == fileRank
            && locations.LineNumbers[index] == line
            && locations.Columns[index] == column {
            return index
        }

        slot = slot + 1
        if slot == capacity {
            slot = 0
        }
        probes = probes + 1
    }

    return -1
}

func BindingLookupKeysEqual(
    left: int,
    right: int,
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[]): bool {
    locations := new BindingLookupLocationTable { FileRanks: fileRanks, LineNumbers: lineNumbers, Columns: columns }
    return BindingLookupKeysEqualCore(left, right, ref locations)
}

func BindingLookupKeysEqualCore(
    left: int,
    right: int,
    locations: &BindingLookupLocationTable): bool {
    return locations.FileRanks[left] == locations.FileRanks[right]
        && locations.LineNumbers[left] == locations.LineNumbers[right]
        && locations.Columns[left] == locations.Columns[right]
}

func HashBindingLookupKey(fileRank: int, line: int, column: int): int {
    hash := 17
    hash = hash * 31 + fileRank
    hash = hash * 31 + line
    hash = hash * 31 + column
    return hash
}

func BindingLookupNearestKeyIsBeforeOrAtQuery(
    nameId: int,
    fileRank: int,
    line: int,
    queryNameId: int,
    queryFileRank: int,
    queryLine: int): bool {
    if nameId < queryNameId {
        return true
    }

    if nameId > queryNameId {
        return false
    }

    if fileRank < queryFileRank {
        return true
    }

    if fileRank > queryFileRank {
        return false
    }

    return line <= queryLine
}

func BindingLookupPositiveModulo(value: int, divisor: int): int {
    result := value % divisor
    if result < 0 {
        return result + divisor
    }

    return result
}

func BindingLookupMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

func BindingLookupAbsInt(value: int): int {
    if value < 0 {
        return 0 - value
    }

    return value
}

func BindingLookupCandidateColumnInSet(
    candidate: int,
    column: int,
    spanStart: int,
    spanEnd: int): bool {
    if column > 0 && candidate == column {
        return true
    }

    if column > 1 && candidate == column - 1 {
        return true
    }

    if candidate == column + 1 {
        return true
    }

    return spanStart > 0 && spanEnd >= spanStart && candidate >= spanStart && candidate <= spanEnd
}

func BindingLookupCandidateColumnMaxDistance(column: int, spanStart: int, spanEnd: int): int {
    maxDistance := 1

    if column > 1 {
        leftDistance := BindingLookupAbsInt((column - 1) - column)
        if leftDistance > maxDistance {
            maxDistance = leftDistance
        }
    }

    rightDistance := BindingLookupAbsInt((column + 1) - column)
    if rightDistance > maxDistance {
        maxDistance = rightDistance
    }

    if spanStart > 0 && spanEnd >= spanStart {
        startDistance := BindingLookupAbsInt(spanStart - column)
        if startDistance > maxDistance {
            maxDistance = startDistance
        }

        endDistance := BindingLookupAbsInt(spanEnd - column)
        if endDistance > maxDistance {
            maxDistance = endDistance
        }
    }

    return maxDistance
}

func BindingLookupCandidateColumnsByCompactSort(
    column: int,
    spanStart: int,
    spanEnd: int,
    resultColumns: int[],
    writeIndex: int): int {
    columns := new BindingLookupCandidateColumnTable { Columns: resultColumns }
    return BindingLookupCandidateColumnsByCompactSortCore(column, spanStart, spanEnd, ref columns, writeIndex)
}

func BindingLookupCandidateColumnsByCompactSortCore(
    column: int,
    spanStart: int,
    spanEnd: int,
    resultColumns: &BindingLookupCandidateColumnTable,
    writeIndex: int): int {
    segmentStart := writeIndex

    if column > 0 {
        writeIndex = BindingLookupAppendCandidateColumnCore(ref resultColumns, writeIndex, segmentStart, column)
    }

    if column > 1 {
        writeIndex = BindingLookupAppendCandidateColumnCore(ref resultColumns, writeIndex, segmentStart, column - 1)
    }

    writeIndex = BindingLookupAppendCandidateColumnCore(ref resultColumns, writeIndex, segmentStart, column + 1)

    if spanStart > 0 && spanEnd >= spanStart {
        candidate := spanStart
        while candidate <= spanEnd {
            writeIndex = BindingLookupAppendCandidateColumnCore(ref resultColumns, writeIndex, segmentStart, candidate)
            candidate = candidate + 1
        }
    }

    i := segmentStart + 1
    while i < writeIndex {
        value := resultColumns.Columns[i]
        distance := BindingLookupCandidateColumnDistance(value, column)
        j := i - 1
        while j >= segmentStart && BindingLookupCandidateColumnDistance(resultColumns.Columns[j], column) > distance {
            resultColumns.Columns[j + 1] = resultColumns.Columns[j]
            j = j - 1
        }

        resultColumns.Columns[j + 1] = value
        i = i + 1
    }

    return writeIndex
}

func BindingLookupAppendCandidateColumn(
    resultColumns: int[],
    writeIndex: int,
    segmentStart: int,
    candidate: int): int {
    columns := new BindingLookupCandidateColumnTable { Columns: resultColumns }
    return BindingLookupAppendCandidateColumnCore(ref columns, writeIndex, segmentStart, candidate)
}

func BindingLookupAppendCandidateColumnCore(
    resultColumns: &BindingLookupCandidateColumnTable,
    writeIndex: int,
    segmentStart: int,
    candidate: int): int {
    i := segmentStart
    while i < writeIndex {
        if resultColumns.Columns[i] == candidate {
            return writeIndex
        }

        i = i + 1
    }

    if writeIndex < resultColumns.Columns.Length {
        resultColumns.Columns[writeIndex] = candidate
        return writeIndex + 1
    }

    return writeIndex
}

func BindingLookupCandidateColumnDistance(candidate: int, column: int): int {
    if candidate >= column {
        return candidate - column
    }

    return column - candidate
}

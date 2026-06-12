func BindingLookupBuildSlotsInto(
    fileRanks: int[],
    lineNumbers: int[],
    columns: int[],
    slotIndices: int[]): int {
    count := BindingLookupMinInt(fileRanks.Length, lineNumbers.Length)
    count = BindingLookupMinInt(count, columns.Length)

    capacity := slotIndices.Length
    if count == 0 || capacity == 0 {
        return 0
    }

    i := 0
    while i < capacity {
        slotIndices[i] = -1
        i = i + 1
    }

    insertedCount := 0
    index := 0
    while index < count {
        hash := HashBindingLookupKey(fileRanks[index], lineNumbers[index], columns[index])
        slot := BindingLookupPositiveModulo(hash, capacity)
        probes := 0

        while probes < capacity {
            candidateIndex := slotIndices[slot]
            if candidateIndex < 0 {
                slotIndices[slot] = index
                insertedCount = insertedCount + 1
                break
            }

            if BindingLookupKeysEqual(
                index,
                candidateIndex,
                fileRanks,
                lineNumbers,
                columns) {
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
    queryCount := BindingLookupMinInt(queryFileRanks.Length, queryLineNumbers.Length)
    queryCount = BindingLookupMinInt(queryCount, queryColumns.Length)
    queryCount = BindingLookupMinInt(queryCount, resultDeclarationIndices.Length)

    foundCount := 0
    i := 0
    while i < queryCount {
        declarationIndex := BindingLookupFindIndex(
            declarationFileRanks,
            declarationLineNumbers,
            declarationColumns,
            declarationSlotIndices,
            queryFileRanks[i],
            queryLineNumbers[i],
            queryColumns[i])

        if declarationIndex < 0 {
            bindingIndex := BindingLookupFindIndex(
                bindingFileRanks,
                bindingLineNumbers,
                bindingColumns,
                bindingSlotIndices,
                queryFileRanks[i],
                queryLineNumbers[i],
                queryColumns[i])

            if bindingIndex >= 0 && bindingIndex < bindingDeclarationIndices.Length {
                declarationIndex = bindingDeclarationIndices[bindingIndex]
                if declarationIndex < 0 || declarationIndex >= declarationFileRanks.Length {
                    declarationIndex = -1
                }
            }
        }

        resultDeclarationIndices[i] = declarationIndex
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
    queryCount := BindingLookupMinInt(queryColumns.Length, spanStartColumns.Length)
    queryCount = BindingLookupMinInt(queryCount, spanEndColumns.Length)
    queryCount = BindingLookupMinInt(queryCount, resultStarts.Length)
    queryCount = BindingLookupMinInt(queryCount, resultCounts.Length)

    writeIndex := 0
    i := 0
    while i < queryCount {
        resultStarts[i] = writeIndex
        segmentStart := writeIndex
        column := queryColumns[i]
        spanStart := spanStartColumns[i]
        spanEnd := spanEndColumns[i]

        maxDistance := BindingLookupCandidateColumnMaxDistance(column, spanStart, spanEnd)
        if maxDistance > 64 {
            writeIndex = BindingLookupCandidateColumnsByCompactSort(
                column,
                spanStart,
                spanEnd,
                resultColumns,
                writeIndex)
        } else {
            distance := 0
            while distance <= maxDistance {
                left := column - distance
                if BindingLookupCandidateColumnInSet(left, column, spanStart, spanEnd) {
                    if writeIndex < resultColumns.Length {
                        resultColumns[writeIndex] = left
                        writeIndex = writeIndex + 1
                    }
                }

                if distance > 0 {
                    right := column + distance
                    if BindingLookupCandidateColumnInSet(right, column, spanStart, spanEnd) {
                        if writeIndex < resultColumns.Length {
                            resultColumns[writeIndex] = right
                            writeIndex = writeIndex + 1
                        }
                    }
                }

                distance = distance + 1
            }
        }

        resultCounts[i] = writeIndex - segmentStart
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
    queryCount := BindingLookupMinInt(queryNameIds.Length, queryFileRanks.Length)
    queryCount = BindingLookupMinInt(queryCount, queryLineNumbers.Length)
    queryCount = BindingLookupMinInt(queryCount, resultDeclarationIndices.Length)
    declarationCount := BindingLookupMinInt(sortedNameIds.Length, sortedFileRanks.Length)
    declarationCount = BindingLookupMinInt(declarationCount, sortedLineNumbers.Length)
    declarationCount = BindingLookupMinInt(declarationCount, sortedColumns.Length)
    declarationCount = BindingLookupMinInt(declarationCount, sortedDeclarationIndices.Length)

    foundCount := 0
    i := 0
    while i < queryCount {
        queryNameId := queryNameIds[i]
        queryFileRank := queryFileRanks[i]
        queryLine := queryLineNumbers[i]
        declarationIndex := -1

        if queryNameId >= 0 && queryFileRank >= 0 && declarationCount > 0 {
            lower := 0
            upper := declarationCount

            while lower < upper {
                middle := (lower + upper) >> 1
                if BindingLookupNearestKeyIsBeforeOrAtQuery(
                    sortedNameIds[middle],
                    sortedFileRanks[middle],
                    sortedLineNumbers[middle],
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
                && sortedNameIds[candidate] == queryNameId
                && sortedFileRanks[candidate] == queryFileRank
                && sortedLineNumbers[candidate] <= queryLine {
                declarationIndex = sortedDeclarationIndices[candidate]
            }
        }

        resultDeclarationIndices[i] = declarationIndex
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
    declarationCount := BindingLookupMinInt(declarationNameIds.Length, declarationFileRanks.Length)
    declarationCount = BindingLookupMinInt(declarationCount, declarationLineNumbers.Length)
    declarationCount = BindingLookupMinInt(declarationCount, declarationColumns.Length)
    declarationCount = BindingLookupMinInt(declarationCount, sortedNameIds.Length)
    declarationCount = BindingLookupMinInt(declarationCount, sortedFileRanks.Length)
    declarationCount = BindingLookupMinInt(declarationCount, sortedLineNumbers.Length)
    declarationCount = BindingLookupMinInt(declarationCount, sortedColumns.Length)
    declarationCount = BindingLookupMinInt(declarationCount, sortedDeclarationIndices.Length)

    if declarationCount == 0 {
        return 0
    }

    maxNameId := 0
    i := 0
    while i < declarationCount {
        nameId := declarationNameIds[i]
        if nameId < 0 {
            return -1
        }

        if nameId > maxNameId {
            maxNameId = nameId
        }

        i = i + 1
    }

    if maxNameId >= stackLefts.Length || maxNameId >= tempDeclarationIndices.Length {
        return -1
    }

    i = 0
    while i <= maxNameId {
        stackLefts[i] = 0
        i = i + 1
    }

    i = 0
    while i < declarationCount {
        nameId := declarationNameIds[i]
        stackLefts[nameId] = stackLefts[nameId] + 1
        i = i + 1
    }

    offset := 0
    i = 0
    while i <= maxNameId {
        countForName := stackLefts[i]
        stackLefts[i] = offset
        offset = offset + countForName
        i = i + 1
    }

    i = 0
    while i <= maxNameId {
        tempDeclarationIndices[i] = -1
        i = i + 1
    }

    i = 0
    while i < declarationCount {
        nameId := declarationNameIds[i]
        previousDeclarationIndex := tempDeclarationIndices[nameId]
        if previousDeclarationIndex >= 0 {
            fileRank := declarationFileRanks[i]
            previousFileRank := declarationFileRanks[previousDeclarationIndex]
            if fileRank < previousFileRank {
                return -1
            }

            if fileRank == previousFileRank {
                lineNumber := declarationLineNumbers[i]
                previousLineNumber := declarationLineNumbers[previousDeclarationIndex]
                if lineNumber < previousLineNumber {
                    return -1
                }

                if lineNumber == previousLineNumber {
                    column := declarationColumns[i]
                    previousColumn := declarationColumns[previousDeclarationIndex]
                    if column < previousColumn {
                        return -1
                    }
                }
            }
        }

        target := stackLefts[nameId]
        sortedNameIds[target] = nameId
        sortedFileRanks[target] = declarationFileRanks[i]
        sortedLineNumbers[target] = declarationLineNumbers[i]
        sortedColumns[target] = declarationColumns[i]
        sortedDeclarationIndices[target] = i
        stackLefts[nameId] = target + 1
        tempDeclarationIndices[nameId] = i
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
    count := BindingLookupMinInt(fileRanks.Length, lineNumbers.Length)
    count = BindingLookupMinInt(count, columns.Length)
    capacity := slotIndices.Length
    if count == 0 || capacity == 0 {
        return -1
    }

    hash := HashBindingLookupKey(fileRank, line, column)
    slot := BindingLookupPositiveModulo(hash, capacity)
    probes := 0

    while probes < capacity {
        index := slotIndices[slot]
        if index < 0 {
            return -1
        }

        if index < count
            && fileRanks[index] == fileRank
            && lineNumbers[index] == line
            && columns[index] == column {
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
    return fileRanks[left] == fileRanks[right]
        && lineNumbers[left] == lineNumbers[right]
        && columns[left] == columns[right]
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
    segmentStart := writeIndex

    if column > 0 {
        writeIndex = BindingLookupAppendCandidateColumn(resultColumns, writeIndex, segmentStart, column)
    }

    if column > 1 {
        writeIndex = BindingLookupAppendCandidateColumn(resultColumns, writeIndex, segmentStart, column - 1)
    }

    writeIndex = BindingLookupAppendCandidateColumn(resultColumns, writeIndex, segmentStart, column + 1)

    if spanStart > 0 && spanEnd >= spanStart {
        candidate := spanStart
        while candidate <= spanEnd {
            writeIndex = BindingLookupAppendCandidateColumn(resultColumns, writeIndex, segmentStart, candidate)
            candidate = candidate + 1
        }
    }

    i := segmentStart + 1
    while i < writeIndex {
        value := resultColumns[i]
        distance := BindingLookupCandidateColumnDistance(value, column)
        j := i - 1
        while j >= segmentStart && BindingLookupCandidateColumnDistance(resultColumns[j], column) > distance {
            resultColumns[j + 1] = resultColumns[j]
            j = j - 1
        }

        resultColumns[j + 1] = value
        i = i + 1
    }

    return writeIndex
}

func BindingLookupAppendCandidateColumn(
    resultColumns: int[],
    writeIndex: int,
    segmentStart: int,
    candidate: int): int {
    i := segmentStart
    while i < writeIndex {
        if resultColumns[i] == candidate {
            return writeIndex
        }

        i = i + 1
    }

    if writeIndex < resultColumns.Length {
        resultColumns[writeIndex] = candidate
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

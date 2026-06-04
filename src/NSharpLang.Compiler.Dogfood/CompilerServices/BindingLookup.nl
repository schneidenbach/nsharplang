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

func BindingLookupQueryChecksumInto(
    declarationFileRanks: int[],
    declarationLineNumbers: int[],
    declarationColumns: int[],
    declarationNameLengths: int[],
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
    declarationCount := BindingLookupMinInt(declarationFileRanks.Length, declarationLineNumbers.Length)
    declarationCount = BindingLookupMinInt(declarationCount, declarationColumns.Length)
    bindingCount := BindingLookupMinInt(bindingFileRanks.Length, bindingLineNumbers.Length)
    bindingCount = BindingLookupMinInt(bindingCount, bindingColumns.Length)
    declarationCapacity := declarationSlotIndices.Length
    bindingCapacity := bindingSlotIndices.Length

    foundCount := 0
    checksum := 0
    i := 0
    while i < queryCount {
        queryFileRank := queryFileRanks[i]
        queryLine := queryLineNumbers[i]
        queryColumn := queryColumns[i]
        declarationIndex := -1

        if declarationCount > 0 && declarationCapacity > 0 {
            hash := 17
            hash = hash * 31 + queryFileRank
            hash = hash * 31 + queryLine
            hash = hash * 31 + queryColumn
            slot := hash % declarationCapacity
            if slot < 0 {
                slot = slot + declarationCapacity
            }

            probes := 0
            while probes < declarationCapacity {
                index := declarationSlotIndices[slot]
                if index < 0 {
                    break
                }

                if index < declarationCount
                    && declarationFileRanks[index] == queryFileRank
                    && declarationLineNumbers[index] == queryLine
                    && declarationColumns[index] == queryColumn {
                    declarationIndex = index
                    break
                }

                slot = slot + 1
                if slot == declarationCapacity {
                    slot = 0
                }
                probes = probes + 1
            }
        }

        if declarationIndex < 0 && bindingCount > 0 && bindingCapacity > 0 {
            hash := 17
            hash = hash * 31 + queryFileRank
            hash = hash * 31 + queryLine
            hash = hash * 31 + queryColumn
            slot := hash % bindingCapacity
            if slot < 0 {
                slot = slot + bindingCapacity
            }

            probes := 0
            while probes < bindingCapacity {
                bindingIndex := bindingSlotIndices[slot]
                if bindingIndex < 0 {
                    break
                }

                if bindingIndex < bindingCount
                    && bindingFileRanks[bindingIndex] == queryFileRank
                    && bindingLineNumbers[bindingIndex] == queryLine
                    && bindingColumns[bindingIndex] == queryColumn {
                    if bindingIndex < bindingDeclarationIndices.Length {
                        declarationIndex = bindingDeclarationIndices[bindingIndex]
                        if declarationIndex < 0 || declarationIndex >= declarationCount {
                            declarationIndex = -1
                        }
                    }
                    break
                }

                slot = slot + 1
                if slot == bindingCapacity {
                    slot = 0
                }
                probes = probes + 1
            }
        }

        resultDeclarationIndices[i] = declarationIndex
        if declarationIndex >= 0 {
            foundCount = foundCount + 1
            nameLength := 0
            if declarationIndex < declarationNameLengths.Length {
                nameLength = declarationNameLengths[declarationIndex]
            }

            checksum = checksum
                + declarationLineNumbers[declarationIndex] * 31
                + declarationColumns[declarationIndex] * 17
                + nameLength * 13
        }

        i = i + 1
    }

    return checksum + foundCount
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

func BindingLookupFindNearestDeclarationChecksumInto(
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
    checksum := 0
    i := 0
    while i < queryCount {
        queryNameId := queryNameIds[i]
        queryFileRank := queryFileRanks[i]
        queryLine := queryLineNumbers[i]
        declarationIndex := -1
        selectedSlot := -1

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
                selectedSlot = candidate
                declarationIndex = sortedDeclarationIndices[candidate]
            }
        }

        resultDeclarationIndices[i] = declarationIndex
        if declarationIndex >= 0 {
            foundCount = foundCount + 1
            checksum = checksum
                + sortedNameIds[selectedSlot] * 13
                + sortedLineNumbers[selectedSlot] * 31
                + sortedColumns[selectedSlot] * 17
                + declarationIndex
        }

        i = i + 1
    }

    return checksum + foundCount
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

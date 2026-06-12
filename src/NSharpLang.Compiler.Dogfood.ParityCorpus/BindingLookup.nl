// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/BindingLookup.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

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

func BindingLookupCandidateColumnChecksumInto(
    queryColumns: int[],
    spanStartColumns: int[],
    spanEndColumns: int[],
    resultStarts: int[],
    resultCounts: int[],
    resultColumns: int[]): int {
    total := BindingLookupCandidateColumnsInto(
        queryColumns,
        spanStartColumns,
        spanEndColumns,
        resultStarts,
        resultCounts,
        resultColumns)

    checksum := total
    i := 0
    while i < resultCounts.Length {
        start := resultStarts[i]
        count := resultCounts[i]
        checksum = checksum + count * 97 + start * 7

        j := 0
        while j < count {
            index := start + j
            if index >= 0 && index < resultColumns.Length {
                checksum = checksum + resultColumns[index] * 31 + (j + 1) * 17
            }

            j = j + 1
        }

        i = i + 1
    }

    return checksum
}

func BindingLookupBuildNearestDeclarationIndexChecksumInto(
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
    count := BindingLookupBuildNearestDeclarationIndexInto(
        declarationNameIds,
        declarationFileRanks,
        declarationLineNumbers,
        declarationColumns,
        tempDeclarationIndices,
        stackLefts,
        sortedNameIds,
        sortedFileRanks,
        sortedLineNumbers,
        sortedColumns,
        sortedDeclarationIndices)

    if count < 0 {
        return count
    }

    checksum := count * 17
    i := 0
    while i < count {
        checksum = checksum
            + (i + 1) * 97
            + sortedNameIds[i] * 31
            + sortedFileRanks[i] * 23
            + sortedLineNumbers[i] * 13
            + sortedColumns[i] * 7
            + sortedDeclarationIndices[i] * 3
        i = i + 1
    }

    return checksum
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

import System

func CodeIntelligenceIdentifierSpanChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    CodeIntelligenceIdentifierSpansInto(
        source,
        lineStarts,
        lineLengths,
        queryLines,
        queryColumns,
        resultStarts,
        resultLengths)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        spanStart := resultStarts[i]
        spanLength := resultLengths[i]
        checksum = checksum + spanStart * 31 + spanLength * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceIdentifierSpansInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceIdentifierSpansFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        queryColumns,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceIdentifierSpansFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    foundCount := 0
    i := 0

    while i < queryLines.Length {
        spanStart := -1
        spanLength := 0
        line := queryLines[i]
        column := queryColumns[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            lineLength := lineLengths[lineIndex]

            if lineLength > 0 {
                index := column - 1
                if index < 0 {
                    index = 0
                }

                if index >= lineLength {
                    index = lineLength - 1
                }

                nearest := FindNearestCodeIntelligenceIdentifierIndex(
                    source,
                    lineStarts[lineIndex],
                    lineLength,
                    index)

                if nearest >= 0 {
                    start := nearest
                    lineStart := lineStarts[lineIndex]
                    while start > 0 && IsCodeIntelligenceIdentifierChar(source[lineStart + start - 1]) {
                        start = start - 1
                    }

                    end := nearest
                    while end + 1 < lineLength && IsCodeIntelligenceIdentifierChar(source[lineStart + end + 1]) {
                        end = end + 1
                    }

                    spanStart = start + 1
                    spanLength = end - start + 1
                }
            }
        }

        resultStarts[i] = spanStart
        resultLengths[i] = spanLength
        if spanStart >= 0 {
            foundCount = foundCount + 1
        }

        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceEditorIdentifierSpanChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    CodeIntelligenceEditorIdentifierSpansInto(
        source,
        lineStarts,
        lineLengths,
        queryLines,
        queryColumns,
        resultStarts,
        resultLengths)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        spanStart := resultStarts[i]
        spanLength := resultLengths[i]
        checksum = checksum + spanStart * 31 + spanLength * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceEditorIdentifierSpansInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceEditorIdentifierSpansFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        queryColumns,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceEditorIdentifierSpansFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    foundCount := 0
    i := 0

    while i < queryLines.Length {
        spanStart := -1
        spanLength := 0
        line := queryLines[i]
        column := queryColumns[i]

        if line > 0 && line <= lineCount && column > 0 {
            lineIndex := line - 1
            lineLength := lineLengths[lineIndex]

            if lineLength > 0 {
                character := column - 1
                lineStart := lineStarts[lineIndex]

                if character >= lineLength {
                    character = lineLength - 1
                    if !IsCodeIntelligenceIdentifierChar(source[lineStart + character]) {
                        resultStarts[i] = spanStart
                        resultLengths[i] = spanLength
                        i = i + 1
                        continue
                    }
                } else {
                    if !IsCodeIntelligenceIdentifierChar(source[lineStart + character]) {
                        resultStarts[i] = spanStart
                        resultLengths[i] = spanLength
                        i = i + 1
                        continue
                    }
                }

                start := character
                while start > 0 && IsCodeIntelligenceIdentifierChar(source[lineStart + start - 1]) {
                    start = start - 1
                }

                end := character
                while end + 1 < lineLength && IsCodeIntelligenceIdentifierChar(source[lineStart + end + 1]) {
                    end = end + 1
                }

                spanStart = start + 1
                spanLength = end - start + 1
            }
        }

        resultStarts[i] = spanStart
        resultLengths[i] = spanLength
        if spanStart >= 0 {
            foundCount = foundCount + 1
        }

        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceDeclarationNameMatchChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    declarationColumns: int[],
    declarationNames: string[],
    selectedStartColumns: int[],
    selectedEndColumns: int[],
    resultMatches: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceDeclarationNameMatchChecksumFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        declarationColumns,
        declarationNames,
        selectedStartColumns,
        selectedEndColumns,
        resultMatches)
}

func CodeIntelligenceDeclarationNameMatchChecksumFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    declarationColumns: int[],
    declarationNames: string[],
    selectedStartColumns: int[],
    selectedEndColumns: int[],
    resultMatches: int[]): int {
    CodeIntelligenceDeclarationNameMatchesFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        declarationColumns,
        declarationNames,
        selectedStartColumns,
        selectedEndColumns,
        resultMatches)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        checksum = checksum + resultMatches[i] * (i + 1)
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceDeclarationNameMatchesFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    declarationColumns: int[],
    declarationNames: string[],
    selectedStartColumns: int[],
    selectedEndColumns: int[],
    resultMatches: int[]): int {
    matchCount := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        matched := 0
        line := queryLines[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            lineStart := lineStarts[lineIndex]
            lineLength := lineLengths[lineIndex]
            declarationName := declarationNames[i]
            searchStart := declarationColumns[i] - 1

            if searchStart < 0 {
                searchStart = 0
            }

            if searchStart > lineLength {
                searchStart = lineLength
            }

            nameIndex := FindCodeIntelligenceNameInLine(
                source,
                lineStart,
                lineLength,
                declarationName,
                searchStart)

            if nameIndex >= 0 {
                nameStartColumn := nameIndex + 1
                nameEndColumn := nameStartColumn + declarationName.Length - 1
                if selectedStartColumns[i] == nameStartColumn && selectedEndColumns[i] == nameEndColumn {
                    matched = 1
                    matchCount = matchCount + 1
                }
            }
        }

        resultMatches[i] = matched
        i = i + 1
    }

    return matchCount
}

func CodeIntelligenceIdentifierNameColumnChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    declarationNames: string[],
    fallbackColumns: int[],
    resultColumns: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceIdentifierNameColumnChecksumFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        declarationNames,
        fallbackColumns,
        resultColumns)
}

func CodeIntelligenceIdentifierNameColumnChecksumFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    declarationNames: string[],
    fallbackColumns: int[],
    resultColumns: int[]): int {
    foundCount := CodeIntelligenceIdentifierNameColumnsFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        declarationNames,
        fallbackColumns,
        resultColumns)

    checksum := foundCount
    i := 0

    while i < queryLines.Length {
        checksum = checksum + resultColumns[i] * 31 + fallbackColumns[i] * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceIdentifierNameColumnsInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    declarationNames: string[],
    fallbackColumns: int[],
    resultColumns: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceIdentifierNameColumnsFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        declarationNames,
        fallbackColumns,
        resultColumns)
}

func CodeIntelligenceIdentifierNameColumnsFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    declarationNames: string[],
    fallbackColumns: int[],
    resultColumns: int[]): int {
    foundCount := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        column := fallbackColumns[i]
        line := queryLines[i]
        declarationName := declarationNames[i]

        if line > 0 && line <= lineCount && declarationName.Length > 0 {
            lineIndex := line - 1
            lineStart := lineStarts[lineIndex]
            lineLength := lineLengths[lineIndex]

            while lineLength > 0 && source[lineStart + lineLength - 1] == '\r' {
                lineLength = lineLength - 1
            }

            if lineLength > 0 {
                searchStart := column - 1
                if searchStart < 0 {
                    searchStart = 0
                }

                if searchStart > lineLength {
                    searchStart = lineLength
                }

                nameIndex := FindCodeIntelligenceWholeIdentifierInLine(
                    source,
                    lineStart,
                    lineLength,
                    declarationName,
                    searchStart)

                if nameIndex < 0 && searchStart != 0 {
                    nameIndex = FindCodeIntelligenceWholeIdentifierInLine(
                        source,
                        lineStart,
                        lineLength,
                        declarationName,
                        0)
                }

                if nameIndex >= 0 {
                    column = nameIndex + 1
                    foundCount = foundCount + 1
                }
            }
        }

        resultColumns[i] = column
        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceMemberReceiverChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    memberStartColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    CodeIntelligenceMemberReceiversInto(
        source,
        lineStarts,
        lineLengths,
        queryLines,
        memberStartColumns,
        resultStarts,
        resultLengths)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        receiverStartColumn := resultStarts[i]
        receiverLength := resultLengths[i]
        checksum = checksum + receiverStartColumn * 31 + receiverLength * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceMemberReceiversInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    memberStartColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceMemberReceiversFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        memberStartColumns,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceMemberReceiversFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    memberStartColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    foundCount := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        receiverStartColumn := -1
        receiverLength := 0
        line := queryLines[i]
        memberStartColumn := memberStartColumns[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            lineLength := lineLengths[lineIndex]
            memberStartIndex := memberStartColumn - 1

            if memberStartIndex > 0 && memberStartIndex <= lineLength {
                lineStart := lineStarts[lineIndex]
                separatorIndex := memberStartIndex - 1
                separatorPosition := lineStart + separatorIndex

                if separatorIndex >= 0 && source[separatorPosition] == '.' {
                    receiverEnd := separatorPosition - 1
                    while receiverEnd >= lineStart {
                        ch := source[receiverEnd]
                        if ch == ' ' {
                            receiverEnd = receiverEnd - 1
                            continue
                        }

                        if ch <= '~' {
                            if ch >= '\t' && ch <= '\r' {
                                receiverEnd = receiverEnd - 1
                                continue
                            }

                            break
                        }

                        if Char.IsWhiteSpace(ch) {
                            receiverEnd = receiverEnd - 1
                            continue
                        }

                        break
                    }

                    if receiverEnd >= lineStart {
                        receiverStart := receiverEnd
                        while receiverStart >= lineStart {
                            ch := source[receiverStart]
                            if ch >= 'a' && ch <= 'z' {
                                receiverStart = receiverStart - 1
                                continue
                            }

                            if ch <= '~' {
                                if ch == '_'
                                    || (ch >= 'A' && ch <= 'Z')
                                    || (ch >= '0' && ch <= '9') {
                                    receiverStart = receiverStart - 1
                                    continue
                                }

                                break
                            }

                            if Char.IsLetterOrDigit(ch) {
                                receiverStart = receiverStart - 1
                                continue
                            }

                            break
                        }

                        receiverStart = receiverStart + 1
                        if receiverStart <= receiverEnd {
                            receiverStartColumn = receiverStart - lineStart + 1
                            receiverLength = receiverEnd - receiverStart + 1
                        }
                    }
                }
            }
        }

        resultStarts[i] = receiverStartColumn
        resultLengths[i] = receiverLength
        if receiverStartColumn >= 0 {
            foundCount = foundCount + 1
        }

        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceMemberReceiverCachedChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    receiverStartsBySeparator: int[],
    receiverLengthsBySeparator: int[],
    queryLines: int[],
    memberStartColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    CodeIntelligenceMemberReceiversCachedInto(
        source,
        lineStarts,
        lineLengths,
        receiverStartsBySeparator,
        receiverLengthsBySeparator,
        queryLines,
        memberStartColumns,
        resultStarts,
        resultLengths)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        receiverStartColumn := resultStarts[i]
        receiverLength := resultLengths[i]
        checksum = checksum + receiverStartColumn * 31 + receiverLength * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceMemberReceiversCachedInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    receiverStartsBySeparator: int[],
    receiverLengthsBySeparator: int[],
    queryLines: int[],
    memberStartColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    BuildCodeIntelligenceMemberReceiverCacheInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        receiverStartsBySeparator,
        receiverLengthsBySeparator)

    return CodeIntelligenceMemberReceiversFromCacheInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        receiverStartsBySeparator,
        receiverLengthsBySeparator,
        queryLines,
        memberStartColumns,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceMemberReceiversFromCacheInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    receiverStartsBySeparator: int[],
    receiverLengthsBySeparator: int[],
    queryLines: int[],
    memberStartColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    foundCount := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        receiverStartColumn := -1
        receiverLength := 0
        line := queryLines[i]
        memberStartColumn := memberStartColumns[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            lineLength := lineLengths[lineIndex]
            memberStartIndex := memberStartColumn - 1

            if memberStartIndex > 0 && memberStartIndex <= lineLength {
                lineStart := lineStarts[lineIndex]
                separatorPosition := lineStart + memberStartIndex - 1

                if source[separatorPosition] == '.' {
                    cachedStartColumn := receiverStartsBySeparator[separatorPosition]
                    if cachedStartColumn != 0 {
                        receiverStartColumn = cachedStartColumn
                        receiverLength = receiverLengthsBySeparator[separatorPosition]
                    }
                }
            }
        }

        resultStarts[i] = receiverStartColumn
        resultLengths[i] = receiverLength
        if receiverStartColumn >= 0 {
            foundCount = foundCount + 1
        }

        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceSourceContextChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    CodeIntelligenceSourceContextsInto(
        source,
        lineStarts,
        lineLengths,
        queryLines,
        resultStarts,
        resultLengths)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        contextStart := resultStarts[i]
        contextLength := resultLengths[i]
        checksum = checksum + contextStart * 31 + contextLength * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceSourceContextsInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceSourceContextsFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceSourceContextsFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    foundCount := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        contextStart := -1
        contextLength := 0
        line := queryLines[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            trimStart := lineStarts[lineIndex]
            trimEnd := trimStart + lineLengths[lineIndex] - 1

            while trimStart <= trimEnd && IsCodeIntelligenceWhitespace(source[trimStart]) {
                trimStart = trimStart + 1
            }

            while trimEnd >= trimStart && IsCodeIntelligenceWhitespace(source[trimEnd]) {
                trimEnd = trimEnd - 1
            }

            contextStart = trimStart
            if trimEnd >= trimStart {
                contextLength = trimEnd - trimStart + 1
            }

            foundCount = foundCount + 1
        }

        resultStarts[i] = contextStart
        resultLengths[i] = contextLength
        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceSourceLineChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    CodeIntelligenceSourceLinesInto(
        source,
        lineStarts,
        lineLengths,
        queryLines,
        resultStarts,
        resultLengths)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        lineStart := resultStarts[i]
        lineLength := resultLengths[i]
        checksum = checksum + lineStart * 31 + lineLength * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceSourceLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceSourceLinesFromLinesInto(
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceSourceLinesFromLinesInto(
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    foundCount := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        lineStart := -1
        lineLength := 0
        line := queryLines[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            lineStart = lineStarts[lineIndex]
            lineLength = lineLengths[lineIndex]
            foundCount = foundCount + 1
        }

        resultStarts[i] = lineStart
        resultLengths[i] = lineLength
        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceCompletionPrefixChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    CodeIntelligenceCompletionPrefixesInto(
        source,
        lineStarts,
        lineLengths,
        queryLines,
        queryColumns,
        resultStarts,
        resultLengths)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        prefixStart := resultStarts[i]
        prefixLength := resultLengths[i]
        checksum = checksum + prefixStart * 31 + prefixLength * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceCompletionPrefixesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceCompletionPrefixesFromLinesInto(
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        queryColumns,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceCompletionPrefixesFromLinesInto(
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    foundCount := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        prefixStart := -1
        prefixLength := 0
        line := queryLines[i]
        column := queryColumns[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            prefixStart = lineStarts[lineIndex]
            prefixLength = lineLengths[lineIndex]

            if column > 0 && column <= prefixLength {
                prefixLength = column
            }

            foundCount = foundCount + 1
        }

        resultStarts[i] = prefixStart
        resultLengths[i] = prefixLength
        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceDocCommentChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    resultLineCounts: int[],
    resultTextLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceDocCommentChecksumFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        resultLineCounts,
        resultTextLengths)
}

func CodeIntelligenceDocCommentChecksumFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    resultLineCounts: int[],
    resultTextLengths: int[]): int {
    checksum := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        definitionLine := queryLines[i]
        startLine := FindCodeIntelligenceDocCommentStartLine(
            source,
            lineStarts,
            lineLengths,
            lineCount,
            definitionLine)

        commentLineCount := 0
        textLength := -1

        if startLine >= 0 {
            lineIndex := startLine
            lastLineIndex := definitionLine - 2
            joinedLength := 0

            while lineIndex <= lastLineIndex {
                lineStart := lineStarts[lineIndex]
                lineLength := lineLengths[lineIndex]

                if IsCodeIntelligenceDocCommentLine(source, lineStart, lineLength) {
                    contentStart := GetCodeIntelligenceDocCommentContentStart(source, lineStart, lineLength)
                    contentLength := GetCodeIntelligenceDocCommentContentLength(source, lineStart, lineLength, contentStart)

                    if commentLineCount > 0 {
                        joinedLength = joinedLength + 1
                    }

                    joinedLength = joinedLength + contentLength
                    commentLineCount = commentLineCount + 1
                }

                lineIndex = lineIndex + 1
            }

            if commentLineCount > 0 {
                textLength = joinedLength
            }
        }

        resultLineCounts[i] = commentLineCount
        resultTextLengths[i] = textLength
        checksum = checksum + commentLineCount * 13 + textLength * 7
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceDocCommentLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    definitionLine: int,
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceDocCommentLinesFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        definitionLine,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceDocCommentLinesFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    definitionLine: int,
    resultStarts: int[],
    resultLengths: int[]): int {
    startLine := FindCodeIntelligenceDocCommentStartLine(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        definitionLine)

    if startLine < 0 {
        return 0
    }

    resultCount := 0
    lineIndex := startLine
    lastLineIndex := definitionLine - 2

    while lineIndex <= lastLineIndex {
        lineStart := lineStarts[lineIndex]
        lineLength := lineLengths[lineIndex]

        if IsCodeIntelligenceDocCommentLine(source, lineStart, lineLength) {
            contentStart := GetCodeIntelligenceDocCommentContentStart(source, lineStart, lineLength)
            contentLength := GetCodeIntelligenceDocCommentContentLength(source, lineStart, lineLength, contentStart)
            resultStarts[resultCount] = contentStart
            resultLengths[resultCount] = contentLength
            resultCount = resultCount + 1
        }

        lineIndex = lineIndex + 1
    }

    return resultCount
}

func CodeIntelligenceVariableDeclarationNameChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    CodeIntelligenceVariableDeclarationNamesInto(
        source,
        lineStarts,
        lineLengths,
        queryLines,
        resultStarts,
        resultLengths)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        nameStartColumn := resultStarts[i]
        nameLength := resultLengths[i]
        checksum = checksum + nameStartColumn * 31 + nameLength * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceVariableDeclarationNamesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    return CodeIntelligenceVariableDeclarationNamesFromLinesInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        queryLines,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceVariableDeclarationNameCachedChecksumInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    nameStartsByLine: int[],
    nameLengthsByLine: int[],
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    CodeIntelligenceVariableDeclarationNamesCachedInto(
        source,
        lineStarts,
        lineLengths,
        nameStartsByLine,
        nameLengthsByLine,
        queryLines,
        resultStarts,
        resultLengths)

    checksum := 0
    i := 0

    while i < queryLines.Length {
        nameStartColumn := resultStarts[i]
        nameLength := resultLengths[i]
        checksum = checksum + nameStartColumn * 31 + nameLength * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceVariableDeclarationNamesCachedInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    nameStartsByLine: int[],
    nameLengthsByLine: int[],
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lineCount := BuildCodeIntelligenceLineRangesInto(source, lineStarts, lineLengths)
    BuildCodeIntelligenceVariableDeclarationNameCacheInto(
        source,
        lineStarts,
        lineLengths,
        lineCount,
        nameStartsByLine,
        nameLengthsByLine)

    return CodeIntelligenceVariableDeclarationNamesFromCacheInto(
        lineCount,
        nameStartsByLine,
        nameLengthsByLine,
        queryLines,
        resultStarts,
        resultLengths)
}

func CodeIntelligenceVariableDeclarationNamesFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    foundCount := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        nameStartColumn := -1
        nameLength := 0
        line := queryLines[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            lineStart := lineStarts[lineIndex]
            lineLength := lineLengths[lineIndex]
            assignIndex := FindCodeIntelligenceAssignmentOperator(source, lineStart, lineLength)

            if assignIndex > 0 {
                nameEnd := assignIndex - 1

                while nameEnd >= 0 && IsCodeIntelligenceWhitespace(source[lineStart + nameEnd]) {
                    nameEnd = nameEnd - 1
                }

                if nameEnd >= 0 {
                    nameStart := nameEnd

                    while nameStart >= 0 && IsCodeIntelligenceIdentifierChar(source[lineStart + nameStart]) {
                        nameStart = nameStart - 1
                    }

                    nameStart = nameStart + 1
                    if nameStart <= nameEnd {
                        nameStartColumn = nameStart + 1
                        nameLength = nameEnd - nameStart + 1
                        foundCount = foundCount + 1
                    }
                }
            }
        }

        resultStarts[i] = nameStartColumn
        resultLengths[i] = nameLength
        i = i + 1
    }

    return foundCount
}

func BuildCodeIntelligenceVariableDeclarationNameCacheInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    nameStartsByLine: int[],
    nameLengthsByLine: int[]): int {
    foundCount := 0
    lineIndex := 0

    while lineIndex < lineCount {
        nameStartColumn := 0
        nameLength := 0
        lineStart := lineStarts[lineIndex]
        lineLength := lineLengths[lineIndex]
        assignIndex := FindCodeIntelligenceAssignmentOperator(source, lineStart, lineLength)

        if assignIndex > 0 {
            nameEnd := assignIndex - 1

            while nameEnd >= 0 && IsCodeIntelligenceWhitespace(source[lineStart + nameEnd]) {
                nameEnd = nameEnd - 1
            }

            if nameEnd >= 0 {
                nameStart := nameEnd

                while nameStart >= 0 && IsCodeIntelligenceIdentifierChar(source[lineStart + nameStart]) {
                    nameStart = nameStart - 1
                }

                nameStart = nameStart + 1
                if nameStart <= nameEnd {
                    nameStartColumn = nameStart + 1
                    nameLength = nameEnd - nameStart + 1
                    foundCount = foundCount + 1
                }
            }
        }

        nameStartsByLine[lineIndex] = nameStartColumn
        nameLengthsByLine[lineIndex] = nameLength
        lineIndex = lineIndex + 1
    }

    return foundCount
}

func CodeIntelligenceVariableDeclarationNamesFromCacheInto(
    lineCount: int,
    nameStartsByLine: int[],
    nameLengthsByLine: int[],
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    foundCount := 0
    i := 0
    queryCount := queryLines.Length

    while i < queryCount {
        nameStartColumn := -1
        nameLength := 0
        line := queryLines[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            cachedStartColumn := nameStartsByLine[lineIndex]

            if cachedStartColumn > 0 {
                nameStartColumn = cachedStartColumn
                nameLength = nameLengthsByLine[lineIndex]
                foundCount = foundCount + 1
            }
        }

        resultStarts[i] = nameStartColumn
        resultLengths[i] = nameLength
        i = i + 1
    }

    return foundCount
}

func BuildCodeIntelligenceMemberReceiverCacheInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    receiverStartsBySeparator: int[],
    receiverLengthsBySeparator: int[]): int {
    memberAccessCount := 0
    lineIndex := 0

    while lineIndex < lineCount {
        lineStart := lineStarts[lineIndex]
        lineEnd := lineStart + lineLengths[lineIndex]
        separatorPosition := lineStart

        while separatorPosition < lineEnd {
            if source[separatorPosition] == '.' {
                receiverStartColumn := -1
                receiverLength := 0
                receiverEnd := separatorPosition - 1

                while receiverEnd >= lineStart {
                    ch := source[receiverEnd]
                    if ch == ' ' {
                        receiverEnd = receiverEnd - 1
                        continue
                    }

                    if ch <= '~' {
                        if ch >= '\t' && ch <= '\r' {
                            receiverEnd = receiverEnd - 1
                            continue
                        }

                        break
                    }

                    if Char.IsWhiteSpace(ch) {
                        receiverEnd = receiverEnd - 1
                        continue
                    }

                    break
                }

                if receiverEnd >= lineStart {
                    receiverStart := receiverEnd
                    while receiverStart >= lineStart {
                        ch := source[receiverStart]
                        if ch >= 'a' && ch <= 'z' {
                            receiverStart = receiverStart - 1
                            continue
                        }

                        if ch <= '~' {
                            if ch == '_'
                                || (ch >= 'A' && ch <= 'Z')
                                || (ch >= '0' && ch <= '9') {
                                receiverStart = receiverStart - 1
                                continue
                            }

                            break
                        }

                        if Char.IsLetterOrDigit(ch) {
                            receiverStart = receiverStart - 1
                            continue
                        }

                        break
                    }

                    receiverStart = receiverStart + 1
                    if receiverStart <= receiverEnd {
                        receiverStartColumn = receiverStart - lineStart + 1
                        receiverLength = receiverEnd - receiverStart + 1
                    }
                }

                receiverStartsBySeparator[separatorPosition] = receiverStartColumn
                receiverLengthsBySeparator[separatorPosition] = receiverLength
                memberAccessCount = memberAccessCount + 1
            }

            separatorPosition = separatorPosition + 1
        }

        lineIndex = lineIndex + 1
    }

    return memberAccessCount
}

func BuildCodeIntelligenceLineRangesInto(source: string, starts: int[], lengths: int[]): int {
    sourceLength := source.Length
    position := 0
    lineStart := 0
    count := 0

    while position < sourceLength {
        if source[position] == '\n' {
            starts[count] = lineStart
            lengths[count] = position - lineStart
            count = count + 1
            position = position + 1
            lineStart = position
            continue
        }

        position = position + 1
    }

    starts[count] = lineStart
    lengths[count] = sourceLength - lineStart
    return count + 1
}

func FindCodeIntelligenceAssignmentOperator(source: string, lineStart: int, lineLength: int): int {
    i := 0
    last := lineLength - 1

    while i < last {
        if source[lineStart + i] == ':' && source[lineStart + i + 1] == '=' {
            return i
        }

        i = i + 1
    }

    return -1
}

func FindCodeIntelligenceNameInLine(
    source: string,
    lineStart: int,
    lineLength: int,
    name: string,
    searchStart: int): int {
    nameLength := name.Length

    if nameLength == 0 {
        if searchStart <= lineLength {
            return searchStart
        }

        return -1
    }

    lastStart := lineLength - nameLength
    position := searchStart

    while position <= lastStart {
        if CodeIntelligenceNameMatchesAt(source, lineStart + position, name) {
            return position
        }

        position = position + 1
    }

    return -1
}

func CodeIntelligenceNameMatchesAt(source: string, sourceStart: int, name: string): bool {
    i := 0
    nameLength := name.Length

    while i < nameLength {
        if source[sourceStart + i] != name[i] {
            return false
        }

        i = i + 1
    }

    return true
}

func FindCodeIntelligenceWholeIdentifierInLine(
    source: string,
    lineStart: int,
    lineLength: int,
    name: string,
    searchStart: int): int {
    nameLength := name.Length
    lastStart := lineLength - nameLength
    position := searchStart

    while position <= lastStart {
        if CodeIntelligenceNameMatchesAt(source, lineStart + position, name)
            && IsCodeIntelligenceWholeIdentifierBoundary(source, lineStart, lineLength, position, nameLength) {
            return position
        }

        position = position + 1
    }

    return -1
}

func IsCodeIntelligenceWholeIdentifierBoundary(
    source: string,
    lineStart: int,
    lineLength: int,
    nameStart: int,
    nameLength: int): bool {
    beforeIndex := nameStart - 1
    if beforeIndex >= 0 && IsCodeIntelligenceIdentifierChar(source[lineStart + beforeIndex]) {
        return false
    }

    afterIndex := nameStart + nameLength
    if afterIndex < lineLength && IsCodeIntelligenceIdentifierChar(source[lineStart + afterIndex]) {
        return false
    }

    return true
}

func FindCodeIntelligenceDocCommentStartLine(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    definitionLine: int): int {
    if definitionLine <= 1 || definitionLine > lineCount + 1 {
        return -1
    }

    commentCount := 0
    startLine := -1
    lineIndex := definitionLine - 2

    while lineIndex >= 0 {
        lineStart := lineStarts[lineIndex]
        lineLength := lineLengths[lineIndex]

        if IsCodeIntelligenceDocCommentLine(source, lineStart, lineLength) {
            startLine = lineIndex
            commentCount = commentCount + 1
            lineIndex = lineIndex - 1
            continue
        }

        if commentCount == 0 && IsCodeIntelligenceBlankLine(source, lineStart, lineLength) {
            lineIndex = lineIndex - 1
            continue
        }

        break
    }

    return startLine
}

func IsCodeIntelligenceDocCommentLine(source: string, lineStart: int, lineLength: int): bool {
    trimStart := lineStart
    trimEnd := lineStart + lineLength - 1

    while trimStart <= trimEnd && IsCodeIntelligenceWhitespace(source[trimStart]) {
        trimStart = trimStart + 1
    }

    while trimEnd >= trimStart && IsCodeIntelligenceWhitespace(source[trimEnd]) {
        trimEnd = trimEnd - 1
    }

    return trimStart + 1 <= trimEnd
        && source[trimStart] == '/'
        && source[trimStart + 1] == '/'
}

func IsCodeIntelligenceBlankLine(source: string, lineStart: int, lineLength: int): bool {
    i := 0

    while i < lineLength {
        if !IsCodeIntelligenceWhitespace(source[lineStart + i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func GetCodeIntelligenceDocCommentContentStart(source: string, lineStart: int, lineLength: int): int {
    trimStart := lineStart
    trimEnd := lineStart + lineLength - 1

    while trimStart <= trimEnd && IsCodeIntelligenceWhitespace(source[trimStart]) {
        trimStart = trimStart + 1
    }

    while trimEnd >= trimStart && IsCodeIntelligenceWhitespace(source[trimEnd]) {
        trimEnd = trimEnd - 1
    }

    while trimStart <= trimEnd && source[trimStart] == '/' {
        trimStart = trimStart + 1
    }

    while trimStart <= trimEnd && IsCodeIntelligenceWhitespace(source[trimStart]) {
        trimStart = trimStart + 1
    }

    return trimStart
}

func GetCodeIntelligenceDocCommentContentLength(
    source: string,
    lineStart: int,
    lineLength: int,
    contentStart: int): int {
    contentEnd := lineStart + lineLength - 1

    while contentEnd >= contentStart && IsCodeIntelligenceWhitespace(source[contentEnd]) {
        contentEnd = contentEnd - 1
    }

    if contentEnd < contentStart {
        return 0
    }

    return contentEnd - contentStart + 1
}

func FindNearestCodeIntelligenceIdentifierIndex(
    source: string,
    lineStart: int,
    lineLength: int,
    index: int): int {
    if lineLength == 0 {
        return -1
    }

    if index >= 0 && index < lineLength && IsCodeIntelligenceIdentifierChar(source[lineStart + index]) {
        return index
    }

    distance := 1
    while distance <= 3 {
        left := index - distance
        if left >= 0
            && IsCodeIntelligenceIdentifierChar(source[lineStart + left])
            && IsCodeIntelligenceSnapFriendlyNeighbor(source, lineStart, lineLength, left + 1, index) {
            return left
        }

        right := index + distance
        if right < lineLength
            && IsCodeIntelligenceIdentifierChar(source[lineStart + right])
            && IsCodeIntelligenceSnapFriendlyNeighbor(source, lineStart, lineLength, index, right - 1) {
            return right
        }

        distance = distance + 1
    }

    return -1
}

func IsCodeIntelligenceIdentifierChar(ch: char): bool {
    if ch >= 'a' && ch <= 'z' {
        return true
    }

    if ch <= '~' {
        return ch == '_'
            || (ch >= 'A' && ch <= 'Z')
            || (ch >= '0' && ch <= '9')
    }

    if ch >= 'A' && ch <= 'Z' {
        return true
    }

    if ch >= '0' && ch <= '9' {
        return true
    }

    return Char.IsLetterOrDigit(ch)
}

func IsCodeIntelligenceSnapFriendlyNeighbor(
    source: string,
    lineStart: int,
    lineLength: int,
    start: int,
    end: int): bool {
    if start > end {
        return true
    }

    i := start
    while i <= end {
        if i < 0 || i >= lineLength {
            i = i + 1
            continue
        }

        ch := source[lineStart + i]
        if IsCodeIntelligenceWhitespace(ch) || IsCodeIntelligenceSnapPunctuation(ch) {
            i = i + 1
            continue
        }

        return false
    }

    return true
}

func IsCodeIntelligenceWhitespace(ch: char): bool {
    if ch == ' ' {
        return true
    }

    if ch <= '~' {
        return ch >= '\t' && ch <= '\r'
    }

    return Char.IsWhiteSpace(ch)
}

func IsCodeIntelligenceSnapPunctuation(ch: char): bool {
    return ch == '.'
        || ch == '?'
        || ch == '('
        || ch == ')'
        || ch == '['
        || ch == ']'
        || ch == '{'
        || ch == '}'
        || ch == ','
        || ch == ';'
        || ch == ':'
}

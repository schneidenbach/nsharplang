import System

// PARITY CORPUS (Arc M1): checksum fixtures extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/IdentifierSpans.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

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

func CodeIntelligenceMemberReceiversFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    memberStartColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    queries := new CodeIntelligenceMemberQueryTable { Lines: queryLines, MemberStartColumns: memberStartColumns }
    result := new CodeIntelligenceSpanOutputTable { Starts: resultStarts, Lengths: resultLengths }
    return CodeIntelligenceMemberReceiversFromLinesCore(source, ref lines, ref queries, ref result)
}

func CodeIntelligenceMemberReceiversFromLinesCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    queries: &CodeIntelligenceMemberQueryTable,
    result: &CodeIntelligenceSpanOutputTable): int {
    foundCount := 0
    i := 0
    queryCount := queries.Lines.Length

    while i < queryCount {
        receiverStartColumn := -1
        receiverLength := 0
        line := queries.Lines[i]
        memberStartColumn := queries.MemberStartColumns[i]

        if line > 0 && line <= lines.Count {
            lineIndex := line - 1
            lineLength := lines.Lengths[lineIndex]
            memberStartIndex := memberStartColumn - 1

            if memberStartIndex > 0 && memberStartIndex <= lineLength {
                lineStart := lines.Starts[lineIndex]
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

        result.Starts[i] = receiverStartColumn
        result.Lengths[i] = receiverLength
        if receiverStartColumn >= 0 {
            foundCount = foundCount + 1
        }

        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceVariableDeclarationNamesFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    queries := new CodeIntelligenceLineQueryTable { Lines: queryLines }
    result := new CodeIntelligenceSpanOutputTable { Starts: resultStarts, Lengths: resultLengths }
    return CodeIntelligenceVariableDeclarationNamesFromLinesCore(source, ref lines, ref queries, ref result)
}

func CodeIntelligenceVariableDeclarationNamesFromLinesCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    queries: &CodeIntelligenceLineQueryTable,
    result: &CodeIntelligenceSpanOutputTable): int {
    foundCount := 0
    i := 0
    queryCount := queries.Lines.Length

    while i < queryCount {
        nameStartColumn := -1
        nameLength := 0
        line := queries.Lines[i]

        if line > 0 && line <= lines.Count {
            lineIndex := line - 1
            lineStart := lines.Starts[lineIndex]
            lineLength := lines.Lengths[lineIndex]
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

        result.Starts[i] = nameStartColumn
        result.Lengths[i] = nameLength
        i = i + 1
    }

    return foundCount
}

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
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }

    while i < queryCount {
        definitionLine := queryLines[i]
        startLine := FindCodeIntelligenceDocCommentStartLineCore(source, ref lines, definitionLine)

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

func CodeIntelligenceVariableDeclarationNameCachedChecksumInto(
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

    CodeIntelligenceVariableDeclarationNamesFromCacheInto(
        lineCount,
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

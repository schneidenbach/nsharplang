// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/IdentifierSpans.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

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

import System

struct CodeIntelligenceLineRangeTable {
    Starts: int[]
    Lengths: int[]
    Count: int
}

struct CodeIntelligencePositionQueryTable {
    Lines: int[]
    Columns: int[]
}

struct CodeIntelligenceLineQueryTable {
    Lines: int[]
}

struct CodeIntelligenceSpanOutputTable {
    Starts: int[]
    Lengths: int[]
}

struct CodeIntelligenceDeclarationMatchQueryTable {
    Lines: int[]
    DeclarationColumns: int[]
    Names: string[]
    SelectedStartColumns: int[]
    SelectedEndColumns: int[]
}

struct CodeIntelligenceMatchOutputTable {
    Matches: int[]
}

struct CodeIntelligenceIdentifierNameQueryTable {
    Lines: int[]
    Names: string[]
    FallbackColumns: int[]
}

struct CodeIntelligenceColumnOutputTable {
    Columns: int[]
}

struct CodeIntelligenceMemberQueryTable {
    Lines: int[]
    MemberStartColumns: int[]
}

struct CodeIntelligenceSeparatorSpanTable {
    StartsBySeparator: int[]
    LengthsBySeparator: int[]
}

struct CodeIntelligenceLineNameTable {
    StartsByLine: int[]
    LengthsByLine: int[]
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
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    queries := new CodeIntelligencePositionQueryTable { Lines: queryLines, Columns: queryColumns }
    result := new CodeIntelligenceSpanOutputTable { Starts: resultStarts, Lengths: resultLengths }
    return CodeIntelligenceIdentifierSpansFromLinesCore(source, ref lines, ref queries, ref result)
}

func CodeIntelligenceIdentifierSpansFromLinesCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    queries: &CodeIntelligencePositionQueryTable,
    result: &CodeIntelligenceSpanOutputTable): int {
    foundCount := 0
    i := 0

    while i < queries.Lines.Length {
        spanStart := -1
        spanLength := 0
        line := queries.Lines[i]
        column := queries.Columns[i]

        if line > 0 && line <= lines.Count {
            lineIndex := line - 1
            lineLength := lines.Lengths[lineIndex]

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
                    lines.Starts[lineIndex],
                    lineLength,
                    index)

                if nearest >= 0 {
                    start := nearest
                    lineStart := lines.Starts[lineIndex]
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

        result.Starts[i] = spanStart
        result.Lengths[i] = spanLength
        if spanStart >= 0 {
            foundCount = foundCount + 1
        }

        i = i + 1
    }

    return foundCount
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
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    queries := new CodeIntelligencePositionQueryTable { Lines: queryLines, Columns: queryColumns }
    result := new CodeIntelligenceSpanOutputTable { Starts: resultStarts, Lengths: resultLengths }
    return CodeIntelligenceEditorIdentifierSpansFromLinesCore(source, ref lines, ref queries, ref result)
}

func CodeIntelligenceEditorIdentifierSpansFromLinesCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    queries: &CodeIntelligencePositionQueryTable,
    result: &CodeIntelligenceSpanOutputTable): int {
    foundCount := 0
    i := 0

    while i < queries.Lines.Length {
        spanStart := -1
        spanLength := 0
        line := queries.Lines[i]
        column := queries.Columns[i]

        if line > 0 && line <= lines.Count && column > 0 {
            lineIndex := line - 1
            lineLength := lines.Lengths[lineIndex]

            if lineLength > 0 {
                character := column - 1
                lineStart := lines.Starts[lineIndex]

                if character >= lineLength {
                    character = lineLength - 1
                    if !IsCodeIntelligenceIdentifierChar(source[lineStart + character]) {
                        result.Starts[i] = spanStart
                        result.Lengths[i] = spanLength
                        i = i + 1
                        continue
                    }
                } else {
                    if !IsCodeIntelligenceIdentifierChar(source[lineStart + character]) {
                        result.Starts[i] = spanStart
                        result.Lengths[i] = spanLength
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

        result.Starts[i] = spanStart
        result.Lengths[i] = spanLength
        if spanStart >= 0 {
            foundCount = foundCount + 1
        }

        i = i + 1
    }

    return foundCount
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
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    queries := new CodeIntelligenceDeclarationMatchQueryTable {
        Lines: queryLines,
        DeclarationColumns: declarationColumns,
        Names: declarationNames,
        SelectedStartColumns: selectedStartColumns,
        SelectedEndColumns: selectedEndColumns
    }
    result := new CodeIntelligenceMatchOutputTable { Matches: resultMatches }
    return CodeIntelligenceDeclarationNameMatchesFromLinesCore(source, ref lines, ref queries, ref result)
}

func CodeIntelligenceDeclarationNameMatchesFromLinesCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    queries: &CodeIntelligenceDeclarationMatchQueryTable,
    result: &CodeIntelligenceMatchOutputTable): int {
    matchCount := 0
    i := 0
    queryCount := queries.Lines.Length

    while i < queryCount {
        matched := 0
        line := queries.Lines[i]

        if line > 0 && line <= lines.Count {
            lineIndex := line - 1
            lineStart := lines.Starts[lineIndex]
            lineLength := lines.Lengths[lineIndex]
            declarationName := queries.Names[i]
            searchStart := queries.DeclarationColumns[i] - 1

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
                if queries.SelectedStartColumns[i] == nameStartColumn && queries.SelectedEndColumns[i] == nameEndColumn {
                    matched = 1
                    matchCount = matchCount + 1
                }
            }
        }

        result.Matches[i] = matched
        i = i + 1
    }

    return matchCount
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
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    queries := new CodeIntelligenceIdentifierNameQueryTable { Lines: queryLines, Names: declarationNames, FallbackColumns: fallbackColumns }
    result := new CodeIntelligenceColumnOutputTable { Columns: resultColumns }
    return CodeIntelligenceIdentifierNameColumnsFromLinesCore(source, ref lines, ref queries, ref result)
}

func CodeIntelligenceIdentifierNameColumnsFromLinesCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    queries: &CodeIntelligenceIdentifierNameQueryTable,
    result: &CodeIntelligenceColumnOutputTable): int {
    foundCount := 0
    i := 0
    queryCount := queries.Lines.Length

    while i < queryCount {
        column := queries.FallbackColumns[i]
        line := queries.Lines[i]
        declarationName := queries.Names[i]

        if line > 0 && line <= lines.Count && declarationName.Length > 0 {
            lineIndex := line - 1
            lineStart := lines.Starts[lineIndex]
            lineLength := lines.Lengths[lineIndex]

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

        result.Columns[i] = column
        i = i + 1
    }

    return foundCount
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
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    cache := new CodeIntelligenceSeparatorSpanTable { StartsBySeparator: receiverStartsBySeparator, LengthsBySeparator: receiverLengthsBySeparator }
    queries := new CodeIntelligenceMemberQueryTable { Lines: queryLines, MemberStartColumns: memberStartColumns }
    result := new CodeIntelligenceSpanOutputTable { Starts: resultStarts, Lengths: resultLengths }
    return CodeIntelligenceMemberReceiversFromCacheCore(source, ref lines, ref cache, ref queries, ref result)
}

func CodeIntelligenceMemberReceiversFromCacheCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    cache: &CodeIntelligenceSeparatorSpanTable,
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
                separatorPosition := lineStart + memberStartIndex - 1

                if source[separatorPosition] == '.' {
                    cachedStartColumn := cache.StartsBySeparator[separatorPosition]
                    if cachedStartColumn != 0 {
                        receiverStartColumn = cachedStartColumn
                        receiverLength = cache.LengthsBySeparator[separatorPosition]
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

func CodeIntelligenceSourceContextsFromLinesInto(
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
    return CodeIntelligenceSourceContextsFromLinesCore(source, ref lines, ref queries, ref result)
}

func CodeIntelligenceSourceContextsFromLinesCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    queries: &CodeIntelligenceLineQueryTable,
    result: &CodeIntelligenceSpanOutputTable): int {
    foundCount := 0
    i := 0
    queryCount := queries.Lines.Length

    while i < queryCount {
        contextStart := -1
        contextLength := 0
        line := queries.Lines[i]

        if line > 0 && line <= lines.Count {
            lineIndex := line - 1
            trimStart := lines.Starts[lineIndex]
            trimEnd := trimStart + lines.Lengths[lineIndex] - 1

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

        result.Starts[i] = contextStart
        result.Lengths[i] = contextLength
        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceSourceLinesFromLinesInto(
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    queries := new CodeIntelligenceLineQueryTable { Lines: queryLines }
    result := new CodeIntelligenceSpanOutputTable { Starts: resultStarts, Lengths: resultLengths }
    return CodeIntelligenceSourceLinesFromLinesCore(ref lines, ref queries, ref result)
}

func CodeIntelligenceSourceLinesFromLinesCore(
    lines: &CodeIntelligenceLineRangeTable,
    queries: &CodeIntelligenceLineQueryTable,
    result: &CodeIntelligenceSpanOutputTable): int {
    foundCount := 0
    i := 0
    queryCount := queries.Lines.Length

    while i < queryCount {
        lineStart := -1
        lineLength := 0
        line := queries.Lines[i]

        if line > 0 && line <= lines.Count {
            lineIndex := line - 1
            lineStart = lines.Starts[lineIndex]
            lineLength = lines.Lengths[lineIndex]
            foundCount = foundCount + 1
        }

        result.Starts[i] = lineStart
        result.Lengths[i] = lineLength
        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceCompletionPrefixesFromLinesInto(
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    queryLines: int[],
    queryColumns: int[],
    resultStarts: int[],
    resultLengths: int[]): int {
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    queries := new CodeIntelligencePositionQueryTable { Lines: queryLines, Columns: queryColumns }
    result := new CodeIntelligenceSpanOutputTable { Starts: resultStarts, Lengths: resultLengths }
    return CodeIntelligenceCompletionPrefixesFromLinesCore(ref lines, ref queries, ref result)
}

func CodeIntelligenceCompletionPrefixesFromLinesCore(
    lines: &CodeIntelligenceLineRangeTable,
    queries: &CodeIntelligencePositionQueryTable,
    result: &CodeIntelligenceSpanOutputTable): int {
    foundCount := 0
    i := 0
    queryCount := queries.Lines.Length

    while i < queryCount {
        prefixStart := -1
        prefixLength := 0
        line := queries.Lines[i]
        column := queries.Columns[i]

        if line > 0 && line <= lines.Count {
            lineIndex := line - 1
            prefixStart = lines.Starts[lineIndex]
            prefixLength = lines.Lengths[lineIndex]

            if column > 0 && column <= prefixLength {
                prefixLength = column
            }

            foundCount = foundCount + 1
        }

        result.Starts[i] = prefixStart
        result.Lengths[i] = prefixLength
        i = i + 1
    }

    return foundCount
}

func CodeIntelligenceDocCommentLinesFromLinesInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    definitionLine: int,
    resultStarts: int[],
    resultLengths: int[]): int {
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    result := new CodeIntelligenceSpanOutputTable { Starts: resultStarts, Lengths: resultLengths }
    return CodeIntelligenceDocCommentLinesFromLinesCore(source, ref lines, definitionLine, ref result)
}

func CodeIntelligenceDocCommentLinesFromLinesCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    definitionLine: int,
    result: &CodeIntelligenceSpanOutputTable): int {
    startLine := FindCodeIntelligenceDocCommentStartLineCore(source, ref lines, definitionLine)

    if startLine < 0 {
        return 0
    }

    resultCount := 0
    lineIndex := startLine
    lastLineIndex := definitionLine - 2

    while lineIndex <= lastLineIndex {
        lineStart := lines.Starts[lineIndex]
        lineLength := lines.Lengths[lineIndex]

        if IsCodeIntelligenceDocCommentLine(source, lineStart, lineLength) {
            contentStart := GetCodeIntelligenceDocCommentContentStart(source, lineStart, lineLength)
            contentLength := GetCodeIntelligenceDocCommentContentLength(source, lineStart, lineLength, contentStart)
            result.Starts[resultCount] = contentStart
            result.Lengths[resultCount] = contentLength
            resultCount = resultCount + 1
        }

        lineIndex = lineIndex + 1
    }

    return resultCount
}

func BuildCodeIntelligenceVariableDeclarationNameCacheInto(
    source: string,
    lineStarts: int[],
    lineLengths: int[],
    lineCount: int,
    nameStartsByLine: int[],
    nameLengthsByLine: int[]): int {
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    cache := new CodeIntelligenceLineNameTable { StartsByLine: nameStartsByLine, LengthsByLine: nameLengthsByLine }
    return BuildCodeIntelligenceVariableDeclarationNameCacheCore(source, ref lines, ref cache)
}

func BuildCodeIntelligenceVariableDeclarationNameCacheCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    cache: &CodeIntelligenceLineNameTable): int {
    foundCount := 0
    lineIndex := 0

    while lineIndex < lines.Count {
        nameStartColumn := 0
        nameLength := 0
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

        cache.StartsByLine[lineIndex] = nameStartColumn
        cache.LengthsByLine[lineIndex] = nameLength
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
    cache := new CodeIntelligenceLineNameTable { StartsByLine: nameStartsByLine, LengthsByLine: nameLengthsByLine }
    queries := new CodeIntelligenceLineQueryTable { Lines: queryLines }
    result := new CodeIntelligenceSpanOutputTable { Starts: resultStarts, Lengths: resultLengths }
    return CodeIntelligenceVariableDeclarationNamesFromCacheCore(lineCount, ref cache, ref queries, ref result)
}

func CodeIntelligenceVariableDeclarationNamesFromCacheCore(
    lineCount: int,
    cache: &CodeIntelligenceLineNameTable,
    queries: &CodeIntelligenceLineQueryTable,
    result: &CodeIntelligenceSpanOutputTable): int {
    foundCount := 0
    i := 0
    queryCount := queries.Lines.Length

    while i < queryCount {
        nameStartColumn := -1
        nameLength := 0
        line := queries.Lines[i]

        if line > 0 && line <= lineCount {
            lineIndex := line - 1
            cachedStartColumn := cache.StartsByLine[lineIndex]

            if cachedStartColumn > 0 {
                nameStartColumn = cachedStartColumn
                nameLength = cache.LengthsByLine[lineIndex]
                foundCount = foundCount + 1
            }
        }

        result.Starts[i] = nameStartColumn
        result.Lengths[i] = nameLength
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
    lines := new CodeIntelligenceLineRangeTable { Starts: lineStarts, Lengths: lineLengths, Count: lineCount }
    cache := new CodeIntelligenceSeparatorSpanTable { StartsBySeparator: receiverStartsBySeparator, LengthsBySeparator: receiverLengthsBySeparator }
    return BuildCodeIntelligenceMemberReceiverCacheCore(source, ref lines, ref cache)
}

func BuildCodeIntelligenceMemberReceiverCacheCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    cache: &CodeIntelligenceSeparatorSpanTable): int {
    memberAccessCount := 0
    lineIndex := 0

    while lineIndex < lines.Count {
        lineStart := lines.Starts[lineIndex]
        lineEnd := lineStart + lines.Lengths[lineIndex]
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

                cache.StartsBySeparator[separatorPosition] = receiverStartColumn
                cache.LengthsBySeparator[separatorPosition] = receiverLength
                memberAccessCount = memberAccessCount + 1
            }

            separatorPosition = separatorPosition + 1
        }

        lineIndex = lineIndex + 1
    }

    return memberAccessCount
}

func BuildCodeIntelligenceLineRangesInto(source: string, starts: int[], lengths: int[]): int {
    lines := new CodeIntelligenceLineRangeTable { Starts: starts, Lengths: lengths, Count: 0 }
    return BuildCodeIntelligenceLineRangesCore(source, ref lines)
}

func BuildCodeIntelligenceLineRangesCore(source: string, lines: &CodeIntelligenceLineRangeTable): int {
    sourceLength := source.Length
    position := 0
    lineStart := 0
    count := 0

    while position < sourceLength {
        if source[position] == '\r' {
            if position + 1 < sourceLength && source[position + 1] == '\n' {
                position = position + 1
                continue
            }

            lines.Starts[count] = lineStart
            lines.Lengths[count] = position - lineStart
            count = count + 1
            position = position + 1
            lineStart = position
            continue
        }

        if source[position] == '\n' {
            lines.Starts[count] = lineStart
            lines.Lengths[count] = position - lineStart
            count = count + 1
            position = position + 1
            lineStart = position
            continue
        }

        position = position + 1
    }

    lines.Starts[count] = lineStart
    lines.Lengths[count] = sourceLength - lineStart
    lines.Count = count + 1
    return lines.Count
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

func FindCodeIntelligenceDocCommentStartLineCore(
    source: string,
    lines: &CodeIntelligenceLineRangeTable,
    definitionLine: int): int {
    if definitionLine <= 1 || definitionLine > lines.Count + 1 {
        return -1
    }

    commentCount := 0
    startLine := -1
    lineIndex := definitionLine - 2

    while lineIndex >= 0 {
        lineStart := lines.Starts[lineIndex]
        lineLength := lines.Lengths[lineIndex]

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

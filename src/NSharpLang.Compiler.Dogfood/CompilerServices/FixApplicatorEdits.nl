import System.Text

struct FixApplicatorEditTable {
    StartLines: int[]
    StartColumns: int[]
    EndLines: int[]
    EndColumns: int[]
    NewTexts: string[]
    Count: int
}

struct FixApplicatorLineTable {
    Lines: string[]
    Count: int
}

func FixValidateOrderedTextEdits(
    source: string,
    hasSource: int,
    startLines: int[],
    startColumns: int[],
    endLines: int[],
    endColumns: int[],
    newTexts: string[],
    count: int,
    errorInfo: int[]): int {
    edits := new FixApplicatorEditTable {
        StartLines: startLines,
        StartColumns: startColumns,
        EndLines: endLines,
        EndColumns: endColumns,
        NewTexts: newTexts,
        Count: count
    }

    return FixValidateOrderedTextEditsCore(source, hasSource, ref edits, errorInfo)
}

func FixApplyOrderedTextEdits(
    source: string,
    startLines: int[],
    startColumns: int[],
    endLines: int[],
    endColumns: int[],
    newTexts: string[],
    count: int,
    output: string[]): int {
    if output.Length < 1 {
        return -1
    }

    edits := new FixApplicatorEditTable {
        StartLines: startLines,
        StartColumns: startColumns,
        EndLines: endLines,
        EndColumns: endColumns,
        NewTexts: newTexts,
        Count: count
    }

    if !FixApplicatorEditTableShapeIsValid(ref edits) {
        return -1
    }

    capacity := FixApplicatorLineCapacity(source, ref edits)
    lines := new FixApplicatorLineTable { Lines: new string[](capacity), Count: 0 }
    if FixApplicatorSplitLogicalLinesInto(source, ref lines) < 0 {
        return -1
    }

    i := 0
    while i < count {
        if FixApplicatorApplySingleEdit(ref lines, ref edits, i) < 0 {
            return -1
        }

        i = i + 1
    }

    output[0] = FixApplicatorJoinLines(ref lines)
    return 0
}

func FixValidateOrderedTextEditsCore(
    source: string,
    hasSource: int,
    edits: &FixApplicatorEditTable,
    errorInfo: int[]): int {
    if errorInfo.Length < 2 || !FixApplicatorEditTableShapeIsValid(ref edits) {
        return -1
    }

    errorInfo[0] = -1
    errorInfo[1] = -1

    i := 0
    while i < edits.Count {
        if edits.StartLines[i] < 1 || edits.EndLines[i] < 1 || edits.StartColumns[i] < 0 || edits.EndColumns[i] < 0 {
            errorInfo[0] = i
            return 1
        }

        endBeforeStart := edits.EndLines[i] < edits.StartLines[i]
            || (edits.EndLines[i] == edits.StartLines[i] && edits.EndColumns[i] < edits.StartColumns[i])
        if endBeforeStart {
            errorInfo[0] = i
            return 2
        }

        i = i + 1
    }

    i = 0
    while i < edits.Count - 1 {
        highIndex := i
        lowIndex := i + 1
        overlaps := edits.StartLines[highIndex] < edits.EndLines[lowIndex]
            || (edits.StartLines[highIndex] == edits.EndLines[lowIndex]
                && edits.StartColumns[highIndex] < edits.EndColumns[lowIndex])

        if overlaps {
            errorInfo[0] = lowIndex
            errorInfo[1] = highIndex
            return 3
        }

        i = i + 1
    }

    if hasSource == 0 {
        return 0
    }

    lineCount := FixApplicatorCountLogicalLines(source)
    lineLengths := new int[](lineCount)
    FixApplicatorBuildLineLengthsInto(source, lineLengths)
    eofLine := lineCount + 1

    i = 0
    while i < edits.Count {
        isEofInsert := edits.StartLines[i] == eofLine
            && edits.EndLines[i] == eofLine
            && edits.StartColumns[i] == 0
            && edits.EndColumns[i] == 0
        if isEofInsert {
            i = i + 1
            continue
        }

        isLastLineWholeLineDeletion := edits.NewTexts[i].Length == 0
            && edits.EndLines[i] == eofLine
            && edits.EndColumns[i] == 0
            && edits.StartLines[i] == lineCount
            && edits.StartColumns[i] == 0
        if isLastLineWholeLineDeletion {
            i = i + 1
            continue
        }

        if !FixApplicatorPositionIsInDocument(lineLengths, lineCount, edits.StartLines[i], edits.StartColumns[i])
            || !FixApplicatorPositionIsInDocument(lineLengths, lineCount, edits.EndLines[i], edits.EndColumns[i]) {
            errorInfo[0] = i
            return 4
        }

        i = i + 1
    }

    return 0
}

func FixApplicatorEditTableShapeIsValid(edits: &FixApplicatorEditTable): bool {
    if edits.Count < 0 {
        return false
    }

    return edits.Count <= edits.StartLines.Length
        && edits.Count <= edits.StartColumns.Length
        && edits.Count <= edits.EndLines.Length
        && edits.Count <= edits.EndColumns.Length
        && edits.Count <= edits.NewTexts.Length
}

func FixApplicatorPositionIsInDocument(lineLengths: int[], lineCount: int, line: int, column: int): bool {
    if line < 1 || line > lineCount {
        return false
    }

    return column <= lineLengths[line - 1]
}

func FixApplicatorLineCapacity(source: string, edits: &FixApplicatorEditTable): int {
    capacity := FixApplicatorCountLogicalLines(source) + edits.Count + 1
    i := 0
    while i < edits.Count {
        if edits.NewTexts[i].Length > 0 {
            capacity = capacity + FixApplicatorCountLogicalLines(edits.NewTexts[i]) + 1
        }

        i = i + 1
    }

    return capacity
}

func FixApplicatorCountLogicalLines(source: string): int {
    count := 1
    position := 0
    sourceLength := source.Length

    while position < sourceLength {
        if source[position] == '\r' {
            count = count + 1
            if position + 1 < sourceLength && source[position + 1] == '\n' {
                position = position + 2
                continue
            }

            position = position + 1
            continue
        }

        if source[position] == '\n' {
            count = count + 1
        }

        position = position + 1
    }

    return count
}

func FixApplicatorBuildLineLengthsInto(source: string, lineLengths: int[]): int {
    position := 0
    lineStart := 0
    lineIndex := 0
    sourceLength := source.Length

    while position < sourceLength {
        if source[position] == '\r' {
            lineLengths[lineIndex] = position - lineStart
            lineIndex = lineIndex + 1

            if position + 1 < sourceLength && source[position + 1] == '\n' {
                position = position + 2
                lineStart = position
                continue
            }

            position = position + 1
            lineStart = position
            continue
        }

        if source[position] == '\n' {
            lineLengths[lineIndex] = position - lineStart
            lineIndex = lineIndex + 1
            position = position + 1
            lineStart = position
            continue
        }

        position = position + 1
    }

    lineLengths[lineIndex] = sourceLength - lineStart
    return lineIndex + 1
}

func FixApplicatorSplitLogicalLinesInto(source: string, lines: &FixApplicatorLineTable): int {
    position := 0
    lineStart := 0
    lineIndex := 0
    sourceLength := source.Length

    while position < sourceLength {
        if source[position] == '\r' {
            if lineIndex >= lines.Lines.Length {
                return -1
            }

            lines.Lines[lineIndex] = source.Substring(lineStart, position - lineStart)
            lineIndex = lineIndex + 1

            if position + 1 < sourceLength && source[position + 1] == '\n' {
                position = position + 2
                lineStart = position
                continue
            }

            position = position + 1
            lineStart = position
            continue
        }

        if source[position] == '\n' {
            if lineIndex >= lines.Lines.Length {
                return -1
            }

            lines.Lines[lineIndex] = source.Substring(lineStart, position - lineStart)
            lineIndex = lineIndex + 1
            position = position + 1
            lineStart = position
            continue
        }

        position = position + 1
    }

    if lineIndex >= lines.Lines.Length {
        return -1
    }

    lines.Lines[lineIndex] = source.Substring(lineStart, sourceLength - lineStart)
    lines.Count = lineIndex + 1
    return lines.Count
}

func FixApplicatorApplySingleEdit(lines: &FixApplicatorLineTable, edits: &FixApplicatorEditTable, index: int): int {
    startLine := edits.StartLines[index] - 1
    endLine := edits.EndLines[index] - 1
    startColumn := edits.StartColumns[index]
    endColumn := edits.EndColumns[index]
    newText := edits.NewTexts[index]

    if startLine == endLine && startColumn == endColumn && newText.Length == 0 {
        return 0
    }

    if startLine >= lines.Count {
        if newText.Length > 0 {
            newLines := new FixApplicatorLineTable {
                Lines: new string[](FixApplicatorCountLogicalLines(newText)),
                Count: 0
            }
            if FixApplicatorSplitLogicalLinesInto(newText, ref newLines) < 0 {
                return -1
            }

            return FixApplicatorInsertLines(ref lines, lines.Count, ref newLines)
        }

        return 0
    }

    if newText.Length == 0 && startColumn == 0 && endColumn == 0 && endLine > startLine {
        removeCount := endLine - startLine
        remainingLines := lines.Count - startLine
        if removeCount > remainingLines {
            removeCount = remainingLines
        }

        FixApplicatorRemoveLines(ref lines, startLine, removeCount)
        return 0
    }

    if startLine == endLine && startColumn == endColumn {
        if startLine < lines.Count {
            line := lines.Lines[startLine]
            column := FixApplicatorMinInt(startColumn, line.Length)
            lines.Lines[startLine] = line.Substring(0, column) + newText + line.Substring(column)
        } else {
            if lines.Count >= lines.Lines.Length {
                return -1
            }

            lines.Lines[lines.Count] = newText
            lines.Count = lines.Count + 1
        }

        if newText.IndexOf('\n') >= 0 {
            combined := lines.Lines[startLine]
            FixApplicatorRemoveLines(ref lines, startLine, 1)
            splitLines := new FixApplicatorLineTable {
                Lines: new string[](FixApplicatorCountLogicalLines(combined)),
                Count: 0
            }
            if FixApplicatorSplitLogicalLinesInto(combined, ref splitLines) < 0 {
                return -1
            }

            return FixApplicatorInsertLines(ref lines, startLine, ref splitLines)
        }

        return 0
    }

    startLineText := ""
    if startLine < lines.Count {
        startLineText = lines.Lines[startLine]
    }

    endLineText := ""
    if endLine < lines.Count {
        endLineText = lines.Lines[endLine]
    }

    prefix := startLineText
    if startColumn <= startLineText.Length {
        prefix = startLineText.Substring(0, startColumn)
    }

    suffix := ""
    if endColumn <= endLineText.Length {
        suffix = endLineText.Substring(endColumn)
    }

    replacement := prefix + newText + suffix
    removeCount := endLine - startLine + 1
    remainingLines := lines.Count - startLine
    if removeCount > remainingLines {
        removeCount = remainingLines
    }

    FixApplicatorRemoveLines(ref lines, startLine, removeCount)
    replacementLines := new FixApplicatorLineTable {
        Lines: new string[](FixApplicatorCountLogicalLines(replacement)),
        Count: 0
    }
    if FixApplicatorSplitLogicalLinesInto(replacement, ref replacementLines) < 0 {
        return -1
    }

    return FixApplicatorInsertLines(ref lines, startLine, ref replacementLines)
}

func FixApplicatorRemoveLines(lines: &FixApplicatorLineTable, startIndex: int, removeCount: int) {
    if removeCount <= 0 {
        return
    }

    readIndex := startIndex + removeCount
    writeIndex := startIndex
    while readIndex < lines.Count {
        lines.Lines[writeIndex] = lines.Lines[readIndex]
        readIndex = readIndex + 1
        writeIndex = writeIndex + 1
    }

    lines.Count = lines.Count - removeCount
}

func FixApplicatorInsertLines(lines: &FixApplicatorLineTable, startIndex: int, insertedLines: &FixApplicatorLineTable): int {
    if insertedLines.Count <= 0 {
        return 0
    }

    if startIndex < 0 || startIndex > lines.Count || lines.Count + insertedLines.Count > lines.Lines.Length {
        return -1
    }

    moveIndex := lines.Count - 1
    while moveIndex >= startIndex {
        lines.Lines[moveIndex + insertedLines.Count] = lines.Lines[moveIndex]
        moveIndex = moveIndex - 1
    }

    i := 0
    while i < insertedLines.Count {
        lines.Lines[startIndex + i] = insertedLines.Lines[i]
        i = i + 1
    }

    lines.Count = lines.Count + insertedLines.Count
    return 0
}

func FixApplicatorJoinLines(lines: &FixApplicatorLineTable): string {
    builder := new StringBuilder()
    i := 0
    while i < lines.Count {
        if i > 0 {
            builder.Append('\n')
        }

        builder.Append(lines.Lines[i])
        i = i + 1
    }

    return builder.ToString()
}

func FixApplicatorMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

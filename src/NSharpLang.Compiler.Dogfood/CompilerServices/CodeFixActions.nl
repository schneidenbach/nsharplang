import System

func CodeFixUnnecessaryNullCheckEditInto(source: string, line: int, editInfo: int[], replacementText: string[]): int {
    if editInfo.Length < 2 || replacementText.Length < 1 {
        return -1
    }

    editInfo[0] = 0
    editInfo[1] = 0
    replacementText[0] = ""

    if line <= 0 {
        return 0
    }

    lineCount := FixApplicatorCountLogicalLines(source)
    if line > lineCount {
        return 0
    }

    lines := new FixApplicatorLineTable { Lines: new string[](lineCount), Count: 0 }
    if FixApplicatorSplitLogicalLinesInto(source, ref lines) < 0 {
        return -1
    }

    sourceLine := lines.Lines[line - 1]
    notNullPattern := "!= null"
    nullPattern := "== null"

    patternStart := sourceLine.IndexOf(notNullPattern, StringComparison.Ordinal)
    replacement := "true"
    if patternStart < 0 {
        patternStart = sourceLine.IndexOf(nullPattern, StringComparison.Ordinal)
        replacement = "false"
    }

    if patternStart < 0 {
        return 0
    }

    rangeInfo := new int[](2)
    if CodeFixTryFindStatementConditionRangeInto(sourceLine, patternStart, rangeInfo) == 0 {
        return 0
    }

    editInfo[0] = rangeInfo[0]
    editInfo[1] = rangeInfo[1]
    replacementText[0] = replacement
    return 1
}

func CodeFixTryFindStatementConditionRangeInto(sourceLine: string, patternStart: int, rangeInfo: int[]): int {
    if rangeInfo.Length < 2 {
        return -1
    }

    rangeInfo[0] = 0
    rangeInfo[1] = 0

    ifIndex := sourceLine.IndexOf("if ", StringComparison.Ordinal)
    whileIndex := sourceLine.IndexOf("while ", StringComparison.Ordinal)

    keywordIndex := -1
    keywordLength := 2
    if ifIndex >= 0 && ifIndex < patternStart {
        keywordIndex = ifIndex
    }

    if whileIndex >= 0 && whileIndex < patternStart && (keywordIndex < 0 || whileIndex > keywordIndex) {
        keywordIndex = whileIndex
        keywordLength = 5
    }

    if keywordIndex < 0 {
        return 0
    }

    conditionStart := keywordIndex + keywordLength
    while conditionStart < sourceLine.Length && CodeFixIsWhitespace(sourceLine[conditionStart]) {
        conditionStart = conditionStart + 1
    }

    braceIndex := CodeFixIndexOfCharFrom(sourceLine, '{', patternStart)
    conditionEnd := sourceLine.Length
    if braceIndex >= 0 {
        conditionEnd = braceIndex
    }

    while conditionEnd > conditionStart && CodeFixIsWhitespace(sourceLine[conditionEnd - 1]) {
        conditionEnd = conditionEnd - 1
    }

    if conditionStart >= conditionEnd {
        return 0
    }

    rangeInfo[0] = conditionStart
    rangeInfo[1] = conditionEnd
    return 1
}

func CodeFixIndexOfCharFrom(text: string, ch: char, start: int): int {
    index := start
    if index < 0 {
        index = 0
    }

    while index < text.Length {
        if text[index] == ch {
            return index
        }

        index = index + 1
    }

    return -1
}

func CodeFixIsWhitespace(ch: char): bool {
    if ch == ' ' {
        return true
    }

    if ch <= '~' {
        return ch >= '\t' && ch <= '\r'
    }

    return Char.IsWhiteSpace(ch)
}

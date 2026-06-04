import System
import System.Text

func DiagnosticSeveritySummaryInto(severities: string[], count: int, resultCounts: int[]): int {
    if resultCounts.Length < 3 {
        return 0
    }

    if count > severities.Length {
        count = severities.Length
    }

    errors := 0
    warnings := 0
    info := 0
    i := 0

    while i < count {
        severity := severities[i]
        if severity == "error" {
            errors = errors + 1
        } else if severity == "warning" {
            warnings = warnings + 1
        } else if severity == "info" {
            info = info + 1
        }

        i = i + 1
    }

    resultCounts[0] = errors
    resultCounts[1] = warnings
    resultCounts[2] = info
    return count
}

func DiagnosticSeveritySummaryChecksumInto(severities: string[], count: int, resultCounts: int[]): int {
    count = DiagnosticSeveritySummaryInto(severities, count, resultCounts)
    if resultCounts.Length < 3 {
        return count
    }

    return count + resultCounts[0] * 31 + resultCounts[1] * 17 + resultCounts[2] * 13
}

func DiagnosticSeverityFilterIndicesInto(
    severityRanks: int[],
    targetRank: int,
    resultIndices: int[]): int {
    if targetRank <= 0 {
        return 0
    }

    matchCount := 0
    length := severityRanks.Length
    i := 0
    unrolledLimit := length - 4
    while i <= unrolledLimit {
        if severityRanks[i] == targetRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        next := i + 1
        if severityRanks[next] == targetRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 2
        if severityRanks[next] == targetRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 3
        if severityRanks[next] == targetRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        i = i + 4
    }

    while i < length {
        if severityRanks[i] == targetRank {
            if matchCount < resultIndices.Length {
                resultIndices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return matchCount
}

func DiagnosticSeverityFilterChecksumInto(
    severityRanks: int[],
    targetRank: int,
    resultIndices: int[]): int {
    matchCount := DiagnosticSeverityFilterIndicesInto(severityRanks, targetRank, resultIndices)
    checksum := matchCount
    i := 0
    while i < matchCount && i < resultIndices.Length {
        index := resultIndices[i]
        checksum = checksum + (i + 1) * 97 + (index + 1) * 31 + severityRanks[index] * 17
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterTraitsInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[]): int {
    count := MinInt(codes.Length, messages.Length)
    count = MinInt(count, snippets.Length)
    count = MinInt(count, resultCategories.Length)
    count = MinInt(count, resultSourceConstructs.Length)

    i := 0
    while i < count {
        code := codes[i]
        message := messages[i]
        snippet := snippets[i]

        category := ClassifyDiagnosticCategory(code, message)
        sourceConstruct := 8

        if category == 2 {
            sourceConstruct = 4
        } else {
            sourceConstruct = InferDiagnosticSourceConstruct(snippet)
        }

        resultCategories[i] = category
        resultSourceConstructs[i] = sourceConstruct

        i = i + 1
    }

    return count
}

func DiagnosticClusterTraitChecksumInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[]): int {
    count := DiagnosticClusterTraitsInto(
        codes,
        messages,
        snippets,
        resultCategories,
        resultSourceConstructs)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultCategories[i] * 31 + resultSourceConstructs[i] * 17
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterTraitsAndPatternsInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[],
    resultPatterns: string[]): int {
    count := MinInt(codes.Length, messages.Length)
    count = MinInt(count, snippets.Length)
    count = MinInt(count, resultCategories.Length)
    count = MinInt(count, resultSourceConstructs.Length)
    count = MinInt(count, resultPatterns.Length)

    i := 0
    while i < count {
        code := codes[i]
        message := messages[i]
        snippet := snippets[i]

        category := ClassifyDiagnosticCategory(code, message)
        sourceConstruct := 8

        if category == 2 {
            sourceConstruct = 4
        } else {
            sourceConstruct = InferDiagnosticSourceConstruct(snippet)
        }

        resultCategories[i] = category
        resultSourceConstructs[i] = sourceConstruct
        resultPatterns[i] = NormalizeDiagnosticMessagePattern(message)

        i = i + 1
    }

    return count
}

func DiagnosticClusterTraitPatternChecksumInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[],
    resultPatterns: string[]): int {
    count := DiagnosticClusterTraitsAndPatternsInto(
        codes,
        messages,
        snippets,
        resultCategories,
        resultSourceConstructs,
        resultPatterns)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultCategories[i] * 31 + resultSourceConstructs[i] * 17 + resultPatterns[i].Length
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterIdsInto(
    codes: string[],
    severities: string[],
    categories: string[],
    sourceConstructs: string[],
    recipes: string[],
    messagePatterns: string[],
    resultIds: string[]): int {
    count := MinInt(codes.Length, severities.Length)
    count = MinInt(count, categories.Length)
    count = MinInt(count, sourceConstructs.Length)
    count = MinInt(count, recipes.Length)
    count = MinInt(count, messagePatterns.Length)
    count = MinInt(count, resultIds.Length)

    hexBuffer := new char[](13)
    i := 0
    while i < count {
        resultIds[i] = CreateDiagnosticClusterId(
            codes[i],
            severities[i],
            categories[i],
            sourceConstructs[i],
            recipes[i],
            messagePatterns[i],
            hexBuffer)
        i = i + 1
    }

    return count
}

func DiagnosticClusterIdChecksumInto(
    codes: string[],
    severities: string[],
    categories: string[],
    sourceConstructs: string[],
    recipes: string[],
    messagePatterns: string[],
    resultIds: string[]): int {
    count := DiagnosticClusterIdsInto(
        codes,
        severities,
        categories,
        sourceConstructs,
        recipes,
        messagePatterns,
        resultIds)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultIds[i].Length * 31
        i = i + 1
    }

    return checksum
}

func CreateDiagnosticClusterId(
    code: string,
    severity: string,
    category: string,
    sourceConstruct: string,
    recipe: string,
    messagePattern: string,
    hexBuffer: char[]): string {
    hash := 17
    hash = HashDiagnosticClusterIdPart(hash, code)
    hash = HashDiagnosticClusterIdSeparator(hash)
    hash = HashDiagnosticClusterIdPart(hash, severity)
    hash = HashDiagnosticClusterIdSeparator(hash)
    hash = HashDiagnosticClusterIdPart(hash, category)
    hash = HashDiagnosticClusterIdSeparator(hash)
    hash = HashDiagnosticClusterIdPart(hash, sourceConstruct)
    hash = HashDiagnosticClusterIdSeparator(hash)
    hash = HashDiagnosticClusterIdPart(hash, recipe)
    hash = HashDiagnosticClusterIdSeparator(hash)
    hash = HashDiagnosticClusterIdPart(hash, messagePattern)

    return FormatDiagnosticClusterId(hash, hexBuffer)
}

func FormatDiagnosticClusterId(hash: int, buffer: char[]): string {
    if buffer.Length < 13 {
        return "diag-" + Math.Abs(hash).ToString("x")
    }

    value := Math.Abs(hash)
    buffer[0] = 'd'
    buffer[1] = 'i'
    buffer[2] = 'a'
    buffer[3] = 'g'
    buffer[4] = '-'

    if value == 0 {
        buffer[5] = '0'
        return new string(buffer, 0, 6)
    }

    digitCount := 0
    remaining := value
    while remaining > 0 {
        digitCount = digitCount + 1
        remaining = remaining / 16
    }

    position := 4 + digitCount
    remaining = value
    while position >= 5 {
        digit := remaining % 16
        buffer[position] = DiagnosticClusterHexDigit(digit)
        remaining = remaining / 16
        position = position - 1
    }

    return new string(buffer, 0, 5 + digitCount)
}

func DiagnosticClusterHexDigit(value: int): char {
    if value < 10 {
        return (char)(48 + value)
    }

    return (char)(87 + value)
}

func HashDiagnosticClusterIdSeparator(hash: int): int {
    return hash * 31 + 124
}

func HashDiagnosticClusterIdPart(hash: int, text: string): int {
    i := 0
    while i < text.Length {
        hash = hash * 31 + (int)text[i]
        i = i + 1
    }

    return hash
}

func DiagnosticClusterNextCommandsInto(
    files: string[],
    lines: int[],
    columns: int[],
    resultCommands: string[]): int {
    count := MinInt(files.Length, lines.Length)
    count = MinInt(count, columns.Length)
    count = MinInt(count, resultCommands.Length)

    builder := new StringBuilder(128)
    i := 0
    while i < count {
        builder.Clear()
        AppendDiagnosticClusterNextCommand(builder, files[i], lines[i], columns[i])
        resultCommands[i] = builder.ToString()
        i = i + 1
    }

    return count
}

func DiagnosticClusterNextCommandChecksumInto(
    files: string[],
    lines: int[],
    columns: int[],
    resultCommands: string[]): int {
    count := DiagnosticClusterNextCommandsInto(files, lines, columns, resultCommands)

    checksum := count
    i := 0
    while i < count {
        checksum = checksum + resultCommands[i].Length * 31
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterCompactGroupsInto(
    codeIds: int[],
    severityIds: int[],
    categoryIds: int[],
    sourceConstructIds: int[],
    recipeIds: int[],
    riskIds: int[],
    messagePatternIds: int[],
    files: string[],
    lines: int[],
    columns: int[],
    slotGroups: int[],
    groupKeyIndices: int[],
    resultRootIndices: int[],
    resultCounts: int[]): int {
    count := MinInt(codeIds.Length, severityIds.Length)
    count = MinInt(count, categoryIds.Length)
    count = MinInt(count, sourceConstructIds.Length)
    count = MinInt(count, recipeIds.Length)
    count = MinInt(count, riskIds.Length)
    count = MinInt(count, messagePatternIds.Length)
    count = MinInt(count, files.Length)
    count = MinInt(count, lines.Length)
    count = MinInt(count, columns.Length)

    maxGroups := MinInt(resultRootIndices.Length, resultCounts.Length)
    maxGroups = MinInt(maxGroups, groupKeyIndices.Length)
    capacity := slotGroups.Length
    if count == 0 || maxGroups == 0 || capacity == 0 {
        return 0
    }

    i := 0
    while i < capacity {
        slotGroups[i] = -1
        i = i + 1
    }

    groupCount := 0
    index := 0
    while index < count {
        hash := HashDiagnosticClusterCompactGroupingKey(
            severityIds[index],
            codeIds[index],
            categoryIds[index],
            sourceConstructIds[index],
            recipeIds[index],
            riskIds[index],
            messagePatternIds[index])
        slot := PositiveModulo(hash, capacity)
        groupIndex := -1
        probes := 0

        while probes < capacity {
            candidateGroup := slotGroups[slot]
            if candidateGroup < 0 {
                break
            }

            keyIndex := groupKeyIndices[candidateGroup]
            if DiagnosticClusterCompactGroupingKeysEqual(
                index,
                keyIndex,
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds) {
                groupIndex = candidateGroup
                break
            }

            slot = slot + 1
            if slot == capacity {
                slot = 0
            }
            probes = probes + 1
        }

        if groupIndex < 0 {
            if groupCount >= maxGroups || groupCount >= capacity || probes >= capacity {
                SortDiagnosticClusterGroups(resultRootIndices, resultCounts, groupCount, files, lines, columns)
                return groupCount
            }

            groupKeyIndices[groupCount] = index
            resultRootIndices[groupCount] = index
            resultCounts[groupCount] = 1
            slotGroups[slot] = groupCount
            groupCount = groupCount + 1
        } else {
            resultCounts[groupIndex] = resultCounts[groupIndex] + 1
            if IsDiagnosticClusterRootBefore(index, resultRootIndices[groupIndex], files, lines, columns) {
                resultRootIndices[groupIndex] = index
            }
        }

        index = index + 1
    }

    SortDiagnosticClusterGroups(resultRootIndices, resultCounts, groupCount, files, lines, columns)
    return groupCount
}

func DiagnosticClusterCompactGroupChecksumInto(
    codeIds: int[],
    severityIds: int[],
    categoryIds: int[],
    sourceConstructIds: int[],
    recipeIds: int[],
    riskIds: int[],
    messagePatternIds: int[],
    files: string[],
    lines: int[],
    columns: int[],
    slotGroups: int[],
    groupKeyIndices: int[],
    resultRootIndices: int[],
    resultCounts: int[]): int {
    groupCount := DiagnosticClusterCompactGroupsInto(
        codeIds,
        severityIds,
        categoryIds,
        sourceConstructIds,
        recipeIds,
        riskIds,
        messagePatternIds,
        files,
        lines,
        columns,
        slotGroups,
        groupKeyIndices,
        resultRootIndices,
        resultCounts)

    checksum := groupCount
    i := 0
    while i < groupCount {
        checksum = checksum + (resultRootIndices[i] + 1) * 31 + resultCounts[i] * 17
        i = i + 1
    }

    return checksum
}

func DiagnosticClusterCompactGroupMembersInto(
    codeIds: int[],
    severityIds: int[],
    categoryIds: int[],
    sourceConstructIds: int[],
    recipeIds: int[],
    riskIds: int[],
    messagePatternIds: int[],
    files: string[],
    lines: int[],
    columns: int[],
    groupRootIndices: int[],
    groupCounts: int[],
    groupCount: int,
    slotGroups: int[],
    groupFirstMemberIndices: int[],
    memberNextIndices: int[],
    resultStarts: int[],
    resultMemberIndices: int[]): int {
    count := MinInt(codeIds.Length, severityIds.Length)
    count = MinInt(count, categoryIds.Length)
    count = MinInt(count, sourceConstructIds.Length)
    count = MinInt(count, recipeIds.Length)
    count = MinInt(count, riskIds.Length)
    count = MinInt(count, messagePatternIds.Length)
    count = MinInt(count, files.Length)
    count = MinInt(count, lines.Length)
    count = MinInt(count, columns.Length)
    groupLimit := MinInt(groupCount, groupRootIndices.Length)
    groupLimit = MinInt(groupLimit, groupCounts.Length)
    groupLimit = MinInt(groupLimit, resultStarts.Length)
    groupLimit = MinInt(groupLimit, groupFirstMemberIndices.Length)

    if groupCount < 0 || groupLimit != groupCount {
        return -1
    }

    if groupCount == 0 {
        return 0
    }

    if slotGroups.Length == 0 || memberNextIndices.Length < count {
        return -1
    }

    i := 0
    while i < slotGroups.Length {
        slotGroups[i] = -1
        i = i + 1
    }

    groupIndex := 0
    totalExpected := 0
    while groupIndex < groupCount {
        rootIndex := groupRootIndices[groupIndex]
        expectedCount := groupCounts[groupIndex]
        if rootIndex < 0 || rootIndex >= count || expectedCount < 0 {
            return -1
        }

        totalExpected = totalExpected + expectedCount
        if totalExpected > resultMemberIndices.Length {
            return -1
        }

        groupFirstMemberIndices[groupIndex] = -1
        resultStarts[groupIndex] = 0

        hash := HashDiagnosticClusterCompactGroupingKey(
            severityIds[rootIndex],
            codeIds[rootIndex],
            categoryIds[rootIndex],
            sourceConstructIds[rootIndex],
            recipeIds[rootIndex],
            riskIds[rootIndex],
            messagePatternIds[rootIndex])
        slot := PositiveModulo(hash, slotGroups.Length)
        probes := 0
        placed := false
        while probes < slotGroups.Length {
            candidateGroup := slotGroups[slot]
            if candidateGroup < 0 {
                slotGroups[slot] = groupIndex
                placed = true
                break
            }

            candidateRoot := groupRootIndices[candidateGroup]
            if DiagnosticClusterCompactGroupingKeysEqual(
                rootIndex,
                candidateRoot,
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds) {
                return -1
            }

            slot = slot + 1
            if slot == slotGroups.Length {
                slot = 0
            }

            probes = probes + 1
        }

        if !placed {
            return -1
        }

        groupIndex = groupIndex + 1
    }

    diagnosticIndex := 0
    while diagnosticIndex < count {
        hash := HashDiagnosticClusterCompactGroupingKey(
            severityIds[diagnosticIndex],
            codeIds[diagnosticIndex],
            categoryIds[diagnosticIndex],
            sourceConstructIds[diagnosticIndex],
            recipeIds[diagnosticIndex],
            riskIds[diagnosticIndex],
            messagePatternIds[diagnosticIndex])
        slot := PositiveModulo(hash, slotGroups.Length)
        probes := 0
        groupIndex = -1
        while probes < slotGroups.Length {
            candidateGroup := slotGroups[slot]
            if candidateGroup < 0 {
                break
            }

            rootIndex := groupRootIndices[candidateGroup]
            if DiagnosticClusterCompactGroupingKeysEqual(
                diagnosticIndex,
                rootIndex,
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds) {
                groupIndex = candidateGroup
                break
            }

            slot = slot + 1
            if slot == slotGroups.Length {
                slot = 0
            }

            probes = probes + 1
        }

        if groupIndex < 0 {
            return -1
        }

        resultStarts[groupIndex] = resultStarts[groupIndex] + 1
        memberNextIndices[diagnosticIndex] = -1
        firstMember := groupFirstMemberIndices[groupIndex]
        if firstMember < 0 || IsDiagnosticClusterRootBefore(diagnosticIndex, firstMember, files, lines, columns) {
            memberNextIndices[diagnosticIndex] = firstMember
            groupFirstMemberIndices[groupIndex] = diagnosticIndex
        } else {
            previousMember := firstMember
            currentMember := memberNextIndices[previousMember]
            while currentMember >= 0
                && !IsDiagnosticClusterRootBefore(diagnosticIndex, currentMember, files, lines, columns) {
                previousMember = currentMember
                currentMember = memberNextIndices[currentMember]
            }

            memberNextIndices[diagnosticIndex] = currentMember
            memberNextIndices[previousMember] = diagnosticIndex
        }

        diagnosticIndex = diagnosticIndex + 1
    }

    offset := 0
    groupIndex = 0
    while groupIndex < groupCount {
        expectedCount := groupCounts[groupIndex]
        if resultStarts[groupIndex] != expectedCount {
            return -1
        }

        resultStarts[groupIndex] = offset
        written := 0
        memberIndex := groupFirstMemberIndices[groupIndex]
        while memberIndex >= 0 {
            resultMemberIndices[offset + written] = memberIndex
            written = written + 1
            memberIndex = memberNextIndices[memberIndex]
        }

        if written != expectedCount {
            return -1
        }

        offset = offset + written
        groupIndex = groupIndex + 1
    }

    return offset
}

func DiagnosticClusterCompactGroupMemberChecksumInto(
    codeIds: int[],
    severityIds: int[],
    categoryIds: int[],
    sourceConstructIds: int[],
    recipeIds: int[],
    riskIds: int[],
    messagePatternIds: int[],
    files: string[],
    lines: int[],
    columns: int[],
    groupRootIndices: int[],
    groupCounts: int[],
    groupCount: int,
    slotGroups: int[],
    groupFirstMemberIndices: int[],
    memberNextIndices: int[],
    resultStarts: int[],
    resultMemberIndices: int[]): int {
    total := DiagnosticClusterCompactGroupMembersInto(
        codeIds,
        severityIds,
        categoryIds,
        sourceConstructIds,
        recipeIds,
        riskIds,
        messagePatternIds,
        files,
        lines,
        columns,
        groupRootIndices,
        groupCounts,
        groupCount,
        slotGroups,
        groupFirstMemberIndices,
        memberNextIndices,
        resultStarts,
        resultMemberIndices)

    if total < 0 {
        return total
    }

    checksum := total
    groupIndex := 0
    while groupIndex < groupCount {
        checksum = checksum + (resultStarts[groupIndex] + 1) * 31 + groupCounts[groupIndex] * 17
        groupIndex = groupIndex + 1
    }

    i := 0
    while i < total {
        index := resultMemberIndices[i]
        checksum = checksum + (index + 1) * 13 + lines[index] * 7 + columns[index] * 5
        i = i + 1
    }

    return checksum
}

func SortDiagnosticClusterGroups(
    resultRootIndices: int[],
    resultCounts: int[],
    groupCount: int,
    files: string[],
    lines: int[],
    columns: int[]): void {
    i := 1
    while i < groupCount {
        root := resultRootIndices[i]
        count := resultCounts[i]
        j := i - 1

        while j >= 0 && IsDiagnosticClusterGroupBefore(root, count, resultRootIndices[j], resultCounts[j], files, lines, columns) {
            resultRootIndices[j + 1] = resultRootIndices[j]
            resultCounts[j + 1] = resultCounts[j]
            j = j - 1
        }

        resultRootIndices[j + 1] = root
        resultCounts[j + 1] = count
        i = i + 1
    }
}

func IsDiagnosticClusterGroupBefore(
    leftRoot: int,
    leftCount: int,
    rightRoot: int,
    rightCount: int,
    files: string[],
    lines: int[],
    columns: int[]): bool {
    if leftCount != rightCount {
        return leftCount > rightCount
    }

    fileCompare := String.Compare(files[leftRoot], files[rightRoot], StringComparison.OrdinalIgnoreCase)
    if fileCompare != 0 {
        return fileCompare < 0
    }

    if lines[leftRoot] != lines[rightRoot] {
        return lines[leftRoot] < lines[rightRoot]
    }

    return columns[leftRoot] < columns[rightRoot]
}

func IsDiagnosticClusterRootBefore(
    left: int,
    right: int,
    files: string[],
    lines: int[],
    columns: int[]): bool {
    if lines[left] != lines[right] {
        return lines[left] < lines[right]
    }

    if columns[left] != columns[right] {
        return columns[left] < columns[right]
    }

    return String.Compare(files[left], files[right], StringComparison.OrdinalIgnoreCase) < 0
}

func DiagnosticClusterCompactGroupingKeysEqual(
    left: int,
    right: int,
    codeIds: int[],
    severityIds: int[],
    categoryIds: int[],
    sourceConstructIds: int[],
    recipeIds: int[],
    riskIds: int[],
    messagePatternIds: int[]): bool {
    return severityIds[left] == severityIds[right]
        && codeIds[left] == codeIds[right]
        && categoryIds[left] == categoryIds[right]
        && sourceConstructIds[left] == sourceConstructIds[right]
        && recipeIds[left] == recipeIds[right]
        && riskIds[left] == riskIds[right]
        && messagePatternIds[left] == messagePatternIds[right]
}

func HashDiagnosticClusterCompactGroupingKey(
    severityId: int,
    codeId: int,
    categoryId: int,
    sourceConstructId: int,
    recipeId: int,
    riskId: int,
    messagePatternId: int): int {
    hash := 17
    hash = hash * 31 + severityId
    hash = hash * 31 + codeId
    hash = hash * 31 + categoryId
    hash = hash * 31 + sourceConstructId
    hash = hash * 31 + recipeId
    hash = hash * 31 + riskId
    hash = hash * 31 + messagePatternId
    return hash
}

func PositiveModulo(value: int, divisor: int): int {
    result := value % divisor
    if result < 0 {
        return result + divisor
    }

    return result
}

func CreateDiagnosticClusterNextCommand(filePath: string, line: int, column: int): string {
    builder := new StringBuilder(filePath.Length + 48)
    AppendDiagnosticClusterNextCommand(builder, filePath, line, column)
    return builder.ToString()
}

func AppendDiagnosticClusterNextCommand(builder: StringBuilder, filePath: string, line: int, column: int): void {
    builder.Append("nlc query inspect --file ")
    AppendEscapedDiagnosticCommandArgument(builder, filePath)
    builder.Append(" --pos ")
    builder.Append(line)
    builder.Append(':')
    builder.Append(column)
}

func EscapeDiagnosticCommandArgument(value: string): string {
    builder := new StringBuilder(value.Length + 2)
    AppendEscapedDiagnosticCommandArgument(builder, value)
    return builder.ToString()
}

func AppendEscapedDiagnosticCommandArgument(builder: StringBuilder, value: string): void {
    if IsBlank(value) {
        builder.Append('"')
        builder.Append('"')
        return
    }

    i := 0
    while i < value.Length {
        if !IsSafeDiagnosticCommandArgumentChar(value[i]) {
            AppendQuotedDiagnosticCommandArgument(builder, value)
            return
        }

        i = i + 1
    }

    builder.Append(value)
}

func AppendQuotedDiagnosticCommandArgument(builder: StringBuilder, value: string): void {
    builder.Append('"')

    i := 0
    while i < value.Length {
        ch := value[i]
        if ch == '\\' {
            builder.Append('\\')
            builder.Append('\\')
        } else if ch == '"' {
            builder.Append('\\')
            builder.Append('"')
        } else {
            builder.Append(ch)
        }

        i = i + 1
    }

    builder.Append('"')
}

func IsSafeDiagnosticCommandArgumentChar(ch: char): bool {
    return Char.IsLetterOrDigit(ch) || ch == '/' || ch == '.' || ch == '_' || ch == '-'
}

func ClassifyDiagnosticCategory(code: string, message: string): int {
    if code == "NL102" {
        if ContainsChar(message, ';') || ContainsIgnoreCase(message, "semicolon") {
            return 0
        }

        return 1
    }

    if code == "NL703" {
        return 2
    }

    if code == "NL301" || code == "NL412" {
        return 3
    }

    if code == "NL201" || code == "NL302" {
        return 4
    }

    if code == "NL202" {
        return 5
    }

    if code == "NL303" {
        return 6
    }

    if ContainsIgnoreCase(message, "expected token") || ContainsIgnoreCase(message, "missing") {
        if ContainsChar(message, ';') || ContainsIgnoreCase(message, "semicolon") {
            return 0
        }

        return 1
    }

    if ContainsIgnoreCase(message, "circular import") {
        return 2
    }

    if ContainsIgnoreCase(message, "undefined variable") || ContainsIgnoreCase(message, "undefined symbol") {
        return 3
    }

    if ContainsIgnoreCase(message, "type not found") || ContainsIgnoreCase(message, "undefined type") || ContainsIgnoreCase(message, "cannot resolve type") {
        return 4
    }

    if ContainsIgnoreCase(message, "type mismatch") {
        return 5
    }

    if ContainsIgnoreCase(message, "member") || ContainsIgnoreCase(message, "method") {
        return 6
    }

    return 7
}

func InferDiagnosticSourceConstruct(snippet: string): int {
    start := TrimStartIndex(snippet)

    if StartsWithIgnoreCase(snippet, start, "let ") || ContainsOrdinal(snippet, ":=") {
        return 0
    }

    declarationStart := StripLeadingDeclarationModifiers(snippet, start)
    if StartsWithIgnoreCase(snippet, declarationStart, "func ") || StartsWithIgnoreCase(snippet, declarationStart, "func* ") {
        return 1
    }

    if StartsWithIgnoreCase(snippet, start, "class ") {
        return 2
    }

    if StartsWithIgnoreCase(snippet, start, "interface ") {
        return 3
    }

    if StartsWithIgnoreCase(snippet, start, "import ") || StartsWithIgnoreCase(snippet, start, "using ") {
        return 4
    }

    if StartsWithIgnoreCase(snippet, start, "return ") {
        return 5
    }

    if StartsWithIgnoreCase(snippet, start, "if ") || StartsWithIgnoreCase(snippet, start, "for ") || StartsWithIgnoreCase(snippet, start, "while ") || StartsWithIgnoreCase(snippet, start, "match ") {
        return 6
    }

    if ContainsCharFrom(snippet, '(', start) && ContainsCharFrom(snippet, ')', start) {
        return 7
    }

    return 8
}

func StripLeadingDeclarationModifiers(snippet: string, start: int): int {
    current := start

    while true {
        current = TrimStartIndexFrom(snippet, current)

        if StartsWithIgnoreCase(snippet, current, "async ") {
            current = current + 6
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "static ") {
            current = current + 7
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "override ") {
            current = current + 9
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "public ") {
            current = current + 7
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "private ") {
            current = current + 8
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "protected ") {
            current = current + 10
            continue
        }

        if StartsWithIgnoreCase(snippet, current, "internal ") {
            current = current + 9
            continue
        }

        return current
    }

    return current
}

func NormalizeDiagnosticMessagePattern(message: string): string {
    if IsBlank(message) {
        return "unknown-message"
    }

    builder := new StringBuilder(message.Length)
    inQuoted := false
    i := 0

    while i < message.Length {
        ch := message[i]
        if ch == '\'' || ch == '"' {
            inQuoted = !inQuoted
            if inQuoted {
                builder.Append("{value}")
            }

            i = i + 1
            continue
        }

        if !inQuoted {
            if ch >= '0' && ch <= '9' {
                builder.Append('#')
            } else {
                builder.Append(ch)
            }
        }

        i = i + 1
    }

    return builder.ToString().Trim()
}

func ContainsIgnoreCase(text: string, needle: string): bool {
    return text.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0
}

func StartsWithIgnoreCase(text: string, start: int, needle: string): bool {
    if start < 0 || start + needle.Length > text.Length {
        return false
    }

    return String.Compare(text, start, needle, 0, needle.Length, StringComparison.OrdinalIgnoreCase) == 0
}

func ContainsOrdinal(text: string, needle: string): bool {
    return text.IndexOf(needle, StringComparison.Ordinal) >= 0
}

func ContainsChar(text: string, ch: char): bool {
    return ContainsCharFrom(text, ch, 0)
}

func ContainsCharFrom(text: string, ch: char, start: int): bool {
    i := start
    if i < 0 {
        i = 0
    }

    while i < text.Length {
        if text[i] == ch {
            return true
        }

        i = i + 1
    }

    return false
}

func TrimStartIndex(text: string): int {
    return TrimStartIndexFrom(text, 0)
}

func TrimStartIndexFrom(text: string, start: int): int {
    i := start
    if i < 0 {
        i = 0
    }

    while i < text.Length && IsWhitespace(text[i]) {
        i = i + 1
    }

    return i
}

func IsBlank(text: string): bool {
    i := 0
    while i < text.Length {
        if !IsWhitespace(text[i]) {
            return false
        }

        i = i + 1
    }

    return true
}

func IsWhitespace(ch: char): bool {
    return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n'
}

func MinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

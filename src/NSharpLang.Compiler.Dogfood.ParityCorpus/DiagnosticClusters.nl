import System
import System.Text

// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/DiagnosticClusters.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

struct DiagnosticClusterPatternOutputTable {
    Patterns: string[]
}

struct DiagnosticClusterIdInputTable {
    Codes: string[]
    Severities: string[]
    Categories: string[]
    SourceConstructs: string[]
    Recipes: string[]
    MessagePatterns: string[]
}

struct DiagnosticClusterIdOutputTable {
    Ids: string[]
}

struct DiagnosticClusterCommandOutputTable {
    Commands: string[]
}

func DiagnosticClusterTraitPatternCount(input: &DiagnosticClusterTraitInputTable, output: &DiagnosticClusterTraitOutputTable, patterns: &DiagnosticClusterPatternOutputTable): int {
    count := DiagnosticClusterTraitCount(ref input, ref output)
    count = MinInt(count, patterns.Patterns.Length)
    return count
}

func DiagnosticClusterIdCount(input: &DiagnosticClusterIdInputTable, output: &DiagnosticClusterIdOutputTable): int {
    count := MinInt(input.Codes.Length, input.Severities.Length)
    count = MinInt(count, input.Categories.Length)
    count = MinInt(count, input.SourceConstructs.Length)
    count = MinInt(count, input.Recipes.Length)
    count = MinInt(count, input.MessagePatterns.Length)
    count = MinInt(count, output.Ids.Length)
    return count
}

func DiagnosticClusterCommandCount(locations: &DiagnosticClusterLocationTable, output: &DiagnosticClusterCommandOutputTable): int {
    count := DiagnosticClusterLocationCount(ref locations)
    count = MinInt(count, output.Commands.Length)
    return count
}

func DiagnosticClusterTraitsAndPatternsInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[],
    resultPatterns: string[]): int {
    input := new DiagnosticClusterTraitInputTable { Codes: codes, Messages: messages, Snippets: snippets }
    output := new DiagnosticClusterTraitOutputTable { Categories: resultCategories, SourceConstructs: resultSourceConstructs }
    patterns := new DiagnosticClusterPatternOutputTable { Patterns: resultPatterns }
    return DiagnosticClusterTraitsAndPatternsCore(ref input, ref output, ref patterns)
}

func DiagnosticClusterTraitsAndPatternsCore(
    input: &DiagnosticClusterTraitInputTable,
    output: &DiagnosticClusterTraitOutputTable,
    patterns: &DiagnosticClusterPatternOutputTable): int {
    count := DiagnosticClusterTraitPatternCount(ref input, ref output, ref patterns)

    i := 0
    while i < count {
        code := input.Codes[i]
        message := input.Messages[i]
        snippet := input.Snippets[i]

        category := ClassifyDiagnosticCategory(code, message)
        sourceConstruct := 8

        if category == 2 {
            sourceConstruct = 4
        } else {
            sourceConstruct = InferDiagnosticSourceConstruct(snippet)
        }

        output.Categories[i] = category
        output.SourceConstructs[i] = sourceConstruct
        patterns.Patterns[i] = NormalizeDiagnosticMessagePattern(message)

        i = i + 1
    }

    return count
}

func DiagnosticClusterIdsInto(
    codes: string[],
    severities: string[],
    categories: string[],
    sourceConstructs: string[],
    recipes: string[],
    messagePatterns: string[],
    resultIds: string[]): int {
    input := new DiagnosticClusterIdInputTable { Codes: codes, Severities: severities, Categories: categories, SourceConstructs: sourceConstructs, Recipes: recipes, MessagePatterns: messagePatterns }
    output := new DiagnosticClusterIdOutputTable { Ids: resultIds }
    return DiagnosticClusterIdsCore(ref input, ref output)
}

func DiagnosticClusterIdsCore(input: &DiagnosticClusterIdInputTable, output: &DiagnosticClusterIdOutputTable): int {
    count := DiagnosticClusterIdCount(ref input, ref output)

    hexBuffer := new char[](13)
    i := 0
    while i < count {
        output.Ids[i] = CreateDiagnosticClusterId(
            input.Codes[i],
            input.Severities[i],
            input.Categories[i],
            input.SourceConstructs[i],
            input.Recipes[i],
            input.MessagePatterns[i],
            hexBuffer)
        i = i + 1
    }

    return count
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
    locations := new DiagnosticClusterLocationTable { Files: files, Lines: lines, Columns: columns }
    output := new DiagnosticClusterCommandOutputTable { Commands: resultCommands }
    return DiagnosticClusterNextCommandsCore(ref locations, ref output)
}

func DiagnosticClusterNextCommandsCore(locations: &DiagnosticClusterLocationTable, output: &DiagnosticClusterCommandOutputTable): int {
    count := DiagnosticClusterCommandCount(ref locations, ref output)

    builder := new StringBuilder(128)
    i := 0
    while i < count {
        builder.Clear()
        AppendDiagnosticClusterNextCommand(builder, locations.Files[i], locations.Lines[i], locations.Columns[i])
        output.Commands[i] = builder.ToString()
        i = i + 1
    }

    return count
}

func AppendDiagnosticClusterNextCommand(builder: StringBuilder, filePath: string, line: int, column: int): void {
    builder.Append("nlc query inspect --file ")
    AppendEscapedDiagnosticCommandArgument(builder, filePath)
    builder.Append(" --pos ")
    builder.Append(line)
    builder.Append(':')
    builder.Append(column)
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

func DiagnosticSeveritySummaryChecksumInto(severities: string[], count: int, resultCounts: int[]): int {
    count = DiagnosticSeveritySummaryInto(severities, count, resultCounts)
    if resultCounts.Length < 3 {
        return count
    }

    return count + resultCounts[0] * 31 + resultCounts[1] * 17 + resultCounts[2] * 13
}

func DiagnosticSeverityFilterChecksumInto(
    severityRanks: int[],
    targetRank: int,
    resultIndices: int[]): int {
    if targetRank <= 0 {
        return 0
    }

    length := severityRanks.Length
    if resultIndices.Length < length {
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

    matchCount := 0
    checksum := 0
    i := 0
    unrolledLimit := length - 8
    while i <= unrolledLimit {
        if severityRanks[i] == targetRank {
            resultIndices[matchCount] = i
            checksum = checksum + (matchCount + 1) * 97 + (i + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next := i + 1
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 2
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 3
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 4
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 5
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 6
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        next = i + 7
        if severityRanks[next] == targetRank {
            resultIndices[matchCount] = next
            checksum = checksum + (matchCount + 1) * 97 + (next + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        i = i + 8
    }

    while i < length {
        if severityRanks[i] == targetRank {
            resultIndices[matchCount] = i
            checksum = checksum + (matchCount + 1) * 97 + (i + 1) * 31 + targetRank * 17
            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return checksum + matchCount
}

func DiagnosticShadowSuppressionChecksumInto(
    codeIds: int[],
    fileRanks: int[],
    targetCodeId: int,
    shadowFileFlags: int[],
    resultIndices: int[]): int {
    count := MinInt(codeIds.Length, fileRanks.Length)
    if count == 0 {
        return 0
    }

    keptCount := 0
    checksum := 0
    i := 0
    while i < count {
        fileRank := fileRanks[i]
        suppress := targetCodeId > 0 &&
            codeIds[i] == targetCodeId &&
            fileRank > 0 &&
            fileRank < shadowFileFlags.Length &&
            shadowFileFlags[fileRank] != 0

        if !suppress {
            if keptCount < resultIndices.Length {
                resultIndices[keptCount] = i
            }

            checksum = checksum + (keptCount + 1) * 97 + (i + 1) * 31 + codeIds[i] * 17 + fileRank * 13
            keptCount = keptCount + 1
        }

        i = i + 1
    }

    return checksum + keptCount
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

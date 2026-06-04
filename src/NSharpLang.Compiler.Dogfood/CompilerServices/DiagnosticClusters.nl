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

    i := 0
    while i < count {
        resultIds[i] = CreateDiagnosticClusterId(
            codes[i],
            severities[i],
            categories[i],
            sourceConstructs[i],
            recipes[i],
            messagePatterns[i])
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
    messagePattern: string): string {
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

    return "diag-" + Math.Abs(hash).ToString("x")
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

    i := 0
    while i < count {
        resultCommands[i] = CreateDiagnosticClusterNextCommand(files[i], lines[i], columns[i])
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
    builder.Append("nlc query inspect --file ")
    AppendEscapedDiagnosticCommandArgument(builder, filePath)
    builder.Append(" --pos ")
    builder.Append(line)
    builder.Append(':')
    builder.Append(column)
    return builder.ToString()
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

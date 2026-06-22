import System
import System.Text

struct DiagnosticSeverityTable {
    Severities: string[]
}

struct DiagnosticSeverityCountTable {
    Counts: int[]
}

struct DiagnosticSeverityRankTable {
    Ranks: int[]
}

struct DiagnosticIndexOutputTable {
    Indices: int[]
}

struct DiagnosticShadowSuppressionTable {
    CodeIds: int[]
    FileRanks: int[]
    ShadowFileFlags: int[]
}

struct DiagnosticClusterTraitInputTable {
    Codes: string[]
    Messages: string[]
    Snippets: string[]
}

struct DiagnosticClusterTraitOutputTable {
    Categories: int[]
    SourceConstructs: int[]
}

struct DiagnosticClusterLocationTable {
    Files: string[]
    Lines: int[]
    Columns: int[]
}

struct DiagnosticClusterGroupingKeyTable {
    CodeIds: int[]
    SeverityIds: int[]
    CategoryIds: int[]
    SourceConstructIds: int[]
    RecipeIds: int[]
    RiskIds: int[]
    MessagePatternIds: int[]
}

struct DiagnosticClusterGroupScratchTable {
    SlotGroups: int[]
    GroupKeyIndices: int[]
}

struct DiagnosticClusterGroupTable {
    RootIndices: int[]
    Counts: int[]
}

struct DiagnosticClusterMemberScratchTable {
    SlotGroups: int[]
    FirstMemberIndices: int[]
    MemberNextIndices: int[]
}

struct DiagnosticClusterMemberOutputTable {
    Starts: int[]
    MemberIndices: int[]
}

func DiagnosticSeverityCount(table: &DiagnosticSeverityTable, requestedCount: int): int {
    if requestedCount > table.Severities.Length {
        return table.Severities.Length
    }

    return requestedCount
}

func DiagnosticShadowSuppressionCount(table: &DiagnosticShadowSuppressionTable): int {
    return MinInt(table.CodeIds.Length, table.FileRanks.Length)
}

func DiagnosticClusterTraitCount(input: &DiagnosticClusterTraitInputTable, output: &DiagnosticClusterTraitOutputTable): int {
    count := MinInt(input.Codes.Length, input.Messages.Length)
    count = MinInt(count, input.Snippets.Length)
    count = MinInt(count, output.Categories.Length)
    count = MinInt(count, output.SourceConstructs.Length)
    return count
}

func DiagnosticClusterLocationCount(locations: &DiagnosticClusterLocationTable): int {
    count := MinInt(locations.Files.Length, locations.Lines.Length)
    count = MinInt(count, locations.Columns.Length)
    return count
}

func DiagnosticClusterGroupingKeyCount(keys: &DiagnosticClusterGroupingKeyTable): int {
    count := MinInt(keys.CodeIds.Length, keys.SeverityIds.Length)
    count = MinInt(count, keys.CategoryIds.Length)
    count = MinInt(count, keys.SourceConstructIds.Length)
    count = MinInt(count, keys.RecipeIds.Length)
    count = MinInt(count, keys.RiskIds.Length)
    count = MinInt(count, keys.MessagePatternIds.Length)
    return count
}

func DiagnosticClusterInputCount(keys: &DiagnosticClusterGroupingKeyTable, locations: &DiagnosticClusterLocationTable): int {
    return MinInt(DiagnosticClusterGroupingKeyCount(ref keys), DiagnosticClusterLocationCount(ref locations))
}

func DiagnosticSeveritySummaryInto(severities: string[], count: int, resultCounts: int[]): int {
    severityTable := new DiagnosticSeverityTable { Severities: severities }
    output := new DiagnosticSeverityCountTable { Counts: resultCounts }
    return DiagnosticSeveritySummaryCore(ref severityTable, count, ref output)
}

func DiagnosticSeveritySummaryCore(severities: &DiagnosticSeverityTable, requestedCount: int, output: &DiagnosticSeverityCountTable): int {
    if output.Counts.Length < 3 {
        return 0
    }

    count := DiagnosticSeverityCount(ref severities, requestedCount)

    errors := 0
    warnings := 0
    info := 0
    i := 0

    while i < count {
        severity := severities.Severities[i]
        if severity == "error" {
            errors = errors + 1
        } else if severity == "warning" {
            warnings = warnings + 1
        } else if severity == "info" {
            info = info + 1
        }

        i = i + 1
    }

    output.Counts[0] = errors
    output.Counts[1] = warnings
    output.Counts[2] = info
    return count
}

func DiagnosticSeverityFilterIndicesInto(
    severityRanks: int[],
    targetRank: int,
    resultIndices: int[]): int {
    severityTable := new DiagnosticSeverityRankTable { Ranks: severityRanks }
    output := new DiagnosticIndexOutputTable { Indices: resultIndices }
    return DiagnosticSeverityFilterIndicesCore(ref severityTable, targetRank, ref output)
}

func DiagnosticTitleText(code: string, severity: string): string {
    label := DiagnosticSeverityLabel(severity)
    if label == "" {
        return ""
    }

    return "[" + code + "] " + label
}

func DiagnosticSeverityLabel(severity: string): string {
    if severity == "error" {
        return "ERROR"
    }

    if severity == "warning" {
        return "WARNING"
    }

    if severity == "info" {
        return "INFO"
    }

    return DiagnosticUpperInvariant(severity)
}

func DiagnosticUpperInvariant(value: string): string {
    if value.Length == 0 {
        return ""
    }

    chars := new char[](value.Length)
    i := 0
    while i < value.Length {
        chars[i] = Char.ToUpperInvariant(value[i])
        i = i + 1
    }

    return new string(chars, 0, value.Length)
}

func DiagnosticDetailText(kind: int, value: string): string {
    if kind == 1 {
        return "Expected: `" + value + "`"
    }

    if kind == 2 {
        return "  Actual: `" + value + "`"
    }

    if kind == 3 {
        return "Hint: " + value
    }

    if kind == 4 {
        return "Suggestion: " + value
    }

    if kind == 5 {
        return "See: " + value
    }

    return ""
}

func DiagnosticNoDiagnosticsText(): string {
    return "No diagnostics found."
}

func DiagnosticFoundSummaryText(errors: int, warnings: int, info: int): string {
    summary := ""
    if errors > 0 {
        summary = DiagnosticAppendSummaryCount(summary, errors, "error", "errors")
    }

    if warnings > 0 {
        summary = DiagnosticAppendSummaryCount(summary, warnings, "warning", "warnings")
    }

    if info > 0 {
        summary = DiagnosticAppendSummaryCount(summary, info, "info", "info")
    }

    if summary == "" {
        return ""
    }

    return "Found " + summary + "."
}

func DiagnosticAppendSummaryCount(current: string, count: int, singular: string, plural: string): string {
    label := singular
    if count != 1 {
        label = plural
    }

    part := count.ToString() + " " + label
    if current == "" {
        return part
    }

    return current + ", " + part
}

func DiagnosticSourceLineText(line: int, sourceSnippet: string): string {
    return "    " + line.ToString() + " | " + sourceSnippet
}

func DiagnosticHeaderLineText(title: string, fileName: string, line: int, column: int, ruler: string): string {
    location := fileName + ":" + line.ToString() + ":" + column.ToString()
    headerContent := " " + title + " "
    locationPart := " " + location + " "
    remainingWidth := 60 - headerContent.Length - locationPart.Length
    if remainingWidth < 0 {
        remainingWidth = 0
    }

    rulerWidth := remainingWidth
    if rulerWidth < 2 {
        rulerWidth = 2
    }

    return DiagnosticRepeatText(ruler, 2) + headerContent + DiagnosticRepeatText(ruler, rulerWidth) +
        locationPart + DiagnosticRepeatText(ruler, 2)
}

func DiagnosticCaretLineText(line: int, column: int, length: int): string {
    lineDigits := line.ToString().Length
    caretOffset := column - 1
    if caretOffset < 0 {
        caretOffset = 0
    }

    caretLength := length
    if caretLength < 1 {
        caretLength = 1
    }

    return "    " + DiagnosticRepeatChar(' ', lineDigits) + " | " +
        DiagnosticRepeatChar(' ', caretOffset) + DiagnosticRepeatChar('^', caretLength)
}

func DiagnosticRepeatChar(ch: char, count: int): string {
    if count <= 0 {
        return ""
    }

    builder := new StringBuilder(count)
    i := 0
    while i < count {
        builder.Append(ch)
        i = i + 1
    }

    return builder.ToString()
}

func DiagnosticRepeatText(text: string, count: int): string {
    if count <= 0 {
        return ""
    }

    if text == "" {
        return ""
    }

    builder := new StringBuilder(text.Length * count)
    i := 0
    while i < count {
        builder.Append(text)
        i = i + 1
    }

    return builder.ToString()
}

func DiagnosticSeverityFilterIndicesCore(
    severityRanks: &DiagnosticSeverityRankTable,
    targetRank: int,
    output: &DiagnosticIndexOutputTable): int {
    if targetRank <= 0 {
        return 0
    }

    matchCount := 0
    length := severityRanks.Ranks.Length
    i := 0

    if output.Indices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            if severityRanks.Ranks[i] == targetRank {
                output.Indices[matchCount] = i
                matchCount = matchCount + 1
            }

            next := i + 1
            if severityRanks.Ranks[next] == targetRank {
                output.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 2
            if severityRanks.Ranks[next] == targetRank {
                output.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 3
            if severityRanks.Ranks[next] == targetRank {
                output.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 4
            if severityRanks.Ranks[next] == targetRank {
                output.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 5
            if severityRanks.Ranks[next] == targetRank {
                output.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 6
            if severityRanks.Ranks[next] == targetRank {
                output.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            next = i + 7
            if severityRanks.Ranks[next] == targetRank {
                output.Indices[matchCount] = next
                matchCount = matchCount + 1
            }

            i = i + 8
        }

        while i < length {
            if severityRanks.Ranks[i] == targetRank {
                output.Indices[matchCount] = i
                matchCount = matchCount + 1
            }

            i = i + 1
        }

        return matchCount
    }

    unrolledLimit := length - 4
    while i <= unrolledLimit {
        if severityRanks.Ranks[i] == targetRank {
            if matchCount < output.Indices.Length {
                output.Indices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        next := i + 1
        if severityRanks.Ranks[next] == targetRank {
            if matchCount < output.Indices.Length {
                output.Indices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 2
        if severityRanks.Ranks[next] == targetRank {
            if matchCount < output.Indices.Length {
                output.Indices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        next = i + 3
        if severityRanks.Ranks[next] == targetRank {
            if matchCount < output.Indices.Length {
                output.Indices[matchCount] = next
            }

            matchCount = matchCount + 1
        }

        i = i + 4
    }

    while i < length {
        if severityRanks.Ranks[i] == targetRank {
            if matchCount < output.Indices.Length {
                output.Indices[matchCount] = i
            }

            matchCount = matchCount + 1
        }

        i = i + 1
    }

    return matchCount
}

func DiagnosticShadowSuppressionIndicesInto(
    codeIds: int[],
    fileRanks: int[],
    targetCodeId: int,
    shadowFileFlags: int[],
    resultIndices: int[]): int {
    source := new DiagnosticShadowSuppressionTable { CodeIds: codeIds, FileRanks: fileRanks, ShadowFileFlags: shadowFileFlags }
    output := new DiagnosticIndexOutputTable { Indices: resultIndices }
    return DiagnosticShadowSuppressionIndicesCore(ref source, targetCodeId, ref output)
}

func DiagnosticShadowSuppressionIndicesCore(
    source: &DiagnosticShadowSuppressionTable,
    targetCodeId: int,
    output: &DiagnosticIndexOutputTable): int {
    count := DiagnosticShadowSuppressionCount(ref source)
    if count == 0 {
        return 0
    }

    keptCount := 0
    i := 0
    while i < count {
        fileRank := source.FileRanks[i]
        suppress := targetCodeId > 0 &&
            source.CodeIds[i] == targetCodeId &&
            fileRank > 0 &&
            fileRank < source.ShadowFileFlags.Length &&
            source.ShadowFileFlags[fileRank] != 0

        if !suppress {
            if keptCount < output.Indices.Length {
                output.Indices[keptCount] = i
            }

            keptCount = keptCount + 1
        }

        i = i + 1
    }

    return keptCount
}

func DiagnosticClusterTraitsInto(
    codes: string[],
    messages: string[],
    snippets: string[],
    resultCategories: int[],
    resultSourceConstructs: int[]): int {
    input := new DiagnosticClusterTraitInputTable { Codes: codes, Messages: messages, Snippets: snippets }
    output := new DiagnosticClusterTraitOutputTable { Categories: resultCategories, SourceConstructs: resultSourceConstructs }
    return DiagnosticClusterTraitsCore(ref input, ref output)
}

func DiagnosticClusterTraitsCore(input: &DiagnosticClusterTraitInputTable, output: &DiagnosticClusterTraitOutputTable): int {
    count := DiagnosticClusterTraitCount(ref input, ref output)

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

        i = i + 1
    }

    return count
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
    keys := new DiagnosticClusterGroupingKeyTable { CodeIds: codeIds, SeverityIds: severityIds, CategoryIds: categoryIds, SourceConstructIds: sourceConstructIds, RecipeIds: recipeIds, RiskIds: riskIds, MessagePatternIds: messagePatternIds }
    locations := new DiagnosticClusterLocationTable { Files: files, Lines: lines, Columns: columns }
    scratch := new DiagnosticClusterGroupScratchTable { SlotGroups: slotGroups, GroupKeyIndices: groupKeyIndices }
    groups := new DiagnosticClusterGroupTable { RootIndices: resultRootIndices, Counts: resultCounts }
    return DiagnosticClusterCompactGroupsCore(ref keys, ref locations, ref scratch, ref groups)
}

func DiagnosticClusterCompactGroupsCore(
    keys: &DiagnosticClusterGroupingKeyTable,
    locations: &DiagnosticClusterLocationTable,
    scratch: &DiagnosticClusterGroupScratchTable,
    groups: &DiagnosticClusterGroupTable): int {
    count := DiagnosticClusterInputCount(ref keys, ref locations)

    maxGroups := MinInt(groups.RootIndices.Length, groups.Counts.Length)
    maxGroups = MinInt(maxGroups, scratch.GroupKeyIndices.Length)
    capacity := scratch.SlotGroups.Length
    if count == 0 || maxGroups == 0 || capacity == 0 {
        return 0
    }

    i := 0
    while i < capacity {
        scratch.SlotGroups[i] = -1
        i = i + 1
    }

    groupCount := 0
    index := 0
    while index < count {
        hash := HashDiagnosticClusterCompactGroupingKeyAt(index, ref keys)
        slot := PositiveModulo(hash, capacity)
        groupIndex := -1
        probes := 0

        while probes < capacity {
            candidateGroup := scratch.SlotGroups[slot]
            if candidateGroup < 0 {
                break
            }

            keyIndex := scratch.GroupKeyIndices[candidateGroup]
            if DiagnosticClusterCompactGroupingKeysEqualCore(index, keyIndex, ref keys) {
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
                SortDiagnosticClusterGroupsCore(ref groups, groupCount, ref locations)
                return groupCount
            }

            scratch.GroupKeyIndices[groupCount] = index
            groups.RootIndices[groupCount] = index
            groups.Counts[groupCount] = 1
            scratch.SlotGroups[slot] = groupCount
            groupCount = groupCount + 1
        } else {
            groups.Counts[groupIndex] = groups.Counts[groupIndex] + 1
            if IsDiagnosticClusterRootBeforeCore(index, groups.RootIndices[groupIndex], ref locations) {
                groups.RootIndices[groupIndex] = index
            }
        }

        index = index + 1
    }

    SortDiagnosticClusterGroupsCore(ref groups, groupCount, ref locations)
    return groupCount
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
    keys := new DiagnosticClusterGroupingKeyTable { CodeIds: codeIds, SeverityIds: severityIds, CategoryIds: categoryIds, SourceConstructIds: sourceConstructIds, RecipeIds: recipeIds, RiskIds: riskIds, MessagePatternIds: messagePatternIds }
    locations := new DiagnosticClusterLocationTable { Files: files, Lines: lines, Columns: columns }
    groups := new DiagnosticClusterGroupTable { RootIndices: groupRootIndices, Counts: groupCounts }
    scratch := new DiagnosticClusterMemberScratchTable { SlotGroups: slotGroups, FirstMemberIndices: groupFirstMemberIndices, MemberNextIndices: memberNextIndices }
    output := new DiagnosticClusterMemberOutputTable { Starts: resultStarts, MemberIndices: resultMemberIndices }
    return DiagnosticClusterCompactGroupMembersCore(ref keys, ref locations, ref groups, groupCount, ref scratch, ref output)
}

func DiagnosticClusterCompactGroupMembersCore(
    keys: &DiagnosticClusterGroupingKeyTable,
    locations: &DiagnosticClusterLocationTable,
    groups: &DiagnosticClusterGroupTable,
    groupCount: int,
    scratch: &DiagnosticClusterMemberScratchTable,
    output: &DiagnosticClusterMemberOutputTable): int {
    count := DiagnosticClusterInputCount(ref keys, ref locations)
    groupLimit := MinInt(groupCount, groups.RootIndices.Length)
    groupLimit = MinInt(groupLimit, groups.Counts.Length)
    groupLimit = MinInt(groupLimit, output.Starts.Length)
    groupLimit = MinInt(groupLimit, scratch.FirstMemberIndices.Length)

    if groupCount < 0 || groupLimit != groupCount {
        return -1
    }

    if groupCount == 0 {
        return 0
    }

    if scratch.SlotGroups.Length == 0 || scratch.MemberNextIndices.Length < count {
        return -1
    }

    i := 0
    while i < scratch.SlotGroups.Length {
        scratch.SlotGroups[i] = -1
        i = i + 1
    }

    groupIndex := 0
    totalExpected := 0
    while groupIndex < groupCount {
        rootIndex := groups.RootIndices[groupIndex]
        expectedCount := groups.Counts[groupIndex]
        if rootIndex < 0 || rootIndex >= count || expectedCount < 0 {
            return -1
        }

        totalExpected = totalExpected + expectedCount
        if totalExpected > output.MemberIndices.Length {
            return -1
        }

        scratch.FirstMemberIndices[groupIndex] = -1
        output.Starts[groupIndex] = 0

        hash := HashDiagnosticClusterCompactGroupingKeyAt(rootIndex, ref keys)
        slot := PositiveModulo(hash, scratch.SlotGroups.Length)
        probes := 0
        placed := false
        while probes < scratch.SlotGroups.Length {
            candidateGroup := scratch.SlotGroups[slot]
            if candidateGroup < 0 {
                scratch.SlotGroups[slot] = groupIndex
                placed = true
                break
            }

            candidateRoot := groups.RootIndices[candidateGroup]
            if DiagnosticClusterCompactGroupingKeysEqualCore(rootIndex, candidateRoot, ref keys) {
                return -1
            }

            slot = slot + 1
            if slot == scratch.SlotGroups.Length {
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
        hash := HashDiagnosticClusterCompactGroupingKeyAt(diagnosticIndex, ref keys)
        slot := PositiveModulo(hash, scratch.SlotGroups.Length)
        probes := 0
        groupIndex = -1
        while probes < scratch.SlotGroups.Length {
            candidateGroup := scratch.SlotGroups[slot]
            if candidateGroup < 0 {
                break
            }

            rootIndex := groups.RootIndices[candidateGroup]
            if DiagnosticClusterCompactGroupingKeysEqualCore(diagnosticIndex, rootIndex, ref keys) {
                groupIndex = candidateGroup
                break
            }

            slot = slot + 1
            if slot == scratch.SlotGroups.Length {
                slot = 0
            }

            probes = probes + 1
        }

        if groupIndex < 0 {
            return -1
        }

        output.Starts[groupIndex] = output.Starts[groupIndex] + 1
        scratch.MemberNextIndices[diagnosticIndex] = -1
        firstMember := scratch.FirstMemberIndices[groupIndex]
        if firstMember < 0 || IsDiagnosticClusterRootBeforeCore(diagnosticIndex, firstMember, ref locations) {
            scratch.MemberNextIndices[diagnosticIndex] = firstMember
            scratch.FirstMemberIndices[groupIndex] = diagnosticIndex
        } else {
            previousMember := firstMember
            currentMember := scratch.MemberNextIndices[previousMember]
            while currentMember >= 0
                && !IsDiagnosticClusterRootBeforeCore(diagnosticIndex, currentMember, ref locations) {
                previousMember = currentMember
                currentMember = scratch.MemberNextIndices[currentMember]
            }

            scratch.MemberNextIndices[diagnosticIndex] = currentMember
            scratch.MemberNextIndices[previousMember] = diagnosticIndex
        }

        diagnosticIndex = diagnosticIndex + 1
    }

    offset := 0
    groupIndex = 0
    while groupIndex < groupCount {
        expectedCount := groups.Counts[groupIndex]
        if output.Starts[groupIndex] != expectedCount {
            return -1
        }

        output.Starts[groupIndex] = offset
        written := 0
        memberIndex := scratch.FirstMemberIndices[groupIndex]
        while memberIndex >= 0 {
            output.MemberIndices[offset + written] = memberIndex
            written = written + 1
            memberIndex = scratch.MemberNextIndices[memberIndex]
        }

        if written != expectedCount {
            return -1
        }

        offset = offset + written
        groupIndex = groupIndex + 1
    }

    return offset
}

func SortDiagnosticClusterGroupsCore(groups: &DiagnosticClusterGroupTable, groupCount: int, locations: &DiagnosticClusterLocationTable): void {
    i := 1
    while i < groupCount {
        root := groups.RootIndices[i]
        count := groups.Counts[i]
        j := i - 1

        while j >= 0 && IsDiagnosticClusterGroupBeforeCore(root, count, groups.RootIndices[j], groups.Counts[j], ref locations) {
            groups.RootIndices[j + 1] = groups.RootIndices[j]
            groups.Counts[j + 1] = groups.Counts[j]
            j = j - 1
        }

        groups.RootIndices[j + 1] = root
        groups.Counts[j + 1] = count
        i = i + 1
    }
}

func IsDiagnosticClusterGroupBeforeCore(
    leftRoot: int,
    leftCount: int,
    rightRoot: int,
    rightCount: int,
    locations: &DiagnosticClusterLocationTable): bool {
    if leftCount != rightCount {
        return leftCount > rightCount
    }

    fileCompare := String.Compare(locations.Files[leftRoot], locations.Files[rightRoot], StringComparison.OrdinalIgnoreCase)
    if fileCompare != 0 {
        return fileCompare < 0
    }

    if locations.Lines[leftRoot] != locations.Lines[rightRoot] {
        return locations.Lines[leftRoot] < locations.Lines[rightRoot]
    }

    return locations.Columns[leftRoot] < locations.Columns[rightRoot]
}

func IsDiagnosticClusterRootBeforeCore(
    left: int,
    right: int,
    locations: &DiagnosticClusterLocationTable): bool {
    if locations.Lines[left] != locations.Lines[right] {
        return locations.Lines[left] < locations.Lines[right]
    }

    if locations.Columns[left] != locations.Columns[right] {
        return locations.Columns[left] < locations.Columns[right]
    }

    return String.Compare(locations.Files[left], locations.Files[right], StringComparison.OrdinalIgnoreCase) < 0
}

func DiagnosticClusterCompactGroupingKeysEqualCore(
    left: int,
    right: int,
    keys: &DiagnosticClusterGroupingKeyTable): bool {
    return keys.SeverityIds[left] == keys.SeverityIds[right]
        && keys.CodeIds[left] == keys.CodeIds[right]
        && keys.CategoryIds[left] == keys.CategoryIds[right]
        && keys.SourceConstructIds[left] == keys.SourceConstructIds[right]
        && keys.RecipeIds[left] == keys.RecipeIds[right]
        && keys.RiskIds[left] == keys.RiskIds[right]
        && keys.MessagePatternIds[left] == keys.MessagePatternIds[right]
}

func HashDiagnosticClusterCompactGroupingKeyAt(index: int, keys: &DiagnosticClusterGroupingKeyTable): int {
    return HashDiagnosticClusterCompactGroupingKey(
        keys.SeverityIds[index],
        keys.CodeIds[index],
        keys.CategoryIds[index],
        keys.SourceConstructIds[index],
        keys.RecipeIds[index],
        keys.RiskIds[index],
        keys.MessagePatternIds[index])
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

func IsWhitespace(ch: char): bool {
    return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n'
}

func MinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

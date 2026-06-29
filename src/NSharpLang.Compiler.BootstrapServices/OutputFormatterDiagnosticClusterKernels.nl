namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text

public class DiagnosticClusterTraitClassification {
    categoriesValue: int[]
    sourceConstructsValue: int[]

    Categories: int[] => categoriesValue
    SourceConstructs: int[] => sourceConstructsValue

    constructor(Categories: int[], SourceConstructs: int[]) {
        categoriesValue = Categories
        sourceConstructsValue = SourceConstructs
    }

    public func Deconstruct(out Categories: int[], out SourceConstructs: int[]) {
        Categories = categoriesValue
        SourceConstructs = sourceConstructsValue
    }
}

public class OutputFormatterDiagnosticClusterKernels {
    public static func ClassifyDiagnosticClusterTraits(
        diagnostics: IReadOnlyList<DiagnosticResult>): DiagnosticClusterTraitClassification {
        items := DiagnosticList(diagnostics)
        count := items.Count
        categories := new int[](count)
        sourceConstructs := new int[](count)

        i := 0
        while i < count {
            diagnostic := items[i]
            category := ClassifyDiagnosticCategory(
                TextOrEmpty(diagnostic.Code),
                TextOrEmpty(diagnostic.Message))
            sourceConstruct := 8

            if category == 2 {
                sourceConstruct = 4
            } else {
                sourceConstruct = InferDiagnosticSourceConstruct(TextOrEmpty(diagnostic.SourceSnippet))
            }

            categories[i] = category
            sourceConstructs[i] = sourceConstruct
            i = i + 1
        }

        return new DiagnosticClusterTraitClassification(categories, sourceConstructs)
    }

    public static func GroupDiagnosticClusters(
        diagnostics: IReadOnlyList<DiagnosticResult>,
        categoryIds: int[],
        sourceConstructIds: int[],
        messagePatterns: string[]): DiagnosticClusterGrouping {
        items := DiagnosticList(diagnostics)
        count := items.Count
        if categoryIds.Length < count || sourceConstructIds.Length < count || messagePatterns.Length < count {
            throw new InvalidOperationException("N# diagnostic cluster grouping kernel received incomplete classification inputs.")
        }

        scratch := new DiagnosticClusterGroupingScratch()
        scratch.EnsureCapacity(count)
        scratch.ResetIds()

        i := 0
        while i < count {
            diagnostic := items[i]
            category := categoryIds[i]

            scratch.CodeIds[i] = scratch.GetCodeId(TextOrEmpty(diagnostic.Code))
            scratch.SeverityIds[i] = scratch.GetSeverityId(TextOrEmpty(diagnostic.Severity))
            scratch.CategoryIds[i] = category
            scratch.SourceConstructIds[i] = sourceConstructIds[i]
            scratch.RecipeIds[i] = category
            scratch.RiskIds[i] = category
            scratch.MessagePatternIds[i] = scratch.GetMessagePatternId(TextOrEmpty(messagePatterns[i]))
            scratch.Files[i] = TextOrEmpty(diagnostic.File)
            scratch.Lines[i] = diagnostic.Line
            scratch.Columns[i] = diagnostic.Column

            i = i + 1
        }

        groupCount := CompactDiagnosticClusterGroups(scratch, count)
        memberTotal := CompactDiagnosticClusterGroupMembers(scratch, count, groupCount)
        if memberTotal < 0 {
            throw new InvalidOperationException("N# diagnostic cluster grouping kernel failed to compact group members.")
        }

        return new DiagnosticClusterGrouping(
            groupCount,
            scratch.RootIndices,
            scratch.Counts,
            scratch.MemberStarts,
            scratch.MemberIndices)
    }

    public static func NormalizeMessagePattern(message: string): string {
        if string.IsNullOrWhiteSpace(message) {
            return "unknown-message"
        }

        builder := new StringBuilder(message.Length)
        inQuoted := false
        index := 0
        while index < message.Length {
            ch := message[index]
            if ch == '\'' || ch == '"' {
                inQuoted = !inQuoted
                if inQuoted {
                    builder.Append("{value}")
                }

                index = index + 1
                continue
            }

            if !inQuoted {
                if char.IsDigit(ch) {
                    builder.Append('#')
                } else {
                    builder.Append(ch)
                }
            }

            index = index + 1
        }

        return builder.ToString().Trim()
    }

    public static func CreateDiagnosticClusterId(
        code: string,
        severity: string,
        category: string,
        sourceConstruct: string,
        recipe: string,
        messagePattern: string): string {
        key := code + "|" + severity + "|" + category + "|" + sourceConstruct + "|" + recipe + "|" + messagePattern
        hash := 17
        index := 0
        while index < key.Length {
            hash = hash * 31 + Convert.ToInt32(key[index])
            index = index + 1
        }

        if hash < 0 {
            hash = 0 - hash
        }

        return "diag-" + PositiveIntToLowerHex(hash)
    }

    public static func BuildDiagnosticClusterNextCommand(root: DiagnosticResult): string {
        fileText := EscapeCommandArgument(root.File)
        return "nlc query inspect --file " + fileText + " --pos " + root.Line.ToString() + ":" + root.Column.ToString()
    }

    static func DiagnosticList(diagnostics: IReadOnlyList<DiagnosticResult>): List<DiagnosticResult> {
        items := new List<DiagnosticResult>()
        foreach diagnosticValue in diagnostics {
            items.Add((DiagnosticResult)diagnosticValue)
        }

        return items
    }

    static func CompactDiagnosticClusterGroups(scratch: DiagnosticClusterGroupingScratch, count: int): int {
        maxGroups := MinInt(scratch.RootIndices.Length, scratch.Counts.Length)
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
            hash := HashDiagnosticClusterCompactGroupingKeyAt(index, scratch)
            slot := PositiveModulo(hash, capacity)
            groupIndex := -1
            probes := 0

            while probes < capacity {
                candidateGroup := scratch.SlotGroups[slot]
                if candidateGroup < 0 {
                    break
                }

                keyIndex := scratch.GroupKeyIndices[candidateGroup]
                if DiagnosticClusterCompactGroupingKeysEqual(index, keyIndex, scratch) {
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
                    SortDiagnosticClusterGroups(scratch, groupCount)
                    return groupCount
                }

                scratch.GroupKeyIndices[groupCount] = index
                scratch.RootIndices[groupCount] = index
                scratch.Counts[groupCount] = 1
                scratch.SlotGroups[slot] = groupCount
                groupCount = groupCount + 1
            } else {
                scratch.Counts[groupIndex] = scratch.Counts[groupIndex] + 1
                if IsDiagnosticClusterRootBefore(index, scratch.RootIndices[groupIndex], scratch) {
                    scratch.RootIndices[groupIndex] = index
                }
            }

            index = index + 1
        }

        SortDiagnosticClusterGroups(scratch, groupCount)
        return groupCount
    }

    static func CompactDiagnosticClusterGroupMembers(
        scratch: DiagnosticClusterGroupingScratch,
        count: int,
        groupCount: int): int {
        groupLimit := MinInt(groupCount, scratch.RootIndices.Length)
        groupLimit = MinInt(groupLimit, scratch.Counts.Length)
        groupLimit = MinInt(groupLimit, scratch.MemberStarts.Length)
        groupLimit = MinInt(groupLimit, scratch.GroupFirstMemberIndices.Length)

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
            rootIndex := scratch.RootIndices[groupIndex]
            expectedCount := scratch.Counts[groupIndex]
            if rootIndex < 0 {
                return -1
            }

            if rootIndex >= count {
                return -1
            }

            if expectedCount < 0 {
                return -1
            }

            totalExpected = totalExpected + expectedCount
            if totalExpected > scratch.MemberIndices.Length {
                return -1
            }

            scratch.GroupFirstMemberIndices[groupIndex] = -1
            scratch.MemberStarts[groupIndex] = 0

            hash := HashDiagnosticClusterCompactGroupingKeyAt(rootIndex, scratch)
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

                candidateRoot := scratch.RootIndices[candidateGroup]
                if DiagnosticClusterCompactGroupingKeysEqual(rootIndex, candidateRoot, scratch) {
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
            hash := HashDiagnosticClusterCompactGroupingKeyAt(diagnosticIndex, scratch)
            slot := PositiveModulo(hash, scratch.SlotGroups.Length)
            probes := 0
            groupIndex = -1
            while probes < scratch.SlotGroups.Length {
                candidateGroup := scratch.SlotGroups[slot]
                if candidateGroup < 0 {
                    break
                }

                rootIndex := scratch.RootIndices[candidateGroup]
                if DiagnosticClusterCompactGroupingKeysEqual(diagnosticIndex, rootIndex, scratch) {
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

            scratch.MemberStarts[groupIndex] = scratch.MemberStarts[groupIndex] + 1
            scratch.MemberNextIndices[diagnosticIndex] = -1
            firstMember := scratch.GroupFirstMemberIndices[groupIndex]
            insertBeforeFirst := firstMember < 0
            if !insertBeforeFirst {
                insertBeforeFirst = IsDiagnosticClusterRootBefore(diagnosticIndex, firstMember, scratch)
            }

            if insertBeforeFirst {
                scratch.MemberNextIndices[diagnosticIndex] = firstMember
                scratch.GroupFirstMemberIndices[groupIndex] = diagnosticIndex
            } else {
                previousMember := firstMember
                currentMember := scratch.MemberNextIndices[previousMember]
                while currentMember >= 0 {
                    if IsDiagnosticClusterRootBefore(diagnosticIndex, currentMember, scratch) {
                        break
                    }

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
            expectedCount := scratch.Counts[groupIndex]
            if scratch.MemberStarts[groupIndex] != expectedCount {
                return -1
            }

            scratch.MemberStarts[groupIndex] = offset
            written := 0
            memberIndex := scratch.GroupFirstMemberIndices[groupIndex]
            while memberIndex >= 0 {
                scratch.MemberIndices[offset + written] = memberIndex
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

    static func SortDiagnosticClusterGroups(scratch: DiagnosticClusterGroupingScratch, groupCount: int) {
        i := 1
        while i < groupCount {
            root := scratch.RootIndices[i]
            count := scratch.Counts[i]
            j := i - 1

            while j >= 0 {
                if !IsDiagnosticClusterGroupBefore(root, count, scratch.RootIndices[j], scratch.Counts[j], scratch) {
                    break
                }

                scratch.RootIndices[j + 1] = scratch.RootIndices[j]
                scratch.Counts[j + 1] = scratch.Counts[j]
                j = j - 1
            }

            scratch.RootIndices[j + 1] = root
            scratch.Counts[j + 1] = count
            i = i + 1
        }
    }

    static func IsDiagnosticClusterGroupBefore(
        leftRoot: int,
        leftCount: int,
        rightRoot: int,
        rightCount: int,
        scratch: DiagnosticClusterGroupingScratch): bool {
        if leftCount != rightCount {
            return leftCount > rightCount
        }

        fileCompare := String.Compare(scratch.Files[leftRoot], scratch.Files[rightRoot], StringComparison.OrdinalIgnoreCase)
        if fileCompare != 0 {
            return fileCompare < 0
        }

        if scratch.Lines[leftRoot] != scratch.Lines[rightRoot] {
            return scratch.Lines[leftRoot] < scratch.Lines[rightRoot]
        }

        return scratch.Columns[leftRoot] < scratch.Columns[rightRoot]
    }

    static func IsDiagnosticClusterRootBefore(
        left: int,
        right: int,
        scratch: DiagnosticClusterGroupingScratch): bool {
        if scratch.Lines[left] != scratch.Lines[right] {
            return scratch.Lines[left] < scratch.Lines[right]
        }

        if scratch.Columns[left] != scratch.Columns[right] {
            return scratch.Columns[left] < scratch.Columns[right]
        }

        return String.Compare(scratch.Files[left], scratch.Files[right], StringComparison.OrdinalIgnoreCase) < 0
    }

    static func DiagnosticClusterCompactGroupingKeysEqual(
        left: int,
        right: int,
        scratch: DiagnosticClusterGroupingScratch): bool {
        return scratch.SeverityIds[left] == scratch.SeverityIds[right]
            && scratch.CodeIds[left] == scratch.CodeIds[right]
            && scratch.CategoryIds[left] == scratch.CategoryIds[right]
            && scratch.SourceConstructIds[left] == scratch.SourceConstructIds[right]
            && scratch.RecipeIds[left] == scratch.RecipeIds[right]
            && scratch.RiskIds[left] == scratch.RiskIds[right]
            && scratch.MessagePatternIds[left] == scratch.MessagePatternIds[right]
    }

    static func HashDiagnosticClusterCompactGroupingKeyAt(index: int, scratch: DiagnosticClusterGroupingScratch): int {
        return HashDiagnosticClusterCompactGroupingKey(
            scratch.SeverityIds[index],
            scratch.CodeIds[index],
            scratch.CategoryIds[index],
            scratch.SourceConstructIds[index],
            scratch.RecipeIds[index],
            scratch.RiskIds[index],
            scratch.MessagePatternIds[index])
    }

    static func HashDiagnosticClusterCompactGroupingKey(
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

    static func PositiveIntToLowerHex(value: int): string {
        if value == 0 {
            return "0"
        }

        digits := "0123456789abcdef"
        result := ""
        current := value
        while current > 0 {
            digit := current % 16
            result = digits.Substring(digit, 1) + result
            current = current / 16
        }

        return result
    }

    static func EscapeCommandArgument(value: string): string {
        if string.IsNullOrWhiteSpace(value) {
            return "\"\""
        }

        index := 0
        while index < value.Length {
            if !IsUnquotedCommandArgumentChar(value[index]) {
                return QuoteCommandArgument(value)
            }

            index = index + 1
        }

        return value
    }

    static func QuoteCommandArgument(value: string): string {
        builder := new StringBuilder(value.Length + 2)
        builder.Append('"')

        index := 0
        while index < value.Length {
            ch := value[index]
            if ch == '\\' {
                builder.Append('\\')
                builder.Append('\\')
            } else if ch == '"' {
                builder.Append('\\')
                builder.Append('"')
            } else {
                builder.Append(ch)
            }

            index = index + 1
        }

        builder.Append('"')
        return builder.ToString()
    }

    static func IsUnquotedCommandArgumentChar(ch: char): bool {
        return char.IsLetterOrDigit(ch) || ch == '/' || ch == '.' || ch == '_' || ch == '-'
    }

    static func PositiveModulo(value: int, divisor: int): int {
        result := value % divisor
        if result < 0 {
            return result + divisor
        }

        return result
    }

    static func ClassifyDiagnosticCategory(code: string, message: string): int {
        if code == "NL102" {
            if ContainsChar(message, ';') || ContainsIgnoreCase(message, "semicolon") {
                return 0
            }

            return 1
        }

        if code == "NL703" {
            return 2
        }

        if code == "NL301" {
            return 3
        }

        if code == "NL412" {
            return 3
        }

        if code == "NL201" {
            return 4
        }

        if code == "NL302" {
            return 4
        }

        if code == "NL202" {
            return 5
        }

        if code == "NL303" {
            return 6
        }

        if ContainsIgnoreCase(message, "expected token") {
            if ContainsChar(message, ';') || ContainsIgnoreCase(message, "semicolon") {
                return 0
            }

            return 1
        }

        if ContainsIgnoreCase(message, "missing") {
            if ContainsChar(message, ';') || ContainsIgnoreCase(message, "semicolon") {
                return 0
            }

            return 1
        }

        if ContainsIgnoreCase(message, "circular import") {
            return 2
        }

        if ContainsIgnoreCase(message, "undefined variable") {
            return 3
        }

        if ContainsIgnoreCase(message, "undefined symbol") {
            return 3
        }

        if ContainsIgnoreCase(message, "type not found") {
            return 4
        }

        if ContainsIgnoreCase(message, "undefined type") {
            return 4
        }

        if ContainsIgnoreCase(message, "cannot resolve type") {
            return 4
        }

        if ContainsIgnoreCase(message, "type mismatch") {
            return 5
        }

        if ContainsIgnoreCase(message, "member") {
            return 6
        }

        if ContainsIgnoreCase(message, "method") {
            return 6
        }

        return 7
    }

    static func InferDiagnosticSourceConstruct(snippet: string): int {
        start := TrimStartIndex(snippet)

        if StartsWithIgnoreCase(snippet, start, "let ") {
            return 0
        }

        if ContainsOrdinal(snippet, ":=") {
            return 0
        }

        declarationStart := StripLeadingDeclarationModifiers(snippet, start)
        if StartsWithIgnoreCase(snippet, declarationStart, "func ") {
            return 1
        }

        if StartsWithIgnoreCase(snippet, declarationStart, "func* ") {
            return 1
        }

        if StartsWithIgnoreCase(snippet, start, "class ") {
            return 2
        }

        if StartsWithIgnoreCase(snippet, start, "interface ") {
            return 3
        }

        if StartsWithIgnoreCase(snippet, start, "import ") {
            return 4
        }

        if StartsWithIgnoreCase(snippet, start, "using ") {
            return 4
        }

        if StartsWithIgnoreCase(snippet, start, "return ") {
            return 5
        }

        if StartsWithIgnoreCase(snippet, start, "if ") {
            return 6
        }

        if StartsWithIgnoreCase(snippet, start, "for ") {
            return 6
        }

        if StartsWithIgnoreCase(snippet, start, "while ") {
            return 6
        }

        if StartsWithIgnoreCase(snippet, start, "match ") {
            return 6
        }

        if ContainsCharFrom(snippet, '(', start) {
            if ContainsCharFrom(snippet, ')', start) {
                return 7
            }
        }

        return 8
    }

    static func StripLeadingDeclarationModifiers(snippet: string, start: int): int {
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

    static func ContainsIgnoreCase(text: string, needle: string): bool {
        return text.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0
    }

    static func StartsWithIgnoreCase(text: string, start: int, needle: string): bool {
        if start < 0 {
            return false
        }

        if start + needle.Length > text.Length {
            return false
        }

        return String.Compare(text, start, needle, 0, needle.Length, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func ContainsOrdinal(text: string, needle: string): bool {
        return text.IndexOf(needle, StringComparison.Ordinal) >= 0
    }

    static func ContainsChar(text: string, ch: char): bool {
        return ContainsCharFrom(text, ch, 0)
    }

    static func ContainsCharFrom(text: string, ch: char, start: int): bool {
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

    static func TrimStartIndex(text: string): int {
        return TrimStartIndexFrom(text, 0)
    }

    static func TrimStartIndexFrom(text: string, start: int): int {
        i := start
        if i < 0 {
            i = 0
        }

        while i < text.Length {
            if !IsWhitespace(text[i]) {
                break
            }

            i = i + 1
        }

        return i
    }

    static func IsWhitespace(ch: char): bool {
        return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n'
    }

    static func MinInt(left: int, right: int): int {
        if left < right {
            return left
        }

        return right
    }

    static func TextOrEmpty(value: string?): string {
        return value ?? ""
    }
}

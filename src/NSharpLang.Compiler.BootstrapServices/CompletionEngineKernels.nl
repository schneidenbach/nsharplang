namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text

public class CompletionReceiverClassification {
    isMemberAccessValue: bool
    receiverValue: string?

    IsMemberAccess: bool => isMemberAccessValue
    Receiver: string? => receiverValue

    constructor(IsMemberAccess: bool, Receiver: string?) {
        isMemberAccessValue = IsMemberAccess
        receiverValue = Receiver
    }
}

public class CompletionEngineKernels {
    public static func ClassifyCompletionReceiver(beforeCursor: string): CompletionReceiverClassification {
        if !IsCompletionMemberAccessContext(beforeCursor) {
            return new CompletionReceiverClassification(false, null)
        }

        receiver := ExtractCompletionReceiver(beforeCursor)
        if receiver.Length == 0 {
            return new CompletionReceiverClassification(true, null)
        }

        return new CompletionReceiverClassification(true, receiver)
    }

    public static func AddGroupedCompletionItemsByKind(
        items: List<CompletionItem>,
        completions: Dictionary<string, List<CompletionItem>>) {
        if items.Count == 0 {
            return
        }

        order := new List<string>()
        groups := new Dictionary<string, List<CompletionItem>>(StringComparer.Ordinal)

        i := 0
        while i < items.Count {
            item := items[i]
            key := PluralizeCompletionKind(item.Kind)
            group := new List<CompletionItem>()
            if !groups.TryGetValue(key, out group) {
                group = new List<CompletionItem>()
                groups.Add(key, group)
                order.Add(key)
            }

            group.Add(item)
            i = i + 1
        }

        j := 0
        while j < order.Count {
            key := order[j]
            group := new List<CompletionItem>()
            groups.TryGetValue(key, out group)
            if completions.ContainsKey(key) {
                removed := new List<CompletionItem>()
                completions.Remove(key, out removed)
            }
            completions.Add(key, group)
            j = j + 1
        }
    }

    static func PluralizeCompletionKind(kind: string): string {
        if kind == "property" {
            return "properties"
        }

        if kind == "class" {
            return "classes"
        }

        return kind + "s"
    }

    static func IsCompletionMemberAccessContext(beforeCursor: string): bool {
        end := TrimCompletionReceiverEnd(beforeCursor, beforeCursor.Length)
        if end <= 0 {
            return false
        }

        if beforeCursor[end - 1] == '.' {
            return true
        }

        lastDot := LastCompletionReceiverCharBefore(beforeCursor, '.', end)
        if lastDot > 0 {
            beforeDotEnd := TrimCompletionReceiverEnd(beforeCursor, lastDot)
            if beforeDotEnd > 0 && IsCompletionReceiverIdentifierChar(beforeCursor[beforeDotEnd - 1]) {
                return true
            }
        }

        return false
    }

    static func ExtractCompletionReceiver(beforeCursor: string): string {
        end := TrimCompletionReceiverEnd(beforeCursor, beforeCursor.Length)
        dotIndex := FindLastCompletionTopLevelDot(beforeCursor, end)
        if dotIndex < 0 {
            return ""
        }

        withoutDotEnd := TrimCompletionReceiverEnd(beforeCursor, dotIndex)
        return ExtractCompletionExpressionSuffix(beforeCursor, withoutDotEnd)
    }

    static func ExtractCompletionExpressionSuffix(text: string, end: int): string {
        literalReceiver := TryExtractCompletionLiteralSuffix(text, end)
        if literalReceiver.Length > 0 {
            return literalReceiver
        }

        start := end - 1
        parenDepth := 0
        consumed := false

        while start >= 0 {
            current := text[start]
            if current == ')' {
                parenDepth = parenDepth + 1
                consumed = true
                start = start - 1
                continue
            }

            if current == '(' {
                if parenDepth == 0 {
                    break
                }

                parenDepth = parenDepth - 1
                start = start - 1
                continue
            }

            if parenDepth > 0 {
                start = start - 1
                continue
            }

            if IsCompletionReceiverIdentifierChar(current) || current == '.' {
                consumed = true
                start = start - 1
                continue
            }

            break
        }

        if !consumed || parenDepth != 0 {
            return ""
        }

        start = start + 1
        if start < end {
            return NormalizeCompletionReceiverCalls(text, start, end)
        }

        return ""
    }

    static func TryExtractCompletionLiteralSuffix(text: string, end: int): string {
        if end <= 0 {
            return ""
        }

        if EndsCompletionReceiverWith(text, end, "true") {
            start := end - 4
            if IsCompletionReceiverTokenBoundary(text, start)
                && !HasCompletionLineCommentBefore(text, start) {
                return text.Substring(start, 4)
            }
        }

        if EndsCompletionReceiverWith(text, end, "false") {
            start := end - 5
            if IsCompletionReceiverTokenBoundary(text, start)
                && !HasCompletionLineCommentBefore(text, start) {
                return text.Substring(start, 5)
            }
        }

        current := text[end - 1]
        if current == '"' {
            rawStart := FindCompletionRawStringStart(text, end)
            if rawStart >= 0 && !HasCompletionLineCommentBefore(text, rawStart) {
                return text.Substring(rawStart, end - rawStart)
            }

            stringStart := FindCompletionStringStart(text, end)
            if stringStart >= 0 && !HasCompletionLineCommentBefore(text, stringStart) {
                return text.Substring(stringStart, end - stringStart)
            }
        }

        if current == '\'' {
            charStart := FindCompletionCharStart(text, end)
            if charStart >= 0 && !HasCompletionLineCommentBefore(text, charStart) {
                return text.Substring(charStart, end - charStart)
            }
        }

        numericStart := FindCompletionNumericLiteralStart(text, end)
        if numericStart >= 0 && !HasCompletionLineCommentBefore(text, numericStart) {
            return text.Substring(numericStart, end - numericStart)
        }

        return ""
    }

    static func NormalizeCompletionReceiverCalls(text: string, start: int, end: int): string {
        builder := new StringBuilder(end - start)
        index := start

        while index < end {
            current := text[index]
            builder.Append(current)
            if current != '(' {
                index = index + 1
                continue
            }

            parenDepth := 1
            index = index + 1
            while index < end && parenDepth > 0 {
                if text[index] == '(' {
                    parenDepth = parenDepth + 1
                } else if text[index] == ')' {
                    parenDepth = parenDepth - 1
                }

                index = index + 1
            }

            builder.Append(')')
        }

        return builder.ToString()
    }

    static func FindCompletionRawStringStart(text: string, end: int): int {
        if end < 6
            || text[end - 1] != '"'
            || text[end - 2] != '"'
            || text[end - 3] != '"' {
            return -1
        }

        position := end - 6
        while position >= 0 {
            if text[position] == '"' && text[position + 1] == '"' && text[position + 2] == '"' {
                while position > 0 && text[position - 1] == '$' {
                    position = position - 1
                }

                return position
            }

            position = position - 1
        }

        return -1
    }

    static func FindCompletionStringStart(text: string, end: int): int {
        position := end - 2

        while position >= 0 {
            if text[position] == '"' && !IsCompletionEscaped(text, position) {
                if position > 0 && text[position - 1] == '$' {
                    return position - 1
                }

                return position
            }

            position = position - 1
        }

        return -1
    }

    static func FindCompletionCharStart(text: string, end: int): int {
        position := end - 2

        while position >= 0 {
            if text[position] == '\'' && !IsCompletionEscaped(text, position) {
                return position
            }

            position = position - 1
        }

        return -1
    }

    static func IsCompletionEscaped(text: string, index: int): bool {
        slashCount := 0
        position := index - 1

        while position >= 0 && text[position] == '\\' {
            slashCount = slashCount + 1
            position = position - 1
        }

        return (slashCount & 1) == 1
    }

    static func FindCompletionNumericLiteralStart(text: string, end: int): int {
        position := end - 1

        while position >= 0 {
            if IsCompletionDigit(text[position])
                && IsCompletionNumericStartBoundary(text, position)
                && ScanCompletionNumber(text, position, end) == end {
                return position
            }

            position = position - 1
        }

        return -1
    }

    static func ScanCompletionNumber(text: string, position: int, end: int): int {
        if text[position] == '0'
            && position + 1 < end
            && (text[position + 1] == 'x' || text[position + 1] == 'X') {
            position = position + 2
            while position < end && (IsCompletionHexDigit(text[position]) || text[position] == '_') {
                position = position + 1
            }

            return ConsumeCompletionIntegerSuffix(text, position, end)
        }

        if text[position] == '0'
            && position + 1 < end
            && (text[position + 1] == 'b' || text[position + 1] == 'B') {
            position = position + 2
            while position < end && (text[position] == '0' || text[position] == '1' || text[position] == '_') {
                position = position + 1
            }

            return ConsumeCompletionIntegerSuffix(text, position, end)
        }

        isFloat := false
        while position < end
            && (IsCompletionDigit(text[position]) || text[position] == '.' || text[position] == '_') {
            if text[position] == '.' {
                if position + 1 < end && text[position + 1] == '.' {
                    break
                }

                if position + 1 >= end || !IsCompletionDigit(text[position + 1]) {
                    break
                }

                isFloat = true
            }

            position = position + 1
        }

        if position < end && (text[position] == 'e' || text[position] == 'E') {
            isFloat = true
            position = position + 1
            if position < end && (text[position] == '+' || text[position] == '-') {
                position = position + 1
            }

            while position < end && (IsCompletionDigit(text[position]) || text[position] == '_') {
                position = position + 1
            }
        }

        if isFloat {
            return ConsumeCompletionFloatSuffix(text, position, end)
        }

        if position < end && (text[position] == 'm' || text[position] == 'M') {
            return position + 1
        }

        return ConsumeCompletionIntegerSuffix(text, position, end)
    }

    static func IsCompletionNumericStartBoundary(text: string, start: int): bool {
        if start <= 0 {
            return true
        }

        previous := text[start - 1]
        if previous == '.' {
            return start < 2 || !IsCompletionDigit(text[start - 2])
        }

        if previous == '+' || previous == '-' {
            if start >= 3 {
                marker := text[start - 2]
                if (marker == 'e' || marker == 'E') && IsCompletionDigit(text[start - 3]) {
                    return false
                }
            }

            return true
        }

        return !IsCompletionReceiverIdentifierChar(previous)
    }

    static func ConsumeCompletionFloatSuffix(text: string, position: int, end: int): int {
        if position < end
            && (text[position] == 'f'
                || text[position] == 'F'
                || text[position] == 'd'
                || text[position] == 'D'
                || text[position] == 'm'
                || text[position] == 'M') {
            return position + 1
        }

        return position
    }

    static func ConsumeCompletionIntegerSuffix(text: string, position: int, end: int): int {
        if position < end && (text[position] == 'u' || text[position] == 'U') {
            position = position + 1
            if position < end && (text[position] == 'l' || text[position] == 'L') {
                position = position + 1
            }

            return position
        }

        if position < end && (text[position] == 'l' || text[position] == 'L') {
            position = position + 1
            if position < end && (text[position] == 'u' || text[position] == 'U') {
                position = position + 1
            }

            return position
        }

        return position
    }

    static func FindLastCompletionTopLevelDot(text: string, end: int): int {
        parenDepth := 0
        index := end - 1

        while index >= 0 {
            current := text[index]
            if current == ')' {
                parenDepth = parenDepth + 1
            } else if current == '(' {
                if parenDepth > 0 {
                    parenDepth = parenDepth - 1
                }
            } else if current == '.' && parenDepth == 0 {
                return index
            }

            index = index - 1
        }

        return -1
    }

    static func LastCompletionReceiverCharBefore(text: string, ch: char, end: int): int {
        index := end - 1

        while index >= 0 {
            if text[index] == ch {
                return index
            }

            index = index - 1
        }

        return -1
    }

    static func TrimCompletionReceiverEnd(text: string, end: int): int {
        if end > text.Length {
            end = text.Length
        }

        while end > 0 && IsCompletionReceiverWhitespace(text[end - 1]) {
            end = end - 1
        }

        return end
    }

    static func EndsCompletionReceiverWith(text: string, end: int, suffix: string): bool {
        if end < suffix.Length {
            return false
        }

        start := end - suffix.Length
        i := 0
        while i < suffix.Length {
            if text[start + i] != suffix[i] {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func IsCompletionReceiverTokenBoundary(text: string, start: int): bool {
        return start <= 0 || !IsCompletionReceiverIdentifierChar(text[start - 1])
    }

    static func HasCompletionLineCommentBefore(text: string, start: int): bool {
        position := 0
        last := start - 1

        while position < last {
            if text[position] == '/' && text[position + 1] == '/' {
                return true
            }

            position = position + 1
        }

        return false
    }

    static func IsCompletionReceiverIdentifierChar(ch: char): bool {
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

    static func IsCompletionReceiverWhitespace(ch: char): bool {
        if ch == ' ' {
            return true
        }

        if ch <= '~' {
            return ch >= '\t' && ch <= '\r'
        }

        return Char.IsWhiteSpace(ch)
    }

    static func IsCompletionDigit(ch: char): bool {
        return ch >= '0' && ch <= '9'
    }

    static func IsCompletionHexDigit(ch: char): bool {
        return (ch >= '0' && ch <= '9')
            || (ch >= 'a' && ch <= 'f')
            || (ch >= 'A' && ch <= 'F')
    }
}

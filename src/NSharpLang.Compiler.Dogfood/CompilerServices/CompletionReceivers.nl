import System
import System.Text

func CodeIntelligenceCompletionReceiverChecksumInto(
    prefixes: string[],
    resultContexts: int[],
    resultReceivers: string[]): int {
    count := CodeIntelligenceCompletionReceiversInto(prefixes, resultContexts, resultReceivers)
    checksum := count
    i := 0

    while i < count {
        checksum = checksum + resultContexts[i] * 31 + resultReceivers[i].Length * 17
        i = i + 1
    }

    return checksum
}

func CodeIntelligenceCompletionReceiversInto(
    prefixes: string[],
    resultContexts: int[],
    resultReceivers: string[]): int {
    count := CompletionReceiverMinInt(prefixes.Length, resultContexts.Length)
    count = CompletionReceiverMinInt(count, resultReceivers.Length)

    i := 0
    while i < count {
        prefix := prefixes[i]
        context := 0
        receiver := ""

        if IsCodeIntelligenceCompletionMemberAccessContext(prefix) {
            context = 1
            receiver = ExtractCodeIntelligenceCompletionReceiver(prefix)
        }

        resultContexts[i] = context
        resultReceivers[i] = receiver
        i = i + 1
    }

    return count
}

func IsCodeIntelligenceCompletionMemberAccessContext(beforeCursor: string): bool {
    end := TrimCodeIntelligenceCompletionReceiverEnd(beforeCursor, beforeCursor.Length)
    if end <= 0 {
        return false
    }

    if beforeCursor[end - 1] == '.' {
        return true
    }

    lastDot := LastCodeIntelligenceCompletionReceiverCharBefore(beforeCursor, '.', end)
    if lastDot > 0 {
        beforeDotEnd := TrimCodeIntelligenceCompletionReceiverEnd(beforeCursor, lastDot)
        if beforeDotEnd > 0 && IsCodeIntelligenceCompletionReceiverIdentifierChar(beforeCursor[beforeDotEnd - 1]) {
            return true
        }
    }

    return false
}

func ExtractCodeIntelligenceCompletionReceiver(beforeCursor: string): string {
    end := TrimCodeIntelligenceCompletionReceiverEnd(beforeCursor, beforeCursor.Length)
    dotIndex := FindLastCodeIntelligenceCompletionTopLevelDot(beforeCursor, end)
    if dotIndex < 0 {
        return ""
    }

    withoutDotEnd := TrimCodeIntelligenceCompletionReceiverEnd(beforeCursor, dotIndex)
    return ExtractCodeIntelligenceCompletionExpressionSuffix(beforeCursor, withoutDotEnd)
}

func ExtractCodeIntelligenceCompletionExpressionSuffix(text: string, end: int): string {
    literalReceiver := TryExtractCodeIntelligenceCompletionLiteralSuffix(text, end)
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

        if IsCodeIntelligenceCompletionReceiverIdentifierChar(current) || current == '.' {
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
        return NormalizeCodeIntelligenceCompletionReceiverCalls(text, start, end)
    }

    return ""
}

func TryExtractCodeIntelligenceCompletionLiteralSuffix(text: string, end: int): string {
    if end <= 0 {
        return ""
    }

    if EndsCodeIntelligenceCompletionReceiverWith(text, end, "true") {
        start := end - 4
        if IsCodeIntelligenceCompletionReceiverTokenBoundary(text, start)
            && !HasCodeIntelligenceCompletionLineCommentBefore(text, start) {
            return text.Substring(start, 4)
        }
    }

    if EndsCodeIntelligenceCompletionReceiverWith(text, end, "false") {
        start := end - 5
        if IsCodeIntelligenceCompletionReceiverTokenBoundary(text, start)
            && !HasCodeIntelligenceCompletionLineCommentBefore(text, start) {
            return text.Substring(start, 5)
        }
    }

    current := text[end - 1]
    if current == '"' {
        rawStart := FindCodeIntelligenceCompletionRawStringStart(text, end)
        if rawStart >= 0 && !HasCodeIntelligenceCompletionLineCommentBefore(text, rawStart) {
            return text.Substring(rawStart, end - rawStart)
        }

        stringStart := FindCodeIntelligenceCompletionStringStart(text, end)
        if stringStart >= 0 && !HasCodeIntelligenceCompletionLineCommentBefore(text, stringStart) {
            return text.Substring(stringStart, end - stringStart)
        }
    }

    if current == '\'' {
        charStart := FindCodeIntelligenceCompletionCharStart(text, end)
        if charStart >= 0 && !HasCodeIntelligenceCompletionLineCommentBefore(text, charStart) {
            return text.Substring(charStart, end - charStart)
        }
    }

    numericStart := FindCodeIntelligenceCompletionNumericLiteralStart(text, end)
    if numericStart >= 0 && !HasCodeIntelligenceCompletionLineCommentBefore(text, numericStart) {
        return text.Substring(numericStart, end - numericStart)
    }

    return ""
}

func NormalizeCodeIntelligenceCompletionReceiverCalls(text: string, start: int, end: int): string {
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

func FindCodeIntelligenceCompletionRawStringStart(text: string, end: int): int {
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

func FindCodeIntelligenceCompletionStringStart(text: string, end: int): int {
    position := end - 2

    while position >= 0 {
        if text[position] == '"' && !IsCodeIntelligenceCompletionEscaped(text, position) {
            if position > 0 && text[position - 1] == '$' {
                return position - 1
            }

            return position
        }

        position = position - 1
    }

    return -1
}

func FindCodeIntelligenceCompletionCharStart(text: string, end: int): int {
    position := end - 2

    while position >= 0 {
        if text[position] == '\'' && !IsCodeIntelligenceCompletionEscaped(text, position) {
            return position
        }

        position = position - 1
    }

    return -1
}

func IsCodeIntelligenceCompletionEscaped(text: string, index: int): bool {
    slashCount := 0
    position := index - 1

    while position >= 0 && text[position] == '\\' {
        slashCount = slashCount + 1
        position = position - 1
    }

    return (slashCount & 1) == 1
}

func FindCodeIntelligenceCompletionNumericLiteralStart(text: string, end: int): int {
    position := end - 1

    while position >= 0 {
        if IsCodeIntelligenceCompletionDigit(text[position])
            && IsCodeIntelligenceCompletionNumericStartBoundary(text, position)
            && ScanCodeIntelligenceCompletionNumber(text, position, end) == end {
            return position
        }

        position = position - 1
    }

    return -1
}

func ScanCodeIntelligenceCompletionNumber(text: string, position: int, end: int): int {
    if text[position] == '0'
        && position + 1 < end
        && (text[position + 1] == 'x' || text[position + 1] == 'X') {
        position = position + 2
        while position < end && (IsCodeIntelligenceCompletionHexDigit(text[position]) || text[position] == '_') {
            position = position + 1
        }

        return ConsumeCodeIntelligenceCompletionIntegerSuffix(text, position, end)
    }

    if text[position] == '0'
        && position + 1 < end
        && (text[position + 1] == 'b' || text[position + 1] == 'B') {
        position = position + 2
        while position < end && (text[position] == '0' || text[position] == '1' || text[position] == '_') {
            position = position + 1
        }

        return ConsumeCodeIntelligenceCompletionIntegerSuffix(text, position, end)
    }

    isFloat := false
    while position < end
        && (IsCodeIntelligenceCompletionDigit(text[position]) || text[position] == '.' || text[position] == '_') {
        if text[position] == '.' {
            if position + 1 < end && text[position + 1] == '.' {
                break
            }

            if position + 1 >= end || !IsCodeIntelligenceCompletionDigit(text[position + 1]) {
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

        while position < end && (IsCodeIntelligenceCompletionDigit(text[position]) || text[position] == '_') {
            position = position + 1
        }
    }

    if isFloat {
        return ConsumeCodeIntelligenceCompletionFloatSuffix(text, position, end)
    }

    if position < end && (text[position] == 'm' || text[position] == 'M') {
        return position + 1
    }

    return ConsumeCodeIntelligenceCompletionIntegerSuffix(text, position, end)
}

func IsCodeIntelligenceCompletionNumericStartBoundary(text: string, start: int): bool {
    if start <= 0 {
        return true
    }

    previous := text[start - 1]
    if previous == '.' {
        return start < 2 || !IsCodeIntelligenceCompletionDigit(text[start - 2])
    }

    if previous == '+' || previous == '-' {
        if start >= 3 {
            marker := text[start - 2]
            if (marker == 'e' || marker == 'E') && IsCodeIntelligenceCompletionDigit(text[start - 3]) {
                return false
            }
        }

        return true
    }

    return !IsCodeIntelligenceCompletionReceiverIdentifierChar(previous)
}

func ConsumeCodeIntelligenceCompletionFloatSuffix(text: string, position: int, end: int): int {
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

func ConsumeCodeIntelligenceCompletionIntegerSuffix(text: string, position: int, end: int): int {
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

func FindLastCodeIntelligenceCompletionTopLevelDot(text: string, end: int): int {
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

func LastCodeIntelligenceCompletionReceiverCharBefore(text: string, ch: char, end: int): int {
    index := end - 1

    while index >= 0 {
        if text[index] == ch {
            return index
        }

        index = index - 1
    }

    return -1
}

func TrimCodeIntelligenceCompletionReceiverEnd(text: string, end: int): int {
    if end > text.Length {
        end = text.Length
    }

    while end > 0 && IsCodeIntelligenceCompletionReceiverWhitespace(text[end - 1]) {
        end = end - 1
    }

    return end
}

func EndsCodeIntelligenceCompletionReceiverWith(text: string, end: int, suffix: string): bool {
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

func IsCodeIntelligenceCompletionReceiverTokenBoundary(text: string, start: int): bool {
    return start <= 0 || !IsCodeIntelligenceCompletionReceiverIdentifierChar(text[start - 1])
}

func HasCodeIntelligenceCompletionLineCommentBefore(text: string, start: int): bool {
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

func IsCodeIntelligenceCompletionReceiverIdentifierChar(ch: char): bool {
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

func IsCodeIntelligenceCompletionReceiverWhitespace(ch: char): bool {
    if ch == ' ' {
        return true
    }

    if ch <= '~' {
        return ch >= '\t' && ch <= '\r'
    }

    return Char.IsWhiteSpace(ch)
}

func IsCodeIntelligenceCompletionDigit(ch: char): bool {
    return ch >= '0' && ch <= '9'
}

func IsCodeIntelligenceCompletionHexDigit(ch: char): bool {
    return (ch >= '0' && ch <= '9')
        || (ch >= 'a' && ch <= 'f')
        || (ch >= 'A' && ch <= 'F')
}

func CompletionReceiverMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}

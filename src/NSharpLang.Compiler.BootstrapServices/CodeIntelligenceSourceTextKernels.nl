namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Text

class CodeIntelligenceSourceTextKernels {
    static func TryExtractIdentifierSpan(snapshot: object, filePathValue: string, source: string, line: int, column: int, out span: ValueTuple<int, int>?): bool {
        span = null

        start := 0
        length := 0
        if !TryExtractIdentifierSpanCore(source, line, column, out start, out length) {
            return true
        }

        span = new ValueTuple<int, int>(start, start + length - 1)
        return true
    }

    static func TryExtractDocComment(snapshot: object, filePathValue: string, source: string, definitionLine: int, out documentation: string?): bool {
        documentation = null

        lineStarts := new int[](source.Length + 1)
        lineLengths := new int[](source.Length + 1)
        lineCount := BuildLineRanges(source, lineStarts, lineLengths)
        startLine := FindDocCommentStartLine(source, lineStarts, lineLengths, lineCount, definitionLine)

        if startLine < 0 {
            return true
        }

        builder := new StringBuilder()
        emitted := 0
        lineIndex := startLine
        lastLineIndex := definitionLine - 2
        while lineIndex <= lastLineIndex {
            lineStart := lineStarts[lineIndex]
            lineLength := lineLengths[lineIndex]
            if IsDocCommentLine(source, lineStart, lineLength) {
                if emitted > 0 {
                    builder.Append('\n')
                }

                contentStart := GetDocCommentContentStart(source, lineStart, lineLength)
                contentLength := GetDocCommentContentLength(source, lineStart, lineLength, contentStart)
                builder.Append(source.Substring(contentStart, contentLength))
                emitted = emitted + 1
            }

            lineIndex = lineIndex + 1
        }

        if emitted > 0 {
            documentation = builder.ToString()
        }

        return true
    }

    static func TryExtractCompletionPrefix(snapshot: object, filePathValue: string, source: string, line: int, column: int, out prefix: string?): bool {
        prefix = null

        lineStart := 0
        lineLength := 0
        if !TryGetLineRange(source, line, out lineStart, out lineLength) {
            return true
        }

        prefixLength := lineLength
        if column > 0 && column <= prefixLength {
            prefixLength = column
        }

        prefix = source.Substring(lineStart, prefixLength)
        return true
    }

    static func TryExtractIdentifierName(snapshot: object, filePathValue: string, source: string, line: int, column: int, out name: string?): bool {
        name = null

        start := 0
        length := 0
        lineStart := 0
        if !TryExtractIdentifierSpanCoreWithLineStart(source, line, column, out start, out length, out lineStart) {
            return true
        }

        name = source.Substring(lineStart + start - 1, length)
        return true
    }

    static func TryExtractSourceContext(snapshot: object, filePathValue: string, source: string, line: int, out context: string?): bool {
        context = null

        lineStart := 0
        lineLength := 0
        if !TryGetLineRange(source, line, out lineStart, out lineLength) {
            return true
        }

        trimStart := lineStart
        trimEnd := lineStart + lineLength - 1

        while trimStart <= trimEnd && IsCodeIntelligenceWhitespace(source[trimStart]) {
            trimStart = trimStart + 1
        }

        while trimEnd >= trimStart && IsCodeIntelligenceWhitespace(source[trimEnd]) {
            trimEnd = trimEnd - 1
        }

        contextLength := 0
        if trimEnd >= trimStart {
            contextLength = trimEnd - trimStart + 1
        }

        context = source.Substring(trimStart, contextLength)
        return true
    }

    static func TryExtractSourceLine(snapshot: object, filePathValue: string, source: string, line: int, out text: string?): bool {
        return TryExtractSourceLine(source, line, out text)
    }

    static func TryExtractSourceLine(source: string, line: int, out text: string?): bool {
        text = null

        lineStart := 0
        lineLength := 0
        if !TryGetLineRange(source, line, out lineStart, out lineLength) {
            return true
        }

        text = source.Substring(lineStart, lineLength)
        return true
    }

    static func TryExtractEditorIdentifierSpan(source: string, line: int, column: int, out span: ValueTuple<int, int, string>?): bool {
        span = null

        if line <= 0 || column <= 0 {
            return true
        }

        lineStart := 0
        lineLength := 0
        if !TryGetLineRange(source, line, out lineStart, out lineLength) {
            return true
        }

        if lineLength <= 0 {
            return true
        }

        character := column - 1
        if character >= lineLength {
            character = lineLength - 1
            if !IsCodeIntelligenceIdentifierChar(source[lineStart + character]) {
                return true
            }
        } else if !IsCodeIntelligenceIdentifierChar(source[lineStart + character]) {
            return true
        }

        start := character
        while start > 0 && IsCodeIntelligenceIdentifierChar(source[lineStart + start - 1]) {
            start = start - 1
        }

        end := character
        while end + 1 < lineLength && IsCodeIntelligenceIdentifierChar(source[lineStart + end + 1]) {
            end = end + 1
        }

        spanStart := start + 1
        spanLength := end - start + 1
        spanName := source.Substring(lineStart + start, spanLength)
        span = new ValueTuple<int, int, string>(spanStart, spanStart + spanLength - 1, spanName)
        return true
    }

    static func TryExtractVariableDeclarationName(snapshot: object, filePathValue: string, source: string, line: int, out name: string?): bool {
        name = null

        lineStart := 0
        lineLength := 0
        if !TryGetLineRange(source, line, out lineStart, out lineLength) {
            return true
        }

        assignIndex := FindAssignmentOperator(source, lineStart, lineLength)
        if assignIndex <= 0 {
            return true
        }

        nameEnd := assignIndex - 1
        while nameEnd >= 0 && IsCodeIntelligenceWhitespace(source[lineStart + nameEnd]) {
            nameEnd = nameEnd - 1
        }

        if nameEnd < 0 {
            return true
        }

        nameStart := nameEnd
        while nameStart >= 0 && IsCodeIntelligenceIdentifierChar(source[lineStart + nameStart]) {
            nameStart = nameStart - 1
        }

        nameStart = nameStart + 1
        if nameStart > nameEnd {
            return true
        }

        name = source.Substring(lineStart + nameStart, nameEnd - nameStart + 1)
        return true
    }

    static func TryExtractIdentifierSpanCore(source: string, line: int, column: int, out start: int, out length: int): bool {
        lineStart := 0
        return TryExtractIdentifierSpanCoreWithLineStart(source, line, column, out start, out length, out lineStart)
    }

    static func TryExtractIdentifierSpanCoreWithLineStart(source: string, line: int, column: int, out start: int, out length: int, out lineStart: int): bool {
        start = -1
        length = 0
        lineStart = 0

        lineLength := 0
        if !TryGetLineRange(source, line, out lineStart, out lineLength) {
            return false
        }

        if lineLength <= 0 {
            return false
        }

        index := column - 1
        if index < 0 {
            index = 0
        }

        if index >= lineLength {
            index = lineLength - 1
        }

        nearest := FindNearestIdentifierIndex(source, lineStart, lineLength, index)
        if nearest < 0 {
            return false
        }

        identifierStart := nearest
        while identifierStart > 0 && IsCodeIntelligenceIdentifierChar(source[lineStart + identifierStart - 1]) {
            identifierStart = identifierStart - 1
        }

        identifierEnd := nearest
        while identifierEnd + 1 < lineLength && IsCodeIntelligenceIdentifierChar(source[lineStart + identifierEnd + 1]) {
            identifierEnd = identifierEnd + 1
        }

        start = identifierStart + 1
        length = identifierEnd - identifierStart + 1
        return true
    }

    static func TryGetLineRange(source: string, line: int, out start: int, out length: int): bool {
        start = 0
        length = 0

        if line <= 0 {
            return false
        }

        sourceLength := source.Length
        currentLine := 1
        lineStart := 0
        position := 0

        while position < sourceLength {
            if source[position] == '\r' {
                if currentLine == line {
                    start = lineStart
                    length = position - lineStart
                    return true
                }

                currentLine = currentLine + 1
                hasNext := position + 1 < sourceLength
                if hasNext {
                    if source[position + 1] == '\n' {
                        position = position + 2
                        lineStart = position
                        continue
                    }
                }

                position = position + 1
                lineStart = position
                continue
            }

            if source[position] == '\n' {
                if currentLine == line {
                    start = lineStart
                    length = position - lineStart
                    return true
                }

                currentLine = currentLine + 1
                position = position + 1
                lineStart = position
                continue
            }

            position = position + 1
        }

        if currentLine == line {
            start = lineStart
            length = sourceLength - lineStart
            return true
        }

        return false
    }

    static func BuildLineRanges(source: string, starts: int[], lengths: int[]): int {
        sourceLength := source.Length
        position := 0
        lineStart := 0
        count := 0

        while position < sourceLength {
            if source[position] == '\r' {
                starts[count] = lineStart
                lengths[count] = position - lineStart
                count = count + 1

                hasNext := position + 1 < sourceLength
                if hasNext {
                    if source[position + 1] == '\n' {
                        position = position + 2
                        lineStart = position
                        continue
                    }
                }

                position = position + 1
                lineStart = position
                continue
            }

            if source[position] == '\n' {
                starts[count] = lineStart
                lengths[count] = position - lineStart
                count = count + 1
                position = position + 1
                lineStart = position
                continue
            }

            position = position + 1
        }

        starts[count] = lineStart
        lengths[count] = sourceLength - lineStart
        return count + 1
    }

    static func FindDocCommentStartLine(source: string, lineStarts: int[], lineLengths: int[], lineCount: int, definitionLine: int): int {
        if definitionLine <= 1 || definitionLine > lineCount + 1 {
            return -1
        }

        commentCount := 0
        startLine := -1
        lineIndex := definitionLine - 2

        while lineIndex >= 0 {
            lineStart := lineStarts[lineIndex]
            lineLength := lineLengths[lineIndex]

            if IsDocCommentLine(source, lineStart, lineLength) {
                startLine = lineIndex
                commentCount = commentCount + 1
                lineIndex = lineIndex - 1
                continue
            }

            if commentCount == 0 && IsBlankLine(source, lineStart, lineLength) {
                lineIndex = lineIndex - 1
                continue
            }

            break
        }

        return startLine
    }

    static func IsDocCommentLine(source: string, lineStart: int, lineLength: int): bool {
        trimStart := lineStart
        trimEnd := lineStart + lineLength - 1

        while trimStart <= trimEnd && IsCodeIntelligenceWhitespace(source[trimStart]) {
            trimStart = trimStart + 1
        }

        while trimEnd >= trimStart && IsCodeIntelligenceWhitespace(source[trimEnd]) {
            trimEnd = trimEnd - 1
        }

        return trimStart + 1 <= trimEnd && source[trimStart] == '/' && source[trimStart + 1] == '/'
    }

    static func IsBlankLine(source: string, lineStart: int, lineLength: int): bool {
        i := 0
        while i < lineLength {
            if !IsCodeIntelligenceWhitespace(source[lineStart + i]) {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func GetDocCommentContentStart(source: string, lineStart: int, lineLength: int): int {
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

    static func GetDocCommentContentLength(source: string, lineStart: int, lineLength: int, contentStart: int): int {
        contentEnd := lineStart + lineLength - 1

        while contentEnd >= contentStart && IsCodeIntelligenceWhitespace(source[contentEnd]) {
            contentEnd = contentEnd - 1
        }

        if contentEnd < contentStart {
            return 0
        }

        return contentEnd - contentStart + 1
    }

    static func FindAssignmentOperator(source: string, lineStart: int, lineLength: int): int {
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

    static func FindNearestIdentifierIndex(source: string, lineStart: int, lineLength: int, index: int): int {
        if lineLength == 0 {
            return -1
        }

        if index >= 0 && index < lineLength && IsCodeIntelligenceIdentifierChar(source[lineStart + index]) {
            return index
        }

        distance := 1
        while distance <= 3 {
            left := index - distance
            if left >= 0 && IsCodeIntelligenceIdentifierChar(source[lineStart + left]) && IsSnapFriendlyNeighbor(source, lineStart, lineLength, left + 1, index) {
                return left
            }

            right := index + distance
            if right < lineLength && IsCodeIntelligenceIdentifierChar(source[lineStart + right]) && IsSnapFriendlyNeighbor(source, lineStart, lineLength, index, right - 1) {
                return right
            }

            distance = distance + 1
        }

        return -1
    }

    static func IsCodeIntelligenceIdentifierChar(ch: char): bool {
        if ch >= 'a' && ch <= 'z' {
            return true
        }

        if ch <= '~' {
            return ch == '_' || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')
        }

        if ch >= 'A' && ch <= 'Z' {
            return true
        }

        if ch >= '0' && ch <= '9' {
            return true
        }

        return Char.IsLetterOrDigit(ch)
    }

    static func IsSnapFriendlyNeighbor(source: string, lineStart: int, lineLength: int, start: int, end: int): bool {
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
            if IsCodeIntelligenceWhitespace(ch) || IsSnapPunctuation(ch) {
                i = i + 1
                continue
            }

            return false
        }

        return true
    }

    static func IsCodeIntelligenceWhitespace(ch: char): bool {
        if ch == ' ' {
            return true
        }

        if ch <= '~' {
            return ch >= '\t' && ch <= '\r'
        }

        return Char.IsWhiteSpace(ch)
    }

    static func IsSnapPunctuation(ch: char): bool {
        return ch == '.' || ch == '?' || ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}' || ch == ',' || ch == ';' || ch == ':'
    }
}

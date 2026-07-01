namespace NSharpLang.Compiler.CodeIntelligence

import System

public struct EditorIdentifierSpan(startColumn: int, endColumn: int, name: string) {
    StartColumn: int = startColumn
    EndColumn: int = endColumn
    Name: string = name
    StartCharacter: int => StartColumn - 1
    EndCharacter: int => EndColumn
}

public class CodeIntelligenceTextUtilities {
    public static func GetEditorWordAtPosition(text: string, line: int, character: int): string {
        span := new EditorIdentifierSpan(0, 0, "")
        if TryGetEditorIdentifierSpanAtPosition(text, line, character, out span) {
            return span.Name
        }

        return ""
    }

    public static func TryGetEditorIdentifierSpanAtPosition(
        text: string,
        line: int,
        character: int,
        out span: EditorIdentifierSpan): bool {
        span = new EditorIdentifierSpan(0, 0, "")
        if line < 0 || character < 0 {
            return false
        }

        oneBasedLine := line + 1
        oneBasedColumn := character + 1
        return TryGetEditorIdentifierSpanCore(text, oneBasedLine, oneBasedColumn, out span)
    }

    public static func GetSourceLine(source: string, line: int): string? {
        start := 0
        length := 0
        if !TryGetSourceLineRange(source, line, out start, out length) {
            return null
        }

        return source.Substring(start, length)
    }

    public static func FindIdentifierNameColumn(source: string, name: string, line: int, fallbackColumn: int): int {
        if name.Length == 0 {
            return fallbackColumn
        }

        lineStart := 0
        lineLength := 0
        if !TryGetSourceLineRange(source, line, out lineStart, out lineLength) {
            return fallbackColumn
        }

        if lineLength == 0 {
            return fallbackColumn
        }

        preferredStart := fallbackColumn - 1
        if preferredStart < 0 {
            preferredStart = 0
        }
        if preferredStart > lineLength {
            preferredStart = lineLength
        }

        index := FindWholeIdentifier(source, lineStart, lineLength, name, preferredStart)
        if index < 0 {
            index = FindWholeIdentifier(source, lineStart, lineLength, name, 0)
        }

        if index >= 0 {
            return index + 1
        }

        return fallbackColumn
    }

    static func FindWholeIdentifier(source: string, lineStart: int, lineLength: int, name: string, startIndex: int): int {
        nameLength := name.Length
        if nameLength == 0 || nameLength > lineLength {
            return -1
        }

        candidate := startIndex
        if candidate < 0 {
            candidate = 0
        }

        while candidate + nameLength <= lineLength {
            if MatchesNameAt(source, lineStart + candidate, name) {
                beforeIsIdentifier := false
                if candidate > 0 {
                    beforeIsIdentifier = IsCodeIntelligenceIdentifierChar(source[lineStart + candidate - 1])
                }

                afterIsIdentifier := false
                afterIndex := candidate + nameLength
                if afterIndex < lineLength {
                    afterIsIdentifier = IsCodeIntelligenceIdentifierChar(source[lineStart + afterIndex])
                }

                if !beforeIsIdentifier && !afterIsIdentifier {
                    return candidate
                }
            }

            candidate = candidate + 1
        }

        return -1
    }

    static func MatchesNameAt(source: string, position: int, name: string): bool {
        index := 0
        while index < name.Length {
            if source[position + index] != name[index] {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func TryGetEditorIdentifierSpanCore(
        source: string,
        line: int,
        column: int,
        out span: EditorIdentifierSpan): bool {
        span = new EditorIdentifierSpan(0, 0, "")
        if line <= 0 || column <= 0 {
            return false
        }

        lineStart := 0
        lineLength := 0
        if !TryGetSourceLineRange(source, line, out lineStart, out lineLength) {
            return false
        }

        if lineLength <= 0 {
            return false
        }

        character := column - 1
        if character >= lineLength {
            character = lineLength - 1
            if !IsCodeIntelligenceIdentifierChar(source[lineStart + character]) {
                return false
            }
        } else if !IsCodeIntelligenceIdentifierChar(source[lineStart + character]) {
            return false
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
        spanEnd := end + 1
        spanName := source.Substring(lineStart + start, end - start + 1)
        span = new EditorIdentifierSpan(spanStart, spanEnd, spanName)
        return true
    }

    static func TryGetSourceLineRange(source: string, line: int, out start: int, out length: int): bool {
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

    static func IsCodeIntelligenceIdentifierChar(ch: char): bool {
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
}

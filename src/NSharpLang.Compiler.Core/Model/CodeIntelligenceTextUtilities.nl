namespace NSharpLang.Compiler.CodeIntelligence

import System

struct EditorIdentifierSpan(startColumn: int, endColumn: int, name: string) {
    StartColumn: int = startColumn
    EndColumn: int = endColumn
    Name: string = name
    StartCharacter: int => StartColumn - 1
    EndCharacter: int => EndColumn
}

class CodeIntelligenceTextUtilities {
    static func GetEditorWordAtPosition(text: string, line: int, character: int): string {
        span := new EditorIdentifierSpan(0, 0, "")
        if TryGetEditorIdentifierSpanAtPosition(text, line, character, out span) {
            return span.Name
        }

        return ""
    }

    static func TryGetEditorIdentifierSpanAtPosition(text: string, line: int, character: int, out span: EditorIdentifierSpan): bool {
        span = new EditorIdentifierSpan(0, 0, "")
        if line < 0 || character < 0 {
            return false
        }

        oneBasedLine := line + 1
        oneBasedColumn := character + 1
        return TryGetEditorIdentifierSpanCore(text, oneBasedLine, oneBasedColumn, out span)
    }

    static func GetSourceLine(source: string, line: int): string? {
        start := 0
        length := 0
        if !TryGetSourceLineRange(source, line, out start, out length) {
            return null
        }

        return source.Substring(start, length)
    }

    static func FindIdentifierNameColumn(source: string, name: string, line: int, fallbackColumn: int): int {
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

    static func TryGetEditorIdentifierSpanCore(source: string, line: int, column: int, out span: EditorIdentifierSpan): bool {
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

    // ── WHICH POSITIONS OF A BUFFER ARE INSIDE LITERAL TEXT ────────────────────────────────────
    //
    // "Is the cursor inside a string?" is the question an editor asks before it treats the word
    // under the cursor as CODE. Rename must refuse a word inside `"…"`; a completion must not
    // offer members for it. The answer has to be a scan of the WHOLE buffer rather than a lookup
    // in the token stream, because it is asked exactly when the buffer does not parse — mid-edit,
    // with an unterminated literal open — and the token stream is then not to be trusted.
    //
    // AN INTERPOLATION HOLE IS NOT INSIDE THE STRING. `$"hello {name}"` has `name` as real code,
    // so the interpolated scans track brace DEPTH and answer false for a position inside a hole,
    // and answer true again for a nested literal inside that hole (`$"{d["key"]}"` — `key` is a
    // string, two levels down). That is why the four literal kinds get four scans instead of one:
    // a raw string ends on `"""` and ignores backslashes, a normal string ends on the first
    // unescaped `"` or at the end of the LINE, and the two interpolated forms differ in both.
    //
    // AN UNTERMINATED LITERAL SWALLOWS THE REST OF THE BUFFER, DELIBERATELY. Each scan's final
    // fallthrough answers "inside" for any position at or after the opening delimiter. Half a
    // literal is a literal, and treating the tail as code would offer completions inside a string
    // the developer is still typing.
    //
    // THE SCANS SHARE ONE CONVENTION: each answers whether the target is inside the literal it
    // just walked, and sets `end` to the index the outer walk should resume from. A `true` answer
    // ends the whole question — the target has been placed — so the outer walk only resumes on
    // false.
    static func IsEditorPositionInsideStringLiteral(text: string, line: int, character: int): bool {
        target := 0
        if !TryGetEditorOffset(text, line, character, out target) {
            return false
        }

        index := 0
        while index < text.Length {
            if text[index] == '$' && index + 1 < text.Length && text[index + 1] == '"' {
                scanEnd := 0
                if index + 3 < text.Length && text[index + 2] == '"' && text[index + 3] == '"' {
                    if ScanEditorInterpolatedRawString(text, index, target, out scanEnd) {
                        return true
                    }

                    index = scanEnd
                    index = index + 1
                    continue
                }

                if ScanEditorInterpolatedString(text, index, target, out scanEnd) {
                    return true
                }

                index = scanEnd
                index = index + 1
                continue
            }

            if text[index] == '"' {
                scanEnd := 0
                if index + 2 < text.Length && text[index + 1] == '"' && text[index + 2] == '"' {
                    if ScanEditorRawString(text, index, target, false, out scanEnd) {
                        return true
                    }

                    index = scanEnd
                    index = index + 1
                    continue
                }

                if ScanEditorRegularString(text, index, target, out scanEnd) {
                    return true
                }

                index = scanEnd
            }

            index = index + 1
        }

        return false
    }

    // The character offset of a 0-based (line, character) position, or false when the position is
    // past the end of the buffer. The end-of-buffer offset itself IS addressable — a cursor sits
    // after the last character — so the walk runs to `text.Length` inclusive.
    static func TryGetEditorOffset(text: string, line: int, character: int, out offset: int): bool {
        offset = 0
        if line < 0 || character < 0 {
            return false
        }

        currentLine := 0
        currentColumn := 0
        index := 0
        while index <= text.Length {
            if currentLine == line && currentColumn == character {
                offset = index
                return true
            }

            if index == text.Length {
                return false
            }

            if text[index] == '\n' {
                currentLine = currentLine + 1
                currentColumn = 0
            } else {
                currentColumn = currentColumn + 1
            }

            index = index + 1
        }

        return false
    }

    static func ScanEditorRawString(text: string, start: int, target: int, hasDollarPrefix: bool, out end: int): bool {
        end = 0
        contentStart := start + 3
        if hasDollarPrefix {
            contentStart = start + 4
        }

        index := contentStart
        while index < text.Length - 2 {
            if target >= contentStart && target < index {
                end = index
                return true
            }

            if text[index] == '"' && text[index + 1] == '"' && text[index + 2] == '"' {
                end = index + 2
                return target >= contentStart && target < index
            }

            index = index + 1
        }

        end = text.Length - 1
        return target >= contentStart
    }

    static func ScanEditorRegularString(text: string, start: int, target: int, out end: int): bool {
        end = 0
        index := start + 1
        while index < text.Length {
            if text[index] == '\n' {
                end = index
                return target > start && target < index
            }

            if text[index] == '"' && !IsEditorEscapedQuote(text, index) {
                end = index
                return target > start && target < index
            }

            index = index + 1
        }

        end = text.Length - 1
        return target > start
    }

    static func ScanEditorInterpolatedRawString(text: string, start: int, target: int, out end: int): bool {
        end = 0
        contentStart := start + 4
        interpolationDepth := 0
        nestedStringDepth := 0

        index := contentStart
        while index < text.Length - 2 {
            if target == index {
                end = index
                return interpolationDepth == 0 || nestedStringDepth > 0
            }

            if nestedStringDepth > 0 {
                if text[index] == '"' {
                    nestedStringDepth = nestedStringDepth - 1
                }

                index = index + 1
                continue
            }

            if text[index] == '{' {
                if index + 1 < text.Length && text[index + 1] == '{' {
                    index = index + 1
                    index = index + 1
                    continue
                }

                interpolationDepth = interpolationDepth + 1
                index = index + 1
                continue
            }

            if text[index] == '}' && interpolationDepth > 0 {
                interpolationDepth = interpolationDepth - 1
                index = index + 1
                continue
            }

            if text[index] == '"' {
                if interpolationDepth > 0 {
                    nestedStringDepth = nestedStringDepth + 1
                    index = index + 1
                    continue
                }

                if text[index + 1] == '"' && text[index + 2] == '"' {
                    end = index + 2
                    return false
                }
            }

            index = index + 1
        }

        end = text.Length - 1
        return target >= contentStart && interpolationDepth == 0
    }

    static func ScanEditorInterpolatedString(text: string, start: int, target: int, out end: int): bool {
        end = 0
        interpolationDepth := 0
        nestedStringDepth := 0

        index := start + 2
        while index < text.Length {
            if text[index] == '\n' {
                end = index
                return target > start + 1 && target < index && interpolationDepth == 0
            }

            if target == index {
                end = index
                return interpolationDepth == 0 || nestedStringDepth > 0
            }

            if text[index] == '\\' {
                index = index + 1
                index = index + 1
                continue
            }

            if nestedStringDepth > 0 {
                if text[index] == '"' {
                    nestedStringDepth = nestedStringDepth - 1
                }

                index = index + 1
                continue
            }

            if text[index] == '{' {
                if interpolationDepth == 0 && index + 1 < text.Length && text[index + 1] == '{' {
                    index = index + 1
                    index = index + 1
                    continue
                }

                interpolationDepth = interpolationDepth + 1
                index = index + 1
                continue
            }

            if text[index] == '}' && interpolationDepth > 0 {
                interpolationDepth = interpolationDepth - 1
                index = index + 1
                continue
            }

            if text[index] == '}' && interpolationDepth == 0 && index + 1 < text.Length && text[index + 1] == '}' {
                index = index + 1
                index = index + 1
                continue
            }

            if text[index] == '"' {
                if interpolationDepth > 0 {
                    nestedStringDepth = nestedStringDepth + 1
                    index = index + 1
                    continue
                }

                end = index
                return false
            }

            index = index + 1
        }

        end = text.Length - 1
        return target > start + 1 && interpolationDepth == 0
    }

    // A quote is escaped when an ODD number of backslashes precedes it. `"a\\"` closes; `"a\""`
    // does not.
    static func IsEditorEscapedQuote(text: string, quoteIndex: int): bool {
        slashCount := 0
        index := quoteIndex - 1
        while index >= 0 && text[index] == '\\' {
            slashCount = slashCount + 1
            index = index - 1
        }

        return slashCount % 2 == 1
    }
}

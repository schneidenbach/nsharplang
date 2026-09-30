namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

class LinterSuppressionSet {
    lines: List<int>
    codes: List<string>

    constructor() {
        lines = new List<int>()
        codes = new List<string>()
    }

    func Add(line: int, code: string) {
        lines.Add(line)
        codes.Add(code)
    }

    func IsSuppressed(line: int, code: string): bool {
        index := 0
        while index < lines.Count {
            if lines[index] == line {
                currentCode := codes[index]
                if string.Equals(currentCode, "*", StringComparison.Ordinal) || string.Equals(currentCode, code, StringComparison.OrdinalIgnoreCase) {
                    return true
                }
            }

            index = index + 1
        }

        return false
    }
}

class LinterSuppressionParser {
    static func BuildSuppressions(filePath: string?, sourceText: string?): LinterSuppressionSet {
        source := sourceText
        if string.IsNullOrEmpty(source) && !string.IsNullOrWhiteSpace(filePath ?? "") {
            path := filePath ?? ""
            if File.Exists(path) {
                try {
                    source = File.ReadAllText(path)
                } catch {
                    source = null
                }
            }
        }

        suppressions := new LinterSuppressionSet()
        if string.IsNullOrEmpty(source) {
            return suppressions
        }

        sourceValue := source ?? ""
        lines := SplitSourceLines(sourceValue)
        lineCount := lines.Count
        nextCodeLines := BuildNextCodeLineIndex(lines)
        pendingCodes := new List<string>()

        lineNumber := 1
        while lineNumber <= lineCount {
            line := lines[lineNumber - 1]
            trimmed := line.Trim()
            codes := ParseSuppressionCodes(line)
            if codes.Count == 0 {
                if !string.IsNullOrWhiteSpace(trimmed) && !trimmed.StartsWith("//", StringComparison.Ordinal) {
                    pendingCodes.Clear()
                }

                lineNumber = lineNumber + 1
                continue
            }

            commentIndex := line.IndexOf("//", StringComparison.Ordinal)
            hasCodeBeforeComment := commentIndex > 0 && !string.IsNullOrWhiteSpace(line.Substring(0, commentIndex))
            if hasCodeBeforeComment {
                AddSuppression(suppressions, lineNumber, codes)
                pendingCodes.Clear()
                lineNumber = lineNumber + 1
                continue
            }

            CopyCodes(pendingCodes, codes)
            nextLine := nextCodeLines[lineNumber - 1]
            if nextLine > 0 {
                AddSuppression(suppressions, nextLine, pendingCodes)
            }

            pendingCodes.Clear()
            lineNumber = lineNumber + 1
        }

        return suppressions
    }

    // Source-position lookup by line number restarts at the beginning of the buffer. Repeatedly
    // asking for every line therefore made suppression parsing quadratic in source lines. Split the
    // buffer in one pass, then use the following reverse index to find a comment's next code line.
    static func SplitSourceLines(sourceText: string): List<string> {
        lines := new List<string>()
        start := 0
        while start <= sourceText.Length {
            position := start
            while position < sourceText.Length && sourceText[position] != '\n' {
                position = position + 1
            }

            lines.Add(sourceText.Substring(start, position - start))
            if position >= sourceText.Length {
                break
            }

            start = position + 1
        }

        return lines
    }

    static func BuildNextCodeLineIndex(lines: IReadOnlyList<string>): int[] {
        nextCodeLines := new int[lines.Count]
        nextCodeLine := -1
        index := lines.Count - 1
        while index >= 0 {
            nextCodeLines[index] = nextCodeLine
            trimmed := lines[index].Trim()
            if !string.IsNullOrWhiteSpace(trimmed) && !trimmed.StartsWith("//", StringComparison.Ordinal) {
                nextCodeLine = index + 1
            }

            index = index - 1
        }

        return nextCodeLines
    }

    static func ParseSuppressionCodes(line: string): List<string> {
        marker := "nlc:ignore"
        markerIndex := line.IndexOf(marker, StringComparison.OrdinalIgnoreCase)
        if markerIndex < 0 {
            return new List<string>()
        }

        codesPart := line.Substring(markerIndex + marker.Length).Trim()
        if codesPart.StartsWith(":", StringComparison.Ordinal) {
            codesPart = codesPart.Substring(1).Trim()
        }

        if string.IsNullOrWhiteSpace(codesPart) {
            allCodes := new List<string>()
            allCodes.Add("*")
            return allCodes
        }

        codes := new List<string>()
        currentStart := -1
        index := 0
        while index <= codesPart.Length {
            isDelimiter := true
            if index < codesPart.Length {
                ch := codesPart[index]
                isDelimiter = ch == ',' || ch == ' ' || ch == '\t'
            }

            if isDelimiter {
                if currentStart >= 0 {
                    token := codesPart.Substring(currentStart, index - currentStart).Trim()
                    if !string.IsNullOrWhiteSpace(token) {
                        codes.Add(token.ToUpperInvariant())
                    }

                    currentStart = -1
                }
            } else if currentStart < 0 {
                currentStart = index
            }

            index = index + 1
        }

        return codes
    }

    static func CopyCodes(destination: List<string>, source: List<string>) {
        for sourceItem in source {
            destination.Add(sourceItem)
        }
    }

    static func AddSuppression(suppressions: LinterSuppressionSet, line: int, codes: List<string>) {
        for code in codes {
            suppressions.Add(line, code)
        }
    }
}

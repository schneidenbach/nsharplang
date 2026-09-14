namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.CodeIntelligence

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
        lineCount := GetSourceLineCount(sourceValue)
        pendingCodes := new List<string>()

        lineNumber := 1
        while lineNumber <= lineCount {
            line := GetSourceLine(sourceValue, lineNumber)
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
            nextLine := FindNextCodeLine(sourceValue, lineNumber + 1, lineCount)
            if nextLine > 0 {
                AddSuppression(suppressions, nextLine, pendingCodes)
            }

            pendingCodes.Clear()
            lineNumber = lineNumber + 1
        }

        return suppressions
    }

    static func FindNextCodeLine(sourceText: string, startLine: int, lineCount: int): int {
        lineNumber := startLine
        while lineNumber <= lineCount {
            trimmed := GetSourceLine(sourceText, lineNumber).Trim()
            if string.IsNullOrWhiteSpace(trimmed) {
                lineNumber = lineNumber + 1
                continue
            }

            if trimmed.StartsWith("//", StringComparison.Ordinal) {
                lineNumber = lineNumber + 1
                continue
            }

            return lineNumber
        }

        return -1
    }

    static func GetSourceLine(sourceText: string, oneBasedLine: int): string {
        line := CodeIntelligenceTextUtilities.GetSourceLine(sourceText, oneBasedLine)
        if line == null {
            return ""
        }

        return line
    }

    static func GetSourceLineCount(sourceText: string): int {
        line := 1
        while CodeIntelligenceTextUtilities.GetSourceLine(sourceText, line) != null {
            line = line + 1
        }

        return line - 1
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
        index := 0
        while index < source.Count {
            destination.Add(source[index])
            index = index + 1
        }
    }

    static func AddSuppression(suppressions: LinterSuppressionSet, line: int, codes: List<string>) {
        index := 0
        while index < codes.Count {
            suppressions.Add(line, codes[index])
            index = index + 1
        }
    }
}

namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import NSharpLang.Compiler.CodeIntelligence

class QuerySymbolNameFilter {
    static func Filter(symbols: IReadOnlyList<SymbolResult>, pattern: string, limit: int): List<SymbolResult> {
        results := new List<SymbolResult>()
        if limit <= 0 {
            return results
        }

        if !IsAscii(pattern) {
            throw new InvalidOperationException("N# query symbol-name filter kernel rejected the pattern.")
        }

        useGlob := pattern.IndexOf('*') >= 0
        maxCount := limit
        if maxCount > symbols.Count {
            maxCount = symbols.Count
        }

        i := 0
        while i < symbols.Count && results.Count < maxCount {
            symbol := symbols[i]
            name := symbol.Name
            if !IsAscii(name) {
                throw new InvalidOperationException("N# query symbol-name filter kernel rejected the pattern.")
            }

            matched := false
            if useGlob {
                matched = GlobMatchesAsciiIgnoreCase(name, pattern)
            } else {
                matched = ContainsAsciiIgnoreCase(name, pattern)
            }

            if matched {
                results.Add(symbol)
            }

            i = i + 1
        }

        return results
    }

    static func IsAscii(value: string): bool {
        i := 0
        while i < value.Length {
            if (int)value[i] > 127 {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func ContainsAsciiIgnoreCase(text: string, pattern: string): bool {
        return text.IndexOf(pattern, StringComparison.OrdinalIgnoreCase) >= 0
    }

    static func GlobMatchesAsciiIgnoreCase(text: string, pattern: string): bool {
        if pattern.Length == 1 && pattern[0] == '*' {
            return true
        }

        if pattern.Length > 1 && pattern[0] == '*' && !PatternHasWildcardFrom(pattern, 1) {
            return EndsWithAsciiIgnoreCase(text, pattern, 1, pattern.Length - 1)
        }

        if pattern.Length > 1 && pattern[pattern.Length - 1] == '*' && !PatternHasWildcardBefore(pattern, pattern.Length - 1) {
            return StartsWithAsciiIgnoreCase(text, pattern, 0, pattern.Length - 1)
        }

        textIndex := 0
        patternIndex := 0
        starIndex := -1
        retryTextIndex := 0

        while textIndex < text.Length {
            if patternIndex < pattern.Length {
                patternChar := pattern[patternIndex]
                if patternChar == '*' {
                    starIndex = patternIndex
                    patternIndex = patternIndex + 1
                    retryTextIndex = textIndex
                    continue
                }

                if CharsEqualAsciiIgnoreCase(text[textIndex], patternChar) {
                    textIndex = textIndex + 1
                    patternIndex = patternIndex + 1
                    continue
                }
            }

            if starIndex >= 0 {
                patternIndex = starIndex + 1
                retryTextIndex = retryTextIndex + 1
                textIndex = retryTextIndex
                continue
            }

            return false
        }

        while patternIndex < pattern.Length && pattern[patternIndex] == '*' {
            patternIndex = patternIndex + 1
        }

        return patternIndex == pattern.Length
    }

    static func PatternHasWildcardFrom(pattern: string, start: int): bool {
        i := start
        while i < pattern.Length {
            if pattern[i] == '*' {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func PatternHasWildcardBefore(pattern: string, end: int): bool {
        i := 0
        while i < end {
            if pattern[i] == '*' {
                return true
            }

            i = i + 1
        }

        return false
    }

    static func StartsWithAsciiIgnoreCase(text: string, pattern: string, patternStart: int, patternLength: int): bool {
        if patternLength > text.Length {
            return false
        }

        i := 0
        while i < patternLength {
            if !CharsEqualAsciiIgnoreCase(text[i], pattern[patternStart + i]) {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func EndsWithAsciiIgnoreCase(text: string, pattern: string, patternStart: int, patternLength: int): bool {
        if patternLength > text.Length {
            return false
        }

        textStart := text.Length - patternLength
        i := 0
        while i < patternLength {
            if !CharsEqualAsciiIgnoreCase(text[textStart + i], pattern[patternStart + i]) {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func CharsEqualAsciiIgnoreCase(left: char, right: char): bool {
        leftCode := (int)left
        rightCode := (int)right

        if leftCode >= 65 && leftCode <= 90 {
            leftCode = leftCode + 32
        }

        if rightCode >= 65 && rightCode <= 90 {
            rightCode = rightCode + 32
        }

        return leftCode == rightCode
    }
}

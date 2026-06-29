namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

public class ParserTokenCompactor {
    public static func TryCompact(tokens: List<Token>, out compactedTokens: List<Token>): bool {
        compactedTokens = new List<Token>()
        i := 0
        while i < tokens.Count {
            token := tokens[i]
            if token.Type != TokenType.Newline {
                compactedTokens.Add(token)
            }

            i = i + 1
        }

        return true
    }
}

public class SourceFileDeduplicator {
    public static func TryDeduplicateOrdinalIgnoreCase(sourceFiles: IReadOnlyList<string>, out deduplicatedSourceFiles: List<string>): bool {
        deduplicatedSourceFiles = new List<string>()
        i := 0
        while i < sourceFiles.Count {
            sourceFile := sourceFiles[i]
            if sourceFile == null {
                deduplicatedSourceFiles = new List<string>()
                return false
            }

            if !ContainsOrdinalIgnoreCase(deduplicatedSourceFiles, sourceFile) {
                deduplicatedSourceFiles.Add(sourceFile)
            }

            i = i + 1
        }

        return true
    }

    static func ContainsOrdinalIgnoreCase(files: List<string>, value: string): bool {
        i := 0
        while i < files.Count {
            if String.Compare(files[i], value, StringComparison.OrdinalIgnoreCase) == 0 {
                return true
            }

            i = i + 1
        }

        return false
    }
}

public class ProjectSourceFileFilter {
    public static func Filter(files: string[], projectRoot: string, excludePatterns: string[], includeTests: bool): string[] {
        relativePaths := new string[](files.Length)
        resultIndices := new int[](files.Length)

        i := 0
        while i < files.Length {
            relativePaths[i] = Path.GetRelativePath(projectRoot, files[i])
            i = i + 1
        }

        keptCount := ProjectSourceFilterKeptIndices(relativePaths, excludePatterns, includeTests, resultIndices)
        result := new string[](keptCount)

        j := 0
        while j < keptCount {
            result[j] = files[resultIndices[j]]
            j = j + 1
        }

        return result
    }

    static func ProjectSourceFilterKeptIndices(
        relativePaths: string[],
        excludePatterns: string[],
        includeTests: bool,
        resultIndices: int[]): int {
        resultCount := 0
        i := 0
        while i < relativePaths.Length {
            path := relativePaths[i]
            keep := true

            if !includeTests {
                if ProjectSourceFilterIsTestFile(path) {
                    keep = false
                }
            }

            if keep {
                if ProjectSourceFilterIsExcluded(path, excludePatterns) {
                    keep = false
                }
            }

            if keep {
                if resultCount < resultIndices.Length {
                    resultIndices[resultCount] = i
                }

                resultCount = resultCount + 1
            }

            i = i + 1
        }

        return resultCount
    }

    static func ProjectSourceFilterIsTestFile(path: string): bool {
        suffixLength := 9
        if path.Length < suffixLength {
            return false
        }

        start := path.Length - suffixLength
        if !ProjectSourceFilterCharEqualsIgnoreCase(path[start], '.') {
            return false
        }

        if !ProjectSourceFilterCharEqualsIgnoreCase(path[start + 1], 't') {
            return false
        }

        if !ProjectSourceFilterCharEqualsIgnoreCase(path[start + 2], 'e') {
            return false
        }

        if !ProjectSourceFilterCharEqualsIgnoreCase(path[start + 3], 's') {
            return false
        }

        if !ProjectSourceFilterCharEqualsIgnoreCase(path[start + 4], 't') {
            return false
        }

        if !ProjectSourceFilterCharEqualsIgnoreCase(path[start + 5], 's') {
            return false
        }

        if !ProjectSourceFilterCharEqualsIgnoreCase(path[start + 6], '.') {
            return false
        }

        if !ProjectSourceFilterCharEqualsIgnoreCase(path[start + 7], 'n') {
            return false
        }

        return ProjectSourceFilterCharEqualsIgnoreCase(path[start + 8], 'l')
    }

    static func ProjectSourceFilterIsExcluded(path: string, excludePatterns: string[]): bool {
        j := 0
        while j < excludePatterns.Length {
            if ProjectSourceFilterMatchesPattern(path, excludePatterns[j]) {
                return true
            }

            j = j + 1
        }

        return false
    }

    static func ProjectSourceFilterMatchesPattern(path: string, pattern: string): bool {
        return ProjectSourceFilterMatchFrom(path, 0, pattern, 0)
    }

    static func ProjectSourceFilterMatchFrom(
        path: string,
        pathIndex: int,
        pattern: string,
        patternIndex: int): bool {
        pi := pathIndex
        qi := patternIndex

        while qi < pattern.Length {
            pc := ProjectSourceFilterNormalizeSlash(pattern[qi])

            if pc == '*' {
                isDouble := false
                if qi + 1 < pattern.Length {
                    if ProjectSourceFilterNormalizeSlash(pattern[qi + 1]) == '*' {
                        isDouble = true
                    }
                }

                if isDouble {
                    afterStars := qi + 2
                    hasSlash := false
                    if afterStars < pattern.Length {
                        if ProjectSourceFilterNormalizeSlash(pattern[afterStars]) == '/' {
                            hasSlash = true
                        }
                    }

                    if hasSlash {
                        nextPattern := afterStars + 1
                        scan := pi
                        while scan < path.Length {
                            if path[scan] == '\n' {
                                return false
                            }

                            crossedSlash := ProjectSourceFilterNormalizeSlash(path[scan]) == '/'
                            scan = scan + 1
                            if crossedSlash {
                                if ProjectSourceFilterMatchFrom(path, scan, pattern, nextPattern) {
                                    return true
                                }
                            }
                        }

                        return false
                    }

                    nextPattern := afterStars
                    limit := pi
                    while limit < path.Length {
                        if path[limit] == '\n' {
                            break
                        }

                        limit = limit + 1
                    }

                    k := limit
                    while k >= pi {
                        if ProjectSourceFilterMatchFrom(path, k, pattern, nextPattern) {
                            return true
                        }

                        k = k - 1
                    }

                    return false
                }

                limit := pi
                while limit < path.Length {
                    if ProjectSourceFilterNormalizeSlash(path[limit]) == '/' {
                        break
                    }

                    limit = limit + 1
                }

                nextPattern := qi + 1
                k := limit
                while k >= pi {
                    if ProjectSourceFilterMatchFrom(path, k, pattern, nextPattern) {
                        return true
                    }

                    k = k - 1
                }

                return false
            }

            if pc == '?' {
                if pi >= path.Length {
                    return false
                }

                if path[pi] == '\n' {
                    return false
                }

                pi = pi + 1
                qi = qi + 1
                continue
            }

            if pi >= path.Length {
                return false
            }

            if ProjectSourceFilterNormalizeSlash(path[pi]) != pc {
                return false
            }

            pi = pi + 1
            qi = qi + 1
        }

        if pi == path.Length {
            return true
        }

        if pi == path.Length - 1 {
            if path[pi] == '\n' {
                return true
            }
        }

        return false
    }

    static func ProjectSourceFilterNormalizeSlash(ch: char): char {
        if ch == '\\' {
            return '/'
        }

        return ch
    }

    static func ProjectSourceFilterCharEqualsIgnoreCase(left: char, right: char): bool {
        if left == right {
            return true
        }

        if left >= 'A' {
            if left <= 'Z' {
                if right >= 'a' {
                    if right <= 'z' {
                        return left - 'A' == right - 'a'
                    }
                }
            }
        }

        if left >= 'a' {
            if left <= 'z' {
                if right >= 'A' {
                    if right <= 'Z' {
                        return left - 'a' == right - 'A'
                    }
                }
            }
        }

        return Char.ToUpperInvariant(left) == Char.ToUpperInvariant(right)
    }
}

public class AssemblyVersionKernels {
    public static func TryParseComponent(component: string, out value: int): bool {
        value = 0
        if component.Length == 0 {
            return false
        }

        parsed := 0
        index := 0
        while index < component.Length {
            ch := component[index]
            if ch < '0' || ch > '9' {
                return false
            }

            digit := ch - '0'
            if parsed > 214748364 {
                return false
            }

            if parsed == 214748364 {
                if digit > 7 {
                    return false
                }
            }

            parsed = parsed * 10 + digit
            index = index + 1
        }

        value = parsed
        return true
    }
}

public class FormatterConfigKernels {
    public static func ParseInt(value: string): int? {
        start := 0
        end := value.Length
        while start < end {
            if !IsWhiteSpace(value[start]) {
                break
            }

            start = start + 1
        }

        while end > start {
            if !IsWhiteSpace(value[end - 1]) {
                break
            }

            end = end - 1
        }

        if start >= end {
            return null
        }

        negative := false
        if value[start] == '+' || value[start] == '-' {
            negative = value[start] == '-'
            start = start + 1
            if start >= end {
                return null
            }
        }

        parsed := 0
        index := start
        while index < end {
            ch := value[index]
            if ch < '0' || ch > '9' {
                return null
            }

            digit := ch - '0'
            if parsed > 214748364 {
                return null
            }

            if parsed == 214748364 {
                if negative {
                    if digit == 8 && index == end - 1 {
                        return 0 - 2147483647 - 1
                    }

                    return null
                }

                if digit > 7 {
                    return null
                }
            }

            parsed = parsed * 10 + digit
            index = index + 1
        }

        if negative {
            return 0 - parsed
        }

        return parsed
    }

    static func IsWhiteSpace(ch: char): bool {
        if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
            return true
        }

        return char.IsWhiteSpace(ch)
    }
}

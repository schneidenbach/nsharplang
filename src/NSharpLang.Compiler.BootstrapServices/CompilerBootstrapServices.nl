namespace NSharpLang.Compiler

import System
import System.Collections.Generic

public class ParserTokenCompactor {
    public static func TryCompact<T>(tokens: IReadOnlyList<T>, out compactedTokens: List<T>): bool {
        compactedTokens = new List<T>()
        i := 0
        while i < tokens.Count {
            token := tokens[i]
            kind := TokenKind(token)
            if kind < 0 {
                compactedTokens = new List<T>()
                return false
            }

            if kind != 136 {
                compactedTokens.Add(token)
            }

            i = i + 1
        }

        return true
    }

    public static func TokenKind(token: object): int {
        property := token.GetType().GetProperty("Type")
        if property == null {
            return -1
        }

        value := property.GetValue(token)
        if value == null {
            return -1
        }

        return Convert.ToInt32(value)
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

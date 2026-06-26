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

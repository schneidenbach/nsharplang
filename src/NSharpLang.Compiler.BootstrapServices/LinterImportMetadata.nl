namespace NSharpLang.Compiler

import System

public class LinterImportSpan {
    columnValue: int
    lengthValue: int

    Column: int => columnValue
    Length: int => lengthValue

    constructor(column: int, length: int) {
        columnValue = column
        lengthValue = length
    }
}

public class LinterImportMetadata {
    public static func ResolveNamespaceImportSpan(
        importColumn: int,
        namespaceName: string,
        sourceLine: string): LinterImportSpan {
        keyword := "import"
        keywordStart := importColumn - 1

        if sourceLine.Length == 0 || keywordStart < 0 || keywordStart >= sourceLine.Length {
            return new LinterImportSpan(importColumn, 0)
        }

        pathStart := keywordStart + keyword.Length
        while pathStart < sourceLine.Length && char.IsWhiteSpace(sourceLine[pathStart]) {
            pathStart = pathStart + 1
        }

        if pathStart >= sourceLine.Length {
            return new LinterImportSpan(importColumn, 0)
        }

        return new LinterImportSpan(pathStart + 1, namespaceName.Length)
    }

    public static func ExtractFileImportSymbolName(path: string, alias: string?): string? {
        if !string.IsNullOrWhiteSpace(alias) {
            return alias
        }

        fileName := GetFileNameWithoutExtension(path)
        if string.IsNullOrWhiteSpace(fileName) {
            return null
        }

        return fileName
    }

    static func GetFileNameWithoutExtension(path: string): string {
        start := 0
        index := path.Length - 1
        while index >= 0 {
            ch := path[index]
            if ch == '/' || ch == '\\' {
                start = index + 1
                break
            }

            index = index - 1
        }

        end := path.Length
        index = path.Length - 1
        while index >= start {
            if path[index] == '.' {
                end = index
                break
            }

            index = index - 1
        }

        if end <= start {
            return ""
        }

        return path.Substring(start, end - start)
    }
}

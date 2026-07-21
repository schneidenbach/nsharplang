namespace NSharpLang.Compiler

public class LinterBlockOwnerSpan {
    lineValue: int
    columnValue: int
    lengthValue: int

    Line: int => lineValue
    Column: int => columnValue
    Length: int => lengthValue

    constructor(line: int, column: int, length: int) {
        lineValue = line
        columnValue = column
        lengthValue = length
    }
}

public class LinterBlockOwnerSpanResolver {
    public static func Resolve(blockLine: int, blockColumn: int, sourceLine: string): LinterBlockOwnerSpan {
        if string.IsNullOrEmpty(sourceLine) {
            return new LinterBlockOwnerSpan(blockLine, blockColumn, 1)
        }

        searchEnd := sourceLine.Length
        if blockColumn > 0 {
            searchEnd = blockColumn - 1
            if searchEnd < 0 {
                searchEnd = 0
            }

            if searchEnd > sourceLine.Length {
                searchEnd = sourceLine.Length
            }
        }

        prefix := sourceLine.Substring(0, searchEnd)
        keywords := BlockOwnerKeywords()

        bestColumn := 0
        bestLength := 0
        index := 0
        while index < keywords.Length {
            keyword := keywords[index]
            column := FindKeywordColumn(prefix, keyword)
            if column > bestColumn {
                bestColumn = column
                bestLength = keyword.Length
            }

            index = index + 1
        }

        if bestColumn > 0 {
            return new LinterBlockOwnerSpan(blockLine, bestColumn, bestLength)
        }

        return new LinterBlockOwnerSpan(blockLine, blockColumn, 1)
    }

    static func BlockOwnerKeywords(): string[] {
        keywords := new string[](15)
        keywords[0] = "foreach"
        keywords[1] = "finally"
        keywords[2] = "throws"
        keywords[3] = "catch"
        keywords[4] = "while"
        keywords[5] = "switch"
        keywords[6] = "assert"
        keywords[7] = "using"
        keywords[8] = "lock"
        keywords[9] = "else"
        keywords[10] = "func"
        keywords[11] = "test"
        keywords[12] = "try"
        keywords[13] = "for"
        keywords[14] = "if"
        return keywords
    }

    static func FindKeywordColumn(text: string, keyword: string): int {
        searchIndex := text.Length - keyword.Length
        while searchIndex >= 0 {
            if MatchesAt(text, keyword, searchIndex) {
                beforeIsIdentifier := searchIndex > 0 && IsIdentifierPart(text[searchIndex - 1])
                afterIndex := searchIndex + keyword.Length
                afterIsIdentifier := afterIndex < text.Length && IsIdentifierPart(text[afterIndex])
                if !beforeIsIdentifier && !afterIsIdentifier {
                    return searchIndex + 1
                }
            }

            searchIndex = searchIndex - 1
        }

        return 0
    }

    static func MatchesAt(text: string, value: string, start: int): bool {
        if start < 0 || start + value.Length > text.Length {
            return false
        }

        index := 0
        while index < value.Length {
            if text[start + index] != value[index] {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func IsIdentifierPart(ch: char): bool {
        return char.IsLetterOrDigit(ch) || ch == '_'
    }
}

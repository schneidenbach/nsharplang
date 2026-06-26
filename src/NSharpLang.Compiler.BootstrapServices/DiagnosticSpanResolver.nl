namespace NSharpLang.Compiler

import System

public class DiagnosticSpanResult {
    columnValue: int
    lengthValue: int

    Column: int => columnValue
    Length: int => lengthValue

    constructor(Column: int, Length: int) {
        columnValue = Column
        lengthValue = Length
    }
}

public class DiagnosticSpanResolver {
    public static func Resolve(sourceLine: string?, oneBasedColumn: int, requestedLength: int): DiagnosticSpanResult {
        if requestedLength > 0 {
            return new DiagnosticSpanResult(oneBasedColumn, Math.Max(1, requestedLength))
        }

        if sourceLine == null {
            return new DiagnosticSpanResult(oneBasedColumn, 1)
        }

        line := sourceLine ?? ""

        if line.Length == 0 {
            return new DiagnosticSpanResult(oneBasedColumn, 1)
        }

        start := oneBasedColumn - 1
        if start < 0 || start >= line.Length {
            return new DiagnosticSpanResult(oneBasedColumn, 1)
        }

        if char.IsWhiteSpace(line[start]) {
            visibleStart := FindNextVisibleTokenStart(line, start)
            if visibleStart < 0 {
                visibleStart = FindPreviousVisibleTokenStart(line, start)
            }

            if visibleStart >= 0 {
                return new DiagnosticSpanResult(
                    visibleStart + 1,
                    InferVisibleTokenLength(line, visibleStart))
            }

            return new DiagnosticSpanResult(oneBasedColumn, 1)
        }

        return new DiagnosticSpanResult(oneBasedColumn, InferVisibleTokenLength(line, start))
    }

    static func FindNextVisibleTokenStart(sourceLine: string, start: int): int {
        index := start
        while index < sourceLine.Length {
            if !char.IsWhiteSpace(sourceLine[index]) {
                return index
            }

            index = index + 1
        }

        return -1
    }

    static func FindPreviousVisibleTokenStart(sourceLine: string, start: int): int {
        index := Math.Min(start, sourceLine.Length - 1)
        while index >= 0 {
            if !char.IsWhiteSpace(sourceLine[index]) {
                break
            }

            index = index - 1
        }

        if index < 0 {
            return -1
        }

        if IsIdentifierPart(sourceLine[index]) {
            while index > 0 {
                if !IsIdentifierPart(sourceLine[index - 1]) {
                    break
                }

                index = index - 1
            }
        }

        return index
    }

    static func IsIdentifierPart(ch: char): bool {
        return char.IsLetterOrDigit(ch) || ch == '_'
    }

    static func InferVisibleTokenLength(sourceLine: string, zeroBasedStart: int): int {
        if zeroBasedStart < 0 || zeroBasedStart >= sourceLine.Length {
            return 1
        }

        if sourceLine[zeroBasedStart] == '"' {
            return ScanQuotedDiagnosticTokenLength(sourceLine, zeroBasedStart, '"')
        }

        if sourceLine[zeroBasedStart] == '\'' {
            return ScanQuotedDiagnosticTokenLength(sourceLine, zeroBasedStart, '\'')
        }

        if sourceLine[zeroBasedStart] == '$' {
            if zeroBasedStart + 1 < sourceLine.Length {
                if sourceLine[zeroBasedStart + 1] == '"' {
                    return 1 + ScanQuotedDiagnosticTokenLength(sourceLine, zeroBasedStart + 1, '"')
                }
            }
        }

        if IsIdentifierPart(sourceLine[zeroBasedStart]) {
            return ScanIdentifierLikeTokenLength(sourceLine, zeroBasedStart)
        }

        return MatchOperatorLength(sourceLine, zeroBasedStart)
    }

    static func ScanIdentifierLikeTokenLength(sourceLine: string, zeroBasedStart: int): int {
        end := zeroBasedStart + 1
        while end < sourceLine.Length {
            ch := sourceLine[end]

            if char.IsLetterOrDigit(ch) || ch == '_' {
                end = end + 1
                continue
            }

            if ch == '.' {
                if end + 1 < sourceLine.Length {
                    if IsIdentifierPart(sourceLine[end + 1]) {
                        end = end + 1
                        continue
                    }
                }
            }

            if ch == '!' || ch == '?' {
                if end + 1 >= sourceLine.Length {
                    end = end + 1
                    continue
                }

                if !IsOperatorChar(sourceLine[end + 1]) {
                    end = end + 1
                    continue
                }
            }

            break
        }

        return end - zeroBasedStart
    }

    static func MatchOperatorLength(sourceLine: string, zeroBasedStart: int): int {
        length := MatchOperator(sourceLine, zeroBasedStart, "??=")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "...")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, ":=")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "::")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "==")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "=>")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "!=")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "<=")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "<<")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, ">=")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, ">>")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "&&")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "||")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "++")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "+=")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "--")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "-=")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "*=")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "/=")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "??")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "?.")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "?[")
        if length > 0 { return length }

        length = MatchOperator(sourceLine, zeroBasedStart, "..")
        if length > 0 { return length }

        return 1
    }

    static func MatchOperator(sourceLine: string, zeroBasedStart: int, op: string): int {
        if zeroBasedStart + op.Length > sourceLine.Length {
            return 0
        }

        if String.Compare(sourceLine, zeroBasedStart, op, 0, op.Length, StringComparison.Ordinal) == 0 {
            return op.Length
        }

        return 0
    }

    static func IsOperatorChar(ch: char): bool {
        if ch == ':' { return true }
        if ch == '=' { return true }
        if ch == '!' { return true }
        if ch == '<' { return true }
        if ch == '>' { return true }
        if ch == '&' { return true }
        if ch == '|' { return true }
        if ch == '+' { return true }
        if ch == '-' { return true }
        if ch == '*' { return true }
        if ch == '/' { return true }
        if ch == '?' { return true }
        if ch == '.' { return true }
        if ch == '%' { return true }
        if ch == '^' { return true }
        return ch == '~'
    }

    static func ScanQuotedDiagnosticTokenLength(sourceLine: string, quoteStart: int, quote: char): int {
        index := quoteStart + 1
        while index < sourceLine.Length {
            if sourceLine[index] == '\\' {
                index = index + 2
                continue
            }

            if sourceLine[index] == quote {
                return index - quoteStart + 1
            }

            index = index + 1
        }

        return Math.Max(1, sourceLine.Length - quoteStart)
    }
}

namespace NSharpLang.Compiler.Ast

import System

struct SourceSpan(startLine: int, startColumn: int, endLine: int, endColumn: int) {
    StartLine: int = startLine
    StartColumn: int = startColumn
    EndLine: int = endLine
    EndColumn: int = endColumn

    static None: SourceSpan => new SourceSpan(0, 0, 0, 0)

    IsValid: bool => StartLine > 0 && StartColumn > 0 && EndLine > 0 && EndColumn > 0

    Length: int => ComputeLength(IsValid, StartLine, StartColumn, EndLine, EndColumn)

    func Contains(line: int, column: int): bool {
        if !IsValid {
            return false
        }

        if line < StartLine || line > EndLine {
            return false
        }

        if line == StartLine && column < StartColumn {
            return false
        }

        if line == EndLine && column >= EndColumn {
            return false
        }

        return true
    }

    static func FromStartAndLength(line: int, column: int, length: int): SourceSpan {
        if line <= 0 || column <= 0 {
            return SourceSpan.None
        }

        return new SourceSpan(line, column, line, column + Math.Max(1, length))
    }

    static func ComputeLength(isValid: bool, startLine: int, startColumn: int, endLine: int, endColumn: int): int {
        if isValid && startLine == endLine {
            return Math.Max(0, endColumn - startColumn)
        }

        return 0
    }

    func EqualsSpan(other: SourceSpan): bool {
        return StartLine == other.StartLine && StartColumn == other.StartColumn && EndLine == other.EndLine && EndColumn == other.EndColumn
    }

    override func Equals(value: object): bool {
        if value == null {
            return false
        }

        if value.GetType() != typeof(SourceSpan) {
            return false
        }

        return EqualsSpan((SourceSpan)value)
    }

    override func GetHashCode(): int {
        hash := 17
        hash = hash * 23 + StartLine
        hash = hash * 23 + StartColumn
        hash = hash * 23 + EndLine
        hash = hash * 23 + EndColumn
        return hash
    }

    static func operator ==(left: SourceSpan, right: SourceSpan): bool => left.EqualsSpan(right)

    static func operator !=(left: SourceSpan, right: SourceSpan): bool => !left.EqualsSpan(right)
}

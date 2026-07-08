namespace NSharpLang.Compiler.Columnar

import NSharpLang.Compiler
import System.Collections.Generic

public class ColumnarSyntaxDiagnostics {
    public static func ParseFile(source: string, fileName: string): List<CompilerError> {
        sources := new string[](1)
        fileNames := new string[](1)
        sources[0] = source
        fileNames[0] = fileName
        sourceFiles := ColumnarEmissionPlanner.BuildSourceFiles(sources, fileNames)

        table := new ParserDiagnosticTable(source.Length + 1)
        lexer := new Lexer(source, fileName)
        tokens := lexer.Tokenize()
        CollectReservedKeywordNameDiagnostics(sourceFiles[0], tokens, table)
        return ParserDiagnosticMessages.Materialize(table, sourceFiles)
    }

    static func CollectReservedKeywordNameDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable) {
        index := 0
        while index < tokens.Count {
            token := tokens[index]
            if IsPanicResetBoundary(token.Type) {
                ParserDiagnosticTableOps.ResetPanicMode(table)
            }

            if Lexer.IsReservedKeyword(token.Type) {
                previous := PreviousSignificantToken(tokens, index)
                next := NextSignificantToken(tokens, index)
                contextKind := ParserDiagnosticContextKind.Unknown()

                if previous != null && (previous.Type == TokenType.Dot || previous.Type == TokenType.QuestionDot) {
                    contextKind = ParserDiagnosticContextKind.DotMember()
                } else if next != null && (next.Type == TokenType.Colon || next.Type == TokenType.ColonAssign) {
                    if IsInsideParameterList(tokens, index) {
                        contextKind = ParserDiagnosticContextKind.Parameter()
                    } else {
                        contextKind = ParserDiagnosticContextKind.Field()
                    }
                }

                if contextKind != ParserDiagnosticContextKind.Unknown() {
                    start := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, token.Line, token.Column)
                    ParserDiagnosticTableOps.Report(
                        table,
                        sourceFile.FileId,
                        (int)ErrorCode.ReservedKeywordAsName,
                        start,
                        token.Value.Length,
                        token.Line,
                        token.Column,
                        ParserDiagnosticMessageKind.ReservedKeywordAsName(),
                        contextKind,
                        start,
                        token.Value.Length,
                        -1,
                        0)
                }
            }

            index = index + 1
        }
    }

    static func IsInsideParameterList(tokens: List<Token>, tokenIndex: int): bool {
        depth := 0
        index := tokenIndex - 1
        while index >= 0 {
            token := tokens[index]
            if token.Type == TokenType.RightParen {
                depth = depth + 1
            } else if token.Type == TokenType.LeftParen {
                if depth == 0 {
                    owner := PreviousSignificantToken(tokens, index)
                    if owner == null {
                        return false
                    }

                    return owner.Type == TokenType.Identifier
                        || owner.Type == TokenType.This
                        || owner.Type == TokenType.Base
                }

                depth = depth - 1
            }

            index = index - 1
        }

        return false
    }

    static func PreviousSignificantToken(tokens: List<Token>, tokenIndex: int): Token? {
        index := tokenIndex - 1
        while index >= 0 {
            token := tokens[index]
            if token.Type != TokenType.Newline {
                return token
            }

            index = index - 1
        }

        return null
    }

    static func NextSignificantToken(tokens: List<Token>, tokenIndex: int): Token? {
        index := tokenIndex + 1
        while index < tokens.Count {
            token := tokens[index]
            if token.Type != TokenType.Newline {
                return token
            }

            index = index + 1
        }

        return null
    }

    static func IsPanicResetBoundary(tokenType: TokenType): bool {
        return tokenType == TokenType.Newline
            || tokenType == TokenType.Semicolon
            || tokenType == TokenType.Comma
            || tokenType == TokenType.RightBrace
    }

    static func OffsetFromLineColumn(lineStarts: int[], sourceLength: int, line: int, column: int): int {
        if line <= 0 || column <= 0 {
            return 0
        }

        lineIndex := line - 1
        if lineIndex < 0 || lineIndex >= lineStarts.Length {
            return sourceLength
        }

        offset := lineStarts[lineIndex] + column - 1
        if offset < 0 {
            return 0
        }

        if offset > sourceLength {
            return sourceLength
        }

        return offset
    }
}

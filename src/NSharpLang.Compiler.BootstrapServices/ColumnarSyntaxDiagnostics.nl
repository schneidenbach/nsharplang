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
        CollectMissingDeclarationNameDiagnostics(sourceFiles[0], tokens, table)
        CollectExpectedMemberNameDiagnostics(sourceFiles[0], tokens, table)
        CollectReservedKeywordNameDiagnostics(sourceFiles[0], tokens, table)
        return ParserDiagnosticMessages.Materialize(table, sourceFiles)
    }

    static func CollectMissingDeclarationNameDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable) {
        index := 0
        while index < tokens.Count {
            token := tokens[index]
            if IsPanicResetBoundary(token.Type) {
                ParserDiagnosticTableOps.ResetPanicMode(table)
            }

            contextKind := DeclarationNameContext(token.Type)
            if contextKind != ParserDiagnosticContextKind.Unknown() && IsDeclarationKeywordPosition(tokens, index) {
                candidateIndex := NextSignificantTokenIndex(tokens, index)
                if token.Type == TokenType.Func && candidateIndex >= 0 {
                    candidate := tokens[candidateIndex]
                    if candidate.Type == TokenType.Star {
                        candidateIndex = NextSignificantTokenIndex(tokens, candidateIndex)
                    }
                } else if token.Type == TokenType.Record && candidateIndex >= 0 {
                    candidate := tokens[candidateIndex]
                    if candidate.Type == TokenType.Struct {
                        candidateIndex = NextSignificantTokenIndex(tokens, candidateIndex)
                    }
                }

                if ShouldReportMissingDeclarationName(tokens, token.Type, candidateIndex) {
                    start := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, token.Line, token.Column)
                    currentStart := -1
                    currentLength := 0
                    if candidateIndex >= 0 {
                        current := tokens[candidateIndex]
                        currentStart = OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, current.Line, current.Column)
                        currentLength = current.Value.Length
                    }

                    ParserDiagnosticTableOps.Report(
                        table,
                        sourceFile.FileId,
                        (int)ErrorCode.ExpectedToken,
                        start,
                        token.Value.Length,
                        token.Line,
                        token.Column,
                        ParserDiagnosticMessageKind.ExpectedDeclarationName(),
                        contextKind,
                        start,
                        token.Value.Length,
                        currentStart,
                        currentLength)
                }
            }

            index = index + 1
        }
    }

    static func CollectExpectedMemberNameDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable) {
        index := 0
        while index < tokens.Count {
            token := tokens[index]
            if IsPanicResetBoundary(token.Type) {
                ParserDiagnosticTableOps.ResetPanicMode(table)
            }

            if token.Type == TokenType.Dot || token.Type == TokenType.QuestionDot {
                next := NextSignificantToken(tokens, index)
                if next == null || (next.Type != TokenType.Identifier && !Lexer.IsReservedKeyword(next.Type)) {
                    receiver := PreviousSignificantToken(tokens, index)
                    line := token.Line
                    column := token.Column
                    length := token.Value.Length
                    receiverStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, token.Line, token.Column)

                    if receiver != null {
                        line = receiver.Line
                        column = receiver.Column
                        length = receiver.Value.Length
                        receiverStart = OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, receiver.Line, receiver.Column)
                    }

                    dotStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, token.Line, token.Column)
                    currentStart := -1
                    currentLength := 0
                    if next != null {
                        currentStart = OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, next.Line, next.Column)
                        currentLength = next.Value.Length
                    }

                    ParserDiagnosticTableOps.Report(
                        table,
                        sourceFile.FileId,
                        (int)ErrorCode.ExpectedToken,
                        receiverStart,
                        length,
                        line,
                        column,
                        ParserDiagnosticMessageKind.ExpectedMemberNameAfterDot(),
                        ParserDiagnosticContextKind.DotMember(),
                        dotStart,
                        token.Value.Length,
                        currentStart,
                        currentLength)
                }
            }

            index = index + 1
        }
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

    static func DeclarationNameContext(tokenType: TokenType): int {
        if tokenType == TokenType.Func {
            return ParserDiagnosticContextKind.FunctionDeclaration()
        }

        if tokenType == TokenType.Class {
            return ParserDiagnosticContextKind.ClassDeclaration()
        }

        if tokenType == TokenType.Struct {
            return ParserDiagnosticContextKind.StructDeclaration()
        }

        if tokenType == TokenType.Record {
            return ParserDiagnosticContextKind.RecordDeclaration()
        }

        if tokenType == TokenType.Interface {
            return ParserDiagnosticContextKind.InterfaceDeclaration()
        }

        if tokenType == TokenType.Union {
            return ParserDiagnosticContextKind.UnionDeclaration()
        }

        if tokenType == TokenType.Enum {
            return ParserDiagnosticContextKind.EnumDeclaration()
        }

        if tokenType == TokenType.Type {
            return ParserDiagnosticContextKind.TypeAliasDeclaration()
        }

        return ParserDiagnosticContextKind.Unknown()
    }

    static func IsDeclarationKeywordPosition(tokens: List<Token>, tokenIndex: int): bool {
        token := tokens[tokenIndex]
        previous := PreviousSignificantToken(tokens, tokenIndex)
        if token.Type == TokenType.Interface && previous != null && previous.Type == TokenType.Duck {
            return true
        }

        if token.Type == TokenType.Struct && previous != null && previous.Type == TokenType.Record {
            return false
        }

        if previous == null {
            return true
        }

        if previous.Type == TokenType.LeftBrace
            || previous.Type == TokenType.RightBrace
            || previous.Type == TokenType.Semicolon {
            return true
        }

        return IsDeclarationModifier(previous.Type)
    }

    static func IsDeclarationModifier(tokenType: TokenType): bool {
        return tokenType == TokenType.Public
            || tokenType == TokenType.Private
            || tokenType == TokenType.Internal
            || tokenType == TokenType.Protected
            || tokenType == TokenType.Static
            || tokenType == TokenType.Abstract
            || tokenType == TokenType.Sealed
            || tokenType == TokenType.Partial
            || tokenType == TokenType.Virtual
            || tokenType == TokenType.Override
            || tokenType == TokenType.Async
            || tokenType == TokenType.Readonly
            || tokenType == TokenType.Immutable
            || tokenType == TokenType.File
    }

    static func ShouldReportMissingDeclarationName(tokens: List<Token>, declarationType: TokenType, candidateIndex: int): bool {
        if candidateIndex < 0 || candidateIndex >= tokens.Count {
            return false
        }

        candidate := tokens[candidateIndex]
        if candidate.Type == TokenType.Identifier {
            return false
        }

        if declarationType == TokenType.Func && candidate.Type == TokenType.Operator {
            return false
        }

        return true
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

    static func NextSignificantTokenIndex(tokens: List<Token>, tokenIndex: int): int {
        index := tokenIndex + 1
        while index < tokens.Count {
            token := tokens[index]
            if token.Type != TokenType.Newline {
                return index
            }

            index = index + 1
        }

        return -1
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

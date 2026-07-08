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
        CollectGenericListDiagnostics(sourceFiles[0], tokens, table)
        CollectFunctionReturnTypeDiagnostics(sourceFiles[0], tokens, table)
        CollectObjectConstructionDiagnostics(sourceFiles[0], tokens, table)
        CollectParameterListDiagnostics(sourceFiles[0], tokens, table)
        CollectFieldDeclarationDiagnostics(sourceFiles[0], tokens, table)
        CollectLeadingMemberAccessDiagnostics(sourceFiles[0], tokens, table)
        CollectExpectedMemberNameDiagnostics(sourceFiles[0], tokens, table)
        CollectReservedKeywordNameDiagnostics(sourceFiles[0], tokens, table)
        return ParserDiagnosticMessages.Materialize(table, sourceFiles)
    }

    static func CollectFunctionReturnTypeDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable) {
        index := 0
        while index < tokens.Count {
            token := tokens[index]
            if IsPanicResetBoundary(token.Type) {
                ParserDiagnosticTableOps.ResetPanicMode(table)
            }

            if token.Type == TokenType.Func {
                AnalyzeFunctionReturnTypeMarker(sourceFile, tokens, table, index)
            }

            index = index + 1
        }
    }

    static func AnalyzeFunctionReturnTypeMarker(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        funcIndex: int) {
        nameIndex := NextSignificantTokenIndex(tokens, funcIndex)
        if nameIndex >= 0 && tokens[nameIndex].Type == TokenType.Star {
            nameIndex = NextSignificantTokenIndex(tokens, nameIndex)
        }

        if nameIndex < 0 || tokens[nameIndex].Type != TokenType.Identifier {
            return
        }

        afterNameIndex := NextSignificantTokenIndex(tokens, nameIndex)
        if afterNameIndex >= 0 && tokens[afterNameIndex].Type == TokenType.Less {
            greaterIndex := FindMatchingGreater(tokens, afterNameIndex)
            if greaterIndex < 0 {
                return
            }

            afterNameIndex = NextSignificantTokenIndex(tokens, greaterIndex)
        }

        if afterNameIndex < 0 || tokens[afterNameIndex].Type != TokenType.LeftParen {
            return
        }

        closeParenIndex := FindMatchingRightParen(tokens, afterNameIndex)
        if closeParenIndex < 0 {
            return
        }

        returnTypeIndex := NextSignificantTokenIndex(tokens, closeParenIndex)
        if returnTypeIndex < 0 {
            return
        }

        closeParen := tokens[closeParenIndex]
        returnType := tokens[returnTypeIndex]
        if returnType.Line != closeParen.Line || !ParserTokenFacts.IsTypeReferenceStart(returnType.Type) {
            return
        }

        nameToken := tokens[nameIndex]
        nameStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, nameToken.Line, nameToken.Column)
        returnTypeStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, returnType.Line, returnType.Column)
        ParserDiagnosticTableOps.Report(
            table,
            sourceFile.FileId,
            (int)ErrorCode.ExpectedToken,
            nameStart,
            nameToken.Value.Length,
            nameToken.Line,
            nameToken.Column,
            ParserDiagnosticMessageKind.ExpectedReturnTypeColon(),
            ParserDiagnosticContextKind.FunctionDeclaration(),
            nameStart,
            nameToken.Value.Length,
            returnTypeStart,
            returnType.Value.Length)
    }

    static func CollectObjectConstructionDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable) {
        index := 0
        while index < tokens.Count {
            token := tokens[index]
            if IsPanicResetBoundary(token.Type) {
                ParserDiagnosticTableOps.ResetPanicMode(table)
            }

            if token.Type == TokenType.New {
                AnalyzeNewExpressionDiagnostics(sourceFile, tokens, table, index)
            }

            index = index + 1
        }
    }

    static func AnalyzeNewExpressionDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        newIndex: int) {
        nextIndex := NextSignificantTokenIndex(tokens, newIndex)
        if nextIndex < 0 {
            return
        }

        next := tokens[nextIndex]
        if next.Type == TokenType.LeftBrace {
            CollectObjectInitializerMemberDiagnostics(sourceFile, tokens, table, nextIndex)
            return
        }

        if next.Type == TokenType.LeftParen {
            closeParenIndex := FindMatchingRightParen(tokens, nextIndex)
            if closeParenIndex >= 0 {
                afterArgsIndex := NextSignificantTokenIndex(tokens, closeParenIndex)
                if afterArgsIndex >= 0 && tokens[afterArgsIndex].Type == TokenType.LeftBrace {
                    CollectObjectInitializerMemberDiagnostics(sourceFile, tokens, table, afterArgsIndex)
                }
            }

            return
        }

        if IsTypeTerminatorForDiagnostics(next.Type) {
            ReportExpectedNewTypeName(sourceFile, tokens, table, newIndex, nextIndex)
            return
        }

        initializerOpenIndex := FindNewInitializerOpen(tokens, nextIndex)
        if initializerOpenIndex >= 0 && !IsArrayConstructionBeforeInitializer(tokens, nextIndex, initializerOpenIndex) {
            CollectObjectInitializerMemberDiagnostics(sourceFile, tokens, table, initializerOpenIndex)
        }
    }

    static func ReportExpectedNewTypeName(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        newIndex: int,
        currentIndex: int) {
        newToken := tokens[newIndex]
        current := tokens[currentIndex]
        start := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, newToken.Line, newToken.Column)
        currentStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, current.Line, current.Column)
        ParserDiagnosticTableOps.Report(
            table,
            sourceFile.FileId,
            (int)ErrorCode.ExpectedToken,
            start,
            newToken.Value.Length,
            newToken.Line,
            newToken.Column,
            ParserDiagnosticMessageKind.ExpectedNewTypeName(),
            ParserDiagnosticContextKind.NewExpression(),
            start,
            newToken.Value.Length,
            currentStart,
            current.Value.Length)
    }

    static func CollectObjectInitializerMemberDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        openIndex: int) {
        closeIndex := FindMatchingRightBrace(tokens, openIndex)
        if closeIndex < 0 {
            return
        }

        segmentStart := openIndex + 1
        parenDepth := 0
        bracketDepth := 0
        braceDepth := 0
        genericDepth := 0
        index := openIndex + 1
        while index <= closeIndex {
            token := tokens[index]
            atSegmentEnd := index == closeIndex
                || (token.Type == TokenType.Comma
                    && parenDepth == 0
                    && bracketDepth == 0
                    && braceDepth == 0
                    && genericDepth == 0)

            if atSegmentEnd {
                firstIndex := FirstSignificantTokenIndexInRange(tokens, segmentStart, index)
                if firstIndex >= 0 {
                    AnalyzeObjectInitializerSegment(sourceFile, tokens, table, firstIndex, index)
                }

                segmentStart = index + 1
            } else {
                if token.Type == TokenType.LeftParen {
                    parenDepth = parenDepth + 1
                } else if token.Type == TokenType.RightParen {
                    if parenDepth > 0 {
                        parenDepth = parenDepth - 1
                    }
                } else if token.Type == TokenType.LeftBracket {
                    bracketDepth = bracketDepth + 1
                } else if token.Type == TokenType.RightBracket {
                    if bracketDepth > 0 {
                        bracketDepth = bracketDepth - 1
                    }
                } else if token.Type == TokenType.LeftBrace {
                    braceDepth = braceDepth + 1
                } else if token.Type == TokenType.RightBrace {
                    if braceDepth > 0 {
                        braceDepth = braceDepth - 1
                    }
                } else if token.Type == TokenType.Less {
                    genericDepth = genericDepth + 1
                } else if token.Type == TokenType.Greater {
                    if genericDepth > 0 {
                        genericDepth = genericDepth - 1
                    }
                }
            }

            index = index + 1
        }
    }

    static func AnalyzeObjectInitializerSegment(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        firstIndex: int,
        endIndex: int) {
        first := tokens[firstIndex]
        if first.Type != TokenType.Identifier {
            return
        }

        nextIndex := NextSignificantTokenIndexBefore(tokens, firstIndex, endIndex)
        if nextIndex >= 0 && tokens[nextIndex].Type == TokenType.Colon {
            return
        }

        ReportMissingObjectInitializerColon(sourceFile, tokens, table, firstIndex)
    }

    static func ReportMissingObjectInitializerColon(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        propertyIndex: int) {
        propertyToken := tokens[propertyIndex]
        start := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, propertyToken.Line, propertyToken.Column)
        ParserDiagnosticTableOps.Report(
            table,
            sourceFile.FileId,
            (int)ErrorCode.ExpectedToken,
            start,
            propertyToken.Value.Length,
            propertyToken.Line,
            propertyToken.Column,
            ParserDiagnosticMessageKind.ExpectedObjectInitializerColon(),
            ParserDiagnosticContextKind.ObjectInitializer(),
            start,
            propertyToken.Value.Length,
            -1,
            0)
    }

    static func CollectLeadingMemberAccessDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable) {
        index := 0
        while index < tokens.Count {
            token := tokens[index]
            if IsPanicResetBoundary(token.Type) {
                ParserDiagnosticTableOps.ResetPanicMode(table)
            }

            if (token.Type == TokenType.Dot || token.Type == TokenType.QuestionDot) && IsLeadingMemberAccess(tokens, index) {
                ReportLeadingMemberAccess(sourceFile, tokens, table, index)
            }

            index = index + 1
        }
    }

    static func ReportLeadingMemberAccess(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        operatorIndex: int) {
        operatorToken := tokens[operatorIndex]
        start := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, operatorToken.Line, operatorToken.Column)
        length := operatorToken.Value.Length
        nextIndex := NextSignificantTokenIndex(tokens, operatorIndex)
        if nextIndex >= 0 {
            next := tokens[nextIndex]
            if next.Type == TokenType.Identifier && next.Line == operatorToken.Line {
                nextStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, next.Line, next.Column)
                length = nextStart + next.Value.Length - start
                if length < operatorToken.Value.Length {
                    length = operatorToken.Value.Length
                }
            }
        }

        ParserDiagnosticTableOps.Report(
            table,
            sourceFile.FileId,
            (int)ErrorCode.ExpectedToken,
            start,
            length,
            operatorToken.Line,
            operatorToken.Column,
            ParserDiagnosticMessageKind.ExpectedExpressionBeforeMemberAccess(),
            ParserDiagnosticContextKind.LeadingMemberAccess(),
            start,
            operatorToken.Value.Length,
            -1,
            0)
    }

    static func CollectGenericListDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable) {
        index := 0
        while index < tokens.Count {
            token := tokens[index]
            if IsPanicResetBoundary(token.Type) {
                ParserDiagnosticTableOps.ResetPanicMode(table)
            }

            if token.Type == TokenType.Less {
                greaterIndex := FindMatchingGreater(tokens, index)
                if greaterIndex > index && HasMissingGenericListElement(tokens, index, greaterIndex) {
                    if IsTypeParameterListOpen(tokens, index) {
                        ReportMissingTypeParameterName(sourceFile, tokens, table, index, greaterIndex)
                    } else if IsGenericTypeArgumentListOpen(tokens, index) {
                        ReportMissingGenericTypeArgument(sourceFile, tokens, table, index, greaterIndex)
                    }
                }
            }

            index = index + 1
        }
    }

    static func ReportMissingTypeParameterName(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        lessIndex: int,
        greaterIndex: int) {
        lessToken := tokens[lessIndex]
        greaterToken := tokens[greaterIndex]
        start := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, lessToken.Line, lessToken.Column)
        greaterStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, greaterToken.Line, greaterToken.Column)
        length := greaterStart + greaterToken.Value.Length - start
        if length < 1 {
            length = lessToken.Value.Length
        }

        ParserDiagnosticTableOps.Report(
            table,
            sourceFile.FileId,
            (int)ErrorCode.ExpectedToken,
            start,
            length,
            lessToken.Line,
            lessToken.Column,
            ParserDiagnosticMessageKind.ExpectedTypeParameterName(),
            ParserDiagnosticContextKind.Unknown(),
            start,
            lessToken.Value.Length,
            greaterStart,
            greaterToken.Value.Length)
    }

    static func ReportMissingGenericTypeArgument(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        lessIndex: int,
        greaterIndex: int) {
        typeNameIndex := FindGenericTypeNameStart(tokens, lessIndex)
        if typeNameIndex < 0 {
            return
        }

        typeNameToken := tokens[typeNameIndex]
        greaterToken := tokens[greaterIndex]
        start := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, typeNameToken.Line, typeNameToken.Column)
        greaterStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, greaterToken.Line, greaterToken.Column)
        length := greaterStart + greaterToken.Value.Length - start
        if length < 1 {
            length = typeNameToken.Value.Length
        }

        ParserDiagnosticTableOps.Report(
            table,
            sourceFile.FileId,
            (int)ErrorCode.ExpectedToken,
            start,
            length,
            typeNameToken.Line,
            typeNameToken.Column,
            ParserDiagnosticMessageKind.ExpectedGenericTypeArgument(),
            ParserDiagnosticContextKind.Unknown(),
            start,
            typeNameToken.Value.Length,
            greaterStart,
            greaterToken.Value.Length)
    }

    static func CollectFieldDeclarationDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable) {
        braceDepth := 0
        typeBodyDepth := -1
        pendingTypeBody := false
        index := 0
        while index < tokens.Count {
            token := tokens[index]
            if IsPanicResetBoundary(token.Type) {
                ParserDiagnosticTableOps.ResetPanicMode(table)
            }

            if IsTypeBodyDeclarationKeyword(token.Type) && IsDeclarationKeywordPosition(tokens, index) {
                pendingTypeBody = true
            }

            if typeBodyDepth >= 0
                && braceDepth == typeBodyDepth
                && token.Type == TokenType.Identifier
                && IsLikelyFieldStart(tokens, index) {
                AnalyzeFieldDeclaration(sourceFile, tokens, table, index)
            }

            if token.Type == TokenType.LeftBrace {
                braceDepth = braceDepth + 1
                if pendingTypeBody {
                    typeBodyDepth = braceDepth
                    pendingTypeBody = false
                }
            } else if token.Type == TokenType.RightBrace {
                if braceDepth == typeBodyDepth {
                    typeBodyDepth = -1
                }

                braceDepth = braceDepth - 1
                if braceDepth < 0 {
                    braceDepth = 0
                }
            }

            index = index + 1
        }
    }

    static func AnalyzeFieldDeclaration(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        nameIndex: int) {
        nameToken := tokens[nameIndex]
        nextIndex := NextSignificantTokenIndex(tokens, nameIndex)
        if nextIndex < 0 {
            return
        }

        next := tokens[nextIndex]
        if next.Type == TokenType.ColonAssign {
            return
        }

        nameStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, nameToken.Line, nameToken.Column)
        if next.Type != TokenType.Colon {
            if ParserTokenFacts.IsTypeReferenceStart(next.Type) {
                currentStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, next.Line, next.Column)
                ParserDiagnosticTableOps.Report(
                    table,
                    sourceFile.FileId,
                    (int)ErrorCode.ExpectedToken,
                    nameStart,
                    nameToken.Value.Length,
                    nameToken.Line,
                    nameToken.Column,
                    ParserDiagnosticMessageKind.ExpectedFieldColon(),
                    ParserDiagnosticContextKind.Field(),
                    nameStart,
                    nameToken.Value.Length,
                    currentStart,
                    next.Value.Length)
            }

            return
        }

        currentIndex := nextIndex + 1
        if currentIndex >= tokens.Count {
            currentIndex = nextIndex
        }

        current := tokens[currentIndex]
        if IsTypeTerminatorForDiagnostics(current.Type) || LooksLikeNextFieldAfterMissingType(tokens, currentIndex) {
            currentStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, current.Line, current.Column)
            ParserDiagnosticTableOps.Report(
                table,
                sourceFile.FileId,
                (int)ErrorCode.ExpectedToken,
                nameStart,
                nameToken.Value.Length,
                nameToken.Line,
                nameToken.Column,
                ParserDiagnosticMessageKind.ExpectedFieldType(),
                ParserDiagnosticContextKind.Field(),
                nameStart,
                nameToken.Value.Length,
                currentStart,
                current.Value.Length)
        }
    }

    static func CollectParameterListDiagnostics(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable) {
        index := 0
        while index < tokens.Count {
            token := tokens[index]
            if IsPanicResetBoundary(token.Type) {
                ParserDiagnosticTableOps.ResetPanicMode(table)
            }

            if token.Type == TokenType.LeftParen && IsParameterListOpen(tokens, index) {
                closeIndex := FindMatchingRightParen(tokens, index)
                if closeIndex > index {
                    CollectParameterSegments(sourceFile, tokens, table, index, closeIndex)
                    index = closeIndex
                }
            }

            index = index + 1
        }
    }

    static func CollectParameterSegments(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        openIndex: int,
        closeIndex: int) {
        segmentStart := openIndex + 1
        lastParameterStartIndex := -1
        index := openIndex + 1
        while index <= closeIndex {
            if index == closeIndex || tokens[index].Type == TokenType.Comma {
                firstIndex := FirstSignificantTokenIndexInRange(tokens, segmentStart, index)
                if firstIndex < 0 {
                    previousIndex := PreviousSignificantTokenIndex(tokens, index)
                    if index == closeIndex
                        && previousIndex >= 0
                        && tokens[previousIndex].Type == TokenType.Comma
                        && lastParameterStartIndex >= 0 {
                        ReportTrailingParameterComma(sourceFile, tokens, table, lastParameterStartIndex, previousIndex, closeIndex)
                    }
                } else {
                    parameterStartIndex := AnalyzeParameterSegment(sourceFile, tokens, table, firstIndex, index)
                    if parameterStartIndex >= 0 {
                        lastParameterStartIndex = parameterStartIndex
                    }
                }

                segmentStart = index + 1
            }

            index = index + 1
        }
    }

    static func AnalyzeParameterSegment(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        firstIndex: int,
        endIndex: int): int {
        nameIndex := SkipParameterPrefixes(tokens, firstIndex, endIndex)
        if nameIndex < 0 || nameIndex >= endIndex {
            return firstIndex
        }

        nameToken := tokens[nameIndex]
        if nameToken.Type == TokenType.Colon {
            typeIndex := NextSignificantTokenIndexBefore(tokens, nameIndex, endIndex)
            spanIndex := nameIndex
            if typeIndex >= 0 && ParserTokenFacts.IsTypeReferenceStart(tokens[typeIndex].Type) {
                spanIndex = typeIndex
            }

            spanToken := tokens[spanIndex]
            spanStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, spanToken.Line, spanToken.Column)
            currentStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, nameToken.Line, nameToken.Column)
            ParserDiagnosticTableOps.Report(
                table,
                sourceFile.FileId,
                (int)ErrorCode.ExpectedToken,
                spanStart,
                spanToken.Value.Length,
                spanToken.Line,
                spanToken.Column,
                ParserDiagnosticMessageKind.ExpectedParameterName(),
                ParserDiagnosticContextKind.Parameter(),
                spanStart,
                spanToken.Value.Length,
                currentStart,
                nameToken.Value.Length)
            return -1
        }

        if nameToken.Type != TokenType.Identifier {
            return firstIndex
        }

        nextIndex := NextSignificantTokenIndexBefore(tokens, nameIndex, endIndex)
        nameStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, nameToken.Line, nameToken.Column)
        if nextIndex < 0 || tokens[nextIndex].Type != TokenType.Colon {
            if nextIndex >= 0 {
                current := tokens[nextIndex]
                currentStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, current.Line, current.Column)
                ParserDiagnosticTableOps.Report(
                    table,
                    sourceFile.FileId,
                    (int)ErrorCode.ExpectedToken,
                    nameStart,
                    nameToken.Value.Length,
                    nameToken.Line,
                    nameToken.Column,
                    ParserDiagnosticMessageKind.ExpectedParameterColon(),
                    ParserDiagnosticContextKind.Parameter(),
                    nameStart,
                    nameToken.Value.Length,
                    currentStart,
                    current.Value.Length)
            }

            return nameIndex
        }

        typeIndex := NextSignificantTokenIndexBefore(tokens, nextIndex, endIndex)
        if typeIndex < 0 || IsTypeTerminatorForDiagnostics(tokens[typeIndex].Type) {
            currentIndex := nextIndex
            if typeIndex >= 0 {
                currentIndex = typeIndex
            }

            current := tokens[currentIndex]
            currentStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, current.Line, current.Column)
            ParserDiagnosticTableOps.Report(
                table,
                sourceFile.FileId,
                (int)ErrorCode.ExpectedToken,
                nameStart,
                nameToken.Value.Length,
                nameToken.Line,
                nameToken.Column,
                ParserDiagnosticMessageKind.ExpectedParameterType(),
                ParserDiagnosticContextKind.Parameter(),
                nameStart,
                nameToken.Value.Length,
                currentStart,
                current.Value.Length)
        }

        return nameIndex
    }

    static func ReportTrailingParameterComma(
        sourceFile: ColumnarSourceFile,
        tokens: List<Token>,
        table: ParserDiagnosticTable,
        lastParameterStartIndex: int,
        commaIndex: int,
        closeIndex: int) {
        startToken := tokens[lastParameterStartIndex]
        commaToken := tokens[commaIndex]
        closeToken := tokens[closeIndex]
        start := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, startToken.Line, startToken.Column)
        commaStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, commaToken.Line, commaToken.Column)
        closeStart := OffsetFromLineColumn(sourceFile.LineStarts, sourceFile.Source.Length, closeToken.Line, closeToken.Column)
        length := commaStart + commaToken.Value.Length - start
        if length < 1 {
            length = startToken.Value.Length
        }

        ParserDiagnosticTableOps.Report(
            table,
            sourceFile.FileId,
            (int)ErrorCode.ExpectedToken,
            start,
            length,
            startToken.Line,
            startToken.Column,
            ParserDiagnosticMessageKind.ExpectedParameterName(),
            ParserDiagnosticContextKind.TrailingParameterComma(),
            start,
            length,
            closeStart,
            closeToken.Value.Length)
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

            if (token.Type == TokenType.Dot || token.Type == TokenType.QuestionDot) && !IsLeadingMemberAccess(tokens, index) {
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

    static func IsTypeParameterListOpen(tokens: List<Token>, lessIndex: int): bool {
        previousIndex := PreviousSignificantTokenIndex(tokens, lessIndex)
        if previousIndex < 0 || tokens[previousIndex].Type != TokenType.Identifier {
            return false
        }

        ownerIndex := PreviousSignificantTokenIndex(tokens, previousIndex)
        return IsDeclarationNameOwner(tokens, ownerIndex)
    }

    static func IsGenericTypeArgumentListOpen(tokens: List<Token>, lessIndex: int): bool {
        previousIndex := PreviousSignificantTokenIndex(tokens, lessIndex)
        if previousIndex < 0 || tokens[previousIndex].Type != TokenType.Identifier {
            return false
        }

        typeNameIndex := FindGenericTypeNameStart(tokens, lessIndex)
        if typeNameIndex < 0 {
            return false
        }

        ownerIndex := PreviousSignificantTokenIndex(tokens, typeNameIndex)
        if ownerIndex < 0 {
            return true
        }

        owner := tokens[ownerIndex]
        return owner.Type == TokenType.Colon
            || owner.Type == TokenType.Comma
            || owner.Type == TokenType.Less
            || owner.Type == TokenType.Assign
            || owner.Type == TokenType.New
            || owner.Type == TokenType.BitwiseAnd
            || owner.Type == TokenType.BitwiseOr
            || owner.Type == TokenType.LeftParen
            || owner.Type == TokenType.Arrow
    }

    static func FindNewInitializerOpen(tokens: List<Token>, startIndex: int): int {
        parenDepth := 0
        bracketDepth := 0
        genericDepth := 0
        index := startIndex
        while index < tokens.Count {
            token := tokens[index]
            if parenDepth == 0 && bracketDepth == 0 && genericDepth == 0 {
                if token.Type == TokenType.LeftBrace {
                    return index
                }

                if token.Type == TokenType.Comma
                    || token.Type == TokenType.RightParen
                    || token.Type == TokenType.RightBracket
                    || token.Type == TokenType.Semicolon
                    || token.Type == TokenType.Newline
                    || token.Type == TokenType.Eof {
                    return -1
                }
            }

            if token.Type == TokenType.LeftParen {
                parenDepth = parenDepth + 1
            } else if token.Type == TokenType.RightParen {
                if parenDepth > 0 {
                    parenDepth = parenDepth - 1
                }
            } else if token.Type == TokenType.LeftBracket {
                bracketDepth = bracketDepth + 1
            } else if token.Type == TokenType.RightBracket {
                if bracketDepth > 0 {
                    bracketDepth = bracketDepth - 1
                }
            } else if token.Type == TokenType.Less {
                genericDepth = genericDepth + 1
            } else if token.Type == TokenType.Greater {
                if genericDepth > 0 {
                    genericDepth = genericDepth - 1
                }
            }

            index = index + 1
        }

        return -1
    }

    static func IsArrayConstructionBeforeInitializer(tokens: List<Token>, typeStartIndex: int, initializerOpenIndex: int): bool {
        index := typeStartIndex
        while index < initializerOpenIndex {
            token := tokens[index]
            if token.Type == TokenType.LeftBracket {
                nextIndex := NextSignificantTokenIndexBefore(tokens, index, initializerOpenIndex)
                if nextIndex >= 0 && tokens[nextIndex].Type == TokenType.RightBracket {
                    return true
                }
            }

            index = index + 1
        }

        return false
    }

    static func HasMissingGenericListElement(tokens: List<Token>, lessIndex: int, greaterIndex: int): bool {
        firstIndex := NextSignificantTokenIndexBefore(tokens, lessIndex, greaterIndex + 1)
        if firstIndex == greaterIndex {
            return true
        }

        previousIndex := PreviousSignificantTokenIndex(tokens, greaterIndex)
        return previousIndex > lessIndex && tokens[previousIndex].Type == TokenType.Comma
    }

    static func FindGenericTypeNameStart(tokens: List<Token>, lessIndex: int): int {
        index := PreviousSignificantTokenIndex(tokens, lessIndex)
        if index < 0 || tokens[index].Type != TokenType.Identifier {
            return -1
        }

        startIndex := index
        while true {
            dotIndex := PreviousSignificantTokenIndex(tokens, startIndex)
            if dotIndex < 0 || tokens[dotIndex].Type != TokenType.Dot {
                return startIndex
            }

            beforeDotIndex := PreviousSignificantTokenIndex(tokens, dotIndex)
            if beforeDotIndex < 0 || tokens[beforeDotIndex].Type != TokenType.Identifier {
                return startIndex
            }

            startIndex = beforeDotIndex
        }

        return startIndex
    }

    static func IsTypeBodyDeclarationKeyword(tokenType: TokenType): bool {
        return tokenType == TokenType.Class
            || tokenType == TokenType.Struct
            || tokenType == TokenType.Record
            || tokenType == TokenType.Interface
    }

    static func IsLikelyFieldStart(tokens: List<Token>, tokenIndex: int): bool {
        token := tokens[tokenIndex]
        if token.Value == "constructor"
            || token.Value == "get"
            || token.Value == "set" {
            return false
        }

        previous := PreviousSignificantToken(tokens, tokenIndex)
        if previous == null {
            return false
        }

        if previous.Type == TokenType.LeftBrace
            || previous.Type == TokenType.RightBrace
            || previous.Type == TokenType.Semicolon {
            return true
        }

        if IsDeclarationModifier(previous.Type)
            || previous.Type == TokenType.Required
            || previous.Type == TokenType.Init
            || previous.Type == TokenType.Readonly {
            return true
        }

        return HasLineBreakBefore(tokens, tokenIndex)
    }

    static func LooksLikeNextFieldAfterMissingType(tokens: List<Token>, tokenIndex: int): bool {
        token := tokens[tokenIndex]
        if token.Type != TokenType.Identifier {
            return false
        }

        nextIndex := NextSignificantTokenIndex(tokens, tokenIndex)
        if nextIndex < 0 {
            return false
        }

        next := tokens[nextIndex]
        return next.Type == TokenType.Colon || next.Type == TokenType.ColonAssign
    }

    static func IsParameterListOpen(tokens: List<Token>, openIndex: int): bool {
        previousIndex := PreviousSignificantTokenIndex(tokens, openIndex)
        if previousIndex < 0 {
            return false
        }

        previous := tokens[previousIndex]
        if previous.Type == TokenType.With {
            return true
        }

        if previous.Type == TokenType.Identifier && previous.Value == "constructor" {
            return true
        }

        if previous.Type == TokenType.Identifier {
            ownerIndex := PreviousSignificantTokenIndex(tokens, previousIndex)
            return IsDeclarationNameOwner(tokens, ownerIndex)
        }

        if previous.Type == TokenType.Greater {
            lessIndex := FindMatchingLess(tokens, previousIndex)
            if lessIndex >= 0 {
                nameIndex := PreviousSignificantTokenIndex(tokens, lessIndex)
                if nameIndex >= 0 && tokens[nameIndex].Type == TokenType.Identifier {
                    ownerIndex := PreviousSignificantTokenIndex(tokens, nameIndex)
                    return IsDeclarationNameOwner(tokens, ownerIndex)
                }
            }
        }

        return false
    }

    static func IsDeclarationNameOwner(tokens: List<Token>, ownerIndex: int): bool {
        if ownerIndex < 0 {
            return false
        }

        owner := tokens[ownerIndex]
        if owner.Type == TokenType.Func
            || owner.Type == TokenType.Class
            || owner.Type == TokenType.Struct
            || owner.Type == TokenType.Record
            || owner.Type == TokenType.Interface
            || owner.Type == TokenType.Union {
            return true
        }

        if owner.Type == TokenType.Star {
            beforeStar := PreviousSignificantTokenIndex(tokens, ownerIndex)
            return beforeStar >= 0 && tokens[beforeStar].Type == TokenType.Func
        }

        return false
    }

    static func FindMatchingRightParen(tokens: List<Token>, openIndex: int): int {
        depth := 0
        index := openIndex
        while index < tokens.Count {
            token := tokens[index]
            if token.Type == TokenType.LeftParen {
                depth = depth + 1
            } else if token.Type == TokenType.RightParen {
                depth = depth - 1
                if depth == 0 {
                    return index
                }
            }

            index = index + 1
        }

        return -1
    }

    static func FindMatchingRightBrace(tokens: List<Token>, openIndex: int): int {
        depth := 0
        index := openIndex
        while index < tokens.Count {
            token := tokens[index]
            if token.Type == TokenType.LeftBrace {
                depth = depth + 1
            } else if token.Type == TokenType.RightBrace {
                depth = depth - 1
                if depth == 0 {
                    return index
                }
            }

            index = index + 1
        }

        return -1
    }

    static func FindMatchingGreater(tokens: List<Token>, lessIndex: int): int {
        depth := 0
        index := lessIndex
        while index < tokens.Count {
            token := tokens[index]
            if token.Type == TokenType.Less {
                depth = depth + 1
            } else if token.Type == TokenType.Greater {
                depth = depth - 1
                if depth == 0 {
                    return index
                }
            }

            index = index + 1
        }

        return -1
    }

    static func FindMatchingLess(tokens: List<Token>, greaterIndex: int): int {
        depth := 0
        index := greaterIndex
        while index >= 0 {
            token := tokens[index]
            if token.Type == TokenType.Greater {
                depth = depth + 1
            } else if token.Type == TokenType.Less {
                depth = depth - 1
                if depth == 0 {
                    return index
                }
            }

            index = index - 1
        }

        return -1
    }

    static func SkipParameterPrefixes(tokens: List<Token>, firstIndex: int, endIndex: int): int {
        index := firstIndex
        while index >= 0 && index < endIndex {
            token := tokens[index]
            if token.Type == TokenType.Params
                || token.Type == TokenType.Ref
                || token.Type == TokenType.Out
                || token.Type == TokenType.This {
                index = NextSignificantTokenIndexBefore(tokens, index, endIndex)
            } else {
                return index
            }
        }

        return -1
    }

    static func IsTypeTerminatorForDiagnostics(tokenType: TokenType): bool {
        return tokenType == TokenType.Comma
            || tokenType == TokenType.RightParen
            || tokenType == TokenType.RightBracket
            || tokenType == TokenType.RightBrace
            || tokenType == TokenType.Newline
            || tokenType == TokenType.Eof
            || tokenType == TokenType.Assign
            || tokenType == TokenType.Semicolon
            || tokenType == TokenType.Arrow
            || tokenType == TokenType.Colon
    }

    static func IsLeadingMemberAccess(tokens: List<Token>, tokenIndex: int): bool {
        previous := PreviousSignificantToken(tokens, tokenIndex)
        if previous == null {
            return true
        }

        if HasLineBreakBefore(tokens, tokenIndex) {
            return true
        }

        return !CanEndExpressionBeforeMemberAccess(previous.Type)
    }

    static func CanEndExpressionBeforeMemberAccess(tokenType: TokenType): bool {
        return tokenType == TokenType.Identifier
            || tokenType == TokenType.IntLiteral
            || tokenType == TokenType.FloatLiteral
            || tokenType == TokenType.CharLiteral
            || tokenType == TokenType.StringLiteral
            || tokenType == TokenType.TripleQuoteStringLiteral
            || tokenType == TokenType.InterpolatedRawStringLiteral
            || tokenType == TokenType.This
            || tokenType == TokenType.Base
            || tokenType == TokenType.True
            || tokenType == TokenType.False
            || tokenType == TokenType.Null
            || tokenType == TokenType.RightParen
            || tokenType == TokenType.RightBracket
            || tokenType == TokenType.RightBrace
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

    static func PreviousSignificantTokenIndex(tokens: List<Token>, tokenIndex: int): int {
        index := tokenIndex - 1
        while index >= 0 {
            token := tokens[index]
            if token.Type != TokenType.Newline {
                return index
            }

            index = index - 1
        }

        return -1
    }

    static func HasLineBreakBefore(tokens: List<Token>, tokenIndex: int): bool {
        index := tokenIndex - 1
        while index >= 0 {
            token := tokens[index]
            if token.Type == TokenType.Newline {
                return true
            }

            if token.Type != TokenType.Newline {
                return false
            }

            index = index - 1
        }

        return false
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

    static func NextSignificantTokenIndexBefore(tokens: List<Token>, tokenIndex: int, endIndex: int): int {
        index := tokenIndex + 1
        while index < endIndex && index < tokens.Count {
            token := tokens[index]
            if token.Type != TokenType.Newline {
                return index
            }

            index = index + 1
        }

        return -1
    }

    static func FirstSignificantTokenIndexInRange(tokens: List<Token>, startIndex: int, endIndex: int): int {
        index := startIndex
        while index < endIndex && index < tokens.Count {
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
            || tokenType == TokenType.LeftBrace
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

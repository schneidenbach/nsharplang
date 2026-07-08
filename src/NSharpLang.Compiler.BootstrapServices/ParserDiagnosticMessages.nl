namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

public class ParserDiagnosticMessages {
    public static func Materialize(table: ParserDiagnosticTable, sourceFiles: ColumnarSourceFile[]): List<CompilerError> {
        diagnostics := new List<CompilerError>()
        index := 0
        while index < table.Count {
            sourceFile := ResolveSourceFile(sourceFiles, table.SourceFileIds[index])
            source := sourceFile.Source
            line := table.Lines[index]
            column := table.Columns[index]
            length := table.Lengths[index]
            snippet := CodeIntelligenceTextUtilities.GetSourceLine(source, line)

            if table.MessageKinds[index] == ParserDiagnosticMessageKind.ReservedKeywordAsName() {
                keyword := SliceSource(source, table.ArgAStarts[index], table.ArgALengths[index])
                suggestions := new List<string>()
                suggestions.Add("Rename it to '" + keyword + "Value' or '_" + keyword + "'")
                suggestions.Add("Pick any name that isn't a reserved N# keyword")

                diagnostics.Add(ParserErrorDiagnostics.Create(
                    ErrorCode.ReservedKeywordAsName,
                    ReservedKeywordContextMessage(table.ContextKinds[index]) + ". Got the reserved keyword '" + keyword + "'",
                    sourceFile.FileName,
                    line,
                    column,
                    snippet,
                    length,
                    "'" + keyword + "' is a reserved keyword in N#, so it can't be used as a name here.",
                    ReservedKeywordHint(keyword, table.ContextKinds[index]),
                    suggestions))
            } else if table.MessageKinds[index] == ParserDiagnosticMessageKind.ExpectedMemberNameAfterDot() {
                operatorText := SliceSource(source, table.ArgAStarts[index], table.ArgALengths[index])
                currentText := SliceSource(source, table.ArgBStarts[index], table.ArgBLengths[index])
                operatorDescription := "dot (.)"
                if operatorText != "." {
                    operatorDescription = "null-conditional member access (" + operatorText + ")"
                }

                suggestions := new List<string>()
                suggestions.Add("Check if you forgot to finish this line")
                suggestions.Add("Common members: Length, Count, ToString(), GetHashCode()")
                suggestions.Add("If this is end of statement, remove the trailing '" + operatorText + "'")

                diagnostics.Add(ParserErrorDiagnostics.Create(
                    ErrorCode.ExpectedToken,
                    "Expected member name. Got '" + currentText + "'",
                    sourceFile.FileName,
                    line,
                    column,
                    snippet,
                    length,
                    "I see a " + operatorDescription + " operator but no member name after it.",
                    "After " + operatorDescription + ", I need to see a property or method name.",
                    suggestions))
            } else if table.MessageKinds[index] == ParserDiagnosticMessageKind.ExpectedDeclarationName() {
                currentText := SliceSource(source, table.ArgBStarts[index], table.ArgBLengths[index])
                expectedMessage := DeclarationNameMessage(table.ContextKinds[index])

                diagnostics.Add(ParserErrorDiagnostics.Create(
                    ErrorCode.ExpectedToken,
                    expectedMessage + ". Got '" + currentText + "'",
                    sourceFile.FileName,
                    line,
                    column,
                    snippet,
                    length,
                    "I was expecting an identifier here, but I found '" + currentText + "' instead.",
                    "An identifier is a name for a variable, function, or type.",
                    null))
            } else if table.MessageKinds[index] == ParserDiagnosticMessageKind.ExpectedParameterName() {
                currentText := SliceSource(source, table.ArgBStarts[index], table.ArgBLengths[index])
                if table.ContextKinds[index] == ParserDiagnosticContextKind.TrailingParameterComma() {
                    suggestions := new List<string>()
                    suggestions.Add("Add a parameter after the comma")
                    suggestions.Add("Remove the trailing comma")

                    diagnostics.Add(ParserErrorDiagnostics.Create(
                        ErrorCode.ExpectedToken,
                        "Expected parameter name. Got '" + currentText + "'",
                        sourceFile.FileName,
                        line,
                        column,
                        snippet,
                        length,
                        "Parameter lists need another parameter after a comma.",
                        "Add the missing parameter after the comma, or remove the trailing comma.",
                        suggestions))
                } else {
                    diagnostics.Add(ParserErrorDiagnostics.Create(
                        ErrorCode.ExpectedToken,
                        "Expected parameter name. Got '" + currentText + "'",
                        sourceFile.FileName,
                        line,
                        column,
                        snippet,
                        length,
                        "I was expecting an identifier here, but I found '" + currentText + "' instead.",
                        "An identifier is a name for a variable, function, or type.",
                        null))
                }
            } else if table.MessageKinds[index] == ParserDiagnosticMessageKind.ExpectedParameterType() {
                parameterName := SliceSource(source, table.ArgAStarts[index], table.ArgALengths[index])
                currentText := SliceSource(source, table.ArgBStarts[index], table.ArgBLengths[index])
                suggestions := new List<string>()
                suggestions.Add("Add a parameter type after ':'")

                diagnostics.Add(ParserErrorDiagnostics.Create(
                    ErrorCode.ExpectedToken,
                    "Expected type name. Got '" + currentText + "'",
                    sourceFile.FileName,
                    line,
                    column,
                    snippet,
                    length,
                    "Parameter '" + parameterName + "' needs a type after ':'.",
                    "Write this parameter as `" + parameterName + ": Type`.",
                    suggestions))
            } else if table.MessageKinds[index] == ParserDiagnosticMessageKind.ExpectedParameterColon() {
                parameterName := SliceSource(source, table.ArgAStarts[index], table.ArgALengths[index])
                currentText := SliceSource(source, table.ArgBStarts[index], table.ArgBLengths[index])
                suggestions := new List<string>()
                suggestions.Add("Add ':' after '" + parameterName + "'")

                diagnostics.Add(ParserErrorDiagnostics.Create(
                    ErrorCode.ExpectedToken,
                    "Expected ':' after parameter name. Got '" + currentText + "'",
                    sourceFile.FileName,
                    line,
                    column,
                    snippet,
                    length,
                    "Parameter '" + parameterName + "' needs a ':' before its type.",
                    "Write this parameter as `" + parameterName + ": Type`.",
                    suggestions))
            }

            index = index + 1
        }

        return diagnostics
    }

    static func ResolveSourceFile(sourceFiles: ColumnarSourceFile[], sourceFileId: int): ColumnarSourceFile {
        if sourceFileId >= 0 && sourceFileId < sourceFiles.Length {
            return sourceFiles[sourceFileId]
        }

        return sourceFiles[0]
    }

    static func ReservedKeywordContextMessage(contextKind: int): string {
        if contextKind == ParserDiagnosticContextKind.DotMember() {
            return "Expected member name"
        }

        if contextKind == ParserDiagnosticContextKind.Parameter() {
            return "Expected parameter name"
        }

        if contextKind == ParserDiagnosticContextKind.Field() {
            return "Expected field name"
        }

        return "Expected identifier"
    }

    static func ReservedKeywordHint(keyword: string, contextKind: int): string {
        if contextKind == ParserDiagnosticContextKind.DotMember() {
            return "After a member access, the name must not be a reserved keyword. To reach a  member literally named '" + keyword + "', access it through a differently-named alias."
        }

        return "Choose a name that isn't a reserved keyword (for example '" + keyword + "Value' or '_" + keyword + "')."
    }

    static func DeclarationNameMessage(contextKind: int): string {
        if contextKind == ParserDiagnosticContextKind.FunctionDeclaration() {
            return "Expected function name"
        }

        if contextKind == ParserDiagnosticContextKind.ClassDeclaration() {
            return "Expected class name"
        }

        if contextKind == ParserDiagnosticContextKind.StructDeclaration() {
            return "Expected struct name"
        }

        if contextKind == ParserDiagnosticContextKind.RecordDeclaration() {
            return "Expected record name"
        }

        if contextKind == ParserDiagnosticContextKind.InterfaceDeclaration() {
            return "Expected interface name"
        }

        if contextKind == ParserDiagnosticContextKind.UnionDeclaration() {
            return "Expected union name"
        }

        if contextKind == ParserDiagnosticContextKind.EnumDeclaration() {
            return "Expected enum name"
        }

        if contextKind == ParserDiagnosticContextKind.TypeAliasDeclaration() {
            return "Expected type alias name"
        }

        return "Expected identifier"
    }

    static func SliceSource(source: string, start: int, length: int): string {
        if start < 0 || length <= 0 || start >= source.Length {
            return ""
        }

        safeLength := length
        if start + safeLength > source.Length {
            safeLength = source.Length - start
        }

        return source.Substring(start, safeLength)
    }
}

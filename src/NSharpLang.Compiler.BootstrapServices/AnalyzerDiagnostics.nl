namespace NSharpLang.Compiler

public class AnalyzerDiagnostics {
    public static func Create(
        code: ErrorCode,
        message: string,
        currentFilePath: string?,
        line: int,
        column: int,
        sourceSnippet: string?,
        suggestion: string?,
        length: int,
        severity: ErrorSeverity): CompilerError {
        resolvedSuggestion: string? = suggestion
        if resolvedSuggestion == null {
            resolvedSuggestion = ErrorSuggestions.GetSuggestion(code, null, null)
        }

        if sourceSnippet != null && currentFilePath != null {
            return CompilerError.WithSnippet(
                code,
                message,
                currentFilePath,
                line,
                column,
                sourceSnippet,
                length,
                resolvedSuggestion,
                severity)
        }

        return CompilerError.CreateDetailed(
            code,
            message,
            line,
            column,
            currentFilePath,
            length,
            resolvedSuggestion,
            null,
            null,
            null,
            severity)
    }

    public static func CreateImportCollision(
        message: string,
        currentFilePath: string?,
        duplicateSourcePath: string?,
        line: int,
        column: int,
        sourceSnippet: string?,
        length: int,
        suggestion: string,
        humanExplanation: string,
        contextualHint: string): CompilerError {
        docsUrl := "https://docs.n-sharp.dev/errors/NL702"
        fileName: string? = currentFilePath
        if fileName == null {
            fileName = duplicateSourcePath
        }

        if sourceSnippet != null && currentFilePath != null {
            return CompilerError.WithSnippetDetailed(
                ErrorCode.ImportCollision,
                message,
                currentFilePath,
                line,
                column,
                sourceSnippet,
                length,
                suggestion,
                ErrorSeverity.Error,
                humanExplanation,
                contextualHint,
                docsUrl)
        }

        return CompilerError.CreateDetailed(
            ErrorCode.ImportCollision,
            message,
            line,
            column,
            fileName,
            length,
            suggestion,
            humanExplanation,
            contextualHint,
            docsUrl,
            ErrorSeverity.Error)
    }
}

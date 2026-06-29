namespace NSharpLang.Compiler

import System

public class StrictLintDiagnostics {
    public static func FromLintDiagnostic(
        fileName: string,
        code: string,
        message: string,
        line: int,
        column: int,
        length: int,
        suggestion: string?,
        sourceSnippet: string?): CompilerError {
        return new CompilerError(
            ErrorCode.InvalidSyntax,
            message,
            line,
            column,
            ErrorSeverity.Error) {
            FileName: fileName,
            Length: Math.Max(length, 1),
            Suggestion: suggestion,
            SourceSnippet: TrimSnippetEnd(sourceSnippet),
            DiagnosticIdOverride: code,
            DocsUrl: DiagnosticCatalog.DocsUrlFor(code)
        }
    }

    static func TrimSnippetEnd(sourceSnippet: string?): string? {
        if sourceSnippet == null {
            return null
        }

        return sourceSnippet.TrimEnd()
    }
}

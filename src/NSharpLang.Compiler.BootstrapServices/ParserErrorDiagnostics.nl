namespace NSharpLang.Compiler

import System.Collections.Generic

public class ParserErrorDiagnostics {
    public static func Create(
        code: ErrorCode,
        message: string,
        fileName: string?,
        line: int,
        column: int,
        sourceSnippet: string?,
        length: int,
        humanExplanation: string?,
        hint: string?,
        suggestions: List<string>?): CompilerError {
        primarySuggestion: string? = null
        if suggestions != null {
            if suggestions.Count > 0 {
                primarySuggestion = suggestions[0]
            }
        }

        error := CompilerError.WithSnippetDetailed(
            code,
            message,
            fileName ?? "unknown",
            line,
            column,
            sourceSnippet ?? "",
            length,
            primarySuggestion,
            ErrorSeverity.Error,
            humanExplanation,
            hint,
            BuildDocsUrl(code))

        if suggestions != null {
            error.Suggestions = suggestions
        }

        return error
    }

    static func BuildDocsUrl(code: ErrorCode): string {
        codeValue: int = (int)code
        return "https://docs.n-sharp.dev/errors/NL" + codeValue.ToString("D3")
    }
}

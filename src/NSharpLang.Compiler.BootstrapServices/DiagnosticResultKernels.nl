namespace NSharpLang.Compiler.CodeIntelligence

public class DiagnosticResultKernels {
    public static func WithColumn(result: DiagnosticResult, column: int): DiagnosticResult {
        return new DiagnosticResult(
            result.Code,
            result.Severity,
            result.Message,
            result.File,
            result.Line,
            column,
            result.Length,
            result.SourceSnippet,
            result.Explanation,
            result.Suggestion,
            result.Hint,
            result.ExpectedType,
            result.ActualType,
            result.DocsUrl)
    }

    public static func WithCodeColumnMessage(result: DiagnosticResult, code: string, column: int, message: string): DiagnosticResult {
        return new DiagnosticResult(
            code,
            result.Severity,
            message,
            result.File,
            result.Line,
            column,
            result.Length,
            result.SourceSnippet,
            result.Explanation,
            result.Suggestion,
            result.Hint,
            result.ExpectedType,
            result.ActualType,
            result.DocsUrl)
    }
}

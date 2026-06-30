namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text

public class OutputFormatterDiagnosticKernels {
    public static func SummarizeDiagnosticSeverities(diagnostics: IReadOnlyList<DiagnosticResult>): DiagnosticSummary {
        errors := 0
        warnings := 0
        info := 0

        foreach diagnosticValue in diagnostics {
            diagnostic := (DiagnosticResult)diagnosticValue
            severity := diagnostic.Severity
            if severity == "error" {
                errors = errors + 1
            } else if severity == "warning" {
                warnings = warnings + 1
            } else if severity == "info" {
                info = info + 1
            }
        }

        return new DiagnosticSummary(errors, warnings, info)
    }

    public static func FilterDiagnosticSeverities(
        diagnostics: IReadOnlyList<DiagnosticResult>,
        targetSeverity: string): ValueTuple<int[], int> {
        resultIndices := new List<int>()
        index := 0

        foreach diagnosticValue in diagnostics {
            diagnostic := (DiagnosticResult)diagnosticValue
            severity := diagnostic.Severity
            if String.Equals(severity, targetSeverity, StringComparison.OrdinalIgnoreCase) {
                resultIndices.Add(index)
            }

            index = index + 1
        }

        values := resultIndices.ToArray()
        return new ValueTuple<int[], int>(values, values.Length)
    }

    public static func FilterDiagnosticSeverityResults(
        diagnostics: IReadOnlyList<DiagnosticResult>,
        targetSeverity: string): List<DiagnosticResult> {
        result := new List<DiagnosticResult>()

        foreach diagnosticValue in diagnostics {
            diagnostic := (DiagnosticResult)diagnosticValue
            severity := diagnostic.Severity
            if String.Equals(severity, targetSeverity, StringComparison.OrdinalIgnoreCase) {
                result.Add(diagnostic)
            }
        }

        return result
    }

    public static func GetDiagnosticTitle(code: string, severity: string): string {
        label := DiagnosticSeverityLabel(severity)
        if label == "" {
            return ""
        }

        return "[" + code + "] " + label
    }

    public static func GetExpectedTypeText(expectedType: string): string {
        return GetDiagnosticDetailText(1, expectedType)
    }

    public static func GetActualTypeText(actualType: string): string {
        return GetDiagnosticDetailText(2, actualType)
    }

    public static func GetHintText(hint: string): string {
        return GetDiagnosticDetailText(3, hint)
    }

    public static func GetSuggestionText(suggestion: string): string {
        return GetDiagnosticDetailText(4, suggestion)
    }

    public static func GetDocsUrlText(docsUrl: string): string {
        return GetDiagnosticDetailText(5, docsUrl)
    }

    public static func GetNoDiagnosticsText(): string {
        return "No diagnostics found."
    }

    public static func GetFoundSummaryText(summary: DiagnosticSummary): string {
        return DiagnosticFoundSummaryText(summary.Errors, summary.Warnings, summary.Info)
    }

    public static func GetSourceLineText(line: int, sourceSnippet: string): string {
        return "    " + line.ToString() + " | " + sourceSnippet
    }

    public static func GetHeaderLineText(title: string, fileName: string, line: int, column: int): string {
        location := fileName + ":" + line.ToString() + ":" + column.ToString()
        headerContent := " " + title + " "
        locationPart := " " + location + " "
        remainingWidth := 60 - headerContent.Length - locationPart.Length
        if remainingWidth < 0 {
            remainingWidth = 0
        }

        rulerWidth := remainingWidth
        if rulerWidth < 2 {
            rulerWidth = 2
        }

        return DiagnosticRepeatText("─", 2) + headerContent + DiagnosticRepeatText("─", rulerWidth) +
            locationPart + DiagnosticRepeatText("─", 2)
    }

    public static func GetCaretLineText(line: int, column: int, length: int): string {
        lineDigits := line.ToString().Length
        caretOffset := column - 1
        if caretOffset < 0 {
            caretOffset = 0
        }

        caretLength := length
        if caretLength < 1 {
            caretLength = 1
        }

        return "    " + DiagnosticRepeatChar(' ', lineDigits) + " | " +
            DiagnosticRepeatChar(' ', caretOffset) + DiagnosticRepeatChar('^', caretLength)
    }

    static func GetDiagnosticDetailText(kind: int, value: string): string {
        if kind == 1 {
            return "Expected: `" + value + "`"
        }

        if kind == 2 {
            return "  Actual: `" + value + "`"
        }

        if kind == 3 {
            return "Hint: " + value
        }

        if kind == 4 {
            return "Suggestion: " + value
        }

        if kind == 5 {
            return "See: " + value
        }

        return ""
    }

    static func DiagnosticSeverityLabel(severity: string): string {
        if severity == "error" {
            return "ERROR"
        }

        if severity == "warning" {
            return "WARNING"
        }

        if severity == "info" {
            return "INFO"
        }

        return DiagnosticUpperInvariant(severity)
    }

    static func DiagnosticUpperInvariant(value: string): string {
        if value.Length == 0 {
            return ""
        }

        return value.ToUpperInvariant()
    }

    static func DiagnosticFoundSummaryText(errors: int, warnings: int, info: int): string {
        summary := ""
        if errors > 0 {
            summary = DiagnosticAppendSummaryCount(summary, errors, "error", "errors")
        }

        if warnings > 0 {
            summary = DiagnosticAppendSummaryCount(summary, warnings, "warning", "warnings")
        }

        if info > 0 {
            summary = DiagnosticAppendSummaryCount(summary, info, "info", "info")
        }

        if summary == "" {
            return ""
        }

        return "Found " + summary + "."
    }

    static func DiagnosticAppendSummaryCount(current: string, count: int, singular: string, plural: string): string {
        label := singular
        if count != 1 {
            label = plural
        }

        part := count.ToString() + " " + label
        if current == "" {
            return part
        }

        return current + ", " + part
    }

    static func DiagnosticRepeatChar(ch: char, count: int): string {
        if count <= 0 {
            return ""
        }

        builder := new StringBuilder(count)
        i := 0
        while i < count {
            builder.Append(ch)
            i = i + 1
        }

        return builder.ToString()
    }

    static func DiagnosticRepeatText(text: string, count: int): string {
        if count <= 0 {
            return ""
        }

        if text == "" {
            return ""
        }

        builder := new StringBuilder(text.Length * count)
        i := 0
        while i < count {
            builder.Append(text)
            i = i + 1
        }

        return builder.ToString()
    }
}

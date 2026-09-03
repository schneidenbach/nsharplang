namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text

record CompilerError(code: ErrorCode, message: string, line: int, column: int, severity: ErrorSeverity) {
    Code: ErrorCode = code
    Message: string = message
    FileName: string?
    Line: int = line
    Column: int = column
    Length: int = 1
    Suggestion: string?
    SourceSnippet: string?
    Severity: ErrorSeverity = severity

    ActualType: string?
    ExpectedType: string?
    HumanExplanation: string?
    ContextualHint: string?
    DocsUrl: string?
    Suggestions: List<string>?
    RelatedInfo: Dictionary<string, string>?
    DiagnosticIdOverride: string?

    DiagnosticId: string => DiagnosticIdOverride ?? BuildDefaultDiagnosticId()

    // MSBuild's diagnostic span is INCLUSIVE at both ends, so a one-character diagnostic reports the
    // same column twice and an N-character one reports N-1 past its start. This is what decides how
    // wide the squiggle is in the IDE error list and what `(line,col-col)` reads in build output; it
    // is the MSBuild counterpart of `Length`, and it never runs backwards past `Column`.
    MsBuildEndColumn: int => Column + Math.Max(0, Length - 1)

    func BuildDefaultDiagnosticId(): string {
        codeValue: int = (int)Code
        return "NL" + codeValue.ToString("D3")
    }

    func FormatForTooling(includeCode: bool = true, includeLocation: bool = false): string {
        builder := new StringBuilder()
        if includeCode {
            builder.Append(DiagnosticId)
            builder.Append(": ")
            builder.Append(Message)
        } else {
            builder.Append(Message)
        }

        if includeLocation {
            builder.AppendLine()
            builder.Append("at ")
            if FileName != null {
                builder.Append(FileName)
                builder.Append(":")
                builder.Append(Line)
                builder.Append(":")
                builder.Append(Column)
            } else {
                builder.Append("line ")
                builder.Append(Line)
                builder.Append(", column ")
                builder.Append(Column)
            }
        }

        if HasText(HumanExplanation) {
            builder.AppendLine()
            builder.AppendLine()
            builder.Append((HumanExplanation ?? "").Trim())
        }

        if HasText(SourceSnippet) {
            builder.AppendLine()
            builder.AppendLine()
            builder.AppendLine(SourceSnippet ?? "")
            markerIndent := ""
            if Column > 0 {
                markerIndent = new string(' ', Column - 1)
            }

            builder.Append(markerIndent)
            builder.Append(new string('^', Math.Max(1, Length)))
        }

        if HasText(ActualType) || HasText(ExpectedType) {
            builder.AppendLine()
            builder.AppendLine()
            if HasText(ActualType) {
                builder.Append("actual: ")
                builder.AppendLine(ActualType ?? "")
            }

            if HasText(ExpectedType) {
                builder.Append("expected: ")
                builder.Append(ExpectedType ?? "")
            }
        }

        if HasText(ContextualHint) {
            builder.AppendLine()
            builder.AppendLine()
            builder.Append((ContextualHint ?? "").Trim())
        }

        renderedSuggestions := false
        suggestions := Suggestions
        if suggestions != null {
            if suggestions.Count > 0 {
                renderedSuggestions = true
                builder.AppendLine()
                builder.AppendLine()
                builder.AppendLine("did you mean:")
                for suggestion in suggestions {
                    builder.Append("- ")
                    builder.AppendLine(suggestion)
                }
            }
        }

        if !renderedSuggestions && HasText(Suggestion) {
            builder.AppendLine()
            builder.AppendLine()
            builder.Append("help: ")
            builder.Append((Suggestion ?? "").Trim())
        }

        if HasText(DocsUrl) {
            builder.AppendLine()
            builder.AppendLine()
            builder.Append("docs: ")
            builder.Append(DocsUrl ?? "")
        }

        return builder.ToString().TrimEnd()
    }

    func FormatForMsBuild(): string {
        parts := new List<string>()
        parts.Add(Message)

        if HasText(HumanExplanation) {
            parts.Add(NormalizeInlineText(HumanExplanation ?? ""))
        }

        if HasText(ActualType) {
            parts.Add("actual: " + (ActualType ?? ""))
        }

        if HasText(ExpectedType) {
            parts.Add("expected: " + (ExpectedType ?? ""))
        }

        if HasText(ContextualHint) {
            parts.Add(NormalizeInlineText(ContextualHint ?? ""))
        }

        renderedSuggestions := false
        suggestions := Suggestions
        if suggestions != null {
            if suggestions.Count > 0 {
                renderedSuggestions = true
                parts.Add("did you mean: " + string.Join(", ", suggestions))
            }
        }

        if !renderedSuggestions && HasText(Suggestion) {
            parts.Add("help: " + NormalizeInlineText(Suggestion ?? ""))
        }

        if HasText(DocsUrl) {
            parts.Add("docs: " + (DocsUrl ?? ""))
        }

        return string.Join(" | ", parts)
    }

    static func NormalizeInlineText(value: string): string {
        builder := new StringBuilder()
        pendingSpace := false
        index := 0
        while index < value.Length {
            ch := value[index]
            if ch == '\r' || ch == '\n' {
                pendingSpace = true
            } else {
                if pendingSpace && builder.Length > 0 && !char.IsWhiteSpace(ch) {
                    builder.Append(' ')
                }

                builder.Append(ch)
                pendingSpace = false
            }

            index = index + 1
        }

        return builder.ToString().Trim()
    }

    static func HasText(value: string?): bool {
        return !string.IsNullOrWhiteSpace(value ?? "")
    }

    func Format(useColors: bool = true): string {
        if HumanExplanation != null {
            return FormatElmStyle(useColors)
        }

        return FormatRustStyle(useColors)
    }

    func FormatElmStyle(useColors: bool): string {
        builder := new StringBuilder()
        severityText := GetElmSeverityText()

        cyan := Csi("1;36m")
        reset := Csi("0m")
        dim := Csi("2m")

        headerLine := new string('-', 50)
        displayFileName := FileName ?? "code"
        if useColors {
            builder.AppendLine($"{dim}-- {severityText} {headerLine}{reset}  {displayFileName}")
        } else {
            builder.AppendLine($"-- {severityText} {headerLine}  {displayFileName}")
        }

        builder.AppendLine()
        builder.AppendLine(HumanExplanation ?? "")
        builder.AppendLine()

        if SourceSnippet != null {
            if useColors {
                builder.AppendLine($"{cyan}{Line}|{reset}     {SourceSnippet}")
            } else {
                builder.AppendLine($"{Line}|     {SourceSnippet}")
            }

            markerIndent := "      "
            if Column > 0 {
                markerIndent = new string(' ', Column - 1 + 6)
            }

            marker := new string('^', Math.Max(1, Length))
            if useColors {
                builder.AppendLine($"{cyan}{markerIndent}{marker}{reset}")
            } else {
                builder.AppendLine($"{markerIndent}{marker}")
            }

            builder.AppendLine()
        }

        if ActualType != null && ExpectedType != null {
            builder.AppendLine("This expression has type:")
            builder.AppendLine()
            builder.AppendLine($"    {ActualType}")
            builder.AppendLine()
            builder.AppendLine("But you said it should be:")
            builder.AppendLine()
            builder.AppendLine($"    {ExpectedType}")
            builder.AppendLine()
        }

        if ContextualHint != null {
            builder.AppendLine($"Hint: {ContextualHint}")
            builder.AppendLine()
        }

        renderedSuggestions := false
        suggestions := Suggestions
        if suggestions != null {
            if suggestions.Count > 0 {
                renderedSuggestions = true
                builder.AppendLine("Did you mean one of these?")
                builder.AppendLine()
                for suggestion in suggestions {
                    builder.AppendLine($"    {suggestion}")
                }

                builder.AppendLine()
            }
        }

        if DocsUrl != null {
            if useColors {
                builder.AppendLine($"{cyan}Read more:{reset} {DocsUrl}")
            } else {
                builder.AppendLine($"Read more: {DocsUrl}")
            }
        }

        return builder.ToString()
    }

    // ESC is built from its CODE POINT, not from a `\x1b` literal, and that is deliberate: this file is
    // compiled by whichever N# compiler the SDK package holds, so a literal here would decode with the
    // escape table of THAT compiler rather than this tree's. The colour of the compiler's own diagnostics
    // must not depend on which compiler compiled the compiler. `\x1b` is a real escape in N# now (see
    // `StringLiteralDecoder`) — user code should spell it that way; a bootstrap kernel should not.
    static func Csi(finalBytes: string): string {
        return ((char)27).ToString() + "[" + finalBytes
    }

    func GetElmSeverityText(): string {
        if Severity == ErrorSeverity.Warning {
            return "WARNING"
        }

        if Code == ErrorCode.TypeMismatch || Code == ErrorCode.TypeNotFound {
            return "TYPE MISMATCH"
        }

        if Code == ErrorCode.UndefinedVariable || Code == ErrorCode.UndefinedType || Code == ErrorCode.UndefinedMember {
            return "NAMING ERROR"
        }

        if Code == ErrorCode.NonExhaustiveMatch {
            return "INCOMPLETE PATTERN MATCH"
        }

        if Code == ErrorCode.WrongArgumentCount || Code == ErrorCode.NoMatchingOverload || Code == ErrorCode.UndefinedFunction {
            return "FUNCTION CALL ERROR"
        }

        if Code == ErrorCode.CircularImport {
            return "CIRCULAR IMPORT"
        }

        return "ERROR"
    }

    func FormatRustStyle(useColors: bool): string {
        builder := new StringBuilder()
        severityText := "error"
        if Severity == ErrorSeverity.Warning {
            severityText = "warning"
        }

        red := Csi("1;31m")
        yellow := Csi("1;33m")
        cyan := Csi("1;36m")
        green := Csi("1;32m")
        bold := Csi("1m")
        reset := Csi("0m")

        severityColor := red
        if Severity == ErrorSeverity.Warning {
            severityColor = yellow
        }

        if useColors {
            builder.AppendLine($"{severityColor}{severityText}{reset} {bold}{DiagnosticId}{reset}: {Message}")
        } else {
            builder.AppendLine($"{severityText} {DiagnosticId}: {Message}")
        }

        if FileName != null {
            if useColors {
                builder.AppendLine($"  {cyan}-->{reset} {FileName}:{Line}:{Column}")
            } else {
                builder.AppendLine($"  --> {FileName}:{Line}:{Column}")
            }
        } else {
            if useColors {
                builder.AppendLine($"  {cyan}-->{reset} line {Line}, column {Column}")
            } else {
                builder.AppendLine($"  --> line {Line}, column {Column}")
            }
        }

        if SourceSnippet != null {
            if useColors {
                builder.AppendLine($"   {cyan}|{reset}")
                builder.Append(cyan)
                builder.Append(Line.ToString().PadLeft(3))
                builder.Append(" |")
                builder.Append(reset)
                builder.Append(" ")
                builder.AppendLine(SourceSnippet)
            } else {
                builder.AppendLine("   |")
                builder.Append(Line.ToString().PadLeft(3))
                builder.Append(" | ")
                builder.AppendLine(SourceSnippet)
            }

            markerIndent := ""
            if Column > 0 {
                markerIndent = new string(' ', Column - 1)
            }

            marker := new string('^', Math.Max(1, Length))
            if useColors {
                builder.AppendLine($"   {cyan}|{reset} {markerIndent}{severityColor}{marker}{reset}")
            } else {
                builder.AppendLine($"   | {markerIndent}{marker}")
            }
        }

        if Suggestion != null {
            if useColors {
                builder.AppendLine($"   {cyan}|{reset}")
                builder.AppendLine($"{green}help{reset}: {Suggestion}")
            } else {
                builder.AppendLine("   |")
                builder.AppendLine($"help: {Suggestion}")
            }
        }

        return builder.ToString()
    }

    static func Create(code: ErrorCode, message: string, line: int, column: int, severity: ErrorSeverity = ErrorSeverity.Error): CompilerError {
        return new CompilerError(code, message, line, column, severity)
    }

    static func CreateDetailed(code: ErrorCode, message: string, line: int, column: int, fileName: string?, length: int, suggestion: string?, humanExplanation: string?, contextualHint: string?, docsUrl: string?, severity: ErrorSeverity = ErrorSeverity.Error): CompilerError {
        return new CompilerError(code, message, line, column, severity) {
            FileName: fileName,
            Length: Math.Max(1, length),
            Suggestion: suggestion,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: docsUrl
        }
    }

    static func WithSnippet(code: ErrorCode, message: string, fileName: string, line: int, column: int, sourceSnippet: string, length: int = 0, suggestion: string? = null, severity: ErrorSeverity = ErrorSeverity.Error): CompilerError {
        span := DiagnosticSpanResolver.Resolve(sourceSnippet, column, length)
        return new CompilerError(code, message, line, span.Column, severity) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: span.Length,
            Suggestion: suggestion
        }
    }

    static func WithSnippetDetailed(code: ErrorCode, message: string, fileName: string, line: int, column: int, sourceSnippet: string, length: int = 0, suggestion: string? = null, severity: ErrorSeverity = ErrorSeverity.Error, humanExplanation: string? = null, contextualHint: string? = null, docsUrl: string? = null): CompilerError {
        span := DiagnosticSpanResolver.Resolve(sourceSnippet, column, length)
        return new CompilerError(code, message, line, span.Column, severity) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: span.Length,
            Suggestion: suggestion,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: docsUrl
        }
    }
}

namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


class AnalyzerRefKindWarningReporter {
    static func ReportIfNeeded(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, parameterModifier: Ast.ParameterModifier, argument: Argument, argumentIndex: int, requiresLocation: bool = false): bool {
        if diagnostics == null || spans == null || argument == null || RefKindCompatibilityFacts.Classify(parameterModifier, argument.Modifier, requiresLocation) != RefKindCompatibilityResult.RefEquivalentToIn {
            return false
        }

        span := spans.GetRefArgumentModifierDiagnosticSpan(argument)
        message := "The 'ref' modifier for argument " + (argumentIndex + 1).ToString() + " corresponding to 'in' parameter is equivalent to 'in'. Consider using 'in' instead."
        suggestion := "Write 'in' instead to show that the callee receives a read-only reference."
        diagnostics.Warn(ErrorCode.RefArgumentForInWarning, message, span.Line, span.Column, suggestion, span.Length)
        return true
    }
}

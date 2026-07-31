namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// The analyzer's diagnostic sink: the single authority for turning a semantic finding into a
// `CompilerError` and appending it to the analysis's error list.
//
// The list is handed in by ARGUMENT rather than owned, exactly as `BindingMap` and `SemanticModel`
// are. That matters for ORDER: `_errors` is one list whose order IS the reported order, and every
// producer — the semantic walks that have moved to N# and the shell members that have not yet —
// appends to the same instance, so a report's position among its neighbours is unchanged by which
// side of the boundary produced it.
//
// The snippet is resolved the same way for every diagnostic: the analysed file's own source text
// when the caller supplied one, and otherwise the project snapshot's copy of the current file (the
// unsaved-editor-buffer path). A diagnostic with no text and a diagnostic at line 0 both carry no
// snippet, which is what makes `AnalyzerDiagnostics.Create` fall back to the detail-only shape.
public class AnalyzerDiagnosticSink {
    errorsValue: List<CompilerError>
    projectSourcesValue: AnalyzerProjectSourceProvider
    currentFilePathValue: string?
    sourceTextValue: string?

    CurrentFilePath: string? => currentFilePathValue

    constructor(errors: List<CompilerError>, projectSources: AnalyzerProjectSourceProvider) {
        errorsValue = errors
        projectSourcesValue = projectSources
        currentFilePathValue = null
        sourceTextValue = null
    }

    // One call per analysis, from the same reset block that sets the analyzer's current file.
    public func BeginAnalysis(filePath: string?, sourceText: string?) {
        currentFilePathValue = filePath
        sourceTextValue = sourceText
    }

    public func SourceSnippet(line: int): string? {
        resolved := ""
        if sourceTextValue != null {
            resolved = sourceTextValue
        } else {
            fromProject := projectSourcesValue.TryGetProjectSourceText(currentFilePathValue)
            if fromProject != null {
                resolved = fromProject
            }
        }

        if resolved.Length == 0 || line <= 0 {
            return null
        }

        return CodeIntelligenceTextUtilities.GetSourceLine(resolved, line)
    }

    public func Report(
        code: ErrorCode,
        message: string,
        line: int,
        column: int,
        suggestion: string?,
        length: int) {
        errorsValue.Add(AnalyzerDiagnostics.Create(
            code,
            message,
            currentFilePathValue,
            line,
            column,
            SourceSnippet(line),
            suggestion,
            length,
            ErrorSeverity.Error))
    }

    public func Warn(
        code: ErrorCode,
        message: string,
        line: int,
        column: int,
        suggestion: string?,
        length: int) {
        errorsValue.Add(AnalyzerDiagnostics.Create(
            code,
            message,
            currentFilePathValue,
            line,
            column,
            SourceSnippet(line),
            suggestion,
            length,
            ErrorSeverity.Warning))
    }

    // NL308. The declaring namespace is read from DISK through the project source provider (the
    // file's own `namespace` header), so a file the current snapshot has never seen still names its
    // namespace correctly; a file that declares none reports the global namespace as `<global>`.
    public func ReportInaccessibleMember(
        memberName: string,
        declarationFile: string?,
        line: int,
        column: int): bool {
        declaringNamespace := projectSourcesValue.GetNamespaceForFile(declarationFile)
        if declaringNamespace == null {
            declaringNamespace = "<global>"
        }

        Report(
            ErrorCode.InaccessibleMember,
            "'" + memberName + "' is not exported from package/namespace '" + declaringNamespace
                + "' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package",
            line,
            column,
            null,
            Math.Max(1, memberName.Length))
        return true
    }
}

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
class AnalyzerDiagnosticSink {
    errorsValue: List<CompilerError>
    projectSourcesValue: AnalyzerProjectSourceProvider
    currentFilePathValue: string?
    sourceTextValue: string?

    CurrentFilePath: string? => currentFilePathValue

    // HOW MANY DIAGNOSTICS HAVE BEEN REPORTED SO FAR. The statement-level expression family compares
    // this against the count it captured before an expression walk ran, so that anything the walk
    // itself reported silences the statement's own later reports — a bare call that failed to
    // resolve must not ALSO be told it "has no effect". The sink owns the list, so the count is its
    // own answer rather than something a driver has to carry across the boundary.
    ErrorCount: int => errorsValue.Count

    constructor(errors: List<CompilerError>, projectSources: AnalyzerProjectSourceProvider) {
        errorsValue = errors
        projectSourcesValue = projectSources
        currentFilePathValue = null
        sourceTextValue = null
    }

    // One call per analysis, from the same reset block that sets the analyzer's current file.
    func BeginAnalysis(filePath: string?, sourceText: string?) {
        currentFilePathValue = filePath
        sourceTextValue = sourceText
    }

    // THE ANALYSED FILE'S TEXT, resolved once and the same way for every reader: the caller's own
    // text when it supplied one, otherwise the project snapshot's copy of the current file (the
    // unsaved-editor-buffer path). `AnalyzerDiagnosticSpans` reads it through this door so that a
    // diagnostic's SPAN and its rendered SNIPPET are computed against the same snapshot — two
    // resolutions could drift and underline the wrong characters.
    func ResolvedSourceText(): string? {
        if sourceTextValue != null {
            return sourceTextValue
        }

        return projectSourcesValue.TryGetProjectSourceText(currentFilePathValue)
    }

    func SourceSnippet(line: int): string? {
        resolved := ""
        fromProject := ResolvedSourceText()
        if fromProject != null {
            resolved = fromProject
        }

        if resolved.Length == 0 || line <= 0 {
            return null
        }

        return CodeIntelligenceTextUtilities.GetSourceLine(resolved, line)
    }

    func Report(code: ErrorCode, message: string, line: int, column: int, suggestion: string?, length: int) {
        errorsValue.Add(AnalyzerDiagnostics.Create(code, message, currentFilePathValue, line, column, SourceSnippet(line), suggestion, length, ErrorSeverity.Error))
    }

    // A diagnostic the RICH builders already constructed, appended to the SAME list `Report` writes
    // to. The two shapes differ only in how much explanation they carry — a report that has a
    // snippet and a docs link is still one report, in one position, among its neighbours — so they
    // must not reach the list by different doors.
    func ReportBuilt(error: CompilerError) {
        errorsValue.Add(error)
    }

    // EVERY DIAGNOSTIC REPORTED SINCE A REMEMBERED COUNT, WITHDRAWN.
    //
    // This is the SPECULATIVE reporter's door and it exists for exactly one caller: overload
    // resolution over a reflected method GROUP finalises candidates in preference order, and a
    // candidate that fails may have reported before it failed. Those reports belong to a candidate
    // the user never named, so they are withdrawn before the next candidate is tried — and the ones
    // that survive are the LAST candidate's, which is why the candidate ORDER is user-visible.
    //
    // It is deliberately a ROLLBACK TO A MARK rather than a remove-by-identity: a report is
    // identified by its POSITION in the one ordered list, exactly as `ErrorCount` identifies the
    // mark, and nothing else in the analyzer may un-report anything.
    // It removes from the END rather than by range, and that is a language wall routed around rather
    // than a preference: `List<T>.RemoveRange` is not in the columnar backend's catalog, and
    // `RemoveAt` is. Removing the last element repeatedly is the same list, one allocation-free step
    // at a time, and it cannot shift an element it is not about to drop.
    func RollbackErrorsTo(count: int) {
        if count < 0 {
            return
        }

        while errorsValue.Count > count {
            errorsValue.RemoveAt(errorsValue.Count - 1)
        }
    }

    // HAS THIS EXACT REPORT ALREADY BEEN MADE? Identity is code + line + column + message, and
    // deliberately NOT severity: the one caller — the expression-tree validator — asks so that a
    // lambda reached twice (once through the dispatch arm and once through a target-typed door)
    // says its one sentence once, and a warning that happened to carry the same code, position and
    // words would be the same sentence to the reader.
    //
    // It is a door on the sink rather than a list the caller reads, because the list is the sink's:
    // nothing outside may scan the reported diagnostics, exactly as nothing outside may un-report
    // one. The scan is linear over an already-short list and runs only when a report is about to be
    // made — never on the silent path.
    func HasReported(code: ErrorCode, message: string, line: int, column: int): bool {
        index := 0
        while index < errorsValue.Count {
            reported := errorsValue[index]
            if reported.Code == code && reported.Line == line && reported.Column == column && reported.Message == message {
                return true
            }

            index = index + 1
        }

        return false
    }

    func Warn(code: ErrorCode, message: string, line: int, column: int, suggestion: string?, length: int) {
        errorsValue.Add(AnalyzerDiagnostics.Create(code, message, currentFilePathValue, line, column, SourceSnippet(line), suggestion, length, ErrorSeverity.Warning))
    }

    // NL308. The declaring namespace is read from DISK through the project source provider (the
    // file's own `namespace` header), so a file the current snapshot has never seen still names its
    // namespace correctly; a file that declares none reports the global namespace as `<global>`.
    func ReportInaccessibleMember(memberName: string, declarationFile: string?, line: int, column: int): bool {
        declaringNamespace := projectSourcesValue.GetNamespaceForFile(declarationFile)
        if declaringNamespace == null {
            declaringNamespace = "<global>"
        }

        Report(ErrorCode.InaccessibleMember, "'" + memberName + "' is not exported from package/namespace '" + declaringNamespace + "' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package", line, column, null, Math.Max(1, memberName.Length))
        return true
    }
}

namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE DIAGNOSTICS — every squiggle the IDE publishes and every row `nlc check` and `query
// diagnostics` print, assembled from the two INDEPENDENT sources the project has.
//
// COMPILER ERRORS COME FIRST, LINT DIAGNOSTICS SECOND, AND THE ORDER IS THE ANSWER. The list is not
// re-sorted anywhere: a consumer reading the first row is reading the first compiler error, and only
// once those run out does it reach lint.
//
// THE TWO SOURCES DISAGREE ABOUT THE DOCS URL ON PURPOSE. A compiler error carries whatever
// `DocsUrl` the error itself set — including NOTHING — while a lint diagnostic ALWAYS gets one from
// the catalog. `FromCompilerError` (the `nlc check` entry) is the third shape: it falls back to the
// catalog when the error carries no URL of its own. Three arms, three answers, and the difference
// between the first and the third is the one line that separates them.
//
// SHADOWING IS SUPPRESSED IN ONE DIRECTION ONLY. When the compiler already reported a shadowed
// declaration in a file, that file's LINT shadowing diagnostics are dropped so the same fact is not
// stated twice — but the compiler error is never dropped in favour of the lint one, and a file with
// no compiler shadowing error keeps every lint row it earned.
//
// THE DISK READ IS ORDERED BEFORE THE COMPILATION-UNIT LOOKUP AND THAT ORDER IS OBSERVABLE. A source
// file that is listed but never parsed still has its text read (and its `.editorconfig` resolved)
// before the walk discovers there is no unit to lint, so a file deleted between analysis and this
// call throws rather than being skipped.
class CodeIntelligenceDiagnostics {
    static func Build(projectRoot: string, allErrors: List<CompilerError>, sourceFiles: List<string>, compilationUnits: Dictionary<string, CompilationUnit>, sourceTexts: Dictionary<string, string>, fileFilter: string?): List<DiagnosticResult> {
        results := new List<DiagnosticResult>()
        filesWithCompilerShadowingErrors := CompilerShadowingErrorFiles(allErrors, projectRoot)

        errorIndex := 0
        while errorIndex < allErrors.Count {
            error := allErrors[errorIndex]
            errorFile := error.FileName ?? "unknown"
            if fileFilter == null || CodeIntelligenceResultKernels.MatchesFilePath(errorFile, fileFilter) {
                results.Add(FromProjectError(error, projectRoot, errorFile, sourceTexts))
            }
            errorIndex = errorIndex + 1
        }

        lintDiagnostics := LintDiagnostics(projectRoot, sourceFiles, compilationUnits, sourceTexts, fileFilter)
        if filesWithCompilerShadowingErrors.Count > 0 {
            lintDiagnostics = CodeIntelligenceResultKernels.SuppressLintShadowingDiagnosticResults(lintDiagnostics, filesWithCompilerShadowingErrors)
        }

        resultIndex := 0
        while resultIndex < lintDiagnostics.Count {
            results.Add(lintDiagnostics[resultIndex])
            resultIndex = resultIndex + 1
        }

        return CodeIntelligenceResultKernels.DeduplicateDiagnosticsPreservingOrderResults(results)
    }

    // The suppression list is built from EVERY compiler error, not the filtered ones: a `--file`
    // query still suppresses using the whole project's shadowing errors.
    static func CompilerShadowingErrorFiles(allErrors: List<CompilerError>, projectRoot: string): List<string> {
        files := new List<string>()

        errorIndex := 0
        while errorIndex < allErrors.Count {
            error := allErrors[errorIndex]
            errorFileName := error.FileName
            if error.Code == ErrorCode.ShadowedDeclaration && errorFileName != null && !String.IsNullOrWhiteSpace(errorFileName) {
                files.Add(CodeIntelligenceSourceDoor.RelativePath(projectRoot, errorFileName))
            }
            errorIndex = errorIndex + 1
        }

        return files
    }

    // ── The three DiagnosticResult shapes ───────────────────────────────

    // A PROJECT error, as `GetDiagnostics` reports it: the snippet falls back to the source line
    // through the FULL-PATH source-text door (which reads from disk when the text is not cached), and
    // the docs URL is whatever the error carried — `null` included.
    static func FromProjectError(error: CompilerError, projectRoot: string, errorFile: string, sourceTexts: Dictionary<string, string>): DiagnosticResult {
        snippet := error.SourceSnippet
        if String.IsNullOrWhiteSpace(snippet) && error.Line > 0 {
            snippet = CodeIntelligenceSourceDoor.SourceLine(SourceTextIn(sourceTexts, errorFile), error.Line)
        }

        return new DiagnosticResult(error.DiagnosticId, SeverityText(error.Severity), error.Message, CodeIntelligenceSourceDoor.RelativePath(projectRoot, errorFile), error.Line, error.Column, error.Length, snippet, error.HumanExplanation, error.Suggestion ?? CodeIntelligenceDisplayText.FormatSuggestions(error.Suggestions), error.ContextualHint, error.ExpectedType, error.ActualType, error.DocsUrl)
    }

    // A LINT diagnostic. Its length is never zero — a zero-width span is widened to one column so the
    // squiggle is visible — it carries no explanation, hint or type pair at all, and its docs URL
    // always comes from the catalog.
    static func FromLintDiagnostic(diagnostic: Diagnostic, projectRoot: string, sourceFile: string, source: string?): DiagnosticResult {
        return new DiagnosticResult(diagnostic.Code, LintSeverityText(diagnostic.Severity), diagnostic.Message, CodeIntelligenceSourceDoor.RelativePath(projectRoot, sourceFile), diagnostic.Location.Line, diagnostic.Location.Column, Math.Max(diagnostic.Length, 1), CodeIntelligenceSourceDoor.SourceLine(source, diagnostic.Location.Line), null, diagnostic.Suggestion, null, null, null, DiagnosticCatalog.DocsUrlFor(diagnostic.Code))
    }

    // ── The lint walk ───────────────────────────────────────────────────
    static func LintDiagnostics(projectRoot: string, sourceFiles: List<string>, compilationUnits: Dictionary<string, CompilationUnit>, sourceTexts: Dictionary<string, string>, fileFilter: string?): List<DiagnosticResult> {
        results := new List<DiagnosticResult>()

        fileIndex := 0
        while fileIndex < sourceFiles.Count {
            sourceFile := sourceFiles[fileIndex]
            fileIndex = fileIndex + 1

            fullPath := Path.GetFullPath(sourceFile)
            if fileFilter != null && !CodeIntelligenceResultKernels.MatchesFilePath(fullPath, fileFilter) {
                continue
            }

            source := ""
            if !sourceTexts.TryGetValue(fullPath, out source) || source == null {
                source = File.ReadAllText(fullPath)
            }

            // The linter's configuration is per FILE, not per project: each file resolves the
            // `.editorconfig` nearest its own directory, and the project root is only the fallback
            // for a path with no directory at all.
            fileDir := Path.GetDirectoryName(fullPath) ?? projectRoot
            linter := new Linter(LinterConfig.FromEditorConfig(fileDir))

            // The presence test and the read are separate on purpose: a `TryGetValue` out local stays
            // nullable to the checker on the true arm, and the linter's parameter is not.
            if !compilationUnits.ContainsKey(fullPath) {
                continue
            }

            diagnostics := linter.Lint(compilationUnits[fullPath], fullPath, source)
            diagnosticIndex := 0
            while diagnosticIndex < diagnostics.Count {
                results.Add(FromLintDiagnostic(diagnostics[diagnosticIndex], projectRoot, fullPath, source))
                diagnosticIndex = diagnosticIndex + 1
            }
        }

        return results
    }

    // ── The two severity renderings, which are NOT the same map ─────────
    // A compiler error has two levels and anything that is not an error is a warning; a lint
    // diagnostic has three, and its third is `info`. The strings are the JSON contract.
    static func SeverityText(severity: ErrorSeverity): string {
        if severity == ErrorSeverity.Error {
            return "error"
        }
        if severity == ErrorSeverity.Warning {
            return "warning"
        }
        return "info"
    }

    static func LintSeverityText(severity: DiagnosticSeverity): string {
        if severity == DiagnosticSeverity.Error {
            return "error"
        }
        if severity == DiagnosticSeverity.Warning {
            return "warning"
        }
        return "info"
    }

    // The full-path source-text door: a cached text wins, and anything else is read from disk. The
    // concrete dictionary is what crosses the boundary; the read-only interface is the same door
    // with a wider parameter and belongs to the member that still owns it in C#.
    static func SourceTextIn(sourceTexts: Dictionary<string, string>, filePath: string?): string? {
        if filePath == null {
            return null
        }

        fullPath := Path.GetFullPath(filePath)
        text := ""
        if sourceTexts.TryGetValue(fullPath, out text) && text != null {
            return text
        }

        return File.ReadAllText(fullPath)
    }
}

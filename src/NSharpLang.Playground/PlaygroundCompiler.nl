namespace NSharpLang.Playground

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar

// Public playground facade. The browser host calls these methods directly; all project analysis
// and response shaping stays here so the host has one stable contract.
sealed class PlaygroundCompiler {
    static SchemaVersion: int => 2
    static MaxSourceLength: int => 64 * 1024
    static MaxProjectSourceLength: int => 128 * 1024
    private static DefaultFileName: string => "Program.nl"

    func GetCatalog(): PlaygroundCatalogResponse {
        schemaVersion := SchemaVersion
        limitations := new string[](4)
        limitations[0] = "The hosted playground runs compiler analysis, formatting, completions, hover, syntax highlighting, and a bounded execution subset entirely in the browser."
        limitations[1] = "The Run button supports tutorial-scale code: functions, print, simple control flow, records/classes, object initializers, string/numeric helpers, and selected match patterns."
        limitations[2] = "Full build, test execution, NuGet restore, filesystem workflows, async, LINQ, and unrestricted .NET interop require the local nlc toolchain."
        limitations[3] = "External assembly resolution is intentionally bounded for browser reliability."
        capabilities := new PlaygroundCapabilities(true, true, true, true, true, true, true, false, limitations)
        examples := PlaygroundExamples.All
        tutorial := PlaygroundExamples.Tutorial
        defaultExampleId := PlaygroundExamples.DefaultId
        estimatedMinutes := PlaygroundExamples.EstimatedMinutes
        return new PlaygroundCatalogResponse(schemaVersion, defaultExampleId, estimatedMinutes, examples, tutorial, capabilities)
    }

    func Check(source: string?, fileName: string? = null): PlaygroundCheckResponse {
        files := new PlaygroundFile[](1)
        files[0] = new PlaygroundFile(NormalizeFileName(fileName), NormalizeSource(source))
        return CheckProject(files, fileName)
    }

    func CheckProject(files: IEnumerable<PlaygroundFile>?, activeFile: string? = null): PlaygroundCheckResponse {
        normalizedFiles := NormalizeFiles(files)
        normalizedActiveFile := NormalizeExistingFileName(activeFile, normalizedFiles)
        analysis := AnalyzeProject(normalizedFiles)
        return BuildCheckResponse(normalizedActiveFile, analysis.Diagnostics)
    }

    func Format(source: string?, fileName: string? = null): PlaygroundFormatResponse {
        schemaVersion := SchemaVersion
        normalizedSource := NormalizeSource(source)
        normalizedFileName := NormalizeFileName(fileName)
        check := Check(normalizedSource, normalizedFileName)
        if check.Summary.Errors > 0 {
            warnings := new string[](1)
            warnings[0] = "Formatting is skipped while the source has compiler errors."
            return new PlaygroundFormatResponse(schemaVersion, false, normalizedFileName, normalizedSource, check.Diagnostics, check.Summary, warnings)
        }

        try {
            lexer := new Lexer(normalizedSource, normalizedFileName)
            lexer.Tokenize()
            parseResult := ColumnarParserRecovery.ParseFileAst(normalizedSource, normalizedFileName)
            if parseResult.CompilationUnit == null {
                warnings := new string[](1)
                warnings[0] = "Formatting is skipped because the parser did not produce an AST."
                return new PlaygroundFormatResponse(schemaVersion, false, normalizedFileName, normalizedSource, check.Diagnostics, check.Summary, warnings)
            }

            formatter := new Formatter()
            formatResult := formatter.FormatSafe(normalizedSource, parseResult.CompilationUnit, lexer.Comments, normalizedFileName)
            return new PlaygroundFormatResponse(schemaVersion, formatResult.Success, normalizedFileName, formatResult.Text, check.Diagnostics, check.Summary, formatResult.Warnings)
        } catch ex: Exception {
            warnings := new string[](1)
            warnings[0] = "Formatting failed: " + ex.Message
            return new PlaygroundFormatResponse(schemaVersion, false, normalizedFileName, normalizedSource, check.Diagnostics, check.Summary, warnings)
        }
    }

    func Complete(files: IEnumerable<PlaygroundFile>?, fileName: string?, line: int, column: int): PlaygroundCompletionResponse {
        schemaVersion := SchemaVersion
        normalizedFiles := NormalizeFiles(files)
        normalizedFileName := NormalizeExistingFileName(fileName, normalizedFiles)
        analysis := AnalyzeProject(normalizedFiles)
        items := new List<PlaygroundCompletionItem>()
        context := CompletionContext.Unknown.ToString()
        receiver: string? = null
        receiverType: string? = null

        if analysis.Snapshot != null {
            engine := new CompletionEngine()
            result := engine.GetCompletions(analysis.Snapshot, normalizedFileName, Math.Max(line, 1), Math.Max(column, 0), true)
            context = result.Context.ToString()
            receiver = result.Receiver
            receiverType = result.ReceiverType
            for item in FlattenCompletions(result) {
                items.Add(item)
            }
        }

        diagnostics := Deduplicate(analysis.Diagnostics)
        summary := Summarize(diagnostics)
        return new PlaygroundCompletionResponse(schemaVersion, summary.Errors == 0, normalizedFileName, context, receiver, receiverType, items, diagnostics, summary)
    }

    func Hover(files: IEnumerable<PlaygroundFile>?, fileName: string?, line: int, column: int): PlaygroundHoverResponse {
        schemaVersion := SchemaVersion
        normalizedFiles := NormalizeFiles(files)
        normalizedFileName := NormalizeExistingFileName(fileName, normalizedFiles)
        analysis := AnalyzeProject(normalizedFiles)
        hover: PlaygroundHover? = null

        if analysis.Snapshot != null {
            service := new CodeIntelligenceService()
            result := service.GetHoverInfo(analysis.Snapshot, normalizedFileName, Math.Max(line, 1), Math.Max(column, 0))
            if result != null {
                hover = new PlaygroundHover(result.Signature, result.Documentation, result.DefinedIn, result.Kind)
            }
        }

        diagnostics := Deduplicate(analysis.Diagnostics)
        summary := Summarize(diagnostics)
        return new PlaygroundHoverResponse(schemaVersion, hover != null, normalizedFileName, hover, diagnostics, summary)
    }

    func RunProject(files: IEnumerable<PlaygroundFile>?, activeFile: string? = null): PlaygroundRunResponse {
        schemaVersion := SchemaVersion
        normalizedFiles := NormalizeFiles(files)
        normalizedActiveFile := NormalizeExistingFileName(activeFile, normalizedFiles)
        analysis := AnalyzeProject(normalizedFiles)
        diagnostics := Deduplicate(analysis.Diagnostics)
        summary := Summarize(diagnostics)

        if summary.Errors > 0 {
            return new PlaygroundRunResponse(schemaVersion, false, normalizedActiveFile, 1, string.Empty, "Run skipped because the program has compiler errors.", null, diagnostics, summary)
        }

        if analysis.Snapshot == null {
            failedDiagnostics := new List<PlaygroundDiagnostic>()
            for diagnostic in diagnostics {
                failedDiagnostics.Add(diagnostic)
            }
            failedDiagnostics.Add(new PlaygroundDiagnostic("PG200", "error", "Run skipped because the browser compiler could not build an executable snapshot.", normalizedActiveFile, 1, 1, 1, null, "The browser runner needs a successfully parsed and analyzed project snapshot before execution.", "Use the local nlc toolchain for this program, or simplify it for the hosted playground.", null))
            return BuildFailedRunResponse(normalizedActiveFile, Deduplicate(failedDiagnostics), "No executable snapshot was available.", null)
        }

        try {
            orderedUnits := new List<CompilationUnit>()
            for path in analysis.Snapshot.SourceFiles {
                unit: CompilationUnit? = null
                if analysis.Snapshot.CompilationUnits.TryGetValue(path, out unit) {
                    if unit != null {
                        orderedUnits.Add(unit)
                    }
                }
            }
            runner := new PlaygroundRunner(orderedUnits)
            run := runner.Run()
            return new PlaygroundRunResponse(schemaVersion, run.ExitCode == 0, normalizedActiveFile, run.ExitCode, run.Stdout, run.Stderr, null, diagnostics, summary)
        } catch caught: Exception {
            unsupported := caught as PlaygroundRunUnsupportedException
            if unsupported != null {
                runDiagnostics := new List<PlaygroundDiagnostic>()
                for diagnostic in diagnostics {
                    runDiagnostics.Add(diagnostic)
                }
                runDiagnostics.Add(new PlaygroundDiagnostic(unsupported.Code, "error", unsupported.Message, normalizedActiveFile, 1, 1, 1, null, "The hosted playground intentionally runs a bounded browser execution subset.", "Install nlc locally for full CLR execution, or try one of the smaller runnable samples.", "Diagnostics, formatting, hover, and completions still work for this code in the browser."))
                return BuildFailedRunResponse(normalizedActiveFile, Deduplicate(runDiagnostics), unsupported.Message, unsupported.Message)
            }

            runDiagnostics := new List<PlaygroundDiagnostic>()
            for diagnostic in diagnostics {
                runDiagnostics.Add(diagnostic)
            }
            runDiagnostics.Add(new PlaygroundDiagnostic("PG299", "error", "Run failed: " + caught.Message, normalizedActiveFile, 1, 1, 1, null, "The browser runner hit an unexpected execution failure.", "If this is reproducible, file an issue with the sample source.", null))
            return BuildFailedRunResponse(normalizedActiveFile, Deduplicate(runDiagnostics), caught.Message, null)
        }
    }

    private static func AnalyzeProject(files: IReadOnlyList<PlaygroundFile>): ProjectAnalysis {
        diagnostics := new List<PlaygroundDiagnostic>()
        totalLength := 0
        for playgroundFile in files {
            totalLength = totalLength + playgroundFile.Code.Length
        }
        if totalLength > MaxProjectSourceLength {
            diagnostics.Add(new PlaygroundDiagnostic("PG001", "error", "Playground source is too large. Maximum project size is " + MaxProjectSourceLength.ToString() + " characters.", files[0].Name, 1, 1, 1, null, "The hosted playground keeps analysis bounded so it can run reliably in the browser.", "Reduce the sample or use the local nlc toolchain for larger programs.", null))
            return new ProjectAnalysis(null, diagnostics)
        }

        for playgroundFile in files {
            if playgroundFile.Code.Length > MaxSourceLength {
                diagnostics.Add(new PlaygroundDiagnostic("PG001", "error", "Playground file '" + playgroundFile.Name + "' is too large. Maximum file size is " + MaxSourceLength.ToString() + " characters.", playgroundFile.Name, 1, 1, 1, null, "The hosted playground keeps per-file analysis bounded so it can run reliably in the browser.", "Reduce the sample or use the local nlc toolchain for larger programs.", null))
            }
        }
        if diagnostics.Count > 0 {
            return new ProjectAnalysis(null, diagnostics)
        }

        return AnalyzeWithProjectCompiler(GetAnalyzableFiles(files))
    }

    private static func AnalyzeWithProjectCompiler(files: IReadOnlyList<PlaygroundFile>): ProjectAnalysis {
        root := GetVirtualProjectRoot()
        paths := new List<string>()
        sourceOverrides := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        for playgroundFile in files {
            path := Path.GetFullPath(Path.Combine(root, playgroundFile.Name))
            paths.Add(path)
            sourceOverrides[path] = playgroundFile.Code
        }

        config := ProjectFileParser.CreateDefault("NSharpPlayground")
        config.Entry = files[0].Name
        config.Exclude = new string[](0)
        compiler := new MultiFileCompiler(paths, root, config, sourceOverrides)
        compiler.CompileForAnalysis()
        snapshot := new ProjectSnapshot(root, compiler.CompilationUnits, compiler.SemanticModels, compiler.AllErrors, compiler.SourceFiles, compiler.ProjectIndex, compiler.SourceTexts)

        service := new CodeIntelligenceService()
        diagnostics := new List<PlaygroundDiagnostic>()
        for diagnostic in service.GetDiagnostics(snapshot) {
            diagnostics.Add(ToPlaygroundDiagnostic(diagnostic))
        }
        AddLintDiagnostics(snapshot, diagnostics)
        return new ProjectAnalysis(snapshot, diagnostics)
    }

    private static func AddLintDiagnostics(snapshot: ProjectSnapshot, diagnostics: List<PlaygroundDiagnostic>) {
        linter := new Linter()
        for pair in snapshot.CompilationUnits {
            source := string.Empty
            text: string? = null
            if snapshot.SourceTexts.TryGetValue(pair.Key, out text) {
                source = text ?? string.Empty
            }
            for finding in linter.Lint(pair.Value, Path.GetFileName(pair.Key), source) {
                diagnostics.Add(ToPlaygroundDiagnostic(finding))
            }
        }
    }

    private static func FlattenCompletions(result: CompletionResult): IReadOnlyList<PlaygroundCompletionItem> {
        items := new List<PlaygroundCompletionItem>()
        for item in CompletionEngineKernels.FlattenCompletionGroups(result.Completions) {
            detail := ""
            if item.Parameters != null && !string.IsNullOrWhiteSpace(item.Parameters) {
                detail = item.Parameters
            }
            if item.Type != null && !string.IsNullOrWhiteSpace(item.Type) {
                if detail.Length > 0 {
                    detail = detail + " "
                }
                detail = detail + item.Type
            }
            detail = detail + EditorCompletionFacts.OverloadSuffix(item)
            items.Add(new PlaygroundCompletionItem(item.Name, item.Kind, detail, item.Documentation, item.Name))
            if items.Count >= 200 {
                break
            }
        }
        return items
    }

    private static func BuildCheckResponse(fileName: string, diagnostics: IReadOnlyList<PlaygroundDiagnostic>): PlaygroundCheckResponse {
        schemaVersion := SchemaVersion
        deduplicated := Deduplicate(diagnostics)
        summary := Summarize(deduplicated)
        return new PlaygroundCheckResponse(schemaVersion, summary.Errors == 0, fileName, deduplicated, summary)
    }

    private static func BuildFailedRunResponse(fileName: string, diagnostics: IReadOnlyList<PlaygroundDiagnostic>, stderr: string, unsupportedReason: string?): PlaygroundRunResponse {
        schemaVersion := SchemaVersion
        return new PlaygroundRunResponse(schemaVersion, false, fileName, 2, string.Empty, stderr, unsupportedReason, diagnostics, Summarize(diagnostics))
    }

    private static func Summarize(diagnostics: IEnumerable<PlaygroundDiagnostic>): PlaygroundSummary {
        errors := 0
        warnings := 0
        infos := 0
        for diagnostic in diagnostics {
            if diagnostic.Severity == "error" {
                errors = errors + 1
            } else if diagnostic.Severity == "warning" {
                warnings = warnings + 1
            } else if diagnostic.Severity == "info" {
                infos = infos + 1
            }
        }
        return new PlaygroundSummary(errors, warnings, infos)
    }

    private static func ToPlaygroundDiagnostic(diagnostic: DiagnosticResult): PlaygroundDiagnostic {
        return new PlaygroundDiagnostic(diagnostic.Code, NormalizeSeverity(diagnostic.Severity), diagnostic.Message, NormalizeFileName(diagnostic.File), Math.Max(diagnostic.Line, 1), Math.Max(diagnostic.Column, 1), Math.Max(diagnostic.Length, 1), diagnostic.SourceSnippet, diagnostic.Explanation, diagnostic.Suggestion, diagnostic.Hint)
    }

    private static func ToPlaygroundDiagnostic(diagnostic: Diagnostic): PlaygroundDiagnostic {
        severity := "info"
        if diagnostic.Severity == DiagnosticSeverity.Error {
            severity = "error"
        } else if diagnostic.Severity == DiagnosticSeverity.Warning {
            severity = "warning"
        }
        fileName := DefaultFileName
        if diagnostic.Location.FilePath != null {
            fileName = NormalizeFileName(diagnostic.Location.FilePath)
        }
        return new PlaygroundDiagnostic(diagnostic.Code, severity, diagnostic.Message, fileName, Math.Max(diagnostic.Location.Line, 1), Math.Max(diagnostic.Location.Column, 1), Math.Max(diagnostic.Length, 1), null, null, diagnostic.Suggestion, null)
    }

    private static func NormalizeSeverity(severity: string): string {
        if string.Equals(severity, "warning", StringComparison.OrdinalIgnoreCase) {
            return "warning"
        }
        if string.Equals(severity, "info", StringComparison.OrdinalIgnoreCase) {
            return "info"
        }
        return "error"
    }

    private static func Deduplicate(diagnostics: IEnumerable<PlaygroundDiagnostic>): IReadOnlyList<PlaygroundDiagnostic> {
        // Keep the first rich diagnostic for each stable location/message key, then apply the
        // response's severity/file/position order without depending on anonymous LINQ keys or a
        // comparer overload the columnar backend cannot emit for arbitrary source records.
        result := new List<PlaygroundDiagnostic>()
        for diagnostic in diagnostics {
            duplicate := false
            for existing in result {
                if existing.Code == diagnostic.Code && existing.File == diagnostic.File && existing.Line == diagnostic.Line && existing.Column == diagnostic.Column && existing.Message == diagnostic.Message {
                    duplicate = true
                    break
                }
            }
            if !duplicate {
                result.Add(diagnostic)
            }
        }

        index := 1
        while index < result.Count {
            current := result[index]
            position := index
            while position > 0 && CompareDiagnostics(current, result[position - 1]) < 0 {
                result[position] = result[position - 1]
                position = position - 1
            }
            result[position] = current
            index = index + 1
        }
        return result
    }

    private static func CompareDiagnostics(left: PlaygroundDiagnostic, right: PlaygroundDiagnostic): int {
        leftError := left.Severity == "error"
        rightError := right.Severity == "error"
        if leftError != rightError {
            if leftError {
                return -1
            }
            return 1
        }
        leftWarning := left.Severity == "warning"
        rightWarning := right.Severity == "warning"
        if leftWarning != rightWarning {
            if leftWarning {
                return -1
            }
            return 1
        }
        result := string.Compare(left.File, right.File, StringComparison.Ordinal)
        if result != 0 {
            return result
        }
        result = left.Line.CompareTo(right.Line)
        if result != 0 {
            return result
        }
        return left.Column.CompareTo(right.Column)
    }

    private static func NormalizeFiles(files: IEnumerable<PlaygroundFile>?): IReadOnlyList<PlaygroundFile> {
        normalized := new List<PlaygroundFile>()
        if files != null {
            for playgroundFile in files {
                normalized.Add(new PlaygroundFile(NormalizeFileName(playgroundFile.Name), NormalizeSource(playgroundFile.Code)))
            }
        }
        deduplicated := new List<PlaygroundFile>()
        for playgroundFile in normalized {
            found := -1
            index := 0
            while index < deduplicated.Count {
                if string.Equals(deduplicated[index].Name, playgroundFile.Name, StringComparison.OrdinalIgnoreCase) {
                    found = index
                    break
                }
                index = index + 1
            }
            if found >= 0 {
                deduplicated[found] = playgroundFile
            } else {
                deduplicated.Add(playgroundFile)
            }
        }
        if deduplicated.Count == 0 {
            deduplicated.Add(new PlaygroundFile(DefaultFileName, string.Empty))
        }
        return deduplicated
    }

    private static func GetAnalyzableFiles(files: IReadOnlyList<PlaygroundFile>): IReadOnlyList<PlaygroundFile> {
        filtered := new List<PlaygroundFile>()
        for playgroundFile in files {
            if !IsTestFile(playgroundFile.Name) {
                filtered.Add(playgroundFile)
            }
        }
        if filtered.Count == 0 {
            return files
        }
        return filtered
    }

    private static func IsTestFile(fileName: string): bool {
        return fileName.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase) || fileName.EndsWith(".tests.nsharp", StringComparison.OrdinalIgnoreCase)
    }

    private static func NormalizeSource(source: string?): string {
        value := source ?? string.Empty
        return value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace("\r", "\n", StringComparison.Ordinal)
    }

    private static func NormalizeExistingFileName(fileName: string?, files: IReadOnlyList<PlaygroundFile>): string {
        normalized := NormalizeFileName(fileName)
        for playgroundFile in files {
            if string.Equals(playgroundFile.Name, normalized, StringComparison.OrdinalIgnoreCase) {
                return normalized
            }
        }
        return files[0].Name
    }

    private static func NormalizeFileName(fileName: string?): string {
        if string.IsNullOrWhiteSpace(fileName) {
            return DefaultFileName
        }
        value := fileName ?? ""
        normalized := value.Replace('\\', '/')
        pieces := normalized.Split('/', StringSplitOptions.RemoveEmptyEntries)
        if pieces.Length == 0 {
            return DefaultFileName
        }
        candidate := pieces[pieces.Length - 1]
        if string.IsNullOrWhiteSpace(candidate) {
            return DefaultFileName
        }
        if candidate.EndsWith(".nl", StringComparison.OrdinalIgnoreCase) || candidate.EndsWith(".nsharp", StringComparison.OrdinalIgnoreCase) {
            return candidate
        }
        return candidate + ".nl"
    }

    private static func GetVirtualProjectRoot(): string {
        return Path.Combine(Path.GetTempPath(), "nsharp-playground")
    }

    private sealed record ProjectAnalysis(Snapshot: ProjectSnapshot?, Diagnostics: List<PlaygroundDiagnostic>) {
    }
}

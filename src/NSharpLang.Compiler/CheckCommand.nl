namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text.Json
import System.Threading.Tasks
import NSharpLang.Cli
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Performance

// The check command owns the complete analysis-to-output route. It deliberately shares the
// compiler-service facade and output formatter with query/daemon callers so a command invocation
// cannot drift from the public diagnostic schemas.
//
// CHECK READS `*.tests.nl`, AND THAT IS THE WHOLE POINT OF THE COMMAND. `nlc test` compiles the test
// files with the rest of the project, so a `check` that skipped them answered about a DIFFERENT
// program than the one that gets built: a project made entirely of test files reported
// `checkedFiles: 0` and `ok: true` while `nlc test` failed on the first lint error in it. Both the
// analysis snapshot and the IL verification below therefore take the `nlc test` file list. A
// single-project check keeps schema 1 because tests use its existing `checkedFiles` and `results`;
// the separate workspace envelope groups each member under schema 2.
//
// CHECK WRITES NO BUILD OUTPUT. A clean analysis is followed by the IL back end's validation
// (`MultiFileCompiler.ValidateAnalyzedEmission`), because the refusals that back end can still make
// (NL103) are decided only by walking the program's bodies; the image it produces stays in memory.
// No assembly, scratch directory or reference assembly is written. The incremental check-result
// stamp is the only project output, and the stats line counts no emitted assembly.
class CheckCommand {
    static func Execute(args: string[]): int {
        arguments := CheckCommandKernels.GetArgumentSummary(args)
        if arguments.ShowHelp {
            Console.WriteLine(CheckCommandKernels.GetHelpText())
            return 0
        }

        outputMode := CheckCommandKernels.GetEffectiveOutputMode(arguments.UseText, arguments.SystemsReport)
        useText := outputMode == 2 || outputMode == -1
        aot := arguments.Aot
        projectDir := CheckCommandKernels.GetProjectDirectory(
            arguments.ProjectOption,
            arguments.PositionalProject,
            Directory.GetCurrentDirectory()
        )

        if !Directory.Exists(projectDir) {
            return EmitError(useText, CheckCommandKernels.GetProjectDirectoryNotFoundMessage(projectDir), projectDir)
        }

        projectYmlPath := CheckCommandKernels.GetProjectYmlPath(projectDir)
        sw := Stopwatch.StartNew()
        warmKey: string? = null
        compiler: MultiFileCompiler? = null
        retainWarmSession := false

        try {
            nestedProjectRoots := new ProjectConfig().DiscoverNestedProjectRoots(projectDir)
            if nestedProjectRoots.Count > 0 {
                if outputMode == -1 {
                    return EmitError(useText, CheckCommandKernels.GetSystemsReportTextUnavailableMessage(), projectDir)
                }

                workspace := CheckWorkspacePlanner.Discover(projectDir)
                if workspace.ConflictMessage != null {
                    return EmitError(useText, workspace.ConflictMessage ?? "", projectDir)
                }

                return ExecuteWorkspace(workspace, projectDir, arguments, outputMode, aot, sw)
            }

            projectConfig := ProjectFileParser.ParseFromDirectory(projectDir)
            if projectConfig != null {
                referenceOptions := new ReferenceResolutionOptions("Debug", true, true, false, aot)
                referenceOptions.UseBuiltProjectReferences = arguments.UseBuiltReferences
                CompilationReferenceResolver.AddResolvedDllReferences(projectDir, projectConfig, referenceOptions)
            }

            CompilationBackendSelectionKernels.Validate(arguments.BackendOption, projectConfig)
            // ONE COMPILATION PER CHECK. The same compiler that analysed the project validates its
            // emission below when the analysis is clean, instead of a second compiler parsing,
            // analysing and loading the reference closure all over again.
            service := new CodeIntelligenceService()
            compiler = new MultiFileCompiler(projectDir, projectConfig, null, true) { AotMode: aot }
            // Ordinary diagnostics do not expose the full systems-function report. The diagnostic
            // pass preserves policy findings while avoiding summary work for unannotated cold code.
            compiler.SystemsDiagnosticsOnly = outputMode != 3
            // In the workspace server, the previous check of this project hands over its analyses
            // (`WarmIncrementalSessions`), so a body edit re-analyses only the files it can reach.
            warmKey = WarmIncrementalSessions.Attach(compiler, projectDir, "", "check", true, aot)
            if outputMode != -1 {
                cached := compiler.TryReadCheckResult(
                    CompilationReferenceResolver.GetProjectAssemblyName(projectDir, projectConfig ?? ProjectFileParser.CreateDefault(null)),
                    outputMode,
                    arguments.UseBuiltReferences,
                    arguments.BackendOption
                )
                if cached != null {
                    WriteCheckOutput(cached.Output, cached.OutputToStandardError)
                    retainWarmSession = cached.ExitCode == 0
                    return cached.ExitCode
                }
            }

            compiler.CompileForAnalysis()
            snapshot := service.SnapshotOfCompilation(projectDir, compiler)
            diagnostics := service.GetDiagnosticsWithLintFiles(snapshot, null, compiler.FilesToLint)
            diagnostics = OutputFormatter.DeduplicateAndSortDiagnostics(diagnostics)
            summary := OutputFormatter.SummarizeDiagnostics(diagnostics)

            sourceFileCount := snapshot.SourceFiles.Count
            hasProjectFile := File.Exists(projectYmlPath)
            if CheckCommandKernels.ShouldVerifyIlOutput(summary.Errors, sourceFileCount, hasProjectFile) {
                verificationDiagnostics := ValidateEmission(compiler, projectDir, projectConfig)
                if verificationDiagnostics.Count > 0 {
                    diagnostics.AddRange(verificationDiagnostics)
                    diagnostics = OutputFormatter.DeduplicateAndSortDiagnostics(diagnostics)
                    summary = OutputFormatter.SummarizeDiagnostics(diagnostics)
                }
            }

            if outputMode == -1 {
                return EmitError(useText, CheckCommandKernels.GetSystemsReportTextUnavailableMessage(), projectDir)
            }

            diagnosticsJson := OutputFormatter.CheckToJson(diagnostics, snapshot.ProjectRoot, snapshot.SourceFiles.Count)
            output := diagnosticsJson
            outputToStandardError := false
            if useText {
                textOutput := new System.Text.StringBuilder()
                if summary.Errors == 0 && summary.Warnings == 0 {
                    fileCount := snapshot.SourceFiles.Count
                    textOutput.AppendLine(CheckCommandKernels.GetNoErrorsMessage(
                        fileCount,
                        ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)
                    ))
                } else {
                    diagnosticText := OutputFormatter.DiagnosticsToText(diagnostics)
                    textOutput.Append(diagnosticText)
                    checkedInMessage := CheckCommandKernels.GetCheckedInMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds))
                    textOutput.AppendLine(checkedInMessage)
                }
                output = textOutput.ToString()
                outputToStandardError = true
            } else if outputMode == 3 {
                output = OutputFormatter.CheckSystemsReportToJson(
                    diagnostics,
                    snapshot.ProjectRoot,
                    snapshot.SourceFiles.Count,
                    snapshot.SystemsReport
                )
            } else {
                output = diagnosticsJson
            }

            exitCode := CheckCommandKernels.GetExitCode(summary.Errors)
            compiler.SaveCheckResult(output, diagnosticsJson, outputToStandardError, exitCode)
            WriteCheckOutput(output, outputToStandardError)
            retainWarmSession = exitCode == 0
            return exitCode
        } catch ex: Exception {
            if useText {
                Console.Error.WriteLine(CheckCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)))
            }

            return EmitError(useText, CheckCommandKernels.GetFailedMessage(ex.Message), projectDir)
        } finally {
            if retainWarmSession {
                WarmIncrementalSessions.Release(warmKey)
            } else {
                currentCompiler := compiler
                if currentCompiler != null {
                    currentCompiler.ReleaseReferenceMetadata()
                }
                WarmIncrementalSessions.Discard(warmKey)
            }
        }
    }

    private static func ExecuteWorkspace(
        workspace: CheckWorkspacePlan,
        projectDir: string,
        arguments: CheckArgumentSummary,
        outputMode: int,
        aotMode: bool,
        elapsed: Stopwatch
    ): int {
        let projectCount: int = workspace.Projects.Count
        if projectCount == 0 {
            return EmitError(false, "No N# project roots or loose source files were found under " + projectDir + ".", projectDir)
        }

        results := new List<CheckWorkspaceProjectResult>()
        sharedReferences := new ResolutionContext(null)
        sharedReferences.CacheProjectFailures = true
        sharedReferences.CompilesConcurrently = true

        // Resolve every member's project graph before any member starts analysis. The reference
        // resolver and the analyzers share process-wide metadata caches; compiling a cold project
        // reference while another workspace member analyzes can leave that reference with an
        // incomplete external-member view. Keep project builds in a serial preflight, then the
        // independent member analyses can still run concurrently below.
        referenceFailures := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        for project in workspace.Projects {
            referenceFailure := ResolveWorkspaceProjectReferences(
                project,
                arguments,
                aotMode,
                sharedReferences
            )
            if referenceFailure != null {
                referenceFailures[project.ProjectRoot] = referenceFailure ?? ""
            }
        }

        maxConcurrency := CheckCommandKernels.GetWorkspaceMaxConcurrency(Environment.ProcessorCount)
        textCompilerRetained := false
        batchStart := 0
        while batchStart < projectCount {
            batchCount := Math.Min(maxConcurrency, projectCount - batchStart)
            tasks := new Task<CheckWorkspaceProjectResult>[batchCount]
            for offset := 0; offset < batchCount; offset++ {
                project := workspace.Projects[batchStart + offset]
                referenceFailure := CheckWorkspaceReferenceFailure(referenceFailures, project.ProjectRoot)
                tasks[offset] = CheckWorkspaceProjectAsync(
                    project,
                    outputMode,
                    aotMode,
                    arguments.UseBuiltReferences,
                    arguments.BackendOption,
                    referenceFailure
                )
            }
            for offset := 0; offset < batchCount; offset++ {
                result := tasks[offset].GetAwaiter().GetResult()
                // JSON and systems-report results contain everything the caller needs; retaining
                // their compiler would keep every member's metadata context alive until the whole
                // workspace finishes. Text mode needs one compiler to persist the final aggregate
                // cache entry, so keep only the first one.
                if outputMode != 2 || textCompilerRetained || result.CheckCompiler == null {
                    result.ReleaseCompiler()
                } else {
                    textCompilerRetained = true
                }
                results.Add(result)
            }
            batchStart += batchCount
        }

        orderedResults := new List<CheckWorkspaceProjectResult>(results)
        orderedResults.Sort((left, right) => String.Compare(left.ProjectRoot, right.ProjectRoot, StringComparison.OrdinalIgnoreCase))
        hasErrors := false
        for result in orderedResults {
            if !result.Succeeded {
                hasErrors = true
            }
        }

        exitCode := 0
        if hasErrors {
            exitCode = 1
        }

        if outputMode == 2 {
            textOwner: CheckWorkspaceProjectResult? = null
            allResultsCached := true
            for result in orderedResults {
                if result.CheckCompiler != null && textOwner == null {
                    textOwner = result
                }
                if !result.CheckWasCached {
                    allResultsCached = false
                }
            }

            owner := textOwner
            if allResultsCached && owner != null && owner.CheckOutputToStandardError && owner.CheckOutput != null {
                Console.Error.Write(owner.CheckOutput ?? "")
            } else {
                output := RenderWorkspaceText(orderedResults, elapsed.ElapsedMilliseconds)
                Console.Error.Write(output)
                if owner != null && owner.CheckCompiler != null && owner.CheckDiagnosticsJson != null {
                    owner.CheckCompiler.SaveCheckResult(
                        output,
                        owner.CheckDiagnosticsJson ?? "",
                        true,
                        exitCode
                    )
                }
            }
        } else {
            Console.Write(OutputFormatter.CheckWorkspaceToJson(projectDir, orderedResults, outputMode == 3))
        }

        for result in orderedResults {
            result.ReleaseCompiler()
        }

        return exitCode
    }

    private static async func CheckWorkspaceProjectAsync(
        project: CheckWorkspaceProject,
        outputMode: int,
        aotMode: bool,
        useBuiltReferences: bool,
        backendOption: string?,
        referenceFailure: string?
    ): Task<CheckWorkspaceProjectResult> {
        await Task.Yield()
        return CheckWorkspaceProject(project, outputMode, aotMode, useBuiltReferences, backendOption, referenceFailure)
    }

    private static func ResolveWorkspaceProjectReferences(
        project: CheckWorkspaceProject,
        arguments: CheckArgumentSummary,
        aotMode: bool,
        sharedReferences: ResolutionContext
    ): string? {
        if project.ConfigError != null || project.Config == null {
            return null
        }

        try {
            config := project.Config
            CompilationBackendSelectionKernels.Validate(arguments.BackendOption, config)
            referenceOptions := new ReferenceResolutionOptions("Debug", true, true, false, aotMode)
            referenceOptions.UseBuiltProjectReferences = arguments.UseBuiltReferences
            referenceOptions.TestSourcesPresent = CheckCommandKernels.HasTestSourceFiles(project.SourceFiles)
            referenceOptions.WorkspaceContext = sharedReferences
            CompilationReferenceResolver.AddResolvedDllReferences(
                project.ProjectRoot,
                config,
                referenceOptions
            )
            return null
        } catch ex: Exception {
            return CheckCommandKernels.GetFailedMessage(ex.Message)
        }
    }

    private static func CheckWorkspaceReferenceFailure(
        failures: Dictionary<string, string>,
        projectRoot: string
    ): string? {
        let failure: string = ""
        if failures.TryGetValue(projectRoot, out failure) {
            return failure
        }
        return null
    }

    static func CheckWorkspaceProject(
        project: CheckWorkspaceProject,
        outputMode: int,
        aotMode: bool,
        useBuiltReferences: bool,
        backendOption: string?,
        referenceFailure: string?
    ): CheckWorkspaceProjectResult {
        emptyDiagnostics := new List<DiagnosticResult>()
        if project.ConfigError != null {
            return new CheckWorkspaceProjectResult(
                project.ProjectRoot,
                project.SourceFiles.Length,
                emptyDiagnostics,
                OutputFormatter.SummarizeDiagnostics(emptyDiagnostics),
                CheckCommandKernels.GetProjectConfigurationFailedMessage(project.ConfigError ?? ""),
                null
            )
        }

        if referenceFailure != null {
            return new CheckWorkspaceProjectResult(
                project.ProjectRoot,
                project.SourceFiles.Length,
                emptyDiagnostics,
                OutputFormatter.SummarizeDiagnostics(emptyDiagnostics),
                referenceFailure,
                null
            )
        }

        compiler: MultiFileCompiler? = null
        try {
            config := project.Config
            service := new CodeIntelligenceService()
            if config != null && project.SourceFiles.Length > 0 && File.Exists(CheckCommandKernels.GetProjectYmlPath(project.ProjectRoot)) {
                effectiveConfig := config ?? ProjectFileParser.CreateDefault(null)
                assemblyName := CompilationReferenceResolver.GetProjectAssemblyName(project.ProjectRoot, effectiveConfig)
                compiler = new MultiFileCompiler(project.SourceFiles, project.ProjectRoot, effectiveConfig, null) { AotMode: aotMode, Workers: 1 }
                compiler.SystemsDiagnosticsOnly = outputMode != 3
                cached := compiler.TryReadCheckResult(assemblyName, outputMode, useBuiltReferences, backendOption)
                if cached != null {
                    restored := RestoreWorkspaceProjectResult(project.ProjectRoot, cached)
                    if restored != null {
                        if outputMode == 2 {
                            restored.CheckCompiler = compiler
                        }
                        restored.CheckWasCached = true
                        restored.CheckOutput = cached.Output
                        restored.CheckOutputToStandardError = cached.OutputToStandardError
                        restored.CheckDiagnosticsJson = cached.DiagnosticsJson
                        return restored
                    }
                }

                compiler.CompileForAnalysis()
                compiler.ValidateAnalyzedEmission(assemblyName)
                snapshot := service.SnapshotOfCompilation(project.ProjectRoot, compiler)
                diagnostics := OutputFormatter.DeduplicateAndSortDiagnostics(service.GetDiagnosticsWithLintFiles(snapshot, null, compiler.FilesToLint))
                summary := OutputFormatter.SummarizeDiagnostics(diagnostics)
                diagnosticsJson := OutputFormatter.CheckToJson(diagnostics, snapshot.ProjectRoot, snapshot.SourceFiles.Count)
                resultJson := diagnosticsJson
                systemsReport: SystemsReport? = null
                if outputMode == 3 {
                    systemsReport = snapshot.SystemsReport
                    resultJson = OutputFormatter.CheckSystemsReportToJson(
                        diagnostics,
                        snapshot.ProjectRoot,
                        snapshot.SourceFiles.Count,
                        snapshot.SystemsReport
                    )
                }
                exitCode := CheckCommandKernels.GetExitCode(summary.Errors)
                compiler.SaveCheckResult(resultJson, resultJson, false, exitCode)
                result := new CheckWorkspaceProjectResult(
                    project.ProjectRoot,
                    snapshot.SourceFiles.Count,
                    diagnostics,
                    summary,
                    null,
                    systemsReport
                )
                // JSON workspace results never use the compiler after this member has been
                // summarized. Retaining every workspace compiler until the final JSON is written
                // keeps all of their reflection metadata graphs alive at once; text mode retains
                // the compiler only because it writes one combined text cache after all members.
                if outputMode == 2 {
                    result.CheckCompiler = compiler
                }
                result.CheckDiagnosticsJson = resultJson
                return result
            }

            snapshot := LoadWorkspaceProjectForCheck(service, project, config, aotMode)
            diagnostics := OutputFormatter.DeduplicateAndSortDiagnostics(service.GetDiagnostics(snapshot, null))
            summary := OutputFormatter.SummarizeDiagnostics(diagnostics)

            systemsReport: SystemsReport? = null
            if outputMode == 3 {
                systemsReport = snapshot.SystemsReport
            }
            return new CheckWorkspaceProjectResult(
                project.ProjectRoot,
                snapshot.SourceFiles.Count,
                diagnostics,
                summary,
                null,
                systemsReport
            )
        } catch ex: Exception {
            return new CheckWorkspaceProjectResult(
                project.ProjectRoot,
                project.SourceFiles.Length,
                emptyDiagnostics,
                OutputFormatter.SummarizeDiagnostics(emptyDiagnostics),
                CheckCommandKernels.GetFailedMessage(ex.Message),
                null
            )
        } finally {
            currentCompiler := compiler
            if currentCompiler != null {
                currentCompiler.ReleaseReferenceMetadata()
            }
        }
    }

    private static func RestoreWorkspaceProjectResult(projectRoot: string, cached: IncrementalCheckResult): CheckWorkspaceProjectResult? {
        try {
            using document := JsonDocument.Parse(cached.DiagnosticsJson)
            root := document.RootElement
            results: JsonElement = default
            if !root.TryGetProperty("results", out results) && !root.TryGetProperty("diagnostics", out results) {
                return null
            }

            diagnostics := new List<DiagnosticResult>()
            for item in results.EnumerateArray() {
                diagnostics.Add(new DiagnosticResult(
                    CachedDiagnosticString(item, "code"),
                    CachedDiagnosticString(item, "severity"),
                    CachedDiagnosticString(item, "message"),
                    CachedDiagnosticString(item, "file"),
                    CachedDiagnosticInt(item, "line"),
                    CachedDiagnosticInt(item, "column"),
                    CachedDiagnosticInt(item, "length"),
                    CachedDiagnosticOptionalString(item, "sourceSnippet"),
                    CachedDiagnosticOptionalString(item, "explanation"),
                    CachedDiagnosticOptionalString(item, "suggestion"),
                    CachedDiagnosticOptionalString(item, "hint"),
                    CachedDiagnosticOptionalString(item, "expectedType"),
                    CachedDiagnosticOptionalString(item, "actualType"),
                    CachedDiagnosticOptionalString(item, "docsUrl")
                ))
            }

            checkedFiles := CachedDiagnosticInt(root, "checkedFiles")
            restored := new CheckWorkspaceProjectResult(
                projectRoot,
                checkedFiles,
                diagnostics,
                OutputFormatter.SummarizeDiagnostics(diagnostics),
                null,
                null
            )
            systemsReport: JsonElement = default
            if root.TryGetProperty("systemsReport", out systemsReport) {
                restored.SystemsReportJson = systemsReport.GetRawText()
            }
            return restored
        } catch ex: Exception {
            return null
        }
    }

    private static func CachedDiagnosticString(value: JsonElement, name: string): string {
        property: JsonElement = default
        if value.TryGetProperty(name, out property) && property.ValueKind == JsonValueKind.String {
            return property.GetString() ?? ""
        }
        return ""
    }

    private static func CachedDiagnosticOptionalString(value: JsonElement, name: string): string? {
        property: JsonElement = default
        if value.TryGetProperty(name, out property) && property.ValueKind == JsonValueKind.String {
            return property.GetString()
        }
        return null
    }

    private static func CachedDiagnosticInt(value: JsonElement, name: string): int {
        property: JsonElement = default
        if value.TryGetProperty(name, out property) && property.ValueKind == JsonValueKind.Number {
            return property.GetInt32()
        }
        return 0
    }

    private static func LoadWorkspaceProjectForCheck(
        service: CodeIntelligenceService,
        project: CheckWorkspaceProject,
        config: ProjectConfig?,
        aotMode: bool
    ): ProjectSnapshot {
        if config == null || project.SourceFiles.Length == 0 || !File.Exists(CheckCommandKernels.GetProjectYmlPath(project.ProjectRoot)) {
            return service.LoadWorkspaceProjectIncludingTests(project.ProjectRoot, config, project.SourceFiles)
        }

        return service.LoadWorkspaceProjectIncludingTestsForCheck(
            project.ProjectRoot,
            config,
            project.SourceFiles,
            CompilationReferenceResolver.GetProjectAssemblyName(project.ProjectRoot, config),
            aotMode
        )
    }

    private static func RenderWorkspaceText(results: IReadOnlyList<CheckWorkspaceProjectResult>, elapsedMilliseconds: long): string {
        builder := new System.Text.StringBuilder()
        for result in results {
            builder.AppendLine("Project: " + result.ProjectRoot)
            if result.ErrorMessage != null {
                builder.AppendLine("  Error: " + (result.ErrorMessage ?? ""))
            } else if result.Summary.Errors == 0 && result.Summary.Warnings == 0 {
                builder.AppendLine(CheckCommandKernels.GetNoErrorsMessage(
                    result.CheckedFiles,
                    ProgramCommandKernels.FormatElapsedMilliseconds(elapsedMilliseconds)
                ))
            } else {
                builder.Append(OutputFormatter.DiagnosticsToText(result.Diagnostics))
                builder.AppendLine(CheckCommandKernels.GetCheckedInMessage(ProgramCommandKernels.FormatElapsedMilliseconds(elapsedMilliseconds)))
            }
        }
        builder.AppendLine("  Checked " + results.Count.ToString() + " projects in " + ProgramCommandKernels.FormatElapsedMilliseconds(elapsedMilliseconds) + ".")
        return builder.ToString()
    }

    // Validates the analysed program's emission in memory and reports any error the back end adds.
    private static func ValidateEmission(compiler: MultiFileCompiler, projectDir: string, config: ProjectConfig?): List<DiagnosticResult> {
        results := new List<DiagnosticResult>()
        effectiveConfig := config ?? ProjectFileParser.CreateDefault(null)
        assemblyName := CompilationReferenceResolver.GetProjectAssemblyName(projectDir, effectiveConfig)
        compileResult := compiler.ValidateAnalyzedEmission(assemblyName)

        if !compileResult.Success {
            errors := CompilerErrorSeverityFilter.Filter(compileResult.Errors, ErrorSeverity.Error)
            sourceTexts: IReadOnlyDictionary<string, string>? = null
            for error in errors {
                results.Add(CodeIntelligenceDiagnostics.FromCompilerError(error, projectDir, sourceTexts))
            }
        }

        return results
    }

    private static func EmitError(useText: bool, message: string, projectRoot: string? = null): int {
        if useText {
            Console.Error.WriteLine(message)
        } else {
            errorJson := OutputFormatter.ErrorToJson("check", message, projectRoot, null, null)
            Console.Write(errorJson)
        }

        return 1
    }

    private static func WriteCheckOutput(output: string, outputToStandardError: bool): void {
        if outputToStandardError {
            Console.Error.Write(output)
        } else {
            Console.Write(output)
        }
    }
}

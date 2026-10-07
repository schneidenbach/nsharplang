namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
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
// CHECK WRITES NOTHING. A clean analysis is followed by the IL back end's validation
// (`MultiFileCompiler.ValidateAnalyzedEmission`), because the refusals that back end can still make
// (NL103) are decided only by walking the program's bodies; the image it produces stays in memory.
// No assembly, scratch directory or reference assembly is written, and the stats line counts no
// emitted assembly.
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
            compiler := new MultiFileCompiler(projectDir, projectConfig, null, true) { AotMode: aot }
            // In the workspace server, the previous check of this project hands over its analyses
            // (`WarmIncrementalSessions`), so a body edit re-analyses only the files it can reach.
            warmKey = WarmIncrementalSessions.Attach(compiler, projectDir, "", "check", true, aot)
            compiler.CompileForAnalysis()
            snapshot := service.SnapshotOfCompilation(projectDir, compiler)
            diagnostics := service.GetDiagnostics(snapshot, null)
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

            if useText {
                if summary.Errors == 0 && summary.Warnings == 0 {
                    fileCount := snapshot.SourceFiles.Count
                    Console.Error.WriteLine(CheckCommandKernels.GetNoErrorsMessage(
                        fileCount,
                        ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)
                    ))
                } else {
                    diagnosticText := OutputFormatter.DiagnosticsToText(diagnostics)
                    writer := Console.Error
                    writer.Write(diagnosticText)
                    checkedInMessage := CheckCommandKernels.GetCheckedInMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds))
                    writer.WriteLine(checkedInMessage)
                }
            } else if outputMode == 3 {
                systemsJson := OutputFormatter.CheckSystemsReportToJson(
                    diagnostics,
                    snapshot.ProjectRoot,
                    snapshot.SourceFiles.Count,
                    snapshot.SystemsReport
                )
                Console.Write(systemsJson)
            } else {
                checkJson := OutputFormatter.CheckToJson(diagnostics, snapshot.ProjectRoot, snapshot.SourceFiles.Count)
                Console.Write(checkJson)
            }

            return CheckCommandKernels.GetExitCode(summary.Errors)
        } catch ex: Exception {
            WarmIncrementalSessions.Discard(warmKey)
            if useText {
                Console.Error.WriteLine(CheckCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)))
            }

            return EmitError(useText, CheckCommandKernels.GetFailedMessage(ex.Message), projectDir)
        } finally {
            WarmIncrementalSessions.Release(warmKey)
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
                    referenceFailure
                )
            }
            for offset := 0; offset < batchCount; offset++ {
                results.Add(tasks[offset].GetAwaiter().GetResult())
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

        if outputMode == 2 {
            WriteWorkspaceText(orderedResults, elapsed)
        } else {
            Console.Write(OutputFormatter.CheckWorkspaceToJson(projectDir, orderedResults, outputMode == 3))
        }

        if hasErrors {
            return 1
        }
        return 0
    }

    private static async func CheckWorkspaceProjectAsync(
        project: CheckWorkspaceProject,
        outputMode: int,
        aotMode: bool,
        referenceFailure: string?
    ): Task<CheckWorkspaceProjectResult> {
        await Task.Yield()
        return CheckWorkspaceProject(project, outputMode, aotMode, referenceFailure)
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

        try {
            config := project.Config
            service := new CodeIntelligenceService()
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
        }
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

    private static func WriteWorkspaceText(results: IReadOnlyList<CheckWorkspaceProjectResult>, elapsed: Stopwatch): void {
        for result in results {
            Console.Error.WriteLine("Project: " + result.ProjectRoot)
            if result.ErrorMessage != null {
                Console.Error.WriteLine("  Error: " + (result.ErrorMessage ?? ""))
            } else if result.Summary.Errors == 0 && result.Summary.Warnings == 0 {
                Console.Error.WriteLine(CheckCommandKernels.GetNoErrorsMessage(
                    result.CheckedFiles,
                    ProgramCommandKernels.FormatElapsedMilliseconds(elapsed.ElapsedMilliseconds)
                ))
            } else {
                Console.Error.Write(OutputFormatter.DiagnosticsToText(result.Diagnostics))
                Console.Error.WriteLine(CheckCommandKernels.GetCheckedInMessage(
                    ProgramCommandKernels.FormatElapsedMilliseconds(elapsed.ElapsedMilliseconds)
                ))
            }
        }
        Console.Error.WriteLine("  Checked " + results.Count.ToString() + " projects in " + ProgramCommandKernels.FormatElapsedMilliseconds(elapsed.ElapsedMilliseconds) + ".")
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
}

namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import NSharpLang.Cli
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// The check command owns the complete analysis-to-output route. It deliberately shares the
// compiler-service facade and output formatter with query/daemon callers so a command invocation
// cannot drift from the public diagnostic schemas.
//
// CHECK READS `*.tests.nl`, AND THAT IS THE WHOLE POINT OF THE COMMAND. `nlc test` compiles the test
// files with the rest of the project, so a `check` that skipped them answered about a DIFFERENT
// program than the one that gets built: a project made entirely of test files reported
// `checkedFiles: 0` and `ok: true` while `nlc test` failed on the first lint error in it. Both the
// analysis snapshot and the IL verification below therefore take the `nlc test` file list. No schema
// field moves for this: the test files are counted in the existing `checkedFiles` and their
// diagnostics arrive in the existing `results`, so `schemaVersion` stays 1.
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

        try {
            projectConfig := ProjectFileParser.ParseFromDirectory(projectDir)
            if projectConfig != null {
                referenceOptions := new ReferenceResolutionOptions("Debug", true, true, false, aot)
                CompilationReferenceResolver.AddResolvedDllReferences(projectDir, projectConfig, referenceOptions)
            }

            CompilationBackendSelectionKernels.Validate(arguments.BackendOption, projectConfig)
            service := new CodeIntelligenceService()
            snapshot := service.LoadProjectIncludingTests(projectDir, projectConfig, null)
            diagnostics := service.GetDiagnostics(snapshot, null)
            diagnostics = OutputFormatter.DeduplicateAndSortDiagnostics(diagnostics)
            summary := OutputFormatter.SummarizeDiagnostics(diagnostics)

            sourceFileCount := snapshot.SourceFiles.Count
            hasProjectFile := File.Exists(projectYmlPath)
            if CheckCommandKernels.ShouldVerifyIlOutput(summary.Errors, sourceFileCount, hasProjectFile) {
                verificationDiagnostics := VerifyIlOutput(projectDir, projectConfig, aot)
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
            if useText {
                Console.Error.WriteLine(CheckCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)))
            }

            return EmitError(useText, CheckCommandKernels.GetFailedMessage(ex.Message), projectDir)
        }
    }

    private static func VerifyIlOutput(projectDir: string, config: ProjectConfig?, aotMode: bool): List<DiagnosticResult> {
        results := new List<DiagnosticResult>()
        effectiveConfig := config
        if effectiveConfig == null {
            effectiveConfig = ProjectFileParser.ParseFromDirectory(projectDir)
            if effectiveConfig == null {
                effectiveConfig = ProjectFileParser.CreateDefault(null)
            }
        }

        tempDir := CheckCommandKernels.GetVerificationTempDirectory(Path.GetTempPath(), Guid.NewGuid().ToString("N"))
        try {
            Directory.CreateDirectory(tempDir)
            assemblyName := CompilationReferenceResolver.GetProjectAssemblyName(projectDir, effectiveConfig)
            outputPath := CheckCommandKernels.GetVerificationOutputPath(tempDir, assemblyName)
            compiler := new MultiFileCompiler(projectDir, effectiveConfig, null, true) { AotMode: aotMode }
            compileResult := compiler.CompileToIlAssembly(assemblyName, outputPath, false, true)

            if !compileResult.Success {
                errors := CompilerErrorSeverityFilter.Filter(compileResult.Errors, ErrorSeverity.Error)
                sourceTexts: IReadOnlyDictionary<string, string>? = null
                for error in errors {
                    results.Add(CodeIntelligenceDiagnostics.FromCompilerError(error, projectDir, sourceTexts))
                }
            }
        } finally {
            CleanupVerificationDirectory(tempDir)
        }

        return results
    }

    private static func CleanupVerificationDirectory(tempDir: string): void {
        try {
            Directory.Delete(tempDir, true)
        } catch {
        }
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

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
            Directory.GetCurrentDirectory())

        if !Directory.Exists(projectDir) {
            return EmitError(useText, CheckCommandKernels.GetProjectDirectoryNotFoundMessage(projectDir), projectDir)
        }

        projectYmlPath := CheckCommandKernels.GetProjectYmlPath(projectDir)
        sw := Stopwatch.StartNew()

        try {
            projectConfig := ProjectFileParser.ParseFromDirectory(projectDir)
            if projectConfig != null {
                referenceOptions := new ReferenceResolutionOptions("Debug", false, true, false, aot)
                CompilationReferenceResolver.AddResolvedDllReferences(projectDir, projectConfig, referenceOptions)
            }

            CompilationBackendSelectionKernels.Validate(arguments.BackendOption, projectConfig)
            service := new CodeIntelligenceService()
            snapshot := service.LoadProject(projectDir, projectConfig, null)
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
                        ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)))
                } else {
                    diagnosticText := OutputFormatter.DiagnosticsToText(diagnostics)
                    Console.Error.WriteLine(diagnosticText.TrimEnd())
                    Console.Error.WriteLine(CheckCommandKernels.GetCheckedInMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)))
                }
            } else if outputMode == 3 {
                Console.WriteLine(OutputFormatter.CheckSystemsReportToJson(
                    diagnostics,
                    snapshot.ProjectRoot,
                    snapshot.SourceFiles.Count,
                    snapshot.SystemsReport))
            } else {
                Console.WriteLine(OutputFormatter.CheckToJson(diagnostics, snapshot.ProjectRoot, snapshot.SourceFiles.Count))
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
            compiler := new MultiFileCompiler(projectDir, effectiveConfig) { AotMode: aotMode }
            compileResult := compiler.CompileToIlAssembly(assemblyName, outputPath, false, true)

            if !compileResult.Success {
                errors := CompilerErrorSeverityFilter.Filter(compileResult.Errors, ErrorSeverity.Error)
                for error in errors {
                    results.Add(CodeIntelligenceDiagnostics.FromCompilerError(error, projectDir, null))
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
            Console.WriteLine(errorJson)
        }

        return 1
    }
}

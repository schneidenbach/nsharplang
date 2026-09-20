namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Linq
import NSharpLang.Compiler

// The CLI's whole route from a project (or a single source file) to an emitted IL assembly, and the
// two `run` routes that execute what was emitted. `build`, `run`, `publish`, `test` and `pack` all
// arrive here: every one of them resolves references, compiles through MultiFileCompiler, reports
// the compiler's diagnostics on STDERR and copies runtime assets beside the output. Keeping the
// whole route in one owner is what makes "the same project builds the same way whichever command
// asked" a property of the code rather than of five call sites agreeing.
//
// The temp directory helpers live here because the single-file `run` route is their only user: it
// emits into a scratch directory, executes it, and deletes it in a finally.
class CliIlBackend {
    static func BuildWithIlBackend(
        projectRoot: string,
        release: bool,
        outputDir: string?,
        timings: bool,
        verbose: bool = false,
        aot: bool = false,
        cliDefines: IReadOnlyList<string>? = null
    ): BuildCommandResult {
        totalSw := Stopwatch.StartNew()
        resolveSw := new Stopwatch()
        compileSw := new Stopwatch()

        try {
            Console.WriteLine(BuildCommandKernels.GetProjectStartMessage(projectRoot))

            projectYmlPath := CompilationReferenceResolverKernels.GetProjectYmlPath(projectRoot)
            if !File.Exists(projectYmlPath) {
                return BuildCommandResult.Failure(CliError.Report(BuildCommandKernels.GetMissingProjectFileMessage()))
            }

            config := ProjectFileParser.Parse(projectYmlPath)
            configuration := BuildCommandKernels.GetConfigurationName(release)
            BuildCommandKernels.ApplyEffectiveDefines(config, debug: !release, cliDefines: cliDefines)
            resolvedOutputDir := BuildCommandKernels.GetOutputDirectory(projectRoot, configuration, config.TargetFramework, outputDir)

            quiet := !verbose
            referenceOptions := new ReferenceResolutionOptions {
                Configuration: configuration,
                Quiet: quiet,
                AotMode: aot
            }

            resolveSw.Start()
            references := CompilationReferenceResolver.AddResolvedDllReferences(projectRoot, config, referenceOptions)
            resolveSw.Stop()

            compileSw.Start()
            perfFacts: BuildPerfReportFacts = BuildPerfReportFacts.Empty
            outputPath := CompileProjectReportingPerfFacts(projectRoot, config, resolvedOutputDir, references, out perfFacts, false, aot)
            compileSw.Stop()
            if outputPath == null {
                Console.WriteLine(BuildCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(totalSw.ElapsedMilliseconds)))
                return BuildCommandResult.Failure(1, perfFacts)
            }

            Console.WriteLine(BuildCommandKernels.GetSuccessElapsedMessage(release, ProgramCommandKernels.FormatElapsedMilliseconds(totalSw.ElapsedMilliseconds)))
            Console.WriteLine(BuildCommandKernels.GetOutputPathMessage(outputPath))

            if timings {
                Console.Error.WriteLine(BuildCommandKernels.GetTimingsMessage(
                    ProgramCommandKernels.FormatElapsedMilliseconds(resolveSw.ElapsedMilliseconds),
                    ProgramCommandKernels.FormatElapsedMilliseconds(compileSw.ElapsedMilliseconds),
                    ProgramCommandKernels.FormatElapsedMilliseconds(totalSw.ElapsedMilliseconds)
                ))
            }

            return new BuildCommandResult(0, perfFacts)
        } catch ex: Exception {
            return BuildCommandResult.Failure(CliError.Report(BuildCommandKernels.GetFailedMessage(ex.Message)))
        }
    }

    static func BuildSingleFileWithIlBackend(
        sourceFile: string,
        projectConfig: ProjectConfig?,
        release: bool,
        outputDir: string?,
        aot: bool = false,
        cliDefines: IReadOnlyList<string>? = null
    ): BuildCommandResult {
        try {
            Console.WriteLine(BuildCommandKernels.GetSingleFileStartMessage(sourceFile))

            sourceDir := BuildCommandKernels.GetSourceDirectory(sourceFile, Directory.GetCurrentDirectory())
            config := GetEffectiveCompilationConfig(projectConfig, BuildCommandKernels.GetSourceFileAssemblyName(sourceFile))
            configuration := BuildCommandKernels.GetConfigurationName(release)
            BuildCommandKernels.ApplyEffectiveDefines(config, debug: !release, cliDefines: cliDefines)
            resolvedOutputDir := BuildCommandKernels.GetOutputDirectory(sourceDir, configuration, config.TargetFramework, outputDir)

            referenceOptions := new ReferenceResolutionOptions {
                Configuration: configuration,
                BuildProjectReferences: false
            }
            references := CompilationReferenceResolver.AddResolvedDllReferences(sourceDir, config, referenceOptions)
            sourceFiles: string[] = [sourceFile]
            perfFacts: BuildPerfReportFacts = BuildPerfReportFacts.Empty
            outputPath := CompileSourceFilesReportingPerfFacts(sourceFiles, sourceDir, config, resolvedOutputDir, references, out perfFacts, aot)
            if outputPath == null {
                return BuildCommandResult.Failure(1, perfFacts)
            }

            Console.WriteLine(BuildCommandKernels.GetSuccessMessage(release))
            Console.WriteLine(BuildCommandKernels.GetOutputPathMessage(outputPath))
            return new BuildCommandResult(0, perfFacts)
        } catch ex: Exception {
            return BuildCommandResult.Failure(CliError.Report(BuildCommandKernels.GetFailedMessage(ex.Message)))
        }
    }

    static func RunWithIlBackend(projectRoot: string, cliDefines: IReadOnlyList<string>? = null): int {
        try {
            normalizedRoot := BuildCommandKernels.NormalizeProjectRoot(projectRoot)
            projectYmlPath := CompilationReferenceResolverKernels.GetProjectYmlPath(normalizedRoot)
            if !File.Exists(projectYmlPath) {
                return CliError.Report(RunCommandKernels.GetMissingProjectFileMessage())
            }

            config := ProjectFileParser.Parse(projectYmlPath)
            if !CompilationReferenceResolverKernels.IsExecutableOutputType(config.OutputType) {
                return CliError.Report(RunCommandKernels.GetLibraryProjectMessage())
            }

            configuration := BuildCommandKernels.GetConfigurationName(false)
            BuildCommandKernels.ApplyEffectiveDefines(config, debug: true, cliDefines: cliDefines)
            outputDir := BuildCommandKernels.GetOutputDirectory(normalizedRoot, configuration, config.TargetFramework, null)
            referenceOptions := new ReferenceResolutionOptions {
                Configuration: configuration
            }
            references := CompilationReferenceResolver.AddResolvedDllReferences(normalizedRoot, config, referenceOptions)
            outputPath := CompileProject(normalizedRoot, config, outputDir, references, false, false)
            if outputPath == null {
                return BuildCommandKernels.GetExitCode(false)
            }

            Console.WriteLine()
            Console.WriteLine(RunCommandKernels.GetProjectStartingMessage())
            Console.WriteLine()
            return DotnetRunner.RunPassthrough("\"" + outputPath + "\"", normalizedRoot)
        } catch ex: Exception {
            return CliError.Report(RunCommandKernels.GetFailedMessage(ex.Message))
        }
    }

    static func RunSingleFileWithIlBackend(sourceFile: string, projectConfig: ProjectConfig?, cliDefines: IReadOnlyList<string>? = null): int {
        tempDir := CreateTempBuildDirectory()
        try {
            Console.WriteLine(RunCommandKernels.GetSingleFileBackendStartMessage(sourceFile))

            sourceDir := RunCommandKernels.GetSourceDirectory(sourceFile, Directory.GetCurrentDirectory())
            config := GetEffectiveCompilationConfig(projectConfig, BuildCommandKernels.GetSourceFileAssemblyName(sourceFile))
            BuildCommandKernels.ApplyEffectiveDefines(config, debug: true, cliDefines: cliDefines)
            if !CompilationReferenceResolverKernels.IsExecutableOutputType(config.OutputType) {
                return CliError.Report(RunCommandKernels.GetLibrarySourceFileMessage())
            }

            referenceOptions := new ReferenceResolutionOptions {
                BuildProjectReferences: false
            }
            references := CompilationReferenceResolver.AddResolvedDllReferences(sourceDir, config, referenceOptions)
            sourceFiles: string[] = [sourceFile]
            outputPath := CompileSourceFiles(sourceFiles, sourceDir, config, tempDir, references, false)
            if outputPath == null {
                return BuildCommandKernels.GetExitCode(false)
            }

            Console.WriteLine()
            return DotnetRunner.RunPassthrough("\"" + outputPath + "\"", sourceDir)
        } catch ex: Exception {
            return CliError.Report(RunCommandKernels.GetFailedMessage(ex.Message))
        } finally {
            CleanupDirectory(tempDir)
        }
    }

    // The shape `publish`, `test` and `pack` share: they already hold a parsed config and a chosen
    // configuration, and they want the output assembly path or null.
    static func BuildProjectWithIlBackendForCommand(
        projectRoot: string,
        config: ProjectConfig,
        configuration: string,
        outputDir: string? = null,
        includeTests: bool = false,
        verbose: bool = false,
        aotMode: bool = false
    ): string? {
        normalizedRoot := BuildCommandKernels.NormalizeProjectRoot(projectRoot)
        BuildCommandKernels.ApplyEffectiveDefines(config, debug: BuildCommandKernels.ShouldApplyDebugDefine(configuration), cliDefines: null)
        resolvedOutputDir := BuildCommandKernels.GetOutputDirectory(normalizedRoot, configuration, config.TargetFramework, outputDir)
        quiet := !verbose
        referenceOptions := new ReferenceResolutionOptions {
            Configuration: configuration,
            IncludeTests: includeTests,
            Quiet: quiet,
            AotMode: aotMode
        }
        references := CompilationReferenceResolver.AddResolvedDllReferences(normalizedRoot, config, referenceOptions)

        return CompileProject(normalizedRoot, config, resolvedOutputDir, references, includeTests, aotMode)
    }

    static func CreateTempBuildDirectory(): string {
        tempDir := BuildCommandKernels.GetTempBuildDirectory(Path.GetTempPath(), Guid.NewGuid().ToString("N"))
        Directory.CreateDirectory(tempDir)
        return tempDir
    }

    static func CleanupDirectory(path: string) {
        if !Directory.Exists(path) {
            return
        }

        try {
            Directory.Delete(path, true)
        } catch {
            // A temp directory that will not delete is not a build failure.
            return
        }
    }

    static func CompileProject(
        projectRoot: string,
        config: ProjectConfig,
        outputDir: string,
        references: ReferenceResolutionResult?,
        includeTests: bool,
        aotMode: bool
    ): string? {
        discardedPerfFacts: BuildPerfReportFacts = BuildPerfReportFacts.Empty
        return CompileProjectReportingPerfFacts(projectRoot, config, outputDir, references, out discardedPerfFacts, includeTests, aotMode)
    }

    static func CompileProjectReportingPerfFacts(
        projectRoot: string,
        config: ProjectConfig,
        outputDir: string,
        references: ReferenceResolutionResult?,
        out perfFacts: BuildPerfReportFacts,
        includeTests: bool,
        aotMode: bool
    ): string? {
        perfFacts = BuildPerfReportFacts.Empty
        sourceFiles := config.GetSourceFiles(projectRoot, includeTests).ToArray()
        compiler := new MultiFileCompiler(sourceFiles, projectRoot, config)
        return CompileReportingPerfFacts(
            compiler,
            outputDir,
            CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config),
            config,
            references,
            out perfFacts,
            aotMode
        )
    }

    static func CompileSourceFiles(
        sourceFiles: string[],
        projectRoot: string,
        config: ProjectConfig,
        outputDir: string,
        references: ReferenceResolutionResult?,
        aotMode: bool
    ): string? {
        discardedPerfFacts: BuildPerfReportFacts = BuildPerfReportFacts.Empty
        return CompileSourceFilesReportingPerfFacts(sourceFiles, projectRoot, config, outputDir, references, out discardedPerfFacts, aotMode)
    }

    static func CompileSourceFilesReportingPerfFacts(
        sourceFiles: string[],
        projectRoot: string,
        config: ProjectConfig,
        outputDir: string,
        references: ReferenceResolutionResult?,
        out perfFacts: BuildPerfReportFacts,
        aotMode: bool
    ): string? {
        perfFacts = BuildPerfReportFacts.Empty
        compiler := new MultiFileCompiler(sourceFiles, projectRoot, config)
        return CompileReportingPerfFacts(
            compiler,
            outputDir,
            CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config),
            config,
            references,
            out perfFacts,
            aotMode
        )
    }

    static func CompileReportingPerfFacts(
        compiler: MultiFileCompiler,
        outputDir: string,
        assemblyName: string,
        config: ProjectConfig,
        references: ReferenceResolutionResult?,
        out perfFacts: BuildPerfReportFacts,
        aotMode: bool
    ): string? {
        perfFacts = BuildPerfReportFacts.Empty
        Directory.CreateDirectory(outputDir)

        compiler.AotMode = aotMode
        outputPath := CompilationReferenceResolverKernels.GetProjectOutputAssemblyPath(outputDir, assemblyName)
        result := compiler.CompileToIlAssembly(assemblyName, outputPath, true)
        perfFacts = BuildCommandKernels.ToPerfReportFacts(compiler.SystemsReport)
        EmitCompilationDiagnostics(result)

        if CompilationReferenceResolverKernels.ShouldTreatProjectReferenceBuildAsFailed(result.Success, result.OutputAssemblyPath) {
            return null
        }

        if CompilationReferenceResolverKernels.IsExecutableOutputType(config.OutputType) {
            CompilationArtifacts.WriteRuntimeConfig(config, result.OutputAssemblyPath)
        }

        if references != null {
            references.CopyRuntimeAssets(outputDir)
        }

        return result.OutputAssemblyPath
    }

    static func EmitCompilationDiagnostics(result: MultiFileCompilationResult) {
        for error in result.Errors {
            Console.Error.WriteLine(error.Format(DiagnosticColorPolicy.ShouldColorizeStandardError()))
        }
    }

    static func GetEffectiveCompilationConfig(projectConfig: ProjectConfig?, defaultName: string): ProjectConfig {
        config := projectConfig ?? ProjectFileParser.CreateDefault(defaultName)
        if config.Name == null {
            config.Name = defaultName
        }

        return config
    }
}

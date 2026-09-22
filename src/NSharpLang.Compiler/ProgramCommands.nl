namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import System.Linq
import System.Runtime.InteropServices
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar

// The five commands that COMPILE something — `build`, `run`, `publish`, `new` and `format` — and
// the `--define` extraction they share. They are one owner because they are one route: each parses
// its flags through its own kernel, validates the backend, and hands the project to
// `CliIlBackend`, which is already N#.
//
// `Program.cs` keeps only `Main`, the command-number dispatch, `nlc test` and the assembly-version
// read; everything else that used to sit beside them is here. What stops the rest from following
// is recorded in census-briefs/CLI2-COMPILER-BLOCKERS.md under "cli4".
static class ProgramCommands {
    static func BuildCommand(args: string[]): int {
        helpOptions := BuildCommandKernels.GetOptionSummary(args)
        if helpOptions.ShowHelp {
            Console.WriteLine(BuildCommandKernels.GetHelpText())
            return 0
        }

        // Extract --define/-d before operand/flag detection so their values are never
        // mistaken for source-file operands by the build operand parsers.
        remainingArgs := args
        cliDefines := ExtractDefineFlags(ref remainingArgs)

        buildOptions := BuildCommandKernels.GetOptionSummary(remainingArgs)
        buildOperands := BuildCommandKernels.GetOperandSummary(remainingArgs)

        try {
            // Support both single-file and multi-file builds
            if buildOperands.Count == 0 {
                projectRoot := BuildCommandKernels.GetProjectRoot(buildOptions.ProjectOption, Directory.GetCurrentDirectory())
                currentProjectConfig := ProjectFileParser.ParseFromDirectory(projectRoot)
                CompilationBackendSelectionKernels.Validate(buildOptions.BackendOption, currentProjectConfig)

                projectBuild: Func<BuildCommandResult> = () => CliIlBackend.BuildWithIlBackend(
                    projectRoot,
                    buildOptions.Release,
                    buildOptions.OutputDir,
                    buildOptions.Timings,
                    buildOptions.Verbose,
                    buildOptions.Aot,
                    cliDefines
                )
                buildResult := RunBuildEmittingPerfReport(
                    buildOptions.PerfReport,
                    projectRoot,
                    projectBuild
                )
                return buildResult
            }

            sourceFile := remainingArgs[buildOperands.FirstOperandIndex]
            if !File.Exists(sourceFile) {
                return CliError.Report(CommandOutputKernels.GetFileNotFoundMessage(sourceFile))
            }

            sourceDir := BuildCommandKernels.GetSourceDirectory(sourceFile, Directory.GetCurrentDirectory())
            sourceProjectConfig := ProjectFileParser.ParseFromDirectory(sourceDir)
            CompilationBackendSelectionKernels.Validate(buildOptions.BackendOption, sourceProjectConfig)
            singleFileBuild: Func<BuildCommandResult> = () => CliIlBackend.BuildSingleFileWithIlBackend(
                sourceFile,
                sourceProjectConfig,
                buildOptions.Release,
                buildOptions.OutputDir,
                buildOptions.Aot,
                cliDefines
            )
            singleFileResult := RunBuildEmittingPerfReport(
                buildOptions.PerfReport,
                sourceDir,
                singleFileBuild
            )
            return singleFileResult
        } catch ex: Exception {
            return CliError.Report(BuildCommandKernels.GetFailedMessage(ex.Message))
        }
    }

    // Runs a build action and, when `perfReport` is set, emits a versioned JSON performance report
    // to stdout. While the report is active, the build's human-readable progress output is
    // redirected to stderr so stdout contains only valid JSON. The report's `ok` flag reflects
    // whether the build succeeded (exit code 0).
    static func RunBuildEmittingPerfReport(
        perfReport: bool,
        projectRoot: string,
        build: Func<BuildCommandResult>
    ): int {
        if !perfReport {
            return build().ExitCode
        }

        originalOut := Console.Out
        result: BuildCommandResult = BuildCommandResult.Failure(1, null)
        try {
            // Keep stdout reserved for the JSON report; send build logs to stderr.
            Console.SetOut(Console.Error)
            result = build()
        } finally {
            Console.SetOut(originalOut)
        }

        perfFacts := result.PerfFacts
        Console.WriteLine(
            OutputFormatter.BuildPerfReportToJson(
                projectRoot,
                result.ExitCode == 0,
                perfFacts.AllocationSites,
                perfFacts.DelegateSites,
                perfFacts.BoxingSites,
                perfFacts.DispatchSites,
                perfFacts.ClosureCaptures,
                perfFacts.PoolSites,
                perfFacts.ResourceSites,
                perfFacts.BoundaryLeakSites,
                perfFacts.HotReadinessSites,
                perfFacts.ImplicitTrapSites,
                perfFacts.TrustedSites
            )
        )
        return result.ExitCode
    }

    static func RunCommand(args: string[]): int {
        helpOptions := RunCommandKernels.GetOptionSummary(args)
        if helpOptions.ShowHelp {
            Console.WriteLine(RunCommandKernels.GetHelpText())
            return 0
        }

        // Extract --define/-d before operand detection so their values are never
        // mistaken for the source-file operand.
        remainingArgs := args
        cliDefines := ExtractDefineFlags(ref remainingArgs)
        runOptions := RunCommandKernels.GetOptionSummary(remainingArgs)
        backendOption := runOptions.BackendOption
        sourceFile := RunCommandKernels.GetSourceOperand(remainingArgs)

        try {
            if sourceFile == null {
                projectRoot := RunCommandKernels.GetProjectRoot(Directory.GetCurrentDirectory())
                currentProjectConfig := ProjectFileParser.ParseFromDirectory(projectRoot)
                CompilationBackendSelectionKernels.Validate(backendOption, currentProjectConfig)

                return CliIlBackend.RunWithIlBackend(projectRoot, cliDefines)
            }

            if !File.Exists(sourceFile) {
                return CliError.Report(CommandOutputKernels.GetFileNotFoundMessage(sourceFile))
            }

            Console.WriteLine(RunCommandKernels.GetSourceStartingMessage(sourceFile))

            sourceDir := RunCommandKernels.GetSourceDirectory(sourceFile, Directory.GetCurrentDirectory())
            sourceProjectConfig := ProjectFileParser.ParseFromDirectory(sourceDir)
            CompilationBackendSelectionKernels.Validate(backendOption, sourceProjectConfig)
            return CliIlBackend.RunSingleFileWithIlBackend(sourceFile, sourceProjectConfig, cliDefines)
        } catch ex: Exception {
            return CliError.Report(RunCommandKernels.GetFailedMessage(ex.Message))
        }
    }

    static func PublishCommand(args: string[]): int {
        publishArguments := PublishCommandKernels.GetArgumentSummary(args)
        if publishArguments.ShowHelp {
            Console.WriteLine(PublishCommandKernels.GetHelpText())
            return 0
        }

        validationError := publishArguments.ValidationError
        if validationError != null {
            return CliError.Report(validationError)
        }

        projectRoot := CommandOutputKernels.GetProjectRoot(publishArguments.ProjectOption, Directory.GetCurrentDirectory())
        backendOption := publishArguments.BackendOption

        try {
            Console.WriteLine(PublishCommandKernels.GetStartMessage(projectRoot))

            projectYmlPath := CompilationReferenceResolverKernels.GetProjectYmlPath(projectRoot)
            if !File.Exists(projectYmlPath) {
                return CliError.Report(PublishCommandKernels.GetMissingProjectFileMessage())
            }

            config := ProjectFileParser.Parse(projectYmlPath)
            CompilationBackendSelectionKernels.Validate(backendOption, config)

            configuration := publishArguments.Configuration
            output := publishArguments.Output
            runtime := publishArguments.Runtime
            if publishArguments.SelfContained {
                return CliError.Report(PublishCommandKernels.GetSelfContainedUnsupportedMessage())
            }

            if publishArguments.Aot {
                Console.WriteLine(PublishCommandKernels.GetAotAnalysisOnlyNotice())
            }

            if PublishCommandKernels.ShouldWriteRuntimeLauncher(runtime) {
                currentRuntime := RuntimeInformation.RuntimeIdentifier
                if !PublishCommandKernels.RuntimeMatchesRequestedRuntime(runtime, currentRuntime) {
                    return CliError.Report(PublishCommandKernels.GetCrossRuntimeUnsupportedMessage(runtime, currentRuntime))
                }
            }

            publishDir := PublishCommandKernels.GetPublishDirectory(projectRoot, configuration, config.TargetFramework, output)

            outputPath := CliIlBackend.BuildProjectWithIlBackendForCommand(
                projectRoot,
                config,
                configuration,
                publishDir,
                false,
                false,
                publishArguments.Aot
            )
            if outputPath == null {
                return CliError.Report(PublishCommandKernels.GetBuildFailureMessage(publishArguments.Aot))
            }

            if PublishCommandKernels.ShouldWriteRuntimeLauncher(runtime) {
                assemblyName := CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config)
                WriteDotnetLauncher(publishDir, assemblyName)
            }

            Console.WriteLine(PublishCommandKernels.GetSuccessMessage())
            return 0
        } catch ex: Exception {
            return CliError.Report(PublishCommandKernels.GetExceptionFailureMessage(ex.Message))
        }
    }

    static func WriteDotnetLauncher(outputDirectory: string, assemblyName: string) {
        Directory.CreateDirectory(outputDirectory)
        if OperatingSystem.IsWindows() {
            File.WriteAllText(
                PublishCommandKernels.GetWindowsLauncherPath(outputDirectory, assemblyName),
                PublishCommandKernels.GetWindowsLauncherText(assemblyName)
            )
            return
        }

        launcherPath := PublishCommandKernels.GetUnixLauncherPath(outputDirectory, assemblyName)
        File.WriteAllText(launcherPath, PublishCommandKernels.GetUnixLauncherText(assemblyName))
        try {
            File.SetUnixFileMode(
                launcherPath,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute
            )
        } catch modeFailure: Exception {
            // Best-effort on filesystems that do not support Unix modes.
        }
    }

    static func NewCommand(args: string[]): int {
        arguments := NewCommandKernels.GetArgumentSummary(args)
        if arguments.ShowHelp {
            Console.WriteLine(NewCommandKernels.GetHelpText())
            return 0
        }

        projectName := NewCommandKernels.GetEffectiveProjectName(
            arguments.FirstPositional,
            arguments.SecondPositional
        )
        if projectName == null {
            return CliError.Report(NewCommandKernels.GetUsageMessage())
        }

        requestedTemplate := NewCommandKernels.GetEffectiveRequestedTemplate(
            arguments.TemplateOption,
            arguments.FirstPositional,
            arguments.SecondPositional
        )

        systemsFlag := arguments.Systems
        templateKind := NewCommandKernels.ResolveTemplateKind(requestedTemplate ?? "console", systemsFlag)
        template := NewCommandKernels.GetProjectTemplateName(templateKind)
        if template == null {
            return CliError.Report(NewCommandKernels.GetInvalidTemplateMessage())
        }

        projectDir := NewCommandKernels.GetProjectDirectory(Directory.GetCurrentDirectory(), projectName)

        if Directory.Exists(projectDir) {
            return CliError.Report(NewCommandKernels.GetDirectoryExistsMessage(projectDir))
        }

        try {
            Console.WriteLine(NewCommandKernels.GetCreatingProjectMessage(template, projectName))

            Directory.CreateDirectory(projectDir)
            WriteCanonicalProject(projectDir, projectName, template)

            Console.WriteLine(NewCommandKernels.GetCreatedFileMessage(projectName, "project.yml"))
            Console.WriteLine(NewCommandKernels.GetCreatedFileMessage(projectName, "global.json"))
            Console.WriteLine(NewCommandKernels.GetCreatedFileMessage(projectName, "NuGet.config"))
            for sourceFileKind in NewCommandKernels.GetTemplateSourceFileKinds(template) {
                sourceFileName := NewCommandKernels.GetTemplateSourceFileName(sourceFileKind)
                Console.WriteLine(NewCommandKernels.GetCreatedFileMessage(projectName, sourceFileName))
            }

            Console.WriteLine()
            Console.WriteLine(NewCommandKernels.GetProjectShapeMessage())
            Console.WriteLine(NewCommandKernels.GetNextStepsIntroMessage(template))
            Console.WriteLine(NewCommandKernels.GetCdCommandMessage(projectName))
            if NewCommandKernels.ShouldShowSystemsCommands(template) {
                Console.WriteLine(NewCommandKernels.GetSystemsReportCommandMessage())
                Console.WriteLine(NewCommandKernels.GetSystemsBuildCommandMessage())
            } else {
                Console.WriteLine(NewCommandKernels.GetBuildCommandMessage())
                if NewCommandKernels.ShouldShowTestCommand(template) {
                    Console.WriteLine(NewCommandKernels.GetTestCommandMessage())
                } else if NewCommandKernels.ShouldShowRunCommand(template) {
                    Console.WriteLine(NewCommandKernels.GetRunCommandMessage())
                }
            }

            Console.WriteLine()

            return 0
        } catch ex: Exception {
            return CliError.Report(NewCommandKernels.GetFailedMessage(ex.Message))
        }
    }

    static func WriteCanonicalProject(projectDir: string, projectName: string, template: string) {
        File.WriteAllText(NewCommandKernels.GetProjectYamlPath(projectDir), NewCommandKernels.GetProjectYamlText(projectName, template))
        WriteSdkSupportFiles(projectDir)

        for sourceFileKind in NewCommandKernels.GetTemplateSourceFileKinds(template) {
            WriteTemplateSourceFile(projectDir, template, sourceFileKind)
        }
    }

    static func WriteTemplateSourceFile(
        projectDir: string,
        template: string,
        sourceFileKind: NewTemplateSourceFileKind
    ) {
        path := NewCommandKernels.GetTemplateSourceFilePath(projectDir, sourceFileKind)
        directory := NewCommandKernels.GetTemplateSourceFileDirectory(projectDir, sourceFileKind)
        if !string.IsNullOrEmpty(directory) {
            Directory.CreateDirectory(directory)
        }

        File.WriteAllText(path, NewCommandKernels.GetTemplateSourceText(template, sourceFileKind))
    }

    static func WriteSdkSupportFiles(projectDir: string) {
        File.WriteAllText(NewCommandKernels.GetGlobalJsonPath(projectDir), NewCommandKernels.GetGlobalJsonText())
        File.WriteAllText(
            NewCommandKernels.GetNuGetConfigPath(projectDir),
            NewCommandKernels.GetNuGetConfigText(NSharpInstallRoot.ProjectFeedValue())
        )
    }

    static func FormatCommand(args: string[]): int {
        formatOptions := FormatCommandKernels.GetOptionSummary(args)
        if formatOptions.ShowHelp {
            Console.WriteLine(FormatCommandKernels.GetHelpText())
            return 0
        }

        try {
            verifyOnly := formatOptions.VerifyOnly
            diffOnly := formatOptions.DiffOnly
            stdinMode := formatOptions.StdinMode
            projectRoot := CommandOutputKernels.GetProjectRoot(formatOptions.ProjectOption, Directory.GetCurrentDirectory())
            projectFlag := new string[](1)
            projectFlag[0] = "--project"
            positionalFiles := PositionalArgumentKernels.GetArgs(args, projectFlag)

            if stdinMode && positionalFiles.Length > 0 {
                Console.Error.WriteLine(FormatCommandKernels.GetStdinWithFilesMessage())
                return 1
            }

            if stdinMode {
                source := Console.In.ReadToEnd()
                formatted := FormatSource(source, "stdin.nl", projectRoot)

                if diffOnly {
                    Console.Write(UnifiedDiff.Create(source, formatted, "a/stdin.nl", "b/stdin.nl"))
                } else {
                    Console.Write(formatted)
                }

                return FormatCommandKernels.GetStdinExitCode(verifyOnly, source, formatted)
            }

            files: string[] = new string[](0)
            if positionalFiles.Length == 0 {
                files = EnumerateFormatFiles(projectRoot).ToArray()
            } else {
                resolved := new List<string>(positionalFiles.Length)
                for positionalFile in positionalFiles {
                    resolved.Add(FormatCommandKernels.ResolveFilePath(projectRoot, positionalFile))
                }

                files = resolved.ToArray()
            }

            if files.Length == 0 {
                Console.WriteLine(FormatCommandKernels.GetNoFilesFoundMessage())
                return 0
            }

            formattedCount := 0
            filesNeedingFormatting := new List<string>()
            failed := false

            for filePath in files {
                if !File.Exists(filePath) {
                    Console.Error.WriteLine(CommandOutputKernels.GetFileNotFoundMessage(filePath))
                    failed = true
                    continue
                }

                try {
                    source := File.ReadAllText(filePath)
                    formatted := FormatSource(source, filePath, projectRoot)
                    relativePath := FormatCommandKernels.GetRelativePath(projectRoot, filePath)

                    if FormatCommandKernels.ShouldEmitFormattedFile(source, formatted) {
                        filesNeedingFormatting.Add(relativePath)

                        if diffOnly {
                            Console.Write(UnifiedDiff.Create(source, formatted, "a/" + relativePath, "b/" + relativePath))
                        }

                        if !verifyOnly && !diffOnly {
                            File.WriteAllText(filePath, formatted)
                            formattedCount = formattedCount + 1
                        }
                    }
                } catch formatFailure: Exception {
                    Console.Error.WriteLine(FormatCommandKernels.GetErrorFormattingMessage(filePath, formatFailure.Message))
                    failed = true
                }
            }

            completionKind := FormatCommandKernels.GetCompletionKind(failed, verifyOnly, diffOnly, filesNeedingFormatting.Count)

            if completionKind == 1 {
                return 1
            }

            if completionKind == 2 {
                Console.Error.WriteLine(FormatCommandKernels.GetCheckFailedHeader(filesNeedingFormatting.Count))
                for needingFormatting in filesNeedingFormatting {
                    Console.Error.WriteLine(FormatCommandKernels.GetCheckFailedPathLine(needingFormatting))
                }

                return 1
            }

            if completionKind == 3 || completionKind == 4 {
                if completionKind == 3 {
                    Console.WriteLine(FormatCommandKernels.GetAllFilesFormattedMessage())
                }

                return 0
            }

            if completionKind == 5 {
                Console.WriteLine(FormatCommandKernels.GetAllFilesFormattedMessage())
                return 0
            }

            Console.WriteLine(FormatCommandKernels.GetFormattedCountMessage(formattedCount))
            return 0
        } catch ex: Exception {
            return CliError.Report(FormatCommandKernels.GetFailedMessage(ex.Message))
        }
    }

    static func FormatSource(source: string, filePath: string, projectRoot: string): string {
        lexer := new Lexer(source, filePath)
        lexer.Tokenize()
        // populates lexer.Comments for the formatter below
        parseResult := ColumnarParserRecovery.ParseFileAst(source, filePath)

        hasParseError := false
        parseMessages := new List<string>()
        for parseError in parseResult.Errors {
            if parseError.Severity == ErrorSeverity.Error {
                hasParseError = true
            }

            parseMessages.Add(parseError.Message)
        }

        if hasParseError {
            throw new Exception(FormatCommandKernels.GetParseErrorsMessage(
                FormatCommandKernels.GetRelativePath(projectRoot, filePath),
                string.Join(", ", parseMessages)
            ))
        }

        fileDir := FormatCommandKernels.GetFileDirectory(projectRoot, filePath)
        config := FormatterConfig.FromEditorConfig(fileDir)
        formatter := new Formatter(config)
        result := formatter.FormatSafe(source, must parseResult.CompilationUnit, lexer.Comments, filePath)

        relativePath := FormatCommandKernels.GetRelativePath(projectRoot, filePath)
        for warning in result.Warnings {
            Console.Error.WriteLine(FormatCommandKernels.GetWarningLine(relativePath, warning))
        }

        if !result.Success {
            throw new Exception(FormatCommandKernels.GetSafetyCheckFailedMessage(
                string.Join("; ", result.Warnings)
            ))
        }

        return result.Text
    }

    // The C# was an iterator (`yield return`), and its one caller consumed it with `.ToArray()`
    // immediately. An iterator body of this shape declines at emit.iterator.unsupported-shape
    // (census-briefs/CLI2-COMPILER-BLOCKERS.md, cli4), so the same walk fills a list in the same
    // order — which is the array the caller always built anyway.
    static func EnumerateFormatFiles(projectRoot: string): List<string> {
        discovered := new List<string>()
        pending := new Stack<string>()
        pending.Push(projectRoot)

        while pending.Count > 0 {
            directory := pending.Pop()

            childDirectories: string[] = new string[](0)
            childFiles: string[] = new string[](0)
            readFailed := false
            try {
                childDirectories = Directory.GetDirectories(directory)
                childFiles = Directory.GetFiles(directory, "*.nl")
            } catch ex: Exception {
                // The C# clause was a FILTER over three exception types; N# has no exception
                // filter, so the same three are tested here and anything else still propagates.
                if !(ex is UnauthorizedAccessException || ex is DirectoryNotFoundException || ex is IOException) {
                    throw
                }

                readFailed = true
            }

            if readFailed {
                continue
            }

            for childDirectory in childDirectories {
                name := FormatCommandKernels.GetDiscoveredDirectoryName(childDirectory)
                if !FormatCommandKernels.ShouldSkipDiscoveredDirectoryName(name) {
                    pending.Push(childDirectory)
                }
            }

            for childFile in childFiles {
                relativePath := FormatCommandKernels.GetRelativePath(projectRoot, childFile)
                if FormatCommandKernels.ShouldFormatDiscoveredPath(relativePath) {
                    discovered.Add(childFile)
                }
            }
        }

        return discovered
    }

    // Extracts conditional-compilation symbols from `--define`/`-d` flags (space form
    // `--define FOO`, equals form `--define=FOO`, and comma/semicolon lists `--define FOO,BAR`),
    // removing them from `args` so operand/flag detection never sees them. Returns the collected
    // symbols in first-seen order.
    static func ExtractDefineFlags(ref args: string[]): List<string> {
        extraction := DefineArgumentKernels.Extract(args)
        args = extraction.RemainingArgs
        defines := new List<string>()
        for define in extraction.Defines {
            defines.Add(define)
        }

        return defines
    }
}

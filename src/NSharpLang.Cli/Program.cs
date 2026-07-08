using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using NSharpLang.Compiler;
using NSharpLang.Cli.Commands;

namespace NSharpLang.Cli;

partial class Program
{
    static int Main(string[] args)
        => Execute(args);

    internal static int Execute(string[] args)
    {
        var commandKind = ProgramCommandKernels.GetCommandKind(args);

        if (commandKind == 29)
        {
            Console.WriteLine(ProgramCommandKernels.GetHelpText(GetVersion()));
            return 0;
        }

        if (commandKind == 30)
        {
            Console.WriteLine(ProgramCommandKernels.GetVersionText(GetVersion()));
            return 0;
        }

        return commandKind switch
        {
            1 => BuildCommand(GetCommandArgs(args)),
            2 => RunCommand(GetCommandArgs(args)),
            3 => PublishCommand(GetCommandArgs(args)),
            4 => NewCommand(GetCommandArgs(args)),
            5 => TestCommand(GetCommandArgs(args)),
            6 => FormatCommand(GetCommandArgs(args)),
            7 => Commands.LintCommand.Execute(GetCommandArgs(args)),
            8 => RestoreCommand.Execute(GetCommandArgs(args)),
            9 => CleanCommand.Execute(GetCommandArgs(args)),
            10 => WatchCommand.Execute(GetCommandArgs(args)),
            11 => DocCommand.Execute(GetCommandArgs(args)),
            12 => CompletionCommand.Execute(GetCommandArgs(args)),
            13 => Commands.CheckCommand.Execute(GetCommandArgs(args)),
            14 => FixCommand.Execute(GetCommandArgs(args)),
            15 => QueryCommand.Execute(GetCommandArgs(args)),
            16 => DaemonCommand.Execute(GetCommandArgs(args)),
            17 => AddCommand.Execute(GetCommandArgs(args)),
            18 => TidyCommand.Execute(GetCommandArgs(args)),
            19 => RemoveCommand.Execute(GetCommandArgs(args)),
            20 => UpdateCommand.Execute(GetCommandArgs(args)),
            21 => InitCommand.Execute(GetCommandArgs(args)),
            22 => EnvCommand.Execute(GetCommandArgs(args)),
            23 => DoctorCommand.Execute(GetCommandArgs(args)),
            24 => TreeCommand.Execute(GetCommandArgs(args)),
            25 => AuditCommand.Execute(GetCommandArgs(args)),
            26 => PackCommand.Execute(GetCommandArgs(args)),
            _ => Error(ProgramCommandKernels.GetUnknownCommandMessage(
                args.Length == 0 ? string.Empty : args[0].ToLower()))
        };
    }

    private static string[] GetCommandArgs(string[] args)
        => args.Length <= 1 ? Array.Empty<string>() : args.Skip(1).ToArray();

    static int BuildCommand(string[] args)
    {
        var helpOptions = BuildCommandKernels.GetOptionSummary(args);
        if (helpOptions.ShowHelp)
        {
            Console.WriteLine(BuildCommandKernels.GetHelpText());
            return 0;
        }

        // Extract --define/-d before operand/flag detection so their values are never
        // mistaken for source-file operands by the build operand parsers.
        var cliDefines = ExtractDefineFlags(ref args);

        var buildOptions = BuildCommandKernels.GetOptionSummary(args);
        var buildOperands = BuildCommandKernels.GetOperandSummary(args);

        try
        {
            // Support both single-file and multi-file builds
            if (buildOperands.Count == 0)
            {
                var projectRoot = BuildCommandKernels.GetProjectRoot(buildOptions.ProjectOption, Directory.GetCurrentDirectory());
                var currentProjectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
                CompilationBackendSelectionKernels.Validate(buildOptions.BackendOption, currentProjectConfig);

                var buildResult = RunBuildEmittingPerfReport(
                    buildOptions.PerfReport,
                    projectRoot,
                    () => BuildWithIlBackend(
                        projectRoot,
                        buildOptions.Release,
                        buildOptions.OutputDir,
                        buildOptions.Timings,
                        buildOptions.Verbose,
                        buildOptions.Aot,
                        cliDefines));
                return buildResult;
            }

            var sourceFile = args[buildOperands.FirstOperandIndex];
            if (!File.Exists(sourceFile))
            {
                return Error(BuildCommandKernels.GetFileNotFoundMessage(sourceFile));
            }

            var sourceDir = BuildCommandKernels.GetSourceDirectory(sourceFile, Directory.GetCurrentDirectory());
            var sourceProjectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);
            CompilationBackendSelectionKernels.Validate(buildOptions.BackendOption, sourceProjectConfig);
            var singleFileResult = RunBuildEmittingPerfReport(
                buildOptions.PerfReport,
                sourceDir,
                () => BuildSingleFileWithIlBackend(
                    sourceFile,
                    sourceProjectConfig,
                    buildOptions.Release,
                    buildOptions.OutputDir,
                    buildOptions.Aot,
                    cliDefines));
            return singleFileResult;
        }
        catch (Exception ex)
        {
            return Error(BuildCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    /// <summary>
    /// Runs a build action and, when <paramref name="perfReport"/> is set, emits a versioned
    /// JSON performance report to stdout. While the report is active, the build's human-readable
    /// progress output is redirected to stderr so stdout contains only valid JSON. The report's
    /// <c>ok</c> flag reflects whether the build succeeded (exit code 0).
    /// </summary>
    static int RunBuildEmittingPerfReport(
        bool perfReport,
        string projectRoot,
        Func<BuildCommandResult> build)
    {
        if (!perfReport)
        {
            return build().ExitCode;
        }

        var originalOut = Console.Out;
        BuildCommandResult result;
        try
        {
            // Keep stdout reserved for the JSON report; send build logs to stderr.
            Console.SetOut(Console.Error);
            result = build();
        }
        finally
        {
            Console.SetOut(originalOut);
        }

        Console.WriteLine(
            NSharpLang.Compiler.CodeIntelligence.OutputFormatter.BuildPerfReportToJson(
                projectRoot,
                result.ExitCode == 0,
                result.PerfFacts.AllocationSites,
                result.PerfFacts.DelegateSites,
                result.PerfFacts.BoxingSites,
                result.PerfFacts.DispatchSites,
                result.PerfFacts.ClosureCaptures,
                result.PerfFacts.PoolSites,
                result.PerfFacts.ResourceSites,
                result.PerfFacts.BoundaryLeakSites,
                result.PerfFacts.HotReadinessSites,
                result.PerfFacts.ImplicitTrapSites,
                result.PerfFacts.TrustedSites));
        return result.ExitCode;
    }

    static string CreateTempBuildDirectory()
    {
        var tempDir = BuildCommandKernels.GetTempBuildDirectory(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);
        return tempDir;
    }

    static void CleanupDirectory(string path)
    {
        if (!Directory.Exists(path))
        {
            return;
        }

        try
        {
            Directory.Delete(path, true);
        }
        catch
        {
            // Ignore cleanup errors for temp directories
        }
    }

    static int RunCommand(string[] args)
    {
        var helpOptions = RunCommandKernels.GetOptionSummary(args);
        if (helpOptions.ShowHelp)
        {
            Console.WriteLine(RunCommandKernels.GetHelpText());
            return 0;
        }

        // Extract --define/-d before operand detection so their values are never
        // mistaken for the source-file operand.
        var cliDefines = ExtractDefineFlags(ref args);
        var runOptions = RunCommandKernels.GetOptionSummary(args);
        var backendOption = runOptions.BackendOption;
        var sourceFile = RunCommandKernels.GetSourceOperand(args);

        try
        {
            if (sourceFile == null)
            {
                var projectRoot = RunCommandKernels.GetProjectRoot(Directory.GetCurrentDirectory());
                var currentProjectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
                CompilationBackendSelectionKernels.Validate(backendOption, currentProjectConfig);

                return RunWithIlBackend(projectRoot, cliDefines);
            }

            if (!File.Exists(sourceFile))
            {
                return Error(RunCommandKernels.GetFileNotFoundMessage(sourceFile));
            }

            Console.WriteLine(RunCommandKernels.GetSourceStartingMessage(sourceFile));

            var sourceDir = RunCommandKernels.GetSourceDirectory(sourceFile, Directory.GetCurrentDirectory());
            var sourceProjectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);
            CompilationBackendSelectionKernels.Validate(backendOption, sourceProjectConfig);
            return RunSingleFileWithIlBackend(sourceFile, sourceProjectConfig, cliDefines);
        }
        catch (Exception ex)
        {
            return Error(RunCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    static int PublishCommand(string[] args)
    {
        var publishArguments = PublishCommandKernels.GetArgumentSummary(args);
        if (publishArguments.ShowHelp)
        {
            Console.WriteLine(PublishCommandKernels.GetHelpText());
            return 0;
        }

        if (publishArguments.ValidationError != null)
        {
            return Error(publishArguments.ValidationError);
        }

        var projectRoot = PublishCommandKernels.GetProjectRoot(publishArguments.ProjectOption, Directory.GetCurrentDirectory());
        var backendOption = publishArguments.BackendOption;

        try
        {
            Console.WriteLine(PublishCommandKernels.GetStartMessage(projectRoot));

            var projectYmlPath = CompilationReferenceResolverKernels.GetProjectYmlPath(projectRoot);
            if (!File.Exists(projectYmlPath))
            {
                return Error(PublishCommandKernels.GetMissingProjectFileMessage());
            }

            var config = ProjectFileParser.Parse(projectYmlPath);
            CompilationBackendSelectionKernels.Validate(backendOption, config);

            var configuration = publishArguments.Configuration;
            var output = publishArguments.Output;
            var runtime = publishArguments.Runtime;
            if (publishArguments.SelfContained)
            {
                return Error(PublishCommandKernels.GetSelfContainedUnsupportedMessage());
            }

            if (publishArguments.Aot)
            {
                Console.WriteLine(PublishCommandKernels.GetAotAnalysisOnlyNotice());
            }

            if (PublishCommandKernels.ShouldWriteRuntimeLauncher(runtime))
            {
                var currentRuntime = RuntimeInformation.RuntimeIdentifier;
                if (!PublishCommandKernels.RuntimeMatchesRequestedRuntime(runtime, currentRuntime))
                {
                    return Error(PublishCommandKernels.GetCrossRuntimeUnsupportedMessage(runtime, currentRuntime));
                }
            }

            var publishDir = PublishCommandKernels.GetPublishDirectory(projectRoot, configuration, config.TargetFramework, output);

            var outputPath = BuildProjectWithIlBackendForCommand(
                projectRoot,
                config,
                configuration,
                publishDir,
                includeTests: false,
                aotMode: publishArguments.Aot);
            if (outputPath == null)
            {
                return Error(PublishCommandKernels.GetBuildFailureMessage(publishArguments.Aot));
            }

            if (PublishCommandKernels.ShouldWriteRuntimeLauncher(runtime))
            {
                WriteDotnetLauncher(publishDir, CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config));
            }

            Console.WriteLine(PublishCommandKernels.GetSuccessMessage());
            return 0;
        }
        catch (Exception ex)
        {
            return Error(PublishCommandKernels.GetExceptionFailureMessage(ex.Message));
        }
    }

    private static void WriteDotnetLauncher(string outputDirectory, string assemblyName)
    {
        Directory.CreateDirectory(outputDirectory);
        if (OperatingSystem.IsWindows())
        {
            File.WriteAllText(
                PublishCommandKernels.GetWindowsLauncherPath(outputDirectory, assemblyName),
                PublishCommandKernels.GetWindowsLauncherText(assemblyName));
            return;
        }

        var launcherPath = PublishCommandKernels.GetUnixLauncherPath(outputDirectory, assemblyName);
        File.WriteAllText(launcherPath, PublishCommandKernels.GetUnixLauncherText(assemblyName));
        try
        {
            File.SetUnixFileMode(
                launcherPath,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute |
                UnixFileMode.GroupRead | UnixFileMode.GroupExecute |
                UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
        }
        catch
        {
            // Best-effort on filesystems that do not support Unix modes.
        }
    }

    static int NewCommand(string[] args)
    {
        var arguments = NewCommandKernels.GetArgumentSummary(args);
        if (arguments.ShowHelp)
        {
            Console.WriteLine(NewCommandKernels.GetHelpText());
            return 0;
        }

        var projectName = NewCommandKernels.GetEffectiveProjectName(
            arguments.FirstPositional,
            arguments.SecondPositional);
        if (projectName == null)
        {
            return Error(NewCommandKernels.GetUsageMessage());
        }

        var requestedTemplate = NewCommandKernels.GetEffectiveRequestedTemplate(
            arguments.TemplateOption,
            arguments.FirstPositional,
            arguments.SecondPositional);

        var systemsFlag = arguments.Systems;
        var template = NewCommandKernels.GetProjectTemplateName(
            NewCommandKernels.ResolveTemplateKind(requestedTemplate ?? "console", systemsFlag));
        if (template == null)
        {
            return Error(NewCommandKernels.GetInvalidTemplateMessage());
        }

        var projectDir = NewCommandKernels.GetProjectDirectory(Directory.GetCurrentDirectory(), projectName);

        if (Directory.Exists(projectDir))
        {
            return Error(NewCommandKernels.GetDirectoryExistsMessage(projectDir));
        }

        try
        {
            Console.WriteLine(NewCommandKernels.GetCreatingProjectMessage(template, projectName));

            Directory.CreateDirectory(projectDir);
            WriteCanonicalProject(projectDir, projectName, template);

            Console.WriteLine(NewCommandKernels.GetCreatedFileMessage(projectName, "project.yml"));
            Console.WriteLine(NewCommandKernels.GetCreatedFileMessage(projectName, "global.json"));
            Console.WriteLine(NewCommandKernels.GetCreatedFileMessage(projectName, "NuGet.config"));
            foreach (var sourceFileKind in NewCommandKernels.GetTemplateSourceFileKinds(template))
            {
                var file = NewCommandKernels.GetTemplateSourceFileName(sourceFileKind);
                Console.WriteLine(NewCommandKernels.GetCreatedFileMessage(projectName, file));
            }

            Console.WriteLine();
            Console.WriteLine(NewCommandKernels.GetProjectShapeMessage());
            Console.WriteLine(NewCommandKernels.GetNextStepsIntroMessage(template));
            Console.WriteLine(NewCommandKernels.GetCdCommandMessage(projectName));
            if (NewCommandKernels.ShouldShowSystemsCommands(template))
            {
                Console.WriteLine(NewCommandKernels.GetSystemsReportCommandMessage());
                Console.WriteLine(NewCommandKernels.GetSystemsBuildCommandMessage());
            }
            else
            {
                Console.WriteLine(NewCommandKernels.GetBuildCommandMessage());
                if (NewCommandKernels.ShouldShowTestCommand(template))
                    Console.WriteLine(NewCommandKernels.GetTestCommandMessage());
                else if (NewCommandKernels.ShouldShowRunCommand(template))
                    Console.WriteLine(NewCommandKernels.GetRunCommandMessage());
            }
            Console.WriteLine();

            return 0;
        }
        catch (Exception ex)
        {
            return Error(NewCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    static void WriteCanonicalProject(string projectDir, string projectName, string template)
    {
        File.WriteAllText(NewCommandKernels.GetProjectYamlPath(projectDir), NewCommandKernels.GetProjectYamlText(projectName, template));
        WriteSdkSupportFiles(projectDir);

        foreach (var sourceFileKind in NewCommandKernels.GetTemplateSourceFileKinds(template))
            WriteTemplateSourceFile(projectDir, template, sourceFileKind);
    }

    static void WriteTemplateSourceFile(
        string projectDir,
        string template,
        NewTemplateSourceFileKind sourceFileKind)
    {
        var path = NewCommandKernels.GetTemplateSourceFilePath(projectDir, sourceFileKind);
        var directory = NewCommandKernels.GetTemplateSourceFileDirectory(projectDir, sourceFileKind);
        if (!string.IsNullOrEmpty(directory))
            Directory.CreateDirectory(directory);

        File.WriteAllText(path, NewCommandKernels.GetTemplateSourceText(template, sourceFileKind));
    }

    static void WriteSdkSupportFiles(string projectDir)
    {
        File.WriteAllText(NewCommandKernels.GetGlobalJsonPath(projectDir), NewCommandKernels.GetGlobalJsonText());
        File.WriteAllText(
            NewCommandKernels.GetNuGetConfigPath(projectDir),
            NewCommandKernels.GetNuGetConfigText(NSharpInstallRoot.ProjectFeedValue()));
    }

    static int TestCommand(string[] args)
    {
        var testOptions = TestCommandKernels.GetOptionSummary(args);
        if (testOptions.ShowHelp)
        {
            Console.WriteLine(TestCommandKernels.GetHelpText());
            return 0;
        }

        var projectRoot = TestCommandKernels.GetProjectRoot(testOptions.ProjectOption, Directory.GetCurrentDirectory());
        var outputMode = TestCommandKernels.GetOutputMode(testOptions.JsonOutput);

        // Parse timeout to milliseconds
        int? timeoutMs = null;
        if (testOptions.Timeout != null)
        {
            timeoutMs = TestCommandKernels.GetDurationMilliseconds(testOptions.Timeout);
            if (timeoutMs == null)
            {
                var message = TestCommandKernels.GetInvalidTimeoutMessage(testOptions.Timeout);
                if (outputMode == 1)
                {
                    OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), message, summary: NativeTestSummary.EmptyFailure);
                    return 1;
                }

                return Error(message);
            }
        }

        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            if (outputMode == 2) Console.WriteLine(TestCommandKernels.GetProjectStartMessage(projectRoot));

            if (testOptions.CollectCoverage || testOptions.CoverageReport)
            {
                var message = TestCommandKernels.GetCoverageUnsupportedMessage();
                if (outputMode == 1)
                {
                    OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), message, summary: NativeTestSummary.EmptyFailure);
                    return 1;
                }

                return Error(message);
            }

            // Find all .tests.nl files
            var testFiles = Directory.GetFiles(projectRoot, "*.tests.nl", SearchOption.AllDirectories);

            if (testFiles.Length == 0)
            {
                if (outputMode == 1)
                {
                    OutputNativeTestJson(projectRoot, true, Array.Empty<NativeTestResult>(), summary: new NativeTestSummary(true, 0, 0, 0, 0));
                    return 0;
                }
                Console.WriteLine(TestCommandKernels.GetNoTestFilesMessage());
                return 0;
            }

            if (outputMode == 2) Console.WriteLine(TestCommandKernels.GetFoundTestFilesMessage(testFiles.Length));

            var projectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
            CompilationBackendSelectionKernels.Validate(testOptions.BackendOption, projectConfig);

            return TestWithIlBackend(
                projectRoot,
                projectConfig,
                testOptions.Filter,
                testOptions.Verbose,
                outputMode,
                timeoutMs,
                testOptions.NoCache,
                testOptions.CollectCoverage,
                testOptions.CoverageReport,
                sw);
        }
        catch (Exception ex)
        {
            if (outputMode == 2)
                Console.WriteLine(TestCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)));
            if (outputMode == 1) { OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), ex.Message, summary: NativeTestSummary.EmptyFailure); return 1; }
            return Error(TestCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    static int FormatCommand(string[] args)
    {
        var formatOptions = FormatCommandKernels.GetOptionSummary(args);
        if (formatOptions.ShowHelp)
        {
            Console.WriteLine(FormatCommandKernels.GetHelpText());
            return 0;
        }

        try
        {
            var verifyOnly = formatOptions.VerifyOnly;
            var diffOnly = formatOptions.DiffOnly;
            var stdinMode = formatOptions.StdinMode;
            var projectRoot = FormatCommandKernels.GetProjectRoot(formatOptions.ProjectOption, Directory.GetCurrentDirectory());
            var positionalFiles = PositionalArgumentKernels.GetArgs(args, ["--project"]);

            if (stdinMode && positionalFiles.Length > 0)
            {
                Console.Error.WriteLine(FormatCommandKernels.GetStdinWithFilesMessage());
                return 1;
            }

            if (stdinMode)
            {
                var source = Console.In.ReadToEnd();
                var formatted = FormatSource(source, "stdin.nl", projectRoot);

                if (diffOnly)
                    Console.Write(UnifiedDiff.Create(source, formatted, "a/stdin.nl", "b/stdin.nl"));
                else
                    Console.Write(formatted);

                return FormatCommandKernels.GetStdinExitCode(verifyOnly, source, formatted);
            }

            string[] files;
            if (positionalFiles.Length == 0)
            {
                files = EnumerateFormatFiles(projectRoot).ToArray();
            }
            else
            {
                files = positionalFiles
                    .Select(file => FormatCommandKernels.ResolveFilePath(projectRoot, file))
                    .ToArray();
            }

            if (files.Length == 0)
            {
                Console.WriteLine(FormatCommandKernels.GetNoFilesFoundMessage());
                return 0;
            }

            var formattedCount = 0;
            var filesNeedingFormatting = new List<string>();
            var failed = false;

            foreach (var file in files)
            {
                if (!File.Exists(file))
                {
                    Console.Error.WriteLine(FormatCommandKernels.GetFileNotFoundMessage(file));
                    failed = true;
                    continue;
                }

                try
                {
                    var source = File.ReadAllText(file);
                    var formatted = FormatSource(source, file, projectRoot);
                    var relativePath = FormatCommandKernels.GetRelativePath(projectRoot, file);

                    if (FormatCommandKernels.ShouldEmitFormattedFile(source, formatted))
                    {
                        filesNeedingFormatting.Add(relativePath);

                        if (diffOnly)
                            Console.Write(UnifiedDiff.Create(source, formatted, $"a/{relativePath}", $"b/{relativePath}"));

                        if (!verifyOnly && !diffOnly)
                        {
                            File.WriteAllText(file, formatted);
                            formattedCount++;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine(FormatCommandKernels.GetErrorFormattingMessage(file, ex.Message));
                    failed = true;
                }
            }

            var completionKind = FormatCommandKernels.GetCompletionKind(failed, verifyOnly, diffOnly, filesNeedingFormatting.Count);

            if (completionKind == 1)
                return 1;

            if (completionKind == 2)
            {
                Console.Error.WriteLine(FormatCommandKernels.GetCheckFailedHeader(filesNeedingFormatting.Count));
                foreach (var file in filesNeedingFormatting)
                    Console.Error.WriteLine(FormatCommandKernels.GetCheckFailedPathLine(file));
                return 1;
            }

            if (completionKind == 3 || completionKind == 4)
            {
                if (completionKind == 3)
                    Console.WriteLine(FormatCommandKernels.GetAllFilesFormattedMessage());
                return 0;
            }

            if (completionKind == 5)
            {
                Console.WriteLine(FormatCommandKernels.GetAllFilesFormattedMessage());
                return 0;
            }

            Console.WriteLine(FormatCommandKernels.GetFormattedCountMessage(formattedCount));
            return 0;
        }
        catch (Exception ex)
        {
            return Error(FormatCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    static string FormatSource(string source, string file, string projectRoot)
    {
        var lexer = new Lexer(source, file);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, file, source);
        var parseResult = parser.ParseCompilationUnit();

        if (parseResult.Errors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            throw new Exception(FormatCommandKernels.GetParseErrorsMessage(
                FormatCommandKernels.GetRelativePath(projectRoot, file),
                string.Join(", ", parseResult.Errors.Select(e => e.Message))));
        }

        var fileDir = FormatCommandKernels.GetFileDirectory(projectRoot, file);
        var config = FormatterConfig.FromEditorConfig(fileDir);
        var formatter = new Formatter(config);
        var result = formatter.FormatSafe(source, parseResult.CompilationUnit!, lexer.Comments, file);

        var relativePath = FormatCommandKernels.GetRelativePath(projectRoot, file);
        foreach (var warning in result.Warnings)
        {
            Console.Error.WriteLine(FormatCommandKernels.GetWarningLine(relativePath, warning));
        }

        if (!result.Success)
        {
            throw new Exception(FormatCommandKernels.GetSafetyCheckFailedMessage(
                string.Join("; ", result.Warnings)));
        }

        return result.Text;
    }

    static IEnumerable<string> EnumerateFormatFiles(string projectRoot)
    {
        var pending = new Stack<string>();
        pending.Push(projectRoot);

        while (pending.Count > 0)
        {
            var directory = pending.Pop();

            string[] childDirectories;
            string[] childFiles;
            try
            {
                childDirectories = Directory.GetDirectories(directory);
                childFiles = Directory.GetFiles(directory, "*.nl");
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or DirectoryNotFoundException or IOException)
            {
                continue;
            }

            foreach (var childDirectory in childDirectories)
            {
                var name = FormatCommandKernels.GetDiscoveredDirectoryName(childDirectory);
                if (!FormatCommandKernels.ShouldSkipDiscoveredDirectoryName(name))
                {
                    pending.Push(childDirectory);
                }
            }

            foreach (var file in childFiles)
            {
                var relativePath = FormatCommandKernels.GetRelativePath(projectRoot, file);
                if (FormatCommandKernels.ShouldFormatDiscoveredPath(relativePath))
                {
                    yield return file;
                }
            }
        }
    }

    /// <summary>
    /// Extracts conditional-compilation symbols from <c>--define</c>/<c>-d</c> flags
    /// (space form <c>--define FOO</c>, equals form <c>--define=FOO</c>, and
    /// comma/semicolon lists <c>--define FOO,BAR</c>), removing them from
    /// <paramref name="args"/> so operand/flag detection never sees them. Returns the
    /// collected symbols in first-seen order.
    /// </summary>
    static List<string> ExtractDefineFlags(ref string[] args)
    {
        var extraction = DefineArgumentKernels.Extract(args);
        args = extraction.RemainingArgs;
        return extraction.Defines.ToList();
    }

    internal static string GetVersion()
    {
        return typeof(Program).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion
            ?? typeof(Program).Assembly.GetName().Version?.ToString()
            ?? "unknown";
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(message));
        return 1;
    }
}

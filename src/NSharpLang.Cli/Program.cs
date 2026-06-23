using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using NSharpLang.Compiler;
using NSharpLang.Cli.Commands;

namespace NSharpLang.Cli;

internal readonly record struct PublishArgumentSummary(
    string? ValidationError,
    string? ProjectOption,
    string? BackendOption,
    string Configuration,
    string? Output,
    string? Runtime,
    bool SelfContained,
    bool Aot,
    bool ShowHelp);

internal readonly record struct BuildOptionSummary(
    string? OutputDir,
    string? BackendOption,
    string? ProjectOption,
    bool Release,
    bool Verbose,
    bool Timings,
    bool PerfReport,
    bool Aot,
    bool ShowHelp);

internal readonly record struct TestOptionSummary(
    string? ProjectOption,
    string? BackendOption,
    string? Filter,
    string? Timeout,
    bool Verbose,
    bool JsonOutput,
    bool CoverageReport,
    bool CollectCoverage,
    bool NoCache,
    bool ShowHelp);

partial class Program
{
    private static readonly string[] NewProjectOptionsWithValues = ["--template", "--type"];

    static int Main(string[] args)
        => Execute(args);

    internal static int Execute(string[] args)
    {
        var commandKind = GetCommandKind(args);

        return commandKind switch
        {
            ProgramCommandKind.Build => BuildCommand(GetCommandArgs(args)),
            ProgramCommandKind.Run => RunCommand(GetCommandArgs(args)),
            ProgramCommandKind.Publish => PublishCommand(GetCommandArgs(args)),
            ProgramCommandKind.New => NewCommand(GetCommandArgs(args)),
            ProgramCommandKind.Test => TestCommand(GetCommandArgs(args)),
            ProgramCommandKind.Format => FormatCommand(GetCommandArgs(args)),
            ProgramCommandKind.Lint => Commands.LintCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Restore => RestoreCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Clean => CleanCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Watch => WatchCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Doc => DocCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Completion => CompletionCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Check => Commands.CheckCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Fix => FixCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Query => QueryCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Daemon => DaemonCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Add => AddCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Tidy => TidyCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Remove => RemoveCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Update => UpdateCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Init => InitCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Env => EnvCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Doctor => DoctorCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Tree => TreeCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Audit => AuditCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Pack => PackCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Export => Commands.ExportCommand.Execute(GetCommandArgs(args)),
            ProgramCommandKind.Help => ShowHelp(),
            ProgramCommandKind.Version => ShowVersion(),
            ProgramCommandKind.Transpile => Error(ProgramCommandKernels.GetTranspileRemovedMessage()),
            _ => Error(ProgramCommandKernels.GetUnknownCommandMessage(GetCommandNameForError(args)))
        };
    }

    internal static ProgramCommandKind GetCommandKind(string[] args)
    {
        if (ProgramCommandKernels.TryGetCommandKind(args, out var commandKind))
            return commandKind;

        throw new InvalidOperationException("N# dogfood compiler services are required for top-level CLI command routing.");
    }

    private static string GetCommandNameForError(string[] args)
        => args.Length == 0 ? string.Empty : args[0].ToLower();

    private static string[] GetCommandArgs(string[] args)
        => args.Length <= 1 ? Array.Empty<string>() : args.Skip(1).ToArray();

    static int BuildCommand(string[] args)
    {
        var helpOptions = GetBuildOptionSummary(args);
        if (helpOptions.ShowHelp)
        {
            Console.WriteLine(BuildCommandKernels.GetHelpText());
            return 0;
        }

        // Extract --define/-d before operand/flag detection so their values are never
        // mistaken for source-file operands by the build operand parsers.
        var cliDefines = ExtractDefineFlags(ref args);

        var buildOptions = GetBuildOptionSummary(args);
        var buildOperands = GetBuildOperandSummary(args);

        try
        {
            // Support both single-file and multi-file builds
            if (buildOperands.Count == 0)
            {
                var projectRoot = buildOptions.ProjectOption != null
                    ? Path.GetFullPath(buildOptions.ProjectOption)
                    : Directory.GetCurrentDirectory();
                var currentProjectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
                var backend = ResolveCompilationBackend(buildOptions.BackendOption, currentProjectConfig);
                if (backend != CompilationBackend.Il)
                {
                    throw new InvalidOperationException(CompilationBackendExtensions.RetiredTranspileBackendMessage);
                }

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

            var sourceFile = buildOperands.FirstOperand!;
            if (!File.Exists(sourceFile))
            {
                return Error(BuildCommandKernels.GetFileNotFoundMessage(sourceFile));
            }

            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var sourceProjectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);
            _ = ResolveCompilationBackend(buildOptions.BackendOption, sourceProjectConfig);
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
                result.PerfFacts.AotBlockers,
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

    private sealed record BuildCommandResult(int ExitCode, BuildPerfReportFacts PerfFacts)
    {
        public static BuildCommandResult Failure(int exitCode = 1, BuildPerfReportFacts? perfFacts = null)
            => new(exitCode, perfFacts ?? BuildPerfReportFacts.Empty);
    }

    private sealed record BuildPerfReportFacts(
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportAotBlocker> AotBlockers,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> AllocationSites,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> DelegateSites,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> BoxingSites,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> DispatchSites,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> ClosureCaptures,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> PoolSites,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> ResourceSites,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> BoundaryLeakSites,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> HotReadinessSites,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite> ImplicitTrapSites,
        IReadOnlyList<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportTrustedSite> TrustedSites)
    {
        public static BuildPerfReportFacts Empty { get; } = new(
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportAotBlocker>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportSite>(),
            Array.Empty<NSharpLang.Compiler.CodeIntelligence.OutputFormatter.PerfReportTrustedSite>());
    }

    private static BuildPerfReportFacts SafeCollectPerfFacts(Func<BuildPerfReportFacts> collect)
    {
        try
        {
            return collect();
        }
        catch
        {
            // The perf report is best-effort instrumentation; never fail the build over it.
            return BuildPerfReportFacts.Empty;
        }
    }

    /// <summary>
    /// Removes orphaned .g.cs files in obj/**/nsharp/ that no longer have
    /// a corresponding .nl source file. Prevents stale generated code from
    /// being compiled after source files are deleted.
    /// </summary>
    internal static void CleanStaleGeneratedFiles(string projectRoot)
    {
        var objDir = Path.Combine(projectRoot, "obj");
        if (!Directory.Exists(objDir))
            return;

        // Collect current .nl source files (relative paths, without extension)
        var nlRelativePaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var nlFile in Directory.GetFiles(projectRoot, "*.nl", SearchOption.AllDirectories))
        {
            var rel = Path.GetRelativePath(projectRoot, nlFile);
            if (ShouldSkipGeneratedSourcePath(rel))
                continue;

            // Strip .nl (or .tests.nl) extension to get the base name with relative dir
            var basePathLength = GetGeneratedSourceBasePathLength(rel);
            if (basePathLength < 0)
                continue;

            var basePath = rel[..basePathLength];
            nlRelativePaths.Add(basePath.Replace('\\', '/'));
        }

        // Find all nsharp/ output directories under obj/
        // Search for both "nsharp" and "NSharp" to handle case-sensitive filesystems (Linux)
        var nsharpDirCandidates = Directory.GetDirectories(objDir, "nsharp", SearchOption.AllDirectories)
            .Concat(Directory.GetDirectories(objDir, "NSharp", SearchOption.AllDirectories))
            .ToArray();
        var nsharpDirs = GeneratedOutputDirectoryDeduplicator.TryDeduplicate(
                nsharpDirCandidates,
                out var dogfoodNsharpDirs)
            ? dogfoodNsharpDirs
            : throw new InvalidOperationException("N# generated output directory deduplication kernel rejected the directories.");
        foreach (var nsharpDir in nsharpDirs)
        {
            if (!Directory.Exists(nsharpDir))
                continue;

            foreach (var gcsFile in Directory.GetFiles(nsharpDir, "*.g.cs", SearchOption.AllDirectories))
            {
                var relToNsharp = Path.GetRelativePath(nsharpDir, gcsFile).Replace('\\', '/');
                var basePathLength = GetGeneratedOutputBasePathLength(relToNsharp);
                var basePath = basePathLength >= 0 ? relToNsharp[..basePathLength] : relToNsharp;

                if (!nlRelativePaths.Contains(basePath))
                {
                    try { File.Delete(gcsFile); } catch { /* ignore cleanup errors */ }
                }
            }
        }
    }

    static int GetGeneratedSourceBasePathLength(string relativeSourcePath)
    {
        if (GeneratedOutputDirectoryDeduplicator.TryGetSourceBasePathLength(relativeSourcePath, out var basePathLength))
            return basePathLength;

        throw new InvalidOperationException("N# generated source base-path length kernel rejected the path.");
    }

    static bool ShouldSkipGeneratedSourcePath(string relativeSourcePath)
    {
        if (GeneratedOutputDirectoryDeduplicator.TryShouldSkipSourcePath(relativeSourcePath, out var shouldSkip))
            return shouldSkip;

        throw new InvalidOperationException("N# generated source skip kernel rejected the path.");
    }

    static int GetGeneratedOutputBasePathLength(string relativeGeneratedPath)
    {
        if (GeneratedOutputDirectoryDeduplicator.TryGetGeneratedOutputBasePathLength(relativeGeneratedPath, out var basePathLength))
            return basePathLength;

        throw new InvalidOperationException("N# generated output base-path length kernel rejected the path.");
    }

    static string CreateTempBuildDirectory()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nlc-build-{Guid.NewGuid():N}");
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
        var helpOptions = GetRunOptionSummary(args);
        if (helpOptions.ShowHelp)
        {
            Console.WriteLine(RunCommandKernels.GetHelpText());
            return 0;
        }

        // Extract --define/-d before operand detection so their values are never
        // mistaken for the source-file operand.
        var cliDefines = ExtractDefineFlags(ref args);
        var runOptions = GetRunOptionSummary(args);
        var backendOption = runOptions.BackendOption;
        var sourceFile = GetRunSourceOperand(args);

        try
        {
            if (sourceFile == null)
            {
                var projectRoot = Directory.GetCurrentDirectory();
                var currentProjectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
                var backend = ResolveCompilationBackend(backendOption, currentProjectConfig);
                if (backend != CompilationBackend.Il)
                {
                    throw new InvalidOperationException(CompilationBackendExtensions.RetiredTranspileBackendMessage);
                }

                return RunWithIlBackend(projectRoot, cliDefines);
            }

            if (!File.Exists(sourceFile))
            {
                return Error(RunCommandKernels.GetFileNotFoundMessage(sourceFile));
            }

            Console.WriteLine(RunCommandKernels.GetSourceStartingMessage(sourceFile));

            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var sourceProjectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);
            _ = ResolveCompilationBackend(backendOption, sourceProjectConfig);
            return RunSingleFileWithIlBackend(sourceFile, sourceProjectConfig, cliDefines);
        }
        catch (Exception ex)
        {
            return Error(RunCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    static int PublishCommand(string[] args)
    {
        var publishArguments = GetPublishArgumentSummary(args);
        if (publishArguments.ShowHelp)
        {
            Console.WriteLine(PublishCommandKernels.GetHelpText());
            return 0;
        }

        if (publishArguments.ValidationError != null)
        {
            return Error(publishArguments.ValidationError);
        }

        var projectRoot = Path.GetFullPath(publishArguments.ProjectOption ?? Directory.GetCurrentDirectory());
        var backendOption = publishArguments.BackendOption;

        try
        {
            Console.WriteLine(PublishCommandKernels.GetStartMessage(projectRoot));

            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return Error(PublishCommandKernels.GetMissingProjectFileMessage());
            }

            var config = ProjectFileParser.Parse(projectYmlPath);
            var backend = ResolveCompilationBackend(backendOption, config);
            if (backend != CompilationBackend.Il)
            {
                throw new InvalidOperationException(CompilationBackendExtensions.RetiredTranspileBackendMessage);
            }

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

            if (!string.IsNullOrWhiteSpace(runtime))
            {
                var currentRuntime = RuntimeInformation.RuntimeIdentifier;
                if (!string.Equals(runtime, currentRuntime, StringComparison.OrdinalIgnoreCase))
                {
                    return Error(PublishCommandKernels.GetCrossRuntimeUnsupportedMessage(runtime, currentRuntime));
                }
            }

            var publishDir = output != null
                ? Path.GetFullPath(output)
                : Path.Combine(projectRoot, "bin", configuration, config.TargetFramework, "publish");

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

            if (!string.IsNullOrWhiteSpace(runtime))
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
                Path.Combine(outputDirectory, $"{assemblyName}.cmd"),
                $"@echo off\r\ndotnet \"%~dp0{assemblyName}.dll\" %*\r\n");
            return;
        }

        var launcherPath = Path.Combine(outputDirectory, assemblyName);
        File.WriteAllText(launcherPath, $"""
#!/usr/bin/env sh
set -eu
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec dotnet "$DIR/{assemblyName}.dll" "$@"
""");
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

    internal static PublishArgumentSummary GetPublishArgumentSummary(string[] args)
        => PublishCommandKernels.GetArgumentSummary(args);

    static int NewCommand(string[] args)
    {
        var arguments = GetNewArgumentSummary(args);
        if (arguments.ShowHelp)
        {
            Console.WriteLine(NewCommandKernels.GetHelpText());
            return 0;
        }

        var projectName = arguments.FirstPositional;
        if (projectName == null)
        {
            return Error(NewCommandKernels.GetUsageMessage());
        }

        var requestedTemplate = arguments.TemplateOption;
        if (arguments.SecondPositional != null && NormalizeProjectTemplate(arguments.FirstPositional!) is { } positionalTemplate)
        {
            requestedTemplate = positionalTemplate;
            projectName = arguments.SecondPositional;
        }

        var systemsFlag = arguments.Systems;
        var template = ResolveProjectTemplate(requestedTemplate ?? "console", systemsFlag);
        if (template == null)
        {
            return Error(NewCommandKernels.GetInvalidTemplateMessage());
        }

        var projectDir = Path.Combine(Directory.GetCurrentDirectory(), projectName);

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
            foreach (var file in GetTemplateSourceFiles(template))
            {
                Console.WriteLine(NewCommandKernels.GetCreatedFileMessage(projectName, file));
            }

            Console.WriteLine();
            Console.WriteLine(NewCommandKernels.GetProjectShapeMessage());
            Console.WriteLine(NewCommandKernels.GetNextStepsIntroMessage(template));
            Console.WriteLine(NewCommandKernels.GetCdCommandMessage(projectName));
            if (template is "systems-cli" or "systems-lib")
            {
                Console.WriteLine(NewCommandKernels.GetSystemsReportCommandMessage());
                Console.WriteLine(NewCommandKernels.GetSystemsBuildCommandMessage());
            }
            else
            {
                Console.WriteLine(NewCommandKernels.GetBuildCommandMessage());
                if (template == "test")
                    Console.WriteLine(NewCommandKernels.GetTestCommandMessage());
                else if (template != "library")
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

    internal static NewArgumentSummary GetNewArgumentSummary(string[] args)
    {
        if (NewCommandKernels.TryGetArgumentSummary(args, out var summary))
            return summary;

        throw new InvalidOperationException("N# new argument summary kernel rejected the arguments.");
    }

    static string[] GetTemplateSourceFiles(string template)
    {
        var sourceFileKinds = GetTemplateSourceFileKinds(template);
        var sourceFiles = new string[sourceFileKinds.Length];
        for (var i = 0; i < sourceFileKinds.Length; i++)
            sourceFiles[i] = GetTemplateSourceFileName(sourceFileKinds[i]);

        return sourceFiles;
    }

    static NewTemplateSourceFileKind[] GetTemplateSourceFileKinds(string template)
    {
        if (NewCommandKernels.TryGetTemplateSourceFileKinds(template, out var dogfoodKinds))
            return dogfoodKinds;

        throw new InvalidOperationException("N# new template source manifest kernel rejected the template.");
    }

    static string GetTemplateSourceFileName(NewTemplateSourceFileKind sourceFileKind)
        => sourceFileKind switch
        {
            NewTemplateSourceFileKind.Program => "Program.nl",
            NewTemplateSourceFileKind.Calculator => "Calculator.nl",
            NewTemplateSourceFileKind.CalculatorTests => "Calculator.tests.nl",
            NewTemplateSourceFileKind.WebApiController => "Controllers/WeatherController.nl",
            NewTemplateSourceFileKind.SystemsTests => "Systems.tests.nl",
            NewTemplateSourceFileKind.PacketCore => "PacketCore.nl",
            NewTemplateSourceFileKind.PacketCoreTests => "PacketCore.tests.nl",
            _ => throw new ArgumentOutOfRangeException(nameof(sourceFileKind), sourceFileKind, "Unknown template source file kind."),
        };

    static string? NormalizeProjectTemplate(string value)
    {
        if (!NewCommandKernels.TryNormalizeTemplate(value, out var templateKind))
            throw new InvalidOperationException("N# new template normalization kernel rejected the template.");

        return GetProjectTemplateName(templateKind);
    }

    static string? ResolveProjectTemplate(string value, bool systems)
    {
        if (!NewCommandKernels.TryResolveTemplate(value, systems, out var templateKind))
            throw new InvalidOperationException("N# new template resolution kernel rejected the template.");

        return GetProjectTemplateName(templateKind);
    }

    static string? GetProjectTemplateName(NewProjectTemplateKind templateKind)
        => templateKind switch
        {
            NewProjectTemplateKind.Console => "console",
            NewProjectTemplateKind.Library => "library",
            NewProjectTemplateKind.Test => "test",
            NewProjectTemplateKind.WebApi => "webapi",
            NewProjectTemplateKind.SystemsCli => "systems-cli",
            NewProjectTemplateKind.SystemsLib => "systems-lib",
            _ => null,
        };

    static void WriteCanonicalProject(string projectDir, string projectName, string template)
    {
        File.WriteAllText(Path.Combine(projectDir, "project.yml"), GenerateProjectYaml(projectName, template));
        WriteSdkSupportFiles(projectDir);

        foreach (var sourceFileKind in GetTemplateSourceFileKinds(template))
            WriteTemplateSourceFile(projectDir, template, sourceFileKind);
    }

    static void WriteTemplateSourceFile(
        string projectDir,
        string template,
        NewTemplateSourceFileKind sourceFileKind)
    {
        var fileName = GetTemplateSourceFileName(sourceFileKind);
        var path = Path.Combine(projectDir, fileName);
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory))
            Directory.CreateDirectory(directory);

        File.WriteAllText(path, GetTemplateSourceText(template, sourceFileKind));
    }

    static void WriteSdkSupportFiles(string projectDir)
    {
        File.WriteAllText(Path.Combine(projectDir, "global.json"), NewCommandKernels.GetGlobalJsonText());
        File.WriteAllText(
            Path.Combine(projectDir, "NuGet.config"),
            NewCommandKernels.GetNuGetConfigText(NSharpInstallRoot.ProjectFeedValue()));
    }

    static string GenerateProjectYaml(string projectName, string template)
        => NewCommandKernels.GetProjectYamlText(projectName, template);

    static string GetTemplateSourceText(string template, NewTemplateSourceFileKind sourceFileKind)
        => NewCommandKernels.GetTemplateSourceText(template, sourceFileKind);

    static int TestCommand(string[] args)
    {
        var testOptions = GetTestOptionSummary(args);
        if (testOptions.ShowHelp)
        {
            Console.WriteLine(TestCommandKernels.GetHelpText());
            return 0;
        }

        var projectRoot = testOptions.ProjectOption ?? Directory.GetCurrentDirectory();
        projectRoot = Path.GetFullPath(projectRoot);
        var outputMode = GetTestOutputMode(testOptions.JsonOutput);

        // Parse timeout to milliseconds
        int? timeoutMs = null;
        if (testOptions.Timeout != null)
        {
            timeoutMs = ParseDurationToMs(testOptions.Timeout);
            if (timeoutMs == null)
            {
                var message = TestCommandKernels.GetInvalidTimeoutMessage(testOptions.Timeout);
                if (outputMode == TestOutputModeKind.Json)
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
            if (outputMode == TestOutputModeKind.Text) Console.WriteLine(TestCommandKernels.GetProjectStartMessage(projectRoot));

            if (testOptions.CollectCoverage || testOptions.CoverageReport)
            {
                var message = TestCommandKernels.GetCoverageUnsupportedMessage();
                if (outputMode == TestOutputModeKind.Json)
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
                if (outputMode == TestOutputModeKind.Json)
                {
                    OutputNativeTestJson(projectRoot, true, Array.Empty<NativeTestResult>(), summary: new NativeTestSummary(true, 0, 0, 0, 0));
                    return 0;
                }
                Console.WriteLine(TestCommandKernels.GetNoTestFilesMessage());
                return 0;
            }

            if (outputMode == TestOutputModeKind.Text) Console.WriteLine(TestCommandKernels.GetFoundTestFilesMessage(testFiles.Length));

            var projectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
            _ = ResolveCompilationBackend(testOptions.BackendOption, projectConfig);

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
            if (outputMode == TestOutputModeKind.Text)
                Console.WriteLine(TestCommandKernels.GetFailedElapsedMessage(FormatElapsed(sw.Elapsed)));
            if (outputMode == TestOutputModeKind.Json) { OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), ex.Message, summary: NativeTestSummary.EmptyFailure); return 1; }
            return Error(TestCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    static int FormatCommand(string[] args)
    {
        var formatOptions = GetFormatOptionSummary(args);
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
            var projectRoot = Path.GetFullPath(formatOptions.ProjectOption ?? Directory.GetCurrentDirectory());
            var positionalFiles = GetPositionalArgs(args, "--project");

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

                return verifyOnly && source != formatted ? 1 : 0;
            }

            string[] files;
            if (positionalFiles.Length == 0)
            {
                files = EnumerateFormatFiles(projectRoot).ToArray();
            }
            else
            {
                files = positionalFiles
                    .Select(file => Path.GetFullPath(Path.IsPathRooted(file) ? file : Path.Combine(projectRoot, file)))
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
                    var relativePath = NormalizePath(Path.GetRelativePath(projectRoot, file));

                    if (!string.Equals(source, formatted, StringComparison.Ordinal))
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

            if (failed)
                return 1;

            if (verifyOnly && filesNeedingFormatting.Count > 0)
            {
                Console.Error.WriteLine(FormatCommandKernels.GetCheckFailedHeader(filesNeedingFormatting.Count));
                foreach (var file in filesNeedingFormatting)
                    Console.Error.WriteLine(FormatCommandKernels.GetCheckFailedPathLine(file));
                return 1;
            }

            if (diffOnly)
            {
                if (filesNeedingFormatting.Count == 0)
                    Console.WriteLine(FormatCommandKernels.GetAllFilesFormattedMessage());
                return 0;
            }

            if (verifyOnly)
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
                NormalizePath(Path.GetRelativePath(projectRoot, file)),
                string.Join(", ", parseResult.Errors.Select(e => e.Message))));
        }

        var fileDir = Path.GetDirectoryName(Path.GetFullPath(file)) ?? projectRoot;
        var config = FormatterConfig.FromEditorConfig(fileDir);
        var formatter = new Formatter(config);
        var result = formatter.FormatSafe(source, parseResult.CompilationUnit!, lexer.Comments, file);

        var relativePath = NormalizePath(Path.GetRelativePath(projectRoot, file));
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
                if (!ShouldSkipDiscoveredDirectory(childDirectory))
                    pending.Push(childDirectory);
            }

            foreach (var file in childFiles)
            {
                if (ShouldFormatDiscoveredFile(projectRoot, file))
                {
                    yield return file;
                }
            }
        }
    }

    static bool ShouldSkipDiscoveredDirectory(string directory)
    {
        var name = Path.GetFileName(directory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (FormatCommandKernels.TryShouldSkipDiscoveredDirectoryName(name, out var shouldSkip))
            return shouldSkip;

        throw new InvalidOperationException("N# format directory pruning kernel rejected the directory name.");
    }

    static bool ShouldFormatDiscoveredFile(string projectRoot, string file)
    {
        var relativePath = NormalizePath(Path.GetRelativePath(projectRoot, file));
        if (FormatCommandKernels.TryShouldFormatDiscoveredPath(relativePath, out var shouldFormat))
            return shouldFormat;

        throw new InvalidOperationException("N# format discovery path kernel rejected the path.");
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
        if (DefineArgumentKernels.TryExtract(args, out var extraction))
        {
            args = extraction.RemainingArgs;
            return extraction.Defines.ToList();
        }

        throw new InvalidOperationException("N# define argument extraction kernel rejected the arguments.");
    }

    static string[] GetPositionalArgs(string[] args, params string[] optionsWithValues)
    {
        if (PositionalArgumentKernels.TryGetArgs(args, optionsWithValues, out var positionalArgs))
            return positionalArgs;

        throw new InvalidOperationException("N# positional argument kernel rejected the arguments.");
    }

    static string? GetFirstPositionalArg(string[] args, string[] optionsWithValues)
    {
        if (NewCommandKernels.TryGetProjectNameOperand(args, optionsWithValues, out var positional))
            return positional;

        throw new InvalidOperationException("N# first positional argument kernel rejected the arguments.");
    }

    private readonly record struct BuildOperandSummary(int Count, string? FirstOperand);

    static BuildOptionSummary GetBuildOptionSummary(string[] args)
        => BuildCommandKernels.GetOptionSummary(args);

    static TestOptionSummary GetTestOptionSummary(string[] args)
        => TestCommandKernels.GetOptionSummary(args);

    internal static TestOutputModeKind GetTestOutputMode(bool json)
        => TestCommandKernels.GetOutputMode(json);

    static BuildOperandSummary GetBuildOperandSummary(string[] args)
    {
        if (BuildCommandKernels.TryGetOperandSummary(args, out var count, out var firstOperandIndex))
        {
            return new BuildOperandSummary(
                count,
                count > 0 ? args[firstOperandIndex] : null);
        }

        throw new InvalidOperationException("N# build operand summary kernel rejected the arguments.");
    }

    internal static string? GetRunSourceOperand(string[] args)
    {
        if (RunCommandKernels.TryGetSourceOperand(args, out var operand))
            return operand;

        throw new InvalidOperationException("N# run source operand kernel rejected the arguments.");
    }

    internal static RunOptionSummary GetRunOptionSummary(string[] args)
        => RunCommandKernels.GetOptionSummary(args);

    internal static FormatOptionSummary GetFormatOptionSummary(string[] args)
        => FormatCommandKernels.GetOptionSummary(args);

    static int? ParseDurationToMs(string duration)
        => TestCommandKernels.GetDurationMilliseconds(duration);

    static string NormalizePath(string path) => path.Replace('\\', '/');

    static string FormatElapsed(TimeSpan elapsed)
    {
        if (elapsed.TotalMinutes >= 1)
            return $"{(int)elapsed.TotalMinutes}m {elapsed.Seconds:D2}s";
        return $"{elapsed.TotalSeconds:F1}s";
    }

    internal static string GetVersion()
    {
        return typeof(Program).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion
            ?? typeof(Program).Assembly.GetName().Version?.ToString()
            ?? "unknown";
    }

    static int ShowVersion()
    {
        Console.WriteLine(ProgramCommandKernels.GetVersionText(GetVersion()));
        return 0;
    }

    static int ShowHelp()
    {
        Console.WriteLine(ProgramCommandKernels.GetHelpText(GetVersion()));

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(message));
        return 1;
    }
}

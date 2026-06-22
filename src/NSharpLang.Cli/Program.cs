using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security;
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
            ProgramCommandKind.Transpile => Error("The 'transpile' command has been removed. Use 'nlc export csharp' instead."),
            _ => Error($"Unknown command: {GetCommandNameForError(args)}. Run 'nlc help' to see available commands.")
        };
    }

    internal static ProgramCommandKind GetCommandKind(string[] args)
        => ProgramCommandKernels.TryGetCommandKind(args, out var commandKind)
            ? commandKind
            : GetCommandKindWithCSharp(args);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product top-level command parsing routes through ProgramCommandKernels.
    private static ProgramCommandKind GetCommandKindWithCSharp(string[] args)
    {
        if (args.Length == 0)
            return ProgramCommandKind.Help;

        var raw = args[0];
        if (raw == "-V")
            return ProgramCommandKind.Version;

        return raw.ToLower() switch
        {
            "build" => ProgramCommandKind.Build,
            "run" => ProgramCommandKind.Run,
            "publish" => ProgramCommandKind.Publish,
            "new" => ProgramCommandKind.New,
            "test" => ProgramCommandKind.Test,
            "format" => ProgramCommandKind.Format,
            "lint" => ProgramCommandKind.Lint,
            "restore" => ProgramCommandKind.Restore,
            "clean" => ProgramCommandKind.Clean,
            "watch" => ProgramCommandKind.Watch,
            "doc" => ProgramCommandKind.Doc,
            "completion" => ProgramCommandKind.Completion,
            "check" => ProgramCommandKind.Check,
            "fix" => ProgramCommandKind.Fix,
            "query" => ProgramCommandKind.Query,
            "daemon" => ProgramCommandKind.Daemon,
            "add" => ProgramCommandKind.Add,
            "tidy" => ProgramCommandKind.Tidy,
            "remove" => ProgramCommandKind.Remove,
            "update" => ProgramCommandKind.Update,
            "init" => ProgramCommandKind.Init,
            "env" => ProgramCommandKind.Env,
            "doctor" => ProgramCommandKind.Doctor,
            "tree" => ProgramCommandKind.Tree,
            "audit" => ProgramCommandKind.Audit,
            "pack" => ProgramCommandKind.Pack,
            "export" => ProgramCommandKind.Export,
            "help" or "--help" or "-h" => ProgramCommandKind.Help,
            "--version" => ProgramCommandKind.Version,
            "transpile" => ProgramCommandKind.Transpile,
            _ => ProgramCommandKind.Unknown
        };
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
            : nsharpDirCandidates.Distinct(StringComparer.Ordinal);
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
        => GeneratedOutputDirectoryDeduplicator.TryGetSourceBasePathLength(relativeSourcePath, out var basePathLength)
            ? basePathLength
            : GetGeneratedSourceBasePathLengthWithCSharp(relativeSourcePath);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product stale-generated source base-path derivation routes through GeneratedOutputDirectoryDeduplicator.
    static int GetGeneratedSourceBasePathLengthWithCSharp(string relativeSourcePath)
    {
        if (relativeSourcePath.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase))
            return relativeSourcePath.Length - ".tests.nl".Length;

        if (relativeSourcePath.EndsWith(".nl", StringComparison.OrdinalIgnoreCase))
            return relativeSourcePath.Length - ".nl".Length;

        return -1;
    }

    static bool ShouldSkipGeneratedSourcePath(string relativeSourcePath)
        => GeneratedOutputDirectoryDeduplicator.TryShouldSkipSourcePath(relativeSourcePath, out var shouldSkip)
            ? shouldSkip
            : ShouldSkipGeneratedSourcePathWithCSharp(relativeSourcePath);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product stale-generated source path pruning routes through GeneratedOutputDirectoryDeduplicator.
    static bool ShouldSkipGeneratedSourcePathWithCSharp(string relativeSourcePath)
        => relativeSourcePath.StartsWith("obj" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
           relativeSourcePath.StartsWith("bin" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);

    static int GetGeneratedOutputBasePathLength(string relativeGeneratedPath)
        => GeneratedOutputDirectoryDeduplicator.TryGetGeneratedOutputBasePathLength(relativeGeneratedPath, out var basePathLength)
            ? basePathLength
            : GetGeneratedOutputBasePathLengthWithCSharp(relativeGeneratedPath);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product stale-generated output base-path derivation routes through GeneratedOutputDirectoryDeduplicator.
    static int GetGeneratedOutputBasePathLengthWithCSharp(string relativeGeneratedPath)
    {
        if (relativeGeneratedPath.EndsWith(".g.cs", StringComparison.OrdinalIgnoreCase))
            return relativeGeneratedPath.Length - ".g.cs".Length;

        return -1;
    }

    static string FindRepoRoot(string startPath)
    {
        var current = new DirectoryInfo(startPath);
        while (current != null)
        {
            if (Directory.Exists(Path.Combine(current.FullName, "src/NSharpLang.Sdk")))
            {
                return current.FullName;
            }
            current = current.Parent;
        }
        // Fallback: assume we're in the repo
        return startPath;
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
            Console.WriteLine(@"N# Publish

Usage: nlc publish [options]

Package the project for distribution.

Options:
  --project <dir>         Project root directory (default: current directory)
  --backend <mode>        Compilation backend: il
  --configuration <cfg>   Build configuration (default: Release)
  --output <dir>          Output directory for published files
  --runtime <rid>         Current host runtime only; adds a framework-dependent launcher
  --self-contained        Planned; currently exits with guidance
  --aot                   Analysis-only: verify Native AOT safety and annotate public APIs
  --help, -h              Show this help text

Supported publish shapes:
  - Portable framework-dependent: nlc publish --output ./dist
  - Current-runtime launcher: nlc publish --runtime <current-rid>

Native AOT (--aot):
  Analysis-only this release. Fails the publish on any AOT blocker (reflection,
  dynamic code, runtime generics, expression trees) and stamps public APIs with
  [RequiresUnreferencedCode]/[RequiresDynamicCode]. It does NOT emit a native image yet.

Unsupported today:
  - Cross-runtime publishing, e.g. publishing linux-x64 from osx-arm64
  - Self-contained apphost/runtime bundles
  - Native AOT image generation

Examples:
  nlc publish
  nlc publish --backend il --output ./dist
  nlc publish --configuration Release
  nlc publish --runtime <current-rid> --output ./dist
  nlc publish --aot
  nlc publish --output ./dist

Exit codes:
  0  Publish succeeded
  1  Publish failed");
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

    private static string? ValidatePublishArguments(string[] args)
    {
        var optionsWithValues = new HashSet<string>(StringComparer.Ordinal)
        {
            "--project",
            "--backend",
            "--configuration",
            "-c",
            "--output",
            "-o",
            "--runtime",
            "-r"
        };
        var switchOptions = new HashSet<string>(StringComparer.Ordinal)
        {
            "--self-contained",
            "--aot"
        };

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (optionsWithValues.Contains(arg))
            {
                if (i + 1 >= args.Length || args[i + 1].StartsWith("-", StringComparison.Ordinal))
                {
                    return $"Option '{arg}' requires a value.";
                }

                i++;
                continue;
            }

            if (switchOptions.Contains(arg))
            {
                continue;
            }

            if (arg is "--target" or "--target-platform")
            {
                return "Target-platform publishing is expressed as --runtime <rid>, and nlc publish does not support cross-runtime publishing yet.";
            }

            if (arg.StartsWith("-", StringComparison.Ordinal))
            {
                return $"Unknown publish option '{arg}'. Run 'nlc publish --help' for supported options.";
            }

            return $"Unexpected publish argument '{arg}'. Run 'nlc publish --help' for usage.";
        }

        return null;
    }

    internal static PublishArgumentSummary GetPublishArgumentSummary(string[] args)
    {
        if (PublishCommandKernels.TryGetArgumentSummary(args, out var summary))
            return summary;

        // Stage 6 C#-surface-shrink: fallback/oracle only; product publish option parsing routes through PublishCommandKernels.
        return new PublishArgumentSummary(
            ValidatePublishArguments(args),
            GetOptionValue(args, "--project"),
            GetOptionValue(args, "--backend"),
            GetOptionValue(args, "--configuration") ?? GetOptionValue(args, "-c") ?? "Release",
            GetOptionValue(args, "--output") ?? GetOptionValue(args, "-o"),
            GetOptionValue(args, "--runtime") ?? GetOptionValue(args, "-r"),
            args.Contains("--self-contained"),
            args.Contains("--aot"),
            args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"));
    }

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
        => NewCommandKernels.TryGetArgumentSummary(args, out var summary)
            ? summary
            : GetNewArgumentSummaryWithCSharp(args);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product new argument parsing routes through NewCommandKernels.
    private static NewArgumentSummary GetNewArgumentSummaryWithCSharp(string[] args)
    {
        var positional = GetPositionalArgsWithCSharp(args, "--template", "--type");
        return new NewArgumentSummary(
            GetFirstPositionalArgWithCSharp(args, NewProjectOptionsWithValues),
            positional.Length >= 2 ? positional[1] : null,
            GetOptionValue(args, "--template") ?? GetOptionValue(args, "--type"),
            args.Contains("--systems"),
            args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"));
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
        => NewCommandKernels.TryGetTemplateSourceFileKinds(template, out var dogfoodKinds)
            ? dogfoodKinds
            : GetTemplateSourceFileKindsWithCSharp(template);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product new-template source manifests route through NewCommandKernels.
    static NewTemplateSourceFileKind[] GetTemplateSourceFileKindsWithCSharp(string template) => template switch
    {
        "console" => new[] { NewTemplateSourceFileKind.Program },
        "library" => new[] { NewTemplateSourceFileKind.Calculator },
        "test" => new[] { NewTemplateSourceFileKind.Calculator, NewTemplateSourceFileKind.CalculatorTests },
        "webapi" => new[] { NewTemplateSourceFileKind.Program, NewTemplateSourceFileKind.WebApiController },
        "systems-cli" => new[] { NewTemplateSourceFileKind.Program, NewTemplateSourceFileKind.SystemsTests },
        "systems-lib" => new[] { NewTemplateSourceFileKind.PacketCore, NewTemplateSourceFileKind.PacketCoreTests },
        _ => Array.Empty<NewTemplateSourceFileKind>(),
    };

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
        var templateKind = NewCommandKernels.TryNormalizeTemplate(value, out var dogfoodTemplateKind)
            ? dogfoodTemplateKind
            : NormalizeProjectTemplateWithCSharp(value);

        return GetProjectTemplateName(templateKind);
    }

    static string? ResolveProjectTemplate(string value, bool systems)
    {
        var templateKind = NewCommandKernels.TryResolveTemplate(value, systems, out var dogfoodTemplateKind)
            ? dogfoodTemplateKind
            : ResolveProjectTemplateWithCSharp(value, systems);

        return GetProjectTemplateName(templateKind);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product new --systems effective-template selection routes through NewCommandKernels.
    static NewProjectTemplateKind ResolveProjectTemplateWithCSharp(string value, bool systems)
    {
        var templateKind = NormalizeProjectTemplateWithCSharp(value);
        if (systems && templateKind == NewProjectTemplateKind.Console)
            return NewProjectTemplateKind.SystemsCli;
        if (systems && templateKind == NewProjectTemplateKind.Library)
            return NewProjectTemplateKind.SystemsLib;

        return templateKind;
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product new-template normalization routes through NewCommandKernels.
    static NewProjectTemplateKind NormalizeProjectTemplateWithCSharp(string value)
    {
        return value.Trim().ToLowerInvariant() switch
        {
            "console" or "exe" or "app" => NewProjectTemplateKind.Console,
            "library" or "lib" => NewProjectTemplateKind.Library,
            "test" or "tests" => NewProjectTemplateKind.Test,
            "webapi" or "web-api" or "web" => NewProjectTemplateKind.WebApi,
            "systems-cli" or "systems-console" or "systems" => NewProjectTemplateKind.SystemsCli,
            "systems-lib" or "systems-library" => NewProjectTemplateKind.SystemsLib,
            _ => NewProjectTemplateKind.Unknown,
        };
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
        switch (sourceFileKind)
        {
            case NewTemplateSourceFileKind.Program:
                var programSource = template switch
                {
                    "webapi" => WebApiProgramSource,
                    "systems-cli" => SystemsCliSource,
                    _ => ConsoleProgramSource,
                };
                File.WriteAllText(Path.Combine(projectDir, "Program.nl"), programSource);
                return;
            case NewTemplateSourceFileKind.Calculator:
                File.WriteAllText(Path.Combine(projectDir, "Calculator.nl"), CalculatorSource);
                return;
            case NewTemplateSourceFileKind.CalculatorTests:
                File.WriteAllText(Path.Combine(projectDir, "Calculator.tests.nl"), CalculatorTestsSource);
                return;
            case NewTemplateSourceFileKind.WebApiController:
                Directory.CreateDirectory(Path.Combine(projectDir, "Controllers"));
                File.WriteAllText(Path.Combine(projectDir, "Controllers", "WeatherController.nl"), WebApiControllerSource);
                return;
            case NewTemplateSourceFileKind.SystemsTests:
                File.WriteAllText(Path.Combine(projectDir, "Systems.tests.nl"), SystemsTestsSource);
                return;
            case NewTemplateSourceFileKind.PacketCore:
                File.WriteAllText(Path.Combine(projectDir, "PacketCore.nl"), SystemsLibrarySource);
                return;
            case NewTemplateSourceFileKind.PacketCoreTests:
                File.WriteAllText(Path.Combine(projectDir, "PacketCore.tests.nl"), SystemsTestsSource);
                return;
            default:
                throw new ArgumentOutOfRangeException(nameof(sourceFileKind), sourceFileKind, "Unknown template source file kind.");
        }
    }

    static void WriteSdkSupportFiles(string projectDir)
    {
        File.WriteAllText(Path.Combine(projectDir, "global.json"), GlobalJsonContent);
        File.WriteAllText(Path.Combine(projectDir, "NuGet.config"), BuildNuGetConfigContent());
    }

    static string GenerateProjectYaml(string projectName, string template)
    {
        return template switch
        {
            "library" or "test" => $@"name: {projectName}
version: 1.0.0
backend: il
outputType: library
targetFramework: net10.0

# Test framework: xunit (default) or nunit
# testFramework: xunit

language:
  asyncDefaultType: ValueTask
",
            "webapi" => $@"name: {projectName}
version: 1.0.0
entry: Program.nl
backend: il
outputType: exe
targetFramework: net10.0
sdk: Microsoft.NET.Sdk.Web

dependencies:
  - framework: Microsoft.AspNetCore.App
  - nuget: Swashbuckle.AspNetCore
    version: 7.2.0
  - nuget: Microsoft.AspNetCore.OpenApi
    version: 9.0.0

language:
  asyncDefaultType: ValueTask
",
            "systems-cli" => GenerateSystemsProjectYaml(projectName, outputType: "exe", entry: "Program.nl"),
            "systems-lib" => GenerateSystemsProjectYaml(projectName, outputType: "library", entry: null),
            _ => ProjectFileParser.GenerateTemplate(projectName),
        };
    }

    static string GenerateSystemsProjectYaml(string projectName, string outputType, string? entry)
    {
        var entryLine = entry == null ? "" : $"entry: {entry}\n";
        return $@"name: {projectName}
version: 1.0.0
{entryLine}backend: il
outputType: {outputType}
targetFramework: net10.0

language:
  profile: systems
  asyncDefaultType: ValueTask
  systems:
    mode: strict
    unknownExternalCalls: warn
    aotTarget: nativeaot
    stackBudgetBytes: 4096
    warmup:
      - Warmup
";
    }

    const string GlobalJsonContent = @"{
  ""sdk"": {
    ""version"": ""10.0.100"",
    ""rollForward"": ""latestFeature""
  },
  ""msbuild-sdks"": {
    ""NSharpLang.Sdk"": ""0.1.0""
  }
}
";

    // The nsharp-local feed is resolved from the running CLI's install root so
    // projects created from a custom NSHARP_INSTALL_DIR install restore without
    // manual edits; default development builds keep the portable %HOME% literal.
    static string BuildNuGetConfigContent() => $@"<?xml version=""1.0"" encoding=""utf-8""?>
<configuration>
  <packageSources>
    <clear />
    <add key=""nuget.org"" value=""https://api.nuget.org/v3/index.json"" />
    <add key=""nsharp-local"" value=""{SecurityElement.Escape(NSharpInstallRoot.ProjectFeedValue())}"" />
  </packageSources>
</configuration>
";

    const string ConsoleProgramSource = @"func main() {
    print ""Hello, N#!""
}
";

    const string CalculatorSource = @"class Calculator {
    static func Add(a: int, b: int): int {
        return a + b
    }

    static func Subtract(a: int, b: int): int {
        return a - b
    }
}
";

    const string CalculatorTestsSource = @"test ""adds two numbers"" {
    result := Calculator.Add(2, 3)
    assert result == 5
}

test ""subtracts two numbers"" {
    result := Calculator.Subtract(7, 4)
    assert result == 3
}
";

    const string WebApiProgramSource = @"import Microsoft.AspNetCore.Builder
import Microsoft.Extensions.DependencyInjection

func main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)

    builder.Services.AddControllers()
    builder.Services.AddEndpointsApiExplorer()
    builder.Services.AddSwaggerGen()

    app := builder.Build()

    app.UseSwagger()
    app.UseSwaggerUI()
    app.UseHttpsRedirection()
    app.UseAuthorization()
    app.MapControllers()

    app.Run()
}
";

    const string WebApiControllerSource = @"import Microsoft.AspNetCore.Mvc

[ApiController]
[Route(""api/weather"")]
class WeatherController: ControllerBase {
    [HttpGet]
    func Get(): IActionResult {
        data := [""Sunny"", ""Cloudy"", ""Rainy""]
        return Ok(data)
    }

    [HttpGet(""{id}"")]
    func GetById([FromRoute] id: int): IActionResult {
        return Ok(id)
    }

    [HttpPost]
    func Create([FromBody] request: CreateWeatherRequest): IActionResult {
        return Ok(request)
    }
}

class CreateWeatherRequest {
    Summary: string
    TemperatureC: int
}
";

    const string SystemsCliSource = @"namespace SystemsTemplate

import System
import System.Buffers.Binary

enum ParseError {
    Short
}

[hot]
func ParseLength(buf: ReadOnlySpan<byte>): Result<uint, ParseError> {
    if buf.Length < 4 {
        return Err(ParseError.Short)
    }

    return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))
}

[boundary]
func Run(): Result<int, ParseError> {
    allow(alloc, reason: ""CLI startup allocates outside the hot parser"") {
        print ""Systems N# template""
    }
    return Ok(0)
}

func Warmup(): void {
}

func main(): void {
    _ := Run()
}
";

    const string SystemsLibrarySource = @"namespace SystemsTemplate

import System
import System.Buffers.Binary

enum ParseError {
    Short
}

[hot]
public func ParseLength(buf: ReadOnlySpan<byte>): Result<uint, ParseError> {
    if buf.Length < 4 {
        return Err(ParseError.Short)
    }

    return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))
}

[boundary]
public func AdaptPacket(bytes: byte[]): Result<uint, ParseError> {
    return ParseLength(bytes.AsSpan())
}

public func Warmup(): void {
}
";

    const string SystemsTestsSource = @"test ""systems smoke"" {
    assert true
}
";

    static int TestCommand(string[] args)
    {
        var testOptions = GetTestOptionSummary(args);
        if (testOptions.ShowHelp)
        {
            Console.WriteLine(@"N# Test

Usage: nlc test [options]

Run `.tests.nl` suites through the IL compilation backend.

Options:
  --project <dir>       Project root directory (default: current directory)
  --backend <mode>      Compilation backend: il
  --filter <name>       Run only tests whose display name or fully-qualified name matches
  --verbose             Show individual test results
  --json                Output results as structured JSON (schemaVersion 1 envelope)
  --timeout <duration>  Test timeout per assembly (e.g., 30s, 5m, 1h). Default: no timeout
  --no-cache            Force clean rebuild before running tests (bypass incremental build)
  --coverage            Planned; currently exits with unsupported-feature guidance
  --coverage-report     Planned; currently exits with unsupported-feature guidance
  --help, -h            Show this help text

The test framework is configured in project.yml via the `testFramework` field.
Supported values: xunit (default), nunit

Coverage collection is not available in the native nlc test runner yet.
When --coverage or --coverage-report is requested, nlc exits 1 and emits
a structured JSON error if --json was also requested.

Examples:
  nlc test
  nlc test --backend il
  nlc test --filter AddPerson
  nlc test --project examples/16-task-cli --verbose
  nlc test --json

Exit codes:
  0  Tests passed
  1  Compilation or test execution failed");
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
                var message = $"Invalid timeout format '{testOptions.Timeout}'. Expected a duration like 30s, 5m, or 1h.";
                if (outputMode == TestOutputModeKind.Json)
                {
                    OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), message);
                    return 1;
                }

                return Error(message);
            }
        }

        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            if (outputMode == TestOutputModeKind.Text) Console.WriteLine($"Testing project in {projectRoot}...");

            if (testOptions.CollectCoverage || testOptions.CoverageReport)
            {
                if (outputMode == TestOutputModeKind.Json)
                {
                    OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), CoverageUnsupportedMessage);
                    return 1;
                }

                return Error(CoverageUnsupportedMessage);
            }

            // Find all .tests.nl files
            var testFiles = Directory.GetFiles(projectRoot, "*.tests.nl", SearchOption.AllDirectories);

            if (testFiles.Length == 0)
            {
                if (outputMode == TestOutputModeKind.Json)
                {
                    OutputNativeTestJson(projectRoot, true, Array.Empty<NativeTestResult>());
                    return 0;
                }
                Console.WriteLine("No test files (*.tests.nl) found.");
                return 0;
            }

            if (outputMode == TestOutputModeKind.Text) Console.WriteLine($"Found {testFiles.Length} test file(s)");

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
            if (outputMode == TestOutputModeKind.Text) Console.WriteLine($"  Tests failed in {FormatElapsed(sw.Elapsed)}");
            if (outputMode == TestOutputModeKind.Json) { OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), ex.Message); return 1; }
            return Error($"Test failed: {ex.Message}");
        }
    }

    static int FormatCommand(string[] args)
    {
        var formatOptions = GetFormatOptionSummary(args);
        if (formatOptions.ShowHelp)
        {
            Console.WriteLine(@"N# Format

Usage: nlc format [options] [files...]

Format N# source files with the canonical formatter.

Options:
  --project <dir>         Project root directory (default: current directory)
  --check                 Exit with code 1 if any file needs formatting
  --verify-no-changes     Back-compat alias for --check
  --diff                  Print unified diffs instead of writing files
  --stdin                 Read source from stdin and write the formatted result to stdout
  --help, -h              Show this help text

Examples:
  nlc format
  nlc format --check
  nlc format --diff Program.nl
  nlc format --stdin < Program.nl

Exit codes:
  0  Formatting succeeded
  1  Formatting failed or --check found unformatted files");
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
                Console.Error.WriteLine("Cannot combine --stdin with file arguments.");
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
                Console.WriteLine("No .nl files found to format.");
                return 0;
            }

            var formattedCount = 0;
            var filesNeedingFormatting = new List<string>();
            var failed = false;

            foreach (var file in files)
            {
                if (!File.Exists(file))
                {
                    Console.Error.WriteLine($"File not found: {file}");
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
                    Console.Error.WriteLine($"Error formatting {file}: {ex.Message}");
                    failed = true;
                }
            }

            if (failed)
                return 1;

            if (verifyOnly && filesNeedingFormatting.Count > 0)
            {
                Console.Error.WriteLine($"Formatting check failed for {filesNeedingFormatting.Count} file(s):");
                foreach (var file in filesNeedingFormatting)
                    Console.Error.WriteLine($"  {file}");
                return 1;
            }

            if (diffOnly)
            {
                if (filesNeedingFormatting.Count == 0)
                    Console.WriteLine("All files are properly formatted.");
                return 0;
            }

            if (verifyOnly)
            {
                Console.WriteLine("All files are properly formatted.");
                return 0;
            }

            Console.WriteLine($"Formatted {formattedCount} file(s).");
            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Format failed: {ex.Message}");
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
            throw new Exception($"Parse errors in {NormalizePath(Path.GetRelativePath(projectRoot, file))}: {string.Join(", ", parseResult.Errors.Select(e => e.Message))}");
        }

        var fileDir = Path.GetDirectoryName(Path.GetFullPath(file)) ?? projectRoot;
        var config = FormatterConfig.FromEditorConfig(fileDir);
        var formatter = new Formatter(config);
        var result = formatter.FormatSafe(source, parseResult.CompilationUnit!, lexer.Comments, file);

        foreach (var warning in result.Warnings)
        {
            Console.Error.WriteLine($"Warning [{NormalizePath(Path.GetRelativePath(projectRoot, file))}]: {warning}");
        }

        if (!result.Success)
        {
            throw new Exception($"Formatter safety check failed: {string.Join("; ", result.Warnings)}");
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

        return ShouldSkipDiscoveredDirectoryNameWithCSharp(name);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product format directory
    // traversal pruning routes through FormatCommandKernels.
    static bool ShouldSkipDiscoveredDirectoryNameWithCSharp(string name)
    {
        return name.Equals(".git", StringComparison.OrdinalIgnoreCase)
            || name.Equals(".hg", StringComparison.OrdinalIgnoreCase)
            || name.Equals(".svn", StringComparison.OrdinalIgnoreCase)
            || name.Equals(".worktrees", StringComparison.OrdinalIgnoreCase)
            || name.Equals(".hermes", StringComparison.OrdinalIgnoreCase)
            || name.Equals(".nlc", StringComparison.OrdinalIgnoreCase)
            || name.Equals("bin", StringComparison.OrdinalIgnoreCase)
            || name.Equals("obj", StringComparison.OrdinalIgnoreCase)
            || name.Equals("node_modules", StringComparison.OrdinalIgnoreCase);
    }

    static bool ShouldFormatDiscoveredFile(string projectRoot, string file)
    {
        var relativePath = NormalizePath(Path.GetRelativePath(projectRoot, file));
        if (FormatCommandKernels.TryShouldFormatDiscoveredPath(relativePath, out var shouldFormat))
            return shouldFormat;

        return ShouldFormatDiscoveredPathWithCSharp(relativePath);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product discovery routes through FormatCommandKernels.
    static bool ShouldFormatDiscoveredPathWithCSharp(string relativePath)
    {
        if (relativePath.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase))
            return false;

        var segments = relativePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Any(segment => segment.Equals(".git", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".hg", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".svn", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".worktrees", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".hermes", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".nlc", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("bin", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("obj", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("node_modules", StringComparison.OrdinalIgnoreCase)))
            return false;

        for (var i = 0; i <= segments.Length - 2; i++)
        {
            var isFixtureRoot = string.Equals(segments[i], "test", StringComparison.OrdinalIgnoreCase)
                || string.Equals(segments[i], "tests", StringComparison.OrdinalIgnoreCase);
            if (isFixtureRoot && string.Equals(segments[i + 1], "fixtures", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        return true;
    }

    static string? GetOptionValue(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == flag)
                return args[i + 1];
        }

        return null;
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

        return ExtractDefineFlagsWithCSharp(ref args);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product define extraction routes through DefineArgumentKernels.
    static List<string> ExtractDefineFlagsWithCSharp(ref string[] args)
    {
        var defines = new List<string>();
        var remaining = new List<string>(args.Length);

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (arg is "--define" or "-d")
            {
                if (i + 1 < args.Length)
                {
                    AddDefineSymbols(defines, args[i + 1]);
                    i++; // consume the flag's value
                }

                continue;
            }

            if (arg.StartsWith("--define=", StringComparison.Ordinal))
            {
                AddDefineSymbols(defines, arg["--define=".Length..]);
                continue;
            }

            if (arg.StartsWith("-d=", StringComparison.Ordinal))
            {
                AddDefineSymbols(defines, arg["-d=".Length..]);
                continue;
            }

            remaining.Add(arg);
        }

        args = remaining.ToArray();
        return defines;
    }

    static void AddDefineSymbols(List<string> defines, string raw)
    {
        foreach (var part in raw.Split(new[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries))
        {
            var symbol = part.Trim();
            if (symbol.Length > 0 && !defines.Contains(symbol))
            {
                defines.Add(symbol);
            }
        }
    }

    static string[] GetPositionalArgs(string[] args, params string[] optionsWithValues)
    {
        if (PositionalArgumentKernels.TryGetArgs(args, optionsWithValues, out var positionalArgs))
            return positionalArgs;

        return GetPositionalArgsWithCSharp(args, optionsWithValues);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product positional collection routes through PositionalArgumentKernels.
    static string[] GetPositionalArgsWithCSharp(string[] args, params string[] optionsWithValues)
    {
        var positional = new List<string>();
        var options = new HashSet<string>(optionsWithValues, StringComparer.Ordinal);

        for (var i = 0; i < args.Length; i++)
        {
            if (options.Contains(args[i]))
            {
                i++;
                continue;
            }

            if (args[i] is "--check" or "--verify-no-changes" or "--diff" or "--stdin" or "--verbose" or "--systems")
                continue;

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                positional.Add(args[i]);
        }

        return positional.ToArray();
    }

    static string? GetFirstPositionalArg(string[] args, string[] optionsWithValues)
    {
        return NewCommandKernels.TryGetProjectNameOperand(args, optionsWithValues, out var positional)
            ? positional
            : GetFirstPositionalArgWithCSharp(args, optionsWithValues);
    }

    static string? GetFirstPositionalArgWithCSharp(string[] args, string[] optionsWithValues)
    {
        var options = new HashSet<string>(optionsWithValues, StringComparer.Ordinal);

        for (var i = 0; i < args.Length; i++)
        {
            if (options.Contains(args[i]))
            {
                i++;
                continue;
            }

            if (args[i] is "--check" or "--verify-no-changes" or "--diff" or "--stdin" or "--verbose")
                continue;

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                return args[i];
        }

        return null;
    }

    private readonly record struct BuildOperandSummary(int Count, string? FirstOperand);

    static BuildOptionSummary GetBuildOptionSummary(string[] args)
    {
        if (BuildCommandKernels.TryGetOptionSummary(args, out var summary))
            return summary;

        return GetBuildOptionSummaryWithCSharp(args);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product build option parsing routes through BuildCommandKernels.
    static BuildOptionSummary GetBuildOptionSummaryWithCSharp(string[] args)
        => new(
            GetOptionValue(args, "--output") ?? GetOptionValue(args, "-o"),
            GetOptionValue(args, "--backend"),
            GetOptionValue(args, "--project"),
            args.Contains("--release"),
            args.Contains("--verbose"),
            args.Contains("--timings"),
            args.Contains("--perf-report"),
            args.Contains("--aot"),
            args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"));

    static TestOptionSummary GetTestOptionSummary(string[] args)
    {
        if (TestCommandKernels.TryGetOptionSummary(args, out var summary))
            return summary;

        return GetTestOptionSummaryWithCSharp(args);
    }

    internal static TestOutputModeKind GetTestOutputMode(bool json)
        => TestCommandKernels.TryGetOutputMode(json, out var outputMode)
            ? outputMode
            : GetTestOutputModeWithCSharp(json);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product test option parsing routes through TestCommandKernels.
    static TestOptionSummary GetTestOptionSummaryWithCSharp(string[] args)
    {
        var coverageReport = args.Contains("--coverage-report");
        return new TestOptionSummary(
            GetOptionValue(args, "--project"),
            GetOptionValue(args, "--backend"),
            GetOptionValue(args, "--filter"),
            GetOptionValue(args, "--timeout"),
            args.Contains("--verbose"),
            args.Contains("--json"),
            coverageReport,
            args.Contains("--coverage") || coverageReport,
            args.Contains("--no-cache"),
            args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"));
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product test output mode selection routes through TestCommandKernels.
    private static TestOutputModeKind GetTestOutputModeWithCSharp(bool json)
        => json ? TestOutputModeKind.Json : TestOutputModeKind.Text;

    static BuildOperandSummary GetBuildOperandSummary(string[] args)
    {
        if (BuildCommandKernels.TryGetOperandSummary(args, out var count, out var firstOperandIndex))
        {
            return new BuildOperandSummary(
                count,
                count > 0 ? args[firstOperandIndex] : null);
        }

        var operands = GetBuildOperandArgsWithCSharp(args);
        return new BuildOperandSummary(
            operands.Length,
            operands.Length > 0 ? operands[0] : null);
    }

    static string[] GetBuildOperandArgsWithCSharp(string[] args)
    {
        args = args
            .Where(a => a is not "--release" and not "--verbose" and not "--timings" and not "--perf-report" and not "--aot")
            .ToArray();
        args = StripOptionWithValue(args, "--output");
        args = StripOptionWithValue(args, "-o");
        args = StripOptionWithValue(args, "--backend");
        args = StripOptionWithValue(args, "--project");
        return args;
    }

    internal static string? GetRunSourceOperand(string[] args)
    {
        if (RunCommandKernels.TryGetSourceOperand(args, out var operand))
            return operand;

        var strippedArgs = StripOptionWithValue(args, "--backend");
        return strippedArgs.Length > 0 ? strippedArgs[0] : null;
    }

    internal static RunOptionSummary GetRunOptionSummary(string[] args)
    {
        if (RunCommandKernels.TryGetOptionSummary(args, out var summary))
            return summary;

        return GetRunOptionSummaryWithCSharp(args);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product run option parsing routes through RunCommandKernels.
    static RunOptionSummary GetRunOptionSummaryWithCSharp(string[] args)
        => new(
            GetOptionValue(args, "--backend"),
            args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"));

    internal static FormatOptionSummary GetFormatOptionSummary(string[] args)
    {
        if (FormatCommandKernels.TryGetOptionSummary(args, out var summary))
            return summary;

        return GetFormatOptionSummaryWithCSharp(args);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product format option parsing routes through FormatCommandKernels.
    static FormatOptionSummary GetFormatOptionSummaryWithCSharp(string[] args)
        => new(
            GetOptionValue(args, "--project"),
            args.Contains("--check") || args.Contains("--verify-no-changes"),
            args.Contains("--diff"),
            args.Contains("--stdin"),
            args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"));

    static int? ParseDurationToMs(string duration)
    {
        if (TestCommandKernels.TryGetDurationMilliseconds(duration, out var milliseconds))
            return milliseconds;

        return ParseDurationToMsWithCSharp(duration);
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product test timeout parsing routes through TestCommandKernels.
    static int? ParseDurationToMsWithCSharp(string duration)
    {
        if (string.IsNullOrWhiteSpace(duration)) return null;

        var trimmed = duration.Trim();
        if (trimmed.Length < 2) return null;

        var unit = trimmed[^1];
        if (!int.TryParse(trimmed[..^1], out var value) || value <= 0)
            return null;

        int? multiplier = unit switch
        {
            's' => 1000,
            'm' => 60 * 1000,
            'h' => 60 * 60 * 1000,
            _ => null
        };

        if (multiplier is not { } factor || value > int.MaxValue / factor)
            return null;

        return value * factor;
    }

    static string[] StripOptionWithValue(string[] args, string flag)
    {
        var result = new List<string>();
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == flag && i + 1 < args.Length)
            {
                i++; // Skip the value too
                continue;
            }
            result.Add(args[i]);
        }
        return result.ToArray();
    }

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
        Console.WriteLine($"nlc {GetVersion()}");
        return 0;
    }

    static int ShowHelp()
    {
        Console.WriteLine($@"N# Compiler (nlc) {GetVersion()}

Usage: nlc <command> [options]

Build & Run:
  build [file]         Compile a project or single .nl file (--release, --verbose)
  run [file]           Build and run a project or single file
  restore              Generate MSBuild compatibility config from project.yml
  publish              Publish project for deployment
  pack                 Create a NuGet package from project.yml metadata
  clean                Remove build artifacts

Analysis & Fix:
  check                Fast type-check (JSON by default)
  fix                  Auto-apply compiler suggestions
  query <cmd>          Code intelligence for LLMs and terminals
  daemon <cmd>         Background analysis daemon
Code Quality:
  format [files...]    Format .nl source files
  lint [files...]      Run static analysis rules
  test                 Run .tests.nl test suites (--filter, --verbose)

Dependencies:
  add <package>        Add a NuGet dependency to project.yml
  tidy                 Identify and remove unused dependencies
  remove <package>     Remove a dependency from project.yml
  update [package]     Update dependencies to latest versions
  tree                 Show dependency tree
  audit                Check for known vulnerabilities

Project:
  new <name>           Create a new N# project
  init                 Initialize N# in the current directory
  export <target>      Export N# sources without changing the IL toolchain
  watch <cmd>          Re-run check/build/test/lint/format on file changes
  doc                  Generate HTML API documentation
  env                  Show environment and toolchain info
  doctor               Verify N# CLI, SDK/templates, LSP, and VS Code tooling
  completion <shell>   Generate shell completion scripts
Options:
  --version, -V        Show nlc version
  --text               Human-readable output for check/fix/query/lint
  --json               Structured JSON output (default for check/fix/query/lint)
  --help, -h           Show this help message

Common Workflows:
  nlc new MyApp && cd MyApp    Create and enter a new project
  nlc build                    Compile the project
  nlc run                      Build and run
  nlc test                     Run tests
  nlc add Serilog@3.1.0        Add a dependency
  nlc check                    Fast feedback loop
  nlc doctor                   Verify the installed toolchain
  nlc fix && nlc check         Auto-fix then verify
  nlc build --release          Release configuration/output layout
  nlc export csharp --project . -o ./myapp-csharp
                               Export C# for inspection
  nlc format --check           CI formatting gate
  nlc test --filter AddPerson  Run specific tests
  nlc watch check              Re-check on every save
  nlc publish -c Release       Publish for deployment

Run 'nlc <command> --help' for command-specific options.");

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine($"Error: {message}");
        return 1;
    }
}

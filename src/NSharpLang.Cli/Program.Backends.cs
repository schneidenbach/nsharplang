using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Performance;

namespace NSharpLang.Cli;

partial class Program
{
    private static CompilationBackend ResolveCompilationBackend(string? backendOption, ProjectConfig? config)
    {
        return !string.IsNullOrWhiteSpace(backendOption)
            ? CompilationBackendExtensions.Parse(backendOption)
            : config?.EffectiveBackend ?? CompilationBackend.Il;
    }

    private static int BuildWithIlBackend(string projectRoot, bool release, string? outputDir, bool timings, bool verbose = false, bool aot = false)
    {
        var totalSw = Stopwatch.StartNew();
        var resolveSw = new Stopwatch();
        var compileSw = new Stopwatch();

        try
        {
            Console.WriteLine($"Building project in {projectRoot} with the IL backend...");

            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return Error("No project.yml found in current directory. Run 'nlc new <name>' to create a project, or use 'nlc build <file.nl>' for a single file.");
            }

            var config = ProjectFileParser.Parse(projectYmlPath);
            var configuration = release ? "Release" : "Debug";
            var resolvedOutputDir = outputDir != null
                ? Path.GetFullPath(outputDir)
                : CompilationReferenceResolver.GetStableOutputDirectory(projectRoot, config, configuration);

            resolveSw.Start();
            var references = CompilationReferenceResolver.AddResolvedDllReferences(
                projectRoot,
                config,
                new ReferenceResolutionOptions(Configuration: configuration, Quiet: !verbose));
            resolveSw.Stop();

            compileSw.Start();
            var outputPath = CompileProjectWithIlBackend(projectRoot, config, resolvedOutputDir, references, aotMode: aot);
            compileSw.Stop();
            if (outputPath == null)
            {
                Console.WriteLine($"  Build failed in {FormatElapsed(totalSw.Elapsed)}");
                return 1;
            }

            Console.WriteLine($"Build successful! (il, {(release ? "release" : "debug")}) [{FormatElapsed(totalSw.Elapsed)}]");
            Console.WriteLine($"Output: {outputPath}");

            if (timings)
            {
                Console.Error.WriteLine($"""
Build timings:
  Resolve:    {FormatElapsed(resolveSw.Elapsed)}
  Emit IL:    {FormatElapsed(compileSw.Elapsed)}
  Total:      {FormatElapsed(totalSw.Elapsed)}
""");
            }

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Build failed: {ex.Message}");
        }
    }

    private static int BuildSingleFileWithIlBackend(string sourceFile, ProjectConfig? projectConfig, bool release, string? outputDir, bool aot = false)
    {
        try
        {
            Console.WriteLine($"Building {sourceFile} with the IL backend...");

            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var config = GetEffectiveCompilationConfig(projectConfig, Path.GetFileNameWithoutExtension(sourceFile));
            var resolvedOutputDir = outputDir != null
                ? Path.GetFullPath(outputDir)
                : Path.Combine(sourceDir, "bin", release ? "Release" : "Debug", config.TargetFramework);

            var references = CompilationReferenceResolver.AddResolvedDllReferences(
                sourceDir,
                config,
                new ReferenceResolutionOptions(Configuration: release ? "Release" : "Debug", BuildProjectReferences: false));
            var outputPath = CompileSourceFilesWithIlBackend(new[] { sourceFile }, sourceDir, config, resolvedOutputDir, references, aotMode: aot);
            if (outputPath == null)
            {
                return 1;
            }

            Console.WriteLine($"Build successful! (il, {(release ? "release" : "debug")})");
            Console.WriteLine($"Output: {outputPath}");
            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Build failed: {ex.Message}");
        }
    }

    private static int RunWithIlBackend(string projectRoot)
    {
        try
        {
            projectRoot = Path.GetFullPath(projectRoot);
            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return Error("No project.yml found in current directory. Run 'nlc new <name>' to create a project.");
            }

            var config = ProjectFileParser.Parse(projectYmlPath);
            if (!string.Equals(config.OutputType, "exe", StringComparison.OrdinalIgnoreCase))
            {
                return Error("Cannot run a library project.");
            }

            var configuration = "Debug";
            var outputDir = CompilationReferenceResolver.GetStableOutputDirectory(projectRoot, config, configuration);
            var references = CompilationReferenceResolver.AddResolvedDllReferences(
                projectRoot,
                config,
                new ReferenceResolutionOptions(Configuration: configuration));
            var outputPath = CompileProjectWithIlBackend(projectRoot, config, outputDir, references);
            if (outputPath == null)
            {
                return 1;
            }

            Console.WriteLine();
            Console.WriteLine("Running...");
            Console.WriteLine();
            return DotnetRunner.RunPassthrough($"\"{outputPath}\"", workingDirectory: projectRoot);
        }
        catch (Exception ex)
        {
            return Error($"Run failed: {ex.Message}");
        }
    }

    private static int RunSingleFileWithIlBackend(string sourceFile, ProjectConfig? projectConfig)
    {
        var tempDir = CreateTempBuildDirectory();
        try
        {
            Console.WriteLine($"Running {sourceFile} with the IL backend...");

            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var config = GetEffectiveCompilationConfig(projectConfig, Path.GetFileNameWithoutExtension(sourceFile));
            if (!string.Equals(config.OutputType, "exe", StringComparison.OrdinalIgnoreCase))
            {
                return Error("Cannot run a library source file.");
            }

            var references = CompilationReferenceResolver.AddResolvedDllReferences(
                sourceDir,
                config,
                new ReferenceResolutionOptions(BuildProjectReferences: false));
            var outputPath = CompileSourceFilesWithIlBackend(new[] { sourceFile }, sourceDir, config, tempDir, references);
            if (outputPath == null)
            {
                return 1;
            }

            Console.WriteLine();
            return DotnetRunner.RunPassthrough($"\"{outputPath}\"", workingDirectory: sourceDir);
        }
        catch (Exception ex)
        {
            return Error($"Run failed: {ex.Message}");
        }
        finally
        {
            CleanupDirectory(tempDir);
        }
    }

    internal static string? BuildProjectWithIlBackendForCommand(
        string projectRoot,
        ProjectConfig config,
        string configuration,
        string? outputDir = null,
        bool includeTests = false,
        bool verbose = false,
        bool aotMode = false)
    {
        projectRoot = Path.GetFullPath(projectRoot);
        var resolvedOutputDir = outputDir != null
            ? Path.GetFullPath(outputDir)
            : CompilationReferenceResolver.GetStableOutputDirectory(projectRoot, config, configuration);
        var references = CompilationReferenceResolver.AddResolvedDllReferences(
            projectRoot,
            config,
            new ReferenceResolutionOptions(Configuration: configuration, IncludeTests: includeTests, Quiet: !verbose));

        return CompileProjectWithIlBackend(projectRoot, config, resolvedOutputDir, references, includeTests, aotMode);
    }

    private static string? CompileProjectWithIlBackend(
        string projectRoot,
        ProjectConfig config,
        string outputDir,
        ReferenceResolutionResult? references = null,
        bool includeTests = false,
        bool aotMode = false)
    {
        var sourceFiles = config.GetSourceFiles(projectRoot, includeTests).ToArray();
        if (!ValidateStrictLintDiagnostics(projectRoot, sourceFiles))
        {
            return null;
        }

        var compiler = new MultiFileCompiler(sourceFiles, projectRoot, config);
        return CompileWithIlBackend(
            compiler,
            outputDir,
            CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config),
            config,
            references,
            aotMode);
    }

    private static string? CompileSourceFilesWithIlBackend(
        string[] sourceFiles,
        string projectRoot,
        ProjectConfig config,
        string outputDir,
        ReferenceResolutionResult? references = null,
        bool aotMode = false)
    {
        if (!ValidateStrictLintDiagnostics(projectRoot, sourceFiles))
        {
            return null;
        }

        var compiler = new MultiFileCompiler(sourceFiles, projectRoot, config);
        return CompileWithIlBackend(
            compiler,
            outputDir,
            CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config),
            config,
            references,
            aotMode);
    }

    private static string? CompileWithIlBackend(
        MultiFileCompiler compiler,
        string outputDir,
        string assemblyName,
        ProjectConfig config,
        ReferenceResolutionResult? references,
        bool aotMode = false)
    {
        Directory.CreateDirectory(outputDir);

        compiler.AotMode = aotMode;
        var outputPath = Path.Combine(outputDir, $"{assemblyName}.dll");
        var result = compiler.CompileToIlAssembly(assemblyName, outputPath);
        EmitCompilationDiagnostics(result);

        if (!result.Success || string.IsNullOrWhiteSpace(result.OutputAssemblyPath))
        {
            return null;
        }

        if (string.Equals(config.OutputType, "exe", StringComparison.OrdinalIgnoreCase))
        {
            CompilationArtifacts.WriteRuntimeConfig(config, result.OutputAssemblyPath);
        }

        references?.CopyRuntimeAssets(outputDir);

        return result.OutputAssemblyPath;
    }

    private static bool ValidateStrictLintDiagnostics(string projectRoot, IReadOnlyList<string> sourceFiles)
    {
        var diagnostics = CodeIntelligenceService.GetLintDiagnostics(projectRoot, sourceFiles)
            .Where(diagnostic => diagnostic.Severity == "error")
            .GroupBy(diagnostic => (diagnostic.Code, diagnostic.File, diagnostic.Line, diagnostic.Column, diagnostic.Message))
            .Select(group => group.First())
            .OrderBy(diagnostic => diagnostic.File)
            .ThenBy(diagnostic => diagnostic.Line)
            .ThenBy(diagnostic => diagnostic.Column)
            .ToList();

        if (diagnostics.Count == 0)
        {
            return true;
        }

        Console.Error.Write(OutputFormatter.DiagnosticsToText(diagnostics));
        return false;
    }

    private static void EmitCompilationDiagnostics(MultiFileCompilationResult result)
    {
        foreach (var error in result.Errors)
        {
            Console.Error.WriteLine(error.Format());
        }
    }

    private static ProjectConfig GetEffectiveCompilationConfig(ProjectConfig? projectConfig, string defaultName)
    {
        var config = projectConfig ?? ProjectFileParser.CreateDefault(defaultName);
        config.Name ??= defaultName;
        return config;
    }

    /// <summary>
    /// Run the AOT-blocker analysis pass over a project and project the blockers into the
    /// stable perf-report shape. Analysis-only: emits no IL and never blocks the build.
    /// </summary>
    private static IReadOnlyList<OutputFormatter.PerfReportAotBlocker> CollectProjectAotBlockers(string projectRoot, ProjectConfig? config)
    {
        var compiler = new MultiFileCompiler(projectRoot, config);
        compiler.CompileForAnalysis();
        return ToPerfReportBlockers(compiler.AotBlockers);
    }

    private static IReadOnlyList<OutputFormatter.PerfReportAotBlocker> CollectSingleFileAotBlockers(string sourceFile, ProjectConfig? projectConfig)
    {
        var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
        var config = GetEffectiveCompilationConfig(projectConfig, Path.GetFileNameWithoutExtension(sourceFile));
        var compiler = new MultiFileCompiler(new[] { sourceFile }, sourceDir, config);
        compiler.CompileForAnalysis();
        return ToPerfReportBlockers(compiler.AotBlockers);
    }

    private static IReadOnlyList<OutputFormatter.PerfReportAotBlocker> ToPerfReportBlockers(IReadOnlyList<AotBlocker> blockers)
    {
        return blockers
            .Select(blocker => new OutputFormatter.PerfReportAotBlocker(
                Code: $"NL{(int)blocker.DiagnosticCode:D3}",
                Kind: blocker.Kind.ToString(),
                File: blocker.File,
                Line: blocker.Line,
                Column: blocker.Column,
                Construct: blocker.Construct,
                EnclosingBoundary: blocker.EnclosingBoundary.ToString(),
                EnclosingDeclaration: blocker.EnclosingDeclaration,
                OnPublicSurface: blocker.IsOnPublicSurface))
            .ToList();
    }
}

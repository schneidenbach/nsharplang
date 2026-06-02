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

    private static BuildCommandResult BuildWithIlBackend(string projectRoot, bool release, string? outputDir, bool timings, bool verbose = false, bool aot = false)
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
                return BuildCommandResult.Failure(
                    Error("No project.yml found in current directory. Run 'nlc new <name>' to create a project, or use 'nlc build <file.nl>' for a single file."));
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
            var outputPath = CompileProjectWithIlBackend(projectRoot, config, resolvedOutputDir, references, out var perfFacts, aotMode: aot);
            compileSw.Stop();
            if (outputPath == null)
            {
                Console.WriteLine($"  Build failed in {FormatElapsed(totalSw.Elapsed)}");
                return BuildCommandResult.Failure(perfFacts: perfFacts);
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

            return new BuildCommandResult(0, perfFacts);
        }
        catch (Exception ex)
        {
            return BuildCommandResult.Failure(Error($"Build failed: {ex.Message}"));
        }
    }

    private static BuildCommandResult BuildSingleFileWithIlBackend(string sourceFile, ProjectConfig? projectConfig, bool release, string? outputDir, bool aot = false)
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
            var outputPath = CompileSourceFilesWithIlBackend(new[] { sourceFile }, sourceDir, config, resolvedOutputDir, references, out var perfFacts, aotMode: aot);
            if (outputPath == null)
            {
                return BuildCommandResult.Failure(perfFacts: perfFacts);
            }

            Console.WriteLine($"Build successful! (il, {(release ? "release" : "debug")})");
            Console.WriteLine($"Output: {outputPath}");
            return new BuildCommandResult(0, perfFacts);
        }
        catch (Exception ex)
        {
            return BuildCommandResult.Failure(Error($"Build failed: {ex.Message}"));
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
        => CompileProjectWithIlBackend(
            projectRoot,
            config,
            outputDir,
            references,
            out _,
            includeTests,
            aotMode);

    private static string? CompileProjectWithIlBackend(
        string projectRoot,
        ProjectConfig config,
        string outputDir,
        ReferenceResolutionResult? references,
        out BuildPerfReportFacts perfFacts,
        bool includeTests = false,
        bool aotMode = false)
    {
        perfFacts = BuildPerfReportFacts.Empty;
        var sourceFiles = config.GetSourceFiles(projectRoot, includeTests).ToArray();
        var compiler = new MultiFileCompiler(sourceFiles, projectRoot, config);
        return CompileWithIlBackend(
            compiler,
            outputDir,
            CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config),
            config,
            references,
            out perfFacts,
            aotMode);
    }

    private static string? CompileSourceFilesWithIlBackend(
        string[] sourceFiles,
        string projectRoot,
        ProjectConfig config,
        string outputDir,
        ReferenceResolutionResult? references = null,
        bool aotMode = false)
        => CompileSourceFilesWithIlBackend(
            sourceFiles,
            projectRoot,
            config,
            outputDir,
            references,
            out _,
            aotMode);

    private static string? CompileSourceFilesWithIlBackend(
        string[] sourceFiles,
        string projectRoot,
        ProjectConfig config,
        string outputDir,
        ReferenceResolutionResult? references,
        out BuildPerfReportFacts perfFacts,
        bool aotMode = false)
    {
        perfFacts = BuildPerfReportFacts.Empty;
        var compiler = new MultiFileCompiler(sourceFiles, projectRoot, config);
        return CompileWithIlBackend(
            compiler,
            outputDir,
            CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config),
            config,
            references,
            out perfFacts,
            aotMode);
    }

    private static string? CompileWithIlBackend(
        MultiFileCompiler compiler,
        string outputDir,
        string assemblyName,
        ProjectConfig config,
        ReferenceResolutionResult? references,
        bool aotMode = false)
        => CompileWithIlBackend(
            compiler,
            outputDir,
            assemblyName,
            config,
            references,
            out _,
            aotMode);

    private static string? CompileWithIlBackend(
        MultiFileCompiler compiler,
        string outputDir,
        string assemblyName,
        ProjectConfig config,
        ReferenceResolutionResult? references,
        out BuildPerfReportFacts perfFacts,
        bool aotMode = false)
    {
        perfFacts = BuildPerfReportFacts.Empty;
        Directory.CreateDirectory(outputDir);

        compiler.AotMode = aotMode;
        var outputPath = Path.Combine(outputDir, $"{assemblyName}.dll");
        var result = compiler.CompileToIlAssembly(assemblyName, outputPath, validateStrictLint: true);
        perfFacts = SafeCollectPerfFacts(() => ToPerfReportFacts(compiler));
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

    private static BuildPerfReportFacts ToPerfReportFacts(MultiFileCompiler compiler)
    {
        var sites = compiler.SystemsReport.Findings
            .Select(finding => new OutputFormatter.PerfReportSite(
                finding.Code,
                finding.Effect,
                finding.File,
                finding.Line,
                finding.Column,
                finding.Message,
                finding.Function,
                finding.Suggestion))
            .ToArray();

        return new BuildPerfReportFacts(
            ToPerfReportBlockers(compiler.AotBlockers),
            sites.Where(site => site.Effect is "allocation").ToArray(),
            sites.Where(site => site.Effect is "delegate").ToArray(),
            sites.Where(site => site.Effect is "boxing").ToArray(),
            sites.Where(site => site.Effect is "dispatch").ToArray(),
            sites.Where(site => site.Effect is "closure").ToArray(),
            sites.Where(site => site.Effect is "pool").ToArray(),
            sites.Where(site => site.Effect is "resource").ToArray(),
            sites.Where(site => site.Effect is "boundaryLeak").ToArray(),
            sites.Where(site => site.Effect is "hotReadiness").ToArray(),
            sites.Where(site => site.Effect is "implicitTrap").ToArray(),
            compiler.SystemsReport.TrustedSites
                .Select(site => new OutputFormatter.PerfReportTrustedSite(
                    site.Function,
                    site.File,
                    site.Line,
                    site.Column,
                    site.Owner,
                    site.Review,
                    site.Expires,
                    site.HasUnsafe,
                    site.BodyStatementCount))
                .ToArray());
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

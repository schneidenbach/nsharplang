using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

partial class Program
{
    private static BuildCommandResult BuildWithIlBackend(string projectRoot, bool release, string? outputDir, bool timings, bool verbose = false, bool aot = false, IReadOnlyList<string>? cliDefines = null)
    {
        var totalSw = Stopwatch.StartNew();
        var resolveSw = new Stopwatch();
        var compileSw = new Stopwatch();

        try
        {
            Console.WriteLine(BuildCommandKernels.GetProjectStartMessage(projectRoot));

            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return BuildCommandResult.Failure(
                    Error(BuildCommandKernels.GetMissingProjectFileMessage()));
            }

            var config = ProjectFileParser.Parse(projectYmlPath);
            var configuration = release ? "Release" : "Debug";
            BuildCommandKernels.ApplyEffectiveDefines(config, debug: !release, cliDefines);
            var resolvedOutputDir = outputDir != null
                ? Path.GetFullPath(outputDir)
                : CompilationReferenceResolver.GetStableOutputDirectory(projectRoot, config, configuration);

            resolveSw.Start();
            var references = CompilationReferenceResolver.AddResolvedDllReferences(
                projectRoot,
                config,
                new ReferenceResolutionOptions
                {
                    Configuration = configuration,
                    Quiet = !verbose,
                    AotMode = aot
                });
            resolveSw.Stop();

            compileSw.Start();
            var outputPath = CompileProjectWithIlBackend(projectRoot, config, resolvedOutputDir, references, out var perfFacts, aotMode: aot);
            compileSw.Stop();
            if (outputPath == null)
            {
                Console.WriteLine(BuildCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(totalSw.ElapsedMilliseconds)));
                return BuildCommandResult.Failure(perfFacts: perfFacts);
            }

            Console.WriteLine(BuildCommandKernels.GetSuccessElapsedMessage(release, ProgramCommandKernels.FormatElapsedMilliseconds(totalSw.ElapsedMilliseconds)));
            Console.WriteLine(BuildCommandKernels.GetOutputPathMessage(outputPath));

            if (timings)
            {
                Console.Error.WriteLine(BuildCommandKernels.GetTimingsMessage(
                    ProgramCommandKernels.FormatElapsedMilliseconds(resolveSw.ElapsedMilliseconds),
                    ProgramCommandKernels.FormatElapsedMilliseconds(compileSw.ElapsedMilliseconds),
                    ProgramCommandKernels.FormatElapsedMilliseconds(totalSw.ElapsedMilliseconds)));
            }

            return new BuildCommandResult(0, perfFacts);
        }
        catch (Exception ex)
        {
            return BuildCommandResult.Failure(Error(BuildCommandKernels.GetFailedMessage(ex.Message)));
        }
    }

    private static BuildCommandResult BuildSingleFileWithIlBackend(string sourceFile, ProjectConfig? projectConfig, bool release, string? outputDir, bool aot = false, IReadOnlyList<string>? cliDefines = null)
    {
        try
        {
            Console.WriteLine(BuildCommandKernels.GetSingleFileStartMessage(sourceFile));

            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var config = GetEffectiveCompilationConfig(projectConfig, Path.GetFileNameWithoutExtension(sourceFile));
            BuildCommandKernels.ApplyEffectiveDefines(config, debug: !release, cliDefines);
            var resolvedOutputDir = outputDir != null
                ? Path.GetFullPath(outputDir)
                : Path.Combine(sourceDir, "bin", release ? "Release" : "Debug", config.TargetFramework);

            var references = CompilationReferenceResolver.AddResolvedDllReferences(
                sourceDir,
                config,
                new ReferenceResolutionOptions
                {
                    Configuration = release ? "Release" : "Debug",
                    BuildProjectReferences = false
                });
            var outputPath = CompileSourceFilesWithIlBackend(new[] { sourceFile }, sourceDir, config, resolvedOutputDir, references, out var perfFacts, aotMode: aot);
            if (outputPath == null)
            {
                return BuildCommandResult.Failure(perfFacts: perfFacts);
            }

            Console.WriteLine(BuildCommandKernels.GetSuccessMessage(release));
            Console.WriteLine(BuildCommandKernels.GetOutputPathMessage(outputPath));
            return new BuildCommandResult(0, perfFacts);
        }
        catch (Exception ex)
        {
            return BuildCommandResult.Failure(Error(BuildCommandKernels.GetFailedMessage(ex.Message)));
        }
    }

    private static int RunWithIlBackend(string projectRoot, IReadOnlyList<string>? cliDefines = null)
    {
        try
        {
            projectRoot = Path.GetFullPath(projectRoot);
            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return Error(RunCommandKernels.GetMissingProjectFileMessage());
            }

            var config = ProjectFileParser.Parse(projectYmlPath);
            if (!string.Equals(config.OutputType, "exe", StringComparison.OrdinalIgnoreCase))
            {
                return Error(RunCommandKernels.GetLibraryProjectMessage());
            }

            var configuration = "Debug";
            BuildCommandKernels.ApplyEffectiveDefines(config, debug: true, cliDefines);
            var outputDir = CompilationReferenceResolver.GetStableOutputDirectory(projectRoot, config, configuration);
            var references = CompilationReferenceResolver.AddResolvedDllReferences(
                projectRoot,
                config,
                new ReferenceResolutionOptions
                {
                    Configuration = configuration
                });
            var outputPath = CompileProjectWithIlBackend(projectRoot, config, outputDir, references);
            if (outputPath == null)
            {
                return 1;
            }

            Console.WriteLine();
            Console.WriteLine(RunCommandKernels.GetProjectStartingMessage());
            Console.WriteLine();
            return DotnetRunner.RunPassthrough($"\"{outputPath}\"", workingDirectory: projectRoot);
        }
        catch (Exception ex)
        {
            return Error(RunCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    private static int RunSingleFileWithIlBackend(string sourceFile, ProjectConfig? projectConfig, IReadOnlyList<string>? cliDefines = null)
    {
        var tempDir = CreateTempBuildDirectory();
        try
        {
            Console.WriteLine(RunCommandKernels.GetSingleFileBackendStartMessage(sourceFile));

            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var config = GetEffectiveCompilationConfig(projectConfig, Path.GetFileNameWithoutExtension(sourceFile));
            BuildCommandKernels.ApplyEffectiveDefines(config, debug: true, cliDefines);
            if (!string.Equals(config.OutputType, "exe", StringComparison.OrdinalIgnoreCase))
            {
                return Error(RunCommandKernels.GetLibrarySourceFileMessage());
            }

            var references = CompilationReferenceResolver.AddResolvedDllReferences(
                sourceDir,
                config,
                new ReferenceResolutionOptions
                {
                    BuildProjectReferences = false
                });
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
            return Error(RunCommandKernels.GetFailedMessage(ex.Message));
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
        BuildCommandKernels.ApplyEffectiveDefines(config, debug: !string.Equals(configuration, "Release", StringComparison.OrdinalIgnoreCase), cliDefines: null);
        var resolvedOutputDir = outputDir != null
            ? Path.GetFullPath(outputDir)
            : CompilationReferenceResolver.GetStableOutputDirectory(projectRoot, config, configuration);
        var references = CompilationReferenceResolver.AddResolvedDllReferences(
            projectRoot,
            config,
            new ReferenceResolutionOptions
            {
                Configuration = configuration,
                IncludeTests = includeTests,
                Quiet = !verbose,
                AotMode = aotMode
            });

        return CompileProjectWithIlBackend(
            projectRoot,
            config,
            resolvedOutputDir,
            references,
            includeTests,
            aotMode);
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
        perfFacts = BuildCommandKernels.ToPerfReportFacts(compiler.SystemsReport);
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

}

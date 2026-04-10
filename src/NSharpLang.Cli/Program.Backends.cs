using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

partial class Program
{
    internal static string GetBackendMsBuildProperty(CompilationBackend backend)
    {
        return $"-p:NSharpCompilationBackend={backend.ToConfigValue()}";
    }

    private static CompilationBackend ResolveCompilationBackend(string? backendOption, ProjectConfig? config)
    {
        return !string.IsNullOrWhiteSpace(backendOption)
            ? CompilationBackendExtensions.Parse(backendOption)
            : config?.EffectiveBackend ?? CompilationBackend.Il;
    }

    private static int BuildWithIlBackend(string projectRoot, bool release, string? outputDir, bool timings)
    {
        var totalSw = Stopwatch.StartNew();

        try
        {
            Console.WriteLine($"Building project in {projectRoot} with the IL backend...");

            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return Error("No project.yml found in current directory. Run 'nlc new <name>' to create a project, or use 'nlc build <file.nl>' for a single file.");
            }

            var config = ProjectFileParser.Parse(projectYmlPath);
            var resolvedOutputDir = outputDir != null
                ? Path.GetFullPath(outputDir)
                : Path.Combine(projectRoot, "bin", release ? "Release" : "Debug", config.TargetFramework);

            var outputPath = CompileProjectWithIlBackend(projectRoot, config, resolvedOutputDir);
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
  Emit IL:    {FormatElapsed(totalSw.Elapsed)}
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

    private static int BuildSingleFileWithIlBackend(string sourceFile, ProjectConfig? projectConfig, bool release, string? outputDir)
    {
        try
        {
            Console.WriteLine($"Building {sourceFile} with the IL backend...");

            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var config = GetEffectiveCompilationConfig(projectConfig, Path.GetFileNameWithoutExtension(sourceFile));
            var resolvedOutputDir = outputDir != null
                ? Path.GetFullPath(outputDir)
                : Path.Combine(sourceDir, "bin", release ? "Release" : "Debug", config.TargetFramework);

            var outputPath = CompileSourceFilesWithIlBackend(new[] { sourceFile }, sourceDir, config, resolvedOutputDir);
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

            var tempDir = CreateTempBuildDirectory();
            try
            {
                var outputPath = CompileProjectWithIlBackend(projectRoot, config, tempDir);
                if (outputPath == null)
                {
                    return 1;
                }

                Console.WriteLine();
                Console.WriteLine("Running...");
                Console.WriteLine();
                return DotnetRunner.RunPassthrough($"\"{outputPath}\"", workingDirectory: projectRoot);
            }
            finally
            {
                CleanupDirectory(tempDir);
            }
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

            var outputPath = CompileSourceFilesWithIlBackend(new[] { sourceFile }, sourceDir, config, tempDir);
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

    private static string? CompileProjectWithIlBackend(string projectRoot, ProjectConfig config, string outputDir)
    {
        var compiler = new MultiFileCompiler(projectRoot, config);
        return CompileWithIlBackend(compiler, outputDir, config.EffectiveName, config);
    }

    private static string? CompileSourceFilesWithIlBackend(string[] sourceFiles, string projectRoot, ProjectConfig config, string outputDir)
    {
        var compiler = new MultiFileCompiler(sourceFiles, projectRoot, config);
        return CompileWithIlBackend(compiler, outputDir, config.EffectiveName, config);
    }

    private static string? CompileWithIlBackend(MultiFileCompiler compiler, string outputDir, string assemblyName, ProjectConfig config)
    {
        Directory.CreateDirectory(outputDir);

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

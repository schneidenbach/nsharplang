using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using NSharpLang.Compiler;
using NSharpLang.Cli.Commands;

namespace NSharpLang.Cli;

class Program
{
    static int Main(string[] args)
        => Execute(args);

    internal static int Execute(string[] args)
    {
        if (args.Length == 0)
        {
            ShowHelp();
            return 0;
        }

        // Handle case-sensitive flags before lowercasing
        var raw = args[0];
        if (raw == "--version" || raw == "-V")
            return ShowVersion();

        var command = raw.ToLower();

        return command switch
        {
            "build" => BuildCommand(args.Skip(1).ToArray()),
            "run" => RunCommand(args.Skip(1).ToArray()),
            "transpile" => TranspileCommand(args.Skip(1).ToArray()),
            "new" => NewCommand(args.Skip(1).ToArray()),
            "test" => TestCommand(args.Skip(1).ToArray()),
            "format" => FormatCommand(args.Skip(1).ToArray()),
            "lint" => Commands.LintCommand.Execute(args.Skip(1).ToArray()),
            "clean" => CleanCommand.Execute(args.Skip(1).ToArray()),
            "watch" => WatchCommand.Execute(args.Skip(1).ToArray()),
            "doc" => DocCommand.Execute(args.Skip(1).ToArray()),
            "completion" => CompletionCommand.Execute(args.Skip(1).ToArray()),
            "check" => Commands.CheckCommand.Execute(args.Skip(1).ToArray()),
            "fix" => FixCommand.Execute(args.Skip(1).ToArray()),
            "query" => QueryCommand.Execute(args.Skip(1).ToArray()),
            "daemon" => DaemonCommand.Execute(args.Skip(1).ToArray()),
            "help" or "--help" or "-h" => ShowHelp(),
            "--version" => ShowVersion(),
            _ => Error($"Unknown command: {command}. Run 'nlc help' to see available commands.")
        };
    }

    static int BuildCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# Build

Usage: nlc build [file.nl] [options]

Build a project or a single N# source file.

Options:
  --keep-generated   Keep generated temporary files for debugging
  --help, -h         Show this help text

Examples:
  nlc build
  nlc build Program.nl
  nlc build --keep-generated

Exit codes:
  0  Build succeeded
  1  Build failed");
            return 0;
        }

        // Check for --keep-generated flag
        var keepGenerated = args.Contains("--keep-generated");
        args = args.Where(a => a != "--keep-generated").ToArray();

        // Support both single-file and multi-file builds
        if (args.Length == 0)
        {
            // No args - build all .nl files in current directory (multi-file mode)
            // Use MSBuild SDK approach (generates .csproj, calls dotnet build, deletes .csproj)
            return BuildWithMSBuild(Directory.GetCurrentDirectory(), keepGenerated);
        }

        var sourceFile = args[0];
        if (!File.Exists(sourceFile))
        {
            return Error($"File not found: {sourceFile}");
        }

        // Single file build - use temp directory
        var tempDir = CreateTempBuildDirectory();
        try
        {
            Console.WriteLine($"Building {sourceFile}...");

            var source = File.ReadAllText(sourceFile);
            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var projectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);
            var csharpCode = CompileToCSharp(source, sourceFile, projectConfig);

            // Write C# to temp file
            var csharpFile = Path.Combine(tempDir, "Program.cs");
            File.WriteAllText(csharpFile, csharpCode);

            // Create .csproj
            var projectFile = Path.Combine(tempDir, "TempProject.csproj");
            File.WriteAllText(projectFile, GenerateCsProj(projectConfig));

            // Build
            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"build \"{projectFile}\" -v q",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                var error = buildResult?.StandardError.ReadToEnd() ?? "";
                var output = buildResult?.StandardOutput.ReadToEnd() ?? "";
                return Error($"Build failed:\n{error}{output}");
            }

            Console.WriteLine("Build successful!");

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Build failed: {ex.Message}");
        }
        finally
        {
            // Clean up temp directory unless --keep-generated
            if (!keepGenerated && Directory.Exists(tempDir))
            {
                try
                {
                    Directory.Delete(tempDir, true);
                }
                catch
                {
                    // Ignore cleanup errors
                }
            }
            else if (keepGenerated)
            {
                Console.WriteLine($"Generated files kept in: {tempDir}");
            }
        }
    }

    static int BuildMultiFile(string projectRoot, bool keepGenerated = false)
    {
        var tempDir = CreateTempBuildDirectory();
        try
        {
            Console.WriteLine($"Building project in {projectRoot}...");

            // Load project config
            var config = ProjectFileParser.ParseFromDirectory(projectRoot);

            // Compile all files
            var compiler = new MultiFileCompiler(projectRoot, config);
            var result = compiler.Compile();

            // Report errors and warnings with rich formatting
            foreach (var error in result.Errors)
            {
                Console.Error.WriteLine(error.Format());
            }

            if (!result.Success)
            {
                return Error($"Build failed with {result.Errors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)");
            }

            // Write C# files to temp directory
            foreach (var kvp in result.TranspiledFiles)
            {
                var sourceFile = kvp.Key;
                var csharpCode = kvp.Value;
                var relativePath = Path.GetRelativePath(projectRoot, sourceFile);
                var csharpFile = Path.Combine(tempDir, Path.ChangeExtension(relativePath, ".cs"));

                // Create subdirectories if needed
                var csharpDir = Path.GetDirectoryName(csharpFile);
                if (csharpDir != null)
                {
                    Directory.CreateDirectory(csharpDir);
                }

                File.WriteAllText(csharpFile, csharpCode);
            }

            // Create .csproj in temp directory
            var projectFile = Path.Combine(tempDir, "TempProject.csproj");
            File.WriteAllText(projectFile, GenerateCsProj(config));

            // Build with dotnet
            Console.WriteLine("Running dotnet build...");
            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"build \"{projectFile}\" -v q",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                var error = buildResult?.StandardError.ReadToEnd() ?? "";
                var output = buildResult?.StandardOutput.ReadToEnd() ?? "";
                return Error($"Build failed:\n{error}{output}");
            }

            Console.WriteLine($"Build successful! ({result.TranspiledFiles.Count} files)");
            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Build failed: {ex.Message}");
        }
        finally
        {
            // Clean up temp directory unless --keep-generated
            if (!keepGenerated && Directory.Exists(tempDir))
            {
                try
                {
                    Directory.Delete(tempDir, true);
                }
                catch
                {
                    // Ignore cleanup errors
                }
            }
            else if (keepGenerated)
            {
                Console.WriteLine($"Generated files kept in: {tempDir}");
            }
        }
    }

    static int BuildWithMSBuild(string projectRoot, bool keepGenerated = false, bool announceGeneratedFiles = true)
    {
        string? generatedCsprojPath = null;
        string? generatedGlobalJsonPath = null;
        string? generatedNuGetConfigPath = null;

        try
        {
            Console.WriteLine($"Building project in {projectRoot}...");

            // Check for project.yml
            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return Error("No project.yml found in current directory. Run 'nlc new <name>' to create a project, or 'nlc build <file.nl>' to build a single file.");
            }

            // Load project config
            var config = ProjectFileParser.Parse(projectYmlPath);
            var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";

            // Generate .csproj in the project directory
            generatedCsprojPath = Path.Combine(projectRoot, $"{projectName}.csproj");
            var csprojContent = $@"<Project Sdk=""NSharpLang.Sdk"">
  <PropertyGroup>
    <OutputType>{(config.OutputType == "exe" ? "Exe" : "Library")}</OutputType>
    <TargetFramework>{config.TargetFramework}</TargetFramework>
  </PropertyGroup>
</Project>";

            File.WriteAllText(generatedCsprojPath, csprojContent);
            Console.WriteLine($"Generated {projectName}.csproj");

            // Generate global.json to point to local SDK (for now)
            generatedGlobalJsonPath = Path.Combine(projectRoot, "global.json");
            if (!File.Exists(generatedGlobalJsonPath))
            {
                var repoRoot = FindRepoRoot(projectRoot);
                var globalJsonContent = $$"""
{
  "sdk": {
    "version": "9.0.100"
  },
  "msbuild-sdks": {
    "NSharpLang.Sdk": "0.1.0"
  }
}
""";
                File.WriteAllText(generatedGlobalJsonPath, globalJsonContent);
                Console.WriteLine("Generated global.json");
            }
            else
            {
                generatedGlobalJsonPath = null; // Don't delete if it already existed
            }

            // Generate NuGet.config to point to local SDK (for now)
            generatedNuGetConfigPath = Path.Combine(projectRoot, "NuGet.config");
            if (!File.Exists(generatedNuGetConfigPath))
            {
                var repoRoot = FindRepoRoot(projectRoot);
                var sdkPath = Path.Combine(repoRoot, "src/NSharpLang.Sdk/bin/Debug");
                var nugetConfigContent = $@"<?xml version=""1.0"" encoding=""utf-8""?>
<configuration>
  <packageSources>
    <clear />
    <add key=""nuget.org"" value=""https://api.nuget.org/v3/index.json"" />
    <add key=""local"" value=""{sdkPath}"" />
  </packageSources>
</configuration>";
                File.WriteAllText(generatedNuGetConfigPath, nugetConfigContent);
                Console.WriteLine("Generated NuGet.config");
            }
            else
            {
                generatedNuGetConfigPath = null; // Don't delete if it already existed
            }

            // Call dotnet build
            Console.WriteLine("Running dotnet build...");
            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"build \"{generatedCsprojPath}\"",
                WorkingDirectory = projectRoot,
                UseShellExecute = false,
                RedirectStandardOutput = false,
                RedirectStandardError = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                return Error("Build failed");
            }

            Console.WriteLine("Build successful!");
            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Build failed: {ex.Message}");
        }
        finally
        {
            // Delete generated files unless --keep-generated
            if (!keepGenerated)
            {
                if (generatedCsprojPath != null && File.Exists(generatedCsprojPath))
                {
                    File.Delete(generatedCsprojPath);
                    Console.WriteLine($"Deleted {Path.GetFileName(generatedCsprojPath)}");
                }
                if (generatedGlobalJsonPath != null && File.Exists(generatedGlobalJsonPath))
                {
                    File.Delete(generatedGlobalJsonPath);
                    Console.WriteLine("Deleted global.json");
                }
                if (generatedNuGetConfigPath != null && File.Exists(generatedNuGetConfigPath))
                {
                    File.Delete(generatedNuGetConfigPath);
                    Console.WriteLine("Deleted NuGet.config");
                }
            }
            else if (announceGeneratedFiles)
            {
                Console.WriteLine($"Generated files kept in: {projectRoot}");
            }
        }
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

    static int TranspileCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# Transpile

Usage: nlc transpile <file.nl>

Transpile a single N# source file to C# and print the generated code to stdout.
Useful for debugging the compiler, inspecting generated C# for interop, or
feeding the output into existing C# tooling.

Options:
  --help, -h    Show this help text

Examples:
  nlc transpile Program.nl
  nlc transpile Program.nl > Program.cs
  nlc transpile Program.nl | grep 'class'

Exit codes:
  0  Transpilation succeeded
  1  Transpilation failed");
            return 0;
        }

        if (args.Length == 0)
        {
            return Error("Usage: nlc transpile <file.nl>");
        }

        var sourceFile = args[0];
        if (!File.Exists(sourceFile))
        {
            return Error($"File not found: {sourceFile}");
        }

        try
        {
            var source = File.ReadAllText(sourceFile);
            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var projectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);
            var csharpCode = CompileToCSharp(source, sourceFile, projectConfig);

            Console.WriteLine(csharpCode);

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Transpilation failed: {ex.Message}");
        }
    }

    static int RunCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# Run

Usage: nlc run [file.nl]

Build and run either the current project or a single N# source file.

Examples:
  nlc run
  nlc run Program.nl

Exit codes:
  0  Program ran successfully
  1  Build or execution failed");
            return 0;
        }

        // Support both single-file and multi-file runs
        if (args.Length == 0)
        {
            // No args - run multi-file project in current directory
            return RunWithMSBuild(Directory.GetCurrentDirectory());
        }

        var sourceFile = args[0];
        if (!File.Exists(sourceFile))
        {
            return Error($"File not found: {sourceFile}");
        }

        // Single file run
        var tempDir = CreateTempBuildDirectory();
        try
        {
            Console.WriteLine($"Running {sourceFile}...");

            // Look for project.yml in the directory containing the source file
            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var projectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);

            var source = File.ReadAllText(sourceFile);
            var csharpCode = CompileToCSharp(source, sourceFile, projectConfig);

            // Write C# to temp file
            var csharpFile = Path.Combine(tempDir, "Program.cs");
            File.WriteAllText(csharpFile, csharpCode);

            // Create .csproj (with dependencies if project.yml exists)
            var projectFile = Path.Combine(tempDir, "TempProject.csproj");
            File.WriteAllText(projectFile, GenerateCsProj(projectConfig));

            // Build and run
            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"build \"{projectFile}\" -v q",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                var error = buildResult?.StandardError.ReadToEnd() ?? "";
                var output = buildResult?.StandardOutput.ReadToEnd() ?? "";
                return Error($"Build failed:\n{error}{output}");
            }

            Console.WriteLine();

            var runResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"run --project \"{projectFile}\" --no-build",
                UseShellExecute = false
            });

            runResult?.WaitForExit();

            return runResult?.ExitCode ?? 0;
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

    static int RunMultiFile(string projectRoot)
    {
        var tempDir = CreateTempBuildDirectory();
        try
        {
            Console.WriteLine($"Running project in {projectRoot}...");

            // Load project config
            var projectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);

            // Compile all files
            var compiler = new MultiFileCompiler(projectRoot, projectConfig);
            var result = compiler.Compile();

            // Report errors and warnings with rich formatting
            foreach (var error in result.Errors)
            {
                Console.Error.WriteLine(error.Format());
            }

            if (!result.Success)
            {
                return Error($"Compilation failed with {result.Errors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)");
            }

            // Write C# to temp directory
            foreach (var kvp in result.TranspiledFiles)
            {
                var sourceFile = kvp.Key;
                var csharpCode = kvp.Value;
                var relativePath = Path.GetRelativePath(projectRoot, sourceFile);
                var csharpFile = Path.Combine(tempDir, Path.ChangeExtension(relativePath, ".cs"));

                // Create subdirectories if needed
                var csharpDir = Path.GetDirectoryName(csharpFile);
                if (csharpDir != null)
                {
                    Directory.CreateDirectory(csharpDir);
                }

                File.WriteAllText(csharpFile, csharpCode);
            }

            // Create .csproj
            var projectFile = Path.Combine(tempDir, "TempProject.csproj");
            File.WriteAllText(projectFile, GenerateCsProj(projectConfig));

            // Build and run
            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"build \"{projectFile}\" -v q",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                var error = buildResult?.StandardError.ReadToEnd() ?? "";
                var output = buildResult?.StandardOutput.ReadToEnd() ?? "";
                return Error($"Build failed:\n{error}{output}");
            }

            Console.WriteLine();

            var runResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"run --project \"{projectFile}\" --no-build",
                UseShellExecute = false
            });

            runResult?.WaitForExit();

            return runResult?.ExitCode ?? 0;
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

    static int RunWithMSBuild(string projectRoot)
    {
        // Build first (generates .csproj, builds, deletes .csproj)
        var buildResult = BuildWithMSBuild(projectRoot, keepGenerated: true, announceGeneratedFiles: false); // Keep it for run
        if (buildResult != 0)
        {
            return buildResult;
        }

        try
        {
            // Load config to get project name
            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            var config = ProjectFileParser.Parse(projectYmlPath);
            var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";
            var csprojPath = Path.Combine(projectRoot, $"{projectName}.csproj");

            // Run with dotnet run
            Console.WriteLine();
            Console.WriteLine("Running...");
            Console.WriteLine();

            var runResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"run --project \"{csprojPath}\" --no-build",
                WorkingDirectory = projectRoot,
                UseShellExecute = false
            });

            runResult?.WaitForExit();

            return runResult?.ExitCode ?? 0;
        }
        catch (Exception ex)
        {
            return Error($"Run failed: {ex.Message}");
        }
        finally
        {
            // Now delete the generated .csproj and config files
            var config = ProjectFileParser.ParseFromDirectory(projectRoot);
            if (config != null)
            {
                var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";
                var csprojPath = Path.Combine(projectRoot, $"{projectName}.csproj");
                var globalJsonPath = Path.Combine(projectRoot, "global.json");
                var nugetConfigPath = Path.Combine(projectRoot, "NuGet.config");

                if (File.Exists(csprojPath))
                {
                    File.Delete(csprojPath);
                    Console.WriteLine($"Deleted {Path.GetFileName(csprojPath)}");
                }
                if (File.Exists(globalJsonPath))
                {
                    File.Delete(globalJsonPath);
                    Console.WriteLine("Deleted global.json");
                }
                if (File.Exists(nugetConfigPath))
                {
                    File.Delete(nugetConfigPath);
                    Console.WriteLine("Deleted NuGet.config");
                }
            }
        }
    }

    static string GenerateCsProj(ProjectConfig? config)
    {
        config ??= ProjectFileParser.CreateDefault();

        var sb = new System.Text.StringBuilder();
        sb.AppendLine($@"<Project Sdk=""{config.Sdk}"">");
        sb.AppendLine("  <PropertyGroup>");
        sb.AppendLine($"    <OutputType>{(config.OutputType == "exe" ? "Exe" : "Library")}</OutputType>");
        sb.AppendLine($"    <TargetFramework>{config.TargetFramework}</TargetFramework>");
        sb.AppendLine("    <LangVersion>latest</LangVersion>");
        sb.AppendLine("    <Nullable>enable</Nullable>");
        sb.AppendLine("  </PropertyGroup>");

        // Generate ItemGroup for dependencies
        if (config.Dependencies.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("  <ItemGroup>");

            foreach (var reference in config.Dependencies)
            {
                switch (reference.Type)
                {
                    case ReferenceType.NuGet:
                        if (reference.Version != null)
                            sb.AppendLine($"    <PackageReference Include=\"{reference.Nuget}\" Version=\"{reference.Version}\" />");
                        else
                            sb.AppendLine($"    <PackageReference Include=\"{reference.Nuget}\" Version=\"*\" />");
                        break;

                    case ReferenceType.Dll:
                        var dllPath = Path.GetFullPath(reference.Dll!);
                        sb.AppendLine($"    <Reference Include=\"{Path.GetFileNameWithoutExtension(reference.Dll)}\">");
                        sb.AppendLine($"      <HintPath>{dllPath}</HintPath>");
                        sb.AppendLine("    </Reference>");
                        break;

                    case ReferenceType.Project:
                        var projectPath = Path.GetFullPath(reference.Project!);
                        sb.AppendLine($"    <ProjectReference Include=\"{projectPath}\" />");
                        break;

                    case ReferenceType.Framework:
                        sb.AppendLine($"    <FrameworkReference Include=\"{reference.Framework}\" />");
                        break;
                }
            }

            sb.AppendLine("  </ItemGroup>");
        }

        // Generate ItemGroup for test dependencies
        if (config.TestDependencies.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("  <ItemGroup>");

            foreach (var reference in config.TestDependencies)
            {
                switch (reference.Type)
                {
                    case ReferenceType.NuGet:
                        if (reference.Version != null)
                            sb.AppendLine($"    <PackageReference Include=\"{reference.Nuget}\" Version=\"{reference.Version}\" />");
                        else
                            sb.AppendLine($"    <PackageReference Include=\"{reference.Nuget}\" Version=\"*\" />");
                        break;

                    case ReferenceType.Dll:
                        var dllPath = Path.GetFullPath(reference.Dll!);
                        sb.AppendLine($"    <Reference Include=\"{Path.GetFileNameWithoutExtension(reference.Dll)}\">");
                        sb.AppendLine($"      <HintPath>{dllPath}</HintPath>");
                        sb.AppendLine("    </Reference>");
                        break;

                    case ReferenceType.Project:
                        var projectPath = Path.GetFullPath(reference.Project!);
                        sb.AppendLine($"    <ProjectReference Include=\"{projectPath}\" />");
                        break;

                    case ReferenceType.Framework:
                        sb.AppendLine($"    <FrameworkReference Include=\"{reference.Framework}\" />");
                        break;
                }
            }

            sb.AppendLine("  </ItemGroup>");
        }

        // FUTURE: Add support for project references when needed
        // if (config.Dependencies != null && config.Dependencies.Count > 0)
        // {
        //     sb.AppendLine();
        //     sb.AppendLine("  <ItemGroup>");
        //     foreach (var projectRef in config.Dependencies)
        //     {
        //         sb.AppendLine($"    <ProjectReference Include=\"{projectRef}\" />");
        //     }
        //     sb.AppendLine("  </ItemGroup>");
        // }
        #pragma warning restore CS0618 // Type or member is obsolete

        sb.AppendLine("</Project>");
        return sb.ToString();
    }

    static string CompileToCSharp(string source, string fileName, ProjectConfig? config = null)
    {
        // Lexical analysis
        var lexer = new Lexer(source, fileName);
        var tokens = lexer.Tokenize();

        // Parsing
        var parser = new Parser(tokens, fileName, source);  // Pass source code
        var parseResult = parser.ParseCompilationUnit();

        // Collect all errors (parse errors + analysis errors)
        var allErrors = new List<CompilerError>(parseResult.Errors);

        // Semantic analysis (only if parsing succeeded)
        if (parseResult.CompilationUnit != null)
        {
            var analyzer = new Analyzer();
            var projectRoot = Path.GetDirectoryName(Path.GetFullPath(fileName)) ?? Directory.GetCurrentDirectory();

            // Load system assemblies
            analyzer.LoadSystemAssemblies();

            // Load assemblies from project configuration
            analyzer.LoadFromProjectConfig(config, projectRoot);

            var analysisResult = analyzer.Analyze(parseResult.CompilationUnit, fileName, projectRoot, source);
            allErrors.AddRange(analysisResult.Errors);
        }

        // Report errors and warnings with rich formatting
        foreach (var error in allErrors)
        {
            Console.Error.WriteLine(error.Format());
        }

        // Stop if there are errors
        if (allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            throw new Exception($"Compilation failed with {allErrors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)");
        }

        // Transpilation — use absolute path so #line directives resolve correctly
        // even when the generated C# is compiled from a temp directory
        var transpiler = new Transpiler(parseResult.CompilationUnit!, config, sourceFilePath: Path.GetFullPath(fileName));
        return transpiler.Transpile();
    }

    static int NewCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# New Project

Usage: nlc new <project-name>

Create a new N# project with a starter `project.yml` and `Program.nl`.

Examples:
  nlc new MyApp

Exit codes:
  0  Project created successfully
  1  Project creation failed");
            return 0;
        }

        if (args.Length == 0)
        {
            return Error("Usage: nlc new <project-name>");
        }

        var projectName = args[0];
        var projectDir = Path.Combine(Directory.GetCurrentDirectory(), projectName);

        if (Directory.Exists(projectDir))
        {
            return Error($"Directory already exists: {projectDir}. Use a different name or remove the existing directory.");
        }

        try
        {
            Console.WriteLine($"Creating new project: {projectName}");

            // Create project directory
            Directory.CreateDirectory(projectDir);

            // Create project.yml
            var projectYml = Path.Combine(projectDir, "project.yml");
            File.WriteAllText(projectYml, ProjectFileParser.GenerateTemplate(projectName));

            // Create Program.nl
            var programNl = Path.Combine(projectDir, "Program.nl");
            File.WriteAllText(programNl, @"func main() {
    print ""Hello, N#!""
}");

            Console.WriteLine($"Created: {projectName}/project.yml");
            Console.WriteLine($"Created: {projectName}/Program.nl");
            Console.WriteLine();
            Console.WriteLine($"To build and run your project:");
            Console.WriteLine($"  cd {projectName}");
            Console.WriteLine($"  nlc run Program.nl");
            Console.WriteLine();

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Failed to create project: {ex.Message}");
        }
    }

    static int TestCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# Test

Usage: nlc test [options]

Run `.tests.nl` suites through the generated xUnit test project.

Options:
  --project <dir>   Project root directory (default: current directory)
  --filter <name>   Run only tests whose display name or fully-qualified name matches
  --verbose         Use more detailed `dotnet test` output
  --help, -h        Show this help text

Examples:
  nlc test
  nlc test --filter AddPerson
  nlc test --project examples/15-dogfood-project --verbose

Exit codes:
  0  Tests passed
  1  Compilation or test execution failed");
            return 0;
        }

        var projectRoot = GetOptionValue(args, "--project") ?? Directory.GetCurrentDirectory();
        projectRoot = Path.GetFullPath(projectRoot);
        var filter = GetOptionValue(args, "--filter");
        var verbose = args.Contains("--verbose");

        try
        {
            Console.WriteLine($"Testing project in {projectRoot}...");

            // Find all .tests.nl files
            var testFiles = Directory.GetFiles(projectRoot, "*.tests.nl", SearchOption.AllDirectories);

            if (testFiles.Length == 0)
            {
                Console.WriteLine("No test files (*.tests.nl) found.");
                return 0;
            }

            Console.WriteLine($"Found {testFiles.Length} test file(s)");

            // Load project config
            var projectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);

            // Find all non-test .nl files using project config (respects exclude patterns)
            var sourceFiles = projectConfig?.GetSourceFiles(projectRoot, includeTests: false) ?? Array.Empty<string>();

            // For exe projects, build main project first and reference it
            // For library projects, compile all together (current behavior)
            MultiFileCompilationResult result;
            string? mainProjectDll = null;

            if (projectConfig?.OutputType == "exe")
            {
                Console.WriteLine("Building main project first...");

                // Build main project
                var mainBuildDir = Path.Combine(Path.GetTempPath(), $"nlc-main-build-{Guid.NewGuid():N}");
                Directory.CreateDirectory(mainBuildDir);

                // Compile source files (excluding tests)
                var mainCompiler = new MultiFileCompiler(sourceFiles, projectRoot, projectConfig);
                var mainResult = mainCompiler.Compile();

                foreach (var error in mainResult.Errors)
                {
                    Console.Error.WriteLine(error.Format());
                }

                if (!mainResult.Success)
                {
                    return Error($"Main project compilation failed with {mainResult.Errors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)");
                }

                // Write main project C# files
                foreach (var kvp in mainResult.TranspiledFiles)
                {
                    var sourceFile = kvp.Key;
                    var csharpCode = kvp.Value;
                    var relativePath = Path.GetRelativePath(projectRoot, sourceFile);
                    var csharpFile = Path.Combine(mainBuildDir, Path.ChangeExtension(relativePath, ".cs"));

                    var csharpDir = Path.GetDirectoryName(csharpFile);
                    if (csharpDir != null)
                    {
                        Directory.CreateDirectory(csharpDir);
                    }

                    File.WriteAllText(csharpFile, csharpCode);
                }

                // Create main project .csproj
                var mainProjectFile = Path.Combine(mainBuildDir, $"{projectConfig.EffectiveName}.csproj");
                File.WriteAllText(mainProjectFile, GenerateCsProj(projectConfig));

                // Build main project
                var mainBuildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                {
                    FileName = "dotnet",
                    Arguments = $"build \"{mainProjectFile}\" -v q",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false
                });

                mainBuildResult?.WaitForExit();

                if (mainBuildResult?.ExitCode != 0)
                {
                    var error = mainBuildResult?.StandardError.ReadToEnd() ?? "";
                    var output = mainBuildResult?.StandardOutput.ReadToEnd() ?? "";
                    return Error($"Main project build failed:\n{error}{output}");
                }

                mainProjectDll = Path.Combine(mainBuildDir, "bin", "Debug", projectConfig.TargetFramework, $"{projectConfig.EffectiveName}.dll");
                Console.WriteLine($"Main project built successfully: {mainProjectDll}");

                // Create a test config that includes reference to main project DLL
                var testConfig = new ProjectConfig
                {
                    Name = projectConfig.Name + ".Tests",
                    OutputType = "library",
                    TargetFramework = projectConfig.TargetFramework,
                    Sdk = projectConfig.Sdk,
                    Dependencies = new List<Reference>(projectConfig.Dependencies)
                    {
                        new Reference { Dll = mainProjectDll }
                    },
                    Language = projectConfig.Language
                };

                // Now compile only test files with reference to main project
                var testCompiler = new MultiFileCompiler(testFiles, projectRoot, testConfig);
                result = testCompiler.Compile();
            }
            else
            {
                // Library project: compile all together (current behavior)
                var allFiles = sourceFiles.Concat(testFiles).ToArray();
                var compiler = new MultiFileCompiler(allFiles, projectRoot, projectConfig);
                result = compiler.Compile();
            }

            // Report errors and warnings with rich formatting
            foreach (var error in result.Errors)
            {
                Console.Error.WriteLine(error.Format());
            }

            if (!result.Success)
            {
                return Error($"Compilation failed with {result.Errors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)");
            }

            // Write C# files to temp directory
            var tempDir = Path.Combine(Path.GetTempPath(), $"nlc-tests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(tempDir);

            foreach (var kvp in result.TranspiledFiles)
            {
                var sourceFile = kvp.Key;
                var csharpCode = kvp.Value;
                var relativePath = Path.GetRelativePath(projectRoot, sourceFile);
                var csharpFile = Path.Combine(tempDir, Path.ChangeExtension(relativePath, ".cs"));

                var csharpDir = Path.GetDirectoryName(csharpFile);
                if (csharpDir != null)
                {
                    Directory.CreateDirectory(csharpDir);
                }

                File.WriteAllText(csharpFile, csharpCode);
            }

            // Create test .csproj with XUnit dependencies
            var projectFile = Path.Combine(tempDir, "TestProject.csproj");
            File.WriteAllText(projectFile, GenerateTestCsProj(projectConfig, mainProjectDll));

            // Copy deps.json file if it exists (needed for WebApplicationFactory)
            if (!string.IsNullOrEmpty(mainProjectDll))
            {
                var depsJsonPath = Path.ChangeExtension(mainProjectDll, ".deps.json");
                if (File.Exists(depsJsonPath))
                {
                    var testOutputDir = Path.Combine(tempDir, "bin", "Debug", projectConfig!.TargetFramework);
                    Directory.CreateDirectory(testOutputDir);
                    var targetDepsPath = Path.Combine(testOutputDir, Path.GetFileName(depsJsonPath));
                    File.Copy(depsJsonPath, targetDepsPath, true);

                    // Create a dummy .csproj and .sln in output directory for WebApplicationFactory content root detection
                    var dummyCsproj = Path.Combine(testOutputDir, "TestProject.csproj");
                    File.WriteAllText(dummyCsproj, "<Project Sdk=\"Microsoft.NET.Sdk.Web\"><PropertyGroup><TargetFramework>" + projectConfig.TargetFramework + "</TargetFramework></PropertyGroup></Project>");

                    var dummySln = Path.Combine(testOutputDir, "TestProject.sln");
                    File.WriteAllText(dummySln, "Microsoft Visual Studio Solution File, Format Version 12.00");

                    // Create project name subdirectory that WebApplicationFactory expects
                    var projectContentRoot = Path.Combine(testOutputDir, projectConfig.EffectiveName);
                    Directory.CreateDirectory(projectContentRoot);
                }
            }

            // Build tests
            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"build \"{projectFile}\" -v q",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                var error = buildResult?.StandardError.ReadToEnd() ?? "";
                var output = buildResult?.StandardOutput.ReadToEnd() ?? "";
                return Error($"Test build failed:\n{error}{output}");
            }

            Console.WriteLine();

            // Run tests
            var dotnetFilter = string.IsNullOrWhiteSpace(filter)
                ? null
                : $"DisplayName~{filter}|FullyQualifiedName~{filter}";
            var testArguments = new List<string>
            {
                "test",
                QuoteArgument(projectFile),
                "--no-build",
                "-v",
                verbose ? "normal" : "minimal"
            };

            if (!string.IsNullOrWhiteSpace(dotnetFilter))
            {
                testArguments.Add("--filter");
                testArguments.Add(QuoteArgument(dotnetFilter));
            }

            var testRunResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = string.Join(" ", testArguments),
                UseShellExecute = false
            });

            testRunResult?.WaitForExit();

            return testRunResult?.ExitCode ?? 0;
        }
        catch (Exception ex)
        {
            return Error($"Test failed: {ex.Message}");
        }
    }

    static int FormatCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
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
            var verifyOnly = args.Contains("--check") || args.Contains("--verify-no-changes");
            var diffOnly = args.Contains("--diff");
            var stdinMode = args.Contains("--stdin");
            var projectRoot = Path.GetFullPath(GetOptionValue(args, "--project") ?? Directory.GetCurrentDirectory());
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
                files = Directory.GetFiles(projectRoot, "*.nl", SearchOption.AllDirectories)
                    .Where(f => !f.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase))
                    .ToArray();
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

    static string GenerateTestCsProj(ProjectConfig? config, string? mainProjectDll = null)
    {
        config ??= ProjectFileParser.CreateDefault();

        // Merge both regular dependencies and test dependencies
        var allDependencies = config.Dependencies
            .Concat(config.TestDependencies)
            .Where(r => r.Type == ReferenceType.NuGet)
            .DistinctBy(r => r.Nuget); // Test dependencies override regular ones if same package

        var dependencies = string.Join("\n    ",
            allDependencies.Select(r =>
                $@"<PackageReference Include=""{r.Nuget}"" Version=""{r.Version ?? "*"}"" />"));

        var assemblyReference = "";
        if (!string.IsNullOrEmpty(mainProjectDll))
        {
            assemblyReference = $@"
  <ItemGroup>
    <Reference Include=""{Path.GetFileNameWithoutExtension(mainProjectDll)}"">
      <HintPath>{mainProjectDll}</HintPath>
    </Reference>
  </ItemGroup>";
        }

        return $@"<Project Sdk=""Microsoft.NET.Sdk"">
  <PropertyGroup>
    <TargetFramework>{config.TargetFramework}</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include=""Microsoft.NET.Test.Sdk"" Version=""17.8.0"" />
    <PackageReference Include=""xunit"" Version=""2.6.0"" />
    <PackageReference Include=""xunit.runner.visualstudio"" Version=""2.5.6"">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    {dependencies}
  </ItemGroup>{assemblyReference}
</Project>";
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
        return formatter.Format(parseResult.CompilationUnit!);
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

    static string[] GetPositionalArgs(string[] args, params string[] optionsWithValues)
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

            if (args[i] is "--check" or "--verify-no-changes" or "--diff" or "--stdin" or "--verbose")
                continue;

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                positional.Add(args[i]);
        }

        return positional.ToArray();
    }

    static string QuoteArgument(string value)
        => $"\"{value.Replace("\"", "\\\"", StringComparison.Ordinal)}\"";

    static string NormalizePath(string path) => path.Replace('\\', '/');

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
  build [file]         Compile a project or single .nl file
  run [file]           Build and run a project or single file
  transpile <file>     Transpile .nl to C# and print to stdout
  clean                Remove build artifacts

Analysis & Fix:
  check                Fast type-check (JSON by default)
  fix                  Auto-apply compiler suggestions
  query <cmd>          Code intelligence for LLMs and terminals
  daemon <cmd>         Background analysis daemon

Code Quality:
  format [files...]    Format .nl source files
  lint [files...]      Run static analysis rules
  test                 Run .tests.nl test suites

Project:
  new <name>           Create a new N# project
  watch <cmd>          Re-run check/build/test on file changes
  doc                  Generate HTML API documentation
  completion <shell>   Generate shell completion scripts

Options:
  --version, -V        Show nlc version
  --text               Human-readable output for check/fix/query/lint
  --json               Structured JSON output (default for check/fix/query/lint)
  --help, -h           Show this help message

Common Workflows:
  nlc new MyApp && cd MyApp    Create and enter a new project
  nlc check                    Fast feedback loop
  nlc fix && nlc check         Auto-fix then verify
  nlc format --check           CI formatting gate
  nlc test --filter AddPerson  Run specific tests
  nlc watch check              Re-check on every save

Run 'nlc <command> --help' for command-specific options.");

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine($"Error: {message}");
        return 1;
    }
}

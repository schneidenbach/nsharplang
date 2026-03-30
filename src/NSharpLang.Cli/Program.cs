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
            "publish" => PublishCommand(args.Skip(1).ToArray()),
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

When run in a directory with project.yml, generates a .g.csproj file and
invokes MSBuild via the NSharpLang.Sdk. No user-authored .csproj is needed.

Options:
  --release          Build with Release configuration (default: Debug)
  --verbose          Show detailed build output
  --keep-generated   Keep generated temporary files for debugging (single-file mode)
  --help, -h         Show this help text

Examples:
  nlc build              Build the current project
  nlc build --release    Optimized release build
  nlc build --verbose    Show detailed build output
  nlc build Program.nl   Build a single file

Exit codes:
  0  Build succeeded
  1  Build failed");
            return 0;
        }

        // Check for flags
        var keepGenerated = args.Contains("--keep-generated");
        var release = args.Contains("--release");
        var verbose = args.Contains("--verbose");
        args = args.Where(a => a is not "--keep-generated" and not "--release" and not "--verbose").ToArray();

        // Support both single-file and multi-file builds
        if (args.Length == 0)
        {
            // No args - build all .nl files in current directory (multi-file mode)
            // Use MSBuild SDK approach (generates .csproj, calls dotnet build, deletes .csproj)
            return BuildWithMSBuild(Directory.GetCurrentDirectory(), keepGenerated, release: release, verbose: verbose);
        }

        var sourceFile = args[0];
        if (!File.Exists(sourceFile))
        {
            return Error($"File not found: {sourceFile}");
        }

        // Single file build - use temp directory
        var sw = System.Diagnostics.Stopwatch.StartNew();
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
            var buildArgs = $"build \"{projectFile}\"";
            if (release) buildArgs += " -c Release";
            buildArgs += verbose ? " -v normal" : " -v q";

            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = buildArgs,
                RedirectStandardOutput = !verbose,
                RedirectStandardError = !verbose,
                UseShellExecute = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                var error = verbose ? "" : (buildResult?.StandardError.ReadToEnd() ?? "");
                var output = verbose ? "" : (buildResult?.StandardOutput.ReadToEnd() ?? "");
                var detail = string.IsNullOrWhiteSpace(error + output) ? "" : $"\n{error}{output}";
                Console.WriteLine($"  Build failed in {FormatElapsed(sw.Elapsed)}");
                return Error($"Build failed{detail}");
            }

            Console.WriteLine($"Build successful! ({(release ? "release" : "debug")}) [{FormatElapsed(sw.Elapsed)}]");

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

    /// <summary>
    /// Ensures that the generated MSBuild project files exist for a project directory.
    /// Returns the path to the generated .g.csproj file.
    /// Generated files: {name}.g.csproj, obj/project.g.props, global.json (if missing), NuGet.config (if missing)
    /// </summary>
    static string EnsureProjectFiles(string projectRoot, ProjectConfig config)
    {
        var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";

        // Pre-generate obj/project.g.props so first build uses correct values
        // (MSBuild evaluates imports before targets run, so without this the
        //  fallback defaults in Sdk.props would be used on first build)
        var objDir = Path.Combine(projectRoot, "obj");
        Directory.CreateDirectory(objDir);

        var outputType = config.OutputType?.ToLowerInvariant() switch
        {
            "library" => "Library",
            _ => "Exe"
        };

        var propsContent = $@"<Project xmlns=""http://schemas.microsoft.com/developer/msbuild/2003"">
  <PropertyGroup>
    <TargetFramework>{config.TargetFramework}</TargetFramework>
    <OutputType>{outputType}</OutputType>
    <AssemblyName>{projectName}</AssemblyName>
    <NSharpTestFramework>{config.TestFramework}</NSharpTestFramework>
  </PropertyGroup>
</Project>";
        File.WriteAllText(Path.Combine(objDir, "project.g.props"), propsContent);

        // Generate .g.csproj — one-liner, the SDK reads everything from project.yml
        var csprojPath = Path.Combine(projectRoot, $"{projectName}.g.csproj");
        File.WriteAllText(csprojPath, "<Project Sdk=\"NSharpLang.Sdk\" />\n");

        // Ensure global.json exists (pins SDK version for MSBuild resolution)
        var globalJsonPath = Path.Combine(projectRoot, "global.json");
        if (!File.Exists(globalJsonPath))
        {
            File.WriteAllText(globalJsonPath, @"{
  ""sdk"": {
    ""version"": ""9.0.100""
  },
  ""msbuild-sdks"": {
    ""NSharpLang.Sdk"": ""0.1.0""
  }
}
");
        }

        // Ensure NuGet.config exists (needed to resolve NSharpLang.Sdk from local feed)
        var nugetConfigPath = Path.Combine(projectRoot, "NuGet.config");
        if (!File.Exists(nugetConfigPath))
        {
            File.WriteAllText(nugetConfigPath, @"<?xml version=""1.0"" encoding=""utf-8""?>
<configuration>
  <packageSources>
    <clear />
    <add key=""nuget.org"" value=""https://api.nuget.org/v3/index.json"" />
    <add key=""nsharp-local"" value=""%HOME%/.nuget/local-feed"" />
  </packageSources>
</configuration>
");
        }

        return csprojPath;
    }

    static int BuildWithMSBuild(string projectRoot, bool keepGenerated = false, bool excludeTests = true, bool release = false, bool verbose = false)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            Console.WriteLine($"Building project in {projectRoot}...");

            // Check for project.yml
            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return Error("No project.yml found in current directory. Run 'nlc new <name>' to create a project, or 'nlc build <file.nl>' to build a single file.");
            }

            // Load project config and ensure generated MSBuild files exist
            var config = ProjectFileParser.Parse(projectYmlPath);
            var csprojPath = EnsureProjectFiles(projectRoot, config);

            // Build — pass NSharpExcludeTests to skip test compilation for production builds
            var buildArgs = $"build \"{csprojPath}\"";
            if (excludeTests) buildArgs += " -p:NSharpExcludeTests=true";
            if (release) buildArgs += " -c Release";
            if (verbose) buildArgs += " -v detailed";

            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = buildArgs,
                WorkingDirectory = projectRoot,
                UseShellExecute = false,
                RedirectStandardOutput = false,
                RedirectStandardError = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                Console.WriteLine($"  Build failed in {FormatElapsed(sw.Elapsed)}");
                return Error("Build failed");
            }

            Console.WriteLine($"Build successful! ({(release ? "release" : "debug")}) [{FormatElapsed(sw.Elapsed)}]");
            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Build failed: {ex.Message}");
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

    static int RunWithMSBuild(string projectRoot)
    {
        // Build first
        var buildResult = BuildWithMSBuild(projectRoot);
        if (buildResult != 0)
        {
            return buildResult;
        }

        try
        {
            // Load config to get project name and .g.csproj path
            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            var config = ProjectFileParser.Parse(projectYmlPath);
            var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";
            var csprojPath = Path.Combine(projectRoot, $"{projectName}.g.csproj");

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
    }

    static int PublishCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# Publish

Usage: nlc publish [options]

Package the project for distribution.

Options:
  --project <dir>         Project root directory (default: current directory)
  --configuration <cfg>   Build configuration (default: Release)
  --output <dir>          Output directory for published files
  --runtime <rid>         Target runtime (e.g., linux-x64, osx-arm64, win-x64)
  --self-contained        Publish as self-contained (includes .NET runtime)
  --help, -h              Show this help text

Examples:
  nlc publish
  nlc publish --configuration Release --runtime linux-x64 --self-contained
  nlc publish --output ./dist

Exit codes:
  0  Publish succeeded
  1  Publish failed");
            return 0;
        }

        var projectRoot = Path.GetFullPath(GetOptionValue(args, "--project") ?? Directory.GetCurrentDirectory());

        try
        {
            Console.WriteLine($"Publishing project in {projectRoot}...");

            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return Error("No project.yml found in current directory. Run 'nlc new <name>' to create a project.");
            }

            var config = ProjectFileParser.Parse(projectYmlPath);
            var csprojPath = EnsureProjectFiles(projectRoot, config);

            // Build publish arguments
            var publishArgs = new List<string> { "publish", $"\"{csprojPath}\"", "-p:NSharpExcludeTests=true" };

            var configuration = GetOptionValue(args, "--configuration") ?? GetOptionValue(args, "-c") ?? "Release";
            publishArgs.Add($"--configuration {configuration}");

            var output = GetOptionValue(args, "--output") ?? GetOptionValue(args, "-o");
            if (output != null)
                publishArgs.Add($"--output \"{output}\"");

            var runtime = GetOptionValue(args, "--runtime") ?? GetOptionValue(args, "-r");
            if (runtime != null)
                publishArgs.Add($"--runtime \"{runtime}\"");

            if (args.Contains("--self-contained"))
                publishArgs.Add("--self-contained");

            var publishResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = string.Join(" ", publishArgs),
                WorkingDirectory = projectRoot,
                UseShellExecute = false,
                RedirectStandardOutput = false,
                RedirectStandardError = false
            });

            publishResult?.WaitForExit();

            if (publishResult?.ExitCode != 0)
            {
                return Error("Publish failed");
            }

            Console.WriteLine("Publish successful!");
            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Publish failed: {ex.Message}");
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

Create a new N# project with `project.yml` and `Program.nl`.
No .csproj file is created — the toolchain generates it automatically.

Examples:
  nlc new MyApp
  cd MyApp && nlc build

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
            Console.WriteLine($"  nlc build");
            Console.WriteLine($"  nlc run");
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

Run `.tests.nl` suites through the generated test project.

Options:
  --project <dir>       Project root directory (default: current directory)
  --filter <name>       Run only tests whose display name or fully-qualified name matches
  --verbose             Use more detailed `dotnet test` output
  --json                Output results as structured JSON (schemaVersion 1 envelope)
  --coverage            Collect code coverage using Coverlet and print a summary
  --coverage-report     Also generate an HTML coverage report (implies --coverage)
  --help, -h            Show this help text

The test framework is configured in project.yml via the `testFramework` field.
Supported values: xunit (default), nunit

Examples:
  nlc test
  nlc test --filter AddPerson
  nlc test --coverage
  nlc test --project examples/16-task-cli --verbose
  nlc test --json
  nlc test --coverage
  nlc test --coverage --coverage-report

Exit codes:
  0  Tests passed
  1  Compilation or test execution failed");
            return 0;
        }

        var projectRoot = GetOptionValue(args, "--project") ?? Directory.GetCurrentDirectory();
        projectRoot = Path.GetFullPath(projectRoot);
        var filter = GetOptionValue(args, "--filter");
        var verbose = args.Contains("--verbose");
        var jsonOutput = args.Contains("--json");
        var coverageReport = args.Contains("--coverage-report");
        var collectCoverage = args.Contains("--coverage") || coverageReport;

        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            if (!jsonOutput) Console.WriteLine($"Testing project in {projectRoot}...");

            // Find all .tests.nl files
            var testFiles = Directory.GetFiles(projectRoot, "*.tests.nl", SearchOption.AllDirectories);

            if (testFiles.Length == 0)
            {
                if (jsonOutput)
                {
                    OutputTestJson(null, projectRoot, true);
                    return 0;
                }
                Console.WriteLine("No test files (*.tests.nl) found.");
                return 0;
            }

            if (!jsonOutput) Console.WriteLine($"Found {testFiles.Length} test file(s)");

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
                if (!jsonOutput) Console.WriteLine("Building main project first...");

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
                    var msg = $"Main project compilation failed with {mainResult.Errors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)";
                    if (jsonOutput) { OutputTestJson(null, projectRoot, false, msg); return 1; }
                    return Error(msg);
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
                    var msg = $"Main project build failed:\n{error}{output}";
                    if (jsonOutput) { OutputTestJson(null, projectRoot, false, msg); return 1; }
                    return Error(msg);
                }

                mainProjectDll = Path.Combine(mainBuildDir, "bin", "Debug", projectConfig.TargetFramework, $"{projectConfig.EffectiveName}.dll");
                if (!jsonOutput) Console.WriteLine($"Main project built successfully: {mainProjectDll}");

                // Create a test config that includes reference to main project DLL
                var testConfig = new ProjectConfig
                {
                    Name = projectConfig.Name + ".Tests",
                    OutputType = "library",
                    TargetFramework = projectConfig.TargetFramework,
                    TestFramework = projectConfig.TestFramework,
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
                var msg = $"Compilation failed with {result.Errors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)";
                if (jsonOutput) { OutputTestJson(null, projectRoot, false, msg); return 1; }
                return Error(msg);
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
                var msg = $"Test build failed:\n{error}{output}";
                if (jsonOutput) { OutputTestJson(null, projectRoot, false, msg); return 1; }
            }

            if (!jsonOutput) Console.WriteLine();

            // Run tests
            var dotnetFilter = string.IsNullOrWhiteSpace(filter)
                ? null
                : $"DisplayName~{filter}|FullyQualifiedName~{filter}";
            var trxFile = Path.Combine(tempDir, "results.trx");
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

            // Add TRX logger for JSON output parsing
            if (jsonOutput)
            {
                testArguments.Add("--logger");
                testArguments.Add(QuoteArgument($"trx;LogFileName={trxFile}"));
            }

            // Add Coverlet properties for coverage
            if (collectCoverage)
            {
                var coverageOutputFile = Path.Combine(tempDir, "coverage.opencover.xml");
                testArguments.Add("--");
                testArguments.Add("/p:CollectCoverage=true");
                testArguments.Add("/p:CoverletOutputFormat=opencover");
                testArguments.Add($"/p:CoverletOutput={coverageOutputFile}");
                testArguments.Add("/p:ExcludeByFile=**/*.g.cs");
            }

            var testRunResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = string.Join(" ", testArguments),
                RedirectStandardOutput = jsonOutput,
                RedirectStandardError = jsonOutput,
                UseShellExecute = false
            });

            testRunResult?.WaitForExit();
            var exitCode = testRunResult?.ExitCode ?? 0;

            // JSON output: parse TRX and emit structured JSON
            if (jsonOutput)
            {
                OutputTestJson(trxFile, projectRoot, exitCode == 0);
            }

            // Coverage summary
            if (collectCoverage && !jsonOutput)
            {
                var coverageFile = Directory.GetFiles(tempDir, "coverage.opencover.xml", SearchOption.AllDirectories)
                    .FirstOrDefault();
                if (coverageFile != null && File.Exists(coverageFile))
                {
                    OutputCoverageSummary(coverageFile);

                    // Generate HTML report if requested
                    if (coverageReport)
                    {
                        var reportDir = Path.Combine(projectRoot, "coverage-report");
                        GenerateCoverageReport(coverageFile, reportDir);
                    }
                }
            }

            // Cleanup temp directories
            try
            {
                Directory.Delete(tempDir, true);
            }
            catch { /* best effort cleanup */ }

            if (!jsonOutput) Console.WriteLine($"  Tests completed in {FormatElapsed(sw.Elapsed)}");
            return exitCode;
        }
        catch (Exception ex)
        {
            if (!jsonOutput) Console.WriteLine($"  Tests failed in {FormatElapsed(sw.Elapsed)}");
            if (jsonOutput) { OutputTestJson(null, projectRoot, false, ex.Message); return 1; }
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

        var testFrameworkPackages = config.TestFramework == "nunit"
            ? @"<PackageReference Include=""Microsoft.NET.Test.Sdk"" Version=""17.11.1"" />
    <PackageReference Include=""NUnit"" Version=""4.3.2"" />
    <PackageReference Include=""NUnit3TestAdapter"" Version=""4.6.0"">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>"
            : @"<PackageReference Include=""Microsoft.NET.Test.Sdk"" Version=""17.11.1"" />
    <PackageReference Include=""xunit"" Version=""2.9.2"" />
    <PackageReference Include=""xunit.runner.visualstudio"" Version=""2.8.2"">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>";

        return $@"<Project Sdk=""Microsoft.NET.Sdk"">
  <PropertyGroup>
    <TargetFramework>{config.TargetFramework}</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    {testFrameworkPackages}
    <PackageReference Include=""coverlet.msbuild"" Version=""6.0.0"">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    <PackageReference Include=""coverlet.msbuild"" Version=""6.0.0"">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    {dependencies}
  </ItemGroup>{assemblyReference}
</Project>";
    }

    static void OutputTestJson(string? trxFile, string projectRoot, bool ok, string? errorMessage = null)
    {
        var results = new List<object>();
        int total = 0, passed = 0, failed = 0, skipped = 0;
        string duration = "0s";

        if (trxFile != null && File.Exists(trxFile))
        {
            try
            {
                var doc = System.Xml.Linq.XDocument.Load(trxFile);
                var ns = doc.Root?.Name.Namespace ?? System.Xml.Linq.XNamespace.None;

                // Parse test results
                var testResults = doc.Descendants(ns + "UnitTestResult");
                foreach (var tr in testResults)
                {
                    total++;
                    var outcome = tr.Attribute("outcome")?.Value ?? "Unknown";
                    switch (outcome.ToLower())
                    {
                        case "passed": passed++; break;
                        case "failed": failed++; break;
                        case "notexecuted": skipped++; break;
                    }

                    // Try to get the NSharpDescription trait
                    var testName = tr.Attribute("testName")?.Value ?? "";
                    var displayName = testName;

                    // Extract error message if failed
                    string? testErrorMsg = null;
                    var errorInfo = tr.Element(ns + "Output")?.Element(ns + "ErrorInfo");
                    if (errorInfo != null)
                    {
                        testErrorMsg = errorInfo.Element(ns + "Message")?.Value;
                    }

                    var testDuration = tr.Attribute("duration")?.Value ?? "00:00:00";
                    if (TimeSpan.TryParse(testDuration, out var ts))
                    {
                        testDuration = $"{ts.TotalSeconds:F3}s";
                    }

                    results.Add(new
                    {
                        name = testName,
                        displayName,
                        outcome = outcome.ToLower(),
                        duration = testDuration,
                        errorMessage = testErrorMsg
                    });
                }

                // Parse total duration from Times element
                var times = doc.Descendants(ns + "Times").FirstOrDefault();
                if (times != null)
                {
                    var start = times.Attribute("start")?.Value;
                    var finish = times.Attribute("finish")?.Value;
                    if (DateTime.TryParse(start, out var startDt) && DateTime.TryParse(finish, out var finishDt))
                    {
                        var totalDuration = finishDt - startDt;
                        duration = $"{totalDuration.TotalSeconds:F3}s";
                    }
                }
            }
            catch
            {
                // If TRX parsing fails, output minimal JSON
            }
        }

        var envelope = new
        {
            schemaVersion = 1,
            command = "test",
            ok,
            projectRoot = projectRoot.Replace('\\', '/'),
            error = errorMessage,
            summary = new { total, passed, failed, skipped, duration },
            results
        };

        var options = new System.Text.Json.JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
        };

        Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(envelope, options));
    }

    static void OutputCoverageSummary(string coverageFile)
    {
        try
        {
            var doc = System.Xml.Linq.XDocument.Load(coverageFile);
            var ns = doc.Root?.Name.Namespace ?? System.Xml.Linq.XNamespace.None;

            Console.WriteLine();
            Console.WriteLine("Coverage Summary:");
            Console.WriteLine(new string('-', 60));
            Console.WriteLine($"{"File",-40} {"Line%",8} {"Branch%",8}");
            Console.WriteLine(new string('-', 60));

            var modules = doc.Descendants(ns + "Module");
            foreach (var module in modules)
            {
                var classes = module.Descendants(ns + "Class");
                foreach (var cls in classes)
                {
                    var fullName = cls.Element(ns + "FullName")?.Value ?? "Unknown";
                    var shortName = fullName.Contains('.') ? fullName[(fullName.LastIndexOf('.') + 1)..] : fullName;

                    var methods = cls.Descendants(ns + "Method");
                    int totalLines = 0, coveredLines = 0, totalBranches = 0, coveredBranches = 0;

                    foreach (var method in methods)
                    {
                        var seqPoints = method.Descendants(ns + "SequencePoint");
                        foreach (var sp in seqPoints)
                        {
                            totalLines++;
                            var vc = int.Parse(sp.Attribute("vc")?.Value ?? "0");
                            if (vc > 0) coveredLines++;
                        }

                        var branchPoints = method.Descendants(ns + "BranchPoint");
                        foreach (var bp in branchPoints)
                        {
                            totalBranches++;
                            var vc = int.Parse(bp.Attribute("vc")?.Value ?? "0");
                            if (vc > 0) coveredBranches++;
                        }
                    }

                    var linePercent = totalLines > 0 ? (100.0 * coveredLines / totalLines) : 0;
                    var branchPercent = totalBranches > 0 ? (100.0 * coveredBranches / totalBranches) : 0;

                    Console.WriteLine($"{shortName,-40} {linePercent,7:F1}% {branchPercent,7:F1}%");
                }
            }

            Console.WriteLine(new string('-', 60));
        }
        catch
        {
            Console.Error.WriteLine("Warning: Could not parse coverage report.");
        }
    }

    static void GenerateCoverageReport(string coverageFile, string reportDir)
    {
        try
        {
            // Install reportgenerator as a global tool if not already installed
            var installResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = "tool install -g dotnet-reportgenerator-globaltool",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            });
            installResult?.WaitForExit();
            // Ignore exit code — tool may already be installed

            // Generate HTML report
            var reportResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "reportgenerator",
                Arguments = $"-reports:\"{coverageFile}\" -targetdir:\"{reportDir}\" -reporttypes:Html",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            });
            reportResult?.WaitForExit();

            if (reportResult?.ExitCode == 0)
            {
                Console.WriteLine();
                Console.WriteLine($"Coverage report generated: {reportDir}/index.html");
            }
            else
            {
                var error = reportResult?.StandardError.ReadToEnd() ?? "";
                Console.Error.WriteLine($"Warning: Could not generate HTML report. Install with: dotnet tool install -g dotnet-reportgenerator-globaltool");
                if (!string.IsNullOrWhiteSpace(error))
                    Console.Error.WriteLine(error);
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Warning: Could not generate HTML report: {ex.Message}");
            Console.Error.WriteLine("Install with: dotnet tool install -g dotnet-reportgenerator-globaltool");
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
  publish              Package for distribution
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
  test                 Run .tests.nl test suites (--coverage, --verbose)

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
  nlc build                    Compile the project
  nlc run                      Build and run
  nlc test                     Run tests
  nlc publish                  Package for distribution
  nlc check                    Fast feedback loop
  nlc fix && nlc check         Auto-fix then verify
  nlc build --release          Optimized release build
  nlc format --check           CI formatting gate
  nlc test --filter AddPerson  Run specific tests
  nlc test --coverage          Run tests with coverage
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

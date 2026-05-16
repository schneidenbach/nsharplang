using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using NSharpLang.Compiler;
using NSharpLang.Cli.Commands;

namespace NSharpLang.Cli;

partial class Program
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
            "new" => NewCommand(args.Skip(1).ToArray()),
            "test" => TestCommand(args.Skip(1).ToArray()),
            "format" => FormatCommand(args.Skip(1).ToArray()),
            "lint" => Commands.LintCommand.Execute(args.Skip(1).ToArray()),
            "restore" => RestoreCommand.Execute(args.Skip(1).ToArray()),
            "clean" => CleanCommand.Execute(args.Skip(1).ToArray()),
            "watch" => WatchCommand.Execute(args.Skip(1).ToArray()),
            "doc" => DocCommand.Execute(args.Skip(1).ToArray()),
            "completion" => CompletionCommand.Execute(args.Skip(1).ToArray()),
            "check" => Commands.CheckCommand.Execute(args.Skip(1).ToArray()),
            "fix" => FixCommand.Execute(args.Skip(1).ToArray()),
            "query" => QueryCommand.Execute(args.Skip(1).ToArray()),
            "daemon" => DaemonCommand.Execute(args.Skip(1).ToArray()),
            "add" => AddCommand.Execute(args.Skip(1).ToArray()),
            "tidy" => TidyCommand.Execute(args.Skip(1).ToArray()),
            "remove" => RemoveCommand.Execute(args.Skip(1).ToArray()),
            "update" => UpdateCommand.Execute(args.Skip(1).ToArray()),
            "init" => InitCommand.Execute(args.Skip(1).ToArray()),
            "env" => EnvCommand.Execute(args.Skip(1).ToArray()),
            "doctor" => DoctorCommand.Execute(args.Skip(1).ToArray()),
            "tree" => TreeCommand.Execute(args.Skip(1).ToArray()),
            "audit" => AuditCommand.Execute(args.Skip(1).ToArray()),
            "bench" => BenchCommand.Execute(args.Skip(1).ToArray()),
            "pack" => PackCommand.Execute(args.Skip(1).ToArray()),
            "export" => Commands.ExportCommand.Execute(args.Skip(1).ToArray()),
            "idiom" => IdiomCommand.Execute(args.Skip(1).ToArray()),
            "help" or "--help" or "-h" => ShowHelp(),
            "--version" => ShowVersion(),
            "transpile" => Error("The 'transpile' command has been removed. Use 'nlc export csharp' instead."),
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

When run in a directory with project.yml, dispatches through the configured
backend via the NSharpLang.Sdk. No user-authored .csproj is needed.

Options:
  --backend <mode>   Compilation backend: il
  --release          Build with Release configuration (default: Debug)
  --verbose          Show detailed build output
  --timings          Emit per-phase timing breakdown after build
  --output <path>    Output directory for build artifacts (-o shorthand)
  --help, -h         Show this help text

Examples:
  nlc build              Build the current project
  nlc build --backend il Build the current project with the IL backend
  nlc build --release    Optimized release build
  nlc build --verbose    Show detailed build output
  nlc build --timings    Show phase-level timing breakdown
  nlc build -o ./dist    Build to a specific output directory
  nlc build Program.nl   Build a single file

Exit codes:
  0  Build succeeded
  1  Build failed");
            return 0;
        }

        // Check for flags
        var release = args.Contains("--release");
        var verbose = args.Contains("--verbose");
        var timings = args.Contains("--timings");
        var outputDir = GetOptionValue(args, "--output") ?? GetOptionValue(args, "-o");
        var backendOption = GetOptionValue(args, "--backend");
        args = args.Where(a => a is not "--release" and not "--verbose" and not "--timings").ToArray();
        // Strip --output/-o and its value from positional args
        args = StripOptionWithValue(args, "--output");
        args = StripOptionWithValue(args, "-o");
        args = StripOptionWithValue(args, "--backend");

        try
        {
            // Support both single-file and multi-file builds
            if (args.Length == 0)
            {
                var projectRoot = Directory.GetCurrentDirectory();
                var currentProjectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
                var backend = ResolveCompilationBackend(backendOption, currentProjectConfig);
                return BuildWithMSBuild(
                    projectRoot,
                    release: release,
                    verbose: verbose,
                    outputDir: outputDir,
                    timings: timings,
                    backend: backend);
            }

            var sourceFile = args[0];
            if (!File.Exists(sourceFile))
            {
                return Error($"File not found: {sourceFile}");
            }

            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var sourceProjectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);
            _ = ResolveCompilationBackend(backendOption, sourceProjectConfig);
            return BuildSingleFileWithIlBackend(sourceFile, sourceProjectConfig, release, outputDir);
        }
        catch (Exception ex)
        {
            return Error($"Build failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Ensures that the generated MSBuild project files exist for a project directory.
    /// Returns the path to the generated .g.csproj file.
    /// Generated files: {name}.g.csproj, global.json (if missing), NuGet.config (if missing)
    /// NOTE: obj/project.g.props is generated by RestoreCommand.Restore(), not here.
    /// Callers must call Restore() before this method to ensure props are up to date.
    /// </summary>
    internal static string EnsureProjectFiles(string projectRoot, ProjectConfig config)
    {
        var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";

        // Generate .g.csproj — one-liner, the SDK reads everything from project.yml
        var csprojPath = Path.Combine(projectRoot, $"{projectName}.g.csproj");
        File.WriteAllText(csprojPath, "<Project Sdk=\"NSharpLang.Sdk\" />\n");

        // Ensure global.json exists (pins SDK version for MSBuild resolution)
        var globalJsonPath = Path.Combine(projectRoot, "global.json");
        if (!File.Exists(globalJsonPath))
        {
            File.WriteAllText(globalJsonPath, @"{
  ""sdk"": {
    ""version"": ""10.0.100"",
    ""rollForward"": ""latestFeature""
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

    static int BuildWithMSBuild(
        string projectRoot,
        bool excludeTests = true,
        bool release = false,
        bool verbose = false,
        string? outputDir = null,
        bool timings = false,
        CompilationBackend? backend = null)
    {
        var totalSw = System.Diagnostics.Stopwatch.StartNew();
        var prepareSw = new System.Diagnostics.Stopwatch();
        var compileSw = new System.Diagnostics.Stopwatch();
        try
        {
            Console.WriteLine($"Building project in {projectRoot}...");

            // Phase 1: Prepare generated MSBuild project files and backend config.
            prepareSw.Start();
            var restoreResult = RestoreCommand.Restore(projectRoot, quiet: true);
            if (restoreResult != 0)
            {
                return Error("No project.yml found in current directory. Run 'nlc new <name>' to create a project, or 'nlc build <file.nl>' to build a single file.");
            }

            // Load project config and ensure generated MSBuild files exist
            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            var config = ProjectFileParser.Parse(projectYmlPath);
            var csprojPath = EnsureProjectFiles(projectRoot, config);

            // Clean up stale .g.cs files from deleted .nl sources
            CleanStaleGeneratedFiles(projectRoot);
            prepareSw.Stop();

            // Phase 2: Compile (dotnet build)
            compileSw.Start();
            var buildArgs = $"build \"{csprojPath}\"";
            if (excludeTests) buildArgs += " -p:NSharpExcludeTests=true";
            if (release) buildArgs += " -c Release";
            if (verbose) buildArgs += " -v detailed";
            if (outputDir != null) buildArgs += $" --output \"{Path.GetFullPath(outputDir)}\"";
            if (backend.HasValue) buildArgs += $" {GetBackendMsBuildProperty(backend.Value)}";

            var buildExitCode = DotnetRunner.RunPassthrough(buildArgs, workingDirectory: projectRoot, verbose: verbose);
            compileSw.Stop();

            if (buildExitCode != 0)
            {
                Console.WriteLine($"  Build failed in {FormatElapsed(totalSw.Elapsed)}");
                return Error("Build failed");
            }

            Console.WriteLine($"Build successful! ({(release ? "release" : "debug")}) [{FormatElapsed(totalSw.Elapsed)}]");

            if (timings)
            {
                Console.Error.WriteLine($"""
Build timings:
  Prepare:    {FormatElapsed(prepareSw.Elapsed)}
  Compile:    {FormatElapsed(compileSw.Elapsed)}
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
            // Skip files inside obj/ and bin/
            var rel = Path.GetRelativePath(projectRoot, nlFile);
            if (rel.StartsWith("obj" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
                rel.StartsWith("bin" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                continue;

            // Strip .nl (or .tests.nl) extension to get the base name with relative dir
            var basePath = rel.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase)
                ? rel[..^".tests.nl".Length]
                : rel[..^".nl".Length];
            nlRelativePaths.Add(basePath.Replace('\\', '/'));
        }

        // Find all nsharp/ output directories under obj/
        // Search for both "nsharp" and "NSharp" to handle case-sensitive filesystems (Linux)
        var nsharpDirs = Directory.GetDirectories(objDir, "nsharp", SearchOption.AllDirectories)
            .Concat(Directory.GetDirectories(objDir, "NSharp", SearchOption.AllDirectories))
            .Distinct(StringComparer.Ordinal);
        foreach (var nsharpDir in nsharpDirs)
        {
            if (!Directory.Exists(nsharpDir))
                continue;

            foreach (var gcsFile in Directory.GetFiles(nsharpDir, "*.g.cs", SearchOption.AllDirectories))
            {
                // Generated files are named like Program.g.cs — strip .g.cs to get base name
                var relToNsharp = Path.GetRelativePath(nsharpDir, gcsFile).Replace('\\', '/');
                var basePath = relToNsharp;
                if (basePath.EndsWith(".g.cs", StringComparison.OrdinalIgnoreCase))
                    basePath = basePath[..^".g.cs".Length];

                if (!nlRelativePaths.Contains(basePath))
                {
                    try { File.Delete(gcsFile); } catch { /* ignore cleanup errors */ }
                }
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

    static int RunCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# Run

Usage: nlc run [file.nl]

Build and run either the current project or a single N# source file.

Options:
  --backend <mode>   Compilation backend: il
  --help, -h         Show this help text

Examples:
  nlc run
  nlc run --backend il
  nlc run Program.nl

Exit codes:
  0  Program ran successfully
  1  Build or execution failed");
            return 0;
        }

        var backendOption = GetOptionValue(args, "--backend");
        args = StripOptionWithValue(args, "--backend");

        try
        {
            if (args.Length == 0)
            {
                var projectRoot = Directory.GetCurrentDirectory();
                var currentProjectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
                var backend = ResolveCompilationBackend(backendOption, currentProjectConfig);
                return RunWithMSBuild(projectRoot, backend);
            }

            var sourceFile = args[0];
            if (!File.Exists(sourceFile))
            {
                return Error($"File not found: {sourceFile}");
            }

            Console.WriteLine($"Running {sourceFile}...");

            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var sourceProjectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);
            _ = ResolveCompilationBackend(backendOption, sourceProjectConfig);
            return RunSingleFileWithIlBackend(sourceFile, sourceProjectConfig);
        }
        catch (Exception ex)
        {
            return Error($"Run failed: {ex.Message}");
        }
    }

    static int RunWithMSBuild(string projectRoot, CompilationBackend backend)
    {
        // Build first
        var buildResult = BuildWithMSBuild(projectRoot, backend: backend);
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

            return DotnetRunner.RunPassthrough(
                $"run --project \"{csprojPath}\" --no-build {GetBackendMsBuildProperty(backend)}",
                workingDirectory: projectRoot);
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
  --backend <mode>        Compilation backend: il
  --configuration <cfg>   Build configuration (default: Release)
  --output <dir>          Output directory for published files
  --runtime <rid>         Target runtime (e.g., linux-x64, osx-arm64, win-x64)
  --self-contained        Publish as self-contained (includes .NET runtime)
  --help, -h              Show this help text

Examples:
  nlc publish
  nlc publish --backend il --output ./dist
  nlc publish --configuration Release --runtime linux-x64 --self-contained
  nlc publish --output ./dist

Exit codes:
  0  Publish succeeded
  1  Publish failed");
            return 0;
        }

        var projectRoot = Path.GetFullPath(GetOptionValue(args, "--project") ?? Directory.GetCurrentDirectory());
        var backendOption = GetOptionValue(args, "--backend");

        try
        {
            Console.WriteLine($"Publishing project in {projectRoot}...");

            var projectYmlPath = Path.Combine(projectRoot, "project.yml");
            if (!File.Exists(projectYmlPath))
            {
                return Error("No project.yml found in current directory. Run 'nlc new <name>' to create a project.");
            }

            var config = ProjectFileParser.Parse(projectYmlPath);
            var backend = ResolveCompilationBackend(backendOption, config);

            // Restore generates obj/project.g.props with all required MSBuild properties
            var restoreResult = RestoreCommand.Restore(projectRoot, quiet: true);
            if (restoreResult != 0)
            {
                return Error("Failed to restore project configuration.");
            }

            var csprojPath = EnsureProjectFiles(projectRoot, config);

            // Clean up stale .g.cs files from deleted .nl sources
            CleanStaleGeneratedFiles(projectRoot);

            // Build publish arguments
            var publishArgs = new List<string> { "publish", $"\"{csprojPath}\"", "-p:NSharpExcludeTests=true" };
            publishArgs.Add(GetBackendMsBuildProperty(backend));

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

            var publishExitCode = DotnetRunner.RunPassthrough(
                string.Join(" ", publishArgs),
                workingDirectory: projectRoot);

            if (publishExitCode != 0)
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

    static int NewCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# New Project

Usage: nlc new <project-name> [--template <template>]

Create a new csproj-free N# project. Fresh projects are project.yml-first:
`nlc build`, `nlc run`, and `nlc test` generate the minimal *.g.csproj MSBuild
entry point when needed. Do not hand-author project build settings in .csproj.

Options:
  --template <template>  Project template: console, library, test, webapi (default: console)
  --type <template>      Alias for --template
  --help, -h             Show this help text

Examples:
  nlc new MyApp
  nlc new MyLib --template library
  nlc new MyApi --template webapi
  cd MyApp && nlc build

Exit codes:
  0  Project created successfully
  1  Project creation failed");
            return 0;
        }

        var positional = GetPositionalArgs(args, "--template", "--type");
        if (positional.Length == 0)
        {
            return Error("Usage: nlc new <project-name> [--template <template>]");
        }

        var projectName = positional[0];
        var template = NormalizeProjectTemplate(GetOptionValue(args, "--template") ?? GetOptionValue(args, "--type") ?? "console");
        if (template == null)
        {
            return Error("Invalid template. Expected one of: console, library, test, webapi.");
        }

        var projectDir = Path.Combine(Directory.GetCurrentDirectory(), projectName);

        if (Directory.Exists(projectDir))
        {
            return Error($"Directory already exists: {projectDir}. Use a different name or remove the existing directory.");
        }

        try
        {
            Console.WriteLine($"Creating new {template} project: {projectName}");

            Directory.CreateDirectory(projectDir);
            WriteCanonicalProject(projectDir, projectName, template);

            Console.WriteLine($"Created: {projectName}/project.yml");
            Console.WriteLine($"Created: {projectName}/global.json");
            Console.WriteLine($"Created: {projectName}/NuGet.config");
            foreach (var file in GetTemplateSourceFiles(template))
            {
                Console.WriteLine($"Created: {projectName}/{file}");
            }

            Console.WriteLine();
            Console.WriteLine("Project shape: csproj-free source tree; nlc generates a minimal .g.csproj at build time.");
            var nextCommand = template switch
            {
                "test" => "  nlc test",
                "library" => null,
                _ => "  nlc run",
            };
            Console.WriteLine(template switch
            {
                "test" => "To build and test your project:",
                "library" => "To build your project:",
                _ => "To build and run your project:",
            });
            Console.WriteLine($"  cd {projectName}");
            Console.WriteLine("  nlc build");
            if (nextCommand != null)
                Console.WriteLine(nextCommand);
            Console.WriteLine();

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Failed to create project: {ex.Message}");
        }
    }

    static string[] GetTemplateSourceFiles(string template) => template switch
    {
        "console" => new[] { "Program.nl" },
        "library" => new[] { "Calculator.nl" },
        "test" => new[] { "Calculator.nl", "Calculator.tests.nl" },
        "webapi" => new[] { "Program.nl", "Controllers/WeatherController.nl" },
        _ => Array.Empty<string>(),
    };

    static string? NormalizeProjectTemplate(string value)
    {
        return value.Trim().ToLowerInvariant() switch
        {
            "console" or "exe" or "app" => "console",
            "library" or "lib" => "library",
            "test" or "tests" => "test",
            "webapi" or "web-api" or "web" => "webapi",
            _ => null,
        };
    }

    static void WriteCanonicalProject(string projectDir, string projectName, string template)
    {
        File.WriteAllText(Path.Combine(projectDir, "project.yml"), GenerateProjectYaml(projectName, template));
        WriteSdkSupportFiles(projectDir);

        switch (template)
        {
            case "console":
                File.WriteAllText(Path.Combine(projectDir, "Program.nl"), ConsoleProgramSource);
                break;
            case "library":
                File.WriteAllText(Path.Combine(projectDir, "Calculator.nl"), CalculatorSource);
                break;
            case "test":
                File.WriteAllText(Path.Combine(projectDir, "Calculator.nl"), CalculatorSource);
                File.WriteAllText(Path.Combine(projectDir, "Calculator.tests.nl"), CalculatorTestsSource);
                break;
            case "webapi":
                Directory.CreateDirectory(Path.Combine(projectDir, "Controllers"));
                File.WriteAllText(Path.Combine(projectDir, "Program.nl"), WebApiProgramSource);
                File.WriteAllText(Path.Combine(projectDir, "Controllers", "WeatherController.nl"), WebApiControllerSource);
                break;
        }
    }

    static void WriteSdkSupportFiles(string projectDir)
    {
        File.WriteAllText(Path.Combine(projectDir, "global.json"), GlobalJsonContent);
        File.WriteAllText(Path.Combine(projectDir, "NuGet.config"), NuGetConfigContent);
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
            _ => ProjectFileParser.GenerateTemplate(projectName),
        };
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

    const string NuGetConfigContent = @"<?xml version=""1.0"" encoding=""utf-8""?>
<configuration>
  <packageSources>
    <clear />
    <add key=""nuget.org"" value=""https://api.nuget.org/v3/index.json"" />
    <add key=""nsharp-local"" value=""%HOME%/.nuget/local-feed"" />
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

    static int TestCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# Test

Usage: nlc test [options]

Run `.tests.nl` suites through the IL compilation backend.

Options:
  --project <dir>       Project root directory (default: current directory)
  --backend <mode>      Compilation backend: il
  --filter <name>       Run only tests whose display name or fully-qualified name matches
  --verbose             Use more detailed `dotnet test` output
  --json                Output results as structured JSON (schemaVersion 1 envelope)
  --timeout <duration>  Test timeout per assembly (e.g., 30s, 5m, 1h). Default: no timeout
  --no-cache            Force clean rebuild before running tests (bypass incremental build)
  --coverage            Collect code coverage using Coverlet and print a summary
  --coverage-report     Also generate an HTML coverage report (implies --coverage)
  --help, -h            Show this help text

The test framework is configured in project.yml via the `testFramework` field.
Supported values: xunit (default), nunit

Examples:
  nlc test
  nlc test --backend il
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
        var timeoutStr = GetOptionValue(args, "--timeout");
        var noCache = args.Contains("--no-cache");
        var backendOption = GetOptionValue(args, "--backend");

        // Parse timeout to milliseconds
        int? timeoutMs = null;
        if (timeoutStr != null)
        {
            timeoutMs = ParseDurationToMs(timeoutStr);
            if (timeoutMs == null)
                return Error($"Invalid timeout format '{timeoutStr}'. Expected a duration like 30s, 5m, or 1h.");
        }

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

            var projectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
            _ = ResolveCompilationBackend(backendOption, projectConfig);

            return TestWithIlBackend(
                projectRoot,
                projectConfig,
                filter,
                verbose,
                jsonOutput,
                timeoutMs,
                noCache,
                collectCoverage,
                coverageReport,
                sw);
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

                // Build a lookup of test ID → NSharpDescription trait from TestDefinitions
                var traitLookup = new Dictionary<string, string>();
                foreach (var unitTest in doc.Descendants(ns + "UnitTest"))
                {
                    var testId = unitTest.Attribute("id")?.Value;
                    if (testId == null) continue;

                    var properties = unitTest.Descendants(ns + "Property");
                    foreach (var prop in properties)
                    {
                        var key = prop.Element(ns + "Key")?.Value;
                        var value = prop.Element(ns + "Value")?.Value;
                        if (key == "NSharpDescription" && value != null)
                        {
                            traitLookup[testId] = value;
                            break;
                        }
                    }
                }

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

                    var testName = tr.Attribute("testName")?.Value ?? "";
                    var displayName = testName;
                    var testId = tr.Attribute("testId")?.Value ?? "";

                    // Look up the NSharpDescription trait for this test
                    string? nsharpDescription = null;
                    if (testId != "" && traitLookup.TryGetValue(testId, out var desc))
                    {
                        nsharpDescription = desc;
                    }

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
                        errorMessage = testErrorMsg,
                        nsharpDescription
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
            DotnetRunner.Run("tool install -g dotnet-reportgenerator-globaltool");
            // Ignore exit code — tool may already be installed

            // Generate HTML report
            var reportResult = DotnetRunner.RunProcess(
                "reportgenerator",
                $"-reports:\"{coverageFile}\" -targetdir:\"{reportDir}\" -reporttypes:Html");

            if (reportResult.ExitCode == 0)
            {
                Console.WriteLine();
                Console.WriteLine($"Coverage report generated: {reportDir}/index.html");
            }
            else
            {
                Console.Error.WriteLine($"Warning: Could not generate HTML report. Install with: dotnet tool install -g dotnet-reportgenerator-globaltool");
                if (!string.IsNullOrWhiteSpace(reportResult.Stderr))
                    Console.Error.WriteLine(reportResult.Stderr);
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
                if (!file.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase)
                    && ShouldFormatDiscoveredFile(projectRoot, file))
                {
                    yield return file;
                }
            }
        }
    }

    static bool ShouldSkipDiscoveredDirectory(string directory)
    {
        var name = Path.GetFileName(directory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
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

    static int? ParseDurationToMs(string duration)
    {
        if (string.IsNullOrWhiteSpace(duration)) return null;

        var trimmed = duration.Trim();
        if (trimmed.Length < 2) return null;

        var unit = trimmed[^1];
        if (!int.TryParse(trimmed[..^1], out var value) || value <= 0)
            return null;

        return unit switch
        {
            's' => value * 1000,
            'm' => value * 60 * 1000,
            'h' => value * 60 * 60 * 1000,
            _ => null
        };
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
  restore              Generate build config from project.yml
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
  test                 Run .tests.nl test suites (--coverage, --verbose)
  bench                Run benchmarks

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
  idiom                Score migration idioms and emit a JSON report
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
  nlc build --release          Optimized release build
  nlc export csharp --project . -o ./myapp-csharp
                               Export a C# migration bundle
  nlc format --check           CI formatting gate
  nlc test --filter AddPerson  Run specific tests
  nlc test --coverage          Run tests with coverage
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

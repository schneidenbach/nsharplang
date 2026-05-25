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
            "tutorial" => TutorialCommand.Execute(args.Skip(1).ToArray()),
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

When run in a directory with project.yml, compiles directly from project.yml
through the native IL backend. No user-authored .csproj is needed.

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
                if (backend != CompilationBackend.Il)
                {
                    throw new InvalidOperationException(CompilationBackendExtensions.RetiredTranspileBackendMessage);
                }

                return BuildWithIlBackend(projectRoot, release, outputDir, timings, verbose);
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
                if (backend != CompilationBackend.Il)
                {
                    throw new InvalidOperationException(CompilationBackendExtensions.RetiredTranspileBackendMessage);
                }

                return RunWithIlBackend(projectRoot);
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
            if (backend != CompilationBackend.Il)
            {
                throw new InvalidOperationException(CompilationBackendExtensions.RetiredTranspileBackendMessage);
            }

            var configuration = GetOptionValue(args, "--configuration") ?? GetOptionValue(args, "-c") ?? "Release";
            var output = GetOptionValue(args, "--output") ?? GetOptionValue(args, "-o");
            var runtime = GetOptionValue(args, "--runtime") ?? GetOptionValue(args, "-r");
            var selfContained = args.Contains("--self-contained");
            if (selfContained && string.IsNullOrWhiteSpace(runtime))
            {
                return Error("Self-contained publish requires --runtime <rid>.");
            }

            var publishDir = output != null
                ? Path.GetFullPath(output)
                : Path.Combine(projectRoot, "bin", configuration, config.TargetFramework, "publish");

            var outputPath = BuildProjectWithIlBackendForCommand(
                projectRoot,
                config,
                configuration,
                publishDir,
                includeTests: false);
            if (outputPath == null)
            {
                return Error("Publish failed");
            }

            if (!string.IsNullOrWhiteSpace(runtime))
            {
                WriteDotnetLauncher(publishDir, CompilationReferenceResolver.GetProjectAssemblyName(projectRoot, config));
            }

            if (selfContained)
            {
                CopySelfContainedRuntime(config, publishDir);
            }

            Console.WriteLine("Publish successful!");
            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Publish failed: {ex.Message}");
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

    private static void CopySelfContainedRuntime(ProjectConfig config, string outputDirectory)
    {
        foreach (var frameworkDirectory in CompilationReferenceResolver.GetRuntimeFrameworkDirectories(config))
        {
            foreach (var file in Directory.GetFiles(frameworkDirectory, "*", SearchOption.TopDirectoryOnly))
            {
                File.Copy(file, Path.Combine(outputDirectory, Path.GetFileName(file)), overwrite: true);
            }
        }
    }

    static int NewCommand(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            Console.WriteLine(@"N# New Project

Usage: nlc new <project-name> [--template <template>]

Create a new csproj-free N# project. Fresh projects are project.yml-first:
`nlc build`, `nlc run`, and `nlc test` build directly from project.yml.
Do not hand-author project build settings in .csproj.

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
            Console.WriteLine("Project shape: csproj-free source tree; nlc builds directly from project.yml.");
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
  --verbose             Show individual test results
  --json                Output results as structured JSON (schemaVersion 1 envelope)
  --timeout <duration>  Test timeout per assembly (e.g., 30s, 5m, 1h). Default: no timeout
  --no-cache            Force clean rebuild before running tests (bypass incremental build)
  --help, -h            Show this help text

The test framework is configured in project.yml via the `testFramework` field.
Supported values: xunit (default), nunit

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
                    OutputNativeTestJson(projectRoot, true, Array.Empty<NativeTestResult>());
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
            if (jsonOutput) { OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), ex.Message); return 1; }
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
  restore              Generate MSBuild compatibility config from project.yml
  publish              Publish project for deployment
  pack                 Create a NuGet package from project.yml metadata
  clean                Remove build artifacts

Analysis & Fix:
  check                Fast type-check (JSON by default)
  fix                  Auto-apply compiler suggestions
  query <cmd>          Code intelligence for LLMs and terminals
  daemon <cmd>         Background analysis daemon
  tutorial             Start the local interactive N# tutorial

Code Quality:
  format [files...]    Format .nl source files
  lint [files...]      Run static analysis rules
  test                 Run .tests.nl test suites (--filter, --verbose)
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
  tutorial             Local 15-minute walkthrough with N# tooling

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
  nlc tutorial                 Open the local guided language walkthrough
  nlc fix && nlc check         Auto-fix then verify
  nlc build --release          Optimized release build
  nlc export csharp --project . -o ./myapp-csharp
                               Export a C# migration bundle
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

using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using Xunit;

namespace NSharpLang.Tests;

public class ExportCommandTests
{
    [Fact]
    public void ExportCommand_SingleFile_WritesCSharpToStdout()
    {
        var tempDir = CreateTempDir();
        try
        {
            var sourceFile = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourceFile, """
func main() {
    print "hello export"
}
""");

            var result = RunCliCommand($"\"{GetCliAssemblyPath()}\" export csharp \"{sourceFile}\"");

            Assert.Equal(0, result.ExitCode);
            Assert.True(string.IsNullOrWhiteSpace(result.Stderr), result.Stderr);
            Assert.Contains("static void Main", result.Stdout);
            Assert.Contains("Console.WriteLine", result.Stdout);
            Assert.Contains("hello export", result.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void ExportCommand_ReturnInsideFinally_FailsAtAnalysisWithNL319()
    {
        // The export backend shares the analyzer, so this must fail with the N# diagnostic at export
        // time — before NL319 the export emitted the return-in-finally verbatim and `dotnet build`
        // of the bundle leaked Roslyn's raw CS0157 instead of an N# error.
        var tempDir = CreateTempDir();
        try
        {
            var sourceFile = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourceFile, """
func main() {
    n := 0
    try {
        n = n + 1
    } finally {
        return
    }
}
""");

            var result = RunCliCommand($"\"{GetCliAssemblyPath()}\" export csharp \"{sourceFile}\"");

            Assert.NotEqual(0, result.ExitCode);
            var combined = result.Stdout + result.Stderr;
            Assert.Contains("NL319", combined);
            Assert.DoesNotContain("CS0157", combined);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void ExportCommand_ProjectBundle_BuildsRunsAndTestsAsCSharp()
    {
        var tempDir = CreateTempDir();
        try
        {
            var sharedDir = Path.Combine(tempDir, "Shared");
            var appDir = Path.Combine(tempDir, "App");
            var bundleDir = Path.Combine(tempDir, "csharp-export");
            Directory.CreateDirectory(sharedDir);
            Directory.CreateDirectory(appDir);
            File.WriteAllText(Path.Combine(sharedDir, "SharedGreeter.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n");
            File.WriteAllText(Path.Combine(appDir, "ExportedApp.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n");

            File.WriteAllText(Path.Combine(sharedDir, "project.yml"), """
name: SharedGreeter
outputType: library
targetFramework: net10.0
""");
            // ScratchLength and Score pin export-compile parity for IL-backend constructs that
            // previously transpiled to invalid C# (F1): an inferred stackalloc declaration
            // (`var x = stackalloc ...` is CS0214) and union case construction (object
            // initializer on a positional record is CS7036).
            File.WriteAllText(Path.Combine(sharedDir, "Greeter.nl"), """
namespace SharedGreeter

union Verdict {
    Pass { score: int }
    Fail { reason: string }
}

class Greeter {
    static func Message(): string {
        return "hello export"
    }

    static func ScratchLength(): int {
        scratch := stackalloc byte[4]
        return scratch.Length
    }

    static func Score(): int {
        verdict := new Verdict.Pass { score: 42 }
        return match verdict {
            Verdict.Pass { score } => score,
            Verdict.Fail { reason } => 0
        }
    }
}
""");

            File.WriteAllText(Path.Combine(appDir, "project.yml"), """
name: ExportedApp
outputType: exe
targetFramework: net10.0
dependencies:
  - project: ../Shared/project.yml
""");
            File.WriteAllText(Path.Combine(appDir, "Program.nl"), """
import SharedGreeter

func main() {
    print Greeter.Message()
}
""");
            File.WriteAllText(Path.Combine(appDir, "Program.tests.nl"), """
import SharedGreeter

test "shared greeter exports cleanly" {
    assert Greeter.Message() == "hello export"
}

test "inferred stackalloc exports cleanly" {
    assert Greeter.ScratchLength() == 4
}

test "union case construction exports cleanly" {
    assert Greeter.Score() == 42
}
""");

            var exportResult = RunCliCommand(
                $"\"{GetCliAssemblyPath()}\" export csharp --project \"{appDir}\" --output \"{bundleDir}\"",
                workingDirectory: appDir,
                timeout: TimeSpan.FromMinutes(5));

            Assert.Equal(0, exportResult.ExitCode);
            Assert.True(string.IsNullOrWhiteSpace(exportResult.Stderr), exportResult.Stderr);
            Assert.Contains("Exported ExportedApp", exportResult.Stdout);

            var appCsproj = Path.Combine(bundleDir, "ExportedApp", "ExportedApp.csproj");
            var testCsproj = Path.Combine(bundleDir, "ExportedApp.Tests", "ExportedApp.Tests.csproj");
            var exportedReference = Directory.GetFiles(
                Path.Combine(bundleDir, "_nsharp_refs"),
                "SharedGreeter.csproj",
                SearchOption.AllDirectories).Single();

            Assert.True(File.Exists(appCsproj));
            Assert.True(File.Exists(testCsproj));
            Assert.True(File.Exists(exportedReference));

            var buildResult = DotnetRunner.Run(
                $"build \"{appCsproj}\" -v q --disable-build-servers",
                workingDirectory: bundleDir,
                timeout: TimeSpan.FromMinutes(5));
            Assert.True(
                buildResult.ExitCode == 0,
                $"stdout:{Environment.NewLine}{buildResult.Stdout}{Environment.NewLine}stderr:{Environment.NewLine}{buildResult.Stderr}");

            var assemblyPath = Path.Combine(bundleDir, "ExportedApp", "bin", "Debug", "net10.0", "ExportedApp.dll");
            Assert.True(File.Exists(assemblyPath));
            var executablePath = Path.Combine(
                Path.GetDirectoryName(assemblyPath)!,
                $"ExportedApp{(RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? ".exe" : string.Empty)}");
            Assert.True(File.Exists(executablePath), $"Exported executable not found at {executablePath}");

            var runResult = DotnetRunner.RunProcess(
                executablePath,
                string.Empty,
                workingDirectory: Path.GetDirectoryName(executablePath),
                timeout: TimeSpan.FromMinutes(3));
            Assert.True(
                runResult.ExitCode == 0,
                $"stdout:{Environment.NewLine}{runResult.Stdout}{Environment.NewLine}stderr:{Environment.NewLine}{runResult.Stderr}");
            Assert.Contains("hello export", runResult.Stdout);

            var testResult = DotnetRunner.Run(
                $"test \"{testCsproj}\" -v q --disable-build-servers",
                workingDirectory: bundleDir,
                timeout: TimeSpan.FromMinutes(5));
            Assert.True(
                testResult.ExitCode == 0,
                $"stdout:{Environment.NewLine}{testResult.Stdout}{Environment.NewLine}stderr:{Environment.NewLine}{testResult.Stderr}");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    private static DotnetRunner.RunResult RunCliCommand(string arguments, string? workingDirectory = null, TimeSpan? timeout = null)
        => DotnetRunner.Run(arguments, workingDirectory: workingDirectory, timeout: timeout);

    private static string GetCliAssemblyPath()
    {
        var cliAssemblyPath = typeof(CheckCommand).Assembly.Location;
        Assert.True(File.Exists(cliAssemblyPath), $"CLI assembly not found at {cliAssemblyPath}");
        return cliAssemblyPath;
    }

    private static string CreateTempDir()
    {
        var path = Path.Combine(Path.GetTempPath(), $"nsharp-export-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }
}

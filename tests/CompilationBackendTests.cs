using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class CompilationBackendTests
{
    [Fact]
    public void CheckCommand_UsesConfiguredIlBackendVerification()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CheckIl
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "checked"
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_UsesConfiguredIlBackendAndProducesRunnableArtifacts()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: BuildIl
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "built with il"
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "-o", outputDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var assemblyPath = Path.Combine(outputDir, "BuildIl.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(outputDir, "BuildIl.runtimeconfig.json")));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("built with il", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_SingleFileSourceAfterOptions_BuildsWithIlBackend()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            var sourcePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourcePath, """
func main(): int {
    return 0
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--backend", "il", "--output", outputDir, sourcePath));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.True(File.Exists(Path.Combine(outputDir, "Program.dll")));
            Assert.True(File.Exists(Path.Combine(outputDir, "Program.runtimeconfig.json")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_SingleFileRequiresColumnarEmissionWhenColumnarDeclines()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            var sourcePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourcePath, """
func CountChars(s: string): int {
    n := 0
    foreach c in s {
        n = n + 1
    }
    return n
}

func main() {
    print CountChars("abc")
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--backend", "il", "--output", outputDir, sourcePath));

            Assert.Equal(1, exitCode);
            Assert.Contains("Building", stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_DefineFlagsDriveConditionalCompilation()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CliDefineBuild
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    #if FEATURE_X
    print "feature-on"
    #else
    print "feature-off"
    #endif

    #if SECOND
    print "second-on"
    #endif
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram(
                    "build",
                    "--define",
                    " FEATURE_X , SECOND ; FEATURE_X ",
                    "--backend",
                    "il",
                    "-o",
                    outputDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var assemblyPath = Path.Combine(outputDir, "CliDefineBuild.dll");
            Assert.True(File.Exists(assemblyPath));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("feature-on", runResult.Stdout);
            Assert.Contains("second-on", runResult.Stdout);
            Assert.DoesNotContain("feature-off", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_StrictLintError_BlocksIlBuild()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: StrictLintBuild
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    unused := 42
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "-o", outputDir));

            Assert.Equal(1, exitCode);
            Assert.Contains("Build failed", stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_ReleaseUsesReleaseOutputLayout()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ReleaseLayout
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "release layout"
}
""");

            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--release"));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful! (il, release)", stdout);
            Assert.Contains(NormalizePath(Path.Combine("bin", "Release", "net10.0", "ReleaseLayout.dll")), NormalizePath(stdout));
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.True(File.Exists(Path.Combine(tempDir, "bin", "Release", "net10.0", "ReleaseLayout.dll")));
            Assert.True(File.Exists(Path.Combine(tempDir, "bin", "Release", "net10.0", "ReleaseLayout.runtimeconfig.json")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_ProjectWithoutBackend_DefaultsToIlAndProducesRunnableArtifacts()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: BuildDefaultIl
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "default backend is il"
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "-o", outputDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.cs", SearchOption.AllDirectories));

            var assemblyPath = Path.Combine(outputDir, "BuildDefaultIl.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(outputDir, "BuildDefaultIl.runtimeconfig.json")));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("default backend is il", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void RunCommand_UsesConfiguredIlBackendAndExecutesProject()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RunIl
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "ran with il"
}
""");

            var cliDll = typeof(CheckCommand).Assembly.Location;
            var runResult = DotnetRunner.Run(
                $"\"{cliDll}\" run",
                workingDirectory: tempDir,
                timeout: TimeSpan.FromMinutes(5));

            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("Running...", runResult.Stdout);
            Assert.Contains("ran with il", runResult.Stdout);
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void RunCommand_SingleFileRequiresColumnarEmissionWhenColumnarDeclines()
    {
        var tempDir = CreateTempDir();
        try
        {
            var sourcePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourcePath, """
func CountChars(s: string): int {
    n := 0
    foreach c in s {
        n = n + 1
    }
    return n
}

func main() {
    print CountChars("abc")
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("run", "--backend", "il", sourcePath));

            Assert.Equal(1, exitCode);
            Assert.Contains("Running", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestCommand_UsesConfiguredIlBackendAndRunsExecutableProjectTests()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TestIl
backend: il
outputType: exe
targetFramework: net10.0
""");
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "testing"
}

func Add(a: int, b: int): int {
    return a + b
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.tests.nl"), """
test "addition works" {
    assert Add(2, 3) == 5
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("test", "--project", tempDir, "--json"));

            Assert.True(exitCode == 0, $"stdout:{Environment.NewLine}{stdout}{Environment.NewLine}stderr:{Environment.NewLine}{stderr}");
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("test", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(1, doc.RootElement.GetProperty("summary").GetProperty("passed").GetInt32());
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestCommand_CoverageJson_ReturnsUnsupportedErrorBeforeDiscovery()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CoverageUnavailable
backend: il
outputType: library
targetFramework: net10.0
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("test", "--project", tempDir, "--coverage", "--json"));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("test", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Contains("Coverage collection is not available in nlc test yet", doc.RootElement.GetProperty("error").GetString());
            Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("total").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PackCommand_UsesConfiguredIlBackendAndProducesNuGetPackage()
    {
        var tempDir = CreateTempDir();
        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackIl
backend: il
outputType: exe
targetFramework: net10.0
version: 1.2.3
package:
  description: IL-backed package
  author: NSharp
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main(): int {
    return 0
}
""");

            var outputDir = Path.Combine(tempDir, "artifacts");
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                PackCommand.Execute(new[] { "--project", tempDir, "--output", outputDir, "--json" }));

            Assert.True(exitCode == 0, $"stdout:{Environment.NewLine}{stdout}{Environment.NewLine}stderr:{Environment.NewLine}{stderr}");
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("pack", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());

            var packagePath = doc.RootElement.GetProperty("packagePath").GetString();
            Assert.False(string.IsNullOrWhiteSpace(packagePath));
            Assert.True(File.Exists(packagePath));

            using var package = ZipFile.OpenRead(packagePath!);
            Assert.Contains(package.Entries, entry => entry.FullName == "lib/net10.0/PackIl.dll");
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_BackendOverrideToIl_UsesSdkProjectReferencesAndRuntimeAssets()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            CreateProjectReferenceFixture(tempDir);
            var outputDir = Path.Combine(tempDir, "dist");

            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--backend", "il", "-o", outputDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var assemblyPath = Path.Combine(outputDir, "App.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(outputDir, "App.runtimeconfig.json")));
            Assert.True(File.Exists(Path.Combine(outputDir, "SharedLib.dll")));
            Assert.True(File.Exists(Path.Combine(outputDir, "Newtonsoft.Json.dll")));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
            Assert.Empty(Directory.GetFiles(Path.Combine(tempDir, "Shared"), "*.g.csproj", SearchOption.TopDirectoryOnly));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: outputDir, timeout: TimeSpan.FromMinutes(3));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("hello from shared", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_AotProjectReferenceRequiresColumnarWhenColumnarDeclines()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);

            var sharedDir = Path.Combine(tempDir, "Shared");
            Directory.CreateDirectory(sharedDir);
            TestSdkFeed.WriteVersionedSdkProject(sharedDir, "SharedLib");
            File.WriteAllText(Path.Combine(sharedDir, "project.yml"), """
name: SharedLib
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(sharedDir, "Shared.nl"), """
func CountChars(s: string): int {
    n := 0
    foreach c in s {
        n = n + 1
    }
    return n
}
""");

            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: App
outputType: exe
targetFramework: net10.0
dependencies:
  - project: Shared/project.yml
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "root"
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--backend", "il", "--aot", "-o", outputDir));

            Assert.Equal(1, exitCode);
            Assert.Contains("AOT builds require successful N# columnar emission", stdout + stderr);
            Assert.False(File.Exists(Path.Combine(outputDir, "SharedLib.dll")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_BackendOverrideToIl_UsesSdkProjectReferencesAndRuntimeAssets()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            CreateProjectReferenceFixture(tempDir);
            var publishDir = Path.Combine(tempDir, "publish");

            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("publish", "--backend", "il", "--output", publishDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Publish successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var assemblyPath = Path.Combine(publishDir, "App.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(publishDir, "App.runtimeconfig.json")));
            Assert.True(File.Exists(Path.Combine(publishDir, "SharedLib.dll")));
            Assert.True(File.Exists(Path.Combine(publishDir, "Newtonsoft.Json.dll")));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
            Assert.Empty(Directory.GetFiles(Path.Combine(tempDir, "Shared"), "*.g.csproj", SearchOption.TopDirectoryOnly));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: publishDir, timeout: TimeSpan.FromMinutes(3));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("hello from shared", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_BackendOverrideToIl_SupportsRuntimeSpecificOutput()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();
        var runtimeIdentifier = RuntimeInformation.RuntimeIdentifier;

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RuntimeSpecificIlPublish
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "runtime-specific il publish"
}
""");

            var publishDir = Path.Combine(tempDir, "publish-runtime");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("publish", "--backend", "il", "--runtime", runtimeIdentifier, "--output", publishDir));

            Assert.True(exitCode == 0, $"stdout:{Environment.NewLine}{stdout}{Environment.NewLine}stderr:{Environment.NewLine}{stderr}");
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);
            Assert.Contains("Publish successful!", stdout);

            var publishedApp = GetPublishedAppPath(publishDir, "RuntimeSpecificIlPublish");
            Assert.True(File.Exists(publishedApp), publishedApp);
            Assert.True(File.Exists(Path.Combine(publishDir, "RuntimeSpecificIlPublish.dll")));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));

            var runResult = DotnetRunner.RunProcess(publishedApp, "", workingDirectory: publishDir, timeout: TimeSpan.FromMinutes(3));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("runtime-specific il publish", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_SelfContainedOutput_ReturnsHelpfulUnsupportedMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();
        var runtimeIdentifier = RuntimeInformation.RuntimeIdentifier;

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: SelfContainedIlPublish
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "self-contained il publish"
}
""");

            var publishDir = Path.Combine(tempDir, "publish-self-contained");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram(
                    "publish",
                    "--backend", "il",
                    "--runtime", runtimeIdentifier,
                    "--self-contained",
                    "--output", publishDir));

            Assert.Equal(1, exitCode);
            Assert.Contains("Publishing project in", stdout);
            Assert.Contains("Self-contained publish is not available in nlc publish yet", stderr);
            Assert.Contains("framework-dependent artifacts", stderr);
            Assert.False(Directory.Exists(publishDir));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_CrossRuntimeOutput_ReturnsHelpfulUnsupportedMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();
        var requestedRuntime = GetDifferentRuntimeIdentifier();

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CrossRuntimeIlPublish
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "cross runtime il publish"
}
""");

            var publishDir = Path.Combine(tempDir, "publish-cross-runtime");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("publish", "--backend", "il", "--runtime", requestedRuntime, "--output", publishDir));

            Assert.Equal(1, exitCode);
            Assert.Contains("Publishing project in", stdout);
            Assert.Contains("Cross-runtime publish is not available in nlc publish yet", stderr);
            Assert.Contains($"Requested runtime '{requestedRuntime}'", stderr);
            Assert.Contains(RuntimeInformation.RuntimeIdentifier, stderr);
            Assert.False(Directory.Exists(publishDir));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_NoProjectFile_ReturnsHelpfulMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("publish", "--backend", "il"));

            Assert.Equal(1, exitCode);
            Assert.Contains("Publishing project in", stdout);
            Assert.Contains("No project.yml found in current directory. Run 'nlc new <name>' to create a project.", stderr);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestCommand_BackendOverrideToIl_RunsTestsThroughSdkProject()
    {
        var tempDir = CreateTempDir();
        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: OverrideIlTests
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "override"
}

func Add(a: int, b: int): int {
    return a + b
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.tests.nl"), """
test "override il tests" {
    assert Add(4, 5) == 9
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("test", "--project", tempDir, "--backend", "il", "--json"));

            Assert.True(exitCode == 0, $"stdout:{Environment.NewLine}{stdout}{Environment.NewLine}stderr:{Environment.NewLine}{stderr}");
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("test", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(1, doc.RootElement.GetProperty("summary").GetProperty("passed").GetInt32());
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }


    private static int ExecuteProgram(params string[] args)
    {
        var programType = typeof(CheckCommand).Assembly.GetType("NSharpLang.Cli.Program");
        Assert.NotNull(programType);

        var method = programType!.GetMethod("Execute", BindingFlags.Static | BindingFlags.NonPublic);
        Assert.NotNull(method);

        return (int)(method!.Invoke(null, new object[] { args }) ?? -1);
    }

    private static (int ExitCode, string Stdout, string Stderr) CaptureConsole(Func<int> action)
    {
        var originalOut = Console.Out;
        var originalError = Console.Error;

        using var stdout = new StringWriter();
        using var stderr = new StringWriter();

        Console.SetOut(stdout);
        Console.SetError(stderr);

        try
        {
            var exitCode = action();
            return (exitCode, stdout.ToString(), stderr.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetError(originalError);
        }
    }

    private static string CreateTempDir()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-backend-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        return tempDir;
    }

    private static string GetPublishedAppPath(string publishDir, string assemblyName)
    {
        var executableName = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            ? $"{assemblyName}.cmd"
            : assemblyName;
        return Path.Combine(publishDir, executableName);
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private static string GetDifferentRuntimeIdentifier()
    {
        var current = RuntimeInformation.RuntimeIdentifier;
        var candidates = new[] { "linux-x64", "osx-arm64", "win-x64" };
        return candidates.First(candidate => !string.Equals(candidate, current, StringComparison.OrdinalIgnoreCase));
    }

    private static void CreateProjectReferenceFixture(string projectRoot)
    {
        TestSdkFeed.WriteSdkResolutionFiles(projectRoot);

        var sharedDir = Path.Combine(projectRoot, "Shared");
        Directory.CreateDirectory(sharedDir);
        TestSdkFeed.WriteVersionedSdkProject(sharedDir, "SharedLib");

        File.WriteAllText(Path.Combine(sharedDir, "project.yml"), """
name: SharedLib
outputType: library
targetFramework: net10.0
""");
        File.WriteAllText(Path.Combine(sharedDir, "Shared.nl"), """
func Greeting(): string {
    return "hello from shared"
}
""");

        File.WriteAllText(Path.Combine(projectRoot, "project.yml"), """
name: App
outputType: exe
targetFramework: net10.0
dependencies:
  - project: Shared/project.yml
  - nuget: Newtonsoft.Json
    version: 13.0.3
""");
        File.WriteAllText(Path.Combine(projectRoot, "Program.nl"), """
import Newtonsoft.Json

func main() {
    print JsonConvert.SerializeObject(Greeting())
}
""");
    }
}

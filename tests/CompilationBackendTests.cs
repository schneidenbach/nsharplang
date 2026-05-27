using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class CompilationBackendTests
{
    [Fact]
    public void MultiFileCompiler_CanCompileExecutableProjectToIlAndRun()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: IlProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print Greeting()
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Greeting.nl"), """
func Greeting(): string {
    return "hello from il backend"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "IlProject.dll");
            var result = compiler.CompileToIlAssembly("IlProject", outputPath);

            Assert.True(result.Success);
            Assert.Equal(outputPath, result.OutputAssemblyPath);
            Assert.True(File.Exists(outputPath));

            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("hello from il backend", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanBuildPackageFirstSourceWithImports()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageFirstIlProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
package PackageFirst

import System

func main() {
    print DateTime.UnixEpoch.Year
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "PackageFirstIlProject.dll");
            var result = compiler.CompileToIlAssembly("PackageFirstIlProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("1970", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanRunRepeatedBlockLocalWithNamespaceQualifiedType()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RepeatedLocalIlProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models.nl"), """
namespace RepeatedLocal.Models

record Item {
    Name: string
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Services.nl"), """
namespace RepeatedLocal.Services

import System.Collections.Generic
import System.Linq
import RepeatedLocal.Models

class ItemService {
    items: List<Item>

    constructor() {
        items = new List<Item>()
        items.Add(new Item { Name: "first" })
        items.Add(new Item { Name: "second" })
    }

    func Filter(firstPass: bool, name: string): List<Item> {
        result := items.ToList()

        if firstPass {
            filtered := new List<Item>()
            for item in result {
                filtered.Add(item)
            }

            result = filtered
        }

        normalized := name.ToLower()
        if normalized.Length > 0 {
            filtered := new List<Item>()
            for item in result {
                if item.Name == normalized {
                    filtered.Add(item)
                }
            }

            result = filtered
        }

        return result
    }
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import RepeatedLocal.Services

func main() {
    service := new ItemService()
    print service.Filter(false, "SECOND").Count
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "RepeatedLocalIlProject.dll");
            var result = compiler.CompileToIlAssembly("RepeatedLocalIlProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("1", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_ReportsBadReflectionCallBeforeIlEmission()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: BadReflectionCall
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    greeting := "hello"
    greeting.CompareTo()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "BadReflectionCall.dll");
            var result = compiler.CompileToIlAssembly("BadReflectionCall", outputPath);

            Assert.False(result.Success);
            Assert.Contains(result.Errors, error => error.Code == ErrorCode.NoMatchingOverload);
            Assert.DoesNotContain(result.Errors, error => error.Message.Contains("Failed to emit IL assembly"));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanRunAsyncExecutableProjectEntryPoint()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: AsyncMainIlProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Threading.Tasks

async func main() {
    await Task.CompletedTask
    print "async entrypoint works"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "AsyncMainIlProject.dll");
            var result = compiler.CompileToIlAssembly("AsyncMainIlProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("async entrypoint works", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsIlAssemblyWithSdkCompatibleVersion()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: VersionedIlProject
backend: il
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Library.nl"), """
namespace Versioned

class Greeter {
    static func Message(): string {
        return "hello"
    }
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "VersionedIlProject.dll");
            var result = compiler.CompileToIlAssembly("VersionedIlProject", outputPath);

            Assert.True(result.Success);
            Assert.Equal(new Version(1, 0, 0, 0), AssemblyName.GetAssemblyName(outputPath).Version);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsNamespaceQualifiedTypesForIlProjects()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: NamespaceIlProject
backend: il
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "MathUtils.nl"), """
namespace InteropLib

class MathUtils {
    static func Add(a: int, b: int): int {
        return a + b
    }
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Geometry.nl"), """
namespace InteropLib.Geometry

interface IShape {
    func Area(): double
}

class Square : IShape {
    Side: double

    constructor(side: double) {
        Side = side
    }

    func Area(): double {
        return Side * Side
    }
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "NamespaceIlProject.dll");
            var result = compiler.CompileToIlAssembly("NamespaceIlProject", outputPath);

            Assert.True(result.Success);

            var assembly = Assembly.LoadFile(outputPath);
            Assert.NotNull(assembly.GetType("InteropLib.MathUtils", throwOnError: false));
            Assert.NotNull(assembly.GetType("InteropLib.Geometry.IShape", throwOnError: false));
            Assert.NotNull(assembly.GetType("InteropLib.Geometry.Square", throwOnError: false));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_AllowsIdentifierCallsToMethodsOnCurrentType()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CurrentTypeCalls
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class MathUtils {
    static func Factorial(n: int): long {
        if n <= 1 {
            return 1
        }

        return n * Factorial(n - 1)
    }
}

func main() {
    print MathUtils.Factorial(5)
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "CurrentTypeCalls.dll");
            var result = compiler.CompileToIlAssembly("CurrentTypeCalls", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("120", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_AllowsRecordPrimaryConstructorParametersInMembers()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RecordPrimaryCtorMembers
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
record Address(street: string, city: string, zip: string) {
    FullAddress: string => $"{street}, {city} {zip}"
}

func main() {
    address := new Address("123 Main St", "Springfield", "62701")
    print address.FullAddress
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "RecordPrimaryCtorMembers.dll");
            var result = compiler.CompileToIlAssembly("RecordPrimaryCtorMembers", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("123 Main St, Springfield 62701", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_AllowsRecordPrimaryConstructorParametersInNamespacedMultiDeclarationFiles()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RecordPrimaryCtorMembersNamespaced
backend: il
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models.nl"), """
namespace NSharpInteropLib.Models

record Person {
    Name: string
    Age: int
    Email: string

    func GetDisplayName(): string {
        return $"{Name} ({Age})"
    }
}

record Address(street: string, city: string, zip: string) {
    FullAddress: string => $"{street}, {city} {zip}"
}

class PersonService {
    people: System.Collections.Generic.List<Person>

    constructor() {
        people = new System.Collections.Generic.List<Person>()
    }

    func Add(person: Person) {
        people.Add(person)
    }

    func GetAll(): System.Collections.Generic.List<Person> {
        return people
    }

    Count: int => people.Count
}

enum Priority {
    Low = 0,
    Medium = 1,
    High = 2,
    Critical = 3
}

enum Status: string {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "RecordPrimaryCtorMembersNamespaced.dll");
            var result = compiler.CompileToIlAssembly("RecordPrimaryCtorMembersNamespaced", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.FormatForMsBuild())));

            var assembly = Assembly.LoadFile(outputPath);
            var addressType = assembly.GetType("NSharpInteropLib.Models.Address", throwOnError: true)!;
            var instance = Activator.CreateInstance(addressType, "123 Main St", "Springfield", "62701");
            var fullAddress = addressType.GetProperty("FullAddress")!.GetValue(instance);
            Assert.Equal("123 Main St, Springfield 62701", fullAddress);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

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
    public void BuildCommand_RetiredTranspileBackendOverride_IsRejected()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: LegacyBuild
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "legacy"
}
""");

            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--backend", "transpile"));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("removed", stderr);
            Assert.Contains("nlc export csharp", stderr);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
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
            Assert.Contains("NL001", stderr);
            Assert.Contains("Variable 'unused' is declared but never read", stderr);
            Assert.False(File.Exists(Path.Combine(outputDir, "StrictLintBuild.dll")));
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
outputType: library
targetFramework: net10.0
version: 1.2.3
package:
  description: IL-backed package
  author: NSharp
""");
            File.WriteAllText(Path.Combine(tempDir, "Library.nl"), """
namespace PackIl

class Greeter {
    static func Message(): string {
        return "packed"
    }
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

    [Fact]
    public void BenchCommand_BackendOverrideToIl_RunsBenchmarksThroughSdkProject()
    {
        var tempDir = CreateTempDir();
        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: BenchIl
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "math.bench.nl"), """
func benchAddNumbers(): int {
    return 1 + 2
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                BenchCommand.Execute(new[]
                {
                    "--project", tempDir,
                    "--backend", "il",
                    "--job", "dry",
                    "--filter", "benchAddNumbers",
                    "--json"
                }));

            Assert.True(exitCode == 0, $"stdout:{Environment.NewLine}{stdout}{Environment.NewLine}stderr:{Environment.NewLine}{stderr}");
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("bench", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.True(doc.RootElement.GetProperty("benchmarkCount").GetInt32() >= 1);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompilationStubEmitter_UsesSystemAndSuppressesFallbackMainForTypeEntryPoints()
    {
        var tempDir = CreateTempDir();
        try
        {
            var sourcePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourcePath, """
class Program {
    Timestamp: DateTime

    static func Main() {
    }
}
""");

            var stub = CompilationStubEmitter.Generate(
                new ProjectConfig
                {
                    Name = "StubMain",
                    OutputType = "exe",
                    TargetFramework = "net10.0"
                },
                new[] { sourcePath });

            Assert.Contains("using System;", stub);
            Assert.Contains("#pragma warning disable CS0649, CS8618", stub);
            Assert.DoesNotContain("internal static class __NSharpIlStub", stub);
            Assert.Contains("public static void Main()", stub);
            Assert.Contains("DateTime", stub);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompilationStubEmitter_EmitsDuckInterfacesReferencedByStubbedTypes()
    {
        var tempDir = CreateTempDir();
        try
        {
            var sourcePath = Path.Combine(tempDir, "Notifier.nl");
            File.WriteAllText(sourcePath, """
namespace IssueTracker

import System.Collections.Generic

duck interface INotifier {
    func Notify(message: string)
}

class NotifierHub {
    notifiers: List<INotifier>
}
""");

            var stub = CompilationStubEmitter.Generate(
                new ProjectConfig
                {
                    Name = "DuckStub",
                    OutputType = "library",
                    TargetFramework = "net10.0"
                },
                new[] { sourcePath });

            Assert.Contains("interface INotifier", stub);
            Assert.Contains("List<INotifier>", stub);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompilationStubEmitter_ParsesCharLiteralBodiesAndEmitsReferencedProjectTypes()
    {
        var tempDir = CreateTempDir();
        try
        {
            var sourcePath = Path.Combine(tempDir, "Services.nl");
            File.WriteAllText(sourcePath, """
namespace TaskCli.Services

class TaskStore {
    func Load(line: string): string[] {
        return line.Split('|')
    }
}

class TaskService {
    store: TaskStore

    constructor(taskStore: TaskStore) {
        store = taskStore
    }
}
""");

            var stub = CompilationStubEmitter.Generate(
                new ProjectConfig
                {
                    Name = "TaskCli",
                    OutputType = "exe",
                    TargetFramework = "net10.0"
                },
                new[] { sourcePath });

            Assert.Contains("class TaskStore", stub);
            Assert.Contains("internal TaskStore store;", stub);
            Assert.Contains("public TaskService(TaskStore taskStore)", stub);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompilationStubEmitter_EmitsParameterAttributesForFrameworkInterop()
    {
        var tempDir = CreateTempDir();
        try
        {
            var sourcePath = Path.Combine(tempDir, "Controller.nl");
            File.WriteAllText(sourcePath, """"
import Microsoft.AspNetCore.Mvc
import System.ComponentModel.DataAnnotations

class UsersController {
    func Get([FromRoute(Name: "id")] id: int): IActionResult {
        return null
    }

    func GetRaw([FromRoute(Name: """raw-id""")] id: int): IActionResult {
        return null
    }

    func Create([FromBody] [Required] user: CreateUserRequest): IActionResult {
        return null
    }
}

class CreateUserRequest {
}
"""");

            var stub = CompilationStubEmitter.Generate(
                new ProjectConfig
                {
                    Name = "ParameterAttributeStub",
                    OutputType = "library",
                    TargetFramework = "net10.0"
                },
                new[] { sourcePath });

            Assert.Contains("IActionResult Get([FromRoute(Name = \"id\")] int id)", stub);
            Assert.Contains("IActionResult GetRaw([FromRoute(Name = \"raw-id\")] int id)", stub);
            Assert.Contains("IActionResult Create([FromBody] [Required] CreateUserRequest user)", stub);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanRunExecutableProjectWithTypeScopedMainEntryPoint()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TypeMainProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System

class Program {
    static func Main() {
        print DateTime.UnixEpoch.Year
    }
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "TypeMainProject.dll");
            var result = compiler.CompileToIlAssembly("TypeMainProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("1970", runResult.Stdout);
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

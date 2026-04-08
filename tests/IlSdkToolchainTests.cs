using System;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class IlSdkToolchainTests
{
    [Fact]
    public void ProjectReferenceResolver_ResolvesProjectYmlToNamedCsproj()
    {
        var tempDir = CreateTempDir();
        try
        {
            var sharedDir = Path.Combine(tempDir, "Shared");
            Directory.CreateDirectory(sharedDir);

            File.WriteAllText(Path.Combine(sharedDir, "project.yml"), """
name: SharedLib
outputType: library
targetFramework: net9.0
""");
            File.WriteAllText(Path.Combine(sharedDir, "SharedLib.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n");

            var resolved = ProjectReferenceResolver.ResolveMsBuildProjectPath(Path.Combine(sharedDir, "project.yml"));

            Assert.Equal(Path.Combine(sharedDir, "SharedLib.csproj"), resolved);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DotnetBuild_UsesIlBackendThroughSdk()
    {
        var tempDir = CreateTempDir();
        try
        {
            CreateSdkProject(tempDir, "SdkIlBuild", """
name: SdkIlBuild
backend: il
outputType: exe
targetFramework: net9.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "sdk il build"
}
""");

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                tempDir,
                $"restore \"{Path.Combine(tempDir, "SdkIlBuild.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(3)));

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                tempDir,
                $"build \"{Path.Combine(tempDir, "SdkIlBuild.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(3)));

            var assemblyPath = Path.Combine(tempDir, "bin", "Debug", "net9.0", "SdkIlBuild.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(tempDir, "bin", "Debug", "net9.0", "SdkIlBuild.runtimeconfig.json")));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: tempDir, timeout: TimeSpan.FromMinutes(3));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("sdk il build", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DotnetRun_UsesIlBackendThroughSdk()
    {
        var tempDir = CreateTempDir();
        try
        {
            CreateSdkProject(tempDir, "SdkIlRun", """
name: SdkIlRun
backend: il
outputType: exe
targetFramework: net9.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "sdk il run"
}
""");

            var runResult = DotnetRunner.Run(
                $"run --project \"{Path.Combine(tempDir, "SdkIlRun.csproj")}\" --disable-build-servers",
                workingDirectory: tempDir,
                timeout: TimeSpan.FromMinutes(5));

            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("sdk il run", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DotnetTest_UsesIlBackendThroughSdk()
    {
        var tempDir = CreateTempDir();
        try
        {
            CreateSdkProject(tempDir, "SdkIlTests", """
name: SdkIlTests
backend: il
outputType: library
targetFramework: net9.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Math.nl"), """
func Add(a: int, b: int): int {
    return a + b
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Math.tests.nl"), """
test "addition works" {
    assert Add(2, 3) == 5
}
""");

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                tempDir,
                $"restore \"{Path.Combine(tempDir, "SdkIlTests.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(5)));

            var trxPath = Path.Combine(tempDir, "results.trx");
            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                tempDir,
                $"test \"{Path.Combine(tempDir, "SdkIlTests.csproj")}\" -v q --disable-build-servers --logger \"trx;LogFileName={trxPath}\"",
                timeout: TimeSpan.FromMinutes(5)));

            Assert.True(File.Exists(trxPath));
            var trx = XDocument.Load(trxPath);
            Assert.Contains(
                trx.Descendants().Where(element => element.Name.LocalName == "UnitTestResult"),
                result => string.Equals((string?)result.Attribute("outcome"), "Passed", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DotnetBuild_CSharpConsumerCanReferenceIlBackedNSharpLibrary()
    {
        var tempDir = CreateTempDir();
        try
        {
            var libraryDir = Path.Combine(tempDir, "InteropLib");
            Directory.CreateDirectory(libraryDir);
            CreateSdkProject(libraryDir, "InteropLib", """
name: InteropLib
backend: il
outputType: library
targetFramework: net9.0
""");
            File.WriteAllText(Path.Combine(libraryDir, "MathUtils.nl"), """
namespace InteropLib

class MathUtils {
    static func Add(a: int, b: int): int {
        return a + b
    }
}
""");
            File.WriteAllText(Path.Combine(libraryDir, "Geometry.nl"), """
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

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                libraryDir,
                $"build \"{Path.Combine(libraryDir, "InteropLib.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(5)));

            var consumerDir = Path.Combine(tempDir, "Consumer");
            Directory.CreateDirectory(consumerDir);
            File.WriteAllText(Path.Combine(consumerDir, "Consumer.csproj"), $$"""
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="{{Path.Combine("..", "InteropLib", "InteropLib.csproj")}}" />
  </ItemGroup>
</Project>
""");
            File.WriteAllText(Path.Combine(consumerDir, "Program.cs"), """
using InteropLib;
using InteropLib.Geometry;

var square = new Square(4.0);
Console.WriteLine($"{MathUtils.Add(2, 3)}:{square.Area()}");
""");

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                consumerDir,
                $"build \"{Path.Combine(consumerDir, "Consumer.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(5)));

            var runResult = DotnetRunner.Run(
                $"run --project \"{Path.Combine(consumerDir, "Consumer.csproj")}\" --no-build",
                workingDirectory: consumerDir,
                timeout: TimeSpan.FromMinutes(5));
            var consumerOutputDir = Path.Combine(consumerDir, "bin", "Debug", "net9.0");
            var outputFiles = Directory.Exists(consumerOutputDir)
                ? string.Join(Environment.NewLine, Directory.GetFiles(consumerOutputDir).OrderBy(path => path, StringComparer.Ordinal).Select(Path.GetFileName))
                : "<missing>";
            Assert.True(
                runResult.ExitCode == 0,
                $"stdout:{Environment.NewLine}{runResult.Stdout}{Environment.NewLine}stderr:{Environment.NewLine}{runResult.Stderr}{Environment.NewLine}output:{Environment.NewLine}{outputFiles}");
            Assert.Contains("5:16", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DotnetBuild_CSharpConsumerCanReferenceIlBackedLibraryWithRecordsEnumsAndGenericRuntimeCollections()
    {
        var tempDir = CreateTempDir();
        try
        {
            var libraryDir = Path.Combine(tempDir, "InteropLib");
            Directory.CreateDirectory(libraryDir);
            CreateSdkProject(libraryDir, "InteropLib", """
name: InteropLib
backend: il
outputType: library
targetFramework: net9.0
""");
            File.WriteAllText(Path.Combine(libraryDir, "Models.nl"), """
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

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                libraryDir,
                $"build \"{Path.Combine(libraryDir, "InteropLib.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(5)));

            var consumerDir = Path.Combine(tempDir, "Consumer");
            Directory.CreateDirectory(consumerDir);
            File.WriteAllText(Path.Combine(consumerDir, "Consumer.csproj"), $$"""
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="{{Path.Combine("..", "InteropLib", "InteropLib.csproj")}}" />
  </ItemGroup>
</Project>
""");
            File.WriteAllText(Path.Combine(consumerDir, "Program.cs"), """
using NSharpInteropLib.Models;

var address = new Address("123 Main St", "Springfield", "62701");
var service = new PersonService();
service.Add(new Person
{
    Name = "Ada",
    Age = 42,
    Email = "ada@example.com"
});

Console.WriteLine($"{address.FullAddress}|{service.Count}|{Priority.High}|{Status.Active}");
""");

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                consumerDir,
                $"build \"{Path.Combine(consumerDir, "Consumer.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(5)));

            var runResult = DotnetRunner.Run(
                $"run --project \"{Path.Combine(consumerDir, "Consumer.csproj")}\" --no-build",
                workingDirectory: consumerDir,
                timeout: TimeSpan.FromMinutes(5));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("123 Main St, Springfield 62701|1|High|", runResult.Stdout);
            Assert.Contains("active", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    private static void CreateSdkProject(string projectDir, string projectName, string projectYaml)
    {
        TestSdkFeed.WriteVersionedSdkProject(projectDir, projectName);
        File.WriteAllText(Path.Combine(projectDir, "project.yml"), projectYaml);
        RestoreCommand.Restore(projectDir, quiet: true);
    }

    private static string CreateTempDir()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-sdk-il-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        return tempDir;
    }
}

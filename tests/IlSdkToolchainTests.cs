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
    public void DotnetBuild_RetiredTranspileBackend_IsRejected()
    {
        var tempDir = CreateTempDir();
        try
        {
            TestSdkFeed.WriteVersionedSdkProject(tempDir, "LegacySdkBuild");
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: LegacySdkBuild
backend: transpile
outputType: exe
targetFramework: net9.0
""");
            Directory.CreateDirectory(Path.Combine(tempDir, "obj"));
            File.WriteAllText(Path.Combine(tempDir, "obj", "project.g.props"), """
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <_NSharpOriginalOutputType>Exe</_NSharpOriginalOutputType>
    <AssemblyName>LegacySdkBuild</AssemblyName>
    <NSharpCompilationBackend>transpile</NSharpCompilationBackend>
    <NSharpTestFramework>xunit</NSharpTestFramework>
    <_NSharpBaseSdk>Microsoft.NET.Sdk</_NSharpBaseSdk>
  </PropertyGroup>
</Project>
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "legacy"
}
""");

            var restoreResult = DotnetRunner.Run(
                $"restore \"{Path.Combine(tempDir, "LegacySdkBuild.csproj")}\" -v q --disable-build-servers",
                workingDirectory: tempDir,
                timeout: TimeSpan.FromMinutes(3));

            Assert.NotEqual(0, restoreResult.ExitCode);
            Assert.Contains("retired", restoreResult.Stderr + restoreResult.Stdout);
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
    public void DotnetBuild_CompilationStubResolvesCrossNamespaceImportsAndTopLevelFunctions()
    {
        var tempDir = CreateTempDir();
        try
        {
            CreateSdkProject(tempDir, "StubNamespaceBuild", """
name: StubNamespaceBuild
backend: il
outputType: exe
targetFramework: net9.0
""");
            Directory.CreateDirectory(Path.Combine(tempDir, "Models"));
            Directory.CreateDirectory(Path.Combine(tempDir, "Services"));
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
namespace StubNamespaceBuild

func main() {
    service := new ProductService()
    service.Add(new Product { Name: "Ada" })
    print service.Count
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Product.nl"), """
namespace StubNamespaceBuild.Models

record Product {
    Name: string
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Services", "ProductService.nl"), """
namespace StubNamespaceBuild.Services

import System.Collections.Generic

class ProductService {
    products: List<Product>

    constructor() {
        products = new List<Product>()
    }

    func Add(product: Product) {
        products.Add(product)
    }

    Count: int => products.Count
}
""");

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                tempDir,
                $"build \"{Path.Combine(tempDir, "StubNamespaceBuild.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(5)));

            var assemblyPath = Path.Combine(tempDir, "bin", "Debug", "net9.0", "StubNamespaceBuild.dll");
            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: tempDir, timeout: TimeSpan.FromMinutes(5));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("1", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DotnetBuild_CompilationStubEmitsDuckInterfacesNeededByIlProjects()
    {
        var tempDir = CreateTempDir();
        try
        {
            CreateSdkProject(tempDir, "StubDuckInterfaceBuild", """
name: StubDuckInterfaceBuild
backend: il
outputType: exe
targetFramework: net9.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
namespace StubDuckInterfaceBuild

func main() {
    hub := new NotifierHub()
    print hub.Count
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Notifier.nl"), """
namespace StubDuckInterfaceBuild

import System.Collections.Generic

duck interface INotifier {
    func Notify(message: string)
}

class ConsoleNotifier {
    func Notify(message: string) {
        print message
    }
}

class NotifierHub {
    notifiers: List<INotifier>

    constructor() {
        notifiers = new List<INotifier>()
        notifiers.Add(new ConsoleNotifier())
    }

    Count: int => notifiers.Count
}
""");

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                tempDir,
                $"build \"{Path.Combine(tempDir, "StubDuckInterfaceBuild.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(5)));

            var assemblyPath = Path.Combine(tempDir, "bin", "Debug", "net9.0", "StubDuckInterfaceBuild.dll");
            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: tempDir, timeout: TimeSpan.FromMinutes(5));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("1", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DotnetBuild_IlProjectSupportsImplicitControllerBaseIdentifierCalls()
    {
        var tempDir = CreateTempDir();
        try
        {
            var libraryDir = Path.Combine(tempDir, "ControllerBaseCalls");
            Directory.CreateDirectory(libraryDir);
            CreateSdkProject(libraryDir, "ControllerBaseCalls", """
name: ControllerBaseCalls
backend: il
outputType: library
targetFramework: net9.0

dependencies:
  - framework: Microsoft.AspNetCore.App
""");
            File.WriteAllText(Path.Combine(libraryDir, "WeatherController.nl"), """
import Microsoft.AspNetCore.Mvc

[ApiController]
[Route("api/weather")]
class WeatherController : ControllerBase {
    [HttpGet]
    func Get(): IActionResult {
        return Ok(["Sunny", "Cloudy"])
    }
}
""");

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                libraryDir,
                $"build \"{Path.Combine(libraryDir, "ControllerBaseCalls.csproj")}\" -v q --disable-build-servers",
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
    <ProjectReference Include="{{Path.Combine("..", "ControllerBaseCalls", "ControllerBaseCalls.csproj")}}" />
    <FrameworkReference Include="Microsoft.AspNetCore.App" />
  </ItemGroup>
</Project>
""");
            File.WriteAllText(Path.Combine(consumerDir, "Program.cs"), """
using Microsoft.AspNetCore.Mvc;

var controller = new WeatherController();
var result = controller.Get();

if (result is not OkObjectResult ok || ok.Value is not IEnumerable<string> values)
{
    Console.WriteLine(result.GetType().FullName);
    Environment.Exit(1);
    return;
}

Console.WriteLine(string.Join(",", values));
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
            Assert.Contains("Sunny,Cloudy", runResult.Stdout);
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

using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Xml.Linq;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using Xunit;

namespace NSharpLang.Tests;

// Shared scaffolding for the IL-SDK toolchain test classes below. The class is split into three
// xUnit collections so the dotnet restore/build/run subprocess chains overlap instead of running
// as one ~45s serial tail (the suite's critical path). Each test uses its own temp project dir,
// and the packed SDK feed (TestSdkFeed) is content-hash cached and read-only after creation, so
// concurrent restores against it are safe.
public abstract class IlSdkToolchainTestBase
{
    protected static void CreateSdkProject(string projectDir, string projectName, string projectYaml)
    {
        TestSdkFeed.WriteVersionedSdkProject(projectDir, projectName);
        File.WriteAllText(Path.Combine(projectDir, "project.yml"), projectYaml);
        RestoreCommand.Restore(projectDir, quiet: true);
    }

    protected static string CreateTempDir()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-sdk-il-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        return tempDir;
    }
}

public class IlSdkToolchainTests : IlSdkToolchainTestBase
{
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
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "sdk il build"
}
""");

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                tempDir,
                $"build \"{Path.Combine(tempDir, "SdkIlBuild.csproj")}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(3)));

            var assemblyPath = Path.Combine(tempDir, "bin", "Debug", "net10.0", "SdkIlBuild.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(tempDir, "bin", "Debug", "net10.0", "SdkIlBuild.runtimeconfig.json")));

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
    public void DotnetBuild_ResolvesRuntimeForAnonymousUnionAndProjectReferences()
    {
        var tempDir = CreateTempDir();
        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);

            var libraryDir = Path.Combine(tempDir, "UnionLib");
            Directory.CreateDirectory(libraryDir);
            File.WriteAllText(Path.Combine(libraryDir, "UnionLib.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n");
            File.WriteAllText(Path.Combine(libraryDir, "project.yml"), """
name: UnionLib
backend: il
outputType: library
targetFramework: net10.0
""");
            RestoreCommand.Restore(libraryDir, quiet: true);
            File.WriteAllText(Path.Combine(libraryDir, "UnionApi.nl"), """
namespace UnionLib

class UnionApi {
    static func Describe(value: int | string): string {
        return match value {
            int number => number.ToString(),
            string text => text
        }
    }

    static func Choose(flag: bool): int | string {
        if flag {
            return 42
        }

        return "runtime"
    }
}
""");

            var consumerDir = Path.Combine(tempDir, "Consumer");
            Directory.CreateDirectory(consumerDir);
            File.WriteAllText(Path.Combine(consumerDir, "Consumer.csproj"), $$"""
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="{{Path.Combine("..", "UnionLib", "UnionLib.csproj")}}" />
  </ItemGroup>
</Project>
""");
            File.WriteAllText(Path.Combine(consumerDir, "Program.cs"), """
var direct = UnionLib.UnionApi.Describe(7);
var returned = UnionLib.UnionApi.Choose(false).As<string>();
Console.WriteLine($"{direct}|{returned}");
""");

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                consumerDir,
                "build Consumer.csproj -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(5)));

            var runResult = DotnetRunner.Run(
                $"run --project \"{Path.Combine(consumerDir, "Consumer.csproj")}\" --no-build",
                workingDirectory: consumerDir,
                timeout: TimeSpan.FromMinutes(5));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("7|runtime", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DotnetBuild_ProjectSemVerPrereleaseKeepsPackageVersionAndUsesNumericClrVersions()
    {
        var tempDir = CreateTempDir();
        try
        {
            CreateSdkProject(tempDir, "SdkSemVerBuild", """
name: SdkSemVerBuild
version: 1.2.0-beta.1+build.5
backend: il
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Library.nl"), """
namespace SdkSemVerBuild

class Api {
    static func Answer(): int {
        return 42
    }
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Directory.Build.targets"), """
<Project>
  <Target Name="PrintNSharpVersionProperties" DependsOnTargets="_ApplyNSharpProjectConfigForCurrentBuild">
    <Message Importance="High" Text="nsharp-version-props Version=$(Version);PackageVersion=$(PackageVersion);AssemblyVersion=$(AssemblyVersion);FileVersion=$(FileVersion)" />
  </Target>
</Project>
""");

            var projectPath = Path.Combine(tempDir, "SdkSemVerBuild.csproj");
            var propertiesResult = DotnetRunner.Run(
                $"msbuild \"{projectPath}\" -t:PrintNSharpVersionProperties -v m --disable-build-servers",
                workingDirectory: tempDir,
                timeout: TimeSpan.FromMinutes(3));
            Assert.Equal(0, propertiesResult.ExitCode);
            Assert.Contains(
                "nsharp-version-props Version=1.2.0-beta.1+build.5;PackageVersion=1.2.0-beta.1+build.5;AssemblyVersion=1.2.0.0;FileVersion=1.2.0.0",
                propertiesResult.Stdout);

            Assert.Equal(0, TestSdkFeed.RunDotnetNoCapture(
                tempDir,
                $"build \"{projectPath}\" -v q --disable-build-servers",
                timeout: TimeSpan.FromMinutes(5)));

            var assemblyPath = Path.Combine(tempDir, "bin", "Debug", "net10.0", "SdkSemVerBuild.dll");
            Assert.Equal(new Version(1, 2, 0, 0), AssemblyName.GetAssemblyName(assemblyPath).Version);
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
targetFramework: net10.0
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

}

public class IlSdkToolchainConsumerTests : IlSdkToolchainTestBase
{
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
targetFramework: net10.0
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

}

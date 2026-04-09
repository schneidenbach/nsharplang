using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using NSharpLang.Cli;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class AnalyzerMetadataLoadContextTests
{
    [Fact]
    public void LoadReferencedAssembly_UsesRequestedAssemblyPathWhenSearchDirectoryAlreadyContainsSameName()
    {
        var tempDir = CreateTempDir();
        try
        {
            var firstAssemblyPath = BuildManagedLibrary(tempDir, "First", "SameNameMetadataCollision", "OnlyInFirst");
            var secondAssemblyPath = BuildManagedLibrary(tempDir, "Second", "SameNameMetadataCollision", "OnlyInSecond");

            using var analyzer = new Analyzer();
            analyzer.LoadSystemAssemblies();
            AddSearchDirectory(analyzer, Path.GetDirectoryName(firstAssemblyPath)!);

            analyzer.LoadReferencedAssembly(secondAssemblyPath);

            var loadedAssembly = GetLoadedMetadataAssemblies(analyzer)
                .Single(assembly => string.Equals(assembly.GetName().Name, "SameNameMetadataCollision", StringComparison.Ordinal));

            Assert.Equal(Path.GetFullPath(secondAssemblyPath), Path.GetFullPath(loadedAssembly.Location));
            Assert.NotNull(loadedAssembly.GetType("Collision.OnlyInSecond", throwOnError: false));
            Assert.Null(loadedAssembly.GetType("Collision.OnlyInFirst", throwOnError: false));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    private static string BuildManagedLibrary(string tempDir, string subdirectory, string assemblyName, string typeName)
    {
        var projectDir = Path.Combine(tempDir, subdirectory);
        Directory.CreateDirectory(projectDir);

        File.WriteAllText(Path.Combine(projectDir, $"{assemblyName}.csproj"), $$"""
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <AssemblyName>{{assemblyName}}</AssemblyName>
    <RootNamespace>Collision</RootNamespace>
    <Nullable>disable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
  </PropertyGroup>
</Project>
""");
        File.WriteAllText(Path.Combine(projectDir, "Marker.cs"), $$"""
namespace Collision;

public sealed class {{typeName}}
{
}
""");

        var buildResult = DotnetRunner.Run(
            $"build \"{Path.Combine(projectDir, $"{assemblyName}.csproj")}\" -v q --disable-build-servers",
            workingDirectory: projectDir,
            timeout: TimeSpan.FromMinutes(3));

        Assert.True(
            buildResult.ExitCode == 0,
            $"stdout:{Environment.NewLine}{buildResult.Stdout}{Environment.NewLine}stderr:{Environment.NewLine}{buildResult.Stderr}");

        var assemblyPath = Path.Combine(projectDir, "bin", "Debug", "net9.0", $"{assemblyName}.dll");
        Assert.True(File.Exists(assemblyPath));
        return assemblyPath;
    }

    private static IReadOnlyList<Assembly> GetLoadedMetadataAssemblies(Analyzer analyzer)
    {
        var field = typeof(Analyzer).GetField("_mlcAssemblies", BindingFlags.Instance | BindingFlags.NonPublic);
        Assert.NotNull(field);
        return Assert.IsAssignableFrom<IReadOnlyList<Assembly>>(field!.GetValue(analyzer));
    }

    private static void AddSearchDirectory(Analyzer analyzer, string directory)
    {
        var field = typeof(Analyzer).GetField("_metadataResolver", BindingFlags.Instance | BindingFlags.NonPublic);
        Assert.NotNull(field);

        var resolver = field!.GetValue(analyzer);
        Assert.NotNull(resolver);

        var addSearchDirectory = resolver!.GetType().GetMethod("AddSearchDirectory", BindingFlags.Instance | BindingFlags.Public);
        Assert.NotNull(addSearchDirectory);
        addSearchDirectory!.Invoke(resolver, new object[] { directory });
    }

    private static string CreateTempDir()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-analyzer-mlc-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        return tempDir;
    }
}

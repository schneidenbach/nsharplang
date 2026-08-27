using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using NSharpLang.Cli;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

// WHAT IS LEFT HERE, AND WHY.
//
// Every version-precedence claim this file used to make now lives in the N# estate, on the owner
// that makes the decision: `AnalyzerMetadataLoadPolicy.CompareVersionSpellings` and
// `PickHighestVersionDirectory` (see `AnalyzerMetadataLoadPolicy.tests.nl`, which restates all nine
// rows and adds twelve the C# never made). The two blocks below are NOT restatements of a rule — they
// drive a real `MetadataLoadContext` over two separately BUILT managed libraries that share one
// assembly identity, which is the only way to observe what the load registry does when two files
// claim the same name. Migrating them needs an estate kernel that can compile a throwaway managed
// library and hand back its path; no such kernel exists yet. Recorded as the remainder rather than
// deleted, because deleting them would drop the only coverage of the adopt-instead-of-throw path.
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

    [Fact]
    public void LoadReferencedAssembly_AdoptsAlreadyLoadedIdentityInsteadOfThrowing()
    {
        var tempDir = CreateTempDir();
        try
        {
            // Two separate builds of the same assembly identity: same name and version but
            // different MVIDs, which is exactly the shape a stale NuGet-cache extraction
            // produces next to the restored copy.
            var stalePath = BuildManagedLibrary(tempDir, "Stale", "DuplicateIdentity", "StaleMarker");
            var restoredPath = BuildManagedLibrary(tempDir, "Restored", "DuplicateIdentity", "RestoredMarker");

            using var analyzer = new Analyzer();
            analyzer.LoadSystemAssemblies();

            // Load the stale copy the way the metadata resolver does — straight into the
            // MetadataLoadContext, bypassing the analyzer's registry.
            var mlc = GetMetadataLoadContext(analyzer);
            mlc.LoadFromAssemblyPath(stalePath);

            analyzer.LoadReferencedAssembly(restoredPath);

            var loadedAssembly = GetLoadedMetadataAssemblies(analyzer)
                .Single(assembly => string.Equals(assembly.GetName().Name, "DuplicateIdentity", StringComparison.Ordinal));

            // The first-loaded copy wins; the second load dedupes instead of throwing and
            // joins the analyzer's registry.
            Assert.Equal(Path.GetFullPath(stalePath), Path.GetFullPath(loadedAssembly.Location));
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
    <TargetFramework>net10.0</TargetFramework>
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

        var assemblyPath = Path.Combine(projectDir, "bin", "Debug", "net10.0", $"{assemblyName}.dll");
        Assert.True(File.Exists(assemblyPath));
        return assemblyPath;
    }

    private static System.Reflection.MetadataLoadContext GetMetadataLoadContext(Analyzer analyzer)
    {
        var field = typeof(Analyzer).GetField("_mlc", BindingFlags.Instance | BindingFlags.NonPublic);
        Assert.NotNull(field);
        return Assert.IsType<System.Reflection.MetadataLoadContext>(field!.GetValue(analyzer));
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

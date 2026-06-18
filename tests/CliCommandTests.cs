using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class CliCommandTests
{
    private static readonly string HelloWorldProject = Path.Combine(FindExamplesDir(), "01-hello-world");
    private static readonly string IssueTrackerFixture = Path.Combine(FindFixturesDir(), "issue-tracker");

    [Fact]
    public void CheckCommand_Help_IsSideEffectFree()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => CheckCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc check", stdout);
        Assert.DoesNotContain("Directory not found", stderr);
    }

    [Fact]
    public void CheckCommand_DefaultsToJsonEnvelope()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", HelloWorldProject }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        var doc = JsonDocument.Parse(stdout);
        Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal(NormalizePath(Path.GetFullPath(HelloWorldProject)),
            doc.RootElement.GetProperty("projectRoot").GetString());
        Assert.True(doc.RootElement.GetProperty("checkedFiles").GetInt32() >= 1);
        AssertJsonContract("check", stdout);
    }

    [Fact]
    public void FixCommand_Help_IsSideEffectFree()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => FixCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc fix", stdout);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
    }

    [Fact]
    public void FixCommand_DryRun_DefaultsToJsonEnvelope()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-fix-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var doc = JsonDocument.Parse(stdout);
            Assert.Equal("fix", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("dryRun").GetBoolean());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(NormalizePath(Path.GetFullPath(tempDir)),
                doc.RootElement.GetProperty("projectRoot").GetString());
            Assert.Equal(0, doc.RootElement.GetProperty("results").GetArrayLength());
            AssertJsonContract("fix", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TreeCommand_ProjectYmlOnly_EmitsStableJsonEnvelope()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-tree-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TreeContract
entry: Program.nl
outputType: exe
targetFramework: net10.0

dependencies:
  - framework: Microsoft.AspNetCore.App
  - nuget: Serilog
    version: 3.1.1
  - nuget: serilog
    version: 9.9.9
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    print "ok"
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                TreeCommand.Execute(new[] { "--project", tempDir, "--json" }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            AssertJsonContract("tree", stdout);

            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal(2, root.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("tree", root.GetProperty("command").GetString());
            Assert.True(root.GetProperty("ok").GetBoolean());
            Assert.Equal(NormalizePath(Path.GetFullPath(tempDir)), root.GetProperty("projectRoot").GetString());
            Assert.Equal("project.yml", root.GetProperty("project").GetProperty("source").GetString());
            Assert.False(root.GetProperty("capabilities").GetProperty("transitiveNuGetDependencies").GetBoolean());
            Assert.Equal(2, root.GetProperty("dependencies").GetArrayLength());
            var dependencies = root.GetProperty("dependencies").EnumerateArray().ToArray();
            Assert.Equal("framework", dependencies[0].GetProperty("kind").GetString());
            Assert.Equal("Microsoft.AspNetCore.App", dependencies[0].GetProperty("name").GetString());
            Assert.Equal("nuget", dependencies[1].GetProperty("kind").GetString());
            Assert.Equal("Serilog", dependencies[1].GetProperty("name").GetString());
            Assert.Equal("3.1.1", dependencies[1].GetProperty("version").GetString());
            Assert.Equal(0, root.GetProperty("transitiveDependencies").GetArrayLength());
            Assert.Equal(2, root.GetProperty("summary").GetProperty("direct").GetInt32());
            Assert.Contains("direct runtime dependencies",
                root.GetProperty("limitations")[0].GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TreeCommand_JsonError_UsesGlobalErrorEnvelope()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-tree-missing-{Guid.NewGuid():N}");

        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            TreeCommand.Execute(new[] { "--project", missingDir, "--json" }));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        var root = doc.RootElement;
        Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("tree", root.GetProperty("command").GetString());
        Assert.False(root.GetProperty("ok").GetBoolean());
        Assert.Equal(NormalizePath(Path.GetFullPath(missingDir)), root.GetProperty("projectRoot").GetString());
        Assert.Contains("Project directory not found",
            root.GetProperty("error").GetProperty("message").GetString());
    }

    [Fact]
    public void TreeDependencyDeduplicator_DeduplicatesAndOrdersDependencies()
    {
        var emptyDependencies = Array.Empty<TreeCommand.TreeDependency>();
        var dependencies = new[]
        {
            NewDependency("Serilog", "nuget", "3.1.1"),
            NewDependency("Microsoft.AspNetCore.App", "framework", null),
            NewDependency("serilog", "nuget", "9.9.9"),
            NewDependency("../Shared/Shared.csproj", "project", null),
            NewDependency("Newtonsoft.Json", "nuget", "13.0.3"),
            NewDependency("microsoft.aspnetcore.app", "framework", null)
        };

        Assert.True(TreeDependencyDeduplicator.TryDeduplicate(dependencies, out var helperActual));
        var commandActual = TreeCommand.Deduplicate(dependencies);

        var expected = new[]
        {
            "framework:Microsoft.AspNetCore.App:",
            "nuget:Newtonsoft.Json:13.0.3",
            "nuget:Serilog:3.1.1",
            "project:../Shared/Shared.csproj:"
        };
        Assert.Equal(expected, helperActual.Select(FormatDependency));
        Assert.Equal(expected, commandActual.Select(FormatDependency));

        TreeCommand.TreeDependency NewDependency(string name, string kind, string? version) =>
            new(name, kind, version, "runtime", false, emptyDependencies);

        static string FormatDependency(TreeCommand.TreeDependency dependency) =>
            $"{dependency.Kind}:{dependency.Name}:{dependency.Version}";
    }

    [Fact]
    public void TreeDependencyDeduplicator_DeduplicatesTargetFrameworks()
    {
        var frameworks = new[]
        {
            "net10.0",
            "NET10.0",
            "net9.0",
            "net8.0",
            "NET9.0"
        };

        Assert.True(TreeDependencyDeduplicator.TryDeduplicateTargetFrameworks(
            frameworks,
            out var dogfoodFrameworks));
        Assert.Equal(new[] { "net10.0", "net9.0", "net8.0" }, dogfoodFrameworks);
        Assert.Equal("unknown", TreeCommand.FormatTargetFrameworks(Array.Empty<string>()));
        Assert.Equal("net10.0,net9.0,net8.0", TreeCommand.FormatTargetFrameworks(frameworks));
    }

    [Fact]
    public void GeneratedOutputDirectoryDeduplicator_DeduplicatesStaleGeneratedDirectories()
    {
        var duplicateDirs = new[] { "obj/Debug/net10.0/nsharp", "obj/Debug/net10.0/nsharp" };
        Assert.True(GeneratedOutputDirectoryDeduplicator.TryDeduplicate(
            duplicateDirs,
            out var distinctDirs));
        Assert.Equal(new[] { "obj/Debug/net10.0/nsharp" }, distinctDirs);

        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-stale-generated-{Guid.NewGuid():N}");
        var generatedDir = Path.Combine(tempDir, "obj", "Debug", "net10.0", "nsharp");
        Directory.CreateDirectory(generatedDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), "func main(): int { return 0 }");

            var liveGeneratedFile = Path.Combine(generatedDir, "Program.g.cs");
            var staleGeneratedFile = Path.Combine(generatedDir, "Deleted.g.cs");
            File.WriteAllText(liveGeneratedFile, "// live");
            File.WriteAllText(staleGeneratedFile, "// stale");

            Program.CleanStaleGeneratedFiles(tempDir);

            Assert.True(File.Exists(liveGeneratedFile));
            Assert.False(File.Exists(staleGeneratedFile));
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void CleanArtifactDirectoryOrderer_OrdersArtifactDirectories()
    {
        var directories = new[]
        {
            "/repo/bin",
            "/repo/src/obj",
            "/repo/src/tmp",
            "/repo/src/.nlc",
            "/repo/node_modules/pkg/bin",
            "/repo/src/obj",
            "/repo/deep/nested/bin",
            "/repo/deep/nested/.nlc",
            "/repo/obj"
        };

        var expected = directories
            .Distinct(StringComparer.Ordinal)
            .Where(dir => !CleanCommand.IsUnderNodeModulesDirectory(dir))
            .Where(dir => CleanCommand.IsArtifactDirectoryName(Path.GetFileName(dir)))
            .OrderByDescending(dir => dir.Length)
            .ToArray();

        Assert.True(CleanArtifactDirectoryOrderer.TryOrder(directories, out var actual));
        Assert.Equal(expected, actual);
    }

    [Fact]
    public void UpdateDependencyFilter_FiltersTargetNuGetDependencies()
    {
        var dependencies = new[]
        {
            new Reference { Nuget = "Serilog", Version = "3.1.1" },
            new Reference { Framework = "Microsoft.AspNetCore.App" },
            new Reference { Nuget = "Newtonsoft.Json", Version = "13.0.3" },
            new Reference { Dll = "lib/Analyzer.dll" },
            new Reference { Nuget = "serilog", Version = "4.0.0" },
            new Reference { Project = "../Shared/project.yml" },
            new Reference { Nuget = "System.Text.Json", Version = "10.0.0" }
        };

        Assert.True(UpdateDependencyFilter.TryFilterAllNuGetDependencies(
            dependencies,
            out var adapterAllNuGet));
        Assert.Equal(new[] { "Serilog", "Newtonsoft.Json", "serilog", "System.Text.Json" },
            adapterAllNuGet.Select(reference => reference.Nuget));

        var allNuGet = UpdateCommand.FilterNuGetDependencies(dependencies, targetPackage: null);
        Assert.Equal(new[] { "Serilog", "Newtonsoft.Json", "serilog", "System.Text.Json" },
            allNuGet.Select(reference => reference.Nuget));

        Assert.True(UpdateDependencyFilter.TryFilterTargetNuGetDependencies(
            dependencies,
            "SERILOG",
            out var serilog));
        Assert.Equal(new[] { "Serilog", "serilog" },
            serilog.Select(reference => reference.Nuget));

        Assert.True(UpdateDependencyFilter.TryFilterTargetNuGetDependencies(
            dependencies,
            "Missing.Package",
            out var missing));
        Assert.Empty(missing);
    }

    [Theory]
    [MemberData(nameof(QueryJsonContractCases))]
    public void QueryCommand_EmitsStableJsonEnvelope(string contractName, string[] args)
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(args));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        AssertJsonContract(contractName, stdout);
    }

    [Fact]
    public void DocOrdering_DogfoodPath_MatchesCSharpKindOrdinalOrdering()
    {
        // M10: the doc symbol ordering must be deterministic regardless of whether the N# dogfood
        // path or the C# fallback runs. This asserts the dogfood ordering (taken because the
        // dogfood DLL is present in the test build) equals the C# `Kind.ToString()` ordinal + name
        // ordering, and locks the invariant so a future SymbolKind addition can't silently diverge.
        var symbols = new List<SymbolResult>();
        foreach (SymbolKind kind in Enum.GetValues<SymbolKind>())
        {
            // Two per kind (reverse-sorted names) to also exercise the name tiebreak.
            symbols.Add(MakeDocSymbol("Zeta" + kind, kind));
            symbols.Add(MakeDocSymbol("Alpha" + kind, kind));
        }

        var actual = ProjectDocGenerator.OrderSymbolsForGeneration(symbols);

        var expected = symbols
            .Where(symbol => symbol.Kind is not SymbolKind.Variable and not SymbolKind.Parameter)
            .OrderBy(symbol => symbol.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(symbol => symbol.Name, StringComparer.Ordinal)
            .ToList();

        Assert.Equal(
            expected.Select(symbol => (symbol.Kind, symbol.Name)),
            actual.Select(symbol => (symbol.Kind, symbol.Name)));
    }

    private static SymbolResult MakeDocSymbol(string name, SymbolKind kind)
        => new(name, kind, "file.nl", 1, 1, null, null, null, null);

    [Fact]
    public void QueryCommand_DoesNotBuildCSharpProjectReferences()
    {
        // H4: `nlc query` is read-only/LLM-first and must never spawn `dotnet build` for a C#
        // project reference (multi-second stalls + the build-pipe deadlock). The referenced C#
        // project must be left unbuilt.
        var root = Path.Combine(Path.GetTempPath(), $"nsharp-query-noref-build-{Guid.NewGuid():N}");
        var csharpDir = Path.Combine(root, "CsLib");
        var nsharpDir = Path.Combine(root, "App");
        Directory.CreateDirectory(csharpDir);
        Directory.CreateDirectory(nsharpDir);

        try
        {
            var csprojPath = Path.Combine(csharpDir, "CsLib.csproj");
            File.WriteAllText(csprojPath, """
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>
</Project>
""");
            File.WriteAllText(Path.Combine(csharpDir, "Lib.cs"), "namespace CsLib { public static class Tools { public static int Value => 1; } }");

            File.WriteAllText(Path.Combine(nsharpDir, "project.yml"), $"""
name: App
outputType: exe
targetFramework: net10.0
dependencies:
  - project: {csprojPath.Replace("\\", "/")}
""");
            File.WriteAllText(Path.Combine(nsharpDir, "Program.nl"), """
func Main() {
    Console.WriteLine("hi")
}
""");

            var (_, _, _) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "symbols",
                "--project", nsharpDir
            }));

            Assert.False(
                Directory.Exists(Path.Combine(csharpDir, "bin")),
                "nlc query must not build a C# project reference (H4).");
            Assert.False(
                Directory.Exists(Path.Combine(csharpDir, "obj")),
                "nlc query must not restore/build a C# project reference (H4).");
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch { /* best effort */ }
        }
    }

    [Fact]
    public void QueryCommand_DiagnosticsClusters_EmitsClusterEnvelope()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-diagnostic-clusters-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: DiagnosticClusters
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    Console.WriteLine(undefinedVar1)
    Console.WriteLine(undefinedVar2)
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "diagnostics",
                "--clusters",
                "--project", tempDir
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("diagnostics.clusters", doc.RootElement.GetProperty("command").GetString());
            AssertJsonContract("diagnosticsClusters", stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            var cluster = Assert.Single(doc.RootElement.GetProperty("clusters").EnumerateArray(),
                item => item.GetProperty("category").GetString() == "identifier-resolution");
            Assert.Equal("symbols:missing-import-or-qualification", cluster.GetProperty("recipe").GetString());
            Assert.Equal("medium", cluster.GetProperty("risk").GetString());
            Assert.Equal("Program.nl", Assert.Single(cluster.GetProperty("files").EnumerateArray()).GetString());
            Assert.True(cluster.GetProperty("relatedDiagnostics").GetArrayLength() >= 2);
            Assert.StartsWith("nlc query inspect --file Program.nl --pos ", cluster.GetProperty("nextCommand").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Ast_EmitsStableNodeTypedJson()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-query-ast-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: AstQuery
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func add(x: int, y: int): int {
    return x + y
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "ast",
                "--file", "Program.nl",
                "--project", tempDir
            }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("query.ast", root.GetProperty("command").GetString());
            Assert.True(root.GetProperty("ok").GetBoolean());

            var file = Assert.Single(root.GetProperty("files").EnumerateArray());
            Assert.EndsWith("Program.nl", file.GetProperty("file").GetString());

            var ast = file.GetProperty("ast");
            Assert.Equal("CompilationUnit", ast.GetProperty("node").GetString());

            var func = Assert.Single(ast.GetProperty("declarations").EnumerateArray());
            Assert.Equal("FunctionDeclaration", func.GetProperty("node").GetString());
            Assert.Equal("add", func.GetProperty("name").GetString());
            Assert.Equal(2, func.GetProperty("parameters").GetArrayLength());
            Assert.Equal("x", func.GetProperty("parameters")[0].GetProperty("name").GetString());

            // Concrete node type is preserved through the polymorphic Statement base, with positions.
            var body = func.GetProperty("body");
            Assert.True(body.GetProperty("line").GetInt32() >= 1);
            var returnStmt = Assert.Single(body.GetProperty("statements").EnumerateArray());
            Assert.Equal("ReturnStatement", returnStmt.GetProperty("node").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Diagnostics_MalformedCode_EmitsStableHighSignalJson()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-malformed-diagnostics-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: MalformedDiagnostics
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class User {
    Name: string
}

func main() {
    first := 1 +
    Console.WriteLine(undefinedFromCli)
    user := new User { Name = "Ada" }
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "diagnostics",
                "--project", tempDir,
                "--file", "Program.nl",
                "--no-daemon"
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("diagnostics", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());

            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToList();
            Assert.Contains(results, result =>
                result.GetProperty("code").GetString() == "NL102" &&
                result.GetProperty("line").GetInt32() == 6 &&
                result.GetProperty("message").GetString()!.Contains("Expected expression after '+'") &&
                result.GetProperty("suggestion").GetString()!.Contains("Add an expression after '+'"));
            Assert.Contains(results, result =>
                result.GetProperty("code").GetString() == "NL103" &&
                result.GetProperty("message").GetString()!.Contains("Object initializer member 'Name' uses '='") &&
                result.GetProperty("hint").GetString()!.Contains("Name: value"));
            Assert.Contains(results, result =>
                result.GetProperty("code").GetString() == "NL301" &&
                result.GetProperty("message").GetString()!.Contains("undefinedFromCli"));
            Assert.DoesNotContain(results, result =>
                result.GetProperty("message").GetString()!.Contains("<error>", StringComparison.Ordinal));
            Assert.True(results.Count <= 4, $"Expected bounded diagnostics, got {results.Count}.");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Diagnostics_IncludesStrictLintErrorsForValidCode()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-lint-diagnostics-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: LintDiagnostics
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    unused := 42
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "diagnostics",
                "--project", tempDir,
                "--file", "Program.nl",
                "--no-daemon"
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            var diagnostic = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray(),
                result => result.GetProperty("code").GetString() == "NL001");
            Assert.Equal("error", diagnostic.GetProperty("severity").GetString());
            Assert.Contains("unused", diagnostic.GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Diagnostics_SeverityFilter_IsCaseInsensitive()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-diagnostic-severity-filter-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: SeverityFilterDiagnostics
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, ".editorconfig"), """
root = true

[*.nl]
dotnet_diagnostic.NL001.severity = warning
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    unused := 42
    undefinedFromCli()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "diagnostics",
                "--project", tempDir,
                "--file", "Program.nl",
                "--severity", "WARNING",
                "--no-daemon"
            }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            var diagnostic = Assert.Single(results);
            Assert.Equal("NL001", diagnostic.GetProperty("code").GetString());
            Assert.Equal("warning", diagnostic.GetProperty("severity").GetString());

            var summary = doc.RootElement.GetProperty("summary");
            Assert.Equal(0, summary.GetProperty("errors").GetInt32());
            Assert.Equal(1, summary.GetProperty("warnings").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommand_Definition_SnapsFromClosingParen()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "definition",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "64:10"
        }));

        Assert.Equal(0, exitCode);

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("GetAll", doc.RootElement.GetProperty("result").GetProperty("name").GetString());
        Assert.Equal("Service.nl", doc.RootElement.GetProperty("result").GetProperty("file").GetString());
    }

    [Fact]
    public void QueryCommand_Type_NoSymbol_ReturnsStructuredEnvelope()
    {
        // Line 1 is a comment — no symbol there
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "type",
            "--project", IssueTrackerFixture,
            "--file", "Program.nl",
            "--pos", "1:1"
        }));

        Assert.Equal(1, exitCode);

        using var doc = JsonDocument.Parse(stdout);
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("type", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("noSymbol", doc.RootElement.GetProperty("error").GetProperty("code").GetString());
        Assert.Equal("Program.nl",
            doc.RootElement.GetProperty("error").GetProperty("details").GetProperty("file").GetString());
        Assert.Equal(1,
            doc.RootElement.GetProperty("error").GetProperty("details").GetProperty("position").GetProperty("line").GetInt32());
    }

    [Fact]
    public void InspectSummary_Contract_UsesCompactEnvelope()
    {
        // Service.nl line 11: store: IssueStore (field)
        var (_, json, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "inspect",
            "--summary",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "11:5"
        }));

        AssertJsonContract("inspectSummary", json);
        using var doc = JsonDocument.Parse(json);
        Assert.True(doc.RootElement.TryGetProperty("summary", out var summary));
        Assert.False(doc.RootElement.TryGetProperty("result", out _));
        Assert.Equal("store", summary.GetProperty("symbol").GetProperty("name").GetString());
    }

    [Fact]
    public void QueryCommand_Inspect_TypeUseGenericArgument_UsesSemanticBinding()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-query-type-use-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(tempDir, "Foo"));
        Directory.CreateDirectory(Path.Combine(tempDir, "Bar"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: QueryTypeUse
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Foo", "Widget.nl"), """
namespace QueryTypeUse.Foo

record Widget {
    Value: string
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Bar", "Widget.nl"), """
namespace QueryTypeUse.Bar

record Widget {
    Value: int
}
""");
            var useSource = """
namespace QueryTypeUse.Foo
import System.Collections.Generic

func Read(items: List<Widget>): string {
    return ""
}
""";
            File.WriteAllText(Path.Combine(tempDir, "Foo", "UseWidget.nl"), useSource);
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
namespace QueryTypeUse

func Main() {
}
""");

            var typeUseColumn = useSource.Split('\n')[3].IndexOf("Widget", StringComparison.Ordinal) + 1;
            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "inspect",
                "--project", tempDir,
                "--file", "Foo/UseWidget.nl",
                "--pos", $"4:{typeUseColumn}"
            }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            var result = doc.RootElement.GetProperty("result");
            Assert.Equal("Widget", result.GetProperty("symbol").GetProperty("name").GetString());
            Assert.EndsWith("Foo/Widget.nl", result.GetProperty("definition").GetProperty("file").GetString(), StringComparison.Ordinal);

            var references = result.GetProperty("references").GetProperty("results").EnumerateArray().ToArray();
            Assert.Contains(references, item => item.GetProperty("file").GetString()!.EndsWith("Foo/UseWidget.nl", StringComparison.Ordinal));
            Assert.DoesNotContain(references, item => item.GetProperty("file").GetString()!.EndsWith("Bar/Widget.nl", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_UsesStableEnvelopeAndPerItemResponses()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "inspect",
    "file": "Service.nl",
    "pos": "11:5",
    "compact": true
  },
  {
    "command": "diagnostics",
    "clusters": true
  },
  {
    "command": "doc",
    "query": "Console.WriteLine"
  },
  {
    "command": "type",
    "file": "Program.nl",
    "pos": "1:1"
  }
]
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "batch",
                "--project", IssueTrackerFixture,
                "--requests", requestsPath
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            AssertJsonContract("batch", stdout);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("batch", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(4, doc.RootElement.GetProperty("requestCount").GetInt32());
            Assert.Equal(3, doc.RootElement.GetProperty("successCount").GetInt32());
            Assert.Equal(1, doc.RootElement.GetProperty("failureCount").GetInt32());

            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Equal("inspect", results[0].GetProperty("request").GetProperty("command").GetString());
            Assert.True(results[0].GetProperty("request").GetProperty("compact").GetBoolean());
            Assert.True(results[0].GetProperty("ok").GetBoolean());
            Assert.True(results[0].GetProperty("response").TryGetProperty("summary", out _));

            Assert.Equal("diagnostics", results[1].GetProperty("request").GetProperty("command").GetString());
            Assert.True(results[1].GetProperty("request").GetProperty("clusters").GetBoolean());
            Assert.True(results[1].GetProperty("ok").GetBoolean());
            Assert.Equal("diagnostics.clusters", results[1].GetProperty("response").GetProperty("command").GetString());

            Assert.Equal("doc", results[2].GetProperty("request").GetProperty("command").GetString());
            Assert.True(results[2].GetProperty("ok").GetBoolean());
            Assert.Equal("doc", results[2].GetProperty("response").GetProperty("command").GetString());

            Assert.Equal("type", results[3].GetProperty("request").GetProperty("command").GetString());
            Assert.False(results[3].GetProperty("ok").GetBoolean());
            Assert.Equal("noSymbol", results[3].GetProperty("response").GetProperty("error").GetProperty("code").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_DuplicateRequestIds_AreRejectedInOrdinalOrder()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-duplicates-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  { "id": "zeta", "command": "doc", "query": "Console.WriteLine" },
  { "id": "alpha", "command": "doc", "query": "String" },
  { "id": " ", "command": "doc", "query": "Int32" },
  { "id": "zeta", "command": "diagnostics" },
  { "id": "Alpha", "command": "doc", "query": "Console" },
  { "id": "alpha", "command": "symbols" }
]
""");

            var exception = Assert.Throws<InvalidDataException>(() => BatchQueryRunner.LoadRequests(requestsPath));
            Assert.Contains("Duplicate batch request ids are not allowed: alpha, zeta", exception.Message);

            var requests = new List<BatchQueryRequest>
            {
                new("doc", Id: "zeta"),
                new("doc", Id: "alpha"),
                new("doc", Id: " "),
                new("diagnostics", Id: "zeta"),
                new("doc", Id: "Alpha"),
                new("symbols", Id: "alpha")
            };

            Assert.True(BatchQueryKernels.TryFindDuplicateRequestIds(requests, out var duplicateIds));
            Assert.Equal(new[] { "alpha", "zeta" }, duplicateIds);

            var okWords = new[] { 1UL | (1UL << 2) | (1UL << 5) | (1UL << 63) };
            Assert.True(BatchQueryKernels.TryCountResultSuccesses(okWords, 6, out var successCount));
            Assert.Equal(3, successCount);

            Assert.True(BatchQueryKernels.TryCountResultSuccesses(Array.Empty<ulong>(), 0, out successCount));
            Assert.Equal(0, successCount);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void NewCommandKernels_SelectsProjectNameOperand()
    {
        Assert.True(NewCommandKernels.TryGetProjectNameOperand(
            new[] { "--template", "webapi", "MyApi" },
            new[] { "--template", "--type" },
            out var projectName));
        Assert.Equal("MyApi", projectName);
    }

    [Fact]
    public void CheckCommandKernels_SelectsProjectOperand()
    {
        Assert.True(CheckCommandKernels.TryGetProjectOperand(
            new[] { "--text", "samples/demo" },
            Array.Empty<string>(),
            out var projectPath));
        Assert.Equal("samples/demo", projectPath);
    }

    [Fact]
    public void FixCommandArgumentKernels_SelectsProjectOperand()
    {
        Assert.True(FixCommandArgumentKernels.TryGetProjectOperand(
            new[] { "--project", "ignored", "--file", "Program.nl", "samples/demo" },
            new[] { "--project", "--file" },
            out var projectPath));
        Assert.Equal("samples/demo", projectPath);
    }

    [Fact]
    public void UpdateCommandKernels_SelectsTargetPackage()
    {
        Assert.True(UpdateCommandKernels.TryGetTargetPackage(
            new[] { "--dry-run", "Newtonsoft.Json" },
            out var dogfoodTarget));
        Assert.Equal("Newtonsoft.Json", dogfoodTarget);
        Assert.Equal("Newtonsoft.Json", UpdateCommand.GetTargetPackage(new[] { "--dry-run", "Newtonsoft.Json" }));
        Assert.Equal("Serilog", UpdateCommand.GetTargetPackage(new[] { "--dry-run", "-v", "Serilog" }));
        Assert.Null(UpdateCommand.GetTargetPackage(new[] { "--dry-run" }));
    }

    [Fact]
    public void AddCommandKernels_SelectsPackageOperand()
    {
        Assert.True(AddCommandKernels.TryGetPackageOperand(
            new[] { "--version", "13.0.3", "--framework", "Newtonsoft.Json" },
            new[] { "--version", "--path" },
            out var dogfoodPackage));
        Assert.Equal("Newtonsoft.Json", dogfoodPackage);
        Assert.Equal(
            "Newtonsoft.Json",
            AddCommand.GetPackageOperand(new[] { "--version", "13.0.3", "--framework", "Newtonsoft.Json" }));
        Assert.Equal(
            "Serilog@3.1.1",
            AddCommand.GetPackageOperand(new[] { "--prerelease", "Serilog@3.1.1" }));
        Assert.Null(AddCommand.GetPackageOperand(new[] { "--version", "13.0.3" }));
    }

    [Fact]
    public void LintCommandKernels_SelectsFileArgsAfterProjectValueExclusion()
    {
        Assert.True(LintCommandKernels.TryGetFileArgs(Array.Empty<string>(), out var empty));
        Assert.Empty(empty);

        var args = new[]
        {
            "--json",
            "--project",
            "src",
            "Program.nl",
            "src",
            "help",
            "-v",
            "Other.nl",
            "--project",
            "tests",
            "tests"
        };

        Assert.True(LintCommandKernels.TryGetFileArgs(args, out var files));
        Assert.Equal(new[] { "Program.nl", "Other.nl" }, files);
    }

    [Fact]
    public void RemoveCommandKernels_SelectsPackageOperand()
    {
        Assert.True(RemoveCommandKernels.TryGetPackageOperand(
            new[] { "--dry-run", "Serilog" },
            out var dogfoodPackage));
        Assert.Equal("Serilog", dogfoodPackage);
        Assert.Equal("Newtonsoft.Json", RemoveCommand.GetPackageOperand(new[] { "Newtonsoft.Json" }));
        Assert.Equal("Serilog", RemoveCommand.GetPackageOperand(new[] { "--dry-run", "Serilog" }));
        Assert.Null(RemoveCommand.GetPackageOperand(new[] { "--dry-run" }));
    }

    [Fact]
    public void ExportCommandKernels_SelectsInputOperandAfterOrderedOptionStripping()
    {
        Assert.True(ExportCommandKernels.TryGetCSharpInputOperand(
            new[] { "Program.nl", "--output", "Program.cs" },
            out var sourceFirst));
        Assert.Equal("Program.nl", sourceFirst);

        Assert.True(ExportCommandKernels.TryGetCSharpInputOperand(
            new[] { "--output", "dist", "Program.nl" },
            out var outputFirst));
        Assert.Equal("Program.nl", outputFirst);

        Assert.True(ExportCommandKernels.TryGetCSharpInputOperand(
            new[] { "-o", "--output", "file" },
            out var shortOutputConsumesLongOutput));
        Assert.Null(shortOutputConsumesLongOutput);

        Assert.True(ExportCommandKernels.TryGetCSharpInputOperand(
            new[] { "--output", "--project", "file" },
            out var longOutputConsumesProject));
        Assert.Equal("file", longOutputConsumesProject);
    }

    [Fact]
    public void BuildCommandKernels_SelectsFirstOperandAfterOptionStripping()
    {
        Assert.True(BuildCommandKernels.TryGetOperandSummary(
            Array.Empty<string>(),
            out var emptyCount,
            out var emptyIndex));
        Assert.Equal(0, emptyCount);
        Assert.Equal(-1, emptyIndex);

        var args = new[]
        {
            "--release",
            "--output",
            "bin/app",
            "--backend",
            "il",
            "--project",
            "samples/demo",
            "--timings",
            "Program.nl"
        };

        Assert.True(BuildCommandKernels.TryGetOperandSummary(args, out var count, out var firstOperandIndex));
        Assert.Equal(1, count);
        Assert.Equal(8, firstOperandIndex);
        Assert.Equal("Program.nl", args[firstOperandIndex]);

        Assert.True(BuildCommandKernels.TryGetOperandSummary(
            new[] { "Main.nl", "--backend", "il" },
            out var sourceFirstCount,
            out var sourceFirstIndex));
        Assert.Equal(1, sourceFirstCount);
        Assert.Equal(0, sourceFirstIndex);
    }

    [Fact]
    public void BuildCommandKernels_SummarizesOptions()
    {
        var args = new[]
        {
            "--release",
            "-o",
            "short-out",
            "--output",
            "dist",
            "--backend",
            "il",
            "--project",
            "samples/demo",
            "--verbose",
            "--timings",
            "--perf-report",
            "--aot",
            "Program.nl"
        };

        Assert.True(BuildCommandKernels.TryGetOptionSummary(args, out var summary));
        Assert.Equal("dist", summary.OutputDir);
        Assert.Equal("il", summary.BackendOption);
        Assert.Equal("samples/demo", summary.ProjectOption);
        Assert.True(summary.Release);
        Assert.True(summary.Verbose);
        Assert.True(summary.Timings);
        Assert.True(summary.PerfReport);
        Assert.True(summary.Aot);
    }

    [Fact]
    public void RunCommandKernels_SelectsSourceOperandAfterBackendStripping()
    {
        Assert.True(RunCommandKernels.TryGetSourceOperand(
            Array.Empty<string>(),
            out var empty));
        Assert.Null(empty);

        Assert.True(RunCommandKernels.TryGetSourceOperand(
            new[] { "--backend", "il" },
            out var projectRun));
        Assert.Null(projectRun);

        Assert.True(RunCommandKernels.TryGetSourceOperand(
            new[] { "--backend", "il", "Program.nl" },
            out var backendFirst));
        Assert.Equal("Program.nl", backendFirst);

        Assert.True(RunCommandKernels.TryGetSourceOperand(
            new[] { "Program.nl", "--backend", "il" },
            out var sourceFirst));
        Assert.Equal("Program.nl", sourceFirst);

        Assert.True(RunCommandKernels.TryGetSourceOperand(
            new[] { "--backend" },
            out var danglingBackend));
        Assert.Equal("--backend", danglingBackend);

        Assert.Equal(
            "Program.nl",
            Program.GetRunSourceOperand(new[] { "--backend", "--unknown", "Program.nl" }));
    }

    [Fact]
    public void PublishCommandKernels_NormalizesDefaultOptionsAndFallbackValidation()
    {
        Assert.True(PublishCommandKernels.TryGetArgumentSummary(
            Array.Empty<string>(),
            out var defaultSummary));
        Assert.Null(defaultSummary.ValidationError);
        Assert.Null(defaultSummary.ProjectOption);
        Assert.Null(defaultSummary.BackendOption);
        Assert.Equal("Release", defaultSummary.Configuration);
        Assert.Null(defaultSummary.Output);
        Assert.Null(defaultSummary.Runtime);
        Assert.False(defaultSummary.SelfContained);
        Assert.False(defaultSummary.Aot);
        Assert.False(PublishCommandKernels.TryGetArgumentSummary(new[] { "-c", "Debug" }, out _));

        var args = new[]
        {
            "-c", "Debug",
            "--output", "dist",
            "--runtime", "osx-arm64",
            "--aot",
            "--self-contained",
            "--project", "samples/demo",
            "--backend", "il",
            "--configuration", "Release",
            "-o", "ignored-output",
            "-r", "ignored-runtime"
        };

        var summary = Program.GetPublishArgumentSummary(args);
        Assert.Null(summary.ValidationError);
        Assert.Equal("samples/demo", summary.ProjectOption);
        Assert.Equal("il", summary.BackendOption);
        Assert.Equal("Release", summary.Configuration);
        Assert.Equal("dist", summary.Output);
        Assert.Equal("osx-arm64", summary.Runtime);
        Assert.True(summary.SelfContained);
        Assert.True(summary.Aot);

        var missingValue = Program.GetPublishArgumentSummary(new[] { "--project", "--backend", "il" });
        Assert.Equal("Option '--project' requires a value.", missingValue.ValidationError);

        var targetPlatform = Program.GetPublishArgumentSummary(new[] { "--target", "linux-x64" });
        Assert.Equal(
            "Target-platform publishing is expressed as --runtime <rid>, and nlc publish does not support cross-runtime publishing yet.",
            targetPlatform.ValidationError);

        var unknown = Program.GetPublishArgumentSummary(new[] { "--mystery" });
        Assert.Equal("Unknown publish option '--mystery'. Run 'nlc publish --help' for supported options.", unknown.ValidationError);

        Assert.Equal(
            "Debug",
            Program.GetPublishArgumentSummary(new[] { "-c", "Debug" }).Configuration);
    }

    [Fact]
    public void ExportCommandKernels_FiltersReferenceValuesByType()
    {
        var references = new[]
        {
            new Reference { Nuget = "Serilog", Version = "3.1.1" },
            new Reference { Framework = "Microsoft.AspNetCore.App" },
            new Reference { Dll = "lib/Analyzer.dll" },
            new Reference { Project = "../Shared/project.yml" },
            new Reference { Nuget = "YamlDotNet", Version = "16.0.0" },
            new Reference { Framework = "Microsoft.WindowsDesktop.App" }
        };

        Assert.True(ExportCommandKernels.TryFilterReferencesByType(
            references,
            ReferenceType.NuGet,
            out var packageReferences));
        Assert.Equal(new[] { "Serilog", "YamlDotNet" }, packageReferences.Select(reference => reference.Nuget).ToArray());

        Assert.True(ExportCommandKernels.TryFilterReferencesByType(
            references,
            ReferenceType.Framework,
            out var frameworkReferences));
        Assert.Equal(new[] { "Microsoft.AspNetCore.App", "Microsoft.WindowsDesktop.App" }, frameworkReferences.Select(reference => reference.Framework).ToArray());

        Assert.True(ExportCommandKernels.TryFilterReferencesByType(
            references,
            ReferenceType.Dll,
            out var dllReferences));
        Assert.Equal(new[] { "lib/Analyzer.dll" }, dllReferences.Select(reference => reference.Dll).ToArray());

        Assert.True(ExportCommandKernels.TryFilterReferencesByType(
            references,
            ReferenceType.Project,
            out var projectReferences));
        Assert.Equal(new[] { "../Shared/project.yml" }, projectReferences.Select(reference => reference.Project).ToArray());
    }

    [Fact]
    public void ExportCommandKernels_DeduplicatesReferenceValues()
    {
        var projectReferences = new[]
        {
            "../Shared/Shared.csproj",
            "../shared/shared.csproj",
            "../Models/Models.csproj",
            "../Shared/SHARED.csproj",
            "../Utilities/Utilities.csproj",
            "../models/models.csproj"
        };

        Assert.True(ExportCommandKernels.TryDeduplicateReferences(
            projectReferences,
            StringComparer.OrdinalIgnoreCase,
            out var distinctProjectReferences));
        Assert.Equal(new[]
        {
            "../Shared/Shared.csproj",
            "../Models/Models.csproj",
            "../Utilities/Utilities.csproj"
        }, distinctProjectReferences);

        var packageReferences = new[]
        {
            new ExportReferenceValue("Newtonsoft.Json", "13.0.3"),
            new ExportReferenceValue("Serilog", "3.1.1"),
            new ExportReferenceValue("Newtonsoft.Json", "13.0.3"),
            new ExportReferenceValue("Newtonsoft.Json", "14.0.0"),
            new ExportReferenceValue("Serilog", "3.1.1")
        };

        Assert.True(ExportCommandKernels.TryDeduplicateReferences(
            packageReferences,
            comparer: null,
            out var distinctPackageReferences));
        Assert.Equal(new[]
        {
            packageReferences[0],
            packageReferences[1],
            packageReferences[3]
        }, distinctPackageReferences);
    }

    [Fact]
    public void RestoreCommandKernels_DeduplicatesProjectReferences()
    {
        var projectReferences = new[]
        {
            "../Shared/Shared.csproj",
            "../shared/shared.csproj",
            "../Models/Models.csproj",
            "../Shared/SHARED.csproj",
            "../Utilities/Utilities.csproj",
            "../models/models.csproj"
        };

        Assert.True(RestoreCommandKernels.TryDeduplicateProjectReferences(
            projectReferences,
            out var dogfoodReferences));
        Assert.Equal(new[]
        {
            "../Shared/Shared.csproj",
            "../Models/Models.csproj",
            "../Utilities/Utilities.csproj"
        }, dogfoodReferences);
        Assert.Equal(dogfoodReferences, RestoreCommand.DeduplicateProjectReferences(projectReferences));
    }

    [Fact]
    public void RestoreCommandKernels_FiltersProjectReferences()
    {
        var references = new[]
        {
            new Reference { Nuget = "Serilog", Version = "3.1.1" },
            new Reference { Project = "../Shared/project.yml" },
            new Reference { Dll = "lib/Analyzer.dll" },
            new Reference { Project = "../Models/project.yml" },
            new Reference { Framework = "Microsoft.AspNetCore.App" }
        };

        Assert.True(RestoreCommandKernels.TryFilterReferencesByType(
            references,
            ReferenceType.Project,
            out var projectReferences));
        Assert.Equal(
            new[] { "../Shared/project.yml", "../Models/project.yml" },
            projectReferences.Select(reference => reference.Project).ToArray());
    }

    [Fact]
    public void CompilationReferenceResolverKernels_FiltersReferenceValuesByType()
    {
        var references = new[]
        {
            new Reference { Nuget = "Serilog", Version = "3.1.1" },
            new Reference { Framework = "Microsoft.AspNetCore.App" },
            new Reference { Dll = "lib/Analyzer.dll" },
            new Reference { Project = "../Shared/project.yml" },
            new Reference { Nuget = "YamlDotNet", Version = "16.0.0" }
        };

        Assert.True(CompilationReferenceResolverKernels.TryFilterReferencesByType(
            references,
            ReferenceType.NuGet,
            out var packageReferences));
        Assert.Equal(new[] { "Serilog", "YamlDotNet" }, packageReferences.Select(reference => reference.Nuget).ToArray());
    }

    [Fact]
    public void CompilationReferenceResolverKernels_SelectsFirstHighestCompatibleScore()
    {
        var scores = new[] { -1, 40, 900, 120, 900, 30 };

        Assert.True(CompilationReferenceResolverKernels.TrySelectBestScoreIndex(scores, scores.Length, out var bestIndex));
        Assert.Equal(2, bestIndex);

        Assert.True(CompilationReferenceResolverKernels.TrySelectBestScoreIndex(new[] { -1, -1 }, 2, out var noMatchIndex));
        Assert.Equal(-1, noMatchIndex);

        Assert.True(CompilationReferenceResolverKernels.TrySelectBestScoreIndex(scores, 0, out var emptyIndex));
        Assert.Equal(-1, emptyIndex);

        Assert.False(CompilationReferenceResolverKernels.TrySelectBestScoreIndex(scores, scores.Length + 1, out _));
    }

    [Theory]
    [InlineData("src/Program.nl", true)]
    [InlineData("bin/Debug/Generated.nl", false)]
    [InlineData("obj/generated/Temporary.nl", false)]
    [InlineData("Tests/FIXTURES/format/case.nl", false)]
    [InlineData("editors\\vscode\\test\\fixtures\\errors\\Bad.nl", false)]
    [InlineData(".nlc/cache/File.nl", false)]
    [InlineData("src/node_modulesx/File.nl", true)]
    public void FormatCommandKernels_SelectsDiscoveredPaths(string relativePath, bool expected)
    {
        Assert.True(FormatCommandKernels.TryShouldFormatDiscoveredPath(relativePath, out var shouldFormat));
        Assert.Equal(expected, shouldFormat);
    }

    [Fact]
    public void RestoreCommand_DeduplicatesProjectReferencesInGeneratedProps()
    {
        static int CountOccurrences(string text, string value)
        {
            var count = 0;
            var index = 0;
            while ((index = text.IndexOf(value, index, StringComparison.Ordinal)) >= 0)
            {
                count++;
                index += value.Length;
            }

            return count;
        }

        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-restore-dedup-{Guid.NewGuid():N}");
        var appDir = Path.Combine(tempDir, "App");
        var sharedDir = Path.Combine(tempDir, "Shared");
        Directory.CreateDirectory(appDir);
        Directory.CreateDirectory(sharedDir);

        try
        {
            File.WriteAllText(Path.Combine(sharedDir, "project.yml"), """
name: Shared
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(sharedDir, "Shared.csproj"), """<Project Sdk="NSharpLang.Sdk" />""");
            File.WriteAllText(Path.Combine(appDir, "project.yml"), """
name: App
outputType: exe
targetFramework: net10.0

dependencies:
  - nuget: Serilog
    version: 3.1.1
  - framework: Microsoft.AspNetCore.App
  - project: ../Shared/project.yml
  - project: ../Shared/Shared.csproj
  - project: ../Shared/project.yml
""");

            Assert.Equal(0, RestoreCommand.Restore(appDir, quiet: true));

            var props = File.ReadAllText(Path.Combine(appDir, "obj", "project.g.props"));
            Assert.Equal(1, CountOccurrences(props, "<ProjectReference Include="));
            Assert.Contains(Path.Combine(sharedDir, "Shared.csproj"), props);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompilerErrorSeverityFilter_FiltersCompilerErrorsBySeverity()
    {
        var errors = new[]
        {
            NewError("parse warning", ErrorSeverity.Warning),
            NewError("parse error", ErrorSeverity.Error),
            NewError("backend error", ErrorSeverity.Error),
            NewError("lint warning", ErrorSeverity.Warning),
            NewError("aot error", ErrorSeverity.Error)
        };

        Assert.True(CompilerErrorSeverityFilter.TryFilter(
            errors,
            ErrorSeverity.Error,
            out var actualErrors));
        Assert.Equal(
            errors.Where(error => error.Severity == ErrorSeverity.Error),
            actualErrors);

        Assert.True(CompilerErrorSeverityFilter.TryFilter(
            errors,
            ErrorSeverity.Warning,
            out var actualWarnings));
        Assert.Equal(
            errors.Where(error => error.Severity == ErrorSeverity.Warning),
            actualWarnings);

        static CompilerError NewError(string message, ErrorSeverity severity) =>
            new(ErrorCode.InvalidSyntax, message, 1, 1, severity);
    }

    [Fact]
    public void QuerySymbolNameFilter_FiltersSymbolsByNamePattern()
    {
        var symbols = new[]
        {
            NewSymbol("UserService"),
            NewSymbol("OrderService"),
            NewSymbol("UserQuery"),
            NewSymbol("RenderPipeline"),
            NewSymbol("CurrentUser")
        };

        Assert.True(QuerySymbolNameFilter.TryFilter(
            symbols,
            "user",
            200,
            out var substringMatches));
        Assert.Equal(
            new[] { "UserService", "UserQuery", "CurrentUser" },
            substringMatches.Select(symbol => symbol.Name));

        Assert.True(QuerySymbolNameFilter.TryFilter(
            symbols,
            "*Service",
            200,
            out var globMatches));
        Assert.Equal(
            new[] { "UserService", "OrderService" },
            globMatches.Select(symbol => symbol.Name));

        Assert.True(QuerySymbolNameFilter.TryFilter(
            symbols,
            "*",
            2,
            out var limitedMatches));
        Assert.Equal(
            new[] { "UserService", "OrderService" },
            limitedMatches.Select(symbol => symbol.Name));

        Assert.False(QuerySymbolNameFilter.TryFilter(
            new[] { NewSymbol("café") },
            "caf*",
            200,
            out _));

        static SymbolResult NewSymbol(string name) =>
            new(
                name,
                SymbolKind.Function,
                "Program.nl",
                1,
                1,
                null,
                null,
                null,
                null);
    }

    [Fact]
    public void FixCommandKernels_FiltersFixesBySafety()
    {
        var fixes = new[]
        {
            NewFix("safe import", FixSafety.Safe),
            NewFix("review unused variable", FixSafety.ReviewNeeded),
            NewFix("suggest rewrite", FixSafety.SuggestionOnly),
            NewFix("safe empty catch", FixSafety.Safe),
            NewFix("review null access", FixSafety.ReviewNeeded)
        };

        Assert.True(FixCommandKernels.TryFilterBySafety(
            fixes,
            includeReviewNeeded: false,
            out var defaultSafeActions));
        Assert.Equal(
            fixes.Where(fix => fix.Safety == FixSafety.Safe),
            defaultSafeActions);

        Assert.True(FixCommandKernels.TryFilterBySafety(
            fixes,
            includeReviewNeeded: true,
            out var reviewSafeActions));
        Assert.Equal(
            fixes.Where(fix => fix.Safety is FixSafety.Safe or FixSafety.ReviewNeeded),
            reviewSafeActions);

        static CodeAction NewFix(string title, FixSafety safety) =>
            new(title, "NL000", new List<TextEdit>(), Safety: safety);
    }

    [Fact]
    public void FixCommandKernels_SelectsSkippedFixEntries()
    {
        var entries = new[]
        {
            NewEntry("safe import", "safe"),
            NewEntry("review unused variable", "reviewNeeded"),
            NewEntry("suggest rewrite", "suggestionOnly"),
            NewEntry("unknown safety", "unknown"),
            NewEntry("safe empty catch", "safe"),
            NewEntry("review null access", "reviewNeeded")
        };

        Assert.True(FixCommandKernels.TrySelectSkippedEntries(
            entries,
            includeReviewNeeded: false,
            out var defaultSkipped));
        Assert.Equal(
            entries.Where(entry => entry.Safety is not "safe"),
            defaultSkipped);

        Assert.True(FixCommandKernels.TrySelectSkippedEntries(
            entries,
            includeReviewNeeded: true,
            out var reviewSkipped));
        Assert.Equal(
            entries.Where(entry => entry.Safety is not "safe" and not "reviewNeeded"),
            reviewSkipped);

        static FixEntry NewEntry(string title, string safety) =>
            new("Program.nl", "NL000", title, new List<TextEdit>(), safety);
    }

    [Fact]
    public void FixCommandKernels_GroupsAppliedFixEntriesByFile()
    {
        var entries = new[]
        {
            NewEntry("src/B.nl", "NL001", "first b"),
            NewEntry("src/A.nl", "NL002", "first a"),
            NewEntry("src/B.nl", "NL003", "second b"),
            NewEntry("src/C.nl", "NL004", "first c"),
            NewEntry("src/A.nl", "NL005", "second a")
        };

        Assert.True(FixCommandKernels.TryGroupAppliedEntriesByFile(entries, out var grouping));

        var actual = new List<(string File, string Code, string Title)>();
        for (var groupIndex = 0; groupIndex < grouping.GroupCount; groupIndex++)
        {
            var start = grouping.Starts[groupIndex];
            var count = grouping.Counts[groupIndex];
            for (var i = 0; i < count; i++)
            {
                var entry = entries[grouping.Indices[start + i]];
                actual.Add((grouping.Files[groupIndex], entry.DiagnosticCode, entry.Title));
            }
        }

        var expected = entries
            .GroupBy(entry => entry.File)
            .SelectMany(group => group.Select(entry => (group.Key, entry.DiagnosticCode, entry.Title)))
            .ToArray();
        Assert.Equal(expected, actual);

        static FixEntry NewEntry(string file, string code, string title) =>
            new(file, code, title, new List<TextEdit>(), "safe");
    }

    [Fact]
    public void TidyCommandKernels_SelectsAndClassifiesDependencies()
    {
        var dependencies = new[]
        {
            NewDependency("Newtonsoft.Json", "used"),
            NewDependency("Serilog", "possibly-unused"),
            NewDependency("Polly", "unknown"),
            NewDependency("Humanizer", "possibly-unused"),
            NewDependency("Custom.Package", "custom")
        };

        var references = new[]
        {
            new Reference { Nuget = "Newtonsoft.Json", Version = "13.0.3" },
            new Reference { Nuget = "Serilog.Sinks.Console", Version = "5.0.1" },
            new Reference { Nuget = "Polly", Version = "8.0.0" },
            new Reference { Nuget = "Microsoft.Extensions.Logging", Version = "10.0.0" },
            new Reference { Nuget = "Custom.Package", Version = "1.0.0" }
        };
        var imports = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Newtonsoft.Json.Linq",
            "Microsoft.Extensions.Logging"
        };

        Assert.True(TidyCommandKernels.TryClassifyDependencyStatusRanks(
            references,
            imports,
            out var statusRanks));
        Assert.Equal(new[] { 2, 1, 3, 2, 1 }, statusRanks);

        Assert.True(TidyCommandKernels.TrySelectPossiblyUnusedDependencies(
            dependencies,
            static dependency => dependency.Status,
            out var actual));
        Assert.Equal(
            dependencies.Where(dependency => dependency.Status == "possibly-unused"),
            actual);

        Assert.True(TidyCommandKernels.TrySummarizeDependencyStatuses(
            dependencies,
            static dependency => dependency.Status,
            out var summary));
        Assert.Equal(2, summary.PossiblyUnusedCount);
        Assert.Equal(1, summary.UnknownCount);

        var nonAsciiReferences = new[]
        {
            new Reference { Nuget = "Résumé.Json", Version = "1.0.0" }
        };
        Assert.False(TidyCommandKernels.TryClassifyDependencyStatusRanks(
            nonAsciiReferences,
            imports,
            out _));

        static TidyDependency NewDependency(string name, string status) => new(name, status);
    }

    [Fact]
    public void TestCommandKernels_SummarizesTestOutcomeRanks()
    {
        Assert.True(TestCommandKernels.TrySummarizeOutcomeRanks(
            new[] { 1, 1, 3, 2, 0, 1 },
            6,
            out var testSummary));
        Assert.False(testSummary.Ok);
        Assert.Equal(3, testSummary.Passed);
        Assert.Equal(1, testSummary.Failed);
        Assert.Equal(1, testSummary.Skipped);
    }

    [Fact]
    public void TestCommandKernels_SummarizesOptions()
    {
        var args = new[]
        {
            "--project",
            "samples/demo",
            "--backend",
            "il",
            "--filter",
            "Adds",
            "--timeout",
            "30s",
            "--verbose",
            "--json",
            "--coverage-report",
            "--no-cache"
        };

        Assert.True(TestCommandKernels.TryGetOptionSummary(args, out var summary));
        Assert.Equal("samples/demo", summary.ProjectOption);
        Assert.Equal("il", summary.BackendOption);
        Assert.Equal("Adds", summary.Filter);
        Assert.Equal("30s", summary.Timeout);
        Assert.True(summary.Verbose);
        Assert.True(summary.JsonOutput);
        Assert.True(summary.CoverageReport);
        Assert.True(summary.CollectCoverage);
        Assert.True(summary.NoCache);
    }

    [Fact]
    public void TidyCommandKernels_FiltersRemovalLines()
    {
        var lines = new[]
        {
            "dependencies:",
            "  - Serilog.Sinks.Console@5.0.1",
            "  - nuget: Newtonsoft.Json",
            "  - NUGET: unused.package",
            "  - framework: Microsoft.AspNetCore.App",
            "  - project: ../Shared/Shared.csproj",
            "  - Other.Package",
            "  - SerilogExtra",
            "name: Demo"
        };
        var packageNames = new[]
        {
            "Serilog",
            "Newtonsoft.Json",
            "Unused.Package"
        };

        Assert.True(TidyCommandKernels.TryFilterRemovalLines(
            lines,
            packageNames,
            out var filteredLines));

        Assert.Equal(
            new[]
            {
                "dependencies:",
                "  - framework: Microsoft.AspNetCore.App",
                "  - project: ../Shared/Shared.csproj",
                "  - Other.Package",
                "name: Demo"
            },
            filteredLines);

        Assert.False(TidyCommandKernels.TryFilterRemovalLines(
            new[] { "  - R\u00e9sum\u00e9.Package" },
            packageNames,
            out _));
        Assert.False(TidyCommandKernels.TryFilterRemovalLines(
            lines,
            new[] { "R\u00e9sum\u00e9.Package" },
            out _));
    }

    [Fact]
    public void DocCommandKernels_OrdersSymbolsForGeneration()
    {
        var symbols = new[]
        {
            NewSymbol("zeta", SymbolKind.Method),
            NewSymbol("alpha", SymbolKind.Function),
            NewSymbol("ignoredVariable", SymbolKind.Variable),
            NewSymbol("Customer", SymbolKind.Class),
            NewSymbol("ignoredParameter", SymbolKind.Parameter),
            NewSymbol("alpha", SymbolKind.Function),
            NewSymbol("OrderState", SymbolKind.Enum),
            NewSymbol("Name", SymbolKind.Property),
            NewSymbol("alpha", SymbolKind.Method),
            NewSymbol("Amount", SymbolKind.TypeAlias),
            NewSymbol("Account", SymbolKind.Class)
        };

        var expected = symbols
            .Where(symbol => symbol.Kind is not SymbolKind.Variable and not SymbolKind.Parameter)
            .OrderBy(symbol => symbol.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(symbol => symbol.Name, StringComparer.Ordinal)
            .ToList();

        Assert.True(DocCommandKernels.TryOrderSymbolsForGeneration(symbols, out var actual));
        Assert.Equal(expected, actual);

        static SymbolResult NewSymbol(string name, SymbolKind kind) =>
            new(name, kind, "/tmp/Program.nl", 1, 1, null, null, null, null);
    }

    [Fact]
    public void DocCommandKernels_OrdersMembersForGeneration()
    {
        var members = new[]
        {
            NewSymbol("zeta", SymbolKind.Method),
            NewSymbol("alpha", SymbolKind.Function),
            NewSymbol("value", SymbolKind.Variable),
            NewSymbol("customer", SymbolKind.Parameter),
            NewSymbol("Customer", SymbolKind.Class),
            NewSymbol("Name", SymbolKind.Property),
            NewSymbol("alpha", SymbolKind.Method),
            NewSymbol("Amount", SymbolKind.Field)
        };

        var expected = members
            .OrderBy(member => member.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(member => member.Name, StringComparer.Ordinal)
            .ToList();

        Assert.True(DocCommandKernels.TryOrderMembersForGeneration(members, out var actual));
        Assert.Equal(expected, actual);

        static SymbolResult NewSymbol(string name, SymbolKind kind) =>
            new(name, kind, "/tmp/Program.nl", 1, 1, null, null, null, null);
    }

    [Fact]
    public void DocCommandKernels_CreatesSlugs()
    {
        var rawSlugs = new[]
        {
            "Class-Customer-/tmp/Customer.nl",
            "Method-GetById-Service.Core.nl",
            "TypeAlias-Result<T>-Errors.nl",
            "Function-R\u00e9sum\u00e9_Count-Reports 2026.nl",
            "Property-HTTPClient2-API.Client.nl"
        };

        Assert.True(DocCommandKernels.TryCreateSlugs(rawSlugs, out var actual));
        Assert.Equal(rawSlugs.Select(CreateExpectedDocSlug).ToArray(), actual);

        static string CreateExpectedDocSlug(string raw)
        {
            var chars = raw
                .ToLowerInvariant()
                .Select(ch => char.IsLetterOrDigit(ch) ? ch : '-')
                .ToArray();
            return string.Join(string.Empty, new string(chars).Split('-', StringSplitOptions.RemoveEmptyEntries));
        }
    }

    [Fact]
    public void BatchCommand_TextMode_IsRejected()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, "[]");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "batch",
                "--text",
                "--requests", requestsPath
            }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("Batch queries only support JSON output.", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_ReportsMissingImportDiagnostics()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-check-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
    Console.WriteLine(sb.ToString())
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            var doc = JsonDocument.Parse(stdout);
            Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Contains(doc.RootElement.GetProperty("results").EnumerateArray(),
                result => result.GetProperty("code").GetString() == "NL002");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_CircularFileImports_ReportCyclePathInJsonAndText()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-circular-import-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CircularImports
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "A.nl"), """
import "B"

class A {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "B.nl"), """
import "C"

class B {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "C.nl"), """
import "A"

class C {
}
""");

            var (jsonExitCode, jsonStdout, jsonStderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));
            var (textExitCode, textStdout, textStderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir, "--text" }));

            Assert.Equal(1, jsonExitCode);
            Assert.True(string.IsNullOrWhiteSpace(jsonStderr));
            using var doc = JsonDocument.Parse(jsonStdout);
            var diagnostic = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray(),
                result => result.GetProperty("code").GetString() == "NL703");
            var jsonMessage = diagnostic.GetProperty("message").GetString();
            var jsonExplanation = diagnostic.GetProperty("explanation").GetString();
            var jsonHint = diagnostic.GetProperty("hint").GetString();
            var jsonSuggestion = diagnostic.GetProperty("suggestion").GetString();
            Assert.Contains("A.nl -> B.nl -> C.nl -> A.nl", jsonMessage);
            Assert.Contains("A.nl -> B.nl -> C.nl -> A.nl", jsonExplanation);
            Assert.Contains("Import path: A.nl -> B.nl -> C.nl -> A.nl", jsonHint);
            Assert.Contains("Move shared types", jsonSuggestion);

            Assert.Equal(1, textExitCode);
            Assert.True(string.IsNullOrWhiteSpace(textStdout));
            Assert.Contains("A.nl -> B.nl -> C.nl -> A.nl", textStderr);
            Assert.Contains("Move shared types", textStderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_LongCircularFileImports_BoundsCyclePathInJsonAndText()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-circular-import-long-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: LongCircularImports
outputType: exe
targetFramework: net10.0
""");

            const int fileCount = 12;
            for (var i = 0; i < fileCount; i++)
            {
                var current = $"F{i:00}";
                var next = $"F{(i + 1) % fileCount:00}";
                File.WriteAllText(Path.Combine(tempDir, $"{current}.nl"), $$"""
import "{{next}}"

class {{current}} {
}
""");
            }

            var (jsonExitCode, jsonStdout, jsonStderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));
            var (textExitCode, textStdout, textStderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir, "--text" }));

            Assert.Equal(1, jsonExitCode);
            Assert.True(string.IsNullOrWhiteSpace(jsonStderr));
            using var doc = JsonDocument.Parse(jsonStdout);
            var diagnostic = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray(),
                result => result.GetProperty("code").GetString() == "NL703");
            var jsonMessage = diagnostic.GetProperty("message").GetString();
            var jsonHint = diagnostic.GetProperty("hint").GetString();
            Assert.Contains("F00.nl -> F01.nl -> F02.nl -> F03.nl -> F04.nl -> F05.nl", jsonMessage);
            Assert.Contains("... (4 more imports) -> F10.nl -> F11.nl -> F00.nl", jsonMessage);
            Assert.DoesNotContain("F06.nl -> F07.nl -> F08.nl -> F09.nl", jsonMessage);
            Assert.Contains("... (4 more imports)", jsonHint);

            Assert.Equal(1, textExitCode);
            Assert.True(string.IsNullOrWhiteSpace(textStdout));
            Assert.Contains("... (4 more imports) -> F10.nl -> F11.nl -> F00.nl", textStderr);
            Assert.DoesNotContain("F06.nl -> F07.nl -> F08.nl -> F09.nl", textStderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_PackageImport_AllowsPascalCaseExports()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-package-exports-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
package Models

class Item {
    func Visible(): string {
        return "visible"
    }
}

public class explicitItem {
    public func visibleExplicit(): string {
        return "explicit"
    }
}

func BuildItem(): Item {
    return new Item()
}

enum Status {
    Ready,
    hidden
}

public func buildExplicit(): explicitItem {
    return new explicitItem()
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import Models

package App

func Main() {
    item := BuildItem()
    explicitValue := buildExplicit()
    print item.Visible()
    print explicitValue.visibleExplicit()
    print Status.hidden
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
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
    public void CheckCommand_PackageImport_RejectsCamelCaseTypesMembersAndFunctions()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-package-hidden-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
package Models

class Item {
    func hiddenMethod(): string {
        return "hidden"
    }
}

private class SecretPascal {
}

class hiddenThing {
}

union Outcome {
    Ok
    hidden
}

func hiddenFunction(): string {
    return "hidden"
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import Models

package App

func Main() {
    thing := new hiddenThing()
    secret := new SecretPascal()
    item := new Item()
    print item.hiddenMethod()
    print Outcome.hidden
    print hiddenFunction()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenThing' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'SecretPascal' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenMethod' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hidden' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenFunction' is not exported"));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_InaccessibleMember_ReportsNL308WithMemberNameSpan()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-nl308-span-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: InaccessibleSpan
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Widget.nl"), """
package Models

class Widget {
    func secretMethod(): string {
        return "x"
    }
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import Models

package App

func Main() {
    w := new Widget()
    print w.secretMethod()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();

            var diagnostic = Assert.Single(results,
                result => result.GetProperty("message").GetString()!.Contains("'secretMethod' is not exported"));
            Assert.Equal("NL308", diagnostic.GetProperty("code").GetString());
            // `print w.secretMethod()` — column 13 is where `secretMethod` begins (1-based).
            Assert.Equal(7, diagnostic.GetProperty("line").GetInt32());
            Assert.Equal(13, diagnostic.GetProperty("column").GetInt32());
            Assert.Equal("secretMethod".Length, diagnostic.GetProperty("length").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_PackageImport_UsesImportedPackageBeforeDuplicateProjectSymbolAmbiguity()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-package-duplicate-export-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));
        Directory.CreateDirectory(Path.Combine(tempDir, "Other"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
package Models

class Item {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Other", "Item.nl"), """
package Other

class Item {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import Models

package App

func Main() {
    _item := new Item()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_PackageImport_ReportsUnexportedImportedDuplicateInsteadOfAmbiguity()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-package-duplicate-hidden-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));
        Directory.CreateDirectory(Path.Combine(tempDir, "Other"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
package Models

class hiddenThing {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Other", "Item.nl"), """
package Other

class hiddenThing {
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import Models

package App

func Main() {
    thing := new hiddenThing()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenThing' is not exported"));
            Assert.DoesNotContain(results, result => result.GetProperty("message").GetString()!.Contains("defined in multiple files"));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_NamespaceImport_RejectsCamelCaseTypesMembersAndFunctions()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-namespace-hidden-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Directory.CreateDirectory(Path.Combine(tempDir, "Models"));

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: NamespaceVisibility
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models", "Item.nl"), """
namespace Models

class Item {
    func hiddenMethod(): string {
        return "hidden"
    }
}

private class SecretPascal {
}

class hiddenThing {
}

enum Status {
    Ready,
    hidden
}

union Outcome {
    Ok
    hidden
}

func hiddenFunction(): string {
    return "hidden"
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
namespace App

import Models

func Main() {
    thing := new hiddenThing()
    secret := new SecretPascal()
    item := new Item()
    print item.hiddenMethod()
    print Outcome.hidden
    print hiddenFunction()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            using var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenThing' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'SecretPascal' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenMethod' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hidden' is not exported"));
            Assert.Contains(results, result => result.GetProperty("message").GetString()!.Contains("'hiddenFunction' is not exported"));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_MissingProject_ReturnsStructuredErrorEnvelope()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-missing-{Guid.NewGuid():N}");

        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", missingDir }));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        var doc = JsonDocument.Parse(stdout);
        Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal(NormalizePath(Path.GetFullPath(missingDir)),
            doc.RootElement.GetProperty("projectRoot").GetString());
        Assert.Contains("Directory not found",
            doc.RootElement.GetProperty("error").GetProperty("message").GetString());
    }

    [Fact]
    public void FixCommand_DryRun_WithPendingFixes_UsesStructuredEnvelopeAndExitCodeOne()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-fix-{Guid.NewGuid():N}");
        var sourceDir = Path.Combine(tempDir, "src");
        Directory.CreateDirectory(sourceDir);

        try
        {
            File.WriteAllText(Path.Combine(sourceDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--file", Path.Combine("src", "Program.nl"), "--dry-run" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var doc = JsonDocument.Parse(stdout);
            Assert.Equal("fix", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(NormalizePath(Path.GetFullPath(tempDir)),
                doc.RootElement.GetProperty("projectRoot").GetString());
            Assert.Equal(1, doc.RootElement.GetProperty("filesModified").GetInt32());
            Assert.Equal(1, doc.RootElement.GetProperty("results").GetArrayLength());
            Assert.Equal(1, doc.RootElement.GetProperty("fixesApplied").GetArrayLength());
            Assert.Equal("src/Program.nl",
                doc.RootElement.GetProperty("fixesApplied")[0].GetProperty("file").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void HoverCommand_AtFunctionDefinition_ReturnsSignature()
    {
        var hiLine = File.ReadLines(Path.Combine(HelloWorldProject, "Program.nl"))
            .Select((text, index) => (Text: text, Line: index + 1))
            .First(line => line.Text.TrimStart().StartsWith("func Hi(", StringComparison.Ordinal))
            .Line;

        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "hover",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", $"{hiLine}:6"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("hover", doc.RootElement.GetProperty("command").GetString());

        var result = doc.RootElement.GetProperty("result");
        Assert.Equal("function", result.GetProperty("kind").GetString());
        Assert.Contains("Hi", result.GetProperty("signature").GetString() ?? "");
        AssertJsonContract("hover", stdout);
    }

    [Fact]
    public void HoverCommand_NoSymbol_ReturnsStructuredError()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "hover",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", "6:1"    // blank line
        }));

        Assert.Equal(1, exitCode);
        using var doc = JsonDocument.Parse(stdout);
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("hover", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("noSymbol", doc.RootElement.GetProperty("error").GetProperty("code").GetString());
    }

    [Fact]
    public void CallGraphCommand_FindsCalleesOfMain()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "call-graph",
            "--project", HelloWorldProject,
            "--function", "Main"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("callGraph", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("Main", doc.RootElement.GetProperty("function").GetString());

        var callees = doc.RootElement.GetProperty("callees").EnumerateArray().ToArray();
        Assert.Contains(callees, c => c.GetProperty("name").GetString() == "Hi");
        AssertJsonContract("callGraph", stdout);
    }

    [Fact]
    public void CallGraphCommand_NoFunction_ReturnsAllEdges()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "call-graph",
            "--project", HelloWorldProject
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("callGraph", doc.RootElement.GetProperty("command").GetString());
        // When no --function is specified, "function" key should be null/absent
        var hasFunction = doc.RootElement.TryGetProperty("function", out var funcProp);
        if (hasFunction)
            Assert.Equal(JsonValueKind.Null, funcProp.ValueKind);
    }

    [Fact]
    public void ImplementorsCommand_FindsCircleForIShape()
    {
        var classesAndRecordsProject = Path.Combine(FindExamplesDir(), "06-classes-and-records");

        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "implementors",
            "--project", classesAndRecordsProject,
            "--name", "IShape"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal("implementors", doc.RootElement.GetProperty("command").GetString());
        Assert.Equal("IShape", doc.RootElement.GetProperty("interface").GetString());

        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.Contains(results, r =>
            r.GetProperty("typeName").GetString() == "Circle" &&
            r.GetProperty("kind").GetString() == "class");
        AssertJsonContract("implementors", stdout);
    }

    [Fact]
    public void ImplementorsCommand_MissingName_ReturnsError()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "implementors",
            "--project", HelloWorldProject
        }));

        Assert.Equal(1, exitCode);
        Assert.Contains("Usage:", stderr);
    }

    [Fact]
    public void SymbolsCommand_WildcardFilter_MatchesGlob()
    {
        var classesAndRecordsProject = Path.Combine(FindExamplesDir(), "06-classes-and-records");

        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "symbols",
            "--project", classesAndRecordsProject,
            "--filter", "*ircle"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());

        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.Contains(results, r => r.GetProperty("name").GetString() == "Circle");
        Assert.DoesNotContain(results, r => r.GetProperty("name").GetString() == "Square");
    }

    [Fact]
    public void SymbolsCommand_SubstringFilter_MatchesSubstring()
    {
        var classesAndRecordsProject = Path.Combine(FindExamplesDir(), "06-classes-and-records");

        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "symbols",
            "--project", classesAndRecordsProject,
            "--filter", "quare"  // should match Square, not Circle
        }));

        Assert.Equal(0, exitCode);
        using var doc = JsonDocument.Parse(stdout);
        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.Contains(results, r => r.GetProperty("name").GetString() == "Square");
        Assert.DoesNotContain(results, r => r.GetProperty("name").GetString() == "Circle");
    }

    [Fact]
    public void CliCommandRegistry_StaysInSyncWithHelpCompletionsAndDocs()
    {
        var publicTopLevelCommands = CommandRegistry.TopLevelCommands.Select(command => command.Name).ToArray();
        var publicQueryCommands = CommandRegistry.QueryCommands.Select(command => command.Name).ToArray();

        var (_, help, _) = CaptureConsole(() => ExecuteProgram("help"));
        var (_, queryHelp, _) = CaptureConsole(() => QueryCommand.Execute(new[] { "help" }));
        var (_, zshCompletion, _) = CaptureConsole(() => CompletionCommand.Execute(new[] { "zsh" }));
        var docs = File.ReadAllText(Path.Combine(FindRepoRoot(), "website", "docs", "cli-reference.md"));

        foreach (var command in publicTopLevelCommands)
        {
            Assert.Contains(command, help);
            Assert.Contains(command, zshCompletion);
            Assert.Contains($"nlc {command}", docs);
        }

        foreach (var command in publicQueryCommands)
        {
            Assert.Contains(command, queryHelp);
            Assert.Contains(command, zshCompletion);
            Assert.Contains($"nlc query {command}", docs);
        }

        Assert.DoesNotContain("convert", publicTopLevelCommands);
        Assert.DoesNotContain("idiom", publicTopLevelCommands);
        Assert.DoesNotContain("nlc convert", help);
        Assert.DoesNotContain("nlc idiom", help);
        Assert.DoesNotContain("nlc convert", zshCompletion);
        Assert.DoesNotContain("nlc idiom", zshCompletion);
        Assert.DoesNotContain("nlc idiom", docs);
    }

    private static int ExecuteProgram(params string[] args)
    {
        var programType = typeof(CheckCommand).Assembly.GetType("NSharpLang.Cli.Program");
        Assert.NotNull(programType);

        var method = programType!.GetMethod("Execute", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic);
        Assert.NotNull(method);

        return (int)(method!.Invoke(null, new object[] { args }) ?? -1);
    }

    private static (int ExitCode, string Stdout, string Stderr) CaptureConsole(Func<int> action, string? stdin = null)
    {
        var originalOut = Console.Out;
        var originalError = Console.Error;
        var originalIn = Console.In;
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        using var input = new StringReader(stdin ?? string.Empty);

        Console.SetOut(stdout);
        Console.SetError(stderr);
        Console.SetIn(input);

        try
        {
            var exitCode = action();
            return (exitCode, stdout.ToString(), stderr.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetError(originalError);
            Console.SetIn(originalIn);
        }
    }

    public static IEnumerable<object[]> QueryJsonContractCases()
    {
        var examplesDir = FindExamplesDir();

        yield return new object[]
        {
            "symbols",
            new[] { "symbols", "--project", Path.Combine(examplesDir, "01-hello-world") }
        };

        yield return new object[]
        {
            "outline",
            new[] { "outline", "--project", Path.Combine(examplesDir, "01-hello-world"), "Program.nl" }
        };

        yield return new object[]
        {
            "diagnostics",
            new[] { "diagnostics", "--project", Path.Combine(examplesDir, "01-hello-world") }
        };

        yield return new object[]
        {
            "doc",
            new[] { "doc", "Console.WriteLine" }
        };

        yield return new object[]
        {
            "type",
            new[]
            {
                "type",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "11:5"
            }
        };

        yield return new object[]
        {
            "definitionSearch",
            new[]
            {
                "definition",
                "--project", Path.Combine(examplesDir, "06-classes-and-records"),
                "--name", "Point"
            }
        };

        yield return new object[]
        {
            "definition",
            new[]
            {
                "definition",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "22:10"
            }
        };

        yield return new object[]
        {
            "references",
            new[]
            {
                "references",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "10:7"
            }
        };

        yield return new object[]
        {
            "completions",
            new[]
            {
                "completions",
                "--project", Path.Combine(examplesDir, "12-multi-file-projects", "MultiFileProject"),
                "--file", "Services/PersonService.nl",
                "--pos", "14:15"
            }
        };

        yield return new object[]
        {
            "inspect",
            new[]
            {
                "inspect",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "11:5"
            }
        };

        yield return new object[]
        {
            "inspectSummary",
            new[]
            {
                "inspect",
                "--compact",
                "--project", IssueTrackerFixture,
                "--file", "Service.nl",
                "--pos", "11:5"
            }
        };

        yield return new object[]
        {
            "hover",
            new[]
            {
                "hover",
                "--project", Path.Combine(examplesDir, "01-hello-world"),
                "--file", "Program.nl",
                "--pos", "18:10"
            }
        };

        yield return new object[]
        {
            "callGraph",
            new[]
            {
                "call-graph",
                "--project", Path.Combine(examplesDir, "01-hello-world"),
                "--function", "Main"
            }
        };

        yield return new object[]
        {
            "implementors",
            new[]
            {
                "implementors",
                "--project", Path.Combine(examplesDir, "06-classes-and-records"),
                "--name", "IShape"
            }
        };
    }

    private static string FindExamplesDir()
    {
        var dir = Directory.GetCurrentDirectory();
        for (int i = 0; i < 10; i++)
        {
            var candidate = Path.Combine(dir, "examples");
            if (Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "01-hello-world")))
                return candidate;

            var parent = Directory.GetParent(dir);
            if (parent == null)
                break;
            dir = parent.FullName;
        }

        throw new DirectoryNotFoundException("Could not find examples directory.");
    }

    private static string FindFixturesDir()
    {
        var repoRoot = FindRepoRoot();
        var candidate = Path.Combine(repoRoot, "tests", "fixtures");
        if (Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "issue-tracker")))
            return candidate;

        throw new DirectoryNotFoundException("Could not find tests/fixtures directory.");
    }

    private static string FindRepoRoot()
    {
        var dir = Directory.GetCurrentDirectory();
        for (int i = 0; i < 10; i++)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")) && Directory.Exists(Path.Combine(dir, "docs")))
                return dir;

            var parent = Directory.GetParent(dir);
            if (parent == null)
                break;
            dir = parent.FullName;
        }

        throw new DirectoryNotFoundException("Could not find repository root.");
    }

    private static void AssertJsonContract(string contractName, string json)
    {
        var expected = LoadJsonContractRootKeys();
        var actual = GetRootPropertyNames(json);

        Assert.True(expected.TryGetValue(contractName, out var expectedKeys),
            $"Missing JSON contract snapshot: {contractName}");
        Assert.True(expectedKeys!.SequenceEqual(actual),
            $"{contractName} JSON envelope changed.\nExpected: [{string.Join(", ", expectedKeys)}]\nActual:   [{string.Join(", ", actual)}]");
    }

    private static IReadOnlyDictionary<string, string[]> LoadJsonContractRootKeys()
    {
        var path = FindJsonContractFixturePath();
        using var document = JsonDocument.Parse(File.ReadAllText(path));

        return document.RootElement.EnumerateObject()
            .ToDictionary(
                property => property.Name,
                property => property.Value.EnumerateArray().Select(value => value.GetString() ?? string.Empty).ToArray(),
                StringComparer.Ordinal);
    }

    private static string[] GetRootPropertyNames(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.EnumerateObject().Select(property => property.Name).ToArray();
    }

    private static string FindJsonContractFixturePath()
    {
        var examplesDir = FindExamplesDir();
        var repoRoot = Directory.GetParent(examplesDir)?.FullName;
        if (repoRoot != null)
        {
            var candidate = Path.Combine(repoRoot, "tests", "fixtures", "json-contract-root-keys.golden.json");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new DirectoryNotFoundException("Could not find json-contract-root-keys.golden.json.");
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private sealed record ExportReferenceValue(string Name, string Version);

    private sealed record TidyDependency(string Name, string Status);
}

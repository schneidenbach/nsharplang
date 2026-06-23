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
    public void ProgramCommandKernels_SummarizesTopLevelCommands()
    {
        var empty = ProgramCommandKernels.GetCommandKind(Array.Empty<string>());
        Assert.Equal(ProgramCommandKind.Help, empty);

        var build = ProgramCommandKernels.GetCommandKind(new[] { "BUILD", "--help" });
        Assert.Equal(ProgramCommandKind.Build, build);

        var longVersion = ProgramCommandKernels.GetCommandKind(new[] { "--VERSION" });
        Assert.Equal(ProgramCommandKind.Version, longVersion);

        var shortVersion = ProgramCommandKernels.GetCommandKind(new[] { "-V" });
        Assert.Equal(ProgramCommandKind.Version, shortVersion);

        var lowerShortVersion = ProgramCommandKernels.GetCommandKind(new[] { "-v" });
        Assert.Equal(ProgramCommandKind.Unknown, lowerShortVersion);

        Assert.Equal("nlc 1.2.3", ProgramCommandKernels.GetVersionText("1.2.3"));
        var helpText = ProgramCommandKernels.GetHelpText("1.2.3");
        Assert.StartsWith("N# Compiler (nlc) 1.2.3\n\nUsage: nlc <command> [options]", helpText, StringComparison.Ordinal);
        Assert.Contains("Build & Run:", helpText);
        Assert.Contains("Common Workflows:", helpText);
        Assert.DoesNotContain("convert", helpText);
        Assert.DoesNotContain("transpile", helpText);
        Assert.Equal(
            "The 'transpile' command has been removed. Use 'nlc export csharp' instead.",
            ProgramCommandKernels.GetTranspileRemovedMessage());
        Assert.Equal(
            "Unknown command: frobnicate. Run 'nlc help' to see available commands.",
            ProgramCommandKernels.GetUnknownCommandMessage("frobnicate"));
        Assert.Equal("Error: boom", ProgramCommandKernels.GetErrorLine("boom"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() =>
            Program.Execute(new[] { "help" }));
        Assert.Equal(0, helpExitCode);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
        var header = helpStdout.Split(Environment.NewLine)[0];
        const string headerPrefix = "N# Compiler (nlc) ";
        Assert.StartsWith(headerPrefix, header, StringComparison.Ordinal);
        var version = header[headerPrefix.Length..];
        Assert.Equal(ProgramCommandKernels.GetHelpText(version) + Environment.NewLine, helpStdout);

        var (versionExitCode, versionStdout, versionStderr) = CaptureConsole(() =>
            Program.Execute(new[] { "--version" }));
        Assert.Equal(0, versionExitCode);
        Assert.Equal(ProgramCommandKernels.GetVersionText(version) + Environment.NewLine, versionStdout);
        Assert.True(string.IsNullOrWhiteSpace(versionStderr));

        var (buildExitCode, buildStdout, buildStderr) = CaptureConsole(() =>
            Program.Execute(new[] { "BUILD", "--help" }));
        Assert.Equal(0, buildExitCode);
        Assert.Contains("Usage: nlc build", buildStdout);
        Assert.True(string.IsNullOrWhiteSpace(buildStderr));

        var (transpileExitCode, _, transpileStderr) = CaptureConsole(() =>
            Program.Execute(new[] { "TRANSPILE", "Program.nl" }));
        Assert.Equal(1, transpileExitCode);
        Assert.Equal(
            ProgramCommandKernels.GetErrorLine(ProgramCommandKernels.GetTranspileRemovedMessage()) + Environment.NewLine,
            transpileStderr);

        var (unknownExitCode, _, unknownStderr) = CaptureConsole(() =>
            Program.Execute(new[] { "FROBNICATE" }));
        Assert.Equal(1, unknownExitCode);
        Assert.Equal(
            ProgramCommandKernels.GetErrorLine(ProgramCommandKernels.GetUnknownCommandMessage("frobnicate")) + Environment.NewLine,
            unknownStderr);
    }

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

            var (depthExitCode, depthStdout, depthStderr) = CaptureConsole(() =>
                TreeCommand.Execute(new[] { "--project", tempDir, "--depth", "bad", "--depth", "0", "--json" }));

            Assert.Equal(0, depthExitCode);
            Assert.True(string.IsNullOrWhiteSpace(depthStderr));

            using var depthDoc = JsonDocument.Parse(depthStdout);
            var depthRoot = depthDoc.RootElement;
            Assert.Equal(0, depthRoot.GetProperty("maxDepth").GetInt32());
            Assert.Equal(0, depthRoot.GetProperty("dependencies").GetArrayLength());
            Assert.Equal(0, depthRoot.GetProperty("summary").GetProperty("direct").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TreeCommand_ProjectYmlOnly_TextUsesOutputMode()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-tree-text-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TreeText
entry: Program.nl
outputType: exe
targetFramework: net10.0

dependencies:
  - nuget: Serilog
    version: 3.1.1
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    print "ok"
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                TreeCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("TreeText (net10.0)", stdout);
            Assert.Contains("Serilog@3.1.1 [nuget]", stdout);
            Assert.DoesNotContain("\"command\"", stdout);
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
    public void TreeCommandKernels_SummarizesOptions()
    {
        var args = new[] { "--project", "samples/demo", "--depth", "2", "--json", "-h" };

        var dogfoodSummary = TreeCommandKernels.GetOptionSummary(args);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.Equal("2", dogfoodSummary.DepthOption);
        Assert.True(dogfoodSummary.Json);
        Assert.True(dogfoodSummary.ShowHelp);

        var permissiveValue = TreeCommandKernels.GetOptionSummary(new[] { "--project", "--json", "--depth", "--help" });
        Assert.Equal("--json", permissiveValue.ProjectOption);
        Assert.Equal("--help", permissiveValue.DepthOption);
        Assert.True(permissiveValue.Json);
        Assert.True(permissiveValue.ShowHelp);

        Assert.True(TreeCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);

        var textMode = TreeCommandKernels.GetOutputMode(json: false);
        Assert.Equal(TreeOutputModeKind.Text, textMode);

        var jsonMode = TreeCommandKernels.GetOutputMode(json: true);
        Assert.Equal(TreeOutputModeKind.Json, jsonMode);

        var helpText = TreeCommandKernels.GetHelpText();
        Assert.Contains("N# Dependency Tree", helpText);
        Assert.Contains("Usage: nlc tree [options]", helpText);
        Assert.Contains("Failed to display tree", helpText);
        Assert.Equal(
            "Project directory not found: /tmp/nsharp-missing",
            TreeCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/nsharp-missing"));
        Assert.Equal("Tree failed: bad graph", TreeCommandKernels.GetTreeFailedMessage("bad graph"));
        Assert.Contains("No project.yml or .csproj found", TreeCommandKernels.GetNoProjectFileMessage());
        Assert.Contains("direct runtime dependencies", TreeCommandKernels.GetProjectYmlLimitationMessage());
        Assert.Equal(
            "Transitive NuGet dependency resolution through MSBuild failed: restore failed",
            TreeCommandKernels.GetTransitiveResolutionFailedLimitation("restore failed"));
        Assert.Equal(
            "restore failed Run 'dotnet restore' and retry.",
            TreeCommandKernels.GetDotnetRestoreRetryMessage("restore failed"));
        Assert.Equal("dotnet list package failed.", TreeCommandKernels.GetDotnetListFailedMessage());
        Assert.Equal("Demo (net10.0)", TreeCommandKernels.GetProjectHeader("Demo", "net10.0"));
        Assert.Equal("  (no dependencies)", TreeCommandKernels.GetNoDependenciesLine());
        Assert.Equal("Serilog@3.1.0 [nuget]", TreeCommandKernels.GetDependencyText("Serilog", "3.1.0", "nuget"));
        Assert.Equal("System.Console [framework]", TreeCommandKernels.GetDependencyText("System.Console", null, "framework"));
        Assert.Equal("└── Serilog@3.1.0 [nuget]", TreeCommandKernels.GetDependencyLine(isLast: true, "Serilog@3.1.0 [nuget]"));
        Assert.Equal("├── Serilog@3.1.0 [nuget]", TreeCommandKernels.GetDependencyLine(isLast: false, "Serilog@3.1.0 [nuget]"));
        Assert.Equal("  transitive (2 packages):", TreeCommandKernels.GetTransitiveHeader(2));
        Assert.Equal("    Serilog@3.1.0 [nuget]", TreeCommandKernels.GetTransitiveDependencyLine("Serilog@3.1.0 [nuget]"));
        Assert.Equal("Limitations:", TreeCommandKernels.GetLimitationsHeader());
        Assert.Equal("  - direct only", TreeCommandKernels.GetLimitationLine("direct only"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => TreeCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
        Assert.Contains("Usage: nlc tree [options]", helpStdout);
    }

    [Fact]
    public void TreeCommandKernels_ParseMaxDepthWithNSharpKernel()
    {
        var cases = new[]
        {
            (Array.Empty<string>(), 99),
            (new[] { "--depth", "2" }, 2),
            (new[] { "--depth", "bad", "--depth", "2" }, 2),
            (new[] { "--depth", "--json", "--depth", "+3" }, 3),
            (new[] { "--depth", " -1 " }, -1),
            (new[] { "--depth", "2147483648", "--depth", "-2147483648" }, -2147483648),
            (new[] { "--depth", "1_000" }, 99),
            (new[] { "--depth", "2147483647" }, 2147483647),
            (new[] { "--depth", "+" }, 99),
            (new[] { "--depth", " 7 " }, 7)
        };

        foreach (var (args, expected) in cases)
        {
            var actual = TreeCommandKernels.GetMaxDepth(args, 99);
            Assert.Equal(expected, actual);
        }
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

        var helperActual = TreeDependencyDeduplicator.Deduplicate(dependencies);
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

        var dogfoodFrameworks = TreeDependencyDeduplicator.DeduplicateTargetFrameworks(frameworks);
        Assert.Equal(new[] { "net10.0", "net9.0", "net8.0" }, dogfoodFrameworks);
        Assert.Equal("unknown", TreeCommand.FormatTargetFrameworks(Array.Empty<string>()));
        Assert.Equal("net10.0,net9.0,net8.0", TreeCommand.FormatTargetFrameworks(frameworks));
    }

    [Fact]
    public void GeneratedOutputDirectoryDeduplicator_DeduplicatesStaleGeneratedDirectories()
    {
        var duplicateDirs = new[] { "obj/Debug/net10.0/nsharp", "obj/Debug/net10.0/nsharp" };
        var distinctDirs = GeneratedOutputDirectoryDeduplicator.Deduplicate(duplicateDirs);
        Assert.Equal(new[] { "obj/Debug/net10.0/nsharp" }, distinctDirs);

        var sourceBaseLength = GeneratedOutputDirectoryDeduplicator.GetSourceBasePathLength("src/Program.nl");
        Assert.Equal("src/Program".Length, sourceBaseLength);
        var testSourceBaseLength = GeneratedOutputDirectoryDeduplicator.GetSourceBasePathLength("src/Calculator.tests.nl");
        Assert.Equal("src/Calculator".Length, testSourceBaseLength);
        var uppercaseTestSourceBaseLength = GeneratedOutputDirectoryDeduplicator.GetSourceBasePathLength("src/Calculator.TESTS.NL");
        Assert.Equal("src/Calculator".Length, uppercaseTestSourceBaseLength);
        var nonSourceBaseLength = GeneratedOutputDirectoryDeduplicator.GetSourceBasePathLength("src/README.md");
        Assert.Equal(-1, nonSourceBaseLength);

        var skipObjSource = GeneratedOutputDirectoryDeduplicator.ShouldSkipSourcePath("obj/Debug/Generated.nl");
        Assert.True(skipObjSource);
        var skipBinSource = GeneratedOutputDirectoryDeduplicator.ShouldSkipSourcePath("BIN\\Debug\\Generated.nl");
        Assert.True(skipBinSource);
        var keepNestedObjSource = GeneratedOutputDirectoryDeduplicator.ShouldSkipSourcePath("src/obj/Generated.nl");
        Assert.False(keepNestedObjSource);
        var keepObjectSource = GeneratedOutputDirectoryDeduplicator.ShouldSkipSourcePath("object/Generated.nl");
        Assert.False(keepObjectSource);

        var generatedBaseLength = GeneratedOutputDirectoryDeduplicator.GetGeneratedOutputBasePathLength("Program.g.cs");
        Assert.Equal("Program".Length, generatedBaseLength);
        var uppercaseGeneratedBaseLength = GeneratedOutputDirectoryDeduplicator.GetGeneratedOutputBasePathLength("nested/Calculator.G.CS");
        Assert.Equal("nested/Calculator".Length, uppercaseGeneratedBaseLength);
        var nonGeneratedBaseLength = GeneratedOutputDirectoryDeduplicator.GetGeneratedOutputBasePathLength("Program.cs");
        Assert.Equal(-1, nonGeneratedBaseLength);

        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-stale-generated-{Guid.NewGuid():N}");
        var generatedDir = Path.Combine(tempDir, "obj", "Debug", "net10.0", "nsharp");
        Directory.CreateDirectory(generatedDir);

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), "func main(): int { return 0 }");
            File.WriteAllText(Path.Combine(tempDir, "Calculator.tests.nl"), "test \"keeps generated test output\" {}");

            var liveGeneratedFile = Path.Combine(generatedDir, "Program.g.cs");
            var liveTestGeneratedFile = Path.Combine(generatedDir, "Calculator.g.cs");
            var staleGeneratedFile = Path.Combine(generatedDir, "Deleted.g.cs");
            File.WriteAllText(liveGeneratedFile, "// live");
            File.WriteAllText(liveTestGeneratedFile, "// live test");
            File.WriteAllText(staleGeneratedFile, "// stale");

            Program.CleanStaleGeneratedFiles(tempDir);

            Assert.True(File.Exists(liveGeneratedFile));
            Assert.True(File.Exists(liveTestGeneratedFile));
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

        var expected = new[]
        {
            "/repo/deep/nested/.nlc",
            "/repo/deep/nested/bin",
            "/repo/src/.nlc",
            "/repo/src/obj",
            "/repo/bin",
            "/repo/obj"
        };

        var actual = CleanArtifactDirectoryOrderer.Order(directories);
        Assert.Equal(expected, actual);
    }

    [Fact]
    public void CleanCommandKernels_SummarizesOptions()
    {
        var args = new[] { "--project", "samples/demo", "--all", "-h" };

        var dogfoodSummary = CleanCommandKernels.GetOptionSummary(args);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.True(dogfoodSummary.CleanAll);
        Assert.True(dogfoodSummary.ShowHelp);

        var permissiveValue = CleanCommandKernels.GetOptionSummary(new[] { "--project", "--all" });
        Assert.Equal("--all", permissiveValue.ProjectOption);
        Assert.True(permissiveValue.CleanAll);
        Assert.False(permissiveValue.ShowHelp);

        Assert.True(CleanCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);

        var helpText = CleanCommandKernels.GetHelpText();
        Assert.Contains("N# Clean", helpText);
        Assert.Contains("Usage: nlc clean [options]", helpText);
        Assert.Contains("Clean failed", helpText);
        Assert.Equal(
            "Project directory not found: /tmp/nsharp-missing",
            CleanCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/nsharp-missing"));
        Assert.Equal(
            "No build artifacts found under /tmp/nsharp.",
            CleanCommandKernels.GetNoArtifactsFoundMessage("/tmp/nsharp"));
        Assert.Equal("Removed 1 build artifact directory:", CleanCommandKernels.GetRemovedArtifactsHeader(1));
        Assert.Equal("Removed 2 build artifact directories:", CleanCommandKernels.GetRemovedArtifactsHeader(2));
        Assert.Equal("  bin/Debug", CleanCommandKernels.GetRemovedArtifactLine("bin/Debug"));
        Assert.Equal("Cleared NuGet caches.", CleanCommandKernels.GetClearedNuGetCachesMessage());
        Assert.Equal(
            "Failed to clear NuGet caches.",
            CleanCommandKernels.GetClearNuGetCachesFailedMessage(string.Empty));
        Assert.Equal(
            "Failed to clear NuGet caches.\nnuget failed",
            CleanCommandKernels.GetClearNuGetCachesFailedMessage("nuget failed"));
        Assert.Equal("Clean failed: access denied", CleanCommandKernels.GetCleanFailedMessage("access denied"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => CleanCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
        Assert.Contains("Usage: nlc clean [options]", helpStdout);

        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-clean-missing-{Guid.NewGuid():N}");
        var (missingExitCode, missingStdout, missingStderr) = CaptureConsole(() =>
            CleanCommand.Execute(new[] { "--project", missingDir }));
        Assert.Equal(1, missingExitCode);
        Assert.True(string.IsNullOrWhiteSpace(missingStdout));
        Assert.Contains($"Project directory not found: {Path.GetFullPath(missingDir)}", missingStderr);

        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-clean-empty-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var (emptyExitCode, emptyStdout, emptyStderr) = CaptureConsole(() =>
                CleanCommand.Execute(new[] { "--project", tempDir }));
            Assert.Equal(0, emptyExitCode);
            Assert.True(string.IsNullOrWhiteSpace(emptyStderr));
            Assert.Contains($"No build artifacts found under {Path.GetFullPath(tempDir)}.", emptyStdout);
        }
        finally
        {
            if (Directory.Exists(tempDir))
                Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void DaemonCommandKernels_SummarizesOptions()
    {
        var args = new[] { "status", "--project", "samples/demo" };

        var dogfoodSummary = DaemonCommandKernels.GetOptionSummary(args);
        Assert.Equal(DaemonSubcommandKind.Status, dogfoodSummary.SubcommandKind);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.False(dogfoodSummary.ShowHelp);

        var help = DaemonCommandKernels.GetOptionSummary(new[] { "start", "--project", "samples/demo", "--help" });
        Assert.Equal(DaemonSubcommandKind.Start, help.SubcommandKind);
        Assert.Equal("samples/demo", help.ProjectOption);
        Assert.True(help.ShowHelp);

        var permissiveValue = DaemonCommandKernels.GetOptionSummary(new[] { "run", "--project", "--help" });
        Assert.Equal(DaemonSubcommandKind.Run, permissiveValue.SubcommandKind);
        Assert.Equal("--help", permissiveValue.ProjectOption);
        Assert.True(permissiveValue.ShowHelp);

        var unknown = DaemonCommandKernels.GetOptionSummary(new[] { "bogus" });
        Assert.Equal(DaemonSubcommandKind.Unknown, unknown.SubcommandKind);
        Assert.False(unknown.ShowHelp);

        Assert.True(DaemonCommandKernels.GetOptionSummary(Array.Empty<string>()).ShowHelp);

        var helpText = DaemonCommandKernels.GetHelpText();
        Assert.Contains("N# Analysis Daemon", helpText);
        Assert.Contains("Usage: nlc daemon <command> [options]", helpText);
        Assert.Contains("Command failed", helpText);
        Assert.Equal("Daemon is already running.", DaemonCommandKernels.GetAlreadyRunningMessage());
        Assert.Equal("Starting daemon for samples/demo...", DaemonCommandKernels.GetStartingMessage("samples/demo"));
        Assert.Equal("Daemon started.", DaemonCommandKernels.GetStartedMessage());
        Assert.Equal("Failed to start daemon.", DaemonCommandKernels.GetStartFailedMessage());
        Assert.Equal("No daemon running.", DaemonCommandKernels.GetNoDaemonRunningMessage());
        Assert.Equal("Daemon stopped.", DaemonCommandKernels.GetStoppedMessage());
        Assert.Equal("Failed to stop daemon.", DaemonCommandKernels.GetStopFailedMessage());
        Assert.Equal(
            "Daemon is running but not responding to status queries.",
            DaemonCommandKernels.GetStatusNotRespondingMessage());

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => DaemonCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
        Assert.Contains("Usage: nlc daemon <command> [options]", helpStdout);
    }

    [Fact]
    public void EnvCommandKernels_SummarizesOptions()
    {
        var args = new[] { "--json", "-h" };

        var dogfoodSummary = EnvCommandKernels.GetOptionSummary(args);
        Assert.True(dogfoodSummary.Json);
        Assert.True(dogfoodSummary.ShowHelp);

        Assert.True(EnvCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(EnvCommandKernels.GetOptionSummary(new[] { "ignored", "-h" }).ShowHelp);
        Assert.True(EnvCommandKernels.GetOptionSummary(new[] { "--json" }).Json);

        var textMode = EnvCommandKernels.GetOutputMode(json: false);
        Assert.Equal(EnvOutputModeKind.Text, textMode);

        var jsonMode = EnvCommandKernels.GetOutputMode(json: true);
        Assert.Equal(EnvOutputModeKind.Json, jsonMode);

        var helpText = EnvCommandKernels.GetHelpText();
        Assert.Contains("N# Environment Info", helpText);
        Assert.Contains("Usage: nlc env [options]", helpText);
        Assert.Contains("Always succeeds", helpText);
        Assert.Equal(
            "nlc version:    1.2.3",
            EnvCommandKernels.GetTextLine(EnvTextLineKind.NlcVersion, "1.2.3"));
        Assert.Equal(
            "nsharp packages: /tmp/packages",
            EnvCommandKernels.GetTextLine(EnvTextLineKind.NsharpPackages, "/tmp/packages"));
        Assert.Equal(
            "project:        Demo",
            EnvCommandKernels.GetTextLine(EnvTextLineKind.Project, "Demo"));

        var (exitCode, stdout, stderr) = CaptureConsole(() => EnvCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("Usage: nlc env [options]", stdout);
    }

    [Fact]
    public void EnvCommand_Text_UsesOutputMode()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => EnvCommand.Execute(Array.Empty<string>()));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("nlc version:", stdout);
        Assert.Contains("dotnet version:", stdout);
        Assert.DoesNotContain("\"command\"", stdout);
    }

    [Fact]
    public void EnvCommand_Json_EmitsStableEnvelope()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => EnvCommand.Execute(new[] { "--json" }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        var root = doc.RootElement;
        Assert.Equal(2, root.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("env", root.GetProperty("command").GetString());
        Assert.True(root.GetProperty("ok").GetBoolean());
        Assert.True(root.TryGetProperty("nlcVersion", out _));
        Assert.True(root.TryGetProperty("dotnetVersion", out _));
        Assert.True(root.TryGetProperty("runtime", out _));
        Assert.True(root.TryGetProperty("os", out _));
        Assert.True(root.TryGetProperty("arch", out _));
        Assert.True(root.TryGetProperty("nugetCachePath", out _));
        Assert.True(root.TryGetProperty("nsharpBinPath", out _));
        Assert.True(root.TryGetProperty("nsharpPackageCachePath", out _));
    }

    [Fact]
    public void DoctorCommandKernels_SummarizesOptions()
    {
        var args = new[] { "--json", "--require-vscode", "--skip-vscode", "-h" };

        var dogfoodSummary = DoctorCommandKernels.GetOptionSummary(args);
        Assert.True(dogfoodSummary.Json);
        Assert.True(dogfoodSummary.RequireVscode);
        Assert.True(dogfoodSummary.SkipVscode);
        Assert.True(dogfoodSummary.ShowHelp);

        Assert.True(DoctorCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(DoctorCommandKernels.GetOptionSummary(new[] { "ignored", "-h" }).ShowHelp);
        Assert.True(DoctorCommandKernels.GetOptionSummary(new[] { "--json" }).Json);

        var textMode = DoctorCommandKernels.GetOutputMode(json: false);
        Assert.Equal(DoctorOutputModeKind.Text, textMode);

        var jsonMode = DoctorCommandKernels.GetOutputMode(json: true);
        Assert.Equal(DoctorOutputModeKind.Json, jsonMode);

        var helpText = DoctorCommandKernels.GetHelpText();
        Assert.Contains("N# Doctor", helpText);
        Assert.Contains("Usage: nlc doctor [options]", helpText);
        Assert.Contains("One or more required checks failed", helpText);
        Assert.Equal("dotnet CLI was not found on PATH", DoctorCommandKernels.GetDotnetNotFoundMessage());
        Assert.Equal("dotnet --version failed", DoctorCommandKernels.GetDotnetVersionFailedMessage());
        Assert.Equal(
            "nlc is running, but no nlc command was found on PATH; source ~/.nsharp/env or use your package manager shell integration",
            DoctorCommandKernels.GetNlcCommandMissingMessage());
        Assert.Equal(
            "N# package cache was not found at /tmp/nsharp; rerun the N# installer",
            DoctorCommandKernels.GetPackageCacheMissingMessage("/tmp/nsharp"));
        Assert.Equal("nsharp-console template is installed", DoctorCommandKernels.GetTemplateInstalledMessage());
        Assert.Equal(
            "nsharp-console template was not found; run the N# installer or dotnet new install NSharpLang.Templates",
            DoctorCommandKernels.GetTemplatesMissingMessage());
        Assert.Equal(
            "nsharp-lsp was not found on PATH; source ~/.nsharp/env or reinstall N#",
            DoctorCommandKernels.GetLanguageServerMissingMessage());
        Assert.Equal("skipped by --skip-vscode", DoctorCommandKernels.GetVscodeSkippedMessage());
        Assert.Equal("VS Code 'code' CLI was not found on PATH", DoctorCommandKernels.GetVscodeRequiredMissingMessage());
        Assert.Equal(
            "VS Code 'code' CLI was not found; install VS Code or rerun with --require-vscode on developer machines",
            DoctorCommandKernels.GetVscodeOptionalMissingMessage());
        Assert.Equal(
            "nsharp.nsharp is not installed; run code --install-extension nsharp.nsharp",
            DoctorCommandKernels.GetVscodeExtensionMissingMessage("nsharp.nsharp"));
        Assert.Equal("N# doctor", DoctorCommandKernels.GetTextHeader());
        Assert.Equal("status: ok", DoctorCommandKernels.GetStatusLine(ok: true));
        Assert.Equal("status: problems found", DoctorCommandKernels.GetStatusLine(ok: false));
        Assert.Equal("✓", DoctorCommandKernels.GetCheckMarker("pass"));
        Assert.Equal("!", DoctorCommandKernels.GetCheckMarker("warn"));
        Assert.Equal("x", DoctorCommandKernels.GetCheckMarker("fail"));
        Assert.Equal(
            "✓ dotnet: 10.0.105",
            DoctorCommandKernels.GetCheckLine("✓", "dotnet", "10.0.105"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => DoctorCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
        Assert.Contains("Usage: nlc doctor [options]", helpStdout);
    }

    [Fact]
    public void AuditCommandKernels_SummarizesOptions()
    {
        var args = new[] { "--project", "samples/demo", "--json", "-h" };

        var dogfoodSummary = AuditCommandKernels.GetOptionSummary(args);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.True(dogfoodSummary.Json);
        Assert.True(dogfoodSummary.ShowHelp);

        var permissiveValue = AuditCommandKernels.GetOptionSummary(new[] { "--project", "--json" });
        Assert.Equal("--json", permissiveValue.ProjectOption);
        Assert.True(permissiveValue.Json);
        Assert.False(permissiveValue.ShowHelp);

        Assert.True(AuditCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(AuditCommandKernels.GetOptionSummary(new[] { "ignored", "-h" }).ShowHelp);

        var textMode = AuditCommandKernels.GetOutputMode(json: false);
        Assert.Equal(AuditOutputModeKind.Text, textMode);

        var jsonMode = AuditCommandKernels.GetOutputMode(json: true);
        Assert.Equal(AuditOutputModeKind.Json, jsonMode);

        var helpText = AuditCommandKernels.GetHelpText();
        Assert.Contains("N# Security Audit", helpText);
        Assert.Contains("Usage: nlc audit [options]", helpText);
        Assert.Contains("Vulnerabilities found or audit failed", helpText);
        Assert.Equal(
            "Project directory not found: /missing/project",
            AuditCommandKernels.GetProjectDirectoryNotFoundMessage("/missing/project"));
        Assert.Equal(
            "No .csproj file found. Run 'nlc init' to create one.",
            AuditCommandKernels.GetNoCsprojFileMessage());
        Assert.Equal(
            "The --vulnerable flag requires .NET SDK 8.0 or later.",
            AuditCommandKernels.GetVulnerableFlagUnsupportedMessage());
        Assert.Equal("Audit failed: denied", AuditCommandKernels.GetFailedMessage("denied"));
        Assert.Equal("No known vulnerabilities found.", AuditCommandKernels.GetNoKnownVulnerabilitiesMessage());
        Assert.Equal("1 vulnerability found:", AuditCommandKernels.GetVulnerabilitySummaryMessage(1));
        Assert.Equal("2 vulnerabilities found:", AuditCommandKernels.GetVulnerabilitySummaryMessage(2));
        Assert.Equal(
            "  High: Serilog@3.1.0",
            AuditCommandKernels.GetVulnerabilityLine("High", "Serilog", "3.1.0"));
        Assert.Equal(
            "    https://example.test/advisory",
            AuditCommandKernels.GetVulnerabilityUrlLine("https://example.test/advisory"));
        Assert.Equal("  (could not parse vulnerability details)", AuditCommandKernels.GetParseFailureMessage());

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => AuditCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
        Assert.Contains("Usage: nlc audit [options]", helpStdout);
    }

    [Fact]
    public void AuditCommand_MissingProjectDirectory_ReturnsHelpfulMessage()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-audit-missing-{Guid.NewGuid():N}");

        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            AuditCommand.Execute(new[] { "--project", missingDir }));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdout));
        Assert.Contains($"Project directory not found: {missingDir}", stderr);
    }

    [Fact]
    public void AuditCommand_NoCsproj_ReturnsHelpfulMessage()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-audit-no-csproj-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                AuditCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("No .csproj file found. Run 'nlc init' to create one.", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void InitCommandKernels_SummarizesOptions()
    {
        var args = new[] { "--name", "MyLib", "--type", "library", "--force", "-h" };

        var dogfoodSummary = InitCommandKernels.GetOptionSummary(args);
        Assert.Equal("MyLib", dogfoodSummary.NameOption);
        Assert.Equal("library", dogfoodSummary.TypeOption);
        Assert.True(dogfoodSummary.Force);
        Assert.True(dogfoodSummary.ShowHelp);

        var permissiveValue = InitCommandKernels.GetOptionSummary(new[] { "--name", "--force", "--type", "--help" });
        Assert.Equal("--force", permissiveValue.NameOption);
        Assert.Equal("--help", permissiveValue.TypeOption);
        Assert.True(permissiveValue.Force);
        Assert.True(permissiveValue.ShowHelp);

        Assert.True(InitCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(InitCommandKernels.GetOptionSummary(new[] { "ignored", "-h" }).ShowHelp);

        var helpText = InitCommandKernels.GetHelpText();
        Assert.Contains("N# Init", helpText);
        Assert.Contains("Usage: nlc init [options]", helpText);
        Assert.Contains("Initialization failed", helpText);
        Assert.Equal(
            "Invalid type 'service'. Expected 'exe' or 'library'.",
            InitCommandKernels.GetInvalidTypeMessage("service"));
        Assert.Equal(
            "project.yml already exists. Use --force to overwrite.",
            InitCommandKernels.GetProjectFileExistsMessage());
        Assert.Equal("Created: Program.nl", InitCommandKernels.GetCreatedFileMessage("Program.nl"));
        Assert.Equal(
            "N# project initialized. Run 'nlc build' to compile.",
            InitCommandKernels.GetSuccessMessage());
        Assert.Equal("Init failed: denied", InitCommandKernels.GetFailedMessage("denied"));

        var exeYaml = InitCommandKernels.GetProjectYamlText("DemoApp", "exe");
        Assert.Equal(ProjectFileParser.GenerateTemplate("DemoApp"), exeYaml);
        Assert.Contains("entry: Program.nl\n", exeYaml);
        Assert.Contains("outputType: exe\n", exeYaml);

        var libraryYaml = InitCommandKernels.GetProjectYamlText("DemoLib", "library");
        Assert.Contains("name: DemoLib\n", libraryYaml);
        Assert.Contains("outputType: library\n", libraryYaml);
        Assert.DoesNotContain("entry: Program.nl", libraryYaml, StringComparison.Ordinal);
        Assert.Contains("# Add your dependencies here\n", libraryYaml);
        Assert.Contains("  profile: default\n", libraryYaml);

        Assert.Equal("<Project Sdk=\"NSharpLang.Sdk\" />\n", InitCommandKernels.GetCsprojText());
        Assert.Equal("func main() {\n    print \"Hello, N#!\"\n}", InitCommandKernels.GetProgramSourceText());
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

        var adapterAllNuGet = UpdateDependencyFilter.FilterAllNuGetDependencies(dependencies);
        Assert.Equal(new[] { "Serilog", "Newtonsoft.Json", "serilog", "System.Text.Json" },
            adapterAllNuGet.Select(reference => reference.Nuget));

        var serilog = UpdateDependencyFilter.FilterTargetNuGetDependencies(dependencies, "SERILOG");
        Assert.Equal(new[] { "Serilog", "serilog" },
            serilog.Select(reference => reference.Nuget));

        var missing = UpdateDependencyFilter.FilterTargetNuGetDependencies(dependencies, "Missing.Package");
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

        var actual = DocCommandKernels.OrderSymbolsForGeneration(symbols);

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
            Assert.Equal(
                QueryCommandKernels.GetNoSymbolAtPositionMessage("Program.nl", 1, 1),
                results[3].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_DocMissUsesQueryMessageKernel()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-doc-miss-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "doc",
    "query": "__DefinitelyMissingBatchDocType__"
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

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("batch", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(1, doc.RootElement.GetProperty("failureCount").GetInt32());

            var result = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray());
            Assert.Equal("doc", result.GetProperty("request").GetProperty("command").GetString());
            Assert.False(result.GetProperty("ok").GetBoolean());
            Assert.Equal(
                QueryCommandKernels.GetNoDocumentationMessage("__DefinitelyMissingBatchDocType__"),
                result.GetProperty("response").GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchQueryKernels_ShapesMessages()
    {
        Assert.Equal("Requests file not found: /tmp/requests.json", BatchQueryKernels.GetRequestsFileNotFoundMessage("/tmp/requests.json"));
        Assert.Equal("Batch requests must be a JSON array or an object with a 'requests' array.", BatchQueryKernels.GetPayloadShapeMessage());
        Assert.Equal("Each batch request must be a JSON object.", BatchQueryKernels.GetRequestObjectRequiredMessage());
        Assert.Equal("Failed to deserialize a batch request.", BatchQueryKernels.GetRequestDeserializeFailedMessage());
        Assert.Equal("Duplicate batch request ids are not allowed: alpha, zeta", BatchQueryKernels.GetDuplicateRequestIdsMessage("alpha, zeta"));
        Assert.Equal("Unsupported batch query command 'unknown'.", BatchQueryKernels.GetUnsupportedCommandMessage("unknown"));
        Assert.Equal("file is required for outline requests.", BatchQueryKernels.GetOutlineFileRequiredMessage());
        Assert.Equal("query is required for doc requests.", BatchQueryKernels.GetDocQueryRequiredMessage());
        Assert.Equal("file and pos are required.", BatchQueryKernels.GetFileAndPosRequiredMessage());
        Assert.Equal("Invalid position format 'bad'. Expected <line>:<col>.", BatchQueryKernels.GetInvalidPositionMessage("bad"));
    }

    [Fact]
    public void BatchQueryRunner_LoadRequestsErrorsUseMessageKernels()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-load-errors-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var missingPath = Path.Combine(tempDir, "missing.json");
            var missing = Assert.Throws<FileNotFoundException>(() => BatchQueryRunner.LoadRequests(missingPath));
            Assert.Contains(BatchQueryKernels.GetRequestsFileNotFoundMessage(missingPath), missing.Message);

            var payloadPath = Path.Combine(tempDir, "payload.json");
            File.WriteAllText(payloadPath, "{}");
            var malformedPayload = Assert.Throws<InvalidDataException>(() => BatchQueryRunner.LoadRequests(payloadPath));
            Assert.Equal(BatchQueryKernels.GetPayloadShapeMessage(), malformedPayload.Message);

            var itemPath = Path.Combine(tempDir, "item.json");
            File.WriteAllText(itemPath, "[1]");
            var nonObjectItem = Assert.Throws<InvalidDataException>(() => BatchQueryRunner.LoadRequests(itemPath));
            Assert.Equal(BatchQueryKernels.GetRequestObjectRequiredMessage(), nonObjectItem.Message);
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
            Assert.Equal(BatchQueryKernels.GetDuplicateRequestIdsMessage("alpha, zeta"), exception.Message);

            var requests = new List<BatchQueryRequest>
            {
                new("doc", Id: "zeta"),
                new("doc", Id: "alpha"),
                new("doc", Id: " "),
                new("diagnostics", Id: "zeta"),
                new("doc", Id: "Alpha"),
                new("symbols", Id: "alpha")
            };

            var duplicateIds = BatchQueryKernels.FindDuplicateRequestIds(requests);
            Assert.Equal(new[] { "alpha", "zeta" }, duplicateIds);

            var okWords = new[] { 1UL | (1UL << 2) | (1UL << 5) | (1UL << 63) };
            var successCount = BatchQueryKernels.CountResultSuccesses(okWords, 6);
            Assert.Equal(3, successCount);

            Assert.Equal(0, BatchQueryKernels.CountResultSuccesses(Array.Empty<ulong>(), 0));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_InvalidRequestsUseMessageKernels()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-invalid-requests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "outline"
  },
  {
    "command": "doc"
  },
  {
    "command": "type",
    "file": "Program.nl"
  },
  {
    "command": "definition",
    "file": "Program.nl",
    "pos": "bad"
  },
  {
    "command": "unknown"
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

            using var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(5, doc.RootElement.GetProperty("failureCount").GetInt32());

            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.Equal(
                BatchQueryKernels.GetOutlineFileRequiredMessage(),
                results[0].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
            Assert.Equal(
                BatchQueryKernels.GetDocQueryRequiredMessage(),
                results[1].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
            Assert.Equal(
                BatchQueryKernels.GetFileAndPosRequiredMessage(),
                results[2].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
            Assert.Equal(
                BatchQueryKernels.GetInvalidPositionMessage("bad"),
                results[3].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
            Assert.Equal(
                BatchQueryKernels.GetUnsupportedCommandMessage("unknown"),
                results[4].GetProperty("response").GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_PositionParsingUsesQueryKernelSemantics()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-position-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "type",
    "file": "Program.nl",
    "pos": " +1 : +1 "
  },
  {
    "command": "type",
    "file": "Program.nl",
    "pos": "2147483648:1"
  },
  {
    "command": "type",
    "file": "Program.nl",
    "pos": "1_000:2"
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

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal(3, doc.RootElement.GetProperty("requestCount").GetInt32());
            Assert.Equal(0, doc.RootElement.GetProperty("successCount").GetInt32());
            Assert.Equal(3, doc.RootElement.GetProperty("failureCount").GetInt32());

            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            var firstError = results[0].GetProperty("response").GetProperty("error");
            Assert.Equal("noSymbol", firstError.GetProperty("code").GetString());
            Assert.Equal(
                QueryCommandKernels.GetNoSymbolAtPositionMessage("Program.nl", 1, 1),
                firstError.GetProperty("message").GetString());
            var overflowError = results[1].GetProperty("response").GetProperty("error");
            Assert.Equal("invalidRequest", overflowError.GetProperty("code").GetString());
            Assert.Equal(
                BatchQueryKernels.GetInvalidPositionMessage("2147483648:1"),
                overflowError.GetProperty("message").GetString());
            var separatorError = results[2].GetProperty("response").GetProperty("error");
            Assert.Equal("invalidRequest", separatorError.GetProperty("code").GetString());
            Assert.Equal(
                BatchQueryKernels.GetInvalidPositionMessage("1_000:2"),
                separatorError.GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BatchCommand_SymbolKindParsingUsesQueryKernel()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-batch-symbol-kind-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var requestsPath = Path.Combine(tempDir, "requests.json");
            File.WriteAllText(requestsPath, """
[
  {
    "command": "symbols",
    "kind": "class"
  }
]
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "batch",
                "--project", IssueTrackerFixture,
                "--requests", requestsPath
            }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            var response = doc.RootElement.GetProperty("results")[0].GetProperty("response");
            var symbols = response.GetProperty("results").EnumerateArray().ToArray();
            Assert.NotEmpty(symbols);
            Assert.All(symbols, symbol => Assert.Equal("class", symbol.GetProperty("kind").GetString()));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void QueryCommandKernels_SummarizesDaemonParameters()
    {
        var args = new[]
        {
            "--file",
            "Program.nl",
            "--pos",
            "12:4",
            "--name",
            "Main",
            "--kind",
            "Function",
            "--severity",
            "warning",
            "--include-keywords",
            "--clusters"
        };

        var dogfoodSummary = QueryCommandKernels.GetDaemonParameterSummary(args);
        Assert.Equal("Program.nl", dogfoodSummary.File);
        Assert.Equal("12:4", dogfoodSummary.Pos);
        Assert.Equal("Main", dogfoodSummary.Name);
        Assert.Equal("Function", dogfoodSummary.Kind);
        Assert.Equal("warning", dogfoodSummary.Severity);
        Assert.True(dogfoodSummary.IncludeKeywords);
        Assert.True(dogfoodSummary.Clusters);

        var permissive = QueryCommandKernels.GetDaemonParameterSummary(
            new[] { "--file", "--include-keywords", "--pos", "--clusters", "--severity" });
        Assert.Equal("--include-keywords", permissive.File);
        Assert.Equal("--clusters", permissive.Pos);
        Assert.Null(permissive.Severity);
        Assert.True(permissive.IncludeKeywords);
        Assert.True(permissive.Clusters);

        Assert.False(QueryCommandKernels.GetDaemonParameterSummary(new[] { "--file" }).IncludeKeywords);
    }

    [Fact]
    public void QueryCommandKernels_SummarizesCommandOptions()
    {
        var args = new[]
        {
            "Type.Name",
            "--filter",
            "*Service",
            "--function",
            "Main",
            "--limit",
            "25",
            "--requests",
            "batch.json"
        };

        var dogfoodSummary = QueryCommandKernels.GetCommandOptionSummary(args);
        Assert.Equal("*Service", dogfoodSummary.Filter);
        Assert.Equal("Main", dogfoodSummary.Function);
        Assert.Equal("25", dogfoodSummary.Limit);
        Assert.Equal("batch.json", dogfoodSummary.Requests);
        Assert.Equal("Type.Name", dogfoodSummary.LeadingOperand);

        var permissive = QueryCommandKernels.GetCommandOptionSummary(
            new[] { "--filter", "--function", "--limit", "--requests", "--requests" });
        Assert.Equal("--function", permissive.Filter);
        Assert.Equal("--limit", permissive.Function);
        Assert.Equal("--requests", permissive.Limit);
        Assert.Equal("--requests", permissive.Requests);
        Assert.Null(permissive.LeadingOperand);

        var missing = QueryCommandKernels.GetCommandOptionSummary(new[] { "--requests" });
        Assert.Null(missing.Requests);
        Assert.Null(missing.LeadingOperand);
    }

    [Fact]
    public void QueryCommandKernels_SummarizesTopLevelOptions()
    {
        var args = new[]
        {
            "symbols",
            "--project",
            "demo",
            "--file",
            "Program.nl",
            "--pos",
            "12:4",
            "--text",
            "--json",
            "--text",
            "--no-daemon",
            "--compact",
            "loose",
            "--project",
            "other"
        };

        var dogfoodSummary = QueryCommandKernels.GetTopLevelOptionSummary(args);
        Assert.Equal("symbols", dogfoodSummary.Subcommand);
        Assert.Equal("other", dogfoodSummary.ProjectDir);
        Assert.Equal("Program.nl", dogfoodSummary.File);
        Assert.Equal("12:4", dogfoodSummary.Pos);
        Assert.True(dogfoodSummary.UseText);
        Assert.True(dogfoodSummary.NoDaemon);
        Assert.True(dogfoodSummary.InspectCompact);
        Assert.Equal(new[] { "loose" }, dogfoodSummary.RemainingArgs);

        var permissive = QueryCommandKernels.GetTopLevelOptionSummary(new[] { "symbols", "--project", "--file" });
        Assert.Equal("--file", permissive.ProjectDir);
        Assert.Empty(permissive.RemainingArgs);

        var trailingMissing = QueryCommandKernels.GetTopLevelOptionSummary(new[] { "symbols", "--project" });
        Assert.Null(trailingMissing.ProjectDir);
        Assert.Equal(new[] { "--project" }, trailingMissing.RemainingArgs);
    }

    [Fact]
    public void QueryCommandKernels_SelectsInspectOutputMode()
    {
        var cases = new[]
        {
            (UseText: false, InspectCompact: false, Expected: QueryInspectOutputModeKind.Json),
            (UseText: false, InspectCompact: true, Expected: QueryInspectOutputModeKind.CompactJson),
            (UseText: true, InspectCompact: false, Expected: QueryInspectOutputModeKind.Text),
            (UseText: true, InspectCompact: true, Expected: QueryInspectOutputModeKind.InvalidCompactText)
        };

        foreach (var testCase in cases)
        {
            var dogfoodMode = QueryCommandKernels.GetInspectOutputMode(
                testCase.UseText,
                testCase.InspectCompact);
            Assert.Equal(testCase.Expected, dogfoodMode);
        }
    }

    [Fact]
    public void QueryCommandKernels_SelectsDiagnosticsOutputMode()
    {
        var cases = new[]
        {
            (UseText: false, Clusters: false, Expected: QueryDiagnosticsOutputModeKind.Json),
            (UseText: true, Clusters: false, Expected: QueryDiagnosticsOutputModeKind.Text),
            (UseText: false, Clusters: true, Expected: QueryDiagnosticsOutputModeKind.ClustersJson),
            (UseText: true, Clusters: true, Expected: QueryDiagnosticsOutputModeKind.ClustersJson)
        };

        foreach (var testCase in cases)
        {
            var dogfoodMode = QueryCommandKernels.GetDiagnosticsOutputMode(
                testCase.UseText,
                testCase.Clusters);
            Assert.Equal(testCase.Expected, dogfoodMode);
        }
    }

    [Fact]
    public void QueryCommandKernels_SelectsJsonOnlyOutputMode()
    {
        var cases = new[]
        {
            (UseText: false, Expected: QueryJsonOnlyOutputModeKind.Json),
            (UseText: true, Expected: QueryJsonOnlyOutputModeKind.TextUnsupported)
        };

        foreach (var testCase in cases)
        {
            var dogfoodMode = QueryCommandKernels.GetJsonOnlyOutputMode(testCase.UseText);
            Assert.Equal(testCase.Expected, dogfoodMode);
        }
    }

    [Fact]
    public void QueryCommandKernels_SelectsTextJsonOutputMode()
    {
        var cases = new[]
        {
            (UseText: false, Expected: QueryTextJsonOutputModeKind.Json),
            (UseText: true, Expected: QueryTextJsonOutputModeKind.Text)
        };

        foreach (var testCase in cases)
        {
            var dogfoodMode = QueryCommandKernels.GetTextJsonOutputMode(testCase.UseText);
            Assert.Equal(testCase.Expected, dogfoodMode);
        }
    }

    [Fact]
    public void QueryCommandKernels_SelectsDaemonRouting()
    {
        var cases = new[]
        {
            (UseText: false, NoDaemon: false, Expected: true),
            (UseText: false, NoDaemon: true, Expected: false),
            (UseText: true, NoDaemon: false, Expected: false),
            (UseText: true, NoDaemon: true, Expected: false)
        };

        foreach (var testCase in cases)
        {
            var dogfoodShouldUse = QueryCommandKernels.ShouldUseDaemon(
                testCase.UseText,
                testCase.NoDaemon);
            Assert.Equal(testCase.Expected, dogfoodShouldUse);
        }
    }

    [Fact]
    public void QueryInspect_RejectsCompactTextOutputMode()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "inspect",
            "--file",
            "Program.nl",
            "--pos",
            "1:1",
            "--text",
            "--compact",
            "--no-daemon"
        }));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdout));
        Assert.Contains("--compact/--summary is only supported with JSON output.", stderr);
    }

    [Fact]
    public void QueryCommandKernels_ParsePositions()
    {
        var cases = new[]
        {
            ("1:1", true, 1, 1),
            ("42:17", true, 42, 17),
            (" 42 : 17 ", true, 42, 17),
            ("+64:+10", true, 64, 10),
            ("-1:5", true, -1, 5),
            ("2147483647:2147483647", true, 2147483647, 2147483647),
            ("-2147483648:-2147483648", true, -2147483648, -2147483648),
            ("0:0", true, 0, 0),
            ("12:", false, 12, 0),
            (":34", false, 0, 0),
            ("12:abc", false, 12, 0),
            ("abc:12", false, 0, 0),
            ("12:34:56", false, 0, 0),
            ("2147483648:1", false, 0, 0),
            ("1:-2147483649", false, 1, 0),
            ("1_000:2", false, 0, 0),
            ("7 :\t8", true, 7, 8)
        };

        foreach (var (input, expectedParsed, expectedLine, expectedColumn) in cases)
        {
            var parsed = QueryCommandKernels.ParsePosition(input, out var line, out var column);
            Assert.Equal(expectedParsed, parsed);
            Assert.Equal(expectedLine, line);
            Assert.Equal(expectedColumn, column);
        }
    }

    [Fact]
    public void QueryCommandKernels_ParsePositiveInts()
    {
        var cases = new[]
        {
            ("1", true, 1),
            ("25", true, 25),
            (" 25 ", true, 25),
            ("+64", true, 64),
            ("0", false, 0),
            ("-1", false, 0),
            ("2147483647", true, 2147483647),
            ("-2147483648", false, 0),
            ("2147483648", false, 0),
            ("-2147483649", false, 0),
            ("1_000", false, 0),
            ("", false, 0),
            ("   ", false, 0),
            ("12.5", false, 0)
        };

        foreach (var (input, expectedParsed, expectedValue) in cases)
        {
            var parsed = QueryCommandKernels.ParsePositiveInt(input, out var value);
            Assert.Equal(expectedParsed, parsed);
            Assert.Equal(expectedValue, value);
        }
    }

    [Fact]
    public void QueryCommandKernels_ParseSymbolKinds()
    {
        (string Input, bool ExpectedParsed, SymbolKind ExpectedKind)[] cases =
        {
            ("Function", true, SymbolKind.Function),
            ("function", true, SymbolKind.Function),
            (" TypeAlias ", true, SymbolKind.TypeAlias),
            ("EnumMember", true, SymbolKind.EnumMember),
            ("15", true, SymbolKind.Test),
            ("-1", true, (SymbolKind)(-1)),
            ("999", true, (SymbolKind)999),
            ("Function, Class", true, SymbolKind.Class),
            ("not-a-kind", false, default),
            ("", false, default),
            ("   ", false, default)
        };

        foreach (var (input, expectedParsed, expectedKind) in cases)
        {
            var kind = QueryCommandKernels.ParseSymbolKind(input);
            Assert.Equal(expectedParsed, kind.HasValue);
            Assert.Equal(expectedKind, kind.GetValueOrDefault());
        }
    }

    [Fact]
    public void QueryCommandKernels_ShapesMessages()
    {
        var help = QueryCommandKernels.GetHelpText("  symbols       List symbols");
        Assert.Contains("N# Code Intelligence CLI", help);
        Assert.Contains("Usage: nlc query <command> [options]", help);
        Assert.Contains("  symbols       List symbols", help);
        Assert.Contains("JSON queries reuse `nlc daemon` automatically", help);

        Assert.Equal(
            "List symbols (aliases: ls, names)",
            QueryCommandKernels.GetDescriptionWithAliases("List symbols", "ls, names"));
        Assert.Equal("List symbols", QueryCommandKernels.GetDescriptionWithAliases("List symbols", string.Empty));
        Assert.Equal(
            "Unknown query subcommand: nope. Run 'nlc query help' for usage.",
            QueryCommandKernels.GetUnknownSubcommandMessage("nope"));
        Assert.Equal("No compilation unit found for --file Missing.nl", QueryCommandKernels.GetNoCompilationUnitForFileMessage("Missing.nl"));
        Assert.Equal("No compilation units in project.", QueryCommandKernels.GetNoCompilationUnitsMessage());
        Assert.Equal("Usage: nlc query hover --file <path> --pos <line>:<col>", QueryCommandKernels.GetPositionUsageMessage("hover"));
        Assert.Equal(
            "Invalid position format: bad. Expected <line>:<col> (e.g. 5:12)",
            QueryCommandKernels.GetInvalidPositionMessage("bad"));
        Assert.Equal("No symbol found at Program.nl:5:12", QueryCommandKernels.GetNoSymbolAtPositionMessage("Program.nl", 5, 12));
        Assert.Equal("No type information found at Program.nl:5:12", QueryCommandKernels.GetNoTypeInformationAtPositionMessage("Program.nl", 5, 12));
        Assert.Equal("No definition found at Program.nl:5:12", QueryCommandKernels.GetNoDefinitionAtPositionMessage("Program.nl", 5, 12));
        Assert.Equal("No interface found at Program.nl:5:12", QueryCommandKernels.GetNoInterfaceAtPositionMessage("Program.nl", 5, 12));
        Assert.Equal("Performance facts are only available as JSON output.", QueryCommandKernels.GetPerformanceJsonOnlyMessage());
        Assert.Equal("Trusted-site reports are only available as JSON output.", QueryCommandKernels.GetTrustedJsonOnlyMessage());
        Assert.Contains("nlc query implementors --name <interface>", QueryCommandKernels.GetImplementorsUsageMessage());
        Assert.Equal("Batch queries only support JSON output.", QueryCommandKernels.GetBatchJsonOnlyMessage());
        Assert.Equal("Usage: nlc query batch --requests <path-to-json>", QueryCommandKernels.GetBatchUsageMessage());
        Assert.Equal("Batch request file did not contain any requests.", QueryCommandKernels.GetEmptyBatchMessage());
        Assert.Equal("Usage: nlc query outline <file>", QueryCommandKernels.GetOutlineUsageMessage());
        Assert.Equal("File not found: Missing.nl", QueryCommandKernels.GetFileNotFoundMessage("Missing.nl"));
        Assert.Contains("nlc query definition --file", QueryCommandKernels.GetDefinitionUsageMessage());
        Assert.Equal("--compact/--summary is only supported with JSON output.", QueryCommandKernels.GetInspectCompactTextUnsupportedMessage());
        Assert.Contains("Position-based only", QueryCommandKernels.GetReferencesUsageMessage());
        Assert.Equal(
            "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. No name-based or text-based fallback was used.",
            QueryCommandKernels.GetSemanticReferencesUnavailableMessage());
        Assert.Contains("nlc query doc Console.WriteLine", QueryCommandKernels.GetDocUsageMessage());
        Assert.Equal("No documentation found for 'Missing.Type'.", QueryCommandKernels.GetNoDocumentationMessage("Missing.Type"));
        Assert.Equal("Project directory not found: /tmp/missing", QueryCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing"));
        Assert.Equal("Failed to analyze project: bad parse", QueryCommandKernels.GetFailedAnalyzeProjectMessage("bad parse"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => QueryCommand.Execute(new[] { "help" }));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage: nlc query <command> [options]", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var (unknownExitCode, unknownStdout, unknownStderr) = CaptureConsole(() => QueryCommand.Execute(new[] { "wat" }));
        Assert.Equal(1, unknownExitCode);
        Assert.True(string.IsNullOrWhiteSpace(unknownStdout));
        Assert.Equal(
            ProgramCommandKernels.GetErrorLine(QueryCommandKernels.GetUnknownSubcommandMessage("wat")) + Environment.NewLine,
            unknownStderr);
    }

    [Fact]
    public void NewCommandKernels_SummarizesArguments()
    {
        var args = new[] { "--template", "library", "--systems", "PacketCore", "-h" };

        var dogfoodSummary = NewCommandKernels.GetArgumentSummary(args);
        Assert.Equal("PacketCore", dogfoodSummary.FirstPositional);
        Assert.Null(dogfoodSummary.SecondPositional);
        Assert.Equal("library", dogfoodSummary.TemplateOption);
        Assert.True(dogfoodSummary.Systems);
        Assert.True(dogfoodSummary.ShowHelp);

        var positionalTemplate = NewCommandKernels.GetArgumentSummary(new[] { "systems-cli", "PacketTool" });
        Assert.Equal("systems-cli", positionalTemplate.FirstPositional);
        Assert.Equal("PacketTool", positionalTemplate.SecondPositional);
        Assert.Null(positionalTemplate.TemplateOption);

        var typeAlias = NewCommandKernels.GetArgumentSummary(new[] { "--type", "webapi", "MyApi" });
        Assert.Equal("webapi", typeAlias.TemplateOption);
        Assert.Equal("MyApi", typeAlias.FirstPositional);

        var libraryAlias = NewCommandKernels.NormalizeTemplateKind(" LIB ");
        Assert.Equal(NewProjectTemplateKind.Library, libraryAlias);
        var webApiAlias = NewCommandKernels.NormalizeTemplateKind("web-api");
        Assert.Equal(NewProjectTemplateKind.WebApi, webApiAlias);
        var systemsAlias = NewCommandKernels.NormalizeTemplateKind("systems");
        Assert.Equal(NewProjectTemplateKind.SystemsCli, systemsAlias);
        var unknownAlias = NewCommandKernels.NormalizeTemplateKind("unknown");
        Assert.Equal(NewProjectTemplateKind.Unknown, unknownAlias);

        var systemsConsole = NewCommandKernels.ResolveTemplateKind("console", systems: true);
        Assert.Equal(NewProjectTemplateKind.SystemsCli, systemsConsole);
        var systemsLibrary = NewCommandKernels.ResolveTemplateKind("library", systems: true);
        Assert.Equal(NewProjectTemplateKind.SystemsLib, systemsLibrary);
        var systemsTest = NewCommandKernels.ResolveTemplateKind("test", systems: true);
        Assert.Equal(NewProjectTemplateKind.Test, systemsTest);
        var effectiveWebApi = NewCommandKernels.ResolveTemplateKind("web-api", systems: false);
        Assert.Equal(NewProjectTemplateKind.WebApi, effectiveWebApi);

        var webApiSourceKinds = NewCommandKernels.GetTemplateSourceFileKinds("webapi");
        Assert.Equal(
            new[] { NewTemplateSourceFileKind.Program, NewTemplateSourceFileKind.WebApiController },
            webApiSourceKinds);
        var systemsLibSourceKinds = NewCommandKernels.GetTemplateSourceFileKinds("systems-lib");
        Assert.Equal(
            new[] { NewTemplateSourceFileKind.PacketCore, NewTemplateSourceFileKind.PacketCoreTests },
            systemsLibSourceKinds);
        var unknownSourceKinds = NewCommandKernels.GetTemplateSourceFileKinds("unknown");
        Assert.Empty(unknownSourceKinds);

        Assert.True(NewCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);

        var helpText = NewCommandKernels.GetHelpText();
        Assert.Contains("N# New Project", helpText);
        Assert.Contains("Usage: nlc new <project-name>", helpText);
        Assert.Contains("Project creation failed", helpText);
        Assert.Equal(
            "Usage: nlc new <project-name> [--template <template>]",
            NewCommandKernels.GetUsageMessage());
        Assert.Equal(
            "Invalid template. Expected one of: console, library, test, webapi, systems-cli, systems-lib.",
            NewCommandKernels.GetInvalidTemplateMessage());
        Assert.Equal(
            "Directory already exists: /tmp/MyApp. Use a different name or remove the existing directory.",
            NewCommandKernels.GetDirectoryExistsMessage("/tmp/MyApp"));
        Assert.Equal(
            "Creating new systems-cli project: PacketTool",
            NewCommandKernels.GetCreatingProjectMessage("systems-cli", "PacketTool"));
        Assert.Equal("Created: MyApp/project.yml", NewCommandKernels.GetCreatedFileMessage("MyApp", "project.yml"));
        Assert.Equal(
            "Project shape: csproj-free source tree; nlc builds directly from project.yml.",
            NewCommandKernels.GetProjectShapeMessage());
        Assert.Equal(
            "To check systems policy and inspect performance facts:",
            NewCommandKernels.GetNextStepsIntroMessage("systems-lib"));
        Assert.Equal("To build your project:", NewCommandKernels.GetNextStepsIntroMessage("library"));
        Assert.Equal("  cd MyApp", NewCommandKernels.GetCdCommandMessage("MyApp"));
        Assert.Equal("  nlc check --systems-report", NewCommandKernels.GetSystemsReportCommandMessage());
        Assert.Equal("  nlc build --perf-report", NewCommandKernels.GetSystemsBuildCommandMessage());
        Assert.Equal("  nlc build", NewCommandKernels.GetBuildCommandMessage());
        Assert.Equal("  nlc test", NewCommandKernels.GetTestCommandMessage());
        Assert.Equal("  nlc run", NewCommandKernels.GetRunCommandMessage());
        Assert.Equal("Failed to create project: denied", NewCommandKernels.GetFailedMessage("denied"));

        var consoleYaml = NewCommandKernels.GetProjectYamlText("MyApp", "console");
        Assert.Equal(ProjectFileParser.GenerateTemplate("MyApp"), consoleYaml);

        var libraryYaml = NewCommandKernels.GetProjectYamlText("MyLib", "library");
        Assert.Contains("name: MyLib\n", libraryYaml);
        Assert.Contains("outputType: library\n", libraryYaml);
        Assert.Contains("language:\n  asyncDefaultType: ValueTask\n", libraryYaml);
        Assert.DoesNotContain("entry: Program.nl", libraryYaml, StringComparison.Ordinal);

        var webApiYaml = NewCommandKernels.GetProjectYamlText("MyApi", "webapi");
        Assert.Contains("sdk: Microsoft.NET.Sdk.Web\n", webApiYaml);
        Assert.Contains("  - framework: Microsoft.AspNetCore.App\n", webApiYaml);
        Assert.Contains("  - nuget: Swashbuckle.AspNetCore\n    version: 7.2.0\n", webApiYaml);

        var systemsCliYaml = NewCommandKernels.GetProjectYamlText("PacketTool", "systems-cli");
        Assert.Contains("entry: Program.nl\n", systemsCliYaml);
        Assert.Contains("outputType: exe\n", systemsCliYaml);
        Assert.Contains("  profile: systems\n", systemsCliYaml);
        Assert.Contains("    warmup:\n      - Warmup\n", systemsCliYaml);

        var systemsLibYaml = NewCommandKernels.GetProjectYamlText("PacketCore", "systems-lib");
        Assert.Contains("outputType: library\n", systemsLibYaml);
        Assert.Contains("  profile: systems\n", systemsLibYaml);
        Assert.DoesNotContain("entry: Program.nl", systemsLibYaml, StringComparison.Ordinal);

        Assert.Equal(
            "{\n"
            + "  \"sdk\": {\n"
            + "    \"version\": \"10.0.100\",\n"
            + "    \"rollForward\": \"latestFeature\"\n"
            + "  },\n"
            + "  \"msbuild-sdks\": {\n"
            + "    \"NSharpLang.Sdk\": \"0.1.0\"\n"
            + "  }\n"
            + "}\n",
            NewCommandKernels.GetGlobalJsonText());
        var defaultNuGetConfig = NewCommandKernels.GetNuGetConfigText("%HOME%/.nsharp/packages");
        Assert.Equal(
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
            + "<configuration>\n"
            + "  <packageSources>\n"
            + "    <clear />\n"
            + "    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" />\n"
            + "    <add key=\"nsharp-local\" value=\"%HOME%/.nsharp/packages\" />\n"
            + "  </packageSources>\n"
            + "</configuration>\n",
            defaultNuGetConfig);
        Assert.Contains("value=\"%HOME%/.nsharp/packages\"", defaultNuGetConfig);

        var escapedNuGetConfig = NewCommandKernels.GetNuGetConfigText("/tmp/a&b<c>d\"e'f/packages");
        Assert.Contains("/tmp/a&amp;b&lt;c&gt;d&quot;e&apos;f/packages", escapedNuGetConfig);

        var consoleSource = NewCommandKernels.GetTemplateSourceText("console", NewTemplateSourceFileKind.Program);
        Assert.Equal("func main() {\n    print \"Hello, N#!\"\n}\n", consoleSource);

        var calculatorSource = NewCommandKernels.GetTemplateSourceText("library", NewTemplateSourceFileKind.Calculator);
        Assert.Contains("class Calculator {\n", calculatorSource);
        Assert.Contains("static func Add(a: int, b: int): int", calculatorSource);

        var calculatorTestsSource = NewCommandKernels.GetTemplateSourceText("test", NewTemplateSourceFileKind.CalculatorTests);
        Assert.Contains("test \"adds two numbers\" {\n", calculatorTestsSource);
        Assert.Contains("assert result == 3\n", calculatorTestsSource);

        var webApiProgramSource = NewCommandKernels.GetTemplateSourceText("webapi", NewTemplateSourceFileKind.Program);
        Assert.Contains("WebApplication.CreateBuilder(args)", webApiProgramSource);
        var controllerSource = NewCommandKernels.GetTemplateSourceText("webapi", NewTemplateSourceFileKind.WebApiController);
        Assert.Contains("[Route(\"api/weather\")]\n", controllerSource);
        Assert.Contains("CreateWeatherRequest", controllerSource);

        var systemsCliSource = NewCommandKernels.GetTemplateSourceText("systems-cli", NewTemplateSourceFileKind.Program);
        Assert.Contains("allow(alloc, reason: \"CLI startup allocates outside the hot parser\")", systemsCliSource);
        Assert.Contains("func main(): void", systemsCliSource);

        var packetCoreSource = NewCommandKernels.GetTemplateSourceText("systems-lib", NewTemplateSourceFileKind.PacketCore);
        Assert.Contains("public func AdaptPacket(bytes: byte[]): Result<uint, ParseError>", packetCoreSource);
        Assert.DoesNotContain("func main", packetCoreSource, StringComparison.Ordinal);

        var packetCoreTestsSource = NewCommandKernels.GetTemplateSourceText("systems-lib", NewTemplateSourceFileKind.PacketCoreTests);
        Assert.Equal("test \"systems smoke\" {\n    assert true\n}\n", packetCoreTestsSource);
    }

    [Fact]
    public void PositionalArgumentKernels_SelectsAllPositionals()
    {
        var args = new[]
        {
            "--template",
            "library",
            "systems-cli",
            "PacketTool",
            "--systems",
            "--diff",
            "src/App.nl",
            "-x",
            "",
            "--type",
            "console"
        };

        var positionalArgs = PositionalArgumentKernels.GetArgs(
            args,
            new[] { "--template", "--type" });
        Assert.Equal(new[] { "systems-cli", "PacketTool", "src/App.nl", "" }, positionalArgs);
    }

    [Fact]
    public void CheckCommandKernels_SummarizesOptionsAndSkipsBackendValue()
    {
        var args = new[] { "--backend", "il", "samples/demo", "--text", "--aot", "--systems-report" };
        var dogfoodSummary = CheckCommandKernels.GetArgumentSummary(args);
        Assert.Null(dogfoodSummary.ProjectOption);
        Assert.Equal("il", dogfoodSummary.BackendOption);
        Assert.Equal("samples/demo", dogfoodSummary.PositionalProject);
        Assert.True(dogfoodSummary.UseText);
        Assert.True(dogfoodSummary.Aot);
        Assert.True(dogfoodSummary.SystemsReport);
        Assert.False(dogfoodSummary.ShowHelp);

        var permissiveValue = CheckCommandKernels.GetArgumentSummary(new[] { "--project", "--backend", "il" });
        Assert.Equal("--backend", permissiveValue.ProjectOption);
        Assert.Equal("il", permissiveValue.BackendOption);

        Assert.True(CheckCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);

        var helpText = CheckCommandKernels.GetHelpText();
        Assert.Contains("N# Type Check", helpText);
        Assert.Contains("Usage: nlc check [options] [project-dir]", helpText);
        Assert.Contains("One or more errors detected", helpText);

        Assert.Equal(
            "Directory not found: /tmp/missing-check-project",
            CheckCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing-check-project"));
        Assert.Equal(
            "--systems-report is only available as JSON output.",
            CheckCommandKernels.GetSystemsReportTextUnavailableMessage());
        Assert.Equal(
            "  Checked 1 file — no errors. [0.1s]",
            CheckCommandKernels.GetNoErrorsMessage(1, "0.1s"));
        Assert.Equal(
            "  Checked 2 files — no errors. [0.2s]",
            CheckCommandKernels.GetNoErrorsMessage(2, "0.2s"));
        Assert.Equal("  Checked in 0.3s", CheckCommandKernels.GetCheckedInMessage("0.3s"));
        Assert.Equal("  Check failed in 0.4s", CheckCommandKernels.GetFailedElapsedMessage("0.4s"));
        Assert.Equal("Check failed: backend exploded", CheckCommandKernels.GetFailedMessage("backend exploded"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => CheckCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage: nlc check [options] [project-dir]", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var missingProject = Path.Combine(Path.GetTempPath(), $"nsharp-check-missing-{Guid.NewGuid():N}");
        var (missingExitCode, missingStdout, missingStderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", missingProject, "--text" }));
        Assert.Equal(1, missingExitCode);
        Assert.True(string.IsNullOrWhiteSpace(missingStdout));
        Assert.Contains($"Directory not found: {Path.GetFullPath(missingProject)}", missingStderr);
    }

    [Fact]
    public void CheckCommandKernels_SelectsEffectiveOutputMode()
    {
        var defaultMode = CheckCommandKernels.GetEffectiveOutputMode(false, false);
        Assert.Equal(CheckOutputModeKind.Json, defaultMode);

        var textMode = CheckCommandKernels.GetEffectiveOutputMode(true, false);
        Assert.Equal(CheckOutputModeKind.Text, textMode);

        var systemsReportMode = CheckCommandKernels.GetEffectiveOutputMode(false, true);
        Assert.Equal(CheckOutputModeKind.SystemsReportJson, systemsReportMode);

        var invalidMode = CheckCommandKernels.GetEffectiveOutputMode(true, true);
        Assert.Equal(CheckOutputModeKind.InvalidSystemsReportText, invalidMode);
    }

    [Fact]
    public void CompilationBackendSelectionKernels_ResolvesEffectiveBackend()
    {
        Assert.Equal(CompilationBackend.Il, CompilationBackendSelectionKernels.Resolve(null, null));
        Assert.Equal(CompilationBackend.Il, CompilationBackendSelectionKernels.Resolve("  ", new ProjectConfig { Backend = " il " }));
        Assert.Equal(CompilationBackend.Il, CompilationBackendSelectionKernels.Resolve("il", new ProjectConfig { Backend = "transpile" }));

        var retired = Assert.Throws<InvalidOperationException>(() =>
            CompilationBackendSelectionKernels.Resolve(null, new ProjectConfig { Backend = " transpile " }));
        Assert.Contains("removed", retired.Message);

        var invalid = Assert.Throws<InvalidOperationException>(() =>
            CompilationBackendSelectionKernels.Resolve(null, new ProjectConfig { Backend = "native" }));
        Assert.Equal("Invalid backend: 'native'. Must be 'il'.", invalid.Message);
    }

    [Fact]
    public void FixCommandArgumentKernels_SummarizesOptionsAndProject()
    {
        var args = new[]
        {
            "--dry-run",
            "--text",
            "--include-review-needed",
            "--file",
            "Program.nl",
            "samples/demo"
        };

        var dogfoodSummary = FixCommandArgumentKernels.GetArgumentSummary(args);
        Assert.Null(dogfoodSummary.ProjectOption);
        Assert.Equal("Program.nl", dogfoodSummary.FileOption);
        Assert.Equal("samples/demo", dogfoodSummary.PositionalProject);
        Assert.True(dogfoodSummary.DryRun);
        Assert.True(dogfoodSummary.UseText);
        Assert.True(dogfoodSummary.IncludeReviewNeeded);
        Assert.False(dogfoodSummary.ShowHelp);

        var explicitProject = FixCommandArgumentKernels.GetArgumentSummary(new[] { "--project", "ignored", "samples/demo" });
        Assert.Equal("ignored", explicitProject.ProjectOption);
        Assert.Equal("samples/demo", explicitProject.PositionalProject);

        var permissiveValue = FixCommandArgumentKernels.GetArgumentSummary(new[] { "--project", "--file", "Program.nl" });
        Assert.Equal("--file", permissiveValue.ProjectOption);
        Assert.Equal("Program.nl", permissiveValue.FileOption);

        Assert.True(FixCommandArgumentKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);
    }

    [Fact]
    public void FixCommandArgumentKernels_SelectsEffectiveOutputMode()
    {
        var defaultMode = FixCommandArgumentKernels.GetEffectiveOutputMode(false);
        Assert.Equal(FixOutputModeKind.Json, defaultMode);

        var textMode = FixCommandArgumentKernels.GetEffectiveOutputMode(true);
        Assert.Equal(FixOutputModeKind.Text, textMode);
    }

    [Fact]
    public void FixCommandKernels_ShapesMessages()
    {
        var helpText = FixCommandKernels.GetHelpText();
        Assert.Contains("N# Auto-Fix", helpText);
        Assert.Contains("Usage: nlc fix [options] [project-dir]", helpText);
        Assert.Contains("--include-review-needed", helpText);

        Assert.Equal(
            "Directory not found: /tmp/missing-fix-project",
            FixCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing-fix-project"));
        Assert.Equal("File not found: Missing.nl", FixCommandKernels.GetFileNotFoundMessage("Missing.nl"));
        Assert.Equal("No .nl files found.", FixCommandKernels.GetNoFilesFoundMessage());
        Assert.Equal("Fix failed: disk full", FixCommandKernels.GetFailedMessage("disk full"));
        Assert.Equal("Nothing to fix.", FixCommandKernels.GetNothingToFixMessage());
        Assert.Equal("Would fix 1 issue in 1 file:", FixCommandKernels.GetAppliedHeader(1, 1, dryRun: true));
        Assert.Equal("Fixed 2 issues in 3 files:", FixCommandKernels.GetAppliedHeader(2, 3, dryRun: false));
        Assert.Equal("  src/Program.nl:", FixCommandKernels.GetAppliedFileHeader("src/Program.nl"));
        Assert.Equal("    [NL001] Remove unused variable", FixCommandKernels.GetEntryLine("NL001", "Remove unused variable"));
        Assert.Equal("Skipped 1 fix:", FixCommandKernels.GetSkippedHeader(1));
        Assert.Equal("Skipped 2 fixes:", FixCommandKernels.GetSkippedHeader(2));
        Assert.Equal(
            "suggestion only — manual review required",
            FixCommandKernels.GetSkippedReason("suggestionOnly"));
        Assert.Equal(
            "requires --include-review-needed flag",
            FixCommandKernels.GetSkippedReason("reviewNeeded"));
        Assert.Equal(
            "  [NL010] Remove unused import (requires --include-review-needed flag)",
            FixCommandKernels.GetSkippedLine("NL010", "Remove unused import", "requires --include-review-needed flag"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => FixCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage: nlc fix [options] [project-dir]", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var missingProject = Path.Combine(Path.GetTempPath(), $"nsharp-fix-missing-{Guid.NewGuid():N}");
        var (missingExitCode, missingStdout, missingStderr) = CaptureConsole(() =>
            FixCommand.Execute(new[] { "--project", missingProject, "--text" }));
        Assert.Equal(1, missingExitCode);
        Assert.True(string.IsNullOrWhiteSpace(missingStdout));
        Assert.Contains($"Directory not found: {Path.GetFullPath(missingProject)}", missingStderr);
    }

    [Fact]
    public void UpdateCommandKernels_SummarizesArguments()
    {
        var args = new[] { "--dry-run", "-v", "Newtonsoft.Json", "-h" };

        var dogfoodSummary = UpdateCommandKernels.GetArgumentSummary(args);
        Assert.Equal("Newtonsoft.Json", dogfoodSummary.TargetPackage);
        Assert.True(dogfoodSummary.DryRun);
        Assert.True(dogfoodSummary.ShowHelp);

        Assert.Equal("Newtonsoft.Json", UpdateCommandKernels.GetArgumentSummary(new[] { "--dry-run", "Newtonsoft.Json" }).TargetPackage);
        Assert.Equal("Serilog", UpdateCommandKernels.GetArgumentSummary(new[] { "--dry-run", "-v", "Serilog" }).TargetPackage);
        Assert.Null(UpdateCommandKernels.GetArgumentSummary(new[] { "--dry-run" }).TargetPackage);
        Assert.True(UpdateCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);
        Assert.Equal("help", UpdateCommandKernels.GetArgumentSummary(new[] { "help" }).TargetPackage);

        var helpText = UpdateCommandKernels.GetHelpText();
        Assert.Contains("N# Update Dependencies", helpText);
        Assert.Contains("Usage: nlc update [package] [options]", helpText);
        Assert.Contains("Update failed", helpText);
        Assert.Equal("No project.yml found.", UpdateCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal("No NuGet dependencies to update.", UpdateCommandKernels.GetNoNuGetDependenciesMessage());
        Assert.Equal(
            "Package 'Serilog' not found in dependencies.",
            UpdateCommandKernels.GetPackageNotFoundMessage("Serilog"));
        Assert.Equal(
            "  Could not resolve latest version for Serilog",
            UpdateCommandKernels.GetResolveLatestFailureMessage("Serilog"));
        Assert.Equal(
            "  Serilog@3.1.0 is up to date",
            UpdateCommandKernels.GetPackageUpToDateMessage("Serilog", "3.1.0"));
        Assert.Equal(
            "  Serilog: unversioned -> 3.1.0",
            UpdateCommandKernels.GetPackageUpdateMessage("Serilog", string.Empty, "3.1.0"));
        Assert.Equal("Updated 1 package.", UpdateCommandKernels.GetUpdatedPackagesMessage(1));
        Assert.Equal("Updated 2 packages.", UpdateCommandKernels.GetUpdatedPackagesMessage(2));
        Assert.Equal("(dry run — no changes made)", UpdateCommandKernels.GetDryRunMessage());
        Assert.Equal("All packages are up to date.", UpdateCommandKernels.GetAllPackagesUpToDateMessage());
        Assert.Equal("Update failed: boom", UpdateCommandKernels.GetFailedMessage("boom"));
    }

    [Fact]
    public void AddCommandKernels_SummarizesArguments()
    {
        var args = new[] { "--version", "13.0.3", "--framework", "--prerelease", "Newtonsoft.Json" };

        var dogfoodSummary = AddCommandKernels.GetArgumentSummary(args);
        Assert.Equal("13.0.3", dogfoodSummary.VersionOption);
        Assert.Null(dogfoodSummary.PathOption);
        Assert.Equal("Newtonsoft.Json", dogfoodSummary.PackageOperand);
        Assert.True(dogfoodSummary.Framework);
        Assert.True(dogfoodSummary.Prerelease);
        Assert.False(dogfoodSummary.ShowHelp);

        Assert.Equal(
            "Newtonsoft.Json",
            AddCommandKernels.GetArgumentSummary(new[] { "--version", "13.0.3", "--framework", "Newtonsoft.Json" }).PackageOperand);
        Assert.Equal(
            "Serilog@3.1.1",
            AddCommandKernels.GetArgumentSummary(new[] { "--prerelease", "Serilog@3.1.1" }).PackageOperand);
        var pathSummary = AddCommandKernels.GetArgumentSummary(new[] { "--path", "../MyLibrary" });
        Assert.Equal("../MyLibrary", pathSummary.PathOption);
        Assert.Null(pathSummary.PackageOperand);
        var permissiveValue = AddCommandKernels.GetArgumentSummary(new[] { "--version", "--path", "../MyLibrary" });
        Assert.Equal("--path", permissiveValue.VersionOption);
        Assert.Equal("../MyLibrary", permissiveValue.PathOption);
        Assert.Equal("../MyLibrary", permissiveValue.PackageOperand);
        Assert.True(AddCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);
        Assert.Null(AddCommandKernels.GetArgumentSummary(new[] { "--version", "13.0.3" }).PackageOperand);

        var inlineSpec = AddCommandKernels.GetPackageSpec("Serilog@3.1.0", "ignored");
        Assert.Equal("Serilog", inlineSpec.PackageName);
        Assert.Equal("3.1.0", inlineSpec.Version);

        var explicitSpec = AddCommandKernels.GetPackageSpec("Serilog", "3.1.0");
        Assert.Equal("Serilog", explicitSpec.PackageName);
        Assert.Equal("3.1.0", explicitSpec.Version);

        var unversionedSpec = AddCommandKernels.GetPackageSpec("Serilog", null);
        Assert.Equal("Serilog", unversionedSpec.PackageName);
        Assert.Null(unversionedSpec.Version);

        var leadingAtSpec = AddCommandKernels.GetPackageSpec("@scope@1.0", "2.0.0");
        Assert.Equal("@scope@1.0", leadingAtSpec.PackageName);
        Assert.Equal("2.0.0", leadingAtSpec.Version);

        var dependencyLines = new[]
        {
            "name: Demo",
            "dependencies:",
            "  - Newtonsoft.Json@13.0.3",
            "    version: ignored",
            "targetFramework: net10.0"
        };
        var insertAt = AddCommandKernels.GetDependencyInsertIndex(dependencyLines);
        Assert.Equal(4, insertAt);

        var missingDependencySection = AddCommandKernels.GetDependencyInsertIndex(
            new[] { "name: Demo", "targetFramework: net10.0" });
        Assert.Equal(-1, missingDependencySection);

        var dependencies = new List<Reference>
        {
            new() { Nuget = "Newtonsoft.Json" },
            new() { Framework = "Microsoft.AspNetCore.App" },
            new() { Project = "../Shared/project.yml" },
            new()
        };

        var packageExists = AddCommandKernels.PackageOrFrameworkDependencyExists(
            dependencies,
            "newtonsoft.json");
        Assert.True(packageExists);

        var frameworkExists = AddCommandKernels.PackageOrFrameworkDependencyExists(
            dependencies,
            "microsoft.aspnetcore.app");
        Assert.True(frameworkExists);

        var packageMissing = AddCommandKernels.PackageOrFrameworkDependencyExists(
            dependencies,
            "Serilog");
        Assert.False(packageMissing);

        var projectExists = AddCommandKernels.ProjectDependencyExists(
            dependencies,
            "../shared/PROJECT.yml");
        Assert.True(projectExists);

        var projectMissing = AddCommandKernels.ProjectDependencyExists(
            dependencies,
            "../Other/project.yml");
        Assert.False(projectMissing);

        Assert.Equal(
            "Usage: nlc add <package> [--version <ver>]\n       nlc add <package>@<version>",
            AddCommandKernels.GetUsageMessage());
        Assert.Contains("--path <path>", AddCommandKernels.GetHelpText());
        Assert.Equal(
            "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project.",
            AddCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal(
            "Resolving latest version for Serilog...",
            AddCommandKernels.GetResolvingLatestVersionMessage("Serilog"));
        Assert.Equal(
            "Could not find package 'Missing.Package' on NuGet. Check the package name and try again.",
            AddCommandKernels.GetPackageNotFoundMessage("Missing.Package"));
        Assert.Equal(
            "'Serilog' is already in dependencies. Use 'nlc update' to change the version.",
            AddCommandKernels.GetDuplicatePackageMessage("Serilog"));
        Assert.Equal(
            "Project reference '../Shared/project.yml' is already in dependencies.",
            AddCommandKernels.GetDuplicateProjectReferenceMessage("../Shared/project.yml"));
        Assert.Equal(
            "Added framework reference 'Microsoft.AspNetCore.App' to project.yml",
            AddCommandKernels.GetFrameworkAddedMessage("Microsoft.AspNetCore.App"));
        Assert.Equal("Added Serilog@3.1.0 to project.yml", AddCommandKernels.GetPackageAddedMessage("Serilog", "3.1.0"));
        Assert.Equal(
            "Added project reference '../Shared/project.yml' to project.yml",
            AddCommandKernels.GetProjectReferenceAddedMessage("../Shared/project.yml"));
    }

    [Fact]
    public void LintCommandKernels_SelectsFileArgsAfterProjectValueExclusion()
    {
        var empty = LintCommandKernels.GetFileArgs(Array.Empty<string>());
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

        var files = LintCommandKernels.GetFileArgs(args);
        Assert.Equal(new[] { "Program.nl", "Other.nl" }, files);
    }

    [Fact]
    public void LintCommandKernels_SummarizesOptions()
    {
        var defaultSummary = LintCommandKernels.GetOptionSummary(Array.Empty<string>());
        Assert.Null(defaultSummary.ProjectOption);
        Assert.False(defaultSummary.UseText);
        Assert.False(defaultSummary.UseJson);
        Assert.False(defaultSummary.ShowHelp);

        var args = new[] { "--project", "src", "--text", "--json", "Program.nl", "-h" };
        var dogfoodSummary = LintCommandKernels.GetOptionSummary(args);
        Assert.Equal("src", dogfoodSummary.ProjectOption);
        Assert.True(dogfoodSummary.UseText);
        Assert.True(dogfoodSummary.UseJson);
        Assert.True(dogfoodSummary.ShowHelp);

        var permissiveValue = LintCommandKernels.GetOptionSummary(new[] { "--project", "--json" });
        Assert.Equal("--json", permissiveValue.ProjectOption);
        Assert.True(permissiveValue.UseJson);

        Assert.True(LintCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);

        var helpText = LintCommandKernels.GetHelpText();
        Assert.Contains("N# Lint", helpText);
        Assert.Contains("Usage: nlc lint [options] [files...]", helpText);
        Assert.Contains("One or more errors were reported", helpText);

        Assert.Equal("warning", LintCommandKernels.GetSeverityText(DiagnosticSeverity.Warning));
        Assert.Equal("error", LintCommandKernels.GetSeverityText(DiagnosticSeverity.Error));
        Assert.Equal("info", LintCommandKernels.GetSeverityText(DiagnosticSeverity.Info));

        Assert.Equal(
            "Directory not found: /tmp/missing-lint-project",
            LintCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing-lint-project"));
        Assert.Equal(
            "No .nl files found. Ensure you are in a project directory or specify files explicitly.",
            LintCommandKernels.GetNoFilesFoundMessage());
        Assert.Equal("File not found: Missing.nl", LintCommandKernels.GetFileNotFoundMessage("Missing.nl"));
        Assert.Equal(
            "Parse errors in Broken.nl: expected expression",
            LintCommandKernels.GetParseErrorsMessage("Broken.nl", "expected expression"));
        Assert.Equal(
            "Error linting: disk full",
            LintCommandKernels.GetErrorLintingDiagnosticMessage("disk full"));
        Assert.Equal(
            "Error linting Broken.nl: disk full",
            LintCommandKernels.GetErrorLintingFileMessage("Broken.nl", "disk full"));
        Assert.Equal(
            "  Linted 1 file — no issues. [0.1s]",
            LintCommandKernels.GetNoIssuesMessage(1, "0.1s"));
        Assert.Equal(
            "  Linted 2 files — no issues. [0.2s]",
            LintCommandKernels.GetNoIssuesMessage(2, "0.2s"));
        Assert.Equal("  Linted in 0.3s", LintCommandKernels.GetLintedInMessage("0.3s"));
        Assert.Equal("Lint failed: backend exploded", LintCommandKernels.GetFailedMessage("backend exploded"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => LintCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage: nlc lint [options] [files...]", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var missingProject = Path.Combine(Path.GetTempPath(), $"nsharp-lint-missing-{Guid.NewGuid():N}");
        var (missingExitCode, missingStdout, missingStderr) = CaptureConsole(() =>
            LintCommand.Execute(new[] { "--project", missingProject, "--text" }));
        Assert.Equal(1, missingExitCode);
        Assert.True(string.IsNullOrWhiteSpace(missingStdout));
        Assert.Contains($"Directory not found: {Path.GetFullPath(missingProject)}", missingStderr);
    }

    [Fact]
    public void LintCommandKernels_SelectsEffectiveOutputMode()
    {
        var defaultMode = LintCommandKernels.GetEffectiveOutputMode(false, false);
        Assert.Equal(LintOutputModeKind.Json, defaultMode);

        var explicitJson = LintCommandKernels.GetEffectiveOutputMode(false, true);
        Assert.Equal(LintOutputModeKind.Json, explicitJson);

        var explicitText = LintCommandKernels.GetEffectiveOutputMode(true, false);
        Assert.Equal(LintOutputModeKind.Text, explicitText);

        var jsonWins = LintCommandKernels.GetEffectiveOutputMode(true, true);
        Assert.Equal(LintOutputModeKind.Json, jsonWins);
    }

    [Fact]
    public void WatchCommandKernels_SelectsForwardedArgs()
    {
        var args = new[]
        {
            "test",
            "--project",
            "samples/demo",
            "--filter",
            "AddPerson",
            "--debounce-ms",
            "50",
            "--json",
            "--max-runs",
            "2",
            "--coverage",
            "-h",
            "--backend",
            "il"
        };

        var forwardedArgs = WatchCommandKernels.GetForwardedArgs(args);
        Assert.Equal(new[] { "--filter", "AddPerson", "--json", "--coverage", "--backend", "il" }, forwardedArgs);
    }

    [Fact]
    public void WatchCommandKernels_SummarizesTargets()
    {
        var build = WatchCommandKernels.GetTargetSummary(new[] { "BUILD", "--max-runs", "1" });
        Assert.Equal(WatchTargetKind.Build, build.TargetKind);

        var unknown = WatchCommandKernels.GetTargetSummary(new[] { "serve", "--max-runs", "1" });
        Assert.Equal(WatchTargetKind.Unknown, unknown.TargetKind);
        Assert.Equal("check", WatchCommandKernels.GetTargetCommandName(WatchTargetKind.Check));
        Assert.Equal("build", WatchCommandKernels.GetTargetCommandName(WatchTargetKind.Build));
        Assert.Equal("test", WatchCommandKernels.GetTargetCommandName(WatchTargetKind.Test));
        Assert.Equal("lint", WatchCommandKernels.GetTargetCommandName(WatchTargetKind.Lint));
        Assert.Equal("format", WatchCommandKernels.GetTargetCommandName(WatchTargetKind.Format));
        Assert.Equal(string.Empty, WatchCommandKernels.GetTargetCommandName(WatchTargetKind.Unknown));
        Assert.Equal(
            "Unsupported watch target 'serve'. Expected check, build, test, lint, or format.",
            WatchCommandKernels.GetUnsupportedTargetMessage("serve"));

        var (exitCode, _, stderr) = CaptureConsole(() =>
            WatchCommand.Execute(new[] { "SERVE", "--max-runs", "1" }));
        Assert.Equal(1, exitCode);
        Assert.Contains("Unsupported watch target 'serve'", stderr);
    }

    [Fact]
    public void WatchCommandKernels_SummarizesOptions()
    {
        var args = new[]
        {
            "test",
            "--project",
            "samples/demo",
            "--debounce-ms",
            "50",
            "--max-runs",
            "2",
            "--json",
            "-h"
        };

        var dogfoodSummary = WatchCommandKernels.GetOptionSummary(args);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.Equal("50", dogfoodSummary.DebounceMsOption);
        Assert.Equal("2", dogfoodSummary.MaxRunsOption);
        Assert.True(dogfoodSummary.ShowHelp);

        var permissiveValues = WatchCommandKernels.GetOptionSummary(
            new[] { "test", "--project", "--debounce-ms", "--max-runs" });
        Assert.Equal("--debounce-ms", permissiveValues.ProjectOption);
        Assert.Equal("--max-runs", permissiveValues.DebounceMsOption);
        Assert.Null(permissiveValues.MaxRunsOption);
        Assert.False(permissiveValues.ShowHelp);

        Assert.True(WatchCommandKernels.GetOptionSummary(Array.Empty<string>()).ShowHelp);
        Assert.True(WatchCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);

        var helpText = WatchCommandKernels.GetHelpText();
        Assert.Contains("N# Watch", helpText);
        Assert.Contains("Usage: nlc watch <check|build|test|lint|format>", helpText);
        Assert.Contains("Invalid usage or the last watched run failed", helpText);
        Assert.Equal(
            "Project directory not found: /tmp/nsharp-missing",
            WatchCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/nsharp-missing"));
        Assert.Equal(
            "--debounce-ms expects a positive integer.",
            WatchCommandKernels.GetPositiveIntExpectedMessage("--debounce-ms"));
        Assert.Equal(
            "Watching /tmp/nsharp for N# changes. Press Ctrl+C to stop.",
            WatchCommandKernels.GetStartedMessage("/tmp/nsharp"));
        Assert.Equal(
            "Change detected at 12:34:56. Re-running `nlc check`.",
            WatchCommandKernels.GetChangeDetectedMessage("12:34:56", "check"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => WatchCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
        Assert.Contains("Usage: nlc watch <check|build|test|lint|format>", helpStdout);

        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-watch-missing-{Guid.NewGuid():N}");
        var (missingExitCode, missingStdout, missingStderr) = CaptureConsole(() =>
            WatchCommand.Execute(new[] { "check", "--project", missingDir }));
        Assert.Equal(1, missingExitCode);
        Assert.True(string.IsNullOrWhiteSpace(missingStdout));
        Assert.Contains($"Project directory not found: {Path.GetFullPath(missingDir)}", missingStderr);

        var (debounceExitCode, debounceStdout, debounceStderr) = CaptureConsole(() =>
            WatchCommand.Execute(new[] { "check", "--debounce-ms", "0" }));
        Assert.Equal(1, debounceExitCode);
        Assert.True(string.IsNullOrWhiteSpace(debounceStdout));
        Assert.Contains("--debounce-ms expects a positive integer.", debounceStderr);
    }

    [Fact]
    public void WatchCommandKernels_ParsePositiveIntsWithNSharpKernel()
    {
        var cases = new[]
        {
            ("1", 1),
            (" 25 ", 25),
            ("+3", 3),
            ("0", 0),
            ("-1", 0),
            ("2147483647", 2147483647),
            ("2147483648", 0),
            ("1_000", 0),
            (string.Empty, 0),
            ("   ", 0)
        };

        foreach (var (value, expected) in cases)
        {
            var actual = WatchCommandKernels.ParsePositiveInt(value);
            Assert.Equal(expected, actual);
        }
    }

    [Fact]
    public void WatchCommandKernels_ClassifiesChangedPathsWithNSharpKernel()
    {
        var cases = new[]
        {
            ("Program.nl", true),
            ("Program.NL", true),
            ("src/Program.nl", true),
            ("src\\Program.nl", true),
            ("project.yml", true),
            ("PROJECT.YML", true),
            ("src/project.yml", true),
            (".editorconfig", true),
            ("src/.editorconfig", true),
            ("src/project.yml.bak", false),
            ("src/.nl", true),
            (".nl", true),
            ("src/Program.cs", false),
            ("src/nested/", false),
            (string.Empty, false)
        };

        foreach (var (path, expected) in cases)
        {
            Assert.Equal(expected, WatchCommandKernels.ShouldTriggerForChangedPath(path));
        }
    }

    [Fact]
    public void RemoveCommandKernels_SummarizesArguments()
    {
        var args = new[] { "--dry-run", "Serilog", "-h" };

        var dogfoodSummary = RemoveCommandKernels.GetArgumentSummary(args);
        Assert.Equal("Serilog", dogfoodSummary.PackageOperand);
        Assert.True(dogfoodSummary.ShowHelp);

        Assert.Equal("Newtonsoft.Json", RemoveCommandKernels.GetArgumentSummary(new[] { "Newtonsoft.Json" }).PackageOperand);
        Assert.Equal("Serilog", RemoveCommandKernels.GetArgumentSummary(new[] { "--dry-run", "Serilog" }).PackageOperand);
        Assert.Null(RemoveCommandKernels.GetArgumentSummary(new[] { "--dry-run" }).PackageOperand);
        Assert.True(RemoveCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);
        Assert.Equal("help", RemoveCommandKernels.GetArgumentSummary(new[] { "help" }).PackageOperand);

        var shorthandVersion = RemoveCommandKernels.GetDependencyLineAction(
            "- Newtonsoft.Json@13.0.3",
            "Newtonsoft.Json");
        Assert.Equal(RemoveDependencyLineAction.RemoveSingleLine, shorthandVersion);

        var shorthandPackage = RemoveCommandKernels.GetDependencyLineAction(
            "  - serilog",
            "Serilog");
        Assert.Equal(RemoveDependencyLineAction.RemoveSingleLine, shorthandPackage);

        var nugetMapping = RemoveCommandKernels.GetDependencyLineAction(
            "- nuget: YamlDotNet",
            "YamlDotNet");
        Assert.Equal(RemoveDependencyLineAction.RemoveMappingBlock, nugetMapping);

        var frameworkMapping = RemoveCommandKernels.GetDependencyLineAction(
            "- framework: Microsoft.AspNetCore.App",
            "Microsoft.AspNetCore.App");
        Assert.Equal(RemoveDependencyLineAction.RemoveMappingBlock, frameworkMapping);

        var keep = RemoveCommandKernels.GetDependencyLineAction(
            "- package: Other",
            "Serilog");
        Assert.Equal(RemoveDependencyLineAction.Keep, keep);

        var stopIndented = RemoveCommandKernels.ShouldStopDependencyContinuationLine("    version: 1.0.0");
        Assert.False(stopIndented);

        var stopNextItem = RemoveCommandKernels.ShouldStopDependencyContinuationLine("- nuget: Other");
        Assert.True(stopNextItem);

        var stopTopLevel = RemoveCommandKernels.ShouldStopDependencyContinuationLine("dependencies:");
        Assert.True(stopTopLevel);

        Assert.Equal(
            RemoveDependencyLineAction.RemoveMappingBlock,
            RemoveCommandKernels.GetDependencyLineAction(" - nuget: YamlDotNet", "YamlDotNet"));
        Assert.False(RemoveCommandKernels.ShouldStopDependencyContinuationLine("  version: 1.0.0"));

        var helpText = RemoveCommandKernels.GetHelpText();
        Assert.Equal("Usage: nlc remove <package>", RemoveCommandKernels.GetUsageMessage());
        Assert.Contains("N# Remove Dependency", helpText);
        Assert.Contains("Failed to remove dependency", helpText);
        Assert.Equal("No project.yml found.", RemoveCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal(
            "Package 'Serilog' not found in dependencies.",
            RemoveCommandKernels.GetPackageNotFoundMessage("Serilog"));
        Assert.Equal("Removed Serilog from project.yml", RemoveCommandKernels.GetRemovedMessage("Serilog"));
    }

    [Fact]
    public void ExportCommandKernels_SelectsInputOperandAfterOrderedOptionStripping()
    {
        var sourceFirst = ExportCommandKernels.GetCSharpInputOperand(
            new[] { "Program.nl", "--output", "Program.cs" });
        Assert.Equal("Program.nl", sourceFirst);

        var outputFirst = ExportCommandKernels.GetCSharpInputOperand(
            new[] { "--output", "dist", "Program.nl" });
        Assert.Equal("Program.nl", outputFirst);

        var shortOutputConsumesLongOutput = ExportCommandKernels.GetCSharpInputOperand(
            new[] { "-o", "--output", "file" });
        Assert.Null(shortOutputConsumesLongOutput);

        var longOutputConsumesProject = ExportCommandKernels.GetCSharpInputOperand(
            new[] { "--output", "--project", "file" });
        Assert.Equal("file", longOutputConsumesProject);
    }

    [Fact]
    public void ExportCommandKernels_SummarizesTargets()
    {
        var empty = ExportCommandKernels.GetTargetSummary(Array.Empty<string>());
        Assert.Equal(ExportTargetKind.Unknown, empty.TargetKind);
        Assert.True(empty.ShowHelp);

        var csharp = ExportCommandKernels.GetTargetSummary(new[] { "CSHARP", "--help" });
        Assert.Equal(ExportTargetKind.CSharp, csharp.TargetKind);
        Assert.False(csharp.ShowHelp);

        var unknown = ExportCommandKernels.GetTargetSummary(new[] { "python", "--help" });
        Assert.Equal(ExportTargetKind.Unknown, unknown.TargetKind);
        Assert.False(unknown.ShowHelp);

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() =>
            ExportCommand.Execute(new[] { "CSHARP", "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage:", helpStdout);
        Assert.Contains("nlc export csharp <file.nl>", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var (unknownExitCode, _, unknownStderr) = CaptureConsole(() =>
            ExportCommand.Execute(new[] { "python", "--help" }));
        Assert.Equal(1, unknownExitCode);
        Assert.Contains("Unknown export target 'python'", unknownStderr);
    }

    [Fact]
    public void ExportCommandKernels_SummarizesCSharpOptions()
    {
        var args = new[] { "-o", "short.cs", "--project", "samples/demo", "--output", "long.cs" };

        var dogfoodSummary = ExportCommandKernels.GetCSharpOptionSummary(args);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.Equal("long.cs", dogfoodSummary.OutputOption);
        Assert.False(dogfoodSummary.ShowHelp);

        var shortOutputOnly = ExportCommandKernels.GetCSharpOptionSummary(new[] { "-o", "short.cs" });
        Assert.Null(shortOutputOnly.ProjectOption);
        Assert.Equal("short.cs", shortOutputOnly.OutputOption);

        var permissiveValue = ExportCommandKernels.GetCSharpOptionSummary(new[] { "--project", "--output", "--output", "--help" });
        Assert.Equal("--output", permissiveValue.ProjectOption);
        Assert.Equal("--output", permissiveValue.OutputOption);
        Assert.True(permissiveValue.ShowHelp);

        Assert.True(ExportCommandKernels.GetCSharpOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(ExportCommandKernels.GetCSharpOptionSummary(new[] { "ignored", "-h" }).ShowHelp);
    }

    [Theory]
    [InlineData("src/Program.tests.nl", true)]
    [InlineData("src/Program.TESTS.NL", true)]
    [InlineData("src/Contest.nl", false)]
    [InlineData("src/Program.tests.nls", false)]
    public void ExportCommandKernels_ClassifiesTestSourceFiles(string sourceFile, bool expected)
    {
        var dogfoodIsTestSource = ExportCommandKernels.IsTestSourceFile(sourceFile);
        Assert.Equal(expected, dogfoodIsTestSource);
    }

    [Fact]
    public void ExportCommandKernels_ShapesMessages()
    {
        var helpText = ExportCommandKernels.GetHelpText();
        Assert.Contains("N# Export", helpText);
        Assert.Contains("Usage: nlc export <target> [options]", helpText);

        var csharpHelpText = ExportCommandKernels.GetCSharpHelpText();
        Assert.Contains("N# Export C#", csharpHelpText);
        Assert.Contains("self-contained C# bundle", csharpHelpText);

        Assert.Equal(
            "Unknown export target 'python'. Expected 'csharp'.",
            ExportCommandKernels.GetUnknownTargetMessage("python"));
        Assert.Equal(
            "Specify either a source path or --project, not both.",
            ExportCommandKernels.GetSourceAndProjectConflictMessage());
        Assert.Equal("Path not found: missing.nl", ExportCommandKernels.GetPathNotFoundMessage("missing.nl"));
        Assert.Equal(
            "No input provided. Pass a .nl file or project directory, or run from a directory containing project.yml.",
            ExportCommandKernels.GetNoInputMessage());
        Assert.Equal("Export failed: boom", ExportCommandKernels.GetFailedMessage("boom"));
        Assert.Equal(
            "Expected an .nl file, got: README.md",
            ExportCommandKernels.GetExpectedNlFileMessage("README.md"));
        Assert.Equal(
            "The export pipeline did not produce output for Program.nl.",
            ExportCommandKernels.GetMissingOutputMessage("Program.nl"));
        Assert.Equal(
            "Refusing to overwrite the source .nl file. Choose a different output path.",
            ExportCommandKernels.GetRefuseOverwriteMessage());
        Assert.Equal(
            "Exported Program.nl to /tmp/Program.cs",
            ExportCommandKernels.GetSingleFileSuccessMessage("Program.nl", "/tmp/Program.cs"));
        Assert.Equal(
            "No project.yml found in /tmp/demo.",
            ExportCommandKernels.GetNoProjectFileMessage("/tmp/demo"));
        Assert.Equal(
            "Exported Demo to /tmp/Demo.csproj",
            ExportCommandKernels.GetProjectSuccessMessage("Demo", "/tmp/Demo.csproj"));
        Assert.Equal(
            "Exported tests to /tmp/Demo.Tests.csproj",
            ExportCommandKernels.GetTestsSuccessMessage("/tmp/Demo.Tests.csproj"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() =>
            ExportCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("N# Export", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var (unknownExitCode, _, unknownStderr) = CaptureConsole(() =>
            ExportCommand.Execute(new[] { "python" }));
        Assert.Equal(1, unknownExitCode);
        Assert.Equal(
            ProgramCommandKernels.GetErrorLine(ExportCommandKernels.GetUnknownTargetMessage("python")) + Environment.NewLine,
            unknownStderr);
    }

    [Fact]
    public void ExportCommandKernels_ShapesCSharpProjectFiles()
    {
        var mainProject = ExportCommandKernels.GetCSharpMainProjectFileText(
            "Microsoft.NET.Sdk.Web",
            "net10.0",
            "Library",
            "Demo&Lib",
            "1.2.3",
            "A&B",
            "D<C>",
            "alpha beta",
            2,
            "MIT",
            "https://example.invalid/repo?a=1&b=2",
            "icon&<.png",
            1,
            new[] { "Serilog", "Analyzer", "Loose" },
            new[] { "3.1.0", "1.0.0", "" },
            new[] { 0, 1, 0 },
            new[] { "", "runtime; build", "" },
            new[] { "Microsoft.AspNetCore.App" },
            new[] { "../Shared/Shared.csproj" },
            new[] { "Custom&Ref" },
            new[] { "lib/custom&ref.dll" });

        Assert.StartsWith("<Project Sdk=\"Microsoft.NET.Sdk.Web\">\n", mainProject, StringComparison.Ordinal);
        Assert.Contains("<AssemblyName>Demo&amp;Lib</AssemblyName>", mainProject);
        Assert.Contains("<Authors>A&amp;B</Authors>", mainProject);
        Assert.Contains("<Description>D&lt;C&gt;</Description>", mainProject);
        Assert.Contains("<RepositoryUrl>https://example.invalid/repo?a=1&amp;b=2</RepositoryUrl>", mainProject);
        Assert.Contains("<PackageIcon>icon&amp;&lt;.png</PackageIcon>", mainProject);
        Assert.Contains("    <PackageReference Include=\"Serilog\" Version=\"3.1.0\" />\n", mainProject);
        Assert.Contains(
            "    <PackageReference Include=\"Analyzer\" Version=\"1.0.0\">\n"
            + "      <PrivateAssets>all</PrivateAssets>\n"
            + "      <IncludeAssets>runtime; build</IncludeAssets>\n"
            + "    </PackageReference>\n",
            mainProject);
        Assert.Contains("    <PackageReference Include=\"Loose\" />\n", mainProject);
        Assert.Contains("    <FrameworkReference Include=\"Microsoft.AspNetCore.App\" />\n", mainProject);
        Assert.Contains("    <ProjectReference Include=\"../Shared/Shared.csproj\" />\n", mainProject);
        Assert.Contains("    <Reference Include=\"Custom&amp;Ref\">\n      <HintPath>lib/custom&amp;ref.dll</HintPath>\n", mainProject);
        Assert.EndsWith("</Project>\n", mainProject, StringComparison.Ordinal);

        var testProject = ExportCommandKernels.GetCSharpTestProjectFileText(
            "net10.0",
            new[] { "xunit.runner.visualstudio" },
            new[] { "2.8.2" },
            new[] { 1 },
            new[] { "runtime; build; native; contentfiles; analyzers; buildtransitive" },
            Array.Empty<string>(),
            new[] { "../Demo/Demo.csproj" },
            Array.Empty<string>(),
            Array.Empty<string>());

        Assert.StartsWith("<Project Sdk=\"Microsoft.NET.Sdk\">\n", testProject, StringComparison.Ordinal);
        Assert.Contains("<IsTestProject>true</IsTestProject>", testProject);
        Assert.Contains("<ProjectReference Include=\"../Demo/Demo.csproj\" />", testProject);
        Assert.DoesNotContain("<AssemblyName>", testProject, StringComparison.Ordinal);
    }

    [Fact]
    public void BuildCommandKernels_SelectsFirstOperandAfterOptionStripping()
    {
        var empty = BuildCommandKernels.GetOperandSummary(Array.Empty<string>());
        Assert.Equal(0, empty.Count);
        Assert.Equal(-1, empty.FirstOperandIndex);

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

        var summary = BuildCommandKernels.GetOperandSummary(args);
        Assert.Equal(1, summary.Count);
        Assert.Equal(8, summary.FirstOperandIndex);
        Assert.Equal("Program.nl", args[summary.FirstOperandIndex]);

        var sourceFirst = BuildCommandKernels.GetOperandSummary(new[] { "Main.nl", "--backend", "il" });
        Assert.Equal(1, sourceFirst.Count);
        Assert.Equal(0, sourceFirst.FirstOperandIndex);

        var multiSource = BuildCommandKernels.GetOperandSummary(new[] { "Main.nl", "--backend", "il", "Extra.nl" });
        Assert.Equal(2, multiSource.Count);
        Assert.Equal(0, multiSource.FirstOperandIndex);
    }

    [Fact]
    public void DefineArgumentKernels_ExtractsDefinesAndRemainingArgs()
    {
        var args = new[]
        {
            "--define",
            "FEATURE, EXTRA ; FEATURE",
            "--backend",
            "il",
            "-d=TRACE",
            "Program.nl",
            "--define=",
            "-d",
            "  LAST  ",
            "--define"
        };

        var extraction = DefineArgumentKernels.Extract(args);
        Assert.Equal(new[] { "FEATURE", "EXTRA", "TRACE", "LAST" }, extraction.Defines);
        Assert.Equal(new[] { "--backend", "il", "Program.nl" }, extraction.RemainingArgs);
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

        var summary = BuildCommandKernels.GetOptionSummary(args);
        Assert.Equal("dist", summary.OutputDir);
        Assert.Equal("il", summary.BackendOption);
        Assert.Equal("samples/demo", summary.ProjectOption);
        Assert.True(summary.Release);
        Assert.True(summary.Verbose);
        Assert.True(summary.Timings);
        Assert.True(summary.PerfReport);
        Assert.True(summary.Aot);
        Assert.False(summary.ShowHelp);

        var firstArgHelp = BuildCommandKernels.GetOptionSummary(new[] { "help", "--release" });
        Assert.True(firstArgHelp.ShowHelp);

        var helpAsMissingValue = BuildCommandKernels.GetOptionSummary(new[] { "--output", "--help" });
        Assert.Equal("--help", helpAsMissingValue.OutputDir);
        Assert.True(helpAsMissingValue.ShowHelp);

        var helpText = BuildCommandKernels.GetHelpText();
        Assert.Contains("N# Build", helpText);
        Assert.Contains("Usage: nlc build [file.nl] [options]", helpText);
        Assert.Contains("Build failed", helpText);
        Assert.Equal("File not found: Missing.nl", BuildCommandKernels.GetFileNotFoundMessage("Missing.nl"));
        Assert.Equal("Build failed: backend exploded", BuildCommandKernels.GetFailedMessage("backend exploded"));
        Assert.Equal(
            "Building project in /tmp/demo with the IL backend...",
            BuildCommandKernels.GetProjectStartMessage("/tmp/demo"));
        Assert.Equal(
            "Building Program.nl with the IL backend...",
            BuildCommandKernels.GetSingleFileStartMessage("Program.nl"));
        Assert.Equal(
            "No project.yml found in current directory. Run 'nlc new <name>' to create a project, or use 'nlc build <file.nl>' for a single file.",
            BuildCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal("  Build failed in 12 ms", BuildCommandKernels.GetFailedElapsedMessage("12 ms"));
        Assert.Equal("Build successful! (il, debug) [12 ms]", BuildCommandKernels.GetSuccessElapsedMessage(release: false, "12 ms"));
        Assert.Equal("Build successful! (il, release) [12 ms]", BuildCommandKernels.GetSuccessElapsedMessage(release: true, "12 ms"));
        Assert.Equal("Build successful! (il, debug)", BuildCommandKernels.GetSuccessMessage(release: false));
        Assert.Equal("Build successful! (il, release)", BuildCommandKernels.GetSuccessMessage(release: true));
        Assert.Equal("Output: /tmp/demo/bin/App.dll", BuildCommandKernels.GetOutputPathMessage("/tmp/demo/bin/App.dll"));
        Assert.Equal(
            "Build timings:\n  Resolve:    1 ms\n  Emit IL:    2 ms\n  Total:      3 ms",
            BuildCommandKernels.GetTimingsMessage("1 ms", "2 ms", "3 ms"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => ExecuteProgram("build", "--help"));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage: nlc build [file.nl] [options]", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var missingPath = Path.Combine(Path.GetTempPath(), $"missing-{Guid.NewGuid():N}.nl");
        var (missingExitCode, missingStdout, missingStderr) = CaptureConsole(() => ExecuteProgram("build", missingPath));
        Assert.Equal(1, missingExitCode);
        Assert.True(string.IsNullOrWhiteSpace(missingStdout));
        Assert.Contains($"File not found: {missingPath}", missingStderr);
    }

    [Fact]
    public void RunCommandKernels_SelectsSourceOperandAfterBackendStripping()
    {
        var empty = RunCommandKernels.GetSourceOperand(Array.Empty<string>());
        Assert.Null(empty);

        var projectRun = RunCommandKernels.GetSourceOperand(new[] { "--backend", "il" });
        Assert.Null(projectRun);

        var backendFirst = RunCommandKernels.GetSourceOperand(new[] { "--backend", "il", "Program.nl" });
        Assert.Equal("Program.nl", backendFirst);

        var sourceFirst = RunCommandKernels.GetSourceOperand(new[] { "Program.nl", "--backend", "il" });
        Assert.Equal("Program.nl", sourceFirst);

        var danglingBackend = RunCommandKernels.GetSourceOperand(new[] { "--backend" });
        Assert.Equal("--backend", danglingBackend);

        Assert.Equal(
            "Program.nl",
            RunCommandKernels.GetSourceOperand(new[] { "--backend", "--unknown", "Program.nl" }));
    }

    [Fact]
    public void RunCommandKernels_SummarizesOptions()
    {
        var empty = RunCommandKernels.GetOptionSummary(Array.Empty<string>());
        Assert.Null(empty.BackendOption);
        Assert.False(empty.ShowHelp);

        var backend = RunCommandKernels.GetOptionSummary(new[] { "--backend", "il", "Program.nl" });
        Assert.Equal("il", backend.BackendOption);
        Assert.False(backend.ShowHelp);

        var help = RunCommandKernels.GetOptionSummary(new[] { "help" });
        Assert.True(help.ShowHelp);

        var permissive = RunCommandKernels.GetOptionSummary(new[] { "--backend", "--help" });
        Assert.Equal("--help", permissive.BackendOption);
        Assert.True(permissive.ShowHelp);

        Assert.True(RunCommandKernels.GetOptionSummary(new[] { "-h" }).ShowHelp);
        Assert.Null(RunCommandKernels.GetOptionSummary(new[] { "--backend" }).BackendOption);

        var helpText = RunCommandKernels.GetHelpText();
        Assert.Contains("N# Run", helpText);
        Assert.Contains("Usage: nlc run [file.nl]", helpText);
        Assert.Contains("Build or execution failed", helpText);
        Assert.Equal("File not found: Missing.nl", RunCommandKernels.GetFileNotFoundMessage("Missing.nl"));
        Assert.Equal("Running Program.nl...", RunCommandKernels.GetSourceStartingMessage("Program.nl"));
        Assert.Equal(
            "No project.yml found in current directory. Run 'nlc new <name>' to create a project.",
            RunCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal("Cannot run a library project.", RunCommandKernels.GetLibraryProjectMessage());
        Assert.Equal("Running...", RunCommandKernels.GetProjectStartingMessage());
        Assert.Equal(
            "Running Program.nl with the IL backend...",
            RunCommandKernels.GetSingleFileBackendStartMessage("Program.nl"));
        Assert.Equal("Cannot run a library source file.", RunCommandKernels.GetLibrarySourceFileMessage());
        Assert.Equal("Run failed: backend exploded", RunCommandKernels.GetFailedMessage("backend exploded"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => ExecuteProgram("run", "--help"));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage: nlc run [file.nl]", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var missingPath = Path.Combine(Path.GetTempPath(), $"missing-{Guid.NewGuid():N}.nl");
        var (missingExitCode, missingStdout, missingStderr) = CaptureConsole(() => ExecuteProgram("run", missingPath));
        Assert.Equal(1, missingExitCode);
        Assert.True(string.IsNullOrWhiteSpace(missingStdout));
        Assert.Contains($"File not found: {missingPath}", missingStderr);

        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-run-no-project-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var (noProjectExitCode, noProjectStdout, noProjectStderr) = CaptureConsole(() =>
                ExecuteRunWithIlBackend(tempDir));
            Assert.Equal(1, noProjectExitCode);
            Assert.True(string.IsNullOrWhiteSpace(noProjectStdout));
            Assert.Contains("No project.yml found in current directory.", noProjectStderr);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void PublishCommandKernels_NormalizesOptionsAndValidation()
    {
        var defaultSummary = PublishCommandKernels.GetArgumentSummary(Array.Empty<string>());
        Assert.Null(defaultSummary.ValidationError);
        Assert.Null(defaultSummary.ProjectOption);
        Assert.Null(defaultSummary.BackendOption);
        Assert.Equal("Release", defaultSummary.Configuration);
        Assert.Null(defaultSummary.Output);
        Assert.Null(defaultSummary.Runtime);
        Assert.False(defaultSummary.SelfContained);
        Assert.False(defaultSummary.Aot);
        Assert.False(defaultSummary.ShowHelp);

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

        var dogfoodSummary = PublishCommandKernels.GetArgumentSummary(args);
        Assert.Null(dogfoodSummary.ValidationError);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.Equal("il", dogfoodSummary.BackendOption);
        Assert.Equal("Release", dogfoodSummary.Configuration);
        Assert.Equal("dist", dogfoodSummary.Output);
        Assert.Equal("osx-arm64", dogfoodSummary.Runtime);
        Assert.True(dogfoodSummary.SelfContained);
        Assert.True(dogfoodSummary.Aot);
        Assert.False(dogfoodSummary.ShowHelp);

        var missingValue = PublishCommandKernels.GetArgumentSummary(new[] { "--project", "--backend", "il" });
        Assert.Equal("Option '--project' requires a value.", missingValue.ValidationError);

        var targetPlatform = PublishCommandKernels.GetArgumentSummary(new[] { "--target", "linux-x64" });
        Assert.Equal(
            "Target-platform publishing is expressed as --runtime <rid>, and nlc publish does not support cross-runtime publishing yet.",
            targetPlatform.ValidationError);

        var unknown = PublishCommandKernels.GetArgumentSummary(new[] { "--mystery" });
        Assert.Equal("Unknown publish option '--mystery'. Run 'nlc publish --help' for supported options.", unknown.ValidationError);

        var unexpected = PublishCommandKernels.GetArgumentSummary(new[] { "Project.nl" });
        Assert.Equal("Unexpected publish argument 'Project.nl'. Run 'nlc publish --help' for usage.", unexpected.ValidationError);

        Assert.Equal(
            "nlc publish --aot is analysis-only in this release: it verifies your project is Native AOT-safe " +
            "(failing on any AOT blocker) and stamps [RequiresUnreferencedCode]/[RequiresDynamicCode] on public APIs, " +
            "but it does NOT produce a native image yet. The output is the usual framework-dependent assembly.",
            PublishCommandKernels.GetAotAnalysisOnlyNotice());
        Assert.Equal(
            "Self-contained publish is not available in nlc publish yet. " +
            "Today nlc publish produces framework-dependent artifacts. " +
            "Omit --self-contained, or use dotnet publish with an MSBuild compatibility project when you need a true apphost/self-contained bundle.",
            PublishCommandKernels.GetSelfContainedUnsupportedMessage());
        Assert.Equal(
            "Cross-runtime publish is not available in nlc publish yet. Requested runtime 'linux-x64', but this machine is 'osx-arm64'. " +
            "Today --runtime only supports the current host runtime to add a framework-dependent launcher. " +
            "Omit --runtime for portable 'dotnet <app>.dll' output, or run nlc publish on the target runtime.",
            PublishCommandKernels.GetCrossRuntimeUnsupportedMessage("linux-x64", "osx-arm64"));
        Assert.Equal("Publish failed", PublishCommandKernels.GetBuildFailureMessage(aotMode: false));
        Assert.Equal(
            "Publish failed: Native AOT blockers were found (see the diagnostics above). Fix them, then publish again.",
            PublishCommandKernels.GetBuildFailureMessage(aotMode: true));
        Assert.Equal("Publish failed: backend exploded", PublishCommandKernels.GetExceptionFailureMessage("backend exploded"));
        Assert.Equal("Publishing project in /tmp/demo...", PublishCommandKernels.GetStartMessage("/tmp/demo"));
        Assert.Equal(
            "No project.yml found in current directory. Run 'nlc new <name>' to create a project.",
            PublishCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal("Publish successful!", PublishCommandKernels.GetSuccessMessage());
        var expectedHelpText = """
N# Publish

Usage: nlc publish [options]

Package the project for distribution.

Options:
  --project <dir>         Project root directory (default: current directory)
  --backend <mode>        Compilation backend: il
  --configuration <cfg>   Build configuration (default: Release)
  --output <dir>          Output directory for published files
  --runtime <rid>         Current host runtime only; adds a framework-dependent launcher
  --self-contained        Planned; currently exits with guidance
  --aot                   Analysis-only: verify Native AOT safety and annotate public APIs
  --help, -h              Show this help text

Supported publish shapes:
  - Portable framework-dependent: nlc publish --output ./dist
  - Current-runtime launcher: nlc publish --runtime <current-rid>

Native AOT (--aot):
  Analysis-only this release. Fails the publish on any AOT blocker (reflection,
  dynamic code, runtime generics, expression trees) and stamps public APIs with
  [RequiresUnreferencedCode]/[RequiresDynamicCode]. It does NOT emit a native image yet.

Unsupported today:
  - Cross-runtime publishing, e.g. publishing linux-x64 from osx-arm64
  - Self-contained apphost/runtime bundles
  - Native AOT image generation

Examples:
  nlc publish
  nlc publish --backend il --output ./dist
  nlc publish --configuration Release
  nlc publish --runtime <current-rid> --output ./dist
  nlc publish --aot
  nlc publish --output ./dist

Exit codes:
  0  Publish succeeded
  1  Publish failed
""";
        var helpText = PublishCommandKernels.GetHelpText();
        Assert.Equal(expectedHelpText, helpText);

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => ExecuteProgram("publish", "--help"));
        Assert.Equal(0, helpExitCode);
        Assert.Equal(helpText + Environment.NewLine, helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        Assert.Equal(
            "Debug",
            PublishCommandKernels.GetArgumentSummary(new[] { "-c", "Debug" }).Configuration);

        Assert.True(PublishCommandKernels.GetArgumentSummary(new[] { "help" }).ShowHelp);
        Assert.True(PublishCommandKernels.GetArgumentSummary(new[] { "--help" }).ShowHelp);
        Assert.True(PublishCommandKernels.GetArgumentSummary(new[] { "ignored", "-h" }).ShowHelp);

        var helpAfterInvalidValue = PublishCommandKernels.GetArgumentSummary(new[] { "--project", "--help" });
        Assert.True(helpAfterInvalidValue.ShowHelp);
        Assert.Equal("Option '--project' requires a value.", helpAfterInvalidValue.ValidationError);
    }

    [Fact]
    public void PackCommandKernels_SummarizesOptions()
    {
        var defaultSummary = PackCommandKernels.GetOptionSummary(Array.Empty<string>());
        Assert.Null(defaultSummary.ProjectOption);
        Assert.Null(defaultSummary.OutputDir);
        Assert.Null(defaultSummary.VersionOverride);
        Assert.Equal("Release", defaultSummary.Configuration);
        Assert.False(defaultSummary.IncludeSymbols);
        Assert.False(defaultSummary.JsonOutput);
        Assert.False(defaultSummary.ShowHelp);

        var args = new[]
        {
            "-c", "Debug",
            "--output", "dist",
            "--version", "2.0.0-beta.1",
            "--include-symbols",
            "--json",
            "--project", "samples/demo",
            "--configuration", "Release",
            "-o", "ignored-output"
        };

        var dogfoodSummary = PackCommandKernels.GetOptionSummary(args);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.Equal("dist", dogfoodSummary.OutputDir);
        Assert.Equal("2.0.0-beta.1", dogfoodSummary.VersionOverride);
        Assert.Equal("Release", dogfoodSummary.Configuration);
        Assert.True(dogfoodSummary.IncludeSymbols);
        Assert.True(dogfoodSummary.JsonOutput);
        Assert.False(dogfoodSummary.ShowHelp);

        var permissiveValue = PackCommandKernels.GetOptionSummary(new[] { "--project", "--json" });
        Assert.Equal("--json", permissiveValue.ProjectOption);
        Assert.True(permissiveValue.JsonOutput);

        Assert.True(PackCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(PackCommandKernels.GetOptionSummary(new[] { "ignored", "-h" }).ShowHelp);

        var textMode = PackCommandKernels.GetOutputMode(json: false);
        Assert.Equal(PackOutputModeKind.Text, textMode);

        var jsonMode = PackCommandKernels.GetOutputMode(json: true);
        Assert.Equal(PackOutputModeKind.Json, jsonMode);

        var helpText = PackCommandKernels.GetHelpText();
        Assert.Contains("N# Pack", helpText);
        Assert.Contains("Usage: nlc pack [options]", helpText);
        Assert.Contains("Pack failed", helpText);

        Assert.Equal(
            "No project.yml found. Run 'nlc new <name>' to create a project.",
            PackCommandKernels.GetMissingProjectFileJsonMessage());
        Assert.Equal(
            "No project.yml found in current directory.\nRun 'nlc new <name>' to create a project.",
            PackCommandKernels.GetMissingProjectFileTextMessage());
        Assert.Equal(
            "Failed to parse project.yml: bad yaml",
            PackCommandKernels.GetParseFailedJsonMessage("bad yaml"));
        Assert.Equal(
            "Failed to parse project.yml: bad yaml",
            PackCommandKernels.GetParseFailedTextMessage("bad yaml"));
        Assert.Equal("Packing Demo 1.2.3...", PackCommandKernels.GetStartMessage("Demo", "1.2.3"));
        Assert.Equal("Packing Demo (no version)...", PackCommandKernels.GetStartMessage("Demo", null));
        Assert.Equal("Packing Demo ...", PackCommandKernels.GetStartMessage("Demo", string.Empty));
        Assert.Equal(
            "Package version is required. Set version in project.yml or pass --version.",
            PackCommandKernels.GetMissingVersionJsonMessage());
        Assert.Equal(
            "Package version is required. Set version in project.yml or pass --version.",
            PackCommandKernels.GetMissingVersionTextMessage());
        Assert.Equal("Pack build failed.", PackCommandKernels.GetBuildFailedJsonMessage());
        Assert.Equal("Pack build failed.", PackCommandKernels.GetBuildFailedTextMessage());
        Assert.Equal("Pack successful!", PackCommandKernels.GetSuccessMessage());
        Assert.Equal("  Package: /tmp/pkg/Demo.1.2.3.nupkg", PackCommandKernels.GetPackagePathLine("/tmp/pkg/Demo.1.2.3.nupkg"));
        Assert.Equal("Pack failed: zip exploded", PackCommandKernels.GetFailedJsonMessage("zip exploded"));
        Assert.Equal("Pack failed: zip exploded", PackCommandKernels.GetFailedTextMessage("zip exploded"));

        var nuspec = PackCommandKernels.GetNuspecText(
            "Demo&Lib",
            "1.2.3",
            "A&B",
            "D<C>",
            "alpha beta",
            2,
            "MIT",
            "https://example.invalid/repo?a=1&b=2",
            "icon&<.png");
        Assert.Contains("<id>Demo&amp;Lib</id>", nuspec);
        Assert.Contains("<authors>A&amp;B</authors>", nuspec);
        Assert.Contains("<description>D&lt;C&gt;</description>", nuspec);
        Assert.Contains("<tags>alpha beta</tags>", nuspec);
        Assert.Contains("<repository type=\"git\" url=\"https://example.invalid/repo?a=1&amp;b=2\" />", nuspec);
        Assert.Contains("<icon>icon&amp;&lt;.png</icon>", nuspec);

        var defaultedNuspec = PackCommandKernels.GetNuspecText(
            "Demo",
            "1.2.3",
            "",
            "",
            "",
            0,
            "",
            "",
            "");
        Assert.Contains("<authors>NSharp</authors>", defaultedNuspec);
        Assert.Contains("<description>Demo N# package</description>", defaultedNuspec);
        Assert.DoesNotContain("<tags>", defaultedNuspec, StringComparison.Ordinal);

        var symbolsNuspec = PackCommandKernels.GetSymbolsNuspecText("Demo&Lib", "1.2.3");
        Assert.Contains("<id>Demo&amp;Lib</id>", symbolsNuspec);
        Assert.Contains("<description>Symbols for Demo&amp;Lib.</description>", symbolsNuspec);

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => PackCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage: nlc pack [options]", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
    }

    [Fact]
    public void PackCommandKernels_SelectsEffectiveVersionSource()
    {
        var missing = PackCommandKernels.GetEffectiveVersionSource(null, null);
        Assert.Equal(PackVersionSourceKind.Missing, missing);

        var fromOverride = PackCommandKernels.GetEffectiveVersionSource("2.0.0", "1.0.0");
        Assert.Equal(PackVersionSourceKind.Override, fromOverride);

        var blankOverride = PackCommandKernels.GetEffectiveVersionSource(" ", "1.0.0");
        Assert.Equal(PackVersionSourceKind.Missing, blankOverride);

        var fromProject = PackCommandKernels.GetEffectiveVersionSource(null, "1.0.0");
        Assert.Equal(PackVersionSourceKind.Project, fromProject);

        var blankProject = PackCommandKernels.GetEffectiveVersionSource(null, " ");
        Assert.Equal(PackVersionSourceKind.Missing, blankProject);
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

        var packageReferences = ExportCommandKernels.FilterReferencesByType(
            references,
            ReferenceType.NuGet);
        Assert.Equal(new[] { "Serilog", "YamlDotNet" }, packageReferences.Select(reference => reference.Nuget).ToArray());

        var frameworkReferences = ExportCommandKernels.FilterReferencesByType(
            references,
            ReferenceType.Framework);
        Assert.Equal(new[] { "Microsoft.AspNetCore.App", "Microsoft.WindowsDesktop.App" }, frameworkReferences.Select(reference => reference.Framework).ToArray());

        var dllReferences = ExportCommandKernels.FilterReferencesByType(
            references,
            ReferenceType.Dll);
        Assert.Equal(new[] { "lib/Analyzer.dll" }, dllReferences.Select(reference => reference.Dll).ToArray());

        var projectReferences = ExportCommandKernels.FilterReferencesByType(
            references,
            ReferenceType.Project);
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

        var distinctProjectReferences = ExportCommandKernels.DeduplicateReferences(
            projectReferences,
            StringComparer.OrdinalIgnoreCase);
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

        var distinctPackageReferences = ExportCommandKernels.DeduplicateReferences(
            packageReferences,
            comparer: null);
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

        var dogfoodReferences = RestoreCommandKernels.DeduplicateProjectReferences(projectReferences);
        Assert.Equal(new[]
        {
            "../Shared/Shared.csproj",
            "../Models/Models.csproj",
            "../Utilities/Utilities.csproj"
        }, dogfoodReferences);
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

        var projectReferences = RestoreCommandKernels.FilterReferencesByType(
            references,
            ReferenceType.Project);
        Assert.Equal(
            new[] { "../Shared/project.yml", "../Models/project.yml" },
            projectReferences.Select(reference => reference.Project).ToArray());
    }

    [Fact]
    public void RestoreCommandKernels_SummarizesOptions()
    {
        var longHelp = RestoreCommandKernels.GetOptionSummary(new[] { "--help" });
        Assert.True(longHelp.ShowHelp);

        var shortHelp = RestoreCommandKernels.GetOptionSummary(new[] { "-h" });
        Assert.True(shortHelp.ShowHelp);

        Assert.False(RestoreCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.False(RestoreCommandKernels.GetOptionSummary(Array.Empty<string>()).ShowHelp);

        var helpText = RestoreCommandKernels.GetHelpText();
        Assert.Contains("N# Restore", helpText);
        Assert.Contains("Usage: nlc restore", helpText);
        Assert.Contains("obj/project.g.props", helpText);
        Assert.Equal(
            "No project.yml found. Run 'nlc new <name>' to create a project.",
            RestoreCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal(
            "Generated obj/project.g.props from project.yml",
            RestoreCommandKernels.GetGeneratedPropsMessage());
        Assert.Equal(
            "Failed to restore project configuration: bad YAML",
            RestoreCommandKernels.GetFailedMessage("bad YAML"));

        var propsWithoutReferences = RestoreCommandKernels.GetGeneratedPropsText(
            "net10.0",
            "Exe",
            "Demo",
            "il",
            "xunit",
            "Microsoft.NET.Sdk",
            Array.Empty<string>());
        Assert.Equal(
            "<Project xmlns=\"http://schemas.microsoft.com/developer/msbuild/2003\">\n"
            + "  <PropertyGroup>\n"
            + "    <TargetFramework>net10.0</TargetFramework>\n"
            + "    <OutputType>Exe</OutputType>\n"
            + "    <_NSharpOriginalOutputType>Exe</_NSharpOriginalOutputType>\n"
            + "    <AssemblyName>Demo</AssemblyName>\n"
            + "    <NSharpCompilationBackend>il</NSharpCompilationBackend>\n"
            + "    <NSharpTestFramework>xunit</NSharpTestFramework>\n"
            + "    <_NSharpBaseSdk>Microsoft.NET.Sdk</_NSharpBaseSdk>\n"
            + "  </PropertyGroup>\n"
            + "</Project>\n",
            propsWithoutReferences);
        Assert.DoesNotContain("<ItemGroup>", propsWithoutReferences, StringComparison.Ordinal);

        var propsWithReferences = RestoreCommandKernels.GetGeneratedPropsText(
            "net10.0",
            "Library",
            "Shared",
            "il",
            "nunit",
            "Microsoft.NET.Sdk.Web",
            new[] { "../Shared/Shared.csproj", "/tmp/a&b<c>d\"e.csproj" });
        Assert.Contains("    <ProjectReference Include=\"../Shared/Shared.csproj\" />\n", propsWithReferences);
        Assert.Contains("    <ProjectReference Include=\"/tmp/a&amp;b&lt;c&gt;d&quot;e.csproj\" />\n", propsWithReferences);
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

        var packageReferences = CompilationReferenceResolverKernels.FilterReferencesByType(
            references,
            ReferenceType.NuGet);
        Assert.Equal(new[] { "Serilog", "YamlDotNet" }, packageReferences.Select(reference => reference.Nuget).ToArray());
    }

    [Fact]
    public void CompilationReferenceResolverKernels_SelectsFirstHighestCompatibleScore()
    {
        var scores = new[] { -1, 40, 900, 120, 900, 30 };

        var bestIndex = CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, scores.Length);
        Assert.Equal(2, bestIndex);

        var noMatchIndex = CompilationReferenceResolverKernels.SelectBestScoreIndex(new[] { -1, -1 }, 2);
        Assert.Equal(-1, noMatchIndex);

        var emptyIndex = CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, 0);
        Assert.Equal(-1, emptyIndex);

        Assert.Throws<ArgumentOutOfRangeException>(() =>
            CompilationReferenceResolverKernels.SelectBestScoreIndex(scores, scores.Length + 1));
    }

    [Fact]
    public void CompilationReferenceResolverKernels_SelectsSharedFrameworkCandidate()
    {
        var versions = new[]
        {
            Version.Parse("8.0.12"),
            Version.Parse("10.0.0"),
            Version.Parse("10.0.3"),
            Version.Parse("9.1.0"),
            Version.Parse("10.0.3.1")
        };

        AssertSelected(versions, 10, 4);
        AssertSelected(versions, 9, 3);
        AssertSelected(versions, 7, 4);
        AssertSelected(versions, null, 4);
        AssertSelected(Array.Empty<Version>(), 10, -1);

        static void AssertSelected(Version[] versions, int? targetMajor, int expectedIndex)
        {
            var selectedIndex = CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(
                versions,
                targetMajor);
            Assert.Equal(expectedIndex, selectedIndex);
        }
    }

    [Fact]
    public void CompilationReferenceResolverKernels_SelectsLatestNuGetVersion()
    {
        AssertSelected(new[] { "1.0.0", "1.1.0-beta", "1.1.0" }, 2);
        AssertSelected(new[] { "1.0.0", "2.0.0-preview", "1.9.0" }, 2);
        AssertSelected(new[] { "2.0.0-alpha", "2.0.0-beta" }, 1);
        AssertSelected(new[] { "1.0.0" }, 0);
        AssertSelected(Array.Empty<string>(), -1);

        static void AssertSelected(string[] versions, int expectedIndex)
        {
            var selectedIndex = CompilationReferenceResolverKernels.SelectLatestNuGetVersionIndex(versions);
            Assert.Equal(expectedIndex, selectedIndex);
        }
    }

    [Fact]
    public void CompilationReferenceResolverKernels_SelectsBestNuGetVersion()
    {
        AssertSelected(new[] { "1.0.0", "2.0.0", "1.9.9" }, 1);
        AssertSelected(new[] { "1.2", "1.2.1", "1.2.0" }, 1);
        AssertSelected(new[] { "1.0.0", "1.0.0-preview" }, 1);
        AssertSelected(new[] { "2.0.0-alpha", "2.0.0" }, 0);
        AssertSelected(new[] { "bad", "1.0.0" }, 0);
        AssertSelected(Array.Empty<string>(), -1);

        static void AssertSelected(string[] versions, int expectedIndex)
        {
            var selectedIndex = CompilationReferenceResolverKernels.SelectBestNuGetVersionIndex(versions);
            Assert.Equal(expectedIndex, selectedIndex);
        }
    }

    [Theory]
    [InlineData("/tmp/project/bin/Debug/net10.0/App.dll", '/', "ref", false)]
    [InlineData("/tmp/project/bin/Debug/net10.0/ref/App.dll", '/', "ref", true)]
    [InlineData("/tmp/project/bin/Debug/net10.0/REF/App.dll", '/', "ref", true)]
    [InlineData("/tmp/project/bin/Debug/net10.0/reference/App.dll", '/', "ref", false)]
    [InlineData("ref/App.dll", '/', "ref", true)]
    [InlineData("lib/ref", '/', "ref", true)]
    [InlineData("lib//ref/App.dll", '/', "ref", true)]
    [InlineData("lib/ref2/App.dll", '/', "ref", false)]
    [InlineData(@"lib\ref\App.dll", '/', "ref", false)]
    [InlineData(@"lib\ref\App.dll", '\\', "ref", true)]
    public void CompilationReferenceResolverKernels_DetectsPathSegments(
        string path,
        char separator,
        string segment,
        bool expected)
    {
        var hasSegment = CompilationReferenceResolverKernels.PathHasSegmentIgnoreCase(
            path,
            separator,
            segment);
        Assert.Equal(expected, hasSegment);
    }

    [Fact]
    public void CompilationReferenceResolverKernels_ShapesCSharpProjectReferenceMessages()
    {
        Assert.Equal(
            "Building C# project reference /tmp/Demo/Demo.csproj",
            CompilationReferenceResolverKernels.GetCSharpProjectReferenceBuildMessage("/tmp/Demo/Demo.csproj"));
    }

    [Fact]
    public void CompilationReferenceResolverKernels_NormalizesNuGetDependencyVersions()
    {
        AssertNormalized(null, null);
        AssertNormalized(string.Empty, null);
        AssertNormalized("   ", null);
        AssertNormalized("13.0.3", "13.0.3");
        AssertNormalized("[13.0.3]", "13.0.3");
        AssertNormalized("(1.0.0, 2.0.0]", "1.0.0");
        AssertNormalized("[, 2.0.0)", "2.0.0");
        AssertNormalized("[ 1.2.3 , 2.0.0)", "1.2.3");
        AssertNormalized(" (, 2.0.0 ] ", "2.0.0");
        AssertNormalized("(,)", null);
        AssertNormalized("[]", null);

        static void AssertNormalized(string? version, string? expectedVersion)
        {
            var normalizedVersion = CompilationReferenceResolverKernels.NormalizeNuGetDependencyVersion(version);
            Assert.Equal(expectedVersion, normalizedVersion);
        }
    }

    [Fact]
    public void CompilationReferenceResolverKernels_ParsesTargetFrameworkVersions()
    {
        AssertParsed("net10.0", 10, 0);
        AssertParsed("netstandard2.1", 2, 1);
        AssertParsed("net472", 472, 0);
        AssertParsed("net10..2", 10, 2);
        AssertParsed("net10.bad", 10, 0);
        AssertParsed("net10.2147483648", 10, 0);
        AssertInvalid("net");
        AssertInvalid("net2147483648.0");

        static void AssertParsed(string targetFramework, int expectedMajor, int expectedMinor)
        {
            var parsed = CompilationReferenceResolverKernels.ParseTargetFrameworkVersion(targetFramework);
            Assert.True(parsed.Parsed);
            Assert.Equal(expectedMajor, parsed.Major);
            Assert.Equal(expectedMinor, parsed.Minor);
        }

        static void AssertInvalid(string targetFramework)
        {
            var parsed = CompilationReferenceResolverKernels.ParseTargetFrameworkVersion(targetFramework);
            Assert.False(parsed.Parsed);
        }
    }

    [Fact]
    public void CompilationReferenceResolverKernels_ScoresFrameworkCompatibility()
    {
        AssertScore(null, "net10.0", 1);
        AssertScore(string.Empty, "net10.0", 1);
        AssertScore("   ", "net10.0", 1);
        AssertScore("net10.0", "net10.0", 10_000);
        AssertScore(".NETFramework,Version=v4.7.2", "net472", 10_000);
        AssertScore("netstandard2.1", "net10.0", 4_201);
        AssertScore("netcoreapp3.1", "net10.0", 7_301);
        AssertScore(".NETCoreApp,Version=v10.0", "net10.0", 8_000);
        AssertScore("net8.0", "net10.0", 8_800);
        AssertScore("net11.0", "net10.0", -1);
        AssertScore("unsupported", "net10.0", -1);
        AssertScore("netbad", "net10.0", -1);

        static void AssertScore(string? assetFramework, string targetFramework, int expectedScore)
        {
            var score = CompilationReferenceResolverKernels.GetFrameworkCompatibilityScore(
                assetFramework,
                targetFramework);
            Assert.Equal(expectedScore, score);
        }
    }

    [Theory]
    [InlineData("src/Program.nl", true)]
    [InlineData("bin/Debug/Generated.nl", false)]
    [InlineData("obj/generated/Temporary.nl", false)]
    [InlineData("Tests/FIXTURES/format/case.nl", false)]
    [InlineData("editors\\vscode\\test\\fixtures\\errors\\Bad.nl", false)]
    [InlineData(".nlc/cache/File.nl", false)]
    [InlineData("src/node_modulesx/File.nl", true)]
    [InlineData("src/Calculator.tests.nl", false)]
    [InlineData("src/Calculator.TESTS.NL", false)]
    [InlineData("src/Contest.nl", true)]
    public void FormatCommandKernels_SelectsDiscoveredPaths(string relativePath, bool expected)
    {
        var shouldFormat = FormatCommandKernels.ShouldFormatDiscoveredPath(relativePath);
        Assert.Equal(expected, shouldFormat);
    }

    [Theory]
    [InlineData(".git", true)]
    [InlineData(".HG", true)]
    [InlineData("bin", true)]
    [InlineData("OBJ", true)]
    [InlineData("node_modules", true)]
    [InlineData("node_modulesx", false)]
    [InlineData("fixtures", false)]
    [InlineData("src", false)]
    public void FormatCommandKernels_SelectsDiscoveredDirectorySkips(string directoryName, bool expected)
    {
        var shouldSkip = FormatCommandKernels.ShouldSkipDiscoveredDirectoryName(directoryName);
        Assert.Equal(expected, shouldSkip);
    }

    [Fact]
    public void FormatCommandKernels_SummarizesOptions()
    {
        var empty = FormatCommandKernels.GetOptionSummary(Array.Empty<string>());
        Assert.Null(empty.ProjectOption);
        Assert.False(empty.VerifyOnly);
        Assert.False(empty.DiffOnly);
        Assert.False(empty.StdinMode);
        Assert.False(empty.ShowHelp);

        var args = new[] { "--project", "samples/demo", "--check", "--diff", "--stdin", "-h" };
        var summary = FormatCommandKernels.GetOptionSummary(args);
        Assert.Equal("samples/demo", summary.ProjectOption);
        Assert.True(summary.VerifyOnly);
        Assert.True(summary.DiffOnly);
        Assert.True(summary.StdinMode);
        Assert.True(summary.ShowHelp);

        var programSummary = FormatCommandKernels.GetOptionSummary(new[] { "--project", "--check", "--verify-no-changes" });
        Assert.Equal("--check", programSummary.ProjectOption);
        Assert.True(programSummary.VerifyOnly);
        Assert.False(programSummary.DiffOnly);
        Assert.False(programSummary.StdinMode);
        Assert.False(programSummary.ShowHelp);

        Assert.True(FormatCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(FormatCommandKernels.GetOptionSummary(new[] { "--help" }).ShowHelp);
        Assert.True(FormatCommandKernels.GetOptionSummary(new[] { "-h" }).ShowHelp);

        var helpText = FormatCommandKernels.GetHelpText();
        Assert.Contains("N# Format", helpText);
        Assert.Contains("Usage: nlc format [options] [files...]", helpText);
        Assert.Contains("Formatting failed or --check found unformatted files", helpText);

        Assert.Equal(
            "Cannot combine --stdin with file arguments.",
            FormatCommandKernels.GetStdinWithFilesMessage());
        Assert.Equal("No .nl files found to format.", FormatCommandKernels.GetNoFilesFoundMessage());
        Assert.Equal("File not found: Missing.nl", FormatCommandKernels.GetFileNotFoundMessage("Missing.nl"));
        Assert.Equal(
            "Error formatting Broken.nl: parse failed",
            FormatCommandKernels.GetErrorFormattingMessage("Broken.nl", "parse failed"));
        Assert.Equal(
            "Warning [src/Program.nl]: Formatter safety check changed trivia.",
            FormatCommandKernels.GetWarningLine("src/Program.nl", "Formatter safety check changed trivia."));
        Assert.Equal(
            "Formatter safety check failed: changed trivia; moved comment",
            FormatCommandKernels.GetSafetyCheckFailedMessage("changed trivia; moved comment"));
        Assert.Equal(
            "Formatting check failed for 2 file(s):",
            FormatCommandKernels.GetCheckFailedHeader(2));
        Assert.Equal("  src/Program.nl", FormatCommandKernels.GetCheckFailedPathLine("src/Program.nl"));
        Assert.Equal("All files are properly formatted.", FormatCommandKernels.GetAllFilesFormattedMessage());
        Assert.Equal("Formatted 3 file(s).", FormatCommandKernels.GetFormattedCountMessage(3));
        Assert.Equal("Format failed: disk full", FormatCommandKernels.GetFailedMessage("disk full"));
        Assert.Equal(
            "Parse errors in src/Broken.nl: expected expression",
            FormatCommandKernels.GetParseErrorsMessage("src/Broken.nl", "expected expression"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => ExecuteProgram("format", "--help"));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage: nlc format [options] [files...]", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var (stdinExitCode, stdinStdout, stdinStderr) = CaptureConsole(() =>
            ExecuteProgram("format", "--stdin", "Program.nl"));
        Assert.Equal(1, stdinExitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdinStdout));
        Assert.Contains("Cannot combine --stdin with file arguments.", stdinStderr);
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

        var actualErrors = CompilerErrorSeverityFilter.Filter(errors, ErrorSeverity.Error);
        Assert.Equal(
            new[] { errors[1], errors[2], errors[4] },
            actualErrors);

        var actualWarnings = CompilerErrorSeverityFilter.Filter(errors, ErrorSeverity.Warning);
        Assert.Equal(
            new[] { errors[0], errors[3] },
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

        var substringMatches = QuerySymbolNameFilter.Filter(
            symbols,
            "user",
            200);
        Assert.Equal(
            new[] { "UserService", "UserQuery", "CurrentUser" },
            substringMatches.Select(symbol => symbol.Name));

        var globMatches = QuerySymbolNameFilter.Filter(
            symbols,
            "*Service",
            200);
        Assert.Equal(
            new[] { "UserService", "OrderService" },
            globMatches.Select(symbol => symbol.Name));

        var limitedMatches = QuerySymbolNameFilter.Filter(
            symbols,
            "*",
            2);
        Assert.Equal(
            new[] { "UserService", "OrderService" },
            limitedMatches.Select(symbol => symbol.Name));

        Assert.Throws<InvalidOperationException>(() =>
            QuerySymbolNameFilter.Filter(
                new[] { NewSymbol("café") },
                "caf*",
                200));

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

        var defaultSafeActions = FixCommandKernels.FilterBySafety(
            fixes,
            includeReviewNeeded: false);
        Assert.Equal(
            fixes.Where(fix => fix.Safety == FixSafety.Safe),
            defaultSafeActions);

        var reviewSafeActions = FixCommandKernels.FilterBySafety(
            fixes,
            includeReviewNeeded: true);
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

        var defaultSkipped = FixCommandKernels.SelectSkippedEntries(
            entries,
            includeReviewNeeded: false);
        Assert.Equal(
            entries.Where(entry => entry.Safety is not "safe"),
            defaultSkipped);

        var reviewSkipped = FixCommandKernels.SelectSkippedEntries(
            entries,
            includeReviewNeeded: true);
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

        var grouping = FixCommandKernels.GroupAppliedEntriesByFile(entries);

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
    public void TidyCommandKernels_SummarizesOptions()
    {
        var args = new[] { "--fix", "--json", "--project", "samples/demo" };

        var dogfoodSummary = TidyCommandKernels.GetOptionSummary(args);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.True(dogfoodSummary.Fix);
        Assert.True(dogfoodSummary.Json);
        Assert.False(dogfoodSummary.ShowHelp);

        var permissiveValue = TidyCommandKernels.GetOptionSummary(new[] { "--project", "--json" });
        Assert.Equal("--json", permissiveValue.ProjectOption);
        Assert.True(permissiveValue.Json);

        Assert.True(TidyCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(TidyCommandKernels.GetOptionSummary(new[] { "ignored", "-h" }).ShowHelp);

        var textMode = TidyCommandKernels.GetOutputMode(json: false);
        Assert.Equal(TidyOutputModeKind.Text, textMode);

        var jsonMode = TidyCommandKernels.GetOutputMode(json: true);
        Assert.Equal(TidyOutputModeKind.Json, jsonMode);

        var importedNamespace = TidyCommandKernels.GetImportedNamespace(
            "  import  Newtonsoft.Json.Linq // trailing comment");
        Assert.Equal("Newtonsoft.Json.Linq", importedNamespace);
        Assert.Equal("System.Text", TidyCommandKernels.GetImportedNamespace("\timport System.Text;"));

        var tabAfterKeyword = TidyCommandKernels.GetImportedNamespace(
            "import\tSystem.Text");
        Assert.Null(tabAfterKeyword);
        Assert.Null(TidyCommandKernels.GetImportedNamespace("print \"import System.Text\""));
        Assert.Null(TidyCommandKernels.GetImportedNamespace("import ;"));
        Assert.Equal("Résumé.Json", TidyCommandKernels.GetImportedNamespace("import Résumé.Json"));
    }

    [Fact]
    public void TidyCommandKernels_ShapesMessages()
    {
        var helpText = TidyCommandKernels.GetHelpText();
        Assert.Contains("N# Tidy", helpText);
        Assert.Contains("Usage: nlc tidy [options]", helpText);
        Assert.Contains("schemaVersion 1", helpText);

        Assert.Equal(
            "No project.yml found in the specified directory.",
            TidyCommandKernels.GetMissingProjectFileJsonMessage());
        Assert.Equal(
            "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project.",
            TidyCommandKernels.GetMissingProjectFileTextMessage());
        Assert.Equal(
            "Failed to parse project.yml: bad yaml",
            TidyCommandKernels.GetParseFailedMessage("bad yaml"));
        Assert.Equal("Nothing to remove.", TidyCommandKernels.GetNothingToRemoveMessage());
        Assert.Equal(
            "Removed 1 possibly-unused dependency.",
            TidyCommandKernels.GetRemovedDependenciesMessage(1));
        Assert.Equal(
            "Removed 2 possibly-unused dependencies.",
            TidyCommandKernels.GetRemovedDependenciesMessage(2));
        Assert.Equal(
            "No NuGet dependencies found in /tmp/demo",
            TidyCommandKernels.GetNoNuGetDependenciesMessage("/tmp/demo"));
        Assert.Equal(
            "  Package       Status           Reason",
            TidyCommandKernels.GetTableHeader("Package     ", "Status         "));
        Assert.Equal(
            "  -------  ------  ------",
            TidyCommandKernels.GetTableSeparator("-------", "------"));
        Assert.Equal(
            "  Newtonsoft.Json  possibly-unused  No import found.",
            TidyCommandKernels.GetTableRow("Newtonsoft.Json", "possibly-unused", "No import found."));
        Assert.Equal(
            "1 possibly-unused dependency found. Run 'nlc tidy --fix' to remove them.",
            TidyCommandKernels.GetPossiblyUnusedFoundMessage(1));
        Assert.Equal(
            "3 possibly-unused dependencies found. Run 'nlc tidy --fix' to remove them.",
            TidyCommandKernels.GetPossiblyUnusedFoundMessage(3));
        Assert.Equal(
            "All dependencies accounted for (2 could not be determined).",
            TidyCommandKernels.GetAllDependenciesAccountedForMessage(2));
        Assert.Equal(
            "All dependencies appear to be in use.",
            TidyCommandKernels.GetAllDependenciesInUseMessage());
        Assert.Equal(
            "Cannot determine namespace for single-segment package name; manual review required.",
            TidyCommandKernels.GetUnknownReasonMessage());
        Assert.Equal(
            "Import statement references namespace matching 'Newtonsoft.Json'.",
            TidyCommandKernels.GetUsedReasonMessage("Newtonsoft.Json"));
        Assert.Equal(
            "No import statement found referencing 'Serilog' or 'Serilog.Sinks'.",
            TidyCommandKernels.GetPossiblyUnusedReasonMessage("Serilog", "Serilog.Sinks"));

        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            TidyCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, exitCode);
        Assert.Contains("N# Tidy", stdout);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
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

        var statusRanks = TidyCommandKernels.ClassifyDependencyStatusRanks(
            references,
            imports);
        Assert.Equal(new[] { 2, 1, 3, 2, 1 }, statusRanks);

        var actual = TidyCommandKernels.SelectPossiblyUnusedDependencies(
            dependencies,
            static dependency => dependency.Status);
        Assert.Equal(
            dependencies.Where(dependency => dependency.Status == "possibly-unused"),
            actual);

        var summary = TidyCommandKernels.SummarizeDependencyStatuses(
            dependencies,
            static dependency => dependency.Status);
        Assert.Equal(2, summary.PossiblyUnusedCount);
        Assert.Equal(1, summary.UnknownCount);

        var nonAsciiReferences = new[]
        {
            new Reference { Nuget = "Résumé.Json", Version = "1.0.0" }
        };
        var nonAsciiImports = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Résumé.Json"
        };
        var nonAsciiStatusRanks = TidyCommandKernels.ClassifyDependencyStatusRanks(
            nonAsciiReferences,
            nonAsciiImports);
        Assert.Equal(new[] { 2 }, nonAsciiStatusRanks);

        static TidyDependency NewDependency(string name, string status) => new(name, status);
    }

    [Fact]
    public void TestCommandKernels_SummarizesTestOutcomeRanks()
    {
        var testSummary = TestCommandKernels.SummarizeOutcomeRanks(
            new[] { 1, 1, 3, 2, 0, 1 },
            6);
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

        var summary = TestCommandKernels.GetOptionSummary(args);
        Assert.Equal("samples/demo", summary.ProjectOption);
        Assert.Equal("il", summary.BackendOption);
        Assert.Equal("Adds", summary.Filter);
        Assert.Equal("30s", summary.Timeout);
        Assert.True(summary.Verbose);
        Assert.True(summary.JsonOutput);
        Assert.True(summary.CoverageReport);
        Assert.True(summary.CollectCoverage);
        Assert.True(summary.NoCache);
        Assert.False(summary.ShowHelp);

        var firstArgHelp = TestCommandKernels.GetOptionSummary(new[] { "help", "--json" });
        Assert.True(firstArgHelp.ShowHelp);
        Assert.True(firstArgHelp.JsonOutput);

        var helpAsProjectValue = TestCommandKernels.GetOptionSummary(new[] { "--project", "--help" });
        Assert.Equal("--help", helpAsProjectValue.ProjectOption);
        Assert.True(helpAsProjectValue.ShowHelp);

        var textMode = TestCommandKernels.GetOutputMode(json: false);
        Assert.Equal(TestOutputModeKind.Text, textMode);

        var jsonMode = TestCommandKernels.GetOutputMode(json: true);
        Assert.Equal(TestOutputModeKind.Json, jsonMode);
    }

    [Fact]
    public void TestCommandKernels_ParsesTimeoutDurations()
    {
        var seconds = TestCommandKernels.GetDurationMilliseconds("30s");
        Assert.Equal(30_000, seconds);

        var minutes = TestCommandKernels.GetDurationMilliseconds(" 5m ");
        Assert.Equal(300_000, minutes);

        var hours = TestCommandKernels.GetDurationMilliseconds("1h");
        Assert.Equal(3_600_000, hours);

        var zero = TestCommandKernels.GetDurationMilliseconds("0s");
        Assert.Null(zero);

        var overflow = TestCommandKernels.GetDurationMilliseconds("2147484s");
        Assert.Null(overflow);

        var (exitCode, _, stderr) = CaptureConsole(() =>
            Program.Execute(new[] { "test", "--timeout", "2147484s" }));
        Assert.Equal(1, exitCode);
        Assert.Contains("Invalid timeout format '2147484s'", stderr);

        var (jsonExitCode, jsonStdout, jsonStderr) = CaptureConsole(() =>
            Program.Execute(new[] { "test", "--timeout", "2147484s", "--json" }));
        Assert.Equal(1, jsonExitCode);
        Assert.True(string.IsNullOrWhiteSpace(jsonStderr));

        using var doc = JsonDocument.Parse(jsonStdout);
        Assert.Equal("test", doc.RootElement.GetProperty("command").GetString());
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Contains("Invalid timeout format '2147484s'", doc.RootElement.GetProperty("error").GetString());
    }

    [Fact]
    public void TestCommandKernels_ShapesMessages()
    {
        var helpText = TestCommandKernels.GetHelpText();
        Assert.StartsWith("N# Test", helpText);
        Assert.Contains("Usage: nlc test [options]", helpText);
        Assert.Contains("--coverage-report", helpText);

        Assert.Equal(
            "IL-backed test runs require a project.yml file.",
            TestCommandKernels.GetMissingProjectFileMessage());
        Assert.Equal(
            "Coverage collection is not available in nlc test yet. The current runner executes IL-backed xUnit/NUnit tests without instrumentation. Omit --coverage/--coverage-report until native coverage support lands.",
            TestCommandKernels.GetCoverageUnsupportedMessage());
        Assert.Equal("Test build failed.", TestCommandKernels.GetBuildFailedMessage());
        Assert.Equal(
            "Invalid timeout format '7w'. Expected a duration like 30s, 5m, or 1h.",
            TestCommandKernels.GetInvalidTimeoutMessage("7w"));
        Assert.Equal("Testing project in /tmp/demo...", TestCommandKernels.GetProjectStartMessage("/tmp/demo"));
        Assert.Equal("No test files (*.tests.nl) found.", TestCommandKernels.GetNoTestFilesMessage());
        Assert.Equal("Found 3 test file(s)", TestCommandKernels.GetFoundTestFilesMessage(3));
        Assert.Equal("Passed: 2, Failed: 1, Skipped: 4, Total: 7", TestCommandKernels.GetSummaryMessage(2, 1, 4, 7));
        Assert.Equal("  Tests completed in 42ms", TestCommandKernels.GetCompletedElapsedMessage("42ms"));
        Assert.Equal("  Tests failed in 42ms", TestCommandKernels.GetFailedElapsedMessage("42ms"));
        Assert.Equal("Test failed: boom", TestCommandKernels.GetFailedMessage("boom"));
        Assert.Equal("Passed adds person [12 ms]", TestCommandKernels.GetVerbosePassedMessage("adds person", "12"));
        Assert.Equal("Skipped adds person: not today", TestCommandKernels.GetVerboseSkippedMessage("adds person", "not today"));
        Assert.Equal("Failed adds person: nope", TestCommandKernels.GetVerboseFailedMessage("adds person", "nope"));
    }

    [Fact]
    public void TestCommandKernels_MatchFilters()
    {
        AssertFilter("addperson", "Add Person", string.Empty, "Tests.AddPerson", expected: true);
        AssertFilter(" description ", "Custom Description", "RawDisplayName", "Tests.Raw", expected: true);
        AssertFilter("rawdisplay", "Custom Description", "RawDisplayName", "Tests.Raw", expected: true);
        AssertFilter("missing | second", "First", string.Empty, "Tests.SecondCase", expected: true);
        AssertFilter(" | ", "First", string.Empty, "Tests.SecondCase", expected: false);
        AssertFilter("missing", "First", string.Empty, "Tests.SecondCase", expected: false);

        static void AssertFilter(
            string filter,
            string displayName,
            string alternateDisplayName,
            string fullyQualifiedName,
            bool expected)
        {
            var actual = TestCommandKernels.MatchesFilter(
                filter,
                displayName,
                alternateDisplayName,
                fullyQualifiedName);
            Assert.Equal(expected, actual);
        }
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

        var filteredLines = TidyCommandKernels.FilterRemovalLines(
            lines,
            packageNames);

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

        var nonAsciiFilteredLines = TidyCommandKernels.FilterRemovalLines(
            new[] { "  - R\u00e9sum\u00e9.Package", "  - Keep.Package" },
            new[] { "R\u00e9sum\u00e9.Package" });
        Assert.Equal(new[] { "  - Keep.Package" }, nonAsciiFilteredLines);
    }

    [Fact]
    public void DocCommandKernels_SummarizesOptions()
    {
        var args = new[] { "--json", "--open", "--project", "samples/demo", "--output", "docs/api" };

        var dogfoodSummary = DocCommandKernels.GetOptionSummary(args);
        Assert.Equal("samples/demo", dogfoodSummary.ProjectOption);
        Assert.Equal("docs/api", dogfoodSummary.OutputOption);
        Assert.True(dogfoodSummary.Json);
        Assert.True(dogfoodSummary.Open);
        Assert.False(dogfoodSummary.ShowHelp);

        var permissiveValue = DocCommandKernels.GetOptionSummary(new[] { "--project", "--json", "--output", "--open" });
        Assert.Equal("--json", permissiveValue.ProjectOption);
        Assert.Equal("--open", permissiveValue.OutputOption);
        Assert.True(permissiveValue.Json);
        Assert.True(permissiveValue.Open);

        Assert.True(DocCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(DocCommandKernels.GetOptionSummary(new[] { "ignored", "-h" }).ShowHelp);

        var textMode = DocCommandKernels.GetOutputMode(json: false);
        Assert.Equal(DocOutputModeKind.Text, textMode);

        var jsonMode = DocCommandKernels.GetOutputMode(json: true);
        Assert.Equal(DocOutputModeKind.Json, jsonMode);

        var helpText = DocCommandKernels.GetHelpText();
        Assert.Contains("N# API Documentation", helpText);
        Assert.Contains("Usage: nlc doc [options]", helpText);
        Assert.Contains("Documentation generation failed", helpText);
        Assert.Equal(
            "Project directory not found: /tmp/missing-doc-project",
            DocCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing-doc-project"));
        Assert.Equal("Generated API docs for 7 symbols.", DocCommandKernels.GetGeneratedSummaryMessage(7));
        Assert.Equal("Output: /tmp/api", DocCommandKernels.GetOutputPathMessage("/tmp/api"));
        Assert.Equal("Index: /tmp/api/index.html", DocCommandKernels.GetIndexPathMessage("/tmp/api/index.html"));
        Assert.Equal("Opened generated documentation in the default browser.", DocCommandKernels.GetOpenedMessage());
        Assert.Equal("Doc generation failed: no symbols", DocCommandKernels.GetGenerationFailedMessage("no symbols"));
        Assert.Equal(
            "Generated docs, but failed to open /tmp/api/index.html.",
            DocCommandKernels.GetOpenFailedMessage("/tmp/api/index.html"));
        Assert.Equal(
            "Generated docs, but failed to open /tmp/api/index.html: denied",
            DocCommandKernels.GetOpenFailedWithDetailMessage("/tmp/api/index.html", "denied"));
        Assert.Equal("src/Program.nl:12:4", DocCommandKernels.GetLocationText("src/Program.nl", 12, 4));
        Assert.Equal(
            "value: int",
            DocCommandKernels.GetParameterText("value", "int", hasDefault: false, defaultValue: string.Empty));
        Assert.Equal(
            "value: int = 42",
            DocCommandKernels.GetParameterText("value", "int", hasDefault: true, defaultValue: "42"));
        Assert.Equal(
            "func Compute(value: int = 42): string",
            DocCommandKernels.GetSignatureText(
                SymbolKind.Function,
                "Compute",
                hasParameterList: true,
                parametersText: "value: int = 42",
                typeName: "string"));
        Assert.Equal(
            "ctor Widget()",
            DocCommandKernels.GetSignatureText(
                SymbolKind.Constructor,
                "Widget",
                hasParameterList: true,
                parametersText: string.Empty,
                typeName: string.Empty));
        Assert.Equal(
            "class Widget",
            DocCommandKernels.GetSignatureText(
                SymbolKind.Class,
                "Widget",
                hasParameterList: false,
                parametersText: string.Empty,
                typeName: string.Empty));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => DocCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.Contains("Usage: nlc doc [options]", helpStdout);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));

        var missingProject = Path.Combine(Path.GetTempPath(), $"nsharp-doc-missing-{Guid.NewGuid():N}");
        var (missingExitCode, missingStdout, missingStderr) = CaptureConsole(() =>
            DocCommand.Execute(new[] { "--project", missingProject }));
        Assert.Equal(1, missingExitCode);
        Assert.True(string.IsNullOrWhiteSpace(missingStdout));
        Assert.Contains($"Project directory not found: {missingProject}", missingStderr);
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

        var actual = DocCommandKernels.OrderSymbolsForGeneration(symbols);
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

        var actual = DocCommandKernels.OrderMembersForGeneration(members);
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

        var actual = DocCommandKernels.CreateSlugs(rawSlugs);
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
    public void QueryTextJsonOutputRoutes_UseTextMode()
    {
        var classesAndRecordsProject = Path.Combine(FindExamplesDir(), "06-classes-and-records");
        var hiLine = File.ReadLines(Path.Combine(HelloWorldProject, "Program.nl"))
            .Select((text, index) => (Text: text, Line: index + 1))
            .First(line => line.Text.TrimStart().StartsWith("func Hi(", StringComparison.Ordinal))
            .Line;

        var (symbolsExitCode, symbolsStdout, symbolsStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "symbols",
            "--project", classesAndRecordsProject,
            "--filter", "*ircle",
            "--text"
        }));

        Assert.Equal(0, symbolsExitCode);
        Assert.True(string.IsNullOrWhiteSpace(symbolsStderr));
        Assert.Contains("Class Circle", symbolsStdout);
        Assert.DoesNotContain("\"command\"", symbolsStdout);

        var (hoverExitCode, hoverStdout, hoverStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "hover",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", $"{hiLine}:6",
            "--text"
        }));

        Assert.Equal(0, hoverExitCode);
        Assert.True(string.IsNullOrWhiteSpace(hoverStderr));
        Assert.Contains("Signature:", hoverStdout);
        Assert.Contains("Hi", hoverStdout);
        Assert.DoesNotContain("\"command\"", hoverStdout);

        var (callGraphExitCode, callGraphStdout, callGraphStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "call-graph",
            "--project", HelloWorldProject,
            "--function", "Main",
            "--text"
        }));

        Assert.Equal(0, callGraphExitCode);
        Assert.True(string.IsNullOrWhiteSpace(callGraphStderr));
        Assert.Contains("Call graph for: Main", callGraphStdout);
        Assert.Contains("Hi", callGraphStdout);
        Assert.DoesNotContain("\"command\"", callGraphStdout);
    }

    [Fact]
    public void QueryTextJsonOutputRoutes_RemainingCommandsUseTextMode()
    {
        var examplesDir = FindExamplesDir();
        var classesAndRecordsProject = Path.Combine(examplesDir, "06-classes-and-records");
        var multiFileProject = Path.Combine(examplesDir, "12-multi-file-projects", "MultiFileProject");

        void AssertTextSuccess(int exitCode, string stdout, string stderr, params string[] expectedStdout)
        {
            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            foreach (var expected in expectedStdout)
            {
                Assert.Contains(expected, stdout);
            }
            Assert.DoesNotContain("\"command\"", stdout);
        }

        void AssertTextError(int exitCode, string stdout, string stderr, string expectedStderr)
        {
            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains(expectedStderr, stderr);
            Assert.DoesNotContain("\"command\"", stderr);
        }

        var (implementorsExitCode, implementorsStdout, implementorsStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "implementors",
            "--project", classesAndRecordsProject,
            "--name", "IShape",
            "--text"
        }));
        AssertTextSuccess(implementorsExitCode, implementorsStdout, implementorsStderr, "Implementors of IShape", "Circle");

        var (outlineExitCode, outlineStdout, outlineStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "outline",
            "--project", HelloWorldProject,
            "Program.nl",
            "--text"
        }));
        AssertTextSuccess(outlineExitCode, outlineStdout, outlineStderr, "File: Program.nl", "Function Main");

        var (typeExitCode, typeStdout, typeStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "type",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "11:5",
            "--text"
        }));
        AssertTextSuccess(typeExitCode, typeStdout, typeStderr, "At Service.nl:11:5:", "IssueStore");

        var (definitionSearchExitCode, definitionSearchStdout, definitionSearchStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "definition",
            "--project", classesAndRecordsProject,
            "--name", "Point",
            "--text"
        }));
        AssertTextSuccess(definitionSearchExitCode, definitionSearchStdout, definitionSearchStderr, "Definitions of 'Point':", "record Point");

        var (definitionExitCode, definitionStdout, definitionStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "definition",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "22:10",
            "--text"
        }));
        AssertTextSuccess(definitionExitCode, definitionStdout, definitionStderr, "CreateIssue", "Service.nl");

        var (referencesExitCode, referencesStdout, referencesStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "references",
            "--project", IssueTrackerFixture,
            "--file", "Service.nl",
            "--pos", "10:7",
            "--text"
        }));
        AssertTextSuccess(referencesExitCode, referencesStdout, referencesStderr, "References to 'IssueService'", "Service.nl");

        var (completionsExitCode, completionsStdout, completionsStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "completions",
            "--project", multiFileProject,
            "--file", "Services/PersonService.nl",
            "--pos", "14:15",
            "--text"
        }));
        AssertTextSuccess(completionsExitCode, completionsStdout, completionsStderr, "Completions at Services/PersonService.nl:14:15", "methods");

        var (implementorsErrorExitCode, implementorsErrorStdout, implementorsErrorStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "implementors",
            "--project", classesAndRecordsProject,
            "--file", "RecordsAndInterfaces.nl",
            "--pos", "4:8",
            "--text"
        }));
        AssertTextError(implementorsErrorExitCode, implementorsErrorStdout, implementorsErrorStderr, "No interface found at RecordsAndInterfaces.nl:4:8");

        var (typeErrorExitCode, typeErrorStdout, typeErrorStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "type",
            "--project", IssueTrackerFixture,
            "--file", "Program.nl",
            "--pos", "1:1",
            "--text"
        }));
        AssertTextError(typeErrorExitCode, typeErrorStdout, typeErrorStderr, "No type information found at Program.nl:1:1");

        var (definitionErrorExitCode, definitionErrorStdout, definitionErrorStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "definition",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", "1:1",
            "--text"
        }));
        AssertTextError(definitionErrorExitCode, definitionErrorStdout, definitionErrorStderr, "No definition found at Program.nl:1:1");

        var (referencesErrorExitCode, referencesErrorStdout, referencesErrorStderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "references",
            "--project", HelloWorldProject,
            "--file", "Program.nl",
            "--pos", "1:1",
            "--text"
        }));
        AssertTextError(referencesErrorExitCode, referencesErrorStdout, referencesErrorStderr, "No symbol found at Program.nl:1:1");
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
    public void SymbolsCommand_KindParsingUsesQueryKernel()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
        {
            "symbols",
            "--project", IssueTrackerFixture,
            "--kind", "class",
            "--no-daemon"
        }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));

        using var doc = JsonDocument.Parse(stdout);
        var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
        Assert.NotEmpty(results);
        Assert.All(results, symbol => Assert.Equal("class", symbol.GetProperty("kind").GetString()));
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

    [Fact]
    public void CompletionCommandKernels_SummarizesOptions()
    {
        var bash = CompletionCommandKernels.GetOptionSummary(new[] { "BASH" });
        Assert.Equal(CompletionShellKind.Bash, bash.ShellKind);
        Assert.False(bash.ShowHelp);

        var zshHelp = CompletionCommandKernels.GetOptionSummary(new[] { "zsh", "--help" });
        Assert.Equal(CompletionShellKind.Zsh, zshHelp.ShellKind);
        Assert.True(zshHelp.ShowHelp);

        var fish = CompletionCommandKernels.GetOptionSummary(new[] { "fish" });
        Assert.Equal(CompletionShellKind.Fish, fish.ShellKind);
        Assert.False(fish.ShowHelp);

        var unknown = CompletionCommandKernels.GetOptionSummary(new[] { "PowerShell" });
        Assert.Equal(CompletionShellKind.Unknown, unknown.ShellKind);
        Assert.False(unknown.ShowHelp);

        Assert.True(CompletionCommandKernels.GetOptionSummary(Array.Empty<string>()).ShowHelp);
        Assert.True(CompletionCommandKernels.GetOptionSummary(new[] { "help" }).ShowHelp);
        Assert.True(CompletionCommandKernels.GetOptionSummary(new[] { "-h" }).ShowHelp);

        var helpText = CompletionCommandKernels.GetHelpText();
        Assert.Contains("N# Shell Completion", helpText);
        Assert.Contains("Usage: nlc completion <bash|zsh|fish>", helpText);
        Assert.Contains("Invalid shell name", helpText);
        Assert.Equal(
            "Unknown shell 'powershell'. Expected bash, zsh, or fish.",
            CompletionCommandKernels.GetUnknownShellMessage("powershell"));

        var (helpExitCode, helpStdout, helpStderr) = CaptureConsole(() => CompletionCommand.Execute(new[] { "--help" }));
        Assert.Equal(0, helpExitCode);
        Assert.True(string.IsNullOrWhiteSpace(helpStderr));
        Assert.Contains("Usage: nlc completion <bash|zsh|fish>", helpStdout);

        var (errorExitCode, errorStdout, errorStderr) = CaptureConsole(() => CompletionCommand.Execute(new[] { "PowerShell" }));
        Assert.Equal(1, errorExitCode);
        Assert.True(string.IsNullOrWhiteSpace(errorStdout));
        Assert.Contains("Unknown shell 'powershell'. Expected bash, zsh, or fish.", errorStderr);
    }

    private static int ExecuteProgram(params string[] args)
    {
        var programType = typeof(CheckCommand).Assembly.GetType("NSharpLang.Cli.Program");
        Assert.NotNull(programType);

        var method = programType!.GetMethod("Execute", System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic);
        Assert.NotNull(method);

        return (int)(method!.Invoke(null, new object[] { args }) ?? -1);
    }

    private static int ExecuteRunWithIlBackend(string projectRoot)
    {
        var programType = typeof(CheckCommand).Assembly.GetType("NSharpLang.Cli.Program");
        Assert.NotNull(programType);

        var method = programType!.GetMethod(
            "RunWithIlBackend",
            System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.NonPublic);
        Assert.NotNull(method);

        return (int)(method!.Invoke(null, new object?[] { projectRoot, null }) ?? -1);
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

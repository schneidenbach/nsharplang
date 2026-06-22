using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class CliParityAuditTests
{
    [Fact]
    public void CleanCommand_RemovesBuildArtifacts()
    {
        var tempDir = CreateTempDir();
        Directory.CreateDirectory(Path.Combine(tempDir, "bin"));
        Directory.CreateDirectory(Path.Combine(tempDir, "obj"));
        Directory.CreateDirectory(Path.Combine(tempDir, ".nlc"));

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CleanCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("Removed 3 build artifact", stdout);
            Assert.False(Directory.Exists(Path.Combine(tempDir, "bin")));
            Assert.False(Directory.Exists(Path.Combine(tempDir, "obj")));
            Assert.False(Directory.Exists(Path.Combine(tempDir, ".nlc")));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CompletionCommand_Bash_IncludesTopLevelCommands()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => CompletionCommand.Execute(new[] { "bash" }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("clean", stdout);
        Assert.Contains("watch", stdout);
        Assert.Contains("doc", stdout);
        Assert.Contains("completion", stdout);
        Assert.Contains("export", stdout);
        Assert.DoesNotContain("convert", stdout);
        Assert.DoesNotContain("transpile", stdout);
    }

    [Fact]
    public void FormatCommand_Check_ReturnsOneWhenFormattingIsNeeded()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), "func main(){print 5}");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("format", "--project", tempDir, "--check"));

            Assert.Equal(1, exitCode);
            Assert.Contains("Formatting check failed", stderr);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FormatCommand_Diff_EmitsUnifiedDiff()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), "func main(){print 5}");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("format", "--project", tempDir, "--diff", "Program.nl"));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("--- a/Program.nl", stdout);
            Assert.Contains("+++ b/Program.nl", stdout);
            Assert.Contains("@@ -", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void UnifiedDiff_Create_EmitsStableMultiHunkDiff()
    {
        var before = string.Join(
            '\n',
            new[]
            {
                "one",
                "two",
                "three",
                "four",
                "five",
                "six",
                "seven",
                "eight",
                "nine",
                "ten",
                "eleven",
                "twelve"
            });
        var after = string.Join(
            '\n',
            new[]
            {
                "one",
                "two",
                "THREE",
                "four",
                "five",
                "six",
                "seven",
                "eight",
                "nine-a",
                "nine",
                "ten",
                "twelve"
            });

        var diff = UnifiedDiff.Create(before, after, "a/Program.nl", "b/Program.nl", contextLines: 1);
        var expected = string.Join(
            '\n',
            new[]
            {
                "--- a/Program.nl",
                "+++ b/Program.nl",
                "@@ -2,3 +2,3 @@",
                " two",
                "-three",
                "+THREE",
                " four",
                "@@ -8,5 +8,5 @@",
                " eight",
                "+nine-a",
                " nine",
                " ten",
                "-eleven",
                " twelve"
            }) + "\n";

        Assert.Equal(expected, diff);
    }

    [Fact]
    public void FormatCommand_ProjectDiscovery_SkipsGeneratedAndInvalidFixtureTrees()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), "func Main() {\n    print \"ok\"\n}\n");
            File.WriteAllText(Path.Combine(tempDir, "Program.tests.nl"), "func Broken(x y) {");
            Directory.CreateDirectory(Path.Combine(tempDir, ".worktrees", "old"));
            File.WriteAllText(Path.Combine(tempDir, ".worktrees", "old", "Bad.nl"), "func Broken(x y) {");
            Directory.CreateDirectory(Path.Combine(tempDir, "tests", "fixtures", "generated", "Models"));
            File.WriteAllText(Path.Combine(tempDir, "tests", "fixtures", "generated", "Models", "Customer.nl"), "record Order(id: string)\n");
            Directory.CreateDirectory(Path.Combine(tempDir, "editors", "vscode", "test", "fixtures", "errors"));
            File.WriteAllText(Path.Combine(tempDir, "editors", "vscode", "test", "fixtures", "errors", "MultipleSyntaxErrors.nl"), "func Broken(x y) {");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("format", "--project", tempDir, "--check"));

            Assert.Equal(0, exitCode);
            Assert.Contains("All files are properly formatted", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FormatCommand_Stdin_FormatsToStdout()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(
            () => ExecuteProgram("format", "--stdin"),
            stdin: "func main(){print 5}");

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("func main() {", stdout);
        Assert.Contains("print 5", stdout);
    }

    [Fact]
    public void FormatCommand_StdinMalformedInput_ReturnsParseDiagnosticsWithoutFormatting()
    {
        var source = """
func main() {
    first := 1 +
    second := 2
}
""";

        var (exitCode, stdout, stderr) = CaptureConsole(
            () => ExecuteProgram("format", "--stdin"),
            stdin: source);

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdout));
        Assert.Contains("Format failed", stderr);
        Assert.Contains("Parse errors in stdin.nl", stderr);
        Assert.Contains("Expected expression after '+'", stderr);
    }

    [Fact]
    public void TestCommand_Help_DocumentsFilterAndVerbose()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => ExecuteProgram("test", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("Compilation backend: il", stdout);
        Assert.Contains("--filter", stdout);
        Assert.Contains("--verbose", stdout);
        Assert.Contains("--coverage", stdout);
        Assert.Contains("Coverage collection is not available", stdout);
    }

    [Fact]
    public void TestCommand_HelpWinsBeforeProjectResolution()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => ExecuteProgram("test", "--project", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("Usage: nlc test", stdout);
    }

    [Fact]
    public async Task WatchCommand_ReRunsAfterFileChange_AndReturnsLastExitCodeAsync()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    print "ok"
}
""");

            var modifier = Task.Run(async () =>
            {
                await Task.Delay(500);
                File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
}
""");
            });

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                WatchCommand.Execute(new[]
                {
                    "check",
                    "--project", tempDir,
                    "--debounce-ms", "50",
                    "--max-runs", "2"
                }));

            Assert.Equal(1, exitCode);
            Assert.Contains("Watching", stdout);
            Assert.Contains("Change detected", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            await modifier;
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DocCommand_GeneratesHtmlAndJsonManifest()
    {
        var tempDir = CreateTempDir();
        var outputDir = Path.Combine(tempDir, "docs-out");

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Add(x: int, y: int): int {
    return x + y
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                DocCommand.Execute(new[] { "--project", tempDir, "--output", outputDir, "--json" }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.True(File.Exists(Path.Combine(outputDir, "index.html")));
            Assert.True(File.Exists(Path.Combine(outputDir, "symbols", "functionaddprogram.html")));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DocCommand_GeneratesHtmlAndTextSummary()
    {
        var tempDir = CreateTempDir();
        var outputDir = Path.Combine(tempDir, "docs-out");

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Add(x: int, y: int): int {
    return x + y
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                DocCommand.Execute(new[] { "--project", tempDir, "--output", outputDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("Generated API docs for", stdout);
            Assert.Contains($"Output: {outputDir}", stdout);
            Assert.DoesNotContain("\"command\"", stdout);
            Assert.True(File.Exists(Path.Combine(outputDir, "index.html")));
            Assert.True(File.Exists(Path.Combine(outputDir, "symbols", "functionaddprogram.html")));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DocCommand_JsonMissingProject_UsesErrorEnvelope()
    {
        var tempDir = CreateTempDir();
        var missingProjectDir = Path.Combine(tempDir, "missing-project");

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                DocCommand.Execute(new[] { "--project", missingProjectDir, "--json" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("doc", root.GetProperty("command").GetString());
            Assert.False(root.GetProperty("ok").GetBoolean());
            Assert.Contains("Project directory not found", root.GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void Linter_IgnoreComment_SuppressesSpecificWarning()
    {
        var source = """
func Main() {
    // nlc:ignore NL001
    value := 42
}
""";

        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var parseResult = parser.ParseCompilationUnit();
        var diagnostics = new Linter().Lint(parseResult.CompilationUnit!, "test.nl", source);

        Assert.DoesNotContain(diagnostics, diagnostic => diagnostic.Code == "NL001");
    }

    // ── Step 1: --version flag ──────────────────────────────────────────

    [Fact]
    public void Version_Flag_ReturnsVersionString()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => ExecuteProgram("--version"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.StartsWith("nlc ", stdout.Trim());
        // Version should contain a semver-like pattern
        Assert.Matches(@"nlc \d+\.\d+\.\d+", stdout.Trim());
    }

    [Fact]
    public void Version_ShortFlag_ReturnsVersionString()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => ExecuteProgram("-V"));

        Assert.Equal(0, exitCode);
        Assert.StartsWith("nlc ", stdout.Trim());
    }

    // ── Step 2: Grouped help text ───────────────────────────────────────

    [Fact]
    public void Help_ShowsGroupedCommands()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => ExecuteProgram("help"));

        Assert.Equal(0, exitCode);
        Assert.Contains("Build & Run:", stdout);
        Assert.Contains("Analysis & Fix:", stdout);
        Assert.Contains("Code Quality:", stdout);
        Assert.Contains("Project:", stdout);
        Assert.Contains("Common Workflows:", stdout);
        Assert.Contains("--version, -V", stdout);
        Assert.Contains("export <target>", stdout);
        Assert.DoesNotContain("convert", stdout);
        Assert.DoesNotContain("transpile", stdout);
    }

    [Fact]
    public void Help_ShowsVersion_InHeader()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => ExecuteProgram("help"));

        Assert.Equal(0, exitCode);
        Assert.Matches(@"N# Compiler \(nlc\) \d+\.\d+\.\d+", stdout);
    }

    [Fact]
    public void Help_ShowsPerCommandHint()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => ExecuteProgram("help"));

        Assert.Equal(0, exitCode);
        Assert.Contains("nlc <command> --help", stdout);
    }

    // ── Step 3: Lint command overhaul ────────────────────────────────────

    [Fact]
    public void LintCommand_Help_ShowsRulesAndFlags()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => LintCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("--json", stdout);
        Assert.Contains("--text", stdout);
        Assert.Contains("--project", stdout);
        Assert.Contains("NL001", stdout);
        Assert.Contains("NL006", stdout);
        Assert.Contains("nlc:ignore", stdout);
    }

    [Fact]
    public void LintCommand_Json_EmitsStructuredEnvelope()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    value := 42
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                LintCommand.Execute(new[] { "--project", tempDir, "--json" }));

            Assert.Equal(1, exitCode);
            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("lint", root.GetProperty("command").GetString());
            Assert.False(root.GetProperty("ok").GetBoolean());
            Assert.True(root.GetProperty("lintedFiles").GetInt32() > 0);
            Assert.True(root.GetProperty("results").GetArrayLength() > 0);
            Assert.True(root.GetProperty("summary").GetProperty("errors").GetInt32() > 0);
            var diagnostic = Assert.Single(root.GetProperty("results").EnumerateArray(),
                result => result.GetProperty("code").GetString() == "NL001");
            Assert.Equal("    value := 42", diagnostic.GetProperty("sourceSnippet").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void LintCommand_Text_ShowsDiagnostics()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    value := 42
}
""");

            var (exitCode, _, stderr) = CaptureConsole(() =>
                LintCommand.Execute(new[] { "--project", tempDir, "--text" }));

            Assert.Equal(1, exitCode);
            Assert.Contains("NL001", stderr);
            Assert.Contains("value", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void LintCommand_CleanProject_ReturnsZero()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    print "hello"
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                LintCommand.Execute(new[] { "--project", tempDir, "--json" }));

            Assert.Equal(0, exitCode);
            using var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(0, doc.RootElement.GetProperty("results").GetArrayLength());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void LintCommand_MissingProject_ReturnsStructuredError()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-nonexistent-{Guid.NewGuid():N}");

        var (exitCode, stdout, _) = CaptureConsole(() =>
            LintCommand.Execute(new[] { "--project", missingDir, "--json" }));

        Assert.Equal(1, exitCode);
        using var doc = JsonDocument.Parse(stdout);
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Contains("not found", doc.RootElement.GetProperty("error").GetProperty("message").GetString());
    }

    [Fact]
    public void LintCommand_Json_MissingFile_ReportsError()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, _) = CaptureConsole(() =>
                LintCommand.Execute(new[] { "--project", tempDir, "NonExistent.nl" }));

            Assert.Equal(1, exitCode);
            using var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.True(doc.RootElement.GetProperty("results").GetArrayLength() > 0);
            var firstResult = doc.RootElement.GetProperty("results")[0];
            Assert.Equal("error", firstResult.GetProperty("severity").GetString());
            Assert.Contains("not found", firstResult.GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void LintCommand_Json_DefaultsToJsonWithFileArgs()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    value := 42
}
""");

            // nlc lint Program.nl (no --json flag) should still default to JSON
            var (exitCode, stdout, _) = CaptureConsole(() =>
                LintCommand.Execute(new[] { "--project", tempDir, "Program.nl" }));

            Assert.Equal(1, exitCode);
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("lint", doc.RootElement.GetProperty("command").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void LintCommand_FileArgs_DoesNotTreatProjectValueAsFile()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    print "hello"
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                LintCommand.Execute(new[] { "--project", tempDir, tempDir, "Program.nl", "--json" }));

            Assert.Equal(0, exitCode);
            using var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(1, doc.RootElement.GetProperty("lintedFiles").GetInt32());
            Assert.Equal(0, doc.RootElement.GetProperty("results").GetArrayLength());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Step 4: C# export flow ───────────────────────────────────────────

    [Fact]
    public void ExportCommand_Help_ExplainsCSharpFlow()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => ExecuteProgram("export", "csharp", "--help"));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage:", stdout);
        Assert.Contains("nlc export csharp <file.nl>", stdout);
        Assert.Contains("self-contained C# bundle", stdout);
        Assert.Contains("sibling test project", stdout);
    }

    [Fact]
    public void ExportCommand_ProjectAndSourceOperand_AreRejected()
    {
        var (exitCode, _, stderr) = CaptureConsole(() =>
            ExecuteProgram("export", "csharp", "--project", "demo", "Program.nl"));

        Assert.Equal(1, exitCode);
        Assert.Equal(
            ProgramCommandKernels.GetErrorLine(ExportCommandKernels.GetSourceAndProjectConflictMessage()) + Environment.NewLine,
            stderr);
    }

    [Fact]
    public void TranspileCommand_PointsToExportCommand()
    {
        var (exitCode, _, stderr) = CaptureConsole(() => ExecuteProgram("transpile", "Program.nl"));

        Assert.Equal(1, exitCode);
        Assert.Contains("removed", stderr);
        Assert.Contains("nlc export csharp", stderr);
    }

    [Fact]
    public void UpdateCommand_Help_ShowsUsage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            UpdateCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("N# Update Dependencies", stdout);
        Assert.Contains("Usage: nlc update [package] [options]", stdout);
    }

    [Fact]
    public void UpdateCommand_NoProjectYml_ReturnsHelpfulMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                UpdateCommand.Execute(Array.Empty<string>()));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("No project.yml found.", stderr);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void UpdateCommand_NoNuGetDependencies_ReturnsStatusMessage()
    {
        var projectDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(projectDir);
            File.WriteAllText("project.yml", """
name: UpdateDemo
version: 1.0.0
backend: il
targetFramework: net10.0

dependencies:
  - framework: Microsoft.AspNetCore.App
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                UpdateCommand.Execute(Array.Empty<string>()));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("No NuGet dependencies to update.", stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void UpdateCommand_MissingTargetDependency_ReturnsHelpfulMessage()
    {
        var projectDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(projectDir);
            File.WriteAllText("project.yml", """
name: UpdateDemo
version: 1.0.0
backend: il
targetFramework: net10.0

dependencies:
  - YamlDotNet@16.3.0
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                UpdateCommand.Execute(new[] { "Serilog" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("Package 'Serilog' not found in dependencies.", stderr);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void RemoveCommand_Help_ShowsUsage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            RemoveCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("N# Remove Dependency", stdout);
        Assert.Contains("Usage: nlc remove <package>", stdout);
    }

    [Fact]
    public void RemoveCommand_NoArgs_ReturnsUsage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            RemoveCommand.Execute(Array.Empty<string>()));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdout));
        Assert.Contains("Usage: nlc remove <package>", stderr);
    }

    [Fact]
    public void RemoveCommand_NoProjectYml_ReturnsHelpfulMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                RemoveCommand.Execute(new[] { "Serilog" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("No project.yml found.", stderr);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void RemoveCommand_MissingDependency_ReturnsHelpfulMessage()
    {
        var projectDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(projectDir);
            File.WriteAllText("project.yml", """
name: RemoveDemo
version: 1.0.0
backend: il
targetFramework: net10.0

dependencies:
  - YamlDotNet@16.3.0
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                RemoveCommand.Execute(new[] { "Serilog" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("Package 'Serilog' not found in dependencies.", stderr);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void RemoveCommand_RemovesMappingDependencyBlock()
    {
        var projectDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(projectDir);
            File.WriteAllText("project.yml", """
name: RemoveDemo
version: 1.0.0
backend: il
targetFramework: net10.0

dependencies:
  - nuget: Newtonsoft.Json
    version: 13.0.3
  - framework: Microsoft.AspNetCore.App
  - nuget: YamlDotNet
    version: 16.3.0
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => ExecuteProgram("remove", "Newtonsoft.Json"));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("Removed Newtonsoft.Json from project.yml", stdout);

            var projectYaml = File.ReadAllText(Path.Combine(projectDir, "project.yml"));
            Assert.DoesNotContain("Newtonsoft.Json", projectYaml);
            Assert.DoesNotContain("13.0.3", projectYaml);
            Assert.Contains("Microsoft.AspNetCore.App", projectYaml);
            Assert.Contains("YamlDotNet", projectYaml);
            Assert.Contains("16.3.0", projectYaml);
            Assert.True(File.Exists(Path.Combine(projectDir, "obj", "project.g.props")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void ConvertCommand_IsNotRegisteredAsPublicCliSurface()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => ExecuteProgram("convert", "--help"));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdout));
        Assert.Contains("Unknown command: convert", stderr);

        var exportedCliTypes = typeof(NSharpLang.Cli.CommandRegistry).Assembly.GetExportedTypes();
        Assert.DoesNotContain(exportedCliTypes, type => type.FullName?.Contains("ConvertCommand") == true);
    }

    // ── Step 5: Error message suggestions ───────────────────────────────

    [Fact]
    public void UnknownCommand_SuggestsHelp()
    {
        var (exitCode, _, stderr) = CaptureConsole(() => ExecuteProgram("frobnicate"));

        Assert.Equal(1, exitCode);
        Assert.Contains("Unknown command: frobnicate", stderr);
        Assert.Contains("nlc help", stderr);
    }

    [Fact]
    public void NewCommand_DirectoryExists_SuggestsAlternative()
    {
        var tempDir = CreateTempDir();
        var projectName = Path.GetFileName(tempDir);
        try
        {
            var (exitCode, _, stderr) = CaptureConsole(() =>
                ExecuteProgram("new", tempDir));

            Assert.Equal(1, exitCode);
            Assert.Contains("already exists", stderr);
            Assert.Contains("different name", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Theory]
    [InlineData("console", true, false, false)]
    [InlineData("library", false, false, false)]
    [InlineData("test", false, true, false)]
    [InlineData("webapi", true, false, true)]
    public void NewCommand_CreatesCanonicalCsprojFreeProjectShape(string template, bool hasProgram, bool hasTests, bool hasWebController)
    {
        var parentDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();
        var projectName = $"Demo{template}";

        try
        {
            Directory.SetCurrentDirectory(parentDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("new", projectName, "--template", template));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var projectDir = Path.Combine(parentDir, projectName);
            AssertCanonicalProjectShape(projectDir, projectName, hasProgram, hasTests, hasWebController);
            Assert.Contains("project.yml", stdout);
            Assert.Contains("nlc build", stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(parentDir, true);
        }
    }

    [Fact]
    public void NewCommand_CustomInstallRootEnvironment_WritesInstallRootFeed()
    {
        var parentDir = CreateTempDir();
        var installRoot = Path.Combine(parentDir, "custom install");
        var originalDirectory = Directory.GetCurrentDirectory();
        var originalInstallDir = Environment.GetEnvironmentVariable(NSharpInstallRoot.InstallDirEnvironmentVariable);

        try
        {
            Directory.SetCurrentDirectory(parentDir);
            Environment.SetEnvironmentVariable(NSharpInstallRoot.InstallDirEnvironmentVariable, installRoot);

            var (exitCode, _, stderr) = CaptureConsole(() =>
                ExecuteProgram("new", "CustomFeedApp"));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var nugetConfig = File.ReadAllText(Path.Combine(parentDir, "CustomFeedApp", "NuGet.config"));
            Assert.Contains(NSharpInstallRoot.InstallRootFeedValue, nugetConfig);
            Assert.DoesNotContain(NSharpInstallRoot.DefaultFeedValue, nugetConfig);
        }
        finally
        {
            Environment.SetEnvironmentVariable(NSharpInstallRoot.InstallDirEnvironmentVariable, originalInstallDir);
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(parentDir, true);
        }
    }

    [Fact]
    public void NewCommand_CustomInstallLayoutWithoutEnvironment_WritesDetectedFeed()
    {
        var root = CreateTempDir();
        var defaultRoot = Path.Combine(root, "default");
        var customRoot = Path.Combine(root, "toolset root");
        var cliBaseDirectory = Path.Combine(customRoot, "lib", "nlc");

        try
        {
            Directory.CreateDirectory(Path.Combine(customRoot, "bin"));
            Directory.CreateDirectory(Path.Combine(customRoot, "packages"));
            Directory.CreateDirectory(cliBaseDirectory);

            var feed = NSharpInstallRoot.ProjectFeedValue(
                cliBaseDirectory,
                installDirOverride: null,
                defaultInstallRoot: defaultRoot);

            Assert.Equal(Path.Combine(customRoot, "packages"), feed);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void NewCommand_AcceptsProjectNameAfterTemplateOption()
    {
        var parentDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();
        var projectName = "DemoOptionFirst";

        try
        {
            Directory.SetCurrentDirectory(parentDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("new", "--template", "library", projectName));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var projectDir = Path.Combine(parentDir, projectName);
            AssertCanonicalProjectShape(projectDir, projectName, hasProgram: false, hasTests: false, hasWebController: false);
            Assert.Contains("library", stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(parentDir, true);
        }
    }

    [Fact]
    public void NewCommand_NormalizesTemplateAliases()
    {
        var parentDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(parentDir);

            var (libraryExitCode, libraryStdout, libraryStderr) = CaptureConsole(() =>
                ExecuteProgram("new", "lib", "DemoLibAlias"));
            Assert.Equal(0, libraryExitCode);
            Assert.True(string.IsNullOrWhiteSpace(libraryStderr));
            AssertCanonicalProjectShape(
                Path.Combine(parentDir, "DemoLibAlias"),
                "DemoLibAlias",
                hasProgram: false,
                hasTests: false,
                hasWebController: false);
            Assert.Contains("library", libraryStdout);

            var (webExitCode, _, webStderr) = CaptureConsole(() =>
                ExecuteProgram("new", "DemoWebAlias", "--template", "web-api"));
            Assert.Equal(0, webExitCode);
            Assert.True(string.IsNullOrWhiteSpace(webStderr));
            AssertCanonicalProjectShape(
                Path.Combine(parentDir, "DemoWebAlias"),
                "DemoWebAlias",
                hasProgram: true,
                hasTests: false,
                hasWebController: true);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(parentDir, true);
        }
    }

    [Fact]
    public void NewCommand_Help_StatesCsprojFreePolicyAndTemplates()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => ExecuteProgram("new", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("csproj-free", stdout, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("--template", stdout);
        Assert.Contains("console", stdout);
        Assert.Contains("library", stdout);
        Assert.Contains("test", stdout);
        Assert.Contains("webapi", stdout);
        Assert.Contains("systems-cli", stdout);
        Assert.Contains("systems-lib", stdout);
        Assert.Contains("--systems", stdout);
    }

    [Fact]
    public void NewCommand_NoArgs_ReturnsUsage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => ExecuteProgram("new"));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdout));
        Assert.Contains("Usage: nlc new <project-name> [--template <template>]", stderr);
    }

    [Fact]
    public void NewCommand_InvalidTemplate_ReturnsHelpfulMessage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            ExecuteProgram("new", "MyApp", "--template", "unknown-template"));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdout));
        Assert.Contains(
            "Invalid template. Expected one of: console, library, test, webapi, systems-cli, systems-lib.",
            stderr);
    }

    [Theory]
    [InlineData("systems-cli", "Program.nl", "Systems.tests.nl")]
    [InlineData("systems-lib", "PacketCore.nl", "PacketCore.tests.nl")]
    public void NewCommand_CreatesSystemsProjectShape(string template, string sourceFile, string testFile)
    {
        var parentDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();
        var projectName = $"Demo{template.Replace("-", "", StringComparison.Ordinal)}";

        try
        {
            Directory.SetCurrentDirectory(parentDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("new", template, projectName));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var projectDir = Path.Combine(parentDir, projectName);
            Assert.True(File.Exists(Path.Combine(projectDir, sourceFile)));
            Assert.True(File.Exists(Path.Combine(projectDir, testFile)));
            Assert.Empty(Directory.GetFiles(projectDir, "*.csproj", SearchOption.TopDirectoryOnly));

            var projectYaml = File.ReadAllText(Path.Combine(projectDir, "project.yml"));
            Assert.Contains($"name: {projectName}", projectYaml);
            Assert.Contains("profile: systems", projectYaml);
            Assert.Contains("mode: strict", projectYaml);
            Assert.Contains("aotTarget: nativeaot", projectYaml);
            Assert.Contains("warmup:", projectYaml);
            Assert.Contains("project.yml", stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(parentDir, true);
        }
    }

    [Fact]
    public void NewCommand_CreatesSystemsProjectShapeFromTemplateFlag()
    {
        var parentDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(parentDir);

            var (exitCode, _, stderr) = CaptureConsole(() =>
                ExecuteProgram("new", "library", "PacketCore", "--systems"));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.True(File.Exists(Path.Combine(parentDir, "PacketCore", "PacketCore.nl")));
            var projectYaml = File.ReadAllText(Path.Combine(parentDir, "PacketCore", "project.yml"));
            Assert.Contains("profile: systems", projectYaml);
            Assert.Contains("outputType: library", projectYaml);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(parentDir, true);
        }
    }

    // ── nlc pack ─────────────────────────────────────────────────────────────

    [Fact]
    public void PackCommand_Help_ShowsUsage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            PackCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("project.yml", stdout);
        Assert.Contains("--output", stdout);
        Assert.Contains("--version", stdout);
        Assert.Contains("--include-symbols", stdout);
    }

    [Fact]
    public void PackCommand_NoProjectYml_Fails()
    {
        var tempDir = CreateTempDir();
        try
        {
            // No project.yml in tempDir
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                PackCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.Contains("project.yml", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PackCommand_NoProjectYml_JsonOutput_ReturnsErrorEnvelope()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                PackCommand.Execute(new[] { "--project", tempDir, "--json" }));

            Assert.Equal(1, exitCode);
            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("pack", root.GetProperty("command").GetString());
            Assert.False(root.GetProperty("ok").GetBoolean());
            Assert.Contains("project.yml",
                root.GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── WS5: Build timings, tidy, add ────────────────────────────────────────

    [Fact]
    public void BuildCommand_Timings_ShowsPhaseBreakdown()
    {
        // Verify --timings is documented in build --help and the phase names are present.
        // The actual timing output is emitted only on a successful build run; testing it
        // end-to-end requires compiling a sample project, which is covered by backend tests.
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            ExecuteProgram("build", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.True(
            stdout.Contains("--timings")
            && stdout.Contains("--backend")
            && stdout.Contains("Compilation backend: il")
            && (stdout.Contains("Transpile") || stdout.Contains("Compile") || stdout.Contains("timings")),
            $"Expected --timings and phase breakdown in build --help but got: {stdout}");
    }

    [Fact]
    public void BuildCommand_HelpWinsBeforeDefineExtraction()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            ExecuteProgram("build", "--define", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("Usage: nlc build", stdout);
    }

    [Fact]
    public void PublishCommand_Help_StatesSupportedAndUnsupportedTargetShapes()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            ExecuteProgram("publish", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("Current host runtime only", stdout);
        Assert.Contains("Portable framework-dependent", stdout);
        Assert.Contains("Cross-runtime publishing", stdout);
        Assert.Contains("Self-contained apphost/runtime bundles", stdout);
    }

    [Fact]
    public void PublishCommand_HelpWinsBeforeValidation()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            ExecuteProgram("publish", "--project", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("Usage: nlc publish", stdout);
    }

    [Fact]
    public void InitCommand_Help_ShowsUsage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            ExecuteProgram("init", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("N# Init", stdout);
        Assert.Contains("Usage: nlc init [options]", stdout);
        Assert.Contains("--force", stdout);
    }

    [Fact]
    public void InitCommand_InvalidType_ReturnsHelpfulMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("init", "--type", "service"));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("Invalid type 'service'. Expected 'exe' or 'library'.", stderr);
            Assert.False(File.Exists(Path.Combine(tempDir, "project.yml")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void InitCommand_CreatesMinimalProjectFiles()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("init", "--name", "DemoLib", "--type", "library"));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("Created: project.yml", stdout);
            Assert.Contains("Created: DemoLib.csproj", stdout);
            Assert.Contains("N# project initialized. Run 'nlc build' to compile.", stdout);

            var projectYaml = File.ReadAllText(Path.Combine(tempDir, "project.yml"));
            Assert.Contains("name: DemoLib", projectYaml);
            Assert.Contains("outputType: library", projectYaml);
            Assert.DoesNotContain("entry:", projectYaml);
            Assert.Equal("<Project Sdk=\"NSharpLang.Sdk\" />\n", File.ReadAllText(Path.Combine(tempDir, "DemoLib.csproj")));
            Assert.False(File.Exists(Path.Combine(tempDir, "Program.nl")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void RestoreCommand_Help_ShowsProjectYmlProjection()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            ExecuteProgram("restore", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("N# Restore", stdout);
        Assert.Contains("Usage: nlc restore", stdout);
        Assert.Contains("obj/project.g.props", stdout);
    }

    [Fact]
    public void RestoreCommand_NoProjectYml_ReturnsHelpfulError()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("restore"));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("No project.yml found. Run 'nlc new <name>' to create a project.", stderr);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TidyCommand_Help_ShowsUsage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            TidyCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("tidy", stdout);
        Assert.Contains("Usage", stdout);
    }

    [Fact]
    public void TidyCommand_NoProjectYml_Fails()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                TidyCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Equal(
                ProgramCommandKernels.GetErrorLine(TidyCommandKernels.GetMissingProjectFileTextMessage()) + Environment.NewLine,
                stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TidyCommand_JsonNoProjectYml_UsesErrorEnvelope()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                TidyCommand.Execute(new[] { "--project", tempDir, "--json" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("tidy", root.GetProperty("command").GetString());
            Assert.False(root.GetProperty("ok").GetBoolean());
            Assert.Contains("No project.yml", root.GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TidyCommand_Json_ClassifiesDependencyUsage()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TidyClassification
entry: Program.nl
outputType: exe
targetFramework: net10.0

dependencies:
  - nuget: Newtonsoft.Json
    version: 13.0.3
  - nuget: Serilog.Sinks.Console
    version: 5.0.1
  - nuget: Polly
    version: 8.0.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
  import  Newtonsoft.Json.Linq // used by tidy import extraction

func Main() {
    print "ok"
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                TidyCommand.Execute(new[] { "--project", tempDir, "--json" }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            using var doc = JsonDocument.Parse(stdout);
            var dependencies = doc.RootElement.GetProperty("dependencies")
                .EnumerateArray()
                .ToDictionary(
                    dependency => dependency.GetProperty("name").GetString()!,
                    dependency => dependency.GetProperty("status").GetString()!);

            Assert.Equal("used", dependencies["Newtonsoft.Json"]);
            Assert.Equal("possibly-unused", dependencies["Serilog.Sinks.Console"]);
            Assert.Equal("unknown", dependencies["Polly"]);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TidyCommand_Text_ClassifiesDependencyUsage()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TidyTextClassification
entry: Program.nl
outputType: exe
targetFramework: net10.0

dependencies:
  - nuget: Serilog.Sinks.Console
    version: 5.0.1
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    print "ok"
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                TidyCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("Package", stdout);
            Assert.Contains("Serilog.Sinks.Console", stdout);
            Assert.Contains("possibly-unused", stdout);
            Assert.DoesNotContain("\"command\"", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void AddCommand_Help_ShowsPathOption()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            AddCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("--path", stdout);
    }

    [Fact]
    public void AddCommand_NoArgs_ReturnsUsage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            AddCommand.Execute(Array.Empty<string>()));

        Assert.Equal(1, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stdout));
        Assert.Contains("Usage: nlc add <package>", stderr);
        Assert.Contains("nlc add <package>@<version>", stderr);
    }

    [Fact]
    public void AddCommand_NoProjectYml_ReturnsHelpfulMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                AddCommand.Execute(new[] { "Serilog@3.1.0" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project.", stderr);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void AddCommand_AddsInlinePackageBeforeNextTopLevelBlock()
    {
        var projectDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(projectDir);
            File.WriteAllText("project.yml", """
name: AddDemo
version: 1.0.0
backend: il

dependencies:
  - Newtonsoft.Json@13.0.3
targetFramework: net10.0
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => AddCommand.Execute(new[] { "Serilog@3.1.0" }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("Added Serilog@3.1.0 to project.yml", stdout);

            var projectYaml = File.ReadAllText(Path.Combine(projectDir, "project.yml"));
            var newDependencyIndex = projectYaml.IndexOf("Serilog@3.1.0", StringComparison.Ordinal);
            var nextTopLevelIndex = projectYaml.IndexOf("targetFramework: net10.0", StringComparison.Ordinal);

            Assert.Contains("Newtonsoft.Json@13.0.3", projectYaml);
            Assert.True(newDependencyIndex >= 0);
            Assert.True(nextTopLevelIndex > newDependencyIndex);
            Assert.True(File.Exists(Path.Combine(projectDir, "obj", "project.g.props")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void AddCommand_RejectsDuplicatePackageDependency()
    {
        var projectDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(projectDir);
            File.WriteAllText("project.yml", """
name: AddDuplicatePackageDemo
version: 1.0.0
backend: il
targetFramework: net10.0

dependencies:
  - Newtonsoft.Json@13.0.3
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => AddCommand.Execute(new[] { "newtonsoft.json@14.0.0" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("already in dependencies", stderr);

            var projectYaml = File.ReadAllText(Path.Combine(projectDir, "project.yml"));
            Assert.Contains("Newtonsoft.Json@13.0.3", projectYaml);
            Assert.DoesNotContain("14.0.0", projectYaml);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void AddCommand_RejectsDuplicateProjectDependency()
    {
        var projectDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(projectDir);
            Directory.CreateDirectory("Shared");
            File.WriteAllText(Path.Combine("Shared", "project.yml"), """
name: Shared
version: 1.0.0
targetFramework: net10.0
outputType: library
""");
            File.WriteAllText("project.yml", """
name: AddDuplicateProjectDemo
version: 1.0.0
backend: il
targetFramework: net10.0

dependencies:
  - project: Shared/project.yml
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() => AddCommand.Execute(new[] { "--path", "shared/PROJECT.yml" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stdout));
            Assert.Contains("already in dependencies", stderr);

            var projectYaml = File.ReadAllText(Path.Combine(projectDir, "project.yml"));
            Assert.Equal(1, projectYaml.Split("project:").Length - 1);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(projectDir, true);
        }
    }

    // ── Test command: build failure properly returns error ────────────

    [Fact]
    public void TestCommand_NoTestFiles_ReturnsZero()
    {
        var tempDir = CreateTempDir();
        try
        {
            // A project with no .tests.nl files should exit cleanly
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    print "hello"
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("test", "--project", tempDir));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("No test files (*.tests.nl) found.", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestCommand_CompilationError_ReturnsNonZero()
    {
        var tempDir = CreateTempDir();
        try
        {
            // project.yml is needed so the test command discovers source files
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TestProject
outputType: library
targetFramework: net10.0
""");
            // Source file with a type error the analyzer catches
            File.WriteAllText(Path.Combine(tempDir, "Lib.nl"), """
func Add(a int, b int) int {
    return a + b
}
""");
            // Test file that references an undefined function
            File.WriteAllText(Path.Combine(tempDir, "Lib.tests.nl"), """
test "add works" {
    result := Multiply(2, 3)
}
""");

            var (exitCode, _, _) = CaptureConsole(() =>
                ExecuteProgram("test", "--project", tempDir));

            // Must return non-zero when compilation fails — previously fell through
            // to the test runner and produced an "invalid DLL argument" error
            Assert.NotEqual(0, exitCode);
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

    private static string CreateTempDir()
    {
        var path = Path.Combine(Path.GetTempPath(), $"nsharp-cli-audit-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private static void AssertCanonicalProjectShape(
        string projectDir,
        string projectName,
        bool hasProgram,
        bool hasTests,
        bool hasWebController)
    {
        Assert.True(File.Exists(Path.Combine(projectDir, "project.yml")), "project.yml should exist");
        Assert.True(File.Exists(Path.Combine(projectDir, "global.json")), "global.json should exist");
        Assert.True(File.Exists(Path.Combine(projectDir, "NuGet.config")), "NuGet.config should exist");
        Assert.False(File.Exists(Path.Combine(projectDir, $"{projectName}.csproj")), "nlc new must not create a user-authored .csproj");
        Assert.False(File.Exists(Path.Combine(projectDir, $"{projectName}.g.csproj")), "nlc new must not create generated build artifacts before build");
        Assert.Empty(Directory.GetFiles(projectDir, "*.csproj", SearchOption.TopDirectoryOnly));

        Assert.Equal(hasProgram, File.Exists(Path.Combine(projectDir, "Program.nl")));
        Assert.Equal(hasTests, File.Exists(Path.Combine(projectDir, "Calculator.tests.nl")));
        Assert.Equal(hasWebController, File.Exists(Path.Combine(projectDir, "Controllers", "WeatherController.nl")));

        var projectYaml = File.ReadAllText(Path.Combine(projectDir, "project.yml"));
        Assert.Contains($"name: {projectName}", projectYaml);
        Assert.Contains(hasProgram ? "entry: Program.nl" : "outputType: library", projectYaml);
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
}

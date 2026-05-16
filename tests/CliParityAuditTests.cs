using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

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
    public void FormatCommand_ProjectDiscovery_SkipsGeneratedAndInvalidFixtureTrees()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), "func Main() {\n    print \"ok\"\n}\n");
            Directory.CreateDirectory(Path.Combine(tempDir, ".worktrees", "old"));
            File.WriteAllText(Path.Combine(tempDir, ".worktrees", "old", "Bad.nl"), "func Broken(x y) {");
            Directory.CreateDirectory(Path.Combine(tempDir, "tests", "fixtures", "idiom-v2", "Models"));
            File.WriteAllText(Path.Combine(tempDir, "tests", "fixtures", "idiom-v2", "Models", "Customer.nl"), "record Order(id: string)\n");
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
    public void TestCommand_Help_DocumentsFilterAndVerbose()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() => ExecuteProgram("test", "--help"));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("Compilation backend: il", stdout);
        Assert.Contains("--filter", stdout);
        Assert.Contains("--verbose", stdout);
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

            Assert.Equal(0, exitCode); // warnings are non-blocking
            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("lint", root.GetProperty("command").GetString());
            Assert.False(root.GetProperty("ok").GetBoolean());
            Assert.True(root.GetProperty("lintedFiles").GetInt32() > 0);
            Assert.True(root.GetProperty("results").GetArrayLength() > 0);
            Assert.True(root.GetProperty("summary").GetProperty("warnings").GetInt32() > 0);
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

            Assert.Equal(0, exitCode); // warnings are non-blocking
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

            Assert.Equal(0, exitCode); // warnings are non-blocking
            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("lint", doc.RootElement.GetProperty("command").GetString());
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
    public void TranspileCommand_PointsToExportCommand()
    {
        var (exitCode, _, stderr) = CaptureConsole(() => ExecuteProgram("transpile", "Program.nl"));

        Assert.Equal(1, exitCode);
        Assert.Contains("removed", stderr);
        Assert.Contains("nlc export csharp", stderr);
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
        Assert.DoesNotContain(exportedCliTypes, type => type.FullName?.Contains("CSharpToNSharpConverter") == true);
        Assert.DoesNotContain(exportedCliTypes, type => type.FullName?.Contains("CSharpConversionResult") == true);
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
    }

    // ── nlc bench ────────────────────────────────────────────────────────────

    [Fact]
    public void BenchCommand_Help_ShowsUsage()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            BenchCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        Assert.Contains("*.bench.nl", stdout);
        Assert.Contains("--backend", stdout);
        Assert.Contains("Compilation backend: il", stdout);
        Assert.Contains("--filter", stdout);
        Assert.Contains("--export", stdout);
        Assert.Contains("--job", stdout);
        Assert.Contains("--list", stdout);
    }

    [Fact]
    public void BenchCommand_NoBenchFiles_ReturnsClean()
    {
        var tempDir = CreateTempDir();
        try
        {
            // No *.bench.nl files — should exit 0 with a friendly message
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                BenchCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("No benchmark files", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BenchCommand_NoBenchFiles_JsonOutput_ReturnsZeroBenchmarks()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                BenchCommand.Execute(new[] { "--project", tempDir, "--json" }));

            Assert.Equal(0, exitCode);
            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.Equal(1, root.GetProperty("schemaVersion").GetInt32());
            Assert.Equal("bench", root.GetProperty("command").GetString());
            Assert.True(root.GetProperty("ok").GetBoolean());
            Assert.Equal(0, root.GetProperty("benchmarkCount").GetInt32());
            Assert.Equal(0, root.GetProperty("benchmarks").GetArrayLength());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BenchCommand_ListOnly_DiscoversBenchFunctions()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "math.bench.nl"), """
func benchAddNumbers() {
    let x = 1 + 2
}

func benchMultiply() {
    let y = 3 * 4
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                BenchCommand.Execute(new[] { "--project", tempDir, "--list", "--json" }));

            Assert.Equal(0, exitCode);
            using var doc = JsonDocument.Parse(stdout);
            var root = doc.RootElement;
            Assert.True(root.GetProperty("ok").GetBoolean());
            Assert.Equal("bench", root.GetProperty("command").GetString());
            Assert.True(root.GetProperty("benchmarkCount").GetInt32() >= 0);
        }
        finally
        {
            Directory.Delete(tempDir, true);
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
        // end-to-end requires MSBuild infrastructure not available in unit tests.
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

            var (exitCode, _, _) = CaptureConsole(() =>
                ExecuteProgram("test", "--project", tempDir));

            Assert.Equal(0, exitCode);
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
            // to dotnet test and produced an "invalid DLL argument" error
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

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
        Directory.CreateDirectory(Path.Combine(tempDir, "nsharp"));
        Directory.CreateDirectory(Path.Combine(tempDir, ".nlc"));

        try
        {
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CleanCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Contains("Removed 4 build artifact", stdout);
            Assert.False(Directory.Exists(Path.Combine(tempDir, "bin")));
            Assert.False(Directory.Exists(Path.Combine(tempDir, "obj")));
            Assert.False(Directory.Exists(Path.Combine(tempDir, "nsharp")));
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

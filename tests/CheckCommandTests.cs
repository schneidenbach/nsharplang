using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using Xunit;

namespace NSharpLang.Tests;

public class CheckCommandTests
{
    private static readonly string HelloWorldProject = Path.Combine(FindExamplesDir(), "01-hello-world");

    // ── Help ───────────────────────────────────────────────────────────

    [Fact]
    public void CheckCommand_ShortHelpFlag_ShowsHelp()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => CheckCommand.Execute(new[] { "-h" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc check", stdout);
    }

    [Fact]
    public void CheckCommand_HelpSubcommand_ShowsHelp()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => CheckCommand.Execute(new[] { "help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc check", stdout);
    }

    [Fact]
    public void CheckCommand_Help_DocumentsAllOptions()
    {
        var (_, stdout, _) = CaptureConsole(() => CheckCommand.Execute(new[] { "--help" }));

        Assert.Contains("--json", stdout);
        Assert.Contains("--text", stdout);
        Assert.Contains("--project", stdout);
        Assert.Contains("--help", stdout);
    }

    // ── Exit codes ─────────────────────────────────────────────────────

    [Fact]
    public void CheckCommand_CleanProject_ExitCodeZero()
    {
        var (exitCode, _, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", HelloWorldProject }));

        Assert.Equal(0, exitCode);
    }

    [Fact]
    public void CheckCommand_ProjectWithErrors_ExitCodeOne()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
    Console.WriteLine(sb.ToString())
}
""");

            var (exitCode, _, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── JSON output (default) ──────────────────────────────────────────

    [Fact]
    public void CheckCommand_CleanProject_JsonEnvelope_OkTrue()
    {
        var (_, stdout, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", HelloWorldProject }));

        var doc = JsonDocument.Parse(stdout);
        Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.True(doc.RootElement.GetProperty("checkedFiles").GetInt32() >= 1);
    }

    [Fact]
    public void CheckCommand_ErrorProject_JsonEnvelope_OkFalse()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
}
""");

            var (_, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            var doc = JsonDocument.Parse(stdout);
            Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.True(doc.RootElement.GetProperty("results").GetArrayLength() > 0);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_JsonResults_ContainDiagnosticFields()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
}
""");

            var (_, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.True(results.Length > 0);

            var first = results[0];
            Assert.True(first.TryGetProperty("code", out _));
            Assert.True(first.TryGetProperty("severity", out _));
            Assert.True(first.TryGetProperty("message", out _));
            Assert.True(first.TryGetProperty("file", out _));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Text output mode ───────────────────────────────────────────────

    [Fact]
    public void CheckCommand_TextMode_CleanProject_PrintsCheckedCount()
    {
        var (exitCode, _, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", HelloWorldProject, "--text" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Checked", stderr);
        Assert.Contains("no errors", stderr);
    }

    [Fact]
    public void CheckCommand_TextMode_WithErrors_PrintsDiagnostics()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
}
""");

            var (exitCode, _, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir, "--text" }));

            Assert.Equal(1, exitCode);
            Assert.False(string.IsNullOrWhiteSpace(stderr));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Missing/invalid project ────────────────────────────────────────

    [Fact]
    public void CheckCommand_MissingProject_JsonError()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-missing-{Guid.NewGuid():N}");

        var (exitCode, stdout, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", missingDir }));

        Assert.Equal(1, exitCode);
        var doc = JsonDocument.Parse(stdout);
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Contains("Directory not found", doc.RootElement.GetProperty("error").GetProperty("message").GetString());
    }

    [Fact]
    public void CheckCommand_MissingProject_TextMode_PrintsToStderr()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-missing-{Guid.NewGuid():N}");

        var (exitCode, _, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", missingDir, "--text" }));

        Assert.Equal(1, exitCode);
        Assert.Contains("Directory not found", stderr);
    }

    // ── Empty project ──────────────────────────────────────────────────

    [Fact]
    public void CheckCommand_EmptyProject_ExitCodeZero()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Positional project argument ────────────────────────────────────

    [Fact]
    public void CheckCommand_PositionalArg_WorksAsProjectDir()
    {
        var (exitCode, stdout, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { HelloWorldProject }));

        Assert.Equal(0, exitCode);
        var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Contains(NormalizePath(Path.GetFullPath(HelloWorldProject)),
            doc.RootElement.GetProperty("projectRoot").GetString());
    }

    // ── Diagnostics deduplication and ordering ─────────────────────────

    [Fact]
    public void CheckCommand_DiagnosticsAreSortedByFileAndLine()
    {
        var tempDir = CreateTempDir();
        var subDir = Path.Combine(tempDir, "src");
        Directory.CreateDirectory(subDir);
        try
        {
            File.WriteAllText(Path.Combine(subDir, "B.nl"), """
func B() {
    x := new StringBuilder()
}
""");
            File.WriteAllText(Path.Combine(subDir, "A.nl"), """
func A() {
    y := new StringBuilder()
}
""");

            var (_, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            Assert.True(results.Length >= 2,
                $"Expected at least 2 diagnostics from 2 files, got {results.Length}");

            // Verify ALL consecutive pairs are sorted by file, then by line
            for (int i = 0; i < results.Length - 1; i++)
            {
                var fileA = results[i].GetProperty("file").GetString() ?? "";
                var fileB = results[i + 1].GetProperty("file").GetString() ?? "";
                var cmp = string.Compare(fileA, fileB, StringComparison.Ordinal);
                if (cmp == 0)
                {
                    var lineA = results[i].GetProperty("line").GetInt32();
                    var lineB = results[i + 1].GetProperty("line").GetInt32();
                    Assert.True(lineA <= lineB,
                        $"Diagnostics not sorted by line within {fileA}: line {lineA} before {lineB}");
                }
                else
                {
                    Assert.True(cmp < 0,
                        $"Diagnostics not sorted by file: {fileA} before {fileB}");
                }
            }
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static string CreateTempDir()
    {
        var path = Path.Combine(Path.GetTempPath(), $"nsharp-check-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private static (int ExitCode, string Stdout, string Stderr) CaptureConsole(Func<int> action)
    {
        var originalOut = Console.Out;
        var originalError = Console.Error;
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();

        Console.SetOut(stdout);
        Console.SetError(stderr);

        try
        {
            var exitCode = action();
            return (exitCode, stdout.ToString(), stderr.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetError(originalError);
        }
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
            if (parent == null) break;
            dir = parent.FullName;
        }

        var fallback = "/Users/spencer/repos/nsharplang/examples";
        if (Directory.Exists(fallback)) return fallback;

        throw new DirectoryNotFoundException("Could not find examples directory.");
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

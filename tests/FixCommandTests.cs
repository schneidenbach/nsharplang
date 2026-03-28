using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using Xunit;

namespace NSharpLang.Tests;

public class FixCommandTests
{
    // ── Help ───────────────────────────────────────────────────────────

    [Fact]
    public void FixCommand_ShortHelpFlag_ShowsHelp()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => FixCommand.Execute(new[] { "-h" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc fix", stdout);
    }

    [Fact]
    public void FixCommand_HelpSubcommand_ShowsHelp()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => FixCommand.Execute(new[] { "help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc fix", stdout);
    }

    [Fact]
    public void FixCommand_Help_DocumentsAllOptions()
    {
        var (_, stdout, _) = CaptureConsole(() => FixCommand.Execute(new[] { "--help" }));

        Assert.Contains("--json", stdout);
        Assert.Contains("--text", stdout);
        Assert.Contains("--project", stdout);
        Assert.Contains("--file", stdout);
        Assert.Contains("--dry-run", stdout);
    }

    // ── Dry-run — empty project ────────────────────────────────────────

    [Fact]
    public void FixCommand_DryRun_EmptyProject_ExitCodeZero()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            Assert.Equal(0, exitCode);
            var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(0, doc.RootElement.GetProperty("filesModified").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Dry-run — project with fixable issues ──────────────────────────

    [Fact]
    public void FixCommand_DryRun_WithFixes_ExitCodeOneAndOkFalse()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            Assert.Equal(1, exitCode);
            var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.True(doc.RootElement.GetProperty("dryRun").GetBoolean());
            Assert.True(doc.RootElement.GetProperty("filesModified").GetInt32() > 0);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_DryRun_DoesNotModifyFiles()
    {
        var tempDir = CreateTempDir();
        try
        {
            var source = """
func Main() {
    sb := new StringBuilder()
}
""";
            var filePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(filePath, source);

            CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            // File should be untouched
            Assert.Equal(source, File.ReadAllText(filePath));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Apply fixes (non dry-run) ──────────────────────────────────────

    [Fact]
    public void FixCommand_Apply_ModifiesFiles()
    {
        var tempDir = CreateTempDir();
        try
        {
            var source = """
func Main() {
    sb := new StringBuilder()
}
""";
            var filePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(filePath, source);

            var (exitCode, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());

            // File should be different after fix
            var fixedSource = File.ReadAllText(filePath);
            Assert.NotEqual(source, fixedSource);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_Apply_JsonEnvelope_ReportsFixesApplied()
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
                FixCommand.Execute(new[] { "--project", tempDir }));

            var doc = JsonDocument.Parse(stdout);
            Assert.Equal("fix", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("fixesApplied").GetArrayLength() > 0);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── --file targeting ───────────────────────────────────────────────

    [Fact]
    public void FixCommand_FileFlag_TargetsSingleFile()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "A.nl"), """
func A() {
    x := new StringBuilder()
}
""");
            File.WriteAllText(Path.Combine(tempDir, "B.nl"), """
func B() {
    y := new StringBuilder()
}
""");

            var (_, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--file", "A.nl", "--dry-run" }));

            var doc = JsonDocument.Parse(stdout);
            var fixes = doc.RootElement.GetProperty("fixesApplied").EnumerateArray().ToArray();
            Assert.True(fixes.Length > 0);
            // All fixes should be for A.nl only
            foreach (var fix in fixes)
            {
                Assert.Equal("A.nl", fix.GetProperty("file").GetString());
            }
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_FileFlag_MissingFile_ReturnsError()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--file", "DoesNotExist.nl" }));

            Assert.Equal(1, exitCode);
            var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Contains("File not found", doc.RootElement.GetProperty("error").GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Missing project ────────────────────────────────────────────────

    [Fact]
    public void FixCommand_MissingProject_JsonError()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-missing-{Guid.NewGuid():N}");

        var (exitCode, stdout, _) = CaptureConsole(() =>
            FixCommand.Execute(new[] { "--project", missingDir }));

        Assert.Equal(1, exitCode);
        var doc = JsonDocument.Parse(stdout);
        Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Contains("Directory not found", doc.RootElement.GetProperty("error").GetProperty("message").GetString());
    }

    [Fact]
    public void FixCommand_MissingProject_TextMode_PrintsToStderr()
    {
        var missingDir = Path.Combine(Path.GetTempPath(), $"nsharp-missing-{Guid.NewGuid():N}");

        var (exitCode, _, stderr) = CaptureConsole(() =>
            FixCommand.Execute(new[] { "--project", missingDir, "--text" }));

        Assert.Equal(1, exitCode);
        Assert.Contains("Directory not found", stderr);
    }

    // ── Text output mode ───────────────────────────────────────────────

    [Fact]
    public void FixCommand_TextMode_NoFixes_PrintsNothingToFix()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, _, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--text" }));

            Assert.Equal(0, exitCode);
            Assert.Contains("No .nl files found", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_TextMode_DryRun_ShowsWouldFix()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
}
""");

            var (_, _, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run", "--text" }));

            Assert.Contains("Would fix", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_TextMode_Apply_ShowsFixed()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    sb := new StringBuilder()
}
""");

            var (_, _, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--text" }));

            Assert.Contains("Fixed", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Multi-file fix ─────────────────────────────────────────────────

    [Fact]
    public void FixCommand_MultipleFiles_FixesAll()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "A.nl"), """
func A() {
    x := new StringBuilder()
}
""");
            File.WriteAllText(Path.Combine(tempDir, "B.nl"), """
func B() {
    y := new StringBuilder()
}
""");

            var (_, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            var doc = JsonDocument.Parse(stdout);
            var fixes = doc.RootElement.GetProperty("fixesApplied").EnumerateArray().ToArray();
            var fixedFiles = fixes.Select(f => f.GetProperty("file").GetString()).Distinct().ToArray();
            Assert.True(fixedFiles.Length >= 2, $"Expected fixes in >=2 files, got {fixedFiles.Length}");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── JSON envelope structure ────────────────────────────────────────

    [Fact]
    public void FixCommand_JsonEnvelope_HasSchemaVersion()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (_, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            var doc = JsonDocument.Parse(stdout);
            Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_JsonEnvelope_NormalizesProjectRoot()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (_, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            var doc = JsonDocument.Parse(stdout);
            var projectRoot = doc.RootElement.GetProperty("projectRoot").GetString()!;
            Assert.DoesNotContain("\\", projectRoot);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_FixesApplied_ContainEditDetails()
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
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            var doc = JsonDocument.Parse(stdout);
            var fixes = doc.RootElement.GetProperty("fixesApplied").EnumerateArray().ToArray();
            Assert.True(fixes.Length > 0);

            var fix = fixes[0];
            Assert.True(fix.TryGetProperty("file", out _));
            Assert.True(fix.TryGetProperty("diagnostic", out _));
            Assert.True(fix.TryGetProperty("title", out _));
            Assert.True(fix.TryGetProperty("edits", out var edits));
            Assert.True(edits.GetArrayLength() > 0);

            var edit = edits.EnumerateArray().First();
            Assert.True(edit.TryGetProperty("startLine", out _));
            Assert.True(edit.TryGetProperty("startColumn", out _));
            Assert.True(edit.TryGetProperty("endLine", out _));
            Assert.True(edit.TryGetProperty("endColumn", out _));
            Assert.True(edit.TryGetProperty("newText", out _));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static string CreateTempDir()
    {
        var path = Path.Combine(Path.GetTempPath(), $"nsharp-fix-{Guid.NewGuid():N}");
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
}

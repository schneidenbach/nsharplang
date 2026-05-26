using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
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

            var (exitCode, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            // Confirm fixes WERE discovered (exit code 1 means pending fixes)
            Assert.Equal(1, exitCode);
            var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("filesModified").GetInt32() > 0,
                "Expected dry-run to discover fixes, but filesModified was 0");

            // File should be untouched despite pending fixes
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
            Assert.Equal(2, doc.RootElement.GetProperty("schemaVersion").GetInt32());
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

    [Fact]
    public void FixCommand_DryRun_CrlfEmptyCatch_ReportsLogicalLineColumns()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"),
                "func main() {\r\n    try {\r\n    } catch {\r\n    }\r\n}");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            Assert.Equal(1, exitCode);
            var doc = JsonDocument.Parse(stdout);
            var fixes = doc.RootElement.GetProperty("fixesApplied").EnumerateArray().ToArray();
            var emptyCatchFix = Assert.Single(fixes,
                f => f.GetProperty("diagnostic").GetString() == "NL011");
            var edit = Assert.Single(emptyCatchFix.GetProperty("edits").EnumerateArray());

            Assert.Equal(3, edit.GetProperty("startLine").GetInt32());
            Assert.Equal(13, edit.GetProperty("startColumn").GetInt32());
            Assert.Equal(3, edit.GetProperty("endLine").GetInt32());
            Assert.Equal(13, edit.GetProperty("endColumn").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Safety filtering ───────────────���────────────────────────────────

    [Fact]
    public void FixCommand_Default_OnlyAppliesSafeFixes()
    {
        var tempDir = CreateTempDir();
        try
        {
            // unused import (NL010 → ReviewNeeded) + unused let variable (NL001 → ReviewNeeded)
            // The let-based var also triggers NL002 (add import, Safe) for StringBuilder
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.IO

func Main() {
    let unused = 42
}
""");

            var (_, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            var applied = doc.RootElement.GetProperty("fixesApplied").EnumerateArray().ToArray();

            // results should contain more fixes than fixesApplied (ReviewNeeded ones are skipped)
            Assert.True(results.Length > applied.Length,
                $"Expected results ({results.Length}) > fixesApplied ({applied.Length})");

            // All applied fixes must be safe
            foreach (var fix in applied)
            {
                Assert.Equal("safe", fix.GetProperty("safety").GetString());
            }

            // results should contain some non-safe fixes
            Assert.Contains(results, r => r.GetProperty("safety").GetString() != "safe");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_IncludeReviewNeeded_AppliesReviewNeededFixes()
    {
        var tempDir = CreateTempDir();
        try
        {
            // unused import (NL010 → ReviewNeeded)
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.IO

func Main() {
    let unused = 42
}
""");

            var (_, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run", "--include-review-needed" }));

            var doc = JsonDocument.Parse(stdout);
            var applied = doc.RootElement.GetProperty("fixesApplied").EnumerateArray().ToArray();

            // With --include-review-needed, ReviewNeeded fixes should also be applied
            Assert.Contains(applied, f => f.GetProperty("safety").GetString() == "reviewNeeded");
            Assert.True(doc.RootElement.GetProperty("includeReviewNeeded").GetBoolean());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_SuggestionOnly_NeverApplied()
    {
        // SuggestionOnly fixes (NL013) should never be in fixesApplied, even with --include-review-needed
        var tempDir = CreateTempDir();
        try
        {
            // String concatenation triggers NL013 (SuggestionOnly)
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    let name = "world"
    let greeting = "hello " + name
    print greeting
}
""");

            var (_, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run", "--include-review-needed" }));

            var doc = JsonDocument.Parse(stdout);
            var applied = doc.RootElement.GetProperty("fixesApplied").EnumerateArray().ToArray();

            // No SuggestionOnly fixes should appear in fixesApplied
            Assert.DoesNotContain(applied, f => f.GetProperty("safety").GetString() == "suggestionOnly");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_ResultsVsFixesApplied_AreDifferentiated()
    {
        var tempDir = CreateTempDir();
        try
        {
            // unused import (NL010 → ReviewNeeded) to ensure results != fixesApplied
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.IO

func Main() {
    let unused = 42
}
""");

            var (_, stdout, _) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--dry-run" }));

            var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results");
            var applied = doc.RootElement.GetProperty("fixesApplied");

            // They should NOT be identical — results includes ReviewNeeded fixes
            var resultsJson = results.GetRawText();
            var appliedJson = applied.GetRawText();
            Assert.NotEqual(resultsJson, appliedJson);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_SafetyFieldInJsonOutput()
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
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();

            // Every result must have a safety field
            foreach (var result in results)
            {
                Assert.True(result.TryGetProperty("safety", out var safety));
                var val = safety.GetString();
                Assert.True(val == "safe" || val == "reviewNeeded" || val == "suggestionOnly",
                    $"Unexpected safety value: {val}");
            }
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void FixCommand_Help_DocumentsIncludeReviewNeeded()
    {
        var (_, stdout, _) = CaptureConsole(() => FixCommand.Execute(new[] { "--help" }));

        Assert.Contains("--include-review-needed", stdout);
    }

    [Fact]
    public void FixCommand_TextMode_ShowsSkippedFixes()
    {
        var tempDir = CreateTempDir();
        try
        {
            // unused import (NL010 → ReviewNeeded) gets skipped without --include-review-needed
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.IO

func Main() {
    let unused = 42
}
""");

            var (_, _, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--text" }));

            // Should mention skipped fixes
            Assert.Contains("Skipped", stderr);
            Assert.Contains("--include-review-needed", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void ShouldApply_SafeIsAlwaysApplied()
    {
        Assert.True(FixCommand.ShouldApply(FixSafety.Safe, includeReviewNeeded: false));
        Assert.True(FixCommand.ShouldApply(FixSafety.Safe, includeReviewNeeded: true));
    }

    [Fact]
    public void ShouldApply_ReviewNeededRequiresFlag()
    {
        Assert.False(FixCommand.ShouldApply(FixSafety.ReviewNeeded, includeReviewNeeded: false));
        Assert.True(FixCommand.ShouldApply(FixSafety.ReviewNeeded, includeReviewNeeded: true));
    }

    [Fact]
    public void ShouldApply_SuggestionOnlyNeverApplied()
    {
        Assert.False(FixCommand.ShouldApply(FixSafety.SuggestionOnly, includeReviewNeeded: false));
        Assert.False(FixCommand.ShouldApply(FixSafety.SuggestionOnly, includeReviewNeeded: true));
    }

    [Fact]
    public void FixCommand_DryRun_File_NL003_ReportsExactZeroBasedEditAndDoesNotModifyFile()
    {
        AssertDryRunSingleFix(
            "NL003",
            @"func Main() {
    if 1 != null {
        print 1
    }
}",
            startLine: 2,
            startColumn: 7,
            endLine: 2,
            endColumn: 16,
            newText: "true");
    }

    [Fact]
    public void FixCommand_DryRun_File_NL011_ReportsExactZeroBasedEditAndDoesNotModifyFile()
    {
        AssertDryRunSingleFix(
            "NL011",
            @"func Main() {
    try {
    } catch {
    }
}",
            startLine: 3,
            startColumn: 13,
            endLine: 3,
            endColumn: 13,
            newText: "\n        // TODO: handle exception");
    }

    [Fact]
    public void FixCommand_DryRun_File_NL011_StandaloneCrReportsLogicalLineAndColumn()
    {
        AssertDryRunSingleFix(
            "NL011",
            "func Main() {\r    try {\r    } catch {\r    }\r}\r",
            startLine: 3,
            startColumn: 13,
            endLine: 3,
            endColumn: 13,
            newText: "\n        // TODO: handle exception");
    }

    [Fact]
    public void FixCommand_DryRun_File_NL015_ReportsExactZeroBasedEditAndDoesNotModifyFile()
    {
        AssertDryRunSingleFix(
            "NL015",
            @"func Main() {
    let answer: int = 42
    print answer
}",
            startLine: 2,
            startColumn: 4,
            endLine: 2,
            endColumn: 8,
            newText: "const ");
    }

    [Fact]
    public void FixCommand_DryRun_File_NL110_ReportsExactZeroBasedEditAndDoesNotModifyFile()
    {
        AssertDryRunSingleFix(
            "NL110",
            @"func Main() {
    p := new Person { Name = ""Ada"" }
}",
            startLine: 2,
            startColumn: 26,
            endLine: 2,
            endColumn: 29,
            newText: ": ");
    }

    [Fact]
    public void FixCommand_DryRun_LastLineWholeLineDeletion_PreflightsSafely()
    {
        var tempDir = CreateTempDir();
        try
        {
            var source = "import System.IO";
            var filePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(filePath, source);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--file", "Program.nl", "--dry-run", "--include-review-needed" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Equal(source, File.ReadAllText(filePath));

            using var doc = JsonDocument.Parse(stdout);
            var fix = Assert.Single(doc.RootElement.GetProperty("fixesApplied").EnumerateArray());
            Assert.Equal("NL010", fix.GetProperty("diagnostic").GetString());
            var edit = Assert.Single(fix.GetProperty("edits").EnumerateArray());
            Assert.Equal(1, edit.GetProperty("startLine").GetInt32());
            Assert.Equal(0, edit.GetProperty("startColumn").GetInt32());
            Assert.Equal(2, edit.GetProperty("endLine").GetInt32());
            Assert.Equal(0, edit.GetProperty("endColumn").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static void AssertDryRunSingleFix(
        string diagnosticCode,
        string source,
        int startLine,
        int startColumn,
        int endLine,
        int endColumn,
        string newText)
    {
        var tempDir = CreateTempDir();
        try
        {
            var filePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(filePath, source);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                FixCommand.Execute(new[] { "--project", tempDir, "--file", "Program.nl", "--dry-run" }));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.Equal(source, File.ReadAllText(filePath));

            using var doc = JsonDocument.Parse(stdout);
            var fix = Assert.Single(
                doc.RootElement.GetProperty("fixesApplied").EnumerateArray(),
                candidate => candidate.GetProperty("diagnostic").GetString() == diagnosticCode);
            Assert.Equal("Program.nl", fix.GetProperty("file").GetString());
            Assert.Equal("safe", fix.GetProperty("safety").GetString());

            var edit = Assert.Single(fix.GetProperty("edits").EnumerateArray());
            Assert.Equal(startLine, edit.GetProperty("startLine").GetInt32());
            Assert.Equal(startColumn, edit.GetProperty("startColumn").GetInt32());
            Assert.Equal(endLine, edit.GetProperty("endLine").GetInt32());
            Assert.Equal(endColumn, edit.GetProperty("endColumn").GetInt32());
            Assert.Equal(newText, edit.GetProperty("newText").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

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

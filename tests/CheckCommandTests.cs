using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class CheckCommandTests
{
    private static readonly string HelloWorldProject = Path.Combine(FindExamplesDir(), "01-hello-world");
    private static readonly string MinimalApiProject = Path.Combine(FindExamplesDir(), "14-minimal-api");

    private const string UnresolvedTypeProgram = """
func Main() {
    sb := new StringBuilder()
}
""";

    // ── Help ───────────────────────────────────────────────────────────

    [Theory]
    [InlineData("-h")]
    [InlineData("help")]
    public void CheckCommand_HelpEntryPoints_ShowHelp(string argument)
    {
        var (exitCode, stdout, _) = CaptureConsole(() => CheckCommand.Execute(new[] { argument }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc check", stdout);
    }

    [Fact]
    public void CheckCommand_Help_DocumentsAllOptions()
    {
        var (_, stdout, _) = CaptureConsole(() => CheckCommand.Execute(new[] { "--help" }));

        Assert.All(
            new[] { "--json", "--text", "--backend", "Compilation backend: il", "--project", "--help" },
            option => Assert.Contains(option, stdout));
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
    public void CheckCommand_FrameworkReferencedProject_JsonOutputIsNotPollutedByAnalyzerWarnings()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", MinimalApiProject }));

        Assert.Equal(0, exitCode);
        Assert.Equal(string.Empty, stderr);

        var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32());
    }

    [Fact]
    public void CheckCommand_ErrorProject_JsonEnvelope_OkFalse()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), UnresolvedTypeProgram);

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
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), UnresolvedTypeProgram);

            var (_, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            var doc = JsonDocument.Parse(stdout);
            var results = doc.RootElement.GetProperty("results").EnumerateArray().ToArray();
            var first = results[0];
            Assert.All(new[] { "code", "severity", "message", "file" },
                name => Assert.True(first.TryGetProperty(name, out _)));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_JsonResults_UseLinterDiagnosticLength()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    message := "hi"
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode); // NL001 (unused-variable) is a build-blocking error.

            var doc = JsonDocument.Parse(stdout);
            var diagnostic = doc.RootElement.GetProperty("results").EnumerateArray()
                .Single(result => result.GetProperty("code").GetString() == "NL001");

            Assert.Equal(2, diagnostic.GetProperty("line").GetInt32()); // Underlines the identifier itself, using its stored length.
            Assert.Equal(5, diagnostic.GetProperty("column").GetInt32());
            Assert.Equal("message".Length, diagnostic.GetProperty("length").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_LockOnValueType_ReportsNL320WithLockeeSpan()
    {
        // NL320 (the CS0185 analog): a value-typed lockee is a check-time error — before this rule the program built clean and segfaulted the whole process inside Monitor.Enter.
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    n := 5
    lock n {
        print(n)
    }
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);

            var doc = JsonDocument.Parse(stdout);
            var diagnostic = doc.RootElement.GetProperty("results").EnumerateArray()
                .Single(result => result.GetProperty("code").GetString() == "NL320");

            Assert.Equal(3, diagnostic.GetProperty("line").GetInt32()); // Underlines the lockee expression itself.
            Assert.Equal(10, diagnostic.GetProperty("column").GetInt32());
            Assert.Equal(1, diagnostic.GetProperty("length").GetInt32());
            Assert.Contains("'int'", diagnostic.GetProperty("message").GetString());
            Assert.Equal("https://schneidenbach.github.io/nsharplang/docs/errors/NL320", diagnostic.GetProperty("docsUrl").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_ReturnInsideFinally_ReportsNL319OnTheKeyword()
    {
        // NL319 (the CS0157 analog): control may not leave a finally — before this rule the program built clean and threw InvalidProgramException on every call.
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Main() {
    n := 0
    try {
        n = n + 1
    } finally {
        return
    }
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);

            var doc = JsonDocument.Parse(stdout);
            var diagnostic = doc.RootElement.GetProperty("results").EnumerateArray()
                .Single(result => result.GetProperty("code").GetString() == "NL319");

            Assert.Equal(6, diagnostic.GetProperty("line").GetInt32()); // Underlines the full `return` keyword.
            Assert.Equal("return".Length, diagnostic.GetProperty("length").GetInt32());
            Assert.Equal("https://schneidenbach.github.io/nsharplang/docs/errors/NL319", diagnostic.GetProperty("docsUrl").GetString());
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
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), UnresolvedTypeProgram);

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
        Assert.Contains(NormalizePath(Path.GetFullPath(HelloWorldProject)), doc.RootElement.GetProperty("projectRoot").GetString());
    }

    [Fact]
    public void CheckCommand_BackendOption_DoesNotBecomeProjectDir()
    {
        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--backend", "il", HelloWorldProject }));

        Assert.Equal(0, exitCode);
        Assert.True(string.IsNullOrWhiteSpace(stderr));
        var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        Assert.Contains(NormalizePath(Path.GetFullPath(HelloWorldProject)), doc.RootElement.GetProperty("projectRoot").GetString());
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
                var lineA = results[i].GetProperty("line").GetInt32();
                var lineB = results[i + 1].GetProperty("line").GetInt32();
                Assert.True(cmp < 0 || (cmp == 0 && lineA <= lineB),
                    $"Diagnostics not sorted by file then line: {fileA}:{lineA} before {fileB}:{lineB}");
            }
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Backend verification ─────────────────────────────────────────────

    [Fact]
    public void CheckCommand_CleanProject_PassesWithIlVerification()
    {
        // This test exercises the full pipeline: analysis + IL backend verification. If backend verification breaks, it fails even though analysis alone passes.
        var (exitCode, stdout, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", HelloWorldProject }));

        Assert.Equal(0, exitCode);
        var doc = JsonDocument.Parse(stdout);
        Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
    }

    [Fact]
    public void CheckCommand_CleanProject_TextMode_PassesWithVerification()
    {
        var (exitCode, _, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", HelloWorldProject, "--text" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("no errors", stderr);
    }

    [Fact]
    public void CheckCommand_AotVerificationRequiresColumnarWhenColumnarDeclines()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: AotCheckRequiresColumnar
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func countChars(s: string): int {
    n := 0
    foreach c in s {
        n = n + 1
    }
    return n
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir, "--aot" }));

            Assert.Equal(1, exitCode);
            using var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            var messages = doc.RootElement.GetProperty("results").EnumerateArray()
                .Select(result => result.GetProperty("message").GetString()).ToArray();
            Assert.Contains(messages, message =>
                message?.Contains("Columnar AOT emission is required", StringComparison.Ordinal) == true);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_AotProjectReferenceRequiresColumnarWhenColumnarDeclines()
    {
        var tempDir = CreateTempDir();
        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);

            var sharedDir = Path.Combine(tempDir, "Shared");
            Directory.CreateDirectory(sharedDir);
            TestSdkFeed.WriteVersionedSdkProject(sharedDir, "SharedLib");
            File.WriteAllText(Path.Combine(sharedDir, "project.yml"), """
name: SharedLib
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(sharedDir, "Shared.nl"), """
func CountChars(s: string): int {
    n := 0
    foreach c in s {
        n = n + 1
    }
    return n
}
""");

            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: App
outputType: library
targetFramework: net10.0
dependencies:
  - project: Shared/project.yml
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Root(): int {
    return 1
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir, "--aot" }));

            Assert.Equal(1, exitCode);
            Assert.Contains("AOT builds require successful N# columnar emission", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_ProjectYmlNative_DoesNotCreateGeneratedCsproj()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CheckNative
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "check"
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);
            using var doc = JsonDocument.Parse(stdout);
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_ReceiverStyleGenericFunction_ReportsDiagnosticsInsteadOfCrashing()
    {
        // Regression: the IL-verification step used to surface an unhandled NotImplementedException as the crash envelope "Check failed: The
        // method or operation is not implemented." for any project declaring a receiver-style (`this`-parameter) generic function. The persisted-emit
        // generic parameter T does not implement Type.IsSZArray, so preflight typing of `value.ToString()` receivers must probe it via
        // IsSafeSzArrayType instead of the raw property. The shape is not yet modeled by the columnar backend, so the correct outcome is the
        // normal diagnostic result shape carrying its NL103 decline.
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ReceiverGenericCheck
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
namespace W

import System

func Tag<T>(this value: T, note: string): string { return note + value.ToString() }
func main() { Console.WriteLine(5.Tag("ok")) }
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);
            using var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.TryGetProperty("error", out _), stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(1, exitCode);

            var decline = Assert.Single(doc.RootElement.GetProperty("results").EnumerateArray());
            Assert.Equal("NL103", decline.GetProperty("code").GetString());
            Assert.Contains("instance call 'T.ToString'", decline.GetProperty("message").GetString());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_VerificationDoesNotRunWhenAnalysisHasErrors()
    {
        // When analysis already found errors, we skip the verification step entirely; this ensures we don't crash or hang trying to verify broken code.
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), UnresolvedTypeProgram);

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(1, exitCode);
            var doc = JsonDocument.Parse(stdout);
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
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

        throw new DirectoryNotFoundException("Could not find examples directory.");
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

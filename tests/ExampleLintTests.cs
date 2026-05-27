using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Comprehensive tests that verify each example project passes linting
/// and that lint rules (especially NL010 unused imports) work correctly
/// on real-world N# code patterns.
/// </summary>
[Collection("ProcessState")]
public class ExampleLintTests
{
    private static readonly string ExamplesDir = FindExamplesDir();

    // ── NL010: Print is a language primitive — does NOT require import System ──

    [Fact]
    public void NL010_PrintStatement_SystemImportFlaggedAsUnused()
    {
        // print is a language primitive (like int, string). The C# exporter
        // auto-injects 'using System;', so the user never needs import System
        // just for print.
        var source = @"
import System

func main() {
    print ""Hello, world!""
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_PrintOnly_SystemImportFlagged()
    {
        var source = @"
import System

func main() {
    name := ""Alice""
    print $""Hello, {name}!""
    print ""Done""
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_SystemImport_NoUsage_IsFlagged()
    {
        var source = @"
import System

func main() {
    x := 5
    y := x + 1
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedSystemCollectionsGeneric_IsFlagged()
    {
        var source = @"
import System.Collections.Generic

func main() {
    x := 5
    y := x + 1
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UsedSystemCollectionsGeneric_NotFlagged()
    {
        var source = @"
import System.Collections.Generic

func main() {
    items := new List<int>()
    count := items.Count
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_SystemCollectionsGeneric_WithIAsyncEnumerable_NotFlagged()
    {
        var source = @"
import System.Collections.Generic
import System.Threading.Tasks

async func* GetNumbers(): IAsyncEnumerable<int> {
    await Task.Delay(100)
    yield 1
}

func main() {
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010" &&
            d.Message.Contains("System.Collections.Generic"));
    }

    [Fact]
    public void NL010_SystemLinq_WithoutUsage_Flagged()
    {
        // System.Linq is now properly tracked via known types (Enumerable,
        // IQueryable, etc.) and known members (extension methods like .Where,
        // .Select). Unused import should be flagged.
        var source = @"
import System.Linq

func main() {
    x := 5
    y := x + 1
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_SystemImport_WithDateTime_NotFlagged()
    {
        var source = @"
import System

func main() {
    now := DateTime.Now
    print $""Time: {now}""
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_SystemImport_WithException_NotFlagged()
    {
        var source = @"
import System

func main() {
    throw new Exception(""error"")
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_SystemImport_WithArgumentException_NotFlagged()
    {
        var source = @"
import System

func Validate(x: int) {
    if x < 0 {
        throw new ArgumentException(""must be non-negative"")
    }
}

func main() {
    Validate(1)
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_SystemImport_WithEnvironment_NotFlagged()
    {
        var source = @"
import System

func main() {
    args := Environment.GetCommandLineArgs()
    x := args
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_MultipleImports_OnlyUnusedFlagged()
    {
        var source = @"
import System
import System.Collections.Generic
import System.Text

func main() {
    items := new List<int>()
    count := items.Count
}";
        var diagnostics = Lint(source);
        // System.Collections.Generic is used (List)
        // System.Text is NOT used (no StringBuilder)
        // System is NOT used (no DateTime/Console/etc...)
        var nl010s = diagnostics.Where(d => d.Code == "NL010").ToList();
        Assert.True(nl010s.Count >= 1, "Should flag at least one unused import");
        Assert.Contains(nl010s, d => d.Message.Contains("System.Text"));
    }

    [Fact]
    public void NL010_UnknownNamespace_NotFlagged()
    {
        var source = @"
import MyCustom.Namespace

func main() {
    x := 5
    y := x + 1
}";
        var diagnostics = Lint(source);
        // Unknown namespaces are conservatively marked as used
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    // ── NL010: File import usage detection ──────────────────────────

    [Fact]
    public void NL010_FileImport_UsedType_NotFlagged()
    {
        // Create temp directory with two files
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Models.nl"), @"
class User {
    Name: string
}
");
            var mainPath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(mainPath, @"
import ""Models""

func main() {
    u := new User { Name: ""Alice"" }
    print u.Name
}
");
            var diagnostics = LintFile(mainPath);
            Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void NL010_FileImport_UnusedType_IsFlagged()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "Models.nl"), @"
class User {
    Name: string
}
");
            var mainPath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(mainPath, @"
import ""Models""

func main() {
    print ""Hello""
}
");
            var diagnostics = LintFile(mainPath);
            Assert.Contains(diagnostics, d => d.Code == "NL010");
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Example project validation via nlc check ────────────────────

    [Theory]
    [InlineData("01-hello-world")]
    [InlineData("03-functions")]
    [InlineData("04-pattern-matching")]
    [InlineData("05-unions")]
    [InlineData("06-classes-and-records")]
    [InlineData("07-interfaces")]
    [InlineData("08-async")]
    [InlineData("09-linq-and-collections")]
    [InlineData("10-interop")]
    [InlineData("11-advanced-features")]
    [InlineData("14-minimal-api")]
    public void NlcCheck_SingleFileExamples_NoErrors(string exampleDir)
    {
        var projectPath = Path.Combine(ExamplesDir, exampleDir);
        if (!Directory.Exists(projectPath))
        {
            // Skip if directory doesn't exist (e.g., running from a different location)
            return;
        }

        var (exitCode, stdout, stderr) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", projectPath }));

        var doc = JsonDocument.Parse(stdout);
        var errors = doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32();
        Assert.True(errors == 0, $"Expected no errors from nlc check. Exit code: {exitCode}\nstdout:\n{stdout}\nstderr:\n{stderr}");
    }

    [Theory]
    [InlineData("12-multi-file-projects/AutoDiscovery")]
    [InlineData("12-multi-file-projects/MultiFileProject")]
    [InlineData("12-multi-file-projects/SimpleProject")]
    [InlineData("12-multi-file-projects/TestExample")]
    [InlineData("12-multi-file-projects/WeatherDemo")]
    [InlineData("12-multi-file-projects/imports")]
    public void NlcCheck_MultiFileExamples_NoErrors(string exampleDir)
    {
        var projectPath = Path.Combine(ExamplesDir, exampleDir);
        if (!Directory.Exists(projectPath))
            return;

        var (exitCode, stdout, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", projectPath }));

        var doc = JsonDocument.Parse(stdout);
        var errors = doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32();
        Assert.Equal(0, errors);
    }

    [Fact]
    public void NlcCheck_TaskCli_NoErrors()
    {
        var projectPath = Path.Combine(ExamplesDir, "16-task-cli");
        if (!Directory.Exists(projectPath))
            return;

        var (exitCode, stdout, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", projectPath }));

        var doc = JsonDocument.Parse(stdout);
        var errors = doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32();
        Assert.Equal(0, errors);
    }

    [Fact]
    public void NlcCheck_IssueTrackerBackend_NoErrors()
    {
        var projectPath = Path.Combine(ExamplesDir, "17-issue-tracker", "backend");
        if (!Directory.Exists(projectPath))
            return;

        var (exitCode, stdout, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", projectPath }));

        var doc = JsonDocument.Parse(stdout);
        var errors = doc.RootElement.GetProperty("summary").GetProperty("errors").GetInt32();
        Assert.Equal(0, errors);
    }

    // ── No NL010 errors on any example ──────────────────────────────

    [Fact]
    public void NlcCheck_TaskCli_NoUnusedImportWarnings()
    {
        var projectPath = Path.Combine(ExamplesDir, "16-task-cli");
        if (!Directory.Exists(projectPath))
            return;

        var (_, stdout, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", projectPath }));

        var doc = JsonDocument.Parse(stdout);
        var results = doc.RootElement.GetProperty("results");
        foreach (var result in results.EnumerateArray())
        {
            var code = result.GetProperty("code").GetString();
            if (code == "NL010")
            {
                var file = result.GetProperty("file").GetString();
                var message = result.GetProperty("message").GetString();
                Assert.Fail($"Unexpected unused import warning in {file}: {message}");
            }
        }
    }

    [Fact]
    public void NlcCheck_IssueTracker_NoUnusedImportWarnings()
    {
        var projectPath = Path.Combine(ExamplesDir, "17-issue-tracker", "backend");
        if (!Directory.Exists(projectPath))
            return;

        var (_, stdout, _) = CaptureConsole(() =>
            CheckCommand.Execute(new[] { "--project", projectPath }));

        var doc = JsonDocument.Parse(stdout);
        var results = doc.RootElement.GetProperty("results");
        foreach (var result in results.EnumerateArray())
        {
            var code = result.GetProperty("code").GetString();
            if (code == "NL010")
            {
                var file = result.GetProperty("file").GetString();
                var message = result.GetProperty("message").GetString();
                Assert.Fail($"Unexpected unused import warning in {file}: {message}");
            }
        }
    }

    // ── Verify specific lint rules on example patterns ──────────────

    [Fact]
    public void Lint_UnionMatchExhaustive_NoWarnings()
    {
        // Pattern from issue-tracker Models.nl: exhaustive match on union
        var source = @"
union IssueError {
    NotFound { id: int }
    InvalidTransition { from: string, to: string }
    ValidationFailed { field: string, reason: string }
}

func FormatError(err: IssueError): string {
    return match err {
        IssueError.NotFound { id } => $""Issue #{id} not found"",
        IssueError.InvalidTransition { from, to } => $""Cannot move from {from} to {to}"",
        IssueError.ValidationFailed { field, reason } => $""{field}: {reason}""
    }
}

func main() {
    msg := FormatError(new IssueError.NotFound(1))
    print msg
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void Lint_RecordWithMethods_NoWarnings()
    {
        // Pattern from task-cli: record with methods
        // No import System needed — print is a language primitive
        var source = @"
record TaskItem {
    Id: int
    Title: string

    func GetInfo(): string {
        return $""#{Id}: {Title}""
    }
}

func main() {
    task := new TaskItem { Id: 1, Title: ""Test"" }
    print task.GetInfo()
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void Lint_DuckInterface_NoWarnings()
    {
        // Pattern from issue-tracker: duck interfaces
        var source = @"
import System.Collections.Generic

duck interface INotifier {
    func Notify(message: string)
}

class ConsoleNotifier {
    func Notify(message: string) {
        print message
    }
}

class Hub {
    notifiers: List<INotifier>

    constructor() {
        notifiers = new List<INotifier>()
    }

    func Register(n: ConsoleNotifier) {
        notifiers.Add(n)
    }
}

func main() {
    hub := new Hub()
    hub.Register(new ConsoleNotifier())
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void Lint_ErrorTuples_NoWarnings()
    {
        // Pattern from examples: Go-style error handling
        var source = @"
import System

func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception(""Cannot divide by zero"")
    }
    return a / b
}

func main() {
    result, err := Divide(10, 2)
    if err == null {
        print $""Result: {result}""
    } else {
        print $""Error: {err.Message}""
    }
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void Lint_ClassWithStaticMethods_NoWarnings()
    {
        // Pattern that was in task-cli: class with all static methods
        // No import System needed — print is a primitive, StringBuilder is System.Text
        var source = @"
import System.Text

class Formatter {
    static func FormatHeader(): string {
        sb := new StringBuilder()
        sb.Append(""ID"".PadRight(5))
        sb.Append(""Title"".PadRight(30))
        return sb.ToString()
    }
}

func main() {
    header := Formatter.FormatHeader()
    print header
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    // ── NL002: Missing import detection ─────────────────────────────

    [Fact]
    public void NL002_MissingImport_ListWithoutGenericImport()
    {
        var source = @"
func main() {
    items := new List<int>()
    x := items
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL002");
    }

    [Fact]
    public void NL002_NoWarning_WhenImported()
    {
        var source = @"
import System.Collections.Generic

func main() {
    items := new List<int>()
    x := items
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL002");
    }

    [Fact]
    public void NL002_MissingImport_StringBuilderWithoutTextImport()
    {
        var source = @"
func main() {
    sb := new StringBuilder()
    x := sb
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL002");
    }

    // ── Helpers ─────────────────────────────────────────────────────

    private static List<Diagnostic> Lint(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();
        var linter = new Linter();
        return linter.Lint(result.CompilationUnit!, "test.nl");
    }

    private static List<Diagnostic> LintFile(string filePath)
    {
        var source = File.ReadAllText(filePath);
        var lexer = new Lexer(source, filePath);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, filePath, source);
        var result = parser.ParseCompilationUnit();
        var linter = new Linter();
        return linter.Lint(result.CompilationUnit!, filePath);
    }

    private static string CreateTempDir()
    {
        var path = Path.Combine(Path.GetTempPath(), $"nsharp-lint-{Guid.NewGuid():N}");
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
}

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace NSharpLang.Cli.Commands;

public static class TutorialCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help", StringComparer.Ordinal) ||
            args.Contains("-h", StringComparer.Ordinal) ||
            (args.Length > 0 && args[0] == "help"))
        {
            return ShowHelp();
        }

        if (!TutorialOptions.TryParse(args, out var options, out var error))
        {
            return Error(error);
        }

        if (!IsLoopbackHost(options.Host))
        {
            return Error("nlc tutorial only binds to loopback hosts. Use 127.0.0.1, localhost, or ::1.");
        }

        try
        {
            var runtime = new TutorialRuntime(options.Workspace);
            runtime.Initialize(options.Reset);

            if (options.DryRun)
            {
                Console.WriteLine("N# tutorial workspace is ready.");
                Console.WriteLine($"Workspace: {runtime.WorkspaceRoot}");
                Console.WriteLine($"Lessons:   {TutorialCatalog.Lessons.Count}");
                Console.WriteLine("Run `nlc tutorial` to start the local walkthrough.");
                return 0;
            }

            return RunServerAsync(options, runtime).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            return Error($"Tutorial failed: {ex.Message}");
        }
    }

    private static async Task<int> RunServerAsync(TutorialOptions options, TutorialRuntime runtime)
    {
        Console.WriteLine("Preparing local N# tutorial server...");
#pragma warning disable ASPDEPR004, ASPDEPR008
        // WebApplicationBuilder currently blocks in the dotnet-tool host path here.
        // This is still ASP.NET Core/Kestrel; the lower-level builder keeps startup deterministic.
        var host = new WebHostBuilder()
            .UseKestrel(serverOptions =>
            {
                serverOptions.Listen(ResolveListenAddress(options.Host), options.Port);
            })
            .Configure(app =>
            {
                app.Run(context => TutorialRouter.HandleAsync(context, runtime));
            })
            .Build();
#pragma warning restore ASPDEPR004, ASPDEPR008

        var stop = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        ConsoleCancelEventHandler cancelHandler = (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            stop.TrySetResult();
        };

        Console.CancelKeyPress += cancelHandler;
        try
        {
            Console.WriteLine("Starting local N# tutorial server...");
            await host.StartAsync();
            var url = host.Services.GetRequiredService<IServer>()
                .Features.Get<IServerAddressesFeature>()
                ?.Addresses.FirstOrDefault()
                ?? $"http://{FormatHostForUrl(options.Host)}:{options.Port}";

            Console.WriteLine("N# tutorial is running locally.");
            Console.WriteLine($"URL:       {url}");
            Console.WriteLine($"Workspace: {runtime.WorkspaceRoot}");
            Console.WriteLine("Press Ctrl+C to stop.");

            if (options.OpenBrowser)
            {
                TryOpenBrowser(url);
            }

            await stop.Task;
            await host.StopAsync();
            return 0;
        }
        finally
        {
            Console.CancelKeyPress -= cancelHandler;
            host.Dispose();
        }
    }

    private static bool IsLoopbackHost(string host)
        => string.Equals(host, "127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
           string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase) ||
           string.Equals(host, "::1", StringComparison.OrdinalIgnoreCase) ||
           string.Equals(host, "[::1]", StringComparison.OrdinalIgnoreCase);

    private static string FormatHostForUrl(string host)
        => host == "::1" ? "[::1]" : host;

    private static IPAddress ResolveListenAddress(string host)
        => host is "::1" or "[::1]" ? IPAddress.IPv6Loopback : IPAddress.Loopback;

    private static void TryOpenBrowser(string url)
    {
        try
        {
            var fileName = OperatingSystem.IsWindows() ? "cmd" :
                OperatingSystem.IsMacOS() ? "open" : "xdg-open";
            var arguments = OperatingSystem.IsWindows() ? $"/c start \"\" \"{url}\"" : url;

            Process.Start(new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true
            });
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Could not open browser automatically: {ex.Message}");
        }
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# Tutorial

Usage: nlc tutorial [options]

Start a local, loopback-only walkthrough that introduces N# with runnable
lessons, editor diagnostics, completions, hover, run, format, and test actions
backed by the `nlc` command line (`nlc query`, `nlc run`, `nlc test`).

Options:
  --host <host>       Loopback host to bind (default: 127.0.0.1)
  --port <port>       Port to bind, or 0 for an available port (default: 0)
  --workspace <dir>   Tutorial state directory (default: user-local app data)
  --reset             Recreate the tutorial workspace before starting
  --open              Open the tutorial URL in the default browser
  --dry-run           Create/update lesson workspaces without starting a server
  --help, -h          Show this help text

Examples:
  nlc tutorial
  nlc tutorial --open
  nlc tutorial --port 5055
  nlc tutorial --workspace ./.nlc/tutorial --dry-run

Exit codes:
  0  Tutorial server stopped cleanly or dry-run succeeded
  1  Tutorial startup failed");
        return 0;
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine($"Error: {message}");
        return 1;
    }
}

internal sealed record TutorialOptions(
    string Host,
    int Port,
    string Workspace,
    bool Reset,
    bool OpenBrowser,
    bool DryRun)
{
    public static bool TryParse(string[] args, out TutorialOptions options, out string error)
    {
        var host = "127.0.0.1";
        var port = 0;
        var workspace = DefaultWorkspace();
        var reset = false;
        var openBrowser = false;
        var dryRun = false;

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--host":
                    if (!TryReadValue(args, ref i, out host))
                    {
                        return Fail(out options, out error, "--host requires a value.");
                    }
                    break;
                case "--port":
                    if (!TryReadValue(args, ref i, out var portValue) ||
                        !int.TryParse(portValue, out port) ||
                        port < 0 || port > 65535)
                    {
                        return Fail(out options, out error, "--port requires a value between 0 and 65535.");
                    }
                    break;
                case "--workspace":
                    if (!TryReadValue(args, ref i, out workspace))
                    {
                        return Fail(out options, out error, "--workspace requires a directory path.");
                    }
                    workspace = Path.GetFullPath(workspace);
                    break;
                case "--reset":
                    reset = true;
                    break;
                case "--open":
                    openBrowser = true;
                    break;
                case "--no-open":
                    openBrowser = false;
                    break;
                case "--dry-run":
                    dryRun = true;
                    break;
                default:
                    return Fail(out options, out error, $"Unknown option: {args[i]}. Run 'nlc tutorial --help' for usage.");
            }
        }

        options = new TutorialOptions(host, port, workspace, reset, openBrowser, dryRun);
        error = string.Empty;
        return true;
    }

    private static bool TryReadValue(string[] args, ref int index, out string value)
    {
        if (index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal))
        {
            value = string.Empty;
            return false;
        }

        index++;
        value = args[index];
        return true;
    }

    private static bool Fail(out TutorialOptions options, out string error, string message)
    {
        options = new TutorialOptions("127.0.0.1", 0, DefaultWorkspace(), false, false, false);
        error = message;
        return false;
    }

    private static string DefaultWorkspace()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(root))
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            root = string.IsNullOrWhiteSpace(home) ? Path.GetTempPath() : home;
        }

        return Path.Combine(root, "NSharpLang", "tutorial");
    }
}

internal static class TutorialRouter
{
    public static async Task HandleAsync(HttpContext context, TutorialRuntime runtime)
    {
        try
        {
            var path = context.Request.Path.Value?.Trim('/') ?? string.Empty;
            var segments = path.Length == 0
                ? Array.Empty<string>()
                : path.Split('/', StringSplitOptions.RemoveEmptyEntries);

            if (IsGet(context, segments, Array.Empty<string>()))
            {
                await WriteAssetAsync(context, "index.html", "text/html; charset=utf-8");
                return;
            }

            if (IsGet(context, segments, new[] { "assets", "app.js" }))
            {
                await WriteAssetAsync(context, "app.js", "text/javascript; charset=utf-8");
                return;
            }

            if (IsGet(context, segments, new[] { "assets", "styles.css" }))
            {
                await WriteAssetAsync(context, "styles.css", "text/css; charset=utf-8");
                return;
            }

            if (IsGet(context, segments, new[] { "source", "app.tsx" }))
            {
                await WriteAssetAsync(context, "app.tsx", "text/typescript; charset=utf-8");
                return;
            }

            if (IsGet(context, segments, new[] { "api", "health" }))
            {
                await WriteJsonAsync(context, new
                {
                    ok = true,
                    command = "tutorial",
                    workspaceRoot = NormalizePath(runtime.WorkspaceRoot)
                });
                return;
            }

            if (IsGet(context, segments, new[] { "api", "lessons" }))
            {
                await WriteJsonAsync(context, runtime.GetCatalog());
                return;
            }

            if (segments.Length == 4 &&
                IsMethod(context, HttpMethods.Get) &&
                segments[0] == "api" &&
                segments[1] == "lessons" &&
                segments[3] == "code")
            {
                var lesson = TutorialCatalog.Find(segments[2]);
                if (lesson == null)
                {
                    await WriteNotFoundAsync(context, $"Unknown lesson '{segments[2]}'.");
                    return;
                }

                await WriteJsonAsync(context, runtime.GetCode(lesson));
                return;
            }

            if (segments.Length == 4 &&
                IsMethod(context, HttpMethods.Post) &&
                segments[0] == "api" &&
                segments[1] == "lessons")
            {
                await HandleLessonPostAsync(context, runtime, segments[2], segments[3]);
                return;
            }

            await WriteNotFoundAsync(context, "Route not found.");
        }
        catch (JsonException ex)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await WriteJsonAsync(context, new { ok = false, error = $"Invalid JSON request body: {ex.Message}" });
        }
        catch (Exception ex)
        {
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            await WriteJsonAsync(context, new { ok = false, error = ex.Message });
        }
    }

    private static async Task HandleLessonPostAsync(HttpContext context, TutorialRuntime runtime, string lessonId, string action)
    {
        var lesson = TutorialCatalog.Find(lessonId);
        if (lesson == null)
        {
            await WriteNotFoundAsync(context, $"Unknown lesson '{lessonId}'.");
            return;
        }

        switch (action)
        {
            case "code":
            {
                var request = await ReadJsonAsync<CodeRequest>(context) ?? new CodeRequest(null);
                runtime.SaveCode(lesson, request.Code ?? string.Empty);
                await WriteJsonAsync(context, runtime.GetCode(lesson));
                return;
            }
            case "diagnostics":
            {
                var request = await ReadJsonAsync<CodeRequest>(context) ?? new CodeRequest(null);
                runtime.SaveCode(lesson, request.Code ?? string.Empty);
                await WriteJsonAsync(context, await runtime.RunDiagnosticsAsync(lesson));
                return;
            }
            case "completions":
            {
                var request = await ReadJsonAsync<CompletionRequest>(context) ?? new CompletionRequest(null, 1, 0);
                runtime.SaveCode(lesson, request.Code ?? string.Empty);
                await WriteJsonAsync(context, await runtime.RunCompletionsAsync(lesson, request.Line, request.Column));
                return;
            }
            case "hover":
            {
                var request = await ReadJsonAsync<CompletionRequest>(context) ?? new CompletionRequest(null, 1, 0);
                runtime.SaveCode(lesson, request.Code ?? string.Empty);
                await WriteJsonAsync(context, await runtime.RunHoverAsync(lesson, request.Line, request.Column));
                return;
            }
            case "run":
            {
                var request = await ReadJsonAsync<CodeRequest>(context) ?? new CodeRequest(null);
                runtime.SaveCode(lesson, request.Code ?? string.Empty);
                await WriteJsonAsync(context, await runtime.RunProgramAsync(lesson));
                return;
            }
            case "test":
            {
                var request = await ReadJsonAsync<CodeRequest>(context) ?? new CodeRequest(null);
                runtime.SaveCode(lesson, request.Code ?? string.Empty);
                await WriteJsonAsync(context, await runtime.RunTestsAsync(lesson));
                return;
            }
            case "format":
            {
                var request = await ReadJsonAsync<CodeRequest>(context) ?? new CodeRequest(null);
                runtime.SaveCode(lesson, request.Code ?? string.Empty);
                var result = await runtime.RunFormatAsync(lesson);
                await WriteJsonAsync(context, result with { Code = runtime.GetCode(lesson).Code });
                return;
            }
            default:
                await WriteNotFoundAsync(context, $"Unknown lesson action '{action}'.");
                return;
        }
    }

    private static bool IsGet(HttpContext context, string[] actual, string[] expected)
        => IsMethod(context, HttpMethods.Get) && actual.SequenceEqual(expected, StringComparer.Ordinal);

    private static bool IsMethod(HttpContext context, string method)
        => string.Equals(context.Request.Method, method, StringComparison.OrdinalIgnoreCase);

    private static async Task<T?> ReadJsonAsync<T>(HttpContext context)
        => await JsonSerializer.DeserializeAsync<T>(context.Request.Body, new JsonSerializerOptions(JsonSerializerDefaults.Web));

    private static async Task WriteAssetAsync(HttpContext context, string name, string contentType)
    {
        context.Response.StatusCode = StatusCodes.Status200OK;
        context.Response.ContentType = contentType;
        await context.Response.WriteAsync(TutorialAssets.ReadWebAsset(name));
    }

    private static async Task WriteJsonAsync(HttpContext context, object value)
    {
        context.Response.ContentType = "application/json; charset=utf-8";
        await JsonSerializer.SerializeAsync(context.Response.Body, value, new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            WriteIndented = true
        });
    }

    private static Task WriteNotFoundAsync(HttpContext context, string message)
    {
        context.Response.StatusCode = StatusCodes.Status404NotFound;
        return WriteJsonAsync(context, new { ok = false, error = message });
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

internal sealed class TutorialRuntime
{
    private const string ProgramFileName = "Program.nl";
    private const string TestFileName = "Program.tests.nl";

    public TutorialRuntime(string workspaceRoot)
    {
        WorkspaceRoot = Path.GetFullPath(workspaceRoot);
    }

    public string WorkspaceRoot { get; }

    public void Initialize(bool reset)
    {
        if (reset && Directory.Exists(WorkspaceRoot))
        {
            Directory.Delete(WorkspaceRoot, recursive: true);
        }

        Directory.CreateDirectory(WorkspaceRoot);
        Directory.CreateDirectory(GetLessonsRoot());
        File.WriteAllText(Path.Combine(WorkspaceRoot, "README.md"), WorkspaceReadme());

        foreach (var lesson in TutorialCatalog.Lessons)
        {
            EnsureLessonWorkspace(lesson);
        }
    }

    public object GetCatalog()
    {
        return new
        {
            schemaVersion = 1,
            ok = true,
            workspaceRoot = NormalizePath(WorkspaceRoot),
            estimatedMinutes = TutorialCatalog.Lessons.Sum(lesson => lesson.Minutes),
            lessons = TutorialCatalog.Lessons.Select(lesson => new
            {
                lesson.Id,
                lesson.Title,
                lesson.Summary,
                lesson.Minutes,
                lesson.Goal,
                lesson.Concepts,
                lesson.CSharpContrast,
                lesson.HasTests
            })
        };
    }

    public CodeResponse GetCode(TutorialLesson lesson)
    {
        EnsureLessonWorkspace(lesson);
        return new CodeResponse(
            LessonId: lesson.Id,
            File: NormalizePath(Path.Combine(GetLessonDirectory(lesson), ProgramFileName)),
            Code: File.ReadAllText(Path.Combine(GetLessonDirectory(lesson), ProgramFileName)),
            TestsFile: lesson.HasTests ? NormalizePath(Path.Combine(GetLessonDirectory(lesson), TestFileName)) : null,
            Tests: lesson.TestsCode);
    }

    public void SaveCode(TutorialLesson lesson, string code)
    {
        EnsureLessonWorkspace(lesson);
        File.WriteAllText(Path.Combine(GetLessonDirectory(lesson), ProgramFileName), NormalizeNewlines(code));
    }

    public Task<ToolResult> RunDiagnosticsAsync(TutorialLesson lesson)
        => RunNlcAsync(lesson, new[] { "query", "diagnostics", "--project", GetLessonDirectory(lesson), "--file", ProgramFileName }, TimeSpan.FromSeconds(10));

    public Task<ToolResult> RunCompletionsAsync(TutorialLesson lesson, int line, int column)
        => RunNlcAsync(lesson, new[] { "query", "completions", "--project", GetLessonDirectory(lesson), "--file", ProgramFileName, "--pos", $"{Math.Max(line, 1)}:{Math.Max(column, 0)}", "--include-keywords" }, TimeSpan.FromSeconds(10));

    public Task<ToolResult> RunHoverAsync(TutorialLesson lesson, int line, int column)
        => RunNlcAsync(lesson, new[] { "query", "hover", "--project", GetLessonDirectory(lesson), "--file", ProgramFileName, "--pos", $"{Math.Max(line, 1)}:{Math.Max(column, 0)}" }, TimeSpan.FromSeconds(10));

    public Task<ToolResult> RunProgramAsync(TutorialLesson lesson)
        => RunNlcAsync(lesson, new[] { "run" }, TimeSpan.FromSeconds(12));

    public Task<ToolResult> RunTestsAsync(TutorialLesson lesson)
        => RunNlcAsync(lesson, new[] { "test", "--project", GetLessonDirectory(lesson), "--verbose" }, TimeSpan.FromSeconds(20));

    public async Task<ToolResult> RunFormatAsync(TutorialLesson lesson)
    {
        var result = await RunNlcAsync(lesson, new[] { "format", "--project", GetLessonDirectory(lesson), ProgramFileName }, TimeSpan.FromSeconds(10));
        return result;
    }

    private async Task<ToolResult> RunNlcAsync(TutorialLesson lesson, IReadOnlyList<string> nlcArgs, TimeSpan timeout)
    {
        EnsureLessonWorkspace(lesson);
        var invocation = NlcInvocation.Create(nlcArgs);
        var psi = new ProcessStartInfo
        {
            FileName = invocation.FileName,
            WorkingDirectory = GetLessonDirectory(lesson),
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var arg in invocation.Arguments)
        {
            psi.ArgumentList.Add(arg);
        }

        psi.Environment["DOTNET_SKIP_FIRST_TIME_EXPERIENCE"] = "1";
        psi.Environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1";

        var command = invocation.ToDisplayString();
        var sw = Stopwatch.StartNew();
        using var process = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start nlc process.");
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        var exitTask = process.WaitForExitAsync();
        var completed = await Task.WhenAny(exitTask, Task.Delay(timeout));
        var timedOut = completed != exitTask;

        if (timedOut)
        {
            try { process.Kill(entireProcessTree: true); } catch { /* process already exited */ }
        }

        await Task.WhenAll(stdoutTask, stderrTask);
        sw.Stop();

        return new ToolResult(
            Ok: !timedOut && process.ExitCode == 0,
            Command: command,
            ExitCode: timedOut ? -1 : process.ExitCode,
            TimedOut: timedOut,
            DurationMs: (int)sw.Elapsed.TotalMilliseconds,
            Stdout: stdoutTask.Result,
            Stderr: timedOut
                ? stderrTask.Result + $"{Environment.NewLine}Command timed out after {timeout.TotalSeconds:0}s."
                : stderrTask.Result,
            Code: null);
    }

    private void EnsureLessonWorkspace(TutorialLesson lesson)
    {
        var dir = GetLessonDirectory(lesson);
        Directory.CreateDirectory(dir);

        WriteIfChanged(Path.Combine(dir, "project.yml"), $"""
name: NSharpTutorial{SanitizeName(lesson.Id)}
version: 1.0.0
targetFramework: net10.0
entry: {ProgramFileName}
outputType: exe
""");

        WriteIfChanged(Path.Combine(dir, ".gitignore"), """
bin/
obj/
.nlc/
""");

        var programPath = Path.Combine(dir, ProgramFileName);
        if (!File.Exists(programPath))
        {
            File.WriteAllText(programPath, NormalizeNewlines(lesson.StartingCode));
        }

        var testPath = Path.Combine(dir, TestFileName);
        if (!string.IsNullOrWhiteSpace(lesson.TestsCode))
        {
            WriteIfChanged(testPath, NormalizeNewlines(lesson.TestsCode));
        }
        else if (File.Exists(testPath))
        {
            File.Delete(testPath);
        }
    }

    private string GetLessonsRoot() => Path.Combine(WorkspaceRoot, "lessons");

    private string GetLessonDirectory(TutorialLesson lesson)
        => Path.Combine(GetLessonsRoot(), lesson.Id);

    private static void WriteIfChanged(string path, string content)
    {
        content = NormalizeNewlines(content);
        if (File.Exists(path) && string.Equals(File.ReadAllText(path), content, StringComparison.Ordinal))
        {
            return;
        }

        File.WriteAllText(path, content);
    }

    private static string WorkspaceReadme() => """
# N# Tutorial Workspace

This directory is owned by `nlc tutorial`.

Each lesson is a real N# project. The browser editor writes to these files,
then calls `nlc query`, `nlc run`, `nlc format`, and `nlc test` against them.
You can open any lesson directory in VS Code to use the full N# extension too.
""";

    private static string SanitizeName(string value)
        => string.Concat(value.Where(char.IsLetterOrDigit));

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private static string NormalizeNewlines(string text)
        => text.Replace("\r\n", "\n").Replace("\r", "\n");
}

internal sealed record TutorialLesson(
    string Id,
    string Title,
    string Summary,
    int Minutes,
    string Goal,
    string[] Concepts,
    string CSharpContrast,
    string StartingCode,
    string? TestsCode)
{
    public bool HasTests => !string.IsNullOrWhiteSpace(TestsCode);
}

internal static class TutorialCatalog
{
    public static readonly IReadOnlyList<TutorialLesson> Lessons = new[]
    {
        new TutorialLesson(
            "01-hello-world",
            "Hello World",
            "Start with a tiny program, a tested function, and `print`.",
            2,
            "Run the program, then change the greeting and use diagnostics to keep it clean.",
            new[] { "entry point", "print", "string interpolation", "tests" },
            "N# keeps top-level ceremony low: `func main()` plus `print` is enough.",
            """
package Tutorial

func Greeting(name: string): string {
    return $"Hello, {name}!"
}

func main() {
    print Greeting("N#")
}
""",
            """
package Tutorial

test "greets by name" {
    assert Greeting("N#") == "Hello, N#!"
}
"""),

        new TutorialLesson(
            "02-values-functions",
            "Values and Functions",
            "Use short declarations, explicit types, immutable bindings, and expression-bodied helpers.",
            2,
            "Make the receipt line read naturally while preserving the tested total.",
            new[] { "type inference", "let", "explicit types", "expression-bodied functions" },
            "N# puts parameter types after names and uses `:=` for inferred locals, closer to Go than C#.",
            """
package Tutorial

func TotalWithTax(subtotal: double, taxRate: double): double => subtotal + subtotal * taxRate

func ReceiptLine(item: string, subtotal: double): string {
    let taxRate := 0.08
    const total: double = TotalWithTax(subtotal, taxRate)
    return $"{item}: ${total}"
}

func main() {
    print ReceiptLine("Coffee", 25.0)
}
""",
            """
package Tutorial

test "computes total with tax" {
    assert TotalWithTax(25.0, 0.08) == 27.0
}
"""),

        new TutorialLesson(
            "03-types-visibility",
            "Types and Visibility",
            "Build records and classes without access-modifier noise.",
            2,
            "Inspect completions on `todo.` and notice which members are part of the public shape.",
            new[] { "records", "classes", "properties", "visibility by casing", "with expressions" },
            "PascalCase declarations are exported; camelCase declarations stay implementation details.",
            """
package Tutorial

record Todo {
    Id: int
    Title: string
    Done: bool
}

class TodoFormatter(prefix: string) {
    func Format(todo: Todo): string {
        status := "open"
        if todo.Done {
            status = "done"
        }
        return $"{prefix} #{todo.Id}: {todo.Title} ({status})"
    }
}

func Complete(todo: Todo): Todo {
    return todo with { Done: true }
}

func main() {
    todo := new Todo { Id: 1, Title: "Try N#", Done: false }
    formatter := new TodoFormatter("task")
    print formatter.Format(Complete(todo))
}
""",
            """
package Tutorial

test "complete preserves the title" {
    todo := new Todo { Id: 7, Title: "Ship", Done: false }
    done := Complete(todo)
    assert done.Done == true
    assert done.Title == "Ship"
}
"""),

        new TutorialLesson(
            "04-unions-patterns",
            "Unions and Match",
            "Model data that has different shapes, then match exhaustively.",
            2,
            "Add or rename a result case and watch diagnostics point to missing match arms.",
            new[] { "unions", "pattern matching", "exhaustiveness", "typed errors" },
            "Instead of nullable result objects or string error codes, N# lets the type carry each case.",
            """
package Tutorial

union LookupResult {
    Found { name: string, score: int }
    Missing { id: int }
}

func Describe(result: LookupResult): string {
    return match result {
        LookupResult.Found { name, score } => $"{name}: {score}",
        LookupResult.Missing { id } => $"Missing player #{id}"
    }
}

func main() {
    print Describe(new LookupResult.Found("Ada", 99))
    print Describe(new LookupResult.Missing(404))
}
""",
            """
package Tutorial

test "describes union cases" {
    assert Describe(new LookupResult.Found("Ada", 99)) == "Ada: 99"
    assert Describe(new LookupResult.Missing(7)) == "Missing player #7"
}
"""),

        new TutorialLesson(
            "05-duck-typing",
            "Duck Typing",
            "Use a structural interface without declaring implementation on each type.",
            2,
            "Create another greeter with a `Greet` method and pass it to `Welcome` without `: IGreeter`.",
            new[] { "duck interface", "structural typing", "concrete types", "interop-friendly shape" },
            "C# requires nominal interface implementation; N# duck interfaces match by member shape.",
            """
package Tutorial

duck interface IGreeter {
    func Greet(name: string): string
}

class FriendlyGreeter {
    func Greet(name: string): string {
        return $"Welcome, {name}."
    }
}

class ExcitedGreeter {
    func Greet(name: string): string {
        return $"WELCOME, {name.ToUpper()}!"
    }
}

func Welcome(greeter: IGreeter, name: string): string {
    return greeter.Greet(name)
}

func main() {
    print Welcome(new FriendlyGreeter(), "Ada")
    print Welcome(new ExcitedGreeter(), "Grace")
}
""",
            """
package Tutorial

test "accepts any matching concrete greeter" {
    assert Welcome(new FriendlyGreeter(), "Ada") == "Welcome, Ada."
    assert Welcome(new ExcitedGreeter(), "Grace") == "WELCOME, GRACE!"
}
"""),

        new TutorialLesson(
            "06-collections-linq",
            "Collections and LINQ",
            "Use array literals, lambdas, LINQ, ranges, and indexes.",
            1,
            "Ask for completions after `numbers.` or `evens.` to see .NET members through N#.",
            new[] { "arrays", "LINQ", "lambdas", "ranges", "index from end", "C# interop" },
            "N# keeps .NET collections and LINQ available instead of inventing a separate collection world.",
            """
import System.Linq

package Tutorial

func SumEven(numbers: int[]): int {
    return numbers.Where(n => n % 2 == 0).Sum()
}

func Middle(numbers: int[]): int[] {
    return numbers[1..^1]
}

func main() {
    numbers := [1, 2, 3, 4, 5, 6]
    print $"Even sum: {SumEven(numbers)}"
    print $"Last item: {numbers[^1]}"
}
""",
            """
package Tutorial

test "sums even numbers" {
    assert SumEven([1, 2, 3, 4, 5, 6]) == 12
}
"""),

        new TutorialLesson(
            "07-error-handling",
            "Go-Style Error Capture",
            "Capture thrown exceptions as values at the call site.",
            1,
            "Use `result, err :=` and keep the happy path readable without swallowing failures.",
            new[] { "error tuples", "exceptions", "null", "control flow" },
            "N# embraces .NET exceptions but gives a Go-like call-site shape when you want it.",
            """
import System

package Tutorial

func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception("division by zero")
    }

    return a / b
}

func SafeDivide(a: int, b: int): string {
    result, err := Divide(a, b)
    if err != null {
        return err.Message
    }

    return $"result: {result}"
}

func main() {
    print SafeDivide(10, 2)
    print SafeDivide(10, 0)
}
""",
            """
package Tutorial

test "captures divide failures" {
    assert SafeDivide(10, 2) == "result: 5"
    assert SafeDivide(10, 0) == "division by zero"
}
"""),

        new TutorialLesson(
            "08-async-interop",
            "Async and .NET Interop",
            "Call the BCL directly and let async return types stay terse.",
            1,
            "Hover over `LoadMessage` and `Task.Delay` to see N# and .NET symbols together.",
            new[] { "async", "await", "Task", ".NET interop", "imports" },
            "N# async functions read tersely while still producing normal .NET tasks for C# callers.",
            """
import System.Threading.Tasks

package Tutorial

async func LoadMessage(name: string): string {
    await Task.Delay(10)
    return $"Loaded profile for {name}"
}

async func main() {
    message := await LoadMessage("Ada")
    print message
}
""",
            null),

        new TutorialLesson(
            "09-testing",
            "Testing",
            "Write `.tests.nl` checks next to the code they verify.",
            1,
            "Break `Add` and run tests to see the tight red-green loop.",
            new[] { "testing", "test keyword", "assert", "table-driven tests", "nlc test" },
            "N# tests are part of the language surface, not a pile of ceremony around C# attributes.",
            """
package Tutorial

class Calculator {
    static func Add(a: int, b: int): int {
        return a + b
    }

    static func Clamp(value: int, min: int, max: int): int {
        if value < min {
            return min
        }

        if value > max {
            return max
        }

        return value
    }
}

func main() {
    print Calculator.Add(2, 3)
}
""",
            """
package Tutorial

test "adds correctly" with (a: int, b: int, expected: int) [
    (1, 2, 3),
    (0, 0, 0),
    (5, 7, 12)
] {
    assert Calculator.Add(a, b) == expected
}

test "clamps to bounds" {
    assert Calculator.Clamp(-5, 0, 10) == 0
    assert Calculator.Clamp(12, 0, 10) == 10
}
"""),

        new TutorialLesson(
            "10-tooling-loop",
            "The Tooling Loop",
            "Use diagnostics, completions, hover, format, run, and tests together.",
            1,
            "This lesson is intentionally ordinary: the point is the `nlc` feedback loop around it.",
            new[] { "nlc query", "diagnostics", "completions", "hover", "format", "run", "test" },
            "The same semantic services back the CLI, the browser tutorial, and editor tooling.",
            """
package Tutorial

record CommandResult {
    Command: string
    Ok: bool
}

func Explain(result: CommandResult): string {
    return match result.Ok {
        true => $"{result.Command} passed",
        false => $"{result.Command} needs attention"
    }
}

func main() {
    result := new CommandResult { Command: "nlc check", Ok: true }
    print Explain(result)
}
""",
            """
package Tutorial

test "explains command status" {
    assert Explain(new CommandResult { Command: "nlc check", Ok: true }) == "nlc check passed"
    assert Explain(new CommandResult { Command: "nlc test", Ok: false }) == "nlc test needs attention"
}
""")
    };

    public static TutorialLesson? Find(string id)
        => Lessons.FirstOrDefault(lesson => string.Equals(lesson.Id, id, StringComparison.Ordinal));
}

internal sealed record CodeRequest(string? Code);

internal sealed record CompletionRequest(string? Code, int Line, int Column);

internal sealed record CodeResponse(string LessonId, string File, string Code, string? TestsFile, string? Tests);

internal sealed record ToolResult(
    bool Ok,
    string Command,
    int ExitCode,
    bool TimedOut,
    int DurationMs,
    string Stdout,
    string Stderr,
    string? Code);

internal sealed record NlcInvocation(string FileName, IReadOnlyList<string> Arguments)
{
    public static NlcInvocation Create(IReadOnlyList<string> nlcArgs)
    {
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath) &&
            string.Equals(Path.GetFileNameWithoutExtension(processPath), "nlc", StringComparison.OrdinalIgnoreCase))
        {
            return new NlcInvocation(processPath, nlcArgs.ToArray());
        }

        var assemblyPath = typeof(Program).Assembly.Location;
        if (string.IsNullOrWhiteSpace(assemblyPath))
        {
            return new NlcInvocation("nlc", nlcArgs.ToArray());
        }

        return new NlcInvocation("dotnet", new[] { assemblyPath }.Concat(nlcArgs).ToArray());
    }

    public string ToDisplayString()
        => string.Join(" ", new[] { FileName }.Concat(Arguments.Select(QuoteIfNeeded)));

    private static string QuoteIfNeeded(string value)
        => value.Any(char.IsWhiteSpace) ? $"\"{value.Replace("\"", "\\\"")}\"" : value;
}

internal static class TutorialAssets
{
    private const string Prefix = "NSharpLang.Cli.Tutorial.Web.";

    public static string ReadWebAsset(string name)
    {
        var resourceName = Prefix + name;
        var assembly = typeof(TutorialAssets).Assembly;
        using var stream = assembly.GetManifestResourceStream(resourceName);
        if (stream == null)
        {
            var available = string.Join(", ", assembly.GetManifestResourceNames()
                .Where(resource => resource.StartsWith(Prefix, StringComparison.Ordinal))
                .OrderBy(resource => resource));
            throw new FileNotFoundException($"Embedded tutorial asset '{name}' was not found. Available assets: {available}");
        }

        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }
}

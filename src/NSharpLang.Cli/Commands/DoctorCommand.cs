using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace NSharpLang.Cli.Commands;

public static class DoctorCommand
{
    private const string VscodeExtensionId = "nsharp.nsharp";

    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var json = args.Contains("--json");
        var requireVscode = args.Contains("--require-vscode");
        var skipVscode = args.Contains("--skip-vscode");
        var checks = new List<DoctorCheck>();

        var dotnet = FindOnPath("dotnet");
        if (dotnet is null)
        {
            checks.Add(DoctorCheck.Fail("dotnet", "dotnet CLI was not found on PATH", required: true));
        }
        else
        {
            var version = RunCapture("dotnet", "--version");
            checks.Add(version.ExitCode == 0
                ? DoctorCheck.Pass("dotnet", version.Stdout.Trim())
                : DoctorCheck.Fail("dotnet", version.Stderr.TrimOrDefault("dotnet --version failed"), required: true));
        }

        checks.Add(DoctorCheck.Pass("nlc", Program.GetVersion()));

        var toolList = dotnet is null ? ProcessResult.Failed("dotnet not found") : RunCapture("dotnet", "tool list -g");
        checks.Add(CheckGlobalTool(toolList, "NSharpLang.Cli", "nlc global tool"));
        checks.Add(CheckGlobalTool(toolList, "NSharpLang.LanguageServer", "language server tool"));

        var templateList = dotnet is null ? ProcessResult.Failed("dotnet not found") : RunCapture("dotnet", "new list nsharp");
        if (templateList.ExitCode == 0 && templateList.Stdout.Contains("nsharp-console", StringComparison.OrdinalIgnoreCase))
            checks.Add(DoctorCheck.Pass("templates", "nsharp-console template is installed"));
        else
            checks.Add(DoctorCheck.Fail("templates", "nsharp-console template was not found; run the N# installer or dotnet new install NSharpLang.Templates", required: true));

        var lsp = FindOnPath("nsharp-lsp");
        if (lsp is not null)
            checks.Add(DoctorCheck.Pass("language-server", lsp));
        else if (toolList.ExitCode == 0 && toolList.Stdout.Contains("NSharpLang.LanguageServer", StringComparison.OrdinalIgnoreCase))
            checks.Add(DoctorCheck.Warn("language-server", "NSharpLang.LanguageServer is installed but nsharp-lsp is not on PATH; add ~/.dotnet/tools to PATH"));
        else
            checks.Add(DoctorCheck.Fail("language-server", "nsharp-lsp was not found; run the N# installer or dotnet tool install -g NSharpLang.LanguageServer", required: true));

        if (skipVscode)
        {
            checks.Add(DoctorCheck.Warn("vscode-extension", "skipped by --skip-vscode"));
        }
        else
        {
            var code = FindOnPath("code");
            if (code is null)
            {
                checks.Add(requireVscode
                    ? DoctorCheck.Fail("vscode-extension", "VS Code 'code' CLI was not found on PATH", required: true)
                    : DoctorCheck.Warn("vscode-extension", "VS Code 'code' CLI was not found; install VS Code or rerun with --require-vscode on developer machines"));
            }
            else
            {
                var extensions = RunCapture("code", "--list-extensions");
                if (extensions.ExitCode == 0 && extensions.Stdout.Split('\n', '\r').Any(e => string.Equals(e.Trim(), VscodeExtensionId, StringComparison.OrdinalIgnoreCase)))
                    checks.Add(DoctorCheck.Pass("vscode-extension", VscodeExtensionId));
                else
                    checks.Add(DoctorCheck.Fail("vscode-extension", $"{VscodeExtensionId} is not installed; run code --install-extension {VscodeExtensionId}", required: requireVscode));
            }
        }

        var ok = checks.All(c => c.Status != "fail");
        if (json)
            WriteJson(ok, checks);
        else
            WriteText(ok, checks);

        return ok ? 0 : 1;
    }

    private static DoctorCheck CheckGlobalTool(ProcessResult toolList, string packageId, string name)
    {
        if (toolList.ExitCode != 0)
            return DoctorCheck.Fail(name, toolList.Stderr.TrimOrDefault("dotnet tool list -g failed"), required: true);

        return toolList.Stdout.Contains(packageId, StringComparison.OrdinalIgnoreCase)
            ? DoctorCheck.Pass(name, packageId)
            : DoctorCheck.Fail(name, $"{packageId} is not installed as a global tool", required: true);
    }

    private static void WriteText(bool ok, IReadOnlyList<DoctorCheck> checks)
    {
        Console.WriteLine("N# doctor");
        Console.WriteLine(ok ? "status: ok" : "status: problems found");
        Console.WriteLine();
        foreach (var check in checks)
        {
            var marker = check.Status switch { "pass" => "✓", "warn" => "!", _ => "x" };
            Console.WriteLine($"{marker} {check.Name}: {check.Detail}");
        }
    }

    private static void WriteJson(bool ok, IReadOnlyList<DoctorCheck> checks)
    {
        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true });
        writer.WriteStartObject();
        writer.WriteNumber("schemaVersion", 1);
        writer.WriteString("command", "doctor");
        writer.WriteBoolean("ok", ok);
        writer.WriteStartArray("checks");
        foreach (var check in checks)
        {
            writer.WriteStartObject();
            writer.WriteString("name", check.Name);
            writer.WriteString("status", check.Status);
            writer.WriteString("detail", check.Detail);
            writer.WriteBoolean("required", check.Required);
            writer.WriteEndObject();
        }
        writer.WriteEndArray();
        writer.WriteEndObject();
        writer.Flush();
        Console.WriteLine(System.Text.Encoding.UTF8.GetString(stream.ToArray()));
    }

    private static string? FindOnPath(string command)
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        var extensions = OperatingSystem.IsWindows() ? new[] { ".exe", ".cmd", ".bat", string.Empty } : new[] { string.Empty };
        foreach (var dir in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (var extension in extensions)
            {
                var candidate = Path.Combine(dir, command + extension);
                if (File.Exists(candidate))
                    return candidate;
            }
        }
        return null;
    }

    private static ProcessResult RunCapture(string fileName, string arguments)
    {
        try
        {
            using var process = new Process();
            process.StartInfo = new ProcessStartInfo(fileName, arguments)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            process.Start();
            var stdout = process.StandardOutput.ReadToEnd();
            var stderr = process.StandardError.ReadToEnd();
            process.WaitForExit(10_000);
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                return ProcessResult.Failed($"{fileName} {arguments} timed out");
            }
            return new ProcessResult(process.ExitCode, stdout, stderr);
        }
        catch (Exception ex)
        {
            return ProcessResult.Failed(ex.Message);
        }
    }

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# Doctor

Usage: nlc doctor [options]

Verifies the public N# install path: dotnet, nlc, templates, language server,
and the VS Code extension when the VS Code 'code' CLI is available.

Options:
  --json              Output as JSON envelope
  --require-vscode    Treat missing VS Code or missing N# extension as a failure
  --skip-vscode       Skip VS Code extension probing
  --help, -h          Show this help text

Examples:
  nlc doctor
  nlc doctor --require-vscode
  nlc doctor --json --skip-vscode

Exit codes:
  0  Required checks passed
  1  One or more required checks failed");
        return 0;
    }

    private sealed record DoctorCheck(string Name, string Status, string Detail, bool Required)
    {
        public static DoctorCheck Pass(string name, string detail) => new(name, "pass", detail, true);
        public static DoctorCheck Warn(string name, string detail) => new(name, "warn", detail, false);
        public static DoctorCheck Fail(string name, string detail, bool required) => new(name, required ? "fail" : "warn", detail, required);
    }

    private sealed record ProcessResult(int ExitCode, string Stdout, string Stderr)
    {
        public static ProcessResult Failed(string stderr) => new(1, string.Empty, stderr);
    }
}

internal static class DoctorStringExtensions
{
    public static string TrimOrDefault(this string value, string fallback)
    {
        var trimmed = value.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? fallback : trimmed;
    }
}

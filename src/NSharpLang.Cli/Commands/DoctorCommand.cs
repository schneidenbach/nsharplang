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
        var options = GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var outputMode = GetOutputMode(options.Json);
        var requireVscode = options.RequireVscode;
        var skipVscode = options.SkipVscode;
        var checks = new List<DoctorCheck>();

        var dotnet = FindOnPath("dotnet");
        if (dotnet is null)
        {
            checks.Add(DoctorCheck.Fail("dotnet", DoctorCommandKernels.GetDotnetNotFoundMessage(), required: true));
        }
        else
        {
            var version = RunCapture("dotnet", "--version");
            checks.Add(version.ExitCode == 0
                ? DoctorCheck.Pass("dotnet", version.Stdout.Trim())
                : DoctorCheck.Fail(
                    "dotnet",
                    version.Stderr.TrimOrDefault(DoctorCommandKernels.GetDotnetVersionFailedMessage()),
                    required: true));
        }

        checks.Add(DoctorCheck.Pass("nlc", Program.GetVersion()));

        var nlc = FindOnPath("nlc");
        checks.Add(nlc is not null
            ? DoctorCheck.Pass("nlc-command", nlc)
            : DoctorCheck.Warn("nlc-command", DoctorCommandKernels.GetNlcCommandMissingMessage()));

        var packageCache = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".nsharp",
            "packages");
        checks.Add(Directory.Exists(packageCache) && Directory.EnumerateFiles(packageCache, "NSharpLang.Sdk.*.nupkg").Any()
            ? DoctorCheck.Pass("nsharp-packages", packageCache)
            : DoctorCheck.Fail(
                "nsharp-packages",
                DoctorCommandKernels.GetPackageCacheMissingMessage(packageCache),
                required: true));

        var templateList = dotnet is null
            ? ProcessResult.Failed(DoctorCommandKernels.GetDotnetNotFoundMessage())
            : RunCapture("dotnet", "new list nsharp");
        if (templateList.ExitCode == 0 && templateList.Stdout.Contains("nsharp-console", StringComparison.OrdinalIgnoreCase))
            checks.Add(DoctorCheck.Pass("templates", DoctorCommandKernels.GetTemplateInstalledMessage()));
        else
            checks.Add(DoctorCheck.Fail("templates", DoctorCommandKernels.GetTemplatesMissingMessage(), required: true));

        var lsp = FindOnPath("nsharp-lsp");
        if (lsp is not null)
            checks.Add(DoctorCheck.Pass("language-server", lsp));
        else
            checks.Add(DoctorCheck.Fail("language-server", DoctorCommandKernels.GetLanguageServerMissingMessage(), required: true));

        if (skipVscode)
        {
            checks.Add(DoctorCheck.Warn("vscode-extension", DoctorCommandKernels.GetVscodeSkippedMessage()));
        }
        else
        {
            var code = FindOnPath("code");
            if (code is null)
            {
                checks.Add(requireVscode
                    ? DoctorCheck.Fail(
                        "vscode-extension",
                        DoctorCommandKernels.GetVscodeRequiredMissingMessage(),
                        required: true)
                    : DoctorCheck.Warn(
                        "vscode-extension",
                        DoctorCommandKernels.GetVscodeOptionalMissingMessage()));
            }
            else
            {
                var extensions = RunCapture("code", "--list-extensions");
                if (extensions.ExitCode == 0 && extensions.Stdout.Split('\n', '\r').Any(e => string.Equals(e.Trim(), VscodeExtensionId, StringComparison.OrdinalIgnoreCase)))
                    checks.Add(DoctorCheck.Pass("vscode-extension", VscodeExtensionId));
                else
                    checks.Add(DoctorCheck.Fail(
                        "vscode-extension",
                        DoctorCommandKernels.GetVscodeExtensionMissingMessage(VscodeExtensionId),
                        required: requireVscode));
            }
        }

        var ok = checks.All(c => c.Status != "fail");
        if (outputMode == DoctorOutputModeKind.Json)
            WriteJson(ok, checks);
        else
            WriteText(ok, checks);

        return ok ? 0 : 1;
    }

    private static void WriteText(bool ok, IReadOnlyList<DoctorCheck> checks)
    {
        Console.WriteLine(DoctorCommandKernels.GetTextHeader());
        Console.WriteLine(DoctorCommandKernels.GetStatusLine(ok));
        Console.WriteLine();
        foreach (var check in checks)
        {
            var marker = DoctorCommandKernels.GetCheckMarker(check.Status);
            Console.WriteLine(DoctorCommandKernels.GetCheckLine(marker, check.Name, check.Detail));
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

    internal static DoctorOptionSummary GetOptionSummary(string[] args)
        => DoctorCommandKernels.TryGetOptionSummary(args, out var summary)
            ? summary
            : GetOptionSummaryWithCSharp(args);

    internal static DoctorOutputModeKind GetOutputMode(bool json)
        => DoctorCommandKernels.TryGetOutputMode(json, out var outputMode)
            ? outputMode
            : GetOutputModeWithCSharp(json);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product doctor option parsing routes through DoctorCommandKernels.
    private static DoctorOptionSummary GetOptionSummaryWithCSharp(string[] args)
        => new(
            ContainsArgWithCSharp(args, "--json"),
            ContainsArgWithCSharp(args, "--require-vscode"),
            ContainsArgWithCSharp(args, "--skip-vscode"),
            ContainsArgWithCSharp(args, "--help") || ContainsArgWithCSharp(args, "-h") || (args.Length > 0 && args[0] == "help"));

    // Stage 6 C#-surface-shrink: fallback/oracle only; product doctor output mode selection routes through DoctorCommandKernels.
    private static DoctorOutputModeKind GetOutputModeWithCSharp(bool json)
        => json ? DoctorOutputModeKind.Json : DoctorOutputModeKind.Text;

    private static bool ContainsArgWithCSharp(string[] args, string value)
    {
        for (var i = 0; i < args.Length; i++)
            if (args[i] == value)
                return true;
        return false;
    }

    private static int ShowHelp()
    {
        Console.WriteLine(DoctorCommandKernels.GetHelpText());
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

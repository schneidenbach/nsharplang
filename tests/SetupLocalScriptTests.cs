using System;
using System.Diagnostics;
using System.IO;
using Xunit;

public class SetupLocalScriptTests
{
    [Fact]
    public void SetupLocalDryRunInstallsFirstClassNSharpToolchain()
    {
        var repoRoot = FindRepoRoot();
        var home = Path.Combine(Path.GetTempPath(), "nsharp-setup-local-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(home);

        try
        {
            var result = RunBash(repoRoot, home, "scripts/setup-local.sh --dry-run");

            Assert.True(
                result.ExitCode == 0,
                $"setup-local dry-run failed with exit code {result.ExitCode}\n" +
                $"--- stdout ---\n{result.Stdout}\n" +
                $"--- stderr ---\n{result.Stderr}");
            Assert.Contains("Deploying Local N# Toolset", result.Stdout);
            Assert.Contains("--skip-vscode", result.Stdout);
            Assert.Contains("dotnet tool install -g NSharpLang.Cli", result.Stdout);
            Assert.Contains("dotnet tool install -g NSharpLang.LanguageServer", result.Stdout);
            Assert.Contains("dotnet new install NSharpLang.Templates", result.Stdout);
            Assert.Contains(".nsharp/env", result.Stdout);
            Assert.Contains("DOTNET_ROOT", result.Stdout);
            Assert.Contains("nlc doctor --skip-vscode", result.Stdout);
            Assert.Contains("nlc new MyApp", result.Stdout);
        }
        finally
        {
            try { Directory.Delete(home, recursive: true); }
            catch { /* best-effort cleanup */ }
        }
    }

    private static ProcessResult RunBash(string workingDirectory, string home, string command)
    {
        using var process = new Process();
        process.StartInfo = new ProcessStartInfo("bash")
        {
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        process.StartInfo.ArgumentList.Add("-lc");
        process.StartInfo.ArgumentList.Add(command);
        process.StartInfo.Environment["HOME"] = home;
        process.StartInfo.Environment["SHELL"] = "/bin/zsh";
        process.StartInfo.Environment["DOTNET_CLI_HOME"] = home;
        process.StartInfo.Environment["DOTNET_NOLOGO"] = "1";

        process.Start();
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(30_000))
        {
            try { process.Kill(entireProcessTree: true); }
            catch { /* best-effort cleanup */ }

            var timedOutStdout = stdoutTask.IsCompleted ? stdoutTask.Result : string.Empty;
            var timedOutStderr = stderrTask.IsCompleted ? stderrTask.Result : string.Empty;
            return new ProcessResult(124, timedOutStdout, timedOutStderr + "\nTimed out after 30 seconds.");
        }

        var stdout = stdoutTask.GetAwaiter().GetResult();
        var stderr = stderrTask.GetAwaiter().GetResult();
        return new ProcessResult(process.ExitCode, stdout, stderr);
    }

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
                return dir;
            dir = Path.GetDirectoryName(dir);
        }

        throw new InvalidOperationException(
            "Could not find repository root (NSharpLang.sln). " +
            $"Searched upward from {AppContext.BaseDirectory}");
    }

    private sealed record ProcessResult(int ExitCode, string Stdout, string Stderr);
}

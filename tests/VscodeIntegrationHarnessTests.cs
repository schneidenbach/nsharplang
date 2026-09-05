using System;
using System.Diagnostics;
using System.IO;
using Xunit;

namespace NSharpLang.Tests;

public class VscodeIntegrationHarnessTests
{
    [Fact]
    public void ShellHarnessSelfTestRejectsZeroPassingOutput()
    {
        var repoRoot = FindRepoRoot();
        var result = RunBash(repoRoot, "NSHARP_VSCODE_HARNESS_SELF_TEST=1 tests/scripts/test-vscode-integration.sh");

        Assert.True(
            result.ExitCode == 0,
            $"VS Code harness self-test failed with exit code {result.ExitCode}\n" +
            $"--- stdout ---\n{result.Stdout}\n" +
            $"--- stderr ---\n{result.Stderr}");
        Assert.Contains("VS Code integration harness self-test passed", result.Stdout);
    }

    [Fact]
    public void TypeScriptSuiteRunnerFailsWhenGrepMatchesZeroTests()
    {
        var repoRoot = FindRepoRoot();
        var suiteRunner = File.ReadAllText(Path.Combine(repoRoot, "editors", "vscode", "test", "suite", "index.ts"));

        Assert.Contains("runner?.total ?? 0", suiteRunner);
        Assert.Contains("TEST_GREP", suiteRunner);
        Assert.Contains("matched 0 tests", suiteRunner);
    }

    private static ProcessResult RunBash(string workingDirectory, string command)
    {
        using var process = new Process();
        process.StartInfo = new ProcessStartInfo("bash")
        {
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        process.StartInfo.ArgumentList.Add("-lc");
        process.StartInfo.ArgumentList.Add(command);
        process.StartInfo.Environment["DOTNET_NOLOGO"] = "1";

        process.Start();
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(60_000))
        {
            try { process.Kill(entireProcessTree: true); }
            catch { /* best-effort cleanup */ }

            var timedOutStdout = stdoutTask.IsCompleted ? stdoutTask.Result : string.Empty;
            var timedOutStderr = stderrTask.IsCompleted ? stderrTask.Result : string.Empty;
            return new ProcessResult(124, timedOutStdout, timedOutStderr + "\nTimed out after 60 seconds.");
        }

        return new ProcessResult(
            process.ExitCode,
            stdoutTask.GetAwaiter().GetResult(),
            stderrTask.GetAwaiter().GetResult());
    }

    private static string FindRepoRoot()
    {
        var dir = Directory.GetCurrentDirectory();
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
                return dir;
            dir = Directory.GetParent(dir)?.FullName;
        }

        throw new InvalidOperationException("Could not find repository root");
    }

    private sealed record ProcessResult(int ExitCode, string Stdout, string Stderr);
}

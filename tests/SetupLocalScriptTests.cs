using System;
using System.Diagnostics;
using System.IO;
using Xunit;

public class SetupLocalScriptTests
{
    private const string PublicInstallCommand =
        "curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . \"$HOME/.nsharp/env\"";

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

    [Fact]
    public void PublicInstallHelpShowsSingleLineInstaller()
    {
        var repoRoot = FindRepoRoot();
        var home = Path.Combine(Path.GetTempPath(), "nsharp-install-help-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(home);

        try
        {
            var result = RunBash(repoRoot, home, "scripts/install.sh --help");

            Assert.True(
                result.ExitCode == 0,
                $"install help failed with exit code {result.ExitCode}\n" +
                $"--- stdout ---\n{result.Stdout}\n" +
                $"--- stderr ---\n{result.Stderr}");
            Assert.Contains(PublicInstallCommand, result.Stdout);
            Assert.Contains("--vsix-url URL", result.Stdout);
            Assert.Contains("--no-path-update", result.Stdout);
        }
        finally
        {
            try { Directory.Delete(home, recursive: true); }
            catch { /* best-effort cleanup */ }
        }
    }

    [Fact]
    public void PublicInstallDryRunInstallsCompilerToolsAndBootstrapsPath()
    {
        var repoRoot = FindRepoRoot();
        var home = Path.Combine(Path.GetTempPath(), "nsharp-install-dry-run-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(home);

        try
        {
            var result = RunBash(repoRoot, home, "scripts/install.sh --dry-run --skip-vscode");

            Assert.True(
                result.ExitCode == 0,
                $"install dry-run failed with exit code {result.ExitCode}\n" +
                $"--- stdout ---\n{result.Stdout}\n" +
                $"--- stderr ---\n{result.Stderr}");
            Assert.Contains("dotnet new install NSharpLang.Templates", result.Stdout);
            Assert.Contains("NSharpLang.Cli", result.Stdout);
            Assert.Contains("NSharpLang.LanguageServer", result.Stdout);
            Assert.Contains("Ensuring nlc is on PATH for future shells", result.Stdout);
            Assert.Contains(".nsharp/env", result.Stdout);
            Assert.Contains("Skipping VS Code extension (--skip-vscode)", result.Stdout);
        }
        finally
        {
            try { Directory.Delete(home, recursive: true); }
            catch { /* best-effort cleanup */ }
        }
    }

    [Fact]
    public void PublicInstallDryRunShowsVscodeMarketplaceAndVsixFallback()
    {
        var repoRoot = FindRepoRoot();
        var home = Path.Combine(Path.GetTempPath(), "nsharp-install-vscode-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(home);

        try
        {
            var result = RunBash(
                repoRoot,
                home,
                "mkdir -p \"$HOME/fake-bin\" && " +
                "printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$HOME/fake-bin/code\" && " +
                "chmod +x \"$HOME/fake-bin/code\" && " +
                "PATH=\"$HOME/fake-bin:$PATH\" scripts/install.sh --dry-run --no-path-update --vsix-url https://example.test/nsharp.vsix");

            Assert.True(
                result.ExitCode == 0,
                $"install VS Code dry-run failed with exit code {result.ExitCode}\n" +
                $"--- stdout ---\n{result.Stdout}\n" +
                $"--- stderr ---\n{result.Stderr}");
            Assert.Contains("Installing VS Code extension: nsharp.nsharp", result.Stdout);
            Assert.Contains("code --install-extension nsharp.nsharp --force", result.Stdout);
            Assert.Contains("curl -fsSL https://example.test/nsharp.vsix -o <temp-vsix>", result.Stdout);
            Assert.Contains("code --install-extension <temp-vsix> --force", result.Stdout);
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

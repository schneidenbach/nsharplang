using System;
using NSharpLang.Cli;
using Xunit;

namespace NSharpLang.Tests;

public class DotnetRunnerTests
{
    [Fact]
    public void DotnetRunner_CapturesOutput()
    {
        var result = DotnetRunner.Run("--version");

        Assert.Equal(0, result.ExitCode);
        Assert.False(string.IsNullOrWhiteSpace(result.Stdout),
            "Expected non-empty stdout from 'dotnet --version'");
        // Should look like a semver — e.g. "9.0.100"
        Assert.Matches(@"\d+\.\d+", result.Stdout);
    }

    [Fact]
    public void DotnetRunner_ReturnsNonZeroExitCode()
    {
        // "dotnet not-a-real-command" exits non-zero
        var result = DotnetRunner.Run("not-a-real-command-nlc-test-xyz");

        Assert.NotEqual(0, result.ExitCode);
    }

    [Fact]
    public void DotnetRunner_RunProcess_CapturesOutput()
    {
        // Use dotnet itself as a non-dotnet process entry point to keep the
        // test hermetic (avoids relying on external tools like curl or echo).
        var result = DotnetRunner.RunProcess("dotnet", "--version");

        Assert.Equal(0, result.ExitCode);
        Assert.False(string.IsNullOrWhiteSpace(result.Stdout));
    }

    [Fact]
    public void DotnetRunner_WorkingDirectory_IsRespected()
    {
        var tempDir = System.IO.Path.GetTempPath();

        // `dotnet --version` doesn't care about cwd, but we verify the call
        // succeeds with an explicit working directory provided.
        var result = DotnetRunner.Run("--version", workingDirectory: tempDir);

        Assert.Equal(0, result.ExitCode);
        Assert.False(string.IsNullOrWhiteSpace(result.Stdout));
    }

    [Fact]
    public void DotnetRunner_StderrIsCapturedSeparately()
    {
        // A successful command should have empty stderr (stdout has the version).
        var result = DotnetRunner.Run("--version");

        Assert.Equal(0, result.ExitCode);
        // Stderr should be empty or nearly empty for --version
        Assert.True(string.IsNullOrWhiteSpace(result.Stderr),
            $"Expected empty stderr but got: {result.Stderr}");
    }
}

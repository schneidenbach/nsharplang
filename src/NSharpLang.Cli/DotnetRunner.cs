using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

namespace NSharpLang.Cli;

/// <summary>
/// Centralised process-launch utility for the nlc CLI.
///
/// All Process.Start / ProcessStartInfo usage in commands must go through
/// this class so we get consistent argument quoting, working-directory
/// resolution, async stdout/stderr capture (deadlock-safe) and timeout
/// handling in one place.
/// </summary>
public static class DotnetRunner
{
    /// <summary>The default timeout applied to captured builds (5 minutes).</summary>
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromMinutes(5);

    /// <summary>Result of a captured process invocation.</summary>
    public record RunResult(int ExitCode, string Stdout, string Stderr);

    /// <summary>
    /// Run <c>dotnet &lt;arguments&gt;</c> and capture stdout/stderr.
    /// Uses async read events to avoid deadlocks on large output.
    /// </summary>
    /// <param name="arguments">Arguments passed after "dotnet".</param>
    /// <param name="workingDirectory">Resolved to an absolute path when provided.</param>
    /// <param name="captureOutput">When false stdout/stderr are not redirected (rare).</param>
    /// <param name="timeout">Defaults to <see cref="DefaultTimeout"/>.</param>
    public static RunResult Run(
        string arguments,
        string? workingDirectory = null,
        bool captureOutput = true,
        TimeSpan? timeout = null)
        => RunProcess("dotnet", arguments, workingDirectory, captureOutput, timeout);

    /// <summary>
    /// Run <c>dotnet &lt;arguments&gt;</c> and forward output directly to the console.
    /// Intended for build / run / publish where the user must see live output.
    /// Returns the process exit code.
    /// </summary>
    /// <param name="arguments">Arguments passed after "dotnet".</param>
    /// <param name="workingDirectory">Resolved to an absolute path when provided.</param>
    /// <param name="verbose">When true, stderr is also forwarded (otherwise silently discarded).</param>
    public static int RunPassthrough(
        string arguments,
        string? workingDirectory = null,
        bool verbose = false)
    {
        var psi = BuildPsi("dotnet", arguments, workingDirectory);
        psi.RedirectStandardOutput = false;
        psi.RedirectStandardError = false;
        psi.UseShellExecute = false;

        var process = new Process { StartInfo = psi };
        try
        {
            process.Start();
            process.WaitForExit();
            return process.ExitCode;
        }
        finally
        {
            process.Dispose();
        }
    }

    /// <summary>
    /// Run an arbitrary process (not necessarily dotnet) and capture its output.
    /// Uses async read events to avoid deadlocks.
    /// </summary>
    /// <param name="fileName">Executable name or full path.</param>
    /// <param name="arguments">Command-line arguments.</param>
    /// <param name="workingDirectory">Resolved to an absolute path when provided.</param>
    /// <param name="timeout">Defaults to <see cref="DefaultTimeout"/>.</param>
    public static RunResult RunProcess(
        string fileName,
        string arguments,
        string? workingDirectory = null,
        TimeSpan? timeout = null)
        => RunProcess(fileName, arguments, workingDirectory, captureOutput: true, timeout);

    // ── internal implementation ────────────────────────────────────────────

    private static RunResult RunProcess(
        string fileName,
        string arguments,
        string? workingDirectory,
        bool captureOutput,
        TimeSpan? timeout)
    {
        var psi = BuildPsi(fileName, arguments, workingDirectory);
        psi.RedirectStandardOutput = captureOutput;
        psi.RedirectStandardError = captureOutput;
        psi.UseShellExecute = false;

        var stdoutBuilder = new StringBuilder();
        var stderrBuilder = new StringBuilder();

        var process = new Process { StartInfo = psi };
        try
        {
            if (captureOutput)
            {
                // Use event-based async reads to prevent deadlocks when both
                // stdout and stderr buffers fill up simultaneously.
                process.OutputDataReceived += (_, e) =>
                {
                    if (e.Data != null)
                    {
                        lock (stdoutBuilder)
                        {
                            stdoutBuilder.AppendLine(e.Data);
                        }
                    }
                };
                process.ErrorDataReceived += (_, e) =>
                {
                    if (e.Data != null)
                    {
                        lock (stderrBuilder)
                        {
                            stderrBuilder.AppendLine(e.Data);
                        }
                    }
                };
            }

            process.Start();

            if (captureOutput)
            {
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }

            var effectiveTimeout = timeout ?? DefaultTimeout;
            var exited = process.WaitForExit((int)effectiveTimeout.TotalMilliseconds);

            if (!exited)
            {
                try { process.Kill(entireProcessTree: true); } catch { /* best effort */ }
                throw new TimeoutException(
                    $"Process '{fileName} {arguments}' did not complete within {effectiveTimeout}.");
            }

            // WaitForExit() with a timeout does not guarantee that the async
            // event streams have been fully drained.  A second call (no timeout)
            // ensures all OutputDataReceived/ErrorDataReceived callbacks fire.
            process.WaitForExit();

            return new RunResult(
                process.ExitCode,
                stdoutBuilder.ToString(),
                stderrBuilder.ToString());
        }
        finally
        {
            process.Dispose();
        }
    }

    private static ProcessStartInfo BuildPsi(
        string fileName,
        string arguments,
        string? workingDirectory)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
        };

        if (workingDirectory != null)
            psi.WorkingDirectory = Path.GetFullPath(workingDirectory);

        return psi;
    }
}

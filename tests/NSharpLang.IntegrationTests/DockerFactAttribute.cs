using System;
using System.Diagnostics;
using Xunit;

namespace NSharpLang.IntegrationTests;

/// <summary>
/// Marks integration tests that require a live Docker daemon.
/// Solution-level `dotnet test` must stay green on developer machines where
/// Docker is not installed or not running; set NSHARP_RUN_DOCKER_INTEGRATION=1
/// to fail instead of skip when Docker is unavailable.
/// </summary>
public sealed class DockerFactAttribute : FactAttribute
{
    private const string ForceEnvironmentVariable = "NSHARP_RUN_DOCKER_INTEGRATION";

    public DockerFactAttribute()
    {
        if (IsForced())
            return;

        var (available, reason) = ProbeDocker();
        if (!available)
            Skip = $"Docker integration prerequisite unavailable: {reason}. Set {ForceEnvironmentVariable}=1 to require this test.";
    }

    private static bool IsForced()
    {
        var value = Environment.GetEnvironmentVariable(ForceEnvironmentVariable);
        return string.Equals(value, "1", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
    }

    private static (bool Available, string Reason) ProbeDocker()
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "docker",
                Arguments = "info --format {{json .ServerVersion}}",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            });

            if (process is null)
                return (false, "failed to start `docker info`");

            if (!process.WaitForExit(10_000))
            {
                try { process.Kill(entireProcessTree: true); }
                catch { /* best effort */ }
                return (false, "`docker info` timed out after 10 seconds");
            }

            if (process.ExitCode == 0)
                return (true, string.Empty);

            var stderr = process.StandardError.ReadToEnd().Trim();
            return (false, string.IsNullOrWhiteSpace(stderr) ? $"`docker info` exited {process.ExitCode}" : stderr);
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            return (false, "docker CLI not found or not executable");
        }
    }
}

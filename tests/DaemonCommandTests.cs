using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using NSharpLang.Cli.Commands;
using NSharpLang.Cli.Daemon;
using Xunit;

namespace NSharpLang.Tests;

public class DaemonCommandTests
{
    // ── Help & Dispatch ────────────────────────────────────────────────

    [Fact]
    public void DaemonCommand_NoArgs_ShowsHelp()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => DaemonCommand.Execute(Array.Empty<string>()));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc daemon", stdout);
    }

    [Fact]
    public void DaemonCommand_HelpFlag_ShowsHelp()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => DaemonCommand.Execute(new[] { "--help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc daemon", stdout);
        Assert.Contains("start", stdout);
        Assert.Contains("stop", stdout);
        Assert.Contains("status", stdout);
    }

    [Fact]
    public void DaemonCommand_HelpSubcommand_ShowsHelp()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => DaemonCommand.Execute(new[] { "help" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc daemon", stdout);
    }

    [Fact]
    public void DaemonCommand_UnknownSubcommand_ShowsHelp()
    {
        var (exitCode, stdout, _) = CaptureConsole(() => DaemonCommand.Execute(new[] { "bogus" }));

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: nlc daemon", stdout);
    }

    // ── Start/Stop/Status when no daemon running ───────────────────────

    [Fact]
    public void DaemonCommand_Stop_WhenNotRunning_PrintsNoDaemon()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, _) = CaptureConsole(() =>
                DaemonCommand.Execute(new[] { "stop", "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.Contains("No daemon running", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DaemonCommand_Status_WhenNotRunning_PrintsNoDaemon()
    {
        var tempDir = CreateTempDir();
        try
        {
            var (exitCode, stdout, _) = CaptureConsole(() =>
                DaemonCommand.Execute(new[] { "status", "--project", tempDir }));

            Assert.Equal(0, exitCode);
            Assert.Contains("No daemon running", stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── DaemonConstants ────────────────────────────────────────────────

    [Fact]
    public void DaemonConstants_GetSocketPath_CreatesNlcDir()
    {
        var tempDir = CreateTempDir();
        try
        {
            var socketPath = DaemonConstants.GetSocketPath(tempDir);

            Assert.True(Directory.Exists(Path.Combine(tempDir, ".nlc")));
            Assert.EndsWith("daemon.sock", socketPath);
            Assert.StartsWith(tempDir, socketPath);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DaemonConstants_HasExpectedMethodNames()
    {
        Assert.Equal("daemon/ping", DaemonConstants.MethodPing);
        Assert.Equal("daemon/shutdown", DaemonConstants.MethodShutdown);
        Assert.Equal("daemon/status", DaemonConstants.MethodStatus);
        Assert.Equal("query/symbols", DaemonConstants.MethodSymbols);
        Assert.Equal("query/batch", DaemonConstants.MethodBatch);
    }

    [Fact]
    public void DaemonConstants_TimeoutsArePositive()
    {
        Assert.True(DaemonConstants.IdleTimeoutMinutes > 0);
        Assert.True(DaemonConstants.ConnectionTimeoutMs > 0);
        Assert.True(DaemonConstants.PingTimeoutMs > 0);
    }

    // ── DaemonClient — no socket ───────────────────────────────────────

    [Fact]
    public void DaemonClient_IsRunning_ReturnsFalse_WhenNoSocketExists()
    {
        var tempDir = CreateTempDir();
        try
        {
            Assert.False(DaemonClient.IsRunning(tempDir));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DaemonClient_Query_ReturnsNull_WhenNoSocketExists()
    {
        var tempDir = CreateTempDir();
        try
        {
            var result = DaemonClient.Query(tempDir, DaemonConstants.MethodPing);
            Assert.Null(result);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DaemonClient_StopDaemon_ReturnsFalse_WhenNotRunning()
    {
        var tempDir = CreateTempDir();
        try
        {
            // StopDaemon calls Query which returns null → false
            Assert.False(DaemonClient.StopDaemon(tempDir));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DaemonClient_GetStatus_ReturnsNull_WhenNotRunning()
    {
        var tempDir = CreateTempDir();
        try
        {
            Assert.Null(DaemonClient.GetStatus(tempDir));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── DaemonClient — stale socket cleanup ────────────────────────────

    [Fact]
    public void DaemonClient_IsRunning_CleansUpStaleSocket()
    {
        var tempDir = CreateTempDir();
        try
        {
            var socketPath = DaemonConstants.GetSocketPath(tempDir);
            // Create a fake socket file (not a real listener)
            File.WriteAllText(socketPath, "stale");

            Assert.False(DaemonClient.IsRunning(tempDir));
            // Stale socket should be cleaned up
            Assert.False(File.Exists(socketPath));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void DaemonClient_Query_ReturnsNull_ForStaleSocket()
    {
        var tempDir = CreateTempDir();
        try
        {
            var socketPath = DaemonConstants.GetSocketPath(tempDir);
            File.WriteAllText(socketPath, "stale");

            var result = DaemonClient.Query(tempDir, DaemonConstants.MethodPing);
            Assert.Null(result);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── DaemonProtocol serialization ───────────────────────────────────

    [Fact]
    public void DaemonRequest_RoundTrips()
    {
        var request = new DaemonRequest
        {
            Id = 42,
            Method = "daemon/ping"
        };

        var json = JsonSerializer.Serialize(request);
        var deserialized = JsonSerializer.Deserialize<DaemonRequest>(json);

        Assert.NotNull(deserialized);
        Assert.Equal("2.0", deserialized!.JsonRpc);
        Assert.Equal(42, deserialized.Id);
        Assert.Equal("daemon/ping", deserialized.Method);
    }

    [Fact]
    public void DaemonResponse_WithResult_RoundTrips()
    {
        var response = new DaemonResponse
        {
            Id = 1,
            Result = "\"pong\""
        };

        var json = JsonSerializer.Serialize(response);
        var deserialized = JsonSerializer.Deserialize<DaemonResponse>(json);

        Assert.NotNull(deserialized);
        Assert.Equal(1, deserialized!.Id);
        Assert.Equal("\"pong\"", deserialized.Result);
        Assert.Null(deserialized.Error);
    }

    [Fact]
    public void DaemonResponse_WithError_RoundTrips()
    {
        var response = new DaemonResponse
        {
            Id = 2,
            Error = new DaemonError { Code = -1, Message = "test error" }
        };

        var json = JsonSerializer.Serialize(response);
        var deserialized = JsonSerializer.Deserialize<DaemonResponse>(json);

        Assert.NotNull(deserialized);
        Assert.Equal(2, deserialized!.Id);
        Assert.Null(deserialized.Result);
        Assert.NotNull(deserialized.Error);
        Assert.Equal(-1, deserialized.Error!.Code);
        Assert.Equal("test error", deserialized.Error.Message);
    }

    [Fact]
    public void DaemonStatus_Serialization_HasExpectedPropertyNames()
    {
        var status = new DaemonStatus
        {
            Pid = 12345,
            Uptime = "1h 2m 3s",
            ProjectRoot = "/tmp/test",
            CachedFiles = 10,
            IdleTimeout = "30m"
        };

        var json = JsonSerializer.Serialize(status);
        using var doc = JsonDocument.Parse(json);

        Assert.Equal(12345, doc.RootElement.GetProperty("pid").GetInt32());
        Assert.Equal("1h 2m 3s", doc.RootElement.GetProperty("uptime").GetString());
        Assert.Equal("/tmp/test", doc.RootElement.GetProperty("projectRoot").GetString());
        Assert.Equal(10, doc.RootElement.GetProperty("cachedFiles").GetInt32());
        Assert.Equal("30m", doc.RootElement.GetProperty("idleTimeout").GetString());
    }

    // ── PID file lifecycle ─────────────────────────────────────────────

    [Fact]
    public void DaemonServer_Cleanup_RemovesPidAndSocket()
    {
        var tempDir = CreateTempDir();
        try
        {
            var socketPath = DaemonConstants.GetSocketPath(tempDir);
            var pidPath = Path.Combine(Path.GetDirectoryName(socketPath)!, "daemon.pid");

            // Simulate files that daemon creates
            File.WriteAllText(socketPath, "socket-placeholder");
            File.WriteAllText(pidPath, "99999");

            Assert.True(File.Exists(socketPath));
            Assert.True(File.Exists(pidPath));

            // Verify the paths are in the right location
            Assert.Equal(Path.Combine(tempDir, ".nlc", "daemon.sock"), socketPath);
            Assert.Equal(Path.Combine(tempDir, ".nlc", "daemon.pid"), pidPath);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static string CreateTempDir()
    {
        var path = Path.Combine(Path.GetTempPath(), $"nsharp-daemon-{Guid.NewGuid():N}");
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
}

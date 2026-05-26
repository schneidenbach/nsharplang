using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using NSharpLang.Cli.Commands;
using NSharpLang.Cli.Daemon;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
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
    public void DaemonConstants_GetSocketPath_FallsBackForLongProjectPaths()
    {
        var tempDir = Path.Combine("/tmp", "nlc-" + new string('x', 120));
        Directory.CreateDirectory(tempDir);
        try
        {
            var socketPath = DaemonConstants.GetSocketPath(tempDir);

            Assert.True(Encoding.UTF8.GetByteCount(socketPath) <= 100);
            Assert.Contains(Path.Combine("nlc-daemon"), socketPath);
            Assert.EndsWith("daemon.sock", socketPath);
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
        Assert.Equal("query/outline", DaemonConstants.MethodOutline);
        Assert.Equal("query/diagnostics", DaemonConstants.MethodDiagnostics);
        Assert.Equal("query/type", DaemonConstants.MethodType);
        Assert.Equal("query/definition", DaemonConstants.MethodDefinition);
        Assert.Equal("query/references", DaemonConstants.MethodReferences);
        Assert.Equal("query/completions", DaemonConstants.MethodCompletions);
        Assert.Equal("query/inspect", DaemonConstants.MethodInspect);
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

    // ── PID file path convention ──────────────────────────────────────

    [Fact]
    public void DaemonServer_PidAndSocketPaths_AreUnderNlcDir()
    {
        var tempDir = CreateTempDir();
        try
        {
            var socketPath = DaemonConstants.GetSocketPath(tempDir);
            var pidPath = Path.Combine(Path.GetDirectoryName(socketPath)!, "daemon.pid");

            // Verify the paths are in the expected .nlc subdirectory
            Assert.Equal(Path.Combine(tempDir, ".nlc", "daemon.sock"), socketPath);
            Assert.Equal(Path.Combine(tempDir, ".nlc", "daemon.pid"), pidPath);

            // Simulate files that daemon creates and verify they land correctly
            File.WriteAllText(socketPath, "socket-placeholder");
            File.WriteAllText(pidPath, "99999");
            Assert.True(File.Exists(socketPath));
            Assert.True(File.Exists(pidPath));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ── Lifecycle integration ───────────────────────────────────────────

    [Fact]
    public void DaemonServer_Lifecycle_CoversSocketPidStatusAndStop()
    {
        var projectDir = CreateTempProject();
        try
        {
            using var server = DaemonTestServer.Start(projectDir);
            var socketPath = DaemonConstants.GetSocketPath(projectDir);
            var pidPath = Path.Combine(Path.GetDirectoryName(socketPath)!, "daemon.pid");

            Assert.True(File.Exists(socketPath));
            Assert.True(File.Exists(pidPath));
            Assert.True(int.TryParse(File.ReadAllText(pidPath), out var pid));
            Assert.True(pid > 0);

            Assert.Equal("\"pong\"", DaemonClient.Query(projectDir, DaemonConstants.MethodPing));

            var statusJson = DaemonClient.GetStatus(projectDir);
            Assert.NotNull(statusJson);
            var status = JsonSerializer.Deserialize<DaemonStatus>(statusJson!);
            Assert.NotNull(status);
            Assert.Equal(projectDir, status!.ProjectRoot);
            Assert.Equal(pid, status.Pid);
            Assert.Equal("30m", status.IdleTimeout);

            Assert.True(DaemonClient.StopDaemon(projectDir));
            Assert.True(WaitUntil(() => !File.Exists(socketPath) && !File.Exists(pidPath), TimeSpan.FromSeconds(5)));
        }
        finally
        {
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void DaemonServer_ReturnsStructuredErrors_ForUnknownMethodAndMalformedJson()
    {
        var projectDir = CreateTempProject();
        try
        {
            using var server = DaemonTestServer.Start(projectDir);

            var unknown = DaemonClient.QueryResponse(projectDir, "daemon/nope");
            Assert.NotNull(unknown);
            Assert.NotNull(unknown!.Error);
            Assert.Equal("2.0", unknown.JsonRpc);
            Assert.Equal(DaemonConstants.ErrorMethodNotFound, unknown.Error!.Code);
            Assert.Contains("Unknown method", unknown.Error.Message);

            var malformedJson = SendRawDaemonRequest(projectDir, "{not json");
            var malformed = JsonSerializer.Deserialize<DaemonResponse>(malformedJson);
            Assert.NotNull(malformed);
            Assert.NotNull(malformed!.Error);
            Assert.Equal(DaemonConstants.ErrorParse, malformed.Error!.Code);
            Assert.Equal("Malformed daemon request JSON.", malformed.Error.Message);
            Assert.NotNull(malformed.Error.Data);
        }
        finally
        {
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void DaemonServer_ReturnsMethodNotFoundBeforeProjectLoad()
    {
        var projectDir = CreateTempDir();
        try
        {
            using var server = DaemonTestServer.Start(projectDir);

            var unknown = DaemonClient.QueryResponse(projectDir, "query/not-real");
            Assert.NotNull(unknown);
            Assert.NotNull(unknown!.Error);
            Assert.Equal(DaemonConstants.ErrorMethodNotFound, unknown.Error!.Code);
            Assert.Contains("Unknown method", unknown.Error.Message);
        }
        finally
        {
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void QueryCommand_DiagnosticsClusters_UsesDaemonEnvelopeWhenDaemonRunning()
    {
        var projectDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(projectDir, "project.yml"), """
name: DaemonDiagnosticClusters
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(projectDir, "Program.nl"), """
func Main() {
    Console.WriteLine(undefinedDaemonCluster)
}
""");

            using var server = DaemonTestServer.Start(projectDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() => QueryCommand.Execute(new[]
            {
                "diagnostics",
                "--clusters",
                "--project", projectDir
            }));

            Assert.Equal(1, exitCode);
            Assert.DoesNotContain("\"error\"", stderr, StringComparison.OrdinalIgnoreCase);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("diagnostics.clusters", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.True(doc.RootElement.TryGetProperty("clusters", out var clusters));
            Assert.True(clusters.ValueKind == JsonValueKind.Array);
            Assert.False(doc.RootElement.TryGetProperty("results", out _));
        }
        finally
        {
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void DaemonServer_FileWatcher_ReloadsSnapshotWhenNlFileIsAdded()
    {
        var projectDir = CreateTempProject();
        try
        {
            using var server = DaemonTestServer.Start(projectDir);

            Assert.NotNull(DaemonClient.Query(projectDir, DaemonConstants.MethodDiagnostics));
            var cachedBefore = GetCachedFileCount(projectDir);
            Assert.True(cachedBefore > 0);

            File.WriteAllText(
                Path.Combine(projectDir, "WatcherAdded.nl"),
                "namespace IssueTracker\n\nclass WatcherAdded {\n}\n");

            Assert.True(WaitUntil(() =>
            {
                Assert.NotNull(DaemonClient.Query(projectDir, DaemonConstants.MethodDiagnostics));
                return GetCachedFileCount(projectDir) > cachedBefore;
            }, TimeSpan.FromSeconds(5)));
        }
        finally
        {
            Directory.Delete(projectDir, true);
        }
    }

    [Fact]
    public void DaemonServer_IdleTimeout_ShutsDownDeterministically()
    {
        var projectDir = CreateTempProject();
        try
        {
            var socketPath = DaemonConstants.GetSocketPath(projectDir);
            using var server = DaemonTestServer.Start(
                projectDir,
                idleTimeout: TimeSpan.FromMilliseconds(200),
                idleCheckInterval: TimeSpan.FromMilliseconds(25));

            Assert.True(File.Exists(socketPath));
            Assert.True(WaitUntil(() => !File.Exists(socketPath), TimeSpan.FromSeconds(5)));
        }
        finally
        {
            Directory.Delete(projectDir, true);
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static string CreateTempDir()
    {
        var path = Path.Combine("/tmp", $"nlc-{Guid.NewGuid():N}"[..16]);
        Directory.CreateDirectory(path);
        return path;
    }

    private static string CreateTempProject()
    {
        var tempDir = CreateTempDir();
        CopyDirectory(Path.Combine(FindRepoRoot(), "tests", "fixtures", "issue-tracker"), tempDir);
        return tempDir;
    }

    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            var fixtureDir = Path.Combine(dir.FullName, "tests", "fixtures", "issue-tracker");
            if (Directory.Exists(fixtureDir))
                return dir.FullName;
            dir = dir.Parent;
        }

        throw new DirectoryNotFoundException("Could not find repository root containing tests/fixtures/issue-tracker.");
    }

    private static void CopyDirectory(string sourceDir, string destinationDir)
    {
        Directory.CreateDirectory(destinationDir);
        foreach (var sourceFile in Directory.GetFiles(sourceDir))
        {
            File.Copy(sourceFile, Path.Combine(destinationDir, Path.GetFileName(sourceFile)), overwrite: true);
        }

        foreach (var sourceSubdir in Directory.GetDirectories(sourceDir))
        {
            CopyDirectory(sourceSubdir, Path.Combine(destinationDir, Path.GetFileName(sourceSubdir)));
        }
    }

    private static int GetCachedFileCount(string projectDir)
    {
        var statusJson = DaemonClient.GetStatus(projectDir);
        Assert.NotNull(statusJson);
        var status = JsonSerializer.Deserialize<DaemonStatus>(statusJson!);
        Assert.NotNull(status);
        return status!.CachedFiles;
    }

    private static string SendRawDaemonRequest(string projectDir, string requestJson)
    {
        var socketPath = DaemonConstants.GetSocketPath(projectDir);
        using var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        socket.ReceiveTimeout = DaemonConstants.ConnectionTimeoutMs;
        socket.SendTimeout = DaemonConstants.ConnectionTimeoutMs;
        socket.Connect(new UnixDomainSocketEndPoint(socketPath));
        var bytes = Encoding.UTF8.GetBytes(requestJson);
        socket.Send(bytes);
        socket.Shutdown(SocketShutdown.Send);

        using var responseStream = new MemoryStream();
        var buffer = new byte[8192];
        int received;
        while ((received = socket.Receive(buffer)) > 0)
        {
            responseStream.Write(buffer, 0, received);
        }

        return Encoding.UTF8.GetString(responseStream.ToArray());
    }

    private static bool WaitUntil(Func<bool> predicate, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (predicate())
                return true;
            Thread.Sleep(25);
        }

        return predicate();
    }

    private sealed class DaemonTestServer : IDisposable
    {
        private readonly string _projectDir;
        private readonly Thread _thread;
        private bool _disposed;

        private DaemonTestServer(string projectDir, TimeSpan idleTimeout, TimeSpan idleCheckInterval)
        {
            _projectDir = projectDir;
            _thread = new Thread(() => new DaemonServer(projectDir, idleTimeout, idleCheckInterval).Run())
            {
                IsBackground = true,
                Name = "nlc-daemon-test-server"
            };
            _thread.Start();
        }

        public static DaemonTestServer Start(
            string projectDir,
            TimeSpan? idleTimeout = null,
            TimeSpan? idleCheckInterval = null)
        {
            var server = new DaemonTestServer(
                projectDir,
                idleTimeout ?? TimeSpan.FromMinutes(DaemonConstants.IdleTimeoutMinutes),
                idleCheckInterval ?? TimeSpan.FromMinutes(1));

            var started = WaitUntil(() => DaemonClient.IsRunning(projectDir), TimeSpan.FromSeconds(5));
            Assert.True(started, "Daemon test server did not become responsive.");
            return server;
        }

        public void Dispose()
        {
            if (_disposed)
                return;
            _disposed = true;

            DaemonClient.StopDaemon(_projectDir);
            _thread.Join(TimeSpan.FromSeconds(5));
        }
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

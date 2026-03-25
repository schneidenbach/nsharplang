using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;

namespace NSharpLang.Cli.Daemon;

/// <summary>
/// Client for communicating with the daemon server via Unix domain socket.
/// Used by QueryCommand to get fast responses from a cached analysis.
/// </summary>
public static class DaemonClient
{
    private static int _nextRequestId;

    /// <summary>
    /// Send a query to the daemon and get the raw JSON response.
    /// Returns null if daemon is not running or connection fails.
    /// </summary>
    public static string? Query(string projectRoot, string method, Dictionary<string, object?>? parameters = null)
    {
        var socketPath = DaemonConstants.GetSocketPath(projectRoot);

        if (!File.Exists(socketPath))
            return null;

        try
        {
            using var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            socket.ReceiveTimeout = 30_000; // 30s for potentially slow first-load
            socket.SendTimeout = DaemonConstants.ConnectionTimeoutMs;
            socket.Connect(new UnixDomainSocketEndPoint(socketPath));

            var request = new DaemonRequest
            {
                Id = Interlocked.Increment(ref _nextRequestId),
                Method = method,
                Params = parameters != null
                    ? JsonSerializer.SerializeToElement(parameters)
                    : null
            };

            var requestJson = JsonSerializer.Serialize(request);
            var requestBytes = Encoding.UTF8.GetBytes(requestJson);
            socket.Send(requestBytes);

            // Receive response
            var buffer = new byte[1024 * 1024]; // 1MB buffer
            var received = socket.Receive(buffer);
            if (received == 0) return null;

            var responseJson = Encoding.UTF8.GetString(buffer, 0, received);
            var response = JsonSerializer.Deserialize<DaemonResponse>(responseJson);

            if (response?.Error != null)
            {
                Console.Error.WriteLine($"[daemon] Error: {response.Error.Message}");
                return null;
            }

            return response?.Result;
        }
        catch (SocketException)
        {
            // Daemon not running or socket stale — clean up
            try { File.Delete(socketPath); } catch { }
            return null;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[daemon] Connection error: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Check if the daemon is running and responsive.
    /// </summary>
    public static bool IsRunning(string projectRoot)
    {
        var socketPath = DaemonConstants.GetSocketPath(projectRoot);
        if (!File.Exists(socketPath)) return false;

        try
        {
            using var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            socket.ReceiveTimeout = DaemonConstants.PingTimeoutMs;
            socket.SendTimeout = DaemonConstants.PingTimeoutMs;
            socket.Connect(new UnixDomainSocketEndPoint(socketPath));

            var request = new DaemonRequest
            {
                Id = 0,
                Method = DaemonConstants.MethodPing
            };

            var requestBytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(request));
            socket.Send(requestBytes);

            var buffer = new byte[1024];
            var received = socket.Receive(buffer);
            return received > 0;
        }
        catch
        {
            // Socket exists but daemon is dead — clean up
            try { File.Delete(socketPath); } catch { }
            return false;
        }
    }

    /// <summary>
    /// Start the daemon as a background process.
    /// Returns true if daemon started successfully.
    /// </summary>
    public static bool StartDaemon(string projectRoot)
    {
        var exePath = Process.GetCurrentProcess().MainModule?.FileName;
        if (exePath == null)
        {
            Console.Error.WriteLine("Cannot determine executable path for daemon");
            return false;
        }

        // Use dotnet run for development, but the real binary path for installed tools
        var startInfo = new ProcessStartInfo
        {
            FileName = exePath,
            Arguments = $"daemon run --project \"{projectRoot}\"",
            UseShellExecute = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false,
            CreateNoWindow = true,
            WorkingDirectory = projectRoot
        };

        // If running via `dotnet run`, we need a different approach
        if (exePath.Contains("dotnet"))
        {
            // Find the CLI project
            var cliDir = FindCliProject();
            if (cliDir != null)
            {
                startInfo.FileName = "dotnet";
                startInfo.Arguments = $"run --project \"{cliDir}\" -- daemon run --project \"{projectRoot}\"";
            }
        }

        try
        {
            var process = Process.Start(startInfo);
            if (process == null) return false;

            // Wait for socket to appear
            var socketPath = DaemonConstants.GetSocketPath(projectRoot);
            for (int i = 0; i < 50; i++) // Up to 5 seconds
            {
                Thread.Sleep(100);
                if (File.Exists(socketPath) && IsRunning(projectRoot))
                    return true;
            }

            Console.Error.WriteLine("Daemon started but not responding within 5 seconds");
            return false;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to start daemon: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Shut down the daemon gracefully.
    /// </summary>
    public static bool StopDaemon(string projectRoot)
    {
        var result = Query(projectRoot, DaemonConstants.MethodShutdown);
        return result != null;
    }

    /// <summary>
    /// Get daemon status information.
    /// </summary>
    public static string? GetStatus(string projectRoot)
    {
        return Query(projectRoot, DaemonConstants.MethodStatus);
    }

    private static string? FindCliProject()
    {
        // Walk up from current directory to find Cli.csproj
        var dir = Directory.GetCurrentDirectory();
        while (dir != null)
        {
            var cliProj = Path.Combine(dir, "src", "NSharpLang.Cli", "Cli.csproj");
            if (File.Exists(cliProj))
                return Path.GetDirectoryName(cliProj);
            dir = Directory.GetParent(dir)?.FullName;
        }
        return null;
    }
}

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
    /// Returns null if daemon is not running, connection fails, or the daemon returns an error.
    /// </summary>
    public static string? Query(string projectRoot, string method, Dictionary<string, object?>? parameters = null)
    {
        var response = QueryResponse(projectRoot, method, parameters);

        var error = response?.Error;
        if (error != null)
        {
            Console.Error.WriteLine(DaemonProtocolKernels.ErrorResponseJson(response!.Id, error.Code, error.Message));
            return null;
        }

        return response?.Result;
    }

    /// <summary>
    /// Send a query to the daemon and get the structured JSON-RPC response.
    /// Returns null only when the daemon cannot be reached or the response cannot be decoded.
    /// </summary>
    public static DaemonResponse? QueryResponse(string projectRoot, string method, Dictionary<string, object?>? parameters = null)
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
            SendAll(socket, requestBytes);
            socket.Shutdown(SocketShutdown.Send);

            using var responseStream = new MemoryStream();
            var buffer = new byte[8192];
            int received;
            while ((received = socket.Receive(buffer)) > 0)
            {
                responseStream.Write(buffer, 0, received);
            }

            if (responseStream.Length == 0)
                return null;

            var responseJson = Encoding.UTF8.GetString(responseStream.ToArray());
            return JsonSerializer.Deserialize<DaemonResponse>(responseJson);
        }
        catch (SocketException ex)
        {
            // Daemon not running or socket stale — clean up only when connect proved it stale.
            if (DaemonClientKernels.ShouldDeleteStaleSocket((int)ex.SocketErrorCode, (int)SocketError.TimedOut))
            {
                try { File.Delete(socketPath); } catch { /* best-effort cleanup of a stale socket */ }
            }
            return null;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(DaemonClientKernels.GetConnectionErrorMessage(ex.Message));
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
            SendAll(socket, requestBytes);
            socket.Shutdown(SocketShutdown.Send);

            var buffer = new byte[1024];
            var received = socket.Receive(buffer);
            return received > 0;
        }
        catch (SocketException ex)
        {
            // Socket exists but daemon is dead — clean up only when connect proved it stale.
            if (DaemonClientKernels.ShouldDeleteStaleSocket((int)ex.SocketErrorCode, (int)SocketError.TimedOut))
            {
                try { File.Delete(socketPath); } catch { /* best-effort cleanup of a stale socket */ }
            }
            return false;
        }
        catch
        {
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
            Console.Error.WriteLine(DaemonClientKernels.GetExecutablePathMissingMessage());
            return false;
        }

        var cliDir = DaemonClientKernels.ShouldProbeCliProject(exePath) ? FindCliProject() : null;
        var startPlan = DaemonClientKernels.GetStartPlan(exePath, projectRoot, cliDir);
        var startInfo = new ProcessStartInfo
        {
            FileName = startPlan.FileName,
            Arguments = startPlan.Arguments,
            UseShellExecute = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false,
            CreateNoWindow = true,
            WorkingDirectory = projectRoot
        };

        try
        {
            var process = Process.Start(startInfo);
            if (process == null) return false;

            // Wait for socket to appear
            var socketPath = DaemonConstants.GetSocketPath(projectRoot);
            for (var i = 0; i < DaemonClientKernels.GetStartWaitAttemptCount(); i++)
            {
                Thread.Sleep(DaemonClientKernels.GetStartWaitDelayMilliseconds());
                if (File.Exists(socketPath) && IsRunning(projectRoot))
                    return true;
            }

            Console.Error.WriteLine(DaemonClientKernels.GetStartTimeoutMessage());
            return false;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(DaemonClientKernels.GetStartFailedWithReasonMessage(ex.Message));
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

    private static void SendAll(Socket socket, byte[] bytes)
    {
        var sent = 0;
        while (sent < bytes.Length)
        {
            sent += socket.Send(bytes, sent, bytes.Length - sent, SocketFlags.None);
        }
    }
}

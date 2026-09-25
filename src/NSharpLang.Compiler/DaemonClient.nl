namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Net.Sockets
import System.Text
import System.Text.Json
import System.Threading
import NSharpLang.Compiler

// The monotonic request-id source the client stamps on every envelope. It is an object with an
// instance field rather than a static counter because `Interlocked.Increment(ref <static field>)`
// declines at emit on this compiler (logged in census-briefs/CLI2-COMPILER-BLOCKERS.md); the
// instance form is the same single shared int incremented atomically.
internal class DaemonRequestIds {
    nextId: int = 0

    func Next(): int {
        value := Interlocked.Increment(ref nextId)
        return value
    }
}

// The client half of the daemon's Unix-domain-socket wire: everything that talks TO a daemon from
// outside it. `nlc query` uses it to reach a warm analysis, and `nlc daemon start/stop/status` uses
// it to find, spawn and shut one down.
//
// Reaching a daemon that is not there is ORDINARY, not exceptional — a cold project has no socket
// and a crashed one leaves a stale file behind — so every entry point answers null/false instead of
// throwing, and only a connect that PROVED the socket stale deletes it. The messages, the start
// plan, the retry budget and the stale-socket rule all belong to `DaemonClientKernels`; this owner
// only opens sockets, copies bytes and starts processes.
class DaemonClient {
    static requestIds: DaemonRequestIds = new DaemonRequestIds()

    // Send a query to the daemon and get the raw JSON response.
    // Returns null if daemon is not running, connection fails, or the daemon returns an error.
    static func Query(projectRoot: string, method: string, parameters: Dictionary<string, object?>? = null): string? {
        response := QueryResponse(projectRoot, method, parameters)
        if response == null {
            return null
        }

        error := response.Error
        if error != null {
            Console.Error.WriteLine(DaemonProtocolKernels.ErrorResponseJson(response.Id, error.Code, error.Message))
            return null
        }

        return response.Result
    }

    // Send a query to the daemon and get the structured JSON-RPC response.
    // Returns null only when the daemon cannot be reached or the response cannot be decoded.
    static func QueryResponse(projectRoot: string, method: string, parameters: Dictionary<string, object?>? = null): DaemonResponse? {
        socketPath := DaemonConstants.GetSocketPath(projectRoot)

        if !File.Exists(socketPath) {
            return null
        }

        try {
            using socket := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)
            // 30s for a potentially slow first load; the send side keeps the short connect budget.
            socket.ReceiveTimeout = 30000
            socket.SendTimeout = DaemonConstants.ConnectionTimeoutMs
            socket.Connect(new UnixDomainSocketEndPoint(socketPath))

            paramsElement: JsonElement? = null
            if parameters != null {
                paramsElement = JsonSerializer.SerializeToElement<Dictionary<string, object?>>(parameters)
            }

            requestId := requestIds.Next()
            // Written as three assignments, not an initializer: `nlc format` rewrites
            // `new T() { … }` to the parenless `new T { … }`, and that shape declines at emit when
            // a value is a nullable struct (census-briefs/CLI2-COMPILER-BLOCKERS.md). An
            // initializer IS these assignments, so nothing about the envelope changes.
            request := new DaemonRequest()
            request.Id = requestId
            request.Method = method
            request.Params = paramsElement

            requestJson := JsonSerializer.Serialize<DaemonRequest>(request)
            requestBytes := Encoding.UTF8.GetBytes(requestJson)
            SendAll(socket, requestBytes)
            socket.Shutdown(SocketShutdown.Send)

            using responseStream := new MemoryStream()
            buffer := new byte[](8192)
            while true {
                received := socket.Receive(buffer)
                if received <= 0 {
                    break
                }

                responseStream.Write(buffer, 0, received)
            }

            if responseStream.Length == 0 {
                return null
            }

            responseJson := Encoding.UTF8.GetString(responseStream.ToArray())
            return JsonSerializer.Deserialize<DaemonResponse>(responseJson)
        } catch ex: Exception {
            // One `catch` because a clause named `SocketException` declines at emit (logged in
            // census-briefs/CLI2-COMPILER-BLOCKERS.md); the socket test below is first, so the two
            // failures are still told apart in the order the clauses had.
            socketFailure := ex as SocketException
            if socketFailure != null {
                // Daemon not running or socket stale — clean up only when connect proved it stale.
                DeleteStaleSocket(socketPath, socketFailure)
                return null
            }

            Console.Error.WriteLine(DaemonClientKernels.GetConnectionErrorMessage(ex.Message))
            return null
        }
    }

    // Check if the daemon is running and responsive.
    static func IsRunning(projectRoot: string): bool {
        socketPath := DaemonConstants.GetSocketPath(projectRoot)
        if !File.Exists(socketPath) {
            return false
        }

        try {
            using socket := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)
            socket.ReceiveTimeout = DaemonConstants.PingTimeoutMs
            socket.SendTimeout = DaemonConstants.PingTimeoutMs
            socket.Connect(new UnixDomainSocketEndPoint(socketPath))

            request := new DaemonRequest()
            request.Id = 0
            request.Method = DaemonConstants.MethodPing

            requestJson := JsonSerializer.Serialize<DaemonRequest>(request)
            requestBytes := Encoding.UTF8.GetBytes(requestJson)
            SendAll(socket, requestBytes)
            socket.Shutdown(SocketShutdown.Send)

            buffer := new byte[](1024)
            received := socket.Receive(buffer)
            return received > 0
        } catch ex: Exception {
            socketFailure := ex as SocketException
            if socketFailure != null {
                // Socket exists but daemon is dead — clean up only when connect proved it stale.
                DeleteStaleSocket(socketPath, socketFailure)
            }

            return false
        }
    }

    // Start the daemon as a background process.
    // Returns true if daemon started successfully.
    static func StartDaemon(projectRoot: string): bool {
        // `Process.GetCurrentProcess().MainModule?.FileName` declines at emit (logged in
        // census-briefs/CLI2-COMPILER-BLOCKERS.md). `Environment.ProcessPath` is the same string:
        // measured identical under both `dotnet Cli.dll` and the apphost.
        exePath := Environment.ProcessPath
        if exePath == null {
            Console.Error.WriteLine(DaemonClientKernels.GetExecutablePathMissingMessage())
            return false
        }

        cliDir: string? = null
        if DaemonClientKernels.ShouldProbeCliProject(exePath) {
            cliDir = FindCliProject()
        }

        startPlan := DaemonClientKernels.GetStartPlan(exePath, projectRoot, cliDir)
        startInfo := new ProcessStartInfo()
        startInfo.FileName = startPlan.FileName
        startInfo.Arguments = startPlan.Arguments
        startInfo.UseShellExecute = false
        startInfo.RedirectStandardOutput = false
        startInfo.RedirectStandardError = false
        startInfo.CreateNoWindow = true
        startInfo.WorkingDirectory = projectRoot

        try {
            process := Process.Start(startInfo)
            if process == null {
                return false
            }

            // Wait for socket to appear
            socketPath := DaemonConstants.GetSocketPath(projectRoot)
            attempt := 0
            while attempt < DaemonClientKernels.GetStartWaitAttemptCount() {
                Thread.Sleep(DaemonClientKernels.GetStartWaitDelayMilliseconds())
                if File.Exists(socketPath) && IsRunning(projectRoot) {
                    return true
                }

                attempt = attempt + 1
            }

            Console.Error.WriteLine(DaemonClientKernels.GetStartTimeoutMessage())
            return false
        } catch ex: Exception {
            Console.Error.WriteLine(DaemonClientKernels.GetStartFailedWithReasonMessage(ex.Message))
            return false
        }
    }

    // Shut down the daemon gracefully.
    static func StopDaemon(projectRoot: string): bool {
        result := Query(projectRoot, DaemonConstants.MethodShutdown, null)
        return result != null
    }

    // Get daemon status information.
    static func GetStatus(projectRoot: string): string? {
        return Query(projectRoot, DaemonConstants.MethodStatus, null)
    }

    // Walk up from the current directory to find Cli.csproj.
    static func FindCliProject(): string? {
        dir: string? = Directory.GetCurrentDirectory()
        while dir != null {
            cliProj := DaemonClientKernels.GetCliProjectPath(dir)
            if File.Exists(cliProj) {
                return DaemonClientKernels.GetCliProjectDirectory(cliProj)
            }

            parent := Directory.GetParent(dir)
            dir = parent?.FullName
        }

        return null
    }

    static func DeleteStaleSocket(socketPath: string, ex: SocketException) {
        if !DaemonClientKernels.ShouldDeleteStaleSocket((int)ex.SocketErrorCode, (int)SocketError.TimedOut) {
            return
        }

        try {
            File.Delete(socketPath)
        } catch deleteFailure: Exception {
            // best-effort cleanup of a stale socket
        }
    }

    static func SendAll(socket: Socket, bytes: byte[]) {
        sent := 0
        while sent < bytes.Length {
            sent = sent + socket.Send(bytes, sent, bytes.Length - sent, SocketFlags.None)
        }
    }
}

namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Net.Sockets
import System.Reflection
import System.Text
import System.Text.Json
import System.Threading
import NSharpLang.Compiler

// The last lines from a daemon child are retained while its redirected streams are drained. Keeping
// the pipes moving prevents a verbose `dotnet run` startup from blocking before the listening socket
// exists, and the bounded tail makes startup failures useful without retaining an unbounded log.
class DaemonStartupOutputCapture {
    gate: object
    lines: List<string>

    constructor() {
        gate = new object()
        lines = new List<string>()
    }

    func Append(line: string?) {
        if line == null {
            return
        }

        lock gate {
            lines.Add(line ?? "")
            while lines.Count > 20 {
                lines.RemoveAt(0)
            }
        }
    }

    func GetTail(): string {
        lock gate {
            if lines.Count == 0 {
                return "(no output captured)"
            }

            result := ""
            for line in lines {
                result = result + line + "\n"
            }

            return result
        }
    }
}

func DaemonStartupOutputTail(output: DaemonStartupOutputCapture, logPath: string): string {
    captured := output.GetTail()
    if !File.Exists(logPath) {
        return captured
    }

    try {
        lines := File.ReadAllLines(logPath)
        if lines.Length == 0 {
            return captured
        }

        first := Math.Max(0, lines.Length - 20)
        tail := ""
        index := first
        while index < lines.Length {
            tail = tail + lines[index] + "\n"
            index = index + 1
        }

        return captured + "\n--- daemon log tail ---\n" + tail
    } catch readFailure: Exception {
        return captured
    }
}

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

        connectFailed := true
        try {
            using socket := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)
            // 30s for a potentially slow first load; the send side keeps the short connect budget.
            socket.ReceiveTimeout = 30000
            socket.SendTimeout = DaemonConstants.ConnectionTimeoutMs
            socket.Connect(new UnixDomainSocketEndPoint(socketPath))
            connectFailed = false

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
                // Only a failed connect can prove a path stale. Connection-refused stays
                // ambiguous on macOS until the ready PID marker; Linux uses /proc/net/unix to
                // distinguish a bound socket from a regular file at the same path.
                DeleteStaleSocket(socketPath, socketFailure, connectFailed)
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

        connectFailed := true
        try {
            using socket := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)
            socket.ReceiveTimeout = DaemonConstants.PingTimeoutMs
            socket.SendTimeout = DaemonConstants.PingTimeoutMs
            socket.Connect(new UnixDomainSocketEndPoint(socketPath))
            connectFailed = false

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
                // A refused connect before the PID marker can be the bind/listen startup window.
                DeleteStaleSocket(socketPath, socketFailure, connectFailed)
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

        // The server is THIS binary — never `dotnet run` over whatever a checkout holds — so it is the
        // same build the client is, which is what `DaemonExecKernels.GetServerLaunchCommand` encodes.
        entryAssembly := Assembly.GetEntryAssembly()
        entryPath: string? = null
        if entryAssembly != null {
            entryPath = entryAssembly.Location
        }

        command := DaemonExecKernels.GetServerLaunchCommand(exePath ?? "", entryPath, projectRoot, false)
        startInfo := new ProcessStartInfo()
        startInfo.FileName = command[0]
        argumentIndex := 1
        while argumentIndex < command.Length {
            startInfo.ArgumentList.Add(command[argumentIndex])
            argumentIndex = argumentIndex + 1
        }

        // All three streams are fresh pipes: a server that inherited the caller's stdout would hold
        // it open for its whole life, and `nlc daemon start | cat` would not finish until the server
        // idled out. Startup lines arrive on stderr and are echoed below; the server sends anything
        // later to its log.
        startInfo.UseShellExecute = false
        startInfo.RedirectStandardInput = true
        startInfo.RedirectStandardOutput = true
        startInfo.RedirectStandardError = true
        startInfo.CreateNoWindow = true
        startInfo.WorkingDirectory = projectRoot

        try {
            socketPath := DaemonConstants.GetSocketPath(projectRoot)
            pidPath := DaemonProtocolKernels.GetPidFilePath(socketPath)
            outputLogPath := Path.Combine(
                Path.GetDirectoryName(socketPath) ?? "",
                DaemonClientKernels.GetStartupOutputLogFileName()
            )
            File.WriteAllText(outputLogPath, "")
            startInfo.Environment[DaemonClientKernels.GetStartupOutputLogEnvironmentVariableName()] = outputLogPath

            process := new Process { StartInfo: startInfo }
            output := new DaemonStartupOutputCapture()
            on process.ErrorDataReceived (sender, received) => {
                output.Append(received.Data)
                if received.Data != null {
                    capturedLine := received.Data ?? ""
                    Console.Error.WriteLine(capturedLine)
                }
            }

            if !process.Start() {
                process.Dispose()
                return false
            }
            CompilerWorkCounters.Shared.CountProcessSpawned()

            process.BeginErrorReadLine()

            // A listening socket that answers ping is the readiness signal. The generous deadline
            // catches a genuinely stuck startup; process exit is reported on the first poll.
            wait := DaemonStartupWait.WaitUntilReady(
                () => File.Exists(pidPath) && File.Exists(socketPath) && IsRunning(projectRoot) && IsWarm(projectRoot),
                () => process.HasExited,
                () => process.ExitCode,
                () => DaemonStartupOutputTail(output, outputLogPath),
                DaemonClientKernels.GetStartTimeoutMilliseconds(),
                DaemonClientKernels.GetStartWaitPollIntervalMilliseconds()
            )
            if wait.Ready {
                return true
            }

            if wait.ProcessExited {
                process.WaitForExit()
                outputTail := DaemonStartupOutputTail(output, outputLogPath)
                Console.Error.WriteLine(DaemonClientKernels.GetStartExitedMessage(process.ExitCode, wait.ElapsedMilliseconds, outputTail))
                process.Dispose()
                return false
            }

            timeoutMessage := DaemonClientKernels.GetStartTimeoutMessage(socketPath, wait.ElapsedMilliseconds, !process.HasExited, wait.OutputTail)
            Console.Error.WriteLine(timeoutMessage)
            if !process.HasExited {
                try {
                    process.Kill(true)
                    process.WaitForExit(5000)
                } catch killFailure: Exception {
                    Console.Error.WriteLine(DaemonClientKernels.GetStartFailedWithReasonMessage(killFailure.Message))
                }
            }
            return false
        } catch ex: Exception {
            Console.Error.WriteLine(DaemonClientKernels.GetStartFailedWithReasonMessage(ex.Message))
            return false
        }
    }

    // Shut down the daemon gracefully.
    // Stopped means GONE: the answer waits (up to ten seconds) until the server no longer answers,
    // so a caller that starts a replacement next never races the old one for the socket.
    static func StopDaemon(projectRoot: string): bool {
        result := Query(projectRoot, DaemonConstants.MethodShutdown, null)
        if result == null {
            return false
        }

        clock := Stopwatch.StartNew()
        while clock.ElapsedMilliseconds < 10000L && IsRunning(projectRoot) {
            Thread.Sleep(50)
        }

        return true
    }

    // Get daemon status information.
    static func GetStatus(projectRoot: string): string? {
        return Query(projectRoot, DaemonConstants.MethodStatus, null)
    }

    // Whether the running server has finished its warm-up. A server from before the field existed is
    // warm by definition: it never ran one.
    static func IsWarm(projectRoot: string): bool {
        status := GetStatus(projectRoot)
        if status == null {
            return false
        }

        try {
            using document := JsonDocument.Parse(status ?? "")
            warmValue: JsonElement = default
            if document.RootElement.ValueKind == JsonValueKind.Object && document.RootElement.TryGetProperty(DaemonProtocolKernels.GetStatusWarmField(), out warmValue) {
                return warmValue.ValueKind == JsonValueKind.True
            }
        } catch parseFailure: Exception {
            return false
        }

        return true
    }

    // The build identity the running server reports, or null when none answers (or it is a build
    // from before servers reported one).
    static func GetStatusIdentity(projectRoot: string): string? {
        status := GetStatus(projectRoot)
        if status == null {
            return null
        }

        try {
            using document := JsonDocument.Parse(status ?? "")
            identity: JsonElement = default
            if document.RootElement.ValueKind == JsonValueKind.Object && document.RootElement.TryGetProperty(DaemonProtocolKernels.GetStatusIdentityField(), out identity) {
                return identity.GetString()
            }
        } catch parseFailure: Exception {
            return null
        }

        return null
    }

    static func DeleteStaleSocket(socketPath: string, ex: SocketException, connectFailed: bool) {
        pidPath := DaemonProtocolKernels.GetPidFilePath(socketPath)
        isLinux := OperatingSystem.IsLinux()
        linuxSocketIsBound := false
        if isLinux && ex.SocketErrorCode == SocketError.ConnectionRefused {
            linuxSocketIsBound = IsLinuxUnixSocketBound(socketPath)
        }

        if !DaemonClientKernels.ShouldDeleteStaleSocket(
            (int)ex.SocketErrorCode,
            connectFailed,
            File.Exists(pidPath),
            (int)SocketError.NotSocket,
            (int)SocketError.ConnectionRefused,
            isLinux,
            linuxSocketIsBound
        ) {
            return
        }

        try {
            File.Delete(socketPath)
        } catch deleteFailure: Exception {
            Console.Error.WriteLine(DaemonClientKernels.GetConnectionErrorMessage(deleteFailure.Message))
        }
    }

    // Linux reports the same ECONNREFUSED for a regular file and a live socket that has been
    // bound but has not started listening. `/proc/net/unix` lists bound Unix sockets by pathname,
    // which lets stale-file cleanup keep a live startup socket intact. If procfs is unavailable,
    // preserve the path because the refusal alone cannot prove that it is stale.
    static func IsLinuxUnixSocketBound(socketPath: string): bool {
        try {
            lines := File.ReadAllLines("/proc/net/unix")
            for line in lines {
                if line.EndsWith(" " + socketPath, StringComparison.Ordinal) {
                    return true
                }
            }
        } catch probeFailure: Exception {
            Console.Error.WriteLine(DaemonClientKernels.GetConnectionErrorMessage("Unable to inspect Linux Unix socket table: " + probeFailure.Message))
            return true
        }

        return false
    }

    static func SendAll(socket: Socket, bytes: byte[]) {
        sent := 0
        while sent < bytes.Length {
            sent = sent + socket.Send(bytes, sent, bytes.Length - sent, SocketFlags.None)
        }
    }
}

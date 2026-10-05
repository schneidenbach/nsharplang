namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Linq
import System.Net.Sockets
import System.Runtime.InteropServices
import System.Text
import System.Text.Json
import System.Threading
import NSharpLang.Cli
import NSharpLang.Cli.Commands
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// The error the query dispatch throws to answer with a JSON-RPC code rather than a message alone.
class DaemonProtocolException: Exception {
    Code: int

    constructor(code: int, message: string): base(message) {
        Code = code
    }
}

// The `data` payload of a parse-error response: the three members `JsonException` exposes about
// WHERE the bytes stopped being JSON. It was a C# anonymous type; the properties are spelled out
// here because the serializer reads properties, not fields, and the camel-case policy turns these
// three names into `path`, `lineNumber` and `bytePositionInLine` exactly as it did before.
class DaemonParseErrorData {
    pathValue: string?
    lineNumberValue: long?
    bytePositionInLineValue: long?

    constructor(path: string?, lineNumber: long?, bytePositionInLine: long?) {
        pathValue = path
        lineNumberValue = lineNumber
        bytePositionInLineValue = bytePositionInLine
    }

    Path: string? {
        get {
            return pathValue
        }
    }

    LineNumber: long? {
        get {
            return lineNumberValue
        }
    }

    BytePositionInLine: long? {
        get {
            return bytePositionInLineValue
        }
    }
}

// Background daemon server that caches project analysis and serves
// nlc query requests via Unix domain socket.
//
// Lifecycle:
// 1. Started by first `nlc query` call or `nlc daemon start`
// 2. Listens on Unix socket at {projectRoot}/.nlc/daemon.sock
// 3. Caches ProjectSnapshot after first request
// 4. FileSystemWatcher invalidates cache on .nl file changes
// 5. Auto-exits after 30 minutes idle
//
// TWO FIELDS ARE READ BY A THREAD THAT DID NOT WRITE THEM — `running`, which the idle thread clears
// while the accept loop reads it, and `cacheInvalid`, which the file-watcher callbacks set while
// `EnsureSnapshot` reads it. Both were `volatile` in C#. N# has no `volatile` modifier, so every
// access goes through `Volatile.Read`/`Volatile.Write`, which is the same acquire/release the
// modifier compiles to; nothing about the ordering changes.
class DaemonServer {
    static DaemonJsonOptions: JsonSerializerOptions = CreateDaemonJsonOptions()

    projectRoot: string
    socketPath: string
    service: CodeIntelligenceService
    completionEngine: CompletionEngine
    snapshots: Dictionary<string, ProjectSnapshot>
    lastActivity: DateTime
    fileWatcher: FileSystemWatcher?
    cacheInvalid: bool
    running: bool
    idleTimeout: TimeSpan
    idleCheckInterval: TimeSpan
    diagnosticGate: object
    diagnosticLines: List<string>
    startupSignal: ManualResetEventSlim
    startupSucceeded: bool
    logWriter: TextWriter
    workGate: object
    activeRequests: int
    servedRequests: int
    background: bool
    maxMemoryMegabytes: long
    lockStream: FileStream?

    constructor(root: string): this(root, TimeSpan.FromMilliseconds((double)DaemonExecKernels.ParseIdleTimeoutMilliseconds(
        Environment.GetEnvironmentVariable(DaemonExecKernels.GetIdleTimeoutEnvironmentVariable()),
        (long)DaemonConstants.IdleTimeoutMinutes * 60000L
    )), TimeSpan.FromMilliseconds((double)DaemonExecKernels.GetLivenessCheckMilliseconds())) {
    }

    constructor(root: string, timeout: TimeSpan, checkInterval: TimeSpan) {
        projectRoot = root
        socketPath = DaemonConstants.GetSocketPath(root)
        service = new CodeIntelligenceService()
        completionEngine = new CompletionEngine()
        snapshots = new Dictionary<string, ProjectSnapshot>(StringComparer.Ordinal)
        lastActivity = DateTime.UtcNow
        fileWatcher = null
        cacheInvalid = true
        running = false
        idleTimeout = timeout
        idleCheckInterval = checkInterval
        diagnosticGate = new object()
        diagnosticLines = new List<string>()
        startupSignal = new ManualResetEventSlim()
        startupSucceeded = false
        logWriter = Console.Error
        workGate = new object()
        activeRequests = 0
        servedRequests = 0
        background = false
        maxMemoryMegabytes = DaemonExecKernels.ParseMaxMemoryMegabytes(Environment.GetEnvironmentVariable(DaemonExecKernels.GetMaxMemoryEnvironmentVariable()))
        lockStream = null
    }

    // `daemon run --background`: started by a client that does not wait, so every line goes to the
    // log from the first one.
    func SetBackground(value: bool) {
        background = value
    }

    func WorkGate(): object {
        return workGate
    }

    func BeginRequest() {
        Interlocked.Increment(ref activeRequests)
        lastActivity = DateTime.UtcNow
    }

    func EndRequest() {
        Interlocked.Decrement(ref activeRequests)
        Interlocked.Increment(ref servedRequests)
        lastActivity = DateTime.UtcNow
    }

    // After every command: a server whose working set outgrew its cap retires once it is idle, and the
    // next command starts a fresh one. A leak in a long-lived compiler costs one restart, never the
    // machine.
    func CheckResourceCaps() {
        workingSetMegabytes := Environment.WorkingSet / 1048576L
        if workingSetMegabytes <= maxMemoryMegabytes {
            return
        }

        // Over the cap: first let every registered cache shed what it can rebuild, and only retire
        // if that was not enough.
        if Monitor.TryEnter(workGate, 1000) {
            try {
                WarmStateRegistry.TrimAll()
                snapshots.Clear()
                GC.Collect()
                GC.WaitForPendingFinalizers()
            } finally {
                Monitor.Exit(workGate)
            }
        }

        workingSetMegabytes = Environment.WorkingSet / 1048576L
        if workingSetMegabytes > maxMemoryMegabytes {
            WriteDiagnostic(DaemonExecKernels.GetMemoryCapMessage(workingSetMegabytes, maxMemoryMegabytes))
            RequestStop()
        }
    }

    // Ends the accept loop from any thread: clears `running` and connects to the socket once so a
    // blocked `Accept` returns.
    func RequestStop() {
        Volatile.Write(ref running, false)
        try {
            using kick := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)
            kick.Connect(new UnixDomainSocketEndPoint(socketPath))
            kick.Close()
        } catch kickFailure: Exception {
            // No socket file to connect through (the workspace was deleted): the accept loop polls,
            // so it sees `running` cleared within one poll interval anyway.
            return
        }
    }

    // A cancelled command gets `GetCancelGraceMilliseconds` to unwind. One that is still running after
    // that (a runaway loop the client gave up on) cannot be stopped from outside its thread, so the
    // server retires: the socket goes first, so no client is routed to it while it exits.
    func RetireIfStillRunning(session: DaemonExecSession) {
        body: ThreadStart = () => {
            Thread.Sleep(DaemonExecKernels.GetCancelGraceMilliseconds())
            if !session.IsFinished() {
                WriteDiagnostic(DaemonExecKernels.GetRetiringAfterCancelMessage(DaemonExecKernels.GetCancelGraceMilliseconds()))
                try {
                    File.Delete(socketPath)
                    File.Delete(DaemonProtocolKernels.GetPidFilePath(socketPath))
                } catch retireFailure: Exception {
                    WriteDiagnostic(DaemonServerKernels.GetServerErrorMessage(retireFailure.Message))
                }

                Environment.Exit(3)
            }
        }
        watcher := new Thread(body)
        watcher.IsBackground = true
        watcher.Start()
    }

    func WaitForStartup(timeoutMilliseconds: int): bool {
        if !startupSignal.Wait(timeoutMilliseconds) {
            return false
        }

        return Volatile.Read(ref startupSucceeded)
    }

    func SignalStartupReady() {
        Volatile.Write(ref startupSucceeded, true)
        startupSignal.Set()
    }

    func SignalStartupFinished() {
        startupSignal.Set()
    }

    func DisposeStartupSignal() {
        startupSignal.Dispose()
    }

    static func CreateDaemonJsonOptions(): JsonSerializerOptions {
        options := new JsonSerializerOptions()
        options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        options.PropertyNameCaseInsensitive = true
        return options
    }

    func WriteDiagnostic(message: string) {
        lock diagnosticGate {
            diagnosticLines.Add(message)
            while diagnosticLines.Count > 20 {
                diagnosticLines.RemoveAt(0)
            }
        }

        // The writer captured at start (or the log), never `Console.Error`: while a command runs,
        // `Console.Error` is that command's client.
        try {
            logWriter.WriteLine(message)
        } catch logFailure: Exception {
            return
        }
    }

    func GetDiagnosticTail(): string {
        lock diagnosticGate {
            if diagnosticLines.Count == 0 {
                return "(no daemon output captured)"
            }

            result := ""
            for line in diagnosticLines {
                result = result + line + "\n"
            }

            return result
        }
    }

    // Start the daemon server. Blocks until shutdown.
    func Run() {
        pidPath := DaemonProtocolKernels.GetPidFilePath(socketPath)
        socketDirectory := Path.GetDirectoryName(socketPath) ?? projectRoot
        diagnosticWriter: StreamWriter? = null
        startupLogPath := Environment.GetEnvironmentVariable(DaemonClientKernels.GetStartupOutputLogEnvironmentVariableName())

        // A background server's standard streams are pipes nobody reads once the client that spawned
        // it returns, so its log is the only place anything it says can go.
        if background && startupLogPath != null && startupLogPath != "" {
            writer := new StreamWriter(startupLogPath ?? "", true)
            writer.AutoFlush = true
            synchronized := TextWriter.Synchronized(writer)
            logWriter = synchronized
            Console.SetOut(synchronized)
            Console.SetError(synchronized)
            diagnosticWriter = writer
        }

        // SIGNALS. SIGTERM (`kill`, a logout, a container stop) is a request to stop: the accept loop
        // winds down, requests in flight finish, the socket and PID file are removed. A background
        // server was started from inside some command's process group, so a Ctrl-C or hang-up meant
        // for that terminal must not reach it; a foreground `nlc daemon run` keeps the default and
        // stops on Ctrl-C like any other program.
        terminate := PosixSignalRegistration.Create(PosixSignal.SIGTERM, (context) => {
            context.Cancel = true
            RequestStop()
        })
        interrupt: PosixSignalRegistration? = null
        hangUp: PosixSignalRegistration? = null
        if background {
            interrupt = PosixSignalRegistration.Create(PosixSignal.SIGINT, (context) => {
                context.Cancel = true
            })
            hangUp = PosixSignalRegistration.Create(PosixSignal.SIGHUP, (context) => {
                context.Cancel = true
            })
        }

        try {
            RunWithSignals(pidPath, socketDirectory, diagnosticWriter, startupLogPath)
        } finally {
            terminate.Dispose()
            interrupt?.Dispose()
            hangUp?.Dispose()
        }
    }

    func RunWithSignals(pidPath: string, socketDirectory: string, startupWriter: StreamWriter?, startupLogPath: string?) {
        ownsSocket := false
        diagnosticWriter := startupWriter

        // ONE SERVER PER WORKSPACE. The lock is held for the server's whole life and released by the
        // kernel when the process dies, however it dies, so it never needs cleaning up.
        if !AcquireServerLock(socketDirectory) {
            WriteDiagnostic(DaemonExecKernels.GetAnotherServerOwnsLockMessage(Path.Combine(socketDirectory, DaemonExecKernels.GetLockFileName())))
            SignalStartupFinished()
            diagnosticWriter?.Dispose()
            return
        }

        try {
            if File.Exists(socketPath) {
                // Holding the lock, a socket that still answers belongs to a server from before the
                // lock existed — an older build that a mismatched client has just asked to stop.
                if !WaitForUnlockedServerToExit() {
                    throw new InvalidOperationException(DaemonProtocolKernels.GetAlreadyRunningMessage(projectRoot))
                }

                File.Delete(socketPath)
            }

            // A PID file is the cross-process readiness marker and is written after Listen succeeds.
            // Remove any prior marker before Bind so a refused connect during the bind/listen window
            // cannot be mistaken for a stale socket by another client.
            if File.Exists(pidPath) {
                File.Delete(pidPath)
            }

            using listener := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)

            try {
                listener.Bind(new UnixDomainSocketEndPoint(socketPath))
                ownsSocket = true
                // Owner-only: connecting to a Unix socket needs write permission on it, so no other
                // user can reach this server, whatever the directory's own mode.
                File.SetUnixFileMode(socketPath, UnixFileMode.UserRead | UnixFileMode.UserWrite)
                listener.Listen(16)

                Volatile.Write(ref running, true)

                // Start file watcher only after this process owns the socket.
                StartFileWatcher()
                DaemonExecHost.CaptureBaselineEnvironment()

                // Write PID file only after bind/listen succeeds.
                File.WriteAllText(pidPath, Environment.ProcessId.ToString())
                SignalStartupReady()

                WriteDiagnostic(DaemonServerKernels.GetListeningMessage(socketPath, Environment.ProcessId))
                WriteDiagnostic(DaemonServerKernels.GetProjectMessage(projectRoot))
                WriteDiagnostic(DaemonServerKernels.GetIdleTimeoutMessage(
                    DaemonServerKernels.FormatDurationMilliseconds((long)Math.Round(idleTimeout.TotalMilliseconds))
                ))

                // `nlc daemon start` drains stderr while waiting for this server's ping response. Move
                // later server output to a project-local log before accepting requests; otherwise the
                // detached daemon could outlive its reader and fill the startup pipe. The launching
                // client supplies this path, while an explicitly-run `daemon run` keeps stderr attached.
                if !background && startupLogPath != null && startupLogPath != "" {
                    writer := new StreamWriter(startupLogPath ?? "", true)
                    writer.AutoFlush = true
                    previousError := Console.Error
                    synchronized := TextWriter.Synchronized(writer)
                    Console.SetOut(synchronized)
                    Console.SetError(synchronized)
                    logWriter = synchronized
                    previousError.Dispose()
                    diagnosticWriter = writer
                }

                // Startup time is not idle time. Set the initial activity after the listener and its
                // watchers are ready so a small configured/test timeout cannot expire during a loaded
                // machine's startup window.
                lastActivity = DateTime.UtcNow

                // Idle and liveness thread. The body is bound to a `ThreadStart` local first: a lambda
                // handed straight to `new Thread(...)` declines at emit (logged in
                // census-briefs/CLI2-COMPILER-BLOCKERS.md), and the typed local is the same delegate.
                idleBody: ThreadStart = () => {
                    while Volatile.Read(ref running) {
                        Thread.Sleep(idleCheckInterval)
                        if !Volatile.Read(ref running) {
                            break
                        }

                        // A workspace deleted (or a socket replaced) under this server leaves nobody
                        // able to reach it: retire now rather than idle out.
                        if !File.Exists(socketPath) {
                            WriteDiagnostic(DaemonExecKernels.GetSocketGoneMessage())
                            RequestStop()
                            break
                        }

                        idle := DateTime.UtcNow - lastActivity
                        if Volatile.Read(ref activeRequests) == 0 && idle >= idleTimeout {
                            WriteDiagnostic(DaemonServerKernels.GetIdleTimeoutShutdownMessage(
                                DaemonServerKernels.FormatDurationMilliseconds((long)Math.Round(idleTimeout.TotalMilliseconds))
                            ))
                            RequestStop()
                            break
                        }
                    }
                }
                idleThread := new Thread(idleBody)
                idleThread.IsBackground = true
                idleThread.Start()

                StartWarmup()

                // The loop POLLS rather than blocking in `Accept`: on macOS closing a listener does not
                // wake a thread blocked in accept(2), so a server whose socket file was deleted could
                // never be woken to exit. Half a second of poll is invisible next to a command.
                while Volatile.Read(ref running) {
                    try {
                        if !listener.Poll(500000, SelectMode.SelectRead) {
                            continue
                        }

                        client := listener.Accept()
                        lastActivity = DateTime.UtcNow

                        if !Volatile.Read(ref running) {
                            client.Dispose()
                            break
                        }

                        StartConnection(client)
                    } catch ex: Exception {
                        // One `catch` with the socket test first, because the C# clause
                        // `catch (SocketException) when (!_running)` is an exception FILTER and N# has
                        // none: a socket failure during shutdown still ends the loop silently, and
                        // every other failure is still reported on the same stream.
                        if !Volatile.Read(ref running) {
                            break
                        }

                        WriteDiagnostic(DaemonServerKernels.GetServerErrorMessage(ex.Message))
                    }
                }

                WaitForActiveRequests()
            } finally {
                Volatile.Write(ref running, false)
                if ownsSocket {
                    Cleanup(pidPath)
                } else {
                    fileWatcher?.Dispose()
                }
            }
        } finally {
            ReleaseServerLock()
            diagnosticWriter?.Dispose()
        }
    }

    func AcquireServerLock(directory: string): bool {
        lockPath := Path.Combine(directory, DaemonExecKernels.GetLockFileName())
        clock := Stopwatch.StartNew()
        while clock.ElapsedMilliseconds < 30000L {
            try {
                lockStream = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None)
                return true
            } catch lockFailure: Exception {
                // Held by a live server. If it is this same build and answering, it is doing the job:
                // leave. A server of another build is on its way out (a mismatched client asked it to
                // stop); wait for it.
                if DaemonClient.IsRunning(projectRoot) && DaemonClient.GetStatusIdentity(projectRoot) == DaemonExecHost.GetIdentity() {
                    return false
                }
            }

            Thread.Sleep(100)
        }

        return false
    }

    func ReleaseServerLock() {
        held := lockStream
        lockStream = null
        if held != null {
            held.Dispose()
        }
    }

    func WaitForUnlockedServerToExit(): bool {
        clock := Stopwatch.StartNew()
        while clock.ElapsedMilliseconds < 10000L {
            if !DaemonClient.IsRunning(projectRoot) {
                return true
            }

            Thread.Sleep(100)
        }

        return !DaemonClient.IsRunning(projectRoot)
    }

    // Requests in flight finish before the server exits (a `daemon stop` while an agent's build runs
    // does not cut that build off).
    func WaitForActiveRequests() {
        clock := Stopwatch.StartNew()
        while Volatile.Read(ref activeRequests) > 0 && clock.ElapsedMilliseconds < 600000L {
            Thread.Sleep(50)
        }
    }

    func StartConnection(client: Socket) {
        body: ThreadStart = () => HandleConnection(client)
        worker := new Thread(body)
        worker.IsBackground = true
        worker.Name = "nlc-daemon-connection"
        worker.Start()
    }

    // An exec client opens with the four magic bytes; a JSON-RPC client opens with `{`. Whatever was
    // read to tell them apart is handed to the JSON reader as the start of its request.
    func HandleConnection(client: Socket) {
        try {
            magic := DaemonExecKernels.GetExecMagic()
            prefix := new byte[](magic.Length)
            prefixCount := 0
            client.ReceiveTimeout = 500
            try {
                while prefixCount < prefix.Length {
                    received := client.Receive(prefix, prefixCount, prefix.Length - prefixCount, SocketFlags.None)
                    if received <= 0 {
                        break
                    }

                    prefixCount = prefixCount + received
                    if prefix[0] != magic[0] {
                        break
                    }
                }
            } catch prefixFailure: Exception {
                socketFailure := prefixFailure as SocketException
                if socketFailure == null || socketFailure.SocketErrorCode != SocketError.TimedOut {
                    throw
                }
            }

            if prefixCount == magic.Length && prefix[0] == magic[0] && prefix[1] == magic[1] && prefix[2] == magic[2] && prefix[3] == magic[3] {
                DaemonExecHost.Serve(this, client)
                return
            }

            HandleClient(client, prefix, prefixCount)
        } catch ex: Exception {
            WriteDiagnostic(DaemonServerKernels.GetClientErrorMessage(ex.Message))
        } finally {
            client.Dispose()
        }
    }

    // THE WARM-UP. The first command a fresh server runs pays for JIT and for loading the reference
    // assemblies' metadata. A fresh server has nothing else to do, so it pays that now, on a two-file project of its own in the temp directory, before any client is waiting.
    // It holds the work lock like any command, so a client that arrives meanwhile is never routed
    // into a half-warm process, and it writes nothing anywhere a client can see.
    func StartWarmup() {
        if !DaemonExecHost.IsConfigured() || !DaemonExecKernels.IsWarmupEnabled(Environment.GetEnvironmentVariable(DaemonExecKernels.GetWarmupEnvironmentVariable())) {
            return
        }

        body: ThreadStart = () => RunWarmup()
        warmup := new Thread(body)
        warmup.IsBackground = true
        warmup.Name = "nlc-daemon-warmup"
        warmup.Start()
    }

    func RunWarmup() {
        lock workGate {
            stopwatch := Stopwatch.StartNew()
            try {
                directory := DaemonWarmup.PrepareProject(DaemonExecHost.GetIdentity())
                DaemonWarmup.Run(directory)
                DaemonExecHost.RunWarmupHooks()
                WriteDiagnostic(DaemonWarmup.GetCompletedMessage(stopwatch.ElapsedMilliseconds))
            } catch warmupFailure: Exception {
                WriteDiagnostic(DaemonWarmup.GetFailedMessage(warmupFailure.Message))
            }
        }
    }

    func HandleClient(client: Socket, prefix: byte[], prefixCount: int) {
        // Read request. CLI clients half-close after sending; direct clients may not,
        // so also stop after a short quiet period once at least one chunk arrived.
        using requestStream := new MemoryStream()
        requestStream.Write(prefix, 0, prefixCount)
        buffer := new byte[](8192)
        client.ReceiveTimeout = 500

        while true {
            received := 0
            try {
                received = client.Receive(buffer)
            } catch receiveFailure: Exception {
                socketFailure := receiveFailure as SocketException
                if socketFailure != null && socketFailure.SocketErrorCode == SocketError.TimedOut && requestStream.Length > 0 {
                    break
                }

                throw
            }

            if received == 0 {
                break
            }

            requestStream.Write(buffer, 0, received)
        }

        if requestStream.Length == 0 {
            return
        }

        request: DaemonRequest? = null
        try {
            requestJson := Encoding.UTF8.GetString(requestStream.ToArray())
            request = JsonSerializer.Deserialize<DaemonRequest>(requestJson, DaemonJsonOptions)
        } catch parseFailure: Exception {
            jsonFailure := parseFailure as JsonException
            if jsonFailure == null {
                throw
            }

            SendResponse(client, Error(
                0,
                DaemonConstants.ErrorParse,
                DaemonProtocolKernels.GetMalformedRequestJsonMessage(),
                new DaemonParseErrorData(jsonFailure.Path, jsonFailure.LineNumber, jsonFailure.BytePositionInLine)
            ))
            return
        }

        if request == null || string.IsNullOrWhiteSpace(request.Method) {
            requestId := 0
            if request != null {
                requestId = request.Id
            }

            SendResponse(client, Error(requestId, DaemonConstants.ErrorInvalidRequest, DaemonProtocolKernels.GetMissingMethodMessage()))
            return
        }

        // Process request
        response := ProcessRequest(request)

        // Send response
        SendResponse(client, response)

        // `daemon/shutdown` cleared `running`; the accept loop is still blocked in `Accept`, and only
        // now — with the answer on its way — is it woken to wind down.
        if !Volatile.Read(ref running) {
            RequestStop()
        }
    }

    func ProcessRequest(request: DaemonRequest): DaemonResponse {
        try {
            methodKind := DaemonProtocolKernels.GetMethodKind(request.Method)

            // Daemon control methods
            if methodKind == DaemonMethodKind.Ping {
                return Ok(request.Id, DaemonProtocolKernels.GetPongResultJson())
            }

            if methodKind == DaemonMethodKind.Shutdown {
                Volatile.Write(ref running, false)
                return Ok(request.Id, DaemonProtocolKernels.GetShutdownResultJson())
            }

            if methodKind == DaemonMethodKind.Status {
                uptime := DateTime.UtcNow - CurrentProcessStartTimeUtc()
                return Ok(
                    request.Id,
                    DaemonProtocolKernels.StatusResultJson(
                        Environment.ProcessId,
                        DaemonProtocolKernels.FormatUptime(uptime.Hours, uptime.Minutes, uptime.Seconds),
                        projectRoot,
                        CachedFileCount(),
                        DaemonServerKernels.FormatDurationMilliseconds((long)Math.Round(idleTimeout.TotalMilliseconds)),
                        new DaemonStatusExecFacts(
                            DaemonExecHost.GetVersion(),
                            DaemonExecHost.GetIdentity(),
                            Volatile.Read(ref activeRequests),
                            Volatile.Read(ref servedRequests),
                            Environment.WorkingSet / 1048576L,
                            maxMemoryMegabytes,
                            WarmStateRegistry.Describe()
                        )
                    )
                )
            }

            if !DaemonProtocolKernels.IsQueryMethod(methodKind) {
                return Error(request.Id, DaemonConstants.ErrorMethodNotFound, DaemonServerKernels.GetUnknownMethodMessage(request.Method))
            }

            // A query from a client of another build would be answered by this build's compiler. The
            // client says which build it is, and is told to answer in-process instead.
            requestIdentity := GetParam<string>(request.Params, "identity")
            if requestIdentity != null && requestIdentity != DaemonExecHost.GetIdentity() {
                return Error(request.Id, DaemonProtocolKernels.GetIdentityMismatchErrorCode(), DaemonProtocolKernels.GetIdentityMismatchMessage())
            }

            // Queries share the compiler with exec requests; one thing runs at a time.
            Monitor.Enter(workGate)
            try {
                return ProcessQuery(request, methodKind)
            } finally {
                Monitor.Exit(workGate)
            }
        } catch ex: Exception {
            protocolFailure := ex as DaemonProtocolException
            if protocolFailure != null {
                return Error(request.Id, protocolFailure.Code, protocolFailure.Message)
            }

            return Error(request.Id, DaemonConstants.ErrorInternal, ex.Message)
        }
    }

    // Read without the work lock (status must answer while a command runs), so it reads a copy.
    func CachedFileCount(): int {
        count := 0
        try {
            loadedSnapshots := new List<ProjectSnapshot>(snapshots.Values)
            for loaded in loadedSnapshots {
                count = count + loaded.CompilationUnits.Count
            }
        } catch concurrentChange: Exception {
            return count
        }

        return count
    }

    func ProcessQuery(request: DaemonRequest, methodKind: DaemonMethodKind): DaemonResponse {
        try {
            // ONE SERVER, MANY PROJECTS. A query names the project it is about; a client from before
            // that parameter existed means the server's own root.
            queryRoot := projectRoot
            requestedRoot := GetParam<string>(request.Params, "projectRoot")
            if requestedRoot != null {
                queryRoot = Path.GetFullPath(requestedRoot ?? projectRoot)
            }

            loaded := EnsureSnapshot(queryRoot)
            if loaded == null {
                return Error(request.Id, DaemonConstants.ErrorInternal, DaemonServerKernels.GetFailedLoadProjectMessage())
            }

            if methodKind == DaemonMethodKind.Batch {
                requests := GetParam<List<BatchQueryRequest>>(request.Params, "requests")
                if requests == null || requests.Count == 0 {
                    return Ok(request.Id, OutputFormatter.ErrorToJson(
                        "batch",
                        DaemonServerKernels.GetEmptyBatchPayloadMessage(),
                        queryRoot,
                        "emptyBatch",
                        null
                    ))
                }

                execution := BatchQueryRunner.Execute(
                    requests,
                    queryRoot,
                    () => loaded,
                    service,
                    completionEngine
                )

                return Ok(request.Id, execution.Json)
            }

            // Extract params
            filePath := GetParam<string>(request.Params, "file")
            posStr := GetParam<string>(request.Params, "pos")
            kind := GetParam<string>(request.Params, "kind")
            severity := GetParam<string>(request.Params, "severity")
            includeKeywords := GetParam<bool>(request.Params, "includeKeywords")
            summary := GetParam<bool>(request.Params, "summary")
            compact := GetParam<bool>(request.Params, "compact")
            clusters := GetParam<bool>(request.Params, "clusters")

            line := 0
            col := 0
            if posStr != null {
                DaemonServerKernels.ParsePosition(posStr, out line, out col)
            }

            parameterValidation := DaemonProtocolKernels.ValidateRequiredParameters(methodKind, filePath != null)
            if !parameterValidation.IsValid {
                return Ok(request.Id, OutputFormatter.ErrorToJson(
                    parameterValidation.QueryCommand,
                    parameterValidation.Message,
                    null,
                    null,
                    null
                ))
            }

            // Query methods
            if methodKind == DaemonMethodKind.Symbols {
                return Ok(request.Id, HandleSymbols(loaded, filePath, kind))
            }

            if methodKind == DaemonMethodKind.Outline {
                return Ok(request.Id, HandleOutline(loaded, must filePath))
            }

            if methodKind == DaemonMethodKind.Diagnostics {
                return Ok(request.Id, HandleDiagnostics(loaded, filePath, severity, clusters))
            }

            if methodKind == DaemonMethodKind.Type {
                return Ok(request.Id, HandleType(loaded, must filePath, line, col))
            }

            if methodKind == DaemonMethodKind.Definition {
                return Ok(request.Id, HandleDefinition(loaded, must filePath, line, col))
            }

            if methodKind == DaemonMethodKind.References {
                return Ok(request.Id, HandleReferences(loaded, must filePath, line, col))
            }

            if methodKind == DaemonMethodKind.Completions {
                return Ok(request.Id, HandleCompletions(loaded, must filePath, line, col, includeKeywords))
            }

            if methodKind == DaemonMethodKind.Inspect {
                return Ok(request.Id, HandleInspect(loaded, must filePath, line, col, includeKeywords, summary || compact))
            }

            if methodKind == DaemonMethodKind.Batch {
                throw new InvalidOperationException(DaemonProtocolKernels.GetBatchDispatchAfterPrecheckMessage())
            }

            throw new DaemonProtocolException(DaemonConstants.ErrorMethodNotFound, DaemonServerKernels.GetUnknownMethodMessage(request.Method))
        } catch ex: Exception {
            protocolFailure := ex as DaemonProtocolException
            if protocolFailure != null {
                return Error(request.Id, protocolFailure.Code, protocolFailure.Message)
            }

            return Error(request.Id, DaemonConstants.ErrorInternal, ex.Message)
        }
    }

    // ── Query Handlers ──────────────────────────────────────────────────

    func HandleSymbols(loaded: ProjectSnapshot, filePath: string?, kind: string?): string {
        kindFilter: SymbolKind? = null
        if kind != null {
            parsedKind := QueryCommandKernels.ParseSymbolKind(kind)
            if parsedKind.HasValue {
                kindFilter = parsedKind.GetValueOrDefault()
            }
        }

        results := service.GetSymbols(loaded, filePath, kindFilter)
        return OutputFormatter.SymbolsToJson(results, loaded.ProjectRoot)
    }

    func HandleOutline(loaded: ProjectSnapshot, filePath: string): string {
        result := service.GetOutline(loaded, filePath)
        return OutputFormatter.OutlineToJson(result)
    }

    func HandleDiagnostics(loaded: ProjectSnapshot, filePath: string?, severity: string?, clusters: bool): string {
        results: List<DiagnosticResult> = service.GetDiagnostics(loaded, filePath)
        if severity != null {
            results = OutputFormatter.FilterDiagnosticsBySeverity(results, severity)
        }

        if clusters {
            return OutputFormatter.DiagnosticClustersToJson(results, loaded.ProjectRoot)
        }

        return OutputFormatter.DiagnosticsToJson(results, loaded.ProjectRoot)
    }

    func HandleType(loaded: ProjectSnapshot, filePath: string, line: int, col: int): string {
        result := service.GetTypeAtPosition(loaded, filePath, line, col)
        if result == null {
            return OutputFormatter.ErrorToJson(
                "type",
                DaemonServerKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                loaded.ProjectRoot,
                "noSymbol",
                PositionDetails(filePath, line, col)
            )
        }

        return OutputFormatter.TypeToJson(result, filePath, line, col)
    }

    func HandleDefinition(loaded: ProjectSnapshot, filePath: string, line: int, col: int): string {
        result := service.FindDefinition(loaded, filePath, line, col)
        if result == null {
            return OutputFormatter.ErrorToJson(
                "definition",
                DaemonServerKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                loaded.ProjectRoot,
                "noSymbol",
                PositionDetails(filePath, line, col)
            )
        }

        return OutputFormatter.DefinitionToJson(result)
    }

    func HandleReferences(loaded: ProjectSnapshot, filePath: string, line: int, col: int): string {
        // Resolve symbol metadata (same as CLI path — don't hardcode placeholders)
        definition := service.FindDefinition(loaded, filePath, line, col)
        if definition == null {
            return OutputFormatter.ErrorToJson(
                "references",
                DaemonServerKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                loaded.ProjectRoot,
                "noSymbol",
                PositionDetails(filePath, line, col)
            )
        }

        symbolName := definition.Name
        symbolKind := definition.Kind
        definedAt := new LocationResult(definition.File, definition.Line, definition.Column)

        results := service.FindReferences(loaded, filePath, line, col)
        if results.Count == 0 {
            details := PositionDetails(filePath, line, col)
            symbol := new Dictionary<string, object>()
            symbol["name"] = symbolName
            symbol["kind"] = symbolKind
            symbol["definedAt"] = definedAt
            details["symbol"] = symbol

            return OutputFormatter.ErrorToJson(
                "references",
                DaemonServerKernels.GetSemanticReferencesUnavailableMessage(),
                loaded.ProjectRoot,
                "semanticReferencesUnavailable",
                details
            )
        }

        return OutputFormatter.ReferencesToJson(symbolName, symbolKind, definedAt, results)
    }

    func HandleCompletions(loaded: ProjectSnapshot, filePath: string, line: int, col: int, includeKeywords: bool): string {
        result := completionEngine.GetCompletions(loaded, filePath, line, col, includeKeywords)
        return OutputFormatter.CompletionsToJson(result, filePath, line, col)
    }

    func HandleInspect(loaded: ProjectSnapshot, filePath: string, line: int, col: int, includeKeywords: bool, summary: bool): string {
        typeResult := service.GetTypeAtPosition(loaded, filePath, line, col)
        definition := service.FindDefinition(loaded, filePath, line, col)
        references: List<ReferenceResult> = new List<ReferenceResult>()
        if definition != null {
            references = service.FindReferences(loaded, filePath, line, col)
        }

        completions := completionEngine.GetCompletions(loaded, filePath, line, col, includeKeywords)

        if typeResult == null && definition == null && references.Count == 0 {
            return OutputFormatter.ErrorToJson(
                "inspect",
                DaemonServerKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                loaded.ProjectRoot,
                "noSymbol",
                PositionDetails(filePath, line, col)
            )
        }

        symbol: InspectSymbolResult? = null
        if definition != null {
            symbol = new InspectSymbolResult(
                definition.Name,
                definition.Kind,
                new LocationResult(definition.File, definition.Line, definition.Column)
            )
        } else if typeResult != null {
            symbol = new InspectSymbolResult(typeResult.Name, typeResult.Kind, typeResult.Definition)
        }

        definitionCount := references.Count(reference => reference.IsDefinition)
        inspect := new InspectResult(
            symbol,
            typeResult,
            definition,
            new InspectReferencesResult(
                references.Count,
                definitionCount,
                references.ToArray()
            ),
            completions
        )

        if summary {
            return OutputFormatter.InspectSummaryToJson(inspect, filePath, line, col)
        }

        return OutputFormatter.InspectToJson(inspect, filePath, line, col)
    }

    // ── Snapshot Management ─────────────────────────────────────────────

    // The project's snapshot, loaded on first use and kept until a watched file changes (any change
    // under the workspace drops every project's snapshot: a project's analysis reads its references'
    // sources too). Callers hold the work lock.
    func EnsureSnapshot(root: string): ProjectSnapshot? {
        if Volatile.Read(ref cacheInvalid) {
            Volatile.Write(ref cacheInvalid, false)
            snapshots.Clear()
        }

        if snapshots.ContainsKey(root) {
            return snapshots[root]
        }

        WriteDiagnostic(DaemonServerKernels.GetLoadingProjectMessage())
        sw := Stopwatch.StartNew()

        try {
            loaded := service.LoadProject(root)
            snapshots[root] = loaded
            sw.Stop()
            elapsedMilliseconds := sw.ElapsedMilliseconds
            fileCount := loaded.CompilationUnits.Count
            WriteDiagnostic(DaemonServerKernels.GetProjectLoadedMessage(elapsedMilliseconds, fileCount))
            return loaded
        } catch ex: Exception {
            WriteDiagnostic(DaemonServerKernels.GetProjectLoadFailedTraceMessage(ex.Message))
            return null
        }
    }

    // ── File Watching ───────────────────────────────────────────────────

    func StartFileWatcher() {
        try {
            watcher := new FileSystemWatcher(projectRoot)
            watcher.IncludeSubdirectories = true
            watcher.NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.CreationTime

            _changed := on watcher.Changed (sender, e) => {
                OnFileChanged(e.FullPath)
            }
            _created := on watcher.Created (sender, e) => {
                OnFileChanged(e.FullPath)
            }
            _deleted := on watcher.Deleted (sender, e) => {
                OnFileChanged(e.FullPath)
            }
            _renamed := on watcher.Renamed (sender, e) => {
                OnFileChanged(e.FullPath)
            }

            watcher.EnableRaisingEvents = true
            fileWatcher = watcher
            WriteDiagnostic(DaemonServerKernels.GetFileWatcherStartedMessage())
        } catch ex: Exception {
            WriteDiagnostic(DaemonServerKernels.GetFileWatcherFailedMessage(ex.Message))
        }
    }

    func OnFileChanged(fullPath: string) {
        if !DaemonServerKernels.ShouldInvalidateForChangedPath(fullPath) {
            return
        }

        fileName := DaemonServerKernels.GetChangedFileName(fullPath)
        WriteDiagnostic(DaemonServerKernels.GetFileChangedMessage(fileName))
        Volatile.Write(ref cacheInvalid, true)
        WarmStateRegistry.NotifyPathChanged(fullPath)
    }

    // ── Cleanup ─────────────────────────────────────────────────────────

    func Cleanup(pidPath: string) {
        fileWatcher?.Dispose()
        try {
            File.Delete(socketPath)
        } catch socketDeleteFailure: Exception {
            WriteDiagnostic(DaemonServerKernels.GetServerErrorMessage(socketDeleteFailure.Message))
        }

        try {
            File.Delete(pidPath)
        } catch pidDeleteFailure: Exception {
            WriteDiagnostic(DaemonServerKernels.GetServerErrorMessage(pidDeleteFailure.Message))
        }

        WriteDiagnostic(DaemonServerKernels.GetShutdownCompleteMessage())
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    // `new { file, position = new { line, column } }` was the C# spelling of this detail payload.
    // It is built here rather than read from `QueryErrorDetailKernels.Position` because that kernel
    // NORMALIZES the path and the daemon never did: the file is echoed back exactly as the client
    // sent it.
    static func PositionDetails(filePath: string, line: int, col: int): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["file"] = filePath
        payload["position"] = QueryErrorDetailKernels.BuildPosition(line, col)
        return payload
    }

    // `daemon status` reports UtcNow minus THIS PROCESS'S START, and it must keep doing exactly
    // that. `Process.GetCurrentProcess().StartTime` cannot be written here: the compiler that
    // builds `src/NSharpLang.Compiler` is the SEEDED BOOTSTRAP SDK, which predates the fix that
    // modelled the `Process` instance surface (census-briefs/CLI2-COMPILER-BLOCKERS.md, cli4), and
    // reseeding is not this lane's to do. The property is therefore read by name off the same
    // `Process` object; `Convert.ToDateTime` on the boxed result is `DateTime`'s own
    // `IConvertible.ToDateTime`, which returns the value unchanged, Kind included. This whole
    // function collapses back to one member access the moment the seed carries that fix.
    static func CurrentProcessStartTimeUtc(): DateTime {
        currentProcess := Process.GetCurrentProcess()
        startTimeProperty := must typeof(Process).GetProperty("StartTime")
        boxedStartTime := startTimeProperty.GetValue(currentProcess)
        startTime := Convert.ToDateTime(boxedStartTime)
        return startTime.ToUniversalTime()
    }

    static func Ok(id: int, result: string): DaemonResponse {
        // Assignments, not an object initializer: `nlc format` rewrites `new T() { … }` to the
        // parenless form and this envelope holds a nullable member, which declined at emit on the
        // compiler this file was written against.
        response := new DaemonResponse()
        response.Id = id
        response.Result = result
        return response
    }

    static func Error(id: int, code: int, message: string): DaemonResponse {
        return Error(id, code, message, null)
    }

    static func Error(id: int, code: int, message: string, data: object?): DaemonResponse {
        error := new DaemonError()
        error.Code = code
        error.Message = message
        error.Data = data

        response := new DaemonResponse()
        response.Id = id
        response.Error = error
        return response
    }

    static func SendResponse(socket: Socket, response: DaemonResponse) {
        responseJson := JsonSerializer.Serialize<DaemonResponse>(response, DaemonJsonOptions)
        responseBytes := Encoding.UTF8.GetBytes(responseJson)
        SendAll(socket, responseBytes)
    }

    static func GetParam<T>(paramsElement: JsonElement?, key: string): T? {
        if paramsElement == null {
            return default
        }

        value := paramsElement.Value
        if value.ValueKind != JsonValueKind.Object {
            return default
        }

        prop: JsonElement = default
        if value.TryGetProperty(key, out prop) {
            try {
                raw := prop.GetRawText()
                return JsonSerializer.Deserialize<T>(raw, DaemonJsonOptions)
            } catch ex: Exception {
                // Tolerate the malformed param (caller treats it as absent) but leave a trace —
                // a silently-dropped param turns protocol bugs into undebuggable client hangs.
                Console.Error.WriteLine(DaemonServerKernels.GetMalformedRequestParamMessage(
                    key,
                    typeof(T).Name,
                    ex.Message
                ))
                return default
            }
        }

        return default
    }

    static func SendAll(socket: Socket, bytes: byte[]) {
        sent := 0
        while sent < bytes.Length {
            sent = sent + socket.Send(bytes, sent, bytes.Length - sent, SocketFlags.None)
        }
    }
}

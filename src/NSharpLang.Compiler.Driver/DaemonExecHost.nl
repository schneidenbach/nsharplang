namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.Diagnostics
import System.Globalization
import System.IO
import System.Net.Sockets
import System.Text
import System.Threading
import NSharpLang.Compiler

// A command's stdout or stderr, inside the server: every write becomes one frame to the client.
//
// The two writers of one request share the session's send lock, so the client receives stdout and
// stderr writes in exactly the order the command made them. Characters are encoded with ONE stateful
// UTF-8 encoder per stream, so a surrogate pair split across two writes still arrives as one code
// point — the bytes the client prints are the bytes `Console.Out` would have printed.
//
// WHY A `StringWriter`. `TextWriter` declares `Encoding` abstract, and the seeded bootstrap compiler
// does not yet emit an override of an abstract PROPERTY declared by an external base (methods are
// fine). `StringWriter` already implements it, and every write it would buffer is overridden here to
// go to the client instead; `DrainStray` forwards anything that reached the base buffer through an
// overload not overridden here, so nothing a command writes is ever dropped.
class DaemonFrameWriter: StringWriter {
    session: DaemonExecSession
    kind: byte
    encoder: Encoder

    constructor(session: DaemonExecSession, kind: byte) {
        this.session = session
        this.kind = kind
        encoder = new UTF8Encoding(false).GetEncoder()
    }

    override func Write(value: char) {
        single := new char[](1)
        single[0] = value
        WriteChars(single, 0, 1)
    }

    override func Write(buffer: char[], index: int, count: int) {
        WriteChars(buffer, index, count)
    }

    override func Write(value: string?) {
        if value == null {
            return
        }

        text := value ?? ""
        if text.Length == 0 {
            return
        }

        chars := text.ToCharArray()
        WriteChars(chars, 0, chars.Length)
    }

    override func Flush() {
        DrainStray()
    }

    func DrainStray() {
        stray := GetStringBuilder()
        if stray.Length == 0 {
            return
        }

        text := stray.ToString()
        stray.Clear()
        chars := text.ToCharArray()
        WriteChars(chars, 0, chars.Length)
    }

    func WriteChars(buffer: char[], index: int, count: int) {
        if count <= 0 {
            return
        }

        lock encoder {
            byteCount := encoder.GetByteCount(buffer, index, count, false)
            bytes := new byte[](byteCount)
            written := encoder.GetBytes(buffer, index, count, bytes, 0, false)
            if written > 0 {
                session.SendOutput(kind, bytes, written)
            }
        }
    }
}

// The command's stdin, inside the server. Nothing is asked of the client until the command first
// reads: a command that never reads stdin never consumes a byte of the user's terminal or pipe.
class DaemonStdinReader: TextReader {
    session: DaemonExecSession
    decoder: Decoder
    pending: char[]
    pendingStart: int
    pendingEnd: int
    ended: bool

    constructor(session: DaemonExecSession) {
        this.session = session
        decoder = new UTF8Encoding(false).GetDecoder()
        pending = new char[](0)
        pendingStart = 0
        pendingEnd = 0
        ended = false
    }

    override func Peek(): int {
        if !Fill() {
            return -1
        }

        return (int)pending[pendingStart]
    }

    override func Read(): int {
        if !Fill() {
            return -1
        }

        value := pending[pendingStart]
        pendingStart = pendingStart + 1
        return (int)value
    }

    override func Read(buffer: char[], index: int, count: int): int {
        if count <= 0 {
            return 0
        }

        if !Fill() {
            return 0
        }

        available := pendingEnd - pendingStart
        taken := Math.Min(available, count)
        Array.Copy(pending, pendingStart, buffer, index, taken)
        pendingStart = pendingStart + taken
        return taken
    }

    // Make at least one character available. False at end of input.
    func Fill(): bool {
        while pendingStart >= pendingEnd {
            if ended {
                return false
            }

            chunk := session.ReadStdinChunk()
            if chunk == null {
                ended = true
                tailCount := decoder.GetCharCount(new byte[](0), 0, 0, true)
                if tailCount == 0 {
                    return false
                }

                pending = new char[](tailCount)
                pendingEnd = decoder.GetChars(new byte[](0), 0, 0, pending, 0, true)
                pendingStart = 0
                continue
            }

            bytes := chunk ?? new byte[](0)
            charCount := decoder.GetCharCount(bytes, 0, bytes.Length, false)
            pending = new char[](charCount)
            pendingEnd = decoder.GetChars(bytes, 0, bytes.Length, pending, 0, false)
            pendingStart = 0
        }

        return true
    }
}

// ONE EXEC CONNECTION, FROM REQUEST TO EXIT CODE.
//
// Three threads touch a session: the request thread (runs the command and writes its output), the
// reader thread (receives stdin, cancellation and child exit codes from the client) and the
// keep-alive thread. Every frame sent goes through `sendGate`, so frames never interleave.
class DaemonExecSession {
    socket: Socket
    stream: NetworkStream
    sendGate: object
    stdinGate: object
    stdinChunks: Queue<byte[]>
    stdinEnded: bool
    stdinRequested: bool
    launchReply: ManualResetEventSlim
    launchExitCode: int
    finished: bool
    cancelled: bool
    clientGone: bool

    constructor(socket: Socket) {
        this.socket = socket
        stream = new NetworkStream(socket, false)
        sendGate = new object()
        stdinGate = new object()
        stdinChunks = new Queue<byte[]>()
        stdinEnded = false
        stdinRequested = false
        launchReply = new ManualResetEventSlim(false)
        launchExitCode = 0
        finished = false
        cancelled = false
        clientGone = false
    }

    func Stream(): NetworkStream {
        return stream
    }

    func IsCancelled(): bool {
        return Volatile.Read(ref cancelled)
    }

    func IsFinished(): bool {
        return Volatile.Read(ref finished)
    }

    func MarkFinished() {
        Volatile.Write(ref finished, true)
    }

    // Sends a frame unless the client is gone; a failed send marks it gone rather than throwing into
    // the command that happened to be writing.
    func Send(kind: byte, payload: byte[], count: int) {
        lock sendGate {
            if Volatile.Read(ref clientGone) {
                return
            }

            try {
                offset := 0
                if count == 0 {
                    DaemonExecWire.WriteFrame(stream, kind, payload, 0, 0)
                    return
                }

                while offset < count {
                    chunk := Math.Min(count - offset, 65536)
                    DaemonExecWire.WriteFrame(stream, kind, payload, offset, chunk)
                    offset = offset + chunk
                }
            } catch sendFailure: Exception {
                Volatile.Write(ref clientGone, true)
            }
        }
    }

    // Command output. After a cancel, or once an isolated test run has terminated the request, the
    // client is no longer listening for it.
    func SendOutput(kind: byte, payload: byte[], count: int) {
        if IsCancelled() || CliInvocationContext.IsTerminated() {
            return
        }

        Send(kind, payload, count)
    }

    func ReadStdinChunk(): byte[]? {
        lock stdinGate {
            if !stdinRequested {
                stdinRequested = true
                Send(DaemonExecKernels.FrameStdinWanted(), new byte[](0), 0)
            }

            while stdinChunks.Count == 0 && !stdinEnded {
                Monitor.Wait(stdinGate)
            }

            if stdinChunks.Count > 0 {
                return stdinChunks.Dequeue()
            }

            return null
        }
    }

    func PushStdin(chunk: byte[]) {
        lock stdinGate {
            stdinChunks.Enqueue(chunk)
            Monitor.PulseAll(stdinGate)
        }
    }

    func EndStdin() {
        lock stdinGate {
            stdinEnded = true
            Monitor.PulseAll(stdinGate)
        }
    }

    // `nlc run`: the client starts the program on its own terminal and answers with the exit code.
    func Launch(arguments: string, workingDirectory: string?): int {
        launchReply.Reset()
        payload := DaemonExecWire.EncodeLaunch(arguments, workingDirectory)
        Send(DaemonExecKernels.FrameLaunch(), payload, payload.Length)
        launchReply.Wait()
        return Volatile.Read(ref launchExitCode)
    }

    func CompleteLaunch(exitCode: int) {
        Volatile.Write(ref launchExitCode, exitCode)
        launchReply.Set()
    }

    // The client cancelled (Ctrl-C) or disconnected. Child processes the command registered are
    // killed by `CliInvocationContext.Cancel`; stdin and a pending launch are released so the command
    // can unwind instead of waiting forever for a client that is not coming back.
    func Cancel() {
        if Volatile.Read(ref cancelled) {
            return
        }

        Volatile.Write(ref cancelled, true)
        CliInvocationContext.Cancel()
        EndStdin()
        if !launchReply.IsSet {
            Volatile.Write(ref launchExitCode, 130)
            launchReply.Set()
        }
    }

    func Dispose() {
        try {
            stream.Dispose()
        } catch disposeFailure: Exception {
            return
        }
    }
}

// THE SERVER HALF OF THE DAEMON-FIRST CLI.
//
// `DaemonServer` hands every connection that opens with the exec magic to `Serve`. One command runs
// at a time per server: a command reads the PROCESS's current directory, environment and console,
// and those cannot be two things at once. A request that cannot take the work lock within
// `GetBusyWaitMilliseconds` is answered "busy" and the client runs the command itself, so a second
// agent never queues behind a first agent's long test run.
class DaemonExecHost {
    private static executor: Func<string[], int>?
    private static version: string?
    private static identity: string?
    private static baselineNames: string[]?
    private static baselineValues: string[]?
    private static warmupHooks: List<Action> = new List<Action>()

    // Called by the CLI pipeline before `nlc daemon run`: the executor is the same in-process
    // dispatch a plain `nlc` invocation would reach, and the version is the CLI's own.
    static func Configure(cliVersion: string, commandExecutor: Func<string[], int>) {
        DaemonExecHost.version = cliVersion
        DaemonExecHost.executor = commandExecutor
        DaemonExecHost.identity = null
    }

    // Work the CLI above the server wants done once the server is warm (the test host starts its
    // first standby test worker here).
    static func AddWarmupHook(hook: Action) {
        DaemonExecHost.warmupHooks.Add(hook)
    }

    static func RunWarmupHooks() {
        for hook in DaemonExecHost.warmupHooks.ToArray() {
            hook()
        }
    }

    // Runs a command for the server's own purposes (the warm-up): in `directory`, with every byte it
    // writes discarded and the process's own environment.
    static func RunUnobserved(args: string[], directory: string): int {
        commandExecutor := DaemonExecHost.executor
        if commandExecutor == null {
            return InternalErrorBoundary.ExitCode()
        }

        originalDirectory := Directory.GetCurrentDirectory()
        originalOut := Console.Out
        originalError := Console.Error
        try {
            Directory.SetCurrentDirectory(directory)
            Console.SetOut(TextWriter.Null)
            Console.SetError(TextWriter.Null)
            run := commandExecutor
            return InternalErrorBoundary.Execute(() => run(args))
        } finally {
            Console.SetOut(originalOut)
            Console.SetError(originalError)
            Directory.SetCurrentDirectory(originalDirectory)
        }
    }

    static func IsConfigured(): bool {
        return DaemonExecHost.executor != null
    }

    static func GetVersion(): string {
        return DaemonExecHost.version ?? "unknown"
    }

    static func GetIdentity(): string {
        cached := DaemonExecHost.identity
        if cached != null {
            return cached
        }

        computed := DaemonBuildIdentity.Compute(GetVersion())
        DaemonExecHost.identity = computed
        return computed
    }

    // The environment the server started with: restored after every request so one client's
    // variables never leak into the next client's command.
    static func CaptureBaselineEnvironment() {
        names := DaemonProcessEnvironment.GetNames()
        values := new string[](names.Length)
        index := 0
        while index < names.Length {
            values[index] = Environment.GetEnvironmentVariable(names[index]) ?? ""
            index = index + 1
        }

        DaemonExecHost.baselineNames = names
        DaemonExecHost.baselineValues = values
    }

    // Runs one command for a client that already sent the exec magic. Never throws.
    static func Serve(server: DaemonServer, socket: Socket) {
        session := new DaemonExecSession(socket)
        try {
            ServeSession(server, session)
        } catch failure: Exception {
            server.WriteDiagnostic(DaemonExecKernels.GetServerCrashedLogMessage(failure.Message))
        } finally {
            session.MarkFinished()
            session.Dispose()
        }
    }

    static func ServeSession(server: DaemonServer, session: DaemonExecSession) {
        socket := session.socket
        socket.ReceiveTimeout = 0
        first := DaemonExecWire.ReadFrame(session.Stream())
        if first == null {
            return
        }

        requestFrame := first ?? new DaemonFrame((byte)0, new byte[](0))
        if requestFrame.Kind != DaemonExecKernels.FrameRequest() {
            return
        }

        request := DaemonExecWire.DecodeRequest(requestFrame.Payload)
        serverIdentity := GetIdentity()
        if request.ProtocolVersion != DaemonExecKernels.GetExecProtocolVersion() || request.Identity != serverIdentity || !IsConfigured() {
            mismatch := DaemonExecWire.EncodeString(serverIdentity)
            session.Send(DaemonExecKernels.FrameMismatch(), mismatch, mismatch.Length)
            return
        }

        if request.Args.Length == 0 || !DaemonExecKernels.IsRoutedCommandName(request.Args[0]) || !Directory.Exists(request.WorkingDirectory) {
            session.Send(DaemonExecKernels.FrameBusy(), new byte[](0), 0)
            return
        }

        if !Monitor.TryEnter(server.WorkGate(), DaemonExecKernels.GetBusyWaitMilliseconds()) {
            session.Send(DaemonExecKernels.FrameBusy(), new byte[](0), 0)
            return
        }

        // A reference this process loaded has changed on disk: it can no longer answer as a fresh
        // process would (`DaemonLoadedReferenceGuard`). Decline, and retire once the lock is free.
        changedReference := server.ReferenceGuard().FindChanged()
        if changedReference != null {
            Monitor.Exit(server.WorkGate())
            server.WriteDiagnostic(DaemonExecKernels.GetStaleReferenceMessage(changedReference ?? ""))
            session.Send(DaemonExecKernels.FrameBusy(), new byte[](0), 0)
            server.RequestStop()
            return
        }

        try {
            server.BeginRequest()
            pidBytes := DaemonExecWire.EncodeInt32(Environment.ProcessId)
            session.Send(DaemonExecKernels.FrameAccepted(), pidBytes, pidBytes.Length)
            StartReader(server, session)
            StartKeepAlive(session)
            stopwatch := Stopwatch.StartNew()
            exitCode := Execute(server, session, request)
            stopwatch.Stop()
            server.ReferenceGuard().Record()
            if !session.IsCancelled() {
                exitBytes := DaemonExecWire.EncodeInt32(exitCode)
                session.Send(DaemonExecKernels.FrameDone(), exitBytes, exitBytes.Length)
            }

            commandName := ""
            if request.Args.Length > 0 {
                commandName = request.Args[0]
            }

            server.WriteDiagnostic(DaemonExecKernels.GetExecMessage(commandName, exitCode, stopwatch.ElapsedMilliseconds))
        } finally {
            session.MarkFinished()
            server.EndRequest()
            Monitor.Exit(server.WorkGate())
        }

        server.CheckResourceCaps()
    }

    // The command, run exactly as `CliPipeline` would run it in the client's own process: the
    // client's directory, environment, culture, console and command line, behind the same internal
    // error boundary `Main` puts around every command.
    static func Execute(server: DaemonServer, session: DaemonExecSession, request: DaemonExecRequest): int {
        originalDirectory := Directory.GetCurrentDirectory()
        originalOut := Console.Out
        originalError := Console.Error
        originalIn := Console.In
        originalCulture := CultureInfo.CurrentCulture
        originalUiCulture := CultureInfo.CurrentUICulture
        stdout := new DaemonFrameWriter(session, DaemonExecKernels.FrameStdout())
        stderr := new DaemonFrameWriter(session, DaemonExecKernels.FrameStderr())
        stdin := new DaemonStdinReader(session)
        launcher: Func<string, string?, int> = (arguments, workingDirectory) => session.Launch(arguments, workingDirectory)
        try {
            ApplyEnvironment(request.EnvironmentNames, request.EnvironmentValues)
            Environment.SetEnvironmentVariable(DaemonExecKernels.GetDaemonChildEnvironmentVariable(), "1")
            Directory.SetCurrentDirectory(request.WorkingDirectory)
            ApplyCulture(request.Culture, request.UiCulture)
            Console.SetOut(stdout)
            Console.SetError(stderr)
            Console.SetIn(stdin)
            CliInvocationContext.Begin(request.CommandLineArgs, request.StderrRedirected, launcher)
            commandExecutor := DaemonExecHost.executor
            if commandExecutor == null {
                return InternalErrorBoundary.ExitCode()
            }

            run := commandExecutor
            args := request.Args
            exitCode := InternalErrorBoundary.Execute(() => run(args))
            terminatedExitCode := 0
            if CliInvocationContext.TryGetTerminatedExitCode(out terminatedExitCode) {
                return terminatedExitCode
            }

            return exitCode
        } finally {
            try {
                Console.Out.Flush()
                Console.Error.Flush()
            } catch flushFailure: Exception {
                server.WriteDiagnostic(DaemonServerKernels.GetServerErrorMessage(flushFailure.Message))
            }

            CliInvocationContext.End()
            Console.SetOut(originalOut)
            Console.SetError(originalError)
            Console.SetIn(originalIn)
            RestoreCulture(originalCulture, originalUiCulture)
            RestoreBaselineEnvironment()
            try {
                Directory.SetCurrentDirectory(originalDirectory)
            } catch directoryFailure: Exception {
                Directory.SetCurrentDirectory(Path.GetTempPath())
            }
        }
    }

    // The client's culture, on this thread and as the default for threads the command starts (the
    // compiler emits on its own wide-stack thread). The thread's culture is set through
    // `Thread.CurrentThread`; the two process-wide defaults are static property SETTERS, which the
    // seeded bootstrap compiler does not emit yet, so they are written through the same `PropertyInfo`
    // a setter call would invoke — `DaemonServer.CurrentProcessStartTimeUtc` reads `Process.StartTime`
    // the same way for the same reason.
    static func ApplyCulture(culture: string, uiCulture: string) {
        resolved := CultureInfo.InvariantCulture
        resolvedUi := CultureInfo.InvariantCulture
        try {
            resolved = CultureInfo.GetCultureInfo(culture)
            resolvedUi = CultureInfo.GetCultureInfo(uiCulture)
        } catch cultureFailure: Exception {
            resolved = CultureInfo.InvariantCulture
            resolvedUi = CultureInfo.InvariantCulture
        }

        SetThreadCultures(resolved, resolvedUi)
        SetDefaultThreadCultures(resolved, resolvedUi)
    }

    static func RestoreCulture(culture: CultureInfo, uiCulture: CultureInfo) {
        SetThreadCultures(culture, uiCulture)
        SetDefaultThreadCultures(null, null)
    }

    static func SetThreadCultures(culture: CultureInfo, uiCulture: CultureInfo) {
        current := Thread.CurrentThread
        current.CurrentCulture = culture
        current.CurrentUICulture = uiCulture
    }

    static func SetDefaultThreadCultures(culture: CultureInfo?, uiCulture: CultureInfo?) {
        cultureProperty := must typeof(CultureInfo).GetProperty("DefaultThreadCurrentCulture")
        uiCultureProperty := must typeof(CultureInfo).GetProperty("DefaultThreadCurrentUICulture")
        cultureProperty.SetValue(null, culture)
        uiCultureProperty.SetValue(null, uiCulture)
    }

    // The process environment becomes EXACTLY the client's: variables the client does not have are
    // removed, not merely left over from the server's own start.
    static func ApplyEnvironment(names: string[], values: string[]) {
        wanted := new HashSet<string>(StringComparer.Ordinal)
        for name in names {
            wanted.Add(name)
        }

        for existing in DaemonProcessEnvironment.GetNames() {
            if !wanted.Contains(existing) {
                Environment.SetEnvironmentVariable(existing, null)
            }
        }

        index := 0
        while index < names.Length {
            Environment.SetEnvironmentVariable(names[index], values[index])
            index = index + 1
        }
    }

    static func RestoreBaselineEnvironment() {
        names := DaemonExecHost.baselineNames
        values := DaemonExecHost.baselineValues
        if names == null || values == null {
            return
        }

        ApplyEnvironment(names ?? new string[](0), values ?? new string[](0))
    }

    // Receives stdin bytes, end of stdin, cancellation and `nlc run` exit codes. A client that goes
    // away without a cancel frame is treated as a cancel: nobody will read what the command prints.
    static func StartReader(server: DaemonServer, session: DaemonExecSession) {
        body: ThreadStart = () => {
            try {
                while !session.IsFinished() {
                    frame := DaemonExecWire.ReadFrame(session.Stream())
                    if frame == null {
                        if !session.IsFinished() {
                            session.Cancel()
                            server.RetireIfStillRunning(session)
                        }

                        return
                    }

                    current := frame ?? new DaemonFrame((byte)0, new byte[](0))
                    kind := current.Kind
                    if kind == DaemonExecKernels.FrameStdinData() {
                        session.PushStdin(current.Payload)
                    } else if kind == DaemonExecKernels.FrameStdinEnd() {
                        session.EndStdin()
                    } else if kind == DaemonExecKernels.FrameChildExit() {
                        session.CompleteLaunch(DaemonExecWire.DecodeInt32(current.Payload, 0))
                    } else if kind == DaemonExecKernels.FrameCancel() {
                        session.Cancel()
                        server.RetireIfStillRunning(session)
                        return
                    }
                }
            } catch readFailure: Exception {
                if !session.IsFinished() {
                    session.Cancel()
                    server.RetireIfStillRunning(session)
                }
            }
        }
        reader := new Thread(body)
        reader.IsBackground = true
        reader.Name = "nlc-exec-reader"
        reader.Start()
    }

    static func StartKeepAlive(session: DaemonExecSession) {
        body: ThreadStart = () => {
            while !session.IsFinished() {
                Thread.Sleep(DaemonExecKernels.GetKeepAliveIntervalMilliseconds())
                if !session.IsFinished() {
                    session.Send(DaemonExecKernels.FrameKeepAlive(), new byte[](0), 0)
                }
            }
        }
        keepAlive := new Thread(body)
        keepAlive.IsBackground = true
        keepAlive.Name = "nlc-exec-keepalive"
        keepAlive.Start()
    }
}

// The names of the current process's environment variables, ordinally sorted.
class DaemonProcessEnvironment {
    static func GetNames(): string[] {
        variables := Environment.GetEnvironmentVariables()
        names := new List<string>()
        for key in variables.Keys {
            name := key as string
            if name != null {
                names.Add(name ?? "")
            }
        }

        result := names.ToArray()
        Array.Sort(result, StringComparer.Ordinal)
        return result
    }
}

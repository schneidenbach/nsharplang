namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.Diagnostics
import System.Globalization
import System.IO
import System.Net.Sockets
import System.Reflection
import System.Runtime.InteropServices
import System.Threading
import NSharpLang.Cli

// How one exec attempt ended, from the client's side.
enum DaemonExecOutcome {
    Completed = 0,
    NotRouted = 1,
    Busy = 2,
    Mismatch = 3,
    Lost = 4
}

// THE CLIENT HALF OF THE DAEMON-FIRST CLI.
//
// `CliPipeline` asks `TryExecute` before running a routed command itself. The answer is either an
// exit code the server produced — with the server's stdout and stderr already written, byte for
// byte, to this process's own streams — or "run it yourself". Every failure on this side ends in
// "run it yourself": a missing server (one is started in the background for next time), a busy
// server, a server of another build (replaced in the background), or a server that dies or freezes
// mid-command (one line on stderr says so).
//
// The client is the cold half: it runs on every invocation, before anything is JIT-compiled. So it
// does as little as possible — no JSON, no reflection-driven serialization, no cryptography.
class DaemonExecClient {
    static func TryExecute(args: string[], version: string, out exitCode: int): bool {
        exitCode = 0
        if !DaemonExecKernels.ShouldRoute(
            args,
            Environment.GetEnvironmentVariable(DaemonExecKernels.GetNoDaemonEnvironmentVariable()),
            Environment.GetEnvironmentVariable(DaemonExecKernels.GetDaemonChildEnvironmentVariable()),
            Environment.GetEnvironmentVariable(DaemonExecKernels.GetCiEnvironmentVariable()),
            Environment.GetEnvironmentVariable(DaemonExecKernels.GetDaemonOptInEnvironmentVariable())
        ) {
            return false
        }

        trace := DaemonClientTrace.Start()
        routedExitCode := 0
        outcome := DaemonExecOutcome.NotRouted
        try {
            outcome = Route(args, version, trace, out routedExitCode)
        } catch routeFailure: Exception {
            trace.Note("client-error:" + routeFailure.GetType().Name)
            outcome = DaemonExecOutcome.NotRouted
        }

        trace.Finish(outcome)
        if outcome == DaemonExecOutcome.Completed {
            exitCode = routedExitCode
            return true
        }

        return false
    }

    static func Route(args: string[], version: string, trace: DaemonClientTrace, out exitCode: int): DaemonExecOutcome {
        exitCode = 0
        workingDirectory := Directory.GetCurrentDirectory()
        workspaceRoot := DaemonWorkspace.ResolveForRouting(workingDirectory)
        if workspaceRoot == null {
            trace.Note("no-workspace")
            return DaemonExecOutcome.NotRouted
        }

        root := workspaceRoot ?? workingDirectory
        socketPath := DaemonConstants.GetSocketPath(root)
        trace.Mark("resolve")
        identity := DaemonBuildIdentity.Compute(version)
        trace.Mark("identity")

        socket := TryConnect(socketPath)
        trace.Mark("connect")
        if socket == null {
            trace.Note("no-server")
            DaemonAutoStart.Spawn(root, socketPath, false)
            return DaemonExecOutcome.NotRouted
        }

        request := BuildRequest(args, identity, workingDirectory)
        session := new DaemonClientSession(socket ?? new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified))
        sessionExitCode := 0
        outcome := session.Run(request, trace, out sessionExitCode)
        if outcome == DaemonExecOutcome.Completed {
            exitCode = sessionExitCode
            return outcome
        }

        if outcome == DaemonExecOutcome.Mismatch {
            trace.Note("mismatch")
            DaemonClient.StopDaemon(root)
            DaemonAutoStart.Spawn(root, socketPath, true)
            return outcome
        }

        if outcome == DaemonExecOutcome.Lost {
            Console.Error.WriteLine(DaemonExecKernels.GetServerLostNote())
            return outcome
        }

        trace.Note("busy")
        return outcome
    }

    static func TryConnect(socketPath: string): Socket? {
        if !File.Exists(socketPath) {
            return null
        }

        socket := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)
        try {
            socket.Connect(new UnixDomainSocketEndPoint(socketPath))
            return socket
        } catch connectFailure: Exception {
            socket.Dispose()
            return null
        }
    }

    static func BuildRequest(args: string[], identity: string, workingDirectory: string): DaemonExecRequest {
        names := DaemonProcessEnvironment.GetNames()
        values := new string[](names.Length)
        index := 0
        while index < names.Length {
            values[index] = Environment.GetEnvironmentVariable(names[index]) ?? ""
            index = index + 1
        }

        return new DaemonExecRequest(
            DaemonExecKernels.GetExecProtocolVersion(),
            identity,
            args,
            Environment.GetCommandLineArgs(),
            workingDirectory,
            names,
            values,
            CultureInfo.CurrentCulture.Name,
            CultureInfo.CurrentUICulture.Name,
            Console.IsOutputRedirected,
            Console.IsErrorRedirected,
            Console.IsInputRedirected,
            Environment.ProcessId
        )
    }
}

// One exec conversation with a server, from the client's side.
class DaemonClientSession {
    socket: Socket
    stream: NetworkStream
    sendGate: object
    stdout: Stream
    stderr: Stream
    pending: List<DaemonFrame>
    pendingBytes: int
    committed: bool
    serverProcessId: int
    launched: bool
    launchedExitCode: int
    stdinPumpStarted: bool
    outputClock: Stopwatch

    constructor(socket: Socket) {
        this.socket = socket
        stream = new NetworkStream(socket, true)
        sendGate = new object()
        stdout = Console.OpenStandardOutput()
        stderr = Console.OpenStandardError()
        pending = new List<DaemonFrame>()
        pendingBytes = 0
        committed = false
        serverProcessId = 0
        launched = false
        launchedExitCode = 0
        stdinPumpStarted = false
        outputClock = Stopwatch.StartNew()
    }

    func Run(request: DaemonExecRequest, trace: DaemonClientTrace, out exitCode: int): DaemonExecOutcome {
        exitCode = 0
        cancelSubscription := on Console.CancelKeyPress (sender, eventArgs) => OnInterrupt()
        terminateRegistration := PosixSignalRegistration.Create(PosixSignal.SIGTERM, (context) => OnInterrupt())
        try {
            return Converse(request, trace, out exitCode)
        } finally {
            terminateRegistration.Dispose()
            off cancelSubscription
            try {
                stream.Dispose()
            } catch disposeFailure: Exception {
                trace.Note("dispose")
            }
        }
    }

    func Converse(request: DaemonExecRequest, trace: DaemonClientTrace, out exitCode: int): DaemonExecOutcome {
        exitCode = 0
        try {
            magic := DaemonExecKernels.GetExecMagic()
            payload := DaemonExecWire.EncodeRequest(request)
            lock sendGate {
                stream.Write(magic, 0, magic.Length)
                DaemonExecWire.WriteFrame(stream, DaemonExecKernels.FrameRequest(), payload, 0, payload.Length)
            }

            trace.Mark("send")
            connection := socket
            connection.ReceiveTimeout = DaemonExecKernels.GetHangTimeoutMilliseconds()
        } catch sendFailure: Exception {
            return DaemonExecOutcome.Busy
        }

        // The first answer decides whether this server will run the command at all. A server that
        // does not speak this wire (an older build's JSON-RPC daemon) answers with bytes that are not
        // a frame; that is a mismatch, not a crash.
        first: DaemonFrame? = null
        try {
            first = DaemonExecWire.ReadFrame(stream)
        } catch firstFailure: Exception {
            invalid := firstFailure as InvalidDataException
            if invalid != null {
                return DaemonExecOutcome.Mismatch
            }

            return DaemonExecOutcome.Busy
        }

        if first == null {
            return DaemonExecOutcome.Busy
        }

        firstFrame := first ?? new DaemonFrame((byte)0, new byte[](0))
        if firstFrame.Kind == DaemonExecKernels.FrameBusy() {
            return DaemonExecOutcome.Busy
        }

        if firstFrame.Kind != DaemonExecKernels.FrameAccepted() {
            return DaemonExecOutcome.Mismatch
        }

        serverProcessId = DaemonExecWire.DecodeInt32(firstFrame.Payload, 0)
        trace.Mark("accepted")
        outputClock.Restart()

        while true {
            frame: DaemonFrame? = null
            try {
                frame = DaemonExecWire.ReadFrame(stream)
            } catch readFailure: Exception {
                return Lose(readFailure, trace, out exitCode)
            }

            if frame == null {
                return Lose(null, trace, out exitCode)
            }

            current := frame ?? new DaemonFrame((byte)0, new byte[](0))
            kind := current.Kind
            if kind == DaemonExecKernels.FrameStdout() || kind == DaemonExecKernels.FrameStderr() {
                Output(current)
            } else if kind == DaemonExecKernels.FrameDone() {
                Commit()
                exitCode = DaemonExecWire.DecodeInt32(current.Payload, 0)
                trace.Mark("done")
                return DaemonExecOutcome.Completed
            } else if kind == DaemonExecKernels.FrameStdinWanted() {
                StartStdinPump()
            } else if kind == DaemonExecKernels.FrameLaunch() {
                Commit()
                LaunchProgram(current.Payload)
            }
        }
    }

    // The server stopped answering mid-command. Before anything reached the terminal the in-process
    // rerun prints the only copy; once a program was launched for `nlc run`, its exit code IS the
    // command's, and running it again would run the user's program twice.
    func Lose(failure: Exception?, trace: DaemonClientTrace, out exitCode: int): DaemonExecOutcome {
        exitCode = 0
        if failure != null {
            trace.Note("lost:" + (failure ?? new Exception()).GetType().Name)
            if IsTimeout(failure) && serverProcessId > 0 {
                DaemonAutoStart.KillFrozenServer(serverProcessId)
            }
        } else {
            trace.Note("lost:eof")
        }

        if launched {
            Commit()
            exitCode = launchedExitCode
            return DaemonExecOutcome.Completed
        }

        return DaemonExecOutcome.Lost
    }

    static func IsTimeout(failure: Exception?): bool {
        current := failure
        while current != null {
            socketFailure := current as SocketException
            if socketFailure != null && socketFailure.SocketErrorCode == SocketError.TimedOut {
                return true
            }

            current = (current ?? new Exception()).InnerException
        }

        return false
    }

    // Output is held back briefly (see `GetOutputCommitMilliseconds`), then written through.
    func Output(frame: DaemonFrame) {
        if committed {
            Write(frame)
            return
        }

        pending.Add(frame)
        pendingBytes = pendingBytes + frame.Payload.Length
        if pendingBytes >= DaemonExecKernels.GetOutputCommitBytes() || outputClock.ElapsedMilliseconds >= DaemonExecKernels.GetOutputCommitMilliseconds() {
            Commit()
        }
    }

    func Commit() {
        if committed {
            return
        }

        committed = true
        for frame in pending {
            Write(frame)
        }

        pending.Clear()
        pendingBytes = 0
    }

    func Write(frame: DaemonFrame) {
        target := stdout
        if frame.Kind == DaemonExecKernels.FrameStderr() {
            target = stderr
        }

        target.Write(frame.Payload, 0, frame.Payload.Length)
        target.Flush()
    }

    // Ctrl-C or SIGTERM: what was printed stays printed, the server is told, and this process then
    // ends exactly as an in-process command would (the handler does not cancel the signal).
    func OnInterrupt() {
        try {
            Commit()
            lock sendGate {
                DaemonExecWire.WriteFrame(stream, DaemonExecKernels.FrameCancel(), new byte[](0), 0, 0)
            }
        } catch interruptFailure: Exception {
            return
        }
    }

    func StartStdinPump() {
        if stdinPumpStarted {
            return
        }

        stdinPumpStarted = true
        body: ThreadStart = () => {
            try {
                input := Console.OpenStandardInput()
                buffer := new byte[](65536)
                while true {
                    received := input.Read(buffer, 0, buffer.Length)
                    if received <= 0 {
                        break
                    }

                    chunk := new byte[](received)
                    Array.Copy(buffer, chunk, received)
                    lock sendGate {
                        DaemonExecWire.WriteFrame(stream, DaemonExecKernels.FrameStdinData(), chunk, 0, received)
                    }
                }

                lock sendGate {
                    DaemonExecWire.WriteFrame(stream, DaemonExecKernels.FrameStdinEnd(), new byte[](0), 0, 0)
                }
            } catch pumpFailure: Exception {
                return
            }
        }
        pump := new Thread(body)
        pump.IsBackground = true
        pump.Name = "nlc-stdin-pump"
        pump.Start()
    }

    // `nlc run`: the program starts HERE, on this process's terminal, the way `DotnetRunner` starts it
    // in-process; the server waits for its exit code.
    func LaunchProgram(payload: byte[]) {
        arguments := DaemonExecWire.DecodeLaunchArguments(payload)
        workingDirectory := DaemonExecWire.DecodeLaunchWorkingDirectory(payload)
        directory: string? = null
        if workingDirectory != "" {
            directory = workingDirectory
        }

        psi := DotnetRunner.BuildPsi("dotnet", arguments, directory)
        psi.RedirectStandardOutput = false
        psi.RedirectStandardError = false
        psi.UseShellExecute = false
        process := new Process { StartInfo: psi }
        launched = true
        process.Start()
        process.WaitForExit()
        launchedExitCode = process.ExitCode
        process.Dispose()
        exitBytes := DaemonExecWire.EncodeInt32(launchedExitCode)
        try {
            lock sendGate {
                DaemonExecWire.WriteFrame(stream, DaemonExecKernels.FrameChildExit(), exitBytes, 0, exitBytes.Length)
            }
        } catch replyFailure: Exception {
            return
        }
    }
}

// Starting a server for next time, and stopping one that froze.
class DaemonAutoStart {
    // Starts `daemon run --background` for the workspace and returns at once: the command that
    // asked runs in-process, and the NEXT command finds a warm server. A recent attempt (the spawn
    // marker) suppresses another, so a server that cannot start does not cost a process per command;
    // `force` (a mismatch just retired the old server) skips that check.
    static func Spawn(workspaceRoot: string, socketPath: string, force: bool): bool {
        try {
            socketDirectory := Path.GetDirectoryName(socketPath) ?? workspaceRoot
            markerPath := Path.Combine(socketDirectory, DaemonExecKernels.GetSpawnMarkerFileName())
            if !force && File.Exists(markerPath) {
                age := DateTime.UtcNow - File.GetLastWriteTimeUtc(markerPath)
                if age.TotalMilliseconds >= 0 && age.TotalMilliseconds < (double)DaemonExecKernels.GetSpawnBackoffMilliseconds() {
                    return false
                }
            }

            processPath := Environment.ProcessPath
            if processPath == null {
                return false
            }

            File.WriteAllText(markerPath, Environment.ProcessId.ToString())
            entryAssembly := Assembly.GetEntryAssembly()
            entryPath: string? = null
            if entryAssembly != null {
                entryPath = entryAssembly.Location
            }

            command := DaemonExecKernels.GetServerLaunchCommand(processPath ?? "", entryPath, workspaceRoot, true)
            psi := new ProcessStartInfo()
            psi.FileName = command[0]
            index := 1
            while index < command.Length {
                psi.ArgumentList.Add(command[index])
                index = index + 1
            }

            // Fresh pipes for all three streams: the server must not hold this process's stdout open,
            // or a caller reading it to end-of-file would wait for the server's idle timeout.
            psi.UseShellExecute = false
            psi.RedirectStandardInput = true
            psi.RedirectStandardOutput = true
            psi.RedirectStandardError = true
            psi.CreateNoWindow = true
            psi.WorkingDirectory = workspaceRoot
            psi.Environment.Remove(DaemonExecKernels.GetDaemonChildEnvironmentVariable())
            psi.Environment[DaemonClientKernels.GetStartupOutputLogEnvironmentVariableName()] = Path.Combine(socketDirectory, DaemonExecKernels.GetLogFileName())
            process := Process.Start(psi)
            if process == null {
                return false
            }

            (process ?? new Process()).Dispose()
            return true
        } catch spawnFailure: Exception {
            return false
        }
    }

    // A server that stopped sending keep-alives for the whole hang window is frozen; the client
    // that noticed retires it so the next command starts a healthy one.
    static func KillFrozenServer(processId: int) {
        try {
            process := Process.GetProcessById(processId)
            process.Kill(true)
            process.Dispose()
        } catch killFailure: Exception {
            return
        }
    }
}

// `NLC_DAEMON_TRACE=1` prints one line to stderr after a routed command: which way it went and
// where the client's time went. Off by default, so it never changes a command's output.
class DaemonClientTrace {
    enabled: bool
    clock: Stopwatch
    marks: List<string>

    constructor(enabled: bool) {
        this.enabled = enabled
        clock = Stopwatch.StartNew()
        marks = new List<string>()
    }

    static func Start(): DaemonClientTrace {
        value := Environment.GetEnvironmentVariable("NLC_DAEMON_TRACE")
        return new DaemonClientTrace(value != null && value != "" && value != "0")
    }

    func Mark(name: string) {
        if enabled {
            marks.Add(name + "=" + clock.ElapsedMilliseconds.ToString())
        }
    }

    func Note(text: string) {
        if enabled {
            marks.Add(text)
        }
    }

    func Finish(outcome: DaemonExecOutcome) {
        if !enabled {
            return
        }

        route := "in-process"
        if outcome == DaemonExecOutcome.Completed {
            route = "daemon"
        }

        Console.Error.WriteLine("[nlc-daemon] route=" + route + " " + String.Join(" ", marks) + " client-ms=" + clock.ElapsedMilliseconds.ToString() + " process-ms=" + ((long)(DateTime.UtcNow - DaemonServer.CurrentProcessStartTimeUtc()).TotalMilliseconds).ToString())
    }
}

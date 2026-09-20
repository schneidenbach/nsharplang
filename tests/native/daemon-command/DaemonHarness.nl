namespace NSharpLang.DaemonCommand.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Net.Sockets
import System.Text
import System.Text.Json
import System.Threading
import NSharpLang.Cli.Daemon

// ─── THE DAEMON CONTRACTS, HALF AS LIBRARY CALLS AND HALF AS PROCESSES ────────────────────────
//
// This project replaces `tests/DaemonCommandTests.cs`. That file reached its subject two ways, and
// the two ways land differently here.
//
// The rows that called ORDINARY PUBLIC TYPES — `DaemonConstants`, `DaemonClient`, the
// `DaemonRequest`/`DaemonResponse` envelope, `DaemonServer` itself — still call them directly, from
// here, against `Cli.dll` as a referenced assembly. Nothing is lost: those are the same objects the
// deleted C# touched.
//
// The six rows that READ WHAT A COMMAND PRINTED spawn the REAL built CLI instead — `dotnet
// <repoRoot>/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll <args>` with the fixture directory as the
// child's working directory — and read the child's pipes.
//
// THAT IS A CHOICE FOR STRENGTH, NOT A WORKAROUND, AND THE DIFFERENCE WAS MEASURED. The deleted C#
// captured stdout by swapping `Console.SetOut` around an in-process `DaemonCommand.Execute(...)` or
// `QueryCommand.Execute(...)` call. `Console.SetOut` is NOT a declining shape on this emit path —
// measured out of repository, a `.tests.nl` that swaps `Console.Out`, writes, restores it and reads
// the captured text compiles and passes — so the in-process spelling was available and was
// rejected on merit: calling `DaemonCommand.Execute` proves nothing about whether `nlc daemon`
// REACHES `DaemonCommand` in the binary a user installs, and calling `QueryCommand.Execute` proves
// nothing about `nlc query`. A child process proves the dispatch, the exit code, and which STREAM
// each sentence reached, all of which the deleted bodies were silent about.
//
// Every daemon this project starts is stopped in a `finally`, and every temporary directory is
// deleted in the same block, so a failing row leaves neither an orphan listener nor a stray socket.

// ─── A CHILD PROCESS RUN ──────────────────────────────────────────────────────────────────────
class ProcessRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

// Start a child process, drain BOTH pipes concurrently, wait for it under a ceiling, and dispose
// it. Draining stdout and stderr as tasks BEFORE the wait is what keeps a chatty child from
// deadlocking against a full pipe buffer; the ceiling is what turns a hung toolchain into a failing
// row rather than a hung gate.
func RunProcess(fileName: string, arguments: string, workingDirectory: string, timeoutMilliseconds: int): ProcessRun {
    startInfo := new ProcessStartInfo { FileName: fileName, Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(timeoutMilliseconds) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("Process '" + fileName + " " + arguments + "' did not complete within " + timeoutMilliseconds.ToString() + " ms.")
    }

    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    exitCode := process.ExitCode
    process.Dispose()
    return new ProcessRun(exitCode, stdout, stderr)
}

// ─── FINDING THE BUILT CLI AND THE FIXTURES ───────────────────────────────────────────────────

func RepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the repository root above this test tree.")
}

func CliDll(): string {
    root := RepositoryRoot()
    cliDll := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), Path.Combine("net10.0", "Cli.dll"))
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The built N# CLI was not found beside the repository root.")
    }

    return cliDll
}

func Quote(value: string): string {
    return "\"" + value + "\""
}

// `nlc <arguments>`, run from `workingDirectory`. Two minutes is a generous ceiling for a daemon
// handshake or a single query; anything slower is hung, not slow.
func Nlc(arguments: string, workingDirectory: string): ProcessRun {
    return RunProcess("dotnet", Quote(CliDll()) + " " + arguments, workingDirectory, 120000)
}

// ─── TEMPORARY PROJECTS ON DISK ───────────────────────────────────────────────────────────────
//
// The deleted C# built its fixtures at `/tmp/nlc-<12 hex>` and that length is LOAD-BEARING, not
// incidental: `DaemonConstants.GetSocketPath` only keeps the socket inside the project's own `.nlc`
// directory while the resulting path fits a Unix domain socket's 100-byte name. A fixture under the
// platform temp directory (`/var/folders/.../T/` on macOS) overflows that budget and silently moves
// the socket to the shared `nlc-daemon` runtime root, which would make the "socket lives under
// .nlc" rows vacuous. So this helper keeps the short `/tmp` prefix the C# used.

func NewTempDirectory(): string {
    directory := Path.Combine("/tmp", "nlc-" + Guid.NewGuid().ToString("N").Substring(0, 12))
    Directory.CreateDirectory(directory)
    return directory
}

func DeleteTempDirectory(directory: string) {
    if Directory.Exists(directory) {
        Directory.Delete(directory, true)
    }
}

func CopyDirectory(sourceDirectory: string, destinationDirectory: string) {
    Directory.CreateDirectory(destinationDirectory)
    for sourceFile in Directory.GetFiles(sourceDirectory) {
        File.Copy(sourceFile, Path.Combine(destinationDirectory, Path.GetFileName(sourceFile)), true)
    }

    for sourceSubdirectory in Directory.GetDirectories(sourceDirectory) {
        CopyDirectory(sourceSubdirectory, Path.Combine(destinationDirectory, Path.GetFileName(sourceSubdirectory)))
    }
}

// A copy of the `issue-tracker` fixture, which is the project the deleted C# analysed whenever a row
// needed a daemon with real symbols in it.
func NewTempProject(): string {
    directory := NewTempDirectory()
    fixture := Path.Combine(Path.Combine(Path.Combine(RepositoryRoot(), "tests"), "fixtures"), "issue-tracker")
    CopyDirectory(fixture, directory)
    return directory
}

// ─── WAITING ──────────────────────────────────────────────────────────────────────────────────

func WaitUntil(probe: Func<bool>, timeoutMilliseconds: long): bool {
    stopwatch := Stopwatch.StartNew()
    while stopwatch.ElapsedMilliseconds < timeoutMilliseconds {
        if probe() {
            return true
        }

        Thread.Sleep(25)
    }

    return probe()
}

// ─── AN IN-PROCESS DAEMON, ALWAYS STOPPED ─────────────────────────────────────────────────────
//
// The deleted C# ran `DaemonServer.Run()` on a background thread wrapped in an `IDisposable` whose
// `Dispose` sent the shutdown request. N# has no `using`-scoped disposal in this shape, so the same
// guarantee is spelled as an explicit `Stop()` inside every row's `finally`.

func StartDaemonThread(projectDirectory: string, idleTimeoutMilliseconds: double, idleCheckIntervalMilliseconds: double): Thread {
    server := new DaemonServer(projectDirectory, TimeSpan.FromMilliseconds(idleTimeoutMilliseconds), TimeSpan.FromMilliseconds(idleCheckIntervalMilliseconds))
    entryPoint: ThreadStart = () => server.Run()
    worker := new Thread(entryPoint)
    worker.IsBackground = true
    worker.Name = "nlc-daemon-test-server"
    worker.Start()
    return worker
}

class DaemonTestServer {
    ProjectDirectory: string
    worker: Thread
    stopped: bool

    constructor(projectDirectory: string, idleTimeoutMilliseconds: double, idleCheckIntervalMilliseconds: double) {
        ProjectDirectory = projectDirectory
        stopped = false
        worker = StartDaemonThread(projectDirectory, idleTimeoutMilliseconds, idleCheckIntervalMilliseconds)
    }

    func Stop() {
        if stopped {
            return
        }

        stopped = true
        DaemonClient.StopDaemon(ProjectDirectory)
        worker.Join(5000)
    }
}

// `TimeSpan.FromMinutes(DaemonConstants.IdleTimeoutMinutes)` — the C# spelling — cannot be used
// here: an `int` argument selects the `(long, long = 0)` overload, whose omitted default declines at
// emit. The product constant still drives the value; only the arithmetic moved.
func DefaultIdleTimeoutMilliseconds(): double {
    return DaemonConstants.IdleTimeoutMinutes * 60000.0
}

func StartDaemonServerWithIdleTimeout(projectDirectory: string, idleTimeoutMilliseconds: double, idleCheckIntervalMilliseconds: double): DaemonTestServer {
    server := new DaemonTestServer(projectDirectory, idleTimeoutMilliseconds, idleCheckIntervalMilliseconds)
    if !WaitUntil(() => DaemonClient.IsRunning(projectDirectory), 10000) {
        server.Stop()
        throw new InvalidOperationException("Daemon test server did not become responsive.")
    }

    return server
}

func StartDaemonServer(projectDirectory: string): DaemonTestServer {
    return StartDaemonServerWithIdleTimeout(projectDirectory, DefaultIdleTimeoutMilliseconds(), 60000.0)
}

// ─── TALKING TO A LIVE DAEMON ─────────────────────────────────────────────────────────────────

// The raw wire, for the one row that must send something `DaemonClient` would never send: bytes
// that are not JSON at all.
func SendRawDaemonRequest(projectDirectory: string, requestJson: string): string {
    socketPath := DaemonConstants.GetSocketPath(projectDirectory)
    socket := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)
    try {
        socket.ReceiveTimeout = DaemonConstants.ConnectionTimeoutMs
        socket.SendTimeout = DaemonConstants.ConnectionTimeoutMs
        socket.Connect(new UnixDomainSocketEndPoint(socketPath))
        requestBytes := Encoding.UTF8.GetBytes(requestJson)
        socket.Send(requestBytes, 0, requestBytes.Length, SocketFlags.None)
        socket.Shutdown(SocketShutdown.Send)

        responseStream := new MemoryStream()
        buffer := new byte[8192]
        received := socket.Receive(buffer, 0, buffer.Length, SocketFlags.None)
        while received > 0 {
            responseStream.Write(buffer, 0, received)
            received = socket.Receive(buffer, 0, buffer.Length, SocketFlags.None)
        }

        return Encoding.UTF8.GetString(responseStream.ToArray())
    } finally {
        socket.Dispose()
    }
}

func DaemonStatusDocument(projectDirectory: string): JsonDocument {
    statusJson := DaemonClient.GetStatus(projectDirectory)
    if statusJson == null {
        throw new InvalidOperationException("The daemon did not answer daemon/status.")
    }

    return JsonDocument.Parse(statusJson)
}

func StatusNumber(projectDirectory: string, fieldName: string): int {
    document := DaemonStatusDocument(projectDirectory)
    try {
        return document.RootElement.GetProperty(fieldName).GetInt32()
    } finally {
        document.Dispose()
    }
}

func StatusText(projectDirectory: string, fieldName: string): string {
    document := DaemonStatusDocument(projectDirectory)
    try {
        return TextOf(document.RootElement.GetProperty(fieldName))
    } finally {
        document.Dispose()
    }
}

func CachedFileCount(projectDirectory: string): int {
    return StatusNumber(projectDirectory, DaemonProtocolKernels.GetStatusCachedFilesField())
}

// The value slot is `object`, not `object?`, because an N#-EMITTED signature carries no nullability
// in metadata (see census-briefs/CLI2-COMPILER-BLOCKERS.md): `DaemonClient.Query` now lives in an N#
// assembly, so its parameter reads back as `Dictionary<string!, object!>!`. The dictionaries sent
// are byte-for-byte the same — every value written here is a non-null string.
func QueryParameters(firstName: string, firstValue: string): Dictionary<string, object> {
    parameters := new Dictionary<string, object>()
    parameters[firstName] = firstValue
    return parameters
}

func FilePositionParameters(relativePath: string, position: string): Dictionary<string, object> {
    parameters := new Dictionary<string, object>()
    parameters["file"] = relativePath
    parameters["pos"] = position
    return parameters
}

// ─── READING JSON ─────────────────────────────────────────────────────────────────────────────

func TextOf(element: JsonElement): string {
    return element.GetString() ?? ""
}

// `TryGetProperty` needs an `out JsonElement`, and a `JsonElement` has no spellable zero here, so
// presence is decided by walking the object's members instead. The claim is the same one the
// deleted C# made with `TryGetProperty`.
func HasProperty(element: JsonElement, propertyName: string): bool {
    enumerator := element.EnumerateObject()
    while enumerator.MoveNext() {
        if enumerator.Current.Name == propertyName {
            return true
        }
    }

    return false
}

func Utf8ByteCount(value: string): int {
    return Encoding.UTF8.GetByteCount(value)
}

func Repeated(character: char, count: int): string {
    builder := new StringBuilder()
    index := 0
    while index < count {
        builder.Append(character)
        index = index + 1
    }

    return builder.ToString()
}

func ElementCount(array: JsonElement): int {
    enumerator := array.EnumerateArray()
    count := 0
    while enumerator.MoveNext() {
        count = count + 1
    }

    return count
}

func EveryElementHasStringProperty(array: JsonElement, propertyName: string, expected: string): bool {
    enumerator := array.EnumerateArray()
    while enumerator.MoveNext() {
        if TextOf(enumerator.Current.GetProperty(propertyName)) != expected {
            return false
        }
    }

    return true
}

// The `error.details.position` object the daemon reports for an unparseable `--pos` argument.
func PositionComponent(responseJson: string, component: string): int {
    document := JsonDocument.Parse(responseJson)
    try {
        position := document.RootElement.GetProperty("error").GetProperty("details").GetProperty("position")
        return position.GetProperty(component).GetInt32()
    } finally {
        document.Dispose()
    }
}

// `daemon status` reports uptime as `<h>h <m>m <s>s`. The rows that check it need the number of
// seconds back, and re-deriving it here — rather than asking the kernel that formatted it — is what
// keeps the assertion from agreeing with its subject by construction.
func UptimeTextToSeconds(uptime: string): long {
    parts := uptime.Split(' ')
    if parts.Length != 3 {
        throw new InvalidOperationException("Unexpected uptime spelling: " + uptime)
    }

    hours := long.Parse(parts[0].TrimEnd('h'))
    minutes := long.Parse(parts[1].TrimEnd('m'))
    seconds := long.Parse(parts[2].TrimEnd('s'))
    return hours * 3600 + minutes * 60 + seconds
}

namespace NSharpLang.DaemonExec.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text.Json
import System.Threading

// ─── THE DAEMON-FIRST CLI, OBSERVED FROM OUTSIDE ──────────────────────────────────────────────
//
// Every row here runs the REAL built CLI as child processes against a REAL workspace server, the way
// an agent or a terminal does, and reads only what a user could read: exit codes, stdout, stderr, the
// server's status and the files in `.nlc/`. Nothing here calls a daemon type in-process, because what
// is under test is precisely the boundary between two processes.
//
// TEST HYGIENE. Every workspace is a fresh `/tmp/nlc-<12 hex>` directory (short, so the socket stays
// inside the workspace's own `.nlc`), every server started here is stopped in a `finally`, and the
// workspace is deleted after it — which on its own retires a server within the liveness window. Every
// server is also started with a one-minute idle timeout, so even a killed test run cannot leave one
// behind for longer than that.
//
// THE ENVIRONMENT. These rows run inside `nlc test`, which sets `NLC_DAEMON_CHILD` for its tests so a
// test's `nlc` never starts a server. These rows WANT a server, so every child here has that marker
// (and `NLC_NO_DAEMON`, `CI`, `NLC_DAEMON`) removed, and whatever a row asks for set explicitly.
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

// The child's start info: `dotnet Cli.dll <args>` in `workingDirectory`, with the routing switches
// cleared and `environment` applied (a null value removes the variable).
func NlcStartInfo(args: string[], workingDirectory: string, environment: Dictionary<string, string?>): ProcessStartInfo {
    startInfo := new ProcessStartInfo()
    startInfo.FileName = "dotnet"
    startInfo.ArgumentList.Add(CliDll())
    for argument in args {
        startInfo.ArgumentList.Add(argument)
    }

    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardInput = true
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false
    startInfo.Environment.Remove("NLC_DAEMON_CHILD")
    startInfo.Environment.Remove("NLC_NO_DAEMON")
    startInfo.Environment.Remove("NLC_DAEMON")
    startInfo.Environment.Remove("CI")
    startInfo.Environment.Remove("NLC_DAEMON_TRACE")
    startInfo.Environment["NLC_DAEMON_IDLE_TIMEOUT"] = "60s"
    for entry in environment {
        if entry.Value == null {
            startInfo.Environment.Remove(entry.Key)
        } else {
            startInfo.Environment[entry.Key] = entry.Value ?? ""
        }
    }

    return startInfo
}

func Finish(process: Process, stdin: string?, timeoutMilliseconds: int): ProcessRun {
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if stdin != null {
        process.StandardInput.Write(stdin ?? "")
    }

    process.StandardInput.Close()
    if !process.WaitForExit(timeoutMilliseconds) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("nlc did not finish within " + timeoutMilliseconds.ToString() + " ms.")
    }

    process.WaitForExit()
    run := new ProcessRun(process.ExitCode, stdoutTask.Result, stderrTask.Result)
    process.Dispose()
    return run
}

func NlcWith(args: string[], workingDirectory: string, environment: Dictionary<string, string?>, stdin: string?): ProcessRun {
    process := new Process { StartInfo: NlcStartInfo(args, workingDirectory, environment) }
    process.Start()
    return Finish(process, stdin, 180000)
}

func NoEnvironment(): Dictionary<string, string?> {
    return new Dictionary<string, string?>()
}

func Traced(): Dictionary<string, string?> {
    environment := new Dictionary<string, string?>()
    environment["NLC_DAEMON_TRACE"] = "1"
    return environment
}

func InProcess(): Dictionary<string, string?> {
    environment := new Dictionary<string, string?>()
    environment["NLC_NO_DAEMON"] = "1"
    return environment
}

// `nlc <args>` routed (a server is used when one is running).
func Nlc(args: string[], workingDirectory: string): ProcessRun {
    return NlcWith(args, workingDirectory, NoEnvironment(), null)
}

// ─── WORKSPACES ───────────────────────────────────────────────────────────────────────────────

func NewWorkspace(): string {
    directory := Path.Combine("/tmp", "nlc-" + Guid.NewGuid().ToString("N").Substring(0, 12))
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "project.yml"), "name: DaemonExecProbe\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\n")
    return directory
}

func WriteSource(workspace: string, fileName: string, source: string) {
    File.WriteAllText(Path.Combine(workspace, fileName), source)
}

func SocketPath(workspace: string): string {
    return Path.Combine(Path.Combine(workspace, ".nlc"), "daemon.sock")
}

func PidPath(workspace: string): string {
    return Path.Combine(Path.Combine(workspace, ".nlc"), "daemon.pid")
}

func ServerPid(workspace: string): int {
    pid := 0
    if File.Exists(PidPath(workspace)) {
        Int32.TryParse(File.ReadAllText(PidPath(workspace)).Trim(), out pid)
    }

    return pid
}

func IsProcessAlive(pid: int): bool {
    if pid <= 0 {
        return false
    }

    try {
        process := Process.GetProcessById(pid)
        alive := !process.HasExited
        process.Dispose()
        return alive
    } catch missing: Exception {
        return false
    }
}

func WaitUntil(probe: Func<bool>, timeoutMilliseconds: long): bool {
    stopwatch := Stopwatch.StartNew()
    while stopwatch.ElapsedMilliseconds < timeoutMilliseconds {
        if probe() {
            return true
        }

        Thread.Sleep(50)
    }

    return probe()
}

// `nlc daemon status` as a JSON document, or null when no server answers.
func Status(workspace: string): JsonDocument? {
    run := Nlc(["daemon", "status", "--project", workspace], workspace)
    text := run.Stdout.Trim()
    if !text.StartsWith("{") {
        return null
    }

    return JsonDocument.Parse(text)
}

func StatusString(workspace: string, field: string): string {
    document := Status(workspace)
    if document == null {
        return ""
    }

    parsed := document ?? JsonDocument.Parse("{}")
    try {
        return parsed.RootElement.GetProperty(field).ToString()
    } finally {
        parsed.Dispose()
    }
}

// The routed command that starts a server, then the wait for that server to be up and warm (its
// warm-up holds the work lock, so a status that answers is not yet a server that will take work;
// the log line is).
func StartServer(workspace: string): int {
    Nlc(["check"], workspace)
    logPath := Path.Combine(Path.Combine(workspace, ".nlc"), "daemon.log")
    ready := WaitUntil(() => File.Exists(SocketPath(workspace)) && File.Exists(logPath) && File.ReadAllText(logPath).Contains("Warm-up"), 90000)
    if !ready {
        throw new InvalidOperationException("The workspace server did not start within 90 s.")
    }

    return ServerPid(workspace)
}

func StopServer(workspace: string) {
    pid := ServerPid(workspace)
    if Directory.Exists(workspace) {
        Nlc(["daemon", "stop", "--project", workspace], workspace)
    }

    WaitUntil(() => !IsProcessAlive(pid), 15000)
}

func DeleteWorkspace(workspace: string) {
    StopServer(workspace)
    if Directory.Exists(workspace) {
        Directory.Delete(workspace, true)
    }
}

// ─── COMPARING OUTPUT ─────────────────────────────────────────────────────────────────────────
//
// Two runs of the same command differ only in wall-clock numbers. Everything else must match byte for
// byte, so only durations are normalised: `[1.7s]`, `in 0.4s`, `"duration": "0.003s"`.
func Normalized(text: string): string {
    result := System.Text.RegularExpressions.Regex.Replace(text, "[0-9]+(\\.[0-9]+)?(ms|s)\\b", "<t>")
    return System.Text.RegularExpressions.Regex.Replace(result, "[0-9]+m [0-9]+s\\b", "<t>")
}

func WithoutTrace(text: string): string {
    lines := text.Split('\n')
    kept := new List<string>()
    for line in lines {
        if !line.StartsWith("[nlc-daemon]") {
            kept.Add(line)
        }
    }

    return String.Join("\n", kept)
}

func CountOccurrences(text: string, fragment: string): int {
    count := 0
    index := text.IndexOf(fragment, StringComparison.Ordinal)
    while index >= 0 {
        count = count + 1
        index = text.IndexOf(fragment, index + fragment.Length, StringComparison.Ordinal)
    }

    return count
}

// One command, in-process and through the server, compared on all three channels. Returns the routed
// run's trace so a row can also assert WHICH way the routed run went.
func AssertParity(workspace: string, args: string[], stdin: string?): string {
    inProcess := NlcWith(args, workspace, InProcess(), stdin)
    routed := NlcWith(args, workspace, Traced(), stdin)
    label := String.Join(" ", args)
    if inProcess.ExitCode != routed.ExitCode {
        throw new InvalidOperationException("Exit codes differ for '" + label + "': in-process " + inProcess.ExitCode.ToString() + ", routed " + routed.ExitCode.ToString() + ". Routed stderr: " + routed.Stderr)
    }

    if Normalized(inProcess.Stdout) != Normalized(routed.Stdout) {
        throw new InvalidOperationException("Stdout differs for '" + label + "'.\n--- in-process ---\n" + inProcess.Stdout + "\n--- routed ---\n" + routed.Stdout)
    }

    if Normalized(inProcess.Stderr) != Normalized(WithoutTrace(routed.Stderr)) {
        throw new InvalidOperationException("Stderr differs for '" + label + "'.\n--- in-process ---\n" + inProcess.Stderr + "\n--- routed ---\n" + routed.Stderr)
    }

    return routed.Stderr
}

func RoutedThroughServer(trace: string): bool {
    return trace.Contains("[nlc-daemon] route=daemon")
}

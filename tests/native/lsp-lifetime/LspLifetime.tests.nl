namespace NSharpLang.LspLifetime.Tests

import System
import System.Diagnostics
import System.IO


// THE STDIO LANGUAGE SERVER MUST NOT OUTLIVE ITS CLIENT, PROVEN AS PROCESSES.
//
// The fourth visual-verification round (artifacts/ide-verification/2026-09-02c) found orphaned
// `LanguageServer.dll --stdio` processes with parent pid 1 on the verification machine, surviving
// the VS Code windows that started them by weeks. A headless probe speaking real LSP framing then
// measured the two ways a client can vanish and found BOTH unhandled: stdin closed (before or
// after `initialize`) left the server alive past 20 seconds, and killing the process whose pid the
// client declared in `initialize` left it alive past 25 seconds. Only an orderly `exit` after the
// handshake ended it, in 0.03 s.
//
// `src/NSharpLang.LanguageServer/Program.cs` answers both, event-driven and without a poll loop:
// stdin is pumped into a `System.IO.Pipelines.Pipe` whose copy completing at EOF exits the process,
// and `OnInitialize` watches the declared pid with `WaitForExitAsync`. These blocks are what keeps
// that true. Each measures a REAL server process, because that is the only thing an orphan is.
//
// WHY THE POLICY IS NOT N#-OWNED. The lifetime logic itself cannot move out of C#: N# declines
// `Process.GetCurrentProcess()`, `Process.GetProcessById()` and `ProcessStartInfo.RedirectStandardInput`
// at columnar emit, and those three ARE the parent watch and the stdin door. The contract is
// N#-owned; the six lines it guards are not, and this comment is the reason.
//
// UNIX ONLY, DELIBERATELY. Every block drives `/bin/sh` and two use `mkfifo`, because a fifo is the
// only way to hold a child's stdin open while writing framed messages into it WITHOUT
// `RedirectStandardInput`, which declines. On Windows the blocks do not run; the gate and CI are
// macOS and ubuntu-latest, so nothing here is silently unmeasured on the platforms that ship it.

// ─── THE SHELL KERNEL ─────────────────────────────────────────────────────────────────────────
class ShellRun {
    ExitCode: int
    TimedOut: bool

    constructor(exitCode: int, timedOut: bool) {
        ExitCode = exitCode
        TimedOut = timedOut
    }
}

// Run a script under `/bin/sh` with a hard bound. The script redirects its own streams, so nothing
// a server prints can reach this harness's stdout — the gate parses that stdout as JSON. A script
// that overruns is killed with its whole tree, so a FAILING block cannot leave the very orphan it
// is here to forbid.
func RunShellScript(script: string, timeoutMilliseconds: int): ShellRun {
    scriptPath := Path.Combine(Path.GetTempPath(), "nsharp-lsp-lifetime-" + Guid.NewGuid().ToString("N") + ".sh")
    File.WriteAllText(scriptPath, script)

    startInfo := new ProcessStartInfo { FileName: "/bin/sh", Arguments: "\"" + scriptPath + "\"" }
    startInfo.WorkingDirectory = Path.GetTempPath()
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()

    timedOut := false
    if !process.WaitForExit(timeoutMilliseconds) {
        timedOut = true
        process.Kill(true)
        process.WaitForExit()
    }

    exitCode := process.ExitCode
    process.Dispose()
    File.Delete(scriptPath)
    return new ShellRun(exitCode, timedOut)
}

// ─── FINDING THE BUILT SERVER ─────────────────────────────────────────────────────────────────

func LspRepositoryRoot(): string {
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

// The gate's native step runs after the unit step, whose `tests/Tests.csproj` project-references
// `LanguageServer.csproj` — so this dll is on disk by the time these blocks run.
func LanguageServerDll(): string {
    root := LspRepositoryRoot()
    serverDirectory := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.LanguageServer"), "bin")
    serverDll := Path.Combine(Path.Combine(Path.Combine(serverDirectory, "Debug"), "net10.0"), "LanguageServer.dll")
    if !File.Exists(serverDll) {
        throw new InvalidOperationException("The built N# language server was not found: " + serverDll)
    }

    return serverDll
}

func IsUnix(): bool {
    return OperatingSystem.IsMacOS() || OperatingSystem.IsLinux()
}

// ─── THE FIFO HANDSHAKE ───────────────────────────────────────────────────────────────────────
//
// `exec 3> "$d/in"` opens the fifo for writing and HOLDS IT OPEN for the rest of the script, so
// the server's stdin never reaches EOF: whatever ends the server in these two blocks, it is not
// the pump. The handshake is written in full because OmniSharp QUEUES notifications until
// `initialize` completes — a bare `exit` sent before the handshake is never acted on, measured at
// 20 s twice. That is the one correction to the recorded design this contract carries, and it has
// a second edge: an `exit` written in the SAME burst as the handshake is dropped too (measured,
// 25 s). So the script WAITS FOR THE INITIALIZE RESPONSE to appear on the server's stdout before
// sending anything else — a readiness fact, not a sleep long enough to usually work.
func LspFifoScript(prologue: string, processIdSpelling: string, afterHandshake: string): string {
    template := """
exec > /dev/null 2>&1
@PROLOGUE@
d=$(mktemp -d) || exit 90
mkfifo "$d/in" || exit 91
dotnet "@DLL@" --stdio < "$d/in" > "$d/out" 2>/dev/null &
server=$!
exec 3> "$d/in"
send() { m=$1; printf 'Content-Length: %d\r\n\r\n%s' "${#m}" "$m" >&3; }
send "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":@PID@,\"rootUri\":null,\"capabilities\":{},\"clientInfo\":{\"name\":\"lsp-lifetime\",\"version\":\"1\"}}}"
waited=0
while [ ! -s "$d/out" ] && [ "$waited" -lt 30 ]; do sleep 1; waited=$((waited + 1)); done
[ -s "$d/out" ] || exit 92
send '{"jsonrpc":"2.0","method":"initialized","params":{}}'
sleep 1
@TAIL@
rc=0
wait "$server" || rc=$?
exec 3>&-
rm -rf "$d"
exit "$rc"
"""
    return template.Replace("@PROLOGUE@", prologue).Replace("@DLL@", LanguageServerDll()).Replace("@PID@", processIdSpelling).Replace("@TAIL@", afterHandshake)
}

// ─── THE THREE LIFETIME DOORS ─────────────────────────────────────────────────────────────────

// `exec` is load-bearing: it replaces the shell with the server, so the pid this harness waits on
// IS the server's. Unfixed, this shape survived 12 s of a 15 s bound and then had to be killed.
test "lsp lifetime: stdin at EOF ends the server" {
    if IsUnix() {
        script := "exec dotnet \"" + LanguageServerDll() + "\" --stdio < /dev/null > /dev/null 2>&1"
        run := RunShellScript(script, 15000)
        assert !run.TimedOut, "the server outlived a closed stdin"
        assert run.ExitCode == 0, "the server left with " + run.ExitCode.ToString()
    }
}

// The complement: the pipe is STILL OPEN when the server leaves, so this block proves the orderly
// `exit` path is untouched by the pump rather than replaced by it.
test "lsp lifetime: an exit notification ends the server while its stdin pipe is still open" {
    if IsUnix() {
        script := LspFifoScript("", "null", "send '{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":null}'")
        run := RunShellScript(script, 60000)
        assert !run.TimedOut, "the server ignored an exit notification"
        assert run.ExitCode == 0, "the server left with " + run.ExitCode.ToString()
    }
}

// The client's own death, with stdin deliberately healthy: only the declared-pid watch can answer
// this one. The kill lands after the readiness wait, because the watch is registered in
// `OnInitialize` and a kill that beat it would measure nothing.
test "lsp lifetime: the death of the declared client process ends the server" {
    if IsUnix() {
        script := LspFifoScript("sleep 600 &\nvictim=$!", "$victim", "kill \"$victim\" 2>/dev/null")
        run := RunShellScript(script, 60000)
        assert !run.TimedOut, "the server outlived the process id its client declared"
        assert run.ExitCode == 0, "the server left with " + run.ExitCode.ToString()
    }
}

namespace NSharpLang.Cli.Daemon

import System
import System.IO
import System.Text

// EVERY DECISION THE DAEMON-FIRST CLI MAKES, AS A PURE FUNCTION.
//
// `nlc check`, `build`, `test`, `run`, `format`, `lint` and `fix` are executed by a warm per-workspace
// server when one is available (`DaemonExecClient` on the client side, `DaemonExecHost` in the server).
// Which commands route, which switches turn routing off, which directory is "the workspace", what
// counts as the same compiler build, how the server is launched and every number the wire waits on
// are decided here, so the estate can cross every one of them without a socket or a process.
class DaemonExecKernels {

    // ── The wire ────────────────────────────────────────────────────────────────────────────────
    //
    // An exec connection opens with these four bytes. The JSON-RPC query wire opens with `{`, so the
    // server tells the two apart from the first byte without a second socket.
    static func GetExecMagic(): byte[] {
        magic := new byte[](4)
        magic[0] = (byte)78
        magic[1] = (byte)76
        magic[2] = (byte)88
        magic[3] = (byte)49
        return magic
    }

    // Bumped whenever a frame's meaning changes. It is part of the build identity as well, so a
    // client never reads frames from a server that writes another version.
    static func GetExecProtocolVersion(): int {
        return 1
    }

    // Client → server frames.
    static func FrameRequest(): byte {
        return (byte)82
    }

    static func FrameStdinData(): byte {
        return (byte)73
    }

    static func FrameStdinEnd(): byte {
        return (byte)90
    }

    static func FrameCancel(): byte {
        return (byte)88
    }

    static func FrameChildExit(): byte {
        return (byte)67
    }

    // Server → client frames.
    static func FrameAccepted(): byte {
        return (byte)65
    }

    static func FrameStdout(): byte {
        return (byte)79
    }

    static func FrameStderr(): byte {
        return (byte)87
    }

    static func FrameStdinWanted(): byte {
        return (byte)81
    }

    static func FrameLaunch(): byte {
        return (byte)80
    }

    static func FrameKeepAlive(): byte {
        return (byte)75
    }

    static func FrameDone(): byte {
        return (byte)68
    }

    static func FrameBusy(): byte {
        return (byte)66
    }

    static func FrameMismatch(): byte {
        return (byte)77
    }

    // A frame larger than this is a corrupt stream, not a large write: writers split their output
    // into chunks far below it.
    static func GetMaxFramePayloadBytes(): int {
        return 16 * 1024 * 1024
    }

    // ── Timing ──────────────────────────────────────────────────────────────────────────────────

    // How long a request waits for the server's work lock before the server answers "busy" and the
    // client runs the command itself. Commands that touch the process-wide current directory,
    // environment and console cannot run side by side in one process, so a second agent never waits
    // longer than this behind a first agent's long build: long enough to queue behind a quick
    // `check` or `format`, short enough that losing the race costs little next to a cold run.
    static func GetBusyWaitMilliseconds(): int {
        return 250
    }

    // The server sends a keep-alive this often while a command runs; a client that hears nothing for
    // the hang window treats the server as frozen.
    static func GetKeepAliveIntervalMilliseconds(): int {
        return 1000
    }

    static func GetHangTimeoutMilliseconds(): int {
        return 15000
    }

    // After a client cancels, the command still running in the server has this long to finish before
    // the server retires itself rather than keep serving with a runaway command inside it.
    static func GetCancelGraceMilliseconds(): int {
        return 10000
    }

    // A client that spawned a server does not spawn another for this long, so a server that cannot
    // start does not cost a process per command.
    static func GetSpawnBackoffMilliseconds(): long {
        return 10000
    }

    // The client holds output back until it is this old or this large, so a server that dies early
    // in a command leaves nothing on the terminal and the in-process rerun prints the only copy.
    static func GetOutputCommitMilliseconds(): long {
        return 1500
    }

    static func GetOutputCommitBytes(): int {
        return 65536
    }

    // How often the server checks that its socket still exists. A workspace deleted under a running
    // server (a test's temporary project) retires the server within this window rather than leaving
    // it idle for the full timeout.
    static func GetLivenessCheckMilliseconds(): int {
        return 2000
    }

    // ── Switches ────────────────────────────────────────────────────────────────────────────────

    static func GetNoDaemonFlag(): string {
        return "--no-daemon"
    }

    static func GetNoDaemonEnvironmentVariable(): string {
        return "NLC_NO_DAEMON"
    }

    // Set for every command the server executes and for every process those commands start (test
    // runs included). An `nlc` started underneath one runs in-process: it must never queue behind the
    // very request that started it.
    static func GetDaemonChildEnvironmentVariable(): string {
        return "NLC_DAEMON_CHILD"
    }

    static func GetCiEnvironmentVariable(): string {
        return "CI"
    }

    static func GetDaemonOptInEnvironmentVariable(): string {
        return "NLC_DAEMON"
    }

    static func GetIdleTimeoutEnvironmentVariable(): string {
        return "NLC_DAEMON_IDLE_TIMEOUT"
    }

    static func GetMaxMemoryEnvironmentVariable(): string {
        return "NLC_DAEMON_MAX_MEMORY_MB"
    }

    static func GetWarmupEnvironmentVariable(): string {
        return "NLC_DAEMON_WARMUP"
    }

    static func GetDefaultMaxMemoryMegabytes(): long {
        return 4096
    }

    // The commands whose whole cost is the compiler and its metadata, and whose output is a pure
    // function of the request: these are the ones a warm process pays off for.
    static func IsRoutedCommandName(command: string): bool {
        return NameIs(command, "check") || NameIs(command, "build") || NameIs(command, "test") || NameIs(command, "run") || NameIs(command, "format") || NameIs(command, "lint") || NameIs(command, "fix")
    }

    // `NLC_NO_DAEMON=1` (any value but empty or `0`) and `NLC_DAEMON_CHILD` turn routing off. On CI
    // (`CI=true` or `CI=1`) routing is off unless `NLC_DAEMON=1` asks for it: a one-shot build gains
    // nothing from a server and should not leave one behind.
    static func IsDisabledByEnvironment(noDaemon: string?, daemonChild: string?, ci: string?, daemonOptIn: string?): bool {
        if IsSet(noDaemon) && noDaemon != "0" {
            return true
        }

        if IsSet(daemonChild) {
            return true
        }

        if IsTruthy(ci) && !IsTruthy(daemonOptIn) {
            return true
        }

        return false
    }

    // `--no-daemon` anywhere before a `--` separator.
    static func HasNoDaemonFlag(args: string[]): bool {
        index := 0
        while index < args.Length {
            argument := args[index]
            if argument == "--" {
                return false
            }

            if argument == GetNoDaemonFlag() {
                return true
            }

            index = index + 1
        }

        return false
    }

    // The argument vector the command itself sees: `--no-daemon` belongs to the router, and a command
    // that does not know the flag must not refuse it.
    static func StripNoDaemonFlag(args: string[]): string[] {
        count := 0
        index := 0
        separatorSeen := false
        while index < args.Length {
            if args[index] == "--" {
                separatorSeen = true
            }

            if separatorSeen || args[index] != GetNoDaemonFlag() {
                count = count + 1
            }

            index = index + 1
        }

        result := new string[](count)
        index = 0
        written := 0
        separatorSeen = false
        while index < args.Length {
            if args[index] == "--" {
                separatorSeen = true
            }

            if separatorSeen || args[index] != GetNoDaemonFlag() {
                result[written] = args[index]
                written = written + 1
            }

            index = index + 1
        }

        return result
    }

    static func ShouldRoute(args: string[], noDaemon: string?, daemonChild: string?, ci: string?, daemonOptIn: string?): bool {
        if args.Length == 0 {
            return false
        }

        if !IsRoutedCommandName(args[0]) {
            return false
        }

        if HasNoDaemonFlag(args) {
            return false
        }

        return !IsDisabledByEnvironment(noDaemon, daemonChild, ci, daemonOptIn)
    }

    // ── The workspace ───────────────────────────────────────────────────────────────────────────
    //
    // One server serves a whole workspace: the nearest ancestor holding `.git` (a directory, or the
    // file a worktree carries), else the nearest ancestor holding `project.yml`. A repository with a
    // hundred projects therefore runs ONE warm server, not a hundred. With neither marker the answer
    // is null when `requireMarker` is set (the router then runs in-process rather than plant a
    // `.nlc` directory in an arbitrary folder) and the start directory otherwise (an explicit
    // `nlc daemon start`).
    static func ResolveWorkspaceRoot(startDirectory: string, hasGitMarker: Func<string, bool>, hasProjectFile: Func<string, bool>, requireMarker: bool): string? {
        nearestProject: string? = null
        directory: string? = startDirectory
        while directory != null {
            current := directory ?? ""
            if hasGitMarker(current) {
                return current
            }

            if nearestProject == null && hasProjectFile(current) {
                nearestProject = current
            }

            directory = Path.GetDirectoryName(current)
        }

        if nearestProject != null {
            return nearestProject
        }

        if requireMarker {
            return null
        }

        return startDirectory
    }

    // ── Build identity ──────────────────────────────────────────────────────────────────────────
    //
    // Two `nlc` processes share a server only when they are the same build of the same toolchain
    // under the same runtime knobs. The identity covers: the informational version (which carries
    // the commit), the exec protocol version, the directory the CLI was loaded from, the size and
    // write time of every assembly beside it (a rebuilt compiler is a different compiler even at the
    // same version string), the runtime version, and every `DOTNET_`/`COMPlus_` variable — those
    // configure the runtime at process start, so a server started under different values cannot honour
    // a request that asks for them.
    static func IsRuntimeConfigurationVariable(name: string): bool {
        return name.StartsWith("DOTNET_", StringComparison.Ordinal) || name.StartsWith("COMPlus_", StringComparison.Ordinal)
    }

    static func ComposeIdentitySource(version: string, baseDirectory: string, runtimeVersion: string, assemblyFacts: string[], runtimeVariables: string[]): string {
        builder := new StringBuilder()
        builder.Append("nlc-exec-protocol=")
        builder.Append(GetExecProtocolVersion())
        builder.Append('\n')
        builder.Append("version=")
        builder.Append(version)
        builder.Append('\n')
        builder.Append("base=")
        builder.Append(baseDirectory)
        builder.Append('\n')
        builder.Append("runtime=")
        builder.Append(runtimeVersion)
        builder.Append('\n')
        for fact in assemblyFacts {
            builder.Append("asm=")
            builder.Append(fact)
            builder.Append('\n')
        }

        for variable in runtimeVariables {
            builder.Append("env=")
            builder.Append(variable)
            builder.Append('\n')
        }

        return builder.ToString()
    }

    // FNV-1a over UTF-16 code units, folded to 64 bits and printed as 16 lowercase hex digits. It is
    // not a security boundary — the socket's permissions are — it only has to tell builds apart, and
    // it costs the client no cryptography start-up on the path every command takes.
    static func HashIdentity(text: string): string {
        hash: ulong = 14695981039346656037UL
        prime: ulong = 1099511628211UL
        index := 0
        while index < text.Length {
            code := (ulong)text[index]
            hash = hash ^ (code & 255UL)
            hash = hash * prime
            hash = hash ^ (code >> 8)
            hash = hash * prime
            index = index + 1
        }

        return hash.ToString("x16")
    }

    // ── Launching the server ────────────────────────────────────────────────────────────────────
    //
    // The server must be THIS binary. Under the `dotnet` muxer the process path is the muxer and the
    // entry assembly names the CLI; under an apphost or a native image the process path is the CLI
    // itself. (The old `dotnet run --project src/NSharpLang.Cli` plan rebuilt and ran whatever the
    // checkout held, which is exactly the stale-server hazard the identity exists to rule out.)
    static func IsDotnetHost(processPath: string): bool {
        fileName := Path.GetFileNameWithoutExtension(processPath)
        return String.Compare(fileName, "dotnet", StringComparison.OrdinalIgnoreCase) == 0
    }

    // Element 0 is the file to start; the rest are its arguments, one per element.
    static func GetServerLaunchCommand(processPath: string, entryAssemblyPath: string?, workspaceRoot: string, background: bool): string[] {
        prefix := GetSelfLaunchPrefix(processPath, entryAssemblyPath)
        extra := 4
        if background {
            extra = 5
        }

        command := new string[](prefix.Length + extra)
        index := 0
        while index < prefix.Length {
            command[index] = prefix[index]
            index = index + 1
        }

        command[index] = "daemon"
        command[index + 1] = "run"
        command[index + 2] = "--project"
        command[index + 3] = workspaceRoot
        if background {
            command[index + 4] = GetBackgroundFlag()
        }

        return command
    }

    // The file and leading arguments that start this same CLI again (the server, or a test worker).
    static func GetSelfLaunchPrefix(processPath: string, entryAssemblyPath: string?): string[] {
        if IsDotnetHost(processPath) && entryAssemblyPath != null && entryAssemblyPath != "" {
            prefix := new string[](2)
            prefix[0] = processPath
            prefix[1] = entryAssemblyPath ?? ""
            return prefix
        }

        single := new string[](1)
        single[0] = processPath
        return single
    }

    // `daemon run --background` writes everything to the log from its first line: nobody is reading
    // its standard streams once the client that spawned it has returned.
    static func GetBackgroundFlag(): string {
        return "--background"
    }

    static func GetSpawnMarkerFileName(): string {
        return "daemon.spawn"
    }

    static func GetLockFileName(): string {
        return "daemon.lock"
    }

    static func GetLogFileName(): string {
        return "daemon.log"
    }

    // ── Limits ──────────────────────────────────────────────────────────────────────────────────

    static func ParseMaxMemoryMegabytes(text: string?): long {
        if text == null {
            return GetDefaultMaxMemoryMegabytes()
        }

        parsed: long = 0
        if long.TryParse(text, out parsed) && parsed > 0 {
            return parsed
        }

        return GetDefaultMaxMemoryMegabytes()
    }

    // `NLC_DAEMON_IDLE_TIMEOUT` takes the same durations `nlc test --timeout` does (`90s`, `30m`, a
    // bare number of seconds); anything else keeps the default.
    static func ParseIdleTimeoutMilliseconds(text: string?, defaultMilliseconds: long): long {
        if text == null || text == "" {
            return defaultMilliseconds
        }

        parsed := TestCommandKernels.GetDurationMilliseconds(text ?? "")
        if parsed == null {
            return defaultMilliseconds
        }

        value: int = parsed
        if value <= 0 {
            return defaultMilliseconds
        }

        return (long)value
    }

    static func IsWarmupEnabled(text: string?): bool {
        return text != "0"
    }

    // ── Messages ────────────────────────────────────────────────────────────────────────────────

    // The ONE line a client prints when it gives up on a server mid-command. Stdout is untouched, so
    // a JSON consumer still reads exactly one document — the in-process run's.
    static func GetServerLostNote(): string {
        return "nlc: the workspace server stopped responding; running in-process instead (use --no-daemon or NLC_NO_DAEMON=1 to skip the server)."
    }

    static func GetServerCrashedLogMessage(reason: string): string {
        return "[daemon] Exec request ended abnormally: " + reason
    }

    static func GetRetiringAfterCancelMessage(graceMilliseconds: int): string {
        return "[daemon] A cancelled command was still running after " + graceMilliseconds.ToString() + " ms. Retiring this server."
    }

    static func GetMemoryCapMessage(workingSetMegabytes: long, capMegabytes: long): string {
        return "[daemon] Working set " + workingSetMegabytes.ToString() + " MB exceeds the " + capMegabytes.ToString() + " MB cap. Retiring this server."
    }

    static func GetSocketGoneMessage(): string {
        return "[daemon] Socket file removed (workspace deleted or replaced). Shutting down."
    }

    static func GetExecMessage(command: string, exitCode: int, elapsedMilliseconds: long): string {
        return "[daemon] exec " + command + " -> " + exitCode.ToString() + " (" + elapsedMilliseconds.ToString() + " ms)"
    }

    static func GetAnotherServerOwnsLockMessage(lockPath: string): string {
        return "[daemon] Another server holds " + lockPath + ". Exiting."
    }

    // ── Helpers ─────────────────────────────────────────────────────────────────────────────────

    static func NameIs(command: string, expected: string): bool {
        return String.Compare(command, expected, StringComparison.OrdinalIgnoreCase) == 0
    }

    static func IsSet(value: string?): bool {
        return value != null && value != ""
    }

    static func IsTruthy(value: string?): bool {
        if value == null {
            return false
        }

        return value == "1" || String.Compare(value, "true", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(value, "yes", StringComparison.OrdinalIgnoreCase) == 0
    }
}

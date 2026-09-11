namespace NSharpLang.NativeComparisonRunner

import System.Diagnostics


// THE SPAWN KERNEL. Every external tool this runner uses — the N# CLI, the emitted kernel program,
// `rustc`, `clang`, `git`, `sysctl`, `uname` — is reached through `RunProcess` and nothing else.
//
// The shape is copied from `tests/native/systems-proof-corpus/SystemsProofCorpus.tests.nl`: one
// `ProcessStartInfo`, one `Process`, `Start`, both pipes drained with `ReadToEnd`, `WaitForExit`,
// `ExitCode`, `Dispose`. Draining BEFORE waiting is what keeps a chatty child (a `--trials 15`
// kernel run emits twelve stdout lines and twelve stderr lines) from deadlocking against a full
// pipe buffer, and the `Dispose` is what guarantees this runner leaves no orphan behind.
//
// A process that cannot be STARTED at all (a missing `rustc`, a repository without `git`) is
// reported as a `SpawnError` string rather than an exception, because every caller here has to
// turn that condition into one diagnostic line — a stack trace out of a benchmark runner is noise.
class ProcessRun {
    ExitCode: int
    Stdout: string
    Stderr: string
    SpawnError: string

    constructor(exitCode: int, stdout: string, stderr: string, spawnError: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
        SpawnError = spawnError
    }

    func Succeeded(): bool {
        return SpawnError == "" && ExitCode == 0
    }

    // The one-line reason this run is unusable, for a caller that is about to abort. Empty when
    // the process ran to a zero exit.
    func FailureReason(): string {
        if SpawnError != "" {
            return SpawnError
        }
        if ExitCode != 0 {
            return "exited with code " + ExitCode.ToString()
        }
        return ""
    }
}

func RunProcess(fileName: string, arguments: string, workingDirectory: string): ProcessRun {
    startInfo := new ProcessStartInfo { FileName: fileName, Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    try {
        process := new Process { StartInfo: startInfo }
        process.Start()
        stdout := process.StandardOutput.ReadToEnd()
        stderr := process.StandardError.ReadToEnd()
        process.WaitForExit()
        exitCode := process.ExitCode
        process.Dispose()
        return new ProcessRun(exitCode, stdout, stderr, "")
    } catch error: Exception {
        return new ProcessRun(-1, "", "", error.Message)
    }
}

// A path or argument as it must appear on a command line. Every path this runner passes to a child
// comes from `Path.GetTempPath()` or from `--repo`, either of which may contain a space.
func QuoteArgument(value: string): string {
    return "\"" + value + "\""
}

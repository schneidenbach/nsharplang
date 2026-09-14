namespace NSharpLang.GateScriptContracts.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text
import System.Text.RegularExpressions

// ─── THE SHELL-SCRIPT CONTRACTS OF THE SHIPPED TOOLCHAIN ──────────────────────────────────────
//
// This project replaces three C# files that never tested C#: `tests/GateStepInputSetGuardTests.cs`,
// `tests/VscodeIntegrationHarnessTests.cs` and `tests/SetupLocalScriptTests.cs`. Every row in all
// three reads a shell script as TEXT or runs one as a PROCESS and reads what it printed. Nothing
// about those claims is tied to the language the harness is written in, so they move to N# whole.
//
// Three kinds of claim live here:
//
//   * `GateStepInputSets.tests.nl` — the product gate's per-step input-set cache is only sound
//     while every declared input set is a superset of what the step actually reads. Those rows
//     read `tests/scripts/test-all-core.sh` and `tests/scripts/test-all.sh` as text and, for the
//     end-to-end row, run the script's OWN embedded python hasher against a synthetic fixture
//     tree. They never run the gate itself.
//   * `VscodeIntegrationHarness.tests.nl` — the VS Code harness's own self-test mode, plus the
//     TypeScript runner's zero-matched-tests guard.
//   * `SetupLocalScripts.tests.nl` — the installers, every one of them in `--dry-run` or `--help`
//     mode with `HOME` pointed at a throwaway directory, so nothing is ever installed.
class ProcessRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }

    func Report(): string {
        return "exit code " + ExitCode.ToString() + "\n--- stdout ---\n" + Stdout + "\n--- stderr ---\n" + Stderr
    }
}

// A child process described declaratively, so the spawn kernel below stays one function. Arguments
// are carried as a LIST rather than a command line: every script here is invoked as
// `bash -lc "<whole command>"`, and the command must arrive as ONE argv entry or the shell would
// re-split it. `ProcessStartInfo.ArgumentList` is what guarantees that.
//
// Environment overrides are carried the same way. `EnvironmentNames`/`EnvironmentValues` are
// parallel lists rather than a dictionary because the child's environment is applied in order and
// the lists keep the spelling identical to the deleted C#'s ordered `startInfo.Environment[...]`
// assignments.
class ProcessLaunch {
    FileName: string
    WorkingDirectory: string
    TimeoutMilliseconds: int
    Arguments: List<string>
    EnvironmentNames: List<string>
    EnvironmentValues: List<string>
    ClearedEnvironmentNames: List<string>

    constructor(fileName: string, workingDirectory: string, timeoutMilliseconds: int) {
        FileName = fileName
        WorkingDirectory = workingDirectory
        TimeoutMilliseconds = timeoutMilliseconds
        Arguments = new List<string>()
        EnvironmentNames = new List<string>()
        EnvironmentValues = new List<string>()
        ClearedEnvironmentNames = new List<string>()
    }

    func WithEnvironment(name: string, value: string) {
        EnvironmentNames.Add(name)
        EnvironmentValues.Add(value)
    }
}

// Start the child, drain BOTH pipes as tasks BEFORE waiting — that is what keeps a chatty script
// from deadlocking against a full pipe buffer — then wait under a ceiling. A timeout kills the
// whole process tree and reports exit 124, exactly as the deleted C# harnesses did, so a hung
// installer becomes a failing row rather than a hung gate.
func Run(launch: ProcessLaunch): ProcessRun {
    startInfo := new ProcessStartInfo { FileName: launch.FileName }
    startInfo.WorkingDirectory = launch.WorkingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    argumentIndex := 0
    while argumentIndex < launch.Arguments.Count {
        startInfo.ArgumentList.Add(launch.Arguments[argumentIndex])
        argumentIndex = argumentIndex + 1
    }

    clearedIndex := 0
    while clearedIndex < launch.ClearedEnvironmentNames.Count {
        startInfo.Environment.Remove(launch.ClearedEnvironmentNames[clearedIndex])
        clearedIndex = clearedIndex + 1
    }

    environmentIndex := 0
    while environmentIndex < launch.EnvironmentNames.Count {
        startInfo.Environment[launch.EnvironmentNames[environmentIndex]] = launch.EnvironmentValues[environmentIndex]
        environmentIndex = environmentIndex + 1
    }

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(launch.TimeoutMilliseconds) {
        process.Kill(true)
        process.WaitForExit()
        timedOutStdout := ""
        if stdoutTask.IsCompleted {
            timedOutStdout = stdoutTask.Result
        }

        timedOutStderr := ""
        if stderrTask.IsCompleted {
            timedOutStderr = stderrTask.Result
        }

        process.Dispose()
        return new ProcessRun(124, timedOutStdout, timedOutStderr + "\nTimed out after " + launch.TimeoutMilliseconds.ToString() + " ms.")
    }

    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    exitCode := process.ExitCode
    process.Dispose()
    return new ProcessRun(exitCode, stdout, stderr)
}

// ─── FINDING THE REPOSITORY ───────────────────────────────────────────────────────────────────
//
// `nlc test` hosts the emitted tests inside the CLI's own process, so `AppContext.BaseDirectory`
// is a directory inside the repository and the upward walk for `NSharpLang.sln` finds the root —
// the same anchor the deleted C# used.
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

    throw new InvalidOperationException("Could not find repository root (NSharpLang.sln). Searched upward from " + AppContext.BaseDirectory + ".")
}

func ReadGateScript(name: string): string {
    return File.ReadAllText(Path.Combine(Path.Combine(Path.Combine(RepositoryRoot(), "tests"), "scripts"), name))
}

// ─── RUNNING A SCRIPT ─────────────────────────────────────────────────────────────────────────

// `bash -lc "<command>"` with the repository as the working directory. The login shell matters:
// the installers source profile files, and the deleted C# proved them under exactly that shell.
func BashLaunch(command: string, timeoutMilliseconds: int): ProcessLaunch {
    launch := new ProcessLaunch("bash", RepositoryRoot(), timeoutMilliseconds)
    launch.Arguments.Add("-lc")
    launch.Arguments.Add(command)
    launch.WithEnvironment("DOTNET_NOLOGO", "1")
    return launch
}

// ─── TEMPORARY DIRECTORIES ────────────────────────────────────────────────────────────────────

func NewTempDirectory(prefix: string): string {
    directory := Path.Combine(Path.GetTempPath(), prefix + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

// Best-effort cleanup, mirroring the `try { Directory.Delete(...) } catch { }` of the deleted C#:
// a throwaway HOME that resists deletion must never turn a passing contract into a failing row.
//
// The catch RETURNS rather than sitting empty: an empty catch is NL011, and the `// nlc:ignore`
// comment that would clear it cannot be used here — `nlc format` relocates a comment written
// immediately above a `} catch` line to the end of the file, which silently destroys the
// suppression. Returning is the honest spelling of "cleanup is best effort" anyway.
func DeleteTempDirectory(directory: string) {
    try {
        if Directory.Exists(directory) {
            Directory.Delete(directory, true)
        }
    } catch error: Exception {
        return
    }
}

// ─── READING SHELL/PYTHON LITERALS OUT OF THE GATE SCRIPTS ────────────────────────────────────

// Every double-quoted string inside a python tuple/list body, in source order.
func QuotedStrings(tupleBody: string): List<string> {
    values := new List<string>()
    matches := Regex.Matches(tupleBody, "\"(?<value>[^\"]+)\"")
    index := 0
    while index < matches.Count {
        values.Add(matches[index].Groups["value"].Value)
        index = index + 1
    }

    return values
}

func RequireMatch(input: string, pattern: string, failure: string): Match {
    found := Regex.Match(input, pattern, RegexOptions.Singleline)
    if !found.Success {
        throw new InvalidOperationException(failure)
    }

    return found
}

// The `COMMON` tuple of `tests/scripts/test-all-core.sh`, shared by every input set.
func CommonPrefixes(coreScript: string): List<string> {
    commonMatch := RequireMatch(coreScript, "COMMON\\s*=\\s*\\((?<body>[^)]*)\\)", "Could not find the COMMON tuple in tests/scripts/test-all-core.sh.")
    return QuotedStrings(commonMatch.Groups["body"].Value)
}

// The `SETS` literal of `tests/scripts/test-all-core.sh`, each entry expanded to COMMON + its own
// prefixes — the exact set the embedded hasher matches paths against.
func ParseInputSets(coreScript: string): Dictionary<string, List<string>> {
    common := CommonPrefixes(coreScript)
    setsMatch := RequireMatch(coreScript, "SETS\\s*=\\s*\\{(?<body>.*?)\\n\\}", "Could not find the SETS literal in tests/scripts/test-all-core.sh.")

    sets := new Dictionary<string, List<string>>()
    // The body is hoisted into a local rather than passed inline. A group-indexer chain
    // (`match.Groups["x"].Value`) in the ARGUMENT of an otherwise-modeled static call declines at
    // emit — NL103, `emit.call.static-member-unmodeled: static call 'Regex.Matches' ... is not
    // modeled` — and the local is the documented way past it. Nothing about the claim changes.
    setsBody: string = setsMatch.Groups["body"].Value
    entries := Regex.Matches(setsBody, "\"(?<name>\\w+)\":\\s*COMMON\\s*\\+\\s*\\((?<body>[^)]*)\\)", RegexOptions.Singleline)
    entryIndex := 0
    while entryIndex < entries.Count {
        entry := entries[entryIndex]
        prefixes := new List<string>()
        commonIndex := 0
        while commonIndex < common.Count {
            prefixes.Add(common[commonIndex])
            commonIndex = commonIndex + 1
        }

        own := QuotedStrings(entry.Groups["body"].Value)
        ownIndex := 0
        while ownIndex < own.Count {
            prefixes.Add(own[ownIndex])
            ownIndex = ownIndex + 1
        }

        sets[entry.Groups["name"].Value] = prefixes
        entryIndex = entryIndex + 1
    }

    return sets
}

// The salted environment variable names, read from the per-step salt in test-all-core.sh.
func SaltedEnvNames(coreScript: string): List<string> {
    coreEnvMatch := RequireMatch(coreScript, "ENV_NAMES\\s*=\\s*\\((?<body>[^)]*)\\)", "Could not find the ENV_NAMES tuple in tests/scripts/test-all-core.sh.")
    return QuotedStrings(coreEnvMatch.Groups["body"].Value)
}

// The embedded per-step hasher, lifted out of its heredoc so it can be run in isolation against a
// synthetic tree. This is how the end-to-end row proves the SHIPPED hasher's behavior rather than
// a re-implementation of it.
func ExtractStepHashPython(coreScript: string): string {
    lines := coreScript.Split('\n')
    start := -1
    index := 0
    while index < lines.Length {
        if start < 0 && lines[index].Contains("STEP_HASH_OUTPUT=\"$(python3") {
            start = index
        }

        index = index + 1
    }

    if start < 0 {
        throw new InvalidOperationException("Could not find the STEP_HASH_OUTPUT python heredoc in tests/scripts/test-all-core.sh.")
    }

    end := -1
    scan := start + 1
    while scan < lines.Length {
        if end < 0 && lines[scan].TrimEnd() == "PY" {
            end = scan
        }

        scan = scan + 1
    }

    if end <= start {
        throw new InvalidOperationException("Could not find the PY heredoc terminator in tests/scripts/test-all-core.sh.")
    }

    builder := new StringBuilder()
    body := start + 1
    while body < end {
        if body > start + 1 {
            builder.Append("\n")
        }

        builder.Append(lines[body])
        body = body + 1
    }

    return builder.ToString()
}

// ─── PREFIX COVERAGE ──────────────────────────────────────────────────────────────────────────
//
// A trailing-slash prefix covers everything beneath it, and also covers the directory itself
// spelled without the slash; a slashless prefix is an exact file name. Ordinal comparison, which
// is what N# string equality and `StartsWith` already do.
func IsCovered(relativePath: string, prefixes: List<string>): bool {
    index := 0
    while index < prefixes.Count {
        prefix := prefixes[index]
        if prefix.EndsWith("/") {
            if relativePath.StartsWith(prefix) || prefix == relativePath + "/" {
                return true
            }
        } else {
            if relativePath == prefix {
                return true
            }
        }

        index = index + 1
    }

    return false
}

func JoinLines(values: List<string>): string {
    return string.Join("\n", values)
}

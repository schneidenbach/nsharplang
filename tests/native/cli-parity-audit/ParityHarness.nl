namespace NSharpLang.CliParityAudit.Tests

import System
import System.Diagnostics
import System.IO
import System.Runtime.InteropServices
import System.Text.Json
import System.Threading

// ─── THE SHIPPED `nlc` PARITY AUDIT, PROVEN AS PROCESSES ──────────────────────────────────────
//
// This project replaces `tests/CliParityAuditTests.cs`. Every row there reached the CLI one of two
// ways: a private `NSharpLang.Cli.Program.Execute` found by REFLECTION, or a command class's own
// `Execute(string[])` called in process — and then read what it printed back through
// `Console.SetOut` / `Console.SetError` / `Console.SetIn`.
//
// NEITHER ROUTE SURVIVES THE MOVE TO N#, AND BOTH DESERVED TO DIE:
//
//   * `Console.SetOut` declines at emit on this backend — measured out of repository as
//     `NL103 ... Declined at emit.call.static-member-unmodeled: static call 'Console.SetOut'
//     with 1 argument(s) is not modeled` — so a `.tests.nl` cannot see what an in-process call
//     printed at all.
//   * A reflected PRIVATE entry point proves nothing about the binary a user runs. The deleted
//     bodies never showed that `nlc lint` REACHES `LintCommand`, only that `LintCommand.Execute`
//     behaves when handed an argument array.
//
// So every row below spawns the REAL built CLI — `dotnet <repoRoot>/src/NSharpLang.Cli/bin/Debug/
// net10.0/Cli.dll <args>` — with the fixture directory as the child's working directory. That is
// strictly stronger than the C# was, because the dispatch from the command NAME is now part of
// the claim.
//
// `Directory.SetCurrentDirectory` DISAPPEARS. Eleven deleted bodies saved the process-wide cwd,
// moved it, and restored it in a `finally`; that mutation of shared process state is exactly why
// the C# class had to sit in the serial xunit `[Collection("ProcessState")]`. A child process
// carries its OWN working directory, so the rows here are independent and this project needs no
// serial collection.
//
// THE STDERR SILENCE CLAIMS ARE NOT VACUOUS. Against a real process, `stderr.Trim().Length == 0`
// is a fact about which STREAM a sentence reached, and the neighbouring rows on the same commands
// (`nlc new` with no arguments, `nlc pack` without a project.yml, `nlc init --type service`, the
// unknown-command row) prove stderr is reachable from this binary at all.

// ─── THE SPAWN KERNEL ─────────────────────────────────────────────────────────────────────────
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
// it. Draining stdout and stderr as tasks BEFORE the wait is what keeps a chatty command from
// deadlocking against a full pipe buffer; the ceiling is what turns a hung toolchain into a
// failing row rather than a hung gate.
func ExecuteProcess(startInfo: ProcessStartInfo, timeoutMilliseconds: int): ProcessRun {
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
        throw new TimeoutException("Process '" + startInfo.FileName + "' did not complete within " + timeoutMilliseconds.ToString() + " ms.")
    }

    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    exitCode := process.ExitCode
    process.Dispose()
    return new ProcessRun(exitCode, stdout, stderr)
}

// Same kernel, but it rewrites a watched file after `delayMilliseconds` while the child is still
// running. This is the N# shape of the deleted `WatchCommand` row's `Task.Run(async () => { await
// Task.Delay(500); File.WriteAllText(...) })`.
func ExecuteProcessWithDelayedWrite(
    startInfo: ProcessStartInfo,
    filePath: string,
    contents: string,
    delayMilliseconds: int,
    timeoutMilliseconds: int
): ProcessRun {
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()

    Thread.Sleep(delayMilliseconds)
    File.WriteAllText(filePath, contents)

    if !process.WaitForExit(timeoutMilliseconds) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("Watch process did not complete within " + timeoutMilliseconds.ToString() + " ms.")
    }

    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    exitCode := process.ExitCode
    process.Dispose()
    return new ProcessRun(exitCode, stdout, stderr)
}

// ─── FINDING THE BUILT CLI ────────────────────────────────────────────────────────────────────

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
    binDirectory := Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug")
    cliDll := Path.Combine(Path.Combine(binDirectory, "net10.0"), "Cli.dll")
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The built N# CLI was not found beside the repository root: " + cliDll)
    }

    return cliDll
}

// `ArgumentList` rather than a hand-quoted `Arguments` string, because several rows pass temp
// directory paths and one deliberately passes an install root WITH A SPACE IN IT.
func NlcStartInfo(arguments: string[], workingDirectory: string): ProcessStartInfo {
    startInfo := new ProcessStartInfo { FileName: "dotnet" }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.ArgumentList.Add(CliDll())
    for argument in arguments {
        startInfo.ArgumentList.Add(argument)
    }

    return startInfo
}

// Five minutes is the ceiling. An `nlc` invocation that takes longer than that is hung, not slow.
func NlcTimeoutMilliseconds(): int {
    return 300000
}

func Nlc(arguments: string[], workingDirectory: string): ProcessRun {
    return ExecuteProcess(NlcStartInfo(arguments, workingDirectory), NlcTimeoutMilliseconds())
}

func NlcWithEnvironment(arguments: string[], workingDirectory: string, name: string, value: string): ProcessRun {
    startInfo := NlcStartInfo(arguments, workingDirectory)
    startInfo.Environment[name] = value
    return ExecuteProcess(startInfo, NlcTimeoutMilliseconds())
}

func NlcWithDelayedWrite(
    arguments: string[],
    workingDirectory: string,
    filePath: string,
    contents: string,
    delayMilliseconds: int
): ProcessRun {
    return ExecuteProcessWithDelayedWrite(
        NlcStartInfo(arguments, workingDirectory),
        filePath,
        contents,
        delayMilliseconds,
        NlcTimeoutMilliseconds()
    )
}

// `nlc format --stdin` with a real redirected stdin.
//
// COMPILER DEFECT WORKAROUND, RECORDED HERE SO IT IS NOT MISTAKEN FOR A STYLE CHOICE. Reading
// `Process.StandardInput` declines on this backend, while `Process.StandardOutput` and
// `Process.StandardError` emit fine:
//
//     test "standard input property" {
//         process := new Process { StartInfo: new ProcessStartInfo { FileName: "true" } }
//         writer: StreamWriter = process.StandardInput
//         assert writer != null
//     }
//     NL103 ... Declined at emit.typed-local.initializer: typed local initializer expression
//     emission declined for 'writer'
//
// So the child's stdin is redirected by the SHELL from a fixture file instead. The claim is
// unweakened — the CLI still reads its source off a real stdin handle it did not open.
func NlcWithStdinFile(arguments: string[], workingDirectory: string, stdinPath: string): ProcessRun {
    command := Quote(CliDll())
    for argument in arguments {
        command = command + " " + Quote(argument)
    }

    command = "dotnet " + command + " < " + Quote(stdinPath)

    startInfo := new ProcessStartInfo { FileName: ShellFileName() }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.ArgumentList.Add(ShellCommandSwitch())
    startInfo.ArgumentList.Add(command)
    return ExecuteProcess(startInfo, NlcTimeoutMilliseconds())
}

func ShellFileName(): string {
    if RuntimeInformation.IsOSPlatform(OSPlatform.Windows) {
        return "cmd.exe"
    }

    return "/bin/sh"
}

func ShellCommandSwitch(): string {
    if RuntimeInformation.IsOSPlatform(OSPlatform.Windows) {
        return "/c"
    }

    return "-c"
}

func Quote(value: string): string {
    return "\"" + value + "\""
}

// ─── FIXTURES ON DISK ─────────────────────────────────────────────────────────────────────────

func NewTempDirectory(): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-cli-audit-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func MissingDirectoryPath(): string {
    return Path.Combine(Path.GetTempPath(), "nsharp-nonexistent-" + Guid.NewGuid().ToString("N"))
}

func DeleteTempDirectory(directory: string) {
    if Directory.Exists(directory) {
        Directory.Delete(directory, true)
    }
}

func WriteFile(directory: string, name: string, contents: string) {
    File.WriteAllText(Path.Combine(directory, name), contents)
}

func TopLevelProjectFileCount(directory: string, pattern: string): int {
    return Directory.GetFiles(directory, pattern, SearchOption.TopDirectoryOnly).Length
}

func IsBlank(text: string): bool {
    return text.Trim().Length == 0
}

// Rows that only read `--help` or reject a missing directory need SOME working directory; the
// system temp directory is the one place guaranteed to hold no project.yml.
func HelpWorkingDirectory(): string {
    return Path.GetTempPath()
}

// ─── READING A JSON ARRAY ─────────────────────────────────────────────────────────────────────
//
// A `JsonElement` INDEXER declines at emit on this backend, so arrays are walked with
// `EnumerateArray` — the spelling `tests/native/cli-command-contracts` already uses.
func FirstElement(items: JsonElement): JsonElement {
    enumerator := items.EnumerateArray()
    while enumerator.MoveNext() {
        return enumerator.Current
    }

    throw new InvalidOperationException("The JSON array is empty.")
}

// ─── THE CANONICAL `nlc new` PROJECT SHAPE ────────────────────────────────────────────────────
//
// The deleted `AssertCanonicalProjectShape` private helper, carried over whole. Every claim it
// made survives, including the two NEGATIVE ones that are the point of the csproj-free policy:
// `nlc new` must not write a user-authored `.csproj`, and it must not write a generated
// `.g.csproj` before a build has run.
func AssertCanonicalProjectShape(
    projectDirectory: string,
    projectName: string,
    hasProgram: bool,
    hasTests: bool,
    hasWebController: bool
) {
    assert File.Exists(Path.Combine(projectDirectory, "project.yml"))
    assert File.Exists(Path.Combine(projectDirectory, "global.json"))
    assert File.Exists(Path.Combine(projectDirectory, "NuGet.config"))
    assert !File.Exists(Path.Combine(projectDirectory, projectName + ".csproj"))
    assert !File.Exists(Path.Combine(projectDirectory, projectName + ".g.csproj"))
    assert TopLevelProjectFileCount(projectDirectory, "*.csproj") == 0

    assert File.Exists(Path.Combine(projectDirectory, "Program.nl")) == hasProgram
    assert File.Exists(Path.Combine(projectDirectory, "Calculator.tests.nl")) == hasTests
    assert File.Exists(Path.Combine(Path.Combine(projectDirectory, "Controllers"), "WeatherController.nl")) == hasWebController

    projectYaml := File.ReadAllText(Path.Combine(projectDirectory, "project.yml"))
    assert projectYaml.Contains("name: " + projectName)
    if hasProgram {
        assert projectYaml.Contains("entry: Program.nl")
    } else {
        assert projectYaml.Contains("outputType: library")
    }
}

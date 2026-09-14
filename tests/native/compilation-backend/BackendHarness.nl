namespace NSharpLang.CompilationBackend.Tests

import System
import System.Diagnostics
import System.IO
import System.Runtime.InteropServices

// ─── THE SHIPPED BACKEND CONTRACTS, PROVEN AS PROCESSES ───────────────────────────────────────
//
// This project replaces `tests/CompilationBackendTests.cs`. Every row there reached the CLI the
// same two ways: `CheckCommand.Execute(...)`/`PackCommand.Execute(...)` in process, or a private
// `Program.Execute` found by reflection — and then read what it printed through `Console.SetOut`.
// Neither route survives the move to N#: `Console.SetOut` declines at emit
// (`emit.call.static-member-unmodeled`), and a reflected private entry point proves nothing about
// the binary the user runs.
//
// Every row below therefore drives the REAL `nlc` binary as a child process with the fixture
// directory as its working directory. That is strictly stronger than the deleted C#: the old
// bodies never proved `nlc build` reaches `BuildCommand` at all, and their
// `Directory.SetCurrentDirectory` dance (which forced the whole class into the serial
// "ProcessState" xunit collection) disappears, because a child process carries its own cwd.

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
// it. Draining stdout and stderr as tasks BEFORE the wait is what keeps a chatty build from
// deadlocking against a full pipe buffer; the ceiling is what turns a hung toolchain into a
// failing row rather than a hung gate.
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
    cliDll := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), Path.Combine("net10.0", "Cli.dll"))
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The built N# CLI was not found beside the repository root.")
    }

    return cliDll
}

func Quote(value: string): string {
    return "\"" + value + "\""
}

// `nlc <arguments>` with `workingDirectory` as the process cwd. Five minutes is the ceiling the
// deleted C# used for its one out-of-process row; every row here inherits it, because an IL build
// that takes longer than that is hung, not slow.
func Nlc(arguments: string, workingDirectory: string): ProcessRun {
    return RunProcess("dotnet", Quote(CliDll()) + " " + arguments, workingDirectory, 300000)
}

func DotnetApp(assemblyPath: string, workingDirectory: string): ProcessRun {
    return RunProcess("dotnet", Quote(assemblyPath), workingDirectory, 300000)
}

// ─── FIXTURES ON DISK ─────────────────────────────────────────────────────────────────────────

func NewTempDirectory(): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-backend-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func DeleteTempDirectory(directory: string) {
    if Directory.Exists(directory) {
        Directory.Delete(directory, true)
    }
}

func WriteFile(directory: string, name: string, contents: string) {
    File.WriteAllText(Path.Combine(directory, name), contents)
}

func NormalizePath(path: string): string {
    return path.Replace("\\", "/")
}

func PublishedAppPath(publishDirectory: string, assemblyName: string): string {
    executableName := assemblyName
    if RuntimeInformation.IsOSPlatform(OSPlatform.Windows) {
        executableName = assemblyName + ".cmd"
    }

    return Path.Combine(publishDirectory, executableName)
}

func DifferentRuntimeIdentifier(): string {
    current := RuntimeInformation.RuntimeIdentifier
    candidates := ["linux-x64", "osx-arm64", "win-x64"]
    for candidate in candidates {
        if !string.Equals(candidate, current, StringComparison.OrdinalIgnoreCase) {
            return candidate
        }
    }

    throw new InvalidOperationException("Every candidate runtime identifier matched the current one.")
}

// The deleted C# proved "no C# transpilation happened" by asserting the fixture holds no generated
// csproj or .cs. Both halves survive, because that is the whole point of the IL backend.
func GeneratedProjectFileCount(directory: string): int {
    return Directory.GetFiles(directory, "*.g.csproj", SearchOption.TopDirectoryOnly).Length
}

func GeneratedCSharpFileCount(directory: string): int {
    return Directory.GetFiles(directory, "*.g.cs", SearchOption.AllDirectories).Length
}

// The declining shape the two "requires columnar emission" rows depend on: a generator whose
// element type is an async lambda. It is the sentinel the repository already uses for "columnar
// declines", so it moves here verbatim rather than being re-derived.
func DecliningSource(): string {
    return "import System\nimport System.Collections.Generic\nimport System.Threading.Tasks\nfunc* Relay(): IEnumerable<Func<Task<int>>> {\n    yield async () => 42\n}\n\n\nfunc main() {\n    print \"counted\"\n}\n"
}

namespace NSharpLang.CensusProcessMembers.Tests

import System
import System.Diagnostics
import System.IO
import System.Threading.Tasks


// CENSUS — THE INSTANCE SURFACE OF `System.Diagnostics.Process`, EXECUTED.
//
// `Process` was named in the instance-member resolver by an EXCLUSIVE arm that answered `ExitCode`,
// `StandardOutput` and `StandardError` and returned false for every other member, so `p.Id`,
// `p.StartTime`, `p.ProcessName`, `p.HasExited` and `p.MainModule` could not be read at all — while
// the class's STATIC members emitted, which is what made the gap look like a per-member table rather
// than a whole surface. The arm is gone and the class reaches the general ordinary-reference arm.
//
// `p.WaitForExitAsync()` is the other half and is not a property at all: its single parameter is
// `CancellationToken cancellationToken = default`, and a struct's `default` read back as an
// unfillable optional, so the call declined at arity 0.
//
// Every row below runs. The values are compared against an independent witness wherever one exists
// (`Environment.ProcessId`, `Environment.ProcessPath`, the exit code a child was told to produce)
// rather than against the same read restated.
class ProcessMembers {
    static func CurrentId(): int {
        current := Process.GetCurrentProcess()
        return current.Id
    }

    static func CurrentProcessName(): string {
        current := Process.GetCurrentProcess()
        return current.ProcessName
    }

    static func CurrentHasExited(): bool {
        current := Process.GetCurrentProcess()
        return current.HasExited
    }

    // `StartTime` is a `DateTime`, so the read has to survive the value-type result path as well as
    // the receiver one. The answer is compared against "now" by the caller.
    static func CurrentStartTime(): DateTime {
        current := Process.GetCurrentProcess()
        return current.StartTime
    }

    // `MainModule` returns a `ProcessModule` — a referenced class that no table named — and its own
    // `FileName` is then an ordinary read through that result.
    static func CurrentMainModuleFileName(): string {
        current := Process.GetCurrentProcess()
        module := current.MainModule
        if module == null {
            return ""
        }
        return module.FileName
    }

    // A CHILD PROCESS, STARTED AND AWAITED. `WaitForExitAsync()` omits the `CancellationToken` its
    // only parameter defaults, and the exit code read afterwards is the one the child was told to
    // produce, so the await genuinely completed before the read.
    static async func RunAndWaitForExit(exitCode: int): Task<int> {
        startInfo := new ProcessStartInfo()
        startInfo.FileName = "/bin/sh"
        startInfo.Arguments = "-c \"exit " + exitCode.ToString() + "\""
        startInfo.UseShellExecute = false
        startInfo.RedirectStandardOutput = true
        child := Process.Start(startInfo)
        if child == null {
            return -1
        }
        await child.WaitForExitAsync()
        return child.ExitCode
    }

    // The child's redirected output, read through `StandardOutput` — one of the three members the
    // removed arm used to answer, so this row is the control that says they still answer.
    static async func RunAndReadOutput(text: string): Task<string> {
        startInfo := new ProcessStartInfo()
        startInfo.FileName = "/bin/sh"
        startInfo.Arguments = "-c \"printf %s " + text + "\""
        startInfo.UseShellExecute = false
        startInfo.RedirectStandardOutput = true
        child := Process.Start(startInfo)
        if child == null {
            return ""
        }
        output := child.StandardOutput.ReadToEnd()
        await child.WaitForExitAsync()
        return output
    }

    // A STATIC external call whose trailing optional is the same `CancellationToken = default`, so
    // the fill is exercised on the static side too.
    static async func WriteThenReadBack(path: string, contents: string): Task<string> {
        await File.WriteAllTextAsync(path, contents)
        return await File.ReadAllTextAsync(path)
    }
}

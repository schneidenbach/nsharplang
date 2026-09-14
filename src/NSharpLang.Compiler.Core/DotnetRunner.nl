namespace NSharpLang.Cli

import System
import System.Diagnostics
import System.IO

class DotnetRunResult {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

class DotnetRunner {
    static DefaultTimeout: TimeSpan => TimeSpan.FromMinutes(5)

    static func Run(arguments: string, workingDirectory: string? = null, captureOutput: bool = true, timeout: TimeSpan? = null): DotnetRunResult {
        return RunProcessCore("dotnet", arguments, workingDirectory, captureOutput, timeout)
    }

    static func RunPassthrough(arguments: string, workingDirectory: string? = null, verbose: bool = false): int {
        psi := BuildPsi("dotnet", arguments, workingDirectory)
        psi.RedirectStandardOutput = false
        psi.RedirectStandardError = false
        psi.UseShellExecute = false

        process := new Process { StartInfo: psi }
        process.Start()
        process.WaitForExit()
        exitCode := process.ExitCode
        process.Dispose()
        return exitCode
    }

    // THE SHAPE THAT INHERITS THIS PROCESS'S DIRECTORY AND TAKES THE DEFAULT TIMEOUT, DECLARED AT ITS
    // OWN ARITY. An N#-emitted assembly writes no nullability metadata and a defaulted parameter
    // cannot be omitted at a call site yet, so a CALLER IN ANOTHER ASSEMBLY cannot reach the four-
    // parameter declaration below at all — neither by omitting the tail nor by passing `null` for it.
    // The two-argument call every such caller wants is therefore a declaration rather than a default.
    static func RunProcess(fileName: string, arguments: string): DotnetRunResult {
        return RunProcessCore(fileName, arguments, null, true, null)
    }

    static func RunProcess(fileName: string, arguments: string, workingDirectory: string? = null, timeout: TimeSpan? = null): DotnetRunResult {
        return RunProcessCore(fileName, arguments, workingDirectory, true, timeout)
    }

    static func RunProcessCore(fileName: string, arguments: string, workingDirectory: string?, captureOutput: bool, timeout: TimeSpan?): DotnetRunResult {
        psi := BuildPsi(fileName, arguments, workingDirectory)
        psi.RedirectStandardOutput = captureOutput
        psi.RedirectStandardError = captureOutput
        psi.UseShellExecute = false

        process := new Process { StartInfo: psi }
        process.Start()

        if !captureOutput {
            process.WaitForExit()
            result := new DotnetRunResult(process.ExitCode, "", "")
            process.Dispose()
            return result
        }

        stdoutTask := process.StandardOutput.ReadToEndAsync()
        stderrTask := process.StandardError.ReadToEndAsync()

        effectiveTimeout := DotnetRunner.DefaultTimeout
        if timeout.HasValue {
            effectiveTimeout = timeout.Value
        }

        exited := process.WaitForExit((int)effectiveTimeout.TotalMilliseconds)
        if !exited {
            try {
                process.Kill(true)
            } catch {
            }

            process.Dispose()
            throw new TimeoutException($"Process '{fileName} {arguments}' did not complete within {effectiveTimeout}.")
        }

        process.WaitForExit()

        result := new DotnetRunResult(process.ExitCode, stdoutTask.Result, stderrTask.Result)
        process.Dispose()
        return result
    }

    static func BuildPsi(fileName: string, arguments: string, workingDirectory: string?): ProcessStartInfo {
        psi := new ProcessStartInfo { FileName: fileName, Arguments: arguments }

        if workingDirectory != null {
            psi.WorkingDirectory = Path.GetFullPath(workingDirectory ?? "")
        }

        return psi
    }
}

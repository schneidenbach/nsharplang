namespace NSharpLang.Cli

import System
import System.Diagnostics
import System.IO

public class DotnetRunner {
    public static DefaultTimeout: TimeSpan => TimeSpan.FromMinutes(5)

    public class RunResult {
        public ExitCode: int
        public Stdout: string
        public Stderr: string

        constructor(exitCode: int, stdout: string, stderr: string) {
            ExitCode = exitCode
            Stdout = stdout
            Stderr = stderr
        }
    }

    public static func Run(
        arguments: string,
        workingDirectory: string? = null,
        captureOutput: bool = true,
        timeout: TimeSpan? = null): DotnetRunner.RunResult {
        return RunProcessCore("dotnet", arguments, workingDirectory, captureOutput, timeout)
    }

    public static func RunPassthrough(
        arguments: string,
        workingDirectory: string? = null,
        verbose: bool = false): int {
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

    public static func RunProcess(
        fileName: string,
        arguments: string,
        workingDirectory: string? = null,
        timeout: TimeSpan? = null): DotnetRunner.RunResult {
        return RunProcessCore(fileName, arguments, workingDirectory, true, timeout)
    }

    static func RunProcessCore(
        fileName: string,
        arguments: string,
        workingDirectory: string?,
        captureOutput: bool,
        timeout: TimeSpan?): DotnetRunner.RunResult {
        psi := BuildPsi(fileName, arguments, workingDirectory)
        psi.RedirectStandardOutput = captureOutput
        psi.RedirectStandardError = captureOutput
        psi.UseShellExecute = false

        process := new Process { StartInfo: psi }
        process.Start()

        if !captureOutput {
            process.WaitForExit()
            result := new DotnetRunner.RunResult(process.ExitCode, "", "")
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

        result := new DotnetRunner.RunResult(
            process.ExitCode,
            stdoutTask.Result,
            stderrTask.Result)
        process.Dispose()
        return result
    }

    static func BuildPsi(
        fileName: string,
        arguments: string,
        workingDirectory: string?): ProcessStartInfo {
        psi := new ProcessStartInfo {
            FileName: fileName,
            Arguments: arguments
        }

        if workingDirectory != null {
            psi.WorkingDirectory = Path.GetFullPath(workingDirectory ?? "")
        }

        return psi
    }
}

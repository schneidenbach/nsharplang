namespace NSharpLang.Cli.Daemon

import System
import System.Diagnostics
import System.Threading

// The result of one startup wait. The same wait loop is used by the product client and by the
// native daemon tests with simulated process signals, so the tests prove the production deadline
// and early-exit behavior without sleeping for a full timeout.
class DaemonStartupWaitResult {
    Ready: bool
    ProcessExited: bool
    ExitCode: int
    ElapsedMilliseconds: long
    OutputTail: string

    constructor(ready: bool, processExited: bool, exitCode: int, elapsedMilliseconds: long, outputTail: string) {
        Ready = ready
        ProcessExited = processExited
        ExitCode = exitCode
        ElapsedMilliseconds = elapsedMilliseconds
        OutputTail = outputTail
    }
}

static class DaemonStartupWait {

    // Poll the daemon's real readiness signal while watching the child process. A fixed retry count
    // turns scheduler delay into a startup failure; the deadline below is only a hang ceiling.
    static func WaitUntilReady(
        isReady: Func<bool>,
        hasExited: Func<bool>,
        getExitCode: Func<int>,
        getOutputTail: Func<string>,
        timeoutMilliseconds: long,
        pollIntervalMilliseconds: int
    ): DaemonStartupWaitResult {
        stopwatch := Stopwatch.StartNew()
        while stopwatch.ElapsedMilliseconds < timeoutMilliseconds {
            if isReady() {
                return new DaemonStartupWaitResult(true, false, -1, stopwatch.ElapsedMilliseconds, getOutputTail())
            }

            if hasExited() {
                return new DaemonStartupWaitResult(false, true, getExitCode(), stopwatch.ElapsedMilliseconds, getOutputTail())
            }

            Thread.Sleep(pollIntervalMilliseconds)
        }

        if isReady() {
            return new DaemonStartupWaitResult(true, false, -1, stopwatch.ElapsedMilliseconds, getOutputTail())
        }

        if hasExited() {
            return new DaemonStartupWaitResult(false, true, getExitCode(), stopwatch.ElapsedMilliseconds, getOutputTail())
        }

        return new DaemonStartupWaitResult(false, false, -1, stopwatch.ElapsedMilliseconds, getOutputTail())
    }
}

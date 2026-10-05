namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// THE PROCESS FACTS A COMMAND READS, WHEN THE COMMAND IS NOT RUNNING IN ITS OWN PROCESS.
//
// `nlc check`, `build`, `test`, `run`, `format`, `lint` and `fix` normally run in the process the user
// started. When the workspace server runs them instead (`DaemonExecHost`), three readings that a
// command takes from "its process" would come from the SERVER's process and be wrong:
//
//   * the command line -- `DiagnosticColorPolicy` reads `--color=` from `Environment.GetCommandLineArgs()`,
//   * whether standard error is a terminal -- `Console.IsErrorRedirected` describes the server's
//     stderr (a log file), not the client's,
//   * and launching a child with the caller's terminal -- `nlc run` hands the built program the
//     console it was started from, which only the CLIENT process still has.
//
// So the server opens this scope around each command it executes and every such reading goes through
// it. With no scope open (the ordinary in-process case) each reading is exactly the process's own,
// so nothing about in-process execution changes.
//
// The server executes ONE command at a time (the work lock in `DaemonExecHost`), so the scope is a
// plain static rather than a thread-local: the compiler emits on its own wide-stack thread, and that
// thread must see the same answers as the thread that started the command.
class CliInvocationContext {
    private static gate: object = new object()
    private static active: bool
    private static commandLineArgs: string[]?
    private static standardErrorRedirected: bool
    private static passthroughLauncher: Func<string, string?, int>?
    private static cancelled: bool
    private static cancellationCallbacks: List<Action>?
    private static terminated: bool
    private static terminatedExitCode: int

    static func Begin(args: string[], isStandardErrorRedirected: bool, launcher: Func<string, string?, int>?) {
        CliInvocationContext.commandLineArgs = args
        CliInvocationContext.standardErrorRedirected = isStandardErrorRedirected
        CliInvocationContext.passthroughLauncher = launcher
        CliInvocationContext.cancelled = false
        CliInvocationContext.cancellationCallbacks = new List<Action>()
        CliInvocationContext.terminated = false
        CliInvocationContext.terminatedExitCode = 0
        CliInvocationContext.active = true
    }

    static func End() {
        CliInvocationContext.active = false
        CliInvocationContext.commandLineArgs = null
        CliInvocationContext.passthroughLauncher = null
        CliInvocationContext.standardErrorRedirected = false
        CliInvocationContext.cancellationCallbacks = null
        CliInvocationContext.cancelled = false
        CliInvocationContext.terminated = false
        CliInvocationContext.terminatedExitCode = 0
    }

    // True while a workspace server is executing a command on a client's behalf.
    static func IsRemoteInvocation(): bool {
        return CliInvocationContext.active
    }

    static func GetCommandLineArgs(): string[] {
        args := CliInvocationContext.commandLineArgs
        if CliInvocationContext.active && args != null {
            return args
        }

        return Environment.GetCommandLineArgs()
    }

    static func IsStandardErrorRedirected(): bool {
        if CliInvocationContext.active {
            return CliInvocationContext.standardErrorRedirected
        }

        return Console.IsErrorRedirected
    }

    // Launch `dotnet <arguments>` with the CLIENT's terminal. Answers false when no remote invocation
    // is open, in which case the caller starts the child itself, exactly as before.
    static func TryLaunchPassthrough(arguments: string, workingDirectory: string?, out exitCode: int): bool {
        exitCode = 0
        launcher := CliInvocationContext.passthroughLauncher
        if !CliInvocationContext.active || launcher == null {
            return false
        }

        exitCode = launcher(arguments, workingDirectory)
        return true
    }

    // CANCELLATION. A client that presses Ctrl-C ends its own process at once, exactly as an
    // in-process command would; the server is told, and anything the command started that would
    // otherwise outlive it (an isolated test run, above all) registers here to be stopped.
    static func RegisterCancellation(callback: Action) {
        if !CliInvocationContext.active {
            return
        }

        runNow := false
        lock CliInvocationContext.gate {
            if CliInvocationContext.cancelled {
                runNow = true
            } else {
                callbacks := CliInvocationContext.cancellationCallbacks
                if callbacks != null {
                    callbacks.Add(callback)
                }
            }
        }

        if runNow {
            callback()
        }
    }

    static func Cancel() {
        callbacks: Action[] = new Action[](0)
        lock CliInvocationContext.gate {
            if CliInvocationContext.cancelled {
                return
            }

            CliInvocationContext.cancelled = true
            registered := CliInvocationContext.cancellationCallbacks
            if registered != null {
                callbacks = registered.ToArray()
            }
        }

        for callback in callbacks {
            try {
                callback()
            } catch callbackFailure: Exception {
                continue
            }
        }
    }

    static func IsCancelled(): bool {
        return CliInvocationContext.active && CliInvocationContext.cancelled
    }

    // TERMINATION. In-process, a test that kills its process (a stack overflow, `Environment.Exit`,
    // a fail-fast) ends `nlc test` with that process's exit code and nothing after it. The server
    // runs tests in a separate process for exactly that reason, and when that process dies it ends
    // the request here: the client exits with the same code and sees nothing the command prints
    // afterwards.
    static func Terminate(exitCode: int) {
        if !CliInvocationContext.active {
            return
        }

        CliInvocationContext.terminatedExitCode = exitCode
        CliInvocationContext.terminated = true
    }

    static func IsTerminated(): bool {
        return CliInvocationContext.active && CliInvocationContext.terminated
    }

    static func TryGetTerminatedExitCode(out exitCode: int): bool {
        exitCode = 0
        if !CliInvocationContext.active || !CliInvocationContext.terminated {
            return false
        }

        exitCode = CliInvocationContext.terminatedExitCode
        return true
    }
}

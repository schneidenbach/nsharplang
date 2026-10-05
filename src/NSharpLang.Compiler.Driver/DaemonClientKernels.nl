namespace NSharpLang.Cli.Daemon

class DaemonClientKernels {
    static func GetConnectionErrorMessage(messageText: string): string {
        return "[daemon] Connection error: " + messageText
    }

    static func GetExecutablePathMissingMessage(): string {
        return "Cannot determine executable path for daemon"
    }

    static func GetStartTimeoutMilliseconds(): long {
        return 120000
    }

    static func GetStartWaitPollIntervalMilliseconds(): int {
        return 100
    }

    static func GetStartupOutputLogEnvironmentVariableName(): string {
        return "NLC_DAEMON_OUTPUT_LOG"
    }

    static func GetStartupOutputLogFileName(): string {
        return "daemon.log"
    }

    static func GetStartTimeoutMessage(socketPath: string, elapsedMilliseconds: long, processAlive: bool, outputTail: string): string {
        return "[daemon] Startup timed out after " + elapsedMilliseconds.ToString() + " ms waiting for daemon/ping to be accepted at " + socketPath + ". Child process alive: " + processAlive.ToString().ToLower() + ".\nLast daemon output:\n" + outputTail
    }

    static func GetStartExitedMessage(exitCode: int, elapsedMilliseconds: long, outputTail: string): string {
        return "[daemon] Startup failed after " + elapsedMilliseconds.ToString() + " ms: child process exited with code " + exitCode.ToString() + " before daemon/ping was accepted. Child process alive: false.\nLast daemon output:\n" + outputTail
    }

    static func GetStartFailedWithReasonMessage(messageText: string): string {
        return "Failed to start daemon: " + messageText
    }

    static func ShouldDeleteStaleSocket(
        socketErrorCode: int,
        connectFailed: bool,
        hasReadyPidFile: bool,
        notSocketErrorCode: int,
        connectionRefusedErrorCode: int
    ): bool {
        if !connectFailed {
            return false
        }

        if socketErrorCode == notSocketErrorCode {
            return true
        }

        return socketErrorCode == connectionRefusedErrorCode && hasReadyPidFile
    }
}

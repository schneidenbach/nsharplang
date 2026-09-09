namespace NSharpLang.Cli.Daemon

import System.IO

class DaemonStartPlan {
    FileName: string
    Arguments: string

    constructor(fileName: string, arguments: string) {
        FileName = fileName
        Arguments = arguments
    }
}

class DaemonClientKernels {
    static func GetConnectionErrorMessage(messageText: string): string {
        return "[daemon] Connection error: " + messageText
    }

    static func GetExecutablePathMissingMessage(): string {
        return "Cannot determine executable path for daemon"
    }

    static func GetStartTimeoutMessage(): string {
        return "Daemon started but not responding within 5 seconds"
    }

    static func GetStartFailedWithReasonMessage(messageText: string): string {
        return "Failed to start daemon: " + messageText
    }

    static func ShouldDeleteStaleSocket(socketErrorCode: int, timedOutSocketErrorCode: int): bool {
        return socketErrorCode != timedOutSocketErrorCode
    }

    static func ShouldProbeCliProject(executablePath: string): bool {
        return executablePath.Contains("dotnet")
    }

    static func GetStartPlan(executablePath: string, projectRoot: string, cliProjectDirectory: string?): DaemonStartPlan {
        if ShouldProbeCliProject(executablePath) && cliProjectDirectory != null {
            cliDir := cliProjectDirectory ?? ""
            return new DaemonStartPlan("dotnet", "run --project " + QuoteArgument(cliDir) + " -- daemon run --project " + QuoteArgument(projectRoot))
        }

        return new DaemonStartPlan(executablePath, "daemon run --project " + QuoteArgument(projectRoot))
    }

    static func GetStartWaitAttemptCount(): int {
        return 50
    }

    static func GetStartWaitDelayMilliseconds(): int {
        return 100
    }

    static func GetCliProjectPath(candidateRoot: string): string {
        return Path.Combine(Path.Combine(Path.Combine(candidateRoot, "src"), "NSharpLang.Cli"), "Cli.csproj")
    }

    static func GetCliProjectDirectory(cliProjectPath: string): string? {
        return Path.GetDirectoryName(cliProjectPath)
    }

    static func QuoteArgument(value: string): string {
        return "\"" + value + "\""
    }
}

namespace NSharpLang.Cli.Daemon

public class DaemonClientKernels {
    public static func GetConnectionErrorMessage(messageText: string): string {
        return "[daemon] Connection error: " + messageText
    }

    public static func GetExecutablePathMissingMessage(): string {
        return "Cannot determine executable path for daemon"
    }

    public static func GetStartTimeoutMessage(): string {
        return "Daemon started but not responding within 5 seconds"
    }

    public static func GetStartFailedWithReasonMessage(messageText: string): string {
        return "Failed to start daemon: " + messageText
    }
}

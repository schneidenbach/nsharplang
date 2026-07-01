namespace NSharpLang.Cli.Daemon

public class DaemonServerMessageKernels {
    public static func GetUnknownMethodMessage(method: string): string {
        return "Unknown method: " + method
    }

    public static func GetFailedLoadProjectMessage(): string {
        return "Failed to load project"
    }

    public static func GetEmptyBatchPayloadMessage(): string {
        return "Batch request payload did not contain any requests."
    }

    public static func GetFileParameterRequiredMessage(): string {
        return "file parameter required"
    }

    public static func GetFileAndPosParametersRequiredMessage(): string {
        return "file and pos parameters required"
    }

    public static func GetDefinitionTargetRequiredMessage(): string {
        return "file+pos or name required"
    }

    public static func GetFileAndPosRequiredMessage(): string {
        return "file and pos required"
    }

    public static func GetSemanticReferencesUnavailableMessage(): string {
        return "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. No name-based or text-based fallback was used."
    }

    public static func GetListeningMessage(socketPath: string, processIdText: string): string {
        return "[daemon] Listening on " + socketPath + " (PID " + processIdText + ")"
    }

    public static func GetProjectMessage(projectRoot: string): string {
        return "[daemon] Project: " + projectRoot
    }

    public static func GetIdleTimeoutMessage(durationText: string): string {
        return "[daemon] Idle timeout: " + durationText
    }

    public static func GetIdleTimeoutShutdownMessage(durationText: string): string {
        return "[daemon] Idle timeout (" + durationText + "). Shutting down."
    }

    public static func GetServerErrorMessage(messageText: string): string {
        return "[daemon] Error: " + messageText
    }

    public static func GetClientErrorMessage(messageText: string): string {
        return "[daemon] Client error: " + messageText
    }

    public static func GetLoadingProjectMessage(): string {
        return "[daemon] Loading project..."
    }

    public static func GetProjectLoadedMessage(elapsedMillisecondsText: string, fileCountText: string): string {
        return "[daemon] Project loaded in " + elapsedMillisecondsText + "ms (" + fileCountText + " files)"
    }

    public static func GetProjectLoadFailedTraceMessage(messageText: string): string {
        return "[daemon] Failed to load project: " + messageText
    }

    public static func GetFileWatcherStartedMessage(): string {
        return "[daemon] File watcher started for *.nl, project.yml, .editorconfig"
    }

    public static func GetFileWatcherFailedMessage(messageText: string): string {
        return "[daemon] File watcher failed: " + messageText
    }

    public static func GetFileChangedMessage(fileName: string): string {
        return "[daemon] File changed: " + fileName + " — cache invalidated"
    }

    public static func GetShutdownCompleteMessage(): string {
        return "[daemon] Shutdown complete."
    }

    public static func GetMalformedRequestParamMessage(key: string, typeName: string, messageText: string): string {
        return "[daemon] Ignoring malformed request param '" + key + "' (expected " + typeName + "): " + messageText
    }
}

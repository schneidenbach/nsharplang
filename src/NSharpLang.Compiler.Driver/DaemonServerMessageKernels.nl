namespace NSharpLang.Cli.Daemon

class DaemonServerMessageKernels {
    static func GetUnknownMethodMessage(method: string): string {
        return "Unknown method: " + method
    }

    static func GetFailedLoadProjectMessage(): string {
        return "Failed to load project"
    }

    static func GetEmptyBatchPayloadMessage(): string {
        return "Batch request payload did not contain any requests."
    }

    static func GetFileParameterRequiredMessage(): string {
        return "file parameter required"
    }

    static func GetFileAndPosParametersRequiredMessage(): string {
        return "file and pos parameters required"
    }

    static func GetDefinitionTargetRequiredMessage(): string {
        return "file+pos or name required"
    }

    static func GetFileAndPosRequiredMessage(): string {
        return "file and pos required"
    }

    static func GetSemanticReferencesUnavailableMessage(): string {
        return "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. No name-based or text-based fallback was used."
    }

    static func GetListeningMessage(socketPath: string, processIdText: string): string {
        return "[daemon] Listening on " + socketPath + " (PID " + processIdText + ")"
    }

    static func GetProjectMessage(projectRoot: string): string {
        return "[daemon] Project: " + projectRoot
    }

    static func GetIdleTimeoutMessage(durationText: string): string {
        return "[daemon] Idle timeout: " + durationText
    }

    static func GetIdleTimeoutShutdownMessage(durationText: string): string {
        return "[daemon] Idle timeout (" + durationText + "). Shutting down."
    }

    static func GetServerErrorMessage(messageText: string): string {
        return "[daemon] Error: " + messageText
    }

    static func GetClientErrorMessage(messageText: string): string {
        return "[daemon] Client error: " + messageText
    }

    static func GetLoadingProjectMessage(): string {
        return "[daemon] Loading project..."
    }

    static func GetProjectLoadedMessage(elapsedMillisecondsText: string, fileCountText: string): string {
        return "[daemon] Project loaded in " + elapsedMillisecondsText + "ms (" + fileCountText + " files)"
    }

    static func GetProjectLoadFailedTraceMessage(messageText: string): string {
        return "[daemon] Failed to load project: " + messageText
    }

    static func GetFileWatcherStartedMessage(): string {
        return "[daemon] File watcher started for *.nl, project.yml, .editorconfig"
    }

    static func GetFileWatcherFailedMessage(messageText: string): string {
        return "[daemon] File watcher failed: " + messageText
    }

    static func GetFileChangedMessage(fileName: string): string {
        return "[daemon] File changed: " + fileName + " — cache invalidated"
    }

    static func GetShutdownCompleteMessage(): string {
        return "[daemon] Shutdown complete."
    }

    static func GetMalformedRequestParamMessage(key: string, typeName: string, messageText: string): string {
        return "[daemon] Ignoring malformed request param '" + key + "' (expected " + typeName + "): " + messageText
    }
}

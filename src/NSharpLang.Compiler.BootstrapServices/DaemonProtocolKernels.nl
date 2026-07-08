namespace NSharpLang.Cli.Daemon

import System.Collections.Generic
import System.IO
import System.Text.Json

public enum DaemonMethodKind {
    Unknown = 0,
    Ping = 1,
    Shutdown = 2,
    Status = 3,
    Batch = 4,
    Symbols = 5,
    Outline = 6,
    Diagnostics = 7,
    Type = 8,
    Definition = 9,
    References = 10,
    Completions = 11,
    Inspect = 12
}

public class DaemonParameterValidation {
    IsValid: bool
    QueryCommand: string
    Message: string

    constructor(isValid: bool, queryCommand: string, message: string) {
        IsValid = isValid
        QueryCommand = queryCommand
        Message = message
    }
}

public class DaemonProtocolKernels {
    public static func GetSocketDir(): string {
        return ".nlc"
    }

    public static func GetSocketName(): string {
        return "daemon.sock"
    }

    public static func GetIdleTimeoutMinutes(): int {
        return 30
    }

    public static func GetConnectionTimeoutMilliseconds(): int {
        return 5000
    }

    public static func GetPingTimeoutMilliseconds(): int {
        return 2000
    }

    public static func GetParseErrorCode(): int {
        return -32700
    }

    public static func GetInvalidRequestErrorCode(): int {
        return -32600
    }

    public static func GetMethodNotFoundErrorCode(): int {
        return -32601
    }

    public static func GetInvalidParamsErrorCode(): int {
        return -32602
    }

    public static func GetInternalErrorCode(): int {
        return -32603
    }

    public static func GetPingMethod(): string {
        return "daemon/ping"
    }

    public static func GetShutdownMethod(): string {
        return "daemon/shutdown"
    }

    public static func GetStatusMethod(): string {
        return "daemon/status"
    }

    public static func GetSymbolsMethod(): string {
        return "query/symbols"
    }

    public static func GetBatchMethod(): string {
        return "query/batch"
    }

    public static func GetOutlineMethod(): string {
        return "query/outline"
    }

    public static func GetDiagnosticsMethod(): string {
        return "query/diagnostics"
    }

    public static func GetTypeMethod(): string {
        return "query/type"
    }

    public static func GetDefinitionMethod(): string {
        return "query/definition"
    }

    public static func GetReferencesMethod(): string {
        return "query/references"
    }

    public static func GetCompletionsMethod(): string {
        return "query/completions"
    }

    public static func GetInspectMethod(): string {
        return "query/inspect"
    }

    public static func GetPidFileName(): string {
        return "daemon.pid"
    }

    public static func GetAlreadyRunningMessage(projectRoot: string): string {
        return "A daemon is already running for " + projectRoot + "."
    }

    public static func GetMalformedRequestJsonMessage(): string {
        return "Malformed daemon request JSON."
    }

    public static func GetMissingMethodMessage(): string {
        return "Daemon request must include a method."
    }

    public static func GetPongResultJson(): string {
        return "\"pong\""
    }

    public static func GetShutdownResultJson(): string {
        return "\"shutting down\""
    }

    public static func FormatUptime(hours: int, minutes: int, seconds: int): string {
        return hours.ToString() + "h " + minutes.ToString() + "m " + seconds.ToString() + "s"
    }

    public static func FormatIdleTimeoutMinutes(minutes: int): string {
        return minutes.ToString() + "m"
    }

    static func CreateCompactJsonOptions(): JsonSerializerOptions {
        return new JsonSerializerOptions()
    }

    public static func StatusResultJson(
        pid: int,
        uptime: string,
        projectRoot: string,
        cachedFiles: int,
        idleTimeout: string): string {
        payload := new Dictionary<string, object>()
        payload["pid"] = pid
        payload["uptime"] = uptime
        payload["projectRoot"] = projectRoot
        payload["cachedFiles"] = cachedFiles
        payload["idleTimeout"] = idleTimeout
        return JsonSerializer.Serialize(payload, CreateCompactJsonOptions())
    }

    public static func GetBatchDispatchAfterPrecheckMessage(): string {
        return "Batch queries should be handled before single-request dispatch."
    }

    public static func GetSocketPath(canonicalRoot: string, socketDir: string, socketName: string, tempPath: string, hashPrefix: string, useProjectLocalSocket: bool): string {
        dir := Path.Combine(canonicalRoot, socketDir)
        projectLocalPath := Path.Combine(dir, socketName)

        if useProjectLocalSocket {
            Directory.CreateDirectory(dir)
            return projectLocalPath
        }

        runtimeRoot := Path.Combine(tempPath, "nlc-daemon")
        runtimeDir := Path.Combine(runtimeRoot, hashPrefix)
        Directory.CreateDirectory(runtimeDir)
        return Path.Combine(runtimeDir, socketName)
    }

    public static func GetMethodKind(method: string): DaemonMethodKind {
        if method == GetPingMethod() {
            return DaemonMethodKind.Ping
        }

        if method == GetShutdownMethod() {
            return DaemonMethodKind.Shutdown
        }

        if method == GetStatusMethod() {
            return DaemonMethodKind.Status
        }

        if method == GetBatchMethod() {
            return DaemonMethodKind.Batch
        }

        if method == GetSymbolsMethod() {
            return DaemonMethodKind.Symbols
        }

        if method == GetOutlineMethod() {
            return DaemonMethodKind.Outline
        }

        if method == GetDiagnosticsMethod() {
            return DaemonMethodKind.Diagnostics
        }

        if method == GetTypeMethod() {
            return DaemonMethodKind.Type
        }

        if method == GetDefinitionMethod() {
            return DaemonMethodKind.Definition
        }

        if method == GetReferencesMethod() {
            return DaemonMethodKind.References
        }

        if method == GetCompletionsMethod() {
            return DaemonMethodKind.Completions
        }

        if method == GetInspectMethod() {
            return DaemonMethodKind.Inspect
        }

        return DaemonMethodKind.Unknown
    }

    public static func IsQueryMethod(kind: DaemonMethodKind): bool {
        return kind == DaemonMethodKind.Batch
            || kind == DaemonMethodKind.Symbols
            || kind == DaemonMethodKind.Outline
            || kind == DaemonMethodKind.Diagnostics
            || kind == DaemonMethodKind.Type
            || kind == DaemonMethodKind.Definition
            || kind == DaemonMethodKind.References
            || kind == DaemonMethodKind.Completions
            || kind == DaemonMethodKind.Inspect
    }

    public static func ValidateRequiredParameters(kind: DaemonMethodKind, hasFile: bool): DaemonParameterValidation {
        if kind == DaemonMethodKind.Outline && !hasFile {
            return InvalidParameters("outline", DaemonServerMessageKernels.GetFileParameterRequiredMessage())
        }

        if kind == DaemonMethodKind.Type && !hasFile {
            return InvalidParameters("type", DaemonServerMessageKernels.GetFileAndPosParametersRequiredMessage())
        }

        if kind == DaemonMethodKind.Definition && !hasFile {
            return InvalidParameters("definition", DaemonServerMessageKernels.GetDefinitionTargetRequiredMessage())
        }

        if kind == DaemonMethodKind.References && !hasFile {
            return InvalidParameters("references", DaemonServerMessageKernels.GetFileAndPosRequiredMessage())
        }

        if kind == DaemonMethodKind.Completions && !hasFile {
            return InvalidParameters("completions", DaemonServerMessageKernels.GetFileAndPosRequiredMessage())
        }

        if kind == DaemonMethodKind.Inspect && !hasFile {
            return InvalidParameters("inspect", DaemonServerMessageKernels.GetFileAndPosRequiredMessage())
        }

        return new DaemonParameterValidation(true, "", "")
    }

    static func InvalidParameters(queryCommand: string, message: string): DaemonParameterValidation {
        return new DaemonParameterValidation(false, queryCommand, message)
    }
}

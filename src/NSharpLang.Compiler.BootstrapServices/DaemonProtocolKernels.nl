namespace NSharpLang.Cli.Daemon

import System.IO

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
        if method == "daemon/ping" {
            return DaemonMethodKind.Ping
        }

        if method == "daemon/shutdown" {
            return DaemonMethodKind.Shutdown
        }

        if method == "daemon/status" {
            return DaemonMethodKind.Status
        }

        if method == "query/batch" {
            return DaemonMethodKind.Batch
        }

        if method == "query/symbols" {
            return DaemonMethodKind.Symbols
        }

        if method == "query/outline" {
            return DaemonMethodKind.Outline
        }

        if method == "query/diagnostics" {
            return DaemonMethodKind.Diagnostics
        }

        if method == "query/type" {
            return DaemonMethodKind.Type
        }

        if method == "query/definition" {
            return DaemonMethodKind.Definition
        }

        if method == "query/references" {
            return DaemonMethodKind.References
        }

        if method == "query/completions" {
            return DaemonMethodKind.Completions
        }

        if method == "query/inspect" {
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

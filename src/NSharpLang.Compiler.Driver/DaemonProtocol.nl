namespace NSharpLang.Cli.Daemon

import System
import System.IO
import System.Security.Cryptography
import System.Text
import System.Text.Json
import System.Text.Json.Serialization
import NSharpLang.Compiler

// The daemon's JSON-RPC 2.0 wire, as types the serializer reads.
//
// The three envelope DTOs below carry only JSON-RPC 2.0's own member names — jsonrpc, id, method,
// params, result, error, code, message, data — which the specification fixes and N# does not
// choose, so each one is spelled once, here, as a `[JsonPropertyName]` on the property that holds
// it. The daemon/status payload, whose five member names ARE this product's own vocabulary, is
// composed by `DaemonProtocolKernels.StatusResultJson` and has no DTO at all.
//
// Every constant these types and their callers use — the protocol version, the five error codes,
// the twelve method names, the socket names and the three timeouts — belongs to
// `DaemonProtocolKernels`; `DaemonConstants` is the reader for them, not a second owner.
class DaemonRequest {
    jsonRpcValue: string
    idValue: int
    methodValue: string
    paramsValue: JsonElement?

    constructor() {
        jsonRpcValue = DaemonProtocolKernels.GetJsonRpcVersion()
        idValue = 0
        methodValue = ""
        paramsValue = null
    }

    [JsonPropertyName("jsonrpc")]
    JsonRpc: string {
        get {
            return jsonRpcValue
        }
        set {
            jsonRpcValue = value
        }
    }

    [JsonPropertyName("id")]
    Id: int {
        get {
            return idValue
        }
        set {
            idValue = value
        }
    }

    [JsonPropertyName("method")]
    Method: string {
        get {
            return methodValue
        }
        set {
            methodValue = value
        }
    }

    [JsonPropertyName("params")]
    Params: JsonElement? {
        get {
            return paramsValue
        }
        set {
            paramsValue = value
        }
    }
}

class DaemonResponse {
    jsonRpcValue: string
    idValue: int
    resultValue: string?
    errorValue: DaemonError?

    constructor() {
        jsonRpcValue = DaemonProtocolKernels.GetJsonRpcVersion()
        idValue = 0
        resultValue = null
        errorValue = null
    }

    [JsonPropertyName("jsonrpc")]
    JsonRpc: string {
        get {
            return jsonRpcValue
        }
        set {
            jsonRpcValue = value
        }
    }

    [JsonPropertyName("id")]
    Id: int {
        get {
            return idValue
        }
        set {
            idValue = value
        }
    }

    [JsonPropertyName("result")]
    Result: string? {
        get {
            return resultValue
        }
        set {
            resultValue = value
        }
    }

    [JsonPropertyName("error")]
    Error: DaemonError? {
        get {
            return errorValue
        }
        set {
            errorValue = value
        }
    }
}

class DaemonError {
    codeValue: int
    messageValue: string
    dataValue: object?

    constructor() {
        codeValue = 0
        messageValue = ""
        dataValue = null
    }

    [JsonPropertyName("code")]
    Code: int {
        get {
            return codeValue
        }
        set {
            codeValue = value
        }
    }

    [JsonPropertyName("message")]
    Message: string {
        get {
            return messageValue
        }
        set {
            messageValue = value
        }
    }

    [JsonPropertyName("data")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    Data: object? {
        get {
            return dataValue
        }
        set {
            dataValue = value
        }
    }
}

class DaemonConstants {
    static SocketDir: string => DaemonProtocolKernels.GetSocketDir()
    static SocketName: string => DaemonProtocolKernels.GetSocketName()
    static IdleTimeoutMinutes: int => DaemonProtocolKernels.GetIdleTimeoutMinutes()
    static ConnectionTimeoutMs: int => DaemonProtocolKernels.GetConnectionTimeoutMilliseconds()
    static PingTimeoutMs: int => DaemonProtocolKernels.GetPingTimeoutMilliseconds()

    static ErrorParse: int => DaemonProtocolKernels.GetParseErrorCode()
    static ErrorInvalidRequest: int => DaemonProtocolKernels.GetInvalidRequestErrorCode()
    static ErrorMethodNotFound: int => DaemonProtocolKernels.GetMethodNotFoundErrorCode()
    static ErrorInvalidParams: int => DaemonProtocolKernels.GetInvalidParamsErrorCode()
    static ErrorInternal: int => DaemonProtocolKernels.GetInternalErrorCode()

    // One socket per project root, named by the first 16 hex digits of the canonical root's
    // SHA-256 — the path budget is small and the whole hash does not fit.
    static func GetSocketPath(projectRoot: string): string {
        canonicalRoot := DaemonProtocolKernels.GetCanonicalProjectRoot(projectRoot)
        using digest := SHA256.Create()
        rootBytes := Encoding.UTF8.GetBytes(canonicalRoot)
        hash := digest.ComputeHash(rootBytes, 0, rootBytes.Length)
        hashPrefix := Convert.ToHexString(hash).ToLowerInvariant().Substring(0, 16)
        return DaemonProtocolKernels.GetSocketPathForProject(canonicalRoot, Path.GetTempPath(), hashPrefix)
    }

    static MethodPing: string => DaemonProtocolKernels.GetPingMethod()
    static MethodShutdown: string => DaemonProtocolKernels.GetShutdownMethod()
    static MethodStatus: string => DaemonProtocolKernels.GetStatusMethod()
    static MethodSymbols: string => DaemonProtocolKernels.GetSymbolsMethod()
    static MethodBatch: string => DaemonProtocolKernels.GetBatchMethod()
    static MethodOutline: string => DaemonProtocolKernels.GetOutlineMethod()
    static MethodDiagnostics: string => DaemonProtocolKernels.GetDiagnosticsMethod()
    static MethodType: string => DaemonProtocolKernels.GetTypeMethod()
    static MethodDefinition: string => DaemonProtocolKernels.GetDefinitionMethod()
    static MethodReferences: string => DaemonProtocolKernels.GetReferencesMethod()
    static MethodCompletions: string => DaemonProtocolKernels.GetCompletionsMethod()
    static MethodInspect: string => DaemonProtocolKernels.GetInspectMethod()
}

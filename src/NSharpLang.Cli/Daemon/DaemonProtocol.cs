using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NSharpLang.Cli.Daemon;

/// <summary>
/// JSON-RPC 2.0 request message for daemon communication.
/// </summary>
public class DaemonRequest
{
    [JsonPropertyName("jsonrpc")]
    public string JsonRpc { get; set; } = "2.0";

    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("method")]
    public string Method { get; set; } = "";

    [JsonPropertyName("params")]
    public JsonElement? Params { get; set; }
}

/// <summary>
/// JSON-RPC 2.0 response message from daemon.
/// </summary>
public class DaemonResponse
{
    [JsonPropertyName("jsonrpc")]
    public string JsonRpc { get; set; } = "2.0";

    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("result")]
    public string? Result { get; set; }

    [JsonPropertyName("error")]
    public DaemonError? Error { get; set; }
}

public class DaemonError
{
    [JsonPropertyName("code")]
    public int Code { get; set; }

    [JsonPropertyName("message")]
    public string Message { get; set; } = "";

    [JsonPropertyName("data")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public object? Data { get; set; }
}

/// <summary>
/// Status info returned by daemon/status.
/// </summary>
public class DaemonStatus
{
    [JsonPropertyName("pid")]
    public int Pid { get; set; }

    [JsonPropertyName("uptime")]
    public string Uptime { get; set; } = "";

    [JsonPropertyName("projectRoot")]
    public string ProjectRoot { get; set; } = "";

    [JsonPropertyName("cachedFiles")]
    public int CachedFiles { get; set; }

    [JsonPropertyName("idleTimeout")]
    public string IdleTimeout { get; set; } = "30m";
}

/// <summary>
/// Wire DTOs stay in C# until N# emits JSON attributes; constants are owned by DaemonProtocolKernels.nl.
/// </summary>
public static class DaemonConstants
{
    public static string SocketDir => DaemonProtocolKernels.GetSocketDir();
    public static string SocketName => DaemonProtocolKernels.GetSocketName();
    public static int IdleTimeoutMinutes => DaemonProtocolKernels.GetIdleTimeoutMinutes();
    public static int ConnectionTimeoutMs => DaemonProtocolKernels.GetConnectionTimeoutMilliseconds();
    public static int PingTimeoutMs => DaemonProtocolKernels.GetPingTimeoutMilliseconds();

    public static int ErrorParse => DaemonProtocolKernels.GetParseErrorCode();
    public static int ErrorInvalidRequest => DaemonProtocolKernels.GetInvalidRequestErrorCode();
    public static int ErrorMethodNotFound => DaemonProtocolKernels.GetMethodNotFoundErrorCode();
    public static int ErrorInvalidParams => DaemonProtocolKernels.GetInvalidParamsErrorCode();
    public static int ErrorInternal => DaemonProtocolKernels.GetInternalErrorCode();

    public static string GetSocketPath(string projectRoot)
    {
        var canonicalRoot = Path.GetFullPath(projectRoot);
        var projectLocalPath = Path.Combine(Path.Combine(canonicalRoot, SocketDir), SocketName);
        var useProjectLocalSocket = DaemonProtocolKernels.ShouldUseProjectLocalSocket(projectLocalPath);
        var hashPrefix = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonicalRoot))).ToLowerInvariant()[..16];
        return DaemonProtocolKernels.GetSocketPath(
            canonicalRoot,
            SocketDir,
            SocketName,
            Path.GetTempPath(),
            hashPrefix,
            useProjectLocalSocket);
    }

    public static string MethodPing => DaemonProtocolKernels.GetPingMethod();
    public static string MethodShutdown => DaemonProtocolKernels.GetShutdownMethod();
    public static string MethodStatus => DaemonProtocolKernels.GetStatusMethod();
    public static string MethodSymbols => DaemonProtocolKernels.GetSymbolsMethod();
    public static string MethodBatch => DaemonProtocolKernels.GetBatchMethod();
    public static string MethodOutline => DaemonProtocolKernels.GetOutlineMethod();
    public static string MethodDiagnostics => DaemonProtocolKernels.GetDiagnosticsMethod();
    public static string MethodType => DaemonProtocolKernels.GetTypeMethod();
    public static string MethodDefinition => DaemonProtocolKernels.GetDefinitionMethod();
    public static string MethodReferences => DaemonProtocolKernels.GetReferencesMethod();
    public static string MethodCompletions => DaemonProtocolKernels.GetCompletionsMethod();
    public static string MethodInspect => DaemonProtocolKernels.GetInspectMethod();
}

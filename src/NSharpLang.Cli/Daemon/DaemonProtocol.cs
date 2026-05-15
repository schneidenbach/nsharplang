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
/// Constants for daemon communication.
/// </summary>
public static class DaemonConstants
{
    public const string SocketDir = ".nlc";
    public const string SocketName = "daemon.sock";
    public const int IdleTimeoutMinutes = 30;
    public const int ConnectionTimeoutMs = 5000;
    public const int PingTimeoutMs = 2000;

    public const int ErrorParse = -32700;
    public const int ErrorInvalidRequest = -32600;
    public const int ErrorMethodNotFound = -32601;
    public const int ErrorInvalidParams = -32602;
    public const int ErrorInternal = -32603;

    public static string GetSocketPath(string projectRoot)
    {
        var canonicalRoot = Path.GetFullPath(projectRoot);
        var dir = Path.Combine(canonicalRoot, SocketDir);
        var projectLocalPath = Path.Combine(dir, SocketName);

        if (Encoding.UTF8.GetByteCount(projectLocalPath) <= 100)
        {
            Directory.CreateDirectory(dir);
            return projectLocalPath;
        }

        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonicalRoot))).ToLowerInvariant()[..16];
        var runtimeDir = Path.Combine(Path.GetTempPath(), "nlc-daemon", hash);
        Directory.CreateDirectory(runtimeDir);
        return Path.Combine(runtimeDir, SocketName);
    }

    // JSON-RPC method names
    public const string MethodPing = "daemon/ping";
    public const string MethodShutdown = "daemon/shutdown";
    public const string MethodStatus = "daemon/status";
    public const string MethodSymbols = "query/symbols";
    public const string MethodBatch = "query/batch";
    public const string MethodOutline = "query/outline";
    public const string MethodDiagnostics = "query/diagnostics";
    public const string MethodType = "query/type";
    public const string MethodDefinition = "query/definition";
    public const string MethodReferences = "query/references";
    public const string MethodCompletions = "query/completions";
    public const string MethodInspect = "query/inspect";
}

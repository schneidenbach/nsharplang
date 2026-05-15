using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using NSharpLang.Cli;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Daemon;

/// <summary>
/// Background daemon server that caches project analysis and serves
/// nlc query requests via Unix domain socket.
///
/// Lifecycle:
/// 1. Started by first `nlc query` call or `nlc daemon start`
/// 2. Listens on Unix socket at {projectRoot}/.nlc/daemon.sock
/// 3. Caches ProjectSnapshot after first request
/// 4. FileSystemWatcher invalidates cache on .nl file changes
/// 5. Auto-exits after 30 minutes idle
/// </summary>
public class DaemonServer
{
    private static readonly JsonSerializerOptions DaemonJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    private readonly string _projectRoot;
    private readonly string _socketPath;
    private readonly CodeIntelligenceService _service = new();
    private readonly CompletionEngine _completionEngine = new();
    private ProjectSnapshot? _snapshot;
    private DateTime _lastActivity;
    private FileSystemWatcher? _fileWatcher;
    private volatile bool _cacheInvalid = true;
    private volatile bool _running;
    private readonly TimeSpan _idleTimeout;
    private readonly TimeSpan _idleCheckInterval;

    public DaemonServer(string projectRoot)
        : this(projectRoot, TimeSpan.FromMinutes(DaemonConstants.IdleTimeoutMinutes), TimeSpan.FromMinutes(1))
    {
    }

    public DaemonServer(string projectRoot, TimeSpan idleTimeout, TimeSpan idleCheckInterval)
    {
        _projectRoot = projectRoot;
        _socketPath = DaemonConstants.GetSocketPath(projectRoot);
        _lastActivity = DateTime.UtcNow;
        _idleTimeout = idleTimeout;
        _idleCheckInterval = idleCheckInterval;
    }

    /// <summary>
    /// Start the daemon server. Blocks until shutdown.
    /// </summary>
    public void Run()
    {
        var pidPath = Path.Combine(Path.GetDirectoryName(_socketPath)!, "daemon.pid");
        var ownsSocket = false;

        if (File.Exists(_socketPath))
        {
            if (DaemonClient.IsRunning(_projectRoot))
            {
                throw new InvalidOperationException($"A daemon is already running for {_projectRoot}.");
            }

            File.Delete(_socketPath);
        }

        using var listener = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);

        try
        {
            listener.Bind(new UnixDomainSocketEndPoint(_socketPath));
            ownsSocket = true;
            listener.Listen(5);

            _running = true;

            // Start file watcher only after this process owns the socket.
            StartFileWatcher();

            // Write PID file only after bind/listen succeeds.
            File.WriteAllText(pidPath, Environment.ProcessId.ToString());

            Console.Error.WriteLine($"[daemon] Listening on {_socketPath} (PID {Environment.ProcessId})");
            Console.Error.WriteLine($"[daemon] Project: {_projectRoot}");
            Console.Error.WriteLine($"[daemon] Idle timeout: {FormatDuration(_idleTimeout)}");

            // Idle timeout thread
            var idleThread = new Thread(() =>
            {
                while (_running)
                {
                    Thread.Sleep(_idleCheckInterval);
                    var idle = DateTime.UtcNow - _lastActivity;
                    if (idle >= _idleTimeout)
                    {
                        Console.Error.WriteLine($"[daemon] Idle timeout ({FormatDuration(_idleTimeout)}). Shutting down.");
                        _running = false;
                        // Connect to self to unblock Accept()
                        try
                        {
                            using var kick = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
                            kick.Connect(new UnixDomainSocketEndPoint(_socketPath));
                            kick.Close();
                        }
                        catch { }
                    }
                }
            })
            { IsBackground = true };
            idleThread.Start();

            while (_running)
            {
                try
                {
                    using var client = listener.Accept();
                    _lastActivity = DateTime.UtcNow;

                    if (!_running) break;

                    HandleClient(client);
                }
                catch (SocketException) when (!_running)
                {
                    break;
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"[daemon] Error: {ex.Message}");
                }
            }
        }
        finally
        {
            _running = false;
            if (ownsSocket)
            {
                Cleanup(pidPath);
            }
            else
            {
                _fileWatcher?.Dispose();
            }
        }
    }

    private void HandleClient(Socket client)
    {
        try
        {
            // Read request. CLI clients half-close after sending; direct clients may not,
            // so also stop after a short quiet period once at least one chunk arrived.
            using var requestStream = new MemoryStream();
            var buffer = new byte[8192];
            client.ReceiveTimeout = 500;

            while (true)
            {
                int received;
                try
                {
                    received = client.Receive(buffer);
                }
                catch (SocketException ex) when (ex.SocketErrorCode == SocketError.TimedOut && requestStream.Length > 0)
                {
                    break;
                }

                if (received == 0) break;
                requestStream.Write(buffer, 0, received);
            }

            if (requestStream.Length == 0) return;

            DaemonRequest? request;
            try
            {
                var requestJson = Encoding.UTF8.GetString(requestStream.ToArray());
                request = JsonSerializer.Deserialize<DaemonRequest>(requestJson, DaemonJsonOptions);
            }
            catch (JsonException ex)
            {
                SendResponse(client, Error(0, DaemonConstants.ErrorParse, "Malformed daemon request JSON.", new { ex.Path, ex.LineNumber, ex.BytePositionInLine }));
                return;
            }

            if (request == null || string.IsNullOrWhiteSpace(request.Method))
            {
                SendResponse(client, Error(request?.Id ?? 0, DaemonConstants.ErrorInvalidRequest, "Daemon request must include a method."));
                return;
            }

            // Process request
            var response = ProcessRequest(request);

            // Send response
            SendResponse(client, response);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[daemon] Client error: {ex.Message}");
        }
    }

    private DaemonResponse ProcessRequest(DaemonRequest request)
    {
        try
        {
            // Daemon control methods
            switch (request.Method)
            {
                case DaemonConstants.MethodPing:
                    return Ok(request.Id, "\"pong\"");

                case DaemonConstants.MethodShutdown:
                    _running = false;
                    return Ok(request.Id, "\"shutting down\"");

                case DaemonConstants.MethodStatus:
                    var uptime = DateTime.UtcNow - Process.GetCurrentProcess().StartTime.ToUniversalTime();
                    var status = new DaemonStatus
                    {
                        Pid = Environment.ProcessId,
                        Uptime = $"{uptime.Hours}h {uptime.Minutes}m {uptime.Seconds}s",
                        ProjectRoot = _projectRoot,
                        CachedFiles = _snapshot?.CompilationUnits.Count ?? 0,
                        IdleTimeout = $"{DaemonConstants.IdleTimeoutMinutes}m"
                    };
                    return Ok(request.Id, JsonSerializer.Serialize(status));
            }

            if (!IsQueryMethod(request.Method))
            {
                return Error(request.Id, DaemonConstants.ErrorMethodNotFound, $"Unknown method: {request.Method}");
            }

            // Ensure snapshot is loaded
            EnsureSnapshot();

            if (_snapshot == null)
            {
                return Error(request.Id, DaemonConstants.ErrorInternal, "Failed to load project");
            }

            if (request.Method == DaemonConstants.MethodBatch)
            {
                var requests = GetParam<List<BatchQueryRequest>>(request.Params, "requests");
                if (requests == null || requests.Count == 0)
                {
                    return Ok(request.Id, OutputFormatter.ErrorToJson(
                        "batch",
                        "Batch request payload did not contain any requests.",
                        _projectRoot,
                        "emptyBatch"));
                }

                var execution = BatchQueryRunner.Execute(
                    requests,
                    _projectRoot,
                    () => _snapshot!,
                    _service,
                    _completionEngine);

                return Ok(request.Id, execution.Json);
            }

            // Extract params
            var file = GetParam<string>(request.Params, "file");
            var posStr = GetParam<string>(request.Params, "pos");
            var name = GetParam<string>(request.Params, "name");
            var kind = GetParam<string>(request.Params, "kind");
            var severity = GetParam<string>(request.Params, "severity");
            var includeKeywords = GetParam<bool>(request.Params, "includeKeywords");
            var summary = GetParam<bool>(request.Params, "summary");
            var compact = GetParam<bool>(request.Params, "compact");
            var clusters = GetParam<bool>(request.Params, "clusters");

            int line = 0, col = 0;
            if (posStr != null)
            {
                var parts = posStr.Split(':');
                if (parts.Length == 2)
                {
                    int.TryParse(parts[0], out line);
                    int.TryParse(parts[1], out col);
                }
            }

            // Query methods
            string result = request.Method switch
            {
                DaemonConstants.MethodBatch => throw new InvalidOperationException("Batch queries should be handled before single-request dispatch."),
                DaemonConstants.MethodSymbols => HandleSymbols(file, kind),
                DaemonConstants.MethodOutline => HandleOutline(file),
                DaemonConstants.MethodDiagnostics => HandleDiagnostics(file, severity, clusters),
                DaemonConstants.MethodType => HandleType(file, line, col),
                DaemonConstants.MethodDefinition => HandleDefinition(file, line, col, name),
                DaemonConstants.MethodReferences => HandleReferences(file, line, col),
                DaemonConstants.MethodCompletions => HandleCompletions(file, line, col, includeKeywords),
                DaemonConstants.MethodInspect => HandleInspect(file, line, col, includeKeywords, summary || compact),
                _ => throw new DaemonProtocolException(DaemonConstants.ErrorMethodNotFound, $"Unknown method: {request.Method}")
            };

            return Ok(request.Id, result);
        }
        catch (DaemonProtocolException ex)
        {
            return Error(request.Id, ex.Code, ex.Message);
        }
        catch (Exception ex)
        {
            return Error(request.Id, DaemonConstants.ErrorInternal, ex.Message);
        }
    }

    // ── Query Handlers ──────────────────────────────────────────────────

    private string HandleSymbols(string? file, string? kind)
    {
        NSharpLang.Compiler.CodeIntelligence.SymbolKind? kindFilter = null;
        if (kind != null && Enum.TryParse<NSharpLang.Compiler.CodeIntelligence.SymbolKind>(kind, true, out var parsed))
            kindFilter = parsed;

        var results = _service.GetSymbols(_snapshot!, file, kindFilter);
        return OutputFormatter.SymbolsToJson(results, _snapshot!.ProjectRoot);
    }

    private string HandleOutline(string? file)
    {
        if (file == null) return OutputFormatter.ErrorToJson("outline", "file parameter required");
        var result = _service.GetOutline(_snapshot!, file);
        return OutputFormatter.OutlineToJson(result);
    }

    private string HandleDiagnostics(string? file, string? severity, bool clusters)
    {
        var results = _service.GetDiagnostics(_snapshot!, file);
        if (severity != null)
            results = results.Where(d => d.Severity.Equals(severity, StringComparison.OrdinalIgnoreCase)).ToList();
        return clusters
            ? OutputFormatter.DiagnosticClustersToJson(results, _snapshot!.ProjectRoot)
            : OutputFormatter.DiagnosticsToJson(results, _snapshot!.ProjectRoot);
    }

    private string HandleType(string? file, int line, int col)
    {
        if (file == null) return OutputFormatter.ErrorToJson("type", "file and pos parameters required");
        var result = _service.GetTypeAtPosition(_snapshot!, file, line, col);
        if (result == null)
        {
            return OutputFormatter.ErrorToJson(
                "type",
                $"No symbol found at {file}:{line}:{col}",
                _snapshot!.ProjectRoot,
                "noSymbol",
                new
                {
                    file,
                    position = new { line, column = col }
                });
        }

        return OutputFormatter.TypeToJson(result, file, line, col);
    }

    private string HandleDefinition(string? file, int line, int col, string? name)
    {
        if (name != null)
        {
            var results = _service.FindDefinitionByName(_snapshot!, name);
            return OutputFormatter.DefinitionSearchToJson(name, results);
        }
        if (file == null) return OutputFormatter.ErrorToJson("definition", "file+pos or name required");
        var result = _service.FindDefinition(_snapshot!, file, line, col);
        if (result == null)
        {
            return OutputFormatter.ErrorToJson(
                "definition",
                $"No symbol found at {file}:{line}:{col}",
                _snapshot!.ProjectRoot,
                "noSymbol",
                new
                {
                    file,
                    position = new { line, column = col }
                });
        }

        return OutputFormatter.DefinitionToJson(result);
    }

    private string HandleReferences(string? file, int line, int col)
    {
        if (file == null) return OutputFormatter.ErrorToJson("references", "file and pos required");

        // Resolve symbol metadata (same as CLI path — don't hardcode placeholders)
        var definition = _service.FindDefinition(_snapshot!, file, line, col);
        if (definition == null)
        {
            return OutputFormatter.ErrorToJson(
                "references",
                $"No symbol found at {file}:{line}:{col}",
                _snapshot!.ProjectRoot,
                "noSymbol",
                new
                {
                    file,
                    position = new { line, column = col }
                });
        }

        var symbolName = definition.Name;
        var symbolKind = definition.Kind;
        var definedAt = new LocationResult(definition.File, definition.Line, definition.Column);

        var results = _service.FindReferences(_snapshot!, file, line, col);
        return OutputFormatter.ReferencesToJson(symbolName, symbolKind, definedAt, results);
    }

    private string HandleCompletions(string? file, int line, int col, bool includeKeywords)
    {
        if (file == null) return OutputFormatter.ErrorToJson("completions", "file and pos required");
        var result = _completionEngine.GetCompletions(_snapshot!, file, line, col, includeKeywords);
        return OutputFormatter.CompletionsToJson(result, file, line, col);
    }

    private string HandleInspect(string? file, int line, int col, bool includeKeywords, bool summary)
    {
        if (file == null) return OutputFormatter.ErrorToJson("inspect", "file and pos required");

        var type = _service.GetTypeAtPosition(_snapshot!, file, line, col);
        var definition = _service.FindDefinition(_snapshot!, file, line, col);
        var references = definition != null
            ? _service.FindReferences(_snapshot!, file, line, col)
            : new List<ReferenceResult>();
        var completions = _completionEngine.GetCompletions(_snapshot!, file, line, col, includeKeywords);

        if (type == null && definition == null && references.Count == 0)
        {
            return OutputFormatter.ErrorToJson(
                "inspect",
                $"No symbol found at {file}:{line}:{col}",
                _snapshot!.ProjectRoot,
                "noSymbol",
                new
                {
                    file,
                    position = new { line, column = col }
                });
        }

        InspectSymbolResult? symbol = null;
        if (definition != null)
        {
            symbol = new InspectSymbolResult(
                definition.Name,
                definition.Kind,
                new LocationResult(definition.File, definition.Line, definition.Column));
        }
        else if (type != null)
        {
            symbol = new InspectSymbolResult(type.Name, type.Kind, type.Definition);
        }

        var inspect = new InspectResult(
            symbol,
            type,
            definition,
            new InspectReferencesResult(
                references.Count,
                references.Count(r => r.IsDefinition),
                references.ToArray()),
            completions);

        return summary
            ? OutputFormatter.InspectSummaryToJson(inspect, file, line, col)
            : OutputFormatter.InspectToJson(inspect, file, line, col);
    }

    // ── Snapshot Management ─────────────────────────────────────────────

    private void EnsureSnapshot()
    {
        if (_snapshot != null && !_cacheInvalid) return;

        Console.Error.WriteLine("[daemon] Loading project...");
        var sw = Stopwatch.StartNew();

        try
        {
            _snapshot = _service.LoadProject(_projectRoot);
            _cacheInvalid = false;
            sw.Stop();
            Console.Error.WriteLine($"[daemon] Project loaded in {sw.ElapsedMilliseconds}ms ({_snapshot.CompilationUnits.Count} files)");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[daemon] Failed to load project: {ex.Message}");
            _snapshot = null;
        }
    }

    // ── File Watching ───────────────────────────────────────────────────

    private void StartFileWatcher()
    {
        try
        {
            _fileWatcher = new FileSystemWatcher(_projectRoot)
            {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.CreationTime
            };

            _fileWatcher.Changed += OnFileChanged;
            _fileWatcher.Created += OnFileChanged;
            _fileWatcher.Deleted += OnFileChanged;
            _fileWatcher.Renamed += (_, e) => OnFileChanged(null, e);

            _fileWatcher.EnableRaisingEvents = true;
            Console.Error.WriteLine("[daemon] File watcher started for *.nl, project.yml, .editorconfig");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[daemon] File watcher failed: {ex.Message}");
        }
    }

    private void OnFileChanged(object? sender, FileSystemEventArgs e)
    {
        // Skip .nlc directory changes
        if (e.FullPath.Contains($"{Path.DirectorySeparatorChar}.nlc{Path.DirectorySeparatorChar}")) return;

        var fileName = Path.GetFileName(e.FullPath);
        var extension = Path.GetExtension(e.FullPath);

        // Only invalidate on relevant files: .nl sources, project.yml, .editorconfig
        if (!extension.Equals(".nl", StringComparison.OrdinalIgnoreCase) &&
            !fileName.Equals("project.yml", StringComparison.OrdinalIgnoreCase) &&
            !fileName.Equals(".editorconfig", StringComparison.OrdinalIgnoreCase))
            return;

        Console.Error.WriteLine($"[daemon] File changed: {fileName} — cache invalidated");
        _cacheInvalid = true;
    }

    // ── Cleanup ─────────────────────────────────────────────────────────

    private void Cleanup(string pidPath)
    {
        _fileWatcher?.Dispose();
        try { File.Delete(_socketPath); } catch { }
        try { File.Delete(pidPath); } catch { }
        Console.Error.WriteLine("[daemon] Shutdown complete.");
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private static DaemonResponse Ok(int id, string result) => new()
    {
        Id = id,
        Result = result
    };

    private static DaemonResponse Error(int id, int code, string message, object? data = null) => new()
    {
        Id = id,
        Error = new DaemonError { Code = code, Message = message, Data = data }
    };

    private static void SendResponse(Socket socket, DaemonResponse response)
    {
        var responseJson = JsonSerializer.Serialize(response, DaemonJsonOptions);
        var responseBytes = Encoding.UTF8.GetBytes(responseJson);
        SendAll(socket, responseBytes);
    }

    private static string FormatDuration(TimeSpan duration)
    {
        if (duration.TotalMinutes >= 1)
            return $"{duration.TotalMinutes:0.#}m";
        if (duration.TotalSeconds >= 1)
            return $"{duration.TotalSeconds:0.#}s";
        return $"{duration.TotalMilliseconds:0}ms";
    }

    private sealed class DaemonProtocolException : Exception
    {
        public DaemonProtocolException(int code, string message) : base(message)
        {
            Code = code;
        }

        public int Code { get; }
    }

    private static bool IsQueryMethod(string method)
    {
        return method is DaemonConstants.MethodBatch
            or DaemonConstants.MethodSymbols
            or DaemonConstants.MethodOutline
            or DaemonConstants.MethodDiagnostics
            or DaemonConstants.MethodType
            or DaemonConstants.MethodDefinition
            or DaemonConstants.MethodReferences
            or DaemonConstants.MethodCompletions
            or DaemonConstants.MethodInspect;
    }

    private static T? GetParam<T>(JsonElement? paramsElement, string key)
    {
        if (paramsElement == null || paramsElement.Value.ValueKind != JsonValueKind.Object) return default;
        if (paramsElement.Value.TryGetProperty(key, out var prop))
        {
            try { return JsonSerializer.Deserialize<T>(prop.GetRawText(), DaemonJsonOptions); }
            catch { return default; }
        }
        return default;
    }

    private static void SendAll(Socket socket, byte[] bytes)
    {
        var sent = 0;
        while (sent < bytes.Length)
        {
            sent += socket.Send(bytes, sent, bytes.Length - sent, SocketFlags.None);
        }
    }
}

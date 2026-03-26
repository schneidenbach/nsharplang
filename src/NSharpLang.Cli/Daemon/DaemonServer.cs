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
    private readonly string _projectRoot;
    private readonly string _socketPath;
    private readonly CodeIntelligenceService _service = new();
    private readonly CompletionEngine _completionEngine = new();
    private ProjectSnapshot? _snapshot;
    private DateTime _lastActivity;
    private FileSystemWatcher? _fileWatcher;
    private bool _cacheInvalid = true;
    private bool _running;

    public DaemonServer(string projectRoot)
    {
        _projectRoot = projectRoot;
        _socketPath = DaemonConstants.GetSocketPath(projectRoot);
        _lastActivity = DateTime.UtcNow;
    }

    /// <summary>
    /// Start the daemon server. Blocks until shutdown.
    /// </summary>
    public void Run()
    {
        // Clean up stale socket
        if (File.Exists(_socketPath))
        {
            File.Delete(_socketPath);
        }

        _running = true;

        // Start file watcher
        StartFileWatcher();

        // Write PID file
        var pidPath = Path.Combine(Path.GetDirectoryName(_socketPath)!, "daemon.pid");
        File.WriteAllText(pidPath, Environment.ProcessId.ToString());

        using var listener = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
        listener.Bind(new UnixDomainSocketEndPoint(_socketPath));
        listener.Listen(5);

        Console.Error.WriteLine($"[daemon] Listening on {_socketPath} (PID {Environment.ProcessId})");
        Console.Error.WriteLine($"[daemon] Project: {_projectRoot}");
        Console.Error.WriteLine($"[daemon] Idle timeout: {DaemonConstants.IdleTimeoutMinutes} minutes");

        // Idle timeout thread
        var idleThread = new Thread(() =>
        {
            while (_running)
            {
                Thread.Sleep(60_000); // Check every minute
                var idle = DateTime.UtcNow - _lastActivity;
                if (idle.TotalMinutes >= DaemonConstants.IdleTimeoutMinutes)
                {
                    Console.Error.WriteLine($"[daemon] Idle timeout ({DaemonConstants.IdleTimeoutMinutes}m). Shutting down.");
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

        // Cleanup
        Cleanup(pidPath);
    }

    private void HandleClient(Socket client)
    {
        try
        {
            // Read request
            var buffer = new byte[65536];
            var received = client.Receive(buffer);
            if (received == 0) return;

            var requestJson = Encoding.UTF8.GetString(buffer, 0, received);
            var request = JsonSerializer.Deserialize<DaemonRequest>(requestJson);
            if (request == null) return;

            // Process request
            var response = ProcessRequest(request);

            // Send response
            var responseJson = JsonSerializer.Serialize(response);
            var responseBytes = Encoding.UTF8.GetBytes(responseJson);
            client.Send(responseBytes);
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

            // Ensure snapshot is loaded
            EnsureSnapshot();

            if (_snapshot == null)
            {
                return Error(request.Id, -1, "Failed to load project");
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
                DaemonConstants.MethodDiagnostics => HandleDiagnostics(file, severity),
                DaemonConstants.MethodType => HandleType(file, line, col),
                DaemonConstants.MethodDefinition => HandleDefinition(file, line, col, name),
                DaemonConstants.MethodReferences => HandleReferences(file, line, col),
                DaemonConstants.MethodCompletions => HandleCompletions(file, line, col, includeKeywords),
                DaemonConstants.MethodInspect => HandleInspect(file, line, col, includeKeywords, summary),
                _ => throw new Exception($"Unknown method: {request.Method}")
            };

            return Ok(request.Id, result);
        }
        catch (Exception ex)
        {
            return Error(request.Id, -1, ex.Message);
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

    private string HandleDiagnostics(string? file, string? severity)
    {
        var results = _service.GetDiagnostics(_snapshot!, file);
        if (severity != null)
            results = results.Where(d => d.Severity.Equals(severity, StringComparison.OrdinalIgnoreCase)).ToList();
        return OutputFormatter.DiagnosticsToJson(results, _snapshot!.ProjectRoot);
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
            _fileWatcher = new FileSystemWatcher(_projectRoot, "*.nl")
            {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.CreationTime
            };

            _fileWatcher.Changed += OnFileChanged;
            _fileWatcher.Created += OnFileChanged;
            _fileWatcher.Deleted += OnFileChanged;
            _fileWatcher.Renamed += (_, e) => OnFileChanged(null, e);

            _fileWatcher.EnableRaisingEvents = true;
            Console.Error.WriteLine("[daemon] File watcher started for *.nl files");
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

        Console.Error.WriteLine($"[daemon] File changed: {Path.GetFileName(e.FullPath)} — cache invalidated");
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

    private static DaemonResponse Error(int id, int code, string message) => new()
    {
        Id = id,
        Error = new DaemonError { Code = code, Message = message }
    };

    private static T? GetParam<T>(JsonElement? paramsElement, string key)
    {
        if (paramsElement == null || paramsElement.Value.ValueKind != JsonValueKind.Object) return default;
        if (paramsElement.Value.TryGetProperty(key, out var prop))
        {
            try { return JsonSerializer.Deserialize<T>(prop.GetRawText()); }
            catch { return default; }
        }
        return default;
    }
}

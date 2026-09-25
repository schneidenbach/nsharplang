namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Linq
import System.Net.Sockets
import System.Text
import System.Text.Json
import System.Threading
import NSharpLang.Cli
import NSharpLang.Cli.Commands
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// The error the query dispatch throws to answer with a JSON-RPC code rather than a message alone.
class DaemonProtocolException: Exception {
    Code: int

    constructor(code: int, message: string): base(message) {
        Code = code
    }
}

// The `data` payload of a parse-error response: the three members `JsonException` exposes about
// WHERE the bytes stopped being JSON. It was a C# anonymous type; the properties are spelled out
// here because the serializer reads properties, not fields, and the camel-case policy turns these
// three names into `path`, `lineNumber` and `bytePositionInLine` exactly as it did before.
class DaemonParseErrorData {
    pathValue: string?
    lineNumberValue: long?
    bytePositionInLineValue: long?

    constructor(path: string?, lineNumber: long?, bytePositionInLine: long?) {
        pathValue = path
        lineNumberValue = lineNumber
        bytePositionInLineValue = bytePositionInLine
    }

    Path: string? {
        get {
            return pathValue
        }
    }

    LineNumber: long? {
        get {
            return lineNumberValue
        }
    }

    BytePositionInLine: long? {
        get {
            return bytePositionInLineValue
        }
    }
}

// Background daemon server that caches project analysis and serves
// nlc query requests via Unix domain socket.
//
// Lifecycle:
// 1. Started by first `nlc query` call or `nlc daemon start`
// 2. Listens on Unix socket at {projectRoot}/.nlc/daemon.sock
// 3. Caches ProjectSnapshot after first request
// 4. FileSystemWatcher invalidates cache on .nl file changes
// 5. Auto-exits after 30 minutes idle
//
// TWO FIELDS ARE READ BY A THREAD THAT DID NOT WRITE THEM — `running`, which the idle thread clears
// while the accept loop reads it, and `cacheInvalid`, which the file-watcher callbacks set while
// `EnsureSnapshot` reads it. Both were `volatile` in C#. N# has no `volatile` modifier, so every
// access goes through `Volatile.Read`/`Volatile.Write`, which is the same acquire/release the
// modifier compiles to; nothing about the ordering changes.
class DaemonServer {
    static DaemonJsonOptions: JsonSerializerOptions = CreateDaemonJsonOptions()

    projectRoot: string
    socketPath: string
    service: CodeIntelligenceService
    completionEngine: CompletionEngine
    snapshot: ProjectSnapshot?
    lastActivity: DateTime
    fileWatcher: FileSystemWatcher?
    cacheInvalid: bool
    running: bool
    idleTimeout: TimeSpan
    idleCheckInterval: TimeSpan

    constructor(root: string): this(root, TimeSpan.FromMinutes(DaemonConstants.IdleTimeoutMinutes), TimeSpan.FromMinutes(1)) {
    }

    constructor(root: string, timeout: TimeSpan, checkInterval: TimeSpan) {
        projectRoot = root
        socketPath = DaemonConstants.GetSocketPath(root)
        service = new CodeIntelligenceService()
        completionEngine = new CompletionEngine()
        snapshot = null
        lastActivity = DateTime.UtcNow
        fileWatcher = null
        cacheInvalid = true
        running = false
        idleTimeout = timeout
        idleCheckInterval = checkInterval
    }

    static func CreateDaemonJsonOptions(): JsonSerializerOptions {
        options := new JsonSerializerOptions()
        options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        options.PropertyNameCaseInsensitive = true
        return options
    }

    // Start the daemon server. Blocks until shutdown.
    func Run() {
        pidPath := DaemonProtocolKernels.GetPidFilePath(socketPath)
        ownsSocket := false

        if File.Exists(socketPath) {
            if DaemonClient.IsRunning(projectRoot) {
                throw new InvalidOperationException(DaemonProtocolKernels.GetAlreadyRunningMessage(projectRoot))
            }

            File.Delete(socketPath)
        }

        using listener := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)

        try {
            listener.Bind(new UnixDomainSocketEndPoint(socketPath))
            ownsSocket = true
            listener.Listen(5)

            Volatile.Write(ref running, true)

            // Start file watcher only after this process owns the socket.
            StartFileWatcher()

            // Write PID file only after bind/listen succeeds.
            File.WriteAllText(pidPath, Environment.ProcessId.ToString())

            Console.Error.WriteLine(DaemonServerKernels.GetListeningMessage(socketPath, Environment.ProcessId))
            Console.Error.WriteLine(DaemonServerKernels.GetProjectMessage(projectRoot))
            Console.Error.WriteLine(DaemonServerKernels.GetIdleTimeoutMessage(
                DaemonServerKernels.FormatDurationMilliseconds((long)Math.Round(idleTimeout.TotalMilliseconds))
            ))

            // Idle timeout thread. The body is bound to a `ThreadStart` local first: a lambda handed
            // straight to `new Thread(...)` declines at emit (logged in
            // census-briefs/CLI2-COMPILER-BLOCKERS.md), and the typed local is the same delegate.
            idleBody: ThreadStart = () => {
                while Volatile.Read(ref running) {
                    Thread.Sleep(idleCheckInterval)
                    idle := DateTime.UtcNow - lastActivity
                    if idle >= idleTimeout {
                        Console.Error.WriteLine(DaemonServerKernels.GetIdleTimeoutShutdownMessage(
                            DaemonServerKernels.FormatDurationMilliseconds((long)Math.Round(idleTimeout.TotalMilliseconds))
                        ))
                        Volatile.Write(ref running, false)
                        // Connect to self to unblock Accept()
                        try {
                            using kick := new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified)
                            kick.Connect(new UnixDomainSocketEndPoint(socketPath))
                            kick.Close()
                        } catch kickFailure: Exception {
                            // the kick is best-effort: Accept() unblocks on shutdown either way
                        }
                    }
                }
            }
            idleThread := new Thread(idleBody)
            idleThread.IsBackground = true
            idleThread.Start()

            while Volatile.Read(ref running) {
                try {
                    using client := listener.Accept()
                    lastActivity = DateTime.UtcNow

                    if !Volatile.Read(ref running) {
                        break
                    }

                    HandleClient(client)
                } catch ex: Exception {
                    // One `catch` with the socket test first, because the C# clause
                    // `catch (SocketException) when (!_running)` is an exception FILTER and N# has
                    // none: a socket failure during shutdown still ends the loop silently, and
                    // every other failure is still reported on the same stream.
                    socketFailure := ex as SocketException
                    if socketFailure != null && !Volatile.Read(ref running) {
                        break
                    }

                    Console.Error.WriteLine(DaemonServerKernels.GetServerErrorMessage(ex.Message))
                }
            }
        } finally {
            Volatile.Write(ref running, false)
            if ownsSocket {
                Cleanup(pidPath)
            } else {
                fileWatcher?.Dispose()
            }
        }
    }

    func HandleClient(client: Socket) {
        try {
            // Read request. CLI clients half-close after sending; direct clients may not,
            // so also stop after a short quiet period once at least one chunk arrived.
            using requestStream := new MemoryStream()
            buffer := new byte[](8192)
            client.ReceiveTimeout = 500

            while true {
                received := 0
                try {
                    received = client.Receive(buffer)
                } catch receiveFailure: Exception {
                    socketFailure := receiveFailure as SocketException
                    if socketFailure != null && socketFailure.SocketErrorCode == SocketError.TimedOut && requestStream.Length > 0 {
                        break
                    }

                    throw
                }

                if received == 0 {
                    break
                }

                requestStream.Write(buffer, 0, received)
            }

            if requestStream.Length == 0 {
                return
            }

            request: DaemonRequest? = null
            try {
                requestJson := Encoding.UTF8.GetString(requestStream.ToArray())
                request = JsonSerializer.Deserialize<DaemonRequest>(requestJson, DaemonJsonOptions)
            } catch parseFailure: Exception {
                jsonFailure := parseFailure as JsonException
                if jsonFailure == null {
                    throw
                }

                SendResponse(client, Error(
                    0,
                    DaemonConstants.ErrorParse,
                    DaemonProtocolKernels.GetMalformedRequestJsonMessage(),
                    new DaemonParseErrorData(jsonFailure.Path, jsonFailure.LineNumber, jsonFailure.BytePositionInLine)
                ))
                return
            }

            if request == null || string.IsNullOrWhiteSpace(request.Method) {
                requestId := 0
                if request != null {
                    requestId = request.Id
                }

                SendResponse(client, Error(requestId, DaemonConstants.ErrorInvalidRequest, DaemonProtocolKernels.GetMissingMethodMessage()))
                return
            }

            // Process request
            response := ProcessRequest(request)

            // Send response
            SendResponse(client, response)
        } catch ex: Exception {
            Console.Error.WriteLine(DaemonServerKernels.GetClientErrorMessage(ex.Message))
        }
    }

    func ProcessRequest(request: DaemonRequest): DaemonResponse {
        try {
            methodKind := DaemonProtocolKernels.GetMethodKind(request.Method)

            // Daemon control methods
            if methodKind == DaemonMethodKind.Ping {
                return Ok(request.Id, DaemonProtocolKernels.GetPongResultJson())
            }

            if methodKind == DaemonMethodKind.Shutdown {
                Volatile.Write(ref running, false)
                return Ok(request.Id, DaemonProtocolKernels.GetShutdownResultJson())
            }

            if methodKind == DaemonMethodKind.Status {
                uptime := DateTime.UtcNow - CurrentProcessStartTimeUtc()
                cachedFiles := 0
                statusSnapshot := snapshot
                if statusSnapshot != null {
                    cachedFiles = statusSnapshot.CompilationUnits.Count
                }

                return Ok(
                    request.Id,
                    DaemonProtocolKernels.StatusResultJson(
                        Environment.ProcessId,
                        DaemonProtocolKernels.FormatUptime(uptime.Hours, uptime.Minutes, uptime.Seconds),
                        projectRoot,
                        cachedFiles,
                        DaemonProtocolKernels.FormatIdleTimeoutMinutes(DaemonConstants.IdleTimeoutMinutes)
                    )
                )
            }

            if !DaemonProtocolKernels.IsQueryMethod(methodKind) {
                return Error(request.Id, DaemonConstants.ErrorMethodNotFound, DaemonServerKernels.GetUnknownMethodMessage(request.Method))
            }

            // Ensure snapshot is loaded
            EnsureSnapshot()

            loaded := snapshot
            if loaded == null {
                return Error(request.Id, DaemonConstants.ErrorInternal, DaemonServerKernels.GetFailedLoadProjectMessage())
            }

            if methodKind == DaemonMethodKind.Batch {
                requests := GetParam<List<BatchQueryRequest>>(request.Params, "requests")
                if requests == null || requests.Count == 0 {
                    return Ok(request.Id, OutputFormatter.ErrorToJson(
                        "batch",
                        DaemonServerKernels.GetEmptyBatchPayloadMessage(),
                        projectRoot,
                        "emptyBatch",
                        null
                    ))
                }

                execution := BatchQueryRunner.Execute(
                    requests,
                    projectRoot,
                    () => loaded,
                    service,
                    completionEngine
                )

                return Ok(request.Id, execution.Json)
            }

            // Extract params
            filePath := GetParam<string>(request.Params, "file")
            posStr := GetParam<string>(request.Params, "pos")
            name := GetParam<string>(request.Params, "name")
            kind := GetParam<string>(request.Params, "kind")
            severity := GetParam<string>(request.Params, "severity")
            includeKeywords := GetParam<bool>(request.Params, "includeKeywords")
            summary := GetParam<bool>(request.Params, "summary")
            compact := GetParam<bool>(request.Params, "compact")
            clusters := GetParam<bool>(request.Params, "clusters")

            line := 0
            col := 0
            if posStr != null {
                DaemonServerKernels.ParsePosition(posStr, out line, out col)
            }

            parameterValidation := DaemonProtocolKernels.ValidateRequiredParameters(methodKind, filePath != null)
            if !parameterValidation.IsValid {
                return Ok(request.Id, OutputFormatter.ErrorToJson(
                    parameterValidation.QueryCommand,
                    parameterValidation.Message,
                    null,
                    null,
                    null
                ))
            }

            // Query methods
            if methodKind == DaemonMethodKind.Symbols {
                return Ok(request.Id, HandleSymbols(loaded, filePath, kind))
            }

            if methodKind == DaemonMethodKind.Outline {
                return Ok(request.Id, HandleOutline(loaded, must filePath))
            }

            if methodKind == DaemonMethodKind.Diagnostics {
                return Ok(request.Id, HandleDiagnostics(loaded, filePath, severity, clusters))
            }

            if methodKind == DaemonMethodKind.Type {
                return Ok(request.Id, HandleType(loaded, must filePath, line, col))
            }

            if methodKind == DaemonMethodKind.Definition {
                return Ok(request.Id, HandleDefinition(loaded, must filePath, line, col))
            }

            if methodKind == DaemonMethodKind.References {
                return Ok(request.Id, HandleReferences(loaded, must filePath, line, col))
            }

            if methodKind == DaemonMethodKind.Completions {
                return Ok(request.Id, HandleCompletions(loaded, must filePath, line, col, includeKeywords))
            }

            if methodKind == DaemonMethodKind.Inspect {
                return Ok(request.Id, HandleInspect(loaded, must filePath, line, col, includeKeywords, summary || compact))
            }

            if methodKind == DaemonMethodKind.Batch {
                throw new InvalidOperationException(DaemonProtocolKernels.GetBatchDispatchAfterPrecheckMessage())
            }

            throw new DaemonProtocolException(DaemonConstants.ErrorMethodNotFound, DaemonServerKernels.GetUnknownMethodMessage(request.Method))
        } catch ex: Exception {
            protocolFailure := ex as DaemonProtocolException
            if protocolFailure != null {
                return Error(request.Id, protocolFailure.Code, protocolFailure.Message)
            }

            return Error(request.Id, DaemonConstants.ErrorInternal, ex.Message)
        }
    }

    // ── Query Handlers ──────────────────────────────────────────────────

    func HandleSymbols(loaded: ProjectSnapshot, filePath: string?, kind: string?): string {
        kindFilter: SymbolKind? = null
        if kind != null {
            parsedKind := QueryCommandKernels.ParseSymbolKind(kind)
            if parsedKind.HasValue {
                kindFilter = parsedKind.GetValueOrDefault()
            }
        }

        results := service.GetSymbols(loaded, filePath, kindFilter)
        return OutputFormatter.SymbolsToJson(results, loaded.ProjectRoot)
    }

    func HandleOutline(loaded: ProjectSnapshot, filePath: string): string {
        result := service.GetOutline(loaded, filePath)
        return OutputFormatter.OutlineToJson(result)
    }

    func HandleDiagnostics(loaded: ProjectSnapshot, filePath: string?, severity: string?, clusters: bool): string {
        results: List<DiagnosticResult> = service.GetDiagnostics(loaded, filePath)
        if severity != null {
            results = OutputFormatter.FilterDiagnosticsBySeverity(results, severity)
        }

        if clusters {
            return OutputFormatter.DiagnosticClustersToJson(results, loaded.ProjectRoot)
        }

        return OutputFormatter.DiagnosticsToJson(results, loaded.ProjectRoot)
    }

    func HandleType(loaded: ProjectSnapshot, filePath: string, line: int, col: int): string {
        result := service.GetTypeAtPosition(loaded, filePath, line, col)
        if result == null {
            return OutputFormatter.ErrorToJson(
                "type",
                DaemonServerKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                loaded.ProjectRoot,
                "noSymbol",
                PositionDetails(filePath, line, col)
            )
        }

        return OutputFormatter.TypeToJson(result, filePath, line, col)
    }

    func HandleDefinition(loaded: ProjectSnapshot, filePath: string, line: int, col: int): string {
        result := service.FindDefinition(loaded, filePath, line, col)
        if result == null {
            return OutputFormatter.ErrorToJson(
                "definition",
                DaemonServerKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                loaded.ProjectRoot,
                "noSymbol",
                PositionDetails(filePath, line, col)
            )
        }

        return OutputFormatter.DefinitionToJson(result)
    }

    func HandleReferences(loaded: ProjectSnapshot, filePath: string, line: int, col: int): string {
        // Resolve symbol metadata (same as CLI path — don't hardcode placeholders)
        definition := service.FindDefinition(loaded, filePath, line, col)
        if definition == null {
            return OutputFormatter.ErrorToJson(
                "references",
                DaemonServerKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                loaded.ProjectRoot,
                "noSymbol",
                PositionDetails(filePath, line, col)
            )
        }

        symbolName := definition.Name
        symbolKind := definition.Kind
        definedAt := new LocationResult(definition.File, definition.Line, definition.Column)

        results := service.FindReferences(loaded, filePath, line, col)
        if results.Count == 0 {
            details := PositionDetails(filePath, line, col)
            symbol := new Dictionary<string, object>()
            symbol["name"] = symbolName
            symbol["kind"] = symbolKind
            symbol["definedAt"] = definedAt
            details["symbol"] = symbol

            return OutputFormatter.ErrorToJson(
                "references",
                DaemonServerKernels.GetSemanticReferencesUnavailableMessage(),
                loaded.ProjectRoot,
                "semanticReferencesUnavailable",
                details
            )
        }

        return OutputFormatter.ReferencesToJson(symbolName, symbolKind, definedAt, results)
    }

    func HandleCompletions(loaded: ProjectSnapshot, filePath: string, line: int, col: int, includeKeywords: bool): string {
        result := completionEngine.GetCompletions(loaded, filePath, line, col, includeKeywords)
        return OutputFormatter.CompletionsToJson(result, filePath, line, col)
    }

    func HandleInspect(loaded: ProjectSnapshot, filePath: string, line: int, col: int, includeKeywords: bool, summary: bool): string {
        typeResult := service.GetTypeAtPosition(loaded, filePath, line, col)
        definition := service.FindDefinition(loaded, filePath, line, col)
        references: List<ReferenceResult> = new List<ReferenceResult>()
        if definition != null {
            references = service.FindReferences(loaded, filePath, line, col)
        }

        completions := completionEngine.GetCompletions(loaded, filePath, line, col, includeKeywords)

        if typeResult == null && definition == null && references.Count == 0 {
            return OutputFormatter.ErrorToJson(
                "inspect",
                DaemonServerKernels.GetNoSymbolAtPositionMessage(filePath, line, col),
                loaded.ProjectRoot,
                "noSymbol",
                PositionDetails(filePath, line, col)
            )
        }

        symbol: InspectSymbolResult? = null
        if definition != null {
            symbol = new InspectSymbolResult(
                definition.Name,
                definition.Kind,
                new LocationResult(definition.File, definition.Line, definition.Column)
            )
        } else if typeResult != null {
            symbol = new InspectSymbolResult(typeResult.Name, typeResult.Kind, typeResult.Definition)
        }

        definitionCount := references.Count(reference => reference.IsDefinition)
        inspect := new InspectResult(
            symbol,
            typeResult,
            definition,
            new InspectReferencesResult(
                references.Count,
                definitionCount,
                references.ToArray()
            ),
            completions
        )

        if summary {
            return OutputFormatter.InspectSummaryToJson(inspect, filePath, line, col)
        }

        return OutputFormatter.InspectToJson(inspect, filePath, line, col)
    }

    // ── Snapshot Management ─────────────────────────────────────────────

    func EnsureSnapshot() {
        if snapshot != null && !Volatile.Read(ref cacheInvalid) {
            return
        }

        Console.Error.WriteLine(DaemonServerKernels.GetLoadingProjectMessage())
        sw := Stopwatch.StartNew()

        try {
            loaded := service.LoadProject(projectRoot)
            snapshot = loaded
            Volatile.Write(ref cacheInvalid, false)
            sw.Stop()
            elapsedMilliseconds := sw.ElapsedMilliseconds
            fileCount := loaded.CompilationUnits.Count
            Console.Error.WriteLine(DaemonServerKernels.GetProjectLoadedMessage(elapsedMilliseconds, fileCount))
        } catch ex: Exception {
            Console.Error.WriteLine(DaemonServerKernels.GetProjectLoadFailedTraceMessage(ex.Message))
            snapshot = null
        }
    }

    // ── File Watching ───────────────────────────────────────────────────

    func StartFileWatcher() {
        try {
            watcher := new FileSystemWatcher(projectRoot)
            watcher.IncludeSubdirectories = true
            watcher.NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.CreationTime

            _changed := on watcher.Changed (sender, e) => {
                OnFileChanged(e.FullPath)
            }
            _created := on watcher.Created (sender, e) => {
                OnFileChanged(e.FullPath)
            }
            _deleted := on watcher.Deleted (sender, e) => {
                OnFileChanged(e.FullPath)
            }
            _renamed := on watcher.Renamed (sender, e) => {
                OnFileChanged(e.FullPath)
            }

            watcher.EnableRaisingEvents = true
            fileWatcher = watcher
            Console.Error.WriteLine(DaemonServerKernels.GetFileWatcherStartedMessage())
        } catch ex: Exception {
            Console.Error.WriteLine(DaemonServerKernels.GetFileWatcherFailedMessage(ex.Message))
        }
    }

    func OnFileChanged(fullPath: string) {
        if !DaemonServerKernels.ShouldInvalidateForChangedPath(fullPath) {
            return
        }

        fileName := DaemonServerKernels.GetChangedFileName(fullPath)
        Console.Error.WriteLine(DaemonServerKernels.GetFileChangedMessage(fileName))
        Volatile.Write(ref cacheInvalid, true)
    }

    // ── Cleanup ─────────────────────────────────────────────────────────

    func Cleanup(pidPath: string) {
        fileWatcher?.Dispose()
        try {
            File.Delete(socketPath)
        } catch socketDeleteFailure: Exception {
            // best-effort: the socket may already be gone
        }

        try {
            File.Delete(pidPath)
        } catch pidDeleteFailure: Exception {
            // best-effort: the pid file may already be gone
        }

        Console.Error.WriteLine(DaemonServerKernels.GetShutdownCompleteMessage())
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    // `new { file, position = new { line, column } }` was the C# spelling of this detail payload.
    // It is built here rather than read from `QueryErrorDetailKernels.Position` because that kernel
    // NORMALIZES the path and the daemon never did: the file is echoed back exactly as the client
    // sent it.
    static func PositionDetails(filePath: string, line: int, col: int): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["file"] = filePath
        payload["position"] = QueryErrorDetailKernels.BuildPosition(line, col)
        return payload
    }

    // `daemon status` reports UtcNow minus THIS PROCESS'S START, and it must keep doing exactly
    // that. `Process.GetCurrentProcess().StartTime` cannot be written here: the compiler that
    // builds `src/NSharpLang.Compiler` is the SEEDED BOOTSTRAP SDK, which predates the fix that
    // modelled the `Process` instance surface (census-briefs/CLI2-COMPILER-BLOCKERS.md, cli4), and
    // reseeding is not this lane's to do. The property is therefore read by name off the same
    // `Process` object; `Convert.ToDateTime` on the boxed result is `DateTime`'s own
    // `IConvertible.ToDateTime`, which returns the value unchanged, Kind included. This whole
    // function collapses back to one member access the moment the seed carries that fix.
    static func CurrentProcessStartTimeUtc(): DateTime {
        currentProcess := Process.GetCurrentProcess()
        startTimeProperty := must typeof(Process).GetProperty("StartTime")
        boxedStartTime := startTimeProperty.GetValue(currentProcess)
        startTime := Convert.ToDateTime(boxedStartTime)
        return startTime.ToUniversalTime()
    }

    static func Ok(id: int, result: string): DaemonResponse {
        // Assignments, not an object initializer: `nlc format` rewrites `new T() { … }` to the
        // parenless form and this envelope holds a nullable member, which declined at emit on the
        // compiler this file was written against.
        response := new DaemonResponse()
        response.Id = id
        response.Result = result
        return response
    }

    static func Error(id: int, code: int, message: string): DaemonResponse {
        return Error(id, code, message, null)
    }

    static func Error(id: int, code: int, message: string, data: object?): DaemonResponse {
        error := new DaemonError()
        error.Code = code
        error.Message = message
        error.Data = data

        response := new DaemonResponse()
        response.Id = id
        response.Error = error
        return response
    }

    static func SendResponse(socket: Socket, response: DaemonResponse) {
        responseJson := JsonSerializer.Serialize<DaemonResponse>(response, DaemonJsonOptions)
        responseBytes := Encoding.UTF8.GetBytes(responseJson)
        SendAll(socket, responseBytes)
    }

    static func GetParam<T>(paramsElement: JsonElement?, key: string): T? {
        if paramsElement == null {
            return default
        }

        value := paramsElement.Value
        if value.ValueKind != JsonValueKind.Object {
            return default
        }

        prop: JsonElement = default
        if value.TryGetProperty(key, out prop) {
            try {
                raw := prop.GetRawText()
                return JsonSerializer.Deserialize<T>(raw, DaemonJsonOptions)
            } catch ex: Exception {
                // Tolerate the malformed param (caller treats it as absent) but leave a trace —
                // a silently-dropped param turns protocol bugs into undebuggable client hangs.
                Console.Error.WriteLine(DaemonServerKernels.GetMalformedRequestParamMessage(
                    key,
                    typeof(T).Name,
                    ex.Message
                ))
                return default
            }
        }

        return default
    }

    static func SendAll(socket: Socket, bytes: byte[]) {
        sent := 0
        while sent < bytes.Length {
            sent = sent + socket.Send(bytes, sent, bytes.Length - sent, SocketFlags.None)
        }
    }
}

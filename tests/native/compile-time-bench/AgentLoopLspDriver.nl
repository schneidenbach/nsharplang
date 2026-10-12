namespace NSharpLang.CompileTimeBench

import System
import System.Collections.Generic
import System.Diagnostics
import System.Globalization
import System.IO
import System.Text
import System.Text.Json
import System.Text.RegularExpressions
import System.Threading
import System.Threading.Tasks

// Small stdio JSON-RPC client used only by the agent-loop performance harness. It launches the
// built N# LanguageServer assembly directly; no editor, VS Code extension, or test server is in
// the measurement path.
class AgentLoopLspSample {
    WallMs: long
    Counters: AgentLoopLspCounters

    constructor(wallMs: long, counters: AgentLoopLspCounters) {
        WallMs = wallMs
        Counters = counters
    }
}

class AgentLoopLspOutputRow {
    Scenario: string
    HeadSamples: List<AgentLoopLspSample>
    BaseSamples: List<AgentLoopLspSample>
    HeadMedianWallMs: long
    BaseMedianWallMs: long
    StructuralCounters: AgentLoopLspCounters

    constructor(scenario: string, head: List<AgentLoopLspSample>, baseSamples: List<AgentLoopLspSample>, counters: AgentLoopLspCounters) {
        Scenario = scenario
        HeadSamples = head
        BaseSamples = baseSamples
        HeadMedianWallMs = AgentLoopLspMedian(head)
        BaseMedianWallMs = AgentLoopLspMedian(baseSamples)
        StructuralCounters = counters
    }
}

class AgentLoopLspOutput {
    Schema: string
    SchemaVersion: int
    Project: string
    SourceFiles: int
    Rows: List<AgentLoopLspOutputRow>

    constructor(project: string, sourceFiles: int, rows: List<AgentLoopLspOutputRow>) {
        Schema = "nsharp.agent-loop-lsp"
        SchemaVersion = 3
        Project = project
        SourceFiles = sourceFiles
        Rows = rows
    }
}

func AgentLoopLspMedian(samples: List<AgentLoopLspSample>): long {
    if samples.Count == 0 {
        return -1
    }
    values := new long[samples.Count]
    i := 0
    while i < samples.Count {
        values[i] = samples[i].WallMs
        i = i + 1
    }
    Array.Sort(values)
    middle := values.Length / 2
    if values.Length % 2 == 1 {
        return values[middle]
    }
    return (values[middle - 1] + values[middle]) / 2
}

func AgentLoopLspElapsedMilliseconds(started: long): long {
    elapsedTicks := Stopwatch.GetTimestamp() - started
    elapsedMilliseconds := elapsedTicks * 1000 / Stopwatch.Frequency
    if elapsedTicks * 1000 % Stopwatch.Frequency != 0 {
        elapsedMilliseconds = elapsedMilliseconds + 1
    }
    return Math.Max(1, elapsedMilliseconds)
}

func AgentLoopLspObject(): Dictionary<string, object?> {
    return new Dictionary<string, object?>()
}

func AgentLoopLspString(value: string): Dictionary<string, object?> {
    message := AgentLoopLspObject()
    message["jsonrpc"] = "2.0"
    message["method"] = value
    return message
}

class AgentLoopLspClient {
    ChildProcess: Process?
    StderrTask: Task<string>?
    PendingMessages: List<string>
    OpenedUris: List<string>
    NextRequestId: int
    Version: int
    Project: string
    Home: string
    LogPath: string
    LogOffset: int
    SupportsVersionedDiagnostics: bool

    constructor(project: string, label: string) {
        ChildProcess = null
        StderrTask = null
        PendingMessages = new List<string>()
        OpenedUris = new List<string>()
        NextRequestId = 1
        Version = 1
        Project = project
        Home = Path.Combine(Path.GetTempPath(), "nsharp-lsp-agent-loop-" + label + "-" + Guid.NewGuid().ToString("N"))
        LogPath = Path.Combine(Path.Combine(Home, ".nsharp"), "lsp-" + DateTime.Now.ToString("yyyyMMdd", CultureInfo.InvariantCulture) + ".log")
        LogOffset = 0
        SupportsVersionedDiagnostics = label != "base"
    }
}

func AgentLoopLspClientStart(client: AgentLoopLspClient, serverDll: string, sourceFiles: List<string>) {
    Directory.CreateDirectory(client.Home)
    startInfo := new ProcessStartInfo()
    startInfo.FileName = "dotnet"
    startInfo.ArgumentList.Add(serverDll)
    startInfo.WorkingDirectory = client.Project
    startInfo.RedirectStandardInput = true
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false
    startInfo.Environment["HOME"] = client.Home
    startInfo.Environment["USERPROFILE"] = client.Home
    startInfo.Environment["DOTNET_CLI_HOME"] = client.Home
    child := new Process { StartInfo: startInfo }
    child.Start()
    client.ChildProcess = child
    client.StderrTask = child.StandardError.ReadToEndAsync()

    root := new Uri(client.Project + Path.DirectorySeparatorChar.ToString()).AbsoluteUri
    initialize := AgentLoopLspObject()
    initialize["processId"] = Environment.ProcessId
    clientInfo := AgentLoopLspObject()
    clientInfo["name"] = "NSharpLang.AgentLoopBench"
    clientInfo["version"] = "1"
    initialize["clientInfo"] = clientInfo
    initialize["rootUri"] = root
    workspaceFolder := AgentLoopLspObject()
    workspaceFolder["uri"] = root
    workspaceFolder["name"] = Path.GetFileName(client.Project) ?? "project"
    workspaceFolders := new List<Dictionary<string, object?>>()
    workspaceFolders.Add(workspaceFolder)
    initialize["workspaceFolders"] = workspaceFolders
    initialize["capabilities"] = AgentLoopLspObject()
    initialize["trace"] = "off"
    response := AgentLoopLspClientRequest(client, "initialize", initialize, 180000)
    errorElement: JsonElement = default
    if response.TryGetProperty("error", out errorElement) {
        throw new InvalidOperationException("Language Server initialize failed: " + errorElement.ToString())
    }
    AgentLoopLspClientNotify(client, "initialized", AgentLoopLspObject())

    // Workspace discovery can enqueue one notification per source file. Drain through a request
    // response before any measured operation so a prior file's diagnostics cannot satisfy a wait.
    AgentLoopLspClientWaitForLog(client)
    AgentLoopLspClientDrainToBarrier(client, sourceFiles)
}

func AgentLoopLspClientDrainToBarrier(client: AgentLoopLspClient, sourceFiles: List<string>) {
    client.PendingMessages.Clear()
    source := sourceFiles[0]
    text := File.ReadAllText(source)
    token := AgentLoopLspToken(source)
    position := AgentLoopLspTokenPosition(text, token)
    sourceUri := new Uri(Path.GetFullPath(source)).AbsoluteUri
    requestId := client.NextRequestId
    client.NextRequestId = client.NextRequestId + 1
    request := AgentLoopLspString("textDocument/hover")
    request["id"] = requestId
    request["params"] = AgentLoopLspTextDocumentPosition(sourceUri, position)
    AgentLoopLspClientSend(client, request)

    timer := Stopwatch.StartNew()
    while timer.ElapsedMilliseconds < 180000 {
        incoming := AgentLoopLspClientReadMessage(client, 180000 - Convert.ToInt32(timer.ElapsedMilliseconds))
        document := JsonDocument.Parse(incoming)
        root := document.RootElement
        id: JsonElement = default
        if root.TryGetProperty("id", out id) && id.ValueKind == JsonValueKind.Number && id.GetInt32() == requestId {
            errorElement: JsonElement = default
            if root.TryGetProperty("error", out errorElement) {
                errorText := errorElement.ToString()
                document.Dispose()
                throw new InvalidOperationException("LSP drain barrier failed: " + errorText)
            }
            document.Dispose()
            client.PendingMessages.Clear()
            AgentLoopLspClientAdvanceLogOffsetAfterQuiet(client)
            return
        }
        document.Dispose()
    }
    throw new TimeoutException("Timed out waiting for the Language Server diagnostics drain barrier.")
}

// The server may flush the barrier request's log entries just after sending its response. Wait
// for a quiet log before advancing the measurement offset so those entries cannot leak into the
// next operation's structural counters.
func AgentLoopLspClientAdvanceLogOffsetAfterQuiet(client: AgentLoopLspClient): void {
    previousLength := -1
    stableSamples := 0
    attempt := 0
    while attempt < 100 {
        currentLength := File.ReadAllText(client.LogPath).Length
        if currentLength == previousLength {
            stableSamples = stableSamples + 1
            if stableSamples >= 20 {
                client.LogOffset = currentLength
                return
            }
        } else {
            previousLength = currentLength
            stableSamples = 0
        }
        Thread.Sleep(5)
        attempt = attempt + 1
    }

    throw new IOException("The Language Server log did not become quiet after the measurement barrier.")
}

func AgentLoopLspClientNotify(client: AgentLoopLspClient, method: string, parameters: Dictionary<string, object?>) {
    message := AgentLoopLspString(method)
    message["params"] = parameters
    AgentLoopLspClientSend(client, message)
}

func AgentLoopLspClientRequest(client: AgentLoopLspClient, method: string, parameters: Dictionary<string, object?>, timeoutMilliseconds: int): JsonElement {
    requestId := client.NextRequestId
    client.NextRequestId = client.NextRequestId + 1
    message := AgentLoopLspString(method)
    message["id"] = requestId
    message["params"] = parameters
    AgentLoopLspClientSend(client, message)
    deadline := Stopwatch.StartNew()
    while deadline.ElapsedMilliseconds < timeoutMilliseconds {
        incoming := AgentLoopLspClientReadMessage(client, timeoutMilliseconds - Convert.ToInt32(deadline.ElapsedMilliseconds))
        document := JsonDocument.Parse(incoming)
        root := document.RootElement
        id: JsonElement = default
        if root.TryGetProperty("id", out id) && id.ValueKind == JsonValueKind.Number && id.GetInt32() == requestId {
            errorElement: JsonElement = default
            if root.TryGetProperty("error", out errorElement) {
                response := root.Clone()
                document.Dispose()
                return response
            }
            response := root.Clone()
            document.Dispose()
            return response
        }
        client.PendingMessages.Add(incoming)
        document.Dispose()
    }
    throw new TimeoutException("Timed out waiting for Language Server request '" + method + "'.")
}

func AgentLoopLspClientSend(client: AgentLoopLspClient, message: Dictionary<string, object?>) {
    child := client.ChildProcess ?? throw new InvalidOperationException("Language Server process is not running.")
    json := JsonSerializer.Serialize<Dictionary<string, object?>>(message)
    payload := Encoding.UTF8.GetBytes(json)
    header := Encoding.ASCII.GetBytes("Content-Length: " + payload.Length.ToString(CultureInfo.InvariantCulture) + "\r\n\r\n")
    stream := child.StandardInput.BaseStream
    stream.Write(header, 0, header.Length)
    stream.Write(payload, 0, payload.Length)
    stream.Flush()
}

func AgentLoopLspClientReadMessage(client: AgentLoopLspClient, timeoutMilliseconds: int): string {
    if timeoutMilliseconds <= 0 {
        throw new TimeoutException("Timed out waiting for a Language Server message.")
    }
    readTask := Task.Run(() => AgentLoopLspClientReadMessageCore(client))
    if !readTask.Wait(timeoutMilliseconds) {
        child := client.ChildProcess
        if child != null && !(child ?? throw new InvalidOperationException("Language Server process is not running.")).HasExited {
            (child ?? throw new InvalidOperationException("Language Server process is not running.")).Kill(true)
            (child ?? throw new InvalidOperationException("Language Server process is not running.")).WaitForExit()
        }
        throw new TimeoutException("Timed out waiting for a Language Server message.")
    }
    return readTask.Result
}

func AgentLoopLspClientReadMessageCore(client: AgentLoopLspClient): string {
    child := client.ChildProcess ?? throw new InvalidOperationException("Language Server process is not running.")
    stream := child.StandardOutput.BaseStream
    headerBytes := new List<byte>()
    while true {
        next := stream.ReadByte()
        if next < 0 {
            throw new EndOfStreamException("Language Server closed stdout before sending a complete LSP header.")
        }
        headerBytes.Add(Convert.ToByte(next))
        count := headerBytes.Count
        if count >= 4 && headerBytes[count - 4] == 13 && headerBytes[count - 3] == 10 && headerBytes[count - 2] == 13 && headerBytes[count - 1] == 10 {
            break
        }
        if headerBytes.Count > 8192 {
            throw new InvalidDataException("Language Server sent an oversized LSP header.")
        }
    }
    header := Encoding.ASCII.GetString(headerBytes.ToArray())
    lengthMatch := Regex.Match(header, "(?im)^Content-Length:\\s*(\\d+)\\s*$")
    if !lengthMatch.Success {
        throw new InvalidDataException("Language Server sent a malformed LSP header: " + header)
    }
    bodyLength := Int32.Parse(lengthMatch.Groups[1].Value, CultureInfo.InvariantCulture)
    if bodyLength < 0 || bodyLength > 16777216 {
        throw new InvalidDataException("Language Server sent an invalid LSP message length.")
    }
    body := new byte[bodyLength]
    offset := 0
    while offset < bodyLength {
        read := stream.Read(body, offset, bodyLength - offset)
        if read <= 0 {
            throw new EndOfStreamException("Language Server closed stdout during an LSP message.")
        }
        offset = offset + read
    }
    return Encoding.UTF8.GetString(body)
}

func AgentLoopLspClientWaitForDiagnostics(client: AgentLoopLspClient, uri: string, expectedVersion: int, expectedDiagnosticMarker: string, timeoutMilliseconds: int): int {
    timer := Stopwatch.StartNew()
    while timer.ElapsedMilliseconds < timeoutMilliseconds {
        incoming := ""
        if client.PendingMessages.Count > 0 {
            incoming = client.PendingMessages[0]
            client.PendingMessages.RemoveAt(0)
        } else {
            incoming = AgentLoopLspClientReadMessage(client, timeoutMilliseconds - Convert.ToInt32(timer.ElapsedMilliseconds))
        }
        document := JsonDocument.Parse(incoming)
        root := document.RootElement
        method: JsonElement = default
        if root.TryGetProperty("method", out method) && method.GetString() == "textDocument/publishDiagnostics" {
            parameters: JsonElement = default
            if root.TryGetProperty("params", out parameters) {
                publishedUri: JsonElement = default
                if parameters.TryGetProperty("uri", out publishedUri) && publishedUri.GetString() == uri {
                    if expectedDiagnosticMarker.Length > 0 && !incoming.Contains(expectedDiagnosticMarker) {
                        document.Dispose()
                        continue
                    }
                    if client.SupportsVersionedDiagnostics {
                        publishedVersion: JsonElement = default
                        if !parameters.TryGetProperty("version", out publishedVersion) || publishedVersion.ValueKind != JsonValueKind.Number || publishedVersion.GetInt32() != expectedVersion {
                            document.Dispose()
                            continue
                        }
                    }
                    document.Dispose()
                    return 1
                }
            }
        }
        document.Dispose()
    }
    throw new TimeoutException("Timed out waiting for diagnostics for " + uri + ".")
}

func AgentLoopLspClientWaitForLog(client: AgentLoopLspClient) {
    attempt := 0
    while attempt < 1200 && !File.Exists(client.LogPath) {
        Thread.Sleep(25)
        attempt = attempt + 1
    }
    if !File.Exists(client.LogPath) {
        throw new IOException("Language Server did not create its private log at " + client.LogPath + ".")
    }
}

func AgentLoopLspClientReadLogCounters(client: AgentLoopLspClient, operation: string): AgentLoopLspCounters {
    previousLength := -1
    stableSamples := 0
    attempt := 0
    delta := ""
    hasCounterMarker := false
    while attempt < 100 {
        allText := File.ReadAllText(client.LogPath)
        if allText.Length < client.LogOffset {
            throw new IOException("Language Server log was truncated while measuring a row.")
        }
        delta = allText.Substring(client.LogOffset)
        hasCounterMarker = delta.Contains("LSP structural counters: ")
        currentLength := allText.Length
        if currentLength == previousLength {
            stableSamples = stableSamples + 1
            if stableSamples >= 3 && hasCounterMarker {
                break
            }
            if stableSamples >= 20 {
                break
            }
        } else {
            previousLength = currentLength
            stableSamples = 0
        }
        Thread.Sleep(5)
        attempt = attempt + 1
    }
    finalText := File.ReadAllText(client.LogPath)
    if finalText.Length < client.LogOffset {
        throw new IOException("Language Server log was truncated while measuring a row.")
    }
    delta = finalText.Substring(client.LogOffset)
    client.LogOffset = finalText.Length
    hasCounterMarker = delta.Contains("LSP structural counters: ")
    snapshots := 0
    legacySnapshots := 0
    structuralSnapshots := 0
    filesParsed := client.SupportsVersionedDiagnostics ? 0L : -1L
    filesReanalyzed := client.SupportsVersionedDiagnostics ? 0L : -1L
    filesReused := client.SupportsVersionedDiagnostics ? 0L : -1L
    projectSnapshotCacheHits := client.SupportsVersionedDiagnostics ? 0L : -1L
    projectDiskStampScans := client.SupportsVersionedDiagnostics ? 0L : -1L
    documentAnalysisRuns := client.SupportsVersionedDiagnostics ? 0L : -1L
    documentCacheReuses := client.SupportsVersionedDiagnostics ? 0L : -1L
    hasIncrementalCounters := false
    projectRoot := client.Project
    lines := delta.Split('\n')
    for line in lines {
        if line.Contains(projectRoot) && line.Contains("Loaded semantic project snapshot for ") {
            legacySnapshots = legacySnapshots + 1
        }
        if line.Contains("LSP structural counters: ") {
            counterMatch := Regex.Match(line, "LSP structural counters: projectSnapshotsBuilt=(\\d+) filesParsed=(\\d+) filesReanalyzed=(\\d+) filesReused=(\\d+)")
            if counterMatch.Success {
                structuralSnapshots = structuralSnapshots + Int32.Parse(counterMatch.Groups[1].Value, CultureInfo.InvariantCulture)
                filesParsed = filesParsed + Int64.Parse(counterMatch.Groups[2].Value, CultureInfo.InvariantCulture)
                filesReanalyzed = filesReanalyzed + Int64.Parse(counterMatch.Groups[3].Value, CultureInfo.InvariantCulture)
                filesReused = filesReused + Int64.Parse(counterMatch.Groups[4].Value, CultureInfo.InvariantCulture)
                cacheHitMatch := Regex.Match(line, "projectSnapshotCacheHits=(\\d+)")
                if cacheHitMatch.Success {
                    if projectSnapshotCacheHits < 0 {
                        projectSnapshotCacheHits = 0
                    }
                    projectSnapshotCacheHits = projectSnapshotCacheHits + Int64.Parse(cacheHitMatch.Groups[1].Value, CultureInfo.InvariantCulture)
                }
                diskStampMatch := Regex.Match(line, "projectDiskStampScans=(\\d+)")
                if diskStampMatch.Success {
                    if projectDiskStampScans < 0 {
                        projectDiskStampScans = 0
                    }
                    projectDiskStampScans = projectDiskStampScans + Int64.Parse(diskStampMatch.Groups[1].Value, CultureInfo.InvariantCulture)
                }
                hasIncrementalCounters = true
            }
        }
        if line.Contains("LSP document analysis counters: ") {
            analysisMatch := Regex.Match(line, "documentAnalysisRuns=(\\d+) documentCacheReuses=(\\d+)")
            if analysisMatch.Success {
                if documentAnalysisRuns < 0 {
                    documentAnalysisRuns = 0
                    documentCacheReuses = 0
                }
                documentAnalysisRuns = documentAnalysisRuns + Int64.Parse(analysisMatch.Groups[1].Value, CultureInfo.InvariantCulture)
                documentCacheReuses = documentCacheReuses + Int64.Parse(analysisMatch.Groups[2].Value, CultureInfo.InvariantCulture)
            }
        }
    }
    if hasIncrementalCounters {
        snapshots = structuralSnapshots
    } else {
        snapshots = legacySnapshots
    }
    if !hasIncrementalCounters && client.SupportsVersionedDiagnostics && operation == "LSP didChange diagnostics" {
        detail := delta
        if detail.Length > 2500 {
            detail = detail.Substring(detail.Length - 2500)
        }
        throw new IOException("The changed-document diagnostics operation did not log incremental project counters. Recent server log: " + detail)
    }
    return new AgentLoopLspCounters(snapshots, 0, 0, filesParsed, filesReanalyzed, filesReused, projectSnapshotCacheHits, projectDiskStampScans, documentAnalysisRuns, documentCacheReuses, 0)
}

func AgentLoopLspClientIsOpened(client: AgentLoopLspClient, uri: string): bool {
    return client.OpenedUris.Contains(uri)
}

func AgentLoopLspClientMarkOpened(client: AgentLoopLspClient, uri: string) {
    if !client.OpenedUris.Contains(uri) {
        client.OpenedUris.Add(uri)
    }
}

func AgentLoopLspClientOpenFile(client: AgentLoopLspClient, text: string, uri: string) {
    parameters := AgentLoopLspObject()
    document := AgentLoopLspObject()
    document["uri"] = uri
    document["languageId"] = "nsharp"
    document["version"] = client.Version
    document["text"] = text
    parameters["textDocument"] = document
    AgentLoopLspClientNotify(client, "textDocument/didOpen", parameters)
    AgentLoopLspClientWaitForDiagnostics(client, uri, client.Version, "", 120000)
    barrierSources := new List<string>()
    barrierSources.Add(new Uri(uri).LocalPath)
    AgentLoopLspClientDrainToBarrier(client, barrierSources)
    AgentLoopLspClientMarkOpened(client, uri)
}

func AgentLoopLspClientMeasure(client: AgentLoopLspClient, operation: string, sample: int, sourceFiles: List<string>): AgentLoopLspSample {
    AgentLoopLspClientDrainToBarrier(client, sourceFiles)
    sourceIndex := sample % sourceFiles.Count
    if operation == "LSP unchanged didOpen" {
        sourceIndex = sourceFiles.Count / 2 + sample
    }
    source := sourceFiles[sourceIndex]
    uri := new Uri(Path.GetFullPath(source)).AbsoluteUri
    original := File.ReadAllText(source)
    if operation == "LSP unchanged didOpen" {
        parameters := AgentLoopLspObject()
        document := AgentLoopLspObject()
        document["uri"] = uri
        document["languageId"] = "nsharp"
        document["version"] = client.Version
        document["text"] = original
        parameters["textDocument"] = document
        started := Stopwatch.GetTimestamp()
        AgentLoopLspClientNotify(client, "textDocument/didOpen", parameters)
        diagnostics := AgentLoopLspClientWaitForDiagnostics(client, uri, client.Version, "", 120000)
        elapsed := AgentLoopLspElapsedMilliseconds(started)
        counters := AgentLoopLspClientReadLogCounters(client, operation)
        counters.DocumentsUpdated = 1
        counters.DiagnosticsPublished = diagnostics
        counters.FreshDiagnosticsVerified = 1
        if client.SupportsVersionedDiagnostics && counters.ProjectSnapshotsBuilt != 0 {
            side := client.SupportsVersionedDiagnostics ? "head" : "base"
            recentLog := new StringBuilder()
            for logLine in File.ReadAllText(client.LogPath).Split('\n') {
                if logLine.Contains("LSP structural counters:") || logLine.Contains("Loaded semantic project snapshot for") || logLine.Contains("Project semantic snapshot degraded:") || logLine.Contains("Updating document:") {
                    recentLog.Append(logLine)
                    recentLog.Append(Environment.NewLine)
                }
            }
            if recentLog.Length > 5000 {
                recentLog.Remove(0, recentLog.Length - 5000)
            }
            throw new InvalidOperationException("Opening unchanged workspace content rebuilt the project snapshot " + counters.ProjectSnapshotsBuilt.ToString() + " time(s) on " + side + ". Snapshot events: " + recentLog.ToString())
        }
        AgentLoopLspClientMarkOpened(client, uri)
        return new AgentLoopLspSample(elapsed, counters)
    }

    if !AgentLoopLspClientIsOpened(client, uri) {
        AgentLoopLspClientOpenFile(client, original, uri)
    }
    diagnosticMarker := AgentLoopLspFreshDiagnosticMarker(sample, operation)
    edited := AgentLoopLspEdit(original, sample, diagnosticMarker)
    client.Version = client.Version + 1
    change := AgentLoopLspObject()
    textDocument := AgentLoopLspObject()
    textDocument["uri"] = uri
    textDocument["version"] = client.Version
    change["textDocument"] = textDocument
    contentChange := AgentLoopLspObject()
    contentChange["text"] = edited
    contentChanges := new List<Dictionary<string, object?>>()
    contentChanges.Add(contentChange)
    change["contentChanges"] = contentChanges

    if operation == "LSP didChange diagnostics" {
        started := Stopwatch.GetTimestamp()
        AgentLoopLspClientNotify(client, "textDocument/didChange", change)
        diagnostics := AgentLoopLspClientWaitForDiagnostics(client, uri, client.Version, diagnosticMarker, 120000)
        elapsed := AgentLoopLspElapsedMilliseconds(started)
        counters := AgentLoopLspClientReadLogCounters(client, operation)
        counters.DocumentsUpdated = 1
        counters.DiagnosticsPublished = diagnostics
        counters.FreshDiagnosticsVerified = 1
        return new AgentLoopLspSample(elapsed, counters)
    }

    AgentLoopLspClientNotify(client, "textDocument/didChange", change)
    AgentLoopLspClientWaitForDiagnostics(client, uri, client.Version, diagnosticMarker, 120000)
    AgentLoopLspClientReadLogCounters(client, operation)
    token := AgentLoopLspToken(source)
    position := AgentLoopLspTokenPosition(edited, token)
    requestMethod := "textDocument/hover"
    if operation == "LSP completion after edit" {
        requestMethod = "textDocument/completion"
    }
    parameters := AgentLoopLspTextDocumentPosition(uri, position)
    if requestMethod == "textDocument/completion" {
        context := AgentLoopLspObject()
        context["triggerKind"] = 1
        parameters["context"] = context
    }
    requestId := client.NextRequestId
    client.NextRequestId = client.NextRequestId + 1
    request := AgentLoopLspString(requestMethod)
    request["id"] = requestId
    request["params"] = parameters
    started := Stopwatch.GetTimestamp()
    AgentLoopLspClientSend(client, request)
    timer := Stopwatch.StartNew()
    while timer.ElapsedMilliseconds < 120000 {
        incoming := AgentLoopLspClientReadMessage(client, 120000 - Convert.ToInt32(timer.ElapsedMilliseconds))
        responseDocument := JsonDocument.Parse(incoming)
        responseRoot := responseDocument.RootElement
        responseId: JsonElement = default
        if responseRoot.TryGetProperty("id", out responseId) && responseId.ValueKind == JsonValueKind.Number && responseId.GetInt32() == requestId {
            errorElement: JsonElement = default
            if responseRoot.TryGetProperty("error", out errorElement) {
                errorText := errorElement.ToString()
                responseDocument.Dispose()
                throw new InvalidOperationException(requestMethod + " failed: " + errorText)
            }
            result: JsonElement = default
            if !responseRoot.TryGetProperty("result", out result) || result.ValueKind == JsonValueKind.Null {
                responseDocument.Dispose()
                throw new InvalidOperationException(requestMethod + " returned no result for " + source)
            }
            responseDocument.Dispose()
            elapsed := AgentLoopLspElapsedMilliseconds(started)
            counters := AgentLoopLspClientReadLogCounters(client, operation)
            counters.FreshDiagnosticsVerified = 1
            return new AgentLoopLspSample(elapsed, counters)
        }
        client.PendingMessages.Add(incoming)
        responseDocument.Dispose()
    }
    throw new TimeoutException("Timed out waiting for Language Server request '" + requestMethod + "'.")
}

func AgentLoopLspClientClose(client: AgentLoopLspClient) {
    child := client.ChildProcess
    if child == null {
        return
    }
    process := child ?? throw new InvalidOperationException("Language Server process is not running.")
    if !process.HasExited {
        try {
            AgentLoopLspClientRequest(client, "shutdown", AgentLoopLspObject(), 10000)
            AgentLoopLspClientNotify(client, "exit", AgentLoopLspObject())
            if !process.WaitForExit(10000) {
                process.Kill(true)
                process.WaitForExit()
            }
        } catch closeFailure: Exception {
            try {
                if !process.HasExited {
                    process.Kill(true)
                    process.WaitForExit()
                }
            } catch ignored: Exception {
                if !process.HasExited {
                    throw ignored
                }
            }
        }
    }
    process.Dispose()
    client.ChildProcess = null
    if Directory.Exists(client.Home) {
        Directory.Delete(client.Home, true)
    }
}
func AgentLoopLspToken(source: string): string {
    name := Path.GetFileNameWithoutExtension(source) ?? ""
    number := name.Substring("Module".Length)
    return "Score" + number + "_00"
}

func AgentLoopLspTokenPosition(text: string, token: string): Dictionary<string, object?> {
    tokenOffset := text.IndexOf(token, StringComparison.Ordinal)
    if tokenOffset < 0 {
        throw new InvalidOperationException("The Language Server benchmark token '" + token + "' was not found.")
    }
    positionOffset := tokenOffset + Math.Max(1, token.Length - 2)
    prefix := text.Substring(0, positionOffset)
    lines := prefix.Split('\n')
    result := new Dictionary<string, object?>()
    result["line"] = lines.Length - 1
    result["character"] = lines[lines.Length - 1].Length
    return result
}

func AgentLoopLspTextDocumentPosition(uri: string, position: Dictionary<string, object?>): Dictionary<string, object?> {
    document := AgentLoopLspObject()
    document["uri"] = uri
    parameters := AgentLoopLspObject()
    parameters["textDocument"] = document
    parameters["position"] = position
    return parameters
}

func AgentLoopLspEdit(source: string, sample: int, diagnosticMarker: string): string {
    anchor := "seed + 0"
    index := source.IndexOf(anchor, StringComparison.Ordinal)
    if index < 0 {
        throw new InvalidOperationException("The Language Server benchmark edit anchor 'seed + 0' was not found.")
    }
    after := index + anchor.Length
    if after < source.Length && Char.IsDigit(source[after]) {
        throw new InvalidOperationException("The Language Server benchmark edit anchor was not unique.")
    }
    return source.Substring(0, index) + "seed + " + (1000 + sample).ToString(CultureInfo.InvariantCulture) + " + " + diagnosticMarker + source.Substring(after)
}

func AgentLoopLspFreshDiagnosticMarker(sample: int, operation: string): string {
    suffix := "Change"
    if operation == "LSP completion after edit" {
        suffix = "Completion"
    } else if operation == "LSP hover" {
        suffix = "Hover"
    }
    return "AgentLoopFreshProbe" + suffix + sample.ToString(CultureInfo.InvariantCulture)
}

func AgentLoopLspMeasure(
    headServerDll: string,
    baseServerDll: string,
    project: string,
    iterations: int,
    paired: bool,
    pairedSamples: int
): string {
    sources := Directory.GetFiles(project, "Module*.nl", SearchOption.TopDirectoryOnly)
    Array.Sort(sources, StringComparer.Ordinal)
    sourceFiles := new List<string>()
    for source in sources {
        sourceFiles.Add(source)
    }
    requiredFiles := iterations
    if paired && pairedSamples > requiredFiles {
        requiredFiles = pairedSamples
    }
    if sourceFiles.Count < requiredFiles {
        throw new InvalidOperationException("The generated project has too few source files for distinct unchanged didOpen samples.")
    }
    if !File.Exists(headServerDll) {
        throw new FileNotFoundException("Language Server assembly not found.", headServerDll)
    }
    if paired && !File.Exists(baseServerDll) {
        throw new FileNotFoundException("Base Language Server assembly not found.", baseServerDll)
    }

    head := new AgentLoopLspClient(project, "head")
    baselineClient: AgentLoopLspClient? = null
    if paired {
        baselineClient = new AgentLoopLspClient(project, "base")
    }
    operations := AgentLoopLspOperations()
    headSamples := new List<List<AgentLoopLspSample>>()
    baseSamples := new List<List<AgentLoopLspSample>>()
    operationIndex := 0
    while operationIndex < operations.Count {
        headSamples.Add(new List<AgentLoopLspSample>())
        baseSamples.Add(new List<AgentLoopLspSample>())
        operationIndex = operationIndex + 1
    }
    try {
        AgentLoopLspClientStart(head, headServerDll, sourceFiles)
        if paired {
            AgentLoopLspClientStart(baselineClient ?? throw new InvalidOperationException("Base client was not created."), baseServerDll, sourceFiles)

            // Discard the first paired pass per operation to warm both live servers, matching the
            // CLI relative gate. Its didOpen target sits beyond the measured pair range, so every
            // timed didOpen still opens a fresh document.
            warmupSample := pairedSamples
            operationIndex = 0
            while operationIndex < operations.Count {
                AgentLoopLspClientMeasure(baselineClient ?? throw new InvalidOperationException("Base client was not created."), operations[operationIndex], warmupSample, sourceFiles)
                AgentLoopLspClientMeasure(head, operations[operationIndex], warmupSample, sourceFiles)
                operationIndex = operationIndex + 1
            }
        }
        if !paired {
            // The first didChange also proves that the workspace snapshot and retained incremental
            // project session are ready. Keep this cold startup pass outside the structural samples
            // so the body-edit row describes a warm editing session.
            warmupSample := sourceFiles.Count
            operationIndex = 0
            while operationIndex < operations.Count {
                operationWarmupSample := warmupSample
                if operations[operationIndex] == "LSP unchanged didOpen" {
                    operationWarmupSample = 0
                }
                AgentLoopLspClientMeasure(head, operations[operationIndex], operationWarmupSample, sourceFiles)
                operationIndex = operationIndex + 1
            }

            sample := 0
            while sample < iterations {
                operationIndex = 0
                while operationIndex < operations.Count {
                    headSamples[operationIndex].Add(AgentLoopLspClientMeasure(head, operations[operationIndex], sample, sourceFiles))
                    operationIndex = operationIndex + 1
                }
                sample = sample + 1
            }
        } else {
            sample := 0
            // Always collect the full odd sample set. The LSP rows are short and can contain
            // unrelated queued-notification noise; a fixed count gives their sign interval the
            // same evidence on every paired run.
            while sample < pairedSamples {
                first := head
                second := baselineClient ?? throw new InvalidOperationException("Base client was not created.")
                if sample % 2 == 1 {
                    first = second
                    second = head
                }
                operationIndex = 0
                while operationIndex < operations.Count {
                    if first == head {
                        headSamples[operationIndex].Add(AgentLoopLspClientMeasure(head, operations[operationIndex], sample, sourceFiles))
                        secondSample := AgentLoopLspClientMeasure(second, operations[operationIndex], sample, sourceFiles)
                        baseSamples[operationIndex].Add(secondSample)
                    } else {
                        baseSamples[operationIndex].Add(AgentLoopLspClientMeasure(first, operations[operationIndex], sample, sourceFiles))
                        headSamples[operationIndex].Add(AgentLoopLspClientMeasure(second, operations[operationIndex], sample, sourceFiles))
                    }
                    operationIndex = operationIndex + 1
                }
                sample = sample + 1
            }
        }

        rows := new List<AgentLoopLspOutputRow>()
        operationIndex = 0
        while operationIndex < operations.Count {
            if headSamples[operationIndex].Count == 0 {
                throw new InvalidOperationException("No Language Server samples were recorded for " + operations[operationIndex] + ".")
            }
            firstCounters := headSamples[operationIndex][0].Counters
            i := 1
            while i < headSamples[operationIndex].Count {
                sampleCounters := headSamples[operationIndex][i].Counters
                if !AgentLoopLspCountersEqual(firstCounters, sampleCounters) {
                    throw new InvalidOperationException(
                        operations[operationIndex] + " structural counters varied at sample " + i.ToString(CultureInfo.InvariantCulture) + ": expected " + AgentLoopLspCountersText(firstCounters) + ", observed " + AgentLoopLspCountersText(sampleCounters) + "."
                    )
                }
                i = i + 1
            }
            rows.Add(new AgentLoopLspOutputRow(operations[operationIndex], headSamples[operationIndex], baseSamples[operationIndex], firstCounters))
            operationIndex = operationIndex + 1
        }
        output := new AgentLoopLspOutput(project, sourceFiles.Count, rows)
        options := new JsonSerializerOptions { PropertyNamingPolicy: JsonNamingPolicy.CamelCase, IncludeFields: true }
        return JsonSerializer.Serialize<AgentLoopLspOutput>(output, options)
    } finally {
        AgentLoopLspClientClose(head)
        if baselineClient != null {
            AgentLoopLspClientClose(baselineClient ?? throw new InvalidOperationException("Base client disappeared."))
        }
    }
}

func AgentLoopLspBelowWorkTarget(
    head: List<List<AgentLoopLspSample>>,
    baselineSamples: List<List<AgentLoopLspSample>>,
    operationCount: int,
    pairs: int,
    targetMilliseconds: long
): bool {
    operation := 0
    while operation < operationCount {
        headTotal := 0L
        baseTotal := 0L
        i := 0
        while i < pairs {
            headTotal = headTotal + head[operation][i].WallMs
            baseTotal = baseTotal + baselineSamples[operation][i].WallMs
            i = i + 1
        }
        if headTotal < targetMilliseconds || baseTotal < targetMilliseconds {
            return true
        }
        operation = operation + 1
    }
    return false
}

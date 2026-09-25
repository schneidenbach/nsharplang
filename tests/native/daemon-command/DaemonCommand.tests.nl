namespace NSharpLang.DaemonCommand.Tests

import System
import System.Diagnostics
import System.IO
import System.Text.Json
import NSharpLang.Cli.Daemon

// The 28 rows of `tests/DaemonCommandTests.cs`, preserved one-for-one. `DaemonHarness.nl` carries
// the header explaining why six of them became child-process runs of the shipped `nlc` binary and
// why the rest still call the daemon types directly.

// ═══ HELP AND DISPATCH ════════════════════════════════════════════════════════════════════════
//
// Four rows that only ever read stdout. Run against the real binary they prove something the
// deleted C#'s in-process `DaemonCommand.Execute(...)` could not: that `nlc daemon` REACHES
// `DaemonCommand` at all.
test "nlc daemon with no subcommand prints its usage and exits 0" {
    run := Nlc("daemon", Path.GetTempPath())

    assert run.ExitCode == 0
    assert run.Stdout.Contains("Usage: nlc daemon")
}

test "nlc daemon --help lists start stop and status and exits 0" {
    run := Nlc("daemon --help", Path.GetTempPath())

    assert run.ExitCode == 0
    assert run.Stdout.Contains("Usage: nlc daemon")
    assert run.Stdout.Contains("start")
    assert run.Stdout.Contains("stop")
    assert run.Stdout.Contains("status")
}

test "nlc daemon help prints the same usage as the help flag and exits 0" {
    run := Nlc("daemon help", Path.GetTempPath())

    assert run.ExitCode == 0
    assert run.Stdout.Contains("Usage: nlc daemon")
}

test "nlc daemon with an unrecognised subcommand falls back to the usage and exits 0" {
    run := Nlc("daemon bogus", Path.GetTempPath())

    assert run.ExitCode == 0
    assert run.Stdout.Contains("Usage: nlc daemon")
}

// ═══ STOP AND STATUS WITH NOTHING RUNNING ═════════════════════════════════════════════════════

test "nlc daemon stop reports no daemon running and exits 0 when none is listening" {
    directory := NewTempDirectory()
    try {
        run := Nlc("daemon stop --project " + Quote(directory), directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("No daemon running")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "nlc daemon status reports no daemon running and exits 0 when none is listening" {
    directory := NewTempDirectory()
    try {
        run := Nlc("daemon status --project " + Quote(directory), directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("No daemon running")
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ THE SOCKET PATH CONVENTION ═══════════════════════════════════════════════════════════════

test "asking for a project's socket path creates its .nlc directory and names the socket daemon.sock" {
    directory := NewTempDirectory()
    try {
        socketPath := DaemonConstants.GetSocketPath(directory)

        assert Directory.Exists(Path.Combine(directory, ".nlc"))
        assert socketPath.EndsWith("daemon.sock")
        assert socketPath.StartsWith(directory)
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "a project path too long for a unix socket name falls back to the shared nlc-daemon runtime root" {
    directory := Path.Combine("/tmp", "nlc-" + Repeated('x', 120))
    Directory.CreateDirectory(directory)
    try {
        socketPath := DaemonConstants.GetSocketPath(directory)

        assert Utf8ByteCount(socketPath) <= 100
        assert socketPath.Contains("nlc-daemon")
        assert socketPath.EndsWith("daemon.sock")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "the daemon method names are the twelve fixed json-rpc method strings" {
    assert DaemonConstants.MethodPing == "daemon/ping"
    assert DaemonConstants.MethodShutdown == "daemon/shutdown"
    assert DaemonConstants.MethodStatus == "daemon/status"
    assert DaemonConstants.MethodSymbols == "query/symbols"
    assert DaemonConstants.MethodBatch == "query/batch"
    assert DaemonConstants.MethodOutline == "query/outline"
    assert DaemonConstants.MethodDiagnostics == "query/diagnostics"
    assert DaemonConstants.MethodType == "query/type"
    assert DaemonConstants.MethodDefinition == "query/definition"
    assert DaemonConstants.MethodReferences == "query/references"
    assert DaemonConstants.MethodCompletions == "query/completions"
    assert DaemonConstants.MethodInspect == "query/inspect"
}

test "every daemon timeout constant is a positive duration" {
    assert DaemonConstants.IdleTimeoutMinutes > 0
    assert DaemonConstants.ConnectionTimeoutMs > 0
    assert DaemonConstants.PingTimeoutMs > 0
}

// ═══ THE CLIENT WITH NO SOCKET ════════════════════════════════════════════════════════════════

test "the client reports no daemon running when the project has no socket file" {
    directory := NewTempDirectory()
    try {
        assert !DaemonClient.IsRunning(directory)
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "a query against a project with no socket file answers null rather than throwing" {
    directory := NewTempDirectory()
    try {
        assert DaemonClient.Query(directory, DaemonConstants.MethodPing) == null
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "stopping a daemon that was never started answers false" {
    directory := NewTempDirectory()
    try {
        assert !DaemonClient.StopDaemon(directory)
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "asking for the status of a daemon that was never started answers null" {
    directory := NewTempDirectory()
    try {
        assert DaemonClient.GetStatus(directory) == null
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ STALE SOCKET CLEANUP ═════════════════════════════════════════════════════════════════════

test "a socket file left behind by a dead daemon is reported not running and deleted" {
    directory := NewTempDirectory()
    try {
        socketPath := DaemonConstants.GetSocketPath(directory)
        File.WriteAllText(socketPath, "stale")

        assert !DaemonClient.IsRunning(directory)
        assert !File.Exists(socketPath)
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "a query through a socket file left behind by a dead daemon answers null" {
    directory := NewTempDirectory()
    try {
        socketPath := DaemonConstants.GetSocketPath(directory)
        File.WriteAllText(socketPath, "stale")

        assert DaemonClient.Query(directory, DaemonConstants.MethodPing) == null
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ THE JSON-RPC ENVELOPE ════════════════════════════════════════════════════════════════════

test "a daemon request round-trips through json carrying the 2.0 protocol version by default" {
    request := new DaemonRequest { Id: 42, Method: "daemon/ping" }

    json := JsonSerializer.Serialize<DaemonRequest>(request)
    deserialized := JsonSerializer.Deserialize<DaemonRequest>(json)

    assert deserialized != null
    assert deserialized.JsonRpc == "2.0"
    assert deserialized.Id == 42
    assert deserialized.Method == "daemon/ping"
}

test "a successful daemon response round-trips its result and leaves the error member null" {
    response := new DaemonResponse { Id: 1, Result: "\"pong\"" }

    json := JsonSerializer.Serialize<DaemonResponse>(response)
    deserialized := JsonSerializer.Deserialize<DaemonResponse>(json)

    assert deserialized != null
    assert deserialized.Id == 1
    assert deserialized.Result == "\"pong\""
    assert deserialized.Error == null
}

test "a failing daemon response round-trips its error code and message and leaves the result null" {
    response := new DaemonResponse { Id: 2, Error: new DaemonError { Code: -1, Message: "test error" } }

    json := JsonSerializer.Serialize<DaemonResponse>(response)
    deserialized := JsonSerializer.Deserialize<DaemonResponse>(json)

    assert deserialized != null
    assert deserialized.Id == 2
    assert deserialized.Result == null
    assert deserialized.Error != null
    assert deserialized.Error.Code == -1
    assert deserialized.Error.Message == "test error"
}

// ═══ THE PID FILE CONVENTION ══════════════════════════════════════════════════════════════════

test "the socket and pid files of a project both sit directly inside its .nlc directory" {
    directory := NewTempDirectory()
    try {
        socketPath := DaemonConstants.GetSocketPath(directory)
        pidPath := Path.Combine(Path.GetDirectoryName(socketPath) ?? "", "daemon.pid")

        assert socketPath == Path.Combine(Path.Combine(directory, ".nlc"), "daemon.sock")
        assert pidPath == Path.Combine(Path.Combine(directory, ".nlc"), "daemon.pid")

        File.WriteAllText(socketPath, "socket-placeholder")
        File.WriteAllText(pidPath, "99999")
        assert File.Exists(socketPath)
        assert File.Exists(pidPath)
    } finally {
        DeleteTempDirectory(directory)
    }
}

// ═══ THE RUNNING DAEMON ═══════════════════════════════════════════════════════════════════════

test "a running daemon writes its socket and pid answers ping and status and removes both files on stop" {
    projectDirectory := NewTempProject()
    server := StartDaemonServer(projectDirectory)
    try {
        socketPath := DaemonConstants.GetSocketPath(projectDirectory)
        pidPath := Path.Combine(Path.GetDirectoryName(socketPath) ?? "", "daemon.pid")

        assert File.Exists(socketPath)
        assert File.Exists(pidPath)

        pid := 0
        assert Int32.TryParse(File.ReadAllText(pidPath), out pid)
        assert pid > 0

        assert DaemonClient.Query(projectDirectory, DaemonConstants.MethodPing) == "\"pong\""

        assert StatusText(projectDirectory, DaemonProtocolKernels.GetStatusProjectRootField()) == projectDirectory
        assert StatusNumber(projectDirectory, DaemonProtocolKernels.GetStatusPidField()) == pid
        assert StatusText(projectDirectory, DaemonProtocolKernels.GetStatusIdleTimeoutField()) == DaemonProtocolKernels.FormatIdleTimeoutMinutes(DaemonConstants.IdleTimeoutMinutes)

        assert DaemonClient.StopDaemon(projectDirectory)
        assert WaitUntil(() => !File.Exists(socketPath) && !File.Exists(pidPath), 5000)
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

test "a running daemon answers an unknown method and unparseable bytes with structured json-rpc errors" {
    projectDirectory := NewTempProject()
    server := StartDaemonServer(projectDirectory)
    try {
        unknown := DaemonClient.QueryResponse(projectDirectory, "daemon/nope")
        assert unknown != null
        assert unknown.Error != null
        assert unknown.JsonRpc == "2.0"
        assert unknown.Error.Code == DaemonConstants.ErrorMethodNotFound
        // The expected sentence is the LITERAL, not a live call to the kernel that produces it:
        // that pairing agrees by construction and never says what the wire message is. The kernel
        // side is pinned independently in the compiler-service estate's daemon kernel contracts.
        assert unknown.Error.Message == "Unknown method: daemon/nope"

        malformedJson := SendRawDaemonRequest(projectDirectory, "{not json")
        malformed := JsonSerializer.Deserialize<DaemonResponse>(malformedJson)
        assert malformed != null
        assert malformed.Error != null
        assert malformed.Error.Code == DaemonConstants.ErrorParse
        assert malformed.Error.Message == "Malformed daemon request JSON."
        assert malformed.Error.Data != null
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

test "an unknown query method is refused before the daemon ever loads the project" {
    projectDirectory := NewTempDirectory()
    server := StartDaemonServer(projectDirectory)
    try {
        unknown := DaemonClient.QueryResponse(projectDirectory, "query/not-real")
        assert unknown != null
        assert unknown.Error != null
        assert unknown.Error.Code == DaemonConstants.ErrorMethodNotFound
        // The LITERAL, for the same reason as above.
        assert unknown.Error.Message == "Unknown method: query/not-real"
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

test "nlc query diagnostics --clusters keeps the cluster envelope while a daemon is serving the project" {
    projectDirectory := NewTempDirectory()
    File.WriteAllText(
        Path.Combine(projectDirectory, "project.yml"),
        "name: DaemonDiagnosticClusters\noutputType: exe\ntargetFramework: net10.0\n"
    )
    File.WriteAllText(
        Path.Combine(projectDirectory, "Program.nl"),
        "func Main() {\n    Console.WriteLine(undefinedDaemonCluster)\n}\n"
    )

    server := StartDaemonServer(projectDirectory)
    try {
        run := Nlc("query diagnostics --clusters --project " + Quote(projectDirectory), projectDirectory)

        assert run.ExitCode == 1
        assert !run.Stderr.ToLowerInvariant().Contains("\"error\"")

        document := JsonDocument.Parse(run.Stdout)
        try {
            root := document.RootElement
            assert TextOf(root.GetProperty("command")) == "diagnostics.clusters"
            assert !root.GetProperty("ok").GetBoolean()
            assert HasProperty(root, "clusters")
            assert root.GetProperty("clusters").ValueKind == JsonValueKind.Array
            assert !HasProperty(root, "results")
        } finally {
            document.Dispose()
        }
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

test "a daemon query with an unparseable position falls back to zero for only the broken component" {
    projectDirectory := NewTempProject()
    server := StartDaemonServer(projectDirectory)
    try {
        lineFallback := DaemonClient.Query(projectDirectory, DaemonConstants.MethodType, FilePositionParameters("Program.nl", "bad:5"))
        assert lineFallback != null
        assert PositionComponent(lineFallback, "line") == 0
        assert PositionComponent(lineFallback, "column") == 5

        columnFallback := DaemonClient.Query(projectDirectory, DaemonConstants.MethodType, FilePositionParameters("Program.nl", "5:bad"))
        assert columnFallback != null
        assert PositionComponent(columnFallback, "line") == 5
        assert PositionComponent(columnFallback, "column") == 0
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

test "a daemon symbols query filtered by kind returns only symbols of that kind" {
    projectDirectory := NewTempProject()
    server := StartDaemonServer(projectDirectory)
    try {
        symbolsJson := DaemonClient.Query(projectDirectory, DaemonConstants.MethodSymbols, QueryParameters("kind", "class"))
        assert symbolsJson != null

        document := JsonDocument.Parse(symbolsJson)
        try {
            symbols := document.RootElement.GetProperty("results")
            assert ElementCount(symbols) > 0
            assert EveryElementHasStringProperty(symbols, "kind", "class")
        } finally {
            document.Dispose()
        }
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

test "a daemon reloads its snapshot when a new .nl file appears in the watched project" {
    projectDirectory := NewTempProject()
    server := StartDaemonServer(projectDirectory)
    try {
        assert DaemonClient.Query(projectDirectory, DaemonConstants.MethodDiagnostics) != null
        cachedBefore := CachedFileCount(projectDirectory)
        assert cachedBefore > 0

        File.WriteAllText(
            Path.Combine(projectDirectory, "WatcherAdded.nl"),
            "namespace IssueTracker\n\nclass WatcherAdded {\n}\n"
        )

        assert WaitUntil(() => DaemonClient.Query(projectDirectory, DaemonConstants.MethodDiagnostics) != null && CachedFileCount(projectDirectory) > cachedBefore, 15000)
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

test "a daemon whose idle timeout elapses shuts itself down and removes its socket" {
    projectDirectory := NewTempProject()
    socketPath := DaemonConstants.GetSocketPath(projectDirectory)
    server := StartDaemonServerWithIdleTimeout(projectDirectory, 200.0, 25.0)
    try {
        assert File.Exists(socketPath)
        assert WaitUntil(() => !File.Exists(socketPath), 10000)
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

// ═══ WHAT THE SERVER ITSELF BUILDS ════════════════════════════════════════════════════════════
//
// Four rows added when `DaemonServer` moved out of C# and into
// `src/NSharpLang.Compiler/DaemonServer.nl`. Each one pins a payload the C# built with an ANONYMOUS
// TYPE — a shape N# has no spelling for, so each became a written-out carrier — or a value the
// server can only get from the operating system. Nothing here agrees with the owner by
// construction: every expected key and every bound is written as a literal.

test "a malformed daemon request reports the path, line and byte position where the bytes stopped being JSON" {
    projectDirectory := NewTempProject()
    server := StartDaemonServer(projectDirectory)
    try {
        malformedJson := SendRawDaemonRequest(projectDirectory, "{\"jsonrpc\":\"2.0\",\"id\":4,")
        document := JsonDocument.Parse(malformedJson)
        try {
            data := document.RootElement.GetProperty("error").GetProperty("data")

            // The three member names are CAMEL-CASED by the daemon's serializer options, exactly as
            // they were when this payload was a C# anonymous type over `JsonException`.
            assert HasProperty(data, "path")
            assert HasProperty(data, "lineNumber")
            assert HasProperty(data, "bytePositionInLine")
            assert !HasProperty(data, "Path")
            assert !HasProperty(data, "LineNumber")

            // The request is one line long and ends after 24 bytes, so the position is reported on
            // line 0 and cannot be zero bytes in.
            assert data.GetProperty("lineNumber").GetInt64() == 0
            assert data.GetProperty("bytePositionInLine").GetInt64() > 0
        } finally {
            document.Dispose()
        }
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

// The daemon under test runs on a thread of THIS process, so the uptime it reports must be this
// process's own age. A counter that started when the server object was constructed would read a
// second or two; the real answer is however long the test host has been alive, and this row is
// written so that only the real answer passes.
test "daemon status reports the age of the serving process, not the age of the server object" {
    projectDirectory := NewTempProject()
    startedAt := Process.GetCurrentProcess().StartTime.ToUniversalTime()
    expectedSeconds := (long)(DateTime.UtcNow - startedAt).TotalSeconds
    server := StartDaemonServer(projectDirectory)
    try {
        uptime := StatusText(projectDirectory, "uptime")
        reportedSeconds := UptimeTextToSeconds(uptime)

        // Within ten seconds of the age measured just above, and never the near-zero a per-object
        // counter would give for a host that has already been running for a while.
        assert reportedSeconds >= expectedSeconds
        assert reportedSeconds - expectedSeconds <= 10
        assert StatusNumber(projectDirectory, "pid") == Environment.ProcessId
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

// `QueryErrorDetailKernels.Position` — what the in-process `nlc query` route uses — NORMALIZES the
// path it echoes. The daemon never did: its detail payload was a C# anonymous type built straight
// from the request parameter. This row sends a spelling the normalizer would change and requires it
// back unchanged, so the two routes keep the difference they have always had.
test "a daemon type query with no symbol echoes the file parameter exactly as the client spelled it" {
    projectDirectory := NewTempProject()
    server := StartDaemonServer(projectDirectory)
    try {
        response := DaemonClient.Query(
            projectDirectory,
            DaemonConstants.MethodType,
            FilePositionParameters("sub\\Missing.nl", "1:1")
        )
        assert response != null

        document := JsonDocument.Parse(response)
        try {
            details := document.RootElement.GetProperty("error").GetProperty("details")
            assert TextOf(details.GetProperty("file")) == "sub\\Missing.nl"
            assert details.GetProperty("position").GetProperty("line").GetInt32() == 1
            assert details.GetProperty("position").GetProperty("column").GetInt32() == 1
            assert TextOf(document.RootElement.GetProperty("error").GetProperty("code")) == "noSymbol"
        } finally {
            document.Dispose()
        }
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

// A parameter whose JSON type the server cannot read is TOLERATED — the request is still answered
// as though the parameter were absent — rather than failing the whole call. `kind` is a string
// slot; sending a number must not turn a symbols query into an error response.
test "a daemon parameter of the wrong json type is treated as absent instead of failing the request" {
    projectDirectory := NewTempProject()
    server := StartDaemonServer(projectDirectory)
    try {
        wrongTypeJson := SendRawDaemonRequest(
            projectDirectory,
            "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"query/symbols\",\"params\":{\"kind\":42}}"
        )
        wrongType := JsonSerializer.Deserialize<DaemonResponse>(wrongTypeJson)
        assert wrongType != null
        assert wrongType.Error == null
        assert wrongType.Result != null

        unfilteredJson := DaemonClient.Query(projectDirectory, DaemonConstants.MethodSymbols)
        assert unfilteredJson != null

        // Same answer as asking with no `kind` at all: the broken filter was dropped, not applied.
        assert wrongType.Result == unfilteredJson
    } finally {
        server.Stop()
        DeleteTempDirectory(projectDirectory)
    }
}

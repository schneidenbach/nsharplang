namespace NSharpLang.Cli.Commands

import System.Text.Json

// THE `nlc daemon` CLIENT AND SERVER MESSAGE KERNELS.
//
// These blocks replace TWO `[Fact]`s deleted from `tests/DaemonCommandTests.cs`:
// `DaemonClientKernels_ShapesClientMessages` (15 declaration lines, 4 `Assert.` rows) and
// `DaemonServerKernels_ShapesQueryMessages` (30 lines, 23 rows). Both are pure — a static call
// with literal arguments and a string answer — so both migrate whole.
//
// THEY ARE THE LAST TWO BUCKET-(a) BODIES IN THAT FILE THAT COULD MOVE. The other two name
// `DaemonServerKernels` only to build an EXPECTATION for a message read off a live unix socket;
// their subject is `DaemonServer`, which is C#. Those two keep their rows and lose the tautology:
// the kernel call becomes the literal it returns, which is what these blocks pin here. So the
// same sentence is now stated independently on both sides of the socket, and neither can drift
// into agreement with a wrong answer.

// ── the client's four sentences ───────────────────────────────────────────────

test "the daemon client's failure sentences are exactly these" {
    assert DaemonClientKernels.GetConnectionErrorMessage("socket refused") == "[daemon] Connection error: socket refused"
    assert DaemonClientKernels.GetExecutablePathMissingMessage() == "Cannot determine executable path for daemon"
    assert DaemonClientKernels.GetStartTimeoutMessage() == "Daemon started but not responding within 5 seconds"
    assert DaemonClientKernels.GetStartFailedWithReasonMessage("denied") == "Failed to start daemon: denied"
}

test "the two client sentences that take a reason really use it" {
    // A CONTROL THE DELETED BODY DID NOT HAVE: it passed one value to each, so a kernel that
    // ignored its argument and hard-coded the sentence would have passed both rows.
    assert DaemonClientKernels.GetConnectionErrorMessage("broken pipe") == "[daemon] Connection error: broken pipe"
    assert DaemonClientKernels.GetStartFailedWithReasonMessage("no such file") == "Failed to start daemon: no such file"
}

// ── the server's protocol sentences ───────────────────────────────────────────

test "the daemon server's protocol refusals are exactly these" {
    assert DaemonServerKernels.GetUnknownMethodMessage("query/nope") == "Unknown method: query/nope"
    assert DaemonServerKernels.GetFailedLoadProjectMessage() == "Failed to load project"
    assert DaemonServerKernels.GetEmptyBatchPayloadMessage() == "Batch request payload did not contain any requests."
    assert DaemonServerKernels.GetFileParameterRequiredMessage() == "file parameter required"
    assert DaemonServerKernels.GetFileAndPosParametersRequiredMessage() == "file and pos parameters required"
    assert DaemonServerKernels.GetDefinitionTargetRequiredMessage() == "file+pos or name required"
    assert DaemonServerKernels.GetFileAndPosRequiredMessage() == "file and pos required"
    assert DaemonServerKernels.GetNoSymbolAtPositionMessage("Program.nl", 5, 12) == "No symbol found at Program.nl:5:12"
    assert DaemonServerKernels.GetSemanticReferencesUnavailableMessage() == "Semantic references are unavailable because the selected position is not backed by a precise compiler binding. No name-based or text-based fallback was used."
}

test "the unknown-method sentence echoes the method it was given, whatever its shape" {
    // THE SENTENCE THE TWO SURVIVING C# BODIES READ OFF THE SOCKET. It is pinned here as a pure
    // function of its argument, so those bodies can now assert the LITERAL rather than calling
    // this kernel to produce their own expectation.
    assert DaemonServerKernels.GetUnknownMethodMessage("daemon/nope") == "Unknown method: daemon/nope"
    assert DaemonServerKernels.GetUnknownMethodMessage("query/not-real") == "Unknown method: query/not-real"
    assert DaemonServerKernels.GetUnknownMethodMessage("") == "Unknown method: "
}

test "the no-symbol sentence formats BOTH coordinates, not just the file" {
    // A CONTROL THE DELETED BODY DID NOT HAVE: one call at 5:12, so a kernel that swapped line and
    // column would have passed it. Two asymmetric positions catch the swap.
    assert DaemonServerKernels.GetNoSymbolAtPositionMessage("Program.nl", 1, 40) == "No symbol found at Program.nl:1:40"
    assert DaemonServerKernels.GetNoSymbolAtPositionMessage("Program.nl", 40, 1) == "No symbol found at Program.nl:40:1"
}

// ── the server's trace lines ──────────────────────────────────────────────────

test "the daemon server's lifecycle trace lines are exactly these" {
    assert DaemonServerKernels.GetListeningMessage("/tmp/daemon.sock", 1234) == "[daemon] Listening on /tmp/daemon.sock (PID 1234)"
    assert DaemonServerKernels.GetProjectMessage("/tmp/project") == "[daemon] Project: /tmp/project"
    assert DaemonServerKernels.GetIdleTimeoutMessage("5m") == "[daemon] Idle timeout: 5m"
    assert DaemonServerKernels.GetIdleTimeoutShutdownMessage("5m") == "[daemon] Idle timeout (5m). Shutting down."
    assert DaemonServerKernels.GetShutdownCompleteMessage() == "[daemon] Shutdown complete."
}

test "the daemon server's error and project-loading trace lines are exactly these" {
    assert DaemonServerKernels.GetServerErrorMessage("boom") == "[daemon] Error: boom"
    assert DaemonServerKernels.GetClientErrorMessage("bad client") == "[daemon] Client error: bad client"
    assert DaemonServerKernels.GetLoadingProjectMessage() == "[daemon] Loading project..."
    assert DaemonServerKernels.GetProjectLoadedMessage(42, 3) == "[daemon] Project loaded in 42ms (3 files)"
    assert DaemonServerKernels.GetProjectLoadFailedTraceMessage("bad yaml") == "[daemon] Failed to load project: bad yaml"
}

test "the file-watcher trace lines are exactly these, and name the three watched patterns" {
    assert DaemonServerKernels.GetFileWatcherStartedMessage() == "[daemon] File watcher started for *.nl, project.yml, .editorconfig"
    assert DaemonServerKernels.GetFileWatcherFailedMessage("denied") == "[daemon] File watcher failed: denied"
    assert DaemonServerKernels.GetFileChangedMessage("Program.nl") == "[daemon] File changed: Program.nl — cache invalidated"
}

test "the malformed-parameter trace names the key, the expected type AND the reason" {
    assert DaemonServerKernels.GetMalformedRequestParamMessage("pos", "String", "invalid token") == "[daemon] Ignoring malformed request param 'pos' (expected String): invalid token"
    // A CONTROL THE DELETED BODY DID NOT HAVE: three arguments in one sentence is exactly the
    // shape a kernel can get subtly wrong by transposing two of them.
    assert DaemonServerKernels.GetMalformedRequestParamMessage("file", "Int32", "not a number") == "[daemon] Ignoring malformed request param 'file' (expected Int32): not a number"
}

test "the project-loaded trace really reads both of its numbers" {
    // The deleted body asked once with 42 and 3.
    assert DaemonServerKernels.GetProjectLoadedMessage(3, 42) == "[daemon] Project loaded in 3ms (42 files)"
    assert DaemonServerKernels.GetProjectLoadedMessage(0, 0) == "[daemon] Project loaded in 0ms (0 files)"
}

// ═══ THE WIRE PROTOCOL ═══════════════════════════════════════════════════════════
//
// EVERYTHING BELOW WAS UNPINNED BY THE ESTATE UNTIL THIS SLICE, AND THAT IS A MEASUREMENT. A census
// of `DaemonProtocolKernels`' 44 entry points against every `.tests.nl` in the repository found TWO
// named anywhere — `GetAlreadyRunningMessage` and `GetSocketPath` — and forty-two named nowhere.
// The only assertions that reached the rest were C# ones in `tests/DaemonCommandTests.cs`, which is
// itself deletion debt, and they did not reach far: the FIVE JSON-RPC error codes appear in no test
// anywhere in the repository, and `"shutting down"` appears in none either. `daemon/ping` could have
// been renamed and the whole suite would still have passed.
//
// WHY THAT MATTERS MORE HERE THAN FOR A SENTENCE. A daemon is a long-running server whose client is
// a separately-launched process: the two agree only because both were built from this source at the
// same moment. `AGENTS.md`'s schema discipline names exactly this surface — versioned and stable —
// and these blocks are where its stability is now stated.
//
// THE SPLIT THIS FILE DOES NOT PIN, AND WHY. The eleven member names of the JSON-RPC envelope
// itself — `jsonrpc`, `id`, `method`, `params`, `result`, `error`, `code`, `message`, `data` — live
// on `[JsonPropertyName]` attributes in `src/NSharpLang.Cli/Daemon/DaemonProtocol.cs`, and a C#
// attribute argument must be a compile-time constant, so they cannot be defined from a kernel in any
// language N# could grow. They are also not this product's to choose: the JSON-RPC 2.0
// specification fixes them, exactly as xUnit fixes the arity of its own `TraitAttribute`. What IS
// this product's to choose — the method names, the error codes it selects from the specification's
// range, the `daemon/status` payload, and the two control results — is all below.

// ── READING THE WIRE BACK ─────────────────────────────────────────────────────
//
// A `JsonElement.GetProperty` chain declines at `emit.call.instance-member-unmodeled` when it is
// written inline inside an `assert`; the spelling that emits is the one
// `OutputFormatterJsonKernels.tests.nl` already uses — a `func` whose body parses, binds the root to
// a local, and returns one value. Measured, not guessed.

func DpkString(json: string, key: string): string? {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(key).GetString()
}

func DpkInt(json: string, key: string): int {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(key).GetInt32()
}

func DpkNestedString(json: string, first: string, second: string): string? {
    document := JsonDocument.Parse(json)
    root := document.RootElement
    return root.GetProperty(first).GetProperty(second).GetString()
}

func DpkRootString(json: string): string? {
    document := JsonDocument.Parse(json)
    return document.RootElement.GetString()
}

test "the twelve daemon methods are exactly these strings" {
    assert DaemonProtocolKernels.GetPingMethod() == "daemon/ping"
    assert DaemonProtocolKernels.GetShutdownMethod() == "daemon/shutdown"
    assert DaemonProtocolKernels.GetStatusMethod() == "daemon/status"
    assert DaemonProtocolKernels.GetSymbolsMethod() == "query/symbols"
    assert DaemonProtocolKernels.GetBatchMethod() == "query/batch"
    assert DaemonProtocolKernels.GetOutlineMethod() == "query/outline"
    assert DaemonProtocolKernels.GetDiagnosticsMethod() == "query/diagnostics"
    assert DaemonProtocolKernels.GetTypeMethod() == "query/type"
    assert DaemonProtocolKernels.GetDefinitionMethod() == "query/definition"
    assert DaemonProtocolKernels.GetReferencesMethod() == "query/references"
    assert DaemonProtocolKernels.GetCompletionsMethod() == "query/completions"
    assert DaemonProtocolKernels.GetInspectMethod() == "query/inspect"
}

test "every method name dispatches to its OWN kind, and anything else is Unknown" {
    // The names above are only half the contract: `GetMethodKind` is the switch the server dispatches
    // on, so a name that no longer maps to its kind is a method that silently stops working.
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetPingMethod()) == DaemonMethodKind.Ping
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetShutdownMethod()) == DaemonMethodKind.Shutdown
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetStatusMethod()) == DaemonMethodKind.Status
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetSymbolsMethod()) == DaemonMethodKind.Symbols
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetBatchMethod()) == DaemonMethodKind.Batch
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetOutlineMethod()) == DaemonMethodKind.Outline
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetDiagnosticsMethod()) == DaemonMethodKind.Diagnostics
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetTypeMethod()) == DaemonMethodKind.Type
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetDefinitionMethod()) == DaemonMethodKind.Definition
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetReferencesMethod()) == DaemonMethodKind.References
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetCompletionsMethod()) == DaemonMethodKind.Completions
    assert DaemonProtocolKernels.GetMethodKind(DaemonProtocolKernels.GetInspectMethod()) == DaemonMethodKind.Inspect

    // The near misses matter as much as the hits: the dispatch is EXACT, not a prefix or a
    // case-insensitive match, so none of these three reaches a handler.
    assert DaemonProtocolKernels.GetMethodKind("daemon/pin") == DaemonMethodKind.Unknown
    assert DaemonProtocolKernels.GetMethodKind("DAEMON/PING") == DaemonMethodKind.Unknown
    assert DaemonProtocolKernels.GetMethodKind("query/symbols ") == DaemonMethodKind.Unknown
    assert !DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Unknown)
}

test "the five error codes are the JSON-RPC 2.0 numbers, and no two of them are the same" {
    // NOT ONE OF THESE FIVE WAS ASSERTED ANYWHERE IN THE REPOSITORY before this block. They are the
    // specification's own reserved codes, so a wrong one is not merely a different number — it tells
    // a conforming client the wrong thing about whose fault the failure was.
    assert DaemonProtocolKernels.GetParseErrorCode() == -32700
    assert DaemonProtocolKernels.GetInvalidRequestErrorCode() == -32600
    assert DaemonProtocolKernels.GetMethodNotFoundErrorCode() == -32601
    assert DaemonProtocolKernels.GetInvalidParamsErrorCode() == -32602
    assert DaemonProtocolKernels.GetInternalErrorCode() == -32603

    assert DaemonProtocolKernels.GetParseErrorCode() != DaemonProtocolKernels.GetInvalidRequestErrorCode()
    assert DaemonProtocolKernels.GetMethodNotFoundErrorCode() != DaemonProtocolKernels.GetInvalidParamsErrorCode()
    assert DaemonProtocolKernels.GetInvalidParamsErrorCode() != DaemonProtocolKernels.GetInternalErrorCode()
}

test "the protocol version is 2.0, and the error envelope is BUILT from that one word" {
    assert DaemonProtocolKernels.GetJsonRpcVersion() == "2.0"

    // The envelope N# composes by hand, stated as the exact bytes a client reads. `result` is
    // present and null on the error arm — `System.Text.Json` emits it on the server's arm too, so
    // the two spellings of the envelope agree on that as well.
    assert DaemonProtocolKernels.ErrorResponseJson(3, -32601, "Unknown method: query/not-real") == "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":null,\"error\":{\"code\":-32601,\"message\":\"Unknown method: query/not-real\"}}"

    // …and the version really comes from the kernel rather than being spelled twice: the envelope
    // contains the word the kernel answers, quoted.
    assert DaemonProtocolKernels.ErrorResponseJson(1, -1, "x").Contains("\"jsonrpc\":\"" + DaemonProtocolKernels.GetJsonRpcVersion() + "\"")
}

test "the error envelope really reads all three of its arguments" {
    // A CONTROL: one call cannot tell a kernel that uses its arguments from one that hard-codes an
    // envelope. Two calls that differ in every field can.
    assert DaemonProtocolKernels.ErrorResponseJson(0, -32700, "Malformed daemon request JSON.") == "{\"jsonrpc\":\"2.0\",\"id\":0,\"result\":null,\"error\":{\"code\":-32700,\"message\":\"Malformed daemon request JSON.\"}}"
    assert DaemonProtocolKernels.ErrorResponseJson(97, -32602, "file and pos required") == "{\"jsonrpc\":\"2.0\",\"id\":97,\"result\":null,\"error\":{\"code\":-32602,\"message\":\"file and pos required\"}}"

    // The message is JSON-ENCODED, not concatenated: a quote inside it cannot break the envelope.
    assert DpkNestedString(DaemonProtocolKernels.ErrorResponseJson(5, -32603, "he said \"no\""), "error", "message") == "he said \"no\""
}

test "the daemon/status payload is exactly these five members, in this order" {
    // THE FIVE NAMES ARE THIS PRODUCT'S OWN, unlike the envelope's. They were spelled TWICE until
    // this slice — once here and once on a C# `DaemonStatus` DTO with no production consumer — and
    // the DTO is gone, so this is now the only place the payload exists.
    assert DaemonProtocolKernels.StatusResultJson(4321, "1h 2m 3s", "/tmp/project", 7, "30m") == "{\"pid\":4321,\"uptime\":\"1h 2m 3s\",\"projectRoot\":\"/tmp/project\",\"cachedFiles\":7,\"idleTimeout\":\"30m\"}"

    // A CONTROL: every value moves independently, so a payload that transposed two of them fails.
    assert DaemonProtocolKernels.StatusResultJson(1, "0h 0m 9s", "/other", 0, "5m") == "{\"pid\":1,\"uptime\":\"0h 0m 9s\",\"projectRoot\":\"/other\",\"cachedFiles\":0,\"idleTimeout\":\"5m\"}"
}

test "the five status member names are the ones the field kernels spell" {
    assert DaemonProtocolKernels.GetStatusPidField() == "pid"
    assert DaemonProtocolKernels.GetStatusUptimeField() == "uptime"
    assert DaemonProtocolKernels.GetStatusProjectRootField() == "projectRoot"
    assert DaemonProtocolKernels.GetStatusCachedFilesField() == "cachedFiles"
    assert DaemonProtocolKernels.GetStatusIdleTimeoutField() == "idleTimeout"

    // …and the payload is composed FROM them, so a renamed kernel moves the wire rather than
    // leaving a second spelling behind.
    payload := DaemonProtocolKernels.StatusResultJson(12, "0h 1m 2s", "/root", 3, "30m")
    assert DpkInt(payload, DaemonProtocolKernels.GetStatusPidField()) == 12
    assert DpkString(payload, DaemonProtocolKernels.GetStatusUptimeField()) == "0h 1m 2s"
    assert DpkString(payload, DaemonProtocolKernels.GetStatusProjectRootField()) == "/root"
    assert DpkInt(payload, DaemonProtocolKernels.GetStatusCachedFilesField()) == 3
    assert DpkString(payload, DaemonProtocolKernels.GetStatusIdleTimeoutField()) == "30m"
}

test "the two control results are JSON-ENCODED strings, quotes included" {
    // A DECODED FACT ABOUT THE WIRE, not a spelling preference. `result` is typed as a string all
    // the way through, so every payload travels as JSON *text inside* a JSON string. `"pong"` is
    // therefore six characters, and a kernel that answered the four characters `pong` would put a
    // bare word where a client expects a document.
    assert DaemonProtocolKernels.GetPongResultJson() == "\"pong\""
    assert DaemonProtocolKernels.GetShutdownResultJson() == "\"shutting down\""
    assert DpkRootString(DaemonProtocolKernels.GetPongResultJson()) == "pong"
    assert DpkRootString(DaemonProtocolKernels.GetShutdownResultJson()) == "shutting down"
}

test "the socket directory, socket file and pid file are exactly these three names" {
    assert DaemonProtocolKernels.GetSocketDir() == ".nlc"
    assert DaemonProtocolKernels.GetSocketName() == "daemon.sock"
    assert DaemonProtocolKernels.GetPidFileName() == "daemon.pid"
    assert DaemonProtocolKernels.GetPidFilePath("/tmp/p/.nlc/daemon.sock") == "/tmp/p/.nlc/daemon.pid"
}

test "the three timeouts are exactly these values, and the idle one becomes the wire's own text" {
    // The C# asserted only that all three are POSITIVE, which every wrong value also satisfies.
    assert DaemonProtocolKernels.GetIdleTimeoutMinutes() == 30
    assert DaemonProtocolKernels.GetConnectionTimeoutMilliseconds() == 5000
    assert DaemonProtocolKernels.GetPingTimeoutMilliseconds() == 2000

    // `idleTimeout` on the status payload is this number, formatted — one answer, not two.
    assert DaemonProtocolKernels.FormatIdleTimeoutMinutes(DaemonProtocolKernels.GetIdleTimeoutMinutes()) == "30m"
    assert DaemonProtocolKernels.FormatIdleTimeoutMinutes(5) == "5m"
}

test "uptime formats hours, then minutes, then seconds, and reads all three" {
    // A CONTROL: three equal numbers would pass a kernel that transposed any two of them.
    assert DaemonProtocolKernels.FormatUptime(1, 2, 3) == "1h 2m 3s"
    assert DaemonProtocolKernels.FormatUptime(3, 2, 1) == "3h 2m 1s"
    assert DaemonProtocolKernels.FormatUptime(0, 0, 0) == "0h 0m 0s"
}

test "the protocol's own two request refusals are exactly these sentences" {
    // These are the only two sentences the SERVER composes before a method is even chosen, and both
    // reach a real client: one when the bytes are not JSON, one when the JSON carries no method.
    assert DaemonProtocolKernels.GetMalformedRequestJsonMessage() == "Malformed daemon request JSON."
    assert DaemonProtocolKernels.GetMissingMethodMessage() == "Daemon request must include a method."
    assert DaemonProtocolKernels.GetBatchDispatchAfterPrecheckMessage() == "Batch queries should be handled before single-request dispatch."
}

test "SIX query methods refuse a request with no file, and the other three accept one" {
    // A POLICY, NOT A FORMAT: which queries can answer without being told a file. `batch`, `symbols`
    // and `diagnostics` are project-wide and answer anyway; the other six refuse, and each refusal
    // names its OWN query command and its OWN sentence, so a client can tell them apart.
    assert !DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Outline, false).IsValid
    assert !DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Type, false).IsValid
    assert !DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Definition, false).IsValid
    assert !DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.References, false).IsValid
    assert !DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Completions, false).IsValid
    assert !DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Inspect, false).IsValid

    assert DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Batch, false).IsValid
    assert DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Symbols, false).IsValid
    assert DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Diagnostics, false).IsValid

    // …and a file makes every one of the six valid, so the refusal is about the PARAMETER and not
    // about the method.
    assert DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Outline, true).IsValid
    assert DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Inspect, true).IsValid
}

test "each file-requiring refusal names its own query command and its own sentence" {
    outline := DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Outline, false)
    assert outline.QueryCommand == "outline"
    assert outline.Message == "file parameter required"

    typeQuery := DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Type, false)
    assert typeQuery.QueryCommand == "type"
    assert typeQuery.Message == "file and pos parameters required"

    definition := DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Definition, false)
    assert definition.QueryCommand == "definition"
    assert definition.Message == "file+pos or name required"

    // THREE OF THE SIX SHARE ONE SENTENCE and differ only in the command they name — which is the
    // detail a `Contains` on the message alone could never state.
    references := DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.References, false)
    completions := DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Completions, false)
    inspect := DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Inspect, false)
    assert references.Message == "file and pos required"
    assert completions.Message == references.Message
    assert inspect.Message == references.Message
    assert references.QueryCommand == "references"
    assert completions.QueryCommand == "completions"
    assert inspect.QueryCommand == "inspect"

    // A valid answer carries no command and no sentence at all.
    ok := DaemonProtocolKernels.ValidateRequiredParameters(DaemonMethodKind.Symbols, false)
    assert ok.QueryCommand == ""
    assert ok.Message == ""
}

test "the nine query kinds are exactly the ones IsQueryMethod admits" {
    assert DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Batch)
    assert DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Symbols)
    assert DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Outline)
    assert DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Diagnostics)
    assert DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Type)
    assert DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Definition)
    assert DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.References)
    assert DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Completions)
    assert DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Inspect)

    // The three DAEMON-CONTROL kinds are not queries, which is what keeps `daemon/shutdown` out of
    // the query dispatch path.
    assert !DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Ping)
    assert !DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Shutdown)
    assert !DaemonProtocolKernels.IsQueryMethod(DaemonMethodKind.Status)
}

test "the socket path is project-local until its own byte budget refuses, then it is not" {
    // `ShouldUseProjectLocalSocket` is the whole reason a daemon works at all under a deep checkout:
    // a unix domain socket path is capped near 104 bytes by the kernel, so a long project root has
    // to fall back to a hashed directory under the temp path. The threshold is 100 BYTES, not
    // characters, and `Utf8ByteCount` is what makes that true of a non-ASCII path.
    assert DaemonProtocolKernels.ShouldUseProjectLocalSocket("/tmp/p/.nlc/daemon.sock")
    assert !DaemonProtocolKernels.ShouldUseProjectLocalSocket("/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/.nlc/daemon.sock")
    assert DaemonProtocolKernels.Utf8ByteCount("é") == 2
    assert DaemonProtocolKernels.Utf8ByteCount("abc") == 3
}

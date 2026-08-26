namespace NSharpLang.Cli.Commands

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

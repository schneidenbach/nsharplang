namespace NSharpLang.IncrementalBuild.Tests

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

// THE WORKSPACE SERVER'S SESSION REGISTRY (`WarmIncrementalSessions`).
//
// One row, because the registry is one process-wide table: rows running beside each other must not
// clear each other's sessions. Every key is unique to this row. The end-to-end claim -- a warm check
// or build re-analyses only what an edit reaches, and answers as a fresh process does -- is
// `tests/native/daemon-exec`'s, against a real server.
test "the warm session registry hands one session per identity, refuses a busy one, and drops what a failure or a trim leaves" {
    root := Path.Combine(Path.GetTempPath(), "nlc-warm-" + Guid.NewGuid().ToString("N"))
    buildKey := WarmIncrementalSessions.KeyFor(root, "App", "build", false, false)

    // Every part of the identity separates sessions.
    assert buildKey != WarmIncrementalSessions.KeyFor(root, "App", "check", false, false)
    assert buildKey != WarmIncrementalSessions.KeyFor(root, "App", "build", true, false)
    assert buildKey != WarmIncrementalSessions.KeyFor(root, "App", "build", false, true)
    assert buildKey != WarmIncrementalSessions.KeyFor(root, "Other", "build", false, false)
    assert buildKey == WarmIncrementalSessions.KeyFor(root + "/.", "App", "build", false, false)

    // Outside the server nothing is attached: an ordinary process compiles exactly as before.
    compiler := new MultiFileCompiler(new List<string>(), root, ProjectFileParser.CreateDefault(null))
    assert WarmIncrementalSessions.Attach(compiler, root, "App", "build", false, false) == null
    assert compiler.IncrementalState == null

    first := WarmIncrementalSessions.Acquire(buildKey, root, "App")
    assert first != null
    // In use: a second compilation of the same identity gets nothing rather than a shared state.
    assert WarmIncrementalSessions.Acquire(buildKey, root, "App") == null
    WarmIncrementalSessions.Release(buildKey)
    again := WarmIncrementalSessions.Acquire(buildKey, root, "App")
    assert Object.ReferenceEquals(first, again)

    // A trim keeps the session in use and drops the others.
    checkKey := WarmIncrementalSessions.KeyFor(root, "App", "check", true, false)
    idle := WarmIncrementalSessions.Acquire(checkKey, root, "App")
    WarmIncrementalSessions.Release(checkKey)
    WarmStateRegistry.TrimAll()
    WarmIncrementalSessions.Release(buildKey)
    assert Object.ReferenceEquals(first, WarmIncrementalSessions.Acquire(buildKey, root, "App"))
    assert !Object.ReferenceEquals(idle, WarmIncrementalSessions.Acquire(checkKey, root, "App"))
    WarmIncrementalSessions.Release(checkKey)

    // A compilation that threw leaves nothing for the next one.
    WarmIncrementalSessions.Discard(buildKey)
    fresh := WarmIncrementalSessions.Acquire(buildKey, root, "App")
    assert fresh != null
    assert !Object.ReferenceEquals(first, fresh)
    WarmIncrementalSessions.Discard(buildKey)
    WarmIncrementalSessions.Discard(checkKey)

    // `nlc daemon status` describes the registry.
    described := false
    for line in WarmStateRegistry.Describe() {
        if line.StartsWith("incremental-compilations: ", StringComparison.Ordinal) {
            described = true
        }
    }
    assert described
}

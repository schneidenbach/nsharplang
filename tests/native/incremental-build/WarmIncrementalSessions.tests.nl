namespace NSharpLang.IncrementalBuild.Tests

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Cli.Commands
import NSharpLang.Compiler

func WarmSessionAnalyzer(): Analyzer {
    analyzer := new Analyzer()
    analyzer.LoadSystemAssemblies()
    return analyzer
}

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
    idleSession := idle ?? throw new InvalidOperationException("the idle session was not created")
    trimAnalyzer := WarmSessionAnalyzer()
    idleState := idleSession.State
    idleState.RetainedAnalyzer = trimAnalyzer
    assert trimAnalyzer.ReferenceMetadata != null
    WarmIncrementalSessions.Release(checkKey)
    WarmStateRegistry.TrimAll()
    assert idleSession.State.RetainedAnalyzer == null
    assert trimAnalyzer.ReferenceMetadata == null, "trimming a warm session must close its reference metadata"
    assert !idleSession.State.ReleaseRetainedAnalyzer(), "a trimmed analyzer must be released exactly once"
    WarmIncrementalSessions.Release(buildKey)
    assert Object.ReferenceEquals(first, WarmIncrementalSessions.Acquire(buildKey, root, "App"))
    assert !Object.ReferenceEquals(idle, WarmIncrementalSessions.Acquire(checkKey, root, "App"))
    WarmIncrementalSessions.Release(checkKey)

    // A compilation that threw leaves nothing for the next one.
    WarmIncrementalSessions.Discard(buildKey)
    fresh := WarmIncrementalSessions.Acquire(buildKey, root, "App")
    assert fresh != null
    freshSession := fresh ?? throw new InvalidOperationException("the replacement session was not created")
    assert !Object.ReferenceEquals(first, freshSession)
    discardedAnalyzer := WarmSessionAnalyzer()
    freshState := freshSession.State
    freshState.RetainedAnalyzer = discardedAnalyzer
    assert discardedAnalyzer.ReferenceMetadata != null
    WarmIncrementalSessions.Discard(buildKey)
    assert freshSession.State.RetainedAnalyzer == null
    assert discardedAnalyzer.ReferenceMetadata == null, "discarding a failed warm check must close its reference metadata"
    assert !freshSession.State.ReleaseRetainedAnalyzer(), "a discarded analyzer must be released exactly once"
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

test "a retained warm analyzer stays alive and supports the next analysis before session disposal" {
    scratch := IncrementalScratch("warm-analyzer-ownership")
    try {
        IncrementalWriteProject(scratch)
        config := ProjectFileParser.Parse(Path.Combine(scratch, "project.yml"))
        files := config.GetSourceFiles(scratch, false)
        session := new IncrementalProjectSession(scratch, "Lib")

        firstCompiler := session.Analyze(config, files, null)
        firstAnalyzer := session.State.RetainedAnalyzer
        assert firstAnalyzer != null, "the completed first analysis must transfer analyzer ownership to the session"
        firstMetadata := firstAnalyzer.ReferenceMetadata
        assert firstMetadata != null
        assert firstCompiler.SemanticModels.Count > 0

        secondCompiler := session.Analyze(config, files, null)
        assert Object.ReferenceEquals(firstAnalyzer, session.State.RetainedAnalyzer), "the next analysis should reuse the retained analyzer"
        assert firstAnalyzer.ReferenceMetadata != null, "the retained metadata context must stay open between checks"
        assert secondCompiler.SemanticModels.Count > 0, "the next analysis must remain usable"
        assert session.State.LastFilesReused > 0, "the warm analysis should reuse unchanged file records"

        session.Dispose()
        assert session.State.RetainedAnalyzer == null
        assert firstAnalyzer.ReferenceMetadata == null, "disposing the retained session must close its metadata context"
        assert !session.State.ReleaseRetainedAnalyzer(), "disposing a session twice must release its analyzer only once"
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "reset releases a retained analyzer before replacing incremental state" {
    state := new IncrementalCompilationState()
    analyzer := WarmSessionAnalyzer()
    state.RetainedAnalyzer = analyzer
    assert analyzer.ReferenceMetadata != null

    state.Reset("changed environment")
    assert state.RetainedAnalyzer == null
    assert analyzer.ReferenceMetadata == null, "reset must close the old reference metadata"
    assert !state.ReleaseRetainedAnalyzer(), "reset must release the old analyzer only once"
}

test "a failed daemon check discards and releases the analyzer retained by its prior successful check" {
    scratch := IncrementalScratch("daemon-check-analyzer-failure")
    try {
        IncrementalWriteProject(scratch)
        sessionKey := WarmIncrementalSessions.KeyFor(scratch, "", "check", true, false)
        retainedSession := WarmIncrementalSessions.Acquire(sessionKey, scratch, "")
        assert retainedSession != null
        heldSession := retainedSession ?? throw new InvalidOperationException("the retained daemon session was not created")
        WarmIncrementalSessions.Release(sessionKey)

        CliInvocationContext.Begin(["nlc", "check", "--project", scratch, "--json"], !Console.IsErrorRedirected, null)
        try {
            firstExitCode := CheckCommand.Execute(["--project", scratch, "--json"])
            assert firstExitCode == 0, "the initial daemon check should be clean"
            retainedAnalyzer := heldSession.State.RetainedAnalyzer
            assert retainedAnalyzer != null
            analyzer := retainedAnalyzer ?? throw new InvalidOperationException("the successful daemon check retained no analyzer")
            assert analyzer.ReferenceMetadata != null

            mathPath := Path.Combine(scratch, "Math.nl")
            File.WriteAllText(mathPath, File.ReadAllText(mathPath).Replace("value * 2", "value * 3"))
            warmExitCode := CheckCommand.Execute(["--project", scratch, "--json"])
            assert warmExitCode == 0, "the next daemon check should reuse the live analyzer"
            assert Object.ReferenceEquals(analyzer, heldSession.State.RetainedAnalyzer), "a successful warm check must keep the same analyzer"
            assert analyzer.ReferenceMetadata != null, "the successful warm check must leave metadata open"

            File.WriteAllText(mathPath, File.ReadAllText(mathPath).Replace("value * 3", "missing * 2"))
            failedExitCode := CheckCommand.Execute(["--project", scratch, "--json"])
            assert failedExitCode != 0, "the edited daemon check must fail analysis"
            assert heldSession.State.RetainedAnalyzer == null, "a failed check must not leave its session retained"
            assert analyzer.ReferenceMetadata == null, "a failed daemon check must close the metadata context"
            assert !heldSession.State.ReleaseRetainedAnalyzer(), "the failed check must release the retained analyzer exactly once"

            replacement := WarmIncrementalSessions.Acquire(sessionKey, scratch, "")
            assert replacement != null
            assert !Object.ReferenceEquals(heldSession, replacement), "a failed check must discard its warm session"
            WarmIncrementalSessions.Discard(sessionKey)
        } finally {
            CliInvocationContext.End()
        }
    } finally {
        WarmIncrementalSessions.Discard(WarmIncrementalSessions.KeyFor(scratch, "", "check", true, false))
        IncrementalCleanup(scratch)
    }
}

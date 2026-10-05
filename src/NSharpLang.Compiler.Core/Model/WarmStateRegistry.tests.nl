namespace NSharpLang.Compiler

import System

// The warm-state seam: a cache registers three delegates and the host drives them. The registry is
// process-wide, so each row registers under a name of its own.

test "a registered cache hears changed paths and trims, and describes itself" {
    heard := ""
    trims := 0
    WarmStateRegistry.Register("warm-state-row-1", (path) => {
        heard = path
    }, () => {
        trims = trims + 1
    }, () => "3 entries")

    WarmStateRegistry.NotifyPathChanged("/w/Program.nl")
    WarmStateRegistry.TrimAll()
    assert heard == "/w/Program.nl"
    assert trims == 1

    found := false
    for line in WarmStateRegistry.Describe() {
        if line == "warm-state-row-1: 3 entries" {
            found = true
        }
    }

    assert found
}

test "registering a name again replaces it instead of adding a second entry" {
    WarmStateRegistry.Register("warm-state-row-2", (path) => {}, () => {}, () => "first")
    before := WarmStateRegistry.Count()
    WarmStateRegistry.Register("warm-state-row-2", (path) => {}, () => {}, () => "second")
    assert WarmStateRegistry.Count() == before

    seen := 0
    for line in WarmStateRegistry.Describe() {
        if line.StartsWith("warm-state-row-2: ") {
            seen = seen + 1
            assert line == "warm-state-row-2: second"
        }
    }

    assert seen == 1
}

test "a cache that throws neither stops the others nor breaks the status line" {
    reached := false
    WarmStateRegistry.Register("warm-state-row-3", (path) => {
        throw new InvalidOperationException("boom")
    }, () => {
        throw new InvalidOperationException("boom")
    }, () => {
        throw new InvalidOperationException("no description")
    })
    WarmStateRegistry.Register("warm-state-row-4", (path) => {
        reached = true
    }, () => {}, () => "fine")

    WarmStateRegistry.NotifyPathChanged("/w/a.nl")
    WarmStateRegistry.TrimAll()
    assert reached

    described := String.Join("\n", WarmStateRegistry.Describe())
    assert described.Contains("warm-state-row-3: unavailable: no description")
    assert described.Contains("warm-state-row-4: fine")
}

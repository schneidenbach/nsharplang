namespace NSharpLang.CompileTimeBench

import System
import System.Collections.Generic
import System.IO

// WHAT THIS FILE STATES.
//
// Every kernel the agent-loop benchmark is assembled from, proven on literal inputs or on a temp
// copy, plus the one gate that spends real time: the small and medium projects through every
// scenario with the CLI this gate built, compared against
// `tests/fixtures/agent-loop/agent-loop-baseline.golden.json`.
//
// LIKE `CompileTimeBench.tests.nl`, NOTHING HERE WRITES TO STDOUT OR STDERR, ON ANY PATH: Step 3a
// parses the captured output of `nlc test --json` as one JSON document. A failure's numbers travel
// in its assertion message, and a green gate leaves its table in `artifacts/agent-loop/`.
func AgentLoopTestTempDirectory(label: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-agent-loop-test-" + label + "-" + BenchLongText(DateTime.UtcNow.Ticks))
    BenchDeleteDirectory(directory)
    Directory.CreateDirectory(directory)
    return directory
}

func AgentLoopTestCounters(parsed: long): AgentLoopCounters {
    return new AgentLoopCounters(parsed, 8, 16, 1, 684, 0)
}

func AgentLoopTestRow(size: string, scenario: string, mode: string, wallMs: long, parsed: long): AgentLoopRow {
    row := new AgentLoopRow(size, scenario, mode)
    row.Samples = 1
    row.ExitCode = 0
    row.MedianWallMs = wallMs
    row.MedianCpuMs = wallMs
    row.MedianPeakRssBytes = 300000000
    row.SourceLines = 448
    row.Counters = AgentLoopTestCounters(parsed)
    return row
}

func AgentLoopTestBaseline(): AgentLoopBaseline {
    baseline := new AgentLoopBaseline()
    baseline.SchemaVersion = 2
    sizes := AgentLoopSizes()
    scenarios := AgentLoopScenarios()
    i := 0
    while i < sizes.Count {
        j := 0
        while j < scenarios.Count {
            baseline.Rows.Add(AgentLoopTestRow(sizes[i].Name, scenarios[j].Id, AgentLoopModeCold(), 1000, 40))
            baseline.Rows.Add(AgentLoopTestRow(sizes[i].Name, scenarios[j].Id, AgentLoopModeWarm(), 1000, 40))
            baseline.Rows.Add(AgentLoopTestRow(sizes[i].Name, scenarios[j].Id, AgentLoopModeDaemonWarm(), 1000, 40))
            j = j + 1
        }
        i = i + 1
    }
    return baseline
}

func AgentLoopTestObserved(parsed: long, wallMs: long): List<AgentLoopRow> {
    rows := new List<AgentLoopRow>()
    rows.Add(AgentLoopTestRow("small", "no-op check", "cold", wallMs, parsed))
    return rows
}

// ─── THE MATRIX ───────────────────────────────────────────────────────────────────────────────

test "agent-loop bench: ten scenarios, each a check, build or test after no edit, a body edit, a signature edit or a new file" {
    scenarios := AgentLoopScenarios()
    assert scenarios.Count == 10
    seen := new List<string>()
    i := 0
    while i < scenarios.Count {
        scenario := scenarios[i]
        assert !seen.Contains(scenario.Id), "duplicate scenario " + scenario.Id
        seen.Add(scenario.Id)
        assert scenario.Command == "check" || scenario.Command == "build" || scenario.Command == "test"
        assert scenario.Edit == AgentLoopEditNone() || scenario.Edit == AgentLoopEditBody() || scenario.Edit == AgentLoopEditSignature() || scenario.Edit == AgentLoopEditNewFile()
        // A test run is measured after no edit and after a body edit: those are the loop an agent
        // runs while making a change pass.
        if scenario.Command == "test" {
            assert scenario.Edit == AgentLoopEditNone() || scenario.Edit == AgentLoopEditBody()
        }
        i = i + 1
    }
}

test "agent-loop bench: paired scenario selection isolates one exact row id without changing the default matrix" {
    all := AgentLoopSelectScenarios("")
    selected := AgentLoopSelectScenarios("no-op build")
    unknown := AgentLoopSelectScenarios("no-op builds")
    assert all.Count == AgentLoopScenarios().Count
    assert selected.Count == 1 && selected[0].Id == "no-op build"
    assert unknown.Count == 0
}

test "agent-loop bench: the sizes are the issue-tracker fixture and two synthetic projects, and the gate measures small and medium" {
    small := AgentLoopFindSize("small") ?? new AgentLoopSize("", "", 0, 0)
    assert small.FixtureProject == "tests/fixtures/issue-tracker"
    assert Directory.Exists(BenchAbsoluteProjectPath(BenchRepositoryRoot(), small.FixtureProject))
    assert AgentLoopFindSize("medium") != null
    assert AgentLoopFindSize("large") != null
    assert AgentLoopFindSize("huge") == null

    gate := AgentLoopGateSizeNames()
    assert gate.Count == 2
    assert gate[0] == "small"
    assert gate[1] == "medium"
}

test "agent-loop bench: the synthetic projects are about 10k and 80k lines" {
    medium := AgentLoopTestTempDirectory("medium")
    large := AgentLoopTestTempDirectory("large")
    try {
        AgentLoopWriteSynthetic(AgentLoopFindSize("medium") ?? new AgentLoopSize("", "", 0, 0), medium)
        AgentLoopWriteSynthetic(AgentLoopFindSize("large") ?? new AgentLoopSize("", "", 0, 0), large)
        mediumLines := AgentLoopSourceLines(medium)
        largeLines := AgentLoopSourceLines(large)
        assert mediumLines >= 9000 && mediumLines <= 12000, "medium is " + BenchLongText(mediumLines) + " lines"
        assert largeLines >= 75000 && largeLines <= 90000, "large is " + BenchLongText(largeLines) + " lines"
        assert File.Exists(Path.Combine(medium, "Synth.tests.nl"))
        assert File.Exists(Path.Combine(medium, "project.yml"))
    } finally {
        BenchDeleteDirectory(medium)
        BenchDeleteDirectory(large)
    }
}

// ─── THE EDITS ────────────────────────────────────────────────────────────────────────────────

test "agent-loop bench: the synthetic text is a pure function of its arguments" {
    assert AgentLoopSyntheticFileText(3, 4, -1, false) == AgentLoopSyntheticFileText(3, 4, -1, false)
    assert AgentLoopSyntheticFileText(0, 4, 2, false) == AgentLoopSyntheticFileText(0, 4, 2, false)
    assert AgentLoopSyntheticFileText(0, 4, 1, false) != AgentLoopSyntheticFileText(0, 4, 2, false)
}

test "agent-loop bench: a synthetic body edit changes one statement of the edit target and nothing else" {
    original := AgentLoopSyntheticFileText(0, 4, -1, false)
    edited := AgentLoopSyntheticFileText(0, 4, 7, false)
    assert original.Contains("func Score000_00(values: int[], seed: int): int {\n    total := seed + 0\n")
    assert edited.Contains("func Score000_00(values: int[], seed: int): int {\n    total := seed + 1007\n")
    assert original.Replace("total := seed + 0\n", "total := seed + 1007\n") == edited

    // Only the edit target's file has an edit target.
    assert AgentLoopSyntheticFileText(1, 4, 7, false) == AgentLoopSyntheticFileText(1, 4, -1, false)
}

test "agent-loop bench: a synthetic signature edit adds a read parameter to the edit target and the argument to its one caller" {
    target := AgentLoopSyntheticFileText(0, 4, -1, true)
    caller := AgentLoopSyntheticFileText(1, 4, -1, true)
    assert target.Contains("func Score000_00(values: int[], seed: int, bias: int): int {")
    assert target.Contains("    return total + bias + 0\n")
    assert caller.Contains("    return total + Score000_00(values, seed, 0)\n")
    // The other functions, and every later file, are untouched.
    assert target.Contains("func Score000_01(values: int[], seed: int): int {")
    assert caller.Contains("    return total + Score000_01(values, seed)\n")
    assert AgentLoopSyntheticFileText(2, 4, -1, true) == AgentLoopSyntheticFileText(2, 4, -1, false)
}

test "agent-loop bench: every issue-tracker edit applies exactly once to a fresh copy" {
    small := AgentLoopFindSize("small") ?? new AgentLoopSize("", "", 0, 0)
    root := BenchRepositoryRoot()
    edits := new List<string>()
    edits.Add(AgentLoopEditBody())
    edits.Add(AgentLoopEditSignature())
    edits.Add(AgentLoopEditNewFile())
    i := 0
    while i < edits.Count {
        directory := AgentLoopTestTempDirectory("fixture")
        try {
            AgentLoopMaterialize(root, small, directory)
            assert !Directory.Exists(Path.Combine(directory, "bin")), "a copied fixture must not carry build outputs"
            refusal := AgentLoopApplyEdit(small, directory, edits[i], 4)
            assert refusal == "", edits[i] + ": " + refusal
        } finally {
            BenchDeleteDirectory(directory)
        }
        i = i + 1
    }

    directory := AgentLoopTestTempDirectory("fixture-text")
    try {
        AgentLoopMaterialize(root, small, directory)
        _ = AgentLoopApplyEdit(small, directory, AgentLoopEditSignature(), 4)
        workflow := File.ReadAllText(Path.Combine(directory, "Workflow.nl"))
        service := File.ReadAllText(Path.Combine(directory, "Service.nl"))
        assert workflow.Contains("static func Transition(issue: Issue, to: IssueStatus, reason: string): IssueStatus {")
        assert workflow.Contains("throw new Exception(reason + \": \" + ")
        assert service.Contains("Workflow.Transition(issue, newStatus, \"edit 4\")")
    } finally {
        BenchDeleteDirectory(directory)
    }
}

test "agent-loop bench: an edit anchor that is missing or not unique is refused, never silently skipped" {
    directory := AgentLoopTestTempDirectory("anchor")
    try {
        path := Path.Combine(directory, "File.nl")
        File.WriteAllText(path, "alpha beta alpha")
        assert AgentLoopReplaceOnce(path, "gamma", "x").Contains("is not in")
        assert AgentLoopReplaceOnce(path, "alpha", "x").Contains("more than once")
        assert AgentLoopReplaceOnce(path, "beta", "delta") == ""
        assert File.ReadAllText(path) == "alpha delta alpha"
        assert AgentLoopReplaceOnce(Path.Combine(directory, "Missing.nl"), "a", "b").Contains("does not exist")
    } finally {
        BenchDeleteDirectory(directory)
    }
}

// ─── WHAT A RUN REPORTS ───────────────────────────────────────────────────────────────────────

test "agent-loop bench: the counters are read from an nsharp.cli-stats v1 line and from nothing else" {
    line := "{\"schema\":\"nsharp.cli-stats\",\"schemaVersion\":1,\"command\":\"check\",\"exitCode\":0,\"wallMs\":1483,\"cpuMs\":1483,\"peakWorkingSetBytes\":null,\"counters\":{\"filesParsed\":40,\"emitParses\":8,\"filesAnalyzed\":16,\"assembliesEmitted\":1,\"referenceAssembliesLoaded\":684,\"processesSpawned\":2}}"
    counters := AgentLoopParseStatsCounters(line) ?? new AgentLoopCounters(-1, -1, -1, -1, -1, -1)
    assert counters.FilesParsed == 40
    assert counters.EmitParses == 8
    assert counters.FilesAnalyzed == 16
    assert counters.AssembliesEmitted == 1
    assert counters.ReferenceAssembliesLoaded == 684
    assert counters.ProcessesSpawned == 2

    assert AgentLoopParseStatsCounters("") == null
    assert AgentLoopParseStatsCounters("not json") == null
    assert AgentLoopParseStatsCounters(line.Replace("\"schemaVersion\":1", "\"schemaVersion\":2")) == null
    assert AgentLoopParseStatsCounters(line.Replace("nsharp.cli-stats", "something-else")) == null
}

test "agent-loop bench: CPU time is user plus system from either time utility, and absent when neither reported it" {
    macos := "  some cli output\n        1.54 real         1.46 user         0.08 sys\n           318996480  maximum resident set size\n"
    assert AgentLoopParseCpuMs(macos) == 1540
    linux := "\tCommand being timed: \"dotnet\"\n\tUser time (seconds): 2.10\n\tSystem time (seconds): 0.35\n"
    assert AgentLoopParseCpuMs(linux) == 2450
    assert AgentLoopParseCpuMs("error NL012: never read\n") == -1
}

test "agent-loop bench: the command line carries --stats=<path> only when the CLI supports it" {
    withStats := AgentLoopCommandArguments("/x/Cli.dll", "build", "/p", "/tmp/s.json")
    assert withStats == "\"/x/Cli.dll\" build --color=never --project \"/p\" --stats=\"/tmp/s.json\""
    without := AgentLoopCommandArguments("/x/Cli.dll", "check", "/p", "")
    assert without == "\"/x/Cli.dll\" check --project \"/p\""
}

test "agent-loop bench: counters that differ between identical samples mark the row unstable" {
    row := new AgentLoopRow("small", "no-op check", "cold")
    wall := new long[](2)
    cpu := new long[](2)
    rss := new long[](2)
    AgentLoopRecordRun(row, new AgentLoopRun(0, 100, 90, 1000, AgentLoopTestCounters(40), ""), wall, cpu, rss)
    AgentLoopRecordRun(row, new AgentLoopRun(0, 120, 95, 1100, AgentLoopTestCounters(40), ""), wall, cpu, rss)
    assert row.CountersStable
    AgentLoopFinishRow(row, wall, cpu, rss)
    assert row.Samples == 2
    assert row.MedianWallMs == 100

    unstable := new AgentLoopRow("small", "no-op check", "cold")
    AgentLoopRecordRun(unstable, new AgentLoopRun(0, 100, 90, 1000, AgentLoopTestCounters(40), ""), wall, cpu, rss)
    AgentLoopRecordRun(unstable, new AgentLoopRun(0, 100, 90, 1000, AgentLoopTestCounters(41), ""), wall, cpu, rss)
    assert !unstable.CountersStable

    failed := new AgentLoopRow("small", "no-op check", "cold")
    AgentLoopRecordRun(failed, new AgentLoopRun(1, 100, 90, 1000, null, "error NL012"), wall, cpu, rss)
    assert failed.ExitCode == 1
    assert failed.Failure == "error NL012"
}

// ─── THE BASELINE AND THE VERDICT ─────────────────────────────────────────────────────────────

test "agent-loop bench: the baseline file the harness writes is the baseline file it reads" {
    written := AgentLoopTestBaseline()
    parsed := AgentLoopParseBaseline(AgentLoopBaselineJson(written))
    assert parsed.SchemaVersion == 2
    assert parsed.Rows.Count == AgentLoopSizes().Count * AgentLoopScenarios().Count * 3
    first := parsed.Rows[0]
    assert first.Size == "small" && first.Scenario == "no-op check" && first.Mode == "cold"
    assert first.SourceLines == 448
    assert AgentLoopCountersEqual(first.Counters ?? AgentLoopTestCounters(-1), AgentLoopTestCounters(40))
    assert AgentLoopBaselineRefusal(parsed) == ""
    json := AgentLoopBaselineJson(written)
    assert !json.Contains("medianWallMs")
    assert !json.Contains("medianCpuMs")
    assert !json.Contains("toleranceFactor")
}

test "agent-loop bench: a baseline with no rows, an unknown schema or unmeasured counters is refused" {
    empty := AgentLoopTestBaseline()
    empty.Rows.Clear()
    assert AgentLoopBaselineRefusal(empty).Contains("has no rows")

    future := AgentLoopTestBaseline()
    future.SchemaVersion = 3
    assert AgentLoopBaselineRefusal(future).Contains("schemaVersion 3")

    missingDaemonWarm := AgentLoopTestBaseline()
    missingDaemonWarm.Rows.RemoveAt(missingDaemonWarm.Rows.Count - 1)
    assert AgentLoopBaselineRefusal(missingDaemonWarm).Contains("missing daemon-warm")

    unmeasured := AgentLoopTestBaseline()
    unmeasured.Rows[0].Counters = new AgentLoopCounters(-1, -1, -1, -1, -1, -1)
    assert AgentLoopBaselineRefusal(unmeasured).Contains("no measured counters")
}

test "agent-loop bench: a baseline is never written from a failed row or from counters that varied between samples" {
    assert AgentLoopUnbaselinableRows(AgentLoopTestObserved(40, 1000)).Count == 0

    failed := AgentLoopTestObserved(40, 1000)
    failed[0].ExitCode = 1
    assert AgentLoopUnbaselinableRows(failed)[0].Contains("exited 1")

    unstable := AgentLoopTestObserved(40, 1000)
    unstable[0].CountersStable = false
    assert AgentLoopUnbaselinableRows(unstable)[0].Contains("different between identical samples")
}

test "agent-loop bench: equal counters pass, fewer must be ratcheted in, more are a regression" {
    baseline := AgentLoopTestBaseline()
    assert AgentLoopCounterFailures(baseline, AgentLoopTestObserved(40, 5000)).Count == 0

    fewer := AgentLoopCounterFailures(baseline, AgentLoopTestObserved(8, 1000))
    assert fewer.Count == 1
    assert fewer[0].Contains("filesParsed 40 -> 8")
    assert fewer[0].Contains("ratchet the baseline down")

    more := AgentLoopCounterFailures(baseline, AgentLoopTestObserved(41, 1000))
    assert more.Count == 1
    assert more[0].Contains("MORE work")

    unknown := AgentLoopTestObserved(40, 1000)
    unknown[0].Size = "unlisted-size"
    assert AgentLoopCounterFailures(baseline, unknown)[0].Contains("has no baseline row")

    failed := AgentLoopTestObserved(40, 1000)
    failed[0].ExitCode = 1
    failed[0].Failure = "error NL012"
    assert AgentLoopCounterFailures(baseline, failed)[0].Contains("exited 1 - error NL012")
}

test "agent-loop bench: the ratchet lowers counters, refuses a rise, and never touches a wall time" {
    baseline := AgentLoopTestBaseline()
    lower := AgentLoopTestObserved(8, 9999)
    assert AgentLoopRatchetCounters(baseline, lower).Count == 0
    cold := AgentLoopFindRow(baseline.Rows, "small", "no-op check", "cold") ?? lower[0]
    assert (cold.Counters ?? AgentLoopTestCounters(-1)).FilesParsed == 8
    assert cold.MedianWallMs == 1000

    higher := AgentLoopRatchetCounters(baseline, AgentLoopTestObserved(9, 1000))
    assert higher.Count == 1
    assert higher[0].Contains("MORE work")
    assert (cold.Counters ?? AgentLoopTestCounters(-1)).FilesParsed == 8

    failed := AgentLoopTestObserved(1, 1000)
    failed[0].ExitCode = 1
    assert AgentLoopRatchetCounters(baseline, failed)[0].Contains("run failed")
    assert (cold.Counters ?? AgentLoopTestCounters(-1)).FilesParsed == 8
}

test "agent-loop relative gate: paired head/base medians accept at 1.20x and fail above it" {
    timings := new List<AgentLoopRelativeTimingRow>()
    row := new AgentLoopRelativeTimingRow("small", "no-op check", AgentLoopModeCold(), AgentLoopRelativeMinimumPairs())
    i := 0
    while i < AgentLoopRelativeMinimumPairs() {
        row.BaseMs[i] = 1000
        row.HeadMs[i] = 1200
        row.BaseCpuMs[i] = 60
        row.HeadCpuMs[i] = 72
        i = i + 1
    }
    row.Samples = AgentLoopRelativeMinimumPairs()
    timings.Add(row)
    assert AgentLoopRelativeTimingFailures(timings).Count == 0
    assert AgentLoopRelativeTimingTable(timings).Contains("| small | no-op check | cold | wall | 1000 | 1200 | 60 | 72 | 200 | 9 | 1.2x |")

    i = 0
    while i < row.Samples {
        row.HeadMs[i] = 1300
        i = i + 1
    }
    failures := AgentLoopRelativeTimingFailures(timings)
    assert failures.Count == 1
    assert failures[0].Contains("95% exact sign interval lower bound 1.3x")
    assert failures[0].Contains("median slowdown 300 ms >= 30 ms")
}

test "agent-loop relative gate uses the exact sign-test lower confidence bound, not a raw median" {
    assert BenchExactMedianLowerBoundRank(9) == 2
    values := new long[](9)
    values[0] = 1000
    values[1] = 1100
    values[2] = 1200
    values[3] = 1300
    values[4] = 1400
    values[5] = 1500
    values[6] = 1600
    values[7] = 1700
    values[8] = 1800
    assert BenchMedianLowerConfidenceBound(values, 9) == 1100
    assert BenchMedianLowerConfidenceBound(values, 8) == -1
}

test "agent-loop relative gate preserves both deliberate 500 ms and 1,500 ms slowdown proofs" {
    baseTimes := new long[](9)
    head500 := new long[](9)
    head1500 := new long[](9)
    i := 0
    while i < 9 {
        baseTimes[i] = 1000
        head500[i] = baseTimes[i] + BenchConfiguredDelayMs("head", "500")
        head1500[i] = baseTimes[i] + BenchConfiguredDelayMs("head", "1500")
        i = i + 1
    }

    failure500 := BenchPairedTimingRegressionFailure("small / no-op build / cold", head500, baseTimes, 9, AgentLoopRelativeToleranceThousandths(), AgentLoopRelativeSlowdownFloorMs())
    failure1500 := BenchPairedTimingRegressionFailure("large / build / cold", head1500, baseTimes, 9, AgentLoopRelativeToleranceThousandths(), AgentLoopRelativeSlowdownFloorMs())
    assert failure500.Contains("median slowdown 500 ms >= 30 ms"), failure500
    assert failure1500.Contains("median slowdown 1500 ms >= 30 ms"), failure1500
}

test "agent-loop relative gate requires both statistical confidence and a 30 ms absolute slowdown" {
    baseTimes := new long[](9)
    noisyHead := new long[](9)
    smallBase := new long[](9)
    smallHead := new long[](9)
    i := 0
    while i < 9 {
        baseTimes[i] = 1000
        noisyHead[i] = 1250
        smallBase[i] = 100
        smallHead[i] = 125
        i = i + 1
    }
    noisyHead[0] = 1000
    noisyHead[1] = 1100

    assert BenchPairedTimingRegressionFailure("row", noisyHead, baseTimes, 9, 1200, 30) == ""
    assert BenchPairedTimingRegressionFailure("row", smallHead, smallBase, 9, 1200, 30) == ""
}

test "agent-loop timing uses CPU only when a short row has a steadier resolved CPU signal" {
    row := new AgentLoopRelativeTimingRow("small", "no-op check", AgentLoopModeDaemonWarm(), 9)
    i := 0
    while i < 9 {
        row.BaseMs[i] = 70 + i * 5
        row.HeadMs[i] = row.BaseMs[i] + (i % 3) * 20
        row.BaseCpuMs[i] = 42
        row.HeadCpuMs[i] = 50
        i = i + 1
    }
    row.Samples = 9
    assert AgentLoopRelativeMetric(row) == "cpu"

    i = 0
    while i < 5 {
        row.BaseCpuMs[i] = 4
        i = i + 1
    }
    assert AgentLoopRelativeMetric(row) == "wall"
}

test "agent-loop relative sampling has a bounded row work target and keeps at least nine odd pairs" {
    assert AgentLoopRelativeMinimumPairs() == 9
    assert AgentLoopRelativeMaximumPairs() == 17
    assert AgentLoopRelativeMaximumPairs() % 2 == 1
    assert AgentLoopRelativeRowWorkTargetMs() == 350
}

test "agent-loop sensitivity floor combines the 20 percent ratio and 30 ms absolute thresholds" {
    assert AgentLoopMinimumDetectableSlowdownMs(100) == 30
    assert AgentLoopMinimumDetectableSlowdownMs(200) == 41
    assert AgentLoopMinimumDetectableSlowdownMs(1000) == 201
    assert AgentLoopMinimumDetectableSlowdownMs(0) == -1
}

test "agent-loop relative gate skips timing for twenty repeated checks of an identical commit" {
    gitRoot := BenchCompilerPerfGitRoot(BenchRepositoryRoot())
    headCommit := BenchGitText(gitRoot, "rev-parse HEAD")
    baseCommit := headCommit
    i := 0
    while i < 20 {
        changes := BenchFindCompilerProductChanges(gitRoot, baseCommit, headCommit)
        assert changes.Error == "", changes.Error
        assert !changes.HasCompilerChanges(), "identical compiler products must skip timing; observed " + String.Join(", ", changes.ProductPaths)
        i = i + 1
    }
}

test "agent-loop compiler product paths cover CLI compiler runtime and SDK inputs but ignore harness and tests" {
    assert BenchIsCompilerProductPath("src/NSharpLang.Compiler.Core/Columnar/Analyzer.nl")
    assert BenchIsCompilerProductPath("src/NSharpLang.Compiler.Driver/project.yml")
    assert BenchIsCompilerProductPath("src/NSharpLang.Cli/Program.cs")
    assert BenchIsCompilerProductPath("src/NSharpLang.TestHost/Runner.cs")
    assert BenchIsCompilerProductPath("src/NSharpLang.Runtime/Union.cs")
    assert BenchIsCompilerProductPath("src/NSharpLang.Build.Tasks/NSharpLang.Build.targets")
    assert BenchIsCompilerProductPath("src/NSharpLang.Sdk/Sdk/Sdk.targets")
    assert !BenchIsCompilerProductPath("tests/native/compile-time-bench/AgentLoopBench.nl")
    assert !BenchIsCompilerProductPath("src/NSharpLang.Compiler.Core/Columnar/Analyzer.tests.nl")
    assert !BenchIsCompilerProductPath("src/NSharpLang.Cli/Cli.csproj")
    assert !BenchIsCompilerProductPath("src/NSharpLang.Sdk/NSharpLang.Sdk.csproj")
    assert !BenchIsCompilerProductPath("memory/testing.md")
}

test "agent-loop bench: the table states every counter and puts a compared value beside each one that moved" {
    observed := AgentLoopTestObserved(8, 500)
    table := AgentLoopRenderTable(observed, AgentLoopTestBaseline().Rows, "the baseline")
    assert table.Contains("Parenthesised values are the baseline")
    assert table.Contains("| parsed | emit parses | analyzed | emitted | refs loaded | spawned |")
    assert table.Contains("| 500 |")
    assert table.Contains("| 8 (40) |")
    assert table.Contains("| 684 |")

    plain := AgentLoopRenderTable(observed, null, "")
    assert !plain.Contains("Parenthesised")
    assert plain.Contains("| small | 448 | no-op check | cold | 0 | 500 |")
}

test "agent-loop bench: the committed structural baseline covers cold, warm and daemon-warm rows" {
    baseline := AgentLoopParseBaseline(File.ReadAllText(AgentLoopBaselinePath(BenchRepositoryRoot())))
    assert AgentLoopBaselineRefusal(baseline) == "", AgentLoopBaselineRefusal(baseline)
    sizes := AgentLoopSizes()
    scenarios := AgentLoopScenarios()
    assert baseline.Rows.Count == sizes.Count * scenarios.Count * 3
    i := 0
    while i < sizes.Count {
        j := 0
        while j < scenarios.Count {
            assert AgentLoopFindRow(baseline.Rows, sizes[i].Name, scenarios[j].Id, AgentLoopModeCold()) != null, sizes[i].Name + " / " + scenarios[j].Id
            assert AgentLoopFindRow(baseline.Rows, sizes[i].Name, scenarios[j].Id, AgentLoopModeWarm()) != null, sizes[i].Name + " / " + scenarios[j].Id
            assert AgentLoopFindRow(baseline.Rows, sizes[i].Name, scenarios[j].Id, AgentLoopModeDaemonWarm()) != null, sizes[i].Name + " / " + scenarios[j].Id
            j = j + 1
        }
        i = i + 1
    }
}

// ─── THE GATE ─────────────────────────────────────────────────────────────────────────────────

test "agent-loop gate: exact counter contracts and change-aware paired cold plus daemon-warm timings" {
    // SILENT ON EVERY PATH: Step 3a parses the captured test stream as one JSON document.
    repositoryRoot := BenchRepositoryRoot()
    baseline := AgentLoopParseBaseline(File.ReadAllText(AgentLoopBaselinePath(repositoryRoot)))
    refusal := AgentLoopBaselineRefusal(baseline)
    assert refusal == "", "agent-loop gate: " + refusal

    cliDll := BenchDefaultCliDll(repositoryRoot)
    assert File.Exists(cliDll), "agent-loop gate: the CLI under test was not found at " + cliDll + ". Build it with: ./scripts/dev.sh"
    assert AgentLoopCliSupportsStats(cliDll), "agent-loop gate: the CLI under test at " + cliDll + " does not list --stats in `nlc build --help`."

    loadAtStart := BenchReadMachineLoad()
    gateStarted := DateTime.UtcNow.Ticks
    gitRoot := BenchCompilerPerfGitRoot(repositoryRoot)
    baseCommit := BenchSelectBaseCommit(gitRoot)
    headCommit := BenchGitText(gitRoot, "rev-parse HEAD")
    productChanges := BenchFindCompilerProductChanges(gitRoot, baseCommit, headCommit)
    assert productChanges.Error == "", "agent-loop gate: " + productChanges.Error

    failures := new List<string>()
    relative := new AgentLoopRelativeMatrix()
    baseLabel := "not compared"
    recordedBaseCommit := baseCommit
    baseBuildMs := 0L
    baseCacheHit := false
    timingStatus := "not compared (no compiler change)"
    if productChanges.HasCompilerChanges() {
        baseCompiler := BenchPrepareBaseCompiler(repositoryRoot)
        assert baseCompiler.Error == "", "agent-loop gate: " + baseCompiler.Error
        relative = AgentLoopMeasureRelativeMatrix(cliDll, baseCompiler.CliDll, repositoryRoot, AgentLoopGateSizeNames(), AgentLoopRelativeMinimumPairs(), false)
        failures.AddRange(AgentLoopRelativeTimingFailures(relative.Timings))
        failures.AddRange(relative.Failures)
        baseLabel = "base CLI"
        recordedBaseCommit = baseCompiler.Commit
        baseBuildMs = baseCompiler.BuildMs
        baseCacheHit = baseCompiler.CacheHit
        timingStatus = "compared by exact sign-test 95% lower bound plus 30 ms slowdown floor"
    } else {
        relative.HeadCounterRows = AgentLoopMeasureStructuralRows(cliDll, repositoryRoot, AgentLoopGateSizeNames(), 3, false)
    }
    failures.AddRange(AgentLoopCounterFailures(baseline, relative.HeadCounterRows))

    loadAtEnd := BenchReadMachineLoad()
    gateElapsedMs := (DateTime.UtcNow.Ticks - gateStarted) / 10000
    facts := BenchReadEnvironmentFacts(gitRoot)
    gateLine := AgentLoopRelativeGateRecordLine(failures, timingStatus, baseLabel, recordedBaseCommit, facts.CliCommit, baseBuildMs, baseCacheHit, gateElapsedMs, AgentLoopMachineText(facts), loadAtStart, loadAtEnd)
    table := "timing: " + timingStatus + "\n\n" + AgentLoopRelativeTimingTable(relative.Timings) + "\n\n## Sensitivity\n\n" + AgentLoopTimingSensitivityTable(relative.HeadCounterRows, relative.Timings) + "\n\n## Head structural counters\n\n" + AgentLoopRenderTable(relative.HeadCounterRows, baseline.Rows, "the committed structural counter baseline " + AgentLoopBaselineRelativePath())
    _ = AgentLoopWriteRelativeGateRecord(repositoryRoot, gateLine, table)
    assert failures.Count == 0, gateLine + "\n" + table
}

// ONE LOADED REFERENCE SET PER COMPILATION, AT ANY WORKER COUNT (`SharedReferenceMetadata`). A parallel
// analysis worker reads the metadata context its shared analyzer opened instead of re-reading the
// project's reference closure, so the medium project checked with four workers opens exactly the
// reference images it opens with one. Two separate processes, so nothing else running in this one can
// move the process-wide counter. (The IL back end's half -- its external type scan reading the same
// context -- is pinned by the committed counter baseline: a medium check opens 40 images, not 77.)
func AgentLoopRunWithWorkers(cliDll: string, directory: string, workers: string): AgentLoopRun {
    statsPath := AgentLoopStatsPath()
    environment := AgentLoopDaemonEnvironment(false)
    environment["NSHARP_COMPILER_WORKERS"] = workers
    run := BenchRunUnderTimeUtilityWithEnvironment(AgentLoopCommandArguments(cliDll, "check", directory, statsPath), Path.GetTempPath(), environment)
    counters: AgentLoopCounters? = null
    if File.Exists(statsPath) {
        counters = AgentLoopParseStatsCounters(File.ReadAllText(statsPath))
        File.Delete(statsPath)
    }
    return new AgentLoopRun(run.ExitCode, run.WallMs, 0, 0, counters, BenchTruncate(run.Stderr.Trim(), 600))
}

test "agent-loop: parallel analysis workers open no reference image beyond the serial compilation's" {
    repositoryRoot := BenchRepositoryRoot()
    cliDll := BenchDefaultCliDll(repositoryRoot)
    assert File.Exists(cliDll), "the CLI under test was not found at " + cliDll
    size := AgentLoopFindSize("medium")
    assert size != null
    directory := AgentLoopSampleDirectory()
    try {
        AgentLoopMaterialize(repositoryRoot, size ?? new AgentLoopSize("", "", 0, 0), directory)
        serial := AgentLoopRunWithWorkers(cliDll, directory, "1")
        parallel := AgentLoopRunWithWorkers(cliDll, directory, "4")
        assert serial.ExitCode == 0, serial.Detail
        assert parallel.ExitCode == 0, parallel.Detail
        serialCounters := serial.Counters ?? AgentLoopZeroCounters()
        parallelCounters := parallel.Counters ?? AgentLoopZeroCounters()
        assert serial.Counters != null && parallel.Counters != null
        assert serialCounters.FilesAnalyzed == parallelCounters.FilesAnalyzed
        assert serialCounters.ReferenceAssembliesLoaded > 0
        assert parallelCounters.ReferenceAssembliesLoaded == serialCounters.ReferenceAssembliesLoaded, "four workers opened " + parallelCounters.ReferenceAssembliesLoaded.ToString() + " reference images, one worker " + serialCounters.ReferenceAssembliesLoaded.ToString()
    } finally {
        BenchDeleteDirectory(directory)
    }
}

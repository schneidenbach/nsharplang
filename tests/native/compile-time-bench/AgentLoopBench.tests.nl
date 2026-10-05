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

func AgentLoopTestBaseline(judgeable: bool): AgentLoopBaseline {
    baseline := new AgentLoopBaseline()
    baseline.SchemaVersion = 1
    baseline.MeasuredAt = "2026-10-05"
    baseline.CliCommit = "deadbeef"
    baseline.Machine = "test machine"
    baseline.LoadAtStart = "1.2"
    baseline.LoadAtEnd = "1.4"
    baseline.TimingJudgeable = judgeable
    baseline.Runs = 3
    baseline.ToleranceThousandths = 1500
    baseline.Rows.Add(AgentLoopTestRow("small", "no-op check", "cold", 1000, 40))
    baseline.Rows.Add(AgentLoopTestRow("small", "no-op check", "warm", 1000, 40))
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
    written := AgentLoopTestBaseline(true)
    parsed := AgentLoopParseBaseline(AgentLoopBaselineJson(written))
    assert parsed.SchemaVersion == 1
    assert parsed.MeasuredAt == "2026-10-05"
    assert parsed.LoadAtStart == "1.2"
    assert parsed.TimingJudgeable
    assert parsed.Runs == 3
    assert parsed.ToleranceThousandths == 1500
    assert parsed.Rows.Count == 2
    first := parsed.Rows[0]
    assert first.Size == "small" && first.Scenario == "no-op check" && first.Mode == "cold"
    assert first.MedianWallMs == 1000
    assert first.SourceLines == 448
    assert AgentLoopCountersEqual(first.Counters ?? AgentLoopTestCounters(-1), AgentLoopTestCounters(40))
    assert AgentLoopBaselineRefusal(parsed) == ""
    assert AgentLoopBaselineJson(written).Contains("loosened without the owner")
}

test "agent-loop bench: a baseline with no rows, an unknown schema or unmeasured counters is refused" {
    empty := AgentLoopTestBaseline(true)
    empty.Rows.Clear()
    assert AgentLoopBaselineRefusal(empty).Contains("has no rows")

    future := AgentLoopTestBaseline(true)
    future.SchemaVersion = 2
    assert AgentLoopBaselineRefusal(future).Contains("schemaVersion 2")

    unmeasured := AgentLoopTestBaseline(true)
    unmeasured.Rows[0].Counters = new AgentLoopCounters(-1, -1, -1, -1, -1, -1)
    assert AgentLoopBaselineRefusal(unmeasured).Contains("no measured counters")
}

test "agent-loop bench: equal counters pass, fewer must be ratcheted in, more are a regression" {
    baseline := AgentLoopTestBaseline(true)
    assert AgentLoopCounterFailures(baseline, AgentLoopTestObserved(40, 5000)).Count == 0

    fewer := AgentLoopCounterFailures(baseline, AgentLoopTestObserved(8, 1000))
    assert fewer.Count == 1
    assert fewer[0].Contains("filesParsed 40 -> 8")
    assert fewer[0].Contains("ratchet the baseline down")

    more := AgentLoopCounterFailures(baseline, AgentLoopTestObserved(41, 1000))
    assert more.Count == 1
    assert more[0].Contains("MORE work")

    unknown := AgentLoopTestObserved(40, 1000)
    unknown[0].Size = "medium"
    assert AgentLoopCounterFailures(baseline, unknown)[0].Contains("has no baseline row")

    failed := AgentLoopTestObserved(40, 1000)
    failed[0].ExitCode = 1
    failed[0].Failure = "error NL012"
    assert AgentLoopCounterFailures(baseline, failed)[0].Contains("exited 1 - error NL012")
}

test "agent-loop bench: the ratchet lowers counters, refuses a rise, and never touches a wall time" {
    baseline := AgentLoopTestBaseline(true)
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

test "agent-loop bench: wall time is judged against the baseline median times its tolerance" {
    baseline := AgentLoopTestBaseline(true)
    assert AgentLoopTimingFailures(baseline, AgentLoopTestObserved(40, 1500)).Count == 0
    over := AgentLoopTimingFailures(baseline, AgentLoopTestObserved(40, 1501))
    assert over.Count == 1
    assert over[0].Contains("over the limit 1500 ms")
}

test "agent-loop bench: wall time is unjudged on a loaded machine, against a loaded baseline, or under SYSTEMS_BENCH=skip" {
    quiet := new BenchMachineLoad(1200, 10)
    loaded := new BenchMachineLoad(3400, 10)
    assert AgentLoopTimingUnjudgedReason(AgentLoopTestBaseline(true), quiet, false) == ""
    assert AgentLoopTimingUnjudgedReason(AgentLoopTestBaseline(true), loaded, false).Contains("at or above the 2")
    assert AgentLoopTimingUnjudgedReason(AgentLoopTestBaseline(true), BenchUnknownLoad(), false) != ""
    assert AgentLoopTimingUnjudgedReason(AgentLoopTestBaseline(false), quiet, false).Contains("a record, not a budget")
    assert AgentLoopTimingUnjudgedReason(AgentLoopTestBaseline(true), quiet, true) == "SYSTEMS_BENCH=skip"
}

test "agent-loop bench: the table states every counter and puts a compared value beside each one that moved" {
    observed := AgentLoopTestObserved(8, 500)
    table := AgentLoopRenderTable(observed, AgentLoopTestBaseline(true).Rows, "the baseline")
    assert table.Contains("Parenthesised values are the baseline")
    assert table.Contains("| parsed | emit parses | analyzed | emitted | refs loaded | spawned |")
    assert table.Contains("| 500 (1000, -50%) |")
    assert table.Contains("| 8 (40) |")
    assert table.Contains("| 684 |")

    plain := AgentLoopRenderTable(observed, null, "")
    assert !plain.Contains("Parenthesised")
    assert plain.Contains("| small | 448 | no-op check | cold | 0 | 500 |")
}

test "agent-loop bench: the committed baseline is usable and covers every size, scenario and mode" {
    baseline := AgentLoopParseBaseline(File.ReadAllText(AgentLoopBaselinePath(BenchRepositoryRoot())))
    assert AgentLoopBaselineRefusal(baseline) == "", AgentLoopBaselineRefusal(baseline)
    sizes := AgentLoopSizes()
    scenarios := AgentLoopScenarios()
    assert baseline.Rows.Count == sizes.Count * scenarios.Count * 2
    i := 0
    while i < sizes.Count {
        j := 0
        while j < scenarios.Count {
            assert AgentLoopFindRow(baseline.Rows, sizes[i].Name, scenarios[j].Id, AgentLoopModeCold()) != null, sizes[i].Name + " / " + scenarios[j].Id
            assert AgentLoopFindRow(baseline.Rows, sizes[i].Name, scenarios[j].Id, AgentLoopModeWarm()) != null, sizes[i].Name + " / " + scenarios[j].Id
            j = j + 1
        }
        i = i + 1
    }
}

// ─── THE GATE ─────────────────────────────────────────────────────────────────────────────────

func AgentLoopGateRecordLine(failures: List<string>, unjudged: string, load: BenchMachineLoad, samples: int, cliCommit: string): string {
    verdict := "ok"
    if failures.Count > 0 {
        verdict = "FAILED (" + BenchIntText(failures.Count) + "): " + String.Join(" | ", failures)
    }

    timing := "timing judged"
    if unjudged != "" {
        timing = "timing unjudged: " + unjudged
    }

    return "agent-loop gate: " + verdict + "; counters judged exactly; " + timing + "; samples=" + BenchIntText(samples) + " load=" + BenchLoadText(load.LoadThousandths) + " cores=" + BenchCountText(load.Cores) + " cliCommit=" + cliCommit
}

test "agent-loop gate: the edit-check-build-test loop does exactly the baselined work, and its wall time is judged only on an idle machine" {
    // SILENT ON EVERY PATH, as the compile-time gate above is. The counters are judged on EVERY run,
    // loaded or not and under SYSTEMS_BENCH=skip too: a count of files parsed does not move with
    // load, so load cannot excuse it. Only the wall-time half is declined, and when it is, ONE
    // sample per row is taken, because a median nobody will judge is not worth three.
    repositoryRoot := BenchRepositoryRoot()
    baseline := AgentLoopParseBaseline(File.ReadAllText(AgentLoopBaselinePath(repositoryRoot)))
    refusal := AgentLoopBaselineRefusal(baseline)
    assert refusal == "", "agent-loop gate: " + refusal

    cliDll := BenchDefaultCliDll(repositoryRoot)
    assert File.Exists(cliDll), "agent-loop gate: the CLI under test was not found at " + cliDll + ". Build it with: ./scripts/dev.sh"
    assert AgentLoopCliSupportsStats(cliDll), "agent-loop gate: the CLI under test at " + cliDll + " does not list --stats in `nlc build --help`."

    load := BenchReadMachineLoad()
    unjudged := AgentLoopTimingUnjudgedReason(baseline, load, BenchGateSkipRequested())
    samples := 1
    if unjudged == "" {
        samples = baseline.Runs
    }

    rows := AgentLoopMeasureMatrix(cliDll, repositoryRoot, AgentLoopGateSizeNames(), samples, true, false, false)
    failures := AgentLoopCounterFailures(baseline, rows)
    if unjudged == "" {
        failures.AddRange(AgentLoopTimingFailures(baseline, rows))
    }

    line := AgentLoopGateRecordLine(failures, unjudged, load, samples, BenchReadCliCommit(repositoryRoot))
    _ = AgentLoopWriteGateRecord(repositoryRoot, line, AgentLoopRenderTable(rows, baseline.Rows, "the committed baseline " + AgentLoopBaselineRelativePath()))
    assert failures.Count == 0, line + " - the full table is in artifacts/agent-loop/last-gate-run.md"
}

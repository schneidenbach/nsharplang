namespace NSharpLang.CompileTimeBench

import System
import System.Collections.Generic
import System.IO


// WHAT THIS FILE STATES.
//
// Every kernel the compile-time report is assembled from, proven on literal inputs — no process,
// no clock, no repository — plus the one gate that spends real time: a live `nlc build` of
// `src/NSharpLang.Compiler.Core`, compared against the checked-in baseline.
//
// The gate and the harness share ONE owner for "run a build and measure it", `BenchMeasureOnce`.
// Nothing here re-implements the spawn, the timing parse or the median.
//
// NOTHING IN THIS FILE WRITES TO STDOUT OR STDERR, ON ANY PATH. The product gate's Step 3a captures
// `nlc test --json` with `> out 2>&1` and parses the whole file as one JSON document, so a single
// stray line — a progress note, a "skipped" note, a green summary — makes a passing run unreadable
// and turns the gate red. Every fact a failure needs travels in the assertion message instead.

// ─── HELPERS ──────────────────────────────────────────────────────────────────────────────────
func BenchTestLongs(a: long, b: long, c: long): long[] {
    values := new long[](3)
    values[0] = a
    values[1] = b
    values[2] = c
    return values
}

func BenchTestScratchDirectory(name: string): string {
    directory := Path.Combine(
        Path.GetTempPath(),
        "nsharp-compile-bench-" + name + "-" + BenchLongText(DateTime.UtcNow.Ticks)
    )
    BenchDeleteDirectory(directory)
    Directory.CreateDirectory(directory)
    return directory
}

func BenchTestBaselinePath(): string {
    return Path.Combine(
        Path.Combine(Path.Combine(BenchRepositoryRoot(), "tests"), "fixtures"),
        Path.Combine("compile-time", "bootstrap-build-baseline.golden.json")
    )
}

func BenchTestStageText(): string {
    return "Core phase/counter contract plus a deterministic Core-scale build through IL emission"
}

func BenchTestPlaceholderBaselineJson(): string {
    counters := "\"filesParsed\":1,\"emitParses\":1,\"filesAnalyzed\":1,\"assembliesEmitted\":1,\"referenceAssembliesLoaded\":1,\"processesSpawned\":0"
    return "{\"schemaVersion\":3,\"project\":\"src/NSharpLang.Compiler.Core\",\"command\":\"build\",\"stage\":\"" + BenchTestStageText() + "\",\"expectedExitCode\":1,\"phaseContract\":\"" + BenchCurrentPhaseContract() + "\",\"phaseDiagnosticMultiset\":\"NL011 ×1, NL202 ×1\",\"files\":1,\"lines\":1,\"coreCounters\":{" + counters + "},\"emitCounters\":{" + counters + "}}"
}

func BenchTestMeasuredBaselineJson(): string {
    return BenchTestPlaceholderBaselineJson()
}

func BenchTestCheckEnvelopeJson(): string {
    return "{\"schemaVersion\":1,\"command\":\"check\",\"checkedFiles\":3,\"ok\":false,\"results\":[" + "{\"code\":\"NL402\",\"severity\":\"error\"}," + "{\"code\":\"NL202\",\"severity\":\"error\"}," + "{\"code\":\"NL402\",\"severity\":\"error\"}," + "{\"code\":\"NL905\",\"severity\":\"warning\"}," + "{\"code\":\"NL202\",\"severity\":\"error\"}," + "{\"code\":\"NL402\",\"severity\":\"error\"}" + "],\"summary\":{\"errors\":5,\"warnings\":1,\"info\":0}}"
}

// A three-line `--timings` block exactly as `BuildCommandKernels.GetTimingsMessage` writes it.
func BenchTestTimingsStderr(): string {
    return "Build timings:\n  Resolve:    0.4s\n  Emit IL:    12.1s\n  Total:      12.5s\n"
}

// The same block as it actually arrives: the CLI's own diagnostic first, then the timings, then
// the BSD time utility's rusage dump on the very same stream.
func BenchTestMacOsMixedStderr(): string {
    return "Program.nl(3,5): warning NL001: Variable 'unused' is declared but never read\n" + "Build timings:\n  Resolve:    0.4s\n  Emit IL:    12.1s\n  Total:      12.5s\n" + "       12.63 real        21.44 user         2.10 sys\n" + "           142606336  maximum resident set size\n" + "                   0  average shared memory size\n" + "               33418  page reclaims\n"
}

func BenchTestLinuxMixedStderr(): string {
    return "Build timings:\n  Resolve:    0.4s\n  Emit IL:    12.1s\n  Total:      12.5s\n" + "\tCommand being timed: \"dotnet Cli.dll build\"\n" + "\tUser time (seconds): 21.44\n" + "\tMaximum resident set size (kbytes): 139264\n" + "\tExit status: 0\n"
}

// ─── THE MEDIAN RULE ──────────────────────────────────────────────────────────────────────────

test "compile-time bench: the median of an ODD run count is the middle measured value" {
    values := BenchTestLongs(900, 100, 500)
    assert BenchMedian(values, 3) == 500
}

test "compile-time bench: the median of an EVEN run count is the LOWER middle measured value, never an average of two" {
    values := new long[](4)
    values[0] = 400L
    values[1] = 100L
    values[2] = 300L
    values[3] = 200L
    assert BenchMedian(values, 4) == 200
}

test "compile-time bench: the median of a SINGLE run is that run, and of no runs at all is the unmeasured marker -1" {
    values := new long[](1)
    values[0] = 77L
    assert BenchMedian(values, 1) == 77
    assert BenchMedian(values, 0) == -1
}

test "compile-time bench: min and max report the extremes of the measured runs and leave the input order alone" {
    values := BenchTestLongs(900, 100, 500)
    assert BenchMinimum(values, 3) == 100
    assert BenchMaximum(values, 3) == 900
    assert values[0] == 900
}

// ─── THE `--timings` PARSER ───────────────────────────────────────────────────────────────────

test "compile-time bench: an elapsed text is read in the two forms FormatElapsedMilliseconds writes, and nothing else" {
    assert BenchParseElapsedText("0.0s") == 0
    assert BenchParseElapsedText("1.2s") == 1200
    assert BenchParseElapsedText("59.9s") == 59900
    assert BenchParseElapsedText("1m 00s") == 60000
    assert BenchParseElapsedText("12m 10s") == 730000
    assert BenchParseElapsedText("12.5") == -1
    assert BenchParseElapsedText("") == -1
    assert BenchParseElapsedText("fast") == -1
}

test "compile-time bench: the three --timings lines parse to resolve, emit and total milliseconds" {
    timings := BenchParseBuildTimings(BenchTestTimingsStderr())
    assert BenchBoolText(timings.Found) == "true"
    assert timings.ResolveMs == 400
    assert timings.EmitMs == 12100
    assert timings.TotalMs == 12500
}

test "compile-time bench: a stderr with no --timings block reports NOT found rather than zeros" {
    timings := BenchParseBuildTimings("error NL202: something went wrong\n")
    assert BenchBoolText(timings.Found) == "false"
    assert timings.ResolveMs == -1
    assert timings.EmitMs == -1
    assert timings.TotalMs == -1
}

test "compile-time bench: the --timings block survives a stderr that also carries a diagnostic and the macOS time utility's rusage dump" {
    stderr := BenchTestMacOsMixedStderr()
    timings := BenchParseBuildTimings(BenchStripTimeUtilityLines(stderr))
    assert BenchBoolText(timings.Found) == "true"
    assert timings.ResolveMs == 400
    assert timings.EmitMs == 12100
    assert timings.TotalMs == 12500
}

test "compile-time bench: stripping the time utility keeps the CLI's own stderr — the diagnostic and the whole timings block — and drops every rusage row" {
    cliStderr := BenchStripTimeUtilityLines(BenchTestMacOsMixedStderr())
    assert cliStderr.IndexOf("warning NL001", StringComparison.Ordinal) >= 0
    assert cliStderr.IndexOf("Build timings:", StringComparison.Ordinal) >= 0
    assert cliStderr.IndexOf("Emit IL:", StringComparison.Ordinal) >= 0
    assert cliStderr.IndexOf("maximum resident set size", StringComparison.Ordinal) < 0
    assert cliStderr.IndexOf("real", StringComparison.Ordinal) < 0
}

test "compile-time bench: a diagnostic's source-line gutter starts with a line NUMBER and is still kept — only plain-word rusage rows are the time utility's" {
    stderr := "error NL012: Parameter 'name' in 'ParseTypeBody' is never read\n" + "1486 |     func ParseTypeBody(name: string): List<Declaration> {\n" + "           142606336  maximum resident set size\n"
    cliStderr := BenchStripTimeUtilityLines(stderr)
    assert cliStderr.IndexOf("1486 |", StringComparison.Ordinal) > 0
    assert cliStderr.IndexOf("maximum resident set size", StringComparison.Ordinal) < 0
    assert BenchParsePeakRssBytes(stderr) == 142606336
}

test "compile-time bench: stripping the time utility on Linux drops the tab-indented rows and keeps the space-indented CLI ones" {
    cliStderr := BenchStripTimeUtilityLines(BenchTestLinuxMixedStderr())
    assert cliStderr.IndexOf("Emit IL:", StringComparison.Ordinal) >= 0
    assert cliStderr.IndexOf("Maximum resident set size", StringComparison.Ordinal) < 0
    assert cliStderr.IndexOf("Command being timed", StringComparison.Ordinal) < 0
}

// ─── THE PEAK-RSS PARSER ──────────────────────────────────────────────────────────────────────

test "compile-time bench: the macOS `/usr/bin/time -l` line reports the peak resident set in BYTES" {
    assert BenchParsePeakRssBytes(BenchTestMacOsMixedStderr()) == 142606336
}

test "compile-time bench: the Linux `/usr/bin/time -v` line reports KILOBYTES and is converted to bytes" {
    assert BenchParsePeakRssBytes(BenchTestLinuxMixedStderr()) == 142606336
}

test "compile-time bench: a stderr with no time utility at all reports peak RSS as unavailable, which is an EMPTY cell and never a failure" {
    assert BenchParsePeakRssBytes(BenchTestTimingsStderr()) == -1
    assert BenchCsvNumber(-1) == ""
    assert BenchRssCell(-1) == "—"
}

test "compile-time bench: peak RSS renders as megabytes with one decimal, rounded half-up" {
    assert BenchFormatMegabytes(142606336) == "136.0"
    assert BenchFormatMegabytes(1572864) == "1.5"
    assert BenchFormatMegabytes(0) == "0.0"
    assert BenchFormatMegabytes(-1) == ""
}

// ─── THE CSV ROWS ─────────────────────────────────────────────────────────────────────────────

test "compile-time bench: a build run row carries the CLI's resolve, emit and total alongside the wall clock and the peak RSS" {
    measured := new BenchCommandRun("build", 0, 12634, 142606336)
    measured.ResolveMs = 400
    measured.EmitMs = 12100
    measured.TotalMs = 12500
    assert BenchRunCsvRow("examples/01-hello-world", 2, measured) == "examples/01-hello-world,build,2,0,12634,400,12100,12500,142606336"
}

test "compile-time bench: a check run row leaves the three build-only timing cells EMPTY" {
    measured := new BenchCommandRun("check", 0, 843, 98304)
    assert BenchRunCsvRow("examples/01-hello-world", 1, measured) == "examples/01-hello-world,check,1,0,843,,,,98304"
}

test "compile-time bench: a run with no peak RSS leaves the RSS cell EMPTY and still carries every other column" {
    measured := new BenchCommandRun("check", 1, 220, -1)
    assert BenchRunCsvRow("templates/nsharp-console", 3, measured) == "templates/nsharp-console,check,3,1,220,,,,"
}

test "compile-time bench: the two CSV headers are the columns the report promises" {
    assert BenchRunCsvHeader() == "project,command,run,exitCode,wallMs,resolveMs,emitMs,totalMs,peakRssBytes"
    assert BenchSummaryCsvHeader() == "project,command,files,lines,status,runs,medianWallMs,minWallMs,maxWallMs,medianResolveMs,medianEmitMs,medianTotalMs,medianPeakRssBytes,linesPerSecond"
}

test "compile-time bench: a summary row states files, lines, the status, the medians and the lines-per-second rate" {
    result := new BenchProjectResult("examples/01-hello-world", "build", 1, 12)
    result.Runs = 5
    result.MedianWallMs = 1000
    result.MinWallMs = 900
    result.MaxWallMs = 1400
    result.MedianResolveMs = 300
    result.MedianEmitMs = 600
    result.MedianTotalMs = 900
    result.MedianPeakRssBytes = 98304
    result.LinesPerSecondTenths = BenchLinesPerSecondTenths(12, 1000)
    assert BenchSummaryCsvRow(result) == "examples/01-hello-world,build,1,12,measured,5,1000,900,1400,300,600,900,98304,12.0"
}

test "compile-time bench: a project the compiler REJECTED and a project with NOTHING TO COMPILE are different statuses, not one `ok=false`" {
    rejected := new BenchProjectResult("templates/nsharp-systems-cli", "build", 1, 33)
    rejected.Ok = false
    rejected.Status = BenchFailedStatus()
    rejected.Runs = 1
    rejected.MedianWallMs = 486
    rejected.MinWallMs = 486
    rejected.MaxWallMs = 486
    rejected.LinesPerSecondTenths = BenchLinesPerSecondTenths(33, 486)
    assert BenchSummaryCsvRow(rejected) == "templates/nsharp-systems-cli,build,1,33,failed,1,486,486,486,,,,,67.9"

    empty := new BenchProjectResult("tests/native/as-boxing", "build", 0, 0)
    empty.Status = BenchNoSourcesStatus()
    assert BenchSummaryCsvRow(empty) == "tests/native/as-boxing,build,0,0,no non-test sources,0,-1,-1,-1,,,,,"
}

test "compile-time bench: a project with no non-test sources contributes NO project and NO lines to an aggregate" {
    results := new List<BenchProjectResult>()

    measured := new BenchProjectResult("examples/01-hello-world", "build", 1, 20)
    measured.Runs = 1
    measured.MedianWallMs = 1000
    results.Add(measured)

    empty := new BenchProjectResult("tests/native/as-boxing", "build", 0, 0)
    empty.Status = BenchNoSourcesStatus()
    results.Add(empty)

    aggregate := BenchAggregateOver(results, "build", "measured corpus projects", false)
    assert aggregate.Projects == 1
    assert aggregate.Lines == 20
    assert aggregate.SumMedianWallMs == 1000
}

test "compile-time bench: a CSV cell that could break a row is quoted and its quotes doubled" {
    assert BenchCsvCell("examples/01-hello-world") == "examples/01-hello-world"
    assert BenchCsvCell("a,b") == "\"a,b\""
    assert BenchCsvCell("say \"hi\"") == "\"say \"\"hi\"\"\""
}

// ─── THE LINES-PER-SECOND FORMULA ─────────────────────────────────────────────────────────────

test "compile-time bench: lines per second is lines divided by the median wall clock in seconds, to one decimal, rounded half-up" {
    assert BenchFormatTenths(BenchLinesPerSecondTenths(1000, 1000)) == "1000.0"
    assert BenchFormatTenths(BenchLinesPerSecondTenths(1000, 2000)) == "500.0"
    assert BenchFormatTenths(BenchLinesPerSecondTenths(250000, 120000)) == "2083.3"
    assert BenchFormatTenths(BenchLinesPerSecondTenths(12, 5000)) == "2.4"
}

test "compile-time bench: a project with no lines, or a run whose wall clock did not advance, has NO rate rather than a fabricated one" {
    assert BenchLinesPerSecondTenths(0, 1000) == -1
    assert BenchLinesPerSecondTenths(1000, 0) == -1
    assert BenchRateCell(-1) == "—"
}

test "compile-time bench: only `\\n`-terminated lines are counted, so a trailing fragment with no newline is not a line" {
    assert BenchCountLines("a\nb\nc\n") == 3
    assert BenchCountLines("a\nb\nc") == 2
    assert BenchCountLines("") == 0
}

// ─── THE STRUCTURAL BASELINE AND RELATIVE VERDICT ─────────────────────────────────────────────

test "compile-time baseline: schema three retains stage and exact CompilerWorkCounters without absolute timing fields" {
    baseline := BenchParseBaseline(File.ReadAllText(BenchTestBaselinePath()))
    assert baseline.SchemaVersion == 3
    assert baseline.Project == "src/NSharpLang.Compiler.Core"
    assert baseline.Stage.Contains("Core phase/counter contract")
    assert baseline.PhaseContract == BenchCurrentPhaseContract()
    assert baseline.PhaseDiagnosticMultiset == BenchCurrentPhaseDiagnosticMultiset()
    assert baseline.CoreCounters != null
    assert baseline.EmitCounters != null
    assert BenchBaselineRefusal(baseline) == ""

    json := File.ReadAllText(BenchTestBaselinePath())
    assert !json.Contains("medianWallMs")
    assert !json.Contains("medianPeakRssBytes")
    assert !json.Contains("toleranceFactor")
    assert json.Contains("coreCounters")
    assert json.Contains("emitCounters")
}

test "compile-time baseline: missing stage, phase contract or CompilerWorkCounters is refused by name" {
    baseline := BenchParseBaseline(BenchTestPlaceholderBaselineJson())
    noStage := new BenchBaseline(3, baseline.Project, baseline.Command, "", 1, BenchCurrentPhaseContract(), BenchCurrentPhaseDiagnosticMultiset(), baseline.CoreCounters, baseline.EmitCounters)
    assert BenchBaselineRefusal(noStage).StartsWith("baseline stage is missing")
    noContract := new BenchBaseline(3, baseline.Project, baseline.Command, "s", 1)
    assert BenchBaselineRefusal(noContract).StartsWith("baseline phaseContract is missing")
    noCounters := new BenchBaseline(3, baseline.Project, baseline.Command, "s", 1, BenchCurrentPhaseContract(), BenchCurrentPhaseDiagnosticMultiset())
    assert BenchBaselineRefusal(noCounters).Contains("missing CompilerWorkCounters")
}

test "compile-time baseline: the checked-in Core phase contract keeps the exact exit and diagnostic census" {
    baseline := BenchParseBaseline(File.ReadAllText(BenchTestBaselinePath()))
    assert baseline.ExpectedExitCode == 1
    assert baseline.PhaseContract == "analysis-before-strict-lint/v1"
    assert baseline.PhaseDiagnosticMultiset == "NL011 ×1, NL202 ×1"
}

test "compile-time relative gate: paired ratios are formed before the median and accept at 1.20x" {
    head := new long[](9)
    control := new long[](9)
    i := 0
    while i < 9 {
        head[i] = 1200
        control[i] = 1000
        i = i + 1
    }
    assert BenchMedianPairRatioThousandths(head, control, 9) == 1200
    assert BenchCompileTimeRatioFailure(head, control, 9) == ""
    table := BenchPairedBuildTable(head, control, 9)
    assert table.Contains("| 1 | 1000 | 1200 | 1.2x |")
    assert table.Contains("exact sign-test 95% lower bound 1.2x")
}

test "compile-time relative gate: the deliberate 500 ms and 1,500 ms head delays fail the confidence and floor rule" {
    head500 := new long[](9)
    head1500 := new long[](9)
    control := new long[](9)
    i := 0
    while i < 9 {
        control[i] = 1000
        head500[i] = control[i] + BenchConfiguredDelayMs("head", "500")
        head1500[i] = control[i] + BenchConfiguredDelayMs("head", "1500")
        i = i + 1
    }
    failure500 := BenchCompileTimeRatioFailure(head500, control, 9)
    failure1500 := BenchCompileTimeRatioFailure(head1500, control, 9)
    assert failure500.Contains("median slowdown 500 ms >= 30 ms"), failure500
    assert failure1500.Contains("median slowdown 1500 ms >= 30 ms"), failure1500
    assert failure500.Contains("95% exact sign interval lower bound")
    assert failure500.Contains("1.2x")
}

test "compile-time relative gate: missing or invalid pair measurements fail closed" {
    head := new long[](9)
    control := new long[](9)
    i := 0
    while i < 9 {
        head[i] = 1200
        control[i] = 1000
        i = i + 1
    }
    head[1] = 0
    control[8] = 0
    assert BenchMedianPairRatioThousandths(head, control, 9) == -1
    assert BenchCompileTimeRatioFailure(head, control, 9).Contains("non-positive base")
}

test "compile-time relative gate: negative ratio sentinels render as readable signed decimals" {
    assert BenchFormatFixed3(-1) == "-0.001"
    assert BenchFormatFixed3(-1200) == "-1.2"
}

test "compile-time structural gate: CompilerWorkCounters must equal the baseline exactly" {
    expected := new AgentLoopCounters(468, 137, 278, 2, 431, 0)
    assert BenchCoreCounterFailure("Core", expected, expected) == ""
    changed := new AgentLoopCounters(468, 137, 279, 2, 431, 0)
    assert BenchCoreCounterFailure("Core", expected, changed).Contains("fix increases")
    assert BenchCoreCounterFailure("Core", expected, null).Contains("did not write nsharp.cli-stats")
}

test "compile-time gate: only head measurements receive the explicit regression-proof delay" {
    assert BenchConfiguredDelayMs("base", "15") == 0
    assert BenchConfiguredDelayMs("head", "15") == 15
    assert BenchConfiguredDelayMs("head", "invalid") == 0
}

// ─── THE CHECK ENVELOPE'S DIAGNOSTIC CENSUS ───────────────────────────────────────────────────

test "compile-time bench: the check envelope's results are censused by code, ordered by count DESCENDING and then by code ASCENDING, whatever order they arrived in" {
    assert BenchDiagnosticCensus(BenchTestCheckEnvelopeJson()) == "6 results: NL402 ×3, NL202 ×2, NL905 ×1"
    assert BenchDiagnosticResultCount(BenchTestCheckEnvelopeJson()) == 6
}

test "compile-time bench: an envelope with an EMPTY results array, no results array at all, or no output has NO census and no count" {
    empty := "{\"schemaVersion\":1,\"command\":\"check\",\"checkedFiles\":1,\"ok\":true,\"results\":[]}"
    assert BenchDiagnosticCensus(empty) == ""
    assert BenchDiagnosticResultCount(empty) == 0

    noResults := "{\"schemaVersion\":1,\"command\":\"check\",\"ok\":false,\"error\":\"boom\"}"
    assert BenchDiagnosticCensus(noResults) == ""
    assert BenchDiagnosticResultCount(noResults) == -1

    assert BenchDiagnosticCensus("") == ""
    assert BenchDiagnosticResultCount("") == -1
}

test "compile-time bench: a result carrying no code is still counted, so the per-code counts always add up to the stated total" {
    envelope := "{\"results\":[{\"severity\":\"error\"},{\"code\":\"NL202\",\"severity\":\"error\"}]}"
    assert BenchDiagnosticCensus(envelope) == "2 results: (no code) ×1, NL202 ×1"
}

test "compile-time bench: rendered build diagnostics read compact headers and rich canonical URLs as one exact multiset" {
    rendered := "-- TYPE MISMATCH -- Semantic.nl\n" + "8| return TakeNumber(\"NL999\")\n" + "Read more: https://schneidenbach.github.io/nsharplang/docs/errors/NL202\n\n" + "error NL011: This catch block is empty\n" + "error NL011: This second catch block is empty\n"
    assert BenchRenderedBuildDiagnosticMultiset(rendered) == "NL011 ×2, NL202 ×1"
}

test "compile-time bench: rendered diagnostic extraction fails closed on prose and malformed identities" {
    malformed := BenchRenderedBuildDiagnosticMultiset("hint: see NL202\nRead more: https://example.test/NL011\nerror NL12: short\nerror NL202 missing colon\n")
    assert malformed == "(unrecognized diagnostic rendering) ×3", malformed
    assert BenchDiagnosticCodeAt("NL202:", 0, true) == "NL202"
    assert BenchDiagnosticCodeAt("NL202x", 0, true) == ""
    assert BenchDiagnosticCodeAt("NL202", 0, false) == "NL202"
    assert BenchDiagnosticCodeAt("NL202/extra", 0, false) == ""
}

test "compile-time bench: the phase contract accepts only its exact diagnostic multiset and calls no evidence unknown" {
    expected := BenchCurrentPhaseDiagnosticMultiset()
    assert BenchPhaseContractRefusal(BenchCurrentPhaseContract(), expected, expected, 1, true) == ""
    assert BenchPhaseContractRefusal(BenchCurrentPhaseContract(), expected, "", 1, true).IndexOf("stage is unknown", StringComparison.Ordinal) > 0
    assert BenchPhaseContractRefusal(BenchCurrentPhaseContract(), expected, expected, 0, false).IndexOf("diagnostic exit 1", StringComparison.Ordinal) > 0
    assert BenchPhaseContractRefusal(BenchCurrentPhaseContract(), expected, expected, 1, false).IndexOf("without the CLI's own build-failure banner", StringComparison.Ordinal) > 0
    mismatch := BenchPhaseContractRefusal(BenchCurrentPhaseContract(), expected, "NL011 ×1", 1, true)
    assert mismatch.IndexOf("expected [NL011 ×1, NL202 ×1]", StringComparison.Ordinal) > 0
    assert mismatch.IndexOf("observed [NL011 ×1]", StringComparison.Ordinal) > 0
    malformed := BenchPhaseContractRefusal(BenchCurrentPhaseContract(), expected, "NL011 ×1, NL202 ×1, (unrecognized diagnostic rendering) ×1", 1, true)
    assert malformed.IndexOf("unrecognized diagnostic rendering", StringComparison.Ordinal) > 0
}

// ─── THE SOURCE-SELECTION RULE ────────────────────────────────────────────────────────────────

test "compile-time bench: the replicated rule takes the `.nl` files nlc build and nlc check compile — a `.tests.nl` beside a `.nl` is DROPPED and a `.nl` under `bin/` is never reached" {
    root := BenchTestScratchDirectory("selection")
    Directory.CreateDirectory(Path.Combine(root, "bin"))
    Directory.CreateDirectory(Path.Combine(root, "obj"))
    Directory.CreateDirectory(Path.Combine(root, "nested"))
    File.WriteAllText(Path.Combine(root, "Program.nl"), "one\ntwo\n")
    File.WriteAllText(Path.Combine(root, "Program.tests.nl"), "dropped\n")
    File.WriteAllText(Path.Combine(Path.Combine(root, "bin"), "Generated.nl"), "never\nreached\n")
    File.WriteAllText(Path.Combine(Path.Combine(root, "obj"), "Intermediate.nl"), "never\n")
    File.WriteAllText(Path.Combine(Path.Combine(root, "nested"), "Helper.nl"), "three\nfour\nfive\n")

    measure := BenchMeasureProjectSources(root)
    files := measure.Files
    lines := measure.Lines
    BenchDeleteDirectory(root)

    assert files == 2
    assert lines == 5
}

test "compile-time bench: the `.tests.nl` suffix is matched case-insensitively and only as a whole suffix" {
    assert BenchIsTestSourcePath("/x/Program.tests.nl")
    assert BenchIsTestSourcePath("/x/Program.TESTS.NL")
    assert !BenchIsTestSourcePath("/x/Program.nl")
    assert !BenchIsTestSourcePath("/x/tests.nl")
    assert !BenchIsTestSourcePath("/x/Program.tests.nl.bak")
}

test "compile-time bench: the skipped source directories are exactly the twelve ProjectConfig.ShouldSkipSourceDirectory skips" {
    assert BenchShouldSkipSourceDirectory("bin")
    assert BenchShouldSkipSourceDirectory("OBJ")
    assert BenchShouldSkipSourceDirectory("node_modules")
    assert BenchShouldSkipSourceDirectory("out")
    assert BenchShouldSkipSourceDirectory(".vscode-test")
    assert BenchShouldSkipSourceDirectory(".worktrees")
    assert !BenchShouldSkipSourceDirectory("nested")
    assert !BenchShouldSkipSourceDirectory("src")
}

// ─── THE CORPUS ───────────────────────────────────────────────────────────────────────────────

// 68 at 8cf40128a; 70 since the two 2026-09 measurement branches merged (tests/native/systems-vectorization-facts and
// tests/fixtures/systems-vectorization/opt-out-probe joined; this harness's own project.yml is excluded by BenchSelfProjectPath);
// 71 since 022/3b-1 added tests/native/external-abstract-override; 72 since the language server's
// lifetime contract added tests/native/lsp-lifetime; 73 since the error-docs slice added
// tests/native/error-docs-contract; 74 since the diagnostic-honesty slice added
// tests/native/diagnostic-honesty; 75 since the Analyzer SDK prerequisite added
// tests/native/sdk-project-reference-boundary; 76 since diagnostics moved into
// tests/native/language-server-diagnostics; 77 since reference resolution moved into
// tests/native/reference-resolution; 78-81 as the 2026-09-10 capability arc added
// tests/native/readonly-structs, generic-type-receivers, type-arity and external-generic-construction;
// 82 since static members on generic types added tests/native/generic-static-members; 83 since the
// SimdReductions translation added tests/native/simd-reductions; 85 since class inheritance added
// tests/native/class-inheritance and tests/native/generic-member-types; 86 since .NET generic interop
// over a declaration's own type parameters added tests/native/constructed-generic-interop; 87 since
// generic methods on user types added tests/native/user-generic-methods; 88 since named tuple
// element metadata added tests/native/tuple-names; 89 since external generics over complete source
// types added tests/native/complete-source-generic-args; 90 since qualified names added
// tests/native/qualified-names; 91 since the faithful N# translations of `Result<TOk, TErr>` and
// `Union<T0, T1>` added tests/native/runtime-acceptance; 93 since generic methods declared by an
// EXTERNAL type added tests/native/external-generic-methods; 94 since the converter census's flow
// and signature rules added tests/native/census-flow-rules; 95 since array covariance and
// target-typed array literals added tests/native/census-conversions; 96 since the C# `foreach`
// pattern added tests/native/census-pattern-foreach; 97 since the type-argument scan and per-element
// tuple naming added tests/native/census-parse-shapes; 98 since lambda parameter inference and
// extension-result widening added tests/native/census-lambda-inference; 99 since field initializers
// became ordinary expressions added tests/native/census-field-initializers; 100 since attributes a
// program declares for itself added tests/native/census-source-attributes; 101 since one extension-call
// path from receiver to IL added tests/native/census-extension-calls; 102 since block-scoped local
// functions added tests/native/census-local-functions; 103 since ordinary expressions inside iterator
// bodies added tests/native/census-iterators; 104 since a camelCase top-level function became visible
// to every file of its namespace added tests/native/census-visibility; 105 since the leftover emit shapes
// added tests/native/census-emit-shapes; 106 since free functions keyed by their namespace added
// tests/native/census-free-function-identity; 107 since the test-framework reference set and
// attributes on `test` blocks added tests/native/census-testrefs; 108 since lifted operators over a
// nullable value type added tests/native/census-lifted-operators; 109 since `on`/`off` event
// subscriptions reached the columnar pipeline added tests/native/census-events; 110 since NL209 for a simple name two imports supply added tests/native/census-imports; 111 since one accessibility relation for source and external members added tests/native/census-accessibility; 112 since the using statement added tests/native/census-using-statement; 113 since overload specificity by better conversion added tests/native/census-overload-resolution; 114 since async lambdas and the bare `throw` rethrow added tests/native/census-async-lambdas; 115 since source-declared events added tests/native/census-source-events; 116 since one type name declared in two files of one namespace added tests/native/census-duplicate-declarations; 117 since NL010 and NL002 answered from the analyzer's binding facts added tests/native/census-import-usage; 118 since an interface's value member became a get-only abstract property slot added tests/native/census-interfaces; 119 since InternalsVisibleTo grants added tests/native/census-internals-visible-to; 120 since the display chain a nested lambda walks added tests/native/census-closures; 121 since the shipped backend contracts moved off `Console.SetOut` and onto the real binary added tests/native/compilation-backend; 122 since the collectible-load-context claims and the Assembly.Load guard outlived their C# helper added tests/native/test-assembly-load-contexts; 123 since the daemon lifecycle, its json-rpc envelopes and its socket paths added tests/native/daemon-command; 124 since the shipped CLI parity audit added tests/native/cli-parity-audit; 125 since the gate's input sets, the VS Code harness self-test, the setup scripts and the ilverify baseline added tests/native/gate-script-contracts; 126 since the language-server handler surface added tests/native/language-server-handlers; 127 since the self-host front-door gate step added tests/native/self-host-front-door; 128 since named arguments reached the columnar planners added tests/native/census-named-arguments; 129 since reflected defaults gained an independently built metadata fixture added tests/fixtures/census-named-arguments-metadata-defaults; 130 since init-only and required members reached the product path added tests/native/census-init-required; 131 since source types became generic signature arguments added tests/native/census-generic-signatures; 132-134 since the inline and typed OmniSharp delegate hosts plus their native runtime contract added tests/fixtures/staticrecv-runtime-inline, tests/fixtures/staticrecv-runtime-typed and tests/native/census-staticrecv-runtime; 135 since the receiver relation for a NON-GENERIC extension slot — the first defect the tip compiler's self-host found — added tests/native/source-typed-explicit-generic-extension; 136 since the type a `catch` clause names left the corelib-only exception index added tests/native/census-catch-types; 137 since the whole instance surface of `System.Diagnostics.Process` and a struct's defaulted optional added tests/native/census-process-members; 138 since a member an external generic interface INHERITS became reachable through a receiver closed over a source type added tests/native/census-source-typed-generic-receiver; 139 since `System.IO.Pipelines` entered the one common-assembly table added tests/native/census-pipelines; 140 since a by-reference argument could name a STATIC field — the `ldsflda` row the plan contract never had — added tests/native/census-static-field-references; 141 since reference-type nullability reached emitted metadata — the annotations an N# assembly's own signatures lost at the boundary — added tests/native/census-nullable-metadata; 142 since an exception's readable properties stopped being gated by a narrower fence than the backend's own added tests/native/census-exception-members; 143 since a `Nullable<T>` member in a REFERENCED assembly became writable — the three write doors that each carried their own copy of the value seam — added tests/native/census-external-nullable-members; 144 since a type the framework FORWARDS out of `System.Runtime` became reachable from emitted code — the resolver that could not follow a forwarder — added tests/native/census-external-type-reach; 145 since a `params` tail became a CALL-SITE shape rather than an exclusion — the packing that made every `LoggerExtensions` member and every `Container<T>` registration reachable — added tests/native/census-params-expansion; 146 since an explicit generic call's RECEIVER became a child of the parser's generic-callee node rather than a re-reading of its span text — the chained spelling every fluent registration spine is written in — added tests/native/census-generic-callee-receiver; 147 since a GENERIC interface method could be implemented — the slot whose type parameters had to be unified with the implementation's by position — added tests/native/census-generic-interface-method; 148 since a `test` block could be lowered under `testFramework: nunit` — the one place the framework choice was still spelled xunit — added tests/native/census-nunit-test-blocks; 149 since the receiver of a member read could be any value rather than one of four named shapes — the missing arm that made a chain stop being plannable at its SECOND hop, so every call taking one declined as unmodeled — added tests/native/census-chained-member-argument; 150 since the preflight gained the emitter's own arm for a bare-name call on the CAPTURED ENCLOSING instance — the lambda-body shape that emitted but could not be typed, so every call that types its arguments refused it — added tests/native/census-captured-receiver-argument; 151 since a name flow has proved present could be passed as an ARGUMENT — the one position where the emitter's unwrap and the recursive door's raw-map reading disagreed, which is what made NL907 advise a change that declined the build — added tests/native/census-narrowed-nullable-argument; 152 since the project's whole reference closure landed in ONE load context — the split that gave the SDK's in-MSBuild emit a different extension universe from `nlc build` for the same project.yml — added tests/native/sdk-emit-path-parity; 153 since a `nuget:` list became a set of ROOTS ordered by distance rather than a first-wins search path, and an unzipped version directory became an INSTALL `dotnet restore` can see — the two places `nlc build` and `dotnet build` disagreed about one packages folder — added tests/native/nuget-resolution-fidelity; 154 since the only thing that built a template was the GATE — the step that caught a wrong package-version rule in the resolver while the native sweep, the estate, the front door and ilverify were all green with it — added tests/native/template-project-smoke; 155 since an N# project could state that it produces no symbol file — the declaration whose absence made a plain `dotnet pack` of any N#-SDK project fail NU5026 for a `.pdb` the emitter never writes — added tests/native/sdk-pack-symbol-contract; 156-157 since `catch ... when` became a REAL CLR filter block rather than the catch-and-rethrow the language forced — the two-pass ordering a rethrow cannot reproduce — added tests/native/census-exception-filters and examples/11-advanced-features/ExceptionFilters; 158-159 since a parameter could be passed READ-ONLY BY REFERENCE — `&T` plus the `In` bit plus `[IsReadOnly]`, which is the pair a C# or F# consumer reads to tell an `in` parameter from a `ref` one — added tests/native/census-in-parameters and examples/11-advanced-features/InParameters; 160 since a camelCase TYPE name became package-private in CLR METADATA as well as in the language — the half of the casing rule that stopped at the compiler, so another assembly could name what a package never exported — added tests/native/census-package-private-types; 161 since the INSTALLED toolchain — packed out of this checkout, staged into a container that holds only the .NET SDK, and driven the way a user's first command drives it — stopped being asserted in C# added tests/native/installed-toolchain-integration; 162-163 since a member could name the INTERFACE whose slot it fills — `func IEnumerable.GetEnumerator()`, which is the only way to implement `IEnumerable<T>` at all, because its two `GetEnumerator` slots differ only in return type — added tests/native/census-explicit-interface-implementation and examples/11-advanced-features/ExplicitInterfaceImplementation; 164 since the compiler began emitting a TRUE reference assembly — a metadata-only surface with `ldnull; throw` bodies, no private members and no synthesized types, byte-stable across an implementation-only edit — instead of the build task rescoping a copy of the implementation, added tests/native/reference-assembly-surface; 165 since the SDK's emit target began reading `@(ReferencePathWithRefAssemblies)` rather than `@(ReferencePath)`, so a dependent project does NOT re-emit when only a referenced project's implementation changed, added tests/native/sdk-reference-incrementality; 166 since the emitted module version id and COFF timestamp became a hash of the image itself rather than a fresh `Guid` and the second the build happened, so two clean builds of one source are the same bytes, added tests/native/emit-determinism; 167 since the order a compilation reads its files in became a function of the files' names rather than of the directories they sit in, so moving a file between directories no longer changes the emitted bytes, added tests/native/canonical-source-order; 168 since a test process stopped being allowed to write the environment, the current directory or a console stream that the rows running beside it read, added tests/native/process-global-state-guard; 169 since the slice direction of Compiler.Core's source became a row rather than a script run by hand - a file under one slice directory may not reach a top-level name a higher slice owns - added tests/native/compiler-core-slice-direction; 170 since a plain `interface` became nominal in emitted metadata as well as in the analyzer - the columnar duck pass had written every source interface, an empty marker included, onto every class that satisfied it structurally - added tests/native/census-nominal-interfaces; 171-172 since a referenced assembly's type in an ENCLOSING namespace took part in name lookup - the rule a namespace's members follow whichever assembly compiled them, which carving Compiler.Model out of Core needs - added tests/fixtures/census-external-lookup-library and tests/native/census-external-lookup; 173-174 since a referenced assembly's types took the operators and constructor arguments a source type takes - identity `==`, and a constructor chosen from the type's own metadata with its arguments emitted against its parameters, which the rest of the Model carve needed - added tests/fixtures/census-external-operands-library and tests/native/census-external-operands; 175-176 since a referenced assembly's class types took the nullability their source declarations have - a maybe-null value refused for a not-null target, a bare one not-null, and a member mentioning a type parameter read from its definition, which the Model carve's front door exposed - added tests/fixtures/census-external-nullability-library and tests/native/census-external-nullability; 177-178 since a referenced assembly's free functions took part in bare-call lookup - a namespace's free functions are its members wherever they were compiled, which carving Compiler.Syntax out of Core needs, because its parser kernels are global free functions - added tests/fixtures/census-external-free-functions-library and tests/native/census-external-free-functions; 179 since a member inherited from a CLOSED generic source base became a member of that instantiation — `Holder<int>::Describe` rather than the open definition's, which declined every bare, `this.` and receiver call with NL103 and emitted a static field or property the CLR refused to load — added tests/native/census-closed-generic-source-base; 186 since an unchanged compilation is answered from a content-hashed up-to-date stamp and a warm caller's per-file analyses are reused added tests/native/incremental-build; 187 since check, build, test, run, format, lint and fix began routing to a warm per-workspace server — the parity, isolation and recovery rows proven against real processes — added tests/native/daemon-exec.
test "compile-time bench: the corpus is the 187 project.yml projects under examples, tests and templates" {
    projects := BenchCollectCorpusProjects(BenchRepositoryRoot())
    assert projects.Count == 187
    assert BenchListContains(projects, "tests/native/incremental-build")
    assert BenchListContains(projects, "tests/native/daemon-exec")
    assert BenchListContains(projects, "tests/native/census-by-ref-forwarding")
    assert BenchListContains(projects, "tests/native/census-type-parameter-receivers")
    assert BenchListContains(projects, "tests/native/free-function-overloads")
    assert BenchListContains(projects, "tests/fixtures/census-overload-resolution-library")
    assert BenchListContains(projects, "tests/native/census-safe-casts")
    assert BenchListContains(projects, "tests/fixtures/census-external-nullability-library")
    assert BenchListContains(projects, "tests/native/census-external-nullability")
    assert BenchListContains(projects, "tests/fixtures/census-external-operands-library")
    assert BenchListContains(projects, "tests/native/census-external-operands")
    assert BenchListContains(projects, "tests/native/census-nominal-interfaces")
    assert BenchListContains(projects, "tests/fixtures/census-external-lookup-library")
    assert BenchListContains(projects, "tests/native/census-external-lookup")
    assert BenchListContains(projects, "tests/native/compiler-core-slice-direction")
    assert BenchListContains(projects, "tests/native/process-global-state-guard")
    assert BenchListContains(projects, "tests/native/canonical-source-order")
    assert BenchListContains(projects, "tests/native/emit-determinism")
    assert BenchListContains(projects, "tests/native/sdk-reference-incrementality")
    assert BenchListContains(projects, "tests/native/reference-assembly-surface")
    assert BenchListContains(projects, "tests/native/census-explicit-interface-implementation")
    assert BenchListContains(projects, "examples/11-advanced-features/ExplicitInterfaceImplementation")
    assert BenchListContains(projects, "tests/native/installed-toolchain-integration")
    assert BenchListContains(projects, "tests/native/census-package-private-types")
    assert BenchListContains(projects, "tests/native/census-in-parameters")
    assert BenchListContains(projects, "examples/11-advanced-features/InParameters")
    assert BenchListContains(projects, "tests/native/census-exception-filters")
    assert BenchListContains(projects, "examples/11-advanced-features/ExceptionFilters")
    assert BenchListContains(projects, "tests/native/sdk-pack-symbol-contract")
    assert BenchListContains(projects, "tests/native/template-project-smoke")
    assert BenchListContains(projects, "tests/native/nuget-resolution-fidelity")
    assert BenchListContains(projects, "tests/native/sdk-emit-path-parity")
    assert BenchListContains(projects, "tests/native/census-narrowed-nullable-argument")
    assert BenchListContains(projects, "tests/native/census-captured-receiver-argument")
    assert BenchListContains(projects, "tests/native/census-chained-member-argument")
    assert BenchListContains(projects, "tests/native/census-closed-generic-source-base")
    assert BenchListContains(projects, "tests/native/census-generic-callee-receiver")
    assert BenchListContains(projects, "tests/native/census-generic-interface-method")
    assert BenchListContains(projects, "tests/native/census-nunit-test-blocks")
    assert BenchListContains(projects, "tests/native/census-params-expansion")
    assert BenchListContains(projects, "tests/native/census-external-type-reach")
    assert BenchListContains(projects, "tests/native/census-external-nullable-members")
    assert BenchListContains(projects, "tests/native/self-host-front-door")
    assert BenchListContains(projects, "tests/native/source-typed-explicit-generic-extension")
    assert BenchListContains(projects, "tests/native/census-catch-types")
    assert BenchListContains(projects, "tests/native/census-process-members")
    assert BenchListContains(projects, "tests/native/census-source-typed-generic-receiver")
    assert BenchListContains(projects, "tests/native/census-pipelines")
    assert BenchListContains(projects, "tests/native/census-static-field-references")
    assert BenchListContains(projects, "tests/fixtures/census-named-arguments-metadata-defaults")
    assert BenchListContains(projects, "tests/native/census-named-arguments")
    assert BenchListContains(projects, "tests/native/census-init-required")
    assert BenchListContains(projects, "tests/native/census-generic-signatures")
    assert BenchListContains(projects, "tests/native/census-closures")
    assert BenchListContains(projects, "tests/native/census-staticrecv-runtime")
    assert BenchListContains(projects, "tests/fixtures/staticrecv-runtime-inline")
    assert BenchListContains(projects, "tests/fixtures/staticrecv-runtime-typed")
    assert BenchListContains(projects, "tests/native/census-internals-visible-to")
    assert BenchListContains(projects, "tests/native/census-interfaces")
    assert BenchListContains(projects, "tests/native/census-source-events")
    assert BenchListContains(projects, "tests/native/census-async-lambdas")
    assert BenchListContains(projects, "tests/native/census-overload-resolution")
    assert BenchListContains(projects, "tests/native/census-using-statement")
    assert BenchListContains(projects, "tests/native/census-accessibility")
    assert BenchListContains(projects, "tests/native/census-imports")
    assert BenchListContains(projects, "tests/native/census-lifted-operators")
    assert BenchListContains(projects, "tests/native/census-events")
    assert BenchListContains(projects, "tests/native/census-testrefs")
    assert BenchListContains(projects, "tests/native/census-free-function-identity")
    assert BenchListContains(projects, "tests/native/census-local-functions")
    assert BenchListContains(projects, "tests/native/census-emit-shapes")
    assert BenchListContains(projects, "tests/native/census-extension-calls")
    assert BenchListContains(projects, "tests/native/census-lambda-inference")
    assert BenchListContains(projects, "tests/native/census-field-initializers")
    assert BenchListContains(projects, "tests/native/census-source-attributes")
    assert BenchListContains(projects, "examples/01-hello-world")
    assert BenchListContains(projects, "tests/native/qualified-names")
    assert BenchListContains(projects, "tests/native/census-conversions")
    assert BenchListContains(projects, "tests/native/census-pattern-foreach")
    assert BenchListContains(projects, "tests/native/methodimpl-attributes")
    assert BenchListContains(projects, "templates/nsharp-console")
    assert BenchListContains(projects, "tests/native/complete-source-generic-args")
    assert BenchListContains(projects, "tests/native/constructed-generic-interop")
    assert BenchListContains(projects, "tests/native/external-generic-construction")
    assert BenchListContains(projects, "tests/native/census-field-initializers")
    assert BenchListContains(projects, "tests/native/external-generic-methods")
    assert BenchListContains(projects, "tests/native/generic-static-members")
    assert BenchListContains(projects, "tests/native/user-generic-methods")
    assert BenchListContains(projects, "tests/native/language-server-diagnostics")
    assert BenchListContains(projects, "tests/native/ownership-audit")
    assert BenchListContains(projects, "tests/native/reference-resolution")
    assert BenchListContains(projects, "tests/native/sdk-project-reference-boundary")
    assert BenchListContains(projects, "tests/native/simd-reductions")
    assert BenchListContains(projects, "tests/native/tuple-names")
    assert BenchListContains(projects, "tests/native/runtime-acceptance")
    assert BenchListContains(projects, "tests/native/type-arity")
    assert BenchListContains(projects, "tests/native/census-flow-rules")
    assert BenchListContains(projects, "tests/native/census-parse-shapes")
    assert BenchListContains(projects, "tests/native/census-iterators")
    assert BenchListContains(projects, "tests/native/census-visibility")
    assert BenchListContains(projects, "tests/native/compilation-backend")
    assert BenchListContains(projects, "tests/native/test-assembly-load-contexts")
    assert BenchListContains(projects, "tests/native/daemon-command")
    assert BenchListContains(projects, "tests/native/cli-parity-audit")
    assert BenchListContains(projects, "tests/native/gate-script-contracts")
    assert BenchListContains(projects, "tests/native/language-server-handlers")
}

test "compile-time bench: the large-project case is NOT in the corpus, and neither is this harness's own project" {
    projects := BenchCollectCorpusProjects(BenchRepositoryRoot())
    assert !BenchListContains(projects, BenchBootstrapProjectPath())
    assert !BenchListContains(projects, BenchSelfProjectPath())
    assert BenchBootstrapProjectPath() == "src/NSharpLang.Compiler.Core"
    assert BenchSelfProjectPath() == "tests/native/compile-time-bench"
}

test "compile-time bench: the corpus is sorted ordinally by repository-relative directory, so two sweeps report their rows in the same order" {
    projects := BenchCollectCorpusProjects(BenchRepositoryRoot())
    ordered := true
    i := 1
    while i < projects.Count {
        if String.Compare(projects[i - 1], projects[i], StringComparison.Ordinal) >= 0 {
            ordered = false
        }

        i = i + 1
    }

    assert ordered
}

// ─── THE TREE-UNTOUCHED PROOF ─────────────────────────────────────────────────────────────────

test "compile-time bench: an unchanged directory listing DIFFS to nothing, and a written file shows up as an added entry" {
    root := BenchTestScratchDirectory("snapshot")
    File.WriteAllText(Path.Combine(root, "kept.txt"), "kept\n")
    before := BenchSnapshotDirectory(root)
    assert BenchDiffSnapshots(before, BenchSnapshotDirectory(root)) == ""

    File.WriteAllText(Path.Combine(root, "written.txt"), "written\n")
    difference := BenchDiffSnapshots(before, BenchSnapshotDirectory(root))
    BenchDeleteDirectory(root)

    assert difference.IndexOf("+ written.txt|", StringComparison.Ordinal) == 0
}

// ─── THE MACHINE THE MEDIAN WAS TAKEN ON ──────────────────────────────────────────────────────

test "compile-time bench: the one-minute load average is read from the sysctl shape and from a REAL uptime line, macOS and Linux" {
    // The first two are verbatim captures from this machine: `sysctl -n vm.loadavg` and
    // `/usr/bin/uptime`. The third is the Linux shape, which says `load average` singular and
    // separates with commas.
    assert BenchOneMinuteLoadThousandths("{ 4.17 4.42 4.62 }") == 4170
    assert BenchOneMinuteLoadThousandths("13:04  up  3:46, 1 user, load averages: 5.18 4.43 4.57") == 5180
    assert BenchOneMinuteLoadThousandths(" 13:02:41 up 3 days,  4:11,  2 users,  load average: 0.52, 0.58, 0.59") == 520
    assert BenchOneMinuteLoadThousandths("LOAD AVERAGE: 12") == 12000
}

test "compile-time bench: the numbers BEFORE the load figures on an uptime line are never mistaken for the load" {
    // The trap this parser exists to avoid: the first parseable number in a real uptime line is
    // the `1` of "1 user", which would report a machine at 5.18 as idle.
    assert BenchOneMinuteLoadThousandths("13:04  up  3:46, 1 user, load averages: 5.18 4.43 4.57") != 1000
    assert BenchFirstLoadToken("{ 4.17 4.42 4.62 }", 0) == "4.17"
    assert BenchFirstLoadToken(": 0.52, 0.58", 1) == "0.52"
    assert BenchFirstLoadToken("   ", 0) == ""
}

test "compile-time bench: a line in neither shape reports the load as UNREADABLE, which is -1 and never 0" {
    assert BenchOneMinuteLoadThousandths("") == -1
    assert BenchOneMinuteLoadThousandths("no load here") == -1
    assert BenchOneMinuteLoadThousandths("load averages") == -1
    assert BenchOneMinuteLoadThousandths("{ }") == -1
    assert BenchOneMinuteLoadThousandths("load average: sixteen") == -1
}

test "compile-time bench: a load renders as a decimal and an unreadable one as `unknown`, never as a number" {
    assert BenchLoadText(5180) == "5.18"
    assert BenchLoadText(2000) == "2"
    assert BenchLoadText(-1) == "unknown"
}

// THE LIVE READER. Load is retained in trend records, so verify this platform can provide it.
test "compile-time bench: this platform answers with a POSITIVE load average and a positive core count" {
    if OperatingSystem.IsMacOS() || OperatingSystem.IsLinux() {
        load := BenchReadMachineLoad()
        assert load.LoadThousandths > 0, "the platform did not answer with a readable one-minute load average: '" + BenchLoadAverageText() + "'"
        assert load.Cores > 0
    }
}

test "compile-time bench: the live two-file build canary proves analysis runs before strict lint" {
    root := BenchRepositoryRoot()
    cliDll := BenchDefaultCliDll(root)
    assert File.Exists(cliDll), "build the CLI before running the phase canary: " + cliDll
    observed := BenchObserveBuildPhase(cliDll)
    refusal := BenchPhaseContractRefusal(
        BenchCurrentPhaseContract(),
        BenchCurrentPhaseDiagnosticMultiset(),
        observed.DiagnosticMultiset,
        observed.ExitCode,
        observed.SawBuildFailedBanner
    )
    assert refusal == "", refusal + "\n" + observed.Stderr
}

// ─── THE COMMIT UNDER TEST ────────────────────────────────────────────────────────────────────

test "compile-time bench: a clean base CLI explicitly carries the compiler runtime closure" {
    project := "<Project>\n  <ItemGroup>\n    <ProjectReference Include=\"..\\NSharpLang.Compiler.Driver\\NSharpLang.Compiler.Driver.csproj\" />\n    <PackageReference Include=\"YamlDotNet\" Version=\"16.3.0\" />\n  </ItemGroup>\n</Project>"
    normalized := BenchBaseCliProjectWithCompilerDependencies(project)
    modelReference := "..\\NSharpLang.Compiler.Model\\NSharpLang.Compiler.Model.csproj"
    runtimeReference := "..\\NSharpLang.Runtime\\NSharpLang.Runtime.csproj"
    cecilReference := "<PackageReference Include=\"Mono.Cecil\" Version=\"0.11.6\" />"
    driverReference := "..\\NSharpLang.Compiler.Driver\\NSharpLang.Compiler.Driver.csproj"
    assert normalized.Contains(modelReference)
    assert normalized.Contains(runtimeReference)
    assert normalized.Contains(cecilReference)
    assert normalized.IndexOf(modelReference, StringComparison.Ordinal) < normalized.IndexOf(runtimeReference, StringComparison.Ordinal)
    assert normalized.IndexOf(runtimeReference, StringComparison.Ordinal) < normalized.IndexOf(driverReference, StringComparison.Ordinal)
    assert BenchBaseCliProjectWithCompilerDependencies(normalized) == normalized
}

test "compile-time bench: base cache reuses head package dependencies and preserves base compiler assemblies" {
    root := BenchTestScratchDirectory("base-runtime-closure")
    headCliDirectory := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0")
    baseCliDirectory := Path.Combine(root, "base-cli")
    Directory.CreateDirectory(headCliDirectory)
    Directory.CreateDirectory(baseCliDirectory)
    headCliDll := Path.Combine(headCliDirectory, "Cli.dll")
    baseCliDll := Path.Combine(baseCliDirectory, "Cli.dll")
    File.WriteAllText(headCliDll, "head cli")
    File.WriteAllText(Path.ChangeExtension(headCliDll, ".deps.json"), "head dependency manifest")
    File.WriteAllText(Path.Combine(headCliDirectory, "Microsoft.Build.Framework.dll"), "head package")
    File.WriteAllText(Path.Combine(headCliDirectory, "NSharpLang.Compiler.Emit.dll"), "head compiler")
    File.WriteAllText(baseCliDll, "base cli")
    File.WriteAllText(Path.ChangeExtension(baseCliDll, ".deps.json"), "base dependency manifest")
    File.WriteAllText(Path.Combine(baseCliDirectory, "NSharpLang.Compiler.Emit.dll"), "base compiler")
    File.WriteAllText(Path.Combine(baseCliDirectory, "Microsoft.Build.Framework.dll"), "old package")

    refusal := BenchApplyHeadCliDependencyClosure(root, baseCliDll)
    assert refusal == "", refusal
    assert File.ReadAllText(Path.ChangeExtension(baseCliDll, ".deps.json")) == "head dependency manifest"
    assert File.ReadAllText(Path.Combine(baseCliDirectory, "Microsoft.Build.Framework.dll")) == "head package"
    assert File.ReadAllText(Path.Combine(baseCliDirectory, "NSharpLang.Compiler.Emit.dll")) == "base compiler"
    assert File.ReadAllText(baseCliDll) == "base cli"
    BenchDeleteDirectory(root)
}

test "compile-time bench: a tree with no git metadata says WHY the CLI commit is unavailable instead of the bare word `unknown`" {
    isolated := BenchCliCommitUnavailableReason(false, true)
    noMetadata := BenchCliCommitUnavailableReason(false, false)
    failed := BenchCliCommitUnavailableReason(true, false)
    assert isolated.IndexOf("isolated gate copy", StringComparison.Ordinal) >= 0
    assert isolated.IndexOf("without .git", StringComparison.Ordinal) > 0
    assert noMetadata.IndexOf("no .git metadata", StringComparison.Ordinal) > 0
    assert failed.IndexOf("git rev-parse HEAD failed", StringComparison.Ordinal) > 0
    assert isolated != "unknown"
    assert noMetadata != "unknown"
    assert failed != "unknown"
}

test "compile-time bench: the CLI commit is the real 40-character sha wherever git metadata exists, and a reason where it does not" {
    root := BenchRepositoryRoot()
    commit := BenchReadCliCommit(root)
    if BenchHasGitMetadata(root) {
        assert commit.Length == 40, "expected a 40-character sha, got '" + commit + "'"
    } else {
        assert commit.StartsWith("unavailable"), "expected a reason, got '" + commit + "'"
    }
}

// ─── THE GATE ─────────────────────────────────────────────────────────────────────────────────

test "compile-time gate: exact Core counters and phase contract accompany change-aware Core-scale emit timing" {
    // Step 3a parses the whole test output as one JSON envelope. Keep the gate silent and preserve
    // the complete relative table and machine trend record under artifacts/compile-time.
    repositoryRoot := BenchRepositoryRoot()
    baseline := BenchParseBaseline(File.ReadAllText(BenchTestBaselinePath()))
    refusal := BenchBaselineRefusal(baseline)
    assert refusal == "", "compile-time gate: " + refusal

    headCli := BenchDefaultCliDll(repositoryRoot)
    assert File.Exists(headCli), "compile-time gate: head CLI was not found at " + headCli + ". Build it with: dotnet build src/NSharpLang.Cli/Cli.csproj -c Debug"
    loadAtStart := BenchReadMachineLoad()
    gateStarted := DateTime.UtcNow.Ticks
    gitRoot := BenchCompilerPerfGitRoot(repositoryRoot)
    baseCommit := BenchSelectBaseCommit(gitRoot)
    headCommit := BenchGitText(gitRoot, "rev-parse HEAD")
    productChanges := BenchFindCompilerProductChanges(gitRoot, baseCommit, headCommit)
    assert productChanges.Error == "", "compile-time gate: " + productChanges.Error
    comparesTiming := productChanges.HasCompilerChanges()
    baseCompiler := new BenchBaseCompiler(baseCommit, "", 0, false, "")
    timingStatus := "not compared (no compiler change)"
    if comparesTiming {
        baseCompiler = BenchPrepareBaseCompiler(repositoryRoot)
        assert baseCompiler.Error == "", "compile-time gate: " + baseCompiler.Error
    }

    headCanary := BenchObserveBuildPhase(headCli)
    headPhaseRefusal := BenchPhaseContractRefusal(baseline.PhaseContract, baseline.PhaseDiagnosticMultiset, headCanary.DiagnosticMultiset, headCanary.ExitCode, headCanary.SawBuildFailedBanner)
    assert headPhaseRefusal == "", "compile-time gate: head phase contract changed: " + headPhaseRefusal
    if comparesTiming {
        baseCanary := BenchObserveBuildPhase(baseCompiler.CliDll)
        basePhaseRefusal := BenchPhaseContractRefusal(baseline.PhaseContract, baseline.PhaseDiagnosticMultiset, baseCanary.DiagnosticMultiset, baseCanary.ExitCode, baseCanary.SawBuildFailedBanner)
        assert basePhaseRefusal == "", "compile-time gate: base phase contract changed: " + basePhaseRefusal
        timingStatus = "compared by exact sign-test 95% lower bound plus 30 ms slowdown floor"
    }

    facts := BenchReadEnvironmentFacts(gitRoot)
    // A clean source copy fixes CompilerWorkCounters at the first-build values. Reusing the checkout
    // makes this failed Core build incremental: the first run parses 468 files, the second 452 and
    // the third 0, even though the inputs are unchanged. Copying source (including uncommitted edits)
    // but excluding bin/obj/.nlc makes the structural phase contract deterministic on every gate run.
    coreCopyRoot := Path.Combine(Path.GetTempPath(), "nsharp-compile-perf-core-" + BenchLongText(DateTime.UtcNow.Ticks))
    coreSource := Path.Combine(repositoryRoot, "src")
    copiedSource := Path.Combine(coreCopyRoot, "src")
    Directory.CreateDirectory(coreCopyRoot)
    try {
        AgentLoopCopyDirectory(coreSource, copiedSource)
        coreProject := Path.Combine(copiedSource, "NSharpLang.Compiler.Core")
        coreStatsPath := Path.Combine(Path.GetTempPath(), "nsharp-compile-perf-core-stats-" + BenchLongText(DateTime.UtcNow.Ticks) + ".json")
        coreBuild := BenchMeasureOnce(headCli, coreProject, "build", 1, coreStatsPath)
        coreCounterFailure := BenchCoreCounterFailure("src/NSharpLang.Compiler.Core", baseline.CoreCounters, coreBuild.Counters)
        assert coreBuild.ExitCode == baseline.ExpectedExitCode, "compile-time gate: Core phase exit changed from " + BenchIntText(baseline.ExpectedExitCode) + " to " + BenchIntText(coreBuild.ExitCode)
        assert coreBuild.SawBuildFailedBanner, "compile-time gate: Core's expected analysis failure did not carry the CLI's Build failed in banner"
        assert coreCounterFailure == "", "compile-time gate: " + coreCounterFailure
    } finally {
        BenchDeleteDirectory(coreCopyRoot)
    }

    scaleDirectory := Path.Combine(Path.GetTempPath(), "nsharp-compile-perf-core-scale-" + BenchLongText(DateTime.UtcNow.Ticks))
    Directory.CreateDirectory(scaleDirectory)
    try {
        large := AgentLoopFindSize("large") ?? new AgentLoopSize("large", "", 160, 32)
        AgentLoopWriteSynthetic(large, scaleDirectory)
        minimumPairs := 9
        maximumPairs := 17
        baseMs := new long[](maximumPairs)
        headMs := new long[](maximumPairs)
        headCountersFailure := ""
        if comparesTiming {
            warmupHead := BenchMeasureOnce(headCli, scaleDirectory, "build", 0)
            warmupBase := BenchMeasureOnce(baseCompiler.CliDll, scaleDirectory, "build", 0)
            if warmupHead.ExitCode != 0 || warmupBase.ExitCode != 0 {
                headCountersFailure = "Core-scale discarded warm-up pair failed: head exit=" + BenchIntText(warmupHead.ExitCode) + ", base exit=" + BenchIntText(warmupBase.ExitCode)
            }
        }
        comparisonWorkMs := 0L
        i := 0
        counterOnlySamples := 3
        while headCountersFailure == "" && ((comparesTiming && (i < minimumPairs || (i < maximumPairs && (comparisonWorkMs < 350 || i % 2 == 0)))) || (!comparesTiming && i < counterOnlySamples)) {
            headRun := new BenchCommandRun("build", -1, -1, -1)
            baseRun := new BenchCommandRun("build", -1, -1, -1)
            headStats := ""
            if comparesTiming && i % 2 == 0 {
                headStats = Path.Combine(Path.GetTempPath(), "nsharp-compile-perf-emit-" + BenchLongText(DateTime.UtcNow.Ticks) + ".json")
                headRun = BenchMeasureOnce(headCli, scaleDirectory, "build", i + 1, headStats, "head")
                baseRun = BenchMeasureOnce(baseCompiler.CliDll, scaleDirectory, "build", i + 1)
            } else if comparesTiming {
                baseRun = BenchMeasureOnce(baseCompiler.CliDll, scaleDirectory, "build", i + 1)
                headStats = Path.Combine(Path.GetTempPath(), "nsharp-compile-perf-emit-" + BenchLongText(DateTime.UtcNow.Ticks) + ".json")
                headRun = BenchMeasureOnce(headCli, scaleDirectory, "build", i + 1, headStats, "head")
            } else {
                headStats = Path.Combine(Path.GetTempPath(), "nsharp-compile-perf-emit-" + BenchLongText(DateTime.UtcNow.Ticks) + ".json")
                headRun = BenchMeasureOnce(headCli, scaleDirectory, "build", i + 1, headStats, "head")
            }

            headMs[i] = headRun.WallMs
            if comparesTiming {
                baseMs[i] = baseRun.WallMs
                comparisonWorkMs = comparisonWorkMs + headRun.WallMs + baseRun.WallMs
            }

            failedRun := headRun.ExitCode != 0
            if comparesTiming && baseRun.ExitCode != 0 {
                failedRun = true
            }
            if failedRun {
                if comparesTiming {
                    headCountersFailure = "Core-scale build did not reach emission: base exit=" + BenchIntText(baseRun.ExitCode) + ", head exit=" + BenchIntText(headRun.ExitCode) + ", base output=" + BenchTruncate(baseRun.Stdout + baseRun.CliStderr, 600) + ", head output=" + BenchTruncate(headRun.Stdout + headRun.CliStderr, 600)
                } else {
                    headCountersFailure = "Core-scale build did not reach emission: head exit=" + BenchIntText(headRun.ExitCode) + ", head output=" + BenchTruncate(headRun.Stdout + headRun.CliStderr, 600)
                }
                break
            }

            rowFailure := BenchCoreCounterFailure("Core-scale emit", baseline.EmitCounters, headRun.Counters)
            if rowFailure != "" {
                headCountersFailure = rowFailure
                break
            }

            i = i + 1
        }

        pairCount := i
        gateFailure := ""
        medianRatio := -1L
        table := "timing: " + timingStatus + "; Core-scale CompilerWorkCounters were checked against the committed baseline."
        if comparesTiming {
            gateFailure = BenchCompileTimeRatioFailure(headMs, baseMs, pairCount)
            medianRatio = BenchMedianPairRatioThousandths(headMs, baseMs, pairCount)
            table = BenchPairedBuildTable(headMs, baseMs, pairCount)
        }
        if headCountersFailure != "" {
            gateFailure = headCountersFailure
        }

        machine := facts.Architecture + ", " + facts.OsDescription + ", " + BenchCountText(facts.ProcessorCount) + " cores, .NET " + facts.DotnetVersion
        endLoad := BenchReadMachineLoad()
        gateElapsedMs := (DateTime.UtcNow.Ticks - gateStarted) / 10000
        coreSourceStats := BenchMeasureProjectSources(Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Compiler.Core"))
        gateLine := BenchRelativeGateRecordLine(gateFailure, timingStatus, baseCompiler.Commit, headCommit, baseCompiler.BuildMs, baseCompiler.CacheHit, loadAtStart, machine, medianRatio)
        gateLine = gateLine + "; loadAtEnd=" + BenchLoadText(endLoad.LoadThousandths) + "; gateElapsedMs=" + BenchLongText(gateElapsedMs) + "; coreFiles=" + BenchIntText(coreSourceStats.Files) + "; coreLines=" + BenchLongText(coreSourceStats.Lines) + "; phase=" + baseline.Stage
        _ = BenchWriteRelativeGateRecord(repositoryRoot, gateLine, table)
        assert gateFailure == "", gateLine + "\n" + table
    } finally {
        BenchDeleteDirectory(scaleDirectory)
    }
}

test "compile-time bench: an unknown diagnostic identity cannot hide beside the expected phase pair" {
    observed := BenchRenderedBuildDiagnosticMultiset("error NL011: empty catch\nRead more: https://schneidenbach.github.io/nsharplang/docs/errors/NL202\nerror XYZ123: unknown diagnostic identity\n")
    assert observed.IndexOf("(unrecognized diagnostic rendering)", StringComparison.Ordinal) >= 0
    refusal := BenchPhaseContractRefusal(BenchCurrentPhaseContract(), BenchCurrentPhaseDiagnosticMultiset(), observed, 1, true)
    assert refusal != ""
}

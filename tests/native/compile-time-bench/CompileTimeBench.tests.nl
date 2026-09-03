namespace NSharpLang.CompileTimeBench

import System
import System.Collections.Generic
import System.IO


// WHAT THIS FILE STATES.
//
// Every kernel the compile-time report is assembled from, proven on literal inputs — no process,
// no clock, no repository — plus the one gate that spends real time: a live `nlc build` of
// `src/NSharpLang.Compiler.BootstrapServices`, compared against the checked-in baseline.
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
    return "front-end (parse + strict lint)"
}

func BenchTestPlaceholderBaselineJson(): string {
    return "{\"schemaVersion\":1,\"project\":\"src/NSharpLang.Compiler.BootstrapServices\"," + "\"command\":\"build\",\"stage\":\"" + BenchTestStageText() + "\",\"expectedExitCode\":1," + "\"measuredAt\":\"2026-09-01\"," + "\"cliCommit\":\"0000000000000000000000000000000000000000\"," + "\"machine\":\"Apple M4, 10 cores, macOS 15.6, .NET 10.0.105\",\"runs\":5," + "\"files\":0,\"lines\":0,\"medianWallMs\":0,\"medianPeakRssBytes\":0,\"toleranceFactor\":1.5}"
}

func BenchTestMeasuredBaselineJson(): string {
    return "{\"schemaVersion\":1,\"project\":\"src/NSharpLang.Compiler.BootstrapServices\"," + "\"command\":\"build\",\"stage\":\"" + BenchTestStageText() + "\",\"expectedExitCode\":1," + "\"measuredAt\":\"2026-09-01\"," + "\"cliCommit\":\"abcdef0123456789abcdef0123456789abcdef01\"," + "\"machine\":\"Apple M4, 10 cores, macOS 15.6, .NET 10.0.105\",\"runs\":5," + "\"files\":403,\"lines\":250000,\"medianWallMs\":120000," + "\"medianPeakRssBytes\":1073741824,\"toleranceFactor\":1.5}"
}

// The same baseline with `expectedExitCode` 0, for the arm where a run is supposed to SUCCEED.
func BenchTestSuccessBaselineJson(): string {
    return "{\"schemaVersion\":1,\"project\":\"src/NSharpLang.Compiler.BootstrapServices\"," + "\"command\":\"build\",\"stage\":\"parse, analysis and emit\",\"expectedExitCode\":0," + "\"measuredAt\":\"2026-09-01\"," + "\"cliCommit\":\"abcdef0123456789abcdef0123456789abcdef01\"," + "\"machine\":\"Apple M4, 10 cores, macOS 15.6, .NET 10.0.105\",\"runs\":5," + "\"files\":403,\"lines\":250000,\"medianWallMs\":120000," + "\"medianPeakRssBytes\":1073741824,\"toleranceFactor\":1.5}"
}

// Three runs' worth of "the CLI printed its own failure banner".
func BenchTestBanners(a: bool, b: bool, c: bool): bool[] {
    values := new bool[](3)
    values[0] = a
    values[1] = b
    values[2] = c
    return values
}

func BenchTestExitCodes(a: int, b: int, c: int): int[] {
    values := new int[](3)
    values[0] = a
    values[1] = b
    values[2] = c
    return values
}

// An `nlc check --json` envelope carrying three codes in mixed order, with a tie on count so the
// code-ascending tiebreak is exercised.
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

// ─── THE BASELINE ─────────────────────────────────────────────────────────────────────────────

test "compile-time bench: the checked-in baseline file parses into every field the gate compares" {
    baseline := BenchParseBaseline(File.ReadAllText(BenchTestBaselinePath()))
    assert baseline.SchemaVersion == 1
    assert baseline.Project == "src/NSharpLang.Compiler.BootstrapServices"
    assert baseline.Command == "build"
    assert baseline.ExpectedExitCode == 1
    assert baseline.Stage.IndexOf("strict lint", StringComparison.Ordinal) > 0
    assert baseline.Stage.IndexOf("analysis and emit are NOT covered", StringComparison.Ordinal) > 0
    assert baseline.ToleranceThousandths == 1500
}

test "compile-time bench: a baseline whose medianWallMs is still the placeholder ZERO is REFUSED, so a placeholder can never pass the gate it guards" {
    baseline := BenchParseBaseline(BenchTestPlaceholderBaselineJson())
    refusal := BenchBaselineRefusal(baseline)
    assert refusal.IndexOf("baseline not measured: medianWallMs is 0", StringComparison.Ordinal) == 0
    assert refusal.IndexOf("tests/fixtures/compile-time/bootstrap-build-baseline.golden.json", StringComparison.Ordinal) > 0
}

test "compile-time bench: a measured baseline is accepted, and its tolerance is applied as an integer limit in milliseconds" {
    baseline := BenchParseBaseline(BenchTestMeasuredBaselineJson())
    assert BenchBaselineRefusal(baseline) == ""
    assert baseline.MedianWallMs == 120000
    assert baseline.MedianPeakRssBytes == 1073741824
    assert BenchGateLimitMs(baseline) == 180000
}

test "compile-time bench: a baseline for another schema version, project or command is REFUSED by name" {
    wrongSchema := new BenchBaseline(2, "src/NSharpLang.Compiler.BootstrapServices", "build", "s", 1, "", "", "", 5, 0, 0, 1, 0, 1500)
    assert BenchBaselineRefusal(wrongSchema) == "baseline schemaVersion 2 is not the supported version 1"

    wrongProject := new BenchBaseline(1, "examples/01-hello-world", "build", "s", 1, "", "", "", 5, 0, 0, 1, 0, 1500)
    assert BenchBaselineRefusal(wrongProject) == "baseline project 'examples/01-hello-world' is not 'src/NSharpLang.Compiler.BootstrapServices'"

    wrongCommand := new BenchBaseline(1, "src/NSharpLang.Compiler.BootstrapServices", "check", "s", 1, "", "", "", 5, 0, 0, 1, 0, 1500)
    assert BenchBaselineRefusal(wrongCommand) == "baseline command 'check' is not 'build'"
}

test "compile-time bench: a baseline with NO stage is REFUSED, because milliseconds that do not say which stage they cover cannot be compared" {
    noStage := new BenchBaseline(1, "src/NSharpLang.Compiler.BootstrapServices", "build", "", 1, "", "", "", 5, 0, 0, 1, 0, 1500)
    refusal := BenchBaselineRefusal(noStage)
    assert refusal.IndexOf("baseline stage is missing", StringComparison.Ordinal) == 0
    assert refusal.IndexOf("does not reach analysis or emit", StringComparison.Ordinal) > 0
}

test "compile-time bench: a baseline with a MISSING or negative expectedExitCode is REFUSED, and a JSON without the key parses to the missing marker rather than throwing" {
    noExit := new BenchBaseline(1, "src/NSharpLang.Compiler.BootstrapServices", "build", "s", -1, "", "", "", 5, 0, 0, 1, 0, 1500)
    refusal := BenchBaselineRefusal(noExit)
    assert refusal.IndexOf("baseline expectedExitCode is missing or negative", StringComparison.Ordinal) == 0

    legacy := BenchParseBaseline(
        "{\"schemaVersion\":1,\"project\":\"src/NSharpLang.Compiler.BootstrapServices\"," + "\"command\":\"build\",\"measuredAt\":\"\",\"cliCommit\":\"\",\"machine\":\"\",\"runs\":5," + "\"files\":0,\"lines\":0,\"medianWallMs\":1,\"medianPeakRssBytes\":0,\"toleranceFactor\":1.5}"
    )
    assert legacy.Stage == ""
    assert legacy.ExpectedExitCode == -1
    assert BenchBaselineRefusal(legacy).IndexOf("baseline stage is missing", StringComparison.Ordinal) == 0
}

test "compile-time bench: a tolerance factor is read as thousandths and rendered back without trailing zeros" {
    assert BenchParseFixed3("1.5") == 1500
    assert BenchParseFixed3("2") == 2000
    assert BenchParseFixed3("1.25") == 1250
    assert BenchParseFixed3("x") == -1
    assert BenchFormatFixed3(1500) == "1.5"
    assert BenchFormatFixed3(2000) == "2"
    assert BenchFormatFixed3(1250) == "1.25"
}

// ─── THE GATE VERDICT ─────────────────────────────────────────────────────────────────────────

test "compile-time bench: runs that MATCH the baselined exit code and carry the CLI's failure banner are `ok`, which is the gate's ONLY silent outcome" {
    baseline := BenchParseBaseline(BenchTestMeasuredBaselineJson())
    wallMs := BenchTestLongs(118000, 130000, 121000)
    exitCodes := BenchTestExitCodes(1, 1, 1)
    banners := BenchTestBanners(true, true, true)
    assert BenchGateVerdict(wallMs, exitCodes, banners, 3, 121000, baseline, "deadbeef") == "ok"
}

test "compile-time bench: a median past the tolerance is a REGRESSION whose message carries all three wall times, the median, the baseline, the tolerance, the limit, the expected exit code, the stage and the CLI commit" {
    baseline := BenchParseBaseline(BenchTestMeasuredBaselineJson())
    wallMs := BenchTestLongs(200000, 190000, 210000)
    exitCodes := BenchTestExitCodes(1, 1, 1)
    banners := BenchTestBanners(true, true, true)
    verdict := BenchGateVerdict(wallMs, exitCodes, banners, 3, 200000, baseline, "deadbeef")
    assert verdict.IndexOf("regressed", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("runs=[200000, 190000, 210000] ms", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("median=200000ms", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("baseline=120000ms", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("tolerance=x1.5", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("limit=180000ms", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("expectedExitCode=1", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("stage=front-end (parse + strict lint)", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("cliCommit=deadbeef", StringComparison.Ordinal) > 0
}

test "compile-time bench: a run that exits 0 where the baseline pins 1 FAILS the gate and says the baseline must be RE-MEASURED, because the command now reaches stages the baseline never covered" {
    baseline := BenchParseBaseline(BenchTestMeasuredBaselineJson())
    wallMs := BenchTestLongs(1000, 1100, 1050)
    exitCodes := BenchTestExitCodes(1, 0, 1)
    banners := BenchTestBanners(true, false, true)
    verdict := BenchGateVerdict(wallMs, exitCodes, banners, 3, 1050, baseline, "deadbeef")
    assert verdict.IndexOf("exited 0 on run 2 but the baseline pins 1", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("now SUCCEEDS where the baseline recorded a failure", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("re-measure the baseline and rewrite its stage", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("exitCodes=[1, 0, 1]", StringComparison.Ordinal) > 0
}

test "compile-time bench: a run that exits non-zero where the baseline pins 0 FAILS the gate and says to fix the failure, not the baseline" {
    baseline := BenchParseBaseline(BenchTestSuccessBaselineJson())
    wallMs := BenchTestLongs(1000, 1100, 1050)
    exitCodes := BenchTestExitCodes(0, 0, 1)
    banners := BenchTestBanners(false, false, true)
    verdict := BenchGateVerdict(wallMs, exitCodes, banners, 3, 1050, baseline, "deadbeef")
    assert verdict.IndexOf("exited 1 on run 3 but the baseline pins 0", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("fix the failure rather than", StringComparison.Ordinal) > 0
}

test "compile-time bench: a run that exits as baselined WITHOUT the CLI's own failure banner FAILS the gate, so a crash or a kill can never pass as the expected failure" {
    baseline := BenchParseBaseline(BenchTestMeasuredBaselineJson())
    wallMs := BenchTestLongs(118000, 130000, 121000)
    exitCodes := BenchTestExitCodes(1, 1, 1)
    banners := BenchTestBanners(true, false, true)
    verdict := BenchGateVerdict(wallMs, exitCodes, banners, 3, 121000, baseline, "deadbeef")
    assert verdict.IndexOf("run 2 of nlc build", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("did NOT carry the CLI's own 'Build failed in ' banner", StringComparison.Ordinal) > 0
    assert verdict.IndexOf("a crash, a kill or a missing CLI cannot pass", StringComparison.Ordinal) > 0
}

test "compile-time bench: the banner check is skipped when the baseline pins exit 0, because a successful build writes no failure banner" {
    baseline := BenchParseBaseline(BenchTestSuccessBaselineJson())
    wallMs := BenchTestLongs(118000, 130000, 121000)
    exitCodes := BenchTestExitCodes(0, 0, 0)
    banners := BenchTestBanners(false, false, false)
    assert BenchGateVerdict(wallMs, exitCodes, banners, 3, 121000, baseline, "deadbeef") == "ok"
}

test "compile-time bench: the failure banner is recognised in the CLI's own stdout wording and nowhere else" {
    assert BenchBuildFailedBanner() == "Build failed in "
    assert BenchSawBuildFailedBanner("Building project in /x with the IL backend...\n  Build failed in 17.5s\n")
    assert !BenchSawBuildFailedBanner("Build successful! (il, debug) [3.1s]\n")
    assert !BenchSawBuildFailedBanner("")
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
// lifetime contract added tests/native/lsp-lifetime.
test "compile-time bench: the corpus is the 72 project.yml projects under examples, tests and templates" {
    projects := BenchCollectCorpusProjects(BenchRepositoryRoot())
    assert projects.Count == 72
    assert BenchListContains(projects, "examples/01-hello-world")
    assert BenchListContains(projects, "templates/nsharp-console")
    assert BenchListContains(projects, "tests/native/ownership-audit")
}

test "compile-time bench: the large-project case is NOT in the corpus, and neither is this harness's own project" {
    projects := BenchCollectCorpusProjects(BenchRepositoryRoot())
    assert !BenchListContains(projects, BenchBootstrapProjectPath())
    assert !BenchListContains(projects, BenchSelfProjectPath())
    assert BenchBootstrapProjectPath() == "src/NSharpLang.Compiler.BootstrapServices"
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

// ─── THE GATE ─────────────────────────────────────────────────────────────────────────────────

func BenchGateSkipRequested(): bool {
    requested := Environment.GetEnvironmentVariable("SYSTEMS_BENCH") ?? ""
    return String.Compare(requested.Trim(), "skip", StringComparison.OrdinalIgnoreCase) == 0
}

test "compile-time gate: nlc build on src/NSharpLang.Compiler.BootstrapServices stays inside the checked-in baseline's tolerance" {
    // SILENT ON EVERY PATH — skip, pass and fail alike. The product gate's Step 3a runs
    // `nlc test --project <dir> --no-cache --json > out 2>&1` and then parses the WHOLE file as one
    // JSON document, so ANY line this block writes to stdout or stderr lands ahead of the envelope
    // and makes it unparseable. A fully green run then reads as "native N# test JSON did not prove a
    // nonempty successful run" and the gate goes red on 51 passing tests. Nothing is lost by the
    // silence: every number a red gate needs is already inside `BenchGateVerdict`'s string, which
    // the runner reports as the assertion's `errorMessage`, and a green run needs no line at all.
    if !BenchGateSkipRequested() {
        repositoryRoot := BenchRepositoryRoot()
        baseline := BenchParseBaseline(File.ReadAllText(BenchTestBaselinePath()))
        refusal := BenchBaselineRefusal(baseline)
        assert refusal == "", "compile-time gate: " + refusal

        cliDll := BenchDefaultCliDll(repositoryRoot)
        assert File.Exists(cliDll), "compile-time gate: the CLI under test was not found at " + cliDll + ". Build it with: dotnet build src/NSharpLang.Cli/Cli.csproj -c Debug"

        projectDirectory := BenchAbsoluteProjectPath(repositoryRoot, baseline.Project)
        wallMs := new long[](3)
        exitCodes := new int[](3)
        banners := new bool[](3)
        i := 0
        while i < 3 {
            measured := BenchMeasureOnce(cliDll, projectDirectory, "build", i + 1)
            wallMs[i] = measured.WallMs
            exitCodes[i] = measured.ExitCode
            banners[i] = measured.SawBuildFailedBanner
            i = i + 1
        }

        median := BenchMedian(wallMs, 3)
        verdict := BenchGateVerdict(wallMs, exitCodes, banners, 3, median, baseline, BenchReadCliCommit(repositoryRoot))
        assert verdict == "ok", verdict
    }
}

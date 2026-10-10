namespace NSharpLang.GateScriptContracts.Tests

import System.Collections.Generic
import System.IO
import System.Text.RegularExpressions


// ─── WHAT STEP 2c PRINTS, AND WHAT IT DECIDES ON ──────────────────────────────────────────────
//
// `GateStepInputSets.tests.nl` pins WHERE the Systems Throughput Gate runs in the product gate and
// that it runs exactly once. These rows pin WHAT IT IS — the shape of the verdict a reader (or a
// failure triage) depends on, and the property that shape rests on.
//
// The property is the one that changed on 2026-09-23. The gate used to divide each measured median
// by a number stored from one session on one idle Apple M4, so its verdict was a statement about
// how busy THIS machine happened to be: `count-transitions` failed at 1.20x-1.75x under a
// concurrent build and passed at 0.95x-1.06x on a quiet box, and one run under load average 25
// failed all twelve cells with nothing regressed. It now measures a frozen control in the SAME
// process, interleaved with the live kernels, and gates on `live / control` — a ratio whose two
// halves share a machine, so load multiplies both and divides out.
//
// These rows read the runner as TEXT. They never run the gate: a measurement lane cannot be a unit
// test, which is exactly why the shape of what it prints is worth pinning where a unit test can
// reach it. A gate whose table silently loses its ratio column, or whose verdict silently goes back
// to comparing stored nanoseconds, would otherwise be found only by someone reading a log.
func ReadRunnerSource(name: string): string {
    root := RepositoryRoot()
    benchmarks := Path.Combine(Path.Combine(root, "benchmarks"), "native-comparison")
    return File.ReadAllText(Path.Combine(Path.Combine(benchmarks, "runner"), name))
}

func ReadKernelSource(name: string): string {
    root := RepositoryRoot()
    benchmarks := Path.Combine(Path.Combine(root, "benchmarks"), "native-comparison")
    return File.ReadAllText(Path.Combine(Path.Combine(benchmarks, "nsharp-kernels"), name))
}

func ThroughputKernelNames(): List<string> {
    names := new List<string>()
    names.Add("Checksum")
    names.Add("CountAscii")
    names.Add("MinMaxDelta")
    names.Add("RollingHash")
    names.Add("ParseEightDigits")
    names.Add("CountTransitions")
    return names
}

test "the throughput gate measures a same-run control and gates on the live/control ratio" {
    runner := ReadRunnerSource("Program.nl")

    // The measurement run asks the kernel program for its PAIRED mode. Without this the control side
    // is never measured and there is nothing to divide by.
    assert runner.Contains("func PairedFlag(): string"), "The gate must name the kernel program's paired-measurement flag in one place."
    assert Regex.IsMatch(runner, "return \"--paired\""), "The gate's paired flag must be `--paired`, the flag the kernel program implements."
    assert Regex.IsMatch(runner, "run := RunKernelProgram\\(options, PairedFlag\\(\\), true\\)"), "The gate's measurement run must pass the paired flag, or only the live kernels are measured."

    // The verdict divides the live median by THIS RUN'S control median. A ratio taken against
    // `row.MedianNs` — the stored 2026-09-01 number — is the load-sensitive comparison this lane
    // moved away from, and it must not come back.
    assert runner.Contains("ratio := liveMeasurements[liveIndex].PairedRatio"), "Each cell's verdict must be the median of its PER-REPETITION live-over-control ratios; the quotient of two independently-taken medians reaches 1.24x under load with nothing regressed."
    assert runner.Contains("ratio = SafeRatio(measured, controlNs)"), "The fallback for a kernel program that does not print `ratio=` must still be this run's control, never a stored number."
    assert !Regex.IsMatch(runner, "ratio := SafeRatio\\(measured, row\\.MedianNs\\)"), "The gate must not compare a measured median against the stored 2026-09-01 baseline; that comparison fails under load with nothing regressed."

    // Both halves of every ratio are read under their own language key, so a missing control is a
    // failure rather than a silently-skipped cell.
    assert runner.Contains("MISSING CONTROL"), "A cell whose control did not report must fail; a cell with no control has been held to nothing."
}

test "the throughput gate keeps its six-column table and its cell-count verdict" {
    runner := ReadRunnerSource("Program.nl")

    header := RequireMatch(runner, "func GateTableHeader\\(\\): string \\{(?<body>.*?)\\n\\}", "Could not find GateTableHeader in the throughput runner.")
    body := header.Groups["body"].Value
    columns := new List<string>()
    columns.Add("workload")
    columns.Add("size")
    columns.Add("baseline ns")
    columns.Add("measured ns")
    columns.Add("ratio")
    columns.Add("status")
    for i := 0; i < columns.Count; i++ {
        assert body.Contains("names.Add(\"" + columns[i] + "\")"), "The gate table must keep its `" + columns[i] + "` column: the pinned contracts and every triage log read this table positionally."
    }

    summary := RequireMatch(runner, "func PrintGateSummary\\(.*?\\n\\}", "Could not find PrintGateSummary in the throughput runner.").Value
    assert summary.Contains("verdict := \"PASS\""), "The gate's passing verdict must still be spelled PASS."
    assert summary.Contains("cells.ToString() + \" cells, \""), "The verdict must still report the cell count."
    assert summary.Contains("failures.ToString() + \" failed\""), "The verdict must still report the failed-cell count."
    assert summary.Contains("\", tolerance \""), "The verdict must still report the tolerance it applied."
    assert summary.Contains("ThroughputControlOrigin()"), "The verdict must name the same-run control it held the kernels to, not a stored baseline."
}

test "the stored idle-M4 numbers survive as an informational drift row that never gates" {
    runner := ReadRunnerSource("Program.nl")

    assert runner.Contains("func PrintDriftTable("), "The gate must still report drift against the stored 2026-09-01 reference; a same-run ratio cannot see the machine moving under both sides."
    assert runner.Contains("ratio := SafeRatio(controlNs, row.MedianNs)"), "Drift must be this run's control over the stored 2026-09-01 median."
    assert runner.Contains("DRIFT (informational, never gating)"), "The drift summary must say in its own words that it never gates."

    // The drift table's contribution to the exit status is nil, and that is checked by what the exit
    // status IS made of: the cell failures and the IL-shape failures, and nothing else.
    assert runner.Contains("if failures > 0 || shapeFailures > 0 {"), "The gate's exit status must come from the cell verdicts and the IL-shape check only — never from drift."
}

test "the throughput gate still checks the emitted IL shape, which the control cannot" {
    runner := ReadRunnerSource("Program.nl")
    baseline := ReadRunnerSource("SystemsThroughputBaseline.nl")

    // Control and live are compiled by the same nlc, so a compiler change that de-vectorizes their
    // shared shape moves both medians together and the ratio stays at 1.00x. That is the 2x-6x
    // regression this lane exists for, so the gate reads the fact out of the IL instead.
    assert Regex.IsMatch(runner, "shapeRun := RunKernelProgram\\(options, \"--il-shape\", false\\)"), "The gate must read the emitted IL shape back; the same-run control is blind to a compiler-wide de-vectorization."
    assert runner.Contains("func PrintIlShapeVerdict("), "The gate must report an IL-shape verdict."
    assert runner.Contains("IL SHAPE FAIL: "), "An unexpected IL shape must announce itself as a failure line."

    helpers := new List<string>()
    helpers.Add("SumInt32")
    helpers.Add("CountInRangeInt32")
    helpers.Add("CountTransitionsInt32")
    helpers.Add("MinMaxInt32")
    for i := 0; i < helpers.Count; i++ {
        assert baseline.Contains("return \"" + helpers[i] + "\""), "The gate must still expect `" + helpers[i] + "`; the four vectorizable kernels' helpers are what `website/docs/systems.md` records."
    }
}

test "the throughput gate keeps twelve cells, two sizes and a 20 percent tolerance" {
    baseline := ReadRunnerSource("SystemsThroughputBaseline.nl")
    measurements := ReadRunnerSource("Measurements.nl")

    rows := Regex.Matches(baseline, "rows\\.Add\\(new ThroughputBaselineRow\\(")
    assert rows.Count == 12, "The gate's row contract is twelve cells — six workloads at two sizes. Found " + rows.Count.ToString() + "."

    tolerance := RequireMatch(baseline, "func DefaultThroughputTolerance\\(\\): double \\{\\s*return (?<value>[0-9.]+)", "Could not find DefaultThroughputTolerance.")
    assert tolerance.Groups["value"].Value == "0.20", "The gate's tolerance must stay at 20 percent; a same-run control removed the reason to widen it, not the reason to have it."

    sizes := RequireMatch(measurements, "func BenchmarkSizes\\(\\): int\\[\\] \\{(?<body>.*?)\\n\\}", "Could not find BenchmarkSizes.").Groups["body"].Value
    assert sizes.Contains("sizes[0] = 64"), "The gate must still measure size 64."
    assert sizes.Contains("sizes[1] = 4096"), "The gate must still measure size 4096."
}

test "the control declares the same six kernels as the kernels it controls for" {
    kernels := ReadKernelSource("Kernels.nl")
    control := ReadKernelSource("ControlKernels.nl")

    assert control.Contains("class ControlKernels {"), "The control must be its own class; a control that shares an implementation with its subject measures nothing."

    names := ThroughputKernelNames()
    for i := 0; i < names.Count; i++ {
        signature := "\\[hot\\]\\s*\\n\\s*static func " + names[i] + "\\(values: int\\[\\]\\): int"
        assert Regex.IsMatch(kernels, signature), "Kernels must declare `[hot] static func " + names[i] + "(values: int[]): int`."
        assert Regex.IsMatch(control, signature), "ControlKernels must declare `[hot] static func " + names[i] + "(values: int[]): int`, or the paired measurement is not measuring the same six kernels."
    }

    liveKernels := Regex.Matches(kernels, "static func \\w+\\(values: int\\[\\]\\): int")
    controlKernels := Regex.Matches(control, "static func \\w+\\(values: int\\[\\]\\): int")
    assert liveKernels.Count == 6, "Kernels must declare exactly six kernels. Found " + liveKernels.Count.ToString() + "."
    assert controlKernels.Count == 6, "ControlKernels must declare exactly six kernels. Found " + controlKernels.Count.ToString() + "."
}

test "the kernel program answers the paired protocol on a stream every old reader already ignores" {
    program := ReadKernelSource("Program.nl")

    assert program.Contains("func ReportPairedTimings("), "The kernel program must implement the paired measurement the gate asks for."
    assert program.Contains("argument == \"--paired\""), "The kernel program must accept `--paired`."

    // The control's lines are the live protocol with a `control ` prefix, which makes them four
    // tokens. Every existing parser of this program's stdout requires exactly three (or exactly two
    // for `--il-shape`), so `compare` and the historical readers skip them without a flag.
    assert program.Contains("WritePairedCell(\"\", keys[workload]"), "The live side must keep the historical three-token stdout line."
    assert program.Contains("WritePairedCell(\"control \", keys[workload]"), "The control side must be prefixed, so three-token readers ignore it."

    // Two kernels that disagree on a result are not two timings of one computation.
    assert program.Contains("control mismatch: "), "The paired mode must refuse to report timings when the control and the live kernel compute different answers."

    // The pairing is the point, so the ratios must be taken before either sample array is sorted:
    // sorted arrays pair the fastest live trial with the fastest control trial, which are not the
    // same experiment and share none of the same contention.
    pairing := RequireMatch(program, "pairedRatios\\[t\\] = PairedRatio.*?Array\\.Sort\\(pairedRatios\\)", "Could not find the paired-ratio computation in the kernel program.").Value
    assert !pairing.Contains("Array.Sort(liveSamples)"), "The per-repetition ratios must be taken before the sample arrays are sorted."
    assert program.Contains("ratio=\" + Format(Percentile(pairedRatios, 0.5))"), "The live stderr line must carry the median of the per-repetition ratios; it is the statistic the gate judges."
}

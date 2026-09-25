namespace NSharpLang.NativeComparisonRunner

import System.Collections.Generic


// THE 2026-09-01 REFERENCE MEDIANS — INFORMATIONAL SINCE THE GATE TOOK A SAME-RUN CONTROL.
//
// WHAT THESE TWELVE NUMBERS USED TO BE. They were the gate's verdict: each measured median was
// divided by the stored one and a cell failed above 1.20x. That worked exactly as long as the
// machine under the gate resembled the machine under the baseline, and no longer. The recorded
// failures are unambiguous — `count-transitions` tripped at 1.20x-1.75x whenever another build was
// running and passed at 0.95x-1.06x on a quiet box; one run under load average 25 failed all twelve
// cells at 1.63x-4.04x while nothing whatsoever had regressed. A stored nanosecond is a measurement
// of one machine in one state. Asking it to judge a different machine in a different state is not a
// tolerance problem, and widening the tolerance would only have traded false alarms for blindness.
//
// WHAT THEY ARE NOW. The gate's reference moved from a number to a program: `ControlKernels` in
// `benchmarks/native-comparison/nsharp-kernels/`, the frozen transcription of the very kernels these
// medians were taken from, re-measured in the same process and interleaved with the live kernels on
// every run. The verdict is `live / control`, two medians taken seconds apart on one machine, and
// load cancels out of it. See `RunGate` in `Program.nl` for the protocol and `ControlKernels.nl` for
// what the control is and what it can and cannot see.
//
// So the rows below no longer decide anything. They are the DRIFT reference: the gate divides
// today's control median by the stored one and prints the result as a separate, clearly
// informational table. That number is the one thing the same-run ratio deliberately cannot see —
// the machine and the toolchain moving underneath both sides at once — and it is worth seeing. On a
// quiet box it sits near 1.0x and a sustained departure is real drift worth investigating; under a
// concurrent build it rises to 2x-4x, which is the load being reported rather than a regression.
//
// THE ROWS WERE MEASURED ON 2026-09-01 (commit 8cf40128a, Apple M4, .NET 10.0.105, load average 2.6
// on 10 cores, no other build or test process running) by `gate --print-baseline` and pasted whole.
// They sit 1.00x-1.36x above the June 2026-06-07 N# column that `JuneBaseline.nl` keeps; that gap is
// the measured finding recorded in `website/docs/systems.md`, not noise.
//
// HOW THEY ARE REFRESHED. Run `gate --print-baseline` on an IDLE machine and paste the block it
// prints over the twelve `rows.Add(...)` lines below. That block now carries the CONTROL's medians,
// which is what the drift table compares against. Do not hand-edit a single number: the printed
// block is formatted to be pasted whole, so a refreshed reference is always internally consistent
// with one measurement session. Refreshing is optional housekeeping — it resets the drift table's
// origin and changes no verdict.
//
// WHY MEDIANS AND NOT MEANS, still. The BenchmarkDotNet gate this lane replaced compared MEANS, and
// a handful of thermally-throttled iterations pull a mean far enough to fail a build that measured
// nothing wrong. The median of a cell's 15 (or 21) trials is unmoved by a few slow ones, on both
// sides of the ratio.
//
// WHY 20 PERCENT, still, and why it is now a different 20 percent. It is wide enough to absorb the
// run-to-run spread between two interleaved medians — a few percent on a quiet box and, because the
// two sides share the machine, still a few percent under load — and tight enough to catch what this
// gate exists to catch: a kernel that got materially slower than the reference it is supposed to
// match. It is NOT the guard against the vectorizer falling back to scalar; a fallback in the
// compiler moves control and live together. The gate's IL-shape check is that guard, and it is
// exact rather than statistical.
//
// The product gate skips this check entirely when `SYSTEMS_BENCH=skip` is set; that decision lives
// in `tests/scripts/test-all-core.sh`, not here, so a direct `gate` invocation always measures.
class ThroughputBaselineRow {
    Workload: string
    Size: int
    MedianNs: double

    constructor(workload: string, size: int, medianNs: double) {
        Workload = workload
        Size = size
        MedianNs = medianNs
    }
}

func ThroughputBaselineRows(): List<ThroughputBaselineRow> {
    rows := new List<ThroughputBaselineRow>()
    rows.Add(new ThroughputBaselineRow("checksum-sum", 64, 5.757))
    rows.Add(new ThroughputBaselineRow("checksum-sum", 4096, 301.044))
    rows.Add(new ThroughputBaselineRow("count-ascii", 64, 6.830))
    rows.Add(new ThroughputBaselineRow("count-ascii", 4096, 350.730))
    rows.Add(new ThroughputBaselineRow("count-transitions", 64, 13.243))
    rows.Add(new ThroughputBaselineRow("count-transitions", 4096, 583.086))
    rows.Add(new ThroughputBaselineRow("rolling-hash", 64, 42.249))
    rows.Add(new ThroughputBaselineRow("rolling-hash", 4096, 4765.592))
    rows.Add(new ThroughputBaselineRow("min-max-delta", 64, 12.555))
    rows.Add(new ThroughputBaselineRow("min-max-delta", 4096, 307.568))
    rows.Add(new ThroughputBaselineRow("parse-eight-digits", 64, 3.333))
    rows.Add(new ThroughputBaselineRow("parse-eight-digits", 4096, 3.352))
    return rows
}

// The date and provenance the rows above currently carry. Printed in the gate's DRIFT summary, so a
// drifting run says WHICH reference it drifted from without anyone opening this file.
func ThroughputBaselineOrigin(): string {
    return "measured 2026-09-01 on an idle Apple M4 (commit 8cf40128a)"
}

// What the gate holds the live kernels to: the frozen control, measured in the same run.
func ThroughputControlOrigin(): string {
    return "ControlKernels, measured in this run, interleaved with the live kernels"
}

func DefaultThroughputTolerance(): double {
    return 0.20
}

// THE IL SHAPE EVERY KERNEL MUST STILL LOWER TO, AND WHY THE GATE CHECKS IT.
//
// The same-run control is blind in exactly one direction: it is compiled by the same `nlc` as the
// kernels it controls for, so a compiler change that stops vectorizing THIS SHAPE slows both sides
// equally and the ratio stays at 1.00x. That is the 2x-6x regression this lane was created to catch,
// so it is caught directly instead — the gate asks the kernel program which `SimdReductions` helper
// each emitted kernel actually calls (`--il-shape`, read back out of the IL at run time) and fails
// when an answer is not the one below, on the live side or the control side.
//
// This is strictly stronger than the timing threshold it backs up: a fallback is a fact about the
// emitted IL, not a statistic, and reading the fact needs no quiet machine at all.
//
// The four vectorizable kernels and their helpers are the ones `website/docs/systems.md` records and
// `tests/native/systems-vectorization-facts` pins at the compiler layer; `rolling-hash` is
// latency-bound and `parse-eight-digits` touches eight elements, so both are `none` by design.
func ExpectedSimdHelper(workload: string): string {
    if workload == "checksum-sum" {
        return "SumInt32"
    }

    if workload == "count-ascii" {
        return "CountInRangeInt32"
    }

    if workload == "count-transitions" {
        return "CountTransitionsInt32"
    }

    if workload == "min-max-delta" {
        return "MinMaxInt32"
    }

    return "none"
}

func IndexOfThroughputBaselineRow(rows: List<ThroughputBaselineRow>, workload: string, size: int): int {
    for i := 0; i < rows.Count; i++ {
        row := rows[i]
        if row.Workload == workload && row.Size == size {
            return i
        }
    }
    return -1
}

namespace NSharpLang.NativeComparisonRunner

import System.Collections.Generic


// THE THROUGHPUT GATE'S BASELINE: TWELVE MEDIANS THE PRODUCT GATE HOLDS N# TO.
//
// WHY MEDIANS AND NOT MEANS. The BenchmarkDotNet gate this replaces compared MEANS, and it flaked
// under load: a handful of thermally-throttled iterations pull a mean far enough to fail a build
// that measured nothing wrong. The median of the kernel program's 15 trials is unmoved by a few
// slow ones, which is exactly the property a gate needs.
//
// WHY 20 PERCENT. Wide enough to absorb run-to-run noise on an idle Apple M4 — the June run's IQRs
// were a few percent of the median — and tight enough to catch the thing this gate exists to catch:
// the vectorizer silently falling back to scalar, which is a 2x to 6x regression, not a 20% one.
// A tolerance that only caught 2x would let a real but smaller codegen loss through; a tolerance of
// 5% would fail on a warm laptop. Nothing between those two failure modes needs finer resolution.
//
// HOW THESE NUMBERS ARE REFRESHED. Run `gate --print-baseline` on an IDLE machine and paste the
// block it prints over the twelve `rows.Add(...)` lines below. Do not hand-edit a single number:
// the printed block is formatted to be pasted whole, so a refreshed baseline is always internally
// consistent with one measurement session.
//
// THE ROWS BELOW WERE MEASURED ON 2026-09-01 (commit 8cf40128a, Apple M4, .NET 10.0.105, load average
// 2.6 on 10 cores, no other build or test process running) by `gate --print-baseline` and pasted whole.
// They sit 1.00x-1.36x above the June 2026-06-07 N# column that `JuneBaseline.nl` keeps; that gap is
// the measured finding recorded in `website/docs/systems.md`, not noise, and it is deliberately NOT
// folded into the tolerance: the gate holds N# to what it does today.
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

// The date and provenance the rows above currently carry. Printed in the gate's summary so a
// failing run says WHICH baseline it failed against without anyone opening this file.
func ThroughputBaselineOrigin(): string {
    return "measured 2026-09-01 on an idle Apple M4 (commit 8cf40128a)"
}

func DefaultThroughputTolerance(): double {
    return 0.20
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

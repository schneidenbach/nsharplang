namespace NSharpLang.NativeComparisonRunner

import System
import System.Collections.Generic


// THE 2026-06-07 CROSS-LANGUAGE TABLE, PINNED AS N# DATA.
//
// Twelve rows, median ns/op, measured at commit 9372d0c78 on the Apple M4 this comparison has
// always run on. It exists so that every refreshed run answers one more question than "how far is
// N# from C today": it also answers "did N# move, and did the GAP move".
//
// ALL FOUR COLUMNS ARE KEPT, INCLUDING C#. The C# column is history — the BenchmarkDotNet project
// that produced it is gone — so nothing computes against it; it is recorded because a four-column
// row deleted down to three cannot be restored, and the N#-vs-C# ratios are the only surviving
// record of what the systems profile was worth against the C# baseline on that date.
//
// The `Rust` and `C` columns are NOT decoration either: the report's `June N#/best-native` column
// divides June's N# by June's OWN best native, so that it can be read directly beside today's
// `N#/best-native`. Comparing a June N# against a native number measured today would confound a
// codegen change with a machine or toolchain change.
//
// These numbers are a fixed historical record. They are never rewritten by a run.
class JuneRow {
    Workload: string
    Size: int
    NsharpNs: double
    CsharpNs: double
    RustNs: double
    CNs: double

    constructor(workload: string, size: int, nsharpNs: double, csharpNs: double, rustNs: double, cNs: double) {
        Workload = workload
        Size = size
        NsharpNs = nsharpNs
        CsharpNs = csharpNs
        RustNs = rustNs
        CNs = cNs
    }

    func BestNativeNs(): double {
        return Math.Min(RustNs, CNs)
    }
}

func JuneBaselineCommit(): string {
    return "9372d0c78"
}

func JuneBaselineDate(): string {
    return "2026-06-07"
}

func JuneRows(): List<JuneRow> {
    rows := new List<JuneRow>()
    rows.Add(new JuneRow("checksum-sum", 64, 4.219, 16.524, 2.634, 2.256))
    rows.Add(new JuneRow("checksum-sum", 4096, 222.625, 982.916, 111.272, 110.180))
    rows.Add(new JuneRow("count-ascii", 64, 5.291, 18.934, 3.388, 3.369))
    rows.Add(new JuneRow("count-ascii", 4096, 298.051, 1174.088, 183.151, 183.020))
    rows.Add(new JuneRow("count-transitions", 64, 11.368, 17.027, 7.012, 6.702))
    rows.Add(new JuneRow("count-transitions", 4096, 477.331, 1069.094, 241.827, 245.100))
    rows.Add(new JuneRow("rolling-hash", 64, 42.251, 41.707, 29.655, 31.265))
    rows.Add(new JuneRow("rolling-hash", 4096, 4695.715, 4708.774, 2889.787, 3066.720))
    rows.Add(new JuneRow("min-max-delta", 64, 11.130, 23.699, 4.474, 8.602))
    rows.Add(new JuneRow("min-max-delta", 4096, 253.578, 1496.034, 155.317, 151.840))
    rows.Add(new JuneRow("parse-eight-digits", 64, 2.787, 4.159, 1.546, 1.554))
    rows.Add(new JuneRow("parse-eight-digits", 4096, 2.776, 4.145, 1.546, 1.552))
    return rows
}

func IndexOfJuneRow(rows: List<JuneRow>, workload: string, size: int): int {
    for i := 0; i < rows.Count; i++ {
        row := rows[i]
        if row.Workload == workload && row.Size == size {
            return i
        }
    }
    return -1
}

// A run whose N# median exceeds June's by this factor is flagged in the report. It is deliberately
// TIGHTER than the throughput gate's 1.20 tolerance, because it fails nothing: `compare` always
// exits 0, so this threshold only decides where a reader's eye is sent, and a false flag on a
// loaded machine costs a second look while a missed 18% drift costs a release.
func JuneRegressionFlagRatio(): double {
    return 1.15
}

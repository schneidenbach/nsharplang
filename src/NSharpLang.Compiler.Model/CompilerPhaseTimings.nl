namespace NSharpLang.Compiler

import System
import System.Collections.Concurrent
import System.Collections.Generic
import System.Diagnostics
import System.Text


// THE COMPILER'S PER-PHASE LEDGER: wall clock, process CPU and process allocation for every phase of
// every project one CLI invocation compiles.
//
// ONE OWNER FOR "WHERE DID THE BUILD GO". `nlc build --timings` prints the ledger after its
// three-line `Build timings:` block, and the throughput work reads the same rows, so a phase split can
// never be produced by a second, disagreeing stopwatch somewhere else.
//
// OFF UNLESS ASKED. `Begin` returns null while the ledger is disabled and `End(null)` is free, so the
// instrumented pipeline pays one static read per phase when nobody is measuring. A build enables it
// once, before its first phase, and never turns it off; the ledger is per process because a project
// build compiles its project references in the same process, and their phases belong in the same
// report.
//
// THE COUNTERS ARE PROCESS-WIDE ON PURPOSE. `Process.TotalProcessorTime` and
// `GC.GetTotalAllocatedBytes` count every thread, so a phase that fans out to workers reports the
// CPU and the allocation of all of them, and CPU above wall is the visible measure of that phase's
// parallelism. The price is that two phases running AT THE SAME TIME on different threads would
// each be charged the other's work; the pipeline runs its phases one after another, so they do not.
//
// THREADING: rows land in a `ConcurrentQueue`, so a phase may end on any thread; formatting reads a
// snapshot and folds repeated (project, phase) rows into one, in first-seen order.
class CompilerPhaseRecord {
    Project: string
    Phase: string
    WallTicks: long
    CpuTicks: long
    AllocatedBytes: long
    Count: int

    constructor(project: string, phase: string, wallTicks: long, cpuTicks: long, allocatedBytes: long, count: int) {
        Project = project
        Phase = phase
        WallTicks = wallTicks
        CpuTicks = cpuTicks
        AllocatedBytes = allocatedBytes
        Count = count
    }

    WallMilliseconds: long => WallTicks * 1000 / Stopwatch.Frequency
    CpuMilliseconds: long => CpuTicks / 10000
}

class CompilerPhaseMark {
    Project: string
    Phase: string
    StartTimestamp: long
    StartCpuTicks: long
    StartAllocatedBytes: long

    constructor(project: string, phase: string, startTimestamp: long, startCpuTicks: long, startAllocatedBytes: long) {
        Project = project
        Phase = phase
        StartTimestamp = startTimestamp
        StartCpuTicks = startCpuTicks
        StartAllocatedBytes = startAllocatedBytes
    }
}

class CompilerPhaseTimings {
    private static enabled: bool
    private static readonly records: ConcurrentQueue<CompilerPhaseRecord> = new ConcurrentQueue<CompilerPhaseRecord>()

    static func Enable() {
        CompilerPhaseTimings.enabled = true
    }

    static func IsEnabled(): bool {
        return CompilerPhaseTimings.enabled
    }

    static func Begin(project: string, phase: string): CompilerPhaseMark? {
        if !CompilerPhaseTimings.enabled {
            return null
        }

        return new CompilerPhaseMark(project, phase, Stopwatch.GetTimestamp(), CurrentCpuTicks(), GC.GetTotalAllocatedBytes(false))
    }

    static func End(mark: CompilerPhaseMark?) {
        if mark == null {
            return
        }

        wallTicks := Stopwatch.GetTimestamp() - mark.StartTimestamp
        cpuTicks := CurrentCpuTicks() - mark.StartCpuTicks
        allocated := GC.GetTotalAllocatedBytes(false) - mark.StartAllocatedBytes
        CompilerPhaseTimings.records.Enqueue(new CompilerPhaseRecord(mark.Project, mark.Phase, wallTicks, cpuTicks, allocated, 1))
    }

    // Repeated (project, phase) rows folded into one, in the order each pair was first recorded.
    static func Snapshot(): List<CompilerPhaseRecord> {
        folded := new List<CompilerPhaseRecord>()
        indexByKey := new Dictionary<string, int>(StringComparer.Ordinal)
        for row in CompilerPhaseTimings.records.ToArray() {
            key := row.Project + "\n" + row.Phase
            existing := 0
            if indexByKey.TryGetValue(key, out existing) {
                previous := folded[existing]
                folded[existing] = new CompilerPhaseRecord(
                    previous.Project,
                    previous.Phase,
                    previous.WallTicks + row.WallTicks,
                    previous.CpuTicks + row.CpuTicks,
                    previous.AllocatedBytes + row.AllocatedBytes,
                    previous.Count + row.Count
                )
            } else {
                indexByKey[key] = folded.Count
                folded.Add(row)
            }
        }

        return folded
    }

    // One row per (project, phase): `<project> <phase> wall=<ms> cpu=<ms> alloc=<MB>`. Phase names
    // are lower-case so no row can be mistaken for one of the `Build timings:` block's own lines.
    static func Format(): string {
        builder := new StringBuilder()
        builder.Append("Phase timings:")
        for phaseRow in Snapshot() {
            builder.Append("\n  ")
            builder.Append(phaseRow.Project)
            builder.Append(" ")
            builder.Append(phaseRow.Phase)
            builder.Append(" wall=")
            builder.Append(phaseRow.WallMilliseconds.ToString())
            builder.Append("ms cpu=")
            builder.Append(phaseRow.CpuMilliseconds.ToString())
            builder.Append("ms alloc=")
            builder.Append((phaseRow.AllocatedBytes / 1048576).ToString())
            builder.Append("MB")
            if phaseRow.Count > 1 {
                builder.Append(" calls=")
                builder.Append(phaseRow.Count.ToString())
            }
        }

        return builder.ToString()
    }

    private static func CurrentCpuTicks(): long {
        process := Process.GetCurrentProcess()
        try {
            return process.TotalProcessorTime.Ticks
        } finally {
            process.Dispose()
        }
    }
}

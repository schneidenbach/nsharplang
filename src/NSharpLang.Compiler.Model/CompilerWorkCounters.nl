namespace NSharpLang.Compiler

import System.Threading

// THE COMPILER'S STRUCTURAL WORK COUNTERS.
//
// How much WORK a command did, counted where the work happens, so that a latency change can be
// explained by something machine load cannot move. A wall clock answers "was it slow"; these answer
// "did it parse every file again", "did it emit an assembly it did not need", "did it reopen the
// whole reference closure". `nlc check|build|test --stats` reports them (`CliStatsKernels`), and the
// agent-loop benchmark (`tests/native/compile-time-bench`, `AgentLoopBench.nl`) gates them EXACTLY.
//
// They are process-wide and always on: one atomic increment per file, per assembly, per reference
// image, per child process. Nothing reads them on the hot path, and nothing resets them, so a
// long-lived host (the daemon, the language server) that wants a per-request figure takes a
// `Snapshot()` before and after and subtracts.
//
// WHAT EACH ONE COUNTS -- the same sentences `memory/components/cli-toolchain.md` documents:
//   * FilesParsed: a source file parsed into the syntax tree the analyzer reads
//     (`ColumnarParserRecovery`); the same file parsed twice counts twice, which is the point.
//   * EmitParses: a source file tokenized and parsed by the columnar IL pipeline
//     (`ColumnarProgramInputBuilder`), which reads source independently of the syntax tree.
//   * FilesAnalyzed: one compilation unit through `Analyzer.Analyze`.
//   * AssembliesEmitted: one IL image written by the columnar emitter (reference assemblies are
//     not counted; they are a by-product of an emitted image).
//   * ReferenceAssembliesLoaded: one reference image opened from a path -- a MetadataLoadContext
//     load or an exact-identity executable load. One file opened by two contexts counts twice.
//   * ProcessesSpawned: one child process this process started.
//
// The fields are INSTANCE fields of one shared object, not static fields, because
// `Interlocked.Increment(ref <static field>)` is not what the stage-0 seed compiles; the daemon's
// `DaemonRequestIds` uses the same shape for the same reason.
class CompilerWorkCounters {
    private static readonly s_shared: CompilerWorkCounters = new CompilerWorkCounters()

    filesParsed: long = 0
    emitParses: long = 0
    filesAnalyzed: long = 0
    assembliesEmitted: long = 0
    referenceAssembliesLoaded: long = 0
    processesSpawned: long = 0

    static Shared: CompilerWorkCounters => s_shared

    func CountFileParsed() {
        Interlocked.Increment(ref filesParsed)
    }

    func CountEmitParse() {
        Interlocked.Increment(ref emitParses)
    }

    func CountFileAnalyzed() {
        Interlocked.Increment(ref filesAnalyzed)
    }

    func CountAssemblyEmitted() {
        Interlocked.Increment(ref assembliesEmitted)
    }

    func CountReferenceAssemblyLoaded() {
        Interlocked.Increment(ref referenceAssembliesLoaded)
    }

    func CountProcessSpawned() {
        Interlocked.Increment(ref processesSpawned)
    }

    func Snapshot(): CompilerWorkCounterSnapshot {
        return new CompilerWorkCounterSnapshot(
            Interlocked.Read(ref filesParsed),
            Interlocked.Read(ref emitParses),
            Interlocked.Read(ref filesAnalyzed),
            Interlocked.Read(ref assembliesEmitted),
            Interlocked.Read(ref referenceAssembliesLoaded),
            Interlocked.Read(ref processesSpawned)
        )
    }
}

record CompilerWorkCounterSnapshot(
    FilesParsed: long,
    EmitParses: long,
    FilesAnalyzed: long,
    AssembliesEmitted: long,
    ReferenceAssembliesLoaded: long,
    ProcessesSpawned: long
) {

    // The work done between `earlier` and this snapshot.
    func Since(earlier: CompilerWorkCounterSnapshot): CompilerWorkCounterSnapshot {
        return new CompilerWorkCounterSnapshot(
            FilesParsed - earlier.FilesParsed,
            EmitParses - earlier.EmitParses,
            FilesAnalyzed - earlier.FilesAnalyzed,
            AssembliesEmitted - earlier.AssembliesEmitted,
            ReferenceAssembliesLoaded - earlier.ReferenceAssembliesLoaded,
            ProcessesSpawned - earlier.ProcessesSpawned
        )
    }
}

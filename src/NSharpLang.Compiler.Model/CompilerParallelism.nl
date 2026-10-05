namespace NSharpLang.Compiler

import System


// HOW MANY WORKERS ONE COMPILATION PHASE MAY USE: the one owner of the compiler's in-project
// parallelism budget.
//
// A phase that fans out (per-file analysis today) asks `WorkerCount` with its number of independent
// work items and the size of the source behind them. The answer is bounded three ways:
//
//   * by the work: never more workers than items, and one worker per `CharactersPerWorker` of source,
//     because every extra worker pays a fixed warm-up (its own analyzer, metadata load context and
//     parsed view of the project) that a small project cannot amortise -- a project under that size
//     is analysed serially, exactly as before parallelism existed;
//   * by the machine: `Environment.ProcessorCount`;
//   * by `MaxWorkers`, so a many-core build server does not multiply the per-worker memory without
//     bound.
//
// `NSHARP_COMPILER_WORKERS=<n>` overrides the heuristic (still capped by the number of items): `1`
// forces the serial path, which is what the serial-versus-parallel differential runs against, and a
// larger value forces fan-out on a small project so tests can exercise it. An unreadable value is
// ignored.
//
// DETERMINISM IS THE PHASE'S OBLIGATION, NOT THIS OWNER'S: every phase that fans out must produce
// output identical to its serial run -- the same diagnostics in the same order, the same IL bytes --
// whatever worker count this returns.
class CompilerParallelism {
    static CharactersPerWorker: long => 400000
    static MaxWorkers: int => 8
    static WorkerOverrideVariable: string => "NSHARP_COMPILER_WORKERS"

    static func WorkerCount(workItems: int, totalSourceCharacters: long): int {
        if workItems <= 1 {
            return 1
        }

        overrideCount := ConfiguredWorkerCount()
        if overrideCount > 0 {
            return Math.Min(overrideCount, workItems)
        }

        ratio := totalSourceCharacters / CompilerParallelism.CharactersPerWorker
        bySize := (int)ratio
        workers := Math.Min(bySize, Math.Min(Environment.ProcessorCount, CompilerParallelism.MaxWorkers))
        workers = Math.Min(workers, workItems)
        if workers < 1 {
            return 1
        }

        return workers
    }

    // The override, or 0 when none is set or it does not parse as a positive count.
    static func ConfiguredWorkerCount(): int {
        configured := Environment.GetEnvironmentVariable(CompilerParallelism.WorkerOverrideVariable)
        if configured == null || configured.Length == 0 {
            return 0
        }

        parsed := 0
        if Int32.TryParse(configured.Trim(), out parsed) && parsed > 0 {
            return parsed
        }

        return 0
    }
}

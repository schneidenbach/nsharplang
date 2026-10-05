namespace NSharpLang.Compiler

import System
import System.Diagnostics
import System.Text
import System.Threading

// THE COMPILER'S STRUCTURAL COUNTERS: how much work a command actually did, counted where the work
// happens. Wall clock on a shared machine says little about whether a change made the compiler do
// LESS; "12 files analysed" against "1 file analysed" says it exactly, and it says it the same way on
// a quiet laptop and a loaded build agent. Every slice can reach this owner (it is the lowest one),
// so the parser, the analyzer driver, the emitter driver and the incremental cache all count into
// ONE place, and one reader — `NSHARP_STATS=1` on any `nlc` command, or a bench harness calling
// `ToJson` — sees all of them.
//
// Process-wide and additive: a workspace check that compiles three projects on three threads reports
// the sum, which is what "work done by this command" means. `Reset` exists for in-process harnesses
// (the differential test, a warm daemon measuring one request) that want a window rather than a
// lifetime.
static class CompilerStats {
    // Files the multi-file driver parsed into ASTs (a cache hit does not count).
    private static filesParsed: long = 0
    // Files whose semantic analysis ran (a reused per-file analysis does not count).
    private static filesAnalyzed: long = 0
    // Files whose analysis products were reused from the incremental cache instead.
    private static filesAnalysisReused: long = 0
    // Files the strict linter ran over.
    private static filesLinted: long = 0
    // Files handed to the columnar emitter, and assemblies it wrote.
    private static filesPlanned: long = 0
    private static assembliesEmitted: long = 0
    // Compilations answered entirely by the up-to-date check: nothing parsed, analysed or emitted.
    private static compilationsUpToDate: long = 0
    // Compilations that ran (some or all of) the pipeline.
    private static compilationsRun: long = 0
    // Persisted-cache outcomes: an entry that was read and matched, read and did not match (or was
    // corrupt, truncated or another format), and entries written.
    private static cacheHits: long = 0
    private static cacheMisses: long = 0
    private static cacheWrites: long = 0
    // Phase wall time, in Stopwatch ticks, summed over every compilation in the process.
    private static parseTicks: long = 0
    private static analyzeTicks: long = 0
    private static lintTicks: long = 0
    private static emitTicks: long = 0
    private static upToDateTicks: long = 0

    FilesParsed: long => Interlocked.Read(ref filesParsed)
    FilesAnalyzed: long => Interlocked.Read(ref filesAnalyzed)
    FilesAnalysisReused: long => Interlocked.Read(ref filesAnalysisReused)
    FilesLinted: long => Interlocked.Read(ref filesLinted)
    FilesPlanned: long => Interlocked.Read(ref filesPlanned)
    AssembliesEmitted: long => Interlocked.Read(ref assembliesEmitted)
    CompilationsUpToDate: long => Interlocked.Read(ref compilationsUpToDate)
    CompilationsRun: long => Interlocked.Read(ref compilationsRun)
    CacheHits: long => Interlocked.Read(ref cacheHits)
    CacheMisses: long => Interlocked.Read(ref cacheMisses)
    CacheWrites: long => Interlocked.Read(ref cacheWrites)

    static func AddFilesParsed(count: int) {
        Interlocked.Add(ref filesParsed, count)
    }

    static func AddFilesAnalyzed(count: int) {
        Interlocked.Add(ref filesAnalyzed, count)
    }

    static func AddFilesAnalysisReused(count: int) {
        Interlocked.Add(ref filesAnalysisReused, count)
    }

    static func AddFilesLinted(count: int) {
        Interlocked.Add(ref filesLinted, count)
    }

    static func AddFilesPlanned(count: int) {
        Interlocked.Add(ref filesPlanned, count)
    }

    static func AddAssemblyEmitted() {
        Interlocked.Increment(ref assembliesEmitted)
    }

    static func AddCompilationUpToDate() {
        Interlocked.Increment(ref compilationsUpToDate)
    }

    static func AddCompilationRun() {
        Interlocked.Increment(ref compilationsRun)
    }

    static func AddCacheHit() {
        Interlocked.Increment(ref cacheHits)
    }

    static func AddCacheMiss() {
        Interlocked.Increment(ref cacheMisses)
    }

    static func AddCacheWrite() {
        Interlocked.Increment(ref cacheWrites)
    }

    static func AddParseTicks(ticks: long) {
        Interlocked.Add(ref parseTicks, ticks)
    }

    static func AddAnalyzeTicks(ticks: long) {
        Interlocked.Add(ref analyzeTicks, ticks)
    }

    static func AddLintTicks(ticks: long) {
        Interlocked.Add(ref lintTicks, ticks)
    }

    static func AddEmitTicks(ticks: long) {
        Interlocked.Add(ref emitTicks, ticks)
    }

    static func AddUpToDateTicks(ticks: long) {
        Interlocked.Add(ref upToDateTicks, ticks)
    }

    // Only for a quiescent process (a harness between requests): nothing may be counting concurrently.
    static func Reset() {
        filesParsed = 0
        filesAnalyzed = 0
        filesAnalysisReused = 0
        filesLinted = 0
        filesPlanned = 0
        assembliesEmitted = 0
        compilationsUpToDate = 0
        compilationsRun = 0
        cacheHits = 0
        cacheMisses = 0
        cacheWrites = 0
        parseTicks = 0
        analyzeTicks = 0
        lintTicks = 0
        emitTicks = 0
        upToDateTicks = 0
    }

    // Whether the process was asked to report: `NSHARP_STATS=1` (or `true`).
    static func IsReportRequested(): bool {
        value := Environment.GetEnvironmentVariable("NSHARP_STATS")
        if value == null {
            return false
        }

        return value == "1" || string.Equals(value, "true", StringComparison.OrdinalIgnoreCase)
    }

    // One line of versioned JSON. Counters are exact; the `*Ms` phase times are wall clock and only
    // as good as the machine they were measured on.
    static func ToJson(): string {
        builder := new StringBuilder()
        builder.Append("{\"schemaVersion\":1,\"kind\":\"nsharp.compiler-stats\"")
        AppendCounter(builder, "filesParsed", Interlocked.Read(ref filesParsed))
        AppendCounter(builder, "filesAnalyzed", Interlocked.Read(ref filesAnalyzed))
        AppendCounter(builder, "filesAnalysisReused", Interlocked.Read(ref filesAnalysisReused))
        AppendCounter(builder, "filesLinted", Interlocked.Read(ref filesLinted))
        AppendCounter(builder, "filesPlanned", Interlocked.Read(ref filesPlanned))
        AppendCounter(builder, "assembliesEmitted", Interlocked.Read(ref assembliesEmitted))
        AppendCounter(builder, "compilationsRun", Interlocked.Read(ref compilationsRun))
        AppendCounter(builder, "compilationsUpToDate", Interlocked.Read(ref compilationsUpToDate))
        AppendCounter(builder, "cacheHits", Interlocked.Read(ref cacheHits))
        AppendCounter(builder, "cacheMisses", Interlocked.Read(ref cacheMisses))
        AppendCounter(builder, "cacheWrites", Interlocked.Read(ref cacheWrites))
        AppendCounter(builder, "parseMs", TicksToMilliseconds(Interlocked.Read(ref parseTicks)))
        AppendCounter(builder, "analyzeMs", TicksToMilliseconds(Interlocked.Read(ref analyzeTicks)))
        AppendCounter(builder, "lintMs", TicksToMilliseconds(Interlocked.Read(ref lintTicks)))
        AppendCounter(builder, "emitMs", TicksToMilliseconds(Interlocked.Read(ref emitTicks)))
        AppendCounter(builder, "upToDateCheckMs", TicksToMilliseconds(Interlocked.Read(ref upToDateTicks)))
        builder.Append("}")
        return builder.ToString()
    }

    private static func AppendCounter(builder: StringBuilder, name: string, value: long) {
        builder.Append(",\"")
        builder.Append(name)
        builder.Append("\":")
        builder.Append(value.ToString(System.Globalization.CultureInfo.InvariantCulture))
    }

    private static func TicksToMilliseconds(ticks: long): long {
        return ticks * 1000 / Stopwatch.Frequency
    }
}

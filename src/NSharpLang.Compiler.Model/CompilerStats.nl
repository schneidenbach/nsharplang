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
// ONE place, and one reader — `NSHARP_STATS=1` on any `nlc` command, or a harness calling
// `Snapshot()` (plain values it can subtract) or `ToJson()` — sees all of them. The surface is
// functions, not static properties: a consumer the columnar backend compiled declined to read this
// class's static properties (2026-10-05).
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
    // Compilations requested (`CompileToIlAssembly`, `CompileForAnalysis`), whether or not the
    // up-to-date check then answered them.
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

    // A consistent-enough copy of every counter (each read is atomic; the set is not a transaction,
    // which only matters while compilations are running).
    static func Snapshot(): CompilerStatsSnapshot {
        snapshot := new CompilerStatsSnapshot()
        snapshot.FilesParsed = Interlocked.Read(ref filesParsed)
        snapshot.FilesAnalyzed = Interlocked.Read(ref filesAnalyzed)
        snapshot.FilesAnalysisReused = Interlocked.Read(ref filesAnalysisReused)
        snapshot.FilesLinted = Interlocked.Read(ref filesLinted)
        snapshot.FilesPlanned = Interlocked.Read(ref filesPlanned)
        snapshot.AssembliesEmitted = Interlocked.Read(ref assembliesEmitted)
        snapshot.CompilationsRun = Interlocked.Read(ref compilationsRun)
        snapshot.CompilationsUpToDate = Interlocked.Read(ref compilationsUpToDate)
        snapshot.CacheHits = Interlocked.Read(ref cacheHits)
        snapshot.CacheMisses = Interlocked.Read(ref cacheMisses)
        snapshot.CacheWrites = Interlocked.Read(ref cacheWrites)
        snapshot.ParseMs = CompilerStats.TicksToMilliseconds(Interlocked.Read(ref parseTicks))
        snapshot.AnalyzeMs = CompilerStats.TicksToMilliseconds(Interlocked.Read(ref analyzeTicks))
        snapshot.LintMs = CompilerStats.TicksToMilliseconds(Interlocked.Read(ref lintTicks))
        snapshot.EmitMs = CompilerStats.TicksToMilliseconds(Interlocked.Read(ref emitTicks))
        snapshot.UpToDateCheckMs = CompilerStats.TicksToMilliseconds(Interlocked.Read(ref upToDateTicks))
        return snapshot
    }

    static func ToJson(): string {
        snapshot := CompilerStats.Snapshot()
        return snapshot.ToJson()
    }

    static func TicksToMilliseconds(ticks: long): long {
        return ticks * 1000 / Stopwatch.Frequency
    }
}

// THE COUNTERS AT ONE MOMENT, as plain values a harness can read, subtract and print.
class CompilerStatsSnapshot {
    FilesParsed: long
    FilesAnalyzed: long
    FilesAnalysisReused: long
    FilesLinted: long
    FilesPlanned: long
    AssembliesEmitted: long
    CompilationsRun: long
    CompilationsUpToDate: long
    CacheHits: long
    CacheMisses: long
    CacheWrites: long
    ParseMs: long
    AnalyzeMs: long
    LintMs: long
    EmitMs: long
    UpToDateCheckMs: long

    constructor() {
        FilesParsed = 0
        FilesAnalyzed = 0
        FilesAnalysisReused = 0
        FilesLinted = 0
        FilesPlanned = 0
        AssembliesEmitted = 0
        CompilationsRun = 0
        CompilationsUpToDate = 0
        CacheHits = 0
        CacheMisses = 0
        CacheWrites = 0
        ParseMs = 0
        AnalyzeMs = 0
        LintMs = 0
        EmitMs = 0
        UpToDateCheckMs = 0
    }

    // One line of versioned JSON. Counters are exact; the `*Ms` phase times are wall clock and only
    // as good as the machine they were measured on.
    func ToJson(): string {
        builder := new StringBuilder()
        builder.Append("{\"schemaVersion\":1,\"kind\":\"nsharp.compiler-stats\"")
        CompilerStatsSnapshot.AppendCounter(builder, "filesParsed", FilesParsed)
        CompilerStatsSnapshot.AppendCounter(builder, "filesAnalyzed", FilesAnalyzed)
        CompilerStatsSnapshot.AppendCounter(builder, "filesAnalysisReused", FilesAnalysisReused)
        CompilerStatsSnapshot.AppendCounter(builder, "filesLinted", FilesLinted)
        CompilerStatsSnapshot.AppendCounter(builder, "filesPlanned", FilesPlanned)
        CompilerStatsSnapshot.AppendCounter(builder, "assembliesEmitted", AssembliesEmitted)
        CompilerStatsSnapshot.AppendCounter(builder, "compilationsRun", CompilationsRun)
        CompilerStatsSnapshot.AppendCounter(builder, "compilationsUpToDate", CompilationsUpToDate)
        CompilerStatsSnapshot.AppendCounter(builder, "cacheHits", CacheHits)
        CompilerStatsSnapshot.AppendCounter(builder, "cacheMisses", CacheMisses)
        CompilerStatsSnapshot.AppendCounter(builder, "cacheWrites", CacheWrites)
        CompilerStatsSnapshot.AppendCounter(builder, "parseMs", ParseMs)
        CompilerStatsSnapshot.AppendCounter(builder, "analyzeMs", AnalyzeMs)
        CompilerStatsSnapshot.AppendCounter(builder, "lintMs", LintMs)
        CompilerStatsSnapshot.AppendCounter(builder, "emitMs", EmitMs)
        CompilerStatsSnapshot.AppendCounter(builder, "upToDateCheckMs", UpToDateCheckMs)
        builder.Append("}")
        return builder.ToString()
    }

    private static func AppendCounter(builder: StringBuilder, name: string, value: long) {
        builder.Append(",\"")
        builder.Append(name)
        builder.Append("\":")
        builder.Append(value.ToString(System.Globalization.CultureInfo.InvariantCulture))
    }
}

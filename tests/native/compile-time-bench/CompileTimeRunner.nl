namespace NSharpLang.CompileTimeBench

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text
import System.Text.Json


// THE PROCESS SIDE OF THE COMPILE-TIME BENCHMARK.
//
// One owner for "run a command and measure it": `BenchMeasureOnce`. The sweep in `Program.nl` and
// the regression gate in `CompileTimeBench.tests.nl` both go through it, so the number the gate
// compares against a baseline is produced by exactly the code that produced the baseline.
//
// EVERY RUN IS FRESH BY CONSTRUCTION. `nlc build` has no incremental cache and `nlc check` has no
// daemon on this path, so a repeat run is already cold; the output directory is nevertheless
// created new under `Path.GetTempPath()` for every single run and deleted afterwards, so a run can
// never read another run's artifacts.
//
// AND EVERY BUILD IS PROVEN NOT TO HAVE TOUCHED THE TREE. A recursive listing of the project
// directory — each file's relative path and its last-write UTC tick, every directory sorted — is
// taken immediately before and immediately after each build, and any difference is a HARNESS
// failure, reported with the offending entries and carried to a non-zero exit code. The listing
// carries no byte length; `BenchSnapshotDirectory` states the measured reason why. A benchmark that
// mutated the repository it measures would invalidate both its own next run and the working tree of
// whoever ran it.

// ─── DISCOVERY ────────────────────────────────────────────────────────────────────────────────

// The repository root, found by walking up from the directory this assembly was loaded into. The
// walk (rather than the current directory) is what lets the same kernels serve the standalone
// harness executable and the gate test, which `nlc test` hosts inside the CLI's own process.
func BenchRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "AGENTS.md")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) && Directory.Exists(Path.Combine(directory, "examples")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the repository root above this assembly.")
}

func BenchDefaultCliDll(repositoryRoot: string): string {
    return Path.Combine(
        Path.Combine(
            Path.Combine(
                Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Cli"),
                "bin"
            ),
            "Debug"
        ),
        Path.Combine("net10.0", "Cli.dll")
    )
}

func BenchAbsoluteProjectPath(repositoryRoot: string, relativeProject: string): string {
    result := repositoryRoot
    segments := relativeProject.Split('/')
    i := 0
    while i < segments.Length {
        result = Path.Combine(result, segments[i])
        i = i + 1
    }

    return result
}

func BenchQuote(value: string): string {
    return "\"" + value + "\""
}

// ─── THE SPAWN KERNEL ─────────────────────────────────────────────────────────────────────────

class BenchProcessRun {
    ExitCode: int
    Stdout: string
    Stderr: string
    WallMs: long

    constructor(exitCode: int, stdout: string, stderr: string, wallMs: long) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
        WallMs = wallMs
    }
}

// Start a child, drain BOTH pipes CONCURRENTLY, wait, and dispose.
//
// THE CONCURRENCY IS THE WHOLE POINT, AND IT IS NOT THEORETICAL. Reading stdout to end BEFORE
// touching stderr deadlocks the moment a child writes more to stderr than the OS pipe buffer holds:
// the child blocks writing stderr, so it never closes stdout, so our read of stdout never returns.
// The buffer is 64 KB and `nlc build` on `src/NSharpLang.Compiler.BootstrapServices` already writes
// 25 KB of diagnostics to stderr today — the sequential shape survives only on that margin, and the
// margin shrinks every time a diagnostic is added. This is the estate's proven shape, from
// `DotnetRunner.RunProcessCore`: both `ReadToEndAsync()` tasks are started FIRST, so neither pipe
// can fill while the other is being drained, and `.Result` is read only after the child has exited.
//
// No timeout: `DotnetRunner` needs one because it drives arbitrary `dotnet` invocations, whereas
// every child here is the CLI under measurement, and a hang in it is a finding the benchmark should
// surface by hanging visibly rather than hide behind a kill.
//
// The wall clock is read from `DateTime.UtcNow` immediately either side of the process's life, in
// ticks, and reported in milliseconds.
func BenchRunProcess(fileName: string, arguments: string, workingDirectory: string): BenchProcessRun {
    startInfo := new ProcessStartInfo { FileName: fileName, Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    startTicks := DateTime.UtcNow.Ticks
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    process.WaitForExit()
    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    endTicks := DateTime.UtcNow.Ticks
    exitCode := process.ExitCode
    process.Dispose()

    return new BenchProcessRun(exitCode, stdout, stderr, (endTicks - startTicks) / 10000)
}

// `/usr/bin/time` when it is there and the platform's flag is known, `""` otherwise. Without it a
// run still reports its wall clock and its timings; only the peak-RSS column goes empty.
func BenchTimeUtilityPath(): string {
    if !OperatingSystem.IsMacOS() && !OperatingSystem.IsLinux() {
        return ""
    }

    if !File.Exists("/usr/bin/time") {
        return ""
    }

    return "/usr/bin/time"
}

func BenchTimeUtilityFlag(): string {
    if OperatingSystem.IsMacOS() {
        return "-l"
    }

    if OperatingSystem.IsLinux() {
        return "-v"
    }

    return ""
}

// Run `dotnet <args>` under the OS time utility when one is available, so that the kernel — not
// this process — reports the child's maximum resident set size.
func BenchRunUnderTimeUtility(arguments: string, workingDirectory: string): BenchProcessRun {
    timeUtility := BenchTimeUtilityPath()
    if timeUtility == "" {
        return BenchRunProcess("dotnet", arguments, workingDirectory)
    }

    return BenchRunProcess(timeUtility, BenchTimeUtilityFlag() + " dotnet " + arguments, workingDirectory)
}

// ─── ONE MEASURED RUN ─────────────────────────────────────────────────────────────────────────

class BenchCommandRun {
    Command: string
    ExitCode: int
    WallMs: long
    PeakRssBytes: long
    ResolveMs: long
    EmitMs: long
    TotalMs: long
    Stdout: string
    CliStderr: string
    TreeDiff: string
    SawBuildFailedBanner: bool

    constructor(command: string, exitCode: int, wallMs: long, peakRssBytes: long) {
        Command = command
        ExitCode = exitCode
        WallMs = wallMs
        PeakRssBytes = peakRssBytes
        ResolveMs = -1
        EmitMs = -1
        TotalMs = -1
        Stdout = ""
        CliStderr = ""
        TreeDiff = ""
        SawBuildFailedBanner = false
    }
}

func BenchFreshOutputDirectory(sequence: int): string {
    directory := Path.Combine(
        Path.GetTempPath(),
        "nsharp-compile-bench-" + BenchIntText(sequence) + "-" + BenchLongText(DateTime.UtcNow.Ticks)
    )
    BenchDeleteDirectory(directory)
    Directory.CreateDirectory(directory)
    return directory
}

func BenchDeleteDirectory(directory: string) {
    if !Directory.Exists(directory) {
        return
    }

    try {
        Directory.Delete(directory, true)
    } catch {
        return
    }
}

// THE ONE OWNER of "run a build and measure it". `command` is `build` or `check`.
func BenchMeasureOnce(cliDll: string, projectDirectory: string, command: string, sequence: int): BenchCommandRun {
    if command == "check" {
        run := BenchRunUnderTimeUtility(
            BenchQuote(cliDll) + " check --project " + BenchQuote(projectDirectory) + " --json",
            Path.GetTempPath()
        )
        measured := new BenchCommandRun(command, run.ExitCode, run.WallMs, BenchParsePeakRssBytes(run.Stderr))
        measured.Stdout = run.Stdout
        measured.CliStderr = BenchStripTimeUtilityLines(run.Stderr)
        return measured
    }

    outputDirectory := BenchFreshOutputDirectory(sequence)
    before := BenchSnapshotDirectory(projectDirectory)
    run := BenchRunUnderTimeUtility(
        BenchQuote(cliDll) + " build --project " + BenchQuote(projectDirectory) + " --timings -o " + BenchQuote(outputDirectory),
        Path.GetTempPath()
    )
    after := BenchSnapshotDirectory(projectDirectory)
    BenchDeleteDirectory(outputDirectory)

    measured := new BenchCommandRun(command, run.ExitCode, run.WallMs, BenchParsePeakRssBytes(run.Stderr))
    measured.Stdout = run.Stdout
    measured.CliStderr = BenchStripTimeUtilityLines(run.Stderr)
    measured.TreeDiff = BenchDiffSnapshots(before, after)
    measured.SawBuildFailedBanner = BenchSawBuildFailedBanner(run.Stdout)

    timings := BenchParseBuildTimings(measured.CliStderr)
    if timings.Found {
        measured.ResolveMs = timings.ResolveMs
        measured.EmitMs = timings.EmitMs
        measured.TotalMs = timings.TotalMs
    }

    return measured
}

// `checkedFiles` out of the `nlc check --json` envelope, which is `snapshot.SourceFiles.Count`
// straight from the compiler — the live oracle this harness cross-checks its own file count
// against. `-1` when the envelope did not carry one (a check that failed before analysis).
func BenchCheckedFilesFromJson(stdout: string): int {
    if stdout.Trim().Length == 0 {
        return -1
    }

    result := -1
    try {
        document := JsonDocument.Parse(stdout)
        result = document.RootElement.GetProperty("checkedFiles").GetInt32()
        document.Dispose()
    } catch {
        return -1
    }

    return result
}

// ─── ONE PROJECT, ONE COMMAND, N RUNS ─────────────────────────────────────────────────────────

class BenchProjectResult {
    Present: bool
    Project: string
    Command: string
    Files: int
    Lines: long
    Ok: bool
    Runs: int
    MedianWallMs: long
    MinWallMs: long
    MaxWallMs: long
    MedianResolveMs: long
    MedianEmitMs: long
    MedianTotalMs: long
    MedianPeakRssBytes: long
    LinesPerSecondTenths: long
    Status: string
    CheckedFiles: int
    DiagnosticCensus: string
    DiagnosticResultCount: int
    FailureDetail: string
    FailureStderr: string
    TreeDiff: string

    constructor(project: string, command: string, files: int, lines: long) {
        Present = true
        Project = project
        Command = command
        Files = files
        Lines = lines
        Ok = true
        Runs = 0
        MedianWallMs = -1
        MinWallMs = -1
        MaxWallMs = -1
        MedianResolveMs = -1
        MedianEmitMs = -1
        MedianTotalMs = -1
        MedianPeakRssBytes = -1
        LinesPerSecondTenths = -1
        Status = BenchMeasuredStatus()
        CheckedFiles = -1
        DiagnosticCensus = ""
        DiagnosticResultCount = -1
        FailureDetail = ""
        FailureStderr = ""
        TreeDiff = ""
    }
}

func BenchMeasureProjectCommand(
    cliDll: string,
    repositoryRoot: string,
    relativeProject: string,
    command: string,
    runs: int,
    runRows: StringBuilder
): BenchProjectResult {
    projectDirectory := BenchAbsoluteProjectPath(repositoryRoot, relativeProject)
    sources := BenchMeasureProjectSources(projectDirectory)
    result := new BenchProjectResult(relativeProject, command, sources.Files, sources.Lines)

    // Nothing to compile means nothing to measure: no command is spawned, no run row is written,
    // and the row is classified rather than failed. See `BenchNoSourcesStatus`.
    if sources.Files == 0 {
        result.Status = BenchNoSourcesStatus()
        return result
    }

    wallMs := new long[](runs)
    resolveMs := new long[](runs)
    emitMs := new long[](runs)
    totalMs := new long[](runs)
    peakRss := new long[](runs)
    rssCount := 0
    timingCount := 0

    i := 0
    while i < runs {
        measured := BenchMeasureOnce(cliDll, projectDirectory, command, i + 1)
        wallMs[i] = measured.WallMs

        if measured.PeakRssBytes >= 0 {
            peakRss[rssCount] = measured.PeakRssBytes
            rssCount = rssCount + 1
        }

        if measured.TotalMs >= 0 {
            resolveMs[timingCount] = measured.ResolveMs
            emitMs[timingCount] = measured.EmitMs
            totalMs[timingCount] = measured.TotalMs
            timingCount = timingCount + 1
        }

        if measured.ExitCode != 0 {
            result.Ok = false
            result.Status = BenchFailedStatus()
            if result.FailureDetail == "" {
                result.FailureDetail = "exit " + BenchIntText(measured.ExitCode) + " on run " + BenchIntText(i + 1)
                result.FailureStderr = BenchTruncate(measured.CliStderr, 1600)
            }
        }

        if measured.TreeDiff != "" && result.TreeDiff == "" {
            result.TreeDiff = measured.TreeDiff
        }

        if command == "check" && result.CheckedFiles < 0 {
            result.CheckedFiles = BenchCheckedFilesFromJson(measured.Stdout)
            result.DiagnosticCensus = BenchDiagnosticCensus(measured.Stdout)
            result.DiagnosticResultCount = BenchDiagnosticResultCount(measured.Stdout)
        }

        runRows.Append(BenchRunCsvRow(relativeProject, i + 1, measured))
        runRows.Append("\n")
        i = i + 1
    }

    result.Runs = runs
    result.MedianWallMs = BenchMedian(wallMs, runs)
    result.MinWallMs = BenchMinimum(wallMs, runs)
    result.MaxWallMs = BenchMaximum(wallMs, runs)
    result.MedianResolveMs = BenchMedian(resolveMs, timingCount)
    result.MedianEmitMs = BenchMedian(emitMs, timingCount)
    result.MedianTotalMs = BenchMedian(totalMs, timingCount)
    result.MedianPeakRssBytes = BenchMedian(peakRss, rssCount)
    result.LinesPerSecondTenths = BenchLinesPerSecondTenths(result.Lines, result.MedianWallMs)
    return result
}

func BenchTruncate(text: string, limit: int): string {
    collapsed := text.Trim()
    if collapsed.Length <= limit {
        return collapsed
    }

    return collapsed.Substring(0, limit) + " …"
}

// ─── THE CSV ROWS ─────────────────────────────────────────────────────────────────────────────

func BenchRunCsvHeader(): string {
    return "project,command,run,exitCode,wallMs,resolveMs,emitMs,totalMs,peakRssBytes"
}

func BenchRunCsvRow(project: string, run: int, measured: BenchCommandRun): string {
    return BenchCsvCell(project) + "," + BenchCsvCell(measured.Command) + "," + BenchIntText(run) + "," + BenchIntText(measured.ExitCode) + "," + BenchLongText(measured.WallMs) + "," + BenchCsvNumber(measured.ResolveMs) + "," + BenchCsvNumber(measured.EmitMs) + "," + BenchCsvNumber(measured.TotalMs) + "," + BenchCsvNumber(measured.PeakRssBytes)
}

// The `ok` column of the first shape of this file was a bool, and a bool cannot tell "the compiler
// rejected this project" apart from "this project has nothing for the compiler to read". `status`
// replaces it with the three answers that exist: `measured`, `failed`, `no non-test sources`.
func BenchSummaryCsvHeader(): string {
    return "project,command,files,lines,status,runs,medianWallMs,minWallMs,maxWallMs," + "medianResolveMs,medianEmitMs,medianTotalMs,medianPeakRssBytes,linesPerSecond"
}

func BenchSummaryCsvRow(result: BenchProjectResult): string {
    return BenchCsvCell(result.Project) + "," + BenchCsvCell(result.Command) + "," + BenchIntText(result.Files) + "," + BenchLongText(result.Lines) + "," + BenchCsvCell(result.Status) + "," + BenchIntText(result.Runs) + "," + BenchLongText(result.MedianWallMs) + "," + BenchLongText(result.MinWallMs) + "," + BenchLongText(result.MaxWallMs) + "," + BenchCsvNumber(result.MedianResolveMs) + "," + BenchCsvNumber(result.MedianEmitMs) + "," + BenchCsvNumber(result.MedianTotalMs) + "," + BenchCsvNumber(result.MedianPeakRssBytes) + "," + BenchFormatTenths(result.LinesPerSecondTenths)
}

// ─── THE ENVIRONMENT BLOCK ────────────────────────────────────────────────────────────────────

class BenchEnvironmentFacts {
    CliCommit: string
    DotnetVersion: string
    OsDescription: string
    Architecture: string
    ProcessorCount: int
    TimeUtility: string

    constructor(
        cliCommit: string,
        dotnetVersion: string,
        osDescription: string,
        architecture: string,
        processorCount: int,
        timeUtility: string
    ) {
        CliCommit = cliCommit
        DotnetVersion = dotnetVersion
        OsDescription = osDescription
        Architecture = architecture
        ProcessorCount = processorCount
        TimeUtility = timeUtility
    }
}

func BenchReadEnvironmentFacts(repositoryRoot: string): BenchEnvironmentFacts {
    timeUtility := BenchTimeUtilityPath()
    if timeUtility == "" {
        timeUtility = "(unavailable)"
    } else {
        timeUtility = timeUtility + " " + BenchTimeUtilityFlag()
    }

    cliCommit := BenchReadCliCommit(repositoryRoot)
    dotnetVersion := BenchReadDotnetVersion()
    osDescription := BenchOsDescription()
    architecture := BenchOsArchitecture()
    processorCount := BenchProcessorCount()
    return new BenchEnvironmentFacts(cliCommit, dotnetVersion, osDescription, architecture, processorCount, timeUtility)
}

// THE OS AND ARCH LINES COME FROM `uname`, NOT FROM `RuntimeInformation`. Measured against the
// live CLI at the time of writing: `RuntimeInformation.OSDescription` declines on this emit path
// both as a return expression (`emit.return.expression`) and behind an explicit typed local
// (`emit.typed-local.initializer`), and `Environment.OSVersion.VersionString` declines the same
// way. `uname` is the platform's own answer to the same question, it is already reachable through
// the spawn kernel this file owns, and a failed spawn degrades to the family name rather than to a
// wrong string.
func BenchOsDescription(): string {
    if OperatingSystem.IsMacOS() || OperatingSystem.IsLinux() {
        run := BenchRunProcess("uname", "-sr", Path.GetTempPath())
        if run.ExitCode == 0 {
            return run.Stdout.Trim()
        }
    }

    return BenchOsFamilyName()
}

func BenchOsArchitecture(): string {
    if OperatingSystem.IsMacOS() || OperatingSystem.IsLinux() {
        run := BenchRunProcess("uname", "-m", Path.GetTempPath())
        if run.ExitCode == 0 {
            return run.Stdout.Trim()
        }
    }

    return "unknown"
}

func BenchOsFamilyName(): string {
    if OperatingSystem.IsMacOS() {
        return "macOS"
    }

    if OperatingSystem.IsLinux() {
        return "Linux"
    }

    if OperatingSystem.IsWindows() {
        return "Windows"
    }

    return "unknown"
}

// `Environment.ProcessorCount` declines on this emit path the same way `RuntimeInformation` does,
// so the logical-processor count is asked of the platform: `sysctl` on macOS, `nproc` on Linux.
// `-1` when neither answers, which the report renders as `unknown`.
func BenchProcessorCount(): int {
    if OperatingSystem.IsMacOS() {
        return BenchSpawnedCount("sysctl", "-n hw.logicalcpu")
    }

    if OperatingSystem.IsLinux() {
        return BenchSpawnedCount("nproc", "")
    }

    return -1
}

func BenchSpawnedCount(fileName: string, arguments: string): int {
    run := BenchRunProcess(fileName, arguments, Path.GetTempPath())
    if run.ExitCode != 0 {
        return -1
    }

    return BenchParseCount(run.Stdout.Trim())
}

func BenchReadCliCommit(repositoryRoot: string): string {
    run := BenchRunProcess("git", "-C " + BenchQuote(repositoryRoot) + " rev-parse HEAD", Path.GetTempPath())
    if run.ExitCode != 0 {
        return "unknown"
    }

    return run.Stdout.Trim()
}

func BenchReadDotnetVersion(): string {
    run := BenchRunProcess("dotnet", "--version", Path.GetTempPath())
    if run.ExitCode != 0 {
        return "unknown"
    }

    return run.Stdout.Trim()
}

// ─── THE MARKDOWN REPORT ──────────────────────────────────────────────────────────────────────

func BenchAppendLine(builder: StringBuilder, line: string) {
    builder.Append(line)
    builder.Append("\n")
}

// A missing row is an ABSENT result rather than a null one: a `--scope` or `--only` run legitimately
// measures build without check (or neither), and every renderer below reads `Present` instead of
// carrying a nullable through the whole report.
func BenchHasNoSources(result: BenchProjectResult): bool {
    return result.Present && result.Status == BenchNoSourcesStatus()
}

func BenchAbsentResult(): BenchProjectResult {
    absent := new BenchProjectResult("", "", 0, 0)
    absent.Present = false
    return absent
}

func BenchFindResult(results: List<BenchProjectResult>, project: string, command: string): BenchProjectResult {
    i := 0
    while i < results.Count {
        if results[i].Project == project && results[i].Command == command {
            return results[i]
        }

        i = i + 1
    }

    return BenchAbsentResult()
}

func BenchDistinctProjects(results: List<BenchProjectResult>): List<string> {
    projects := new List<string>()
    seen := new HashSet<string>(StringComparer.Ordinal)
    i := 0
    while i < results.Count {
        if seen.Add(results[i].Project) {
            projects.Add(results[i].Project)
        }

        i = i + 1
    }

    return projects
}

func BenchOkColumn(build: BenchProjectResult, check: BenchProjectResult): string {
    if BenchHasNoSources(build) || BenchHasNoSources(check) {
        return "n/a (" + BenchNoSourcesStatus() + ")"
    }

    buildFailed := build.Present && !build.Ok
    checkFailed := check.Present && !check.Ok
    if !buildFailed && !checkFailed {
        return "yes"
    }

    if buildFailed && checkFailed {
        return "**no (build+check)**"
    }

    if buildFailed {
        return "**no (build)**"
    }

    return "**no (check)**"
}

func BenchCell(value: long): string {
    if value < 0 {
        return "—"
    }

    return BenchLongText(value)
}

func BenchRateCell(tenths: long): string {
    if tenths < 0 {
        return "—"
    }

    return BenchFormatTenths(tenths)
}

func BenchRssCell(bytes: long): string {
    if bytes < 0 {
        return "—"
    }

    return BenchFormatMegabytes(bytes)
}

func BenchProjectTableHeader(builder: StringBuilder) {
    BenchAppendLine(builder, "| project | files | lines | ok | build median ms | resolve ms | emit ms | total ms | build peak RSS MB | build lines/s | check median ms | check peak RSS MB | check lines/s | check results |")
    BenchAppendLine(builder, "|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
}

func BenchProjectTableRow(builder: StringBuilder, project: string, build: BenchProjectResult, check: BenchProjectResult) {
    files := 0
    lines := 0L
    if build.Present {
        files = build.Files
        lines = build.Lines
    } else if check.Present {
        files = check.Files
        lines = check.Lines
    }

    buildMedian := -1L
    buildResolve := -1L
    buildEmit := -1L
    buildTotal := -1L
    buildRss := -1L
    buildRate := -1L
    if build.Present {
        buildMedian = build.MedianWallMs
        buildResolve = build.MedianResolveMs
        buildEmit = build.MedianEmitMs
        buildTotal = build.MedianTotalMs
        buildRss = build.MedianPeakRssBytes
        buildRate = build.LinesPerSecondTenths
    }

    checkMedian := -1L
    checkRss := -1L
    checkRate := -1L
    checkResults := -1
    if check.Present {
        checkMedian = check.MedianWallMs
        checkRss = check.MedianPeakRssBytes
        checkRate = check.LinesPerSecondTenths
        checkResults = check.DiagnosticResultCount
    }

    BenchAppendLine(
        builder,
        "| `" + project + "` | " + BenchIntText(files) + " | " + BenchLongText(lines) + " | " + BenchOkColumn(build, check) + " | " + BenchCell(buildMedian) + " | " + BenchCell(buildResolve) + " | " + BenchCell(buildEmit) + " | " + BenchCell(buildTotal) + " | " + BenchRssCell(buildRss) + " | " + BenchRateCell(buildRate) + " | " + BenchCell(checkMedian) + " | " + BenchRssCell(checkRss) + " | " + BenchRateCell(checkRate) + " | " + BenchCell(checkResults) + " |"
    )
}

class BenchAggregate {
    Command: string
    Scope: string
    Projects: int
    Lines: long
    SumMedianWallMs: long
    LinesPerSecondTenths: long

    constructor(command: string, scope: string, projects: int, lines: long, sumMedianWallMs: long) {
        Command = command
        Scope = scope
        Projects = projects
        Lines = lines
        SumMedianWallMs = sumMedianWallMs
        LinesPerSecondTenths = BenchLinesPerSecondTenths(lines, sumMedianWallMs)
    }
}

// A row with no non-test sources contributes NOTHING to an aggregate — not its lines, not a place
// in the project count. It was never compiled by the command being aggregated, so counting it would
// dilute a lines-per-second figure with source no command read.
func BenchAggregateOver(results: List<BenchProjectResult>, command: string, scope: string, okOnly: bool): BenchAggregate {
    projects := 0
    lines := 0L
    sumMedian := 0L
    i := 0
    while i < results.Count {
        result := results[i]
        if result.Command == command && !BenchHasNoSources(result) && (!okOnly || result.Ok) {
            projects = projects + 1
            lines = lines + result.Lines
            if result.MedianWallMs > 0 {
                sumMedian = sumMedian + result.MedianWallMs
            }
        }

        i = i + 1
    }

    return new BenchAggregate(command, scope, projects, lines, sumMedian)
}

func BenchAggregateTable(results: List<BenchProjectResult>, label: string): string {
    builder := new StringBuilder()
    BenchAppendLine(builder, "| command | scope | projects | lines | sum of median wall ms | aggregate lines/s |")
    BenchAppendLine(builder, "|---|---|---:|---:|---:|---:|")
    BenchAggregateRow(builder, BenchAggregateOver(results, "build", label, false))
    BenchAggregateRow(builder, BenchAggregateOver(results, "build", "compiled (status=measured, exit 0)", true))
    BenchAggregateRow(builder, BenchAggregateOver(results, "check", label, false))
    BenchAggregateRow(builder, BenchAggregateOver(results, "check", "compiled (status=measured, exit 0)", true))
    return builder.ToString() ?? ""
}

func BenchAggregateRow(builder: StringBuilder, aggregate: BenchAggregate) {
    BenchAppendLine(
        builder,
        "| " + aggregate.Command + " | " + aggregate.Scope + " | " + BenchIntText(aggregate.Projects) + " | " + BenchLongText(aggregate.Lines) + " | " + BenchLongText(aggregate.SumMedianWallMs) + " | " + BenchRateCell(aggregate.LinesPerSecondTenths) + " |"
    )
}

// The middle, slowest and fastest per-project rate for one command, as one Markdown line each.
func BenchRateSpreadLines(results: List<BenchProjectResult>, command: string, builder: StringBuilder) {
    rates := new long[](results.Count)
    count := 0
    slowest := ""
    fastest := ""
    slowestRate := -1L
    fastestRate := -1L

    i := 0
    while i < results.Count {
        result := results[i]
        if result.Command == command && !BenchHasNoSources(result) && result.LinesPerSecondTenths >= 0 {
            rates[count] = result.LinesPerSecondTenths
            count = count + 1
            if slowestRate < 0 || result.LinesPerSecondTenths < slowestRate {
                slowestRate = result.LinesPerSecondTenths
                slowest = result.Project
            }

            if fastestRate < 0 || result.LinesPerSecondTenths > fastestRate {
                fastestRate = result.LinesPerSecondTenths
                fastest = result.Project
            }
        }

        i = i + 1
    }

    if count == 0 {
        BenchAppendLine(builder, "- `" + command + "`: no project produced a lines/second rate in this run.")
        return
    }

    BenchAppendLine(
        builder,
        "- `" + command + "` per-project lines/s — median " + BenchRateCell(BenchMedian(rates, count)) + ", slowest `" + slowest + "` at " + BenchRateCell(slowestRate) + ", fastest `" + fastest + "` at " + BenchRateCell(fastestRate) + " (over " + BenchIntText(count) + " measured project rows)."
    )
}

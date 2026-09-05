namespace NSharpLang.NativeComparisonRunner

import System
import System.Collections.Generic
import System.Globalization
import System.IO
import System.Text


// THE NATIVE-COMPARISON RUNNER: `compare` MEASURES, `gate` GUARDS.
//
//   compare --cli <Cli.dll> --repo <root> [--out <dir>] [--trials <n>]
//       Builds the N# kernel program, compiles all twelve Rust/C ports, runs the three languages
//       back to back per workload, and writes results.csv / results.md / raw-stdout.log /
//       raw-stderr.log under `<repo>/artifacts/native-comparison/<yyyy-MM-dd>/`. It exits 0 whenever
//       the plumbing worked: a regression against June is INFORMATION here, not a verdict.
//
//   gate --cli <Cli.dll> --repo <root> [--tolerance 0.20] [--trials <n>] [--print-baseline]
//       Builds and runs the N# kernel program only, compares its twelve medians with
//       `SystemsThroughputBaseline`, and exits 1 if any cell exceeds the tolerance. This is the
//       shape the product gate calls (`tests/scripts/test-all-core.sh`, step 3c), which skips it
//       entirely when `SYSTEMS_BENCH=skip` is set.
//
// WHY THIS IS AN N# PROGRAM AND NOT A SHELL SCRIPT. The obvious spelling of all this is a
// `scripts/bench-native-comparison.sh` beside a `scripts/systems-throughput-baseline.json`. The
// ownership ratchet (`tests/native/ownership-audit`) refuses any NEW non-N# file in the repository,
// so a new `.sh` and a new `.json` are both OWN003 failures — and rightly: a benchmark runner that
// drives the N# compiler is exactly the tooling the dogfood rule exists to move into N#. Runner,
// report writer and both baselines are therefore N# source, and the baselines being N# DATA rather
// than a parsed file also means a malformed baseline is a compile error instead of a runtime
// surprise inside the gate.
//
// WHY BOTH MODES REPLACE THE KERNEL PROGRAM'S `NSharpLang.Runtime.dll`. `nlc build` copies the
// runtime that sits beside the CLI it was launched from (`CompilationReferenceResolverKernels.nl`
// resolves it out of the CLI's own base directory) into the kernel program's output directory. A
// developer CLI is a Debug build, so that copy carries `DebuggableAttribute(DisableOptimizations)`
// — and the JIT then compiles every `SimdReductions` helper the kernels call at MINOPTS. The
// measurement that results is of an unoptimized runtime, not of N# codegen. It was measured on a
// loaded machine, checksum-sum 4096: 3925 ns with the Debug runtime against 1019 ns with the Release
// one, and min-max-delta 4096 down to 772 ns — a 3-4x error, and it lands entirely on the vectorized
// kernels because they are the ones that call into the runtime.
//
// So both modes build `src/NSharpLang.Runtime` at `-c Release` (or take `--runtime <dll>`) and copy
// the result over the kernel program's `NSharpLang.Runtime.dll` AFTER `nlc build` has run — after,
// because the build is what puts the Debug copy there. This is not papering over a product defect:
// the published toolset already packs the runtime with `-c Release` (`scripts/lib/packages.sh`), so
// a user's install is optimized; only a dev CLI's copy is not. `tests/scripts/test-all-core.sh`
// step 3c needs no change either — the runner builds the Release runtime itself, inside whatever
// isolated copy of the tree the gate is running from.
//
// WHY `gate` NEVER TOUCHES `git`. The product gate runs from an rsync copy of the tree that excludes
// `.git/`, so a `git rev-parse` there fails by construction. Only `compare` records a commit, and it
// degrades to `unknown` with a note on stderr rather than failing — a measurement session is still
// worth having when the checkout it came from cannot name itself.
class RunnerOptions {
    Mode: string
    CliPath: string
    RepoRoot: string
    OutDirectory: string
    RuntimePath: string
    Trials: int
    Tolerance: double
    PrintBaseline: bool
    Error: string

    constructor() {
        Mode = ""
        CliPath = ""
        RepoRoot = ""
        OutDirectory = ""
        RuntimePath = ""
        Trials = 0
        Tolerance = DefaultThroughputTolerance()
        PrintBaseline = false
        Error = ""
    }
}

func UsageText(): string {
    compare := "  compare --cli <Cli.dll> --repo <repo root> [--out <dir>] [--trials <n>]"
    compareExtra := "       [--runtime <NSharpLang.Runtime.dll>]"
    gate := "  gate --cli <Cli.dll> --repo <repo root> [--tolerance <fraction>] [--trials <n>]"
    gateExtra := "       [--runtime <NSharpLang.Runtime.dll>] [--print-baseline]"
    return "usage:\n" + compare + "\n" + compareExtra + "\n" + gate + "\n" + gateExtra
}

func ParseOptions(arguments: string[]): RunnerOptions {
    options := new RunnerOptions()
    if arguments.Length < 2 {
        options.Error = "no mode given"
        return options
    }

    mode := arguments[1]
    if mode != "compare" && mode != "gate" {
        options.Error = "unknown mode '" + mode + "'"
        return options
    }
    options.Mode = mode

    index := 2
    while index < arguments.Length {
        argument := arguments[index]
        if argument == "--print-baseline" {
            options.PrintBaseline = true
            index = index + 1
            continue
        }

        if index + 1 >= arguments.Length {
            options.Error = "option '" + argument + "' needs a value"
            return options
        }

        ApplyOption(options, argument, arguments[index + 1])
        if options.Error != "" {
            return options
        }
        index = index + 2
    }

    ValidateOptions(options)
    return options
}

func ApplyOption(options: RunnerOptions, argument: string, value: string) {
    if argument == "--cli" {
        options.CliPath = value
    } else if argument == "--repo" {
        options.RepoRoot = value
    } else if argument == "--out" {
        options.OutDirectory = value
    } else if argument == "--runtime" {
        options.RuntimePath = value
    } else if argument == "--trials" {
        trials := ParseIntOrMissing(value)
        if trials < 1 {
            options.Error = "--trials needs a positive whole number, got '" + value + "'"
            return
        }
        options.Trials = trials
    } else if argument == "--tolerance" {
        tolerance := 0.0
        if !Double.TryParse(value, CultureInfo.InvariantCulture, out tolerance) {
            options.Error = "--tolerance needs a number, got '" + value + "'"
            return
        }
        options.Tolerance = tolerance
    } else {
        options.Error = "unknown option '" + argument + "'"
    }
}

func ValidateOptions(options: RunnerOptions) {
    if options.PrintBaseline && options.Mode != "gate" {
        options.Error = "--print-baseline is only valid with 'gate'"
        return
    }
    if options.CliPath == "" {
        options.Error = "--cli is required"
        return
    }
    if !File.Exists(options.CliPath) {
        options.Error = "--cli does not exist: " + options.CliPath
        return
    }
    if options.RepoRoot == "" {
        options.Error = "--repo is required"
        return
    }
    if !Directory.Exists(options.RepoRoot) {
        options.Error = "--repo does not exist: " + options.RepoRoot
    }
}

// ─── THE N# KERNEL PROGRAM ────────────────────────────────────────────────────────────────────

// The kernel project is `nsharp-kernels`, NOT `nsharp`: the product gate's isolated copy excludes
// every directory named `nsharp/`, so a project under that name would silently vanish from the very
// gate that is supposed to run it.
func KernelProjectDirectory(repoRoot: string): string {
    comparison := Path.Combine(Path.Combine(repoRoot, "benchmarks"), "native-comparison")
    return Path.Combine(comparison, "nsharp-kernels")
}

// Debug output. The kernels are measured as the product build emits them, and `--release` is not
// used until it is shown to change the emitted IL: a configuration that moved the numbers without
// moving the IL would be measuring MSBuild rather than the compiler.
func KernelOutputDirectory(repoRoot: string): string {
    debug := Path.Combine(Path.Combine(KernelProjectDirectory(repoRoot), "bin"), "Debug")
    return Path.Combine(debug, "net10.0")
}

func KernelAssemblyPath(repoRoot: string): string {
    return Path.Combine(KernelOutputDirectory(repoRoot), "NSharpLang.NativeComparison.dll")
}

// `--trials` is a TIMING option, so it is appended only to a timing run. Passing it to `--il-shape`
// would be harmless — the kernel program ignores it there — but it would be recorded in the report's
// command block as though the IL inspection depended on a trial count, which it does not.
func KernelArguments(options: RunnerOptions, extraArguments: string, includeTrials: bool): string {
    text := extraArguments
    if includeTrials && options.Trials > 0 {
        if text != "" {
            text = text + " "
        }
        text = text + "--trials " + options.Trials.ToString()
    }
    return text
}

func KernelBuildArguments(options: RunnerOptions): string {
    project := QuoteArgument(KernelProjectDirectory(options.RepoRoot))
    return QuoteArgument(options.CliPath) + " build --project " + project
}

func KernelRunArguments(options: RunnerOptions, extraArguments: string, includeTrials: bool): string {
    text := QuoteArgument(KernelAssemblyPath(options.RepoRoot))
    arguments := KernelArguments(options, extraArguments, includeTrials)
    if arguments != "" {
        text = text + " " + arguments
    }
    return text
}

func KernelBuildCommand(options: RunnerOptions): string {
    return "dotnet " + KernelBuildArguments(options)
}

func KernelRunCommand(options: RunnerOptions, extraArguments: string, includeTrials: bool): string {
    return "dotnet " + KernelRunArguments(options, extraArguments, includeTrials)
}

func RunKernelProgram(options: RunnerOptions, extraArguments: string, includeTrials: bool): ProcessRun {
    arguments := KernelRunArguments(options, extraArguments, includeTrials)
    return RunProcess("dotnet", arguments, options.RepoRoot)
}

// The optimized runtime to measure against: either the one `--runtime` named, or one this runner
// builds. `Error` is empty on success.
class RuntimeChoice {
    Path: string
    Error: string

    constructor(path: string, error: string) {
        Path = path
        Error = error
    }
}

func RuntimeProjectDirectory(repoRoot: string): string {
    return Path.Combine(Path.Combine(repoRoot, "src"), "NSharpLang.Runtime")
}

func RuntimeProjectPath(repoRoot: string): string {
    return Path.Combine(RuntimeProjectDirectory(repoRoot), "NSharpLang.Runtime.csproj")
}

func RuntimeReleaseAssembly(repoRoot: string): string {
    release := Path.Combine(Path.Combine(RuntimeProjectDirectory(repoRoot), "bin"), "Release")
    return Path.Combine(Path.Combine(release, "net10.0"), "NSharpLang.Runtime.dll")
}

// `--disable-build-servers -nr:false` keeps this from leaving MSBuild node processes behind in a
// gate that may be running from a directory the gate deletes afterwards.
func RuntimeBuildArguments(repoRoot: string): string {
    project := QuoteArgument(RuntimeProjectPath(repoRoot))
    return "build --disable-build-servers -nr:false " + project + " -c Release -v q"
}

func ResolveRuntime(options: RunnerOptions): RuntimeChoice {
    if options.RuntimePath != "" {
        if !File.Exists(options.RuntimePath) {
            return new RuntimeChoice("", "--runtime does not exist: " + options.RuntimePath)
        }
        return new RuntimeChoice(options.RuntimePath, "")
    }

    arguments := RuntimeBuildArguments(options.RepoRoot)
    print "dotnet " + arguments
    build := RunProcess("dotnet", arguments, options.RepoRoot)
    if !build.Succeeded() {
        message := "Building the Release NSharpLang.Runtime failed: " + build.FailureReason()
        message = AppendOutput(message, build.Stdout)
        message = AppendOutput(message, build.Stderr)
        return new RuntimeChoice("", message)
    }

    assembly := RuntimeReleaseAssembly(options.RepoRoot)
    if !File.Exists(assembly) {
        return new RuntimeChoice("", "The Release runtime built but its assembly was not at " + assembly)
    }

    return new RuntimeChoice(assembly, "")
}

// `File.ReadAllBytes(...).Length` rather than a `FileInfo`: `new FileInfo(path)` declines on this
// emit path at `emit.local.initializer`, and the runtime assembly is a few tens of kilobytes.
func FileSizeBytes(path: string): long {
    bytes := File.ReadAllBytes(path)
    return Convert.ToInt64(bytes.Length)
}

// Overwrite the Debug runtime that `nlc build` just copied beside the kernel program. Must run
// AFTER the build, because the build is what puts the unoptimized copy there.
func InstallRuntime(repoRoot: string, runtimeAssembly: string): string {
    if !File.Exists(runtimeAssembly) {
        return "The runtime assembly to install was not found: " + runtimeAssembly
    }

    destination := Path.Combine(KernelOutputDirectory(repoRoot), "NSharpLang.Runtime.dll")
    try {
        File.Copy(runtimeAssembly, destination, true)
    } catch error: Exception {
        return "Could not install the runtime over " + destination + ": " + error.Message
    }

    return ""
}

// Build the kernel program, confirm the assembly landed, and put the optimized runtime beside it.
// Returns "" on success, and the whole message to print on failure — including the build's own
// output, because a decline from the columnar backend names its site there and nowhere else.
func PrepareKernelProgram(options: RunnerOptions, runtimeAssembly: string): string {
    build := RunProcess("dotnet", KernelBuildArguments(options), options.RepoRoot)
    if !build.Succeeded() {
        message := "Building the N# kernel program failed: " + build.FailureReason()
        message = AppendOutput(message, build.Stdout)
        message = AppendOutput(message, build.Stderr)
        return message
    }

    assembly := KernelAssemblyPath(options.RepoRoot)
    if !File.Exists(assembly) {
        return "The N# kernel program built but its assembly was not at " + assembly
    }

    return InstallRuntime(options.RepoRoot, runtimeAssembly)
}

func AppendOutput(message: string, output: string): string {
    if output.Trim() == "" {
        return message
    }
    return message + "\n" + output.TrimEnd()
}

// ─── ENVIRONMENT CAPTURE ──────────────────────────────────────────────────────────────────────

func ProbeFirstLine(fileName: string, arguments: string, workingDirectory: string): string {
    run := RunProcess(fileName, arguments, workingDirectory)
    if !run.Succeeded() {
        return "unknown"
    }
    lines := SplitLines(run.Stdout)
    for i := 0; i < lines.Length; i++ {
        line := lines[i].Trim()
        if line != "" {
            return line
        }
    }
    return "unknown"
}

func LoadAverageText(): string {
    return ProbeFirstLine("sysctl", "-n vm.loadavg", Path.GetTempPath())
}

func CoreCountText(): string {
    return ProbeFirstLine("sysctl", "-n hw.ncpu", Path.GetTempPath())
}

// `sysctl -n vm.loadavg` answers `{ 25.30 22.10 20.05 }`; the one-minute figure is the first number
// in it. Returns the missing sentinel when the answer is not that shape.
func ParseOneMinuteLoad(text: string): double {
    flattened := text.Replace("{", " ").Replace("}", " ")
    tokens := SignificantTokens(flattened)
    for i := 0; i < tokens.Count; i++ {
        value := ParseDoubleOrMissing(tokens[i])
        if value >= 0.0 {
            return value
        }
    }
    return MissingNumber()
}

func CaptureEnvironment(options: RunnerOptions, rustCompiler: string): RunEnvironment {
    environment := new RunEnvironment()
    environment.TimestampUtc = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    ApplyCommit(environment, options.RepoRoot)
    environment.CpuBrand = ProbeFirstLine("sysctl", "-n machdep.cpu.brand_string", options.RepoRoot)
    environment.Architecture = ProbeFirstLine("uname", "-m", options.RepoRoot)
    environment.CoreCount = CoreCountText()
    environment.LoadAverage = LoadAverageText()
    environment.DotnetVersion = ProbeFirstLine("dotnet", "--version", options.RepoRoot)
    environment.RustcVersion = ProbeFirstLine(rustCompiler, "--version", options.RepoRoot)
    environment.ClangVersion = ProbeFirstLine(ClangCompiler(), "--version", options.RepoRoot)
    return environment
}

func ApplyCommit(environment: RunEnvironment, repoRoot: string) {
    prefix := "-C " + QuoteArgument(repoRoot) + " rev-parse "
    full := RunProcess("git", prefix + "HEAD", repoRoot)
    short := RunProcess("git", prefix + "--short HEAD", repoRoot)
    if full.Succeeded() && short.Succeeded() {
        environment.CommitFull = full.Stdout.Trim()
        environment.CommitShort = short.Stdout.Trim()
        return
    }
    Console.Error.WriteLine("note: git could not name the commit; recording it as 'unknown'.")
}

// ─── MODE: compare ────────────────────────────────────────────────────────────────────────────

// One `compare` run in progress: what it was asked to do, the binaries it built, and what it has
// collected so far. Gathered into one object so that the measurement loop and the per-child reader
// take a session rather than five parallel arguments.
class CompareSession {
    Options: RunnerOptions
    PortSet: NativePortSet
    TemporaryDirectory: string
    Measurements: List<Measurement>
    Captures: List<RunCapture>

    constructor(options: RunnerOptions, portSet: NativePortSet, temporaryDirectory: string) {
        Options = options
        PortSet = portSet
        TemporaryDirectory = temporaryDirectory
        Measurements = new List<Measurement>()
        Captures = new List<RunCapture>()
    }
}

func DefaultOutputDirectory(repoRoot: string): string {
    artifacts := Path.Combine(Path.Combine(repoRoot, "artifacts"), "native-comparison")
    return Path.Combine(artifacts, DateTime.UtcNow.ToString("yyyy-MM-dd"))
}

func TemporaryBinaryDirectory(): string {
    name := "nsharp-native-comparison-" + DateTime.UtcNow.Ticks.ToString()
    return Path.Combine(Path.GetTempPath(), name)
}

func RemoveDirectoryQuietly(directory: string) {
    try {
        if Directory.Exists(directory) {
            Directory.Delete(directory, true)
        }
    } catch error: Exception {
        Console.Error.WriteLine("note: could not remove " + directory + ": " + error.Message)
    }
}

func TrialsLabel(options: RunnerOptions): string {
    if options.Trials > 0 {
        return options.Trials.ToString() + " (--trials)"
    }
    return "kernel default"
}

func RunCompare(options: RunnerOptions): int {
    outputDirectory := options.OutDirectory
    if outputDirectory == "" {
        outputDirectory = DefaultOutputDirectory(options.RepoRoot)
    }

    runtime := ResolveRuntime(options)
    if runtime.Error != "" {
        Console.Error.WriteLine(runtime.Error)
        return 1
    }

    rustCompiler := ResolveRustCompiler()
    environment := CaptureEnvironment(options, rustCompiler)
    environment.RuntimePath = runtime.Path
    environment.RuntimeSizeBytes = FileSizeBytes(runtime.Path)
    banner := "native-comparison: " + environment.CpuBrand
    banner = banner + ", load average " + environment.LoadAverage
    banner = banner + ", commit " + environment.CommitShort
    print banner
    print "runtime: " + runtime.Path

    buildFailure := PrepareKernelProgram(options, runtime.Path)
    if buildFailure != "" {
        Console.Error.WriteLine(buildFailure)
        return 1
    }

    ilShapeRun := RunKernelProgram(options, "--il-shape", false)
    if !ilShapeRun.Succeeded() {
        reason := "The kernel program's --il-shape run failed: " + ilShapeRun.FailureReason()
        Console.Error.WriteLine(AppendOutput(reason, ilShapeRun.Stderr))
        return 1
    }
    ilShapes := ParseIlShapeLines(ilShapeRun.Stdout)

    temporaryDirectory := TemporaryBinaryDirectory()
    Directory.CreateDirectory(temporaryDirectory)
    portSet := CompileNativePorts(options.RepoRoot, temporaryDirectory)
    if portSet.Error != "" {
        Console.Error.WriteLine(portSet.Error)
        RemoveDirectoryQuietly(temporaryDirectory)
        return 1
    }

    // Recorded before the binaries are removed, because these strings are what the report quotes as
    // "the commands this run issued".
    commands := CompareCommands(options, portSet, temporaryDirectory)

    session := new CompareSession(options, portSet, temporaryDirectory)
    measured := MeasureAllWorkloads(session)
    RemoveDirectoryQuietly(temporaryDirectory)
    if !measured {
        return 1
    }

    measurements := session.Measurements
    missing := MissingCells(measurements)
    if missing.Count > 0 {
        Console.Error.WriteLine("The run did not produce every cell:")
        for i := 0; i < missing.Count; i++ {
            Console.Error.WriteLine("  " + missing[i])
        }
        return 1
    }

    report := new ReportData()
    report.Environment = environment
    report.Measurements = measurements
    report.IlShapes = ilShapes
    report.Commands = commands
    report.TrialsLabel = TrialsLabel(options)
    report.Captures = session.Captures

    Directory.CreateDirectory(outputDirectory)
    WriteReportFile(outputDirectory, "results.csv", BuildResultsCsv(measurements))
    WriteReportFile(outputDirectory, "results.md", BuildResultsMarkdown(report))
    WriteReportFile(outputDirectory, "raw-stdout.log", BuildRawLog(report.Captures, false))
    WriteReportFile(outputDirectory, "raw-stderr.log", BuildRawLog(report.Captures, true))

    print ""
    print BuildComparisonTable(measurements, ilShapes).TrimEnd()
    print ""
    PrintRegressionSummary(measurements)
    print "Wrote results.csv, results.md, raw-stdout.log and raw-stderr.log to " + outputDirectory
    return 0
}

func WriteReportFile(outputDirectory: string, fileName: string, text: string) {
    File.WriteAllText(Path.Combine(outputDirectory, fileName), text)
}

// N#, then Rust, then C, one workload at a time — back to back so the three share as close to the
// same machine state as a sequential run allows.
func MeasureAllWorkloads(session: CompareSession): bool {
    workloads := WorkloadKeys()

    for i := 0; i < workloads.Length; i++ {
        workload := workloads[i]
        print "measuring " + workload + " ..."

        only := "--only " + workload
        nsharpRun := RunKernelProgram(session.Options, only, true)
        nsharpCommand := KernelRunCommand(session.Options, only, true)
        if !CollectRun(session, NsharpLanguageKey(), workload, nsharpRun, nsharpCommand) {
            return false
        }

        port := session.PortSet.Ports[IndexOfNativePort(session.PortSet.Ports, workload)]

        rustRun := RunProcess(port.RustBinary, "", session.TemporaryDirectory)
        if !CollectRun(session, RustLanguageKey(), workload, rustRun, port.RustBinary) {
            return false
        }

        cRun := RunProcess(port.CBinary, "", session.TemporaryDirectory)
        if !CollectRun(session, CLanguageKey(), workload, cRun, port.CBinary) {
            return false
        }
    }

    return true
}

// Record one child's output, or explain why the run is unusable. A non-zero exit, or a stdout that
// does not carry both sizes, stops `compare`: a table with a silently absent cell is worse than no
// table, because it looks complete.
func CollectRun(session: CompareSession, language: string, workload: string, run: ProcessRun, command: string): bool {
    if !run.Succeeded() {
        reason := command + " failed: " + run.FailureReason()
        Console.Error.WriteLine(AppendOutput(reason, run.Stderr))
        return false
    }

    parsed := ParseMeasurementLines(language, run.Stdout)
    ApplyStabilityLines(parsed, language, run.Stderr)

    sizes := BenchmarkSizes()
    for i := 0; i < sizes.Length; i++ {
        if IndexOfMeasurement(parsed, workload, sizes[i], language) < 0 {
            expected := workload + " " + sizes[i].ToString() + " <ns>"
            reason := command + " printed no '" + expected + "' line on stdout."
            Console.Error.WriteLine(AppendOutput(reason, run.Stdout))
            return false
        }
    }

    for i := 0; i < parsed.Count; i++ {
        entry := parsed[i]
        if entry.Workload == workload {
            session.Measurements.Add(entry)
        }
    }

    session.Captures.Add(new RunCapture(language, workload, run.Stdout, run.Stderr))
    return true
}

func MissingCells(measurements: List<Measurement>): List<string> {
    missing := new List<string>()
    workloads := WorkloadKeys()
    sizes := BenchmarkSizes()
    languages := ReportLanguages()

    for w := 0; w < workloads.Length; w++ {
        for s := 0; s < sizes.Length; s++ {
            for l := 0; l < languages.Length; l++ {
                if IndexOfMeasurement(measurements, workloads[w], sizes[s], languages[l]) < 0 {
                    cell := workloads[w] + " " + sizes[s].ToString() + " " + languages[l]
                    missing.Add(cell)
                }
            }
        }
    }

    return missing
}

func PrintRegressionSummary(measurements: List<Measurement>) {
    notices := RegressionNotices(measurements)
    if notices.Count == 0 {
        flag := FormatRatio(JuneRegressionFlagRatio())
        print "No workload regressed past " + flag + " of its June N# median."
        return
    }
    for i := 0; i < notices.Count; i++ {
        print notices[i]
    }
}

// The commands this run actually issued, recorded verbatim for the report's header block. The first
// workload stands in for all six; the others differ only in the key.
func CompareCommands(options: RunnerOptions, portSet: NativePortSet, temporaryDirectory: string): List<string> {
    first := WorkloadKeys()[0]
    rustArguments := RustCompileArguments(options.RepoRoot, temporaryDirectory, first)
    clangArguments := ClangCompileArguments(options.RepoRoot, temporaryDirectory, first)

    commands := new List<string>()
    commands.Add("dotnet " + RuntimeBuildArguments(options.RepoRoot))
    commands.Add(KernelBuildCommand(options))
    commands.Add("cp " + RuntimeReleaseAssembly(options.RepoRoot) + " " + Path.Combine(KernelOutputDirectory(options.RepoRoot), "NSharpLang.Runtime.dll"))
    commands.Add(KernelRunCommand(options, "--il-shape", false))
    commands.Add(KernelRunCommand(options, "--only " + first, true))
    commands.Add(portSet.RustCompiler + " " + rustArguments)
    commands.Add(RustBinaryPath(temporaryDirectory, first))
    commands.Add(ClangCompiler() + " " + clangArguments)
    commands.Add(CBinaryPath(temporaryDirectory, first))
    return commands
}

// ─── MODE: gate ───────────────────────────────────────────────────────────────────────────────

func RunGate(options: RunnerOptions): int {
    // Read before the runtime build, so the figure describes the machine the medians were taken on
    // rather than the machine after this runner has finished loading it.
    loadAverage := LoadAverageText()
    coreCount := CoreCountText()

    runtime := ResolveRuntime(options)
    if runtime.Error != "" {
        Console.Error.WriteLine(runtime.Error)
        return 1
    }

    header := "systems throughput gate: load average " + loadAverage
    header = header + ", " + coreCount + " cores, runtime " + runtime.Path
    print header
    WarnOnLoad(loadAverage, coreCount)

    buildFailure := PrepareKernelProgram(options, runtime.Path)
    if buildFailure != "" {
        Console.Error.WriteLine(buildFailure)
        return 1
    }

    run := RunKernelProgram(options, "", true)
    if !run.Succeeded() {
        reason := KernelRunCommand(options, "", true) + " failed: " + run.FailureReason()
        Console.Error.WriteLine(AppendOutput(reason, run.Stderr))
        return 1
    }

    measurements := ParseMeasurementLines(NsharpLanguageKey(), run.Stdout)
    ApplyStabilityLines(measurements, NsharpLanguageKey(), run.Stderr)
    return ReportGate(options, measurements)
}

func WarnOnLoad(loadAverage: string, coreCount: string) {
    oneMinuteLoad := ParseOneMinuteLoad(loadAverage)
    cores := ParseDoubleOrMissing(coreCount)
    if oneMinuteLoad >= 0.0 && cores > 0.0 && oneMinuteLoad > cores {
        print "warning: the one-minute load average exceeds the core count; medians may be inflated."
    }
}

func GateTableHeader(): string {
    names := new List<string>()
    names.Add("workload")
    names.Add("size")
    names.Add("baseline ns")
    names.Add("measured ns")
    names.Add("ratio")
    names.Add("status")

    alignments := new List<string>()
    alignments.Add("---")
    alignments.Add("---:")
    alignments.Add("---:")
    alignments.Add("---:")
    alignments.Add("---:")
    alignments.Add("---")

    return MarkdownRow(names) + "\n" + MarkdownRow(alignments)
}

func GateRow(workload: string, size: int, baseline: string, measured: string, ratio: string, status: string): string {
    cells := new List<string>()
    cells.Add(workload)
    cells.Add(size.ToString())
    cells.Add(baseline)
    cells.Add(measured)
    cells.Add(ratio)
    cells.Add(status)
    return MarkdownRow(cells)
}

func ReportGate(options: RunnerOptions, measurements: List<Measurement>): int {
    baseline := ThroughputBaselineRows()
    failures := 0
    cells := 0

    print ""
    print GateTableHeader()

    for i := 0; i < baseline.Count; i++ {
        row := baseline[i]
        cells = cells + 1
        index := IndexOfMeasurement(measurements, row.Workload, row.Size, NsharpLanguageKey())
        if index < 0 {
            failures = failures + 1
            baselineNs := FormatNanoseconds(row.MedianNs)
            print GateRow(row.Workload, row.Size, baselineNs, "n/a", "n/a", "MISSING MEASUREMENT")
            continue
        }

        measured := measurements[index].MedianNs
        ratio := SafeRatio(measured, row.MedianNs)
        status := "ok"
        if ratio < 0.0 || ratio > 1.0 + options.Tolerance {
            status = "FAIL"
            failures = failures + 1
        }
        baselineNs := FormatNanoseconds(row.MedianNs)
        measuredNs := FormatNanoseconds(measured)
        print GateRow(row.Workload, row.Size, baselineNs, measuredNs, FormatRatio(ratio), status)
    }

    // A measured cell the baseline does not name is a failure too: the twelve rows are a contract,
    // and a workload that appears without a baseline has never been held to one.
    for i := 0; i < measurements.Count; i++ {
        entry := measurements[i]
        if IndexOfThroughputBaselineRow(baseline, entry.Workload, entry.Size) < 0 {
            cells = cells + 1
            failures = failures + 1
            measuredNs := FormatNanoseconds(entry.MedianNs)
            print GateRow(entry.Workload, entry.Size, "n/a", measuredNs, "n/a", "MISSING BASELINE")
        }
    }

    print ""
    PrintGateSummary(options, cells, failures)

    if options.PrintBaseline {
        print ""
        print "Paste-ready SystemsThroughputBaseline.nl rows for this run:"
        print ""
        print BuildBaselineBlock(measurements).TrimEnd()
    }

    if failures > 0 {
        return 1
    }
    return 0
}

func PrintGateSummary(options: RunnerOptions, cells: int, failures: int) {
    verdict := "PASS"
    if failures > 0 {
        verdict = "FAIL"
    }
    summary := verdict + ": " + cells.ToString() + " cells, " + failures.ToString() + " failed"
    summary = summary + ", tolerance " + FormatRatio(1.0 + options.Tolerance)
    summary = summary + ", baseline " + ThroughputBaselineOrigin() + "."
    print summary
}

// The measured medians as the exact `rows.Add(...)` lines of `SystemsThroughputBaseline.nl`, so
// refreshing the baseline is a paste rather than twelve hand edits.
func BuildBaselineBlock(measurements: List<Measurement>): string {
    builder := new StringBuilder()
    workloads := WorkloadKeys()
    sizes := BenchmarkSizes()

    for w := 0; w < workloads.Length; w++ {
        for s := 0; s < sizes.Length; s++ {
            index := IndexOfMeasurement(measurements, workloads[w], sizes[s], NsharpLanguageKey())
            if index < 0 {
                continue
            }
            median := FormatNanoseconds(measurements[index].MedianNs)
            arguments := "\"" + workloads[w] + "\", " + sizes[s].ToString() + ", " + median
            builder.AppendLine("    rows.Add(new ThroughputBaselineRow(" + arguments + "))")
        }
    }

    return builder.ToString()
}

// ─── ENTRY POINT ──────────────────────────────────────────────────────────────────────────────

func main(): void {
    options := ParseOptions(Environment.GetCommandLineArgs())
    if options.Error != "" {
        Console.Error.WriteLine("error: " + options.Error)
        Console.Error.WriteLine(UsageText())
        Environment.Exit(2)
        return
    }

    if options.Mode == "compare" {
        Environment.Exit(RunCompare(options))
        return
    }

    Environment.Exit(RunGate(options))
}

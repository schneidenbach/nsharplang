namespace NSharpLang.SystemsProofCorpus.Tests

import System
import System.Diagnostics
import System.IO
import System.Text.Json


// THE EXECUTABLE SYSTEMS PROOF CORPUS, IN N#.
//
// These replace the first tranche of `tests/SystemsNSharpTests.cs`: the single 544-line `[Fact]`
// `ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence`, whose 212 in-body `Assert.`
// calls plus 42 rows inside `AssertSystemsProofBuildDiagnostics` and 12 inside
// `AssertNativeImportHasNoManagedBody` make 266 decoded claim rows over the 21 shipped proof
// projects under `docs/design/systems-samples/proofs`.
//
// WHY THIS TRANCHE AND NOT THE BIGGER ONE. The mechanical decode splits the C# file six ways by
// what the bodies READ: 52 methods (996 declaration lines) analyse source in memory, 4 drive the
// CLI in process, 2 read the parser's AST, 1 reads `Result<,>` by reflection, 1 walks the gauntlet
// fixtures — and exactly ONE, this one, builds projects and LAUNCHES PROCESSES. Task 020 asks for
// a missing native-test capability consumed immediately by a real cluster; this is the only
// tranche in the file that needs one.
//
// THE CAPABILITY IS A SYNCHRONOUS SPAWN KERNEL, and `RunProcess` below is all of it: one
// `ProcessStartInfo`, one `Process`, `Start`, `StandardOutput.ReadToEnd`, `StandardError.ReadToEnd`,
// `WaitForExit`, `ExitCode`, `Dispose`. It is synchronous by necessity — `Task.Run`, `Stopwatch`
// and `TickCount64` all decline on this emit path — and it terminates every child it starts.
//
// WHAT CHANGED ABOUT THE ROUTE, AND WHY IT IS STRONGER. The deleted body never spelled a process
// API: `Process`, `ProcessStartInfo`, `StandardOutput` and `WaitForExit` occur ZERO times in it,
// and its 11 launches all went through `DotnetRunner.Run`, which is already N#-owned. Its
// "real build", meanwhile, was IN-PROCESS — `new MultiFileCompiler(...).CompileToIlAssembly(...)`
// — and the perf-report JSON its 25 `JsonDocument.Parse` calls read was assembled by a private
// helper IN THE TEST FILE (`BuildSystemsProofPerfReportJson`), not by the shipping CLI. Every
// block below instead spawns the real `nlc build --perf-report`, `nlc check --systems-report` and
// `nlc query trusted`, so the pinned envelopes are the ones a user sees.
//
// WHY NOTHING IS LOADED. `AssertNativeImportHasNoManagedBody` opened each emitted assembly in an
// `AssemblyLoadContext` and read `GetMethodBody()`. That is the reflection-loading debt the AOT
// single-binary end state forbids, so it is not carried here. The emitted assemblies are EXECUTED
// AS PROCESSES instead, and the two native-import proofs answer the same question more directly —
// see the `26-native-device-handle` and `27-c-library-cli` run blocks.
//
// PE METADATA IS UNREACHABLE FROM N#, MEASURED. `System.Reflection.Metadata` resolves as a
// `nuget:` dependency, but `new PEReader(stream)` declines at `emit.local.initializer`, the two
// `PEStreamOptions` arities decline identically, and even `(int)PEStreamOptions.PrefetchEntireImage`
// declines at `emit.return.expression` — `nuget:`-sourced types are reflection-only on this emit
// path. That is why route (a), execution, is the answer rather than a metadata read.
//
// NO REGULAR EXPRESSIONS. The C# stripped ANSI with `Regex.Replace` and counted `-- WARNING` with
// `Regex.Matches`. `Regex` construction and the static `Regex.IsMatch` both decline here, so the
// census is counted by ordinal `IndexOf`; the ANSI wrapper sits outside the marker text and does
// not disturb it, which the diagnostic censuses below prove on all 21 projects.


// ─── THE SPAWN KERNEL ─────────────────────────────────────────────────────────────────────────

class ProofRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

// Start a child process, drain BOTH pipes to completion, wait for it, and dispose it. Draining
// before waiting is what keeps a chatty child from deadlocking against a full pipe buffer, and the
// `Dispose` is what guarantees this project leaves no orphan `dotnet` process behind.
func RunProcess(fileName: string, arguments: string, workingDirectory: string): ProofRun {
    startInfo := new ProcessStartInfo { FileName: fileName, Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdout := process.StandardOutput.ReadToEnd()
    stderr := process.StandardError.ReadToEnd()
    process.WaitForExit()
    exitCode := process.ExitCode
    process.Dispose()
    return new ProofRun(exitCode, stdout, stderr)
}


// ─── THE CORPUS ON DISK ───────────────────────────────────────────────────────────────────────

// The repository root, found by walking up from the directory this test assembly was loaded into
// (which is the CLI's own directory, because `nlc test` hosts the emitted tests in its process).
func ProofRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln"))
            && Directory.Exists(Path.Combine(directory, "src"))
            && Directory.Exists(Path.Combine(directory, "docs")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the repository root above this test tree.")
}

func ProofCliDll(): string {
    root := ProofRepositoryRoot()
    binDirectory := Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug")
    cliDll := Path.Combine(Path.Combine(binDirectory, "net10.0"), "Cli.dll")
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The built N# CLI was not found beside the repository root.")
    }

    return cliDll
}

func ProofDirectory(name: string): string {
    root := ProofRepositoryRoot()
    proofs := Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "docs"), "design"), "systems-samples"), "proofs")
    directory := Path.Combine(proofs, name)
    if !Directory.Exists(directory) {
        throw new InvalidOperationException("The shipped systems proof project was not on disk.")
    }

    return directory
}

func ProofOutputDirectory(name: string): string {
    return Path.Combine(Path.Combine(Path.Combine(ProofDirectory(name), "bin"), "Debug"), "net10.0")
}


// ─── THE THREE CLI ENTRY POINTS, EACH A REAL PROCESS ──────────────────────────────────────────

func BuildProof(name: string): ProofRun {
    return RunProcess("dotnet", "\"" + ProofCliDll() + "\" build --project \"" + ProofDirectory(name) + "\" --perf-report", Path.GetTempPath())
}

func CheckProof(name: string): ProofRun {
    return RunProcess("dotnet", "\"" + ProofCliDll() + "\" check --project \"" + ProofDirectory(name) + "\" --systems-report", Path.GetTempPath())
}

func QueryTrustedProof(name: string): ProofRun {
    return RunProcess("dotnet", "\"" + ProofCliDll() + "\" query trusted --project \"" + ProofDirectory(name) + "\"", Path.GetTempPath())
}

// The emitted assembly, executed AS A PROCESS from its own output directory — route (a) of the AOT
// question, and the reason nothing here calls `Assembly.Load`.
func RunProofAssembly(name: string, assemblyName: string): ProofRun {
    outputDirectory := ProofOutputDirectory(name)
    return RunProcess("dotnet", "\"" + Path.Combine(outputDirectory, assemblyName + ".dll") + "\"", outputDirectory)
}

// A probe project written under the system temp directory and checked by the REAL CLI. It exists
// because the corpus has no shipped sample for a shape the compiler must REFUSE — a refused shape
// cannot also be a shipped sample — and a refusal pinned only inside the analyzer's own contracts
// would not say that `nlc check` fails the build over it.
func WriteNativeImportProbe(folderName: string, parameterSpelling: string): string {
    directory := Path.Combine(Path.GetTempPath(), folderName)
    if Directory.Exists(directory) {
        Directory.Delete(directory, true)
    }

    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "project.yml"), "name: NativeImportProbe\nversion: 0.1.0\ntargetFramework: net10.0\noutputType: exe\nentry: Program.nl\n")
    File.WriteAllText(Path.Combine(directory, "Program.nl"), "namespace Probe.NativeImport\n\nimport System\nimport System.Runtime.InteropServices\n\nstatic class NativeHash {\n    [LibraryImport(\"fast_hash\")]\n    static func Hash64(data: " + parameterSpelling + ", len: int, out value: ulong): int\n}\n\nfunc Main() {\n    Console.WriteLine(0)\n}\n")
    return directory
}

func CheckProjectJson(directory: string): ProofRun {
    return RunProcess("dotnet", "\"" + ProofCliDll() + "\" check --project \"" + directory + "\" --json", Path.GetTempPath())
}

// `assembly=<bool> runtime=<bool>` — the two artifacts the deleted body checked with `File.Exists`.
func ProofArtifacts(name: string, assemblyName: string): string {
    outputDirectory := ProofOutputDirectory(name)
    return "assembly=" + BoolText(File.Exists(Path.Combine(outputDirectory, assemblyName + ".dll")))
        + " runtime=" + BoolText(File.Exists(Path.Combine(outputDirectory, "NSharpLang.Runtime.dll")))
}


// ─── THE TEXT KERNELS ─────────────────────────────────────────────────────────────────────────

func BoolText(value: bool): string {
    if value {
        return "true"
    }

    return "false"
}

func IntText(value: int): string {
    return value.ToString() ?? ""
}

func CountOccurrences(text: string, needle: string): int {
    count := 0
    index := text.IndexOf(needle, StringComparison.Ordinal)
    while index >= 0 {
        count = count + 1
        index = text.IndexOf(needle, index + needle.Length, StringComparison.Ordinal)
    }

    return count
}

// `errors=<n> warnings=<n>` over the CLI's own diagnostic banners. The C# asserted only that
// `-- ERROR` was absent and that `-- WARNING` occurred N times; stating both halves as one row
// makes an unexpected error a named failure rather than a silent one.
func DiagnosticCensus(stderr: string): string {
    return "errors=" + IntText(CountOccurrences(stderr, "-- ERROR"))
        + " warnings=" + IntText(CountOccurrences(stderr, "-- WARNING"))
}


// ─── THE ENVELOPE READERS ─────────────────────────────────────────────────────────────────────

func ArrayCount(element: JsonElement, name: string): int {
    return element.GetProperty(name).GetArrayLength()
}

func ElementAt(element: JsonElement, name: string, index: int): JsonElement {
    position := 0
    enumerator := element.GetProperty(name).EnumerateArray()
    while enumerator.MoveNext() {
        if position == index {
            return enumerator.Current
        }

        position = position + 1
    }

    throw new InvalidOperationException("The requested array element was not present in the envelope.")
}

func Text(element: JsonElement, name: string): string {
    return element.GetProperty(name).GetString() ?? "<null>"
}

func Flag(element: JsonElement, name: string): string {
    return BoolText(element.GetProperty(name).GetBoolean())
}

// `<schemaVersion>|<command>|<ok>` — the versioned envelope every `nlc build --perf-report` writes.
func BuildEnvelope(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    root := document.RootElement
    row := IntText(root.GetProperty("schemaVersion").GetInt32()) + "|" + Text(root, "command") + "|" + Flag(root, "ok")
    document.Dispose()
    return row
}

// EVERY perf-report array, counted. The deleted body checked between two and seven of the eleven
// arrays per project and never said what the others held; this states the whole census, so a site
// appearing where the C# was not looking is a named failure.
func PerfCensus(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    perf := document.RootElement.GetProperty("perfReport")
    row := "allocationSites=" + IntText(ArrayCount(perf, "allocationSites"))
        + " delegateSites=" + IntText(ArrayCount(perf, "delegateSites"))
        + " boxingSites=" + IntText(ArrayCount(perf, "boxingSites"))
        + " dispatchSites=" + IntText(ArrayCount(perf, "dispatchSites"))
        + " closureCaptures=" + IntText(ArrayCount(perf, "closureCaptures"))
        + " poolSites=" + IntText(ArrayCount(perf, "poolSites"))
        + " resourceSites=" + IntText(ArrayCount(perf, "resourceSites"))
        + " boundaryLeakSites=" + IntText(ArrayCount(perf, "boundaryLeakSites"))
        + " hotReadinessSites=" + IntText(ArrayCount(perf, "hotReadinessSites"))
        + " implicitTrapSites=" + IntText(ArrayCount(perf, "implicitTrapSites"))
        + " trustedSites=" + IntText(ArrayCount(perf, "trustedSites"))
    document.Dispose()
    return row
}

// `<code>|<effect>|<function>` for one effect site.
func PerfSiteRow(stdout: string, arrayName: string, index: int): string {
    document := JsonDocument.Parse(stdout)
    site := ElementAt(document.RootElement.GetProperty("perfReport"), arrayName, index)
    row := Text(site, "code") + "|" + Text(site, "effect") + "|" + Text(site, "function")
    document.Dispose()
    return row
}

// `<function>|<owner>|<review>|<expires>|<hasUnsafe>` for one trusted site. `review` and `expires`
// are pinned here although the C# read neither from a build.
func PerfTrustedRow(stdout: string, index: int): string {
    document := JsonDocument.Parse(stdout)
    site := ElementAt(document.RootElement.GetProperty("perfReport"), "trustedSites", index)
    row := Text(site, "function") + "|" + Text(site, "owner") + "|" + Text(site, "review")
        + "|" + Text(site, "expires") + "|" + Flag(site, "hasUnsafe")
    document.Dispose()
    return row
}

// `<schemaVersion>|<command>|<ok>|errors=<n>|warnings=<n>|info=<n>` from `nlc check --systems-report`.
func CheckEnvelope(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    root := document.RootElement
    summary := root.GetProperty("summary")
    row := IntText(root.GetProperty("schemaVersion").GetInt32()) + "|" + Text(root, "command") + "|" + Flag(root, "ok")
        + "|errors=" + IntText(summary.GetProperty("errors").GetInt32())
        + "|warnings=" + IntText(summary.GetProperty("warnings").GetInt32())
        + "|info=" + IntText(summary.GetProperty("info").GetInt32())
    document.Dispose()
    return row
}

// `<code>:<severity>@<line>:<column>` for every diagnostic the check envelope carries, joined by
// `|`, or `<empty>`. This REPLACES a structurally vacuous claim: the deleted body asserted
// `string.IsNullOrWhiteSpace(aotCheck.Stderr)`, and `nlc check --systems-report` CANNOT write to
// stderr — every `Console.Error` path in `CheckCommand.Execute` is gated on text mode, which a
// JSON output mode never enters — so that assertion could not fail for its whole life. What the
// warnings ARE is a claim; that they were not on the wrong stream is not.
func CheckDiagnosticCensus(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    row := ""
    enumerator := document.RootElement.GetProperty("diagnostics").EnumerateArray()
    while enumerator.MoveNext() {
        diagnostic := enumerator.Current
        if row != "" {
            row = row + "|"
        }

        row = row + Text(diagnostic, "code") + ":" + Text(diagnostic, "severity")
            + "@" + IntText(diagnostic.GetProperty("line").GetInt32())
            + ":" + IntText(diagnostic.GetProperty("column").GetInt32())
    }

    document.Dispose()
    if row == "" {
        return "<empty>"
    }

    return row
}

// `<target>|<analysis>|<nativeImageEmitted>|<trimSafe>` — the whole AOT block, where the C# read
// two of its four fields.
func AotRow(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    aot := document.RootElement.GetProperty("systemsReport").GetProperty("aot")
    row := Text(aot, "target") + "|" + Text(aot, "analysis") + "|" + Flag(aot, "nativeImageEmitted") + "|" + Flag(aot, "trimSafe")
    document.Dispose()
    return row
}

// Every function the systems report names, in order — the census the C#'s `Single(...)` lookups
// assumed but never stated.
func SystemsFunctionNames(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    row := ""
    enumerator := document.RootElement.GetProperty("systemsReport").GetProperty("functions").EnumerateArray()
    while enumerator.MoveNext() {
        if row != "" {
            row = row + "|"
        }

        row = row + Text(enumerator.Current, "name")
    }

    document.Dispose()
    return row
}

// `isHot|isBoundary|allocates|hasImplicitTrapObligation|usesUnknownExternalCall|aotSafe` for one
// named function.
func SystemsFunctionRow(stdout: string, name: string): string {
    document := JsonDocument.Parse(stdout)
    row := "<absent>"
    enumerator := document.RootElement.GetProperty("systemsReport").GetProperty("functions").EnumerateArray()
    while enumerator.MoveNext() {
        function := enumerator.Current
        if Text(function, "name") == name {
            effects := function.GetProperty("effects")
            row = Flag(function, "isHot") + "|" + Flag(function, "isBoundary")
                + "|" + Flag(effects, "allocates")
                + "|" + Flag(effects, "hasImplicitTrapObligation")
                + "|" + Flag(effects, "usesUnknownExternalCall")
                + "|" + Flag(effects, "aotSafe")
        }
    }

    document.Dispose()
    return row
}

// `<schemaVersion>|<command>|<ok>|results=<n>` from `nlc query trusted`.
func TrustedQueryEnvelope(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    root := document.RootElement
    row := IntText(root.GetProperty("schemaVersion").GetInt32()) + "|" + Text(root, "command") + "|" + Flag(root, "ok")
        + "|results=" + IntText(root.GetProperty("results").GetArrayLength())
    document.Dispose()
    return row
}

// `<function>|<owner>|<review>|<expires>|<hasUnsafe>|<bodyStatementCount>` for one query result.
func TrustedQueryRow(stdout: string, index: int): string {
    document := JsonDocument.Parse(stdout)
    result := ElementAt(document.RootElement, "results", index)
    row := Text(result, "function") + "|" + Text(result, "owner") + "|" + Text(result, "review")
        + "|" + Text(result, "expires") + "|" + Flag(result, "hasUnsafe")
        + "|" + IntText(result.GetProperty("bodyStatementCount").GetInt32())
    document.Dispose()
    return row
}



// ─── THE 21 BUILDS ────────────────────────────────────────────────────────────────────────────
// One block per shipped proof project. Each spawns the real `nlc build --project … --perf-report`,
// pins the versioned envelope, the CLI's own diagnostic census, the WHOLE eleven-array perf
// census, and every site row the census says is there.

test "020 s40 systems proof corpus: 24-zero-copy-frame-reader builds — the perf report is a versioned envelope with a 0-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("24-zero-copy-frame-reader")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=0"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
}

test "020 s40 systems proof corpus: 25-trusted-memory-copy builds — the perf report is a versioned envelope with a 0-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("25-trusted-memory-copy")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=0"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=1"
    assert PerfTrustedRow(build.Stdout, 0) == "CopyExact|runtime-core|2026-12-01|2027-06-01|true"
}

test "020 s40 systems proof corpus: 26-native-device-handle builds — the perf report is a versioned envelope with a 1-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("26-native-device-handle")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=1"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
}

test "020 s40 systems proof corpus: 27-c-library-cli builds — the perf report is a versioned envelope with a 1-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("27-c-library-cli")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=1"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
}

test "020 s40 systems proof corpus: 30-cold-failure-logging builds — the perf report is a versioned envelope with a 2-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("30-cold-failure-logging")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=2"
    assert PerfCensus(build.Stdout) == "allocationSites=1 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert PerfSiteRow(build.Stdout, "allocationSites", 0) == "NSYS001|allocation|LogColdFailure"
}

test "020 s40 systems proof corpus: 31-hot-metrics builds — the perf report is a versioned envelope with a 1-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("31-hot-metrics")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=1"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
}

test "020 s40 systems proof corpus: 32-cache-prewarm builds — the perf report is a versioned envelope with a 1-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("32-cache-prewarm")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=1"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
}

test "020 s40 systems proof corpus: 33-arraypool-file-io builds — the perf report is a versioned envelope with a 2-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("33-arraypool-file-io")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=2"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
}

test "020 s40 systems proof corpus: 34-memorypool-disposal builds — the perf report is a versioned envelope with a 0-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("34-memorypool-disposal")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=0"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
}

test "020 s40 systems proof corpus: 35-async-file-hot-parser builds — the perf report is a versioned envelope with a 4-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("35-async-file-hot-parser")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=4"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=2 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert PerfSiteRow(build.Stdout, "boundaryLeakSites", 0) == "NSYS070|boundaryLeak|ReadAndCount"
    assert PerfSiteRow(build.Stdout, "boundaryLeakSites", 1) == "NSYS070|boundaryLeak|Main"
}

test "020 s40 systems proof corpus: 36-dictionary-setup-hot-read builds — the perf report is a versioned envelope with a 3-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("36-dictionary-setup-hot-read")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=3"
    assert PerfCensus(build.Stdout) == "allocationSites=1 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=1 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert PerfSiteRow(build.Stdout, "allocationSites", 0) == "NSYS001|allocation|BuildCatalog"
    assert PerfSiteRow(build.Stdout, "boundaryLeakSites", 0) == "NSYS070|boundaryLeak|BuildCatalog"
}

test "020 s40 systems proof corpus: 37-fixed-capacity-map builds — the perf report is a versioned envelope with a 1-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("37-fixed-capacity-map")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=1"
    assert PerfCensus(build.Stdout) == "allocationSites=1 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert PerfSiteRow(build.Stdout, "allocationSites", 0) == "NSYS001|allocation|NewMap"
}

test "020 s40 systems proof corpus: 38-unmanaged-sort-comparer builds — the perf report is a versioned envelope with a 1-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("38-unmanaged-sort-comparer")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=1"
    assert PerfCensus(build.Stdout) == "allocationSites=1 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert PerfSiteRow(build.Stdout, "allocationSites", 0) == "NSYS001|allocation|Main"
}

test "020 s40 systems proof corpus: 39-hot-linq-pipeline builds — the perf report is a versioned envelope with a 1-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("39-hot-linq-pipeline")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=1"
    assert PerfCensus(build.Stdout) == "allocationSites=1 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert PerfSiteRow(build.Stdout, "allocationSites", 0) == "NSYS001|allocation|Main"
}

test "020 s40 systems proof corpus: 41-structured-errors builds — the perf report is a versioned envelope with a 0-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("41-structured-errors")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=0"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
}

test "020 s40 systems proof corpus: 42-aot-friendly-public-api builds — the perf report is a versioned envelope with a 2-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("42-aot-friendly-public-api")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=2"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert ProofArtifacts("42-aot-friendly-public-api", "SystemsProof42AotFriendlyPublicApi") == "assembly=true runtime=true"
}

test "020 s40 systems proof corpus: 43-mono-wasm-plugin builds — the perf report is a versioned envelope with a 0-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("43-mono-wasm-plugin")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=0"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
}

test "020 s40 systems proof corpus: 44-ci-allocation-gate builds — the perf report is a versioned envelope with a 2-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("44-ci-allocation-gate")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=2"
    assert PerfCensus(build.Stdout) == "allocationSites=1 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert PerfSiteRow(build.Stdout, "allocationSites", 0) == "NSYS001|allocation|Main"
}

test "020 s40 systems proof corpus: 45-trusted-audit builds — the perf report is a versioned envelope with a 0-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("45-trusted-audit")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=0"
    assert PerfCensus(build.Stdout) == "allocationSites=0 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=1"
    assert PerfTrustedRow(build.Stdout, 0) == "UnsafeAuditSurface.WrapHandle|interop|2026-12-01|2027-06-01|true"
}

test "020 s40 systems proof corpus: 46-dapper-boundary builds — the perf report is a versioned envelope with a 2-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("46-dapper-boundary")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=2"
    assert PerfCensus(build.Stdout) == "allocationSites=2 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert PerfSiteRow(build.Stdout, "allocationSites", 0) == "NSYS001|allocation|LoadFirstUser"
    assert PerfSiteRow(build.Stdout, "allocationSites", 1) == "NSYS001|allocation|Main"
}

test "020 s40 systems proof corpus: 48-effect-drift builds — the perf report is a versioned envelope with a 1-warning census (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("48-effect-drift")

    assert build.ExitCode == 0
    assert BuildEnvelope(build.Stdout) == "1|build|true"
    assert DiagnosticCensus(build.Stderr) == "errors=0 warnings=1"
    assert PerfCensus(build.Stdout) == "allocationSites=1 delegateSites=0 boxingSites=0 dispatchSites=0 closureCaptures=0 poolSites=0 resourceSites=0 boundaryLeakSites=0 hotReadinessSites=0 implicitTrapSites=0 trustedSites=0"
    assert PerfSiteRow(build.Stdout, "allocationSites", 0) == "NSYS001|allocation|Main"
}


// ─── THE 18 RUN BLOCKS: THE 11 THE DELETED BODY MADE, THE TWO NATIVE-IMPORT PROOFS, AND FIVE MORE ─────────────────────────────────────────────────────
// Every emitted assembly is EXECUTED AS A PROCESS from its own output directory. Each proof
// `Main` is self-checking — it returns a distinct nonzero code per failed step — so `exit 0` is
// a claim about the whole program, not a claim that it started.

test "020 s40 systems proof corpus: 24-zero-copy-frame-reader runs — the zero-copy frame reader executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("24-zero-copy-frame-reader")
    assert build.ExitCode == 0
    assert ProofArtifacts("24-zero-copy-frame-reader", "SystemsProof24ZeroCopyFrameReader") == "assembly=true runtime=true"

    run := RunProofAssembly("24-zero-copy-frame-reader", "SystemsProof24ZeroCopyFrameReader")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 25-trusted-memory-copy runs — the trusted memory copy executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("25-trusted-memory-copy")
    assert build.ExitCode == 0
    assert ProofArtifacts("25-trusted-memory-copy", "SystemsProof25TrustedMemoryCopy") == "assembly=true runtime=true"

    run := RunProofAssembly("25-trusted-memory-copy", "SystemsProof25TrustedMemoryCopy")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

// THE `26-native-device-handle` SUBSTITUTION. The deleted body proved `Open` and `Close` had
// no managed body by loading the assembly into an `AssemblyLoadContext`. Running it instead
// proves the whole native path END TO END: `Main` calls libc `open("/dev/null", 0)` through
// the emitted import, and a nonnegative descriptor is what makes the answer an `Ok`.
test "020 s40 systems proof corpus: 26-native-device-handle runs — the native device handle executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("26-native-device-handle")
    assert build.ExitCode == 0
    assert ProofArtifacts("26-native-device-handle", "SystemsProof26NativeDeviceHandle") == "assembly=true runtime=true"

    run := RunProofAssembly("26-native-device-handle", "SystemsProof26NativeDeviceHandle")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == "SystemsProofs.NativeDeviceHandle.DeviceHandle"
    assert run.Stderr == ""
}

// THE `27-c-library-cli` FINDING, AND ITS FIX. Slice 40 pinned this proof as A SHIPPED SAMPLE
// THAT COULD NOT EXECUTE: `[LibraryImport]` over a `ReadOnlySpan<byte>` was accepted in
// SILENCE — `nlc check --json` answered `ok: true` with zero rows and `nlc build` succeeded —
// and the program then aborted at exit 134 with `MarshalDirectiveException: Cannot marshal
// 'parameter #1': Non-blittable generic types cannot be marshaled.`, raised by the CLR's
// interop marshaller at the call, BEFORE the native library was looked for.
//
// A generic type can never appear in a P/Invoke signature, and nothing rewrites it here: C#
// survives spans under `[LibraryImport]` only because a SOURCE GENERATOR replaces the
// declaration with a pinning wrapper around a pointer-taking stub, while N# emits the P/Invoke
// directly. So the shape is now REFUSED at check time (`NL405`, pinned below and in
// `AnalyzerAttributeValidator.tests.nl`) and the sample is spelled with the array the
// marshaller accepts.
//
// WHAT THE RUN PROVES NOW IS STRICTLY MORE THAN WHAT IT PROVED BEFORE. The call reaches the
// native LOADER — `DllNotFoundException` naming `fast_hash`, from `NativeHash.Hash64` itself —
// which is the successor to the deleted `AssertNativeImportHasNoManagedBody(…, "NativeHash",
// "Hash64")`: only a GENUINE interop stub gets as far as `dlopen`, and no managed body could
// produce this stack. The sample still cannot COMPLETE, because `fast_hash` stands in for a C
// library this repository does not carry; what it can now do is marshal.
test "020 s40 systems proof corpus: 27-c-library-cli is a genuine native import — its signature marshals and the call reaches the native loader, not the marshaller (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("27-c-library-cli")
    assert build.ExitCode == 0
    assert ProofArtifacts("27-c-library-cli", "SystemsProof27CLibraryCli") == "assembly=true runtime=true"

    run := RunProofAssembly("27-c-library-cli", "SystemsProof27CLibraryCli")
    assert run.ExitCode != 0
    assert run.Stdout == ""
    assert !run.Stderr.Contains("MarshalDirectiveException")
    assert run.Stderr.Contains("System.DllNotFoundException")
    assert run.Stderr.Contains("fast_hash")
    assert run.Stderr.Contains("SystemsProofs.CLibraryCli.NativeHash.Hash64")
}

// THE CONTROL FOR THE REFUSAL, THROUGH THE REAL CLI. The corpus no longer ships a sample with
// the refused shape — that is the point of the fix — so the negative is written out and checked
// here, beside a byte-identical positive that differs only in the parameter's spelling. Without
// the pair, `27` passing would be equally consistent with the rule having been deleted.
//
// The sentence is matched in PIECES rather than whole: the `--json` envelope escapes `'` as
// `\u0027` and `<` as `\u003C`, so `can't marshal parameter 'data'` and `ReadOnlySpan<byte>` do
// not occur literally in the output. The code, the verb and the type NAME do.
test "020 chip: nlc check REFUSES a [LibraryImport] span parameter and ACCEPTS the array beside it" {
    spanProbe := WriteNativeImportProbe("nsharp-native-import-probe-span", "ReadOnlySpan<byte>")
    refused := CheckProjectJson(spanProbe)
    arrayProbe := WriteNativeImportProbe("nsharp-native-import-probe-array", "byte[]")
    accepted := CheckProjectJson(arrayProbe)
    Directory.Delete(spanProbe, true)
    Directory.Delete(arrayProbe, true)

    assert refused.ExitCode == 1
    assert refused.Stdout.Contains("\"code\": \"NL405\"")
    assert refused.Stdout.Contains("marshal parameter")
    assert refused.Stdout.Contains("ReadOnlySpan")
    assert refused.Stdout.Contains("\"errors\": 1")

    assert accepted.ExitCode == 0
    assert !accepted.Stdout.Contains("NL405")
    assert accepted.Stdout.Contains("\"errors\": 0")
}

test "020 s40 systems proof corpus: 30-cold-failure-logging runs — the cold failure logger executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("30-cold-failure-logging")
    assert build.ExitCode == 0
    assert ProofArtifacts("30-cold-failure-logging", "SystemsProof30ColdFailureLogging") == "assembly=true runtime=true"

    run := RunProofAssembly("30-cold-failure-logging", "SystemsProof30ColdFailureLogging")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == "parse failed"
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 33-arraypool-file-io runs — the ArrayPool file reader executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("33-arraypool-file-io")
    assert build.ExitCode == 0
    assert ProofArtifacts("33-arraypool-file-io", "SystemsProof33ArrayPoolFileIo") == "assembly=true runtime=true"

    run := RunProofAssembly("33-arraypool-file-io", "SystemsProof33ArrayPoolFileIo")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 34-memorypool-disposal runs — the MemoryPool disposal path executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("34-memorypool-disposal")
    assert build.ExitCode == 0
    assert ProofArtifacts("34-memorypool-disposal", "SystemsProof34MemoryPoolDisposal") == "assembly=true runtime=true"

    run := RunProofAssembly("34-memorypool-disposal", "SystemsProof34MemoryPoolDisposal")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 35-async-file-hot-parser runs — the async file hot parser executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("35-async-file-hot-parser")
    assert build.ExitCode == 0
    assert ProofArtifacts("35-async-file-hot-parser", "SystemsProof35AsyncFileHotParser") == "assembly=true runtime=true"

    run := RunProofAssembly("35-async-file-hot-parser", "SystemsProof35AsyncFileHotParser")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 37-fixed-capacity-map runs — the fixed-capacity map executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("37-fixed-capacity-map")
    assert build.ExitCode == 0
    assert ProofArtifacts("37-fixed-capacity-map", "SystemsProof37FixedCapacityMap") == "assembly=true runtime=true"

    run := RunProofAssembly("37-fixed-capacity-map", "SystemsProof37FixedCapacityMap")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 38-unmanaged-sort-comparer runs — the unmanaged sort comparer executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("38-unmanaged-sort-comparer")
    assert build.ExitCode == 0
    assert ProofArtifacts("38-unmanaged-sort-comparer", "SystemsProof38UnmanagedSortComparer") == "assembly=true runtime=true"

    run := RunProofAssembly("38-unmanaged-sort-comparer", "SystemsProof38UnmanagedSortComparer")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 39-hot-linq-pipeline runs — the hot LINQ pipeline executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("39-hot-linq-pipeline")
    assert build.ExitCode == 0
    assert ProofArtifacts("39-hot-linq-pipeline", "SystemsProof39HotLinqPipeline") == "assembly=true runtime=true"

    run := RunProofAssembly("39-hot-linq-pipeline", "SystemsProof39HotLinqPipeline")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 41-structured-errors runs — the structured-error parser executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("41-structured-errors")
    assert build.ExitCode == 0
    assert ProofArtifacts("41-structured-errors", "SystemsProof41StructuredErrors") == "assembly=true runtime=true"

    run := RunProofAssembly("41-structured-errors", "SystemsProof41StructuredErrors")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 46-dapper-boundary runs — the database boundary executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("46-dapper-boundary")
    assert build.ExitCode == 0
    assert ProofArtifacts("46-dapper-boundary", "SystemsProof46DapperBoundary") == "assembly=true runtime=true"

    run := RunProofAssembly("46-dapper-boundary", "SystemsProof46DapperBoundary")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}


// ─── THE TWO SYSTEMS-REPORT CHECKS ────────────────────────────────────────────────────────────
// `nlc check --project … --systems-report`, spawned. Both blocks pin the FULL function census the
// deleted body's `Single(function => …)` lookups only assumed, and the whole four-field AOT block
// where the C# read two fields.

test "020 s40 systems proof corpus: 24-zero-copy-frame-reader checks clean — NextFrame is hot, allocation-free, trap-free and AOT-safe (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    check := CheckProof("24-zero-copy-frame-reader")

    assert check.ExitCode == 0
    assert CheckEnvelope(check.Stdout) == "1|check.systemsReport|true|errors=0|warnings=0|info=0"
    assert CheckDiagnosticCensus(check.Stdout) == "<empty>"
    assert AotRow(check.Stdout) == "nativeaot|pass|false|true"
    assert SystemsFunctionNames(check.Stdout) == "NextFrame|Main"
    assert SystemsFunctionRow(check.Stdout, "NextFrame") == "true|false|false|false|false|true"
}

test "020 s40 systems proof corpus: 42-aot-friendly-public-api checks AOT-clean — the analysis passes, the assembly is trim-safe, and NameApi.Normalize is AOT-safe (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    check := CheckProof("42-aot-friendly-public-api")

    assert check.ExitCode == 0
    assert CheckEnvelope(check.Stdout) == "1|check.systemsReport|true|errors=0|warnings=2|info=0"
    assert CheckDiagnosticCensus(check.Stdout) == "NSYS050:warning@19:28|NSYS050:warning@19:47"
    assert AotRow(check.Stdout) == "nativeaot|pass|false|true"
    assert SystemsFunctionNames(check.Stdout) == "NameApi.Normalize"
    assert SystemsFunctionRow(check.Stdout, "NameApi.Normalize") == "false|true|false|false|true|true"
}


// ─── THE TWO TRUSTED-SITE QUERIES ─────────────────────────────────────────────────────────────
// `nlc query trusted --project …`, spawned. The C# read three fields off each result; these rows
// pin all six, `review` and `bodyStatementCount` included.

test "020 s40 systems proof corpus: 25-trusted-memory-copy answers one trusted site — CopyExact, owned by runtime-core, expiring 2027-06-01 (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    trusted := QueryTrustedProof("25-trusted-memory-copy")

    assert trusted.ExitCode == 0
    assert trusted.Stderr == ""
    assert TrustedQueryEnvelope(trusted.Stdout) == "1|trusted|true|results=1"
    assert TrustedQueryRow(trusted.Stdout, 0) == "CopyExact|runtime-core|2026-12-01|2027-06-01|true|3"
}

test "020 s40 systems proof corpus: 45-trusted-audit answers one trusted site — UnsafeAuditSurface.WrapHandle, owned by interop, expiring 2027-06-01 (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    trusted := QueryTrustedProof("45-trusted-audit")

    assert trusted.ExitCode == 0
    assert trusted.Stderr == ""
    assert TrustedQueryEnvelope(trusted.Stdout) == "1|trusted|true|results=1"
    assert TrustedQueryRow(trusted.Stdout, 0) == "UnsafeAuditSurface.WrapHandle|interop|2026-12-01|2027-06-01|true|2"
}

// ─── THE FIVE RUNS THE DELETED BODY NEVER MADE ────────────────────────────────────────────────
// 18 of the 21 proof projects are `outputType: exe`; the deleted body executed 11 of them, so seven
// shipped executable samples were built and never run. Two of the seven are the native-import
// proofs above. These are the other five, and with them EVERY executable proof in the corpus is
// proven to execute. The three that are absent — 42, 43 and 45 — are `outputType: library` and have
// no entry point at all.

test "020 s40 systems proof corpus: 31-hot-metrics runs — the hot metrics counter executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("31-hot-metrics")
    assert build.ExitCode == 0
    assert ProofArtifacts("31-hot-metrics", "SystemsProof31HotMetrics") == "assembly=true runtime=true"

    run := RunProofAssembly("31-hot-metrics", "SystemsProof31HotMetrics")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == "metrics ok"
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 32-cache-prewarm runs — the prewarmed cache executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("32-cache-prewarm")
    assert build.ExitCode == 0
    assert ProofArtifacts("32-cache-prewarm", "SystemsProof32CachePrewarm") == "assembly=true runtime=true"

    run := RunProofAssembly("32-cache-prewarm", "SystemsProof32CachePrewarm")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == "217"
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 36-dictionary-setup-hot-read runs — the catalog build and hot read execute as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("36-dictionary-setup-hot-read")
    assert build.ExitCode == 0
    assert ProofArtifacts("36-dictionary-setup-hot-read", "SystemsProof36DictionarySetupHotRead") == "assembly=true runtime=true"

    run := RunProofAssembly("36-dictionary-setup-hot-read", "SystemsProof36DictionarySetupHotRead")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == "200"
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 44-ci-allocation-gate runs — the allocation gate executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("44-ci-allocation-gate")
    assert build.ExitCode == 0
    assert ProofArtifacts("44-ci-allocation-gate", "SystemsProof44CiAllocationGate") == "assembly=true runtime=true"

    run := RunProofAssembly("44-ci-allocation-gate", "SystemsProof44CiAllocationGate")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == "6"
    assert run.Stderr == ""
}

test "020 s40 systems proof corpus: 48-effect-drift runs — the drifted effect path executes as a process (was SystemsNSharpTests.ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence)" {
    build := BuildProof("48-effect-drift")
    assert build.ExitCode == 0
    assert ProofArtifacts("48-effect-drift", "SystemsProof48EffectDrift") == "assembly=true runtime=true"

    run := RunProofAssembly("48-effect-drift", "SystemsProof48EffectDrift")
    assert run.ExitCode == 0
    assert run.Stdout.Trim() == ""
    assert run.Stderr == ""
}

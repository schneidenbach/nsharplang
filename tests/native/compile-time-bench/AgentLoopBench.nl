namespace NSharpLang.CompileTimeBench

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text
import System.Text.Json

// THE AGENT-LOOP LATENCY BENCHMARK.
//
// An AI agent writing N# does not compile a project once; it edits, checks, builds and tests in a
// tight loop, dozens of times an hour. What it pays for is the latency of that loop, and the
// compile-time benchmark beside this file measures something else (one cold build of one large
// project). So this owner measures the loop itself:
//
//   SCENARIOS (`AgentLoopScenarios`) - each one is "the agent did X, then ran Y":
//     no-op       nothing changed since the last run of the same command   check, build, test
//     body        one function's BODY changed                              check, build, test
//     signature   a PUBLIC function gained a parameter, call sites updated check, build
//     new-file    a new source file was added                              check, build
//
//   SIZES (`AgentLoopSizes`):
//     small   tests/fixtures/issue-tracker, a real 534-line ASP.NET project, copied
//     medium  a deterministic synthetic library of ~10k lines (40 files)
//     large   the same generator at ~80k lines (160 files), Compiler.Core's size
//
//   MODES: every scenario is measured COLD and WARM. One sample is: a fresh temp copy of the
//   project, one PRIME run of the scenario's own command (the agent's previous step), the edit,
//   then the measured COLD run (the first fresh process after the edit) and the measured WARM run
//   (the same command again, unchanged - a second process, or a daemon answer when `--daemon` keeps
//   one up). Every sample re-primes a fresh copy, so no sample can inherit another's outputs and an
//   incremental compiler's caches are always exactly one prime old.
//
// WHAT IS MEASURED. Wall time and CPU time (user + sys, children included) and peak RSS come from
// `/usr/bin/time` around the CLI process - the same spawn kernel the compile-time benchmark uses.
// Those move with machine load. The STRUCTURAL counters do not: files parsed, columnar emit parses,
// files analyzed, assemblies emitted, reference images loaded and child processes spawned, read from
// the CLI's own `--stats=<path>` line (`CompilerWorkCounters` in Compiler.Model, schema
// `nsharp.cli-stats` v1). The same input gives the same counts on a busy machine and an idle one, so
// they are gated EXACTLY, and they are what explains a wall-time change.
//
// THE BUDGET (`tests/fixtures/agent-loop/agent-loop-baseline.golden.json`). Counters must equal the
// baseline row for row: a decrease is an improvement that must be ratcheted into the baseline in the
// same commit, an increase is a regression to fix. Wall time is judged against the baseline's
// medians with the baseline's tolerance only on a machine quiet enough to judge (the compile-time
// benchmark's `BenchLoadRefusesTimingJudgement`, one fifth of the logical cores) AND only when the
// baseline's own timings were taken on such a machine; otherwise it is reported as unjudged.
// No threshold in that file is ever loosened without the owner.

// ─── SIZES AND SCENARIOS ──────────────────────────────────────────────────────────────────────
class AgentLoopSize {
    Name: string
    FixtureProject: string
    FileCount: int
    FunctionsPerFile: int

    constructor(name: string, fixtureProject: string, fileCount: int, functionsPerFile: int) {
        Name = name
        FixtureProject = fixtureProject
        FileCount = fileCount
        FunctionsPerFile = functionsPerFile
    }
}

func AgentLoopSizes(): List<AgentLoopSize> {
    sizes := new List<AgentLoopSize>()
    sizes.Add(new AgentLoopSize("small", "tests/fixtures/issue-tracker", 0, 0))
    sizes.Add(new AgentLoopSize("medium", "", 40, 16))
    sizes.Add(new AgentLoopSize("large", "", 160, 32))
    return sizes
}

// The sizes the product gate measures. `large` is the full-matrix run's: one sample of it costs
// minutes, and the counters it would gate are the same code paths `medium` already pins.
func AgentLoopGateSizeNames(): List<string> {
    names := new List<string>()
    names.Add("small")
    names.Add("medium")
    return names
}

func AgentLoopFindSize(name: string): AgentLoopSize? {
    sizes := AgentLoopSizes()
    i := 0
    while i < sizes.Count {
        if sizes[i].Name == name {
            return sizes[i]
        }

        i = i + 1
    }

    return null
}

class AgentLoopScenario {
    Id: string
    Command: string
    Edit: string

    constructor(id: string, command: string, edit: string) {
        Id = id
        Command = command
        Edit = edit
    }
}

func AgentLoopEditNone(): string {
    return "none"
}

func AgentLoopEditBody(): string {
    return "body"
}

func AgentLoopEditSignature(): string {
    return "signature"
}

func AgentLoopEditNewFile(): string {
    return "new-file"
}

func AgentLoopScenarios(): List<AgentLoopScenario> {
    scenarios := new List<AgentLoopScenario>()
    scenarios.Add(new AgentLoopScenario("no-op check", "check", AgentLoopEditNone()))
    scenarios.Add(new AgentLoopScenario("no-op build", "build", AgentLoopEditNone()))
    scenarios.Add(new AgentLoopScenario("no-op test", "test", AgentLoopEditNone()))
    scenarios.Add(new AgentLoopScenario("body check", "check", AgentLoopEditBody()))
    scenarios.Add(new AgentLoopScenario("body build", "build", AgentLoopEditBody()))
    scenarios.Add(new AgentLoopScenario("body test", "test", AgentLoopEditBody()))
    scenarios.Add(new AgentLoopScenario("signature check", "check", AgentLoopEditSignature()))
    scenarios.Add(new AgentLoopScenario("signature build", "build", AgentLoopEditSignature()))
    scenarios.Add(new AgentLoopScenario("new-file check", "check", AgentLoopEditNewFile()))
    scenarios.Add(new AgentLoopScenario("new-file build", "build", AgentLoopEditNewFile()))
    return scenarios
}

// ─── THE PROJECTS ─────────────────────────────────────────────────────────────────────────────

func AgentLoopPad(value: int, width: int): string {
    text := BenchIntText(value)
    while text.Length < width {
        text = "0" + text
    }

    return text
}

func AgentLoopShouldSkipCopiedDirectory(name: string): bool {
    return name == "bin" || name == "obj" || name == ".nlc"
}

// A fixture is copied file by file, without its build outputs, into the sample's own directory.
func AgentLoopCopyDirectory(source: string, destination: string) {
    Directory.CreateDirectory(destination)
    files := Directory.GetFiles(source)
    i := 0
    while i < files.Length {
        File.Copy(files[i], Path.Combine(destination, Path.GetFileName(files[i]) ?? ""), true)
        i = i + 1
    }

    directories := Directory.GetDirectories(source)
    j := 0
    while j < directories.Length {
        name := Path.GetFileName(directories[j]) ?? ""
        if !AgentLoopShouldSkipCopiedDirectory(name) {
            AgentLoopCopyDirectory(directories[j], Path.Combine(destination, name))
        }

        j = j + 1
    }
}

func AgentLoopSyntheticNamespace(): string {
    return "AgentLoopSynth"
}

func AgentLoopSyntheticProjectYml(): string {
    return "name: AgentLoopSynth\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
}

func AgentLoopSyntheticFileName(file: int): string {
    return "Module" + AgentLoopPad(file, 3) + ".nl"
}

func AgentLoopSyntheticFunctionName(file: int, function: int): string {
    return "Score" + AgentLoopPad(file, 3) + "_" + AgentLoopPad(function, 2)
}

// THE EDIT TARGET is `Score000_00`: its body is what a body edit changes, and its signature is what
// a signature edit extends. Its ONE caller is `Score001_00` (every function calls its namesake in
// the previous file), so a signature edit rewrites exactly two files, and no test calls it.
func AgentLoopIsEditTarget(file: int, function: int): bool {
    return file == 0 && function == 0
}

// One synthetic source file. `bodyVariant < 0` is the unedited text; `bodyVariant >= 0` changes the
// edit target's first statement. `signatureEdited` gives the edit target a third parameter, which its
// return reads (strict lint refuses an unread one), and its caller the matching argument.
// Everything is a pure function of the arguments, so two runs of the harness measure byte-identical
// projects.
func AgentLoopSyntheticFileText(file: int, functionsPerFile: int, bodyVariant: int, signatureEdited: bool): string {
    builder := new StringBuilder()
    suffix := AgentLoopPad(file, 3)
    BenchAppendLine(builder, "namespace " + AgentLoopSyntheticNamespace())
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "import System.Collections.Generic")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "record Item" + suffix + "(Id: int, Name: string, Weight: int) {")
    BenchAppendLine(builder, "}")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "class Ledger" + suffix + " {")
    BenchAppendLine(builder, "    entries: List<Item" + suffix + ">")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "    constructor() {")
    BenchAppendLine(builder, "        entries = new List<Item" + suffix + ">()")
    BenchAppendLine(builder, "    }")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "    func Add(item: Item" + suffix + ") {")
    BenchAppendLine(builder, "        entries.Add(item)")
    BenchAppendLine(builder, "    }")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "    func TotalWeight(): int {")
    BenchAppendLine(builder, "        total := 0")
    BenchAppendLine(builder, "        for entry in entries {")
    BenchAppendLine(builder, "            total = total + entry.Weight")
    BenchAppendLine(builder, "        }")
    BenchAppendLine(builder, "        return total")
    BenchAppendLine(builder, "    }")
    BenchAppendLine(builder, "}")

    function := 0
    while function < functionsPerFile {
        name := AgentLoopSyntheticFunctionName(file, function)
        parameters := "values: int[], seed: int"
        if signatureEdited && AgentLoopIsEditTarget(file, function) {
            parameters = parameters + ", bias: int"
        }

        start := "seed + " + BenchIntText(function)
        if bodyVariant >= 0 && AgentLoopIsEditTarget(file, function) {
            start = "seed + " + BenchIntText(1000 + bodyVariant)
        }

        call := "0"
        if file > 0 {
            call = AgentLoopSyntheticFunctionName(file - 1, function) + "(values, seed"
            if signatureEdited && AgentLoopIsEditTarget(file - 1, function) {
                call = call + ", 0"
            }
            call = call + ")"
        }

        BenchAppendLine(builder, "")
        BenchAppendLine(builder, "func " + name + "(" + parameters + "): int {")
        BenchAppendLine(builder, "    total := " + start)
        BenchAppendLine(builder, "    for i := 0; i < values.Length; i++ {")
        BenchAppendLine(builder, "        if values[i] % 2 == 0 {")
        BenchAppendLine(builder, "            total = total + values[i] * " + BenchIntText(file % 7 + 2))
        BenchAppendLine(builder, "        } else {")
        BenchAppendLine(builder, "            total = total - values[i]")
        BenchAppendLine(builder, "        }")
        BenchAppendLine(builder, "    }")
        BenchAppendLine(builder, "    if total > " + BenchIntText(100 + function) + " {")
        BenchAppendLine(builder, "        total = total / 2")
        BenchAppendLine(builder, "    }")
        result := "total + " + call
        if signatureEdited && AgentLoopIsEditTarget(file, function) {
            result = "total + bias + " + call
        }
        BenchAppendLine(builder, "    return " + result)
        BenchAppendLine(builder, "}")
        function = function + 1
    }

    return builder.ToString() ?? ""
}

func AgentLoopSyntheticTestText(): string {
    builder := new StringBuilder()
    BenchAppendLine(builder, "namespace " + AgentLoopSyntheticNamespace())
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "test \"the second module scores the same input the same way twice\" {")
    BenchAppendLine(builder, "    values: int[] = [1, 2, 3, 4, 5]")
    BenchAppendLine(builder, "    assert " + AgentLoopSyntheticFunctionName(1, 1) + "(values, 3) == " + AgentLoopSyntheticFunctionName(1, 1) + "(values, 3)")
    BenchAppendLine(builder, "}")
    BenchAppendLine(builder, "")
    BenchAppendLine(builder, "test \"a ledger totals the weights it was given\" {")
    BenchAppendLine(builder, "    ledger := new Ledger000()")
    BenchAppendLine(builder, "    ledger.Add(new Item000(1, \"a\", 2))")
    BenchAppendLine(builder, "    ledger.Add(new Item000(2, \"b\", 5))")
    BenchAppendLine(builder, "    assert ledger.TotalWeight() == 7")
    BenchAppendLine(builder, "}")
    return builder.ToString() ?? ""
}

func AgentLoopWriteSynthetic(size: AgentLoopSize, directory: string) {
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "project.yml"), AgentLoopSyntheticProjectYml())
    file := 0
    while file < size.FileCount {
        File.WriteAllText(
            Path.Combine(directory, AgentLoopSyntheticFileName(file)),
            AgentLoopSyntheticFileText(file, size.FunctionsPerFile, -1, false)
        )
        file = file + 1
    }

    File.WriteAllText(Path.Combine(directory, "Synth.tests.nl"), AgentLoopSyntheticTestText())
}

func AgentLoopMaterialize(repositoryRoot: string, size: AgentLoopSize, directory: string) {
    if size.FixtureProject != "" {
        AgentLoopCopyDirectory(BenchAbsoluteProjectPath(repositoryRoot, size.FixtureProject), directory)
        return
    }

    AgentLoopWriteSynthetic(size, directory)
}

// The non-test source lines of a materialized project, so the report states what was measured.
func AgentLoopSourceLines(directory: string): long {
    return BenchMeasureSelectedProjectSources(directory, false).Lines
}

// ─── THE EDITS ────────────────────────────────────────────────────────────────────────────────

func AgentLoopAddedFileName(): string {
    return "AgentLoopAdded.nl"
}

// Replace `anchor` in one file, refusing (with the reason) unless it occurs exactly once: an edit
// that silently did nothing would measure a no-op and call it an edit.
func AgentLoopReplaceOnce(path: string, anchor: string, replacement: string): string {
    if !File.Exists(path) {
        return "edit target " + path + " does not exist"
    }

    text := File.ReadAllText(path)
    first := text.IndexOf(anchor, StringComparison.Ordinal)
    if first < 0 {
        return "edit anchor '" + anchor + "' is not in " + path
    }

    if text.IndexOf(anchor, first + anchor.Length, StringComparison.Ordinal) >= 0 {
        return "edit anchor '" + anchor + "' occurs more than once in " + path
    }

    File.WriteAllText(path, text.Substring(0, first) + replacement + text.Substring(first + anchor.Length))
    return ""
}

// The small project's edits, against the issue-tracker fixture's own text:
//   body       `IssueService.validate`'s length limit (Service.nl)
//   signature  public `Workflow.Transition` gains `reason: string`, its body reads it (strict lint
//              refuses an unread parameter), and its one caller passes it
//   new-file   a class that calls into `IssueService`
func AgentLoopApplyFixtureEdit(directory: string, edit: string, variant: int): string {
    if edit == AgentLoopEditBody() {
        return AgentLoopReplaceOnce(
            Path.Combine(directory, "Service.nl"),
            "title.Length > 200 {",
            "title.Length > " + BenchIntText(200 + variant) + " {"
        )
    }

    if edit == AgentLoopEditSignature() {
        declaration := AgentLoopReplaceOnce(
            Path.Combine(directory, "Workflow.nl"),
            "static func Transition(issue: Issue, to: IssueStatus): IssueStatus {",
            "static func Transition(issue: Issue, to: IssueStatus, reason: string): IssueStatus {"
        )
        if declaration != "" {
            return declaration
        }

        use := AgentLoopReplaceOnce(
            Path.Combine(directory, "Workflow.nl"),
            "throw new Exception(Errors.Format(new IssueError.InvalidTransition(describe(issue.Status), describe(to))))",
            "throw new Exception(reason + \": \" + Errors.Format(new IssueError.InvalidTransition(describe(issue.Status), describe(to))))"
        )
        if use != "" {
            return use
        }

        return AgentLoopReplaceOnce(
            Path.Combine(directory, "Service.nl"),
            "Workflow.Transition(issue, newStatus)",
            "Workflow.Transition(issue, newStatus, \"edit " + BenchIntText(variant) + "\")"
        )
    }

    if edit == AgentLoopEditNewFile() {
        File.WriteAllText(
            Path.Combine(directory, AgentLoopAddedFileName()),
            "namespace IssueTracker\n\nclass AgentLoopAdded {\n    static func OpenCount(service: IssueService): int {\n        return service.GetAll().Count + " + BenchIntText(variant) + "\n    }\n}\n"
        )
        return ""
    }

    return ""
}

func AgentLoopApplySyntheticEdit(size: AgentLoopSize, directory: string, edit: string, variant: int): string {
    if edit == AgentLoopEditBody() {
        File.WriteAllText(
            Path.Combine(directory, AgentLoopSyntheticFileName(0)),
            AgentLoopSyntheticFileText(0, size.FunctionsPerFile, variant, false)
        )
        return ""
    }

    if edit == AgentLoopEditSignature() {
        File.WriteAllText(
            Path.Combine(directory, AgentLoopSyntheticFileName(0)),
            AgentLoopSyntheticFileText(0, size.FunctionsPerFile, -1, true)
        )
        File.WriteAllText(
            Path.Combine(directory, AgentLoopSyntheticFileName(1)),
            AgentLoopSyntheticFileText(1, size.FunctionsPerFile, -1, true)
        )
        return ""
    }

    if edit == AgentLoopEditNewFile() {
        File.WriteAllText(
            Path.Combine(directory, AgentLoopAddedFileName()),
            "namespace " + AgentLoopSyntheticNamespace() + "\n\nfunc AddedScore(values: int[]): int {\n    return " + AgentLoopSyntheticFunctionName(0, 1) + "(values, " + BenchIntText(variant) + ")\n}\n"
        )
        return ""
    }

    return ""
}

// `""` when the edit was applied (or there was none to apply); the reason otherwise.
func AgentLoopApplyEdit(size: AgentLoopSize, directory: string, edit: string, variant: int): string {
    if edit == AgentLoopEditNone() {
        return ""
    }

    if size.FixtureProject != "" {
        return AgentLoopApplyFixtureEdit(directory, edit, variant)
    }

    return AgentLoopApplySyntheticEdit(size, directory, edit, variant)
}

// ─── ONE RUN OF THE CLI ───────────────────────────────────────────────────────────────────────

class AgentLoopCounters {
    FilesParsed: long
    EmitParses: long
    FilesAnalyzed: long
    AssembliesEmitted: long
    ReferenceAssembliesLoaded: long
    ProcessesSpawned: long

    constructor(filesParsed: long, emitParses: long, filesAnalyzed: long, assembliesEmitted: long, referenceAssembliesLoaded: long, processesSpawned: long) {
        FilesParsed = filesParsed
        EmitParses = emitParses
        FilesAnalyzed = filesAnalyzed
        AssembliesEmitted = assembliesEmitted
        ReferenceAssembliesLoaded = referenceAssembliesLoaded
        ProcessesSpawned = processesSpawned
    }
}

// The stand-in an unwrap needs after a null check has already ruled null out.
func AgentLoopZeroCounters(): AgentLoopCounters {
    return new AgentLoopCounters(0, 0, 0, 0, 0, 0)
}

func AgentLoopCountersEqual(left: AgentLoopCounters, right: AgentLoopCounters): bool {
    return left.FilesParsed == right.FilesParsed && left.EmitParses == right.EmitParses && left.FilesAnalyzed == right.FilesAnalyzed && left.AssembliesEmitted == right.AssembliesEmitted && left.ReferenceAssembliesLoaded == right.ReferenceAssembliesLoaded && left.ProcessesSpawned == right.ProcessesSpawned
}

func AgentLoopCountersText(counters: AgentLoopCounters): string {
    return "filesParsed=" + BenchLongText(counters.FilesParsed) + " emitParses=" + BenchLongText(counters.EmitParses) + " filesAnalyzed=" + BenchLongText(counters.FilesAnalyzed) + " assembliesEmitted=" + BenchLongText(counters.AssembliesEmitted) + " referenceAssembliesLoaded=" + BenchLongText(counters.ReferenceAssembliesLoaded) + " processesSpawned=" + BenchLongText(counters.ProcessesSpawned)
}

func AgentLoopJsonLong(element: JsonElement, name: string): long {
    return element.GetProperty(name).GetInt64()
}

func AgentLoopCountersFromElement(element: JsonElement): AgentLoopCounters {
    return new AgentLoopCounters(
        AgentLoopJsonLong(element, "filesParsed"),
        AgentLoopJsonLong(element, "emitParses"),
        AgentLoopJsonLong(element, "filesAnalyzed"),
        AgentLoopJsonLong(element, "assembliesEmitted"),
        AgentLoopJsonLong(element, "referenceAssembliesLoaded"),
        AgentLoopJsonLong(element, "processesSpawned")
    )
}

// The counters out of one `--stats` line, or null when the line is absent, unreadable, or not
// schema `nsharp.cli-stats` version 1.
func AgentLoopParseStatsCounters(json: string): AgentLoopCounters? {
    if json.Trim().Length == 0 {
        return null
    }

    try {
        document := JsonDocument.Parse(json)
        root := document.RootElement
        if (root.GetProperty("schema").GetString() ?? "") != "nsharp.cli-stats" || root.GetProperty("schemaVersion").GetInt32() != 1 {
            document.Dispose()
            return null
        }

        counters := AgentLoopCountersFromElement(root.GetProperty("counters"))
        document.Dispose()
        return counters
    } catch {
        return null
    }
}

// User plus system CPU of the timed child, in milliseconds, from the time utility's report: the
// macOS `-l` summary line `1.54 real 1.46 user 0.08 sys`, or Linux `-v`'s `User time (seconds):`
// and `System time (seconds):` lines. `-1` when neither shape is present.
func AgentLoopParseCpuMs(stderr: string): long {
    lines := BenchSplitLines(stderr)
    userMs := -1L
    systemMs := -1L
    i := 0
    while i < lines.Count {
        line := lines[i].Trim()
        if line.EndsWith(" sys", StringComparison.Ordinal) && line.IndexOf(" user ", StringComparison.Ordinal) > 0 {
            tokens := line.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            if tokens.Length == 6 && tokens[3] == "user" && tokens[5] == "sys" {
                userMs = BenchParseFixed3(tokens[2])
                systemMs = BenchParseFixed3(tokens[4])
            }
        } else if line.StartsWith("User time (seconds):", StringComparison.Ordinal) {
            userMs = BenchParseFixed3(line.Substring("User time (seconds):".Length))
        } else if line.StartsWith("System time (seconds):", StringComparison.Ordinal) {
            systemMs = BenchParseFixed3(line.Substring("System time (seconds):".Length))
        }

        i = i + 1
    }

    if userMs < 0 || systemMs < 0 {
        return -1
    }

    return userMs + systemMs
}

class AgentLoopRun {
    ExitCode: int
    WallMs: long
    CpuMs: long
    PeakRssBytes: long
    Counters: AgentLoopCounters?
    Detail: string

    constructor(exitCode: int, wallMs: long, cpuMs: long, peakRssBytes: long, counters: AgentLoopCounters?, detail: string) {
        ExitCode = exitCode
        WallMs = wallMs
        CpuMs = cpuMs
        PeakRssBytes = peakRssBytes
        Counters = counters
        Detail = detail
    }
}

func AgentLoopCommandArguments(cliDll: string, command: string, projectDirectory: string, statsPath: string): string {
    arguments := BenchQuote(cliDll) + " " + command
    if command == "build" {
        arguments = arguments + " --color=never"
    }

    arguments = arguments + " --project " + BenchQuote(projectDirectory)
    if statsPath != "" {
        arguments = arguments + " --stats=" + BenchQuote(statsPath)
    }

    return arguments
}

func AgentLoopStatsPath(): string {
    return Path.Combine(Path.GetTempPath(), "nsharp-agent-loop-stats-" + BenchLongText(DateTime.UtcNow.Ticks) + ".json")
}

// THE ONE OWNER of "run one agent-loop command and measure it". `useStats` is false only for a CLI
// that predates `--stats` (a base build being compared); its counters are then null, never zero.
func AgentLoopRunCommand(cliDll: string, projectDirectory: string, command: string, useStats: bool, daemon: bool): AgentLoopRun {
    statsPath := ""
    if useStats {
        statsPath = AgentLoopStatsPath()
    }

    run := BenchRunUnderTimeUtilityWithEnvironment(AgentLoopCommandArguments(cliDll, command, projectDirectory, statsPath), Path.GetTempPath(), AgentLoopDaemonEnvironment(daemon))
    counters: AgentLoopCounters? = null
    if statsPath != "" && File.Exists(statsPath) {
        counters = AgentLoopParseStatsCounters(File.ReadAllText(statsPath))
        File.Delete(statsPath)
    }

    detail := ""
    if run.ExitCode != 0 {
        detail = BenchTruncate(BenchStripTimeUtilityLines(run.Stderr).Trim() + " " + run.Stdout.Trim(), 600)
    } else if useStats && counters == null {
        detail = "the CLI exited 0 but wrote no readable nsharp.cli-stats v1 line to " + statsPath
    }

    return new AgentLoopRun(run.ExitCode, run.WallMs, AgentLoopParseCpuMs(run.Stderr), BenchParsePeakRssBytes(run.Stderr), counters, detail)
}

// Whether a CLI understands `--stats`: its own `build --help` says so.
func AgentLoopCliSupportsStats(cliDll: string): bool {
    run := BenchRunProcess("dotnet", BenchQuote(cliDll) + " build --help", Path.GetTempPath())
    return run.ExitCode == 0 && run.Stdout.IndexOf("--stats", StringComparison.Ordinal) >= 0
}

// WHICH WAY A MEASURED COMMAND RUNS, decided for the child alone. `nlc check|build|test` route to a
// warm per-workspace server by default and start one on first use, so a run without `--daemon` sets
// `NLC_NO_DAEMON=1` (the in-process baseline, and no server left behind), and a `--daemon` run clears
// every switch that would keep it in-process — including `NLC_DAEMON_CHILD`, which a test host sets
// for everything its tests start.
func AgentLoopDaemonEnvironment(daemon: bool): Dictionary<string, string?> {
    environment := new Dictionary<string, string?>()
    if daemon {
        removed: string? = null
        environment["NLC_NO_DAEMON"] = removed
        environment["NLC_DAEMON_CHILD"] = removed
        environment["NLC_DAEMON"] = removed
        environment["CI"] = removed
    } else {
        environment["NLC_NO_DAEMON"] = "1"
    }

    return environment
}

// THE DAEMON IS STARTED THROUGH THE APPHOST beside `Cli.dll` when there is one. (Both product bugs
// below were fixed on speed/daemon-first — the server is always this same binary and never inherits
// its caller's streams — and `tests/native/daemon-exec` pins both; the two workarounds stay, harmless,
// so a base CLI from before the fix can still be measured.) Measured on
// 2026-10-05: `dotnet Cli.dll daemon start` for a project OUTSIDE the repository fails ("Could not
// execute because the specified command or file was not found"), because a CLI whose process is
// `dotnet` looks for `src/NSharpLang.Cli` above the PROJECT to `dotnet run`, finds none under the temp
// directory, and falls back to `dotnet daemon run`. The apphost's process path is the CLI itself, so
// its start plan is `<Cli> daemon run`, which works anywhere.
//
// AND ITS OUTPUT GOES TO A FILE, NOT A PIPE. The started daemon inherits `daemon start`'s stdout, so a
// caller reading that stdout to end waits for the DAEMON to exit - measured: the first `--daemon`
// sample hung for ten minutes. `/bin/sh` redirects the command into a log file instead, which the
// daemon may keep open as long as it likes. (Paths are single-quoted: the harness's own temp
// directories never contain a quote.)
func AgentLoopDaemonCommand(cliDll: string, verb: string, projectDirectory: string): BenchProcessRun {
    arguments := " daemon " + verb + " --project '" + projectDirectory + "'"
    command := "dotnet '" + cliDll + "'" + arguments
    apphost := cliDll.Substring(0, cliDll.Length - ".dll".Length)
    if cliDll.EndsWith(".dll", StringComparison.Ordinal) && File.Exists(apphost) {
        command = "'" + apphost + "'" + arguments
    }

    log := Path.Combine(Path.GetTempPath(), "nsharp-agent-loop-daemon-" + BenchLongText(DateTime.UtcNow.Ticks) + ".log")
    startInfo := new ProcessStartInfo { FileName: "/bin/sh" }
    startInfo.ArgumentList.Add("-c")
    startInfo.ArgumentList.Add(command + " > '" + log + "' 2>&1")
    startInfo.WorkingDirectory = Path.GetTempPath()
    startInfo.UseShellExecute = false
    startInfo.Environment.Remove("NLC_NO_DAEMON")
    startInfo.Environment.Remove("NLC_DAEMON_CHILD")
    process := new Process { StartInfo: startInfo }
    startTicks := DateTime.UtcNow.Ticks
    process.Start()
    process.WaitForExit()
    exitCode := process.ExitCode
    process.Dispose()
    wallMs := (DateTime.UtcNow.Ticks - startTicks) / 10000

    output := ""
    if File.Exists(log) {
        output = File.ReadAllText(log)
        File.Delete(log)
    }

    return new BenchProcessRun(exitCode, output, output, wallMs)
}

// ─── ONE SCENARIO, N SAMPLES ──────────────────────────────────────────────────────────────────

func AgentLoopModeCold(): string {
    return "cold"
}

func AgentLoopModeWarm(): string {
    return "warm"
}

// One row of the result table: one size, one scenario, one mode, over every sample.
class AgentLoopRow {
    Size: string
    Scenario: string
    Mode: string
    Samples: int
    ExitCode: int
    MedianWallMs: long
    MedianCpuMs: long
    MedianPeakRssBytes: long
    Counters: AgentLoopCounters?
    CountersStable: bool
    SourceLines: long
    Failure: string

    constructor(size: string, scenario: string, mode: string) {
        Size = size
        Scenario = scenario
        Mode = mode
        Samples = 0
        ExitCode = 0
        MedianWallMs = -1
        MedianCpuMs = -1
        MedianPeakRssBytes = -1
        Counters = null
        CountersStable = true
        SourceLines = -1
        Failure = ""
    }
}

func AgentLoopRowKey(size: string, scenario: string, mode: string): string {
    return size + " / " + scenario + " / " + mode
}

func AgentLoopFindRow(rows: List<AgentLoopRow>, size: string, scenario: string, mode: string): AgentLoopRow? {
    i := 0
    while i < rows.Count {
        row := rows[i]
        if row.Size == size && row.Scenario == scenario && row.Mode == mode {
            return row
        }

        i = i + 1
    }

    return null
}

// Fold one sample's run into its row: the first non-zero exit code wins, the counters must agree
// across samples (a structural counter that varies between identical inputs cannot be gated
// exactly, and saying so is the finding), and the timings are kept for the median.
func AgentLoopRecordRun(row: AgentLoopRow, run: AgentLoopRun, wall: long[], cpu: long[], rss: long[]) {
    index := row.Samples
    wall[index] = run.WallMs
    cpu[index] = run.CpuMs
    rss[index] = run.PeakRssBytes
    if row.ExitCode == 0 && run.ExitCode != 0 {
        row.ExitCode = run.ExitCode
    }

    if row.Failure == "" && run.Detail != "" {
        row.Failure = run.Detail
    }

    if index == 0 {
        row.Counters = run.Counters
    } else {
        first := row.Counters
        current := run.Counters
        if first == null || current == null {
            if first != null || current != null {
                row.CountersStable = false
            }
        } else if !AgentLoopCountersEqual(first ?? AgentLoopZeroCounters(), current ?? AgentLoopZeroCounters()) {
            row.CountersStable = false
        }
    }

    row.Samples = index + 1
}

func AgentLoopFinishRow(row: AgentLoopRow, wall: long[], cpu: long[], rss: long[]) {
    row.MedianWallMs = BenchMedian(wall, row.Samples)
    row.MedianCpuMs = BenchMedian(cpu, row.Samples)
    row.MedianPeakRssBytes = BenchMedian(rss, row.Samples)
}

func AgentLoopSampleDirectory(): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-agent-loop-" + BenchLongText(DateTime.UtcNow.Ticks))
    BenchDeleteDirectory(directory)
    return directory
}

// Measure one scenario on one size: `samples` fresh copies, each primed, edited, then run cold and
// warm. Returns the cold row and the warm row, in that order.
func AgentLoopMeasureScenario(
    cliDll: string,
    repositoryRoot: string,
    size: AgentLoopSize,
    scenario: AgentLoopScenario,
    samples: int,
    useStats: bool,
    daemon: bool
): List<AgentLoopRow> {
    cold := new AgentLoopRow(size.Name, scenario.Id, AgentLoopModeCold())
    warm := new AgentLoopRow(size.Name, scenario.Id, AgentLoopModeWarm())
    coldWall := new long[](samples)
    coldCpu := new long[](samples)
    coldRss := new long[](samples)
    warmWall := new long[](samples)
    warmCpu := new long[](samples)
    warmRss := new long[](samples)

    sample := 0
    while sample < samples {
        directory := AgentLoopSampleDirectory()
        daemonStarted := false
        try {
            AgentLoopMaterialize(repositoryRoot, size, directory)
            if sample == 0 {
                lines := AgentLoopSourceLines(directory)
                cold.SourceLines = lines
                warm.SourceLines = lines
            }

            if daemon {
                started := AgentLoopDaemonCommand(cliDll, "start", directory)
                daemonStarted = started.ExitCode == 0
                if started.ExitCode != 0 {
                    cold.Failure = "nlc daemon start exited " + BenchIntText(started.ExitCode) + ": " + BenchTruncate(started.Stderr.Trim(), 400)
                    cold.ExitCode = started.ExitCode
                }
            }

            prime := AgentLoopRunCommand(cliDll, directory, scenario.Command, useStats, daemon)
            if prime.ExitCode != 0 && cold.Failure == "" {
                cold.Failure = "the prime run of nlc " + scenario.Command + " exited " + BenchIntText(prime.ExitCode) + ": " + prime.Detail
                cold.ExitCode = prime.ExitCode
            }

            editRefusal := AgentLoopApplyEdit(size, directory, scenario.Edit, sample + 1)
            if editRefusal != "" && cold.Failure == "" {
                cold.Failure = "the " + scenario.Edit + " edit could not be applied: " + editRefusal
                cold.ExitCode = 1
            }

            AgentLoopRecordRun(cold, AgentLoopRunCommand(cliDll, directory, scenario.Command, useStats, daemon), coldWall, coldCpu, coldRss)
            AgentLoopRecordRun(warm, AgentLoopRunCommand(cliDll, directory, scenario.Command, useStats, daemon), warmWall, warmCpu, warmRss)
        } finally {
            // Stopped before its directory goes, on a failing sample too: a daemon left behind
            // would hold its socket under a deleted tree until its idle timeout.
            if daemonStarted {
                _ = AgentLoopDaemonCommand(cliDll, "stop", directory)
            }
            BenchDeleteDirectory(directory)
        }

        sample = sample + 1
    }

    AgentLoopFinishRow(cold, coldWall, coldCpu, coldRss)
    AgentLoopFinishRow(warm, warmWall, warmCpu, warmRss)
    rows := new List<AgentLoopRow>()
    rows.Add(cold)
    rows.Add(warm)
    return rows
}

// Every scenario on every named size, in table order. `printProgress` is false inside the gate,
// which must not write a byte to stdout or stderr.
func AgentLoopMeasureMatrix(
    cliDll: string,
    repositoryRoot: string,
    sizeNames: List<string>,
    samples: int,
    useStats: bool,
    daemon: bool,
    printProgress: bool
): List<AgentLoopRow> {
    rows := new List<AgentLoopRow>()
    scenarios := AgentLoopScenarios()
    i := 0
    while i < sizeNames.Count {
        size := AgentLoopFindSize(sizeNames[i])
        if size == null {
            throw new InvalidOperationException("unknown agent-loop size '" + sizeNames[i] + "'")
        }

        j := 0
        while j < scenarios.Count {
            measured := AgentLoopMeasureScenario(cliDll, repositoryRoot, size ?? new AgentLoopSize("", "", 0, 0), scenarios[j], samples, useStats, daemon)
            k := 0
            while k < measured.Count {
                rows.Add(measured[k])
                if printProgress {
                    print "  " + AgentLoopRowKey(measured[k].Size, measured[k].Scenario, measured[k].Mode) + ": " + BenchLongText(measured[k].MedianWallMs) + " ms" + AgentLoopProgressCounters(measured[k])
                }
                k = k + 1
            }

            j = j + 1
        }

        i = i + 1
    }

    return rows
}

func AgentLoopProgressCounters(row: AgentLoopRow): string {
    counters := row.Counters
    if counters == null {
        return ""
    }

    return ", " + AgentLoopCountersText(counters ?? AgentLoopZeroCounters())
}

// ─── THE BASELINE ─────────────────────────────────────────────────────────────────────────────

class AgentLoopBaseline {
    SchemaVersion: int
    MeasuredAt: string
    CliCommit: string
    Machine: string
    LoadAtStart: string
    LoadAtEnd: string
    TimingJudgeable: bool
    Runs: int
    ToleranceThousandths: long
    Rows: List<AgentLoopRow>

    constructor() {
        SchemaVersion = 0
        MeasuredAt = ""
        CliCommit = ""
        Machine = ""
        LoadAtStart = ""
        LoadAtEnd = ""
        TimingJudgeable = false
        Runs = 0
        ToleranceThousandths = 0
        Rows = new List<AgentLoopRow>()
    }
}

func AgentLoopBaselineRelativePath(): string {
    return "tests/fixtures/agent-loop/agent-loop-baseline.golden.json"
}

func AgentLoopBaselinePath(repositoryRoot: string): string {
    return BenchAbsoluteProjectPath(repositoryRoot, AgentLoopBaselineRelativePath())
}

func AgentLoopJsonString(value: string): string {
    return JsonSerializer.Serialize<string>(value)
}

func AgentLoopAppendField(builder: StringBuilder, indent: string, name: string, value: string, last: bool) {
    builder.Append(indent)
    builder.Append(AgentLoopJsonString(name))
    builder.Append(": ")
    builder.Append(value)
    if !last {
        builder.Append(",")
    }
    builder.Append("\n")
}

func AgentLoopBoolJson(value: bool): string {
    if value {
        return "true"
    }

    return "false"
}

// The golden file, written by the harness itself (`--write-baseline`), so its shape can only be
// the shape `AgentLoopParseBaseline` reads.
func AgentLoopBaselineJson(baseline: AgentLoopBaseline): string {
    builder := new StringBuilder()
    builder.Append("{\n")
    AgentLoopAppendField(builder, "  ", "schemaVersion", BenchIntText(baseline.SchemaVersion), false)
    AgentLoopAppendField(builder, "  ", "kind", AgentLoopJsonString("nsharp.agent-loop-baseline"), false)
    AgentLoopAppendField(builder, "  ", "policy", AgentLoopJsonString(AgentLoopBaselinePolicy()), false)
    AgentLoopAppendField(builder, "  ", "measuredAt", AgentLoopJsonString(baseline.MeasuredAt), false)
    AgentLoopAppendField(builder, "  ", "cliCommit", AgentLoopJsonString(baseline.CliCommit), false)
    AgentLoopAppendField(builder, "  ", "machine", AgentLoopJsonString(baseline.Machine), false)
    AgentLoopAppendField(builder, "  ", "loadAtStart", AgentLoopJsonString(baseline.LoadAtStart), false)
    AgentLoopAppendField(builder, "  ", "loadAtEnd", AgentLoopJsonString(baseline.LoadAtEnd), false)
    AgentLoopAppendField(builder, "  ", "timingJudgeable", AgentLoopBoolJson(baseline.TimingJudgeable), false)
    AgentLoopAppendField(builder, "  ", "runs", BenchIntText(baseline.Runs), false)
    AgentLoopAppendField(builder, "  ", "toleranceFactor", BenchFormatFixed3(baseline.ToleranceThousandths), false)
    builder.Append("  \"rows\": [\n")
    i := 0
    while i < baseline.Rows.Count {
        row := baseline.Rows[i]
        builder.Append("    {\n")
        AgentLoopAppendField(builder, "      ", "size", AgentLoopJsonString(row.Size), false)
        AgentLoopAppendField(builder, "      ", "scenario", AgentLoopJsonString(row.Scenario), false)
        AgentLoopAppendField(builder, "      ", "mode", AgentLoopJsonString(row.Mode), false)
        AgentLoopAppendField(builder, "      ", "sourceLines", BenchLongText(row.SourceLines), false)
        AgentLoopAppendField(builder, "      ", "exitCode", BenchIntText(row.ExitCode), false)
        AgentLoopAppendField(builder, "      ", "medianWallMs", BenchLongText(row.MedianWallMs), false)
        AgentLoopAppendField(builder, "      ", "medianCpuMs", BenchLongText(row.MedianCpuMs), false)
        AgentLoopAppendField(builder, "      ", "medianPeakRssBytes", BenchLongText(row.MedianPeakRssBytes), false)
        counters := row.Counters ?? new AgentLoopCounters(-1, -1, -1, -1, -1, -1)
        builder.Append("      \"counters\": {")
        builder.Append("\"filesParsed\": " + BenchLongText(counters.FilesParsed))
        builder.Append(", \"emitParses\": " + BenchLongText(counters.EmitParses))
        builder.Append(", \"filesAnalyzed\": " + BenchLongText(counters.FilesAnalyzed))
        builder.Append(", \"assembliesEmitted\": " + BenchLongText(counters.AssembliesEmitted))
        builder.Append(", \"referenceAssembliesLoaded\": " + BenchLongText(counters.ReferenceAssembliesLoaded))
        builder.Append(", \"processesSpawned\": " + BenchLongText(counters.ProcessesSpawned))
        builder.Append("}\n")
        builder.Append("    }")
        if i + 1 < baseline.Rows.Count {
            builder.Append(",")
        }
        builder.Append("\n")
        i = i + 1
    }

    builder.Append("  ]\n}\n")
    return builder.ToString() ?? ""
}

func AgentLoopBaselinePolicy(): string {
    return "Structural counters are gated exactly: a decrease is ratcheted into this file in the same commit, an increase is a regression to fix. Wall time is judged only when timingJudgeable is true and the machine is below the load threshold. No threshold here is loosened without the owner."
}

func AgentLoopParseBaseline(json: string): AgentLoopBaseline {
    baseline := new AgentLoopBaseline()
    document := JsonDocument.Parse(json)
    root := document.RootElement
    baseline.SchemaVersion = root.GetProperty("schemaVersion").GetInt32()
    baseline.MeasuredAt = root.GetProperty("measuredAt").GetString() ?? ""
    baseline.CliCommit = root.GetProperty("cliCommit").GetString() ?? ""
    baseline.Machine = root.GetProperty("machine").GetString() ?? ""
    baseline.LoadAtStart = root.GetProperty("loadAtStart").GetString() ?? ""
    baseline.LoadAtEnd = root.GetProperty("loadAtEnd").GetString() ?? ""
    baseline.TimingJudgeable = root.GetProperty("timingJudgeable").GetBoolean()
    baseline.Runs = root.GetProperty("runs").GetInt32()
    baseline.ToleranceThousandths = BenchParseFixed3(root.GetProperty("toleranceFactor").GetRawText() ?? "")
    rows := root.GetProperty("rows")
    i := 0
    while i < rows.GetArrayLength() {
        element := rows[i]
        row := new AgentLoopRow(
            element.GetProperty("size").GetString() ?? "",
            element.GetProperty("scenario").GetString() ?? "",
            element.GetProperty("mode").GetString() ?? ""
        )
        row.SourceLines = element.GetProperty("sourceLines").GetInt64()
        row.ExitCode = element.GetProperty("exitCode").GetInt32()
        row.MedianWallMs = element.GetProperty("medianWallMs").GetInt64()
        row.MedianCpuMs = element.GetProperty("medianCpuMs").GetInt64()
        row.MedianPeakRssBytes = element.GetProperty("medianPeakRssBytes").GetInt64()
        row.Counters = AgentLoopCountersFromElement(element.GetProperty("counters"))
        row.Samples = baseline.Runs
        baseline.Rows.Add(row)
        i = i + 1
    }

    document.Dispose()
    return baseline
}

// `""` when the baseline can be gated against; the reason otherwise.
func AgentLoopBaselineRefusal(baseline: AgentLoopBaseline): string {
    if baseline.SchemaVersion != 1 {
        return "agent-loop baseline schemaVersion " + BenchIntText(baseline.SchemaVersion) + " is not the supported version 1"
    }

    if baseline.Rows.Count == 0 {
        return "agent-loop baseline has no rows: measure one with --agent-loop --write-baseline " + AgentLoopBaselineRelativePath()
    }

    if baseline.ToleranceThousandths <= 0 {
        return "agent-loop baseline toleranceFactor is missing or not a positive decimal"
    }

    i := 0
    while i < baseline.Rows.Count {
        row := baseline.Rows[i]
        counters := row.Counters
        if counters == null || (counters ?? AgentLoopZeroCounters()).FilesParsed < 0 {
            return "agent-loop baseline row " + AgentLoopRowKey(row.Size, row.Scenario, row.Mode) + " has no measured counters"
        }

        if row.MedianWallMs <= 0 {
            return "agent-loop baseline row " + AgentLoopRowKey(row.Size, row.Scenario, row.Mode) + " has no measured wall time"
        }

        i = i + 1
    }

    return ""
}

// The rows a baseline may NOT be written from: a failed run, or counters that differed between
// identical samples. A budget taken from either would gate a number nobody can reproduce.
func AgentLoopUnbaselinableRows(rows: List<AgentLoopRow>): List<string> {
    refusals := new List<string>()
    i := 0
    while i < rows.Count {
        row := rows[i]
        key := AgentLoopRowKey(row.Size, row.Scenario, row.Mode)
        if row.ExitCode != 0 || row.Failure != "" {
            refusals.Add(key + ": exited " + BenchIntText(row.ExitCode) + " - " + row.Failure)
        } else if !row.CountersStable || row.Counters == null {
            refusals.Add(key + ": counters missing or different between identical samples")
        }

        i = i + 1
    }

    return refusals
}

// ─── THE VERDICT ──────────────────────────────────────────────────────────────────────────────

// Why a counter moved, in the words the reader has to act on.
func AgentLoopCounterChange(name: string, baseline: long, observed: long): string {
    if observed == baseline {
        return ""
    }

    if observed < baseline {
        return name + " " + BenchLongText(baseline) + " -> " + BenchLongText(observed) + " (less work: ratchet the baseline down in this commit)"
    }

    return name + " " + BenchLongText(baseline) + " -> " + BenchLongText(observed) + " (MORE work: a regression; fix it - raising the baseline needs the owner)"
}

func AgentLoopAppendChange(changes: List<string>, change: string) {
    if change != "" {
        changes.Add(change)
    }
}

func AgentLoopCounterChanges(baseline: AgentLoopCounters, observed: AgentLoopCounters): List<string> {
    changes := new List<string>()
    AgentLoopAppendChange(changes, AgentLoopCounterChange("filesParsed", baseline.FilesParsed, observed.FilesParsed))
    AgentLoopAppendChange(changes, AgentLoopCounterChange("emitParses", baseline.EmitParses, observed.EmitParses))
    AgentLoopAppendChange(changes, AgentLoopCounterChange("filesAnalyzed", baseline.FilesAnalyzed, observed.FilesAnalyzed))
    AgentLoopAppendChange(changes, AgentLoopCounterChange("assembliesEmitted", baseline.AssembliesEmitted, observed.AssembliesEmitted))
    AgentLoopAppendChange(changes, AgentLoopCounterChange("referenceAssembliesLoaded", baseline.ReferenceAssembliesLoaded, observed.ReferenceAssembliesLoaded))
    AgentLoopAppendChange(changes, AgentLoopCounterChange("processesSpawned", baseline.ProcessesSpawned, observed.ProcessesSpawned))
    return changes
}

// The half no machine load can excuse: every observed row exited 0 as its baseline row did, its
// counters were stable across samples, and they equal the baseline's exactly.
func AgentLoopCounterFailures(baseline: AgentLoopBaseline, observed: List<AgentLoopRow>): List<string> {
    failures := new List<string>()
    i := 0
    while i < observed.Count {
        row := observed[i]
        key := AgentLoopRowKey(row.Size, row.Scenario, row.Mode)
        if row.ExitCode != 0 || row.Failure != "" {
            failures.Add(key + ": exited " + BenchIntText(row.ExitCode) + " - " + row.Failure)
        } else if !row.CountersStable {
            failures.Add(key + ": the structural counters differed between identical samples, so they cannot be gated exactly; find the nondeterminism")
        } else {
            expected := AgentLoopFindRow(baseline.Rows, row.Size, row.Scenario, row.Mode)
            observedCounters := row.Counters
            if expected == null {
                failures.Add(key + ": has no baseline row; add it with --agent-loop --write-baseline")
            } else if observedCounters == null {
                failures.Add(key + ": the CLI reported no counters")
            } else {
                baselineRow := expected ?? row
                changes := AgentLoopCounterChanges(baselineRow.Counters ?? AgentLoopZeroCounters(), observedCounters ?? AgentLoopZeroCounters())
                if changes.Count > 0 {
                    failures.Add(key + ": " + String.Join("; ", changes))
                }
            }
        }

        i = i + 1
    }

    return failures
}

func AgentLoopCounterNotAbove(baseline: AgentLoopCounters, observed: AgentLoopCounters): bool {
    return observed.FilesParsed <= baseline.FilesParsed && observed.EmitParses <= baseline.EmitParses && observed.FilesAnalyzed <= baseline.FilesAnalyzed && observed.AssembliesEmitted <= baseline.AssembliesEmitted && observed.ReferenceAssembliesLoaded <= baseline.ReferenceAssembliesLoaded && observed.ProcessesSpawned <= baseline.ProcessesSpawned
}

// THE RATCHET (`--ratchet`). Copy each measured row's counters into the baseline when NONE of them
// went up, and refuse the rows where one did: an improvement lands in the same commit as the change
// that made it, and a regression can never be written in by the tool that is meant to catch it.
// Wall-time fields are left exactly as they were, so a ratchet run on a busy machine cannot loosen a
// timing budget either. Returns the refusals; the baseline is changed only for the rows accepted.
func AgentLoopRatchetCounters(baseline: AgentLoopBaseline, observed: List<AgentLoopRow>): List<string> {
    refusals := new List<string>()
    i := 0
    while i < observed.Count {
        row := observed[i]
        key := AgentLoopRowKey(row.Size, row.Scenario, row.Mode)
        expected := AgentLoopFindRow(baseline.Rows, row.Size, row.Scenario, row.Mode)
        observedCounters := row.Counters
        if row.ExitCode != 0 || row.Failure != "" || !row.CountersStable || observedCounters == null {
            refusals.Add(key + ": not ratcheted - the run failed or its counters were unstable")
        } else if expected == null {
            refusals.Add(key + ": not ratcheted - no baseline row (a new row is written with --write-baseline, by the owner)")
        } else {
            baselineRow := expected ?? row
            current := baselineRow.Counters ?? AgentLoopZeroCounters()
            next := observedCounters ?? current
            if AgentLoopCounterNotAbove(current, next) {
                baselineRow.Counters = next
            } else {
                refusals.Add(key + ": not ratcheted - " + String.Join("; ", AgentLoopCounterChanges(current, next)))
            }
        }

        i = i + 1
    }

    return refusals
}

func AgentLoopTimingLimitMs(baselineWallMs: long, toleranceThousandths: long): long {
    return baselineWallMs * toleranceThousandths / 1000
}

// The half that only means something on a quiet machine compared with a baseline that was itself
// taken on one. `""` when every observed median is inside the limit.
func AgentLoopTimingFailures(baseline: AgentLoopBaseline, observed: List<AgentLoopRow>): List<string> {
    failures := new List<string>()
    i := 0
    while i < observed.Count {
        row := observed[i]
        expected := AgentLoopFindRow(baseline.Rows, row.Size, row.Scenario, row.Mode)
        if expected != null {
            baselineRow := expected ?? row
            limit := AgentLoopTimingLimitMs(baselineRow.MedianWallMs, baseline.ToleranceThousandths)
            if row.MedianWallMs > limit {
                failures.Add(AgentLoopRowKey(row.Size, row.Scenario, row.Mode) + ": median wall " + BenchLongText(row.MedianWallMs) + " ms over the limit " + BenchLongText(limit) + " ms (baseline " + BenchLongText(baselineRow.MedianWallMs) + " ms x" + BenchFormatFixed3(baseline.ToleranceThousandths) + ")")
            }
        }

        i = i + 1
    }

    return failures
}

// Why the timing half was not judged, or `""` when it was.
func AgentLoopTimingUnjudgedReason(baseline: AgentLoopBaseline, load: BenchMachineLoad, skipRequested: bool): string {
    if skipRequested {
        return "SYSTEMS_BENCH=skip"
    }

    if !baseline.TimingJudgeable {
        return "the baseline's own timings were taken on a loaded machine (load " + baseline.LoadAtStart + " at start), so they are a record, not a budget; re-measure on an idle machine to make them one"
    }

    if BenchLoadRefusesTimingJudgement(load) {
        return "the one-minute load average is " + BenchLoadText(load.LoadThousandths) + " on " + BenchCountText(load.Cores) + " logical cores, at or above the " + BenchFormatFixed3(BenchLoadThresholdThousandths(load.Cores)) + " threshold"
    }

    return ""
}

// ─── THE TABLE ────────────────────────────────────────────────────────────────────────────────

func AgentLoopMegabytes(bytes: long): string {
    if bytes < 0 {
        return ""
    }

    return BenchFormatMegabytes(bytes)
}

func AgentLoopCounterCell(observed: long, compare: long, hasCompare: bool): string {
    if !hasCompare || compare == observed {
        return BenchLongText(observed)
    }

    return BenchLongText(observed) + " (" + BenchLongText(compare) + ")"
}

func AgentLoopWallCell(observed: long, compare: long, hasCompare: bool): string {
    if !hasCompare || compare <= 0 {
        return BenchLongText(observed)
    }

    percent := (observed - compare) * 100 / compare
    sign := ""
    if percent > 0 {
        sign = "+"
    }

    return BenchLongText(observed) + " (" + BenchLongText(compare) + ", " + sign + BenchLongText(percent) + "%)"
}

// The markdown table: one line per size x scenario x mode. With `compare` rows (the committed
// baseline, or a base CLI measured in the same run), every cell that differs carries the compared
// value in parentheses, and the wall cell its percentage change.
func AgentLoopRenderTable(rows: List<AgentLoopRow>, compare: List<AgentLoopRow>?, compareLabel: string): string {
    builder := new StringBuilder()
    if compare != null {
        BenchAppendLine(builder, "Parenthesised values are " + compareLabel + "; a cell without one is unchanged.")
        BenchAppendLine(builder, "")
    }

    BenchAppendLine(builder, "| size | lines | scenario | mode | exit | wall ms | cpu ms | peak RSS MB | parsed | emit parses | analyzed | emitted | refs loaded | spawned |")
    BenchAppendLine(builder, "|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    i := 0
    while i < rows.Count {
        row := rows[i]
        compareRow: AgentLoopRow? = null
        if compare != null {
            compareRow = AgentLoopFindRow(compare ?? rows, row.Size, row.Scenario, row.Mode)
        }

        hasCompare := compareRow != null
        other := compareRow ?? row
        counters := row.Counters ?? new AgentLoopCounters(-1, -1, -1, -1, -1, -1)
        otherCounters := other.Counters ?? new AgentLoopCounters(-1, -1, -1, -1, -1, -1)
        builder.Append("| " + row.Size + " | " + BenchLongText(row.SourceLines) + " | " + row.Scenario + " | " + row.Mode + " | " + BenchIntText(row.ExitCode))
        builder.Append(" | " + AgentLoopWallCell(row.MedianWallMs, other.MedianWallMs, hasCompare))
        builder.Append(" | " + BenchLongText(row.MedianCpuMs))
        builder.Append(" | " + AgentLoopMegabytes(row.MedianPeakRssBytes))
        builder.Append(" | " + AgentLoopCounterCell(counters.FilesParsed, otherCounters.FilesParsed, hasCompare))
        builder.Append(" | " + AgentLoopCounterCell(counters.EmitParses, otherCounters.EmitParses, hasCompare))
        builder.Append(" | " + AgentLoopCounterCell(counters.FilesAnalyzed, otherCounters.FilesAnalyzed, hasCompare))
        builder.Append(" | " + AgentLoopCounterCell(counters.AssembliesEmitted, otherCounters.AssembliesEmitted, hasCompare))
        builder.Append(" | " + AgentLoopCounterCell(counters.ReferenceAssembliesLoaded, otherCounters.ReferenceAssembliesLoaded, hasCompare))
        builder.Append(" | " + AgentLoopCounterCell(counters.ProcessesSpawned, otherCounters.ProcessesSpawned, hasCompare))
        BenchAppendLine(builder, " |")
        i = i + 1
    }

    return builder.ToString() ?? ""
}

// The rows of `rows` whose size is one of `sizeNames`, in order.
func AgentLoopRowsForSizes(rows: List<AgentLoopRow>, sizeNames: List<string>): List<AgentLoopRow> {
    selected := new List<AgentLoopRow>()
    i := 0
    while i < rows.Count {
        if sizeNames.Contains(rows[i].Size) {
            selected.Add(rows[i])
        }

        i = i + 1
    }

    return selected
}

// The gate's records, beside the compile-time gate's: one line saying what the gate did, and the
// table it measured. Best effort, like `BenchWriteGateRecord`: a log that cannot be written must not
// turn a gate red.
func AgentLoopWriteGateRecord(repositoryRoot: string, line: string, table: string): bool {
    directory := Path.Combine(Path.Combine(repositoryRoot, "artifacts"), "agent-loop")
    try {
        Directory.CreateDirectory(directory)
        File.WriteAllText(Path.Combine(directory, "last-gate-run.txt"), line + "\n")
        File.WriteAllText(Path.Combine(directory, "last-gate-run.md"), line + "\n\n" + table)
        return true
    } catch {
        return false
    }
}

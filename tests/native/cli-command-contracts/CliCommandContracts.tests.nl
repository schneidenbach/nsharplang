namespace NSharpLang.CliCommandContracts.Tests

import System
import System.Diagnostics
import System.IO
import System.Text.Json


// THE SHIPPED `nlc` COMMAND CONTRACTS, PROVEN AS PROCESSES.
//
// These replace the rows of `tests/CliCommandTests.cs` that the estate CANNOT make. The mechanical
// decode of that file split its 96 bucket-(a) bodies three ways by what they READ: 70 call an
// N#-owned function with in-memory arguments and nothing else, 14 ALSO drive an N#-owned command's
// `Execute` through a console capture, and 12 mix kernel rows with rows driven by a C#-owned entry
// point. The first group went to `src/NSharpLang.Compiler.BootstrapServices/*.tests.nl`. This
// project is where the second group's console rows land.
//
// WHY THE SPLIT IS FORCED AND NOT A PREFERENCE — THE MEASUREMENT. A `.tests.nl` in the estate can
// call `TreeCommand.Execute(...)` directly, because it compiles into the same assembly. What it
// cannot do is SEE what that call printed: `Console.SetOut` declines on this emit path with
//
//     NL103 ... Declined at emit.call.static-member-unmodeled: static call 'Console.SetOut'
//     with 1 argument(s) is not modeled
//
// measured out of repository on a two-line probe. Every row below is therefore about something
// only a process can show — an exit code, or which STREAM a sentence reached — and the route is
// the SHIPPED CLI rather than an in-process call, which is strictly stronger than the C# had:
// the deleted bodies invoked `TreeCommand.Execute` directly and so never proved that
// `nlc tree` REACHES `TreeCommand` at all.
//
// THE STDERR CLAIMS ARE NOT VACUOUS HERE, AND THAT IS CHECKED. Slice 40 found that
// `nlc check --systems-report` cannot write to stderr at all, which made a whole family of
// `IsNullOrWhiteSpace(stderr)` assertions structurally unfailable. Each silence claim below is
// therefore paired with a NEIGHBOUR on the same command that DOES write to stderr — the
// missing-directory runs — so the pair proves the stream is reachable and the silence is a fact.


// ─── THE SPAWN KERNEL ─────────────────────────────────────────────────────────────────────────

class CliRun {
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
func RunProcess(fileName: string, arguments: string, workingDirectory: string): CliRun {
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
    return new CliRun(exitCode, stdout, stderr)
}


// ─── FINDING THE BUILT CLI ────────────────────────────────────────────────────────────────────

func CliRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln"))
            && Directory.Exists(Path.Combine(directory, "src"))
            && Directory.Exists(Path.Combine(directory, "tests")) {
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

func CliDll(): string {
    root := CliRepositoryRoot()
    binDirectory := Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug")
    cliDll := Path.Combine(Path.Combine(binDirectory, "net10.0"), "Cli.dll")
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The built N# CLI was not found beside the repository root.")
    }

    return cliDll
}

func Nlc(arguments: string): CliRun {
    return RunProcess("dotnet", "\"" + CliDll() + "\" " + arguments, Path.GetTempPath())
}


// ─── A TEMPORARY PROJECT ON DISK ──────────────────────────────────────────────────────────────

func NewTempDirectory(prefix: string): string {
    directory := Path.Combine(Path.GetTempPath(), prefix + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func MissingDirectoryPath(prefix: string): string {
    return Path.Combine(Path.GetTempPath(), prefix + "-" + Guid.NewGuid().ToString("N"))
}


// ─── READING A JSON ARRAY ─────────────────────────────────────────────────────────────────────
//
// A `JsonElement` INDEXER declines at emit — measured here as
// `emit.local.initializer` on `root.GetProperty("a")[0]` — so arrays are walked with
// `EnumerateArray`, which is the spelling `tests/native/query-integration` and
// `tests/native/systems-proof-corpus` already use.
func ElementAt(items: JsonElement, wanted: int): JsonElement {
    enumerator := items.EnumerateArray()
    seen := 0
    while enumerator.MoveNext() {
        if seen == wanted {
            return enumerator.Current
        }

        seen = seen + 1
    }

    throw new InvalidOperationException("The JSON array has no element at index " + wanted.ToString() + ".")
}

func TextOf(element: JsonElement): string {
    return element.GetString() ?? ""
}

// The envelope reports the project root as a fully-resolved, forward-slashed path. The deleted C#
// compared against a private `NormalizePath` helper that did exactly this substitution.
func NormalizedFullPath(path: string): string {
    return Path.GetFullPath(path).Replace("\\", "/")
}


// ═══ THE HELP CONTRACT, ONE ROW PER COMMAND ═══════════════════════════════════════════════════
//
// The deleted C# made this claim once per command, always the same three assertions: exit 0, a
// silent stderr, and the command's own `Usage:` line on stdout. It made them by calling
// `XCommand.Execute(new[] { "--help" })` in process. Here they are made against the real binary,
// so the dispatch from `nlc <name>` to the command is proven too. Six commands migrate in this
// slice; `tidy` and `completion` carry the same row and stay with their still-unmigrated bodies.

test "nlc tree --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("tree --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc tree [options]")
    assert run.Stdout.Contains("N# Dependency Tree")
}

test "nlc clean --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("clean --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc clean [options]")
    assert run.Stdout.Contains("N# Clean")
}

test "nlc env --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("env --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc env [options]")
    assert run.Stdout.Contains("N# Environment Info")
}

test "nlc audit --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("audit --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc audit [options]")
    assert run.Stdout.Contains("N# Security Audit")
}

test "nlc doctor --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("doctor --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc doctor [options]")
    assert run.Stdout.Contains("N# Doctor")
}

test "nlc daemon --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("daemon --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc daemon <command> [options]")
    assert run.Stdout.Contains("N# Analysis Daemon")
}


// ═══ THE `nlc tree` ENVELOPE ══════════════════════════════════════════════════════════════════
//
// Three deleted bodies —`TreeCommand_ProjectYmlOnly_EmitsStableJsonEnvelope`,
// `_TextUsesOutputMode` and `_JsonError_UsesGlobalErrorEnvelope` — wrote a project.yml to a temp
// directory and read the answer back. They are reproduced whole here, against the real binary.

func WriteTreeProject(directory: string, name: string, dependencies: string) {
    File.WriteAllText(Path.Combine(directory, "project.yml"),
        "name: " + name + "\n"
        + "entry: Program.nl\n"
        + "outputType: exe\n"
        + "targetFramework: net10.0\n"
        + "\n"
        + dependencies)
    File.WriteAllText(Path.Combine(directory, "Program.nl"), "func Main() {\n    print \"ok\"\n}\n")
}

func TreeDependenciesBlock(): string {
    return "dependencies:\n"
        + "  - framework: Microsoft.AspNetCore.App\n"
        + "  - nuget: Serilog\n"
        + "    version: 3.1.1\n"
        + "  - nuget: serilog\n"
        + "    version: 9.9.9\n"
}

test "nlc tree --json over a project.yml emits the versioned envelope and deduplicates dependencies" {
    directory := NewTempDirectory("nsharp-tree")
    try {
        WriteTreeProject(directory, "TreeContract", TreeDependenciesBlock())

        run := Nlc("tree --project \"" + directory + "\" --json")
        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("schemaVersion").GetInt32() == 2
        assert TextOf(root.GetProperty("command")) == "tree"
        assert root.GetProperty("ok").GetBoolean()
        assert TextOf(root.GetProperty("projectRoot")) == NormalizedFullPath(directory)
        assert TextOf(root.GetProperty("project").GetProperty("source")) == "project.yml"
        assert !root.GetProperty("capabilities").GetProperty("transitiveNuGetDependencies").GetBoolean()

        dependencies := root.GetProperty("dependencies")
        assert dependencies.GetArrayLength() == 2
        first := ElementAt(dependencies, 0)
        second := ElementAt(dependencies, 1)
        assert TextOf(first.GetProperty("kind")) == "framework"
        assert TextOf(first.GetProperty("name")) == "Microsoft.AspNetCore.App"
        assert TextOf(second.GetProperty("kind")) == "nuget"
        assert TextOf(second.GetProperty("name")) == "Serilog"
        assert TextOf(second.GetProperty("version")) == "3.1.1"

        assert root.GetProperty("transitiveDependencies").GetArrayLength() == 0
        assert root.GetProperty("summary").GetProperty("direct").GetInt32() == 2
        limitation := TextOf(ElementAt(root.GetProperty("limitations"), 0))
        assert limitation.Contains("direct runtime dependencies")
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc tree takes the LAST parseable --depth, and a depth of zero empties the tree" {
    directory := NewTempDirectory("nsharp-tree-depth")
    try {
        WriteTreeProject(directory, "TreeContract", TreeDependenciesBlock())

        run := Nlc("tree --project \"" + directory + "\" --depth bad --depth 0 --json")
        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("maxDepth").GetInt32() == 0
        assert root.GetProperty("dependencies").GetArrayLength() == 0
        assert root.GetProperty("summary").GetProperty("direct").GetInt32() == 0
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc tree without --json renders text and emits no JSON envelope at all" {
    directory := NewTempDirectory("nsharp-tree-text")
    try {
        WriteTreeProject(directory, "TreeText", "dependencies:\n  - nuget: Serilog\n    version: 3.1.1\n")

        run := Nlc("tree --project \"" + directory + "\"")
        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0
        assert run.Stdout.Contains("TreeText (net10.0)")
        assert run.Stdout.Contains("Serilog@3.1.1 [nuget]")
        assert !run.Stdout.Contains("\"command\"")
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc tree --json over a missing directory uses the global error envelope and exits 1" {
    missing := MissingDirectoryPath("nsharp-tree-missing")

    run := Nlc("tree --project \"" + missing + "\" --json")
    assert run.ExitCode == 1
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("schemaVersion").GetInt32() == 1
    assert TextOf(root.GetProperty("command")) == "tree"
    assert !root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("projectRoot")) == NormalizedFullPath(missing)
    errorMessage := TextOf(root.GetProperty("error").GetProperty("message"))
    assert errorMessage.Contains("Project directory not found")
    document.Dispose()
}


// ═══ THE `nlc env` ENVELOPE ═══════════════════════════════════════════════════════════════════

test "nlc env renders text by default and names both versions it reports" {
    run := Nlc("env")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("nlc version:")
    assert run.Stdout.Contains("dotnet version:")
    assert !run.Stdout.Contains("\"command\"")
}

test "nlc env --json emits the versioned envelope with all eight reported facts present" {
    run := Nlc("env --json")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("schemaVersion").GetInt32() == 2
    assert TextOf(root.GetProperty("command")) == "env"
    assert root.GetProperty("ok").GetBoolean()

    // The deleted C# asked `TryGetProperty(name, out _)` eight times and threw the value away.
    // Asking for the property outright is the same claim with a better failure: a missing key
    // names itself instead of failing an anonymous boolean.
    assert root.GetProperty("nlcVersion").ValueKind == JsonValueKind.String
    assert root.GetProperty("dotnetVersion").ValueKind == JsonValueKind.String
    assert root.GetProperty("runtime").ValueKind == JsonValueKind.String
    assert root.GetProperty("os").ValueKind == JsonValueKind.String
    assert root.GetProperty("arch").ValueKind == JsonValueKind.String
    assert root.GetProperty("nugetCachePath").ValueKind == JsonValueKind.String
    assert root.GetProperty("nsharpBinPath").ValueKind == JsonValueKind.String
    assert root.GetProperty("nsharpPackageCachePath").ValueKind == JsonValueKind.String
    document.Dispose()
}


// ═══ THE STDERR ROUTES, WHICH ARE ALSO THE ANTI-VACUITY CONTROLS ══════════════════════════════
//
// Every `err=0` row above is only meaningful if this command family CAN write to stderr. These
// four rows are the proof that it can, and they are the whole of two deleted bodies —
// `AuditCommand_MissingProjectDirectory_ReturnsHelpfulMessage` and
// `AuditCommand_NoCsproj_ReturnsHelpfulMessage` — plus the two `nlc clean` runs the deleted
// `CleanCommandKernels_SummarizesOptions` made at its tail.

test "nlc audit over a missing directory writes its remedy to STDERR, leaves stdout empty, exits 1" {
    missing := MissingDirectoryPath("nsharp-audit-missing")

    run := Nlc("audit --project \"" + missing + "\"")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Project directory not found: " + missing)
}

test "nlc audit over a directory with no csproj writes its remedy to STDERR and exits 1" {
    directory := NewTempDirectory("nsharp-audit-no-csproj")
    try {
        run := Nlc("audit --project \"" + directory + "\"")

        assert run.ExitCode == 1
        assert run.Stdout.Trim().Length == 0
        assert run.Stderr.Contains("No .csproj file found. Run 'nlc init' to create one.")
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc clean over a missing directory writes its remedy to STDERR and exits 1" {
    missing := MissingDirectoryPath("nsharp-clean-missing")

    run := Nlc("clean --project \"" + missing + "\"")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Project directory not found: " + missing)
}

test "nlc clean over an artifact-free directory reports so on STDOUT and exits 0" {
    directory := NewTempDirectory("nsharp-clean-empty")
    try {
        run := Nlc("clean --project \"" + directory + "\"")

        assert run.ExitCode == 0
        assert run.Stderr.Trim().Length == 0
        assert run.Stdout.Contains("No build artifacts found under " + directory + ".")
    } finally {
        Directory.Delete(directory, true)
    }
}


// ═══ THE TOP-LEVEL DISPATCH ═══════════════════════════════════════════════════════════════════
//
// The tail of `ProgramCommandKernels_SummarizesTopLevelCommands`. The deleted body reached
// `NSharpLang.Cli.Program.Execute` BY REFLECTION — `GetMethod("Execute", Static | Public |
// NonPublic).Invoke(...)` — which is exactly the reflective binding the AOT single-binary end
// state forbids. Spawning the binary answers the same questions without it.

test "nlc help exits 0 and writes a version-stamped header to stdout" {
    run := Nlc("help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.StartsWith("N# Compiler (nlc) ")
    assert run.Stdout.Contains("Usage: nlc <command> [options]")
    assert run.Stdout.Contains("Build & Run:")
    assert run.Stdout.Contains("Common Workflows:")
}

test "nlc --version writes one line whose text nlc help repeats in its header" {
    versionRun := Nlc("--version")

    assert versionRun.ExitCode == 0
    assert versionRun.Stderr.Trim().Length == 0
    assert versionRun.Stdout.StartsWith("nlc ")

    version := versionRun.Stdout.Trim().Substring(4)
    assert version.Length > 0

    helpRun := Nlc("help")
    assert helpRun.Stdout.StartsWith("N# Compiler (nlc) " + version)
}

test "an UPPERCASE command still dispatches, so the command name is case-insensitive" {
    run := Nlc("BUILD --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc build")
}

test "an unknown command exits 1 and writes one Error: line to STDERR, lowercased" {
    // The deleted body pinned the lowercasing implicitly, by comparing against the kernel called
    // with `"frobnicate"` while passing `"FROBNICATE"` on the command line. It is explicit here.
    run := Nlc("FROBNICATE")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Trim()
        == "Error: Unknown command: frobnicate. Run 'nlc help' to see available commands."
}

test "nlc query help exits 0, and an unknown query subcommand exits 1 through stderr" {
    helpRun := Nlc("query help")
    assert helpRun.ExitCode == 0
    assert helpRun.Stderr.Trim().Length == 0
    assert helpRun.Stdout.Contains("Usage: nlc query <command> [options]")

    unknownRun := Nlc("query wat")
    assert unknownRun.ExitCode == 1
    assert unknownRun.Stdout.Trim().Length == 0
    assert unknownRun.Stderr.Trim()
        == "Error: Unknown query subcommand: wat. Run 'nlc query help' for usage."
}


// ═══ SLICE 43: SEVEN MORE COMMANDS' HELP CONTRACTS ════════════════════════════════════════════
//
// The same three claims per command — exit 0, a silent stderr, the command's own `Usage:` line on
// stdout — for the seven whose kernel bodies migrate to the estate this slice. SIX of the seven
// were previously proven by an IN-PROCESS `XCommand.Execute(["--help"])` call, and FIVE of those
// six reach a command that is STILL a `.cs` file in `src/NSharpLang.Cli/Commands/` —
// `CheckCommand`, `FixCommand`, `LintCommand`, `WatchCommand` and `DocCommand`; only `TidyCommand`
// is N#-owned. So these rows are the only thing in the repository that proves `nlc check`
// dispatches to `CheckCommand` at all. The seventh, `format`, had no command wrapper in the
// deleted body at all — it went through the top-level dispatcher.

test "nlc check --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("check --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc check [options] [project-dir]")
    assert run.Stdout.Contains("N# Type Check")
}

test "nlc fix --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("fix --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc fix [options] [project-dir]")
    assert run.Stdout.Contains("N# Auto-Fix")
}

test "nlc lint --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("lint --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc lint [options] [files...]")
    assert run.Stdout.Contains("N# Lint")
}

test "nlc watch --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("watch --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc watch <check|build|test|lint|format>")
    assert run.Stdout.Contains("N# Watch")
}

test "nlc format --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("format --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc format [options] [files...]")
    assert run.Stdout.Contains("N# Format")
}

test "nlc tidy --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("tidy --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc tidy [options]")
    assert run.Stdout.Contains("N# Tidy")
}

test "nlc doc --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("doc --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc doc [options]")
    assert run.Stdout.Contains("N# API Documentation")
}


// ═══ SLICE 43: THE MISSING-DIRECTORY ROUTES ═══════════════════════════════════════════════════
//
// These are the anti-vacuity controls for the seven silences above: each of these five commands
// DOES write to stderr, so a `Stderr.Trim().Length == 0` claim on the same binary is a
// measurement rather than a structural fact. They also pin which stream the sentence reaches —
// the deleted C# asserted an EMPTY STDOUT beside each one, and that half is kept.
//
// THE TWO SENTENCE FAMILIES DIFFER AND THE DIFFERENCE IS PINNED: `check`, `fix` and `lint` say
// `Directory not found:`; `doc` and `watch` say `Project directory not found:`.

test "nlc check over a missing project writes Directory not found to STDERR and exits 1" {
    missingDirectory := MissingDirectoryPath("nsharp-check-missing")

    run := Nlc("check --project \"" + missingDirectory + "\" --text")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Directory not found: " + missingDirectory)
}

test "nlc fix over a missing project writes Directory not found to STDERR and exits 1" {
    missingDirectory := MissingDirectoryPath("nsharp-fix-missing")

    run := Nlc("fix --project \"" + missingDirectory + "\" --text")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Directory not found: " + missingDirectory)
}

test "nlc lint over a missing project writes Directory not found to STDERR and exits 1" {
    missingDirectory := MissingDirectoryPath("nsharp-lint-missing")

    run := Nlc("lint --project \"" + missingDirectory + "\" --text")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Directory not found: " + missingDirectory)
}

test "nlc doc over a missing project writes Project directory not found to STDERR and exits 1" {
    missingDirectory := MissingDirectoryPath("nsharp-doc-missing")

    run := Nlc("doc --project \"" + missingDirectory + "\"")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Project directory not found: " + missingDirectory)
}

test "nlc watch over a missing project writes Project directory not found to STDERR and exits 1" {
    missingDirectory := MissingDirectoryPath("nsharp-watch-missing")

    run := Nlc("watch check --project \"" + missingDirectory + "\"")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Project directory not found: " + missingDirectory)
}


// ═══ SLICE 43: THE ARGUMENT-REFUSAL ROUTES ════════════════════════════════════════════════════
//
// Three refusals that never reach a project at all. Each proves that the kernel sentence the
// estate pins is the sentence the SHIPPED binary writes, and that it goes to stderr with an exit
// of 1 — and, for `watch`, that the target word is lowercased on the way.

test "nlc watch refuses an unsupported target, lowercasing it in the sentence, and exits 1" {
    // The command line says `SERVE`; the sentence says `'serve'`. The deleted C# passed
    // `["SERVE", ...]` and asserted a substring of the lowercased message, so the lowercasing was
    // implied rather than stated.
    run := Nlc("watch SERVE --max-runs 1")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Unsupported watch target 'serve'. Expected check, build, test, lint, or format.")
}

test "nlc watch refuses a zero debounce through stderr and exits 1" {
    run := Nlc("watch check --debounce-ms 0")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("--debounce-ms expects a positive integer.")
}

test "nlc format refuses --stdin beside a file argument through stderr and exits 1" {
    run := Nlc("format --stdin Program.nl")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Cannot combine --stdin with file arguments.")
}


// ═══ SLICE 43: THE `nlc test` TIMEOUT REFUSAL, ON BOTH OUTPUT ROUTES ═══════════════════════════
//
// The one place in this slice where the SAME refusal is proven on two routes, which is what the
// deleted `TestCommandKernels_ParsesTimeoutDurations` did in its second half. The text route puts
// the sentence on stderr behind an `Error: ` prefix; the JSON route puts it INSIDE the envelope
// on stdout and leaves stderr empty. The pair is its own anti-vacuity control: the same binary,
// the same arguments plus `--json`, and the stream that was loud goes silent.

test "nlc test refuses an overflowing timeout on stderr, with the Error prefix, and exits 1" {
    run := Nlc("test --timeout 2147484s")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Invalid timeout format '2147484s'")
    assert run.Stderr.Trim().StartsWith("Error: ")
}

test "nlc test --json puts the same refusal in the envelope and says nothing on stderr" {
    run := Nlc("test --timeout 2147484s --json")

    assert run.ExitCode == 1
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement

    assert TextOf(root.GetProperty("command")) == "test"
    assert !root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("error")).Contains("Invalid timeout format '2147484s'")
    // The envelope is the versioned one every other JSON route uses — a control the deleted body
    // did not have, which is what keeps a bare `{"error": ...}` from passing.
    assert root.GetProperty("schemaVersion").GetInt32() == 1
    document.Dispose()
}


// ═══ SLICE 44: THE `nlc query batch` ENVELOPE ═════════════════════════════════════════════════
//
// SIX deleted bodies wrote a requests file to a temporary directory and read the batch envelope
// back through a console capture of `QueryCommand.Execute`:
// `BatchCommand_UsesStableEnvelopeAndPerItemResponses`, `..._DocMissUsesQueryMessageKernel`,
// `BatchQueryRunner_LoadRequestsErrorsUseMessageKernels`,
// `..._DuplicateRequestIds_AreRejectedInOrdinalOrder`, `..._InvalidRequestsUseMessageKernels` and
// `..._PositionParsingUsesQueryKernelSemantics`. Their kernel rows are in
// `src/NSharpLang.Compiler.BootstrapServices/BatchQueryKernels.tests.nl`; their ENVELOPE rows are
// here, against the real binary.
//
// FOURTEEN OF THEIR 62 ASSERTIONS WERE TAUTOLOGIES AND ARE NOT REPRODUCED AS SUCH. Each compared
// an envelope's message against a LIVE CALL to the kernel that produced it, so the two sides
// agreed by construction and neither ever said what the sentence is. Every one is a LITERAL here,
// and the same literal is pinned in the estate — so a change to either side now breaks something.
//
// AND THREE OF THEM ASSERTED SOMETHING NO USER CAN SEE. `BatchQueryRunner_LoadRequestsErrorsUse
// MessageKernels` called `BatchQueryRunner.LoadRequests` directly and asserted the EXCEPTION TYPES
// `FileNotFoundException` and `InvalidDataException`. `BatchQueryRunner` is `internal` in
// `src/NSharpLang.Cli/`, and the shipped behaviour is not an exception at all: all four load
// failures surface as exit 1 with a top-level `invalidRequestsFile` error envelope naming the
// requests path. That is what is pinned below — measured, not assumed.

func WriteRequests(directory: string, payload: string): string {
    requestsPath := Path.Combine(directory, "requests.json")
    File.WriteAllText(requestsPath, payload)
    return requestsPath
}

func IssueTrackerFixture(): string {
    return Path.Combine(Path.Combine(Path.Combine(CliRepositoryRoot(), "tests"), "fixtures"), "issue-tracker")
}

func NlcBatch(requestsPath: string): CliRun {
    return Nlc("query batch --project \"" + IssueTrackerFixture() + "\" --requests \"" + requestsPath + "\"")
}

test "nlc query batch answers one result per request, in order, and exits 1 when any item failed" {
    directory := NewTempDirectory("nsharp-batch")
    try {
        requestsPath := WriteRequests(directory,
            "[\n"
            + "  { \"command\": \"inspect\", \"file\": \"Service.nl\", \"pos\": \"11:5\", \"compact\": true },\n"
            + "  { \"command\": \"diagnostics\", \"clusters\": true },\n"
            + "  { \"command\": \"doc\", \"query\": \"Console.WriteLine\" },\n"
            + "  { \"command\": \"type\", \"file\": \"Program.nl\", \"pos\": \"1:1\" }\n"
            + "]\n")

        run := NlcBatch(requestsPath)
        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("schemaVersion").GetInt32() == 1
        assert TextOf(root.GetProperty("command")) == "batch"
        assert !root.GetProperty("ok").GetBoolean()
        assert root.GetProperty("requestCount").GetInt32() == 4
        assert root.GetProperty("successCount").GetInt32() == 3
        assert root.GetProperty("failureCount").GetInt32() == 1

        results := root.GetProperty("results")
        assert results.GetArrayLength() == 4

        // the REQUEST is echoed back beside the response, flags included
        first := ElementAt(results, 0)
        assert TextOf(first.GetProperty("request").GetProperty("command")) == "inspect"
        assert first.GetProperty("request").GetProperty("compact").GetBoolean()
        assert first.GetProperty("ok").GetBoolean()
        assert first.GetProperty("response").GetProperty("summary").ValueKind != JsonValueKind.Undefined

        // `--clusters` changes the RESPONSE's own command name, which is the sharpest row here
        second := ElementAt(results, 1)
        assert TextOf(second.GetProperty("request").GetProperty("command")) == "diagnostics"
        assert second.GetProperty("request").GetProperty("clusters").GetBoolean()
        assert second.GetProperty("ok").GetBoolean()
        assert TextOf(second.GetProperty("response").GetProperty("command")) == "diagnostics.clusters"

        third := ElementAt(results, 2)
        assert TextOf(third.GetProperty("request").GetProperty("command")) == "doc"
        assert third.GetProperty("ok").GetBoolean()
        assert TextOf(third.GetProperty("response").GetProperty("command")) == "doc"

        fourth := ElementAt(results, 3)
        assert TextOf(fourth.GetProperty("request").GetProperty("command")) == "type"
        assert !fourth.GetProperty("ok").GetBoolean()
        assert TextOf(fourth.GetProperty("response").GetProperty("error").GetProperty("code")) == "noSymbol"
        // THE LITERAL, not a live call to the kernel that produced it
        assert TextOf(fourth.GetProperty("response").GetProperty("error").GetProperty("message")) == "No symbol found at Program.nl:1:1"
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "every per-item response carries its OWN versioned envelope, not just the outer one" {
    // A CONTROL THE DELETED BODIES DID NOT HAVE. They read `command`, `ok` and `error` out of the
    // per-item responses and never checked that each one is itself a schema-versioned envelope, so
    // a runner that inlined bare payloads would have passed every row they wrote.
    directory := NewTempDirectory("nsharp-batch-envelopes")
    try {
        requestsPath := WriteRequests(directory,
            "[\n"
            + "  { \"command\": \"doc\", \"query\": \"Console.WriteLine\" },\n"
            + "  { \"command\": \"type\", \"file\": \"Program.nl\", \"pos\": \"1:1\" }\n"
            + "]\n")

        run := NlcBatch(requestsPath)
        document := JsonDocument.Parse(run.Stdout)
        results := document.RootElement.GetProperty("results")

        enumerator := results.EnumerateArray()
        seen := 0
        while enumerator.MoveNext() {
            response := enumerator.Current.GetProperty("response")
            assert response.GetProperty("schemaVersion").GetInt32() == 1
            assert response.GetProperty("command").ValueKind == JsonValueKind.String
            seen = seen + 1
        }

        assert seen == 2
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "a documentation miss is a per-item failure whose sentence names the query" {
    directory := NewTempDirectory("nsharp-batch-doc-miss")
    try {
        requestsPath := WriteRequests(directory,
            "[\n  { \"command\": \"doc\", \"query\": \"__DefinitelyMissingBatchDocType__\" }\n]\n")

        run := NlcBatch(requestsPath)
        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert TextOf(root.GetProperty("command")) == "batch"
        assert !root.GetProperty("ok").GetBoolean()
        assert root.GetProperty("failureCount").GetInt32() == 1
        assert root.GetProperty("results").GetArrayLength() == 1

        only := ElementAt(root.GetProperty("results"), 0)
        assert TextOf(only.GetProperty("request").GetProperty("command")) == "doc"
        assert !only.GetProperty("ok").GetBoolean()
        assert TextOf(only.GetProperty("response").GetProperty("error").GetProperty("message")) == "No documentation found for '__DefinitelyMissingBatchDocType__'."
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "every per-request validation refusal reaches the envelope with its own code and sentence" {
    directory := NewTempDirectory("nsharp-batch-invalid")
    try {
        requestsPath := WriteRequests(directory,
            "[\n"
            + "  { \"command\": \"outline\" },\n"
            + "  { \"command\": \"doc\" },\n"
            + "  { \"command\": \"type\", \"file\": \"Program.nl\" },\n"
            + "  { \"command\": \"definition\", \"file\": \"Program.nl\", \"pos\": \"bad\" },\n"
            + "  { \"command\": \"unknown\" }\n"
            + "]\n")

        run := NlcBatch(requestsPath)
        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert !root.GetProperty("ok").GetBoolean()
        assert root.GetProperty("failureCount").GetInt32() == 5
        assert root.GetProperty("successCount").GetInt32() == 0

        results := root.GetProperty("results")
        assert TextOf(ElementAt(results, 0).GetProperty("response").GetProperty("error").GetProperty("message")) == "file is required for outline requests."
        assert TextOf(ElementAt(results, 1).GetProperty("response").GetProperty("error").GetProperty("message")) == "query is required for doc requests."
        assert TextOf(ElementAt(results, 2).GetProperty("response").GetProperty("error").GetProperty("message")) == "file and pos are required."
        assert TextOf(ElementAt(results, 3).GetProperty("response").GetProperty("error").GetProperty("message")) == "Invalid position format 'bad'. Expected <line>:<col>."
        assert TextOf(ElementAt(results, 4).GetProperty("response").GetProperty("error").GetProperty("message")) == "Unsupported batch query command 'unknown'."

        // THE ERROR CODES, WHICH THE DELETED BODY NEVER READ ON THIS PATH. Four of the five are
        // `invalidRequest`; the unknown command gets its own.
        assert TextOf(ElementAt(results, 0).GetProperty("response").GetProperty("error").GetProperty("code")) == "invalidRequest"
        assert TextOf(ElementAt(results, 3).GetProperty("response").GetProperty("error").GetProperty("code")) == "invalidRequest"
        assert TextOf(ElementAt(results, 4).GetProperty("response").GetProperty("error").GetProperty("code")) == "unsupportedCommand"
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "a position batch requests parses is answered, and two it refuses are refused differently" {
    // THE ROW THAT SHOWS WHY THIS FAMILY EXISTS. ` +1 : +1 ` is ACCEPTED as 1:1 — signs and
    // surrounding spaces and all — and fails only because there is no symbol there. `2147483648:1`
    // overflows and `1_000:2` uses a digit separator, and both are refused as malformed.
    directory := NewTempDirectory("nsharp-batch-position")
    try {
        requestsPath := WriteRequests(directory,
            "[\n"
            + "  { \"command\": \"type\", \"file\": \"Program.nl\", \"pos\": \" +1 : +1 \" },\n"
            + "  { \"command\": \"type\", \"file\": \"Program.nl\", \"pos\": \"2147483648:1\" },\n"
            + "  { \"command\": \"type\", \"file\": \"Program.nl\", \"pos\": \"1_000:2\" }\n"
            + "]\n")

        run := NlcBatch(requestsPath)
        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("requestCount").GetInt32() == 3
        assert root.GetProperty("successCount").GetInt32() == 0
        assert root.GetProperty("failureCount").GetInt32() == 3

        results := root.GetProperty("results")
        firstError := ElementAt(results, 0).GetProperty("response").GetProperty("error")
        assert TextOf(firstError.GetProperty("code")) == "noSymbol"
        assert TextOf(firstError.GetProperty("message")) == "No symbol found at Program.nl:1:1"

        overflowError := ElementAt(results, 1).GetProperty("response").GetProperty("error")
        assert TextOf(overflowError.GetProperty("code")) == "invalidRequest"
        assert TextOf(overflowError.GetProperty("message")) == "Invalid position format '2147483648:1'. Expected <line>:<col>."

        separatorError := ElementAt(results, 2).GetProperty("response").GetProperty("error")
        assert TextOf(separatorError.GetProperty("code")) == "invalidRequest"
        assert TextOf(separatorError.GetProperty("message")) == "Invalid position format '1_000:2'. Expected <line>:<col>."
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "duplicate request ids abort the WHOLE run with a top-level invalidRequestsFile envelope" {
    // THE ROW THE DELETED BODY COULD NOT MAKE. It called `BatchQueryRunner.LoadRequests` directly
    // and asserted an `InvalidDataException`. What a user actually gets is exit 1, a silent
    // stderr, and a top-level error envelope with NO `results` array at all — the run does not
    // start. The ids are reported ordinal-sorted, which is what makes the sentence stable.
    directory := NewTempDirectory("nsharp-batch-duplicates")
    try {
        requestsPath := WriteRequests(directory,
            "[\n"
            + "  { \"id\": \"zeta\", \"command\": \"doc\", \"query\": \"Console.WriteLine\" },\n"
            + "  { \"id\": \"alpha\", \"command\": \"doc\", \"query\": \"String\" },\n"
            + "  { \"id\": \" \", \"command\": \"doc\", \"query\": \"Int32\" },\n"
            + "  { \"id\": \"zeta\", \"command\": \"diagnostics\" },\n"
            + "  { \"id\": \"Alpha\", \"command\": \"doc\", \"query\": \"Console\" },\n"
            + "  { \"id\": \"alpha\", \"command\": \"symbols\" }\n"
            + "]\n")

        run := NlcBatch(requestsPath)
        assert run.ExitCode == 1
        assert run.Stderr.Trim().Length == 0

        document := JsonDocument.Parse(run.Stdout)
        root := document.RootElement
        assert root.GetProperty("schemaVersion").GetInt32() == 1
        assert TextOf(root.GetProperty("command")) == "batch"
        assert !root.GetProperty("ok").GetBoolean()
        assert TextOf(root.GetProperty("error").GetProperty("code")) == "invalidRequestsFile"
        assert TextOf(root.GetProperty("error").GetProperty("message")) == "Duplicate batch request ids are not allowed: alpha, zeta"
        assert TextOf(root.GetProperty("error").GetProperty("details").GetProperty("requests")) == requestsPath
        // NO results array, and no counts: the run never began. (`out _` is not a spelling this
        // emit path accepts, so the absence is read off the emitted JSON text, which is exact.)
        assert !run.Stdout.Contains("\"results\"")
        assert !run.Stdout.Contains("\"requestCount\"")
        document.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}

test "all THREE remaining requests-file failures use the same envelope and name the path" {
    // THE OTHER THREE ROWS OF THE `Assert.Throws` BODY, ON THE ROUTE A USER TRAVELS. A missing
    // file, a payload that is neither an array nor a `requests` object, and an array element that
    // is not an object all answer exit 1 and `invalidRequestsFile` — the exception TYPES the
    // deleted body distinguished (`FileNotFoundException` versus `InvalidDataException`) are not
    // observable anywhere in the shipped output.
    directory := NewTempDirectory("nsharp-batch-load-errors")
    try {
        missingPath := Path.Combine(directory, "missing.json")
        missingRun := NlcBatch(missingPath)
        assert missingRun.ExitCode == 1
        missingDocument := JsonDocument.Parse(missingRun.Stdout)
        assert TextOf(missingDocument.RootElement.GetProperty("error").GetProperty("code")) == "invalidRequestsFile"
        assert TextOf(missingDocument.RootElement.GetProperty("error").GetProperty("message")) == "Requests file not found: " + missingPath
        missingDocument.Dispose()

        payloadPath := Path.Combine(directory, "payload.json")
        File.WriteAllText(payloadPath, "{}")
        payloadRun := NlcBatch(payloadPath)
        assert payloadRun.ExitCode == 1
        payloadDocument := JsonDocument.Parse(payloadRun.Stdout)
        assert TextOf(payloadDocument.RootElement.GetProperty("error").GetProperty("code")) == "invalidRequestsFile"
        assert TextOf(payloadDocument.RootElement.GetProperty("error").GetProperty("message")) == "Batch requests must be a JSON array or an object with a 'requests' array."
        payloadDocument.Dispose()

        itemPath := Path.Combine(directory, "item.json")
        File.WriteAllText(itemPath, "[1]")
        itemRun := NlcBatch(itemPath)
        assert itemRun.ExitCode == 1
        itemDocument := JsonDocument.Parse(itemRun.Stdout)
        assert TextOf(itemDocument.RootElement.GetProperty("error").GetProperty("code")) == "invalidRequestsFile"
        assert TextOf(itemDocument.RootElement.GetProperty("error").GetProperty("message")) == "Each batch request must be a JSON object."
        itemDocument.Dispose()
    } finally {
        Directory.Delete(directory, true)
    }
}


// ═══ SLICE 44: THE `nlc completion` CONTRACT ══════════════════════════════════════════════════
//
// The console rows of `CompletionCommandKernels_SummarizesOptions`; its kernel rows are in
// `src/NSharpLang.Compiler.BootstrapServices/CompletionCommandKernels.tests.nl`. The deleted body
// called `CompletionCommand.Execute` in process, so it never proved that `nlc completion` reaches
// it — these do.

test "nlc completion --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("completion --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Usage: nlc completion <bash|zsh|fish>")
    assert run.Stdout.Contains("N# Shell Completion")
}

test "nlc completion with an unknown shell exits 1, and the sentence goes to STDERR" {
    // The pair below is its own anti-vacuity control: the row above proves stdout is reachable and
    // stderr silent; this one proves the reverse on the same command.
    run := Nlc("completion PowerShell")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Unknown shell 'powershell'. Expected bash, zsh, or fish.")
}

test "nlc completion lowercases the shell name it reports, which the estate row cannot show" {
    // The kernel is handed the name as typed; the COMMAND lowercases it before the sentence. The
    // deleted body passed `PowerShell` and expected `'powershell'` and never said which layer did
    // it — the estate row asks the kernel for `"powershell"` directly, so only this row proves the
    // command performs the fold.
    run := Nlc("completion POWERSHELL")

    assert run.ExitCode == 1
    assert run.Stderr.Contains("Unknown shell 'powershell'.")
}


// ═══ SLICE 44: THE COMMAND REGISTRY STAYS IN SYNC ═════════════════════════════════════════════
//
// The console-and-docs half of `CliCommandRegistry_StaysInSyncWithHelpCompletionsAndDocs`. The
// registry's own CONTENT is pinned as literals in
// `src/NSharpLang.Compiler.BootstrapServices/CommandRegistry.tests.nl`; the same literals are
// pinned here, against `nlc help`, `nlc query help`, the generated zsh script and
// `website/docs/cli-reference.md`.
//
// THE DELETED BODY LOOPED OVER WHATEVER THE REGISTRY HAPPENED TO CONTAIN. A registry that silently
// lost a command would have passed it — one fewer iteration, every remaining assertion still true.
// Both sides are literal now, so a drift in either direction fails something.

func TopLevelCommandNames(): string[] {
    return [
        "build", "run", "new", "init", "test", "format", "lint", "clean", "watch", "doc",
        "completion", "check", "fix", "query", "daemon", "add", "tidy", "remove", "update",
        "publish", "tree", "audit", "env", "doctor", "restore", "pack", "help"
    ]
}

func QueryCommandNames(): string[] {
    return [
        "batch", "symbols", "outline", "ast", "diagnostics", "type", "inspect", "definition",
        "def", "references", "refs", "completions", "doc", "hover", "call-graph", "implementors",
        "perf", "trusted", "help"
    ]
}

func CliReferenceDocs(): string {
    return File.ReadAllText(Path.Combine(Path.Combine(Path.Combine(CliRepositoryRoot(), "website"), "docs"), "cli-reference.md"))
}

test "every one of the 27 top-level commands is in nlc help, the zsh script AND the docs" {
    help := Nlc("help")
    assert help.ExitCode == 0
    assert help.Stderr.Trim().Length == 0

    zsh := Nlc("completion zsh")
    assert zsh.ExitCode == 0
    assert zsh.Stderr.Trim().Length == 0

    docs := CliReferenceDocs()
    names := TopLevelCommandNames()
    assert names.Length == 27

    i := 0
    while i < names.Length {
        assert help.Stdout.Contains(names[i])
        assert zsh.Stdout.Contains(names[i])
        assert docs.Contains("nlc " + names[i])
        i = i + 1
    }
}

test "every one of the 19 query subcommands is in nlc query help, the zsh script AND the docs" {
    queryHelp := Nlc("query help")
    assert queryHelp.ExitCode == 0
    assert queryHelp.Stderr.Trim().Length == 0

    zsh := Nlc("completion zsh")
    docs := CliReferenceDocs()
    names := QueryCommandNames()
    assert names.Length == 19

    i := 0
    while i < names.Length {
        assert queryHelp.Stdout.Contains(names[i])
        assert zsh.Stdout.Contains(names[i])
        assert docs.Contains("nlc query " + names[i])
        i = i + 1
    }
}

test "the retired idiom command is absent from help, the zsh script and the docs" {
    help := Nlc("help")
    zsh := Nlc("completion zsh")

    assert !help.Stdout.Contains("nlc idiom")
    assert !zsh.Stdout.Contains("nlc idiom")
    assert !CliReferenceDocs().Contains("nlc idiom")
}


// ═══ SLICE 45: THE SIX DEPENDENCY AND HOUSEKEEPING COMMANDS, PROVEN AS PROCESSES ══════════════
//
// These blocks replace the 21 console-reading bodies deleted from `tests/CliParityAuditTests.cs`
// that drove `AddCommand`, `TidyCommand`, `UpdateCommand`, `RemoveCommand`, `CleanCommand` and
// `CompletionCommand`. All six subjects are `.nl` files in
// `src/NSharpLang.Compiler.BootstrapServices/` with NO C# counterpart, and all six deleted bodies
// called `XCommand.Execute(...)` IN PROCESS through a console capture — so none of them proved that
// `nlc <name>` reaches the command at all, and none could observe an exit code.
//
// THE ESTATE ALREADY STATES EVERY SENTENCE THESE BLOCKS OBSERVE. `AddCommandKernels.tests.nl`,
// `UpdateCommandKernels.tests.nl`, `RemoveCommandKernels.tests.nl`, `TidyCommandKernels.tests.nl`,
// `CleanCommandKernels.tests.nl` and `CompletionCommandKernels.tests.nl` pin each message as a
// LITERAL. What is missing there, and supplied here, is which STREAM the sentence reaches, what
// EXIT CODE the process returns, and what the command left on disk. Each claim is therefore made
// once on each side, and neither side can drift into agreement with a wrong answer.
//
// FOUR CROSS-COMMAND FACTS ARE STATED HERE FOR THE FIRST TIME, because each needs two commands or
// two arms side by side and every deleted body saw only one:
//   * the three missing-project sentences are NOT the same, and only `add` tells the user how to fix
//   * `update` and `remove` share their missing-package sentence WORD FOR WORD
//   * `add`'s failure usage and its `--help` usage differ, and only the latter mentions `--path`
//   * `add`'s two duplicate-dependency arms differ, and only the package arm offers a remedy

// ── running a command in a project directory ──────────────────────────────────
//
// `update`, `remove` and `add` take no `--project`: they read the CURRENT DIRECTORY. The deleted
// bodies simulated that with `Directory.SetCurrentDirectory`, which mutates process-global state
// and is why that whole file carried `[Collection("ProcessState")]`. A child process needs no such
// thing — its working directory is its own.

func NlcIn(workingDirectory: string, arguments: string): CliRun {
    return RunProcess("dotnet", "\"" + CliDll() + "\" " + arguments, workingDirectory)
}

func WriteProjectYml(directory: string, text: string) {
    File.WriteAllText(Path.Combine(directory, "project.yml"), text)
}

func ProjectWithNuGetDependency(prefix: string, name: string): string {
    directory := NewTempDirectory(prefix)
    WriteProjectYml(directory,
        "name: " + name + "\n"
        + "version: 1.0.0\n"
        + "backend: il\n"
        + "targetFramework: net10.0\n"
        + "\n"
        + "dependencies:\n"
        + "  - YamlDotNet@16.3.0\n")
    return directory
}


// ═══ `nlc clean` ══════════════════════════════════════════════════════════════════════════════

test "nlc clean removes the three artifact directories, names them, and says nothing on stderr" {
    directory := NewTempDirectory("nlc-clean-artifacts")
    Directory.CreateDirectory(Path.Combine(directory, "bin"))
    Directory.CreateDirectory(Path.Combine(directory, "obj"))
    Directory.CreateDirectory(Path.Combine(directory, ".nlc"))

    run := Nlc("clean --project \"" + directory + "\"")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Removed 3 build artifact directories:")
    assert !Directory.Exists(Path.Combine(directory, "bin"))
    assert !Directory.Exists(Path.Combine(directory, "obj"))
    assert !Directory.Exists(Path.Combine(directory, ".nlc"))

    // THE LISTING IS ORDERED, WHICH THE DELETED BODY NEVER READ. It asserted the count sentence and
    // the three absences and stopped; a command that removed the right directories while printing
    // the wrong names would have passed it.
    dotNlcIndex := run.Stdout.IndexOf(".nlc", 0, StringComparison.Ordinal)
    binIndex := run.Stdout.IndexOf("bin", 0, StringComparison.Ordinal)
    objIndex := run.Stdout.IndexOf("obj", 0, StringComparison.Ordinal)
    assert dotNlcIndex >= 0
    assert binIndex > dotNlcIndex
    assert objIndex > binIndex

    Directory.Delete(directory, true)
}

test "nlc clean on a directory with nothing to remove still exits 0" {
    // THE CONTROL FOR THE COUNT SENTENCE: the number in `Removed 3 …` is a fact about this run and
    // not a constant, so a clean tree must not report it.
    directory := NewTempDirectory("nlc-clean-empty")

    run := Nlc("clean --project \"" + directory + "\"")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert !run.Stdout.Contains("Removed 3 build artifact")

    Directory.Delete(directory, true)
}


// ═══ `nlc completion` ═════════════════════════════════════════════════════════════════════════

test "nlc completion bash emits a bash script naming every top-level command" {
    run := Nlc("completion bash")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("clean")
    assert run.Stdout.Contains("watch")
    assert run.Stdout.Contains("doc")
    assert run.Stdout.Contains("completion")

    // AND IT IS A BASH SCRIPT, not a bare word list — which is the part the deleted body's four
    // `Contains` rows could not distinguish from any output containing those four words.
    assert run.Stdout.Contains("_nlc_commands=")
    assert run.Stdout.Contains("complete -F _nlc nlc")
    assert run.Stdout.Contains("COMPREPLY=(")

    // the same registry the estate pins, reached through the real binary
    names := TopLevelCommandNames()
    i := 0
    while i < names.Length {
        assert run.Stdout.Contains(names[i])
        i = i + 1
    }
}

test "nlc completion bash carries the three nested command lists too" {
    run := Nlc("completion bash")

    assert run.Stdout.Contains("_nlc_query_commands=")
    assert run.Stdout.Contains("_nlc_daemon_commands=")
    assert run.Stdout.Contains("_nlc_watch_commands=")
}


// ═══ `nlc update` ═════════════════════════════════════════════════════════════════════════════

test "nlc update --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("update --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("N# Update Dependencies")
    assert run.Stdout.Contains("Usage: nlc update [package] [options]")
}

test "nlc update with no project.yml exits 1 and writes to STDERR, leaving stdout silent" {
    directory := NewTempDirectory("nlc-update-noproject")

    run := NlcIn(directory, "update")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("No project.yml found.")

    Directory.Delete(directory, true)
}

test "nlc update with only a framework dependency exits 0 and writes to STDOUT" {
    // THE STREAM SPLIT IS THE CLAIM. This is a SUCCESS, so the sentence goes to stdout and stderr
    // stays silent — the exact mirror of the block above. The deleted bodies asserted each half in
    // isolation and never put the pair together.
    directory := NewTempDirectory("nlc-update-frameworkonly")
    WriteProjectYml(directory,
        "name: UpdateDemo\nversion: 1.0.0\nbackend: il\ntargetFramework: net10.0\n\ndependencies:\n  - framework: Microsoft.AspNetCore.App\n")

    run := NlcIn(directory, "update")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("No NuGet dependencies to update.")

    Directory.Delete(directory, true)
}

test "nlc update names a package that is not in dependencies and exits 1" {
    directory := ProjectWithNuGetDependency("nlc-update-missingtarget", "UpdateDemo")

    run := NlcIn(directory, "update Serilog")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Package 'Serilog' not found in dependencies.")

    Directory.Delete(directory, true)
}


// ═══ `nlc remove` ═════════════════════════════════════════════════════════════════════════════

test "nlc remove --help exits 0, writes its usage to stdout, and says nothing on stderr" {
    run := Nlc("remove --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("N# Remove Dependency")
    assert run.Stdout.Contains("Usage: nlc remove <package>")
}

test "nlc remove with no arguments exits 1 and puts its usage on STDERR, not stdout" {
    // THE SAME SENTENCE REACHES A DIFFERENT STREAM depending on whether it was asked for. The
    // `--help` block above finds `Usage: nlc remove <package>` on STDOUT; here it is a failure.
    run := Nlc("remove")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Usage: nlc remove <package>")
}

test "nlc remove with no project.yml exits 1 and writes to stderr" {
    directory := NewTempDirectory("nlc-remove-noproject")

    run := NlcIn(directory, "remove Serilog")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("No project.yml found.")

    Directory.Delete(directory, true)
}

test "nlc remove names a package that is not in dependencies and exits 1" {
    directory := ProjectWithNuGetDependency("nlc-remove-missingdep", "RemoveDemo")

    run := NlcIn(directory, "remove Serilog")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Package 'Serilog' not found in dependencies.")

    Directory.Delete(directory, true)
}


// ═══ `nlc tidy` ═══════════════════════════════════════════════════════════════════════════════

func WriteTidyProject(directory: string, name: string, dependencies: string, program: string) {
    WriteProjectYml(directory,
        "name: " + name + "\n"
        + "entry: Program.nl\n"
        + "outputType: exe\n"
        + "targetFramework: net10.0\n"
        + "\n"
        + "dependencies:\n"
        + dependencies)
    File.WriteAllText(Path.Combine(directory, "Program.nl"), program)
}

func TidyStatusOf(payload: JsonElement, wanted: string): string {
    enumerator := payload.GetProperty("dependencies").EnumerateArray()
    while enumerator.MoveNext() {
        entry := enumerator.Current
        if TextOf(entry.GetProperty("name")) == wanted {
            return TextOf(entry.GetProperty("status"))
        }
    }

    throw new InvalidOperationException("The tidy envelope has no dependency named '" + wanted + "'.")
}

// `nlc tidy --help` is ALREADY pinned above, in the help-contract family, with exactly the rows
// `TidyCommand_Help_ShowsUsage` made — exit 0, a silent stderr, `Usage: nlc tidy [options]` and
// `N# Tidy`. Writing it a second time here was caught by the perturbation matrix, which reported
// 27 red blocks against 26 inverted ones because the two titles mangle to one test method name.
// The migration for that body is the inherited block; what is new is the row it never made.
test "nlc tidy --help documents the three dependency STATUSES the command can report" {
    run := Nlc("tidy --help")

    assert run.ExitCode == 0
    // THE DELETED BODY ASKED ONLY FOR `Contains("tidy")` AND `Contains("Usage")`, which any help
    // text for any command containing the word would satisfy. The help actually documents the
    // classification vocabulary, and it is the same three words the JSON envelope uses.
    assert run.Stdout.Contains("used")
    assert run.Stdout.Contains("possibly-unused")
    assert run.Stdout.Contains("unknown")
    assert run.Stdout.Contains("--fix")
    assert run.Stdout.Contains("schemaVersion")
}

test "nlc tidy with no project.yml exits 1 and writes the ERROR-PREFIXED sentence to stderr" {
    // THE LITERAL, NOT A KERNEL CALL. The deleted body compared this stream against a live call to
    // `ProgramCommandKernels.GetErrorLine(TidyCommandKernels.GetMissingProjectFileTextMessage())`,
    // so both sides were computed by the kernels and agreed by construction. The kernels' own text
    // is pinned in `TidyCommandKernels.tests.nl`; the sentence a user sees is pinned here.
    directory := NewTempDirectory("nlc-tidy-noproject")

    run := Nlc("tidy --project \"" + directory + "\"")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Trim() == "Error: No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project."

    Directory.Delete(directory, true)
}

test "nlc tidy --json uses a DIFFERENT missing-project sentence than the text arm does" {
    // THE DELETED BODY ASKED ONLY FOR `Contains("No project.yml")`, WHICH BOTH SENTENCES SATISFY,
    // so it could not see that the two arms differ. They do, and deliberately: the JSON arm names
    // "the specified directory" because a machine reader has no current directory to reason about.
    directory := NewTempDirectory("nlc-tidy-jsonnoproject")

    run := Nlc("tidy --project \"" + directory + "\" --json")

    assert run.ExitCode == 1
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("schemaVersion").GetInt32() == 1
    assert TextOf(root.GetProperty("command")) == "tidy"
    assert !root.GetProperty("ok").GetBoolean()
    assert TextOf(root.GetProperty("error").GetProperty("message")) == "No project.yml found in the specified directory."
    document.Dispose()

    // …and the text arm's sentence is genuinely a different string
    textRun := Nlc("tidy --project \"" + directory + "\"")
    assert !textRun.Stderr.Contains("No project.yml found in the specified directory.")

    Directory.Delete(directory, true)
}

test "nlc tidy --json classifies each dependency as used, possibly-unused or unknown" {
    directory := NewTempDirectory("nlc-tidy-json")
    WriteTidyProject(directory, "TidyClassification",
        "  - nuget: Newtonsoft.Json\n    version: 13.0.3\n"
        + "  - nuget: Serilog.Sinks.Console\n    version: 5.0.1\n"
        + "  - nuget: Polly\n    version: 8.0.0\n",
        "  import  Newtonsoft.Json.Linq // used by tidy import extraction\n\nfunc Main() {\n    print \"ok\"\n}\n")

    run := Nlc("tidy --project \"" + directory + "\" --json")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert TidyStatusOf(root, "Newtonsoft.Json") == "used"
    assert TidyStatusOf(root, "Serilog.Sinks.Console") == "possibly-unused"
    assert TidyStatusOf(root, "Polly") == "unknown"

    // EVERY ROW CARRIES A REASON, which the deleted body never read — and the three reasons are
    // different sentences, so the status field is not the only thing an LLM consumer can act on.
    enumerator := root.GetProperty("dependencies").EnumerateArray()
    reasons := 0
    while enumerator.MoveNext() {
        assert TextOf(enumerator.Current.GetProperty("reason")).Length > 0
        reasons = reasons + 1
    }
    assert reasons == 3
    document.Dispose()

    Directory.Delete(directory, true)
}

test "the tidy envelope's ok field reports CLEANLINESS, not success, and exit 0 can carry ok:false" {
    // A PRODUCT FINDING, MEASURED AND RECORDED RATHER THAN FIXED. Everywhere else in `nlc` — `check`
    // with 246 errors, `tidy` with no project.yml — `ok:false` accompanies a failure. In `tidy`'s
    // success path it means "no possibly-unused dependency was found", so a consumer reading `ok`
    // alone cannot tell "your project has an unused dependency" from "the command failed"; only the
    // exit code separates them. The deleted body asserted `Assert.Equal(0, exitCode)` and read the
    // `dependencies` array, and never read `ok` on this path at all.
    unclean := NewTempDirectory("nlc-tidy-ok-unclean")
    WriteTidyProject(unclean, "TidyUnclean",
        "  - nuget: Serilog.Sinks.Console\n    version: 5.0.1\n",
        "func Main() {\n    print \"ok\"\n}\n")

    clean := NewTempDirectory("nlc-tidy-ok-clean")
    WriteTidyProject(clean, "TidyClean",
        "  - nuget: Newtonsoft.Json\n    version: 13.0.3\n",
        "import Newtonsoft.Json.Linq\n\nfunc Main() {\n    print \"ok\"\n}\n")

    uncleanRun := Nlc("tidy --project \"" + unclean + "\" --json")
    cleanRun := Nlc("tidy --project \"" + clean + "\" --json")

    assert uncleanRun.ExitCode == 0
    assert cleanRun.ExitCode == 0

    uncleanDocument := JsonDocument.Parse(uncleanRun.Stdout)
    cleanDocument := JsonDocument.Parse(cleanRun.Stdout)

    // SAME EXIT CODE, OPPOSITE `ok`.
    assert !uncleanDocument.RootElement.GetProperty("ok").GetBoolean()
    assert cleanDocument.RootElement.GetProperty("ok").GetBoolean()

    uncleanDocument.Dispose()
    cleanDocument.Dispose()

    Directory.Delete(unclean, true)
    Directory.Delete(clean, true)
}

test "nlc tidy without --json prints a table and no JSON at all" {
    directory := NewTempDirectory("nlc-tidy-text")
    WriteTidyProject(directory, "TidyTextClassification",
        "  - nuget: Serilog.Sinks.Console\n    version: 5.0.1\n",
        "func Main() {\n    print \"ok\"\n}\n")

    run := Nlc("tidy --project \"" + directory + "\"")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Package")
    assert run.Stdout.Contains("Serilog.Sinks.Console")
    assert run.Stdout.Contains("possibly-unused")
    assert !run.Stdout.Contains("\"command\"")

    // AND IT TELLS THE USER WHAT TO DO NEXT, which the deleted body did not read.
    assert run.Stdout.Contains("Status")
    assert run.Stdout.Contains("Reason")
    assert run.Stdout.Contains("Run 'nlc tidy --fix' to remove them.")

    Directory.Delete(directory, true)
}

test "nlc tidy --fix rewrites project.yml removing ONLY the package it named" {
    // THE DATA-LOSS DEFECT, END TO END — THE ONE ARM NO KERNEL BLOCK CAN MAKE, because the loss is
    // a FILE, not a return value. `nlc tidy --fix` rewrites `project.yml` from a line filter whose
    // package match used to be a BARE PREFIX. On exactly this project the report named ONE
    // dependency and the file lost THREE lines: `Serilog.Sinks` (correctly) plus
    // `Serilog.SinksExtra` and `Serilog.Sinks.Console` — different packages, sitting in a
    // `testDependencies:` section `TidyCommand` never classified and the table never printed.
    //
    // The count in the message and the count of vanished lines are read TOGETHER here, which is
    // what makes the row able to fail: a filter that over-deletes still prints "Removed 1".
    directory := NewTempDirectory("nlc-tidy-fix")
    WriteProjectYml(directory,
        "name: TidyFix\n"
        + "entry: Program.nl\n"
        + "outputType: exe\n"
        + "targetFramework: net10.0\n"
        + "\n"
        + "dependencies:\n"
        + "  - Serilog.Sinks@1.0.0\n"
        + "  - Newtonsoft.Json@13.0.3\n"
        + "\n"
        + "testDependencies:\n"
        + "  - Serilog.SinksExtra@2.0.0\n"
        + "  - Serilog.Sinks.Console@5.0.1\n")
    File.WriteAllText(Path.Combine(directory, "Program.nl"),
        "import Newtonsoft.Json.Linq\n\nfunc Main() {\n    print \"ok\"\n}\n")

    projectPath := Path.Combine(directory, "project.yml")
    before := File.ReadAllLines(projectPath).Length

    run := Nlc("tidy --fix --project \"" + directory + "\"")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Removed 1 possibly-unused dependency.")

    rewritten := File.ReadAllText(projectPath)
    // THE NEGATIVE HALF: the one package the report named is gone.
    assert !rewritten.Contains("Serilog.Sinks@1.0.0")
    // THE POSITIVE HALF: everything the report did NOT name survives, prefix or not.
    assert rewritten.Contains("  - Newtonsoft.Json@13.0.3")
    assert rewritten.Contains("  - Serilog.SinksExtra@2.0.0")
    assert rewritten.Contains("  - Serilog.Sinks.Console@5.0.1")
    assert rewritten.Contains("testDependencies:")
    // ONE line left, not three.
    assert File.ReadAllLines(projectPath).Length == before - 1

    // IDEMPOTENCE: a second `--fix` finds nothing to remove and leaves the file exactly as it was.
    second := Nlc("tidy --fix --project \"" + directory + "\"")

    assert second.ExitCode == 0
    assert second.Stdout.Contains("Nothing to remove.")
    assert File.ReadAllText(projectPath) == rewritten

    Directory.Delete(directory, true)
}


// ═══ `nlc add` ════════════════════════════════════════════════════════════════════════════════

test "nlc add --help exits 0 and documents the --path option" {
    run := Nlc("add --help")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("--path")
    assert run.Stdout.Contains("N# Add Dependency")
    assert run.Stdout.Contains("Usage: nlc add <package> [options]")
}

test "nlc add with no arguments exits 1 and its FAILURE usage omits --path entirely" {
    // A FINDING NEITHER DELETED BODY COULD REACH. `AddCommand_Help_ShowsPathOption` read `--path`
    // off the help text and `AddCommand_NoArgs_ReturnsUsage` read a `Usage:` line off stderr; the
    // two lived in different bodies, so nothing compared them. They are DIFFERENT usage texts, and
    // the one a user actually hits on failure does not mention the option at all.
    run := Nlc("add")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Usage: nlc add <package> [--version <ver>]")
    assert run.Stderr.Contains("nlc add <package>@<version>")
    assert !run.Stderr.Contains("--path")

    // …while the help text, on stdout, spells all three forms
    help := Nlc("add --help")
    assert help.Stdout.Contains("Usage: nlc add <package> [options]")
    assert help.Stdout.Contains("nlc add --path <local-project>")
}

test "nlc add with no project.yml exits 1 and is the ONLY one of the three that says how to fix it" {
    // THE THREE COMMANDS DO NOT SHARE THIS SENTENCE. `update` and `remove` both stop at
    // "No project.yml found."; only `add` continues into a remedy. Each deleted body asserted its
    // own command's `Contains` and could never have noticed.
    addDirectory := NewTempDirectory("nlc-add-noproject")
    updateDirectory := NewTempDirectory("nlc-update-noproject-cmp")
    removeDirectory := NewTempDirectory("nlc-remove-noproject-cmp")

    addRun := NlcIn(addDirectory, "add Serilog@3.1.0")
    updateRun := NlcIn(updateDirectory, "update")
    removeRun := NlcIn(removeDirectory, "remove Serilog")

    assert addRun.ExitCode == 1
    assert addRun.Stdout.Trim().Length == 0
    assert addRun.Stderr.Trim() == "No project.yml found. Run 'nlc new <name>' or 'nlc init' to create a project."

    assert updateRun.Stderr.Trim() == "No project.yml found."
    assert removeRun.Stderr.Trim() == "No project.yml found."
    assert !updateRun.Stderr.Contains("nlc init")
    assert !removeRun.Stderr.Contains("nlc init")

    Directory.Delete(addDirectory, true)
    Directory.Delete(updateDirectory, true)
    Directory.Delete(removeDirectory, true)
}

test "nlc add inserts a package INSIDE the dependencies block, before the next top-level key" {
    directory := NewTempDirectory("nlc-add-inline")
    WriteProjectYml(directory,
        "name: AddDemo\nversion: 1.0.0\nbackend: il\n\ndependencies:\n  - Newtonsoft.Json@13.0.3\ntargetFramework: net10.0\n")

    run := NlcIn(directory, "add Serilog@3.1.0")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("Added Serilog@3.1.0 to project.yml")

    projectYaml := File.ReadAllText(Path.Combine(directory, "project.yml"))
    addedIndex := projectYaml.IndexOf("Serilog@3.1.0", 0, StringComparison.Ordinal)
    existingIndex := projectYaml.IndexOf("Newtonsoft.Json@13.0.3", 0, StringComparison.Ordinal)
    nextTopLevelIndex := projectYaml.IndexOf("targetFramework: net10.0", 0, StringComparison.Ordinal)

    assert existingIndex >= 0
    assert addedIndex > existingIndex
    assert nextTopLevelIndex > addedIndex

    // THE INDENTATION IS THE POINT AND THE DELETED BODY NEVER READ IT: a line inserted at the wrong
    // indent is still "before targetFramework" and still passes an index comparison, while
    // producing a project.yml that no longer parses.
    assert projectYaml.Contains("  - Serilog@3.1.0\n")

    // and the generated props are refreshed by the same run
    assert File.Exists(Path.Combine(Path.Combine(directory, "obj"), "project.g.props"))

    Directory.Delete(directory, true)
}

test "nlc add rejects a duplicate package case-insensitively and leaves project.yml untouched" {
    directory := NewTempDirectory("nlc-add-duppackage")
    WriteProjectYml(directory,
        "name: AddDuplicatePackageDemo\nversion: 1.0.0\nbackend: il\ntargetFramework: net10.0\n\ndependencies:\n  - Newtonsoft.Json@13.0.3\n")
    before := File.ReadAllText(Path.Combine(directory, "project.yml"))

    run := NlcIn(directory, "add newtonsoft.json@14.0.0")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("already in dependencies")

    // THE SENTENCE ECHOES THE USER'S CASING, NOT THE STORED CASING — measured, and a detail the
    // deleted body's `Contains("already in dependencies")` could not see.
    assert run.Stderr.Contains("'newtonsoft.json' is already in dependencies.")
    assert run.Stderr.Contains("Use 'nlc update' to change the version.")

    // THE FILE IS BYTE-IDENTICAL. The deleted body checked that `13.0.3` survived and that `14.0.0`
    // was absent, which a command that rewrote the file some other way could still satisfy.
    assert File.ReadAllText(Path.Combine(directory, "project.yml")) == before

    Directory.Delete(directory, true)
}

test "nlc add rejects a duplicate project reference, and that arm offers NO remedy" {
    // THE TWO DUPLICATE ARMS ARE DIFFERENT ANSWERS. Both end in "already in dependencies", which is
    // all the deleted bodies asserted — but only the package arm tells the user about `nlc update`,
    // and there is no equivalent for a project reference.
    directory := NewTempDirectory("nlc-add-dupproject")
    Directory.CreateDirectory(Path.Combine(directory, "Shared"))
    File.WriteAllText(Path.Combine(Path.Combine(directory, "Shared"), "project.yml"),
        "name: Shared\nversion: 1.0.0\ntargetFramework: net10.0\noutputType: library\n")
    WriteProjectYml(directory,
        "name: AddDuplicateProjectDemo\nversion: 1.0.0\nbackend: il\ntargetFramework: net10.0\n\ndependencies:\n  - project: Shared/project.yml\n")
    before := File.ReadAllText(Path.Combine(directory, "project.yml"))

    run := NlcIn(directory, "add --path shared/PROJECT.yml")

    assert run.ExitCode == 1
    assert run.Stdout.Trim().Length == 0
    assert run.Stderr.Contains("Project reference 'shared/PROJECT.yml' is already in dependencies.")
    assert !run.Stderr.Contains("Use 'nlc update' to change the version.")

    assert File.ReadAllText(Path.Combine(directory, "project.yml")) == before

    Directory.Delete(directory, true)
}


// ═══ THE TWO CROSS-COMMAND SENTENCES ══════════════════════════════════════════════════════════

test "nlc update and nlc remove share their missing-package sentence WORD FOR WORD" {
    // Two commands, two `.nl` owners, ONE sentence. The two deleted bodies each asserted the same
    // string in isolation, so neither said the commands agree — and neither would have noticed if
    // one of them drifted.
    updateDirectory := ProjectWithNuGetDependency("nlc-shared-update", "UpdateDemo")
    removeDirectory := ProjectWithNuGetDependency("nlc-shared-remove", "RemoveDemo")

    updateRun := NlcIn(updateDirectory, "update Serilog")
    removeRun := NlcIn(removeDirectory, "remove Serilog")

    assert updateRun.Stderr.Trim() == "Package 'Serilog' not found in dependencies."
    assert updateRun.Stderr.Trim() == removeRun.Stderr.Trim()
    assert updateRun.ExitCode == removeRun.ExitCode
    assert updateRun.ExitCode == 1

    Directory.Delete(updateDirectory, true)
    Directory.Delete(removeDirectory, true)
}

test "every one of the six commands reaches its N#-owned implementation through nlc dispatch" {
    // THE CLAIM NO DELETED BODY COULD MAKE AT ALL. All 21 of them called `XCommand.Execute(...)` in
    // process, so a registry that lost the mapping from `nlc add` to `AddCommand` would have left
    // every one of them green while the shipped CLI reported an unknown command.
    add := Nlc("add --help")
    tidy := Nlc("tidy --help")
    update := Nlc("update --help")
    remove := Nlc("remove --help")
    clean := Nlc("clean --help")
    completion := Nlc("completion --help")

    assert add.ExitCode == 0
    assert tidy.ExitCode == 0
    assert update.ExitCode == 0
    assert remove.ExitCode == 0
    assert clean.ExitCode == 0
    assert completion.ExitCode == 0

    assert add.Stdout.Contains("N# Add Dependency")
    assert tidy.Stdout.Contains("N# Tidy")
    assert update.Stdout.Contains("N# Update Dependencies")
    assert remove.Stdout.Contains("N# Remove Dependency")
    assert clean.Stdout.Contains("N# Clean")
    assert completion.Stdout.Contains("completion")

    // …and the negative control: a name the registry does NOT carry fails
    unknown := Nlc("addd --help")
    assert unknown.ExitCode != 0
}


// ═══ THE TWO DECISIONS THAT RETIRE WITH A C# SUBJECT ══════════════════════════════════════════
//
// `Commands/QueryCommand.cs:108` and `Program.cs:581/:584/:633` are the closeout inventory's
// `(b)` bucket: residues that are not moved to an N# owner because the file holding them is itself
// scheduled for deletion. That is a reason not to MOVE them. It is not a reason to let them retire
// UNOBSERVED — a deletion that silently changes the order of an LLM-facing array, or the labels on a
// diff a human is about to apply, is exactly the kind of regression the campaign exists to prevent.
//
// The blocks below observe the SHIPPED BINARY, so they outlive whatever implements it. When
// `QueryCommand.cs` and `Program.cs` are deleted, these rows keep asking the same questions of
// whatever answers in their place, and a changed answer fails by name.

// ── `nlc query ast` — the compilation-unit ORDER ──────────────────────────────────────────────

func WriteOrderingProject(directory: string) {
    WriteProjectYml(directory,
        "name: AstOrdering\n"
        + "entry: Program.nl\n"
        + "outputType: exe\n"
        + "targetFramework: net10.0\n")
    File.WriteAllText(Path.Combine(directory, "Program.nl"), "func Main() {\n    print \"ok\"\n}\n")
    File.WriteAllText(Path.Combine(directory, "Zeta.nl"), "func Zed(): int {\n    return 1\n}\n")
    File.WriteAllText(Path.Combine(directory, "Beta.nl"), "func Bet(): int {\n    return 2\n}\n")
    File.WriteAllText(Path.Combine(directory, "alpha.nl"), "func Alp(): int {\n    return 3\n}\n")
}

func AstFileNameAt(payload: JsonElement, index: int): string {
    return Path.GetFileName(TextOf(ElementAt(payload.GetProperty("files"), index).GetProperty("file"))) ?? ""
}

test "nlc query ast orders its files ORDINALLY, so every capital sorts before every lowercase" {
    // THE DECISION: `QueryCommand.cs:108` sorts the compilation units with `StringComparer.Ordinal`.
    // Nothing anywhere asserted that before this block — no estate contract reads the order of the
    // `files` array, and the two `.tests.nl` comments that mention `CompilationUnits` are epitaphs
    // for deleted bodies. The choice is observable and consequential: an LLM diffing two `ast` runs
    // sees a reordered array as a change.
    //
    // `Beta.nl`, `Program.nl`, `Zeta.nl`, `alpha.nl` is the ORDINAL order. Under
    // `OrdinalIgnoreCase` — the other comparer a maintainer would reach for — `alpha.nl` would come
    // FIRST, so this fixture separates the two rather than merely agreeing with both.
    directory := NewTempDirectory("nlc-ast-order")
    WriteOrderingProject(directory)

    run := Nlc("query ast --project \"" + directory + "\"")

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0

    document := JsonDocument.Parse(run.Stdout)
    root := document.RootElement
    assert root.GetProperty("ok").GetBoolean()
    assert root.GetProperty("files").GetArrayLength() == 4

    assert AstFileNameAt(root, 0) == "Beta.nl"
    assert AstFileNameAt(root, 1) == "Program.nl"
    assert AstFileNameAt(root, 2) == "Zeta.nl"
    assert AstFileNameAt(root, 3) == "alpha.nl"
    document.Dispose()

    Directory.Delete(directory, true)
}

test "the ast order is STABLE across runs, so a consumer can diff two envelopes" {
    // The order above could be an accident of dictionary iteration rather than a sort. Two runs of
    // the same project answering the same sequence is what makes it a contract.
    directory := NewTempDirectory("nlc-ast-order-stable")
    WriteOrderingProject(directory)

    first := Nlc("query ast --project \"" + directory + "\"")
    second := Nlc("query ast --project \"" + directory + "\"")

    assert first.ExitCode == 0
    assert second.ExitCode == 0

    firstDocument := JsonDocument.Parse(first.Stdout)
    secondDocument := JsonDocument.Parse(second.Stdout)
    assert AstFileNameAt(firstDocument.RootElement, 0) == AstFileNameAt(secondDocument.RootElement, 0)
    assert AstFileNameAt(firstDocument.RootElement, 3) == AstFileNameAt(secondDocument.RootElement, 3)
    firstDocument.Dispose()
    secondDocument.Dispose()

    Directory.Delete(directory, true)
}

// ── `nlc format --diff` — the unified-diff LABELS ─────────────────────────────────────────────

func WriteMisformattedFile(path: string) {
    File.WriteAllText(path, "func  Main( ) {\n        print \"x\"\n}\n")
}

test "nlc format --diff labels the two sides a/PATH and b/PATH, git-style" {
    // THE DECISION: `Program.cs:633` composes `$"a/{relativePath}"` and `$"b/{relativePath}"`. The
    // RENDERER is already N# — `UnifiedDiff.nl` owns the `--- ` and `+++ ` prefixes — but
    // `UnifiedDiff.tests.nl` states outright that "a label is never inspected", so the N# side is
    // PROVEN INDIFFERENT to exactly the text C# decides. Nothing else observed it.
    //
    // The prefixes are what let the output be piped into `git apply` / `patch -p1`, so they are a
    // compatibility contract, not decoration.
    directory := NewTempDirectory("nlc-format-diff")
    WriteProjectYml(directory, "name: FormatDiff\nentry: messy.nl\noutputType: exe\ntargetFramework: net10.0\n")
    WriteMisformattedFile(Path.Combine(directory, "messy.nl"))

    run := Nlc("format --project \"" + directory + "\" --diff messy.nl")

    assert run.ExitCode == 0
    assert run.Stdout.Contains("--- a/messy.nl")
    assert run.Stdout.Contains("+++ b/messy.nl")

    // …and the before label really precedes the after label, which a pair of `Contains` cannot say.
    assert run.Stdout.IndexOf("--- a/messy.nl") < run.Stdout.IndexOf("+++ b/messy.nl")

    // A CONTROL: the label carries the PATH, not a fixed word. A file in a subdirectory proves the
    // relative path reaches the label instead of just its file name.
    nested := Path.Combine(directory, "sub")
    Directory.CreateDirectory(nested)
    WriteMisformattedFile(Path.Combine(nested, "deep.nl"))

    nestedRun := Nlc("format --project \"" + directory + "\" --diff sub/deep.nl")
    assert nestedRun.ExitCode == 0
    assert nestedRun.Stdout.Contains("--- a/sub/deep.nl")
    assert nestedRun.Stdout.Contains("+++ b/sub/deep.nl")

    Directory.Delete(directory, true)
}

test "nlc format --diff writes NOTHING for a file that is already formatted" {
    // The negative half of the same claim: the labels appear because a diff exists, not on every
    // run. Without this row the block above could pass against a command that always printed a
    // header.
    directory := NewTempDirectory("nlc-format-diff-clean")
    WriteProjectYml(directory, "name: FormatDiffClean\nentry: tidy.nl\noutputType: exe\ntargetFramework: net10.0\n")
    File.WriteAllText(Path.Combine(directory, "tidy.nl"), "func Main() {\n    print \"x\"\n}\n")

    run := Nlc("format --project \"" + directory + "\" --diff tidy.nl")

    assert run.ExitCode == 0
    assert !run.Stdout.Contains("--- a/")
    assert !run.Stdout.Contains("+++ b/")

    Directory.Delete(directory, true)
}

// A CHILD THAT IS FED ON STDIN — AND WHY IT GOES THROUGH A SHELL.
//
// The portable spelling is `RedirectStandardInput = true` followed by
// `process.StandardInput.Write(text)`. IT DOES NOT EMIT, and the measurement is narrower than that:
// a project whose ONLY unusual line is `startInfo.RedirectStandardInput = true` declines, while the
// same project with `RedirectStandardOutput` builds. The unmodeled member is the
// `ProcessStartInfo.RedirectStandardInput` SETTER, not `Process.StandardInput` — which is why
// `RunProcess` above can drain both output pipes and still not feed one.
// The recovery is not a weakening — a shell redirect is how a user actually reaches
// `--stdin` (`cat file.nl | nlc format --stdin`), so the route below is the documented one rather
// than a test-only harness trick. The source is written to a file first so no quoting of N# source
// has to survive two layers of shell.
func NlcWithStdinFile(arguments: string, inputPath: string): CliRun {
    command := "exec dotnet '" + CliDll() + "' " + arguments + " < '" + inputPath + "'"
    return RunProcess("/bin/sh", "-c \"" + command + "\"", Path.GetTempPath())
}

func WriteStdinSource(directory: string): string {
    path := Path.Combine(directory, "piped-source.nl")
    File.WriteAllText(path, "func  Main( ) {\n        print \"x\"\n}\n")
    return path
}

test "nlc format --stdin --diff calls the anonymous input stdin.nl on BOTH sides of the diff" {
    // THE DECISION: `Program.cs:581` names the piped source `stdin.nl` and `:584` labels the two
    // sides `a/stdin.nl` / `b/stdin.nl`. There is no file on disk, so the name is INVENTED — the
    // purest product decision in this bucket — and nothing observed it before this block.
    //
    // The name is not private: the formatter reports parse errors against it, and the diff is meant
    // to be applicable, so `stdin.nl` is what a user reads and what a tool matches on.
    directory := NewTempDirectory("nlc-format-stdin")
    source := WriteStdinSource(directory)

    run := NlcWithStdinFile("format --stdin --diff", source)

    assert run.ExitCode == 0
    assert run.Stderr.Trim().Length == 0
    assert run.Stdout.Contains("--- a/stdin.nl")
    assert run.Stdout.Contains("+++ b/stdin.nl")
    assert run.Stdout.IndexOf("--- a/stdin.nl") < run.Stdout.IndexOf("+++ b/stdin.nl")

    // The diff is real, not just a header: the formatter's answer is in the body.
    assert run.Stdout.Contains("-func  Main( ) {")
    assert run.Stdout.Contains("+func Main() {")

    Directory.Delete(directory, true)
}

test "nlc format --stdin without --diff writes the formatted source and never names stdin.nl" {
    // The control for the block above: `stdin.nl` belongs to the DIFF arm. On the plain arm the
    // invented name never reaches the user, so a build that leaked it everywhere fails here.
    directory := NewTempDirectory("nlc-format-stdin-plain")
    source := WriteStdinSource(directory)

    run := NlcWithStdinFile("format --stdin", source)

    assert run.ExitCode == 0
    assert run.Stdout == "func Main() {\n    print \"x\"\n}\n"
    assert !run.Stdout.Contains("stdin.nl")

    Directory.Delete(directory, true)
}

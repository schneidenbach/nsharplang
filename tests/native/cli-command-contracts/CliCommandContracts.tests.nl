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

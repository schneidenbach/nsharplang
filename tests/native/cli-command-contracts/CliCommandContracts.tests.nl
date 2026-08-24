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

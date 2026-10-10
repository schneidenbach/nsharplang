namespace NSharpLang.GateScriptContracts.Tests

import System
import System.Collections.Generic
import System.IO

// ─── THE DEVELOPMENT ESTATE EVIDENCE GUARD ────────────────────────────────────────────────────
//
// `scripts/dev.sh --estate` used to trust `dotnet test`'s exit code alone. A filtered run can
// report success without executing a test, so every row below installs a disposable fake `dotnet`
// ahead of PATH and invokes the script with `--no-build`. The fake restore is silent and succeeds;
// only its test output varies, so no real build, restore, or cache is touched.
func FakeDotnetScript(testOutput: string, testExitCode: int): string {
    return "#!/usr/bin/env bash\n" + "if [ \"${1:-}\" = \"test\" ]; then\n" + "  cat <<'TEST_OUTPUT'\n" + testOutput + "TEST_OUTPUT\n" + "  exit " + testExitCode.ToString() + "\n" + "fi\n" + "exit 0\n"
}

func MakeFakeDotnet(directory: string, testOutput: string, testExitCode: int): string {
    bin := Path.Combine(directory, "bin")
    Directory.CreateDirectory(bin)
    dotnet := Path.Combine(bin, "dotnet")
    File.WriteAllText(dotnet, FakeDotnetScript(testOutput, testExitCode))

    chmod := new ProcessLaunch("chmod", RepositoryRoot(), 60000)
    chmod.Arguments.Add("+x")
    chmod.Arguments.Add(dotnet)
    chmodRun := Run(chmod)
    if chmodRun.ExitCode != 0 {
        throw new InvalidOperationException("Could not make synthetic dotnet executable: " + chmodRun.Report())
    }

    return bin
}

func RunDevEstateWithFakeDotnet(testOutput: string, testExitCode: int): ProcessRun {
    temporaryRoot := NewTempDirectory("nsharp-dev-estate-evidence")
    try {
        bin := MakeFakeDotnet(temporaryRoot, testOutput, testExitCode)
        launch := new ProcessLaunch("bash", RepositoryRoot(), 60000)
        launch.Arguments.Add("scripts/dev.sh")
        launch.Arguments.Add("--no-build")
        launch.Arguments.Add("--estate")
        launch.Arguments.Add("DeliberatelyMissing")
        launch.WithEnvironment("PATH", bin + ":" + (Environment.GetEnvironmentVariable("PATH") ?? ""))
        return Run(launch)
    } finally {
        DeleteTempDirectory(temporaryRoot)
    }
}

func RequireMissingEstateEvidence(run: ProcessRun) {
    assert run.ExitCode != 0, "dev.sh accepted output that did not prove a test run: " + run.Report()
    assert run.Stdout.Contains("Estate rows did not produce a nonempty successful test summary"), run.Report()
    assert run.Stdout.Contains("Expected one VSTest or N# native summary line with Passed: > 0, Failed: 0, and Total: > 0."), run.Report()
    assert !run.Stdout.Contains("Estate rows passed"), run.Report()
}

test "dev estate rejects an exit-zero test command with no output" {
    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet("", 0))
}

test "dev estate rejects no-matching-test output that exits zero" {
    run := RunDevEstateWithFakeDotnet("No test matches the given testcase filter.\n", 0)

    RequireMissingEstateEvidence(run)
    assert run.Stdout.Contains("No test matches the given testcase filter."), run.Report()
}

test "dev estate rejects a zero-total summary that exits zero" {
    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet("Passed: 0, Failed: 0, Skipped: 0, Total: 0\n", 0))
}

test "dev estate rejects a skipped-only summary that exits zero" {
    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet("Passed: 0, Failed: 0, Skipped: 2, Total: 2\n", 0))
}

test "dev estate rejects a failed summary even when the test process exits zero" {
    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet("Passed: 2, Failed: 1, Skipped: 0, Total: 3\n", 0))
}

test "dev estate rejects mixed failed and passing summaries" {
    output := "Failed!  - Failed: 1, Passed: 2, Skipped: 0, Total: 3, Duration: 18 ms\n" + "Passed!  - Failed: 0, Passed: 2, Skipped: 0, Total: 2, Duration: 18 ms\n"

    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet(output, 0))
}

test "dev estate rejects counters split across separate lines" {
    output := "Passed: 2\nFailed: 0\nSkipped: 0\nTotal: 2\n"

    RequireMissingEstateEvidence(RunDevEstateWithFakeDotnet(output, 0))
}

test "dev estate accepts a positive VSTest summary" {
    run := RunDevEstateWithFakeDotnet("Passed!  - Failed: 0, Passed: 2, Skipped: 0, Total: 2, Duration: 18 ms\n", 0)

    assert run.ExitCode == 0, run.Report()
    assert run.Stdout.Contains("Estate rows passed"), run.Report()
}

test "dev estate accepts the N# native test summary format" {
    run := RunDevEstateWithFakeDotnet("Passed: 2, Failed: 0, Skipped: 0, Total: 2\n", 0)

    assert run.ExitCode == 0, run.Report()
    assert run.Stdout.Contains("Estate rows passed"), run.Report()
}

test "dev estate preserves a nonzero test process exit" {
    run := RunDevEstateWithFakeDotnet("Passed: 2, Failed: 0, Skipped: 0, Total: 2\n", 23)

    assert run.ExitCode == 23, run.Report()
    assert run.Stdout.Contains("Estate rows failed"), run.Report()
    assert !run.Stdout.Contains("Estate rows passed"), run.Report()
}

// ─── AN EDIT TO ONE SLICE PAYS FOR THAT SLICE ─────────────────────────────────────────────────
//
// An estate-only run used to build the whole CLI first -- compiling the edited slice product-only
// and then again tests-included -- and to restore, build and start a test host for all six estate
// projects whatever the filter named. These rows run the real script with a fake `dotnet` that
// RECORDS every invocation, so the rows read which builds and which projects the script asked for.
func RecordingFakeDotnetScript(log: string): string {
    return "#!/usr/bin/env bash\n" + "printf '%s\\n' \"$*\" >> '" + log + "'\n" + "if [ \"${1:-}\" = \"test\" ]; then\n" + "  echo 'Passed!  - Failed: 0, Passed: 2, Skipped: 0, Total: 2, Duration: 18 ms'\n" + "fi\n" + "exit 0\n"
}

class RecordedDevRun {
    Run: ProcessRun
    Invocations: string[]
    constructor(run: ProcessRun, invocations: string[]) {
        this.Run = run
        this.Invocations = invocations
    }
}

func RunDevWithRecordingDotnet(arguments: string[]): RecordedDevRun {
    temporaryRoot := NewTempDirectory("nsharp-dev-recorded")
    try {
        log := Path.Combine(temporaryRoot, "dotnet.log")
        File.WriteAllText(log, "")
        bin := Path.Combine(temporaryRoot, "bin")
        Directory.CreateDirectory(bin)
        dotnet := Path.Combine(bin, "dotnet")
        File.WriteAllText(dotnet, RecordingFakeDotnetScript(log))
        chmod := new ProcessLaunch("chmod", RepositoryRoot(), 60000)
        chmod.Arguments.Add("+x")
        chmod.Arguments.Add(dotnet)
        chmodRun := Run(chmod)
        if chmodRun.ExitCode != 0 {
            throw new InvalidOperationException("Could not make the recording dotnet executable: " + chmodRun.Report())
        }

        launch := new ProcessLaunch("bash", RepositoryRoot(), 60000)
        launch.Arguments.Add("scripts/dev.sh")
        for argument in arguments {
            launch.Arguments.Add(argument)
        }
        launch.WithEnvironment("PATH", bin + ":" + (Environment.GetEnvironmentVariable("PATH") ?? ""))
        run := Run(launch)
        return new RecordedDevRun(run, File.ReadAllLines(log))
    } finally {
        DeleteTempDirectory(temporaryRoot)
    }
}

func RecordedInvocationsStartingWith(recorded: RecordedDevRun, verb: string): List<string> {
    matching := new List<string>()
    for invocation in recorded.Invocations {
        if invocation.StartsWith(verb + " ", StringComparison.Ordinal) {
            matching.Add(invocation)
        }
    }

    return matching
}

test "dev estate builds no CLI when only estate rows are selected, and still builds it for a native slice" {
    estateOnly := RunDevWithRecordingDotnet(["--estate", "ColumnarLambdaStatementBodyTests"])
    assert estateOnly.Run.ExitCode == 0, estateOnly.Run.Report()
    assert estateOnly.Run.Stdout.Contains("Estate rows only: the CLI is not built"), estateOnly.Run.Report()
    assert RecordedInvocationsStartingWith(estateOnly, "build").Count == 0, string.Join("\n", estateOnly.Invocations)

    buildOnly := RunDevWithRecordingDotnet(["--build-only"])
    assert buildOnly.Run.ExitCode == 0, buildOnly.Run.Report()
    builds := RecordedInvocationsStartingWith(buildOnly, "build")
    assert builds.Count == 1, string.Join("\n", buildOnly.Invocations)
    assert builds[0].Contains("src/NSharpLang.Cli/Cli.csproj"), builds[0]
}

test "dev estate runs only the estate projects whose row names can contain the filter" {
    recorded := RunDevWithRecordingDotnet(["--no-build", "--estate", "ColumnarLambdaStatementBodyTests"])
    assert recorded.Run.ExitCode == 0, recorded.Run.Report()
    tests := RecordedInvocationsStartingWith(recorded, "test")
    assert tests.Count == 1, string.Join("\n", recorded.Invocations)
    assert tests[0].Contains("src/NSharpLang.Compiler.Emit/NSharpLang.Compiler.Emit.csproj"), tests[0]
    for skipped in ["Syntax", "Core", "Plan", "CodeIntel", "Tooling", "Driver"] {
        assert recorded.Run.Stdout.Contains("NSharpLang.Compiler." + skipped + ": skipped, no row name can contain 'ColumnarLambdaStatementBodyTests'"), skipped + ": " + recorded.Run.Report()
    }
}

test "dev estate runs every estate project when the filter is an expression or no row name can contain it" {
    for filter in ["DeliberatelyMissing", "Columnar|Analyzer"] {
        recorded := RunDevWithRecordingDotnet(["--no-build", "--estate", filter])
        assert recorded.Run.ExitCode == 0, filter + ": " + recorded.Run.Report()
        assert RecordedInvocationsStartingWith(recorded, "test").Count == 7, filter + ": " + string.Join("\n", recorded.Invocations)
        assert !recorded.Run.Stdout.Contains("skipped, no row name"), filter + ": " + recorded.Run.Report()
    }
}

// ─── `--since` BY COMPILER.CORE SLICE DIRECTORY ───────────────────────────────────────────────
//
// Compiler.Core's sources sit in eight slice directories, and `dev.sh --since` maps a changed path
// to a selection with shell `case` globs. A `case` glob's `*` also matches `/`, so a slice that is
// not spelled before the `src/NSharpLang.Compiler.Core/*` catch-all silently falls into it and
// every edit selects EVERYTHING. Each row copies the real script into a throwaway git repository,
// leaves ONE changed file in it, and reads the selection the script prints -- with a fake `dotnet`
// ahead of PATH and `--no-build`, so nothing is built or run for real.
func DevSinceRun(changedPath: string): ProcessRun {
    root := NewTempDirectory("nsharp-dev-since")
    try {
        // The fake `dotnet` lives BESIDE the repository, not in it, or it would be a changed path too.
        bin := MakeFakeDotnet(root, "Passed: 2, Failed: 0, Skipped: 0, Total: 2\n", 0)
        repository := Path.Combine(root, "repository")
        scripts := Path.Combine(repository, "scripts")
        Directory.CreateDirectory(scripts)
        File.Copy(Path.Combine(Path.Combine(RepositoryRoot(), "scripts"), "dev.sh"), Path.Combine(scripts, "dev.sh"))
        File.WriteAllText(Path.Combine(repository, "README.md"), "dev.sh --since probe\n")
        DevSinceGit(repository, ["init", "-q"])
        DevSinceGit(repository, ["add", "-A"])
        DevSinceGit(repository, ["-c", "user.name=probe", "-c", "user.email=probe@example.invalid", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--no-gpg-sign", "-m", "base"])

        changed := Path.Combine(repository, changedPath)
        Directory.CreateDirectory(Path.GetDirectoryName(changed) ?? repository)
        File.WriteAllText(changed, "// changed\n")

        launch := new ProcessLaunch("bash", repository, 60000)
        launch.Arguments.Add("scripts/dev.sh")
        launch.Arguments.Add("--no-build")
        launch.Arguments.Add("--since")
        launch.WithEnvironment("PATH", bin + ":" + (Environment.GetEnvironmentVariable("PATH") ?? ""))
        return Run(launch)
    } finally {
        DeleteTempDirectory(root)
    }
}

func DevSinceGit(root: string, arguments: string[]) {
    git := new ProcessLaunch("git", root, 60000)
    for argument in arguments {
        git.Arguments.Add(argument)
    }

    run := Run(git)
    if run.ExitCode != 0 {
        throw new InvalidOperationException("git failed in the dev.sh probe repository: " + run.Report())
    }
}

// The words of the one `Change-aware selection (since HEAD): ...` line, sorted. The script sorts
// them with the locale's `sort`, so the rows compare them as a set rather than as a spelling.
func DevSinceWords(run: ProcessRun): string {
    marker := "Change-aware selection (since HEAD): "
    start := run.Stderr.IndexOf(marker, StringComparison.Ordinal)
    if start < 0 {
        return "<no selection line>"
    }

    rest := run.Stderr.Substring(start + marker.Length)
    newline := rest.IndexOf("\n", StringComparison.Ordinal)
    if newline >= 0 {
        rest = rest.Substring(0, newline)
    }

    words := new List<string>(rest.Split(' ', StringSplitOptions.RemoveEmptyEntries))
    words.Sort(StringComparer.Ordinal)
    return string.Join(" ", words)
}

test "dev since selects each Compiler.Core slice directory's own subsystem" {
    slices: string[] = ["Semantics"]
    expected: string[] = ["Analyzer estate"]
    index := 0
    while index < slices.Length {
        run := DevSinceRun("src/NSharpLang.Compiler.Core/" + slices[index] + "/Probe.nl")
        assert run.ExitCode == 0, slices[index] + ": " + run.Report()
        assert DevSinceWords(run) == expected[index], slices[index] + " selected '" + DevSinceWords(run) + "': " + run.Report()
        assert !run.Stderr.Contains("EVERYTHING (fail-safe)"), slices[index] + ": " + run.Report()
        index = index + 1
    }
}

test "dev since treats a Compiler.Core Model change as central and runs everything" {
    run := DevSinceRun("src/NSharpLang.Compiler.Core/Model/Probe.nl")

    assert run.ExitCode == 0, run.Report()
    assert run.Stderr.Contains("Change-aware selection: EVERYTHING (fail-safe). Triggers:"), run.Report()
    assert run.Stderr.Contains("src/NSharpLang.Compiler.Core/Model/Probe.nl (Compiler.Core Model slice: the AST and shared model every slice reads)"), run.Report()
}

test "dev since treats a change to the carved Compiler.Model project as central and runs everything" {
    run := DevSinceRun("src/NSharpLang.Compiler.Model/Probe.nl")

    assert run.ExitCode == 0, run.Report()
    assert run.Stderr.Contains("Change-aware selection: EVERYTHING (fail-safe). Triggers:"), run.Report()
    assert run.Stderr.Contains("src/NSharpLang.Compiler.Model/Probe.nl (Compiler.Model: the AST and shared model every slice reads)"), run.Report()
}

test "dev since selects the carved Compiler.Syntax project's subsystem, and runs everything for its build configuration" {
    run := DevSinceRun("src/NSharpLang.Compiler.Syntax/Probe.nl")
    assert run.ExitCode == 0, run.Report()
    assert DevSinceWords(run) == "Columnar estate", "selected '" + DevSinceWords(run) + "': " + run.Report()
    assert !run.Stderr.Contains("EVERYTHING (fail-safe)"), run.Report()

    for configuration in ["project.yml", "NSharpLang.Compiler.Syntax.csproj", "global.json"] {
        configured := DevSinceRun("src/NSharpLang.Compiler.Syntax/" + configuration)
        assert configured.ExitCode == 0, configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("Change-aware selection: EVERYTHING (fail-safe). Triggers:"), configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("src/NSharpLang.Compiler.Syntax/" + configuration + " (Compiler.Syntax build config)"), configuration + ": " + configured.Report()
    }
}

test "dev since selects the carved Compiler.Tooling project's subsystem, and runs everything for its build configuration" {
    run := DevSinceRun("src/NSharpLang.Compiler.Tooling/Probe.nl")
    assert run.ExitCode == 0, run.Report()
    assert DevSinceWords(run) == "estate", "selected '" + DevSinceWords(run) + "': " + run.Report()
    assert !run.Stderr.Contains("EVERYTHING (fail-safe)"), run.Report()

    for configuration in ["project.yml", "NSharpLang.Compiler.Tooling.csproj", "global.json"] {
        configured := DevSinceRun("src/NSharpLang.Compiler.Tooling/" + configuration)
        assert configured.ExitCode == 0, configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("Change-aware selection: EVERYTHING (fail-safe). Triggers:"), configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("src/NSharpLang.Compiler.Tooling/" + configuration + " (Compiler.Tooling build config)"), configuration + ": " + configured.Report()
    }
}

test "dev since selects the carved Compiler.Plan project's subsystem, and runs everything for its build configuration" {
    run := DevSinceRun("src/NSharpLang.Compiler.Plan/Probe.nl")
    assert run.ExitCode == 0, run.Report()
    assert DevSinceWords(run) == "Columnar estate", "selected '" + DevSinceWords(run) + "': " + run.Report()
    assert !run.Stderr.Contains("EVERYTHING (fail-safe)"), run.Report()

    for configuration in ["project.yml", "NSharpLang.Compiler.Plan.csproj", "global.json"] {
        configured := DevSinceRun("src/NSharpLang.Compiler.Plan/" + configuration)
        assert configured.ExitCode == 0, configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("Change-aware selection: EVERYTHING (fail-safe). Triggers:"), configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("src/NSharpLang.Compiler.Plan/" + configuration + " (Compiler.Plan build config)"), configuration + ": " + configured.Report()
    }
}

test "dev since selects the carved Compiler.Emit project's subsystem, and runs everything for its build configuration" {
    run := DevSinceRun("src/NSharpLang.Compiler.Emit/Probe.nl")
    assert run.ExitCode == 0, run.Report()
    assert DevSinceWords(run) == "Columnar estate", "selected '" + DevSinceWords(run) + "': " + run.Report()
    assert !run.Stderr.Contains("EVERYTHING (fail-safe)"), run.Report()

    for configuration in ["project.yml", "NSharpLang.Compiler.Emit.csproj", "global.json"] {
        configured := DevSinceRun("src/NSharpLang.Compiler.Emit/" + configuration)
        assert configured.ExitCode == 0, configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("Change-aware selection: EVERYTHING (fail-safe). Triggers:"), configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("src/NSharpLang.Compiler.Emit/" + configuration + " (Compiler.Emit build config)"), configuration + ": " + configured.Report()
    }
}

test "dev since selects the carved Compiler.CodeIntel project's subsystem, and runs everything for its build configuration" {
    run := DevSinceRun("src/NSharpLang.Compiler.CodeIntel/Probe.nl")
    assert run.ExitCode == 0, run.Report()
    assert DevSinceWords(run) == "LanguageServer completion doc estate query", "selected '" + DevSinceWords(run) + "': " + run.Report()
    assert !run.Stderr.Contains("EVERYTHING (fail-safe)"), run.Report()

    for configuration in ["project.yml", "NSharpLang.Compiler.CodeIntel.csproj", "global.json"] {
        configured := DevSinceRun("src/NSharpLang.Compiler.CodeIntel/" + configuration)
        assert configured.ExitCode == 0, configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("Change-aware selection: EVERYTHING (fail-safe). Triggers:"), configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("src/NSharpLang.Compiler.CodeIntel/" + configuration + " (Compiler.CodeIntel build config)"), configuration + ": " + configured.Report()
    }
}

test "dev since selects the carved Compiler.Driver project's subsystem, and runs everything for its build configuration" {
    run := DevSinceRun("src/NSharpLang.Compiler.Driver/Probe.nl")
    assert run.ExitCode == 0, run.Report()
    assert DevSinceWords(run) == "cli daemon estate", "selected '" + DevSinceWords(run) + "': " + run.Report()
    assert !run.Stderr.Contains("EVERYTHING (fail-safe)"), run.Report()

    for configuration in ["project.yml", "NSharpLang.Compiler.Driver.csproj", "global.json"] {
        configured := DevSinceRun("src/NSharpLang.Compiler.Driver/" + configuration)
        assert configured.ExitCode == 0, configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("Change-aware selection: EVERYTHING (fail-safe). Triggers:"), configuration + ": " + configured.Report()
        assert configured.Stderr.Contains("src/NSharpLang.Compiler.Driver/" + configuration + " (Compiler.Driver build config)"), configuration + ": " + configured.Report()
    }
}

test "dev since still runs everything for a Compiler.Core file outside every slice directory" {
    run := DevSinceRun("src/NSharpLang.Compiler.Core/Stray.nl")

    assert run.ExitCode == 0, run.Report()
    assert run.Stderr.Contains("Change-aware selection: EVERYTHING (fail-safe). Triggers:"), run.Report()
    assert run.Stderr.Contains("src/NSharpLang.Compiler.Core/Stray.nl (shared compiler file)"), run.Report()
}

test "dev list names the slice directories and the carved projects that hold estate rows" {
    run := Run(BashLaunch("scripts/dev.sh --list", 60000))

    assert run.ExitCode == 0, run.Report()
    assert run.Stdout.Contains("estate    src/NSharpLang.Compiler.Core/<slice>/*.tests.nl (run with --estate; slices: Model Semantics)"), run.Report()
    assert run.Stdout.Contains("estate    src/NSharpLang.Compiler.Syntax/*.tests.nl (run with --estate)"), run.Report()
    assert run.Stdout.Contains("estate    src/NSharpLang.Compiler.Plan/*.tests.nl (run with --estate)"), run.Report()
    assert run.Stdout.Contains("estate    src/NSharpLang.Compiler.Emit/*.tests.nl (run with --estate)"), run.Report()
    assert run.Stdout.Contains("estate    src/NSharpLang.Compiler.CodeIntel/*.tests.nl (run with --estate)"), run.Report()
    assert run.Stdout.Contains("estate    src/NSharpLang.Compiler.Tooling/*.tests.nl (run with --estate)"), run.Report()
    assert run.Stdout.Contains("estate    src/NSharpLang.Compiler.Driver/*.tests.nl (run with --estate)"), run.Report()
}

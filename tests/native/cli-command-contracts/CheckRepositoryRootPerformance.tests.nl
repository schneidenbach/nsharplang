namespace NSharpLang.CliCommandContracts.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text.Json

// These two figures are the measured structural baseline for this repository root on 2026-10-05.
// The parser counter includes source parses reached through project references and file imports;
// checkedFiles is the workspace's one-owner census. Lower parser/reference counts are improvements.
func CliRootCheckExpectedMembers(): int => 223
func CliRootCheckExpectedFiles(): int => 1991
func CliRootCheckExpectedFilesParsed(): long => 5258
func CliRootCheckMaximumReferenceImages(): long => 18184

// Quiet-machine timing measurement: about 64 s. Keep the 2x budget (128 s) independent from the
// 15-minute hard timeout: that one only catches a stuck CLI and never judges performance.
func CliRootCheckQuietWallBudgetMs(): long => 128000
func CliRootCheckHangTimeoutMs(): int => 900000

class CliRootCheckMachineLoad {
    LoadThousandths: long
    Cores: int

    constructor(loadThousandths: long, cores: int) {
        LoadThousandths = loadThousandths
        Cores = cores
    }
}

func CliRootCheckParseInteger(text: string): long {
    if text.Length == 0 {
        return -1
    }

    value := 0L
    i := 0
    while i < text.Length {
        c := text[i]
        if c < '0' || c > '9' {
            return -1
        }

        value = value * 10 + (c - '0')
        i = i + 1
    }

    return value
}

func CliRootCheckParseFixed3(text: string): long {
    trimmed := text.Trim()
    if trimmed.Length == 0 {
        return -1
    }

    dot := trimmed.IndexOf(".", StringComparison.Ordinal)
    if dot < 0 {
        whole := CliRootCheckParseInteger(trimmed)
        if whole < 0 {
            return -1
        }
        return whole * 1000
    }

    wholeText := trimmed.Substring(0, dot)
    fractionText := trimmed.Substring(dot + 1)
    if wholeText.Length == 0 || fractionText.Length == 0 || fractionText.Length > 3 {
        return -1
    }

    whole := CliRootCheckParseInteger(wholeText)
    fraction := CliRootCheckParseInteger(fractionText)
    if whole < 0 || fraction < 0 {
        return -1
    }

    scale := 1L
    i := fractionText.Length
    while i < 3 {
        scale = scale * 10
        i = i + 1
    }
    return whole * 1000 + fraction * scale
}

func CliRootCheckIsLoadSeparator(c: char): bool {
    return c == ' ' || c == '\t' || c == ',' || c == '{' || c == '}'
}

func CliRootCheckFirstLoadToken(text: string, start: int): string {
    i := start
    while i < text.Length && CliRootCheckIsLoadSeparator(text[i]) {
        i = i + 1
    }

    from := i
    while i < text.Length && !CliRootCheckIsLoadSeparator(text[i]) {
        i = i + 1
    }

    if i <= from {
        return ""
    }
    return text.Substring(from, i - from)
}

func CliRootCheckLoadThousandths(text: string): long {
    marker := text.IndexOf("load average", StringComparison.OrdinalIgnoreCase)
    if marker >= 0 {
        tail := text.Substring(marker)
        colon := tail.IndexOf(":", StringComparison.Ordinal)
        if colon < 0 {
            return -1
        }
        return CliRootCheckParseFixed3(CliRootCheckFirstLoadToken(tail, colon + 1))
    }

    if text.Trim().StartsWith("{") {
        return CliRootCheckParseFixed3(CliRootCheckFirstLoadToken(text, 0))
    }
    return -1
}

func CliRootCheckLoadAverageText(): string {
    if OperatingSystem.IsMacOS() {
        sysctl := RunProcess("sysctl", "-n vm.loadavg", Path.GetTempPath())
        if sysctl.ExitCode == 0 {
            return sysctl.Stdout.Trim()
        }
    }

    if OperatingSystem.IsMacOS() || OperatingSystem.IsLinux() {
        uptime := RunProcess("/usr/bin/uptime", "", Path.GetTempPath())
        if uptime.ExitCode == 0 {
            return uptime.Stdout.Trim()
        }
    }
    return ""
}

func CliRootCheckProcessorCount(): int {
    if OperatingSystem.IsMacOS() {
        run := RunProcess("sysctl", "-n hw.logicalcpu", Path.GetTempPath())
        if run.ExitCode == 0 {
            return (int)CliRootCheckParseInteger(run.Stdout.Trim())
        }
    }

    if OperatingSystem.IsLinux() {
        run := RunProcess("nproc", "", Path.GetTempPath())
        if run.ExitCode == 0 {
            return (int)CliRootCheckParseInteger(run.Stdout.Trim())
        }
    }
    return -1
}

// Match BenchLoadRefusesTimingJudgement: unreadable load is unjudged, and the threshold is one
// fifth of the logical cores (2.0 on this 10-core machine). Load only gates the timing assertion.
func CliRootCheckLoadThresholdThousandths(cores: int): long {
    if cores <= 0 {
        return 2000
    }
    return cores * 200
}

func CliRootCheckReadMachineLoad(): CliRootCheckMachineLoad {
    return new CliRootCheckMachineLoad(
        CliRootCheckLoadThousandths(CliRootCheckLoadAverageText()),
        CliRootCheckProcessorCount()
    )
}

func CliRootCheckRefusesTimingJudgement(load: CliRootCheckMachineLoad): bool {
    return load.LoadThousandths < 0 || load.LoadThousandths >= CliRootCheckLoadThresholdThousandths(load.Cores)
}

func CliRootCheckLoadText(load: CliRootCheckMachineLoad): string {
    if load.LoadThousandths < 0 {
        return "unknown"
    }

    whole := load.LoadThousandths / 1000
    fraction := load.LoadThousandths % 1000
    if fraction == 0 {
        return whole.ToString()
    }
    if fraction % 100 == 0 {
        return whole.ToString() + "." + (fraction / 100).ToString()
    }
    if fraction % 10 == 0 {
        return whole.ToString() + "." + (fraction / 10).ToString("D2")
    }
    return whole.ToString() + "." + fraction.ToString("D3")
}

func CliRootCheckShouldSkipDirectory(name: string): bool {
    if String.Equals(name, ".context", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, ".git", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, ".github", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, ".hermes", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, ".vscode", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, ".vscode-test", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, ".worktrees", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, "bin", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, "bootstrap", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, "node_modules", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, "nsharp", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, "obj", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    if String.Equals(name, "out", StringComparison.OrdinalIgnoreCase) {
        return true
    }
    return false
}

func CliRootCheckDiscoverNestedProjects(directory: string, roots: List<string>): void {
    for subdirectory in Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly) {
        name := Path.GetFileName(subdirectory) ?? ""
        if CliRootCheckShouldSkipDirectory(name) || File.Exists(Path.Combine(subdirectory, ".git")) || Directory.Exists(Path.Combine(subdirectory, ".git")) {
            continue
        }

        if File.Exists(Path.Combine(subdirectory, "project.yml")) {
            roots.Add(NormalizedFullPath(subdirectory))
        }
        CliRootCheckDiscoverNestedProjects(subdirectory, roots)
    }
}

func CliRootCheckExpectedProjectRoots(repositoryRoot: string): List<string> {
    roots := new List<string>()
    if File.Exists(Path.Combine(repositoryRoot, "project.yml")) || Directory.GetFiles(repositoryRoot, "*.nl", SearchOption.TopDirectoryOnly).Length > 0 {
        roots.Add(NormalizedFullPath(repositoryRoot))
    }
    CliRootCheckDiscoverNestedProjects(repositoryRoot, roots)
    return roots
}

func CliRootCheckFindProject(roots: List<string>, candidate: string): bool {
    for root in roots {
        if EquivalentProcessPath(root, candidate) {
            return true
        }
    }
    return false
}

func CliRootCheckWriteGateRecord(repositoryRoot: string, line: string): bool {
    path := Path.Combine(Path.Combine(Path.Combine(repositoryRoot, "artifacts"), "cli-command-contracts"), "root-check-last-run.txt")
    try {
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? "")
        File.WriteAllText(path, line + "\n")
        return true
    } catch {
        return false
    }
}

test "nlc check checks each repository project once and pins workspace work while load judges wall time" {
    repositoryRoot := CliRepositoryRoot()
    load := CliRootCheckReadMachineLoad()
    statsPath := Path.Combine(Path.GetTempPath(), "nsharp-check-workspace-stats-" + Guid.NewGuid().ToString("N") + ".json")
    startInfo := new ProcessStartInfo {
        FileName: "dotnet",
        Arguments: "\"" + CliDll() + "\" check --project \"" + repositoryRoot + "\" --json --stats=\"" + statsPath + "\"",
        WorkingDirectory: repositoryRoot
    }
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    startTicks := DateTime.UtcNow.Ticks
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(CliRootCheckHangTimeoutMs()) {
        process.Kill()
        process.WaitForExit()
        process.Dispose()
        if File.Exists(statsPath) {
            File.Delete(statsPath)
        }
        throw new TimeoutException("nlc check --project <repository-root> --json exceeded the 900000 ms hang detector.")
    }

    endTicks := DateTime.UtcNow.Ticks
    exitCode := process.ExitCode
    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    process.Dispose()
    wallMs := (endTicks - startTicks) / 10000

    assert File.Exists(statsPath), "nlc check did not write the requested --stats file. stdout=" + stdout + " stderr=" + stderr
    statsDocument := JsonDocument.Parse(File.ReadAllText(statsPath))
    File.Delete(statsPath)
    stats := statsDocument.RootElement
    assert stats.GetProperty("schema").GetString() == "nsharp.cli-stats"
    assert stats.GetProperty("schemaVersion").GetInt32() == 1
    assert TextOf(stats.GetProperty("command")) == "check"
    assert stats.GetProperty("exitCode").GetInt32() == exitCode
    assert exitCode == 1, stdout + stderr
    assert stderr.Length == 0, stderr

    document := JsonDocument.Parse(stdout)
    root := document.RootElement
    assert root.GetProperty("schemaVersion").GetInt32() == 2, stdout
    assert TextOf(root.GetProperty("command")) == "check"
    assert !root.GetProperty("ok").GetBoolean()
    assert EquivalentProcessPath(TextOf(root.GetProperty("projectRoot")), NormalizedFullPath(repositoryRoot))

    expectedRoots := CliRootCheckExpectedProjectRoots(repositoryRoot)
    projects := root.GetProperty("projects")
    assert expectedRoots.Count == CliRootCheckExpectedMembers(), "workspace project census changed: expected 223 project.yml roots, found " + expectedRoots.Count.ToString()
    assert projects.GetArrayLength() == expectedRoots.Count, "workspace returned " + projects.GetArrayLength().ToString() + " member results for " + expectedRoots.Count.ToString() + " discovered project roots"

    checkedFiles := 0
    memberErrors := 0
    memberWarnings := 0
    memberInfo := 0
    observedRoots := new List<string>()
    expectedCoreRoot := NormalizedFullPath(Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Compiler.Core"))
    foundCoreDiagnostics := false
    for member in projects.EnumerateArray() {
        memberRoot := TextOf(member.GetProperty("projectRoot"))
        assert CliRootCheckFindProject(expectedRoots, memberRoot), "workspace returned an undiscovered project: " + memberRoot
        assert !CliRootCheckFindProject(observedRoots, memberRoot), "workspace checked a member more than once: " + memberRoot
        observedRoots.Add(memberRoot)

        memberFiles := member.GetProperty("checkedFiles").GetInt32()
        checkedFiles = checkedFiles + memberFiles
        summary := member.GetProperty("summary")
        memberErrors = memberErrors + summary.GetProperty("errors").GetInt32()
        memberWarnings = memberWarnings + summary.GetProperty("warnings").GetInt32()
        memberInfo = memberInfo + summary.GetProperty("info").GetInt32()
        assert member.GetProperty("results").GetArrayLength() == summary.GetProperty("errors").GetInt32() + summary.GetProperty("warnings").GetInt32() + summary.GetProperty("info").GetInt32(), "member diagnostic rows disagree with its summary: " + memberRoot

        if EquivalentProcessPath(memberRoot, expectedCoreRoot) {
            foundCoreDiagnostics = true
            assert member.GetProperty("results").GetArrayLength() > 0, stdout
            assert summary.GetProperty("errors").GetInt32() > 0, stdout
        }
    }

    assert observedRoots.Count == expectedRoots.Count, "not every discovered project root had exactly one result"
    assert foundCoreDiagnostics, "the workspace omitted Compiler.Core's diagnostics"
    assert checkedFiles == CliRootCheckExpectedFiles(), "checkedFiles changed from the measured 1,991 source files: " + checkedFiles.ToString()
    assert root.GetProperty("checkedFiles").GetInt32() == checkedFiles, "workspace checkedFiles does not equal the sum of its member rows"
    assert root.GetProperty("summary").GetProperty("errors").GetInt32() == memberErrors, "workspace error summary did not aggregate member diagnostics"
    assert root.GetProperty("summary").GetProperty("warnings").GetInt32() == memberWarnings, "workspace warning summary did not aggregate member diagnostics"
    assert root.GetProperty("summary").GetProperty("info").GetInt32() == memberInfo, "workspace info summary did not aggregate member diagnostics"
    assert root.GetProperty("summary").GetProperty("projectFailures").GetInt32() > 0

    counters := stats.GetProperty("counters")
    filesParsed := counters.GetProperty("filesParsed").GetInt64()
    referenceImages := counters.GetProperty("referenceAssembliesLoaded").GetInt64()
    assert filesParsed >= checkedFiles, "filesParsed was " + filesParsed.ToString() + " for " + checkedFiles.ToString() + " checked source files"
    assert filesParsed <= CliRootCheckExpectedFilesParsed(), "filesParsed increased above the measured 5,258 workspace parse events: " + filesParsed.ToString()
    assert referenceImages <= CliRootCheckMaximumReferenceImages(), "referenceAssembliesLoaded increased above the measured 18,184 workspace images: " + referenceImages.ToString()

    timingUnjudged := CliRootCheckRefusesTimingJudgement(load)
    timingVerdict := "timing judged"
    if timingUnjudged {
        timingVerdict = "timing unjudged: load " + CliRootCheckLoadText(load) + " on " + load.Cores.ToString() + " cores is unknown or at/above the " + CliRootCheckLoadThresholdThousandths(load.Cores).ToString() + " thousandths threshold"
    } else if wallMs > CliRootCheckQuietWallBudgetMs() {
        timingVerdict = "timing failed: " + wallMs.ToString() + " ms over the " + CliRootCheckQuietWallBudgetMs().ToString() + " ms budget at load " + CliRootCheckLoadText(load)
    }
    timingRecord := "repository-root check: projects=" + expectedRoots.Count.ToString() + " checkedFiles=" + checkedFiles.ToString() + " filesParsed=" + filesParsed.ToString() + " referenceAssembliesLoaded=" + referenceImages.ToString() + " wallMs=" + wallMs.ToString() + " budgetMs=" + CliRootCheckQuietWallBudgetMs().ToString() + " load=" + CliRootCheckLoadText(load) + " cores=" + load.Cores.ToString() + "; " + timingVerdict
    _ = CliRootCheckWriteGateRecord(repositoryRoot, timingRecord)
    assert timingUnjudged || wallMs <= CliRootCheckQuietWallBudgetMs(), timingRecord

    document.Dispose()
    statsDocument.Dispose()
}

test "workspace text check groups a member's diagnostics under its project" {
    directory := NewTempDirectory("nlc-check-workspace-text")
    try {
        WriteProjectYml(directory, "name: CheckWorkspaceRoot\nversion: 0.1.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        File.WriteAllText(Path.Combine(directory, "Root.nl"), "class Root {}\n")
        memberDirectory := Path.Combine(directory, "member")
        Directory.CreateDirectory(memberDirectory)
        WriteProjectYml(memberDirectory, "name: CheckWorkspaceMember\nversion: 0.1.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        File.WriteAllText(Path.Combine(memberDirectory, "Member.nl"), "import System.Text\n\nclass Member {}\n")

        run := Nlc("check --text --project \"" + directory + "\"")

        assert run.ExitCode == 1, run.Stdout + run.Stderr
        assert run.Stdout.Trim().Length == 0, run.Stdout
        assert run.Stderr.Contains("Project: " + NormalizedFullPath(directory)) || run.Stderr.Contains("Project: /private" + NormalizedFullPath(directory)), run.Stderr
        assert run.Stderr.Contains("Project: " + NormalizedFullPath(memberDirectory)) || run.Stderr.Contains("Project: /private" + NormalizedFullPath(memberDirectory)), run.Stderr
        assert run.Stderr.Contains("NL010"), run.Stderr
        assert run.Stderr.Contains("Member.nl"), run.Stderr
    } finally {
        Directory.Delete(directory, true)
    }
}

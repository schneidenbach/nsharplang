namespace NSharpLang.CliCommandContracts.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Text.Json

// Parse work includes project-reference builds as well as each member's own files. Across five
// worktree runs, three test-all-style copy runs, and the reported gate observation, the highest
// observed ratio is 5,352 / 1,991, so the rounded-up ratchet is three parse events per checked file.
// The reference-image budget below measures a no-dependency member's shared reference surface, then
// adds the resolved reference assets of every actual workspace member. This keeps built project and
// NuGet outputs in the budget without treating them as a repository-wide per-member constant.
func CliRootCheckMaxParseEventsPerCheckedFile(): long => 3

// Quiet-machine timing measurement: about 64 s. Keep the documented 2x budget (128 s) independent
// from the 15-minute hard timeout: that one only catches a stuck CLI and never judges performance.
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

class CliRootCheckDiscoveredMember {
    Root: string
    ExcludePatterns: List<string>
    CheckedFiles: int

    constructor(root: string, excludePatterns: List<string>) {
        Root = root
        ExcludePatterns = excludePatterns
        CheckedFiles = 0
    }
}

func CliRootCheckWorkspaceFailureText(projects: JsonElement): string {
    failures := ""
    for member in projects.EnumerateArray() {
        if member.GetProperty("ok").GetBoolean() {
            continue
        }

        if failures.Length > 0 {
            failures = failures + "\n"
        }
        failures = failures + "- " + TextOf(member.GetProperty("projectRoot"))

        errorMessage := new JsonElement()
        hasError := member.TryGetProperty("error", out errorMessage)
        if hasError {
            failures = failures + " error: " + TextOf(errorMessage)
        }

        diagnosticCount := 0
        for diagnostic in member.GetProperty("results").EnumerateArray() {
            if diagnosticCount >= 3 {
                break
            }
            location := TextOf(diagnostic.GetProperty("file")) + ":" +
                diagnostic.GetProperty("line").GetInt32().ToString() + ":" +
                diagnostic.GetProperty("column").GetInt32().ToString()
            failures = failures + "\n  " + TextOf(diagnostic.GetProperty("code")) + " " +
                TextOf(diagnostic.GetProperty("severity")) + " " + location + ": " +
                TextOf(diagnostic.GetProperty("message"))
            diagnosticCount = diagnosticCount + 1
        }

        if diagnosticCount == 0 && !hasError {
            failures = failures + " (no diagnostic or project error was returned)"
        }
    }

    if failures.Length == 0 {
        return "none"
    }
    return failures
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

func CliRootCheckReadExcludePatterns(projectRoot: string): List<string> {
    patterns := new List<string>()
    projectYml := Path.Combine(projectRoot, "project.yml")
    if !File.Exists(projectYml) {
        return patterns
    }

    inExcludeBlock := false
    for line in File.ReadAllLines(projectYml) {
        trimmed := line.Trim()
        if trimmed.Length == 0 || trimmed.StartsWith("#") {
            continue
        }

        isIndented := line[0] == ' ' || line[0] == '\t'
        if !isIndented {
            inExcludeBlock = String.Equals(trimmed, "exclude:", StringComparison.Ordinal)
            continue
        }

        if inExcludeBlock && trimmed.StartsWith("-") {
            pattern := trimmed.Substring(1).Trim()
            if pattern.Length >= 2 {
                first := pattern[0]
                last := pattern[pattern.Length - 1]
                if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
                    pattern = pattern.Substring(1, pattern.Length - 2)
                }
            }
            if pattern.Length > 0 {
                patterns.Add(pattern)
            }
        }
    }
    return patterns
}

func CliRootCheckNormalizeSlash(value: char): char {
    if value == '\\' {
        return '/'
    }
    return value
}

func CliRootCheckGlobMatches(path: string, pattern: string): bool {
    return CliRootCheckGlobMatchFrom(path, 0, pattern, 0)
}

func CliRootCheckGlobMatchFrom(path: string, pathIndex: int, pattern: string, patternIndex: int): bool {
    pi := pathIndex
    qi := patternIndex
    while qi < pattern.Length {
        pc := CliRootCheckNormalizeSlash(pattern[qi])
        if pc == '*' {
            isDouble := qi + 1 < pattern.Length && CliRootCheckNormalizeSlash(pattern[qi + 1]) == '*'
            if isDouble {
                afterStars := qi + 2
                hasSlash := afterStars < pattern.Length && CliRootCheckNormalizeSlash(pattern[afterStars]) == '/'
                if hasSlash {
                    nextPattern := afterStars + 1
                    scan := pi
                    while scan < path.Length {
                        if path[scan] == '\n' {
                            return false
                        }
                        crossedSlash := CliRootCheckNormalizeSlash(path[scan]) == '/'
                        scan = scan + 1
                        if crossedSlash && CliRootCheckGlobMatchFrom(path, scan, pattern, nextPattern) {
                            return true
                        }
                    }
                    return false
                }

                limit := path.Length
                k := limit
                while k >= pi {
                    if CliRootCheckGlobMatchFrom(path, k, pattern, afterStars) {
                        return true
                    }
                    k = k - 1
                }
                return false
            }

            limit := pi
            while limit < path.Length && CliRootCheckNormalizeSlash(path[limit]) != '/' && path[limit] != '\n' {
                limit = limit + 1
            }
            k := limit
            nextPattern := qi + 1
            while k >= pi {
                if CliRootCheckGlobMatchFrom(path, k, pattern, nextPattern) {
                    return true
                }
                k = k - 1
            }
            return false
        }

        if pc == '?' {
            if pi >= path.Length || path[pi] == '\n' {
                return false
            }
            pi = pi + 1
            qi = qi + 1
            continue
        }

        if pi >= path.Length || CliRootCheckNormalizeSlash(path[pi]) != pc {
            return false
        }
        pi = pi + 1
        qi = qi + 1
    }

    return pi == path.Length || (pi == path.Length - 1 && path[pi] == '\n')
}

func CliRootCheckIsExcludedSource(path: string, patterns: List<string>): bool {
    for pattern in patterns {
        if CliRootCheckGlobMatches(path, pattern) {
            return true
        }
    }
    return false
}

func CliRootCheckIsWithinProjectRoot(path: string, projectRoot: string): bool {
    boundary := projectRoot
    if !boundary.EndsWith(Path.DirectorySeparatorChar.ToString()) {
        boundary = boundary + Path.DirectorySeparatorChar.ToString()
    }
    return path.StartsWith(boundary, StringComparison.OrdinalIgnoreCase)
}

func CliRootCheckFindSourceOwner(members: List<CliRootCheckDiscoveredMember>, sourceFile: string): int {
    fullPath := NormalizedFullPath(sourceFile)
    ownerIndex := 0
    ownerLength := members[0].Root.Length
    index := 1
    while index < members.Count {
        root := members[index].Root
        if root.Length > ownerLength && CliRootCheckIsWithinProjectRoot(fullPath, root) {
            ownerIndex = index
            ownerLength = root.Length
        }
        index = index + 1
    }
    return ownerIndex
}

func CliRootCheckDiscoverSourceFiles(directory: string, members: List<CliRootCheckDiscoveredMember>): void {
    directoryFiles := new string[](0)
    try {
        directoryFiles = Directory.GetFiles(directory, "*.nl", SearchOption.TopDirectoryOnly)
    } catch {
        return
    }

    for sourceFile in directoryFiles {
        ownerIndex := CliRootCheckFindSourceOwner(members, sourceFile)
        member := members[ownerIndex]
        relativePath := Path.GetRelativePath(member.Root, sourceFile)
        if !CliRootCheckIsExcludedSource(relativePath, member.ExcludePatterns) {
            member.CheckedFiles = member.CheckedFiles + 1
        }
    }

    subdirectories := new string[](0)
    try {
        subdirectories = Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)
    } catch {
        return
    }

    for subdirectory in subdirectories {
        name := Path.GetFileName(subdirectory) ?? ""
        if !CliRootCheckShouldSkipDirectory(name) && !File.Exists(Path.Combine(subdirectory, ".git")) && !Directory.Exists(Path.Combine(subdirectory, ".git")) {
            CliRootCheckDiscoverSourceFiles(subdirectory, members)
        }
    }
}

func CliRootCheckExpectedSourceMembers(repositoryRoot: string, roots: List<string>): List<CliRootCheckDiscoveredMember> {
    members := new List<CliRootCheckDiscoveredMember>()
    for root in roots {
        members.Add(new CliRootCheckDiscoveredMember(root, CliRootCheckReadExcludePatterns(root)))
    }
    CliRootCheckDiscoverSourceFiles(repositoryRoot, members)
    return members
}

func CliRootCheckFindProject(roots: List<string>, candidate: string): bool {
    return CliRootCheckFindProjectIndex(roots, candidate) >= 0
}

func CliRootCheckFindProjectIndex(roots: List<string>, candidate: string): int {
    index := 0
    while index < roots.Count {
        if EquivalentProcessPath(roots[index], candidate) {
            return index
        }
        index = index + 1
    }
    return -1
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

test "nlc check checks each repository project once, keeps Core clean, and pins workspace work while load judges wall time" {
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
    expectedSourceMembers := CliRootCheckExpectedSourceMembers(repositoryRoot, expectedRoots)
    referenceBudget := CliRootCheckReferenceImageBudget(expectedRoots)
    projects := root.GetProperty("projects")
    assert projects.GetArrayLength() == expectedRoots.Count, "workspace returned " + projects.GetArrayLength().ToString() + " member results for " + expectedRoots.Count.ToString() + " discovered project roots"

    checkedFiles := 0
    discoveredFiles := 0
    memberErrors := 0
    memberWarnings := 0
    memberInfo := 0
    observedRoots := new List<string>()
    expectedCoreRoot := NormalizedFullPath(Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Compiler.Core"))
    foundCoreProject := false
    for member in projects.EnumerateArray() {
        memberRoot := TextOf(member.GetProperty("projectRoot"))
        expectedMemberIndex := CliRootCheckFindProjectIndex(expectedRoots, memberRoot)
        assert expectedMemberIndex >= 0, "workspace returned an undiscovered project: " + memberRoot
        assert !CliRootCheckFindProject(observedRoots, memberRoot), "workspace checked a member more than once: " + memberRoot
        observedRoots.Add(memberRoot)

        memberFiles := member.GetProperty("checkedFiles").GetInt32()
        discoveredMemberFiles := expectedSourceMembers[expectedMemberIndex].CheckedFiles
        assert memberFiles == discoveredMemberFiles, "workspace checked " + memberFiles.ToString() + " files for " + memberRoot + ", filesystem discovery found " + discoveredMemberFiles.ToString()
        checkedFiles = checkedFiles + memberFiles
        discoveredFiles = discoveredFiles + discoveredMemberFiles
        summary := member.GetProperty("summary")
        memberErrors = memberErrors + summary.GetProperty("errors").GetInt32()
        memberWarnings = memberWarnings + summary.GetProperty("warnings").GetInt32()
        memberInfo = memberInfo + summary.GetProperty("info").GetInt32()
        assert member.GetProperty("results").GetArrayLength() == summary.GetProperty("errors").GetInt32() + summary.GetProperty("warnings").GetInt32() + summary.GetProperty("info").GetInt32(), "member diagnostic rows disagree with its summary: " + memberRoot

        if EquivalentProcessPath(memberRoot, expectedCoreRoot) {
            foundCoreProject = true
            assert member.GetProperty("results").GetArrayLength() == 0, stdout
            assert summary.GetProperty("errors").GetInt32() == 0, stdout
        }
    }

    assert observedRoots.Count == expectedRoots.Count, "not every discovered project root had exactly one result"
    assert foundCoreProject, "the workspace omitted Compiler.Core's result"
    assert checkedFiles == discoveredFiles, "workspace checkedFiles does not equal the independently discovered source-file census"
    assert root.GetProperty("checkedFiles").GetInt32() == checkedFiles, "workspace checkedFiles does not equal the sum of its member rows"
    assert root.GetProperty("summary").GetProperty("errors").GetInt32() == memberErrors, "workspace error summary did not aggregate member diagnostics"
    assert root.GetProperty("summary").GetProperty("warnings").GetInt32() == memberWarnings, "workspace warning summary did not aggregate member diagnostics"
    assert root.GetProperty("summary").GetProperty("info").GetInt32() == memberInfo, "workspace info summary did not aggregate member diagnostics"
    assert root.GetProperty("summary").GetProperty("projectFailures").GetInt32() == 0, "the workspace reported project failures despite returning a result for every discovered project. Failing projects and first diagnostics/errors:\n" + CliRootCheckWorkspaceFailureText(projects)

    counters := stats.GetProperty("counters")
    filesParsed := counters.GetProperty("filesParsed").GetInt64()
    referenceImages := counters.GetProperty("referenceAssembliesLoaded").GetInt64()
    assert filesParsed >= checkedFiles, "filesParsed was " + filesParsed.ToString() + " for " + checkedFiles.ToString() + " checked source files"
    maxParseEvents := CliRootCheckMaxParseEventsPerCheckedFile() * (long)checkedFiles
    assert filesParsed <= maxParseEvents, "filesParsed was " + filesParsed.ToString() + "; the ratio ratchet allows at most " + CliRootCheckMaxParseEventsPerCheckedFile().ToString() + " events per discovered checked file (" + maxParseEvents.ToString() + ")"
    maxReferenceImages := referenceBudget.Maximum
    assert referenceImages <= maxReferenceImages, "referenceAssembliesLoaded was " + referenceImages.ToString() + "; the dependency-derived budget allows " + referenceBudget.EmptyProjectReferenceImages.ToString() + " shared opens per member plus up to six opens for each of " + referenceBudget.ConfiguredReferenceImages.ToString() + " resolved reference images (" + maxReferenceImages.ToString() + ")"

    timingUnjudged := CliRootCheckRefusesTimingJudgement(load)
    timingVerdict := "timing judged"
    if timingUnjudged {
        timingVerdict = "timing unjudged: load " + CliRootCheckLoadText(load) + " on " + load.Cores.ToString() + " cores is unknown or at/above the " + CliRootCheckLoadThresholdThousandths(load.Cores).ToString() + " thousandths threshold"
    } else if wallMs > CliRootCheckQuietWallBudgetMs() {
        timingVerdict = "timing failed: " + wallMs.ToString() + " ms over the " + CliRootCheckQuietWallBudgetMs().ToString() + " ms budget at load " + CliRootCheckLoadText(load)
    }
    timingRecord := "repository-root check: projects=" + expectedRoots.Count.ToString() + " checkedFiles=" + checkedFiles.ToString() + " filesParsed=" + filesParsed.ToString() + " maxParseEvents=" + maxParseEvents.ToString() + " referenceAssembliesLoaded=" + referenceImages.ToString() + " sharedReferenceImagesPerMember=" + referenceBudget.EmptyProjectReferenceImages.ToString() + " configuredReferenceImages=" + referenceBudget.ConfiguredReferenceImages.ToString() + " maxReferenceImages=" + maxReferenceImages.ToString() + " wallMs=" + wallMs.ToString() + " budgetMs=" + CliRootCheckQuietWallBudgetMs().ToString() + " load=" + CliRootCheckLoadText(load) + " cores=" + load.Cores.ToString() + "; " + timingVerdict
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

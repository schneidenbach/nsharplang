namespace NSharpLang.GateScriptContracts.Tests

import System
import System.Collections.Generic
import System.IO
import System.Text.RegularExpressions

// ─── THE PER-STEP INPUT-SET GUARDS ────────────────────────────────────────────────────────────
//
// Replaces `tests/GateStepInputSetGuardTests.cs`.
//
// The product gate (`tests/scripts/test-all.sh`) may skip a step inside a plain fresh development
// run only when the step's ENTIRE declared input set is byte-identical to inputs that previously
// passed it. That design is sound ONLY while every declared input set is a superset of what the
// step actually reads. These guards also ensure commit verification disables per-step skipping;
// see `memory/testing.md`, "The Product Gate Skips Steps With Unchanged Inputs".
//
// Every row here reads `tests/scripts/test-all-core.sh` and `tests/scripts/test-all.sh` as TEXT.
// None of them runs the gate. The one end-to-end row lifts the gate's own embedded python hasher
// out of its heredoc and runs THAT against a synthetic three-file tree in a temporary directory.

// Repo files unit tests read and assert on that the source scan below cannot discover (non-repo-root
// anchors), plus the files whose omission originally made a docs-only --commit skip failing unit
// tests.
func KnownRepoFilesReadByUnitTests(): List<string> {
    files := new List<string>()
    // tests/CliCommandTests.cs: CliCommandRegistry_StaysInSyncWithHelpCompletionsAndDocs
    files.Add("website/docs/cli-reference.md")
    // tests/native/query-integration: golden compare anchored at the repository root
    files.Add("docs/examples/diagnostic-clusters.sample.json")
    return files
}

test "the UNIT input set covers documentation wholesale and every repo file unit tests read through a non-root anchor" {
    sets := ParseInputSets(ReadGateScript("test-all-core.sh"))
    assert sets.ContainsKey("UNIT"), "Could not find the UNIT entry in the SETS literal of tests/scripts/test-all-core.sh."
    unitPrefixes := sets["UNIT"]

    // Wholesale documentation coverage, not per-file allowlists: any future parity test against
    // any docs page must stay covered.
    assert unitPrefixes.Contains("docs/")
    assert unitPrefixes.Contains("website/docs/")

    known := KnownRepoFilesReadByUnitTests()
    uncovered := new List<string>()
    index := 0
    while index < known.Count {
        if !IsCovered(known[index], unitPrefixes) {
            uncovered.Add(known[index])
        }

        index = index + 1
    }

    assert uncovered.Count == 0, "These repo files are read and asserted on by unit tests but are NOT in the UNIT input set of the validated per-step cache (tests/scripts/test-all-core.sh). A change to them would skip unit tests in a cached development gate run and hide a red test. Add a covering prefix to SETS[\"UNIT\"] — see memory/testing.md, \"The Product Gate Skips Steps With Unchanged Inputs\".\n" + JoinLines(uncovered)
}

// Self-discovery: every consecutive-literal path that a test source joins onto the repo root must
// be covered by a UNIT prefix. New tests that read repo files through the repo-root convention are
// guarded automatically; widen the UNIT entry in SETS when this fires.
//
// Matches `Path.Combine` calls anchored at the repo root by convention (`FindRepoRoot()` or a
// *repoRoot* identifier) and captures the consecutive leading string-literal segments. Temp-dir
// anchors (tempRoot, projectRoot, bare root) are deliberately excluded — they routinely reuse
// repo-like names (project.yml) outside the repository.
func RepoRootCombinePattern(): string {
    return "Path\\.Combine\\(\\s*(?:FindRepoRoot\\(\\)|\\w*[Rr]epoRoot\\w*)\\s*(?:,\\s*\"(?<seg>[^\"]+)\")+"
}

func HasExcludedSegment(relativePath: string): bool {
    segments := relativePath.Replace("\\", "/").Split('/')
    index := 0
    while index < segments.Length {
        segment := segments[index]
        if segment == "bin" || segment == "obj" || segment == "TestResults" {
            return true
        }

        index = index + 1
    }

    return false
}

func CollectRepoRootCombineOffenders(testsDirectory: string, repoRoot: string, pattern: string, unitPrefixes: List<string>, offenders: List<string>) {
    for sourceFile in Directory.EnumerateFiles(testsDirectory, pattern, SearchOption.AllDirectories) {
        relativePath := Path.GetRelativePath(repoRoot, sourceFile)
        if HasExcludedSegment(relativePath) {
            continue
        }

        matches := Regex.Matches(File.ReadAllText(sourceFile), RepoRootCombinePattern())
        matchIndex := 0
        while matchIndex < matches.Count {
            captures := matches[matchIndex].Groups["seg"].Captures
            segments := new List<string>()
            captureIndex := 0
            while captureIndex < captures.Count {
                segments.Add(captures[captureIndex].Value)
                captureIndex = captureIndex + 1
            }

            joined := string.Join("/", segments)
            if !IsCovered(joined, unitPrefixes) {
                offender := relativePath + ": Path.Combine(<repo root>, \"" + joined + "\")"
                if !offenders.Contains(offender) {
                    offenders.Add(offender)
                }
            }

            matchIndex = matchIndex + 1
        }
    }
}

test "every repo-root path a test source joins is covered by a UNIT input-set prefix" {
    repoRoot := RepositoryRoot()
    sets := ParseInputSets(ReadGateScript("test-all-core.sh"))
    unitPrefixes := sets["UNIT"]
    offenders := new List<string>()
    testsDirectory := Path.Combine(repoRoot, "tests")

    // Both test dialects are scanned. The deleted C# only walked `*.cs`; walking `*.nl` beside it
    // keeps the guard alive as test sources migrate to N#, and is a strict widening — no existing
    // `.nl` under tests/ spells a repo-root `Path.Combine` at all.
    CollectRepoRootCombineOffenders(testsDirectory, repoRoot, "*.cs", unitPrefixes, offenders)
    CollectRepoRootCombineOffenders(testsDirectory, repoRoot, "*.nl", unitPrefixes, offenders)

    assert offenders.Count == 0, "Test sources join these paths onto the repo root, but no UNIT input-set prefix in tests/scripts/test-all-core.sh covers them, so changing those files would skip unit tests in a cached development gate run. Add a covering prefix to SETS[\"UNIT\"] — see memory/testing.md, \"The Product Gate Skips Steps With Unchanged Inputs\".\n" + JoinLines(offenders)
}

// The step keys must agree with the whole-gate signature on environment: a marker stored under one
// behavior-changing environment (columnar backend on, golden regeneration, ...) must never satisfy
// a run under another.
test "the per-step cache salt covers the ilverify tool version and the same environment the whole-gate signature covers" {
    coreScript := ReadGateScript("test-all-core.sh")
    gateScript := ReadGateScript("test-all.sh")

    saltMatch := RequireMatch(coreScript, "salt = json\\.dumps\\(\\{(?<body>.*?)\\}, sort_keys=True\\)", "Could not find the per-step salt construction in tests/scripts/test-all-core.sh.")
    assert saltMatch.Groups["body"].Value.Contains("\"ilverify\"")
    assert saltMatch.Groups["body"].Value.Contains("\"environment\"")

    coreEnvNames := SaltedEnvNames(coreScript)
    gateEnvMatch := RequireMatch(gateScript, "env_names\\s*=\\s*\\[(?<body>[^\\]]*)\\]", "Could not find the env_names list in tests/scripts/test-all.sh.")
    gateEnvNames := QuotedStrings(gateEnvMatch.Groups["body"].Value)

    assert coreEnvNames.Contains("NSHARP_EXPERIMENTAL_SOA")
    assert gateEnvNames.Contains("NSHARP_EXPERIMENTAL_SOA")

    coreSet := new HashSet<string>()
    coreIndex := 0
    while coreIndex < coreEnvNames.Count {
        coreSet.Add(coreEnvNames[coreIndex])
        coreIndex = coreIndex + 1
    }

    coreSorted := new List<string>()
    coreSorted.AddRange(coreEnvNames)
    coreSorted.Sort(StringComparer.Ordinal)
    gateSorted := new List<string>()
    gateSorted.AddRange(gateEnvNames)
    gateSorted.Sort(StringComparer.Ordinal)

    assert coreSet.SetEquals(gateEnvNames), "The per-step salt ENV_NAMES (tests/scripts/test-all-core.sh) and the whole-gate signature env_names (tests/scripts/test-all.sh) must list the same environment variables, or step markers and gate manifests disagree on what \"same environment\" means.\ncore:  " + string.Join(", ", coreSorted) + "\ngate:  " + string.Join(", ", gateSorted)

    // Golden regeneration inside the discarded isolated copy makes golden tests self-satisfying;
    // the isolated env must always strip it.
    assert gateScript.Contains("unset NSHARP_UPDATE_DIAGNOSTIC_GOLDENS")
}

test "commit verification turns the per-step cache off and forces a fresh run" {
    gateScript := ReadGateScript("test-all.sh")
    commitCase := RequireMatch(gateScript, "--commit\\|--pre-commit\\)(?<body>.*?);;", "Could not find the --commit case in tests/scripts/test-all.sh.")

    assert commitCase.Groups["body"].Value.Contains("FORCE_RUN=1")
    assert commitCase.Groups["body"].Value.Contains("STEP_CACHE_OFF=1")
}

// The throughput gate is a measured stage: it must run immediately after compiler build and the
// formatting contract, while self-host, native, and VS Code work has not yet preconditioned the
// host. These assertions guard the stage order and its single runner invocation without running
// the gate.
test "the systems throughput stage runs once after compiler build/format and before prolonged phases" {
    coreScript := ReadGateScript("test-all-core.sh")

    throughputSections := Regex.Matches(coreScript, "section\\s+\"Step 2c: Systems Throughput Gate\"")
    runnerInvocations := Regex.Matches(coreScript, "NSharpLang\\.NativeComparisonRunner\\.dll\\s+gate\\s+--cli")
    assert throughputSections.Count == 1, "The Systems Throughput Gate must have exactly one product-gate stage."
    assert runnerInvocations.Count == 1, "The Systems Throughput Gate must invoke the throughput runner exactly once."

    compilerBuildIndex := coreScript.IndexOf("dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.Cli/Cli.csproj")
    formatIndex := coreScript.IndexOf("dotnet \"$CLI_DLL\" format --project examples --check")
    runnerIndex := coreScript.IndexOf("NSharpLang.NativeComparisonRunner.dll gate --cli")
    selfHostIndex := coreScript.IndexOf("dotnet \"$CLI_DLL\" check --use-built-references --project \"$SELF_HOST_PROJECT\"")
    nativeTestIndex := coreScript.IndexOf("dotnet restore $DOTNET_STABLE_FLAGS \"$BOOTSTRAP_TEST_PROJECT\"")
    vscodeIndex := coreScript.IndexOf("tests/scripts/test-vscode-integration.sh")

    assert compilerBuildIndex >= 0, "Could not find the compiler build invocation in the product gate."
    assert formatIndex >= 0, "Could not find the formatting contract in the product gate."
    assert runnerIndex >= 0, "Could not find the throughput runner invocation in the product gate."
    assert selfHostIndex >= 0, "Could not find the self-host front-door invocation in the product gate."
    assert nativeTestIndex >= 0, "Could not find the native N# test invocation in the product gate."
    assert vscodeIndex >= 0, "Could not find the VS Code integration-test invocation in the product gate."

    assert compilerBuildIndex < formatIndex, "The compiler build must run before the formatting contract."
    assert formatIndex < runnerIndex, "The Systems Throughput Gate must run after compiler build and formatting prerequisites."
    assert runnerIndex < selfHostIndex, "The Systems Throughput Gate must run before the self-host front-door phase."
    assert runnerIndex < nativeTestIndex, "The Systems Throughput Gate must run before the native N# test phase."
    assert runnerIndex < vscodeIndex, "The Systems Throughput Gate must run before the VS Code integration-test phase."
}

// ─── THE END-TO-END HASH ROW ──────────────────────────────────────────────────────────────────

func WriteFixtureFile(root: string, relativePath: string, content: string) {
    path := Path.Combine(root, relativePath.Replace("/", Path.DirectorySeparatorChar.ToString()))
    Directory.CreateDirectory(Path.GetDirectoryName(path) ?? root)
    File.WriteAllText(path, content)
}

// Run the gate's OWN embedded hasher over `root` and read back its `NAME=hash` lines.
//
// The salted environment is pinned OFF so ambient session variables (a local SOA experiment, a
// gate exporting VSCODE_TESTS) cannot leak into the baseline expectations.
func RunStepHash(pythonPath: string, root: string): Dictionary<string, string> {
    launch := new ProcessLaunch("python3", RepositoryRoot(), 180000)
    launch.Arguments.Add(pythonPath)
    launch.Arguments.Add(root)

    saltedNames := SaltedEnvNames(ReadGateScript("test-all-core.sh"))
    saltedIndex := 0
    while saltedIndex < saltedNames.Count {
        launch.ClearedEnvironmentNames.Add(saltedNames[saltedIndex])
        saltedIndex = saltedIndex + 1
    }

    run := Run(launch)
    if run.ExitCode != 0 {
        throw new InvalidOperationException("step-hash python exited " + run.ExitCode.ToString() + ": " + run.Stderr)
    }

    hashes := new Dictionary<string, string>()
    lines := run.Stdout.Split('\n')
    index := 0
    while index < lines.Length {
        line := lines[index].Trim()
        separator := line.IndexOf("=")
        if line.Length > 0 && separator > 0 {
            hashes[line.Substring(0, separator)] = line.Substring(separator + 1)
        }

        index = index + 1
    }

    return hashes
}

func SameHashes(left: Dictionary<string, string>, right: Dictionary<string, string>): bool {
    if left.Count != right.Count {
        return false
    }

    for key in left.Keys {
        if !right.ContainsKey(key) {
            return false
        }

        if right[key] != left[key] {
            return false
        }
    }

    return true
}

// End-to-end behavior of the embedded hash step: identical inputs must produce identical keys, and
// a docs change must move the UNIT key and ONLY the keys whose sets cover docs.
test "the embedded step hasher is stable for identical inputs and moves only the UNIT key when website docs change" {
    python := ExtractStepHashPython(ReadGateScript("test-all-core.sh"))
    workRoot := NewTempDirectory("nsharp-step-hash-guard")
    try {
        pythonPath := Path.Combine(workRoot, "step-hash.py")
        File.WriteAllText(pythonPath, python)

        fixtureRoot := Path.Combine(workRoot, "repo")
        WriteFixtureFile(fixtureRoot, "src/Compiler.cs", "class Compiler { }")
        WriteFixtureFile(fixtureRoot, "tests/SampleTests.cs", "class SampleTests { }")
        WriteFixtureFile(fixtureRoot, "website/docs/cli-reference.md", "nlc build")

        baseline := RunStepHash(pythonPath, fixtureRoot)
        rerun := RunStepHash(pythonPath, fixtureRoot)
        assert SameHashes(baseline, rerun)

        WriteFixtureFile(fixtureRoot, "website/docs/cli-reference.md", "nlc build --changed")
        afterWebsiteDocs := RunStepHash(pythonPath, fixtureRoot)
        assert baseline["UNIT"] != afterWebsiteDocs["UNIT"]
        assert afterWebsiteDocs["EXAMPLES"] == baseline["EXAMPLES"]
    } finally {
        DeleteTempDirectory(workRoot)
    }
}

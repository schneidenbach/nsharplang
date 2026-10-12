namespace NSharpLang.DaemonExec.Tests

import System
import System.Collections.Generic
import System.IO
import System.Security.Cryptography
import System.Text

// A forced-fresh control keeps every environment setting of the cached invocation and disables
// only incremental shortcuts. This makes a miss test compare like-for-like compiler inputs.
func CheckStampProofFreshEnvironment(environment: Dictionary<string, string?>): Dictionary<string, string?> {
    fresh := new Dictionary<string, string?>()
    for entry in environment {
        fresh[entry.Key] = entry.Value
    }
    fresh["NSHARP_INCREMENTAL"] = "0"
    return fresh
}

func CheckStampProofWithStats(args: string[], statsPath: string): string[] {
    allArgs := new List<string>(args)
    allArgs.Add("--stats=" + statsPath)
    return allArgs.ToArray()
}

func CheckStampProofAssertMiss(project: string, args: string[], environment: Dictionary<string, string?>, label: string) {
    fresh := CheckStampRun(project, args, CheckStampProofFreshEnvironment(environment))
    statsPath := CheckStampStatsPath()
    actual := CheckStampRun(project, CheckStampProofWithStats(args, statsPath), environment)
    CheckStampAssertSame(fresh, actual, label)
    assert CheckStampParsedFiles(statsPath) > 0, label + ": changed option or environment reused a saved result"

    replayStatsPath := CheckStampStatsPath()
    replay := CheckStampRun(project, CheckStampProofWithStats(args, replayStatsPath), environment)
    CheckStampAssertSame(actual, replay, label + " no-op replay")
    assert CheckStampParsedFiles(replayStatsPath) == 0, label + ": stable option set did not replay"
}

func CheckStampProofAssertBypass(project: string, args: string[], environment: Dictionary<string, string?>, label: string) {
    fresh := CheckStampRun(project, args, CheckStampProofFreshEnvironment(environment))
    statsPath := CheckStampStatsPath()
    actual := CheckStampRun(project, CheckStampProofWithStats(args, statsPath), environment)
    CheckStampAssertSame(fresh, actual, label)
    assert CheckStampParsedFiles(statsPath) > 0, label + ": the documented cache bypass reused a result"
}

func CheckStampProofSystemsProject(): string {
    project := NewWorkspace()
    File.WriteAllText(
        Path.Combine(project, "project.yml"),
        "name: CheckStampSystems\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    unknownExternalCalls: warn\n"
    )
    WriteSource(project, "Hot.nl", "[hot]\nfunc Run(): int {\n    return External.Fast()\n}\n")
    return project
}

func CheckStampProofAppSource(bodyVariant: bool, signatureVariant: bool): string {
    local := "func Local(): int {\n    return 1000 + 2\n}"
    if signatureVariant {
        body := "value + 1000"
        if bodyVariant {
            body = "value + 1001"
        }
        local = "func Local(value: int): int {\n    return " + body + "\n}"
    } else if bodyVariant {
        local = "func Local(): int {\n    return 1000 + 3\n}"
    }

    return "namespace CheckStampApp\n\nimport CheckStampReference\n\nfunc Use(): int {\n    return Value()\n}\n\n" + local + "\n"
}

func CheckStampProofAddExtra(app: string, extras: List<string>, suffix: string) {
    name := "Extra" + suffix + ".nl"
    path := Path.Combine(app, name)
    WriteSource(app, name, "namespace CheckStampApp\n\nfunc Extra" + suffix + "(): int => 7\n")
    extras.Add(path)
}

// Keep the checksum valid while changing the compiler identity portion of the stamp key. This
// exercises the same miss as running the next compiler build against a previous compiler's state.
func CheckStampProofChangeCompilerIdentity(stampPath: string): void {
    bytes := File.ReadAllBytes(stampPath)
    payloadLength := bytes.Length - 32
    assert payloadLength > 0, "the check stamp must contain a payload"
    input := new MemoryStream(bytes, 0, payloadLength)
    reader := new BinaryReader(input, Encoding.UTF8)
    magic := reader.ReadString()
    version := reader.ReadInt32()
    key := reader.ReadString()
    analysisReuseKey := reader.ReadString()
    tailStart := (int)input.Position
    tail := new byte[payloadLength - tailStart]
    Array.Copy(bytes, tailStart, tail, 0, tail.Length)
    reader.Dispose()

    payloadStream := new MemoryStream()
    writer := new BinaryWriter(payloadStream, Encoding.UTF8)
    writer.Write(magic)
    writer.Write(version)
    writer.Write(key + "-simulated-compiler-identity-change")
    writer.Write(analysisReuseKey + "-simulated-compiler-identity-change")
    writer.Write(tail)
    writer.Flush()
    payload := payloadStream.ToArray()
    writer.Dispose()

    algorithm := SHA256.Create()
    checksum: byte[] = null
    try {
        checksum = algorithm.ComputeHash(payload)
    } finally {
        algorithm.Dispose()
    }

    updated := new byte[payload.Length + checksum.Length]
    Array.Copy(payload, updated, payload.Length)
    Array.Copy(checksum, 0, updated, payload.Length, checksum.Length)
    File.WriteAllBytes(stampPath, updated)
}

// Every step always follows the requested replay-or-fresh invocation with a full compile under the
// same inputs. The seed and step travel through all assertion messages to make a failure repeatable.
func CheckStampProofRandomSequence(seed: int) {
    root := NewWorkspace()
    app := Path.Combine(root, "App")
    reference := Path.Combine(root, "Reference")
    Directory.CreateDirectory(app)
    Directory.CreateDirectory(reference)
    File.WriteAllText(
        Path.Combine(app, "project.yml"),
        "name: CheckStampApp\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../Reference/project.yml\n"
    )
    File.WriteAllText(
        Path.Combine(reference, "project.yml"),
        "name: CheckStampReference\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    WriteSource(app, "Use.nl", CheckStampProofAppSource(false, false))
    WriteSource(reference, "Api.nl", "namespace CheckStampReference\n\nfunc Value(): int => 1\n")

    extras := new List<string>()
    bodyVariant := false
    signatureVariant := false
    renamed := false
    referenceVariant := false
    systemsProfile := false
    useFileName := "Use.nl"
    environment := InProcess()
    random := new Random(seed)
    kindOrder := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    shuffleIndex := kindOrder.Length - 1
    while shuffleIndex > 0 {
        swapIndex := random.Next(shuffleIndex + 1)
        temporary := kindOrder[shuffleIndex]
        kindOrder[shuffleIndex] = kindOrder[swapIndex]
        kindOrder[swapIndex] = temporary
        shuffleIndex = shuffleIndex - 1
    }
    currentArgs := new List<string>()
    optionIndex := -1

    try {
        initialReferenceBuild := NlcWith(["build", "--project", reference], reference, InProcess(), null)
        assert initialReferenceBuild.ExitCode == 0, "seed " + seed.ToString() + ": initial reference build failed: " + initialReferenceBuild.Stderr
        CheckStampRun(app, new string[](0), environment)

        step := 0
        while step < 48 {
            kind := random.Next(10)
            if step < kindOrder.Length {
                kind = kindOrder[step]
            } else if step % 8 == 0 {
                kind = 8
            }
            try {
                if kind == 0 {
                    bodyVariant = !bodyVariant
                    File.WriteAllText(Path.Combine(app, useFileName), CheckStampProofAppSource(bodyVariant, signatureVariant))
                } else if kind == 1 {
                    signatureVariant = !signatureVariant
                    File.WriteAllText(Path.Combine(app, useFileName), CheckStampProofAppSource(bodyVariant, signatureVariant))
                } else if kind == 2 {
                    CheckStampProofAddExtra(app, extras, step.ToString())
                } else if kind == 3 {
                    if extras.Count == 0 {
                        CheckStampProofAddExtra(app, extras, "delete" + step.ToString())
                    }
                    deleteIndex := random.Next(extras.Count)
                    File.Delete(extras[deleteIndex])
                    extras.RemoveAt(deleteIndex)
                } else if kind == 4 {
                    oldPath := Path.Combine(app, useFileName)
                    useFileName = renamed ? "Use.nl" : "MovedUse.nl"
                    newPath := Path.Combine(app, useFileName)
                    File.Move(oldPath, newPath)
                    renamed = !renamed
                } else if kind == 5 {
                    systemsProfile = !systemsProfile
                    projectFile := Path.Combine(app, "project.yml")
                    config := "name: CheckStampApp\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../Reference/project.yml\n"
                    if systemsProfile {
                        config = config + "language:\n  profile: systems\n  systems:\n    mode: audit\n    unknownExternalCalls: warn\n"
                    }
                    config = config + "# randomized project setting step " + step.ToString() + "\n"
                    File.WriteAllText(projectFile, config)
                } else if kind == 6 {
                    referenceVariant = !referenceVariant
                    referenceSource := "namespace CheckStampReference\n\nfunc Value(): int => " + (referenceVariant ? "2" : "1") + "\n"
                    File.WriteAllText(Path.Combine(reference, "Api.nl"), referenceSource)
                    rebuilt := NlcWith(["build", "--project", reference], reference, InProcess(), null)
                    assert rebuilt.ExitCode == 0, "reference rebuild failed: " + rebuilt.Stderr
                } else if kind == 7 {
                    appStampDirectory := Path.Combine(Path.Combine(app, "obj"), "nlc")
                    stamps := Directory.GetFiles(appStampDirectory, "*.check.stamp")
                    assert stamps.Length == 1, "expected the check stamp before corruption"
                    File.WriteAllBytes(stamps[0], [1, 2, 3])
                } else if kind == 9 {
                    appStampDirectory := Path.Combine(Path.Combine(app, "obj"), "nlc")
                    stamps := Directory.GetFiles(appStampDirectory, "*.check.stamp")
                    assert stamps.Length == 1, "expected the check stamp before compiler identity change"
                    CheckStampProofChangeCompilerIdentity(stamps[0])
                }

                if kind == 8 {
                    optionIndex = (optionIndex + 1) % 4
                    currentArgs.Clear()
                    if optionIndex == 0 {
                        currentArgs.Add("--aot")
                    } else if optionIndex == 1 {
                        currentArgs.Add("--backend")
                        currentArgs.Add("il")
                    } else if optionIndex == 2 {
                        currentArgs.Add("--use-built-references")
                    } else {
                        currentArgs.Add("--systems-report")
                    }
                }
                if random.Next(5) == 0 {
                    environment["NSHARP_COMPILER_WORKERS"] = random.Next(2) == 0 ? "1" : "3"
                }

                label := "seed " + seed.ToString() + " step " + step.ToString() + " edit " + kind.ToString()
                statsPath: string? = null
                invocationArgs := currentArgs.ToArray()
                if kind == 9 {
                    statsPath = CheckStampStatsPath()
                    invocationArgs = CheckStampProofWithStats(invocationArgs, statsPath)
                }
                replayOrFresh := CheckStampRun(app, invocationArgs, environment)
                forcedFresh := CheckStampRun(app, currentArgs.ToArray(), CheckStampProofFreshEnvironment(environment))
                CheckStampAssertSame(forcedFresh, replayOrFresh, label)
                if kind == 9 {
                    assert statsPath != null
                    assert CheckStampParsedFiles(statsPath) > 0, label + ": compiler identity change must force a full check"
                }
            } catch ex: Exception {
                throw new InvalidOperationException("randomized check differential " + seed.ToString() + " step " + step.ToString() + ": " + ex.Message)
            }
            step = step + 1
        }
    } finally {
        Directory.Delete(root, true)
    }
}

test "each accepted check option that changes output misses and then replays under that option" {
    project := CheckStampProject()
    try {
        defaultRun := CheckStampRun(project, new string[](0), InProcess())
        jsonStatsPath := CheckStampStatsPath()
        explicitJson := CheckStampRun(project, ["--json", "--stats=" + jsonStatsPath], InProcess())
        CheckStampAssertSame(defaultRun, explicitJson, "explicit JSON alias")
        assert CheckStampParsedFiles(jsonStatsPath) == 0, "--json is the default mode, so it shares the JSON cache entry"

        CheckStampProofAssertMiss(project, ["--aot"], InProcess(), "--aot")
        CheckStampProofAssertMiss(project, ["--backend", "il"], InProcess(), "--backend il")
        CheckStampProofAssertMiss(project, ["--systems-report"], InProcess(), "--systems-report")

        fullEnvironment := CheckStampProofFreshEnvironment(InProcess())
        freshText := CheckStampRun(project, ["--text"], fullEnvironment)
        textStatsPath := CheckStampStatsPath()
        text := CheckStampRun(project, ["--text", "--stats=" + textStatsPath], InProcess())
        assert text.ExitCode == freshText.ExitCode, "--text miss changed the exit code"
        assert text.Stdout == freshText.Stdout, "--text miss changed stdout"
        assert text.Stderr.StartsWith("  Checked 1 file — no errors."), "--text must report the human summary"
        assert freshText.Stderr.StartsWith("  Checked 1 file — no errors."), "forced fresh text must report the same human summary"
        assert CheckStampParsedFiles(textStatsPath) > 0, "--text output mode change must miss"
        textReplayStatsPath := CheckStampStatsPath()
        textReplay := CheckStampRun(project, ["--text", "--stats=" + textReplayStatsPath], InProcess())
        CheckStampAssertSame(text, textReplay, "text no-op replay")
        assert CheckStampParsedFiles(textReplayStatsPath) == 0
    } finally {
        Directory.Delete(project, true)
    }
}

test "use-built-references invalidates against a real built project dependency" {
    root := NewWorkspace()
    app := Path.Combine(root, "App")
    reference := Path.Combine(root, "Reference")
    Directory.CreateDirectory(app)
    Directory.CreateDirectory(reference)
    File.WriteAllText(
        Path.Combine(app, "project.yml"),
        "name: CheckStampApp\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../Reference/project.yml\n"
    )
    File.WriteAllText(
        Path.Combine(reference, "project.yml"),
        "name: CheckStampReference\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    WriteSource(app, "Use.nl", "namespace CheckStampApp\n\nimport CheckStampReference\n\nfunc Use(): int => Value()\n")
    WriteSource(reference, "Api.nl", "namespace CheckStampReference\n\nfunc Value(): int => 1\n")
    try {
        built := NlcWith(["build", "--project", reference], reference, InProcess(), null)
        assert built.ExitCode == 0, built.Stderr
        CheckStampRun(app, new string[](0), InProcess())
        CheckStampProofAssertMiss(app, ["--use-built-references"], InProcess(), "--use-built-references with a project dependency")
    } finally {
        Directory.Delete(root, true)
    }
}

test "project configuration and target framework changes miss the check result" {
    project := CheckStampProofSystemsProject()
    try {
        CheckStampRun(project, new string[](0), InProcess())

        projectFile := Path.Combine(project, "project.yml")
        original := File.ReadAllText(projectFile)
        File.WriteAllText(projectFile, original.Replace("unknownExternalCalls: warn", "unknownExternalCalls: error"))
        CheckStampProofAssertMiss(project, new string[](0), InProcess(), "language.systems.unknownExternalCalls")

        updated := File.ReadAllText(projectFile)
        File.WriteAllText(projectFile, updated.Replace("mode: strict", "mode: audit"))
        CheckStampProofAssertMiss(project, new string[](0), InProcess(), "language.systems.mode")

        updated = File.ReadAllText(projectFile)
        File.WriteAllText(projectFile, updated.Replace("profile: systems", "profile: default"))
        CheckStampProofAssertMiss(project, new string[](0), InProcess(), "language.profile")

        updated = File.ReadAllText(projectFile)
        File.WriteAllText(projectFile, updated.Replace("targetFramework: net10.0", "targetFramework: net10.0-macos"))
        CheckStampProofAssertMiss(project, new string[](0), InProcess(), "target framework")

        // This spelling is the actual lint configuration source. `nlc check` does not run strict
        // lint, but the shared build/check input closure observes the file, so enabling or disabling
        // a rule can never leave a saved answer current if the check pipeline begins consuming it.
        editorConfig := Path.Combine(project, ".editorconfig")
        File.WriteAllText(editorConfig, "root = true\n\n[*.nl]\ndotnet_diagnostic.NL001.severity = none\n")
        CheckStampProofAssertMiss(project, new string[](0), InProcess(), "editorconfig lint setting")
    } finally {
        Directory.Delete(project, true)
    }
}

test "check environment inputs either miss or deliberately disable result replay" {
    project := CheckStampProject()
    try {
        CheckStampRun(project, new string[](0), InProcess())

        soa := InProcess()
        soa["NSHARP_EXPERIMENTAL_SOA"] = "1"
        CheckStampProofAssertMiss(project, new string[](0), soa, "NSHARP_EXPERIMENTAL_SOA")

        workers := InProcess()
        workers["NSHARP_COMPILER_WORKERS"] = "2"
        CheckStampProofAssertMiss(project, new string[](0), workers, "NSHARP_COMPILER_WORKERS")

        packages := InProcess()
        packages["NUGET_PACKAGES"] = Path.Combine(Path.GetTempPath(), "nsharp-empty-packages-" + Guid.NewGuid().ToString("N"))
        CheckStampProofAssertMiss(project, new string[](0), packages, "NUGET_PACKAGES")

        // NSHARP_INCREMENTAL is the escape hatch, not an analysis input: setting it to 0 must bypass
        // both reading and writing a check result while preserving the fresh answer.
        disabled := InProcess()
        disabled["NSHARP_INCREMENTAL"] = "0"
        CheckStampProofAssertBypass(project, new string[](0), disabled, "NSHARP_INCREMENTAL=0")

        debug := InProcess()
        debug["NSHARP_DEBUG_LOG"] = "1"
        CheckStampProofAssertBypass(project, new string[](0), debug, "NSHARP_DEBUG_LOG cache bypass")

        decline := InProcess()
        decline["NSHARP_COLUMNAR_DECLINE_LOG"] = "1"
        CheckStampProofAssertBypass(project, new string[](0), decline, "NSHARP_COLUMNAR_DECLINE_LOG cache bypass")
    } finally {
        Directory.Delete(project, true)
    }
}

test "instrumentation and color settings do not change saved diagnostics" {
    project := CheckStampProject()
    try {
        mathPath := Path.Combine(project, "Math.nl")
        File.WriteAllText(mathPath, File.ReadAllText(mathPath).Replace("value * 2", "missing * 2"))
        prime := CheckStampRun(project, ["--text"], InProcess())
        assert prime.ExitCode != 0, "the color check needs a diagnostic to render"
        statsPath := CheckStampStatsPath()
        withStats := CheckStampRun(project, ["--text", "--stats=" + statsPath], InProcess())
        CheckStampAssertSame(prime, withStats, "--stats side channel")
        assert CheckStampParsedFiles(statsPath) == 0, "stats are reported separately and must remain available on a hit"

        statsOnStderr := CheckStampRun(project, ["--text", "--stats"], InProcess())
        assert statsOnStderr.ExitCode == prime.ExitCode
        assert statsOnStderr.Stdout == prime.Stdout
        assert statsOnStderr.Stderr.StartsWith(prime.Stderr), "--stats must append its own line after check's text output"
        assert statsOnStderr.Stderr.Contains("nsharp.cli-stats"), "--stats must still report its separate schema on a cache hit"

        color := InProcess()
        color["NO_COLOR"] = "1"
        color["FORCE_COLOR"] = "1"
        colorStatsPath := CheckStampStatsPath()
        withColorEnvironment := CheckStampRun(project, ["--text", "--color=always", "--stats=" + colorStatsPath], color)
        CheckStampAssertSame(prime, withColorEnvironment, "color formatting settings")
        assert CheckStampParsedFiles(colorStatsPath) == 0, "check diagnostics text is deliberately uncolored"
        assert !withColorEnvironment.Stderr.Contains("\u001b["), "check text output must not contain terminal color escapes"
    } finally {
        Directory.Delete(project, true)
    }
}

test "check help only advertises supported output and diagnostic policy options" {
    project := CheckStampProject()
    try {
        help := CheckStampRun(project, ["--help"], InProcess())
        assert help.ExitCode == 0
        assert help.Stdout.Contains("--json") && help.Stdout.Contains("--text")
        assert help.Stdout.Contains("--aot") && help.Stdout.Contains("--systems-report")
        assert !help.Stdout.Contains("--quiet")
        assert !help.Stdout.Contains("--format")
        assert !help.Stdout.Contains("--warn-as-error")
        assert !help.Stdout.Contains("--disabled-rules")
    } finally {
        Directory.Delete(project, true)
    }
}

test "systems policy settings are fingerprinted and preserve diagnostics" {
    project := CheckStampProofSystemsProject()
    try {
        CheckStampRun(project, ["--systems-report"], InProcess())
        projectFile := Path.Combine(project, "project.yml")
        File.WriteAllText(projectFile, File.ReadAllText(projectFile).Replace("mode: strict", "mode: audit"))
        CheckStampProofAssertMiss(project, ["--systems-report"], InProcess(), "systems policy report mode")
    } finally {
        Directory.Delete(project, true)
    }
}

test "daemon and no-daemon check paths return identical results" {
    project := CheckStampProject()
    try {
        StartServer(project)
        assert RoutedThroughServer(AssertParity(project, ["check", "--project", project], null))
        assert RoutedThroughServer(AssertParity(project, ["check", "--project", project, "--aot"], null))
        assert RoutedThroughServer(AssertParity(project, ["check", "--project", project, "--text"], null))
        assert RoutedThroughServer(AssertParity(project, ["check", "--project", project, "--systems-report"], null))
    } finally {
        DeleteWorkspace(project)
    }
}

test "seeded randomized edits match forced fresh checks for three forty-step runs" {
    CheckStampProofRandomSequence(7)
    CheckStampProofRandomSequence(73)
    CheckStampProofRandomSequence(2026)
}

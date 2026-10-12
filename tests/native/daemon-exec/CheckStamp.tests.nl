namespace NSharpLang.DaemonExec.Tests

import System
import System.Collections.Generic
import System.IO
import System.Text.Json

func CheckStampProject(): string {
    project := NewWorkspace()
    File.WriteAllText(Path.Combine(project, "project.yml"), "name: CheckStampProbe\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    WriteSource(project, "Math.nl", "namespace CheckStampProbe\n\nfunc Twice(value: int): int {\n    return value * 2\n}\n\nfunc Use(): int {\n    return Twice(2)\n}\n")
    return project
}

func CheckStampStatsPath(): string {
    return Path.Combine(Path.GetTempPath(), "nsharp-check-stats-" + Guid.NewGuid().ToString("N") + ".json")
}

func CheckStampParsedFiles(path: string): long {
    try {
        using document := JsonDocument.Parse(File.ReadAllText(path))
        counters: JsonElement = default
        filesParsed: JsonElement = default
        if document.RootElement.TryGetProperty("counters", out counters) && counters.TryGetProperty("filesParsed", out filesParsed) {
            return filesParsed.GetInt64()
        }
    } finally {
        if File.Exists(path) {
            File.Delete(path)
        }
    }

    throw new InvalidOperationException("nlc check did not write the filesParsed counter.")
}

func CheckStampAnalyzedFiles(path: string): long {
    try {
        using document := JsonDocument.Parse(File.ReadAllText(path))
        counters: JsonElement = default
        filesAnalyzed: JsonElement = default
        if document.RootElement.TryGetProperty("counters", out counters) && counters.TryGetProperty("filesAnalyzed", out filesAnalyzed) {
            return filesAnalyzed.GetInt64()
        }
    } finally {
        if File.Exists(path) {
            File.Delete(path)
        }
    }

    throw new InvalidOperationException("nlc check did not write the filesAnalyzed counter.")
}

func CheckStampMultiFileProject(): string {
    project := NewWorkspace()
    File.WriteAllText(Path.Combine(project, "project.yml"), "name: CheckStampMultiProbe\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    WriteSource(project, "Math.nl", "namespace CheckStampMultiProbe\n\nfunc Twice(value: int): int {\n    return value * 2\n}\n")
    WriteSource(project, "Use.nl", "namespace CheckStampMultiProbe\n\nfunc Use(): int {\n    return Twice(2)\n}\n")
    WriteSource(project, "Other.nl", "namespace CheckStampMultiProbe\n\nfunc Other(): int {\n    value := 9\n    return value\n}\n")
    return project
}

func CheckStampRun(project: string, args: string[], environment: Dictionary<string, string?>): ProcessRun {
    allArgs := new List<string>()
    allArgs.Add("check")
    allArgs.Add("--project")
    allArgs.Add(project)
    allArgs.AddRange(args)
    return NlcWith(allArgs.ToArray(), project, environment, null)
}

func CheckStampAssertSame(expected: ProcessRun, actual: ProcessRun, edit: string) {
    assert actual.ExitCode == expected.ExitCode, edit + ": exit code differed"
    assert actual.Stdout == expected.Stdout, edit + ": stdout differed\nexpected:\n" + expected.Stdout + "\nactual:\n" + actual.Stdout
    assert actual.Stderr == expected.Stderr, edit + ": stderr differed\nexpected:\n" + expected.Stderr + "\nactual:\n" + actual.Stderr
}

func CheckStampAssertInvalidatedLikeFresh(project: string, label: string) {
    fullEnvironment := InProcess()
    fullEnvironment["NSHARP_INCREMENTAL"] = "0"
    fresh := CheckStampRun(project, new string[](0), fullEnvironment)

    statsPath := CheckStampStatsPath()
    cached := CheckStampRun(project, ["--stats=" + statsPath], InProcess())
    CheckStampAssertSame(fresh, cached, label)
    parsed := CheckStampParsedFiles(statsPath)
    assert parsed > 0, label + ": a changed input was answered without parsing"

    noOpStatsPath := CheckStampStatsPath()
    noOp := CheckStampRun(project, ["--stats=" + noOpStatsPath], InProcess())
    CheckStampAssertSame(cached, noOp, label + " no-op replay")
    assert CheckStampParsedFiles(noOpStatsPath) == 0, label + ": an unchanged check parsed source files"
}

test "cold check stamps replay exact JSON and text with zero parsed files" {
    project := CheckStampProject()
    try {
        prime := CheckStampRun(project, new string[](0), InProcess())
        jsonStatsPath := CheckStampStatsPath()
        replay := CheckStampRun(project, ["--stats=" + jsonStatsPath], InProcess())
        CheckStampAssertSame(prime, replay, "JSON no-op")
        assert CheckStampParsedFiles(jsonStatsPath) == 0

        textPrime := CheckStampRun(project, ["--text"], InProcess())
        textStatsPath := CheckStampStatsPath()
        textReplay := CheckStampRun(project, ["--text", "--stats=" + textStatsPath], InProcess())
        CheckStampAssertSame(textPrime, textReplay, "text no-op")
        assert CheckStampParsedFiles(textStatsPath) == 0
    } finally {
        Directory.Delete(project, true)
    }
}

test "cold check stamps miss on source, file-set and project configuration edits and match a fresh check" {
    project := CheckStampProject()
    try {
        CheckStampRun(project, new string[](0), InProcess())

        mathPath := Path.Combine(project, "Math.nl")
        originalMath := File.ReadAllText(mathPath)
        File.WriteAllText(mathPath, originalMath.Replace("value * 2", "value * 3"))
        CheckStampAssertInvalidatedLikeFresh(project, "body edit")

        changedMath := File.ReadAllText(mathPath)
        File.WriteAllText(mathPath, changedMath.Replace("func Twice(value: int): int", "func Twice(value: int, factor: int): int").Replace("value * 3", "value * factor").Replace("Twice(2)", "Twice(2, 3)"))
        CheckStampAssertInvalidatedLikeFresh(project, "signature edit")

        extraPath := Path.Combine(project, "Extra.nl")
        File.WriteAllText(extraPath, "namespace CheckStampProbe\n\nfunc Extra(): int {\n    return 5\n}\n")
        CheckStampAssertInvalidatedLikeFresh(project, "new source file")
        File.Delete(extraPath)
        CheckStampAssertInvalidatedLikeFresh(project, "deleted source file")

        projectFile := Path.Combine(project, "project.yml")
        File.WriteAllText(projectFile, File.ReadAllText(projectFile) + "# cache input change\n")
        CheckStampAssertInvalidatedLikeFresh(project, "project.yml edit")
    } finally {
        Directory.Delete(project, true)
    }
}

test "a cold body edit reuses unchanged file analyses and matches a full check" {
    project := CheckStampMultiFileProject()
    try {
        CheckStampRun(project, new string[](0), InProcess())
        mathPath := Path.Combine(project, "Math.nl")
        File.WriteAllText(mathPath, File.ReadAllText(mathPath).Replace("value * 2", "value * 3"))

        fullEnvironment := InProcess()
        fullEnvironment["NSHARP_INCREMENTAL"] = "0"
        fresh := CheckStampRun(project, new string[](0), fullEnvironment)
        statsPath := CheckStampStatsPath()
        incremental := CheckStampRun(project, ["--stats=" + statsPath], InProcess())
        CheckStampAssertSame(fresh, incremental, "multi-file cold body edit")
        assert CheckStampAnalyzedFiles(statsPath) == 1, "a cold body-only edit must analyze exactly its edited file"

        File.WriteAllText(mathPath, File.ReadAllText(mathPath).Replace("value * 3", "missing * 3"))
        diagnosticFresh := CheckStampRun(project, new string[](0), fullEnvironment)
        diagnosticStatsPath := CheckStampStatsPath()
        diagnosticPartial := CheckStampRun(project, ["--stats=" + diagnosticStatsPath], InProcess())
        CheckStampAssertSame(diagnosticFresh, diagnosticPartial, "body edit that introduces an analyzer diagnostic")
        assert diagnosticPartial.ExitCode != 0, "the edited body must report its new diagnostic"
        assert CheckStampAnalyzedFiles(diagnosticStatsPath) == 1, "a diagnostic body edit must analyze exactly its edited file"
    } finally {
        Directory.Delete(project, true)
    }
}

test "check stamps preserve diagnostics and a nonzero exit code" {
    project := CheckStampProject()
    try {
        mathPath := Path.Combine(project, "Math.nl")
        File.WriteAllText(mathPath, File.ReadAllText(mathPath).Replace("value * 2", "missing * 2"))

        fullEnvironment := InProcess()
        fullEnvironment["NSHARP_INCREMENTAL"] = "0"
        fresh := CheckStampRun(project, new string[](0), fullEnvironment)
        assert fresh.ExitCode != 0, "the fixture edit must produce a diagnostic"

        statsPath := CheckStampStatsPath()
        first := CheckStampRun(project, ["--stats=" + statsPath], InProcess())
        CheckStampAssertSame(fresh, first, "diagnostic cache miss")
        assert CheckStampParsedFiles(statsPath) > 0

        noOpStatsPath := CheckStampStatsPath()
        replay := CheckStampRun(project, ["--stats=" + noOpStatsPath], InProcess())
        CheckStampAssertSame(first, replay, "diagnostic cache hit")
        assert CheckStampParsedFiles(noOpStatsPath) == 0

        textPrime := CheckStampRun(project, ["--text"], InProcess())
        textStatsPath := CheckStampStatsPath()
        textReplay := CheckStampRun(project, ["--text", "--stats=" + textStatsPath], InProcess())
        CheckStampAssertSame(textPrime, textReplay, "text diagnostic cache hit")
        assert textReplay.ExitCode != 0
        assert CheckStampParsedFiles(textStatsPath) == 0
    } finally {
        Directory.Delete(project, true)
    }
}

test "a truncated check stamp falls back to a full check and then re-arms the cache" {
    project := CheckStampProject()
    try {
        prime := CheckStampRun(project, new string[](0), InProcess())
        stamps := Directory.GetFiles(Path.Combine(Path.Combine(project, "obj"), "nlc"), "*.check.stamp")
        assert stamps.Length == 1, "expected one check-result stamp"
        File.WriteAllBytes(stamps[0], [1, 2, 3])

        statsPath := CheckStampStatsPath()
        recovered := CheckStampRun(project, ["--stats=" + statsPath], InProcess())
        CheckStampAssertSame(prime, recovered, "corrupt stamp recovery")
        assert CheckStampParsedFiles(statsPath) > 0, "a truncated stamp must force full analysis"

        noOpStatsPath := CheckStampStatsPath()
        noOp := CheckStampRun(project, ["--stats=" + noOpStatsPath], InProcess())
        CheckStampAssertSame(recovered, noOp, "re-armed stamp")
        assert CheckStampParsedFiles(noOpStatsPath) == 0

        bytes := File.ReadAllBytes(stamps[0])
        bytes[bytes.Length / 2] = (byte)(bytes[bytes.Length / 2] ^ 1)
        File.WriteAllBytes(stamps[0], bytes)
        garbledStatsPath := CheckStampStatsPath()
        garbledRecovery := CheckStampRun(project, ["--stats=" + garbledStatsPath], InProcess())
        CheckStampAssertSame(recovered, garbledRecovery, "garbled stamp recovery")
        assert CheckStampParsedFiles(garbledStatsPath) > 0, "a garbled stamp must force full analysis"
    } finally {
        Directory.Delete(project, true)
    }
}

test "a referenced project rebuild invalidates the saved result" {
    container := NewWorkspace()
    app := Path.Combine(container, "App")
    reference := Path.Combine(container, "Reference")
    Directory.CreateDirectory(app)
    Directory.CreateDirectory(reference)
    File.WriteAllText(Path.Combine(app, "project.yml"), "name: CheckStampApp\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: ../Reference/project.yml\n")
    File.WriteAllText(Path.Combine(reference, "project.yml"), "name: CheckStampReference\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    WriteSource(app, "Use.nl", "namespace CheckStampApp\n\nimport CheckStampReference\n\nfunc Use(): int => Value()\n")
    WriteSource(reference, "Api.nl", "namespace CheckStampReference\n\nfunc Value(): int => 1\n")
    try {
        referenceBuild := NlcWith(["build", "--project", reference], reference, InProcess(), null)
        assert referenceBuild.ExitCode == 0, referenceBuild.Stderr
        CheckStampRun(app, new string[](0), InProcess())

        referenceSource := Path.Combine(reference, "Api.nl")
        File.WriteAllText(referenceSource, "namespace CheckStampReference\n\nfunc Value(): string => \"changed\"\n")
        rebuilt := NlcWith(["build", "--project", reference], reference, InProcess(), null)
        assert rebuilt.ExitCode == 0, rebuilt.Stderr
        CheckStampAssertInvalidatedLikeFresh(app, "referenced project rebuild")
    } finally {
        Directory.Delete(container, true)
    }
}

test "workspace checks persist independent member results and replay the workspace envelope" {
    workspace := NewWorkspace()
    child := Path.Combine(workspace, "Child")
    Directory.CreateDirectory(child)
    File.WriteAllText(Path.Combine(child, "project.yml"), "name: CheckStampChild\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    WriteSource(workspace, "Program.nl", "namespace DaemonExecProbe\n\nfunc main() {\n    print \"root\"\n}\n")
    WriteSource(child, "Child.nl", "namespace CheckStampChild\n\nfunc Value(): int {\n    return 1\n}\n")
    try {
        prime := NlcWith(["check"], workspace, InProcess(), null)
        statsPath := CheckStampStatsPath()
        replay := NlcWith(["check", "--stats=" + statsPath], workspace, InProcess(), null)
        CheckStampAssertSame(prime, replay, "workspace no-op")
        assert CheckStampParsedFiles(statsPath) == 0
        stamps := Directory.GetFiles(Path.Combine(Path.Combine(workspace, "obj"), "nlc"), "*.check.stamp")
        childStamps := Directory.GetFiles(Path.Combine(Path.Combine(child, "obj"), "nlc"), "*.check.stamp")
        assert stamps.Length == 1 && childStamps.Length == 1, "workspace members must own their check stamps"

        textPrime := NlcWith(["check", "--text"], workspace, InProcess(), null)
        textStatsPath := CheckStampStatsPath()
        textReplay := NlcWith(["check", "--text", "--stats=" + textStatsPath], workspace, InProcess(), null)
        CheckStampAssertSame(textPrime, textReplay, "workspace text no-op")
        assert CheckStampParsedFiles(textStatsPath) == 0

        reportPrime := NlcWith(["check", "--systems-report"], workspace, InProcess(), null)
        reportStatsPath := CheckStampStatsPath()
        reportReplay := NlcWith(["check", "--systems-report", "--stats=" + reportStatsPath], workspace, InProcess(), null)
        CheckStampAssertSame(reportPrime, reportReplay, "workspace systems report no-op")
        assert CheckStampParsedFiles(reportStatsPath) == 0

        childSource := Path.Combine(child, "Child.nl")
        File.WriteAllText(childSource, File.ReadAllText(childSource).Replace("return 1", "return 2"))
        fullEnvironment := InProcess()
        fullEnvironment["NSHARP_INCREMENTAL"] = "0"
        fresh := NlcWith(["check"], workspace, fullEnvironment, null)
        changedStatsPath := CheckStampStatsPath()
        changed := NlcWith(["check", "--stats=" + changedStatsPath], workspace, InProcess(), null)
        CheckStampAssertSame(fresh, changed, "workspace member body edit")
        assert CheckStampParsedFiles(changedStatsPath) > 0
    } finally {
        Directory.Delete(workspace, true)
    }
}

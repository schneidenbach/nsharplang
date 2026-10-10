namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.IO

test "Execute logs every compiler diagnostic in result order before failure and skips reference synchronization" {
    scratch := EmitTaskScratch("execute-diagnostics")
    try {
        firstSourcePath := Path.Combine(scratch, "First.nl")
        secondSourcePath := Path.Combine(scratch, "Second.nl")
        projectFile := Path.Combine(scratch, "project.yml")
        target := Path.Combine(Path.Combine(scratch, "out"), "ExecuteFixture.dll")
        referenceTarget := Path.Combine(Path.Combine(Path.Combine(scratch, "out"), "ref"), "ExecuteFixture.dll")
        projectPath := Path.Combine(scratch, "Execute.proj")
        badReference := Path.Combine(scratch, "Bad.dll")
        File.WriteAllText(
            firstSourcePath,
            "func First(): int {\n" + "    return missingFirst\n" + "}\n"
        )
        File.WriteAllText(secondSourcePath, "func Second(): int {\n" + "    return missingSecond\n" + "}\n")
        File.WriteAllText(badReference, "bad metadata")
        File.WriteAllText(projectFile, "name: ExecuteFixture\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        EmitTaskWriteDirectProjectWithReference(projectPath, firstSourcePath + ";" + secondSourcePath, projectFile, target, referenceTarget, badReference)

        result := EmitTaskRunDirectProject(projectPath)
        output := result.Stdout + result.Stderr
        first := "First.nl(2,12,2,23): error NL301: Variable 'missingFirst' not found | I cannot find a `missingFirst` variable on line 2: | Make sure you've declared this variable before using it. | docs: https://schneidenbach.github.io/nsharplang/docs/errors/NL301"
        second := "Second.nl(2,12,2,24): error NL301: Variable 'missingSecond' not found | I cannot find a `missingSecond` variable on line 2: | Make sure you've declared this variable before using it. | docs: https://schneidenbach.github.io/nsharplang/docs/errors/NL301"
        firstWarning := "First.nl(1,1,1,4): warning NL923: Reference assembly '" + badReference + "' could not be loaded or fully inspected (BadImageFormatException: Image is too small.); types from it may be reported as not found."
        secondWarning := "Second.nl(1,1,1,4): warning NL923: Reference assembly '" + badReference + "' could not be loaded or fully inspected (BadImageFormatException: Image is too small.); types from it may be reported as not found."
        firstIndex := output.IndexOf(first, StringComparison.Ordinal)
        secondIndex := output.IndexOf(second, StringComparison.Ordinal)
        firstWarningIndex := output.IndexOf(firstWarning, StringComparison.Ordinal)
        secondWarningIndex := output.IndexOf(secondWarning, StringComparison.Ordinal)
        assert result.ExitCode != 0, output
        assert firstIndex >= 0, output
        assert firstWarningIndex > firstIndex, output
        assert secondIndex > firstWarningIndex, output
        assert secondWarningIndex > secondIndex, output
        assert !output.Contains("Emitted N# IL assembly to "), output
        assert !File.Exists(target)
        assert !File.Exists(referenceTarget)
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "Execute synchronizes a successful output before its final message and reports an outer exception as failure" {
    scratch := EmitTaskScratch("execute-success-exception")
    try {
        sourcePath := Path.Combine(scratch, "Valid.nl")
        projectFile := Path.Combine(scratch, "project.yml")
        target := Path.Combine(Path.Combine(scratch, "out"), "ExecuteFixture.dll")
        referenceTarget := Path.Combine(Path.Combine(Path.Combine(scratch, "out"), "ref"), "ExecuteFixture.dll")
        projectPath := Path.Combine(scratch, "Execute.proj")
        File.WriteAllText(sourcePath, "func Value(): int {\n    return 42\n}\n")
        File.WriteAllText(projectFile, "name: ExecuteFixture\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        EmitTaskWriteDirectProject(projectPath, sourcePath, projectFile, target, referenceTarget)

        success := EmitTaskRunDirectProject(projectPath)
        successOutput := success.Stdout + success.Stderr
        assert success.ExitCode == 0, successOutput
        assert File.Exists(target)
        assert File.Exists(referenceTarget)
        assert successOutput.Contains("Emitted N# IL assembly to " + target), successOutput

        syncFailureTarget := Path.Combine(Path.Combine(scratch, "sync-failure-out"), "ExecuteFixture.dll")
        syncFailureProjectPath := Path.Combine(scratch, "SyncFailure.proj")
        EmitTaskWriteDirectProject(syncFailureProjectPath, sourcePath, projectFile, syncFailureTarget, scratch)
        syncFailure := EmitTaskRunDirectProject(syncFailureProjectPath)
        syncFailureOutput := syncFailure.Stdout + syncFailure.Stderr
        assert syncFailure.ExitCode != 0, syncFailureOutput
        assert File.Exists(syncFailureTarget)
        assert syncFailureOutput.Contains("Access to the path '" + scratch + "' is denied."), syncFailureOutput
        assert !syncFailureOutput.Contains("Emitted N# IL assembly to "), syncFailureOutput

        missingProjectFile := Path.Combine(scratch, "missing-project.yml")
        missingTarget := Path.Combine(Path.Combine(scratch, "missing-out"), "ExecuteFixture.dll")
        missingReferenceTarget := Path.Combine(Path.Combine(Path.Combine(scratch, "missing-out"), "ref"), "ExecuteFixture.dll")
        missingProjectPath := Path.Combine(scratch, "MissingProject.proj")
        EmitTaskWriteDirectProject(missingProjectPath, sourcePath, missingProjectFile, missingTarget, missingReferenceTarget)
        failure := EmitTaskRunDirectProject(missingProjectPath)
        failureOutput := failure.Stdout + failure.Stderr
        assert failure.ExitCode != 0, failureOutput
        assert failureOutput.Contains("Project file not found: " + missingProjectFile), failureOutput
        assert !failureOutput.Contains("Emitted N# IL assembly to "), failureOutput
        assert !File.Exists(missingTarget)
        assert !File.Exists(missingReferenceTarget)
    } finally {
        Directory.Delete(scratch, true)
    }
}

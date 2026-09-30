namespace NSharpLang.CliCommandContracts.Tests

import System
import System.Diagnostics
import System.IO
import System.Text.Json

// The repository root is a workspace with hundreds of independent member programs plus loose root
// sources. One invocation must check every program, aggregate its diagnostics, and remain bounded.
test "nlc check checks every repository project and aggregates member diagnostics within three minutes" {
    repositoryRoot := CliRepositoryRoot()
    startInfo := new ProcessStartInfo {
        FileName: "dotnet",
        Arguments: "\"" + CliDll() + "\" check --project \"" + repositoryRoot + "\" --json",
        WorkingDirectory: repositoryRoot
    }
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(180000) {
        process.Kill()
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("nlc check --project <repository-root> --json did not check the workspace within 180000 ms.")
    }

    exitCode := process.ExitCode
    stdout := stdoutTask.Result
    stderr := stderrTask.Result
    process.Dispose()

    assert exitCode == 1, stdout + stderr
    assert stderr.Length == 0, stderr
    document := JsonDocument.Parse(stdout)
    root := document.RootElement
    assert root.GetProperty("schemaVersion").GetInt32() == 2, stdout
    assert TextOf(root.GetProperty("command")) == "check"
    assert !root.GetProperty("ok").GetBoolean()
    assert EquivalentProcessPath(TextOf(root.GetProperty("projectRoot")), NormalizedFullPath(repositoryRoot))
    assert root.GetProperty("projects").GetArrayLength() >= 200, stdout
    assert root.GetProperty("checkedFiles").GetInt32() >= 1000, stdout
    assert root.GetProperty("summary").GetProperty("errors").GetInt32() > 0, stdout

    expectedMemberRoot := NormalizedFullPath(Path.Combine(Path.Combine(repositoryRoot, "src"), "NSharpLang.Compiler.Core"))
    foundMemberDiagnostics := false
    for member in root.GetProperty("projects").EnumerateArray() {
        if EquivalentProcessPath(TextOf(member.GetProperty("projectRoot")), expectedMemberRoot) {
            foundMemberDiagnostics = true
            assert member.GetProperty("results").GetArrayLength() > 0, stdout
            assert member.GetProperty("summary").GetProperty("errors").GetInt32() > 0, stdout
        }
    }
    assert foundMemberDiagnostics, stdout
    document.Dispose()
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

        run := NlcIn(directory, "check --text")

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

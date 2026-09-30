namespace NSharpLang.GateScriptContracts.Tests

import System.IO

// ─── THE VS CODE INTEGRATION HARNESS GUARDS ───────────────────────────────────────────────────
//
// Replaces `tests/VscodeIntegrationHarnessTests.cs`.
//
// A VS Code integration run that matches ZERO tests must FAIL, not pass silently. Two independent
// layers make that promise: the shell harness (`tests/scripts/test-vscode-integration.sh`), which
// carries its own self-test mode, and the TypeScript suite runner
// (`editors/vscode/test/suite/index.ts`), which rejects a zero-total grep. Both are checked here.
//
// The self-test row runs the harness in `NSHARP_VSCODE_HARNESS_SELF_TEST=1` mode exactly as the
// deleted C# did — that mode feeds the harness synthetic output and never launches VS Code, so
// this row stays fast and installs nothing.
test "the VS Code harness self-test rejects output that reports zero passing tests" {
    launch := BashLaunch("NSHARP_VSCODE_HARNESS_SELF_TEST=1 tests/scripts/test-vscode-integration.sh", 60000)
    run := Run(launch)

    assert run.ExitCode == 0, "VS Code harness self-test failed with " + run.Report()
    assert run.Stdout.Contains("VS Code integration harness self-test passed")
}

test "the TypeScript suite runner fails when the test grep matches zero tests" {
    suiteRunner := File.ReadAllText(Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(RepositoryRoot(), "editors"), "vscode"), "test"), "suite"), "index.ts"))

    assert suiteRunner.Contains("runner?.total ?? 0")
    assert suiteRunner.Contains("TEST_GREP")
    assert suiteRunner.Contains("matched 0 tests")
}

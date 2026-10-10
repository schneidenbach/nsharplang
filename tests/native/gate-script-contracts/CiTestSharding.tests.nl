namespace NSharpLang.GateScriptContracts.Tests

import System.IO

test "CI shard discovery assigns every estate and native project once, including projects added later" {
    run := Run(BashLaunch("scripts/ci-test-shards.sh verify-contract", 60000))

    assert run.ExitCode == 0, "The CI shard contract failed: " + run.Report()
    assert run.Stdout.Contains("discovered projects are assigned exactly once across 10 test shards."), run.Stdout
}

test "CI shard duration planning includes the harness structural checks and keeps timing lanes separate" {
    run := Run(BashLaunch("scripts/ci-test-shards.sh plan --print", 60000))
    runner := File.ReadAllText(Path.Combine(RepositoryRoot(), "scripts/ci-test-shards.sh"))

    assert run.ExitCode == 0, "The CI shard planner failed: " + run.Report()
    assert run.Stdout.Contains("10 duration-balanced shards"), run.Stdout
    assert runner.Contains("for project in sorted(projects, key=lambda item: (-project_seconds(item, durations), item))"), "The duration planner must assign every discovered project, including compile-time-bench."
    assert runner.Contains("PERFORMANCE_SLICES"), "The paired timing jobs must remain isolated from the discovered project matrix."
    assert runner.Contains("\"medium-lsp\", \"large-lsp\""), "LSP median timing rows must be split by project size into the parallel performance lanes."
}

test "ordinary native shards use the Release CLI while structural and timing harness runs use Debug" {
    runner := File.ReadAllText(Path.Combine(RepositoryRoot(), "scripts/ci-test-shards.sh"))

    assert runner.Contains("DEBUG_CLI_DLL if project == PERFORMANCE_PROJECT else RELEASE_CLI_DLL")
    assert runner.Contains("\"structural\"") && runner.Contains("\"timing\"")
    assert runner.Contains("\"CompileTimeGate\"") && runner.Contains("\"AgentLoopGate\"")
    assert runner.Contains("--performance-slice")
    assert runner.Contains("--no-cache") && runner.Contains("--json")
}

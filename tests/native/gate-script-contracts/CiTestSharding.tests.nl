namespace NSharpLang.GateScriptContracts.Tests

import System.IO

test "CI shard discovery assigns every estate and native project once, including projects added later" {
    run := Run(BashLaunch("scripts/ci-test-shards.sh verify-contract", 60000))

    assert run.ExitCode == 0, "The CI shard contract failed: " + run.Report()
    assert run.Stdout.Contains("discovered projects are assigned exactly once across 10 test shards and the compiler-performance lane."), run.Stdout
}

test "CI shard duration planning is deterministic and keeps compiler performance isolated" {
    run := Run(BashLaunch("scripts/ci-test-shards.sh plan --print", 60000))

    assert run.ExitCode == 0, "The CI shard planner failed: " + run.Report()
    assert run.Stdout.Contains("10 duration-balanced shards")
    assert run.Stdout.Contains("compiler-performance:")
    assert run.Stdout.Contains("tests/native/compile-time-bench")
}

test "ordinary native shards use the Release CLI while the quiet performance lane uses Debug" {
    runner := File.ReadAllText(Path.Combine(RepositoryRoot(), "scripts/ci-test-shards.sh"))

    assert runner.Contains("DEBUG_CLI_DLL if project == PERFORMANCE_PROJECT else RELEASE_CLI_DLL")
    assert runner.Contains("--no-cache") && runner.Contains("--json")
}

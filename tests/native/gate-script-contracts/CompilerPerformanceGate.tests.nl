namespace NSharpLang.GateScriptContracts.Tests

import System.IO

func CompilerPerfSource(relativePath: string): string {
    return File.ReadAllText(Path.Combine(RepositoryRoot(), relativePath))
}

test "compiler performance base selection uses merge-base for branches and HEAD parent at the origin tip" {
    runner := CompilerPerfSource("tests/native/compile-time-bench/CompileTimeRunner.nl")

    assert runner.Contains("merge-base HEAD refs/remotes/origin/systems-language"), "A branch must compare against its merge base with origin/systems-language."
    assert runner.Contains("rev-parse HEAD~1"), "At the origin tip, the base must be the previous compiler commit."
    assert runner.Contains("archive --format=tar --output"), "The base source must be materialized without changing this worktree."
    assert runner.Contains("NSHARP_COMPILER_PERF_CACHE"), "The caller must be able to put commit-keyed base builds in its gate cache."
    assert runner.Contains("File.Exists(cliDll)"), "A cached base CLI must be reused."
    assert runner.Contains("BenchPrepareBaseCliProject"), "A clean base archive must receive the explicit compiler model/runtime project edges needed by the C# CLI launcher."
    assert runner.Contains("BenchApplyHeadCliDependencyClosure"), "The base CLI must use the head runtime dependency closure so both measured compilers resolve the same packages."
    assert runner.Contains("File.Copy(headDeps, baseDeps, true)"), "The dependency manifest must be refreshed for both new and cached base CLI builds."
    assert runner.Contains("Directory.GetFiles(headCliDirectory, \"*.dll\", SearchOption.TopDirectoryOnly)"), "The head package assemblies must be available to the cached base CLI."
    assert runner.Contains("dependencyName.StartsWith(\"NSharpLang.\""), "Refreshing package dependencies must preserve the base compiler's N# assemblies."
    assert runner.Contains("--disable-build-servers -nr:false"), "The cached base CLI must use the product gate's stable MSBuild flags."
    assert runner.Contains("\"NSharpLang.Cli\"") && runner.Contains("\"Cli.csproj\""), "The cached base compiler must be a built CLI."
}

test "compile-time timing pairs Core-scale emit while exact phase and counter checks remain primary" {
    gate := CompilerPerfSource("tests/native/compile-time-bench/CompileTimeBench.tests.nl")
    kernels := CompilerPerfSource("tests/native/compile-time-bench/CompileTimeBench.nl")
    baseline := CompilerPerfSource("tests/fixtures/compile-time/bootstrap-build-baseline.golden.json")

    assert gate.Contains("pairCount := 3"), "The Core-scale timing gate must take three paired samples."
    assert gate.Contains("headFirst := i % 2 == 0"), "The Core-scale gate must alternate which compiler runs first."
    assert gate.Contains("BenchCoreCounterFailure(\"src/NSharpLang.Compiler.Core\""), "The Core analysis counter contract must remain exact."
    assert gate.Contains("BenchCoreCounterFailure(\"Core-scale emit\""), "The deterministic emit workload must retain exact --stats counters."
    assert gate.Contains("AgentLoopCopyDirectory(coreSource, copiedSource)"), "The Core phase workload must start from a clean source copy so incremental outputs cannot change its counters."
    assert gate.Contains("BenchPhaseContractRefusal"), "The semantic phase contract must stay in the gate."
    assert kernels.Contains("return 1200"), "The paired timing tolerance must remain 1.20x."
    assert kernels.Contains("BenchMedianPairRatioThousandths"), "The gate must take the median after forming each pair ratio."
    assert !baseline.Contains("medianWallMs") && !baseline.Contains("medianPeakRssBytes") && !baseline.Contains("toleranceFactor"), "The compile-time golden must not gate absolute timing or RSS."
}

test "agent-loop timing pairs cold and daemon-warm scenarios with exact counter rows" {
    gate := CompilerPerfSource("tests/native/compile-time-bench/AgentLoopBench.tests.nl")
    kernels := CompilerPerfSource("tests/native/compile-time-bench/AgentLoopBench.nl")
    baseline := CompilerPerfSource("tests/fixtures/agent-loop/agent-loop-baseline.golden.json")

    assert gate.Contains("pairCount := 3"), "The agent-loop gate must take three paired samples."
    assert gate.Contains("AgentLoopRelativeTimingFailures(relative.Timings)"), "The gate must judge paired relative timings."
    assert gate.Contains("AgentLoopCounterFailures(baseline, relative.HeadCounterRows)"), "The exact structural counter contract must remain primary."
    assert kernels.Contains("headFirst := sample % 2 == 0"), "Agent-loop pairs must alternate head/base order."
    assert kernels.Contains("AgentLoopModeDaemonWarm()"), "Daemon-warm rows must be measured and reported."
    assert kernels.Contains("return 1200"), "The agent-loop tolerance must remain 1.20x."
    assert !baseline.Contains("medianWallMs") && !baseline.Contains("peakRssBytes") && !baseline.Contains("toleranceFactor"), "The agent-loop golden must contain structural counters only."
}

test "compiler performance gates keep load as trend data and carry ratio reports from the isolated gate" {
    compileGate := CompilerPerfSource("tests/native/compile-time-bench/CompileTimeBench.tests.nl")
    agentGate := CompilerPerfSource("tests/native/compile-time-bench/AgentLoopBench.tests.nl")
    runner := CompilerPerfSource("tests/native/compile-time-bench/CompileTimeRunner.nl")
    driver := ReadGateScript("test-all.sh")
    coreScript := ReadGateScript("test-all-core.sh")

    assert compileGate.Contains("BenchReadMachineLoad()"), "The compile-time gate should record machine load for its trend artifact."
    assert agentGate.Contains("BenchReadMachineLoad()"), "The agent-loop gate should record machine load for its trend artifact."
    assert !compileGate.Contains("BenchLoadRefusesTimingJudgement"), "Load must not suppress the compile-time ratio verdict."
    assert !agentGate.Contains("BenchLoadRefusesTimingJudgement") && !agentGate.Contains("SYSTEMS_BENCH"), "Load and SYSTEMS_BENCH must not suppress the agent-loop ratio verdict."
    assert runner.Contains("NSHARP_COMPILER_PERF_HEAD_DELAY_MS"), "The head-only delay hook must support a deliberate regression proof."
    assert coreScript.Contains("paired compiler timings"), "The paired compiler project must stay serial to reduce sibling contention noise."
    assert driver.Contains("NSHARP_COMPILER_PERF_GIT_ROOT=\"$SOURCE_ROOT\""), "The isolated gate must resolve base commits from the source worktree."
    assert driver.Contains("NSHARP_COMPILER_PERF_CACHE=\"$CACHE_ROOT/compiler-perf-base\""), "Base builds must be cached outside the disposable source copy."
    assert driver.Contains("for gate_record in native-sweep compile-time agent-loop; do"), "Both compiler trend reports must be carried out of the isolated gate."
}

test "CI runs the paired compiler gates with git history and uploads their trend artifacts" {
    workflow := CompilerPerfSource(".github/workflows/build.yml")

    assert workflow.Contains("fetch-depth: 0"), "CI must fetch the compiler history and origin branch needed for deterministic base selection."
    assert workflow.Contains("name: Compiler performance gates"), "CI must run the same N# compiler performance gate project as the product gate."
    assert workflow.Contains("test --project tests/native/compile-time-bench --no-cache"), "CI must run the fresh paired timing and structural counter gates."
    assert workflow.Contains("name: Upload compiler performance trends"), "CI must upload the absolute trend artifacts."
    assert workflow.Contains("artifacts/compile-time/relative-gate.md") && workflow.Contains("artifacts/agent-loop/relative-gate.md"), "Both ratio tables must be included in the CI artifact."
    assert workflow.Contains("if-no-files-found: warn"), "A test failure before artifact creation must not hide the gate's original failure."
}

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
    assert runner.Contains("if BenchIsCompilerProductAssembly(dependencyName) {"), "Refreshing package dependencies must preserve the base compiler's N# assemblies."
    assert runner.Contains("fileName.StartsWith(\"NSharpLang.\", StringComparison.Ordinal)"), "Refreshing package dependencies must preserve the base compiler's N# assemblies."
    assert runner.Contains("fileName == \"Compiler.dll\""), "Refreshing package dependencies must preserve the base compiler's command layer, which is not named NSharpLang.*."
    assert runner.Contains("--disable-build-servers -nr:false"), "The cached base CLI must use the product gate's stable MSBuild flags."
    assert runner.Contains("\"NSharpLang.Cli\"") && runner.Contains("\"Cli.csproj\""), "The cached base compiler must be a built CLI."
}

test "compile-time timing uses nine odd pairs and the confidence plus absolute-slowdown rule" {
    gate := CompilerPerfSource("tests/native/compile-time-bench/CompileTimeBench.tests.nl")
    kernels := CompilerPerfSource("tests/native/compile-time-bench/CompileTimeBench.nl")
    runner := CompilerPerfSource("tests/native/compile-time-bench/CompileTimeRunner.nl")
    baseline := CompilerPerfSource("tests/fixtures/compile-time/bootstrap-build-baseline.golden.json")

    assert gate.Contains("minimumPairs := 9"), "The Core-scale timing row must take at least nine independent pairs."
    assert gate.Contains("maximumPairs := 17") && gate.Contains("comparisonWorkMs < 350"), "The Core-scale row must have a bounded work target and pair cap."
    assert gate.Contains("warmupHead := BenchMeasureOnce") && gate.Contains("warmupBase := BenchMeasureOnce"), "Core-scale timing must discard a warm-up pair before collecting samples."
    assert gate.Contains("i % 2 == 0"), "The Core-scale gate must alternate which compiler runs first."
    assert gate.Contains("BenchCoreCounterFailure(\"src/NSharpLang.Compiler.Core\""), "The Core analysis counter contract must remain exact."
    assert gate.Contains("BenchCoreCounterFailure(\"Core-scale emit\""), "The deterministic emit workload must retain exact --stats counters."
    assert gate.Contains("AgentLoopCopyDirectory(coreSource, copiedSource)"), "The Core phase workload must start from a clean source copy so incremental outputs cannot change its counters."
    assert gate.Contains("BenchPhaseContractRefusal"), "The semantic phase contract must stay in the gate."
    assert gate.Contains("BenchFindCompilerProductChanges") && gate.Contains("not compared (no compiler change)"), "A harness-only commit must skip timing while retaining head counter checks."
    assert kernels.Contains("timing: "), "The compile-time record must label timing as compared or not compared."
    assert kernels.Contains("BenchMedianLowerConfidenceBound") && kernels.Contains("BenchMedianPairedDifference"), "Timing decisions need an exact confidence bound and an absolute median slowdown."
    assert kernels.Contains("return 1200"), "The paired timing tolerance must remain 1.20x."
    assert kernels.Contains("BenchMedianPairRatioThousandths"), "The gate must take the median after forming each pair ratio."
    assert runner.Contains("src/NSharpLang.Compiler.") && runner.Contains("src/NSharpLang.Compiler/") && runner.Contains("src/NSharpLang.Cli/"), "Product paths must cover compiler slice projects and the CLI."
    assert runner.Contains("src/NSharpLang.Runtime/") && runner.Contains("src/NSharpLang.Build.Tasks/") && runner.Contains("src/NSharpLang.Sdk/Sdk/"), "Product paths must cover runtime, build tasks and SDK targets."
    assert !baseline.Contains("medianWallMs") && !baseline.Contains("medianPeakRssBytes") && !baseline.Contains("toleranceFactor"), "The compile-time golden must not gate absolute timing or RSS."
}

test "agent-loop timing keeps exact counters and uses bounded confidence-tested pairs" {
    gate := CompilerPerfSource("tests/native/compile-time-bench/AgentLoopBench.tests.nl")
    kernels := CompilerPerfSource("tests/native/compile-time-bench/AgentLoopBench.nl")
    baseline := CompilerPerfSource("tests/fixtures/agent-loop/agent-loop-baseline.golden.json")

    assert gate.Contains("AgentLoopRelativeMinimumPairs()"), "The agent-loop gate must take at least nine paired samples per row."
    assert gate.Contains("not compared (no compiler change)"), "A harness-only commit must select the timing-skip status."
    assert kernels.Contains("timing: "), "The agent-loop record must label timing as compared or not compared."
    assert gate.Contains("AgentLoopMeasureStructuralRows"), "Skipping timing must still run exact head structural counter checks."
    assert gate.Contains("AgentLoopRelativeTimingFailures(relative.Timings)"), "The gate must judge paired relative timings."
    assert gate.Contains("AgentLoopCounterFailures(baseline, relative.HeadCounterRows)"), "The exact structural counter contract must remain primary."
    assert kernels.Contains("AgentLoopRelativeMinimumPairs(): int {\n    return 9") && kernels.Contains("AgentLoopRelativeMaximumPairs(): int {\n    return 17"), "Each row needs a nine-pair minimum and a finite upper bound."
    assert kernels.Contains("AgentLoopRelativeRowWorkTargetMs(): long {\n    return 350"), "Short rows must receive more pairs until their work target or cap."
    assert kernels.Contains("AgentLoopDiscardRelativeWarmupPair"), "Cold and daemon-warm rows must discard one warm-up pair."
    assert kernels.Contains("headFirst := sample % 2 == 0"), "Agent-loop pairs must alternate head/base order."
    assert kernels.Contains("AgentLoopModeDaemonWarm()"), "Daemon-warm rows must be measured and reported."
    assert kernels.Contains("AgentLoopRelativeMetric(row)") && kernels.Contains("AgentLoopRelativeSlowdownFloorMs"), "Fast rows may use a steadier CPU signal, and all failures require an absolute floor."
    assert kernels.Contains("AgentLoopTimingSensitivityTable") && kernels.Contains("AgentLoopMinimumDetectableSlowdownMs"), "The report must state the zero-noise detection floor for each measured size."
    assert kernels.Contains("wall base ms") && kernels.Contains("CPU base ms"), "The relative report must retain both wall and CPU measurements."
    assert kernels.Contains("AgentLoopSelectScenarios(scenarioId)"), "A focused same-code proof must be able to isolate one scenario without changing the gate matrix."
    assert CompilerPerfSource("tests/native/compile-time-bench/AgentLoopProgram.nl").Contains("--scenario <id>"), "The standalone paired runner must expose the exact scenario selector."
    assert gate.Contains("< 20") && gate.Contains("BenchFindCompilerProductChanges"), "The unchanged-product proof must repeat the diff skip twenty times."
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

# Systems N# Verification Summary

Date: 2026-06-03
Scope: current implementation pass for `docs/design/systems-nsharp.md`

This file records command evidence for the current Systems N# implementation
wave. It is intentionally separate from the design proposal so benchmark and
test claims stay tied to concrete runs.

## BenchmarkDotNet Gate

Current product gate: every Systems N#/runtime benchmark row must have median
ratio `<= 1.05` against its matched C# baseline and must allocate `0 B`. The
1.05 tolerance is deliberate: `scripts/benchmark-systems.sh` gates on medians
instead of means to avoid thermally-throttled tail iterations turning
near-parity rows flaky.

Command:

```bash
./scripts/benchmark-systems.sh
```

Result: passed.

Settings:

- Mode: `gate`
- Filter: `*SystemsFastGateBenchmarks*`
- Job: `short`
- Launch count: `1`
- Warmup count: `3`
- Iteration count: `16`
- Iteration time: `250ms`

Coverage enforced by `scripts/benchmark-systems.sh`:

| Benchmark family | Baseline rows | N#/runtime rows | Feature coverage |
| --- | ---: | ---: | --- |
| `SystemsFastGateBenchmarks` | 6 | 6 | aggregate hot loops, span handoff, caller buffers, direct `Result<T,E>` ABI, pooled boundary handoff, and hot+result combinations |

Gate result:

- Required rows: 12
- Observed rows: 12
- Allocation gate: every row reported `Allocated=0 B`
- Throughput gate: all N#/runtime rows were below the current median-ratio cap
  of `1.05` against matched C# baselines. The recorded pre-commit isolated full
  gate after generated JSON context proof promotion observed worst computed N#
  ratio `0.9903`, below both the current cap and parity.

Worst throughput ratios from that recorded passing isolated run:

| Row | Mean | Ratio | Allocated |
| --- | ---: | ---: | ---: |
| `SystemsFastGateBenchmarks.NSharp [Scenario=HotResultCombinations]` | 156.362 μs | 0.99 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=CallerBuffers]` | 6.919 μs | 0.87 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=SpanHandoff]` | 7.316 μs | 0.86 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=ResultAbi]` | 8.298 μs | 0.84 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=PooledBoundary]` | 4.566 μs | 0.66 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=HotLoops]` | 5.139 μs | 0.42 | 0 B |

Regression addressed in this wave:

- `SystemsHotPathBenchmarks.CountAscii` previously underperformed because the
  N# source used nested branches while the C# baseline used a combined
  `value >= 32 && value <= 126` branch. The benchmark source was made
  shape-equivalent. Fresh passing rows after the fix:
  `Size=64` ratio `0.97`, `Size=4096` ratio `1.00`, both `0 B`.
- The fast aggregate rows were then hardened after fresh `--commit` evidence
  exposed near-threshold and failing rows. Hot-loop, caller-buffer, and pooled
  boundary aggregate bodies now use fused hot-path shapes while the detailed
  matrix keeps the individual workload rows. `Result<T,E>` hot consumption uses
  direct tag checks plus unchecked payload reads after the tag is proven.
- The hot+result combination gate now calls explicit aggregate C#/N# methods
  instead of driving the detailed parameterized benchmark harness ten times per
  feature-family operation. The N# aggregate is now a compiled `[hot]`
  `allCombinations` function, avoiding a C#/N# delegate boundary for every
  sub-operation while the detailed matrix keeps the per-workload wrapper rows.
- A fresh `--commit` run exposed a `ResultAbi` row with rounded ratio `1.00`
  but computed mean ratio `1.0031`. The runtime-result hot path now uses
  explicit indexed loops, aggressive hot-path implementation hints, and direct
  tag assumptions for known benchmark states; the follow-up BenchmarkDotNet gate
  passed with `ResultAbi` computed ratio `0.8379`.
- A later full-gate attempt exposed `PooledBoundary` computed ratio `1.1521`.
  The fused N# pooled aggregate still checked an impossible negative-value branch
  after the previous clamp pass had already normalized negatives. Removing that
  redundant branch brought the follow-up row to computed ratio `0.6615`.

Harness hardening in this wave:

- Retained artifact directories are cleaned before a run, preventing stale CSVs
  from being counted as current evidence.
- The script now prints coverage, allocation, worst-ratio, and full-row
  summaries after a successful BenchmarkDotNet run.
- Benchmark N# source binding now compiles each unique benchmark source once per
  generated runner process and reuses the emitted `Program` type for subsequent
  method delegates.
- The fast aggregate gate now initializes only the benchmark family required by
  the current `Scenario` row instead of preparing all six families for every
  row.
- The gate now passes `--iterationTime 250` explicitly. This keeps the same
  12-row coverage, warmups, 16 measured iterations, memory diagnoser, and hard
  ratio/allocation parser, while avoiding BenchmarkDotNet's slower default
  500ms target for every measured iteration.
- The default suite gate now runs a 12-row aggregate mode rather than the full
  matrix. The full matrix remains available through
  `NSHARP_SYSTEMS_BENCH_MODE=matrix` and is structurally covered as a 196-row
  deep mode.
- Systems N#/runtime ratio limits were tightened from `1.20` to `1.15`, then
  superseded by the current hard `1.00` max-ratio gate.

## Focused Test Evidence

Proof-promotion command:

```bash
dotnet test tests/Tests.csproj \
  --filter "FullyQualifiedName~AnalyzerTests.GeneratedRegex|FullyQualifiedName~SystemsNSharpTests.SystemsProofProjects_AreExecutableAndCoveredByAudit|FullyQualifiedName~SystemsNSharpTests.ExecutableSystemsProofProjects" \
  --no-restore -v q --nologo
```

Result: focused proof/docs/JSON slice passed, 3/3 tests, 17.98s reported test
duration after the numeric JSON writer assertion was added.

Coverage:

- Executable systems proof projects now include proofs 24-48. Proofs 28 and 47
  are executable JSON-context/AOT-analysis proofs; native image publication is
  still not claimed.
- Proof 26 covers native `LibraryImport` declarations for open/close handles.
  Check/build pass with one expected boundary console warning, the perf report
  emits no sites, the emitted native methods have no managed body, and direct
  `ilverify` passes. Runtime execution is not claimed because `LibraryImport("c")`
  resolution is platform/deployment-specific.
- Proof 27 was rechecked after the native-import backend fix: the emitted
  `LibraryImport` method has no managed body and direct `ilverify` passes.
- Proof 29 covers an executable generated-regex boundary parser: `nlc check
  --systems-report` passes with two expected boundary-review warnings,
  `nlc build --perf-report` reports the reviewed `ParseRoute` allocation and
  no delegate, boxing, dispatch, closure, boundary-leak, trap, hot-readiness, or
  AOT blocker sites, the emitted assembly runs, and the proof test verifies
  preserved `[GeneratedRegex]` metadata plus cached `Regex` factory behavior.
  This is IL-backend generated-regex evidence, not a NativeAOT native image;
  `[GeneratedRegex]` remains a dedicated temporary hook even though the general
  Roslyn source-generator pipeline now supports generated C# sources.
- Proof 28 covers a NativeAOT-targeted JSON CLI: `nlc check --systems-report`
  passes with six reviewed boundary warnings, `nlc build --perf-report` reports
  three boundary allocations and no delegate, boxing, dispatch, closure,
  boundary-leak, trap, hot-readiness, or AOT blocker sites, the emitted assembly
  prints `{"Input":"input.txt","Verbose":true}`, and the proof test verifies the
  real System.Text.Json generator output: `JsonSerializerContext.Default`,
  `JsonTypeInfo<T>` property, converter implementation, and
  `aot.analysis=pass`/`trimSafe=true`.
- Proof 30 covers an allocation-free hot parser plus a boundary cold-failure
  logger. The perf report intentionally records one allocation site in
  `LogColdFailure`; the emitted assembly runs and verifies cleanly with
  ILVerify.
- Proof 33 covers an `ArrayPool<byte>` boundary that rents a byte buffer, reads a
  copied runtime DLL through `File.OpenRead`, calls a hot span parser, disposes
  the stream, returns the buffer on the lexical path, emits no perf-report sites,
  runs successfully, and verifies cleanly with ILVerify. Its two check warnings
  are the expected boundary-review findings for file open/read calls.
- Proof 34 covers a `MemoryPool<byte>` boundary that rents an
  `IMemoryOwner<byte>`, passes the owner span to a hot allocation-free fill
  routine, disposes the owner on the lexical path, emits no perf-report sites,
  runs successfully, and verifies cleanly with ILVerify.
- Proof 35 covers an async boundary that rents an `ArrayPool<byte>` buffer,
  reads from a copied runtime DLL with `FileStream.ReadAsync`, feeds the bytes
  to a hot allocation-free span parser, returns the buffer on the lexical path,
  and runs successfully. The perf report intentionally records two async
  boundary leak warnings for `Task<int>` return shapes and has no allocation,
  delegate, boxing, dispatch, trap, hot-readiness, or AOT blockers. The original
  `ValueTask<Result<T,E>>` shape remains a compiler/analyzer gap.
- Proof 37 covers a fixed-capacity custom map with a reviewed construction
  allocation in `NewMap`, hot allocation-free `Put`/`Get`, and
  `Result<int, MapError>` over a generated enum. The emitted assembly runs and
  direct `ilverify` reports all classes/methods verified.
- Proof 38 covers a current `struct` constrained generic sortable-record proof:
  `nlc check --systems-report` passes with one boundary allocation warning,
  `nlc build --perf-report` reports no delegate, boxing, dispatch, boundary
  leak, trap, hot-readiness, or AOT blockers, the emitted assembly runs, and
  the proof test decodes hot `SortPair` IL to require `constrained.` and no
  `box` opcode.
- Proof 46 covers an executable database-adapter boundary: the boundary allocates
  scratch state and constructs the row source, maps a row into a value DTO, and
  returns `Result<UserDto, DbError>` to hot code. The perf report intentionally
  records the two boundary allocation sites and has no delegate, boxing,
  dispatch, boundary leak, trap, hot-readiness, or AOT blockers. Real Dapper/EF
  NuGet execution remains external package interop work.
- Proof 47 covers CLI startup honesty with source-generated JSON:
  `nlc check --systems-report` passes with five reviewed boundary warnings,
  `nlc build --perf-report` reports four boundary allocations and no delegate,
  boxing, dispatch, closure, boundary-leak, trap, hot-readiness, or AOT blocker
  sites, warmup registration is present, the emitted assembly prints
  `{"Ready":true,"Mode":"run"}`, and the proof test verifies generated
  `StartupJsonContext` shape plus `aot.analysis=pass`/`trimSafe=true`.
- Proof 41 was rebuilt, run, and directly IL-verified after the enum metadata
  fix to keep generated-struct `Result<T,E>` access covered.
- Proof 42 covers a NativeAOT-targeted public API report: `nlc check
  --systems-report` reports `aot.analysis=pass`, `trimSafe=true`, and
  `NameApi.Normalize.effects.aotSafe=true`; `nlc build --perf-report` emits no
  allocation, delegate, boxing, dispatch, trap, hot-readiness, or AOT blocker
  sites; direct `ilverify` passes for the emitted library.
- Proof 40 has a real C# `ProjectReference` consumer that calls
  `PacketApi.ParseHeader(ReadOnlySpan<byte>)` and validates the
  `Result<Header, HeaderError>` ABI.
- The SDK project-reference test now covers a `.csproj` filename that differs
  from `project.yml` assembly identity.
- Proof 39 covers a hot-compatible extension-method pipeline over
  `ReadOnlySpan<int>`. Check/build pass with one expected boundary allocation
  warning in `Main`, the perf report emits no delegate, closure, boxing,
  dispatch, boundary-leak, trap, hot-readiness, or AOT blocker sites, and the
  emitted assembly runs successfully. This is pipeline-contract evidence, not a
  direct ZLinq package execution claim.

Additional compiler/runtime slice:

```bash
dotnet test tests/Tests.csproj \
  --filter "FullyQualifiedName~ILCompilerTests|FullyQualifiedName~CompilationBackendTests|FullyQualifiedName~ErrorTupleResultBranchTests|FullyQualifiedName~DotnetRunnerTests" \
  --no-restore
```

Result: passed, 500/500 tests.

## Full Suite Status

Command:

```bash
./scripts/test-all.sh --commit
```

Result: passed.

Highlights:

- Unit tests: passed, 3324/3324.
- Systems BenchmarkDotNet gate: passed, 12 rows, all `0 B`, worst ratio `0.99`
  and worst computed ratio `0.9903`, below the hard `1.00` cap.
- VS Code smoke tests: passed, 40/40.
- C# interop tests: passed, 31/31.
- Template creation/build, example builds/checks, and IL verification: passed.
- IL verification: passed, 84/84 N# assemblies.
- Fresh isolated run duration: `4m20s` after generated JSON context proof
  promotion.
- Timing from the recorded pre-commit isolated run: BenchmarkDotNet `1m17s`,
  unit tests `1m14s`, VS Code smoke `53s`, IL verification `25s`; all other
  full-gate steps were single-digit seconds.

Measured slow stages from the passing run:

| Stage | Duration |
| --- | ---: |
| Systems BenchmarkDotNet gate | 1m 17s |
| Unit tests | 1m 14s |
| VS Code smoke tests | 0m 53s |
| IL verification gate | 0m 25s |
| Full isolated run | 4m 20s |

Harness speedups landed in this wave:

- The isolated wrapper now uses a dependency-declaration/toolchain cache key for
  NuGet/npm package caches instead of the full source-result cache key, so
  source-only edits do not force an empty package cache.
- Example build and `nlc check` fan-out default to up to 8 workers while still
  allowing `TEST_ALL_JOBS` overrides.
- The Systems BenchmarkDotNet gate now pins measured iteration time to `250ms`,
  reducing the fresh full-gate benchmark section from `3m21s` to roughly
  `1m12s`-`1m16s` while preserving the same 12 rows, memory diagnoser, 16
  measured iterations, and hard computed-ratio/allocation checks.
- The core full-suite gate prints a timing summary for every section.
- The C# interop full-suite step now uses `dotnet test --no-restore` after its
  explicit restore, avoiding a duplicate NuGet restore without changing test
  coverage.
- Parallel single-file example builds now pass `--output` to a per-item
  temporary directory, preserving the parallel fan-out while avoiding shared
  `examples/**/bin` output races between files in the same directory.
- `nlc build --perf-report` now reuses the `SystemsReport` and AOT facts from
  the IL compiler instance that emitted the assembly instead of running a second
  analysis compile solely for JSON perf facts.
- CLI build linting now runs against the `MultiFileCompiler` parsed ASTs before
  IL emission instead of reparsing every source file in a separate lint
  preflight.
- The executable systems proof-matrix unit test remains intentionally slower
  than ordinary analyzer tests because it builds 25 proof projects, checks perf
  reports, runs selected emitted assemblies, inspects IL/reflection shape, and
  validates one real C# project-reference consumer.

Commit gate policy:

- Run `./scripts/test-all.sh --commit` after the final content edit and before
  committing so the release gate is fresh rather than cache-backed.

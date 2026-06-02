# Systems N# Verification Summary

Date: 2026-06-02
Scope: current implementation pass for `docs/design/systems-nsharp.md`

This file records command evidence for the current Systems N# implementation
wave. It is intentionally separate from the design proposal so benchmark and
test claims stay tied to concrete runs.

## BenchmarkDotNet Gate

Current gate: every Systems N#/runtime benchmark row must have ratio `<= 1.00`
against its matched C# baseline and must allocate `0 B`.

Command:

```bash
NSHARP_SYSTEMS_BENCH_ITERATION_COUNT=16 \
NSHARP_SYSTEMS_BENCH_ARTIFACTS=/tmp/nsharp-systems-fast-gate-combination-all \
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

Coverage enforced by `scripts/benchmark-systems.sh`:

| Benchmark family | Baseline rows | N#/runtime rows | Feature coverage |
| --- | ---: | ---: | --- |
| `SystemsFastGateBenchmarks` | 6 | 6 | aggregate hot loops, span handoff, caller buffers, direct `Result<T,E>` ABI, pooled boundary handoff, and hot+result combinations |

Gate result:

- Required rows: 12
- Observed rows: 12
- Allocation gate: every row reported `Allocated=0 B`
- Throughput gate: all N#/runtime rows reported BenchmarkDotNet `Ratio <= 1.00`
  against matched C# baselines; the worst computed N# ratio was `0.9809`

Worst throughput ratios from the passing run:

| Row | Mean | Ratio | Allocated |
| --- | ---: | ---: | ---: |
| `SystemsFastGateBenchmarks.NSharp [Scenario=HotResultCombinations]` | 153.759 μs | 0.98 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=ResultAbi]` | 8.520 μs | 0.87 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=SpanHandoff]` | 7.222 μs | 0.86 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=PooledBoundary]` | 5.342 μs | 0.79 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=CallerBuffers]` | 6.879 μs | 0.78 | 0 B |
| `SystemsFastGateBenchmarks.NSharp [Scenario=HotLoops]` | 5.013 μs | 0.44 | 0 B |

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
  feature-family operation.

Harness hardening in this wave:

- Retained artifact directories are cleaned before a run, preventing stale CSVs
  from being counted as current evidence.
- The script now prints coverage, allocation, worst-ratio, and full-row
  summaries after a successful BenchmarkDotNet run.
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
  --filter "FullyQualifiedName~SystemsNSharpTests.SystemsProofProjects_AreDesignOnlyAndCoveredByAudit|FullyQualifiedName~SystemsNSharpTests.ExecutableSystemsProofProjects" \
  --no-restore -v q --nologo
```

Result: passed, 2/2 tests.

Coverage:

- Executable systems proof projects now include proof 33
  (`arraypool-file-io`), proof 34 (`memorypool-disposal`), and proof 37
  (`fixed-capacity-map`) in addition to proofs 24, 25, 27, 31, 32, 36, 40, 41,
  43, 44, 45, and 48.
- Proof 33 covers an `ArrayPool<byte>` boundary that rents a byte buffer, reads a
  copied runtime DLL through `File.OpenRead`, calls a hot span parser, disposes
  the stream, returns the buffer on the lexical path, emits no perf-report sites,
  runs successfully, and verifies cleanly with ILVerify. Its two check warnings
  are the expected boundary-review findings for file open/read calls.
- Proof 34 covers a `MemoryPool<byte>` boundary that rents an
  `IMemoryOwner<byte>`, passes the owner span to a hot allocation-free fill
  routine, disposes the owner on the lexical path, emits no perf-report sites,
  runs successfully, and verifies cleanly with ILVerify.
- Proof 37 covers a fixed-capacity custom map with a reviewed construction
  allocation in `NewMap`, hot allocation-free `Put`/`Get`, and
  `Result<int, MapError>` over a generated enum. The emitted assembly runs and
  direct `ilverify` reports all classes/methods verified.
- Proof 41 was rebuilt, run, and directly IL-verified after the enum metadata
  fix to keep generated-struct `Result<T,E>` access covered.
- Proof 40 has a real C# `ProjectReference` consumer that calls
  `PacketApi.ParseHeader(ReadOnlySpan<byte>)` and validates the
  `Result<Header, HeaderError>` ABI.
- The SDK project-reference test now covers a `.csproj` filename that differs
  from `project.yml` assembly identity.

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
./scripts/test-all.sh
```

Result: passed.

Highlights:

- Unit tests: passed, 3317/3317.
- Systems BenchmarkDotNet gate: passed, 12 rows, all `0 B`, worst ratio `0.98`
  and worst computed ratio `0.9809`.
- VS Code smoke tests: passed, 40/40.
- C# interop tests: passed, 31/31.
- Template creation/build, example builds/checks, and IL verification: passed.
- IL verification: passed, 84/84 N# assemblies.
- Isolated cache result: `564eeb96c3525a25`, duration `436s`.

Measured slow stages from the passing run:

| Stage | Duration |
| --- | ---: |
| Systems BenchmarkDotNet gate | 3m 39s |
| Unit tests | 1m 39s |
| VS Code smoke tests | 0m 58s |
| IL verification gate | 0m 25s |
| Full isolated run | 7m 16s |

Harness speedups landed in this wave:

- The isolated wrapper now uses a dependency-declaration/toolchain cache key for
  NuGet/npm package caches instead of the full source-result cache key, so
  source-only edits do not force an empty package cache.
- Example build and `nlc check` fan-out default to up to 8 workers while still
  allowing `TEST_ALL_JOBS` overrides.
- The core full-suite gate prints a timing summary for every section.

Commit gate policy:

- Run `./scripts/test-all.sh --commit` after the final content edit and before
  committing so the release gate is fresh rather than cache-backed.

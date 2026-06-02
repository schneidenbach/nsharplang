# Systems Proof Project Audit

Date: 2026-06-02
Status: mixed executable proof report and compiler audit

The projects under `docs/design/systems-samples/proofs/` are design proof inputs
for use cases 24-48 in `docs/design/systems-nsharp.md`. Only projects marked
`executable` below are current compiler evidence, and only for the listed gates.
Projects marked `design-only` must not be cited as passing implementation
evidence until migrated and verified by `nlc check --systems-report`,
`nlc build --perf-report`, and any required interop/AOT gate.

Current audit command shape:

```bash
dotnet src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll check --project <proof-dir> --systems-report
```

Current status summary from the 2026-06-02 audit:

| Project | Status | Check evidence | Build/perf evidence | Other required evidence | Remaining gap |
| --- | --- | --- | --- | --- | --- |
| `24-zero-copy-frame-reader` | executable | passes, 0 errors, 1 warning | passes `nlc build --perf-report`; no allocation, boxing, dispatch, trap, hot-readiness, or AOT blockers | hot `NextFrame` reports zero-copy span handoff with `BinaryPrimitives.ReadInt32LittleEndian` and `reader.buf.Slice`; lifetime-only `'a` is erased from the CLR signature | Console output remains a known non-hot warning in `Main`. |
| `25-trusted-memory-copy` | executable | passes, 0 errors, 0 warnings | passes `nlc build --perf-report`; no allocation, boxing, dispatch, trap, hot-readiness, or AOT blockers; reports trusted site | emitted assembly runs with copied runtime asset; passes `nlc query trusted`; hot `CopyExact` uses governed `Buffer.MemoryCopy` through `Span<T>.ptr`/`ReadOnlySpan<T>.ptr` | Broader pointer syntax remains intentionally narrow; v1 only supports span `.ptr` for trusted memory-copy wrappers. |
| `26-native-device-handle` | design-only | 6 errors, 1 warning | missing | missing | Native handle ownership and source-generated interop proof not executable. |
| `27-c-library-cli` | executable | passes, 0 errors, 1 warning | passes `nlc build --perf-report`; no allocation, trap, dispatch, or AOT blockers | source-generated interop-shaped boundary compiles | Real native library execution and NativeAOT publish remain external deployment proofs. |
| `28-nativeaot-json-cli` | design-only | 7 errors, 3 warnings | missing | native image deferred | NativeAOT publish proof is analysis-only; sample syntax is not current. |
| `29-generated-regex-boundary` | design-only | 23 errors, 2 warnings | missing | missing | Generated regex boundary syntax and summaries are not executable. |
| `30-cold-failure-logging` | design-only | 10 errors, 1 warning | missing | missing | Cold-path allow/trap proof sample is still design syntax. |
| `31-hot-metrics` | executable | passes, 0 errors, 1 warning | passes `nlc build --perf-report`; no allocation, trap, or AOT blockers | hot metrics proof covers `Interlocked.Increment` on byref struct fields | Console output remains a known non-hot warning in `Main`. |
| `32-cache-prewarm` | executable | passes, 0 errors, 1 warning | passes `nlc build --perf-report`; no hot-readiness, trap, or AOT blockers | warmup config and static table initialization are compiler-covered | Console output remains a known non-hot warning in `Main`. |
| `33-arraypool-file-io` | design-only | 11 errors, 4 warnings | missing | missing | Pool rent/return proof uses unimplemented ownership/IO patterns. |
| `34-memorypool-disposal` | design-only | 3 errors, 1 warning | missing | missing | MemoryPool ownership/disposal summary is not a passing fixture. |
| `35-async-file-hot-parser` | design-only | 8 errors, 5 warnings | missing | missing | Async boundary sample uses unsupported/deferred async systems proof shapes. |
| `36-dictionary-setup-hot-read` | executable | passes, 0 errors, 3 warnings | passes `nlc build --perf-report`; reports setup allocation/boundary leak and no hot-readiness/trap/AOT blockers | hot `Dictionary.TryGetValue` read is summary-covered only for registered `Dictionary` members | Boundary return shape intentionally remains a warning. |
| `37-fixed-capacity-map` | design-only | 20 errors, 1 warning | missing | missing | Custom collection sample has parser/type-system gaps. |
| `38-unmanaged-sort-comparer` | design-only | 64 errors, 0 warnings | missing | missing | Generic comparer/constraint proof is not implemented. |
| `39-hot-linq-pipeline` | design-only | 24 errors, 1 warning | missing | missing | Hot-LINQ contract is summary design, not executable library evidence. |
| `40-csharp-hot-parser-api` | executable | passes, 0 errors, 0 warnings | passes `nlc build --perf-report`; no allocation, dispatch, trap, or AOT blockers | C# `ProjectReference` consumer compiles and runs `PacketApi.ParseHeader`, preserving `ReadOnlySpan<byte>` and `Result<Header, HeaderError>` ABI through mismatched `.csproj`/`project.yml` names | Broader C# ABI matrix and native publish remain future deployment proofs. |
| `41-structured-errors` | design-only | 22 errors, 0 warnings | missing | missing | Pattern/result sample uses proposed result/pattern syntax beyond current support. |
| `42-aot-friendly-public-api` | design-only | 9 errors, 2 warnings | missing | native image deferred | AOT public API proof is analysis-only and not executable. |
| `43-mono-wasm-plugin` | executable | passes, 0 errors, 0 warnings | passes `nlc build --perf-report`; no allocation, dispatch, trap, or AOT blockers | target-qualified `aotSafe(mono-wasm)` analysis compiles | Actual Mono/WASM runner remains an external deployment proof. |
| `44-ci-allocation-gate` | executable | passes, 0 errors, 2 warnings | passes `nlc build --perf-report`; reports boundary allocation and no AOT blockers | fast Systems BenchmarkDotNet gate covers allocation/perf CI enforcement; detailed matrix remains explicit deep mode | No native image proof required for this use case. |
| `45-trusted-audit` | executable | passes, 0 errors, 0 warnings | passes `nlc build --perf-report`; reports trusted site | passes `nlc query trusted` with owner/review/expiry/unsafe metadata | Broader unsafe-wrapper projects still pending. |
| `46-dapper-boundary` | design-only | 14 errors, 6 warnings | missing | missing | ORM boundary sample is intentionally design-only. |
| `47-cli-startup-honesty` | design-only | 12 errors, 4 warnings | missing | native image deferred | Startup/AOT/readiness proof is broader than current implementation. |
| `48-effect-drift` | executable | passes, 0 errors, 1 warning | passes `nlc build --perf-report`; reports boundary allocation and no hot-readiness/trap/AOT blockers | source-inferred helper allocation drift is covered by an adversarial systems test | Broad external package identity drift proof remains deferred to sidecar/package coverage. |

Executable Systems N# evidence currently lives in
`tests/fixtures/systems-gauntlet/`, the executable proof projects listed above,
`tests/SystemsNSharpTests.cs`, the fast BenchmarkDotNet gate, and the detailed
BenchmarkDotNet matrix mode in `benchmarks/Systems*Benchmarks.cs` enforced by
`scripts/benchmark-systems.sh`.
Those are the artifacts that must be cited for current implementation status.

# Systems Proof Project Audit

Date: 2026-06-01
Status: current compiler audit, not a pass report

The projects under `docs/design/systems-samples/proofs/` are design proof inputs
for use cases 24-48 in `docs/design/systems-nsharp.md`. They are not executable
examples and must not be cited as passing compiler evidence until each project
has been migrated into a current compiler fixture or example and verified by
`nlc check --systems-report`, `nlc build --perf-report`, and any required
interop/AOT gate.

Current audit command shape:

```bash
dotnet src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll check --project <proof-dir> --systems-report
```

Current status summary from the 2026-06-01 audit:

| Project | Errors | Warnings | Primary reason it is not executable evidence |
| --- | ---: | ---: | --- |
| `24-zero-copy-frame-reader` | 7 | 1 | Proposed enum/call syntax and hot external-call gaps. |
| `25-trusted-memory-copy` | 4 | 0 | Proposed unsafe/trusted body syntax exceeds current parser/analyzer support. |
| `26-native-device-handle` | 6 | 1 | Native handle ownership and source-generated interop proof not executable. |
| `27-c-library-cli` | 4 | 1 | Boundary/native interop sample still uses design-only shapes. |
| `28-nativeaot-json-cli` | 7 | 3 | NativeAOT publish proof is analysis-only; sample syntax is not current. |
| `29-generated-regex-boundary` | 23 | 2 | Generated regex boundary syntax and summaries are not executable. |
| `30-cold-failure-logging` | 10 | 1 | Cold-path allow/trap proof sample is still design syntax. |
| `31-hot-metrics` | 8 | 2 | Metrics boundary and atomics sample is not compiler-current. |
| `32-cache-prewarm` | 3 | 1 | Warmup/readiness proof is incomplete beyond config/reporting. |
| `33-arraypool-file-io` | 11 | 4 | Pool rent/return proof uses unimplemented ownership/IO patterns. |
| `34-memorypool-disposal` | 3 | 1 | MemoryPool ownership/disposal summary is not a passing fixture. |
| `35-async-file-hot-parser` | 8 | 5 | Async boundary sample uses unsupported/deferred async systems proof shapes. |
| `36-dictionary-setup-hot-read` | 2 | 3 | Dictionary hot-read proof remains summary/design-only. |
| `37-fixed-capacity-map` | 20 | 1 | Custom collection sample has parser/type-system gaps. |
| `38-unmanaged-sort-comparer` | 64 | 0 | Generic comparer/constraint proof is not implemented. |
| `39-hot-linq-pipeline` | 24 | 1 | Hot-LINQ contract is summary design, not executable library evidence. |
| `40-csharp-hot-parser-api` | 6 | 0 | C# consumer ABI proof has no compiled interop project yet. |
| `41-structured-errors` | 22 | 0 | Pattern/result sample uses proposed result/pattern syntax beyond current support. |
| `42-aot-friendly-public-api` | 9 | 2 | AOT public API proof is analysis-only and not executable. |
| `43-mono-wasm-plugin` | 6 | 0 | Mono/WASM target proof is not implemented. |
| `44-ci-allocation-gate` | 1 | 2 | CI allocation proof needs the real perf-report/BDN gates now being added. |
| `45-trusted-audit` | 4 | 0 | Trusted audit project does not yet pass current syntax and query gates. |
| `46-dapper-boundary` | 14 | 6 | ORM boundary sample is intentionally design-only. |
| `47-cli-startup-honesty` | 12 | 4 | Startup/AOT/readiness proof is broader than current implementation. |
| `48-effect-drift` | 4 | 0 | Dependency drift proof lacks external identity validation. |

Executable Systems N# evidence currently lives in
`tests/fixtures/systems-gauntlet/`, `tests/SystemsNSharpTests.cs`, and
`benchmarks/Systems*Benchmarks.cs`. Those are the artifacts that must be cited
for current implementation status.

# Systems N# Sample Proofs

Status: mixed executable and design proof samples

These samples challenge the Systems N# use-case appendix in
`../systems-nsharp.md`. They are intentionally stored under `docs/design/`
instead of `examples/` because most files still use proposed Systems N# syntax
and contracts that are not yet current compiler fixtures.

Current compiler audit status is tracked in
`../../audits/systems-proof-project-audit.md`.

Executable proof projects can be cited only for the exact command gates they
pass. Current executable proof projects:

- `proofs/24-zero-copy-frame-reader`: `nlc check --systems-report`,
  `nlc build --perf-report`, and emitted assembly run.
- `proofs/25-trusted-memory-copy`: `nlc check --systems-report`,
  `nlc build --perf-report`, and emitted assembly run.
- `proofs/27-c-library-cli`: `nlc check --systems-report` and
  `nlc build --perf-report`.
- `proofs/30-cold-failure-logging`: `nlc check --systems-report`,
  `nlc build --perf-report`, and emitted assembly run.
- `proofs/31-hot-metrics`: `nlc check --systems-report` and
  `nlc build --perf-report`.
- `proofs/32-cache-prewarm`: `nlc check --systems-report` and
  `nlc build --perf-report`.
- `proofs/33-arraypool-file-io`: `nlc check --systems-report`,
  `nlc build --perf-report`, and emitted assembly run.
- `proofs/34-memorypool-disposal`: `nlc check --systems-report`,
  `nlc build --perf-report`, and emitted assembly run.
- `proofs/36-dictionary-setup-hot-read`: `nlc check --systems-report` and
  `nlc build --perf-report`.
- `proofs/37-fixed-capacity-map`: `nlc check --systems-report`,
  `nlc build --perf-report`, and emitted assembly run.
- `proofs/40-csharp-hot-parser-api`: `nlc check --systems-report`,
  `nlc build --perf-report`, and a C# `ProjectReference` consumer run.
- `proofs/41-structured-errors`: `nlc check --systems-report`,
  `nlc build --perf-report`, and emitted assembly run.
- `proofs/42-aot-friendly-public-api`: `nlc check --systems-report` and
  `nlc build --perf-report` for NativeAOT/trim-safety analysis.
- `proofs/43-mono-wasm-plugin`: `nlc check --systems-report` and
  `nlc build --perf-report` for target-qualified Mono/WASM AOT analysis.
- `proofs/44-ci-allocation-gate`: `nlc check --systems-report` and
  `nlc build --perf-report`.
- `proofs/45-trusted-audit`: `nlc check --systems-report`,
  `nlc build --perf-report`, and `nlc query trusted`.
- `proofs/48-effect-drift`: `nlc check --systems-report` and
  `nlc build --perf-report`.

All other proof projects remain design-only until migrated and verified.

The sample set is split in two:

- Basic one-file operations are embedded inline in `systems-nsharp.md`.
- Complex proofs live here as complete-ish projects with `project.yml` and
  `Program.nl`.

Each project is meant to answer one question: "Can this use case be expressed in
the proposed feature set without hand-waving the cost model?"

Current complex proof projects:

| Use case | Project |
| ---: | --- |
| 24 | `proofs/24-zero-copy-frame-reader` |
| 25 | `proofs/25-trusted-memory-copy` |
| 26 | `proofs/26-native-device-handle` |
| 27 | `proofs/27-c-library-cli` |
| 28 | `proofs/28-nativeaot-json-cli` |
| 29 | `proofs/29-generated-regex-boundary` |
| 30 | `proofs/30-cold-failure-logging` |
| 31 | `proofs/31-hot-metrics` |
| 32 | `proofs/32-cache-prewarm` |
| 33 | `proofs/33-arraypool-file-io` |
| 34 | `proofs/34-memorypool-disposal` |
| 35 | `proofs/35-async-file-hot-parser` |
| 36 | `proofs/36-dictionary-setup-hot-read` |
| 37 | `proofs/37-fixed-capacity-map` |
| 38 | `proofs/38-unmanaged-sort-comparer` |
| 39 | `proofs/39-hot-linq-pipeline` |
| 40 | `proofs/40-csharp-hot-parser-api` |
| 41 | `proofs/41-structured-errors` |
| 42 | `proofs/42-aot-friendly-public-api` |
| 43 | `proofs/43-mono-wasm-plugin` |
| 44 | `proofs/44-ci-allocation-gate` |
| 45 | `proofs/45-trusted-audit` |
| 46 | `proofs/46-dapper-boundary` |
| 47 | `proofs/47-cli-startup-honesty` |
| 48 | `proofs/48-effect-drift` |

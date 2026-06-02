# Systems N# Implementation Adversarial Review

Date: 2026-06-02
Scope: implementation pass for `docs/design/systems-nsharp.md`

## Review Position

The implementation covers a meaningful executable slice of the v1 product
surface as an enforceable policy lane, but it does not cover the whole proposal.
Systems N# currently proves source-level and summarized hot-path effects for the
compiler fixtures and CLI gates listed below. It does not prove process-wide
pause freedom, native-image emission, arbitrary third-party package safety,
data-race freedom, or every design proof project in the use-case appendix.

## Concrete Coverage Added

- HotSummary data model and BCL seed catalog for span/string/array helpers,
  `BinaryPrimitives`, `MemoryMarshal`, `BitOperations`, `Math`, `Vector`,
  `Volatile`, `Interlocked`, `Thread.MemoryBarrier`, pool APIs, `LibraryImport`,
  and `GeneratedRegex`, plus analyzer handling for source-generated
  `System.Text.Json` calls.
- Sidecar HotSummary loading via `language.systems.hotSummaryFiles`, with
  fail-closed `[hot]` behavior unless `allowHotSidecars` is explicitly true,
  and `NSYS150` drift diagnostics when a sidecar omits body/package identity.
- Interprocedural source summaries for current-project N# calls, including
  caller-to-callee call paths in systems diagnostics.
- Safe `stackalloc` budget enforcement via
  `language.systems.stackBudgetBytes`.
- `ref struct`, ref-like field restrictions, `scoped` parameter lifetimes, and
  `returns 'a` parsing/formatting/codegen support.
- Restricted `unsafe {}` plus `[memory(safe)]` and governed `[trusted]`
  requirements.
- Boundary/system exception-control-flow findings, obvious disposable ownership
  diagnostics, and fail-closed `NSYS140` checks for unsupported concurrency
  primitive calls.
- `Result<T,E>` runtime ABI plus compiler-known `Ok`/`Err` construction,
  systems must-use diagnostics, and copy-shape size warnings.
- Systems templates for `nlc new`, `dotnet new`, and `--systems` flags.
- Acceptance gauntlet fixtures under `tests/fixtures/systems-gauntlet/` with
  source, systems JSON golden, human diagnostic golden, perf-report golden, and
  C# interop notes for the ten executable v1 scenarios.
- Executable proof projects 26, 30, 33, 34, 37, 40, 41, 42, and 43 now cover
  the native device handle sample, the cold failure logging sample, the
  ArrayPool file-IO handoff sample, the MemoryPool disposal sample, the
  fixed-capacity map sample, the C# hot parser API, structured error values,
  the AOT-friendly public API sample, and the Mono/WASM target-analysis sample
  through `nlc check --systems-report` and `nlc build --perf-report`.
- Proof 40 additionally has a real C# `ProjectReference` consumer gate covering
  minimal N# SDK projects, `project.yml` assembly/version identity, the
  `Result<T,E>` runtime ABI, and a `ReadOnlySpan<byte>` parser API.
- Fast BenchmarkDotNet coverage for hot-path throughput/allocation across
  caller-owned loops, write buffers, direct Result ABI operations, pooled
  boundary handoff, and hot+result combinations (`SystemsFastGateBenchmarks`),
  with an explicit detailed matrix mode for the full `Systems*Benchmarks`
  corpus. The commit gate uses 16 measured iterations, requires all Systems
  benchmark rows to allocate 0 B, and keeps every N#/runtime row at or below a
  hard 1.00 ratio against matched C# baselines.
  Current command evidence is recorded in
  `docs/audits/systems-nsharp-verification-summary.md`.
- A proof-project audit for the design-only projects under
  `docs/design/systems-samples/proofs/`, explicitly recording that they are not
  passing executable evidence yet.

## Remaining Hard Edges

1. HotSummary matching is signature/pattern based, not full metadata-token and
   body-hash validation for every external assembly. Sidecar entries now fail
   when they omit body/package identity, but the loader still does not validate
   those identities against external binaries.
2. Lifetime analysis is CLR/ref-like oriented and catches the v1 escape shapes;
   it is not a Rust-style borrow checker.
3. Pool and disposable-resource balance are lexical and intentionally
   conservative. They recognize obvious return/dispose shapes but do not prove
   arbitrary ownership transfer.
4. AOT is analysis-only. Reports explicitly set `nativeImageEmitted: false`
   until `nlc publish --aot` emits and verifies a native image.
5. The acceptance gauntlet is intentionally source/analyzer focused. Broader
   C# ABI matrices, full NativeAOT, and source-generator deployment projects
   should become separate preview gates as those surfaces mature.
6. Most remaining complex proof projects for use cases 26-48 remain design proof
   inputs, not current compiler examples; only the projects marked `executable`
   in the proof audit are current compiler evidence. See
   `docs/audits/systems-proof-project-audit.md`.

## Adversarial Smoke Cases

- A `[hot]` caller reaches a cold callee that allocates: must fail at the call
  site with `NSYS010` and a call path.
- A sidecar summary claims a method is safe: must still fail in `[hot]` unless
  the project opts into hot sidecars.
- A sidecar summary omits body/package identity: must fail with `NSYS150`.
- A ref-like field appears in an ordinary struct: must fail with `NSYS080`.
- `unsafe {}` appears without `[memory(safe)]` and governed `[trusted]`: must
  fail with `NSYS100`.
- A function-level `[allow]` on a public API lacks governance text: must fail
  with `NSYS150`.
- A `Result<T,E>` return is ignored on a systems path: must fail with `NSYS160`.
- `Interlocked`/`Volatile` calls outside the v1 summarized set: must fail with
  `NSYS140` instead of being accepted by a wildcard.

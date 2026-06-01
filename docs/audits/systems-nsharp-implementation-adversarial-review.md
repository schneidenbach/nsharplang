# Systems N# Implementation Adversarial Review

Date: 2026-06-01
Scope: implementation pass for `docs/design/systems-nsharp.md`

## Review Position

The implementation now covers the v1 product surface as an enforceable policy
lane, but it should still be marketed carefully: Systems N# proves source-level
and summarized hot-path effects. It does not prove process-wide pause freedom,
native-image emission, arbitrary third-party package safety, or data-race
freedom.

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
  C# interop notes for the ten v1 scenarios.
- BenchmarkDotNet coverage for hot-path throughput/allocation
  (`SystemsHotPathBenchmarks`) and Result ABI throughput/allocation
  (`SystemsResultBenchmarks`).

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
5. The acceptance gauntlet is intentionally source/analyzer focused. Full
   NativeAOT, source-generator, and C# consumer projects should become separate
   preview gates as those deployment surfaces mature.

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

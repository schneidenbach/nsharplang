# Compiler Dogfood Benchmark Metrics — Summary

**Status:** Living document. Authoritative roll-up of N#-vs-C# benchmark metrics for the compiler
dogfood rewrite. Updated 2026-06-05.

This is the one-stop metrics table. Per-slice narrative evidence (why a probe was accepted or
rejected, the exact kernel shape, language/runtime limitations) lives in
[`compiler-dogfood-rewrite.md`](compiler-dogfood-rewrite.md); this file is the numbers.

## Acceptance rule (recap)

Strong target: **≥5× faster than the C# counterpart on BOTH the representative and the large
generated corpus**, with exact semantic parity and (ideally) zero per-operation managed allocation
on the N# path. Routing latitude exists for a slice that lands slightly under 5× when the win is
large, broadly applicable, and the **representative** row is convincing — but a path is **never**
routed on the large/generated row alone, and a representative-row miss is a rejection.

`ratio = mean(C#) / mean(N#)`. Ratio is the gate; it is robust to absolute-timing noise because the
two rows are measured under identical conditions.

## Measurement environment

- .NET 10.0.5, Arm64 (Apple Silicon), `dotnet run -c Release ... --memory`.
- Measured 2026-06-05. The seven slices below were each benchmarked inside their own isolated
  worktree, several while sibling slices were also building/benchmarking. Parallel load inflates
  **absolute** times but affects the C# and N# rows of a given benchmark equally, so the **ratios**
  (the gate) hold. Re-run any row sequentially with the filter in "Refresh" below for clean
  absolute numbers.

## This batch — 7 slices (2026-06-05)

| # | Slice / benchmark class | Corpus | C# mean | N# mean | Ratio | N# alloc | Routed? |
|---|-------------------------|--------|---------|---------|-------|----------|---------|
| 1 | Formatter import ordering · `CompilerServiceFormatterImportOrderingBenchmarks` | representative (~33 imports) | 2,057.0 ns | 330.6 ns | **6.2×** | 0 B (vs 2,568 B) | ✅ **routed** |
| 1 | " | large generated | 1,281.05 µs | 63.40 µs | **20.2×** | 0 B (vs 478,176 B) | ✅ |
| 2 | Formatter safety/error scan · `CompilerServiceFormatterSafetyScanBenchmarks` | representative | 2,066.0 ns | 707.8 ns | 2.9× | 0 B | ❌ rejected |
| 2 | " | large generated | 16,446.6 ns | 6,184.7 ns | 2.7× | 0 B | ❌ |
| 3 | ProjectFile source filtering · `CompilerServiceProjectSourceFilterBenchmarks` | representative | 411.42 µs | 15.94 µs | **25.8×** | 760 B (vs 307,248 B) | ✅ **routed** |
| 3 | " | large generated | 6.505 ms | 242.10 µs | **26.9×** | 10,944 B (vs 4,593,824 B) | ✅ |
| 4 | Analyzer overload-signature distinctness · `CompilerServiceAnalyzerOverloadSignatureBenchmarks` | representative | 2.339 µs | 2.665 µs | 0.88× (N# slower) | 0 B | ❌ rejected |
| 4 | " | large generated | 261.051 µs | 184.146 µs | 1.42× | 0 B | ❌ |
| 5 | ILCompiler overload selection · `CompilerServiceOverloadSelectionBenchmarks` | representative | 124.95 µs | 11.07 µs | **11.3×** | 0 B (vs 417,112 B) | ✅ **routed** |
| 5 | " | large generated | 1,042.99 µs | 95.91 µs | **10.9×** | 0 B (vs 3,337,272 B) | ✅ |
| 6 | Declared-type exact-name lookup · `CompilerServiceTypeLookupBenchmarks` | representative (best: NestedMiddle, 1024) | 1,326.79 ns | 344.09 ns | 3.86× | — | ❌ rejected (benchmark-only) |
| 6 | " | large generated (best: NestedLate, 8192) | 28,250.15 ns | 5,653.97 ns | 5.00× | — | ❌ |
| 7 | Code-intelligence output construction | — | — | — | — | — | audit-only (no kernel) |

### Routing rationale per slice

- **#1 Formatter import ordering — ROUTED.** 6.2× representative / 20.2× large, zero N# allocation.
  The C# per-call `Select`-with-index → `OrderByDescending(StartsWith "System")` → `ThenBy` →
  `ToList()` dominates even at small import counts, so the representative win is convincing. Routed
  via `NSharpCompilerDogfoodAdapter` (`FormatterImportOrderIndicesInto`, two-pass stable counting
  sort), LINQ kept as fallback. Codex review caught a scratch-buffer reuse bug (large-then-small list
  returned a stale length, silently disabling the fast path); fixed with a regression test.
- **#2 Formatter safety/error scan — REJECTED.** 2.9× / 2.7×, both rows miss the gate. The win is
  only the `Enumerable.Range().Where().ToArray()` allocation in the error-collection path; the actual
  hot cost is public error-message string materialization, which the kernel cannot remove. Kept as
  rejection evidence.
- **#3 ProjectFile source filtering — ROUTED.** 25.8× / 26.9×, ~400× less allocation. The C#
  baseline's two-pass `Where(...).ToArray()` plus per-file `Regex.Escape/Replace/IsMatch` dominates;
  the N# kernel precomputes exclude patterns once and classifies in a single pass into caller-owned
  buffers. Routed via `NSharpCompilerDogfoodAdapter.TryFilterSourceFiles`, preserving enumeration
  order and the public `string[]` contract.
- **#4 Analyzer overload-signature distinctness — REJECTED.** 0.88× (representative is *slower*) /
  1.42×. Once the analyzer holds short interned signature strings, C# `string.Equals` JITs to fast
  length/reference checks with no allocation, so the integer rank-row scan only wins marginally at
  large arity and loses on the common few-overload case. (The enum/union exhaustiveness *coverage*
  kernels in this area were already accepted and routed on the base branch; this slice covered the
  remaining `HasDistinctParameterSignature` leftover only.)
- **#5 ILCompiler overload selection — ROUTED.** 11.3× / 10.9×, zero N# allocation. Highest-velocity
  path (runs on every declared-method/constructor call during IL emission). Replaces the per-call
  LINQ/materialization binder with compact primitive candidate columns ranked by
  `OverloadSelectBestCandidate`, reproducing the exact tie-break order
  (score > non-generic > non-params > fewer-defaults, first-wins). 485 ILCompiler/dogfood tests pass.
- **#6 Declared-type exact-name lookup — REJECTED (benchmark-only).** Best representative case 3.86×;
  common compiler cases (tiny lists, early match, missing) sit at ≤1.4× or slower; only the
  large worst-case full scan reaches exactly 5.0×. The realistic baseline is a zero-allocation
  `FirstOrDefault(Ordinal Equals)` loop — no allocation to recover, and the N# delegate-call +
  bounds-check overhead dominates when lists are small. Benchmark-only by design: the relevant
  `TypeResolver` path lives in the LanguageServer, which this slice was not permitted to modify.
- **#7 Code-intelligence output construction — AUDIT-ONLY.** Hover/definition/diagnostic/completion
  construction (`GetHoverInfo`, `BuildSignature`, `FormatFunctionSignature`, `FormatTypeRef`,
  the 14-field `DiagnosticResult` record) is string/record materialization with no compact-array
  route that survives a public-string boundary crossing. Documented as not dogfood-able without
  broader N# ownership of the output representation; no kernel added.

## Batch outcome

- **Routed to production:** 3 — #1 Formatter import ordering, #3 ProjectFile source filtering,
  #5 ILCompiler overload selection.
- **Rejected (evidence retained):** 3 — #2 Formatter safety scan, #4 overload-signature distinctness,
  #6 declared-type exact-name lookup.
- **Audit-only:** 1 — #7 code-intelligence output.
- **Full `test-all.sh` gate** (VSCODE_TESTS=skip, fresh `--commit`) observed green on the Unit 3
  (3332 tests) and Unit 4 (610 s, all tests + IL verification) branches. Unit 6's branch tripped the
  format-contract gate on one file; it is not routed, so it carries no production risk (fix the
  formatting before merging that branch if it is kept).

## 2026-06-06 — Lexer feature-complete; comment-trivia benchmark

The N# lexer kernels reached full feature parity with the C# production lexer (indentation braces,
systems keywords, lifetimes, Unicode classification, malformed-number `Unknown` tokens, comment
trivia). Added `CompilerServiceLexerCommentBenchmarks` for the new `CommentsInto` kernel. Short-job
(`--job short`) numbers, parity asserted in `[GlobalSetup]`:

| Corpus | N# `CommentsInto` | C# `Lexer.Comments` | Speedup | N# alloc | C# alloc |
|--------|-------------------|---------------------|---------|----------|----------|
| Representative | 1.51 µs | 7.16 µs | 4.7× | 0 B | 33,882 B |
| LargeGenerated | 408 µs | 7.35 ms | 18.0× | 0 B | 10,664,663 B |

**Honest framing (not a clean codegen isolation):** C# has no dedicated comment scanner — the only way
to obtain `Lexer.Comments` is the full allocating `Lexer.Tokenize()` (StringBuilder per token, `Token`
records, `List<Token>`, indentation pass). So this measures *how each system obtains comment trivia
today*: N#'s dedicated zero-alloc comment scan vs C#'s tokenize-byproduct. It is dramatic and real
(0 B vs 10.7 MB on the large row), but it is NOT a scan-vs-scan comparison — a hypothetical C#
comment-only scanner would narrow it, and in the compiler the full token pass is needed regardless
(so the apples-to-apples cost is `TokenizeMetadataInto` + `CommentsInto`, both zero-alloc scans, which
the existing `CompilerServiceLexerMetadataBenchmarks` already covers for the token pass). The honest
takeaway: the N# lexer scanners are zero-allocation where the C# lexer allocates heavily, which is the
boundary-profiling thesis (N# wins when the C# baseline is wasteful) confirmed on the lexer subsystem.
The lexer kernels remain behind the `*DogfoodAdapter` bridge; routing the whole lexer is NOT justified
because the parser consumes C# `Token` objects, so materialization re-incurs the string allocations
— bridge deletion awaits an N# parser (Phase 2/3).

## 2026-06-06 — Parser front-end: N# statement kernel vs C# Parser (clears 5× on both rows)

The N#-native recursive-descent front-end (lexer→type→expression→statement kernels composed in-assembly
over one shared columnar node table) parses a supported-form function body vs the production C# `Parser`.
`CompilerServiceParserBenchmarks`, `--job short`, parse phase only (tokenization done once in setup),
node-for-node parity proven by `CompilerDogfoodProjectTests.Parser_RealCorpusFunctionBodies_MatchProductionParser`:

| Corpus | N# statement kernel | C# `Parser` | Speedup | N# alloc | C# alloc | Alloc ratio |
|--------|---------------------|-------------|---------|----------|----------|-------------|
| Representative | 550 ns | 3,266 ns | **5.9×** | 400 B | 5,688 B | 0.07 |
| LargeGenerated | 15.9 µs | 83.3 µs | **5.2×** | 8,608 B | 148,224 B | 0.06 |

Clears the ≥5× gate on BOTH rows. **Honest framing:** the C# parser allocates a record per AST node +
`List`s; the N# kernel writes a flat columnar table into caller-pre-allocated arrays (only the small
`st`/`argStack` scratch allocates — 400 B / 8,608 B). The columnar design is the win (the systems-tier
thesis). The C# baseline also parses the trivial `func benchBody() {…}` wrapper (signature + constructor
token-compaction); negligible on the body-dominated LargeGenerated row, so 5.2× is the conservative number.
Not yet routed: routing requires materializing the columnar table into the host `CompilationUnit` (or
N# consumers) — the swap-evidence criterion, a later phase.

## Prior accepted/rejected evidence (pre-this-batch)

Earlier dogfood slices already recorded in [`compiler-dogfood-rewrite.md`](compiler-dogfood-rewrite.md)
on the `codex/compiler-dogfood-benchmarks` lineage cover the lexer (token-kind / metadata scanning),
source-text line mapping, the CLI argument / query / doc-ordering / tree-dependency families,
declared-type suffix & name-candidate kernels (reported 11×–93×), diagnostic clustering/dedup,
completion grouping/receivers, semantic scopes, identifier spans, AOT requirements, anonymous-union
shims, struct-copy analysis, path matching, and the enum/union exhaustiveness coverage kernels. That
file remains the source of record for those numbers and routing decisions. (They are not
re-transcribed here to avoid drift; refresh them with the per-class filters below when a clean
sequential sweep is run.)

## Refresh

Build once, then run any class sequentially for clean absolute numbers:

```bash
dotnet build benchmarks/NSharpLang.Benchmarks.csproj -c Release
dotnet run -c Release --project benchmarks/NSharpLang.Benchmarks.csproj -- \
  --filter "*CompilerService*" --memory          # all compiler-service rows, or narrow with a class name
```

Parity for the routed/rejected kernels:

```bash
dotnet test tests/Tests.csproj --filter ClassName=CompilerDogfoodProjectTests
```

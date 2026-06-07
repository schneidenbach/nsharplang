# Dogfood Parity Roadmap (deferred Phase 5)

Scoped plan for the "M1: extend every N# dogfood kernel to full parity, then remove all silent C#
fallbacks" effort, intentionally deferred from the `review-fixes` branch as its own dedicated
project. It is effectively a multi-session compiler self-host and needs a quiet machine + a settled
`systems-language` tree to validate against.

## Goal

No silent behavior and no per-call C# fallbacks. Every dogfood method becomes **N#-authoritative**:
call the N# kernel directly, no `try/catch`-to-C#; exceptions propagate loudly. The only permitted
fallback is the bootstrap case "dogfood DLL not loaded at all" (`IsAvailable == false`), per
AGENTS.md. Each kernel must first be proven at full input parity by a **differential test** (run N#
and the old C# over a large/fuzzed corpus, assert identical output) before its fallback is deleted.

## Workstreams

### 5a — Live decline-based kernels (~31 methods)
Extend each to handle every input its C# counterpart did, then delete the decline early-returns + C#
fallback. Examples:
- Non-ASCII: `TryFilterSymbolsByNamePattern` (QueryCommand), `TryClassifyTidyDependencyStatusRanks` /
  `TryFilterTidyRemovalLines` (Tidy), `TrySelectBestDocType`, doc slugs, completion classifiers.
- Path edge cases: `TryFilterSourceFiles` (literal `\n` / regex parity).
Each paired with a differential parity test across fuzzed Unicode/edge inputs.

### 5b — Exception-only kernels (~55 methods)
Across the 3 adapters + perf adapter: add a differential parity test per kernel, then remove the
silent `catch { return false; }` + the C# fallback at the call site (Parser.cs, Formatter.cs,
ProjectFile.cs, CodeIntelligenceService.cs, OutputFormatter.cs, …). Kernel bugs then surface as
CI exceptions instead of silent degradation.

### 5c — Parser / binder / type-inference self-host (largest, highest-risk)
Bring the columnar front-end (`LexerTokenKindScanner.nl`, `Parser*.nl`, `ColumnarAstMaterializer.cs`,
`ColumnarNameResolver.cs`, `ColumnarTypeInferer.cs`, `ColumnarTypeLattice.cs`) to **full N# parity**
with `Parser.cs`/`SemanticModel.cs`: all declarations (class/struct/record/interface/enum/union/
package/imports), generics, all statements/expressions, attributes, error recovery. Build a
**differential parse harness**: parse every `.nl` file in the repo (examples, tests, the compiler's
own source) through both the N# columnar path and `Parser.cs`, assert AST-equivalence; add structured
fuzzing. Then flip the front-end on by default (remove `NSHARP_PARSER_FRONTEND` gating) and delete
the C# `Parser.cs` fallback at `Parser.cs:24` (and the columnar binder/inferer fallbacks).
- **Risk/blocker:** if true parser parity needs N# language features that don't yet exist, that is a
  genuine blocker — surface it rather than ship a partial silent path. Until 5c is fully green, the
  C# parser fallback stays (bootstrap-class) and the flag is not flipped.

### 5d — Remove the global silent-fallback affordance
Once 5a/5b/5c kernels are authoritative, ensure the bootstrap `IsAvailable` path is the sole
remaining fallback, with a one-time diagnostic if the DLL is unexpectedly missing.

## Folded-in review findings (deferred here because they live in the columnar pipeline)
- **M6** — `ParserDeclarations.nl` recognizes `Test`(73) as a top-level keyword, but the lexer never
  emits 73 (`test` is contextual → `Identifier`), so a `*.tests.nl` file with no top-level `func` is
  parsed as zero declarations and the adapter returns an empty symbol set instead of falling back.
  Fix as part of the parser kernel work (detect the contextual `test`/`setup`/`teardown` and fall
  back, or parse them). Repro: `examples/16-task-cli/Program.tests.nl`.
- **M8** — `NSharpCompilerDogfoodAdapter` columnar inferer keys `functionReturnTypes` by name only,
  so top-level overloads collide (last-registered wins). Key by canonical signature
  (`ColumnarFunctionSymbol.Signature()`).

## AGENTS.md update (deferred Phase 6)
Once the no-fallback policy is real, rewrite the "Compiler Dogfood Architecture" section:
N#-authoritative hot paths, **no silent per-call C# fallbacks**, bootstrap-only fallback; note the
differential-parity-harness requirement for routing an N# slice into production; remove stale rules.

## Sequencing / prerequisites
- Land the `review-fixes` branch first (Critical + all High + most Medium), then base this on the
  settled `systems-language`.
- Run on a quiet machine (the differential harness + any benchmark validation are load-sensitive).
- Drive 5c incrementally behind the differential harness; each sub-slice gated on it staying green.

# Self-Host Progress Log

**Status:** Living log for the N# compiler self-hosting / dogfood migration. Newest entries on top.
See [`compiler-dogfood-rewrite.md`](compiler-dogfood-rewrite.md) for per-slice methodology and
evidence, [`compiler-benchmark-metrics.md`](compiler-benchmark-metrics.md) for the numbers, and
[`compiler-dogfood-boundary-profiling.md`](compiler-dogfood-boundary-profiling.md) for the
delegate-boundary cost analysis (the key perf finding driving the endgame).

This log records: what migrated, benchmark deltas, adapters removed, bootstrap coverage %, and every
language/runtime/compiler limitation found plus the principled change made to resolve it.

---

## 2026-06-05 — Consolidation: dogfood work merged onto `systems-language`

**What:** Consolidated all scattered dogfood worktrees/branches onto the canonical working branch
`systems-language` (which carries the separate "Systems N#" line: memory pools, zero-copy proofs,
ref/lifetime safety, source generators, etc.). Previously the dogfood self-hosting work lived only on
`codex/compiler-dogfood-benchmarks` and a fan of unit branches.

Merged in:
- `nsharp-dogfood-profiling` — the real integration branch: canonical dogfood base (145 commits) +
  accepted/routed units **1** (formatter import ordering), **3** (ProjectFile source filtering),
  **5** (ILCompiler overload selection) + rejection-evidence units **2** (formatter safety scan),
  **4** (analyzer overload-signature distinctness), **6** (declared-type exact-name lookup) + all
  three design docs + the `DogfoodBoundaryOverheadBenchmarks` decomposition benchmark.
- `nsharp-dogfood-unit-7-code-intel-audit` — the audit-only doc section.

**Routed (production) kernels carried in** (unchanged numbers, see metrics doc):
- Formatter import ordering — 6.2× representative / 20.2× large, 0 B.
- ProjectFile source filtering — 25.8× / 26.9×.
- ILCompiler overload selection — 11.3× / 10.9×, 0 B (runs on every declared-method/ctor call).

**Conflicts reconciled (8 core files)** — preserving BOTH systems-language semantics and dogfood
routing:
- `ILCompiler.cs`: kept profiling's routed compact-candidate overload ranking
  (`SelectBestDeclaredMethodCandidate`) **and** systems-language's `HasRuntimeTypeParameters` generic
  detection; kept systems-language's `FinalizeTopLevelEnumTypes` (re-registers baked enums in
  `_enumTypes`/`_typeKeys`) **and** the dogfood `OrderTypeBuildersByDescendingTypeKeyDepth` helper;
  kept systems-language's `EmitExpressionStatement`/`TryEmitAssignmentStatement` lowering (a superset
  of profiling's inline assignment-discard); combined profiling's member-load null-guard with the
  correct `memberOwnerType`.
- `Program.cs`: preserved systems-language's `--systems` template flag on top of profiling's
  `GetFirstPositionalArg` refactor.
- `Program.Backends.cs`: dropped profiling's now-dead `ValidateStrictLintDiagnostics` (systems-language
  moved strict-lint into the compiler via `CompileToIlAssembly(validateStrictLint: true)`).
- `CompilationStubEmitter.cs`, `Analyzer.cs`, `memory/README.md`, `runTest.ts`: additive.

### Limitation found + principled fix: TokenType ordinal coupling

**Symptom:** After a clean (compiling) merge, the full gate hit **63 failures** — formatting gate,
unit tests, example builds, IL verification — all braced N# source failing to parse with
"Unexpected token newline in expression."

**Root cause:** The systems-language line inserted six token types (`Lifetime`, then
`Alloc`/`Allow`/`Stackalloc`/`Unsafe`/`Scoped`) into the **middle** of the `TokenType` enum. The
production-routed dogfood kernel `ParserTokenCompactionIndicesInto`
(`src/NSharpLang.Compiler.Dogfood/CompilerServices/LexerTokenKindScanner.nl`) — reached from the
`Parser` constructor via `NSharpCompilerDogfoodAdapter.TryCompactParserTokens` — filters newline
tokens by the **hard-coded integer ordinal 136**. The insertions shifted `Newline` from 136 to 142,
so the kernel filtered the wrong token type and left stray newlines in the parser's token stream.
This is the dogfood kernels' ordinal-coupling fragility surfacing through a real enum change.

**Fix (smallest principled change):** Restore the kernels' ordinal contract by appending the six new
token types at the **end** of `TokenType` (they are referenced only by name in C#, never by ordinal).
Documented the load-bearing ordering on the enum, and added an explicit guard test
`ParserTokenCompactionParityRespectsTokenTypeLayout` pinning `(int)TokenType.Newline == 136` so any
future mid-enum insertion fails loudly at the C# test layer instead of silently in production.

**Follow-up debt (tracked, not yet done):** The dogfood `TokenType`-ordinal kernels remain coupled to
a fixed enum layout. The more robust long-term fix is to pass ordinal constants (e.g. the newline
kind) into the kernels as data rather than baking them — decoupling kernels from enum layout entirely.
Deferred to avoid widening the binding/benchmark/test surface during consolidation; the guard test +
enum comment prevent silent recurrence in the meantime.

**Verification:** `format --project examples --check` → "All files are properly formatted"; targeted
re-run of the previously-failing classes (`CompilerDogfoodProjectTests`, `StructCopyEliminationTests`,
`AnalyzerBindingMapTests`) → 42/42 pass.

### Limitation found + principled fix: short-circuit `&&`/`||` codegen vs C#

**Symptom:** After the ordinal fix the full gate had exactly one remaining failure — the Systems
BenchmarkDotNet gate (`SystemsFastGateBenchmarks`), `HotResultCombinations` scenario, N# at
~1.01× the C# baseline (zero-tolerance gate; N# must be ≤ C#).

**Root cause (verified by emitted-IL diff vs pre-merge `84dda83`):** the merge correctly brought in
the dogfood branch's short-circuit `&&`/`||` lowering (commit `b4a873e "Fix IL primitive operator
semantics"`, with the `ILCompiler_LogicalOperatorsShortCircuit` test). Pre-merge systems-language
lowered `&&`/`||` **eagerly** (`clt; cgt; or; brfalse` — one branch) which is a *latent correctness
bug* (the right operand is always evaluated). The IL diff showed only `scanDigits`,
`scanAndChecksumDigits`, `copyDigits` changed — each a hot loop with `if value < 48 || value > 57`.
The materializing short-circuit helper (`EmitLogicalOr`) added `ldc.i4.0`/`ldc.i4.1`/`br`
boolean-materialization and a second branch; RyuJIT compiles the equivalent C# range check
(`value < 48 || value > 57`) to a single branch, so correct-but-two-branch N# lost by ~1–2%.

**Fix (compiler self-improvement — explicitly in scope):** added a short-circuiting
`EmitConditionBranch(condition, target, branchIfTrue)` used by `EmitIf`/`EmitWhile`/`EmitFor`. It
lowers `&&`/`||`/`!` to branches taken directly against the target labels (no boolean
materialization), and:
- **fuses** integer relational comparisons with their branch into one
  `blt`/`bgt`/`ble`/`bge`/`beq`/`bne.un` opcode (gated to integral operands, where the relational
  inverse is exact — no NaN/unordered hazard);
- **eagerly** evaluates `a && b`/`a || b` as `left; right; and/or; br` (a single branch) ONLY when
  both operands are provably pure and non-throwing (an integer comparison whose leaves are integer
  locals/params or integer/char literals) — observably identical to short-circuit but one branch
  instead of two, matching the JIT-folded C# shape.

Side-effecting operands (calls, member access, indexing, division) still short-circuit, so
`ILCompiler_LogicalOperatorsShortCircuit` and the operator-matrix/IL-shape suites pass (100/100 on
the targeted run). After the fix the emitted IL for the hot loops is *smaller* than pre-merge's, and
`HotResultCombinations` measures **0.99×** (N# faster), so the benchmark gate passes. This is a net
codegen quality improvement for every `if`/`while`/`for` condition in the language.

**Verification:** Systems BenchmarkDotNet gate passes (all 6 scenarios ≤ 1.00, HotResultCombinations
0.99); 100/100 targeted short-circuit/operator/control-flow tests pass. Full
`VSCODE_TESTS=skip ./scripts/test-all.sh --commit` re-run pending.

---

## 2026-06-05 — Lever 3 codegen: `array.Length` → `ldlen` for SZ arrays

**What:** `EmitMemberAccess`/`EmitMemberLoadValue` lowered `array.Length` on a single-dimension
zero-based array (`IsSZArray`) to a non-virtual `call Array.get_Length()`. Replaced with the canonical
`ldlen; conv.i4`. Strings, `Span<T>`, and multidimensional arrays are unaffected (not `IsSZArray`).

**Why (boundary-profiling Lever 3):** `ldlen` is the form the JIT's bounds-check elimination
pattern-matches, so an `array.Length`-bounded counted loop (`for i := 0; i < a.Length; i++ { a[i] }`)
now emits the same shape C# does and the JIT elides the `ldelem` bounds check.

**Evidence (direct micro-benchmark, 4096-int sum, 2M iterations, identical checksums):**

| N# array.Length form | N# / C# ratio | IL size (`sumArray`) |
|----------------------|---------------|----------------------|
| `call get_Length` (before) | 1.003× (slightly slower) | 33 B |
| `ldlen; conv.i4` (after)   | **0.999× (parity)** | 30 B |

Modest but real: moves the canonical counted array loop from marginally-slower to parity with C#,
meeting the "never slower than C#" bar, with smaller and canonical IL. 537 array/length/span/string/
loop tests pass; parity is guaranteed (same value). Benefits every `array.Length`-bounded loop,
including the array-heavy dogfood kernels.

## Bootstrap coverage

- **0%** — no compiler source is yet compiled by the N# compiler itself. The dogfood kernels are
  N#-authored compiler *services* compiled through the normal `NSharpLang.Sdk` path and bound via the
  `*DogfoodAdapter` delegate boundary; this is the pre-bootstrap stage. The endgame (per the boundary
  profiling doc) is removing those delegate boundaries via in-assembly N#-to-N# calls.

## Adapters (debt to shrink toward zero)

- `NSharpCompilerDogfoodAdapter`, `NSharpCodeIntelligenceDogfoodAdapter`,
  `NSharpPerformanceDogfoodAdapter`, `NSharpCliDogfoodAdapter` — all still present as temporary
  transition boundaries. None removed yet. Each routed kernel still crosses the ~1.2 ns
  delegate-dispatch + bounds-check floor documented in the boundary profiling doc.

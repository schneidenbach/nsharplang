# Roadmap to Done — N# self-host + Rust-class performance + language strategy

The standing execution plan. Work this top-to-bottom autonomously. It exists so there is never a "which next?"
question — only genuine architectural forks surface. Living evidence in
[`self-host-progress.md`](self-host-progress.md), [`columnar-pipeline.md`](columnar-pipeline.md),
[`systems-vs-native.md`](systems-vs-native.md).

## Operating contract (how this gets executed)

- Execute this roadmap top-to-bottom, **one verified + committed slice at a time**, without pausing for
  approval between slices. After a slice lands, take the next item automatically.
- Every slice: build → correctness/parity test → adversarial-verify (a read-only workflow) for any new
  non-trivial logic → `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` is GREEN → commit. **No shortcuts,
  no faked parity, no weakened tests, no regressions.** A failed gate that is a known thermal flake
  (HotResultCombinations ≈1.0×, systems compile/build-perf tests) is re-run cool & serially, not worked around.
- **Decompose large efforts into verified sub-slices** (e.g. vectorization codegen = detection → single-lane
  emission → unrolling → widen types → default-on). Never defer a large item wholesale to "a future session."
- **Surface to the user ONLY for:** (a) a genuine architectural fork this roadmap does not pre-decide where a
  wrong choice wastes major work; (b) a hard blocker (a decision/credential only they can give); (c) the
  roadmap is complete. Progress itself is reported by the commits + the progress log, not by stopping.
- **Hands-off mode:** the user runs `/loop` so I am re-invoked to keep taking the next slice while they are
  away. Otherwise I continue turn-to-turn. Either way the contract is the same.
- Keep this doc current: check items off, add discovered work, record the real numbers.

## Definition of DONE

1. **C#-free:** the compiler, compiler-service, and CLI command logic run on the N# columnar pipeline
   end-to-end; the C# binder/analyzer/codegen and the `*DogfoodAdapter` bridges are deleted. Only the CLR/BCL
   host boundary + bootstrap loader remain in C# (AGENTS.md-permitted).
2. **Rust-class perf:** systems-N# generated code is within ~2× of Rust/C on the vectorizable hot kernels
   (checksum-sum, count-ascii) and ties-or-better elsewhere; the SystemsFastGate never-regress bar holds.
3. **Top-of-class language + tooling:** general-purpose and systems surfaces are feature-complete for the
   corpus + examples; LSP/CLI run on the columnar pipeline; docs current.

## End deliverable — what "done" ships

A dynamic workflow spawns many short-lived `nlc` invocations; cold-start latency and reliability dominate.
The finished product is:
1. **AOT single-binary `nlc`** — `PublishAot` the CLI (and keep it AOT-clean as subsystems migrate; the
   systems AOT/readiness reporting helps here). Eliminates JIT warmup → millisecond cold starts.
2. **LLM-first CLI** — the versioned `nlc query` JSON toolchain: stable, schema-versioned JSON for
   check/fix/query/diagnostics so an agent has the same power as VS Code.
3. **Daemon/fast-path** for repeated invocations in one workflow (warm compiler, incremental).
4. **Deterministic, hermetic builds** (project.yml-first, single SDK reference) so a workflow can
   `nlc new`/`build`/`run`/`test` with no environment surprises.

The fast self-hosted compiler (Phase S) + AOT packaging is what makes N# genuinely snappy for agents.

## Phase S — Self-host (eliminate C# reliance)

- [x] Parser kernels parse 100% of own systems source (slices 1–24); 2.4× faster than C# unmaterialized
- [x] Routing-via-materialization proven a dead end; columnar pipeline chosen (slices 25–27)
- [x] Stage 1 — columnar declared-symbol model
- [x] Stage 2 — columnar name resolution
- [ ] **Stage 3 — columnar type checking.** Expression type inference over the columnar + symbol tables for
      the pure-N# surface (literals, locals/params, function returns, operators, index, cast, new); BCL
      member/call types via a typed host boundary (reflection — AGENTS.md-permitted). Parity vs the C# binder's
      inferred types on the corpus.
- [x] Stage 3 — columnar type checking (expression inference; reviewed against the real binder; binder/output
      parity deferred to stages 4-5). Surfaced two C# binder ECMA gaps (see reconciliation item below).
- [ ] **Binder reconciliation** (correctness improvement surfaced by stage-3 adversarial review): the C#
      binder (Analyzer.cs) does NOT concretely type bitwise binary ops (&,|,^,<<,>> → Unknown) nor apply
      numeric promotion to unary -/~ (ECMA §12.4 gaps). The columnar inferer currently MATCHES the binder
      (behavior-preserving). Decide + do: fix the binder to ECMA-correct (then update ColumnarTypeLattice to
      the promoted types and re-verify), or keep matching. Low-risk localized binder change; gate for regress.
- [x] **Stage 3b — columnar diagnostics** (pure-structural: definite-return, unreachable-after-terminal,
      unused-local). Parity vs the C# analyzer. **COMPLETE** — all three sub-slices below landed, each
      parity-gated vs a C#-AST mirror on hand-built cases + the full 32-file corpus and adversarially verified.
      - [x] **3b-i definite-return (NL305)** — `ColumnarDiagnosticsPass.StatementAlwaysReturns` is the columnar
        subset of `Analyzer.StatementAlwaysReturns` (Return exits; Block exits if any stmt exits; If exits only
        with an else where both branches exit; Break/Continue/ExprStmt/VarDecl/While non-exiting). The kernel
        refuses throw/switch/try/wrapper forms, so the subset is faithful by construction; omitted return type =
        void (matches `Analyzer.cs:621`). Async/generator functions carry the `isAsyncUnitTask`/`isIterator`
        exemptions (BCL task-type knowledge the pass can't model) → the adapter DECLINES those sources to the C#
        analyzer (corpus has none, so zero coverage loss). Parity-tested vs a C#-AST mirror + exact expected
        diagnostics on 7 hand-built cases, and on the full 32-file dogfood corpus (mirror parity + ZERO
        false-positive NL305 on valid self-host source). Adversarially verified (the review caught the async
        unit-task divergence; fixed + regression-tested).
      - [x] **3b-ii unreachable-after-terminal (NL312)** — `ColumnarDiagnosticsPass.CollectUnreachable` mirrors
        `Analyzer.AnalyzeStatements`: within a statement list, once a statement always exits, the immediately
        following statement is reported unreachable (once, then the list is skipped), recursing into nested
        blocks / if-branches / while-bodies exactly as `AnalyzeStatement` does. Reported position is the
        statement's `line:col`, resolved from the tokenizer's own per-token line/col (a byte-offset→position map
        in the adapter) — empirically equal to the AST `Statement.Line/Column` (the exact-parity test would fail
        otherwise). Parity vs a C#-AST mirror on 6 hand-built cases (incl. only-first-reported, nested, and the
        unreachable-before-missing-return ordering) + zero unreachable on the 32-file corpus. Adversarially
        verified (clean — no divergence).
      - [x] **3b-iii unused-local (NL001)** — `ColumnarDiagnosticsPass.CollectUnusedLocals` walks the body in
        SOURCE ORDER, faithful to the Linter's time-/scope-ordered NL001 (a first naive "global" attempt was
        reverted — see `fe61aa51`). The adapter processes functions in source order sharing one `usedNames` set
        that accumulates every identifier use (the file-level `_usedVariables` analog), seeded with each
        function's params and NEVER cleared between functions; each Block's `:=` locals are checked at the
        Block's exit against `usedNames` AS OF THEN — so a use after the block closes (later sibling block / later
        function) does NOT suppress, while an earlier use does. Discards (`_`/`_`-prefixed) exempt; params always
        used; assignment-target counts as a use; interpolated strings decline upstream (kernel refuses `$"..."`).
        Parity vs a C#-AST mirror reproducing the exact ordering on 9 hand-built cases (both ordering directions,
        nesting, assignment, discard) + the full 32-file corpus. Adversarially verified (the prior global rule's
        divergence is fixed; APPROVE, clean).
- [~] **Stage 4 — columnar codegen.** Emit IL directly from the columnar + resolved tables for the systems
      subset; compile a trivial then a real dogfood function with NO C# AST. Parity: emitted IL runs identically
      to the C# path (same outputs); IL-verification gate green.
      **SCOPED (read-only Explore workflow, 2026-06-07).** Emission seam: REUSE the existing
      `ILGenerator` (`ILCompiler._currentIL`) — it is already AST-decoupled — via a SEPARATE columnar dispatcher
      (`EmitColumnarBody`/`EmitColumnarExpression`) that switches on columnar node kinds and calls the same
      low-level emit helpers (`EmitLoadArgument` ~9590, `EmitInt32Constant`, `_currentIL.Emit(OpCodes.Add)`,
      `_currentIL.Emit(OpCodes.Ret)`), populating the context dicts (`_parameters`/`_parameterTypes`/
      `_currentReturnType`/`_locals`) from columnar data — no AST materialized. Key methods: `Compile` ~10108,
      `DeclareFunction` ~10480, `EmitFunctionBody` ~10783, `EmitExpression` ~13573, `EmitBinaryExpression` ~15436,
      `EmitReturn` ~11858. Data is ~80% sufficient from stages 1–3; gaps for the trivial case: CLR `Type` from a
      canonical string (hardcode builtins / reuse `ResolveType` ~8000), param ordinal (= index in the signature),
      local slots (assign in source order at `:=`); calls/method-tokens (`_methods` ~10593) and `External` types
      deferred. Parity gate: route columnar-emitted method → `Assembly.Load` → invoke vs the C# path oracle (same
      pattern as `NSharpCompiledMethod.Bind`), assert equal across inputs + ilverify green. Decompose:
      - [x] **4-spike DONE** — `Columnar/ColumnarIlEmitter.cs` + adapter `TryEmitColumnarFunction` emit a real
        one-method assembly whose body IL comes straight from the columnar tables; the test LOADS + INVOKES it.
        Proven end-to-end for INT-ONLY top-level funcs: param load, int literal, paren, and int `+`/`-`/`*`
        binary (incl. nested left-assoc + multi-param) — `identity(42)==42`, `add(2,3)==5`, `poly(3,4,5)==7`,
        `(a+b)*b`, `a-b-c`. Folds in 4a (binary) + 4f (int literals) for the int subset. Self-contained
        (`PersistedAssemblyBuilder.Save` → `Assembly.Load`), no `ILCompiler` changes, declines every unsupported
        form (locals, if/while, calls, non-int, value-less return, multi-func) → C# path unaffected.
        Adversarially verified (decline-safety strong; the one edge — value-less int return — fixed + tested).
      - [ ] 4b full canonical→CLR type resolution (beyond int; reuse `ResolveType`) · [ ] 4c unify into a real
        dispatcher + the parity-vs-C#-path test harness · [ ] 4d locals (`x := a+b; return x`) · [ ] 4e unary ·
        [ ] 4g if/else · [ ] 4h while · [ ] 4i calls · [ ] 4j route via `DeclareFunction` (flagged) + benchmark
        never-slower · [ ] 4k C# fallback for declined forms + gate closure.
- [ ] **Stage 5 — end-to-end route.** Compile the dogfood corpus through the full columnar pipeline with no
      internal materialization; behind a flag, then default-on once never-slower + parity proven end-to-end.
- [ ] **Stage 6 — delete C#.** Remove the C# binder/analyzer/codegen paths the columnar pipeline replaces;
      shrink/remove the `*DogfoodAdapter` bridges. Track C# LOC deleted.
- [ ] **Coverage expansion** (pulled in as stages need them): class/struct/enum/record/interface/union decls
      + members; for/foreach/let/match/lambdas/generics/tuples/is-as/range/`new[size]`/`new{init}`. Each is a
      parser-kernel form added + parity-gated, then threaded through stages 1–4.
- **Deferred parity findings** (carried over from the retired dogfood-parity roadmap; fix as the parser
  kernel / inferer work lands): **M6** — `test`/`setup`/`teardown` are contextual keywords the lexer emits
  as identifiers, so a `*.tests.nl` file with no top-level `func` parses as zero declarations (repro:
  `examples/16-task-cli/Program.tests.nl`); detect-and-fall-back or parse them. **M8** — the columnar
  inferer keys function return types by name only, so top-level overloads collide (last wins); key by
  canonical signature (`ColumnarFunctionSymbol.Signature()`).

## Phase P — Rust-class performance

- [x] Ceiling measured: unrolled `Vector<int>` = 4.5× over scalar (checksum-sum 8.8× → ~2× behind native)
- [x] **P1 — auto-vectorize counted reductions** (the `while`-form `i:=0; while i<len { acc=acc+a[i]; i=i+1 }`).
      Sub-slices: [x] (a) pattern detection (`ReductionLoopShape.TryMatch` + 11 tests, no emission change);
      [x] (b) lowering to the unrolled `Vector<int>` SIMD helper (`SimdReductions.SumInt32` in NSharpLang.Runtime;
      `ILCompiler.TryEmitVectorizedReduction` hooks EmitWhile), behind an off-by-default thread-local flag, with
      run(vectorized)==run(scalar) across lengths incl. tails + post-loop index = max(index,bound) + the
      optimization-fires shape check (27 tests). Adversarial review caught + fixed a real divergence: bounds are
      now restricted to provably side-effect-free int (int local/param, int literal, array.Length=pure ldlen)
      and evaluated once — `.Count`/custom `.Length` no longer vectorize. Already unrolled to 4 accumulators
      (the helper). [x] (c) [merged into (b)]; [x] (e) DEFAULT-ON (env NSHARP_VECTORIZE_REDUCTIONS=0 to opt
      out) — never-regress proven: the full 3466-test suite + dogfood + examples + IL-verification + the
      SystemsFastGate benchmark all pass with vectorization active. [x] (d) widen element types: INTEGER ONLY
      (long/uint/ulong — wrapping add is associative); float/double do NOT vectorize (FP reassociation is not
      value-preserving) — they fall back to scalar. DONE: `SumInt64`/`SumUInt32`/`SumUInt64` helpers +
      element-type dispatch in the emitter (accumulator type must equal element type); 44 tests incl. wraparound.
      Adversarial review found+fixed two real divergences (both pre-existing in the int path): `int.MinValue`
      bound overflowing `end - step` (→ `if (end <= start) return`), and OOB throwing `ArgumentOutOfRangeException`
      instead of `IndexOutOfRangeException` (→ SIMD only over a provably in-bounds range).
      [x] (f) FOR-FORM: the vectorizer hooked only `EmitWhile`, but the benchmarks + idiomatic N# use `for`
      (probe: for-form emitted 0 SIMD calls vs while-form's 1 — the win was NOT reaching the benchmark). Now
      `ReductionLoopShape` matches `for i := s; i < n; i++ { acc = acc + a[i] }` (iterator increment, single-stmt
      body braced/braceless) and `EmitFor` emits the initializer then shares the while-form's emit core; terminal
      `index = max(s, n)` matches a counted for-loop's exit. 35 tests; adversarial review SAFE-TO-SHIP. **P1 COMPLETE
      (and now actually firing on idiomatic `for`-loops).**
      Scoping (workflow w8urlgage): hook EmitWhile (ILCompiler.cs:12401, _currentIL/_locals); Vector<int>
      Reflection.Emit feasible (RuntimeCalls.cs generic-binding patterns; N# already emits Vector<int> op IL);
      int wrapping add associative (reorder safe); mandatory scalar tail (Vector<int>.Count platform-varies).
      P1(b) APPROACH DECIDED (probe): RAW Reflection.Emit, NOT AST-lowering — N# supports `Vector<int>` +
      operators + `new Vector<int>(arr)` but NOT `Vector.Sum` (the non-generic `Vector` static class is
      "undefined variable"), so the horizontal sum must be emitted directly. Emit via reflection: ctor(int[],
      int), op_Addition, Vector.Sum<int> (MakeGenericMethod), Vector<int>.Count getter; zero vacc via
      ldloca+initobj; vector loop while i<=len-lanes; then acc += Vector.Sum(vacc); then the scalar tail.
      Behind an off-by-default flag; correctness test = run(vectorized) == run(scalar) across lengths incl.
      non-multiples of Count.
- [x] **P2 — range-predicate counts** (count-ascii) — packed compare + masked accumulate.
      [x] (a) detector `RangePredicateCountShape.TryMatch` (while/for, temp/inlined subject, inclusive range, unit
      counter increment; 19 accept/reject tests; no codegen change). [x] (b) masked-count helper
      `SimdReductions.CountInRangeInt32` (`Vector.GreaterThanOrEqual & Vector.LessThanOrEqual` → mask; `acc -= mask`;
      `Vector.Sum`; reuses P1's empty/OOB/overflow guards) + emitter hook (`TryEmitMatchedRangeCount` in
      EmitWhile/EmitFor) + parity tests (int[], while/for, temp/inlined, tails + inclusive boundaries) +
      adversarial review (no divergence). Fires for int[]/int counter+index/int side-effect-free bound+lo+hi only;
      non-int lo/hi or non-int[] array fall back to scalar. **P2 COMPLETE for int[].** [ ] (c) DEFERRED unless the
      corpus needs it: widen element types or generalize predicate operators (`>`/`<`, reversed operands).
- [x] **P-minmax — min/max conditional reductions** (min-max-delta — the 10.5× kernel, the LARGEST remaining
      native gap). min/max are associative + commutative integer reductions, so lane-wise `Vector.Min`/`Vector.Max`
      is value-preserving like P1's sum. [x] (a) detector `MinMaxReductionLoopShape.TryMatch` (while/for,
      temp/inlined subject, one OR two reductions in one body, reversed `min > value` operand order; 22
      accept/reject tests; no codegen change). [x] (b) lane-wise SIMD helpers `SimdReductions.MinInt32`/`MaxInt32`
      (seed-broadcast accumulators + horizontal fold + scalar tail; reuse P1's empty/OOB/overflow guards) + emitter
      hook (`TryEmitMatchedMinMaxReduction` in EmitWhile/EmitFor; one helper call per reduction, bound evaluated
      once, index unchanged between calls) + parity tests (for/while, temp/inlined, min-only, scalar≡vectorized
      across lengths incl. SIMD tails + int.MinValue/MaxValue extremes) + adversarial review (7 candidates, ALL
      adjudicated non-divergent — the one the judge flagged "real" rested on an impossible "concurrent array resize"
      premise: .NET `int[]` is fixed-length, `array.Length` immutable, and the cached-bound pattern is identical to
      the shipped/reviewed SumInt32/CountInRangeInt32). int[] only. [x] (c) FUSED single-pass
      `SimdReductions.MinMaxInt32` (loads each `Vector<int>` once, applies both `Vector.Min`+`Vector.Max`, returns
      `(min,max)`); routed via `TryGetMinMaxPair` for the `[1 min, 1 max]` body (ValueTuple return, `ldloca`+`ldfld`
      Item1→min/Item2→max); per-reduction path kept for min-only/max-only. **MEASURED — rigorous back-to-back, same
      machine (BDN, M4):** fused **262.5 ns @4096 = 0.168× = 5.94× faster than C#** (vs two-pass 453 ns/0.296×) →
      **1.73× faster than two-pass** → implied **~10.5× → ~1.77× behind native — BELOW the ~2× DONE bar, Rust-class**
      (at 64, two-pass was 1.303× = *slower* than C#; fused 0.768×). Decision rule honored (measured fused>two-pass
      before keeping). 69 MinMax tests; adversarially verified. **P-minmax (a,b,c) COMPLETE for int[]** — widen to
      long/uint/ulong only if the corpus needs it.
- [x] **P3 / P-ctrans — count-transitions, realized as VECTORIZATION** (the bigger win; the bounds-check-elision
      goal — removing the per-iteration indexed-load+branch tax — is subsumed by replacing the loop with a SIMD
      helper). count-transitions counts `i in [1,len)` where `a[i] != a[i-1]`; the loop carries `previous`, but
      passing it as the helper's seed makes the rewrite value-identical for ANY init (the first compare is
      `a[start]` vs the seed, the rest `a[i]` vs `a[i-1]`) — no non-local init analysis. [x] (a) detector
      `CountTransitionsShape` (for/while temp form; carry `previous=current` + `current!=previous` + unit counter
      increment; five distinct names; 17 accept/reject tests; no codegen change). [x] (b)
      `SimdReductions.CountTransitionsInt32(a, start, end, seedPrevious) -> (count, lastPrevious)` (first-vs-seed
      scalar, then SIMD shifted compare `~Vector.Equals`/`acc-=mask` over `[start+1,end)`, scalar tail; reads only
      `a[start..end-1]`, same empty/OOB guards) + emitter (`TryEmitMatchedCountTransitions`; ValueTuple `Item1`→
      count, `Item2`→previous restore, `index=max`) + 46 tests (parity incl. terminal previous; OOB; fallbacks) +
      adversarial review. **MEASURED:** N# **2.37× faster than C#** @4096 (1119.8→471.9 ns; was ~0.99× tied) →
      implied **~4.54× → ~1.9× behind native (Rust-class)**. **With this every vectorizable kernel is within ~2× of
      native; only rolling-hash (~1.5×, the latency-bound floor) remains, and it is not vectorizable.** int[] only.
- [x] **P4 — LLVM / NativeAOT backend evaluation** (decision doc): DONE 2026-06-07 →
      [`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md). **DECISION: defer the
      structural vectorizing backend (evidence-gated reopen, gates G1–G4).** Phase P's per-pattern `Vector<T>`
      emission already closed the 8.8–10.5× SIMD gap to ≤2.0× native (measured), so the structural backend's
      original prize is gone; the residual ~1.6–2× is latency-bound / small-input / scalar-scheduling, which
      NativeAOT (shares RyuJIT → no loop auto-vectorization) and the WASM-only experimental NativeAOT-LLVM do not
      cheaply fix. Split out: NativeAOT **image emission** is a separate, lower-risk CLI startup/size track
      (orthogonal to throughput), worth pursuing on its own merits — `nlc publish --aot` is analysis-only today.

## Phase T — Tooling + language strategy

- [ ] Route the columnar pipeline into the CLI (`nlc check`/`query`/`format`) and the LSP once stages 3–4 land
      (the LLM-first toolchain + IDE run on the fast N# path).
- [x] Re-run the systems-vs-native harness; keep `systems-vs-native.md` numbers current. **RIGOROUS
      single-machine re-run DONE (2026-06-07):** N#(vectorized)/C#/Rust/C all re-measured back-to-back on one
      cool, idle machine → the previously *implied* "~1.6–2× behind native" is now **MEASURED**: N#/best-native
      ≤2.02× at 4096 (checksum 2.02×, count-ascii 1.63×, count-transitions 1.97×, min-max-delta 1.67×,
      rolling-hash 1.62×, parse-eight-digits 1.80×); worst single cell 2.49× (min-max-delta @64, fixed
      SIMD/call overhead). Down from 8.24–10.5×. N# beats C#/RyuJIT ~2–6× on the vectorizable kernels. Full
      table + 2026-06-06 history in `systems-vs-native.md`.
- [ ] Broader general-purpose language features per `project_roadmap_2026q2` — lower priority until self-host +
      perf land, then resumed.

## Status cursor

Phase P **P1 is COMPLETE** (a–f: int/long/uint/ulong counted-reduction auto-vectorization, default-on, both
`while` and `for` forms — now firing on idiomatic/benchmark code — parity- and adversarially-verified, all
correctness bugs fixed). **P2 is COMPLETE for int[]** (a: detector; b: masked-SIMD count codegen, count-ascii,
adversarially verified). **P-minmax is COMPLETE for int[]** (a: detector; b: lane-wise Vector.Min/Vector.Max
codegen; c: FUSED single-pass MinMaxInt32 — MEASURED **5.94× faster than C#** at 4096 (1.73× over two-pass) →
**~1.77× behind native, Rust-class**, adversarially verified). **P3/P-ctrans is COMPLETE for int[]** (count-transitions
vectorized as a seeded shifted-compare count — MEASURED **2.37× faster than C#** @4096, ~1.9× behind native).
**EVERY vectorizable systems kernel is now Rust-class (within ~2× of native); only rolling-hash (~1.5×, the
latency-bound floor) is left, and it is not vectorizable.** Phase P's per-pattern auto-vectorization program is
essentially DONE. **Stage 3b — columnar diagnostics (Phase S) is COMPLETE**: 3b-i definite-return (NL305),
3b-ii unreachable-after-terminal (NL312), and 3b-iii unused-local (NL001) all landed in `ColumnarDiagnosticsPass`
(the columnar subset of `StatementAlwaysReturns`; `CollectUnreachable` mirroring `Analyzer.AnalyzeStatements`;
`CollectUnusedLocals` reproducing the Linter's time-/scope-ordered NL001) — async/generator sources decline to
C#; positions resolved from the tokenizer's own line/col matching the AST; parity vs a C#-AST mirror on
hand-built cases + the full 32-file corpus, each adversarially verified (the reviews caught + we fixed an async
unit-task divergence in 3b-i and a global-rule ordering divergence in 3b-iii). **Stage 4 — columnar codegen
is SCOPED** (read-only Explore workflow): reuse `ILCompiler._currentIL` via a separate columnar dispatcher, data
~80% sufficient from stages 1–3, decomposed into a spike + 4a–4k (see the Stage 4 item above). **The 4-spike
is DONE** — `ColumnarIlEmitter` emits a runnable one-method assembly straight from the columnar tables (proven
by load+invoke for int-only param/literal/paren/`+`/`-`/`*` functions), de-risking the emission seam; declines
everything else so the C# path is unaffected; adversarially verified. **Next: 4c (a real columnar dispatcher +
the parity-vs-C#-path harness) / 4d (locals) / 4g–4h (if/while), then 4j (route via `DeclareFunction`).** This
is the inflection point where C# begins to be deleted (Stages 5 route → 6 delete)
(columnar codegen) — where end-to-end binder/output parity (incl. the binder reconciliation item) is verified —
→ 5 (route) → 6 (delete C#). Phase T (route columnar into CLI/LSP) follows stages 3–4.

**Perf capstone (Track C) — COMPLETE 2026-06-07.** The rigorous single-machine cross-language re-run is done:
N#/best-native is now **MEASURED ≤2.0× at 4096** (worst cell 2.49×), down from 8.24–10.5× — `systems-vs-native.md`
leads with the authoritative post-vectorization table. **P4** (LLVM/NativeAOT backend) is **evaluated and
deferred** — decision doc [`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md):
the structural backend's order-of-magnitude prize was captured by Phase P's `Vector<T>` emission, so it stays
deferred behind evidence gates G1–G4; NativeAOT image emission is split out as a separate, lower-risk CLI
startup/size track. **Next: the self-host spine — Stage 3b (columnar diagnostics).**

The `systems-language-perf` worktree (P-minmax(c) + P3/P-ctrans) has been merged into `systems-language`
(commit `d2a447f3`).

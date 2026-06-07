# Roadmap to Done — N# self-host + Rust-class performance + language strategy

The standing execution plan. Work this top-to-bottom autonomously. It exists so there is never a "which next?"
question — only genuine architectural forks surface. Living evidence in
[`self-host-progress.md`](self-host-progress.md), [`columnar-pipeline.md`](columnar-pipeline.md),
[`systems-perf-backlog.md`](systems-perf-backlog.md).

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
- [ ] **Stage 3b — columnar diagnostics** (pure-structural: definite-return, unreachable-after-terminal,
      unused-local). Parity vs the C# analyzer.
- [ ] **Stage 4 — columnar codegen.** Emit IL directly from the columnar + resolved tables for the systems
      subset; compile a trivial then a real dogfood function with NO C# AST. Parity: emitted IL runs identically
      to the C# path (same outputs); IL-verification gate green.
- [ ] **Stage 5 — end-to-end route.** Compile the dogfood corpus through the full columnar pipeline with no
      internal materialization; behind a flag, then default-on once never-slower + parity proven end-to-end.
- [ ] **Stage 6 — delete C#.** Remove the C# binder/analyzer/codegen paths the columnar pipeline replaces;
      shrink/remove the `*DogfoodAdapter` bridges. Track C# LOC deleted.
- [ ] **Coverage expansion** (pulled in as stages need them): class/struct/enum/record/interface/union decls
      + members; for/foreach/let/match/lambdas/generics/tuples/is-as/range/`new[size]`/`new{init}`. Each is a
      parser-kernel form added + parity-gated, then threaded through stages 1–4.

## Phase P — Rust-class performance

- [x] Ceiling measured: unrolled `Vector<int>` = 4.5× over scalar (checksum-sum 8.8× → ~2× behind native)
- [ ] **P1 — auto-vectorize counted reductions** (the `while`-form `i:=0; while i<len { acc=acc+a[i]; i=i+1 }`).
      Sub-slices: [x] (a) pattern detection only (`ReductionLoopShape.TryMatch` + 11 tests, no emission change);
      (b) `Vector<int>` IL emission, single accumulator + scalar tail, behind a flag, parity (vectorized ==
      scalar on randomized inputs) + SystemsFastGate bench; (c) unroll to ≥4 independent accumulators;
      (d) widen element types (long/float/double); (e) default-on once never-regress proven.
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
- [ ] **P2 — range-predicate counts** (count-ascii) — same staged approach (packed compare + masked accumulate).
- [ ] **P3 — bounds-check elision** for proven-in-range counted loops (count-transitions's size-scaling tax).
- [ ] **P4 — LLVM / NativeAOT backend evaluation** (design workflow) once A-pattern wins plateau — the
      long-pole bet for broad vectorizable parity. Decide build-vs-not from P1–P3 results.

## Phase T — Tooling + language strategy

- [ ] Route the columnar pipeline into the CLI (`nlc check`/`query`/`format`) and the LSP once stages 3–4 land
      (the LLM-first toolchain + IDE run on the fast N# path).
- [ ] Re-run the systems-vs-native harness after each Phase-P win; keep `systems-vs-native.md` numbers current.
- [ ] Broader general-purpose language features per `project_roadmap_2026q2` — lower priority until self-host +
      perf land, then resumed.

## Status cursor

Next up: **Stage 3b — columnar diagnostics** (Phase S) and/or **P1 (a) — vectorization pattern detection**
(Phase P, user-prioritized Rust bar). Then Stage 4 (codegen) — where end-to-end binder/output parity (incl.
the binder reconciliation item) is verified. Phase T follows stages 3–4.

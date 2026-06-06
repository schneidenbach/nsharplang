# N# Self-Host & Speed Roadmap

**Status:** Strategic plan. Written 2026-06-05 after consolidating the dogfood work onto
`systems-language`. Grounds the path from today's state to the `goal.md` Definition of Done plus the
end deliverable: **a fast, complete N# usable by dynamic Claude workflows.**

Companion docs: [`compiler-dogfood-rewrite.md`](compiler-dogfood-rewrite.md) (methodology/evidence),
[`compiler-dogfood-boundary-profiling.md`](compiler-dogfood-boundary-profiling.md) (the decisive perf
finding), [`compiler-benchmark-metrics.md`](compiler-benchmark-metrics.md) (numbers),
[`systems-nsharp.md`](systems-nsharp.md) (systems-language spec), and
[`self-host-progress.md`](self-host-progress.md) (running log).

## Where we are (measured)

> **Update 2026-06-06 — Phase 1 lexer correctness COMPLETE.** The N# lexer kernels
> (`LexerTokenKindScanner.nl`) now reach full feature parity with the C# production lexer, verified by
> targeted parity tests + adversarial differential-fuzz reviews and committed across six slices:
> indentation-brace insertion, systems keyword recognition (`alloc`/`allow`/`stackalloc`/`unsafe`/
> `scoped`), lifetime tokens (`'a` with the `<`/`,`/`scoped`/`returns` context lookback), Unicode
> character classification (`char.IsWhiteSpace`/`IsLetter`/`IsLetterOrDigit`/`IsDigit` — confirmed to
> compile in the dogfood kernel), the `'\<CR>` char-literal edge, malformed-number `Unknown` tokens,
> and comment-trivia collection (`CommentsInto` vs `Lexer.Comments`). Token kind, position
> (start/line/column), value length, indentation, and comments all match `Lexer.Tokenize()`; token-text
> is host-derivable. See `self-host-progress.md` for per-slice evidence.
>
> **What this does and does NOT do:** it proves the lexer CAN be N# and closes the Phase 0 language-gap
> audit for the lexer (no compiler change was needed — today's N# + BCL interop expresses the whole
> lexer). It does NOT delete a bridge: these kernels are still array-of-primitive services reached
> through the `*DogfoodAdapter` delegate boundary. **Deleting the lexer bridge requires Phase 2/3** — an
> N#-native `Token`/`TokenStream` plus an in-assembly N#→N# consumer (the parser) so the call inlines.
> That subsystem migration (parser → N#, consuming N# tokens directly) is the next major phase and is
> where real Definition-of-Done progress (bridge deletion, then bootstrap) happens. The gate is
> reliable when run on a cool, idle machine (its marginal `HotResultCombinations` benchmark + cold-start
> `ProcessState` tests are load/thermal-sensitive — see `self-host-progress.md`).

- **Compiler:** ~97K LOC of C#. Lexer → Parser → Binder/Analyzer → ILCompiler (Reflection.Emit) → CLI.
- **Bridge code:** 4 `*DogfoodAdapter` types, **18 `Delegate.CreateDelegate` boundaries** into the
  separately-loaded `NSharpLang.Compiler.Dogfood.dll`, called from ~10 production sites
  (Parser, Formatter, ProjectFile, Analyzer, CodeIntelligenceService, MultiFileCompiler, …).
- **N# we already have:** 27 `.nl` kernels (array-of-primitive compiler-service slices); 3 routed to
  production (formatter import ordering, ProjectFile filtering, IL overload selection).
- **Codegen quality:** recent wins — short-circuit `&&`/`||` with comparison fusion, `array.Length`→
  `ldlen`; canonical counted array loops now match C# (BCE fires). Pinned by IL-shape tests.
- **AOT/startup:** none. The CLI is a normal framework-dependent build → JIT warmup on every cold
  invocation. This is the single biggest blocker for "used by dynamic Claude workflows."

## The one architectural truth that shapes everything

Per the boundary-profiling doc: the `*DogfoodAdapter` delegate boundary is a **fixed ~1.2 ns/call,
un-inlinable** floor, because the kernel lives in a late-loaded assembly reached through an open
delegate. **Adding kernels behind adapters can never remove the bridge** — it only adds more bridges.
A bridge is deleted only when its *caller* is also N#, so the call is in-assembly and the JIT inlines.

Therefore the spine of this roadmap is **incremental whole-subsystem migration to N#**: take one
subsystem, give it an N#-native representation (not "C# computes arrays → N# kernel → C#
materializes"), compile it with the N# compiler, route production to it, and **delete its adapter**.
Repeat until the compiler compiles itself (bootstrap) and the adapters are gone.

## Critical path (sequenced)

### Phase 0 — Language-completeness audit (gate for everything) — DO FIRST
The compiler is written in rich C# (classes, inheritance, generics, `Dictionary`, pattern matching,
records, nullable, LINQ, `Reflection.Emit`). N# must express all of it (fast) before a subsystem can
move. Produce a concrete gap list by attempting to author the **lexer** in N# (see Phase 1) and
recording every construct N# can't yet compile. For each gap, per `goal.md` rule 5, implement the
smallest principled language/compiler change with tests+benchmarks — do **not** work around it.
Known likely gaps to confirm: N#-native growable collections / hash maps (or a sanctioned BCL
`List`/`Dictionary` interop boundary), rich enum/union modelling of token & AST nodes, string slicing
without allocation (systems `Span`/pooling), and a sanctioned `Reflection.Emit` host boundary for the
back end.

### Phase 1 — Beachhead subsystem: the Lexer (first bridge truly deleted)
The lexer is the ideal first whole-subsystem migration: self-contained (`string` → tokens), extremely
hot, no `Reflection.Emit`, and we already have token-kind/metadata scanner kernels. Steps:
1. Define N#-native `Token`/`TokenStream` (systems representation: compact, pooled, zero-alloc).
2. Port the full lexer (trivia, indentation tokens, diagnostics, positions) to N#, not just scanning.
3. Compile it through the normal `NSharpLang.Sdk` path into an N#-owned lexer assembly.
4. Route production tokenization to it; assert token-sequence + diagnostic parity against the C# lexer
   on the whole corpus; benchmark whole-file tokenization (must be never-slower, dramatically faster
   on large files).
5. **Delete** the lexer-related adapter surface and the C# lexer once parity holds.
This proves the migration pattern end-to-end and removes the first real bridge.

### Phase 2 — In-assembly N#-to-N# call path (the boundary-removal mechanism)
Prototype Lever 2 from the boundary-profiling doc: a call path where one N# function calls another
**in the same emitted assembly** (no `Delegate.CreateDelegate`), so the JIT inlines and the ~0.7 ns
dispatch disappears. Validate with the declared-type-lookup kernel decomposition benchmark: confirm
only the ~0.5 ns codegen gap remains, then close that with continued codegen work (bounds-check
elision is largely handled for the canonical shapes; extend to the caller-owned-buffer kernels by
hoisting a single `count <= buf.Length` precheck so the JIT can elide per-element checks). As this
lands, the per-subsystem adapters collapse toward zero.

### Phase 3 — Migrate the remaining subsystems, deleting each adapter
Order by tractability and bridge density: **Source-text/line-map → Parser → Binder/Semantic model →
Analyzer/diagnostics → IL emitter (over a `Reflection.Emit` host boundary) → CLI command logic.**
Each step: N#-native representation → N# implementation → parity + benchmark gate → route → delete the
adapter + dead C#. `NSharpCodeIntelligenceDogfoodAdapter`, `NSharpPerformanceDogfoodAdapter`,
`NSharpCliDogfoodAdapter`, and finally `NSharpCompilerDogfoodAdapter` shrink to nothing.

### Phase 4 — Bootstrap milestone
The N# compiler compiles its own N# sources into the working compiler; the result passes the **full
test suite + ECMA-335 IL verification**, and whole-project compile time is dramatically faster than the
current C# compiler. Stage it: compile a growing subset of the compiler's own N# each iteration and
assert IL/behavior parity; expand to full self-host. This is the `goal.md` Definition of Done.

## Parallel track — Systems-language: complete + super fast

Per `systems-nsharp.md`, drive the systems v1 spec to completion and zero-overhead:
- Finish the spec surface: `Result<T,E>`, restricted `unsafe`, ref/lifetime safety, fixed-capacity &
  pooled collections, stackalloc/spans, AOT/readiness reporting, hot-path cost visibility (HotSummary).
- Enforce zero-overhead with the existing **zero-tolerance** Systems BenchmarkDotNet gate (N# mean ≤ C#
  on every scenario) — already catches regressions; expand scenario coverage as features land.
- Keep emitting verifiable IL (the IL-verification gate) and growing the proof corpus.
The systems features are *also* what makes the migrated compiler fast (pooled token/AST storage,
zero-copy string handling, `Result` error paths) — the two tracks reinforce each other.

## End deliverable — "used by dynamic Claude workflows"

A dynamic workflow spawns many short-lived `nlc` invocations; cold-start latency and reliability
dominate. Requirements:
1. **AOT single-binary `nlc`** — `PublishAot` the CLI (and keep it AOT-clean as subsystems migrate; the
   systems AOT/readiness reporting helps here). Eliminates JIT warmup → millisecond cold starts.
2. **LLM-first CLI** — the versioned `nlc query` JSON toolchain (already an AGENTS.md goal): stable,
   schema-versioned JSON for check/fix/query/diagnostics so an agent has the same power as VS Code.
3. **Daemon/fast-path** for repeated invocations in one workflow (warm compiler, incremental).
4. **Deterministic, hermetic builds** (project.yml-first, single SDK reference) so a workflow can
   `nlc new`/`build`/`run`/`test` with no environment surprises.
The fast self-hosted compiler (Phase 4) + AOT packaging is what makes N# genuinely snappy for agents.

## Speed, concretely (three axes)

- **Compile time:** comes from Phase 4 (fast N# compiler) + systems pooling/zero-copy in the compiler.
- **Emitted-code speed:** ongoing codegen quality (BCE done for canonical loops; extend to buffer
  kernels; keep matching/beating C# under the benchmark gate).
- **Startup:** AOT (end-deliverable item 1) — the dominant factor for dynamic workflows.

## Immediate next step (recommended)

Begin **Phase 0+1 together**: attempt the N# lexer port, using it to drive out the concrete
language-gap list. The first verified+committed slice is the N#-native `Token`/`TokenStream`
representation plus a tokenizer that reaches parity on a first corpus, with each language gap found
either closed (small principled compiler change + tests) or documented in `self-host-progress.md`.
This is the smallest step that (a) deletes a real bridge, (b) proves the whole-subsystem pattern, and
(c) surfaces the true scope of the language work ahead.

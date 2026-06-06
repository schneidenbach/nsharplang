# N# Self-Host — Dynamic Workflow Prompt

Paste the block below into a self-paced dynamic workflow (e.g. `/loop` with no interval). It is
designed to run autonomously, one verified+committed slice per iteration, and to keep going until the
Definition of Done — or to stop and document precisely when genuinely blocked.

---

You are an expert .NET/compiler engineer driving N# (a CLR language, "Go-esque" but with a richer
type system and a systems-programming tier) to **full self-hosting** and to a state where N# is fast
and complete enough to be used by dynamic Claude workflows.

Work on branch `systems-language` in this repo. NEVER work on `main`.

## Read first (ground yourself every cold start)
- `goal.md` — the mandate and Definition of Done.
- `AGENTS.md` — gate discipline, "NO SHORTCUTS", project.yml-first config, adapters-are-temporary.
- `docs/design/self-host-roadmap.md` — the sequenced plan (Phase 0 audit → Phase 1 lexer beachhead →
  Phase 2 in-assembly N#→N# call path → Phase 3 migrate parser/binder/IL-emit/CLI → Phase 4 bootstrap;
  plus the systems-language completion track and the AOT/LLM-first-CLI packaging for Claude workflows).
- `docs/design/self-host-progress.md` — the running log; READ THE NEWEST ENTRIES to see exactly where
  the last iteration stopped and what the next slice is.
- `docs/design/compiler-dogfood-boundary-profiling.md` — the decisive perf finding: the
  `*DogfoodAdapter` delegate boundary is a fixed, un-inlinable ~1.2 ns/call floor. You CANNOT delete
  bridge code by adding kernels — only by migrating a kernel's CALLER into N# so calls inline
  in-assembly. Whole-subsystem migration, not one-off kernels.
- `docs/design/compiler-dogfood-rewrite.md` and `compiler-benchmark-metrics.md` for prior evidence.

## The operating loop (one verified+committed slice per iteration)
1. **Pick the highest-leverage target** from the roadmap's current phase (start from the newest
   `self-host-progress.md` entry). Favor broad N#-owned subsystem representations over late one-off
   kernels. The spine is: migrate a subsystem to N# → route production to it → DELETE its adapter.
2. **Benchmark-first.** For any perf-sensitive change, write/extend a BenchmarkDotNet comparison
   (C# baseline + N# candidate, representative + large corpora, `[MemoryDiagnoser]`, parity asserted
   in `[GlobalSetup]`) BEFORE claiming a win. For codegen changes, diff emitted IL (compile the same
   source with the changed compiler vs. a clean checkout and compare method IL bytes).
3. **Implement in N#** (kernels/subsystems live under `src/NSharpLang.Compiler.Dogfood/CompilerServices/*.nl`,
   compiled through the normal `NSharpLang.Sdk` path). If N# can't yet express something fast/correct,
   do NOT work around it: document the precise language/runtime/compiler limitation in
   `self-host-progress.md` and make the smallest principled N#/compiler change to unblock it, with
   tests + benchmarks.
4. **Verify parity absolutely** — identical semantics, diagnostics, CLI JSON shape, formatting, and
   emitted IL. Add targeted parity tests (`tests/CompilerDogfoodProjectTests.cs` and friends).
5. **Route production only when never-slower AND faster on BOTH representative and large rows.** Never
   route on the large/generated row alone; a representative-row miss is a rejection. Record rejected
   evidence; don't delete it.
6. **Delete the now-redundant C# adapter/orchestration surface** and any dead C# the slice obsoletes.
7. **Gate, then commit.** Run `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` in the FOREGROUND;
   it MUST print "ALL TESTS PASSED" on a fresh isolated run. Then `git commit`. Commit messages end
   with `Co-Authored-By: Claude <noreply@anthropic.com>`.
8. **Update the docs** — append a `self-host-progress.md` entry with REAL numbers, adapters removed,
   bootstrap coverage %, and every limitation found + the principled fix. Keep the roadmap honest.
9. Periodically attempt a **bootstrap milestone**: compile a growing subset of the compiler's own N#
   sources with the N# compiler; assert IL/behavior parity; expand the subset over time.

## Hard rules (non-negotiable)
- No hacks, stubs, `NotImplemented`, faked parity, weakened/skipped tests, or "temporary" workarounds
  presented as done. Never hardcode benchmark inputs/outputs or cherry-pick best-cases.
- Correctness is absolute; performance bar is "AT LEAST as fast as C# on EVERY input size, never
  slower anywhere, and dramatically faster on representative AND large rows." "Allocates less" is not
  "faster."
- C# is allowed ONLY at genuine CLR/BCL host boundaries (process entry, BCL interop, MSBuild/LSP glue,
  and the `Reflection.Emit` back-end boundary). Adapters are temporary — shrink and delete them.
- Commit EARLY (never leave work uncommitted before a long command). Never regress the gate.
- Codex review is NOT required (the user lifted it). Substitute careful self-review of the diff
  against the correctness criteria, plus the full gate.

## Gotchas learned (don't relearn the hard way)
- `TokenType` member ORDER is load-bearing: the dogfood kernels bake enum ordinals (e.g. `Newline ==
  136`). APPEND new token types at the END of the enum; `ParserTokenCompactionParityRespectsTokenTypeLayout`
  pins it.
- The Systems BenchmarkDotNet gate (`scripts/benchmark-systems.sh`) is ZERO-TOLERANCE (N# mean ≤ C#
  on every scenario). It also fails with "Benchmark project names need to be unique" if extra git
  worktrees containing `NSharpLang.Benchmarks.csproj` exist under the repo root — keep worktrees out
  of `.claude/worktrees/`.
- Recent codegen wins already landed: short-circuit `&&`/`||` with integer comparison fusion;
  `array.Length`→`ldlen` (BCE-friendly). Canonical counted array loops now match C#. Don't regress
  these (IL-shape tests in `tests/PerfEvidence/ArithmeticAndLoopShapeTests.cs` pin them).

## Definition of Done
- Compiler core, compiler services, and CLI command logic implemented in N# (not C# orchestration).
- The N# compiler compiles its own source (bootstrap); the result passes the full test suite AND IL
  verification.
- Whole-project compile time dramatically faster than the current C# compiler; no migrated hot path
  slower than its C# predecessor on any input size.
- Remaining C# is only genuine host-boundary glue; the `*DogfoodAdapter` delegate boundaries are
  removed or reduced to true CLR/BCL interop.
- For dynamic Claude workflows: an AOT single-binary `nlc` with millisecond cold starts, a stable
  versioned `nlc query` JSON toolchain, and hermetic project.yml-first builds.
- `self-host-roadmap.md`, `self-host-progress.md`, `compiler-dogfood-rewrite.md`, and
  `compiler-benchmark-metrics.md` reflect the final state with evidence.

## Self-pacing (dynamic mode)
Do ONE verified+committed slice per iteration, then schedule the next. If a gate run is in flight,
wait for it before committing. Stop the loop only when the Definition of Done is met, or when you are
genuinely blocked — in which case document the precise blocker and the smallest principled unblock in
`self-host-progress.md` before stopping. Do not pause to ask for direction on work you can verify
yourself; just do the next slice.

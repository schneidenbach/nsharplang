GOAL: Make the N# compiler genuinely self-hosting — the compiler core, compiler services, and CLI/tooling logic implemented in N# itself, dramatically faster than today's C# implementation, with ZERO hacks, shortcuts, stubs, or workarounds. The existing C# `*DogfoodAdapter` code and any C# orchestration exist ONLY as temporary scaffolding to keep things working during the transition — your job is to migrate behind them and then remove them. This will take many hours and many committed, verified iterations. Do not stop until the Definition of Done is met or you are genuinely blocked and have documented exactly why.

=== READ FIRST (ground yourself) ===
- AGENTS.md (mandatory rules, gate discipline, "NO SHORTCUTS", adapter-is-temporary policy)
- docs/design/compiler-dogfood-rewrite.md (methodology, accepted/rejected evidence)
- docs/design/compiler-benchmark-metrics.md (current N#-vs-C# numbers)
- docs/design/compiler-dogfood-boundary-profiling.md (THE key perf finding — read carefully)

=== WHERE THINGS LIVE ===
- Canonical base branch with the dogfood scaffolding: `codex/compiler-dogfood-benchmarks`. Work on a dedicated long-lived branch off it (e.g. `nsharp-selfhost`), in your OWN git worktree. First consolidate the already-accepted slices (formatter import ordering, ProjectFile source filtering, ILCompiler overload selection) so you start from the most complete state.
- N# kernels: src/NSharpLang.Compiler.Dogfood/CompilerServices/*.nl
- Temporary C# transition boundaries to SHRINK TOWARD ZERO: NSharpCompilerDogfoodAdapter, NSharpCodeIntelligenceDogfoodAdapter, NSharpPerformanceDogfoodAdapter, NSharpCliDogfoodAdapter.
- Benchmarks: benchmarks/ (BenchmarkDotNet), resource wiring via DogfoodCompilerSources, N# binding via NSharpCompiledMethod.Bind.
- Parity tests: tests/CompilerDogfoodProjectTests.cs

=== KEY ARCHITECTURAL FINDING (must respect) ===
The adapters call N# kernels through non-inlinable reflection-bound delegates into a dynamically-loaded assembly. Measured cost: a fixed ~1.2ns per-call floor (~0.7ns delegate dispatch + ~0.5ns N# bounds-check codegen), flat across input size. Implications you must act on:
- The real high-performance endgame is N#-calling-N# DIRECTLY (in-assembly, inlinable), NOT adapter delegates. Treat every adapter delegate as debt to remove, not a destination.
- N# only beats C# when the C# baseline is wasteful (allocates/LINQ). When C# is already an optimal zero-alloc loop, the only way N# reaches parity is by removing the delegate boundary. So prefer broad N#-owned representations and whole-subsystem migration over one-off late kernel calls.
- Improve N# codegen quality (e.g. array bounds-check elision) so N# bodies match or beat equivalent C#. The compiler improving itself is IN SCOPE.

=== HARD RULES (non-negotiable) ===
1. No hacks, shortcuts, stubs, NotImplemented, faked parity, or "temporary" workarounds presented as done.
2. Correctness/parity is absolute: identical semantics, diagnostics, CLI JSON shape, formatting output, emitted IL, and public developer experience. Verify, don't assume.
3. Performance: every migrated path must be AT LEAST as fast as C# on EVERY input size (never slower anywhere) and dramatically faster on representative AND large rows. Benchmark-first. Never route on the large/generated row alone. "Allocates less" is NOT a substitute for "faster and correct."
4. C# is allowed ONLY at genuine CLR/BCL host boundaries (process entry, BCL interop, MSBuild/LSP/VS Code glue). Adapters are temporary — shrink and delete them; never grow them into permanent service layers.
5. If N# cannot yet express a fast/correct implementation, do NOT work around it. Document the precise language/runtime/compiler limitation and implement the smallest principled N#/compiler change that unblocks it, with tests + benchmarks.
6. Gate discipline: stay in your own worktree; commit EARLY (never leave work uncommitted before a long command); run `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` in the FOREGROUND before every commit and it MUST pass; run the `codex-code-review` skill (and `code-review`) on every code change and fix findings before committing.
7. Never declare a slice or the goal "done" without: a green fresh full gate, passing parity tests, recorded benchmark evidence, and (for self-host milestones) a successful bootstrap.

=== OPERATING LOOP (repeat continuously, one verified+committed slice at a time) ===
a. Pick the highest-leverage target: a hot C# compiler/service/CLI path still in C#, an adapter delegate to dissolve into a direct N#-to-N# path, or an N# codegen weakness blocking parity. Favor broad subsystem ownership over one-off kernels.
b. Benchmark-first: write/extend a BenchmarkDotNet class (C# baseline + N# candidate, representative + large corpora, [MemoryDiagnoser]); assert parity in [GlobalSetup].
c. Implement in N#. Route production only when never-slower AND faster on both rows. Else record rejected evidence and either improve the N#/codegen or remove the boundary so it inlines.
d. Delete the now-redundant C# adapter/orchestration surface. Remove dead C#.
e. Parity tests → codex review → full gate (foreground) → commit. Update the design docs + metrics summary with REAL numbers.
f. Periodically attempt a SELF-HOST BOOTSTRAP milestone: compile a growing subset of the compiler's own N# sources with the N# compiler; assert IL/behavior parity; expand the subset over time toward full bootstrap.

=== DEFINITION OF DONE ===
- Compiler core, compiler services, and CLI command logic are implemented in N# (not C# orchestration).
- The N# compiler compiles its own source (bootstrap); the result passes the full test suite AND IL verification.
- Whole-project compile time is dramatically faster than the current C# compiler, and NO migrated hot path is slower than its C# predecessor on any input size.
- Remaining C# is only genuine host-boundary glue; the `*DogfoodAdapter` delegate boundaries are removed or reduced to true CLR/BCL interop.
- docs/design/compiler-dogfood-rewrite.md, compiler-benchmark-metrics.md, and compiler-dogfood-boundary-profiling.md reflect the final state with evidence.

=== PROGRESS LOG & CADENCE ===
Maintain docs/design/self-host-progress.md: what migrated, benchmark deltas, adapters removed, bootstrap coverage %, and every language/compiler limitation found + the principled change made to resolve it. Commit after every verified slice. Never regress the gate.

=== ANTI-SHORTCUT CONTRACT ===
- Never disable, skip, weaken, or special-case tests to make them pass.
- Never hardcode benchmark inputs/outputs or cherry-pick unrealistic best-cases to fabricate a win.
- Never leave TODO stubs or "temporary" hacks and call it done.
- Never claim performance or completion without committed, reproducible evidence and a green fresh gate.
- When stuck, document precisely and make the smallest principled fix — never paper over it.
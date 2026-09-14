# Compiler-only ownership complete

Final verified source revision: `0cc84110a25c91afedba9471a6b20edc7427c152`.

The compiler-only objective is complete: preprocessing, lexing, parsing, binding, type checking,
semantic analysis, compiler diagnostics, reference/metadata resolution, lowering and code generation
have sole N# production owners. Canonical compiler assertions execute in N#. Replaced C# compiler
owners, validation decisions, callbacks and fallback implementations are removed.

The complete Analyzer, SystemsAnalyzer, input builder, emitter, MultiFileCompiler and reference
resolver acceptances remain valid. The final complete SDK EmitIlAssembly owner, actual-source
prerequisites and installed SDK verification are accepted in
[the SDK record](2026-09-09-complete-sdk-emit-task-ownership.md). The existing .NET and Cecil APIs
are ecosystem boundaries; no new metadata writer or runtime reimplementation was necessary.

## Final source and assertion audit

The production audit reviewed all 25 tracked C# files in Compiler, Build.Tasks, CLI and Playground,
plus direct editor callers. No surviving compiler-core C# owner was found. The remaining facades
and SDK property/item transport are documented in [the current boundary inventory](../../memory/architecture.md#non-nsharp-survivors).
Substantive editor document orchestration, command policy and the browser-only interpreter remain
separate backlog work, not compiler fallbacks. Stale reverse-dependency commentary was removed
without changing executable behavior.

All 23 remaining C# test files are accounted for: the three-file command/SDK crosswalk covers 49
methods and 181 assertion markers; the remaining 20-file sweep covers 328 declared methods and 1,237
markers. These are static census numbers, not executed assertion counts. Retained tests observe
distinct CLI/editor policy, package/ABI/process integration, synthetic LSP conversion, runtime or
test infrastructure. No in-scope compiler assertion remains C#-owned.

Review rejected one earlier false equivalence: a receiver-generic library regression did not
preserve the original executable fixture, total diagnostic cardinality or contiguous message.
`aa26a7695` restores the complete original case in N#: both files are byte-identical, the complete
error list contains exactly one NL103, and its message contains `instance call 'T.ToString'`.
The reduced regression remains useful independent coverage. Exact 1/1 and native 198/198 pass.
The define-flag compiler assertions were also migrated with exact project/source/raw-argument
bytes; their replaced C# assertions are deleted.

Evidence and SHA256:

- Production report: `/private/tmp/nsharp-multifile-assessment/final-production-csharp-boundary-20260909.md`,
  `b312de28a13060a84b66e4ac3ec8141707fbbaf9d522bdea6329c96e2f3d1a81`.
- Remaining 20-file inventory: `/private/tmp/nsharp-final-remaining-csharp-assertion-sweep-20260909/assertion-inventory-r1.json`,
  `29ac4025656e4b7093cc75a64f31850e75f9198a2ccf17e6669c2ca62387b871`.
- Corrected three-file crosswalk: `/private/tmp/nsharp-final-three-file-assertion-audit-20260909/remaining-three-files-crosswalk-r2-receiver-correction.md`,
  `c72e48b1c62c67e7b4e416c00f670a9420b746888375ae286890d4ae656b0979`.
- Exact receiver receipt: `/private/tmp/nsharp-receiver-generic-exact-canonical-20260909/final-receipt-r1.json`,
  `b4a73bde9aa398de43db5d710d2051d73e075df97ecc17512f383375d255931f`.

## Verification and cleanup

The final fresh `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate passes in 562s with no SDK
or package-path overrides: 399 C# integration tests, 8,017 N# compiler-service tests, all 56 native
project entries (including columnar 198), 12 throughput cells, templates/examples and 68 IL assemblies.
The isolated workspace is preserved. No whole-gate or per-step cached result was accepted.
The final audit sequence changes tests, documentation and a C# comment only; prior required IDE
gates and visual verification for compiler behavior remain accepted.

Final gate receipt: `/private/tmp/nsharp-sdk-owner-root-integration-20260909/final-canonical-gate-r1-receipt.json`,
SHA256 `346ebc7af6de7bbc8a7b43659c7b15287beae9377b423abbfe8f6461b6e76993`.
Gate log SHA256: `e36aaea2d506b7f2440969bf2343394f4297b54495b7560444a6eaef2420ce83`.
The installed SDK acceptance remains unchanged: 8,017 self-host tests, native 47/197/78/4/88/12,
unfiltered BSS 1,236/10,977, Compiler 5/58, Build.Tasks 3/33, sole-owner metadata and exact feed/cache
payload agreement. No SDK republish is needed for the final test/comment-only correction.

Cleanup retired 89 completed agent worktrees and 85 local branches across the two recorded cleanup
runs. Verified recovery bundles and draft archives are under `/Users/spencer/nsharp-worktree-archives`.
All implementation handoffs are integrated. Held backlog work and verification evidence snapshots
are preserved. CLI/editor features, runtime, NativeAOT and broader writer work remain in
[the separate backlog](../../tasks/BRANCH-BACKLOG.md); compiler-only completion does not close them.

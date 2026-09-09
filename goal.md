# Completed goal: sole N# compiler ownership

Accepted on 2026-09-09 after the final fresh gate at `0cc84110`.
[Completion, boundaries and evidence](systems-language-closeout/decodes/2026-09-09-compiler-only-ownership-complete.md).
The compiler-only objective is complete; broader branch work remains separately held.
The following contract remains the ownership requirement for future compiler changes.

The compiler scope is preprocessing, lexing, parsing, binding, type checking, semantic analysis,
compiler diagnostics, compiler reference/metadata resolution, lowering and code generation.
Every compiler decision and canonical compiler assertion in this scope must be N#-owned.

CLI, LSP/editor features, runtime reimplementation, NativeAOT and broader branch initiatives remain
in [the separate backlog](tasks/BRANCH-BACKLOG.md). Change SDK/tooling only when directly necessary
to build, integrate or verify this migration. Pursue a metadata writer only as a demonstrated
compiler-ownership dependency. This contract supersedes the earlier broader goal and tiny-slice
execution wording; accepted migrations and valid evidence remain accepted.

## Execution

Astra plans, reviews and integrates. Delegate bounded implementation to Sol Max or Terra Max.
Read [the queue](tasks/README.md) and [the live cursor](systems-language-closeout/STATUS.md).
Preserve in-flight work and finish active verification.

Select substantial coherent production areas: complete methods, classes or connected method groups,
including necessary helpers and state. Choose scope from actual dependencies and behavior, not line
counts or one-extraction-per-turn limits. Consider moving dependencies with their callers first.

For each area, identify the complete behavior and C# code to remove, implement its N# replacement
and canonical assertions, route production directly through N#, and delete the replaced C# decisions.
Preserve semantics, diagnostics, evaluation order and meaningful failure behavior. Add no C# compiler
behavior, tests, helpers, adapters, decision callbacks or fallbacks. N# must be the sole production owner.

Migrate canonical C# compiler assertions even when embedded in CLI, editor or SDK tests. Preserve
exact fixtures, state, diagnostic details and assertion cardinality; record their executed N# successors.
Delete replaced assertions and unused helpers. Retain only distinct integration or separately scoped
policy observations in mixed tests. Production migration alone is insufficient.

Prove capability blockers by compiling the actual proposed N# source. Implement necessary
prerequisites in N#, grouping related proven prerequisites into a coherent seed update when feasible.
Complete required verification before publishing a new SDK seed.

Use ./scripts/dev.sh and targeted tests during implementation. Reuse valid baseline evidence and
existing native coverage, adding focused regressions for real gaps. Commit coherent pieces as their
focused tests pass, then continue until the complete selected area is reviewed and integrated.
Run fresh product gates at AGENTS.md integration checkpoints before push, retaining required IDE
verification when a change affects IDE behavior. Do not stop at planning, scaffolding, a prerequisite
or a tiny extraction. Stage only owned files and preserve unrelated work.

After integration, retire completed worktrees and local branches only after checking active users,
unique commits and dirty/untracked work. Preserve necessary evidence and archive recoverable work
under the lifecycle in tasks/README.md. Keep held backlog work separate.

## Completion

- All in-scope compiler behavior is solely N#-owned.
- Canonical compiler assertions execute in N# without weakened or skipped coverage.
- Legacy compiler validation, decision callbacks and fallback ownership are removed.
- Every surviving non-N# integration boundary is mechanical and explicitly documented.
- Required compiler and integration checks pass, and verified commits are pushed.

Keep the goal open until every condition holds; a prerequisite or completed sub-area is not completion.

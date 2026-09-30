# 004 — Fixed-arity direct calls

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Execute exactly one vertical ownership slice. Do not stop at planning, scaffolding, prerequisites,
parity results, or a progress summary.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Existing C# may only shrink, route mechanically to N#, or be deleted.
- Implement all new behavior and canonical tests in N#.
- Before editing, identify the exact C# methods, branches, and assertions this slice will delete.
- N# must become the direct production owner. Leave no legacy fallback, shadow implementation,
  comparison route, or duplicated semantic authority for the migrated behavior.
- Tests migrate with the behavior; do not defer them to a later test-refactor task.
- If an N# or interop prerequisite is missing, implement it in N# and continue through production
  routing and C# deletion in this task. A prerequisite commit is not completion.
- If substantial N# code accumulates without a named C# deletion, recut the work inside this task
  and finish the smaller terminal slice. Do not commit an unused foundation.
- Follow `AGENTS.md`: use focused `./scripts/dev.sh` evidence, run the required integration or IDE
  gates, commit with an `Evidence:` block, update the queue ledger, perform any required clean SDK
  repin, stage selectively, and leave the working tree clean.
- Report only after the slice is complete. Include the commit, exact C# deletion, N# production and
  test delta, and gate evidence.

## Slice

Move fixed-arity, non-generic direct method calls into N# plans.

Cover exact static and instance call forms currently accepted without generic inference,
extension-method rewriting, params expansion, or ref/out arguments. N# owns receiver and argument
planning, candidate selection, exact signature identity, `call` versus `callvirt`, return type,
and stack validation.

Delete the matching C# call-binding, preflight, and emission decisions. Do not route an N#
rejection back to the old call binder. Keep generic, extension, params, and ref/out calls outside
this slice.

Add native tests for overload selection, static/instance distinction, value/reference receivers,
void/non-void returns, bad arity/types, inaccessible/abstract members, malformed handles,
rollback, recursive use, persisted execution, and IL verification.

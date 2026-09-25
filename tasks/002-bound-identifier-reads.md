# 002 — Bound identifier reads

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

Move bound identifier-value reads into the N# code-plan owner.

Scope this slice to ordinary parameters, locals, lifted locals, and current-instance facts used as
expression roots or recursive range/index children. Preserve exact shadowing, type,
argument/local ordinal, and definite-binding behavior.

N# must select, validate, and execute the exact load operation. Delete the matching C# emission
and preflight/type branches for these forms. An N# decline must never fall back to the deleted C#
behavior. Leave unrelated member access, calls, and operators explicitly outside this slice.

Add native N# valid, invalid, shadowing, malformed-fact, rollback, and persisted-execution tests.
Include recursive range/index consumption of each newly owned identifier form.

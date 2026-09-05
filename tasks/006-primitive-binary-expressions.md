# 006 — Primitive binary expressions

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

Move one coherent primitive binary-expression family into N# plans.

Cover arithmetic, comparison, and bitwise operations over the exact primitive types currently
accepted by the recursive range/index path. N# owns operand planning, numeric/type compatibility,
opcode selection, result type, checked/unchecked distinctions where applicable, and stack
validation.

Delete the corresponding C# binary emission and preflight/type decisions. Do not include
short-circuit Boolean control flow, coalescing, overloaded operators, or user conversions.

Add native tests for every admitted operator/type combination, mismatch rejection, overflow-mode
distinctions, malformed facts, rollback, recursive range/index use, persisted execution, and IL
verification.

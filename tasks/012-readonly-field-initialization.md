# 012 — Readonly-field initialization placement

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

Own readonly-field initialization placement in N#.

Use the `RecordsAndInterfaces.dll` `IL:InitOnly` failure as the product reproducer. N# must decide
which initialization runs directly in an instance constructor, which can use a helper, field
ordering, static versus instance ownership, and exact stores for readonly and mutable fields.

Delete the corresponding C# constructor/initializer placement and emission decisions and their
C# assertions. Add native tests for readonly/mutable, static/instance, primary and explicit
constructors, inheritance, invalid reassignment, persisted execution, and exact IL placement.
Run the product fixture and ILVerify.

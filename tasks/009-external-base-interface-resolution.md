# 009 — External base and interface resolution

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

Own external base and interface resolution in N#, using the generated Web API project's
`ControllerBase` decline as the primary product reproducer.

Reproduce the failure and identify the precise C# type/reference/binding decisions responsible.
N# must own ordered reference lookup, exact semantic identity, base-versus-interface
classification, accessibility, generic construction where already accepted, and the type handle
used by definition emission.

Route declaration emission directly through the N# result and delete the matching C# base-type
resolution decisions and assertions. Add native valid, invalid, ambiguous, missing-reference,
ref-only, and product-route tests. Build the generated Web API project and run ILVerify before
committing.

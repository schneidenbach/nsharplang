# 017 — Semantic analyzer ownership

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Execute exactly one vertical semantic slice in this goal turn. Do not attempt all of `Analyzer.cs`
at once, and do not stop at planning, scaffolding, prerequisites, parity results, or a progress
summary.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Existing C# may only shrink, route mechanically to N#, or be deleted.
- Implement all new behavior and canonical tests in N#.
- Identify the exact C# semantic methods, branches, callers, and assertions this sub-slice deletes.
- Use stable symbol/type identities; text matching is not semantic resolution.
- N# must be the direct production authority, with no callback or fallback to `Analyzer.cs`.
- Tests migrate with the behavior. Missing N# prerequisites remain inside this sub-slice.
- Recut within this goal turn if N# grows without the named C# deletion.
- Follow all compiler and mandatory IDE evidence in `AGENTS.md`, then commit with `Evidence:`,
  update the ledger, repin when required, and leave a clean tree.
- Report only after this sub-slice is complete.

## Slice

Move one bounded semantic behavior from `Analyzer.cs` into the canonical N# semantic model.

Read the active sub-slice in `systems-language-closeout/STATUS.md`. If none is recorded, select the
smallest deletion-ready behavior in this order: conversions/assignability, primitive operators,
pattern binding/exhaustiveness, one definite-assignment or flow join, field/property resolution,
fixed-arity call binding, one statement/assignment family, then one expression/declaration family.
Record the exact target before editing.

Route every affected production consumer directly to the N# result, migrate its assertions, and
delete the exact C# methods and branches. Move any required AST model for this behavior in the same
slice and delete the corresponding C# records; do not land an unused parallel AST.

After committing, leave task 017 unchecked and name the next concrete sub-slice while analyzer or
C# AST policy remains. Mark it complete only when `Analyzer.cs` and the C# AST are deleted or are
reviewed zero-policy mechanical hosts.

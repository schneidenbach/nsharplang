# 018 — Systems analyzer ownership

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Execute exactly one vertical systems-policy slice in this goal turn. Do not attempt all of
`SystemsAnalyzer.cs` at once, and do not stop at planning, scaffolding, prerequisites, parity
results, or a progress summary.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Existing C# may only shrink, route mechanically to N#, or be deleted.
- Implement all new behavior and canonical tests in N#.
- Identify the exact C# policy methods, callers, and assertions this sub-slice deletes.
- Consume stable semantic identities from task 017; never reconstruct identity from source text.
- N# must be the direct production authority with no callback or fallback.
- Tests migrate with the behavior. Missing N# prerequisites remain inside this sub-slice.
- Follow all compiler and mandatory IDE evidence in `AGENTS.md`, commit with `Evidence:`, update
  the ledger, repin when required, and leave a clean tree.
- Report only after this sub-slice is complete.

## Slice

Move one bounded systems-policy family into N#.

Read the active sub-slice in `systems-language-closeout/STATUS.md`. If none is recorded, choose the
smallest deletion-ready family with complete input facts: allocation restrictions,
attribute/modifier rules, unsafe/pointer policy, async/generator policy, or prohibited call/member
policy. Record the exact target before editing.

Move both required fact production and policy evaluation into canonical N# semantic identities,
route production directly, migrate the assertions, and delete the matching
`SystemsAnalyzer.cs` methods and branches.

After committing, leave task 018 unchecked and name the next concrete sub-slice while systems
policy remains. Mark it complete only when `SystemsAnalyzer.cs` is deleted or is a reviewed
zero-policy mechanical host.

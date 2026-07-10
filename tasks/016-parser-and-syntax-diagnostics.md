# 016 — Parser and syntax-diagnostic ownership

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Execute exactly one vertical ownership slice in this goal turn. Do not attempt all of `Parser.cs`
at once, and do not stop at planning, scaffolding, prerequisites, parity results, or a progress
summary.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Existing C# may only shrink, route mechanically to N#, or be deleted.
- Implement all new behavior and canonical tests in N#.
- Identify the exact C# parser/recovery/diagnostic branches and assertions this sub-slice deletes.
- N# must be the direct production authority; no legacy or differential fallback may remain.
- Tests migrate with the behavior. Missing N# prerequisites remain inside this sub-slice.
- Recut within this goal turn if N# grows without the named C# deletion.
- Follow every backend and mandatory IDE verification rule in `AGENTS.md`, including the VS
  Code-enabled gate, extension reinstall, computer-use verification, screenshots, selective
  staging, an `Evidence:` commit, ledger updates, and a clean tree.
- Report only after this sub-slice is complete.

## Slice

Move one bounded syntax behavior from `Parser.cs` to the existing N# parser and diagnostic owner.

Read the active sub-slice in `systems-language-closeout/STATUS.md`. If none is recorded, choose the
smallest deletion-ready behavior from imports/namespaces, type declarations, member declarations,
functions/generics, statements, expressions, or patterns, and record the exact target before
editing.

Make N# the sole production parser and ordered diagnostic authority for that behavior. Route every
affected compiler and IDE consumer directly to it, migrate canonical assertions to native N#, and
delete the corresponding C# parsing, recovery, and reporting decisions. Never retain production
shadow parsing or a comparison route.

After committing, leave task 016 unchecked and name the next concrete sub-slice while parser policy
remains. Mark it complete only when `Parser.cs` is deleted or is a reviewed zero-policy mechanical
host.

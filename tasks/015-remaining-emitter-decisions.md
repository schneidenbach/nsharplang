# 015 — Remaining emitter decisions

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Execute exactly one vertical ownership slice in this goal turn. Do not attempt the whole emitter
at once, and do not stop at planning, scaffolding, prerequisites, parity results, or a progress
summary.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Existing C# may only shrink, route mechanically to N#, or be deleted.
- Implement all new behavior and canonical tests in N#.
- Before editing, identify the exact C# methods, branches, and assertions this sub-slice deletes.
- N# must become the direct production owner. Leave no legacy fallback, shadow implementation,
  comparison route, or duplicated semantic authority for the migrated behavior.
- Tests migrate with the behavior; do not defer them.
- Missing N# prerequisites are part of this sub-slice; continue through production deletion.
- If substantial N# code accumulates without the named C# deletion, recut within this goal turn.
- Follow `AGENTS.md`: focused evidence, required integration/IDE gates, selective staging, an
  `Evidence:` commit, ledger updates, required clean repin, and a clean working tree.
- Report only after this sub-slice is complete, with exact code deltas and evidence.

## Slice

Perform one remaining `ColumnarIlEmitter.cs` ownership deletion.

Read the active sub-slice recorded in `systems-language-closeout/STATUS.md`. If none is recorded,
inventory the current emitter only far enough to select the smallest coherent deletion-ready
family: one expression root kind, one statement kind, or one declaration/lowering family. Record
that exact target before editing; do not produce a broad plan.

Move the selected family end-to-end into existing canonical N# binding/plan/execution owners,
migrate its assertions to native N#, route production directly, and delete the named C# decisions.
Do not add another feature-specific binder or schema when an existing owner can be extended.

After committing, if emitter policy remains, leave task 015 unchecked and record the next smallest
concrete sub-slice in STATUS.md. Mark task 015 complete only when `ColumnarIlEmitter.cs` is deleted
or is a reviewed, non-growing, zero-policy mechanical host.

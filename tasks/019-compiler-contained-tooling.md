# 019 — Compiler-contained tooling ownership

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Execute exactly one vertical tooling behavior in this goal turn. Do not attempt an entire large
tooling file at once, and do not stop at planning, scaffolding, prerequisites, parity results, or a
progress summary.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Existing C# may only shrink, route mechanically to N#, or be deleted.
- Implement all new behavior and canonical semantic tests in N#.
- Identify the exact C# policy methods, callers, and assertions this sub-slice deletes.
- N# must be the direct production authority; keep only proved pre-existing mechanical adapters.
- Tests migrate with the behavior. Missing N# prerequisites remain inside this sub-slice.
- Follow the mandatory VS Code-enabled gate, extension reinstall, computer-use verification,
  screenshots, selective staging, `Evidence:` commit, ledger update, and clean-tree rules in
  `AGENTS.md`.
- Report only after this sub-slice is complete.

## Slice

Move one bounded behavior from `Linter`, `Formatter`, `CodeIntelligenceService`,
`CompletionEngine`, `DocQuery`, `OutputFormatter`, or `NullabilityMetadata` into N#.

Read the active sub-slice in `systems-language-closeout/STATUS.md`. If none is recorded, select the
smallest deletion-ready behavior and record its exact input/output contract and C# deletion target
before editing. Do not select an entire file unless it is already small enough for complete
replacement.

Route every CLI and IDE consumer directly to the canonical N# result, migrate semantic assertions,
and delete the corresponding C# product policy. Document any surviving mechanical boundary.

After committing, leave task 019 unchecked and name the next concrete sub-slice while tooling
policy remains. Mark it complete only when all listed files are deleted or reduced to reviewed,
non-growing mechanical hosts.

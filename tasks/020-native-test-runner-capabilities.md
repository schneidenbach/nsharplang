# 020 — Native N# test-runner capabilities

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Execute exactly one vertical native-test capability in this goal turn. Do not attempt the entire
runner at once, and do not stop at planning, scaffolding, prerequisites, parity results, or a
progress summary.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Existing C# may only shrink, route mechanically to N#, or be deleted.
- Implement runner parsing/modeling, execution policy, and canonical tests in N#.
- The new capability must immediately migrate one real C# test cluster; unused infrastructure is
  not completion.
- N# must own result classification and stable output. Existing C# may only mechanically execute
  an N#-decided plan and must shrink.
- Follow `AGENTS.md`: focused and CLI JSON evidence, required product gates, selective staging,
  `Evidence:` commits, ledger updates, required repins, and a clean tree.
- Report only after this capability and its first real migration are complete.

## Slice

Implement one missing native-test capability and immediately consume it by migrating one real C#
compiler/tooling test cluster.

Read the active sub-slice in `systems-language-closeout/STATUS.md`. If none is recorded, select the
first missing capability in this order: table-driven cases, skip, setup/teardown, async `Task`,
async `ValueTask`, structured failure JSON, whole-run timeout. Record the exact migrated test
cluster before editing.

Delete the migrated C# assertions and the matching C# runner policy. Run the native runner's own
tests, migrated suite, CLI JSON contracts, and required product gate.

After committing, leave task 020 unchecked and name the next capability while runner or canonical
C# test policy remains. Mark it complete only when the required runner surface is N#-owned and no
C# compiler/tooling file remains a canonical assertion layer.

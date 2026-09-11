# 014 — Async iterators

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

Own `async func*` parsing, semantic validation, and async-iterator lowering in N#.

Use `examples/08-async/AsyncStreams.nl` as the product reproducer. Build on the completed
synchronous iterator owner; do not create a second state-machine model. N# must own async/yield
composition, element and awaitable types, generated state-machine definitions, move-next and
dispose behavior, cancellation/captures where currently supported, and emitted interfaces.

Delete the corresponding C# parser, analyzer, definition, and lowering decisions and migrate
their assertions to native N#. Add multiple awaits/yields, branches, failures, disposal, invalid
declarations/types, persisted asynchronous enumeration, and IL verification tests. Build and run
the example before committing, including the required VS Code gate and visual verification.

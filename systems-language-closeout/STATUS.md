# Systems-language closeout cursor

Last updated: 2026-07-10

## Cursor

- Current task: `tasks/001-external-static-fields-and-properties.md`
- Current iteration: one terminal slice
- Active sub-slice: finish and recut the existing dirty external-static field/property work
- Last accepted prerequisite commit: `b839bd1ee` (`Admit metadata-only assembly inspection`)
- Queue: `tasks/README.md`

## Current evidence

- BootstrapServices native contracts: 162/162 green after the latest scope-fact fixes.
- The focused Columnar run was interrupted before a final result and must be rerun.
- Current uncommitted C# delta: four additions, 82 deletions; net minus 78 lines.
- Current uncommitted N# delta: 3,306 additions, 42 deletions. Task 001 must remove duplication and
  land a canonical reusable owner rather than preserving a static-member-specific mini-analyzer.
- The latest semantic review says the slice is not commit-safe: file-import suffix/base-directory
  behavior, fully qualified owner lookup, external base/interface handling, declaration
  accessibility and package precedence, and global-versus-namespaced ambiguity still diverge from
  production semantics. A derived-class primary-parameter non-inheritance test is also missing.
- Product-route fixtures should cover a ref/lib package plus MSBuild reference-only input and a
  project-relative DLL while the test process runs from another working directory.
- Required before task 001 completion: product-route fixtures, ownership audit update, focused
  suites, fresh non-VS-Code product gate, coherent commit, clean repin, and clean worktree.

## Iterative-task targets

These are populated only when their task becomes current.

- Task 015 next emitter sub-slice: not selected
- Task 016 next parser sub-slice: not selected
- Task 017 next semantic sub-slice: not selected
- Task 018 next systems-policy sub-slice: not selected
- Task 019 next tooling sub-slice: not selected
- Task 020 next native-runner sub-slice: not selected

## Completion ledger

No numbered task is complete yet. After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.

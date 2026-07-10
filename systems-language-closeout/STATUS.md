# Systems-language closeout cursor

Last updated: 2026-07-10

## Cursor

- Current task: `tasks/002-bound-identifier-reads.md`
- Current iteration: one terminal slice
- Active sub-slice: move parameter, local, lifted-local, and current-instance reads into N# plans
- Last accepted ownership commit: `6110bbbcf` (`Own external static members in N#`)
- Queue: `tasks/README.md`

## Current evidence

- Task 001 is accepted at `6110bbbcf`. N# now owns reusable binding-scope facts, deterministic
  assembly/type discovery, exact static field/property selection, schema-v3 planning, validation,
  and execution; the emitter-side reflection/preload owner and hard-coded enum, primitive, pool,
  field, property, and preflight branches were deleted.
- Focused evidence: 3,182/3,182 unit tests, 178/178 BootstrapServices contracts, 18/18 ownership
  audit, both external-static fixtures 1/1, and both issue-tracker routes 6/6.
- The fresh non-VS-Code product gate passed units, native discovery, formatting, package/ref/DLL
  fixtures, project examples, and every `nlc check`. Its four remaining groups are assigned to
  later queue owners: Web API external base resolution (009), synchronous iterators (013), async
  iterators (014), and seven record/init/method-access IL findings (011-012 and 015 as applicable).
- Clean repin: `nlc 0.1.0+6110bbbcf`, doctor status `ok`; installed, local-feed, and global-cache SDK
  hashes all equal `5f83e6ede55076f3c9019878e4b1cd189432b62edfd6b88c71f7154131b3b626`.
  The cached BootstrapServices DLL hash is
  `d38482c6e3bbf105ba0977df95ba2ebc8c78cb736bf7f94a72ea934bc4263612`.

## Iterative-task targets

These are populated only when their task becomes current.

- Task 015 next emitter sub-slice: not selected
- Task 016 next parser sub-slice: not selected
- Task 017 next semantic sub-slice: not selected
- Task 018 next systems-policy sub-slice: not selected
- Task 019 next tooling sub-slice: not selected
- Task 020 next native-runner sub-slice: not selected

## Completion ledger

Completed slices:

- Task 001 — external static fields and properties; commit `6110bbbcf`.
  - Deleted C# owners: `TryUsePlannedExternalStaticMember`,
    `PreloadSupportedExternalReferenceAssemblies`, `TryGetStringComparisonValue`,
    `TryEmitPrimitiveStaticConstant`, and the matching enum/primitive/pool/static-member emission
    and preflight branches. `ColumnarIlEmitter.cs` fell from 21,515 to 21,361 lines.
  - Added N# owners: `ColumnarBindingScopeFacts`, `ColumnarExternalStaticMemberPlanner`,
    `ExternalAssemblyScan`, `ExternalQualifiedTypeResolver`, schema-v3 field handles/`ldsfld`, and
    their native contracts plus package and relative-DLL product fixtures.
  - Evidence: 3,182 units; 178 BootstrapServices contracts; 18 ownership tests; package,
    outside-CWD DLL, issue-tracker, exact-reference, persisted execution, and clean repin proofs.

After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.

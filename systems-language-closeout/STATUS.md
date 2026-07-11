# Systems-language closeout cursor

Last updated: 2026-07-10

## Cursor

- Current task: `tasks/003-instance-fields-and-properties.md`
- Current iteration: one terminal slice
- Active sub-slice: move ordinary instance field and property reads into N# plans
- Last accepted ownership commit: `61a593715` (`Own bound identifier reads in N#`)
- Queue: `tasks/README.md`

## Current evidence

- Task 002 is accepted at `61a593715`. N# now owns exact parameter, local, lifted/boxed capture,
  and current-instance field/property value reads as roots and recursive range/index children,
  including shadowing, ordinals, receiver address form, malformed-fact rollback, and persisted
  execution. The matching C# emission and preflight branches were deleted, and an N# ownership
  claim is terminal rather than a fallback route.
- Focused evidence: 3,182/3,182 unit tests, 201/201 BootstrapServices contracts, 26/26 range-index
  product contracts, and 18/18 ownership-audit contracts.
- The fresh non-VS-Code product gate passed units, native discovery, formatting, package/ref/DLL
  fixtures, project examples, and every `nlc check`. Its four remaining groups are assigned to
  later queue owners: Web API external base resolution (009), synchronous iterators (013), async
  iterators (014), and seven record/init/method-access IL findings (011-012 and 015 as applicable).
- Clean repin: `nlc 0.1.0+61a5937154d2292a8b5586f492fbedce7e217ac3`, doctor status `ok`;
  installed, local-feed, and global-cache SDK hashes all equal
  `788c27827584154de70825b13f758f4292c13366ab9030f2b78220b1b9c6c807`.
  The cached BootstrapServices DLL hash is
  `5c3dae62e57ae8ebdb6578f3228f6d0d3fd6cef22e2525fdcd0a42017c22fbab`.

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

- Task 002 — bound identifier reads; commit `61a593715`.
  - Deleted C# owners: ordinary local/non-byref-parameter, lifted-local, boxed-capture,
    explicit-`this`, and bare current-instance field/property identifier emission, plus the
    matching preflight/type branches. `ColumnarIlEmitter.cs` fell from 21,361 to 21,209 lines.
  - Added N# owners: `ColumnarBoundIdentifierPlanner`, exact lexical/current-instance binding
    facts, recursive code-plan argument-address and declared-signature validation, live source-type
    metadata, and atomic zero-arity property accessor definition, with native malformed, rollback,
    shadowing, generic/inherited receiver, persisted, and source-type-return contracts.
  - Evidence: 3,182 units; 201 BootstrapServices contracts; 26 range-index product contracts;
    18 ownership tests; fresh non-VS-Code product-gate task surfaces; clean SDK repin.

After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.

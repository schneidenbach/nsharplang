# Systems-language closeout cursor

Last updated: 2026-07-11

## Cursor

- Current task: `tasks/004-fixed-arity-direct-calls.md`
- Current iteration: one terminal slice
- Active sub-slice: move fixed-arity non-generic direct calls into N# plans
- Last accepted ownership commit: `ad51692d4` (`Own instance field and property reads in N#`)
- Queue: `tasks/README.md`

## Current evidence

- Task 003 is accepted at `ad51692d4`. N# now owns ordinary one-receiver source and runtime
  field/property selection, receiver lowering, exact reflection identity, result type, validation,
  and execution, including inherited, closed-generic, value/reference/byref, persisted, recursive
  range/index, `typeof`, and zero-hole interpolation receiver forms. The C# direct read chain is
  narrowed to excluded nested receivers; matching direct runtime-property, `typeof`, interpolation,
  and preflight branches are deleted, while nested chains, calls, indexers, writes, and ref/out stay
  on their existing owners.
- Focused evidence: 3,182/3,182 unit tests, 238/238 BootstrapServices contracts, 41/41 range-index
  product contracts, and 18/18 ownership-audit contracts.
- The fresh non-VS-Code product gate passed units, native discovery, formatting, package/ref/DLL
  fixtures, project examples, and every `nlc check`. Its four remaining groups are assigned to
  later queue owners: Web API external base resolution (009), synchronous iterators (013), async
  iterators (014), and seven record/init/method-access IL findings (011-012 and 015 as applicable).
- Clean repin: `nlc 0.1.0+ad51692d4f8d5a75db87ebb9e9fd9fb128d4c0fd`, doctor status `ok`;
  installed, local-feed, and global-cache SDK hashes all equal
  `2ee6d03d6baeae9a25bb98f2d01bf16408e33fc62d481f9f7a24817ccabbbe6c`.
  The cached BootstrapServices DLL hash is
  `c701e8ebaae83501dff465ddb019f3ee16368df7ebecbd88f3ea0112ccb2ae4b`.

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

- Task 003 — instance fields and properties; commit `ad51692d4` (stage-0 prerequisites
  `da2be2c32`, `97cde7c6e`, and `aedb1267f`).
  - Deleted C# owners: direct one-receiver source field/property read emission, direct
    `Exception.Message` and `WebApplication.Environment` property arms, the member-chain preflight
    shortcut for the migrated roots, `typeof` emission/preflight, and zero-hole interpolation
    emission. The retained source-member branch is restricted to excluded nested receivers.
    `ColumnarIlEmitter.cs` fell from 21,209 to 21,164 lines.
  - Added N# owners: `ColumnarInstanceMemberPlanner`, exact runtime/source member resolvers,
    schema-v3 field/method/type handles and receiver-address operations, `ColumnarTypeOfPlanner`,
    zero-hole interpolation receiver planning, and live source type/union/tuple facts, with native
    accessibility, shadowing, inheritance, closed-generic, value/reference/byref, corrupt-handle,
    rollback, persisted-execution, nested-fallback, and recursive range/index contracts.
  - Evidence: 3,182 units; 238 BootstrapServices contracts; 41 range-index product contracts;
    18 ownership tests; three adversarial audits; fresh non-VS-Code product-gate task surfaces;
    clean SDK repin.

After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.

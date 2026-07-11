# Systems-language closeout cursor

Last updated: 2026-07-11

## Cursor

- Current task: `tasks/005-construction-and-array-literals.md`
- Current iteration: one terminal slice
- Active sub-slice: move ordinary construction, sized arrays, and inferred array literals into N# plans
- Last accepted ownership commit: `5ad756e1d` (`Own fixed-arity direct calls in N#`)
- Queue: `tasks/README.md`

## Current evidence

- Task 004 is accepted at `5ad756e1d` (stage-0 prerequisites `d6d551ea1`, `d24ec7bb4`,
  `8ce4d49e2`, `fcbcf4ef6`, `0cd216a44`, `0e1d02ed1`, `507742abc`, `1e747dd97`,
  `469408917`, `1b63b9a82`, and `0035d82ae`). N# now owns exact fixed-arity,
  non-generic source and runtime static/instance calls: receiver and argument planning, overload and
  signature selection, admitted conversions, `call` versus `callvirt`, result type, rollback, and
  stack validation. Exact source-owner scope, import/type-alias subtree boundaries, addressable
  value receivers, and synthesized record calls are covered by native and product contracts.
- The C# emitter's synthesized-record `Equals`/`GetHashCode` preflight and emission branches and
  direct `TextWriter.WriteLine(string)` arm are deleted. Retained call paths are fenced to excluded
  generic, extension, params, ref/out, contextual-lambda, method-group, or whole-subtree forms.
  `ColumnarIlEmitter.cs` fell from 21,164 to 21,097 lines.
- Evidence: 3,181/3,182 units in the fresh gate (only Task 009), 382/382 BootstrapServices
  contracts, 14/14 direct-call product contracts, 2/2 interface-parameter contracts, 18/18
  ownership-audit contracts, 4/4 decline-diagnostic contracts, 2/2 reflection-bootstrap contracts,
  and exact direct-call IL verification. The two gate-only scope regressions were fixed and their
  exact unit tests pass 2/2.
- The fresh non-VS-Code product gate has exactly ten remaining failure groups, all assigned to later
  queue owners: issue-tracker/Web API external base resolution (009), record-with value lowering
  (011), readonly initialization (012), synchronous iterators (013), async iterators (014), and
  remaining method-access/IL decisions (015).
- Clean repin: `nlc 0.1.0+5ad756e1dfa68d6849fd7cc689ff5e7f8865e10c`, doctor status `ok`;
  installed, local-feed, and global-cache SDK hashes all equal
  `878804310b6b8a6c4a7f5a819487a75a7e5cd4fb254009f48ad8b66313251d88`.
  The cached BootstrapServices DLL hash is
  `2a56c9f0d6cbb592ad34b6a47e4d71a443f3dea4c275462d45cd1a6fd184773a`.

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

- Task 004 — fixed-arity direct calls; commit `5ad756e1d` (stage-0 prerequisites `d6d551ea1`,
  `d24ec7bb4`, `8ce4d49e2`, `fcbcf4ef6`, `0cd216a44`, `0e1d02ed1`, `507742abc`,
  `1e747dd97`, `469408917`, `1b63b9a82`, and `0035d82ae`).
  - Deleted C# owners: synthesized-record `Equals(object)` and `GetHashCode()` call preflight and
    emission, the direct `TextWriter.WriteLine(string)` arm, and unrestricted re-entry into ordinary
    source/runtime fixed-call paths. Retained C# routes are mechanically fenced to excluded call
    families. `ColumnarIlEmitter.cs` fell from 21,164 to 21,097 lines.
  - Added N# owners: `ColumnarDirectCallPlanner`, exact source/runtime resolvers, contextual
    conversion and nullable lowering, source-static scope resolution, exact method/constructor facts,
    address-preserving value receivers, synthesized record call facts, and schema/executor stack
    validation, with native overload, accessibility, malformed-handle, rollback, recursive,
    persisted, alias/shadowing, and IL-shape contracts.
  - Evidence: 3,181/3,182 fresh-gate units with only Task 009 remaining; 382 BootstrapServices
    contracts; 14 direct-call, 2 interface-parameter, 18 ownership, 4 decline-diagnostic, and 2
    reflection-bootstrap contracts; exact ILVerify; three adversarial audits; clean SDK repin.

After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.

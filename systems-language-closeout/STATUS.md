# Systems-language closeout cursor

Last updated: 2026-07-18

## Cursor

- Current task: `tasks/006-primitive-binary-expressions.md`
- Current iteration: one terminal slice (stage 0 `3dcb60bd2` opcode identities; ownership routing
  landed next — see Current evidence)
- Active sub-slice: own bare sibling-function CALL operands (the last deletion blocker; casts and decimal literals landed at `83941f204`), then delete the case-12 numeric arms. Prior framing —
  cast expressions (kind 16 numeric casts), decimal literals, and bare sibling-function call
  operands. The verified blocker: with the case-12 numeric arms deleted, `x == (uint)42`,
  `d == 24.5m`, and `Foo() == 42` decline because those operands are not yet plannable, so the
  deletion was reverted and the arm stands as the fenced whole-subtree residual. Once those operand
  families plan, delete the case-12 numeric switch, shifts branch, decimal table, string-pair
  concat, and shrink `TryGetPreflightBinaryExpressionType` to the retained families
  (&&/||, ??, null comparisons, string chains, string+char, Type/record/enum equality,
  source operators).
- Last accepted ownership commit: `6746c1b2c` (`Own construction and array literals in N#`)
- Queue: `tasks/README.md`

## Current evidence

- Task 005 is accepted at `6746c1b2c` (stage-0 prerequisites `67a3e5803`,
  `37822d657`, `f9ed33dd9`, `aca8d35b3`, `91c062dd6`, `e63f27176`, and `ff2cf1138`). N# now owns
  construction planning end-to-end for the admitted family: ordinary source/runtime constructor
  calls with exact selection, defaults (including enum and dotted/aliased enum defaults), sized and
  inferred array literals with exact store opcodes, source class/struct/record and union-case object
  initializers (including nested values, generic-base member rebinding, and target-typed integers),
  closed source/runtime generic construction, and the approved runtime constructor catalog, all
  through schema-v3 plan rows executed and stack-validated by `ColumnarCodePlanExecutor`.
- The Analyzer's string-matched member/export/declaration resolution was deleted and replaced by
  the N#-owned `AnalyzerDeclarationContext`/`ColumnarSemanticTypeRegistry` exact-scope facts:
  `Analyzer.cs` fell from 23,471 to 23,068 lines. `ColumnarSynthesizedGenericScopeTests.cs` was
  deleted in favor of the native `generic-scope-invalid` project. Aggregate C# across the slice is
  net negative (−157 lines).
- The C# emitter retains exactly one fenced legacy surface for constructions: the whole-subtree
  residual (kinds 15/58/36 plus four helpers), reachable only when the N# planner declines without
  claiming (a value outside the plannable surface, e.g. interpolated holes or sibling-function call
  arguments). This mirrors the accepted task-004 fenced-call architecture; `ColumnarIlEmitter.cs`
  is 21,586 lines (epoch ceiling 21,723). The residual shrinks as later owners land (interpolation,
  sibling calls: task 015).
- Evidence: 3,182/3,182 units in the fresh gate (task 009's issue-tracker failure is FIXED by this
  slice); 553/553 BootstrapServices contracts; native product contracts all green: 14/14
  direct-calls, 18/18 ownership-audit, 7/7 construction-arrays (new), 3/3 generic-scope-invalid
  (new), 1/1 erased-enum-identity (new). Previously red vs HEAD and now green: `examples/16-task-cli`
  (union-case construction with interpolated argument), `examples/12-multi-file-projects/WeatherDemo`
  (record object initializer with call/index values), AutoDiscovery, issue-tracker backend check,
  and systems proof 36 (`new Dictionary<int,int>(capacity: 128)` named argument).
- The fresh non-VS-Code product gate has exactly four remaining failure groups, all verified
  byte-identical at HEAD `ff2cf1138` and assigned to later queue owners: Web API template build
  (009), Iterators single-file example (013), AsyncStreams single-file example (014), and the IL
  verification findings `RecordStructs.dll` CallVirtOnValueType/StackUnexpected (011) and
  `RecordsAndInterfaces.dll` InitOnly on `<InitializeFields>$` (012). Down from ten groups at the
  task-004 acceptance.
- The ownership growth ratchet is repinned to observed state (audit 18/18); the emitter entry rises
  only within its immutable epoch ceiling and records the restored fenced residual.
- Post-acceptance follow-ups `195028aa9` and `7f4e727d6`: columnar emission now runs on a dedicated
  wide-stack thread (MSBuild task threads run ~256 KB stacks and the emitter's per-node frames are
  large; the July-12 sources overflowed every fresh SDK-path emit), and the NL103 decline diagnostic
  is built inside that same thread (the decline trace is thread-local). The stale mid-slice SDK pack
  in `~/.nuget/local-feed` (the feed actually consulted; `~/.nsharp/packages` is not) was replaced,
  and the self-host loop is regenerative again: BootstrapServices Release re-emits cleanly through
  the packaged SDK, 553/553 contracts pass against the fresh kernel, and the clean repin is
  `nlc 0.1.0+7f4e727d615d2c38b5b71e6ac69690e5aa2275ff` with doctor status all-green.

## Iterative-task targets

These are populated only when their task becomes current.

- Task 015 next emitter sub-slice: not selected (queued residual from 005: interpolated-hole
  string values and bare sibling-function call arguments inside constructions whole-subtree-exit to
  the fenced legacy arms; owning those value forms in N# retires the construction residual)
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

- Task 005 — construction and array literals; commit `6746c1b2c` (stage-0
  prerequisites `67a3e5803`, `37822d657`, `f9ed33dd9`, `aca8d35b3`, `91c062dd6`, `e63f27176`,
  and `ff2cf1138`).
  - Deleted C# owners: the Analyzer's string-matched member/export/declaration resolution
    (nested-type, tuple, primary-constructor-parameter, declared-member and export-visibility
    string lookups; `Analyzer.cs` fell from 23,471 to 23,068 lines), the emitter's unconditional
    construction ownership (constructions claimed by the N# planner never reach C#; the retained
    kinds 15/58/36 arms are fenced to the whole-subtree residual), and
    `ColumnarSynthesizedGenericScopeTests.cs` (replaced by the native `generic-scope-invalid`
    project). Aggregate C# net −157 lines.
  - Added N# owners: `ColumnarConstructionPlanner` (source/runtime/closed-generic constructor
    selection with defaults, sized/inferred arrays, source and union-case object initializers,
    runtime catalog), construction-row execution in `ColumnarCodePlanExecutor`,
    `ColumnarSemanticTypeRegistry` + `AnalyzerDeclarationContext` exact declaration scopes,
    `ColumnarPrimitiveBinaryPlanner` (admitted value-position binaries),
    `ColumnarSourceOperatorResolver`, and `TypeInfoIdentityFacts`, with native construction-arrays,
    generic-scope-invalid, and erased-enum-identity product contracts.
  - Evidence: 3,182/3,182 fresh-gate units (issue-tracker fixed); 553 BootstrapServices contracts;
    14 direct-call, 18 ownership, 7 construction-arrays, 3 generic-scope-invalid, and 1
    erased-enum-identity contracts; fresh non-VS-Code product gate down to four failure groups all
    verified pre-existing at HEAD and owned by 009/011/012/013/014; ratchet repin (audit 18/18);
    clean SDK repin.

After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.

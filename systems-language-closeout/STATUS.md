# Systems-language closeout cursor

Last updated: 2026-07-21

## Cursor

- Current task: `tasks/015-remaining-emitter-decisions.md`
- Current iteration: one terminal slice
- Active sub-slice: not yet selected (015 owns the recorded fenced residuals: lambda-taking LINQ
  arms, the interpolation hole/emission core, the C# generic String.Join arm for non-int/string
  elements, extension interface-receiver inference, preflight typing of legacy-owned static
  calls, the case-12/13 numeric/conditional cores, and real async-func lowering to replace the
  blocking consumer await model)
- Last accepted ownership commit: task 014's slice commits (`d396a847c`, `73ae226d5`,
  `0a33f1ff2`, `f3d1e89c9`)
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

- Task 006 — primitive binary expressions; commit `e57c80c8a` (stage commits `3dcb60bd2`,
  `e41570f69`, `83941f204`, `62ab5ffdf`, `096655625`, `5523402c5`, `aade33590`, `8397811ea`).
  - Deleted C# owners: the case-12 shifts branch, decimal op_* table, and right-literal adoption
    path from both emission and preflight, plus the preflight's arith/bitwise/ordering/numeric
    equality arms. `ColumnarIlEmitter.cs` fell from 21,618 to 21,499. The retained fenced numeric
    core serves exactly the whole-subtree residual: contextual-lambda call operands (010), member
    chains on call results, unary-negated call operands, dictionary-indexer reads, and string-typed
    operands such as enum string-constant reads (015 grows the nested-operand surface).
  - Added N# owners: the full primitive binary family (arithmetic with checked/unchecked overflow
    selection, bitwise, shifts, ordering with float unordered complements, numeric/Boolean
    equality, decimal op_* calls, string-pair concat, right-literal adoption) at expression roots
    and value position; operand families unlocked along the way — numeric casts, decimal literals
    (incl. negative), sibling-function calls, local-delegate invocations, String.Join catalog,
    List<T> indexer chains, byref-parameter deref reads over the typed-ldind family, ushort literal
    casts, and slot-reinterpretation casts via explicit conv.
  - Evidence: 608 BootstrapServices contracts (Debug and fresh Release self-emit); 15 primitive-
    binary, 41 range-index, 14 direct-call, 3 interface-parameter, 18 ownership contracts;
    3,182/3,182 units; fresh non-VS-Code gate at the same four pre-existing later-owner failure
    groups (009/011/012/013/014) as the 005 acceptance; toolset repins at each two-stage bootstrap.

- Task 007 — conditional and short-circuit expressions; commit `e9df4eb60` (routing commit
  `7eaccb1e9`, Brtrue two-stage bootstrap with mid-stage toolset repin).
  - Deleted C# owner: the `&&`/`||` sub-arm in `TryGetPreflightBinaryExpressionType` (proven dead —
    N# types every plannable short-circuit at the front door; a residual short-circuit is only ever
    emitted, never preflight-typed; zero hits across units, native contracts, examples, and the
    self-emit). `ColumnarIlEmitter.cs` fell from 21,499 to 21,497. The case-12 short-circuit and
    case-13 ternary EMIT arms are verify-first load-bearing (self-emit ternary null-comparison
    conditions; example `||` chains over string equality) and are recut as precisely-fenced
    whole-subtree residual servers retiring with task 015's nested-operand/equality surface growth.
  - Added N# owners: `ColumnarConditionalPlanner` — Boolean `&&`/`||` with the exact case-12
    short-circuit lowering and relocated ternary planning with widened operand recursion, claimed
    at expression roots and value position across emit and preflight facades; the `Brtrue` schema
    identity (contract id 58, condition-gated validation, allowlist name).
  - Evidence: 619 BootstrapServices contracts (Debug and fresh Release-packed-SDK re-emit); new
    conditional product project 8/8 with executed side-effect-order and right-operand-not-evaluated
    proofs; 3,182/3,182 units; all native projects green; fresh non-VS-Code gate at the same four
    pre-existing later-owner failure groups (009/011/012/013/014); clean toolset repin.

- Task 008 — complete range/index owner deletion; commit `23ced5034`.
  - Deleted C# owners: every range/index decision from `399008ea9` and its expansions — five
    static handles plus their resolver, thirteen lowering helpers, the case-11 index-from-end and
    case-69 range arms, the case-10 string/array Index/Range reads, and both preflight
    type-selection helpers with their dispatch arms. Only the Index/Range type-system entries
    remain (typed locals/parameters, not lowering policy). Residual inventory: empty — no fallback
    from N# to any old branch. `ColumnarIlEmitter.cs` fell from 21,497 to 21,209 (net −288).
  - Added N# owners: none needed — `ColumnarRangeIndexPlanner`/`ColumnarRangeIndexHandles` already
    owned the entire surface; the historical C# canonical test was migrated at `0206a1ed1`.
  - Evidence: 41/41 range-index product contracts identical before and after the deletion (the
    decisive dead-code proof); 619 BootstrapServices contracts against both feed and fresh SDK;
    3,182/3,182 units; all native projects green; fresh Release self-emit clean; fresh non-VS-Code
    gate at the same four pre-existing later-owner failure groups (009/011/012/013/014).

- Task 009 — external base and interface resolution; slice commits `85c817440` (base/interface
  classification), `5f9bf3fce` (inherited external-base-method calls), and the extension-calls
  commit; ACCEPTANCE: the generated Web API template checks, builds, and ILVerifies clean, and the
  fresh gate fell from four failure groups to three (013/014 iterators, 011/012 ilverify).
  - Deleted C# owners: the emitter's PASS 0a' base/interface classification decision block
    (`ColumnarIlEmitter.cs` 21,209 → 21,164); the remaining slices added zero C#.
  - Added N# owners: `ColumnarBaseTypePlanner` (ordered base classification incl. external runtime
    class bases with protected-ctor default chaining), inherited external-base-method bare/this
    call planning over the recorded base chain, `ColumnarExtensionMethodResolver` (ExtensionAttribute
    index with instance-beats-extension precedence and trailing-optional null-default fill),
    IServiceCollection admission, and highest-version NuGet runtime-asset unification.
  - Evidence: 625 BootstrapServices contracts; external-base-interface 18/18, extension-calls 4/4
    executed; 3,182/3,182 units; fresh Release self-emit clean; Web API ILVerify fully verified;
    all native projects green; gate baseline shrunk to three groups.

- Task 014 — async iterators; staged commits `d396a847c` (async classification facts: IsAsync,
  AwaitResumeCount, async return-shape admission/declines), `73ae226d5` (await-foreach parsing in
  the N# kernels: awaited kind-29 form + kind-73 consumer statement, toolset repin), `0a33f1ff2`
  (async state machines with REAL suspension: IAsyncEnumerable/IAsyncEnumerator/IAsyncDisposable
  member specs, schema-4 catch regions op 7, awaiter/promise/result/continuation field roles 5-8,
  MoveNextAsync fast-path vs TaskCompletionSource pending path, ldftn MoveNextCore continuation
  ctor, both exception routes, clone/dispose discipline — proven resuming off-caller-thread),
  `f3d1e89c9` (closing: classic C-style for kind 28, postfix ++/-- kind 44 incl. yield i++,
  ToUpper/ToLower/Trim instance calls, kind-73 await-foreach consumer lowering via the accepted
  blocking-await model; AsyncStreams.nl end-to-end).
  - NEW SURFACE like 013: no C# async-iterator emitter ever existed; deletion contract satisfied
    by planner-owned decline sites (emit.iterator.async-*) plus the deleted
    emit.iterator.async-emit-pending gate and zero net C# decision growth (emitter net −2 across
    the closing slice: 21,719/20,644 vs immutable epoch 21,723/20,646 — case-73 additions paid by
    lossless comment compression).
  - Added N# owners: ColumnarIteratorPlanner async classification + AnalyzeShape async facts +
    BuildAsyncMoveNextCore/MoveNextAsync/DisposeAsync/GetAsyncEnumerator/AsyncFactory plans, the
    kind-28/44/instance-string-call body surface, ColumnarCodePlan/Executor schema-4 catch
    regions, parser-kernel await-foreach forms.
  - Evidence: FULL VS Code-ENABLED GATE GREEN — ZERO failure groups (first fully-green gate of
    the closeout; AsyncStreams cleared; 14m11s; gate exit 0 with ALL TESTS PASSED). 731/731
    BootstrapServices contracts (717+14); 3,185/3,185 units; native iterators 25/25 (21+4 async);
    ownership audit 18/18; AsyncStreams.nl builds via the columnar pipeline, output order exact,
    real delays (1.273s wall for 10×100ms+4×50ms), ILVerify 2/2; nlc check/lint on the example
    0 findings; post-commit SDK repin to ~/.nuget/local-feed + gate dependency-cache reseed
    (nsharplang.* must be copied into the active Caches/NSharpLang/test-all/dependencies/<key>
    after a repin — the isolated gate only sees nuget.org plus that cache). VS Code extension
    rebuilt+reinstalled (reload-vscode-extension.sh exit 0); gate VS Code integration tests
    (extension, diagnostics, hover, completion) pass. OUTSTANDING: the computer-use visual IDE
    spot-check was attempted at this acceptance and screen-control access was DENIED at the
    approval dialog again (second denial after 013); the automated VS Code integration evidence
    stands in. Retry at the next IDE-affecting acceptance only if the user re-enables access.
  - Residuals recorded for 015+: await foreach inside an async iterator body (machine
    composition), async instance/generic iterators, awaited operands beyond statement-position
    Task.Delay(int), real async-func lowering to retire the blocking consumer await model.

- Task 013 — synchronous iterators; staged commits `489895987` (func*/yield parsing in the N#
  kernels, node kind 72, generator flag 4096, toolset repin), `71c5450b1` (schema-4 stage 1:
  Ret/Throw/Isinst/Stsfld/Leave allowlist + exception-region operations incl. FAULT, repin),
  `dd7d12107` (method-body executor + backward-branch stack-fixpoint validator, 13 contracts incl.
  the leave-runs-finally-not-fault proof), `03849de55` (ColumnarIteratorPlanner decision layer),
  `d0a4ee530` (MoveNext lowering proven running), `0c0961048` (native iterators project registered
  in ilverify.sh at its 476 ceiling + fall-through fix), `9698fbb76` (array for..in, throw, slot
  reuse), `bb359043f` (enumerator hoisting under the Roslyn try/FAULT region discipline; Dispose
  cascade), `d3602cfa4` (generic iterators via self-instantiation TypeSpec rebinding + MVAR-leak
  guard), `edfcbeb66` (instance iterators: <>__this capture, member reads, user-type sequence
  elements, member-call for..in sources incl. recursion), `f1c1b3b9f` (consumer surface:
  interpolation multi-arg call holes, plan-pinned generic String.Join<Int32>, open-generic
  extension inference — all N#, zero C# growth).
  - NEW SURFACE, not a migration: no C# iterator emitter ever existed (the C# recursive-descent
    func*/yield parser/analyzer stays as the LSP-fallback/oracle owned by 016/017; the analyzer
    already validated func* correctly). The "delete the C# owner" premise did not apply; the
    deletion contract is satisfied by the planner-owned decline sites replacing the blanket
    emit.statement.yield-unsupported arm and by zero net C# decision growth (emitter hosts
    mechanically at 21,619 of the immutable 21,723 ceiling).
  - Added N# owners: parser kernels (func* scan/signature/method-scan + yield statements),
    ColumnarCodePlan/Executor schema-4 method bodies, ColumnarIteratorPlanner (shape facts, state
    numbering, field layout, member/override specs, MoveNext/member/factory plans, decline
    classification), interpolation splitter multi-arg holes, plan-pinned generic external calls,
    open-generic extension-method inference.
  - Evidence: examples/09-linq-and-collections/Iterators.nl builds through the columnar pipeline,
    runs byte-exact across all nine sections, and ILVerifies (all six assemblies); native
    tests/native/iterators 21/21 executed proofs (sequences, infinite+break, re-enumeration
    clones, lazy throw, recursive tree traversal 1,2,4,5,3,6, generic value+reference elements,
    LINQ chain); 690/690 BootstrapServices contracts; 3,182/3,182 units; ownership audit 18/18;
    FULL VS Code-ENABLED GATE: exactly one failure group remains (AsyncStreams, owned by 014) —
    the Iterators group is CLEARED; VS Code smoke tests (extension, diagnostics, hover,
    completion) pass; extension rebuilt+reinstalled via reload-vscode-extension.sh. OUTSTANDING:
    the computer-use visual IDE spot-check was not performed this session (screen-control access
    denied at the approval dialog); the gate's automated VS Code integration evidence stands in.
    Perform the visual check at the next IDE-affecting acceptance (014).
  - Fenced 015 residuals recorded: lambda-taking LINQ arms (TryEmitEnumerableExtensionCall,
    TryEmitLambdaLiteral), the interpolation hole/emission core, the C# generic String.Join arm
    for non-int/string elements, extension interface-receiver inference, preflight typing of
    legacy-owned static calls.

- Task 012 — readonly-field initialization placement; commit recorded in git ("Own readonly-field
  initialization placement in N#").
  - Deleted C# owners: the initialized-fields decision, unconditional helper synthesis, whole-body
    helper emission, and the inline default-ctor body decision — the N# plan is the sole placement
    authority.
  - Added N# owners: `ColumnarFieldInitPlanner` — initonly stores inline in every base-reaching
    constructor, mutable stores in a helper synthesized only when needed, static ownership
    untouched.
  - Evidence: RecordsAndInterfaces builds, runs, ILVerifies clean; estate-wide ILVerify 0 findings
    (empty baseline); the gate's IL-verification step now PASSES — the gate is down to TWO groups
    (013 Iterators, 014 AsyncStreams). New readonly-init project 18/18; 625 contracts; 3,182/3,182
    units; fresh Release self-emit clean.

- Task 011 — record-with lowering for value receivers; commit `8a90bcd92`.
  - Deleted C# owners: the case-52 arm's clone-always callvirt selection, receiver gate, per-field
    binding, and result-type decision, plus the value-record `<Clone>$` synthesis branch (record
    structs now carry no Clone, matching C#). The arm is mechanical over the N# plan.
  - Added N# owners: `ColumnarRecordWithPlanner` — clone/copy strategy (reference clone versus
    verifiable value copy through an addressed temp), receiver shape, ordered member resolution,
    readonly decline, exact call form, result type.
  - Evidence: RecordStructs builds, runs correctly, ILVerifies clean (delta −2 findings);
    whole-estate ILVerify over 91 assemblies leaves only the task-012 InitOnly finding; new
    record-with product project 12/12 registered in the ilverify gate; 625 contracts; 3,182/3,182
    units; fresh Release self-emit clean; gate steady at three groups.

- Task 010 — lambda definition placement and visibility; slice commit recorded
  in git ("Own lambda definition placement in N#").
  - Deleted C# owners: the non-capturing lambda placement decisions — visibility attribute
    literals, name+counter construction, synthesized-signature guards, value-type/ctor guard,
    type-parameter ownership decision, static-versus-this classification branching, and the dual
    sub-emitter constructions (unified). `ColumnarIlEmitter.cs` 21,164 → 21,150. The value-capture
    display-class path is a precisely-fenced residual pending ModuleBuilder/DefineType modeling.
  - Added N# owners: `ColumnarLambdaPlacementPlanner` — owning-type selection, generated method
    identity, exact visibility (assembly-static for verifiable cross-type ldftn), signature
    validation, and the physical DefineMethod, consumed mechanically by the emitter.
  - Evidence: byte-identical IL across all three product reproducers (which run correctly and
    ILVerify clean; the historical cross-type MethodAccess shapes are confirmed fixed); new
    lambda-placement product project 9/9 registered in the ilverify gate; 625 BootstrapServices
    contracts; 3,182/3,182 units; fresh Release self-emit clean; gate steady at three groups
    (013/014 iterators, 011/012 ilverify).

After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.

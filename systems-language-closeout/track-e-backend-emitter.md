# Track E — N# lowering, binding, metadata policy, and mechanical emit host

**Live status (amended at `1bb109831`, 2026-07-09):** E0's first versioned N# code plan is now
production-routed and directly executed by N# for boolean literals; the replaced C# emit/type
branches are deleted. `399008ea9` range/index C# decisions and assertions remain the immediate
migration debt. Their recursive child-expression sequencing must move into N# before deletion;
a C# callback or replayer is not an allowed shortcut. No new or expanded C# is permitted: every
older instruction below that names a C# replayer, test, seed, whitelist, callback, adapter, or
differential harness is superseded by an N# owner and native `.tests.nl` evidence.

## Mission

Replace the handwritten C# emitter as a product-decision owner. N# must select:

- accepted syntax/fact shapes and hard declines;
- types, members, overloads, generic construction, and conversions;
- opcodes, operands, locals, labels, exception regions, and call forms;
- declaration/type passes, registry lookups, metadata shape, attributes, and entry-point policy;
- TypeRef contract owners and metadata patch operations.

Only a pre-existing, non-growing C# host may survive when it:

- stores external Reflection.Emit/PE handles N# cannot represent;
- invokes already-selected reflection members/builders;
- serializes/saves PE metadata and performs already-planned byte patches;
- passes data already available at an ecosystem boundary without selecting or classifying it.

Code-plan construction, validation, and execution are N# responsibilities. A surviving C# host
does not replay plan rows or provide callbacks into legacy lowering.

The host contains no name/type/kind/arity/overload/opcode/schema/tie-breaking decision. It is
listed path-by-path in `memory/architecture.md#non-nsharp-survivors` at closeout.

## Ownership invariants

- `OpCode.Value` is the wire id; never positional reflection order.
- Parser node kinds come from the one live ledger in
  `CompilerServices/ColumnarParserKernels.nl`; never duplicate or reserve fixed ordinals here.
- User-defined type shadowing wins before BCL/external lookup.
- BCL binding preserves the language's proven exact-match/allowed-conversion rules; do not gain
  C# overload semantics accidentally.
- Builder-bound closed generic members use the correct rebinding mechanism; plain reflection on
  `TypeBuilder`-backed constructed types is a known crash surface.
- Unexpected host/replayer holes throw. Unsupported language shapes produce a stable, attributed
  decline only at an N# decision point.
- A construct has one owner at a commit boundary. N# “not mine” may route to a not-yet-ported C#
  branch temporarily, but a ported construct's old branch is deleted in the same commit.

## Standing harness

- Focused: `./scripts/dev.sh Columnar`, CompilationBackend, the exact new kernel suite, and
  `./scripts/dev.sh --since` for shared changes.
- Successor proof: before deleting a family, run native N# contracts and production-path persisted
  execution over the same behavior and edge-value inventory, then inspect emitted IL/metadata as
  applicable. No force-old route, C# differential harness, or callback may be introduced.
- Persisted reload is mandatory for Reflection.Emit handles, byref returns, generic constructed
  members, and metadata changes. A runtime-only in-memory call does not prove persistence.
- Run IL verification whenever instruction/metadata/save mechanics change.
- Execute adversarial values, not only exit codes: partial initialization, early return, wrong
  types, NaN comparisons, hashing/equality, shadowing, generic instantiations, and exception flow.
- Run the Systems performance gate only for SIMD/hot-path stages, cool and serially.
- Use fresh non-VS-Code product gates at SDK/repin/broad emitter checkpoints. The IDE gate is
  required only when an E change also alters an IDE-reachable surface under the repository rule.

## Plan contract

`ColumnarCodePlan.nl` is a versioned N# SoA model. Schema v1 deliberately admits exactly one
operand-free boolean constant instruction and uses the actual signed `OpCode.Value`; it does not
advertise future rows or pools. Later schema versions must grow construction, validation,
execution, and invalid-row tests atomically to include, as their owning slices require:

- instruction rows keyed by ECMA opcode value;
- explicit operand kinds for scalar constants, strings, args, locals, labels, switch tables,
  selected types/methods/fields/constructors, and declaration/metadata operations;
- N#-selected handle pools carried through the existing product interop path;
- local and label declarations;
- explicit exception-region operations (`BeginException`, catch/finally/fault/filter as supported,
  `EndException`) with a documented ILGenerator auto-leave contract;
- one plan unit per emitted/synthesized method when closures/async/type passes require it.

N# plan execution predeclares locals/labels, maps opcode values, replays rows, and invokes selected
handles through the existing product interop path. Unknown ids throw. No
`ColumnarPlanReplayer.cs`, equivalent C# bridge, feature seed, or whitelist may be created. If an
external API shape is not callable from N#, extending N# interop/emission and pinning it with native
N# tests is the prerequisite.

## Remaining waves

### E0 — ratchet foundation and first vertical deletion

Start immediately after the recorded Track A handoff; do not wait for binder/registry work.

1. Finish the N# plan model and N# executor with native schema-integrity and invalid-row throw
   tests.
2. Add N# fragment planning before the legacy dispatch.
3. Port one complete reflection-free family (for example scalar literal/unary/binary fragments)
   whose C# decision branch can be deleted atomically. N# owns constants, promotions, opcodes,
   and result types.
4. Prove behavior with native N# successor tests, persisted execution, and IL verification; delete
   the old branch and its C# assertions. Do not add a force-old hook or C# differential harness.
5. Replace the `399008ea9` range/index assertions and lowering decisions with gated native N#
   tests and N# plan ownership, then delete the introduced C# branches and assertions.
6. Add an N#-owned ownership-ratchet audit/allowlist covering all product-adjacent languages. A
   shell/build entrypoint may invoke it mechanically but may not own classifications.

Progress at `1bb109831`: the deliberately narrow boolean portions of items 1–4 are implemented
and focused-proven. Seven schema/planner contracts and five persisted production tests pass; the
old boolean branches are gone. The native gate runs 58 tests and rejects empty/inconsistent
results before caching. The full checkpoint still has the separately inventoried four blocker
buckets, so E0 is not complete. Item 5 is next and must first solve recursive child-fragment
sequencing in N#; item 6 remains.

Beyond the exact range/index migration debt named by E0, general member, index, and call families
do not belong in this foundation slice. Any handle capability range/index needs is implemented
and proved in N# without broadening the accept set. Prior commits showed that a Span claim did not
cover persisted ReadOnlySpan byref-return handles; do not generalize from it.

### E1 — Reflection.Emit and persisted-handle capability matrix

Probe every host shape required by plans: opcode/label structs, locals, method/field/constructor
handles, type/module/method/constructor builders, attributes, generic member rebinding, byref
returns, exception regions, and persisted save/reload.

For each shape record one outcome:

- directly callable/storable from N# with persisted proof; or
- directly executed by N# through an existing, non-growing mechanical boundary whose exact
  survivor classification is recorded.

There is no third route that adds a feature-specific C# whitelist. A claim covering a family has
a test for every advertised receiver/handle shape.

### E2 — N# BCL/external member binder

Create one N# binding owner for static, instance, property, and allowed external members. N# owns
allowed assembly/type surface, user shadowing, candidate filtering, exact parameter/return gates,
generic substitution/rebinding, preflight type matching, ambiguity, call form, and decline reason.

If N# cannot enumerate reflection candidates, C# flattens raw `MethodInfo`/type facts only. N#
selects the handle and records it in the plan. Delete handwritten member clauses family by family;
every exceptional host arm needs a mechanical-boundary proof and a pinning test.

Prove generalization by supporting several already-documented APIs with no C# emitter edit. Pin
shadowing, ambiguity, unsupported result, byref, generic, and no-unintended-widening behavior.

### E3 — definitions, registry, and type resolution

Move the remaining C# definition models to N# slot classes. Port alias registration, inheritance/
interface chain lookup, member/constructor/property slots, cycle/depth facts, type admission,
canonical type resolution, builtins/external seeds, arrays/byref/nullable/tuples/delegates,
closed user generics, and structural type equivalence.

C# supplies a data-only Type/assembly/open-generic seed. An `if` keyed on a name/type in the seed
is policy and belongs in N#. Preserve nearest-declaration and user-shadowing rules with direct and
executed tests.

The interface declaration pass depends on the N# definition model: definition model first,
interface pass second. Do not follow the old numeric order that inverted that edge.

### E4 — lowering-family deletion waves

Grow the plan and delete old branches in bounded commit units:

1. procedural/control-flow/scalar core;
2. member access, writes, indexing, arguments, conversions, and calls (after E1–E3);
3. construction, constructors, records, unions, patterns, and match;
4. strings, concatenation, interpolation, and tuple-name metadata;
5. local functions, lambdas, closures/captures, async and synthesized methods;
6. SIMD shape selection and calls;
7. declaration/type passes, parameter/default/custom-attribute metadata, entry point, and final
   pass driver.

Each unit names the exact C# methods/branches deleted, direct N# owner, differential corpus, edge
values, and checkpoint. Broad waves may use several commits; no construct stays dual-owned after
its commit.

Accept-set lifts (generic records, nested user generics, new collection heads, richer test
metadata, etc.) are demand-driven product slices through these N# owners. Revalidate former
“permanent decline” claims against current language contracts; do not preserve a July 2 list as
design and do not widen behavior accidentally during a parity port.

### E5 — TypeRef scoping and Cecil retirement

Pin main/reference, exe/library, and C# ProjectReference consumption. C# may scan metadata into
flat facts; N# chooses contract assembly owners, tie-breaks, versions, and exact TypeRef patch
plans. The PE host applies validated offsets/rows mechanically.

Land the emitter-side fix while the current Cecil compensation remains as a no-op oracle. Prove
repeatable metadata serialization or take an explicitly tested fixed-fact fallback. Then delete
Cecil code, package references, and SDK payload; repin and build from clean; run IL verification
and the fresh product gate.

### E6 — host and ownership closeout

Delete the remaining old dispatch, binder, resolver, registry, pass, SIMD, closure, and lowering
bodies. Rename/split the host if that makes the mechanical boundary explicit. Update the ratchet
allowlist and the survivor inventory with exact paths and forbidden responsibilities.

Compare representative metadata surfaces with MetadataLoadContext, run the dynamic product
corpus and native tests, execute every runnable product, run IL verification/performance evidence,
and take a fresh product gate.

## Cross-track contracts

- A supplies current product-gate blockers and consumes the N# plan route; it no longer owns the
  C# emitter after the handoff.
- C owns the parser/node ledger; E consumes it without a second ordinal table.
- D supplies canonical type/symbol identity and semantic front-door checks. E must not silently
  accept a shape the Analyzer rejects.
- B/D share metadata/package policy; E owns emitted member/type selection, not CLI resolution.
- H's final audit classifies the plan replayer, seeds, and PE host; it does not waive decisions
  because they use Reflection.Emit.
- SDK repins are announced shared-state changes and invalidate concurrent gate evidence.

## Prohibitions

- No fallback emitter, force-old production flag, or fault-to-decline conversion.
- No C# general binder, name/member whitelist, typeref owner policy, or opcode selection.
- No C# callback/delegate into an N# kernel.
- No plain reflection lookup on builder-bound closed generic members.
- No positional opcode ids, duplicated node-kind map, or stale fixed ordinal.
- No compile-only deletion evidence and no unpersisted Reflection.Emit capability claim.
- No open-ended accept-set work before E0 and no feature-specific C# growth after the handoff.
- No full-gate batching of unrelated lowering families.

## Exit criteria

- [ ] E0 N#-owned ratchet guard is committed; subsequent emitter C# growth is forbidden.
- [ ] N# binder/type resolver/registry/type passes own all member/type/metadata decisions.
- [ ] N# plans own every opcode/operand/local/label/exception/conversion/call/lowering decision;
      every ported C# branch is deleted.
- [ ] Replayer/seed/save/patch host contains decoding and external API mechanics only and throws
      on unknown operations.
- [ ] Persisted-handle, generic, byref, metadata, execution, ILVerify, and SIMD performance
      evidence is green.
- [ ] TypeRefs are correctly contract-scoped and Cecil is absent from source/package payloads.
- [ ] Dynamic product corpus/native tests and fresh product gate are green.
- [ ] Exact mechanical survivors are recorded in the durable inventory and enforced by the
      ownership-audit allowlist.

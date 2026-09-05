# Contingent S2.2(i): complete record synthesis with consumed structural type rows

Planning only, pinned to h product `47d0a062d7427eac6c825d921247714b418b64cd`. The h gate now passes at `e170415204`; its documentation-only acceptance follow-up precedes execution. The 19 copied source/doc files and unapplied boundary are hashed in `/private/tmp/nsharp-s22i-next-cut/manifest.json` (SHA256 `2b628757dee1139cc12641326cdc033f499f255f68e13410c04a345aa351e1af`). Revalidate against the accepted tip; this h follow-up changes the two ledger documents but no planned product/test source. No i product edit, build, test or SDK action was performed for this assessment.

Recommend the connected **record PASS 0e owner plus its five type-pool consumers**, rather than another constraint-map prerequisite. The existing `ColumnarRecordValueMemberPlanner` already owns the three bodies, and `ColumnarStructDef` owns authoritative Equals/GetHashCode declarations. C# still owns which records/members receive them, when each builder/body is created, and the clone declaration. Moving that complete driver into the existing N# planner while switching its five AddType sites to the existing keyed overload makes direct writer progress with real C# deletion. It does not pretend to migrate argument admission, generic constraint construction, method/field pools, ambient locals or maxstack.

## Exact consumed boundary

At the pinned `src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs`:

- Replace PASS 0e loop **3790–3814** with `ColumnarRecordValueMemberPlanner.EmitRecordValueMembers(structs, structDefsInOrder, typeResolutionCatalog.StructuralTypeReferences)`.
- Delete `SynthesizeRecordValueMembers` **8018–8035** and `SynthesizeRecordCloneMember` **8037–8053**, together with their attached moved-policy comments beginning at 8009. Their only callers are the PASS 0e branch and the value-member helper's final clone call.
- The retained unapplied C# diff removes **70 total lines / 66 nonblank / 3,479 bytes**, including the moved comments and separator blanks, and adds the two-line direct invocation. Both removed helpers disappear; no C# callback or remaining alternative synthesis driver.

Proposed N# door: `EmitRecordValueMembers(IReadOnlyList<ColumnarStructInput> structs, ColumnarStructDef[] definitions, ColumnarStructuralTypeReferenceTable table)`. It borrows the actual ordered inputs without copying. Keep the loop and its policy together. Add a table parameter to the existing BuildEqualsPlan/BuildGetHashCodePlan/BuildClonePlan signatures; those three methods have only these current C# product callers, so no compatibility wrappers are required by the inspected call graph.

The existing N# declarations at `ColumnarDefinitions.nl:476,494` must remain the sole Equals/GetHashCode signature/registry owner. Reuse them directly. Move the current clone DefineMethod call as written into N#, including attributes **Public|HideBySig (134)**, exact `def.Builder` return and actual BCL `Type.EmptyTypes`. Do not infer a Virtual bit from the old comments: current clone declaration does not supply it. Retain the existing clone registry assignment phase.

## Structural consumer and lifetime

The catalog is constructed at C# **3110**, before PASS 0e. `ColumnarSemanticTypeRegistry.nl:1173–1176` registers every exact source struct key and its original builder into the catalog's single structural table. The PASS 0e door can receive that existing table directly; there is no new registration or catalog snapshot prerequisite.

At each former AddType site in `ColumnarRecordValueMemberPlanner.nl`, select and consume immediately:

| Existing site | New selected identity | Consumer |
|---|---|---|
| 41, 103, 145: record builder | `table.SelectSourceDefinition(def.DeclaredTypeName, recordType)` | Equals isinst/unbox/local/this; Hash this; Clone castclass/this |
| 43: object | `table.SelectRuntimeType(actual typeof(object))` | Equals argument 1 |
| 105: int | `table.SelectRuntimeType(actual typeof(int))` | Hash accumulator local |

Use `plan.AddType(selected, table)` and the unchanged independently retained runtime companion. Selection occurs at those former AddType points after the existing RequireRecordDef/PrepareMethodBody phases, not in the outer loop or before the member is known to need synthesis. No table selection on ordinary classes, generic records, already-owned members or skipped clone paths. Do not share one selected result across separate method builds merely to reduce allocations.

The keyed AddType/ValidatedTypeAt machinery already exists at `ColumnarCodePlan.nl:899–926`; table provenance checking already occurs through the executor before emitted rows. No new structural schema is required for nongeneric source records plus object/int. The corrected earlier census is 36 AddType calls in 12 files, one keyed/35 legacy; changing these five existing sites would yield **six keyed/30 legacy**, without changing the call count. This is a projected census, not an executed result. Member and field pool handles remain a separate later boundary.

## Exact phase and mutation behavior

1. Read live structs.Count each iteration, then structs[s], then `st.IsRecord`. Only a record reads definitions[s]. Skip whenever `def.GenericParameters != null`, including a nonnull empty dictionary. Do not substitute Count>0 or read `def.IsRecord` in place of the input selector.
2. Walk the actual FieldOrder and Fields in order. Read each FieldBuilder.FieldType and call existing N# ContainsBuilderBoundType, breaking at the first true. This includes nested builder-bound collection fields; a CoreLib module test is not equivalent. Preserve disposal/exception behavior of the original array iteration; do not build an eager field fact array.
3. Baked-field route checks Methods.ContainsKey("Equals"), declares/registers Equals only if missing, **builds its complete plan before GetILGenerator**, then executes it. Only after success does it check/declare/build/execute GetHashCode. Only after that does clone processing begin. Read mutable Methods/RecordClone at their existing phases; do not choose all members up front.
4. Builder-bound fields skip Equals/Hash and still enter clone processing. Clone skips when !IsReference or RecordClone is nonnull. Otherwise DefineMethod precedes BuildClonePlan, which precedes GetILGenerator and Execute. `def.RecordClone = clone` occurs only after successful execution. Equals/Hash registration, by contrast, occurs in their existing Define helpers before body construction. Preserve that asymmetry.
5. Reuse existing body/reflection helpers unchanged: RequireRecordDef, comparer definition/member lookup, MemberwiseClone lookup, code-plan ordering and executor validation. Do not reflect signature facts from newly created MethodBuilders. A new structural-table mismatch may reject at its actual AddType phase; pin that invariant boundary instead of claiming every malformed-table exception is historical. Never prevalidate every record/member/table before earlier valid members have progressed.

## Why map construction and call admission wait

`BuildGenericInterfaceConstraintMap:17161–17176` is a consumed C# producer but **not a dependency of record synthesis**. Its only producer call remains 4256; shared-empty dictionary storage remains 299–300 and constructor fallback 243. It can be a later coherent closure with its shared-empty identity, lazy allocation, minimum-length loop, duplicate-key overwrite, exact array retention and null-row timing. It need not be moved before this writer consumer. Combining it here would be unrelated ratchet payment.

The h-plan warning still holds at the new offsets: instance selection **17218–17312**, closed constrained selection **17178–17216**, argument matching **17314–17371**. Six chain callers remain 8903/14994/15216/15231/16629/16652; the last two include the combined duplicate-builder scan that must continue after failed member selection. The matcher still depends on addressability, contextual lambdas/local functions, target-typed new, collections/arrays, recursive preflight and conversion paths. Existing N# SelectLocalInstance scores/fences candidates, whereas this C# owner accepts a sole arity without matching and rejects multiple compatible candidates without ranking. No callback or eager argument matrix makes that an equivalent bounded port. Those policies remain explicitly outside this proposed cut.

## Bounded execution prerequisites and controls

First prove the exact N# driver surface under the accepted seed: IReadOnlyList<ColumnarStructInput> plus definition array, original DefineSynthesized* calls, clone DefineMethod with 134/Type.EmptyTypes, builder GetILGenerator, existing executor, and source/keyed AddType path. Use a real nongeneric reference record definition registered in a fresh table and execute all three bodies. Do not add a C# bridge or call the old C# driver if the N# surface refuses. A missing admitted spelling/capability is a measured prerequisite and requires re-scope before implementation expands.

Direct contracts should pin:

- ordinary-class and generic-record skips, including nonnull-empty GenericParameters, with no structural rows created;
- runtime-field reference/value records; direct and nested-collection builder-bound fields; first failing field/order behavior;
- user Equals/Hash ownership independently, both present, pre-existing RecordClone, and reference-vs-value clone selection;
- declared method flags/order and exact registry/builder identity, especially clone bit134 and its delayed RecordClone publication;
- all five expected plan type entries are keyed to the exact same table, source owner names remain distinct across namespaces/emissions, and independently corrupting a runtime companion rejects before any IL in that plan; existing structural pool controls are reusable;
- a valid first record followed by a failing later record retains the first record's methods and working bodies, using a baseline-reachable malformed second input with a successful twin. Do not assert universal per-member fault progress from a parse refusal or invent a byte-count witness. A missing source registration/table control can separately observe declaration-before-plan rejection, explicitly as a new invariant boundary.

Reuse `ColumnarSynthesizedRecordDirectCall.tests.nl` for authoritative synthesized method facts and `ColumnarRecordValueMemberFacts.tests.nl` for typed row/executor semantics. Neither currently proves the complete PASS 0e policy or all five structural consumers. Reuse native `record-with` for reference/value/positional record copy behavior and actual clone presence/absence. Add native Equals/hash/user-override and builder-field skip controls with emitted metadata and actual execution. Compare the immutable pre/post normalized PE and runtime output; a predicted one-key/runtime-pair mutation should make a named direct control fail while the untampered twin succeeds. No current plan claims these new controls ran.

Stop/reassess if the table is not registered at the real caller, a copied/eager signature or field matrix is proposed, a raw MethodBuilder signature read appears, the clone's flags/registration phase changes, keyed rows fail legitimate source definitions, the N# driver requires callbacks, or unrelated C# deletion is used to justify growth. Keep h acceptance separate and revalidate this draft before starting i.

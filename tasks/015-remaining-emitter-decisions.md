# 015 — Remaining emitter decisions

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Execute a substantial coherent compiler ownership area under `tasks/README.md`: complete methods,
classes or connected method groups with necessary helpers and state. Continue through integration;
do not stop at planning, scaffolding, prerequisites, parity results or a tiny extraction.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Existing C# may only shrink, route mechanically to N#, or be deleted.
- Implement all new behavior and canonical tests in N#.
- Before editing, identify the complete C# method groups, helpers, state and assertions this area deletes.
- N# must become the direct production owner. Leave no legacy fallback, shadow implementation,
  comparison route, or duplicated semantic authority for the migrated behavior.
- Tests migrate with the behavior; do not defer them.
- Missing N# prerequisites are part of this sub-slice; continue through production deletion.
- Move necessary proven dependencies with callers; finish the selected area through named C# deletion.
- Follow `AGENTS.md`: focused evidence, required integration/IDE gates, selective staging, an
  `Evidence:` commit, ledger updates, required clean repin, and a clean working tree.
- Report only after this sub-slice is complete, with exact code deltas and evidence.

## Selected area: complete ColumnarIlEmitter

At the accepted input-builder checkpoint `15540cf42`, move the complete remaining emitter class:
16,635 C# lines, 67 fields, one private constructor and 295 methods. Preserve its accepted N#
binding/planning owners and Runtime dependencies. This class has no dependency on another surviving
Compiler C# type; all 116 referenced compiler types already reside in BootstrapServices.

The original field count includes five private integer constants. Their symbol-resolved literal
inlining is an accepted source-equivalent translation: preserve all five values and every resolved
read, and document the removed private literal metadata. The remaining owner has 62 runtime fields;
preserve their types, initialization order, sharing and visibility. This does not require a new
constant-field language feature.

Move the complete stateful owner to N#, delete ColumnarIlEmitter.cs and route the existing
MultiFileCompiler call directly to its N# entry. Review minimal cross-assembly type/entry visibility;
keep construction and private helpers nonpublic. Preserve initialization, reflection resolution,
reference/metadata identity, evaluation and emission order, ref/out failure state, diagnostics,
exceptions, generated IL and artifact behavior. Do not replace Reflection.Emit with a new metadata
writer unless actual compiled source proves a necessary dependency.

Materialize and compile the actual complete proposed N# class as the primary capability proof.
Repair only demonstrated prerequisites in N#, grouping related prerequisites where feasible.
Faithful equivalent source is permitted when it preserves behavior. Verify all emitted owner methods
with ILVerify; a successful compilation alone is insufficient for ref/out and closure lowering.

Migrate eight existing native emitter reflection lookups to BootstrapServices, preserving signatures,
flags and assertions. Also migrate the complete connected 53 compiler-facing C# canonical cases:
46 compiler-facing facts in CompilationBackendTests (including record-struct structural equality), all five ColumnarDeclineDiagnosticsTests
and both PreprocessorConditionalCompilationTests. Preserve public pipeline calls/options, every
assertion, subprocess/output/error behavior and cleanup; keep CLI-command policy facts separately.
These active tests assert compiler behavior even without naming the emitter directly. Delete their
replaced C# methods/classes and only helpers no longer used by surviving tests. Add focused
ownership/failure regressions only for real gaps. Reuse accepted coverage and use dev.sh during implementation. Root owns ratchet retirement, review, fresh backend
gate, any verified SDK publication, acceptance record and push. This emitter-only area is backend-only.

Move the complete MultiFileCompiler after this dependency is integrated, with its helpers and state.
That later area affects CompileForAnalysis and requires the IDE-enabled gate plus real-editor visual
verification. Do not hide the dependency with callbacks, split validation ownership, or resume held
CLI/editor feature branches. Task 015 remains open until the complete emitter is N#-owned and the
selected area has passed review, required checks, commits and push.

## In-flight evidence (2026-09-08; not ownership acceptance)

All 53 translated canonical cases pass against the existing compiler: 45 MultiFileCompiler cases,
record-struct equality, five decline-diagnostic cases and two preprocessing cases. Root verified
53 distinct passing results with no skipped cases and independently rehashed all 112 runtime-written
fixtures against the original C# fixture bytes. Source sets and explicit file orders match.
The complete assertion review preserves all 178 original Assert invocations through 40 shared-helper
cases and 13 custom cases. Root separately checked all 40 helper output policies and expected values.
Review corrected delimiter-newline differences and restored exact diagnostic-code equality where a
substring predicate had weakened the original assertion; the corrected focused case passes.
Evidence: `/private/tmp/nsharp-columnar-il-emitter-tests-20260908/canonical53-assertion-fixture-mapping-r1.json`
and `root-canonical53-fixture-baseline-acceptance.json` in that directory. This accepts baseline
assertion/fixture equivalence only; the final C# deletion diff and replacement-emitter execution remain
required before accepting the migrated area.

The full proposed N# emitter is materialized but has not compiled successfully. Parser reductions
and formatter-clean method fragments are translation evidence only. Neither baseline test results
nor operation-count parity proves that the replacement emitter works. Required next evidence is
the compiled complete owner, all-method IL verification, candidate execution of the canonical and
native suites, legacy-owner deletion, and the fresh integration checkpoint described above.

The assembled candidate now passes kernel parsing with 299 methods and 62 runtime fields
(`full-kernel-runtime-r75.log` in the emitter evidence directory below). Whole-source emission still
declines. Scratch compilation preserves the failure with stubbed method bodies; method signatures
alone and the first 35 fields reach later body emission. The first argumented static initializer
introduces the earlier failure. Inspection of the actual input rows confirms that all eleven
SIMD/ValueTuple helper initializers are rejected by the existing N#
`ColumnarStaticFieldInitializerEmitter.TryParseParameterlessStaticInitializerCall`; the three
parameterless collection helpers pass. `TryEmitAll` returns false before ordinary body emission.
This established the dependency on connected N# static-initializer helper-call parsing, resolution
and argument emission. No per-field wrapper, C# callback or fallback is an acceptable substitute. Evidence:
`/private/tmp/nsharp-columnar-il-emitter-owner-20260907/silent-exit-audit/rowdump-current-r3.log`
and `declaration-bisect-r2/` in that directory. Reduced-source results establish localization only;
the complete class must be rebuilt and verified after the prerequisite.

That prerequisite is integrated in `38c900aff` and `a6550b612`. The N# owner now resolves and emits
the required single string/`nameof` argument while preserving parameterless behavior, overload
order, rejection before IL emission and meaningful failures. Canonical N# assertions pass 8/8;
the existing native initializer family plus the new regression passes 3/3. The byte-identical
ordinary source probe fails with the previous private compiler and succeeds with the replacement.
The private production BootstrapServices payload (`412d6b412ac21d0d5b6825d4bdd375b3192361b7a2a49d46109716c99bae4295`)
contains no `NSharpTests` metadata and passes unfiltered IL verification of all 1,227 types and
10,535 methods. Final evidence:
`/private/tmp/nsharp-columnar-il-emitter-owner-20260907/static-initializer-argument-seed/final-receipt.json`
(SHA-256 `cc53296864b8d848a68b9c417e4997b3c3e1713a577302a8b9cf9cf8f5acd090`).
This is prerequisite acceptance only: the full emitter is still being compiled, and shared SDK
publication, whole-owner canonical execution, legacy deletion and integration checks remain pending.

The demonstrated `Array.Empty<byte>()`, `Array.Empty<Type>()` and `Array.Empty<Type[]>()` dependency
is integrated in `dc02a272a`. Its N# binding/planning tests pass 12/12, the native Array.Empty family
passes 4/4, and the three byte-identical source probes that failed on the installed SDK now compile
and pass all-method IL verification with the private candidate. This is focused prerequisite
acceptance, not SDK publication or emitter ownership acceptance. Evidence is under
`/private/tmp/nsharp-columnar-il-emitter-owner-20260907/array-empty-byte-type-seed/`.

A separate unfiltered check of all 10,529 BootstrapServices methods found two existing IL errors in
`AnalyzerMetadataAssemblyResolver`'s constructor, reproduced against both the installed SDK and the
private candidate. The emitted call targets `Object::.ctor` despite the external
`MetadataAssemblyResolver` base. `ColumnarConstructorDeclarationPlanner.EmitCtorBaseChain` ignores
the recorded external `ExactBaseType` when `BaseDef` is null. The N# constructor-chain fix is
integrated in `34459dd88`: source-base ordering and failure behavior are preserved, while implicit
external chains select an accessible parameterless constructor or decline before declaration/IL.
Eight canonical tests and both affected native families (4/4 and 20/20) pass. A private second-stage
self-rebuild emits the correct external constructor call and passes unfiltered IL verification of all
1,227 types and 10,531 methods. This repairs the findings rather than accepting a baseline exception;
the fresh integration gate and SDK publication remain pending with complete emitter integration.
See `/private/tmp/nsharp-columnar-constructor-base-correctness-20260908/final-receipt.json` and
`root-stage2-review.json` there, plus the original `root-external-base-constructor-finding.json` in
the prerequisite evidence directory above.

The exact `MethodBuilder.SetParameters(Type[])` dependency is integrated in `c580a102c`.
Its canonical N# assertion passes, and the same complete emitter source with the same 170 references
advances past the original call failure using the verified private candidate. The final receipt is
`/private/tmp/nsharp-columnar-il-emitter-owner-20260907/set-parameters-prerequisite-final-receipt.json`.
Use its verified r3 payload; the earlier r2 payload reintroduced invalid external-base constructor IL
through a stale bootstrap and is withdrawn.

The `List<T>(Dictionary<TKey,TValue>.KeyCollection)` snapshot dependency is integrated in
`0810c36af`. It selects the exact CLR `IEnumerable<T>` constructor through the existing N# argument
planner, preserving constructor semantics and the original key snapshot. Three canonical assertions,
the populated snapshot regression and all 41 native reflection-bootstrap tests pass. Both the private
production payload and emitted native assembly pass unfiltered IL verification. Evidence is under
`/private/tmp/nsharp-columnar-il-emitter-owner-20260907/body63-list-copy-seed/`.

The complete 53-method calls/conversions group is reviewed for assembly into the emitter. Its actual
no-stub diagnostic composition advances through those bodies, and review corrected split boxed
enumerator state and restored constructor-list enumeration semantics. The accepted fragment is
`bcl53-complete-compile-r2/section-bcl-calls-conversions-compiled-r3.nl` in the emitter evidence
directory; r2 is withdrawn. This is not whole-owner acceptance. The remaining entry, body and
constructor/member-write groups, demonstrated tuple-job dependencies, final canonical execution,
legacy deletion, fresh integration gate and push remain part of this same selected area.

The exact `MethodBuilder.DefineGenericParameters(string[])` dependency is integrated in `35a3ad9e2`.
Three canonical N# tests pass; the actual entry source advances past the previously unmodeled call.
Evidence: `method-generic-parameters-prereq/final-receipt.json` in the emitter evidence directory.

Builder-bound tuple job storage is integrated in `0ab3f4a8d`. The existing N# type admission,
construction planner and runtime field resolver now own exact CLR ValueTuple shapes containing live
source reference types, including the explicit ValueTuple8/ValueTuple2 Rest layout for nine-element
jobs. Original tuple storage and argument order remain required; parallel-list substitutes are not
accepted. Six canonical N# tests and all 42 native reflection-bootstrap tests pass. The native witness
uses source classes, MethodBuilder, Type and dictionaries and checks every stored field. Identical
source fails with the prior private compiler and passes with the replacement. Production and native
assemblies pass unfiltered IL verification; production BootstrapServices contains no NSharpTests class.
Root verified all eight committed source hashes and all 14 private payload hashes, and ran
`./scripts/dev.sh ValueTuple` successfully. The canonical/native counts come from their separate
nonzero runs, not the dev.sh legacy harness. Evidence:
`/private/tmp/nsharp-columnar-il-emitter-owner-20260907/tuple-key-enumerator-seed/tuple-final-receipt.json`.

The executable `PersistedAssemblyBuilder.GenerateMetadata` binding is integrated in `16cefead0`.
Its canonical N# test verifies the exact receiver, two out BlobBuilder parameters and metadata return
type. The actual emitter source advances through that call; production IL verification passes.
Evidence: `generate-metadata-prereq/final-receipt.json` in the emitter evidence directory.

The exact `OpCodes.Constrained` field admission is integrated in `fa4eefbab`. Its canonical N# test
passes, and the actual constrained-call method advances past the field failure with the private
candidate. All production types and methods pass unfiltered IL verification. Evidence:
`constrained-prereq/final-receipt.json` in the emitter evidence directory.

Concrete dictionary key enumeration is integrated in `3ed8348b8`. The N# type planner and runtime
member resolver admit the exact BCL KeyCollection enumerator and resolve its closed Current property.
Four canonical assertions, the byte-identical originally failing source, two focused native tests and
all 129 tests in the native columnar-emit-facts verification project pass. Production and native IL
verification pass; emitted code uses one addressable struct local for MoveNext, Current and Dispose,
including disposal in finally and dictionary mutation failure. Root verified committed source and
private payload hashes. Evidence: `keycollection-enumerator-seed/keycollection-final-receipt.json`
in the emitter evidence directory.

These private candidates have different source bases: the key-enumerator candidate includes tuple
support but predates GenerateMetadata and Constrained. The entry owner must build a combined payload
before claiming complete emitter compilation. The original tuple constructor candidate lists are
restored in the constructor/member-write group; scratch bypasses remain diagnostic evidence only.
Complete entry/body/suffix compilation, canonical execution through the new owner, C# deletion, the
fresh integration gate and push remain pending. No shared SDK seed has been published for this work.

The connected `Ldobj`, `Stobj`, `Stind_Ref` and `Bge` dependency is integrated in `9a30ab9e6`.
Two canonical N# tests verify exact CLR fields and Type, no-operand and Label emission signatures.
The combined private candidate includes the accepted List snapshot and dictionary key enumerator
changes; its production build, focused dev.sh run and unfiltered IL verification of all 1,227 types
and 10,540 methods pass. Root verified two committed source hashes, 24 evidence files and 14 payload
files. Earlier candidate-r3 omitted the List snapshot source and is not a combined-body candidate.
Evidence: `ldobj-stobj-prereq/final-receipt.json` in the emitter evidence directory.

The complete 63-method body fragment through r49 is source-reviewed for assembly, retaining all five
original Bge sites. Review restored the original Public|Instance tuple-field lookup: baked tuple
namesake admission means a public static field must not become eligible. The corrected reduced-source
run has no decline diagnostics but still reports directEmitted=False; this is not an emitted-assembly
or whole-owner acceptance result. The full emitter must supply compilation and IL evidence.
Fragment: `body63-current-compile/section-body63.final-r49.nl` in the emitter evidence directory,
SHA-256 `e6aa206d7abfddabceb9806e468a3cbdf2d546473ad59d54b66bcedbd2505a01`.

The remaining `Blt` and `Bne_Un` field dependency is integrated in `16515387c`.
An inventory of the complete emitter found 92 distinct opcode fields; these were the only two still
missing. The canonical N# assertion passes, the production assembly contains no test types, and all
1,227 types and 10,540 methods pass unfiltered IL verification. The byte-identical conditional source
and both direct opcode variants advance past array-list-pattern emission to a later expression
failure. Root verified 21 receipt artifacts, committed source hashes and candidate payload hashes.
Evidence: `branch-opcode-prereq/final-receipt-r1.json` in the emitter evidence directory.
The combined private candidate has BootstrapServices SHA-256
`073c4335d0299313676cea589e916f5f90bbbf515f763241352925b3258c969f`.

Expression source review has accepted Core r11 and the other expression methods through r24.
The latter's temporary Core stub and opcode bypass are diagnostic-only; the original opcode
conditional must be restored under the combined candidate, and the real Core must be assembled
before any whole-owner acceptance. Source review evidence is
`root-expression-r11-r24-source-review.json` in the emitter evidence directory.
Complete emitter compilation, canonical execution through that owner, C# deletion, the fresh
integration gate and push remain pending. No shared SDK seed has been published for this work.

The remaining 37 expression helpers are source-reviewed and frozen for full-owner assembly in
`expression38-complete-compile-r1/section-expression38.production-r36.nl` (SHA-256
`ac0e2b4cfb45c67983a723d76d7a1a0767e347129f5ed73e897db2e72a32d411`). The insertable fragment
contains 38 methods because it retains the original reserved `EmitExpressionCore`; the owner must
replace that method with its reviewed complete implementation. Root verified six artifact hashes,
method order, byte-identical reserved Core, unchanged source outside the assigned group and the
restored conditional opcodes. The helper diagnostic run has no decline diagnostics but does not
emit an assembly. The restored-Core composition first declines inside the original Core.
Neither result is whole-owner acceptance. Evidence: `root-expression37-final-fragment-review.json`
and `expression38-production-r36-final-receipt.json` in that directory.

Canonical migration commits `976750a63` and `c98d53b9e` remain isolated until complete-owner
integration. The frozen final selection contains 87 unique N# tests: 53 migrated canonical tests,
30 direct emitter callers and four ownership/failure controls. Root verified the inventory hash
and all selected names against the emitted test inventory. The existing 53-test and populated-enum
baselines remain valid; pre-owner missing-type failures are negative routing evidence only.
The exact candidate command and 87/87 acceptance condition are recorded in
`/private/tmp/nsharp-columnar-il-emitter-tests-20260908/final-new-owner-selection-r1.json`.

Core r26 is source-reviewed for assembly. The complete emitter composition is byte-identical to
root's independent assembly (SHA-256
`90bcfca785b204780885afbfdff3db98b7ab1a22b5447a36dedc403f3578eaba`), retaining the accepted
body, expression-helper, calls/conversions and constructor/member-write groups. This full source
initially returned false without a trace. A benign replacement class emits in the same project and
candidate, and late diagnostic sentinels are reached, narrowing the failure to later emitter work.

Source audit and actual compilation identify the untraced reference-constructor validation as the
remaining failure at that checkpoint: six nonnullable fields relied on implicit CLR zero state.
Spelling those initial assignments in N# advances to a located `new Label()` constructor-body
failure. The exact Label default-construction prerequisite is being implemented in N#, using the
existing initobj construction plan; no validator weakening or C# behavior is permitted. A temporary
Label self-assignment is diagnostic-only and must be replaced before full-owner acceptance.
Evidence is in `whole-expression-assembly-r1/root-complete-r1-review.json`,
`silent-false-constructor-audit.json` and `root-explicit-zero-constructor-review.json` in the emitter
evidence directory. Whole-emitter assembly emission, IL verification and canonical execution remain
pending; no shared SDK publication or push is justified by these diagnostic runs.


Exact Label zero construction is integrated in `a900f9b61`. Root verified all 27 receipt/source
artifacts and 14 candidate payload hashes against immutable commit `9064ee0297`; the canonical
assertion passes 1/1, native reflection coverage passes 43/43, and production IL verification
passes all 1,227 types and 10,540 methods with no test types. Evidence:
`/private/tmp/nsharp-columnar-label-default-20260908/final-receipt-r1.json`.

The complete production emitter source now retains real Label construction and real Dictionary
copy construction (SHA-256 `f5416804be209fe48c4ec0de97d876c817339f4b7363e5efb58a9a4c82cead38`).
Root reviewed the complete constructor delta: six explicit CLR defaults, equivalent guarded async
initialization, and an erased Dictionary type alias plus ordered dictionary reuse/null/copy cases.
The actual 454-source run under the Label candidate advances to the exact
`new Dictionary<string, Type>(typeParameters, StringComparer.Ordinal)` expression.
Goodall owns that proven N# construction prerequisite in an isolated worktree; Hooke owns the
complete emitter, direct production routing, C# deletion and private build preparation. A scratch
source with Label and Dictionary bypasses emits, but is diagnostic isolation only and cannot
satisfy production acceptance. Evidence: `whole-expression-assembly-r1/r9-label-candidate.log`
in the emitter evidence directory.


The complete unmodified production emitter now passes direct emission under provisional combined
Label+Dictionary BootstrapServices `bd5d070395ac54512db3c6a10c0f80a362c164b2f0bdd270d94b2ca148880cec`.
Root verified the exact production source hash above, all 454 sources with the emitter first,
170 resolved references, `inputBuilt=True`, `directEmitted=True`, non-null output bytes and zero
decline records. Evidence: `final-owner-build/full-production-direct-r1.log`, SHA-256
`49dd47cc106c1e36c5a49bb3f7e8088b7587406fa451c3abd062ed88ae44b2ae` in the emitter evidence directory.
This is the first complete production-source emission result without diagnostic bypasses.
The saved assembly build, unfiltered IL verification, direct routing/C# deletion, canonical 87,
fresh integration gate and push remain pending.

The Dictionary prerequisite's exact canonical assertion passes 1/1 after using the existing generic
AST fixture. Its production build is clean, and the byte-identical minimal N# constructor source
builds. The earlier kind-0 generic-name fixture was malformed and is not a product failure.
The native regression fixture still needs emission/execution verification before final prerequisite
acceptance. Source and canonical review evidence:
`/private/tmp/nsharp-columnar-dictionary-copy-comparer-20260908/root-source-review-r2.json`.

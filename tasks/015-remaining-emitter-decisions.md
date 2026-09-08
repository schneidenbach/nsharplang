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

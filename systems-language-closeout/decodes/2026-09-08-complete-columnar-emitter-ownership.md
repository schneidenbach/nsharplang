# Complete ColumnarIlEmitter ownership — 2026-09-08

The complete emitter is N#-owned. `773dbf1ff` deletes the 16,635-line C# class and
introduces its N# replacement; `8ec52542b` contains the final formatted source.
MultiFileCompiler calls the N# entry directly through the existing project reference.
There is no C# emitter, decision callback, adapter, or fallback for this area.
Compiler-wide ownership remains open: the complete MultiFileCompiler is next.

The replacement preserves all 62 runtime fields, their initialization and sharing,
the private constructor, and the complete connected emission behavior. Five private
integer constants were inlined at their resolved reads with unchanged values; their
literal-field metadata is deliberately removed. The class is public and sealed; its
only public method is the seven-argument static entry, whose last two defaults are null.
All 62 fields and the 33-argument constructor remain private. Fourteen fields are
static and 51 are readonly. Existing N# planners and Runtime implementations remain.

The 53 compiler-facing C# canonical cases moved to N# in `e0236b87b`; the replaced
C# cases and unused helpers are deleted. Eight native reflection lookups now name
BootstrapServices directly. The exact 87-case final selection includes those migrated
cases, direct callers, ownership checks, and meaningful failure controls.
`f0220903c` covers the populated enum registry. `1f4dece3a` retires four audit rows;
the pinned epochs and other 377 rows are unchanged, and the ownership audit passes 18/18.

Actual complete-source compilation proved the required N# prerequisites, including
collection constructors/enumeration, builder tuples, Label initialization, metadata
generation, and the emitter's opcodes. No additional metadata writer was necessary.
`1076ec2a0` corrects two canonical expectations made stale by those admitted shapes.

Formatting exposed a real integration defect: the formatter removed `private` from
lowercase fields, although field emission requires that explicit bit. The rejected
candidate exposed all 62 fields. `6d8970fd5` fixes the N# field-formatting path and adds
N# source, idempotence, and emitted-metadata assertions without changing compiler
default visibility or other declaration formatting. Four focused canonicals and seven
native formatting tests pass. The final emitter differs in syntax only by formatting
and two redundant public modifiers; its complete extracted IL equals the accepted
private-field candidate. All-method IL verification passes: BootstrapServices
1,231 types / 10,849 methods and Compiler 8 types / 109 methods. Neither production
assembly defines NSharpTests; only BootstrapServices defines the emitter.

Fresh `./scripts/test-all.sh --commit` on `8ec52542b` passes in 595 seconds with IDE
tests enabled: 521 C# tests, 7,968 N# canonicals, 47 native-project entries, 36 VS Code
tests, 12 throughput cells, templates/examples, and IL verification of 68 assemblies.
The official local setup succeeds. Both feeds contain the same four final packages;
ten SDK payloads match Release and twelve cache entries match the packages. The SDK
SHA-256 is `526b67ff70309c649a1df435d470c36a0e736935f5f2a67eee26f6901c865d1a`.
An ordinary installed-SDK clean/restore/build freshly compiles all 805 N# files and
passes all 7,968 canonicals without SDK-path overrides. Installed `nlc` passes the
exact 87 emitter assertions. The formatter metadata test also passes using byte-identical
installed CLI files in the existing harness's required repository layout.
The final installed production assembly also passes unfiltered IL verification of all
1,231 types and 10,849 methods; it has no NSharpTests type and retains all 62 private fields.

The extension was rebuilt and reinstalled with `./scripts/reload-vscode-extension.sh`.
Visual VS Code checks retain lowercase, underscore-prefixed, and readonly private
fields, show zero diagnostics, and leave the source byte-identical after a second
Format Document pass. Before/after screenshots are captured in the coordinating task.
The installed extension's BootstrapServices assembly matches Release byte-for-byte.

Evidence roots:

- `/private/tmp/nsharp-columnar-il-emitter-owner-20260907/final-owner-build/final-owner-handoff-r4.json`
- `/private/tmp/nsharp-columnar-il-emitter-owner-20260907/final-owner-build/final-candidate-verification-r4/final-owner-verification-r4.json`
- `/private/tmp/nsharp-complete-emitter-gate-20260908-r2/root-gate-acceptance.json`
- `/private/tmp/nsharp-complete-emitter-sdk-20260908/installed-verification/`
- `/private/tmp/nsharp-complete-emitter-sdk-20260908/visual-verification.json`

Next: move all 663 lines of MultiFileCompiler with its state, constructors, pipeline,
reference handling, wide-stack emission, and ten recovery canonicals. Preserve direct
callers and migrate seven assembly-qualified native lookups. The analysis path requires
IDE-enabled integration and visual unsaved-buffer verification. CLI/editor feature
work, Runtime reimplementation, NativeAOT, and the broader writer backlog remain separate.

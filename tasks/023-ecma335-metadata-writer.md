# 023 — The ECMA-335 metadata writer: the second executor over the plan rows

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

This task gives the compiler its own metadata writer — `System.Reflection.Metadata.Ecma335`
(`MetadataBuilder`, `BlobBuilder`, `MethodBodyStreamEncoder`, `ManagedPEBuilder`) driven from the
same plan rows the Reflection.Emit executor consumes today — and then retires Reflection.Emit from the
emitter. It exists because task 022 slice 2 measured, by execution, that `PersistedAssemblyBuilder`
cannot reach a single type universe: `MakeGenericType` refuses a `TypeBuilder` argument whatever the
builder's core assembly, `MakeGenericSignatureType` reaches no member, and any hybrid writes a second
corelib `AssemblyRef` and produces an image that does not bind
(`systems-language-closeout/decodes/2026-09-02-universe-a-viability-decode.md`). A native `nlc` that
can emit an arbitrary BCL call therefore needs a writer that encodes `MemberRef`s and `TypeSpec`s from
the metadata universe itself, the way every real compiler does. The 2026-09-01 metadata-writer decode
shelved this on the premise that `PersistedAssemblyBuilder` sufficed; that premise is withdrawn for
exactly this operation and no other — the AOT capability floor (task 022 slice 1) still stands.

- Add no C# source. The writer is N#: the `Ecma335` API surface the writer needs is spelled from N#, and
  where N# cannot spell it today, THAT is a language deliverable of slice 1 — not a reason to write C#.
- The writer is a SECOND executor over the SAME plan rows. It does not re-plan, re-bind or re-lower;
  a plan-row change made for the writer is a defect in the plan rows and is fixed there for both executors.
- Parity is measured, never argued: the writer's image and the Reflection.Emit image are compared
  under the IL harness's normaliser at method-body granularity (scope-normalised, the mapping stated),
  and by running the executable corpus programs for identical stdout/exit, with `ilverify` green.
- Every slice re-derives its predecessor's census by decode rather than inheriting it.
- Follow every final backend, product, documentation, selective-staging, `Evidence:` commit, repin, and
  clean-tree rule in `AGENTS.md`. Backend slices use `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`
  at their integration checkpoints.
- Report only after every terminal condition below is green.

---

## Slice 1 — The spelling gap

Measurement plus the language work it names. Change no emitter file.

Enumerate every `System.Reflection.Metadata` / `System.Reflection.Metadata.Ecma335` /
`System.Reflection.PortableExecutable` member the writer needs (start from the executable path the
emitter already drives from C# — `GenerateMetadata` → `PEHeaderBuilder` → `MetadataRootBuilder` →
`ManagedPEBuilder` → `BlobBuilder` — then the encoders: `MethodBodyStreamEncoder`, `InstructionEncoder`,
`ControlFlowBuilder`, `BlobEncoder`/`SignatureTypeEncoder`/`MethodSignatureEncoder`,
`MetadataBuilder.Add*` for every table the emitter populates today, `MetadataTokens`, and the handle
structs with their implicit conversions). For each, write the N# probe that spells it and record PASS or
the exact `nlc check`/emit decline. Group the declines by language cause (a readonly-struct handle
returned by value, an implicit conversion operator, a `ref` return, a nested generic, an `out`
parameter, an enum flag composition, a `params`/`ReadOnlySpan<byte>` overload…).

Terminal condition: a dated decode under `systems-language-closeout/decodes/` with the member table and
the cause groups; each language cause closed by an N# language slice with its contracts (or, where a
cause is a genuine N# design refusal, the writer's spelling around it stated and contracted); a probe
program in N# that writes a `Main` printing a string through `MetadataBuilder` and runs on the shared
framework; STATUS.md §0 discipline.

## Slice 2 — The writer for the declaration host (re-aimed 2026-09-03 by its own Phase-1 decode)

Slice 1's decode assumed plan rows exist for declarations; slice 2's decode measured that they do not: the
declaration host is imperative C# over the source-shaped `ColumnarProgramInput` (57 `TryResolveType` sites, 95
`MakeGenericType`), and the method-body plan rows describe only what the door claims. Measured over the corpus at
`8a144587b` (67 N#-emitted assemblies, 4,320 bodies): 17.9% of bodies are wholly row-described (13.1% door-claimed,
4.8% synthesized), 75.1% are host-assembled with plan fragments, 7.0% carry no plan row. So slice 2 is a sequence:

- **S2.0 — decode** (done, `b0231f9f5`): the method-body key dumper rebuilt (`ilspycmd -il`, short/long folding,
  branch offsets to ordinals, a scope map with a collision guard), the three-marker census above, and the body fork
  decided — **(B) the plan-recording sink**: the host's `ILGenerator` field becomes an N#-owned recorder producing the
  same plan rows the executor consumes (eight members, 88 opcodes of which 37 carry operands, six new plan constants,
  zero new operand kinds), every recorded body validated by `ValidateMethodBodyStack`, a refused body a located finding.
- **The `U` (uint) literal suffix** did not emit at all — fixed as its own commit (`2b131186f`; two contracts had pinned
  the defect as a fact).
- **S2.1 — the declaration-row IR** (`ColumnarDeclarationPlan.nl`) driving the EXISTING Reflection.Emit walk from rows, one
  table per commit at whole-PE `IL_DIFFS=0` (one writer still): (a) module + assembly + enums, (b) typedefs, (c) fields +
  constants, (d) methods + signatures + parameters, (e) properties + accessors, (f) generic parameters + constraints, (g)
  custom attributes, (h) P/Invoke, (i) method overrides — the walk's order dependencies become explicit row order.
  **(g) implemented at `f6ebcf42`, integrated at `4f2a8e63`:** N# owns the four attribute families'
  selection, blob data and application order; all four C# attachment calls are removed. The corrected
  control-first proof compares 94 assemblies with no IL, output-set or outcome differences and 2,138
  native tests per arm. Constructor resolution remains S2.2; (h) follows below. See STATUS for the
  exact fresh integration-gate record and the dated parity proof.
  **(h) implemented at `0cde66a0`, integrated at checkpoint `69ad857b`:** N# P/Invoke rows own
  selection, validity/declines, names, attribute/convention words and implementation-bit merging.
  Shared native-flag bodies move onto ColumnarFunctionInput after strict analysis exposed a global
  helper visibility problem. No new C# policy; emitter −8 lines, InputBuilder expression −9 bytes.
  Three-arm proof: 94 images and 2,138 native tests per arm, zero image/output/outcome differences.
  Estate 7,666; native declarations 66; audit 18/18. Shared signature/default metadata remains later work.
  **(i) implemented at `75fa5a77`, integrated in the current checkpoint:** all fourteen C# override
  attachment sites move to consumed ordinary/iterator N# records. Exact target order, equality
  domains, flags, late errors and iterator reflection phases are preserved. Emitter −26 lines;
  estate 7,676, native declarations 76, audit 18/18. Three-arm parity compares 94 images and 2,145
  native tests per arm with zero differences; exact new controls pass 10/10 on both compilers.
  See STATUS's fresh gate pointer and [i proof](../systems-language-closeout/decodes/2026-09-04-s21i-parity-proof.md).
- **S2.2 — resolution moves to N#**: the revalidated 56 ordinary and 30 type-parameter-aware resolver calls (definitions excluded) emit a resolved type-reference KEY, `AddType` gains its
  structural form, the override resolver returns a descriptor beside its `MethodInfo`, maxstack becomes a plan column
  from `ValidateMethodBodyStack`'s heights, ambient locals become slot indices. The first connected
  resolver cut and required production key consumer are specified in the
  [next-cut decode](../systems-language-closeout/decodes/2026-09-04-s22-resolution-next-cut.md).
  **S2.2(a) implemented at `77686382`:** the connected canonical resolver and dependency
  closure are N#-owned; thirteen C# helper definitions are deleted. Resolution retains immutable
  structural identity and emission provenance, consumed by the existing `typeof` type-pool/ldtoken
  path. Emitter 19,629 / 18,637 nonblank (−1,059 / −1,040); estate 7,703, native declarations 79,
  iterators 25. The corrected pool census is 36 calls across 12 files: one keyed, 35 still
  handle-only. Member/override descriptors, remaining type consumers, ambient locals and maxstack
  are later S2.2 cuts. See STATUS and the
  [implementation decode](../systems-language-closeout/decodes/2026-09-04-s22a-canonical-structural-resolution.md).
  **S2.2(b) implemented at `4b592311`, production controls integrated at `ad303387`:**
  ordinary source-interface member lookup is N#-owned and its actual declaring/signature identity
  is consumed by the existing override attachment executor. The C# recursive helper is deleted;
  emitter 19,613 / 18,622 nonblank (−16 / −15). A required correction makes retained structural
  identity storage readonly with copied BCL read-only collections; S2.2(a)'s input snapshots alone
  did not prove backing-storage immutability. Estate 7,714, native declarations 85, iterators 25;
  strict source retains 259 findings. Closed-source, external/base/iterator member resolution,
  remaining type consumers, ambient locals and maxstack remain open. See STATUS and the
  [implementation decode](../systems-language-closeout/decodes/2026-09-05-s22b-source-interface-member-resolution.md).
  **S2.2(c) implemented at `0813c1ac`, controls integrated at `93ecaf6d`:** closed source-interface
  matching, completeness and signature substitution are N#-owned, as is the shared generic method
  rebinder. Four C# helpers are deleted; successful immutable open/context/effective bindings remain
  consumed through override execution. Original source facts are snapshotted and validated without
  a second closure. Emitter 19,517 / 18,537 nonblank (−96 / −85); estate 7,726, native declarations 89;
  strict 259 unchanged. Three-arm parity covers 94 images and 2,165 tests per arm with zero differences;
  exact controls pass 20/20 with all 24 MethodImpl rows equal. External/base/iterator members,
  source discovery/call admission, remaining type consumers, ambient locals and maxstack remain open.
  See STATUS and the [implementation decode](../systems-language-closeout/decodes/2026-09-05-s22c-closed-source-interface-members.md).
  **S2.2(d) implemented at `405483ca4`, controls integrated at `7009a190d`:** external-interface
  enumeration, matching and completeness are N#-owned; the C# matcher and both loops are deleted.
  Consumed descriptors retain actual external VAR/MVAR ownership, open/context/effective types and
  ordered required/optional custom modifiers. Original unfiltered GetMethods and first-Methods policy
  remains. Emitter 19,492 / 18,513 nonblank (−25 / −24); estate 7,736, native declarations 93; strict
  259 unchanged. Three-arm parity covers 94 images and 2,169 tests per arm with zero differences;
  exact controls pass 24/24 with all 31 MethodImpl rows equal. Base/iterator descriptors, source
  discovery/call admission, remaining type consumers, ambient locals and maxstack remain open.
  See STATUS and the [implementation decode](../systems-language-closeout/decodes/2026-09-05-s22d-external-interface-members.md).
- **S2.3 — the writer, declarations only**, behind `backend: il-writer` (the switch already exists in N#; one C# branch in
  `MultiFileCompiler.cs` paid by an exact shrink; `_NSharpEmitKey` gains the backend so the arms never share `obj/`), grown
  table by table against the hello-world probe, `ilverify` on the declarations-only image, a metadata-table diff against
  the Reflection.Emit image.
- **S2.4 — the byte-level body encoder** (header, EH section small and fat with fault, every body byte through
  `BlobBuilder`; zero catalog rows; slice 1's blanket refusal of the body layer is corrected — `AddMethodBody` and
  `ExceptionRegionEncoder` were catalog gaps, not signature refusals).
- **S2.5 — the remaining bodies** through the recording sink.
- **S2.6 — the switch, the parity harness and `tests/native/metadata-writer`** (the compile-time corpus pin moves in the
  same commit).

Terminal condition: hello-world and the `.tests.nl` corpus projects emit through the writer with method-body parity to
the Reflection.Emit image under a name-resolved body dump with a stated scope map, identical stdout/exit for the
executable programs, `ilverify` unchanged, decline census stated, `nlc test` green with identical Passed counts; the
writer selectable per project (`backend: il-writer`) for the A/B only — no product default moves yet. The Cecil
corelib→contract rewrite stays load-bearing through slice 2.

## Slice 3 — One universe through the writer

With the writer, external references are encoded from the metadata catalog: `TypeRef`/`MemberRef`/
`TypeSpec`/`MethodSpec` from the metadata context's types, generic instantiations closed over the
compiler's own `TypeDef`s by TypeSpec blob, no runtime `Type` anywhere in the emit path, and the
references pointing at the contract assemblies (`System.Runtime`, `System.Collections`, …) as written —
which retires `EmitIlAssembly.cs`'s Cecil corelib→contract rewrite, load-bearing until this slice. This is
what task 022 slice 2 could not reach.

Terminal condition: `Assembly.Load`, `Assembly.LoadFrom`, `AppDomain.GetAssemblies` and every runtime
member lookup in the emit path reach zero (the census task 022 slice 2 re-derived: 5 C# + 10 N# loader
sites, 1,800 `typeof` sites of which 654 are comparisons); the corpus A/B holds at method-body
granularity; the estate green; the decline census unchanged.

## Slice 4 — The default flips, and Reflection.Emit leaves

The writer becomes the product's emitter; the Reflection.Emit executor and `ColumnarIlEmitter.cs`'s
host are deleted (the C# dies with them); the SDK and CLI carry the writer; the AOT capability floor
is re-measured (the `CustomAttributeBuilder` cell is moot; nothing else in the floor is exercised).

Terminal condition: `ColumnarIlEmitter.cs` deleted; the ownership ratchet's rows for it and
`EmitIlAssembly.cs` removed as REMOVED paths (never to reappear); the fresh product gate green; the
architecture documentation present-tense; task 022 slice 5 (the native `nlc`) unblocked and run.

---

## Out of scope

- Debug information (`MarkSequencePoint`, PDB emission) — not emitted today; a later task.
- Re-planning: any change to the plan rows for the writer's convenience.
- Task 022 slices 3a, 3b and 4 (the analyzer's and editor's universe) — independent of the writer and
  proceed on their own.

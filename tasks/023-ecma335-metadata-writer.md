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

## Slice 2 — The writer for the declaration host

The writer executes the plan rows for types, fields, methods, properties, generic parameters and their
constraints, custom attributes (the blobs task 022 slice 2a already writes), P/Invoke, nested types,
unions, enums, and the exception regions — everything the Reflection.Emit executor defines outside
method bodies — and encodes method bodies through `InstructionEncoder` from the same opcode rows (124
distinct opcodes in the union; `BeginFaultBlock` included).

Terminal condition: hello-world and the `.tests.nl` corpus projects emit through the writer with
method-body parity to the Reflection.Emit image under the normaliser, identical stdout/exit for the
executable programs, `ilverify` green, decline census stated; the writer selectable per project
(`project.yml`) for the A/B only — no product default moves yet.

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

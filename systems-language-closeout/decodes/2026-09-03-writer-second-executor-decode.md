# DECODE (WIP) — what a second executor can actually execute: the plan-row census, the door claim rate, and the F2 fork (task 023, slice 2, S2.0)

Measured in the isolated worktree `/private/tmp/nsharp-agent-wt/023-s2` (branch `stream/023-s2-writer`,
off `a9059fc71`). **Zero product files changed in this slice.** Probes and the rebuilt harness live
OUTSIDE the repo at `/private/tmp/nsharp-agent-wt/probes/023-s2/`. Every language verdict below is a
real `dotnet build` through the PACKAGED SDK (`~/.nsharp/packages`, packed 2026-09-02 22:36 from the
`71bec2dcb` republish) and, where marked RUN, an execution.

**STATUS: WIP, committed at a coordinator pause.** Sections 1–4 and 6–7 are complete and measured.
Section 5 (the corpus body denominator and the two-marker door census) has its harness built and its
corpus swept; the dump was stopped mid-run for the pause and is re-run on resume. The fork verdict in
§4 does not depend on §5's denominator — it is decided by the static census in §4.2 — but §5 sizes it.

---

## 0. Headline — four sentences

1. **There are no declaration plan rows at all.** `ColumnarCodePlan` is the ONLY plan-row IR and it is
   method-body-only; the declaration host is a C# walk over `ColumnarProgramInput`, a SOURCE-shaped
   table whose type references are canonical STRINGS. The declaration-row IR is slice 2's first
   deliverable, not its input.
2. **The plan rows do not describe most method bodies either.** `EmitBody` offers the door first and
   falls back to 1,104 direct `.Emit(` sites; the door claims 7 of 21 statement kinds and no branch,
   loop or region in a USER body.
3. **The fork is decided by a static census, and it is not close.** Routing every host body through the
   plan rows costs **8 sink members, 6 new opcode constants and ZERO new operand kinds** — every one of
   the 37 operand-carrying opcodes the host emits already has a plan operand kind. Growing the door to
   100% instead is the remainder of the 015-B arc, which has taken B1–B16 to reach the current rate.
4. **The byte-level body route needs no catalog rows and no republish**, and slice 1's blanket
   "the body layer is REFUSED" does not describe the two overloads and the region encoder that matter.

---

## 1. The plan-row consumer shape, as measured

### 1.1 The declaration host reads no rows

`ColumnarIlEmitter.TryEmitColumnarAssembly` (`src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs:3949`)
walks `ColumnarProgramInput` (`ColumnarInputs.nl:303`) and calls Reflection.Emit imperatively:

| call | sites | call | sites |
|---|---|---|---|
| `MakeGenericType` | 95 | `DefineMethodOverride` | 14 |
| `DefineMethod` | 28 | `DefineType` | 11 |
| `DefineField` | 11 | `AddInterfaceImplementation` | 10 |
| `CreateType` | 10 | `SetConstant` | 9 |
| `DefineConstructor` | 6 | `DefineGenericParameters` | 6 |
| `DefineProperty` | 4 | `DefineNestedType` | 4 |
| `SetCustomAttribute` | 4 | `SetParent` / `DefineParameter` | 2 / 2 |
| `DefineEnum` / `DefineLiteral` | 1 / 1 | `DefinePInvokeMethod` / `DefineDynamicModule` | 1 / 1 |

The 26 N# owners it consults answer QUESTIONS, not rows: `ColumnarTypeOfPlanner` (245 references),
`ColumnarBaseTypePlanner` (9), `ColumnarGenericConstraintPlanner` (6), `ColumnarAttributeBlobs` (4),
`ColumnarOverrideTargetResolver` (1). **So "a second executor over the same plan rows" has, for the
declaration host, no rows to execute.**

### 1.2 What the host computes that the writer also needs

Each of these is a computation the Reflection.Emit executor performs and the writer would otherwise
repeat — which makes it planner work by the task's own rule:

- **canonical string -> `Type`**: `TryResolveType` / `TryResolveTypeWithTypeParams`, **57 call sites**, C#.
  (Name mangling is ALREADY N#: `ColumnarBindingScopeFacts.ExactTypeNameForFile` /
  `ExactStructTypeName` / `ExactRelativeTypeNameForFile`.)
- **`TypeAttributes` composition** — record vs struct vs interface vs enum vs nested visibility, inline
  C# `|` expressions at the `DefineType` sites.
- **base/interface list resolution and nested-owner resolution.**
- **the override target**: `ColumnarOverrideTargetResolver.TryFindOverrideTarget` returns a `MethodInfo`;
  the writer needs (declaring-type key, name, signature).
- **the 95 `MakeGenericType` sites** — closed instantiations the writer must encode as `TypeSpec` blobs.
- **maxstack** — see §3.

### 1.3 The method-body pools carry live handles; one pool has no structural form at all

`ColumnarCodePlan.nl` pools: `Types: Type[]`, `Methods: MethodInfo[]`, `Constructors: ConstructorInfo[]`,
`Fields: FieldInfo[]`, `AmbientLocals: LocalBuilder[]`. Three have a structural mirror
(`AddMethodWithSignature:987`, `AddConstructorWithSignature:1039`, `AddFieldWithSignature:1085`; 14 files
use them) — but every mirror column is itself typed `Type`, so it still bottoms out in a possible
`TypeBuilder`. `AddType` has no structural form (STATUS §3.2 already named this as the one prerequisite).
`AmbientLocals` has none and no route to one: a `LocalBuilder` captured from the host's live
`ILGenerator` cannot be described. Two producers — `ColumnarBoundIdentifierPlanner.nl:199,206,377`.
Planners still on the unsigned pools: `ColumnarAsyncEntryPointPlanner`, `ColumnarExternalStaticMemberPlanner`,
`ColumnarIteratorPlanner`, `ColumnarBoundIdentifierPlanner`, `ColumnarInstanceMemberPlanner`.

---

## 2. Which bodies become rows today

`EmitBody` (`ColumnarIlEmitter.cs:5906`) offers `ColumnarMethodBodyPlanner.TryPlanBody` first and, on
decline, emits the body itself. The door's statement arms are kinds 20, 48, 72, 49, 25, 27, 51 —
**7 of 21** — and its expression door answers 12 kinds; **no branch, loop or exception region appears in
a door-claimed USER body**. Schema-v4 bodies that DO carry labels and regions exist only for SYNTHESIZED
members (`ColumnarIteratorPlanner`, `ColumnarAsyncEntryPointPlanner`; the `Execute` sites at
`ColumnarIlEmitter.cs:3676-3825`, `5849`, `9205-9232`).

The inherited corpus figure (STATUS §1 baselines at `c79fe23bb`) is a **door-marker floor of 461 of
3,590 method-body keys ~ 12.8%**. It is re-derived in §5, not inherited.

---

## 3. maxstack, and the model that already computes it and throws it away

`ILGenerator` computes maxstack for the Reflection.Emit path; **nothing in N# does**.
`ColumnarCodePlanExecutor.ValidateMethodBodyStack` (`ColumnarCodePlanExecutor.nl:730`) already runs a
fixed-point per-instruction height model over every schema-v4 body, with a merge-must-agree rule, a
seeded handler entry, catch entering at height 1, `leave` requiring height 0, `ret` refused inside a
protected region, and both a fall-off-the-end and an unreachable-instruction refusal — and then discards
`heights[]`. **maxstack belongs in the plan as a column** computed from that array, so both executors
agree by construction rather than by two implementations agreeing by luck. The same function already
owns the exception-region semantics the fat-header EH section needs.

---

## 4. THE F2 FORK, DECIDED

### 4.1 The three options

- **(A) grow the door to 100% first** — the remainder of the 015-B arc.
- **(B) route the host's own IL calls through a plan-recording sink**, so every body becomes rows
  mechanically without porting the door.
- **(C) writer emits declarations only in slice 2; bodies later** — not viable: two writers cannot share
  one assembly, so one unencodable body kills the whole project.

### 4.2 The census that decides it

Measured over `ColumnarIlEmitter.cs` by a balanced-paren scan of every `.Emit(OpCodes.X, ...)` site:

```
TOTAL .Emit SITES: 1104     1-ARG (no operand): 235     2-ARG (operand): 869
DISTINCT OPCODES:    88     operand-carrying:    37
ILGenerator MEMBERS ON `_il`: Emit 1073, DeclareLocal 111, MarkLabel 48, DefineLabel 48,
                              EndExceptionBlock 5, BeginExceptionBlock 5, BeginCatchBlock 4,
                              BeginFinallyBlock 2                      -> EIGHT MEMBERS
OTHER ILGenerator RECEIVERS: il 17, ctorIl 17, setterIl 4, getterIl 3, lambdaIl 2, cctorIl 1
```

Operand kinds actually needed, and the plan operand kind each already has:

| operand | opcodes | sites | existing plan operand kind |
|---|---|---|---|
| method / ctor | Call 195, Callvirt 110, Newobj 61, Ldftn 7 | 373 | `MethodOperand` / `ConstructorOperand` |
| local | Stloc 108, Ldloc 95, Ldloca 72 | 275 | `AmbientLocalOperand` / `PlanLocalOperand` |
| branch label | Br 23, Brfalse 14, Brtrue 14, Bge 5, Leave 4 | 60 | `LabelOperand` |
| field | Stfld 26, Ldfld 26, Stsfld 3, Ldsfld 2 | 57 | `FieldOperand` |
| constant | Ldc_I4 34, Ldstr 14, Ldc_I8 5, Ldc_R4 2, Ldc_R8 2 | 57 | Int32/Int64/Single/Double/String |
| type | Initobj 11, Box 10, Newarr 7, Isinst 4, Castclass 2, Ldelem 2, Stelem 2, Constrained 1, Ldobj 1, Stobj 1 | 41 | `TypeOperand` |
| argument | Ldarg_S/Ldarg/Starg_S/Starg/Ldarga_S/Ldarga | 6 | `ArgumentOperand` |

**Zero new operand kinds.** Opcode constants: the plan publishes **109**, the host names **88**, the
union is **123** (the task text says 124 — re-derived here as 123; the difference is not yet attributed
and is recorded as an open item). Of the 88, **14 have no plan constant**, and 8 of those are short-form
or ordinal aliases the executor already folds (`Ldarg_0..3`, `Ldarg_S`, `Ldarga_S`, `Starg`, `Starg_S`).

**The genuinely new opcode constants are SIX: `Bge`, `Constrained`, `Ldftn`, `Ldobj`, `Stobj`, `Stind_Ref`.**

### 4.3 Verdict — (B), ACCEPTED by the coordinator 2026-09-03

**(B).** A plan-recording sink over eight members, six new opcode constants and no new operand kind is
bounded and mechanical; it makes the plan rows TOTAL, which is the precondition the task's own sentence
("the writer is a SECOND executor over the SAME plan rows") assumes and the code does not yet meet.
(A) is the remainder of an arc that has taken sixteen slices to reach ~13%. (C) is impossible.

The sink is not new C#: it is a TYPE CHANGE on one field (`ColumnarIlEmitter.cs:64`,
`private readonly ILGenerator _il;`) plus six local variables, with the call sites unchanged in shape.
Under the growth ratchet that is a same-size edit, not growth. The recorded rows are then executed by
EITHER the Reflection.Emit executor (replaying onto a real `ILGenerator`, which must be byte-identical to
today) or the writer.


### 4.4 The sink's contract (coordinator ruling, 2026-09-03 — binding on the slice that cuts it)

1. **THE SINK IS N#-OWNED.** The recording type lives beside `ColumnarCodePlan` in `BootstrapServices`
   and produces EXACTLY the rows the executor already consumes -- the same schema, the same operand
   kinds, with the six new opcode constants (`Bge`, `Constrained`, `Ldftn`, `Ldobj`, `Stobj`,
   `Stind_Ref`) added to the plan's own vocabulary. It is not an adapter and not a shim: a recorded
   body and a planner-produced body are the same artefact by construction, which is the only reading
   under which "the writer is a SECOND executor over the SAME plan rows" is true.
2. **THE C# CHANGE IS A TYPE CHANGE, AND ITS SIZE IS DECLARED.** One field
   (`ColumnarIlEmitter.cs:64`, `private readonly ILGenerator _il;`) plus the six local receivers
   (`il` 17, `ctorIl` 17, `setterIl` 4, `getterIl` 3, `lambdaIl` 2, `cctorIl` 1). The call sites do not
   change shape. The commit states the before/after line and marker counts for the exact-match growth
   ratchet; a same-size edit is not growth, and this must be shown, not asserted.
3. **EVERY RECORDED BODY GOES THROUGH `ValidateMethodBodyStack`, exactly like a planner-produced one.**
   maxstack and the exception-region semantics then come from ONE place for BOTH producers -- which is
   the whole point of §3 -- rather than from two implementations that agree by luck.
4. **A BODY THE VALIDATOR REFUSES IS A LOCATED FINDING, NEVER A SILENT SKIP.** The recording path has no
   quiet fallback: a refusal names the member and the rule it broke. A sink that silently declines to
   record is the failure mode that would make every downstream parity number meaningless.

The 123-vs-124 opcode-union discrepancy stays an OPEN ITEM in the §4.12 row until it is attributed.

---

## 5. The corpus census — PENDING (harness built, corpus swept, dump stopped at the pause)

- **Harness rebuilt** (F7): the B-arc's method-body key comparator was in NEITHER `~/nl98keep/harness`
  nor `~/nl97keep/harness` nor any live worktree. `~/nl98keep/harness/nl89-ilcompare.py` +
  `nl98_ilnorm.py` are WHOLE-PE comparators and cannot serve this A/B: two writers never agree on heap,
  blob and row order. The rebuilt dumper is
  `/private/tmp/nsharp-agent-wt/probes/023-s2/harness/nl23_bodykey.py`, front-ended by `ilspycmd -il`
  (**zero C# written for the harness**), which already resolves every token operand to
  `[Scope]Namespace.Type::Member(sig)`.
  - KEY = `<declaring type path>::<normalised .method header>`.
  - VALUE = the opcode sequence with short/long encodings folded (`ldarg.0`/`ldarg.s 0`/`ldarg 0` ->
    `ldarg 0`; `ldc.i4.8`/`ldc.i4.s 8` -> `ldc.i4 8`; `br.s` -> `br`; `leave.s` -> `leave`) and branch
    operands rewritten from BYTE OFFSETS to TARGET INSTRUCTION ORDINALS — exactly the encodings a
    byte-level writer and `ILGenerator` legitimately disagree on.
  - `.maxstack`, the `.locals init` type list and the exception-region structure are compared but
    reported SEPARATELY, so a maxstack change can never pass silently as "no IL diff".
  - `--scope exact | scopeless`; `scopeless` IS the contract-equivalence mapping of the 2026-09-02
    universe-A decode, and it is not assumed — the dumper reports any full type name seen under two
    distinct scopes.
  - **NON-VACUITY PROVEN**: `selftest` perturbs one instruction and the comparator reports exactly that
    one key (`SELFTEST PASS ... ops_diff=1`).
  - Two parser defects found and fixed while building it, both recorded in the file's own header: comments
    were stripped BEFORE the `// end of method` / `// end of class` terminators were read (folding a whole
    assembly into one method), and the class NAME was taken from the joined header rather than its first
    line (yielding the BASE type, `<Module>.System.Object`).
- **Corpus swept, baseline arm**: `ARM=base TARGETS=72 BUILT=48 ASSEMBLIES=174`, of which 49 are
  N#-emitted after the third-party deny list (`Microsoft.*`, `Swashbuckle.*`, `xunit.*`, `System.*`,
  `YamlDotNet`, `MetadataLoadContext`) and de-duplication by assembly basename — a referenced project's
  output is copied into the referring project's `bin`, and counting both inflates the denominator.
  `.tests.nl` projects go through `nlc test`; everything else through `nlc build`.
- **PENDING on resume**: the body denominator, and the two-marker census —
  marker DOOR (`ldc.i4 24301; pop` at `ColumnarIlEmitter.cs`'s door site) and marker ALL
  (`ldc.i4 49374; pop` inside `ColumnarCodePlanExecutor.Execute`), giving door-claimed bodies,
  plan-executed bodies, and by subtraction the synthesized ones. Both are throwaway scratch mutations.

---

## 6. F6 re-derived — the body layer is a CATALOG gap, not a signature refusal

Slice 1's decode grouped `MethodBodyStreamEncoder`, `InstructionEncoder`, `ControlFlowBuilder`,
`ExceptionRegionEncoder` and `ILOpCode` as "~40 members REFUSED", alongside the signature encoders whose
every overload takes an `out` byref struct or an `Action<T>`. **That wording does not describe two of
them.** From the reference pack's own XML:

```
MethodBodyStreamEncoder.AddMethodBody(Int32, Int32, Int32, Boolean, StandaloneSignatureHandle, MethodBodyAttributes)
MethodBodyStreamEncoder.AddMethodBody(Int32, Int32, Int32, Boolean, StandaloneSignatureHandle, MethodBodyAttributes, Boolean)
ExceptionRegionEncoder.Add / AddCatch / AddFault / AddFilter / AddFinally / IsSmallExceptionRegion
```

Not one byref, not one `Action<T>`. Measured through the packaged SDK, they decline for a DIFFERENT
reason — `new MethodBodyStreamEncoder(bb)` is `emit.local.unsupported-type` (probe p06) and
`ExceptionRegionEncoder` as a parameter is `emit.declaration.function-param` (p06b): the 023/1b list
admits six classes and 31 handle structs, and none of `MethodBodyStreamEncoder`, its nested `MethodBody`,
`Blob`, `BlobWriter` or `ExceptionRegionEncoder` is among them. **They are row gaps of the 023/1b class.**

**And the writer does not need them.** `MetadataBuilder.AddMethodDefinition(MethodAttributes,
MethodImplAttributes, StringHandle, BlobHandle, System.Int32 bodyOffset, ParameterHandle)` takes a plain
int offset into the IL stream, and the whole byte-level `BlobBuilder` surface PASSES AND RUNS (probe p05:
`WriteByte`, `WriteBytes(byte[])` selected past its `byte*` and `ImmutableArray<byte>` siblings,
`WriteInt32`, `WriteUInt16`, `WriteUInt32`, `WriteCompressedInteger`, `Align(4)`, `get_Count()`,
`ToArray()` — 16 bytes in, 16 bytes out). So the writer owns the tiny/fat header (II.25.4.1-4) and the
4-byte-aligned EH section in both its small and fat forms (II.25.4.5/6, fault included) and hands the
stream to `ManagedPEBuilder` exactly as `ColumnarIlEmitter.cs:5881-5890` already does — **no catalog row,
no republish.** That is the adopted route.

---

## 7. Language measurements (packaged SDK; probes `p01`-`p07b`)

| shape | probe | verdict |
|---|---|---|
| int `<<` `>>` `&` `\|` `^` | p01 | **PASS + RUN** (4800/300/44/4396/301) |
| `byte[]` element store from a `byte` VARIABLE and from `Convert.ToByte(65)`; `List<byte>` + `ToArray()` | p02 | **PASS + RUN** |
| `ulong` `UL` literals with `/`, `%`, `&` | p03b | **PASS + RUN** |
| `uint` arithmetic between two `uint` LOCALS | p03d | **PASS + RUN** (273) |
| `Dictionary<string,int>` indexer-set, `TryGetValue(k, out v)`, `ContainsKey`, `Count` | p04b | **PASS + RUN** |
| the `BlobBuilder` byte-level surface | p05 | **PASS + RUN** |
| `TypeDefinitionHandle[]` element stores from `MetadataTokens.*`; `List<MethodDefinitionHandle>`; `MetadataTokens.EntityHandle(int)` / `GetToken(EntityHandle)` / `GetRowNumber(EntityHandle)` | p07b | **PASS + RUN** |
| `Encoding.UTF8.GetBytes(s)` | p04 | **DECLINE** `emit.local.initializer` — reuse `ColumnarAttributeBlobs.Utf8Bytes` |
| `MetadataTokens.GetToken(TypeDefinitionHandle)` | p07 | **NL402** — the implicit `op_Implicit`, exactly as slice 1 contracted; tokens come from declaration order |
| `MethodBodyStreamEncoder` / `ExceptionRegionEncoder` | p06 / p06b | **DECLINE, catalog** — §6 |

### 7.1 NEW LANGUAGE DEFECT — the `U` (uint) literal suffix does not emit, at any magnitude

Not recorded anywhere in STATUS §2.1, which documents `UL` and `L` and is silent on a lone `U`.

```
p03f   c: uint = 256U     decline  emit.typed-local.initializer
p03g   c := 256U          decline  emit.local.initializer
p03d   two uint LOCALS divided                      PASS + RUN     -> uint ARITHMETIC is fine
p03b   256UL / 33554433UL                           PASS + RUN     -> the UL suffix is fine
```

**The owner is found and the analyzer is already right.** `ColumnarScalarLiteralPlanner.TryParseIntegerLiteral`
(`:247`) models exactly three kinds — `0` unsuffixed Int32, `1` `L` Int64, `2` `UL`/`LU` UInt64 — and a
lone `U` (suffixLength 1, hasUnsigned, !hasLong) falls into its `else { return false }`. The LEXER
already tokenises it (`Lexer.ConsumeIntegerSuffix:592` accepts a bare `u`/`U`), and
`AnalyzerLiteralExpressions.nl:99,290` already states and implements the C# rule — *"`u` is `uint` when
the magnitude fits and `ulong` when it does not"*. So the analyzer and the emitter disagree about a
documented rule and the emitter is the one that is wrong.

Sizing: one new kind `3` (UInt32) in `TryParseIntegerLiteral`, with C#'s ECMA-334 §6.4.5.3 rule — a bare
`U` is UInt32 when the magnitude fits 4294967295 and UInt64 (kind 2) when it does not — plus a kind-3 arm
in `TryAppendInteger` (`:90`) emitting `ldc.i4` of the two's-complement int32 bits, the way the kind-2 arm
already does for Int64. `ConstantConversionFacts:72`'s `literalKind != 0` gate stays correct by
construction: a `U`-suffixed literal is still not an unsuffixed int constant, so §10.2.11 does not widen.

---

## 8. Open items carried into S2.1

- The opcode union is measured at **123**, not the 124 the task text states; the difference is unattributed.
- `BeginFaultBlock` has **0** call sites in the C# host — only `ColumnarCodePlanExecutor` emits it, from
  synthesized iterator/async plans. A byte-level EH writer must still encode the fault clause.
- `_NSharpEmitKey` (`src/NSharpLang.Sdk/Sdk/Sdk.targets:142`) does not include the backend value, so the
  A/B's two arms must never share `obj/`.

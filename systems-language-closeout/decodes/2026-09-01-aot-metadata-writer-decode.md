# DECODE — the "AOT metadata writer": `MetadataBuilder` as a SECOND EXECUTOR over the plan rows

Measured at `8cf40128a` in the isolated worktree
`/private/tmp/claude-501/-Users-spencer-repos-nsharplang/2c21afb5-aa30-49ea-93f4-de6a82d53a0d/scratchpad/wt/decode-aot-metadata-writer`
(branch `stream/decode-aot-metadata-writer`). **No production file was edited.** Every number below
is followed by the command that produced it. Probes live outside the repo under
`…/8c6daca3-…/scratchpad/probe/`.

---

## 0. THE HEADLINE — the task's premise is dead, and what survives is smaller and harder than the record says

**0.1 — THE PREMISE IS OVERTURNED, BY SOMEONE ELSE'S EXECUTION.** This task exists in
`STATUS.md` §3.8 because "NativeAOT forbids Reflection.Emit outright, so this is not optional".
The parallel AOT type-model decode **disproved that by running a NativeAOT binary**
(`/private/tmp/claude-501/-Users-spencer-repos-nsharplang/2c21afb5-aa30-49ea-93f4-de6a82d53a0d/scratchpad/decodes/aot-type-model/decode.md`
§0.1, §3, §4): `PersistedAssemblyBuilder` + `ILGenerator` + `CreateType` + `Save` **work under
NativeAOT**, including with an MLC `RoAssembly` as the core assembly, producing a 2,560-byte assembly
that reads back clean. What AOT forbids is exactly two things: **loading** an assembly into the
compiler's own process, and `DefineDynamicAssembly` (generating code to *run* in-process) — and the
emitter uses **zero** `DefineDynamicAssembly` and **one** `PersistedAssemblyBuilder`.

I re-measured that one site independently:

```
$ grep -rn "PersistedAssemblyBuilder" src --include="*.cs"
src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs:1602:  (a comment)
src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs:3991:  var builder = new PersistedAssemblyBuilder(assemblyIdentity, typeof(object).Assembly);
```

**So: the `MetadataBuilder` writer is NOT on the AOT critical path, and this task must stop being
sold as one.** Do not duplicate the type-model decode's loader-deletion slices; they own the
`Assembly.LoadFrom` / `Assembly.Load` sites and the MLC universe, and they are the actual AOT work.

**0.2 — THE SECOND JUSTIFICATION IS ALSO WEAKER THAN THE RECORD ASSUMES.** §3.9 rules that
`015-E` (the 2,023-line declaration host) "retires with the AOT metadata writer". The type-model
decode already decoupled that. This decode adds the harder half of the reason: **the declaration
host does not need `MetadataBuilder` to become N#-owned, because Reflection.Emit is ALREADY spellable
from N# and `MetadataBuilder` is NOT.**

- `tests/native/reflection-emit-bootstrap/ReflectionEmitBootstrap.nl` (301 lines) drives
  `ILGenerator.DefineLabel` / `DeclareLocal` / `Emit(OpCodes.…, LocalBuilder|Label|int)` /
  `MarkLabel` from N# today, and `ColumnarExternalBindingPlans.nl` catalogues
  `TypeBuilder`, `MethodBuilder`, `ConstructorBuilder`, `FieldBuilder`, `ILGenerator`,
  `DynamicMethod`, `Label`, `LocalBuilder`, `OpCode`, `OpCodes`.
  (`grep -n "func IsSupportedRuntimeTypeName" …ColumnarExternalBindingPlans.nl` → 32 distinct
  admitted type-name rows, listed in §7.)
- **`System.Reflection.Metadata` is admitted in zero of those rows, is absent from
  `ExternalAssemblyScan.CommonAssemblyNames()`'s 27 names, and declines at emit in every spelling I
  probed** (§7). It is the same wall `tests/native/systems-proof-corpus/SystemsProofCorpus.tests.nl:44`
  already records for `PEReader`.

**0.3 — WHAT THE TASK HONESTLY IS NOW.** Three surviving justifications, in descending strength:

1. **A second, independent backend is the only true byte-level oracle the emitter can ever have.**
   Today nothing compares emitted IL against an independent producer; the gate is `ilverify`
   (baseline empty) plus behaviour. A second executor over the same rows makes divergence a
   *measurable* fact rather than a reviewed one. **This is the strongest reason and it is not an
   AOT reason.**
2. **The type-description model it forces (`AddType`'s named prerequisite) is owed anyway.** The
   plan's 15 reflection-typed columns are what tie the IR to live `Type` objects; the type-model
   task needs the same decoupling for its "one type universe" slice. Paying it once serves both.
3. **Dependency shedding and determinism** — `PersistedAssemblyBuilder` is itself a `MetadataBuilder`
   client, so this buys independence from `System.Reflection.Emit`, not capability.

**0.4 — AND IT IS EXPENSIVE IN A WAY THE ARCHIVE DID NOT PRICE.** The archive's rationale
(`git show 40e0cc20e:systems-language-closeout/STATUS.md`, §"THE AOT DECISION", line 14455) says the
writer is "cheap" because the member pools already carry structural signatures. **Three measured
facts re-price that**, all new here:

- The signature side is **not** complete: **45** signature-bearing pool adds across 13 planners, but
  **66** handle-only adds across 8 planners, and the handle-only ones in `ColumnarIteratorPlanner`
  point at `FieldBuilder`/`TypeBuilder` state-machine members (§4).
- Even the "structural" columns are `Type`/`Type[]`/`Type[][]` — **11 `Type`-typed columns, 3
  `MemberInfo`-typed, 1 `LocalBuilder`-typed, 15 of 68 total** (§4). "Signature-bearing" today means
  *which `Type` objects*, not *a description a token writer can consume*.
- **SRM's API is 16 structs to 7 classes with lambda-taking members** (§8), landing squarely on two
  named N# walls: `ColumnarExternalBindingPlans` "cannot describe a VALUE receiver" (§3.3), and
  lambdas are `015-B`'s blocker #1. The mitigation exists (write signature blobs byte-wise into a
  `BlobBuilder`) but it is a mitigation, not an absence of cost.

**0.5 — THE ONE THING THAT IS GENUINELY CHEAP, AND IT IS THE BEST NEWS HERE.** The plan's opcode
column is already the ECMA-335 encoding, so the writer's opcode half is **a cast, not a switch**:

```
$ dotnet run -c Release -- …/opcodes.txt          # probe/opmap
TOTAL=108 MAPPED-1:1=108 NOT-IN-ILOpCode=0 NOT-IN-OpCodes=0
```

All **108** modeled opcode constants satisfy `(ILOpCode)(ushort)planValue` **and** round-trip to the
same `System.Reflection.Emit.OpCode` by value. That deletes the executor's 80-arm
`EmitWithoutOperand` cascade outright in the second backend.

---

## 1. What was measured, and the shape of the answer

| question | answer | where |
|---|---|---|
| plan-row vocabulary | **7 operation kinds × 14 operand kinds, 108 opcodes, 23 `Append*` entry points** | §2 |
| how the executor lowers them | **one 14-arm dispatch + 3 helpers; 114 `OpCodes.` sites in the only production `.nl` naming `OpCodes`** | §3 |
| handle model | **15 of 68 plan columns are reflection-typed; `AddType` is one of four gaps, not the only one** | §4 |
| declaration host | **`TryEmitColumnarAssembly` 3974–5996 = 2,023 lines, 43 declines, 12 passes; 141 Reflection.Emit declaration calls over 27 APIs file-wide** | §5 |
| who consumes emitted assemblies | **nobody in-process: `File.WriteAllBytes`, then `nlc test` loads from a PATH** | §6 |
| N# spellability of SRM | **NL704/NL201 with no dependency; `emit.local.initializer` decline with one** | §7 |
| the probe | **ran, printed `42 / 7 / Int32`, ilverify "All Classes and Methods … Verified."** | §8 |
| byte-identity as an oracle | **NOT achievable as stated — measured, enumerable divergences** | §9 |
| staged plan | **6 slices, only one of which is a prerequisite for anything else** | §10 |

---

## 2. The plan-row vocabulary — the exact surface a second executor must cover

```
$ wc -l src/NSharpLang.Compiler.BootstrapServices/ColumnarCodePlan.nl \
        src/NSharpLang.Compiler.BootstrapServices/ColumnarCodePlanExecutor.nl \
        src/NSharpLang.Compiler.BootstrapServices/ColumnarExternalBindingPlans.nl \
        src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs
2308  ColumnarCodePlan.nl
2711  ColumnarCodePlanExecutor.nl
1090  ColumnarExternalBindingPlans.nl
20784 ColumnarIlEmitter.cs
```

(§3.2's 2,155 / 2,625 / 21,519 are all stale at this tip; the IR pair is now **5,019** N# lines.)

### 2.1 Operation kinds — 7 (`grep -n "Operation(): int" ColumnarCodePlan.nl`)

| # | constant | operand | Reflection.Emit lowering | `MetadataBuilder` equivalent |
|---|---|---|---|---|
| 1 | `EmitInstructionOperation` | per operand kind | `EmitInstruction` | `InstructionEncoder.OpCode(ILOpCode)` + operand |
| 2 | `MarkLabelOperation` | Label | `il.MarkLabel(labels[i])` | `InstructionEncoder.MarkLabel(LabelHandle)` |
| 3 | `BeginExceptionBlockOperation` | Label (**written back**) | `labels[i] = il.BeginExceptionBlock()` | no analogue — see §2.4 |
| 4 | `BeginFinallyBlockOperation` | none | `il.BeginFinallyBlock()` | `ControlFlowBuilder.AddFinallyRegion(…)` |
| 5 | `BeginFaultBlockOperation` | none | `il.BeginFaultBlock()` | `ControlFlowBuilder.AddFaultRegion(…)` |
| 6 | `EndExceptionBlockOperation` | none | `il.EndExceptionBlock()` | region close (offsets) |
| 7 | `BeginCatchBlockOperation` | **Type** | `il.BeginCatchBlock(plan.Types[i])` | `ControlFlowBuilder.AddCatchRegion(…, EntityHandle)` |

### 2.2 Operand kinds — 14 (`grep -n "Operand(): int" ColumnarCodePlan.nl`)

`NoOperand`0 `Int32`1 `Type`2 `Argument`3 `AmbientLocal`4 `Method`5 `Constructor`6 `Field`7
`PlanLocal`8 `Label`9 `Int64`10 `Single`11 `Double`12 `String`13.

### 2.3 Opcodes — 109 constants, 108 real

```
$ grep -c "static func [A-Za-z0-9_]*(): short" ColumnarCodePlan.nl
109                       # 108 opcodes + NoOpCode()==0
```

The file's own header states the invariant that makes the writer cheap:
*"Opcode values are the signed values exposed by `System.Reflection.Emit.OpCode.Value`. They are
never positional reflection indices or a second semantic numbering system."*
Two-byte opcodes therefore appear as negative shorts (`Ceq -511` = `0xFE01`), and §0.5's probe proves
`(ILOpCode)(ushort)v` is total and correct over all 108.

108 also reproduces §3.2's "108 names" in
`ColumnarExternalBindingPlans.IsSupportedOpCodeMemberName`'s three family predicates.

### 2.4 Row-producing API — 23 `Append*` functions (`grep -c "func Append" ColumnarCodePlan.nl`)

`AppendInstruction`, `AppendInstructionWithoutOperand`, `AppendInt32/Int64/Single/Double/String/Type/
Argument/AmbientLocal/Method/Constructor/Field/PlanLocal/Label Instruction`, `AppendMarkLabel`,
`AppendBeginExceptionBlock`, `AppendBeginFinallyBlock`, `AppendBeginCatchBlock`,
`AppendBeginFaultBlock`, `AppendEndExceptionBlock`, `AppendRegionMarker`, `AppendV2Row`.

**THE ONE STRUCTURAL MISMATCH IN THE WHOLE ROW MODEL, AND IT IS IN OPERATION KIND 3.** The
Reflection.Emit executor *writes back* into the label pool:

```nl
} else if operationKind == ColumnarCodePlanContract.BeginExceptionBlockOperation() {
    labels[plan.OperandIndices[i]] = il.BeginExceptionBlock()
```

`ILGenerator` invents the region's end label and hands it back so `leave` rows can target it.
`ControlFlowBuilder` has no such call: it takes **four labels** (try start/end, handler start/end)
that the writer must have marked itself, and it registers the region **after** the body is encoded.
So the second executor cannot be a straight row-for-row replay of kinds 3–7: it must buffer the
region stack and emit `AddCatchRegion`/`AddFinallyRegion`/`AddFaultRegion` at `EndExceptionBlock`.
**This is the only place the two backends do not share a shape.** My probe implements exactly this
buffering and it verifies (§8).

### 2.5 Schemas — v1/v2/v3/v4, and the mirror column

- v4 is a documented superset of v3 with **no fragments at all**; `ExecuteMethodBodyRows` and
  `ExecuteV3`/`ExecuteRecursiveRows` differ only in servicing kinds 3–7, and both call the shared
  `EmitInstruction` — §3.2's "byte identity across schemas is BY CONSTRUCTION" holds, and it holds
  for the second backend for the same reason.
- `PlanLocalIsMirror: bool[]` is a **type-discovery scratch** marker: a mirrored plan names the
  enclosing body's locals for typing only and `Execute` refuses it. The second executor must refuse
  it identically — it is not a row kind, it is a plan-level admissibility flag.

---

## 3. How the executor lowers each row today

```
$ grep -c "OpCodes\." ColumnarCodePlanExecutor.nl                       → 114
$ awk 'NR>=406 && NR<=575' ColumnarCodePlanExecutor.nl | grep -c "il.Emit(OpCodes\."  → 80
$ grep -rl "OpCodes\." src --include="*.nl"                             → 16 files, 1 production
$ grep -rn "ColumnarCodePlanExecutor\.Execute" src --include="*.nl" | grep -v "\.tests\.nl"
  → 14 production call sites in 14 planners (+1 comment)
$ grep -c "ColumnarCodePlanExecutor\.Execute" src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs
  → 19
```

`ColumnarCodePlanExecutor.nl` is confirmed **the only production `.nl` file naming `OpCodes`**
(the other 15 are `.tests.nl`). The lowering is:

- `EmitInstruction` (`:299`) — a 14-arm operand dispatch. Method rows pick `Call` vs `Callvirt`;
  Field rows pick among `Ldsfld/Stsfld/Ldflda/Stfld/Ldfld`; Label rows among `Br/Brtrue/Leave/Brfalse`;
  Type rows among `Ldtoken/Box/Castclass/Isinst/Unbox_Any/Initobj/Newarr/Stelem/Ldelem`.
- `EmitArgument` (`:390`) — **one row, four encodings** (see §9; this is where byte-identity dies).
- `EmitWithoutOperand` (`:406`) — **80 `il.Emit` arms**, all deleted by §0.5's cast in the second backend.
- `EmitLocal` (`:564`) — 3 arms (`Ldloc/Ldloca/Stloc`), `LocalBuilder`-typed.

**The 1,145 `OpCodes.` sites in `ColumnarIlEmitter.cs` are NOT this writer's surface.** They are
`015-B`'s surface — the C# residual body emitter the plan rows are replacing. A second executor
serves *plan rows only*. This is the single most important scoping fact in the decode and the record
does not state it.

```
$ for t in "OpCodes\." TypeBuilder ILGenerator MethodBuilder AssemblyBuilder ModuleBuilder \
      PersistedAssemblyBuilder FieldBuilder ConstructorBuilder EnumBuilder \
      GenericTypeParameterBuilder LocalBuilder CustomAttributeBuilder; do
    printf "%-30s %s\n" "$t" "$(grep -c "$t" ColumnarIlEmitter.cs)"; done
OpCodes.                     1145      (was 1,190 at 40e0cc20e — 015-B has removed 45)
TypeBuilder                   147      (was 177 — −30)
ILGenerator                    52
LocalBuilder                   34
MethodBuilder                  27
FieldBuilder                   18
EnumBuilder                    17
ConstructorBuilder             12
GenericTypeParameterBuilder    11
AssemblyBuilder                11
ModuleBuilder                   5
CustomAttributeBuilder          4
PersistedAssemblyBuilder        2
```

### 3.1 Plan-row coverage at this tip — the ceiling on what a second backend can ever emit

```
$ python3  # brace-matched extents + `case N:` census over ColumnarIlEmitter.cs
EmitStatement:      lines 6266..7928 (1663); 21 case arms [20,21,22,23,24,25,26,27,28,29,30,40,41,48,49,51,56,61,62,72,73]
EmitExpressionCore: lines 9663..12190 (2528); 27 case arms [0,1,3,6,7,8,9,10,11,12,13,15,16,17,18,36,42,44,45,46,47,52,53,57,58,59,64]
```

- `ColumnarMethodBodyPlanner.ExpressionKindLedger()` now lists **34** kinds;
  `IsDeclinedExpressionKind` names **21**, so the door claims **13** (`0,1,2,3,4,6,8,9,11,12,13,57,62`).
  §3.2/§4.1's "7 of 27" is stale twice over — the denominator grew to 34 and the numerator to 13.
- The method-body door's **statement** claim is still only *N kind-24 declarations followed by one
  kind-20 `return <expr>`*, plus the bare-void body (`TryPlanBody`, `:197`).
- `ColumnarIteratorPlanner.EmitStatement` (`:1878`) claims **10** statement kinds
  (`25,40,24,23,26,27,72,28,29,48`) — this is where §3.2's "10 of 21" actually lives.

**Consequence: a second backend cannot replace the emitter until plan-row coverage is total, because
under a single-backend cutover any body still emitted by the C# residual could not be emitted at
all.** Until then the second executor can only run *alongside* the first as an oracle.

---

## 4. The handle model, and the `AddType` prerequisite RE-PRICED

### 4.1 What the plan actually stores

`class ColumnarCodePlan` has **68** declared columns. **15 are reflection-typed:**

| column | type | what a token writer needs instead |
|---|---|---|
| `Types` | `Type[]` | TypeRef / TypeDef / TypeSpec handle |
| `ResultType`, `FragmentResultTypes`, `planLocalMirrorTypes` | `Type?`/`Type[]` | typing only — never emitted |
| `Methods` | `MethodInfo[]` | MemberRef / MethodDef / MethodSpec |
| `MethodDeclaringTypes`, `MethodReturnTypes`, `MethodParameterTypes` | `Type[]`, `Type[][]` | signature blob |
| `Constructors` | `ConstructorInfo[]` | MemberRef / MethodDef |
| `ConstructorDeclaringTypes`, `ConstructorParameterTypes` | `Type[]`, `Type[][]` | signature blob |
| `Fields` | `FieldInfo[]` | MemberRef / FieldDef |
| `FieldDeclaringTypes`, `FieldValueTypes` | `Type[]` | field signature blob |
| `AmbientLocals` | **`LocalBuilder[]`** | **no analogue at all** |

### 4.2 What `AddType` lacks — exactly

```nl
func AddType(value: Type): int {
    EnsureV2Building()
    if value == null { throw new ArgumentNullException("value") }
    EnsureTypeCapacity(TypeCount + 1)
    index := TypeCount
    Types[index] = value          // ← the entire body: a live Type object, nothing beside it
    TypeCount = TypeCount + 1
    return index
}
```

Contrast `AddMethodWithSignature`, which stores `declaringType`, `parameterTypes`, `returnType`,
`isStatic`, `isAbstract` **beside** the handle and sets `MethodUsesDeclaredSignature[index] = true`
— with the stated reason: *"Reflection.Emit `MethodBuilder` does not expose `GetParameters` until its
owner has been baked."*

**So the named prerequisite is real, and it is understated in two directions:**

1. **The "signature" the member pools carry is itself `Type` objects.** `MethodDeclaringTypes[i]`
   is a `TypeBuilder` for a user type. A token writer cannot consume it either. The prerequisite is
   not "give `AddType` a signature" — it is **a `ColumnarTypeRef` description model** that names
   either (a) an external type by assembly + namespace + name + generic arguments, or (b) a
   user-declared type by its declaration identity; and then routing *every* `Type`-typed column
   through it.
2. **Three more pools need the same treatment, not one.** Measured:

```
$ grep -rn "AddMethodWithSignature\|AddConstructorWithSignature\|AddFieldWithSignature" src --include="*.nl" \
    | grep -v "\.tests\.nl" | grep -v ColumnarCodePlan.nl | wc -l        → 45  (13 planners)
$ grep -rn "\.AddMethod(\|\.AddConstructor(\|\.AddField(" src --include="*.nl" \
    | grep -v "\.tests\.nl" | wc -l                                       → 66  (8 planners)
$ grep -rn "\.AddType(" src --include="*.nl" | grep -v "\.tests\.nl" | wc -l → 35
```

45 signature-bearing vs **66 handle-only**. The archive's "the pools already carry structural
signatures … used by 12 production planners" is true of 13 planners and **40 % of the adds**. The
handle-only majority is concentrated in `ColumnarIteratorPlanner` (34 sites), and those are the worst
case: `plan.AddField(context.FieldForName("<>__state"))` and `plan.AddType(context.StateMachineType)`
are **`FieldBuilder` and `TypeBuilder` handles for a type the emitter is mid-way through defining**.

3. **`AmbientLocals: LocalBuilder[]` has no description column at all** and no obvious one: the
   executor's own comment says *"Public Reflection.Emit exposes neither an `ILGenerator` target
   signature nor a `LocalBuilder` owner, so those two associations cannot be rediscovered here."*
   A token writer owns the local-signature blob itself, so ambient locals must become
   **(slot index, `ColumnarTypeRef`)** pairs — which is only possible once the *host* owns the local
   table, i.e. once the declaration host is the writer's (§5). **This is a genuine ordering
   constraint the record does not name.**

### 4.3 What ECMA-335 tables the operands map onto

| operand | user-declared target | external target | generic |
|---|---|---|---|
| Type (`ldtoken/box/castclass/isinst/unbox.any/initobj/newarr/stelem/ldelem`, catch) | `TypeDefinitionHandle` | `TypeReferenceHandle` | `TypeSpecificationHandle` (closed instantiation, arrays, byref) |
| Method (`call/callvirt`) | `MethodDefinitionHandle` | `MemberReferenceHandle` | `MethodSpecificationHandle` |
| Constructor (`newobj`) | `MethodDefinitionHandle` (`.ctor`) | `MemberReferenceHandle` | via TypeSpec parent |
| Field (`ldfld/ldflda/stfld/ldsfld/stsfld`) | `FieldDefinitionHandle` | `MemberReferenceHandle` | via TypeSpec parent |
| String (`ldstr`) | — | `UserStringHandle` (`GetOrAddUserString`) | — |
| PlanLocal / AmbientLocal | local-signature slot index | — | `StandaloneSignatureHandle` |
| Label | IL offsets | — | — |

The generic column is not hypothetical: **30** `TypeBuilder.GetMethod/GetConstructor/GetField` sites
in `ColumnarIlEmitter.cs` are exactly the "rebind a member onto a generic instantiation" operation,
which in ECMA-335 is a MemberRef with a TypeSpec parent.

```
$ grep -c "TypeBuilder.GetMethod(\|TypeBuilder.GetConstructor(\|TypeBuilder.GetField(" ColumnarIlEmitter.cs → 30
```

---

## 5. The declaration host — 015-E's surface, tabulated as the writer's second half

```
$ python3   # brace-matched extent
TryEmitColumnarAssembly lines 3974..5996 = 2023 ;  Decline( sites: 43 ;  PASS comments: 12
```

(§3.9's "2,024 lines / 41 decline sites" is off by 1 and 2 at this tip.)

### 5.1 The twelve passes, verbatim from the source

`PASS 0` enums (i4-underlying + string-backed) → `PASS 0 (structs)` value types → `PASS 0i`
interfaces → `PASS 0a'` base/interface lists → `PASS 0a''` duck interfaces → `PASS 0b` struct methods
→ `PASS 0b'` property accessors → `PASS 0b''` inherited-member shadowing → `PASS 0c` user
constructors → `PASS 0d` default constructors → `PASS 0e` record value members → `PASS 0 (unions)`
abstract base + case types. Then `Pass 2` (bodies), display classes, base-before-derived
`CreateType()`, the entry point, and serialization.

### 5.2 The Reflection.Emit declaration API surface — 141 calls over 27 APIs, file-wide

```
$ grep -oE "\.(DefineType|DefineNestedType|DefineEnum|DefineLiteral|DefineField|DefineMethod|DefineConstructor|
   DefineDefaultConstructor|DefineProperty|DefineGenericParameters|DefineDynamicModule|DefinePInvokeMethod|
   SetConstant|SetCustomAttribute|SetParent|AddInterfaceImplementation|SetImplementationFlags|SetReturnType|
   SetParameters|SetBaseTypeConstraint|SetInterfaceConstraints|SetGenericParameterAttributes|DefineParameter|
   SetGetMethod|SetSetMethod|DefineMethodOverride|CreateType)\(" ColumnarIlEmitter.cs | sort | uniq -c
```

| API | file | in host `3974..5996` | ECMA-335 target | `MetadataBuilder` member (verified present) |
|---|---|---|---|---|
| `DefineMethod` | 28 | 11 | MethodDef | `AddMethodDefinition` |
| `DefineMethodOverride` | 14 | 3 | MethodImpl | `AddMethodImplementation` |
| `DefineType` | 11 | 7 | TypeDef | `AddTypeDefinition` |
| `DefineField` | 11 | 6 | Field | `AddFieldDefinition` |
| `AddInterfaceImplementation` | 10 | 2 | InterfaceImpl | `AddInterfaceImplementation` |
| `SetConstant` | 9 | 2 | Constant | `AddConstant` |
| `CreateType` | 9 | 9 | — (baking is a builder concept; the writer has none) | n/a |
| `DefineGenericParameters` | 6 | 5 | GenericParam | `AddGenericParameter` |
| `DefineConstructor` | 6 | 4 | MethodDef `.ctor` | `AddMethodDefinition` |
| `SetGetMethod` / `SetSetMethod` | 4 / 3 | 3 / 2 | MethodSemantics | `AddMethodSemantics` |
| `SetCustomAttribute` | 4 | 4 | CustomAttribute | `AddCustomAttribute` |
| `DefineProperty` | 4 | 3 | Property + PropertyMap | `AddProperty`, `AddPropertyMap` |
| `DefineNestedType` | 4 | 4 | NestedClass | `AddNestedType` |
| `DefineDefaultConstructor` | 3 | 1 | MethodDef + body | hand-written |
| `SetReturnType` / `SetParameters` | 2 / 2 | 1 / 1 | signature blob | (signature is written once) |
| `DefineParameter` | 2 | 0 | Param | `AddParameter` |
| `SetParent` | 1 | 1 | TypeDef.Extends | field of `AddTypeDefinition` |
| `SetBaseTypeConstraint` / `SetInterfaceConstraints` / `SetGenericParameterAttributes` | 1 each | 1 each | GenericParamConstraint | `AddGenericParameterConstraint` |
| `SetImplementationFlags` | 1 | 1 | MethodDef.ImplFlags | field of `AddMethodDefinition` |
| `DefinePInvokeMethod` | 1 | 1 | ImplMap + ModuleRef | `AddMethodImport`, `AddModuleReference` |
| `DefineLiteral` | 1 | 1 | Field + Constant | `AddFieldDefinition` + `AddConstant` |
| `DefineEnum` | 1 | 1 | TypeDef + `value__` | `AddTypeDefinition` + `AddFieldDefinition` |
| `DefineDynamicModule` | 1 | 1 | Module | `AddModule` |
| **total** | **141** | **75** | | |

**Every row has a `MetadataBuilder` counterpart.** I verified the API surface exists rather than
assuming it (`probe/apiprobe`, reflecting `MetadataBuilder`'s public `Add*`/`GetOrAdd*`): 49 members
including `AddConstant`, `AddCustomAttribute`, `AddGenericParameter`,
`AddGenericParameterConstraint`, `AddInterfaceImplementation`, `AddMethodImplementation`,
`AddMethodImport`, `AddMethodSemantics`, `AddMethodSpecification`, `AddNestedType`, `AddProperty`,
`AddPropertyMap`, `AddStandaloneSignature`, `AddTypeSpecification`, `AddEvent`, `AddEventMap`,
`AddFieldLayout`, `AddTypeLayout`, `AddStateMachineMethod`, `AddModuleReference`.

**`CreateType()` is the one with no counterpart, and that is a feature.** Baking exists because
`TypeBuilder` is a two-phase object; a metadata writer emits rows in dependency order and never
bakes. The nine `CreateType()` calls and the base-before-derived ordering comment become **row
ordering**, not a lifecycle.

### 5.3 The tail is ALREADY `MetadataBuilder` — the biggest de-risking fact in §5

`ColumnarIlEmitter.cs:5975-5992` (inside the host):

```csharp
var metadataBuilder = builder.GenerateMetadata(out var ilStream, out var mappedFieldData);
var peBuilder = new System.Reflection.PortableExecutable.ManagedPEBuilder(
    header: PEHeaderBuilder.CreateExecutableHeader(),
    metadataRootBuilder: new MetadataRootBuilder(metadataBuilder),
    ilStream: ilStream, mappedFieldData: mappedFieldData,
    entryPoint: MetadataTokens.MethodDefinitionHandle(entryPointMethod.MetadataToken));
peBuilder.Serialize(peBlob);
```

The **executable** path already serializes through `MetadataRootBuilder` + `ManagedPEBuilder`; only
the **library** path takes `builder.Save(stream)`. So the PE-writing half of the writer is not new
work — it is a pattern already in the tree, and my probe uses the identical call shape.

---

## 6. What consumes an emitted assembly — nothing in-process

- `MultiFileCompiler.cs:500-501` is the only consumer:
  `TryEmitColumnarAssembly(… out var assembly …); File.WriteAllBytes(outputPath, assembly);`
  (`grep -rn "TryEmitColumnarAssembly" src --include="*.cs"` → 2 hits: the definition and this call.)
  **The emitter's product contract is a `byte[]`, so a second backend is a drop-in at exactly one
  seam.**
- Emission runs on a dedicated 64 MB wide-stack thread (`MultiFileCompiler.EmitOnWideStackThread`).
- `nlc test` does **not** use Reflection.Emit's dynamic path:
  `src/NSharpLang.Cli/Program.Testing.cs` (617 lines) resolves via
  `AssemblyLoadContext.Default.Resolving` → `context.LoadFromAssemblyPath(candidatePath)` and drives
  xunit's `XunitFrontController` over a **file path**. `grep -n "AssemblyLoadContext\|Assembly.Load"`
  returns 6 hits, all path-based. (Under a single-binary AOT `nlc` this still has to become a spawn —
  but that is the type-model decode's and §3.8's ruling, not this task's.)
- `tests/native/systems-proof-corpus/SystemsProofCorpus.tests.nl` **spawns processes** and explicitly
  refuses in-process loading (`:38-42`).
- **`ilverify` coverage:** `scripts/ilverify.sh` builds every example/fixture project and every
  native test assembly with the freshly built CLI, then verifies **every** emitted DLL against the
  resolved shared framework. `wc -l scripts/ilverify-baseline.txt` → **15 lines, all comments —
  the baseline is empty.** Today's emitter output is 100 % verifiable, so `ilverify` is a
  *usable* oracle for a second backend, not a rubber stamp.
- Corpus size: `find tests/native -name project.yml | wc -l` → **40**;
  `find examples -name project.yml | wc -l` → **18**.

---

## 7. N# SPELLABILITY — measured, and the verdict is NO

Probes: `…/8c6daca3-…/scratchpad/probe/nlspell/*`, each a real `nlc build` with the
worktree-built CLI (`src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll`, built at this tip) and
`NSHARP_COLUMNAR_DECLINE_LOG=1`.

| probe | shape | result |
|---|---|---|
| `c00_control` | `new StringBuilder()` + `Append` + `ToString` | **Build successful** |
| `c01` | `import System.Reflection.Metadata.Ecma335; new MetadataBuilder()` | `NL704: I can't find namespace 'System.Reflection.Metadata.Ecma335'` + `NL201: Type 'MetadataBuilder' not found` |
| `c02` | `import System.Reflection.Metadata; new BlobBuilder()` | `NL201: Type 'BlobBuilder' not found` |
| `c03` | fully-qualified `new System.Reflection.Metadata.BlobBuilder()` | reaches emit → **`decline site=emit.local.initializer`** |
| `c04` | `ILOpCode.Ret` | `NL301` — not a known name |
| `c05` | `new InstructionEncoder(b)` | `NL704` + 2 × `NL201` |
| `c06` | `MetadataTokens.MethodDefinitionHandle(1)` | `NL704` |
| `c07` | `PEHeaderBuilder.CreateExecutableHeader()` | `NL704: … 'System.Reflection.PortableExecutable'` |
| `c08` | `md.GetOrAddString("x")` | `NL704` + `NL201` |
| `c09` | **with `nuget: System.Reflection.Metadata`** — `new MetadataBuilder()` | analyzer PASSES; **`decline site=emit.local.initializer` → `emit.statement.block-child` → `emit.body`** |
| `c10` | **with the nuget dep** — `new BlobBuilder()` | same decline chain |

**Verdict: `System.Reflection.Metadata` is not spellable from N# at emit today, in any of the three
forms probed.** This reproduces `SystemsProofCorpus.tests.nl:44-48`'s record for `PEReader` exactly
(*"`nuget:`-sourced types are reflection-only on this emit path"*) and extends it from `PEReader` to
the whole writer surface.

The three walls, in order:

1. **The assembly is not scanned.** `ExternalAssemblyScan.CommonAssemblyNames()` is **27** names
   (`sed -n '598,634p' ExternalAssemblyScan.nl`) and `System.Reflection.Metadata` is not among them —
   even though it ships in `Microsoft.NETCore.App` (`ls …/Microsoft.NETCore.App/10.0.5/ | grep
   Metadata` → `System.Reflection.Metadata.dll`). `AnalyzerMetadataLoadPolicy.CommonAssemblyNames()`
   is pinned equal to it by `AnalyzerMetadataLoadPolicy.tests.nl:169`, so that is **two** rows.
2. **The type is not admitted.** `ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName` carries
   **32** distinct type-name rows — `System.Index`, `System.Range`, `System.RuntimeTypeHandle`, 17
   `System.Reflection.*` and 10 `System.Reflection.Emit.*`. **Zero** `System.Reflection.Metadata.*`.
   With `TryGetRuntimeTypeName` (101 lines) that is rows 3 and 4; the analyzer's own table is row 5 —
   §3.3's "a catalog row is FIVE rows until a sweep says otherwise".
3. **The member has no call plan.** `GetStaticCallPlan` (113 lines) and `GetInstanceCallPlan` (361
   lines) carry no SRM rows, and §3.3's warning applies in full: *"no plan can describe a VALUE
   receiver"*.

### 7.1 And the value-receiver wall is not theoretical for THIS API

```
s01  g := Guid.NewGuid(); g.ToString()      → decline site=emit.local.unsupported-type … 'System.Guid'
s02  user struct with instance method returning a struct   → Build successful
s03  d := new DateTime(2020,1,1); d.Year    → decline site=emit.local.initializer
```

**User** structs with instance methods work. **External** structs work only when catalogued — and the
catalogued external structs (`OpCode`, `Label`, `Index`, `Range`) appear in the catalog as *argument
and return* types, never as receivers of an instance call. SRM is **16 structs to 7 classes**
(`probe/opmap`), and its entire signature API is instance methods on mutable structs that return
further structs:

```
BlobEncoder.MethodSignature(SignatureCallingConvention, Int32, Boolean) -> MethodSignatureEncoder
MethodSignatureEncoder.Parameters(Int32, Action`1, Action`1) -> Void        ← lambdas
MethodSignatureEncoder.Parameters(Int32, ReturnTypeEncoder&, ParametersEncoder&) -> Void  ← byref out
BlobEncoder.LocalVariableSignature(Int32) -> LocalVariablesEncoder
```

Both overloads of `Parameters` are unspellable-shaped for N# today: one takes `Action<T>` (the
`015-B` lambda wall), the other takes two `out`-style byref struct parameters.

**THE MITIGATION, AND IT IS THE ONE THAT MAKES THIS TASK POSSIBLE AT ALL:** the encoder structs are
a convenience layer over `BlobBuilder`, which is a **class** with byte-level members
(`WriteByte`, `WriteCompressedInteger`, `WriteInt32`, …). Every ECMA-335 signature blob can be
written directly. So the N#-side surface reduces to:

- classes only: `MetadataBuilder`, `BlobBuilder`, `ControlFlowBuilder`, `MetadataRootBuilder`,
  `ManagedPEBuilder`, `PEHeaderBuilder`, static `MetadataTokens`;
- handle **structs** as opaque values passed to `MetadataBuilder.Add*` (the same role `Label` and
  `OpCode` already play, which the catalog already supports);
- **`InstructionEncoder` / `MethodBodyStreamEncoder` / `ExceptionRegionEncoder` remain structs with
  no class alternative** — the body stream's tiny/fat header selection, 4-byte alignment and EH
  clause table would have to be hand-written onto a `BlobBuilder` to avoid them. That is real,
  specifiable work (ECMA-335 II.25.4) and it must be priced, not waved at.

**Net spellability price: a catalog widening across ≥5 rows plus ~15 admitted types and ~40 member
plans, ALL of which is inert inside `BootstrapServices` until a toolset repack** — `BootstrapServices`
is `<Project Sdk="NSharpLang.Sdk" />` and compiles under the packaged `NSharpLang.Sdk.0.1.0.nupkg`
from `~/.nuget/local-feed` (§2.1's two-stage wall). Compare: the Reflection.Emit surface needs
**zero** new rows.

---

## 8. THE PROBE — it ran, it executes, it verifies

`…/8c6daca3-…/scratchpad/probe/mdwriter/MdProbe/Program.cs` — a C# console app **outside the repo**
that writes an assembly with `MetadataBuilder` only, **zero `System.Reflection.Emit`**.

```
$ dotnet mdwriter/MdProbe/bin/Release/net10.0/MdProbe.dll out
WROTE out/Emitted.dll (2560 bytes)

$ dotnet Emitted.dll                       # + a hand-written Emitted.runtimeconfig.json
42
7
Int32
RUN EXIT=0

$ NETCORE_DIR=$(dotnet --list-runtimes | awk '$1=="Microsoft.NETCore.App"{…}' | sort -V | tail -1)
$ DOTNET_ROOT=$(cd "$NETCORE_DIR/../../.." && pwd) ~/.dotnet/tools/ilverify Emitted.dll -r "$NETCORE_DIR/*.dll"
All Classes and Methods in …/out/Emitted.dll Verified.
```

Coverage — deliberately chosen to hit the plan-row vocabulary rather than "hello world":

| plan-row concept | probe construct |
|---|---|
| operation 1, operands `NoOperand/Int32/String` | `ldc.i4 42`, `ldstr`, `ret`, `pop`, `dup`, `throw` |
| operand `Type` | `ldtoken System.Int32` → `Type.GetTypeFromHandle` → `get_Name` |
| operand `Argument` | `ldarg.0` in a 1-parameter static |
| operand `PlanLocal` | 3 locals via `AddStandaloneSignature` + `LocalVariableSignature(3)` |
| operand `Method` / `Constructor` / `Field` | `call`/`callvirt` on MemberRef **and** MethodDef; `newobj` on both; `ldfld`/`stfld` on FieldDef |
| operand `Label` | `beq`, `leave` via `ControlFlowBuilder` |
| operations 3,4,6,7 | `try` / `catch (Exception)` / `finally` via `AddCatchRegion` + `AddFinallyRegion` |
| declaration host | TypeDef `<Module>` + `Probe.Program`, instance `.ctor`, private field, 5 MethodDefs, entry point |

### 8.1 The exact API calls the port must reproduce

26 distinct SRM/PE types spelled, ~14 more inferred (encoder chains), and **34 distinct members**:

```
GetOrAddString(22) OpCode(21) Parameters(12) MethodSignature(12) Token(8) MarkLabel(8) DefineLabel(8)
Call(8) AddMemberReference(7) AddParameter(6) AddMethodDefinition(5) AddMethodBody(5) LoadLocal(4)
LoadConstantI4(4) StoreLocal(3) GetOrAddBlob(3) Branch(3) AddVariable(3) AddTypeDefinition(2)
ToArray Serialize LocalVariableSignature LoadString GetOrAddUserString GetOrAddGuid FieldSignature
AddTypeReference AddStandaloneSignature AddModule AddFinallyRegion AddFieldDefinition AddCatchRegion
AddAssemblyReference AddAssembly
```

### 8.2 Three implementation facts the port will otherwise rediscover late

1. **Row ids are positional and must be forward-declared.** A `call` to a MethodDef the writer has
   not yet added needs `MetadataTokens.MethodDefinitionHandle(n)` computed from declaration order.
   My probe asserts the prediction (`if (answerDef != answerDefH) throw …`) and the assert is
   load-bearing — it fired during development. **A production writer needs a real two-pass
   handle-reservation phase, not arithmetic.**
2. **`TypeDef.MethodList`/`FieldList` are range starts,** so `<Module>` and the first real type both
   point at row 1 and ownership is "up to the next TypeDef's start".
3. **`ReturnTypeEncoder` has no `.String()`** — it is `r.Type().String()`; and there is no
   `InstructionEncoder.CallVirtual`, only `OpCode(ILOpCode.Callvirt)` + `Token(...)`. Both cost a
   compile error to discover.

---

## 9. THE ORACLE — byte-identity is NOT achievable as the brief assumes, and I measured why

**Correction first: there is no existing SRM body-dump comparator in the tree.**
`grep -rln "System.Reflection.Metadata\|MetadataReader\|PEReader" tests` returns exactly two files:
`tests/AnalyzerMetadataLoadContextTests.cs` and `SystemsProofCorpus.tests.nl` (whose only mention is
the *record that PE metadata is unreachable from N#*). `grep -rn "GetILAsByteArray\|GetMethodBody()"`
over `scripts tests src` returns one hit — a comment. **The corpus harness does not compare SRM body
dumps; that comparator has to be built.**

### 9.1 Whole-file byte-identity: 17 bytes of nondeterminism, at known offsets

```
$ rm -rf bin obj && nlc build && cp …/Spellc00_control.dll /tmp/a.dll
$ rm -rf bin obj && nlc build && cp …/Spellc00_control.dll /tmp/b.dll
$ cmp -l /tmp/a.dll /tmp/b.dll | wc -l         → 17
$ cmp -l /tmp/a.dll /tmp/b.dll | awk '{printf "0x%x ", $1-1}'
0x88  0x47c 0x47d … 0x48b
```

One byte in the PE COFF `TimeDateStamp` and a 16-byte run = the **MVID**. So even
*self*-comparison needs a normalizer masking 4 + 16 bytes. That is cheap and worth building.

### 9.2 Method-body byte-identity: TWO measured, unavoidable divergences

**(a) `ldarg` narrowing.** The executor documents it (`ColumnarCodePlanExecutor.nl:381-397`):
`Emit(OpCode, short)` does **not** narrow `Ldarg`, so ordinals ≥ 4 stay long-form and *"a planned
body with four or more argument slots is therefore three bytes per load larger than the hand-written
IL it replaces — correct, and not yet byte-identical."* I measured today's product bytes:

```
# N# source: func pick(a,b,c,d,e: int): int { return a+b+c+d+e }
$ nlc build && dotnet run --project probe/dump -- …/ArgShape.dll
pick: maxStack=8 len=13  02 03 58 04 58 05 58 fe 09 04 00 58 2a
                                              ^^^^^^^^^^^  ldarg 4, long form, 4 bytes
```

and what `InstructionEncoder` produces for the same row:

```
n=   0  LoadArgument=[02]        LoadLocal=[06]        StoreLocal=[0a]
n=   3  LoadArgument=[05]        LoadLocal=[09]        StoreLocal=[0d]
n=   4  LoadArgument=[0e 04]     LoadLocal=[11 04]     StoreLocal=[13 04]     ← ldarg.s, 2 bytes
n= 255  LoadArgument=[0e ff]     …
n= 256  LoadArgument=[fe 09 00 01 00 00]   ← 4-byte operand where ECMA-335 III.3.38 says uint16
```

So the second backend is **strictly better** at ordinals 4..255 (2 bytes vs 4) and **wrong** at
≥ 256 if the convenience helper is used. **Rulings this forces:** the writer must emit `ldarg` by
`OpCode(ILOpCode.Ldarg)` + an explicit `WriteUInt16`, *or* the oracle must carry an enumerated,
named allowlist for this one row. My recommendation is the allowlist plus a follow-up slice that
narrows *both* backends, because the narrowed form is the correct one and the record already calls
the current form "not yet byte-identical".

**(b) `ldc.i4`.** The `Int32Operand` row is always `LdcI4` and `il.Emit(OpCodes.Ldc_I4, int)` does
not narrow, while `InstructionEncoder.LoadConstantI4` does. Same ruling.

**(c) `maxStack`.** Today's bodies report `maxStack=8` (the tiny-header value). The plan already
computes exact heights in `ValidateMethodBodyStack`, so the writer *could* emit an exact maxStack and
diverge. It should pass 8 to match, and the exact height stays a validator, not an encoder input.

### 9.3 The oracle I would actually build

Three layers, cheapest first, none of which requires SRM to be spellable from N#:

1. **`ilverify` over both backends** — already exists, baseline empty, covers 40 native projects +
   18 examples.
2. **A differential method-body comparator** (throwaway C#, outside the repo, like `probe/dump`):
   run both executors over every plan the corpus produces, `MetadataReader`-dump each MethodDef body,
   diff bytes with the §9.2 allowlist. This is the *non-vacuity control* — it must be shown to catch
   a seeded mutation before any slice trusts it.
3. **Behaviour**: `nlc test` over all 40 native projects and `nlc build` over all 18 examples, both
   backends, identical outcomes.

---

## 10. PROPOSED STAGED PLAN — 6 slices, re-priced for the corrected premise

**Prerequisite status, stated plainly:** *none of these slices is a prerequisite for a NativeAOT
`nlc`.* The AOT prerequisites are the type-model decode's loader-deletion slices (its §7 slices 1–2
and 5) and `nlc test`'s spawn conversion. Everything below is **ownership and oracle work** and
should be scheduled against `015`, not against AOT.

**Hard dependency on `015-B`:** slices W4–W5 cannot land until plan-row coverage is total, because a
single-backend cutover cannot emit what the C# residual still emits (§3.1: 13/34 expression kinds,
2 statement kinds at the method-body door, 10/21 at the iterator door).

| # | slice | C# it shrinks | closing measurement |
|---|---|---|---|
| **W1** | **The type-reference description model.** Add `ColumnarTypeRef` (external: assembly+namespace+name+generic args; user: declaration identity) and route **all 35 `AddType` sites, all 66 handle-only member adds, and the `AmbientLocals` column** through it. The reflection handle stays as a second column so the existing executor is untouched. | **none** — additive N#. This is a prerequisite slice and must be labelled one. | every production pool add carries a description (a `.tests.nl` census asserts 0 handle-only adds); the whole estate + ilverify byte-identical to the pre-slice tip. Shares its answer with the type-model decode's "one type universe" slice — **coordinate, do not duplicate**. |
| **W2** | **The catalog widening + spellability, behind the two-stage wall.** `System.Reflection.Metadata` into `CommonAssemblyNames` (and its pinned analyzer mirror), ~15 types into `IsSupportedRuntimeTypeName`/`TryGetRuntimeTypeName`, ~40 member plans. **Entry gate: prove the byte-level `BlobBuilder` route works without any encoder struct** — extend `probe/mdwriter` to write every signature blob by hand and re-verify. | none | the §7 probes flip from `NL704`/decline to **Build successful**; `nlc build` of a `.nl` file that constructs a `MetadataBuilder` and writes one MethodDef succeeds. Requires ONE toolset repack at the slice boundary, from a committed tip, behind a green gate. |
| **W3** | **The differential oracle** (§9.3 layer 2), as a throwaway harness outside the repo. | none | catches ≥1 seeded mutation per operand kind (14 mutations, 14 catches); reproduces the §9.2 divergence list exactly and nothing else. **Take this BEFORE W4 — it is what makes W4 falsifiable.** |
| **W4** | **The body writer**: `ColumnarCodePlanMetadataWriter` over the same rows. 7 operation kinds + 14 operand kinds; opcode via `(ILOpCode)(ushort)` (§0.5); region buffering for kind 3 (§2.4); `ldarg`/`ldc.i4` emitted long-form to match (§9.2). Not routed to production. | none yet | every plan the corpus produces replays through both executors with W3 reporting only allowlisted diffs. |
| **W5** | **The declaration host**: port `TryEmitColumnarAssembly`'s 12 passes + the state-machine hosting to `MetadataBuilder` tables (§5.2's 141 calls → the `Add*` rows). This is where `015-E` dies. | **~2,023 lines + the 43 declines** | the writer emits every one of the 40 native projects and 18 examples; ilverify clean; `nlc test` outcomes identical. **Gated on `015-B` totality.** |
| **W6** | **Cutover**: delete `PersistedAssemblyBuilder`, the Reflection.Emit arms of the executor, and the `LocalBuilder`/builder columns of the plan. | the executor's 114 `OpCodes.` sites and the emitter's remaining hosting | one backend; the growth ratchet repinned once, last. |

**If the answer is "not worth it", the honest alternative this decode surfaces** and which should be
weighed at W1's boundary: **port the declaration host to N# on Reflection.Emit instead** (§0.2 —
`ILGenerator`/`TypeBuilder`/`OpCodes` are already catalogued and already driven from N# by
`tests/native/reflection-emit-bootstrap`). That achieves `015-E`'s ownership goal, is AOT-viable per
the type-model decode's native run, needs **zero** catalog widening and **zero** toolset repack, and
leaves W1 (which is owed anyway) as the only shared cost. The `MetadataBuilder` writer then becomes
what it honestly is: an oracle and a dependency-shedding option, schedulable whenever.

---

## 11. Corrections this decode makes to the record

| record | corrected |
|---|---|
| §3.8 "NativeAOT forbids Reflection.Emit outright, so this is not optional" | **False**, disproved by native execution in the parallel decode; the emitter's one builder is `PersistedAssemblyBuilder`, which works under AOT. |
| §3.8 / §4.1 "1,190 `OpCodes.` sites, 177 `TypeBuilder`" | **1,145** and **147** at `8cf40128a` (`015-B` removed 45 and 30). |
| §3.9 "`015-E` … retires with the AOT metadata writer" | **Decoupled** — and further, the host can be N#-owned on Reflection.Emit with no writer at all. |
| archive §"THE AOT DECISION" — the pools "already carry structural signatures … 12 production planners", so the writer is cheap | 13 planners / **45** adds, against **66** handle-only adds; and the "signatures" are `Type` objects, so the prerequisite is a description model, not a column. |
| §3.8 "its ONE named prerequisite is giving `AddType` the same treatment" | **Four**, not one: `AddType`, the 66 handle-only member adds, the `Type`-typed signature columns, and `AmbientLocals: LocalBuilder[]` (which has no description at all and orders after the declaration host). |
| §3.2 / §4.1 "plan-row planner covers 10/21 statement + 7/27 expression kinds" | expression ledger is now **34** kinds with **13** claimed; the 10/21 figure is the **iterator** door, not the method-body door, whose statement claim is 2 kinds. |
| §3.9 "`TryEmitColumnarAssembly` … 2,024 lines / 41 decline sites" | **2,023 lines / 43 declines** (3974..5996). |
| brief's premise "the corpus harness already compares SRM body dumps" | **No such harness exists**; two files in `tests` mention SRM and neither dumps bodies. It must be built (W3). |
| implied "byte-identity between the two executors is the natural oracle" | **Not as stated** — two measured encoding divergences (`ldarg` ≥ 4, `ldc.i4`) plus 17 bytes of per-build nondeterminism. The oracle is body-bytes-modulo-an-enumerated-allowlist. |

## 12. What this decode did NOT settle

- Whether hand-writing the method-body stream (tiny/fat header, 4-byte alignment, EH clause table)
  onto a `BlobBuilder` is acceptable, or whether `MethodBodyStreamEncoder`/`InstructionEncoder`
  (structs) must be made spellable. W2's entry gate exists to answer this by probe.
- Whether `ColumnarOrdinaryRuntimeDirectCallResolver` would bind SRM instance members without
  explicit call plans once the types are admitted (§3.3 warns the catalog is not the binding
  authority — "measure by execution"). Not probed; it needs the W2 widening to be measurable at all.
- The generic surface: 30 `TypeBuilder.GetMethod/GetConstructor/GetField` sites map to
  MemberRef-with-TypeSpec-parent, which my probe does not exercise. The `modreq`/generic-record
  landmines recorded in memory (`project_generic_oracle_arc_complete`) are the ones to re-probe there.
- Performance. `PersistedAssemblyBuilder` is itself a `MetadataBuilder` client, so a direct writer
  should be faster, but I measured nothing.

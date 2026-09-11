# DECODE — the spelling gap: what the ECMA-335 metadata writer needs from N#, and what N# refuses (task 023, slice 1)

Measured in the isolated worktree `…/2c21afb5…/scratchpad/wt/023-s1-spelling-gap` (branch
`stream/023-s1-spelling-gap`), rebased across three coordinator tips during the slice: the Tier A/B
census at `fcba80dad`, the language work at `b3ca5afe6`, the final measurements at `9c3a41ca9`
(= `d9c943a75` + two docs commits). Probes live OUTSIDE the repo at `…/scratchpad/probes/023/`
(48 probe projects). **Every verdict below is a real `nlc check` + `nlc build` with the worktree's own
CLI, and every PASS marked RUN was executed.** The API surface was enumerated from the reference
pack's `System.Reflection.Metadata.{dll,xml}` with `ilspycmd` and the shipped XML doc IDs — no C# was
written for this slice, for the probes or for the census.

---

## 0. Headline — four sentences

1. **The writer is spellable from N#, and the proof is that it wrote a running assembly.** A 105-line
   N# program drives `MetadataBuilder` alone — no `System.Reflection.Emit` — and writes a 2,048-byte
   `Emitted.dll`; that assembly RUNS under `dotnet` on the shared framework and prints its string with
   exit 0, and `ilverify` answers *"All Classes and Methods … Verified."*
2. **Four of the six walls the 2026-09-01 decode predicted are not walls at this tip.** An instance
   call on an external STRUCT receiver, an external struct in a plain local, one returned by value
   from a call, and a chained call on a call result all PASS and RUN. That decode's "no plan can
   describe a VALUE receiver" verdict is superseded for these shapes.
3. **The two walls that were real were not language walls at all — they were closed allow-lists**, of
   exactly the class task 022 slice 3a-i had just retired for construction. External enum members were
   admitted per MEMBER (`MethodAttributes.Public` bound, `MethodAttributes.Static` did not); the
   writer's assembly was not scanned and its types were not admitted. Both are now fixed
   (`023/1a`, `023/1b`).
4. **The SRM encoder layer is refused by design, not left as a gap.** Every signature entry point has
   exactly two overloads — one taking `out` byref structs, one taking `Action<T>` — and both are off
   the N# surface. The writer encodes its own blobs byte by byte onto a `BlobBuilder`, which is
   ECMA-335 II.23.2 work the writer should own anyway, and which reduces the required surface from
   ~200 members over ~60 types to ~95 over ~20.

---

## 1. The member table — what the writer needs

Counted from the emitter's own executable path plus the Reflection.Emit executor's `Define*`/`Set*`
census in `ColumnarIlEmitter.cs` (`DeclareLocal` 111, `MakeGenericType` 95, `MarkLabel` 48,
`DefineLabel` 48, `GetILGenerator` 39, `DefineMethod` 28, `DefineMethodOverride` 14, `DefineType` 11,
`DefineField` 11, `AddInterfaceImplementation` 10, `SetConstant` 9, `CreateType` 9,
`DefineGenericParameters` 6, `DefineConstructor` 6, exception openers 11, property accessors 11,
`DefinePInvokeMethod` 1, `DefineEnum`/`DefineLiteral` 2, `DefineDynamicModule` 1, …).

| group | members | status |
|---|---|---|
| the PE tail the emitter drives today (`ColumnarIlEmitter.cs:5900-5912`) | 8 | **all spellable** |
| `MetadataBuilder` — 27 of its 44 `Add*` + 5 of its 10 `GetOrAdd*` + ctor | 33 | **spellable** |
| `BlobBuilder` byte level | ~19 | **spellable** |
| `MetadataTokens` handle factories + `GetRowNumber`/`GetHeapOffset` | ~33 | **spellable** |
| the 28 handle structs (+ `LabelHandle`) | 31 admitted | **spellable** |
| the flag enums the writer sets | ~14 used | **spellable** (023/1a) |
| the encoder layer — `BlobEncoder`, `SignatureTypeEncoder`, `MethodSignatureEncoder`, `ParametersEncoder`, `ReturnTypeEncoder`, `LocalVariablesEncoder`, `GenericTypeArgumentsEncoder`, `CustomAttributeSignatureEncoder` and 6 more | ~50 over 14 struct types | **REFUSED — §4** |
| the body layer — `MethodBodyStreamEncoder`, `InstructionEncoder`, `ControlFlowBuilder`, `ExceptionRegionEncoder`, `ILOpCode` | ~40 | **REFUSED — §4** |

The table→writer mapping the census implies: `DefineDynamicModule`→`AddModule`;
`DefineType`/`NestedType`/`Enum`→`AddTypeDefinition` (+`AddNestedType`, `AddTypeLayout`);
`SetParent`→the TypeDef `Extends` column; `AddInterfaceImplementation`→same;
`DefineField`/`DefineLiteral`→`AddFieldDefinition` (+`AddConstant`, `AddFieldLayout`,
`AddFieldRelativeVirtualAddress`); `DefineMethod`/`Constructor`/`DefaultConstructor`/`TypeInitializer`
→`AddMethodDefinition`; `DefineParameter`→`AddParameter`;
`DefineMethodOverride`→`AddMethodImplementation`; `DefinePInvokeMethod`→`AddMethodImport`
(+`AddModuleReference`); `DefineProperty`+accessors→`AddProperty`+`AddPropertyMap`
+`AddMethodSemantics`; `DefineGenericParameters`+constraints→`AddGenericParameter`
+`AddGenericParameterConstraint`; `SetCustomAttribute`→`AddCustomAttribute`;
`DeclareLocal`→`AddStandaloneSignature`; `MakeGenericType`→`AddTypeSpecification`
(+`AddMethodSpecification`); external operands→`AddTypeReference`+`AddMemberReference`
+`AddAssemblyReference`; `ldstr`→`GetOrAddUserString`.

---

## 2. Four predicted walls that are NOT walls (measured, and RUN)

The 2026-09-01 metadata-writer decode priced the encoder chain as unreachable partly because
*"no plan can describe a VALUE receiver"* and because the catalogued external structs (`OpCode`,
`Label`, `Index`, `Range`) *"appear in the catalog as argument and return types, never as receivers"*.
Measured on already-catalogued types, so the answer is not masked by the admission gate:

```
a01  op := OpCodes.Ret ; n := op.get_Name()                    PASS   RUN prints "ret"
a02  op := OpCodes.Ret                (external struct, plain local)   PASS
a02b _h := typeof(int).get_TypeHandle()  (struct returned by a CALL)   PASS   RUN
a02c _op: OpCode = OpCodes.Ret        (typed local)                    PASS
a03  typeof(int).get_Name().ToUpperInvariant()   (chain on a result)   PASS   RUN prints "INT32"
a09  m.get_Name() on a MethodInfo — declared on MemberInfo             PASS   RUN
a11  Path.Combine(a, b) with a `params` sibling overload               PASS   RUN prints "a/b"
```

`a09` matters beyond itself: it de-risked `PEBuilder.Serialize`, the base-declared member the writer
calls on a `ManagedPEBuilder`. `a11` confirms the selection rule's escape hatch — an exact full-arity
match survives excluded siblings (`bestScore == argCount * 8`,
`ColumnarOrdinaryRuntimeDirectCallResolver:256`).

**The one shape with no precedent anywhere in the estate turned out to work.** Nothing in the whole
N# estate ever put an external struct in a *plain local*: `ColumnarCodePlanExecutor.nl:218,228` only
ever stores `il.DefineLabel()` into an ARRAY SLOT. `a02` was the probe that decided whether handles
could be named at all, and it passes.

---

## 3. The walls that were real — and both were allow-lists, not language

### 3.1 External enum members were a per-MEMBER hand list (fixed: 023/1a)

```
a08c  a := MethodAttributes.Public                    PASS
a08g  a := MethodAttributes.Static                    decline  emit.local.initializer
a08h  q := MethodAttributes.Family                    decline  emit.local.initializer
a08   Take(MethodAttributes.Public | ..Static)        decline  (argument position)
a08b  a := MethodAttributes.Public | ..Static         decline  (local initializer)
a08i  f := BindingFlags.Public | BindingFlags.Static  PASS     RUN prints 24
```

The `|` was never the problem — `a08i` proves it. `ColumnarExternalBindingPlans.nl:272` read
`&& memberName == "Public"`. Eight enum rows stood in `GetStaticMemberPlan`: four admitting a WHOLE
enum and four admitting ONE member each. The `BindingFlags` row had already written down why the whole
type is the only coherent answer — *"a mask is USED by combining its members, so admitting a subset
would only move the decline"* — and the four per-member rows were exactly that decline, moved one step
later. All eight are deleted; the rule is now general in
`ColumnarExternalStaticMemberPlanner.TryAppendExternalEnumMember`, fenced on an int32-representable
backing (`Convert.ToInt32` over a wider constant THROWS — a compiler crash, not a decline) and on the
owner resolving to an enum (a non-enum owner still needs its own row).

### 3.2 The writer's assembly and types were not in the catalog (fixed: 023/1b)

```
b01  import System.Reflection.Metadata + new BlobBuilder(16)          NL201 Type not found
b03  import System.Reflection.Metadata.Ecma335                        NL704 namespace not found
b05  import System.Reflection.PortableExecutable                      NL704
b07  func Take(h: StringHandle)                                       NL201
b02  new System.Reflection.Metadata.BlobBuilder(16)   fully qualified — analyzer PASSES, emit declines
b09  func Take(h: System.…Metadata.StringHandle)      emit.declaration.function-param
b10  System.…Ecma335.MetadataTokens.MethodDefinitionHandle(1)         Variable 'System' not found
```

**`b10`/`b11`/`b12` are the load-bearing measurement.** A fully-qualified `new` and a fully-qualified
PARAMETER type both reach emit, but a fully-qualified STATIC RECEIVER does not bind at all. So the
scan row cannot be worked around by qualifying, and `MetadataTokens` — which every handle in the
writer comes from — is unreachable without it.

**The row set was sized by measurement and came out 37, not the 27 the plan estimated:**

- an **enum type needs no row**: 023/1a made members bind through the planner, and `TypeAttributes`,
  `AssemblyFlags` and `CorFlags` bind with nothing on `IsSupportedRuntimeTypeName`;
- a **static-only owner needs no row**: `MetadataTokens` resolves as a static-call owner, and
  `PEHeaderBuilder.CreateExecutableHeader()` binds as a CALL with only its RESULT type needing
  admission;
- **`PEBuilder` does need one**, as the DECLARING type of `Serialize` — the 015-B11 `get_Module` shape
  exactly: a base-declared member is a separate admission from the receiving type's;
- the **handle family is admitted whole** (31 names), because a writer that can declare a
  `TypeDefinitionHandle` and not a `MethodSpecificationHandle` is 023/1a's defect one table over.

**`IsSupportedRuntimeTypeName` remains a closed allow-list and that is recorded as a defect**, of the
same class as the construction list 022/3a-i retired and as `ColumnarTypeOfPlanner.IsSupportedType`.
The rule it is to be replaced by is *"a catalog-resolvable type is supported"*, after 022/3a's
resolution helper is shared. Not built here.

---

## 4. The encoder layer is refused, and the refusal is priced

Every SRM signature entry point publishes exactly two overloads, and BOTH are off the N# surface:

```
MethodSignatureEncoder.Parameters(Int32, Action<ReturnTypeEncoder>, Action<ParametersEncoder>)
MethodSignatureEncoder.Parameters(Int32, ReturnTypeEncoder&, ParametersEncoder&)
BlobEncoder.CustomAttributeSignature(…)   LiteralEncoder.TaggedScalar/TaggedVector(…)
NamedArgumentsEncoder.AddArgument(…)      SignatureTypeEncoder.Array(…)
```

`ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedSignatureType` (`:414`) refuses any parameter
or return that `get_IsByRef()`, and `IsIntrinsicExcludedShape` (`:378`) refuses generic methods,
varargs and any `params` parameter; the `Action<T>` sibling needs a lambda into an external generic
delegate, which the 015-B door does not claim. Measured:

```
a06  l.ForEach(x => Sink(x))  on List<int>     decline  emit.expression-statement.call
a05  d.TryGetValue("a", out v) on Dictionary   PASS     RUN  — `out` is a CATALOG question, not a
a05b DateTime.TryParse(s, out d)               decline    blanket byref refusal
```

**The mitigation is not a workaround, it is the right architecture.** `BlobBuilder` is a class with
byte-level members, and every ECMA-335 signature blob and method body can be written directly onto it.
That drops 14 struct types and ~90 members from the required surface, and it removes struct-receiver
chaining from the writer entirely: in the byte-level spelling every handle is only ever a by-value
argument or return — exactly the role `Label` and `OpCode` already play.

---

## 5. The remaining language gaps, each with its probe

| gap | probe | exact text | verdict |
|---|---|---|---|
| no implicit conversion operator, at an argument or a typed local | `a04`, `a04b`, `c03b` | ``Cannot pass `int` as argument for parameter `i` of type `Index` ``; `NL402 … Available overloads: - AddTypeReference(EntityHandle, StringHandle, StringHandle)` | **spelled around, contracted** — `MetadataTokens.EntityHandle(<token>)` is an exact overload, and the token comes from the writer's own declaration order, which is the two-pass row reservation a from-scratch writer needs anyway |
| the literal `0` does not convert to an external enum | `d01`, `d02` | `Variable 'f' is typed as 'AssemblyFlags', but the value is 'int'`; ``Cannot pass `int` as argument for parameter `f` of type `AssemblyFlags` `` | **FILED, sized** — §6 |
| an in-range integer literal does not store into a `byte[]` element | `a10b` | `emit.statement.block-child` (node kind 23) at `b[0] = 65` | **FILED, sized** — §6. `v: byte = 65` (`a10f`), `Take(65)` into a `byte` parameter (`a10g`) and `Convert.ToByte(65)` (`a10e`) all PASS, so the wall is the element STORE alone |
| an omitted defaulted parameter declines | `c02b` | `emit.local.initializer` on `new MetadataBuilder()` | **spelled around** — the writer passes full arity everywhere, including `ManagedPEBuilder`'s eleven arguments |
| `DateTime.TryParse(s, out d)` is not modeled | `a05b` | `emit.call.static-member-unmodeled … 'DateTime.TryParse' with 2 argument(s)` | **FILED** — a catalog row question, not a byref refusal (`a05` passes) |
| a fully-qualified static receiver does not bind | `b10`, `b11`, `b12` | `Variable 'System' not found` | **FILED** — qualified-name resolution is a slice of its own |
| `NL010` mis-attributes `System.IO` | `a15` | `The import 'import System.IO' is not used by any code in this file` for `SearchOption.TopDirectoryOnly` | **FILED** — analyzer import-usage attribution; the same shape in `System.Globalization` (`a16`) is clean |
| `AssemblyFlags` publishes no zero-named member | — | — | **FILED with the literal-zero gap** — until it lands, the writer spells zero as `AssemblyFlags.PublicKey & AssemblyFlags.Retargetable` |

---

## 6. Why the two constant-conversion gaps were FILED and not landed

They are two DIFFERENT C# rules and the brief's single sentence conflated them:

- **§10.2.4, implicit enumeration conversions** — only a constant expression *with the value zero*
  converts to an enum type. `TypeAttributes t = 0;` compiles in C#; `TypeAttributes t = 1;` does not.
  Adopting "any in-range literal" would make N# laxer than C# and would silently accept
  `AssemblyFlags = 7` for a combination that names nothing.
- **§10.2.11, implicit constant expression conversions** — *any* in-range `int` constant converts to
  `byte`/`sbyte`/`short`/`ushort`/`uint`/`ulong`. That is `b[0] = 65`, a numeric rule, not an enum one.

**And they are not small.** The typed-local gate is
`AnalyzerVariableDeclaration.ReportIfNotAssignable` → `assignabilityValue.IsAssignable(target, source)`
— a `TypeInfo`-to-`TypeInfo` predicate with **45 call sites** and no literal in scope. The argument
position is a different owner (`AnalyzerOverloadScoring` → `ErrorMessageBuilder.TypeMismatch`). And the
typed-local emit coercion lives in `ColumnarIlEmitter.cs`, which is **C#** — and this task forbids
adding C#, so either the rule is confined to owners already in N# or that owner is ported first. Each
of the three is its own slice with its own contracts and census; folding them into a measurement slice
is the shortcut this task exists to refuse.

---

## 7. What this decode changes for slices 2–4

- **Slice 2 is unblocked and its spelling is decided**: byte-level blobs and bodies onto `BlobBuilder`,
  handles by value, `EntityHandle` by token, two-pass row reservation, full arity everywhere.
- **The two-stage wall is a sequencing constraint on slice 2, not a surprise.** The writer will live in
  `BootstrapServices`, which compiles under the PACKAGED SDK, so `023/1b`'s catalog rows are inert
  inside it until the coordinator republishes — exactly the boundary `022/3a-i`→`3a-ii` already crossed
  once in this arc.
- **The 015-B11 lesson generalises**: `PEBuilder` needed admitting even though no writer source line
  names it. A base-declared member is a separate admission from the receiving type's, and the writer's
  surface must be sized against DECLARING types, not spelled ones.
- **`compile-time-bench` is a load-dependent timing gate and this arc reproduced that a third time**
  (median 16,761ms / 13,549ms against an 11,802ms limit whose baseline records an *idle machine* and
  pins CLI `8cf40128a`). Its stage is "front-end (parse + strict lint)"; neither an emit-planner nor a
  catalog-row change touches it.

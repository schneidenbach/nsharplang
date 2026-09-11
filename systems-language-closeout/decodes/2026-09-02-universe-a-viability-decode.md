# DECODE — is universe A reachable with `PersistedAssemblyBuilder`? (task 022, slice 2h)

Measurement only; **no product file was changed**. Measured at `e8c9f456b` (branch
`stream/022-s2-one-universe`). The probes live OUTSIDE the repo at
`…/8c6daca3…/scratchpad/probes/mixeduniverse` and `…/probes/universeA`; every verdict below is the
result of BUILDING an assembly and, where the row says RUN, of executing it under `dotnet`.

"Universe A" is the direction ruled after slice 2's decode: the builder is cored on the metadata
context, every `typeof(X)` in a signature or operand position routes through one N#-owned emit-universe
facade, and user `TypeBuilder`s live in that universe.

## 0. Headline — three sentences

1. **Universe A is unreachable through `PersistedAssemblyBuilder`, and the wall is structural.** No
   arrangement of builder core and operand universe can emit a member call on an external generic
   closed over a builder-defined type (`List<Foo>().Add(x)` where `Foo` is a user type) — the four
   possible arrangements were built and run, and each fails in a different, measured way.
2. **The half of universe A that DOES work is worth having, and it makes a deletion possible**: coring
   the metadata context on the REFERENCE PACK makes emitted TypeRefs point at the contract assemblies
   (`System.Object@System.Runtime`, `List\`1@System.Collections`) instead of `System.Private.CoreLib`,
   and that executable RUNS — which is exactly the condition under which `EmitIlAssembly.cs`'s Cecil
   corelib→contract TypeRef rewrite becomes redundant.
3. **The only remaining route to universe A is the `MetadataBuilder` second executor that task 022
   put out of scope** — writing the `TypeSpec` and its `MemberRef`s directly instead of asking
   `TypeBuilder.GetConstructor`/`GetMethod` for them. That ruling was made on the premise that
   `PersistedAssemblyBuilder` suffices; for universe A it measurably does not.

## 1. The four arrangements, built and run

| arrangement | builder core | operands | closes `List<UserType>` | member access on it | emitted AsmRefs | RUNS |
|---|---|---|---|---|---|---|
| **today** | runtime `typeof(object).Assembly` | runtime | **YES** (M15) | YES | `System.Private.CoreLib`, `System.Console` | **YES** (C1exe: `exit=0 out=C1exe EXECUTED`) |
| **mixed** (slice 2's reading) | runtime | MLC | **NO** (M14) | — | corelib ref DUPLICATED | **NO** (L1: `MissingMethodException: Console.WriteLine(String)`) |
| **universe A** | MLC | MLC | **NO** via `MakeGenericType` (B4); declarative-only via `MakeGenericSignatureType` (B5/B6) | **NO** (S4–S7) | contracts when ref-pack-cored (B2/B6) | YES for what it can build |
| **hybrid** | MLC | MLC, generic DEFINITIONS from `typeof(...)` | YES to construct | reaches the handles | corelib ref DUPLICATED | **NO** (S8: `MissingMethodException: List\`1.Add(!0)`) |

### 1.1 The wall, verbatim

```
B4  MLC-cored builder, mlcList.MakeGenericType(userTypeBuilder)
    ArgumentException: This type 'Type: UserType' was not loaded by the MetadataLoadContext that
    loaded the generic type or method.
```

It is not about the builder's core assembly — B4 is MLC-cored and fails identically to M14, which was
runtime-cored. `RoType.MakeGenericType` requires every argument to have been loaded by the SAME
`MetadataLoadContext`, and a `TypeBuilder` is created by `ModuleBuilderImpl` and never is. The
asymmetry is exact and was measured both ways: a RUNTIME open definition closes over a `TypeBuilder`
(M15) and over an MLC type (M8) and saves clean (M17); an MLC open definition closes over neither a
runtime type (M7) nor a `TypeBuilder` (M14/B4).

### 1.2 `MakeGenericSignatureType` — the route that exists, and where it stops

```
S1 signature type as a METHOD RETURN type                                   PASS
S2 signature type as a PARAMETER type                                       PASS
S3 signature type as a LOCAL (DeclareLocal)                                 PASS
B5 signature type as a FIELD type, MLC-cored, saved as an EXE, RUN          PASS (exit=0)
S4 listOfUser.GetConstructor(...)      NotSupportedException: This method is not supported on signature types.
S5 TypeBuilder.GetConstructor(sig, openCtor)  ArgumentException: 'type' must be or must contain a TypeBuilder as a generic argument.
S6 TypeBuilder.GetMethod(sig, openAdd)        ArgumentException: (same)
S7 newobj + callvirt through those handles    ArgumentException: (same)
```

So a signature type covers every DECLARATIVE position — field, parameter, return, local — and cannot
reach a MEMBER. `newobj List<Foo>()` and `callvirt List<Foo>::Add` have no route. That is not an edge
case: it is how the corpus uses external generics.

### 1.3 The hybrid fails for the same reason the mixed universe did

`typeof(List<>)` is a runtime handle and is green under NativeAOT by construction, so "definitions from
`typeof`, everything else from metadata" looked viable. It builds and reaches the handles, and then:

```
HYB AsmRefs: System.Private.CoreLib | System.Console | System.Private.CoreLib
HYB RUN: exit=134  MissingMethodException: Method not found: 'System.Void System.Collections.Generic.List`1.Add(!0)'.
```

A DUPLICATE corelib AssemblyRef, and an image that does not bind — the M10/L1 pathology exactly.
`ModuleBuilderImpl` maps `System.String`/`System.Void` to ECMA primitive element types only when the
type's `Assembly` is REFERENCE-EQUAL to the builder's core assembly, so any second corelib object in
the module costs both the primitive encoding and a second AssemblyRef row. Two corelib objects is the
single predictor of a non-binding image across every red row here.

## 2. What ref-pack coring buys (question ii)

`System.Object` is defined by `System.Private.CoreLib.dll` in the shared framework and by
`System.Runtime.dll` in `Microsoft.NETCore.App.Ref/10.0.5/ref/net10.0` — verified by scanning both
directories' TypeDef tables rather than assumed.

```
B1  MLC cored on System.Private.CoreLib   AsmRefs: System.Private.CoreLib | System.Console
                                          TypeRefs: System.Object@System.Private.CoreLib      RUN exit=0
B2  MLC cored on the REF PACK's System.Runtime
                                          AsmRefs: System.Runtime | System.Console
                                          TypeRefs: System.Object@System.Runtime              RUN exit=0
B6  same + a signature-typed List<UserType> field
                                          AsmRefs: System.Runtime | System.Console | System.Collections
                                          TypeRefs: System.Object@System.Runtime | List`1@System.Collections   RUN exit=0
```

**Ref-pack coring points every emitted reference at the contract assemblies and the executable still
runs.** Today's emitter does not: a real corpus program (`examples/01-hello-world`, built by the tip
CLI) writes `System.Object@System.Private.CoreLib`, `System.String@System.Private.CoreLib`,
`DefaultInterpolatedStringHandler@System.Private.CoreLib`. `System.Private.CoreLib` is the one runtime
assembly with no reference-pack counterpart, which is why `EmitIlAssembly.cs` carries a Cecil
corelib→contract TypeRef rewrite at all (021/8: without it `csc` answers
`CS0012: The type 'Object' is defined in an assembly that is not referenced`). **If the emitter cores
on the ref pack, that rewrite becomes a deletion** — it is worth taking on its own, independently of
the generic wall.

## 3. The `typeof` facade census (question iv)

`ColumnarIlEmitter.cs`: **1,800** `typeof(` sites, **170** distinct arguments, dominated by primitives
(`string` 297, `int` 266, `void` 93, `bool` 75, `object` 61, `char` 50, `List<>` 44, `double` 44).

| class | sites | what it is |
|---|---|---|
| EMIT-OPERAND/SIGNATURE | 598 | argument to `Emit`/`Define*`/`SetParameters`/`SetReturnType`/`DeclareLocal`/`MakeGenericType`/`Get{Method,Field,Constructor}` |
| COMPARISON/DISPATCH | 654 | `== typeof(X)`, `is`, `IsAssignableFrom`, `switch` over a resolved `Type` |
| OTHER | 539 | `Type`-valued expressions feeding the two above |
| COMPILER-OWN-TYPE | 9 | `typeof(NSharpLang.Runtime.*)` |

**The comparison class cannot stay runtime, and that is the number that matters.** Slice 2's decode
measured `mlcString == typeof(string)` → `False`, `.Equals` → `False`, `IsAssignableFrom` → `False`,
with identical `FullName` and `AssemblyQualifiedName` strings. So every one of the 654 comparisons
silently flips the moment the operand is metadata-sourced. Only the 9 compiler-own sites are
genuinely internal. **The facade is ~1,791 of 1,800 sites in this file alone**, not the
signature-position subset the plan assumed.

## 4. The honest A/B terminal condition for 2e–2g (question iii)

The condition slices 2a–2d were held to — normalised whole-PE identity plus `IL_DIFFS=0` over
name-resolved method bodies — **cannot be carried into 2e–2g and must not be pretended**:

- Ref-pack coring CHANGES TypeRef targets by design (`@System.Private.CoreLib` → `@System.Runtime`,
  `@System.Collections`). Whole-PE identity is impossible.
- The body dumper resolves each token to `namespace.type::member@scope`, so the scope change makes
  nearly every body that touches a BCL member differ. Raw `IL_DIFFS=0` is impossible too.

What IS honest, and what I propose:

1. **Scope-normalised body identity.** Same name-resolved body dump, with the resolution scope mapped
   through a contract-equivalence table (`System.Private.CoreLib` ≡ the contract assembly that
   forwards the type). Two builds are equal when every body's opcode sequence and every operand's
   `namespace.type::member` + signature agree, ignoring which assembly declares it. That is the real
   invariant: same program, same members, different declaring-assembly spelling.
2. **A behavioural gate, because the byte comparison no longer carries the proof.** Every one of the
   52 `.tests.nl` corpus projects stays green through `nlc test`, and every executable corpus program
   produces byte-identical stdout and exit code before and after.
3. **`ilverify` unchanged against `scripts/ilverify-baseline.txt`** — a malformed TypeRef/AssemblyRef
   table is exactly the failure this arc can produce, and it is the only gate that reads the metadata
   for correctness rather than for equality.
4. **The decline census stays 0** and the estate count moves only by the blocks added.

## 5. What this means for the queue

- **2e–2g as scoped cannot land.** They retire the runtime half of the catalog, and the measurement
  says the emitter still needs a runtime open generic definition to reach a member of `List<Foo>`.
- **The ref-pack coring half is separable and is worth taking**: it is a real AOT win (no
  `Assembly.Location`, no runtime corelib identity), it makes emitted assemblies C#-consumable without
  Cecil, and it was measured to RUN. It does not depend on the generic question.
- **The `MetadataBuilder` second executor is no longer optional for universe A.** Task 022's
  out-of-scope note rules it out because "`PersistedAssemblyBuilder` is already a `MetadataBuilder`
  client and already works under NativeAOT". That is true for everything except this one operation.
  Emitting the `TypeSpec` + `MemberRef` directly is the only measured route to a metadata-universe
  emitter, and the ruling should be re-taken with that on the table.

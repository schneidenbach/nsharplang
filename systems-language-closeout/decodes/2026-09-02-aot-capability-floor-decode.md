# DECODE — the AOT capability floor (task 022, slice 1)

Measurement only; **no product file was changed**. Measured at `385b7e8d1` in the isolated worktree
`…/2c21afb5…/scratchpad/wt/022-s1-aot-floor` (branch `stream/022-s1-aot-floor`). The probe lives
OUTSIDE the repo at `…/2c21afb5…/scratchpad/probes/aotfloor` (970 lines, one program, two hosts);
the hardened census tool is at `…/probes/memberscan2`. Raw TSV, publish logs and the merge script are
in `…/8c6daca3…/scratchpad`.

This decode supersedes the "not proven" list in `2026-09-01-aot-type-model-decode.md` §4 and corrects
four of its numbers. Every verdict below is the RUNTIME result of executing a Mach-O arm64 binary; no
verdict is read off an analyzer warning.

## 0. Headline — three sentences

1. **The persisted-emit pipeline works end to end under NativeAOT over `MetadataLoadContext` types —
   including the EXECUTABLE path the previous decode never touched.** The native binary built a
   `PersistedAssemblyBuilder` whose core assembly is an MLC `RoAssembly`, drove all 124 opcodes, all
   five exception-region openers, `DefineMethodOverride`, `DefinePInvokeMethod`, enums, properties,
   generic parameters and constraints, called `GenerateMetadata` + `ManagedPEBuilder`, wrote a 2,560-byte
   executable, and **that executable then ran under `dotnet` and printed its string**.
2. **`CustomAttributeBuilder` cannot be CONSTRUCTED under NativeAOT.** `new CustomAttributeBuilder(ctor, args)`
   throws `PlatformNotSupportedException: Dynamic code generation is not supported on this platform.` in
   both universes and for every argument shape. The emitter has four such sites. **The substitute is
   measured and green: `SetCustomAttribute(ConstructorInfo, byte[])`, the raw-blob overload, PASSES
   under NativeAOT in both universes** — and it also sidesteps a second, independent MLC wall.
3. **The runtime type universe degrades under NativeAOT in three ways the metadata universe does not**:
   `Assembly.LoadFrom` throws, `MemberInfo.MetadataToken` throws, and member lookups on BCL types
   **return null** for members the image did not keep — silently, even when the app calls them. Every
   one of those three is green over MLC types. That is the measured case for slice 2.

## 1. What was run

```
probe            …/probes/aotfloor          970 lines, ONE program, host named by AOTFLOOR_HOST
CoreCLR host     dotnet build -c Debug -p:PublishAot=false   →  dotnet aotfloor.dll <fxdir> <outdir>
NativeAOT host   dotnet publish -c Release -r osx-arm64 /p:PublishAot=true
                 → bin/Release/net10.0/osx-arm64/publish/aotfloor   (Mach-O 64-bit arm64, 3,842,376 bytes)
fxdir            /opt/homebrew/Cellar/dotnet/10.0.105/libexec/shared/Microsoft.NETCore.App/10.0.5
rows             CoreCLR 416 · NativeAOT 421 · 408 joined cells
```

**A trap worth recording: a `PublishAot=true` project bakes `IsDynamicCodeSupported=false` into the
runtimeconfig of its ORDINARY build output too.** The first CoreCLR run therefore reported itself as
`NATIVEAOT` and `DefineDynamicAssembly` threw there as well — a false red for the whole CoreCLR
column. The CoreCLR host must be built with `-p:PublishAot=false`, and the host label must come from
the harness, not from `RuntimeFeature`.

## 2. Verdict counts

| host | PASS | AOT-RED | TRIM-RED | RED (other) | n/a |
|---|---|---|---|---|---|
| CoreCLR   | 387 | 0 | 1 | 10 | 13 |
| NativeAOT | 345 | 9 | 36 | 18 | 13 |

The vocabulary is three-way on purpose. **AOT-RED** is a NativeAOT capability limit
(`PlatformNotSupportedException` / "dynamic code generation"). **TRIM-RED** is the target being absent
from the image — slice 5's rooting problem, not a capability limit. **RED** is everything else,
verbatim, never folded into the other two. No `[DynamicDependency]`, no `rd.xml`, no trim roots were
used; a red slice 5 must fix is the point of the measurement.

## 3. The red cells that matter, and what they do to slices 2–5

### 3.1 `CustomAttributeBuilder` — the one genuine emit blocker (slice 5, and slice 2 gets it free)

```
NativeAOT · runtime   A13a1 new CustomAttributeBuilder(ctor, no args)   AOT-RED
NativeAOT · mlc       A13a1 new CustomAttributeBuilder(ctor, no args)   AOT-RED
  PlatformNotSupportedException: Dynamic code generation is not supported on this platform.
NativeAOT · both      A13b1 (string arg, the Trait shape) and A13c1 (runtime-sourced ctor)  AOT-RED, same message
NativeAOT · both      A13d TypeBuilder.SetCustomAttribute(ctor, byte[] blob)                PASS
NativeAOT · both      A13e MethodBuilder.SetCustomAttribute(ctor, byte[]) with a string arg PASS
```

Four estate sites construct a `CustomAttributeBuilder`: `ColumnarIlEmitter.cs:4117` (`IsByRefLike` on
a ref struct), `:4960` (`IsReadOnly`), `:5882` (xunit `Trait` with two string arguments) and `:5883`
(`Fact`). **Under a NativeAOT `nlc` none of them can run**, so ref-struct and readonly-struct
attributes and every emitted test attribute would be lost — silently, since the exception is thrown
by the builder's constructor, not by the emit. The fix is not rooting and not a fallback: it is the
blob overload, which is green on both hosts and in both universes.

The same substitution closes an independent wall that has nothing to do with AOT:

```
CoreCLR · mlc   A13b1 new CustomAttributeBuilder(ctor, string arg)
  ArgumentException: An invalid type was used as a custom attribute constructor argument, field or property.
```

`CustomAttributeBuilder` validates each argument's type against the *runtime* `typeof(string)` while an
MLC-cored constructor's parameter is an MLC `String`, so a fully MLC-cored builder cannot write an
attribute WITH ARGUMENTS at all. A13c proves the diagnosis: the same call with a RUNTIME-sourced
constructor passes on CoreCLR. So slice 2 would hit this wall the moment it makes the builder
MLC-cored — and the blob overload removes it at the same time it removes the AOT blocker. **One
change, two walls.**

### 3.2 The runtime loaders (slice 2)

```
NativeAOT · runtime   Assembly.LoadFrom(path)   AOT-RED  PlatformNotSupportedException: Operation is not supported on this platform.
NativeAOT · runtime   Assembly.Load(AssemblyName)  RED   FileNotFoundException: Cannot load assembly 'System.Linq'. No metadata found for this assembly.
NativeAOT · runtime   AppDomain.CurrentDomain.GetAssemblies()   PASS  count=1   ← degraded, not thrown
NativeAOT · runtime   Type.GetType(name), four shapes           PASS (all four)
NativeAOT · runtime   Assembly.Location (entry assembly)        PASS  ''  EMPTY => single-file
NativeAOT · runtime   typeof(object).Assembly.Location          PASS  ''  EMPTY => MLC would be fed nothing
```

`AppDomain.GetAssemblies()` returning **1** is the dangerous shape: it does not throw, so
`ExternalAssemblyScan.Loaded()` would quietly return a one-entry universe and the compiler would
mis-bind rather than fail. `typeof(object).Assembly.Location == ""` confirms the previous decode's
warning: `ExternalAssemblyScan.nl:132`'s `metadataPath := runtimeAssembly.get_Location()` feeds the
metadata context **nothing** under a single-file binary, and slice 2's re-sourcing is mandatory, not
optional.

### 3.3 Two members that are red on runtime types and GREEN on MLC types (slice 2 fixes them)

```
NativeAOT · runtime   MemberInfo::get_MetadataToken   RED  InvalidOperationException: There is no metadata token available for the given member.
NativeAOT · mlc       MemberInfo::get_MetadataToken   PASS 0x060008f3
NativeAOT · runtime   Type::get_Module → Module.Name  PASS "<Unknown>"          ← wrong answer, no exception
NativeAOT · mlc       Type::get_Module → Module.Name  PASS "System.Private.CoreLib.dll"
```

Four estate call sites read `MetadataToken`. The single-universe move is what makes them work.

### 3.4 Reachability: member lookups return NULL under NativeAOT, and calling the member does not help

The probe's first NativeAOT run (`rows-aot-run1-notrimkeepalive.tsv`) lost its entire runtime-type
universe because `typeof(string).GetMethod("Concat", …)` returned **null**. A second run added
`KeepAlive()` — ordinary static calls to `string.Concat`, `int.MaxValue`, `string.Empty`,
`"x".Length`, `Array.Empty<string>()`, `IDisposable.Dispose`, `EventHandler` and an `AppDomain` event
subscription, no attributes and no directives — and **the lookups still returned null**. Calling a BCL
member does not make it reflection-discoverable in a NativeAOT image.

Group T shows the hazard is per-member and not predictable from source: `string.PadLeft(int,char)`
(never called), `Type.GetType("System.Text.Rune")`, `PropertyInfo.GetValue` / `MethodInfo.Invoke` /
`GetProperties()` over the app's own objects, and even `Type.GetType("OwnShape")` by bare name — all
PASS. But `String.Concat(string,string)`, `Int32.MaxValue`, `String.Empty`, `String.Length`,
`Array.Empty<>`, `IDisposable.Dispose`, `System.EventHandler` and `AppDomain`'s events — all null.

**Consequences.** For slice 5, the good news is that the twenty sites reflecting over the compiler's
OWN AST objects are green (T3/T4/T5) and `Type.GetType` by name is green (T2/T6) — the trim-rooting
job is smaller than feared. The bad news is the failure mode: `Type.GetMethod` (33 estate sites),
`GetField` (19) and `GetProperty` (23) over BCL RUNTIME types return **null**, not an exception, so a
NativeAOT `nlc` would mis-bind silently. Over MLC types every one of those lookups reads a metadata
file and is immune. This is the strongest measured argument for slice 2.

### 3.5 Universe-inherent reds, identical on both hosts (not AOT's doing)

Seven census members throw on MLC types — **three more than the four the previous decode named**:

| member | estate call sites | exception |
|---|---|---|
| `FieldInfo::GetValue` | 9 | `InvalidOperationException: The requested operation cannot be used on objects loaded by a MetadataLoadContext.` |
| `PropertyInfo::GetValue` | 9 | same message — **no metadata substitute exists** |
| `ConstructorInfo::Invoke` | 3 | `InvalidOperationException: Cannot invoke a method on objects loaded by a MetadataLoadContext.` |
| `ParameterInfo::get_DefaultValue` | 1 | `…illegal to request the default value… Use RawDefaultValue instead.` |
| **`MemberInfo::IsDefined`** | **2** | `…cannot be used on objects loaded by a MetadataLoadContext. Use CustomAttributeData instead.` |
| **`ParameterInfo::IsDefined`** | **2** | `…cannot be used on objects loaded by a MetadataLoadContext.` |
| **`Type::get_TypeHandle`** | **2** | `…cannot be used on objects loaded by a MetadataLoadContext.` |

The substitutes are measured green: `FieldInfo::GetRawConstantValue` PASS (`2147483647`),
`ParameterInfo::get_RawDefaultValue` PASS, and `MemberInfo::GetCustomAttributesData` /
`ParameterInfo::GetCustomAttributesData` PASS — so the two `IsDefined` pairs convert to an attribute-data
scan. `PropertyInfo::GetValue` has no substitute and `Type::get_TypeHandle` has none either; slice 2
must decide those two by inspection, not by conversion.

Also host-independent and universe-independent: **`Type::get_IsSZArray` on a
`GenericTypeParameterBuilder` throws `NotImplementedException` on BOTH hosts and in BOTH universes**,
reproducing the recorded persisted-emit landmine exactly. It is a *builder*-receiver hazard, not an
MLC one and not an AOT one.

### 3.6 What is NOT a blocker

`Type::GetTypeFromHandle` is **N/A-by-construction**: it is `typeof(X)`, a runtime handle, and an MLC
type has no `RuntimeTypeHandle`. With 1,516 call sites it is the estate's heaviest reflection member,
and it is runtime by construction in every one of them. "One type universe" therefore means the
EXTERNAL catalog is single-sourced; it cannot mean "no runtime `Type` objects", and the builder stays
runtime-cored (`new PersistedAssemblyBuilder(assemblyIdentity, typeof(object).Assembly)`,
`ColumnarIlEmitter.cs:3991`). Measuring slice 2 against the stronger reading would be measuring it
against an impossible bar.

`NullabilityInfoContext::Create` over an MLC member is **PASS under NativeAOT** — measured here for
the first time; the previous decode's verdict was CoreCLR-only.

## 4. The `ilc` warning ledger, adjudicated

`grep -c "^ILC :" publish-aot.log` → **99**, **0 errors**. `TrimmerSingleWarn=false` is required or
ilc collapses these per assembly and the ledger cannot be keyed.

| code | count | code | count | code | count |
|---|---|---|---|---|---|
| IL2080 | 60 | IL2094 | 21 | IL2070 | 6 |
| IL2026 | 45 | IL2075 | 21 | IL2060 | 4 |
| IL2046 | 39 | IL3051 | 19 | IL3002 | 2 |
| IL3050 | 25 | IL2077 | 16 | IL2096/2093/2092/2065/2057 | 1 each |
| | | IL3000 | 10 | IL2055 | 7 |

**The discrimination rule, applied.** A warning is never a verdict; a cell's value is the runtime
result of the native binary. A FALSE `IL3050` is one whose target method appears in a PASS row of the
NativeAOT column; a REAL one appears in an AOT-RED row whose exception is `PlatformNotSupportedException`
with the dynamic-code message. Anything else is a different failure mode and is not attributed to the
warning. A warning no row exercises is UNADJUDICATED and named.

| IL3050 target | n | verdict | evidence |
|---|---|---|---|
| `Type.MakeGenericType` | 8 | **FALSE POSITIVE** | PASS in all four NativeAOT cells (`List\`1`), incl. over a `TypeBuilder` |
| `Type.MakeArrayType()` | 7 | **FALSE POSITIVE** | PASS in all four (`String[]`, `T[]`) |
| `MethodInfo.MakeGenericMethod` | 4 | **FALSE POSITIVE** | PASS NativeAOT·MLC (`Empty`); the runtime cell is TRIM-RED, a reachability failure, not dynamic code |
| `Enum.GetValues(Type)` inside `EnumBuilderImpl..ctor` | 1 | **FALSE POSITIVE** | A04a `DefineEnum` PASS on both hosts, both universes |
| `AssemblyBuilder.DefineDynamicAssembly` | 2 | **REAL** | A22 AOT-RED, `PlatformNotSupportedException: Dynamic code generation is not supported on this platform.` — and it is the CONTROL: **0 sites in the estate** |
| `Type.MakeArrayType(int)` via `SignatureTypeExtensions` | 3 | **UNADJUDICATED** | multi-dimensional arrays; no estate site and no probe row |

`IL3000` (10) on `Assembly.Location` is **REAL and confirmed by execution**: both `Assembly.GetEntryAssembly().Location`
and `typeof(object).Assembly.Location` return `""` in the native binary. `IL3002` (2) on `Module.Name`
is **REAL but non-throwing**: it returns `"<Unknown>"` for runtime types, and the correct file name
for MLC types. The 39 `IL2046` / 21 `IL2094` / 19 `IL3051` are annotation-mismatch advisories on
`MetadataLoadContext`'s `Ro*` overrides and are UNADJUDICATED by design — no probe row calls
`GetMethodBody`, and the estate does not either.

## 5. Census re-derivation (Group D)

The previous decode's `memberscan` **cannot re-derive its own census**: run against a current estate
build it dies with `System.InvalidCastException` at the `(MemberReferenceHandle)handle` cast
(`Program.cs:68`) — its hand-rolled IL walker mis-sizes an instruction and reads a bogus token. The
MemberRef-table pass needs no IL walk and is the trustworthy half. `memberscan2` drops the walker,
guards every handle, and adds the `System.Reflection.Emit.*` owners.

```
dotnet build src/NSharpLang.Compiler.BootstrapServices/…csproj -c Debug      16.8 s, 0 warnings, 0 errors
dotnet memberscan2.dll …/bin/Debug/net10.0/NSharpLang.Compiler.BootstrapServices.dll
  → typedefs=1115 memberrefs=4572 skipped=0
    DISTINCT_REFLECTION_MEMBERS=132        (131 at 8cf40128a; +1, none removed)
    DISTINCT_EMIT_MEMBERS=128              (112 OpCodes fields + 9 ILGenerator + 7 TypeBuilder)
```

The one addition is **`MethodBase::get_IsFinal`**. The old figure was 131; the packaged-binary figure
is 92 and must never be quoted.

## 6. The emit surface, re-derived from source at `385b7e8d1`

`ColumnarIlEmitter.cs` 20,784 lines · **1,197** `OpCodes.` sites (1,145 at `8cf40128a`) · **100**
distinct opcodes. `ColumnarCodePlanExecutor.nl` 2,711 lines · **112** distinct opcodes. **Union: 124**,
overlap 88. N#-only: the `Ldind_*` family, `Ldc_I4_<0..8,M1>`, `And`/`Or`/`Xor`/`Shl`/`Shr`/`Shr_Un`,
`Ldtoken`. C#-only: `Bge`, `Blt`, `Bne_Un`, `Constrained`, `Ldftn`, `Ldobj`, `Stobj`, `Stind_Ref`,
`Starg`, `Starg_S`, `Ldarg_S`, `Ldarga_S`. **No `Switch`, no `Calli`, no `SignatureHelper`**, so
`Emit(OpCode, Label[])` and `Emit(OpCode, SignatureHelper)` are outside the floor.

Builder tokens (C#): `TypeBuilder` 135, `LocalBuilder` 34, `MethodBuilder` 25, `FieldBuilder` 17,
`ILGenerator` 13, `ConstructorBuilder` 12, `EnumBuilder` 9, `GenericTypeParameterBuilder` 9,
`ModuleBuilder` 5, `CustomAttributeBuilder` 4, `PersistedAssemblyBuilder` 2, `ParameterBuilder` 1;
`DynamicMethod`, `SignatureHelper` and `EventBuilder` are **0** in both languages.

Two facts the previous decode did not carry:

- **There are TWO save paths.** A library goes out through `Save(stream)` (`:5991`). An EXECUTABLE goes
  out through `GenerateMetadata(out ilStream, out mappedFieldData)` → `PEHeaderBuilder.CreateExecutableHeader()`
  → `MetadataRootBuilder` → `ManagedPEBuilder.Serialize` → `BlobBuilder.WriteContentTo`, keyed on
  `MethodBuilder.MetadataToken` (`:5978–5987`). Both are now PASS under NativeAOT in both universes, and
  both produced images were executed.
- **The exception-region surface is five openers and one lives only in N#.** C# uses
  `BeginExceptionBlock`/`BeginCatchBlock`/`BeginFinallyBlock`/`EndExceptionBlock`; `BeginFaultBlock`
  appears only at `ColumnarCodePlanExecutor.nl:232`, fed by `ColumnarIteratorPlanner.nl:1415`. There is
  no `BeginExceptFilterBlock`, no `MarkSequencePoint` and no symbol writer anywhere — the emitter writes
  no sequence points, so the floor owes nothing to debug metadata.

## 7. Corrections to `2026-09-01-aot-type-model-decode.md`

1. **§4's "Not proven" list is now proven** — `EnumBuilder`, `CustomAttributeBuilder`, exception
   regions, `DefineMethodOverride`, property/event definition and the full opcode surface were all
   exercised. One of them, `CustomAttributeBuilder`, came back **red**.
2. **`Type.GetType` is 73 sites in 24 production `.nl` files, not 2.** The decode counted only the two
   C# sites. All four probed shapes PASS under NativeAOT, so this is a smaller problem than the count
   suggests — but slice 5 must state that, not assume it.
3. **The MLC-inherent red set is seven members, not four.** `MemberInfo::IsDefined`,
   `ParameterInfo::IsDefined` and `Type::get_TypeHandle` were missed.
4. **The census is 132, not 131** (`MethodBase::get_IsFinal` added), and the tool that produced 131
   crashes on a current build.
5. **`AppDomain.GetAssemblies()` does not throw under NativeAOT — it returns 1.** The decode called it
   "degraded"; the measured shape is a silent one-entry universe, which is worse than a throw.

## 8. The full table

Legend: **AOT-RED** = NativeAOT capability limit · *TRIM-RED* = target absent from the image
(reachability, slice 5) · **RED** = any other failure, verbatim · `n/a` = no such cell ·
`—` = not applicable in that universe. Section 9 lists every red with its exception text.

#### Setup / universe construction

| API | CoreCLR · runtime | CoreCLR · MLC | NativeAOT · runtime | NativeAOT · MLC |
|---|---|---|---|---|
| RuntimeFeature.IsDynamicCodeSupported / IsDynamicCodeCompiled | PASS | (same) | PASS | (same) |
| KeepAlive() — ordinary static use of the BCL receivers the capability cells reflect over (NOT a trim root) | PASS | (same) | PASS | (same) |
| universe built | PASS | PASS | PASS | PASS |
| new MetadataLoadContext(PathAssemblyResolver, "System.Private.CoreLib") | — | PASS | — | PASS |
| MLC resolution of System.Console::WriteLine(string) for the exe entry point | — | PASS | — | PASS |
| universe receiver: String.Concat(string,string) | — | — | *TRIM-RED* | — |
| universe receiver: Array.Empty<> | — | — | *TRIM-RED* | — |
| universe receiver: Int32.MaxValue | — | — | *TRIM-RED* | — |
| universe receiver: String.Empty | — | — | *TRIM-RED* | — |
| universe receiver: String.Length | — | — | *TRIM-RED* | — |

#### Group A — the persisted-emit surface

| API | CoreCLR · runtime | CoreCLR · MLC | NativeAOT · runtime | NativeAOT · MLC |
|---|---|---|---|---|
| A22 AssemblyBuilder.DefineDynamicAssembly(Run)  [CONTROL — 0 sites in the estate] | PASS | — | **AOT-RED** | — |
| A01 new PersistedAssemblyBuilder(AssemblyName, coreAssembly) | PASS | PASS | PASS | PASS |
| A02 ModuleBuilder DefineDynamicModule | PASS | PASS | PASS | PASS |
| A04a ModuleBuilder.DefineEnum | PASS | PASS | PASS | PASS |
| A04b EnumBuilder.DefineLiteral | PASS | PASS | PASS | PASS |
| A04c EnumBuilder.CreateType | PASS | PASS | PASS | PASS |
| A03a ModuleBuilder.DefineType | PASS | PASS | PASS | PASS |
| A03b TypeBuilder.SetParent | PASS | PASS | PASS | PASS |
| A03c TypeBuilder.AddInterfaceImplementation | PASS | PASS | PASS | PASS |
| A03d TypeBuilder.DefineNestedType | PASS | PASS | PASS | PASS |
| A05a TypeBuilder.DefineField (plain) | PASS | PASS | PASS | PASS |
| A05b TypeBuilder.DefineField (closed generic) | PASS | PASS | PASS | PASS |
| A05c TypeBuilder.DefineField (array) | PASS | PASS | PASS | PASS |
| A05d FieldBuilder.SetConstant (int literal) | PASS | PASS | PASS | PASS |
| A05e FieldBuilder.SetConstant (string literal) | PASS | PASS | PASS | PASS |
| A05f instance field for IL | PASS | PASS | PASS | PASS |
| A05g static field for IL | PASS | PASS | PASS | PASS |
| A06a TypeBuilder.DefineMethod | PASS | PASS | PASS | PASS |
| A06b MethodBuilder.SetReturnType/SetParameters | PASS | PASS | PASS | PASS |
| A06c MethodBuilder.DefineParameter | PASS | PASS | PASS | PASS |
| A06d MethodBuilder.SetImplementationFlags | PASS | PASS | PASS | PASS |
| A07a TypeBuilder.DefineConstructor | PASS | PASS | PASS | PASS |
| A07b TypeBuilder.DefineDefaultConstructor | PASS | PASS | PASS | PASS |
| A07c TypeBuilder.DefineTypeInitializer | PASS | PASS | PASS | PASS |
| A08 TypeBuilder.DefineProperty + SetGetMethod + SetSetMethod | PASS | PASS | PASS | PASS |
| A09 TypeBuilder.DefineEvent [NOT-IN-ESTATE-SURFACE] | PASS | PASS | PASS | PASS |
| A10 TypeBuilder.DefineGenericParameters + constraints | PASS | PASS | PASS | PASS |
| A10b GenericTypeParameterBuilder.SetBaseTypeConstraint | PASS | PASS | PASS | PASS |
| A11 MethodBuilder.DefineGenericParameters | PASS | PASS | PASS | PASS |
| A12 TypeBuilder.DefineMethodOverride | PASS | PASS | *TRIM-RED* | PASS |
| A13a1 new CustomAttributeBuilder(ctor, no args) | PASS | PASS | **AOT-RED** | **AOT-RED** |
| A13a2 TypeBuilder.SetCustomAttribute (no-arg ctor) | PASS | PASS | *TRIM-RED* | *TRIM-RED* |
| A13b1 new CustomAttributeBuilder(ctor, string arg)  [the Trait shape, :5882] | PASS | **RED** | **AOT-RED** | **AOT-RED** |
| A13b2 MethodBuilder.SetCustomAttribute (string args) | PASS | *TRIM-RED* | *TRIM-RED* | *TRIM-RED* |
| A13c1 new CustomAttributeBuilder with a RUNTIME-sourced ctor [isolates A13b1] | PASS | PASS | **AOT-RED** | **AOT-RED** |
| A13c2 SetCustomAttribute with that RUNTIME-sourced builder | PASS | PASS | *TRIM-RED* | *TRIM-RED* |
| A13d TypeBuilder.SetCustomAttribute(ctor, byte[] blob)  [the CustomAttributeBuilder-free substitute] | PASS | PASS | PASS | PASS |
| A13e MethodBuilder.SetCustomAttribute(ctor, byte[] blob) with a STRING argument | PASS | PASS | PASS | PASS |
| A14 TypeBuilder.DefinePInvokeMethod | PASS | PASS | PASS | PASS |
| A15 ILGenerator regions (DeclareLocal/DefineLabel/MarkLabel/Begin{Exception,Catch,Finally,Fault}Block/EndExceptionBlock) | PASS | PASS | PASS | PASS |
| A16 ILGenerator.Emit overloads (OpCode\|int\|long\|float\|double\|string\|Type\|MethodInfo\|ConstructorInfo\|FieldInfo\|Label\|LocalBuilder\|byte\|short) | PASS | PASS | **RED** | PASS |
| A17 opcode sweep — all 124 union opcodes accepted by ILGenerator.Emit | PASS | PASS | **RED** | PASS |
| A18a TypeBuilder.CreateType (nested) | PASS | PASS | PASS | PASS |
| A18 TypeBuilder.CreateType | PASS | PASS | PASS | PASS |
| A19 PersistedAssemblyBuilder.Save(stream)  [LIBRARY path] | PASS | PASS | PASS | PASS |
| A21 readback of the saved LIBRARY with a fresh MetadataLoadContext | PASS | PASS | PASS | PASS |
| A20a exe builder + entry-point method | PASS | PASS | PASS | PASS |
| A20b PersistedAssemblyBuilder.GenerateMetadata(out ilStream, out mappedFieldData) | PASS | PASS | PASS | PASS |
| A20c MethodBuilder.MetadataToken (read off a persisted builder) | PASS | PASS | PASS | PASS |
| A20d PEHeaderBuilder.CreateExecutableHeader() | PASS | PASS | PASS | PASS |
| A20e MetadataRootBuilder(metadataBuilder) | PASS | PASS | PASS | PASS |
| A20f ManagedPEBuilder.Serialize + BlobBuilder.WriteContentTo | PASS | PASS | PASS | PASS |
| A20g the produced image is on disk with a runtimeconfig (RUN verdict comes from the harness) | PASS | PASS | PASS | PASS |

#### Group B — the estate's 132 distinct reflection members

| API | CoreCLR · runtime | CoreCLR · MLC | NativeAOT · runtime | NativeAOT · MLC |
|---|---|---|---|---|
| AppDomain::get_CurrentDomain | PASS | n/a | PASS | n/a |
| AppDomain::GetAssemblies | PASS | n/a | PASS | n/a |
| Assembly::GetExportedTypes | PASS | PASS | PASS | PASS |
| Assembly::GetName | PASS | PASS | PASS | PASS |
| Assembly::GetType | PASS | PASS | PASS | PASS |
| Assembly::GetTypes | PASS | PASS | PASS | PASS |
| Assembly::Load | PASS | n/a | **RED** | n/a |
| Assembly::LoadFrom | PASS | n/a | **AOT-RED** | n/a |
| Assembly::get_FullName | PASS | PASS | PASS | PASS |
| Assembly::get_IsCollectible | PASS | PASS | PASS | PASS |
| Assembly::get_IsDynamic | PASS | PASS | PASS | PASS |
| Assembly::get_Location | PASS | PASS | PASS | PASS |
| AssemblyName::GetAssemblyName | PASS | PASS | PASS | PASS |
| AssemblyName::ReferenceMatchesDefinition | PASS | PASS | PASS | PASS |
| AssemblyName::get_FullName | PASS | PASS | PASS | PASS |
| AssemblyName::get_Name | PASS | PASS | PASS | PASS |
| ConstructorInfo::Invoke | PASS | **RED** | PASS | **RED** |
| CustomAttributeData::get_AttributeType | PASS | PASS | PASS | PASS |
| CustomAttributeData::get_ConstructorArguments | PASS | PASS | PASS | PASS |
| CustomAttributeTypedArgument::get_Value | PASS | PASS | PASS | PASS |
| EventInfo::GetAddMethod | PASS | PASS | *TRIM-RED* | PASS |
| EventInfo::GetRemoveMethod | PASS | PASS | *TRIM-RED* | PASS |
| EventInfo::get_EventHandlerType | PASS | PASS | *TRIM-RED* | PASS |
| FieldInfo::GetValue  [KNOWN RED on MLC] | PASS | **RED** | *TRIM-RED* | **RED** |
| FieldInfo::GetRawConstantValue  [the substitute slice 2 converts to] | PASS | PASS | *TRIM-RED* | PASS |
| FieldInfo::get_FieldType | PASS | PASS | *TRIM-RED* | PASS |
| FieldInfo::get_IsInitOnly | PASS | PASS | *TRIM-RED* | PASS |
| FieldInfo::get_IsLiteral | PASS | PASS | *TRIM-RED* | PASS |
| FieldInfo::get_IsPublic | PASS | PASS | *TRIM-RED* | PASS |
| FieldInfo::get_IsStatic | PASS | PASS | *TRIM-RED* | PASS |
| MemberInfo::GetCustomAttributesData | PASS | PASS | PASS | PASS |
| MemberInfo::IsDefined | PASS | **RED** | PASS | **RED** |
| MemberInfo::get_DeclaringType | PASS | PASS | PASS | PASS |
| MemberInfo::get_MetadataToken | PASS | PASS | **RED** | PASS |
| MemberInfo::get_Name | PASS | PASS | PASS | PASS |
| MetadataLoadContext::LoadFromAssemblyName | n/a | PASS | n/a | PASS |
| MetadataLoadContext::LoadFromAssemblyPath | n/a | PASS | n/a | PASS |
| MetadataLoadContext::Dispose | n/a | — | n/a | — |
| MethodBase::Equals | PASS | PASS | PASS | PASS |
| MethodBase::GetParameters | PASS | PASS | PASS | PASS |
| MethodBase::get_CallingConvention | PASS | PASS | PASS | PASS |
| MethodBase::get_IsAbstract | PASS | PASS | PASS | PASS |
| MethodBase::get_IsFinal  [NEW at 385b7e8d1 — not in the 131] | PASS | PASS | PASS | PASS |
| MethodBase::get_IsGenericMethod | PASS | PASS | *TRIM-RED* | PASS |
| MethodBase::get_IsGenericMethodDefinition | PASS | PASS | *TRIM-RED* | PASS |
| MethodBase::get_IsPublic | PASS | PASS | PASS | PASS |
| MethodBase::get_IsSpecialName | PASS | PASS | PASS | PASS |
| MethodBase::get_IsStatic | PASS | PASS | PASS | PASS |
| MethodBase::get_IsVirtual | PASS | PASS | PASS | PASS |
| MethodInfo::GetGenericArguments | PASS | PASS | *TRIM-RED* | PASS |
| MethodInfo::MakeGenericMethod | PASS | PASS | *TRIM-RED* | PASS |
| MethodInfo::GetGenericMethodDefinition | PASS | PASS | *TRIM-RED* | PASS |
| MethodInfo::get_ReturnParameter | PASS | PASS | PASS | PASS |
| MethodInfo::get_ReturnType | PASS | PASS | PASS | PASS |
| NullabilityInfoContext::Create | PASS | PASS | **RED** | PASS |
| NullabilityInfo::get_ReadState | PASS | PASS | **RED** | PASS |
| NullabilityInfo::get_ElementType | PASS | PASS | **RED** | PASS |
| NullabilityInfo::get_GenericTypeArguments | PASS | PASS | **RED** | PASS |
| ParameterInfo::GetCustomAttributesData | PASS | PASS | PASS | PASS |
| ParameterInfo::IsDefined | PASS | **RED** | PASS | **RED** |
| ParameterInfo::get_DefaultValue  [KNOWN RED on MLC] | PASS | **RED** | PASS | **RED** |
| ParameterInfo::get_RawDefaultValue  [the substitute] | PASS | PASS | PASS | PASS |
| ParameterInfo::get_IsOptional | PASS | PASS | PASS | PASS |
| ParameterInfo::get_IsOut | PASS | PASS | PASS | PASS |
| ParameterInfo::get_Name | PASS | PASS | PASS | PASS |
| ParameterInfo::get_ParameterType | PASS | PASS | PASS | PASS |
| PropertyInfo::GetValue  [KNOWN RED on MLC — no metadata substitute] | PASS | **RED** | *TRIM-RED* | **RED** |
| PropertyInfo::GetGetMethod | PASS | PASS | *TRIM-RED* | PASS |
| PropertyInfo::GetSetMethod | PASS | PASS | *TRIM-RED* | PASS |
| PropertyInfo::GetIndexParameters | PASS | PASS | *TRIM-RED* | PASS |
| PropertyInfo::get_GetMethod | PASS | PASS | *TRIM-RED* | PASS |
| PropertyInfo::get_SetMethod | PASS | PASS | *TRIM-RED* | PASS |
| PropertyInfo::get_PropertyType | PASS | PASS | *TRIM-RED* | PASS |
| Type::GetArrayRank | PASS | PASS | PASS | PASS |
| Type::GetConstructor | PASS | PASS | PASS | PASS |
| Type::GetConstructors | PASS | PASS | PASS | PASS |
| Type::GetElementType | PASS | PASS | PASS | PASS |
| Type::GetEnumUnderlyingType | PASS | PASS | PASS | PASS |
| Type::GetEvent | PASS | PASS | *TRIM-RED* | PASS |
| Type::GetEvents | PASS | PASS | PASS | PASS |
| Type::GetField | PASS | PASS | PASS | PASS |
| Type::GetFields | PASS | PASS | PASS | PASS |
| Type::GetGenericArguments | PASS | PASS | PASS | PASS |
| Type::GetGenericTypeDefinition | PASS | PASS | PASS | PASS |
| Type::GetInterfaces | PASS | PASS | PASS | PASS |
| Type::GetMethod | PASS | PASS | PASS | PASS |
| Type::GetMethods | PASS | PASS | PASS | PASS |
| Type::GetNestedType | PASS | PASS | PASS | PASS |
| Type::GetNestedTypes | PASS | PASS | PASS | PASS |
| Type::GetProperties | PASS | PASS | PASS | PASS |
| Type::GetProperty | PASS | PASS | PASS | PASS |
| Type::GetType(string) | PASS | n/a | PASS | n/a |
| Type::GetTypeFromHandle | PASS | n/a | PASS | n/a |
| Type::get_TypeHandle | PASS | n/a | PASS | n/a |
| Type::IsAssignableFrom | PASS | PASS | PASS | PASS |
| Type::MakeArrayType | PASS | PASS | PASS | PASS |
| Type::MakeByRefType | PASS | PASS | PASS | PASS |
| Type::MakeGenericType | PASS | PASS | PASS | PASS |
| Type::MakePointerType | PASS | PASS | PASS | PASS |
| Type::ToString | PASS | PASS | PASS | PASS |
| Type::get_Assembly | PASS | PASS | PASS | PASS |
| Type::get_AssemblyQualifiedName | PASS | PASS | PASS | PASS |
| Type::get_BaseType | PASS | PASS | PASS | PASS |
| Type::get_ContainsGenericParameters | PASS | PASS | PASS | PASS |
| Type::get_DeclaringMethod | PASS | PASS | *TRIM-RED* | PASS |
| Type::get_DeclaringType | PASS | PASS | PASS | PASS |
| Type::get_FullName | PASS | PASS | PASS | PASS |
| Type::get_GenericParameterPosition | PASS | PASS | PASS | PASS |
| Type::get_GenericTypeArguments | PASS | PASS | PASS | PASS |
| Type::get_HasElementType | PASS | PASS | PASS | PASS |
| Type::get_IsAbstract | PASS | PASS | PASS | PASS |
| Type::get_IsArray | PASS | PASS | PASS | PASS |
| Type::get_IsByRef | PASS | PASS | PASS | PASS |
| Type::get_IsByRefLike | PASS | PASS | PASS | PASS |
| Type::get_IsClass | PASS | PASS | PASS | PASS |
| Type::get_IsEnum | PASS | PASS | PASS | PASS |
| Type::get_IsFunctionPointer | PASS | PASS | PASS | PASS |
| Type::get_IsGenericParameter | PASS | PASS | PASS | PASS |
| Type::get_IsGenericType | PASS | PASS | PASS | PASS |
| Type::get_IsGenericTypeDefinition | PASS | PASS | PASS | PASS |
| Type::get_IsInterface | PASS | PASS | PASS | PASS |
| Type::get_IsNested | PASS | PASS | PASS | PASS |
| Type::get_IsNestedPublic | PASS | PASS | PASS | PASS |
| Type::get_IsPointer | PASS | PASS | PASS | PASS |
| Type::get_IsPrimitive | PASS | PASS | PASS | PASS |
| Type::get_IsPublic | PASS | PASS | PASS | PASS |
| Type::get_IsSZArray  [the persisted-emit landmine; bare T is the hazard] | PASS | PASS | PASS | PASS |
| Type::get_IsSealed | PASS | PASS | PASS | PASS |
| Type::get_IsValueType | PASS | PASS | PASS | PASS |
| Type::get_IsVisible | PASS | PASS | PASS | PASS |
| Type::get_Module | PASS | PASS | PASS | PASS |
| Type::get_Namespace | PASS | PASS | PASS | PASS |
| Type::op_Equality | PASS | PASS | PASS | PASS |
| Type::op_Inequality | PASS | PASS | PASS | PASS |
| MetadataLoadContext::Dispose  [on a THROWAWAY context, not the live one] | — | PASS | — | PASS |
| Type::get_TypeHandle  [recorded verbatim on MLC] | — | **RED** | — | **RED** |

#### Group B (builder receivers) — reported apart, never as a fourth column

| API | CoreCLR · runtime | CoreCLR · MLC | NativeAOT · runtime | NativeAOT · MLC |
|---|---|---|---|---|
| Type::get_IsSZArray on a GenericTypeParameterBuilder  [the recorded NotImplementedException landmine] | **RED** | (same) | **RED** | (same) |
| Type::get_IsSZArray on a TypeBuilder | PASS | (same) | PASS | (same) |
| Type::get_IsGenericParameter on a GenericTypeParameterBuilder | PASS | (same) | PASS | (same) |
| Type::get_IsValueType on a TypeBuilder | PASS | (same) | PASS | (same) |
| Type::get_FullName on a TypeBuilder | PASS | (same) | PASS | (same) |
| Type::get_Assembly.IsDynamic on a TypeBuilder  [TypeInfoIdentityFacts.nl:424] | PASS | (same) | PASS | (same) |
| Type::MakeGenericType over a TypeBuilder definition | PASS | (same) | PASS | (same) |
| Type::MakeArrayType on a GenericTypeParameterBuilder | PASS | (same) | PASS | (same) |

#### Group C — the runtime-loader shapes

| API | CoreCLR · runtime | CoreCLR · MLC | NativeAOT · runtime | NativeAOT · MLC |
|---|---|---|---|---|
| C1 Assembly.LoadFrom(path)  [C#:9314,:9359 · N# ExternalAssemblyScan.nl:567] | PASS | — | **AOT-RED** | — |
| C2 Assembly.Load(new AssemblyName(name))  [C#:9329 · N# ExternalAssemblyScan.nl:129, DocQuery.nl:90] | PASS | — | **RED** | — |
| C2b Assembly.Load(string)  [the by-name form] | PASS | — | PASS | — |
| C3 AppDomain.CurrentDomain.GetAssemblies()  [C#:2817 · N# ExternalAssemblyScan.nl:81] | PASS | — | PASS | — |
| C4a Type.GetType("System.Text.StringBuilder")  [CoreLib, referenced] | PASS | — | PASS | — |
| C4b Type.GetType("System.Void")  [the estate's commonest form, N# x73] | PASS | — | PASS | — |
| C4c Type.GetType(asm-qualified, NOT referenced by this binary) | PASS | — | PASS | — |
| C4d Type.GetType("System.Console, System.Console")  [AnalyzerMemberAccess.nl:879 shape] | PASS | — | PASS | — |
| C5 Assembly.Location on the ENTRY assembly  [11 N# sites; '' under single-file] | PASS | — | PASS | — |
| C6 typeof(object).Assembly.Location  [what OpenWithReferences seeds metadataPath from, ExternalAssemblyScan.nl:132] | PASS | — | PASS | — |
| C7 AppContext.BaseDirectory  [the single-file substitute] | PASS | — | PASS | — |
| C1 Assembly.LoadFrom(path) | — | n/a | — | n/a |
| C2 Assembly.Load(AssemblyName) | — | n/a | — | n/a |
| C3 AppDomain.CurrentDomain.GetAssemblies() | — | n/a | — | n/a |

#### Group T — reachability (trimming), reported apart from capability

| API | CoreCLR · runtime | CoreCLR · MLC | NativeAOT · runtime | NativeAOT · MLC |
|---|---|---|---|---|
| T1 GetMethod for a BCL member the app never calls (string.PadLeft(int,char)) | PASS | — | PASS | — |
| T2 Type.GetType for a type reached only by name (System.Text.Rune) | PASS | — | PASS | — |
| T3 PropertyInfo.GetValue over the app's OWN object, type reached by typeof  [the 20 AST sites] | PASS | — | PASS | — |
| T4 GetProperties() over the app's OWN object | PASS | — | PASS | — |
| T5 MethodInfo.Invoke over the app's OWN object | PASS | — | PASS | — |
| T6 Type.GetType("OwnShape") — the app's own type reached only by name | PASS | — | PASS | — |


## 9. Every red cell, with its verbatim exception

| host | universe | API | verdict — exception type and message, verbatim |
|---|---|---|---|
| NativeAOT | runtime | universe receiver: String.Concat(string,string) | `TRIM-RED:MemberMissing:member lookup returned null: String.Concat` |
| NativeAOT | runtime | universe receiver: Array.Empty<> | `TRIM-RED:MemberMissing:member lookup returned null: Array.Empty<>` |
| NativeAOT | runtime | universe receiver: Int32.MaxValue | `TRIM-RED:MemberMissing:member lookup returned null: Int32.MaxValue` |
| NativeAOT | runtime | universe receiver: String.Empty | `TRIM-RED:MemberMissing:member lookup returned null: String.Empty` |
| NativeAOT | runtime | universe receiver: String.Length | `TRIM-RED:MemberMissing:member lookup returned null: String.Length` |
| NativeAOT | runtime | A22 AssemblyBuilder.DefineDynamicAssembly(Run)  [CONTROL — 0 sites in the estate] | `AOT-RED:PlatformNotSupportedException:Dynamic code generation is not supported on this platform.` |
| NativeAOT | runtime | A12 TypeBuilder.DefineMethodOverride | `TRIM-RED:MemberMissing:member lookup returned null: IDisposable.Dispose` |
| NativeAOT | runtime | A13a1 new CustomAttributeBuilder(ctor, no args) | `AOT-RED:PlatformNotSupportedException:Dynamic code generation is not supported on this platform.` |
| NativeAOT | mlc | A13a1 new CustomAttributeBuilder(ctor, no args) | `AOT-RED:PlatformNotSupportedException:Dynamic code generation is not supported on this platform.` |
| NativeAOT | runtime | A13a2 TypeBuilder.SetCustomAttribute (no-arg ctor) | `TRIM-RED:MemberMissing:member lookup returned null: CustomAttributeBuilder` |
| NativeAOT | mlc | A13a2 TypeBuilder.SetCustomAttribute (no-arg ctor) | `TRIM-RED:MemberMissing:member lookup returned null: CustomAttributeBuilder` |
| CoreCLR | mlc | A13b1 new CustomAttributeBuilder(ctor, string arg)  [the Trait shape, :5882] | `RED:ArgumentException:An invalid type was used as a custom attribute constructor argument, field or property.` |
| NativeAOT | runtime | A13b1 new CustomAttributeBuilder(ctor, string arg)  [the Trait shape, :5882] | `AOT-RED:PlatformNotSupportedException:Dynamic code generation is not supported on this platform.` |
| NativeAOT | mlc | A13b1 new CustomAttributeBuilder(ctor, string arg)  [the Trait shape, :5882] | `AOT-RED:PlatformNotSupportedException:Dynamic code generation is not supported on this platform.` |
| CoreCLR | mlc | A13b2 MethodBuilder.SetCustomAttribute (string args) | `TRIM-RED:MemberMissing:member lookup returned null: CustomAttributeBuilder` |
| NativeAOT | runtime | A13b2 MethodBuilder.SetCustomAttribute (string args) | `TRIM-RED:MemberMissing:member lookup returned null: CustomAttributeBuilder` |
| NativeAOT | mlc | A13b2 MethodBuilder.SetCustomAttribute (string args) | `TRIM-RED:MemberMissing:member lookup returned null: CustomAttributeBuilder` |
| NativeAOT | runtime | A13c1 new CustomAttributeBuilder with a RUNTIME-sourced ctor [isolates A13b1] | `AOT-RED:PlatformNotSupportedException:Dynamic code generation is not supported on this platform.` |
| NativeAOT | mlc | A13c1 new CustomAttributeBuilder with a RUNTIME-sourced ctor [isolates A13b1] | `AOT-RED:PlatformNotSupportedException:Dynamic code generation is not supported on this platform.` |
| NativeAOT | runtime | A13c2 SetCustomAttribute with that RUNTIME-sourced builder | `TRIM-RED:MemberMissing:member lookup returned null: CustomAttributeBuilder` |
| NativeAOT | mlc | A13c2 SetCustomAttribute with that RUNTIME-sourced builder | `TRIM-RED:MemberMissing:member lookup returned null: CustomAttributeBuilder` |
| NativeAOT | runtime | A16 ILGenerator.Emit overloads (OpCode\|int\|long\|float\|double\|string\|Type\|MethodInfo\|ConstructorInfo\|FieldInfo\|Label\|LocalBuilder\|byte\|short) | `RED:ArgumentNullException:Value cannot be null. (Parameter 'field')` |
| NativeAOT | runtime | A17 opcode sweep — all 124 union opcodes accepted by ILGenerator.Emit | `RED:InvalidOperationException:opcodes rejected: Ldfld=ArgumentNullException,Ldflda=ArgumentNullException,Ldsfld=ArgumentNullException,Stfld=ArgumentNullException,Stsfld=ArgumentNullException` |
| NativeAOT | runtime | Assembly::Load | `RED:FileNotFoundException:Cannot load assembly 'System.Linq'. No metadata found for this assembly.` |
| NativeAOT | runtime | Assembly::LoadFrom | `AOT-RED:PlatformNotSupportedException:Operation is not supported on this platform.` |
| CoreCLR | mlc | ConstructorInfo::Invoke | `RED:InvalidOperationException:Cannot invoke a method on objects loaded by a MetadataLoadContext.` |
| NativeAOT | mlc | ConstructorInfo::Invoke | `RED:InvalidOperationException:Cannot invoke a method on objects loaded by a MetadataLoadContext.` |
| NativeAOT | runtime | EventInfo::GetAddMethod | `TRIM-RED:MemberMissing:member lookup returned null: event` |
| NativeAOT | runtime | EventInfo::GetRemoveMethod | `TRIM-RED:MemberMissing:member lookup returned null: event` |
| NativeAOT | runtime | EventInfo::get_EventHandlerType | `TRIM-RED:MemberMissing:member lookup returned null: event` |
| CoreCLR | mlc | FieldInfo::GetValue  [KNOWN RED on MLC] | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext.` |
| NativeAOT | runtime | FieldInfo::GetValue  [KNOWN RED on MLC] | `TRIM-RED:MemberMissing:member lookup returned null: literal field receiver` |
| NativeAOT | mlc | FieldInfo::GetValue  [KNOWN RED on MLC] | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext.` |
| NativeAOT | runtime | FieldInfo::GetRawConstantValue  [the substitute slice 2 converts to] | `TRIM-RED:MemberMissing:member lookup returned null: literal field receiver` |
| NativeAOT | runtime | FieldInfo::get_FieldType | `TRIM-RED:MemberMissing:member lookup returned null: literal field receiver` |
| NativeAOT | runtime | FieldInfo::get_IsInitOnly | `TRIM-RED:MemberMissing:member lookup returned null: static field receiver` |
| NativeAOT | runtime | FieldInfo::get_IsLiteral | `TRIM-RED:MemberMissing:member lookup returned null: literal field receiver` |
| NativeAOT | runtime | FieldInfo::get_IsPublic | `TRIM-RED:MemberMissing:member lookup returned null: literal field receiver` |
| NativeAOT | runtime | FieldInfo::get_IsStatic | `TRIM-RED:MemberMissing:member lookup returned null: literal field receiver` |
| CoreCLR | mlc | MemberInfo::IsDefined | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext. Use CustomAttributeData instead.` |
| NativeAOT | mlc | MemberInfo::IsDefined | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext. Use CustomAttributeData instead.` |
| NativeAOT | runtime | MemberInfo::get_MetadataToken | `RED:InvalidOperationException:There is no metadata token available for the given member.` |
| NativeAOT | runtime | MethodBase::get_IsGenericMethod | `TRIM-RED:MemberMissing:member lookup returned null: generic method receiver` |
| NativeAOT | runtime | MethodBase::get_IsGenericMethodDefinition | `TRIM-RED:MemberMissing:member lookup returned null: generic method receiver` |
| NativeAOT | runtime | MethodInfo::GetGenericArguments | `TRIM-RED:MemberMissing:member lookup returned null: generic method receiver` |
| NativeAOT | runtime | MethodInfo::MakeGenericMethod | `TRIM-RED:MemberMissing:member lookup returned null: generic method receiver` |
| NativeAOT | runtime | MethodInfo::GetGenericMethodDefinition | `TRIM-RED:MemberMissing:member lookup returned null: generic method receiver` |
| NativeAOT | runtime | NullabilityInfoContext::Create | `RED:ArgumentNullException:Value cannot be null. (Parameter 'propertyInfo')` |
| NativeAOT | runtime | NullabilityInfo::get_ReadState | `RED:PrerequisiteFailed:NullabilityInfoContext::Create did not produce a value in this universe` |
| NativeAOT | runtime | NullabilityInfo::get_ElementType | `RED:PrerequisiteFailed:NullabilityInfoContext::Create did not produce a value in this universe` |
| NativeAOT | runtime | NullabilityInfo::get_GenericTypeArguments | `RED:PrerequisiteFailed:NullabilityInfoContext::Create did not produce a value in this universe` |
| CoreCLR | mlc | ParameterInfo::IsDefined | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext.` |
| NativeAOT | mlc | ParameterInfo::IsDefined | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext.` |
| CoreCLR | mlc | ParameterInfo::get_DefaultValue  [KNOWN RED on MLC] | `RED:InvalidOperationException:It is illegal to request the default value on a ParameterInfo loaded by a MetadataLoadContext. Use RawDefaultValue instead.` |
| NativeAOT | mlc | ParameterInfo::get_DefaultValue  [KNOWN RED on MLC] | `RED:InvalidOperationException:It is illegal to request the default value on a ParameterInfo loaded by a MetadataLoadContext. Use RawDefaultValue instead.` |
| CoreCLR | mlc | PropertyInfo::GetValue  [KNOWN RED on MLC — no metadata substitute] | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext.` |
| NativeAOT | runtime | PropertyInfo::GetValue  [KNOWN RED on MLC — no metadata substitute] | `TRIM-RED:MemberMissing:member lookup returned null: property receiver` |
| NativeAOT | mlc | PropertyInfo::GetValue  [KNOWN RED on MLC — no metadata substitute] | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext.` |
| NativeAOT | runtime | PropertyInfo::GetGetMethod | `TRIM-RED:MemberMissing:member lookup returned null: property receiver` |
| NativeAOT | runtime | PropertyInfo::GetSetMethod | `TRIM-RED:MemberMissing:member lookup returned null: property receiver` |
| NativeAOT | runtime | PropertyInfo::GetIndexParameters | `TRIM-RED:MemberMissing:member lookup returned null: property receiver` |
| NativeAOT | runtime | PropertyInfo::get_GetMethod | `TRIM-RED:MemberMissing:member lookup returned null: property receiver` |
| NativeAOT | runtime | PropertyInfo::get_SetMethod | `TRIM-RED:MemberMissing:member lookup returned null: property receiver` |
| NativeAOT | runtime | PropertyInfo::get_PropertyType | `TRIM-RED:MemberMissing:member lookup returned null: property receiver` |
| NativeAOT | runtime | Type::GetEvent | `TRIM-RED:MemberMissing:member lookup returned null: AppDomain event` |
| NativeAOT | runtime | Type::get_DeclaringMethod | `TRIM-RED:MemberMissing:member lookup returned null: generic method receiver` |
| CoreCLR | mlc | Type::get_TypeHandle  [recorded verbatim on MLC] | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext.` |
| NativeAOT | mlc | Type::get_TypeHandle  [recorded verbatim on MLC] | `RED:InvalidOperationException:The requested operation cannot be used on objects loaded by a MetadataLoadContext.` |
| CoreCLR | builder | Type::get_IsSZArray on a GenericTypeParameterBuilder  [the recorded NotImplementedException landmine] | `RED:NotImplementedException:The method or operation is not implemented.` |
| NativeAOT | builder | Type::get_IsSZArray on a GenericTypeParameterBuilder  [the recorded NotImplementedException landmine] | `RED:NotImplementedException:The method or operation is not implemented.` |
| NativeAOT | runtime | C1 Assembly.LoadFrom(path)  [C#:9314,:9359 · N# ExternalAssemblyScan.nl:567] | `AOT-RED:PlatformNotSupportedException:Operation is not supported on this platform.` |
| NativeAOT | runtime | C2 Assembly.Load(new AssemblyName(name))  [C#:9329 · N# ExternalAssemblyScan.nl:129, DocQuery.nl:90] | `RED:FileNotFoundException:Cannot load assembly 'System.Linq'. No metadata found for this assembly.` |

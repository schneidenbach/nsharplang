# DECODE — the AOT type-model task

Measured at `8cf40128a2175ecf5a61196a6ab7f7911ded5afc` in the isolated worktree
`/private/tmp/claude-501/-Users-spencer-repos-nsharplang/2c21afb5-aa30-49ea-93f4-de6a82d53a0d/scratchpad/wt/decode-aot-type-model`
(branch `stream/decode-aot-type-model`). No production edits. Every number below is followed by the
command that produced it. Probes live outside the repo under
`…/2c21afb5…/scratchpad/probes/{aotmlc,mlcsurface,memberscan,spell}`.

Two environment facts recorded rather than assumed: `~/repos/roslyn` **does not exist on this
machine** (`ls ~/repos` → no `roslyn` entry), so the AGENTS.md pointer could not be used; the
verification below is against the SDK's own shipping `System.Reflection.MetadataLoadContext` 10.0.5
package and against the real `ilc` NativeAOT compiler (`dotnet --list-sdks` → `10.0.105`).

---

## 0. THE HEADLINE — the task's premise is overturned

> **`MetadataLoadContext` is fully AOT-compatible. It is NOT an AOT blocker, and "replace the MLC
> external type model" is NOT what the AOT single-binary `nlc` is waiting on.**

This was not reasoned from documentation. A NativeAOT single-file `osx-arm64` binary was compiled and
executed, and it performed the analyzer's whole external-type job.

```
cd …/scratchpad/probes/aotmlc
dotnet publish -c Release -r osx-arm64 /p:PublishAot=true
./bin/Release/net10.0/osx-arm64/publish/aotmlc /opt/homebrew/Cellar/dotnet/10.0.105/libexec/shared/Microsoft.NETCore.App/10.0.5
```

Output of the native binary (`file …/aotmlc` → `Mach-O 64-bit executable arm64`, 2,382,184 bytes):

```
RUNTIME_ASM_LOCATION=''  (empty => single-file)
MLC_ASM_LOCATION='…/Microsoft.NETCore.App/10.0.5/System.Private.CoreLib.dll'
MLC_STATIC_METHODS=70
MLC_MAKEGENERIC=True
MLC_MAKEARRAY=System.String[]
MLC_ATTR_ARG type=System.Byte eqTypeofByte=False value=1 valueType=System.Byte
[Select args=2] MLC_MAKEGENERICMETHOD: OK
```

Type resolution, member enumeration, custom-attribute reads, `MakeGenericType`, `MakeArrayType`,
`MakeGenericMethod` and `IsAssignableFrom` all answer correctly with no JIT present. Note
`MLC_ASM_LOCATION` is a real path **even though the host binary is single-file** — an `RoAssembly`'s
`Location` is the file it was read from, so §3.4's `IsMetadataAssemblyPathAlreadyLoaded` keeps
working. And `MLC_ATTR_ARG … eqTypeofByte=False` reproduces §3.4's projected-`ArgumentType` trap
under AOT unchanged: the rule "test the VALUE" survives.

The package carries no `RequiresDynamicCode` annotation at all:

```
strings -a ~/.nuget/packages/system.reflection.metadataloadcontext/10.0.5/lib/net10.0/System.Reflection.MetadataLoadContext.dll \
  | grep -iE "RequiresDynamicCode|RequiresUnreferencedCode|DynamicallyAccessedMembers"
→ DynamicallyAccessedMembersAttribute, RequiresAssemblyFilesAttribute,
  RequiresUnreferencedCodeAttribute, UnconditionalSuppressMessageAttribute   (no RequiresDynamicCode)
```

`ilc` compiled the whole stack with **zero errors** and 91 advisory warning lines
(`grep -c "^ILC :" publish-aot.log` → `91`; `grep -oE "IL[0-9]{4}" … | sort | uniq -c`):

| code | count | meaning |
|---|---|---|
| IL2046 | 38 | annotation-mismatch on overrides (`GetMethodBody`) |
| IL2094 | 21 | annotation mismatch |
| IL3051 | 15 | `RequiresDynamicCode` **annotation mismatch** on MLC's `Ro*` overrides — the overrides are metadata-only |
| IL3050 | 8 | real `RequiresDynamicCode` call sites (4 in MLC, 4 in the probe's own two lines) |
| IL2075 / IL2026 / IL2070 / IL2055 | 8 / 8 / 6 / 4 | trim analysis |
| IL3000 | 2 | `Assembly.Location` in a single-file app |

The 8 `IL3050` are all `Type.MakeGenericType` / `Type.MakeArrayType`, and the run above proves they
are false positives for MLC receivers: `MLC_MAKEGENERIC=True` and `MLC_MAKEARRAY=System.String[]`
were produced by the AOT binary. **The distinction that matters — "MLC reading is AOT-safe,
Reflection.Emit's `Run` mode is not" — is confirmed by execution, not by reading.**

### 0.1 The second headline, which is larger

> **`PersistedAssemblyBuilder` — the ONLY assembly builder the emitter uses — works under NativeAOT,
> including with `MetadataLoadContext` types in every signature position.**

```
./aotmlc /opt/homebrew/…/Microsoft.NETCore.App/10.0.5
→ === PersistedAssemblyBuilder over MLC CORE ASSEMBLY, MLC types in signatures ===
  [created=Greeter] [saved=2560 bytes to /var/folders/…/MlcBuilt.dll]
  [readback type=Ns.Greeter fields=3 methods=1]   build+save: OK
  === MIXED UNIVERSE: MLC-cored builder + a RUNTIME typeof(int) in a signature ===  [bytes=2048] OK
  === RUNTIME-cored builder (what the emitter does today) ===                        [bytes=2048] OK
```

That native run built a `PersistedAssemblyBuilder` whose **core assembly is an MLC `RoAssembly`**,
defined a type over an MLC base type, fields of MLC type / MLC generic instantiation
(`List<string>`) / MLC array type, a static method with MLC signature types, drove an `ILGenerator`
(`DeclareLocal`, `Ldstr`, `Stloc`, `Ldloc`, `Call` on an **MLC `MethodInfo`**, `Ldc_I4`, `Ret`),
defined a generic type parameter, called `CreateType()`, `Save()`d it, and read the result back with
a fresh MLC (3 fields, 1 static method). The same binary, same run.

Contrast, in the same run:

```
RUNTIME_Assembly_LoadFrom: PlatformNotSupportedException: Operation is not supported on this platform.
RUNTIME_Assembly_Load_byname: FileNotFoundException: Cannot load assembly 'System.Linq'. No metadata found…
RUNTIME_Type_GetType: OK   [System.Text.StringBuilder]
EMIT_DefineDynamicAssembly: PlatformNotSupportedException: Dynamic code generation is not supported on this platform.
EMIT_PersistedAssemblyBuilder: OK   [bytes=2048]
```

`grep -n "DefineDynamicAssembly\|new PersistedAssemblyBuilder" src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs`
returns **one** builder construction and **zero** `DefineDynamicAssembly`:

```
3991:  var builder = new PersistedAssemblyBuilder(assemblyIdentity, typeof(object).Assembly);
5991:  builder.Save(stream);
```

So the emitter is already on the AOT-viable builder. **The AOT blocker in the type-model dimension
is not Reflection.Emit and not the MLC — it is that the emitter feeds that builder from the RUNTIME
loader, and the runtime loader is the thing that dies under AOT.**

### 0.2 What this does to the two inherited rulings

- §3.8's *"the real blockers are (a) Reflection.Emit in the emitter … and (b) the analyzer's MLC
  external TYPE MODEL"* — **(b) is wrong** and **(a) is wrong as stated**. `OpCodes`/`ILGenerator`/
  `TypeBuilder` under `PersistedAssemblyBuilder` are metadata+IL *writing*, which AOT permits;
  `AssemblyBuilderAccess.Run` is what AOT forbids, and the emitter does not use it.
- §3.8's *"THE AOT DECISION, not to be re-litigated"* (plan rows target the existing Reflection.Emit
  executor first; `MetadataBuilder` arrives later as a second executor) is **reaffirmed and made
  cheaper**: the existing executor is *already* the AOT backend. `MetadataBuilder` is demoted from an
  AOT prerequisite to an optional dependency-shedding backend. Nothing here re-opens that decision;
  it removes the deadline from it.
- §3.9's ruling that `015-E`'s declaration host *"retires with the AOT metadata writer"* is
  **decoupled** — see §6.

---

## 1. The census — production `.nl` naming reflection object types

Definition used (stated because 021's differs slightly and re-derivation is required):
production `.nl` = every `*.nl` under `src/` that is not `*.tests.nl`.

```
find src -name '*.nl' ! -name '*.tests.nl' | wc -l          → 403
find src -name '*.tests.nl' | wc -l                          → 287
grep -rl '^import System\.Reflection' --include='*.nl' src | grep -v '\.tests\.nl' | wc -l → 83
```

021 measured 396 / 74 / 99; the estate has grown, and the direction of every number is the same.

Naive substring counting is wrong here: `Type` is also an N# **member name** (`Type: TypeReference`
appears 18× in `Declarations.nl` alone). The census therefore counts a reflection type only in a
**type position** — after `:`, `<`, `,`, `as`, `is`, `new`, `typeof(`, or `System.` — and not when
followed by `:` or `=`. Full-line and trailing `//` comments are stripped.

```
find src -name '*.nl' ! -name '*.tests.nl' -print0 | xargs -0 perl /tmp/nl-census.pl
→ FILES_WITH_HITS: 105        TOTAL_CODE_LINES: 1702
```

**105 of 403 production `.nl` files (26.1%) name a reflection object type on a line of code, across
1,702 code lines.** Occurrences by type:

| type | occ. | type | occ. |
|---|---|---|---|
| `Type` | 1855 | `MethodBase` | 6 |
| `MethodInfo` | 220 | `AssemblyName` | 6 |
| `FieldInfo` | 62 | `CustomAttributeData` | 4 |
| `Assembly` | 51 | `EventInfo` | 2 |
| `ConstructorInfo` | 39 | `NullabilityInfoContext` | 2 |
| `ParameterInfo` | 35 | `Module` | 1 |
| `NullabilityInfo` | 15 | `PathAssemblyResolver` | 1 |
| `BindingFlags` | 7 | `MetadataAssemblyResolver` | 1 |
| `MetadataLoadContext` | 7 | `PropertyInfo` | 6 |

### 1.1 By owner family — the finding that reframes the scope

| family | files | code lines | share of lines |
|---|---|---|---|
| **`Columnar*` — binding plans + emitter-facing planners** | **47** | **1,191** | **70.0%** |
| `Analyzer*` — analyzer facts | 38 | 334 | 19.6% |
| tooling + scan (`DocQuery`, `Completion*`, `EditorType*`, `External*`, `Nullability*`, …) | 13 | 157 | 9.2% |
| shared model (`ReflectionTypeInfoModels`, `TypeInfoFactories`, `ReferenceConverter`, …) | 7 | 20 | 1.2% |

Top files: `ColumnarConstructionPlanner.nl` 113, `ColumnarTypeOfPlanner.nl` 86,
`ColumnarIteratorPlanner.nl` 69, `ColumnarRuntimeInstanceMemberResolver.nl` 63,
`ColumnarSourceDirectCallResolver.nl` 60, `ColumnarOrdinaryRuntimeDirectCallResolver.nl` 57,
`ColumnarCodePlan.nl` 56, `ColumnarCodePlanExecutor.nl` 53.

**021 framed this as "the ANALYZER's external type model across a quarter of the estate". The
measurement says the reflection object model is 70% a BACK-END dependency and 20% an analyzer one.**
Corroborated independently:

```
grep -rl "import System.Reflection.Emit" --include='*.nl' src | grep -v '\.tests\.nl' | wc -l  → 33
  (32 of the 33 are Columnar*; the one exception is TypeInfoIdentityFacts.nl)
wc -l src/NSharpLang.Compiler.BootstrapServices/ColumnarCodePlanExecutor.nl  → 2711
  OpCodes 115 · ILGenerator 16 · LocalBuilder 7 · TypeBuilder 3 · MethodBuilder 2
```

A "replace the analyzer's type model" task would have touched the smaller half.

### 1.2 The distinct member surface — what a replacement must actually offer

Source greps cannot answer "which members are called". The IL can. A throwaway
`System.Reflection.Metadata` scanner (`…/probes/memberscan`) reads the `MemberRef` table of the
freshly built estate assembly and counts call-site instructions:

```
dotnet build src/NSharpLang.Cli/Cli.csproj -c Debug        # 8m39s, "Build succeeded", 4 warnings
dotnet …/memberscan.dll src/NSharpLang.Compiler.BootstrapServices/bin/Debug/net10.0/NSharpLang.Compiler.BootstrapServices.dll
→ typedefs=1113 bodies=9331 memberrefs=4532
  DISTINCT_REFLECTION_MEMBERS=131
```

**131 distinct reflection members**, over 17 owner types:

| owner | distinct members | owner | distinct members |
|---|---|---|---|
| `System.Type` | 61 | `AssemblyName` | 4 |
| `Assembly` | 10 | `EventInfo` | 3 |
| `MethodBase` | 10 | `MetadataLoadContext` | 3 |
| `ParameterInfo` | 7 | `NullabilityInfo` | 3 |
| `PropertyInfo` | 7 | `AppDomain` | 2 |
| `FieldInfo` | 6 | `CustomAttributeData` | 2 |
| `MemberInfo` | 5 | `ConstructorInfo` | 1 |
| `MethodInfo` | 5 | `CustomAttributeTypedArgument` | 1 |
| | | `NullabilityInfoContext` | 1 |

The same scan against the **stale** packaged assembly (`~/.nsharp/lib/nlc/…dll`, SDK 0.1.0) reports
`typedefs=725 bodies=5696 memberrefs=2311 DISTINCT_REFLECTION_MEMBERS=92`. The surface grew by 39
members; the 8cf40128a number is 131. Members present only in the fresh build include
`Assembly::GetTypes`, `Assembly::get_FullName`, `CustomAttributeData::get_AttributeType`,
`CustomAttributeData::get_ConstructorArguments`, `CustomAttributeTypedArgument::get_Value`, the three
`EventInfo` members, `MemberInfo::GetCustomAttributesData`, `MemberInfo::IsDefined`,
`MemberInfo::get_MetadataToken`, `MetadataLoadContext::LoadFromAssemblyName`,
`MethodInfo::get_ReturnParameter`. **Never inherit a member census from a packaged binary.**

Heaviest call sites (`System.Type` unless noted): `op_Equality` 540, `MemberInfo::get_Name` 185,
`get_IsGenericTypeDefinition` 115, `op_Inequality` 117, `get_IsGenericType` 90, `GetGenericArguments`
84, `get_FullName` 68, `get_IsValueType` 58, `ParameterInfo::get_ParameterType` 54,
`get_IsGenericParameter` 54, `MethodBase::GetParameters` 53, `MethodInfo::get_ReturnType` 44,
`get_IsSZArray` 41.

### 1.3 Which of the 131 an MLC cannot answer — exactly four

```
dotnet …/probes/mlcsurface/bin/Release/net10.0/mlcsurface.dll /opt/homebrew/…/Microsoft.NETCore.App/10.0.5
```

| member | MLC verdict |
|---|---|
| `FieldInfo.GetValue` | **THROW** `InvalidOperationException: The requested operation cannot be used on objects loaded by a MetadataLoadContext.` → use `GetRawConstantValue` (**OK**, returned `2147483647` / `1`) |
| `PropertyInfo.GetValue` | **THROW**, same message — no metadata equivalent |
| `ConstructorInfo.Invoke` | **THROW** `Cannot invoke a method on objects loaded by a MetadataLoadContext.` |
| `ParameterInfo.DefaultValue` | **THROW** `It is illegal to request the default value on a ParameterInfo loaded by a MetadataLoadContext. Use RawDefaultValue instead.` |

Everything else in the risky set answers: `IsSZArray` (`True` on `string[]`, `False` on a bare
generic parameter — **the `NotImplementedException` landmine recorded in memory for persisted emit
does not reproduce on MLC types**), `IsByRefLike`, `IsFunctionPointer`, `GetEnumUnderlyingType`,
`MakePointerType`, `MakeByRefType`, `GetNestedType`, `IsAssignableFrom`, `AssemblyQualifiedName`,
`DeclaringMethod`, `MakeGenericMethod`, `PropertyInfo.GetGetMethod`, `Assembly.GetExportedTypes`
(1378), `Assembly.GetTypes` (2757), `Assembly.Location`, `AssemblyName.ReferenceMatchesDefinition`,
`ParameterInfo.GetCustomAttributesData`, `MemberInfo.MetadataToken`, and
**`NullabilityInfoContext.Create` over an MLC member** (`NotNull`).

The 21 executing-reflection call sites in production `.nl`
(`grep -rn "\.GetValue(\|\.Invoke(" --include='*.nl' src | grep -v '\.tests\.nl'`) split cleanly:

- **20 reflect over the compiler's OWN in-memory objects** — `AstChildrenCore.nl:284,289`,
  `AstNodeFinderCore.nl:379,384`, `CompilationUnitFacts.nl:79,84`, `TypeInfoFactories.nl:843,848`,
  `CodeFix.nl:212,217`, `BatchQueryKernels.nl:232,237`,
  `OutputFormatterAstJsonKernels.nl:138,145`, `OutputFormatterJsonKernels.nl:338`,
  `OutputFormatterReferenceFileKernels.nl:49,57`, plus the three `ConstructorInfo.Invoke`
  at `ExternalAssemblyScan.nl:577,591` and `NullabilityMetadataReflection.nl:190`.
  These are an **AOT trimming/rooting** concern (the AST types must survive trimming), not an MLC
  concern.
- **exactly ONE touches an external type**: `ColumnarExternalStaticMemberPlanner.nl:201`
  `value := field.GetValue(null)` — a static/const read on an externally-loaded field. Under MLC this
  becomes `GetRawConstantValue()`. One line.

---

## 2. The C# side — every `MetadataLoadContext` site

```
grep -rn 'MetadataLoadContext' --include='*.cs' src   → 10 lines, 2 files
```

**`src/NSharpLang.Compiler/Analyzer.cs`** (2,798 lines; `wc -l`) — 9 of the 10 lines, 4 of them
comments. Fields: `_metadataResolver` (`:33`), `_mlc` (`:34`), `_mlcAssemblies` (`:40`),
`_referenceLoadFailures` (`:45`). The surviving surface, by what each member *does*:

| member | kind of work |
|---|---|
| `LoadSystemAssemblies` (`:2365`) | **construct** — builds `NSharpMetadataResolver`, adds `RuntimeEnvironment.GetRuntimeDirectory()` + `AppContext.BaseDirectory` + every shared-framework version dir, then `new MetadataLoadContext(resolver, AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName())` (`:2385`) and loads the 27 `CommonAssemblyNames()` |
| `LoadReferencedAssembly(path)` (`:2282`) | **load by path** — `_mlc.GetAssemblies()` dedupe, `_mlc.LoadFromAssemblyPath` (`:2309`) |
| `LoadReferencedAssemblyByName(name)` (`:2322`) | **load by name** — `_mlc.LoadFromAssemblyName` (`:2332`) |
| `RegisterMetadataAssembly` (`:2341`) | **register** into `_mlcAssemblies` (`:2344`) |
| `IsMetadataAssemblyAlreadyLoaded` ×2, `IsMetadataAssemblyPathAlreadyLoaded` (`:2347`,`:2351`,`:2355`) | **dedupe predicates** — the path one reads `loadedAssembly.Location` |
| `LoadFromProjectConfig` (`:2472`) | **orchestrate** — restored-package pinning, non-NuGet deps *before* NuGet ones, test deps contribute a NAME, the ASP.NET trigger |
| `LoadProjectReference` / `LoadNuGetPackage` / `LoadProjectReferenceFile` | **resolve** project.yml reference kinds to paths |
| `RecordReferenceLoadFailure` ×2 (`:2267`,`:2272`) | **diagnose** into the write-dead `_referenceLoadFailures` |
| `Dispose` (`:2429`) | `_mlc?.Dispose()`, `_mlcAssemblies.Clear()` |
| nested **`NSharpMetadataResolver`** (`:2680–2797`) | **resolve** — `override Resolve(MetadataLoadContext, AssemblyName)` (`:2715`): already-loaded scan → search directories → exact NuGet dir → prefix-matched NuGet dirs; `TryLoadFromNuGetPackageDir` (`:2761`), `PickPackageVersionDirectory`, `AddSearchDirectory`, `PinPackageVersion` |

Every *decision* inside these is already an `AnalyzerMetadataLoadPolicy.*` call (021/9 moved 21 of
24). What is left is the **mechanism**: construct, load, register, dedupe, orchestrate, resolve,
dispose. Its C# test debt is small: `wc -l tests/AnalyzerMetadataLoadContextTests.cs` → **159**,
`grep -c "\[Fact\]"` → **2**.

**`src/NSharpLang.LanguageServer/Services/TypeResolver.cs`** (373 lines) — the single match is a
**comment** (`:30`) naming the two-universe gap. The file itself does **not** use an MLC. Its
universe is `Type.GetType(seedTypeName)?.Assembly` (`:80`) over
`EditorTypeCatalogFacts.EditorUniverseSeedTypeNames()`, reaching three assemblies of the running
language-server process.

**`src/NSharpLang.Build.Tasks/EmitIlAssembly.cs`** — **no MLC**. It reads metadata with
**Mono.Cecil** (`using Mono.Cecil;` `:7`, `AssemblyDefinition.ReadAssembly` `:147`). This is a
**fourth** metadata reader in the estate (MLC, the runtime loader, `Type.GetType`, Cecil) and is out
of this task's scope — it runs inside MSBuild, not inside `nlc`.

---

## 3. The emitter's own reflection dependence

```
wc -l src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs   → 20784   (021 measured 21,519; it shrank)
```

Reflection.**Emit** surface (`grep -c` per token): `OpCodes.` 1145 · `TypeBuilder` 147 ·
`ILGenerator` 52 · `LocalBuilder` 34 · `MethodBuilder` 27 · `FieldBuilder` 18 · `EnumBuilder` 17 ·
`ConstructorBuilder` 12 · `GenericTypeParameterBuilder` 11 · `AssemblyBuilder` 11 · `ModuleBuilder` 5
· `CustomAttributeBuilder` 4 · `PersistedAssemblyBuilder` 2 · **`DynamicMethod` 0** ·
**`SignatureHelper` 0**.

Reflection **read** surface: `Type` 585 · `MethodInfo` 62 · `BindingFlags` 45 · `Assembly` 20 ·
`FieldInfo` 13 · `ConstructorInfo` 13 · `MethodBase` 2 · `PropertyInfo` 2 · `ParameterInfo` 0 ·
`CustomAttributeData` 0.

**How much of the analyzer's type model does the emitter consume? All of it, and then a second copy
of it from a different universe.** The emitter's `Type` values come from three places:

| site | mechanism | AOT verdict (measured, §0.1) |
|---|---|---|
| `:9294` `foreach (var assembly in ExternalAssemblyScan.Loaded())` | `AppDomain.CurrentDomain.GetAssemblies()` | degraded — only what the AOT image links |
| `:2794` `Type.GetType(fullName, throwOnError: false)` | runtime loader | works for **rooted** types only |
| `:9314`, `:9359` `Assembly.LoadFrom(referencePath).GetType(…)` | runtime loader | **`PlatformNotSupportedException`** |
| `:9329` `Assembly.Load(new AssemblyName(assemblyName))` | runtime loader | **`FileNotFoundException`** |

and in N#: `ExternalAssemblyScan.nl:103` `Assembly.Load(name)`, `:553` `Assembly.LoadFrom(path)`,
`DocQuery.nl:90` `Assembly.Load(assemblyName)`.

`ExternalAssemblyScan.nl` is the **dual-universe owner**, and it says so in its own header:

> *"Metadata determines binding; an exact runtime implementation only supplies the Reflection.Emit
> handle. The two identities must match byte-for-byte."*

Every `ExternalAssemblyCatalogEntry` carries **both** a `RuntimeAssembly` (from `Assembly.Load` /
`AppDomain`) and a `MetadataAssembly` (from an MLC built at `OpenWithReferences` `:169–171` via
`CreateMetadataLoadContext` `:566–592`). §0.1 measured that the premise behind the runtime half is
false: `PersistedAssemblyBuilder` accepts MLC types for the core assembly, base types, fields,
generic instantiations, arrays, method signatures and `Emit(OpCodes.Call, …)` operands, under both
CoreCLR and NativeAOT. **The `RuntimeAssembly` half of the catalog is the AOT blocker, and it exists
to satisfy a requirement that measurement says does not exist.**

One concrete breakage the swap must carry: `OpenWithReferences` derives each common assembly's
`metadataPath` from `runtimeAssembly.get_Location()` (`:105`). §0's `RUNTIME_ASM_LOCATION=''` shows
that is **empty under single-file AOT**, so `IsInspectable && MetadataPath.Length > 0` would fail and
the MLC would be fed nothing. Those paths must be re-sourced from the resolved reference paths and
the shared-framework directory.

---

## 4. What NativeAOT actually forbids here

Measured, not read. Same native binary, same run:

| capability | NativeAOT | note |
|---|---|---|
| `MetadataLoadContext` read model (types, members, attributes, generics, arrays, assignability, `NullabilityInfoContext`) | **works** | §0, §1.3 |
| `PersistedAssemblyBuilder` + `ILGenerator` + `CreateType` + `Save` | **works** | §0.1 — 2,560-byte assembly, read back clean |
| `PersistedAssemblyBuilder` with an **MLC core assembly** and MLC types | **works** | §0.1 |
| `AssemblyBuilder.DefineDynamicAssembly` (`Run`) | **`PlatformNotSupportedException: Dynamic code generation is not supported on this platform.`** | **not used by the emitter** |
| `Assembly.LoadFrom` | **`PlatformNotSupportedException`** | 3 C# sites + 1 N# site |
| `Assembly.Load(AssemblyName)` | **`FileNotFoundException`** | 1 C# site + 2 N# sites |
| `Type.GetType(name)` | works for rooted types | 2 sites; trim-fragile |
| `Assembly.Location` on the app's own assembly | `""` | 3 N# sites |
| `AssemblyLoadContext` (collectible, `nlc test`) | not applicable | §3.8's SPAWN ruling stands |

**Verdict: NativeAOT forbids exactly two things this compiler does — loading an assembly into the
running process, and generating code to run in it. It forbids neither reading metadata with an MLC
nor writing metadata and IL with `PersistedAssemblyBuilder`.**

Scope of what was proven: `DefineType`, `DefineField`, `DefineMethod`, `DefineGenericParameters`,
`GetILGenerator`, `DeclareLocal`, `Emit` (ldstr/stloc/ldloc/call/ldc/ret), `CreateType`, `Save`,
readback. **Not** proven: `EnumBuilder`, `CustomAttributeBuilder`, exception-handling regions,
`DefineMethodOverride`, property/event definition, or the full 1,145-opcode surface. Those are all
metadata/IL *writing* and are expected to hold, but the first slice below exists to prove it rather
than assume it.

---

## 5. The N#-spellability wall, re-probed at `8cf40128a`

Ten probe projects built against the **freshly built** worktree CLI
(`src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll` — never the installed `nlc`) with
`NSHARP_COLUMNAR_DECLINE_LOG=1`.

| probe | source | result at `8cf40128a` | vs 021 |
|---|---|---|---|
| **A** | `import System.Reflection.Metadata` alone | **`Build successful!`** | same |
| **B** | `typeof(MetadataReader)` | declines `emit.local.initializer` → `emit.statement.block-child` → `emit.body` | same, identical sites |
| **B2** control | `typeof(DateTime)` | **`Build successful!` (0.6s)** | same |
| **F2** | `func Probe(_reader: MetadataReader)`, no `nuget:` | **`NL201: Type 'MetadataReader' not found`** | same |
| **C** | `import System.Reflection.PortableExecutable`, no `nuget:` | **`NL704: I can't find namespace …`** | same |
| **E3** | C + `nuget: System.Reflection.Metadata 10.0.5`, `new PEReader(stream)` | NL704 gone; declines `emit.local.initializer` | same |
| **E2** | `func Probe(reader: MetadataReader)` **with** the `nuget:` line | **NEW, sharper**: `decline site=emit.declaration.function-param message="function parameter type 'MetadataReader' could not be resolved for 'Probe'"` | 021 saw only the NL201 form |

**All five of 021's spellings reproduce. `MetadataReader` remains unspellable from the estate.**

But four probes 021 did not run change the shape of the answer:

| probe | source | result |
|---|---|---|
| **G** | `func Probe(ctx: MetadataLoadContext)`, **no** `nuget:` line | `NL201: Type 'MetadataLoadContext' not found` |
| **G2** | same **with** `nuget: System.Reflection.MetadataLoadContext 10.0.5`, calling `ctx.LoadFromAssemblyPath("x.dll")` and chaining `.GetName().get_FullName().Length` | **`Build successful!` (0.6s)** |
| **G3** | G2 + `resolver := new PathAssemblyResolver(paths)` | declines: `emit.local.initializer … declined for 'resolver'` |
| **G4** | G2 + `ctx := new MetadataLoadContext(resolver, "System.Private.CoreLib")` with the resolver as a **parameter** | declines: `emit.local.initializer … declined for 'ctx'` |

**The spellability verdict, restated precisely:**

1. `MetadataReader` / `PEReader` are unspellable in every measured form — *and it no longer matters*,
   because §0 removes the reason anyone wanted them.
2. `MetadataLoadContext` **is** spellable and callable from N# **today**: as a parameter annotation,
   as a field (`ExternalAssemblyScan.nl:61` `Context: MetadataLoadContext?`), as an instance-call
   receiver, and through a chained call on the returned `Assembly`. G2 builds.
3. The **only** remaining wall is `new` on a `nuget:`-sourced type. G3 and G4 decline at the same
   site for two different types, which is why `ExternalAssemblyScan.CreateMetadataLoadContext`
   (`:566–592`) reflection-invokes both constructors (`:577`, `:591`).

**Pricing the widening.** This is **not** a new admission class and **not** a catalog-row problem in
the broad sense — annotations, fields, parameters, instance calls and chained calls on
`nuget:`-sourced types already emit. It is one construction path: `emit.local.initializer` for a
`new` whose type comes from a `nuget:` reference. The alternative — "write the metadata reader in N#
over raw bytes" — is now **ruled out on cost/benefit**: it would hand-implement ECMA-335 table
decoding to replace a component that §0 proved already runs under AOT, and it would still have to
supply the 131-member `Type`/`MethodInfo`/… object model that 105 files consume. The cheap move is
the one-constructor widening; the expensive move buys nothing measured.

---

## 6. Relationship to `015-E` and the AOT metadata writer

- **`015-E`** (`TryEmitColumnarAssembly` at `ColumnarIlEmitter.cs:3974`, the 2,024-line declaration
  host) was ruled in §3.9 to "retire with the AOT metadata writer". §0.1 **decouples** them: the
  declaration host is AOT-viable the moment its `Type` operands come from one universe. It has no
  dependency on a `MetadataBuilder` port. `015-E` should be scheduled on the plan-row/ownership
  calendar, not on this task's.
- **The AOT metadata writer** (`MetadataBuilder` as a second executor over the same plan rows) is
  **demoted**: it is no longer on the AOT critical path. `PersistedAssemblyBuilder` *is* a
  `MetadataBuilder` client; writing a second one buys dependency independence and possibly speed, not
  AOT capability. It must not gate this task, and this task must not gate it.
- **Which lands first, and why.** Slices 1–2 below land **before** `015-E`, because slice 2 changes
  what `TryEmitColumnarAssembly` resolves external types *from*, and doing the ownership move first
  would move code that then has to be rewritten. Slices 3–5 are independent of the whole `015` arc.
- `015-B` (the plan-row lambda-body emitter) is independent of everything here: it targets the
  existing executor, which §0.1 proves is already the AOT backend.

---

## 7. Proposed staged plan

Every slice states its **closing measurement**, the **C# that shrinks**, and the **estate contracts**
it needs. Dependency-ordered.

### Slice 1 — the AOT capability floor (measurement only; no product edits)
Widen the §0 probe to the emitter's *actual* persisted-emit surface — `EnumBuilder`,
`GenericTypeParameterBuilder`, `CustomAttributeBuilder`, exception-handling regions,
`DefineMethodOverride`, property/event definition, the opcode families the 1,145 sites use — and to
all 131 members of §1.2 over MLC types. **Closing measurement:** one table, every API ×
{CoreCLR, NativeAOT} × {runtime types, MLC types}, with every red cell named and a stated
consequence. **C# shrunk:** none. **Contracts:** none. **Why first:** every later slice's shape
depends on which cells are red, and §4 names exactly what was not yet proven.

### Slice 2 — one type universe: the emitter reads from the MLC catalog
Delete the runtime-loader half. C# sites: `ColumnarIlEmitter.cs:2794`, `:9314`, `:9329`, `:9359`.
N# sites: `ExternalAssemblyScan.nl:103`, `:553`, `DocQuery.nl:90`, and `Loaded()`'s
`AppDomain.CurrentDomain.GetAssemblies()`. Re-source `metadataPath` so it does not come from
`Assembly.Location` (§3). Retire `ExternalAssemblyCatalogEntry.RuntimeAssembly`,
`AttachRuntimeAssembly` and `TryLoadExactRuntimeAssembly` if slice 1 shows no red cell requiring
them. Convert `ColumnarExternalStaticMemberPlanner.nl:201` `field.GetValue(null)` →
`GetRawConstantValue()` (§1.3). **Closing measurement:** `Assembly.Load`/`LoadFrom` +
`AppDomain.GetAssemblies` sites 7 → 0 in production; A/B over the corpus with **all normalized IL
digests identical** (the 021/8 pattern); `ExternalAssemblyScan` decline census unchanged.
**C# shrunk:** `ColumnarIlEmitter.cs` (4 resolution sites and their fallback ladders).
**Contracts:** `ExternalAssemblyScan.tests.nl` gains the single-universe catalog invariant.

### Slice 3a — widen the columnar surface: `new` on a `nuget:`-sourced type
The one wall §5 leaves standing. **Closing measurement:** probes G3 and G4 build; the three
`ConstructorInfo.Invoke` sites (`ExternalAssemblyScan.nl:577`, `:591`;
`NullabilityMetadataReflection.nl:190`) are replaced by direct `new` and the reflection-invoke
helpers deleted; `ConstructorInfo::Invoke` disappears from the §1.2 IL census.
**C# shrunk:** none directly — this unblocks 3b. **Contracts:** a columnar-admission contract pinning
`new` on a `nuget:`-sourced type. (`NullabilityMetadataReflection.nl:190` invokes a **CoreLib** ctor,
not a `nuget:` one — its decline reason must be decoded separately inside this slice, not assumed.)

### Slice 3b — move the MLC quarantine out of `Analyzer.cs`
The §2 mechanism — construct / load-by-path / load-by-name / register / dedupe / orchestrate /
resolve / dispose — plus the nested `NSharpMetadataResolver` (`:2680–2797`), including the three
orchestration decisions 021/9 could not move (non-NuGet before NuGet; a test dependency contributes a
NAME; the four-stage probe order). **Closing measurement:** `grep -rn MetadataLoadContext
--include='*.cs' src` → 0 code lines; `Analyzer.cs` line count; the 58-project + 8-project
differential IDENTICAL; the 2 `[Fact]`s in `tests/AnalyzerMetadataLoadContextTests.cs` (159 lines)
migrated to estate contracts. **C# shrunk:** `Analyzer.cs` by the quarantine (021 measured 25 extents
/ 492 lines at its tip; re-measure). **Contracts:** a new `AnalyzerMetadataLoad*.tests.nl`.
**Also fix while here:** `_referenceLoadFailures` is WRITE-DEAD (§3.4), so half the NL923 pairing
rule's input never arrives; the owner already holds the table by reference.

### Slice 4 — serve the editor from the analyzer's universe
`TypeResolver.cs`'s three-assembly `Type.GetType` seed universe → the analyzer's MLC catalog. This is
§3.8's named fix and the reason `TypeResolver.cs:30`'s comment says "do not paper over it by adding a
fifth seed name". **Closing measurement:** completion offers, and hover names, a type from a package
the user depends on — proven in VS Code with computer-use, not only in unit tests (AGENTS.md's
IDE rule applies: this slice is the one that must run the VS Code-enabled gate). **C# shrunk:**
`TypeResolver.cs` (373 lines) loses `LoadSystemAssemblies`, `_loadedAssemblies`,
`_exportedTypesCache`, `_namespaceCache`, the lazy double-checked load and the `_loadLock`.
**Contracts:** `EditorTypeCatalogFacts.tests.nl` extended; `EditorUniverseSeedTypeNames()` retires.

### Slice 5 — the single-file residues, and an actual AOT `nlc`
`Assembly.Location` (3 N# sites), `Type.GetType` (2 sites) → rooted or replaced; trim roots for the
20 sites that reflect over the compiler's own AST objects (§1.3); `Program.Testing.cs`'s collectible
`AssemblyLoadContext` → the native runner SPAWNs the built test executable (§3.8's standing ruling).
**Closing measurement:** `dotnet publish src/NSharpLang.Cli /p:PublishAot=true` produces a native
`nlc` that builds hello-world **and** a corpus project, with `ilc` warning counts recorded and every
`IL3050`/`IL2026` on N#-owned code named. **C# shrunk:** `Program.Testing.cs`'s ALC block.
**Contracts:** a `cli-command-contracts` row pinning the spawned-runner behaviour through the shipped
binary.

**Not in this task:** the `MetadataBuilder` second executor (§6), `015-E`'s ownership move, and
`EmitIlAssembly.cs`'s Mono.Cecil reader (it runs inside MSBuild, never inside `nlc`).

---

## 8. Corrections this decode makes to the record

1. **§3.8 (b) — "the analyzer's MLC external TYPE MODEL" is an AOT blocker: FALSE.** MLC reads run
   correctly in a NativeAOT single-file binary (§0).
2. **§3.8 (a) — "Reflection.Emit in the emitter" as a blocker is imprecise.** `AssemblyBuilderAccess.Run`
   is forbidden; the emitter uses `PersistedAssemblyBuilder`, which works (§0.1). `grep` returns
   **0** `DefineDynamicAssembly` sites.
3. **The real type-model blocker is the emitter's RUNTIME loader**, not the analyzer's MLC: 4 C# and
   3 N# sites, of which `Assembly.LoadFrom` throws `PlatformNotSupportedException` outright (§3, §4).
4. **The reflection object model is 70% a back-end dependency** (47 `Columnar*` files / 1,191 code
   lines) and 20% an analyzer one (38 files / 334 lines) — 021 framed it as the analyzer's (§1.1).
5. **The member surface is 131, not 92** — 92 is what the stale packaged SDK 0.1.0 assembly reports.
   Never census a packaged binary (§1.2).
6. **`MetadataLoadContext` IS spellable from N#** — G2 builds with an annotation, an instance call
   and a chained call. Only `new` on a `nuget:`-sourced type declines (§5). 021's framing
   ("reflection-only") over-states the wall by four use positions.
7. **`Type.IsSZArray` does not throw on MLC types** (`True` / `False` measured), so the persisted-emit
   `NotImplementedException` landmine recorded in memory is a *runtime-Type* hazard, not an MLC one
   (§1.3).
8. **`015-E` is not gated on the AOT metadata writer** (§6).

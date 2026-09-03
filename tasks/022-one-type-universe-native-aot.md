# 022 — One external type universe, and a NativeAOT `nlc`

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

This task removes the compiler's dependence on loading assemblies into its own process, and on
generating code to run in it. It is not a `MetadataReader` port. It was also filed as "not a
`MetadataBuilder` port" on the 2026-09-01 measurement that `PersistedAssemblyBuilder` suffices; slice 2's
2h measurement withdrew that for one operation — closing an external generic over a builder-defined type
(`systems-language-closeout/decodes/2026-09-02-universe-a-viability-decode.md`) — so the writer is now
**task 023**, and this task's emit-side universe work (2f, 2g, slice 5) waits on it. Do not start the writer here.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Do not keep a runtime-loader path as a fallback beside the metadata path. A slice that routes
  through the metadata catalog but leaves `Assembly.LoadFrom` reachable is a shadow route and is not
  done.
- Every slice re-derives its predecessor's census by decode rather than inheriting it, and records
  what it overturns.
- Never census a packaged binary. `~/.nsharp/lib/nlc/…` and `~/.nuget/packages/nsharplang.sdk/…` are
  stale by 39 reflection members at the time of writing; build the estate and measure that.
- Every AOT claim is proven by publishing and RUNNING a native binary, never by reading an analyzer
  warning. `ilc` emits `IL3050`/`IL3051` on `MetadataLoadContext` code paths that then execute
  correctly; a warning is not a verdict.
- Follow every final backend, product, IDE, visual-verification, documentation, selective-staging,
  `Evidence:` commit, repin, and clean-tree rule in `AGENTS.md`.
- Backend slices (1, 2, 3a, 3b, 5) use `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` at their
  integration checkpoints. **Slice 4 touches the language server and may not skip VS Code tests**:
  run the VS Code-enabled gate, reinstall the extension, and visually verify with computer-use.
- Report only after every terminal condition below is green.

---

## Slice 1 — Establish the AOT capability floor

Measurement only. Change no product file.

Publish and run a NativeAOT probe that exercises the emitter's actual persisted-emit surface —
`EnumBuilder`, `GenericTypeParameterBuilder`, `CustomAttributeBuilder`, exception-handling regions
(including `BeginFaultBlock`, N#-only), `DefineMethodOverride`, `DefinePInvokeMethod`, property
definition (`DefineProperty` ×4; event definition is NOT in the surface — `DefineEvent`/`EventBuilder`
is 0 sites in both languages), BOTH save paths (`PersistedAssemblyBuilder.Save` for libraries and the
`GenerateMetadata` → `ManagedPEBuilder` executable path, `ColumnarIlEmitter.cs:5978–5991`), and every
opcode family the `OpCodes.` sites in `ColumnarIlEmitter.cs` and `ColumnarCodePlanExecutor.nl` use
(124 distinct in the union) — and every one of the distinct reflection members the estate calls
(131 at `8cf40128a`; 132 re-derived at `385b7e8d1`, `MethodBase::get_IsFinal` added), evaluated over
`MetadataLoadContext` types AND over runtime types.

Terminal condition: one table, every API × {CoreCLR, NativeAOT} × {runtime types, MLC types}, each
red cell named with its exception type, message and the consequence for the slices below. Seven red
cells are already known and must be reproduced rather than assumed — their provenance is CoreCLR-only
(the `mlcsurface` probe of the 2026-09-01 decode; the NativeAOT column had never been measured):
`FieldInfo.GetValue`, `PropertyInfo.GetValue` (9 sites, no substitute), `ConstructorInfo.Invoke`,
`ParameterInfo.DefaultValue`, `MemberInfo.IsDefined` (2 sites) and `ParameterInfo.IsDefined` (2 sites)
— both convert to a `GetCustomAttributesData()` scan — and `Type.TypeHandle` (2 sites, no substitute).
Record the floor in `systems-language-closeout/STATUS.md` §0 discipline — one table row plus short
findings; the full table is a dated file under `systems-language-closeout/decodes/`.

**Measured 2026-09-02 (`871b6dafc`; `decodes/2026-09-02-aot-capability-floor-decode.md`).** 408 cells.
The only emit API NativeAOT forbids is `new CustomAttributeBuilder(...)` (throws in the constructor, both
universes; four sites: `ColumnarIlEmitter.cs:4117`, `:4960`, `:5882`, `:5883`); the substitute
`SetCustomAttribute(ConstructorInfo, byte[])` is green everywhere and also removes a CoreCLR wall
(`CustomAttributeBuilder` type-checks arguments against the runtime `typeof(string)`, so an MLC-cored
builder cannot write an attribute with arguments). Everything else in persisted emit is green, including
the executable path from an MLC-cored builder. Under NativeAOT over RUNTIME types: `Assembly.LoadFrom`
throws, `MemberInfo.MetadataToken` throws (4 sites), `AppDomain.GetAssemblies()` returns 1,
`Assembly.Location` returns `""`, and BCL member lookups (`GetMethod` 33 sites, `GetField` 19,
`GetProperty` 23) RETURN NULL for members the binary statically calls — silent mis-binding, not an
exception; all of these are green over MLC types. `Type.GetType` is green in all four probed shapes.
`ilc`: 99 warnings, 0 errors; the `IL3050`s on `MakeGenericType`/`MakeArrayType()`/`MakeGenericMethod`/
`Enum.GetValues` are false (each passes); only `DefineDynamicAssembly` is real, and it has 0 sites.
Instrument trap: a `PublishAot=true` project bakes `IsDynamicCodeSupported=false` into its ORDINARY
build, so the CoreCLR host must be built `-p:PublishAot=false`.

## Slice 2 — One type universe: the emitter reads from the metadata catalog

Delete the runtime-loader half of the external type model.

Reading of "one universe" (fixed by slice 1's measurement): the EXTERNAL catalog is single-sourced from
the metadata context; the builder itself stays runtime-cored (`new PersistedAssemblyBuilder(identity,
typeof(object).Assembly)`, `ColumnarIlEmitter.cs:3991`), because `Type::GetTypeFromHandle` — `typeof(X)`
at 1,516 sites — has no MLC form and is N/A by construction. This slice also carries the
`CustomAttributeBuilder` → `SetCustomAttribute(ConstructorInfo, byte[])` conversion at the four sites:
the moment the catalog is MLC-sourced, `CustomAttributeBuilder` refuses attribute arguments.

C#: `ColumnarIlEmitter.cs:2794` (`Type.GetType`), `:9314` and `:9359` (`Assembly.LoadFrom`), `:9329`
(`Assembly.Load`), and the fallback ladders around them. N#: `ExternalAssemblyScan.nl:103`, `:553`,
`DocQuery.nl:90`, and `Loaded()`'s `AppDomain.CurrentDomain.GetAssemblies()`.

Re-source every `metadataPath` so none derives from `Assembly.Location` (11 N# sites, `ExternalAssemblyScan.nl:132`
among them) — measured to return the empty string under NativeAOT, which would silently feed the
metadata context nothing. Retire
`ExternalAssemblyCatalogEntry.RuntimeAssembly`, `AttachRuntimeAssembly` and
`TryLoadExactRuntimeAssembly` unless slice 1 produced a red cell that requires them. Convert
`ColumnarExternalStaticMemberPlanner.nl:201`'s `field.GetValue(null)` to `GetRawConstantValue()`.

Terminal condition, RE-AIMED 2026-09-02 after 2h: 2a–2d landed with whole-PE and method-body
`IL_DIFFS=0` (attribute blobs byte-identical; `GetRawConstantValue`; the two silent guards keyed on
`FullName`; `metadataPath` off `Assembly.Location`). 2e closes the slice with the loader retirements that
survive the universe question — `ExternalAssemblyScan.nl`'s `Assembly.Load` for path discovery if 2d made
it dead, the two `DocQueryTypeIndex.nl` `Assembly.Location` reads re-sourced from the reference-pack
directories — and records that `EmitIlAssembly.cs`'s Cecil corelib→contract rewrite is LOAD-BEARING until
task 023 slice 3: coring the metadata context on the reference pack was measured incompatible with the
emitter's generic surface (`new List<Point>()` over a user type is a `TypeSpec` closed by
`MakeGenericType(runtime List<>, PointTypeBuilder)` with `MemberRef`s parented on it — unreachable from a
metadata-cored builder), and a reference assembly cannot be loaded for execution
(`BadImageFormatException`). Contract-assembly references without the rewrite are task 023's. The loader
retirements that need the emit universe to be the metadata universe — `TryResolveExactRuntimeType`,
the ASP.NET/Newtonsoft and test-framework ladders, `ExternalAssemblyCatalogEntry.RuntimeAssembly` —
are task 023 slice 3's; they are not reachable through `PersistedAssemblyBuilder` (2h: `MakeGenericType`
refuses a `TypeBuilder` whatever the builder's core; every hybrid writes a second corelib `AssemblyRef`
and does not bind).

## Slice 3a — Admit `new` on external types generally; the construction allow-list retired

RE-AIMED 2026-09-02 by the slice's own decode: provenance is irrelevant — `new DeserializerBuilder()`
(NuGet) builds today and `new NullabilityInfoContext()` (CoreLib) declines, for one reason: external
construction is gated by a closed allow-list keyed on `typeof` identity
(`ColumnarConstructionPlanner.TrySelectRuntimeConstructor`, thirteen types plus seventeen approved
exception types), and anything else declines with no site of its own. The allow-list is the defect.

Replace it with the general rule: the planner consumes the analyzer's bound constructor for
`new X(args)` on an external type where the analyzer records one, and otherwise selects from the
metadata catalog by arity and argument assignability keyed on full name (never `Type` identity), with
overload ties declined loudly naming the candidates. The argument conversions the estate's own shapes
need — array → `IEnumerable<T>`, the implicit upcast to an abstract parameter type — are admitted
generally in argument planning, never as special cases.

Terminal condition: the allow-list and `IsApprovedExceptionType` (where it exists only to feed it) are
deleted; an N# function that writes `new PathAssemblyResolver(paths)`,
`new MetadataLoadContext(resolver, "System.Private.CoreLib")` and `new NullabilityInfoContext()`
builds; the three `ConstructorInfo.Invoke` sites (`ExternalAssemblyScan.nl:649`, `:663`,
`NullabilityMetadataReflection.nl:209` at `114c4cda3`) become direct construction and
`CreateMetadataLoadContext`, `SetObject` and `CreateNullabilityContext` are deleted;
`ConstructorInfo::Invoke` disappears from the estate's IL member census; the control-first corpus sweep
holds `IL_DIFFS=0` at both granularities for every previously admitted construction; the decline census
before/after names every newly admitted shape; a contract per admitted shape and per loud decline.

## Slice 3b — Retire the `MetadataLoadContext` quarantine from `Analyzer.cs`

Move the mechanism — construct, load-by-path, load-by-name, register, dedupe, orchestrate, resolve,
dispose — and the nested `NSharpMetadataResolver` to an N# owner. Carry the three orchestration
decisions the previous audit could not move because they carry no literal: non-NuGet dependencies
load before NuGet ones, a test dependency contributes its package NAME where a normal one contributes
a PATH, and `LoadReferencedAssembly`'s four-stage probe sequence.

While here, close the recorded write-dead `_referenceLoadFailures`: the owner already holds the table
by reference, so the NL923 pairing rule starts working the moment the loading surface writes to it.

Terminal condition: `MetadataLoadContext` matches zero code lines in `src/**/*.cs`; the 58-project and
8-project differentials are IDENTICAL; the two `[Fact]`s in
`tests/AnalyzerMetadataLoadContextTests.cs` (159 lines) are migrated to estate contracts and the file
is deleted; `Analyzer.cs`'s line count and extent classifier are re-measured and recorded.

## Slice 4 — Serve the editor from the analyzer's type universe

The language server's universe is three assemblies reached through `Type.GetType` seed names; the
analyzer's is a metadata context over 27 common assemblies plus the project's own references. So
completion cannot offer a type from a package the user depends on and hover cannot name one. Route
`TypeResolver.cs` to the analyzer's catalog and retire `EditorUniverseSeedTypeNames()`,
`LoadSystemAssemblies`, `_loadedAssemblies`, `_exportedTypesCache`, `_namespaceCache`, the lazy
double-checked load and the load lock.

Do not close this gap by adding another seed name.

Terminal condition: in VS Code, completion offers and hover names a type from a package the project
depends on — verified visually with computer-use and screenshots, not only by unit tests. VS
Code-enabled gate green, extension reinstalled. `TypeResolver.cs` line count recorded.

## Slice 5 — A NativeAOT `nlc`

Waits for task 023 slice 3 (the emit path binding through the writer from the metadata universe);
until then a native `nlc` cannot emit an arbitrary BCL call (slice 1: runtime member lookups return null
under NativeAOT for members the binary does not statically call).

Close the single-file residues: the `Assembly.Location` reads (11 N# sites), the `Type.GetType` sites
(73 sites across 24 production `.nl` files plus the C# ones — all four probed shapes pass under NativeAOT,
so this is a rooting audit, not a rewrite), the `CustomAttributeBuilder` sites if slice 2 has not already
converted them, trim roots for the twenty call sites that reflect over the compiler's own AST objects
(measured green unrooted; trimming fails as a null, never an exception, so each root is pinned by a
contract), and
`Program.Testing.cs`'s collectible `AssemblyLoadContext` — under a single-binary `nlc`, `nlc test`
cannot load an emitted assembly and the native runner must spawn the built test executable.

Terminal condition: `dotnet publish src/NSharpLang.Cli /p:PublishAot=true` produces a native `nlc`
that builds hello-world and a corpus project; every `ilc` warning on N#-owned code is named with a
verdict; the spawned-runner behaviour is pinned through the shipped binary in
`tests/native/cli-command-contracts`; the fresh product gate is green and the queue ledger and
present-tense architecture documentation are updated.

---

## Out of scope

- The `MetadataBuilder` second executor — it is task 023. The 2026-09-01 reading ("a second writer
  buys dependency independence, not AOT capability") is withdrawn by 2h: without it the emit path cannot
  leave the runtime universe, and the runtime universe cannot bind arbitrary BCL members under NativeAOT.
- `015-E`'s ownership move for `TryEmitColumnarAssembly`. It is not gated on a metadata writer and is
  not gated on this task beyond slice 2 landing first, because slice 2 changes what it resolves
  external types from.
- A hand-written `MetadataReader` or ECMA-335 decoder in N#. `MetadataReader` remains unspellable
  from the estate in all five measured forms, and the reason anyone wanted it has been removed.
- `EmitIlAssembly.cs`'s Mono.Cecil reader. It runs inside MSBuild, never inside `nlc`.

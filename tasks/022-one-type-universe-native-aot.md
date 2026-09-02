# 022 — One external type universe, and a NativeAOT `nlc`

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

This task removes the compiler's dependence on loading assemblies into its own process, and on
generating code to run in it. It is not a `MetadataReader` port and not a `MetadataBuilder` port.
Both were named as prerequisites by earlier records and both were measured unnecessary — see
`systems-language-closeout/decodes/2026-09-01-aot-type-model-decode.md` §0, §4, §6. Do not use this task to start either.

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
`EnumBuilder`, `GenericTypeParameterBuilder`, `CustomAttributeBuilder`, exception-handling regions,
`DefineMethodOverride`, property and event definition, and every opcode family the 1,145 `OpCodes.`
sites in `ColumnarIlEmitter.cs` use — and every one of the 131 distinct reflection members the estate
calls, evaluated over `MetadataLoadContext` types.

Terminal condition: one table, every API × {CoreCLR, NativeAOT} × {runtime types, MLC types}, each
red cell named with its exception type, message and the consequence for the slices below. Four red
cells are already known and must be reproduced rather than assumed: `FieldInfo.GetValue`,
`PropertyInfo.GetValue`, `ConstructorInfo.Invoke`, `ParameterInfo.DefaultValue`. Record the floor in
`systems-language-closeout/STATUS.md` §0 discipline — one table row plus short findings.

## Slice 2 — One type universe: the emitter reads from the metadata catalog

Delete the runtime-loader half of the external type model.

C#: `ColumnarIlEmitter.cs:2794` (`Type.GetType`), `:9314` and `:9359` (`Assembly.LoadFrom`), `:9329`
(`Assembly.Load`), and the fallback ladders around them. N#: `ExternalAssemblyScan.nl:103`, `:553`,
`DocQuery.nl:90`, and `Loaded()`'s `AppDomain.CurrentDomain.GetAssemblies()`.

Re-source every `metadataPath` so none derives from `Assembly.Location` — that returns the empty
string in a single-file binary and would silently feed the metadata context nothing. Retire
`ExternalAssemblyCatalogEntry.RuntimeAssembly`, `AttachRuntimeAssembly` and
`TryLoadExactRuntimeAssembly` unless slice 1 produced a red cell that requires them. Convert
`ColumnarExternalStaticMemberPlanner.nl:201`'s `field.GetValue(null)` to `GetRawConstantValue()`.

Terminal condition: `Assembly.Load`, `Assembly.LoadFrom` and `AppDomain.GetAssemblies` sites in
production reach zero; an A/B over the corpus produces identical outcomes with **all** normalized IL
digests identical; the `ExternalAssemblyScan` decline census is unchanged; the estate carries a
contract pinning the single-universe catalog invariant.

## Slice 3a — Admit `new` on a `nuget:`-sourced type

Widen columnar emission for the one construction path that still declines. Annotations, fields,
parameters, instance calls and chained calls on `nuget:`-sourced types already emit; only
`emit.local.initializer` for a `new` declines.

Terminal condition: an N# function that writes `new PathAssemblyResolver(paths)` and
`new MetadataLoadContext(resolver, "System.Private.CoreLib")` builds; the three
`ConstructorInfo.Invoke` sites (`ExternalAssemblyScan.nl:577`, `:591`,
`NullabilityMetadataReflection.nl:190`) become direct construction and their reflection-invoke
helpers are deleted; `ConstructorInfo::Invoke` disappears from the estate's IL member census; a
columnar-admission contract pins the new shape.

`NullabilityMetadataReflection.nl:190` invokes a **CoreLib** constructor, not a `nuget:`-sourced one.
Decode its decline reason inside this slice rather than assuming it is the same wall.

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

Close the single-file residues: the `Assembly.Location` reads, the `Type.GetType` sites, trim roots
for the twenty call sites that reflect over the compiler's own AST objects, and
`Program.Testing.cs`'s collectible `AssemblyLoadContext` — under a single-binary `nlc`, `nlc test`
cannot load an emitted assembly and the native runner must spawn the built test executable.

Terminal condition: `dotnet publish src/NSharpLang.Cli /p:PublishAot=true` produces a native `nlc`
that builds hello-world and a corpus project; every `ilc` warning on N#-owned code is named with a
verdict; the spawned-runner behaviour is pinned through the shipped binary in
`tests/native/cli-command-contracts`; the fresh product gate is green and the queue ledger and
present-tense architecture documentation are updated.

---

## Out of scope

- The `MetadataBuilder` second executor. `PersistedAssemblyBuilder` is already a `MetadataBuilder`
  client and already works under NativeAOT; a second writer buys dependency independence, not AOT
  capability, and must not gate this task.
- `015-E`'s ownership move for `TryEmitColumnarAssembly`. It is not gated on a metadata writer and is
  not gated on this task beyond slice 2 landing first, because slice 2 changes what it resolves
  external types from.
- A hand-written `MetadataReader` or ECMA-335 decoder in N#. `MetadataReader` remains unspellable
  from the estate in all five measured forms, and the reason anyone wanted it has been removed.
- `EmitIlAssembly.cs`'s Mono.Cecil reader. It runs inside MSBuild, never inside `nlc`.

# 022 slice 4 — serve the editor from the analyzer's type universe (Phase-1 decode)

Read-only decode, written at `a6b36fb4a` (branch `stream/022-s3b2-load-surface`, base
`72f93322c`) while gate r21 runs on the merged 3b-4a/3b-4b. No product file was touched and no build
or test was run to produce it. Every claim below is a READ; every claim that needs execution is filed
in §6 as a probe rather than asserted.

---

## 1. What the gap actually is

`TypeResolver.cs` (373 lines) reaches its universe through
`EditorTypeCatalogFacts.EditorUniverseSeedTypeNames()` → `Type.GetType(seedName)` → `.Assembly`.
Four seed names, de-duplicated, reaching **three assemblies of the running language-server process**.
The analyzer's universe is a `MetadataLoadContext` over 27 common assemblies **plus every reference
the project declares**, which 022/3b-2..3b-4b has just finished moving into
`AnalyzerMetadataLoadSurface`/`AnalyzerMetadataAssemblyResolver`.

So the editor cannot offer, and cannot hover, a type from a package the user depends on. The file's
own header says this and says the fix is not another seed name.

**The two universes are also different KINDS of `Type`.** The editor's are runtime types; the
analyzer's are `MetadataLoadContext` projections. That is the risk this slice has to clear, and §3
clears it by census.

## 2. Every C# site, and what happens to it

| site | lines | verdict |
|---|---|---|
| `TypeResolver._loadedAssemblies`, `_exportedTypesCache`, `_namespaceCache`, `_assembliesLoaded`, `_loadLock` | 5 fields | DIE — the universe is the analyzer's, and it is not lazily loaded here |
| `TypeResolver.EnsureAssembliesLoaded` (double-checked lock) | 13 | DIES with them |
| `TypeResolver.LoadSystemAssemblies` (the seed walk) | 19 | DIES; `EditorUniverseSeedTypeNames()` retires with it |
| `TypeResolver.ResolveTypeByFullName` | 18 | MOVES — it is `AnalyzerExternalTypeProbe.ResolveExactExternalType` over a different list |
| `TypeResolver.ResolveTypeBySimpleName` | 24 | MOVES |
| `TypeResolver.GetOrCacheExportedTypes` | 17 | MOVES (and see §5 — the cache changes meaning) |
| `TypeResolver.ResolveType` | 60 | MOVES; the alias/array/generic-strip steps are already `EditorTypeCatalogFacts`' answers |
| `TypeResolver.GetImportableTypes` | 55 | MOVES |
| `TypeResolver.GetNamespaceSuggestions` + `GetKnownNamespaces` | 47 | MOVES |
| `ImportableTypeInfo` record | 8 | MOVES to N#; `CompletionHandler.cs` follows the type's namespace |
| `TypeResolver` class + ctor + usings | remainder | either a thin forward over the N# catalog, or deleted with the handlers taking the catalog directly |
| `HoverHandler.cs:114` `_typeResolver.ResolveType(typeName)` | 1 | STAYS as a call; its receiver changes |
| `CompletionHandler.cs:134`, `:365` | 2 | STAYS as calls |
| `DocumentManager` ctor `_sharedAnalyzer` | — | STAYS; it is where the universe already lives |

Ratchet rows that move: `TypeResolver.cs` (373), and `CompletionHandler.cs` (638) / `HoverHandler.cs`
(149) only if the `ImportableTypeInfo` namespace change touches them. `DocumentManager.cs` (1,449)
gains at most a factory line — it must not grow, so the factory belongs on `Analyzer`.

## 3. THE MLC-SAFETY CENSUS — the finding that makes the slice possible

Every consumer of a resolved `Type`, exhaustively:

- `HoverHandler` reads `systemType?.Namespace` and `systemType?.Assembly?.GetName().Name`.
- `TypeResolver.GetImportableTypes` reads `Name`, `Namespace`, `FullName`, `IsPublic`, `IsNested`,
  `IsInterface`, `IsEnum`.
- `GetKnownNamespaces` reads `Namespace` off exported types.
- `ResolveType` calls `MakeArrayType()` on the element type.

**All of them are metadata reads, and `MakeArrayType()` was measured green over MLC types in slice 1.**
Nothing calls `Invoke`, `GetValue`, `TypeHandle` or any of the seven MLC-inherent reds. The editor's
consumers are therefore MLC-safe by construction, and switching the universe cannot break them —
which is the fact that turns "route the editor at the analyzer's catalog" from a hope into a plan.

`ImportableTypeInfo` is already a pure data record of strings and two bools, so nothing downstream
holds a `Type` at all.

## 4. The N# owner

**NEW `EditorTypeCatalog.nl`**, beside `EditorTypeCatalogFacts.nl` (483 lines, pure policy, unchanged).
It holds `assemblies: List<Assembly>` **BY REFERENCE** — the analyzer's `_mlcAssemblies`, the same seam
`AnalyzerExternalTypeProbe`, `AnalyzerImports`, `AnalyzerDeclarationPolicy` and
`AnalyzerMetadataLoadSurface` already use — and performs:

`ResolveType(name)`, `ResolveByFullName(fullName)`, `ResolveBySimpleName(simpleName)`,
`ImportableTypes(prefix)`, `NamespaceSuggestions(prefix)`, plus the exported-type cache.

`Analyzer` gains ONE line, the analogue of 3b-3's `CreateWellKnownTypes()`:
`public EditorTypeCatalog CreateEditorTypeCatalog() => _metadataLoadSurface.CreateEditorTypeCatalog();`
— so the list still never leaves the surface that owns it. `DocumentManager` exposes the catalog it
already has; `TypeResolver` takes it instead of `ILogger` alone.

`NSharpLang.LanguageServer` → `NSharpLang.Compiler` → `BootstrapServices` is the existing reference
direction, so an N# owner is reachable from the LSP with no new edge. (This is the same check that
made 3b-4a free: `ProjectConfig` and friends were already N#.)

## 5. THE UNIVERSE BECOMES MUTABLE, AND THAT IS A CORRECTNESS CHANGE, NOT A PERFORMANCE ONE

Today the editor's three assemblies are fixed for the life of the process, so `_namespaceCache` and
`_exportedTypesCache` can be filled once and never invalidated. The analyzer's list is **appended to**
whenever `LoadFromProjectConfig` runs — which `DocumentManager` calls per project directory, AFTER the
first completion may already have been served.

A cache that is correct today becomes a bug the moment the universe can grow: the first `import`
keystroke in a fresh window would pin a namespace set that predates the project's own packages, which
is the exact defect this slice exists to remove. The owner must key its caches on the assembly list's
identity — the count is the cheapest honest key, since the list is append-only and never reordered —
and a contract must pin it: **a namespace set computed before an assembly joins must not be the answer
after it joins.**

That contract is the one this slice cannot be considered done without, and no test in the tree makes
that statement today.

## 6. THE REPUBLISH QUESTION — one candidate boundary, unresolved by design

`EditorTypeCatalog.nl` lives in `BootstrapServices`, which compiles under the PACKAGED SDK (now packed
from `27a6d24f6`). The question is whether any read it needs is a shape that package has not admitted.
Read-only census of `ColumnarExternalBindingPlans.nl`:

| member | status by READ | verdict |
|---|---|---|
| `Assembly::GetExportedTypes` | hand row present (`:794`) | green |
| `Assembly::GetType(string)` | hand row present (`:791`), 1 argument | green — and the C#'s 3-argument `GetType(fullName, throwOnError: false, ignoreCase: false)` is **exactly the 1-argument overload's default semantics**, so the named `ignoreCase: false` the header calls out is preserved by the shorter spelling, not lost |
| `Assembly::GetName`, `AssemblyName::get_Name` | rows present | green |
| `Type::MakeArrayType`, `get_IsInterface`, `get_IsEnum` | row at `:608`/`:617` | green |
| `Type::get_Namespace`, `get_FullName`, `get_Name` | NO hand row, but spelled in production N# (`AnalyzerExtensionMethodResolution.nl:199`, `AnalyzerImports.nl:344`) | green — the ordinary resolver serves them |
| **`Type::get_IsPublic`, `Type::get_IsNested`** | **no hand row; the `:617` list does not contain them; the `get_IsPublic` rows at `:719`/`:759` are `MethodBase`/`FieldInfo`, not `Type`; not spelled anywhere in the estate** | **OPEN — probe first** |
| `Comparer<T>.Create(lambda)` | lambdas over external types decline | **must not be used** |

**The decisive question is `Type.IsPublic` / `Type.IsNested`.** `Type.Namespace` proves the hand table
is not the only route — the ordinary runtime resolver serves `Type` members it never lists — so these
two may well bind already. They may equally decline. I did not build, so I do not know, and the
project's rule is that a census is not a verdict.

Three outcomes, decided by one probe project built by the PACKAGED SDK:

1. **They bind.** No boundary. The slice proceeds end to end in one go.
2. **They decline and a derivation exists.** `IsOfferableCompletionType` already receives `fullName`,
   and a nested type's full name carries `+`; `GetExportedTypes()` returns only publicly reachable
   types, so `isPublic` is true by construction for every type that scan yields. Re-deriving both
   inside `EditorTypeCatalogFacts` from data it already has keeps the slice republish-free — at the
   cost of changing that owner's inputs, which its contract must follow.
3. **They decline and no derivation is honest.** Then the two rows are a `ColumnarExternalBindingPlans`
   change, INERT inside `BootstrapServices` until the coordinator repacks — a two-stage boundary. **In
   that case I stop before the estate-side step and report**, exactly as 3b-4b's gate was handled.

The ORDERING is a second, independent constraint and is republish-free either way:
`GetImportableTypes` and `GetNamespaceSuggestions` sort through `Comparer<T>.Create(...)`, which N#
cannot spell. The policy comparators (`CompareImportableTypes`, `CompareNamespaceSegments`) already
exist; the owner sorts with an explicit insertion sort driven by them, the route
`AnalyzerReferenceLoadReport` used before `Array.Sort(T[], int, int, IComparer<T>)` became spellable.
Whether an N# class can implement `IComparer<T>` is worth a probe but is not on the critical path.

## 7. Contracts

`EditorTypeCatalog.tests.nl`, driving a real `MetadataLoadContext` opened the way the estate opens one:

1. **The gap itself, as a positive.** A type that exists ONLY in a project-referenced assembly (not in
   the three seed assemblies) resolves, and its namespace is offered. This is the slice's whole reason
   to exist and no test states it today.
2. **The mutable universe** (§5): a namespace set computed before an assembly joins is not the answer
   after it joins; the same for the exported-type cache.
3. **Full-name resolution is case-SENSITIVE**, pinned against the `ignoreCase: false` the C# header
   named — a case-flipped spelling must not resolve.
4. **The array walk**: `Foo[]` resolves through its element, one rank per call, and a missing element
   answers null rather than a bare array of nothing.
5. **Offerability and ordering**: the curated set is offered at an empty prefix, the prefix filter
   applies otherwise, and the result respects `CompareImportableTypes` and `MaxImportableTypeResults`.
6. **A miss is an answer**: an unknown name resolves to null without throwing, over an MLC universe.

Each of 1, 2 and 3 must be shown to BITE by mutation before the slice is claimed — 3b-4b's D3 contract
passed against its own mutant on the first attempt, and that is now the arc's standing warning.

## 8. Instruments

Unchanged from 3b, plus the two this slice adds because it touches the IDE:

- estate `dotnet restore … -p:NSharpExcludeTests=false --force-evaluate` then `dotnet test` with the
  same property; baseline re-measured at the gated tip, never inherited.
- `nlc check --project P --json` over `git ls-files '*project.yml'`, base CLI (pristine detached
  worktree at the tip) vs slice CLI, compared by index and by `diff -r` on stdout, stderr and exit
  code. **This differential is expected to be IDENTICAL: nothing in the compiler's own analysis path
  changes.** A row that moves is a defect, not a result.
- control-first corpus IL sweep, ctlA vs ctlB before ctlA vs slice, with the CLI's own
  `NSharpLang.Runtime.dll` pinned to the base copy (3b-2's finding).
- decline census 0; root `nlc format --check --project .`; audit 18/18 with both keys derived LAST, at
  each commit's own tree.
- **The VS Code-ENABLED gate.** `VSCODE_TESTS=skip` is forbidden here: this slice changes the language
  server. `./scripts/test-all.sh --commit`, extension reinstalled via
  `scripts/reload-vscode-extension.sh` — and its kill step has silently failed before, so the server
  process's start time is checked before any verdict, using `pgrep -n` rather than `head -n 1` (the
  fourth-round IDE finding: the lowest pid on this machine is a stale August orphan).
- **Computer-use visual verification, which IS the terminal condition.** Completion offering, and
  hover naming, a type from a package the project depends on — screenshotted. `examples/14-minimal-api`
  or `examples/17-issue-tracker/backend` carry real `nuget:` dependencies and are the natural probe
  projects. VS Code is click-tier: no typing, so the walk must be driveable by clicks and file edits
  made through the Bash tool.

## 9. Sub-slice order

1. **4a — the probe.** One project outside the repo, built by the PACKAGED SDK, answering §6's
   `Type.IsPublic`/`Type.IsNested` question and the `IComparer<T>` question. No product file. If the
   answer is outcome 3, STOP and report the boundary.
2. **4b — `EditorTypeCatalog.nl` and its contracts**, over the analyzer's list, with the mutable-universe
   contract and its mutation. Product-side C# untouched except the one `Analyzer` factory line.
3. **4c — `TypeResolver.cs` routed and gutted**: the seed walk, the lazy lock, the three caches and
   `EditorUniverseSeedTypeNames()` retire; `ImportableTypeInfo` moves; the two handlers follow. Ratchet
   rows for `TypeResolver.cs` (and any handler that moves) repinned LAST.
4. **4d — the VS Code gate and the visual verification**, with the record and screenshots under
   `artifacts/ide-verification/`.

Slice 4 is terminal only at 4d: a green unit suite is explicitly NOT sufficient for this one.

## 10. Standing corrections found while reading

- **STATUS §1 Baselines still say the packaged SDK is "packed from `94ff758b5` on 2026-09-02 21:15".**
  The coordinator republished from `27a6d24f6` before 3b-4b. The Baselines row is stale and a slice that
  inherits it will price the two-stage wall against the wrong package.
- The `022` queue row in §1 still describes 3b-4a as "in flight (three WIP commits)". Both 3b-4a and
  3b-4b have since landed and slice 3b is terminal.

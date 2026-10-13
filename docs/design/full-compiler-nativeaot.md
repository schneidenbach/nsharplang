# Full-compiler NativeAOT

**Status:** NativeAOT host is published and runs the full check path for 8 of 21 examples. The other
13 reach emission and expose reflection, dynamic-code, metadata-universe, or backend blockers. The
CI smoke gate currently enforces JIT/R2R/AOT parity for the 8 completed check roots. Owner-approved
2026-10-13.

## Starting state and target

At the start of this owner-approved work, `nlc` had a NativeAOT front door and a separate
ReadyToRun compiler host. The front door handled `--version` and help, then started
`dotnet lib/nlc/Cli.dll` for compiler commands. Its `RuntimeFeature.IsDynamicCodeSupported` branch
trimmed the compiler from the NativeAOT image, so compiler commands still ran JIT/R2R.

The target is one `nlc` compiler host published as NativeAOT, performing `check`, `build`, and `test`
across the example corpus with current JIT/R2R results preserved. The first routing slice removes the
front-door diversion so NativeAOT enters the same N# `CliPipeline` as JIT/R2R. No production C# owner
is added. `src/NSharpLang.Cli/Program.cs` remains the CLI entry point; compiler and host logic remain
N#-owned.

## Measured source inventory

The census below was rerun on 2026-10-13 from this worktree. It scans production `.nl` files under
the compiler projects, CLI, and TestHost; `*.tests.nl` files and comments are excluded. Counts are
source call sites, not distinct API members.

| Area | Count | Interpretation |
|---|---:|---|
| Production N# files in the compiler/CLI/TestHost closure | 654 | Source files searched |
| `typeof(...)` expressions | 3,671 | 1,824 in Plan, 1,587 in Emit, 157 in Core, and 103 in other projects |
| `typeof(...)` expressions on compiler-declared types | 16 resolved sites | Most `typeof` operands name CLR/dependency types used by binding and emission. The 16 direct compiler-type handles are a small static-root subset, not a count of all reflection over compiler models. |
| Common reflection API calls | 1,341 | Code-only count of calls to 26 APIs: `GetType`, type/member lookup, custom-attribute reads, value reads, invocation, generic construction, and assignability checks. User/reference metadata and compiler-owned models are mixed in this total. |
| Compiler-owned AST reflection | 123 `TypeInfoFactoryReflection` calls | Additional string-based AST traversal probes live in `AstNodeFinderCore` and `AstChildrenCore`; all such accesses need typed replacements before the root descriptor can be removed. |
| `Type.GetType(...)` | 24 | Name-based type resolution sites; each needs an explicit metadata-catalog or static-root verdict. |
| Executable assembly loads | 10 | Seven in `ExternalAssemblyScan` and three in TestHost. These load executable assemblies into the compiler process. |
| Metadata-context assembly loads | 8 | `MetadataLoadContext.LoadFromAssemblyPath/Name` sites read metadata and are retained as the current reference model. |
| All `Assembly.Load*` and `AssemblyLoadContext` load sites | 18 | The 10 executable loads plus 8 metadata-only loads above. |
| `AppDomain` assembly enumeration | 8 | Runtime-discovered assemblies also seed or reconcile catalogs. |
| Production `DefineDynamicAssembly` / `DynamicMethod` construction | 0 / 0 | The emitter builds persisted metadata with `PersistedAssemblyBuilder`; production code does not directly create a runnable dynamic assembly or `DynamicMethod`. |
| Dynamic generic construction | 177 `MakeGenericType`; 41 `MakeGenericMethod` | These sites receive `IL3050`/`IL2060` analysis warnings where their instantiations are not statically known. |
| Test-only `DefineDynamicAssembly` calls | 22 | Reflection fixtures in `*.tests.nl`; they are not reachable from the product compiler host. |
| Test-host assembly load sites | 3 | `ReflectionTestRunner` and `XunitTestRunner` load emitted test assemblies in-process; this moves to a child-process boundary. |

`Assembly.Load*` is not one homogeneous blocker: the eight metadata-context loads are the current
read-only metadata path. The ten executable loads, load-context inventory, and test-assembly loads
are the in-process loading debt. The full-host publish now reports **1,549** ILLink/NativeAOT
warnings with `TrimmerSingleWarn=false`; the top groups are IL3050 (465), IL2070 (254), IL2026
(243), IL2075 (197), and IL2055 (184). This is the actual compiler-host warning set, unlike the
old front-door-only publish which trimmed the compiler away.

The current NativeAOT root descriptor retains **208** `NSharpLang.Compiler.Ast.*` declarations plus
`System.Index`, `System.Range`, and `RuntimeHelpers`. Those roots let analysis and the common
range/index planner run, but they are transitional: the analyzer still reports IL2075 for
`TypeInfoFactoryReflection.GetOptionalProperty`. The descriptor must shrink as those string-based AST
property reads become typed access.

## The one type universe

The compiler currently has three overlapping representations:

1. Source declarations use `TypeInfo`/`TypeReference` in Compiler.Model.
2. Reference assemblies use `System.Type` objects created by `MetadataLoadContext`.
3. Plan and Emit use runtime `System.Type` handles from `typeof(...)`, assembly scans, and static
   runtime reflection.

One universe means replacing (1) and (2) with one immutable metadata model for source and reference
types. A type identity must carry exact assembly identity, namespace/nesting, arity, and value/class
kind. Type shapes must represent generic parameters and substitutions, constructed generics, arrays,
nullable/byref/pointer forms, tuples, function types, and source-only N# types. The catalog must expose
base/interface closure, constraints, fields, properties, methods, constructors, explicit interface
implementations, attributes, nullability, accessibility, and method signatures without loading an
implementation assembly. Source declarations enter the same catalog as project, framework, and
NuGet metadata. Lookup, equality, assignability, overload ranking, generic inference, and diagnostics
must all use those identities rather than `Type.FullName` fallbacks or runtime-vs-MLC special cases.

`ExternalAssemblyScan` then becomes a path/identity/catalog owner only: it reads reference images and
must stop calling `Assembly.Load`, `Assembly.LoadFrom`, `AssemblyLoadContext.LoadFromAssemblyPath`,
or `AppDomain.GetAssemblies()` to complete the type catalog. `MetadataLoadContext` is useful as a
transition reader, but it is not the final model: its custom-context `Type` values cannot cross into
the current persisted writer for external project types. The current AOT run reaches this concrete
failure for `AutoDiscovery` and `MultiFileProject`: `The type 'Type: Product'/'Type: Person' was
created by a custom ReflectionContext and cannot be used here.`

Compiler implementation types remain ordinary statically compiled N# host types. The 16 resolved
compiler-owned `typeof` sites may stay only when they name a compiler implementation type and the
linker contract requires that static handle. They must not stand in for a user's or reference's type.

### Emitter boundary: design fork

The current sole writer is the 32,148-line `ColumnarIlEmitter.nl` path backed by
`PersistedAssemblyBuilder`/`TypeBuilder`/`ILGenerator`. Its member and signature APIs receive
`System.Type` and reflection handles. A metadata-model `Type` cannot simply be passed through: the
NativeAOT run above proves that MLC-created custom-context types are rejected in the emitted external
reference cases. Calling `Assembly.Load` to turn them into runtime types is unavailable under
NativeAOT and violates the required single metadata universe.

The next implementation slice therefore has two possible writer contracts, and they cannot coexist
as permanent fallback paths:

1. Keep `PersistedAssemblyBuilder` as the sole writer, but first prove and implement a supported way
   for it to consume symbolic external type/member references without a runtime `System.Type`.
2. Replace its handle-building boundary with a metadata-native writer that accepts the new model and
   writes `TypeRef`/`MemberRef`/signature rows directly through `MetadataBuilder` and
   `ManagedPEBuilder`, following the same low-level PE pattern Roslyn uses.

The official [`MetadataBuilder` API](https://learn.microsoft.com/dotnet/api/system.reflection.metadata.ecma335.metadatabuilder)
exposes assembly-reference, type-reference, member-reference, signature, and PE construction
primitives. That is a demonstrated route for symbolic references; no equivalent public symbolic
reference input has yet been demonstrated in the current PAB path. The owner-approved AOT capability
notes establish that `PersistedAssemblyBuilder` itself works under NativeAOT, but do not resolve this
external metadata-handle boundary. Do not start a second writer or add a runtime-load fallback until
this choice is settled.

## Migration slices and size

Sizes are source/call-site inventory, not calendar estimates. Every accepted slice must retain one
owner for both JIT/R2R and NativeAOT; no runtime-loading fallback or duplicate emitter is acceptable.

| Slice | Owner and scope | Current size | Status and acceptance evidence |
|---|---|---:|---|
| 1. Full-host entry | `CliPipeline` and front-door routing; let every compiler command enter the same N# path under JIT/R2R/AOT | 250-line N# dispatch; front-door kernels | **Done.** `e11cb9843`; native `--version` and real check route pass, and the `RuntimeFeature.IsDynamicCodeSupported` diversion is gone. |
| 2. Project and framework discovery | Typed YAML mapping and framework-root lookup when `RuntimeEnvironment.GetRuntimeDirectory()` names the native app directory | `ProjectFileParser.nl` 523 lines; new locator 175 lines; 22 parser, 26 resolver, and 13 front-door tests | **Done.** YAML mapping is at `5837fff9c`; the root lookup resolves installed `System.Runtime` under JIT, R2R, and AOT, and its focused estates pass. |
| 3. Check diagnostics JSON | Remove reflection serialization from the check result, including serializer-compatible string escaping and optional diagnostic fields | One `CheckToJson` writer and one 39-test contract file | **Done for the check envelope.** The CLI contract slice preserves .NET's escaped backtick and HTML-sensitive wire forms; the AOT smoke compares identical JSON on all three hosts. Other CLI JSON envelopes remain unfinished. |
| 4. Compiler-owned AST trimming | Replace string-based AST property reads with typed access, then remove temporary roots | 123 `TypeInfoFactoryReflection` calls; 208 AST declarations currently rooted; `TypeInfoFactories.nl` 1,185 lines and `AstNodeFinderCore.nl` 600+ lines | **In progress.** A temporary linker descriptor makes analysis runnable; the IL2075 warnings and roots stay until typed access replaces these readers. |
| 5. Unified reference/source type catalog | Make source declarations and reference metadata share one identity/model; delete executable reference loads and AppDomain inventory | 3,671 `typeof` expressions (3,411 in Plan/Emit); 1,341 common reflection calls; `ExternalAssemblyScan.nl` 2,241 lines; 10 executable loads and 8 MLC loads | **Not started.** Requires the emitter-boundary decision above; tests must cover equality, overloads, generic constraints, attributes, nullability, and project-reference identity. |
| 6. Metadata-native emission | Move plan/signature/member/IL emission to accept metadata-model handles without constructing runtime types for user/reference assemblies | `ColumnarIlEmitter.nl` 32,148 lines; 1,824 Plan and 1,587 Emit `typeof` sites; 465 IL3050 warnings in the current full-host publish | **Blocked at the design fork.** The MLC-to-PAB external type failures make a direct type-model substitution insufficient. Acceptance needs existing emit-shape estates, ILVerify, JIT/R2R parity, and AOT `build` plus execution. |
| 7. Test execution boundary | Stop loading emitted test assemblies in the compiler process; launch the test executable and preserve structured results | Three TestHost load sites; `ReflectionTestRunner.nl` 350 lines, `XunitTestRunner.nl` 543 lines | **Not started.** Test pass/fail, output, timeout, and framework protocol must pass on JIT/R2R and NativeAOT. |
| 8. Product smoke and compatibility gate | Publish the full host, enforce warnings for completed scopes, and compare `check` JSON and exits | `scripts/test-nativeaot-compiler.sh` (120 lines), shared warning-scope helper (20 lines), one CI job step, 21 example roots | **Partial gate landed.** It publishes JIT, R2R, and NativeAOT; rejects warnings in finished owners in both smoke and per-RID toolset publishing; and compares 8 of 21 examples. Grow the manifest as each AOT slice completes. |

The test-only 22 dynamic-assembly fixtures stay in the managed compiler-service estate. They should
not be rewritten merely to make the NativeAOT compiler host publish; the AOT test process boundary
must make their ownership and execution explicit.

## Cold-command measurements and expected contribution

These are the latest recorded managed-host body-edit medians available at this checkpoint. They use
the small (448-line), medium (10,640-line), and large (80,960-line) agent-loop fixtures. The check,
build, and test rows were collected on the dates shown in `memory/testing.md` and are baseline
observations, not AOT results.

| Size | Cold `nlc check` | Cold `nlc build` | Cold `nlc test` |
|---|---:|---:|---:|
| Small | 555 ms | 752 ms | 840 ms |
| Medium | 410 ms | 705 ms | 841 ms |
| Large | 489 ms | 2,330 ms | 2,609 ms |

The check values are the 2026-10-12 persisted body-edit medians; build values are the 2026-10-06
body-edit medians; test values are the 2026-10-09 body-edit medians. The experiment dates and
machine/load context are recorded in [testing.md §8a](../../memory/testing.md#8a-the-agent-loop-latency-benchmark-and-gate---agent-loop-same-project).

An earlier EventPipe attribution measured **257 ms of `NSharpLang.*` JIT intervals on medium** and
**602 ms on large** during a cold `nlc check`; these are the first measured upper-bound signal for
compiler JIT work removed by AOT. That capture predates the persisted body-edit optimization, so the
current cached-check rows before converting them into a projected median. The direct observation is
that NativeAOT can remove at most those compiler-JIT intervals from that measured experiment; the
actual cold check/build/test median improvement is not measured yet. Current AOT checks fail on 13
examples before they can serve as a full compiler benchmark, and the test process boundary is not
migrated. Do not turn the older JIT interval into fabricated AOT medians. The acceptance benchmark
will alternate fresh cold `check`, `build`, and `test` runs on the same fixture, host, and runtime;
then this table will gain the measured NativeAOT medians and paired differences.

## AOT smoke and compatibility gate

`scripts/test-nativeaot-compiler.sh` is wired into the CI package job. It builds the managed host,
publishes ReadyToRun and NativeAOT hosts for the runner RID, enables both trim and AOT analyzers, and
compares exact check JSON plus exit codes after clearing each disposable example copy's build/cache
outputs. The initial manifest contains 8 roots; they pass on JIT, R2R, and NativeAOT. The runner's
normal native toolset step separately checks the front door's `--version` and an issue-tracker check.

The full host publish currently has 1,549 analyzer warnings. They remain visible; one shared warning
scope check fails warnings in the completed root-discovery, typed project-YAML mapping, and check-JSON
method scopes during both smoke and per-RID toolset publishing, while other warnings stay assigned to
unfinished owners. The per-RID toolset includes the full NativeAOT `bin/nlc` plus a ReadyToRun
compatibility `Cli.dll`; its integration test checks a completed AOT example and runs the existing
`build`/`run`/`test` contract through the ReadyToRun host. The 8-root manifest grows only when a root
passes on all three hosts. The remaining 13 AOT check failures are recorded by current first refusal:

- `PackagePrivateSimple`, `PackagePrivateTypes`, and `WeatherDemo`: `EqualityComparer<T>.Default` was
  removed from the reflection surface.
- `AutoDiscovery` and `MultiFileProject`: an MLC type created by a custom `ReflectionContext` is
  passed into emission.
- `InParameters`: dynamic code generation is requested by an emission path.
- `TestExample`, `MinimalApi`, `TaskCli`, and `IssueTracker`: the runtime reports that the operation
  is unsupported on this platform.
- `ExceptionFilters`: the filter's first block child is refused by the emission planner.
- `ExplicitInterfaceImplementation`: `IEnumerator<string>` cannot be resolved for the emitted
  explicit implementation.
- `LockStatement`: the `Task.Run` static member call is not modeled on the AOT route.

All 21 example checks pass on the managed JIT host. The AOT gate currently covers the finished
subset, not the full product corpus. Focused estates run on the managed host during each slice; the
full non-VS-Code product gate remains an integration checkpoint after a multi-commit milestone.

## Current implementation cursor

The full `src/NSharpLang.Cli/Cli.csproj` host now publishes as NativeAOT and runs real checks. It
passes 8 of the 21 example roots and has exact JIT/R2R/AOT check-JSON parity on those roots. The
first executed slices are direct compiler routing (`e11cb9843`), typed YAML project parsing
(`5837fff9c`), framework-root resolution (`f641d7875`), and the NativeAOT-safe check JSON writer
(`e003cf6c4`). The trim descriptor and CI smoke harness in this milestone let the full host publish
and keep the eight completed roots warning-clean and parity-checked. The remaining warning scope
and partial example results are recorded above; build/test parity and cold AOT medians remain open.

The next slice is at a real design fork: decide whether `PersistedAssemblyBuilder` can be retained
with symbolic metadata handles, or whether its `System.Type`/reflection-handle boundary must be
replaced by a metadata-native writer. That decision sets the owner and size of the 3,671-site Plan /
Emit type migration. The in-process reference-load and test-load owners then move to metadata-only
catalog reads and child processes respectively.

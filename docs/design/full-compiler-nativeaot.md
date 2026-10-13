# Full-compiler NativeAOT

**Status:** measured migration plan; implementation has not yet switched the compiler host to
NativeAOT. Owner-approved 2026-10-13.

## Goal and current shape

Today `nlc` has a small NativeAOT front door and a separate ReadyToRun compiler host. The front door
handles `--version` and help, then starts `dotnet lib/nlc/Cli.dll` for compiler commands. It folds
`RuntimeFeature.IsDynamicCodeSupported` to false and trims the compiler from its own image. The
compiler remains JIT/R2R code.

The goal is one `nlc` compiler host that can be published as NativeAOT, perform `check`, `build`, and
`test` against the example corpus, and preserve current JIT/R2R results. No production C# owner is
added. `src/NSharpLang.Cli/Program.cs` remains the CLI entry point; compiler and host logic remain
N#-owned.

## Measured source inventory

The census below was rerun in this worktree at `0d3e81633` on 2026-10-13. It scans production `.nl`
files under the compiler projects, CLI, and TestHost; `*.tests.nl` files are excluded. Counts are
source call sites, not distinct API members. A method name is counted once per call expression.

| Area | Count | Interpretation |
|---|---:|---|
| Production N# files in the compiler/CLI/TestHost closure | 654 | Source files searched |
| `typeof(...)` expressions | 3,673 | 1,824 in Plan, 1,587 in Emit, 157 in Core, and 105 in the other projects |
| `typeof(...)` expressions whose operand names a compiler-declared type | 18 direct matches | Most `typeof` operands name CLR/dependency types used by binding and emission. These 18 direct compiler-type handles are static roots, not a count of all reflection over compiler models. |
| Reflection-style member calls | 1,455 | Broad source scan across type/member lookup, custom-attribute reads, value reads, and invocation. Most operate on user/reference metadata; this is not a count of compiler-type roots. |
| `Type.GetType(...)` | 24 | Name-based type resolution sites; each needs an explicit metadata-catalog or static-root verdict. |
| Runtime assembly loads | 10 | Seven in `ExternalAssemblyScan` and three in TestHost; these load executable assemblies into the compiler process. |
| Metadata-context assembly loads | 8 | `MetadataLoadContext.LoadFromAssemblyPath/Name`; these read metadata and are retained as the reference model. |
| `Assembly.Load`, `Assembly.LoadFrom`, and `AssemblyLoadContext` load calls, all forms | 18 | The 10 runtime loads plus 8 metadata-only loads above. |
| `AppDomain` assembly enumeration | 8 | Runtime-discovered assemblies are also used to seed or reconcile catalogs. |
| Production `DefineDynamicAssembly` / `DynamicMethod` calls | 0 / 0 | The emitter constructs persisted metadata with one `PersistedAssemblyBuilder`; it does not execute compiler-generated code. |
| Test-only `DefineDynamicAssembly` calls | 22 | Reflection fixtures in `*.tests.nl`; these are not reachable from the product compiler host. |
| `ReflectionTestRunner` collectible load sites | 1 direct, plus 2 runner resolution sites | Test execution must move to a child process so the NativeAOT compiler never loads the user's test assembly. |

`Assembly.Load*` is not one homogeneous blocker: the eight metadata-context loads are the desired
read-only metadata path. The ten executable loads, load-context inventory, and test-assembly loads
are the in-process loading debt. The NativeAOT front-door publish currently reports zero IL warnings
because the compiler is trimmed out; that result says nothing about the full-host warning set. The
20 compiler-object reflection sites in the earlier trimming inventory remain a focused audit set;
the first full-host publish must rederive reachability and warnings rather than treating that count as
a completed root list.

## The one type universe

The project and framework reference catalog owns one metadata universe, opened through
`MetadataLoadContext`. A user/reference type used by analysis, member binding, and emission has one
metadata identity and comes from that catalog. `ExternalAssemblyScan` must stop loading implementation
assemblies into a process `AssemblyLoadContext`, calling `Assembly.Load`, or using
`AppDomain.GetAssemblies()` to complete the catalog. Installed framework packs, project outputs,
NuGet assets, and reference images are resolved by their metadata paths and exact assembly identities.

Compiler implementation objects are separate: they are the statically compiled N# host types that
execute the compiler. A `typeof(CompilerType)` used to anchor one of those types may remain when the
linker warning and behavior contract require it. It must not stand in for a user/reference type. The
source `TypeInfo` model remains the semantic representation of declarations being compiled. The
emitter remains the single persisted-IL writer; `PersistedAssemblyBuilder` is retained as the output
builder, and attribute emission continues through the raw metadata overload that is NativeAOT-safe.
Any combination of source-defined generic types and external metadata types that the emitter cannot
represent must be proved with an N# fixture before the catalog migration is accepted.

`MetadataLoadContext` and `PersistedAssemblyBuilder` are in scope as supported NativeAOT components
per the owner-approved capability notes. Their use still needs end-to-end compiler evidence with
ordinary example projects. In particular, a successful API probe does not prove that every
source/external generic closure, custom attribute, or emitted reference shape is supported.

## Migration slices and size

Sizes are current source/call-site inventory, not calendar estimates. Each slice is accepted only
when its focused N# tests pass on the managed host and its NativeAOT publish/run check passes. The
same source owner must serve both hosts; runtime-loading fallbacks and duplicate emitters are not
acceptable end states.

| Slice | Owner and scope | Current size | Acceptance evidence |
|---|---|---:|---|
| 1. Full-host entry and warning gate | `CliPipeline` and toolset publish script: allow the NativeAOT image to enter the real command pipeline, with trim/AOT analyzers enabled and warnings as errors for completed owners | One 250-line N# dispatch file; existing front-door routing and publish gate | Native image starts, reports version/help, and reports actionable publish diagnostics for unfinished owners; JIT/R2R dispatch tests stay unchanged |
| 2. Reference metadata ownership | `ExternalAssemblyScan`, `ReferenceImageSnapshotStore`, analyzer resolver; remove runtime assembly pairing and app-domain inventory | 2,241-line scan owner; 18 load sites total, of which 10 are executable loads and 8 metadata reads; 9 app-domain inventory sites | One catalog under CoreCLR and NativeAOT; reference identity, overload/member binding, and `nlc check` parity contracts |
| 3. Metadata-backed emission | Plan/Emit binding, including type resolution, methods, fields, constructors, generic closures, attributes, and persisted writer inputs | 3,742 `typeof` sites overall, 17 direct compiler-type targets, 1,589 Emit and 1,845 Plan sites; `ColumnarIlEmitter.nl` is 32,148 lines | Existing emit-shape tests, ILVerify, whole-PE/method-body parity for unchanged JIT output, then AOT-published `nlc build` and example execution |
| 4. Compiler-object reflection and trimming | Internal model serialization, object inspection, and static roots; retain only contract-backed reflection over compiler-owned objects | 20-site focused reflection/root audit; principal owners include 1,185-line `TypeInfoFactories.nl` and 402-line `IncrementalBuildInputs.nl`; full-host IL warning census still pending | Warnings-as-errors publish for completed owners; reflection serialization/format/query contracts under JIT and NativeAOT |
| 5. Test process boundary | `NSharpLang.TestHost`: stop loading emitted test assemblies in the compiler process; launch the compiled test executable and preserve structured results/exit codes | Seven production N# files; `ReflectionTestRunner.nl` 350 lines, `XunitTestRunner.nl` 543 lines, and `NativeTestLoadContext.nl` | Focused `nlc test` projects under JIT and AOT hosts, including pass/fail, output, timeout, and test-framework cases |
| 6. Product smoke and compatibility gate | CI-compatible NativeAOT publish/run plus command parity for the 21 example `project.yml` roots | One smoke script and one CI job/step; 21 example roots | Full-host publish with IL warnings as errors; run `nlc check` over every example; compare JIT/R2R and AOT `check`, `build`, and `test` outputs and exit codes |

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
current cached-check rows need fresh JIT/R2R attribution before translating those intervals into a
current end-to-end forecast. AOT's startup and runtime memory changes are not yet measured. The
acceptance benchmark will rerun paired cold `check`, `build`, and `test` medians on the same fixture,
host, and runtime version with the AOT and managed hosts alternating; the measured medians and
structural counters will replace this estimate when the smoke gate lands.

## Initial gate contract

The NativeAOT smoke gate must publish the full compiler host for the runner RID with
`EnableTrimAnalyzer=true`, `EnableAotAnalyzer=true`, and IL warnings treated as errors for every
completed slice. It then runs `--version`, `help`, and `check` against all 21 examples, recording the
same JSON diagnostics and exit codes as the managed host. As slices complete, their owners move
under the warnings-as-errors boundary; the gate may not suppress or baseline an unfinished warning
without naming the owner, call site, and reason.

The compatibility checkpoint also runs focused estate/native projects on both hosts. When the test
process slice completes, the full non-VS-Code product gate runs through both the JIT/R2R toolset and
the published NativeAOT host. CI uses a Linux host RID and keeps the NativeAOT artifact isolated from
the normal package/install outputs.

## Current implementation cursor

The current toolset still publishes the trimmed front door plus ReadyToRun compiler host. No
full-compiler NativeAOT publish/run or AOT-vs-managed median has passed yet. The first implementation
slice must make the real compiler path reachable in a NativeAOT image, publish it with analyzer
warnings visible, and turn this source inventory into warning-by-warning migration evidence.

# N# Compiler Architecture

## Overview

N# has one supported executable backend:
- `il` - parse/analyze and emit a managed assembly directly.

The product toolchain runs through IL end to end. Projects use `backend: il` or omit the field and
take the default. The CLI and MSBuild SDK honor that path for build, run, test, perf-report, publish,
and package flows.

The parser, AST, syntax diagnostics, semantic analysis, systems analysis, columnar input builder,
IL emitter, multi-file compiler, recursive reference resolver and complete SDK EmitIlAssembly task
are N#-owned. The final canonical assertion and surviving-boundary audits pass at `0cc84110`;
compiler-only completion (`2026-09-09-compiler-only-ownership-complete.md`). CLI/editor policy and broader branch initiatives are tracked
separately. Historical allowlist labels below do not establish current completion.

```text
.nl source
  -> Lexer
  -> Parser
  -> Analyzer / semantic model
  -> IL compiler
  -> managed assembly / executable
```

## Why Emit IL Directly?

- **Backend independence:** CLI and SDK builds route through direct IL emission.
- **Production backend:** the CLI and SDK execute projects through direct IL emission.
- **Real-backend validation:** `nlc check` validates the executable backend directly.

## Main Components

1. **Lexer** - tokenizes source code (`src/NSharpLang.Compiler.Syntax/Lexer.nl`)
2. **Parser** - builds syntax trees (`src/NSharpLang.Compiler.Syntax/ColumnarParserRecovery.nl`, N#)
3. **Analyzer** - type checking and semantic analysis (`src/NSharpLang.Compiler.Core/Semantics/Analyzer.nl`, with the N# owners `AnalyzerDeclarationContext.nl`, `TypeInfoIdentityFacts.nl`, `AnalyzerConversionFacts.nl`, `AnalyzerCallableReferenceFacts.nl`, `AnalyzerWellKnownTypes.nl`, `AnalyzerWellKnownTypeFacts.nl`, `AnalyzerClrTypeConversion.nl`, `AnalyzerAssignabilityFacts.nl`, `AnalyzerExternalTypeProbe.nl`, `AnalyzerTypeReferenceFacts.nl`, `AnalyzerScopeStack.nl`, `AnalyzerProjectDiscovery.nl`, `AnalyzerTypeResolver.nl`, `AnalyzerTypeSubstitution.nl`, `AnalyzerStructuralAssignability.nl`, `AnalyzerDiagnosticSink.nl`, `AnalyzerStateModels.nl`, `AnalyzerDiagnostics.nl`, `NullabilityMetadataCore.nl`, `NullabilityMetadataReflection.nl`, `AnalyzerReflectionTypeConversion.nl`, `AnalyzerFunctionTypeFactory.nl`, `AnalyzerAssignability.nl`)
4. **Columnar backend** - emits managed PE assemblies from N# compiler tables (`src/NSharpLang.Compiler.Core/Backend.Emit/ColumnarIlEmitter.nl`)
5. **CLI** - command-line workflows (`src/NSharpLang.Cli/`)
6. **Error reporting** - diagnostics and suggestions (`src/NSharpLang.Compiler.Model/CompilerError.nl`, `ErrorCode.nl`, `ErrorMessageBuilder.nl`, `ErrorSuggestions.nl`, N#)

## Compiler.Core slice directories

`src/NSharpLang.Compiler.Core` is being carved into eight slice projects, lowest first, and ordered so
a file names only its own slice or a lower one. **S0 and S1 are carved**: `src/NSharpLang.Compiler.Model`
and `src/NSharpLang.Compiler.Syntax` are each their own N#-SDK project (one-line csproj, `project.yml`,
the SDK's `global.json` pin); Syntax takes Model with `project:`, Core takes Syntax, and every consumer
builds the Model -> Syntax -> Core DAG through those edges. The other six are still directories of Core:

| directory | slice | holds |
|---|---|---|
| `src/NSharpLang.Compiler.Model/` (Core's `Model/` holds only its estate) | S0 | the AST, the type, diagnostic and project-config models, and the shared facts every slice reads |
| `src/NSharpLang.Compiler.Syntax/` (product AND estate) | S1 | lexer, preprocessor, the columnar parser kernels and node table |
| `Semantics/` | S2 | the analyzer, the systems analyzer, flow and nullability |
| `Backend.Plan/` | S3 | the columnar planners and binding scope, and the metadata-blob writers |
| `Backend.Emit/` | S4 | `ColumnarIlEmitter` and the IL realizations |
| `CodeIntel/` | S5 | completion, hover, signature help, code fixes, DocQuery and the Linter |
| `Tooling/` | S6 | the formatter and the JSON output models |
| `Driver/` | S7 | the CLI command kernels, `MultiFileCompiler`, and the SDK emit task |

Every `.tests.nl` sits beside its subject, in the same directory, except where a row's helpers force
it into the lowest slice they build in (Syntax's `AstNodeFinderCore.tests.nl`, below). The directories are organisational
only: the SDK's `**/*.nl` globs and the CLI's source walk recurse, `project.yml` lists no sources, a
file's namespace is its own `namespace` line, and canonical source order (below) keys on the
basename, so moving a file between directories changes no byte of any assembly. `scripts/dev.sh
--since` selects tests by these directories.

**No product file reaches upward.** The last reach -- the node table's binding context -- is held as
`ColumnarBindingScope`, an empty Syntax base that `ColumnarBindingScopeFacts` (Backend.Plan) derives
from, and planners read it back through `ColumnarBindingScopeFacts.Of(nodes)`. (A base class, not a
marker interface: the committed seed's columnar emitter registers every source interface
structurally, `duck` or not, so an empty interface lands on every class in the assembly. The tip
emitter registers only `duck interface`s since `ae7daa9a4`, pinned by
`tests/native/census-nominal-interfaces`; the base can collapse to a marker after the next reseed.)
`tests/native/compiler-core-slice-direction`
holds the rule until the slices are projects: a product file under slice k naming a top-level name a
file under slice j > k owns fails it with the file, line and name, and so does a Core file outside
the eight directories. The estate's own reaches upward (171: rows in a lower slice than their
subject, and helpers another slice's rows call -- 111 of them from `Model/`) are a ceiling that may
only fall; they are the split's fixture-hoisting work.

**One `Program` holder per namespace per slice, and no per-slice estate namespace.** The emitter puts
a namespace's free functions on one `<namespace>.Program` per assembly (`ColumnarFreeFunctionHolders`),
and the estate declares ~4,000 free functions across every slice -- so once the slices are
assemblies each slice's tests-included build emits its own `NSharpLang.Compiler.Program`, and so on.
Those never meet: a slice's tests-included build references every lower slice PRODUCT-ONLY (the
SDK's `_NSharpTestedProject` scoping, in the seed since `1f1d05542`), and a lowered `test` block lands
on its own file's `<namespace>.<stem>Tests` type, unique because basenames are. The only product
holder is the global one the parser kernels write in `Syntax/`, and no `.tests.nl` is in the global
namespace. So the plan's per-slice estate namespaces (F2) buy nothing against holders, and renaming
now would cut the 558 helper reaches (69 file pairs) that cross slices inside the one assembly; if
wanted for hygiene they belong with the fixture hoisting. What CAN collide is held at the source by
the same native project: no namespace's holder written by two slices' product code (two shipped
`X.Program`s are CS0433 in every C# consumer -- `census-free-function-identity`'s shipped-holder rows
see that only in a seed built after the split), and no slice's estate declaring free functions in a
namespace a LOWER slice's product code holds.

**Carving a slice turns its types EXTERNAL to every slice above it, and name lookup now treats
external types the way it treats source ones** (found carving Model, 2026-09-24; fixed on
`census/lookup`; the carve landed on `census/model`). Before the fix `SimpleNamePrecedence`
rules 1-2 (the file's own namespace, then each enclosing one, before any import) and the
lexically-relative qualifier (`Ast.X` inside `NSharpLang.Compiler`) applied to SOURCE declarations only,
in the analyzer and in the emitter's binding scope alike, so once Model was an assembly `TypeInfo`
(3,552 bare uses in 193 Core files) bound `System.Reflection.TypeInfo` through an import, `Ast.X` did
not resolve, and two imports supplying one external name resolved first-import-wins in the emitter
(which `nlc format`'s import sort could silently flip). Now `SimpleNamePrecedence.Select` /
`SelectQualified` own the RULE: every candidate namespace is asked of source and metadata, the first
lexical one that declares the name wins, and the import tier is one tier whose ties are NL209 in the
analyzer and a named `emit.names.ambiguous-import` decline in the emitter (see
`memory/components/analyzer.md`, "THE RULE, NOT ONLY THE ORDER"). The fix changes how Core compiles
ITSELF (the emit-only path has no analyzer), so a slice carve needs it republished in the seed first.
A class's EMITTED parent is selected through the same gated walk, so a bare base binds the enclosing
namespace's referenced-assembly type over an imported source one (`ExternalLexicalLookup`'s base row).
The binding scope's member-name FENCE (`AddClassBaseScope` -> `classBaseNameByType`) is built at
`Create`, before the assembly scan exists, so it resolves a base from source alone; once the scan is
prepared, `ReselectClassBasesWithMetadata` asks the same precedence rule of every written base and
moves one it settles on lexical metadata to the external-base fence, so the fence walks the parent the
class is emitted with. Before that, a bare base whose enclosing namespace's type came from a referenced
assembly kept the imported SOURCE rival in the fence, and the rival's members shadowed names inside the
class (`Environment.NewLine` refused beside a rival member `Environment`) -- invisible until
`ExternalLexicalLookup`'s rows stopped compiling their library as source.

**Compiler.Model is carved** (2026-09-24, `census/model`, on the tenth seed, whose compiler carries
the cross-assembly lookup rule and the referenced-assembly emit paths G1-G6). What the carve is:
- the product files as pure renames into `src/NSharpLang.Compiler.Model/`; Model's own estate (47 files)
  stays in Core's `Model/` directory, because its rows still reach the slices above it -- moving it is
  the fixture-hoisting work, and until then Core's tests-included build hosts Model's rows;
- the SDK packs `NSharpLang.Compiler.Model.dll` into `tools/` and names it in the emit target's
  `Inputs`; `Sdk.targets`' emit-only switch names every compiler project, not just Core (the seed
  compiles the compiler emit-only; analysis is Step 2d's job), pinned by gate-script-contracts'
  `SdkEmitStampPaths` row against Core's `project:` closure and `reseed.sh`'s `COMPILER_PROJECT_DIRS`;
  Model takes its runtime edge the ordinary way (no runtime package in its project.yml, no SDK name
  exception -- the old pair was the NU1504 duplicate);
- the compiler is several assemblies at run time: `ExternalAssemblyScan.CompilerSliceAssemblyNames`
  names Model and Core, `CompilerAssemblyReferencesIdentity` unions every slice's references, and
  `IsCompilerProductAssembly` names both;
- rows that read the compiler's own source find it through the slice layout
  (`CompilerSourceFiles`/`CompilerProjectDirectories` in Core's `Model/CompilerProjectLayout.tests.nl`,
  which follow Core's `project:` graph), and rows that need the estate HOST's own reference image
  name the host by a type it declares (`ExternalScanHost`), never by a Model type, which the host only
  runs a copy of;
- `dll:` consumers take `NSharpLang.Compiler.Model.dll` beside `NSharpLang.Compiler.Core.dll`, and an
  assembly-qualified Model type name says `NSharpLang.Compiler.Model`;
- Step 2d checks Model (ceiling 0) before Core; the compile-time bench keeps Core (the façade that now
  builds the Model -> Core DAG) as its subject.
Measured edit -> test (`./scripts/dev.sh --estate <file>Tests`, a one-line body edit, twice each, with
another session's gate running on the box): a Model file 330 / 216 s before the carve, **13.3 / 12.6 s**
after -- a body edit leaves Model's reference assembly unchanged, so neither Core nor its tests-included
build re-emits; a Core file (`Driver/RunCommandKernels.nl`) 209 / 217 s before, 253 / 249 s after. The
extra time was Core's tests-included emit (`EmitIlAssembly` 135.9 s -> 164.2 s under the committed
seed), and sampling its thread with `dotnet-stack` put all of it in `ExternalAssemblyScan.FindExactType`
misses (already 55% of the thread at the base): the emitter's owner walk cached per (file, spelling)
and so re-asked every referenced assembly for the same `<namespace>.<name>` pairs in every file.
`ColumnarExternalTypeCatalog.FindInNamespaceCached` shares that answer across files; with a scratch
stage-2 seed the same emit is **96.1 / 95.3 s**. The emit runs in the SEED's SDK task, so dev.sh sees
it after the next republish.

**Compiler.Syntax is carved** (2026-09-24, `census/syntax`, on the eleventh seed plus the pre-carve
commits a republish must carry: the front-door zero, the formatter-row split, referenced free
functions, `excludeTests` and transitive project references -- the seed's own emitter and SDK
compile Core, so referenced free functions and `excludeTests` must be IN the seed before the carve
builds). What the carve is:
- the product (28 files) AND the estate as pure renames into `src/NSharpLang.Compiler.Syntax/` -- the
  first slice whose rows are its own, because they reach only Syntax and Model. 18 estate files moved:
  Syntax's 15, and three rows that parse through Syntax's own estate helpers (`PsAst`, `Golden`,
  `AstEq`): `AstNodeFinderCore.tests.nl` (its subject is Model's, and the lowest slice its rows build
  in is Syntax -- "beside its subject" gives way there) and the parser rows of
  `ColumnarParserGenericTypeReceiver`/`ColumnarParserTypeArgumentScan`, whose ONE formatter round-trip
  row each kept them in Tooling and now lives beside the formatter (`Tooling/Formatter*.tests.nl`);
- `excludeTests: true` in Syntax's project.yml keeps every build that does not pass
  `-p:NSharpExcludeTests=false` product-only (Sdk.props reads it at evaluation time, for any N#
  project), and the estate runners run each estate project on its own: `scripts/dev.sh --estate`
  (a filter that matches no row of one project is fine, a project that proves nothing is not),
  test-all-core Step 3a, the reseed's step 8 and both CI workflows;
- Syntax's parser kernels are GLOBAL free functions, so Core's calls into them (~30 names in six
  files) are calls to a REFERENCED assembly's free functions -- which neither the analyzer nor the
  emitter could make until the carve's own fix (`memory/components/analyzer.md`, "A FREE FUNCTION
  ACROSS AN ASSEMBLY BOUNDARY"). The emit-only path compiles Core, so that fix rides the seed;
- Core takes Syntax with `project:` and Syntax takes Model, so Core reaches Model TRANSITIVELY --
  which `nlc` did not compile against until the carve's front door found it (36,701 diagnostics, every
  Model name; `ReferenceResolutionResult.ProjectOutputAssemblies`);
- the SDK packs `NSharpLang.Compiler.Syntax.dll` into `tools/` and names it in the emit target's
  `Inputs` and the emit-only switch; `CompilerSliceAssemblyNames` names it; `dll:` consumers take it
  beside Model and Core; the 11 assembly-qualified `ColumnarParserRecovery` names say
  `NSharpLang.Compiler.Syntax`; `ShippedPayloadAssemblies` reads every slice (it had missed Model);
- 16 Core files import `NSharpLang.Compiler.Columnar`: a SOURCE type's project-wide discovery had
  answered `ColumnarParserRecovery`/`ColumnarNodeTable`/`ColumnarExpressionNodeKind` for them, and a
  referenced one needs its import (62 NL002s);
- Step 2d checks Model, Syntax (both 0), then Core.

## Data Flow

### Tokenization
- Input: `.nl` source text
- Output: tokens with line/column information

### Parsing
- Input: tokens
- Output: compilation unit syntax tree

### Analysis
- Input: compilation unit
- Output: semantic result, diagnostics, type information, nullability, and binding facts

### IL Emission
- Input: syntax plus semantic context
- Output: managed PE assembly
- Process: the N# columnar backend emits metadata and IL directly.

## Current Compiler Debt

If code search finds old parser, binder, analyzer, semantic-model, diagnostics, IL-lowering, codegen,
generated-source backend, or legacy comparison path ownership, treat it as a target for replacement
and deletion. Do not preserve it because an older doc called it an inspection surface.

<a id="non-nsharp-survivors"></a>

## Non-N# survivors

This is the durable location for the final closeout allowlist. During the migration, absence from
this section does not make a non-N# file acceptable; it remains product-ownership debt until its
N# replacement is in the product path or the final audit proves it is mechanical integration.

### Current compiler boundary, 2026-09-09

The final production audit at `03c47cc42` found no surviving C# compiler-core owner. It reviewed
all25 tracked C# files in Compiler, Build.Tasks, CLI and Playground plus direct editor callers,
reusing the unchanged four-file/56-method compiler-service inventory. Exact source manifests and
the report are under `/private/tmp/nsharp-multifile-assessment/final-production-csharp-boundary-20260909.md`.
The separate final23-file assertion audit and exact-fixture corrections also pass at `0cc84110`;
the compiler-only objective is complete. This production verdict alone did not waive test migration.

| Surviving boundary | Responsibility and N# owner | Scope |
|---|---|---|
| `CodeIntelligenceService` | Constructs N# MultiFileCompiler, projects its returned ProjectSnapshot, forwards queries to CodeIntelligenceQueries/Navigation | Mechanical compiler-service facade; its old reverse-dependency rationale was removed |
| `CompletionEngine` | Chooses snapshot/disk input and routes to N# completion owners | Separate editor feature policy |
| `FixApplicator` | Calls N# parser/linter/fix services and accumulates actions | Separate fix workflow |
| `OutputFormatter` | Forwards to N# presentation kernels with nullable-list adapters | Separate CLI presentation boundary |
| `LoadProjectConfig` | Projects ProjectFileParser and AssemblyVersionUtilities results into MSBuild properties | Mechanical SDK property/logging transport |
| `LoadProjectReferences` | Converts SdkProjectReferenceProjection rows into MSBuild items | Mechanical SDK item/logging transport |
| CLI build/check callers | Supply options/paths to N# resolver and MultiFileCompiler; serialize results and manage command artifacts | Separate command workflows; no compiler decisions |
| Editor DocumentManager/handlers | Manage documents, caches, publication and navigation around N# analysis | Substantial separate IDE work; not a mechanical facade |
| PlaygroundCompiler/PlaygroundRunner | Browser orchestration around N# analysis, then a browser-only AST interpreter | Separate playground/runtime work; the interpreter is not a compiler fallback |

`RunLegacyValidationPipeline` and the SDK `ValidateWithLegacyAnalysis` property retain historical
names, but their implementation and validation decisions are wholly N#. The SDK property remains
an existing public configuration boundary. Its bootstrap emit-only selection does not invoke any
C# analyzer or legacy emitter. Removing validation or changing that public option is not required
to remove C# ownership, and must not silently alter diagnostics or bootstrap behavior.

### Historical reviewed inventory for `src/NSharpLang.Compiler`

The table records the task-021 terminal audit, not current ownership acceptance. The current
compiler cursor and ratchet are authoritative. Complete Analyzer, SystemsAnalyzer, input-builder
and ColumnarIlEmitter ownership is accepted. The complete MultiFileCompiler class is also accepted
at `27b1a8a1b`; its old C# file and ten-case recovery test file are deleted.

At that audit, tracked files in the compiler assembly were classified as follows. "Decisions"
is the product-decision census — `NL` codes / user-facing sentences / ordering sites / non-zero exit
returns. That census alone does not prove a boundary mechanical: state, control flow and failure
policy must also be reviewed. Line counts are
`ratchet epoch -> current`; no row in the entire 381-row ratchet has ever exceeded its epoch.

| path | epoch -> current | decisions | N# owner it invokes | class |
|---|---|---|---|---|
| `Analyzer.cs` | 23,451 -> 0 | removed | complete `Analyzer.nl` and existing N# collaborators | deleted; accepted at `a207ee13b` |
| `CodeIntelligence/CodeIntelligenceService.cs` | 1,906 -> 153 | 0/0/0/0 | `ProjectSnapshot.nl`, `CodeIntelligenceQueries.nl` | mechanical |
| `CodeIntelligence/CompletionEngine.cs` | 805 -> 96 | 0/1/0/0 | `CompletionEngineKernels.nl`, `CompletionReceiverFacts.nl` | mechanical |
| `CodeIntelligence/FixApplicator.cs` | 57 -> 54 | 0/0/0/0 | `ColumnarParserRecovery.nl`, `Linter.nl`, `CodeFix.nl` | mechanical |
| `CodeIntelligence/OutputFormatter.cs` | 379 -> 271 | 0/0/0/0 | `OutputFormatterJsonKernels.nl` and siblings | mechanical |
| `Columnar/ColumnarDeclineTrace.cs` | 39 -> 39 | 0/0/0/0 | `ColumnarDeclineReasons.nl` | mechanical |
| `Columnar/ColumnarIlEmitter.cs` | 21,723 -> 21,519 | **0/144/3/2** | the `Columnar*Planner/Resolver/Facts` family (33 production files) | **STILL OWNING — not mechanical** |
| `Columnar/ColumnarProgramInputBuilder.cs` | 1,062 -> 1,051 | 0/0/0/0 | 16 `global::Program.*` parser kernels | mechanical |
| `MultiFileCompiler.cs` | 670 -> 663 | 0/6/0/0 | `ImportGraph*`, `ColumnarEmissionDiagnostics.nl` | mechanical |
| `Performance/SystemsAnalyzer.cs` | 2,390 -> 1,156 | 0/0/0/0 | the twelve `Systems*Policy` types (11 files) | mechanical |
| `Compiler.csproj` | 38 -> 38 | — | — | mechanical |

Eleven further C# files in this assembly are `state:"removed"` — deleted whole, 37,616 epoch lines:
`Parser.cs`, `Formatter.cs`, `Linter.cs`, `DocQuery.cs`, the three `Ast/*.cs`, `NullabilityMetadata.cs`,
`ErrorReporting.cs`, `AstNodeFinder.cs` and `Columnar/ColumnarCompiler.cs`.

**Current ownership must be proved from source.** Historical mechanical labels do not exempt
remaining state/control ownership from the active goal:

- The complete `ColumnarIlEmitter` implementation, including SIMD loop lowering, now lives in
  `src/NSharpLang.Compiler.Core/Backend.Emit/ColumnarIlEmitter.nl`; its C# owner is deleted.
  Checkpoint `8ec52542b`, published with `d533cd51e`, passed the fresh IDE-enabled product gate,
  installed SDK verification and real-editor formatting checks. See
  the acceptance evidence (`2026-09-08-complete-columnar-emitter-ownership.md`).
- The existing `tests/native/systems-vectorization-facts` assertions and product-gate throughput
  checks remain the vectorizer's regression coverage. Calls into
  `src/NSharpLang.Runtime/SimdReductions.cs` are runtime calls; runtime reimplementation remains
  separate from compiler lowering ownership.
- The complete `MultiFileCompiler.nl` owns pipeline sequencing, state, diagnostics, emission-thread
  lifetime and failure behavior. Its ten recovery cases execute in N#. Fresh product/IDE checks,
  installed SDK self-host and real unsaved-buffer verification pass at `27b1a8a1b`.
  Acceptance (`2026-09-08-complete-multifile-compiler-ownership.md`).
- **The compilation order is canonical and independent of directory layout.** File ids are indices
  into `MultiFileCompiler`'s source list and emission walks them in that order, so the order is part
  of the emitted bytes. `CanonicalSourceOrder` (`CompilerServices.nl`) sorts every compilation's
  files by basename (ordinal), tie-broken by full path, inside `MultiFileCompilerInputBuilder.Build`
  - the one owner that `nlc build`/`check`/`test`, the SDK's `EmitIlAssembly` task and the language
  server all pass through - so the CLI's directory walk and the SDK glob's item order no longer
  decide anything, and moving a file between directories no longer changes a byte (the module
  version id and timestamp being content hashes, a whole-file comparison is the check).
  `tests/native/canonical-source-order` pins it: two layouts of one program emit identical
  implementation and reference assemblies, explicit lists in any order match discovery, a rename
  DOES move the bytes (the control), and every `src/` N# project keeps its basenames unique, which
  is what makes the Compiler.Core split's directory moves byte-identical.
- `CompilationReferenceResolver.nl` solely owns recursive reference builds, package traversal,
  caching and failure behavior. The C# owner is deleted; seven direct and four command canonicals
  execute in N#. Fresh gate and installed SDK verification are accepted at `a20dc98af`.
- `EmitIlAssembly.nl` now owns the entire SDK task, including reference scanning, traversal,
  duplicate identity reuse, rewrite/write ordering, logging and failure cleanup. Its 303-line C#
  owner is deleted; `Sdk.targets` directly loads the N# class from Compiler Core. MSBuild Task,
  ITaskItem and logging objects and Cecil metadata objects are external ecosystem APIs; all task
  policy and control flow reside in N#. This does not require a new metadata writer. The ownership
  change is accepted at `b13cc7622` with fresh product gate and installed self-host8017/8017;
  SDK task acceptance (`2026-09-09-complete-sdk-emit-task-ownership.md`).
- The former Analyzer metadata quarantine is removed with the complete C# class. Its metadata
  lifecycle and existing reflection operations are owned by N#; no metadata-writer rewrite was
  required to achieve that ownership. NativeAOT and a broader metadata-writer initiative remain
  separate from the compiler-only goal unless a concrete ownership dependency is demonstrated.

Sibling assemblies are classified the same way and carry two `(b)` pins — surfaces that retire *with
their subject* rather than moving, and which are pinned by contract in the meantime:
`Cli/Daemon/DaemonProtocol.cs`'s JSON-RPC wire DTOs, and `Playground/PlaygroundRunner.cs`'s execution
mechanism (a tree-walking interpreter that answers differently from `nlc run` on seven of fourteen
comparable programs; it retires when the playground runs emitted IL in the browser).
`Playground/PlaygroundCompiler.cs` carries the hosted playground's own presentation copy — 24
sentences and 7 ordering sites — and retires with the same Playground task.

The ratchet at `tests/native/ownership-audit/non-nsharp-growth-ratchet.v2.json` enforces this
allowlist mechanically. Since the E1 epoch it holds two row classes: CODE rows (C#, TypeScript,
JavaScript, Python, and the other implementation languages) may not grow past their epoch ceiling
(`OWN004`), and a new code file is refused outright (`OWN003` — *"new unclassified non-N# file;
implement this behavior in N# or remove the file"*); DELIVERY rows (config, MSBuild, shell and
binary surfaces) carry no ceiling but an exact reviewed fingerprint, so any drift is reported
(`OWN005`) and a new delivery file is admitted only by adding its row in a reviewed repin. `tasks/README.md` is the ordered vertical ownership queue and
`systems-language-closeout/STATUS.md` is its cursor/evidence ledger.

## Build And Test Commands

```bash
dotnet build src/NSharpLang.Compiler/Compiler.csproj
dotnet build src/NSharpLang.Cli/Cli.csproj

# the compiler-service estate (~9,200 rows beside their owners)
dotnet restore src/NSharpLang.Compiler.Core/NSharpLang.Compiler.Core.csproj -p:NSharpExcludeTests=false --force-evaluate
dotnet test src/NSharpLang.Compiler.Core/NSharpLang.Compiler.Core.csproj -p:NSharpExcludeTests=false --no-restore

# one native project
dotnet src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll test --project tests/native/<dir> --no-cache
```

There is no C# unit suite: `tests/*.cs` and `tests/Tests.csproj` are retired. Every assertion lives
either in the estate or in a `tests/native/<dir>` project, which is what the gate's Step 3a runs.

`-p:NSharpExcludeTests=false` applies to the project it is given to and to nothing it references.
MSBuild passes a global property down the whole `ProjectReference` closure, restore walk included,
so the SDK records the tested project as `_NSharpTestedProject` (Sdk.props) and hands that name to
its references through `AdditionalProperties` and the restore walk's property list (Sdk.targets); a
project that receives another project's name builds product-only - no `@(NSharpTestFiles)`, the
ordinary `obj/` in both phases - which is what `nlc test` already does for `project:` references.
Without the flag nothing is recorded or passed. `tests/native/sdk-reference-incrementality`
(`TestsIncludedScope.tests.nl`) builds an A -> B pair whose tests share a namespace and pins that B
ships no test type and no second `Program` holder, with B-tested-directly as the control;
`tests/native/census-free-function-identity` (`ShippedHolders.tests.nl`) holds every assembly an
SDK's `tools/` ships - the committed seed, or the one `NSHARP_BOOTSTRAP_DIR` names, and this tree's
next payload - to one holder per namespace, none empty.

The tested project itself builds into trees of its own: `obj/tests-included/` AND
`bin/tests-included/` (Sdk.props, both decided before the base SDK's props). Its product build keeps
`obj/` and `bin/`. Sharing `bin/` let whichever configuration wrote last win - the timestamp-gated
deps file and assembly copy - so the product output carried the test types and a deps file naming
xunit, and a stale product deps file aborted Compiler.Core's estate host
(Microsoft.TestPlatform.CoreUtilities) until `rm -rf bin`. `dotnet test <csproj>` finds the new
path by itself; nothing reads the tests-included assembly by path.
`TestsIncludedOutput.tests.nl` in the same project interleaves product and tests-included builds
twice and pins both trees; against the SDK without the split it fails on the product `Lib.dll`.

Use `./scripts/dev.sh <pattern>` for focused backend/compiler iteration and the appropriate
`./scripts/test-all.sh --commit` gate at integration checkpoints, as described in `AGENTS.md`.

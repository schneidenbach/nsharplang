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
4. **Columnar backend** - emits managed PE assemblies from N# compiler tables (`src/NSharpLang.Compiler.Emit/ColumnarIlEmitter.nl`)
5. **CLI** - command-line workflows (`src/NSharpLang.Cli/`)
6. **Error reporting** - diagnostics and suggestions (`src/NSharpLang.Compiler.Model/CompilerError.nl`, `ErrorCode.nl`, `ErrorMessageBuilder.nl`, `ErrorSuggestions.nl`, N#)

## Compiler.Core slice projects

The split is complete: Model (S0), Syntax (S1), Plan (S3), Emit (S4), CodeIntel (S5), Tooling (S6)
and Driver (S7) are separate projects, and Core retains Semantics (S2) as its façade under decision
D-B. The projects are ordered lowest first so each reference points down the dependency graph:
`src/NSharpLang.Compiler.Model`, `src/NSharpLang.Compiler.Syntax`, `src/NSharpLang.Compiler.Plan`
(S3, `Backend.Plan`), `src/NSharpLang.Compiler.Emit` (S4, `Backend.Emit`),
`src/NSharpLang.Compiler.CodeIntel`, `src/NSharpLang.Compiler.Tooling` and
`src/NSharpLang.Compiler.Driver` are each their own N#-SDK project (one-line csproj, `project.yml`,
the SDK's `global.json` pin); Syntax takes Model with `project:`, Core takes Syntax, Plan takes Core,
Emit takes Plan, CodeIntel takes Emit, Tooling takes CodeIntel, Driver takes Tooling, the `Compiler`
facade takes Driver, and every consumer builds the Model -> Syntax -> Core -> Plan -> Emit -> CodeIntel
-> Tooling -> Driver DAG through those edges. Core owns the retained Semantics project and the Model
estate:

| directory | slice | holds |
|---|---|---|
| `src/NSharpLang.Compiler.Model/` (Core's `Model/` holds only its estate) | S0 | the AST, the type, diagnostic and project-config models, and the shared facts every slice reads |
| `src/NSharpLang.Compiler.Syntax/` (product AND estate) | S1 | lexer, preprocessor, the columnar parser kernels and node table |
| `src/NSharpLang.Compiler.Core/Semantics/` | S2 | the analyzer, the systems analyzer, flow and nullability; Core's retained façade |
| `src/NSharpLang.Compiler.Plan/` (product AND estate) | S3 | the columnar planners and binding scope, and the metadata-blob writers |
| `src/NSharpLang.Compiler.Emit/` (product AND estate) | S4 | `ColumnarIlEmitter` and the IL realizations |
| `src/NSharpLang.Compiler.CodeIntel/` (product AND estate) | S5 | completion, hover, signature help, navigation, code fixes, DocQuery and the Linter |
| `src/NSharpLang.Compiler.Tooling/` (product AND estate) | S6 | the formatter and the JSON output models |
| `src/NSharpLang.Compiler.Driver/` (product AND estate) | S7 | the CLI command kernels, `MultiFileCompiler`, the reference resolver, and the SDK's three MSBuild tasks |

Every `.tests.nl` sits beside its subject, except where a row's helpers force it into the lowest
slice it builds in (Syntax's `AstNodeFinderCore.tests.nl`, below). Within a project, directories are
organizational: the SDK's `**/*.nl` globs and CLI source walk recurse, `project.yml` lists no sources,
and canonical source order keys on the basename. Moving a file across project boundaries changes its
assembly owner. `scripts/dev.sh --since` selects estate tests by these slice directories.

**No product file reaches upward.** The last reach -- the node table's binding context -- is held as
`ColumnarBindingScope`, an empty Syntax base that `ColumnarBindingScopeFacts` (Backend.Plan) derives
from, and planners read it back through `ColumnarBindingScopeFacts.Of(nodes)`. (A base class, not a
marker interface: the committed seed's columnar emitter registers every source interface
structurally, `duck` or not, so an empty interface lands on every class in the assembly. The tip
emitter registers only `duck interface`s since `ae7daa9a4`, pinned by
`tests/native/census-nominal-interfaces`; the base can collapse to a marker after the next reseed.)
`tests/native/compiler-core-slice-direction` holds the rule across the completed project graph: a
product file under slice k naming a top-level name owned by slice j > k fails with the file, line and
name; it also guards Core's retained Semantics sources. Estate reach is tracked separately from
product direction and remains the fixture-hoisting backlog.

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
A base two imports supply equally is a tie there too: the walk drops it from the fence
(`invalidClassBaseOwners`) instead of keeping the first import written, and the emitted parent is
refused with the NL209 wording (`ExternalLexicalLookup`'s class-base tie row).

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
Measured edit -> test (`./scripts/dev.sh --estate <file>Tests`, a one-line body edit, twice each, with
another session's gate on the box): a Syntax file (`Lexer.nl`, rows `LexerTests`) 227 / 320 s at
`353fb69f7`, **65-80 s** on the pre-carve seed (which still compiles Syntax WITH analysis, because its
emit-only switch predates Syntax) and **26 / 26 s** on a scratch stage-2 seed packed from the carve --
a body edit leaves Syntax's reference assembly unchanged, so neither Core nor its tests-included build
re-emits, and Core's estate answers "no row matches" in seconds; a Core file
(`Driver/RunCommandKernels.nl`) 362 / 218 s at the base, 297 / 330 s and 202 / 214 s on the same two
seeds -- Core's own and tests-included emits are the whole cost there, as before.
The subsequent Driver, Tooling, CodeIntel, Emit and Plan carves applied this boundary checklist; the
Compiler.Core split is now complete. Core remains the Semantics façade under decision D-B, so there is
no pending Semantics project carve. Step 2d checks each carved project through
`nlc check --use-built-references`; each slice owns its project edge, SDK payload and `Inputs`,
`ShippedPayloadAssemblies`, release-set entry, reseed wiring and estate selection. For the current
front-door ceilings and per-carve receipts, see `systems-language-closeout/STATUS.md` §1 and §4.13.

**Compiler.Driver is carved** (2026-09-25, `census/carve-driver`), TOP-DOWN: the slices between it and
Syntax are still Core's directories, so Driver becomes a project ABOVE Core (Driver takes Core with
`project:`, the `Compiler` facade, `Cli` and `Build.Tasks` take Driver) rather than below it. Carving
top-down needs one measurement first: nothing left in Core may name Driver, product or estate, and no
Driver row may call another slice's estate helper. The split plan's name graph found one of each and
both were cut before the move: Semantics' binder row read `CheckCommandKernels`' `string[]` signature
through a MetadataLoadContext (it reads a Semantics one now; the estate reach ceiling fell 161 -> 160),
and the resolver fixture built its generic-only diagnostic sequence with `TypeBuilder` through
Backend.Plan's and Model's estate helpers (an N# class with an explicit `IEnumerable.GetEnumerator` now).
What the carve is:
- Driver's 56 front-door diagnostics fixed in Core FIRST (Core 1,261 -> 1,205), so it starts at 0
  rather than carrying debt out of Core's count. A check of Driver that compiled Core from source
  would be BLOCKED while Core's count is above zero, so `nlc check` gained `--use-built-references`
  (a `project:` dependency read from the assembly its own build wrote, transitively; missing or stale
  is an error naming it), and Step 2d checks EVERY project that way: Driver 0 (after the four NL002s
  `SystemsReport`, a referenced type now, asked for), and Compiler (34) and Playground (0), BLOCKED
  at -1 until then, measured for the first time;
- the product (88 files) AND its estate (58) as pure renames into `src/NSharpLang.Compiler.Driver/`,
  with `excludeTests: true` and its own estate project in dev.sh, Step 3a, reseed step 8 and both CI
  workflows (Syntax 1,376 + Core 8,289 -> Syntax 1,376 + Core 7,586 + Driver 703: 9,665/9,665);
- the SDK's `UsingTask`s load `LoadProjectConfig`, `LoadProjectReferences` and `EmitIlAssembly` from
  `tools/NSharpLang.Compiler.Driver.dll`, which the SDK packs and names in the emit target's `Inputs`
  and the emit-only switch; reseed.sh builds DRIVER as the top of the graph and cleans all four
  directories; `SdkEmitStampPaths` and the estate's `CompilerProjectDirectories` walk the `project:`
  graph from Driver, not Core; `CompilerSliceAssemblyNames` names Driver; packages.sh packs it between
  Core and the facade (release set, verify-release.py and its test);
- the committed seed does not name Driver in its emit-only switch, so until a republish it compiles
  Driver WITH analysis, and that analyzer judges a referenced type's `out` argument strictly: the one
  `ColumnarProgramInput?` local passed to `TryBuildMultiFile(out program: ColumnarProgramInput)` is
  declared the way every other caller declares it. (An interpolated string with two holes as the first
  of two constructor arguments is an NL103 decline in both emitters -- bound to a local in
  `DotnetRunner` until the runtime-exception arm constructed from metadata, fixed and collapsed
  2026-09-27 on `census/chip-fixes`);
- 43 `dll:` consumers take `NSharpLang.Compiler.Driver.dll` beside Core's, 18 assembly-qualified names of
  Driver types (`MultiFileCompiler`, `DotnetRunner`, `PlaygroundFile`, ...) say
  `NSharpLang.Compiler.Driver`, and the SDK task rows load the tasks from Driver.dll.
The compile-time bench keeps Core as its subject: Core no longer contains Driver, so its corpus shrank
by Driver's lines, which the next idle-box re-measure of the baseline records.
Measured edit -> test (`./scripts/dev.sh --estate RunCommandKernelsTests`, a one-line body edit of
`RunCommandKernels.nl` and its revert, with other sessions' builds on the box): 452 / 264 s on the pre-carve
tree and the previous seed, 241 / 276 s on the pre-carve tree and the republished seed at `5733d2848`,
**94 / 106 s** on the carve and that same committed seed (which compiles Driver WITH analysis, its
emit-only switch predating Driver), and **48 / 48 s** and **61 / 54 s** on scratch stage-2 seeds packed
from the carve before and after its rebase. A Driver body edit re-emits only Driver, product-only for
the CLI and tests-included for its rows; Core and Syntax answer "no row matches" in seconds, because
nothing below Driver changed.

**Compiler.Tooling is carved** (2026-09-25, `census/carve-tooling`), TOP-DOWN like Driver: the formatter
and the JSON output models become `src/NSharpLang.Compiler.Tooling`, a project ABOVE Core and below
Driver (Tooling takes Core with `project:`, Driver takes Tooling; user decision D-A puts Tooling above
CodeIntel, so it takes Core whole rather than a CodeIntel that is not yet a project). The measurement
that gates a top-down carve found nothing to cut: the split plan's name graph over Core and every
carved slice, product and estate, has no Core file naming a Tooling one and no Tooling row calling
another slice's estate helper; Tooling reaches Model, Syntax and one Semantics type (`OperatorFacts`),
and Driver reaches Tooling (42 names). What the carve is:
- Tooling's 3 front-door diagnostics fixed in Core FIRST (Core 1,205 -> 1,202): two unused estate
  imports and an NL303 in `FormatterConfig.ParseRequiredInt` -- after an early-exit
  `if !parsed.HasValue { throw }` guard the analyzer narrows `parsed` to `int` and refuses
  `parsed.Value`, while the same read inside `if parsed.HasValue { ... }` is accepted; the read sat in
  the positive branch with a `// COMPILER:` note until the narrowing was made consistent (since fixed:
  `x.HasValue` is now a null FACT exactly like `x != null`, recorded by the binder in `AnalyzerNullFlow`
  and read back by `AnalyzerFlowNarrowing`, and `ParseRequiredInt` is the guard-clause form again);
- the product (8 files) AND its estate (8) as pure renames, with `excludeTests: true` and its own
  estate project in dev.sh, Step 3a, reseed step 8 and both CI workflows (Syntax 1,376 + Core 7,591 +
  Driver 707 -> Syntax 1,376 + Core 7,238 + Tooling 353 + Driver 707: 9,674/9,674);
- the SDK packs `tools/NSharpLang.Compiler.Tooling.dll` (Driver's task assembly now needs it) and
  names it in the emit target's `Inputs` and the emit-only switch; reseed.sh cleans and estate-runs it;
  `SdkEmitStampPaths` walks Driver -> Tooling -> Core; `CompilerSliceAssemblyNames` names it;
  packages.sh packs it between Core and Driver (release set, verify-release.py and its test);
- 43 `dll:` consumers, the NL924 boundary probe's closure and the facade-interop consumer take
  `NSharpLang.Compiler.Tooling.dll` beside Core's; no assembly-qualified name spelled a Tooling type;
- Step 2d checks Tooling (0) between Core and Driver; the slice-direction guard counts Tooling's
  product and estate in its own project.
- the committed seed (`a1a226991`, packed from `1c052c596`) does not name Tooling in its emit-only
  switch, so until the next republish it compiles Tooling WITH analysis, product and rows; Tooling's
  zero front door is what lets that build pass unchanged (measured: 0 errors on the committed seed as
  on a scratch stage-2 seed packed from the carve).
Measured edit -> test (`./scripts/dev.sh --estate FormatterConfigTests`, a one-line body edit of
`FormatterConfig.nl` and its revert, after a warm run): **162 / 166 s** on the pre-carve tree and the
committed seed (`a1a226991`) -- Core's own and tests-included emits -- **23 / 24 s** on the carve and
that same committed seed (which compiles Tooling WITH analysis), and **26 / 30 s** on a scratch
stage-2 seed packed from the carve. A Tooling body edit re-emits only Tooling and Driver above it
(product-only for the CLI, tests-included for Tooling's rows); Syntax, Core and Driver answer "no row
matches" in seconds.

**Compiler.CodeIntel is carved** (2026-09-25, `census/carve-codeintel`), TOP-DOWN like Tooling:
completion, hover, signature help, navigation, code fixes, the fix applicator, DocQuery and the Linter
become `src/NSharpLang.Compiler.CodeIntel`, a project ABOVE Core and below Tooling (CodeIntel takes Core
with `project:` and declares the `System.Reflection.MetadataLoadContext` package its own rows spell;
Tooling takes CodeIntel; user decision D-A). The top-down measurement found no product reach into
CodeIntel but 19 estate reaches in 7 rows below it, and one Backend.Plan row that spelled a CodeIntel
kernel as an assembly-qualified string -- a reach no name graph sees. All were cut in Core first, each
by moving the row to the slice that can read both sides or by reading a lower slice's owner instead:
the linter's placeholder door and the source-event rendering and backtick-rule rows moved beside their
CodeIntel subjects, the analyzer's reference-pack fixtures locate the packs through Model's
`CompilationReferenceResolverKernels.GetDotnetSharedRootCandidates` rather than DocQuery's discovery, and
the two resolver rows read Model and Semantics types (`FileResolver`,
`AnalyzerMemberResolution.TryResolveReflectionPropertyOrField`) instead of CodeIntel ones; the estate's
upward-reach ceiling fell 160 -> 141. What the carve is:
- CodeIntel's 173 front-door diagnostics fixed in Core FIRST (Core 1,202 -> 1,029; NL905 118, NL010 24,
  NL202 15, NL012 11, NL002 4, NL907 1, 146 of them in its estate), so it starts at 0. Two analyzer gaps
  are routed around with `// COMPILER:` notes: `ref p` over a `&T` parameter is typed `&&T` and refused,
  so `FixApplicatorEditEngine` forwarded its by-ref parameters bare (fixed and collapsed 2026-09-27 on
  `census/chip-fixes`: `ref p` passes the `&T` on); and `==` between a maybe-null source
  class value and a non-null one of the same class is refused (`string` is accepted), so
  `LinterNullCheckPolicy`'s rows narrowed first (fixed and collapsed 2026-09-27 on `census/chip-fixes`:
  a reference `?` no longer decides the equality). `TryExtractCompletionPrefix` lost its two unread
  parameters (its one caller is the facade's `CompletionEngine`), and the `CodeFixProvider` family names
  the arguments it does not read with a leading underscore;
- the product (100 files) AND its estate (66) as pure renames, with `excludeTests: true` and its own
  estate project in dev.sh, Step 3a, reseed step 8 and both CI workflows (Syntax 1,376 + Core 7,238 +
  Tooling 353 + Driver 708 -> Syntax 1,376 + Core 6,106 + CodeIntel 1,132 + Tooling 353 + Driver 708:
  9,675/9,675);
- the SDK packs `tools/NSharpLang.Compiler.CodeIntel.dll` and names it in the emit target's `Inputs` and
  the emit-only switch; reseed.sh cleans and estate-runs it; `SdkEmitStampPaths` walks Driver -> Tooling
  -> CodeIntel -> Core; `CompilerSliceAssemblyNames` names it; packages.sh packs it between Core and
  Tooling (release set, verify-release.py and its test);
- 43 `dll:` consumers, the NL924 boundary probe's closure and the facade-interop consumer take
  `NSharpLang.Compiler.CodeIntel.dll`; five assembly-qualified names of CodeIntel types (`Linter`,
  `LinterConfig`, `ProjectSnapshot` twice, `DocQuery`, `DiagnosticResult`) say
  `NSharpLang.Compiler.CodeIntel`;
- Step 2d checks CodeIntel (0) between Core and Tooling; the slice-direction guard counts CodeIntel's
  product and estate in its own project;
- the committed seed does not name CodeIntel in its emit-only switch, so until the next republish it
  compiles CodeIntel WITH analysis, product and rows; its zero front door is what lets that analysis
  pass. Carving turned one call into a referenced-assembly call that the columnar emitter -- the
  seed's and the tip's -- declines: a static call taking a `cond ? null : value` argument
  (`emit.call.static-member-unmodeled`, `ImportEditPlanner.IsNamespaceInScope`; a source callee takes
  it). The argument was bound to a local with a `// COMPILER:` note until the emitter modelled it
  (fixed 2026-09-27 on `census/chip-fixes`, and collapsed once the seed carried the fix).
Measured edit -> test (`./scripts/dev.sh --estate UnifiedDiffTests`, a one-line body edit of
`UnifiedDiff.nl` and its revert, after a warm run, with another session's gate on the box):
**185 / 191 s** on the pre-carve tree and the committed seed (`b75070d46`) -- Core's own and
tests-included emits -- **58 / 52 s** on the carve and that same committed seed (which compiles
CodeIntel WITH analysis), and **38 / 37 s** on a scratch stage-2 seed packed from the carve. A CodeIntel
body edit re-emits only CodeIntel and what sits above it (Tooling and Driver product-only for the CLI,
CodeIntel tests-included for its rows); Syntax, Core, Tooling and Driver answer "no row matches" in
seconds.

**Compiler.Emit is carved** (2026-09-25, `census/carve-emit`), TOP-DOWN like CodeIntel: `Backend.Emit/`
-- `ColumnarIlEmitter` and the IL realizations (entry point, iterators, events, argument opcodes,
friend declarations) -- becomes `src/NSharpLang.Compiler.Emit` (assembly `NSharpLang.Compiler.Emit`;
a backend slice's project drops its `Backend.` prefix, which the slice-direction guard's
`SliceProjectName` spells), a project ABOVE Core and below CodeIntel. Emit takes Core with
`project:` and declares the packages its own source spells (`YamlDotNet`, `Mono.Cecil` for its Cecil
admission row, and `NSharpLang.Runtime` for the SIMD helpers' `nameof`s -- `Sdk.props` leaves Emit,
like Core, out of the implicit runtime reference, or MSBuild would see the NU1504 pair); CodeIntel
takes Emit, so the chain stays linear (Driver -> Tooling -> CodeIntel -> Emit -> Core), although only
Driver's `MultiFileCompiler` names an Emit type -- the chain edge the split plan gives S5 -> S4. The
top-down measurement found NO product reach into Emit from Plan or Semantics, but the estate was
entangled both ways, and every edge was cut in Core first:
- 29 reaches from Core's rows into Emit (the estate upward-reach ceiling fell 141 -> 112): rows that
  emit a whole program or drive a private emitter step moved beside their Emit subjects --
  `ColumnarFreeFunctionScope.tests.nl` whole (8 of its 10 rows emit and read the metadata back),
  the 12 emitting source-attribute rows into `ColumnarSourceAttributeEmission.tests.nl`, the
  field-initializer, constructor-chain (`EmitChainedConstructorCall` by reflection) and Cecil
  writable-property rows into `ColumnarIlEmitter.tests.nl`, the argument-opcode row into
  `ColumnarArgumentInstructionEmitter.tests.nl`, the friend-declaration row into
  `ColumnarInternalsVisibleToEmitter.tests.nl`, and the constructor decline-trace row beside the
  emitted hostile `IReadOnlyList<T>` it drives the planner with (`ColumnarMemberIteratorRealization`);
  the Cecil/MSBuild admission rows that never reached the emitter moved DOWN (the whole
  `ColumnarSdkCecilBindingPrerequisite.tests.nl` into `Backend.Plan/`, where its catch-sequence
  sibling already read its `Smc*` helpers); the generic-call row reads a captured error's runtime
  type itself;
- 211 reaches from Emit's rows into Backend.Plan's and Model's estate helpers (`TypeOfCreateBuilder`,
  `ExecutorRequiredMethod`, `ColumnarIteratorShapeProbe`, `SemanticTypeResolution` ...), which a
  tests-included Emit build cannot see: it references Core PRODUCT-ONLY. Emit's rows now share their
  own `ColumnarEmitFixtures.tests.nl` (`EmitFixture*`), spelling the Reflection.Emit calls directly
  where the planner helpers still go through reflection invocation (a relic of older emitter gaps),
  and copying only the one fixture with real logic, the iterator-shape probe. Estate helpers are
  per-assembly now, so a fixture two slices' rows need exists once per slice.
What the carve is:
- Emit's front door fixed in Core FIRST (Core 1,029 -> 771: zero additions, 258 removals -- 251 of
  Emit's own 252, 248 of them in `ColumnarIlEmitter.nl`, the 252nd staying with the Cecil rows that
  moved down, and the seven NL905s of the moved source-attribute rows), so it starts at 0. Carving
  added ~100 cross-assembly diagnostics on top, all analyzer or emitter gaps, routed around with
  `// COMPILER:` notes: an `out` argument to a REFERENCED N# method is checked as if it
  flowed in (a `T?` local passed to `out value: T` is NL202, and three overload sets became NL402), so
  such locals are declared with the parameter's own type; a `for` step is not narrowed by its
  condition, so base-chain walks step with `?.`; `nameof(JsonElement.ArrayEnumerator.Current)` is
  NL303, so those names are literals; and the columnar emitter (seed's and tip's) declines a
  referenced static call whose argument is another referenced static call over an implicit-`this`
  call (`AnalyzerVariableDeclaration.IsErrorCaptureForm`), or over a `must` operand
  (`MakeGenericType([must t])`, `Bind((must p).Getter)`), so those operands are narrowed or bound to
  locals first. All four are FIXED in the compiler (branch `fix/emit-carve-compiler-gaps`, below); the
  analysis route-arounds collapsed with their fixes, because the committed seed compiles Emit
  emit-only, and gap 4's local waits on the next seed republish, because the seed's emitter predates it; Two Plan signatures now say what they accept (`TryValidateGenericSiblingConstraints`'s
  `baseConstraints: Type?[]`, `ColumnarLocalFunctionClosurePlanner.Plan`'s nullable local-function
  list);
- the product (6 files) AND its estate (13) as pure renames, with `excludeTests: true` and its own
  estate project in dev.sh, Step 3a, reseed step 8 and both CI workflows (Syntax 1,376 + Core 6,106 +
  CodeIntel 1,132 + Tooling 353 + Driver 708 -> Syntax 1,376 + Core 6,049 + Emit 57 + CodeIntel 1,132
  + Tooling 353 + Driver 708: 9,675/9,675);
- the SDK packs `tools/NSharpLang.Compiler.Emit.dll` and names it in the emit target's `Inputs` and
  the emit-only switch; reseed.sh cleans and estate-runs it; `SdkEmitStampPaths` walks Driver ->
  Tooling -> CodeIntel -> Emit -> Core; `CompilerSliceAssemblyNames` names it; packages.sh packs it
  between Core and CodeIntel (release set, verify-release.py and its test);
- 43 `dll:` consumers, the NL924 boundary probe's closure, the facade-interop consumer, the shipped
  payload and the SDK feed inputs take `NSharpLang.Compiler.Emit.dll`; the one assembly-qualified name
  of an Emit type (`ColumnarIlEmitterOwnership`'s `ColumnarIlEmitter`) says `NSharpLang.Compiler.Emit`;
- Step 2d checks Emit (0) between Core and CodeIntel; the slice-direction guard counts Emit's product
  and estate in its own project;
- the committed seed does not name Emit in its emit-only switch, so until the next republish it
  compiles Emit WITH analysis, product and rows (and warns NU1504 for the runtime pair its older
  `Sdk.props` still adds); Emit's zero front door is what lets that analysis pass.
Measured edit -> test (`./scripts/dev.sh --estate ColumnarLambdaStatementBodyTests`, a one-line body
edit of `ColumnarIlEmitter.nl` and its revert, after a warm run, with other sessions' builds on the box
(load average 8-10)): **257 / 235 s** on the pre-carve tree and the committed seed (`fde28e9e6`) --
Core's own and tests-included emits -- **295 / 262 s** on the carve and that same committed seed
(which compiles Emit WITH analysis: its emit-only switch predates Emit, and the analyzer walks the
31k-line emitter every time), and **94 / 99 s** on a scratch stage-2 seed packed from the carve. An
Emit body edit re-emits Emit and what sits above it (CodeIntel, Tooling, Driver and the facade
product-only for the CLI, 38 s of the cycle, Emit tests-included for its rows); Syntax and Core answer
"no row matches" without re-emitting. CORRECTED by `census/slice-cycle`: R1-R3 were in place, and the
binlog shows CodeIntel, Tooling and Driver SKIPPING their emit with Emit's reference assembly unchanged.
The 94 s was dev.sh building the CLI (Emit re-emitted product-only) before the estate re-emitted it
tests-included, visiting all six estate projects, a columnar parse that was O(declarations x file
tokens), and type-name misses asked of every reference; with those fixed the same cycle is **7 / 8 s**
(`memory/testing.md` section 7a).

**Compiler.Plan is carved** (2026-09-27, `census/carve-plan`), TOP-DOWN like Emit: `Backend.Plan/` --
the columnar planners and resolvers, the binding scope, the code-plan executor and the metadata-blob
writers -- becomes `src/NSharpLang.Compiler.Plan` (assembly `NSharpLang.Compiler.Plan`), a project ABOVE
Core and below Emit. Plan takes Core with `project:` and declares the packages its own source spells
(`System.Reflection.MetadataLoadContext`, `YamlDotNet`, `Mono.Cecil`, `Microsoft.Build.Framework` and
`Microsoft.Build.Utilities.Core` for the SDK-task admission tables and their rows, and
`NSharpLang.Runtime` -- `Sdk.props` leaves Plan, like Core and Emit, out of the implicit runtime
reference); Emit takes Plan instead of Core, so the chain stays linear (Driver -> Tooling -> CodeIntel ->
Emit -> Plan -> Core). Core keeps its name and its project (user decision D-B): it now holds Semantics
(product and rows) and Model's estate, and the compile-time bench keeps measuring it.
The top-down measurement found NO product reach into Plan from Semantics, Model or Syntax: the one
violation the split design named (`ConstantConversionFacts` -> `ColumnarScalarLiteralPlanner`) was
already gone -- `b60557d97` moved the integer-literal parser into Model's `NumericLiteralFacts` -- and
no assembly-qualified string names a Plan type in Core. The estate was entangled both ways, and every
edge was cut in Core first:
- 61 reaches from Core's rows into Plan (the estate upward-reach ceiling fell 112 -> 51): rows whose
  subject is a planner type moved beside it, whole -- the prepared external type catalog
  (`ExternalAssemblyScan`) and the columnar void-gap agreement (`AnalyzerTypeReferenceFacts`) into a
  new `ColumnarBindingScopeFacts.tests.nl`, the numeric-limit agreement into
  `ColumnarExternalBindingPlans.tests.nl`, the inherited-member relation the planner asks too
  (`MemberAccessibility`) into a new `ColumnarRuntimeInstanceMemberResolver.tests.nl`, the two
  unreadable-host extension rows (`AnalyzerReflectionMemberProbe`) into
  `ColumnarExtensionMethodResolver.tests.nl`, and the generic index's nullability rows
  (`NullabilityGenericSubstitution`) into `ColumnarSemanticTypeRegistry.tests.nl`, each with lookups of
  its own; Core's rows that borrowed the planner rows' Reflection.Emit helpers (`TypeOfCreateBuilder`,
  `ExecutorRequiredMethod`, `TypeOfRequiredInvocation`, `ColumnarConstructionPlanner.SameObject`, a probe
  enum) spell the calls directly or through Core's own `Model/CoreEstateFixtures.tests.nl`
  (`CoreFixture*`), and the metadata-signature row reads `SoaColumnDeclaration`'s constructor instead of
  a planner input's;
- 62 reaches from Plan's rows into Model's estate helpers (`IdentityBake`, `NullabilityProbeSequenceCount`),
  which a tests-included Plan build cannot see: Plan's rows share their own
  `ColumnarPlanFixtures.tests.nl` (`PlanFixture*`), spelling `TypeBuilder.CreateType` directly.
What the carve is:
- Plan's front door fixed in Core FIRST (Core 766 -> 377: zero additions, 389 removals -- NL002 186,
  NL202 66, NL905 63, NL010 46, NL012 12, NL011 7, NL907 7, NL001 1, NL304 1; 74 in its product, 315
  in its estate), so it starts at 0. Checked as its own project against built Core it STAYS 0 -- unlike
  Emit's, Plan's carve found no cross-assembly analyzer gap. Three gaps the fixes met are routed around
  with `// COMPILER:` notes: `==` between a class and its `?` annotation is refused (NL202; the
  analyzer's reference-equality tail does not see through a reference `?`), so identity tests said
  `Object.ReferenceEquals` (fixed and collapsed back to `==`/`!=` 2026-09-27 on `census/chip-fixes`);
  still open: out locals are declared with the parameter's own type (the Emit
  carve's rule); and a `ref` parameter that starts its own line of a wrapped parameter list does not
  parse (NL107), so that signature is one line;
- the product (120 files) AND its estate (137) as pure renames, with `excludeTests: true` and its own
  estate project in dev.sh (and its estate-only project selection), Step 3a, reseed step 8 and both CI
  workflows (Syntax 1,383 + Core 6,104 + Emit 57 + CodeIntel 1,133 + Tooling 353 + Driver 711 ->
  Syntax 1,383 + Core 4,287 + Plan 1,817 + Emit 57 + CodeIntel 1,133 + Tooling 353 + Driver 711);
- the SDK packs `tools/NSharpLang.Compiler.Plan.dll` and names it in the emit target's `Inputs` and the
  emit-only switch; reseed.sh cleans and estate-runs it; `SdkEmitStampPaths` walks Driver -> ... -> Emit
  -> Plan -> Core; `CompilerSliceAssemblyNames` names it; packages.sh packs it between Core and Emit
  (release set, verify-release.py and its test);
- 43 `dll:` consumers, the NL924 boundary probe's closure, the facade-interop consumer, the shipped
  payload and the SDK feed inputs take `NSharpLang.Compiler.Plan.dll`; the assembly-qualified names of
  Plan types (`ColumnarDeclineTrace`, `ColumnarProgramInputBuilder`, the bootstrap input types the
  emitter-ownership and iterator-ordering rows reflect over) say `NSharpLang.Compiler.Plan`, and
  `ColumnarIlEmitterOwnership` pins the emitter to the Emit assembly referencing the Plan assembly whose
  `ColumnarProgramInput` it takes;
- Step 2d checks Plan (0) between Core and Emit; the slice-direction guard counts Plan's product and
  estate in its own project;
- the committed seed does not name Plan in its emit-only switch, so until the next republish it
  compiles Plan WITH analysis (and warns NU1504 for the runtime pair its older `Sdk.props` still adds);
  Plan's zero front door is what lets that analysis pass.
Measured edit -> test (`memory/testing.md` section 7a's command: `./scripts/dev.sh --estate <Rows>` after
a warm run, a one-line body edit and its revert, private `NUGET_PACKAGES`, other sessions' gates queued
on the box): a Plan file (`ColumnarTypeOfPlanner.nl` / `ColumnarTypeOfPlannerTests`) **37 / 36 s** on the
pre-carve tree and the committed seed (`efee4818f`, load ~6) -> **16 / 17 s** on the carve and a scratch
stage-2 seed packed from it (load ~4.3); a Core file (`Semantics/AnalyzerDeclarationContext.nl` /
`AnalyzerDeclarationContextTests`) **36 / 36 s** -> **28 / 32 s** (load 5.5-8). Each cycle is one
tests-included emit of the edited slice: `EmitIlAssembly` (`-clp:PerformanceSummary`, load ~7) takes
**18.2 s** for Plan tests-included and **8.8-11.2 s** product-only (the split design predicted ~30 s),
and **24.9 s** for Core tests-included (~55 s before the carve) and **9.3 s** product-only. Plan is
still the largest remaining slice (120 product files, 137 estate files); the sub-split the design names
(`Plan.Call` / `.Type` / `.Body`) is not done here.

**The Emit carve's four compiler gaps are fixed** (2026-09-28, `fix/emit-carve-compiler-gaps`, on
`origin/systems-language` f235eae4e), each where it is owned and each held to "one project and two projects
answer alike" (`tests/native/census-external-nullability`, `census-external-operands`):
- `out`/`ref`/`in` to a REFERENCED method (Semantics + Plan): the reflection binder reads the WRITTEN
  modifier's direction for the maybe-null question -- `out` flows out only (never refused), `ref` must
  match both ways (reported as the `&T` pair a source call reports), everything else flows in. A
  reflected read-only reference binds as source does: `in` takes a bare or `in` argument,
  `ref readonly` (`[In]` + `RequiresLocationAttribute`, e.g. .NET 10's `Volatile.Read`) takes `ref`
  or `in`, never a bare value (`Volatile.Read(value)` stays NL402); `ReflectedParameterDirection`
  (Model) is the one reader of that, used by the binder,
  `ColumnarOrdinaryRuntimeDirectCallResolver.ReflectedModifierKinds` (5 `in`, 6 `ref readonly`) and the
  direct-call planner's by-ref gate. Before this a referenced `in` parameter was NL402 and, once bound,
  every reflected `in` scored as `ref` in the planner.
- a `for` update (Semantics + Emit + Plan): analysed AFTER the body (C#'s order) with the loop closed,
  under the condition-true facts minus every path the body can write (a `continue` before the write
  reaches the update with the write still ahead) -- `AnalyzerLoopSequence.SurvivingBodyNarrowings`; the
  emitter pushes the same names for the increment (`ForStepNarrowedNames`), so a `Nullable<T>` the
  condition proved reads as its `T` there too. Loop bodies now receive the same true facts; writes
  kill them after their statement's reads, nested blocks carry kills out, and `if` branches merge only
  facts shared by reachable exits (including guard branches that `continue`). The emit-side kill set
  (`CollectAssignedNames`) counts `ref`/`out` arguments and deconstruction targets, as the analyzer's
  always did. Runtime coverage is in `tests/native/census-flow-rules/LoopBodyNarrowing`; focused Plan
  and Emit rows pin the facts and emitted behavior.
- a nested type of a REFLECTED owner (Semantics): `ResolveMember`'s reflection arm answers a nested type
  in static position, as its source arm always did, so `JsonElement.ArrayEnumerator` resolves through
  the imported spelling, not only the namespace-qualified one.
- a referenced static call typed as an argument (Emit): `TryGetPreflightRuntimeStaticCallType` is the
  preflight twin of the contextual and ordinary static tiers (the instance twin already existed), so a
  call the direct-call planner cannot type -- a `must` operand, a call over an operator at depth three --
  types as an argument exactly as it emits.
The referenced `in` rvalue follow-up is fixed (2026-09-28): a bare non-storage argument is converted to
the substituted element type, stored in a fresh emitter local, and passed by address for source and
referenced methods and constructors. `ColumnarByRefCallArgumentFacts.TryGetAddressableArgumentTarget`
is the shared syntactic storage predicate used by the planner and emitter; the emitter's declared-
argument preflight and emission both own temporary allocation. Unsupported explicit generic calls
remain with the emitter's ordinary referenced generic-call tier, which handles by-value and by-ref
signatures alike. Written `in` still requires storage, and written `in` at a by-value parameter is
rejected during analysis with the existing NL202/NL402 families.
The route-arounds: gaps 1-3's collapsed in the commits that fixed them (ten base-chain walks step with
`d.BaseDef`, the enumerator member names are `nameof`s, 34 of the carve's 88 retyped `out` locals are
`T?` again -- the other 54 are its front-door fixes, chosen by the tip's front door, and wait on the
`&&`/`||` out-write flow follow-up); the committed seed compiles Emit emit-only, so an analysis fix needs
no republish there. Gap 4's `lastDeclaredName` local is an EMITTER route-around and needs one:
`fix/emit-carve-compiler-gaps-collapse` inlines it, builds with a stage-1 SDK packed from this branch
(`NSHARP_RESEED_STOP_AFTER=pack` into scratch dirs), and the committed seed refuses it at NL103.

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

### Incrementality (within a project)
Two layers, both owned by `MultiFileCompiler` in Driver
(`memory/components/cli-toolchain.md`, "Incremental builds" and "Incremental analysis"):
- **The up-to-date stamp** (`IncrementalBuildStamp`, `IncrementalBuildInputCapture`): an unchanged
  compilation — same compiler identity, options, configuration, sources and every other file it
  consulted, by content — is answered from `obj/nlc/` without parsing, analysing or emitting. Opted
  into by the CLI's project and reference builds (`MultiFileCompiler.IncrementalBuild`).
- **Per-file analysis reuse** (`IncrementalCompilationState`, `IncrementalCompilationPlan`,
  `IncrementalFileSummary`, `IncrementalProjectSession`): a warm caller keeps the analyzer and each
  file's analysis; a file is re-analysed only when its text, or the surface of a file in its
  name-based dependency closure, changed. Parsing, import cycles, the systems policy, lint and
  the IL walk still run whole-project; the back end keeps each file's columnar parse while its text
  holds and answers an unchanged compilation's emission from the last one
  (`ColumnarFileProgramCache`, `IncrementalCompilationState.LastEmissionKey`; why the walk itself is
  not per-function incremental is in `memory/components/cli-toolchain.md`). Cold processes rebuild
  everything after an edit, because the systems policy and the emitter consume every file's
  semantic model.
- **Observing it:** `MultiFileCompiler.WasUpToDate`, `IncrementalCompilationState.LastFilesAnalyzed`
  / `LastFilesReused`; the work counters themselves belong to `CompilerWorkCounters` (`--stats`).
- **Who holds the per-file state:** the workspace server (`WarmIncrementalSessions`, registered with
  `WarmStateRegistry`), one session per compilation identity, for the commands it runs for clients.

### The agent-loop speed program: one owner per concern (`speed/integration`, `320cd5f92`, 2026-10-05)

Five branches made the edit -> check -> build -> test loop faster (agent-loop benchmark and work
counters, incremental compilation, the workspace server, compiler throughput, the NativeAOT front
door). Where two of them built the same thing, ONE owner was kept:

| Concern | Owner | Why it won | What went |
|---|---|---|---|
| Work counters vs phase timings | ONE `--stats` line (`nsharp.cli-stats` v1): `counters` from `CompilerWorkCounters` (always on, exact, the agent-loop gate's subject) plus an optional `phases` array from `CompilerPhaseTimings` (wall/CPU/alloc per project and phase, the rows `--timings` prints) | The two answer different questions -- "how much work" is gateable under load, "where did the time go" is not -- so both stay, behind one output. `phases` is an added optional field, compatible under v1's own rule | incremental's interim `CompilerStats`/`NSHARP_STATS` (dropped on its branch); the server resets the phase ledger per request |
| Type-name misses | `AssemblyTypeNameIndex` (Model) | Throughput's API (`GetTypeOrNull`, `MayDeclareTopLevelType`, `PlainTopLevelTypeName`) is wired into every probe site (analyzer, qualified resolver, declaration context, catalog entries); the daemon's per-FILE-VERSION table cache and its `WarmStateRegistry` entry were folded into it, so a long-lived process reads each reference's tables once per file version, not once per load context | daemon's `ExternalTypeNameIndex` and its double check in `ExternalQualifiedTypeResolver` |
| Parse reuse | One parse per file per compilation: the driver's parse (unit + errors) seeds every analyzer's project source provider (`Analyzer.SeedProjectParses`), which serves cross-file lookup AND file imports (`TryGetProjectParse`); an incremental record keeps its parse so a reused file seeds too | Throughput's seeding saved a whole project parse per analyzer (per worker); incremental's import reuse saved re-parsing imported files; seeding into the provider's parse cache gives both from one cache | throughput's unit-only `SeedCompilationUnits` (it bypassed the import cache) |
| Order-independence of shared declarations | A body's nullable-return provenance lives per analysis in `AnalyzerFunctionTypeFactory` (cleared per `Analyze`) | Once declarations are shared, the AST field `FunctionDeclaration.ReferencedNullabilityReturnType` leaked to other files' call sites depending on analysis order (and, in parallel, timing); the per-analysis table is exactly the old unshared semantics | the AST field |
| Reference reuse | incremental's `ExternalAssemblyScan.OwnedAssemblyLoadedFrom` (the process-wide exact-identity context answers a second request for the same path/identity) | Distinct from throughput's in-compilation indexes; nothing overlapped | -- |
| Warm state | The daemon's `WarmStateRegistry` holds `AssemblyTypeNameIndex` (`reference-type-names`) and `WarmIncrementalSessions` (`incremental-compilations`); routed `check`/`build` attach the session's `IncrementalCompilationState` | That is what makes a warm body edit re-analyse one file | -- |
| Parallel analysis vs incremental reuse | Reused files skip the workers; only the rest are queued; workers replay every earlier file's import loads, reused included. The shared analyzer stays LAZY (a stamp-answered build loads no reference) and may be the state's retained one | Composes both; no eager reference load on a no-op | throughput's eager `_sharedAnalyzer` in the constructor |
| Reference metadata (`speed/agent-loop-2`) | ONE `MetadataLoadContext` per compilation (`SharedReferenceMetadata`, Model): the shared analyzer opens it, parallel workers attach, the IL back end's external scan reads it when every file it wants is already loaded from that path; one gate serialises loads, resolver probes and table writes | The analyzer, each worker and the emitter each read the same closure (large rows 151 images, small 501); the context is thread-safe by construction, the resolver's tables are not, hence the gate | per-worker contexts; the scan's private context when the analysis already holds its files |
| Nested parallelism | A workspace `nlc check` (members already concurrent) analyses each member, and each project reference built for it, on one worker (`ResolutionContext.CompilesConcurrently`) | Measured on the repository root: per-member fan-out opened 548 more reference images for no wall gain and broke the root-check row's per-member ratio | -- |
| `Cli.csproj` `TieredPGO=false` vs AOT/R2R | Kept as is | It reaches the IL host and the RID toolset's ReadyToRun host through `Cli.runtimeconfig.json` (R2R code still tiers up, straight to tier 1); the NativeAOT front door has no JIT. The front-door guard in `CliPipeline.Execute` runs FIRST, before daemon routing, as a lone constant test so ILC trims the compiler and daemon client | -- |
| Hermetic gates vs daemon | `dev.sh` and `test-all-core.sh` default `NLC_NO_DAEMON=1`; the agent-loop bench's `--daemon` mode clears it (and `NLC_DAEMON_CHILD`, `NLC_DAEMON`, `CI`) for its spawned commands, so the routed path is still what `--daemon` measures | -- | -- |

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
  `src/NSharpLang.Compiler.Emit/ColumnarIlEmitter.nl`; its C# owner is deleted.
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
  decide anything. Moving a file within a project no longer changes a byte (the module version id
  and timestamp are content hashes, and a whole-file comparison is the check); crossing a project
  boundary changes assembly ownership and is outside this guarantee.
  `tests/native/canonical-source-order` pins it: two layouts of one program emit identical
  implementation and reference assemblies, explicit lists in any order match discovery, a rename
  DOES move the bytes (the control), and every `src/` N# project keeps its basenames unique, which
  lets moves within one project remain byte-identical.
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
  required to achieve that ownership. A broader metadata-writer initiative remains separate from
  the compiler-only goal unless a concrete ownership dependency is demonstrated. NativeAOT now
  covers only the `nlc` FRONT DOOR (per-RID toolsets; see `memory/components/cli-toolchain.md`):
  the compiler stays a ReadyToRun JIT host because the emitter binds runtime types and loads
  references in-process.

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

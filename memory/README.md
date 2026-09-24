# N# Compiler and Toolset Documentation

**Status:** Active implementation notes. Current code and recent commits are authoritative; docs are useful
only when they match product-path behavior.

## Compiler Ownership Rule

The compiler-only ownership objective is complete at the verified `0cc84110` checkpoint;
final acceptance (`2026-09-09-compiler-only-ownership-complete.md`). Sole N# compiler behavior and canonical assertions remain required;
see [the execution contract](../tasks/README.md) and [current cursor](../systems-language-closeout/STATUS.md).
The complete Analyzer and SystemsAnalyzer are N#-owned in Compiler Core; both C# classes are
deleted and verified through installed SDK self-hosting. The complete ColumnarProgramInputBuilder
is also N#-owned, with its C# class deleted and canonical/package/self-host verification accepted.
The complete ColumnarIlEmitter is N#-owned and its C# class is deleted, with canonical, installed
SDK self-host and IDE verification accepted. Complete MultiFileCompiler ownership and its ten
recovery canonicals are accepted at `27b1a8a1b`, including installed SDK self-host and real unsaved
editor verification. Complete recursive compiler reference resolution is now N#-owned in the working
branch, with its C# class deleted and seven direct plus four command-level N# canonicals integrated;
its fresh gate and installed SDK verification are accepted at `a20dc98af`. The complete SDK task,
including reference-assembly scan/rewrite, is now N#-owned in `EmitIlAssembly.nl`; its C# class is
deleted and SDK routing is direct. Fresh integration and installed self-host verification pass at
`b13cc7622`; see SDK task acceptance (`2026-09-09-complete-sdk-emit-task-ownership.md`). Historical allowlist labels do not prove
current compiler-wide completion. CLI/editor features and broader branch work stay separately
recorded; SDK/tooling changes are in scope only as demonstrated compiler migration dependencies.
Do not preserve fallback emitters or expand `*DogfoodAdapter` layers into product architecture.

Compiler-service kernels are statically compiled through `NSharpLang.Compiler.Core`;
product paths must not use `Assembly.Load`/delegate reflection for N# compiler services. Because
Compiler Core is built by the pinned stage-0 SDK, any kernel that uses a tip-only language or
backend feature requires a local SDK repin with `./scripts/setup-local.sh` before it is a valid
kernel shape.

## Self-Host: the front door and the seed

Two different compilers touch `src/NSharpLang.Compiler.Core` and they do not see the same program.

**The seed compiles it without analysis.** Every build and every gate step compiles Core with the
PINNED stage-0 SDK in `bootstrap/`, through the SDK's emit-only path, which skips analysis and lint
entirely. **The tip compiler's front door (`nlc check` / `nlc build --project`) runs the whole
pipeline.** So the tip compiler can stop being able to compile the compiler's own source and nothing
in the gate notices. That is not hypothetical: four `while true { ... return ... }` loops in Core
carried a dead trailing `return` that the old seed accepted and the tip refuses
(`emit.statement.unreachable-after-transfer`, NL312), and it surfaced only during a hand republish of
the seed.

It has happened twice. The second time (2026-09-19, found by `./scripts/reseed.sh` at `9b4c46174`) it
was not the source: `compilationUnit.FileImports.OfType<FileImport>()` in `MultiFileCompiler.nl`
declined at `emit.call.generic-unresolved` because the wave-12 change that replaced the emitter's
hard-coded `Cast`/`OfType` table with the ordinary extension index matched the receiver against the
candidate's closed slot — and that slot is the NON-GENERIC `System.Collections.IEnumerable`, which
`ColumnarExtensionMethodResolver.ReferenceAssignableFrom` only asked the builder-bound owner about
for a CONSTRUCTED slot. A receiver whose element is a type the compilation is writing has no
reflectable interface list, so the relation answered `false`. The seed predated the change, so every
gate step stayed green; only the republish could see it. `tests/native/source-typed-explicit-generic-extension`
pins the shape.

**A SEED-HIDDEN DEFECT NEED NOT BE ABOUT COMPILING CORE AT ALL — it can be about what the compiled
assembly LOOKS LIKE.** The third and fourth (2026-09-19, at `f369e5d22`) were both in emitted
METADATA, and neither could fail a build the old seed produced. `[Required]`/`[Output]` on an
MSBuild task property had two writers, so every task property carried the attribute twice and
`Attribute.GetCustomAttribute` threw `AmbiguousMatchException`. Then
`ColumnarFreeFunctionHolders.ForFile` — which DEFINES the type it returns — was called eagerly for
every body the emitter ran, so every namespace that declared so much as one method got an empty
public `Program`: 11 in `NSharpLang.Compiler.Core`, 2 in `Compiler`, and `dotnet build
src/NSharpLang.Cli` then failed CS0433 on `NSharpLang.Cli.Commands.Program`. The rule the source
already stated — a holder exists "only once something is placed in it" — is now enforced by
`ColumnarFreeFunctionHolderSlot`, and `tests/native/census-free-function-identity` sweeps the
emitted assembly for empty holders. **So the republish is not green when step 8 passes: build every
C# consumer of the self-compiled assemblies (`Cli`, `Build.Tasks`, `LanguageServer`, `Playground`)
against the stage-2 seed before believing it.**

`Step 2d: Self-Host Front Door` in `tests/scripts/test-all-core.sh` closes that blind spot. It runs
`nlc check --json` over `src/NSharpLang.Compiler.Core`, `src/NSharpLang.Compiler`,
`src/NSharpLang.Playground` and `src/NSharpLang.Build.Tasks` with the CLI the gate just built and
fails on any INCREASE over the committed ceilings. **The ceilings are a backlog, not a target**: the
front door reports diagnostics on Core's own source that the emit-only path never asked about
(missing and unused imports, nullable arguments passed to non-nullable parameters, definite-assignment
holes, ambiguous simple names). They exist to be driven to zero and must never be raised. The step is
inside the validated step cache on the UNIT input set, so it runs only when the compiler's own
sources move.

**Measured 2026-09-14 after the wave-12 source repair** (`388a6b9e6`): Core reports
**1,342 diagnostics across 946 files** (1,329 errors and 13 warnings). Comparing diagnostic identities
(file, code, severity, message and source snippet) against the original 1,374-diagnostic baseline
finds **zero additions and 32 removals**. The gate ceiling is now 1,342. Explicit nullable contracts,
short opcode conversions, qualified reflection types and import cleanup removed the new source
regressions without suppressions or a ceiling increase.

**Measured 2026-09-20 at `e5ce20f39`** (the IVT2, signature-help and folding lanes): Core reports
**1,340 diagnostics across 952 files** (1,327 errors and 13 warnings), and **the gate ceiling is now
1,340**. Those three lanes had added **9** diagnostics to Core's own source — five unused imports
(`EditorFoldingFacts.nl` ×2 and its tests, `SignatureHelpOverloadFacts.nl`,
`ColumnarInternalsVisibleToEmitter.tests.nl`), two unread parameters on
`SignatureHelpOverloadFacts.ResolveTypeReceiver`, and an NL201/NL010 pair on
`ColumnarInternalsVisibleToEmitter.nl`. The imports and parameters were removed; the pair was a
CHECKER defect, not a source one. `System.Reflection.Emit.PersistedAssemblyBuilder` is the one
Reflection.Emit type `System.Private.CoreLib` does not declare — `AssemblyBuilder`, `TypeBuilder`,
`ModuleBuilder`, `EnumBuilder` and `ILGenerator` all resolved through the core entry — so it answered
NL201 on the compiler's own IL back end, and the `import` that supplies it was then NL010. Adding
`System.Reflection.Emit` to `ExternalAssemblyScan.CommonAssemblyNames` (32 names now, pinned in
`AnalyzerMetadataLoadPolicy.tests.nl`) resolves it and also cleared the pre-existing NL201 in
`ColumnarIlEmitter.nl`: zero additions and two removals against the 1,342 baseline.

**Measured 2026-09-22 at `5de55561b`** (the Compiler.Core compression campaign, PRs 1-4 of the Fable
audit, rebased onto the sixth seed): Core reports **1,318 diagnostics carried by 279 of the project's
files** (1,302 errors and 16 warnings), and **the gate ceiling is now 1,318**. The four PRs had ADDED
fourteen NL010s — deleting a duplicated function leaves the import that served it unused, and
`ColumnarCanonicalTypeResolver` and `ColumnarTypeOfPlanner` lost six and three imports' worth of work
between them when their builtin tables moved to `WellKnownTypeCatalog`. Removing those, plus the
twenty-two other unused imports already sitting in the same eighteen files, took the count from 1,340
to 1,318, so the ceiling came down the way `c751edd7e` brought it to 1,340. No other class moved.

**Measured 2026-09-23 at `d81168959`** (PRs 5-7 of the same campaign: the emit context, the loop
idiom sweep, the node-kind ledgers): Core reports **1,317 diagnostics carried by 279 of the project's
files**, and **the gate ceiling is now 1,317**. Measured with the tip CLI against BOTH trees the way
`c751edd7e` established -- the base source (`9ef0f5b32`) reports 1,318 through the same front door,
so the compiler changed no answer -- the diff over diagnostic identities is **zero additions and one
removal**: the NL905 on `initCtor` in `ColumnarIlEmitter.nl`. Its `initCtor.Body.SourceFileId` used
to be dereferenced twice, once for the file's sibling view and once for its holder slot, and
`ColumnarEmitContext.ForSourceFile` now derives both from one file id. NL905 424 -> 423; NL202 352,
NL002 239, NL010 165, NL012 38, NL011 30, NL304 28 all unmoved. A 2,500-line source reduction that
neither adds nor hides a front-door diagnostic is the result this step exists to be able to state.

**Measured 2026-09-23 at `3fc4585ea`** (PRs 8-10 of the same campaign: the accessor-to-property
sweep, the per-type families, the parser-kernel split): Core reports **1,314 diagnostics carried by
278 of the project's files**, and **the gate ceiling is now 1,314**. Measured with the tip CLI
against BOTH trees the way `c751edd7e` established -- the base source (`738996c29`) reports 1,317
through the same front door -- the diff over diagnostic identities is **zero additions and three
removals**. Two are NL905 in `ColumnarIlEmitter.nl`, on `bclInitializerSetterForOpcode` and
`bclMemberInitializerSetterForOpcode`. The source ALREADY guards `property.SetMethod == null`
immediately above each one; written `property.get_SetMethod() == null` that guard narrowed nothing,
because flow narrowing tracks a member read and cannot track a call that might answer differently
next time -- so the accessor idiom was manufacturing two false positives. The third is the NL002 on
the deleted `CompilerServices/ColumnarParserKernels.nl`, for a `List` used without the import that
provides it: the old file's four imports did not include `System.Collections.Generic`, and the split
gives each of the twelve new files the imports it actually uses. NL905 423 -> 421, NL002 239 -> 238;
NL202 352, NL010 165, NL012 38, NL011 30 and NL304 28 all unmoved.

**Measured 2026-09-24 at `ab1f732b8`** (the first step of carving `Compiler.Model` out of Core):
Core reports **1,291 diagnostics carried by 270 of the project's files**, and **the gate ceiling is
now 1,291**. Model's product files carried 23 of the 1,314, and they had to reach zero first: once
Model is its own project, `check` on Core builds it as a `project:` reference and a diagnostic there
BLOCKS Core's check instead of counting in it. Measured with the same tip CLI against both trees, the
identity diff is **zero additions and 23 removals**, all in Model product files: NL011 8 (each empty
catch now says what falling out of it did -- `return null`, `continue`, or a helper returning the
fallback), NL010 5, NL002 4, NL012 4 (`_`-named interface parameters) and NL905 2 (a `Try...` helper
answering null where a catch always left). NL202 352 and NL304 28 unmoved.

The original 819-file baseline took 19m20s on a loaded machine; the front-door check remains a costly
integration check. `src/NSharpLang.Build.Tasks` has no `.nl` sources yet, so its ceiling remains zero.

`src/NSharpLang.Compiler` and `src/NSharpLang.Playground` carry the ceiling **-1, meaning BLOCKED**.
`check` on a project builds its project references first, and that build fails while Core's own front
door is not clean — so both answer an `error` envelope rather than a diagnostic list and there is
nothing to count. The original SELFHOST measurement found zero diagnostics in their own `.nl` sources
through `--text`; that observation does not make their blocked project checks clean. When Core reaches
0 their ceilings become real numbers.

Since the block is structural, the step no longer STARTS those two checks while Core's own count in
the same run is a number above zero: each one spent a full front-end compile of all of Core (~2
minutes apiece, measured) to arrive at the BLOCKED line it is recorded with anyway. The row is
printed with the count that proves the block instead, and the guard stops firing on its own the day
Core reaches 0 — at which point both projects are checked for real. Pinned by
`tests/native/gate-script-contracts/SelfHostFrontDoor.tests.nl`.

The remaining backlog, measured at `5de55561b`, is NL905 (424 possible null dereferences), NL202 (352
argument type mismatches), NL002 (239 missing imports), NL010 (165 unused imports), and 96
NL012/NL011/NL304 findings (unused parameters, empty catches and definite-assignment holes), with 42
NL907/NL001/NL209/NL303/NL301/NL402 behind them. The source cleanup campaign remains
open; a successful seed build through the emit-only path does not prove that this front door is clean.

### Republishing the seed

`./scripts/reseed.sh` is the runbook, and every step of it exists because skipping it produced a seed
that could not rebuild itself:

1. pack the SDK and runtime with the CURRENT seed
2. install them into `bootstrap/` and re-pin `SHA256SUMS`
3. evict `nsharplang.sdk` and `nsharplang.runtime` from the NuGet cache — a republished seed keeps its
   version, so the cache serves the OLD bytes forever and the rebuild proves nothing
4. `scripts/verify-bootstrap.py`
5. clean self-rebuild of Core (`obj` must go: `project.assets.json` pins the resolved SDK path); each
   restore hashes the exact lowercased SDK/runtime cache packages against the verified bootstrap bytes
   before its build can start
6. **pack AGAIN** — these are the packages a compiler COMPILED BY ITSELF produces, and they are the
   ones that get committed. A one-stage seed cannot carry a change to the MSBuild task surface,
   because stage 1's tasks were built by the OLD SDK
7. install stage 2, evict, verify, clean self-rebuild again
8. the compiler-service estate

`NSHARP_RESEED_BOOTSTRAP_DIR`, `NSHARP_RESEED_PACKAGES_DIR` and `NSHARP_RESEED_STAGE_ROOT` point the
run at a scratch seed and a scratch package cache, and `NSHARP_RESEED_STOP_AFTER=<step>` stops after
one; that is how the runbook is exercised without touching the committed seed.
`scripts/verify-bootstrap.py` honours `NSHARP_BOOTSTRAP_DIR` for the same reason. Commit the
`.nupkg` files and `SHA256SUMS` together, never separately.

## Quick Lookup

| Question | Read |
|----------|------|
| Understand current architecture? | [architecture.md](architecture.md) |
| Work on CLI/tooling behavior? | [components/cli-toolchain.md](components/cli-toolchain.md) |
| Run tests and gates? | [testing.md](testing.md) |
| Check known limitations? | [limitations.md](limitations.md) |
| Work on language features? | Current source, recent commits, tests, and focused website docs |
| Work on Systems N#? | Current source, recent commits, tests, and [../website/docs/systems.md](../website/docs/systems.md) |

## Components

| Component | File | Key Topics |
|-----------|------|------------|
| Lexer | [components/lexer.md](components/lexer.md) | Tokenization, strings, operators |
| Parser | [components/parser.md](components/parser.md) | AST construction, precedence, patterns |
| Analyzer | [components/analyzer.md](components/analyzer.md) | Types, scopes, semantic checking |
| CLI Toolchain | [components/cli-toolchain.md](components/cli-toolchain.md) | `check`, `fix`, `query`, daemon, completions, JSON schemas |
| Error Reporting | [components/error-reporting.md](components/error-reporting.md) | Error codes, formatting, suggestions |

## Testing

Read [testing.md](testing.md). Do not hard-code test totals; use fresh command output or dated evidence
from the relevant test run.

## Related Documentation

- [../README.md](../README.md) - repository overview and setup
- [../docs/README.md](../docs/README.md) - user-facing and design documentation map
- [../website/docs/](../website/docs/) - published documentation source

## Deleted Stale Docs

The old self-host progress log, dogfood rewrite plan, benchmark summary, columnar roadmap, SoA gate,
performance refactor plan, cross-language systems benchmark roadmap, implementation audit, and parity
audit docs were removed because they repeatedly instructed agents to route through N# while preserving
legacy compiler ownership or optimizing proof artifacts instead of deleting old owners. Do not
recreate those files as history archives; use current code, recent commits, and tests instead.

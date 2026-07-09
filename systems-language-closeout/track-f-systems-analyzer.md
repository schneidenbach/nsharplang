# Track F — Systems policy analyzer re-host (NSYS001–NSYS180)

> **LIVE STATUS (audited at `fb856ee46`):** not started; static-binding prerequisites are now
> satisfied. Redesign F2 before implementation: call facts require caller node ids and resolved
> declaration/function ids with overload, local-function, and generic-instantiation identity.
> File/name/line/column tuples are lossy. C# may flatten already-resolved BindingMap/SemanticModel
> facts but may not reimplement callee resolution. Parser input work contends on the consolidated
> `CompilerServices/ColumnarParserKernels.nl`. See [STATUS.md](STATUS.md).

**Owner model:** F1 attribute/modifier input prework is a swing slice after the current parser
writer releases the consolidated kernel file. F2–F4 wait for—or jointly land with C/D—the
canonical source-qualified SymbolId/TypeId/FunctionId contract. Static binding is already
complete. One owner should carry F2–F4 across the differential harness and deletion.

## Mission & end state

Re-host `src/NSharpLang.Compiler/Performance/SystemsAnalyzer.cs` (2,390 LOC — the only file in
`Performance/`) as an N# kernel, then delete it. SystemsAnalyzer is the systems-profile
policy/effect analyzer emitting the 19 NSYS diagnostic codes (NSYS001–NSYS180). Today it is
hard-bound to the C# object AST (`NSharpLang.Compiler.Ast` walkers over
CompilationUnit/FunctionDeclaration/Statement/Expression) and to the C# `SemanticModel` for
call-site→declaration resolution — one of the consumers keeping the C# front-end alive.

End state:

- All 19 NSYS codes produced by `SystemsPolicyKernels.nl` in BootstrapServices, computing over
  columnar node tables + flat fact arrays. **No kernel input is a C# AST or SemanticModel type.**
- The SemanticModel coupling is **disconnected first**, not last: a producer stage mechanically
  flattens call-resolution facts already decided by the legacy resolver into flat arrays; it
  performs no lookup, matching, filtering, or selection, and the kernel consumes only the
  arrays. When Track D's columnar binder lands, the producer is swapped without touching kernel
  logic.
- `SystemsAnalyzer.cs` deleted; `Performance/` empty/removed; perf-report JSON contract
  byte-stable throughout (goldens are the versioned contract, `SystemsReport.SchemaVersion`).

Track-critical campaign rules restated (full set in [README.md](README.md)): replace-then-delete
with differential evidence; stage = one commit with an `Evidence:` line; verify-first against the
real pipeline; no new C# product logic, including in the marked fact producer, which may only
flatten already-resolved identities mechanically; no route-back-into-C#
(no delegates into kernels); kernel shape limits until Track E lifts them (no bare `this`, no
`GetType()` on typed receivers, no generic user types, modeled BCL surface only); stage only your
own files; behavioral probes via fresh `dotnet build src/NSharpLang.Cli/Cli.csproj` + `Cli.dll`,
never the stale installed `~/.nsharp/bin/nlc`.

## Why this is its own track (and why NOT part of Track D)

- **Different walker, different diagnostics family.** SystemsAnalyzer is an effect/policy walker
  (allocation, resource, hot-path, boundary policy) over function bodies — structurally unlike
  Track D's `Analyzer.cs` semantic binder (types, conversions, member resolution). Bundling it
  into [track-d-semantics.md](track-d-semantics.md) would delay Track D's analyzer spine for
  zero shared context.
- **Self-contained oracle and mostly isolated domain.** SystemsNSharpTests plus the
  systems-gauntlet goldens run the real pipeline; the touched files are SystemsAnalyzer,
  SystemsPolicy inputs/kernels, ColumnarInputs, one MultiFileCompiler seam, and the contended
  consolidated parser kernel for F1.
- **F1 needs only static binding; F2+ needs canonical identity.** The heavy policy kernel lives in
  statically-referenced BootstrapServices, but resolved call facts must use C/D's shared semantic
  ids. F may begin input-column work independently; it may not invent an F-only identity or
  duplicate resolution while waiting for D.

## Current state (verified 2026-07-02, commit 9538ab66)

All line anchors below were verified on that commit; re-verify anchors before porting if the file
has moved under you.

### SystemsAnalyzer.cs member map (the port inventory)

- **Entry:** `Analyze` (L48–104) — takes `IReadOnlyDictionary<string, CompilationUnit>`,
  `PerformanceFactStore`, `IReadOnlyDictionary<string, SemanticModel>`; assembles the report,
  orders findings, aggregates the summary. Mode gates `IsSystemsProfile`/`EffectiveMode`/
  `IsAuditMode` (L106–108) read `_config.Language.Profile` and `_config.Language.Systems.Mode`
  (project.yml nests these under `language.systems.{mode,aotTarget,stackBudgetBytes}`).
- **Registration:** `RegisterDeclarations` (L110–159), `RegisterMemberType` (L160–167),
  `RegisterFunction` (L168–186) — builds `_structTypes`/`_refStructTypes`/`_enumTypes`/
  `_typeAliases`/`_memberTypeNames` and the `FunctionEntry` list.
- **Per-function summaries:** `AnalyzeFunction` (L187–318) — memoized recursion via
  `_summaryCache` keyed by `FunctionDeclaration` reference identity plus a visiting set
  (recursion guard). Attribute reads at L195–199: `new AttributeSet(function.Attributes)`,
  `IsHot = attributes.Has("hot")`, `IsBoundary = attributes.Has("boundary")`; `[allow(...)]`
  args via `attributes.GetAll("allow")` (L344) with matching rule `AttributeNameEquals` (L2191).
  `AttributeSet` nested type around L2180+.
- **Check methods → NSYS codes:** `CheckRefLikeFields` (L319; NSYS080 at L329),
  `ValidateFunctionLevelAllows` (L342; NSYS150/180 near L351), `CheckFunctionSurface` (L382;
  NSYS070 at L392, NSYS160/170 at L424), `CheckIgnoredResult` (L445; NSYS130 near L476),
  `CheckPoolBalance` (L468; "pool" policy L477), `CheckResourceBalance` (L488; NSYS090 near
  L496), `AddTypeFinding` (L508). Also: NSYS001 strict-profile alloc marker at L1377; NSYS010
  hot heap alloc at L222; NSYS100 near L291; NSYS060 near L81; NSYS120 conservatism at
  L1426–1477 and emission also at L654.
- **Effect walker:** `WalkStatement` (L536–717; NSYS090 hot-async/resource findings at L622 and
  L673), `WalkExpression` (L946–1140; NSYS090 await at L1066), `WalkCall` (L1141–1263; NSYS140
  at L1183, NSYS130 pool-rent at L1203–1205).
- **Callee resolution (the SemanticModel coupling to sever):** `MergeDeclaredCalleeSummaries`
  (L718), `TryResolveDeclaredCallee` (L741–765), `TryGetEntryForFunctionType` (L766),
  `TryGetEntryForMethodGroup` (L777), `TryGetEntryForDeclarationSite` (L790),
  `BuildVisibleDeclarationFiles` (L816), `TryResolveConstrainedInterfaceCallee` (L849),
  `TryLookupTypeReference` (L905), `ReportCalleePolicyViolations` (L919–945; NSYS020/030/040/050
  at L927–933, NSYS090 at L939, NSYS130 at L940–941, NSYS110 at L943).
- **Facts application:** `IsBufferMemoryCopyCall`/`ApplyBufferMemoryCopyFacts` (L1241–1263),
  `ApplyHotSummary` (L1264–1349; NSYS090 HotSummary-resource at L1346) — consumes
  `HotSummaryCatalog` entries.
- **Allocation tracking:** `RecordAllocation` (L1350–1403), `IsHeapAllocation` (L1404–1415),
  `IsValueTypeName` (L1416), `AddUnknownExternalCall` (L1426–1477).
- **Finding plumbing:** `AddHotFinding` (L1478), `AddFindingForPolicy` (L1486; "allow" policy
  check L1463), `AddFinding` overloads (L1509–1575).
- **Guard derivation:** `DeriveGuardsFromExitingIf` (L1576), `DeriveLoopGuards` (L1586),
  `DerivePositiveGuards` (L1589), `StatementExits` (L1597), `CollectNegativeGuard`/
  `CollectPositiveGuard` (L1607–1633), `IsIndexGuarded` (L1634), `IsNonZeroGuarded`/
  `IsDefinitelyNonZero`/`IsNonZeroFloatLiteral` (L1645–1667), `TryGetLengthComparison` (L1668),
  `TryGetIndexLessThanLength` (L1684), `IsZero` (L1700).
- **Type-size estimation + helpers:** `EstimateResultSize` (L1779), `EstimateTypeSize` (L1789),
  `EstimateSimpleTypeSize` (L1802), `IsSystemsHostileSurface` (L1820+); `GetCallTarget`/
  `ExpressionKey`/`SimpleName`/`TypeReferenceName`/`IsRefLikeType`/`ContainsRefLikeType`/
  `IsResultType` (L1703–1778).
- **Codes emitted (verified by grep):** NSYS001, 010, 020, 030, 040, 050, 060, 070, 080, 090,
  100, 110, 120, 130, 140, 150, 160, 170, 180 — 19 total.

### The single call site

`src/NSharpLang.Compiler/MultiFileCompiler.cs:335–345 AnalyzeSystemsPolicy`:
`new SystemsAnalyzer(_projectRoot, _config).Analyze(_compilationUnits, _performanceFacts,
_semanticModels)`, each finding → `_allErrors` via N# `SystemsFindingDiagnostics.ToCompilerError`.
Keep this method boundary stable; you rewrite its interior.

### Report models and consumers — ALL already N#; do not recreate

- `src/NSharpLang.Compiler.BootstrapServices/SystemsReport.nl` (90 LOC): `SystemsReport` record
  with `SchemaVersion: int` (L8) and `Findings: IReadOnlyList<SystemsFinding>` (L14);
  `SystemsFinding` record (L63): `Code, Severity, Effect, Message, File, Line, Column, Length,
  Function?, Policy?, SummarySource?, Suggestion?, CallPath: IReadOnlyList<string>`;
  `SystemsTrustedSite` (L79). Plus `SystemsReportSummary.nl` (11 LOC),
  `SystemsFindingDiagnostics.nl` (51 LOC), `HotSummaryModels.nl` (831 LOC, including
  `HotSummaryCatalog.Load` and the sidecar JSON schema), `PerformanceFactStore.nl` (33 LOC).
- JSON contract: `OutputFormatter.CheckSystemsReportToJson`
  (`src/NSharpLang.Compiler/CodeIntelligence/OutputFormatter.cs:377–394`, command
  `check.systemsReport`) delegates normalization to N#
  `OutputFormatterNormalizationKernels.NormalizeSystemsReport`
  (`BootstrapServices/OutputFormatterNormalizationKernels.nl:275–297`).
- Consumers: `src/NSharpLang.Cli/Program.Backends.cs:402–425` (findings→sites + TrustedSites for
  the perf report), `src/NSharpLang.Cli/Commands/QueryCommand.cs:272`,
  `src/NSharpLang.Compiler/CodeIntelligence/CodeIntelligenceService.cs:58` and `:1767–1801`
  (snapshot holds the report).

### THE INPUT GAP (pre-work, blocks everything else)

`ColumnarFunctionInput` (`src/NSharpLang.Compiler.BootstrapServices/ColumnarInputs.nl`) carries
`Name, ReturnCanonical, Param* columns, BodyNodes: ColumnarNodeTable, BodyRoot, IsStatic,
IsAsync, TypeParam*, ModifierFlags: int, LocalFunctions` — **no attribute columns**.
The function/declaration regions in the consolidated
`BootstrapServices/CompilerServices/ColumnarParserKernels.nl` do not yet expose the required
attribute facts. SystemsAnalyzer needs `[hot]`, `[boundary]`, `[allow(...)]`, and the
corpus contains qualified/argumented forms (`examples/10-interop/QualifiedAttributes.nl`).
Attribute name + argument columns must be surfaced through the columnar function parser before
any finding kernel can run. Also verify `alloc` expressions / `alloc { }` blocks have a
distinguishable node KIND in `ColumnarNodeTable` (kinds/valueStarts columns) rather than being
erased — NSYS001 depends on the alloc marker; the gauntlet builds via columnar emission, so the
parser accepts the syntax, but acceptance ≠ surfaced.

## Standing harness

- **`tests/SystemsNSharpTests.cs` (2,403 lines).** Harness at L2243–2281:
  `Analyze(source, profile, mode)` → `AnalyzeProject` → `new MultiFileCompiler(...);
  compiler.CompileForAnalysis(); return compiler.SystemsReport;` — the REAL pipeline including
  legacy-analyzer semantic models. This is what makes the fact producer viable and the
  differential harness cheap. Note: the namespace `NSharpLang.Tests.PerfEvidence` it imports
  holds only `IlVerifyBaselineEmptyTests.cs` — there are no fixture files under
  `tests/PerfEvidence/`; don't hunt there.
- **Golden gauntlet:** `tests/fixtures/systems-gauntlet/{01-packet-parser, 02-frame-writer,
  03-spsc-ring, 04-heap-arena, 05-ref-struct-reader, 06-pooled-boundary, 07-trusted-copy,
  08-order-book, 09-native-interop, 10-json-cli}`, each with `systems.golden.json` +
  `diagnostics.golden.txt` + `perf-report.golden.json`, asserted byte-style by
  `AssertSystemsGolden` (L1186), `AssertDiagnosticsGolden` (L1287), `AssertPerfGolden` (L1311).
  `BuildSystemsProofProjects` (L2032–2096) also BUILDS these projects in-process via columnar
  emission — gauntlet sources are already inside the columnar accept-set.
- **Differential harness** (you build it in F3, delete it in F4): both implementations run in
  `AnalyzeSystemsPolicy`, finding lists compared per ported code
  (code+file+line+column+message), throw in DEBUG on mismatch — so every existing systems test
  doubles as a differential assertion for free.
- **Evidence ladder:** inner loop `./scripts/dev.sh SystemsNSharp` (never raw
  `dotnet test --filter` — documented hang); plus `dev.sh Columnar` / `dev.sh CompilationBackend`
  for F1, `dev.sh PerformanceFactStore` / `dev.sh CheckCommand` at the flip. Run the full unit
  suite at sub-arc boundaries and attribute every current failure directly; the historical
  baseline is retired.
  SystemsNSharpTests itself must be fully green throughout; if any of its tests sit in the
  pre-existing failure set, resolve WHY before porting that area — a broken oracle poisons the
  port. Integration checkpoint at track end: fresh `VSCODE_TESTS=skip ./scripts/test-all.sh
  --commit` (not IDE-affecting; spend no VS Code budget). Benchmark-gate cautions: run the gate
  cool and serially (the Systems benchmark + allocation gates flake under thermal/CPU load —
  the PooledBoundary ~4 B allocation gate especially), and never gate from a worktree nested
  under the repo root (breaks the BDN Systems gate: "expected 6, got 0"); use a `/tmp` worktree.

## Sub-arc plan

Every stage is one commit with focused evidence green. Keep `SystemsAnalyzer.cs` alive as the
comparison oracle until F4.

### F1 — pre-work: attribute/modifier columns in the columnar parser inputs

1. Extend the live function/signature regions in
   `CompilerServices/ColumnarParserKernels.nl` to capture, per function: attribute names and
   per-attribute argument texts (e.g. `allow` → `["alloc"]`). Use the existing flat out-array
   kernel convention (counts + offsets into a string sidecar), preserving the single parser
   ledger and coordinating one writer on the consolidated file.
2. Extend `ColumnarFunctionInput` with attribute columns. `string[][]` is already a modeled shape
   (`ColumnarUnionInput.CaseFieldNames`) — stub-probe it; fall back to parallel flat arrays +
   counts if the pinned SDK declines. Default the new columns empty in the constructor like the
   existing optional columns so every current caller compiles unchanged.
3. Populate the columns in the program-input owner (today
   `src/NSharpLang.Compiler/Columnar/ColumnarProgramInputBuilder.cs`; whatever Track B leaves as
   owner post-static-binding). Struct methods, constructors, and properties reuse
   `ColumnarFunctionInput`, so they inherit the columns.
4. Type declarations: `CheckRefLikeFields` needs the `refstruct`/`struct`/`class` distinction —
   verify `ColumnarStructInput.IsReference` plus whatever ref-struct flag exists; if
   ref-structness is not surfaced, add it here. Also confirm the alloc-marker node kind (see
   input gap above).
5. Evidence: `./scripts/dev.sh Columnar` + a probe test asserting `[hot] func F() {}`
   round-trips with attribute name `hot` and `[allow(alloc)]` carries the arg. CRITICAL: the
   emitter must keep IGNORING the new columns (attributes have no codegen today) —
   `./scripts/dev.sh CompilationBackend` proves no emission regression.

### F2 — disconnect stage: the callee-resolution fact producer

1. New `src/NSharpLang.Compiler.BootstrapServices/SystemsPolicyInputs.nl`: a
   `SystemsCallResolutionFacts` record of flat columns keyed by stable semantic identity:
   caller source-file id + caller function/declaration id + columnar call-node id/span; resolved
   kind (unresolved/external, project function, constrained-interface member); resolved
   declaration/function id; and the overload signature and closed generic-instantiation identity
   needed to distinguish same-named overloads, local functions, and constructed calls. File/line/
   column/name columns are display facts only, never join keys. Reuse C/D's canonical
   SymbolId/TypeId contract rather than inventing an F-only identity.
2. In `MultiFileCompiler.AnalyzeSystemsPolicy`, while legacy analysis still runs, mechanically
   flatten the already-resolved BindingMap/SemanticModel identities into that record. Do not port
   or duplicate the lookup/resolution algorithms in C#. This is the disconnect point: the kernel
   consumes facts, never the C# object graph. When Track D's N# binder lands, it produces the
   same stable fact rows without changing the policy kernel.
3. `HotSummaryCatalog` is already N# (`HotSummaryModels.nl` incl. `Load`) — pass the loaded
   catalog to the kernel directly. `PerformanceFactStore` is already N# — the kernel writes
   AOT-blocker facts into it directly.
4. Evidence: a unit test asserting the producer resolves the same declaration for a 2-file
   cross-call as `TryResolveDeclaredCallee` does (drive both on one MultiFileCompiler instance).

### F3 — kernel port (three commit-sized stages, differential from day one)

1. **Skeleton + registration + summaries + surface checks**
   (NSYS001/010/060/070/080/100/150/160/170/180): create
   `src/NSharpLang.Compiler.BootstrapServices/SystemsPolicyKernels.nl` (namespace
   `NSharpLang.Compiler`, beside SystemsReport.nl). Port registration (L110–186) over
   `ColumnarProgramInput` (structs/enums/unions/interfaces + the new attribute columns); the
   per-function summary state machine (L187–318) with memoization keyed by function INDEX (int)
   instead of C# reference identity; `CheckRefLikeFields`, `ValidateFunctionLevelAllows`,
   `CheckFunctionSurface`; the alloc-marker walk (NSYS001 L1377, hot-alloc NSYS010 L222) over
   `ColumnarNodeTable` node kinds; `RecordAllocation`/`IsHeapAllocation`/`IsValueTypeName`
   (L1350–1425). Wire the DIFFERENTIAL harness in `AnalyzeSystemsPolicy` in this same stage;
   product output still comes from the C# analyzer. Evidence: `./scripts/dev.sh SystemsNSharp`.
2. **Effect walker + callee policy + allocation/hot findings**
   (NSYS020/030/040/050/090/110/120/130/140): port `WalkStatement` (L536–717), `WalkExpression`
   (L946–1140), `WalkCall` (L1141–1263) as an iterative walk over the post-order
   `ColumnarNodeTable` (proven kernel pattern: shared state arrays + LIFO work stack, no
   recursion needed). Port `MergeDeclaredCalleeSummaries` + `ReportCalleePolicyViolations`
   (L718–740, L919–945) consuming F2 fact rows; `ApplyHotSummary`/`ApplyBufferMemoryCopyFacts`
   (L1241–1349); `AddUnknownExternalCall` (L1426) conservatism;
   `CheckIgnoredResult`/`CheckPoolBalance`/`CheckResourceBalance` (L445–507). Evidence:
   differential green on `dev.sh SystemsNSharp` including callee-policy + hot-summary families.
3. **Guard derivation + type-size estimation:** port L1576–1702 (guards) and L1747–1830+
   (`IsRefLikeType`/`ContainsRefLikeType`/`IsResultType`, `Estimate*Size`,
   `IsSystemsHostileSurface`) — these operate on type-canonical STRINGS in the columnar world;
   reuse `ColumnarTypeCanonicalizer.nl` for string surgery instead of re-porting TypeReference
   pattern matches. Evidence: differential green across the FULL SystemsNSharpTests suite + the
   gauntlet goldens.

### F4 — flip ownership, then delete the C# owner

1. **Flip:** `AnalyzeSystemsPolicy` calls ONLY the kernel — build `ColumnarProgramInput` per
   project (via the statically-bound program assembly, from `_sourceTexts`), produce fact rows,
   call `SystemsPolicyKernels.Analyze(...)` → `SystemsReport`; findings→errors stays on N#
   `SystemsFindingDiagnostics.ToCompilerError`. Determinism: findings sorted file/line/column
   exactly as `Analyze` (L48–104) orders them today; `SchemaVersion` preserved; the gauntlet
   goldens must not change by a byte — a golden diff means the kernel is wrong. Delete the
   differential harness in this commit. Evidence: `dev.sh SystemsNSharp`,
   `dev.sh PerformanceFactStore`, `dev.sh CheckCommand`, plus behavioral probes on a fresh
   `Cli.dll`: (a) scratch systems-profile project (`language.profile: systems`,
   `language.systems.mode: strict`) with unmarked `new Box()` → NSYS001, with `alloc new Box()`
   → clean; (b) a `[hot]` heap-alloc program prints NSYS010 with today's exact message;
   (c) `check --json` `check.systemsReport` envelope byte-compares against pre-flip capture
   (capture it during F3 stage 1); (d) each gauntlet project's diagnostics diff clean against
   `diagnostics.golden.txt`.
2. **Delete:** `git rm src/NSharpLang.Compiler/Performance/SystemsAnalyzer.cs` (Performance/
   empties). Remove `using NSharpLang.Compiler.Performance;` from MultiFileCompiler.cs and any
   stragglers — `grep -rn "SystemsAnalyzer" src tests --include="*.cs"` must return zero product
   hits (tests referencing it directly get repointed at the pipeline harness SystemsNSharpTests
   already uses). Delete the F2 fact producer ONLY if Track D's columnar binder has landed;
   otherwise it stays as the clearly-marked legacy-boundary producer for Track H's glue
   inventory/front-end deletion — record which outcome in the commit message. Update
   `memory/components/` systems/perf docs to name the N# owner. Integration checkpoint: fresh
   `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` (read the GATE EXIT line from the log).

## Cross-track contract

- **Track B static binding is complete.** F1 may proceed after the active parser writer releases
  the consolidated file. SDK repins remain announced shared-state changes.
- **Tracks C/D provide canonical identity before F2.** Caller source/function/node ids and
  resolved declaration/function/type ids are a shared compiler contract, not a systems-policy
  invention. F2 may jointly land that contract with D, but cannot proceed with display tuples as
  join keys.
- **`MultiFileCompiler.cs` contention** (see README contention ledger): Track C owns pipeline
  sequencing, Track E touches typeref scoping. Land F2/F4 edits to `AnalyzeSystemsPolicy` AFTER
  Track C's sequencing sub-arc, then rebase on it; the method boundary itself stays stable.
- **Columnar-parser input extension (F1)** touches the consolidated
  `CompilerServices/ColumnarParserKernels.nl` and `ColumnarInputs.nl`, which Track A/C/G work may
  also touch (A during product closeout,
  restoration, C for the syntax front-end). Coordinate before editing; new columns must default
  empty so other tracks' callers compile unchanged; stage only your files, never `git add -A`.
- **Track D** ([track-d-semantics.md](track-d-semantics.md)): its N# semantic owner ultimately
  produces the same stable fact rows and removes the temporary C# flattener. F blocks on the id
  contract, not necessarily on every analyzer family.
- **Track E** ([track-e-backend-emitter.md](track-e-backend-emitter.md)): accept-set work lifts
  kernel shape limits (e.g. generic user types). Until then, write the kernel inside today's
  limits.
- **Track H** ([track-h-tests-release.md](track-h-tests-release.md)): verifies that the temporary
  internal fact flattener is gone before final campaign close. Internal C#→N# transition glue is
  not an external-host survivor.

## What NOT to do

- **Do NOT delete SystemsAnalyzer.cs before the differential harness has run green across the
  ENTIRE SystemsNSharpTests suite AND the gauntlet goldens** (the 2026-07-01 incident: deleting
  C# owners without full-fidelity replacements caused ~107 failures).
- **Do NOT regenerate or "fix" golden files to match kernel output.** The goldens are the
  versioned contract (`SystemsReport.SchemaVersion`); any diff is a kernel bug. The only
  acceptable golden change is none.
- **Do NOT pass C# delegates into the kernel** for callee resolution — the route-back-into-C#
  anti-pattern is banned campaign-wide. The disconnect is a FACT ARRAY produced before the
  kernel runs.
- **Do NOT reference `NSharpLang.Compiler` C# types (Ast, SemanticModel, Analyzer) from any
  .nl file** — BootstrapServices is referenced BY the Compiler; a back-reference is circular and
  defeats the point.
- **Do NOT re-implement the report models** — SystemsReport.nl, SystemsReportSummary.nl,
  SystemsFindingDiagnostics.nl, HotSummaryModels.nl, PerformanceFactStore.nl are already N#.
- **Do NOT trust reviewer reasoning over the pipeline** — verify-first; probe edge cases
  (partial init, early return, unknown callee, audit vs strict mode, direct and mutual
  recursion) through the differential harness before accepting any "equivalent" verdict.
- **Do NOT use columnar-declined shapes in kernel code** (bare `this`, `GetType()` on typed
  receivers, generic user types, records as base types). The kernel is big — stub-probe early
  (~13s/build), not after 2,000 lines.
- **Do NOT `git add -A`** — concurrent tracks share this checkout.

## Track exit criteria

- [ ] `SystemsAnalyzer.cs` (2,390 LOC) deleted; `Performance/` empty/removed; zero product
      references (`grep -rn "SystemsAnalyzer" src --include="*.cs"` clean).
- [ ] All 19 NSYS codes produced by `SystemsPolicyKernels.nl` from columnar tables + fact
      arrays; no kernel input is a C# AST or SemanticModel type.
- [ ] Attribute/argument columns surfaced end-to-end (parser kernel → `ColumnarFunctionInput` →
      program input) with emission behavior unchanged.
- [ ] Any temporary C# producer only flattens already-resolved stable identities with zero
      lookup/filter/selection policy; its D removal stage is recorded, and it is absent before
      final campaign close.
- [ ] `tests/SystemsNSharpTests.cs` fully green; all `tests/fixtures/systems-gauntlet/*` goldens
      byte-identical (zero golden diffs in the final commit).
- [ ] `check.systemsReport` JSON envelope byte-stable (probe evidence in the commit message).
- [ ] No new C# resolution or product policy; temporary C# adaptation is mechanical flattening
      only; net C# LOC strongly negative.
- [ ] Fresh `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` green (GATE EXIT line from the
      log, not a cached result).
- [ ] `memory/components/` systems/perf docs name the N# owner.

## Gotchas & prior art

- **The tests run the whole pipeline** (`CompileForAnalysis`), so legacy semantic models exist
  during the port — that is what makes the F2 producer viable and the differential harness
  cheap.
- **Findings depend on resolution success:** files whose legacy analysis failed have no
  SemanticModel; their calls are conservatively unknown (see the comment at
  MultiFileCompiler.cs:337–339). Encode "no model" as resolved-kind-0 ROWS, not missing rows, or
  NSYS120 conservatism diffs.
- **Summary memoization + visiting-set semantics** (L187–318) are behavioral: a self-recursive
  `[hot]` function must produce the same findings as today — add differential probes for direct
  AND mutual recursion.
- **Attribute forms:** qualified attributes exist in the corpus
  (`examples/10-interop/QualifiedAttributes.nl`); `AttributeNameEquals` (L2191) implements the
  matching rule — port THAT rule, do not invent string equality.
- **Node/token ordinal contract:** node-kind ordinals are an implicit shared contract between
  the .nl parser kernels and consumers (e.g. case 25 = Block in the emitter); no shared
  constants file exists. Copy ordinals verbatim into ONE named-constant block in the kernel with
  a comment pointing at the producing parser kernel — TokenType-ordinal drift and the
  `>>`-split gotcha have caused real bugs.
- **Kernel-proof test pattern:** copy the `tests/ColumnarTypeCanonicalizerTests.cs` /
  `Columnar*FactsTests` shape for kernel-level unit tests. Emitted-assembly loading in tests
  must use `CollectibleAssemblyScope` — never `Assembly.Load(bytes)`; a source-scan guard test
  trips on the literal string.
- **Exemplar commits:** `65eb92b9` (print statements modeled in the columnar backend) and
  `8b4dc47f` (value-struct union emission with oracle probes) show the slice+probe cadence; the
  ImportGraphModels.nl port shows the "N# decisions, C# enumeration glue" end shape for the F2
  producer.

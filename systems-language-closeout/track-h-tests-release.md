# Track H — Test estate & release integration

> **LIVE STATUS (audited at `fb856ee46`):** runner DTO/JSON/test-policy ports are partial; the
> xUnit path, native-test gate and estate, playground, C# test closeout, front-end integration,
> docs, and final audit remain. No product suite may be deferred at campaign close. TypeScript
> owns UI/adapter integration only; canonical language/LSP semantics also require N# coverage.
> H must mechanically retarget a named live consumer only when the producing track explicitly
> hands it off; it never deletes a live facade by assumption. A `query ast` schema change is a
> separate approved versioned contract, not incidental cleanup. See [STATUS.md](STATUS.md).

**Owner model.** One senior owner, staffed in two bursts. H1 runner-host shrink may start now.
H2/H3 native-estate and CLI migration wait for Track A's complete native-test grammar and fresh
green product gate. The ENDGAME waits on the named C/D/E/F/G exits (playground, front-end
deletion, estate close-out, docs, final audit). The Track H owner is
the **release integrator**: they know which suites assert what through which harness — exactly the
knowledge the endgame deletion runs on. This owner executes the front-end deletion but does not
self-certify it: the delete commits are **co-signed** by the Track C, D, and G owners, each
verifying their domain's rows of the incident checklist (sub-arc H5) against pre-deletion
captures and recording go/no-go in writing (commit trailer or PR review). Co-sign is a
verification act, not a courtesy ping.

Track-critical campaign rules (full set in [README.md](README.md)): **replace-then-delete** (never
delete a C# owner or C# test before the N# replacement is in the product path / in the gate with
behaviors verified); **no C# test truth** at end state; **stage = commit** with an `Evidence:`
line; **verify-first** against the real pipeline built from this branch (installed
`~/.nsharp/bin/nlc` is routinely stale); stage only your own files; heavy gates run fresh, cool,
serially, never from a worktree nested under the repo root.

## Mission & end state

1. `nlc test` is N#-owned: discovery policy, case modeling, display names, result records,
   outcome ranking, failure formatting, and the schemaVersion-1 JSON envelope live in N# kernels;
   `Program.Testing.cs` shrinks 740 → ~150–200 LOC of ALC/reflection/Invoke host glue; the
   xunit-controller path and the `xunit.runner.utility 2.9.2` PackageReference are deleted from
   `src/NSharpLang.Cli/Cli.csproj`.
2. First N#-owned test estate: 16 kernel-proof C# test files (1,453 LOC) become `.tests.nl`
   siblings of their kernels, and a **new `nlc test` gate step** lands in
   `tests/scripts/test-all-core.sh` (none exists today) — the first gate coverage of the
   `.tests.nl` feature itself.
3. The 11 CLI product-behavior suites (13,830 LOC / 494 facts, incl. CliCommandTests.cs 5,483)
   are re-owned as N# tests in `tests/nsharp/` that SPAWN `nlc` and assert on
   stdout/stderr/exit/JSON — implementation-agnostic tests that survive every remaining C#-owner
   deletion without rewrites.
4. Playground Run executes real columnar-emitted IL; the 970-LOC C# AST interpreter is deleted.
5. The C# front-end is deleted (inventory below), co-signed by C/D/G.
6. The remaining C# test estate (71 files / 65,029 LOC at drafting) is closed out: product
   behavior migrates to N#; every survivor is classified mechanical harness/guard with owner,
   forbidden responsibilities, and a removal path.
7. Docs/memory describe the N#-owned toolchain as CURRENT architecture, present tense; transition
   guidance is deleted, never archived.
8. A final ownership audit proves every remaining non-N# file is inventoried mechanical glue.
   This audit closes the campaign.

## Why this is one track

Every arc is the same competency: the assertion map. Migrating a suite requires knowing what it
pins; deleting the front-end requires knowing which tests were its truth and where successors
live; the estate close-out is that map made total; the final audit is its proof. A second owner
would have to rebuild the map the first already carries. The phase gap is a staffing pause, not a
handoff.

## Current state (verified 2026-07-02, commit 9538ab66)

All anchors verified at 9538ab66. Tracks A–G will move some; re-verify with grep before editing —
drift is expected, not a plan error.

### The runner: `src/NSharpLang.Cli/Program.Testing.cs` — 740 LOC, single C# owner of N#-native test execution

- **L20–49 data records**: `NativeTestCase(DisplayName, FullyQualifiedName, MethodInfo, Arguments,
  SkipReason)`, `NativeTestResult(Name, DisplayName, Outcome, Duration, ErrorMessage,
  NSharpDescription)` (last serialized as `nsharpDescription` via `JsonPropertyName`),
  `NativeTestRun`, `NativeTestSummary`.
- **L51–65 `NativeTestLoadContext`**: collectible ALC with directory-probing Load. Host boundary;
  stays C#.
- **L67–169 `TestWithIlBackend`**: command spine; all message text already delegated to
  `TestCommandKernels`. Framework routing L133–135: `"nunit"` → `RunReflectionTests`, else →
  `RunXunitTests`.
- **L172–261 `RunXunitTests`**: `XunitFrontController` discovery+execution — the only consumer of
  xunit.runner.utility. **DELETION TARGET.**
- **L263–358 `XunitResultSink`**: IMessageSink → result accumulation. **DELETION TARGET** (plus
  nearby `GetXunitDescription`/`GetXunitFullyQualifiedName` helpers).
- L374–414 `RunReflectionTests`: attribute-name path via NativeTestLoadContext + `TestCommandKernels.
  MatchesFilter(filter, displayName, string.Empty, fqn)` — proves discovery needs no xunit library.
- **L416–454 `DiscoverNativeTests`**: a method is a test if it carries a test attribute OR its
  declaring type is literally named `"NSharpTests"` (L429 — the attribute-free emission
  convention); display name from `Trait("NSharpDescription", …)`; InlineData row expansion with
  `"(a, b)"`/`"null"` suffixes (L436–450).
- L456–524 `RunNativeTest`: lifecycle order `InitializeAsync → Setup → test → Teardown →
  DisposeAsync → Dispose`; duration `F3`-seconds, skipped = `"0.000s"`. L526–583 Invoke/Task-wait/
  timeout glue (stays C#). L585–595 `IsLifecycleMethod` + `IsTestMethodAttribute` name sets
  (Xunit Fact/Theory, NUnit Test/TestCase) — magic-string DECISIONS, port to N#. L597–656
  description/skip/InlineData extraction — decisions port, reflection walking stays. L658–678
  `UnwrapInvocationException` stays. L680–701 outcome summarizing + rank map
  (`passed→1, failed→2, skipped→3, _→0`) — rank map ports.
- **L703–738 `OutputNativeTestJson`** — the pinned envelope: `{ schemaVersion: 1, command:
  "test", ok, projectRoot (slash-normalized), error, summary { total, passed, failed, skipped,
  duration: "0s" }, results: [...] }`, `WriteIndented`, camelCase, `WhenWritingNull` omission,
  `nsharpDescription` on results. **Port to N# with byte parity.**

The N# half exists: `src/NSharpLang.Compiler.BootstrapServices/TestCommandKernels.nl` (421 LOC,
ns `NSharpLang.Cli`) — outcome/option summaries, `SummarizeOutcomeRanks`, `MatchesFilter`, help
text, every message getter; statically referenced, no reflection loader. Dependency to delete:
Cli.csproj L36 `xunit.runner.utility 2.9.2`; Program.Testing.cs L13–14 `using Xunit*`. Canary
pins (Track A turns green — verify first): `tests/CompilationBackendTests.cs`
`TestCommand_UsesConfiguredIlBackendAndRunsExecutableProjectTests` (L1145–1188),
`TestCommand_CoverageJson_ReturnsUnsupportedErrorBeforeDiscovery` (L1191–1219),
`TestCommand_BackendOverrideToIl_RunsTestsThroughSdkProject` (L1566+).

### The 16 kernel-proof C# test files (wc-verified, 1,453 LOC total)

| File (tests/) | LOC | Facts | Kernel under test (BootstrapServices/) | Notes |
|---|---|---|---|---|
| ParserTokenFactsTests.cs | 207 | 5 | ParserTokenFacts.nl | `AssertTokenSet`: exhaustive over `Enum.GetValues<TokenType>()`, both directions |
| ParserLiteralFactsTests.cs | 47 | 3 | ParserLiteralFacts.nl | pure |
| NumericLiteralFactsTests.cs | 80 | 6 | NumericLiteralFacts.nl | `typeof(...)` args |
| OperatorFactsTests.cs | 98 | 6 | OperatorFacts.nl | pure |
| TypeReferenceFactsTests.cs | 137 | 6 | TypeReferenceFacts.nl | pure |
| AnalyzerBindingFactsTests.cs | 123 | 4 | AnalyzerBindingFacts.nl | pure |
| AnalyzerOverloadSignatureFactsTests.cs | 75 | 2 | AnalyzerOverloadSignatureFacts.nl | pure |
| ColumnarLiteralFactsTests.cs | 54 | 3 | StringLiteralDecoder.nl | 1 emit-integration fact |
| ColumnarNumericFactsTests.cs | 101 | 4 | ColumnarNumericFacts.nl | 2 emit-integration facts |
| ColumnarPatternFactsTests.cs | 66 | 3 | ColumnarPatternFacts.nl | 1 emit-integration fact |
| ColumnarRuntimeTypeFactsTests.cs | 20 | 1 | ColumnarRuntimeTypeFacts.nl | pure |
| ColumnarTypeCanonicalizerTests.cs | 102 | 6 | ColumnarTypeCanonicalizer.nl | 2 emit-integration facts |
| GeneratorSequenceTypeFactsTests.cs | 57 | 4 | GeneratorSequenceTypeFacts.nl | pure |
| LoopSequenceTypeFactsTests.cs | 81 | 4 | LoopSequenceTypeFacts.nl | pure |
| TaskLikeTypeFactsTests.cs | 50 | 3 | TaskLikeTypeFacts.nl | pure |
| PerformanceFactStoreTests.cs | 155 | 10 | PerformanceFactStore.nl (ns …Compiler.Performance) | pure data-model |

The **6 emit-integration facts** (only these columnar files call `ColumnarCompiler.TryEmitProgram`
in all of tests/) cannot convert literally — `.tests.nl` in BootstrapServices cannot reference the
Compiler assembly (circular), and in-proc byte loading is host-boundary. **Rewrite behaviorally**:
a `.tests.nl` body IS a columnar-emitted program, so `test "int-promotable arithmetic" { let a:
byte = 1  let b: short = 2  assert a + b == 3 }` proves identical routing end-to-end; any single
inexpressible one relocates into `tests/CompilationBackendTests.cs` (relocation, not new C#),
recorded in the commit message. `typeof` is columnar-supported (the kernels themselves use it).

### The 11 CLI product-behavior suites (wc/grep-verified, 13,830 LOC / 494 facts)

| File (tests/) | LOC | Facts | ProcessState | Character |
|---|---|---|---|---|
| CliCommandTests.cs | 5,483 | 135 | yes | in-proc reflection on `Program.Execute` + CaptureConsole; kernel facts (`ProgramCommandKernels.GetCommandKind` L31–58); registry/help/docs parity guard reading `website/docs/cli-reference.md`; reads `tests/fixtures/json-contract-root-keys.golden.json` (L5470) |
| CheckCommandTests.cs | 674 | 26 | yes | in-proc, examples-anchored (`01-hello-world`, `14-minimal-api`) |
| FixCommandTests.cs | 838 | 31 | yes | fix behavior, edits + JSON |
| FixApplicatorTests.cs | 561 | 35 | no | MIXED: kernel facts (`FixApplicatorTextEditOrderer.OrderTextEdits`) + process-observable behavior |
| CodeFixTests.cs | 601 | 25 | no | code-fix production behavior |
| DaemonCommandTests.cs | 808 | 31 | yes | daemon lifecycle/protocol — long-lived process + stdin |
| CliParityAuditTests.cs | 1,824 | 73 | yes | parity-audit assertions |
| QueryIntegrationTests.cs | 1,321 | 65 | no | `nlc query`; golden vs `docs/examples/diagnostic-clusters.sample.json` |
| DocQueryTests.cs | 142 | 8 | no | direct `DocQuery` facade facts — follows Track B's owner move |
| ProjectFileTests.cs | 903 | 36 | no | MIXED: kernel facts (`AssemblyVersionUtilities`) + project.yml behavior |
| ExampleLintTests.cs | 675 | 29 | yes | lints `examples/` sources |

`[Collection("ProcessState")]` (tests/ProcessStateCollection.cs, 8 LOC) serializes suites mutating
Console/CWD/process state; process-boundary rewrites dissolve it. The file dies with its **last**
C# consumer, not before. Process spawning is columnar-modeled (`ColumnarRuntimeTypeFacts.nl`
L8–12 whitelists `Process`/`ProcessStartInfo`/`StreamReader`, consumed at ColumnarIlEmitter.cs
L443); `StreamWriter`/`StandardInput` is NOT modeled — daemon-group blocker to probe.

### The gate has NO nlc-test step

`tests/scripts/test-all-core.sh` (812 LOC): Step 2 builds Cli (~L310); Step 2b format gate
(L317–333, `$CLI_DLL` fresh); **Step 3 `dotnet test tests/Tests.csproj` (L336–357) is the ONLY
test-execution step**. `grep -n "nlc test"`: zero hits — `.tests.nl` files are only ever
format-checked today. Per-step cache: `step_cache_hit/store/skip_banner` (L161–183); a python
heredoc hashes each entry of the `SETS` literal at **L200–208** (`COMMON` + `UNIT`/`EXAMPLES`
tuples; UNIT covers `src/ tests/ examples/ templates/ docs/ website/docs/
editors/vscode/test/suite/`). `tests/GateStepInputSetGuardTests.cs` (303 LOC) regex-parses that
literal (every entry must match `"NAME": COMMON + (...)`), pins known repo-file reads (L22–28),
self-discovers repo-root path literals in `tests/**/*.cs` only (L59–94 — **`.nl` sources escape
until extended**), and executes the extracted python against a fixture (L151–180). A new step
reusing `UNIT_INPUTS_HASH` passes all guards unchanged; `--commit` forces `STEP_CACHE_OFF=1`
(guard-verified).

SDK hazard: `Sdk.targets` L84–87 auto-discovers `**/*.tests.nl` unless `NSharpExcludeTests ==
'true'` (set NOWHERE today), injects xunit/NUnit/Test.Sdk, and folds tests into `_NSharpIlSources`
(L154–156) — `.tests.nl` beside kernels would leak xunit + test types into the PRODUCT
BootstrapServices assembly on MSBuild builds. Fix via the csproj's generated `obj/project.g.props`
(InitialTargets writes only when missing — delete the stale file after editing). `nlc test`
doesn't use MSBuild for the il backend, so the exclusion doesn't affect it. `scripts/dev.sh`
(282 LOC) maps BootstrapServices paths to the unmapped `__FULL__` branch and never runs
`nlc test` — needs native-runner awareness.

### The endgame deletion inventory (sizes at 9538ab66; C/D/F/G shrink several to shells first)

| File | LOC today | Expected state when H5 starts |
|---|---|---|
| src/NSharpLang.Compiler/Parser.cs | 7,117 | diagnostics-free silent AST builder (after Track C) |
| src/NSharpLang.Compiler/Ast/Declarations.cs | 238 | pure data, ownerless (after Track D) |
| src/NSharpLang.Compiler/Ast/Expressions.cs | 381 | pure data, ownerless (incl. `AstNode` base) |
| src/NSharpLang.Compiler/Ast/Statements.cs | 225 | pure data, ownerless |
| src/NSharpLang.Compiler/Analyzer.cs | 22,783 | temporary zero-policy facade after D; G must delete it before H5 |
| src/NSharpLang.Compiler/Performance/SystemsAnalyzer.cs | 2,390 | must be deleted by Track F before H5; H verifies absence |
| src/NSharpLang.Compiler/Linter.cs | 1,611 | <50-LOC parse-boundary shell (after Track G) |
| src/NSharpLang.Compiler/Formatter.cs | 2,303 | FormatSafe shell over the N# engine (after Track G) |
| src/NSharpLang.Compiler/ErrorReporting.cs | 14 | `record ParseResult`; only consumer is Parser.cs |
| src/NSharpLang.Compiler/AstNodeFinder.cs | 15 | may already be deleted by Track G — verify |
| src/NSharpLang.Compiler/CodeIntelligence/FixApplicator.cs | 57 | parse-glue shell (after Track G) |
| src/NSharpLang.Compiler/MultiFileCompiler.cs | 533 | host glue + the dual validation path |
| src/NSharpLang.Playground/PlaygroundRunner.cs | 970 | deleted by H4 |

Ast/ totals 844 LOC / ~120 records. Consumer graph at 9538ab66: 13 `new Parser(` sites
(Playground, Cli fmt, LintCommand, DocumentManager, Formatter, Parser's recursive sub-parser, 4 in
Analyzer.cs import resolution, MultiFileCompiler, FixApplicator, CodeIntelligenceService);
`NSharpLang.Compiler.Ast` referenced by 55 files (13 src + ~26 tests). Note:
`CompilationReferenceResolver.cs:591`'s `TargetFrameworkVersionParseResult` is unrelated — NOT an
ErrorReporting.cs consumer.

**Dual-path anchors**: `MultiFileCompiler.CompileToIlAssembly(string, string, bool
validateStrictLint = false, bool validateWithLegacyAnalysis = true)` at **L398–477** (emit-only
fast path L406–420 vs legacy `ParseAllFiles()` — C# Parser at L201–204 — + `AnalyzeAllFiles()` +
columnar emission L422–477); `CompileForAnalysis()` L391–396; AST-keyed `_compilationUnits` L24 /
public `CompilationUnits` L44. SDK side: `src/NSharpLang.Sdk/Sdk/Sdk.targets` **L16–17**
(`NSharpEmitValidateWithLegacyAnalysis`, defaults `false` for BootstrapServices, `true` otherwise)
passed at **L171** (`ValidateWithLegacyAnalysis="$(NSharpEmitValidateWithLegacyAnalysis)"`);
`src/NSharpLang.Build.Tasks/EmitIlAssembly.cs` L43 property + L67 forwarding.

**`nlc query ast`** is a C#-AST product surface: `QueryCommand.cs:37` → `AstCommand` →
`snapshot.CompilationUnits` (L105–106) → `OutputFormatter.AstToJson` (OutputFormatter.cs L175–252,
reflection-walks the C# AST). Before H5, either preserve v1 bytes on the columnar parse or complete
a separately approved versioned migration with compatibility policy and goldens.
**Reflection-idiom compat kernels** (13 BootstrapServices `.nl` files that walk the
C# AST via `GetType().Name` dispatch + `GetProperty` over `object`): AstNodeFinderCore,
AstChildrenCore, CompilationUnitFacts, DeclarationFacts, CompletionDeclarationFacts,
TypeReferenceFacts, TypeInfoFactories, AnalyzerExhaustivenessSelector, CodeFix, BatchQueryKernels,
HotSummaryModels (+HotSummarySource), OutputFormatterReferenceFileKernels. H5 deletes the
object-walking halves — leaving them after Ast/ dies gives kernels that compile but silently
return garbage (string-name coupling).

**Playground**: `PlaygroundRunner.cs` (970 LOC) is a SECOND C# implementation of N# semantics —
an AST-walking interpreter with `MaxSteps=20_000`/`MaxCallDepth=128`/`MaxOutputLines=200` and 20
PG2xx codes (PG201–PG220). Caller `PlaygroundCompiler.cs` (614 LOC, schema v2): `RunProject` L192
runs real product analysis then the interpreter (L234–241; PG2xx catch at L253). Contract to keep
byte-stable: `PlaygroundRunResponse` (PlaygroundModels.cs L104–113). Emission is already
in-memory (`ColumnarCompiler.TryEmitProgram[MultiFile]` → `byte[]`; `isExecutable: true` builds a
real entry-point PE, landed in 9538ab66); the only disk write is the private
`MultiFileCompiler.TryEmitWithColumnarBackend` (L484–506) — the playground needs a public
bytes-returning split, NOT `InternalsVisibleTo` widening. Wasm host is pure glue; Run is on the
browser main thread (no Worker). Tests: `tests/PlaygroundCompilerTests.cs` (1,913 LOC), run-path
facts at L126/L1813/L1828/L1847.

### The remaining C# test estate (measured at 9538ab66 — re-inventory live before H6)

**71 files / 65,029 LOC** under tests/ (top level). Largest suites:

| Suite | LOC | | Suite | LOC |
|---|---|---|---|---|
| AnalyzerTests.cs | 13,438 | | PlaygroundCompilerTests.cs | 1,913 |
| ParserTests.cs | 6,130 | | CliParityAuditTests.cs | 1,824 |
| CliCommandTests.cs | 5,483 | | CompilationBackendTests.cs | 1,816 |
| LanguageServerTests.cs | 4,223 | | LinterTests.cs | 1,380 |
| LanguageServerDiagnosticsTests.cs | 3,182 | | AnalyzerSemanticModelTests.cs | 1,363 |
| SystemsNSharpTests.cs | 2,403 | | CodeIntelligenceTests.cs | 1,357 |
| FormatterTests.cs | 2,146 | | ParserErrorTests.cs | 1,923 |

Harness that STAYS C# (host boundary — the binding keep-list): `CollectibleAssemblyScope.cs` (40 —
the only sanctioned emitted-assembly loader), `CollectibleAssemblyScopeTests.cs` (134 — self-test
+ the repo-wide source-scan guard `TestSources_HaveNoDirectAssemblyLoadCallSites` L62–107: regex
over every `tests/**/*.cs` LINE, trips on the literal `Assembly.Load(` even inside string
literals; only `//`-comment tails stripped), `TestSdkFeed.cs` (326), `ProcessStateCollection.cs`
(8), `GateStepInputSetGuardTests.cs` (303), `SetupLocalScriptTests.cs` (359),
`VscodeIntegrationHarnessTests.cs` (82), `DotnetRunnerTests.cs` (65 — dies with its Track-B-domain
owner), `AnalyzerMetadataLoadContextTests.cs` (106 — dies with its Track-D-domain owner),
`PerfEvidence/IlVerifyBaselineEmptyTests.cs` (67), `tests/NSharpLang.IntegrationTests/` (~570,
Docker Testcontainers — already process-boundary).

### The incident checklist (2026-07-01) — the co-sign contract

"Delete fallback" commits deleted load-bearing paths before full-fidelity replacements existed
(~107 failures). The four behaviors that broke SILENTLY, their restoration commits (prior art for
"full fidelity"), and the endgame co-signer for each:

| # | Behavior | Restored in | Co-signer |
|---|---|---|---|
| 1 | Diagnostic spans (analyzer name spans, rich call diagnostics) | 2383a4fa | Track C (syntax) + Track D (semantic) |
| 2 | Rich NL401/NL202 messages, incl. parameter names in NL202 fallback text | 52c8a0d8 | Track D |
| 3 | ToString display (type-reference display via N#-owned overrides) | 19a9df58 | Track D (rendering) + Track G (hover/query surfaces) |
| 4 | Runtime well-known-type loading (NSharpLang.Runtime Result/Union/event types) | e3702449 | Track D |

Track G additionally co-signs the tooling surfaces: formatter idempotency, lint byte-stability,
completion/hover in the real editor.

## Standing harness

- Inner loop: `./scripts/dev.sh <pattern>` (`TestCommand`, `CompilationBackend`, `Playground`,
  `GateStepInputSetGuard`, `CollectibleAssemblyScope`, `--since`). Never raw
  `dotnet test --filter` (documented xUnit hang).
- Native runs, always against a FRESH build:
  `dotnet build --disable-build-servers -nr:false src/NSharpLang.Cli/Cli.csproj -v q`, then
  `dotnet src/NSharpLang.Cli/bin/Debug/net10.0/nlc.dll test --project <proj> [--filter g] [--json]`.
- Full unit suite after any test-file deletion: `dotnet test tests/Tests.csproj`.
- Integration checkpoints (fresh; read the GATE EXIT line; cached results are not evidence):
  `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` for backend arcs; VS Code-enabled
  `./scripts/test-all.sh --commit` + `./scripts/reload-vscode-extension.sh` + computer-use visual
  verification for anything under the IDE experience (H5 final stage; LSP migrations in H6).
- Spot-probe every migrated group: temporarily break the expected string and watch the N# test
  FAIL — an assertion that cannot fail is the classic migration bug.
- Parity table (old facts → new asserts) in every deletion commit message.

## Phase 1 sub-arcs (H1 ready now; H2–H3 start after Track A's green product gate)

### H1 — Finish the N#-owned test runner; delete the xunit path

1. **Pin runner semantics first** (commit): facts in `tests/CompilationBackendTests.cs` covering
   `--filter` display-name matching (two tests, filter selects one, `total==1`); failing-assert
   path (exit 1, `summary.failed==1`, `outcome=="failed"`, `errorMessage` present when non-null
   and OMITTED when null); `--verbose` composed output; envelope root keys exactly
   `schemaVersion, command, ok, projectRoot, error, summary, results` with slash-normalized
   projectRoot, `summary.duration=="0s"`, `nsharpDescription` on results; timeout message.
2. **Unify on the reflection runner; delete the xunit path** (commit): route all frameworks
   through `RunReflectionTests` (L133–135) — it already understands the Fact/Theory/InlineData,
   NUnit Test/TestCase/Ignore, `Skip`, `Trait("NSharpDescription",…)`, and `NSharpTests` universes
   (the entire surface emitted N# test assemblies produce; no MemberData/ClassData by
   construction). Delete RunXunitTests (L172–261), XunitResultSink (L263–358) + xunit helpers, the
   `using Xunit*` lines, and Cli.csproj L36. Filter-arg watch: the xunit path passed
   `testCase.DisplayName` as MatchesFilter's second arg, the reflection path passes empty —
   confirm stage-1 filter facts still pass. Evidence: dev.sh TestCommand + CompilationBackend;
   `grep -c xunit.runner.utility src/NSharpLang.Cli/Cli.csproj` → 0; `nlc test --json` probe on
   `examples/12-multi-file-projects/TestExample`.
3. **Port result modeling + JSON envelope to N#** (commit): extend `TestCommandKernels.nl` (or a
   sibling `TestRunnerKernels.nl`, same namespace, past ~800 LOC) with case-display-name
   composition (the InlineData suffix), outcome-rank map, F3-seconds duration formatting, and
   `BuildTestJsonEnvelope(...)` taking flat arrays and returning JSON **byte-identical** to
   `OutputNativeTestJson` — pin parity FIRST: a C# fact captures the old serializer's literal
   output for a fixed 3-result fixture, then asserts the kernel reproduces it byte-for-byte.
   Shrink `OutputNativeTestJson` to one Console.WriteLine. Kernels take arrays in, return
   strings/plans out — never a C# delegate. Stage-0 SDK constraint: pinned subset only; repins go
   through Track B.
4. **Port discovery/lifecycle decisions; shrink to glue** (commit): C# extracts per-method flat
   facts (names, attribute full names, trait pairs, skip candidates, InlineData row strings); N#
   owns the decisions at L429 + L585–630 (test-attribute set, `NSharpTests` convention, lifecycle
   name set, display-name/skip precedence, ordered execution plan); C# executes the plan. End
   audit: only NativeTestLoadContext, reflection walking, Invoke/Task-wait/timeout, exception
   unwrapping, and Console writes remain — no message text, format strings, JSON, or magic names
   in C#. Arc-end checkpoint: fresh `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`.
5. **Docs + AOT record** (commit): rewrite `memory/components/cli-toolchain.md`'s `nlc test`
   section (currently "xUnit-backed" — stale) and record the AOT limitation: in-process ALC test
   execution is JIT-host-only; the NativeAOT single-binary end-state needs process isolation or a
   generated static dispatcher — documented open debt, NOT solved here.

Context: the xunit version-skew triangle (tests pin 2.6.2, SDK injects 2.9.2 for user projects,
Cli carried runner 2.9.2) loses its third leg here; the SDK's injection keeps serving the
`dotnet test` route for user projects — do not touch it.

### H2 — First N#-owned test estate + the `nlc test` gate step

1. **Probe the route; stop the MSBuild leak; land one seed test** (commit): write ONE seed
   `ParserTokenFacts.tests.nl` (same namespace as the kernel); probe `nlc test --project
   src/NSharpLang.Compiler.BootstrapServices --json` with the fresh Cli — this makes the tip
   columnar backend compile the ENTIRE kernel corpus in one merged program with tests, a
   never-gated shape; if the corpus declines for non-test reasons, STOP and route to Track A/E
   (decline diagnosability owns the bisect). Fix the SDK leak: emit
   `<NSharpExcludeTests>true</NSharpExcludeTests>` from the generated `obj/project.g.props`
   (delete the stale generated file — it only writes when missing); verify no xunit in
   `obj/project.assets.json`, no test types in the product assembly.
2. **Add the gate step BEFORE deleting anything** (commit): new "Step 3c: N# native tests" in
   `tests/scripts/test-all-core.sh` after Step 3, following the Step 2b accumulating pattern,
   cache-keyed on the existing `UNIT_INPUTS_HASH` (a strict superset of this step's inputs — no
   SETS change, guards pass untouched; a new SETS entry must keep the exact `"NAME": COMMON +
   (...)` form). Body: fresh `$CLI_DLL` over BootstrapServices, `tests/fixtures/issue-tracker`,
   `examples/12-multi-file-projects/TestExample`, accumulating exit codes. Prove in a fresh
   `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` that the step EXECUTED. Update
   `memory/testing.md`. **Binding: no C# test file dies before this gate run is green.**
3. **Convert in four batches, deleting each batch's C# in the same commit** (4 commits):
   Batch A parser family (569 LOC C#); B analyzer family (198); C columnar family (343, incl. the
   6 behavioral rewrites); D sequence/perf family (343). Rules: one `.tests.nl` sibling per
   kernel, same namespace; every Theory/InlineData row becomes an explicit assert; **preserve
   exhaustive-set semantics** (`AssertTokenSet` asserts membership AND non-membership over all of
   `TokenType` — if enum-enumeration shapes decline, enumerate every member literally; never drop
   the negative half); prefix display names with the kernel name (multi-file merge requires
   project-unique names); parity table per batch; full unit suite after each deletion.
4. **Teach dev.sh the native runner** (commit, may fold into a batch): BootstrapServices paths →
   run `nlc test` on the project AND keep the fail-safe full unit suite.
5. **Close out**: zero migrated `*Tests.cs` remain; docs updated; fresh checkpoint gate.

### H3 — CLI product-behavior suites to N# process-boundary tests

Strategic payoff: process-boundary tests survive every remaining C#-owner deletion (Tracks B–G,
H5) without rewrites. Coordinate with Track B on the Query/Doc groups — ideally migrate them
early, but this is NOT a hard gate on B's port work: B freezes byte-level golden envelope oracles
before porting and keeps the existing C# CLI/query parity suites authoritative and green
throughout. The hard constraint runs the other way: those C# parity nets may not be deleted,
weakened, or re-baselined until their H3 successors are in the gate — and any expectation change
AFTER a B port requires deputy review with a commit-hash go/no-go record.

1. **Project + support kernel** (commit): `tests/nsharp/project.yml` (`name:
   NSharpLang.CliTests`, `backend: il`, `outputType: library`) + `TestSupport.nl`: `RunNlc(args,
   workDir)` spawning `dotnet <cli-dll>` via Process/ProcessStartInfo with redirected streams —
   CLI path from env `NSHARP_TEST_NLC`, repo files via `NSHARP_TEST_REPO_ROOT` (both injected by
   the gate step and dev.sh; NEVER a hardcoded/installed path); temp-project scaffolding;
   substring/exit-code/golden-text helpers. Interop probe first (`dotnet --version`, then
   `nlc --version`). Extend the H2 gate step body with `tests/nsharp` (UNIT hash already covers
   it). Test-support code lives in the TEST project, never in BootstrapServices (ships in the
   product).
2. **Group migrations** (commits per suite; delete each C# original only after its N# twin runs
   green IN THE GATE, fresh run):
   - Group 1 pure-text CLI (help/version/unknown/clean/completions regions of CliCommandTests).
     In-proc kernel facts (`ProgramCommandKernels.*`) go beside their kernels as BootstrapServices
     `.tests.nl`, not fake process tests; the registry/docs parity guard ports reading
     `cli-reference.md` via repo root (if file-read interop declines, keep that ONE fact in a slim
     C# guard file, recorded).
   - Group 2 check/fix/codefix. FixApplicatorTests splits by nature: kernel facts →
     BootstrapServices siblings; process behavior → FixCommand.tests.nl; C#-seam-only pins die
     with their owners, ENUMERATED in the commit message.
   - Group 3 query/doc/project-file. Goldens byte-exact (`diagnostic-clusters.sample.json`,
     `json-contract-root-keys.golden.json`); DocQuery facts become `nlc doc <symbol>` process
     assertions; ProjectFileTests kernel facts relocate, behavior facts drive `nlc build/check`
     on temp projects.
   - Group 4 example-lint + parity audit (audit facts pinning C#-internal structure die with
     their owners, enumerated).
   - Group 5 daemon LAST: start/write/read/shutdown over stdin/stdout; probe `StandardInput`
     modeling first — if declined and Track E's binder hasn't landed, extend the interop modeling
     N#-side or defer THIS SUITE ONLY with the blocker named; drive the full daemon flow to the
     END (partial walkthroughs hide last-step crashes).
3. **Guard maintenance** (commit): extend `GateStepInputSetGuardTests` with a self-discovery fact
   scanning `tests/nsharp/**/*.nl` and `src/**/*.tests.nl` for repo-relative path literals (the
   current guard scans only `.cs`); keep the known-repo-file entries with comments pointing at
   the N# readers.
4. **CliCommandTests close-out** (commits): migrate remaining regions until empty; delete; final
   parity accounting against the 494-fact baseline; ProcessStateCollection.cs stays while any C#
   ProcessState suite survives; docs (`memory/testing.md`: run one group via
   `dotnet <nlc> test --project tests/nsharp --filter <group>`); fresh checkpoint gate.

Hygiene: RunNlc passes a controlled environment (no inherited `NSHARP_*` vars — ambient vars
corrupted gate caches before); no shared temp dirs or chdir in TestSupport.nl; batch process
spawns where the original batched assertions; split the gate invocation by `--filter` group if
the step exceeds a couple of minutes.

## Phase 2 sub-arcs (endgame — waits on completed C, D, F, and G exits)

### H4 — Playground Run on the real pipeline; delete the 970-LOC interpreter

1. **Bytes-boundary split + execution proof** (commit): refactor
   `MultiFileCompiler.TryEmitWithColumnarBackend` (L484–506) into a public
   `TryCompileToIlBytes(assemblyName, out byte[])` holding today's exact source-gathering +
   `ColumnarCompiler.TryEmitProgram[MultiFile]` call (incl. the `isExecutable` decision), the
   private method reduced to split + `File.WriteAllBytes`. Zero new product logic; wasm-safe; no
   `InternalsVisibleTo` widening. **MultiFileCompiler.cs is on the contention ledger** (C/E/F) —
   coordinate first. Probe test: hello-world → bytes → `CollectibleAssemblyScope` →
   `Assembly.EntryPoint` → stdout.
2. **Corpus probe** (commit): every `PlaygroundExamples.All` + Tutorial step through the bytes
   pipeline; label outcomes (ran / analysis error / columnar decline with Track A's
   machine-readable reason). Policy: a declining example blocks THAT EXAMPLE (real diagnostic),
   never the slice; never re-grow an interpreter subset.
3. **Replace-then-delete in one commit**: `RunProject` keeps the normalize → analyze →
   errors-skip-run flow byte-for-byte (schema v2 `PlaygroundRunResponse`, "Run skipped…" and
   PG200/PG299 envelopes unchanged); the interpreter block becomes compile-to-bytes → collectible
   ALC (`LoadFromStream`; Unload wrapped so a wasm no-op/throw is swallowed) → EntryPoint invoke →
   Console SetOut/SetError capture with try/finally restore, preserving the 200-line truncation;
   unhandled exceptions unwrap to Stderr + ExitCode 1. Delete PlaygroundRunner.cs and
   `PlaygroundRunUnsupportedException` + its catch; PG201–PG220 retire; rewrite the catalog
   `Limitations` text to host limits, not language-subset limits. Tests: previously-interpretable
   runs keep IDENTICAL stdout; the PG2xx fact (L1847) becomes a real-run or real-decline
   assertion (probe, don't guess); add ≥3 run tests for constructs the interpreter rejected;
   expected values follow real CLR behavior (`DivideByZeroException` text), not interpreter
   quirks.
4. **Wasm + browser verification + gate** (commit): `./scripts/build-playground-wasm.sh`; serve,
   hard-reload (stale-chunk hazard), Run EVERY catalog entry, drive the tutorial to the LAST step
   (a crash once hid on the final module), screenshots; fresh `VSCODE_TESTS=skip` gate. Runaway
   execution (MaxSteps is gone; Run is on the wasm main thread, no Worker) is a documented host
   limitation + JS-side follow-up — never new C# step-limiting logic.

### H5 — Front-end deletion (co-signed by Tracks C, D, G)

1. **Stage 0 — go/no-go audit + co-sign kickoff** (no commit): confirm C/D/G (and F for
   SystemsAnalyzer) complete against their own exit criteria. Live consumer worksheet:
   `grep -rn "new Parser(" src --include='*.cs'` and `grep -rln "NSharpLang.Compiler.Ast" src
   --include='*.cs'` — every hit must be inside a file this sub-arc deletes, or STOP and route
   back to the owning track (**this sub-arc deletes, it never ports**);
   `grep -rn "GetType().Name" src/NSharpLang.Compiler.BootstrapServices/*.nl` per kernel;
   `grep -rn "ValidateWithLegacyAnalysis\|validateWithLegacyAnalysis" src` must match only the
   three anchor sites. Snapshot the checklist oracle: capture `nlc check` output (spans +
   NL401/NL202 text) on a known-error fixture, `nlc query type` ToString display, `nlc run` of a
   Result/union example — the before/after diff for every stage AND the co-signers' artifact.
2. **Commit 1 — syntax-tooling shells** (Track G co-signs): delete Formatter.cs, Linter.cs,
   FixApplicator.cs, AstNodeFinder.cs (if G hasn't), the CodeIntelligenceService source-text
   wrapper block; repoint/delete their tests under the never-delete-a-pin-without-a-named-
   successor rule. Verify `nlc fmt` idempotency over examples/, lint byte-stability, and the fix
   pipeline; run the full VS Code-enabled gate, reload/reinstall the extension, perform visual
   format/lint/fix verification, and capture screenshots at this commit.
3. **Commit 2 — single pipeline** (Tracks C and D co-sign): delete the
   `validateWithLegacyAnalysis` parameter and dual routing in `CompileToIlAssembly` (L398–477);
   delete the C#-Parser call in `ParseAllFiles` and `_compilationUnits`/`CompilationUnits` once
   consumer-free; delete Sdk.targets L16–17 + the L171 attribute and EmitIlAssembly.cs L43/L67 in
   the SAME commit; repin the local SDK (`scripts/setup-local.sh`) BEFORE the gate or examples
   build against a stale packaged SDK still passing the deleted property. Because this is part
   of the IDE-visible front-end deletion, run the VS Code-enabled gate, reload/reinstall the
   extension, visually verify the affected editor paths, and capture screenshots at this commit;
   then run the incident-checklist diff.
4. **Commit 3 — remaining explicitly handed-off front-end remnants** (C, D, and G ALL co-sign,
   four incident rows verified in writing): verify that G already deleted the zero-consumer
   `Analyzer.cs` facade and F already deleted `SystemsAnalyzer.cs`; H must not delete either.
   Delete only the zero-policy `Parser.cs`, remaining C# Ast files, and ErrorReporting.cs that
   their producing tracks explicitly hand off. Before this delete,
   resolve `nlc query ast` as a separate approved versioned-schema contract with compatibility
   policy and pre/post goldens; do not smuggle a breaking schema bump into the deletion commit.
   Once that contract is ready, re-found it on the columnar parse and delete `AstToJson`. Tests:
   ParserErrorTests stays as the syntax-diagnostics contract (N#-targeted per
   Track C); ParserTests grammar pins (precedence, `>>` splitting, interpolation holes, lambda
   lookahead) are rewritten against columnar node tables — the grammar regression net MUST
   survive; pure C#-record-shape pins die. Run the full unit suite, full VS Code-enabled gate,
   extension reload, computer-use verification across the incident surfaces, screenshots, and
   the incident-checklist diff at this commit.
5. **Commit 4 — reflection-idiom kernel sweep + docs + IDE gate** (Track G co-signs the IDE
   evidence): delete the object-walking kernel halves/files; remaining `GetType().Name` hits in
   BootstrapServices justified in the commit message; sweep test-side kernel-facts suites whose
   subjects died. Rewrite `memory/components/parser.md` and `analyzer.md` to describe the N#
   owners (present tense, no transition history). Final gates: this deletion sits under every LSP
   feature — **VS Code-enabled** `./scripts/test-all.sh --commit`,
   `./scripts/reload-vscode-extension.sh`, computer-use verification (squiggles with correct
   spans, hover type display, completion after `.`, format-on-command), screenshots.

### H6 — Remaining C# test-estate close-out

1. **Classification worksheet** (scratch, never a committed progress log): every remaining
   `tests/**/*.cs` file → product surface, assertion subject, migration target, residue verdict.
   Only two survivor categories: mechanical harness/guard (the keep-list) and external editor
   harness (VS Code TypeScript tests under `editors/vscode`). Mixed files SPLIT: product
   assertions to N#, guard stays. Every survivor gets a header comment naming its mechanical role
   and the product assertions it is forbidden to contain.
2. **Compiler semantic suites to N#**: parser/analyzer/semantic-model/binding-map/diagnostics/
   formatter/linter/systems/backend/native-runner assertions — pure kernel facts beside their
   kernels as `.tests.nl`; end-to-end behavior in native N# projects driving the fresh `nlc`
   process or temp projects. Diagnostic tests assert FULL tuples (code, message, line, column,
   length, explanation, hint, suggestions, snippet); schema/text goldens stay byte-exact.
3. **Tooling/SDK/LSP suites**: code-intel/query/fix/format/lint/project-file/SDK behavior →
   process-boundary N#; LanguageServer behavior moves to process-boundary N# tests speaking LSP
   JSON-RPC plus the TypeScript editor harness — C# survives only as harness self-test owning no
   LSP assertions. IDE-affecting migrations run under the full IDE verification rule.
4. **Guard the new estate**: all native projects in the gate step; the `.nl` repo-file-read guard
   covers new projects; add a source-scan guard failing when a NON-whitelisted C# test file
   contains `[Fact]`, `[Theory]`, `Assert.`, or direct product-surface calls — explicit, reviewed
   whitelist, so C# product tests cannot reappear silently.
5. **Estate audit**: `find tests -name '*.cs' | sort`;
   `rg -n "\[Fact\]|\[Theory\]|Assert\.|Should\(" tests --glob '*.cs'`;
   `rg -n "NSharpLang\.Compiler|NSharpLang\.Cli|NSharpLang\.LanguageServer" tests --glob '*.cs'` —
   every hit gone or whitelisted. Fresh product gate.

### H7 — Docs & memory close-out (after H5/H6 — docs describe reality, never aspiration)

1. **memory/ rewrite** (commit): `architecture.md` (already stale — cites the deleted Lexer.cs;
   point at the N# owners, single columnar path; "Current Compiler Debt" becomes a single-owner
   statement + enumerated mechanical glue); `components/lexer.md` + `error-reporting.md`
   rewritten around the N# owners; verify H5's parser.md/analyzer.md tense/paths; sweep
   `cli-toolchain.md`; `README.md` ownership rule becomes an end-state PRESERVATION rule (keep
   "Deleted Stale Docs" verbatim); `testing.md` example code de-C#'d, table refreshed — KEEP the
   "Emitted Assemblies Load Into Collectible Scopes" heading verbatim (a guard test's message
   cites it; `grep -rn "memory/" tests --include='*.cs'` before renaming anything);
   `limitations.md` gains the durable AOT notes (test-runner process isolation; metadata-reader
   items flagged by Tracks B/D).
2. **AGENTS.md + website + docs/** (commit): rewrite "Compiler Dogfood Architecture" as the
   end-state ownership rule (rename the heading — "dogfood" describes a finished transition); fix
   the "While the compiler rewrite … is in progress" phrasing; preserve every operational rule
   (dev.sh ladder, gate discipline, IDE mandate, project.yml philosophy) — reframe, not purge.
   CLAUDE.md is just `@AGENTS.md` — edit AGENTS.md only. Website: `cli-reference.md` for the
   approved `query ast` contract outcome; playground/tutorial copy loses "bounded execution
   subset". docs/:
   sweep for legacy-validation references.
3. **tasks/ audit + final sweep** (commit): delete completed/superseded entries (no archive), fix
   C#-owner references in survivors, update tasks/README.md; doc grep sweep
   (`Parser\.cs|Analyzer\.cs|Linter\.cs|Formatter\.cs|Lexer\.cs|ErrorReporting\.cs`,
   `validateWithLegacyAnalysis|DogfoodKernelLoader|DogfoodAdapter`, `moving to N#|being moved to
   N#|deletion debt|legacy fallback|PlaygroundRunner`, `Compiler.Dogfood`) — each remaining hit
   individually justified; path-validity check: every `src/...` path cited in memory/ exists.
   Docs-only gate is fast; still run it fresh.

Binding: no history archives, progress logs, or "how we got here" narratives — transition docs
re-train future agents to tolerate C# owners; when in doubt between rewriting and deleting a
section, delete. No hard-coded test totals/timings in docs. User auto-memory is out of scope.

### H8 — Final product-ownership audit (campaign close)

Not implementation, not doc cleanup: the proof. Runs after H7 so stale docs cannot hide behind
"code is clean" and vice versa.

1. **Survivor inventory** in the architecture/memory doc (not a new archive doc): every remaining
   non-N# file with compiler/tooling proximity gets file path; the ecosystem surface it adapts to
   (MSBuild, LSP wire protocol, process/socket/file IO, PE/ALC/runtime loading, NuGet/Zip/HTTP,
   Docker, editor harness); an explicit forbidden-responsibilities statement (owns no
   compiler/tooling decisions, diagnostics, schema shaping, query behavior, formatting/linting
   logic, lowering decisions, fallbacks, or product test assertions); the N# owner it calls into;
   a removal/re-evaluation path. **Default answer is NO**: a file is product ownership unless it
   affirmatively earns the glue classification — "it's small" is not a waiver.
2. **Product-code grep gates** (every hit deleted, migrated, or classified):
   ```
   rg -n "new Parser\(|new Analyzer\(|new Linter\(|new Formatter\(" src tests editors scripts
   rg -n "NSharpLang\.Compiler\.Ast|validateWithLegacyAnalysis|NSharpEmitValidateWithLegacyAnalysis" src tests editors scripts docs memory website/docs
   rg -n "DogfoodKernelLoader|DogfoodAdapter|Compiler\.Dogfood" src tests editors scripts docs memory website/docs
   rg -n "AstToJson|OutputFormatter\.[A-Za-z0-9_]+ToJson" src/NSharpLang.Cli src/NSharpLang.Compiler
   rg -n "class Parser|class Analyzer|class Linter|class Formatter" src/NSharpLang.Compiler src/NSharpLang.Cli src/NSharpLang.LanguageServer
   rg -n "CreateDelegate<|MethodInfo\.Invoke|Assembly\.Load\(|Mono\.Cecil|xunit\.runner\.utility" src tests
   rg -n "legacy fallback|moving to N#|being moved to N#|deletion debt" src tests docs memory website/docs AGENTS.md
   ```
   Expected result is not zero hits for every pattern; it is **no unclassified hit owns product
   behavior** (e.g. `MethodInfo.Invoke` in the test runner's host glue is inventoried glue).
3. **Test-estate gates**: the H6 audit greps re-run; every C# test hit whitelisted; every
   compiler/tooling assertion in N# or the editor harness; `find . -name '*.tests.nl' | sort`
   inventoried.
4. **Behavioral gates**: all native N# test projects run directly with the fresh CLI; final
   product gate — VS Code-enabled `./scripts/test-all.sh --commit` for the final campaign state
   (or, if only docs/inventory changed since the last IDE-verified commit, cite that evidence and
   run a fresh `VSCODE_TESTS=skip` gate for the docs commit). Read the GATE EXIT line.
5. **Close**: commit the audit with command summaries in the message; confirm goal.md matches the
   achieved state. This commit closes the campaign.

## Cross-track contract

- **From Track A** ([track-a-product-path.md](track-a-product-path.md), early): a fresh green
  product gate, the complete promised `.tests.nl` grammar/emission contract, TestCommand
  canaries, and machine-readable NL103 decline reasons (used by H2's corpus probe and H4's
  example labeling). The historical failure baseline is retired; any current red is concrete
  work to record, not a stash/`comm` comparison.
- **From Tracks C, D, G** ([track-c-syntax-frontend.md](track-c-syntax-frontend.md),
  [track-d-semantics.md](track-d-semantics.md), [track-g-tooling-ide.md](track-g-tooling-ide.md);
  endgame): front-end flips complete against their own exit criteria — C (silent AST producer,
  N# syntax diagnostics, provenance), D (AST model in N#, analyzer spine, stable N# API and
  non-LSP consumers retargeted), G (linter/formatter/code-intel/completion/LSP re-hosted and the
  final facade consumer removed). H5's Stage-0 grep audit is
  the enforcement: any live consumer outside the deletion set routes BACK.
- **From Track F** ([track-f-systems-analyzer.md](track-f-systems-analyzer.md)):
  `SystemsAnalyzer.cs` deleted; H verifies the absence before H5 commit 3 and routes back to F
  if it exists.
- **From Track B** ([track-b-kernel-binding-cli.md](track-b-kernel-binding-cli.md)): SDK-repin
  protocol (H1-3 kernel additions, H5-3's mandatory repin); DocQuery/CLI decision-core moves that
  the H3 Query/Doc groups pin behavior for.
- **From Track E** ([track-e-backend-emitter.md](track-e-backend-emitter.md)): the final campaign
  audit is blocked until N# owns lowering/member/type/typeref decisions and Cecil retirement is
  complete. H3 may consume E's modeled process surface, but no missing interop suite may be
  deferred at final close.
- **Co-signers (binding)**: front-end delete commits co-signed by the C, D, and G owners per the
  incident matrix — spans (C+D), NL401/NL202 richness (D), ToString display (D+G), runtime
  well-known-type loading (D) — plus G's IDE evidence. Each owner diffs the Stage-0 captures for
  their rows and records go/no-go.
- **Provides to everyone**: the `nlc test` gate step (H2) — the vehicle every track's `.tests.nl`
  coverage rides on; the process-boundary CLI suites (H3) — the safety net under B/C/D/G's
  ownership moves (coordinate Query/Doc migration with Track B; never a hard gate on B's ports,
  but the C# parity nets stay authoritative until their H3 successors are in the gate); keep-list
  stewardship; the final audit verdict that ends the campaign.
- **Contention**: `MultiFileCompiler.cs` (H4-1, H5-3) is shared with C/E/F — land after C's
  sequencing sub-arc, coordinate via the README contention ledger. `tests/Tests.csproj` is
  append-only for everyone. The H5-3 SDK repin goes through Track B's announce protocol.

## What NOT to do

- **Never delete a C# suite (or any single assertion) before its N# successor runs green IN THE
  GATE** — fresh run, GATE EXIT read — or before an explicit mechanical-guard classification
  exists. A `.tests.nl` file existing is not the proof; execution in the gate is. Silent coverage
  loss is this track's named failure mode.
- **Never write the literal `Assembly.Load(` in any `tests/**/*.cs` line, including string
  literals and expected-output fixtures** — the source-scan guard trips on literals (only
  `//`-tails stripped). Emitted assemblies load via `CollectibleAssemblyScope` (tests) / the
  collectible-ALC `LoadFromStream` pattern (src).
- No deleted path survives as a fallback: no RunXunitTests fallback, no PlaygroundRunner subset
  for declined examples, no Parser.cs "for the LSP" or "as an oracle" — replace-then-delete in
  the same arc, never preserve-both.
- No new C# product logic anywhere — new formatting/naming/ordering/JSON decisions go in `.nl`
  kernels; C# additions are array-marshaling glue at reflection/host boundaries only; no
  delegates passed into kernels (arrays in, plans/strings out). In H5, even N# porting is out of
  scope — a live consumer means a dependency track isn't done.
- No testing C# internals from N# (no reflection into Cli types from `.tests.nl`); in-proc kernel
  facts live beside kernels; C#-seam-only pins die with their owners, ENUMERATED, never silently.
- No weakened assertions in migration: byte-exact goldens stay byte-exact; exhaustive-set tests
  keep the negative half; diagnostic pins keep full tuples. Parity means equal or stronger.
- No test-support code in product kernels (BootstrapServices ships); no `.tests.nl` compiled into
  the product assembly via MSBuild (the `NSharpExcludeTests` generated-props fix, verified in the
  assets file); no loose PropertyGroups in csproj files (generated `obj/project.g.props` is the
  sanctioned place).
- No hardcoded or installed `~/.nsharp/bin/nlc` anywhere (RunNlc, gate step, probes) — the
  env-var-injected fresh Cli dll is the only target.
- Never migrate the keep-list (CollectibleAssemblyScope + guard, TestSdkFeed,
  ProcessStateCollection, GateStepInputSetGuardTests, SetupLocalScriptTests,
  VscodeIntegrationHarnessTests, DotnetRunnerTests, AnalyzerMetadataLoadContextTests,
  IlVerifyBaselineEmptyTests, Docker IntegrationTests, VS Code TypeScript harness).
- Don't touch the SDK's xunit/NUnit injection for user projects (load-bearing `dotnet test`
  route); don't solve the AOT test-execution problem here (document it). The former Dogfood
  parity corpus is already deleted and must not be recreated.
- No raw `dotnet test --filter` (documented hang); no `git add -A`; no history archives or
  progress logs; no batching H5's stages into one commit; no waiving a product C# owner as "glue"
  because it is small — H8's default answer is no.

## Track exit criteria

- [ ] `Program.Testing.cs` ≈150–200 LOC of inventoried host glue; RunXunitTests/XunitResultSink
      deleted; `xunit.runner.utility` gone from Cli.csproj; N# kernels own discovery decisions,
      display names, ranks, durations, and the schemaVersion-1 envelope with a byte-parity fact.
- [ ] The `nlc test` gate step exists in test-all-core.sh, cache-correct
      (GateStepInputSetGuardTests green), covering BootstrapServices + fixtures + examples +
      `tests/nsharp` + every later native project — proven executing in fresh `--commit` runs.
- [ ] The 16 kernel-proof files (1,453 LOC) and the 11 CLI suites (13,830 LOC / 494 facts)
      deleted with per-batch/per-group parity tables; the 6 emit-integration facts accounted for
      (behavioral rewrite or documented relocation); no product suite deferred at campaign
      close.
- [ ] `PlaygroundRunner.cs` deleted; Run executes columnar IL in a collectible ALC in both hosts;
      schema v2 unchanged; wasm bundle rebuilt; full catalog + tutorial browser-verified to the
      end with screenshots.
- [ ] Front-end deleted (Parser.cs 7,117; Ast/ 844; Analyzer.cs facade; Linter.cs 1,611;
      Formatter.cs 2,303; ErrorReporting.cs; AstNodeFinder.cs; FixApplicator.cs; wrapper blocks;
      reflection-idiom kernel halves); `validateWithLegacyAnalysis` /
      `NSharpEmitValidateWithLegacyAnalysis` gone from MultiFileCompiler, EmitIlAssembly.cs, and
      Sdk.targets; SDK repinned; `nlc query ast` v1 preserved byte-for-byte or a separately
      approved versioned migration completed with compatibility policy and goldens; all four
      incident behaviors byte-stable against pre-deletion captures with recorded C/D/G co-signs; VS Code
      gate + extension reload + computer-use screenshots green.
- [ ] Remaining C# test estate closed: no C# file under tests/ is the canonical assertion layer
      for compiler/tooling behavior; every survivor carries a header comment naming its role and
      forbidden assertions; a source-scan guard blocks new non-whitelisted C# product tests;
      grammar/diagnostic/schema pins all have named N# successors.
- [ ] Docs/memory rewritten to present-tense N# ownership; transition guidance deleted (not
      archived); grep sweeps clean or justified; cited paths exist; AGENTS.md reframed with all
      operational rules intact.
- [ ] Final audit committed: survivor inventory complete; product-code and test-estate grep gates
      show no unclassified product-owning hits; native projects run in the gate; final product
      gate fresh and green with VS Code-enabled evidence for the final IDE-affecting state;
      goal.md matches the achieved state.

## Gotchas & prior art

- **The 2026-07-01 incident is this track's founding trauma**: ~107 failures from "Delete
  fallback" commits that silently dropped spans / NL401+NL202 richness / ToString display /
  runtime well-known types — restored in 2383a4fa, 52c8a0d8, 19a9df58, e3702449 (study before
  H5). Capture-and-diff plus co-sign exists because these broke silently.
- **Exemplar deletions**: "Move lexer into N# bootstrap" (3fd604c2d) deleted Lexer.cs after
  static consumption — H5's pattern at scale. Banned dead ends: materialize-N#-parse-to-C#-AST
  (deleted d0884f4e) and re-parse-in-ILCompiler — never revive either to keep old tests
  compiling; rewrite tests against columnar tables.
- **String-name coupling breaks silently**: reflection-idiom kernels dispatch on C# AST type
  NAMES — post-Ast/-deletion they compile but return garbage; kernel retirement is in-commit,
  never "cleanup later".
- **`obj/project.g.props` regeneration trap**: InitialTargets writes only when the file is
  missing — after editing the csproj `Lines`, delete the stale generated file or new properties
  never appear.
- **Multi-file merge semantics**: `nlc test` concatenates a project's sources into one columnar
  program — display names must be unique project-wide; prefix with the kernel/suite name.
- **The JSON envelope is a public schema** (schemaVersion 1);
  `tests/fixtures/json-contract-root-keys.golden.json` pins CLI JSON root keys repo-wide. Byte
  parity, not "semantically equivalent" — capture the old serializer's literal output into the
  parity fact.
- **`testFramework: nunit` is live product surface** (project.yml knob; SDK injects NUnit 4.3.2) —
  the unified runner keeps the NUnit attribute-name sets; don't "simplify" them away.
- **Fresh-compiler-compiles-the-kernels risk** (H2-1): `nlc test` on BootstrapServices is a
  never-gated shape (whole corpus, one merged program, includeTests) — the genuine risk point;
  bisect declines with Track A's reasons; a reduced test project is a scope deviation to surface,
  not a quiet swap.
- **Guard blind spot**: the repo-file-read self-discovery guard scans only `.cs` — N# test
  sources escape it until H3's extension; the UNIT hash's breadth covers cache correctness
  meanwhile.
- **Console capture is process-global** (H4): SetOut/SetError affects concurrent in-proc test
  callers — restore in finally; serialize the run-path test class if its collection is parallel.
- **Docs train agents**: transition-era strategy logs were deleted precisely because they taught
  agents to preserve legacy owners — H7's delete-don't-archive rule is load-bearing.

All facts verified 2026-07-02 at commit 9538ab66; re-verify line anchors and inventories against
the live tree before each sub-arc — upstream tracks move them by design.

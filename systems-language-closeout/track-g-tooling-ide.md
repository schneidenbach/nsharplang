# Track G — Tooling & IDE: linter, formatter, code intelligence, and the LSP re-host

> **LIVE STATUS (audited at `fb856ee46`):** the XML-doc stub deletion landed; the linter,
> formatter, code-intelligence, completion, handler, and front-end ownership work remains.
> Every commit changing a surface reachable from the IDE uses the VS Code-enabled gate,
> extension reload, computer-use verification, and screenshots—even when parity is expected.
> Any numbered "IDE gate" below is acceptance evidence that runs before committing the
> immediately preceding production flip; it is never a later checkpoint commit. Candidate-only
> or test-harness-only work is the sole backend-gate exception.
> The old skipped-gate allowances below are void. Comment/trivia parser work contends on the
> consolidated parser-kernel file. See [STATUS.md](STATUS.md).

**Owner model.** One senior owner runs this entire track, spanning both the producer ports
(linter, formatter, code-intel, completion — sub-arcs 1–4) and the LSP handlers that consume
them (sub-arcs 5–11). The alternative is a staffing handoff exactly at the shared API boundary
between "what the tooling computes" and "what the editor shows" — the worst possible seam,
because every LSP arc consumes the producer kernels this track's first half creates, and every
parity bug straddles the boundary. A single owner also amortizes the expensive fixed cost of
this track: the VS Code verification rig (extension reload script + computer-use visual
verification + the 21 VS Code integration suites) is set up ONCE at track start and reused for
every IDE-affecting stage, instead of being re-learned per slice. **If staffing forces a
split, cut between sub-arc 4 and sub-arc 5** — tooling owner (1–4, with full IDE evidence on
every production-reachable commit) and
IDE owner (5–11, always VS Code gates), with a mandatory handoff bundle from the tooling owner:
kernel API inventory (every public N# entry point with signatures), the producer golden/fixture
corpus and how to regenerate it, shadow-mode setup notes, VS Code rig notes (reload script
quirks, workspace-trust/stale-server pitfalls), and the LSP consumer map (which handler consumes
which kernel). Never split mid-LSP: sub-arcs 5–11 share the rig, the
handler inventory, and the shadow-mode harness.

All facts below verified 2026-07-02 at commit 9538ab66.

## Mission & end state

Every tooling and IDE decision executes in N#:

- All ten lint rules, the lint scope machinery, and the known-namespace data tables run in
  BootstrapServices kernels; `Linter.cs` is a <50 LOC shell.
- `nlc format` is an N# engine over the **columnar tables** (tokens + node tables), not an AST
  walker; `Formatter.cs` is a ~50 LOC `FormatSafe` shell whose reparse gate stays on the C#
  Parser only until Track C's N# syntax authority exists.
- Every AST-walking code-intelligence producer (symbols, outline, call graph, implementors,
  hover assembly, diagnostics envelopes, definition/reference building) and the full
  type-at-position + completion engine are N# kernels; CLI (`nlc query`), daemon, batch,
  playground, and LSP all consume them with byte-stable output.
- The LanguageServer's handlers are thin protocol adapters: every classification, structure,
  display, ranking, matching, and refusal decision lives in kernels behind plain result
  records. No OmniSharp type appears in any kernel signature.
- `DocumentManager.UpdateDocument` runs the N#-owned front-end (columnar parse → N# analyzer →
  N# linter). The LanguageServer is no longer a load-bearing consumer keeping `Parser.cs` /
  `Analyzer.cs` / `Lexer.cs` / `Linter.cs` alive. This track deletes the zero-consumer
  `Analyzer.cs` facade with the final IDE-consumer flip and hands H only an explicit checklist
  of other zero-policy remnants owned by their producing tracks.
- The IDE experience is UNCHANGED throughout: the ~8,000-line LSP unit-test corpus and all 21
  VS Code integration suites pass at full fidelity at every stage.

## Why this is one track

1. **Producer → consumer chain.** The linter port feeds LSP diagnostics; the code-intel
   producers feed hover/definition/references; type-at-position + completion feed the LSP
   completion convergence; the formatter feeds the LSP formatting handler. Splitting producers
   from consumers puts the handoff exactly where the parity bugs live.
2. **One brain, four surfaces.** LSP, `nlc query`, the daemon, and the playground must share
   one implementation of every behavior (completion is currently TWO independent engines).
   Convergence decisions need one owner who sees all four surfaces.
3. **The VS Code rig is expensive and shared.** Every IDE-affecting stage requires the full
   `./scripts/test-all.sh --commit` with VS Code tests ON, plus
   `./scripts/reload-vscode-extension.sh`, plus computer-use visual verification with
   screenshots (non-negotiable per AGENTS.md — unit tests pass while the real editor breaks on
   workspace trust, stale server binaries, cursor positioning). One owner sets this up once
   and gets fast at it; eight owners each pay the setup tax.
4. **The re-host (sub-arc 11) is the payoff of everything before it.** Sub-arcs 5–10 move
   every handler decision behind kernel interfaces precisely so the final front-end swap
   collapses to `UpdateDocument` plus kernel input types. Only the person who built those
   interfaces knows where the seams are.

## Current state (verified 2026-07-02, commit 9538ab66)

### Linter — `src/NSharpLang.Compiler/Linter.cs` (1,611 LOC, C#-owned)

- Entry `Linter.Lint(CompilationUnit, string? filePath, string? sourceText)` at L21-26
  constructs an internal `LintVisitor` (L33-1611) — the three-line entry is all that survives.
- Ten rules: NL001 unused variable, NL002 missing import, NL003 value-type null check, NL004
  async without await, NL006 unreachable code, NL010 unused import, NL011 empty catch, NL012
  unused parameter, NL016 redundant null check, NL020 shadowing.
- **NL012 is the sharpest edge** (`MarkVariableUsed`, L929-996): a name use resolves to the
  NEAREST scope binding it, then credits only the parameter frame whose dedicated parameter
  scope **`ReferenceEquals`** that resolved scope. Captured-parameter reads in nested
  lambdas/local functions count; a shadowing local/loop/catch/lambda binding correctly does
  NOT credit the enclosing parameter. This fixed a build-blocking false positive once and is
  pinned by `tests/LinterUnusedVariableTests.cs` (471 LOC).
- **Recursion-depth guard THROWS** (`InvalidOperationException` with line/column/type, depth >
  100, L734-737) — pinned behavior; lint crashes loudly on pathological ASTs rather than
  silently truncating. The circular-visit guard (reference-equality set) still marks
  identifiers used on skip — load-bearing against false NL001.
- **~240 LOC data tables**: `_knownNamespaceTypes` L1273-1421 + `_knownNamespaceMembers`
  L1422-1513 (NL010), plus TWO drifted inline `commonTypesMap` copies (NL002).
- Default expression traversal routes through the N# `AstChildrenCore.Of` kernel — fail-safe: a
  node missing from the switch cannot silently skip a subtree.
- Already N# (reuse, never re-port): `LinterBindingUsageCore` (NL001/NL012 gating + messages),
  `LinterSuppressionParser`, `LinterImportMetadata`, `LinterFileImportUsage`, `LinterConfig`,
  `LinterDiagnosticModels` (the `Diagnostic` model every consumer holds),
  `DiagnosticSpanResolver`, `CodeIntelligenceTextUtilities`, and the fully-N# NL970 strict
  rules (`StrictLintDiagnostics` — not this track).
- Consumers (signature stays put): `LintCommand.cs:119`, `DocumentManager.cs:287`,
  `MultiFileCompiler.cs:367`, `CodeIntelligenceService.cs:304`, `FixApplicator.cs:40`,
  `PlaygroundCompiler.cs:379`. Oracles: `tests/LinterTests.cs` (1,380 LOC),
  `LinterUnusedVariableTests.cs`, `ExampleLintTests.cs`, `FixApplicatorTests.cs`.

### Formatter — `src/NSharpLang.Compiler/Formatter.cs` (2,303 LOC, C#-owned)

- **`FormatSafe` L29-57 is contract** (hardened deliberately after a swallowed-failure bug):
  format → re-lex (N# `Lexer`) → re-parse (C# `Parser`) → abort-with-ORIGINAL-source on any
  error → format the reparse output AGAIN and abort if not byte-identical (idempotence). On
  any failure return the original source with warnings, never best-effort output. This shell
  survives the track; the reparse gate stays on the C# Parser until Track C
  (track-c-syntax-frontend.md) delivers N# syntax authority.
- Printer arms: declarations L208-964 (~16 arms: function, class, soa record, interface,
  union, enum, field, property, constructor, indexer, test, plus struct/record/type-alias/
  newtype/preprocessor); statements L966-1529 (~25 arms incl. `foreach`→`for x in`
  canonicalization, try/catch/finally, allow/alloc/unsafe, assert/assert-throws, yield);
  expressions L1531-1923 (~30 arms incl. raw/normal interpolated strings, match,
  line-length-aware object-initializer wrapping). Patterns L1924-2042; modifiers +
  `ShouldPreserveExplicitCasingVisibility` L2142-2189 — **semantics-load-bearing** (PascalCase
  = public / camelCase = file-private; dropping/adding an explicit visibility keyword flips
  accessibility).
- Blank-line preservation via `_lastEmittedSourceLine`; comment interleaving from
  `List<CommentTrivia>`; column-tracked wrapping (`GetCurrentColumn` reads the live output
  buffer — an off-by-one breaks idempotence intermittently on long initializers).
- Already N#: `FormatterImportOrderer` (import ordering, enforced, no C# fallback),
  `OperatorFacts` (all binary/unary/assignment operator text), `FormatterConfig`,
  `FormatResult`, `FormatCommandKernels`, `Lexer.nl` (reparse-gate lexer AND the
  `CommentTrivia` oracle).
- **CRITICAL CORRECTION — comments are NOT in the columnar token array.** The columnar
  scanner's `TokenizeMetadataCore` consumes `//` and `/* */` with `continue` and emits NO
  token row (built for emission speed). Comment capture must be added to the token scanner
  BEFORE any printer work — as a side table, never interleaved (indentation-brace insertion
  and newline compaction key off the raw stream's exact shape). The N# product `Lexer.nl` DOES
  capture `CommentTrivia(Line, Column, Text, IsMultiLine)` and is the cross-check oracle.
- Columnar front-end available to build on: the consolidated
  `CompilerServices/ColumnarParserKernels.nl` (scanner plus declaration/expression/type/member
  regions), `ColumnarNodeTable.nl` (post-order node table with kinds/spans/children accessors),
  and `ColumnarInterpolationSplitter.nl`. Formatter trivia extensions contend on the consolidated
  parser file and require one coordinated writer.
  It parses 100% of the compiler's own source and is 2.4x faster than the C# parser — but it
  was built for emission, so expect span/trivia fidelity gaps to audit and close.
- Consumers: CLI `Program.cs` `FormatSource` (FormatSafe at :750), LSP
  `DocumentFormattingHandler.cs:51`, `PlaygroundCompiler.cs:87-88`. **NOT a consumer:**
  `OnTypeFormattingHandler.cs` (own raw-text indent heuristics — leave it alone). Oracle:
  `tests/FormatterTests.cs` (2,146 LOC, 116 assertions, ALL through two private helpers at
  L21-39 — repointing the suite = editing those two helpers only).

### Code-intelligence producers — `CodeIntelligenceService.cs` (1,803 LOC) + `CompletionEngine.cs` (569 LOC)

- CIS regions that move: symbols (`DeclarationToSymbol` L904-1049, per-kind switch),
  outline (`DeclarationToOutlineEntry` L1049-1146), call graph (`CollectCallSites*`
  L522-733), implementors (L734-791), diagnostics merge (`GetDiagnostics`/`ToDiagnosticResult`
  L142-321), hover assembly (L460-521), definition/reference building (L358-459, L1573-1620),
  thin text-helper wrappers L1629-1755 (delete — inline the kernel calls).
- CIS regions that stay C#: `LoadProject`/`ProjectSnapshot` glue (MultiFileCompiler-coupled
  host edge), parse boundaries (die with the re-host), file IO (`GetSourceText`).
- The type-at-position region (~500 LOC: `GetTypeAtPosition` L329-357,
  `ResolveTypeUseAtPosition` L821-886, resolution block L1146-1556) and the CompletionEngine
  remainder (~450 LOC) are their own sub-arc. `ResolveTypeReferenceToTypeInfo` /
  `FlattenUnionTypeReference` are DUPLICATED across the two files — unify to one kernel copy.
- `AstNodeFinder.cs` is a 15-LOC pure shim over `AstNodeFinderCore.nl` (6 call sites incl. LSP
  CompletionHandler:198 and HoverHandler:67) — deleted in sub-arc 4.
- Result models are ALREADY all N# (`CodeIntelligenceModels.nl`, call-graph/implementor/
  completion models, `TypeInfoModels.nl`, `SemanticModel.nl`); fact kernels exist
  (`DeclarationFacts`, `TypeReferenceFacts`, `BindingLookupKernels` + `BindingMap`,
  `CodeIntelligenceSourceTextKernels`, `CompletionEngineKernels`, `CompletionDeclarationFacts`).
  These sub-arcs relocate producers only — outputs are a versioned JSON contract
  (schemaVersion=1) and must stay byte-stable.
- Oracles: `tests/CodeIntelligenceTests.cs` (1,357 LOC), `CompletionEngineTests.cs`,
  `AstNodeFinderTests.cs`, `CliParityAuditTests.cs`, daemon/batch suites.

### LanguageServer — `src/NSharpLang.LanguageServer/`

- **Dead shell:** `Services/XmlDocReader.cs` — 10 LOC, empty class (a prior commit gutted the
  body, left the shell); one DI registration in `Program.cs` L46; one unused ctor parameter on
  `TypeResolver` (L69, never stored).
- **Diagnostic conversion:** `Services/LspDiagnosticConverter.cs` (100 LOC, internal static —
  `FromCompilerError` L14-28, `FromLinterDiagnostic` L30-48, `BuildRange` L69-88 with
  1-based→0-based, exclusive-end, min-length-1, end clamped to source-line length) is ALREADY
  the single conversion owner. The real duplication is the **publish loop, copy-pasted three
  times**: `TextDocumentHandler.PublishDiagnostics` L124-142,
  `DidChangeWatchedFilesHandler.PublishDiagnostics` L106-124, and the `Program.cs`
  `OnInitialized` initial-workspace-scan loop L111-137 — plus two one-line
  `ConvertCompilerErrorToDiagnostic` forwarding shims.
- **End-line estimation, genuinely triplicated with drift:** `SelectionRangeHandler.cs`
  L398-428 (`EstimateEndLine`, plus the superset family through L551: block / statement /
  if-else-chain / try-finally / switch estimators), `FoldingRangeHandler.cs` L236-298
  (byte-identical scan), `DocumentSymbolHandler.cs` L208-239 — **drift point: this copy takes
  a NULLABLE `sourceLines`** and guards it; the other two require non-null. Brace-depth scan:
  from the node's 1-based line, per-char `{`/`}` counting, return the line closing depth 0
  after at least one open, fall back to the start line.
- **DocumentManager** (`Services/DocumentManager.cs`, 1,450 LOC): `UpdateDocument` runs per
  keystroke — `new Lexer` at L246, `new Parser` at L250, `_sharedAnalyzer.Analyze` at L278
  (field at L25, constructed with `LoadSystemAssemblies()`), `LinterConfig.FromEditorConfig` +
  `new Linter().Lint` at L286-288, then symbol extraction into `DocumentState`. Also owns the
  ~600 LOC AST→symbol extraction block (L796-1400) that the navigation sub-arc ports, and the
  kernel-backed `FindProjectDefinition/References/Hover` delegates (stay as-is).
- **Handlers with C#-owned decisions:** SemanticTokensHandler (1,045 LOC), CompletionHandler
  (705 — a full SECOND completion engine), CallHierarchyHandler (768), SelectionRangeHandler
  (552), SignatureHelpHandler (548), TypeHierarchyHandler (414), InlayHintHandler (373),
  FoldingRangeHandler (299), EditorUtilities (299), GoToImplementationHandler (285),
  DocumentSymbolHandler (262), WorkspaceSymbolHandler (179), PrepareRenameHandler (171),
  DocumentHighlightHandler (142), RenameHandler (137), TypeResolver (573 — half host
  reflection, half portable decisions).
- **Keyword-list drift:** at least four copies of the keyword vocabulary exist
  (CompletionHandler L27-38 — the superset; CompletionEngine's smaller keywords+modifiers
  split; HoverHandler's inline array; PrepareRenameHandler `IsKeyword` L133-151; plus the
  tmLanguage regexes). Convergence to ONE facts kernel happens in sub-arc 7.
- **Test corpus:** `tests/LanguageServerTests.cs` (4,223 LOC, 161 tests),
  `LanguageServerDiagnosticsTests.cs` (3,182 LOC, 92 tests — the **span-fidelity canary**: it
  pins exact published ranges/codes/messages, and it is the first suite that catches a
  dropped-span regression of the 2026-07-01 class), `LanguageServerWorkspaceDiagnosticsTests.cs`
  (403), `LanguageServerAutoImportTests.cs` (198), 21 VS Code suites in
  `editors/vscode/test/suite/`. `LanguageServer.csproj` has `InternalsVisibleTo("Tests")` —
  several tests reach handler internals directly and must be RETARGETED at kernels, not
  deleted.
- **Test Explorer contract:** `editors/vscode/src/testController.ts:126` discovers tests via
  `DocumentSymbol.detail === 'test'`. Any drift silently kills the Test Explorer while unit
  tests stay green.

## Standing harness

Set up at track start; every sub-arc reuses it.

1. **The VS Code rig (set up ONCE, amortize).** `./scripts/reload-vscode-extension.sh` kills
   VS Code, rebuilds the language server, repackages + reinstalls the VSIX, reopens a sample
   project. Computer-use drives the real editor and screenshots each verified behavior.
   Pitfalls the rig must absorb up front: **stale server binaries** (the packaged VSIX can
   carry an old compiler — always repackage before any visual check, or you verify the old
   binary), **workspace trust** prompts blocking the server, cursor-positioning flakiness, and
   computer-use timeouts (kill the processes and retry; never downgrade to "unit tests
   passed"). Keep one canonical sample project with: comments + blank lines, a match
   expression, an object initializer near the line limit, a class implementing an interface,
   nested lambdas capturing parameters, a `*.tests.nl` file, and a file with a deliberate
   syntax error.
2. **Parity fixture discipline.** Every port stage runs both implementations (C# authoritative,
   N# candidate) over the relevant fixture corpus and asserts identical ordered result tuples
   BEFORE the flip; the parity harness is deleted in the flip commit (both sides then call one
   engine; the real suites are the permanent guard). Golden-capture CLI output before each
   stage; byte-diff after. All behavioral probes run against a fresh
   `dotnet build src/NSharpLang.Cli` + that `Cli.dll` — the installed `~/.nsharp/bin/nlc` is
   frequently stale and gives false "broken feature" results.
3. **N#-pipeline shadow mode (recommended by the 2026-07-02 adversarial review — build it in
   sub-arc 5).** A thin, test-harness-only mode that runs whatever N# front-end surface exists
   (Track C's columnar parse diagnostics, Track D's analyzer spine as it lands, this track's
   linter) alongside the C# path over the LSP fixture corpus and diffs full tuples. It is NOT
   a product fallback and never serves editor answers — it exists so sub-arcs 6–10 can
   validate each kernel against the FUTURE data path while it is still non-authoritative,
   shrinking sub-arc 11's blast radius from "everything at once" to "already-diffed inputs".
   Grow it incrementally as Tracks C/D land surfaces; it becomes sub-arc 11's Stage-2 parity
   harness and dies with it.
4. **Test-evidence ladder** (per README campaign rules): `./scripts/dev.sh <pattern>` inner
   loop (never raw `dotnet test --filter` — documented xUnit hang); full
   `dotnet test tests/Tests.csproj` for current breadth evidence; genuinely inert candidate-only
   stages may gate with `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`;
   every production-reachable stage—including linter, formatter, code-intelligence, and
   completion producer commits before the handler re-host—gates before that commit with the
   FULL `./scripts/test-all.sh --commit` + reload + computer-use. Stage = commit, with an
   `Evidence:` line. A later cumulative checkpoint never substitutes for per-commit evidence.

## Sub-arcs

Order is dependency-driven: 1 proves large-visitor-in-N# mechanics on the cheapest target;
2 reuses them on the columnar-table frontier; 3–4 empty the code-intel file in sequence (same
file — never interleave); 5 de-duplicates the LSP before anything is ported (port ONE copy,
not three); 6–10 move every handler decision behind kernels; 11 swaps the front-end.

### Sub-arc 1 — Linter core to N# (`LinterCore.nl`); `Linter.cs` → shell

Blocked on Track D's first sub-arc (AST model in N#) so the kernel dispatches on TYPED N# AST
nodes instead of multiplying the `GetType().Name` string-reflection idiom into 1,500 more LOC
(a renamed node would silently skip a subtree ⇒ false NL001/NL010).

- **Stage 1 — `LinterKnownNamespaces.nl`.** Move the NL002/NL010 data tables: merge the two
  drifted `commonTypesMap` copies (diff first; keep the union, note disagreements in the
  commit), port `_knownNamespaceTypes`/`_knownNamespaceMembers` verbatim. Flip
  `CheckMissingImport`/`CheckMissingImportForType`/`CheckUnusedImports` to the kernel and
  DELETE the C# tables in the same commit (~300 LOC). Evidence: `./scripts/dev.sh Linter`;
  `nlc lint` over `examples/` byte-identical.
- **Stage 2 — scope machinery + NL001/NL012/NL020.** Stub-probe unproven kernel shapes first
  (~13s/build): reference-equality set (if `ReferenceEqualityComparer.Instance` is
  inexpressible, a `List<object>` + `object.ReferenceEquals` scan is behaviorally identical
  under the 100-depth cap); model scopes as a small class (`LinterScope` holding
  name→`LinterVariable{Line,Column,Used}`) instead of tuple-valued dictionaries. Port
  PushScope/PopScope/DeclareVariable/CheckShadowedVariable/MarkVariableUsed EXACTLY —
  **the NL012 resolve-to-nearest-scope-then-`ReferenceEquals`-the-frame-scope semantics move
  verbatim, comment included**. Port the AddDiagnostic funnel (rule-enabled → suppression set
  → `DiagnosticSpanResolver.Resolve`, same short-circuits), the full traversal skeleton with
  the recursion-depth THROW and the mark-used-on-skip circular guard, default expression case
  through `AstChildrenCore.Of`. C# `LintVisitor` stays authoritative; add a parity test
  running BOTH engines over the linter fixture corpus asserting identical
  (Code, Message, Line, Column, Length, Severity, Suggestion) tuples for this rule subset.
- **Stage 3 — remaining rules.** NL002/003/004/006/010/011/016, `ContainsParserErrorPlaceholder`
  (~30 arms — suppresses lint on parser-recovered code), string-interpolation identifier
  credit. Message strings move CHARACTER-FOR-CHARACTER (tests assert on them; CLI JSON is a
  versioned contract). Extend parity to the full rule set + adversarial fixtures (parser-error
  placeholders, near-cap nesting, captured params in nested lambdas, shadowing locals over
  params, interpolated-string-only usage).
- **Stage 4 — the flip and IDE acceptance.** `Linter.Lint` delegates to `LinterCore.Lint`; DELETE `LintVisitor`
  (L33-1611) and the parity harness in the SAME commit; `grep -rn "LintVisitor" src tests`
  empty. All six consumers flip implicitly. Evidence: `dev.sh Linter` + `dev.sh Fix`, the full
  unit suite green, `nlc lint` byte-identical on a ten-rule fixture (fresh Cli.dll). Before
  this commit, run the full VS Code-enabled `./scripts/test-all.sh --commit`, reload/reinstall
  the extension, and visually verify lint squiggles and clear-on-fix behavior with screenshots.
  Expected identical diagnostics do not waive the IDE rule; `LanguageServerDiagnosticsTests`
  is the span canary. There is no separate later gate commit.

### Sub-arc 2 — Formatter to N# over columnar tables; `Formatter.cs` → FormatSafe shell

Blocked on Track B's static kernel binding (track-b-kernel-binding-cli.md) — the formatter
kernel calls the columnar parser kernels kernel-to-kernel with typed entry points, and this
sub-arc EXTENDS their signatures (comment capture), which must be a plain typed edit, not a
reflection-ABI change. Do this after sub-arc 1: the linter proves the mechanics on the cheaper
target. Do NOT port the formatter as an AST walker — that route cements the C# AST this
campaign deletes (rejected; the columnar direction is the standing user decision).

- **Stage 0 — fidelity audit.** Map all ~71 printer arms + patterns/attributes/type-refs/
  modifiers to their columnar source of truth; record gaps as checked-in skipped round-trip
  probes (unskipped as later stages close them). Known audit points: attributes, type aliases,
  newtype, test/setup/teardown, preprocessor lines, doc comments, raw interpolated strings,
  `>>` splitting in nested generics, blank lines via raw newline tokens.
- **Stage 1 — comment capture in the columnar scanner.** Add a comment SIDE TABLE entry point
  (`TokenizeColumnarSourceWithCommentsInto`: kinds 0=`//`/1=`/* */`, starts, lengths, lines,
  columns, count) recording rows at the two skip sites in `TokenizeMetadataCore`. NEVER
  interleave comment tokens into the raw stream. Differential tests: old vs new entry point
  byte-identical over the repo `.nl` corpus; comment table vs `Lexer.nl` `CommentTrivia`
  identical sets (the product-path oracle). The emission path pays nothing.
- **Stage 2 — emit-state machine + declaration printers** (`FormatterCore.nl` +
  `FormatterDeclarations.nl`). Entry
  `Format(source, fileName, config, includeComments): string` runs tokenize + declaration scan
  + per-declaration parses internally. Port first: emit state (indent, comment cursor,
  last-emitted-source-line), the comment/blank-line engine against the side table + raw
  newline tokens, top-level layout (imports via `FormatterImportOrderer`), then the ~16
  declaration printers with bodies stubbed to source-slice passthrough. Port
  `ShouldPreserveExplicitCasingVisibility` VERBATIM here (headers need it;
  semantics-load-bearing). Parity harness: N# output == C# `Format(ast, comments)`
  byte-for-byte over FormatterTests fixtures + repo `.nl` files, with an explicit shrinking
  red-list for body-level fixtures.
- **Stage 3 — statement/expression/pattern printers** over `ColumnarNodeTable` (operator text
  via `OperatorFacts` kernel-to-kernel; interpolation via `ColumnarInterpolationSplitter` +
  source slices). Port the wrapping engine exactly — current-column computation against the
  output buffer must match or idempotence fails intermittently; add fixtures at
  MaxLineLength±1. Close fidelity gaps by EXTENDING the parser kernels (new span/value
  columns, node kinds), never by reading the C# AST. Drive the red-list to zero: byte parity
  on everything + double-format fixpoint over the whole corpus. One commit per printer family.
- **Stage 4 — the flip and IDE acceptance.** `Formatter.cs` → ~50 LOC shell: source-based `Format` delegating to
  the kernel; `FormatSafe` keeps BOTH gates exactly (reparse on C# Parser until Track C's
  authority; idempotence = kernel called twice; original-source-on-failure). Delete the AST
  printing engine (~2,240 LOC) in the same commit. Repoint FormatterTests' two private
  helpers; keep the corpus fixpoint assertions as the permanent idempotence guard. Corpus
  gate: `nlc format` over the entire repo TWICE — second run zero diffs; already-canonical
  files byte-unchanged. Before this commit, run the full VS Code-enabled
  `test-all.sh --commit` + reload + computer-use: Format Document on the canonical sample
  (comments, blank lines, match, near-limit initializer); second format is a no-op; a file
  WITH syntax errors formats to NOTHING (safety gate) rather than mangling. There is no
  separate later gate commit.

### Sub-arc 3 — Code-intelligence producers to N#

Blocked on Track D's AST model (typed kernels, same reasoning as sub-arc 1). Public method
signatures stay put; JSON output byte-stable (golden-capture before, byte-diff after, every
stage). Stages 1–3 each delete production code that feeds IDE behavior, so each one carries the
full VS Code-enabled gate, extension reload, affected-feature computer-use verification, and
screenshots before its own commit.

- **Stage 1 — symbols + outline** (`CodeIntelligenceSymbolProducers.nl`): the per-kind
  switches + `FormatModifiers` verbatim. Per-kind quirks are contract: SoaRecord synthesizes
  Field symbols with `TypeName:"soa"`; enum/union members carry line/column 0; union cases
  filter through the exported-identifier predicate; `DefaultValue?.ToString()` display
  preserved exactly (ToString display was a 2026-07-01 casualty). Delete the C# switch bodies
  same commit. Probes: `nlc query symbols|outline` (text + `--json`) byte-identical.
- **Stage 2 — call graph + implementors** (dedicated kernels): the four `CollectCallSites*`
  walkers + `ExtractCalleeName`, `CollectImplementors` + `InterfaceNameMatches` with exact
  per-kind base-vs-interface logic. A missed traversal arm silently drops edges — the arm set
  is the checklist. Probes: `nlc query callgraph` (± filter, small `--limit`),
  `nlc query implementors`.
- **Stage 3 — diagnostics merge, hover assembly, definition/reference building.** Severity
  mapping, snippet attach, relative paths, the lint-envelope loop (the `Linter` shell call
  stays the boundary; per-file `LinterConfig.FromEditorConfig` survives), hover composition
  taking already-resolved type/definition inputs (do NOT drag type resolution in — that is
  sub-arc 4), `BuildReferenceResultsFromDeclaration` + `FindDefinitionLocation*`. Delete the
  text-helper wrapper block where call sites are in this sub-arc's regions. Probes:
  `nlc check --json`, `nlc lint --json`, `nlc query hover|definition|references`, one daemon
  round-trip.
- **Stage 4 — cumulative acceptance checklist, not a separate commit:** confirm the per-commit
  evidence from Stages 1–3 covers symbols, hover, definitions, references, and diagnostics.
  Re-run the full IDE evidence only if the combined path changed after those commits; this
  checklist cannot repair a missing earlier gate.

### Sub-arc 4 — Type-at-position & completion engine to N#

Immediately after sub-arc 3 (same file — the sequencing avoids edit collisions in
`CodeIntelligenceService.cs`).

- **Stage 1 — `CodeIntelligenceTypeResolution.nl`**: the whole L1146-1556 region +
  `GetTypeAtPosition` + `ResolveTypeUseAtPosition`, ported in dependency order; the duplicated
  `ResolveTypeReferenceToTypeInfo`/`FlattenUnionTypeReference` become ONE kernel copy and both
  C# copies die. Delete the C# bodies in the same commit. Probe: `nlc query type` byte-diff.
- **Stage 2 — `CompletionEngineCore.nl`**: keyword/modifier/primitive data, member + identifier
  completions, `FindMemberAccessAtPosition` + `GetNearbyColumns` (**the −1-line/−1-column then
  exact probe order is deliberate cursor tolerance — port exactly, tests encode it**), the
  formatting families. `CompletionEngine.cs` → ≤~80 LOC entry shell; signature unchanged
  (QueryCommand, BatchQueryRunner, DaemonServer, LSP CompletionHandler untouched).
- **Stage 3 — delete `AstNodeFinder.cs`**: retarget the 6 call sites to
  `AstNodeFinderCore.FindExpressionAtPosition(...) as Expression`.
- **Display seam**: if the nullability-metadata formatting for `ReflectionTypeInfo` is still
  C#-owned when this runs (its port is Track B's independent-filler sub-arc,
  track-b-kernel-binding-cli.md), apply it at the thin C# shell AFTER the kernel returns, marked
  `// HOST-SEAM`, never as a delegate passed into a kernel.
- **IDE verification (mandatory — completions and hover types flow through the LSP)**: full
  VS Code gate + reload + computer-use: `.`-triggered member completion shows the same
  members; hover on a local shows the resolved type. Screenshots.

### Sub-arc 5 — LSP consolidation + shadow mode

No cross-track dependencies — can start the moment the owner has the rig up (it is also the
rig's shakedown cruise). Pure consolidation: zero behavior change, one owner per behavior, so
sub-arcs 6–10 each port ONE copy instead of three.

- **Stage 1 — delete the `XmlDocReader` stub**: the file, the `Program.cs` L46 DI
  registration, the unused `TypeResolver` ctor parameter (never stored — pure signature
  change). `grep -rn XmlDocReader src editors` empty.
- **Stage 2 — single diagnostic-publish path**: one shared
  `ToLspDiagnostics(DiagnosticsPublication)` helper beside `LspDiagnosticConverter`; collapse
  the three publish loops (TextDocumentHandler L124-142, DidChangeWatchedFilesHandler
  L106-124, `Program.cs` OnInitialized L111-137 — the easy one to miss) and delete the two
  forwarding shims. Conversion math (`FromCompilerError`/`FromLinterDiagnostic`/`BuildRange`)
  untouched — `LanguageServerDiagnosticsTests` + `LanguageServerWorkspaceDiagnosticsTests` pin
  exact ranges/severities/codes; any diff means the consolidation changed behavior — stop.
- **Stage 3 — one end-line estimator**: `Services/AstEndLineEstimator.cs` (internal static,
  deliberately temporary C#) containing SelectionRangeHandler's SUPERSET family, adopting
  DocumentSymbolHandler's nullable-`sourceLines` signature (null falls through to the
  start-line fallback; the other two callers always pass non-null — behavior unchanged).
  Delete all three private copies same commit. Add direct unit tests (nested braces,
  brace-on-header-line, no-close fallback, else-if chain, try/catch/finally, switch, null
  sourceLines) — these become sub-arc 8's port oracle.
- **Stage 4 — stand up shadow mode** (see Standing harness #3): a test-harness-only
  double-run of the available N# front-end surfaces vs the C# path over the LSP fixture
  corpus, diffing full diagnostic tuples and (as Track D lands them) semantic answers at
  sampled positions. Explicitly NOT reachable from product code — no flag, no fallback. Wire
  it so each later sub-arc can register its kernel's inputs for diffing.
- **Stage 5 — IDE gate**: full VS Code `test-all.sh --commit` + reload + computer-use
  (squiggle range on an induced error, Outline tree, fold/unfold, expand-selection, **Test
  Explorer discovery** — DocumentSymbolHandler was touched and `testController.ts` keys on
  `detail === 'test'`).

### Sub-arc 6 — Semantic tokens to N# (compressed)

Handler: `SemanticTokensHandler.cs` (1,045 LOC → ~150 LOC protocol adapter). Kernels to
create: `SemanticTokenModels.nl` + `SemanticTokenKernels.nl`. Stages: (1) models + token-kind
fact sets — token kinds cross the boundary by NAME string, never enum ordinal
(TokenType-ordinal drift is a documented past codegen hazard); (2) pure classifiers +
interpolated/raw-string sub-tokenization (`ClassifyToken` L198-252, re-lexing internals
L277-477) with C# forwarders kept for the internals-pinned tests; (3) the AST walks — five
name-set builders L927-1043 + the catch-result-binding walk L564-925 (~345 LOC of `CollectFrom*`
arms — the arm list is the exhaustive checklist) + `ClassifyIdentifier`'s exact 10-step
precedence over flattened name-set/kind-map/semantic-key inputs; (4) one
`ClassifyDocumentTokens` entry owning the whole loop policy incl. `PushSemanticToken`'s skip
rules, handler collapses to flatten → kernel → `builder.Push`, internals tests retargeted at
kernels without losing a single (tokenTypeIndex, modifierBits) assertion; (5) VS Code gate +
before/after screenshots. Sharpest hazards: **interpolated strings deliberately classify to
null** so TextMate colors the expression holes — break this and every interpolated string
changes color; the `TokenTypes`/`TokenModifiers` legend arrays stay in the handler (kernel
emits indices into them — never reorder); the catch-binding modifier
(`CatchResultModifierMask = 1<<5`) is pinned by internals tests.

### Sub-arc 7 — Completion convergence (compressed)

Handler: `CompletionHandler.cs` (705 LOC — a second, independent completion engine → ~150 LOC
adapter over the sub-arc-4 engine). Stages: (1) behavioral-union inventory — the two keyword
vocabularies are NOT identical; diff them and every intentional difference before porting
anything; (2) grow the N# completion model (insertText/isSnippet/sortRank/autoImport fields)
+ create the ONE `LanguageVocabularyFacts.nl` (keywords, modifiers, primitives, snippet
definitions — the single source of truth that sub-arcs 9/10 also consume; the LSP superset
wins for IDE surfaces, the engine keeps `includeKeywords=false` for LLM output) + port the
sort-rank/dedup policy (rank constants `"0000"`…`"0900"`, `BuildSortText`, in-scope
suppression — tests pin the exact rank strings); (3) one editor-facing engine entry covering
the union (member completion, scoping, document symbols, vocabulary, import-statement
completion, external importables with auto-import detail) — `TypeResolver`'s reflection
enumeration stays C# feeding plain records, its namespace-suggestion DECISIONS move to
kernels; (4) adapter rewrite + delete the duplicate in one commit — **preserve the
trigger-character race protection verbatim**: `request.Context?.TriggerCharacter == "."` is
the PRIMARY member-completion signal, document-text inspection the fallback (didChange can
race the request; hard-won LSP architecture decision), and keep the `.`/`:`/` ` trigger
registration; (5) VS Code gate + computer-use (fast-typed `.` completion, `import Sys…`
completion, snippet tab-stop expansion — a missed `InsertTextFormat.Snippet` flag renders
literal `${1:...}`, auto-import detail + ranking) + `nlc query complete` JSON byte-diff (the
CLI schema is versioned). Hazards: the engine's prefix extraction THROWS on kernel rejection —
the LSP adapter must not crash the request pipeline on half-typed buffers (explicit
catch/empty-result policy, tested); use the synchronized-snapshot path, never a fake snapshot
from stale disk state (that fallback was deliberately deleted).

### Sub-arc 8 — Document structure (compressed)

Handlers: `DocumentSymbolHandler.cs` (262→~90), `FoldingRangeHandler.cs` (299→~70),
`SelectionRangeHandler.cs` (552→~80). Kernels: `DocumentStructureKernels.nl` +
`DocumentStructureModels.nl` (StructureNode/FoldingRegion/ContainmentRange; kind tags as plain
strings — the adapter maps to `LspSymbolKind`). Stages: (1) models + port the sub-arc-5
`AstEndLineEstimator` verbatim (its unit tests are the ready-made oracle; both implementations
pass the same cases in this commit); (2) the outline tree — **detail strings byte-identical:
`"test"` / `"setup"` / `"teardown"` / `"record"` / `"soa"` / `"union"`**, `FormatTypeRef`
rendering (`Name<A,B>`, `T[]`, `T?`, `(A,B) -> R`), and `MakeSymbol`'s clamping math (Range
must fully contain SelectionRange; single-line symbols widen endCol; null source lines →
`int.MaxValue`); (3) folding (declarations, statement bodies, imports block, multi-line
comments) + selection containment chains, then DELETE the temporary C# estimator + its tests —
the kernel is sole owner; (4) VS Code gate + computer-use — **Test Explorer discovery on a
`*.tests.nl` file is the non-negotiable check** (`detail === 'test'` is load-bearing; a
unit-green, discovery-broken state is exactly what visual verification exists to catch).
Hazard: the brace-scan estimator's blind spots (braces in strings/comments) are pinned
canon — do not fix them here; improvement belongs against the columnar token stream after the
re-host.

### Sub-arc 9 — Display intelligence: hover, signature help, inlay hints (compressed)

Handlers: `HoverHandler.cs` (307→~130), `SignatureHelpHandler.cs` (548), `InlayHintHandler.cs`
(373), `EditorUtilities.cs` (299 — string-literal scanners). Kernels:
`EditorDisplayKernels.nl` (+ models), extend `CodeIntelligenceSourceTextKernels.nl` and
`CodeIntelligenceSignatureKernels.nl` (extend, don't fork). Stages: (1) the four hand-rolled
string-literal scanners + `IsEscaped` → source-text kernels; `IsPositionInsideStringLiteral`
becomes a one-line forwarder (consumer: PrepareRenameHandler); (2) hover — keyword/primitive
hover facts (consume the sub-arc-7 vocabulary kernel), markdown shaping of the project-hover
result, variable/System-type hover rendering (the adapter reads
`System.Type.Namespace`/assembly via reflection and passes STRINGS; the kernel owns the
markdown), preserving the fallback ordering byte-for-byte; (3) signature help — backward
call-context scanning (`ExtractMethodCall`, `CountCommas` — string/char/escape-aware with
`(`/`[`/`<` depth tracking; **the `<`/`>` quirk treating comparison operators as depth changes
is shipped behavior, port character-for-character**), label shaping, and
`SelectActiveSignature` (exact-arity first, then first-that-can-accept, else 0); the
SemanticModel receiver lookup stays an adapter data feed until sub-arc 11; (4) inlay hints —
the hint-site walk (functions/blocks/var decls/foreach/await-foreach/local functions),
eligibility (skip explicit annotations, skip unknown types), `FormatTypeForHint` incl. tuple
shapes; retarget the internals-pinned `CollectHints`/`FormatTypeForHint` tests at kernels;
(5) cleanup + consolidated gate. Every stage that changes published behavior ends with the
full VS Code gate + reload + computer-use (hover a local / a System-typed variable / `func` /
`int`; signature help in a nested call with comma-containing string args, active parameter
advancing; hints on inferred `:=`/foreach/tuple and absent on explicit annotations). Hazard:
if hover/signature ranges look off-by-one vs tests, suspect stale pre-de-drift expectations
(the BindingMap keyword-offset compensation was removed at 65eb92b9) before "fixing" the
kernel.

### Sub-arc 10 — Navigation family + DocumentManager symbol extraction (compressed)

The last big C#-owned decision block. Handlers: `CallHierarchyHandler.cs` (768),
`TypeHierarchyHandler.cs` (414), `GoToImplementationHandler.cs` (285),
`WorkspaceSymbolHandler.cs` (179), `PrepareRenameHandler.cs` (171),
`DocumentHighlightHandler.cs` (142, filter half), `RenameHandler.cs` (137, edit-building
half), plus DocumentManager L796-1400 (~600 LOC symbol extraction) and the `TypeResolver.cs`
split. Kernels: `EditorSymbolExtractionKernels.nl` + `EditorNavigationKernels.nl` (+ models
replacing `Models/SymbolInfo.cs`/`SymbolLocation.cs`). Stages: (1) symbol extraction —
`ExtractSymbols`/`ExtractSymbolsInfo`/`ExtractSymbolLocations` (parameters, locals,
foreach/await-foreach variables, catch bindings) + doc-comment harvesting; REUSE the existing
N# TypeInfo-construction kernels; **`FindNameColumn` is load-bearing** (parameters/tuple names
lack AST positions — the text-search fallback is why go-to-definition on a parameter works;
replicate verbatim, or prove equivalence to `FindIdentifierNameColumn` with a test BEFORE
switching); one walk fills all three tables (this runs per keystroke); (2) call + type
hierarchy — function anchoring (converge the duplicated `GetFunctionEndLine` copies onto the
sub-arc-8 estimator), the outgoing-call walk, per-document supertype/subtype matchers;
cross-document iteration STAYS in C# (host state) — kernels get per-document data; (3)
implementations + workspace symbols + rename family + highlights — **`VerifySemantic` stays
REQUIRED** for go-to-implementation (deliberate hardening; no text-only fallback), the three
`RenameRefused` messages move verbatim (tests pin them), rename-edit grouping reuses
`TextEditOrdering.nl`, PrepareRename consumes the sub-arc-7 vocabulary kernel (do NOT add a
fifth keyword list), `MatchesQuery` internals test retargeted; (4) `TypeResolver` split —
decision half (alias maps, importable-type ranking/limits/force-includes, namespace
suggestions + priorities, `FormatTypeName`) to kernels, reconciled with whatever sub-arc 7
already moved (exactly one owner per decision); the reflection half stays with a
`MECHANICAL-GLUE` header declaring it owns no decisions; (5) cleanup + gate. Full VS Code gate
per stage + computer-use (call hierarchy in/out, type hierarchy super/sub, go-to-impl on an
interface, Cmd+T search, cross-file rename, rename refusal on `func`, highlights).

### Sub-arc 11 — LSP front-end re-host onto the N# pipeline

The terminal slice and the highest-blast-radius commit in the track. `DocumentManager`'s
per-keystroke `new Lexer` (L246) / `new Parser` (L250) / `_sharedAnalyzer.Analyze` (L278,
field L25) / `new Linter` (L286-288) swap for the N#-owned front-end;
`CodeIntelligenceService.LoadProject` and `FixApplicator` swap in lockstep. Blocked on: Track
C's syntax-ownership flip (N# parse diagnostics with recovery, comment trivia, token surface),
Track D's analyzer spine (NLxxx diagnostics + semantic model answering identifier lookup /
type-at-position / visible variables + BindingMap parity, with the metadata host isolated as a
boundary this track CALLS, never re-owns), and this track's own sub-arcs 1 and 3–10.

- **Stage 1 — precondition audit.** Verify every required parity artifact EXISTS (this stage
  builds none). Inventory every `DocumentState` property consumer (`Tokens` feeds semantic
  tokens, `Comments` feeds folding, `Bindings` feeds strict references…) and write the swap
  map (property → replacing N# surface → consumers) to the scratchpad. If any artifact is
  missing or partial, STOP and report the gap — never shim it with C#.
- **Stage 2 — parity harness (the shadow mode, promoted).** For every fixture in the four LSP
  suites + `examples/`: run the C# path exactly as `UpdateDocument` does and the N# front-end;
  diff FULL tuples — diagnostic (code, message, file, line, col, span length, severity),
  linter set, comment trivia, semantic answers at sampled positions, strict-reference sets per
  declared symbol. Fix every divergence UPSTREAM in the owning N# subsystem (Track C/D files
  or this track's kernels), never with LSP-side patch-ups or offset compensation (a
  keyword-offset compensation hack between front-ends already bit once and was excised).
  Include mid-edit fixtures — unclosed brace, half-typed member access: **syntax-error
  recovery is the hard parity axis**; recovery differences surface as missing
  completions/symbols, not diagnostic diffs. VERIFY-FIRST: the pipeline is the arbiter, not
  reasoning about what "should" match.
- **Stage 3 — swap `UpdateDocument`** (replace-then-delete, ONE commit): one N# front-end
  invocation producing parse diagnostics + syntax surface + comments + tokens, analyzer result
  (diagnostics, semantic model, bindings), linter diagnostics. Host logic untouched (LRU
  eviction, project-config load, metadata-host load, dedup, symbol-extraction kernel calls).
  Update `DocumentState` types per the swap map; delete `_sharedAnalyzer` and every C#
  front-end instantiation. Grep gate:
  `grep -rn "new Lexer\|new Parser\|new Analyzer\|new Linter" src/NSharpLang.LanguageServer/`
  → zero. FULL VS Code gate (all 21 suites) + reload + computer-use BEFORE the commit.
- **Stage 4 — swap `CodeIntelligenceService` + `FixApplicator`** the same way (code actions
  must apply fixes against the same front-end the diagnostics came from); same grep gate over
  `src/NSharpLang.Compiler/CodeIntelligence/`; `nlc check` / `nlc query` / `nlc fix` probes
  byte-identical. Also swap `FormatSafe`'s reparse gate to the N# syntax authority here (Track
  C's flip has landed by definition) and delete the C# Parser dependency from the shell.
- **Stage 5 — delete the parity harness and zero-consumer facade** (temporary code dies when done — the permanent net
  is the LSP corpus, now running entirely on N#). Update `memory/` LSP/architecture notes.
  Delete the now-zero-consumer `Analyzer.cs` facade in this same commit. Hand Track H the
  deletion notice and an explicit checklist only for other producing-track remnants; H does not
  delete the Analyzer facade. Final full VS Code gate + a computer-use
  END-TO-END session driven to the last scenario (syntax-error squiggle appears and clears;
  type error with the rich message; `.` completion; hover; definition + references; cross-file
  rename; outline + Test Explorer on a `*.tests.nl`; lint squiggle) — the last scenario is
  where stale-pipeline crashes hide.
- **Per-keystroke latency is a gate, not a note**: the columnar parser is measured faster than
  the C# one, but the analyzer's interactive latency is unproven — watch the VS Code
  performance suite and the editor feel; a noticeable regression blocks the commit.

## Cross-track contract

**Consumes:**
- **Track B (track-b-kernel-binding-cli.md) — static kernel binding**: prerequisite for
  sub-arc 2 (the formatter extends and calls the columnar parser kernels kernel-to-kernel with
  typed entry points). SDK repins are Track B's to grant — request and announce; new emitter
  capability is usable in kernels only after a repin.
- **Track D (track-d-semantics.md) — AST model in N#** (its first sub-arc): prerequisite for
  sub-arcs 1 and 3 (typed-AST kernels instead of multiplying the `GetType().Name` reflection
  idiom). If a sub-arc must start before it lands, use the proven reflection idiom over
  `object` (the `AstNodeFinderCore.nl` pattern) and re-verify every string literal when the
  model moves — never invent a third dispatch style.
- **Track C (track-c-syntax-frontend.md) — syntax-ownership flip** + **Track D — analyzer
  spine**: hard prerequisites for sub-arc 11 (and for retiring `FormatSafe`'s C#-Parser
  reparse gate). The metadata host (assembly loading semantics) is Track D's isolated
  boundary — sub-arc 11 calls it, never re-owns it.
- **Track A (track-a-product-path.md):** the historical unit baseline is retired. Track A still
  owns product-gate blockers, but every current failure is attributed directly.

**Produces:**
- **Code-intel facts** (sub-arcs 3–4) consumed by this track's own LSP arcs — the sync table's
  G→G edge.
- **Front-end flip complete** (sub-arc 11): with Tracks C and D's flips, this deletes the
  zero-consumer `Analyzer.cs` facade and unblocks Track H (track-h-tests-release.md) to verify
  the handoff and remove only explicitly assigned zero-policy remnants such as remaining
  `Parser.cs` / `Lexer.cs` / `Linter.cs` / `Formatter.cs` shells. Sub-arcs 1, 2, 3–4 each
  pre-perform
  ~97% of their file's deletion; this track hands H an explicit checklist of the residue
  (parse-boundary lines, FormatSafe shell, host-glue files with `MECHANICAL-GLUE` headers).
- **Shared vocabulary + structure kernels** (sub-arcs 7–8) that any later doc/playground work
  in Track H may consume.

**Contention:** this track's files are effectively exclusive (LanguageServer,
CodeIntelligence, Linter/Formatter), except `MultiFileCompiler.cs` (one `Linter.Lint` call
site — Tracks C/E/F also edit that file; the flip is a no-op line for them but coordinate
timing) and `tests/Tests.csproj` (append-only, never reorder). Stage only your own files —
never `git add -A`; run contended gates from a `/tmp` worktree (never nested under the repo
root).

## What NOT to do (merged across the whole track)

- **Never delete-first.** Every C# body dies in the SAME commit its N# replacement passes the
  pinned tests. The 2026-07-01 incident (~107 failures: dropped diagnostic spans, rich
  NL401/NL202 messages, ToString display) is the canonical failure and it happened in exactly
  this subsystem class.
- **No dual engines, no fallbacks, no flags.** No hybrid linter dispatching some rules to N#;
  no C# front-end kept reachable behind a flag/env/try-catch after the re-host; no second
  N#-side completion engine (convergence means ONE owner per behavior).
- **No route-back-into-C# delegates.** Data crosses the kernel boundary, never behavior — no
  formatter/severity/resolver/classifier callbacks passed into kernels. TypeResolver and the
  metadata host feed materialized plain records.
- **No OmniSharp protocol types in kernels**, no kernel references to the Compiler or
  LanguageServer assemblies (circular/invisible), no LSP-protocol DTOs leaking into
  BootstrapServices.
- **No AST-walking formatter** and no materializing columnar parses into the C# AST (deleted
  dead end, 4–5x slower) and no re-parsing inside consumers — one front-end invocation per
  document update.
- **Do not "simplify" pinned semantics**: the NL012 `ReferenceEquals` frame crediting, the
  recursion-depth throw, the circular-guard mark-used-on-skip, `FormatSafe`'s two gates,
  `ShouldPreserveExplicitCasingVisibility`, the interpolated-string null-classification, the
  10-step identifier-classification precedence, SortText rank strings, `GetNearbyColumns`
  probe order, `CountCommas` depth quirks, `VerifySemantic`-required, `RenameRefused` texts,
  the `detail === 'test'` contract, `FindNameColumn`, and every diagnostic message string
  (verbatim, character-for-character).
- **No new keyword lists** — after sub-arc 7 there is exactly one vocabulary kernel. No
  TokenType ordinals across the C#/N# boundary — names only (documented ordinal-drift hazard).
- **No behavior changes smuggled into consolidation or ports** — parity first, improvements
  never; estimator blind spots and recovery quirks are pinned canon until a deliberate,
  separate product decision.
- **Do not reformat the repo corpus to make the formatter gate pass** — fix the engine, not
  the corpus.
- **Do not touch `OnTypeFormattingHandler.cs`** (not a Formatter consumer).
- **No `VSCODE_TESTS=skip` on any IDE-affecting stage**; no `git add -A`; no `Assembly.Load(`
  string literals in tests (the source-scan guard self-trips); no raw `dotnet test --filter`
  (xUnit hang); no nondeterminism in formatter/completion kernels (Ordinal/invariant
  everywhere — the idempotence gate converts nondeterminism into intermittent product
  failures).
- **No new C# product logic** — C# edits only shrink or disconnect ownership; the only
  additions are thin adapter mapping, input flattening, and the two sub-arc-5 shared helpers
  (which replace three copies each; net LOC down).

## Track exit criteria

- [ ] `Linter.cs` < 50 LOC; `LintVisitor` + data tables deleted; all ten rules in N#;
      `grep -rn "LintVisitor" src tests` empty; linter oracle suites pass UNMODIFIED.
- [ ] `Formatter.cs` ≤ ~60 LOC (FormatSafe shell); all formatting decisions in N# over
      columnar tokens + node tables; comment side table feeds the engine; repo-wide
      double-format fixpoint checked in as a permanent guard; the reparse gate runs on the N#
      syntax authority after sub-arc 11.
- [ ] `CodeIntelligenceService.cs` reduced to LoadProject/snapshot glue + thin kernel entries;
      `CompletionEngine.cs` ≤ ~80 LOC; `AstNodeFinder.cs` deleted; the type-reference
      resolution duplicates exist exactly once, in N#; every `nlc query`/`check`/`lint` JSON
      byte-identical on the probe corpus.
- [ ] Every LSP handler is a protocol adapter; all classification/structure/display/ranking/
      matching/refusal decisions live in kernels; internals-pinned tests retargeted, not
      deleted; exactly one publish path, one estimator owner (in N#), one keyword vocabulary,
      one completion engine.
- [ ] `DocumentManager`/`CodeIntelligenceService`/`FixApplicator` grep gates clean (zero
      `new Lexer|new Parser|new Analyzer|new Linter`); `_sharedAnalyzer` gone;
      `DocumentState` carries N#-owned surfaces; the parity harness was built, proved
      full-tuple parity, and was deleted.
- [ ] The four LanguageServer unit suites FULLY green on the N# front-end (parity is the
      deliverable — not baseline-relative); `LanguageServerDiagnosticsTests` (the span
      canary) green; all 21 VS Code suites green.
- [ ] Every IDE-affecting stage shipped with the full VS Code gate + extension reload +
      computer-use screenshots, including Test Explorer discovery on a `*.tests.nl` file and
      the sub-arc-11 end-to-end session driven to the final scenario.
- [ ] Residual C# in LanguageServer/CodeIntelligence is inventoried mechanical glue
      (protocol wire-up, document/file state, TypeResolver reflection feed, metadata-host
      calls) with `MECHANICAL-GLUE` headers; deletion checklist handed to Track H; docs
      (`memory/components/cli-toolchain.md`, LSP architecture notes) updated to name the N#
      owners.

## Gotchas & prior art

- **Exemplar commits for the port motion**: 0eaafef2 (NL001/NL012 gating → kernel), aa3db221
  (suppressions), 2198d9f2 (import metadata), 9545a9bf / a588acfa (wrapper deletion after the
  kernel was proven), 8b723ffd (AST node finder → kernel + 15-line shim), 9d9b4fd9 (completion
  declaration items), 3fd604c2d (lexer statically consumed — the binding pattern), 4b02aa4c
  (OperatorFacts), fe8ff87d/d7755860 (import ordering enforced, fallback deleted), dbab712e
  (FormatSafe hardening — behavior contract), 9ca946b7/92ab54ae/5bb95f89/c631eebc (TypeInfo
  construction kernels — sub-arc 10 REUSES these), 134bd871 (required semantic
  go-to-implementation), 4a447eec (deleted the disk-snapshot fallback — don't rebuild it),
  65eb92b9 (BindingMap de-drift — offset compensation is the anti-pattern), d056a821 (columnar
  front-end parses 100% of own source), d0884f4e (deleted materialization dead end).
- **The stale-binary trap has two heads**: the installed `~/.nsharp/bin/nlc` (always probe a
  fresh-built Cli.dll) and the packaged VSIX (always `./scripts/reload-vscode-extension.sh`
  before any visual check). Both produce convincing false "the port broke it" results.
- **Kernel shape limits** (until Track E lifts them): no bare `this` as expression/argument;
  no `GetType()` on a typed receiver (cast to `object` first); no generic user types; pinned
  stage-0 SDK subset — stub-probe unproven shapes (~13s/build) before bulk porting; repin via
  Track B when genuinely needed and say so in the commit.
- **VERIFY-FIRST is the arbiter**: execution probes against the real N# pipeline overturned
  four confident adversarial reviews in this repo. Where semantics are at stake (NL012
  crediting, null-state defaults, union flattening, recovery parity), probe edge fixtures
  before trusting any review verdict — including your own reasoning.
- **Sizing**: ~4–6 weeks for one owner. Sub-arc 11's Stage 2 (parity) is where the hidden work
  lives — divergences there belong to Tracks C/D and must be fixed upstream; budget the
  coordination. Sub-arc 5 can start day one and doubles as the VS Code rig shakedown; sub-arcs
  1 and 5 can interleave if Track D's AST model is late.
- **The formatter's comment-capture stage is new ground** — the scanner deliberately dropped
  comments for emission speed; keep the arrays optional/separate so emission pays nothing, and
  trust the `Lexer.nl` `CommentTrivia` oracle over any reviewer's reading of the scanner.
- **Idempotence traps**: column-tracked wrapping (fixtures at MaxLineLength±1), dictionary
  iteration order, culture-sensitive formatting. The `>>` split in nested generics
  (`List<List<int>>`) differs between the C# parser and the columnar kernels — type-reference
  printing must not assume token-count fidelity with source.
- **Per-keystroke paths are perf-sensitive**: symbol extraction and semantic tokens run on
  every edit. One AST walk filling all tables mirrors current cost; if the VS Code performance
  suite regresses on token-fact flattening, switch the feed to parallel arrays (columnar
  style) — same kernel decisions, cheaper marshaling. Evidence first, optimization second.

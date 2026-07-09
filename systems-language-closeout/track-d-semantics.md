# Track D — semantics: retire Analyzer.cs end to end

> **LIVE STATUS (audited at `fb856ee46`):** the MetadataLoadContext probe is complete
> (`fef45dd22`); the AST move and analyzer families are not. `Analyzer.cs` is now 23,451 LOC.
> Add source-qualified SymbolId/TypeId contracts and consume the shared N# package/version
> policy rather than preserving new C# metadata policy. Every routed slice is IDE-affecting
> because the Language Server shares the Analyzer. D retargets all non-IDE consumers; G owns the
> final IDE-consumer flip and deletes the then-zero-consumer facade in the same commit. H only
> verifies that handoff.
> [STATUS.md](STATUS.md) is authoritative.

**Owner model:** ONE senior owner for the whole track, start to finish. This is the campaign's
long pole (~5–8 weeks) — staff it early, protect the owner from swing work, and do not split
sub-arcs across people. The owner carries three pieces of context that every sub-arc reuses:
the **step-protocol host contract** (designed once in sub-arc 2 knowing what sub-arcs 3–9 will
demand of it), the **state-reset ledger** (Analyzer.cs L255–292 — which of the ~100 fields reset
per `Analyze()` vs survive; getting it wrong silently corrupts LSP incremental analysis), and
the **TypeInfo model** (TypeInfoModels.nl and its ToString displays, which every diagnostic
message renders through). Paying that tax once instead of ten times is the reason this is one
track. Read `systems-language-closeout/README.md` first — campaign rules, sync table, and
contention ledger live there and are binding; this file restates only track-critical constraints.

All facts below verified 2026-07-02 at commit 9538ab66. Do not trust them blindly after the tree
moves — re-anchor line numbers with grep before editing a region.

## Mission & end state

N# owns every semantic decision the compiler front-end makes. Concretely:

- The 120-type C# AST record model (844 LOC across three files) is deleted; equivalent N#
  classes live in `src/NSharpLang.Compiler.BootstrapServices/` under the same
  `NSharpLang.Compiler.Ast` namespace.
- `src/NSharpLang.Compiler/Analyzer.cs` may temporarily shrink to a **≤ ~500 LOC facade**:
  construction (MLC + resolver setup), public API forwards (`Analyze`, `SetProjectSourceTexts`,
  `GetTypeDeclarationFiles`, the `Load*` family, `Dispose`), a typed parse-provider seam, and —
  only if the metadata probe says NO-GO — a ~95-line mechanical resolver shell. Every temporary
  facade member is comment-classified FACADE, serves only the exact G-owned IDE consumer, and is
  deleted by G with that consumer flip. Any separate MECHANICAL-GLUE resolver shell is inventoried
  by H's final audit.
- All conversion/operator/pattern/flow/member/call/statement/expression/declaration/spine logic
  lives in BootstrapServices kernels, statically bound (Compiler.csproj:26 ProjectReference),
  never reflection-loaded.
- Diagnostic output is byte-identical throughout: messages, suggestions, spans, dedup, ordering.
  Parity, not improvement — language changes are separate proposals.

Analyzer.cs is a **parallel pipeline, not columnar-retired**: ColumnarCompiler never calls it
(codegen re-parses via columnar kernels); Analyzer serves `check`/build-analysis/LSP/
code-intelligence via a shared instance (`MultiFileCompiler.cs:110`,
`LanguageServer/Services/DocumentManager.cs:39`). Porting is the only path to N# ownership —
old memory claiming "Analyzer RETIRE gated on columnar coverage" is stale; correct it in
sub-arc 10.

## Why this is one track

The old per-commit plan sliced the analyzer into ten independent tasks, each of which would have
re-derived the host seam, re-learned the reset ledger, and coordinated `AnalyzerHost.nl` edits
with concurrent executors. One owner instead:

1. **Designs the host contract once.** The transition seam (virtual-class host + step protocol,
   below) accumulates members from every sub-arc and is deleted member-by-member as later
   sub-arcs land their owners. A single owner designs it in sub-arc 2 already knowing the full
   demand list (span getters, external-type lookup, reflection-type conversion, expression
   re-entry, scope push/pop, symbol declaration) and never fights merge contention on the seam
   file.
2. **Builds the regression net once.** The analyzer parity fixtures and probe corpus created in
   sub-arc 2 (captured pre-port, byte-diffed after every slice) are the standing harness for
   every later sub-arc.
3. **Settles boundary ambiguities by fiat.** The old plan had unowned strips (e.g.
   L17516–17799, the is/cast/await/typeof family) with "verify the other task took it" notes;
   this file assigns every line range exactly once.
4. **Keeps commit shape unchanged.** Track ownership changes who executes consecutive stages,
   never the stage-equals-commit rule. Every stage below is one commit with focused evidence
   green and an `Evidence:` line.

## Current state (verified 2026-07-02, commit 9538ab66)

### Analyzer.cs region map (the demolition plan)

One stateful class, ~100 mutable fields, the whole front-end semantic pipeline.

| Region | Lines | Contents | Sub-arc |
|---|---|---|---|
| State + driver | L1–435 | ~100 fields L27–247; **state-reset ledger L255–292** (note: `_projectNamespaceCache` RESETS per `Analyze()` — earlier analysis claiming it survives was wrong); 2-pass `Analyze()` L248+; pass-1 DeclareType already routes through N# TypeInfo factories L318–345; `ReportReferenceLoadFailures` NL923 L393/405 | 10 |
| Declarations + attributes | L436–2935 | `AnalyzeDeclaration` dispatch L436; attribute validation L499–1582 (`TryResolveClrAttributeType` L1054, `HasMatchingAttributeConstructor` L1278); test/setup/teardown L1583–1832; `AnalyzeFunctionDeclaration` L1833; generator/task-like return checks L2009–2125; `StatementAlwaysReturns` L2126; type-member declarations L2185–2935 | 9 |
| Definite assignment | L2936–3508 | ctor-field + local walkers; cleanest self-contained region in the file | 5 |
| Statements | L3509–6099 | dispatch L3531; expr-statements + must-use L3716–4023; **span machinery L4024–4370** (`GetExpressionDiagnosticSpan` L4069, `GetTokenLength` L4301); local fn/var-decl/tuple-deconstruct L4400–4771; if-narrowing L4772–5037 (→ sub-arc 5); loops L5038–5407; return L5408–5603; try/finally NL319 L5604–5768 (ECMA-335 comment L149–159); using/lock NL320/switch L5769–6099 | 8 (flow parts: 5) |
| Patterns | L6100–6552 | `AnalyzePattern` L6100 + list/relational/property pattern helpers | 4 |
| Expression dispatch | L6553–7053 | `AnalyzeExpression` L6553; callable-reference rules L6693–6832; nullability flow glue L6833–6898 (→ sub-arc 5); default/range/spread/alloc/interpolation L6899–7053 | 9 (flow glue: 5) |
| Operators | L7054–8015 | binary dispatch L7054; typed analyzers L7156–7751; overload resolution L7439–7748; unary family L7752–8015; plus mismatch reporters L20902–20945 | 3 |
| Member resolution | L8016–9877 | `AnalyzeMemberAccess` L8016; `AnalyzeIndexAccess` L8109; `ReportPossibleNullAccess` L8424 (**NL905**); `ResolveMember` core L9125 (294 lines); extension methods L9711–9877 | 6 |
| Call binding | L9878–13961 | reflection-type bridge L9878–10517 (**`ConvertReflectionType` L9878**, `TryConvertTypeInfoToClrType` L10323); **`AnalyzeCall` L10518**; `ValidateSyntheticFunctionCall` L10966 (**the NL401/NL202 front door**); overload scoring + generic inference L11869–12831; reflection binding L12832–13961 (`BindReflectionCall` L12844, `FinalizeBoundReflectionCall` L13554 with `MakeGenericMethod` at L13617) | 7 |
| Assignments + mutation | L13962–15878 | `AnalyzeAssignment` L13962; events L14284–14454; null-state-after-assignment L14455–14469 (→ sub-arc 5); write targets/SoA mutation/readonly L14500–15852 | 8 (flow: 5) |
| Lambda + expression trees | L15879–16314 | `AnalyzeLambda` L15879; expression-tree restrictions L16007–16287 | 9 |
| Composite expressions | L16315–17515 | ternary/tuple/array/collection; `AnalyzeNewExpression` L16681; object initializers L16916–17281 (**`TryResolveObjectInitializerMemberType` L17024 — safety-critical NL202 guard**); stackalloc; union-case construction L17394–17515 | 9 |
| is/cast/await family | L17516–17799 | is/cast/await/throw/typeof/nameof/sizeof/checked/unchecked/with — unowned strip in the old plan; **assigned to sub-arc 9** | 9 |
| Match + exhaustiveness | L17800–18478 | `AnalyzeMatchExpression` L17800; four exhaustiveness checkers; union helpers L17459–17515 ride along | 4 |
| Type/identifier resolution | L18479–19507 | `ResolveType` family L18479–19114; project-wide resolution + sibling-file re-parse L18890–19094; `TryResolveExternalType` L19140; `LookupType`/`LookupSymbol` L19182/19195; null-state/error-tuple bookkeeping L19205–19347 (→ sub-arc 5); `ResolveIdentifier` L19411 | 10 (flow: 5) |
| Conversions | L19509–20953 | `IsAssignable` L19509 (root of 56 `ErrorCode.TypeMismatch` sites); int-literal typing L19647+; function/delegate scoring L19830–20108; `IsSubtypeOf` L20145; reflection identity + `GetInterfacesSafe`/`GetBaseTypeSafe` L20204–20291; duck interfaces L20561; type predicates L20633–20901 | 2 |
| Scopes + declaration validation | L20954–21498 | `PushScope`/`PopScope` L20954–20979 (paired `_semanticScopeIds` for SemanticModel lockstep); `DeclareSymbol` L21036; `DeclareType` L21170; `ValidateOperatorOverload` L21345; Error/Warning sinks L21417–21456 | 10 |
| Imports + namespaces | L21499–22094 | `ProcessImports` L21499; `ProcessFileImport` L21523 (~210 lines); namespace validation; `GetExternalSearchAssemblies` L21999; `CheckImportCollisions` L22056 | 10 |
| Metadata host | L22095–22481 | `LoadReferencedAssembly` L22095, `LoadSystemAssemblies` L22181, `LoadFromProjectConfig` L22270, `LoadNuGetPackage` L22360, `ProcessImportForAssemblyLoading` L22445 | 10 |
| Typo suggestions | L22482–22530 | pure scope scans; route through ErrorSuggestions.nl | 10 |
| NSharpMetadataResolver | L22534–22630 | `internal sealed class : MetadataAssemblyResolver` (external abstract base); TFM probe order net10.0→netstandard2.0; `LoadFailures` drained by NL923 | 0 + 10 |
| WellKnownTypes | L22631–22783 | MLC-resolved primitives (throw-on-missing), `Nullable`1`/Action/Func, NSharpLang.Runtime `Union`2`/`Result`2` — **broke in the 2026-07-01 incident, restored by e3702449**; regression-sensitive | 10 |

### AST model inventory (sub-arc 1's payload)

Three C# files in `src/NSharpLang.Compiler/Ast/`, 844 LOC, **120 record types**
(counted via `grep -cE '^public (abstract )?record'`):

- `Statements.cs` — 225 LOC, 33 records (`Statement` base, IfStatement … LocalFunctionStatement;
  CatchClause/SwitchCase are baseless payloads).
- `Declarations.cs` — 238 LOC, 23 records (`Declaration` base, CompilationUnit,
  FunctionDeclaration … TeardownDeclaration).
- `Expressions.cs` — 381 LOC, 64 records (`AstNode(int Line, int Column)` abstract base,
  `Expression`, `InterpolatedStringPart`, `Pattern(int Line, int Column)` — Pattern does NOT
  extend AstNode, preserve that — plus ~56 concrete nodes and 4 positionless payloads:
  Argument, TupleElement, MatchCase, PropertyInitializer).

Members beyond plain positional data (must survive the move exactly):

- `FunctionDeclaration`: computed `IsAsyncIterator` (Async+Generator flag test); init-props
  `OperatorKeywordSpan`/`OperatorSymbolSpan` (default `SourceSpan.None`) and `ReturnLifetime`
  (default null), set by object-initializer at Parser.cs:505–507/2525.
- `FileImport`: init-props `PathColumn`/`PathLength` with computed defaults; computed
  `DiagnosticColumn`/`DiagnosticLength`; pinned by tests/ParserTests.cs:3233–3236.
- `CallExpression.IsResultFactory` — **mutable `bool?`**, set at Analyzer.cs:11812/11816,
  currently write-only; port as a settable property anyway.
- `MatchExpression.IsExhaustive` — **mutable `bool`**, 12 set sites in Analyzer.cs; port settable.
- `PropertyInitializer.IsIndexerInitializer` computed; C# default parameter values on
  Parameter/Argument/PropertyPattern/AttributeNode/EnumMember/NewExpression/
  InterpolatedStringExpression — preserve every default; call sites rely on them.
- One post-construction mutation from C#: Parser.cs:1990 assigns `elements[0].Type.Span = ...`
  (on the already-N# TypeReference — settable N# members assigned from C# are proven).

**Atomicity rationale:** the three files are one strongly-connected component
(`LambdaExpression`→`BlockStatement`, `LocalFunctionStatement`→`FunctionDeclaration`,
`SwitchCase`→`Pattern`, `TestDeclaration`→`Expression`). Types cannot reference across the
BootstrapServices/Compiler assembly boundary in both directions, so all 120 types move in ONE
commit that also deletes all three .cs files.

**Record-semantics audit (embed-quality, run 2026-07-02):** zero `with {` expressions on AST
records; every Dictionary/HashSet keyed on AST nodes already uses
`ReferenceEqualityComparer.Instance` (Analyzer.cs:196, 7769, 10701, 14015; Linter.cs:47;
SystemsAnalyzer.cs:27–29); exactly ONE default-equality LINQ site relies on record value
equality — Analyzer.cs:18236 `pattern.Properties.Except(constrainedProperties)` — pinned to
reference equality in a prep commit BEFORE the type switch. No positional patterns, no
node `==`, no reliance on synthesized ToString.

**Idioms to copy:** `FileHeaderDeclarations.nl` is THE constructor idiom — PascalCase
constructor parameters disambiguated with `this.X = X`, which keeps both the 198 positional
Parser.cs construction sites AND the named-argument sites (`new CompilationUnit(Namespace:
null, ...)` in FixApplicator.cs:29 and tests/AnalyzerTests.cs ~11868) compiling unchanged.
`examples/06-classes-and-records/ConstructorChaining.nl:39` proves `: base(...)` chaining under
the pinned SDK. `CompletionDeclarationFacts.nl:83` is the `Convert.ToInt32` flag-test idiom for
`IsAsyncIterator`. Do NOT copy TypeInfoModels.nl's empty-base pattern — AST bases MUST expose
Line/Column polymorphically (hundreds of C# sites read `expr.Line` through base-typed refs).

### Existing N# assets (build on these, never duplicate)

All in `src/NSharpLang.Compiler.BootstrapServices/`, statically consumed by C# today:
`TypeInfoModels.nl` (948 LOC — the full TypeInfo hierarchy incl. `DeclaredMemberInfo`,
`ReflectionMethodGroupInfo`, and the ToString displays diagnostics render through),
`TypeInfoFactories.nl` (982), `BindingMap.nl` (609 — the existence proof for N# classes with
mutable Dictionary fields consumed from C#), `AnalyzerBindingFacts.nl`,
`AnalyzerOverloadSignatureFacts.nl`, `AnalyzerDiagnostics.nl` (the Error-sink factory),
`AnalyzerStateModels.nl` (Scope, FlowNarrowing, ErrorTupleResultGuard,
DiscardedExpressionContext, AttributeArgumentConstantKind), `SemanticModel.nl` (311),
`ErrorMessageBuilder.nl` (732 — `WrongArgumentCount` :230, `NoMatchingOverload` :260,
`WrongArgumentType` :490, `UndefinedMember` :635), `ErrorSuggestions.nl` (236),
`ErrorCode.nl`/`CompilerError.nl`, `NullState.nl`, `DefiniteAssignmentState.nl`,
`DiagnosticSpanResolver.nl`, `OperatorFacts.nl` (205, 31 Analyzer call sites),
`NumericLiteralFacts.nl`, `CodeIntelligenceTextUtilities.nl` (owns the identifier-column scan
and `GetSourceLine`), `SoaFeature.nl`, `LoopSequenceTypeFacts.nl`, `TaskLikeTypeFacts.nl`,
`GeneratorSequenceTypeFacts.nl`, `NSharpMethodGroupInfoFactory.nl`, `ReadonlyFieldTarget.nl`,
`VisibilityConventions.nl`, `ImportGraphModels.nl` (file IO from N# proven),
`ExternalAssemblyScan.nl` (System.Reflection imports from N# proven),
`CompilationReferenceResolverKernels.nl`, `AnalyzerExhaustivenessSelector.nl` (91 — still on the
`GetProperty("Name")` reflection idiom; sub-arc 4 de-reflects it), `FileHeaderDeclarations.nl`,
`TypeReferences.nl`, `SourceSpan.nl`, `AnalysisResult.nl`.

Diagnostics construction is already fully N#: the C# `Error` sink (L21422) builds
`CompilerError` via `AnalyzerDiagnostics.Create` + `CodeIntelligenceTextUtilities.GetSourceLine`.
Kernels construct final `CompilerError`s themselves and **share Analyzer's `_errors` list
instance** (L135) so error ordering and count-sensitive checks stay exact.

### Diagnostic-code ground truth (corrections that outrank folklore)

- **NL905 = `PossibleNullAccess`** (ErrorCode.nl:89), NL907 = `NullabilityWarning`. Loose talk
  calling the possible-null diagnostic "NL401" is WRONG.
- **NL401 = `WrongArgumentCount`** (ErrorCode.nl:48) — call arity, sub-arc 7.
- **NL202 = `TypeMismatch`** (ErrorCode.nl:16). NL202 is **safety-critical, not cosmetic**:
  `EmitValueCoercion` silently no-ops for closed generics over emitted user types, so the
  analyzer's argument and object-initializer checks are the ONLY guard turning would-be silent
  garbage reads into compile errors (the object-initializer hole was fixed 2026-06-12; commit
  52c8a0d8 most recently adjusted the NL202 fallback wording — keep byte-exact).
- Others in this track: NL303 UndefinedMember, NL308 InaccessibleMember, NL402
  NoMatchingOverload, NL208 GenericConstraintViolation, NL319 finally-control-transfer, NL320
  lock-on-value-type, NL923 reference-load failure.
- `tests/DiagnosticGoldenTests.cs` pins message/span bytes (NL202 golden at line 140, NL401
  golden at line 164). `tests/AnalyzerTests.cs` (13,438 lines) is the behavior oracle.

### The transition seams (designed once, in sub-arc 2)

Two shapes, both delegate-free (delegates into kernels are banned campaign-wide):

1. **`AnalyzerHost.nl`** — an N# class with `virtual func` members carrying default fallback
   bodies; Analyzer.cs holds a nested `AnalyzerHostBridge : AnalyzerHost` whose overrides are
   ONE-LINE forwards to not-yet-ported regions. Each member is doc-tagged with the sub-arc that
   deletes it. Any conditional in a bridge override is C# product logic growing — banned.
   Probe first: C#-overriding-an-N#-`virtual func` is CLR-standard but unproven in this repo;
   if emission declines under the pinned SDK, fall back to an N# `interface` implemented by the
   C# bridge (probe that too; record the winning mechanism in the commit message — all later
   sub-arcs reuse it).
2. **The step protocol** — for lazy resolution inside deep kernel logic (member resolution,
   call binding), the kernel's entry returns an N#-modeled step value:
   `Done(memberType, …binding facts…)` / `NotFound(…undefined-member reporting data…)` /
   `NeedTypeReferences(List<TypeReference>)` (host answers with `ResolveType` results and calls
   the kernel's continue-function), plus narrowly-scoped `Need*` cases for reflection-type and
   nullability-metadata conversion until their owners land. **The C# host returns raw facts
   only** — candidate filtering, overload ordering, and nullability interpretation stay in N#.
   The shim is a dumb loop with zero decisions. Laziness is semantic: `ResolveType` emits
   NL302-family diagnostics, so eager pre-resolution changes diagnostic output.

Known full demand list for the host (design the contract for all of it up front; add members
per sub-arc, delete per sub-arc): `ResolveType`, `TryResolveExternalType`, `LookupSymbol`,
`DeclareSymbol`, `PushScope`/`PopScope` (all deleted by sub-arc 10);
`ConvertReflectionType`, `TryConvertTypeInfoToClrType`, `CreateFunctionTypeInfoFromDelegate`
(deleted by sub-arc 7); `GetExpressionDiagnosticSpan` + pattern/property-pattern span getters
(deleted by sub-arc 8); `AnalyzeExpressionWithExpectedType` (traversal re-entry, deleted by
sub-arc 9); `ResolveDeclaredValueMember` (deleted by sub-arc 6).

## Standing harness (built once, used by every sub-arc)

- **Current-state honesty:** the historical failure baseline is retired. Attribute every current
  failure directly from a clean commit; never stash another owner's working tree to recreate an
  obsolete comparison set.
- **Parity probe corpus (created in sub-arc 2, grown per sub-arc):** a directory of small N#
  probe projects exercising each diagnostic family this track touches. Capture `check` (and
  `check --json` for span diffs) transcripts from a **fresh-built CLI** BEFORE each sub-arc's
  first port commit; byte-diff after every stage. Fresh-build discipline is absolute: the
  installed `~/.nsharp/bin/nlc` is frequently stale — always
  `dotnet build src/NSharpLang.Cli` and run that `Cli.dll`.
- **Inner loop:** `./scripts/dev.sh Analyzer` plus the new kernel's own pattern
  (`./scripts/dev.sh AnalyzerConversions`, etc.). Never raw `dotnet test --filter` (documented
  xUnit hang). Kernel-shape declines (reason-less NL103 under the pinned emit-only SDK) are
  diagnosed by stub-probe bisection, ~13s per BootstrapServices build.
- **Golden gates:** `./scripts/dev.sh DiagnosticGolden` after any stage touching message or
  span construction.
- **Integration checkpoints:** once a sub-arc is routed through the production Analyzer, it is
  IDE-affecting because the Language Server shares that Analyzer. Use the VS Code-enabled
  `./scripts/test-all.sh --commit`, extension reload, computer-use visual verification, and
  screenshots at that commit. A genuinely inert kernel/oracle commit with no production caller
  may use the non-VS-Code checkpoint; expected parity does not make a routed flip backend-only.
- **Kernel test suites:** one `tests/Analyzer<Kernel>Tests.cs` per kernel, append-only into
  `tests/Tests.csproj` (contention ledger rule). Never the literal `Assembly.Load(` in test
  source — a source-scan guard test self-trips on the string; emitted test assemblies load via
  `CollectibleAssemblyScope`.
- **Stage-0 SDK constraint:** all kernels compile emit-only with the pinned stage-0 SDK. Probe
  unproven shapes before designing around them; if a genuinely required shape declines, a repin
  is a Track B event (track-b-kernel-binding-cli.md) — announce, never repin silently mid-gate.

## Sub-arc 0 — MetadataLoadContext go/no-go probe (AT TRACK START)

One small commit, run before anything else — the verdict shapes sub-arc 10's endgame AND feeds
Track H's mechanical-glue inventory (track-h-tests-release.md), so it must not wait 5+ weeks.

1. Add `System.Reflection.MetadataLoadContext` version **9.0.0** (matching Compiler.csproj:21)
   to `src/NSharpLang.Compiler.BootstrapServices/project.yml` dependencies — the nuget
   precedent already exists there (`- nuget: YamlDotNet version: 16.3.0`).
2. Write a minimal probe kernel (`AnalyzerMetadataResolverProbe.nl`): an N# class extending the
   **external abstract** `MetadataAssemblyResolver`, overriding
   `Resolve(MetadataLoadContext, AssemblyName)` to return null. Also probe instantiating a
   `MetadataLoadContext` from N#. The BootstrapServices build alone answers the question.
3. **GO:** record in the commit message; sub-arc 10 ports `NSharpMetadataResolver` itself to N#
   (and tries moving the MLC instantiation too).
4. **NO-GO** (N# cannot override an external abstract member): record the exact compiler error
   in the commit message and in `memory/`; the bounded fallback is the ~95-line C#
   `NSharpMetadataResolver` shell surviving as documented MECHANICAL-GLUE whose `Resolve`
   override calls N# policy functions for candidate-path enumeration and failure recording.
   The fallback is bounded either way — this probe cannot dead-end the track.
5. **Delete the probe file after recording the verdict.** Notify Track H of the verdict.

Evidence: BootstrapServices build + `./scripts/dev.sh Analyzer` (no behavior change expected).

## Sub-arc 1 — AST model move (ONE atomic commit)

Deliverable: `Ast{Statements,Declarations,Expressions}.nl` in BootstrapServices; the three .cs
files deleted; namespace `NSharpLang.Compiler.Ast` unchanged. This removes the circular-
dependency blocker that forces tree-walking kernels into the `GetType().Name` +
`GetProperty(string)` reflection idiom (AST types currently live downstream of
BootstrapServices). Every later sub-arc, plus Track G's typed-AST linter/code-intel kernels,
is gated on this — land it immediately after the probe.

Stages (drafting order inside stage 3 is NOT a commit sequence):

1. **Shape probe (build-only, nothing committed):** one temp `AstShapeProbe.nl` exercising:
   3-level hierarchy with base Line/Column members + `: base(...)` chaining and a base-typed
   `.Line` read; a settable `bool?` property (IsResultFactory analog — `int?` is proven,
   `bool?` is not); `List<List<ProbeExpr>>?` (TestDeclaration.TableCases analog); a settable
   base member with default assigned post-construction (Span analog); a `Convert.ToInt32`
   flag-test computed property. ~13s per build; bisect declines by commenting out. Fallbacks in
   order for base-chaining failure: assign inherited members directly in derived constructors;
   then a base `SetPosition(line, column)` method (implicit-receiver instance calls are fine —
   only bare `this` as expression/argument declines). Delete the probe before stage 3's commit.
2. **Prep commit — pin the one value-equality site:** Analyzer.cs:18236 →
   `.Except(constrainedProperties, ReferenceEqualityComparer.Instance)`. Lands BEFORE the
   representation changes so any behavioral diff surfaces against the still-comparable record
   implementation. Evidence: `./scripts/dev.sh Analyzer` (match/exhaustiveness groups), the full
   VS Code-enabled gate, extension reload, computer-use verification, and screenshots in this
   commit because `Analyzer.cs` is already IDE-reachable.
3. **The move (atomic):** all 120 types as N# `public class`es — identical type names,
   identical PascalCase property names/order, constructor params keep the records' PascalCase
   positional names/order/defaults with `this.X = X` bodies (FileHeaderDeclarations.nl idiom);
   bases declare Line/Column, derived chain `: base(Line, Column)`; `Pattern` stands alone;
   init-props become settable with identical defaults; computed members preserved
   (IsAsyncIterator via the flag-test idiom); mutable props settable
   (IsResultFactory/IsExhaustive); **no Equals/GetHashCode/ToString overrides on any AST class**
   (reference equality is the new contract — every keyed collection already opted in
   explicitly). Delete the entire `Ast/` directory in the same commit. Build ladder:
   BootstrapServices → Compiler.csproj → `./scripts/dev.sh --since` (Ast/* correctly escalates
   to the full unit suite — do not hand-narrow around it).
4. **IDE integration checkpoint:** the AST model feeds Analyzer/tooling/LSP code. Run the full
   VS Code-enabled `./scripts/test-all.sh --commit`, reload/reinstall the extension, and verify
   diagnostics/hover/navigation in the real editor with screenshots. The whole-corpus recompile
   and full unit suite must also be green.
5. **Opportunistic typed conversion (separate commit):** convert the two smallest
   reflection-idiom kernels to typed access — `AstChildrenCore.nl` (sole product consumer
   Linter.cs:834) and `AstNodeFinderCore.nl` (sole consumer AstNodeFinder.cs:14). The other ~10
   reflection-idiom kernels are converted by their owning sub-arcs/tracks (exhaustiveness
   selector → sub-arc 4; TypeInfoFactories/DeclarationFacts/CompilationUnitFacts → sub-arc 10
   and Track C's pipeline arc; completion/codefix/query kernels → Tracks G and B). State the
   handoff in the commit message. Then a docs/memory prose sweep (no file references the .cs
   paths — verified).

Hazards: (a) renaming ANYTHING breaks reflection-idiom dispatch, named-argument call sites, and
52 LSP CompilationUnit refs; (b) partial moves cannot compile — never split; (c) the special
members (init-prop defaults, computed props, mutable flags) are this sub-arc's equivalent of
the 2026-07-01 dropped-behavior incident; (d) do not touch Parser.cs beyond what compilation
forces — its machinery is Track C's (track-c-syntax-frontend.md).

## Sub-arcs 2–9 — the analyzer ports

Common shape for every sub-arc: create the kernel(s) in BootstrapServices; constructor-inject
`host: AnalyzerHost`, prior-arc kernels, and the SHARED `_errors` list (plus `scopes:
Stack<Scope>` where scope-walking); per-file `FilePath`/`SourceText` pushed by the wrapper;
`error`/`warning` helpers mirroring the C# sink byte-for-byte. Port leaf-first; **delete the
ported C# bodies in the same commit**, leaving one-line forwards only where other C# regions
still call them (each forward annotated with the sub-arc that deletes it). Rewrite LINQ as
loops; C# switch-expressions as N# match/if-chains; no bare `this`; no `GetType()` on typed
receivers. Byte-diff the probe corpus at every stage boundary.

### Sub-arc 2 — Conversions/assignability engine (~1,445 LOC → `AnalyzerConversions.nl`)

- **Scope:** L19509–20953 minus the two operand-mismatch reporters (L20902–20945, sub-arc 3's).
  Absorbs the pure callable-reference predicates at L6705–6760, `IsDelegateType` L10184,
  `TypesEqual` L12642. The region emits ZERO diagnostics — a pure decision engine, the least
  entangled big region, and the proving ground for class-scale ports.
- **Anchors:** `IsAssignable` L19509 (22 self-recursive uses; backs 56 TypeMismatch sites);
  int-literal typing L19647–19755 (leans on `NumericLiteralFacts.nl`; `_currentExpectedType`
  becomes an explicit parameter — field stays C# until sub-arc 10); generic/span/variance
  L19756–19829; function/delegate conversion scoring L19830–20108; `IsSubtypeOf` L20145;
  reflection identity L20204–20291 (`GetInterfacesSafe`/`GetBaseTypeSafe` exception-swallowing
  is LOAD-BEARING — MLC types with unresolvable deps throw from `GetInterfaces()`; removing the
  try/catch turns NL923-able projects into crashes); `IsImplicitNumericConversion(TypeInfo,
  TypeInfo)` L20292 (the `(Type,Type)` overload at L13850 is sub-arc 7's — do not touch);
  duck interfaces L20561–20632; predicates L20633–20901.
- **Stages:** (1) prove the host-seam mechanism + create `AnalyzerHost.nl` with the initial
  three members (`ResolveType`, `TryConvertTypeInfoToClrType`,
  `CreateFunctionTypeInfoFromDelegate`) and the virtual-dispatch probe test; (2) leaf
  predicates + numeric machinery + reflection identity; (3) structural machinery
  (subtype/common-base/duck/pattern-feasibility/callable-reference predicates); (4)
  function-type/delegate conversion scoring; (5) `IsAssignable` + `HasImplicitConversion` +
  `GetCommonType` last (root of the call graph), then the sub-arc's behavioral probe set
  (string→int mismatch, int-literal narrowing bounds, array→span, lambda→Func, duck
  satisfaction, anonymous-union arms) and the integration checkpoint.
- **Hazards:** delegate-conversion scoring must stay integer-identical — an off-by-one silently
  changes which overload binds (worse than an error); the seam mechanism probe gates the whole
  track's host design; this sub-arc creates the parity fixtures every later arc regresses
  against — build them generously.

### Sub-arc 3 — Operators (~960 LOC → `AnalyzerOperators.nl`)

- **Scope:** L7054–8015 plus the reporters L20902–20945. The two dispatch shells
  (`AnalyzeBinaryExpression` L7054, `AnalyzeUnaryExpression` L7752) stay in C# — they own
  operand `AnalyzeExpression` re-entry, `&&`/`||` narrowing scope choreography (internals are
  sub-arc 5's), and SoA escape-report calls — deleted by sub-arc 9. Pair with `OperatorFacts.nl`
  (31 call sites); do NOT absorb it.
- **Anchors:** typed binary analyzers L7156–7438; overload resolution L7439–7748
  (`TryResolveDeclaredBinaryOperator` L7467 walks N#-owned `DeclaredMemberInfo`;
  `TryResolveRuntimeBinaryOperator` L7514 scans CLR `op_*` via `Type.GetMethods()`;
  `TryResolveOperandClrType` L7572 closes MLC generic definitions with `MakeGenericType` —
  inspection only, never invokes); unary family L7752–8015 incl. `AnalyzeMustExpression` L7984
  (redundant-`must` warning, `length: 4`).
- **Host adds:** `GetExpressionDiagnosticSpan` (→8), `TryResolveExternalType` (→10),
  `ConvertReflectionType` (→7).
- **Stages:** (1) scaffold + typed binary analyzers + both mismatch reporters (wording
  byte-for-byte incl. the shift-integral special case and side-text branches); (2) declared +
  runtime operator-overload resolution; (3) unary family + shells slimmed to
  operand-analysis/narrowing/SoA/dispatch, then probes (`1 << true`, `"a" - "b"`, `!5`, `x++`
  on non-target, `~enum` non-flags, `??` non-nullable warning, wrong-param declared `operator +`
  must NOT bind, redundant must).
- **Hazards:** the L7490 declared-operator parameter guard prevents wrong-overload binding that
  diverges from the IL backend — silent wrong codegen, not an error; shared `_errors` instance
  keeps shell/kernel error interleaving order exact (AnalyzerTests asserts order).

### Sub-arc 4 — Patterns & exhaustiveness (~1,100 LOC → `AnalyzerPatterns.nl`)

- **Scope:** pattern analysis L6100–6552; match + exhaustiveness L17800–18478; union helpers
  `TryResolveDeclaredUnionType` L17459 / `ResolveTypeWithSubstitution` L17497 ride along.
  The former Dogfood exhaustiveness kernel is already deleted and
  `AnalyzerExhaustivenessSelector.nl` was typed in `ceffed709`; preserve that completed work and
  do not recreate the stage.
- **Anchors:** `AnalyzePattern` L6100 (220-line dispatch); relational/list/property helpers
  L6320–6552; `AnalyzeMatchExpression` L17800; four exhaustiveness checkers (nullable L17917,
  anonymous-union L17978, union L18024, enum L18375); `FormatPartialCoverageCases` L18194
  (test-locked); `MatchKeywordLength = 5` (Analyzer.cs L27) — NonExhaustive diagnostics
  underline the `match` keyword.
- **Host adds:** `AnalyzeExpressionWithExpectedType` (→9), `PushScope`/`PopScope`/
  `DeclareSymbol` (→10), `ResolveDeclaredValueMember` (→6), pattern-name span getters (→8).
- **Stages:** (1) match analysis + exhaustiveness (plain `int[]` replaces
  `ArrayPool.Rent` — pooling was never observable; a temporary `AnalyzePattern` host member is
  allowed but must die in stage 3); (3) pattern analysis, delete the temp member, probes
  (list patterns on arrays/List/Span, relational on non-comparables, qualified union-case
  names, nested-union totality, guards NOT counting toward exhaustiveness, string-backed enums).
- **Hazards:** missing-case list ORDER comes from declaration order via the selector's flag
  scan — test-locked; do not "fix" exhaustiveness semantics in passing (guarded arms, `_` in
  payloads); the TypeInfo-side `UnionDeclarationInfo`/`EnumDeclarationInfo` are N# already —
  don't confuse with the AST `UnionDeclaration`/`EnumDeclaration`.

### Sub-arc 5 — Flow analysis (~950 LOC → `AnalyzerFlow.nl`)

- **Scope:** five regions — definite assignment L2936–3508 (external calls: only `Error` ×2,
  `ResolveType` ×1, `IsNullableType` ×1 — the cleanest walker port in the file); if-narrowing
  internals L4772–5037 (the `AnalyzeIfStatement` traversal shell STAYS C# until sub-arc 8;
  every narrowing DECISION moves); nullability flow typing L6833–6898; null-state after
  assignment L14455–14469; null-state scope lookup + error-tuple guards L19205–19347 (depends
  only on the `Stack<Scope>`). State models are already N# (`DefiniteAssignmentState.nl`,
  `NullState.nl`, `FlowNarrowing`/`Scope`/`ErrorTupleResultGuard` in AnalyzerStateModels.nl) —
  this arc ports the drivers.
- **Stages:** (1) definite assignment whole (NL definite-assignment branch-merge semantics —
  `IntersectWith` on if-branches, always-exits propagation, static-field exemption with its
  rationale comment, report dedup at (name,line,column)); (2) null-state bookkeeping + flow
  typing (`_suppressNullabilityFlowType` field L199 becomes a kernel property; C# save/restore
  sites L6681–6689 and the reset at L268 set it — delete the C# field); (3) narrowing
  internals (`ExtractFlowNarrowings` L4899 with `&&`-chain recursion, `TryRemoveAnonymousUnionArm`
  L4978, `TryExtractHasValueNarrowing` L5021, `ApplyNarrowingsToScope` L4856), probes
  (branch-partial read-before-assign, ctor missing field, `!= null` both branches,
  `is Circle` arm removal, `HasValue`, early-return residual narrowing, error-tuple guards,
  reassignment invalidating `x.y` facts).
- **Hazards:** the 2026-07-01 incident was THIS surface's neighborhood (null-state wording +
  spans) — golden diffs are stop-the-line; `Stack<Scope>` enumeration is top-first and the
  shadowing cutoffs depend on it (a misbehaving N# foreach over Stack is a stop-the-line
  compiler bug, never paper over with an order-inverting List copy); reflection reference types
  default to `Oblivious`, NOT MaybeNull (L6887–6891 — deliberate .NET-interop pragmatism;
  flattening floods users with noise); early-return residual narrowing choreography stays in
  the shell, driven by kernel-extracted lists; kernel shares `_scopes` and `_errors` INSTANCES —
  copies desynchronize silently; the `UnverifiedErrorResult` emission site is sub-arc 10's —
  this arc owns only the bookkeeping it consults.

### Sub-arc 6 — Member resolution (~1,860 LOC → `AnalyzerMembers.nl`)

- **Scope:** L8016–9877 — member/index access, the 294-line `ResolveMember` core (L9125),
  nullable access + NL905/NL907, undefined-member NL303 + suggestions, export-visibility NL308
  decision, SoA member intrinsics + the NL103 SoA message family, tuple members, reflection
  property/field resolution, extension methods (L9711+, `_extensionMethods` registry moves with
  its reset semantics). **This arc introduces the step protocol** (Done/NotFound/
  NeedTypeReferences + narrow Need-cases for reflection-type and nullability-metadata
  conversion) — the C# `ResolveMember` becomes the dumb step-loop shim.
- **Anchors:** `AnalyzeMemberAccess` L8016; `AnalyzeIndexAccess` L8109; `ReportPossibleNullAccess`
  L8424–8457 (byte-for-byte: `isNullConditional` early-out, `IsUnsafeNullState` gate,
  `(line,column,path,operation)` dedup against `_reportedNullabilityDiagnostics` — reset at
  L270 — message ``"Possible null {operation}: `{path}` is {stateLabel}"`` with the call
  special-case and the exact 4-way suggestion switch); binding recording into `_bindingMap`
  L8607/8716; `ReportUndefinedMember` L8881 via `ErrorMessageBuilder.UndefinedMember` +
  `NullabilityMetadata.FormatTypeInfo`; `ResolveDeclaredValueMember` L9563 (LAZY —
  `ResolveType` emits diagnostics; eager pre-resolution changes output); extension search
  L9783.
- **NullabilityMetadata.cs (261 LOC) is NOT this track's** — its port is owned by Track B's
  independent-filler sub-arc (track-b-kernel-binding-cli.md). If unlanded when this arc runs,
  route ConvertProperty/ConvertField/FormatTypeInfo through a step case; Track B collapses it. Never
  port it here — dual ownership means divergent nullable decoding.
- **Stages:** (1) kernel scaffold + step-protocol model types + ResolveMember core (with a
  `Reset()` mirroring exactly the L255–292 subset touching its fields); (2) member access +
  NL905/NL907 (shell passes receiver TypeInfo, null-state inputs, and span triples in);
  (3) index access + SoA bans (`_currentExpectedType` save/restore stays in the shell —
  brackets a shell-owned AnalyzeExpression; the DECISION `ShouldUseIntExpectedTypeForIndex` is
  kernel-owned); (4) undefined-member + suggestions + export visibility (the NL308 decision
  ports; the `ReportInaccessibleMember` reporter at L21987 stays a shell call until sub-arc 10);
  (5) extension methods; (6) shell-shrink audit (everything left is a step loop, an annotated
  re-entry, or gone; expect ≥1,500 LOC net removed) + checkpoint.
- **Hazards:** NL905 probes must confirm `?.` receivers produce NO diagnostic and dedup fires
  once per key; the NL303 member-name column collapsing to 1 is the 2383a4fa regression
  signature — spans come in from the shell until sub-arc 8; route all column scans through
  `CodeIntelligenceTextUtilities.nl`, never re-implement.

### Sub-arc 7 — Call binding (~4,080 LOC → `AnalyzerTypeBridge.nl` + `AnalyzerCalls.nl` + `AnalyzerReflectionCalls.nl`)

The safety-critical arc. **NL202 here is the only guard against EmitValueCoercion's silent
no-op for closed generics over emitted user types** — a lost check is silent garbage reads at
runtime, not a missing message. The full unit suite (not just the Analyzer slice) runs before
every commit in this arc.

- **Scope:** the reflection-type bridge L9878–10517 (`ConvertReflectionType` L9878,
  `TryConvertTypeInfoToClrTypeForBinding` L9952, `CreateFunctionTypeInfoFromDelegate` L10210,
  `TryConvertTypeInfoToClrType` L10323); source-call region L10518–12831 (`AnalyzeCall` L10518,
  ref/out addressability L10682–10913, `ValidateSyntheticFunctionCall` L10966 — the NL401/NL202
  front door with its rich-vs-fallback decision tree, `TryBindSyntheticFunctionArguments`
  L11115, SoA synthetic calls L11361–11556, `BindSyntheticNSharpCall` L11869 + scoring +
  NL208 constraints L12182–12397 + generic inference/LUB L12462–12831); reflection region
  L12832–13961 (`ReflectionBoundArgument` hierarchy, `BindReflectionCall` L12844,
  `TryBindReflectionArguments` L13062, method-group-to-delegate L13385,
  `FinalizeBoundReflectionCall` L13554, `GetReflectionMatchScore` L13836,
  `IsImplicitNumericConversion(Type,Type)` L13850).
- **Stages:** (1) bridge kernel — collapses sub-arc 6's reflection-type step cases
  (AnalyzerMembers calls the bridge directly); WellKnownTypes `Type` handles passed in as
  constructor values; (2) synthetic call validation — NL401 rich
  (`ErrorMessageBuilder.WrongArgumentCount`, docs URL `errors/NL401`) vs plain fallback, NL202
  rich (`WrongArgumentType` with parameter name, 1-based index) vs the exact
  `"Argument '{name}'"`/`"Argument {index}"` fallback shape commit 52c8a0d8 restored, NL402
  missing-argument + `"Use {signature}."`; (3) call-dispatch decisions + ref/out + SoA
  synthetic calls (the recursion shell — `AnalyzeCallCallee`, argument loop,
  `_currentExpectedType`/`_allowUnboundCallableReference` bracketing — stays C#, annotated for
  sub-arc 9); (4) overload selection + generic constraints/inference/LUB — scoring must be
  **ordinally identical**; add score-vector tests asserting the chosen overload AND the full
  vector incl. generic-parameter-cost tie-breaks; name the `(TypeInfo)` parameterless-ctor
  check distinctly from the `(Type)` overload at L16591 (sub-arc 9's); (5) reflection binding —
  **probe `MakeGenericMethod` on an MLC MethodInfo from N# first** (L13617 constructs, never
  executes, but is unproven from a kernel; if it declines, isolate the single call behind a
  step request — never keep the whole 147-line method in C# for one line); also move the
  unbound-reflection diagnostics (L11622–11821, `FormatReflectionMethodSignature` L11715);
  (6) shell-shrink audit (expect ≥3,300 LOC net removed) + the guard-probe suite + checkpoint.
- **Mandatory guard probe at every stage boundary:** a program constructing a generic
  record/class over an emitted user type and passing a wrong-typed argument → MUST produce
  NL202 at `check`; the corrected program must `build`+run with correct values. Include the
  partial-init / early-return / wrong-type triple per the verify-first playbook.

### Sub-arc 8 — Statements & assignments (~3,900 LOC → `AnalyzerStatements.nl` + `AnalyzerAssignments.nl` + extended `DiagnosticSpanResolver.nl`)

- **Scope:** statements L3509–6099 (minus sub-arc 5's flow pieces) and assignments/mutation
  L13962–15878 (minus L14455–14469). Span machinery L4024–4370 extends the EXISTING
  `DiagnosticSpanResolver.nl` — never a duplicate.
- **Stages:** (1) span machinery (`GetStatementDiagnosticSpan` L4037,
  `GetExpressionDiagnosticSpan` L4069, `GetTokenLength` L4301, `ScanQuotedTokenLength` L4312) —
  with a **mandatory differential span gate**: fresh CLI `check --json` over `examples/` +
  test fixtures before (stash-clean) and after; every line/column/length byte-identical; this
  also deletes the host's span-getter seam members from sub-arcs 3/4/6; (2) statement leaves
  part 1 (expression statements + must-use incl. reflection `HasMustUseAttribute(MethodInfo)`,
  assert, local functions, variable declarations, tuple deconstruction); (3) part 2 (loops +
  sequence element typing over `LoopSequenceTypeFacts.nl`, return + mismatch messages, try/
  finally NL319 — port the ECMA-335 rationale comment L149–159 and the reset-at-nested-body
  semantics of the `_finallyDepth` trio EXACTLY — using/dispose, lock NL320 — the CS0185
  analog; value-typed lockee is unverifiable IL that segfaults in Monitor.Enter — switch shell
  dispatching into sub-arc 4's kernel); (4) statement dispatch + an N# statement-context class
  rehoming `_inLoop`/the finally-depth trio/`_currentReturnType`/async flags (per-function-body
  state, instantiated by the C# Analyzer until sub-arc 10 rehomes everything); (5) assignment
  core + compound assignment (operator result via sub-arc 3's kernel) + events
  (EventSubscriptionTests is the lock — confirm they execute); (6) write-target validation +
  SoA mutation subsystem + `CheckMemberWriteReceiverIsVariable` L15276 (its
  `Dictionary<Expression, TypeInfo>` keys follow sub-arc 1's reference-equality contract — the
  MemberWriteThroughValueCopy tests are the canary) + readonly enforcement L15437–15852; rerun
  the span corpus diff; (7) checkpoint.
- **Hazards:** spans were half the 2026-07-01 incident — do not trust reasoning about spans,
  diff the real JSON; behavioral probes: return-inside-finally → NL319 (not an
  InvalidProgramException at runtime), `lock (someInt)` → NL320, discarded must-use call;
  commit 65eb92b9 is the span-offset prior art — spans must have exactly ONE owner, no
  two-layer compensation.

### Sub-arc 9 — Expressions & declarations (~4,400 LOC → `AnalyzerExpressions.nl` + `AnalyzerDeclarations.nl` + `AnalyzerAttributeValidation.nl`)

The convergence arc: expression dispatch cannot leave C# while any case has a C#-only body,
which is why it runs after sub-arcs 3–7.

- **Scope:** declarations + attributes L436–2935; expression dispatch + small forms L6553–7053
  (minus sub-arc 5's flow glue); lambda + expression trees L15879–16314; composite expressions
  L16315–17515; and the formerly-unowned strip **L17516–17799** (is/cast/await/throw/typeof/
  nameof/sizeof/checked/unchecked/with) — owned HERE, settled.
- **Stages:** (1) attribute validation subsystem wholesale (L499–1582: constant classification —
  `AttributeArgumentConstantKind` already N# — `TryResolveClrAttributeType` L1054 probing
  external-type candidates with/without the "Attribute" suffix, constructor matching L1278,
  argument CLR-type inference, every attribute diagnostic byte-exact); (2) test/setup/teardown +
  `AnalyzeFunctionDeclaration` L1833 + generator/task-like return checks + `StatementAlwaysReturns`
  L2126 (export publicly — sub-arc 8's statement walker consumes it); `ValidateOperatorOverload`
  stays a seam call until sub-arc 10; (3) type-member declaration analyzers L2185–2935 + the
  `AnalyzeDeclaration` dispatch (enum duplicate-member and int/string-backing messages
  test-locked; ctor definite-assignment hooks call sub-arc 5's kernel; copy the pass-1
  `NominalTypeInfoFactory.*` call style at L318–345); (4) lambda + expression-tree restrictions
  (`FindUnsupportedExpressionTreeExpression` L16072 — pure AST walk, fully kernel-expressible);
  (5) composite expressions incl. **`TryResolveObjectInitializerMemberType` L17024 — treat like
  an emitter change**: probe wrong-typed initializer value on a generic user type, partial
  required-member init, SoA named-initializer ban — each byte-identical to pre-port; full suite
  before commit (highest-risk commit of the whole analyzer arc); (6) the L17516–17799 family,
  then the master dispatch L6553–6832 + callable-reference rules + small forms L6899–7053;
  delete every emptied private expression method; exactly one `AnalyzeExpression` forward
  survives for sub-arc 10's ranges; deleting the dispatch also deletes sub-arc 3's operator
  shells and the host's `AnalyzeExpressionWithExpectedType` re-entry member; (7) checkpoint.
- **Hazards:** full suite at every dispatch-touching stage (3, 5, 6) — dispatch touches
  everything; expression analysis is where a C#-callback temptation is strongest — the shell
  computes argument/operand types and passes values; genuine interleaved re-analysis is an
  explicit step case, never a delegate.

## Sub-arc 10 — Spine & metadata host (the terminal slice)

Every prior sub-arc is a leaf relative to this spine; porting it last collapses ALL remaining
host-seam members instead of creating new ones.

1. **Imports/namespaces/typo suggestions → `AnalyzerImports.nl`.** L21499–22094 minus
   `GetExternalSearchAssemblies` (assembly lists passed in) and minus the
   `ProcessImportForAssemblyLoading` host call (seam until step 4): `ProcessImports`/
   `ProcessFileImport` (file IO proven from N#; imported-file parses arrive pre-parsed until
   step 3's parse seam), namespace caches as kernel fields, `ExtractPublicSymbols`,
   `CheckImportCollisions` (fold into `AnalyzerDiagnostics.CreateImportCollision`),
   `ValidatePackageName`/`IsValidIdentifier`, typo suggestions L22482–22530 via
   ErrorSuggestions.nl.
2. **Scopes/DeclareSymbol/sinks → `AnalyzerCore.nl` (part 1).** L20954–21498: Push/PopScope
   with the paired `_semanticScopeIds` discipline (SemanticModel scope IDs in lockstep —
   AnalyzerSemanticModelTests is the lock; desync corrupts IDE features silently),
   `DeclareSymbol` (fold AnalyzerBindingFacts/OverloadSignatureFacts into direct N# calls),
   `DeclareType`, params/default validation, `ValidateOperatorOverload` (collapse sub-arc 9's
   seam), Error/Warning sinks, `GetSourceSnippet`. The scope stack becomes N#-owned state.
   Collapse every scope/DeclareSymbol/Error seam left by sub-arcs 2–9. Full suite — every
   diagnostic in the product flows through these sinks.
3. **Type + identifier resolution → `AnalyzerCore.nl` (part 2).** L18479–19204 + L19348–19507:
   ResolveType family, anonymous unions, `TryResolveExternalType` over MLC assemblies +
   `_externalTypeCache`, Lookup*, ResolveIdentifier, `CheckVisibilityConvention`. Preserve the
   `_reportUnresolvedTypes` opt-in exactly (pass-1 and lazy cross-file resolution stay lenient —
   design comment L181–185). Probe: unresolved type → NL201 identical span/message.
4. **The `Analyze()` driver + state rehoming; expose the stable N# analyzer API.** The N# analyzer
   class holds the full field inventory. Port the **state-reset ledger L255–292 line by line**:
   cleared per `Analyze()` — errors, scopes, imports, semantic model, binding map,
   `_externalNamespaceCache`, **`_projectNamespaceCache` (it RESETS)**,
   `_projectFileNamespaceCache`, `_typeDeclarationFiles`, ~15 scalars; survives —
   `_externalTypeCache` (never cleared), the MLC + `_mlcAssemblies`, `_referenceLoadFailures`
   (drained by NL923 reporting, not reset), `_projectSourceTexts`/`_projectCompilationUnitCache`
   (cleared only by `SetProjectSourceTexts`, L232–240). **Parse-seam decision (binding):**
   project type resolution L18890–19094 and `ProcessFileImport` re-parse sibling files; the
   Parser is C# (Track C shrinks it to a silent AST producer; Track H deletes it). Define an N#
   interface `AnalyzerParseProvider { TryParseFile(path, sourceText): CompilationUnit? }` that
   a mechanical C# parse host implements — a typed host seam carrying ZERO analyzer policy.
   Retarget `MultiFileCompiler` and every non-LSP product consumer to the stable N# API in this
   track. Track G retargets `DocumentManager` as part of its front-end re-host. If a temporary
   facade remains for that one consumer, record its exact consumer and G deletion commit; G
   deletes it in the same commit that removes the consumer. H only verifies absence. This is an
   IDE integration slice: the
   full VS Code-enabled gate, extension reload, computer-use verification, and screenshots are
   mandatory, in addition to AnalyzerBindingMapTests/AnalyzerSemanticModelTests.
5. **Metadata host policy → `AnalyzerMetadataHost.nl`.** Port the POLICY regardless of the
   sub-arc-0 verdict: search-directory composition, the TFM probe order, NuGet path composition
   (`~/.nuget/packages`), `LoadFromProjectConfig`/`LoadProjectReference`/`LoadNuGetPackage`/
   `LoadProjectReferenceFile`/`ProcessImportForAssemblyLoading` decision logic (reuse
   `CompilationReferenceResolverKernels.nl` patterns), NL923 failure-recording, and the
   WellKnownTypes resolve list + fallback assembly order (core → System.Private.CoreLib →
   NSharpLang.Runtime for `Union`2`/`Result`2` — keep throw-on-missing primitives; this is the
   e3702449 regression surface). GO path: the resolver subclass moves to N# too. NO-GO path:
   the ~95-line C# shell survives with a MECHANICAL-GLUE file-header comment naming this track
   and Track H. Do NOT delete the C# loading path before
   `tests/AnalyzerMetadataLoadContextTests.cs` passes against the N# policy — reference-load
   breakage masquerades as "type not found" (NL923 design comment L174–178). Probe: NuGet +
   project-reference project checks identically; a deliberately broken reference still yields
   NL923.
6. **Facade audit + final checkpoint.** Grep Analyzer.cs for any private method body beyond a
   forward — port it or classify it. Target: **≤ ~500 LOC**. Grep for seam interfaces —
   zero remaining C# implementations except `AnalyzerParseProvider` (and the NO-GO shell).
   Correct stale memory/docs ("Analyzer retire gated on columnar coverage"); record the probe
   verdict in memory. Because the LSP shares this analyzer, the rehost is IDE-affecting by
   construction: run the VS Code-enabled `./scripts/test-all.sh --commit`, plus
   `./scripts/reload-vscode-extension.sh`, plus computer-use visual verification (diagnostics
   squiggles, hover, go-to-definition on a sample project). Non-negotiable.

## Cross-track contract

- **Sub-arc 1 (AST in N#) unblocks Track G** (track-g-tooling-ide.md): typed-AST linter,
  code-intel, and LSP structure kernels are hard-gated on it. Land it first after the probe and
  announce.
- **Sub-arc 0's probe verdict feeds Track H** (track-h-tests-release.md): GO/NO-GO determines
  whether `NSharpMetadataResolver` appears in the final mechanical-glue inventory. Report the
  verdict when the probe commit lands, not at track end.
- **Consumer retargeting is explicit.** Track D exposes the production N# analyzer API and
  retargets `MultiFileCompiler` plus non-LSP consumers. Track G retargets `DocumentManager` and
  its IDE consumers, then deletes the zero-consumer Analyzer facade in that same commit. H only
  verifies the absence and owns no analyzer port, routing decision, or facade deletion.
  Parser.cs/ErrorReporting.cs/AstNodeFinder.cs remain with
  their named syntax/tooling owners until the front-end deletion.
- **Track C** (track-c-syntax-frontend.md) owns Parser.cs and syntax diagnostics; Track D's
  only Parser coupling is the `AnalyzerParseProvider` seam and whatever compilation fallout the
  AST move forces — avoid gratuitous Parser churn.
- **Track B** owns the NullabilityMetadata.cs port (its independent-filler sub-arc); sub-arcs 6/7 seam to it if unlanded.
- **Track A** owns remaining product-gate blockers; the historical baseline is retired.
  **Track B** owns SDK repins (request + announce)
  and makes Track D's kernel iteration cheaper once static binding lands — do not block on it.
- **Contention:** Track D's file set is essentially private (Analyzer.cs, the new .nl kernels,
  new test files) — stage only those; `tests/Tests.csproj` and shared fixtures are append-only.

## What NOT to do

Merged and deduplicated across the whole track; each item has bitten someone or is one grep
away from doing so.

- **Never delete-then-replace.** Replace-then-delete in the same commit, always. The 2026-07-01
  incident is canonical: "Delete fallback" commits dropped diagnostic spans, rich NL401/NL202
  wording, ToString displays, and WellKnownTypes' NSharpLang.Runtime loading (~107 failures;
  repaired by 2383a4fa, e3702449, 19a9df58). If a golden diff appears: stop and fix, never
  re-baseline.
- **Never reword, simplify, reorder, or "improve" any diagnostic** — message text, suggestion
  text, spans, dedup keys, error ordering are all test-locked. Parity first; language changes
  are separate proposals.
- **Never weaken an NL202 path** (call arguments, object initializers) — it is the
  EmitValueCoercion front door; a lost check is silent garbage at runtime.
- **No delegates into kernels** (`Func<>`/`Action<>` route-backs — the retired DocQuery
  `ScoreTypeMatch` anti-pattern). Seams are the AnalyzerHost virtual class with one-line bridge
  forwards, typed N# interfaces implemented by the facade, or explicit step-protocol cases.
  No decision logic in any bridge override, ever.
- **No new C# product logic.** C# edits delete bodies, add one-line forwards, or implement
  zero-policy seams. Nothing else.
- **Kernels go in BootstrapServices only** — the Dogfood project/loader are deleted and must not
  be recreated — and never
  referencing the Compiler assembly (circular).
- **Do not change state-reset semantics.** One Analyzer instance is shared across all project
  files and by the LSP; which fields reset per `Analyze()` vs survive is load-bearing. Port
  L255–292 line by line; `_projectNamespaceCache` resets.
- **Do not replace shared instances with copies** — `_errors`, `_scopes`, the binding map are
  cross-region-visible; copies desynchronize silently.
- **Do not add Equals/GetHashCode/ToString to AST classes**; do not rename AST types,
  properties, or constructor parameters.
- **Do not copy the `GetProperty("Name")` reflection idiom into any new kernel** — sub-arc 1
  removes its reason to exist; any new string-keyed member access in kernel code is a
  regression.
- **No LINQ chains or C# switch-expressions in kernels**; no bare `this` as expression/argument;
  no `GetType()` on a typed receiver (cast to `object` first); no `ArrayPool` imported
  reflexively; no `Assembly.Load(` literal anywhere (source-scan guard self-trips).
- **Never raw `dotnet test --filter`** (documented xUnit hang); never `git add -A` (concurrent
  sessions); never gate from a worktree nested under the repo root (breaks the benchmark gate);
  never trust the installed `~/.nsharp/bin/nlc` (stale-binary false negatives).
- **Do not skip or defer the sub-arc-0 probe**, and do not delete the C# metadata-loading path
  before the MLC tests pass on the N# policy.
- **Do not port other tracks' property**: NullabilityMetadata (Track B), Parser internals
  (Track C), or the final IDE-consumer retarget/facade deletion (Track G). Do not "unify" the
  flow walkers
  with null-state machinery or otherwise refactor across parity — post-ownership at best.
- **Temporary seams die within the sub-arc that created them** (e.g. sub-arc 4's interim
  `AnalyzePattern` host member). A track is not done while a temp seam survives.

## Track exit criteria

- [ ] Probe verdict (GO/NO-GO on subclassing `MetadataAssemblyResolver` from N#) recorded in a
      commit message and in memory; probe file deleted; Track H notified.
- [ ] `Ast/{Statements,Declarations,Expressions}.cs` deleted; 120 N# AST classes in
      BootstrapServices with identical names/properties/ctor-parameter names/order/defaults;
      special members preserved (IsAsyncIterator, OperatorKeywordSpan/OperatorSymbolSpan/
      ReturnLifetime, FileImport path/diagnostic members, IsResultFactory, IsExhaustive,
      IsIndexerInitializer); no equality overrides; ParserTests span pins green.
- [ ] All track kernels exist in BootstrapServices and own their regions: AnalyzerConversions,
      AnalyzerOperators, AnalyzerPatterns (preserving the typed
      AnalyzerExhaustivenessSelector), AnalyzerFlow, AnalyzerMembers, AnalyzerTypeBridge/
      AnalyzerCalls/AnalyzerReflectionCalls, AnalyzerStatements/AnalyzerAssignments (+ extended
      DiagnosticSpanResolver), AnalyzerExpressions/AnalyzerDeclarations/
      AnalyzerAttributeValidation, AnalyzerImports/AnalyzerCore/AnalyzerMetadataHost.
- [ ] Stable N# analyzer API owns all semantics and all non-LSP consumers are retargeted. Any
      temporary `Analyzer.cs` facade is ≤ ~500 LOC, zero-policy, used only by the exact G-owned
      IDE consumer recorded in `STATUS.md`, and deleted by G after its re-host. The NO-GO
      metadata resolver shell is separately inventoried mechanical glue.
- [ ] Diagnostics byte-identical across the full probe corpus (NL103-SoA, NL201, NL202, NL208,
      NL303, NL308, NL319, NL320, NL401, NL402, NL905, NL907, NL923, definite assignment,
      exhaustiveness, operators, spans via the `check --json` corpus diff); DiagnosticGoldenTests
      green; overload-selection score vectors ordinally identical; the EmitValueCoercion
      front-door probe passes.
- [ ] AnalyzerTests, AnalyzerSemanticModelTests, AnalyzerBindingMapTests,
      AnalyzerMetadataLoadContextTests, EventSubscriptionTests, DiagnosticSpanResolverTests,
      CheckCommandTests, and all new kernel suites green with zero current failures.
- [ ] Every production-routed analyzer/AST commit carries the VS Code-enabled gate, extension
      reload, computer-use visual verification, and screenshots; inert candidate/oracle commits
      use the appropriate backend checkpoint. Final screenshots confirm diagnostics, hover, and
      go-to-definition.
- [ ] Stale memory/docs corrected (AST ownership, reflection-idiom prescription, "analyzer
      retired by columnar coverage"); probe verdict and any SDK-shape findings recorded.
- [ ] No new C# product logic anywhere in the track's diff; commits are per-stage with
      `Evidence:` lines; no temp code survives.

## Gotchas & prior art

- **Exemplar commits:** 013488fd / 2383a4fa — the group-sized recipe (kernel + shrunk C# +
  focused tests in one commit). The "Restore … via N# kernels" family (2383a4fa name spans +
  rich call diagnostics, e3702449 well-known types, 19a9df58 ToString displays) shows what
  cleanup looks like when a port drops behavior — study them to avoid needing them. 3fd604c2d
  (Lexer.cs deleted, Lexer.nl statically consumed) is the static-binding shape sub-arc 1
  extends; 56948135 decoupled TypeInfo from the AST records to prepare the move; 52c8a0d8 shows
  how recently and finely NL202 wording is tuned; 65eb92b9 is the one-owner-per-span-offset
  precedent.
- **VERIFY-FIRST is the soundness arbiter** (project memory): execution probes against the real
  N# pipeline overturned four confident adversarial reviews in the union/class arcs. Reviews
  reason in C# CSxxxx; the oracle speaks NLxxx. Probe partial-init / early-return / wrong-type
  before trusting ANY review verdict — especially on operator typing, exhaustiveness,
  overload-scoring "equivalence", and span refactors.
- **Silent-failure surfaces outrank loud ones:** overload-score drift, narrowing/reset
  mistakes, and coercion-check gaps produce zero diagnostics and wrong behavior. That is why
  score-vector tests, the reset ledger, and the EmitValueCoercion probe are mandatory rather
  than nice-to-have.
- **MLC discipline:** metadata-only inspection never executes loaded code — `MakeGenericType`/
  `MakeGenericMethod` construct, not run; `GetInterfacesSafe`/`GetBaseTypeSafe` swallow loader
  exceptions on purpose; never swap MLC types for runtime `Type.GetType` lookups; never add
  runtime `Assembly.Load` (AOT end-state: static binding is the only compatible route).
- **`Stack<T>` enumerates top-first** — scope-shadowing cutoffs depend on it; a pinned-SDK
  foreach misbehavior over `Stack<Scope>` is a stop-the-line compiler bug (repin via Track B),
  not something to paper over.
- **Reflection reference types default to `Oblivious` null-state**, not MaybeNull — deliberate
  .NET-interop pragmatism; flattening it floods external-API users with noise.
- **dev.sh escalation on Ast/* and shared files is correct, not a nuisance** — the model fans
  out everywhere; take the full-suite run for those commits.
- **Concurrent sessions in this checkout are normal:** stage only your files, gate from the
  repo root or a `/tmp` worktree, commit fast after gating, and keep `AnalyzerHost.nl`/
  `tests/Tests.csproj` edits additive.

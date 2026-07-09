# Systems-language closeout — live execution ledger

**Audited implementation base:** `49c0105c8` (2026-07-09), 253 commits after the original
`9538ab66` planning snapshot. This file is the resume point. Current code and git history outrank
it; update it whenever they disagree.

**Emitter handoff debt:** `399008ea9` proved range/index value/read behavior but introduced C#
emitter decisions and C# assertions that the no-new-C# closeout rule requires E0 to replace with
N# lowering/plan ownership and gated `.tests.nl` successors before deleting those branches and
assertions. No further C# growth is permitted. Array `Index`/`^` writes, compound/postfix mutation,
and ref/out address lowering remain plan-first debt after that replacement, while range writes/ref
and string writes remain intentional errors.

Status meanings:

- `complete` — the production route and required evidence exist at the recorded commit.
- `partial` — useful code landed, but the production route, parity proof, deletion, or exit gate
  is incomplete. Partial never satisfies a dependency that requires completion.
- `ready` — prerequisites are complete and one owner may start after revalidation.
- `blocked` — a named stop gate failed; another independent ready stage should proceed.

## Verified campaign state

- A detached-HEAD `dotnet test tests/Tests.csproj` run at `fb856ee46` completed with zero
  failures on 2026-07-09. The former 67-failure baseline and all stash/`comm` instructions are
  retired.
- The fresh non-VS-Code product gate at `49c0105c8` ran all 3,183 unit tests green, then ended
  `FAILURES: 4`. The concrete product blockers are inventoried below. Unit green is not a
  substitute for the Track A product gate.
- Range/index value and read semantics are complete at `399008ea9`: all four range forms,
  array/string/reference-array slicing, typed and conditional `Index`/`Range`, byte/short/enum
  endpoints, parenthesized starts, and the existing Span integer-index path have persisted
  execution evidence. `RangeAndIndex.nl` and `OpenEndedRanges.nl` build/run and their four emitted
  assemblies passed ILVerify.
- `NSharpLang.Compiler.Dogfood`, `DogfoodKernelLoader`, reflection delegate binding, and the
  parity corpus are gone. Static binding is complete.
- Per-file columnar source identity, construction, decline provenance, and multi-file routing are
  in the production route.
- Plain test declarations and assert/assert-throws are modeled. The full test grammar is not:
  setup/teardown, table-driven `with`, skip, and full framework parity remain live gaps.
- Syntax-diagnostic kernels exist but are preparatory: `ColumnarSyntaxDiagnostics.ParseFile`
  has no production consumer or direct differential parity suite. Do not count the diagnostic
  families as ported until that proof and routing exist.
- The first native compiler-closeout probe reached project-reference compilation on 2026-07-09,
  but rebuilding `NSharpLang.Compiler.BootstrapServices/project.yml` through `nlc test` activates
  the legacy validation path and rejects sources that the pinned Stage-0 SDK compiles with
  `NSharpEmitValidateWithLegacyAnalysis=false`. A DLL-reference probe then reached emission but
  correctly declined construction of an unmodeled external compiler-service type. C/D/H must
  remove the validation discrepancy; E0 successor tests exercise plans through their production
  route instead of retaining either probe as a fallback.
- E0's direct Reflection.Emit prerequisite is now production-routed through
  `ColumnarExternalBindingPlans.nl`: N# selects exact assembly-qualified types, static members,
  opcode fields, call forms, and signatures; the existing emitter only materializes that payload
  and is 124 lines smaller. The native `reflection-emit-bootstrap` project compiles real
  `ILGenerator` local/label/opcode overloads, its one test passes, and the focused Columnar suite
  remains 102/102 green. This is the interop prerequisite, not E0 completion: N# plan execution,
  a production lowering family, and old lowering-branch deletion remain next.

## Ownership trend that changed the priority

| Owner | `9538ab66` | `fb856ee46` | Verdict |
|---|---:|---:|---|
| `ColumnarIlEmitter.cs` | 13,712 LOC | 21,828 LOC | frozen legacy owner; E now deletes it |
| `Analyzer.cs` | 22,783 LOC | 23,451 LOC | no retirement yet |
| `Parser.cs` | 7,117 LOC | 7,117 LOC | no retirement yet |
| `SystemsAnalyzer.cs` | 2,390 LOC | 2,390 LOC | not started |
| `Linter.cs` / `Formatter.cs` | 1,611 / 2,303 LOC | unchanged | not started |
| `OutputFormatter.cs` | 669 LOC | 379 LOC | real but incomplete reduction |
| `DocQuery.cs` | 918 LOC | 740 LOC | partial |
| `Program.Testing.cs` | 740 LOC | 653 LOC | partial |

LOC is a smoke alarm, not the completion test. The completion test is sole N# production
ownership plus deletion or an approved mechanical-host inventory. The emitter growth makes the
first post-audit priority non-negotiable: establish N# lowering plans before any more language
coverage work.

## Active dependency queue

Execute dependency-ready lanes in parallel only when their file domains do not contend. With one
owner, finish one commit-sized stage before switching.

1. **E0 — land the N#-only ownership ratchet foundation and discharge `399008ea9`.** Finish the
   N# code-plan model, implement plan execution in N#, route production directly to it, and port
   reflection-free scalar/procedural lowering end to end without a new C# replayer, seed,
   whitelist, callback, or test. Replace the range/index C# assertions with gated `.tests.nl`
   successors, move their lowering decisions into the N# owner, then delete the corresponding C#
   branches and assertions. Member/index/call capability gaps are N# language/interop
   prerequisites, not permission for a C# bridge. No force-old flag may survive. Add an N#-owned
   ownership guard whose shell/build entrypoint is mechanical only.
2. **C2a — prove the existing syntax-diagnostic candidate.** Before adding another diagnostic
   family, add native N# ordered full-tuple successor tests over invalid, clean, and recovery
   corpora, then delete the superseded C# assertions. Resolve the current duplicate-lex/collector
   architecture against the single-parser contract; do not grow two diagnostic parsers.
3. **D1 — move the AST model to N#.** Revalidate live shapes, preserve names/defaults/mutable
   members, delete the C# AST records atomically, and run the IDE-required evidence because the
   shared analyzer/tooling path consumes those types. This unlocks typed linter and code-
   intelligence kernels.
4. **B3a — close DocQuery in parallel when an owner is available.** Static binding is complete
   and this file domain does not contend with E0/C2a/D1. Run the live go/no-go API probes, move
   remaining lookup/index/format policy into the existing N# owner, and shrink C# to a raw
   metadata/XML-loading host or delete it. Nullability is a separate B3b lane coordinated with D.
5. **Close Track A through N# ownership.** Fix the recorded product-gate blockers—including the
   remaining native-test grammar—through N# parser/semantic/lowering owners. Record the first
   fresh green product-gate commit, then mark A complete.
6. **Continue ownership lanes by the DAG.** Prefer a vertical stage that deletes the largest
   reachable old owner: C syntax flip; D analyzer families; E lowering families; B residual
   DocQuery/nullability/CLI ownership; F systems policy; G tooling/LSP; H tests/release. Never
   return to open-ended C# corpus widening.

## Fresh product-gate blocker inventory (`49c0105c8`)

Reproducer for the complete checkpoint: `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`.
The isolated run ended `FAILURES: 4` after 3,183/3,183 unit tests passed.
`RangeAndIndex.nl` and `OpenEndedRanges.nl` both passed. Focused decline reproducers use the fresh
`src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll` plus
`NSHARP_COLUMNAR_DECLINE_LOG=1`; IL rows were confirmed directly with `ilverify` and the same
framework-reference set as `scripts/ilverify.sh`.

| Product blocker | Deepest evidence | Owning N# layer and dependency |
|---|---|---|
| Generated `nsharp-webapi` project | `emit.declaration.base-type`: base/interface type `ControllerBase` could not be resolved for `WeatherController`. Reproduce: generate `nsharp-webapi`, then run `nlc build` in it with decline logging. | Track E external type/base binder. E2 owns the decision after E0's plan boundary and E1's handle-capability matrix. |
| `examples/08-async/AsyncStreams.nl` | `parse.declaration-scan` at 1:1: function scan rejected the first `async func*`. | Columnar parser/function-declaration facts in Track A/C must model `async func*`; generator state-machine lowering then belongs to E plans. No handwritten C# coverage; E0 is the lowering prerequisite. |
| `examples/09-linq-and-collections/Iterators.nl` | `parse.declaration-scan` at 3:1: function scan rejected the first `func*`. | Columnar parser/function-declaration facts in Track A/C must model `func*`; iterator state-machine lowering then belongs to E plans. No handwritten C# coverage; E0 is the lowering prerequisite. |
| `IssueTracker.dll` IL | `IL:MethodAccess` in `IssueTracker.Routes::Map`: `ldftn Program::<Lambda>_0` targets a private method on another type. | Track E N# lambda-definition placement and visibility plan; depends on E0, then the E3 definition registry/E4 lowering family. |
| `RecordStructs.dll` IL | At `Program::Main` offset `0x55b`, `callvirt Color::<Clone>$` consumes a `Color` value instead of its address (`IL:CallVirtOnValueType` and `IL:StackUnexpected`). | Track E N# record-`with`/value-receiver lowering plan after E0; the old C# branch must be deleted with the fix. |
| `RecordsAndInterfaces.dll` IL | `IL:InitOnly` in `Circle::<InitializeFields>$`: helper method executes `stfld` for readonly `Pi` outside `.ctor`. | Track E N# declaration/constructor initialization plan; depends on E0 and the E3 definition model before its E4 lowering deletion. |
| `TaskCli.dll` IL | `IL:MethodAccess` in `Formatter::FormatTags`: `ldftn Program::<Lambda>_0` targets a private method on another type. | Same E lambda-definition placement/visibility owner and E0 → E3/E4 dependency as `IssueTracker.dll`. |
| `WeatherDemo.dll` IL | `IL:MethodAccess` in `GetMinMaxTemp` and `GetHotDaysSummary`: three `ldftn` sites target private `Program::<Lambda>_0..2` methods from `WeatherService` (two normalized gate findings). | Same E lambda-definition placement/visibility owner and E0 → E3/E4 dependency; both affected methods are independently pinned. |

Do not baseline these IL findings: they are product-emission defects. The four gate failure counts
are Web API template build, `AsyncStreams`, `Iterators`, and the IL verification step; the IL step
contains the five assembly rows and seven normalized verifier codes above (with Weather's repeated
member finding deduplicated by the gate).

## Track status

| Track / stage | Status | Evidence | Remaining binding work |
|---|---|---|---|
| A1 decline diagnostics | complete | `18df2415e`…`465856bef` | Preserve stable reason ids and spans. |
| A2 product-path restoration | partial | 3,183-unit green/four-category product-gate inventory at `49c0105c8`; range/index A0 at `399008ea9`; plain tests in `d34e7e6e7`; asserts in `9996d4525` | Fix the inventoried template, iterator/async-iterator, and IL blockers; full test grammar; dynamic corpus sweep; fresh green product gate. All remaining coverage is N# plan-first. |
| B1 static kernel binding / Dogfood deletion | complete | `27bb97773`, `aa9ec5326`, `3c963eb5d` | Never recreate reflection binding or the deleted project. |
| B2 JSON and CLI decisions | partial | unverified partial; live inventory required | Re-inventory live C# command policy; `OutputFormatter.cs` is not yet a tiny host. |
| B3a DocQuery | ready | partial N# owner exists; live inventory required | Independent lane now: delete remaining decision bodies; keep only proved raw metadata/XML extraction/loading glue. |
| B3b nullability | partial, blocked on D caller seam | partial N# owner exists; live inventory required | Remove `typeOverride` callbacks with D's canonical type/call bridge; keep only proved raw NullabilityInfo extraction glue. |
| C1 per-file pipeline/provenance | complete | `dd494cd29`…`6382af774` | Preserve file identity; no merged-source route. |
| C2 syntax diagnostics | partial | foundation `760cf0203` plus family ports | Direct differential harness first; integrate with the real columnar parse; then finish families. |
| C3 syntax ownership flip | ready after C2 | — | Flip compiler, FormatSafe error gate, lint/fmt, imported-file, and LSP consumers; delete C# reporting. |
| D0 MetadataLoadContext probe | complete | `fef45dd22` | Apply the recorded verdict to the final metadata host inventory. |
| D1 AST model | ready | — | Atomic N# move and C# record deletion. |
| D2–D10 semantic ownership | ready after D1 by dependencies | — | Port vertical families, canonical ids, shared package policy, and retarget non-LSP consumers. |
| D/G facade cleanup | blocked on D API + G re-host | — | G retargets the final IDE consumer and deletes the then-zero-consumer facade; H only verifies. |
| E0 N# lowering-plan ratchet + range/index debt | in progress and highest priority | direct N# Reflection.Emit bootstrap in current slice; native probe 1/1 and Columnar 102/102 green; `bc16cac51` adds range/index native successors (13/13 direct, not gated yet) | N# plan execution, production route, range/index and first scalar/procedural C# branch deletion, native gate wiring, N#-owned cross-language guard. |
| E1–E6 emitter ownership | pending after E0 as applicable | — | N# binder/resolver/passes/plans; typeref policy in N#; Cecil deletion; mechanical PE host only. |
| F1 systems input columns | ready after current parser writer releases the file | — | Attribute/modifier/alloc facts only; no F-specific semantic identity. |
| F2–F4 systems policy | blocked on C/D canonical identity contract | — | Stable caller node and resolved declaration/function ids, N# walker, mechanical fact flatten, C# owner deletion. |
| G tooling / IDE | partial only for isolated prior work | `0d42981b0` deleted the XML-doc stub | Linter, formatter, code-intel, completion, handlers, and front-end re-host remain. |
| H1 native runner host shrink | ready | runner model/JSON/test-policy ports are partial | Delete xUnit-controller policy and finish N# discovery/lifecycle/result ownership. |
| H2–H3 native estate/CLI migrations | blocked on A grammar + green product gate | — | Gate the complete native-test route before deleting predecessor suites. |
| H4–H8 release/endgame | blocked on named track exits | — | Playground, C# test closeout, deletion integration, docs, and final audit. |

## Corrections that override the track notebooks

These are binding. Patch the relevant track file when launching the affected stage.

1. **Node kinds are live, not reserved by old prose.** Kind 57 is already
   `CheckedContextExpression`; the in-flight range slice claims kind 69. Re-read the one live
   ledger, allocate the next globally free kind, and update every producer, consumer, and ledger
   entry in the same commit. Never follow a fixed number from the July 2 notes.
2. **Parser topology changed.** Former Dogfood parser files are now the single statically-bound
   `CompilerServices/ColumnarParserKernels.nl`. C, F, and G all contend on that file. Old paths
   and import-component assumptions are invalid.
3. **One parse, one diagnostic authority.** The current syntax candidate calls `Lexer` and runs
   independent collectors, while the original design required diagnostics to share the columnar
   scanner/parser state. Before growing it, either integrate it with that state or record a new
   design with equivalent single-owner, clean-path allocation, recovery-parity, and performance
   proof. Two parser-like decision engines are not an acceptable end state.
4. **FormatSafe belongs to the syntax flip.** C must move its parse-error refusal gate to the N#
   syntax authority before deleting `ParseResult.Errors`. A silent AST reparse may remain only
   for the temporary AST/idempotence comparison and must disappear with the formatter re-host.
5. **Analyzer facade ownership is split at one explicit seam.** D exposes the stable N# API and
   retargets `MultiFileCompiler` plus every non-IDE product consumer. A temporary zero-policy
   facade may then serve only the exact G-owned IDE consumer recorded in this ledger. G retargets
   that final consumer and deletes the facade in the same commit. H verifies absence; it neither
   retargets the consumer nor deletes the facade.
6. **Use canonical semantic identity.** C/D must introduce source-qualified SymbolId/TypeId
   values; name plus line/column is insufficient. F call facts must contain caller node id and
   resolved declaration/function id, including overload/local/generic-instantiation identity.
   C# may flatten already-resolved facts; it may not reimplement resolution policy.
7. **One package-version policy owner.** CLI and Analyzer metadata loading must consume the same
   N# resolver/version-selection facts. The SemVer policy recently added to `Analyzer.cs` is
   deletion debt, not a second canonical implementation.
8. **IDE gates follow reachability, not track labels.** Any commit changing code reached by
   `DocumentManager`, the shared Analyzer, linter/formatter/code-intelligence, an LSP handler, or
   the extension is IDE-affecting even when parity is expected. It requires the VS Code-enabled
   gate, extension reload, computer-use verification, and screenshots after that commit.
9. **E ordering is a DAG.** Interface-pass work depends on the N# definition model; do not run
   the old E3.4 before E4.1. Do not take the old Route B that grows temporary C# Reflection.Emit
   whitelists. Member/binder and typeref-owner selection policy belongs in N#; C# only invokes
   reflected APIs or patches/replays already-selected metadata operations.
10. **H has no allowed deferred product suite.** TypeScript may own editor/UI adapter assertions,
    but canonical language/LSP semantics also require N# tests. A `query ast` schema change is a
    separate versioned contract with goldens and an approval boundary, not incidental cleanup in
    the front-end delete.
11. **A wave is not a commit.** Broad sub-arcs may contain many commits. Every actual commit unit
    must name its input contract, N# production owner, exact deleted/shrunk C# owner, focused
    evidence, and checkpoint. Avoid both one-helper churn and multi-thousand-line catch-all
    commits.
12. **Build.Tasks is in scope for decisions.** `LoadProjectConfig.cs` and
    `LoadProjectReferences.cs` may keep MSBuild `ITaskItem` materialization, but output/default,
    dependency-classification, ordering, and projection policy must move to N# plan objects. The
    final audit covers `.cs`, `.targets`, `.props`, TypeScript, shell, and WASM glue—not only C#.
13. **No new C# survives the amended closeout.** Every notebook direction requesting a new C#
    test, differential harness, replayer, seed, whitelist, callback, adapter, or feature branch is
    stale. Implement the prerequisite and successor in N#, run it through the product/native gate,
    then delete or reduce the old C# owner. Existing C# boundary files may not grow.

## Contention ledger (live)

- `CompilerServices/ColumnarParserKernels.nl`: C diagnostics, F inputs, and G formatter trivia.
  The A0 writer has released it; one writer at a time, with partitioning only when merges are
  guaranteed.
- `ColumnarIlEmitter.cs`: E owns it exclusively after `399008ea9`. Track A may no longer add
  feature branches.
- `MultiFileCompiler.cs`: C flip, F systems host, D consumer retarget, H playground/deletion.
- `Analyzer.cs`: D owns retirement; B may supply N# metadata/version APIs but does not edit the
  analyzer concurrently.
- `tests/Tests.csproj` and shared fixtures: append-only, never reorder; new C# product assertions
  must be entered in H's migration inventory.
- SDK repins and package/build-script changes: announce before changing shared installed state;
  gate from a clean `/tmp` worktree when the main checkout is active.

## Updating this ledger

After a stage commits, update its row with the commit and evidence, record the next dependency,
and remove obsolete blocker prose. Do not accumulate a narrative history: compact completed
stages to one evidence line. Delete this temporary ledger during the final documentation
closeout after the survivor inventory becomes the durable architecture record.

The durable inventory lives at `memory/architecture.md#non-nsharp-survivors`. The campaign must
also land a committed ownership-audit script and reviewed allowlist that cover product-adjacent
`.cs`, `.targets`, `.props`, TypeScript, shell, and WASM files; H8 runs that guard as final proof.

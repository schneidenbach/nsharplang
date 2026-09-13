# Active managed toolchain conversion

Authorized 2026-09-09, after completed compiler ownership and Compiler Core rename.
Astra plans, reviews and integrates. Luna Max subagents implement bounded complete areas using
the N# skill and current repository language docs/executable N# examples. Minimal faithful
conversion is the default; no redesign or new feature work is implied.

## Scope and completion

Convert remaining managed Compiler facade, Build.Tasks, CLI, LanguageServer, Playground and Runtime
production ownership to N#. Evaluate and convert the Wasm export host where supported; document any
strictly mechanical host boundary. SDK/Templates remain native packaging configuration; change their
integration only as required by these ports. VS Code extension migration is deferred at very low priority.
NativeAOT, a new metadata writer and unrelated branch initiatives remain separate.

Migrate canonical C# assertions with each owner, including setup/state, ordering, exact diagnostics,
outputs and failure/lifecycle behavior. Remove replaced assertions and unused helpers after N#
successors execute. No new C# behavior, tests, helpers, adapters, callbacks or fallbacks. Intentional
C# interoperability fixture inputs may remain where they prove cross-language behavior.

Move complete classes or connected methods with necessary helpers and state. Preserve public and
package contracts; don't treat changing project extensions as completion. Compile actual proposed
N# sources to prove prerequisites; implement required compiler fixes in N#. Root serializes shared
compiler prerequisites, SDK seeds/feed writes, ratchets and integration gates. Use dev.sh and targeted
native tests while implementing. Commit coherent green pieces; root reviews and runs fresh required
integration gates and IDE verification before push. Retire completed worktrees/branches after checking
active users, unique history and dirty files, preserving evidence and recoverable unfinished work.

## Current lanes

Base: 06186dc6d (includes bootstrap/CI work; preserve it).

| Area | Owner | Worktree / branch | Status |
|---|---|---|---|
| Complete Compiler service facade and assertions | Luna Max toolchain_facade | Integrated at 5691697ce; old lane retired | Four C# owners and remaining C# assertion removed; root combined build and 98 native tests pass; private package consumer passes; final gate pending |
| Complete LoadProjectConfig / LoadProjectReferences and assertions | Luna Max toolchain_build_tasks | Integrated; original lane retired | Owners and canonical SDK assertions integrated into candidate; 8,028 Core tests pass; 20 native SDK tests pass; final integration gate/push pending |
| CLI command owners and assertions | Luna Max toolchain_facade | CheckCommand integrated through a46c04d1d; FixCommand next | CheckCommand C# owner and 559-line C# test file removed; lane native contracts 123/123; array correction integrated through 6b3f4d669; root combined compiler canonicals pass 8,075/8,075 |
| LSP signature/services | Queued | Signature branch preserved | Refresh unique signature work without restarting |
| Playground compiler and interpreter | Luna Max toolchain_build_tasks | /private/tmp/nsharp-agent-wt/toolchain-playground; codex/toolchain-playground | Integrated through 5480fc33a; both C# owners deleted; lane 150 native assertions pass; root combined build/native verification pending |
| Runtime ABI and assertions | Luna Max toolchain_build_tasks | Starting codex/runtime-owner from 5480fc33a | Convert four remaining managed Runtime owners with CLR identity/behavior preserved; root owns seed publication |
| Wasm host | Queued | No new worktree yet | Prove export integration and retain only necessary mechanical boundary |

Assessment and actual probe evidence: /private/tmp/nsharp-other-projects-assessment-20260909/ASSESSMENT.md.
Unique held config/signature work remains preserved until integrated or safely archived.
The two clean query worktrees and branches were removed after confirming both tips are ancestors
of systems-language, have no active task users and contain only ignored build outputs. Cleanup
receipt: /private/tmp/toolchain-query-worktree-cleanup-20260909.json.
The completed SDK worktree and branch are also retired: its owner confirmed no active use,
the checkout was clean apart from ignored build outputs, and all three commits were patch-equivalent
to integration commits. Recoverable original history is in the verified bundle
/private/tmp/toolchain-build-tasks-retired-20260909.bundle.
The completed facade worktree/branch is retired after confirming a clean checkout and all six
lane commits patch-equivalent to integrated commits. Its agent moved to the separate check-command
worktree. Verified recovery bundle: /private/tmp/toolchain-facade-retired-20260910.bundle.
A finished lane is not completion of this whole objective.

## Current integration findings

- Facade keeps its public Compiler assembly/API. Actual imported Core static-call probe passes;
  the remaining library interop work is ordinary property/member handling, not a Core call allowlist.
- Proven facade prerequisites: oblivious generic argument compatibility, nullable enum parameter/
  value/constructor binding. Root verified these with all 8,021 Core canonical tests passing (0 failed/skipped) using an
  isolated SDK candidate. Receipt: /private/tmp/toolchain-facade-prerequisite-receipt.json.
  This is prerequisite evidence; no seed publication or complete facade acceptance is claimed.
- Ordinary external member binding is integrated with exact public getter/field selection and
  builder-bound receiver rejection. Combined compiler assertions pass 8,039/8,039 after the
  SortedDictionary.Keys contract update; nominal Dictionary.KeyCollection rejections remain.
  Receipt: /private/tmp/toolchain-integrated-member-receipt-r3.json. Facade project/package routing
  remains incomplete, so this does not mark the whole facade area accepted.
- MSBuild owner commit also preserves exact OutputAttribute metadata through the N# parser and
  emitter. Full dictionary metadata is retained by the original TaskItem constructor shape.
  The Build.Tasks project now contains no C# source; its remaining empty assembly and MSBuild
  project are mechanical dependency-copy/package boundaries. SDK UsingTask resolves both owners
  directly from Compiler.Core.
- Playground's literal-field and ordinary value-receiver prerequisites pass all 8,048 N# Core
  canonical tests (zero failed/skipped) at c914a56fe. Evidence:
  /private/tmp/toolchain-integrated-const-value-canonicals-r8.log. The prior four failures/crash
  were traced to invalid IL for field writes through out-reference parameters; initializing
  local objects before assigning the out parameters preserves the intended source behavior.
  Underlying emitter defect evidence remains /private/tmp/core-r7.il, with its correction
  investigation assigned alongside the proven generic safe-cast prerequisite. No SDK seed is
  published from this candidate; complete Playground ownership remains in progress.
  Const completion/diagnostic changes require the IDE-enabled integration gate and visual
  verification; extension migration itself remains deferred.
- Closed generic safe casts are integrated through the canonical scoped type resolver, with
  reference-target checks and no ordinary-resolution fallback. All 8,051 Core assertions pass
  at 0f9e88185: /private/tmp/toolchain-integrated-generic-cast-canonicals-r1.log.
  A subsequent test-only revision makes rejection fixtures reach the cast expression rather
  than fail in return signatures; all three focused canonical cases pass at ffec3c5e0:
  /private/tmp/toolchain-integrated-generic-cast-body-tests-r1.log.
- Facade package identity/readme metadata now projects through N# configuration, restore and
  MSBuild task owners. All 8,055 Core assertions pass at 249563ee1 after preserving the original
  template bytes: /private/tmp/toolchain-integrated-package-canonicals-r2.log. Private SDK boundary
  tests pass 20/20: /private/tmp/toolchain-facade-sdk-native-r1.log. Those native checks used
  explicitly substituted private fixture binaries, so final clean production/package verification
  remains required.
- Closed generic catalog admission now validates the definition and arguments in the selected
  reflection universe, preserving exact identities instead of requiring a constructed-name lookup
  through the defining assembly. All 8,057 Core assertions pass at 8b968d92a:
  /private/tmp/toolchain-integrated-catalog-canonicals-r1.log. This resolves the facade's generic
  return-type blocker.
- Ordinary external ref/out calls now use the semantic call planner and lexical managed addresses;
  no loaded-assembly name scan or per-kernel adapter was added. Runtime tests cover mutation,
  nested argument evaluation, exact modifier matching, out initialization and uninitialized-ref
  rejection. All 8,068 Core assertions pass at ce44d49b8:
  /private/tmp/toolchain-integrated-static-byref-canonicals-r1.log. The facade can call the existing
  completion-prefix kernel directly; final owner/package integration remains in progress.
- The complete facade is integrated at 5691697ce with portable Core project references, SDK-supplied
  Runtime dependency, original Compiler.dll/NSharpLang.Compiler identities and no-PDB package routing.
  Lane native suites pass 79 query + 5 reference + 13 completion + 1 query-completion tests; the
  private package consumer builds/runs. The source API retains method sets, arities and defaults,
  but parameters previously named `file` are `fileName`: `file` is an N# keyword and the current
  language has no escaped-identifier syntax. Positional/binary callers are unchanged; named-argument
  source callers require that spelling change. This source-compatibility limitation is explicit.
  Root combined CLI build passes with zero warnings/errors, and all four native suites pass again
  against the real integrated outputs: /private/tmp/toolchain-integrated-facade-build-r1.log and
  /private/tmp/toolchain-integrated-facade-{query,reference,completion,query-completions}-r1.log.
  The next lane is complete CheckCommand ownership (Execute, IL verification and errors), including
  canonical CLI contracts; accepted query migrations remain intact.
- Playground's shared declaration-name helper is integrated at 006c4cc36, with all 20 focused
  Core canonical tests passing: /private/tmp/toolchain-integrated-playground-helper-canonicals-r1.log.
  Corrected private owner probes pass 34 tooling + 116 diagnostic-span tests; final project routing
  and C# owner deletion remain in progress.
- All five IlSdkToolchainTests.cs cases now have N# successors and the C# file is removed in the
  integration candidate. Review retained XML UnitTestResult/outcome semantics and removed new
  assertions that merely mirrored private field names. All 20 native SDK tests pass against a private package (22.7s). Receipt:
  /private/tmp/toolchain-integrated-sdk-receipt-r1.json. Final fresh integration gate remains pending.
- Concurrent release task owns packaging/bootstrap delivery fixes and its clean-snapshot gates.
  All accepted release fixes through dc7efda2 are integrated into this candidate. GitHub run
  34424070745 and its seven-asset unofficial prerelease passed verification; the remote hold is
  lifted. This candidate still requires its own fresh integration gate before push. Root serializes
  SDK seed/feed writes and retires lane worktrees only after their changes are accepted.

- CheckCommand is integrated through a46c04d1d. Execute, IL verification, cleanup and error output
  now reside in N#; all 559 lines of CheckCommandTests.cs are replaced by native process assertions.
  Review restored exact JSON trailing bytes and diagnostic-write/elapsed-evaluation order, and
  removed global temporary-directory count assertions that race concurrent processes. Lane native
  contracts pass 123/123; root default dev.sh build rejects GetArgumentSummary and FromCompilerError with NL402.
  Evidence: /private/tmp/toolchain-integrated-check-build-r1.log. The owner must resolve that
  integration gap before gate acceptance. No shared SDK seed or push yet.

- Runtime assembly pairing is integrated at 4244403ac. Runtime handles match selected metadata
  by exact assembly identity and MVID; known reference-assembly layouts retain their paired
  implementation behavior, and identical modules retain compiler-context preference across paths.
  All 8,070 Core canonical assertions pass (zero failed/skipped):
  /private/tmp/toolchain-integrated-runtime-pair-canonicals-r1.log.
- Playground compiler/interpreter ownership is integrated through 5480fc33a. Both C# files
  (1,505 lines) are deleted. Lane tests execute 34 tooling and 116 diagnostic assertions successfully
  against matching project outputs; root clean combined verification remains required.
  Receipts: /private/tmp/playground-native-tooling-artifact-r2.log and
  /private/tmp/playground-native-diagnostic-artifact-r2.log.

- Retired the clean CheckCommand worktree and codex/check-command-owner branch after confirming
  all five commits are patch-equivalent in integration and the owner moved to the FixCommand
  worktree. Verified history bundle: /private/tmp/check-command-retired-20260910.bundle.
  The in-flight default-validation correction remains preserved in codex/fix-command-owner.

- Forced self-rebuild with the new runtime-pair SDK candidate fails on EmitIlAssembly.sourcesValue
  (ITaskItem[]), independently reproduced without SIMD edits. Earlier 8,070 canonical and production
  evidence used the preceding facade seed; it does not prove self-hosting by the new candidate.
  Log: /private/tmp/toolchain-integrated-runtime-pair-selfbuild-r2.log. Publication is blocked
  while the runtime-pair owner corrects reference/runtime companion handling. SIMD edits are preserved.

- CheckCommand imported-array compatibility correction is integrated through 6b3f4d669.
  It unwraps only oblivious array annotations, keeps nullable element mismatches distinct, and
  restricts its additional reflected-call path to SZ arrays while preserving successful existing
  CLR matches. Typed null sourceTexts preserves the command failure/output behavior.
  Lane canonical suite passes 8,074 tests; root combined suite passes 8,075 with zero failures
  or skips: /private/tmp/toolchain-integrated-check-array-canonicals-r1.log.
  FixCommand complete ownership and C# assertion migration has resumed in its existing worktree.

- The partial runtime-pair correction clears ITaskItem[] but then fails ZipFile.ExtractToDirectory.
  A forced rebuild of the same source with the preceding facade seed succeeds, confirming this
  second failure belongs to the resolver regression. It is not a new SIMD or ZipFile feature gap.
  The candidate remains unpublished while exact dependency selection is corrected.

## Recovery after temporary worktrees disappeared

The former /private/tmp worktree directories, private candidates and logs are no longer present.
Committed branch tips survive. Git administrative metadata was archived at
/Users/spencer/repos/nsharp-worktree-recovery-gy0mvuhz before pruning missing registrations;
all eight saved indexes matched HEAD (no staged changes recoverable). Uncommitted resolver/SIMD
files that existed only in those directories must be reconstructed from recorded findings.

Active persistent worktrees are now /Users/spencer/repos/nsharp-worktrees/integration,
/Users/spencer/repos/nsharp-worktrees/fix-command and
/Users/spencer/repos/nsharp-worktrees/runtime-owner. FixCommand commit 33522d9c6 survived and
is under review; do not restart that port. Luna Max agents are reconstructing the self-hosting
resolver correction and verifying FixCommand assertions. Private build evidence now goes under
/Users/spencer/repos/nsharp-worktrees/evidence. Historical test counts above remain historical
evidence, not fresh recovery/build verification. Shared main checkout and SDK cache remain untouched.

Recovery verification: the recovered private stage-0 SDK rebuilt current compiler-core successfully
(0 warnings/errors; evidence/recovered-core-build-r3.log), and default dev.sh --build-only plus
all 123 native CLI contracts pass (evidence/recovered-cli-build-r1.log and
evidence/recovered-cli-contracts-r1.log). These are persistent paths beneath the evidence directory
above. The current candidate still fails normal Playground project build while rebuilding Core
on ITaskItem[]; its self-hosting correction remains mandatory before publication.

A source audit found 12 remaining CheckCommand assertion methods in tests/CliCommandTests.cs and
Check/Fix coverage in tests/CompilationBackendTests.cs. Their canonical N# migration is now a third
Luna Max lane at /Users/spencer/repos/nsharp-worktrees/check-assertions
(codex/check-remaining-assertions). Dedicated-test-file deletion alone is not owner completion.

FixCommand is now integrated through 3cc75672b: the 191-line C# owner, 838-line dedicated
C# test file and three shared Fix assertions are replaced by N# ownership/assertions. Review
preserved original edit tie ordering, per-file atomic writes and exact JSON/output bytes.
Root dev.sh build passes with 0 warnings/errors; all 130 native CLI contracts pass against the
integrated output. Receipts: evidence/integrated-fix-core-build-r1.log,
evidence/integrated-fix-cli-build-r1.log and evidence/integrated-fix-cli-contracts-r1.log.
The clean Fix worktree/branch is retired; verified persistent history bundle:
/Users/spencer/repos/nsharp-worktrees/evidence/fix-command-completed.bundle.
The remaining shared Check/backend assertions remain assigned to the separate lane.

## CLI project boundary correction

User clarified that CLI commands must not live in the Compiler project merely because it already
builds N#. Move CheckCommand/FixCommand and their command-specific helper/state/test groups into
a dedicated native NSharpLang.Cli.Core project. The existing CLI executable references it; the
dependency direction is CLI host -> CLI.Core -> Compiler -> Compiler.Core. Compiler, Playground
and SDK packages must not acquire a CLI command dependency. Reusable compiler-service FixApplicator
remains in Compiler. This is one coherent CLI library, not a project per command.

The bounded relocation is assigned to the Luna agent at
/Users/spencer/repos/nsharp-worktrees/cli-native-owner (codex/cli-native-owner). Preserve exact
command semantics and canonical tests, remove reverse test dependencies/host-assembly assumptions,
and verify the published CLI closure. Shared CLI-only code still in Compiler.Core remains explicit
placement debt to move with its complete caller group; do not introduce a reverse dependency.

## Compiler capability gaps for the Runtime conversion (2026-09-10)

Proven with the tip CLI (`nlc 0.1.0+dc7efda2f`) before any edit, then implemented as one integration
branch (`gap/integration`, 20 stream merges plus 3 root fixes) by Opus streams in persistent worktrees
under `/Users/spencer/repos/nsharp-worktrees/gap-*`; root planned, reviewed, merged, gated and pushed.
No Runtime `.cs` file was edited; the four acceptance sources are translated as executable native tests
that compare side by side with the real `NSharpLang.Runtime` types.

| Gap | Baseline | Now | Native evidence |
|---|---|---|---|
| Readonly structs | NL101 at `readonly struct` | all modifier orders, generic, `readonly ref/record struct`; NL326 mutable-instance-field rule; NL311 on non-structs; `IsReadOnlyAttribute` + `initonly` emission | `tests/native/readonly-structs` |
| Static members on generic types | NL323 at the declaration; `Box<int>.Create` parsed as a comparison | constructed generic receivers (`Name<T>.Member`, new AST node); static fields/properties/methods/operators/conversions on generic types with per-instantiation storage; generic methods on user types; `Result<int, string>.Ok(42)` | `generic-type-receivers`, `generic-static-members`, `user-generic-methods`, `runtime-acceptance` |
| Type identity by arity | NL306 for `Subscription` + `Subscription<T>`; generic user types emitted WITHOUT the `` `N `` CLR suffix | (name, arity) identity in every table; `` Name`N `` metadata names; qualified and unqualified references are one identity; abstract/virtual/override on source classes; faithful `NSharpEventSubscription` with zero deviations | `type-arity`, `class-inheritance`, `generic-member-types` |
| Constructed external generic members and constructors | `Vector<int>.Count` parse failure; `new Vector<int>(a, i)`, operators, indexer and `Vector.Sum` declined at emit | ordinary resolution for constructors, operators, indexers, generic static and instance methods (explicit and inferred type arguments), static members of constructed types; complete `SimdReductions` translation executing with parity against the C# helper | `external-generic-construction`, `external-generic-methods`, `simd-reductions`, `tuple-names` |

Adjacent gaps closed because the acceptance sources required them: external generics over the declaring
type's own parameters and over complete source types (`IEquatable<Self>` base lists with real dispatch,
`EqualityComparer<T>.Default`); `?.`, `default`, `base.Member` and `is` over any type in the columnar
backend; `[MethodImpl]` implementation flags (were silently dropped; NL930-NL932); `TupleElementNamesAttribute`
in both directions; namespace-qualified names in expression position; an explicit import now outranks
project-wide auto-discovery, and two imports supplying one name is NL209 (auto-discovery itself is kept:
`examples/12-multi-file-projects/AutoDiscovery` documents it); by-ref arguments in the semantic call planner;
user-defined conversions declared by external generic types; NL327 for `this`/`base` without a receiver.
Measured language limits that the translations spell around: `const` is not a field modifier (the
`MethodImplOptions` combination is written at each member), N# has no explicit interface implementation
(`IEnumerable<T>` on a source class does not load), and a generic method called directly on a call
result needs a local. Remaining documented limits are in `website/docs/types.md` "Current limits".

Evidence at the integrated tip: compiler-service estate 8,339/8,339; 66 native projects, every one
executing with zero failures; C# unit suite 399/399; format gate clean; ilverify clean over the new
assemblies. Three regressions were caught only by full sweeps or the product gate (a nullable-interface
typed local, `TryGetValue(key, out x)` on a static-field receiver, `base.Value` accepted in a constructor
initializer) plus a double-`box` IL defect from a merge collision — streams must run the FULL native
sweep, and a native project whose test build fails reports total 0, which a sweep must flag.
The A2 stream's three slices (abstract/virtual/override, generic-over-type-parameter member types,
exception property reads including the `ArgumentException::get_Message` override contract) are one
squashed commit whose message names only the first; this paragraph is the record for the other two.


## Converter-driven census slices (2026-09-12)

The conversion is now driven by a deterministic C#→N# transducer kept OUTSIDE the product repo
(`/Users/spencer/repos/nsharp-cs2nl`, Roslyn-based; `convert` writes a 1:1 N# translation with
`// CONVERT:` stubs where no N# spelling exists yet, `census` tallies those stubs per construct across
LanguageServer, Cli, Wasm and the C# tests; `CENSUS.md` there is the ranked gap list). The census
ranks compiler gaps by how much converted code they block; each slice fixes ONE rule in the N#
compiler with native contracts, and the converted projects are re-run through `nlc check` to
measure. Slices landed with this record (`census/merge` onto systems-language `a0bd6fd1e`):

| Slice | What blocked the conversion | Rule now | Evidence |
|---|---|---|---|
| `nlc check` non-termination | a 27-link `.WithHandler<T>()` chain in the converted LanguageServer `Program.nl`: every receiver read re-walked the chain, 2^N | a call walks its member-access receiver ONCE; later reads re-run only the expression tail at their own position (step kind 16); one report per fault in `check` and `build` | `AnalyzerCallAnalysis.tests.nl` receiver-walk counts; `analyzer-semantic-model` lambda scope census 15→7 / 7→5 |
| try/finally return | `return` inside `try` with `finally` read as falling through | C# rule: a protected region's return completes the function; regions nest | `tests/native/census-flow-rules/TryFinallyReturn` |
| break/continue narrowing | `if x == null { continue }` did not narrow `x` afterwards | jumps narrow the way `return` does | `census-flow-rules/JumpNarrowing` |
| external signature identity | `Nullable<T>` / array annotations and omitted defaulted arguments on cross-assembly members failed to bind | one reflected-type identity rule for both; constructor defaults filled like methods | `census-flow-rules/ExternalSignatures` |
| reference stores and casts | `object[]` element stores and array-literal explicit casts declined at emit | the conversion the analyzer proved is emitted; downcast arms stay ahead of the upcast funnel | `census-flow-rules/ReferenceStoresAndCasts` |

Corpus pin 94. Remaining ranked gaps (from `CENSUS.md`): non-literal field initializers, generators
(`yield`), source-declared attributes, struct-enumerator `foreach`, lambda result inference for
method type parameters, a deep-nesting parser crash, `nlc build` dropping the NL103 decline site,
NL010 false positives, generic methods on a call result, `IEnumerable<T>` on source classes. The
order of work is: close gaps until the mechanical conversion of LanguageServer, Cli and Wasm checks
clean, land those conversions 1:1, then rewrite them into idiomatic N# with the C# owner deleted.

## Census wave 3 (2026-09-13)

Nine streams from the refreshed census, each an Opus agent in `/Users/spencer/repos/nsharp-worktrees/census-<stream>`
from a brief in `census-briefs/`, merged onto `census/merge` in landing order with the corpus pin and the
diagnostic-catalog counts reconciled at each merge (every stream bumps both; the merge takes the sum):

| Stream | Rule now | Evidence |
|---|---|---|
| CONV | array covariance (`S[]`→`T[]` for reference elements), target-typed array literals in every position, `null` to a reflected nullable generic-interface parameter (`IsReferenceType` asks the definition) | `census-conversions`, `census-flow-rules` |
| FLOW2 | narrowing through parentheses, negation and the ternary; `Nullable<T>` members bind after narrowing (NL907 is a warning); `while true` reachability; `return` in a constructor; NL304 only for non-nullable reference fields; `x?.M == null` narrows | `census-flow-rules` (NarrowingLattice, ReachabilityAndConstructors) |
| TOOL | `nlc check` reads `*.tests.nl`; `nlc build` prints the decline site; NL111 bounds expression nesting at 512 (no stack overflow); NL010 counts every type position | `cli-command-contracts`, `error-docs-contract` |
| ENUM | `for..in` follows the C# foreach pattern (struct enumerators unboxed, disposal by the four C# answers, `ReadOnlySpan<T>` as an index loop); the emitter's collection name table is gone | `census-pattern-foreach` |
| PARSE2 | a whole TYPE in an explicit type-argument list (`Task.FromResult<List<int>?>(null)`); tuple element names per element in literals and types; a tuple-annotated bare local | `census-parse-shapes` |
| LAMBDA | one method-type-inference engine by position for extensions, statics, instance and user generic methods; method groups; NL413; the per-member Enumerable emit table deleted; reflection over referenced members is load-tolerant (`AnalyzerReflectionMemberProbe`) | `census-lambda-inference` |
| INIT | field initializers are expressions: a real `.cctor`, instance initializers before the base call, struct initializers in declared constructors (NL328/NL329), `beforefieldinit` | `census-field-initializers` |
| ATTR | attributes a program declares for itself: general ECMA-335 blob writer, `AttributeUsage` honored (NL933/NL934), attributes on properties and constructors | `census-source-attributes` |
| EXT | one extension-call path from receiver to IL: source-class element sequences, arrays, explicit type arguments on extension calls (the `Cast`/`OfType` table deleted), lambdas in every argument position through the columnar parser and the construction planner, type-parameter receivers | `census-extension-calls` |
| ITER | iterator bodies use the ordinary expression planner (the parallel mini-planner deleted): calls, literals, `new`, `for..in` over any sequence, target-typed `yield`; one BCL exception resolution path; external record initializers | `census-iterators` |
| LOCALFN | local functions bound by the block (forward calls, mutual recursion, definite assignment at the call); a substituted generic parameter takes the type argument's nullability (`Lazy<T>.Value`, `First` vs `FirstOrDefault`); `assert cond` narrows; postcondition attributes belong to the postcondition owner alone | `census-local-functions`, `census-flow-rules` |
| FLOW3 | `out` arguments take any nullability; `[NotNull]`/`[MaybeNull]`/`[NotNullWhen]`/`[MaybeNullWhen]`/`[NotNullIfNotNull]` read off reflected and source members; a `?.` chain's continuation lifts | `census-flow-rules` |
| CONV2 | shift operands typed by the operator; integer constants adopt a neighbour's type; user-defined implicit conversions on arguments (`op_Implicit`); array literals scored element-wise against overload sets | `census-conversions` |
| TUPLE2 | `System.ValueTuple\`N` is the tuple type it spells; element names survive `Nullable<T>.Value`, indexers, dictionary values, chains and foreach variables at emit; tuple-typed fields/properties; `(a, b) := e` / `(a, b) = e` and `Deconstruct(out …)` | `census-parse-shapes` |
| ENUM2 | `for x: T in e` — an annotated loop variable with the C# explicit element conversion (NL330), node kind 76 | `census-pattern-foreach` |

| LAMBDA2 | a lambda or method group converts to ANY delegate type (signature read off `Invoke`); method groups against overload sets; external generics' delegate positions and member reads through the definition; constrained type-parameter receivers at both lookup sites; external property assignment by ordinary resolution | `census-lambda-inference` |
| LOCALFN2 | local functions capture like lambdas — one display-class model (`ColumnarLocalFunctionClosurePlanner`), `this`-only capture on the declaring type, NL331 for a captured by-ref parameter; type members may declare local functions | `census-local-functions` |
| VIS | a camelCase top-level `func` is NAMESPACE-private (visible from every file of its namespace), in discovery, completion and `nlc query` | `census-visibility` |
| FLOW4 | `[DoesNotReturn]`/`[DoesNotReturnIf]` as one reachability fact both the analyzer and the planner ask; a narrowed `T?` (and a lifted tuple) is read as its `T` at emit; loop bodies that never fall through emit | `census-flow-rules` |
| EMIT2 | a struct assigns its own field from its own method (addressable receivers); enum instance members resolve against `System.Enum`; a conditional over an interpolated string and a `string` is a `string`; `T[]` → `T?[]` admitted; the "declining shape" sentinel moved to a bare static field as a call receiver (three N# fixtures and the three C# fixtures in `tests/CompilationBackendTests.cs`) | `census-emit-shapes` |
| ATTR2 | attributes on FIELDS (a `FieldDeclTokens` column on the struct scan), optional attribute-constructor parameters filled from declared defaults, per-element constant conversion in attribute arrays, chaining to an EXTERNAL base constructor with arguments, NL935 for attribute positions N# has none of | `census-source-attributes`, `class-inheritance` |
| ITER2 | a generator suspends inside a `try` whose handler is a `finally`; writes through a member, an indexer and an annotated loop variable inside the machine; `await` of anything; a lambda built from the machine the generator is already running on | `census-emit-shapes`, `census-local-functions` |
| EMIT3 | free functions keyed by NAMESPACE (two same-named functions in different namespaces no longer share one body); the holder type is `Program` unless the namespace declares one, then `<Program>`; free-function visibility follows the analyzer's rule | `census-free-function-identity` |
| INHERIT | a source type deriving from an external base sees every inherited member: reads and calls with and without a receiver, static members through the derived type, completion offers what a receiver inherits; the surrogate's base chain is written down | `class-inheritance` |
| LAMBDA3 | a method group a REFERENCED assembly declares converts to a delegate; a lambda's result is read through its CLR shape; an output is inferred from an overloaded group; a type parameter met by `X` and `X?` fixes to the lifted bound; a `ref`/`out` argument is an EXACT inference | `census-lambda-inference` |
| TUPLE3 | a tuple's element names survive a local, a source member and an inferred return | `tuple-names` |
| TESTREFS | one owner for the test-framework reference set (`TestFrameworkReferenceSet`: restore row, compile assemblies with the package that ships each, runtime assemblies, the emit host's probe list) — a metapackage such as `xunit` is never loaded by name; a project with `*.tests.nl` plans the rows without declaring the dependency; attributes on `test` blocks, a `[Fact]`-derived attribute decides the run (`Skip`); a source attribute declared in another file binds; writes to inherited external members | `census-testrefs`, `cli-command-contracts`, `language-server-diagnostics` |
| FLOW5 | `.Value`/`HasValue` answer only for nullable VALUE types; `x?.M(...)` binds its callee (overloads, arity, postconditions); lifted `==`/`!=` over `T?` in analysis and IL; `x?.TryGetValue(k, out v) == true` narrows `v`; postconditions bind through an oblivious or nullable-annotated receiver; a `null` ternary arm emits | `census-flow-rules`, `analyzer-clean-source` |
| EMIT4 | a bare static member of the enclosing type is a call receiver; `this` reaches object's own members on a source class; `GetType()` on a typed source receiver; `[DoesNotReturn]` tails in value functions and `Debug.Assert` by ordinary static resolution; `T?[]` local annotations and typed foreach; a `?`-lifted SOURCE struct at every declared position; tuple literals (named or not) into tuple-typed locals and as lambda results at generic positions; the "declining shape" sentinel is now `await foreach` inside a generator (four N# fixtures + the three C# sites) | `census-emit-shapes` |
| LIFT | every operator family lifts over a nullable value type with C# §12.4.8 semantics: arithmetic/bitwise/shift → `R?` absent-in-absent-out, comparison → plain `bool` (false when absent, narrows nothing), unary, compound and postfix on `T?`, `bool?` three-valued `&`/`|`, user-defined `op_*` on `decimal?`/`TimeSpan?`; one lowering per shape, no operator tables; `null + 1` stays refused | `census-lifted-operators` (IL-verified in the gate) |
| EVENTS | `on`/`off` reach the columnar pipeline (expression kind 79 / statement kind 80): any receiver a call accepts (static type, local, parameter, field, `this.`, property chain, indexer), the handler a lambda, a delegate value or a method group, the handle typed once for `on` and `off`, `add_`/`remove_` read off the `EventInfo` (no event tables); method groups bind against reference-assembly delegates; hover/definition on both keywords | `census-events` (IL-verified in the gate) |
| AMBIG | NL209 wherever two imports supply one simple name, external types included, in every position (annotation, `new`, type argument, `typeof`, `is`/`as`, static receiver, attribute); a metadata miss is memoized so the probe is affordable; a mismatch pair that renders the same is qualified by one owner (`TypeMismatchDisplay`); a delegate-constructor parameter type is resolved in its DECLARING file's scope (no NL209 at a line that never spells the name); the emitter's hardcoded `Range`/`Index`/`DateTime` table is the last resort, not the first; an imported CLR generic outranks an unimported source type of the same spelling; the `System` row of the NL010 import table completed by sibling (66 → 112) | `census-imports` |
| ACCESS | one accessibility relation (`MemberAccessibility.nl`) for source and reflected members: `protected`/`private`/`internal`/`protected internal`/`private protected` enforced on source members with the C# receiver rule (NL308 by one owner), every written word reaches CLR metadata (fields included; `private protected` → famandassem), `public`/`internal`/`private` words on free functions decide `Public|Static` vs `Assembly|Static`; `this.M()`/`base.M()` reach an external base's protected methods (`base.` non-virtual); completion filters by accessibility | `census-accessibility` |
| USING | the `using` statement with C# semantics (statement kind 77, `await using` 78): `using x := e { }`, `using x: T = e { }`, `using e { }`, the DECLARATION form released at the end of the enclosing block in reverse order, `await using` via `IAsyncDisposable`; a real `try`/`finally` lowering, struct resources by constrained call, null resources skipped, NL333 for a non-disposable resource, NL309 for rebinding the resource; termination analysis, generators, lambdas, local functions, formatter, hover/completion inside the block; `let x: T := e` fixed on the way | `census-using-statement` |
| OVERLOAD | C# §12.6.4.3 better-function-member for SOURCE and REFLECTED overload sets by one owner (`AnalyzerOverloadSpecificity`, a partial order over a verdict matrix — order-independent): the more specific type wins (`IEnumerable<T>` over `IEnumerable`, `T` over `object`), non-generic over generic only at identical parameters, `ref`/`out` positions scored through their by-ref shell, the extension receiver at position 0, lambda-return and method-group conversion scores; an unbreakable tie is NL414 (never a silent pick; withheld when an argument is `unknown`); the columnar source resolver applies the same rule (four emitter tie-contracts moved from Rejected to the specific overload) | `census-overload-resolution` |
| TOOL2 | lint fidelity: an aliased import is used when its alias is written AND when the namespace's own names are (both questions), an alias-qualified type reads as the one type it names, a declaration is not in scope inside its own initializer (no NL020 for a lambda parameter there), the converted language server's four lint reports pinned as executing editor contracts; a static receiver (`Thread.Sleep`) counts as an import use | `qualified-names`, `language-server-diagnostics` |
| ASYNC | `async` lambdas (expression kind 78) in every lambda position against `Task`/`Task<T>`/`ValueTask`/`ValueTask<T>` and any task-like delegate, capturing like ordinary closures, exceptions landing on the task; `async` local functions; `return <lambda>` (sync too); the `Task.Run` row picks `Action` or `Func<Task>` by the argument's shape; a bare `throw` re-throws (IL `rethrow`, kind 48 with no children) inside async and generator bodies, NL336 outside a handler; NL334 for an `async` lambda with no task-like target (`async void` refused by design), NL335 names the missing `async` keyword | `census-async-lambdas` |
| EVENTS2 | events DECLARED by N# types: `event Name: DelegateType` on classes, structs and records (static too) — a `[CompilerGenerated]` backing field, `add_`/`remove_` with the C# `Interlocked.CompareExchange` loop, `EventInfo` metadata; raised inside the declaring type (`Name?.Invoke(...)`), reached from outside only through `on`/`off` (NL337), NL338 for a non-delegate type, NL311 for `virtual`/`abstract`/`override`, NL323 for an interface event; a bare `this` as an expression (kind 82); `nlc query` and completion know the `event` kind | `census-source-events` (IL-verified in the gate) |

Still running at this record: TOOL2 (import/shadowing fidelity). Open items from every report are collected in
`/Users/spencer/repos/nsharp-worktrees/census-briefs/FOLLOWUPS.md` (among them: overload specificity for
`Assert.Single`, NL209 for a simple name two imports supply, protected external members, the `using` statement,
async lambdas, `await foreach` inside a generator).

Converter (`nsharp-cs2nl`) mappings added in the same wave: iterators as `func*`, hoisted local functions, class
primary constructors, negated `HasValue`, discard assignments, lambda-parameter renames, typed-foreach casts,
`KeyValuePair`/`Deconstruct` deconstruction, primary-constructor field initializers in the constructor, nullable
`var` locals, `is` over a constant as equality. Census at `669674b9e`: runtime 0, cli 46, tests 91,
languageserver 123 (from 1 / 145 / 153 / did-not-finish at `755e53a14`). Wave 4 briefs (FLOW3, CONV2, TUPLE2,
LAMBDA2, TOOL2, ENUM2) are in `census-briefs/`.

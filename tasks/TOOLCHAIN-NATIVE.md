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
| CLI command owners and assertions | Luna Max toolchain_facade | CheckCommand integrated through a46c04d1d; FixCommand next | CheckCommand C# owner and 559-line C# test file removed; lane native contracts 123/123; array correction integrated through 6b3f4d669; combined compiler verification running |
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
  Lane canonical suite passes 8,074 tests; root combined verification is running.
  FixCommand complete ownership and C# assertion migration has resumed in its existing worktree.

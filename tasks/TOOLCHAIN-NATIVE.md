# Active managed toolchain conversion

Authorized 2026-09-09, after completed compiler ownership and Compiler Core rename.
Astra plans, reviews and integrates. Luna Max subagents implement bounded complete areas using
the N# skill and current repository language docs/executable N# examples. Minimal faithful
conversion is the default; no redesign or new feature work is implied.

## Scope and completion

Convert remaining managed Compiler facade, Build.Tasks, CLI, LanguageServer, Playground and Runtime
production ownership to N#. Evaluate and convert the Wasm export host where supported; document any
strictly mechanical host boundary. SDK/Templates remain native packaging configuration; change their
integration only as required by these ports. Visual Studio extension is deferred at very low priority.
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
| Complete Compiler service facade and assertions | Luna Max toolchain_facade | /private/tmp/nsharp-agent-wt/toolchain-facade; codex/toolchain-facade | Implementing |
| Complete LoadProjectConfig / LoadProjectReferences and assertions | Luna Max toolchain_build_tasks | Integrated; original lane retired | Owners and canonical SDK assertions integrated into candidate; 8,028 Core tests pass; 20 native SDK tests pass; final integration gate/push pending |
| CLI query/commands and LSP signature/services | Next wave | Signature branch preserved; integrated query branches retired | Continue from integration HEAD; refresh unique signature work without restarting |
| Playground interpreter | Luna Max next after SDK assertions | /private/tmp/nsharp-agent-wt/toolchain-playground; codex/toolchain-playground | Implementing from 2f73fdf12; complete connected owner and tests |
| Runtime ABI and bootstrap | Queued | No new worktree yet | Preserve CLR identity/behavior; verify actual proposed types |
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
- All five IlSdkToolchainTests.cs cases now have N# successors and the C# file is removed in the
  integration candidate. Review retained XML UnitTestResult/outcome semantics and removed new
  assertions that merely mirrored private field names. All 20 native SDK tests pass against a private package (22.7s). Receipt:
  /private/tmp/toolchain-integrated-sdk-receipt-r1.json. Final fresh integration gate remains pending.
- Concurrent release task owns packaging/bootstrap delivery fixes and its clean-snapshot gates.
  All accepted release fixes through dc7efda2 are integrated into this candidate. GitHub run
  34424070745 and its seven-asset unofficial prerelease passed verification; the remote hold is
  lifted. This candidate still requires its own fresh integration gate before push. Root serializes
  SDK seed/feed writes and retires lane worktrees only after their changes are accepted.

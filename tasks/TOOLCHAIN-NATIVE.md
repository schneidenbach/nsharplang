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
| Complete LoadProjectConfig / LoadProjectReferences and assertions | Luna Max toolchain_build_tasks | /private/tmp/nsharp-agent-wt/toolchain-build-tasks; codex/toolchain-build-tasks | Implementing; reuse held config work |
| CLI query/commands and LSP signature/services | Next wave | Existing held branches preserved | Refresh and integrate accepted work; don't restart |
| Playground interpreter | Queued | No new worktree yet | Complete connected owner and tests |
| Runtime ABI and bootstrap | Queued | No new worktree yet | Preserve CLR identity/behavior; verify actual proposed types |
| Wasm host | Queued | No new worktree yet | Prove export integration and retain only necessary mechanical boundary |

Assessment and actual probe evidence: /private/tmp/nsharp-other-projects-assessment-20260909/ASSESSMENT.md.
Existing held config/query/signature work remains preserved until integrated or safely archived.
A finished lane is not completion of this whole objective.

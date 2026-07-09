GOAL: eliminate non-N# ownership of compiler and compiler-tooling behavior.

Scope:
- Lexer and preprocessing; parser and syntax diagnostics; binding, analysis, semantic models,
  metadata policy, and diagnostics; IL lowering and code generation; project configuration and
  reference-resolution policy; formatter, linter, code intelligence, query, and LSP decisions;
  CLI, native-test-runner, and playground compiler behavior; and the canonical tests for those
  product behaviors.
- `NSharpLang.Runtime` implementation, editor UI wiring, MSBuild protocol objects, operating-
  system integration, and other ecosystem hosts are separate surfaces. They are not a reason to
  retain compiler/tooling decisions outside N#, and runtime re-hosting requires its own campaign.

Definition of done:
- Every in-scope product decision is implemented in N# and is the sole production owner.
- No product path depends on legacy validation, a legacy compiler-core or emitter fallback,
  Roslyn-as-backend, `validateWithLegacyAnalysis`, `NSharpEmitValidateWithLegacyAnalysis`,
  `*DogfoodAdapter`, reflection-bound compiler kernels, or route-back callbacks into C#.
- Remaining non-N# code within scope appears in the committed
  `memory/architecture.md#non-nsharp-survivors` inventory. Each entry
  names its ecosystem boundary, the N# owner it invokes, the responsibilities it is forbidden to
  own, and a removal or re-evaluation trigger. Small size alone never qualifies a file as glue.
- Canonical compiler/tooling product assertions execute in N# (or, for editor UI integration
  only, in the editor harness). Tests are not skipped, deleted, weakened, or re-baselined merely
  to manufacture green.
- Every closeout track is complete, all native N# test projects pass, the final ownership greps
  (enforced by a committed audit script and reviewed allowlist) have no unclassified hits, and a
  fresh VS Code-enabled product gate plus required visual IDE verification is green.

Execution contract:
1. Start from current code and recent git history. Read
   `systems-language-closeout/README.md` and its live status ledger; the July 2 inventories in
   individual track files are reference material, not executable truth.
2. Execute the dependency graph and live priority queue, not filename or track-letter order.
   Never redo a stage already proved by a recorded commit. Parallelize dependency-ready,
   non-contending tracks when separate owners/worktrees are available; otherwise finish the
   active commit-sized stage before switching.
3. Preserve in-flight user work. Finish or safely hand off a coherent dirty slice before changing
   direction, stage only owned files, and never use `git add -A`.
4. Enforce an ownership ratchet: after the current in-flight coverage slice, no commit may add
   feature-specific C# compiler/tooling behavior. A normal stage lands the N# owner in the
   product path and deletes or measurably shrinks the replaced non-N# owner in the same commit.
   Mechanical host capability may be added only when the N# side owns every decision and the
   survivor inventory records the boundary.
5. Coverage gaps do not waive the ratchet. Parser, semantic, binding, and lowering decisions for
   newly supported constructs go into N#; C# may only replay already-decided plans or adapt an
   external API.
6. Revalidate the named symbols and contracts before each stage. Update the live ledger after
   every completed stage with its commit, focused evidence, remaining exit criteria, and next
   prerequisite. If a stop gate fails, record it and continue another independent eligible
   stage; do not claim completion.
7. Commit one coherent vertical ownership slice at a time with an `Evidence:` block. Use
   `./scripts/dev.sh <pattern>` for the inner loop. Run the fresh non-VS-Code product gate at the
   integration checkpoints defined by `AGENTS.md`. Any change reachable from the Language
   Server, LSP handlers, extension, or IDE experience also requires the VS Code-enabled gate,
   extension reload, computer-use verification, and screenshots.

Operating prohibitions:
- Do not add or preserve legacy compiler/tooling logic, fallback implementations, comparison
  routes, parity-only owners, or permanent transition adapters.
- Do not do unrelated CLI text/help/schema churn. Public schema changes require a separately
  approved versioned contract; an ownership move preserves bytes unless that contract says
  otherwise.
- Do not treat preparatory kernels, tests, docs, or moved adapters as completion until the N#
  owner is used by the production path and the old owner is deleted or disconnected.
- Do not recreate deleted route-with-fallback dogfood plans or history archives. Current code,
  current tests, recent commits, and the committed live ledger are authoritative.

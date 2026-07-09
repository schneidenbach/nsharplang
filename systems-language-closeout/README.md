# Systems-language closeout — execution contract

This is the sole execution package for removing non-N# compiler and compiler-tooling ownership.
The authoritative goal is [goal.md](../goal.md); the live resume point is
[STATUS.md](STATUS.md). The eight track files are deep design notebooks. Their July 2 snapshots,
line numbers, fixed ordinals, baseline counts, and completed stages are not executable truth.

Authority order:

1. current code and current tests;
2. recent git history and committed gate evidence;
3. [STATUS.md](STATUS.md), after reconciling it with 1 and 2;
4. the remaining-work and contract sections of the track notebooks;
5. historical inventories in those notebooks, only after live revalidation.

If two sources disagree, fix the live ledger before implementation. Never reimplement a stage
whose production route and evidence already exist.

## Definition of done

- N# is the sole owner of every in-scope parser, binder, analyzer, semantic, diagnostic,
  lowering, code-generation, project/reference, formatter, linter, code-intelligence, query,
  LSP, CLI, native-test-runner, and playground compiler decision.
- No product route contains legacy validation or fallback behavior, reflection-bound compiler
  kernels, Roslyn-as-backend, route-back callbacks, or permanent transition adapters.
- Remaining non-N# code is listed in one survivor inventory and is demonstrably mechanical
  ecosystem adaptation. It owns none of the decisions above and none of their canonical tests.
- All native test projects, the ownership greps, and the final fresh VS Code-enabled product gate
  are green. Required editor behavior has been visually verified in the installed extension.

`NSharpLang.Runtime` implementation is not silently absorbed into this campaign. It is a separate
runtime/performance surface and needs its own approved re-host plan. Compiler support for runtime
types and calls remains in scope here.

## How to execute

1. Read [STATUS.md](STATUS.md), inspect the working tree, and reconcile the next stage with live
   symbols and recent commits.
2. Select a dependency-ready commit unit from the active queue—not the alphabetically next file.
   A commit unit is one vertical ownership slice: N# production owner, direct behavior/parity
   proof, and same-commit deletion or measurable shrink of the replaced owner.
3. Finish a coherent dirty slice before changing direction. Preserve other owners' edits, stage
   only owned files, and never use `git add -A`.
4. Use parallel owners/worktrees for dependency-ready, non-contending tracks. One file or semantic
   contract has one writer. When only one owner is available, finish the active commit unit before
   switching tracks.
5. Record an `Evidence:` block in the commit. Update [STATUS.md](STATUS.md) immediately with the
   commit, proof, remaining exit criteria, and next dependency.
6. A failed stop gate makes that stage blocked, not complete. Record the exact blocker and proceed
   to another independent ready stage; never rationalize past missing evidence.

Broad track “stages” in the old notebooks are waves, not necessarily commits. Split them into
bounded commit units before execution. Avoid both extremes seen in recent history: one trivial
helper per commit and multi-thousand-line batches spanning unrelated constructs.

## Ownership ratchet

Replace-then-delete is binding. Preparatory kernels, tests, parity modes, docs, moved adapters,
and C# forwarding layers are not ownership progress until the N# implementation serves the
production path and the replaced owner is gone or mechanically bounded.

The in-flight range/index slice recorded in [STATUS.md](STATUS.md) is the final temporary
handwritten C# emitter expansion. After it:

- new language coverage is implemented through N# parser/semantic/lowering owners;
- C# may replay an N# plan or adapt an external API, but may not select opcodes, members, types,
  overloads, metadata owners, diagnostics, schema shapes, or fallback behavior;
- a C# host-capability addition must be data/mechanics only, paired with the N# decision owner,
  and entered in the survivor inventory;
- every emitter stage deletes more feature-specific C# than it adds.

This replaces the old Track A exception that allowed open-ended additions to
`ColumnarIlEmitter.cs`. Unit baseline restoration succeeded; continuing that exception would
grow the owner the campaign exists to delete.

## Verification contract

- Inner loop: `./scripts/dev.sh <semantically relevant pattern>` or `./scripts/dev.sh --since`.
  Do not use raw filtered `dotnet test`; the repository has a documented hang class.
- Full unit evidence is not a product gate. Run `dotnet test tests/Tests.csproj` when a wave's
  breadth warrants it, and discover totals dynamically.
- Backend/compiler/SDK/CLI integration checkpoints use a fresh
  `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` as specified by `AGENTS.md`.
- IDE reachability decides the IDE gate. Any commit changing code used by the shared Analyzer,
  `DocumentManager`, linter, formatter, code intelligence, Language Server, LSP handlers, or
  extension uses the VS Code-enabled `./scripts/test-all.sh --commit`, then
  `./scripts/reload-vscode-extension.sh`, then computer-use visual verification with screenshots.
  Expected parity does not waive this rule.
- Emission mechanics require executed value assertions and IL verification. Reflection.Emit
  claims cover every advertised receiver/shape after persisted-assembly reload, not merely one
  representative type.
- Public text and JSON ownership moves preserve exact bytes. A schema change is a separate,
  approved, versioned contract with goldens and migration policy.
- Tests and goldens are never weakened or re-baselined solely to make a port green.

## Track graph

| Track | Notebook | Remaining mission | Start condition |
|---|---|---|---|
| A | [track-a-product-path.md](track-a-product-path.md) | Close remaining product-gate and native-test grammar gaps through N# owners | Active after E0 plan foundation for lowering gaps |
| B | [track-b-kernel-binding-cli.md](track-b-kernel-binding-cli.md) | Delete residual CLI/JSON/DocQuery/nullability decisions | DocQuery ready independently; nullability caller seam coordinates with D |
| C | [track-c-syntax-frontend.md](track-c-syntax-frontend.md) | Prove/integrate syntax diagnostics, flip consumers, delete C# reporting | C2 parity stage ready; one writer on parser monolith |
| D | [track-d-semantics.md](track-d-semantics.md) | Move AST, semantic families, metadata policy, consumers, and facade | D1 ready; D0 probe complete |
| E | [track-e-backend-emitter.md](track-e-backend-emitter.md) | Establish N# plan/replay, then retire binder/resolver/pass/lowering and Cecil ownership | E0 is highest priority after the in-flight slice |
| F | [track-f-systems-analyzer.md](track-f-systems-analyzer.md) | Re-host systems policy over stable semantic identities | F1 input columns ready; F2+ waits on C/D canonical ids |
| G | [track-g-tooling-ide.md](track-g-tooling-ide.md) | Re-host linter, formatter, code intelligence, completion, LSP, and IDE front end | Typed-AST work waits on D1; independent consolidation may start with full IDE evidence |
| H | [track-h-tests-release.md](track-h-tests-release.md) | Native runner/estate, playground, integration deletions, docs, and final audit | H1 ready; H2/H3 wait on A grammar/gate; endgame waits on C/D/E/F/G |

The graph is intentionally not A→B→…→H. Long poles D and E should run concurrently where file
ownership permits. H has an early phase and an endgame phase. The exact live state and corrected
edges are in [STATUS.md](STATUS.md).

## Hard synchronization points

- The current dirty coverage slice lands before E takes exclusive ownership of the emitter.
- E0 plan/replay foundation lands before any further accept-set expansion.
- C2 direct differential parity precedes more syntax-diagnostic families or a production flip.
- D1 typed AST precedes typed linter/code-intelligence/analyzer walkers.
- C syntax authority, D semantic authority and consumer retarget, F systems ownership, and G IDE
  re-host precede H's front-end deletion.
- Canonical successor tests must execute in the gate before their C# predecessors are deleted.
- SDK repins and package/build-script changes are announced and gated from clean state; a repin
  invalidates concurrent evidence.

## Shared contracts missing from the original snapshot

- C/D own source-qualified SymbolId/TypeId contracts. Name plus line/column is not semantic
  identity.
- F consumes caller node ids and resolved declaration/function ids, including overload, local,
  and generic-instantiation identity. C# flattens already-resolved facts; it does not resolve.
- B/D share one N# NuGet/version-selection policy. Analyzer metadata loading may keep mechanical
  MetadataLoadContext/file/JSON extraction only.
- C owns the `FormatSafe` parse-error authority switch before `ParseResult.Errors` disappears.
- D's terminal stage retargets live consumers to the N# analyzer API before the C# facade is
  deleted; H cannot delete a still-live facade by assumption.
- Build.Tasks configuration/reference decisions move to N# plans; C# may materialize MSBuild
  protocol objects.
- TypeScript tests may own editor/UI adapter integration only. Canonical language and LSP
  semantics are also pinned in N#.
- The final ownership audit covers C#, `.targets`, `.props`, TypeScript, shell, and WASM host
  code. A non-C# file is not automatically glue.
- The survivor inventory is `memory/architecture.md#non-nsharp-survivors`; a committed audit
  script and reviewed allowlist enforce it at closeout.

## Using the notebooks safely

Before launching a track stage, add or refresh its live-status banner and patch invalid paths,
ordinals, prerequisites, and gate claims. In particular:

- parser kernels are now consolidated in
  `src/NSharpLang.Compiler.BootstrapServices/CompilerServices/ColumnarParserKernels.nl`;
- node kind 57 is occupied; allocate from the live ledger;
- the Track E numeric sequence contains a backward dependency (the interface pass needs the N#
  definition model), and the temporary C# whitelist route is forbidden;
- every July 2 LOC count, line anchor, test total, example count, and “intentional decline” list
  is historical until re-proved against current code and product contracts.

Do not preserve these notebooks as history after closeout. H's documentation stage deletes the
temporary ledger and replaces planning prose with the durable survivor inventory and present-
tense architecture.

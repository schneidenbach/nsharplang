# N# compiler ownership queue

The active objective is compiler ownership: preprocessing, lexing, parsing, binding, type checking,
semantic analysis, compiler diagnostics, compiler reference/metadata resolution, lowering and code
generation, with canonical compiler assertions executing in N#. Every in-scope compiler decision
must have N# as its sole production owner. Accepted migrations remain accepted.

This execution contract supersedes historical one-sub-slice-per-turn, smallest-extraction and
line-budget instructions in the numbered task files. Astra plans, reviews and integrates; bounded
implementation is delegated to Sol Max or Terra Max.

## Queue protocol

1. Read `systems-language-closeout/STATUS.md`, current source and recent evidence. Preserve in-flight
   work and finish active verification before replacing its scope.
2. Select a substantial coherent ownership area: complete methods, classes or connected method
   groups, including necessary helpers and state. Choose by production dependencies, not line count.
   When a dependency appears, first consider moving it with its callers; related numbered files may
   be addressed together when they describe that same ownership area.
3. Identify the production behavior, C# decisions and canonical assertions that will disappear.
   Implement N# replacements, route production directly, remove the replaced C# owner and migrate
   canonical assertions. Preserve semantics, diagnostics, evaluation order and meaningful failures.
4. Add no C# compiler behavior, tests, helpers, adapters, decision callbacks or fallback. A migrated
   area is complete only when N# is its sole production owner. Surviving boundaries must be
   mechanical and explicitly documented.
5. Prove capability blockers by compiling the actual proposed N# source. Implement necessary
   prerequisites in N#, grouping related proven prerequisites into a coherent seed update where
   feasible; complete required verification before publishing an SDK seed.
6. Use `./scripts/dev.sh` and targeted tests, reuse valid baseline evidence and native coverage, and
   add regressions for real gaps. Commit coherent pieces as focused evidence passes; continue until
   the whole selected area is integrated. Do not stop at planning, scaffolding, prerequisites or a
   tiny extraction. Run fresh integration gates at AGENTS.md checkpoints, retaining IDE verification
   when compiler changes affect IDE behavior, then push the verified commits.
7. Keep tasks and the overall goal open until their actual exit conditions pass. Completion requires
   solely N# compiler ownership and canonical assertions, removal of legacy validation/callbacks/
   fallback ownership, documented mechanical boundaries, and passing compiler/integration checks.

## C# test migration is required

Refactor the existing C# compiler tests into executable N# tests alongside each production migration.
Moving production code alone does not complete an area. Preserve complete fixtures, setup/state,
assertion cardinality, diagnostic codes/messages/spans, evaluation order and failure behavior.
Map every removed C# compiler assertion to its executed N# successor; similar component coverage
or a C# wrapper calling an N# helper is insufficient. Delete the replaced C# assertions and their
unused helpers. In mixed CLI/editor/SDK tests, migrate the compiler assertions and retain only the
distinct integration or separately scoped policy observations. Final task021 must audit all remaining
C# tests, including compiler assertions outside compiler-named files. Do not add new C# tests.

## Worktree lifecycle

After review and integration, retire completed agent worktrees and their local branches. Check for
active users, uncommitted/untracked work and unique commits first; preserve active and held backlog
work. Preserve unique branch history in a verified Git bundle before retiring obsolete proof branches,
and record the recovery path. Keep verification receipts and required proof inputs outside disposable
worktrees. Do not accumulate completed worktrees as a substitute for an integration record.

Cleanup on 2026-09-08 retired81 agent worktrees and77 local branches. Recoverable history and nine
uncommitted draft archives are in `/Users/spencer/nsharp-worktree-archives/2026-09-08`; the verified
`branches.bundle`, `inventory-before.json`, `cleanup-results.json` and per-draft receipts record exact
revisions and recovery inputs. Three active SDK worktrees, held query/config/signature-help work,
the main checkout and six verification evidence snapshots remain. Archived drafts are preserved work,
not newly accepted migrations. Continue retiring completed worktrees under this protocol.
On2026-09-09, two more completed SDK test worktrees/local branches were retired after integration.
Their incremental Git bundles and the exact already-integrated host/fixture draft are verified in
`/Users/spencer/nsharp-worktree-archives/2026-09-09`; its README records prerequisites and recovery.
Active follow-ups use `preprocessor-define-canonicals`, `reference-coercion-interface-identity-tests`
and the existing SDK owner worktree. Held backlog and detached verification evidence remain preserved.

CLI, LSP/editor features, runtime reimplementation, NativeAOT and other branch initiatives are
recorded in [the separate branch backlog](BRANCH-BACKLOG.md). SDK/tooling changes are in scope only
when directly necessary to build, integrate or verify compiler migration. A new metadata writer is
conditional on a demonstrated compiler-ownership dependency; the previous NativeAOT dependency
alone does not make it an additional active objective.

## Ordered tasks

- [x] [001 — External static fields and properties](001-external-static-fields-and-properties.md)
- [x] [002 — Bound identifier reads](002-bound-identifier-reads.md)
- [x] [003 — Instance fields and properties](003-instance-fields-and-properties.md)
- [x] [004 — Fixed-arity direct calls](004-fixed-arity-direct-calls.md)
- [x] [005 — Construction and array literals](005-construction-and-array-literals.md)
- [x] [006 — Primitive binary expressions](006-primitive-binary-expressions.md)
- [x] [007 — Conditional and short-circuit expressions](007-conditional-and-short-circuit-expressions.md)
- [x] [008 — Complete range/index owner deletion](008-range-index-owner-deletion.md)
- [x] [009 — External base and interface resolution](009-external-base-interface-resolution.md)
- [x] [010 — Lambda definition placement and visibility](010-lambda-definition-placement.md)
- [x] [011 — Record-with lowering for value receivers](011-record-with-value-receivers.md)
- [x] [012 — Readonly-field initialization placement](012-readonly-field-initialization.md)
- [x] [013 — Synchronous iterators](013-synchronous-iterators.md)
- [x] [014 — Async iterators](014-async-iterators.md)
- [x] [015 — Remaining emitter decisions](015-remaining-emitter-decisions.md)
- [x] [016 — Parser and syntax-diagnostic ownership](016-parser-and-syntax-diagnostics.md)
- [x] [017 — Semantic analyzer ownership](017-semantic-analyzer-ownership.md)
- [x] [018 — Complete SystemsAnalyzer ownership](018-systems-analyzer-ownership.md)
- [x] [019 — Compiler-contained tooling ownership](019-compiler-contained-tooling.md)
- [x] [020 — Native N# test-runner capabilities](020-native-test-runner-capabilities.md)
- [ ] [021 — Final compiler ownership audit](021-final-compiler-ownership-audit.md)
- [ ] [022 — One external type universe, and a NativeAOT `nlc`](022-one-type-universe-native-aot.md)
- [ ] [023 — The ECMA-335 metadata writer: the second executor over the plan rows](023-ecma335-metadata-writer.md)

The checklist preserves historical task identity and acceptance. Select active work by compiler
ownership dependencies under the contract above; broader exit criteria remain in the separate backlog.

## 021 terminal state — audit recorded, box deliberately unchecked

The original twelve-slice audit at `6fcb41f64` found that surviving C# was non-growing and classified,
but the declaration/body emitter still owned compiler decisions. The end state remains unchanged:
one N# production owner for IL generation, with any surviving host pre-existing, non-growing,
mechanical, and explicitly reviewed against its N# owner.

Current measured route and boundaries are in [STATUS §1](../systems-language-closeout/STATUS.md):

1. The complete `ColumnarIlEmitter.cs` owner (16,635 lines / 15,817 nonblank) is deleted
   in `773dbf1ff`; production routes directly to its N# replacement. The final formatted owner
   at `8ec52542b` preserves all 62 private fields and passes the exact 87 selected assertions.
   The N# formatter dependency is fixed in `6d8970fd5`. Fresh IDE-enabled integration passes
   521 C# / 7,968 N# canonicals / 36 VS Code tests; installed SDK self-host and visual formatter
   verification pass. [Acceptance](../systems-language-closeout/decodes/2026-09-08-complete-columnar-emitter-ownership.md).
   MultiFileCompiler is entirely N#-owned in `51fded82` with all ten recovery canonicals migrated.
   Final `7a3579e5` passes the fresh IDE-enabled gate, installed SDK self-host and real unsaved-buffer
   verification. [Acceptance](../systems-language-closeout/decodes/2026-09-08-complete-multifile-compiler-ownership.md).
   CompilationReferenceResolver is entirely N#-owned and its 497-line C# owner is deleted; its
   complete verification is published at `6d90129fb`. Additional workspace, command and CLI parity
   compiler canonicals are published at `698a34f30` (fresh gate:399 C#/8000 N# assertions).
   The active area is complete SDK EmitIlAssembly ownership, its proven MSBuild/Cecil prerequisites
   and canonical N# tests. Its three active worktrees remain reserved for that work.
   ColumnarProgramInputBuilder is entirely N#-owned; its accepted evidence remains valid.
   Historical checkboxes do not establish compiler-wide ownership or canonical assertion completion.
2. Analyzer.cs, SystemsAnalyzer.cs and TypeResolver.cs are deleted; their accepted N# owners and
   canonical evidence must be preserved. Task 023 writer implementation is conditional on a
   demonstrated compiler-ownership dependency. NativeAOT and broader writer ordering remain in
   the separate branch backlog and do not block independent compiler ownership work.
3. Visual IDE verification is available and has been performed, including the 2026-09-04 package
   catalog growth, completion import acceptance, NL002 quick fix, and fresh-server lifetime checks.
   It is no longer accurately described as unavailable. [Evidence](../systems-language-closeout/decodes/2026-09-04-takeover-verification.md).

The 2026-09-03 handoff snapshot was retired after its four streams landed; current ownership,
remaining source/tooling chips, verification procedure, and owner choices are carried in STATUS §1.
The 021, 022, and 023 boxes stay unchecked until their actual terminal conditions pass.

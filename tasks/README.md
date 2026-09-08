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
- [ ] [015 — Remaining emitter decisions](015-remaining-emitter-decisions.md)
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

1. After input-builder integration, `ColumnarIlEmitter.cs` remains 16,635 lines /
   15,817 nonblank and MultiFileCompiler 663/587. These complete production ownership areas
   remain in scope. ColumnarProgramInputBuilder is now entirely N#-owned; its fresh integration
   gate and SDK acceptance remain pending in STATUS. Historical checkboxes do not establish
   compiler-wide ownership or canonical assertion completion.
2. Analyzer.cs, SystemsAnalyzer.cs and TypeResolver.cs are deleted; their accepted N# owners and
   canonical evidence must be preserved. Task 023 writer implementation is conditional on a
   demonstrated compiler-ownership dependency. NativeAOT and broader writer ordering remain in
   the separate branch backlog and do not block independent compiler ownership work.
3. Visual IDE verification is available and has been performed, including the 2026-09-04 package
   catalog growth, completion import acceptance, NL002 quick fix, and fresh-server lifetime checks.
   It is no longer accurately described as unavailable. [Evidence](../systems-language-closeout/decodes/2026-09-04-takeover-verification.md).

The 2026-09-03 handoff snapshot was retired after its four streams landed; current ownership,
remaining source/tooling chips, verification procedure, and owner choices are carried in STATUS §1.
The 015, 021, 022, and 023 boxes stay unchecked until their actual terminal conditions pass.

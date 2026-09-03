# N# compiler ownership queue

This is the authoritative execution order for the systems-language closeout. The former broad
track notebooks were replaced by vertical ownership prompts on 2026-07-10.

Run one numbered task at a time. Every task embeds the complete execution contract before its
slice-specific prompt. Do not batch multiple numbered files into one implementation turn.

## Queue protocol

1. Read `systems-language-closeout/STATUS.md` and open the first unchecked task below.
2. Revalidate its named code and accept set against the current tree and recent history.
3. Complete one terminal vertical slice, including N# implementation, direct production routing,
   native tests, C# deletion, required gates, commit, repin, and documentation.
4. Mark a non-repeatable task complete only after all of its stated exit conditions pass.
5. Tasks 015–020 are iterative owner burn-downs. One goal turn completes one concrete sub-slice.
   Keep the task unchecked and record the next exact sub-slice in STATUS.md until its named owner
   is gone or is a reviewed zero-policy mechanical host.
6. Update this checklist and STATUS.md in the same commit as the completed slice. Never mark work
   complete based on preparatory code or tests alone.

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
- [x] [018 — Systems analyzer ownership](018-systems-analyzer-ownership.md)
- [x] [019 — Compiler-contained tooling ownership](019-compiler-contained-tooling.md)
- [x] [020 — Native N# test-runner capabilities](020-native-test-runner-capabilities.md)
- [ ] [021 — Final compiler ownership audit](021-final-compiler-ownership-audit.md)
- [ ] [022 — One external type universe, and a NativeAOT `nlc`](022-one-type-universe-native-aot.md)
- [ ] [023 — The ECMA-335 metadata writer: the second executor over the plan rows](023-ecma335-metadata-writer.md)
- [ ] [024 — Handoff 2026-09-03: in-flight streams and the next steps](024-handoff-2026-09-03.md) — a snapshot for the next coordinator; delete it once its streams have landed and STATUS.md §1 carries the rest

The order is deliberate. If current code proves a dependency has changed, update the queue in a
small documentation commit with concrete evidence before reordering; do not silently skip ahead.

## 021 terminal state — twelve slices run, box deliberately unchecked

Task 021's audit is complete and its findings are recorded in `memory/architecture.md`'s reviewed
allowlist. The box is **not** checked, because the task's own contract requires that every surviving
non-N# file be *"pre-existing, non-growing, mechanical, and explicitly reviewed against a canonical
N# owner."* Three of those four conjuncts hold across the whole surface — zero non-N# files were
added, zero of 381 ratchet rows exceed their epoch ceiling, and every file is classified with its
owner named. **The `mechanical` conjunct fails for one file**, and with it the task's requirement
that IL generation have exactly one N# production owner.

What remains, and where it belongs:

1. **`src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs`** — 21,519 lines carrying **144
   user-facing sentences**. Blocked on the four remaining `015` sub-tasks and on the AOT
   metadata-writer task that must replace `System.Reflection.Emit`. By design, `015` does not
   complete inside `021`; closing `015` is what unblocks this box.
2. **`Analyzer.cs`'s `MetadataLoadContext` quarantine** — 17 members plus the nested
   `NSharpMetadataResolver`, holding the file's only remaining decision (one internal exception
   message). Blocked on the AOT external-type-model task: the estate cannot yet spell
   `MetadataReader`, and 83 production `.nl` files name the `System.Reflection` object model.
3. **Visual IDE verification** — the one terminal condition no backend slice could discharge.
   Computer-use is unavailable in this environment (the grant list is empty and a grant needs an
   interactive dialog), so the VS Code integration suite plus the extension reinstall are the only
   evidence. An integration suite is not a screenshot; editor *rendering* remains unverified.

Everything else `021` named is green, including the full VS Code-enabled product gate, the ownership
audit, and the clean two-key repin.
